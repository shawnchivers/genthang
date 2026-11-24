// Synchronized upscaler to HDMI
// Based on framebuffer_sync.sv from SNESTang / MDTang (nand2mario, 2024, GPL-3.0);
// modified for Gen Thang (scanlines, composite blend, Genesis DAC table).
//
// This module takes RGB pixel input, buffers 16 lines of the video in BRAM, 
// then upscales and output the video in 720p HDMI format.
// TV mode centers a 4:3 window; LCD mode fills the input of a 4:3 panel controller.
// LCD800=1 outputs native 800x480 DVI instead, for bare TFT panels behind a TFP401
// (which has no scaler): TV = centred 640x480, LCD = full 800 width.
// SELECTABLE=1 adds 480p59.94 and 1080i60 gameplay, with a 720p recovery menu.
//
// This is different from framebuffer.sv in that it requires the input video
// to be synchronized to HDMI. This allows the module use much less BRAM space
// compared to a full framebuffer.
module framebuffer #(
    parameter WIDTH = 320,          // max frame width (<=1280)
    parameter HEIGHT = 240,         // max frame height (<=720)
    parameter COLOR_BITS = 4,       // bits per RGB color channel
    parameter BUFFER_LINES = 32,    // power-of-two line ring, must exceed core lead over HDMI
    parameter LCD800 = 0,           // 1 = 800x480 output (29.7MHz pixel clock, DVI only)
    parameter SELECTABLE = 0,       // 1 = runtime 720p / 1080i / 480p
    parameter ADAPTIVE_BLEND = 1,   // 0 = composite blend off/on only
    parameter PICTURE_OPTS = 0      // 1 = brightness (video_opt[9:8]) for games, GT_PICTURE builds
)(
	input clk,                      // megadrive clock
	input resetn,
	input clk_pixel,                // 74.25Mhz pixel clock (29.7MHz with LCD800)
	input clk_5x_pixel,             // 5x pixel clock
    input video_reset,              // pixel-domain reset while the HDMI PLL relocks

    // video signals
    input ce_pix,                   // pixel strobe
    input [COLOR_BITS-1:0] r,       // pixel color
    input [COLOR_BITS-1:0] g,
    input [COLOR_BITS-1:0] b,
    input transp,                   // VDP transparency-dither flag of this pixel (adaptive blend)
    input interlace,                // quasi-static; scanlines are skipped in interlace like MiSTer
    input [$clog2(WIDTH)-1:0] x,    // pixel position
    input [$clog2(HEIGHT)-1:0] y,
    input [10:0] width,             // frame width
    input [9:0] height,             // frame height

    output pause_core,              // sync mechanism: input video should be a bit faster (e.g. 0.x%)
                                    // than HDMI. It should wait after line 0 is rendered
                                    // and wait for sync_line1 to continue rendering.
    output reg tv480 = 1'b0,         // latched request for the 27MHz pixel clock

    // overlay from iosys
    input overlay,
    output [7:0] overlay_x,
    output [7:0] overlay_y,
    input [14:0] overlay_color,     // BGR5
    input [9:0] video_opt,          // scanlines [1:0], blend [3:2], DVI [4], LCD [5], 1080i [6], 480p [7], dim [9:8]

    input [15:0] audio_left,        // audio sample
    input [15:0] audio_right,

	// HDMI output signals
	output       tmds_clk_n,
	output       tmds_clk_p,
	output [2:0] tmds_d_n,
	output [2:0] tmds_d_p
);

localparam CLKFRQ = LCD800 ? 29700 : 74250;
reg tv1080 = 1'b0;
wire [10:0] screen_w = LCD800 ? 11'd800 : SELECTABLE && tv480 ? 11'd720 : SELECTABLE && tv1080 ? 11'd1920 : 11'd1280;
wire [9:0] screen_h = LCD800 || SELECTABLE && tv480 ? 10'd480 : SELECTABLE && tv1080 ? 10'd540 : 10'd720;
wire [10:0] tv_w = LCD800 ? 11'd640 : SELECTABLE && tv1080 ? 11'd1440 : 11'd960;
wire [10:0] tv_begin = LCD800 ? 11'd79 : SELECTABLE && tv1080 ? 11'd239 : 11'd159;
localparam H_BITS = SELECTABLE ? 12 : 11;

