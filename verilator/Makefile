# Headless Verilator testbenches for Gen Thang on the Nano 20K.
#   make ref   - golden model: Genesis core + original BRAM VRAM + ideal memory
#   make dut   - md20k_core (iosys menu softcore + firmware, SDRAM controller w/ VRAM)
#                against strict SDRAM, SPI flash and TF card models
#   make run-ref ARGS="-n 300 -d 100,200"   /   make run-dut ARGS=...
#   make textdisp - render the menu overlay alone to run/textdisp/overlay_*.ppm
# Pass your own ROM with ROM=/path/to/game.md (no ROM is shipped). The DUT boots the
# menu firmware (../firmware/firmware.bin) and loads the ROM from sd.img (FAT32).
# MTOOLS is a directory prefix for mcopy/mdir when they are not on PATH (trailing /).
ROM ?=
FIRMWARE ?= ../firmware/firmware.bin
MTOOLS ?=
D = ../src
VERILATOR ?= verilator
REF_MDIR ?= obj_ref
DUT_MDIR ?= obj_dut
CDEFS ?=

CORE = $D/system.sv $D/gpio_buttons.v \
	$D/fx68k/verilator/fx68k.sv $D/fx68k/verilator/fx68kAlu.sv $D/fx68k/verilator/uaddrPla.sv \
	$D/vdp/vdp.v $D/common/dpram_block.v $D/common/dpram.v $D/common/dpram32_block.v \
	$D/peripherals/gen_io.sv \
	$D/jt89/jt89_mixer.v $D/jt89/jt89_noise.v $D/jt89/jt89_tone.v $D/jt89/jt89_vol.v $D/jt89/jt89.v \
	$(wildcard $D/jt12/*.v $D/jt12/adpcm/*.v $D/jt12/mixer/*.v) \
	$D/peripherals/genesis_lpf.v $D/peripherals/audio_iir_filter.v \
	$D/t80/t80_alu.v $D/t80/t80.v $D/t80/t80_mcode.v $D/t80/t80_reg.v $D/t80/t80s.v

REF_SRCS = tb_ref.sv ideal_mem.sv perf68k.sv $D/vdp/vram.v $(CORE)
DUT_SRCS = tb_dut.sv perf68k.sv $D/frame_sync.sv sdram_model.sv spiflash_model.sv sd_card_model.sv $D/md20k_core.sv \
	$D/memory/sdram_md20k.v $D/iosys/iosys_picorv32.v $D/iosys/picorv32.v $D/iosys/textdisp.v \
	$D/iosys/simpleuart.v $D/iosys/simplespimaster.v $D/iosys/spiflash.v $D/iosys/spi_master.v \
	$(CORE)

VFLAGS = --cc --exe --build -j 4 -O3 --x-assign fast --x-initial fast --noassert \
	+1800-2017ext+sv -Wno-fatal -Wno-PINMISSING -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-lint -Wno-style \
	-Wno-MULTIDRIVEN -Wno-UNOPTFLAT -Wno-CASEINCOMPLETE -Wno-TIMESCALEMOD \
	-I$D -I$D/fx68k -I$D/vdp -CFLAGS "-O2"

.PHONY: ref dut run-ref run-dut hex clean textdisp genesis-pad gen-io

hex: rom8.hex fw8.hex sd.img
rom8.hex: mkhex.py
	@test -n "$(ROM)" || { echo "set ROM=/path/to/game.md"; exit 1; }
	python3 mkhex.py "$(ROM)"

# firmware as the SPI flash sees it at 0x500000 (256KB, erased bytes 0xFF)
fw8.hex: $(FIRMWARE)
	python3 -c "import sys; d=open(sys.argv[1],'rb').read(); d+=b'\xff'*(262144-len(d)); \
		open('fw8.hex','w').write('\n'.join('%02x'%b for b in d)+'\n')" $(FIRMWARE)

# 64MB FAT32 TF card image holding the ROM
sd.img:
	@test -n "$(ROM)" || { echo "set ROM=/path/to/game.md"; exit 1; }
	rm -f $@ && mkfs.vfat -C -F 32 -s 1 $@ 65536 > /dev/null
	MTOOLS_SKIP_CHECK=1 $(MTOOLS)mcopy -i $@ "$(ROM)" ::/
	MTOOLS_SKIP_CHECK=1 $(MTOOLS)mdir -i $@ ::/

ref: hex
	$(VERILATOR) $(VFLAGS) --top-module tb_ref --Mdir $(REF_MDIR) \
		-CFLAGS '-DTOP_HEADER=\"Vtb_ref.h\" -DTOP_CLASS=Vtb_ref $(CDEFS)' $(REF_SRCS) tb_main.cpp -o tb_ref

dut: hex
	$(VERILATOR) $(VFLAGS) --top-module tb_dut --Mdir $(DUT_MDIR) \
		-CFLAGS '-DTOP_HEADER=\"Vtb_dut.h\" -DTOP_CLASS=Vtb_dut -DIS_DUT $(CDEFS)' $(DUT_SRCS) tb_main.cpp -o tb_dut

run/%:
	mkdir -p $@ && cd $@ && ln -sf ../../../src/fx68k/microrom.mem ../../../src/fx68k/nanorom.mem \
		../../../src/iosys/demofont.hex ../../rom8.hex ../../rom16.hex ../../rom32.hex ../../fw8.hex \
		../../sd.img .

textdisp: run/textdisp
	$(VERILATOR) --cc --exe --build -j 4 -O3 -Wno-fatal -Wno-lint -Wno-style --top-module textdisp \
		--Mdir obj_textdisp $D/iosys/textdisp.v tb_textdisp.cpp -o tb_textdisp
	cd run/textdisp && ../../obj_textdisp/tb_textdisp 16 .

genesis-pad:
	$(VERILATOR) --cc --exe --build -j 4 -O3 -Wno-fatal -Wno-lint -Wno-style --top-module genesis_pad \
		--Mdir obj_genesis_pad $D/iosys/genesis_pad.v tb_genesis_pad.cpp -o tb_genesis_pad
	./obj_genesis_pad/tb_genesis_pad

gen-io:
	$(VERILATOR) --cc --exe --build -j 4 -O3 -Wno-fatal -Wno-lint -Wno-style --top-module gen_io_minimal \
		--Mdir obj_gen_io $D/peripherals/gen_io.sv tb_gen_io.cpp -o tb_gen_io
	./obj_gen_io/tb_gen_io

run-ref: ref run/ref
	cd run/ref && ../../$(REF_MDIR)/tb_ref $(ARGS)

run-dut: dut run/dut
	cd run/dut && ../../$(DUT_MDIR)/tb_dut $(ARGS)

clean:
	rm -rf obj_ref obj_dut obj_ref_* obj_dut_* obj_refdbg obj_dutdbg obj_ymclk obj_textdisp obj_genesis_pad obj_gen_io run rom8.hex rom16.hex rom32.hex \
		fw8.hex sd.img
