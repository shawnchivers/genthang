// SPI-mode SDHC card model, sampled on the system clock. CS is ignored (the core
// ties DAT3 low). Sector data comes from the C++ testbench (sd.img) through DPI.
// Supports CMD0/8/55/ACMD41/58/17/24, which is what firmware/spi_sd.c uses.
module sd_card_model (
    input             clk,
    input             sck,
    input             mosi,
    output reg        miso,
    output reg [31:0] errors,
    output reg [31:0] blocks_read
);

import "DPI-C" function int sd_img_read(input int addr);
import "DPI-C" function void sd_img_write(input int addr, input int data);

reg        sck_d;
reg [2:0]  bitn;
reg [7:0]  rx, tx;
reg [7:0]  q [0:1023];
reg [9:0]  qh, qt;
reg [7:0]  cmdb [0:5];
reg [2:0]  cmdn;
reg        app, inited;
reg [1:0]  wst;
reg [9:0]  wcnt;
reg [31:0] waddr;

initial begin
    miso = 1'b1;
    tx = 8'hFF;
    sck_d = 1'b0;
    bitn = 3'd0;
    qh = 10'd0;
    qt = 10'd0;
    cmdn = 3'd0;
    app = 1'b0;
    inited = 1'b0;
    wst = 2'd0;
    errors = 0;
    blocks_read = 0;
end

task automatic push(input [7:0] b);
    q[qt] = b;
    qt = qt + 10'd1;
endtask

task automatic do_cmd;
    reg [5:0]  c;
    reg [31:0] arg;
    c = cmdb[0][5:0];
    arg = {cmdb[1], cmdb[2], cmdb[3], cmdb[4]};
    push(8'hFF);                                // Ncr
    case (c)
    6'd0:  begin inited = 1'b0; push(8'h01); end
    6'd8:  begin push(8'h01); push(8'h00); push(8'h00); push(8'h01); push(8'hAA); end
    6'd55: push(inited ? 8'h00 : 8'h01);
    6'd41: if (app) begin inited = 1'b1; push(8'h00); end else push(8'h04);
    6'd58: begin push(8'h00); push(8'hC0); push(8'hFF); push(8'h80); push(8'h00); end
    6'd17: begin
        push(8'h00); push(8'hFF); push(8'hFE);
        for (int i = 0; i < 512; i++) push(sd_img_read(arg * 512 + i));
        push(8'hFF); push(8'hFF);
        blocks_read = blocks_read + 1;
    end
    6'd24: begin push(8'h00); wst = 2'd1; waddr = arg * 512; end
    default: begin
        push(8'h04);
        errors = errors + 1;
        $display("SD: unsupported CMD%0d arg %08h", c, arg);
    end
    endcase
    app = (c == 6'd55);
endtask

task automatic got_byte(input [7:0] b);
    if (wst == 2'd1) begin
        if (b == 8'hFE) begin wst = 2'd2; wcnt = 10'd0; end
    end else if (wst == 2'd2) begin
        if (wcnt < 10'd512) sd_img_write(waddr + wcnt, b);
        wcnt = wcnt + 10'd1;
        if (wcnt == 10'd514) begin              // data + CRC: accepted, then busy
            push(8'h05); push(8'h00); push(8'h00);
            wst = 2'd0;
        end
    end else if (cmdn == 3'd0) begin
        if (b[7:6] == 2'b01) begin cmdb[0] = b; cmdn = 3'd1; end
    end else begin
        cmdb[cmdn] = b;
        cmdn = cmdn + 3'd1;
        if (cmdn == 3'd6) begin cmdn = 3'd0; do_cmd(); end
    end
endtask

always @(posedge clk) begin
    reg [7:0] r;
    reg rise, fall;
    rise = sck && !sck_d;
    fall = !sck && sck_d;
    sck_d = sck;
    if (rise) begin                             // sample MOSI
        r = {rx[6:0], mosi};
        rx = r;
        bitn = bitn + 3'd1;
        if (bitn == 3'd0) got_byte(r);
    end else if (fall) begin                    // next MISO bit
        if (bitn == 3'd0) begin
            if (qh != qt) begin tx = q[qh]; qh = qh + 10'd1; end
            else tx = 8'hFF;
        end else
            tx = {tx[6:0], 1'b1};
        miso = tx[7];
    end
end

endmodule
