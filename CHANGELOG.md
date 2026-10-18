# Changelog

## Unreleased

- **USB serial upload removed from the default build** so the design fits the GW2AR-18
  again. Since the VDP slot-timing change (`08dbf6c`) every build failed placement by
  42-348 LUTs at 100% CLS. The iosys UART is now only built with `GT_SERIAL_UPLOAD=1`
  (which fits with the register-file change below, but with only 9 spare CLS); without
  it the menu ignores the serial port and its debug output, and releases no longer ship
  the upload tools. Copy ROMs and core images to the card in a card reader.
- The menu's PicoRV32 uses a single-read-port register file (`ENABLE_REGS_DUALPORT=0`),
  halving its distributed RAM. The menu CPU takes an extra cycle for instructions with
  two source registers.
- Result: logic 97% (20101/20736), CLS 10270/10368, timing met on all clocks
  (clk_sys 62.6 MHz against 54 MHz). Not yet tested on the board.
- 68000 refresh keeps its 128-cycle phase across DMA bus hand-overs (fixes seven wrong
  pixels in an Aladdin palette transition; see `docs/known-issues.md`).

## 1.6.2 - 2026-10-14

- Fixed the menu's "Reset game" sometimes freezing the game (for example Streets of Rage 2
  stopping on a still picture). The menu overlay pauses the core, and the reset was sent
  entirely inside that pause. The fx68k 68000 only takes a reset when its clock enables run
  while it is held, so depending on where the CPU was frozen the reset was lost. The 68000
  then carried on with the old game while the Z80 and YM2612 had been reset. The pause is now
  lifted while the reset is asserted. Tested on the board with repeated resets in SOR2.
- Verilator `tb_ref`: `+sreset`, `+sreset_len`, `+spause`, `+oldpause` and `+sprobe` reproduce
  and inspect a menu reset.

## 1.6.1 - 2026-10-13

- Fixed the Streets of Rage 2 stage 1 trash-can glitch (a stray pixel column beside the
  can, or black dots and a white line on it). The VDP line buffers now use Gowin
  simple-dual-port BSRAM instead of true dual-port, whose sprite buffer returned corrupted
  colour bits on the board although simulation and timing were clean. The sprite buffer
  write port runs on the falling clock edge, fed straight from registers. See
  `docs/sor2-trashcan-glitch.md`.
- Added the `GT_NO_SOUND=1` build option (debug builds without FM, PSG and audio filters).
- Known issue: the menu's "Reset game" can hang some games (`docs/known-issues.md`).

## 1.6.0 - 2026-10-11

- Added a **Video output** menu option: HDMI (default) or DVI. DVI sends the picture
  without HDMI data islands and therefore without audio. An LG 50PN6500 plasma pulsed
  on mid and dark tones whenever any data island was present, whatever it carried;
  standalone HDMI tests showed DVI and island-free output were stable. The setting is
  saved in `GENTHANG.CFG` (third character), which older firmware ignores.
- Added a stereo 3.5 mm line-out on DB9 and raw builds: 1-bit sigma-delta audio on
  FPGA pins 31 (left, J6 row 14) and 56 (right, J5 row 7), filtered off board with
  1 kOhm, 10 nF and 10 uF per channel. It works in HDMI and DVI modes. The menu shows the DVI setting as
  "Video output: DVI+LINE OUT". Without the filter the jack is not hot-pluggable.
- Restored 68K DRAM refresh timing: every 128 CPU cycles the next 68K bus cycle
  waits 2 cycles, as on the console. CPU-bound code no longer runs ~1.6% fast.
- 68K writes to the VDP no longer take an extra wait state when the VDP FIFO has
  room. Together these match BlastEm's bus timing in the genthangverify probes
  and fix Flicky running two frames ahead of the reference.
- The menu's serial port baud divider is now fixed at 115200 baud (the only
  rate the firmware uses) to free logic for the timing fix.

## 1.5.2 - 2026-10-10

- Fixed X/Y/Z/Mode on wired 6-button DB9 pads repeatedly triggering while held.
  The pad reader restarted its handshake every ~2 ms, before some pads' TH
  counters had reset, so those scans read the extra buttons as released. A
  missed 6-button reply now keeps the previous X/Y/Z/Mode state and doubles the
  pause between scans (from about 2.4 ms up to 19 ms, longer than a console
  polling once per frame); pads that reset quickly keep the short poll. Button
  changes are also reported right after each scan instead of one pause later.
