#!/usr/bin/env python3
"""Two-player Genesis carrier with a stereo 3.5 mm line-out (revision L3).

Run through ../cad-python:  build_board.py generate | route | import | check | export | checksums
It is O1 (dual-db9-opt-pcb) plus the GenThang line-out filter, and every part is
through-hole for easy hand assembly. Pin assignments, including the two audio pins,
are read from the live canonical GenThang DB9 constraints file when present,
otherwise from the vendored snapshot used for the matching bitstream.
"""
import argparse
import csv
import hashlib
import importlib.util
import json
import os
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

NAME = 'dual-db9-lineout-pcb'
REV = 'L3'
LIBNAME = 'DualDB9LineOut'
ZIP_PCBWAY = f'dual-db9-lineout-{REV}-gerbers.zip'
ZIP_OSHPARK = f'dual-db9-lineout-{REV}-OSHPARK.zip'
LIVE_CST = ROOT.parent / 'src/boards/nano20k_db9.cst'
if not LIVE_CST.exists():
    LIVE_CST = WORKSPACE / 'genthang/src/boards/nano20k_db9.cst'
REFERENCE_CST = HERE / 'reference/built-pinout.cst'
CST = LIVE_CST if LIVE_CST.exists() else REFERENCE_CST
KICAD_FP = Path(os.environ.get('KICAD_FOOTPRINT_DIR', '/usr/share/kicad/footprints'))
WIDTH, HEIGHT = 100, 70
FLANGE = 10.92                       # DB9 flange sits this far forward of pin 1
SOCKET_X, SOCKET_Y = 25.87, 41
SOCKET_ROTATION = 90
NANO_BOUNDS = (SOCKET_X - 3.09, SOCKET_Y - 21.435, SOCKET_X + 50.95, SOCKET_Y + 1.115)
USB_CLEARANCE = (0, NANO_BOUNDS[1], NANO_BOUNDS[0], NANO_BOUNDS[3])
HDMI_CLEARANCE = (NANO_BOUNDS[2], NANO_BOUNDS[1], WIDTH, NANO_BOUNDS[3])
JACK_SLOT_WIDTH = .6
LOCATIONS = {'J6': (SOCKET_X, SOCKET_Y), 'J5': (SOCKET_X, SOCKET_Y - 20.32),
             'J1': (16.46, HEIGHT - FLANGE), 'J2': (72.46, HEIGHT - FLANGE)}
HOLES = {'H1': (5, 5), 'H2': (95, 5), 'H3': (5, 45), 'H4': (95, 45)}
# GPIOs the controller ports must never use; audio pins are checked separately.
FORBIDDEN_GPIO = {15, 16, 17, 18, 19, 20, 25, 26, 31, 52, 53, 54, 55, 56, 75, 76, 80, 85, 86}

# DB9 pin -> (function, RTL signal suffix); the same for both players.
FUNCTIONS = {1: ('D0', 'd[0]'), 2: ('D1', 'd[1]'), 3: ('D2', 'd[2]'), 4: ('D3', 'd[3]'),
             6: ('TL', 'd[4]'), 7: ('TH', 'th'), 9: ('TR', 'd[5]')}
POWER = {1: {5: ('3V3', 'J6', 19), 8: ('GND', 'J6', 20)},
         2: {5: ('3V3', 'J5', 16), 8: ('GND', 'J5', 15)}}
PLAYER_REF = {1: 'J1', 2: 'J2'}
PLAYER_HEADER = {1: 'J6', 2: 'J5'}

