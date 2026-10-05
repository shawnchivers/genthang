// SDRAM controller for Gen Thang on the Tang Nano 20K (first written for the
// MDTang20K port, hence the file name).
//
// Embedded 64Mbit SDRAM: 32-bit, 4 banks x 2048 rows x 256 columns, CL2, burst 1,
// every access uses auto-precharge. Runs on clk_sys (~54MHz). Read data is captured
// in the input register 3 edges after READ, which needs the chip clock at ~315
// degrees (see gowin_pll_sys.v), and handed to the client on the following edge.
//
// Physical byte map (23 bits, bank = [22:21], row = [20:10], col = [9:2]):
//   bank 0-1  0x000000-0x3FFFFF  cartridge ROM (core word address passes through)
//   bank 2    0x400000-0x40FFFF  68K work RAM  (core word 0x400000-0x407FFF)
//   bank 2    0x420000-0x43FFFF  cartridge SRAM (core word 0x410000-0x41FFFF)
//   bank 2    0x440000-0x45FFFF  save state window (core word 0x420000-0x42FFFF)
//   bank 3    0x600000-0x60FFFF  VDP VRAM (32-bit words = one vram32 fetch)
//   bank 3    0x700000-0x7FFFFF  PicoRV32 (iosys) memory, 1MB
// The PicoRV32 sees its 1MB at 0x000000 and physical 0x400000-0x7FFFFF 1:1.
//
// Clients use toggle req/ack handshakes. Read data is valid on dout combinationally
// in the cycle ack changes and is held afterwards. Priority:
//   refresh > mem (68K/Z80/VDP-DMA bus) > vram32 > vram16 > rv > loader > VRAM clear
module sdram_md20k #(
    parameter FREQ = 54_000_000,
    // bank busy time after ACT, in extra cycles (ACT-to-ACT = value + 1 cycles)
    parameter [3:0] T_RC_RD = 4'd3,     // tRC 60ns
    parameter [3:0] T_RC_WR = 4'd4,     // tWR + tRP after the write
    parameter [3:0] T_RFC   = 4'd4,     // auto refresh
    parameter       PIPELINE_READS = 1  // 0: one access at a time
) (
    input             clk,
    input             resetn,
    output reg        ready = 1'b0,     // init sequence finished
    input       [2:0] rd_lat,           // edges from READ to data capture (2..4), nominal 3

    // SDRAM pins, data bus split for the top-level tristate
    output reg  [3:0] cmd = 4'b0111,    // {nCS, nRAS, nCAS, nWE}, NOP at power-up
    output reg [10:0] sa,
    output reg  [1:0] ba,
    output reg  [3:0] dqm = 4'b1111,
    output reg [31:0] dq_out,
    output reg        dq_oe = 1'b0,
    input      [31:0] dq_in,

    // main bus (ROM / 68K RAM / SRAM), Genesis word address
    input             mem_req,
    output reg        mem_ack,
    input             mem_we,
    input      [24:1] mem_addr,
    input      [15:0] mem_din,
    input       [1:0] mem_be,
    output     [15:0] mem_dout,

    // VDP 16-bit port
    input             v16_req,
    output reg        v16_ack,
    input             v16_we,
    input      [15:1] v16_addr,
    input      [15:0] v16_din,
    input       [1:0] v16_be,
    output     [15:0] v16_dout,

    // VDP 32-bit render port (read only)
    input             v32_req,
    output reg        v32_ack,
    input      [15:2] v32_addr,
    output     [31:0] v32_dout,

    // PicoRV32 memory, byte address (see map above)
    input             rv_req,
    output reg        rv_ack,
    input             rv_we,
    input      [22:2] rv_addr,
    input      [31:0] rv_din,
    input       [3:0] rv_be,
    output     [31:0] rv_dout,

    // ROM loader (writes only), physical 32-bit word in banks 0-1
    input             ld_req,
    output reg        ld_ack,
    input      [21:2] ld_addr,
    input      [31:0] ld_din,

    // zero all of VRAM while held high; done stays high once finished
    input             vram_clear,
    output reg        vram_clear_done
);

