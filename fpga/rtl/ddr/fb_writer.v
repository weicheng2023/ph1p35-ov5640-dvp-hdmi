// ============================================================================
// fb_writer.v
//
// Deterministic 640x480 RGB565 frame writer for the PH1P35 native paxi.
//
//   8 pixels per beat, beat[15:0]=pixel0 ... beat[127:112]=pixel7
//   one beat per single-beat write, active-high mask=0x0000, wlast=1
//   AW and W are handled independently (each valid is held until its own
//   ready; the next beat starts only after both handshakes)
//   address = BASE_ADDR + beat_index * ADDR_STEP (16-bit address units)
//
// After all 38400 beats are accepted, a CRC-only raster pass recomputes the
// exact same image and emits crc_expected. write_done means "all beats
// accepted + expected CRC ready"; it is NOT a claim of physical DRAM commit.
// The readback comparison in fb_reader is the proof.
// ============================================================================
`timescale 1ns / 1ps

module fb_writer #(
    parameter integer ADDR_WIDTH    = 25,
    parameter integer BASE_ADDR     = 4096,
    parameter integer ADDR_STEP     = 8,
    parameter integer BEATS_PER_ROW = 80,
    parameter integer ROWS          = 480,
    parameter integer TOTAL_BEATS   = 38400,
    parameter integer TIMEOUT       = 24_000_000
) (
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     start,

    output reg  [ADDR_WIDTH-1:0]    paxi_awaddr,
    output reg                      paxi_awvalid,
    input  wire                     paxi_awready,
    output reg  [127:0]             paxi_wdata,
    output reg  [15:0]              paxi_wstrb,
    output reg                      paxi_wvalid,
    output reg                      paxi_wlast,
    input  wire                     paxi_wready,

    output reg                      write_done,
    output reg  [31:0]              crc_expected,
    output reg                      error
);

    localparam [2:0] ST_IDLE  = 3'd0,
                     ST_GEN   = 3'd1,
                     ST_SETUP = 3'd2,
                     ST_WR    = 3'd3,
                     ST_NEXT  = 3'd4,
                     ST_CRC   = 3'd5,
                     ST_DONE  = 3'd6,
                     ST_ERR   = 3'd7;

    localparam [31:0] CRC_INIT = 32'hFFFF_FFFF;
    localparam [ADDR_WIDTH-1:0] BASE = BASE_ADDR;

    reg [2:0]  state;
    reg [15:0] beat_index;
    reg [8:0]  row;
    reg [6:0]  beat_col;
    reg [2:0]  pix_idx;
    reg [127:0] beat_data;
    reg        aw_done;
    reg        w_done;
    reg [31:0] timeout_cnt;

    reg [31:0] crc;
    reg [9:0]  cx;
    reg [9:0]  cy;

    // Pattern x/y/pixel: GEN uses the beat/pixel counters, CRC uses raster.
    wire [9:0] pat_x = (state == ST_CRC) ? cx
                                         : ({beat_col, 3'b000} + {7'b0, pix_idx});
    wire [9:0] pat_y = (state == ST_CRC) ? cy : {1'b0, row};

    wire [15:0] pat_pix;
    fb_pattern u_pat (
        .x      (pat_x),
        .y      (pat_y),
        .rgb565 (pat_pix)
    );

    wire [31:0] crc_next;
    crc32_16 u_crc (
        .crc_in  (crc),
        .data    (pat_pix),
        .crc_out (crc_next)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= ST_IDLE;
            beat_index    <= 16'd0;
            row           <= 9'd0;
            beat_col      <= 7'd0;
            pix_idx       <= 3'd0;
            beat_data     <= 128'd0;
            aw_done       <= 1'b0;
            w_done        <= 1'b0;
            timeout_cnt   <= 32'd0;
            crc           <= CRC_INIT;
            cx            <= 10'd0;
            cy            <= 10'd0;
            paxi_awaddr   <= {ADDR_WIDTH{1'b0}};
            paxi_awvalid  <= 1'b0;
            paxi_wdata    <= 128'd0;
            paxi_wstrb    <= 16'd0;
            paxi_wvalid   <= 1'b0;
            paxi_wlast    <= 1'b0;
            write_done    <= 1'b0;
            crc_expected  <= 32'd0;
            error         <= 1'b0;
        end else begin
            case (state)
                ST_IDLE: begin
                    paxi_awvalid <= 1'b0;
                    paxi_wvalid  <= 1'b0;
                    paxi_wstrb   <= 16'd0;
                    paxi_wlast   <= 1'b0;
                    write_done   <= 1'b0;
                    error        <= 1'b0;
                    aw_done      <= 1'b0;
                    w_done       <= 1'b0;
                    timeout_cnt  <= 32'd0;
                    if (start) begin
                        beat_index <= 16'd0;
                        row        <= 9'd0;
                        beat_col   <= 7'd0;
                        pix_idx    <= 3'd0;
                        beat_data  <= 128'd0;
                        state      <= ST_GEN;
                    end
                end

                ST_GEN: begin
                    // Generate 8 pixels, one per cycle.
                    beat_data[16*pix_idx +: 16] <= pat_pix;
                    if (pix_idx == 3'd7) begin
                        pix_idx <= 3'd0;
                        state   <= ST_SETUP;
                    end else begin
                        pix_idx <= pix_idx + 3'd1;
                    end
                end

                ST_SETUP: begin
                    // Load data before AW; present W one cycle after AW accepts.
                    paxi_awaddr  <= BASE + beat_index * ADDR_STEP;
                    paxi_wdata   <= beat_data;
                    paxi_wstrb   <= 16'h0000;
                    paxi_wlast   <= 1'b1;
                    paxi_awvalid <= 1'b1;
                    paxi_wvalid  <= 1'b0;
                    aw_done      <= 1'b0;
                    w_done       <= 1'b0;
                    timeout_cnt  <= 32'd0;
                    state        <= ST_WR;
                end

                ST_WR: begin
                    // AW and W are independent; hold each until its ready.
                    if (paxi_awvalid && paxi_awready) begin
                        aw_done      <= 1'b1;
                        paxi_awvalid <= 1'b0;
                        paxi_wvalid  <= 1'b1;
                    end
                    if (paxi_wvalid && paxi_wready) begin
                        w_done      <= 1'b1;
                        paxi_wvalid <= 1'b0;
                    end

                    if (aw_done && w_done) begin
                        state       <= ST_NEXT;
                        timeout_cnt <= 32'd0;
                    end else begin
                        timeout_cnt <= timeout_cnt + 32'd1;
                        if (timeout_cnt >= TIMEOUT)
                            state <= ST_ERR;
                    end
                end

                ST_NEXT: begin
                    aw_done <= 1'b0;
                    w_done  <= 1'b0;
                    if (beat_index == (TOTAL_BEATS - 1)) begin
                        // All beats accepted; begin the CRC-only raster pass.
                        crc   <= CRC_INIT;
                        cx    <= 10'd0;
                        cy    <= 10'd0;
                        state <= ST_CRC;
                    end else begin
                        beat_index <= beat_index + 16'd1;
                        if (beat_col == (BEATS_PER_ROW - 1)) begin
                            beat_col <= 7'd0;
                            row      <= row + 9'd1;
                        end else begin
                            beat_col <= beat_col + 7'd1;
                        end
                        pix_idx  <= 3'd0;
                        beat_data <= 128'd0;
                        state    <= ST_GEN;
                    end
                end

                ST_CRC: begin
                    crc <= crc_next;
                    if (cx == 10'd639) begin
                        cx <= 10'd0;
                        if (cy == (ROWS - 1)) begin
                            crc_expected <= ~crc_next;
                            write_done   <= 1'b1;
                            state        <= ST_DONE;
                        end else begin
                            cy <= cy + 10'd1;
                        end
                    end else begin
                        cx <= cx + 10'd1;
                    end
                end

                ST_DONE: begin
                    paxi_awvalid <= 1'b0;
                    paxi_wvalid  <= 1'b0;
                    write_done   <= 1'b1;
                    state        <= ST_DONE;
                end

                ST_ERR: begin
                    paxi_awvalid <= 1'b0;
                    paxi_wvalid  <= 1'b0;
                    error        <= 1'b1;
                    state        <= ST_ERR;
                end

                default: state <= ST_ERR;
            endcase
        end
    end

endmodule