# Line-out: GenThang drives 1-bit audio on audio_jack_l / audio_jack_r. Per channel:
# pin -> 1k -> node (10n to GND) -> 10u (+ toward node) -> jack, 47k from jack side to GND.
AUDIO = {'L': ('audio_jack_l', 'J6'), 'R': ('audio_jack_r', 'J6')}
RES = 'R_Axial_DIN0207_L6.3mm_D2.5mm_P7.62mm_Horizontal'
DISC = 'C_Disc_D5.0mm_W2.5mm_P5.00mm'
ELEC = 'CP_Radial_D5.0mm_P2.00mm'
JACK = 'Jack_3.5mm_CUI_SJ1-3523N_Horizontal'
KICAD_LIB = {RES: 'Resistor_THT', DISC: 'Capacitor_THT', ELEC: 'Capacitor_THT', JACK: 'Connector_Audio'}
JACK_PADS = {'S': '1', 'T': '2', 'R': '3'}   # CUI SJ1-3523N datasheet numbering
# ref: (value, footprint, pin-1 x, y, rotation, {pad: net})
# Both filters sit behind the Nano, outside the side-facing cable corridors.
AUDIO_PARTS = {
    'R2': ('1k', RES, 64.0, 7.0, 0, {'1': 'AUD_R_PWM', '2': 'AUD_R_FLT'}),
    'C2': ('10nF', DISC, 64.0, 13.0, 0, {'1': 'AUD_R_FLT', '2': 'GND'}),
    'C4': ('10uF', ELEC, 77.0, 7.0, 0, {'1': 'AUD_R_FLT', '2': 'AUD_R_OUT'}),
    'R4': ('47k', RES, 76.0, 14.0, 0, {'1': 'AUD_R_OUT', '2': 'GND'}),
    'R1': ('1k', RES, 18.0, 7.0, 0, {'1': 'AUD_L_PWM', '2': 'AUD_L_FLT'}),
    'C1': ('10nF', DISC, 18.0, 13.0, 0, {'1': 'AUD_L_FLT', '2': 'GND'}),
    'C3': ('10uF', ELEC, 31.0, 7.0, 0, {'1': 'AUD_L_FLT', '2': 'AUD_L_OUT'}),
    'R3': ('47k', RES, 30.0, 14.0, 0, {'1': 'AUD_L_OUT', '2': 'GND'}),
    # Footprint origin is 4.5 mm behind the board edge; its Edge.Cuts supply the
    # rear edge between x=43.5 and 56.5, including the notch under the barrel.
    'J3': ('LINE_OUT_3.5mm', JACK, 50.0, 4.5, 180, {'1': 'GND', '2': 'AUD_L_OUT', '3': 'AUD_R_OUT'}),
}
JACK_EDGE = (50.0 - 6.5, 50.0 + 6.5)
AUDIO_MPN = {'1k': '1 kOhm 1/4 W axial, 7.62 mm (0.3 in) pitch', '47k': '47 kOhm 1/4 W axial, 7.62 mm pitch',
             '10nF': '10 nF 50 V ceramic disc, 5.0 mm pitch',
             '10uF': '10 uF 25 V radial electrolytic, 5 mm dia, 2.0 mm pitch',
             'LINE_OUT_3.5mm': 'CUI / Same Sky SJ1-3523N'}


def cst_pins():
    text = CST.read_text()
    out = {}
    for player in (1, 2):
        for dbpin, (func, suffix) in FUNCTIONS.items():
            signal = ('db9_' if player == 1 else 'db9b_') + suffix
            out[player, dbpin] = (signal, int(re.search(
                r'IO_LOC\s+"' + re.escape(signal) + r'"\s+(\d+);', text)[1]))
    return out


def audio_pins():
    """{'L'/'R': (signal, gpio, header ref, contact number as str)} from the CST."""
    text = CST.read_text()
    out = {}
    for ch, (signal, ref) in AUDIO.items():
        gpio = int(re.search(r'IO_LOC\s+"' + re.escape(signal) + r'"\s+(\d+);', text)[1])
        row = LEFT if ref == 'J6' else RIGHT
        assert row.count(gpio) == 1, f'{signal} GPIO{gpio} is not on {ref}'
        out[ch] = (signal, gpio, ref, str(row.index(gpio) + 1))
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
AUDIO_WIRES = {ch: (f'AUD_{ch}_PWM', ref, num) for ch, (_, _, ref, num) in audio_pins().items()}
ALL_NETS = sorted({n for n, _, _ in WIRES.values()} |
                  {n for part in AUDIO_PARTS.values() for n in part[5].values()})


