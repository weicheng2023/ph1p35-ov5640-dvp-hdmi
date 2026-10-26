// ============================================================================
// async_fifo_gray.v
// Dual-clock FIFO with Gray-coded pointers.
//
// Purpose:
//   Carry multi-bit events (and later pixel words) from the camera PCLK domain
//   to the 50 MHz system domain. Do not use a 2FF synchronizer on a multi-bit
//   bus: bits can arrive in different cycles and tear the value.
//
// Notes:
//   - First-word-fall-through read: rd_data is the current head and is valid
//     when rd_empty is low. Assert rd_en for one rd_clk cycle to pop.
//   - wr_full is conservative: it is based on a synchronized read pointer, so
//     it may assert slightly early. That is safe.
//   - wr_overflow is sticky until wr_rst_n. It means a write was attempted
//     while full and was dropped.
//   - Both sides must be reset together at power-up. If only one side is reset
//     while the other keeps running, the pointers can desynchronize.
//
// Reference: standard Cummings-style Gray-pointer asynchronous FIFO.
// ============================================================================
`timescale 1ns / 1ps

module async_fifo_gray #(
    parameter integer DATA_WIDTH = 64,
    parameter integer ADDR_WIDTH = 4          // depth = 2**ADDR_WIDTH
) (
    // Write domain
    input  wire                  wr_clk,
    input  wire                  wr_rst_n,
    input  wire                  wr_en,
    input  wire [DATA_WIDTH-1:0] wr_data,
    output wire                  wr_full,
    output reg                   wr_overflow,

    // Read domain
    input  wire                  rd_clk,
    input  wire                  rd_rst_n,
    input  wire                  rd_en,
    output wire [DATA_WIDTH-1:0] rd_data,
    output wire                  rd_empty
);

    localparam integer DEPTH = (1 << ADDR_WIDTH);
    localparam integer PTR_W = ADDR_WIDTH + 1;

    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    reg [PTR_W-1:0] wbin;
    reg [PTR_W-1:0] wgray;
    reg [PTR_W-1:0] rbin;
    reg [PTR_W-1:0] rgray;

    // Synchronizers. Attributes are hints; Anlogic TD may ignore them.
    (* ASYNC_REG = "TRUE" *) reg [PTR_W-1:0] wq1_rgray;
    (* ASYNC_REG = "TRUE" *) reg [PTR_W-1:0] wq2_rgray;
    (* ASYNC_REG = "TRUE" *) reg [PTR_W-1:0] rq1_wgray;
    (* ASYNC_REG = "TRUE" *) reg [PTR_W-1:0] rq2_wgray;

    wire winc = wr_en && !wr_full;
    wire rinc = rd_en && !rd_empty;

    wire [PTR_W-1:0] wbin_next  = wbin + {{(PTR_W-1){1'b0}}, winc};
    wire [PTR_W-1:0] wgray_next = (wbin_next >> 1) ^ wbin_next;
    wire [PTR_W-1:0] rbin_next  = rbin + {{(PTR_W-1){1'b0}}, rinc};
    wire [PTR_W-1:0] rgray_next = (rbin_next >> 1) ^ rbin_next;

    // Full when the next write Gray pointer equals the synchronized read
    // pointer with the two MSBs inverted.
    wire wr_full_val = (wgray_next ==
                        {~wq2_rgray[PTR_W-1:PTR_W-2], wq2_rgray[PTR_W-3:0]});
    wire rd_empty_val = (rgray_next == rq2_wgray);

    reg wr_full_r;
    reg rd_empty_r;

    assign wr_full  = wr_full_r;
    assign rd_empty = rd_empty_r;
    assign rd_data  = mem[rbin[ADDR_WIDTH-1:0]];

    // ------------------------------------------------------------------
    // Write pointer and full flag
    // ------------------------------------------------------------------
    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wbin      <= {PTR_W{1'b0}};
            wgray     <= {PTR_W{1'b0}};
            wr_full_r <= 1'b0;
        end else begin
            wbin      <= wbin_next;
            wgray     <= wgray_next;
            wr_full_r <= wr_full_val;
        end
    end

    // ------------------------------------------------------------------
    // Read pointer and empty flag
    // ------------------------------------------------------------------
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rbin       <= {PTR_W{1'b0}};
            rgray      <= {PTR_W{1'b0}};
            rd_empty_r <= 1'b1;
        end else begin
            rbin       <= rbin_next;
            rgray      <= rgray_next;
            rd_empty_r <= rd_empty_val;
        end
    end

    // ------------------------------------------------------------------
    // Pointer synchronization
    // ------------------------------------------------------------------
    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wq1_rgray <= {PTR_W{1'b0}};
            wq2_rgray <= {PTR_W{1'b0}};
        end else begin
            wq1_rgray <= rgray;
            wq2_rgray <= wq1_rgray;
        end
    end

    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rq1_wgray <= {PTR_W{1'b0}};
            rq2_wgray <= {PTR_W{1'b0}};
        end else begin
            rq1_wgray <= wgray;
            rq2_wgray <= rq1_wgray;
        end
    end

    // ------------------------------------------------------------------
    // Memory write (read is combinational, shown above)
    // ------------------------------------------------------------------
    always @(posedge wr_clk) begin
        if (winc) begin
            mem[wbin[ADDR_WIDTH-1:0]] <= wr_data;
        end
    end

    // ------------------------------------------------------------------
    // Sticky overflow flag
    // ------------------------------------------------------------------
    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wr_overflow <= 1'b0;
        end else if (wr_en && wr_full) begin
            wr_overflow <= 1'b1;
        end
    end

endmodule
