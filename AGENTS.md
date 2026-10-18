# Agent notes for Gen Thang

Gen Thang is a Sega Genesis core for the Tang Nano 20K (GW2AR-18). Accuracy work is checked
against BlastEm with the sibling `genthangverify` repository (see its `AGENTS.md`).

## Before changing core timing

Read the **Regression-sensitive** section at the top of [docs/known-issues.md](docs/known-issues.md)
first. Small 68K bus-timing changes (refresh, DMA bus hand-over, DTACK, wait states) shift when
games' raster-dependent writes land, and different games depend on different phases. A change that
fixes its target scenario has repeatedly broken others:

- Refresh phase across DMA: `d294e0f` fixed Aladdin `scenes-6` but broke Alien 3 `boot-7` and the
  SOR2 trash-can demo, and was reverted. The refresh code in `src/system.sv` carries a warning.

Rules for timing changes:

1. One passing target scenario is not evidence of an improvement. Run the scenarios listed in
   known-issues for the area you touch, then a full overnight campaign, and compare it job by job
   with the previous version (`genthangverify/campaigns/...`, `./mdv campaign brief DIR --baseline ...`).
2. BlastEm is the reference, not hardware truth. If variants only trade failures, keep the current
   behaviour and record the trade-off in `docs/known-issues.md`.
3. Do not relax comparison tolerances or add game-specific delays to make a scenario pass.

## FPGA fit

The design is close to full (about 97% logic, 100% CLS before the fit work). After any RTL change,
run a real Gowin build, not only Verilator:

```sh
GOWIN_HOME=~/Downloads/Gowin_V1.9.11.03_Education_Linux ./build.sh
```

Check that placement succeeds (no `PR0003 ... unPlaced`) and that timing has no negative slack
(`impl/pnr/*_tr_content.html`). Builds share `impl/`, so do not run two in one checkout; use a copy.
`GT_SERIAL_UPLOAD=1` (USB serial upload) has very little headroom.

## Simulation

- `verilator/`: `make ref` (Genesis core, ideal memory) and `make dut` (whole board: menu CPU,
  SDRAM, SD card). See the README's simulation section.
- `genthangverify` builds its own testbench from `src/` with the Genesis core only; it does not
  exercise the menu CPU (iosys) or the SDRAM controller.
