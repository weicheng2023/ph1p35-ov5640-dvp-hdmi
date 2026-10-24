// ============================================================================
// top_sccb_pin_test.v
// Diagnostic: toggle SCL push-pull and SDA open-drain, independent of SCCB.
// Use a scope/logic analyzer on J2-32 (SCL) and J2-33 (SDA).
// ============================================================================
`timescale 1ns / 1ps

module top_sccb_pin_test (
    input  wire       clk_50m,
    output wire [3:0] led,
    output wire       cam_scl,
    inout  wire       cam_sda
);

    reg [31:0] cnt;

    initial cnt = 32'd0;

    always @(posedge clk_50m)
        cnt <= cnt + 32'd1;

    // ~1.5 kHz for easy probing: 50MHz / 2^15
    wire slow = cnt[14];

    // SCL push-pull square wave.
    assign cam_scl = slow;

    // SDA open-drain: drive low on one phase, release high on the other.
    assign cam_sda = slow ? 1'bz : 1'b0;

    // LED1 heartbeat, LED2/3 show the two phases, LED4 steady on.
    assign led[0] = cnt[24];
    assign led[1] = slow;
    assign led[2] = ~slow;
    assign led[3] = 1'b1;

endmodule
