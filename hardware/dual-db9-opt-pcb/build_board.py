#!/usr/bin/env python3
"""Two-player Genesis carrier, reassigned-pin ("opt") breadboard wiring as a PCB.

Run through ../cad-python:  build_board.py generate | route | import | check | export
Separate source/output: never regenerates the existing boards or firmware.
Fitted parts (all through-hole): 2 female Nano sockets, 2 Kycon male DB9.
Pin assignments are read from the live canonical GenThang DB9 constraints file
when present, otherwise from the vendored snapshot used for the matching bitstream.
"""
import argparse
import csv
import hashlib
import importlib.util
import json
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET
import zipfile
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(ROOT))
import pcbnew as p
from design import Design, LEFT, RIGHT, WORKSPACE, DSUB, SOCKET_MPN, DB9_MPN
from mechanical import footprint, outline, xy, mm
from generate import schematic, board_text, rectangle

NAME = 'dual-db9-opt-pcb'
REV = 'O1'
LIBNAME = 'DualDB9Opt'
LIVE_CST = WORKSPACE / 'src/boards/nano20k_db9.cst'
REFERENCE_CST = HERE / 'reference/built-pinout.cst'
CST = LIVE_CST if LIVE_CST.exists() else REFERENCE_CST
WIDTH, HEIGHT = 100, 70
FLANGE = 10.92                       # DB9 flange sits this far forward of pin 1
SOCKET_X, SOCKET_Y = 39.84, 8        # J6; J5 is 20.32 mm to the right
LOCATIONS = {'J6': (SOCKET_X, SOCKET_Y), 'J5': (SOCKET_X + 20.32, SOCKET_Y),
             'J1': (16.46, HEIGHT - FLANGE), 'J2': (72.46, HEIGHT - FLANGE)}
HOLES = {'H1': (5, 5), 'H2': (95, 5), 'H3': (5, 45), 'H4': (95, 45)}
FORBIDDEN_GPIO = {15, 16, 17, 18, 19, 20, 25, 26, 52, 53, 54, 55, 56, 75, 76, 80, 85, 86}

# DB9 pin -> (function, RTL signal suffix); the same for both players.
FUNCTIONS = {1: ('D0', 'd[0]'), 2: ('D1', 'd[1]'), 3: ('D2', 'd[2]'), 4: ('D3', 'd[3]'),
             6: ('TL', 'd[4]'), 7: ('TH', 'th'), 9: ('TR', 'd[5]')}
POWER = {1: {5: ('3V3', 'J6', 19), 8: ('GND', 'J6', 20)},
         2: {5: ('3V3', 'J5', 16), 8: ('GND', 'J5', 15)}}
PLAYER_REF = {1: 'J1', 2: 'J2'}
PLAYER_HEADER = {1: 'J6', 2: 'J5'}


def cst_pins():
    text = CST.read_text()
    out = {}
    for player in (1, 2):
        for dbpin, (func, suffix) in FUNCTIONS.items():
            signal = ('db9_' if player == 1 else 'db9b_') + suffix
            out[player, dbpin] = (signal, int(re.search(
                r'IO_LOC\s+"' + re.escape(signal) + r'"\s+(\d+);', text)[1]))
    return out


def wire_map():
    """{(player, dbpin): (net, header ref, contact number as str)} from the CST."""
    wires = {}
    for (player, dbpin), (signal, gpio) in cst_pins().items():
        ref = PLAYER_HEADER[player]
        row = LEFT if ref == 'J6' else RIGHT
        assert row.count(gpio) == 1, f'{signal} GPIO{gpio} is not on {ref}'
        wires[player, dbpin] = (f'P{player}_{FUNCTIONS[dbpin][0]}', ref, str(row.index(gpio) + 1))
    for player, table in POWER.items():
        for dbpin, (net, ref, contact) in table.items():
            wires[player, dbpin] = (net, ref, str(contact))
    return wires


WIRES = wire_map()


