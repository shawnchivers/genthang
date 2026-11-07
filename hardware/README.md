# Gen Thang hardware

Hardware that accompanies the Gen Thang firmware lives here, separate from the
FPGA sources and the wiring illustrations in `docs/hardware/`.

| Design | Files | Physical status |
|---|---|---|
| [Dual-DB9 carrier, O1](dual-db9-opt-pcb/README.md) | KiCad PCB and schematic, Gerbers, BOM, assembly and continuity-test guides | Fabricated |
| [Standalone L3 dual-DB9 carrier with line-out](dual-db9-lineout-pcb/README.md) | KiCad PCB/schematic, L3 Gerbers, BOM, capacitor chooser and illustrated assembly guide | GPIO17 audio tested by author; L3 submitted to OSH Park |
| [Giger-inspired biomechanical case](dual-db9-biomech-case/README.md) | Printable base/lid STLs, editable STEP model, CadQuery source and renders | Printed |

Start with the [illustrated DB9 + biomech console build guide](dual-db9-opt-pcb/index.html)
for parts, printing, soldering, electrical checks, firmware setup and complete
case assembly. The page works offline and can be printed as a bench reference.

For powered-speaker audio, use the separate
[L3 line-out build guide](dual-db9-lineout-pcb/index.html), with
simple [capacitor choices](dual-db9-lineout-pcb/index.html#caps) and electrical
checks. L3 uses GPIO31 left / GPIO17 right and is not the O1 biomech carrier.

## Ordering the PCB

**OSH Park is the recommended PCB manufacturer for people within the USA.** Upload the
[OSH Park fabrication ZIP](dual-db9-opt-pcb/dual-db9-opt-O1-OSHPARK.zip).
A [generic Gerber archive](dual-db9-opt-pcb/dual-db9-opt-O1-KYCON-gerbers.zip)
is also included.
Read the [fabrication notes](dual-db9-opt-pcb/MANUFACTURING-RELEASE.md)
and [assembly guide](dual-db9-opt-pcb/ASSEMBLY.md) before ordering or powering a board.
The controller ports supply 3.3 V from the Nano. Tested with SEGA OEM 3- and 6-button controllers, including hot-plugging.

For L3 instead, upload the
[L3 OSH Park ZIP](dual-db9-lineout-pcb/dual-db9-lineout-L3-OSHPARK.zip),
not an O1 or historical L1/L2 archive. The
[standalone package](dual-db9-lineout-pcb/IMPORT.md) includes all ordering and
assembly files without requiring a sibling repository.
Read the [L3 test status](dual-db9-lineout-pcb/TEST-STATUS.md) and use the
[GPIO17 firmware](../builds/db9-gpio17/genthang_nano20k_db9_gpio17_flash.bin).

## Working with the designs

The design folders retain their original names and revision filenames so the
PCB, case, fabrication archives and scripts refer to the same revision. O1,
the biomechanical case and the standalone L3 carrier are imported from the
separate hardware development repository; L3's source revision is recorded in
[IMPORT.md](dual-db9-lineout-pcb/IMPORT.md).

`cad-python`, `design.py`, `mechanical.py`, `generate.py` and
`check_and_import.py` are shared PCB-generation helpers. The wrapper uses an
installed KiCad Python environment or the author's rootless KiCad installation.
From `hardware/dual-db9-opt-pcb/`:

```sh
../cad-python build_board.py check
../cad-python -m unittest test_board
```

For L3, from `hardware/dual-db9-lineout-pcb/`:

```sh
bash ../cad-python -m unittest discover -s . -p 'test_build_board.py'
bash ../cad-python build_board.py check
bash ../cad-python build_board.py checksums
```

Regeneration uses `generate`, `route`, `import`, then `export` actions in that
order. Routing currently expects Java 21 and Freerouting under
`~/.local/kicad-pkg/`, as specified in `build_board.py`; inspection and ordering
do not require regenerating anything. Checks and exports overwrite generated
reports, and `export` refreshes the release checksum manifest.

See the [case instructions](dual-db9-biomech-case/README.md#files-and-rebuild)
for CadQuery model generation and mesh checks. USB ROM upload requires a
`GT_SERIAL_UPLOAD=1` firmware build; the standard build does not enable it.
