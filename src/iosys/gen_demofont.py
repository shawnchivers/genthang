#!/usr/bin/env python3
"""Generate demofont.hex: the 2bpp menu font for textdisp.v.

128 characters x 8 rows, one 16-bit word per row, pixel x (0 = left) in bits
[2x+1:2x]: 0 transparent, 1 drop shadow, 2 body, 3 top-edge highlight.
Glyphs 0x20-0x7E are font8x8_basic (public domain, bit 0 = left pixel);
0x01-0x06 are menu icons.
"""
from pathlib import Path

BASIC = """
0000000000000000 183c3c1818001800 3636000000000000 36367f367f363600
0c3e031e301f0c00 006333180c666300 1c361c6e3b336e00 0606030000000000
180c0606060c1800 060c1818180c0600 00663cff3c660000 000c0c3f0c0c0000
00000000000c0c06 0000003f00000000 00000000000c0c00 6030180c06030100
3e63737b6f673e00 0c0e0c0c0c0c3f00 1e33301c06333f00 1e33301c30331e00
383c36337f307800 3f031f3030331e00 1c06031f33331e00 3f3330180c0c0c00
1e33331e33331e00 1e33333e30180e00 000c0c00000c0c00 000c0c00000c0c06
180c0603060c1800 00003f00003f0000 060c1830180c0600 1e3330180c000c00
3e637b7b7b031e00 0c1e33333f333300 3f66663e66663f00 3c66030303663c00
1f36666666361f00 7f46161e16467f00 7f46161e16060f00 3c66030373667c00
3333333f33333300 1e0c0c0c0c0c1e00 7830303033331e00 6766361e36666700
0f06060646667f00 63777f7f6b636300 63676f7b73636300 1c36636363361c00
3f66663e06060f00 1e3333333b1e3800 3f66663e36666700 1e33070e38331e00
3f2d0c0c0c0c1e00 3333333333333f00 33333333331e0c00 6363636b7f776300
6363361c1c366300 3333331e0c0c1e00 7f6331184c667f00 1e06060606061e00
03060c1830604000 1e18181818181e00 081c366300000000 00000000000000ff
0c0c180000000000 00001e303e336e00 0706063e66663b00 00001e3303331e00
3830303e33336e00 00001e333f031e00 1c36060f06060f00 00006e33333e301f
0706366e66666700 0c000e0c0c0c1e00 300030303033331e 070666361e366700
0e0c0c0c0c0c1e00 0000337f7f6b6300 00001f3333333300 00001e3333331e00
00003b66663e060f 00006e33333e3078 00003b6e66060f00 00003e031e301f00
080c3e0c0c2c1800 0000333333336e00 00003333331e0c00 0000636b7f7f3600
000063361c366300 00003333333e301f 00003f190c263f00 380c0c070c0c3800
1818180018181800 070c0c380c0c0700 6e3b000000000000
""".split()

ICONS = {
    0x01: [0x00, 0x0E, 0x7F, 0x7F, 0x7F, 0x7F, 0x7F, 0x00],   # folder
    0x02: [0x3E, 0x7F, 0x5D, 0x5D, 0x7F, 0x7F, 0x55, 0x00],   # cartridge
    0x03: [0x01, 0x03, 0x07, 0x0F, 0x07, 0x03, 0x01, 0x00],   # right arrow
    0x04: [0x38, 0x68, 0x08, 0x08, 0x0E, 0x0F, 0x06, 0x00],   # music note
    0x05: [0x40, 0x60, 0x70, 0x78, 0x70, 0x60, 0x40, 0x00],   # left arrow
    0x06: [0x08, 0x08, 0x3E, 0x1C, 0x36, 0x22, 0x00, 0x00],   # star
}


def glyphs():
    g = [[0] * 8 for _ in range(128)]
    for i, h in enumerate(BASIC):
        g[0x20 + i] = list(bytes.fromhex(h))
    for c, rows in ICONS.items():
        g[c] = rows
    return g


def encode(rows):
    def b(x, y):
        return 0 <= x < 8 and 0 <= y < 8 and (rows[y] >> x) & 1
    words = []
    for y in range(8):
        w = 0
        for x in range(8):
            if b(x, y):
                v = 2 if b(x, y - 1) else 3
            elif b(x - 1, y - 1) or b(x - 1, y) or b(x, y - 1):
                v = 1
            else:
                v = 0
            w |= v << (2 * x)
        words.append(w)
    return words


def main():
    out = Path(__file__).with_name("demofont.hex")
    lines = [f"{w:04x}" for rows in glyphs() for w in encode(rows)]
    out.write_text("\n".join(lines) + "\n")
    print(f"wrote {out} ({len(lines)} words)")


if __name__ == "__main__":
    main()