def design():
    d = Design(NAME, WIDTH, HEIGHT, {}, SOCKET_X, SOCKET_Y)
    gpio = {(pl, dbpin): g for (pl, dbpin), (_, g) in cst_pins().items()}
    audio = audio_pins()
    for c in d.components:
        if c['ref'] in ('J5', 'J6'):
            c['x'], c['y'] = LOCATIONS[c['ref']]
            c['rotation'] = SOCKET_ROTATION
            c['nets'] = {str(i): None for i in range(1, 21)}
            c['labels'] = {str(i): f'NC {i}' for i in range(1, 21)}
            for (player, dbpin), (net, ref, num) in WIRES.items():
                if ref == c['ref']:
                    c['nets'][num] = net
                    extra = f'GPIO{gpio[player, dbpin]} ' if (player, dbpin) in gpio else ''
                    c['labels'][num] = extra + net
            for ch, (net, ref, num) in AUDIO_WIRES.items():
                if ref == c['ref']:
                    assert c['nets'][num] is None
                    c['nets'][num] = net
                    c['labels'][num] = f'GPIO{audio[ch][1]} {net}'
        else:
            c['x'], c['y'] = HOLES[c['ref']]
    for player in (1, 2):
        nets = {'0': 'GND', **{str(pin): net for (pl, pin), (net, _, _) in WIRES.items() if pl == player}}
        d.add(PLAYER_REF[player], f'GENESIS_3V3_PLAYER{player}', DSUB, *LOCATIONS[PLAYER_REF[player]],
              nets, mpn=DB9_MPN)
    for ref, (value, fname, x, y, rot, nets) in AUDIO_PARTS.items():
        labels = {'1': 'SLEEVE', '2': 'TIP_L', '3': 'RING_R'} if ref == 'J3' else \
                 {'1': '+', '2': '-'} if fname == ELEC else {}
        d.add(ref, value, f'{LIBNAME}:{fname}', x, y, dict(nets), mpn=AUDIO_MPN[value],
              rotation=rot, labels=labels)
    return d


def library_footprint(fname):
    fp = p.FootprintLoad(str(KICAD_FP / (KICAD_LIB[fname] + '.pretty')), fname)
    assert fp is not None, f'KiCad footprint {fname} not found under {KICAD_FP}'
    if fname == JACK:
        for pad in fp.Pads():
            if pad.GetNumber() in JACK_PADS:
                pad.SetNumber(JACK_PADS[pad.GetNumber()])
                drill = pad.GetDrillSize()
                pad.SetDrillSize(xy(max(p.ToMM(drill.x), JACK_SLOT_WIDTH),
                                    max(p.ToMM(drill.y), JACK_SLOT_WIDTH)))
        # The barrel (local y > 3.0) hangs past the board edge: clip silkscreen there.
        for item in list(fp.GraphicalItems()):
            if item.GetLayer() != p.F_SilkS or not isinstance(item, p.PCB_SHAPE):
                continue
            a, b = item.GetStart(), item.GetEnd()
            limit = mm(3.0)
            if a.y > limit and b.y > limit:
                fp.Remove(item)
            elif a.y > limit:
                item.SetStart(p.VECTOR2I(a.x, limit))
            elif b.y > limit:
                item.SetEnd(p.VECTOR2I(b.x, limit))
    return fp


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


# Escape front-row DB9 pads through the rear-row gaps before autorouting.
PRE_ROUTED = [(player, pin) for player in (1, 2) for pin in (6, 7, 9)]


def pre_route_tl(b, nets):
    """Hand-route PRE_ROUTED nets (see above)."""
    for (player, dbpin) in PRE_ROUTED:
        ref = PLAYER_REF[player]
        net, _, _ = WIRES[player, dbpin]
        px, py = LOCATIONS[ref][0] + 1.385 + 2.77 * (dbpin - 6), LOCATIONS[ref][1] + 2.84
        points = [(px, 55), (px, py)]
        for a, c in zip(points, points[1:]):
            track = p.PCB_TRACK(b)
            track.SetStart(xy(*a))
            track.SetEnd(xy(*c))
            track.SetWidth(mm(.3))
            track.SetLayer(p.F_Cu)
            track.SetNet(nets[net])
            b.Add(track)


