// ============================================================================
// rgb565_to_rgb888.v
// RGB565 -> RGB888 expansion with bit replication:
//   R8 = {R5, R5[4:2]}
//   G8 = {G6, G6[5:4]}
//   B8 = {B5, B5[4:2]}
//
// RGB565 layout: [15:11] R, [10:5] G, [4:0] B.
// ============================================================================
`timescale 1ns / 1ps

module rgb565_to_rgb888 (
    input  wire [15:0] rgb565,
    output wire [23:0] rgb888
);

    wire [4:0] r5 = rgb565[15:11];
    wire [5:0] g6 = rgb565[10:5];
    wire [4:0] b5 = rgb565[4:0];

    assign rgb888 = {r5, r5[4:2], g6, g6[5:4], b5, b5[4:2]};

endmodule
