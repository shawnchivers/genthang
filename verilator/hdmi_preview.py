#!/usr/bin/env python3
"""Render a testbench frame (PPM) the way src/framebuffer_sync.sv shows it on HDMI.

The Verilator testbenches stop at the Genesis video output, so scanlines and
composite blending (applied in the HDMI scaler) never appear in their frames.
This script repeats that arithmetic on a dumped frame: nearest-neighbour scaling
into the 960x720 (4:3) window, the 4-bit-to-8-bit channel expansion, the
left-neighbour blend and the scanline dimming of the lower half of each source
line. The VDP transparency flag is not in a frame dump, so the adaptive blend
mode cannot be previewed.

usage: hdmi_preview.py in.ppm out.png [--scanlines 0|1|2] [--blend] [--no-scale] [--overlay]
                       [--crop X,Y,W,H]
       --scanlines 1 = 25% dimming, 2 = 50% (the menu's Scanlines setting)
       --crop       keep only this rectangle of the 960x720 window (to zoom in on detail)
       --overlay    menu overlay dump (overlay_*.ppm): scale only, the board draws it
                    without the DAC table, blend or scanlines
"""
import argparse
import struct
import sys
import zlib

WINDOW_W, WINDOW_H = 960, 720


def read_ppm(path):
    with open(path, "rb") as f:
        data = f.read()
    fields, pos = [], 0
    while len(fields) < 4:
        while data[pos:pos + 1].isspace():
            pos += 1
        end = pos
        while not data[end:end + 1].isspace():
            end += 1
        fields.append(data[pos:end])
        pos = end
    assert fields[0] == b"P6" and fields[3] == b"255", "expected a binary 8-bit PPM"
    width, height = int(fields[1]), int(fields[2])
    return width, height, data[pos + 1:pos + 1 + width * height * 3]


def crop(rgb, rect):
    x, y, w, h = rect
    assert 0 <= x and 0 <= y and x + w <= WINDOW_W and y + h <= WINDOW_H, "crop outside the window"
    rows = [rgb[((y + r) * WINDOW_W + x) * 3:((y + r) * WINDOW_W + x + w) * 3] for r in range(h)]
    return w, h, b"".join(rows)


def write_png(path, width, height, rgb):
    rows = b"".join(b"\x00" + rgb[y * width * 3:(y + 1) * width * 3] for y in range(height))

    def chunk(kind, body):
        crc = zlib.crc32(kind + body) & 0xFFFFFFFF
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", crc)

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(rows, 9)))
        f.write(chunk(b"IEND", b""))


def channel(a, b, blend, dim):
    """chan() from framebuffer_sync.sv; a, b are 4-bit values (this pixel, left pixel)."""
    da, db = a * 17, b * 17                      # dac(): {i, i}
    v = ((da + db) if blend else (da << 1)) >> 1
    if dim == 1:
        return v - (v >> 2)
    if dim == 2:
        return v >> 1
    return v


def render(width, height, pixels, scanlines, blend):
    out = bytearray()
    for row in range(WINDOW_H):
        ycnt = (row * height) % WINDOW_H
        src_y = (row * height) // WINDOW_H
        dim = scanlines if ycnt >= WINDOW_H // 2 else 0
        line = bytearray()
        for col in range(WINDOW_W):
            src_x = (col * width) // WINDOW_W
            left_x = max(src_x - 1, 0)
            here = (src_y * width + src_x) * 3
            left = (src_y * width + left_x) * 3
            for c in range(3):
                line.append(channel(pixels[here + c] >> 4, pixels[left + c] >> 4, blend, dim))
        out += line
    return bytes(out)


def render_overlay(width, height, pixels):
    out = bytearray()
    for row in range(WINDOW_H):
        src_y = (row * height) // WINDOW_H
        for col in range(WINDOW_W):
            here = (src_y * width + (col * width) // WINDOW_W) * 3
            out += pixels[here:here + 3]
    return bytes(out)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawTextHelpFormatter)
    ap.add_argument("input")
    ap.add_argument("output")
    ap.add_argument("--scanlines", type=int, choices=(0, 1, 2), default=0)
    ap.add_argument("--blend", action="store_true")
    ap.add_argument("--no-scale", action="store_true", help="write the frame at its native size")
    ap.add_argument("--overlay", action="store_true", help="input is a menu overlay dump")
    ap.add_argument("--crop", type=lambda s: tuple(int(v) for v in s.split(",")),
                    help="X,Y,W,H in output-window pixels")
    args = ap.parse_args()

    width, height, pixels = read_ppm(args.input)
    if args.no_scale:
        write_png(args.output, width, height, pixels)
    else:
        if args.overlay:
            image = render_overlay(width, height, pixels)
        else:
            image = render(width, height, pixels, args.scanlines, args.blend)
        if args.crop:
            out_w, out_h, image = crop(image, args.crop)
        else:
            out_w, out_h = WINDOW_W, WINDOW_H
        write_png(args.output, out_w, out_h, image)


if __name__ == "__main__":
    sys.exit(main())
