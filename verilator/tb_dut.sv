// Device under test: md20k_core (Genesis, SDRAM controller, iosys menu softcore)
// with SDRAM, SPI flash (menu firmware) and TF card (sd.img) models. hclk = clk_sys;
// the C++ driver scans overlay_x/y to capture the menu overlay.
module tb_dut #(
    parameter FIRMWARE_SIZE = 128*1024
) (
    input         clk_sys,
    input         clk_z80,
    input   [7:0] btn_n,            // {start, c, b, a, up, down, left, right}, active low
    input   [3:0] btn_x_n,          // {triangle, R1, L1, select}, active low
    input   [7:0] overlay_x,
    input   [7:0] overlay_y,
    output [14:0] overlay_color,
    output  [3:0] red, green, blue,
    output        hsync, hblank, vblank, ce_pix,
    output  [1:0] resolution,
    output [15:0] audio_left, audio_right,
    output        md_on,
    output        loading,
    output        overlay,
    output        uart_tx,
    output [23:0] dbg_m68k_a,
    output [31:0] sdram_errors, flash_errors, rom_writes_checked, refreshes, max_refresh_gap,
    output [31:0] sd_errors, sd_blocks_read
);

wire        flash_cs_n, flash_sck, flash_mosi, flash_miso;
wire        sd_clk, sd_cmd, sd_dat0;
wire [3:0]  cmd;
wire [10:0] sa;
wire [1:0]  ba;
wire [3:0]  dqm;
wire [31:0] dq_out, dq_in;
wire        dq_oe;

// DualShock layout {R, L, X, A, Right, Left, Down, Up, Start, Select, Y, B}:
// Genesis A = Square (Y), B = Cross (B), C = Circle (A). The Genesis buttons go
// through the same debouncer as tb_ref so game input timing matches.
wire [11:0] joy;
wire [3:0]  bx = ~btn_x_n;
gpio_buttons #(.FREQ(54_000_000)) buttons (.clk(clk_sys), .btn_n(btn_n), .joy(joy));
wire [11:0] pad = {bx[2], bx[1], bx[3], joy[6], joy[0], joy[1], joy[2], joy[3], joy[7], bx[0], joy[4], joy[5]};

md20k_core #(.FIRMWARE_SIZE(FIRMWARE_SIZE)) core (
    .clk_sys(clk_sys), .clk_z80(clk_z80), .hclk(clk_sys),
    .flash_cs_n(flash_cs_n), .flash_sck(flash_sck), .flash_mosi(flash_mosi), .flash_miso(flash_miso),
    .sd_clk(sd_clk), .sd_cmd(sd_cmd), .sd_dat0(sd_dat0), .sd_dat1(), .sd_dat2(), .sd_dat3(),
    .uart_rx(1'b1), .uart_tx(uart_tx),
    .pad(pad), .pad2(12'd0),
    .sdram_cmd(cmd), .sdram_a(sa), .sdram_ba(ba), .sdram_dqm(dqm),
    .sdram_dq_out(dq_out), .sdram_dq_oe(dq_oe), .sdram_dq_in(dq_in),
    .pause_core(pause_core),
    .red(red), .green(green), .blue(blue), .hsync(hsync), .hblank(hblank), .vblank(vblank),
    .ce_pix(ce_pix), .resolution(resolution), .audio_left(audio_left), .audio_right(audio_right),
    .overlay(overlay), .overlay_x(overlay_x), .overlay_y(overlay_y), .overlay_color(overlay_color),
    .md_on(md_on), .loading(loading), .dbg_m68k_a(dbg_m68k_a)
);

sdram_model #(.PRELOAD(0), .ROM_BYTES(4194304)) chip (
    .clk(clk_sys), .cmd(cmd), .a(sa), .ba(ba), .dqm(dqm), .dq_out(dq_out), .dq_oe(dq_oe), .dq_in(dq_in),
    .errors(sdram_errors), .rom_writes_checked(rom_writes_checked), .refreshes(refreshes),
    .max_refresh_gap_cycles(max_refresh_gap)
);

spiflash_model #(.HEX("fw8.hex"), .SIZE(262144)) flash (
    .clk(clk_sys), .cs_n(flash_cs_n), .sck(flash_sck), .mosi(flash_mosi), .miso(flash_miso),
    .errors(flash_errors)
);

sd_card_model sd (
    .clk(clk_sys), .sck(sd_clk), .mosi(sd_cmd), .miso(sd_dat0),
    .errors(sd_errors), .blocks_read(sd_blocks_read)
);

perf68k perf (
    .clk(clk_sys), .clken(core.megadrive.M68K_CLKENp), .as_n(core.megadrive.M68K_AS_N),
    .a(core.megadrive.M68K_A), .vblank(vblank),
    .vdp_br_n(core.megadrive.VBUS_BR_N), .vdp_bgack_n(core.megadrive.VBUS_BGACK_N),
    .z80_br_n(core.megadrive.Z80_BR_N), .z80_bgack_n(core.megadrive.Z80_BGACK_N)
);

// +hdmisync: lock the core to a 60.00 Hz HDMI frame like the board does (mdtang_top.sv).
// 720p60 is 900000 clk_sys per frame; its first 4:3 line lasts ~1080 clk_sys.
wire pause_core;
bit  hdmisync, hdmisync_old;
initial begin
    hdmisync_old = $test$plusargs("hdmisync_old");
    hdmisync = $test$plusargs("hdmisync") | hdmisync_old;
end
reg [19:0] hdmi_cnt = 20'd0;
always @(posedge clk_sys) hdmi_cnt <= hdmi_cnt == 20'd899999 ? 20'd0 : hdmi_cnt + 20'd1;

reg ce_pix_r, hblank_r, hsync_seen;
reg [8:0] fx;
reg [7:0] fy;
always @(posedge clk_sys) begin
    ce_pix_r <= ce_pix;
    hblank_r <= hblank;
    if (vblank) begin
        fy <= 0;
        hsync_seen <= 0;
    end
    if (hsync)
        hsync_seen <= 1;
    if (hsync_seen) begin
        if (ce_pix & ~ce_pix_r & ~hblank & ~vblank)
            fx <= fx + 1'd1;
        if (hblank) begin
            fx <= 0;
            if (!hblank_r)
                fy <= fy + 1'd1;
        end
    end
end

frame_sync fsync (
    .clk(clk_sys), .resetn((md_on | hdmisync_old) & hdmisync), .x(fx), .y(fy),
    .hdmi_first_line(hdmi_cnt < 20'd1080), .pause_core(pause_core)
);

endmodule
