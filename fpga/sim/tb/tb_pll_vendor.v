// ============================================================================
// tb_pll_vendor.v
// Configuration check for the synthesis PLL using TD's own functional model
// (PH1P_PHY_PLL_V2 in $TD_HOME/sim_release/ph1p/ph1p_phy_pll_v2.v).
//
// This is NOT the main logic simulation (that uses pll_hdmi_sim.v). It checks
// that the 50 MHz -> 25.0 MHz / 125.0 MHz integer configuration locks and
// produces the expected periods in the vendor model. The model's lock
// behaviour is a functional indication, not silicon jitter/lock evidence.
//
// Compile:
//   vlog -sv $TD_HOME/sim_release/ph1p/ph1p_phy_pll_v2.v \
//            fpga/sim/tb/tb_pll_vendor.v
//   vsim -c -do "run -all; quit" work.tb_pll_vendor
//
// The vendor model prints internal $hold timing-check messages during the
// reset sequence; they are model artifacts and do not stop this check.
// ============================================================================
`timescale 1ns / 1ps

module tb_pll_vendor;

    reg  clk_50m;
    wire [6:0] clkc;
    wire [6:0] clkcb;
    wire lock;

    integer errors;
    realtime t0, t1;
    real     c0_period;
    real     c1_period;

    initial clk_50m = 1'b0;
    always #10 clk_50m = ~clk_50m;   // 50 MHz

    PH1P_PHY_PLL_V2 #(
        .FBKCLK                 ("CLKC0_EXT"    ),
        .FBKCLK_INT             ("CLKC0_EXT"    ),
        .FIN                    ("50.000000000"  ),
        .REFCLK_DIV             (2               ),
        .FBCLK_DIV              (1               ),

        .CLKC0_ENABLE           ("ENABLE"        ),
        .CLKC0_DIV              (50              ),
        .CLKC0_CPHASE           (49              ),
        .CLKC0_FPHASE           (0               ),
        .CLKC0_FPHASE_RSTSEL    (0               ),
        .CLKC0_DUTY50           ("ENABLE"        ),
        .CLKC0_DUTY_INT         (25              ),

        .CLKC1_ENABLE           ("ENABLE"        ),
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
        .refclk         (clk_50m    ),
        .refclk_rst     (1'b0       ),
        .fbclk          (clkc[0]    ),
        .clkc           (clkc       ),
        .clkcb          (clkcb      ),
        .lock           (lock       ),
        .pllreset       (1'b0       ),
        .clkc_rst       (2'b00      ),
        .clkc_en        (7'b0000011 ),
        .wakeup         (1'b1       ),
        .cps_step       (1'b0       ),
        .pllpd          (1'b0       ),
        .drp_clk        (1'b0       ),
        .drp_rstn       (1'b1       ),
        .drp_sel        (1'b0       ),
        .drp_rd         (1'b0       ),
        .drp_wr         (1'b0       ),
        .drp_addr       (8'h00      ),
        .drp_wdata      (8'h00      ),
        .drp_err        (           ),
        .drp_rdy        (           ),
        .drp_rdata      (           ),
        .psdone         (           ),
        .psclk          (1'b0       ),
        .psdown         (1'b0       ),
        .psstep         (1'b0       ),
        .psclksel       (3'b000     ),
        .ssc_reset      (1'b0       ),
        .scan_clk       (1'b1       ),
        .scan_enable    (1'b1       ),
        .scan_mode      (1'b0       ),
        .scan_resetn    (1'b1       )
    );

    initial begin
        errors = 0;

        #150000;                     // vendor model locks at ~120 us

        if (lock !== 1'b1) begin
            $display("FAIL PLL lock = %b (expected 1)", lock);
            errors = errors + 1;
        end else begin
            $display("ok   PLL lock = 1");
        end

        @(posedge clkc[0]); t0 = $realtime;
        @(posedge clkc[0]); t1 = $realtime;
        c0_period = t1 - t0;
        if ((c0_period < 39.9) || (c0_period > 40.1)) begin
            $display("FAIL C0 period = %0.3f ns (expected 40.000)", c0_period);
            errors = errors + 1;
        end else begin
            $display("ok   C0 period = %0.3f ns", c0_period);
        end

        @(posedge clkc[1]); t0 = $realtime;
        @(posedge clkc[1]); t1 = $realtime;
        c1_period = t1 - t0;
        if ((c1_period < 7.9) || (c1_period > 8.1)) begin
            $display("FAIL C1 period = %0.3f ns (expected 8.000)", c1_period);
            errors = errors + 1;
        end else begin
            $display("ok   C1 period = %0.3f ns", c1_period);
        end

        if (errors == 0)
            $display("TB: PASS - pll_vendor (25.0/125.0 MHz, lock)");
        else
            $display("TB: FAIL - pll_vendor, errors=%0d", errors);

        $finish;
    end

endmodule
