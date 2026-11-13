// ============================================================================
// pixel_gearbox.v
//
// 128-bit FIFO word -> 8 x RGB565 pixels, in the HDMI pixel clock domain.
//
// Uses the async_fifo_gray first-word-fall-through read port:
//   - fifo_rd_data is the current head; valid when !fifo_rd_empty.
//   - The 8 pixels of one word are consumed over 8 active pixels.
//   - At the 8th pixel, fifo_rd_en pops the word; the next head is ready for
//     the next active pixel (the FIFO's head changes after the clock edge).
//
// Underflow is only flagged when video_valid && de && fifo_rd_empty. Before
// video_valid (initial prefill), an empty FIFO is NOT an error.
// ============================================================================
`timescale 1ns / 1ps

module pixel_gearbox (
    input  wire        pixel_clk,
    input  wire        rst_n,
    input  wire        video_valid,
    input  wire        de,
    input  wire [127:0] fifo_rd_data,
    input  wire        fifo_rd_empty,
    output wire        fifo_rd_en,
    output wire [15:0] rgb565,
    output reg         underflow
);

    reg [2:0] pix_idx;

    assign rgb565 = fifo_rd_data[16*pix_idx +: 16];
    // Pop on the SAME edge that consumes pixel 7. Registering this enable
    // delays the FIFO head by one pixel and repeats the previous word's pixel 0.
    assign fifo_rd_en = rst_n && video_valid && de && !fifo_rd_empty && (pix_idx == 3'd7);

    always @(posedge pixel_clk or negedge rst_n) begin
        if (!rst_n) begin
            pix_idx    <= 3'd0;
            underflow  <= 1'b0;
        end else begin
            if (video_valid && de) begin
                if (fifo_rd_empty) begin
                    underflow <= 1'b1;
                end else if (pix_idx == 3'd7) begin
                    pix_idx    <= 3'd0;
                end else begin
                    pix_idx <= pix_idx + 3'd1;
                end
            end
        end
    end

endmodule
