| Gen Thang save-state stub. The menu copies it to the save-state window and raises a
| level 7 interrupt whose vector the hardware fetches from the window (system.sv).
| It runs with the Z80 frozen at an instruction boundary and talks to the menu
| through CMD/STAT/GO in the window:
|   save: dump CPU, VDP, Z80 and YM state, STAT=1, wait GO=2, STAT=3, rte
|   load: STAT=1, wait GO=2 (menu has filled the window and work RAM), restore, STAT=3, rte
| Work RAM, cartridge SRAM and (on save) VRAM are read/written by the menu directly.
| Build: see Makefile (ss_stub.h).

        .equ W,     0x400000            | save state window (SDRAM)
        .equ H,     0x420000            | save state registers, see system.sv
        .equ CMD,   W+0x80
        .equ STAT,  W+0x84
        .equ GO,    W+0x86
        .equ STACK, W+0x1000            | own stack: the menu rewrites work RAM on load
        .equ CPU,   W+0x1000            | d0-d7/a0-a6, usp, ssp
        .equ VREG,  W+0x1100            | VDP registers 0-31
        .equ VADDR, W+0x1120            | ADDR lo, ADDR hi, {PENDING, CODE}, ADDR[16]
        .equ CRAM,  W+0x1200
        .equ VSRAM, W+0x1280
        .equ ZREG,  W+0x1300            | T80 REG words 0-13, then the status word
        .equ ZSTAT, W+0x1320
        .equ IOREG, W+0x1330            | data 1-3, control 1-3
        .equ YM,    W+0x1400            | port 0 then port 1
        .equ ZRAM,  W+0x2000
        .equ VRAM,  W+0x10000
        .equ VCTRL, 0xC00004
        .equ VDATA, 0xC00000

        .text
        .globl  entry
entry:
        cmp.w   #2,CMD
        beq     load

| ---- save ---------------------------------------------------------------------------
        movem.l d0-d7/a0-a6,CPU
        move.l  usp,a0
        move.l  a0,CPU+60
        move.l  a7,CPU+64
        lea     STACK,a7
        lea     VCTRL,a1
        lea     VDATA,a2
        lea     H+0x41,a0               | registers, address and code before a status
        lea     VREG,a3                 | read clears PENDING
        moveq   #35,d1
1:      move.b  (a0),(a3)+
        addq.l  #2,a0
        dbra    d1,1b
2:      move.w  (a1),d0                 | wait for DMA and the FIFO
        btst    #1,d0
        bne.s   2b
        btst    #9,d0
        beq.s   2b
        move.b  H+0x81,VADDR            | a DMA may have moved the address
        move.b  H+0x83,VADDR+1
        move.b  H+0x87,VADDR+3
        move.w  #0x8F02,(a1)
        move.l  #0x00000020,(a1)        | CRAM read
        lea     CRAM,a3
        moveq   #63,d1
3:      move.w  (a2),(a3)+
        dbra    d1,3b
        move.l  #0x00000010,(a1)        | VSRAM read
        lea     VSRAM,a3
        moveq   #39,d1
4:      move.w  (a2),(a3)+
        dbra    d1,4b
        bsr     vdp_resume
5:      tst.w   H+0x20                  | Z80 frozen?
        bpl.s   5b
        lea     H,a0
        lea     ZREG,a3
        moveq   #16,d1                  | 14 register words, a gap, the status word
6:      move.w  (a0)+,(a3)+
        dbra    d1,6b
        lea     0xA00000,a0
        lea     ZRAM,a3
        move.w  #8191,d1
7:      move.b  (a0)+,(a3)+
        dbra    d1,7b
        lea     H+0x401,a0
        lea     YM,a3
        move.w  #511,d1
8:      move.b  (a0),(a3)+
        addq.l  #2,a0
        dbra    d1,8b
        lea     0xA10003,a0             | I/O data and control registers
        lea     IOREG,a3
        moveq   #5,d1
9:      move.b  (a0),(a3)+
        addq.l  #2,a0
        dbra    d1,9b
        bsr     handshake
        movea.l CPU+64,a7
        movem.l CPU,d0-d7/a0-a6
        move.w  #3,STAT
        rte

| ---- load ---------------------------------------------------------------------------
load:
        lea     STACK,a7
        bsr     handshake
        lea     VCTRL,a1
        lea     VDATA,a2
        move.w  (a1),d0
1:      move.w  (a1),d0
        btst    #1,d0
        bne.s   1b
        move.w  #0x8104,(a1)            | display and DMA off, mode 5
        move.w  #0x8F02,(a1)
        move.l  #0x40000000,(a1)        | VRAM write
        lea     VRAM,a0
        move.w  #32767,d1
2:      move.w  (a0)+,(a2)
        dbra    d1,2b
        move.l  #0xC0000000,(a1)        | CRAM write
        lea     CRAM,a0
        moveq   #63,d1
