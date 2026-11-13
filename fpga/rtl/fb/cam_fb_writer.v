// ============================================================================
// cam_fb_writer.v
//
// Stage 3 DDR writer: consumes 129-bit camera beats from the PCLK -> DDR
// asynchronous FIFO and writes one complete 640x480 RGB565 frame per header
// into the ping-pong frame buffer.
//
// Native PAXI contract (unchanged from the Stage 2 board-proven design):
//   - address unit is a 16-bit word; a 128-bit beat advances ADDR_STEP = 8;
//   - write mask is ACTIVE HIGH: 16'h0000 writes every byte;
//   - AW is accepted first; WVALID is presented one cycle later and held
//     until WREADY; the next beat starts only after both handshakes;
//   - single-beat transfers, wlast = 1, no B channel.
//
// Ping-pong:
//   BASE_ADDR + wr_idx * FRAME_STRIDE
//   frame 0 at 4096, frame 1 at 4096 + 307200 = 311296 (word addresses).
//
// The frame header is only accepted while `buf_free` is high. `buf_free` is
// computed in the same clock domain from wr_idx and the display reader index,
// so the writer never starts a frame in the buffer the display is reading.
// `frame_done` is a one-cycle pulse carrying the completed buffer index.
//
// This module does not claim physical DRAM commit: the display image and the
// ModelSim readback are the evidence.
// ============================================================================
`timescale 1ns / 1ps

module cam_fb_writer #(
    parameter integer ADDR_WIDTH    = 25,
    parameter integer BASE_ADDR     = 4096,
    parameter integer FRAME_STRIDE  = 307200,   // 38400 beats * 8 words
    parameter integer ADDR_STEP     = 8,
    parameter integer TOTAL_BEATS   = 38400,
    parameter integer TIMEOUT       = 24_000_000
) (
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     run,          // level: self-check passed

    input  wire [128:0]             fifo_rd_data, // first word fall through
    input  wire                     fifo_rd_empty,
    output reg                      fifo_rd_en,

    input  wire                     buf_free,

    output reg  [ADDR_WIDTH-1:0]    paxi_awaddr,
    output reg                      paxi_awvalid,
    input  wire                     paxi_awready,
    output reg  [127:0]             paxi_wdata,
    output reg  [15:0]              paxi_wstrb,
    output reg                      paxi_wvalid,
    output reg                      paxi_wlast,
    input  wire                     paxi_wready,

    output reg                      frame_done,   // one-cycle pulse
    output reg  [0:0]               frame_done_idx,
    output reg  [0:0]               wr_idx,       // next buffer to write
    output reg                      busy,
    output reg                      error,
    output reg  [15:0]              beats_dbg
);

    localparam [2:0] W_IDLE  = 3'd0,
                     W_GET   = 3'd1,
                     W_SETUP = 3'd2,
                     W_WR    = 3'd3,
                     W_NEXT  = 3'd4,
                     W_ERR   = 3'd5,
                     W_HDR   = 3'd6;

    reg [2:0]        state;
    reg [ADDR_WIDTH-1:0] base;
    reg [15:0]       beats;
    reg [127:0]      data_q;
    reg              aw_done;
    reg              w_done;
    reg [31:0]       timeout_cnt;
    reg              stray_data;

    wire [ADDR_WIDTH-1:0] cur_addr = base + beats * ADDR_STEP;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= W_IDLE;
            base           <= {ADDR_WIDTH{1'b0}};
            beats          <= 16'd0;
            data_q         <= 128'd0;
            aw_done        <= 1'b0;
            w_done         <= 1'b0;
            timeout_cnt    <= 32'd0;
            stray_data     <= 1'b0;
            paxi_awaddr    <= {ADDR_WIDTH{1'b0}};
            paxi_awvalid   <= 1'b0;
            paxi_wdata     <= 128'd0;
            paxi_wstrb     <= 16'd0;
            paxi_wvalid    <= 1'b0;
            paxi_wlast     <= 1'b0;
            frame_done     <= 1'b0;
            frame_done_idx <= 1'b0;
            wr_idx         <= 1'b1;      // first frame goes to buffer 1
            busy           <= 1'b0;
            error          <= 1'b0;
            beats_dbg      <= 16'd0;
            fifo_rd_en     <= 1'b0;
        end else begin
            fifo_rd_en <= 1'b0;
            frame_done <= 1'b0;

            if (!run) begin
                paxi_awvalid <= 1'b0;
                paxi_wvalid  <= 1'b0;
                busy         <= 1'b0;
                state        <= W_IDLE;
            end else begin
                case (state)
                    W_IDLE: begin
                        paxi_awvalid <= 1'b0;
                        paxi_wvalid  <= 1'b0;
                        busy         <= 1'b0;
                        if (!fifo_rd_empty) begin
                            if (fifo_rd_data[128]) begin
                                // Frame header. Only start when the display
                                // is not using the target buffer.
                                if (buf_free) begin
                                    fifo_rd_en <= 1'b1;      // pop header
                                    base       <= BASE_ADDR + wr_idx * FRAME_STRIDE;
                                    beats      <= 16'd0;
                                    beats_dbg  <= 16'd0;
                                    busy       <= 1'b1;
                                    timeout_cnt<= 32'd0;
                                    // The pop takes effect on the next clock;
                                    // wait one cycle so W_GET sees the first
                                    // data word, not the header again.
                                    state      <= W_HDR;
                                end
                            end else begin
                                // Data word outside a frame: discard and flag.
                                fifo_rd_en <= 1'b1;
                                stray_data <= 1'b1;
                                error      <= 1'b1;
                            end
                        end
                    end

                    W_HDR: begin
                        // One-cycle settle after the registered header pop.
                        state <= W_GET;
                    end

                    W_GET: begin
                        if (!fifo_rd_empty) begin
                            if (fifo_rd_data[128]) begin
                                // Header inside a frame: the beat protocol is
                                // broken. Stop rather than write garbage.
                                error <= 1'b1;
                                state <= W_ERR;
                            end else begin
                                data_q     <= fifo_rd_data;
                                fifo_rd_en <= 1'b1;
                                state      <= W_SETUP;
                            end
                        end else begin
                            timeout_cnt <= timeout_cnt + 32'd1;
                            if (timeout_cnt >= TIMEOUT) begin
                                error <= 1'b1;
                                state <= W_ERR;
                            end
                        end
                    end

                    W_SETUP: begin
                        paxi_awaddr  <= cur_addr;
                        paxi_wdata   <= data_q;
                        paxi_wstrb   <= 16'h0000;  // active-high mask: write all
                        paxi_wlast   <= 1'b1;
                        paxi_awvalid <= 1'b1;
                        paxi_wvalid  <= 1'b0;
                        aw_done      <= 1'b0;
                        w_done       <= 1'b0;
                        timeout_cnt  <= 32'd0;
                        state        <= W_WR;
                    end

                    W_WR: begin
                        if (paxi_awvalid && paxi_awready) begin
                            aw_done      <= 1'b1;
                            paxi_awvalid <= 1'b0;
                            paxi_wvalid  <= 1'b1;   // one cycle after AW
                        end
                        if (paxi_wvalid && paxi_wready) begin
                            w_done      <= 1'b1;
                            paxi_wvalid <= 1'b0;
                        end

                        if (aw_done && w_done) begin
                            timeout_cnt <= 32'd0;
                            state       <= W_NEXT;
                        end else begin
                            timeout_cnt <= timeout_cnt + 32'd1;
                            if (timeout_cnt >= TIMEOUT) begin
                                error <= 1'b1;
                                state <= W_ERR;
                            end
                        end
                    end

                    W_NEXT: begin
                        aw_done <= 1'b0;
                        w_done  <= 1'b0;
                        if (beats == (TOTAL_BEATS - 1)) begin
                            // Frame complete: publish it and swap buffers.
                            frame_done     <= 1'b1;
                            frame_done_idx <= wr_idx;
                            wr_idx         <= ~wr_idx;
                            busy           <= 1'b0;
                            beats_dbg      <= beats + 16'd1;
                            state          <= W_IDLE;
                        end else begin
                            beats     <= beats + 16'd1;
                            beats_dbg <= beats + 16'd1;
                            state     <= W_GET;
                        end
                    end

                    W_ERR: begin
                        paxi_awvalid <= 1'b0;
                        paxi_wvalid  <= 1'b0;
                        busy         <= 1'b0;
                        error        <= 1'b1;
                    end

                    default: begin
                        state <= W_ERR;
                    end
                endcase
            end
        end
    end

endmodule
