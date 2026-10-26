// ============================================================================
// dvp_capture.v
// OV5640 8-bit DVP capture and frame/line/pixel counters, in the PCLK domain.
//
// Timing contract (must match the SCCB configuration and the board):
//   - D[7:0], HREF, VSYNC are sampled on the rising edge of PCLK.
//   - HREF is active high; a high HREF cycle carries one valid byte.
//   - VSYNC is active high; its rising edge starts a new frame.
//   - RGB565: two bytes per pixel, first byte = {R[4:0],G[5:3]} (high byte),
//     second byte = {G[2:0],B[4:0]} (low byte). This matches OV5640 register
//     0x4300 = 0x61 (format 6, output sequence 1).
//
// IMPORTANT:
//   - The polarity parameters must be matched to register 0x4740. The 2026-10-26
//     LA capture measured HREF active high and VSYNC active low (idle high,
//     short low pulse), so the configuration table writes 0x4740 = 0x22 and
//     the board top sets VSYNC_ACTIVE_HIGH=0. Do not assume the reset default
//     0x20 (HREF active low) or the earlier 0x23 attempt.
//   - PCLK is asynchronous to clk_50m. Never sample a one-PCLK event in the
//     system domain; this module counts in the PCLK domain and exports events
//     through an asynchronous FIFO.
//
// Event word (64 bit):
//   [63:56] tag        0xA5 = line event, 0x5A = frame-start event
//   [55:40] frame_cnt  frame index (first active frame = 1)
//   [39:24] line_cnt   line index inside the frame (first line = 0)
//   [23:8]  pix_cnt    valid bytes in the line (RGB565: 2 * pixels)
//   [7:0]   err_flags
//
// err_flags bits:
//   [0] odd byte count at line end
//   [1] zero-length line
//   [2] line length != EXPECTED_PIX (only when EXPECTED_PIX != 0)
//   [3] VSYNC asserted while HREF was high (partial line discarded)
//   [4] previous frame line count != EXPECTED_LINES (only in frame event)
//   [5] event FIFO overflow (sticky)
//   [6] reserved
//   [7] reserved
//
// Reset/enable:
//   - rst_n is asynchronous to PCLK. It is asserted asynchronously and
//     released synchronously in the PCLK domain by rst_sync.
//   - cap_en is a 50 MHz-domain level. It is synchronized into the PCLK
//     domain. When low, all counters are cleared and the first STARTUP_FRAMES
//     VSYNC edges are discarded.
//   - The event FIFO write side must use pclk_rst_n_o, not rst_n, so its reset
//     release is synchronous to PCLK.
// ============================================================================
`timescale 1ns / 1ps

module dvp_capture #(
    parameter integer HREF_ACTIVE_HIGH  = 1,
    parameter integer VSYNC_ACTIVE_HIGH = 1,
    parameter integer STARTUP_FRAMES    = 1,
    parameter integer EXPECTED_PIX      = 0,   // 0 disables the check
    parameter integer EXPECTED_LINES    = 0    // 0 disables the check
) (
    // PCLK domain
    input  wire        pclk,
    input  wire        rst_n,
    input  wire        cap_en,

    input  wire [7:0]  dvp_d,
    input  wire        dvp_href,
    input  wire        dvp_vsync,

    // Event FIFO write side
    output reg  [63:0] evt_data,
    output reg         evt_wr,
    input  wire        evt_full,
    output reg         evt_overflow,

    // Debug / status (PCLK domain values; observe slowly or via the FIFO)
    output reg  [15:0] frame_cnt,
    output reg  [15:0] line_cnt,
    output reg  [15:0] pix_cnt,
    output reg  [15:0] line_pix_cnt,
    output reg  [15:0] startup_cnt,
    output reg         active,
    output reg         frame_start_pulse,
    output reg  [7:0]  err_flags,

    // Sampled-byte observability for simulation and future pixel FIFO
    output wire        sample_valid,
    output wire [7:0]  sample_data,

    // Reset for the event FIFO write side
    output wire        pclk_rst_n_o
);

    localparam [7:0] TAG_LINE  = 8'hA5;
    localparam [7:0] TAG_FRAME = 8'h5A;

    // ------------------------------------------------------------------
    // PCLK-domain reset: async assert, sync release
    // ------------------------------------------------------------------
    reg [2:0] rst_sync;

    always @(posedge pclk or negedge rst_n) begin
        if (!rst_n) rst_sync <= 3'b000;
        else        rst_sync <= {rst_sync[1:0], 1'b1};
    end

    wire pclk_rst_n = rst_sync[2];
    assign pclk_rst_n_o = pclk_rst_n;

    // ------------------------------------------------------------------
    // cap_en: 50 MHz level -> PCLK domain
    // ------------------------------------------------------------------
    reg [1:0] cap_sync;

    always @(posedge pclk or negedge pclk_rst_n) begin
        if (!pclk_rst_n) cap_sync <= 2'b00;
        else             cap_sync <= {cap_sync[0], cap_en};
    end

    wire cap_en_p = cap_sync[1];

    // ------------------------------------------------------------------
    // Input registers (sample on rising PCLK edge)
    // ------------------------------------------------------------------
    reg [7:0] d_q;
    reg       href_q;
    reg       vsync_q;

    always @(posedge pclk or negedge pclk_rst_n) begin
        if (!pclk_rst_n) begin
            d_q     <= 8'd0;
            href_q  <= 1'b0;
            vsync_q <= 1'b0;
        end else begin
            d_q     <= dvp_d;
            href_q  <= dvp_href;
            vsync_q <= dvp_vsync;
        end
    end

    wire href_act  = HREF_ACTIVE_HIGH  ? href_q  : ~href_q;
    wire vsync_act = VSYNC_ACTIVE_HIGH ? vsync_q : ~vsync_q;

    // ------------------------------------------------------------------
    // Edge detection
    // ------------------------------------------------------------------
    reg href_act_d;
    reg vsync_act_d;

    always @(posedge pclk or negedge pclk_rst_n) begin
        if (!pclk_rst_n) begin
            href_act_d  <= 1'b0;
            vsync_act_d <= 1'b0;
        end else begin
            href_act_d  <= href_act;
            vsync_act_d <= vsync_act;
        end
    end

    wire href_rise  =  href_act & ~href_act_d;
    wire href_fall  = ~href_act &  href_act_d;
    wire vsync_rise =  vsync_act & ~vsync_act_d;

    // ------------------------------------------------------------------
    // Frame start / startup filter
    // ------------------------------------------------------------------
    wire startup_ready = (startup_cnt + 16'd1 >= STARTUP_FRAMES);
    wire start_frame_now = vsync_rise && cap_en_p && (active || startup_ready);

    wire vsync_mid_line_now = start_frame_now && href_act_d;

    wire [15:0] next_frame_cnt = active ? (frame_cnt + 16'd1) : 16'd1;

    always @(posedge pclk or negedge pclk_rst_n) begin
        if (!pclk_rst_n) begin
            startup_cnt <= 16'd0;
            active      <= 1'b0;
        end else if (!cap_en_p) begin
            startup_cnt <= 16'd0;
            active      <= 1'b0;
        end else begin
            if (start_frame_now) begin
                active <= 1'b1;
            end
            if (vsync_rise && !active && (startup_cnt < STARTUP_FRAMES)) begin
                startup_cnt <= startup_cnt + 16'd1;
            end
        end
    end

    // ------------------------------------------------------------------
    // Sticky errors
    // ------------------------------------------------------------------
    reg vsync_mid_line_err;

    always @(posedge pclk or negedge pclk_rst_n) begin
        if (!pclk_rst_n)         vsync_mid_line_err <= 1'b0;
        else if (!cap_en_p)      vsync_mid_line_err <= 1'b0;
        else if (vsync_mid_line_now) vsync_mid_line_err <= 1'b1;
    end

    always @(posedge pclk or negedge pclk_rst_n) begin
        if (!pclk_rst_n)         evt_overflow <= 1'b0;
        else if (!cap_en_p)      evt_overflow <= 1'b0;
        else if (evt_wr && evt_full) evt_overflow <= 1'b1;
    end

    // ------------------------------------------------------------------
    // Error flags for the current event
    // ------------------------------------------------------------------
    reg byte_phase;

    wire line_event = href_fall && active && cap_en_p && !start_frame_now;

    wire line_odd_err  = byte_phase;
    wire line_zero_err = (pix_cnt == 16'd0);
    wire line_len_err  = (EXPECTED_PIX != 0) && (pix_cnt != EXPECTED_PIX);

    wire [7:0] line_err = {
        2'b00,
        evt_overflow,
        1'b0,
        1'b0,
        line_len_err,
        line_zero_err,
        line_odd_err
    };

    wire frame_len_err_now = active &&
                             (EXPECTED_LINES != 0) &&
                             (line_cnt != EXPECTED_LINES);

    wire [7:0] frame_err = {
        1'b0,
        1'b0,
        evt_overflow,
        frame_len_err_now,
        (vsync_mid_line_err | vsync_mid_line_now),
        1'b0,
        1'b0,
        1'b0
    };

    wire [7:0] err_add = (line_event      ? line_err  : 8'h00) |
                         (start_frame_now ? frame_err : 8'h00) |
                         ((evt_wr && evt_full) ? 8'h20 : 8'h00);

    always @(posedge pclk or negedge pclk_rst_n) begin
        if (!pclk_rst_n)    err_flags <= 8'h00;
        else if (!cap_en_p) err_flags <= 8'h00;
        else                err_flags <= err_flags | err_add;
    end

    // ------------------------------------------------------------------
    // Pixel counter, byte phase, line counter, frame counter
    // ------------------------------------------------------------------
    always @(posedge pclk or negedge pclk_rst_n) begin
        if (!pclk_rst_n) begin
            pix_cnt      <= 16'd0;
            byte_phase   <= 1'b0;
            line_pix_cnt <= 16'd0;
        end else if (!cap_en_p) begin
            pix_cnt      <= 16'd0;
            byte_phase   <= 1'b0;
            line_pix_cnt <= 16'd0;
        end else if (start_frame_now) begin
            pix_cnt      <= 16'd0;
            byte_phase   <= 1'b0;
            line_pix_cnt <= 16'd0;
        end else if (active && href_rise) begin
            // First valid byte of the line; high byte of the first pixel.
            pix_cnt    <= 16'd1;
            byte_phase <= 1'b1;
        end else if (active && href_act) begin
            pix_cnt    <= pix_cnt + 16'd1;
            byte_phase <= ~byte_phase;
        end else if (line_event) begin
            line_pix_cnt <= pix_cnt;
            byte_phase   <= 1'b0;
        end
    end

    always @(posedge pclk or negedge pclk_rst_n) begin
        if (!pclk_rst_n)         line_cnt <= 16'd0;
        else if (!cap_en_p)      line_cnt <= 16'd0;
        else if (start_frame_now) line_cnt <= 16'd0;
        else if (line_event)     line_cnt <= line_cnt + 16'd1;
    end

    always @(posedge pclk or negedge pclk_rst_n) begin
        if (!pclk_rst_n)         frame_cnt <= 16'd0;
        else if (!cap_en_p)      frame_cnt <= 16'd0;
        else if (start_frame_now) frame_cnt <= next_frame_cnt;
    end

    // ------------------------------------------------------------------
    // Event generation
    // ------------------------------------------------------------------
    always @(posedge pclk or negedge pclk_rst_n) begin
        if (!pclk_rst_n) begin
            evt_data <= 64'd0;
            evt_wr   <= 1'b0;
        end else if (!cap_en_p) begin
            evt_data <= 64'd0;
            evt_wr   <= 1'b0;
        end else begin
            evt_wr <= 1'b0;
            if (start_frame_now) begin
                evt_data <= {TAG_FRAME, next_frame_cnt, 16'd0, 16'd0, frame_err};
                evt_wr   <= 1'b1;
            end else if (line_event) begin
                evt_data <= {TAG_LINE, frame_cnt, line_cnt, pix_cnt, line_err};
                evt_wr   <= 1'b1;
            end
        end
    end

    always @(posedge pclk or negedge pclk_rst_n) begin
        if (!pclk_rst_n)         frame_start_pulse <= 1'b0;
        else if (!cap_en_p)      frame_start_pulse <= 1'b0;
        else                     frame_start_pulse <= start_frame_now;
    end

    // ------------------------------------------------------------------
    // Sampled-byte observability (one PCLK cycle; used by the TB and by a
    // future pixel FIFO)
    // ------------------------------------------------------------------
    assign sample_valid = href_act && active && cap_en_p;
    assign sample_data  = d_q;

endmodule
