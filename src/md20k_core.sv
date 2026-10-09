// Genesis core, memory, and TF card menu for Gen Thang on the Tang Nano 20K.
// The Genesis, SDRAM controller and ROM loader run on clk_sys; the iosys menu
// softcore (PicoRV32, SD card, on-screen menu) runs on clk_z80 = clk_sys / 2.
//
// Boot: SDRAM init -> zero VRAM, iosys copies its firmware from SPI flash 0x500000
//       into SDRAM -> the firmware shows the menu and streams the chosen ROM from
//       the SD card -> the Genesis is released from reset.

module md20k_core #(
    parameter FREQ = 54_000_000,
    parameter FIRMWARE_SIZE = 256*1024,
    parameter SDRAM_PIPELINE = 1,
    parameter P2_SIX_BUTTON = 1
) (
    input             clk_sys,
    input             clk_z80,          // clk_sys / 2 from the same PLL
    input             hclk,             // HDMI pixel clock, for the menu overlay

    // SPI flash holding the menu firmware
    output            flash_cs_n,
    output            flash_sck,
    output            flash_mosi,
    input             flash_miso,

    // TF card, SPI mode
    output            sd_clk,
    output            sd_cmd,
    input             sd_dat0,
    output            sd_dat1,
    output            sd_dat2,
    output            sd_dat3,

    // firmware debug console
    input             uart_rx,
    output            uart_tx,

    // DualShock pad and/or DB9 Genesis pad, active high: {R, L, X, A, Right, Left, Down, Up, Start, Select, Y, B}
    // Genesis 6-button: Square A, Cross B, Circle C, L1 X, Triangle Y, R1 Z, Select Mode.
    // Menu: Select+Start (Mode+Start), or Start+A+B+C for 3-button pads.
    input      [11:0] pad,
    input      [11:0] pad2,             // player 2, same layout

    // SDRAM (data bus split; tristate in the top level)
    output      [3:0] sdram_cmd,        // {nCS, nRAS, nCAS, nWE}
    output     [10:0] sdram_a,
    output      [1:0] sdram_ba,
    output      [3:0] sdram_dqm,
    output     [31:0] sdram_dq_out,
    output            sdram_dq_oe,
    input      [31:0] sdram_dq_in,

    // video / audio
    input             pause_core,
    output      [3:0] red,
    output      [3:0] green,
    output      [3:0] blue,
    output            hsync,
    output            hblank,
    output            vblank,
    output            ce_pix,
    output      [1:0] resolution,
    output            transp,
    output            interlace,
    output     [15:0] audio_left,
    output     [15:0] audio_right,

    // menu overlay; overlay_x/y and overlay_color are in the hclk domain
    output            overlay,
    input       [7:0] overlay_x,
    input       [7:0] overlay_y,
    output     [14:0] overlay_color,
    output      [3:0] video_opt,        // clk_z80 domain, quasi-static

    output reg        md_on,
    output            loading,
    output     [23:0] dbg_m68k_a
);

// reset
reg        reset = 1'b1;
reg [15:0] reset_cnt = 16'hFFFF;
always @(posedge clk_sys) begin
    if (reset_cnt != 0) reset_cnt <= reset_cnt - 16'd1;
    else reset <= 1'b0;
end

// Genesis 6-button pad: {Z, Y, X, Mode, Start, C, B, A, Up, Down, Left, Right}
function [11:0] genesis_pad(input [11:0] p);
    genesis_pad = {p[11], p[9], p[10], p[2], p[3], p[8], p[0], p[1], p[4], p[5], p[6], p[7]};
endfunction
wire [11:0] joy1 = genesis_pad(pad);
wire [11:0] joy2 = genesis_pad(pad2);
wire        menu_key = pad[3] & (pad[2] | (pad[1] & pad[0] & pad[8]));

wire sdram_ready, vram_clear_done;