def design():
    d = Design(NAME, WIDTH, HEIGHT, {}, SOCKET_X, SOCKET_Y)
    gpio = {(pl, dbpin): g for (pl, dbpin), (_, g) in cst_pins().items()}
    for c in d.components:
        if c['ref'] in ('J5', 'J6'):
            c['nets'] = {str(i): None for i in range(1, 21)}
            c['labels'] = {str(i): f'NC {i}' for i in range(1, 21)}
            for (player, dbpin), (net, ref, num) in WIRES.items():
                if ref == c['ref']:
                    c['nets'][num] = net
                    extra = f'GPIO{gpio[player, dbpin]} ' if (player, dbpin) in gpio else ''
                    c['labels'][num] = extra + net
        else:
            c['x'], c['y'] = HOLES[c['ref']]
    for player in (1, 2):
        nets = {'0': 'GND', **{str(pin): net for (pl, pin), (net, _, _) in WIRES.items() if pl == player}}
        d.add(PLAYER_REF[player], f'GENESIS_3V3_PLAYER{player}', DSUB, *LOCATIONS[PLAYER_REF[player]],
              nets, mpn=DB9_MPN)
    return d


def hole_footprint():
    f = p.FOOTPRINT(None)
    f.SetFPID(p.LIB_ID(LIBNAME, 'Mount_M2_5'))
    f.SetAttributes(p.FP_EXCLUDE_FROM_BOM | p.FP_EXCLUDE_FROM_POS_FILES)
    pad = p.PAD(f)
    pad.SetNumber('')
    pad.SetAttribute(p.PAD_ATTRIB_NPTH)
    pad.SetShape(p.PAD_SHAPE_CIRCLE)
    pad.SetSize(xy(2.7, 2.7))
    pad.SetDrillSize(xy(2.7, 2.7))
    layers = p.LSET()
    for layer in [p.F_Cu, p.B_Cu, p.F_Mask, p.B_Mask]:
        layers.AddLayer(layer)
    pad.SetLayerSet(layers)
    f.Add(pad)
    outline(f, -2.5, -2.5, 2.5, 2.5, p.F_CrtYd)
    return f


# Front-row DB9 pads (6, 7, 9) are boxed in by the back row and the grounded
# boardlock trunk. These nets are routed by hand on F.Cu: straight across from the
# Nano contact, then down the 0.87 mm gap between two back-row pads (0.285 mm to
# each, above the 0.25 mm clearance). Player 1's three runs nest without crossing.
PRE_ROUTED = [(1, 6), (1, 7), (1, 9), (2, 6)]


def pre_route_tl(b, nets):
    """Hand-route PRE_ROUTED nets (see above)."""
    for (player, dbpin) in PRE_ROUTED:
        ref = PLAYER_REF[player]
        net, header, contact = WIRES[player, dbpin]
        hx, hy = LOCATIONS[header][0], LOCATIONS[header][1] + 2.54 * (int(contact) - 1)
        px, py = LOCATIONS[ref][0] + 1.385 + 2.77 * (dbpin - 6), LOCATIONS[ref][1] + 2.84
        points = [(hx, hy), (px, hy), (px, py)]
        for a, c in zip(points, points[1:]):
            track = p.PCB_TRACK(b)
            track.SetStart(xy(*a))
            track.SetEnd(xy(*c))
            track.SetWidth(mm(.3))
            track.SetLayer(p.F_Cu)
            track.SetNet(nets[net])
            b.Add(track)


