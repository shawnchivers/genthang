# Deprecated controller pinouts

These layouts are retained for reproducing older hardware and firmware only.
They are not included in current releases. New designs should use the single
canonical J6/J5 physical pinout documented in the main README:

- `GT_PAD=db9` for Genesis controllers.
- `GT_PAD=raw` for twelve direct switches on the same twelve data GPIOs.

## DualShock 2 (`GT_PAD=ds`)

The deprecated `ds` build reads two DualShock 2 pads. Player 1 uses J6 contacts
15-20 and player 2 uses J5 contacts 15-20, matching Sipeed's PMOD DS2 / DS2x2
adapter.

| DualShock connector pin | Signal | Player 1 FPGA pin (contact) | Player 2 FPGA pin (contact) |
|---|---|---|---|
| 1 | DATA | 19 (J6.17) | 71 (J5.18) |
| 2 | COMMAND | 20 (J6.16) | 53 (J5.19) |
| 3 | 7.5 V motor supply | not connected | not connected |
| 4 | GND | GND (J6.20) | GND (J5.15) |
| 5 | VCC | 3.3 V (J6.19) | 3.3 V (J5.16) |
| 6 | ATT / chip select | 18 (J6.18) | 72 (J5.17) |
| 7 | CLK | 17 (J6.15) | 52 (J5.20) |
| 8 | not connected | - | - |
| 9 | ACK | not connected | not connected |

DATA uses the FPGA's internal pull-up. The pad is powered from 3.3 V; rumble and
analog sticks are not used. GPIO52 and GPIO53 are shared with the Nano's HDMI DDC
level shifter.

The source remains buildable for archival use:

```sh
GT_PAD=ds ./build.sh
```

It prints a deprecation warning and is not built by `release.sh`.

## Original single-DB9 breadboard

The first tested Genesis breadboard crossed between J6 and J5 and used a separate
`db9_breadboard` image. It is superseded by the canonical P1-on-J6 mapping. Its
complete wiring table, photographs, drawings, and bench notes remain in
[single-db9-breadboard.md](single-db9-breadboard.md).

The old `GT_PINOUT=breadboard` and `GT_PINOUT=breadboard-rev1` values are accepted
only as deprecated aliases for canonical `GT_PAD=db9`; they no longer reproduce
the retired wiring.
