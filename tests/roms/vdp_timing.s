| vdp_timing: ROM-free Genesis test program for VDP counter and DMA timing (no
| commercial code). Results are word writes to $FFFF00, printed by verilator/tb_ref.sv
| as "TESTOUT xxxx" and checked by `make -C verilator vdp-timing` against documented
| NTSC H40/V28 hardware values (Charles MacDonald, "Sega Genesis VDP documentation"):
|   tag 1: lines per frame (262), V after $EA ($E5), H samples in $B7-$E3 (0)
|   tag 4: 68K->VRAM DMA, 4096 bytes, display off: lines (205 bytes/line -> ~20)
|   tag 5: 68K->VRAM DMA, 512 bytes, active display: lines (18 bytes/line -> ~28)
|   tag 6: VRAM fill, 4096 bytes, display off: lines (204 bytes/line -> ~20)
|   tag 7: VRAM copy, 2048 bytes, display off: lines (102 bytes/line -> ~20)

    .macro PRINT val
    move.w  \val, 0xFFFF00
    .endm

    .text
    .global start
    .org 0
    .long 0x00FFFE00
    .long start
    .rept 62
    .long idle
    .endr

    .org 0x100
    .ascii "SEGA MEGA DRIVE "
    .ascii "GEN THANG TEST  "
    .ascii "VDP TIMING TEST PROGRAM                         "
    .ascii "VDP TIMING TEST PROGRAM                         "
    .ascii "GM 00000000-01"
    .word 0
    .ascii "J               "
    .long 0, rom_end - 1, 0x00FF0000, 0x00FFFFFF
    .ascii "            "
    .ascii "            "
    .ascii "                                        "
    .ascii "JUE             "

    .org 0x200
start:
    move.w  #0x2700, %sr
    lea     0xC00004, %a4       | control / status
    lea     0xC00000, %a5       | data
    lea     0xC00008, %a6       | HV counter
    move.w  #0x8004, (%a4)
    move.w  #0x8174, (%a4)      | display on, DMA on, V28
    move.w  #0x8C81, (%a4)      | H40
    move.w  #0x8F02, (%a4)
    bsr     wait_vbl_start
    bsr     wait_vbl_start

    | ---- tag 1: counters over one frame ----
    bsr     wait_vbl_start
    moveq   #0, %d2             | V changes (lines)
    moveq   #0, %d4             | H samples in the $B7-$E3 gap
    moveq   #-1, %d5            | V value following $EA
    moveq   #0, %d7             | left the first vblank
    move.w  (%a6), %d6
    lsr.w   #8, %d6
1:  move.w  (%a6), %d0
    move.w  %d0, %d1
    lsr.w   #8, %d1
    andi.w  #0xFF, %d0
    cmp.w   %d6, %d1
    beq.s   2f
    addq.w  #1, %d2
    cmpi.w  #0xEA, %d6          | $E5-$EA occur twice: keep the first $EA only
    bne.s   3f
    tst.w   %d5
    bpl.s   3f
    move.w  %d1, %d5
3:  move.w  %d1, %d6
2:  cmpi.w  #0xB7, %d0
    blo.s   4f
    cmpi.w  #0xE3, %d0
    bhi.s   4f
    addq.w  #1, %d4
4:  move.w  (%a4), %d0
    btst    #3, %d0
    beq.s   5f
    tst.w   %d7
    beq.s   1b
    bra.s   6f
5:  moveq   #1, %d7
    bra.s   1b
6:  PRINT   #1
    PRINT   %d2
    PRINT   %d5
    PRINT   %d4

    | ---- tag 4: 68K->VRAM DMA, 2048 words, display off ----
    move.w  #0x8F02, (%a4)
    bsr     wait_vbl_end        | VB stays set while the display is off: wait first
    move.w  #0x8134, (%a4)
    move.w  #0x9300, (%a4)
    move.w  #0x9408, (%a4)
    move.w  #0x9500, (%a4)
    move.w  #0x9600, (%a4)
    move.w  #0x9700, (%a4)
    move.w  (%a6), %d1
    lsr.w   #8, %d1
    move.l  #0x60000080, (%a4)  | VRAM $2000, DMA (68K halts until done)
    move.w  (%a6), %d0
    lsr.w   #8, %d0
    sub.w   %d1, %d0
    andi.w  #0xFF, %d0          | VB clears at V=$FF, one line before 0
    PRINT   #4
    PRINT   %d0

    | ---- tag 5: 68K->VRAM DMA, 256 words, active display ----
    move.w  #0x8174, (%a4)
    bsr     wait_vbl_end
    move.w  #0x9300, (%a4)
    move.w  #0x9401, (%a4)
    move.w  #0x9500, (%a4)
    move.w  #0x9600, (%a4)
    move.w  #0x9700, (%a4)
    move.w  (%a6), %d1
    lsr.w   #8, %d1
    move.l  #0x60000080, (%a4)
    move.w  (%a6), %d0
    lsr.w   #8, %d0
    sub.w   %d1, %d0
    andi.w  #0xFF, %d0
    PRINT   #5
    PRINT   %d0

    | ---- tag 6: VRAM fill, 4096 bytes, display off ----
    move.w  #0x8F01, (%a4)
    bsr     wait_vbl_end
    move.w  #0x8134, (%a4)
    move.w  #0x9300, (%a4)
    move.w  #0x9410, (%a4)
    move.w  #0x9780, (%a4)
    move.l  #0x40000081, (%a4)  | VRAM $4000, DMA fill
    move.w  #0x1234, (%a5)      | fill value starts the fill
    bsr     count_dma_lines
    PRINT   #6
    PRINT   %d2

    | ---- tag 7: VRAM copy, 2048 bytes, display off ----
    move.w  #0x8174, (%a4)
    bsr     wait_vbl_end
    move.w  #0x8134, (%a4)
    move.w  #0x9300, (%a4)
    move.w  #0x9408, (%a4)
    move.w  #0x9500, (%a4)
    move.w  #0x9600, (%a4)
    move.w  #0x97C0, (%a4)
    move.l  #0x200000C1, (%a4)  | VRAM copy $0000 -> $6000
    bsr     count_dma_lines
    PRINT   #7
    PRINT   %d2

    PRINT   #0xFFFF
    move.w  #0x8174, (%a4)
    move.w  #0x8F02, (%a4)
done:
    bra.s   done

| lines elapsed while the VDP reports DMA busy (status bit 1)
count_dma_lines:
    nop
    nop
    moveq   #0, %d2
    move.w  (%a6), %d6
    lsr.w   #8, %d6
1:  move.w  (%a4), %d0
    btst    #1, %d0
    beq.s   2f
    move.w  (%a6), %d1
    lsr.w   #8, %d1
    cmp.w   %d6, %d1
    beq.s   1b
    addq.w  #1, %d2
    move.w  %d1, %d6
    bra.s   1b
2:  rts

wait_vbl_start:
1:  move.w  (%a4), %d0
    btst    #3, %d0
    bne.s   1b
2:  move.w  (%a4), %d0
    btst    #3, %d0
    beq.s   2b
    rts

wait_vbl_end:
1:  move.w  (%a4), %d0
    btst    #3, %d0
    beq.s   1b
2:  move.w  (%a4), %d0
    btst    #3, %d0
    bne.s   2b
    rts

idle:
    rte

    .balign 1024, 0xFF
rom_end:
