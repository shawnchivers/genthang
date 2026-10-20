# O1 prototype manufacturing release

## Upload

**OSH Park is the recommended PCB manufacturer for people within the USA.** Upload `dual-db9-opt-O1-OSHPARK.zip` to OSH Park.
`dual-db9-opt-O1-KYCON-gerbers.zip` is the generic bare-board fabrication archive.
Do not upload the routed KiCad file as a substitute for the Gerbers. This design has
through-hole assembly only; no stencil, paste layers, or SMT centroid are required.

## Order parameters

| Parameter | Value |
|---|---|
| Board size | 100 × 70 mm |
| Layers | 2 |
| Material | FR-4, Tg ≥130 °C |
| Thickness | 1.6 mm |
| Copper | 1 oz outer layers |
| Finish | ENIG, RoHS/lead-free |
| Solder mask | Both sides; OSH Park standard purple (generic export originally specified green) |
| Silkscreen | White, top |
| Electrical test | 100% flying probe |
| Quantity | Prototype quantity first |

Request separate plated and nonplated drills. Confirm that the four 2.70 mm mounting
holes are nonplated and that the vendor can hold the requested plated-hole tolerance
before ordering. There are no slots or internal cutouts.

## Required review before payment

1. Confirm the quoted board is 100 × 70 mm and the DB9 overhang is not interpreted as
   board material.
2. Confirm the archive contains separate `PTH.drl` and `NPTH.drl` files.
3. Reject any request to merge or plate the four mounting holes.
4. If assembly is requested, require the exact Harwin M20-7822046 and Kycon
   K22X-E9P-N parts; substitutions are not approved.
5. Review the vendor's rendered top and bottom previews against `board-top.svg` and
   `board-bottom.svg`.

## Release evidence

- Native KiCad DRC: zero violations, zero unconnected pads, zero footprint errors.
- Independent connectivity, drill, placement, firmware-pinout, and schematic equivalence audit: pass.
- Gerber ZIP integrity test: pass.
- Release-file SHA-256 manifest: `SHA256SUMS`.

This is ready for a prototype fabrication order, not a production-qualified release.
The controller ports supply 3.3 V from the Nano. Tested with SEGA OEM 3- and 6-button controllers, including hot-plugging.
