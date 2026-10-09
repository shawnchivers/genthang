# Gowin build for Gen Thang on the Tang Nano 20K (GW2AR-18C)
#   ./build.sh                -> impl/pnr/genthang_nano20k.fs, DualShock pads
#   GT_PAD=db9 ./build.sh     -> Genesis pads on DB9 (stock pin table; not released)
#   GT_PAD=raw ./build.sh     -> 12 direct buttons (handheld)
#   GT_PAD=db9 GT_PINOUT=breadboard ./build.sh -> single-DB9 breadboard wiring,
#                                impl/pnr/genthang_nano20k_db9_breadboard.fs

set_device GW2AR-LV18QN88C8/I7 -device_version C

source build_config.tcl
puts "GT_PAD=$pad GT_PINOUT=$pinout CST=$pad_cst OUTPUT=$output_base"
# selects the pad ports in mdtang_top.sv (the checked-in default is GT_PAD_DS)
set f [open src/pad_config.vh w]
puts $f "`define GT_PAD_[string toupper $pad]"
close $f

# board layer
add_file -type cst     $pad_cst
add_file -type sdc     "src/mdtang.sdc"
add_file -type verilog "src/mdtang_top.sv"
add_file -type verilog "src/md20k_core.sv"
add_file -type verilog "src/nano20k/gowin_pll_sys.v"
add_file -type verilog "src/nano20k/gowin_pll_hdmi.v"
add_file -type verilog "src/memory/sdram_md20k.v"
add_file -type verilog "src/iosys/dualshock_controller.v"
add_file -type verilog "src/iosys/genesis_pad.v"

# iosys: PicoRV32 menu system (iosys_picorv32.v must come before picorv32.v)
add_file -type verilog "src/iosys/iosys_picorv32.v"
add_file -type verilog "src/iosys/picorv32.v"
add_file -type verilog "src/iosys/textdisp.v"
add_file -type verilog "src/iosys/simpleuart.v"
add_file -type verilog "src/iosys/simplespimaster.v"
add_file -type verilog "src/iosys/spiflash.v"
add_file -type verilog "src/iosys/spi_master.v"

# HDMI
add_file -type verilog "src/framebuffer_sync.sv"
add_file -type verilog "src/frame_sync.sv"
add_file -type verilog "src/hdmi/audio_clock_regeneration_packet.sv"
add_file -type verilog "src/hdmi/audio_info_frame.sv"
add_file -type verilog "src/hdmi/audio_sample_packet.sv"
add_file -type verilog "src/hdmi/auxiliary_video_information_info_frame.sv"
add_file -type verilog "src/hdmi/hdmi.sv"
add_file -type verilog "src/hdmi/packet_assembler.sv"
add_file -type verilog "src/hdmi/packet_picker.sv"
add_file -type verilog "src/hdmi/serializer.sv"
add_file -type verilog "src/hdmi/source_product_description_info_frame.sv"
add_file -type verilog "src/hdmi/tmds_channel.sv"

# Genesis: system, 68000, Z80, VDP, IO
add_file -type verilog "src/system.sv"
add_file -type verilog "src/common/dpram.v"
add_file -type verilog "src/common/dpram32_block.v"
add_file -type verilog "src/common/dpram_block.v"
add_file -type verilog "src/fx68k/fx68k.sv"
add_file -type verilog "src/fx68k/fx68kAlu.sv"
add_file -type verilog "src/fx68k/uaddrPla.sv"
add_file -type verilog "src/t80/t80.v"
add_file -type verilog "src/t80/t80_alu.v"
add_file -type verilog "src/t80/t80_mcode.v"
add_file -type verilog "src/t80/t80_reg.v"
add_file -type verilog "src/t80/t80s.v"
add_file -type verilog "src/vdp/vdp.v"
add_file -type verilog "src/vdp/vdp_common.v"
add_file -type verilog "src/peripherals/gen_io.sv"
add_file -type verilog "src/peripherals/genesis_lpf.v"
add_file -type verilog "src/peripherals/audio_iir_filter.v"

# FM: YM2612 (JT12)
foreach f [concat [glob src/jt12/*.v] [glob src/jt12/adpcm/*.v] [glob src/jt12/mixer/*.v]] {
    add_file -type verilog $f
}

# PSG: SN76489 (jt89)
add_file -type verilog "src/jt89/jt89.v"
add_file -type verilog "src/jt89/jt89_mixer.v"
add_file -type verilog "src/jt89/jt89_noise.v"
add_file -type verilog "src/jt89/jt89_tone.v"
add_file -type verilog "src/jt89/jt89_vol.v"

set_option -synthesis_tool gowinsynthesis
set_option -top_module mdtang_top
set_option -verilog_std sysv2017
set_option -vhdl_std vhd2008
set_option -rw_check_on_ram 1
set_option -ireg_in_iob 1
set_option -oreg_in_iob 1
set_option -ioreg_in_iob 1
set_option -use_sspi_as_gpio 1
set_option -use_mspi_as_gpio 1
set_option -use_ready_as_gpio 1
set_option -use_done_as_gpio 1
set_option -use_i2c_as_gpio 1
set_option -use_cpu_as_gpio 1
if {$pad eq "ds"} {
    set_option -place_option 2       ;# timing priority
} elseif {$pad ne "db9" || $pinout ne "stock"} {
    set_option -place_option 2       ;# timing priority
}
if {$pad ne "db9" || $pinout ne "stock"} {
    set_option -route_option 1       ;# timing-directed routing
}
set_option -output_base_name $output_base

run all
