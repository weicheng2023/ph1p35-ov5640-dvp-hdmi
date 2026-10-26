// ============================================================================
// ov5640_bringup.v
// Camera power/reset, Chip ID read, and RGB565 configuration.
//
// Flow:
//   ov5640_id_reader: PWDN=0, RESET low -> high, read 0x300A/0x300B, retry.
//   After id_match, the SCCB bus is switched to ov5640_cfg, which writes the
//   RGB565 table and reads back key registers.
//
// The SCCB master is shared. id_match is sticky and is only asserted after the
// reader's last transaction, so the config sequencer starts from a free bus.
// cfg_ok is only high when the configuration and readback both succeeded.
//
// This module does not touch PCLK/DVP. The board top connects cfg_ok to the DVP
// capture enable.
// ============================================================================
`timescale 1ns / 1ps

module ov5640_bringup #(
    parameter integer SCCB_DIV           = 250,
    parameter integer PWRUP_CYCLES       = 500_000,
    parameter integer RESET_WAIT_CYCLES  = 1_000_000,
    parameter integer RETRY_CYCLES       = 50_000_000,
    parameter integer SCCB_TIMEOUT       = 200_000,
    parameter integer RESET_DELAY_CYCLES = 50_000,
    parameter integer H_PIX              = 640,
    parameter integer V_PIX              = 480,
    parameter integer H_TOTAL            = 1600,
    parameter integer V_TOTAL            = 1000,
    parameter integer COLOR_BAR          = 0
) (
    input  wire        clk,
    input  wire        rst_n,

    output wire        cam_scl,
    inout  wire        cam_sda,
    output wire        cam_reset_n,
    output wire        cam_pwdn,

    output wire        id_match,
    output wire        cfg_ok,
    output wire        cfg_error,

    output wire [7:0]  rb_id_hi,
    output wire [7:0]  rb_id_lo,
    output wire [7:0]  rb_4300,
    output wire [7:0]  rb_4740,
    output wire [7:0]  rb_503d,
    output wire [12:0] rb_width,
    output wire [12:0] rb_height,
    output wire [7:0]  rb_3035,
    output wire [7:0]  rb_3036,
    output wire [7:0]  rb_3037,
    output wire [7:0]  rb_3108,
    output wire [7:0]  cfg_idx
);

    // ------------------------------------------------------------------
    // SCCB bus
    // ------------------------------------------------------------------
    wire sda_in  = cam_sda;
    wire sda_out;
    wire sda_oe;

    assign cam_sda = sda_oe ? sda_out : 1'bz;

    wire        sccb_busy;
    wire        sccb_done;
    wire        sccb_ack_error;
    wire [7:0]  sccb_rd_data;

    // Shared master inputs, muxed between reader and config.
    wire        sccb_start;
    wire        sccb_rw;
    wire [15:0] sccb_reg;
    wire [7:0]  sccb_wdata;

    // Reader-side SCCB signals
    wire        id_start;
    wire        id_rw;
    wire [15:0] id_reg;
    wire [7:0]  id_wdata;

    // Config-side SCCB signals
    wire        cfg_start;
    wire        cfg_rw;
    wire [15:0] cfg_reg;
    wire [7:0]  cfg_wdata;

    wire cfg_active = id_match;

    assign sccb_start = cfg_active ? cfg_start : id_start;
    assign sccb_rw    = cfg_active ? cfg_rw    : id_rw;
    assign sccb_reg   = cfg_active ? cfg_reg   : id_reg;
    assign sccb_wdata = cfg_active ? cfg_wdata : id_wdata;

    sccb_master #(
        .DIV (SCCB_DIV)
    ) u_sccb (
        .clk       (clk),
        .rst_n     (rst_n),
        .start     (sccb_start),
        .rw        (sccb_rw),
        .dev_addr  (7'h3C),
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
    // Power-up, reset, Chip ID
    // ------------------------------------------------------------------
    wire [7:0] id_hi;
    wire [7:0] id_lo;
    wire       link_ok;
    wire       id_error;

    ov5640_id_reader #(
        .PWRUP_CYCLES      (PWRUP_CYCLES),
        .RESET_WAIT_CYCLES (RESET_WAIT_CYCLES),
        .RETRY_CYCLES      (RETRY_CYCLES),
        .SCCB_TIMEOUT      (SCCB_TIMEOUT)
    ) u_id (
        .clk            (clk),
        .rst_n          (rst_n),
        .cam_pwdn       (cam_pwdn),
        .cam_reset_n    (cam_reset_n),
        .sccb_start     (id_start),
        .sccb_rw        (id_rw),
        .sccb_reg       (id_reg),
        .sccb_wdata     (id_wdata),
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
    // RGB565 configuration and readback
    // ------------------------------------------------------------------
    wire cfg_done;

    ov5640_cfg #(
        .H_PIX              (H_PIX),
        .V_PIX              (V_PIX),
        .H_TOTAL            (H_TOTAL),
        .V_TOTAL            (V_TOTAL),
        .COLOR_BAR          (COLOR_BAR),
        .RESET_DELAY_CYCLES (RESET_DELAY_CYCLES),
        .SCCB_TIMEOUT       (SCCB_TIMEOUT)
    ) u_cfg (
        .clk          (clk),
        .rst_n        (rst_n),
        .start        (id_match),
        .sccb_start   (cfg_start),
        .sccb_rw      (cfg_rw),
        .sccb_reg     (cfg_reg),
        .sccb_wdata   (cfg_wdata),
        .sccb_busy    (sccb_busy),
        .sccb_done    (sccb_done),
        .sccb_rd_data (sccb_rd_data),
        .cfg_done     (cfg_done),
        .cfg_error    (cfg_error),
        .cfg_idx      (cfg_idx),
        .rb_id_hi     (rb_id_hi),
        .rb_id_lo     (rb_id_lo),
        .rb_4300      (rb_4300),
        .rb_4740      (rb_4740),
        .rb_503d      (rb_503d),
        .rb_width     (rb_width),
        .rb_height    (rb_height),
        .rb_3035      (rb_3035),
        .rb_3036      (rb_3036),
        .rb_3037      (rb_3037),
        .rb_3108      (rb_3108)
    );

    assign cfg_ok = cfg_done && !cfg_error;

endmodule
