#!/usr/bin/env python3
"""Biomechanical, Giger-inspired enclosure for the two-player DB9 carrier O1 (../dual-db9-opt-pcb).

CadQuery. Run:  python3 build_case.py   -> stl/case_base.stl, stl/case_lid.stl, mockup/*.stl,
                                             dual-db9-biomech-case.step, fit-report.json

Two printed parts, both support-free in the orientation they are exported in:
  base : tray with vertebral-disc corner columns, a rib cage that continues the lid's ribs down the
         walls, vents between the ribs, two toothed 'maw' DB9 ports, the HDMI channel at the front and a
         USB-C orifice at the back. Prints floor-down.
  lid  : flat plate (printed flat face down) carrying a spine, a rib cage, vent slits between the
         ribs and two corrugated hoses. Every relief element is an upper half-solid standing on the
         plate, so the relief is a height field with no overhangs.

Case coordinates: x = board x (0..100), y = 70 - board y (DB9 edge at y = 0, USB-C end towards +y),
z up from the bed (base floor underside z = 0). Board geometry comes from build_board.py and the
Kycon K22X-E9P-N / Tang Nano 20K drawings in ../dual-db9-opt-pcb/reference.

The board slides in: drop it into the back of the cavity (BACK_GAP), push it forward so the DB9 shells
pass through the front wall, then screw it to the four bosses (M2.5 self-tapping).
"""
import json
import math
from pathlib import Path

import cadquery as cq
from OCP.BRepBuilderAPI import BRepBuilderAPI_GTransform
from OCP.gp import gp_GTrsf, gp_Mat

HERE = Path(__file__).resolve().parent

# ---- carrier O1 (../dual-db9-opt-pcb/build_board.py) -------------------------------------------
BOARD_W, BOARD_H, PCB_T = 100.0, 70.0, 1.6
BOARD_HOLES = [(5, 5), (95, 5), (5, 45), (95, 45)]          # board coords, y down
DB9_CX = [16.46 + 5.54, 72.46 + 5.54]                      # connector centre lines (pin 1 + 5.54)
SOCKET_X, SOCKET_Y = [39.84, 60.16], 8.0                    # J6 / J5 pin 1, 20 contacts at 2.54

# ---- Kycon K22X-E9P-N (drawing) ------------------------------------------------------------------
FLANGE_W, FLANGE_H, FLANGE_T = 30.81, 12.55, 1.0
SHELL_TOP, SHELL_H, NOSE = 16.92, 8.36, 6.1
SHELL_BOT = SHELL_TOP - 2 * SHELL_H * math.tan(math.radians(10))
INSERT_PITCH = 24.99
DB9_BODY_D = 10.92 + 1.5                                    # flange to back of body, generous

# ---- Tang Nano 20K on Harwin M20-7822046 sockets -------------------------------------------------
SOCKET_BODY_H = 8.5
NANO_STAND = 11.04                                          # carrier top face to Nano underside
NANO_W, NANO_T = 22.55, 1.6
NANO_USB_END = SOCKET_Y - 2.6                               # board y of the USB-C end of the Nano
NANO_HDMI_END = SOCKET_Y + 19 * 2.54 + 3.18
HDMI = dict(w=15.0, d=11.5, h=6.3)
USBC = dict(w=9.0, d=7.4, h=3.3)

# ---- case parameters (mm) ------------------------------------------------------------------------
FLOOR = 2.4
BOSS_H = 5.0                                                # floor to PCB underside (THT tails ~3.2)
WALL = 3.2
CLR_SIDE = 0.5
CLR_FRONT = 0.15                                            # DB9 flange to inner front wall face
BACK_GAP = 6.9                                              # slide-in room behind the board (> NOSE)
Z_TOP = 33.5                                                # base rim = lid underside
PORT_WALL = 1.2                                             # wall left in front of the DB9 flanges
DB9_POCKET = (35.0, 19.0, 4.0)                              # w, h, r of the plug recess at the wall
MAW_H = 2.2                                                 # height of the raised DB9/USB bezels
HDMI_NOTCH_W = 24.0
USB_HOLE = (15.0, 10.0, 3.0)
USB_CHAMFER = 2.0
LID_T = 4.0
TONGUE = (0.4, 1.8, 1.5)                                    # inner/outer offset from cavity, height
GROOVE = (0.15, 2.05, 1.8)
SCREW_PILOT_COL, SCREW_PILOT_BOSS = 2.5, 2.1               # M3 lid screws, M2.5 board screws
LID_HOLE, LID_CBORE = 3.4, 6.4

