# Known issues

## Regression-sensitive: 68K refresh timing around DMA (read before changing it)

The 68K DRAM-refresh scheduler in [system.sv](../src/system.sv) (search for "68K DRAM
refresh") restarts its 128-cycle interval when a 68K-to-VDP DMA releases the bus
(`ff8f6f3`). Small changes to this phase move CPU bus cycles by a few clocks, which
changes when palette, VRAM and HV-counter-dependent writes land relative to the raster.
Different games depend on different phases, so a change that fixes one game can break
others:

| Variant | Aladdin `scenes-6` | Alien 3 `boot-7` | SOR2 trash-can demo |
|---|---|---|---|
| Before `ff8f6f3` (`08dbf6c`) | passes | **30 frames fail** | passes |
| `ff8f6f3`, restart after DMA (current) | **1 frame fails** (7 px) | passes | passes |
| `d294e0f`, free-running phase (reverted) | passes | **30 frames fail** | **1 frame fails** (16 px) |

`d294e0f` was pushed and then reverted on 2026-10-18 after the overnight campaign on
`7cdd2bf` showed these regressions. Before changing refresh, DMA bus hand-over, DTACK or
other 68K bus-cycle timing:

1. Run the three scenarios above, not just the one you are fixing. The campaign specs
   are in `genthangverify/campaigns/genthang-overnight-20261015/campaign.db` (job names
   `scenes-6`, `boot-7`, `library-sor2-demo-trashcan.json`).
2. Run a full overnight campaign and compare it job by job against the previous
   version. A single target scenario passing is not evidence of an improvement.
3. BlastEm is the reference, not hardware truth. If the variants only trade failures,
   keep the current behaviour and record the result here.

## Overnight differential follow-up (2026-10-17)

These results follow the `genthang-overnight-20261015` campaign. They have been verified
in simulation, not on the FPGA.

### Fixed, then reverted

- **Aladdin `scenes-6`:** the refresh-timing change `ff8f6f3` introduced seven early-white
  pixels at frame 81 during a palette transition. Registers and VDP memories matched
  after the transition. `d294e0f` kept the 128-cycle refresh phase across DMA bus
  ownership changes, and the 120-frame reproduction passed **106/106 compared frames**.
  **This was reverted:** the next campaign showed it broke Alien 3 `boot-7` and the SOR2
  trash-can demo (see the table above). Aladdin `scenes-6` is open again, with one frame
  failing.

### Fixed

- **Brett Hull Hockey 95 `boot-31`: verifier defect, not a renderer fix.** The verification
  top advertised `0x400000` ROM words (8 MiB), masking unbanked cartridge SRAM at
  `$200001`. Save writes were discarded and reads hit ROM padding. The active adapter
  now supplies the actual loaded word count, including appended resume data.
  A generated `cart-sram` probe reproduces the old failure and now reads back both
  bytes correctly. The original boot scenario now passes **600/600 frames**, previously
  46 failing with a 53,849-pixel worst difference. CRAM and VRAM also match at frames
  455-457, where the divergence began.

### Still open or reclassified

- **Streets of Rage 1 `boot-16`: mostly temporal alignment, not new large image
  corruption.** The (since reverted) refresh change `d294e0f` preserved all 600 DUT frame CRCs from the latest
  overnight binary. The strict comparison still reports 56 failures at offset +1,
  versus 52 in the baseline. Only DUT frames 338, 339, 343 and 347 changed between
  those binaries. In both runs, reference frame 78 is the only frame without an exact
  match within two frames of the selected offset; its aligned difference is 337 pixels.
  The reported 50,236-pixel difference at frame 367 is zero at offset 0. A single
  global offset cannot describe the changing transition timing. The strict comparator
  and its tolerances have **not** been relaxed; the frame-78 transition remains an
  open interrupt-timing discrepancy, reduced below.
- **Death Duel `boot-54`: HV-sensitive game-state divergence.** Both random seeds are
  zero through frame 252. The game's routine at `$2D9A` mixes the live HV counter into
  the seed at work RAM `$FF77FC`; seeds and generated sprite positions differ at frame
  253, before the first visible mismatch at 254. Sprite-table VRAM then differs.
  The 280-frame capture reproduces the failure, but does not establish which CPU/VDP
  timing is hardware-correct. No sprite-renderer workaround was applied.
- **Timing probes:** H40 elapsed-time decoding now uses 210 counter steps per line,
  not 211 (`00-B6`, then `E5-FF`). Old numeric reports need redecoding. Remaining
  differences include FIFO active cost (reference 382, DUT 375), DMA fill/copy cost
  (1101/1094 versus 1088/1082), and active 68K DMA cost (reference 34812, DUT 34813
  with the current refresh restart; 34820 with the reverted `d294e0f`). HINT logging includes an initial pending sample, not evidence of
  two extra sustained interrupts. The H40-to-H32 line-150 picture discrepancy is
  confined to border/stale-buffer padding outside the 256 active pixels. Six-button
  timeout differences remain hardware-uncertain.

### SOR1 transition reduced to a pending-interrupt race

A 20-frame replay from reference state 77 reproduces the partial-logo transition:
18/19 aligned frames match, with a single 342-pixel difference. Private CPU/VDP tracing
preserves all 20 frame CRCs on each backend. Both enable display and VINT on line 101;
the difference is not a frame-long delay in enabling the display.

The game immediately follows that register write with `SR=$2700`. Genthang services
the already-pending VINT before this mask and before the game sets its frame-wait
flag. That handler skips the palette work. BlastEm reaches the frame-wait setup
before servicing the interrupt, so its palette becomes visible during the logo's
scanout. Genthang uploads that palette at the next VBlank instead.

The generated `vint-enable-mask` probe isolates this without game code: with immediate
SR masking, BlastEm records zero interrupts and Genthang one; with one intervening
NOP, both record one. A private delayed-mask game control makes the short replay
**20/20 frames exact**. This is a diagnostic control, **not a game or core fix**.
Which interrupt-sampling boundary matches real hardware is still unverified.
No speculative IRQ delay, ROM patch, or comparison relaxation was applied to the
production core or verifier. The audit records this as `hardware-uncertain`.

### Validation and limits

Calibration, all three smoke scenarios, all three accuracy scenarios, and the new CPU
palette, DMA palette and cartridge-SRAM probes pass on the combined build. The focused
probe/catalog unit suite now passes 16 tests. The SOR1 follow-up reran all three
palette/SRAM probes successfully and verified that the accepted combined simulator
binary is unchanged. The new interrupt probe intentionally reports the unresolved
zero-versus-one service difference, not a pass. The earlier full verifier suite ran 103 tests with
two pre-existing errors in the legacy sprite-latency experiment (`obj_ci instance not
found`); those experiments were not changed. No FPGA synthesis, timing closure or
board validation was performed. Other campaign cases have not been requalified.

See the [verification workflow and probes](../../genthangverify/README.md#source-audit-and-probes)
for replaying the checks.

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
