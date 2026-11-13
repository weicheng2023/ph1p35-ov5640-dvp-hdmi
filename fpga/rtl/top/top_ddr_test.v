// ============================================================================
// top_ddr_test.v
//
// Independent (no camera, no HDMI) DDR bring-up test for PH1P35MDG324.
//
// DDR hardware:
//   - PH1P35MDG324 has in-package DDR2-class 512Mb x16 (64 MB, 1.5 V).
//   - TD IP MIS_DDRF6F1D0P0_1.1 "Integrated" mode: DDR2 512Mb x16,
//     MDG324 PHY config, native paxi_* 128-bit user port
//     (word-addressed, no B response channel). MC0_MIS_AXI is NOT defined;
//     the full AXI4 adapter is not used in this minimal test.
//
// Clock:
//   - clk_50m (C4) is used as both ref_clk and apb_pclk.
//   - The IP PLL is configured for 50 MHz ref -> 533.33 MHz DDR clock
//     (DDR2-1066): N=3, M=64, C=2, CLK3=21.
//
// Test:
//   - wait for ddrphy_rdy (calibration complete);
//   - AXI write 16 known 128-bit beats, read them back, compare;
//   - LED1 = 1 Hz heartbeat
//     LED2 = ddrphy_rdy (calibration complete)
//     LED3 = pattern PASS
//     LED4 = pattern FAIL/timeout
//
// The DDR pins are in-package. The top exposes them only as pass-through
// ports; the IP ADC (ddr2.adc) assigns the IP pins to the internal PHY
// sites. No package-ball pin assignments for ddr_* are needed.
// ============================================================================
`timescale 1ns / 1ps

module top_ddr_test #(
    parameter integer POR_CYCLES = 65_535,
    parameter integer HB_CYCLES  = 25_000_000
) (
    input  wire        clk_50m,
    output wire [3:0]  led,

    // In-package DDR2 interface (pass-through; assigned by the IP ADC)
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
    // Power-on reset / heartbeat
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
    // DDR IP user interface
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

    // ------------------------------------------------------------------
    // DDR controller + PHY (vendor generated IP)
    //
    // The plain `ddr2` wrapper instantiates the vendor wrapper as
    // "ph1p_ddrmc_wrapper". The IP ADC is rooted at this `ddr2` model so
    // its paths ph1p_ddrmc_wrapper/... resolve correctly.
    // ------------------------------------------------------------------
    ddr2 u_ddr2 (
        .ref_clk          (clk_50m),
        .sys_rst_n        (rst_n),

        // APB debug port: explicitly tie off (do not leave floating).
        .apb_pclk         (clk_50m),
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
    // Sync ddrphy_rdy into dhi_clk; synchronize the reset release too.
    // ------------------------------------------------------------------
    reg [1:0] rst_dhi_sync;
    reg [1:0] rdy_sync;

    always @(posedge dhi_clk or negedge rst_n) begin
        if (!rst_n) begin
            rst_dhi_sync <= 2'b00;
            rdy_sync     <= 2'b00;
        end else begin
            rst_dhi_sync <= {rst_dhi_sync[0], 1'b1};
            rdy_sync     <= {rdy_sync[0], ddrphy_rdy};
        end
    end

    wire rst_dhi_n = rst_dhi_sync[1];
    wire ddr_ready = rdy_sync[1];

    // ------------------------------------------------------------------
    // AXI pattern test
    // ------------------------------------------------------------------
    wire       test_done;
    wire       test_pass;
    wire       test_fail;
    wire [7:0] test_err_cnt;

    ddr_axi_pattern_test #(
        .ADDR_WIDTH (25),
        .DATA_WIDTH (128),
        .STRB_WIDTH (16),
        .N          (16),
        .TIMEOUT    (24_000_000)
    ) u_pattern (
        .clk           (dhi_clk),
        .rst_n         (rst_dhi_n),
        .start         (ddr_ready),

        .paxi_awaddr   (paxi_awaddr),
        .paxi_awvalid  (paxi_awvalid),
        .paxi_awready  (paxi_awready),
        .paxi_wdata    (paxi_wdata),
        .paxi_wstrb    (paxi_wstrb),
        .paxi_wvalid   (paxi_wvalid),
        .paxi_wlast    (paxi_wlast),
        .paxi_wready   (paxi_wready),

        .paxi_araddr   (paxi_araddr),
        .paxi_arvalid  (paxi_arvalid),
        .paxi_arready  (paxi_arready),
        .paxi_rdata    (paxi_rdata),
        .paxi_rlast    (paxi_rlast),
        .paxi_rvalid   (paxi_rvalid),
        .paxi_rready   (paxi_rready),

        .done          (test_done),
        .pass          (test_pass),
        .fail          (test_fail),
        .err_cnt       (test_err_cnt)
    );

    // ------------------------------------------------------------------
    // LEDs (active high): D10/E10/C6/D6 = LED1..LED4
    // ------------------------------------------------------------------
    assign led[0] = hb;
    assign led[1] = ddr_ready;
    assign led[2] = test_pass;
    assign led[3] = test_fail;

endmodule
