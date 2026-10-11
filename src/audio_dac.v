// Stereo 1-bit audio output for a 3.5 mm line-out jack.
// First-order sigma-delta per channel at clk_sys (54 MHz, ~1000x oversampling): the carry
// out of a 16-bit accumulator of the offset-binary sample. Kept small because the FPGA is
// nearly full. External filter per channel: pin - 1 kOhm - (10 nF to GND) - 10 uF - jack.
module audio_dac (
    input             clk,
    input      [15:0] left,     // signed PCM
    input      [15:0] right,
    output reg        out_l = 1'b0,
    output reg        out_r = 1'b0
);

reg [15:0] acc_l = 16'd0, acc_r = 16'd0;

always @(posedge clk) begin
    {out_l, acc_l} <= {1'b0, acc_l} + {1'b0, left ^ 16'h8000};
    {out_r, acc_r} <= {1'b0, acc_r} + {1'b0, right ^ 16'h8000};
end

endmodule
