// SPI NOR flash model, sampled on the system clock.
module spiflash_model #(
    parameter        HEX  = "rom8.hex",
    parameter [23:0] BASE = 24'h500000,
    parameter        SIZE = 2097152
) (
    input            clk,
    input            cs_n,
    input            sck,
    input            mosi,
    output reg       miso,
    output reg [31:0] errors
);

reg [7:0]  mem [0:SIZE-1];
reg        sck_d;
reg        cs_d;
reg [5:0]  nbits;
reg [31:0] sh;
reg        data_phase;
reg        program_phase;
reg        status_phase;
reg        write_enable;
reg [7:0]  command;
reg [23:0] addr;
reg [2:0]  bitp;
reg [7:0]  program_byte;
integer    i;

function integer mem_addr(input [23:0] flash_addr);
    if (flash_addr >= BASE && flash_addr < BASE + SIZE)
        mem_addr = flash_addr - BASE;
    else
        mem_addr = flash_addr % SIZE;
endfunction

initial begin
    $readmemh(HEX, mem);
    errors = 0;
    miso = 1'b1;
    sck_d = 1'b0;
    cs_d = 1'b1;
    write_enable = 1'b0;
end

always @(posedge clk) begin
    sck_d <= sck;
    cs_d <= cs_n;
    if (cs_n) begin
        if (!cs_d) begin
            if (command == 8'h20 && write_enable) begin
                for (i = 0; i < 4096; i = i + 1)
                    mem[mem_addr({addr[23:12], 12'd0} + i)] = 8'hFF;
                write_enable <= 1'b0;
            end else if (command == 8'h02 && program_phase) begin
                write_enable <= 1'b0;
            end else if (command == 8'h06) begin
                write_enable <= 1'b1;
            end else if (command == 8'h04) begin
                write_enable <= 1'b0;
            end
        end
        nbits <= 6'd0;
        data_phase <= 1'b0;
        program_phase <= 1'b0;
        status_phase <= 1'b0;
        command <= 8'h00;
        miso <= 1'b1;
    end else if (sck & ~sck_d) begin                // rising: sample MOSI
        if (program_phase) begin
            program_byte <= {program_byte[6:0], mosi};
            bitp <= bitp + 3'd1;
            if (bitp == 3'd7) begin
                if (write_enable)
                    mem[mem_addr(addr)] <= {program_byte[6:0], mosi};
                addr <= addr + 24'd1;
            end
        end else if (!data_phase && !status_phase) begin
            sh <= {sh[30:0], mosi};
            nbits <= nbits + 6'd1;
            if (nbits == 6'd7) begin
                command <= {sh[6:0], mosi};
                if ({sh[6:0], mosi} == 8'h05) begin
                    status_phase <= 1'b1;
                    bitp <= 3'd7;
                end else if ({sh[6:0], mosi} != 8'h03 &&
                             {sh[6:0], mosi} != 8'h02 &&
                             {sh[6:0], mosi} != 8'h20 &&
                             {sh[6:0], mosi} != 8'h06 &&
                             {sh[6:0], mosi} != 8'h04) begin
                    errors <= errors + 1;
                    $display("FLASH ERROR: command %02h", {sh[6:0], mosi});
                end
            end
            if (nbits == 6'd31) begin
                addr <= {sh[22:0], mosi};
                if (command == 8'h03) begin
                    bitp <= 3'd7;
                    data_phase <= 1'b1;
                end else if (command == 8'h02) begin
                    bitp <= 3'd0;
                    program_phase <= 1'b1;
                end
            end
        end
    end else if (~sck & sck_d && data_phase) begin  // falling: shift out
        miso <= mem[mem_addr(addr)][bitp];
        bitp <= bitp - 3'd1;
        if (bitp == 3'd0) addr <= addr + 24'd1;
    end else if (~sck & sck_d && status_phase) begin
        miso <= bitp == 3'd1 ? write_enable : 1'b0;
        bitp <= bitp - 3'd1;
    end
end

endmodule
