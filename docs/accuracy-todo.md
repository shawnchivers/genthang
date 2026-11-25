# Accuracy work tracker

Background and evidence for each item: [accuracy-audit.md](accuracy-audit.md).

## 1. Per-game quirk detection (done)

- [x] Firmware reads the cartridge serial (`$183-$18A`) during load and matches it
      against the MiSTer quirk table
- [x] Quirk bits travel with the existing load-finish write (`$02000030`, bits 9-15)
      and drive `system` inputs
- [x] Quirks enabled: FMBUSY, NORAM, SRAM, SRAM00, EEPROM (read stub), SCHAN, FAST_FIFO
- [x] Tests: firmware table/bit packing, register latch
- [x] FPGA fit and timing (DB9 default build: 20,035/20,736 logic, 10,233/10,368 CLS,
      clk_sys 66.2 MHz / 54, no negative slack)
- [x] Flash test image `builds/quirks/` (local, not committed)
- [x] Hardware check (confirmed good on the board) with the titles in `game-compatible.txt`:
  - [x] Hellfire (FMBUSY)
  - [x] Twin Hawk (FMBUSY)
  - [x] Tecmo World Cup (FMBUSY)
  - [x] Puggsy (NORAM)
  - [x] NBA Jam TE (SRAM)
  - [x] NFL Quarterback Club (SRAM)
  - [x] Sonic 1 Remastered (SRAM00)
  - [x] Clue (FAST_FIFO)

Not planned: Pier Solar mapper (needs its EEPROM) and SVP; both stay unsupported.

## 2. Z80 bank stall during frame-lock pause (reverted)

- [x] Tried spreading the frame-lock pause: 14 MCLK every 3434 MCLK, so the once-per-frame
      halt dropped from ~73 us to ~5 us (`a7bf260`)
- [x] Reverted: on hardware it broke sprites in Streets of Rage 2 (flickering/broken
      sprites), because the VDP was frozen mid-line during active display. No audible
      gain was found either.
- [ ] If revisited: pause only during horizontal blanking (between sprite fetches), and
      test sprite-heavy games first

## 3. Bus and memory timing measurement (done)

- [x] `tests/roms/bus_timing.s`: ROM-free program (ROM/RAM loops, VDP port writes,
      68K->VRAM DMA, Z80 streaming banked ROM); `make -C verilator test-roms`
- [x] Compared `perf68k` over 60 steady frames:

      | | ref (ideal memory) | dut (SDRAM) |
      |---|---|---|
      | 68K clocks lost to ROM/RAM waits | 0.84% | 0.89% |
      | lost to VDP DMA | 44.86% | 44.90% |
      | lost to Z80 bus | 10.04% | 10.23% |
      | accesses with an extra wait | 0 | 0.5% (3,724 of ~715k) |
      | ROM / VDP accesses done | 543,986 / 23,016 | 542,823 / 22,879 |

- [x] Conclusion: SDRAM, posted writes and VRAM-in-SDRAM cost about 0.05% of 68K
      time; no fix needed. The extra waits (one 68K clock on 0.5% of accesses) are the
      only visible difference.
- [ ] Later: a `dma_timing` program for VDP status/FIFO timing in H32/H40

## 4. YM2612 state on reset (done)

- [x] `make -C verilator jt12-reset`: a sustained note survived a /IC reset at full
      level (registers, key-on and envelopes are all in non-resetting shift registers)
- [x] `jt12_sh_rst` shifts the reset value in while `rst` is held; the note now stops
- [x] FPGA fit and timing (DB9: 20,541/20,736 logic, 10,353/10,368 CLS, 44/46 BSRAM;
      tight, clk_sys 64.0 MHz)
- [x] Hardware check: no audible difference in normal play (change kept)

## Later

- [ ] Gowin removed-logic warnings check
- [ ] Formal properties for VDP H/V counters
- [ ] BlastEm diff testing for the self-written programs
