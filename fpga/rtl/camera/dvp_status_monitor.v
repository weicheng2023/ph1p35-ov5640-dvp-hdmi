// ============================================================================
// dvp_status_monitor.v
// 50 MHz-domain consumer for dvp_capture event words.
//
// It drains the asynchronous event FIFO, checks frame/line ordering and line
// lengths, tracks min/max bytes per line, and produces sticky status bits for
// LEDs or a later debug channel.
//
// This module never samples PCLK, HREF or VSYNC directly. All camera timing
// information arrives through the FIFO as complete 64-bit events.
//
// Event word layout (see dvp_capture.v):
//   [63:56] tag (0xA5 line, 0x5A frame)
//   [55:40] frame_cnt
//   [39:24] line_cnt
//   [23:8]  pix_cnt
//   [7:0]   err_flags
// ============================================================================
`timescale 1ns / 1ps

module dvp_status_monitor #(
    parameter integer EXPECTED_PIX   = 0,
    parameter integer EXPECTED_LINES = 0
) (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [63:0] evt_data,
    input  wire        evt_empty,
    output wire        evt_rd_en,

    output reg  [15:0] frame_cnt,
    output reg  [15:0] line_cnt,
    output reg  [15:0] lines_in_frame,
    output reg  [15:0] pix_min,
    output reg  [15:0] pix_max,
    output reg         line_ok,
    output reg         frame_ok,
    output reg         err_sticky,
    output reg  [7:0]  last_err,
    output reg  [31:0] evt_count
);

    localparam [7:0] TAG_LINE  = 8'hA5;
    localparam [7:0] TAG_FRAME = 8'h5A;

    // First-word-fall-through FIFO: pop whenever an event is available.
    assign evt_rd_en = !evt_empty;

    wire [7:0]  evt_tag   = evt_data[63:56];
    wire [15:0] evt_frame = evt_data[55:40];
    wire [15:0] evt_line  = evt_data[39:24];
    wire [15:0] evt_pix   = evt_data[23:8];
    wire [7:0]  evt_err   = evt_data[7:0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            frame_cnt     <= 16'd0;
            line_cnt      <= 16'd0;
            lines_in_frame<= 16'd0;
            pix_min       <= 16'hFFFF;
            pix_max       <= 16'd0;
            line_ok       <= 1'b1;
            frame_ok      <= 1'b1;
            err_sticky    <= 1'b0;
            last_err      <= 8'h00;
            evt_count     <= 32'd0;
        end else if (!evt_empty) begin
            evt_count <= evt_count + 32'd1;
            last_err  <= evt_err;

            case (evt_tag)
                TAG_FRAME: begin
                    if (evt_frame != (frame_cnt + 16'd1)) begin
                        frame_ok <= 1'b0;
                    end
                    if ((frame_cnt != 16'd0) &&
                        (EXPECTED_LINES != 0) &&
                        (lines_in_frame != EXPECTED_LINES)) begin
                        frame_ok <= 1'b0;
                    end
                    if (evt_err != 8'h00) begin
                        frame_ok   <= 1'b0;
                        err_sticky <= 1'b1;
                    end
                    frame_cnt      <= evt_frame;
                    line_cnt       <= 16'd0;
                    lines_in_frame <= 16'd0;
                end

                TAG_LINE: begin
                    if (evt_frame != frame_cnt) begin
                        frame_ok <= 1'b0;
                    end
                    if (evt_line != line_cnt) begin
                        line_ok <= 1'b0;
                    end
                    if ((EXPECTED_PIX != 0) && (evt_pix != EXPECTED_PIX)) begin
                        line_ok <= 1'b0;
                    end
                    if (evt_err != 8'h00) begin
                        line_ok    <= 1'b0;
                        err_sticky <= 1'b1;
                    end
                    line_cnt       <= evt_line + 16'd1;
                    lines_in_frame <= lines_in_frame + 16'd1;
                    if (evt_pix < pix_min) pix_min <= evt_pix;
                    if (evt_pix > pix_max) pix_max <= evt_pix;
                end

                default: begin
                    line_ok    <= 1'b0;
                    frame_ok   <= 1'b0;
                    err_sticky <= 1'b1;
                end
            endcase
        end
    end

endmodule
