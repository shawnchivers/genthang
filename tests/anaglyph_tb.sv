`timescale 1ns/1ps
// Anaglyph 3D write path: lines of random colours and layer depths go in through the
// framebuffer's write port, and every written pixel is checked against a model of the
// per-eye depth-plane shifts for 3D off, full colour and half colour, at H40 and H32 widths.
module anaglyph_tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg ce_pix = 0, de = 0;
    reg [8:0] x = 0;
    reg [7:0] y = 0;
    reg [3:0] r = 0, g = 0, b = 0;
    reg [2:0] depth = 0;
    reg [9:0] options = 0;
    framebuffer #(.ADAPTIVE_BLEND(0), .ANAGLYPH(1)) dut (
        .clk(clk), .resetn(1'b1), .clk_pixel(clk), .clk_5x_pixel(clk),
        .ce_pix(ce_pix), .r(r), .g(g), .b(b), .transp(1'b0), .depth(depth), .de(de),
        .interlace(1'b0), .x(x), .y(y), .width(11'd320), .height(10'd224),
        .overlay(1'b0), .overlay_color(15'd0), .video_opt(options),
        .audio_left(16'd0), .audio_right(16'd0),
        .pause_core(), .overlay_x(), .overlay_y(),
        .tmds_clk_n(), .tmds_clk_p(), .tmds_d_n(), .tmds_d_p()
    );

    reg [11:0] line_color [0:319];
    reg [2:0] line_depth [0:319];

    // depth plane of a VDP layer: 0 far (backdrop, plane B low), 1 middle (plane A low),
    // 2 screen (sprites and high-priority layers); the left eye sees plane p shifted by
    // 2 - p pixels at x + shift, the right eye at x - shift
    function automatic integer plane(input integer d);
        return d <= 1 ? 0 : d == 2 ? 1 : 2;
    endfunction

    function automatic [11:0] eye(input integer px, width, direction);
        for (int p = 2; p >= 0; p--) begin
            integer q = px + direction * (2 - p);
            if (q >= 0 && q < width && plane(line_depth[q]) == p)
                return line_color[q];
        end
        return line_color[px];
    endfunction

    function automatic [11:0] expected(input integer px, width, mode);
        reg [11:0] left, right;
        integer luma;
        left = eye(px, width, 1);
        right = eye(px, width, -1);
        luma = (left[11:8] + 2 * left[7:4] + left[3:0]) / 4;
        case (mode)
        1: return {left[11:8], right[7:0]};
        2: return {4'(luma), right[7:0]};
        default: return line_color[px];
        endcase
    endfunction

    // one VDP pixel every 8 clocks, like the core's pixel strobe
    task automatic pixel(input reg active, input reg [8:0] px);
        de = active;
        x = px;
        if (active) {r, g, b} = line_color[px];
        depth = active ? line_depth[px] : 3'd0;
        @(negedge clk) ce_pix = 1;
        @(negedge clk) ce_pix = 0;
        repeat (6) @(negedge clk);
    endtask

    task automatic run_line(input integer width, mode, line);
        for (int i = 0; i < width; i++) begin
            line_color[i] = 12'($urandom);
            // runs of layers so that edges between them are common
            line_depth[i] = i == 0 || $urandom_range(3) == 0 ? 3'($urandom_range(6)) : line_depth[i - 1];
        end
        options = 10'(mode);
        y = 8'(line);
        for (int i = 0; i < width; i++)
            pixel(1, 9'(i));
        y = 8'(line + 1);                   // the top level counts the next line at HBLANK
        for (int i = 0; i < 12; i++)
            pixel(0, 0);
        for (int i = 0; i < width; i++) begin
            reg [11:0] got = dut.mem[(line % 32) * 320 + i];
            reg [11:0] want = expected(i, width, mode);
            if (got !== want)
                $fatal(1, "mode %0d width %0d line %0d x %0d: wrote %h expected %h (depth %0d)",
                       mode, width, line, i, got, want, line_depth[i]);
        end
    endtask

    initial begin
        repeat (4) @(negedge clk);
        for (int line = 0; line < 48; line++)
            run_line(line % 2 ? 256 : 320, line % 3, line);
        $display("Anaglyph 3D: off, full colour and half colour writes at H40 and H32 passed");
        $finish;
    end
endmodule

// HDMI encoding and board buffers are outside this write-path test.
module hdmi #(
    parameter VIDEO_ID_CODE = 4, DVI_OUTPUT = 0, VIDEO_REFRESH_RATE = 60.0, SELECTABLE = 0, BIT_WIDTH = 11,
    IT_CONTENT = 1, AUDIO_RATE = 48000, AUDIO_BIT_WIDTH = 16, START_X = 0, START_Y = 0
) (
    input clk_pixel_x5, clk_pixel, clk_audio, reset, dvi_mode, interlace_mode,
    input [23:0] rgb,
    input [AUDIO_BIT_WIDTH-1:0] audio_sample_word [1:0],
    output [2:0] tmds,
    output tmds_clock,
    output field,
    output [10:0] cx,
    output [9:0] cy,
    output [10:0] frame_width,
    output [9:0] frame_height
);
    assign tmds = 0;
    assign field = 0;
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
