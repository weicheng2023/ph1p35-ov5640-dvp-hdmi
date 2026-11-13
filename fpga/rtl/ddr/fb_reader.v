// ============================================================================
// fb_reader.v
//
// Native-paxi frame reader with two modes:
//
//   mode=0 (VERIFY):
//     Read all 38400 beats once. Unpack 8 pixels/beat, compare each pixel
//     against the same fb_pattern used by the writer, record the first
//     error, and compute the CRC-32. verify_done/crc_ok are asserted at
//     the frame end. No FIFO is used in this mode.
//
//   mode=1 (DISPLAY):
//     Read beats continuously and push each 128-bit beat into the 128-bit
//     asynchronous FIFO. No per-pixel processing (the verification pass has
//     already proved the data). Only issue a read when the FIFO is not full;
//     one outstanding read. prefill_done is asserted after PREFILL_WORDS
//     beats have been written, so the pixel side can arm VSYNC-aligned video.
//
// Single-beat read: arvalid is held until arready; rready is asserted while
// waiting for rvalid; rlast is checked; one outstanding read only.
// ============================================================================
`timescale 1ns / 1ps

module fb_reader #(
    parameter integer ADDR_WIDTH    = 25,
    parameter integer BASE_ADDR     = 4096,
    parameter integer ADDR_STEP     = 8,
    parameter integer BEATS_PER_ROW = 80,
    parameter integer ROWS          = 480,
    parameter integer TOTAL_BEATS   = 38400,
    parameter integer PREFILL_WORDS = 192,
    parameter integer TIMEOUT       = 24_000_000
) (
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     start,
    input  wire                     mode,          // 0=verify, 1=display

    output reg  [ADDR_WIDTH-1:0]    paxi_araddr,
    output reg                      paxi_arvalid,
    input  wire                     paxi_arready,
    input  wire [127:0]             paxi_rdata,
    input  wire                     paxi_rlast,
    input  wire                     paxi_rvalid,
    output reg                      paxi_rready,

    // Display FIFO write side
    output reg                      fifo_wr_en,
    output reg  [127:0]             fifo_wr_data,
    input  wire                     fifo_wr_full,
    input  wire                     fifo_wr_overflow,

    // Status / verification
    output reg                      prefill_done,
    output reg                      verify_done,
    output reg                      crc_ok,
    output reg  [31:0]              crc_actual,
    input  wire [31:0]              crc_expected,

    output reg                      err_valid,
    output reg  [18:0]              err_pixel,
    output reg  [ADDR_WIDTH-1:0]    err_addr,
    output reg  [15:0]              err_exp,
    output reg  [15:0]              err_act,

    output reg                      error,
    output reg                      busy,
    output reg                      rlast_err
);

    localparam [2:0] ST_IDLE  = 3'd0,
                     ST_AR    = 3'd1,
                     ST_DATA  = 3'd2,
                     ST_PROC  = 3'd3,
                     ST_VDONE = 3'd4,
                     ST_DONE  = 3'd5,
                     ST_ERR   = 3'd6;

    localparam [31:0] CRC_INIT = 32'hFFFF_FFFF;
    localparam [ADDR_WIDTH-1:0] BASE = BASE_ADDR;

    reg [2:0]   state;
    reg [15:0]  beat_index;
    reg [8:0]   row;
    reg [6:0]   beat_col;
    reg [2:0]   pix_idx;
    reg [127:0] beat_data;
    reg [31:0]  crc;
    reg [31:0]  timeout_cnt;
    reg [15:0]  prefill_cnt;

    // Verify-mode expected pixel.
    wire [9:0] exp_x = ({beat_col, 3'b000} + {7'b0, pix_idx});
    wire [9:0] exp_y = {1'b0, row};
    wire [15:0] exp_pix;

    fb_pattern u_pat (
        .x      (exp_x),
        .y      (exp_y),
        .rgb565 (exp_pix)
    );

    // The read-side CRC is computed over the ACTUAL read pixels, so a
    // corrupted beat changes crc_actual; the expected CRC comes from the
    // writer's identical raster of the pattern.
    wire [15:0] act_pix = beat_data[16*pix_idx +: 16];

    wire [31:0] crc_next;
    crc32_16 u_crc (
        .crc_in  (crc),
        .data    (act_pix),
        .crc_out (crc_next)
    );
    wire [18:0] cur_pixel = {beat_index, 3'b000} + {16'b0, pix_idx};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= ST_IDLE;
            beat_index    <= 16'd0;
            row           <= 9'd0;
            beat_col      <= 7'd0;
            pix_idx       <= 3'd0;
            beat_data     <= 128'd0;
            crc           <= CRC_INIT;
            timeout_cnt   <= 32'd0;
            prefill_cnt   <= 16'd0;
            paxi_araddr   <= {ADDR_WIDTH{1'b0}};
            paxi_arvalid  <= 1'b0;
            paxi_rready   <= 1'b0;
            fifo_wr_en    <= 1'b0;
            fifo_wr_data  <= 128'd0;
            prefill_done  <= 1'b0;
            verify_done   <= 1'b0;
            crc_ok        <= 1'b0;
            crc_actual    <= 32'd0;
            err_valid     <= 1'b0;
            err_pixel     <= 19'd0;
            err_addr      <= {ADDR_WIDTH{1'b0}};
            err_exp       <= 16'd0;
            err_act       <= 16'd0;
            error         <= 1'b0;
            busy          <= 1'b0;
            rlast_err     <= 1'b0;
        end else begin
            case (state)
                ST_IDLE: begin
                    paxi_arvalid <= 1'b0;
                    paxi_rready  <= 1'b0;
                    fifo_wr_en   <= 1'b0;
                    verify_done  <= 1'b0;
                    crc_ok       <= 1'b0;
                    error        <= 1'b0;
                    busy         <= 1'b0;
                    if (start) begin
                        beat_index   <= 16'd0;
                        row          <= 9'd0;
                        beat_col     <= 7'd0;
                        pix_idx      <= 3'd0;
                        beat_data    <= 128'd0;
                        crc          <= CRC_INIT;
                        timeout_cnt  <= 32'd0;
                        prefill_cnt  <= 16'd0;
                        prefill_done <= 1'b0;
                        err_valid    <= 1'b0;
                        rlast_err    <= 1'b0;
                        crc_actual   <= 32'd0;
                        busy         <= 1'b1;
                        state        <= ST_AR;
                    end
                end

                ST_AR: begin
                    fifo_wr_en <= 1'b0;
                    // Display mode: do not issue a read unless the FIFO has
                    // room. Verify mode: no FIFO, issue immediately.
                    if ((mode == 1'b1) && fifo_wr_full) begin
                        timeout_cnt <= 32'd0;
                    end else begin
                        paxi_araddr  <= BASE + beat_index * ADDR_STEP;
                        paxi_arvalid <= 1'b1;
                        paxi_rready  <= 1'b1;
                        if (paxi_arvalid && paxi_arready) begin
                            paxi_arvalid <= 1'b0;
                            state        <= ST_DATA;
                            timeout_cnt  <= 32'd0;
                        end else begin
                            timeout_cnt <= timeout_cnt + 32'd1;
                            if (timeout_cnt >= TIMEOUT)
                                state <= ST_ERR;
                        end
                    end
                end

                ST_DATA: begin
                    paxi_rready <= 1'b1;
                    if (paxi_rvalid) begin
                        if (!paxi_rlast) begin
                            rlast_err <= 1'b1;
                            error     <= 1'b1;
                        end

                        beat_data <= paxi_rdata;
                        pix_idx   <= 3'd0;

                        if (mode == 1'b1) begin
                            // Display: push the whole beat, then next beat.
                            fifo_wr_en   <= 1'b1;
                            fifo_wr_data <= paxi_rdata;
                            if (prefill_cnt != PREFILL_WORDS)
                                prefill_cnt <= prefill_cnt + 16'd1;
                            if (prefill_cnt == (PREFILL_WORDS - 1))
                                prefill_done <= 1'b1;
                            paxi_rready  <= 1'b1;
                            timeout_cnt  <= 32'd0;

                            if (beat_index == (TOTAL_BEATS - 1)) begin
                                beat_index <= 16'd0;
                                row        <= 9'd0;
                                beat_col   <= 7'd0;
                            end else begin
                                beat_index <= beat_index + 16'd1;
                                if (beat_col == (BEATS_PER_ROW - 1)) begin
                                    beat_col <= 7'd0;
                                    row      <= row + 9'd1;
                                end else begin
                                    beat_col <= beat_col + 7'd1;
                                end
                            end
                            state <= ST_AR;
                        end else begin
                            // Verify: process 8 pixels, one per cycle.
                            state <= ST_PROC;
                        end
                        timeout_cnt <= 32'd0;
                    end else begin
                        timeout_cnt <= timeout_cnt + 32'd1;
                        if (timeout_cnt >= TIMEOUT)
                            state <= ST_ERR;
                    end
                end

                ST_PROC: begin
                    fifo_wr_en <= 1'b0;
                    // Compare the actual pixel with the expected pattern.
                    if (act_pix !== exp_pix) begin
                        if (!err_valid) begin
                            err_valid <= 1'b1;
                            err_pixel <= cur_pixel;
                            err_addr  <= BASE + beat_index * ADDR_STEP;
                            err_exp   <= exp_pix;
                            err_act   <= act_pix;
                        end
                    end
                    crc <= crc_next;

                    if (pix_idx == 3'd7) begin
                        pix_idx <= 3'd0;
                        if (beat_index == (TOTAL_BEATS - 1)) begin
                            crc_actual <= ~crc_next;
                            state      <= ST_VDONE;
                        end else begin
                            beat_index <= beat_index + 16'd1;
                            if (beat_col == (BEATS_PER_ROW - 1)) begin
                                beat_col <= 7'd0;
                                row      <= row + 9'd1;
                            end else begin
                                beat_col <= beat_col + 7'd1;
                            end
                            state <= ST_AR;
                        end
                    end else begin
                        pix_idx <= pix_idx + 3'd1;
                    end
                    timeout_cnt <= 32'd0;
                end

                ST_VDONE: begin
                    // Registered compare, so a first-error on the last pixel
                    // cannot race the CRC result.
                    crc_ok      <= (crc_actual == crc_expected) &&
                                   !err_valid && !rlast_err;
                    verify_done <= 1'b1;
                    busy        <= 1'b0;
                    state       <= ST_DONE;
                end

                ST_DONE: begin
                    paxi_arvalid <= 1'b0;
                    paxi_rready  <= 1'b0;
                    fifo_wr_en   <= 1'b0;
                    verify_done  <= 1'b1;
                    busy         <= 1'b0;

                    // The core re-uses the reader for the display mode after
                    // the verify pass, so a new start must re-arm the reader
                    // without leaving ST_DONE.
                    if (start) begin
                        beat_index   <= 16'd0;
                        row          <= 9'd0;
                        beat_col     <= 7'd0;
                        pix_idx      <= 3'd0;
                        beat_data    <= 128'd0;
                        crc          <= CRC_INIT;
                        timeout_cnt  <= 32'd0;
                        prefill_cnt  <= 16'd0;
                        prefill_done <= 1'b0;
                        verify_done  <= 1'b0;
                        crc_ok       <= 1'b0;
                        err_valid    <= 1'b0;
                        rlast_err    <= 1'b0;
                        crc_actual   <= 32'd0;
                        error        <= 1'b0;
                        busy         <= 1'b1;
                        state        <= ST_AR;
                    end
                end

                ST_ERR: begin
                    paxi_arvalid <= 1'b0;
                    paxi_rready  <= 1'b0;
                    fifo_wr_en   <= 1'b0;
                    error        <= 1'b1;
                    busy         <= 1'b0;
                end

                default: state <= ST_ERR;
            endcase

            if (fifo_wr_overflow)
                error <= 1'b1;
        end
    end

endmodule
