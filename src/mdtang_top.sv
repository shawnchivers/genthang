// Gen Thang (Mega Drive / Genesis) on the Tang Nano 20K (GW2AR-18C) - board top level.
//
// ROMs are picked from the TF card with the on-screen menu (iosys + PicoRV32
// firmware at SPI flash 0x500000). Video and audio over HDMI (720p). Controllers by
// build variant (GT_PAD, see build.tcl): two DualShocks, two Genesis pads on DB9,
// or 12 direct buttons. Select+Start, Mode+Start or Start+A+B+C = menu.
// Game and menu logic live in md20k_core; this file holds clocks, pads and HDMI.
`include "pad_config.vh"

module mdtang_top (
    input        sys_clk,           // 27MHz crystal

    // SPI flash (menu firmware at 0x500000)
    output       flash_spi_cs_n,
    output       flash_spi_clk,
    output       flash_spi_mosi,
    input        flash_spi_miso,
    output       flash_spi_wp_n,
    output       flash_spi_hold_n,

    // on-board TF card slot
    output       sd_clk,
    output       sd_cmd,
    input        sd_dat0,
    output       sd_dat1,
    output       sd_dat2,
    output       sd_dat3,

    // firmware debug console (on-board USB serial)
    input        UART_RXD,
    output       UART_TXD,

`ifdef GT_PAD_DB9
    // Genesis pads on DB9: {pin 9, pin 6, pins 4, 3, 2, 1}, pin 7 = TH
    input  [5:0] db9_d,
    output       db9_th,
    input  [5:0] db9b_d,
    output       db9b_th,
`elsif GT_PAD_RAW
    // buttons to GND: {R, L, X, A, Right, Left, Down, Up, Start, Select, Y, B}
    input [11:0] btn_n,
`else
    // DualShock 1 on PMOD, DualShock 2 on the header
    output       ds_clk,
    output       ds_cs,
    output       ds_mosi,
    input        ds_miso,
    output       ds2_clk,
    output       ds2_cs,
    output       ds2_mosi,
    input        ds2_miso,
`endif

    // embedded SDRAM (fixed connections, not in the .cst)
    output       O_sdram_clk,
    output       O_sdram_cke,
    output       O_sdram_cs_n,
    output       O_sdram_cas_n,
    output       O_sdram_ras_n,
    output       O_sdram_wen_n,
    inout [31:0] IO_sdram_dq,
    output [10:0] O_sdram_addr,
    output [3:0] O_sdram_dqm,
    output [1:0] O_sdram_ba,

    output [1:0] led,               // active low: [0] game running, [1] loading ROM

    output       tmds_clk_n,
    output       tmds_clk_p,
    output [2:0] tmds_d_n,
    output [2:0] tmds_d_p
);

localparam FREQ = 54_000_000;

// Clocks -------------------------------------------------------------------------------
wire clk_sys, clk_z80, hclk, hclk5, pll_sys_lock, pll_hdmi_lock;

gowin_pll_sys pll_sys (
    .clkin(sys_clk), .clkout(clk_sys), .clkoutp(O_sdram_clk), .clkoutd(clk_z80), .lock(pll_sys_lock)
);

gowin_pll_hdmi pll_hdmi (.clkin(sys_clk), .clkout(hclk5), .lock(pll_hdmi_lock));

CLKDIV #(.DIV_MODE(5)) hdmi_div5 (
    .CLKOUT(hclk), .HCLKIN(hclk5), .RESETN(pll_hdmi_lock), .CALIB(1'b0)
);

// Core ----------------------------------------------------------------------------------
wire [3:0]  sdram_cmd;
wire [31:0] sdram_dq_out;
wire        sdram_dq_oe;
wire [3:0]  red, green, blue;
wire        hsync, hblank, vblank, ce_pix, pause_core, md_on, loading, overlay;
wire [7:0]  overlay_x, overlay_y;
wire [14:0] overlay_color;
wire [3:0]  video_opt;
wire [1:0]  resolution;
wire        transp, interlace;
wire [15:0] audio_left, audio_right;
wire [11:0] pad1, pad2;             // {R, L, X, A, Right, Left, Down, Up, Start, Select, Y, B}

assign {O_sdram_cs_n, O_sdram_ras_n, O_sdram_cas_n, O_sdram_wen_n} = sdram_cmd;
assign O_sdram_cke = 1'b1;
assign IO_sdram_dq = sdram_dq_oe ? sdram_dq_out : 32'bz;
assign flash_spi_wp_n = 1'b1;
assign flash_spi_hold_n = 1'b1;

`ifdef GT_PAD_DB9
genesis_pad #(.FREQ(FREQ)) db9 (.clk(clk_sys), .d(db9_d), .th(db9_th), .btns(pad1));
genesis_pad #(.FREQ(FREQ)) db9b (.clk(clk_sys), .d(db9b_d), .th(db9b_th), .btns(pad2));
`elsif GT_PAD_RAW
reg [11:0] btn_s1, btn_s2;
always @(posedge clk_sys) {btn_s2, btn_s1} <= {btn_s1, ~btn_n};
assign pad1 = btn_s2;
assign pad2 = 12'd0;
`else
dualshock_controller #(.FREQ(FREQ)) ds1 (
    .clk(clk_sys), .I_RSTn(pll_sys_lock),
    .O_psCLK(ds_clk), .O_psSEL(ds_cs), .O_psTXD(ds_mosi), .I_psRXD(ds_miso),
    .O_RXD_1(), .O_RXD_2(), .O_RXD_3(), .O_RXD_4(), .O_RXD_5(), .O_RXD_6(),
    .snes_btns(pad1)
);
dualshock_controller #(.FREQ(FREQ)) ds2 (
    .clk(clk_sys), .I_RSTn(pll_sys_lock),
    .O_psCLK(ds2_clk), .O_psSEL(ds2_cs), .O_psTXD(ds2_mosi), .I_psRXD(ds2_miso),
    .O_RXD_1(), .O_RXD_2(), .O_RXD_3(), .O_RXD_4(), .O_RXD_5(), .O_RXD_6(),
    .snes_btns(pad2)
);
`endif

md20k_core #(.FREQ(FREQ),
`ifdef GT_PAD_RAW
    .P2_SIX_BUTTON(0)
