// Locks the core's frame to the 60.00 Hz HDMI frame: the core (slightly faster) halts
// at the start of its line 1 until HDMI begins line 0. Cleared while the core is in reset
// so no stale pause or sync state carries over into the next game.
//
// At 54 MHz the core is ~3960 MCLK per frame ahead of 60.00 Hz. Rather than absorbing
// all of it in one ~73 us halt (which also stalls any Z80 access to the 68K bus), the
// core is paused for SPREAD_PAUSE MCLK (two 68K cycles) every SPREAD_PERIOD MCLK, about
// once per line. That leaves ~300 MCLK (~5 us) for the frame lock. 262 * 3434 + 3668 =
// 899,708 MCLK per core frame stays below every HDMI frame (900,000 at 60 Hz, 901,800
// for LCD800), so the lock still always catches up.
module frame_sync #(
    parameter SPREAD_PERIOD = 3434,
    parameter SPREAD_PAUSE = 14
) (
    input            clk,
    input            resetn,
    input      [8:0] x,
    input      [7:0] y,
    input            hdmi_first_line,   // HDMI clock domain
    output           pause_core
);

reg lock_pause = 1'b0;
reg [$clog2(SPREAD_PERIOD)-1:0] spread_cnt = 0;
reg [$clog2(SPREAD_PAUSE+1)-1:0] spread_left = 0;
assign pause_core = lock_pause | (spread_left != 0);
always @(posedge clk) begin
    if (spread_left != 0)
        spread_left <= spread_left - 1'd1;
    else if (~lock_pause) begin
        spread_cnt <= spread_cnt + 1'd1;
        if (spread_cnt == SPREAD_PERIOD - 1) begin
            spread_cnt <= 0;
            spread_left <= SPREAD_PAUSE[$bits(spread_left)-1:0];
        end
    end
    if (~resetn) begin
        spread_cnt <= 0;
        spread_left <= 0;
    end
end

reg sync_done = 1'b0;
reg hdmi_first_line_r, hdmi_first_line_rr;
always @(posedge clk) begin
    hdmi_first_line_r <= hdmi_first_line;
    hdmi_first_line_rr <= hdmi_first_line_r;
    if (~sync_done) begin
        if (~lock_pause) begin
            if (y == 1 && x == 0)
                lock_pause <= 1'b1;
        end else if (hdmi_first_line_rr) begin
            lock_pause <= 1'b0;
            sync_done <= 1'b1;
        end
    end
    if (y == 100) sync_done <= 1'b0;
    if (~resetn) begin
        lock_pause <= 1'b0;
        sync_done <= 1'b0;
    end
end

endmodule
