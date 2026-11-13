// ============================================================================
// ov5640_frame_capture.v
//
// Full-frame OV5640 DVP capture (PCLK domain) for the Stage 3 DDR frame
// buffer. One complete 640x480 RGB565 frame becomes 480 rows x 80 beats of
// 128 bits (8 pixels per beat). Beats are pushed into the PCLK -> DDR user
// clock asynchronous FIFO.
//
// FIFO word format (DATA_WIDTH = 129):
//   word[128] = 1 : frame header (start of a new camera frame)
//   word[128] = 0 : pixel beat, word[127:0] = 8 RGB565 pixels, pixel0 in
//                   bits [15:0] .. pixel7 in bits [127:112]
//
// Frame protocol (unchanged data contract with cam_fb_writer):
//   header, 38400 beats, header, 38400 beats, ...
// Exactly V_ACTIVE lines are always emitted. Missing lines are padded with
// black rows (0x0000) at the next VSYNC, before that frame's data is closed.
//
// Line capture rules (same measured timing as ov5640_line_capture):
//   - Data/HREF/VSYNC are sampled on the rising PCLK edge.
//   - A line is the HREF-active phase selected by HREF_ACTIVE_HIGH.
//   - Only HREF-active phases with at least LINE_MIN bytes are accepted.
//   - The captured window is bytes [CAPTURE_START, CAPTURE_START+2*PIXELS)
//     of the active phase; the measured active phase is 1920 PCLK (high) or
//     1280 PCLK (low), so 1280 bytes are always present.
//   - The 1.373 ms vertical-blanking HREF high (~65,900 bytes) is NOT
//     rejected: it is one of the 480 HREF rises per frame, and the first
//     1280 bytes of that phase are treated as the last image row. This is
//     the interpretation that makes 480 HREF rises equal 480 image rows.
//     If board evidence shows this row is invalid, set LINE_MAX below the
//     blanking length and let the pad logic fill that row with black.
//
// A whole line is first stored in a 640x16 line RAM, then read out. This
// guarantees that a short/spurious HREF phase can never leak partial beats
// into the DDR frame buffer: the length check happens before any beat is
// pushed.
//
// The frame header is only pushed when the DDR side reports a free write
// buffer (`buf_free`), so a camera frame is dropped (not captured) while
// both ping-pong buffers are in use.
// ============================================================================
`timescale 1ns / 1ps

module ov5640_frame_capture #(
    parameter integer HREF_ACTIVE_HIGH  = 1,
    parameter integer VSYNC_ACTIVE_HIGH = 1,
    parameter integer PIXELS            = 640,
    parameter integer V_ACTIVE          = 480,
    parameter integer BEATS_PER_LINE    = 80,       // PIXELS / 8
    parameter integer CAPTURE_START     = 0,        // even; 0 or 640
    parameter integer BYTE_SWAP         = 0,        // 1 = swap high/low byte
    parameter integer LINE_MIN          = 1200,     // min active-phase length
    parameter integer LINE_MAX          = 70000,    // accept the 1.373 ms row
    parameter integer TIMEOUT_CYCLES    = 26_000_000 // ~0.54 s at 48 MHz
) (
    input  wire         pclk,
    input  wire         rst_n,          // async assert, PCLK sync release
    input  wire         cap_en,         // cfg_ok && DDR ready, 50 MHz level
    input  wire         buf_free,       // DDR user-clock level, 2FF here

    input  wire [7:0]   dvp_d,
    input  wire         dvp_href,
    input  wire         dvp_vsync,

    // 129-bit FIFO write port (see word format above).
    // IMPORTANT: driven combinationally. The async FIFO's wr_full is a
    // registered "this write would overflow" flag, so a registered wr_en
    // would be checked one cycle too late and the word would be dropped.
    output wire         fifo_wr_en,
    output wire [128:0] fifo_wr_data,
    input  wire         fifo_wr_full,

    // Status
    output wire         frame_active_o,
    output wire [15:0]  lines_captured_o,
    output wire [15:0]  frames_started_o,
    output reg          capture_error_o,
    output wire [7:0]   dbg_state_o
);

    localparam integer CAP_END = CAPTURE_START + 2 * PIXELS;

    localparam [2:0] S_IDLE = 3'd0,
                     S_LINE = 3'd1,
                     S_EMIT = 3'd2,
                     S_PAD  = 3'd3,
                     S_EOF  = 3'd4;

    // ------------------------------------------------------------------
    // PCLK-domain reset: async assert, sync release
    // ------------------------------------------------------------------
    reg [2:0] rst_sync;

    always @(posedge pclk or negedge rst_n) begin
        if (!rst_n) rst_sync <= 3'b000;
        else        rst_sync <= {rst_sync[1:0], 1'b1};
    end

    wire prst_n = rst_sync[2];

    // ------------------------------------------------------------------
    // Level synchronizers: cap_en (50 MHz) and buf_free (DDR user clock)
    // ------------------------------------------------------------------
    reg [1:0] cap_sync;
    reg [1:0] free_sync;

    always @(posedge pclk or negedge prst_n) begin
        if (!prst_n) begin
            cap_sync  <= 2'b00;
            free_sync <= 2'b00;
        end else begin
            cap_sync  <= {cap_sync[0],  cap_en};
            free_sync <= {free_sync[0], buf_free};
        end
    end

    wire cap_en_p   = cap_sync[1];
    wire buf_free_p = free_sync[1];

    // ------------------------------------------------------------------
    // Input registers and edge detection
    // ------------------------------------------------------------------
    reg [7:0] d_q;
    reg       href_q;
    reg       vsync_q;

    always @(posedge pclk or negedge prst_n) begin
        if (!prst_n) begin
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

    reg href_act_d;
    reg vsync_act_d;

    always @(posedge pclk or negedge prst_n) begin
        if (!prst_n) begin
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
    // Line RAM (single clock, write during S_LINE, read during S_EMIT)
    // ------------------------------------------------------------------
    reg [15:0] line_ram [0:PIXELS-1];

    // ------------------------------------------------------------------
    // Line capture counters
    // ------------------------------------------------------------------
    reg [16:0] line_bytes;      // active-phase cycles in the current line
    reg [11:0] byte_idx;        // byte offset inside the active phase
    reg [10:0] pix_wr;          // pixels written into the line RAM
    reg [7:0]  high_byte;
    reg        line_seen_long;  // line exceeded LINE_MAX

    wire first_cycle = href_rise;
    wire [11:0] eff_idx = first_cycle ? 12'd0 : byte_idx;

    wire in_window = href_act &&
                     (eff_idx >= CAPTURE_START) &&
                     (eff_idx <  CAP_END);

    wire low_byte   = eff_idx[0];
    wire [10:0] pix_index = (eff_idx - CAPTURE_START) >> 1;

    wire [15:0] pix_pair = BYTE_SWAP ? {d_q, high_byte} : {high_byte, d_q};

    // ------------------------------------------------------------------
    // Emit pipeline registers
    // ------------------------------------------------------------------
    reg [9:0]   emit_a;         // next line RAM address to read
    reg         ram_v;          // ram_q holds a valid pixel
    reg [15:0]  ram_q;
    reg [127:0] beat_shift;
    reg [2:0]   beat_cnt;
    reg [127:0] beat_out;
    reg         beat_ready;
    reg [9:0]   pix_out;

    // ------------------------------------------------------------------
    // Frame / state registers
    // ------------------------------------------------------------------
    reg [2:0]  state;
    reg        frame_active;
    reg [15:0] lines_captured;
    reg [15:0] frames_started;
    reg        vsync_pending;
    reg [7:0]  pad_beat;        // 0..BEATS_PER_LINE-1
    reg        line_skip_dbg;   // HREF rise ignored (busy / inactive frame)
    reg [7:0]  dbg_state;

    assign frame_active_o   = frame_active;
    assign lines_captured_o = lines_captured;
    assign frames_started_o = frames_started;
    assign dbg_state_o      = dbg_state;

    // ------------------------------------------------------------------
    // FIFO write port (combinational). fifo_wr_full is the same-cycle
    // "this write would overflow" flag, so the enable must not be delayed.
    // The state machine below advances on the same !fifo_wr_full condition,
    // keeping the pushed word and the counters consistent.
    // ------------------------------------------------------------------
    wire push_emit = (state == S_EMIT) && beat_ready;
    wire push_pad  = (state == S_PAD);
    wire push_hdr  = (state == S_EOF) && buf_free_p;
    wire push_req  = push_emit | push_pad | push_hdr;

    assign fifo_wr_en   = push_req && !fifo_wr_full;
    assign fifo_wr_data = push_hdr ? {1'b1, 128'd0} :
                          (push_pad ? {1'b0, 128'd0} : {1'b0, beat_out});

    // ------------------------------------------------------------------
    // Main state machine (PCLK)
    // ------------------------------------------------------------------
    always @(posedge pclk or negedge prst_n) begin
        if (!prst_n) begin
            state           <= S_IDLE;
            frame_active    <= 1'b0;
            lines_captured  <= 16'd0;
            frames_started  <= 16'd0;
            vsync_pending   <= 1'b0;
            line_bytes      <= 17'd0;
            byte_idx        <= 12'd0;
            pix_wr          <= 11'd0;
            high_byte       <= 8'd0;
            line_seen_long  <= 1'b0;
            pad_beat        <= 8'd0;
            emit_a          <= 10'd0;
            ram_v           <= 1'b0;
            ram_q           <= 16'd0;
            beat_shift      <= 128'd0;
            beat_cnt        <= 3'd0;
            beat_out        <= 128'd0;
            beat_ready      <= 1'b0;
            pix_out         <= 10'd0;
            line_skip_dbg   <= 1'b0;
            dbg_state       <= 8'd0;
        end else begin
            line_skip_dbg <= 1'b0;

            // VSYNC edge is always latched; it is processed when the line
            // pipeline is idle so no line is broken mid-transfer.
            if (vsync_rise)
                vsync_pending <= 1'b1;

            if (!cap_en_p) begin
                // Capture disabled: drop frame state but keep the line RAM.
                state          <= S_IDLE;
                frame_active   <= 1'b0;
                lines_captured <= 16'd0;
                vsync_pending  <= 1'b0;
                beat_ready     <= 1'b0;
                ram_v          <= 1'b0;
                byte_idx       <= 12'd0;
                line_bytes     <= 17'd0;
            end else begin
                case (state)
                    // ----------------------------------------------
                    S_IDLE: begin
                        if (vsync_pending) begin
                            // Close the previous frame: pad missing rows,
                            // then open the next frame if a buffer is free.
                            if (frame_active && (lines_captured < V_ACTIVE)) begin
                                pad_beat <= 8'd0;
                                state    <= S_PAD;
                            end else begin
                                state    <= S_EOF;
                            end
                        end else if (href_rise) begin
                            if (frame_active && (lines_captured < V_ACTIVE)) begin
                                // Start a new line.
                                state          <= S_LINE;
                                line_bytes     <= 17'd1;
                                byte_idx       <= 12'd1;
                                pix_wr         <= 11'd0;
                                high_byte      <= d_q;      // first byte = high
                                line_seen_long <= 1'b0;
                                ram_v          <= 1'b0;
                            end else begin
                                line_skip_dbg <= 1'b1;
                            end
                        end
                    end

                    // ----------------------------------------------
                    S_LINE: begin
                        if (href_act) begin
                            line_bytes <= line_bytes + 17'd1;
                            byte_idx   <= byte_idx + 12'd1;

                            if (line_bytes >= LINE_MAX)
                                line_seen_long <= 1'b1;

                            if (in_window && !low_byte)
                                high_byte <= d_q;

                            if (in_window && low_byte) begin
                                line_ram[pix_index[9:0]] <= pix_pair;
                                pix_wr <= pix_wr + 11'd1;
                            end
                        end else if (href_fall) begin
                            if (!line_seen_long &&
                                (line_bytes >= LINE_MIN) &&
                                (line_bytes <= LINE_MAX) &&
                                (pix_wr == PIXELS) &&
                                (lines_captured < V_ACTIVE)) begin
                                // Line is complete and plausible: emit it.
                                state      <= S_EMIT;
                                emit_a     <= 10'd0;
                                ram_v      <= 1'b0;
                                beat_shift <= 128'd0;
                                beat_cnt   <= 3'd0;
                                beat_out   <= 128'd0;
                                beat_ready <= 1'b0;
                                pix_out    <= 10'd0;
                            end else begin
                                // Rejected line: no beats were pushed.
                                state <= S_IDLE;
                            end
                        end
                    end

                    // ----------------------------------------------
                    S_EMIT: begin
                        if (beat_ready) begin
                            if (!fifo_wr_full) begin
                                beat_ready   <= 1'b0;
                                if (pix_out == PIXELS) begin
                                    // Last beat of the line accepted.
                                    lines_captured <= lines_captured + 16'd1;
                                    state          <= S_IDLE;
                                end
                            end
                        end else begin
                            // Issue one RAM read per cycle (synchronous read).
                            if (emit_a < PIXELS) begin
                                ram_q  <= line_ram[emit_a[9:0]];
                                ram_v  <= 1'b1;
                                emit_a <= emit_a + 10'd1;
                            end else begin
                                ram_v  <= 1'b0;
                            end

                            // Consume the pixel read in the previous cycle.
                            if (ram_v) begin
                                beat_shift <= {ram_q, beat_shift[127:16]};
                                if (beat_cnt == 3'd7) begin
                                    beat_out   <= {ram_q, beat_shift[127:16]};
                                    beat_ready <= 1'b1;
                                    beat_cnt   <= 3'd0;
                                end else begin
                                    beat_cnt <= beat_cnt + 3'd1;
                                end
                                pix_out <= pix_out + 10'd1;
                            end
                        end
                    end

                    // ----------------------------------------------
                    S_PAD: begin
                        // Fill missing rows with black beats.
                        if (!fifo_wr_full) begin
                            if (pad_beat == (BEATS_PER_LINE - 1)) begin
                                pad_beat       <= 8'd0;
                                lines_captured <= lines_captured + 16'd1;
                                if ((lines_captured + 16'd1) == V_ACTIVE)
                                    state <= S_EOF;
                            end else begin
                                pad_beat <= pad_beat + 8'd1;
                            end
                        end
                    end

                    // ----------------------------------------------
                    S_EOF: begin
                        // Open the next frame only when the DDR side has a
                        // ping-pong buffer the display reader is not using.
                        if (!buf_free_p) begin
                            frame_active  <= 1'b0;
                            vsync_pending <= 1'b0;
                            state         <= S_IDLE;
                        end else if (!fifo_wr_full) begin
                            frame_active  <= 1'b1;
                            lines_captured<= 16'd0;
                            frames_started<= frames_started + 16'd1;
                            vsync_pending <= 1'b0;
                            state         <= S_IDLE;
                        end
                    end

                    default: state <= S_IDLE;
                endcase
            end

            dbg_state <= {
                3'b000,
                vsync_q,
                frame_active,
                (state == S_PAD),
                (state == S_EMIT),
                (state == S_LINE)
            };
        end
    end

    // ------------------------------------------------------------------
    // No-VSYNC timeout: catches a camera that never streams after cfg_ok.
    // ------------------------------------------------------------------
    reg [31:0] timeout_cnt;

    always @(posedge pclk or negedge prst_n) begin
        if (!prst_n) begin
            timeout_cnt     <= 32'd0;
            capture_error_o <= 1'b0;
        end else if (!cap_en_p) begin
            timeout_cnt     <= 32'd0;
            capture_error_o <= 1'b0;
        end else if (vsync_rise) begin
            timeout_cnt     <= 32'd0;
            capture_error_o <= 1'b0;
        end else if (timeout_cnt >= (TIMEOUT_CYCLES - 1)) begin
            capture_error_o <= 1'b1;
        end else begin
            timeout_cnt <= timeout_cnt + 32'd1;
        end
    end

endmodule