def generate():
    d = design()
    b = p.BOARD()
    b.SetCopperLayerCount(2)
    settings = b.GetDesignSettings()
    settings.m_MinClearance = mm(.25)
    settings.m_TrackMinWidth = mm(.3)
    settings.m_CopperEdgeClearance = mm(.5)
    settings.m_SolderMaskMinWidth = mm(.1)
    nc = settings.m_NetSettings.m_DefaultNetClass
    nc.SetClearance(mm(.25))
    nc.SetTrackWidth(mm(.3))
    nc.SetViaDiameter(mm(.8))
    nc.SetViaDrill(mm(.4))
    nets = {}
    for name in sorted({net for net, _, _ in WIRES.values()}):
        net = p.NETINFO_ITEM(b, name)
        b.Add(net)
        nets[name] = net
    lib = HERE / f'footprints/{LIBNAME}.pretty'
    lib.mkdir(parents=True, exist_ok=True)
    for c in d.components:
        if c['ref'].startswith('H'):
            fp = hole_footprint()
            fname = 'Mount_M2_5'
        else:
            fname = c['footprint'].split(':')[1]
            fp = footprint(fname)
        fp.SetFPID(p.LIB_ID(LIBNAME, fname))
        p.FootprintSave(str(lib), fp)
        c['footprint'] = f'{LIBNAME}:{fname}'
        fp.SetReference(c['ref'])
        fp.SetValue(c['value'])
        fp.Reference().SetVisible(False)
        fp.Value().SetVisible(False)
        fp.SetPosition(xy(c['x'], c['y']))
        for pad in fp.Pads():
            net = c['nets'].get(pad.GetNumber())
            if net:
                pad.SetNet(nets[net])
        b.Add(fp)
    pre_route_tl(b, nets)
    rectangle(b, 0, 0, WIDTH, HEIGHT)
    # Nano module envelope on documentation only; no fabricated cutout.
    cx = SOCKET_X + 10.16
    rectangle(b, cx - 11.275, 4.91, cx + 11.275, 58.95, p.Dwgs_User)
    board_text(b, 'USB-C', cx, 3, 1)
    board_text(b, 'HDMI', cx, 62, 1)
    board_text(b, 'J6', SOCKET_X - 3.3, 10, .85)
    board_text(b, 'J5', SOCKET_X + 23.6, 10, .85)
    board_text(b, 'GEN THANG', cx, 66.5, 1.2)
    board_text(b, '2 PLAYER / ' + REV, cx, 69, .8)
    board_text(b, '3.3V ONLY', 22, 12, 1.4)
    board_text(b, 'NO 5V / NO HOT PLUG', 22, 16, .9)
    board_text(b, 'GT_PAD=db9', 78, 12, .85)
    board_text(b, 'CANONICAL PIN TABLE', 78, 15.5, .8)
    board_text(b, 'PLAYER 1  J1', 22, 26, 1)
    board_text(b, 'PLAYER 2  J2', 82, 26, 1)
    for ref in ('J1', 'J2'):
        x, y = LOCATIONS[ref]
        board_text(b, '1', x, y - 2.2, .8)
    b.SetFileName(str(HERE / (NAME + '-unrouted.kicad_pcb')))
    p.SaveBoard(b.GetFileName(), b)
    assert p.ExportSpecctraDSN(b, str(HERE / (NAME + '.dsn')))
    # Signals 0.30 mm; power and ground 0.60 mm, ordinary 0.8/0.4 mm vias.
    dsn = HERE / (NAME + '.dsn')
    t = dsn.read_text()
    start = t.index('(class kicad_default')
    end = t.index('(circuit', start)
    head = t[start:end]
    for net in ['3V3', 'GND']:
        head = re.sub(r'(?<!\S)' + net + r'(?!\S)', '', head)
    t = t[:start] + head + t[end:]
    marker = '  (wiring'
    pos = t.index(marker)
    close = t.rfind('  )', 0, pos)
    power = '    (class Power 3V3 GND (circuit (use_via "Via[0-1]_800:400_um")) (rule (width 600) (clearance 250.1)))\n'
    t = t[:close] + power + t[close:]
    dsn.write_text(t)
    project = {'board': {'design_settings': {'rules': {
        'min_clearance': .25, 'min_track_width': .3, 'min_copper_edge_clearance': .5,
        'min_via_diameter': .8, 'min_through_hole_diameter': .3}}},
        'net_settings': {'classes': [
            {'name': 'Default', 'clearance': .25, 'track_width': .3, 'via_diameter': .8, 'via_drill': .4},
            {'name': 'Power', 'clearance': .25, 'track_width': .6, 'via_diameter': .8, 'via_drill': .4,
             'nets': ['3V3', 'GND']}]}}
    for stem in [NAME, NAME + '-unrouted']:
        (HERE / (stem + '.kicad_pro')).write_text(json.dumps(project, indent=2) + '\n')
    (HERE / 'fp-lib-table').write_text(
        f'(fp_lib_table (lib (name "{LIBNAME}") (type KiCad) (uri "${{KIPRJMOD}}/footprints/{LIBNAME}.pretty") '
        f'(options "") (descr "Exact part geometry")))\n')
    schematic(d, HERE)
    sch = HERE / (NAME + '.kicad_sch')
    sch.write_text(sch.read_text().replace('A1 - DRAFT, NOT FOR FABRICATION', REV + ' - 3.3V PROTOTYPE CARRIER'))
    (HERE / 'connectivity.json').write_text(json.dumps(
        {'name': NAME, 'revision': REV, 'width_mm': WIDTH, 'height_mm': HEIGHT,
         'components': d.components}, indent=2) + '\n')
    write_assembly(d)
    fit_template(b)
    shutil.copyfile(CST, HERE / 'reference/built-pinout.cst')
    print(f'Generated two-player carrier: {WIDTH}x{HEIGHT}mm, {len({n for n, _, _ in WIRES.values()})} nets, '
          '4 fitted parts, 4 mounting holes.')


