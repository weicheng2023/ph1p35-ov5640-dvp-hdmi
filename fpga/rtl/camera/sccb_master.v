// ============================================================================
// sccb_master.v
// Minimal SCCB master (I2C-compatible) for OV5640 register access.
//
// Write: START, dev+W, reg_hi, reg_lo, data, STOP
// Read : START, dev+W, reg_hi, reg_lo, STOP, START, dev+R, data, NA, STOP
//
// Notes:
//   - 4 phases per SCL period; DIV is the quarter-period divider.
//   - DIV=125 @50MHz -> 100kHz SCCB.
//   - SCCB read uses an NA bit (master drives high), not an I2C NACK.
//   - sda is tri-state; top drives cam_sda = sda_oe ? sda_out : 1'bz.
// ============================================================================
`timescale 1ns / 1ps

module sccb_master #(
    parameter integer DIV = 125
) (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        start,       // one-cycle pulse
    input  wire        rw,          // 0=write, 1=read
    input  wire [6:0]  dev_addr,    // OV5640: 7'h3C
    input  wire [15:0] reg_addr,
    input  wire [7:0]  wr_data,

    output reg  [7:0]  rd_data,
    output wire        busy,
    output wire        done,
    output reg         ack_error,

    output reg         scl,
    output reg         sda_out,
    output reg         sda_oe,
    input  wire        sda_in
);

    localparam [2:0] ST_IDLE  = 3'd0,
                     ST_START = 3'd1,
                     ST_TX    = 3'd2,
                     ST_ACK   = 3'd3,
                     ST_STOP  = 3'd4,
                     ST_RX    = 3'd5,
                     ST_NA    = 3'd6,
                     ST_DONE  = 3'd7;

    reg [2:0]  state;
    reg [1:0]  phase;
    reg [7:0]  div_cnt;
    reg [3:0]  bit_cnt;
    reg [7:0]  shifter;
    reg [7:0]  tx_byte;
    reg [6:0]  dev_latch;
    reg [15:0] reg_latch;
    reg        rw_latch;
    reg [7:0]  wr_latch;
    reg        after_stop;
    reg [2:0]  byte_idx;

    assign busy = (state != ST_IDLE);
    assign done = (state == ST_DONE);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= ST_IDLE;
            phase      <= 2'd0;
            div_cnt    <= 8'd0;
            bit_cnt    <= 4'd0;
            shifter    <= 8'd0;
            tx_byte    <= 8'd0;
            dev_latch  <= 7'd0;
            reg_latch  <= 16'd0;
            rw_latch   <= 1'b0;
            wr_latch   <= 8'd0;
            after_stop <= 1'b0;
            byte_idx   <= 3'd0;
            rd_data    <= 8'd0;
            ack_error  <= 1'b0;
            scl        <= 1'b1;
            sda_out    <= 1'b1;
            sda_oe     <= 1'b0;
        end else if (div_cnt == DIV - 1) begin
            div_cnt <= 8'd0;
            phase   <= phase + 2'd1;

            case (state)
                // ------------------------------------------------------------
                ST_IDLE: begin
                    scl     <= 1'b1;
                    sda_out <= 1'b1;
                    sda_oe  <= 1'b0;
                    if (start) begin
                        dev_latch  <= dev_addr;
                        reg_latch  <= reg_addr;
                        rw_latch   <= rw;
                        wr_latch   <= wr_data;
                        tx_byte    <= {dev_addr, 1'b0};
                        byte_idx   <= 3'd0;
                        bit_cnt    <= 4'd0;
                        after_stop <= 1'b0;
                        ack_error  <= 1'b0;
                        phase      <= 2'd0;
                        state      <= ST_START;
                    end
                end

                // START: SDA high->low while SCL is high
                ST_START: begin
                    case (phase)
                        2'd0: begin
                            scl <= 1'b1; sda_out <= 1'b1; sda_oe <= 1'b1;
                            // Latch again on the first START phase so reg/wr
                            // are stable even when updated with start.
                            reg_latch <= reg_addr;
                            rw_latch  <= rw;
                            wr_latch  <= wr_data;
                        end
                        2'd1: sda_out <= 1'b0;
                        2'd2: scl <= 1'b0;
                        2'd3: begin
                            shifter <= tx_byte;
                            bit_cnt <= 4'd0;
                            state   <= ST_TX;
                        end
                    endcase
                end

                // Send 8 bits, MSB first
                ST_TX: begin
                    case (phase)
                        2'd0: begin scl <= 1'b0; sda_out <= shifter[7]; sda_oe <= 1'b1; end
                        2'd1: scl <= 1'b1;
                        2'd2: scl <= 1'b1;
                        2'd3: begin
                            scl     <= 1'b0;
                            shifter <= {shifter[6:0], 1'b0};
                            if (bit_cnt == 4'd7) begin
                                bit_cnt <= 4'd0;
                                state   <= ST_ACK;
                            end else begin
                                bit_cnt <= bit_cnt + 4'd1;
                            end
                        end
                    endcase
                end

                // Receive ACK (slave pulls low)
                ST_ACK: begin
                    case (phase)
                        2'd0: begin scl <= 1'b0; sda_oe <= 1'b0; end
                        2'd1: scl <= 1'b1;
                        2'd2: begin
                            if (sda_in) ack_error <= 1'b1;
                        end
                        2'd3: begin
                            scl <= 1'b0;
                            case (byte_idx)
                                3'd0: begin
                                    byte_idx <= 3'd1;
                                    shifter  <= reg_latch[15:8];
                                    state    <= ST_TX;
                                end
                                3'd1: begin
                                    byte_idx <= 3'd2;
                                    shifter  <= reg_latch[7:0];
                                    state    <= ST_TX;
                                end
                                3'd2: begin
                                    if (rw_latch) begin
                                        after_stop <= 1'b1;
                                        state      <= ST_STOP;
                                    end else begin
                                        byte_idx <= 3'd3;
                                        shifter  <= wr_latch;
                                        state    <= ST_TX;
                                    end
                                end
                                default: begin
                                    if (rw_latch) begin
                                        bit_cnt <= 4'd0;
                                        rd_data <= 8'd0;
                                        state   <= ST_RX;
                                    end else begin
                                        after_stop <= 1'b0;
                                        state      <= ST_STOP;
                                    end
                                end
                            endcase
                        end
                    endcase
                end

                // STOP: SDA low->high while SCL is high
                ST_STOP: begin
                    case (phase)
                        2'd0: begin scl <= 1'b0; sda_out <= 1'b0; sda_oe <= 1'b1; end
                        2'd1: scl <= 1'b1;
                        2'd2: sda_out <= 1'b1;
                        2'd3: begin
                            scl     <= 1'b1;
                            sda_oe  <= 1'b0;
                            if (after_stop) begin
                                after_stop <= 1'b0;
                                byte_idx   <= 3'd3;
                                tx_byte    <= {dev_latch, 1'b1};
                                state      <= ST_START;
                            end else begin
                                state <= ST_DONE;
                            end
                        end
                    endcase
                end

                // Receive 8 data bits
                ST_RX: begin
                    case (phase)
                        2'd0: begin scl <= 1'b0; sda_oe <= 1'b0; end
                        2'd1: scl <= 1'b1;
                        2'd2: rd_data <= {rd_data[6:0], sda_in};
                        2'd3: begin
                            scl <= 1'b0;
                            if (bit_cnt == 4'd7) begin
                                bit_cnt <= 4'd0;
                                state   <= ST_NA;
                            end else begin
                                bit_cnt <= bit_cnt + 4'd1;
                            end
                        end
                    endcase
                end

                // NA: 9th SCCB read bit, master drives high
                ST_NA: begin
                    case (phase)
                        2'd0: begin scl <= 1'b0; sda_out <= 1'b1; sda_oe <= 1'b1; end
                        2'd1: scl <= 1'b1;
                        2'd2: scl <= 1'b1;
                        2'd3: begin
                            scl        <= 1'b0;
                            after_stop <= 1'b0;
                            state      <= ST_STOP;
                        end
                    endcase
                end

                // Done: held until the next start
                ST_DONE: begin
                    scl    <= 1'b1;
                    sda_oe <= 1'b0;
                    if (phase == 2'd3) state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end else begin
            div_cnt <= div_cnt + 8'd1;
        end
    end

endmodule
