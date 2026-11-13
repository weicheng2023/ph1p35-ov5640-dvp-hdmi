// ============================================================================
// ddr2_top.v  (module name: ddr2)
//
// Thin board-independent wrapper around the vendor-generated PH1P35MDG324
// Integrated DDR2 512Mb x16 IP. This is the plain RTL top that the vendor
// IP ADC/SDC expect: it instantiates the generated wrapper as
// "ph1p_ddrmc_wrapper", so the ADC paths
//   ph1p_ddrmc_wrapper/ph1p_ddrmc_top/...
// resolve relative to this "ddr2" model.
//
// Differences from the vendor reference `ddr2.v`:
//   - ref_clk PLL configured for 50 MHz (not 100 MHz):
//     N=3, M=64, C=2, CLK3=21 -> 533.33 MHz DDR clock (DDR2-1066);
//   - CAL_EN=1 (enable delay calibration);
//   - APB/DDR/AXI ports are the same.
//
// The vendor IP wrapper keeps the native paxi_* interface (word-addressed,
// no B response channel); MC0_MIS_AXI is NOT defined.
// ============================================================================
`timescale 1ps/1ps

module ddr2 #(
    // CAL_EN=1: run the PHY delay calibration (and wait for ddrphy_rdy).
    // CAL_EN=0: reference-project control; skips training. NOT a fix.
    parameter integer CAL_EN = 1
) (
    input  wire         ref_clk,
    input  wire         sys_rst_n,

    // APB debug port
    input  wire         apb_pclk,
    input  wire         apb_prst_n,
    output wire         apb_pready,
    input  wire         apb_psel,
    input  wire         apb_penable,
    input  wire         apb_pwrite,
    input  wire [15:0]  apb_paddr,
    input  wire [31:0]  apb_pwdata,
    output wire [31:0]  apb_prdata,

    // MC clocks/status
    output wire         dhi_clk,
    output wire         cfg_clk,
    output wire         cfg_rst_n,
    output wire         ddrphy_rst_n,
    output wire         ddrphy_rdy,

    // Native paxi interface (word-addressed, 128-bit beats)
    input  wire [24:0]  paxi_awaddr,
    input  wire         paxi_awvalid,
    output wire         paxi_awready,
    input  wire [127:0] paxi_wdata,
    input  wire [15:0]  paxi_wstrb,
    input  wire         paxi_wvalid,
    input  wire         paxi_wlast,
    output wire         paxi_wready,
    input  wire [24:0]  paxi_araddr,
    input  wire         paxi_arvalid,
    output wire         paxi_arready,
    output wire [127:0] paxi_rdata,
    output wire         paxi_rlast,
    output wire         paxi_rvalid,
    input  wire         paxi_rready,

    // In-package DDR2 interface
    output wire [0:0]   ddr_ck_p,
    output wire [0:0]   ddr_ck_n,
    output wire [0:0]   ddr_cke,
    output wire [0:0]   ddr_odt,
    output wire [0:0]   ddr_cs_n,
    output wire         ddr_ras_n,
    output wire         ddr_cas_n,
    output wire         ddr_we_n,
    output wire [1:0]   ddr_ba,
    output wire [12:0]  ddr_addr,
    inout  wire [1:0]   ddr_dqs_p,
    inout  wire [1:0]   ddr_dqs_n,
    inout  wire [15:0]  ddr_dq,
    inout  wire [1:0]   ddr_dm
);

    ph1p_ddrmc_wrapper_63f4ac254419 #(
        .tCK              (1876),
        .BK_NUM           (2),
        .AC_NUM           (4),
        .DX_NUM           (2),
        .CK_WIDTH         (1),
        .CS_WIDTH         (1),
        .CKE_WIDTH        (1),
        .ODT_WIDTH        (1),
        .BG_WIDTH         (0),
        .BA_WIDTH         (2),
        .ROW_WIDTH        (13),
        .COL_WIDTH        (10),
        .ADR_WIDTH        (13),
        .HOST_AC_DRV      ("75"),
        .HOST_DX_DRV      ("75"),
        .HOST_DX_ODT      ("75"),
        .DRAM_DRV         ("0"),
        .DRAM_ODT         ("75"),
        .WDM              (1),
        .CAL_EN           (CAL_EN),
        .CWL              (6),
        .CL               (7),
        .PLL0_REFCLK_FREQ (50.0),
        .PLL0_REFCLK_DIV  (3),
        .PLL0_FBKCLK_DIV  (64),
        .PLL0_FRAC        ("DISABLE"),
        .PLL0_FRAC_SDM    (0),
        .PLL0_CLK2_DIV    (2),
        .PLL0_CLK3_DIV    (21),
        .PLL1_REFCLK_FREQ (133.3333),
        .PLL1_REFCLK_DIV  (4),
        .PLL1_CLK0_DIV    (12),
        .MC_ECC           ("OFF"),
        .MC_ADDR_MAP      ("ROW_COL_BANK"),
        .MC_REORDER       ("NORMAL"),
        .MC_ADDR_WIDTH    (25),
        .MC_DATA_WIDTH    (128),
        .MC_MASK_WIDTH    (16),
        .AXI_ID_WIDTH     (4),
        .AXI_ADDR_WIDTH   (26),
        .AXI_DATA_WIDTH   (128),
        .AXI_MASK_WIDTH   (16)
    ) ph1p_ddrmc_wrapper (
        .ref_clk          (ref_clk),
        .sys_rst_n        (sys_rst_n),

        .apb_pclk         (apb_pclk),
        .apb_prst_n       (apb_prst_n),
        .apb_pready       (apb_pready),
        .apb_psel         (apb_psel),
        .apb_penable      (apb_penable),
        .apb_pwrite       (apb_pwrite),
        .apb_paddr        (apb_paddr),
        .apb_pwdata       (apb_pwdata),
        .apb_prdata       (apb_prdata),

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

endmodule