PCB_Z0 = FLOOR + BOSS_H
PCB_Z1 = PCB_Z0 + PCB_T
DB9_ZC = PCB_Z1 + FLANGE_H / 2
NANO_Z0 = PCB_Z1 + NANO_STAND
NANO_Z1 = NANO_Z0 + NANO_T
HDMI_ZC = NANO_Z1 + HDMI['h'] / 2
USB_ZC = NANO_Z1 + USBC['h'] / 2
HDMI_NOTCH_Z = HDMI_ZC - 7.6
NANO_CX = SOCKET_X[0] + 10.16

CAV = (-CLR_SIDE, BOARD_W + CLR_SIDE, -CLR_FRONT, BOARD_H + BACK_GAP)
OUT = (CAV[0] - WALL, CAV[1] + WALL, CAV[2] - WALL, CAV[3] + WALL)
COLS = [(OUT[0] - 0.8, OUT[2] - 0.85), (OUT[1] + 0.8, OUT[2] - 0.85),
        (OUT[0] - 0.8, OUT[3] + 1.4), (OUT[1] + 0.8, OUT[3] + 1.4)]
LID_PT = LID_T                                              # lid plate top (lid local z, bed = 0)
REL = LID_PT - 0.2                                          # relief solids start just inside the plate

# Mated plugs (nominal envelopes, used only by the fit check).
DB9_PLUG = (32.0, 16.0)
HDMI_PLUG = (21.0, 11.5)
USB_PLUG = (13.0, 7.5)


def cy(board_y):
    return BOARD_H - board_y


# ---- geometry helpers ----------------------------------------------------------------------------
def box(x0, x1, y0, y1, z0, z1):
    return cq.Solid.makeBox(x1 - x0, y1 - y0, z1 - z0, cq.Vector(x0, y0, z0))


def cyl(x, y, z0, z1, d):
    return cq.Solid.makeCylinder(d / 2, z1 - z0, cq.Vector(x, y, z0))


def ring(offsets, z0, z1):
    """Rectangular band around the cavity between two outward offsets."""
    a, b = offsets
    return box(CAV[0] - b, CAV[1] + b, CAV[2] - b, CAV[3] + b, z0, z1).cut(
        box(CAV[0] - a, CAV[1] + a, CAV[2] - a, CAV[3] + a, z0 - 1, z1 + 1))


def rrect(w, h, r):
    pts = [(-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2)]
    wire = cq.Wire.makePolygon([cq.Vector(x, y, 0) for x, y in pts], close=True)
    return wire.fillet2D(r, wire.Vertices()) if r > 0 else wire


def dshape(top, bot, h, r):
    pts = [(-bot / 2, -h / 2), (bot / 2, -h / 2), (top / 2, h / 2), (-top / 2, h / 2)]
    wire = cq.Wire.makePolygon([cq.Vector(x, y, 0) for x, y in pts], close=True)
    return wire.fillet2D(r, wire.Vertices())


def port_shape(w, h, r_bot, c_top):
    """Opening whose upper corners are 45-degree chamfers (prints as a short bridge), rounded below."""
    pts = [(-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2 - c_top), (w / 2 - c_top, h / 2),
           (-w / 2 + c_top, h / 2), (-w / 2, h / 2 - c_top)]
    wire = cq.Wire.makePolygon([cq.Vector(x, y, 0) for x, y in pts], close=True)
    return wire.fillet2D(r_bot, [v for v in wire.Vertices() if v.Y < -h / 2 + 1e-6])


def place(wire, origin, normal, xdir=(1, 0, 0)):
    return wire.transformShape(cq.Plane(origin=origin, xDir=xdir, normal=normal).rG)


def loft(*wires, ruled=True):
    return cq.Solid.makeLoft(list(wires), ruled)


def prism(wire, vec):
    return cq.Solid.extrudeLinear(cq.Face.makeFromWires(wire), cq.Vector(*vec))


def front_frustum(cx, cz, y0, y1, size0, size1):
    """Loft between two rounded rectangles in the planes y = y0 and y = y1."""
    return loft(place(rrect(*size0), (cx, y0, cz), (0, -1, 0)),
                place(rrect(*size1), (cx, y1, cz), (0, -1, 0)))


_DOME = []


def unit_dome():
    """Upper half of a unit sphere whose poles lie on its base (a pole at the apex tessellates badly)."""
    if not _DOME:
        sphere = cq.Solid.makeSphere(1.0, cq.Vector(0, 0, 0), cq.Vector(0, 1, 0), -90, 90, 360)
        _DOME.append(sphere.intersect(box(-2, 2, -2, 2, 0, 2)).Solids()[0])
    return _DOME[0]


