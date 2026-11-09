# ============================================================================
# top_ddr_test.sdc
#
# Board clock for the independent DDR bring-up test.
# The vendor IP SDC (ddr2.sdc) is read AFTER this file; it derives/renames
# the DDR PLL clocks and adds the IP's asynchronous group.
#
# clk_50m (C4) is both the IP ref_clk and the APB clock. The IP PLL
# generates the DDR/MC clocks; the AXI pattern test runs in dhi_clk.
# ============================================================================

create_clock -name clk_50m -period 20.000 [get_ports clk_50m]
set_clock_uncertainty 0.200 [get_clocks clk_50m]

# Derive the PLL clocks; the vendor SDC repeats this and renames the
# PLL0/PLL1 outputs. The DDR-async clock group is appended to the IP SDC
# copy (build/ddr_ip/src/sdc/ddr2.sdc), where the renamed clocks exist in
# the IP SDC context.
derive_clocks
