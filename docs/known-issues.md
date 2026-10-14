# Known issues

## Menu "Reset game" did not always restart the game (fixed in 1.6.2)

**Symptom:** after "Reset game" the game sometimes froze, e.g. Streets of Rage 2 on a still
picture, while another "Reset game" worked.

**Cause:** the menu overlay pauses the core (the 68K clock enables stop), and the firmware
pulses the reset (`SS_RESET`, 100 ms) from inside the menu, so the whole pulse fell in the
pause. fx68k sets its reset flags on every clock, but clears them on its next T3 and only
jumps to the reset microcode on T1, both of which need the clock enables. Depending on the
T-state the 68K was paused in, the reset was lost: the 68K continued the old game while the
reset had put the Z80 (and YM2612) in reset. SOR2 then waits for its sound driver forever.

**Fix:** `md20k_core.sv` lifts the overlay pause while the reset is asserted, so the CPUs see
a clocked reset like a real reset button. Reproduced and verified in `tb_ref`
(`+sreset=<cycle> +spause=<cycles>`, `+oldpause` for the old behaviour): resets at stage-1
frames 40 and 47 hung before and restart into the SEGA logo and title now. Confirmed on
the board (1.6.2): repeated resets in SOR2 restart every time.