def half_ellipsoid(cx, cy_, z0, a, b, c, rot=0.0):
    """Upper half-ellipsoid with its flat base at z0: a height field, so it never overhangs."""
    g = gp_GTrsf()
    g.SetVectorialPart(gp_Mat(a, 0, 0, 0, b, 0, 0, 0, c))
    shape = cq.Shape.cast(BRepBuilderAPI_GTransform(unit_dome().wrapped, g, True).Shape())
    if rot:
        shape = shape.rotate(cq.Vector(0, 0, 0), cq.Vector(0, 0, 1), rot)
    return shape.translate(cq.Vector(cx, cy_, z0))


def wave_rod(length, radius, n=160):
    """Solid of revolution about +z with radius(t) for t in [0, length]."""
    pts = [(radius(length * i / n), length * i / n) for i in range(n + 1)]
    wp = (cq.Workplane('XZ').moveTo(0, 0).lineTo(*pts[0])
          .spline(pts[1:], includeCurrent=True).lineTo(0, length).close())
    return wp.revolve(360, (0, 0, 0), (0, 1, 0)).val()


def semi_ellipse(p, t, w, h):
    """Closed half-ellipse section (half-width w, height h) standing on the plane through p, normal t."""
    t = cq.Vector(t.x, t.y, 0).normalized()
    n = cq.Vector(-t.y, t.x, 0)
    arc = cq.Edge.makeEllipse(w, h, p, t, n, 0, 180)
    return cq.Wire.assembleEdges([arc, cq.Edge.makeLine(arc.endPoint(), arc.startPoint())])


def fuse_all(base, parts):
    return base.fuse(*parts).clean() if parts else base


def cut_all(base, parts):
    return base.cut(*parts).clean() if parts else base


# ---- base tray -----------------------------------------------------------------------------------
def smoothstep(u):
    u = min(max(u, 0.0), 1.0)
    return u * u * (3 - 2 * u)


def vertebra_radius(z, neck=4.4, rim=6.3, period=Z_TOP / 5):
    """Disc profile: slow rise (underside, max slope 0.95 = under 45 degrees), short rim, quick fall."""
    a, t = rim - neck, z % period
    if t < 0.8:
        return neck
    if t < 3.8:
        return neck + a * smoothstep((t - 0.8) / 3.0)
    if t < 4.3:
        return rim
    if t < 5.9:
        return rim - a * smoothstep((t - 4.3) / 1.6)
    return neck


def column(cx, cy_):
    """Corner column of five stacked vertebral discs."""
    return wave_rod(Z_TOP, vertebra_radius, n=400).translate(cq.Vector(cx, cy_, 0))


RIB_SECS = [(0.0, 2.7, 3.4), (10.0, 2.4, 4.2), (21.0, 2.0, 3.2), (Z_TOP, 1.7, 2.3)]   # (z, half-width, depth)


def wall_rib(origin, along, shift):
    """Bony rib on a vertical wall: bulges gently (under 6 degrees) and leans by `shift` at its foot."""
    ox, oy = origin
    wires = []
    for z, w, d in RIB_SECS:
        k = 1 - z / Z_TOP
        p = cq.Vector(ox + shift[0] * k, oy + shift[1] * k, z)
        arc = cq.Edge.makeEllipse(w, d, p, cq.Vector(0, 0, 1), cq.Vector(*along), 0, 180)
        wires.append(cq.Wire.assembleEdges([arc, cq.Edge.makeLine(arc.endPoint(), arc.startPoint())]))
    return loft(*wires, ruled=False)


def pointed_slot(c, along, z0, z1, w, wall_axis, shift=(0.0, 0.0)):
    """Vent with a steep pointed top, cut through the wall along wall_axis; leans with the ribs."""
    ax, ay = along
    nx, ny = wall_axis
    pts = [(-w / 2, z0), (w / 2, z0), (w / 2, z1 - w), (0, z1), (-w / 2, z1 - w)]
    verts = []
    for s, z in pts:
        k = 1 - z / Z_TOP
        verts.append(cq.Vector(c[0] + ax * s - nx * 6 + shift[0] * k, c[1] + ay * s - ny * 6 + shift[1] * k, z))
    return prism(cq.Wire.makePolygon(verts, close=True), (nx * 12, ny * 12, 0))


