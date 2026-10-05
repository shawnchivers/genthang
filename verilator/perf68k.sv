// 68K bus statistics, printed once per 60 frames:
//  - wait states per region (a zero-wait bus cycle keeps AS low for 2 CLKENp edges)
//  - 68K clocks lost to VDP DMA and to Z80 accesses of the 68K bus (from bus request
//    to release, so arbitration delay is included)
module perf68k (
    input        clk,
    input        clken,
    input        as_n,
    input [23:1] a,
    input        vblank,
    input        vdp_br_n,
    input        vdp_bgack_n,
    input        z80_br_n,
    input        z80_bgack_n
);

localparam R_ROM = 0, R_RAM = 1, R_VDP = 2, R_OTH = 3;
longint clocks, dma_clk, z80_clk, waits [0:3], accesses [0:3], hist [0:7];
int     cur, region, frames;
reg     vblank_r, as_r;

function automatic int region_of(input [23:1] ad);
    if ({ad, 1'b0} < 24'hA00000) return R_ROM;
    if (&ad[23:21]) return R_RAM;
    if (ad[23:21] == 3'b110) return R_VDP;
    return R_OTH;
endfunction

initial begin
    clocks = 0; dma_clk = 0; z80_clk = 0;
    for (int i = 0; i < 4; i++) begin waits[i] = 0; accesses[i] = 0; end
    for (int i = 0; i < 8; i++) hist[i] = 0;
end

always @(posedge clk) begin
    vblank_r <= vblank;
    as_r <= as_n;
    if (clken) begin
        clocks <= clocks + 1;
        if (!vdp_br_n || !vdp_bgack_n) dma_clk <= dma_clk + 1;
        else if (!z80_br_n || !z80_bgack_n) z80_clk <= z80_clk + 1;
    end
    if (!as_r && as_n && region != R_VDP && region != R_OTH)
        hist[cur > 7 ? 7 : cur] <= hist[cur > 7 ? 7 : cur] + 1;
    if (as_r && !as_n) begin
        cur <= 0;
        region <= region_of(a);
        accesses[region_of(a)] <= accesses[region_of(a)] + 1;
    end else if (!as_n && clken) begin
        cur <= cur + 1;
        if (cur >= 2) waits[region] <= waits[region] + 1;
    end
    if (vblank && !vblank_r) begin
        frames <= frames + 1;
        if (frames % 60 == 59) begin
            $display("perf68k: %0d clk  ROM %0d acc %0d ws | RAM %0d acc %0d ws | VDP %0d acc %0d ws | other %0d acc %0d ws",
                clocks, accesses[R_ROM], waits[R_ROM], accesses[R_RAM], waits[R_RAM],
                accesses[R_VDP], waits[R_VDP], accesses[R_OTH], waits[R_OTH]);
            $display("perf68k: lost to ROM/RAM waits %0.2f%%  VDP DMA %0.2f%%  Z80 bus %0.2f%%",
                100.0 * (waits[R_ROM] + waits[R_RAM]) / clocks, 100.0 * dma_clk / clocks,
                100.0 * z80_clk / clocks);
            $display("perf68k: ROM/RAM AS-low clocks histogram 0..7+: %0d %0d %0d %0d %0d %0d %0d %0d",
                hist[0], hist[1], hist[2], hist[3], hist[4], hist[5], hist[6], hist[7]);
            for (int i = 0; i < 8; i++) hist[i] <= 0;
            clocks <= 0; dma_clk <= 0; z80_clk <= 0;
            for (int i = 0; i < 4; i++) begin waits[i] <= 0; accesses[i] <= 0; end
        end
    end
end

endmodule