def write_assembly(d):
    with (HERE / 'BOM.csv').open('w', newline='') as f:
        w = csv.writer(f)
        w.writerow(['Line', 'Quantity Per Board', 'Reference Designator', 'Manufacturer',
                    'Manufacturer Part Number', 'Description', 'Package', 'Type', 'Substitutions',
                    'Source URL'])
        w.writerow([1, 2, 'J5 J6', 'Harwin', 'M20-7822046', '1x20 female socket; 2.54mm pitch; 8.5mm body height',
                    '1x20 SIL', 'Through-hole', 'NO - written approval required',
                    'https://www.harwin.com/products/M20-7822046'])
        w.writerow([2, 2, 'J1 J2', 'Kycon', 'K22X-E9P-N',
                    'Male DE9 right angle; boardlocks; recessed 4-40 inserts; NOT NJ',
                    'DE9 right angle THT', 'Through-hole', 'NO - fit of other DB9 parts is not verified',
                    'https://www.kycon.com/Pub_Eng_Draw/K22X-E9P-N.pdf'])
    with (HERE / 'THT-placement-reference.csv').open('w', newline='') as f:
        w = csv.writer(f)
        w.writerow(['Reference', 'X_mm', 'Y_mm', 'Rotation_deg', 'Side', 'Datum', 'Note'])
        for ref, (x, y) in LOCATIONS.items():
            w.writerow([ref, x, HEIGHT - y, 0, 'Top', 'Bottom-left board corner; X right/Y up; footprint anchor pin 1',
                        'Manual THT reference, NOT SMT centroid; see assembly drawing for physical orientation'])
    with (HERE / 'net-test.csv').open('w', newline='') as f:
        w = csv.writer(f)
        w.writerow(['Player', 'DB9 Contact', 'Nano Socket', 'Nano Contact', 'Net', 'Required'])
        for (player, num), (net, ref, pin) in sorted(WIRES.items()):
            w.writerow([player, num, ref, pin, net, 'Continuity; test with Nano removed'])
        w.writerow(['1+2', 'Boardlocks of J1 and J2', 'J6', '20', 'GND', 'Continuity'])
    (HERE / 'SMT-NOT-APPLICABLE.txt').write_text(
        'All 4 fitted parts are through-hole. No SMT parts, solder-paste stencil, or SMT centroid are '
        'required. THT-placement-reference.csv is explicitly NOT an SMT centroid. Use the assembly drawing.\n')