def iris_notches(cx, cz, y_a, y_b, n, r0, r1, width=1.6, min_elev=40.0):
    """Radial notches through a bezel rim so it reads as a ring of teeth. Notches flatter than min_elev
    degrees from horizontal are skipped: their side walls would be steep overhangs."""
    cuts = []
    for i in range(n):
        ang = 360 * i / n + 15
        if abs(math.sin(math.radians(ang))) < math.sin(math.radians(min_elev)):
            continue
        b = box(r0, r1, min(y_a, y_b), max(y_a, y_b), -width / 2, width / 2)
        b = b.rotate(cq.Vector(0, 0, 0), cq.Vector(0, 1, 0), ang)
        cuts.append(b.translate(cq.Vector(cx, 0, cz)))
    return cuts


def build_base():
    x0, x1, y0, y1 = OUT
    body = cq.Workplane().box(x1 - x0, y1 - y0, Z_TOP, centered=False).translate((x0, y0, 0))
    body = body.edges('|Z').fillet(5.0).val()

    adds = [column(*c) for c in COLS]

    # side walls: the lid's rib cage continues down the walls, leaning back; vents between the ribs
    rib_y = [SPINE_Y0 + RIB_PATH[-1][1] + SPINE_PITCH * (k - 1) for k in range(9)]
    side_lean = (0.0, 3.5)
    for y in rib_y:
        adds.append(wall_rib((x0 + 0.3, y), (0, 1, 0), side_lean))
        adds.append(wall_rib((x1 - 0.3, y), (0, -1, 0), side_lean))
    # back wall ribs fan out from the USB-C orifice
    rib_x = [8.5 + i * 6.4 for i in range(5)]
    rib_x += [BOARD_W - x for x in rib_x]
    for x in rib_x:
        adds.append(wall_rib((x, y1 - 0.3), (1, 0, 0), (-2.5 if x < NANO_CX else 2.5, 0.0)))
    # chin: a rib between the two maws, under the HDMI channel
    adds.append(wall_rib((NANO_CX, y0 + 0.3), (-1, 0, 0), (0.0, 0.0)).intersect(
        box(-50, 150, -50, 150, 0, HDMI_NOTCH_Z)))

    # front maws: tapered bezel around each DB9 recess, with radial teeth
    pw, ph, pr = DB9_POCKET
    grow = 2 * ((CAV[2] - PORT_WALL) - (OUT[2] - MAW_H))     # 45-degree funnel growth over its depth
    bez_top = (pw + grow + 2.4, ph + grow + 2.4, pr + grow / 2 + 1.2)
    bez_base = (bez_top[0] + 2 * (MAW_H + 0.35), bez_top[1] + 2 * (MAW_H + 0.35), bez_top[2] + MAW_H + 0.35)
    clip = box(-50, 150, -50, 150, 0, Z_TOP - 0.6)
    for cx in DB9_CX:
        bz = front_frustum(cx, DB9_ZC, OUT[2] + 0.35, OUT[2] - MAW_H, bez_base, bez_top)
        bz = cut_all(bz, iris_notches(cx, DB9_ZC, OUT[2] - MAW_H - 1, OUT[2] - 0.7, 12, 11, 40, 2.4))
        adds.append(bz.intersect(clip))
    # back orifice around USB-C
    uw, uh, ur = USB_HOLE
    usb_top = (22.0, 15.0, 5.0)
    usb_base = (usb_top[0] + 2 * (MAW_H + 0.35), usb_top[1] + 2 * (MAW_H + 0.35), usb_top[2] + MAW_H + 0.35)
    ub = loft(place(rrect(*usb_base), (NANO_CX, OUT[3] - 0.35, USB_ZC), (0, 1, 0)),
              place(rrect(*usb_top), (NANO_CX, OUT[3] + MAW_H, USB_ZC), (0, 1, 0)))
    adds.append(cut_all(ub, iris_notches(NANO_CX, USB_ZC, OUT[3] + 0.6, OUT[3] + MAW_H + 1, 12, 5, 30)))
    adds.append(ring(TONGUE[:2], Z_TOP - 0.01, Z_TOP + TONGUE[2]))        # locates the lid

    shell = fuse_all(body, adds)

    cuts = [box(CAV[0], CAV[1], CAV[2], CAV[3], FLOOR, Z_TOP + 10)]
    for cx in DB9_CX:
        # plug recess: plug-sized at the 1.2 mm port wall, opening at 45 degrees through the bezel
        cuts.append(front_frustum(cx, DB9_ZC, CAV[2] - PORT_WALL, OUT[2] - MAW_H - 0.05,
                                  (pw, ph, pr), (pw + grow + 0.1, ph + grow + 0.1, pr + grow / 2 + 0.05)))
        d = dshape(SHELL_TOP + 1.0, SHELL_BOT + 1.0, SHELL_H + 1.2, 1.3)
        cuts.append(prism(place(d, (cx, CAV[2] + 1, DB9_ZC), (0, -1, 0)), (0, -8, 0)))
        for dx in (-INSERT_PITCH / 2, INSERT_PITCH / 2):      # optional #4-40 screws into the inserts
            cuts.append(cq.Solid.makeCylinder(1.65, 8, cq.Vector(cx + dx, CAV[2] + 1, DB9_ZC), cq.Vector(0, -1, 0)))
    cuts.append(box(NANO_CX - HDMI_NOTCH_W / 2, NANO_CX + HDMI_NOTCH_W / 2, OUT[2] - 10, CAV[2] + 1,
                    HDMI_NOTCH_Z, Z_TOP + 10))
    # USB-C: straight hole plus a funnel through the bezel that widens sideways and down (flat top)
    back = dict(normal=(0, 1, 0), xdir=(-1, 0, 0))
    cuts.append(prism(place(port_shape(uw, uh, ur, USB_CHAMFER), (NANO_CX, CAV[3] - 1, USB_ZC), **back), (0, 8, 0)))
    cuts.append(loft(place(port_shape(uw, uh, ur, USB_CHAMFER), (NANO_CX, OUT[3] - 0.01, USB_ZC), **back),
                     place(port_shape(uw + 4, uh + 1.7, ur + 1.5, USB_CHAMFER),
                           (NANO_CX, OUT[3] + MAW_H + 0.05, USB_ZC - 0.85), **back)))
    # vents between the ribs, leaning with them
    for a, b in zip(rib_y, rib_y[1:]):
        y = (a + b) / 2
        cuts.append(pointed_slot((OUT[0] + WALL / 2, y), (0, 1), 13.0, 27.5, 2.0, (1, 0), side_lean))
        cuts.append(pointed_slot((OUT[1] - WALL / 2, y), (0, 1), 13.0, 27.5, 2.0, (1, 0), side_lean))
    for xs in (sorted(rib_x[:5]), sorted(rib_x[5:])):
        for a, b in zip(xs, xs[1:]):
            lean = (-2.5 if a < NANO_CX else 2.5, 0.0)
            cuts.append(pointed_slot(((a + b) / 2, OUT[3] - WALL / 2), (1, 0), 13.0, 27.5, 2.0, (0, 1), lean))
    for c in COLS:
        cuts.append(cyl(c[0], c[1], Z_TOP - 15, Z_TOP + 5, SCREW_PILOT_COL))
    for fx, fy in [(14, 6), (86, 6), (14, 70), (86, 70)]:   # optional 10 mm bump-on feet
        cuts.append(cyl(fx, fy, -1, 1.0, 10.6))
    shell = cut_all(shell, cuts)

    shell = fuse_all(shell, [cyl(x, cy(y), FLOOR - 0.5, PCB_Z0, 6.0) for x, y in BOARD_HOLES])
    return cut_all(shell, [cyl(x, cy(y), PCB_Z0 - 6.0, PCB_Z0 + 1, SCREW_PILOT_BOSS) for x, y in BOARD_HOLES])


