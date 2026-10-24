// ============================================================================
// top_cam_id.v
// Minimal board bring-up: camera reset -> SCCB Chip ID read -> LED status.
//
// Hardware:
//   PH1P35_FT V1 / HX1P35B_FT_40P, PH1P35MDG324
//   50MHz clock: C4 (FPGA_A_SYSCLK_50MHZ)
//   LED0..3: D10, E10, C6, D6 (active high; physical LED1..4)
//   Camera SCCB/control: SCL=R6, SDA=T5, RESET=U7, PWDN=U6
//
// LEDs:
//   LED0: 1Hz heartbeat (FPGA running)
//   LED1: at least one SCCB read completed without ACK error
//   LED2: high byte read back == 0x56
//   LED3: Chip ID == 0x5640 (full match)
//
// Notes:
//   - This test uses SCCB + RESET + PWDN only; PCLK/DVP are not in the RTL.
//   - Camera 3.3V/GND must still be wired per docs/hardware/wiring.md.
//   - If LED1 stays off, check SCCB pull-ups, SCL/SDA wiring and camera power.
// ============================================================================
`timescale 1ns / 1ps

module top_cam_id #(
    parameter integer POR_CYCLES          = 65_535,     // power-on reset ~1.3ms
    parameter integer HB_CYCLES           = 25_000_000, // 0.5s toggle -> 1Hz
    parameter integer PWRUP_CYCLES        = 500_000,    // 10ms
    parameter integer RESET_WAIT_CYCLES   = 1_000_000,  // 20ms
    parameter integer RETRY_CYCLES        = 50_000_000, // 1s
    parameter integer SCCB_DIV            = 250,        // 50kHz @50MHz (debug margin)
    parameter integer SCCB_TIMEOUT        = 200_000     // 4ms
) (
    input  wire       clk_50m,
    output wire [3:0] led,

    output wire       cam_scl,
    inout  wire       cam_sda,
    output wire       cam_reset_n,
    output wire       cam_pwdn
);

    // ------------------------------------------------------------------
    // Power-on reset
    // ------------------------------------------------------------------
    reg [31:0] por_cnt;
    reg        rst_n;

    // Simulation power-up values; FPGA registers also default to 0.
    initial begin
        por_cnt = 32'd0;
        rst_n   = 1'b0;
    end

    always @(posedge clk_50m) begin
        if (por_cnt < POR_CYCLES) begin
            por_cnt <= por_cnt + 32'd1;
            rst_n   <= 1'b0;
        end else begin
            rst_n   <= 1'b1;
        end
    end

    // ------------------------------------------------------------------
    // 1Hz heartbeat
    // ------------------------------------------------------------------
    reg [31:0] hb_cnt;
    reg        hb;

    initial begin
        hb_cnt = 32'd0;
        hb     = 1'b0;
    end

    always @(posedge clk_50m) begin
        if (!rst_n) begin
            hb_cnt <= 32'd0;
            hb     <= 1'b0;
        end else if (hb_cnt >= HB_CYCLES - 1) begin
            hb_cnt <= 32'd0;
            hb     <= ~hb;
        end else begin
            hb_cnt <= hb_cnt + 32'd1;
        end
    end

    // ------------------------------------------------------------------
    // SCCB bus
    // ------------------------------------------------------------------
    wire sccb_busy;
    wire sccb_done;
    wire sccb_ack_error;
    wire [7:0] sccb_rd_data;

    wire        sccb_start;
    wire        sccb_rw;
    wire [15:0] sccb_reg;
    wire [7:0]  sccb_wdata;

    wire sda_in  = cam_sda;
    wire sda_out;
    wire sda_oe;

    assign cam_sda = sda_oe ? sda_out : 1'bz;

    sccb_master #(
        .DIV (SCCB_DIV)
    ) u_sccb (
        .clk       (clk_50m),
        .rst_n     (rst_n),
        .start     (sccb_start),
        .rw        (sccb_rw),
        .dev_addr  (7'h3C),          // OV5640: 0x78 write / 0x79 read
        .reg_addr  (sccb_reg),
        .wr_data   (sccb_wdata),
        .rd_data   (sccb_rd_data),
        .busy      (sccb_busy),
        .done      (sccb_done),
        .ack_error (sccb_ack_error),
        .scl       (cam_scl),
        .sda_out   (sda_out),
        .sda_oe    (sda_oe),
        .sda_in    (sda_in)
    );

    // ------------------------------------------------------------------
    // Chip ID read / retry
    // ------------------------------------------------------------------
    wire [7:0] id_hi;
    wire [7:0] id_lo;
    wire       link_ok;
    wire       id_match;
    wire       id_error;

    ov5640_id_reader #(
        .PWRUP_CYCLES      (PWRUP_CYCLES),
        .RESET_WAIT_CYCLES (RESET_WAIT_CYCLES),
        .RETRY_CYCLES      (RETRY_CYCLES),
        .SCCB_TIMEOUT      (SCCB_TIMEOUT)
    ) u_reader (
        .clk            (clk_50m),
        .rst_n          (rst_n),
        .cam_pwdn       (cam_pwdn),
        .cam_reset_n    (cam_reset_n),
        .sccb_start     (sccb_start),
        .sccb_rw        (sccb_rw),
        .sccb_reg       (sccb_reg),
        .sccb_wdata     (sccb_wdata),
        .sccb_busy      (sccb_busy),
        .sccb_done      (sccb_done),
        .sccb_ack_error (sccb_ack_error),
        .sccb_rd_data   (sccb_rd_data),
        .id_hi          (id_hi),
        .id_lo          (id_lo),
        .link_ok        (link_ok),
        .id_match       (id_match),
        .id_error       (id_error)
    );

    // ------------------------------------------------------------------
    // LED status
    // ------------------------------------------------------------------
    assign led[0] = hb;
    assign led[1] = link_ok;
    assign led[2] = (id_hi == 8'h56);
    assign led[3] = id_match;

endmodule