3:      move.w  (a0)+,(a2)
        dbra    d1,3b
        move.l  #0x40000010,(a1)        | VSRAM write
        lea     VSRAM,a0
        moveq   #39,d1
4:      move.w  (a0)+,(a2)
        dbra    d1,4b
        lea     VREG,a0
        move.w  #0x8000,d0
        moveq   #23,d1
5:      move.b  (a0)+,d0
        move.w  d0,(a1)
        add.w   #0x0100,d0
        dbra    d1,5b
        bsr     vdp_resume

        move.w  ZSTAT,d5
        moveq   #0,d0                   | Z80 reset line first: the YM2612 follows it
        btst    #12,d5
        beq.s   6f
        move.w  #0x100,d0
6:      move.w  d0,0xA11200
        lea     YM,a0
        lea     0xA04000,a3
        moveq   #0x21,d0
        bsr     ym_port
        lea     YM+256,a0
        lea     0xA04002,a3
        moveq   #0x30,d0
        bsr     ym_port
        lea     ZRAM,a0
        lea     0xA00000,a3
        move.w  #8191,d1
7:      move.b  (a0)+,(a3)+
        dbra    d1,7b
        lea     0xA06000,a3             | bank register, 9 bits, A15 first
        move.w  d5,d0
        moveq   #8,d1
8:      move.b  d0,(a3)
        lsr.w   #1,d0
        dbra    d1,8b
        lea     IOREG,a0
        move.b  3(a0),0xA10009
        move.b  4(a0),0xA1000B
        move.b  5(a0),0xA1000D
        move.b  (a0),0xA10003
        move.b  1(a0),0xA10005
        move.b  2(a0),0xA10007

        lea     ZREG,a0                 | frozen in HALT: PC is past the HALT opcode
        btst    #14,d5
        bne.s   9f
        subq.w  #1,8(a0)
9:      lea     H,a3
        moveq   #13,d1
10:     move.w  (a0)+,(a3)+
        dbra    d1,10b
        move.w  #1,H+0x20               | reset the T80 (it stays frozen)
        move.w  #0,H+0x20
        move.w  #2,H+0x20               | load its registers
        move.w  #0,H+0x20
        moveq   #0,d0
        btst    #13,d5
        bne.s   11f
        move.w  #0x100,d0
11:     move.w  d0,0xA11100             | game's Z80 bus request

        move.l  CPU+60,a0
        move.l  a0,usp
        movea.l CPU+64,a7               | the exception frame is in the restored work RAM
        movem.l CPU,d0-d7/a0-a6
        move.w  #3,STAT
        rte

| ---- helpers ------------------------------------------------------------------------
handshake:
        move.w  #1,STAT
1:      cmp.w   #2,GO
        bne.s   1b
        rts

| Restore autoincrement, address and code from VREG/VADDR without starting a DMA.
| a1 = VDP control port
vdp_resume:
        move.w  #0x8F00,d0
        move.b  VREG+15,d0
        move.w  d0,(a1)
        moveq   #0,d0
        move.b  VADDR+1,d0
        lsl.w   #8,d0
        move.b  VADDR,d0                | d0 = ADDR[15:0]
        move.w  d0,d2
        andi.w  #0x3FFF,d2
        moveq   #0,d1
        move.b  VADDR+2,d1              | {0, PENDING, CODE}
        moveq   #3,d3
        and.w   d1,d3                   | CODE[1:0]
        cmpi.w  #2,d3                   | 2: the last control write set a register
        beq.s   1f
        ror.w   #2,d3
        or.w    d3,d2
1:      move.w  d2,(a1)
        moveq   #0x1C,d4
        and.w   d1,d4                   | CODE[4:2] -> bits 6:4
        lsl.w   #2,d4
        rol.w   #2,d0                   | ADDR[15:14] -> bits 1:0
        andi.w  #3,d0
        or.w    d0,d4
        moveq   #1,d0
        and.b   VADDR+3,d0              | ADDR[16] -> bit 2
        lsl.w   #2,d0
        or.w    d0,d4
        move.w  d4,(a1)
        move.b  VADDR+2,d1
        andi.w  #3,d1
        cmpi.w  #2,d1
        bne.s   2f
        move.w  #0x8F00,d0
        move.b  VREG+15,d0
        move.w  d0,(a1)
        rts
2:      btst    #6,VADDR+2
        beq.s   3f
        move.w  d2,(a1)                 | only the first word had been written
3:      rts

| Write YM2612 registers d0..0xB7 except key on/off.
| a0 = shadow of this port, a3 = address port
ym_port:
1:      cmpi.b  #0x28,d0
        beq.s   3f
2:      btst    #7,0xA04000
        bne.s   2b
        move.b  d0,(a3)
        move.b  (a0,d0.w),1(a3)
3:      addq.b  #1,d0
        cmpi.b  #0xB8,d0
        bne.s   1b
        rts
