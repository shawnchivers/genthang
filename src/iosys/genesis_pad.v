// Genesis / Mega Drive 3- and 6-button pad on a DB9 port (pad powered from 3.3V; the
// FPGA pins are not 5V tolerant). Every scan clocks TH through four pulses, which also
// reads the extra buttons of a 6-button pad; the pause between scans lets the pad's
// counter reset. With nothing plugged in the pulled-up lines read as "no pad" and btns is 0.
//
// How long a 6-button pad needs TH idle before it resets varies (about 1-2ms on Sega pads,
// longer on some clones and at 3.3V). A scan that starts before the reset misses the
// 6-button reply; X/Y/Z/Mode then keep their last value instead of reading as released,
// and the pause doubles (2.4, 4.9, 9.7, then 19.4ms, longer than a console's once per frame).
module genesis_pad #(
    parameter FREQ = 54_000_000
) (
    input             clk,
    input       [5:0] d,            // {TR (pin 9), TL (pin 6), D3, D2, D1, D0 (pin 1)}, pulled up
    output reg        th = 1'b1,    // pin 7, select
    // active high, DualShock order {R, L, X, A, Right, Left, Down, Up, Start, Select, Y, B}
    // = Genesis {Z, X, Y, C, Right, Left, Down, Up, Start, Mode, A, B}
    output reg [11:0] btns = 12'd0
);

localparam STEP = FREQ / 250_000;   // 4us per TH level
localparam SW   = $clog2(STEP + 1);
localparam IDLE = $clog2(FREQ / 500);   // shortest pause between scans: 2^IDLE clocks, 2-4ms

reg [5:0]      d_s1, d_s2;
reg [3:0]      step = 4'd0;
reg [IDLE+3:0] cnt = 0;
reg [1:0]      gap = 2'd0;          // pause = 2^(IDLE + gap) clocks
reg            six = 1'b0;          // a 6-button pad answered the last scans
reg            pad = 1'b0;          // TH low forced D2/D3 low in this scan: a pad is there
reg            sig = 1'b0;          // D0-D3 all low on the 3rd TH low: 6-button reply
wire [5:0]     n = ~d_s2;           // lines are active low; an empty port reads all released

always @(posedge clk) begin
    {d_s2, d_s1} <= {d_s1, d};
    cnt <= cnt + 1'd1;
    if (step == 4'd8) begin
        if (cnt[IDLE + gap]) begin
            cnt <= 0;
            step <= 4'd0;
        end
    end else if (cnt[SW-1:0] == STEP) begin     // upper bits are 0 during a scan
        cnt <= 0;
        step <= step + 4'd1;
        th <= step[0] | step == 4'd7;   // next level: low on odd steps, high when done
        case (step)                 // sample the level set during this step
        4'd0:                       // TH=1: Up Down Left Right B C
            {btns[8:4], btns[0]} <= {n[5], n[3], n[2], n[1], n[0], n[4]};
        4'd1: begin                 // TH=0: Up Down 0 0 A Start
            {btns[3], btns[1]} <= {n[5], n[4]};
            pad <= d_s2[3:2] == 2'b00;
        end
        4'd5: sig <= d_s2[3:0] == 4'b0000;
        4'd6:                       // TH=1: Z Y X Mode on a 6-button pad
            if (pad && sig) begin
                {btns[11:9], btns[2]} <= {n[0], n[2], n[1], n[3]};
                six <= 1'b1;
            end else if (pad && six && gap != 2'd3) begin
                gap <= gap + 2'd1;  // the pad had not reset yet: keep X/Y/Z/Mode, wait longer
            end else begin          // 3-button pad or none
                {btns[11:9], btns[2]} <= 4'd0;
                six <= 1'b0;
                if (!pad) gap <= 2'd0;
            end
        default: ;
        endcase
    end
end

endmodule
