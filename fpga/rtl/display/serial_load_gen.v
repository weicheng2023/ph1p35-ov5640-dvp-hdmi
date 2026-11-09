// ============================================================================
// serial_load_gen.v
// Generate exactly one load pulse per pixel in the 5x serial clock domain.
//
// pixel_clk and serial_clk come from the same PLL (serial = 5 x pixel).
// A toggle in the pixel domain is re-synchronised into the serial domain;
// the toggle edge detector produces one pulse per pixel. The pulse is
// delayed by two serial cycles so the pixel data (registered on pixel_clk)
// is stable before the serial shift registers load it.
//
// All four TMDS lanes share this one load pulse, so they stay phase-aligned.
// ============================================================================
`timescale 1ns / 1ps

module serial_load_gen (
    input  wire pixel_clk,
    input  wire serial_clk,
    input  wire rst,        // active high
    output reg  load        // one serial_clk pulse per pixel
);

    reg pix_toggle;
    reg t1, t2;
    reg edge_d1, edge_d2;

    always @(posedge pixel_clk or posedge rst) begin
        if (rst)
            pix_toggle <= 1'b0;
        else
            pix_toggle <= ~pix_toggle;
    end

    always @(posedge serial_clk or posedge rst) begin
        if (rst) begin
            t1      <= 1'b0;
            t2      <= 1'b0;
            edge_d1 <= 1'b0;
            edge_d2 <= 1'b0;
            load    <= 1'b0;
        end else begin
            t1      <= pix_toggle;
            t2      <= t1;
            edge_d1 <= t1 ^ t2;
            edge_d2 <= edge_d1;
            load    <= edge_d2;
        end
    end

endmodule