`else
    .P2_SIX_BUTTON(1)
`endif
) core (
    .clk_sys(clk_sys), .clk_z80(clk_z80), .hclk(hclk),
    .flash_cs_n(flash_spi_cs_n), .flash_sck(flash_spi_clk),
    .flash_mosi(flash_spi_mosi), .flash_miso(flash_spi_miso),
    .sd_clk(sd_clk), .sd_cmd(sd_cmd), .sd_dat0(sd_dat0), .sd_dat1(sd_dat1), .sd_dat2(sd_dat2),
    .sd_dat3(sd_dat3), .uart_rx(UART_RXD), .uart_tx(UART_TXD),
    .pad(pad1), .pad2(pad2),
    .sdram_cmd(sdram_cmd), .sdram_a(O_sdram_addr), .sdram_ba(O_sdram_ba), .sdram_dqm(O_sdram_dqm),
    .sdram_dq_out(sdram_dq_out), .sdram_dq_oe(sdram_dq_oe), .sdram_dq_in(IO_sdram_dq),
    .pause_core(pause_core),
    .red(red), .green(green), .blue(blue), .hsync(hsync), .hblank(hblank), .vblank(vblank),
    .ce_pix(ce_pix), .resolution(resolution), .transp(transp), .interlace(interlace), .audio_left(audio_left), .audio_right(audio_right),
    .overlay(overlay), .overlay_x(overlay_x), .overlay_y(overlay_y), .overlay_color(overlay_color),
    .video_opt(video_opt),
    .md_on(md_on), .loading(loading), .dbg_m68k_a()
);

assign led = ~{loading, md_on};

// HDMI ----------------------------------------------------------------------------------
// there are 15 dummy pixels after VBLANK before the first HBLANK
reg ce_pix_r, hblank_r, hsync_seen;
reg [8:0] x;
reg [7:0] y;
always @(posedge clk_sys) begin
    ce_pix_r <= ce_pix;
    hblank_r <= hblank;
    if (vblank) begin
        y <= 0;
        hsync_seen <= 0;
    end
    if (hsync)
        hsync_seen <= 1;
    if (hsync_seen) begin
        if (ce_pix & ~ce_pix_r & ~hblank & ~vblank)
            x <= x + 1'd1;
        if (hblank) begin
            x <= 0;
            if (!hblank_r)
                y <= y + 1'd1;
        end
    end
end

// 720p reads a 224-line frame ~11% slower than the core writes it, so the core runs
// up to ~25 lines ahead by the bottom of the frame: the ring needs 32 lines.
framebuffer #(.WIDTH(320), .HEIGHT(240), .COLOR_BITS(4), .BUFFER_LINES(32)) fb (
    .clk(clk_sys), .resetn(md_on), .clk_pixel(hclk), .clk_5x_pixel(hclk5),
    .ce_pix(ce_pix & hsync_seen), .r(red), .g(green), .b(blue), .transp(transp), .interlace(interlace), .x(x), .y(y),
    .width(resolution[0] ? 11'd320 : 11'd256), .height(resolution[1] ? 10'd240 : 10'd224),
    .audio_left(audio_left), .audio_right(audio_right),
    .overlay(overlay), .overlay_x(overlay_x), .overlay_y(overlay_y), .overlay_color(overlay_color),
    .video_opt(video_opt),
    .pause_core(pause_core),
    .tmds_clk_n(tmds_clk_n), .tmds_clk_p(tmds_clk_p), .tmds_d_n(tmds_d_n), .tmds_d_p(tmds_d_p)
);

endmodule
