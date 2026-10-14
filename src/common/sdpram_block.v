// Simple dual-port BSRAM (Gowin SDPB): one write port (clkw) and one read port (clkr).
// For line buffers that only ever write on one port and read on the other; it avoids the
// true-dual-port (DPB) same-address read/write behaviour, which the simulation model does
// not reproduce.
module sdpram_block #(
    parameter ADDR_WIDTH = 9,
    parameter DATA_WIDTH = 8        // 4, 8 or 16
)(
    input                       clkw,
    input      [ADDR_WIDTH-1:0] addr_w,
    input      [DATA_WIDTH-1:0] din,
    input                       we,
    input                       clkr,
    input      [ADDR_WIDTH-1:0] addr_r,
    output     [DATA_WIDTH-1:0] dout
);
`ifndef VERILATOR
wire [31:0] do32;
wire [13:0] ada = DATA_WIDTH == 4 ? {addr_w, 2'b0} : DATA_WIDTH == 8 ? {addr_w, 3'b0} : {addr_w, 4'b0011};
wire [13:0] adb = DATA_WIDTH == 4 ? {addr_r, 2'b0} : DATA_WIDTH == 8 ? {addr_r, 3'b0} : {addr_r, 4'b0000};
SDPB #(
    .READ_MODE(1'b0), .BIT_WIDTH_0(DATA_WIDTH), .BIT_WIDTH_1(DATA_WIDTH),
    .BLK_SEL_0(3'b000), .BLK_SEL_1(3'b000), .RESET_MODE("SYNC")
) sdpb (
    .CLKA(clkw), .CEA(we), .RESETA(1'b0), .ADA(ada), .DI({{(32-DATA_WIDTH){1'b0}}, din}), .BLKSELA(3'b000),
    .CLKB(clkr), .CEB(1'b1), .RESETB(1'b0), .OCE(1'b1), .ADB(adb), .DO(do32), .BLKSELB(3'b000)
);
assign dout = do32[DATA_WIDTH-1:0];
`else
reg [DATA_WIDTH-1:0] ram[0:2**ADDR_WIDTH-1];
reg [DATA_WIDTH-1:0] q;
always @(posedge clkw) if (we) ram[addr_w] <= din;
always @(posedge clkr) q <= ram[addr_r];
assign dout = q;
`endif
endmodule
