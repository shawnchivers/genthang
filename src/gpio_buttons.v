// Player 1 buttons wired straight to FPGA pins (active low, external pull-ups).
// Two-flop synchronizer, ~2ms debounce, and opposite D-pad directions cancel.
module gpio_buttons #(
    parameter FREQ = 54_000_000
) (
    input             clk,
    input       [7:0] btn_n,        // {start, c, b, a, up, down, left, right}, active low
    output reg [11:0] joy           // Genesis order: Z Y X Mode Start C B A Up Down Left Right
);

localparam TICK = FREQ / 1000;      // 1ms sample tick

reg [7:0] sync1 = 8'hFF, sync2 = 8'hFF;
reg [7:0] s0 = 8'hFF, s1 = 8'hFF, s2 = 8'hFF;
reg [7:0] stable = 8'hFF;
reg [$clog2(TICK)-1:0] tick_cnt = 0;

always @(posedge clk) begin
    sync1 <= btn_n;
    sync2 <= sync1;

    tick_cnt <= tick_cnt + 1'd1;
    if (tick_cnt == TICK - 1) begin
        tick_cnt <= 0;
        s0 <= sync2;
        s1 <= s0;
        s2 <= s1;
        // a button changes state only after three equal samples (>=2ms)
        stable <= (s0 & s1 & s2) | (stable & (s0 | s1 | s2));
    end
end

wire [7:0] p = ~stable;             // active high
wire right = p[0] & ~p[1];
wire left  = p[1] & ~p[0];
wire down  = p[2] & ~p[3];
wire up    = p[3] & ~p[2];

always @(posedge clk)
    joy <= {4'b0000, p[7], p[6], p[5], p[4], up, down, left, right};

endmodule
