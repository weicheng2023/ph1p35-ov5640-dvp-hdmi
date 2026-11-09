// ============================================================================
// tb_ov5640_line_capture.v
// Self-checking testbench for the OV5640 single-line capture.
//
// Simulated camera stream (PCLK = 48 MHz):
//   1. long vertical-blanking HREF: 65,920 high cycles, data=0x00
//   2. valid active line: 1,920 high cycles
//        - first 1,280 bytes = 640 RGB565 color-bar pixels
//        - last 640 bytes = 0x00 dummy
//      followed by 1,280 low cycles
//   3. second valid line: 1,920 high cycles, all bytes 0x55
//      (must NOT overwrite the frozen first line)
//
// Checks:
//   - the long blanking line is rejected
//   - capture_done / line_bytes after the valid line
//   - every one of the 640 RGB565 entries in the line buffer
//   - the second line does not change the buffer
//
// Parameters:
//   CAP_START : 0 = first 1280 bytes, 640 = second 1280 bytes
//   SWAP      : 0 = high byte first, 1 = byte-swapped
// ============================================================================
`timescale 1ns / 1ps

module tb_ov5640_line_capture;

    parameter integer CAP_START = 0;
    parameter integer SWAP      = 0;

    reg         pclk;
    reg         rst_n;
    reg         cap_en;
    reg  [7:0]  dvp_d;
    reg         dvp_href;
    reg         dvp_vsync;

    wire [9:0]  wr_addr;
    wire [15:0] wr_data;
    wire        wr_en;

    wire        capture_done;
    wire        capture_error;
    wire [15:0] line_bytes;
    wire [15:0] lines_seen;
    wire [15:0] line_total_dbg;
    wire [7:0]  dbg_state;

    integer errors;
    integer i;

    // ------------------------------------------------------------------
    // DUT + line buffer
    // ------------------------------------------------------------------
    ov5640_line_capture #(
        .HREF_ACTIVE_HIGH (1        ),
        .PIXELS           (640      ),
        .CAPTURE_START    (CAP_START),
        .BYTE_SWAP        (SWAP     ),
        .LINE_MIN         (1200     ),
        .LINE_MAX         (2200     ),
        .STARTUP_LINES    (1        ),
        .TIMEOUT_CYCLES   (16_000_000)
    ) u_cap (
        .pclk          (pclk          ),
        .rst_n         (rst_n         ),
        .cap_en        (cap_en        ),
        .dvp_d         (dvp_d         ),
        .dvp_href      (dvp_href      ),
        .dvp_vsync     (dvp_vsync     ),
        .wr_addr       (wr_addr       ),
        .wr_data       (wr_data       ),
        .wr_en         (wr_en         ),
        .capture_done  (capture_done  ),
        .capture_error (capture_error ),
        .line_bytes    (line_bytes    ),
        .lines_seen    (lines_seen    ),
        .line_total_dbg(line_total_dbg),
        .dbg_state     (dbg_state     )
    );

    line_buffer_dpram #(
        .ADDR_WIDTH (10),
        .DATA_WIDTH (16)
    ) u_ram (
        .wr_clk  (pclk    ),
        .wr_en   (wr_en   ),
        .wr_addr (wr_addr ),
        .wr_data (wr_data ),
        .rd_clk  (pclk    ),
        .rd_addr (10'd0   ),
        .rd_data (        )
    );

    initial pclk = 1'b0;
    always #10.4165 pclk = ~pclk;   // 48 MHz

    // ------------------------------------------------------------------
    // RGB565 reference color bar (80 px per bar)
    // ------------------------------------------------------------------
    function [15:0] bar565(input integer idx);
        integer bar;
        begin
            bar = idx / 80;
            case (bar)
                0: bar565 = 16'hFFFF;   // white
                1: bar565 = 16'hFFE0;   // yellow
                2: bar565 = 16'h07FF;   // cyan
                3: bar565 = 16'h07E0;   // green
                4: bar565 = 16'hF81F;   // magenta
                5: bar565 = 16'hF800;   // red
                6: bar565 = 16'h001F;   // blue
                default: bar565 = 16'h0000; // black
            endcase
        end
    endfunction

    function [15:0] expected_pixel(input integer idx);
        integer src_pix;
        reg [15:0] v;
        begin
            // CAPTURE_START is a byte offset; the source pixel is
            // CAP_START/2 + idx. Beyond pixel 639 the line is dummy (0).
            src_pix = (CAP_START / 2) + idx;
            if (src_pix < 640)
                v = bar565(src_pix);
            else
                v = 16'h0000;
            expected_pixel = SWAP ? {v[7:0], v[15:8]} : v;
        end
    endfunction

    // ------------------------------------------------------------------
    // Camera stream drivers (drive on the falling edge)
    // ------------------------------------------------------------------
    task drive_long_blank;
        begin
            for (i = 0; i < 65920; i = i + 1) begin
                @(negedge pclk);
                dvp_href = 1'b1;
                dvp_d    = 8'h00;
            end
            @(negedge pclk);
            dvp_href = 1'b0;
            dvp_d    = 8'h00;
            for (i = 0; i < 1280; i = i + 1) @(negedge pclk);
        end
    endtask

    task drive_valid_line;
        reg [15:0] p;
        begin
            for (i = 0; i < 1920; i = i + 1) begin
                @(negedge pclk);
                dvp_href = 1'b1;
                if (i < 1280) begin
                    p = bar565(i / 2);
                    dvp_d = (i % 2 == 0) ? p[15:8] : p[7:0];
                end else begin
                    dvp_d = 8'h00;
                end
            end
            @(negedge pclk);
            dvp_href = 1'b0;
            dvp_d    = 8'h00;
            for (i = 0; i < 1280; i = i + 1) @(negedge pclk);
        end
    endtask

    task drive_const_line(input [7:0] v);
        begin
            for (i = 0; i < 1920; i = i + 1) begin
                @(negedge pclk);
                dvp_href = 1'b1;
                dvp_d    = v;
            end
            @(negedge pclk);
            dvp_href = 1'b0;
            dvp_d    = 8'h00;
            for (i = 0; i < 1280; i = i + 1) @(negedge pclk);
        end
    endtask

    // ------------------------------------------------------------------
    // Main
    // ------------------------------------------------------------------
    initial begin
        errors    = 0;
        pclk      = 1'b0;
        rst_n     = 1'b0;
        cap_en    = 1'b0;
        dvp_d     = 8'h00;
        dvp_href  = 1'b0;
        dvp_vsync = 1'b0;

        repeat (5) @(posedge pclk);
        rst_n = 1'b1;
        repeat (5) @(posedge pclk);
        cap_en = 1'b1;
        repeat (5) @(posedge pclk);

        // 1. Long blanking line: must be rejected.
        drive_long_blank;
        repeat (5) @(posedge pclk);
        if (capture_done !== 1'b0) begin
            $display("FAIL long blanking line accepted, line_bytes=%0d", line_bytes);
            errors = errors + 1;
        end else if (capture_error !== 1'b0) begin
            $display("FAIL timeout error asserted before the valid line");
            errors = errors + 1;
        end else begin
            $display("ok   long blanking line rejected, line_total_dbg=%0d", line_total_dbg);
        end

        // 2. Valid line: must capture 640 pixels.
        drive_valid_line;
        repeat (5) @(posedge pclk);
        if (capture_done !== 1'b1) begin
            $display("FAIL valid line not captured");
            errors = errors + 1;
        end else begin
            $display("ok   valid line captured, line_bytes=%0d lines_seen=%0d", line_bytes, lines_seen);
        end
        if (line_bytes != 16'd1920) begin
            $display("FAIL line_bytes=%0d expected 1920", line_bytes);
            errors = errors + 1;
        end

        // 3. Check every line-buffer entry.
        for (i = 0; i < 640; i = i + 1) begin
            if (u_ram.mem[i] !== expected_pixel(i)) begin
                $display("FAIL mem[%0d]=%04h expected=%04h", i, u_ram.mem[i], expected_pixel(i));
                errors = errors + 1;
                if (errors > 10) i = 640; // stop spamming
            end
        end
        if (errors == 0)
            $display("ok   all 640 RGB565 entries match (CAP_START=%0d SWAP=%0d)", CAP_START, SWAP);

        // 4. A second valid line must not overwrite the frozen buffer.
        drive_const_line(8'h55);
        repeat (5) @(posedge pclk);
        if (u_ram.mem[0] !== expected_pixel(0) || u_ram.mem[320] !== expected_pixel(320)) begin
            $display("FAIL frozen buffer was overwritten (mem[0]=%04h mem[320]=%04h)",
                     u_ram.mem[0], u_ram.mem[320]);
            errors = errors + 1;
        end else begin
            $display("ok   buffer stayed frozen after the second line");
        end

        if (errors == 0)
            $display("TB: PASS - ov5640_line_capture (CAP_START=%0d SWAP=%0d)", CAP_START, SWAP);
        else
            $display("TB: FAIL - ov5640_line_capture, errors=%0d", errors);

        $finish;
    end

endmodule
