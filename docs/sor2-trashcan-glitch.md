# SOR2 trash-can glitch (fixed in 1.6.1)

## Symptom

In Streets of Rage 2, stage 1, the trash can sometimes showed a one-pixel vertical column
just left of it (lines ~110-135). After a first partial fix, it showed black dots on its
yellow body and a white vertical line instead. It never appeared in simulation or BlastEm,
and on the board it came and went between builds of the same source.

## Cause

The VDP sprite line buffer (`obj_ci`, one 512 x 8 BSRAM) was a Gowin true-dual-port block
(`DPB`), with one port only ever reading and the other only writing. On the board it
occasionally returned corrupted colour-index bits (yellow D or orange E read back as F =
black, or pixels as 1 = white). The logic in front of it was correct, and timing analysis
passed.

The SOR2 can's three sprites are always the last entries in the sprite list, so they are
drawn last on their lines, and the corruption showed up there.

## Fix

- All four VDP line buffers (`obj_ci`, `obj_ci2`, `bga_ci`, `bgb_ci`) use simple-dual-port
  BSRAM (`SDPB`, one write port and one read port, `src/common/sdpram_block.v`).
- The `obj_ci` write port is clocked on `~CLK` and fed straight from `CLK` registers, so its
  address, data and enable have half a period of setup and hold.
- Earlier changes are kept: the render-side clear trails the copy by one pixel (no
  same-address read and write), and the write data is 0 between writes.

Cost: none (same BSRAM count, clk_sys 60.26 MHz against 54 needed).

## How it was found

1. Hardware loop (`genthangverify/scripts/hwloop`): HDMI capture, a virtual pad over UART,
   and automatic loading and flashing over JTAG.
2. Test ROM (`genthangverify/scripts/canrom`, built from your own SOR2 dump): restores the
   stage-1 VDP state and moves only the can through all 8 pixel phases. An optional variant
   adds game-like VRAM traffic.
3. Ruled out: game behaviour (the sprite table is ordinary), logic bugs (the reference and
   full-board SDRAM simulations are pixel-exact against BlastEm), and congestion (a build
   without audio at 65% logic still glitched).
4. Proof: a checker build drew the picture from a LUT-RAM copy of `obj_ci` and lit LED 1
   when the BSRAM disagreed. The glitch was gone and the LED came on, so the BSRAM was
   corrupting data.
5. The SDPB build was confirmed clean on the board. A LUT-RAM line buffer also works, but it
   doesn't fit with audio.

## Lessons

- Clean simulation and passing timing don't prove a BSRAM configuration is reliable on the
  GW2AR-18. For one-read, one-write buffers, use SDPB, not DPB.
- When a bug follows placement, add a LUT-RAM copy of the suspect memory and compare
  the two on chip.

Debug build option added along the way: `GT_NO_SOUND=1` (no FM/PSG/filters, ~35% of the logic).
