// ============================================================================
// ov5640_id_reader.v
// Power-up sequence + OV5640 Chip ID read (0x300A/0x300B).
//
// Sequence:
//   1. PWDN=0, RESET=0 for PWRUP_CYCLES
//   2. RESET=1, wait RESET_WAIT_CYCLES
//   3. Read 0x300A (high byte)
//   4. Read 0x300B (low byte)
//   5. Compare with 0x56/0x40; retry after RETRY_CYCLES on failure
//
// Notes:
//   - This block does not drive PCLK/DVP data. It validates power, reset,
//     SCCB and the programming path only.
//   - The camera module has an onboard 24MHz oscillator; no FPGA XCLK output.
//   - SCCB's 9th bit is "don't care"; OV5640 may leave SDA high. ACK high is
//     therefore not treated as a fatal error. Chip ID match is the real check.
//   - link_ok means "a read transaction completed", not "ACK was low".
// ============================================================================
`timescale 1ns / 1ps

module ov5640_id_reader #(
    parameter integer PWRUP_CYCLES      = 500_000,   // 10 ms @50MHz
    parameter integer RESET_WAIT_CYCLES = 1_000_000, // 20 ms @50MHz
    parameter integer RETRY_CYCLES      = 50_000_000,// 1 s @50MHz
    parameter integer SCCB_TIMEOUT      = 200_000    // 4 ms @50MHz
) (
    input  wire        clk,
    input  wire        rst_n,

    output reg         cam_pwdn,
    output reg         cam_reset_n,

    output reg         sccb_start,
    output reg         sccb_rw,
    output reg  [15:0] sccb_reg,
    output reg  [7:0]  sccb_wdata,

    input  wire        sccb_busy,
    input  wire        sccb_done,
    input  wire        sccb_ack_error,
    input  wire [7:0]  sccb_rd_data,

    output reg  [7:0]  id_hi,
    output reg  [7:0]  id_lo,
    output reg         link_ok,
    output reg         id_match,
    output reg         id_error
);

    localparam [3:0] S_PWR      = 4'd0,
                     S_RELEASE  = 4'd1,
                     S_REQ_HI   = 4'd2,
                     S_WAIT_HI  = 4'd3,
                     S_REQ_LO   = 4'd4,
                     S_WAIT_LO  = 4'd5,
                     S_CHECK    = 4'd6,
                     S_OK       = 4'd7,
                     S_RETRY    = 4'd8;

    reg [3:0]  state;
    reg [31:0] delay_cnt;
    reg [31:0] timeout_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= S_PWR;
            delay_cnt    <= 32'd0;
            timeout_cnt  <= 32'd0;
            cam_pwdn     <= 1'b0;
            cam_reset_n  <= 1'b0;
            sccb_start   <= 1'b0;
            sccb_rw      <= 1'b1;
            sccb_reg     <= 16'h300A;
            sccb_wdata   <= 8'd0;
            id_hi        <= 8'd0;
            id_lo        <= 8'd0;
            link_ok      <= 1'b0;
            id_match     <= 1'b0;
            id_error     <= 1'b0;
        end else begin
            // start defaults low; pulse it only when needed
            sccb_start <= 1'b0;

            case (state)
                // ------------------------------------------------------------
                S_PWR: begin
                    cam_pwdn    <= 1'b0;
                    cam_reset_n <= 1'b0;
                    if (delay_cnt >= PWRUP_CYCLES - 1) begin
                        delay_cnt <= 32'd0;
                        state     <= S_RELEASE;
                    end else begin
                        delay_cnt <= delay_cnt + 32'd1;
                    end
                end

                // ------------------------------------------------------------
                S_RELEASE: begin
                    cam_reset_n <= 1'b1;
                    if (delay_cnt >= RESET_WAIT_CYCLES - 1) begin
                        delay_cnt <= 32'd0;
                        state     <= S_REQ_HI;
                    end else begin
                        delay_cnt <= delay_cnt + 32'd1;
                    end
                end

                // ------------------------------------------------------------
                S_REQ_HI: begin
                    timeout_cnt <= 32'd0;
                    id_error    <= 1'b0;
                    id_hi       <= 8'd0;
                    id_lo       <= 8'd0;
                    if (!sccb_busy && !sccb_done) begin
                        sccb_start <= 1'b1;
                        sccb_rw    <= 1'b1;
                        sccb_reg   <= 16'h300A;
                        sccb_wdata <= 8'd0;
                        state      <= S_WAIT_HI;
                    end
                end

                S_WAIT_HI: begin
                    timeout_cnt <= timeout_cnt + 32'd1;
                    if (sccb_done && sccb_busy) begin
                        // SCCB's 9th bit is "don't care"; do not abort on ACK high.
                        // Use the returned Chip ID as the real success criterion.
                        id_hi   <= sccb_rd_data;
                        link_ok <= 1'b1;
                        state   <= S_REQ_LO;
                    end else if (timeout_cnt >= SCCB_TIMEOUT) begin
                        id_error  <= 1'b1;
                        link_ok   <= 1'b0;
                        delay_cnt <= 32'd0;
                        state     <= S_RETRY;
                    end
                end

                // ------------------------------------------------------------
                S_REQ_LO: begin
                    timeout_cnt <= 32'd0;
                    if (!sccb_busy && !sccb_done) begin
                        sccb_start <= 1'b1;
                        sccb_rw    <= 1'b1;
                        sccb_reg   <= 16'h300B;
                        sccb_wdata <= 8'd0;
                        state      <= S_WAIT_LO;
                    end
                end

                S_WAIT_LO: begin
                    timeout_cnt <= timeout_cnt + 32'd1;
                    if (sccb_done && sccb_busy) begin
                        id_lo   <= sccb_rd_data;
                        link_ok <= 1'b1;
                        state   <= S_CHECK;
                    end else if (timeout_cnt >= SCCB_TIMEOUT) begin
                        id_error  <= 1'b1;
                        link_ok   <= 1'b0;
                        delay_cnt <= 32'd0;
                        state     <= S_RETRY;
                    end
                end

                // ------------------------------------------------------------
                S_CHECK: begin
                    link_ok  <= 1'b1;
                    id_error <= 1'b0;
                    if (id_hi == 8'h56 && id_lo == 8'h40) begin
                        id_match <= 1'b1;
                        state    <= S_OK;
                    end else begin
                        id_match  <= 1'b0;
                        delay_cnt <= 32'd0;
                        state     <= S_RETRY;
                    end
                end

                S_OK: begin
                    link_ok  <= 1'b1;
                    id_match <= 1'b1;
                end

                // ------------------------------------------------------------
                S_RETRY: begin
                    id_match <= 1'b0;
                    if (delay_cnt >= RETRY_CYCLES - 1) begin
                        delay_cnt <= 32'd0;
                        state     <= S_REQ_HI;
                    end else begin
                        delay_cnt <= delay_cnt + 32'd1;
                    end
                end

                default: state <= S_PWR;
            endcase
        end
    end

endmodule
