// ============================================================================
// top_ddr_fb_hdmi_wbuf.v
//
// EXPERIMENTAL board top, identical to top_ddr_fb_hdmi except that the pixel
// gearbox uses the registered 128-bit word buffer variant:
//
//   FIFO head -> word_buf (128-bit register) -> 8:1 mux -> RGB565 register
//   -> RGB888 register -> TMDS, with DE/HS/VS delayed by the same 2 pixels.
//
// Purpose: isolate whether the right-edge colour-bar spurs seen on the
// board-proven top_ddr_fb_hdmi_paxi_fix_20261109 build come from the
// combinational FIFO-head -> mux -> encoder path. This top does NOT replace
// or rebuild that bitstream; it produces its own output files.
//
// Everything else (DDR IP, CAL_EN=0, 50 MHz reference, PLL, TMDS chain,
// video timing, PAXI contract, pin constraints) is unchanged.
//
// LEDs (same as top_ddr_fb_hdmi):
//   LED1 = 50 MHz heartbeat
//   LED2 = ddrphy_rdy (DDR READY)
//   LED3 = full-frame beats accepted + expected CRC ready
//   LED4 = self-check / readback CRC / FIFO / stream error
// ============================================================================
`timescale 1ns / 1ps

module top_ddr_fb_hdmi_wbuf #(
    parameter integer POR_CYCLES = 65_535,
    parameter integer HB_CYCLES  = 25_000_000
) (
    input  wire        clk_50m,
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

    // ------------------------------------------------------------------
    // DDR controller/PHY (CAL_EN=0 experimental, unchanged)
    // ------------------------------------------------------------------
    wire        dhi_clk;
    wire        cfg_clk;
    wire        cfg_rst_n;
    wire        ddrphy_rst_n;
    wire        ddrphy_rdy;

    wire [24:0] paxi_awaddr;
    wire        paxi_awvalid;
    wire        paxi_awready;
    wire [127:0] paxi_wdata;
    wire [15:0] paxi_wstrb;
    wire        paxi_wvalid;
    wire        paxi_wlast;
    wire        paxi_wready;
    wire [24:0] paxi_araddr;
    wire        paxi_arvalid;
    wire        paxi_arready;
    wire [127:0] paxi_rdata;
    wire        paxi_rlast;
    wire        paxi_rvalid;
    wire        paxi_rready;

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
    // Frame-buffer + HDMI core, registered word-buffer gearbox
    // ------------------------------------------------------------------
    wire ddr_ready;
    wire write_done;
    wire error;
    wire hdmi_lock;

    ddr_fb_hdmi_core #(
        .USE_WBUF (1)
    ) u_core (
        .clk_50m        (clk_50m_buf),
        .rst_n          (rst_n),
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
        .write_done_o   (write_done),
        .error_o        (error),
        .hdmi_lock_o    (hdmi_lock)
    );

    assign led[0] = hb;
    assign led[1] = ddr_ready;
    assign led[2] = write_done;
    assign led[3] = error;

endmodule
