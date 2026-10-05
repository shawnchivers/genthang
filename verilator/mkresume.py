"""Build a ROM that boots straight into a BlastEm save state.

usage: mkresume.py game.md slot_0.state out.md

The state (VRAM, CRAM, VSRAM, VDP registers, 68K work RAM and registers, Z80 RAM and
registers, YM2612 registers, Z80 bank) is appended after the ROM with a 68K routine that
restores it, and the reset vector is pointed at that routine. Runs on real hardware,
emulators and the testbenches. Not restored: Z80 R register, YM/PSG internal phase,
VDP FIFO/sprite line state (rebuilt on the next frame).
"""
import struct
import sys


def sections(path):
    d = open(path, "rb").read()
    if d[:8] != b"BLSTSZ\x01\x07":
        sys.exit("not a BlastEm native save state")
    d, p, s = d[8:], 0, {}
    while p < len(d):
        sid, sz = struct.unpack(">HI", d[p:p + 6])
        s[sid] = d[p + 6:p + 6 + sz]
        p += 6 + sz
    return s


class Asm:
    def __init__(self, org):
        self.org, self.b = org, bytearray()

    def pc(self):
        return self.org + len(self.b)

    def w(self, *words):
        for x in words:
            self.b += struct.pack(">H", x & 0xFFFF)

    def l(self, x):
        self.w(x >> 16, x)

    def lea(self, an, addr):            # lea (xxx).l,An
        self.w(0x41F9 | an << 9); self.l(addr)

    def copy_loop(self, op, count):     # move.w #count-1,d0 / op / dbra d0,*-2
        self.w(0x303C, count - 1)
        top = self.pc()
        self.w(op)
        self.w(0x51C8, top - (self.pc() + 2))

    def wait_bit(self, bit, addr):      # btst #bit,(xxx).l / bne.s *
        top = self.pc()
        self.w(0x0839, bit); self.l(addr)
        self.w(0x6600 | ((top - (self.pc() + 2)) & 0xFF))

    def move_b(self, val, addr):        # move.b #val,(xxx).l
        self.w(0x13FC, val & 0xFF); self.l(addr)

    def move_w(self, val, addr):        # move.w #val,(xxx).l
        self.w(0x33FC, val); self.l(addr)


def z80_stub(z, zram):
    regs, f = z[0:13], z[13]
    alt, altf = z[14:27], z[27]
    pc, sp = struct.unpack(">HH", z[28:32])
    im, iff1 = z[32], z[33]
    C, B, E, D, L, H, IXL, IXH, IYL, IYH, I, R, A = range(13)
    base = sp - 0x60
    data = base + 0x40
    code = bytearray()
    for i in range(3):                  # put back the bytes under the JP at 0
        code += bytes([0x3E, zram[i], 0x32, i, 0x00])
    code += bytes([0x31, data & 0xFF, data >> 8])               # ld sp,data
    code += bytes([0xF1, 0xC1, 0xD1, 0xE1, 0x08, 0xD9])         # alt set, ex af,af', exx
    code += bytes([0xDD, 0xE1, 0xFD, 0xE1])                     # pop ix, pop iy
    code += bytes([0x3E, regs[I], 0xED, 0x47])                  # ld i,a
    code += bytes([0xC1, 0xD1, 0xE1, 0xF1])                     # main bc de hl af
    code += bytes([0x31, sp & 0xFF, sp >> 8])
    code += bytes([0xED, (0x46, 0x56, 0x5E)[im & 3]])
    code += bytes([0xFB if iff1 else 0xF3, 0xC3, pc & 0xFF, pc >> 8])
    assert len(code) <= 0x40
    pops = bytes([altf, alt[A], alt[C], alt[B], alt[E], alt[D], alt[L], alt[H],
                  regs[IXL], regs[IXH], regs[IYL], regs[IYH],
                  regs[C], regs[B], regs[E], regs[D], regs[L], regs[H], f, regs[A]])
    zram = bytearray(zram)
    zram[base:base + len(code)] = code
    zram[data:data + len(pops)] = pops
    zram[0:3] = bytes([0xC3, base & 0xFF, base >> 8])
    return zram