def fit_template(b):
    s = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{WIDTH+10}mm" height="{HEIGHT+15}mm" '
         f'viewBox="-5 -5 {WIDTH+10} {HEIGHT+15}">',
         f'<rect x="-5" y="-5" width="{WIDTH+10}" height="{HEIGHT+15}" fill="white"/>',
         '<style>text{font-family:monospace;font-size:1.7px}.line{fill:none;stroke:#111;stroke-width:.15}</style>',
         f'<rect class="line" width="{WIDTH}" height="{HEIGHT}"/>']
    for fp in b.GetFootprints():
        for pad in fp.Pads():
            pos = pad.GetPosition()
            x, y, r = p.ToMM(pos.x), p.ToMM(pos.y), p.ToMM(pad.GetDrillSize().x) / 2
            s.append(f'<circle class="line" cx="{x}" cy="{y}" r="{r}"/>')
            if pad.GetNumber() == '1':
                s.append(f'<text x="{x+1}" y="{y-1}">{fp.GetReference()}.1</text>')
    cx = SOCKET_X + 10.16
    s.append(f'<rect class="line" x="{cx-11.275}" y="4.91" width="22.55" height="54.04" stroke-dasharray="1,1"/>')
    for ref in ('J1', 'J2'):
        x = LOCATIONS[ref][0] + 5.54
        s.append(f'<rect class="line" x="{x-15.405}" y="57.6" width="30.81" height="18.5"/>')
    s.extend([f'<text x="{cx}" y="2" text-anchor="middle">NANO USB-C UP</text>',
              f'<text x="{cx}" y="63" text-anchor="middle">NANO HDMI DOWN</text>',
              f'<text x="1" y="{HEIGHT+3}">{WIDTH} x {HEIGHT} mm / TOP VIEW / K22X-E9P-N ONLY / J5-J6 20.32mm APART</text>',
              f'<path class="line" d="M 7,{HEIGHT+8} h50 M7,{HEIGHT+6} v4 M57,{HEIGHT+6} v4"/>',
              f'<text x="7" y="{HEIGHT+5}">50mm ruler: PRINT 100%, NO FIT-TO-PAGE</text>', '</svg>'])
    (HERE / 'fit-1to1.svg').write_text('\n'.join(s) + '\n')


def route():
    java = Path.home() / '.local/kicad-pkg/root/usr/lib/jvm/java-21-openjdk-amd64/bin/java'
    jar = Path.home() / '.local/kicad-pkg/freerouting.jar'
    ses = HERE / (NAME + '.ses')
    ses.unlink(missing_ok=True)
    log = (HERE / 'routing.log').open('w')
    # Freerouting opens a window; it exits itself after saving the session.
    subprocess.run([str(java), '-jar', str(jar), '-de', str(HERE / (NAME + '.dsn')), '-do', str(ses),
                    '-mp', '30'], stdout=log, stderr=subprocess.STDOUT, timeout=900)
    assert ses.exists(), 'router produced no session; see routing.log'


def import_session():
    spec = importlib.util.spec_from_file_location('importer', ROOT / 'check_and_import.py')
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    b = p.LoadBoard(str(HERE / (NAME + '-unrouted.kicad_pcb')))
    mod.import_routes(HERE, b)
    # Fresh process avoids pcbnew7 SWIG invalidation on reload after removals.
    return subprocess.run([sys.executable, __file__, 'check']).returncode


