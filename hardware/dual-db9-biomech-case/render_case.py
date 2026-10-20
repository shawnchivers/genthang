#!/usr/bin/env python3
"""Offscreen VTK renders of the biomechanical case (run build_case.py first) and a contact sheet."""
from pathlib import Path

import vtk
from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
OUT = HERE / 'renders'

SHELL = dict(color=(0.16, 0.17, 0.17), metallic=0.85, roughness=0.24)
MOCK = {'pcb': ((0.03, 0.30, 0.18), 0.0, 0.5), 'db9': ((0.62, 0.64, 0.66), 0.9, 0.3),
        'sockets': ((0.05, 0.05, 0.06), 0.0, 0.6), 'nano': ((0.04, 0.04, 0.05), 0.1, 0.5),
        'hdmi': ((0.70, 0.71, 0.72), 0.9, 0.3), 'usbc': ((0.70, 0.71, 0.72), 0.9, 0.3),
        'plugs': ((0.10, 0.10, 0.11), 0.0, 0.7)}


def actor(path, color, metallic, roughness, z=0.0, opacity=1.0):
    reader = vtk.vtkSTLReader()
    reader.SetFileName(str(path))
    normals = vtk.vtkPolyDataNormals()
    normals.SetInputConnection(reader.GetOutputPort())
    normals.SetFeatureAngle(35)
    mapper = vtk.vtkPolyDataMapper()
    mapper.SetInputConnection(normals.GetOutputPort())
    a = vtk.vtkActor()
    a.SetMapper(mapper)
    p = a.GetProperty()
    p.SetInterpolationToPBR()
    p.SetColor(color)
    p.SetMetallic(metallic)
    p.SetRoughness(roughness)
    p.SetOpacity(opacity)
    a.SetPosition(0, 0, z)
    return a


def shell(name, z=0.0):
    return actor(HERE / 'stl' / f'{name}.stl', SHELL['color'], SHELL['metallic'], SHELL['roughness'], z)


def mock(names, opacity=1.0):
    return [actor(HERE / 'mockup' / f'{n}.stl', *MOCK[n], opacity=opacity) for n in names]


def render(name, actors, pos, focal, up=(0, 0, 1), view_angle=30, size=(1600, 1000), parallel=None):
    ren = vtk.vtkRenderer()
    ren.SetBackground(0.035, 0.04, 0.045)
    ren.SetBackground2(0.12, 0.13, 0.13)
    ren.GradientBackgroundOn()
    ren.UseSphericalHarmonicsOff()
    for a in actors:
        ren.AddActor(a)
    ren.RemoveAllLights()
    for p, c, i in [((-160, -220, 260), (1.0, 0.97, 0.92), 2.2), ((260, 120, 140), (0.55, 0.78, 0.85), 1.4),
                    ((40, 260, -80), (0.45, 0.55, 0.55), 0.9), ((50, -300, 30), (0.9, 0.9, 0.9), 0.35),
                    ((-300, 60, 60), (0.7, 0.75, 0.8), 0.8)]:
        light = vtk.vtkLight()
        light.PositionalOff()
        light.SetPosition(*p)
        light.SetFocalPoint(50, 38, 20)
        light.SetColor(*c)
        light.SetIntensity(i)
        ren.AddLight(light)
    cam = ren.GetActiveCamera()
    cam.SetPosition(*pos)
    cam.SetFocalPoint(*focal)
    cam.SetViewUp(*up)
    cam.SetViewAngle(view_angle)
    if parallel:
        cam.ParallelProjectionOn()
        cam.SetParallelScale(parallel)
    ren.ResetCameraClippingRange()
    win = vtk.vtkRenderWindow()
    win.SetOffScreenRendering(1)
    win.SetMultiSamples(8)
    win.AddRenderer(ren)
    win.SetSize(*size)
    win.Render()
    grab = vtk.vtkWindowToImageFilter()
    grab.SetInput(win)
    grab.Update()
    writer = vtk.vtkPNGWriter()
    writer.SetFileName(str(OUT / f'{name}.png'))
    writer.SetInputConnection(grab.GetOutputPort())
    writer.Write()


def contact_sheet(tiles):
    font_path = '/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf'
    try:
        font, big = ImageFont.truetype(font_path, 22), ImageFont.truetype(font_path, 30)
    except OSError:
        font = big = ImageFont.load_default()
    W, cols, tw, th, cap, gap = 1800, 3, 570, 356, 36, 22
    hero = Image.open(OUT / 'hero.png').convert('RGB')
    hero = hero.resize((W, int(hero.height * W / hero.width)))
    rows = (len(tiles) + cols - 1) // cols
    sheet = Image.new('RGB', (W, hero.height + gap + rows * (th + cap + gap)), (9, 10, 12))
    sheet.paste(hero, (0, 0))
    d = ImageDraw.Draw(sheet)
    d.text((30, 24), 'GenThang dual DB9 - biomechanical case', fill=(220, 225, 222), font=big)
    xg = (W - cols * tw) // (cols + 1)
    for i, (key, text) in enumerate(tiles):
        r, c = divmod(i, cols)
        x, y = xg + c * (tw + xg), hero.height + gap + r * (th + cap + gap)
        sheet.paste(Image.open(OUT / f'{key}.png').convert('RGB').resize((tw, th)), (x, y))
        d.text((x, y + th + 6), text, fill=(200, 205, 202), font=font)
    sheet.save(OUT / 'contact-sheet.png')


def main():
    OUT.mkdir(exist_ok=True)
    closed = [shell('case_base'), shell('case_lid', 33.5)]
    render('hero', closed, (-95, -150, 130), (50, 38, 18))
    render('front', closed + mock(['pcb', 'db9', 'sockets', 'nano', 'hdmi']), (5, -215, 55), (50, 20, 18))
    render('back', closed, (150, 240, 120), (50, 38, 18))
    render('top', closed + mock(['pcb', 'db9', 'sockets', 'nano']), (50, 38, 400), (50, 38, 0), up=(0, 1, 0), parallel=62)
    render('side', closed, (-330, 38, 30), (50, 38, 24), parallel=40)
    render('exploded', [shell('case_base'), shell('case_lid', 75)] +
           mock(['pcb', 'db9', 'sockets', 'nano', 'hdmi', 'usbc']), (-120, -180, 160), (50, 38, 40))
    render('open', [shell('case_base')] + mock(['pcb', 'db9', 'sockets', 'nano', 'hdmi', 'usbc']),
           (130, -100, 160), (50, 40, 10))
    lid_bed = shell('case_lid')
    lid_bed.SetPosition(135, 0, 0)
    render('print', [shell('case_base'), lid_bed], (110, -260, 230), (115, 40, 10))
    contact_sheet([('front', 'Front: DB9 maws + HDMI channel'), ('back', 'Back: USB-C orifice, vents'),
                   ('top', 'Top: spine, rib cage, vent slits'), ('side', 'Side: rib cage, vents, hoses'),
                   ('exploded', 'Exploded with the O1 carrier'), ('open', 'Lid off: board slid into place')])


if __name__ == '__main__':
    main()