def silk(b):
    """DIY silkscreen: every part's reference and value, polarity and jack wiring."""
    board_text(b, 'USB-C POWER', 11, 30, .9)
    board_text(b, '<--', 11, 33, 1)
    board_text(b, 'HDMI -->', 89, 31, .9)
    board_text(b, 'J6', SOCKET_X - 3.2, SOCKET_Y, .85)
    board_text(b, 'J5', SOCKET_X - 3.2, SOCKET_Y - 20.32, .85)
    board_text(b, 'GEN THANG', 50, 63, 1.2)
    board_text(b, '2 PLAYER + LINE OUT / ' + REV, 50, 66, .8)
    board_text(b, '3.3V ONLY / NO HOT PLUG PADS', 50, 49, .9)
    board_text(b, 'GT_PAD=db9  AUDIO L31 / R17', 50, 52, .85)
    board_text(b, 'PLAYER 1  J1', 22, 54, 1)
    board_text(b, 'PLAYER 2  J2', 82, 54, 1)
    for ref in ('J1', 'J2'):
        x, y = LOCATIONS[ref]
        board_text(b, '1', x, y - 2.2, .8)
    board_text(b, 'J3 LINE OUT', 50, 15, .85)
    board_text(b, 'POWERED SPEAKERS ONLY', 50, 18, .8)
    labels = {'R2 1k': (67.8, 3.4), 'C2 10n': (66.5, 17), 'C4 10u +': (78, 3.0), 'R4 47k': (80, 17.5),
              'R1 1k': (21.8, 3.4), 'C1 10n': (20.5, 17), 'C3 10u +': (32, 3.0), 'R3 47k': (34, 17.5)}
    for ref, (x, y) in labels.items():
        board_text(b, ref, x, y, .8)


def outline_with_jack(b):
    """Board outline; the jack footprint's own Edge.Cuts close the rear edge."""
    points = [(JACK_EDGE[1], 0), (WIDTH, 0), (WIDTH, HEIGHT), (0, HEIGHT), (0, 0), (JACK_EDGE[0], 0)]
    for a, c in zip(points, points[1:]):
        s = p.PCB_SHAPE()
        s.SetShape(p.SHAPE_T_SEGMENT)
        s.SetStart(xy(*a))
        s.SetEnd(xy(*c))
        s.SetWidth(mm(.05))
        s.SetLayer(p.Edge_Cuts)
        b.Add(s)


def generate():
    d = design()
    b = p.BOARD()
    b.SetCopperLayerCount(2)
    settings = b.GetDesignSettings()
    settings.m_MinClearance = mm(.25)
    settings.m_TrackMinWidth = mm(.3)
    settings.m_CopperEdgeClearance = mm(.5)
    settings.m_SolderMaskMinWidth = mm(.102)
    nc = settings.m_NetSettings.m_DefaultNetClass
    nc.SetClearance(mm(.25))
    nc.SetTrackWidth(mm(.3))
    nc.SetViaDiameter(mm(.8))
    nc.SetViaDrill(mm(.4))
    nets = {}
    for name in ALL_NETS:
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
            fp = library_footprint(fname) if fname in KICAD_LIB else footprint(fname)
        fp.SetFPID(p.LIB_ID(LIBNAME, fname))
        p.FootprintSave(str(lib), fp)
        c['footprint'] = f'{LIBNAME}:{fname}'
        fp.SetReference(c['ref'])
        fp.SetValue(c['value'])
        fp.Reference().SetVisible(False)
        fp.Value().SetVisible(False)
        fp.SetPosition(xy(c['x'], c['y']))
        fp.SetOrientationDegrees(c['rotation'])
        for pad in fp.Pads():
            net = c['nets'].get(pad.GetNumber())
            if net:
                pad.SetNet(nets[net])
        b.Add(fp)
    pre_route_tl(b, nets)
    outline_with_jack(b)
    # Nano module envelope on documentation only; no fabricated cutout.
    rectangle(b, *NANO_BOUNDS, p.Dwgs_User)
    rectangle(b, *USB_CLEARANCE, p.Dwgs_User)
    rectangle(b, *HDMI_CLEARANCE, p.Dwgs_User)
    silk(b)
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
    fitted = len([c for c in d.components if not c['ref'].startswith('H')])
    print(f'Generated two-player line-out carrier: {WIDTH}x{HEIGHT}mm, {len(ALL_NETS)} nets, '
          f'{fitted} fitted parts, 4 mounting holes.')


