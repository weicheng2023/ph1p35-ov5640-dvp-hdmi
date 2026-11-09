// ============================================================================
// video_timing.v
// 640x480 pixel timing generator (59.981 Hz with the 25.0 MHz pixel clock).
//
//   Pixel clock : 25.0 MHz  (800 x 521 x 59.981 Hz)
//   H: active 640, front porch 16, sync 96, back porch 48, total 800
//   V: active 480, front porch 10, sync  2, back porch 29, total 521
//   HSYNC / VSYNC are ACTIVE LOW.
//
// Why V total 521 instead of the DMT 525:
//   The PH1P PLL cleanly locks 25.0 MHz (and 125 MHz serial), not 25.2 MHz.
//   25.0e6 / (800*525) = 59.524 Hz, which is outside the usual +/-0.5%
//   VESA window. Reducing the vertical back porch from 33 to 29 gives
//   25.0e6 / (800*521) = 59.981 Hz, within 0.03% of 60 Hz. Active video,
//   sync widths and sync positions are unchanged; only the post-sync
//   blanking is 4 lines shorter. This is a deliberate, documented tradeoff.
//
// Counters run continuously. de/hs/vs are combinational decodes of the
// counters, so they are aligned with hcount/vcount in the same pixel cycle.
//
// This module has no dependency on the camera, DVP, DDR or any vendor IP.
// ============================================================================
`timescale 1ns / 1ps

module video_timing #(
    parameter integer H_ACTIVE = 640,
    parameter integer H_FP     = 16,
    parameter integer H_SYNC   = 96,
    parameter integer H_BP     = 48,
    parameter integer V_ACTIVE = 480,
    parameter integer V_FP     = 10,
    parameter integer V_SYNC   = 2,
    parameter integer V_BP     = 29
) (
    input  wire       pixel_clk,
    input  wire       rst,        // active high, synchronous to pixel_clk
    output reg  [9:0] hcount,
    output reg  [9:0] vcount,
    output wire       de,         // active video
    output wire       hs,         // horizontal sync, active low
    output wire       vs          // vertical sync, active low
);

    localparam integer H_TOTAL = H_ACTIVE + H_FP + H_SYNC + H_BP; // 800
    localparam integer V_TOTAL = V_ACTIVE + V_FP + V_SYNC + V_BP; // 521

    always @(posedge pixel_clk or posedge rst) begin
        if (rst) begin
            hcount <= 10'd0;
            vcount <= 10'd0;
        end else if (hcount == (H_TOTAL - 1)) begin
            hcount <= 10'd0;
            if (vcount == (V_TOTAL - 1))
                vcount <= 10'd0;
            else
                vcount <= vcount + 10'd1;
        end else begin
            hcount <= hcount + 10'd1;
        end
    end

    assign de = (hcount < H_ACTIVE) && (vcount < V_ACTIVE);

    assign hs = ~((hcount >= (H_ACTIVE + H_FP)) &&
                  (hcount <  (H_ACTIVE + H_FP + H_SYNC)));

    assign vs = ~((vcount >= (V_ACTIVE + V_FP)) &&
                  (vcount <  (V_ACTIVE + V_FP + V_SYNC)));

endmodule
