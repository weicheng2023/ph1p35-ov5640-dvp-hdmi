// ============================================================================
// tb_cam_fb_hdmi_core.v
//
// Stage 3 integration test: synthetic OV5640 DVP -> capture -> async FIFO ->
// DDR ping-pong writer -> DDR reader -> display FIFO -> HDMI timing.
//
// The camera model keeps the measured real timing (48.000 MHz PCLK, HREF
// active 1920 PCLK / inactive 1280 PCLK, VSYNC 66.6 us, vertical blanking
// ~65,920 PCLK). The geometry is a parameter so the default regression can
// use a small display (64x48) and run quickly; the full 640x480 real-time
// case is the same testbench with larger -g values.
//
// Each camera frame carries a frame id in the blue channel. Every row is
// identical in blue, so a frame that shows two different blue values is a
// tear; a blue value that changes between display frames proves live update.
//
// Checks:
//   - 16-beat DDR self-check
//   - camera frame written to DDR (content checked directly in the model)
//   - video starts after prefill + VSYNC
//   - no tearing at the top/bottom of a displayed frame
//   - frame id advances across display frames
//   - no underflow / overflow / writer / reader / capture error
// ============================================================================
`timescale 1ns / 1ps

module tb_cam_fb_hdmi_core #(
    parameter integer H_ACTIVE    = 64,
    parameter integer V_ACTIVE    = 48,
    parameter integer CAM_LINES   = 48,
    parameter integer FRAME_STRIDE= 3072,     // beats * 8
    parameter integer TOTAL_BEATS = 384,
    parameter integer PREFILL     = 48,
    parameter integer READY_DELAY = 0,
    parameter integer H_PHASE     = 1920,     // real HREF active length
    parameter integer H_BLANK     = 1280
) ();

    // ------------------------------------------------------------------
    // Clocks / resets
    // ------------------------------------------------------------------
    reg clk_50m;
    reg dhi_clk;
    reg cam_pclk;
    reg rst_n;
    reg ddrphy_rdy;
    reg cfg_ok;

    initial clk_50m  = 1'b0;
    initial dhi_clk  = 1'b0;
    initial cam_pclk = 1'b0;
    always #10.0000 clk_50m  = ~clk_50m;   // 50 MHz
    always #3.7500  dhi_clk  = ~dhi_clk;   // 133.3 MHz
    always #10.4167 cam_pclk = ~cam_pclk;  // 48.0 MHz

    // ------------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------------
    wire [24:0]  awaddr;
    wire         awvalid, awready;
    wire [127:0] wdata;
    wire [15:0]  wstrb;
    wire         wvalid, wlast, wready;
    wire [24:0]  araddr;
    wire         arvalid, arready;
    wire [127:0] rdata;
    wire         rlast, rvalid, rready;
    wire         tmds_clk_p, tmds_d0_p, tmds_d1_p, tmds_d2_p;

    wire ddr_ready, self_pass, frame_valid, capture_error, error, hdmi_lock;

    reg  cam_vsync, cam_href;
    reg  [7:0] cam_data;

    cam_fb_hdmi_core #(
        .HREF_ACTIVE_HIGH  (1),
        .VSYNC_ACTIVE_HIGH (1),
        .CAPTURE_START     (0),
        .BYTE_SWAP         (0),
        .PIXELS            (H_ACTIVE),
        .V_ACTIVE          (V_ACTIVE),
        .BASE_ADDR         (4096),
        .FRAME_STRIDE      (FRAME_STRIDE),
        .TOTAL_BEATS       (TOTAL_BEATS),
        .PREFILL_WORDS     (PREFILL)
    ) dut (
        .clk_50m         (clk_50m),
        .rst_n           (rst_n),
        .cfg_ok          (cfg_ok),
        .cam_pclk        (cam_pclk),
        .cam_vsync       (cam_vsync),
        .cam_href        (cam_href),
        .cam_data        (cam_data),
        .dhi_clk         (dhi_clk),
        .ddrphy_rdy      (ddrphy_rdy),
        .paxi_awaddr     (awaddr),
        .paxi_awvalid    (awvalid),
        .paxi_awready    (awready),
        .paxi_wdata      (wdata),
        .paxi_wstrb      (wstrb),
        .paxi_wvalid     (wvalid),
        .paxi_wlast      (wlast),
        .paxi_wready     (wready),
        .paxi_araddr     (araddr),
        .paxi_arvalid    (arvalid),
        .paxi_arready    (arready),
        .paxi_rdata      (rdata),
        .paxi_rlast      (rlast),
        .paxi_rvalid     (rvalid),
        .paxi_rready     (rready),
        .tmds_clk_p      (tmds_clk_p),
        .tmds_d0_p       (tmds_d0_p),
        .tmds_d1_p       (tmds_d1_p),
        .tmds_d2_p       (tmds_d2_p),
        .ddr_ready_o     (ddr_ready),
        .self_pass_o     (self_pass),
        .frame_valid_o   (frame_valid),
        .capture_error_o (capture_error),
        .error_o         (error),
        .hdmi_lock_o     (hdmi_lock)
    );

    ddr_axi_slave_model #(
        .ADDR_WIDTH  (25),
        .DATA_WIDTH  (128),
        .STRB_WIDTH  (16),
        .DEPTH       (131072),
        .READY_DELAY (READY_DELAY)
    ) u_model (
        .clk          (dhi_clk),
        .rst_n        (rst_n),
        .paxi_awaddr  (awaddr),
        .paxi_awvalid (awvalid),
        .paxi_awready (awready),
        .paxi_wdata   (wdata),
        .paxi_wstrb   (wstrb),
        .paxi_wvalid  (wvalid),
        .paxi_wlast   (wlast),
        .paxi_wready  (wready),
        .paxi_araddr  (araddr),
        .paxi_arvalid (arvalid),
        .paxi_arready (arready),
        .paxi_rdata   (rdata),
        .paxi_rlast   (rlast),
        .paxi_rvalid  (rvalid),
        .paxi_rready  (rready)
    );

    integer errors;

    integer cnt_cw, cnt_cr;
    initial begin
        cnt_cw = 0; cnt_cr = 0;
        forever begin
            #5_000_000;
            $display("MON t=%0t wst=%0d wbeats=%0d lin=%0d frm=%0d rst=%0d rbeat=%0d comp=%0d disp=%0d dv=%b bf=%b cw=%0d cr=%0d ovf=%b ce=%b",
                     $time, dut.u_writer.state, dut.u_writer.beats,
                     dut.u_capture.lines_captured, dut.u_capture.frames_started,
                     dut.u_reader.state, dut.u_reader.beat,
                     dut.complete_idx, dut.disp_idx, dut.disp_valid, dut.buf_free,
                     cnt_cw, cnt_cr, dut.cam_fifo_wr_overflow, dut.cam_capture_error);
        end
    end

    always @(posedge cam_pclk) if (dut.cam_fifo_wr_en) cnt_cw = cnt_cw + 1;
    always @(posedge dhi_clk) if (dut.cam_fifo_rd_en) cnt_cr = cnt_cr + 1;

    // ------------------------------------------------------------------
    // Camera pixel / RGB helpers
    // ------------------------------------------------------------------
    function [15:0] cam_pix;
        input integer x;
        input integer y;
        input integer fid;
        reg [4:0] r;
        reg [5:0] g;
        reg [4:0] b;
        begin
            r = x & 5'h1F;
            g = y & 6'h3F;
            b = fid & 5'h1F;
            cam_pix = {r, g, b};
        end
    endfunction

    function [23:0] exp_rgb;
        input integer x;
        input integer y;
        input [4:0] fid;
        reg [4:0] r;
        reg [5:0] g;
        reg [4:0] b;
        begin
            r = x & 5'h1F;
            g = y & 6'h3F;
            b = fid;
            exp_rgb = {r, r[4:2], g, g[5:4], b, b[4:2]};
        end
    endfunction

    // ------------------------------------------------------------------
    // Camera driver (real timing)
    // ------------------------------------------------------------------
    integer cyc;
    integer i;
    integer y;
    integer fid;
    integer run_cam;

    task drive_byte;
        input [7:0] b;
        begin
            cam_data = b;
            @(posedge cam_pclk); #1;
        end
    endtask

    task drive_line;
        input integer yline;
        reg [15:0] p;
        begin
            cam_href = 1'b1;
            for (i = 0; i < H_ACTIVE; i = i + 1) begin
                p = cam_pix(i, yline, fid);
                cam_data = p[15:8];
                @(posedge cam_pclk); #1;
                cam_data = p[7:0];
                @(posedge cam_pclk); #1;
            end
            // Remaining part of the real 1920-PCLK active phase.
            for (i = 2*H_ACTIVE; i < H_PHASE; i = i + 1) begin
                cam_data = 8'hEE;
                @(posedge cam_pclk); #1;
            end
            cam_href = 1'b0;
            for (i = 0; i < H_BLANK; i = i + 1) begin
                cam_data = 8'h00;
                @(posedge cam_pclk); #1;
            end
        end
    endtask

    task drive_frame;
        begin
            fid = fid + 1;
            // Vertical blanking: HREF low, VSYNC high for 66.6 us.
            cam_href = 1'b0;
            for (i = 0; i < 2000; i = i + 1) @(posedge cam_pclk);
            cam_vsync = 1'b1;
            for (i = 0; i < 3200; i = i + 1) @(posedge cam_pclk);
            cam_vsync = 1'b0;
            for (i = 0; i < 60720; i = i + 1) @(posedge cam_pclk);
            // Active lines.
            for (y = 0; y < CAM_LINES; y = y + 1) drive_line(y);
        end
    endtask

    initial begin
        fid = 0;
        cam_vsync = 1'b0;
        cam_href  = 1'b0;
        cam_data  = 8'h00;
        run_cam   = 0;
        wait (rst_n === 1'b1);
        wait (cfg_ok === 1'b1);
        repeat (200) @(posedge cam_pclk);
        forever begin
            drive_frame;
        end
    end

    // ------------------------------------------------------------------
    // Pixel sampling
    // ------------------------------------------------------------------
    task sample_px;
        input  [9:0]  h;
        input  [9:0]  v;
        output [23:0] val;
        reg found;
        begin
            found = 1'b0;
            while (!found) begin
                @(posedge dut.pixel_clk); #1;
                if (dut.de && dut.hcount == h && dut.vcount == v) begin
                    found = 1'b1;
                    val = dut.rgb;
                end
            end
        end
    endtask

    // ------------------------------------------------------------------
    // Main test
    // ------------------------------------------------------------------
    integer n;
    reg [23:0] top_rgb, bot_rgb;
    reg [4:0]  fid_top, fid_bot;
    reg [4:0]  fid_seen;
    integer    fid_changes;
    integer    idx;
    integer    b;
    reg [4:0]  fid_ref;
    reg [24:0] frame_base;
    reg [127:0] beat0, beatN;

    initial begin
        errors = 0;
        rst_n = 1'b0;
        ddrphy_rdy = 1'b0;
        cfg_ok = 1'b0;

        repeat (20) @(posedge clk_50m);
        rst_n = 1'b1;
        repeat (20) @(posedge dhi_clk);
        ddrphy_rdy = 1'b1;
        cfg_ok = 1'b1;

        // 1. DDR self-check
        wait (dut.self_done === 1'b1);
        if (dut.self_pass !== 1'b1) begin
            $display("FAIL DDR self-check");
            errors = errors + 1;
        end else begin
            $display("ok   DDR self-check");
        end

        // 2. First camera frame written
        wait (frame_valid === 1'b1);
        $display("ok   first camera frame written, fid_written=%0d",
                 u_model.mem[(4096 + dut.complete_idx*FRAME_STRIDE)/8][15:0]);

        // 3. Direct DDR content check of the completed frame.
        frame_base = 4096 + dut.complete_idx * FRAME_STRIDE;
        beat0      = u_model.mem[frame_base / 8];
        fid_ref    = beat0[4:0];
        for (b = 0; b < H_ACTIVE/8; b = b + 1) begin
            beat0 = u_model.mem[frame_base/8 + b];
            for (idx = 0; idx < 8; idx = idx + 1) begin
                if (beat0[16*idx +: 16] !== cam_pix(b*8+idx, 0, fid_ref)) begin
                    if (errors < 10)
                        $display("FAIL DDR row0 pix %0d got %04h exp %04h",
                                 b*8+idx, beat0[16*idx +: 16],
                                 cam_pix(b*8+idx, 0, fid_ref));
                    errors = errors + 1;
                end
            end
        end
        beatN = u_model.mem[frame_base/8 + (TOTAL_BEATS-1)];
        for (idx = 0; idx < 8; idx = idx + 1) begin
            if (beatN[16*idx +: 16] !== cam_pix(H_ACTIVE-8+idx, V_ACTIVE-1, fid_ref)) begin
                if (errors < 10)
                    $display("FAIL DDR last beat pix %0d got %04h exp %04h", idx,
                             beatN[16*idx +: 16],
                             cam_pix(H_ACTIVE-8+idx, V_ACTIVE-1, fid_ref));
                errors = errors + 1;
            end
        end
        if (errors == 0) $display("ok   DDR frame content (row0 + last beat)");

        // 4. Display: video starts, then check tear and live update.
        wait (dut.video_valid === 1'b1);
        $display("ok   video_valid");

        fid_seen = 5'h1F;
        fid_changes = 0;
        for (n = 0; n < 10; n = n + 1) begin
            sample_px(10'd0, 10'd0, top_rgb);
            sample_px(10'd0, V_ACTIVE-1, bot_rgb);
            fid_top = top_rgb[7:3];
            fid_bot = bot_rgb[7:3];
            if (top_rgb !== exp_rgb(0, 0, fid_top)) begin
                $display("FAIL frame %0d top pixel rgb=%06h exp=%06h",
                         n, top_rgb, exp_rgb(0, 0, fid_top));
                errors = errors + 1;
            end
            if (bot_rgb !== exp_rgb(0, V_ACTIVE-1, fid_top)) begin
                $display("FAIL frame %0d bottom pixel rgb=%06h exp=%06h",
                         n, bot_rgb, exp_rgb(0, V_ACTIVE-1, fid_top));
                errors = errors + 1;
            end
            if (fid_top !== fid_bot) begin
                $display("FAIL frame %0d tearing: top fid=%0d bottom fid=%0d",
                         n, fid_top, fid_bot);
                errors = errors + 1;
            end
            if (fid_top !== fid_seen) begin
                if (n > 0) fid_changes = fid_changes + 1;
                fid_seen = fid_top;
                $display("ok   display frame %0d fid=%0d", n, fid_top);
            end
        end
        if (fid_changes < 1) begin
            $display("FAIL frame id never advanced (live update not shown)");
            errors = errors + 1;
        end else begin
            $display("ok   frame id advanced %0d time(s)", fid_changes);
        end

        // 5. No errors anywhere.
        if (dut.writer_error || dut.reader_error || dut.underflow ||
            dut.reader_fifo_wr_overflow || capture_error) begin
            $display("FAIL writer_err=%b reader_err=%b underflow=%b overflow=%b capture_err=%b",
                     dut.writer_error, dut.reader_error, dut.underflow,
                     dut.reader_fifo_wr_overflow, capture_error);
            errors = errors + 1;
        end else begin
            $display("ok   no writer/reader/FIFO/capture errors");
        end

        if (u_model.protocol_error) begin
            $display("FAIL PAXI protocol error in model");
            errors = errors + 1;
        end

        if (errors == 0) $display("TB: PASS - cam_fb_hdmi_core");
        else             $display("TB: FAIL - cam_fb_hdmi_core errors=%0d", errors);
        if (errors != 0) $fatal(1, "Test failed");
        $finish;
    end

    initial begin
        #2_000_000_000;   // 2 s absolute guard (full-size run is slower)
        $fatal(1, "simulation timeout");
    end

endmodule
