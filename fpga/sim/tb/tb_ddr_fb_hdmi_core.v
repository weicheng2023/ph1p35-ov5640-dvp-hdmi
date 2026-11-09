// ============================================================================
// tb_ddr_fb_hdmi_core.v
//
// Integration testbench for the DDR frame-buffer -> HDMI core, using a
// behavioural paxi slave model with a 65536-beat memory (frame base 4096).
//
// Checks:
//   - 16-beat self-check pass
//   - frame write_done and expected CRC
//   - full-frame readback CRC match + no pixel compare error
//   - FIFO prefill + VSYNC-aligned video_valid
//   - 8 bars / border / marker / grid at the correct HDMI row/column
//   - no underflow / overflow / error
//
// The encrypted DDR IP is not simulated; this verifies the digital path.
// ============================================================================
`timescale 1ns / 1ps

module tb_ddr_fb_hdmi_core #(
    parameter integer READY_DELAY  = 0,
    parameter integer CORRUPT      = 0,
    parameter integer CORRUPT_ADDR = 4128,  // native base 4096 + 4*8
    parameter integer FIFO_FAULT = 0, // 1=underflow, 2=overflow
    parameter integer DDR_PROOF = 0
) ();

    reg         clk_50m;
    reg         dhi_clk;
    reg         rst_n;
    reg         ddrphy_rdy;

    wire [24:0]  awaddr;
    wire         awvalid;
    wire         awready;
    wire [127:0] wdata;
    wire [15:0]  wstrb;
    wire         wvalid;
    wire         wlast;
    wire         wready;
    wire [24:0]  araddr;
    wire         arvalid;
    wire         arready;
    wire [127:0] rdata;
    wire         rlast;
    wire         rvalid;
    wire         rready;

    wire         tmds_clk_p, tmds_d0_p, tmds_d1_p, tmds_d2_p;
    wire         ddr_ready, write_done, error, hdmi_lock;

    integer errors;

    initial clk_50m  = 1'b0;
    initial dhi_clk  = 1'b0;
    always #10.000 clk_50m = ~clk_50m;    // 50 MHz
    always #3.750  dhi_clk = ~dhi_clk;    // 133.33 MHz

    ddr_fb_hdmi_core dut (
        .clk_50m        (clk_50m),
        .rst_n          (rst_n),
        .dhi_clk        (dhi_clk),
        .ddrphy_rdy     (ddrphy_rdy),

        .paxi_awaddr    (awaddr),
        .paxi_awvalid   (awvalid),
        .paxi_awready   (awready),
        .paxi_wdata     (wdata),
        .paxi_wstrb     (wstrb),
        .paxi_wvalid    (wvalid),
        .paxi_wlast     (wlast),
        .paxi_wready    (wready),
        .paxi_araddr    (araddr),
        .paxi_arvalid   (arvalid),
        .paxi_arready   (arready),
        .paxi_rdata     (rdata),
        .paxi_rlast     (rlast),
        .paxi_rvalid    (rvalid),
        .paxi_rready    (rready),

        .tmds_clk_p     (tmds_clk_p),
        .tmds_d0_p      (tmds_d0_p),
        .tmds_d1_p      (tmds_d1_p),
        .tmds_d2_p      (tmds_d2_p),

        .ddr_ready_o    (ddr_ready),
        .write_done_o   (write_done),
        .error_o        (error),
        .hdmi_lock_o    (hdmi_lock)
    );

    ddr_axi_slave_model #(
        .ADDR_WIDTH  (25),
        .DATA_WIDTH  (128),
        .STRB_WIDTH  (16),
        .DEPTH        (65536),
        .READY_DELAY  (READY_DELAY),
        .CORRUPT      (CORRUPT),
        .CORRUPT_ADDR (CORRUPT_ADDR)
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

    function [23:0] cvt565;
        input [15:0] p;
        reg [4:0] r;
        reg [5:0] g;
        reg [4:0] b;
        begin
            r = p[15:11];
            g = p[10:5];
            b = p[4:0];
            cvt565 = {r, r[4:2], g, g[5:4], b, b[4:2]};
        end
    endfunction

    task check_pixel;
        input [9:0] h;
        input [9:0] v;
        input [23:0] exp;
        reg found;
        begin
            found = 1'b0;
            // Sample after the clock edge settles so hcount/vcount/pix_idx
            // all reflect the current pixel cycle (avoids the active-region
            // race with the DUT's non-blocking updates).
            while (!found) begin
                @(posedge dut.pixel_clk);
                #1;
                if (dut.de && dut.hcount == h && dut.vcount == v) begin
                    found = 1'b1;
                    if (dut.rgb !== exp) begin
                        $display("FAIL h=%0d v=%0d rgb=%06h expected=%06h",
                                 h, v, dut.rgb, exp);
                        errors = errors + 1;
                    end else begin
                        $display("ok   h=%0d v=%0d rgb=%06h", h, v, dut.rgb);
                    end
                end
            end
        end
    endtask

    initial begin
        #50_000_000; // 50 ms absolute timeout
        $fatal(1,"simulation timeout");
    end

    initial begin
        errors     = 0;
        rst_n      = 1'b0;
        ddrphy_rdy = 1'b0;

        repeat (10) @(posedge clk_50m);
        rst_n = 1'b1;
        repeat (20) @(posedge dhi_clk);
        ddrphy_rdy = 1'b1;

        // Self-test corruption must stop before frame writes and show red.
        if (CORRUPT && CORRUPT_ADDR < 128) begin
            wait (error === 1'b1);
            wait (hdmi_lock === 1'b1);
            repeat (8) @(posedge dut.pixel_clk);
            #1;
            if (dut.error_code !== 1 || dut.rgb !== 24'hFF0000 || write_done || dut.video_valid)
                $fatal(1,"Self-test error classification/display");
            $display("TB: PASS - ddr_fb_hdmi_core self failure/red");
            $finish;
        end
        // 1. 16-beat self-check.
        wait (dut.self_done === 1'b1);
        if (dut.self_pass !== 1'b1) begin
            $display("FAIL self-check pass=%b err_cnt=%0d rlast_err=%b",
                     dut.self_pass, dut.self_err_cnt, dut.self_rlast_err);
            errors = errors + 1;
        end else begin
            $display("ok   self-check pass");
        end

        // 2. Frame write + expected CRC.
        wait (dut.writer_write_done === 1'b1);
        $display("ok   frame write accepted, crc_expected=%08h",
                 dut.writer_crc_expected);

        // 3. Full-frame readback verification.
        wait (dut.reader_verify_done === 1'b1);
        $display("crc_actual=%08h crc_expected=%08h crc_ok=%b err_valid=%b err_addr=%0d",
                 dut.reader_crc_actual, dut.writer_crc_expected,
                 dut.reader_crc_ok, dut.reader_err_valid, dut.reader_err_addr);
        if (CORRUPT == 0) begin
            if (dut.reader_crc_ok !== 1'b1) begin
                $display("FAIL readback CRC/compare");
                errors = errors + 1;
            end else begin
                $display("ok   full-frame readback CRC match");
            end

            if (DDR_PROOF) begin
                // Change DDR after verification: pixel (40,10) must follow DDR,
                // not the combinational pattern generator (white -> green).
                @(negedge dhi_clk);
                u_model.mem[4096/8 + 10*80 + 5][15:0] = 16'h07E0;
            end
            // 4. VSYNC-aligned video start and image checks.
            wait (dut.video_valid === 1'b1);
            if (hdmi_lock !== 1'b1 || ddr_ready !== 1'b1) begin
                $display("FAIL hdmi_lock=%b ddr_ready=%b", hdmi_lock, ddr_ready);
                errors = errors + 1;
            end

            // line 10: border, marker, 8 bars
            check_pixel(10'd0,   10'd10, 24'hFFFFFF); // 2px border
            check_pixel(10'd3,   10'd10, 24'hFF0000); // marker checker (red)
            check_pixel(10'd39,  10'd10, 24'hFFFFFF);
            check_pixel(10'd40,  10'd10, DDR_PROOF ? 24'h00FF00 : 24'hFFFFFF);
            check_pixel(10'd41,  10'd10, 24'hFFFFFF); // white bar
            check_pixel(10'd79,  10'd10, 24'hFFFFFF);
            check_pixel(10'd80,  10'd10, 24'hFFFF00);
            check_pixel(10'd120, 10'd10, 24'hFFFF00); // yellow
            check_pixel(10'd200, 10'd10, 24'h00FFFF); // cyan
            check_pixel(10'd280, 10'd10, 24'h00FF00); // green
            check_pixel(10'd360, 10'd10, 24'hFF00FF); // magenta
            check_pixel(10'd440, 10'd10, 24'hFF0000); // red
            check_pixel(10'd520, 10'd10, 24'h0000FF); // blue
            check_pixel(10'd600, 10'd10, 24'h000000); // black

            // line 32: grid, and line 33: bar again
            check_pixel(10'd40,  10'd32, cvt565(16'h8410));
            check_pixel(10'd40,  10'd33, 24'hFFFFFF);

            // 5. No stream errors.
            if (dut.underflow !== 1'b0 || dut.reader_fifo_wr_overflow !== 1'b0 ||
                error !== 1'b0) begin
                $display("FAIL underflow=%b overflow=%b error=%b",
                         dut.underflow, dut.reader_fifo_wr_overflow, error);
                errors = errors + 1;
            end else begin
                $display("ok   no underflow/overflow/error");
            end
            if (FIFO_FAULT != 0) begin
                if (FIFO_FAULT == 1) begin
                    force dut.fifo_rd_empty = 1'b1;
                    wait (dut.underflow === 1'b1);
                    release dut.fifo_rd_empty;
                end else begin
                    force dut.reader_fifo_wr_overflow = 1'b1;
                    repeat (4) @(posedge dhi_clk);
                    release dut.reader_fifo_wr_overflow;
                end
                wait (error === 1'b1);
                repeat (10) @(posedge dut.pixel_clk);
                #1;
                if (dut.error_code !== 4 || dut.rgb !== 24'hFFFF00)
                    $fatal(1,"FIFO error classification/display");
                $display("ok FIFO fault=%0d detected/yellow",FIFO_FAULT);
            end
        end else begin
            // Negative test: the injected frame-beat corruption must be
            // detected, must abort display start, and must raise error_o.
            if (dut.reader_crc_ok !== 1'b0) begin
                $display("FAIL corrupt frame not detected by CRC");
                errors = errors + 1;
            end else if (dut.reader_crc_actual === dut.writer_crc_expected) begin
                $display("FAIL read-side CRC was not computed from actual data");
                errors = errors + 1;
            end else if (dut.reader_err_valid !== 1'b1) begin
                $display("FAIL corrupt frame not flagged per-pixel");
                errors = errors + 1;
            end else if (dut.reader_err_addr !== CORRUPT_ADDR) begin
                $display("FAIL err_addr=%0d expected=%0d",
                         dut.reader_err_addr, CORRUPT_ADDR);
                errors = errors + 1;
            end else begin
                $display("ok   corruption detected at addr=%0d", dut.reader_err_addr);
            end

            wait (error === 1'b1);
            if (dut.phase !== 3'd7 || dut.error_code !== 4'd3) begin
                $display("FAIL phase=%0d error_code=%0d expected PH_ERROR/3",
                         dut.phase, dut.error_code);
                errors = errors + 1;
            end else begin
                $display("ok   aborted in PH_ERROR, display never started");
            end
            repeat (8) @(posedge dut.pixel_clk);
            #1;
            if (dut.rgb !== 24'hFF00FF) $fatal(1,"Frame error color");
            if (dut.video_valid !== 1'b0) begin
                $display("FAIL video_valid asserted despite corrupt frame");
                errors = errors + 1;
            end
        end

        if (u_model.protocol_error) $fatal(1,"Unexpected alignment error");
        if (errors == 0)
            $display("TB: PASS - ddr_fb_hdmi_core");
        else
            $display("TB: FAIL - ddr_fb_hdmi_core, errors=%0d", errors);

        if (errors != 0) $fatal(1,"Test failed");
        $finish;
    end

endmodule
