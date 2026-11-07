`timescale 1ns/1ps
module spiflash_boot_tb #(parameter LEN = 4);
    reg clk = 0;
    always #5 clk = ~clk;
    reg resetn = 0, start = 0, byte_we = 0, ctrl_we = 0;
    reg [31:0] data = 0;
    wire cs_full, cs_boot, sck_full, sck_boot;
    wire busy_full, busy_boot, strobe_full, strobe_boot;
    wire [7:0] byte_full, byte_boot;
    wire [31:0] read_full;
    wire wait_full, wait_boot;
    integer count_full = 0, count_boot = 0;
    reg watch_boot_idle = 0;

    spiflash #(.ADDR(24'h500000), .LEN(LEN)) full (
        .clk(clk), .resetn(resetn), .ncs(cs_full), .miso(1'b1), .mosi(), .sck(sck_full),
        .start(start), .busy(busy_full), .dout(byte_full), .dout_strb(strobe_full),
        .reg_byte_we(byte_we), .reg_word_we(1'b0), .reg_ctrl_we(ctrl_we),
        .reg_di(data), .reg_do(read_full), .reg_wait(wait_full)
    );
    spiflash #(.ADDR(24'h500000), .LEN(LEN), .MMIO(0)) boot (
        .clk(clk), .resetn(resetn), .ncs(cs_boot), .miso(1'b1), .mosi(), .sck(sck_boot),
        .start(start), .busy(busy_boot), .dout(byte_boot), .dout_strb(strobe_boot),
        .reg_byte_we(byte_we), .reg_word_we(1'b0), .reg_ctrl_we(ctrl_we),
        .reg_di(data), .reg_do(), .reg_wait(wait_boot)
    );

    always @(posedge clk) begin
        #1;
        if (resetn) begin
            if (strobe_full !== strobe_boot)
                $fatal(1, "Firmware bootstrap strobes differ");
            if (strobe_full) begin
                count_full++;
                if (byte_full !== 8'hff) $fatal(1, "Bad default bootstrap byte");
            end
            if (strobe_boot) begin
                count_boot++;
                if (byte_boot !== 8'hff) $fatal(1, "Bad bootstrap-only byte");
            end
            if (watch_boot_idle && (cs_boot !== 1'b1 || sck_boot !== 1'b0 || wait_boot !== 1'b0))
                $fatal(1, "Bootstrap-only flash reacted to an MMIO request");
        end
    end

    initial begin
        #((LEN + 10) * 1000 + 100000);
        $fatal(1, "SPI flash test timed out");
    end

    initial begin
        repeat (4) @(negedge clk);
        resetn = 1;
        @(negedge clk);
        start = 1;
        @(negedge clk);
        start = 0;
        wait (count_full == LEN && count_boot == LEN && !busy_full && !busy_boot);
        repeat (100) @(negedge clk);
        watch_boot_idle = 1;
        ctrl_we = 1;
        data = 0;
        @(negedge clk);
        ctrl_we = 0;
        if (cs_full !== 1'b0) $fatal(1, "Default flash control no longer works");
        byte_we = 1;
        data = 8'h05;
        #1;
        wait (wait_full === 1'b0);
        @(negedge clk);
        byte_we = 0;
        @(negedge clk);
        byte_we = 1;
        data = 8'hff;
        #1;
        wait (wait_full === 1'b0);
        #1;
        if (read_full[7:0] !== 8'hff) $fatal(1, "Default flash MMIO byte transfer failed");
        @(negedge clk);
        byte_we = 0;
        data = 1;
        ctrl_we = 1;
        @(negedge clk);
        ctrl_we = 0;
        repeat (100) @(negedge clk);
        if (count_full != LEN || count_boot != LEN) $fatal(1, "Unexpected firmware bytes after bootstrap");
        $display("SPI flash: %0d firmware bytes, default MMIO and bootstrap-only idle passed", LEN);
        $finish;
    end
endmodule
