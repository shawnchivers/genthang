`timescale 1ns/1ps
module picture_modes_tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg [9:0] options = 0;
    reg overlay = 0, active_test = 1, scan_test = 0;
    reg [14:0] overlay_color = 0;
    reg [12:0] sample = 0;
    reg [11:0] left_sample = 0;
    framebuffer #(.PICTURE_OPTS(1)) dut (
        .clk(clk), .resetn(1'b1), .clk_pixel(clk), .clk_5x_pixel(clk),
        .ce_pix(1'b0), .r(4'd0), .g(4'd0), .b(4'd0), .transp(1'b0),
        .interlace(1'b0), .x(9'd0), .y(8'd0), .width(11'd320), .height(10'd224),
        .overlay(overlay), .overlay_color(overlay_color), .video_opt(options),
        .audio_left(16'd0), .audio_right(16'd0),
        .pause_core(), .overlay_x(), .overlay_y(),
        .tmds_clk_n(), .tmds_clk_p(), .tmds_d_n(), .tmds_d_p()
    );
    // GT_PICTURE=0 (DB9) build: colour mode and brightness bits must have no effect
    framebuffer #(.PICTURE_OPTS(0)) plain (
        .clk(clk), .resetn(1'b1), .clk_pixel(clk), .clk_5x_pixel(clk),
        .ce_pix(1'b0), .r(4'd0), .g(4'd0), .b(4'd0), .transp(1'b0),
        .interlace(1'b0), .x(9'd0), .y(8'd0), .width(11'd320), .height(10'd224),
        .overlay(overlay), .overlay_color(overlay_color), .video_opt(options),
        .audio_left(16'd0), .audio_right(16'd0),
        .pause_core(), .overlay_x(), .overlay_y(),
        .tmds_clk_n(), .tmds_clk_p(), .tmds_d_n(), .tmds_d_p()
    );

    // Expected game channel: blend, then one dimmer whose level is brightness plus the
    // scanline level on scanline rows, capped at 25%. PICTURE_OPTS=0 ignores brightness.
    function automatic [7:0] game_channel(input integer a, b, blend, scan_row, scan, bright);
        integer v, d;
        v = blend ? (a * 17 + b * 17) / 2 : a * 17;
        d = (scan_row ? scan : 0) + bright;
        if (d > 3) d = 3;
        case (d)
        1: v = v - v / 4;
        2: v = v / 2;
        3: v = v / 4;
        default: ;
        endcase
        return 8'(v);
    endfunction

    task automatic drive();
        force dut.active = active_test;   force plain.active = active_test;
        force dut.mem_portB_rdata = sample; force plain.mem_portB_rdata = sample;
        force dut.left_px = left_sample;  force plain.left_px = left_sample;
        force dut.scan = scan_test;       force plain.scan = scan_test;
    endtask

    task automatic expect_rgb(input [23:0] want_dut, want_plain, input string what);
        drive();
        @(posedge clk);
        #1;
        if (dut.rgb !== want_dut) $fatal(1, "%s: RGB %h expected %h (options %h)", what, dut.rgb, want_dut, options);
        if (plain.rgb !== want_plain) $fatal(1, "%s: PICTURE_OPTS=0 RGB %h expected %h", what, plain.rgb, want_plain);
        @(negedge clk);
    endtask

    initial begin
        for (int bright = 0; bright < 4; bright++)
        for (int blend = 0; blend < 3; blend++)
        for (int scan = 0; scan < 3; scan++)
        for (int row = 0; row < 2; row++)
        for (int flagged = 0; flagged < 2; flagged++) begin
            options = 10'((bright << 8) | (3 << 6) | (blend << 2) | scan);  // colour bits ignored
            scan_test = row;
            overlay = 0;
            repeat (3) @(negedge clk);
            for (int pixel = 0; pixel < 4096; pixel += (bright == 0 && blend == 0 ? 1 : 7)) begin
                reg [23:0] want, want_plain;
                integer do_blend;
                sample = {1'(flagged), 12'(pixel)};
                left_sample = 12'(pixel * 5 + 'h3a1);
                do_blend = blend == 1 || (blend == 2 && flagged);
                for (int ch = 0; ch < 3; ch++) begin
                    want[ch*8 +: 8] = game_channel(sample[ch*4 +: 4], left_sample[ch*4 +: 4], do_blend, row, scan, bright);
                    want_plain[ch*8 +: 8] = game_channel(sample[ch*4 +: 4], left_sample[ch*4 +: 4], do_blend, row, scan, 0);
                end
                expect_rgb(want, want_plain, "game");
            end
            // The menu is never dimmed, blended or scanlined.
            overlay = 1;
            for (int level = 0; level < 32; level++) begin
                reg [23:0] menu;
                overlay_color = {5'(31 - level), 5'((level + 11) % 32), 5'(level)};
                menu = {overlay_color[4:0], overlay_color[4:2], overlay_color[9:5], overlay_color[9:7],
                        overlay_color[14:10], overlay_color[14:12]};
                expect_rgb(menu, menu, "menu");
            end
            active_test = 0;
            expect_rgb(24'd0, 24'd0, "blanking");
            active_test = 1;
        end
        $display("Picture modes: brightness x scanlines x blend on game pixels, menu, blanking and PICTURE_OPTS=0 bypass passed");
        $finish;
    end
endmodule

// HDMI encoding and board buffers are outside this RGB-path test.
module hdmi #(
    parameter VIDEO_ID_CODE = 4, DVI_OUTPUT = 0, VIDEO_REFRESH_RATE = 60.0,
    IT_CONTENT = 1, AUDIO_RATE = 48000, AUDIO_BIT_WIDTH = 16, START_X = 0, START_Y = 0
) (
    input clk_pixel_x5, clk_pixel, clk_audio, reset, dvi_mode,
    input [23:0] rgb,
    input [AUDIO_BIT_WIDTH-1:0] audio_sample_word [1:0],
    output [2:0] tmds,
    output tmds_clock,
    output [10:0] cx,
    output [9:0] cy,
    output [10:0] frame_width,
    output [9:0] frame_height
);
    assign tmds = 0;
    assign tmds_clock = clk_pixel;
    assign cx = 0;
    assign cy = 0;
    assign frame_width = 1280;
    assign frame_height = 720;
endmodule

module ELVDS_OBUF(input I, output O, OB);
    assign O = I;
    assign OB = ~I;
endmodule
