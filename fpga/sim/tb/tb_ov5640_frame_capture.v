// ============================================================================
// tb_ov5640_frame_capture.v
//
// Unit test for the Stage 3 PCLK-domain full-frame capture.
//
// Real camera timing is used: 48.000 MHz PCLK, HREF active phase 1920 PCLK
// (1280 valid bytes + 640 dummy bytes), HREF inactive 1280 PCLK, VSYNC
// active high 66.6 us. A long vertical-blanking HREF pulse (~65,920 PCLK)
// is driven at the frame boundary, matching the measured board behaviour.
//
// Parameters let the regression cover:
//   V_ACTIVE    : rows expected per frame (missing rows are padded black)
//   CAM_LINES   : normal image lines actually driven
//   LONG_LINE   : 1 = drive the long blanking HREF pulse (one extra row)
//   CAP_START   : 0 or 640 capture window
//   SWAP        : byte swap
//   BUF_FREE_OFF: 1 = DDR side reports no free buffer for frame 2
//
// Expected output: header + V_ACTIVE*80 beats, in order; pixel values match
// the driven bytes; pad rows are 0x0000.
// ============================================================================
`timescale 1ns / 1ps

module tb_ov5640_frame_capture #(
    parameter integer V_ACTIVE     = 4,
    parameter integer HREF_ACTIVE_HIGH = 1,
    parameter integer CAM_LINES    = 4,
    parameter integer LONG_LINE    = 0,
    parameter integer CAP_START    = 0,
    parameter integer SWAP         = 0,
    parameter integer BUF_FREE_OFF = 0
) ();

    localparam integer LONG_LEN = 65920;

    reg         pclk;
    reg         rst_n;
    reg         cap_en;
    reg         buf_free;
    reg  [7:0]  dvp_d;
    reg         dvp_href_phase;
    wire        dvp_href;
    assign dvp_href = HREF_ACTIVE_HIGH ? dvp_href_phase : ~dvp_href_phase;
    reg         dvp_vsync;

    wire        fifo_wr_en;
    wire [128:0] fifo_wr_data;
    wire        frame_active;
    wire [15:0] lines_captured;
    wire [15:0] frames_started;
    wire        capture_error;
    wire [7:0]  dbg_state;

    integer errors;

    ov5640_frame_capture #(
        .HREF_ACTIVE_HIGH  (HREF_ACTIVE_HIGH),
        .VSYNC_ACTIVE_HIGH (1),
        .PIXELS            (640),
        .V_ACTIVE          (V_ACTIVE),
        .BEATS_PER_LINE    (80),
        .CAPTURE_START     (CAP_START),
        .BYTE_SWAP         (SWAP),
        .LINE_MIN          (1200),
        .LINE_MAX          (70000)
    ) dut (
        .pclk            (pclk),
        .rst_n           (rst_n),
        .cap_en          (cap_en),
        .buf_free        (buf_free),
        .dvp_d           (dvp_d),
        .dvp_href        (dvp_href),
        .dvp_vsync       (dvp_vsync),
        .fifo_wr_en      (fifo_wr_en),
        .fifo_wr_data    (fifo_wr_data),
        .fifo_wr_full    (1'b0),
        .frame_active_o  (frame_active),
        .lines_captured_o(lines_captured),
        .frames_started_o(frames_started),
        .capture_error_o (capture_error),
        .dbg_state_o     (dbg_state)
    );

    // 48.000 MHz camera pixel clock
    initial pclk = 1'b0;
    always #10.4167 pclk = ~pclk;

    // ------------------------------------------------------------------
    // Collected output words
    // ------------------------------------------------------------------
    reg [128:0] words [0:16*1024];
    integer     nwords;

    always @(posedge pclk) begin
        if (fifo_wr_en) begin
            words[nwords] = fifo_wr_data;
            nwords = nwords + 1;
        end
    end

    // ------------------------------------------------------------------
    // Expected pixel for captured pixel k of line y (driven byte pattern)
    //   bytes 0..1279     : pixel p = {8'h10+y, p[7:0]}
    //   bytes 1280..1919  : dummy 0xEE
    // ------------------------------------------------------------------
    function [15:0] exp_pix;
        input integer y;
        input integer k;
        integer b;
        reg [7:0] hi, lo;
        begin
            b = CAP_START + 2*k;
            if (b < 1280) begin
                hi = 8'h10 + y;
                lo = (b >> 1) & 8'hFF;
            end else begin
                hi = 8'hEE;
                lo = 8'hEE;
            end
            exp_pix = SWAP ? {lo, hi} : {hi, lo};
        end
    endfunction

    // ------------------------------------------------------------------
    // Camera driver
    // ------------------------------------------------------------------
    integer cyc;
    integer y;
    integer i;
    integer accepted;

    task drive_byte;
        input [7:0] b;
        begin
            dvp_d = b;
            @(posedge pclk); #1;
        end
    endtask

    task drive_line;
        input integer yline;
        begin
            dvp_href_phase = 1'b1;
            // byte 0 is sampled on the first active PCLK edge
            dvp_d = 8'h10 + yline;
            @(posedge pclk); #1;
            for (i = 1; i < 1280; i = i + 1) begin
                if (i & 1) dvp_d = ((i >> 1) & 8'hFF);      // low byte
                else       dvp_d = 8'h10 + yline;           // high byte
                @(posedge pclk); #1;
            end
            for (i = 0; i < 640; i = i + 1) begin
                dvp_d = 8'hEE;
                @(posedge pclk); #1;
            end
            dvp_href_phase = 1'b0;
            for (i = 0; i < 1280; i = i + 1) begin
                dvp_d = 8'h00;
                @(posedge pclk); #1;
            end
        end
    endtask

    task drive_long_blank;
        begin
            dvp_href_phase = 1'b1;
            dvp_d    = 8'h00;
            for (i = 0; i < LONG_LEN; i = i + 1) begin
                if (i == 10000)      dvp_vsync = 1'b1;
                if (i == 13200)      dvp_vsync = 1'b0;
                @(posedge pclk); #1;
            end
            dvp_href_phase = 1'b0;
            for (i = 0; i < 1280; i = i + 1) @(posedge pclk);
        end
    endtask

    task drive_frame_start;
        begin
            dvp_href_phase = 1'b0;
            dvp_vsync = 1'b1;
            for (i = 0; i < 3200; i = i + 1) @(posedge pclk);
            dvp_vsync = 1'b0;
            for (i = 0; i < 200; i = i + 1) @(posedge pclk);
        end
    endtask

    // ------------------------------------------------------------------
    // Checker
    // ------------------------------------------------------------------
    integer beat;
    integer beat_no;
    integer frame_beats;
    integer pix_k;
    reg [15:0] got;
    reg [15:0] exp;
    integer ci;
    integer frame;

    task check_frame;
        input integer frame_no;
        input integer first_word;
        begin
            if (words[first_word][128] !== 1'b1) begin
                $display("FAIL frame %0d: missing header", frame_no);
                errors = errors + 1;
            end
            for (beat_no = 0; beat_no < V_ACTIVE * 80; beat_no = beat_no + 1) begin
                if (words[first_word + 1 + beat_no][128] !== 1'b0) begin
                    $display("FAIL frame %0d beat %0d: unexpected header",
                             frame_no, beat_no);
                    errors = errors + 1;
                end
                // y = beat_no / 80, k = (beat_no % 80)*8 + i
                for (pix_k = 0; pix_k < 8; pix_k = pix_k + 1) begin
                    got = words[first_word + 1 + beat_no][16*pix_k +: 16];
                    if ((beat_no / 80) < CAM_LINES)
                        exp = exp_pix(beat_no / 80, (beat_no % 80) * 8 + pix_k);
                    else if (LONG_LINE && ((beat_no / 80) == CAM_LINES))
                        exp = 16'h0000;  // long pulse driven with 0x00
                    else
                        exp = 16'h0000;  // padded row
                    if (got !== exp) begin
                        if (errors < 20)
                            $display("FAIL frame %0d beat %0d pix %0d: got %04h exp %04h",
                                     frame_no, beat_no, pix_k, got, exp);
                        errors = errors + 1;
                    end
                end
            end
        end
    endtask

    // ------------------------------------------------------------------
    // Stimulus
    // ------------------------------------------------------------------
    initial begin
        errors = 0;
        nwords = 0;
        rst_n = 1'b0;
        cap_en = 1'b0;
        buf_free = 1'b1;
        dvp_d = 8'd0;
        dvp_href_phase = 1'b0;
        dvp_vsync = 1'b0;

        repeat (20) @(posedge pclk);
        rst_n = 1'b1;
        repeat (20) @(posedge pclk);
        cap_en = 1'b1;
        // Let cap_en/buf_free synchronizers settle before the first VSYNC
        // (on the board cfg_ok precedes the camera stream by hundreds of ms).
        repeat (16) @(posedge pclk);

        // One VSYNC per frame, inside the long blanking HREF pulse when
        // LONG_LINE=1 (measured behaviour), otherwise a plain VSYNC pulse.

        // Frame 1
        if (LONG_LINE) drive_long_blank; else drive_frame_start;
        for (y = 0; y < CAM_LINES; y = y + 1) drive_line(y);

        // Frame 2: optionally no free buffer (frame is dropped)
        if (BUF_FREE_OFF) buf_free = 1'b0;
        repeat (8) @(posedge pclk);
        if (LONG_LINE) drive_long_blank; else drive_frame_start;
        for (y = 0; y < CAM_LINES; y = y + 1) drive_line(y);

        // Frame 3: buffer free again
        buf_free = 1'b1;
        repeat (8) @(posedge pclk);
        if (LONG_LINE) drive_long_blank; else drive_frame_start;
        for (y = 0; y < CAM_LINES; y = y + 1) drive_line(y);

        // Closing boundary: close frame 3 (pad if needed) but do not open a
        // fourth frame (buf_free low -> no header).
        buf_free = 1'b0;
        repeat (4) @(posedge pclk);
        if (LONG_LINE) drive_long_blank; else drive_frame_start;
        repeat (4000) @(posedge pclk);

        // ------------------------------------------------------------------
        // Check collected words
        // ------------------------------------------------------------------
        accepted = CAM_LINES + LONG_LINE;
        if (accepted > V_ACTIVE) accepted = V_ACTIVE;
        frame_beats = V_ACTIVE * 80 + 1;

        $display("words collected=%0d frames_started=%0d lines=%0d accepted=%0d",
                 nwords, frames_started, lines_captured, accepted);

        if (BUF_FREE_OFF) begin
            // Frame 1 was captured, frame 2 was dropped, frame 3 captured.
            if (nwords != 2 * frame_beats) begin
                $display("FAIL word count %0d expected %0d",
                         nwords, 2 * frame_beats);
                errors = errors + 1;
            end else begin
                check_frame(1, 0);
                check_frame(3, frame_beats);
            end
        end else begin
            if (nwords != 3 * frame_beats) begin
                $display("FAIL word count %0d expected %0d",
                         nwords, 3 * frame_beats);
                errors = errors + 1;
            end else begin
                check_frame(1, 0);
                check_frame(2, frame_beats);
                check_frame(3, 2 * frame_beats);
            end
        end

        if (capture_error !== 1'b0) begin
            $display("FAIL unexpected capture_error");
            errors = errors + 1;
        end

        if (errors == 0) $display("TB: PASS - ov5640_frame_capture");
        else             $display("TB: FAIL - ov5640_frame_capture errors=%0d", errors);
        if (errors != 0) $fatal(1, "Test failed");
        $finish;
    end

    initial begin
        #20_000_000;
        $fatal(1, "simulation timeout");
    end

endmodule
