# Two-player Genesis carrier — O1 (reassigned-pin PCB)

**PCB version of the canonical two-controller pinout**
(`GT_PAD=db9`, see the
[controller wiring guide](../../README.md#3-connect-a-controller)).
No resistors, logic
ICs, pull-ups, fuses or level shifters; the FPGA's internal pull-ups bias the inputs.

| Fitted part | Qty | Exact part |
|---|---:|---|
| Female Nano socket | 2 | Harwin M20-7822046, 1×20, 2.54 mm, 8.5 mm tall |
| Right-angle male DB9 | 2 | Kycon K22X-E9P-N |

The Nano plugs into the sockets and stays removable (it needs downward male pins; Harwin
M20-9992046 is a documented mate). Nothing but copper and four through-hole parts.

## Why this board looks different from the other dual boards

Because the pins are reassigned, **player 1 is entirely on the left socket row (J6) and
player 2 entirely on the right (J5)**. Each DB9 sits at the bottom edge on its own side of
the Nano, nothing crosses the module, and neither port uses the LED-loaded GPIO17-20, so
no buffers are needed for them. The board is 100×70 mm, two layers.

## Connections (from the GenThang constraints file)

Nano top view: USB-C up, J6 left, J5 right, contact 1 nearest USB. DB9 pins are numbered
as on the Kycon part. Both ports' pin 8 / shell / boardlocks are ground; pin 5 is 3.3 V.

| DB9 pin | Function | Player 1 (J1) | Player 2 (J2) |
|---|---|---|---|
| 1 | D0 / Up | GPIO73 — J6.1 | GPIO42 — J5.5 |
| 2 | D1 / Down | GPIO74 — J6.2 | GPIO41 — J5.6 |
| 3 | D2 / Left | GPIO77 — J6.5 | GPIO51 — J5.9 |
| 4 | D3 / Right | GPIO27 — J6.8 | GPIO48 — J5.10 |
| 5 | 3.3 V supply | 3V3 — J6.19 | 3V3 — J5.16 |
| 6 | TL (B / A) | GPIO28 — J6.9 | GPIO49 — J5.12 |
| 7 | TH select (output) | GPIO29 — J6.12 | GPIO72 — J5.17 |
| 8 | Ground | GND — J6.20 | GND — J5.15 |
| 9 | TR (C / Start) | GPIO30 — J6.13 | GPIO71 — J5.18 |

J5.1 (Nano 5 V) and every other socket contact have **no carrier connection**.
[net-test.csv](net-test.csv) lists every connection for continuity testing. The
authoritative pin source is `genthang/src/boards/nano20k_db9.cst`; the
generator reads it, a copy is in [reference/built-pinout.cst](reference/built-pinout.cst),
and the audit fails if the PCB, schematic or constraints disagree.

Player 2 uses two inputs with side effects on the Nano: **GPIO49** (LCD backlight boost
enable) and **GPIO51** (audio amplifier shutdown) — pad *inputs only*. Keep the Nano's
LCD connector and speaker header empty. Load the canonical `GT_PAD=db9` image.

## Files

- [Routed KiCad PCB](dual-db9-opt-pcb.kicad_pcb), [schematic PDF](schematic.pdf)
- [Top copper](board-top.svg), [bottom copper](board-bottom.svg), [assembly top](assembly-top.svg),
  [1:1 fit print](fit-1to1.svg)
- [Gerbers + drills](fabrication/), [generic fabrication ZIP](dual-db9-opt-O1-KYCON-gerbers.zip),
  [OSH Park order ZIP](dual-db9-opt-O1-OSHPARK.zip)
- [BOM](BOM.csv), [assembly notes](ASSEMBLY.md), [fabrication settings](FABRICATION.txt)
- [Parts sourcing and purchase links](PARTS-SOURCING.md)
- [Manufacturing release checklist](MANUFACTURING-RELEASE.md), [DRC](drc.txt),
  [validation](validation.json), [test status](TEST-STATUS.md), [checksums](SHA256SUMS)

## Mechanics

- 100×70 mm, 2 layers, 1.6 mm FR-4, 1 oz. Socket spacing 20.32 mm; J6/J5 at x = 39.84 / 60.16 mm.
- J1 / J2 (Kycon K22X-E9P-N) at the bottom edge, noses overhanging 6.1 mm, envelopes
  clear of each other, the Nano and the board sides; the HDMI plug has the gap between them.
- Power/ground 0.60 mm, signals 0.30 mm, clearance 0.25 mm, 0.8/0.4 mm vias.
- Four nonplated 2.7 mm mounting holes at (5,5), (95,5), (5,45), (95,45).
- DB9 pins 6, 7, 9 of player 1 and pin 6 of player 2 are hand-routed on the top layer down
  the 0.87 mm gaps between back-row pads (0.285 mm clearance); the rest is auto-routed.
  Some copper passes under the connector bodies, covered by solder mask.

## Limits

No ESD diode, port fuse, series resistor or 5 V buffer. The controller ports supply
3.3 V from the Nano. Tested with SEGA OEM 3- and 6-button controllers, including hot-plugging.

## PCB ordering

**OSH Park is the recommended PCB manufacturer for people within the USA.** Use the [OSH Park ZIP](dual-db9-opt-O1-OSHPARK.zip).
A generic Gerber archive is also included.

## Reproduce

Via `../cad-python`: `build_board.py generate`, `route` (Freerouting), `import`
(also runs the audit and native DRC), `export`. `test_board.py` holds mutation tests.
See the [tooling notes](../README.md#working-with-the-designs) for dependencies.
