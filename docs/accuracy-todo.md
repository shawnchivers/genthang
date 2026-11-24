# Accuracy work tracker

Background and evidence for each item: [accuracy-audit.md](accuracy-audit.md).

## 1. Per-game quirk detection (in progress)

- [x] Firmware reads the cartridge serial (`$183-$18A`) during load and matches it
      against the MiSTer quirk table
- [x] Quirk bits travel with the existing load-finish write (`$02000030`, bits 9-15)
      and drive `system` inputs
- [x] Quirks enabled: FMBUSY, NORAM, SRAM, SRAM00, EEPROM (read stub), SCHAN, FAST_FIFO
- [x] Tests: firmware table/bit packing, register latch
- [x] FPGA fit and timing (DB9 default build: 20,035/20,736 logic, 10,233/10,368 CLS,
      clk_sys 66.2 MHz / 54, no negative slack)
- [ ] Flash test image `builds/quirks/` (local, not committed)
- [ ] Hardware check with the titles in `game-compatible.txt`:
  - [ ] Hellfire (FMBUSY)
  - [ ] Twin Hawk (FMBUSY)
  - [ ] Tecmo World Cup (FMBUSY)
  - [ ] Puggsy (NORAM)
  - [ ] NBA Jam TE (SRAM)
  - [ ] NFL Quarterback Club (SRAM)
  - [ ] Sonic 1 Remastered (SRAM00)
  - [ ] Clue (FAST_FIFO)

Not planned: Pier Solar mapper (needs its EEPROM) and SVP; both stay unsupported.

## 2. Z80 bank stall during frame-lock pause

- [ ] `z80_bank` ROM-free test program showing the ~73 µs stall
- [ ] Let Z80 accesses to the 68K bus proceed while the 68K is paused
- [ ] Re-run test; hardware listen test (PCM drums)

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
