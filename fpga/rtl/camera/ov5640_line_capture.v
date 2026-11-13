// ============================================================================
// ov5640_line_capture.v
// Capture one OV5640 DVP line into a 640 x 16 RGB565 line buffer, in the
// camera PCLK domain.
//
// Why this module exists:
//   The measured HREF active phase is 1920 PCLK at 48 MHz (40 us), while
//   640 RGB565 pixels need 1280 bytes. The first 1280 bytes of the active
//   phase are treated as the valid pixels; the remaining 640 bytes are
//   ignored. CAPTURE_START=640 selects the other half if the color-bar
//   display proves the validity window is different.
//
//   The 1.373 ms vertical-blanking HREF high is ~65,900 bytes. It is
//   rejected by the LINE_MIN..LINE_MAX filter instead of being trusted.
//
// Timing contract (must match 0x4300=0x61 and 0x4740=0x22):
//   - Data, HREF and VSYNC are sampled on the rising PCLK edge.
//   - HREF_ACTIVE_HIGH=1 samples the HREF-high phase.
//   - RGB565: first byte = high byte {R[4:0],G[5:3]},
//     second byte = low byte {G[2:0],B[4:0]}.
//
// The module writes the line buffer every accepted line until
// STARTUP_LINES lines have been accepted; then capture_done freezes the
// buffer so the HDMI read side can never see a partially written line.
// ============================================================================
`timescale 1ns / 1ps

module ov5640_line_capture #(
    parameter integer HREF_ACTIVE_HIGH = 1,
    parameter integer PIXELS           = 640,
    parameter integer CAPTURE_START    = 0,       // must be even; 0 or 640
    parameter integer BYTE_SWAP        = 0,       // 1 = swap high/low byte
    parameter integer LINE_MIN         = 1200,    // accept active-phase length
    parameter integer LINE_MAX         = 2200,
    parameter integer STARTUP_LINES    = 1,       // accept N lines, then freeze
    parameter integer TIMEOUT_CYCLES   = 16_000_000
) (
    input  wire        pclk,
    input  wire        rst_n,          // asynchronous assert, PCLK sync release
    input  wire        cap_en,         // cfg_ok, 50 MHz level

    input  wire [7:0]  dvp_d,
    input  wire        dvp_href,
    input  wire        dvp_vsync,      // sampled for debug only; not required

    // Line-buffer write port (PCLK domain, combinational)
    output wire [9:0]  wr_addr,
    output wire [15:0] wr_data,
    output wire        wr_en,

    // Status
    output reg         capture_done,
    output reg         capture_error,
    output reg  [15:0] line_bytes,
    output reg  [15:0] lines_seen,
    output reg  [15:0] line_total_dbg,
    output reg  [7:0]  dbg_state
);

    localparam integer CAP_END = CAPTURE_START + 2 * PIXELS;

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
    // cap_en: 50 MHz level -> PCLK domain
    // ------------------------------------------------------------------
    reg [1:0] cap_sync;

    always @(posedge pclk or negedge prst_n) begin
        if (!prst_n) cap_sync <= 2'b00;
        else         cap_sync <= {cap_sync[0], cap_en};
    end

    wire cap_en_p = cap_sync[1];

    // ------------------------------------------------------------------
    // Input registers and HREF/VSYNC edges
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

    wire href_act  = HREF_ACTIVE_HIGH ? href_q : ~href_q;

    reg href_act_d;

    always @(posedge pclk or negedge prst_n) begin
        if (!prst_n) href_act_d <= 1'b0;
        else         href_act_d <= href_act;
    end

    wire href_rise =  href_act & ~href_act_d;
    wire href_fall = ~href_act &  href_act_d;

    // ------------------------------------------------------------------
    // Byte/pixel counters
    // ------------------------------------------------------------------
    reg [16:0] line_total;     // total HREF-active cycles in this line
    reg [11:0] byte_idx;       // byte offset inside the active phase
    reg [10:0] pix_cnt;        // pixels written for this line
    reg [7:0]  high_byte;
    reg        line_full;
    reg [15:0] accepted_cnt;

    // First active cycle: the current d_q is byte 0.
    wire first_cycle = href_rise;
    wire [11:0] eff_idx = first_cycle ? 12'd0 : byte_idx;

    wire in_window  = href_act &&
                      !capture_done &&
                      (eff_idx >= CAPTURE_START) &&
                      (eff_idx <  CAP_END);

    wire low_byte   = eff_idx[0];
    wire [10:0] pix_index = (eff_idx - CAPTURE_START) >> 1;

    // Combinational write event, then one pipeline register before the ERAM.
    // The register shortens the register-to-ERAM path and improves the hold
    // margin in the 48 MHz PCLK domain. The RAM write happens one PCLK later
    // than the low-byte sample; all three signals are delayed together.
    wire        wr_en_comb   = in_window && low_byte;
    wire [9:0]  wr_addr_comb = pix_index[9:0];
    wire [15:0] wr_data_comb = BYTE_SWAP ? {d_q, high_byte} : {high_byte, d_q};

    reg         ram_wr_en;
    reg  [9:0]  ram_wr_addr;
    reg  [15:0] ram_wr_data;

    always @(posedge pclk or negedge prst_n) begin
        if (!prst_n) begin
            ram_wr_en   <= 1'b0;
            ram_wr_addr <= 10'd0;
            ram_wr_data <= 16'd0;
        end else if (!cap_en_p || capture_done) begin
            ram_wr_en <= 1'b0;
        end else begin
            ram_wr_en <= wr_en_comb;
            if (wr_en_comb) begin
                ram_wr_addr <= wr_addr_comb;
                ram_wr_data <= wr_data_comb;
            end
        end
    end

    assign wr_addr = ram_wr_addr;
    assign wr_data = ram_wr_data;
    assign wr_en   = ram_wr_en;

    always @(posedge pclk or negedge prst_n) begin
        if (!prst_n) begin
            line_total <= 17'd0;
            byte_idx   <= 12'd0;
            pix_cnt    <= 11'd0;
            high_byte  <= 8'd0;
            line_full  <= 1'b0;
        end else if (!cap_en_p) begin
            line_total <= 17'd0;
            byte_idx   <= 12'd0;
            pix_cnt    <= 11'd0;
            high_byte  <= 8'd0;
            line_full  <= 1'b0;
        end else if (capture_done) begin
            // Freeze the accepted line; stop all capture counters.
            line_total <= 17'd0;
            byte_idx   <= 12'd0;
            pix_cnt    <= 11'd0;
            high_byte  <= 8'd0;
            line_full  <= 1'b0;
        end else if (first_cycle) begin
            line_total <= 17'd1;
            byte_idx   <= 12'd1;
            pix_cnt    <= 11'd0;
            high_byte  <= d_q;          // first active byte = high byte
            line_full  <= 1'b0;
        end else if (href_act) begin
            line_total <= line_total + 17'd1;
            byte_idx   <= byte_idx + 12'd1;
            if (in_window && !low_byte)
                high_byte <= d_q;
            if (wr_en_comb) begin
                pix_cnt <= pix_cnt + 11'd1;
                if (pix_cnt == (PIXELS - 1))
                    line_full <= 1'b1;
            end
        end else begin
            // HREF inactive; counters hold until the next first_cycle.
            line_total <= 17'd0;
            byte_idx   <= 12'd0;
            pix_cnt    <= 11'd0;
            high_byte  <= 8'd0;
            line_full  <= 1'b0;
        end
    end

    // ------------------------------------------------------------------
    // Line acceptance: length filter + startup-line count
    // ------------------------------------------------------------------
    always @(posedge pclk or negedge prst_n) begin
        if (!prst_n) begin
            accepted_cnt <= 16'd0;
            capture_done <= 1'b0;
            line_bytes   <= 16'd0;
            lines_seen   <= 16'd0;
            line_total_dbg <= 16'd0;
        end else if (!cap_en_p) begin
            accepted_cnt <= 16'd0;
            capture_done <= 1'b0;
            line_bytes   <= 16'd0;
            lines_seen   <= 16'd0;
            line_total_dbg <= 16'd0;
        end else if (href_fall && !capture_done) begin
            line_total_dbg <= line_total[15:0];
            if (line_full &&
                (line_total >= LINE_MIN) &&
                (line_total <= LINE_MAX)) begin
                accepted_cnt <= accepted_cnt + 16'd1;
                if ((accepted_cnt + 16'd1) >= STARTUP_LINES) begin
                    capture_done <= 1'b1;
                    line_bytes   <= line_total[15:0];
                    lines_seen   <= accepted_cnt + 16'd1;
                end
            end
        end
    end

    // ------------------------------------------------------------------
    // No-valid-line timeout
    // ------------------------------------------------------------------
    reg [31:0] timeout_cnt;

    always @(posedge pclk or negedge prst_n) begin
        if (!prst_n) begin
            timeout_cnt   <= 32'd0;
            capture_error <= 1'b0;
        end else if (!cap_en_p) begin
            timeout_cnt   <= 32'd0;
            capture_error <= 1'b0;
        end else if (!capture_done) begin
            if (timeout_cnt >= (TIMEOUT_CYCLES - 1))
                capture_error <= 1'b1;
            else
                timeout_cnt <= timeout_cnt + 32'd1;
        end
    end

    // ------------------------------------------------------------------
    // Debug state (shown on LEDs / used by the TB)
    // ------------------------------------------------------------------
    always @(posedge pclk or negedge prst_n) begin
        if (!prst_n)
            dbg_state <= 8'h00;
        else begin
            dbg_state <= {
                3'b000,
                vsync_q,
                capture_done,
                capture_error,
                line_full,
                href_act
            };
        end
    end

endmodule