# ---- lid -----------------------------------------------------------------------------------------
SPINE_N, SPINE_Y0, SPINE_PITCH = 11, 1.5, 7.6
RIB_PATH = [(13.0, 1.2), (22.0, 3.4), (31.0, 6.2), (38.0, 8.6), (44.5, 10.6)]
RIB_SECTIONS = [(0.0, 2.0, 2.4), (0.15, 2.3, 3.6), (0.3, 2.2, 3.9), (0.5, 1.9, 3.4),
                (0.7, 1.6, 2.7), (0.85, 1.4, 2.1), (1.0, 1.3, 1.7)]     # (u, half-width, height)
HOSE_X = [4.0, 96.0]
HOSE_Y = (1.5, 77.5)


def spine_scale(i):
    return 1.22 - 0.055 * i                                 # heavy at the port end, tail at USB-C


def rib_edge(y, s, side, z=REL, sweep=1.0):
    pts = [(3.6 * s, 0.0)] + RIB_PATH
    return cq.Edge.makeSpline([cq.Vector(NANO_CX + side * dx, y + dy * sweep, z) for dx, dy in pts])


def rib(y, s, side, sweep=1.0):
    edge = rib_edge(y, s, side, sweep=sweep)
    wires = [semi_ellipse(edge.positionAt(u), edge.tangentAt(u), w, h) for u, w, h in RIB_SECTIONS]
    return loft(*wires, ruled=False)


