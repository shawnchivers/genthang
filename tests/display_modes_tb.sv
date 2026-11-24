`timescale 1ns/1ps
module display_modes_tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg [9:0] options = 0;
    reg [10:0] source_width = 320;
    reg [9:0] source_height = 224;
    reg overlay = 0;
    reg video_reset = 0;
    wire ecc_done, tmds_done, fixed_done, native_done, audio_done;
    packet_ecc_check ecc_check(.clk(clk), .done(ecc_done));
    tmds_encoding_check tmds_check(.clk(clk), .done(tmds_done));
    audio_packet_check audio_check(.clk(clk), .done(audio_done));
    fixed_video_check fixed_check(.clk(clk), .done(fixed_done));
    fixed_video_check #(.LCD800(1)) native_check(.clk(clk), .done(native_done));
    framebuffer #(.SELECTABLE(1), .ADAPTIVE_BLEND(0)) dut (
        .clk(clk), .resetn(1'b1), .clk_pixel(clk), .clk_5x_pixel(clk), .video_reset(video_reset),
        .ce_pix(1'b0), .r(4'd0), .g(4'd0), .b(4'd0), .transp(1'b0),
        .interlace(1'b0), .x(9'd0), .y(8'd0), .width(source_width), .height(source_height),
        .overlay(overlay), .overlay_color(15'd0), .video_opt(options),
        .audio_left(16'd0), .audio_right(16'd0),
        .pause_core(), .overlay_x(), .overlay_y(),
        .tmds_clk_n(), .tmds_clk_p(), .tmds_d_n(), .tmds_d_p()
    );

    int ticks = 0, last_vsync = -1, vsync_on = -1, last_hsync = -1;
    bit old_vsync = 0, old_hsync = 0;
    bit [1:0] old_mode = 0;
    bit checking = 0;
    always @(negedge clk) begin
        ticks++;
        if ({dut.tv480, dut.tv1080} != old_mode) begin
            if (dut.cx != 1 || dut.cy != 0 || dut.field)
                $fatal(1, "Timing changed outside a full-frame boundary");
            old_mode = {dut.tv480, dut.tv1080};
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

    task automatic relock;
        // Model the reference-clock synchronizer and the stopped/restarted PLL.
        repeat (6) @(negedge clk);
        video_reset = 1;
        repeat (2) @(negedge clk);
        repeat (10) begin
            @(negedge clk);
            if (dut.cx != 0 || dut.cy != 0 || dut.field || dut.active || dut.clk_audio)
                $fatal(1, "Video/audio did not reset while the PLL relocked");
        end
        video_reset = 0;
        boundary();
    endtask

    task automatic check_field(input int w, h, total_w, total_h, window_w, start_x, vic);
        int pixels = 0, active_pixels = 0, hsync_pixels = 0, vsync_pixels = 0, sum;
        int sw, sh, hfront, hpulse, packets, vfront, vpulse, vy, vx;
        bit expected_vsync;
        bit [4:0] expected_regions;
        sw = overlay ? 256 : int'(source_width);
        sh = overlay ? 224 : int'(source_height);
        hfront = vic == 2 ? 16 : vic == 5 ? 88 : 110;
        hpulse = vic == 2 ? 62 : vic == 5 ? 44 : 40;
        packets = vic == 2 ? 3 : vic == 5 ? 7 : 10;
        vfront = vic == 2 ? 9 : vic == 5 ? 2 : 5;
        vpulse = vic == 2 ? 6 : 5;
        do begin
            if (dut.hdmi.frame_width != total_w || dut.hdmi.frame_height != total_h ||
                dut.hdmi.screen_width != w || dut.hdmi.screen_height != h)
                $fatal(1, "Wrong raster dimensions");
            if (dut.hdmi.hsync != ((vic == 2) ^ (dut.cx >= w + hfront && dut.cx < w + hfront + hpulse)))
                $fatal(1, "Wrong H-sync position or polarity");
            vy = h + vfront - 1 + (vic == 5 && dut.field ? 1 : 0);
            vx = w + hfront - (vic == 5 && dut.field ? 1100 : 0);
            expected_vsync = dut.cy == vy ? dut.cx >= vx : dut.cy == vy + vpulse ? dut.cx < vx :
                             dut.cy >= h + vfront && dut.cy < h + vfront + vpulse;
            if (dut.hdmi.vsync != ((vic == 2) ^ expected_vsync))
                $fatal(1, "Wrong V-sync position or polarity");
            if (dut.hdmi.true_hdmi_output.data_island_period_instantaneous !=
                (dut.cx >= w + 14 && dut.cx < w + 14 + packets * 32))
                $fatal(1, "Wrong HDMI data-island region");
            if (dut.hdmi.true_hdmi_output.packet_enable !=
                (dut.cx >= w + 14 && dut.cx < w + 14 + packets * 32 && (int'(dut.cx) - w - 14) % 32 == 0))
                $fatal(1, "Wrong HDMI packet alignment");
            if (dut.hdmi.hsync != (vic == 2)) hsync_pixels++;
            if (dut.hdmi.vsync != (vic == 2)) vsync_pixels++;
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
                if (vic == 2 &&
                    dut.hdmi.true_hdmi_output.packet_picker.auxiliary_video_information_info_frame.packet_bytes[2][5:4] != 1)
                    $fatal(1, "480p must advertise 4:3 non-square pixels");
            end
            if (vic == 2 && dut.hdmi.true_hdmi_output.num_packets_alongside != 3)
                $fatal(1, "480p data islands do not fit its horizontal blanking");
            expected_regions = {
                dut.cx >= total_w - 2 && dut.cx < total_w && (dut.cy == total_h - 1 || dut.cy < h - 1),
                dut.cx >= total_w - 10 && dut.cx < total_w - 2 && (dut.cy == total_h - 1 || dut.cy < h - 1),
                (dut.cx >= w + 12 && dut.cx < w + 14) ||
                    (dut.cx >= w + 14 + packets * 32 && dut.cx < w + 16 + packets * 32),
                dut.cx >= w + 4 && dut.cx < w + 12,
                dut.cx < w && dut.cy < h
            };
            pixels++;
            @(negedge clk);
            if ({dut.hdmi.true_hdmi_output.video_guard, dut.hdmi.true_hdmi_output.video_preamble,
                 dut.hdmi.true_hdmi_output.data_island_guard, dut.hdmi.true_hdmi_output.data_island_preamble,
                 dut.hdmi.video_data_period} != expected_regions)
                $fatal(1, "HDMI guard, preamble or video period differs from raster reference");
        end while (dut.cx != 0 || dut.cy != 0);
        if (pixels != total_w * total_h || active_pixels != w * h)
            $fatal(1, "Wrong field duration or active pixel count");
        if (hsync_pixels != total_h * (vic == 2 ? 62 : vic == 5 ? 44 : 40))
            $fatal(1, "Wrong H-sync pulse width");
        if (vic == 2) begin
            if (vsync_pixels != 6 * total_w)
                $fatal(1, "480p V-sync must last six lines");
            if (dut.hdmi.true_hdmi_output.packet_picker.audio_clock_regeneration_packet.cycle_time_stamp != 26976)
                $fatal(1, "480p audio CTS %0d does not match the 27MHz sampling divider",
                       dut.hdmi.true_hdmi_output.packet_picker.audio_clock_regeneration_packet.cycle_time_stamp);
        end
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
        // 480p uses a different pixel clock, but still only changes at a frame
        // boundary and always returns to a 720p menu.
        repeat (1000) @(negedge clk);
        options = 10'h080;
        wait (dut.tv480);
        relock();
        check_field(720, 480, 858, 525, 717, 2, 2);
        source_width = 320;
        source_height = 224;
        check_field(720, 480, 858, 525, 717, 2, 2);
        repeat (1000) @(negedge clk);
        overlay = 1;
        wait (!dut.tv480);
        relock();
        check_field(1280, 720, 1650, 750, 960, 159, 4);
        overlay = 0;
        wait (dut.tv480);
        relock();
        check_field(720, 480, 858, 525, 717, 2, 2);
        options = 10'h090;
        wait (dut.dvi);
        boundary();
        repeat (5000) begin
            @(negedge clk);
            if (dut.hdmi.mode > 1) $fatal(1, "480p DVI emitted a data island or guard band");
        end
        overlay = 1;
        options = 10'h0A0;
        wait (!dut.tv480 && dut.lcd);
        relock();
        check_field(1280, 720, 1650, 750, 1277, 2, 4);
        overlay = 0;
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
        $display("Display modes: 720p/1080i/480p raster, scaling, AVI, audio CTS, recovery menu and DVI passed");
        if (!ecc_done) $fatal(1, "Packet ECC check did not finish");
        if (!tmds_done) $fatal(1, "TMDS encoding check did not finish");
        if (!audio_done) $fatal(1, "Audio packet check did not finish");
        if (!fixed_done || !native_done) $fatal(1, "Fixed-output checks did not finish");
        $finish;
    end
    initial begin
        #800000000;
        $fatal(1, "Display test timed out");
    end
endmodule

module audio_packet_check(input clk, output reg done = 0);
    reg reset = 1, sample_clock = 0;
    reg [15:0] samples [1:0];
    wire [23:0] header;
    wire [55:0] sub [3:0];
    reg [4:0] pixel = 0;
    int expected_sample = 0;
    always @(posedge clk) pixel <= pixel + 1'b1;
    packet_picker #(.VIDEO_ID_CODE(4), .SELECTABLE(1), .VIDEO_RATE(74.25E6),
                    .AUDIO_BIT_WIDTH(16), .AUDIO_RATE(48000)) dut (
        .clk_pixel(clk), .clk_audio(sample_clock), .reset(reset),
        .interlace_mode(1'b0), .mode_480p(1'b1), .video_field_end(1'b0),
        .packet_enable(pixel == 0), .packet_pixel_counter(pixel),
        .audio_sample_word(samples), .header(header), .sub(sub)
    );
    function automatic [15:0] left_sample(input int n);
        return 16'(n * 937 + 16'h1234);
    endfunction
    function automatic [15:0] right_sample(input int n);
        return 16'(n * 347 - 16'h4321);
    endfunction
    always @(negedge clk)
        if (!reset && pixel == 1 && header[7:0] == 2) begin
            if (header[11:8] != 4'hF) $fatal(1, "Audio packet omitted a sample");
            for (int s = 0; s < 4; s++) begin
                if (sub[s][23:0] != {left_sample(expected_sample + s), 8'd0} ||
                    sub[s][47:24] != {right_sample(expected_sample + s), 8'd0})
                    $fatal(1, "Audio payload/channel/order mismatch at sample %0d", expected_sample + s);
            end
            expected_sample += 4;
        end
    initial begin
        repeat (4) @(negedge clk);
        reset = 0;
        for (int n = 0; n < 128; n++) begin
            samples[0] = left_sample(n);
            samples[1] = right_sample(n);
            sample_clock = 1;
            repeat (10) @(negedge clk);
            sample_clock = 0;
            repeat (552) @(negedge clk);
        end
        repeat (128) @(negedge clk);
        if (expected_sample != 128) $fatal(1, "Audio samples were lost or duplicated");
        done = 1;
        $display("HDMI audio: 128 stereo samples retain exact payload, channel and order");
    end
endmodule

module fixed_video_check #(parameter LCD800 = 0)(input clk, output reg done = 0);
    reg [9:0] options = 10'h040;
    framebuffer #(.LCD800(LCD800), .ADAPTIVE_BLEND(0)) dut (
        .clk(clk), .resetn(1'b1), .clk_pixel(clk), .clk_5x_pixel(clk), .video_reset(1'b0),
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
                if (dut.tv1080 || dut.tv480 || dut.field || dut.hdmi.frame_width != FW ||
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
