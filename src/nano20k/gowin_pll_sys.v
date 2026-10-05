// System / SDRAM / Z80 clock PLL for Tang Nano 20K (GW2AR-18C)
//
//   27MHz in ->
//     clkout  = 54.0 MHz  (clk_sys : Genesis master clock, ~53.69MHz target)
//     clkoutp = 54.0 MHz  phase-shifted 315deg, drives O_sdram_clk to the
//               embedded SDRAM (sdram_md20k captures read data 3 edges after READ)
//     clkoutd = 27.0 MHz  (clk_z80 = clk_sys / 2)
//
// rPLL: fCLKOUT = FCLKIN*(FBDIV_SEL+1)/(IDIV_SEL+1) = 27*2/1 = 54MHz
//       fVCO    = fCLKOUT*ODIV_SEL = 54*16 = 864MHz (valid 400-1200MHz)
//       CLKOUTD = CLKOUT/DYN_SDIV_SEL = 54/2 = 27MHz
//
// NOTE: 54.0MHz is 0.57% above the MiSTer 53.693MHz Genesis master clock. This is
// harmless because framebuffer_sync re-syncs the core to HDMI via pause_core.
// 315deg leaves ~2ns hold / ~5ns setup on read capture over the pad-delay range
// Proven by SNESTang and Gen Thang on this chip (86MHz, 225deg, READ+3).
// Tune PSDA_SEL if needed.
module gowin_pll_sys (clkout, clkoutp, clkoutd, lock, clkin);

output clkout;         // 54MHz  clk_sys
output clkoutp;        // 54MHz  O_sdram_clk (315deg shifted)
output clkoutd;        // 27MHz  clk_z80
output lock;
input clkin;           // 27MHz

wire clkoutd3_o;
wire gw_gnd;
assign gw_gnd = 1'b0;

rPLL rpll_inst (
    .CLKOUT(clkout),
    .LOCK(lock),
    .CLKOUTP(clkoutp),
    .CLKOUTD(clkoutd),
    .CLKOUTD3(clkoutd3_o),
    .RESET(gw_gnd),
    .RESET_P(gw_gnd),
    .CLKIN(clkin),
    .CLKFB(gw_gnd),
    .FBDSEL({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .IDSEL({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .ODSEL({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .PSDA({gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .DUTYDA({gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .FDLY({gw_gnd,gw_gnd,gw_gnd,gw_gnd})
);

defparam rpll_inst.FCLKIN = "27";
defparam rpll_inst.DYN_IDIV_SEL = "false";
defparam rpll_inst.IDIV_SEL = 0;            // /1
defparam rpll_inst.DYN_FBDIV_SEL = "false";
defparam rpll_inst.FBDIV_SEL = 1;           // x2  -> 54MHz
defparam rpll_inst.DYN_ODIV_SEL = "false";
defparam rpll_inst.ODIV_SEL = 16;           // VCO = 54*16 = 864MHz
defparam rpll_inst.PSDA_SEL = "1110";       // CLKOUTP phase = 315deg (14 * 22.5)
defparam rpll_inst.DYN_DA_EN = "false";
defparam rpll_inst.DUTYDA_SEL = "1000";
defparam rpll_inst.CLKOUT_FT_DIR = 1'b1;
defparam rpll_inst.CLKOUTP_FT_DIR = 1'b1;
defparam rpll_inst.CLKOUT_DLY_STEP = 0;
defparam rpll_inst.CLKOUTP_DLY_STEP = 0;
defparam rpll_inst.CLKFB_SEL = "internal";
defparam rpll_inst.CLKOUT_BYPASS = "false";
defparam rpll_inst.CLKOUTP_BYPASS = "false";
defparam rpll_inst.CLKOUTD_BYPASS = "false";
defparam rpll_inst.DYN_SDIV_SEL = 2;        // CLKOUTD = CLKOUT/2 = 27MHz
defparam rpll_inst.CLKOUTD_SRC = "CLKOUT";
defparam rpll_inst.CLKOUTD3_SRC = "CLKOUT";
defparam rpll_inst.DEVICE = "GW2AR-18C";

endmodule
