#!/usr/bin/env python3

from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont
import vtk


ROOT = Path(__file__).resolve().parent
OUTPUT = ROOT / "dual-db9-opt-pcb-true-3d-mockup.png"

GREEN = (0.018, 0.24, 0.15)
GREEN_EDGE = (0.04, 0.75, 0.45)
BLACK = (0.006, 0.009, 0.012)
PLASTIC = (0.018, 0.022, 0.028)
SILVER = (0.52, 0.58, 0.62)
GOLD = (0.95, 0.57, 0.08)
WHITE = (0.74, 0.90, 0.84)
RED = (0.88, 0.09, 0.08)
BLUE = (0.08, 0.28, 0.95)


def finish(actor, color, metallic=0.0, roughness=0.45, opacity=1.0):
    prop = actor.GetProperty()
    prop.SetColor(color)
    prop.SetOpacity(opacity)
    prop.SetInterpolationToPBR()
    prop.SetMetallic(metallic)
    prop.SetRoughness(roughness)
    return actor


def cube(center, size, color, metallic=0.0, roughness=0.45, opacity=1.0):
    source = vtk.vtkCubeSource()
    source.SetCenter(*center)
    source.SetXLength(size[0])
    source.SetYLength(size[1])
    source.SetZLength(size[2])
    mapper = vtk.vtkPolyDataMapper()
    mapper.SetInputConnection(source.GetOutputPort())
    return finish(vtk.vtkActor(mapper=mapper), color, metallic, roughness, opacity)


def cylinder(center, radius, height, color, axis="z", resolution=48, metallic=0.0, roughness=0.4):
    source = vtk.vtkCylinderSource()
    source.SetRadius(radius)
    source.SetHeight(height)
    source.SetResolution(resolution)
    source.CappingOn()
    mapper = vtk.vtkPolyDataMapper()
    mapper.SetInputConnection(source.GetOutputPort())
    actor = vtk.vtkActor()
    actor.SetMapper(mapper)
    if axis == "z":
        actor.RotateX(90)
    elif axis == "x":
        actor.RotateZ(90)
    actor.SetPosition(*center)
    return finish(actor, color, metallic, roughness)


def torus(center, major, minor, color, axis="z", metallic=0.0, roughness=0.35):
    shape = vtk.vtkParametricTorus()
    shape.SetRingRadius(major)
    shape.SetCrossSectionRadius(minor)
    source = vtk.vtkParametricFunctionSource()
    source.SetParametricFunction(shape)
    source.SetUResolution(64)
    source.SetVResolution(20)
    mapper = vtk.vtkPolyDataMapper()
    mapper.SetInputConnection(source.GetOutputPort())
    actor = vtk.vtkActor()
    actor.SetMapper(mapper)
    if axis == "y":
        actor.RotateX(90)
    elif axis == "x":
        actor.RotateY(90)
    actor.SetPosition(*center)
    return finish(actor, color, metallic, roughness)


def trapezoid_prism(center, top_width, bottom_width, height, depth, color,
                    metallic=0.0, roughness=0.4):
    cx, cy, cz = center
    y0, y1 = cy - depth / 2, cy + depth / 2
    outline = [
        (-bottom_width / 2, -height / 2),
        (bottom_width / 2, -height / 2),
        (top_width / 2, height / 2),
        (-top_width / 2, height / 2),
    ]
    points = vtk.vtkPoints()
    for y in (y0, y1):
        for x, z in outline:
            points.InsertNextPoint(cx + x, y, cz + z)
    faces = vtk.vtkCellArray()
    for ids in ((0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4),
                (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)):
        face = vtk.vtkPolygon()
        face.GetPointIds().SetNumberOfIds(4)
        for index, point_id in enumerate(ids):
            face.GetPointIds().SetId(index, point_id)
        faces.InsertNextCell(face)
    poly = vtk.vtkPolyData()
    poly.SetPoints(points)
    poly.SetPolys(faces)
    normals = vtk.vtkPolyDataNormals()
    normals.SetInputData(poly)
    normals.SplittingOn()
    mapper = vtk.vtkPolyDataMapper()
    mapper.SetInputConnection(normals.GetOutputPort())
    actor = vtk.vtkActor()
    actor.SetMapper(mapper)
    return finish(actor, color, metallic, roughness)


