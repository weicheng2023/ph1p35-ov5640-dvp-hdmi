# ============================================================================
# top_ddr_debug.sdc
#
# Board clock for the DDR status/debug top. The vendor IP SDC (ddr2.sdc) is
# read AFTER this file; it derives/renames the DDR PLL clocks and contains
# the single-group asynchronous constraint (appended by prepare_ddr_ip.sh).
#
# The timeout/status logic is in clk_50m only; ddrphy_rst_n/ddrphy_rdy are
# 2-flop synchronized into clk_50m in ddr_status_debug.v.
# ============================================================================

create_clock -name clk_50m -period 20.000 [get_ports clk_50m]
set_clock_uncertainty 0.200 [get_clocks clk_50m]

derive_clocks
