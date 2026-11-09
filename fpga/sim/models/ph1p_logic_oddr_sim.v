// ============================================================================
// ph1p_logic_oddr_sim.v  (SIMULATION ONLY)
// Behavioural model of the PH1P_LOGIC_ODDR primitive.
//
// The vendor simulation model is encrypted. This model reproduces the
// behaviour needed by tmds_serializer.v:
//   - both d0 and d1 are captured on the POSEDGE
//   - d0 is presented while clk is high, d1 while clk is low
// This is the standard DDR output-cell behaviour and matches the reference
// PH1P35 HDMI design's use of the primitive (one registered 2-bit pair
// drives both output phases).
//
// It does NOT model IO delays, jitter, drive strength or the differential
// N output. Those are validated by the TD build and board measurement.
// ============================================================================
`timescale 1ns / 1ps

module PH1P_LOGIC_ODDR (
    output wire q,
    input  wire clk,
    input  wire d1,     // data presented while clk is low
    input  wire d0,     // data presented while clk is high
    input  wire rst
);

    parameter ASYNCRST = "ENABLE";

    reg q_pos;
    reg q_neg;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            q_pos <= 1'b0;
            q_neg <= 1'b0;
        end else begin
            q_pos <= d0;
            q_neg <= d1;
        end
    end

    assign q = clk ? q_pos : q_neg;

endmodule
