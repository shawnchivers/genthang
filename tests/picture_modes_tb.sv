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

    function automatic [7:0] reference_channel(input integer value, mode, dimming, channel);
        integer c;
        c = value;
        if ((mode == 1 && channel == 2) || (mode == 2 && channel == 0))
            c = value - value / 8;
        else if ((mode == 1 || mode == 2) && channel == 1)
            c = value - value / 16;
        else if (mode == 3) begin
            c = value + value / 4 - 32;
            if (c < 0) c = 0;
            if (c > 255) c = 255;
        end
        case (dimming)
        1: c = c - c / 4;
        2: c = c / 2;
        3: c = c / 4;
        default: ;
        endcase
        return 8'(c);
    endfunction

    task automatic check_pixel(input [23:0] source, input integer mode, dimming);
        reg [23:0] expected_rgb;
        force dut.active = active_test;
        force dut.mem_portB_rdata = sample;
        force dut.left_px = left_sample;
        force dut.scan = scan_test;
        force plain.active = active_test;
        force plain.mem_portB_rdata = sample;
        force plain.left_px = left_sample;
        force plain.scan = scan_test;
        // Color mode was removed: video_opt[7:6] are ignored, only brightness applies
        expected_rgb = {reference_channel(int'(source[23:16]), 0, dimming, 0),
                        reference_channel(int'(source[15:8]), 0, dimming, 1),
                        reference_channel(int'(source[7:0]), 0, dimming, 2)};
        // PICTURE_OPTS=0 has one register stage, PICTURE_OPTS=1 two
        @(posedge clk);
        #1;
        if (plain.rgb !== source)
            $fatal(1, "PICTURE_OPTS=0 RGB %h expected unchanged %h (mode %0d dim %0d)",
                   plain.rgb, source, mode, dimming);
        @(posedge clk);
        #1;
        if (dut.rgb !== expected_rgb)
            $fatal(1, "RGB %h expected %h (mode %0d dim %0d source %h; options %h input %h active %b)",
                   dut.rgb, expected_rgb, mode, dimming, source, dut.opt_s2, dut.picture_rgb_r, dut.active_r);
        @(negedge clk);
    endtask

    initial begin
        force dut.active = active_test;
        force dut.mem_portB_rdata = sample;
        force dut.left_px = left_sample;
        force dut.scan = scan_test;
        for (int mode = 0; mode < 4; mode++)
        for (int dimming = 0; dimming < 4; dimming++)
        for (int channel = 0; channel < 3; channel++)
        for (int value = 0; value < 256; value++)
            if (dut.picture_chan(8'(value), 2'(mode), 2'(dimming), channel) !==
                reference_channel(value, mode, dimming, channel))
                $fatal(1, "Channel mismatch at %0d / %0d / %0d / %0d",
                       mode, dimming, channel, value);

        for (int mode = 0; mode < 4; mode++)
        for (int dimming = 0; dimming < 4; dimming++) begin
            options = 10'((mode << 6) | (dimming << 8));
            repeat (3) @(negedge clk);
            overlay = 0;
            for (int pixel = 0; pixel < 4096; pixel++) begin
                sample = 13'(pixel);
                check_pixel({{2{sample[11:8]}}, {2{sample[7:4]}}, {2{sample[3:0]}}},
                            mode, dimming);
            end
            overlay = 1;
            // Traverse every 5-bit channel value, with asymmetric RGB to catch swaps.
            for (int level = 0; level < 32; level++) begin
                overlay_color = {5'(31 - level), 5'((level + 11) % 32), 5'(level)};
                check_pixel({overlay_color[4:0], overlay_color[4:2],
                             overlay_color[9:5], overlay_color[9:7],
                             overlay_color[14:10], overlay_color[14:12]}, mode, dimming);
            end
            // Scanlines and blending still bypass the menu.
            options[3:0] = 4'b1010;
            scan_test = 1;
            repeat (3) @(negedge clk);
            check_pixel({overlay_color[4:0], overlay_color[4:2],
                         overlay_color[9:5], overlay_color[9:7],
                         overlay_color[14:10], overlay_color[14:12]}, mode, dimming);
            active_test = 0;
            force dut.active = 1'b0;
            force plain.active = 1'b0;
            @(posedge clk);
            #1;
            if (plain.rgb !== 24'd0) $fatal(1, "Blanking must remain black");
            @(posedge clk);
            #1;
            if (dut.rgb !== 24'd0) $fatal(1, "Blanking must remain black");
            @(negedge clk);
            active_test = 1;
            scan_test = 0;
        end

        overlay = 0;
        for (int blend = 0; blend < 3; blend++)
        for (int scan = 0; scan < 3; scan++)
        for (int flagged = 0; flagged < 2; flagged++)
        for (int mode = 0; mode < 4; mode++)
        for (int dimming = 0; dimming < 4; dimming++) begin
            options = 10'((mode << 6) | (dimming << 8) | (blend << 2) | scan);
            scan_test = 1;
            sample = {1'(flagged), 12'h8cf};
            left_sample = 12'h246;
            repeat (3) @(negedge clk);
            begin
                reg [23:0] source;
                integer v;
                for (int ch = 0; ch < 3; ch++) begin
                    v = int'(sample[ch*4 +: 4]) * 17;
                    if (blend == 1 || (blend == 2 && flagged != 0))
                        v = (v + int'(left_sample[ch*4 +: 4]) * 17) / 2;
                    if (scan == 1) v = v - v / 4;
                    if (scan == 2) v = v / 2;
                    source[ch*8 +: 8] = 8'(v);
                end
                check_pixel(source, mode, dimming);
            end
        end
        $display("Picture modes: exhaustive channel/game colors, menu, blanking, effects and PICTURE_OPTS=0 bypass passed");
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
