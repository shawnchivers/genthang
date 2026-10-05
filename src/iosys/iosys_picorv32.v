// IOSys - PicoRV32-based I/O subsystem adapted for Gen Thang.
//
// IOSys provides the following functionality,
// - Menu system
// - ROM file loading
// - Configuration options
// - USB serial ROM uploads
// - Save-state control
//
// This is similar to the IO controller of MIST, or HPS of MiSTer.
//
// Based on the IOSys block of SNESTang / MDTang (nand2mario, GPL-3.0); modified
// for Gen Thang (Nano 20K clocking, USB serial upload, save-state and video
// option registers).
//
// The softcore runs RV32I at 21.6Mhz and uses SDRAM as main memory. Firmware is 
// loaded from SPI flash on the board. Firmware source is in firmware/.
//

`define MCU_PICORV32

`ifndef PICORV32_REGS
`ifdef PICORV32_V
`error "iosys.v must be read before picorv32.v!"
`endif

`define PICORV32_REGS picosoc_regs
`endif

`ifndef PICOSOC_MEM
`define PICOSOC_MEM picosoc_mem
`endif

// this macro can be used to check if the verilog files in your
// design are read in the correct order.
`define PICOSOC_V

module iosys_picorv32 #(
    parameter FREQ=21_477_000,
    parameter [14:0] COLOR_LOGO=15'b00000_10101_00000,
    parameter [15:0] CORE_ID=1,     // inherited core identifier; unused by Gen Thang
    parameter FIRMWARE_SIZE = 256*1024
)
(
    input clk,                      // system clock
    input hclk,                     // hdmi clock
//    input clkref,                   // 1/2 of mclk, for sdram access synchronization
    input resetn,

    // OSD display interface
    output overlay,
    input [7:0] overlay_x,          // 0-255
    input [7:0] overlay_y,          // 0-223
    output [14:0] overlay_color,    // BGR5
    output reg [3:0] video_opt,     // [1:0] scanlines off/25%/50%, [3:2] composite blend off/on/adaptive
    output reg [3:0] ss_ctrl,       // save state: [0] window/hooks on, [1] 68K NMI, [2] Z80 freeze; [3] game reset
    input [11:0] joy1,              // joystick 1: (R L X A RT LT DN UP START SELECT Y B)
    input [11:0] joy2,              // joystick 2

    // ROM loading interface
    output reg rom_loading,         // 0-to-1 loading starts, 1-to-0 loading is finished
    input      core_ready,          // game CPU has left reset after loading
    output reg [31:0] rom_word,     // 4 file bytes, first byte in [7:0]
    output reg rom_req,             // toggles for each rom_word; the next one waits for rom_ack
    input      rom_ack,
    
    // 32-bit wide memory interface for risc-v softcore
    // rv_valid stays high until the rv_ready pulse
    output rv_valid,                // 1: active memory access
    input rv_ready,                 // pulse when access is done
    output [22:0] rv_addr,          // 8MB memory space
    output [31:0] rv_wdata,         // 32-bit write data
    output [3:0] rv_wstrb,          // 4 byte write strobe
    input [31:0] rv_rdata,          // 32-bit read data

    input ram_busy,                 // iosys starts after SDRAM initialization

    // SPI flash
    output flash_spi_cs_n,          // chip select
    input  flash_spi_miso,          // master in slave out
    output flash_spi_mosi,          // mster out slave in
    output flash_spi_clk,           // spi clock
    output flash_spi_wp_n,          // write protect
    output flash_spi_hold_n,        // hold operations

    // UART
    input uart_rx,
    output uart_tx,

    // SD card
    output sd_clk,
    output sd_cmd,                  // MOSI
    input  sd_dat0,                 // MISO
    output sd_dat1,                 // 1
    output sd_dat2,                 // 1
    output sd_dat3                  // 0 for SPI mode
);

/* verilator lint_off PINMISSING */
/* verilator lint_off WIDTHTRUNC */

reg flash_loaded;
reg flash_loading;
reg [20:0] flash_addr = {21{1'b1}};

reg flash_start;
wire [7:0] flash_dout;
wire flash_out_strb;
assign flash_spi_hold_n = 1;
assign flash_spi_wp_n = 1;      // disable write protection
reg [31:0] flash_word;
reg flash_wr;                   // held until rv_ready
reg flash_last;
wire [31:0] spiflash_reg_do;
wire spiflash_reg_wait;

// copy the firmware into RV memory one 32-bit word at a time
always @(posedge clk) begin
    if (~resetn) begin
        flash_loaded <= 0;
        flash_loading <= 0;
        flash_wr <= 0;
        flash_last <= 0;
        flash_addr <= {21{1'b1}};
    end else begin
        flash_start <= 0;

        if (~flash_loaded && ~flash_loading && ~ram_busy) begin
            // start loading
            flash_start <= 1;
            flash_loading <= 1;
        end

        if (flash_loading) begin
            if (flash_out_strb) begin
                reg [20:0] next_addr = flash_addr + 1;
                flash_addr <= next_addr;
                flash_word[next_addr[1:0]*8 +: 8] <= flash_dout;
                if (next_addr[1:0] == 2'b11) flash_wr <= 1;
                if (next_addr == FIRMWARE_SIZE-1) flash_last <= 1;
            end
            if (flash_wr && rv_ready) begin
                flash_wr <= 0;
                if (flash_last) begin
                    flash_loading <= 0;
                    flash_loaded <= 1;
                end
            end
        end
    end
end

// picorv32 softcore
wire mem_valid /* synthesis syn_keep=1 */;
wire mem_ready;
wire [31:0] mem_addr /* synthesis syn_keep=1 */, mem_wdata /* synthesis syn_keep=1 */;
wire [3:0] mem_wstrb /* synthesis syn_keep=1 */;
wire [31:0] mem_rdata /* synthesis syn_keep=1 */;

reg ram_ready /* synthesis syn_keep=1 */;
reg [31:0] ram_rdata;

wire        ram_sel = mem_valid && mem_addr[31:23] == 0;

wire        textdisp_reg_char_sel /* synthesis syn_keep=1 */= mem_valid && (mem_addr == 32'h 0200_0000);

wire        simpleuart_reg_div_sel = mem_valid && (mem_addr == 32'h 0200_0010);
wire [31:0] simpleuart_reg_div_do;

wire        simpleuart_reg_dat_sel /* synthesis syn_keep=1 */ = mem_valid && (mem_addr == 32'h 0200_0014);
wire [31:0] simpleuart_reg_dat_do;
wire        simpleuart_reg_dat_wait;

wire        simplespimaster_reg_byte_sel /* synthesis syn_keep=1 */ = mem_valid && (mem_addr == 32'h0200_0020);
wire        simplespimaster_reg_word_sel /* synthesis syn_keep=1 */ = mem_valid && (mem_addr == 32'h0200_0024);
wire [31:0] simplespimaster_reg_do;
wire        simplespimaster_reg_wait /* synthesis syn_keep=1 */;

wire        romload_reg_ctrl_sel /* synthesis syn_keep=1 */ = mem_valid && (mem_addr == 32'h 0200_0030);       // write 1 to start loading, 0 to finish loading
wire        romload_reg_data_sel /* synthesis syn_keep=1 */ = mem_valid && (mem_addr == 32'h 0200_0034);       // write once to load 4 bytes

wire        joystick_reg_sel = mem_valid && (mem_addr == 32'h 0200_0040);

wire        time_reg_sel = mem_valid && (mem_addr == 32'h0200_0050);        // milli-seconds since start-up (overflows in 49 days)
wire        cycle_reg_sel = mem_valid && (mem_addr == 32'h0200_0054);       // cycles counter (overflows every 200 seconds)

wire        id_reg_sel = mem_valid && (mem_addr == 32'h0200_0060);

wire        spiflash_reg_byte_sel = mem_valid && (mem_addr == 32'h0200_0070);
wire        spiflash_reg_ctrl_sel = mem_valid && (mem_addr == 32'h0200_0078);

assign mem_ready = ram_ready || textdisp_reg_char_sel || simpleuart_reg_div_sel || 
            romload_reg_ctrl_sel || (romload_reg_data_sel && !rom_wait) || joystick_reg_sel || time_reg_sel || cycle_reg_sel || id_reg_sel ||
            (simpleuart_reg_dat_sel && !simpleuart_reg_dat_wait) ||
            ((simplespimaster_reg_byte_sel || simplespimaster_reg_word_sel) && !simplespimaster_reg_wait) ||
            spiflash_reg_byte_sel && !spiflash_reg_wait ||
            spiflash_reg_ctrl_sel;

assign mem_rdata = ram_ready ? ram_rdata :
    romload_reg_ctrl_sel ? {31'd0, core_ready} :
        joystick_reg_sel ? {4'b0, joy2, 4'b0, joy1} :
        simpleuart_reg_div_sel ? simpleuart_reg_div_do :
        simpleuart_reg_dat_sel ? simpleuart_reg_dat_do : 
        time_reg_sel ? {8'd0, time_reg} :
        cycle_reg_sel ? 32'd0 :
        id_reg_sel ? {16'b0, CORE_ID} :
        (simplespimaster_reg_byte_sel | simplespimaster_reg_word_sel) ? simplespimaster_reg_do : 
        spiflash_reg_byte_sel ? spiflash_reg_do :
        32'h 0000_0000;

picorv32 #(
    // .ENABLE_MUL(1),
    // .ENABLE_DIV(1),
    // .COMPRESSED_ISA(1)
    .CATCH_ILLINSN(0),
    .ENABLE_COUNTERS (0),
    .ENABLE_COUNTERS64 (0),
    .CATCH_MISALIGN (0),
    .TWO_STAGE_SHIFT(0)
) rv32 (
    .clk(clk), .resetn(resetn & flash_loaded),
    .mem_valid(mem_valid), .mem_ready(mem_ready), .mem_addr(mem_addr), 
    .mem_wdata(mem_wdata), .mem_wstrb(mem_wstrb), .mem_rdata(mem_rdata)
);

// text display @ 0x0200_0000
textdisp disp (
    .clk(clk), .hclk(hclk), .resetn(resetn),
    .x(overlay_x), .y(overlay_y), .color(overlay_color),
    .reg_char_we(textdisp_reg_char_sel ? mem_wstrb : 4'b0),
    .reg_char_di(mem_wdata) 
);

// toggle overlay display on/off; textdisp register 1 holds the video options
reg overlay_buf = 1;
assign overlay = overlay_buf;
always @(posedge clk) begin
    if (~resetn) begin
        overlay_buf <= 1;
        video_opt <= 4'd0;
        ss_ctrl <= 4'd0;
    end else begin
        if (textdisp_reg_char_sel && mem_wstrb[0]) begin
            case (mem_wdata[25:24])
            2'd1: overlay_buf <= 1;
            2'd2: overlay_buf <= 0;
            2'd3: if (mem_wdata[23:16] == 8'd1) video_opt <= mem_wdata[3:0];
                  else if (mem_wdata[23:16] == 8'd2) ss_ctrl <= mem_wdata[3:0];
            default: ;
            endcase
        end 
    end
end

// uart @ 0x0200_0010
simpleuart simpleuart (
    .clk         (clk         ),
    .resetn      (resetn       ),

    .ser_tx      (uart_tx      ),
    .ser_rx      (uart_rx      ),

    .reg_div_we  (simpleuart_reg_div_sel ? mem_wstrb : 4'b0),
    .reg_div_di  (mem_wdata),
    .reg_div_do  (simpleuart_reg_div_do),

    .reg_dat_we  (simpleuart_reg_dat_sel ? mem_wstrb[0] : 1'b0),
    .reg_dat_re  (simpleuart_reg_dat_sel && !mem_wstrb),
    .reg_dat_di  (mem_wdata),
    .reg_dat_do  (simpleuart_reg_dat_do),
    .reg_dat_wait(simpleuart_reg_dat_wait)
);

// spi sd card @ 0x0200_0020
assign sd_dat1 = 1;
assign sd_dat2 = 1;
assign sd_dat3 = 0;
simplespimaster simplespi (
    .clk(clk), .resetn(resetn),
    .sck(sd_clk), .mosi(sd_cmd), .miso(sd_dat0),
    .reg_byte_we(simplespimaster_reg_byte_sel ? mem_wstrb[0] : 1'b0),
    .reg_word_we(simplespimaster_reg_word_sel ? mem_wstrb[0] : 1'b0),
    .reg_di(mem_wdata),
    .reg_do(simplespimaster_reg_do),
    .reg_wait(simplespimaster_reg_wait)
);

// ROM loading I/O @ 0x02000_0030
// rom_word is registered one cycle before rom_req toggles, so the receiver can
// synchronize rom_req and then use rom_word directly.
reg rom_go;
wire rom_wait = rom_go || (rom_req != rom_ack);
always @(posedge clk) begin
    rom_go <= 0;
    if (~resetn) begin
        rom_req <= rom_ack;
    end else begin
        if (romload_reg_data_sel && mem_wstrb && !rom_wait) begin
            rom_word <= mem_wdata;
            rom_go <= 1;
        end
        if (rom_go)
            rom_req <= ~rom_req;
    end
end
always @(posedge clk) begin
    if (~resetn)
        rom_loading <= 0;
    else if (romload_reg_ctrl_sel && mem_wstrb) begin
        // control register
        if (mem_wdata[7:0] == 8'd1)
            rom_loading <= 1;
        if (mem_wdata[7:0] == 8'd0)
            rom_loading <= 0;
    end    
end

// SPI flash @ 0x02000_0070
// Load the firmware from flash address 0x500000 into RV memory at address 0x0
spiflash #(.ADDR(24'h500000), .LEN(FIRMWARE_SIZE)) flash (
    .clk(clk), .resetn(resetn),
    .ncs(flash_spi_cs_n), .miso(flash_spi_miso), .mosi(flash_spi_mosi),
    .sck(flash_spi_clk), 

    .start(flash_start), .dout(flash_dout), .dout_strb(flash_out_strb), .busy(),

    .reg_byte_we(spiflash_reg_byte_sel ? mem_wstrb[0] : 1'b0),
    .reg_word_we(1'b0),
    .reg_ctrl_we(spiflash_reg_ctrl_sel ? mem_wstrb[0] : 1'b0),
    .reg_di(mem_wdata), .reg_do(spiflash_reg_do), .reg_wait(spiflash_reg_wait)
);

// RV memory access
assign rv_addr = flash_loading ? {2'b00, flash_addr[20:2], 2'b00} : mem_addr;
assign rv_wdata = flash_loading ? flash_word : mem_wdata;
assign rv_wstrb = flash_loading ? 4'b1111 : mem_wstrb;
assign ram_rdata = rv_rdata;
assign rv_valid = flash_loading ? flash_wr : (mem_valid & ram_sel);
assign ram_ready = rv_ready;

// Time counter register
reg [23:0] time_reg;                // wraps after 4.6 hours
reg [$clog2(FREQ/1000)-1:0] time_cnt;
always @(posedge clk) begin
    if (~resetn) begin
        time_reg <= 0;
        time_cnt <= 0;
    end else begin
        time_cnt <= time_cnt + 1;
        if (time_cnt == FREQ/1000-1) begin
            time_cnt <= 0;
            time_reg <= time_reg + 1;
        end
    end
end

// assign led = ~{2'b0, (^ total_refresh[7:0]), s0, flash_cnt[12]};     // flash while loading

endmodule

module picosoc_regs (
	input clk, wen,
	input [5:0] waddr,
	input [5:0] raddr1,
	input [5:0] raddr2,
	input [31:0] wdata,
	output [31:0] rdata1,
	output [31:0] rdata2
);
	reg [31:0] regs [0:31];

	always @(posedge clk)
		if (wen) regs[waddr[4:0]] <= wdata;

	assign rdata1 = regs[raddr1[4:0]];
	assign rdata2 = regs[raddr2[4:0]];
endmodule

