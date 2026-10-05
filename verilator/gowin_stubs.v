// Port-compatible stubs of Gowin primitives, for Verilator lint of the board top only.
module rPLL #(parameter FCLKIN = "27", parameter DYN_IDIV_SEL = "false", parameter IDIV_SEL = 0,
    parameter DYN_FBDIV_SEL = "false", parameter FBDIV_SEL = 0, parameter DYN_ODIV_SEL = "false",
    parameter ODIV_SEL = 8, parameter PSDA_SEL = "0000", parameter DYN_DA_EN = "false",
    parameter DUTYDA_SEL = "1000", parameter CLKOUT_FT_DIR = 1'b1, parameter CLKOUTP_FT_DIR = 1'b1,
    parameter CLKOUT_DLY_STEP = 0, parameter CLKOUTP_DLY_STEP = 0, parameter CLKFB_SEL = "internal",
    parameter CLKOUT_BYPASS = "false", parameter CLKOUTP_BYPASS = "false", parameter CLKOUTD_BYPASS = "false",
    parameter DYN_SDIV_SEL = 2, parameter CLKOUTD_SRC = "CLKOUT", parameter CLKOUTD3_SRC = "CLKOUT",
    parameter DEVICE = "GW2AR-18C")
(
    output CLKOUT, output LOCK, output CLKOUTP, output CLKOUTD, output CLKOUTD3,
    input RESET, input RESET_P, input CLKIN, input CLKFB,
    input [5:0] FBDSEL, input [5:0] IDSEL, input [5:0] ODSEL,
    input [3:0] PSDA, input [3:0] DUTYDA, input [3:0] FDLY
);
assign {CLKOUT, CLKOUTP, CLKOUTD, CLKOUTD3} = {4{CLKIN}};
assign LOCK = 1'b1;
endmodule

module CLKDIV #(parameter DIV_MODE = 2, parameter GSREN = "false")
    (output CLKOUT, input HCLKIN, input RESETN, input CALIB);
assign CLKOUT = HCLKIN;
endmodule

module ELVDS_OBUF (input I, output O, output OB);
assign O = I;
assign OB = ~I;
endmodule

module OSER10 #(parameter GSREN = "false", parameter LSREN = "true")
    (output Q, input D0, D1, D2, D3, D4, D5, D6, D7, D8, D9, input PCLK, input FCLK, input RESET);
assign Q = D0;
endmodule
