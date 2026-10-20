# Gen Thang hardware

Hardware that accompanies the Gen Thang firmware lives here, separate from the
FPGA sources and the wiring illustrations in `docs/hardware/`.

| Design | Files | Physical status |
|---|---|---|
| [Dual-DB9 carrier, O1](dual-db9-opt-pcb/README.md) | KiCad PCB and schematic, Gerbers, BOM, assembly and continuity-test guides | Fabricated |
| [Giger-inspired biomechanical case](dual-db9-biomech-case/README.md) | Printable base/lid STLs, editable STEP model, CadQuery source and renders | Printed |

## Ordering the PCB

**OSH Park is the recommended PCB manufacturer for people within the USA.** Upload the
[OSH Park fabrication ZIP](dual-db9-opt-pcb/dual-db9-opt-O1-OSHPARK.zip).
A [generic Gerber archive](dual-db9-opt-pcb/dual-db9-opt-O1-KYCON-gerbers.zip)
is also included.
Read the [fabrication notes](dual-db9-opt-pcb/MANUFACTURING-RELEASE.md)
and [assembly guide](dual-db9-opt-pcb/ASSEMBLY.md) before ordering or powering a board.
The controller ports supply 3.3 V from the Nano. Tested with SEGA OEM 3- and 6-button controllers, including hot-plugging.

## Working with the designs

The design folders retain their original names and O1 filenames so the PCB,
case, fabrication archives and scripts refer to the same revision. Only these
two designs are imported from the separate hardware development repository.

`cad-python`, `design.py`, `mechanical.py`, `generate.py` and
`check_and_import.py` are shared PCB-generation helpers. The wrapper uses an
installed KiCad Python environment or the author's rootless KiCad installation.
From `hardware/dual-db9-opt-pcb/`:

```sh
../cad-python build_board.py check
../cad-python -m unittest test_board
```

Regeneration uses `generate`, `route`, `import`, then `export` actions in that
order. Routing currently expects Java 21 and Freerouting under
`~/.local/kicad-pkg/`, as specified in `build_board.py`; inspection and ordering
do not require regenerating anything. Checks and exports overwrite generated
reports, and `export` refreshes the release checksum manifest.

See the [case instructions](dual-db9-biomech-case/README.md#files-and-rebuild)
for CadQuery model generation and mesh checks. USB ROM upload requires a
`GT_SERIAL_UPLOAD=1` firmware build; the standard build does not enable it.
