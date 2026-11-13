// ============================================================================
// pll_hdmi.v
// PH1P35 PLL for the HDMI color-bar design.
//
// Input : 50 MHz (C4)
// Output: pixel_clk  = 25.0 MHz
//         serial_clk = 125.0 MHz  (5 x pixel clock, DDR -> 250 Mbps/lane)
//
// PLL configuration (TD 6.2.1 PH1P_PHY_PLL_V2):
//   C0 feedback (FBKCLK = CLKC0_EXT, FEEDBK_MODE = NORMAL)
//   C0   = FIN * FBCLK_DIV / REFCLK_DIV = 50 * 1 / 2 = 25.0 MHz
//   VCO  = C0 * CLKC0_DIV = 25.0 * 50 = 1250 MHz
//   C1   = VCO / 10 = 125.0 MHz
//   VREF = FIN / REFCLK_DIV = 25 MHz
//
// Why 25.0 MHz and not 25.2 MHz:
//   Exact 25.2 MHz needs C0 = 50 * M/N with M/N = 63/125. With C0 feedback
//   that means VREF = 0.4 MHz (below the TD 10 MHz minimum) or fractional-N.
//   The TD vendor functional PLL model locks the integer 25.0 MHz
//   configuration (C0 feedback) but does NOT lock the 25.2 MHz VCO-feedback
//   or fractional configurations. 25.0 MHz is therefore the clean,
//   reproducible choice; the vertical total is adjusted to 521 lines so the
//   frame rate is 59.981 Hz instead of 59.524 Hz (see video_timing.v).
//
// Loop filter: LPF_CAP=25 / ICP_CUR=29 / LPF_RES=0, matching the PH1P
// reference PLL that locks in the same vendor model.
//
// This file is for synthesis. ModelSim uses fpga/sim/models/pll_hdmi_sim.v.
// ============================================================================
`timescale 1ns / 1ps

module pll_hdmi (
    input  wire clk_50m,
    output wire pixel_clk,      // 25.0 MHz, buffered
    output wire serial_clk,     // 125.0 MHz, 5 x pixel
    output wire lock
);

    wire [6:0] clkc;
    wire [6:0] clkcb;

    // C0 is the pixel clock and is fed back through a BUFG for the fabric.
    wire clk0_raw = clkc[0];
    wire clk1_raw = clkc[1];

    PH1P_LOGIC_BUFG u_bufg_pixel (
        .i (clk0_raw),
        .o (pixel_clk)
    );

    assign serial_clk = clk1_raw;

    PH1P_PHY_PLL_V2 #(
        .FBKCLK                 ("CLKC0_EXT"    ),
        .FBKCLK_INT             ("CLKC0_EXT"    ),
        .FIN                    ("50.000000000"  ),
        .REFCLK_DIV             (2               ),
        .FBCLK_DIV              (1               ),

        .CLKC0_ENABLE           ("ENABLE"        ),
        .PREDIV_MUXC0           ("VCO"           ),
        .DIVOUT_MUXC0           ("DIV"           ),
        .CLKC0_DIV              (50              ),
        .CLKC0_CPHASE           (49              ),
        .CLKC0_FPHASE           (0               ),
        .CLKC0_FPHASE_RSTSEL    (0               ),
        .CLKC0_DUTY50           ("ENABLE"        ),
        .CLKC0_DUTY_INT         (25              ),

        .CLKC1_ENABLE           ("ENABLE"        ),
        .PREDIV_MUXC1           ("VCO"           ),
        .DIVOUT_MUXC1           ("DIV"           ),
        .CLKC1_DIV              (10              ),
        .CLKC1_CPHASE           (9               ),
        .CLKC1_FPHASE           (0               ),
        .CLKC1_FPHASE_RSTSEL    (0               ),
        .CLKC1_DUTY50           ("ENABLE"        ),
        .CLKC1_DUTY_INT         (5               ),

        .CLKC2_ENABLE           ("DISABLE"       ),
        .CLKC3_ENABLE           ("DISABLE"       ),
        .CLKC4_ENABLE           ("DISABLE"       ),
        .CLKC5_ENABLE           ("DISABLE"       ),
        .CLKC6_ENABLE           ("DISABLE"       ),

        .WORK_MODE              ("USER"          ),
        .PD_DIG                 ("ENABLE"        ),
        .PLL_USR_RST            ("ENABLE"        ),
        .PLL_FEED_TYPE          ("EXTERNAL"      ),
        .PLL_FASTLOOP           ("ENABLE"        ),

        .LPF_RES                (0               ),
        .LPF_CAP                (25              ),
        .ICP_CUR                (29              ),

        .FRAC_ENABLE            ("DISABLE"       ),
        .SDM_FRAC               (0               ),
        .PHASE_PATH_SEL         (0               ),
        .DYN_PHASE_PATH_SEL     ("DISABLE"       ),
        .DYN_FPHASE_EN          ("DISABLE"       ),
        .PI_OUT_SEL             ("NORMAL"        ),
        .PI_FRAC_EN             ("DISABLE"       ),
        .CLKC0_PI_SHIFT_EN      ("DISABLE"       ),
        .FEEDBK_MODE            ("NORMAL"        ),
        .DYN_CPHASE_EN          ("DISABLE"       )
    ) u_pll (
        .refclk         (clk_50m        ),
        .refclk_rst     (1'b0           ),
        .fbclk          (pixel_clk      ),
        .clkc           (clkc           ),
        .clkcb          (clkcb          ),
        .lock           (lock           ),
        .pllreset       (1'b0           ),
        .clkc_rst       (2'b00          ),
        .clkc_en        (7'b0000011     ),   // C0 + C1 enabled
        .wakeup         (1'b1           ),
        .cps_step       (1'b0           ),
        .pllpd          (1'b0           ),
        .drp_clk        (1'b0           ),
        .drp_rstn       (1'b1           ),
        .drp_sel        (1'b0           ),
        .drp_rd         (1'b0           ),
        .drp_wr         (1'b0           ),
        .drp_addr       (8'h00          ),
        .drp_wdata      (8'h00          ),
        .drp_err        (               ),
        .drp_rdy        (               ),
        .drp_rdata      (               ),
        .psdone         (               ),
        .psclk          (1'b0           ),
        .psdown         (1'b0           ),
        .psstep         (1'b0           ),
        .psclksel       (3'b000         ),
        .ssc_reset      (1'b0           ),
        .scan_clk       (1'b1           ),
        .scan_enable    (1'b1           ),
        .scan_mode      (1'b0           ),
        .scan_resetn    (1'b1           )
    );

endmodule
