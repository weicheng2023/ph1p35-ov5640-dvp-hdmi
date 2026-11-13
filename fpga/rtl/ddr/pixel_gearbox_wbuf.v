// ============================================================================
// pixel_gearbox_wbuf.v
//
// Experimental variant of pixel_gearbox (see docs/display/ddr-framebuffer-
// bringup.md). Same 128-bit async FIFO, but every pixel now passes through
// two explicit register stages:
//
//   FIFO async head --(registered once per 8 pixels)--> word_buf (128 bits)
//   word_buf --8:1 mux--> pix565_r (16-bit pixel register)
//
// Motivation (test hypothesis, not a proven root cause):
//   In pixel_gearbox the FIFO head drives the 8:1 mux combinationally and the
//   selected RGB565 goes straight through RGB565->RGB888 into the TMDS
//   encoder registers in the same pixel clock cycle. This variant puts a
//   register on the FIFO read data (word_buf) and a register on the selected
//   pixel, so a FIFO read-pointer change or a RAM read-port change can never
//   reach the pixels being scanned out in the same cycle.
//
// Timing / handshake (FWFT FIFO, rd_data = current head):
//   - The word that word_buf holds is consumed over 8 active pixels.
//   - The consumed word is popped at pixel 6 (not pixel 7), because the FIFO
//     head only becomes the NEXT word after the pop edge. Pixel 7 still
//     reads the old word_buf, and at the pixel-7 edge word_buf captures
//     fifo_rd_data, which is then the next word. Pixels 0..7 of the next
//     group therefore all use the registered word.
//   - word_buf is primed during blanking (video_valid && !rd_empty) so the
//     first active pixel already has data.
//   - 640 active pixels/line = 80 groups of 8, so pix_idx is 0 at every
//     line start; there is no per-line resynchronisation.
//
// The output rgb565 is registered and one pixel later than de. The core
// delays DE/HS/VS by the matching number of stages before the TMDS encoder.
//
// Underflow is sticky and flagged whenever an active pixel is scanned with
// an empty FIFO (same meaning as pixel_gearbox).
// ============================================================================
`timescale 1ns / 1ps

module pixel_gearbox_wbuf (
    input  wire         pixel_clk,
    input  wire         rst_n,
    input  wire         video_valid,
    input  wire         de,
    input  wire [127:0] fifo_rd_data,
    input  wire         fifo_rd_empty,
    output wire         fifo_rd_en,
    output reg  [15:0]  rgb565,
    output reg          underflow
);

    reg [127:0] word_buf;
    reg [2:0]   pix_idx;
    reg         primed;

    // Pop the word being scanned at pixel 6. After this edge the FIFO head is
    // the next word, so the pixel-7 edge can latch it into word_buf.
    assign fifo_rd_en = rst_n && video_valid && de && !fifo_rd_empty &&
                        (pix_idx == 3'd6);

    always @(posedge pixel_clk or negedge rst_n) begin
        if (!rst_n) begin
            word_buf  <= 128'd0;
            pix_idx   <= 3'd0;
            primed    <= 1'b0;
            rgb565    <= 16'd0;
            underflow <= 1'b0;
        end else if (!primed) begin
            // Prime during blanking: latch the first head, do not pop it.
            if (video_valid && !fifo_rd_empty) begin
                word_buf <= fifo_rd_data;
                primed   <= 1'b1;
            end
        end else if (video_valid && de) begin
            // Registered pixel: always one word_buf/pix_idx combination.
            rgb565 <= word_buf[16*pix_idx +: 16];

            if (fifo_rd_empty)
                underflow <= 1'b1;

            if (pix_idx == 3'd7) begin
                pix_idx <= 3'd0;
                // Head is the next word (popped at pixel 6). If the FIFO ran
                // dry, keep the old word and rely on the sticky underflow.
                if (!fifo_rd_empty)
                    word_buf <= fifo_rd_data;
            end else begin
                pix_idx <= pix_idx + 3'd1;
            end
        end
    end

endmodule