def main():
    rom = bytearray(open(sys.argv[1], "rb").read())
    s = sections(sys.argv[2])

    v = s[3]
    if v[1] != 64:
        sys.exit("unexpected VDP section layout")
    o = 2
    vram = v[o:o + 65536]; o += 65536
    cram = v[o:o + 128]; o += 128
    vsram = v[o:o + 80]; o += 128
    o += 320                            # sprite attribute cache
    vreg = v[o:o + 24]

    m = s[1]
    dregs = struct.unpack(">8I", m[0:32])
    aregs = struct.unpack(">9I", m[32:68])
    pc, sr = struct.unpack(">IH", m[68:74])
    wram = s[10][1:1 + 65536]
    zram = z80_stub(s[2], s[11][1:1 + 8192])
    ym = s[4]
    ym1, ym2 = ym[0:0xB8 - 0x21], ym[0xB8 - 0x21:0xB8 - 0x21 + 0xB8 - 0x30]
    z_reset, z_busreq, z_bank = s[6][0], s[6][1], struct.unpack(">H", s[6][2:4])[0]
    io = [s[7], s[8]]

    base = (len(rom) + 0xFFFF) & ~0xFFFF
    a = Asm(base)
    a.w(0x46FC, 0x2700)                 # move.w #$2700,sr
    a.lea(1, 0xC00004)
    a.lea(2, 0xC00000)
    a.w(0x3011)                         # move.w (a1),d0: clear pending command
    for i, val in enumerate(vreg):
        if i == 0: val &= ~0x10         # no HINT
        if i == 1: val &= ~0x70         # display, VINT and DMA off
        if i == 15: val = 2
        a.w(0x32BC, 0x8000 | i << 8 | val)
    a.w(0x22BC); a.l(0x40000000)        # VRAM write @0 (after reg 5, fills the sprite cache)
    vram_lea = len(a.b); a.lea(0, 0)
    a.copy_loop(0x3498, 32768)          # move.w (a0)+,(a2)
    a.w(0x22BC); a.l(0xC0000000)
    cram_lea = len(a.b); a.lea(0, 0)
    a.copy_loop(0x3498, 64)
    a.w(0x22BC); a.l(0x40000010)
    vsram_lea = len(a.b); a.lea(0, 0)
    a.copy_loop(0x3498, 40)
    for i in (15, 0, 1):
        a.w(0x32BC, 0x8000 | i << 8 | vreg[i])
    wram_lea = len(a.b); a.lea(0, 0)
    a.lea(3, 0xFF0000)
    a.copy_loop(0x36D8, 32768)          # move.w (a0)+,(a3)+
    a.move_w(0x100, 0xA11200)           # Z80 out of reset
    a.move_w(0x100, 0xA11100)           # and take its bus
    a.wait_bit(0, 0xA11100)
    zram_lea = len(a.b); a.lea(0, 0)
    a.lea(3, 0xA00000)
    a.copy_loop(0x16D8, 8192)           # move.b (a0)+,(a3)+
    a.move_w(0, 0xA11200)               # reset pulse (also resets the YM2612): Z80 restarts into the stub
    a.w(0x4E71, 0x4E71, 0x4E71, 0x4E71)
    a.move_w(0x100, 0xA11200)
    a.wait_bit(0, 0xA11100)
    for part, regs, start in ((0, ym1, 0x21), (1, ym2, 0x30)):
        for r, val in enumerate(regs):
            reg = start + r
            if reg in (0x28, 0x29) or (reg & 3) == 3 and reg >= 0x30:
                continue
            if reg == 0x27:
                val &= 0xCF             # keep timer load/enable, no flag reset
            a.wait_bit(7, 0xA04000)
            a.move_b(reg, 0xA04000 + 2 * part)
            a.move_b(val, 0xA04001 + 2 * part)
    for i in range(9):
        a.move_b(z_bank >> i & 1, 0xA06000)
    if z_reset:
        a.move_w(0, 0xA11200)
    if not z_busreq:
        a.move_w(0, 0xA11100)
    for port, sec in enumerate(io):
        a.move_b(sec[1], 0xA10009 + 2 * port)   # control
        a.move_b(sec[0], 0xA10003 + 2 * port)   # data
    supervisor = sr & 0x2000
    ssp, usp = (aregs[7], aregs[8]) if supervisor else (aregs[8], aregs[7])
    a.w(0x207C); a.l(usp)               # move.l #usp,a0
    a.w(0x4E60)                         # move.l a0,usp
    a.lea(7, ssp)
    a.w(0x2F3C); a.l(pc)                # move.l #pc,-(a7)
    a.w(0x3F3C, sr)                     # move.w #sr,-(a7)
    regs_lea = len(a.b); a.lea(0, 0)
    a.w(0x4CD0, 0x7FFF)                 # movem.l (a0),d0-d7/a0-a6
    a.w(0x4E73)                         # rte

    blobs = {}
    data = bytearray()
    def put(name, blob):
        blobs[name] = a.pc() + len(data)
        data.extend(blob)
        if len(data) & 1: data.append(0)
    put("vram", vram); put("cram", cram); put("vsram", vsram); put("wram", wram)
    put("zram", zram)
    put("regs", struct.pack(">15I", *dregs, *aregs[:7]))
    for off, name in ((vram_lea, "vram"), (cram_lea, "cram"), (vsram_lea, "vsram"),
                      (wram_lea, "wram"), (zram_lea, "zram"), (regs_lea, "regs")):
        a.b[off + 2:off + 6] = struct.pack(">I", blobs[name])

    rom += b"\xff" * (base - len(rom))
    rom += a.b + data
    rom += b"\xff" * (-len(rom) % 4)
    rom[4:8] = struct.pack(">I", base)
    open(sys.argv[3], "wb").write(rom)
    print(f"{sys.argv[3]}: {len(rom)} bytes, resume code at {base:#x}, 68K pc {pc:#x} sr {sr:#06x}"
          f", Z80 pc {struct.unpack('>H', s[2][28:30])[0]:#x}")


if __name__ == "__main__":
    main()
