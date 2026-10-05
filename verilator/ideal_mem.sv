// Reference memory for the golden model: fixed 4-cycle latency (like MDTang's
// sdram.v on the Mega boards), ROM preloaded, 68K RAM / SRAM separate.
module ideal_mem #(
    parameter ROM_HEX = "rom16.hex",
    parameter ROM_WORDS = 1048576
) (
    input             clk,
    input             req,
    output reg        ack,
    input             we,
    input      [24:1] addr,
    input      [15:0] din,
    input       [1:0] be,
    output reg [15:0] dout
);

reg [15:0] rom [0:ROM_WORDS-1];
reg [15:0] ram [0:32767];
reg [15:0] sram [0:65535];
initial begin
    $readmemh(ROM_HEX, rom);
    begin : sum_rom
        reg [15:0] s;
        integer j;
        s = 0;
        for (j = 24'h100; j < ROM_WORDS; j = j + 1) s = s + rom[j];
        $display("ideal_mem: loaded ROM sum %04h, rom[0]=%04h rom[last]=%04h", s, rom[0], rom[ROM_WORDS-1]);
    end
end

reg [2:0] cnt;
reg       busy;
always @(posedge clk) begin
    if (!busy && (req ^ ack)) begin
        busy <= 1'b1;
        cnt <= 3'd0;
    end
    if (busy) begin
        cnt <= cnt + 3'd1;
        if (cnt == 3'd2) begin
            busy <= 1'b0;
            ack <= req;
            if (addr[24:16] == 9'b0_1000_0000) begin
                if (we) begin
                    if (be[1]) ram[addr[15:1]][15:8] <= din[15:8];
                    if (be[0]) ram[addr[15:1]][7:0]  <= din[7:0];
                end else dout <= ram[addr[15:1]];
            end else if (addr[24:17] == 8'b0_1000_001) begin
                if (we) begin
                    if (be[1]) sram[addr[16:1]][15:8] <= din[15:8];
                    if (be[0]) sram[addr[16:1]][7:0]  <= din[7:0];
                end else dout <= sram[addr[16:1]];
            end else if (!we) begin
                dout <= rom[addr[$clog2(ROM_WORDS):1]];
                // debug: follow the boot checksum pointer and sum what it reads
                if (addr == expect_a) begin
                    chk <= chk + rom[addr[$clog2(ROM_WORDS):1]];
                    expect_a <= expect_a + 24'd1;
                    if (expect_a == 24'h0FFFFF)
                        $display("ideal_mem: checksum reads done, sum %04h (header %04h)", chk + rom[addr[$clog2(ROM_WORDS):1]], rom[24'hC7]);
                end
                if (addr == 24'h0000C7 && expect_a > 24'h100)
                    $display("ideal_mem: header checksum word read, pointer at %06h, sum so far %04h", expect_a, chk);
            end
        end
    end
end

reg [23:0] expect_a = 24'h000100;
reg [15:0] chk = 16'd0;

endmodule