def check():
    b = p.LoadBoard(str(HERE / (NAME + '.kicad_pcb')))
    manifest = json.loads((HERE / 'connectivity.json').read_text())
    components = {c['ref']: c for c in manifest['components']}
    assert set(components) == {'J1', 'J2', 'J5', 'J6', 'H1', 'H2', 'H3', 'H4'}
    fps = {f.GetReference(): f for f in b.GetFootprints()}
    assert set(fps) == set(components)
    assert b.GetCopperLayerCount() == 2
    edge = b.GetBoardEdgesBoundingBox()
    assert abs(p.ToMM(edge.GetWidth()) - WIDTH) < .1 and abs(p.ToMM(edge.GetHeight()) - HEIGHT) < .1
    expected = {}
    for ref, fp in fps.items():
        c = components[ref]
        assert abs(p.ToMM(fp.GetPosition().x) - c['x']) < .00001
        assert abs(p.ToMM(fp.GetPosition().y) - c['y']) < .00001
        assert fp.GetOrientationDegrees() == 0
        assert str(fp.GetFPID().GetLibItemName()) == c['footprint'].split(':')[1]
        for pad in fp.Pads():
            num = pad.GetNumber()
            net = c['nets'].get(num) or ''
            assert pad.GetNetname() == net
            if net:
                expected[(ref, num)] = net

    # Independent firmware contract, parsed here rather than via wire_map().
    cst = CST.read_text()
    reference = REFERENCE_CST.read_text()
    assert reference == cst, 'reference/built-pinout.cst is stale; re-run generate'
    gpio = {}
    for player, prefix in ((1, 'db9_'), (2, 'db9b_')):
        for dbpin, suffix in {1: 'd[0]', 2: 'd[1]', 3: 'd[2]', 4: 'd[3]', 6: 'd[4]', 7: 'th', 9: 'd[5]'}.items():
            signal = prefix + suffix
            pin = int(re.search(r'IO_LOC\s+"' + re.escape(signal) + r'"\s+(\d+);', cst)[1])
            port = re.search(r'IO_PORT\s+"' + re.escape(signal) + r'"\s+([^;]+)', cst)[1]
            assert 'IO_TYPE=LVCMOS33' in port
            assert ('DRIVE=8' in port) if suffix == 'th' else ('PULL_MODE=UP' in port)
            assert pin not in FORBIDDEN_GPIO
            row = LEFT if player == 1 else RIGHT
            assert pin in row, f'player {player} {signal} GPIO{pin} is on the wrong header'
            gpio[player, dbpin] = pin
    assert len(set(gpio.values())) == 14
    for (player, dbpin), pin in gpio.items():
        ref = PLAYER_HEADER[player]
        row = LEFT if ref == 'J6' else RIGHT
        contact = str(row.index(pin) + 1)
        net = components[PLAYER_REF[player]]['nets'][str(dbpin)]
        assert net.startswith(f'P{player}_')
        assert components[ref]['nets'][contact] == net
    for player in (1, 2):
        ref = PLAYER_REF[player]
        for dbpin, rail in ((5, '3V3'), (8, 'GND')):
            net, header, contact = POWER[player][dbpin]
            assert net == rail
            assert components[ref]['nets'][str(dbpin)] == rail
            assert components[header]['nets'][str(contact)] == rail
            assert {'J6': LEFT, 'J5': RIGHT}[header][contact - 1] == rail
        assert components[ref]['nets']['0'] == 'GND'
    assert components['J5']['nets']['1'] is None            # Nano 5V stays unconnected
    assert set(expected.values()) == {n for n, _, _ in WIRES.values()}
    assert len(expected) == 38    # 18 + 18 socket/DB9 contacts + 2 shared boardlock pads
    for ref, pos in HOLES.items():
        fp = fps[ref]
        pads = list(fp.Pads())
        assert len(pads) == 1 and pads[0].GetAttribute() == p.PAD_ATTRIB_NPTH
        assert abs(p.ToMM(pads[0].GetDrillSize().x) - 2.7) < 1e-6
        assert (p.ToMM(fp.GetPosition().x), p.ToMM(fp.GetPosition().y)) == pos
    for item in b.GetTracks():
        assert item.GetNetname() in expected.values()
        if type(item) is p.PCB_VIA:
            assert item.GetWidth() >= mm(.8) and item.GetDrillValue() >= mm(.4)
        else:
            assert item.GetWidth() >= mm(.6 if item.GetNetname() in {'3V3', 'GND'} else .3)
    for ref in ['J5', 'J6']:
        pads = {v.GetNumber(): v for v in fps[ref].Pads()}
        assert len(pads) == 20
        for i in range(1, 21):
            pad = pads[str(i)]
            want = next((net for net, r, n in WIRES.values() if (r, n) == (ref, str(i))), '')
            assert pad.GetNetname() == want
            assert abs(p.ToMM(pad.GetDrillSize().x) - 1.02) < 1e-6
            assert abs(p.ToMM(pad.GetPosition().y) - SOCKET_Y - (i - 1) * 2.54) < .00001
        assert len([v for v in pads.values() if v.GetNetname()]) == 9
    assert abs(p.ToMM(fps['J5'].GetPosition().x - fps['J6'].GetPosition().x) - 20.32) < 1e-6
    for ref in ('J1', 'J2'):
        fp = fps[ref]
        assert len(list(fp.Pads())) == 11
        for pad in fp.Pads():
            n = int(pad.GetNumber())
            x = p.ToMM(pad.GetPosition().x - fp.GetPosition().x)
            y = p.ToMM(pad.GetPosition().y - fp.GetPosition().y)
            if n == 0:
                assert min(abs(x - v) for v in [-6.955, 18.035]) < .00001 and abs(y - 1.395) < .00001
                drill = 3.05
            else:
                ex, ey = ((n - 1) * 2.77, 0) if n <= 5 else (1.385 + (n - 6) * 2.77, 2.84)
                assert abs(x - ex) < .00001 and abs(y - ey) < .00001
                drill = 1.09
            assert abs(p.ToMM(pad.GetDrillSize().x) - drill) < 1e-6
        assert abs(p.ToMM(fp.GetPosition().y) + FLANGE - HEIGHT) < 1e-6
    # DB9 envelopes (incl. nose) stay clear of each other, the Nano and the board sides.
    cx = SOCKET_X + 10.16
    envelopes = {ref: (LOCATIONS[ref][0] + 5.54 - 15.405, LOCATIONS[ref][0] + 5.54 + 15.405) for ref in ('J1', 'J2')}
    assert envelopes['J1'][0] > 0 and envelopes['J2'][1] < WIDTH
    assert envelopes['J1'][1] < cx - 11.275 and envelopes['J2'][0] > cx + 11.275
    netxml = HERE / 'schematic.net.xml'
    subprocess.run(['kicad-cli', 'sch', 'export', 'netlist', '--format', 'kicadxml', '-o', str(netxml),
                    str(HERE / (NAME + '.kicad_sch'))], check=True)
    actual = {}
    for net in ET.parse(netxml).getroot().findall('./nets/net'):
        for node in net.findall('node'):
            key = (node.attrib['ref'], node.attrib['pin'])
            if key in expected:
                actual[key] = net.attrib['name'].removeprefix('/')
    assert actual == expected, (actual, expected)
    report = HERE / 'drc.txt'
    assert p.WriteDRCReport(b, str(report), p.EDA_UNITS_MILLIMETRES, True)
    counts = Counter(re.findall(r'^\[([^]]+)\]', report.read_text(), re.M))
    result = {'board': NAME, 'revision': REV, 'size_mm': [WIDTH, HEIGHT], 'fitted_components': 4,
              'electrical_nets': len({n for n, _, _ in WIRES.values()}),
              'unique_connected_pad_ids': len(expected), 'drc_findings': dict(counts),
              'pin_geometry_and_firmware_contract': 'PASS', 'schematic_pcb_equivalence': 'PASS',
              'firmware_pinout': 'GT_PAD=db9 (genthang)',
              'firmware_contract_source': 'live checkout' if CST == LIVE_CST else 'vendored audited snapshot',
              'breadboard_validated': False, 'manufactured_pcb_tested': False,
              'assembly_connector': 'Kycon K22X-E9P-N',
              'fabrication_release': 'PROTOTYPE_READY'}
    (HERE / 'validation.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))
    return not counts


def export():
    assert check(), 'Resolve CAD findings before packaging'
    fab = HERE / 'fabrication'
    fab.mkdir(exist_ok=True)
    board = HERE / (NAME + '.kicad_pcb')
    subprocess.run(['kicad-cli', 'pcb', 'export', 'gerbers', '--output', str(fab) + '/', '--layers',
                    'F.Cu,B.Cu,F.Mask,B.Mask,F.Silkscreen,B.Silkscreen,Edge.Cuts', str(board)], check=True)
    subprocess.run(['kicad-cli', 'pcb', 'export', 'drill', '--output', str(fab) + '/',
                    '--excellon-separate-th', '--generate-map', '--map-format', 'pdf', str(board)], check=True)
    for filename, layers in [('board-top.svg', 'F.Cu,F.Silkscreen,Edge.Cuts'), ('board-bottom.svg', 'B.Cu,Edge.Cuts'),
                             ('assembly-top.svg', 'F.Fab,F.Silkscreen,F.Mask,Dwgs.User,Edge.Cuts')]:
        extra = ['--black-and-white'] if filename == 'assembly-top.svg' else []
        subprocess.run(['kicad-cli', 'pcb', 'export', 'svg', '--layers', layers, '--output', str(HERE / filename),
                        '--page-size-mode', '2', '--exclude-drawing-sheet', *extra, str(board)], check=True)
    subprocess.run(['kicad-cli', 'sch', 'export', 'pdf', '--output', str(HERE / 'schematic.pdf'),
                    str(HERE / (NAME + '.kicad_sch'))], check=True)
    files = [v for v in sorted(fab.iterdir()) if v.is_file()]
    required = {NAME + s for s in ['-F_Cu.gtl', '-B_Cu.gbl', '-F_Mask.gts', '-B_Mask.gbs',
                                   '-Edge_Cuts.gm1', '-PTH.drl', '-NPTH.drl']}
    assert required <= {v.name for v in files}
    with zipfile.ZipFile(HERE / 'dual-db9-opt-O1-KYCON-gerbers.zip', 'w', zipfile.ZIP_DEFLATED) as z:
        for file in files:
            z.write(file, file.name)
    oshpark_names = [
        NAME + suffix for suffix in [
            '-F_Cu.gtl', '-B_Cu.gbl', '-F_Mask.gts', '-B_Mask.gbs',
            '-F_Silkscreen.gto', '-B_Silkscreen.gbo', '-Edge_Cuts.gm1',
            '-PTH.drl', '-NPTH.drl',
        ]
    ]
    with zipfile.ZipFile(HERE / 'dual-db9-opt-O1-OSHPARK.zip', 'w', zipfile.ZIP_DEFLATED) as z:
        for name in oshpark_names:
            z.write(fab / name, name)
    release_files = {
        'ASSEMBLY.md', 'BOM.csv', 'FABRICATION.txt', 'MANUFACTURING-RELEASE.md',
        'PARTS-SOURCING.md', 'README.md', 'SMT-NOT-APPLICABLE.txt', 'TEST-STATUS.md',
        'THT-placement-reference.csv',
        'assembly-top.svg', 'board-bottom.svg', 'board-top.svg', 'build_board.py',
        'connectivity.json', 'drc.txt', 'dual-db9-opt-O1-KYCON-gerbers.zip',
        'dual-db9-opt-O1-OSHPARK.zip',
        'dual-db9-opt-pcb-unrouted.kicad_pcb', 'dual-db9-opt-pcb-unrouted.kicad_pro',
        'dual-db9-opt-pcb.kicad_pcb', 'dual-db9-opt-pcb.kicad_pro',
        'dual-db9-opt-pcb.kicad_sch', 'fit-1to1.svg', 'fp-lib-table', 'net-test.csv',
        'schematic.net.xml', 'schematic.pdf', 'test_board.py', 'validation.json',
    }
    paths = [HERE / name for name in release_files if (HERE / name).is_file()]
    for directory in (fab, HERE / 'footprints', HERE / 'reference'):
        paths.extend(v for v in directory.rglob('*') if v.is_file())
    (HERE / 'SHA256SUMS').write_text(''.join(
        hashlib.sha256(v.read_bytes()).hexdigest() + '  ' + str(v.relative_to(HERE)) + '\n' for v in sorted(paths)))
    with zipfile.ZipFile(HERE / 'dual-db9-opt-O1-KYCON-gerbers.zip') as z:
        assert z.testzip() is None
    with zipfile.ZipFile(HERE / 'dual-db9-opt-O1-OSHPARK.zip') as z:
        assert z.testzip() is None
    print('Created generic and OSH Park prototype fabrication ZIPs (KYCON only).')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['generate', 'route', 'import', 'check', 'export'])
    action = parser.parse_args().action
    if action == 'generate':
        generate()
    elif action == 'route':
        route()
    elif action == 'import':
        raise SystemExit(import_session())
    elif action == 'check':
        raise SystemExit(0 if check() else 1)
    else:
        export()
