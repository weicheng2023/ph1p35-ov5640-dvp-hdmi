// ============================================================================
// ov5640_cfg.v
// OV5640 RGB565 configuration sequencer with readback verification.
//
// Sequence:
//   1. Wait for start (id_match from ov5640_id_reader).
//   2. Write every entry from ov5640_cfg_rom.
//      - 0x3008=0x82 triggers a 1 ms reset delay.
//   3. Read back key registers and compare:
//        fatal: 0x300A/0x300B, 0x4300, 0x4740, 0x3808..0x380B, 0x503D
//        stored, non-fatal: 0x3035, 0x3036, 0x3037, 0x3108
//   4. cfg_done=1; cfg_error is sticky.
//
// Notes:
//   - The table writes 0x4740=0x22 explicitly: PCLK and HREF active high,
//     VSYNC active low. This matches the 2026-10-26 LA capture. Do not rely on
//     the reset default 0x20 (which has HREF active low).
//   - The SCCB master re-latches reg/rw/data on every START, including the
//     repeated START of a read. This module holds them stable until the
//     transaction completes.
//   - SCCB's 9th bit is don't-care; readback values are the real check.
//   - H_PIX/V_PIX/H_TOTAL/V_TOTAL are parameters. They are NOT measured
//     values yet; readback and the logic analyzer must confirm them.
// ============================================================================
`timescale 1ns / 1ps

module ov5640_cfg #(
    parameter integer H_PIX              = 640,
    parameter integer V_PIX              = 480,
    parameter integer H_TOTAL            = 1600,
    parameter integer V_TOTAL            = 1000,
    parameter integer COLOR_BAR          = 0,
    parameter integer RESET_DELAY_CYCLES = 50_000,   // 1 ms @ 50 MHz
    parameter integer SCCB_TIMEOUT       = 200_000   // 4 ms @ 50 MHz
) (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        start,          // level; connect to id_match

    // SCCB master interface
    output reg         sccb_start,
    output reg         sccb_rw,
    output reg  [15:0] sccb_reg,
    output reg  [7:0]  sccb_wdata,
    input  wire        sccb_busy,
    input  wire        sccb_done,
    input  wire [7:0]  sccb_rd_data,

    // Status
    output reg         cfg_done,
    output reg         cfg_error,
    output reg  [7:0]  cfg_idx,

    // Readback values
    output reg  [7:0]  rb_id_hi,
    output reg  [7:0]  rb_id_lo,
    output reg  [7:0]  rb_4300,
    output reg  [7:0]  rb_4740,
    output reg  [7:0]  rb_503d,
    output reg  [12:0] rb_width,
    output reg  [12:0] rb_height,
    output reg  [7:0]  rb_3035,
    output reg  [7:0]  rb_3036,
    output reg  [7:0]  rb_3037,
    output reg  [7:0]  rb_3108
);

    localparam [3:0] S_IDLE    = 4'd0,
                     S_REQ     = 4'd1,
                     S_WAIT    = 4'd2,
                     S_NEXT    = 4'd3,
                     S_DELAY   = 4'd4,
                     S_RB_REQ  = 4'd5,
                     S_RB_WAIT = 4'd6,
                     S_RB_NEXT = 4'd7,
                     S_DONE    = 4'd8;

    localparam integer RB_LAST = 12;

    wire [12:0] h_pix = H_PIX;
    wire [12:0] v_pix = V_PIX;

    reg [3:0]  state;
    reg [3:0]  rb_idx;
    reg [31:0] delay_cnt;
    reg [31:0] timeout_cnt;

    // ------------------------------------------------------------------
    // Configuration ROM
    // ------------------------------------------------------------------
    wire [23:0] cfg_word;
    wire [15:0] cfg_reg  = cfg_word[23:8];
    wire [7:0]  cfg_data = cfg_word[7:0];

    ov5640_cfg_rom #(
        .H_PIX     (H_PIX),
        .V_PIX     (V_PIX),
        .H_TOTAL   (H_TOTAL),
        .V_TOTAL   (V_TOTAL),
        .COLOR_BAR (COLOR_BAR)
    ) u_rom (
        .idx  (cfg_idx),
        .word (cfg_word)
    );

    // ------------------------------------------------------------------
    // Readback address/expected value
    // ------------------------------------------------------------------
    reg [15:0] rb_addr;
    reg [7:0]  rb_expected;

    always @* begin
        case (rb_idx)
            4'd0:  begin rb_addr = 16'h300A; rb_expected = 8'h56; end
            4'd1:  begin rb_addr = 16'h300B; rb_expected = 8'h40; end
            4'd2:  begin rb_addr = 16'h4300; rb_expected = 8'h61; end
            4'd3:  begin rb_addr = 16'h4740; rb_expected = 8'h22; end
            4'd4:  begin rb_addr = 16'h3808; rb_expected = {4'd0, h_pix[11:8]}; end
            4'd5:  begin rb_addr = 16'h3809; rb_expected = h_pix[7:0]; end
            4'd6:  begin rb_addr = 16'h380A; rb_expected = {5'd0, v_pix[10:8]}; end
            4'd7:  begin rb_addr = 16'h380B; rb_expected = v_pix[7:0]; end
            4'd8:  begin rb_addr = 16'h503D; rb_expected = COLOR_BAR ? 8'h80 : 8'h00; end
            4'd9:  begin rb_addr = 16'h3035; rb_expected = 8'h11; end
            4'd10: begin rb_addr = 16'h3036; rb_expected = 8'h3C; end
            4'd11: begin rb_addr = 16'h3037; rb_expected = 8'h13; end
            4'd12: begin rb_addr = 16'h3108; rb_expected = 8'h01; end
            default: begin rb_addr = 16'h300A; rb_expected = 8'h00; end
        endcase
    end

    // ------------------------------------------------------------------
    // Sequencer
    // ------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= S_IDLE;
            cfg_idx      <= 8'd0;
            rb_idx       <= 4'd0;
            delay_cnt    <= 32'd0;
            timeout_cnt  <= 32'd0;
            sccb_start   <= 1'b0;
            sccb_rw      <= 1'b0;
            sccb_reg     <= 16'd0;
            sccb_wdata   <= 8'd0;
            cfg_done     <= 1'b0;
            cfg_error    <= 1'b0;
            rb_id_hi     <= 8'd0;
            rb_id_lo     <= 8'd0;
            rb_4300      <= 8'd0;
            rb_4740      <= 8'd0;
            rb_503d      <= 8'd0;
            rb_width     <= 13'd0;
            rb_height    <= 13'd0;
            rb_3035      <= 8'd0;
            rb_3036      <= 8'd0;
            rb_3037      <= 8'd0;
            rb_3108      <= 8'd0;
        end else begin
            sccb_start <= 1'b0;   // one-cycle pulse unless explicitly set

            case (state)
                // ----------------------------------------------------------
                S_IDLE: begin
                    if (start) begin
                        cfg_idx     <= 8'd0;
                        rb_idx      <= 4'd0;
                        cfg_error   <= 1'b0;
                        cfg_done    <= 1'b0;
                        timeout_cnt <= 32'd0;
                        state       <= S_REQ;
                    end
                end

                // ----------------------------------------------------------
                S_REQ: begin
                    if (cfg_word == 24'hFFFFFF) begin
                        rb_idx <= 4'd0;
                        state  <= S_RB_REQ;
                    end else if (!sccb_busy && !sccb_done) begin
                        sccb_reg   <= cfg_reg;
                        sccb_wdata <= cfg_data;
                        sccb_rw    <= 1'b0;
                        sccb_start <= 1'b1;
                        timeout_cnt <= 32'd0;
                        state      <= S_WAIT;
                    end
                end

                S_WAIT: begin
                    timeout_cnt <= timeout_cnt + 32'd1;
                    if (sccb_done && sccb_busy) begin
                        // SCCB's 9th bit is don't-care; readback is the check.
                        if ((cfg_reg == 16'h3008) && (cfg_data == 8'h82)) begin
                            delay_cnt <= 32'd0;
                            state     <= S_DELAY;
                        end else begin
                            cfg_idx <= cfg_idx + 8'd1;
                            state   <= S_NEXT;
                        end
                    end else if (timeout_cnt >= SCCB_TIMEOUT) begin
                        cfg_error <= 1'b1;
                        cfg_done  <= 1'b1;
                        state     <= S_DONE;
                    end
                end

                S_NEXT: begin
                    if (!sccb_busy && !sccb_done) state <= S_REQ;
                end

                S_DELAY: begin
                    if (delay_cnt >= (RESET_DELAY_CYCLES - 1)) begin
                        cfg_idx <= cfg_idx + 8'd1;
                        state   <= S_NEXT;
                    end else begin
                        delay_cnt <= delay_cnt + 32'd1;
                    end
                end

                // ----------------------------------------------------------
                S_RB_REQ: begin
                    if (!sccb_busy && !sccb_done) begin
                        sccb_reg   <= rb_addr;
                        sccb_rw    <= 1'b1;
                        sccb_start <= 1'b1;
                        timeout_cnt <= 32'd0;
                        state      <= S_RB_WAIT;
                    end
                end

                S_RB_WAIT: begin
                    timeout_cnt <= timeout_cnt + 32'd1;
                    if (sccb_done && sccb_busy) begin
                        case (rb_idx)
                            4'd0: begin
                                rb_id_hi <= sccb_rd_data;
                                if (sccb_rd_data != rb_expected) cfg_error <= 1'b1;
                            end
                            4'd1: begin
                                rb_id_lo <= sccb_rd_data;
                                if (sccb_rd_data != rb_expected) cfg_error <= 1'b1;
                            end
                            4'd2: begin
                                rb_4300 <= sccb_rd_data;
                                if (sccb_rd_data != rb_expected) cfg_error <= 1'b1;
                            end
                            4'd3: begin
                                rb_4740 <= sccb_rd_data;
                                if (sccb_rd_data != rb_expected) cfg_error <= 1'b1;
                            end
                            4'd4: begin
                                rb_width[12:8] <= {1'b0, sccb_rd_data[3:0]};
                                if (sccb_rd_data != rb_expected) cfg_error <= 1'b1;
                            end
                            4'd5: begin
                                rb_width[7:0] <= sccb_rd_data;
                                if (sccb_rd_data != rb_expected) cfg_error <= 1'b1;
                            end
                            4'd6: begin
                                rb_height[12:8] <= {2'b00, sccb_rd_data[2:0]};
                                if (sccb_rd_data != rb_expected) cfg_error <= 1'b1;
                            end
                            4'd7: begin
                                rb_height[7:0] <= sccb_rd_data;
                                if (sccb_rd_data != rb_expected) cfg_error <= 1'b1;
                            end
                            4'd8: begin
                                rb_503d <= sccb_rd_data;
                                if (sccb_rd_data != rb_expected) cfg_error <= 1'b1;
                            end
                            4'd9:  rb_3035 <= sccb_rd_data;  // non-fatal
                            4'd10: rb_3036 <= sccb_rd_data;  // non-fatal
                            4'd11: rb_3037 <= sccb_rd_data;  // non-fatal
                            4'd12: rb_3108 <= sccb_rd_data;  // non-fatal
                            default: ;
                        endcase

                        if (rb_idx == RB_LAST) begin
                            cfg_done <= 1'b1;
                            state    <= S_DONE;
                        end else begin
                            rb_idx <= rb_idx + 4'd1;
                            state  <= S_RB_NEXT;
                        end
                    end else if (timeout_cnt >= SCCB_TIMEOUT) begin
                        cfg_error <= 1'b1;
                        cfg_done  <= 1'b1;
                        state     <= S_DONE;
                    end
                end

                S_RB_NEXT: begin
                    if (!sccb_busy && !sccb_done) state <= S_RB_REQ;
                end

                S_DONE: begin
                    cfg_done <= 1'b1;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