// iosys (clk_z80) --------------------------------------------------------------------
wire        rv_valid;
wire [22:0] rv_addr;
wire [31:0] rv_wdata;
wire [3:0]  rv_wstrb;
reg         rv_ready_z;
wire [31:0] rv_dout;                    // held by the SDRAM controller until the next RV read
wire        rom_loading_z, rom_req_z;
wire [31:0] rom_word;
reg         rom_ack;
wire [3:0]  ss_ctrl_z;

iosys_picorv32 #(.FREQ(FREQ / 2), .CORE_ID(4), .FIRMWARE_SIZE(FIRMWARE_SIZE)) iosys (
    .clk(clk_z80), .hclk(hclk), .resetn(~reset),
    .overlay(overlay), .overlay_x(overlay_x), .overlay_y(overlay_y), .overlay_color(overlay_color),
    .video_opt(video_opt), .ss_ctrl(ss_ctrl_z),
    .joy1(pad), .joy2(pad2),
    .rom_loading(rom_loading_z), .core_ready(md_on), .rom_word(rom_word), .rom_req(rom_req_z), .rom_ack(rom_ack),
    .rv_valid(rv_valid), .rv_ready(rv_ready_z), .rv_addr(rv_addr), .rv_wdata(rv_wdata),
    .rv_wstrb(rv_wstrb), .rv_rdata(rv_dout), .ram_busy(~sdram_ready),
    .flash_spi_cs_n(flash_cs_n), .flash_spi_miso(flash_miso), .flash_spi_mosi(flash_mosi),
    .flash_spi_clk(flash_sck), .flash_spi_wp_n(), .flash_spi_hold_n(),
    .uart_rx(uart_rx), .uart_tx(uart_tx),
    .sd_clk(sd_clk), .sd_cmd(sd_cmd), .sd_dat0(sd_dat0), .sd_dat1(sd_dat1), .sd_dat2(sd_dat2),
    .sd_dat3(sd_dat3)
);

// RV memory bridge. clk_z80 -> clk_sys paths have 4 clk_sys cycles (mdtang.sdc), so the
// request fields are registered one clk_z80 cycle before the toggle, which then goes
// through a 2-flop synchronizer. clk_sys -> clk_z80 paths are timed normally.
// While a game runs with the menu hidden the softcore is stalled at its next SDRAM
// access (keeping the SDRAM free for the Genesis) until the menu key is held.
wire        rv_ack;
reg  [1:0]  rvb_st = 2'd0;
reg         rv_req_z = 1'b0;
reg  [22:2] rvb_addr;
reg  [31:0] rvb_din;
reg  [3:0]  rvb_be;
reg         rvb_we;
wire        rv_hold = md_on & ~overlay & ~menu_key;

always @(posedge clk_z80) begin
    rv_ready_z <= 1'b0;
    case (rvb_st)
    2'd0: if (rv_valid && !rv_ready_z && !rv_hold) begin
        rvb_addr <= rv_addr[22:2];
        rvb_din <= rv_wdata;
        rvb_be <= rv_wstrb;
        rvb_we <= |rv_wstrb;
        rvb_st <= 2'd1;
    end
    2'd1: begin
        rv_req_z <= ~rv_req_z;
        rvb_st <= 2'd2;
    end
    2'd2: if (rv_ack == rv_req_z) begin
        rv_ready_z <= 1'b1;
        rvb_st <= 2'd0;
    end
    default: rvb_st <= 2'd0;
    endcase
    if (reset) rvb_st <= 2'd0;
end

reg [1:0] rv_req_s = 2'b00;
always @(posedge clk_sys) rv_req_s <= {rv_req_s[0], rv_req_z};

// ROM loader (clk_sys): one 32-bit SDRAM write per rom_word -------------------------
// File bytes b0..b3 arrive as rom_word = {b3,b2,b1,b0}; Genesis words are big-endian
// and word 0 sits in the low half of the 32-bit SDRAM word.
reg  [1:0]  rom_req_s = 2'b00;
reg  [1:0]  loading_s = 2'b00;
reg  [1:0]  overlay_s = 2'b00;
reg  [3:0]  ss_s1, ss_ctrl;             // quasi-static: firmware waits between changes
always @(posedge clk_sys) {ss_ctrl, ss_s1} <= {ss_s1, ss_ctrl_z};
reg         loading_r, start_pend, ld_busy;
reg         ld_req = 1'b0;
wire        ld_ack;
reg  [20:0] ld_cnt;                     // 32-bit words written (4MB max)
wire [31:0] ld_din = {rom_word[23:16], rom_word[31:24], rom_word[7:0], rom_word[15:8]};
assign loading = loading_s[1];