localparam CMD_NOP     = 4'b0111;
localparam CMD_ACT     = 4'b0011;
localparam CMD_READ    = 4'b0101;
localparam CMD_WRITE   = 4'b0100;
localparam CMD_PRE     = 4'b0010;
localparam CMD_REFRESH = 4'b0001;
localparam CMD_MRS     = 4'b0000;
localparam [10:0] MODE_REG = 11'b000_0_010_0_000;   // CL2, sequential, burst 1

localparam REFRESH_CYCLES = FREQ / 1000 * 64 / 8192;  // 7.8us
localparam INIT_CYCLES    = FREQ / 1000 * 200 / 1000; // 200us

localparam P_MEM = 3'd0, P_V16 = 3'd1, P_V32 = 3'd2, P_LD = 3'd3, P_CLR = 3'd4, P_RV = 3'd5;

localparam S_INIT = 3'd0, S_IDLE = 3'd1, S_RD = 3'd2, S_WR = 3'd3, S_REF = 3'd4;

function [22:0] mem_phys(input [24:1] wa);
    if (wa[24:16] == 9'b0_1000_0000)            // 68K RAM
        mem_phys = {7'b10_00000, wa[15:1], 1'b0};
    else if (wa[24:17] == 8'b0_1000_001)        // cartridge SRAM
        mem_phys = {6'b10_0001, wa[16:1], 1'b0};
    else if (wa[24:17] == 8'b0_1000_010)        // save state window
        mem_phys = {6'b10_0010, wa[16:1], 1'b0};
    else                                        // ROM
        mem_phys = {1'b0, wa[21:1], 1'b0};
endfunction

reg [2:0]  state;
reg [3:0]  cyc;
reg [15:0] init_cnt;
reg [9:0]  refresh_cnt;
reg        need_refresh;
reg [3:0]  bank_wait [0:3];
reg [13:0] clr_addr;

// current access
reg [2:0]  port;
reg        half;

// read data delivery
reg [31:0] dq_in_r;         // input register, packed into the IOB
always @(posedge clk) dq_in_r <= dq_in;
reg        rd_valid;
reg [15:0] mem_buf, v16_buf;
reg [31:0] v32_buf, rv_buf;
// reads in flight, one entry per cycle since READ; entry rd_lat-1 completes
reg [3:0]  rp_v;
reg [2:0]  rp_port [0:3];
reg        rp_half [0:3];
wire [15:0] dq16 = half ? dq_in_r[31:16] : dq_in_r[15:0];
assign mem_dout = (rd_valid && port == P_MEM) ? dq16  : mem_buf;
assign v16_dout = (rd_valid && port == P_V16) ? dq16  : v16_buf;
assign v32_dout = (rd_valid && port == P_V32) ? dq_in_r : v32_buf;
assign rv_dout  = (rd_valid && port == P_RV)  ? dq_in_r : rv_buf;

// request selection; a client with a read in the pipeline is not pending until its ack
reg infl_mem, infl_v16, infl_v32, infl_rv;
wire mem_pend = (mem_req ^ mem_ack) & ~infl_mem;
wire v16_pend = (v16_req ^ v16_ack) & ~infl_v16;
wire v32_pend = (v32_req ^ v32_ack) & ~infl_v32;
wire rv_pend  = (rv_req ^ rv_ack) & ~infl_rv;
wire ld_pend  = ld_req ^ ld_ack;
wire clr_pend = vram_clear & ~vram_clear_done;

reg        sel_any;
reg [2:0]  sel_port;
reg [22:0] sel_pa;
reg        sel_we;
reg [31:0] sel_d32;
reg [3:0]  sel_dqm;         // write byte mask, active low
always @* begin
    sel_any = 1'b1;
    sel_we = 1'b0;
    sel_d32 = 32'd0;
    sel_dqm = 4'b0000;
    if (mem_pend) begin
        sel_port = P_MEM;
        sel_pa = mem_phys(mem_addr);
        sel_we = mem_we;
        sel_d32 = {mem_din, mem_din};
        sel_dqm = sel_pa[1] ? {~mem_be, 2'b11} : {2'b11, ~mem_be};
    end else if (v32_pend) begin
        sel_port = P_V32;
        sel_pa = {7'b11_00000, v32_addr, 2'b00};
    end else if (v16_pend) begin
        sel_port = P_V16;
        sel_pa = {7'b11_00000, v16_addr, 1'b0};
        sel_we = v16_we;
        sel_d32 = {v16_din, v16_din};
        sel_dqm = v16_addr[1] ? {~v16_be, 2'b11} : {2'b11, ~v16_be};
    end else if (rv_pend) begin
        sel_port = P_RV;
        sel_pa = rv_addr[22] ? {1'b1, rv_addr[21:2], 2'b00} : {3'b111, rv_addr[19:2], 2'b00};
        sel_we = rv_we;
        sel_d32 = rv_din;
        sel_dqm = ~rv_be;
    end else if (ld_pend) begin
        sel_port = P_LD;
        sel_pa = {1'b0, ld_addr, 2'b00};
        sel_we = 1'b1;
        sel_d32 = ld_din;
    end else begin
        sel_port = P_CLR;
        sel_pa = {7'b11_00000, clr_addr, 2'b00};
        sel_we = 1'b1;
        sel_any = clr_pend;
    end
end

wire bank_free = bank_wait[sel_pa[22:21]] == 0;
wire all_banks_free = bank_wait[0] == 0 && bank_wait[1] == 0 && bank_wait[2] == 0 && bank_wait[3] == 0;
// a read to another bank may start right after the previous READ; a WRITE must come
// at least 4 cycles after the last READ so the CL2 read data has left the bus
wire can_start = PIPELINE_READS ?
                 ((state == S_IDLE && (!sel_we || rp_v[1:0] == 2'b00)) ||
                  (state == S_RD && cyc == 4'd2 && !sel_we) || (state == S_WR && cyc == 4'd2)) :
                 ((state == S_IDLE && rp_v == 4'd0) || (state == S_WR && cyc == 4'd2));

reg [2:0]  op_port;         // registered copy for column command
reg [22:0] op_pa;
reg [31:0] op_d32;
reg [3:0]  op_dqm;

integer i;
always @(posedge clk) begin
    cmd <= CMD_NOP;
    dqm <= 4'b1111;
    dq_oe <= 1'b0;
    cyc <= cyc + 4'd1;
    for (i = 0; i < 4; i = i + 1)
        if (bank_wait[i] != 0) bank_wait[i] <= bank_wait[i] - 4'd1;

    if (refresh_cnt != 10'h3FF) refresh_cnt <= refresh_cnt + 10'd1;
    if (refresh_cnt >= REFRESH_CYCLES) need_refresh <= 1'b1;

    if (rd_valid) begin
        rd_valid <= 1'b0;
        case (port)
        P_MEM: mem_buf <= dq16;
        P_V16: v16_buf <= dq16;
        P_V32: v32_buf <= dq_in_r;
        P_RV:  rv_buf <= dq_in_r;
        default: ;
        endcase
    end

    rp_v <= {rp_v[2:0], 1'b0};
    for (i = 1; i < 4; i = i + 1) begin
        rp_port[i] <= rp_port[i-1];
        rp_half[i] <= rp_half[i-1];
    end
    if (rp_v[rd_lat - 3'd1]) begin      // dq_in_r holds the word; client samples next edge
        rd_valid <= 1'b1;
        port <= rp_port[rd_lat - 3'd1];
        half <= rp_half[rd_lat - 3'd1];
        case (rp_port[rd_lat - 3'd1])
        P_MEM: begin mem_ack <= mem_req; infl_mem <= 1'b0; end
        P_V16: begin v16_ack <= v16_req; infl_v16 <= 1'b0; end
        P_V32: begin v32_ack <= v32_req; infl_v32 <= 1'b0; end
        P_RV:  begin rv_ack <= rv_req; infl_rv <= 1'b0; end
        default: ;
        endcase
        rp_v[rd_lat] <= 1'b0;
    end

    case (state)
    S_INIT: begin
        // 200us wait, precharge all, 2x auto refresh, mode register set
        init_cnt <= init_cnt + 16'd1;
        if (init_cnt == INIT_CYCLES) begin
            cmd <= CMD_PRE;
            sa[10] <= 1'b1;
        end
        if (init_cnt == INIT_CYCLES + 4)  cmd <= CMD_REFRESH;
        if (init_cnt == INIT_CYCLES + 12) cmd <= CMD_REFRESH;
        if (init_cnt == INIT_CYCLES + 20) begin
            cmd <= CMD_MRS;
            sa <= MODE_REG;
            ba <= 2'b00;
        end
        if (init_cnt == INIT_CYCLES + 24) begin
            state <= S_IDLE;
            ready <= 1'b1;
        end
    end

    S_RD: begin
        if (cyc == 4'd1) begin
            cmd <= CMD_READ;
            sa <= {3'b100, op_pa[9:2]};         // A10: auto precharge
            ba <= op_pa[22:21];
            dqm <= 4'b0000;
            rp_v[0] <= 1'b1;
            rp_port[0] <= op_port;
            rp_half[0] <= op_pa[1];
        end
        if (cyc == 4'd2) state <= S_IDLE;
    end

    S_WR: begin
        if (cyc == 4'd1) begin
            cmd <= CMD_WRITE;
            sa <= {3'b100, op_pa[9:2]};
            ba <= op_pa[22:21];
            dq_oe <= 1'b1;
            dq_out <= op_d32;
            dqm <= op_dqm;
        end
        if (cyc == 4'd2) begin
            case (op_port)
            P_MEM: mem_ack <= mem_req;
            P_V16: v16_ack <= v16_req;
            P_RV:  rv_ack <= rv_req;
            P_LD:  ld_ack <= ld_req;
            P_CLR: begin
                clr_addr <= clr_addr + 14'd1;
                if (&clr_addr) vram_clear_done <= 1'b1;
            end
            default: ;
            endcase
            state <= S_IDLE;
        end
    end

    S_REF:
        if (cyc == T_RFC) state <= S_IDLE;

    default: ;
    endcase

    // start a new access (also in the last cycle of the previous one)
    if (can_start) begin
        if (need_refresh) begin
            if (all_banks_free) begin
                cmd <= CMD_REFRESH;
                need_refresh <= 1'b0;
                refresh_cnt <= 10'd0;
                for (i = 0; i < 4; i = i + 1) bank_wait[i] <= T_RFC;
                cyc <= 4'd1;
                state <= S_REF;
            end else if (state != S_IDLE)
                state <= S_IDLE;
        end else if (sel_any && bank_free) begin
            cmd <= CMD_ACT;
            ba <= sel_pa[22:21];
            sa <= sel_pa[20:10];
            bank_wait[sel_pa[22:21]] <= sel_we ? T_RC_WR : T_RC_RD;
            op_port <= sel_port;
            op_pa <= sel_pa;
            op_d32 <= sel_d32;
            op_dqm <= sel_dqm;
            if (!sel_we)
                case (sel_port)
                P_MEM: infl_mem <= 1'b1;
                P_V16: infl_v16 <= 1'b1;
                P_V32: infl_v32 <= 1'b1;
                P_RV:  infl_rv <= 1'b1;
                default: ;
                endcase
            cyc <= 4'd1;
            state <= sel_we ? S_WR : S_RD;
        end else if (state != S_IDLE)
            state <= S_IDLE;
    end

    if (~resetn) begin
        state <= S_INIT;
        init_cnt <= 16'd0;
        ready <= 1'b0;
        rd_valid <= 1'b0;
        rp_v <= 4'd0;
        {infl_mem, infl_v16, infl_v32, infl_rv} <= 4'd0;
        need_refresh <= 1'b0;
        refresh_cnt <= 10'd0;
        clr_addr <= 14'd0;
        vram_clear_done <= 1'b0;
        for (i = 0; i < 4; i = i + 1) bank_wait[i] <= 4'd0;
        mem_ack <= mem_req;
        v16_ack <= v16_req;
        v32_ack <= v32_req;
        rv_ack <= rv_req;
        ld_ack <= ld_req;
    end
end

endmodule
