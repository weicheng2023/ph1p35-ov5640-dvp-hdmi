// ============================================================================
// fb_pattern.v
//
// Deterministic 640x480 RGB565 test image:
//   - 8 vertical bars, 80 px each:
//       white, yellow, cyan, green, magenta, red, blue, black
//   - 2-pixel white border
//   - 16x16 red/white checker marker at the top-left (inside the border)
//   - 1-pixel gray horizontal grid every 32 rows
//
// Priority: border > marker > grid > bar.
//
// The same function is used by the write side (expected data/CRC) and the
// read side (per-pixel expected comparison), so any mismatch is a real
// data/address error.
// ============================================================================
`timescale 1ns / 1ps

module fb_pattern (
    input  wire [9:0]  x,
    input  wire [9:0]  y,
    output reg  [15:0] rgb565
);

    localparam [15:0] C_WHITE   = 16'hFFFF;
    localparam [15:0] C_YELLOW  = 16'hFFE0;
    localparam [15:0] C_CYAN    = 16'h07FF;
    localparam [15:0] C_GREEN   = 16'h07E0;
    localparam [15:0] C_MAGENTA = 16'hF81F;
    localparam [15:0] C_RED     = 16'hF800;
    localparam [15:0] C_BLUE    = 16'h001F;
    localparam [15:0] C_BLACK   = 16'h0000;
    localparam [15:0] C_GRID    = 16'h8410;   // mid gray

    function [15:0] bar565;
        input [9:0] xx;
        begin
            if (xx < 10'd80)
                bar565 = C_WHITE;
            else if (xx < 10'd160)
                bar565 = C_YELLOW;
            else if (xx < 10'd240)
                bar565 = C_CYAN;
            else if (xx < 10'd320)
                bar565 = C_GREEN;
            else if (xx < 10'd400)
                bar565 = C_MAGENTA;
            else if (xx < 10'd480)
                bar565 = C_RED;
            else if (xx < 10'd560)
                bar565 = C_BLUE;
            else
                bar565 = C_BLACK;
        end
    endfunction

    always @* begin
        if (x < 10'd2 || x > 10'd637 || y < 10'd2 || y > 10'd477)
            rgb565 = C_WHITE;
        else if (x < 10'd18 && y < 10'd18)
            rgb565 = (x[0] ^ y[0]) ? C_RED : C_WHITE;
        else if (y[4:0] == 5'd0)
            rgb565 = C_GRID;
        else
            rgb565 = bar565(x);
    end

endmodule
