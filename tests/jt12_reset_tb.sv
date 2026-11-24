`timescale 1ns/1ps
// YM2612 /IC reset (driven from the Z80 reset line) must clear the register and
// envelope shift registers: a sustained note stops and stays silent afterwards.
module jt12_reset_tb;
    reg clk = 0;
    always #5 clk = ~clk;

    reg rst = 1, cen = 0, wr_n = 1;
    reg [1:0] addr = 0;
    reg [7:0] din = 0;
    wire [7:0] dout;
    wire signed [15:0] left, right;
    integer div = 0;

    always @(posedge clk) begin                 // FM_CLKEN: MCLK / 7
        div <= div == 6 ? 0 : div + 1;
        cen <= div == 6;
    end

    jt12 dut (.rst(rst), .clk(clk), .cen(cen), .cs_n(1'b0), .addr(addr), .wr_n(wr_n),
              .din(din), .dout(dout), .en_hifi_pcm(1'b0), .ladder(1'b0),
              .snd_left(left), .snd_right(right));

    task automatic write(input [1:0] a, input [7:0] d);
        @(negedge clk); addr = a; din = d; wr_n = 0;
        repeat (14) @(negedge clk);
        wr_n = 1;
        repeat (300) @(negedge clk);            // well past the busy flag
    endtask

    task automatic reg_write(input [7:0] r, input [7:0] d);
        write(0, r);
        write(1, d);
    endtask

    integer peak;
    task automatic measure(input integer clocks);
        peak = 0;
        repeat (clocks) begin
            @(posedge clk);
            if (left > peak) peak = left;
            if (-left > peak) peak = -left;
        end
    endtask

    initial begin
        repeat (5000) @(posedge clk);
        rst = 0;
        repeat (2000) @(posedge clk);
        // channel 1: algorithm 7 (all operators to the output), full level, fast attack,
        // no decay, slowest release so the note would ring on if state survived reset
        reg_write(8'hB0, 8'h07);
        reg_write(8'hB4, 8'hC0);
        for (int op = 0; op < 4; op++) begin
            reg_write(8'h30 + 8'(op * 4), 8'h01);   // DT/MUL
            reg_write(8'h40 + 8'(op * 4), 8'h00);   // TL max volume
            reg_write(8'h50 + 8'(op * 4), 8'h1F);   // AR
            reg_write(8'h60 + 8'(op * 4), 8'h00);   // D1R
            reg_write(8'h70 + 8'(op * 4), 8'h00);   // D2R
            reg_write(8'h80 + 8'(op * 4), 8'h00);   // SL 0, RR 0
        end
        reg_write(8'hA4, 8'h22);
        reg_write(8'hA0, 8'h69);
        reg_write(8'h28, 8'hF0);                    // key on, all operators
        measure(200000);
        if (peak < 128) $fatal(1, "note did not sound before reset (peak %0d)", peak);
        $display("before reset: peak %0d", peak);

        rst = 1;                                    // ~1400 MCLK, below the YM's 192-cycle minimum
        repeat (1400) @(posedge clk);
        rst = 0;
        repeat (20000) @(posedge clk);              // let the output pipeline drain
        measure(200000);
        $display("after reset: peak %0d", peak);
        if (peak > 16) $fatal(1, "YM2612 still sounding after reset (peak %0d)", peak);
        $display("jt12 reset: registers and envelopes cleared passed");
        $finish;
    end
endmodule
