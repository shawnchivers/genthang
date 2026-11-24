`timescale 1ns/1ps
module display_modes_tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg [9:0] options = 0;
    reg [10:0] source_width = 320;
    reg [9:0] source_height = 224;
    reg overlay = 0;
    wire ecc_done, tmds_done, fixed_done, native_done;
    packet_ecc_check ecc_check(.clk(clk), .done(ecc_done));
    tmds_encoding_check tmds_check(.clk(clk), .done(tmds_done));
    fixed_video_check fixed_check(.clk(clk), .done(fixed_done));
    fixed_video_check #(.LCD800(1)) native_check(.clk(clk), .done(native_done));
    framebuffer #(.SELECTABLE(1), .ADAPTIVE_BLEND(0)) dut (
        .clk(clk), .resetn(1'b1), .clk_pixel(clk), .clk_5x_pixel(clk),
        .ce_pix(1'b0), .r(4'd0), .g(4'd0), .b(4'd0), .transp(1'b0),
        .interlace(1'b0), .x(9'd0), .y(8'd0), .width(source_width), .height(source_height),
        .overlay(overlay), .overlay_color(15'd0), .video_opt(options),
        .audio_left(16'd0), .audio_right(16'd0),
        .pause_core(), .overlay_x(), .overlay_y(),
        .tmds_clk_n(), .tmds_clk_p(), .tmds_d_n(), .tmds_d_p()
    );

    int ticks = 0, last_vsync = -1, vsync_on = -1, last_hsync = -1;
    bit old_vsync = 0, old_hsync = 0, old_mode = 0;
    bit checking = 0;
    always @(negedge clk) begin
        ticks++;
        if (dut.tv1080 != old_mode) begin
            if (dut.cx != 1 || dut.cy != 0 || dut.field)
                $fatal(1, "Timing changed outside a full-frame boundary");
            old_mode = dut.tv1080;
        end
        if (checking) begin
            if (dut.hdmi.hsync && !old_hsync) begin
                if (last_hsync >= 0 && ticks - last_hsync != 2200)
                    $fatal(1, "1080i H-sync is not continuous at 2200 pixels");
                last_hsync = ticks;
            end
            if (dut.hdmi.vsync && !old_vsync) begin
                if (last_vsync >= 0 && ticks - last_vsync != 1237500)
                    $fatal(1, "1080i V-sync must be 562.5 lines apart");
                last_vsync = ticks;
                vsync_on = ticks;
            end
            if (!dut.hdmi.vsync && old_vsync && vsync_on >= 0 && ticks - vsync_on != 11000)
                $fatal(1, "1080i V-sync must last five lines");
        end
        old_vsync = dut.hdmi.vsync;
        old_hsync = dut.hdmi.hsync;
    end

    task automatic boundary;
        do @(negedge clk); while (dut.cx != 0 || dut.cy != 0);
    endtask

    task automatic check_field(input int w, h, total_w, total_h, window_w, start_x, vic);
        int pixels = 0, active_pixels = 0, hsync_pixels = 0, sum;
        int sw, sh;
        sw = overlay ? 256 : int'(source_width);
        sh = overlay ? 224 : int'(source_height);
        do begin
            if (dut.hdmi.frame_width != total_w || dut.hdmi.frame_height != total_h ||
                dut.hdmi.screen_width != w || dut.hdmi.screen_height != h)
                $fatal(1, "Wrong raster dimensions");
            if (dut.hdmi.hsync) hsync_pixels++;
            if (dut.cx < w && dut.cy < h) active_pixels++;
            if (dut.cy < h && dut.cx == start_x + 8) begin
                if (dut.yy != int'(dut.cy) * sh / h ||
                    dut.xx != 8 * sw / window_w)
                    $fatal(1, "Scaler mismatch at (%0d,%0d): source (%0d,%0d)",
                           dut.cx, dut.cy, dut.xx, dut.yy);
            end
            if (dut.cx == 100 && dut.cy == 100) begin
                if (dut.hdmi.true_hdmi_output.packet_picker.auxiliary_video_information_info_frame.packet_bytes[4] != vic)
                    $fatal(1, "Wrong HDMI AVI video identification code");
                sum = 8'h82 + 2 + 13;
                for (int b = 0; b < 14; b++)
                    sum += int'(dut.hdmi.true_hdmi_output.packet_picker.auxiliary_video_information_info_frame.packet_bytes[b]);
                if ((sum & 255) != 0) $fatal(1, "Invalid AVI checksum");
            end
            pixels++;
            @(negedge clk);
        end while (dut.cx != 0 || dut.cy != 0);
        if (pixels != total_w * total_h || active_pixels != w * h)
            $fatal(1, "Wrong field duration or active pixel count");
        if (hsync_pixels != total_h * (vic == 5 ? 44 : 40))
            $fatal(1, "Wrong H-sync pulse width");
    endtask

    initial begin
        boundary();
        check_field(1280, 720, 1650, 750, 960, 159, 4);
        // Request the new mode mid-frame; the current frame must finish first.
        repeat (1000) @(negedge clk);
        options = 10'h040;
        wait (dut.tv1080);
        boundary();
        checking = 1;
        // Start on field 1, then verify both field lengths and their half-line sync.
        if (!dut.field) $fatal(1, "Expected second interlaced field");
        check_field(1920, 540, 2200, 563, 1440, 239, 5);
        source_width = 256;
        source_height = 240;
        check_field(1920, 540, 2200, 562, 1440, 239, 5);
        checking = 0;
        if (last_vsync < 0 || last_hsync < 0) $fatal(1, "Missing sync edges");
        // Opening the menu mid-field returns to 720p after the full frame, so a
        // display that cannot show 1080i can still show the menu.
        repeat (1000) @(negedge clk);
        overlay = 1;
        wait (!dut.tv1080);
        boundary();
        check_field(1280, 720, 1650, 750, 960, 159, 4);
        overlay = 0;
        wait (dut.tv1080);
        boundary();
        check_field(1920, 540, 2200, 563, 1440, 239, 5);
        // LCD keeps its 720p 4:3 squeeze in both the menu and games.
        overlay = 1;
        options = 10'h060;
        wait (!dut.tv1080 && dut.lcd);
        boundary();
        check_field(1280, 720, 1650, 750, 1277, 2, 4);
        overlay = 0;
        boundary();
        check_field(1280, 720, 1650, 750, 1277, 2, 4);
        options = 10'h040;
        wait (dut.tv1080);
        // LCD returns to 720p and fills the panel-controller input.
        options = 10'h020;
        wait (!dut.tv1080 && dut.lcd);
        boundary();
        check_field(1280, 720, 1650, 750, 1277, 2, 4);
        options = 0;
        wait (!dut.lcd);
        boundary();
        check_field(1280, 720, 1650, 750, 960, 159, 4);
        // The DVI option remains independent of the display mode.
        options = 10'h050;
        wait (dut.tv1080 && dut.dvi);
        boundary();
        if (dut.hdmi.true_hdmi_output.packet_picker.auxiliary_video_information_info_frame.packet_bytes[4] != 5)
            $fatal(1, "DVI switch changed the timing selection");
        repeat (5000) begin
            @(negedge clk);
            if (dut.hdmi.mode > 1) $fatal(1, "DVI emitted a data island or guard band");
        end
        $display("Display modes: raster, half-line interlace, scaling, AVI, boundary switching and DVI passed");
        if (!ecc_done) $fatal(1, "Packet ECC check did not finish");
        if (!tmds_done) $fatal(1, "TMDS encoding check did not finish");
        if (!fixed_done || !native_done) $fatal(1, "Fixed-output checks did not finish");
        $finish;
    end
    initial begin
        #800000000;
        $fatal(1, "Display test timed out");
    end
endmodule

module fixed_video_check #(parameter LCD800 = 0)(input clk, output reg done = 0);
    reg [9:0] options = 10'h040;
    framebuffer #(.LCD800(LCD800), .ADAPTIVE_BLEND(0)) dut (
        .clk(clk), .resetn(1'b1), .clk_pixel(clk), .clk_5x_pixel(clk),
        .ce_pix(1'b0), .r(4'd0), .g(4'd0), .b(4'd0), .transp(1'b0),
        .interlace(1'b0), .x(9'd0), .y(8'd0), .width(11'd320), .height(10'd224),
        .overlay(1'b0), .overlay_color(15'd0), .video_opt(options),
        .audio_left(16'd0), .audio_right(16'd0),
        .pause_core(), .overlay_x(), .overlay_y(),
        .tmds_clk_n(), .tmds_clk_p(), .tmds_d_n(), .tmds_d_p()
    );
    localparam W = LCD800 ? 800 : 1280, H = LCD800 ? 480 : 720;
    localparam FW = LCD800 ? 992 : 1650, FH = LCD800 ? 500 : 750;
    int pixels;
    initial begin
        do @(negedge clk); while (dut.cx != 0 || dut.cy != 0);
        for (int lcd = 0; lcd < 2; lcd++) begin
            options = 10'h040 | (lcd ? 10'h020 : 10'h000);
            do @(negedge clk); while (dut.cx != 0 || dut.cy != 0);
            pixels = 0;
            do begin
                if (dut.tv1080 || dut.field || dut.hdmi.frame_width != FW ||
                    dut.hdmi.frame_height != FH || dut.hdmi.screen_width != W || dut.hdmi.screen_height != H)
                    $fatal(1, "Fixed-output raster changed (LCD800=%0d)", LCD800);
                if (dut.cx == 100 && dut.cy == 100 &&
                    (dut.window_width != (lcd ? W - 3 : H * 4 / 3) || dut.dvi != 1'(LCD800)))
                    $fatal(1, "Fixed-output scaling/DVI changed (LCD800=%0d)", LCD800);
                pixels++;
                @(negedge clk);
            end while (dut.cx != 0 || dut.cy != 0);
            if (pixels != FW * FH) $fatal(1, "Fixed-output frame duration changed");
        end
        done = 1;
        $display("Fixed-output timing and LCD scaling passed (LCD800=%0d)", LCD800);
    end
endmodule

module tmds_encoding_check(input clk, output reg done = 0);
    reg [7:0] pixel = 0;
    reg [2:0] mode = 0;
    wire [9:0] encoded;
    reg [8:0] q;
    reg [9:0] expected;
    int balance, ones, delta, input_ones;
    bit xnor_mode;
    tmds_channel dut(.clk_pixel(clk), .video_data(pixel), .data_island_data(4'd0),
                     .control_data(2'd0), .mode(mode), .tmds(encoded));
    initial begin
        @(negedge clk);
        for (int start = 0; start < 256; start++) begin
            mode = 0;
            balance = 0;
            @(negedge clk);
            mode = 1;
            for (int step = 0; step < 256; step++) begin
                pixel = 8'(start + step * 17);
                input_ones = 0;
                for (int b = 0; b < 8; b++) input_ones += int'(pixel[b]);
                xnor_mode = input_ones > 4 || (input_ones == 4 && !pixel[0]);
                q[0] = pixel[0];
                for (int b = 1; b < 8; b++) q[b] = q[b-1] ^ pixel[b] ^ xnor_mode;
                q[8] = !xnor_mode;
                ones = 0;
                for (int b = 0; b < 8; b++) ones += int'(q[b]);
                if (balance == 0 || ones == 4) begin
                    expected = {~q[8], q[8], q[8] ? q[7:0] : ~q[7:0]};
                    delta = (2 * ones - 8) * (q[8] ? 1 : -1);
                end else if ((balance > 0 && ones > 4) || (balance < 0 && ones < 4)) begin
                    expected = {1'b1, q[8], ~q[7:0]};
                    delta = 8 - 2 * ones + (q[8] ? 2 : 0);
                end else begin
                    expected = {1'b0, q[8], q[7:0]};
                    delta = 2 * ones - 8 - (q[8] ? 0 : 2);
                end
                @(posedge clk);
                #1;
                if (encoded !== expected) $fatal(1, "TMDS encoding differs from reference");
                balance += delta;
                @(negedge clk);
            end
        end
        done = 1;
        $display("TMDS encoding: 65,536 pixels match the running-disparity reference");
    end
endmodule

module packet_ecc_check(input clk, output reg done = 0);
    reg reset = 1, enable = 0;
    reg [23:0] header;
    reg [55:0] sub [3:0];
    wire [8:0] data_bits;
    wire [4:0] counter;
    reg [7:0] parity [4:0];
    reg [63:0] body;
    reg [31:0] head;
    reg [8:0] expected;
    int unsigned seed = 32'h93715ab1;
    packet_assembler dut(.clk_pixel(clk), .reset(reset), .data_island_period(enable),
                         .header(header), .sub(sub), .packet_data(data_bits), .counter(counter));
    function automatic [7:0] step_ecc(input [7:0] p, input bit b);
        return (p >> 1) ^ ((p[0] ^ b) ? 8'h83 : 8'h00);
    endfunction
    initial begin
        repeat (2) @(negedge clk);
        reset = 0;
        for (int packet = 0; packet < 128; packet++) begin
            enable = 0;
            seed = seed * 1664525 + 1013904223;
            header = seed[23:0];
            for (int s = 0; s < 4; s++) begin
                sub[s][31:0] = seed;
                seed = seed * 1664525 + 1013904223;
                sub[s][55:32] = seed[23:0];
            end
            for (int s = 0; s < 5; s++) parity[s] = 0;
            @(negedge clk);
            enable = 1;
            for (int pixel = 0; pixel < 32; pixel++) begin
                // Allow combinational packet selection to settle before comparing.
                #1;
                if (counter != pixel) $fatal(1, "Packet counter mismatch");
                head = {parity[4], header};
                expected[0] = head[pixel];
                for (int s = 0; s < 4; s++) begin
                    body = {parity[s], sub[s]};
                    expected[s+1] = body[2*pixel];
                    expected[s+5] = body[2*pixel+1];
                    if (pixel < 28)
                        parity[s] = step_ecc(step_ecc(parity[s], sub[s][2*pixel]), sub[s][2*pixel+1]);
                end
                if (pixel < 24) parity[4] = step_ecc(parity[4], header[pixel]);
                if (data_bits !== expected)
                    $fatal(1, "Packet %0d pixel %0d: payload/ECC %h expected %h (header %h, sub0 %h)",
                           packet, pixel, data_bits, expected, header, sub[0]);
                @(negedge clk);
            end
        end
        enable = 0;
        done = 1;
        $display("Packet mux sharing: 128 payloads and BCH parity match the independent reference");
    end
endmodule

module ELVDS_OBUF(input I, output O, OB);
    assign O = I;
    assign OB = ~I;
endmodule