def slit(y, side, half_w=1.0, lo=14.0, hi=35.0):
    """Vent slit following the gap between two ribs (the rib curve shifted half a pitch)."""
    edge = rib_edge(y, 1.0, side, z=0)
    pts = []
    for k in range(41):
        p = edge.positionAt(k / 40)
        if lo <= abs(p.x - NANO_CX) <= hi:
            t = edge.tangentAt(k / 40)
            pts.append((p, cq.Vector(t.x, t.y, 0).normalized()))
    left = [p + cq.Vector(-t.y, t.x, 0) * half_w for p, t in pts]
    right = [p - cq.Vector(-t.y, t.x, 0) * half_w for p, t in pts]

    def cap(p, t):                                           # half circle from the left side to the right
        n = cq.Vector(-t.y, t.x, 0)
        return [p + (n * math.cos(a) + t * math.sin(a)) * half_w for a in [math.pi * k / 8 for k in range(1, 8)]]
    outline = left + cap(*pts[-1]) + right[::-1] + cap(pts[0][0], pts[0][1] * -1)
    return prism(cq.Wire.makePolygon(outline, close=True), (0, 0, 40)).translate(cq.Vector(0, 0, -5))


def hose(x):
    length = HOSE_Y[1] - HOSE_Y[0]

    def r(t):
        if t < 3.0 or t > length - 3.0:
            return 3.9                                       # couplings at both ends
        return 2.95 + 0.45 * math.cos(2 * math.pi * (t - 3.0) / 3.4)
    rod = wave_rod(length, r, n=240).rotate(cq.Vector(0, 0, 0), cq.Vector(1, 0, 0), -90)
    return rod.translate(cq.Vector(x, HOSE_Y[0], REL))


def lid_outline(height):
    x0, x1, y0, y1 = OUT
    plate = cq.Workplane().box(x1 - x0, y1 - y0, height, centered=False).translate((x0, y0, 0))
    return fuse_all(plate.edges('|Z').fillet(5.0).val(), [cyl(cx, cy_, 0, height, 12.0) for cx, cy_ in COLS])


def fuse_staged(base, groups):
    """Fuse group by group; OCC's general fuse occasionally fails on one big mixed argument list."""
    for group in groups:
        try:
            base = fuse_all(base, group)
        except ValueError:
            for part in group:
                base = base.fuse(part).clean()
    return base


def build_lid():
    plate = lid_outline(LID_T)
    spine, ribs, other = [], [], []
    for i in range(SPINE_N):
        y, s = SPINE_Y0 + i * SPINE_PITCH, spine_scale(i)
        spine.append(half_ellipsoid(NANO_CX, y, REL, 6.2 * s, 3.1 * s, 4.6 * s))            # centrum
        spine.append(half_ellipsoid(NANO_CX, y + 0.6, REL, 1.7 * s, 3.3 * s, 9.0 * s))      # spinous ridge
        for side in (-1, 1):                                                                  # transverse lobes
            spine.append(half_ellipsoid(NANO_CX + side * 6.5 * s, y + 0.8, REL, 4.2 * s, 1.5 * s, 2.8 * s,
                                        rot=-side * 18))
        if i < SPINE_N - 1:
            spine.append(half_ellipsoid(NANO_CX, y + SPINE_PITCH / 2, REL, 4.4 * s, 1.3, 3.0 * s))   # disc
        if i <= 8:
            ribs += [rib(y, s, -1), rib(y, s, 1)]
        elif i == 9:                                         # tail ribs, swept less so they stay on the lid
            ribs += [rib(y, s, -1, 0.45), rib(y, s, 1, 0.45)]
    other += [hose(x) for x in HOSE_X]
    for cx, cy_ in COLS:                                     # knuckles over the lid screws
        other.append(half_ellipsoid(cx, cy_, REL, 5.6, 5.6, 4.0))
    other.append(half_ellipsoid(DB9_CX[0], OUT[2] + 2.2, REL, 1.8, 1.8, 2.6))                # P1: one node
    for dx in (-2.2, 2.2):                                                                     # P2: two nodes
        other.append(half_ellipsoid(DB9_CX[1] + dx, OUT[2] + 2.2, REL, 1.6, 1.6, 2.4))
    lid = fuse_staged(plate, [spine, ribs, other])

    cuts = [slit(SPINE_Y0 + i * SPINE_PITCH + SPINE_PITCH / 2, side) for i in range(8) for side in (-1, 1)]
    for cx, cy_ in COLS:
        cuts.append(cyl(cx, cy_, -1, 30, LID_HOLE))
        cuts.append(cyl(cx, cy_, LID_PT - 1.0, 30, LID_CBORE))
    cuts.append(ring(GROOVE[:2], -1, GROOVE[2]))
    lid = cut_all(lid, cuts)
    return lid.intersect(lid_outline(60))