- The `genesis-pad` Verilator test now models 6-button pads with 1-12 ms reset
  times and fails on any change of a held button. Bench-tested on the DB9 build
  with a wired six-button pad on P1.

## 1.5.1 - 2026-10-10

- Made the canonical dual-DB9 J6/J5 controller mapping the default and deprecated
  the separate DualShock layout. DualShock source remains available for archival
  builds but is no longer included in releases.
- Consolidated all non-DualShock controller wiring on the dual-DB9 J6/J5 pinout.
  The raw build now uses the same 12 data GPIOs as DB9 and omits only the two TH
  outputs. The DualShock constraints are unchanged.
- Replaced the separate DB9 breadboard release variants with one `db9` image.
  `GT_PINOUT=breadboard` and `breadboard-rev1` remain warning-producing aliases
  for canonical DB9; the duplicate constraint files were removed.

## 1.5.0 - 2026-10-09

- Removed the nonfunctional CRAM-dots menu option and forced the VDP option off.
  Settings files written by v1.4.2 remain readable.
- Added a dual-DB9 `breadboard-rev1` build matching the two-controller perfboard
  pinout in the Genthang hardware repository.

## 1.4.2 - 2026-10-09

- Fixed the Genesis six-button controller phase counter so the extended response
  occurs once per handshake instead of repeating every fourth rapid poll.
- Added a runtime **CRAM dots** option to the menu. It defaults to off, persists
  in `GENTHANG.CFG`, and preserves settings files written by earlier releases.
- Built and timing-checked the DualShock, raw-button, and DB9 breadboard images;
  the controller, smoke, and VDP accuracy regressions all pass.

## 1.4.1 - 2026-10-08

- Corrected per-line sprite-cell overflow handling for partially budgeted
  horizontally flipped sprites; the rendered cell selection now matches
  BlastEm in the covered Verilator comparisons. Physical hardware overflow
  ordering is not independently confirmed.
- Enabled timing-priority placement and timing-directed routing for the DS,
  raw, and DB9 breadboard release builds.

## 1.4.0 - 2026-10-08

- VDP accuracy, found with genthangverify against BlastEm: the sprite line buffer RAM is
  clocked on `CLK` here (Genesis_MiSTer uses `~CLK`), which made the "is this pixel already
  taken" read lag one pixel, so overlapping sprites lost or replaced pixels and the sprite
  collision flag was wrong. Sprite part three now issues the read two pixels ahead and
  primes the first two pixels of every tile (two extra cycles per sprite tile). Sonic 2 and
  Streets of Rage 2 scenes that differed on every frame now match BlastEm.
- `VSCROLL_BUG` is now 1 (hardware behaviour of the partial left column with per-column
  vertical scroll) instead of the MiSTer "nicer" option 0.
- Consolidated the project into the standalone `genthang` repository with a clean
  root commit while retaining the earlier development record below.
- Clarified the project's lineage: Gen Thang adapts MDTang, bringing its spirit to
  the much smaller Tang Nano 20K.
- New `db9_breadboard` image and `GT_PINOUT=breadboard` build option: single Genesis
  pad on a nine-wire DB9 breakout that avoids the Nano's HDMI-sideband GPIOs. Built
  and timing-checked, and bench-tested with a wired six-button Genesis pad.
- The two-pad stock DB9 image and its wiring notes are no longer part of this
  repository (the wiring is kept in the hardware repository).
- Build selection variables renamed `MDX_PAD` / `MDX_PINOUT` to `GT_PAD` / `GT_PINOUT`;
  Gowin outputs are now named `genthang_nano20k*`.
- `release.sh` builds the `ds`, `raw` and `db9_breadboard` variants, fails on missed
  clocks or negative slack, and packages a tarball with `SHA256SUMS`.
- Source headers now say which files are based on MDTang, Genesis_MiSTer and
  SNESTang; added `THIRD_PARTY.md`.
- Documentation rewritten: DualShock 2 and breadboard wiring, display options,
  save states, and screenshots identified explicitly as Gen Thang Verilator output.
- Gowin builds use `GOWIN_HOME`, `GW_SH` or `gw_sh` on `PATH`; no installation
  directory is assumed.
- Verilator `Makefile` no longer assumes a ROM path or tool locations; added
  `verilator/hdmi_preview.py` to preview scanlines and composite blend on dumped
  frames.
