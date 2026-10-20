"""Custom footprints from dimensioned references; units mm, top view.

Socket and DB9 hole patterns follow their manufacturer drawings.
"""
import pcbnew as p


def mm(v):
    return int(round(v * 1_000_000))


def xy(x, y):
    return p.VECTOR2I(mm(x), mm(y))


def layers(*ids):
    result = p.LSET()
    for layer in ids:
        result.AddLayer(layer)
    return result


def outline(fp, x1, y1, x2, y2, layer, width=.05):
    for a, b in [((x1,y1),(x2,y1)),((x2,y1),(x2,y2)),
                 ((x2,y2),(x1,y2)),((x1,y2),(x1,y1))]:
        item = p.FP_SHAPE(fp)
        item.SetShape(p.SHAPE_T_SEGMENT)
        item.SetStart(xy(*a)); item.SetStart0(xy(*a))
        item.SetEnd(xy(*b)); item.SetEnd0(xy(*b))
        item.SetWidth(mm(width)); item.SetLayer(layer)
        fp.Add(item)


def pad(fp, number, x, y, width, height, drill=None):
    item = p.PAD(fp)
    item.SetNumber(str(number))
    item.SetPosition(xy(x,y)); item.SetPos0(xy(x,y))
    item.SetSize(xy(width,height))
    if drill is None:
        item.SetAttribute(p.PAD_ATTRIB_SMD)
        item.SetShape(p.PAD_SHAPE_RECT)
        item.SetLayerSet(layers(p.F_Cu))  # Mask is a separate circular opening.
    else:
        item.SetAttribute(p.PAD_ATTRIB_PTH)
        item.SetShape(p.PAD_SHAPE_RECT if str(number) == '1' else p.PAD_SHAPE_CIRCLE)
        item.SetDrillSize(xy(drill,drill))
        item.SetLayerSet(layers(p.F_Cu,p.B_Cu,p.F_Mask,p.B_Mask))
    item.SetLocalSolderMaskMargin(0)
    fp.Add(item)


def footprint(name):
    fp = p.FOOTPRINT(None)
    fp.SetFPID(p.LIB_ID('GenThang',name))
    if name == 'Harwin_M20-7822046_1x20':
        fp.SetAttributes(p.FP_THROUGH_HOLE)
        for i in range(20):
            pad(fp,i+1,0,2.54*i,1.8,1.8,1.02)
        # Length 51.20, width2.50, centered on a48.26mm contact span.
        outline(fp,-1.25,-1.47,1.25,49.73,p.F_Fab,.1)
        outline(fp,-1.35,-1.57,1.35,49.83,p.F_SilkS,.12)
        outline(fp,-1.75,-1.97,1.75,50.23,p.F_CrtYd)
    elif name == 'Kycon_K22X-E9P-N':
        fp.SetAttributes(p.FP_THROUGH_HOLE)
        # Native engineering drawing faces UP. Here rotated180, translated to
        # pin1, so faces DOWN: 1..5 across back row, 6..9 nearer board edge.
        for i in range(5):
            pad(fp,i+1,i*2.77,0,1.9,1.9,1.09)
        for i in range(4):
            pad(fp,i+6,1.385+i*2.77,2.84,1.9,1.9,1.09)
        for x in [5.54-24.99/2,5.54+24.99/2]:
            pad(fp,0,x,10.92-9.525,4.4,4.4,3.05)
        outline(fp,5.54-30.81/2,-1.48,5.54+30.81/2,10.92,p.F_Fab,.1)
        # Conservative full-flange-width envelope includes the projecting nose;
        # not an invented exact 3D model of the shell curvature.
        outline(fp,5.54-30.81/2-.5,-1.98,5.54+30.81/2+.5,17.52,p.F_CrtYd)
        outline(fp,5.54-30.81/2,10.92,5.54+30.81/2,17.02,p.Dwgs_User,.1)
    else:
        raise ValueError(f'Unknown custom footprint {name}')
    return fp