# ---- component mock-ups (fit check and renders) --------------------------------------------------
def mockups():
    m = {'pcb': box(0, BOARD_W, 0, BOARD_H, PCB_Z0, PCB_Z1)}
    db9, plugs = [], []
    for cx in DB9_CX:
        db9.append(box(cx - FLANGE_W / 2, cx + FLANGE_W / 2, 0, FLANGE_T, PCB_Z1, PCB_Z1 + FLANGE_H))
        db9.append(box(cx - FLANGE_W / 2 + 1, cx + FLANGE_W / 2 - 1, FLANGE_T, DB9_BODY_D, PCB_Z1, PCB_Z1 + FLANGE_H))
        db9.append(prism(place(dshape(SHELL_TOP, SHELL_BOT, SHELL_H, 1.0), (cx, 0, DB9_ZC), (0, -1, 0)),
                         (0, -NOSE, 0)))
        for dx in (-INSERT_PITCH / 2, INSERT_PITCH / 2):                       # boardlocks under the board
            db9.append(box(cx + dx - 1.3, cx + dx + 1.3, cy(61.92) - 1.3, cy(61.92) + 1.3, PCB_Z0 - 3.2, PCB_Z0))
        db9.append(box(cx - 7.5, cx + 7.5, cy(62.0), cy(58.5), PCB_Z0 - 3.2, PCB_Z0))  # signal tails
        y_face = CAV[2] - PORT_WALL - 0.05
        plugs.append(box(cx - DB9_PLUG[0] / 2, cx + DB9_PLUG[0] / 2, y_face - 40, y_face,
                         DB9_ZC - DB9_PLUG[1] / 2, DB9_ZC + DB9_PLUG[1] / 2))
    m['db9'] = fuse_all(db9[0], db9[1:])
    sockets = []
    for sx in SOCKET_X:
        sy0, sy1 = cy(SOCKET_Y + 19 * 2.54 + 1.27), cy(SOCKET_Y - 1.27)
        sockets.append(box(sx - 1.27, sx + 1.27, sy0, sy1, PCB_Z1, PCB_Z1 + SOCKET_BODY_H))
        sockets.append(box(sx - 1.27, sx + 1.27, sy0, sy1, PCB_Z1 + SOCKET_BODY_H, NANO_Z0))   # Nano header body
        sockets.append(box(sx - 0.5, sx + 0.5, sy0, sy1, PCB_Z0 - 3.0, PCB_Z0))
    m['sockets'] = fuse_all(sockets[0], sockets[1:])
    ny0, ny1 = cy(NANO_HDMI_END), cy(NANO_USB_END)
    m['nano'] = fuse_all(box(NANO_CX - NANO_W / 2, NANO_CX + NANO_W / 2, ny0, ny1, NANO_Z0, NANO_Z1),
                         [box(NANO_CX - 6, NANO_CX + 6, 28, 40, NANO_Z1, NANO_Z1 + 1.4)])
    m['hdmi'] = box(NANO_CX - HDMI['w'] / 2, NANO_CX + HDMI['w'] / 2, ny0 - 0.6, ny0 - 0.6 + HDMI['d'],
                    NANO_Z1, NANO_Z1 + HDMI['h'])
    m['usbc'] = box(NANO_CX - USBC['w'] / 2, NANO_CX + USBC['w'] / 2, ny1 + 0.8 - USBC['d'], ny1 + 0.8,
                    NANO_Z1, NANO_Z1 + USBC['h'])
    plugs.append(box(NANO_CX - HDMI_PLUG[0] / 2, NANO_CX + HDMI_PLUG[0] / 2, OUT[2] - 40, ny0 - 0.65,
                     HDMI_ZC - HDMI_PLUG[1] / 2, HDMI_ZC + HDMI_PLUG[1] / 2))
    plugs.append(box(NANO_CX - USB_PLUG[0] / 2, NANO_CX + USB_PLUG[0] / 2, ny1 + 0.85, OUT[3] + 40,
                     USB_ZC - USB_PLUG[1] / 2, USB_ZC + USB_PLUG[1] / 2))
    m['plugs'] = fuse_all(plugs[0], plugs[1:])
    z_head = Z_TOP + LID_PT - 1.0                            # M3 x 12 lid screws, modelled at core diameter
    m['screws'] = fuse_all(cyl(*COLS[0], z_head - 12, z_head, 2.4),
                           [cyl(cx, cy_, z_head - 12, z_head, 2.4) for cx, cy_ in COLS[1:]])
    return m