always @(posedge clk_sys) begin
    rom_req_s <= {rom_req_s[0], rom_req_z};
    loading_s <= {loading_s[0], rom_loading_z};
    overlay_s <= {overlay_s[0], overlay};
    loading_r <= loading;

    if (ld_busy) begin
        if (ld_req == ld_ack) begin
            ld_busy <= 1'b0;
            ld_cnt <= ld_cnt + 21'd1;
            rom_ack <= ~rom_ack;
        end
    end else if (rom_req_s[1] != rom_ack) begin
        if (ld_cnt[20])
            rom_ack <= ~rom_ack;        // beyond 4MB: drop
        else begin
            ld_req <= ~ld_req;
            ld_busy <= 1'b1;
        end
    end

    if (loading && !loading_r) begin
        md_on <= 1'b0;
        ld_cnt <= 21'd0;
    end
    if (!loading && loading_r)
        start_pend <= 1'b1;
    if (start_pend && !ld_busy && rom_req_s[1] == rom_ack && vram_clear_done) begin
        start_pend <= 1'b0;
        md_on <= 1'b1;
    end

    if (reset) begin
        md_on <= 1'b0;
        start_pend <= 1'b0;
        ld_busy <= 1'b0;
        ld_cnt <= 21'd0;
        rom_ack <= rom_req_s[1];
    end
end

// Menu Reset Game resets the CPUs without applying the power-on reset used while no
// game is loaded. SDRAM and the rest of the console state remain live, matching the
// short physical reset-button press required by games such as X-Men.
wire reset_btn = ss_ctrl[2:0] == 3'b110;

// Genesis ------------------------------------------------------------------------------
wire [24:1] mem_addr;
wire [15:0] mem_data, mem_wdata;
wire [1:0]  mem_be;
wire        mem_req, mem_ack, mem_we;

wire        vram_req, vram_ack, vram_we, vram_u_n, vram_l_n;
wire [15:1] vram_a;
wire [15:0] vram_d, vram_q;
wire        vram32_req, vram32_ack;
wire [15:1] vram32_a;
wire [31:0] vram32_q;
wire [15:0] core_audio_left, core_audio_right;

assign audio_left  = overlay_s[1] ? 16'd0 : core_audio_left;
assign audio_right = overlay_s[1] ? 16'd0 : core_audio_right;

