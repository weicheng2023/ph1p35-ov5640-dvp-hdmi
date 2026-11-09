# ============================================================================
# top_hdmi_colorbar.sdc
# Timing constraints for the independent HDMI color-bar source.
#
# Input clock: C4 = 50.000 MHz (period 20.000 ns).
# PLL outputs (derived by TD from PH1P_PHY_PLL_V2 parameters):
#   pixel_clk  = 25.000 MHz (period 40.0000 ns)
#   serial_clk = 125.000 MHz (period 8.0000 ns)
#
# pixel_clk and serial_clk come from the same PLL and are synchronous
# (5:1). The TMDS encoder outputs are stable for a full pixel period and
# are captured by the shared, toggle-synchronised load pulse. No false
# paths are used to hide timing.
#
# The TMDS outputs are DDR serial data at 125 MHz. There is no board-level
# input/output delay specification for the monitor side, so no external
# output delay is invented here.
# ============================================================================

create_clock -name clk_50m -period 20.000 [get_ports {clk_50m}]

# Derive pixel_clk and serial_clk from the PLL instance.
# TD 6.2.1 marks derive_pll_clocks obsolete; derive_clocks handles the PLL
# outputs and reports the same 25.0 / 125.0 MHz clocks.
derive_clocks
