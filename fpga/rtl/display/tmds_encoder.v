// ============================================================================
// tmds_encoder.v
// DVI 1.0 / HDMI TMDS 8b/10b encoder (video data + control periods).
//
//   din[7:0] : pixel component (B on channel 0, G on channel 1, R on channel 2)
//   ctrl[1:0]: {c1,c0}; channel 0 uses {VSYNC,HSYNC}, channels 1/2 use 2'b00
//   de       : active video
//   dout[9:0]: TMDS character, dout[0] is transmitted FIRST
//
// Algorithm (DVI 1.0 section 3.2.3):
//   1) minimise transitions with XOR or XNOR coding
//   2) choose the final inversion from the running disparity
//
// Control characters (DE=0):
//   ctrl 00 -> 1101010100
//   ctrl 01 -> 0010101011
//   ctrl 10 -> 0101010100
//   ctrl 11 -> 1010101011
//
// This is a standard, open TMDS encoder. It contains no vendor IP.
// ============================================================================
`timescale 1ns / 1ps

module tmds_encoder (
    input  wire       clk,
    input  wire       rst,       // active high
    input  wire [7:0] din,
    input  wire [1:0] ctrl,
    input  wire       de,
    output reg  [9:0] dout       // dout[0] transmitted first
);

    // ------------------------------------------------------------------
    // Stage 0: number of ones in din
    // ------------------------------------------------------------------
    reg [3:0] n1d;

    always @(*) begin
        n1d = din[0] + din[1] + din[2] + din[3] +
              din[4] + din[5] + din[6] + din[7];
    end

    // ------------------------------------------------------------------
    // Stage 1: transition minimisation (XOR / XNOR)
    // q_m[8] = 0 for XNOR coding, 1 for XOR coding.
    // ------------------------------------------------------------------
    reg [8:0] q_m;

    always @(*) begin
        if ((n1d > 4'd4) || ((n1d == 4'd4) && (din[0] == 1'b0))) begin
            // XNOR path
            q_m[0] = din[0];
            q_m[1] = ~(q_m[0] ^ din[1]);
            q_m[2] = ~(q_m[1] ^ din[2]);
            q_m[3] = ~(q_m[2] ^ din[3]);
            q_m[4] = ~(q_m[3] ^ din[4]);
            q_m[5] = ~(q_m[4] ^ din[5]);
            q_m[6] = ~(q_m[5] ^ din[6]);
            q_m[7] = ~(q_m[6] ^ din[7]);
            q_m[8] = 1'b0;
        end else begin
            // XOR path
            q_m[0] = din[0];
            q_m[1] = q_m[0] ^ din[1];
            q_m[2] = q_m[1] ^ din[2];
            q_m[3] = q_m[2] ^ din[3];
            q_m[4] = q_m[3] ^ din[4];
            q_m[5] = q_m[4] ^ din[5];
            q_m[6] = q_m[5] ^ din[6];
            q_m[7] = q_m[6] ^ din[7];
            q_m[8] = 1'b1;
        end
    end

    // ------------------------------------------------------------------
    // Stage 2: ones/zeros in q_m[7:0]
    // ------------------------------------------------------------------
    reg [3:0] n1q_m;
    reg [3:0] n0q_m;

    always @(*) begin
        n1q_m = q_m[0] + q_m[1] + q_m[2] + q_m[3] +
                q_m[4] + q_m[5] + q_m[6] + q_m[7];
        n0q_m = 4'd8 - n1q_m;
    end

    // Signed disparity terms. n1q_m/n0q_m are 4-bit unsigned (0..8), so
    // extend to 5-bit signed before subtracting to avoid 4-bit wrap-around.
    wire signed [4:0] d_n1_minus_n0;
    wire signed [4:0] d_n0_minus_n1;
    wire signed [4:0] d_two_if_qm8;
    wire signed [4:0] d_two_if_not_qm8;

    assign d_n1_minus_n0     = $signed({1'b0, n1q_m}) - $signed({1'b0, n0q_m});
    assign d_n0_minus_n1     = -d_n1_minus_n0;
    assign d_two_if_qm8      = q_m[8]      ? 5'sd2 : 5'sd0;
    assign d_two_if_not_qm8  = (~q_m[8])   ? 5'sd2 : 5'sd0;

    // ------------------------------------------------------------------
    // Stage 3: running disparity / final inversion
    // ------------------------------------------------------------------
    reg signed [4:0] cnt;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            cnt  <= 5'sd0;
            dout <= 10'b1101010100;      // valid control character
        end else if (!de) begin
            cnt <= 5'sd0;
            case (ctrl)
                2'b00: dout <= 10'b1101010100;
                2'b01: dout <= 10'b0010101011;
                2'b10: dout <= 10'b0101010100;
                2'b11: dout <= 10'b1010101011;
            endcase
        end else if ((cnt == 5'sd0) || (n1q_m == n0q_m)) begin
            dout[9] <= ~q_m[8];
            dout[8] <=  q_m[8];
            if (q_m[8] == 1'b0) begin
                dout[7:0] <= ~q_m[7:0];
                cnt <= cnt + d_n0_minus_n1;
            end else begin
                dout[7:0] <= q_m[7:0];
                cnt <= cnt + d_n1_minus_n0;
            end
        end else if (((cnt > 5'sd0) && (n1q_m > n0q_m)) ||
                     ((cnt < 5'sd0) && (n0q_m > n1q_m))) begin
            dout[9]   <= 1'b1;
            dout[8]   <= q_m[8];
            dout[7:0] <= ~q_m[7:0];
            cnt <= cnt + d_two_if_qm8 + d_n0_minus_n1;
        end else begin
            dout[9]   <= 1'b0;
            dout[8]   <= q_m[8];
            dout[7:0] <= q_m[7:0];
            cnt <= cnt - d_two_if_not_qm8 + d_n1_minus_n0;
        end
    end

endmodule
