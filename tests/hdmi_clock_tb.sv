`timescale 1ns/1ps
module hdmi_clock_tb;
    reg clk = 0, lowres = 0;
    always #18.518519 clk = ~clk;
    wire serial_clk, locked;
    gowin_pll_hdmi #(.SELECTABLE(1)) dut (
        .clkin(clk), .mode_480p(lowres), .clkout(serial_clk), .lock(locked)
    );

    task automatic check_clock(input real period_ns);
        realtime start_time, elapsed;
        wait (locked);
        repeat (20) @(posedge serial_clk);
        start_time = $realtime;
        repeat (100) @(posedge serial_clk);
        elapsed = $realtime - start_time;
        if (elapsed < period_ns * 99.9 || elapsed > period_ns * 100.1)
            $fatal(1, "Serial clock period %0.6f ns, expected %0.6f ns", elapsed / 100, period_ns);
        if (dut.rpll_inst.ODSEL !== (lowres ? 6'd62 : 6'd63))
            $fatal(1, "Wrong VCO output divider");
    endtask

    task automatic change_mode(input bit mode);
        realtime reset_start;
        @(negedge clk);
        lowres = mode;
        @(negedge locked);
        reset_start = $realtime;
        wait (!dut.pll_reset);
        if ($realtime - reset_start < 2000)
            $fatal(1, "PLL reset must last at least 2us");
    endtask

    initial begin
        check_clock(1000.0 / 371.25);
        change_mode(1);
        check_clock(1000.0 / 135.0);
        change_mode(0);
        check_clock(1000.0 / 371.25);
        // A menu request arriving during reset must not strand the clock.
        change_mode(1);
        lowres = 0;
        check_clock(1000.0 / 371.25);
        $display("HDMI PLL: measured 371.25/135MHz, reset/relock and interrupted switch passed");
        $finish;
    end
    initial begin
        #2000000;
        $fatal(1, "HDMI PLL did not relock");
    end
endmodule
