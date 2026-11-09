// ============================================================================
// line_buffer_dpram.v
// Dual-clock line buffer: one write port in the camera PCLK domain, one
// synchronous read port in the HDMI pixel-clock domain.
//
// 640 x 16 bit = 10,240 bit. TD should infer one 20K ERAM block. This is a
// true dual-port memory: the write and read clocks are asynchronous, and the
// top-level SDC groups cam_pclk separately from the HDMI clocks.
//
// The memory is intentionally not reset. The HDMI side must gate its output
// with a "capture done" flag so it never displays unwritten entries.
// ============================================================================
`timescale 1ns / 1ps

module line_buffer_dpram #(
    parameter integer ADDR_WIDTH = 10,
    parameter integer DATA_WIDTH = 16
) (
    // Write port (camera PCLK domain)
    input  wire                     wr_clk,
    input  wire                     wr_en,
    input  wire [ADDR_WIDTH-1:0]    wr_addr,
    input  wire [DATA_WIDTH-1:0]    wr_data,

    // Read port (HDMI pixel-clock domain)
    input  wire                     rd_clk,
    input  wire [ADDR_WIDTH-1:0]    rd_addr,
    output reg  [DATA_WIDTH-1:0]    rd_data
);

    reg [DATA_WIDTH-1:0] mem [0:(1 << ADDR_WIDTH) - 1];

    always @(posedge wr_clk) begin
        if (wr_en)
            mem[wr_addr] <= wr_data;
    end

    always @(posedge rd_clk) begin
        rd_data <= mem[rd_addr];
    end

endmodule