system #(.P2_SIX_BUTTON(P2_SIX_BUTTON)) megadrive (
    .MCLK(clk_sys), .CLK_Z80(clk_z80), .RESET_N(md_on), .SOFT_RESET(reset_btn),
    .LPF_MODE(2'b11), .ENABLE_FM(1'b1), .ENABLE_PSG(1'b1), .DAC_LDATA(core_audio_left), .DAC_RDATA(core_audio_right),
    .LOADING(loading), .PAL(1'b0), .EXPORT(1'b1), .FAST_FIFO(1'b0), .SRAM_QUIRK(1'b0), .SRAM00_QUIRK(1'b0),
    .EEPROM_QUIRK(1'b0), .NORAM_QUIRK(1'b0), .PIER_QUIRK(1'b0), .SVP_QUIRK(1'b0), .FMBUSY_QUIRK(1'b0),
    .SCHAN_QUIRK(1'b0), .TURBO(2'b00),
    .GG_RESET(1'b0), .GG_EN(1'b0), .GG_CODE(129'd0), .GG_AVAILABLE(),
    .BRAM_A(15'd0), .BRAM_DI(16'd0), .BRAM_DO(), .BRAM_WE(1'b0), .BRAM_CHANGE(),
    .RED(red), .GREEN(green), .BLUE(blue), .VS(), .HS(hsync), .HBL(hblank), .VBL(vblank), .CE_PIX(ce_pix),
    .BORDER(1'b0), .CRAM_DOTS(ss_ctrl[3]), .INTERLACE(interlace), .FIELD(), .RESOLUTION(resolution),
    .J3BUT(1'b0), .JOY_1(joy1), .JOY_2(joy2), .JOY_3(12'd0), .JOY_4(12'd0), .JOY_5(12'd0), .MULTITAP(3'd0),
    .MOUSE(25'd0), .MOUSE_OPT(3'd0), .GUN_OPT(1'b0), .GUN_TYPE(1'b0), .GUN_SENSOR(1'b0), .GUN_A(1'b0),
    .GUN_B(1'b0), .GUN_C(1'b0), .GUN_START(1'b0),
    .SERJOYSTICK_IN(8'd0), .SERJOYSTICK_OUT(), .SER_OPT(2'd0),
    .ROMSZ({3'b000, ld_cnt[19:0], 1'b0}),
    .MEM_ADDR(mem_addr), .MEM_DATA(mem_data), .MEM_WDATA(mem_wdata), .MEM_WE(mem_we), .MEM_BE(mem_be),
    .MEM_REQ(mem_req), .MEM_ACK(mem_ack),
    .VRAM_REQ(vram_req), .VRAM_ACK(vram_ack), .VRAM_WE(vram_we), .VRAM_U_N(vram_u_n), .VRAM_L_N(vram_l_n),
    .VRAM_A(vram_a), .VRAM_D(vram_d), .VRAM_Q(vram_q),
    .VRAM32_REQ(vram32_req), .VRAM32_ACK(vram32_ack), .VRAM32_A(vram32_a), .VRAM32_Q(vram32_q),
    .EN_HIFI_PCM(1'b0), .LADDER(1'b0), .OBJ_LIMIT_HIGH(1'b0), .TRANSP_DETECT(transp),
    .PAUSE_EN(pause_core | (overlay_s[1] & ~ss_ctrl[0])), .BGA_EN(1'b1), .BGB_EN(1'b1), .SPR_EN(1'b1), .DBG_M68K_A(dbg_m68k_a), .DBG_VBUS_A(),
    .SS_EN(ss_ctrl[0]), .SS_NMI(ss_ctrl[1]), .SS_ZFREEZE(ss_ctrl[2])
);

// SDRAM ----------------------------------------------------------------------------------
sdram_md20k #(.FREQ(FREQ), .PIPELINE_READS(SDRAM_PIPELINE)) sdram (
    .clk(clk_sys), .resetn(~reset), .ready(sdram_ready), .rd_lat(3'd3),
    .cmd(sdram_cmd), .sa(sdram_a), .ba(sdram_ba), .dqm(sdram_dqm),
    .dq_out(sdram_dq_out), .dq_oe(sdram_dq_oe), .dq_in(sdram_dq_in),

    .mem_req(mem_req), .mem_ack(mem_ack), .mem_we(mem_we), .mem_addr(mem_addr),
    .mem_din(mem_wdata), .mem_be(mem_be), .mem_dout(mem_data),

    .v16_req(vram_req), .v16_ack(vram_ack), .v16_we(vram_we), .v16_addr(vram_a),
    .v16_din(vram_d), .v16_be(~{vram_u_n, vram_l_n}), .v16_dout(vram_q),

    .v32_req(vram32_req), .v32_ack(vram32_ack), .v32_addr(vram32_a[15:2]), .v32_dout(vram32_q),

    .rv_req(rv_req_s[1]), .rv_ack(rv_ack), .rv_we(rvb_we), .rv_addr(rvb_addr), .rv_din(rvb_din),
    .rv_be(rvb_be), .rv_dout(rv_dout),

    .ld_req(ld_req), .ld_ack(ld_ack), .ld_addr(ld_cnt[19:0]), .ld_din(ld_din),

    .vram_clear(sdram_ready), .vram_clear_done(vram_clear_done)
);

endmodule
