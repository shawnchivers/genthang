`timescale 1ns/1ps
module jt12_ladder_tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg clk_en = 1, ladder = 0;
    reg signed [8:0] sample = 0;
    reg [1:0] pan = 0;
    wire signed [15:0] left, right;
    reg signed [15:0] expected_left, expected_right;
    integer offset_left, offset_right;
    integer checks = 0;

    jt12_acc dut (
        .rst(1'b0), .clk(clk), .clk_en(clk_en), .ladder(ladder),
        .channel_en(1'b0), .op_result(9'sd0), .rl(2'b00), .zero(1'b0),
        .s1_enters(1'b0), .s2_enters(1'b0), .s3_enters(1'b0), .s4_enters(1'b0),
        .ch6op(1'b0), .alg(3'd0), .pcm_en(1'b0), .pcm(9'sd0),
        .left(left), .right(right)
    );

    initial begin
        // Isolate the output arithmetic from the upstream accumulator and pan pipeline.
        force dut.acc_out = sample;
        force dut.rl_old = pan;
        for (int enabled = 0; enabled < 2; enabled++)
        for (int panning = 0; panning < 4; panning++)
        for (int value = -256; value < 256; value++) begin
            @(negedge clk);
            clk_en = 1;
            ladder = 1'(enabled);
            pan = 2'(panning);
            sample = 9'(value);
            offset_left = !enabled ? 0 : (value >= 0 ? 7 : (pan[1] ? 0 : -6));
            offset_right = !enabled ? 0 : (value >= 0 ? 7 : (pan[0] ? 0 : -6));
            expected_left = 16'(pan[1] ? value + offset_left : offset_left);
            expected_right = 16'(pan[0] ? value + offset_right : offset_right);
            @(posedge clk);
            #1;
            if (left !== expected_left || right !== expected_right)
                $fatal(1, "ladder=%0d pan=%b sample=%0d: got %0d/%0d expected %0d/%0d",
                       enabled, pan, value, left, right, expected_left, expected_right);
            checks++;

            @(negedge clk);
            clk_en = 0;
            ladder = ~ladder;
            pan = ~pan;
            sample = ~sample;
            @(posedge clk);
            #1;
            if (left !== expected_left || right !== expected_right)
                $fatal(1, "Outputs changed with clock enable low");
        end
        $display("JT12 ladder: %0d sample/panning/mode combinations and clock-enable holds passed", checks);
        $finish;
    end
endmodule
