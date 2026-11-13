// ============================================================================
// top_ov5640_line_to_hdmi.v
// Board top: OV5640 internal color bar -> DVP D0-D7 -> one-line buffer ->
// the already-proven HDMI/TMDS output.
//
//   clk_50m   : C4, 50 MHz
//   cam_*     : OV5640 SCCB + DVP + reset/power-down
//   tmds_*    : HDMI1, same pins/chain as top_hdmi_colorbar
//   led[3:0]  : D10/E10/C6/D6 = physical LED1..LED4
//
// Camera configuration:
//   COLOR_BAR=1 -> 0x503D=0x80 (OV5640 internal test pattern)
//   0x4300=0x61 (RGB565, high byte first)
//   0x4740=0x22 (measured VSYNC active high; HREF sampled active high here)
//
// LEDs:
//   LED1: 1 Hz heartbeat
//   LED2: cfg_ok (SCCB config + readback)
//   LED3: capture_done (one valid line frozen in the buffer)
//   LED4: capture_error or no cfg_ok
//
// This top does NOT use DDR. It repeats one captured line on all 480 lines.
// ============================================================================
`timescale 1ns / 1ps

module top_ov5640_line_to_hdmi #(
    parameter integer POR_CYCLES        = 65_535,
    parameter integer HB_CYCLES         = 25_000_000,
    parameter integer SCCB_DIV          = 250,

    parameter integer H_PIX             = 640,
    parameter integer V_PIX             = 480,
    parameter integer H_TOTAL           = 1600,
    parameter integer V_TOTAL           = 1000,

    parameter integer COLOR_BAR         = 1,
    parameter integer HREF_ACTIVE_HIGH  = 1,
    parameter integer CAPTURE_START     = 0,
    parameter integer BYTE_SWAP         = 0,
    parameter integer STARTUP_LINES     = 3
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

    output wire [3:0]  led,

    output wire        tmds_clk_p,
    output wire        tmds_d0_p,
    output wire        tmds_d1_p,
    output wire        tmds_d2_p
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
    // Camera power/ID/config
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
        .SCCB_DIV    (SCCB_DIV),
        .H_PIX       (H_PIX),
        .V_PIX       (V_PIX),
        .H_TOTAL     (H_TOTAL),
        .V_TOTAL     (V_TOTAL),
        .COLOR_BAR   (COLOR_BAR)
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
    // Camera line -> HDMI core
    // ------------------------------------------------------------------
    wire        pll_lock;
    wire        capture_done;
    wire        capture_error;
    wire [15:0] line_bytes;
    wire [15:0] lines_seen;
    wire [7:0]  dbg_state;

    ov5640_line_to_hdmi_core #(
        .HREF_ACTIVE_HIGH (HREF_ACTIVE_HIGH),
        .CAPTURE_START    (CAPTURE_START),
        .BYTE_SWAP        (BYTE_SWAP),
        .STARTUP_LINES    (STARTUP_LINES)
    ) u_core (
        .clk_50m       (clk_50m),
        .rst_n         (rst_n),
        .cfg_ok        (cfg_ok),
        .cam_pclk      (cam_pclk),
        .cam_vsync     (cam_vsync),
        .cam_href      (cam_href),
        .cam_data      (cam_data),
        .tmds_clk_p    (tmds_clk_p),
        .tmds_d0_p     (tmds_d0_p),
        .tmds_d1_p     (tmds_d1_p),
        .tmds_d2_p     (tmds_d2_p),
        .pll_lock_o    (pll_lock),
        .capture_done_o(capture_done),
        .capture_error_o(capture_error),
        .line_bytes_o  (line_bytes),
        .lines_seen_o  (lines_seen),
        .dbg_state_o   (dbg_state)
    );

    // ------------------------------------------------------------------
    // Slow status sync (PCLK -> 50 MHz) for LEDs
    // ------------------------------------------------------------------
    reg [1:0] done_sync50;
    reg [1:0] err_sync50;
    reg [1:0] lock_sync50;

    always @(posedge clk_50m) begin
        if (!rst_n) begin
            done_sync50 <= 2'b00;
            err_sync50  <= 2'b00;
            lock_sync50 <= 2'b00;
        end else begin
            done_sync50 <= {done_sync50[0], capture_done};
            err_sync50  <= {err_sync50[0],  capture_error};
            lock_sync50 <= {lock_sync50[0], pll_lock};
        end
    end

    // ------------------------------------------------------------------
    // LEDs
    // ------------------------------------------------------------------
    assign led[0] = hb;                       // 1 Hz heartbeat
    assign led[1] = cfg_ok;                   // config + readback OK
    assign led[2] = done_sync50[1];           // line captured
    assign led[3] = err_sync50[1] | ~cfg_ok | ~lock_sync50[1];

endmodule
