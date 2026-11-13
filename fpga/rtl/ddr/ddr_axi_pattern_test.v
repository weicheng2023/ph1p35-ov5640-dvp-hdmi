// ============================================================================
// ddr_axi_pattern_test.v
//
// Minimal native-paxi read/write pattern test for the PH1P35 DDR MC.
//
// The TD PH1P DDR wrapper exposes a *word-addressed* paxi_* port
// (AXI-like; no B response channel). This is the interface the vendor
// reference example drives. Full AXI4 (axi_* with ID/len/size/burst/B)
// is only available when MC0_MIS_AXI is defined; this test does not use it.
//   - paxi_awaddr/paxi_araddr are MC_ADDR_WIDTH bits (25 for 512Mb x16);
//   - each address unit is 16 bits; a 128-bit beat advances by 8 units;
//   - write: awvalid/awready + wdata/wstrb/wvalid/wlast/wready
//     (no B response channel);
//   - read : arvalid/arready + rdata/rlast/rvalid/rready.
//
// The test writes N known 128-bit patterns to BASE_ADDR + index*ADDR_STEP, then reads
// them back and compares. `pass` is asserted only if every beat matches.
//
// Clock/reset: run in the IP's dhi_clk domain; `start` must already be
// synchronized to this domain (the top synchronizes ddrphy_rdy).
// ============================================================================
`timescale 1ns / 1ps

module ddr_axi_pattern_test #(
    parameter integer ADDR_WIDTH    = 25,
    parameter integer DATA_WIDTH    = 128,
    parameter integer STRB_WIDTH    = 16,
    parameter integer N             = 16,
    parameter integer BASE_ADDR     = 0,
    parameter integer ADDR_STEP     = 8,
    parameter integer DRAIN_CYCLES  = 0,
    parameter integer TIMEOUT       = 24_000_000
) (
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     start,

    // Native PAXI master (16-bit addresses, 128-bit blocks)
    output reg  [ADDR_WIDTH-1:0]    paxi_awaddr,
    output reg                      paxi_awvalid,
    input  wire                     paxi_awready,
    output reg  [DATA_WIDTH-1:0]    paxi_wdata,
    output reg  [STRB_WIDTH-1:0]    paxi_wstrb,
    output reg                      paxi_wvalid,
    output reg                      paxi_wlast,
    input  wire                     paxi_wready,

    output reg  [ADDR_WIDTH-1:0]    paxi_araddr,
    output reg                      paxi_arvalid,
    input  wire                     paxi_arready,
    input  wire [DATA_WIDTH-1:0]    paxi_rdata,
    input  wire                     paxi_rlast,
    input  wire                     paxi_rvalid,
    output reg                      paxi_rready,

    // Results
    output reg                      done,
    output reg                      pass,
    output reg                      fail,
    output reg  [7:0]               err_cnt,

    // First error snapshot (for ChipWatcher / simulation)
    output reg  [ADDR_WIDTH-1:0]    err_addr,
    output reg  [DATA_WIDTH-1:0]    exp_data,
    output reg  [DATA_WIDTH-1:0]    act_data,
    output reg                      rlast_err
);

    localparam [2:0] ST_IDLE     = 3'd0,
                     ST_WR_AW    = 3'd1,
                     ST_WR_NEXT  = 3'd2,
                     ST_RD_AR    = 3'd3,
                     ST_RD_DATA  = 3'd4,
                     ST_DONE     = 3'd5,
                     ST_FAIL     = 3'd6,
                     ST_DRAIN    = 3'd7;

    localparam [ADDR_WIDTH-1:0] BASE = BASE_ADDR;

    reg [2:0]  state;
    reg [7:0]  idx;
    reg        aw_done;
    reg        w_done;
    reg        err_valid;
    reg [31:0] timeout_cnt;
    reg [31:0] drain_cnt;

    // Known pattern: four mixed 32-bit fields. Uses idx in every field so
    // address/data stuck-at or byte-lane errors are visible.
    function [DATA_WIDTH-1:0] pat;
        input [7:0] i;
        begin
            pat = {32'hA5A5_5A5A ^ {24'h0, i},
                   32'h0123_4567 + {24'h0, i},
                   32'hDEAD_BEEF ^ {24'h0, i},
                   32'h89AB_CDEF - {24'h0, i}};
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= ST_IDLE;
            idx           <= 8'd0;
            aw_done       <= 1'b0;
            w_done        <= 1'b0;
            timeout_cnt   <= 32'd0;
            done          <= 1'b0;
            pass          <= 1'b0;
            fail          <= 1'b0;
            err_cnt       <= 8'd0;
            err_valid     <= 1'b0;
            err_addr      <= {ADDR_WIDTH{1'b0}};
            exp_data      <= {DATA_WIDTH{1'b0}};
            act_data      <= {DATA_WIDTH{1'b0}};
            rlast_err     <= 1'b0;
            drain_cnt     <= 32'd0;
            paxi_awaddr   <= {ADDR_WIDTH{1'b0}};
            paxi_awvalid  <= 1'b0;
            paxi_wdata    <= {DATA_WIDTH{1'b0}};
            paxi_wstrb    <= {STRB_WIDTH{1'b0}};
            paxi_wvalid   <= 1'b0;
            paxi_wlast    <= 1'b0;
            paxi_araddr   <= {ADDR_WIDTH{1'b0}};
            paxi_arvalid  <= 1'b0;
            paxi_rready   <= 1'b0;
        end else if (state == ST_DONE || state == ST_FAIL) begin
            // Hold the result; stop all AXI activity.
            paxi_awvalid  <= 1'b0;
            paxi_wvalid   <= 1'b0;
            paxi_arvalid  <= 1'b0;
            paxi_rready   <= 1'b0;
            done          <= (state == ST_DONE);
            pass          <= (state == ST_DONE) && (err_cnt == 0) && !rlast_err;
            fail          <= (state == ST_FAIL) || (err_cnt != 0) || rlast_err;
        end else begin
            case (state)
                ST_IDLE: begin
                    // Do not watchdog while waiting for calibration.
                    paxi_awvalid <= 1'b0;
                    paxi_wvalid  <= 1'b0;
                    paxi_arvalid <= 1'b0;
                    paxi_rready  <= 1'b0;
                    idx          <= 8'd0;
                    aw_done      <= 1'b0;
                    w_done       <= 1'b0;
                    timeout_cnt  <= 32'd0;
                    if (start) begin
                        state        <= ST_WR_AW;
                        paxi_awaddr  <= BASE;
                        paxi_wdata   <= pat(8'd0);
                        paxi_wstrb   <= {STRB_WIDTH{1'b0}};
                        paxi_awvalid <= 1'b1;
                        paxi_wvalid  <= 1'b0;
                        paxi_wlast   <= 1'b1;
                    end
                end

                ST_WR_AW: begin
                    // Deassert each valid immediately after its handshake;
                    // the IP may keep ready high, so holding valid would
                    // start an unintended second beat.
                    if (paxi_awvalid && paxi_awready) begin
                        aw_done      <= 1'b1;
                        paxi_awvalid <= 1'b0;
                        // IPUG034: W is presented one cycle after accepted AW,
                        // within the two-cycle limit, regardless of WREADY.
                        paxi_wvalid  <= 1'b1;
                    end
                    if (paxi_wvalid && paxi_wready) begin
                        w_done      <= 1'b1;
                        paxi_wvalid <= 1'b0;
                    end
                    if (aw_done && w_done) begin
                        state       <= ST_WR_NEXT;
                        timeout_cnt <= 32'd0;
                    end else begin
                        timeout_cnt <= timeout_cnt + 32'd1;
                        if (timeout_cnt >= TIMEOUT)
                            state <= ST_FAIL;
                    end
                end

                ST_WR_NEXT: begin
                    aw_done <= 1'b0;
                    w_done  <= 1'b0;
                    if (idx == (N - 1)) begin
                        idx          <= 8'd0;
                        paxi_araddr  <= BASE;
                        paxi_arvalid <= (DRAIN_CYCLES > 0) ? 1'b0 : 1'b1;
                        paxi_rready  <= (DRAIN_CYCLES > 0) ? 1'b0 : 1'b1;
                        drain_cnt    <= 32'd0;
                        state        <= (DRAIN_CYCLES > 0) ? ST_DRAIN : ST_RD_AR;
                    end else begin
                        idx          <= idx + 8'd1;
                        paxi_awaddr  <= BASE + (idx + 1) * ADDR_STEP;
                        paxi_wdata   <= pat(idx + 8'd1);
                        paxi_wstrb   <= {STRB_WIDTH{1'b0}};
                        paxi_awvalid <= 1'b1;
                        paxi_wvalid  <= 1'b0;
                        paxi_wlast   <= 1'b1;
                        state        <= ST_WR_AW;
                    end
                    timeout_cnt <= 32'd0;
                end

                ST_DRAIN: begin
                    // Conservative drain only; it is NOT proof of physical
                    // write completion. The readback comparison is the proof.
                    if (drain_cnt >= (DRAIN_CYCLES - 1)) begin
                        paxi_araddr  <= BASE;
                        paxi_arvalid <= 1'b1;
                        paxi_rready  <= 1'b1;
                        state        <= ST_RD_AR;
                        drain_cnt    <= 32'd0;
                    end else begin
                        drain_cnt <= drain_cnt + 32'd1;
                    end
                end

                ST_RD_AR: begin
                    paxi_rready <= 1'b1;
                    if (paxi_arvalid && paxi_arready) begin
                        paxi_arvalid <= 1'b0;
                        state        <= ST_RD_DATA;
                        timeout_cnt  <= 32'd0;
                    end else begin
                        timeout_cnt <= timeout_cnt + 32'd1;
                        if (timeout_cnt >= TIMEOUT)
                            state <= ST_FAIL;
                    end
                end

                ST_RD_DATA: begin
                    paxi_rready <= 1'b1;
                    if (paxi_rvalid) begin
                        if (!paxi_rlast)
                            rlast_err <= 1'b1;

                        if (paxi_rdata !== pat(idx)) begin
                            err_cnt <= err_cnt + 8'd1;
                            if (!err_valid) begin
                                err_valid <= 1'b1;
                                err_addr  <= BASE + idx * ADDR_STEP;
                                exp_data  <= pat(idx);
                                act_data  <= paxi_rdata;
                            end
                        end

                        if (idx == (N - 1)) begin
                            state       <= ST_DONE;
                            paxi_rready <= 1'b0;
                        end else begin
                            idx          <= idx + 8'd1;
                            paxi_araddr  <= BASE + (idx + 1) * ADDR_STEP;
                            paxi_arvalid <= 1'b1;
                            state        <= ST_RD_AR;
                        end
                        timeout_cnt <= 32'd0;
                    end else begin
                        timeout_cnt <= timeout_cnt + 32'd1;
                        if (timeout_cnt >= TIMEOUT)
                            state <= ST_FAIL;
                    end
                end

                default: state <= ST_FAIL;
            endcase
        end
    end

endmodule
