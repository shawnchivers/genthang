# Known issues

## Menu "Reset game" does not always restart the game

**Status:** open. Workaround: use "Load another game" and pick the same ROM. That does a
full reset with the ROM reloaded from the TF card, like power-on.

**Seen:** Streets of Rage 2 (USA), 2026-10-13. After "Reset game" the game stopped on its
SEGA logo and stayed there for minutes: the picture was static and the 68K made no
progress. Another "Reset game" a few minutes later restarted it normally. The user
reports the same in other games: reset works sometimes, not always.

**What "Reset game" does:** firmware `OPT_RESET` (`firmware/firmware.c`) writes
`SS_RESET` to the save-state control register, waits 100 ms and for the buttons to be
released, then clears it. In `md20k_core.sv` that value (`ss_ctrl[2:0] == 3'b110`) is
`reset_btn`, the system's `SOFT_RESET`. It resets the CPUs while SDRAM and the rest of the
console state stay live, matching a short press of a real reset button (X-Men needs that).
The same value also asserts `SS_NMI` and `SS_ZFREEZE` for the whole pulse, and all three
are released together.

**Suspects (not yet examined):**
- State that a real reset clears and the soft reset does not: Z80 bus request/reset
  registers, YM2612/PSG, VDP FIFO/DMA or interrupt state, cartridge mapper registers.
- The release order of the reset, NMI and Z80 freeze bits (one cycle apart after the
  2-flop synchronizer).
- SOR2 hangs on the SEGA logo, where it starts its Z80 sound driver; that points at the
  Z80/YM state.

**How to reproduce with the hardware loop:** a `GT_VPAD` debug build plus
`genthangverify/scripts/hwloop/` can press "Reset game" repeatedly and check the picture
keeps moving (`tcloop.wait_alive`). The loop itself now restarts games through "Load
another game" because of this issue.
