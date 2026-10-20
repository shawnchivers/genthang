# Verification scope

- Native KiCad DRC: 0 violations, 0 unconnected pads (drc.txt). Independent audit
  (validation.json): pad nets vs the constraints file, socket and DB9 drills/positions,
  mounting holes, 5 V contact unconnected, no forbidden GPIOs, schematic netlist equivalence.
- `test_board.py`: 10 mutation tests show the audit rejects wrong nets, a swapped
  cross-player net, a connected LED pin, wrong drills, a reversed or moved connector.
- O1 prototype release export: Gerber/drill archive integrity and release checksums pass.
  The firmware contract is audited against the vendored built-pinout snapshot when the
  historical live `breadboard-rev1` constraint file is not present in the sibling checkout.
- The firmware pinout builds in Gowin V1.9.11.03 and meets timing (genthang docs).
- Tested with SEGA OEM 3- and 6-button controllers, including hot-plugging.
- Not done: ESD qualification; third-party controllers untested.
