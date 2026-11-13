// ============================================================================
// cam_fb_reader.v
//
// Stage 3 DDR display reader:
//   - reads one complete 640x480 RGB565 frame (38400 beats) from the selected
//     ping-pong buffer, one outstanding single-beat read at a time;
//   - pushes each 128-bit beat into the 128-bit asynchronous display FIFO
//     (DDR user clock -> HDMI pixel clock);
//   - at the end of a pass it stops issuing reads and waits until the display
//     side has consumed every word (FIFO write-domain empty). At that point
//     the display has just consumed the last active pixel of its frame, so
//     the next pass starts in vertical blanking and the buffer index may be
//     switched there without tearing;
//   - `prefill_done` is asserted after PREFILL_WORDS words of the first pass,
//     which is what the HDMI side uses to arm VSYNC-aligned video.
//
// The ping-pong index itself is owned by cam_fb_hdmi_core; this module
// latches `pass_base` when a pass starts. `pass_done` is a one-cycle pulse.
// ============================================================================
`timescale 1ns / 1ps

module cam_fb_reader #(
    parameter integer ADDR_WIDTH    = 25,
    parameter integer ADDR_STEP     = 8,
    parameter integer TOTAL_BEATS   = 38400,
    parameter integer PREFILL_WORDS = 192,
    parameter integer TIMEOUT       = 24_000_000
) (
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     run,          // display has a complete frame

    input  wire [ADDR_WIDTH-1:0]    pass_base,    // latched at pass start
    input  wire                     fifo_wr_full,
    input  wire                     fifo_wr_empty,// write-side empty (drain)

    output reg  [ADDR_WIDTH-1:0]    paxi_araddr,
    output reg                      paxi_arvalid,
    input  wire                     paxi_arready,
    input  wire [127:0]             paxi_rdata,
    input  wire                     paxi_rlast,
    input  wire                     paxi_rvalid,
    output reg                      paxi_rready,

    output reg                      fifo_wr_en,
    output reg  [127:0]             fifo_wr_data,
    output reg                      prefill_done,
    output reg                      pass_done,    // one-cycle pulse
    output reg                      busy,
    output reg                      error,
    output reg  [15:0]              beats_dbg,
    output reg                      rlast_err
);

    localparam [2:0] R_WAIT  = 3'd0,
                     R_AR    = 3'd1,
                     R_DATA  = 3'd2,
                     R_DRAIN = 3'd3,
                     R_ERR   = 3'd4;

    reg [2:0]  state;
    reg [ADDR_WIDTH-1:0] base;
    reg [15:0] beat;
    reg [15:0] prefill_cnt;
    reg [31:0] timeout_cnt;
    // After a beat is accepted, its FIFO write is registered one cycle later
    // and the FIFO's registered full flag reflects it one cycle after that.
    // Hold off issuing the next read for two cycles so a new request can
    // never be in flight when the FIFO is really full (that would stall the
    // read while the PAXI bus is held, blocking the writer).
    reg [1:0]  push_hold;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= R_WAIT;
            base         <= {ADDR_WIDTH{1'b0}};
            beat         <= 16'd0;
            prefill_cnt  <= 16'd0;
            timeout_cnt  <= 32'd0;
            paxi_araddr  <= {ADDR_WIDTH{1'b0}};
            paxi_arvalid <= 1'b0;
            paxi_rready  <= 1'b0;
            fifo_wr_en   <= 1'b0;
            fifo_wr_data <= 128'd0;
            prefill_done <= 1'b0;
            pass_done    <= 1'b0;
            busy         <= 1'b0;
            error        <= 1'b0;
            beats_dbg    <= 16'd0;
            rlast_err    <= 1'b0;
            push_hold    <= 2'd0;
        end else begin
            fifo_wr_en <= 1'b0;
            pass_done  <= 1'b0;
            if (push_hold != 2'd0)
                push_hold <= push_hold - 2'd1;

            if (!run) begin
                paxi_arvalid <= 1'b0;
                paxi_rready  <= 1'b0;
                busy         <= 1'b0;
                state        <= R_WAIT;
            end else begin
                case (state)
                    R_WAIT: begin
                        // Start a pass. `pass_base` reflects the reader index
                        // for this pass (the core resolves a pending switch
                        // on the same cycle as pass_done).
                        base        <= pass_base;
                        beat        <= 16'd0;
                        beats_dbg   <= 16'd0;
                        timeout_cnt <= 32'd0;
                        busy        <= 1'b1;
                        state       <= R_AR;
                    end

                    R_AR: begin
                        fifo_wr_en <= 1'b0;
                        // Present a read only when the display FIFO has room
                        // and the previous write has fully taken effect.
                        // Once ARVALID is presented it is held until the
                        // handshake (PAXI: VALID must not be withdrawn).
                        if (!paxi_arvalid && !fifo_wr_full && (push_hold == 2'd0)) begin
                            paxi_araddr  <= base + beat * ADDR_STEP;
                            paxi_arvalid <= 1'b1;
                            paxi_rready  <= 1'b1;
                        end

                        if (paxi_arvalid && paxi_arready) begin
                            // Any accepted AR must be consumed, even if the
                            // FIFO filled while the request was pending.
                            paxi_arvalid <= 1'b0;
                            timeout_cnt  <= 32'd0;
                            state        <= R_DATA;
                        end else if (!paxi_arvalid && fifo_wr_full) begin
                            // Wait for display space (not an error).
                            timeout_cnt <= 32'd0;
                        end else begin
                            timeout_cnt <= timeout_cnt + 32'd1;
                            if (timeout_cnt >= TIMEOUT) begin
                                error <= 1'b1;
                                state <= R_ERR;
                            end
                        end
                    end

                    R_DATA: begin
                        // Do not accept a beat unless the FIFO can store it.
                        // rready may be held low; the read data stays valid.
                        paxi_rready <= !fifo_wr_full;
                        if (paxi_rvalid && paxi_rready) begin
                            fifo_wr_en   <= 1'b1;
                            fifo_wr_data <= paxi_rdata;
                            push_hold    <= 2'd2;

                            if (!paxi_rlast)
                                rlast_err <= 1'b1;

                            if (prefill_cnt != PREFILL_WORDS)
                                prefill_cnt <= prefill_cnt + 16'd1;
                            if (prefill_cnt == (PREFILL_WORDS - 1))
                                prefill_done <= 1'b1;

                            timeout_cnt <= 32'd0;
                            beats_dbg   <= beat + 16'd1;

                            if (beat == (TOTAL_BEATS - 1)) begin
                                beat        <= 16'd0;
                                paxi_rready <= 1'b0;
                                state       <= R_DRAIN;
                            end else begin
                                beat  <= beat + 16'd1;
                                state <= R_AR;
                            end
                        end else begin
                            timeout_cnt <= timeout_cnt + 32'd1;
                            if (timeout_cnt >= TIMEOUT) begin
                                error <= 1'b1;
                                state <= R_ERR;
                            end
                        end
                    end

                    R_DRAIN: begin
                        // The display has consumed the last word of the frame
                        // when the write side sees the FIFO empty. Only then
                        // does the next pass (and a buffer switch) start.
                        paxi_arvalid <= 1'b0;
                        paxi_rready  <= 1'b0;
                        if (fifo_wr_empty) begin
                            pass_done   <= 1'b1;
                            timeout_cnt <= 32'd0;
                            state       <= R_WAIT;
                        end else begin
                            timeout_cnt <= timeout_cnt + 32'd1;
                            if (timeout_cnt >= TIMEOUT) begin
                                // Display never drained (HDMI not running).
                                error <= 1'b1;
                                state <= R_ERR;
                            end
                        end
                    end

                    R_ERR: begin
                        paxi_arvalid <= 1'b0;
                        paxi_rready  <= 1'b0;
                        busy         <= 1'b0;
                        error        <= 1'b1;
                    end

                    default: state <= R_ERR;
                endcase
            end
        end
    end

endmodule
