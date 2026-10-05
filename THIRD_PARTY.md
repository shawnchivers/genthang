# Third-party components and notices

Gen Thang is licensed under the [GNU GPL v3](LICENSE). It is built on, and contains,
the work of the projects listed here. Original copyright notices and licence texts
are kept in the source files and in the vendored directories (for example
`src/jt12/LICENSE`); a file that Gen Thang changed says so in its header. Nothing
below should be read as the original authors endorsing or having written Gen Thang's
changes.

## Project lineage

| Project | Role |
|---|---|
| [MDTang](https://github.com/nand2mario/mdtang) (nand2mario, GPL-3.0) | Gen Thang adapts MDTang, bringing its spirit to the much smaller Tang Nano 20K. The Genesis system wrapper, the Tang-specific changes to the MiSTer sources, the Z80 clock split and the Verilog T80 come from MDTang. |
| [Genesis_MiSTer](https://github.com/MiSTer-devel/Genesis_MiSTer) and [MegaDrive_MiSTer](https://github.com/MiSTer-devel/MegaDrive_MiSTer) (MiSTer-devel, GPL-3.0) | The Genesis implementation MDTang ports: `system.sv`, the VDP, I/O block, audio filters and the 68000/Z80/FM/PSG wiring. |
| [SNESTang](https://github.com/nand2mario/snestang) (nand2mario, GPL-3.0) | The "iosys" PicoRV32 I/O subsystem and menu-firmware architecture, the synchronised HDMI framebuffer, the PLL wrappers, the menu overlay and the DualShock reader. |

## Components in this repository

| Component | Location | Author / source | Licence |
|---|---|---|---|
| FX68K 68000 core and microcode ROMs | `src/fx68k/` | Jorge Cwik, [ijor/fx68k](https://github.com/ijor/fx68k), as distributed with Genesis_MiSTer / MDTang | GPL-3.0 |
| T80 Z80 core | `src/t80/` | Daniel Wallner, MikeJ, TobiFlex, Sean Riddle and Sorgelig (T80 v350); Verilog conversion for MDTang | BSD-style, see file headers |
| VDP | `src/vdp/vdp.v`, `vdp_common.v` | Gregory Estrade (FPGAGen), Till Harbaum, Alexey Melnikov, via Genesis_MiSTer | BSD-style, see file headers |
| Genesis system and I/O | `src/system.sv`, `src/peripherals/gen_io.sv` | Gregory Estrade, Sorgelig (Alexey Melnikov), via Genesis_MiSTer / MDTang | BSD-style, see file headers |
| Audio low-pass and IIR filters | `src/peripherals/genesis_lpf.v`, `audio_iir_filter.v` | Gregory Hogan (Soltan_G42), via Genesis_MiSTer | MIT |
| JT12 (YM2612) | `src/jt12/` | Jose Tejada (jotego), [jt12](https://github.com/jotego/jt12) | GPL-3.0 |
| JT89 (SN76489) | `src/jt89/` | Jose Tejada (jotego), [jt89](https://github.com/jotego/jt89) | GPL-3.0 |
| PicoRV32 and `simpleuart.v` (PicoSoC) | `src/iosys/picorv32.v`, `simpleuart.v` | Claire Xenia Wolf, [YosysHQ/picorv32](https://github.com/YosysHQ/picorv32) | ISC |
| iosys, SPI master/flash blocks, menu overlay, DualShock reader | `src/iosys/` | nand2mario (SNESTang / MDTang), modified for Gen Thang | GPL-3.0 |
| SPI master | `src/iosys/spi_master.v` | Russell Merrick, [nandland/spi-master](https://github.com/nandland/spi-master) (the file's header carries no author line; identified from the upstream module) | MIT |
| HDMI transmitter | `src/hdmi/` | Sameer Puri, [hdl-util/hdmi](https://github.com/hdl-util/hdmi) | MIT or Apache-2.0 |
| Synchronised framebuffer / HDMI scaler | `src/framebuffer_sync.sv` | nand2mario (SNESTang / MDTang), modified for Gen Thang | GPL-3.0 |
| PLL wrappers | `src/nano20k/` | Generated with Gowin tools; the HDMI PLL follows SNESTang | GPL-3.0 |
| SDRAM controller, Nano 20K core, board top, frame sync, DB9 pad reader | `src/memory/`, `src/md20k_core.sv`, `src/mdtang_top.sv`, `src/frame_sync.sv`, `src/iosys/genesis_pad.v` | Gen Thang (the file names keep the project's MDTang lineage) | GPL-3.0 |
| FatFs R0.15 | `firmware/fatfs/` | ChaN, [elm-chan.org/fsw/ff](http://elm-chan.org/fsw/ff/) | FatFs licence (BSD-style) |
| SD card SPI driver | `firmware/spi_sd.c` | Bruno Levy (FemtoRV, [learn-fpga](https://github.com/BrunoLevy/learn-fpga)), via SNESTang / MDTang | BSD-3-Clause |
| Menu firmware, start-up code, linker script | `firmware/` | nand2mario (SNESTang / MDTang), modified for Gen Thang | GPL-3.0 |
| Menu font | `src/iosys/gen_demofont.py` | glyphs from `font8x8_basic` (Daniel Hepper), public domain; menu icons by Gen Thang | public domain / GPL-3.0 |
| 68000 save-state stub | `firmware/m68k/savestate.s` | Gen Thang | GPL-3.0 |
| Testbenches, uploader, build and release scripts | `verilator/`, `upload/`, `tests/`, `*.sh`, `*.tcl` | Gen Thang | GPL-3.0 |

Where this table and a file header disagree, the file header is authoritative.

## Tools used to produce this project

- [Gowin EDA](https://www.gowinsemi.com/) Education 1.9.11.03 (synthesis, place and route, programming).
- [Verilator](https://www.veripool.org/verilator/) 5.x for the headless simulations and screenshots.
- A RISC-V GCC toolchain (for the PicoRV32 menu firmware) and GNU binutils for m68k (for the save-state stub).
- Python 3, GNU Make and Bash for the scripts; mtools and `mkfs.vfat` for the simulated TF card images.
- GitHub Copilot (Claude models) assisted with development and documentation. All changes were reviewed by the author, and hardware behaviour was checked on a real board only where the README says so.

## Trademarks and content

Sega, Mega Drive, Genesis and the names of games are trademarks of their respective
owners. Sipeed, Tang Nano and Gowin are trademarks of their respective owners. HDMI
is a trademark of HDMI Licensing Administrator, Inc. This project is not affiliated
with or endorsed by any of them. No ROM images, BIOS files or other copyrighted game
data are included.