def tube(points, radius, color, metallic=0.3, roughness=0.38):
    vtk_points = vtk.vtkPoints()
    line = vtk.vtkPolyLine()
    line.GetPointIds().SetNumberOfIds(len(points))
    for index, point in enumerate(points):
        vtk_points.InsertNextPoint(*point)
        line.GetPointIds().SetId(index, index)
    cells = vtk.vtkCellArray()
    cells.InsertNextCell(line)
    poly = vtk.vtkPolyData()
    poly.SetPoints(vtk_points)
    poly.SetLines(cells)
    source = vtk.vtkTubeFilter()
    source.SetInputData(poly)
    source.SetRadius(radius)
    source.SetNumberOfSides(14)
    source.CappingOn()
    mapper = vtk.vtkPolyDataMapper()
    mapper.SetInputConnection(source.GetOutputPort())
    actor = vtk.vtkActor()
    actor.SetMapper(mapper)
    return finish(actor, color, metallic, roughness)


def flat_text(text, position, scale=1.0, color=WHITE):
    source = vtk.vtkVectorText()
    source.SetText(text)
    mapper = vtk.vtkPolyDataMapper()
    mapper.SetInputConnection(source.GetOutputPort())
    actor = vtk.vtkActor()
    actor.SetMapper(mapper)
    actor.SetScale(scale, scale, scale)
    actor.SetPosition(*position)
    return finish(actor, color, 0.0, 0.6)


def add_mounting_hole(actors, x, y):
    actors.append(cylinder((x, y, 0), 2.3, 2.3, BLACK, "z", roughness=0.7))
    actors.append(torus((x, y, 0.88), 2.85, 0.28, SILVER, metallic=0.65, roughness=0.28))


def add_socket(actors, x):
    actors.append(cube((x, 2.86, 3.2), (3.1, 52.5, 4.7), PLASTIC, roughness=0.34))
    actors.append(cube((x, 2.86, 5.6), (2.45, 51.6, 0.35), (0.06, 0.07, 0.08), roughness=0.3))
    for index in range(20):
        y = 27.0 - index * 2.54
        actors.append(torus((x, y, 5.92), 0.70, 0.16, (1.0, 0.68, 0.10),
                            metallic=0.12, roughness=0.24))
        actors.append(cylinder((x, y, 5.88), 0.48, 0.32, BLACK, "z", resolution=32, roughness=0.65))
        actors.append(cylinder((x, y, -1.25), 0.35, 1.0, SILVER, "z", resolution=24,
                               metallic=0.75, roughness=0.25))


def add_db9(actors, x):
    # Right-angle body with a metal face projecting over the board edge.
    actors.append(cube((x, -29.0, 6.1), (34.0, 14.5, 10.5), PLASTIC, roughness=0.3))
    actors.append(cube((x, -35.1, 8.0), (38.0, 2.1, 15.5), (0.72, 0.78, 0.81),
                       metallic=0.28, roughness=0.25))
    actors.append(trapezoid_prism((x, -36.25, 8.0), 25.4, 30.0, 10.7, 0.36,
                                  (0.08, 0.10, 0.12), metallic=0.15, roughness=0.25))
    actors.append(trapezoid_prism((x, -36.48, 8.0), 22.7, 27.0, 8.7, 0.28,
                                  (0.008, 0.011, 0.015), roughness=0.72))

    # Two mounting ears and recessed screw heads.
    for sx in (-15.8, 15.8):
        actors.append(torus((x + sx, -36.72, 8.0), 1.85, 0.42, SILVER, "y",
                            metallic=0.9, roughness=0.2))
        actors.append(cylinder((x + sx, -36.76, 8.0), 1.25, 0.42, (0.10, 0.12, 0.13),
                               "y", resolution=40, metallic=0.35, roughness=0.28))
        actors.append(cube((x + sx, -37.0, 8.0), (1.9, 0.18, 0.25), (0.45, 0.49, 0.51),
                           metallic=0.8, roughness=0.2))

    # Female DB9 contact cavities: five above, four below.
    for count, z, spacing in ((5, 9.7, 4.25), (4, 6.3, 4.25)):
        start = -(count - 1) * spacing / 2
        for index in range(count):
            px = x + start + index * spacing
            actors.append(torus((px, -36.76, z), 0.91, 0.21, (1.0, 0.70, 0.09), "y",
                                metallic=0.08, roughness=0.22))
            actors.append(cylinder((px, -36.88, z), 0.58, 0.45, BLACK, "y",
                                   resolution=32, roughness=0.7))

    # Board locks and through-hole tails visible from below.
    for sx in (-14.2, 14.2):
        actors.append(cylinder((x + sx, -24.2, -1.15), 1.2, 1.35, SILVER, "z",
                               metallic=0.82, roughness=0.24))
    for row, py in enumerate((-23.7, -20.9)):
        count = 5 if row == 0 else 4
        for index in range(count):
            px = x + (index - (count - 1) / 2) * 2.77
            actors.append(cylinder((px, py, -1.1), 0.32, 1.0, SILVER, "z", resolution=20,
                                   metallic=0.8, roughness=0.25))


