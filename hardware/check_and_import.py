#!/usr/bin/env python3
"""Import local-router (Freerouting SES) traces into a KiCad board; used by every board generator.

No footprint motion is allowed. KiCad 7's public SES import requires an open GUI board, so this handles just
wires/vias from the explicitly checked SES format; each board's own check then runs native KiCad DRC.
"""
import json
import re

import pcbnew as p


def sexpr(text):
    tokens = re.findall(r'"(?:\\.|[^"\\])*"|[()]|[^\s()]+', text)
    stack, root = [], []
    for token in tokens:
        if token == '(':
            node = []
            (stack[-1] if stack else root).append(node)
            stack.append(node)
        elif token == ')':
            assert stack, "Unbalanced router output"
            stack.pop()
        else:
            assert stack
            stack[-1].append(json.loads(token) if token.startswith('"') else token)
    assert not stack and len(root) == 1
    return root[0]


def children(node, tag):
    return [v for v in node if isinstance(v, list) and v and v[0] == tag]


def import_routes(folder, board):
    name = folder.name
    session = sexpr((folder / (name + '.ses')).read_text())
    routes, = children(session, 'routes')
    resolution, = children(routes, 'resolution')
    assert resolution[1] == 'um'
    scale = 1 / (1000 * float(resolution[2]))
    def position(x, y):
        return p.VECTOR2I(p.FromMM(float(x)*scale), p.FromMM(-float(y)*scale))
    # Assert no movement/mirroring/rotation has been introduced by the router.
    placement, = children(session, 'placement')
    assert children(placement, 'resolution') == [resolution]
    fps = {f.GetReference(): f for f in board.GetFootprints()}
    for component in children(placement, 'component'):
        for item in children(component, 'place'):
            fp = fps[item[1]]
            actual = position(item[2], item[3])
            assert abs(actual.x-fp.GetPosition().x) <= 10
            assert abs(actual.y-fp.GetPosition().y) <= 10
            rotation_delta = (float(item[5]) - fp.GetOrientationDegrees()) % 360
            assert item[4] == 'front' and min(rotation_delta, 360 - rotation_delta) < 1e-9
    nets = {n.GetNetname(): n for n in board.GetNetsByNetcode().values()}
    # SES contains the complete routing, including initial power neckdowns.
    for old in list(board.GetTracks()):
        board.Remove(old)
    network, = children(routes, 'network_out')
    for net in children(network, 'net'):
        code = nets[net[1]].GetNetCode()
        for item in net[2:]:
            if item[0] == 'wire':
                path, = children(item, 'path')
                assert path[1] in ['F.Cu', 'B.Cu']
                layer = p.F_Cu if path[1] == 'F.Cu' else p.B_Cu
                width = p.FromMM(float(path[2]) * scale)
                coords = path[3:]
                assert len(coords) % 2 == 0
                points = [position(x, y) for x, y in zip(coords[::2], coords[1::2])]
                for a, b in zip(points, points[1:]):
                    if a == b:
                        continue
                    t = p.PCB_TRACK(board)
                    t.SetStart(a)
                    t.SetEnd(b)
                    t.SetWidth(width)
                    t.SetLayer(layer)
                    t.SetNetCode(code)
                    board.Add(t)
            elif item[0] == 'via':
                match = re.fullmatch(r'Via\[0-1\]_(\d+):(\d+)_um', item[1])
                assert match, item
                via = p.PCB_VIA(board)
                via.SetPosition(position(item[2], item[3]))
                via.SetWidth(p.FromMM(int(match[1])/1000))
                via.SetDrill(p.FromMM(int(match[2])/1000))
                via.SetViaType(p.VIATYPE_THROUGH)
                via.SetLayerPair(p.F_Cu, p.B_Cu)
                via.SetNetCode(code)
                board.Add(via)
            else:
                raise ValueError(f'Unsupported routing item: {item[0]}')
    target = folder / (name + '.kicad_pcb')
    board.SetFileName(str(target))
    p.SaveBoard(str(target), board)
    return target
