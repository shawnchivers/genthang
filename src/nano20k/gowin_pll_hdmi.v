// HDMI pixel clock PLL for Tang Nano 20K (GW2AR-18C)
// 27MHz in -> 371.25MHz out (5x 720p pixel clock). Divide by 5 (CLKDIV) in top
// to get the 74.25MHz pixel clock. The 800x480 build overrides the dividers for
// 148.5MHz = 27 * 11 / 2 (29.7MHz pixel clock, VCO 594MHz).
// SELECTABLE switches to 135MHz for 480p (27MHz pixel, VCO 540MHz).
//
// Based on snestang/src/pllr/gowin_pll_hdmi.v from SNESTang (proven on GW2AR-18C).
module gowin_pll_hdmi #(parameter IDIV = 3, parameter FBDIV = 54, parameter ODIV = 2,
                       parameter SELECTABLE = 0) (clkout, lock, clkin, mode_480p);

output clkout;
output lock;
input clkin;
input mode_480p;

wire clkoutp_o;
wire clkoutd_o;
wire clkoutd3_o;
wire gw_gnd;

assign gw_gnd = 1'b0;

wire pll_lock, pll_reset, lowres;
generate
    if (SELECTABLE) begin: selectable
        reg [1:0] mode_sync = 2'b00;
        reg mode = 1'b0;
        reg [5:0] reset_count = 6'd63;
        always @(posedge clkin) begin
            mode_sync <= {mode_sync[0], mode_480p};
            if (mode_sync[1] != mode) begin
                mode <= mode_sync[1];
                reset_count <= 6'd63;
            end else if (reset_count != 0)
                reset_count <= reset_count - 1'b1;
        end
        assign lowres = mode;
        // Hold reset for >2us after changing dividers, then wait for PLL lock.
        assign pll_reset = reset_count != 0;
    end else begin: fixed_clock
        assign lowres = 1'b0;
        assign pll_reset = 1'b0;
    end
endgenerate
assign lock = pll_lock && !pll_reset;

rPLL rpll_inst (
    .CLKOUT(clkout),
    .LOCK(pll_lock),
    .CLKOUTP(clkoutp_o),
    .CLKOUTD(clkoutd_o),
    .CLKOUTD3(clkoutd3_o),
    .RESET(pll_reset),
    .RESET_P(gw_gnd),
    .CLKIN(clkin),
    .CLKFB(gw_gnd),
    .FBDSEL(SELECTABLE ? (lowres ? 6'd59 : 6'd9) : 6'd0),
    .IDSEL(SELECTABLE ? (lowres ? 6'd63 : 6'd60) : 6'd0),
    .ODSEL(SELECTABLE ? (lowres ? 6'd62 : 6'd63) : 6'd0),
    .PSDA({gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .DUTYDA({gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .FDLY({gw_gnd,gw_gnd,gw_gnd,gw_gnd})
);

defparam rpll_inst.FCLKIN = "27";
defparam rpll_inst.DYN_IDIV_SEL = SELECTABLE ? "true" : "false";
defparam rpll_inst.IDIV_SEL = IDIV;       // 720p default: 371.25 = 27 * 55 / 4, 371.25/5 = 74.25 (720p pixel clock)
defparam rpll_inst.DYN_FBDIV_SEL = SELECTABLE ? "true" : "false";
defparam rpll_inst.FBDIV_SEL = FBDIV;
defparam rpll_inst.DYN_ODIV_SEL = SELECTABLE ? "true" : "false";
defparam rpll_inst.ODIV_SEL = ODIV;
defparam rpll_inst.PSDA_SEL = "0000";
defparam rpll_inst.DYN_DA_EN = "true";
defparam rpll_inst.DUTYDA_SEL = "1000";
defparam rpll_inst.CLKOUT_FT_DIR = 1'b1;
defparam rpll_inst.CLKOUTP_FT_DIR = 1'b1;
defparam rpll_inst.CLKOUT_DLY_STEP = 0;
defparam rpll_inst.CLKOUTP_DLY_STEP = 0;
defparam rpll_inst.CLKFB_SEL = "internal";
defparam rpll_inst.CLKOUT_BYPASS = "false";
defparam rpll_inst.CLKOUTP_BYPASS = "false";
defparam rpll_inst.CLKOUTD_BYPASS = "false";
defparam rpll_inst.DYN_SDIV_SEL = 2;
defparam rpll_inst.CLKOUTD_SRC = "CLKOUT";
defparam rpll_inst.CLKOUTD3_SRC = "CLKOUT";
defparam rpll_inst.DEVICE = "GW2AR-18C";

endmodule
