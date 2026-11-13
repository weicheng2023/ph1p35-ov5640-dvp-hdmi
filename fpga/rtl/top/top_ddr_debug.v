// ============================================================================
// top_ddr_debug.v
//
// Minimal DDR bring-up debug top. It does NOT issue any AXI read/write.
//
// LEDs:
//   LED1 = 50 MHz heartbeat (clk_50m)
//   LED2 = ddrphy_rst_n  (IP reset released / PLL locked), 2-flop synced
//   LED3 = ddrphy_rdy    (initialization/calibration done), 2-flop synced
//   LED4 = independent 50 MHz timeout (latched if READY is not high in 1 s)
//
// CAL_EN:
//   default 1 (training enabled). Build with -define DDR_CAL0 for the
//   CAL_EN=0 control. CAL_EN=0 is NOT a fix; it only disables training.
//
// The AXI/APB inputs are tied off so only clock/reset/init/calibration are
// exercised.
// ============================================================================
`timescale 1ns / 1ps

module top_ddr_debug #(
    parameter integer POR_CYCLES     = 65_535,
    parameter integer HB_CYCLES      = 25_000_000,
    parameter integer TIMEOUT_CYCLES = 50_000_000
) (
    input  wire        clk_50m,
    output wire [3:0]  led,

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

`ifdef DDR_CAL0
    localparam integer CAL_EN_LOCAL = 0;
`else
    localparam integer CAL_EN_LOCAL = 1;
`endif

    // The debug top has a small clk_50m fanout; without an explicit BUFG
    // the tool inserts auto-created SCLK nets that check_timing reports as
    // "no clock driven". Use one global buffer for all 50 MHz logic and the
    // DDR ref/apb clocks.
    wire clk_50m_buf;
    PH1P_LOGIC_BUFG u_bufg_clk (
        .i (clk_50m),
        .o (clk_50m_buf)
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

    always @(posedge clk_50m_buf) begin
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
    // DDR controller/PHY: status only, no AXI transactions
    // ------------------------------------------------------------------
    wire dhi_clk;
    wire cfg_clk;
    wire cfg_rst_n;
    wire ddrphy_rst_n;
    wire ddrphy_rdy;

    ddr2 #(
        .CAL_EN (CAL_EN_LOCAL)
    ) u_ddr2 (
        .ref_clk          (clk_50m_buf),
        .sys_rst_n        (rst_n),

        // APB tied off
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

        // Native paxi tied off: no transactions in this debug build.
        .paxi_awaddr      (25'd0),
        .paxi_awvalid     (1'b0),
        .paxi_awready     (),
        .paxi_wdata       (128'd0),
        .paxi_wstrb       (16'd0),
        .paxi_wvalid      (1'b0),
        .paxi_wlast       (1'b0),
        .paxi_wready      (),
        .paxi_araddr      (25'd0),
        .paxi_arvalid     (1'b0),
        .paxi_arready     (),
        .paxi_rdata       (),
        .paxi_rlast       (),
        .paxi_rvalid      (),
        .paxi_rready      (1'b0),

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
    // Status/timeout monitor (independent 50 MHz domain)
    // ------------------------------------------------------------------
    wire pll_lock;
    wire ddr_ready;
    wire timeout;

    ddr_status_debug #(
        .TIMEOUT_CYCLES (TIMEOUT_CYCLES)
    ) u_status (
        .clk_50m      (clk_50m_buf),
        .rst_n        (rst_n),
        .ddrphy_rst_n (ddrphy_rst_n),
        .ddrphy_rdy   (ddrphy_rdy),
        .pll_lock     (pll_lock),
        .ready        (ddr_ready),
        .timeout      (timeout)
    );

    assign led[0] = hb;
    assign led[1] = pll_lock;
    assign led[2] = ddr_ready;
    assign led[3] = timeout;

endmodule