def build_scene():
    actors = []
    # Real 1.6 mm FR-4 body, with a thin brighter solder-mask top.
    actors.append(cube((0, 0, 0), (100, 70, 1.6), GREEN, roughness=0.33))
    actors.append(cube((0, 0, 0.83), (99.5, 69.5, 0.08), (0.02, 0.33, 0.20),
                       roughness=0.28))
    actors.append(cube((0, 0, -0.83), (99.5, 69.5, 0.08), (0.015, 0.25, 0.17),
                       roughness=0.3))

    for x, y in ((-45, 30), (45, 30), (-45, -10), (45, -10)):
        add_mounting_hole(actors, x, y)

    # Routed top copper paths are raised, and bottom paths sit beneath the FR-4.
    top_routes = [
        [(-10.16, 27, 0.92), (-10.16, 8, 0.92), (-30, -2, 0.92), (-31, -23, 0.92)],
        [(-10.16, 18, 0.92), (-19, 8, 0.92), (-22, -24, 0.92)],
        [(10.16, 21, 0.92), (10.16, 7, 0.92), (26, -4, 0.92), (27, -23, 0.92)],
        [(10.16, 11, 0.92), (20, 4, 0.92), (18, -24, 0.92)],
    ]
    bottom_routes = [
        [(-10.16, 24, -0.92), (-39, 2, -0.92), (-39, -22, -0.92)],
        [(-10.16, 16, -0.92), (-31, -1, -0.92), (-31, -22, -0.92)],
        [(10.16, 23, -0.92), (37, 4, -0.92), (37, -22, -0.92)],
        [(10.16, 13, -0.92), (29, -3, -0.92), (29, -22, -0.92)],
        [(-10.16, -3, -0.92), (0, -10, -0.92), (10.16, -3, -0.92)],
    ]
    for route in top_routes:
        actors.append(tube(route, 0.19, RED, metallic=0.65, roughness=0.3))
    for route in bottom_routes:
        actors.append(tube(route, 0.19, BLUE, metallic=0.55, roughness=0.32))

    add_socket(actors, -10.16)
    add_socket(actors, 10.16)
    add_db9(actors, -28.0)
    add_db9(actors, 28.0)

    actors.append(flat_text("DUAL DB9 OPT", (-46, 24, 0.92), 2.7))
    actors.append(flat_text("PLAYER 1", (-42, -15, 0.92), 1.55))
    actors.append(flat_text("PLAYER 2", (24, -15, 0.92), 1.55))
    actors.append(flat_text("GENTHANG  O1", (-46, 20, 0.92), 1.0, (0.45, 0.72, 0.63)))
    return actors


def configure_lights(renderer, camera_position):
    head = vtk.vtkLight()
    head.SetLightTypeToHeadlight()
    head.SetColor(0.92, 0.97, 1.0)
    head.SetIntensity(0.72)
    renderer.AddLight(head)

    key = vtk.vtkLight()
    key.SetPosition(camera_position[0] * 0.65, camera_position[1] * 0.65,
                    camera_position[2] * 0.82)
    key.SetFocalPoint(0, 0, 0)
    key.SetColor(0.72, 0.92, 1.0)
    key.SetIntensity(1.15)
    renderer.AddLight(key)

    rim = vtk.vtkLight()
    rim.SetPosition(-90, 75, 65 if camera_position[2] >= 0 else -65)
    rim.SetFocalPoint(0, 0, 4)
    rim.SetColor(0.1, 1.0, 0.68)
    rim.SetIntensity(0.72)
    renderer.AddLight(rim)

    warm = vtk.vtkLight()
    warm.SetPosition(70, -80, 35)
    warm.SetFocalPoint(0, 0, 3)
    warm.SetColor(1.0, 0.48, 0.18)
    warm.SetIntensity(0.36)
    renderer.AddLight(warm)


