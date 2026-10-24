// ============================================================================
// top_led_test.v
// Diagnostic: drive all four user LEDs steady on.
// Use this to verify programming and LED pin mapping, independent of clock.
// ============================================================================
`timescale 1ns / 1ps

module top_led_test (
    output wire [3:0] led
);

    assign led = 4'b1111;

endmodule
