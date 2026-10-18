// Mono I2S transmitter for the Tang Nano 20K's on-board MAX98357A speaker amplifier.
// 48 kHz, 64 BCLK per frame (32-bit slots, Philips I2S: MSB one BCLK after the LRCK edge).
// BCLK (3.072 MHz) comes from a fractional divider of clk (54 MHz): 54e6 / (2 * 3.072e6)
// = 1125 / 128, so edges are 8 or 9 clocks apart (within the amp's jitter tolerance).
// The same (L+R)/2 sample, attenuated by 6 dB per ATTEN step, goes in both slots, so
// any SD_MODE channel setting plays it. Kept small because the FPGA is nearly full.
module i2s_tx #(
    parameter INC   = 128,
    parameter MOD   = 1125,
    parameter ATTEN = 2
) (
    input             clk,
    input      [15:0] left,     // signed PCM
    input      [15:0] right,
    output reg        bclk  = 1'b0,
    output reg        lrck  = 1'b0,
    output reg        din   = 1'b0,
    output reg        frame = 1'b0  // one-clock pulse at the start of each frame
);

wire signed [16:0] sum  = $signed(left) + $signed(right);
wire signed [16:0] mono = sum >>> (ATTEN + 1);

reg  [10:0] ph = 11'd0;
wire [11:0] ph_next = ph + INC;
wire        edge_now = ph_next >= MOD;
reg  [5:0]  bitn = 6'd0;
wire [5:0]  bitn_next = bitn + 6'd1;
reg  [15:0] sh = 16'd0;

always @(posedge clk) begin
    frame <= 1'b0;
    ph <= edge_now ? ph_next - MOD : ph_next;
    if (edge_now) begin
        bclk <= ~bclk;
        if (bclk) begin             // falling edge: the amp samples on the rising edge
            bitn <= bitn_next;
            lrck <= bitn_next[5];
            din  <= sh[15];
            sh   <= bitn_next[4:0] == 5'd0 ? mono[15:0] : {sh[14:0], 1'b0};
            frame <= bitn_next == 6'd0;
        end
    end
end

endmodule
