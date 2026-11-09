// ============================================================================
// crc32_16.v
//
// One RGB565 pixel -> next CRC-32 state (combinational).
//
// CRC-32/ISO-HDLC (reflected polynomial 0xEDB88320):
//   init  = 0xFFFFFFFF
//   input = 16-bit pixel, LOW byte first, then HIGH byte
//   final = CRC XOR 0xFFFFFFFF
//
// The write image generator and the DDR readback use exactly this block,
// so the expected/actual CRC are comparable.
// ============================================================================
`timescale 1ns / 1ps

module crc32_16 (
    input  wire [31:0] crc_in,
    input  wire [15:0] data,
    output wire [31:0] crc_out
);

    function [31:0] crc32_byte;
        input [31:0] c;
        input [7:0]  d;
        integer i;
        reg [31:0] x;
        begin
            x = c;
            for (i = 0; i < 8; i = i + 1) begin
                if ((x[0] ^ d[i]) == 1'b1)
                    x = (x >> 1) ^ 32'hEDB8_8320;
                else
                    x = (x >> 1);
            end
            crc32_byte = x;
        end
    endfunction

    wire [31:0] c1 = crc32_byte(crc_in, data[7:0]);
    wire [31:0] c2 = crc32_byte(c1, data[15:8]);

    assign crc_out = c2;

endmodule