def render_view(filename, size, camera_position, focal_point, view_up, parallel=False,
                parallel_scale=62, floor=False):
    renderer = vtk.vtkRenderer()
    renderer.SetBackground(0.012, 0.025, 0.038)
    renderer.SetBackground2(0.002, 0.006, 0.011)
    renderer.GradientBackgroundOn()
    renderer.SetUseImageBasedLighting(False)

    for actor in build_scene():
        renderer.AddActor(actor)

    if floor:
        floor_actor = cube((0, 0, -4.8), (240, 220, 1.0), (0.006, 0.011, 0.016),
                           roughness=0.82)
        renderer.AddActor(floor_actor)

    camera = renderer.GetActiveCamera()
    camera.SetPosition(*camera_position)
    camera.SetFocalPoint(*focal_point)
    camera.SetViewUp(*view_up)
    camera.SetViewAngle(38)
    if parallel:
        camera.ParallelProjectionOn()
        camera.SetParallelScale(parallel_scale)

    configure_lights(renderer, camera_position)
    renderer.UseFXAAOn()

    window = vtk.vtkRenderWindow()
    window.SetOffScreenRendering(1)
    window.SetAlphaBitPlanes(1)
    window.SetMultiSamples(8)
    window.SetSize(*size)
    window.AddRenderer(renderer)
    window.Render()

    capture = vtk.vtkWindowToImageFilter()
    capture.SetInput(window)
    capture.SetScale(1)
    capture.SetInputBufferTypeToRGBA()
    capture.ReadFrontBufferOff()
    capture.Update()

    writer = vtk.vtkPNGWriter()
    writer.SetFileName(str(filename))
    writer.SetInputConnection(capture.GetOutputPort())
    writer.Write()
    window.Finalize()


def font(size, bold=False):
    candidates = [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" if bold
        else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/liberation2/LiberationSans-Bold.ttf" if bold
        else "/usr/share/fonts/truetype/liberation2/LiberationSans-Regular.ttf",
    ]
    for candidate in candidates:
        if Path(candidate).exists():
            return ImageFont.truetype(candidate, size)
    return ImageFont.load_default()


def rounded_panel(canvas, box, accent, title, subtitle, image):
    draw = ImageDraw.Draw(canvas)
    x0, y0, x1, y1 = box
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.rounded_rectangle((x0 + 10, y0 + 16, x1 + 10, y1 + 16), 28, fill=(0, 0, 0, 150))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(18)))
    draw.rounded_rectangle(box, 28, fill=(11, 22, 34, 255), outline=(42, 65, 80, 255), width=2)
    draw.rounded_rectangle((x0 + 24, y0 + 66, x1 - 24, y1 - 55), 18,
                           fill=(3, 9, 14), outline=accent, width=2)
    clipped = image.resize((x1 - x0 - 52, y1 - y0 - 129), Image.Resampling.LANCZOS)
    canvas.alpha_composite(clipped, (x0 + 26, y0 + 68))
    draw.rounded_rectangle((x0 + 25, y1 - 42, x0 + 174, y1 - 13), 14, fill=accent)
    draw.text((x0 + 40, y1 - 39), title, font=font(14, True), fill="white")
    width = draw.textlength(subtitle, font=font(12))
    draw.text((x1 - 28 - width, y1 - 37), subtitle, font=font(12), fill=(135, 163, 177))
    for index, color in enumerate(((255, 86, 99), (255, 198, 71), (56, 219, 157))):
        draw.ellipse((x0 + 28 + index * 20, y0 + 24, x0 + 38 + index * 20, y0 + 34), fill=color)


