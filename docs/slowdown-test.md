# 68K wait states and busy-scene slowdown (2026-10-02)

## Problem
SOR2 slowed down in busy scenes, first in the stage 3 boat scene with the two ninjas.

## Cause
`MBUS_WAIT_FOR_S4` in `src/system.sv` (from mdtang) held every 68K access until S4.
DTACK then arrived too late, so every ROM/RAM/VDP/IO access took one wait state.
A real Genesis has none on ROM/RAM.

Measured with `verilator/perf68k.sv` in the reference model, over the same 60 frames:

| | ROM/RAM wait states | 68K time lost | ROM accesses |
|---|---|---|---|
| before | 1 per access | 18.2% | 1,339,475 |
| after  | 0 | 0.0% | 1,644,418 (+23%) |

## Fix (src/system.sv)
- 68K reads skip `MBUS_WAIT_FOR_S4`. Writes still wait, because UDS/LDS are only valid from S4.
- ROM/RAM/SRAM reads raise DTACK and data in the same clock that SDRAM acks, without going
  through `MBUS_FINISH`.
- 68K writes to work RAM are posted. DTACK goes out at once, and the bus returns to idle
  when SDRAM acks (`wr_posted`).

Build: logic 90%, CLS 95%, BSRAM 42/46, clk_sys Fmax 54.33 MHz, no negative slack.

## Side effects to watch for
The 68K now uses more SDRAM time and has priority over the VDP's VRAM fetches in
`sdram_md20k.v`, so VDP fetches can be delayed more than before. Possible symptoms
are flickering tiles, dropped sprites, or a hang in a specific scene (which would
point at the posted-write path: a read overtaking a write is designed out but has
not been exercised exhaustively). If glitches appear, try in this order:
1. Give the VDP's v32 port priority over the 68K during active display.
2. Revert posted writes.
3. Revert the early-read change (this brings back the slowdown).

## Boat scene test (save state)
`verilator/mkresume.py game.md slot_0.state out.md` turns a BlastEm native save state into a
ROM whose reset vector restores the state: VRAM, CRAM, VSRAM, VDP registers, work RAM, 68K
registers, Z80 RAM and registers, YM registers and Z80 bank. It runs in BlastEm, both
testbenches and on the board. `Streets of Rage 2 (USA) [Boat].md` starts on the ship with the
two ninjas.

68K time lost in the boat scene, per second of play:

| | ROM/RAM waits | VDP DMA | Z80 bus |
|---|---|---|---|
| reference (ideal memory) | 0.00% | 1.8% | 1.0% |
| board, first fix only | 2.65% | 1.8% | 1.0% |
| board, + SDRAM read pipelining + early read | 0.10% | 1.8% | 1.0% |

With the first fix only, the board fell 2-3 frames behind the reference within 5 s of the
scene. The second round:
- `sdram_md20k.v` starts a READ to another bank 2 cycles after the previous READ. Reads
  complete through a small per-read delay line. A client with a read in flight is not
  re-selected until its ack; without that check, duplicate reads acked the VDP's next request
  with stale data and garbled the picture. A WRITE waits until the last READ is 2 cycles old.
- `system.sv` starts plain ROM / work RAM reads directly from MBUS_IDLE, skipping SELECT.

Build: logic 92%, CLS 96%, BSRAM 42/46, clk_sys Fmax 54.10 MHz (tight but positive).

## Notes
- The fix changes game timing, so frame hashes from before it no longer match the
  reference core; compare against a reference built from the same `system.sv`.
- The testbench never asserts the HDMI `pause_core` frame lock, so it does not
  exercise that path.
- `Streets of Rage 2 (USA) [Boat].md` is a locally produced test ROM and is not
  distributed with this repository.