// video stuff
wire [H_BITS-1:0] cx /* xsynthesis syn_keep=1 */;
wire [9:0] cy  /* xsynthesis syn_keep=1 */;
wire field;

//
// BRAM frame buffer
//
localparam FB_DEPTH = WIDTH * BUFFER_LINES;
localparam COLOR_WIDTH = COLOR_BITS * 3;
localparam MEM_WIDTH = COLOR_WIDTH + ADAPTIVE_BLEND;
localparam FB_AWIDTH = $clog2(FB_DEPTH);
localparam LINE_BITS = $clog2(BUFFER_LINES);
reg [MEM_WIDTH-1:0] mem [0:FB_DEPTH-1];
reg [FB_AWIDTH-1:0] mem_portA_addr;
reg mem_portA_we;

wire [FB_AWIDTH-1:0] mem_portB_addr;
reg [MEM_WIDTH-1:0] mem_portB_rdata;

// BRAM port A read/write
reg ce_pix_r, hblank_r;
assign mem_portA_addr = y[LINE_BITS-1:0] * WIDTH + x;
always @(posedge clk) begin
    ce_pix_r <= ce_pix;
    if (ce_pix & ~ce_pix_r) 
        mem[mem_portA_addr] <= MEM_WIDTH'({transp, r, g, b});
end

// BRAM port B read
reg [$clog2(WIDTH)-1:0] xx  /* xsynthesis syn_keep=1 */; // scaled-down pixel position
reg [$clog2(HEIGHT)-1:0] yy /* xsynthesis syn_keep=1 */;
assign mem_portB_addr = yy[LINE_BITS-1:0] * WIDTH + xx;
always @(posedge clk_pixel) begin
    mem_portB_rdata <= mem[mem_portB_addr];
end

