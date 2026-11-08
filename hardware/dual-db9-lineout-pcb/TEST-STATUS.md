# L3 test status

## Author confirmation, 2026-11-07

The author reports that moving right audio to GPIO17 works, has tested that
configuration, and has submitted the L3 PCB files to OSH Park.
Both controller pinouts remain unchanged; left audio remains on GPIO31.

The matching pin assignment, tests and packaged firmware are already in
[GenThang main](https://github.com/shawnchivers/genthang/commit/fbf6664c5f6448510bc2a2ebbf7aaf82cb94554c).

This records author-reported audio testing and the fabrication order. It is not
an independent certification of a returned L3 PCB, every controller or cable,
or production reliability. The optional 47 nF / 56 nF filter response has not
been measured on L3.

## Official firmware

The standard DB9 flash image in
[GenThang v1.9.3](https://github.com/shawnchivers/genthang/releases/tag/v1.9.3)
replaces the provisional GPIO17 packages, with GPIO31 left audio, GPIO17 right
audio and matching 1.9.3 menu firmware. See the [firmware downloads](README.md#firmware).
The official variants passed build and timing checks. The preceding GPIO17/L3
ladder implementation was confirmed working on hardware; the fresh v1.9.3 images
were not newly flashed for that release.

## CAD and fabrication checks

- Native DRC: zero violations and zero unconnected pads.
- PCB/schematic equivalence and canonical DB9 pin mapping: pass.
- GPIO31 left / GPIO17 right audio routing: pass.
- Three 0.60 x 1.40 mm plated jack slots and OSH Park drill/annular-ring checks: pass.
- Regression tests check connector placement, cable corridors, silkscreen,
  archive contents and rejection of invalid slot geometry.

[validation.json](validation.json) is a generated CAD report. Its
`manufactured_pcb_tested: false` field is not updated by the CAD checker and does
not encode the later author-reported GPIO17 bench test above.

## Limits

No ESD qualification, controller port fuse, level shifter or 5 V-tolerant input
is provided. Controller supply is 3.3 V only. Disconnect power before plugging
or unplugging controllers and before changing parts or wiring.
Line-out is for powered speakers or an amplifier, not direct headphones.
