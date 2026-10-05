# Changelog

## 1.4.0-alpha - unreleased

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