def compose():
    temp_main = ROOT / ".true3d-main.png"
    temp_top = ROOT / ".true3d-top.png"
    temp_bottom = ROOT / ".true3d-bottom.png"

    render_view(temp_main, (1400, 1200), (116, -142, 104), (0, -2, 3), (0, 0, 1), floor=True)
    render_view(temp_top, (620, 430), (0, -6, 150), (0, -2, 0), (0, 1, 0),
                parallel=True, parallel_scale=61)
    render_view(temp_bottom, (620, 430), (0, -6, -150), (0, -2, 0), (0, -1, 0),
                parallel=True, parallel_scale=61)

    width, height = 1920, 1200
    y = np.linspace(0, 1, height)[:, None, None]
    x = np.linspace(0, 1, width)[None, :, None]
    top = np.array([4, 10, 18], dtype=float)[None, None, :]
    bottom = np.array([2, 5, 10], dtype=float)[None, None, :]
    bg = top * (1 - y) + bottom * y
    bg = np.broadcast_to(bg, (height, width, 3)).copy()
    cyan = np.exp(-(((x - 0.48) / 0.42) ** 2 + ((y - 0.44) / 0.55) ** 2))
    bg += cyan * np.array([0, 19, 23])[None, None, :]
    canvas = Image.fromarray(np.uint8(np.clip(bg, 0, 255)), "RGB").convert("RGBA")

    main = Image.open(temp_main).convert("RGBA")
    canvas.alpha_composite(main, (-30, 0))
    draw = ImageDraw.Draw(canvas)

    draw.text((80, 60), "GENTHANG HARDWARE  /  O1", font=font(21, True),
              fill=(219, 255, 250), stroke_width=0)
    draw.text((76, 100), "DUAL DB9", font=font(58, True), fill="white")
    draw.text((80, 175), "DUAL CONTROLLER ADAPTER", font=font(22),
              fill=(107, 255, 235))
    draw.line((80, 220, 495, 220), fill=(49, 224, 194), width=3)
    draw.ellipse((507, 214, 519, 226), fill=(93, 255, 221))

    rounded_panel(canvas, (1360, 86, 1870, 568), (242, 66, 73, 255),
                  "TOP / 3D", "COMPONENT SIDE", Image.open(temp_top).convert("RGBA"))
    rounded_panel(canvas, (1360, 632, 1870, 1114), (68, 124, 235, 255),
                  "BOTTOM / 3D", "SOLDER SIDE", Image.open(temp_bottom).convert("RGBA"))

    # Product callouts target actual modeled features.
    draw.line((387, 798, 237, 960, 82, 960), fill=(104, 255, 236), width=2)
    draw.ellipse((380, 791, 394, 805), fill=(104, 255, 236))
    draw.text((82, 978), "RECESSED FEMALE DB9", font=font(20, True), fill="white")
    draw.text((82, 1008), "INDIVIDUAL CONTACT CAVITIES", font=font(14), fill=(117, 166, 172))

    draw.line((742, 405, 916, 262, 1190, 262), fill=(104, 255, 236), width=2)
    draw.ellipse((735, 398, 749, 412), fill=(104, 255, 236))
    draw.text((931, 229), "2× 20-PIN FEMALE SOCKETS", font=font(20, True), fill="white")
    draw.text((931, 260), "RAISED BODIES + GOLD CONTACT RINGS", font=font(14),
              fill=(117, 166, 172))

    draw.line((95, 1084, 1270, 1084), fill=(35, 57, 69), width=2)
    specs = [
        (95, "BOARD", "100 × 70 × 1.6 mm"),
        (355, "PORTS", "2× FEMALE DB9"),
        (625, "SOCKETS", "2× HARWIN 1×20"),
        (920, "RENDER", "PROCEDURAL 3D GEOMETRY"),
    ]
    for sx, heading, value in specs:
        draw.text((sx, 1103), heading, font=font(13, True), fill=(104, 255, 236))
        draw.text((sx, 1133), value, font=font(15), fill=(215, 229, 231))

    canvas.convert("RGB").save(OUTPUT, quality=96)
    for temporary in (temp_main, temp_top, temp_bottom):
        temporary.unlink(missing_ok=True)


if __name__ == "__main__":
    compose()
    print(OUTPUT)
