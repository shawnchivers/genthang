// Golden reference: Genesis system with the original BRAM VRAM and ideal memory.
module tb_ref (
    input         clk_sys,
    input         clk_z80,
    input   [7:0] btn_n,
    output  [3:0] red, green, blue,
    output        hsync, hblank, vblank, ce_pix,
    output  [1:0] resolution,
    output [15:0] audio_left, audio_right,
    output reg    md_on,
    output [23:0] dbg_m68k_a,
    output [31:0] sdram_errors, flash_errors, rom_writes_checked, refreshes, max_refresh_gap
);

assign sdram_errors = 0;
assign flash_errors = 0;
assign rom_writes_checked = 0;
assign refreshes = 0;
assign max_refresh_gap = 0;

reg [15:0] rst_cnt = 0;
always @(posedge clk_sys) begin
    if (rst_cnt != 16'd2000) rst_cnt <= rst_cnt + 16'd1;
    md_on <= rst_cnt == 16'd2000;
end

wire [11:0] joy1;
gpio_buttons #(.FREQ(54_000_000)) buttons (.clk(clk_sys), .btn_n(btn_n), .joy(joy1));

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

system megadrive (
    .MCLK(clk_sys), .CLK_Z80(clk_z80), .RESET_N(md_on),
    .LPF_MODE(2'b11), .ENABLE_FM(1'b1), .ENABLE_PSG(1'b1), .DAC_LDATA(audio_left), .DAC_RDATA(audio_right),
    .LOADING(~md_on), .PAL(1'b0), .EXPORT(1'b1), .FAST_FIFO(1'b0), .SRAM_QUIRK(1'b0), .SRAM00_QUIRK(1'b0),
    .EEPROM_QUIRK(1'b0), .NORAM_QUIRK(1'b0), .PIER_QUIRK(1'b0), .SVP_QUIRK(1'b0), .FMBUSY_QUIRK(1'b0),
    .SCHAN_QUIRK(1'b0), .TURBO(2'b00),
    .GG_RESET(1'b0), .GG_EN(1'b0), .GG_CODE(129'd0), .GG_AVAILABLE(),
    .BRAM_A(15'd0), .BRAM_DI(16'd0), .BRAM_DO(), .BRAM_WE(1'b0), .BRAM_CHANGE(),
    .RED(red), .GREEN(green), .BLUE(blue), .VS(), .HS(hsync), .HBL(hblank), .VBL(vblank), .CE_PIX(ce_pix),
    .BORDER(1'b0), .CRAM_DOTS(1'b0), .INTERLACE(), .FIELD(), .RESOLUTION(resolution),
    .J3BUT(1'b0), .JOY_1(joy1), .JOY_2(12'd0), .JOY_3(12'd0), .JOY_4(12'd0), .JOY_5(12'd0), .MULTITAP(3'd0),
    .MOUSE(25'd0), .MOUSE_OPT(3'd0), .GUN_OPT(1'b0), .GUN_TYPE(1'b0), .GUN_SENSOR(1'b0), .GUN_A(1'b0),
    .GUN_B(1'b0), .GUN_C(1'b0), .GUN_START(1'b0),
    .SERJOYSTICK_IN(8'd0), .SERJOYSTICK_OUT(), .SER_OPT(2'd0),
    .ROMSZ(24'h200000),
    .MEM_ADDR(mem_addr), .MEM_DATA(mem_data), .MEM_WDATA(mem_wdata), .MEM_WE(mem_we), .MEM_BE(mem_be),
    .MEM_REQ(mem_req), .MEM_ACK(mem_ack),
    .VRAM_REQ(vram_req), .VRAM_ACK(vram_ack), .VRAM_WE(vram_we), .VRAM_U_N(vram_u_n), .VRAM_L_N(vram_l_n),
    .VRAM_A(vram_a), .VRAM_D(vram_d), .VRAM_Q(vram_q),
    .VRAM32_REQ(vram32_req), .VRAM32_ACK(vram32_ack), .VRAM32_A(vram32_a), .VRAM32_Q(vram32_q),
    .EN_HIFI_PCM(1'b0), .LADDER(1'b0), .OBJ_LIMIT_HIGH(1'b0), .TRANSP_DETECT(),
    .PAUSE_EN(1'b0), .BGA_EN(1'b1), .BGB_EN(1'b1), .SPR_EN(1'b1), .DBG_M68K_A(dbg_m68k_a), .DBG_VBUS_A(),
    .SS_EN(1'b0), .SS_NMI(1'b0), .SS_ZFREEZE(1'b0)
);

vram vram (
    .clk(clk_sys), .loading(~md_on),
    .vram_req(vram_req), .vram_ack(vram_ack), .vram_we(vram_we), .vram_u_n(vram_u_n), .vram_l_n(vram_l_n),
    .vram_a(vram_a), .vram_d(vram_d), .vram_q(vram_q),
    .vram32_req(vram32_req), .vram32_ack(vram32_ack), .vram32_a(vram32_a), .vram32_q(vram32_q)
);

ideal_mem #(.ROM_WORDS(2097152)) mem (
    .clk(clk_sys), .req(mem_req), .ack(mem_ack), .we(mem_we), .addr(mem_addr),
    .din(mem_wdata), .be(mem_be), .dout(mem_data)
);

perf68k perf (
    .clk(clk_sys), .clken(megadrive.M68K_CLKENp), .as_n(megadrive.M68K_AS_N),
    .a(megadrive.M68K_A), .vblank(vblank),
    .vdp_br_n(megadrive.VBUS_BR_N), .vdp_bgack_n(megadrive.VBUS_BGACK_N),
    .z80_br_n(megadrive.Z80_BR_N), .z80_bgack_n(megadrive.Z80_BGACK_N)
);

endmodule
