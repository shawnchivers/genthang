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

## 2. Z80 bank stall during frame-lock pause (in progress)

- [x] Spread the frame-lock pause: 14 MCLK (two 68K cycles) every 3434 MCLK, so the
      remaining once-per-frame halt drops from ~3960 MCLK (73 us) to ~306 (5.7 us)
- [x] `make -C verilator frame-sync`: lock holds, no dropped frames, pause lengths
- [x] FPGA fit and timing (DB9: 20,221 logic, 10,313/10,368 CLS, clk_sys 64.3 MHz)
- [ ] Hardware listen test with sample-heavy games (`builds/spread-pause/`, local)
- [ ] Optional: `z80_bank` ROM-free test program to measure stalls end to end

## 3. Bus and memory timing measurement

- [ ] `bus_timing` and `dma_timing` test programs
- [ ] Compare `perf68k` wait states in `make ref` and `make dut`
- [ ] Decide on fixes from the numbers

## 4. YM2612 state on soft reset

- [ ] Sim: key on, soft reset, check FM is silent
- [ ] Reset jt12 shift registers on soft reset if needed

## Later

- [ ] Gowin removed-logic warnings check
- [ ] Formal properties for VDP H/V counters
- [ ] BlastEm diff testing for the self-written programs