def overlap(a, b):
    try:
        return a.intersect(b).Volume()
    except Exception:                                        # noqa: BLE001 - OCC can fail on empty results
        return 0.0


def fit_report(base, lid_placed, m):
    board = fuse_all(m['pcb'], [m['db9'], m['sockets'], m['nano'], m['hdmi'], m['usbc']])
    chk = {}
    for name in ('pcb', 'db9', 'sockets', 'nano', 'hdmi', 'usbc', 'plugs', 'screws'):
        chk[f'base_vs_{name}'] = round(overlap(base, m[name]), 4)
        chk[f'lid_vs_{name}'] = round(overlap(lid_placed, m[name]), 4)
    chk['lid_vs_base'] = round(overlap(base, lid_placed), 4)
    # slide-in: the populated board must clear the base along its whole travel...
    travel = BACK_GAP - 0.25
    for k in range(5):
        dy = travel * k / 4
        chk[f'slide_dy_{dy:.2f}'] = round(overlap(base, board.translate(cq.Vector(0, dy, 0))), 4)
    # ...and drop straight into the back of the (straight-walled) cavity.
    bb = board.translate(cq.Vector(0, travel, 0)).BoundingBox()
    drop_ok = CAV[0] < bb.xmin and bb.xmax < CAV[1] and CAV[2] < bb.ymin and bb.ymax < CAV[3]
    rep = {'units': 'mm^3 of overlap (0 = clear)', 'checks': chk, 'drop_in_clear': drop_ok}
    rep['ok'] = drop_ok and all(v < 0.01 for v in chk.values())
    return rep


def main():
    (HERE / 'stl').mkdir(exist_ok=True)
    (HERE / 'mockup').mkdir(exist_ok=True)
    print('building base...', flush=True)
    base = build_base()
    print('building lid...', flush=True)
    lid = build_lid()
    lid_placed = lid.translate(cq.Vector(0, 0, Z_TOP))
    m = mockups()

    for name, shape in (('case_base', base), ('case_lid', lid)):
        assert shape.isValid(), f'{name} is not a valid solid'
        assert len(shape.Solids()) == 1, f'{name} has {len(shape.Solids())} solids'
        cq.exporters.export(cq.Workplane().add(shape), str(HERE / 'stl' / f'{name}.stl'),
                            tolerance=0.02, angularTolerance=0.12)
    for name, shape in m.items():
        cq.exporters.export(cq.Workplane().add(shape), str(HERE / 'mockup' / f'{name}.stl'),
                            tolerance=0.05, angularTolerance=0.3)

    assy = cq.Assembly(name='dual-db9-biomech-case')
    assy.add(base, name='case_base', color=cq.Color(0.16, 0.17, 0.18))
    assy.add(lid_placed, name='case_lid', color=cq.Color(0.16, 0.17, 0.18))
    assy.save(str(HERE / 'dual-db9-biomech-case.step'))

    print('fit check...', flush=True)
    rep = fit_report(base, lid_placed, m)
    bb_b, bb_l = base.BoundingBox(), lid.BoundingBox()
    rep['parts'] = {
        'case_base': {'size_mm': [round(bb_b.xlen, 1), round(bb_b.ylen, 1), round(bb_b.zlen, 1)],
                      'volume_cm3': round(base.Volume() / 1000, 1), 'print': 'floor down, no supports'},
        'case_lid': {'size_mm': [round(bb_l.xlen, 1), round(bb_l.ylen, 1), round(bb_l.zlen, 1)],
                     'volume_cm3': round(lid.Volume() / 1000, 1), 'print': 'flat face down, no supports'},
    }
    rep['assembled_height_mm'] = round(Z_TOP + bb_l.zmax, 1)
    rep['key_z_mm'] = {k: round(v, 2) for k, v in dict(
        pcb_top=PCB_Z1, db9_centre=DB9_ZC, nano_top=NANO_Z1, hdmi_centre=HDMI_ZC,
        usbc_centre=USB_ZC, lid_underside=Z_TOP).items()}
    (HERE / 'fit-report.json').write_text(json.dumps(rep, indent=2) + '\n')
    print(json.dumps(rep, indent=2))
    if not rep['ok']:
        raise SystemExit('fit check failed')


if __name__ == '__main__':
    main()
