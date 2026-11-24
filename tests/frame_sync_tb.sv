// frame_sync: the core (54 MHz, 262 x 3420 MCLK lines) stays locked to a 60 Hz HDMI frame
// (900,000 MCLK), drops no frames, and apart from the short per-line pauses only needs a
// few microseconds of frame-lock halt instead of one ~73 us block.
module frame_sync_tb;
    localparam LINE = 3420, LINES = 262, HDMI_FRAME = 900000, FRAMES = 12;

    reg clk = 0, resetn = 0;
    always #1 clk = ~clk;

    reg  [31:0] core_pos = 0;               // MCLKs the core has run, i.e. not paused
    wire [31:0] in_frame = core_pos % (LINE * LINES);
    wire [31:0] line = in_frame / LINE, dot = in_frame % LINE;
    // active lines 0-223; x counts during the active part and is 0 in hblank, y is 0 in vblank
    wire [7:0] y = line < 224 ? 8'(line) : 8'd0;
    wire [8:0] x = line < 224 && dot < 2560 ? 9'(dot / 8) : 9'd0;

    reg [31:0] hdmi_cnt = 0;
    wire hdmi_first_line = hdmi_cnt < 800;
    wire pause_core;

    frame_sync dut (.clk(clk), .resetn(resetn), .x(x), .y(y), .hdmi_first_line(hdmi_first_line),
                    .pause_core(pause_core));

    integer run = 0, longest = 0, lock_max = 0, short_max = 0, frames_core = 0, frames_hdmi = 0;
    integer phase;
    always @(posedge clk) if (resetn) begin
        hdmi_cnt <= hdmi_cnt == HDMI_FRAME - 1 ? 0 : hdmi_cnt + 1;
        if (hdmi_cnt == 0) frames_hdmi <= frames_hdmi + 1;
        if (!pause_core) begin
            core_pos <= core_pos + 1;
            if (in_frame == LINE * LINES - 1) frames_core <= frames_core + 1;
        end
        if (pause_core) run <= run + 1;
        else if (run) begin
            if (frames_hdmi >= 3) begin              // after the initial lock
                if (run > 14) begin
                    if (run > lock_max) lock_max = run;
                end else if (run > short_max) short_max = run;
            end
            run <= 0;
        end
    end

    initial begin
        repeat (10) @(posedge clk);
        resetn = 1;
        wait (frames_hdmi == FRAMES);
        // core line 1 starts right after HDMI line 0 begins: the lock held
        phase = (core_pos % (LINE * LINES)) - LINE;
        $display("core frames %0d, hdmi frames %0d, lock halt max %0d MCLK, spread pause %0d MCLK",
                 frames_core, frames_hdmi, lock_max, short_max);
        if (short_max != 14) $fatal(1, "spread pause should be 14 MCLK, got %0d", short_max);
        if (lock_max > 600) $fatal(1, "frame-lock halt too long: %0d MCLK", lock_max);
        if (frames_core < frames_hdmi - 2 || frames_core > frames_hdmi)
            $fatal(1, "core frames %0d vs HDMI %0d: lock lost", frames_core, frames_hdmi);
        if (phase < 0 || phase > 1000) $fatal(1, "core not aligned to HDMI frame (%0d)", phase);
        $display("frame_sync: spread pause, short frame-lock halt and no dropped frames passed");
        $finish;
    end
endmodule
