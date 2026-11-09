// ============================================================================
// ddr_status_debug.v
//
// Debug-only status monitor for the PH1P35 DDR bring-up.
//
//   pll_lock : synchronized ddrphy_rst_n (IP reset released / PLL locked)
//   ready    : synchronized ddrphy_rdy   (initialization/calibration done)
//   timeout  : latched if ready is not high within TIMEOUT_CYCLES of
//              clk_50m after reset. The counter runs ONLY on clk_50m, so it
//              still works when the DDR user clock (dhi_clk) is stopped.
//
// The timeout is latched, so a late ready (LED3 on with LED4 on) is visible
// as "ready appeared only after the window", not hidden.
// ============================================================================
`timescale 1ns / 1ps

module ddr_status_debug #(
    parameter integer TIMEOUT_CYCLES = 50_000_000   // 1 s at 50 MHz
) (
    input  wire clk_50m,
    input  wire rst_n,
    input  wire ddrphy_rst_n,
    input  wire ddrphy_rdy,
    output wire pll_lock,
    output wire ready,
    output reg  timeout
);

    reg [1:0] pll_sync;
    reg [1:0] rdy_sync;
    reg [31:0] timeout_cnt;

    always @(posedge clk_50m or negedge rst_n) begin
        if (!rst_n) begin
            pll_sync    <= 2'b00;
            rdy_sync    <= 2'b00;
            timeout_cnt <= 32'd0;
            timeout     <= 1'b0;
        end else begin
            pll_sync <= {pll_sync[0], ddrphy_rst_n};
            rdy_sync <= {rdy_sync[0], ddrphy_rdy};

            if (!rdy_sync[1] && !timeout) begin
                if (timeout_cnt >= (TIMEOUT_CYCLES - 1)) begin
                    timeout     <= 1'b1;
                    timeout_cnt <= 32'd0;
                end else begin
                    timeout_cnt <= timeout_cnt + 32'd1;
                end
            end
        end
    end

    assign pll_lock = pll_sync[1];
    assign ready    = rdy_sync[1];

endmodule
