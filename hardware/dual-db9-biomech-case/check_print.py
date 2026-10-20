#!/usr/bin/env python3
"""Printability check of the exported STLs: closed 2-manifold mesh, and the area of downward-facing
surfaces steeper than the overhang limit that are not on the bed (they would need support or bridging).
"""
import struct
import sys
from collections import Counter
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
LIMIT_DEG = 50.0            # from vertical; 45 degrees nominal plus tessellation slack


def read_stl(path):
    data = path.read_bytes()
    if data[:5] == b'solid' and b'facet' in data[:300]:
        v = [list(map(float, ln.split()[1:4])) for ln in data.decode().splitlines() if ln.strip().startswith('vertex')]
        return np.array(v).reshape(-1, 3, 3)
    n = struct.unpack('<I', data[80:84])[0]
    rec = np.frombuffer(data[84:84 + 50 * n], dtype=np.dtype([('n', '<3f4'), ('v', '<9f4'), ('a', '<u2')]))
    return rec['v'].reshape(-1, 3, 3).astype(float)


def check(path, bridges):
    tri = read_stl(path)
    keys = np.round(tri, 4)
    edges = Counter()
    for t in keys:
        a, b, c = map(tuple, t)
        for e in ((a, b), (b, c), (c, a)):
            edges[tuple(sorted(e))] += 1
    bad_edges = sum(1 for k in edges.values() if k != 2)
    n = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
    area = np.linalg.norm(n, axis=1) / 2
    nz = n[:, 2] / np.maximum(np.linalg.norm(n, axis=1), 1e-12)
    zmin = tri[:, :, 2].min(axis=1)
    down = (nz < -np.sin(np.radians(LIMIT_DEG))) & (zmin > 0.05)
    flat = down & (nz < -0.999)
    sloped = down & ~flat
    print(f'{path.name}: {len(tri)} triangles, non-manifold edges: {bad_edges}, '
          f'volume {abs(np.einsum("ij,ij->i", tri[:, 0], np.cross(tri[:, 1], tri[:, 2])).sum()) / 6000:.1f} cm3')
    print(f'  horizontal ceilings (bridges) above the bed: {area[flat].sum():7.1f} mm2')
    for z, a in sorted(Counter({round(float(z), 1): 0 for z in zmin[flat]}).items()):
        sel = flat & (np.abs(zmin - z) < 0.06)
        span = tri[sel].reshape(-1, 3)
        print(f'    z = {z:5.1f}: {area[sel].sum():6.1f} mm2, x {span[:, 0].min():6.1f}..{span[:, 0].max():6.1f}, '
              f'y {span[:, 1].min():6.1f}..{span[:, 1].max():6.1f}  {bridges.get(z, "")}')
    print(f'  sloped overhangs steeper than {LIMIT_DEG:.0f} deg from vertical: {area[sloped].sum():7.1f} mm2')
    return bad_edges == 0


def main():
    ok = check(HERE / 'stl' / 'case_base.stl', {1.0: 'optional foot recesses (10.6 mm bridge)',
                                                 16.9: 'tops of the 3.3 mm #4-40 holes',
                                                 20.1: 'DB9 shell openings (17.9 mm bridge)',
                                                 28.3: 'USB-C opening (11-15 mm bridge)'})
    ok &= check(HERE / 'stl' / 'case_lid.stl', {1.8: 'lid groove (1.9 mm bridge)'})
    sys.exit(0 if ok else 1)


if __name__ == '__main__':
    main()
