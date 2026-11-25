// Locks the core's frame to the 60.00 Hz HDMI frame: the core (slightly faster) halts
// at the start of its line 1 until HDMI begins line 0. Cleared while the core is in reset
// so no stale pause or sync state carries over into the next game.
module frame_sync (
    input            clk,
    input            resetn,
    input      [8:0] x,
    input      [7:0] y,
    input            hdmi_first_line,   // HDMI clock domain
    output reg       pause_core = 1'b0
);

reg sync_done = 1'b0;
reg hdmi_first_line_r, hdmi_first_line_rr;
always @(posedge clk) begin
    hdmi_first_line_r <= hdmi_first_line;
    hdmi_first_line_rr <= hdmi_first_line_r;
    if (~sync_done) begin
        if (~pause_core) begin
            if (y == 1 && x == 0)
                pause_core <= 1'b1;
        end else if (hdmi_first_line_rr) begin
            pause_core <= 1'b0;
            sync_done <= 1'b1;
        end
    end
    if (y == 100) sync_done <= 1'b0;
    if (~resetn) begin
        pause_core <= 1'b0;
        sync_done <= 1'b0;
    end
end

endmodule