def write_assembly(d):
    with (HERE / 'BOM.csv').open('w', newline='') as f:
        w = csv.writer(f)
        w.writerow(['Line', 'Quantity Per Board', 'Reference Designator', 'Manufacturer',
                    'Manufacturer Part Number', 'Description', 'Package', 'Type', 'Substitutions',
                    'Source URL'])
        w.writerow([1, 2, 'J5 J6', 'Harwin', 'M20-7822046', '1x20 female socket; 2.54mm pitch; 8.5mm body height',
                    '1x20 SIL', 'Through-hole', 'Any 1x20 2.54 mm female header of similar height',
                    'https://www.harwin.com/products/M20-7822046'])
        w.writerow([2, 2, 'J1 J2', 'Kycon', 'K22X-E9P-N',
                    'Male DE9 right angle; boardlocks; recessed 4-40 inserts; NOT NJ',
                    'DE9 right angle THT', 'Through-hole', 'NO - fit of other DB9 parts is not verified',
                    'https://www.kycon.com/Pub_Eng_Draw/K22X-E9P-N.pdf'])
        w.writerow([3, 1, 'J3', 'CUI / Same Sky', 'SJ1-3523N', '3.5 mm stereo jack, right angle, 3 conductor',
                    'THT slotted pins', 'Through-hole', 'Must match SJ1-3523N footprint',
                    'https://www.cuidevices.com/product/resource/pdf/sj1-352xn.pdf'])
        w.writerow([4, 2, 'R1 R2', 'Any', '1 kOhm', AUDIO_MPN['1k'], 'Axial DIN0207', 'Through-hole', 'Yes', ''])
        w.writerow([5, 2, 'R3 R4', 'Any', '47 kOhm', AUDIO_MPN['47k'] + '; 22k-100k fine',
                    'Axial DIN0207', 'Through-hole', 'Yes', ''])
        w.writerow([6, 2, 'C1 C2', 'Any', '10 nF (103)', AUDIO_MPN['10nF'], 'Disc 5.0 mm pitch',
                    'Through-hole', 'Yes; film capacitor of same pitch also fine', ''])
        w.writerow([7, 2, 'C3 C4', 'Any', '10 uF', AUDIO_MPN['10uF'] + '; POLARIZED',
                    'Radial 5 mm dia 2.0 mm pitch', 'Through-hole', 'Yes; 2.5 mm pitch leads can be bent', ''])
    with (HERE / 'THT-placement-reference.csv').open('w', newline='') as f:
        w = csv.writer(f)
        w.writerow(['Reference', 'X_mm', 'Y_mm', 'Rotation_deg', 'Side', 'Datum', 'Note'])
        places = {**{ref: (x, y, SOCKET_ROTATION if ref in ('J5', 'J6') else 0)
                     for ref, (x, y) in LOCATIONS.items()},
                  **{ref: (v[2], v[3], v[4]) for ref, v in AUDIO_PARTS.items()}}
        for ref, (x, y, rot) in places.items():
            w.writerow([ref, x, HEIGHT - y, rot, 'Top', 'Bottom-left board corner; X right/Y up; footprint anchor pin 1',
                        'Manual THT reference, NOT SMT centroid; see assembly drawing for physical orientation'])
    with (HERE / 'net-test.csv').open('w', newline='') as f:
        w = csv.writer(f)
        w.writerow(['Player', 'DB9 Contact', 'Nano Socket', 'Nano Contact', 'Net', 'Required'])
        for (player, num), (net, ref, pin) in sorted(WIRES.items()):
            w.writerow([player, num, ref, pin, net, 'Continuity; test with Nano removed'])
        w.writerow(['1+2', 'Boardlocks of J1 and J2', 'J6', '20', 'GND', 'Continuity'])
        for ch, (net, ref, num) in AUDIO_WIRES.items():
            r = 'R1' if ch == 'L' else 'R2'
            w.writerow(['audio ' + ch, f'{r} pad 1', ref, num, net, 'Continuity; test with Nano removed'])
        w.writerow(['audio L', 'J3 tip (pin 2)', 'C3', '-', 'AUD_L_OUT', 'Continuity'])
        w.writerow(['audio R', 'J3 ring (pin 3)', 'C4', '-', 'AUD_R_OUT', 'Continuity'])
        w.writerow(['audio', 'J3 sleeve (pin 1)', 'J6', '20', 'GND', 'Continuity'])
    (HERE / 'SMT-NOT-APPLICABLE.txt').write_text(
        'All fitted parts are through-hole. No SMT parts, solder-paste stencil, or SMT centroid are '
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
            x, y = p.ToMM(pos.x), p.ToMM(pos.y)
            drill = pad.GetDrillSize()
            dx, dy = p.ToMM(drill.x), p.ToMM(drill.y)
            if round(pad.GetOrientationDegrees()) % 180 == 90:
                dx, dy = dy, dx
            s.append(f'<rect class="line" x="{x-dx/2}" y="{y-dy/2}" width="{dx}" height="{dy}" '
                     f'rx="{min(dx,dy)/2}"/>')
            if pad.GetNumber() == '1':
                s.append(f'<text x="{x+1}" y="{y-1}">{fp.GetReference()}.1</text>')
    for x1, y1, x2, y2 in (NANO_BOUNDS, USB_CLEARANCE, HDMI_CLEARANCE):
        s.append(f'<rect class="line" x="{x1}" y="{y1}" width="{x2-x1}" height="{y2-y1}" stroke-dasharray="1,1"/>')
    for ref in ('J1', 'J2'):
        x = LOCATIONS[ref][0] + 5.54
        s.append(f'<rect class="line" x="{x-15.405}" y="57.6" width="30.81" height="18.5"/>')
    s.extend(['<text x="2" y="28">USB-C LEFT</text>',
              '<text x="80" y="28">HDMI RIGHT</text>',
              '<text x="50" y="19" text-anchor="middle">AUDIO REAR / NANO ON FEMALE HEADERS</text>',
              f'<text x="1" y="{HEIGHT+3}">{WIDTH} x {HEIGHT} mm / TOP VIEW / K22X-E9P-N + SJ1-3523N</text>',
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
    # Pre-routed DB9 escapes can leave short dangling stubs once the router finishes them.
    subprocess.run([sys.executable, str(ROOT / 'trim_stubs.py'), str(HERE / (NAME + '.kicad_pcb'))], check=True)
    for leftover in HERE.glob('trim-*.txt'):
        leftover.unlink()
    # Fresh process avoids pcbnew7 SWIG invalidation on reload after removals.
    return subprocess.run([sys.executable, __file__, 'check']).returncode


def check_oshpark_drills(b):
    slots = 0
    for fp in b.GetFootprints():
        for pad in fp.Pads():
            drill = pad.GetDrillSize()
            dx, dy = p.ToMM(drill.x), p.ToMM(drill.y)
            assert min(dx, dy) >= .254, (fp.GetReference(), pad.GetNumber(), 'drill below OSH Park minimum')
            if dx != dy:
                slots += 1
                assert min(dx, dy) >= .508, (fp.GetReference(), pad.GetNumber(), 'slot below OSH Park minimum')
            if pad.GetAttribute() == p.PAD_ATTRIB_PTH:
                size = pad.GetSize()
                ring = min(p.ToMM(size.x) - dx, p.ToMM(size.y) - dy) / 2
                assert ring >= .127, (fp.GetReference(), pad.GetNumber(), 'annular ring below OSH Park minimum')
    assert slots == 3, f'Expected three jack slots, found {slots}'
    return slots


def bounds(fp):
    box = fp.GetCourtyard(p.F_CrtYd).BBox()
    return tuple(p.ToMM(v) for v in (box.GetLeft(), box.GetTop(), box.GetRight(), box.GetBottom()))


def overlaps(a, b):
    return a[0] < b[2] and b[0] < a[2] and a[1] < b[3] and b[1] < a[3]


def check():
    b = p.LoadBoard(str(HERE / (NAME + '.kicad_pcb')))
    manifest = json.loads((HERE / 'connectivity.json').read_text())
    components = {c['ref']: c for c in manifest['components']}
    assert set(components) == {'J1', 'J2', 'J5', 'J6', 'H1', 'H2', 'H3', 'H4', *AUDIO_PARTS}
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
        assert fp.GetOrientationDegrees() == c['rotation']
        assert str(fp.GetFPID().GetLibItemName()) == c['footprint'].split(':')[1]
        assert fp.GetAttributes() & p.FP_THROUGH_HOLE or ref.startswith('H'), f'{ref} is not through-hole'
        for pad in fp.Pads():
            num = pad.GetNumber()
            net = c['nets'].get(num) or ''
            assert pad.GetNetname() == net, (ref, num, pad.GetNetname(), net)
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
    # Line-out contract: the audio outputs are push-pull LVCMOS33 on the expected pins,
    # distinct from every pad pin, and wired through the documented filter to the jack.
    audio_gpio = {}
    for ch, (signal, header) in AUDIO.items():
        pin = int(re.search(r'IO_LOC\s+"' + re.escape(signal) + r'"\s+(\d+);', cst)[1])
        port = re.search(r'IO_PORT\s+"' + re.escape(signal) + r'"\s+([^;]+)', cst)[1]
        assert 'IO_TYPE=LVCMOS33' in port and 'PULL_MODE=NONE' in port
        row = LEFT if header == 'J6' else RIGHT
        assert pin in row and pin not in gpio.values()
        assert components[header]['nets'][str(row.index(pin) + 1)] == f'AUD_{ch}_PWM'
        audio_gpio[ch] = pin
    assert audio_gpio == {'L': 31, 'R': 17}, audio_gpio
    for ch, r, cf, ce, rb in (('L', 'R1', 'C1', 'C3', 'R3'), ('R', 'R2', 'C2', 'C4', 'R4')):
        n = lambda ref, pad: components[ref]['nets'][pad]
        assert (n(r, '1'), n(r, '2')) == (f'AUD_{ch}_PWM', f'AUD_{ch}_FLT')
        assert {n(cf, '1'), n(cf, '2')} == {f'AUD_{ch}_FLT', 'GND'}
        assert (n(ce, '1'), n(ce, '2')) == (f'AUD_{ch}_FLT', f'AUD_{ch}_OUT'), 'electrolytic + must face the node'
        assert {n(rb, '1'), n(rb, '2')} == {f'AUD_{ch}_OUT', 'GND'}
        assert components[r]['value'] == '1k' and components[cf]['value'] == '10nF'
        assert components[ce]['value'] == '10uF' and components[rb]['value'] == '47k'
    assert components['J3']['nets'] == {'1': 'GND', '2': 'AUD_L_OUT', '3': 'AUD_R_OUT'}
    jack = {pad.GetNumber(): pad for pad in fps['J3'].Pads() if pad.GetNumber()}
    assert set(jack) == {'1', '2', '3'}
    assert components['J5']['nets']['1'] is None            # Nano 5V stays unconnected
    assert set(expected.values()) == set(ALL_NETS)
    # 38 DB9/socket pads + 2 audio socket pads + 8 filter parts x 2 + 3 jack pads
    assert len(expected) == 38 + 2 + 16 + 3, len(expected)
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
            want = next((net for net, r, n in [*WIRES.values(), *AUDIO_WIRES.values()]
                         if (r, n) == (ref, str(i))), '')
            assert pad.GetNetname() == want
            assert abs(p.ToMM(pad.GetDrillSize().x) - 1.02) < 1e-6
            assert abs(p.ToMM(pad.GetPosition().x) - SOCKET_X - (i - 1) * 2.54) < .00001
            assert abs(p.ToMM(pad.GetPosition().y) - LOCATIONS[ref][1]) < .00001
        assert len([v for v in pads.values() if v.GetNetname()]) == {'J6': 11, 'J5': 9}[ref]
        assert fps[ref].GetOrientationDegrees() == 90
    assert abs(p.ToMM(fps['J6'].GetPosition().y - fps['J5'].GetPosition().y) - 20.32) < 1e-6
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
    # The side-facing Nano and cable corridors must remain clear of fitted parts.
    envelopes = {ref: (LOCATIONS[ref][0] + 5.54 - 15.405, LOCATIONS[ref][0] + 5.54 + 15.405) for ref in ('J1', 'J2')}
    assert envelopes['J1'][0] > 0 and envelopes['J2'][1] < WIDTH
    assert envelopes['J1'][1] < envelopes['J2'][0]
    for ref, fp in fps.items():
        if ref in ('J5', 'J6'):
            continue
        box = bounds(fp)
        for keepout in (NANO_BOUNDS, USB_CLEARANCE, HDMI_CLEARANCE):
            assert not overlaps(box, keepout), (ref, 'obstructs Nano or cable access', box)
        if ref in AUDIO_PARTS and ref != 'J3':
            assert 0 < box[0] < box[2] < WIDTH and 0 < box[1] < box[3] < HEIGHT, (ref, box)
    assert fps['J3'].GetOrientationDegrees() == 180
    assert abs(bounds(fps['J3'])[1] + 2.05) < .01
    for pad in fps['J3'].Pads():
        assert p.ToMM(pad.GetPosition().y) > 1.5
    slots = check_oshpark_drills(b)
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
    result = {'board': NAME, 'revision': REV, 'size_mm': [WIDTH, HEIGHT],
              'fitted_components': len(fps) - len(HOLES), 'all_through_hole': True,
              'electrical_nets': len(ALL_NETS),
              'unique_connected_pad_ids': len(expected), 'drc_findings': dict(counts),
              'pin_geometry_and_firmware_contract': 'PASS', 'line_out_contract': 'PASS',
              'schematic_pcb_equivalence': 'PASS',
              'nano_orientation': 'USB-C left / HDMI right, top-mounted female headers',
              'connector_layout': 'audio rear / DB9 front',
              'module_and_cable_clearance': 'PASS',
              'oshpark_drill_and_annular_ring_contract': 'PASS',
              'plated_slots': slots, 'minimum_slot_width_mm': JACK_SLOT_WIDTH,
              'firmware_pinout': 'GT_PAD=db9 (GPIO31 left / GPIO17 right; L3)',
              'firmware_contract_source': 'live checkout' if CST == LIVE_CST else 'vendored audited snapshot',
              'manufactured_pcb_tested': False, 'fabrication_release': 'PROTOTYPE_READY'}
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
    with zipfile.ZipFile(HERE / ZIP_PCBWAY, 'w', zipfile.ZIP_DEFLATED) as z:
        for file in files:
            z.write(file, file.name)
    oshpark_names = [NAME + suffix for suffix in [
        '-F_Cu.gtl', '-B_Cu.gbl', '-F_Mask.gts', '-B_Mask.gbs', '-F_Silkscreen.gto', '-B_Silkscreen.gbo',
        '-Edge_Cuts.gm1', '-PTH.drl', '-NPTH.drl']]
    with zipfile.ZipFile(HERE / ZIP_OSHPARK, 'w', zipfile.ZIP_DEFLATED) as z:
        for name in oshpark_names:
            z.write(fab / name, name)
    checksums()
    for name in (ZIP_PCBWAY, ZIP_OSHPARK):
        with zipfile.ZipFile(HERE / name) as z:
            assert z.testzip() is None
    print('Created PCBWay and OSH Park prototype fabrication ZIPs.')


def checksums():
    release_files = {
        'ASSEMBLY.md', 'BOM.csv', 'README.md', 'SMT-NOT-APPLICABLE.txt', 'THT-placement-reference.csv',
        'TEST-STATUS.md', 'index.html',
        'assembly-top.svg', 'board-bottom.svg', 'board-top.svg', 'build_board.py',
        'connectivity.json', 'drc.txt', ZIP_PCBWAY, ZIP_OSHPARK,
        NAME + '-unrouted.kicad_pcb', NAME + '-unrouted.kicad_pro', NAME + '.kicad_pcb', NAME + '.kicad_pro',
        NAME + '.kicad_sch', 'fit-1to1.svg', 'fp-lib-table', 'net-test.csv',
        'schematic.net.xml', 'schematic.pdf', 'validation.json',
    }
    paths = [HERE / name for name in release_files if (HERE / name).is_file()]
    for directory in (HERE / 'fabrication', HERE / 'footprints', HERE / 'reference', HERE / 'assets'):
        paths.extend(v for v in directory.rglob('*') if v.is_file())
    (HERE / 'SHA256SUMS').write_text(''.join(
        hashlib.sha256(v.read_bytes()).hexdigest() + '  ' + str(v.relative_to(HERE)) + '\n' for v in sorted(paths)))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['generate', 'route', 'import', 'check', 'export', 'checksums'])
    action = parser.parse_args().action
    if action == 'generate':
        generate()
    elif action == 'route':
        route()
    elif action == 'import':
        raise SystemExit(import_session())
    elif action == 'check':
        raise SystemExit(0 if check() else 1)
    elif action == 'checksums':
        checksums()
    else:
        export()
