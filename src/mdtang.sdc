
// Tang Nano 20K clocks
create_clock -name sys_clk -period 37.037 -waveform {0 18.5} [get_nets {sys_clk}]     // 27MHz crystal
create_clock -name clk_sys -period 18.518 -waveform {0 9.26} [get_nets {clk_sys}]     // 54MHz Genesis master
create_generated_clock -name clk_z80 -source [get_nets {clk_sys}] -divide_by 2 [get_nets {clk_z80}]  // 27MHz
create_clock -name hclk5  -period 2.6936 -waveform {0 1.347} [get_nets {hclk5}]       // 371.25MHz 5x pixel
create_generated_clock -name hclk -source [get_nets {hclk5}] -master_clock hclk5 -divide_by 5 [get_nets {hclk}]  // 74.25MHz 720p pixel

// core -> HDMI crosses through the framebuffer's dual-clock RAM and synchronizers
set_clock_groups -asynchronous -group [get_clocks {clk_sys clk_z80}] -group [get_clocks {hclk hclk5}]

// Z80 to M68K, 2 clk_sys cycles
set_multicycle_path 4 -end -setup -from [get_clocks {clk_z80}] -to [get_clocks {clk_sys}]
set_multicycle_path 3 -end -hold -from [get_clocks {clk_z80}] -to [get_clocks {clk_sys}]

// JT12's phase increment register captures only on FM_CLKEN-derived clk_en. FM_CLKEN
// is asserted once every seven clk_sys cycles, so this endpoint has seven cycles.
set_multicycle_path 7 -setup -to [get_cells {core/megadrive/fm/u_jt12/u_pg/phinc_II*}]
set_multicycle_path 6 -hold  -to [get_cells {core/megadrive/fm/u_jt12/u_pg/phinc_II*}]

// From fx68k.txt
// micro-code fetch is needed in 2 cycles
//set_multicycle_path 4 -start -setup -from [get_pins {megadrive/M68K/Ir*/*}] -to [get_pins {megadrive/M68K/microAddr_*/*}]
//set_multicycle_path 3 -start -hold -from [get_pins {megadrive/M68K/Ir*/*}] -to [get_pins {megadrive/M68K/microAddr_*/*}]
//set_multicycle_path 4 -start -setup -from [get_pins {megadrive/M68K/Ir*/*}] -to [get_pins {megadrive/M68K/nanoAddr_*/*}]
//set_multicycle_path 3 -start -hold -from [get_pins {megadrive/M68K/Ir*/*}] -to [get_pins {megadrive/M68K/nanoAddr_*/*}]

// The update of the CCR flags is also time critical.
//set_multicycle_path 4 -start -setup -from [get_pins {megadrive/M68K/nanoLatch*/*}] -to [get_pins {megadrive/M68K/excUnit/alu/pswCcr*/*}]
//set_multicycle_path 3 -start -hold -from [get_pins {megadrive/M68K/nanoLatch*/*}] -to [get_pins {megadrive/M68K/excUnit/alu/pswCcr*/*}]
//set_multicycle_path 4 -start -setup -from [get_pins {megadrive/M68K/excUnit/alu/oper*/*}] -to [get_pins {megadrive/M68K/excUnit/alu/pswCcr*/*}]
//set_multicycle_path 3 -start -hold -from [get_pins {megadrive/M68K/excUnit/alu/oper*/*}] -to [get_pins {megadrive/M68K/excUnit/alu/pswCcr*/*}]
