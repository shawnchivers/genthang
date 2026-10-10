# Changelog

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
