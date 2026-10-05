// Genesis / Mega Drive 3- and 6-button pad on a DB9 port (pad powered from 3.3V; the
// FPGA pins are not 5V tolerant). Every ~2ms it clocks TH through four pulses, which
// also reads the extra buttons of a 6-button pad; the pause lets the pad's counter
// reset. With nothing plugged in the pulled-up lines read as "no pad" and btns is 0.
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
localparam IDLE = FREQ / 500;       // 2ms between scans

reg [5:0]  d_s1, d_s2;
reg [3:0]  step = 4'd0;
reg [16:0] cnt = 17'd0;
reg [5:0]  s0, s1, s5, s6;

always @(posedge clk) begin
    {d_s2, d_s1} <= {d_s1, d};
    cnt <= cnt + 17'd1;
    if (step == 4'd8) begin
        if (cnt == IDLE) begin
            cnt <= 17'd0;
            step <= 4'd0;
            if (s1[3:2] == 2'b00)   // TH low forces D2/D3 low: a pad is there
                btns <= ~{s6[0] | |s5[3:0], s6[2] | |s5[3:0], s6[1] | |s5[3:0], s0[5],
                          s0[3], s0[2], s0[1], s0[0], s1[5], s6[3] | |s5[3:0], s1[4], s0[4]};
            else
                btns <= 12'd0;
        end
    end else if (cnt == STEP) begin
        cnt <= 17'd0;
        case (step)                 // sample the level set during this step
        4'd0: s0 <= d_s2;           // TH=1: Up Down Left Right B C
        4'd1: s1 <= d_s2;           // TH=0: Up Down 0 0 A Start
        4'd5: s5 <= d_s2;           // TH=0: D0-D3 all low on a 6-button pad
        4'd6: s6 <= d_s2;           // TH=1: Z Y X Mode on a 6-button pad
        default: ;
        endcase
        step <= step + 4'd1;
        th <= step[0] | step == 4'd7;   // next level: low on odd steps, high when done
    end
end

endmodule
