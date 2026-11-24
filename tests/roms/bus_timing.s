| bus_timing: ROM-free Genesis test program for bus/memory timing (no commercial code).
| The 68K loops over ROM reads, work-RAM writes and reads, VDP data-port writes and a
| 68K->VRAM DMA while the Z80 continuously reads banked ROM. verilator/perf68k.sv
| reports wait states per region, so `make ref` (ideal memory) and `make dut` (SDRAM)
| can be compared. Built by `make -C verilator test-roms`.

    .text
    .global start
    .org 0
    .long 0x00FFFE00            | initial SSP
    .long start                 | reset PC
    .rept 62
    .long idle                  | every other vector
    .endr

    .org 0x100
    .ascii "SEGA MEGA DRIVE "
    .ascii "GEN THANG TEST  "
    .ascii "BUS TIMING TEST PROGRAM                         "    | domestic name (48)
    .ascii "BUS TIMING TEST PROGRAM                         "    | overseas name (48)
    .ascii "GM 00000000-00"                                     | serial (matches no quirk)
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
    lea     0xC00004, %a4       | VDP control
    lea     0xC00000, %a5       | VDP data

    | load the Z80 loop: ld a,(8000h) ; jr -5  (reads banked ROM at 68K $000000 forever)
    move.w  #0x100, 0xA11100    | bus request
    move.w  #0x100, 0xA11200    | release reset so the request is granted
1:  btst    #0, 0xA11100
    bne.s   1b
    lea     z80code, %a0
    lea     0xA00000, %a1
    moveq   #4, %d0
2:  move.b  (%a0)+, (%a1)+
    dbra    %d0, 2b
    move.w  #0, 0xA11200        | reset the Z80 so it starts at 0
    move.w  #0, 0xA11100        | release the bus
    moveq   #20, %d0
3:  dbra    %d0, 3b
    move.w  #0x100, 0xA11200    | run

    | VDP: H40, display on, DMA enabled, V28, auto-increment 2
    move.w  #0x8004, (%a4)
    move.w  #0x8174, (%a4)
    move.w  #0x8C81, (%a4)
    move.w  #0x8F02, (%a4)

main:
    lea     0, %a0              | ROM reads
    move.w  #255, %d1
4:  move.l  (%a0)+, %d0
    dbra    %d1, 4b
    lea     0xFF0000, %a0       | RAM writes
    move.w  #255, %d1
5:  move.l  %d0, (%a0)+
    dbra    %d1, 5b
    lea     0xFF0000, %a0       | RAM reads
    move.w  #255, %d1
6:  move.l  (%a0)+, %d0
    dbra    %d1, 6b
    move.l  #0x40000000, (%a4)  | VRAM write $0000 through the data port
    move.w  #127, %d1
7:  move.w  %d0, (%a5)
    dbra    %d1, 7b
    | 68K->VRAM DMA, 512 words from ROM $000000 to VRAM $1000
    move.w  #0x9300, (%a4)
    move.w  #0x9402, (%a4)
    move.w  #0x9500, (%a4)
    move.w  #0x9600, (%a4)
    move.w  #0x9700, (%a4)
    move.l  #0x50000080, (%a4)
    bra     main

idle:
    rte

z80code:
    .byte 0x3A, 0x00, 0x80, 0x18, 0xFB
    .balign 2
    .balign 1024, 0xFF
rom_end:
