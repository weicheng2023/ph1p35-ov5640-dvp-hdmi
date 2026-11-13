// ============================================================================
// top_cam_fb_hdmi.v
//
// Stage 3 board top: ATK-MC5640 (OV5640) 8-bit DVP -> DDR double frame
// buffer -> 640x480@60 HDMI live display.
//
//   clk_50m    : C4, 50 MHz (HDMI PLL reference, DDR ref_clk)
//   cam_*      : SCCB + DVP + reset/power-down (same pins as top_dvp_test)
//   ddr_*      : in-package DDR2 512Mb x16 (assigned by the vendor IP ADC)
//   tmds_*     : HDMI1, same pins/chain as the board-proven color bar
//   led[3:0]   : D10/E10/C6/D6 = physical LED1..LED4
//
// Camera configuration is unchanged from the Stage 2 camera work:
//   0x4300 = 0x61 (RGB565, high byte first), 0x4740 = 0x22 (VSYNC active
//   high), 0x503D = COLOR_BAR (0 = normal image for Stage 3).
//
// LEDs:
//   LED1 = 1 Hz heartbeat
//   LED2 = DDR ready + 16-beat self-check passed
//   LED3 = at least one camera frame written to the frame buffer
//   LED4 = error (DDR / capture / FIFO / stream)
//
// CAL_EN=0 is the same experimental configuration as Stage 2. It is not a
// claim of complete PHY calibration.
// ============================================================================
`timescale 1ns / 1ps

module top_cam_fb_hdmi #(
    parameter integer POR_CYCLES        = 65_535,
    parameter integer HB_CYCLES         = 25_000_000,
    parameter integer SCCB_DIV          = 250,

    parameter integer H_PIX             = 640,
    parameter integer V_PIX             = 480,
    parameter integer H_TOTAL           = 1600,
    parameter integer V_TOTAL           = 1000,

    parameter integer COLOR_BAR         = 0,      // 0 = live image, 1 = test bar
    // HREF polarity with 0x4740=0x22 on this module:
    //   datasheet bit1=1 means HREF active high, but this module's polarity
    //   bits are inverted (proven for bit0/VSYNC): the pin is active LOW.
    //   The measured low phase is 26.665 us = 1280 PCLK, exactly 640 RGB565
    //   pixels, so the valid line is the low phase. HREF_ACTIVE_HIGH=0.
    parameter integer HREF_ACTIVE_HIGH  = 0,
    parameter integer CAPTURE_START     = 0,      // 0 or 640
    parameter integer BYTE_SWAP         = 0
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
    output wire        tmds_d2_p,

    // In-package DDR2 interface (pass-through; IP ADC assigns the sites)
    output wire [12:0] ddr_addr,
    output wire [1:0]  ddr_ba,
    output wire [0:0]  ddr_cke,
    output wire [0:0]  ddr_odt,
    output wire [0:0]  ddr_cs_n,
    output wire        ddr_ras_n,
    output wire        ddr_cas_n,
    output wire        ddr_we_n,
    output wire [0:0]  ddr_ck_p,
    output wire [0:0]  ddr_ck_n,
    inout  wire [1:0]  ddr_dm,
    inout  wire [15:0] ddr_dq,
    inout  wire [1:0]  ddr_dqs_p,
    inout  wire [1:0]  ddr_dqs_n
);

    // ------------------------------------------------------------------
    // 50 MHz global buffer + POR + heartbeat
    // ------------------------------------------------------------------
    wire clk_50m_buf;
    PH1P_LOGIC_BUFG u_bufg_clk (
        .i (clk_50m),
        .o (clk_50m_buf)
    );

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

    reg [31:0] hb_cnt;
    reg        hb;

    initial begin
        hb_cnt = 32'd0;
        hb     = 1'b0;
    end

    always @(posedge clk_50m_buf) begin
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

    // Optional camera internal color-bar build (-define CAM_COLOR_BAR) for
    // the first board test. It only changes 0x503D; the capture/DDR/HDMI
    // path is identical.
`ifdef CAM_COLOR_BAR
    localparam integer CB_SEL = 1;
`else
    localparam integer CB_SEL = COLOR_BAR;
`endif

    // ------------------------------------------------------------------
    // Camera power/ID/RGB565 configuration (shared SCCB master)
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
        .COLOR_BAR   (CB_SEL)
    ) u_bringup (
        .clk         (clk_50m_buf),
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
    // DDR controller/PHY (CAL_EN=0 experimental, same as Stage 2)
    // ------------------------------------------------------------------
    wire         dhi_clk;
    wire         cfg_clk;
    wire         cfg_rst_n;
    wire         ddrphy_rst_n;
    wire         ddrphy_rdy;

    wire [24:0]  paxi_awaddr;
    wire         paxi_awvalid;
    wire         paxi_awready;
    wire [127:0] paxi_wdata;
    wire [15:0]  paxi_wstrb;
    wire         paxi_wvalid;
    wire         paxi_wlast;
    wire         paxi_wready;
    wire [24:0]  paxi_araddr;
    wire         paxi_arvalid;
    wire         paxi_arready;
    wire [127:0] paxi_rdata;
    wire         paxi_rlast;
    wire         paxi_rvalid;
    wire         paxi_rready;

    ddr2 #(
        .CAL_EN (0)          // EXPERIMENTAL: PHY training bypassed
    ) u_ddr2 (
        .ref_clk          (clk_50m_buf),
        .sys_rst_n        (rst_n),

        .apb_pclk         (clk_50m_buf),
        .apb_prst_n       (rst_n),
        .apb_pready       (),
        .apb_psel         (1'b0),
        .apb_penable      (1'b0),
        .apb_pwrite       (1'b0),
        .apb_paddr        (16'd0),
        .apb_pwdata       (32'd0),
        .apb_prdata       (),

        .dhi_clk          (dhi_clk),
        .cfg_clk          (cfg_clk),
        .cfg_rst_n        (cfg_rst_n),
        .ddrphy_rst_n     (ddrphy_rst_n),
        .ddrphy_rdy       (ddrphy_rdy),

        .paxi_awaddr      (paxi_awaddr),
        .paxi_awvalid     (paxi_awvalid),
        .paxi_awready     (paxi_awready),
        .paxi_wdata       (paxi_wdata),
        .paxi_wstrb       (paxi_wstrb),
        .paxi_wvalid      (paxi_wvalid),
        .paxi_wlast       (paxi_wlast),
        .paxi_wready      (paxi_wready),
        .paxi_araddr      (paxi_araddr),
        .paxi_arvalid     (paxi_arvalid),
        .paxi_arready     (paxi_arready),
        .paxi_rdata       (paxi_rdata),
        .paxi_rlast       (paxi_rlast),
        .paxi_rvalid      (paxi_rvalid),
        .paxi_rready      (paxi_rready),

        .ddr_ck_p         (ddr_ck_p),
        .ddr_ck_n         (ddr_ck_n),
        .ddr_cke          (ddr_cke),
        .ddr_odt          (ddr_odt),
        .ddr_cs_n         (ddr_cs_n),
        .ddr_ras_n        (ddr_ras_n),
        .ddr_cas_n        (ddr_cas_n),
        .ddr_we_n         (ddr_we_n),
        .ddr_ba           (ddr_ba),
        .ddr_addr         (ddr_addr),
        .ddr_dqs_p        (ddr_dqs_p),
        .ddr_dqs_n        (ddr_dqs_n),
        .ddr_dq           (ddr_dq),
        .ddr_dm           (ddr_dm)
    );

    // ------------------------------------------------------------------
    // Stage 3 core: camera -> DDR double buffer -> HDMI
    // ------------------------------------------------------------------
    wire ddr_ready;
    wire self_pass;
    wire frame_valid;
    wire capture_error;
    wire error;
    wire hdmi_lock;

    cam_fb_hdmi_core #(
        .HREF_ACTIVE_HIGH  (HREF_ACTIVE_HIGH),
        .VSYNC_ACTIVE_HIGH (1),
        .CAPTURE_START     (CAPTURE_START),
        .BYTE_SWAP         (BYTE_SWAP),
        .PIXELS            (640),
        .V_ACTIVE          (480),
        .BASE_ADDR         (4096),
        .FRAME_STRIDE      (307200),
        .TOTAL_BEATS       (38400),
        .PREFILL_WORDS     (192)
    ) u_core (
        .clk_50m        (clk_50m_buf),
        .rst_n          (rst_n),
        .cfg_ok         (cfg_ok),

        .cam_pclk       (cam_pclk),
        .cam_vsync      (cam_vsync),
        .cam_href       (cam_href),
        .cam_data       (cam_data),

        .dhi_clk        (dhi_clk),
        .ddrphy_rdy     (ddrphy_rdy),

        .paxi_awaddr    (paxi_awaddr),
        .paxi_awvalid   (paxi_awvalid),
        .paxi_awready   (paxi_awready),
        .paxi_wdata     (paxi_wdata),
        .paxi_wstrb     (paxi_wstrb),
        .paxi_wvalid    (paxi_wvalid),
        .paxi_wlast     (paxi_wlast),
        .paxi_wready    (paxi_wready),
        .paxi_araddr    (paxi_araddr),
        .paxi_arvalid   (paxi_arvalid),
        .paxi_arready   (paxi_arready),
        .paxi_rdata     (paxi_rdata),
        .paxi_rlast     (paxi_rlast),
        .paxi_rvalid    (paxi_rvalid),
        .paxi_rready    (paxi_rready),

        .tmds_clk_p     (tmds_clk_p),
        .tmds_d0_p      (tmds_d0_p),
        .tmds_d1_p      (tmds_d1_p),
        .tmds_d2_p      (tmds_d2_p),

        .ddr_ready_o    (ddr_ready),
        .self_pass_o    (self_pass),
        .frame_valid_o  (frame_valid),
        .capture_error_o(capture_error),
        .error_o        (error),
        .hdmi_lock_o    (hdmi_lock)
    );

    // ------------------------------------------------------------------
    // LEDs
    // ------------------------------------------------------------------
    assign led[0] = hb;
    assign led[1] = ddr_ready && self_pass;
    assign led[2] = frame_valid;
    assign led[3] = error;

endmodule