// Video synchronization
reg hdmi_first_line;
frame_sync sync (
    .clk(clk), .resetn(resetn), .x(x), .y(y), .hdmi_first_line(hdmi_first_line),
    .pause_core(pause_core)
);
always @(posedge clk_pixel) begin
    if (!video_reset && cy == 0 && cx >= (SELECTABLE && tv480 ? 11'd3 :
                                        LCD800 ? 11'd80 : SELECTABLE && tv1080 ? 11'd240 : 11'd160))
        hdmi_first_line <= 1;
    else
        hdmi_first_line <= 0;
end

// audio stuff
localparam AUDIO_RATE=48000;
localparam AUDIO_CLK_DELAY = CLKFRQ * 1000 / AUDIO_RATE / 2;
logic [$clog2(AUDIO_CLK_DELAY)-1:0] audio_divider;
logic clk_audio;

always @(posedge clk_pixel) begin
    if (video_reset) begin
        audio_divider <= 0;
        clk_audio <= 0;
    end else if (audio_divider != (SELECTABLE && tv480 ? 281 : AUDIO_CLK_DELAY) - 1)
        audio_divider <= audio_divider + 1'b1;
    else begin 
        clk_audio <= ~clk_audio; 
        audio_divider <= 0; 
    end
end

reg [15:0] audio_sample_word [1:0];
always @(posedge clk) begin
    audio_sample_word[0] <= audio_left;
    audio_sample_word[1] <= audio_right;
end

//
// Video
//
reg [23:0] rgb;             // actual RGB output
reg active                  /* xsynthesis syn_keep=1 */;
reg [10:0] xcnt             /* xsynthesis syn_keep=1 */;
reg [10:0] ycnt             /* xsynthesis syn_keep=1 */;                  // fractional scaling counters
reg [9:0] cy_r;
assign overlay_x = xx;
assign overlay_y = yy;
reg lcd = 1'b0;
// LCD mode starts at cx=2, once yy has advanced for the new line (cy_r lags cy by one
// cycle), and spans the remaining screen_w-3 pixels.
wire full_width = lcd || SELECTABLE && tv480;
wire [10:0] window_width = full_width ? (LCD800 ? 11'd797 : SELECTABLE && tv480 ? 11'd717 : 11'd1277) : tv_w;
wire [10:0] xbegin = full_width ? 11'd2 : tv_begin;
wire [10:0] xend = full_width ? (LCD800 ? 11'd799 : SELECTABLE && tv480 ? 11'd719 : 11'd1279) :
                               LCD800 ? 11'd719 : SELECTABLE && tv1080 ? 11'd1679 : 11'd1119;

// address calculation
// Assume the video occupies fully on the Y direction, we are upscaling the video by `SCREEN_H/height`.
// xcnt and ycnt are fractional scaling counters.
always @(posedge clk_pixel) begin
    reg active_t;
    reg [10:0] xcnt_next;
    reg [10:0] ycnt_next;
    xcnt_next = xcnt + (overlay ? 256 : width);
    ycnt_next = ycnt + (overlay ? 224 : height);

    active_t = 0;
    if (cx == H_BITS'(xbegin)) begin
        active_t = 1;
        active <= 1;
    end else if (cx == H_BITS'(xend)) begin
        active_t = 0;
        active <= 0;
    end

    if (active_t | active) begin        // increment xx
        xcnt <= xcnt_next;
        if (xcnt_next >= window_width) begin
            xcnt <= xcnt_next - window_width;
            xx <= xx + 1;
        end
    end

    cy_r <= cy;
    if (cy[0] != cy_r[0]) begin         // increment yy at new lines
        ycnt <= ycnt_next;
        if (ycnt_next >= {1'b0, screen_h}) begin
            ycnt <= ycnt_next - {1'b0, screen_h};
            yy <= yy + 1;
        end
    end

    if (cx == 0) begin
        active <= 0;
        xx <= 0;
        xcnt <= 0;
    end
    
    if (cy == 0) begin
        yy <= 0;
        ycnt <= 0;
    end 

end

// calc rgb value to hdmi
// Game pixels go through MiSTer's measured Genesis DAC table. Blend averages each pixel
// with the one to its left (composite dither blending; adaptive = only where the VDP
// flags transparency dither). Scanlines dim the lower half of each Genesis line.
reg [9:0] opt_s1, opt_s2;
reg ov_s1 = 1'b1, ov_s2 = 1'b1;
reg il_s1, il_s2;
reg [$clog2(WIDTH)-1:0] xx_r, xx_px;
reg [COLOR_WIDTH-1:0] rdata_r, prev_px;
reg scan;
// rdata holds Genesis pixel xx_r; it just moved to a new pixel when xx_r != xx_px
wire [COLOR_WIDTH-1:0] left_px = xx_r != xx_px ? rdata_r : prev_px;
// Adaptive blend flag of the left neighbour: blending a pair when either pixel is flagged
// keeps dithered sprites over dithered planes from blending every other pixel (shimmer).
reg rflag_r, prev_flag;
wire cur_flag = ADAPTIVE_BLEND != 0 && mem_portB_rdata[MEM_WIDTH-1];
wire left_flag = xx_r != xx_px ? rflag_r : prev_flag;
always @(posedge clk_pixel) begin
    rflag_r <= cur_flag;
    prev_flag <= active ? left_flag : cur_flag;
end
always @(posedge clk_pixel) begin
    opt_s1 <= video_opt;
    opt_s2 <= opt_s1;
    ov_s1 <= overlay;
    ov_s2 <= ov_s1;
    il_s1 <= interlace;
    il_s2 <= il_s1;
    scan <= ycnt >= {2'b0, screen_h[9:1]} && !il_s2;
    xx_r <= xx;
    xx_px <= xx_r;
    rdata_r <= mem_portB_rdata[COLOR_WIDTH-1:0];
    if (!active)
        prev_px <= mem_portB_rdata[COLOR_WIDTH-1:0];    // pixel 0 is its own left neighbour
    else
        prev_px <= left_px;
end

function automatic [7:0] dac(input [3:0] i);
    dac = {i, i};
endfunction

function automatic [7:0] chan(input [COLOR_BITS-1:0] a, input [COLOR_BITS-1:0] b,
                              input blend, input [1:0] dim);
    reg [8:0] s;
    reg [7:0] v;
    s = blend ? dac(a) + dac(b) : {dac(a), 1'b0};
    v = s[8:1];
    case (dim)
    2'd1:    chan = v - v[7:2];
    2'd2:    chan = {1'b0, v[7:1]};
    2'd3:    chan = PICTURE_OPTS ? {2'b00, v[7:2]} : v;   // 25 % only exists with brightness
    default: chan = v;
    endcase
endfunction

// Brightness (GT_PICTURE, video_opt[9:8]: 100/75/50/25%) shares the scanline dimmer:
// on scanline rows the two levels add, capped at 25%. Games only.
wire [2:0] dim_sum = (scan ? {1'b0, opt_s2[1:0]} : 3'd0) + {1'b0, opt_s2[9:8]};
wire [1:0] dim = !PICTURE_OPTS ? (scan ? opt_s2[1:0] : 2'd0)    // exactly the pre-brightness dimmer
               : dim_sum[2] ? 2'd3 : dim_sum[1:0];
wire do_blend;
generate
    if (ADAPTIVE_BLEND) begin
        assign do_blend = opt_s2[3:2] == 2'd1 || (opt_s2[3:2] == 2'd2 && (cur_flag || left_flag));
    end else begin
        assign do_blend = opt_s2[2];
    end
endgenerate
// Handheld (PICTURE_OPTS) builds draw the menu at a fixed 50% so it is not harsh on the LCD.
wire [23:0] menu_rgb = {overlay_color[4:0], overlay_color[4:2], overlay_color[9:5], overlay_color[9:7],
                        overlay_color[14:10], overlay_color[14:12]};
wire [23:0] picture_rgb = overlay
    ? (PICTURE_OPTS ? {1'b0, menu_rgb[23:17], 1'b0, menu_rgb[15:9], 1'b0, menu_rgb[7:1]} : menu_rgb)
    : {chan(mem_portB_rdata[COLOR_BITS*2 +: COLOR_BITS], left_px[COLOR_BITS*2 +: COLOR_BITS], do_blend, dim),
       chan(mem_portB_rdata[COLOR_BITS   +: COLOR_BITS], left_px[COLOR_BITS   +: COLOR_BITS], do_blend, dim),
       chan(mem_portB_rdata[0            +: COLOR_BITS], left_px[0            +: COLOR_BITS], do_blend, dim)};

always @(posedge clk_pixel)
    rgb <= active ? picture_rgb : 24'h000000;

// HDMI output.
logic[2:0] tmds;

localparam VIDEOID = LCD800 ? 0 : 4;    // 0 = custom 800x480 timing in hdmi.sv
localparam VIDEO_REFRESH = 60.0;
localparam COLLEN = 80;
localparam AUDIO_BIT_WIDTH = 16;

// DVI output sends no HDMI data islands (so no audio). Some plasma TVs pulse the picture
// whenever data islands are present. Switch only at a frame start.
reg dvi = 1'b0;
always @(posedge clk_pixel)
    if (cx == 0 && cy == 0 && !field) begin
        dvi <= LCD800 ? 1'b1 : opt_s2[4];     // a TFP401 is a DVI receiver
        lcd <= opt_s2[5];
        // Alternate TV timings apply only to gameplay: the menu returns to 720p so an
        // incompatible display can still be rescued. LCD stays 720p 4:3 throughout.
        tv1080 <= SELECTABLE && opt_s2[6] && !opt_s2[7] && !opt_s2[5] && !ov_s2;
        tv480 <= SELECTABLE && opt_s2[7] && !opt_s2[5] && !ov_s2;
    end

hdmi #( .VIDEO_ID_CODE(VIDEOID), 
        .SELECTABLE(SELECTABLE),
        .BIT_WIDTH(H_BITS),
        .DVI_OUTPUT(LCD800),
        .VIDEO_REFRESH_RATE(VIDEO_REFRESH),
        .IT_CONTENT(1),
        .AUDIO_RATE(AUDIO_RATE), 
        .AUDIO_BIT_WIDTH(AUDIO_BIT_WIDTH),
        .START_X(0),
        .START_Y(0) )

hdmi( .clk_pixel_x5(clk_5x_pixel), 
        .clk_pixel(clk_pixel), 
        .clk_audio(clk_audio),
        .rgb(rgb), 
        .reset(video_reset),
        .audio_sample_word(audio_sample_word),
        .dvi_mode(dvi),
        .interlace_mode(tv1080),
        .mode_480p(tv480),
        .field(field),
        .tmds(tmds), 
        .tmds_clock(),
        .cx(cx), 
        .cy(cy),
        .frame_width(),
        .frame_height() );

// Gowin LVDS output buffer
ELVDS_OBUF tmds_bufds [3:0] (
    .I({clk_pixel, tmds}),
    .O({tmds_clk_p, tmds_d_p}),
    .OB({tmds_clk_n, tmds_d_n})
);

endmodule
