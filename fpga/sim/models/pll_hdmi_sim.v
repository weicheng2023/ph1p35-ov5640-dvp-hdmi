// ============================================================================
// pll_hdmi_sim.v  (SIMULATION ONLY)
// Behavioural replacement for fpga/rtl/display/pll_hdmi.v.
//
// Generates the same three ports as the synthesis PLL:
//   pixel_clk  = 25.0 MHz
//   serial_clk = 125.0 MHz  (5 x pixel_clk)
//   lock       = 0 for 10 us, then 1
//
// Both clocks are divided from one 1250 MHz behavioural VCO, so they are
// phase-aligned exactly as the real PLL outputs are. The vendor functional
// PLL model locks the same 25.0/125 MHz configuration at about 120 us.
// This model does NOT validate the real PLL's loop filter, jitter or
// lock behaviour; those are checked by the TD build, the vendor model and
// the board LED2.
// ============================================================================
`timescale 1ns / 1fs

module pll_hdmi (
    input  wire clk_50m,
    output wire pixel_clk,
    output wire serial_clk,
    output wire lock
);

    reg vco;
    initial vco = 1'b0;
    always #0.400 vco = ~vco;         // 1250 MHz

    reg [2:0] div5;                    // 0..4  -> toggle = 125 MHz
    reg [4:0] div25;                   // 0..24 -> toggle = 25 MHz
    reg pixel_r;
    reg serial_r;
    reg lock_r;

    initial begin
        div5     = 3'd0;
        div25    = 5'd0;
        pixel_r  = 1'b0;
        serial_r = 1'b0;
        lock_r   = 1'b0;
    end

    always @(posedge vco) begin
        if (div5 == 3'd4) begin
            div5     <= 3'd0;
            serial_r <= ~serial_r;
        end else begin
            div5 <= div5 + 3'd1;
        end

        if (div25 == 5'd24) begin
            div25   <= 5'd0;
            pixel_r <= ~pixel_r;
        end else begin
            div25 <= div25 + 5'd1;
        end
    end

    initial begin
        #10000;
        lock_r = 1'b1;
    end

    assign pixel_clk  = pixel_r;
    assign serial_clk = serial_r;
    assign lock       = lock_r;

endmodule
