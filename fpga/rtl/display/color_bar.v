// ============================================================================
// color_bar.v
// 8 vertical color bars for 640x480: each bar is 80 pixels wide.
//
//   bar 0 : white   0xFFFFFF
//   bar 1 : yellow  0xFFFF00
//   bar 2 : cyan    0x00FFFF
//   bar 3 : green   0x00FF00
//   bar 4 : magenta 0xFF00FF
//   bar 5 : red     0xFF0000
//   bar 6 : blue    0x0000FF
//   bar 7 : black   0x000000
//
// rgb is only meaningful when de=1. Outside active video the TMDS
// channels carry control codes, so rgb is forced to 0 there.
// ============================================================================
`timescale 1ns / 1ps

module color_bar (
    input  wire [9:0]  hcount,
    input  wire        de,
    output reg  [23:0] rgb
);

    always @(*) begin
        if (!de) begin
            rgb = 24'h000000;
        end else if (hcount < 10'd80) begin
            rgb = 24'hFFFFFF;   // white
        end else if (hcount < 10'd160) begin
            rgb = 24'hFFFF00;   // yellow
        end else if (hcount < 10'd240) begin
            rgb = 24'h00FFFF;   // cyan
        end else if (hcount < 10'd320) begin
            rgb = 24'h00FF00;   // green
        end else if (hcount < 10'd400) begin
            rgb = 24'hFF00FF;   // magenta
        end else if (hcount < 10'd480) begin
            rgb = 24'hFF0000;   // red
        end else if (hcount < 10'd560) begin
            rgb = 24'h0000FF;   // blue
        end else begin
            rgb = 24'h000000;   // black
        end
    end

endmodule
