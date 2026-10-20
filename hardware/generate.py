#!/usr/bin/env python3
"""Shared KiCad 7 helpers for the board generators: pin-level schematics, board text and outline shapes.

Imported by the O1, L1, split P1/P2 and crescent M1 build scripts; run them with KiCad's pcbnew Python module.
"""
import json
import math
import os
import uuid
from pathlib import Path

import pcbnew as p
from design import REVISION

LIB = Path(os.environ.get("KICAD_FOOTPRINT_DIR", "/usr/share/kicad/footprints"))


def mm(x):
    return p.FromMM(x)


def point(x, y):
    return p.VECTOR2I(mm(x), mm(y))


def uid(text):
    return str(uuid.uuid5(uuid.NAMESPACE_URL, "genthang-hw/" + REVISION + "/" + text))


def q(s):
    return json.dumps(str(s))


def board_text(board, text, x, y, size=1, layer=p.F_SilkS):
    t = p.PCB_TEXT(board)
    t.SetText(text)
    t.SetPosition(point(x, y))
    t.SetTextSize(point(size, size))
    t.SetTextThickness(mm(0.15))
    t.SetLayer(layer)
    board.Add(t)


def rectangle(board, x1, y1, x2, y2, layer=p.Edge_Cuts):
    for a, b in [((x1, y1), (x2, y1)), ((x2, y1), (x2, y2)),
                 ((x2, y2), (x1, y2)), ((x1, y2), (x1, y1))]:
        s = p.PCB_SHAPE()
        s.SetShape(p.SHAPE_T_SEGMENT)
        s.SetStart(point(*a))
        s.SetEnd(point(*b))
        s.SetWidth(mm(0.05 if layer == p.Edge_Cuts else 0.15))
        s.SetLayer(layer)
        board.Add(s)


def schematic(d, folder):
    """Native pin-level wiring diagram; passive symbols, NOT a functional ERC model."""
    root_id = uid(d.name + "/schematic")
    symbols, instances, wires = [], [], []
    components = [c for c in d.components if c["nets"]]
    for index, c in enumerate(components):
        ref, name = c["ref"], "GenThang:" + c["ref"]
        pins = sorted(c["nets"], key=int)
        half = math.ceil(len(pins) / 2)
        height = max(5.08, (half+1)*2.54)
        geometry, positions = [], []
        for i, number in enumerate(pins):
            right = i >= half
            row = i - half if right else i
            y = (half - 1)*1.27 - row*2.54
            x, angle = (15.24, 180) if right else (-15.24, 0)
            label = c["labels"].get(number, number)
            geometry.append(f'(pin passive line (at {x} {y} {angle}) (length 5.08) '
                            f'(name {q(label)} (effects (font (size .8 .8)))) '
                            f'(number {q(number)} (effects (font (size .8 .8)))))')
            positions.append((number, x, y, right))
        sy = f'''(symbol {q(name)} (pin_names (offset .5)) (in_bom yes) (on_board yes)
          (property "Reference" {q(ref)} (at 0 {height/2+2} 0) (effects (font (size 1 1))))
          (property "Value" {q(c['value'])} (at 0 {-height/2-2} 0) (effects (font (size 1 1))))
          (property "Footprint" {q(c['footprint'])} (at 0 0 0) (effects (font (size 1 1)) hide))
          (symbol {q(ref+'_0_1')} (rectangle (start -10.16 {height/2}) (end 10.16 {-height/2})
           (stroke (width .254) (type default)) (fill (type background))))
          (symbol {q(ref+'_1_1')} {' '.join(geometry)}))'''
        symbols.append(sy)
        x, y = 45 + (index % 9)*88.9, 45 + (index // 9)*48.26
        instance = uid(d.name + "/" + ref)
        instances.append(f'''(symbol (lib_id {q(name)}) (at {x} {y} 0) (unit 1)
          (in_bom yes) (on_board yes) (dnp no) (uuid {instance})
          (property "Reference" {q(ref)} (at {x} {y-height/2-2} 0) (effects (font (size 1 1))))
          (property "Value" {q(c['value'])} (at {x} {y+height/2+2} 0) (effects (font (size .9 .9))))
          (property "Footprint" {q(c['footprint'])} (at {x} {y} 0) (effects (font (size 1 1)) hide))
          (instances (project {q(d.name)} (path "/{root_id}" (reference {q(ref)}) (unit 1)))))''')
        for number, px, py, right in positions:
            xx, yy = x + px, y - py
            net = c["nets"][number]
            key = d.name + "/" + ref + "/" + number
            if net is None:
                wires.append(f'(no_connect (at {xx} {yy}) (uuid {uid(key+"/nc")}))')
            else:
                lx = xx + (3 if right else -24)
                wires += [f'(wire (pts (xy {xx} {yy}) (xy {lx} {yy})) '
                          f'(stroke (width 0) (type default)) (uuid {uid(key+"/wire")}))',
                          f'(label {q(net)} (at {lx} {yy} 0) '
                          f'(effects (font (size .85 .85)) (justify left bottom)) (uuid {uid(key+"/label")}))']
    content = f'''(kicad_sch (version 20230121) (generator eeschema) (uuid {root_id}) (paper "A1")
    (title_block (title {q(d.name + ' ' + REVISION + ' - DRAFT, NOT FOR FABRICATION')})
        (comment 1 "Pin-level connectivity drawing; passive symbols, not functional ERC validation"))
      (lib_symbols {' '.join(symbols)}) {' '.join(wires)} {' '.join(instances)}
      (sheet_instances (path "/" (page "1"))))\n'''
    (folder / (d.name + ".kicad_sch")).write_text(content)
