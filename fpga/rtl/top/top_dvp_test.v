// ============================================================================
// top_dvp_test.v
// Board bring-up top for the OV5640 DVP capture stage.
//
//   clk_50m  : C4, 50 MHz
//   cam_*    : ATK-MC5640 DVP + SCCB + reset/power-down
//   led[3:0] : D10/E10/C6/D6 = physical LED1..LED4
//
// What it does:
//   1. Power-up sequence + Chip ID read (ov5640_id_reader).
//   2. RGB565 configuration + readback (ov5640_cfg).
//   3. DVP capture + asynchronous event FIFO + 50 MHz monitor.
//
// LED semantics:
//   LED1: 1 Hz heartbeat (FPGA configured and running)
//   LED2: cfg_ok (configuration + readback succeeded)
//   LED3: frame counter bit 0 (toggles as frames arrive)
//   LED4: error (cfg error, line/frame error, or event FIFO overflow)
//
// This top does NOT drive HDMI or DDR. The camera's PCLK/VSYNC/HREF are also
// available on J2 for the logic analyzer; the FPGA counters are a cross-check.
// ============================================================================
`timescale 1ns / 1ps

module top_dvp_test #(
    parameter integer POR_CYCLES     = 65_535,
    parameter integer HB_CYCLES      = 25_000_000,
    parameter integer SCCB_DIV       = 250,
    parameter integer H_PIX          = 640,
    parameter integer V_PIX          = 480,
    parameter integer H_TOTAL        = 1600,
    parameter integer V_TOTAL        = 1000,
    parameter integer COLOR_BAR      = 0,
    parameter integer STARTUP_FRAMES = 10,
    // Measured 2026-10-26: HREF high = 40 us at PCLK = 50 MHz -> 2000 PCLK.
    // The RGB565 active width is still H_PIX=640 (1280 bytes); the remaining
    // bytes may be dummy/padding and are not yet distinguished.
    parameter integer HREF_PCLK      = 2000
) (
    input  wire        clk_50m,

    input  wire        cam_pclk,
    input  wire        cam_vsync,
    input  wire        cam_href,
    input  wire [7:0]  cam_data,

    output wire        cam_scl,
    inout  wire        cam_sda,
    output wire        cam_reset_n,
    output wire        cam_pwdn,

    output wire [3:0]  led
);

    // ------------------------------------------------------------------
    // Power-on reset
    // ------------------------------------------------------------------
    reg [31:0] por_cnt;
    reg        rst_n;

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
    // 1 Hz heartbeat
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
    // Camera power/reset, ID read, configuration
    // ------------------------------------------------------------------
    wire       id_match;
    wire       cfg_ok;
    wire       cfg_error;

    wire [7:0]  rb_id_hi;
    wire [7:0]  rb_id_lo;
    wire [7:0]  rb_4300;
    wire [7:0]  rb_4740;
    wire [7:0]  rb_503d;
    wire [12:0] rb_width;
    wire [12:0] rb_height;
    wire [7:0]  rb_3035;
    wire [7:0]  rb_3036;
    wire [7:0]  rb_3037;
    wire [7:0]  rb_3108;
    wire [7:0]  cfg_idx;

    ov5640_bringup #(
        .SCCB_DIV           (SCCB_DIV),
        .H_PIX              (H_PIX),
        .V_PIX              (V_PIX),
        .H_TOTAL            (H_TOTAL),
        .V_TOTAL            (V_TOTAL),
        .COLOR_BAR          (COLOR_BAR)
    ) u_bringup (
        .clk         (clk_50m),
        .rst_n       (rst_n),
        .cam_scl     (cam_scl),
        .cam_sda     (cam_sda),
        .cam_reset_n (cam_reset_n),
        .cam_pwdn    (cam_pwdn),
        .id_match    (id_match),
        .cfg_ok      (cfg_ok),
        .cfg_error   (cfg_error),
        .rb_id_hi    (rb_id_hi),
        .rb_id_lo    (rb_id_lo),
        .rb_4300     (rb_4300),
        .rb_4740     (rb_4740),
        .rb_503d     (rb_503d),
        .rb_width    (rb_width),
        .rb_height   (rb_height),
        .rb_3035     (rb_3035),
        .rb_3036     (rb_3036),
        .rb_3037     (rb_3037),
        .rb_3108     (rb_3108),
        .cfg_idx     (cfg_idx)
    );

    // ------------------------------------------------------------------
    // DVP capture (PCLK domain) + event FIFO + 50 MHz monitor
    // ------------------------------------------------------------------
    wire [63:0] evt_data;
    wire        evt_wr;
    wire        evt_full;
    wire        evt_overflow;
    wire        pclk_rst_n;

    wire        sample_valid;
    wire [7:0]  sample_data;

    dvp_capture #(
        .HREF_ACTIVE_HIGH  (1),
        .VSYNC_ACTIVE_HIGH (0),   // measured: VSYNC idle high, short low pulse
        .STARTUP_FRAMES    (STARTUP_FRAMES),
        .EXPECTED_PIX      (HREF_PCLK),
        .EXPECTED_LINES    (V_PIX)
    ) u_cap (
        .pclk              (cam_pclk),
        .rst_n             (rst_n),
        .cap_en            (cfg_ok),
        .dvp_d             (cam_data),
        .dvp_href          (cam_href),
        .dvp_vsync         (cam_vsync),
        .evt_data          (evt_data),
        .evt_wr            (evt_wr),
        .evt_full          (evt_full),
        .evt_overflow      (evt_overflow),
        .frame_cnt         (),
        .line_cnt          (),
        .pix_cnt           (),
        .line_pix_cnt      (),
        .startup_cnt       (),
        .active            (),
        .frame_start_pulse (),
        .err_flags         (),
        .sample_valid      (sample_valid),
        .sample_data       (sample_data),
        .pclk_rst_n_o      (pclk_rst_n)
    );

    wire [63:0] evt_rd_data;
    wire        evt_empty;
    wire        evt_rd_en;
    wire        fifo_overflow;

    async_fifo_gray #(
        .DATA_WIDTH (64),
        .ADDR_WIDTH (4)
    ) u_evt_fifo (
        .wr_clk      (cam_pclk),
        .wr_rst_n    (pclk_rst_n),
        .wr_en       (evt_wr),
        .wr_data     (evt_data),
        .wr_full     (evt_full),
        .wr_overflow (fifo_overflow),
        .rd_clk      (clk_50m),
        .rd_rst_n    (rst_n),
        .rd_en       (evt_rd_en),
        .rd_data     (evt_rd_data),
        .rd_empty    (evt_empty)
    );

    wire [15:0] mon_frame_cnt;
    wire [15:0] mon_line_cnt;
    wire [15:0] mon_lines_in_frame;
    wire [15:0] mon_pix_min;
    wire [15:0] mon_pix_max;
    wire        mon_line_ok;
    wire        mon_frame_ok;
    wire        mon_err_sticky;
    wire [7:0]  mon_last_err;
    wire [31:0] mon_evt_count;

    dvp_status_monitor #(
        .EXPECTED_PIX   (HREF_PCLK),
        .EXPECTED_LINES (V_PIX)
    ) u_mon (
        .clk            (clk_50m),
        .rst_n          (rst_n),
        .evt_data       (evt_rd_data),
        .evt_empty      (evt_empty),
        .evt_rd_en      (evt_rd_en),
        .frame_cnt      (mon_frame_cnt),
        .line_cnt       (mon_line_cnt),
        .lines_in_frame (mon_lines_in_frame),
        .pix_min        (mon_pix_min),
        .pix_max        (mon_pix_max),
        .line_ok        (mon_line_ok),
        .frame_ok       (mon_frame_ok),
        .err_sticky     (mon_err_sticky),
        .last_err       (mon_last_err),
        .evt_count      (mon_evt_count)
    );

    // ------------------------------------------------------------------
    // LEDs
    // ------------------------------------------------------------------
    assign led[0] = hb;
    assign led[1] = cfg_ok;
    assign led[2] = mon_frame_cnt[0];
    assign led[3] = cfg_error | evt_overflow | fifo_overflow |
                    mon_err_sticky | ~mon_line_ok | ~mon_frame_ok;

endmodule
