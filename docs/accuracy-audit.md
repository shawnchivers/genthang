# Static accuracy audit (no game ROMs)

Branch `static-accuracy-analysis`. Everything here comes from reading source, lint and
diffs against the upstream cores, with no commercial ROMs. Issued builds have been
tested on hardware; this audit concerns accuracy relative to an original Genesis,
not release test status. Each proposed change needs a targeted accuracy check first.

Upstreams compared: [MDTang](https://github.com/nand2mario/mdtang) `903d30c` and
[Genesis_MiSTer](https://github.com/MiSTer-devel/Genesis_MiSTer) `adc0c42` (its final
commit). [MegaDrive_MiSTer](https://github.com/MiSTer-devel/MegaDrive_MiSTer) is now
Nuked-MD, a different design, so its VDP/CPU fixes do not apply.

## Summary

| # | Finding | Area | Risk | Fix effort |
|---|---|---|---|---|
| 1 | Per-game quirks never enabled (no cartridge-ID detection) | system | **High** for listed titles | Small |
| 2 | Z80, YM2612 and PSG run 0.57% fast and are not paused by frame lock | clocks | Medium | Medium |
| 3 | Z80 accesses to the 68K bus stall up to ~73 µs once per frame | clocks/bus | Medium | Small/medium |
| 4 | VRAM moved from BRAM to SDRAM (VDP slot/DMA timing now depends on SDRAM) | VDP/bus | Medium | Measure first |
| 5 | Fast ROM/RAM path and posted 68K writes differ from upstream DTACK timing | bus | Medium | Measure first |
| 6 | Soft reset does not clear YM2612 shift registers | audio | Medium | Small |
| 7 | 6-button pad counter saturates at 4 (intentional since 1.4.2) | I/O | Low/medium | n/a |
| 8 | Smaller items: unused port C/serial registers, power-on HV phase, VDP accuracy relative to original Genesis hardware | various | Low | n/a |

No accuracy fixes from Genesis_MiSTer are missing. Except as noted, jt12, jt89, fx68k
and T80 match upstream (Gen Thang only changes `X` defaults and the ladder maths).

## 1. Upstream differences

Gen Thang vs MDTang changed lines: `system.sv` 458, `vdp.v` 291, `gen_io.sv` 247,
`fx68k.sv` 28, `fx68kAlu.sv` 16. These are classified below.

- **Quirks tied off** (`src/md20k_core.sv`, the `system` instance): `SRAM_QUIRK`,
  `SRAM00_QUIRK`, `EEPROM_QUIRK`, `NORAM_QUIRK`, `PIER_QUIRK`, `SVP_QUIRK`,
  `FMBUSY_QUIRK`, `SCHAN_QUIRK` and `FAST_FIFO` are all `0`. The logic that uses them
  is still in `system.sv` (lines ~904-1078, 1441). MiSTer sets them from the cartridge
  serial at header offset `$183` (`Genesis.sv` ~979-1004). Titles affected:
  - FM busy: Hellfire (US/JP/EU), Twin Hawk, Tecmo World Cup (MegaDrive_MiSTer `9c98c6e`)
  - No-RAM: Puggsy (fake RAM check)
  - SRAM: NFL Quarterback Club / '96, NBA Jam TE, College Slam, Frank Thomas Big Hurt
  - SRAM00: Sonic 1 Remastered
  - FIFO (`FAST_FIFO`): Clue
  - SCHAN: Game no Kanzume Otokuyou
  - Pier Solar mapper (its EEPROM and SVP are documented as unsupported)
- **VRAM in SDRAM** (`system.sv` ~435, `md20k_core.sv` ~281): MDTang acknowledges VRAM in one
  cycle from BRAM; Gen Thang goes through `sdram_md20k` req/ack.
- **Fast ROM/RAM path** (`system.sv` ~887-910) skips `MBUS_SELECT`/`WAIT_FOR_S4`.
  **Posted writes** (`system.sv` ~1155-1165, not in MDTang) give DTACK before the SDRAM
  write completes.
- **68K refresh** re-added (2 cycles every 128, phase reset on BGACK), described as a
  known trade-off in CHANGELOG 1.8.0. 68K reads of the Z80 area take one wait state
  (matches BlastEm).
- **YM2612**: `jt12_sh_rst` has no reset (from MDTang), so `SOFT_RESET` leaves
  operator/envelope state.
- **VDP changes beyond upstream** (accuracy relative to original Genesis hardware needs comparison):
  `REG0[5]` left-column blank, two-slot VRAM writes outside 128K mode, split VRAM copy,
  window-edge scroll fix, hflip sprite pixel-limit clip, power-on HV phase.
  Spot-checked as unchanged: sprite per-line/frame limits, interlace mode 2, VSRAM
  20-column clamp, HV latch.
- **Fixed configuration**: `PAL=0`, `EXPORT=1` (no JP/PAL region), `OBJ_LIMIT_HIGH=0`
  (hardware limits, correct), `CRAM_DOTS=0`, `VSCROLL_BUG=1`.

## 2. Tied-off and removed logic

`verilator --lint-only -Wall` on `system` gives 176 UNUSEDSIGNAL, 26 PINMISSING and
8 UNDRIVEN warnings. After removing the documented exclusions (SVP, EEPROM, BRAM
saves, Game Genie, light gun, mouse, multitap, ADPCM), the only undocumented loss is
item 1. The ladder effect is wired through `GT_LADDER`, and `gen_io` DTACK is used by
the I/O port, so both are fine.

Next step: put the Gowin synthesis "removed register/logic" warnings into the same
table so that logic optimised away by synthesis (not just in the RTL) is also covered.

## 3. Clock ratios

| Clock | Real NTSC | Gen Thang | Error |
|---|---|---|---|
| MCLK | 53.693175 MHz | 54.000 MHz | +0.571% |
| 68K (MCLK/7), VDP | frame-locked | 60.00 Hz frames vs 59.923 | +0.129% |
| Z80 (MCLK/15), YM2612 (MCLK/7 cen), PSG (MCLK/15) | | **never paused** (`system.sv` 283, 297, 319) | +0.571% |

`frame_sync.sv` keeps the 68K and VDP in step with HDMI by pausing them at line 1 for
about 0.44% of a frame (~73 µs, about one line). The sound side keeps running, which
gives:

- Music pitch about 10 cents sharp, and tempo from FM timers 0.57% fast.
- The Z80 gets about 264 extra cycles per frame relative to the 68K (60000 vs 59736).
  Drivers that count Z80 cycles against VINT drift slightly.
- **Item 3:** Z80 accesses to the 68K bus (bank reads of ROM samples) are arbitrated
  on `M68K_CLKENp` (`system.sv` ~1546), which stops during the pause. A sample fetch
  can therefore stall for up to ~73 µs once per frame, possibly a 60 Hz glitch in PCM
  drums and voices.

The PLL cannot fix this. A frame-exact MCLK would be 53.7624 MHz, but the GW2AR
phase-detector minimum (≥3 MHz) limits IDIV to ≤9, and 54 MHz is the nearest value.

Possible fixes:
1. Let the Z80 bank path run during the pause: an arbitration strobe that ignores
   `PAUSE_EN`, granted only when the 68K is halted. That removes the stall.
2. Spread the pause across the frame (one MCLK skipped every ~175) instead of one
   73 µs block. Bus behaviour then stays even, and the Z80/68K ratio can be matched by
   gating Z80/FM/PSG by the same fraction (needs ~0.44% audio rate trim).
3. Pause during VBlank instead of line 1 (smaller change; the stall moves but remains).

## 4. Bus and memory timing

ROM, 68K RAM, cartridge SRAM and VRAM all share one SDRAM. Without a ROM, the risk
can be estimated only from the structure:

- 68K ROM/RAM reads wait for `MEM_REQ == MEM_ACK`, so VDP fetches and DMA can add
  wait states that real hardware (0-wait ROM) does not.
- VDP slot timing depends on `v16`/`v32` ack latency. If a VRAM ack takes longer than
  a slot, FIFO and DMA timing stretch.
- Posted writes: a write followed by a read of the same address must be ordered (the
  state machine waits on `MEM_REQ == MEM_ACK`, which looks safe, but this needs a
  directed test).

The existing harness can already measure all of this: `verilator/perf68k.sv`
reports 68K wait states per region and clocks lost to DMA and Z80. It runs in both
`make ref` (ideal memory, BRAM VRAM) and `make dut` (SDRAM model). It just needs
input programs (item 5).

## 5. ROM-free tests

None of these need commercial software:

1. **Self-written 68K test programs** (assembled with `m68k-elf-as`, a few hundred
   bytes each). They load like a ROM into `make ref` and `make dut`. Proposed set:
   - `bus_timing`: tight `MOVE.L (A0)+` loops from ROM and RAM. Compare `perf68k`
     wait states between ref and dut, and against BlastEm/documented counts.
   - `dma_timing`: 68K→VRAM, fill and copy DMA in H32/H40, display on/off. Read
     `$C00004` (DMA busy, FIFO full) and the HV counter after each one.
   - `z80_bank`: the Z80 streams bytes from ROM through the bank register into the
     YM DAC, and the 68K timestamps with the HV counter. Shows the item 3 stall
     directly.
   - `quirk_fmbusy`: Z80 reads `$4001-$4003` (status mirrors) with and without
     the quirk.
   - `soft_reset_ym`: key on a note, pulse soft reset, check FM output is silent.
2. **Module testbenches** (fast, no CPU): VRAM req→ack latency histogram from the
   SDRAM model during DMA; `frame_sync` pause length/position; Z80 arbitration while
   `PAUSE_EN` is high.
3. **Formal properties** (SymbiYosys): VDP H/V counter sequence (H32/H40, NTSC line
   count 262, VINT at line 224/240), HINT counter reload, no MBUS state deadlock, and
   posted write ordered before the next read.
4. **Diff testing against BlastEm** for the self-written programs: both log
   HV/cycle timestamps, and the logs are compared.

## Proposed order of fixes

1. Cartridge-ID quirk detection (firmware reads the serial and sets a register, or a
   small header-capture block) for FMBUSY, NORAM, SRAM, SRAM00, SCHAN, FAST_FIFO.
2. `z80_bank` test program, then let Z80 bank accesses run during the frame-lock pause.
3. `bus_timing` / `dma_timing` programs to measure items 4 and 5 against the ideal
   reference.
4. Soft reset clears the YM2612 (or does a full YM reset on soft reset).
