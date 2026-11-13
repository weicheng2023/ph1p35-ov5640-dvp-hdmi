# ============================================================================
# top_cam_fb_hdmi.sdc
# Timing constraints for Stage 3: OV5640 -> DDR double buffer -> HDMI.
#
# Clocks:
#   clk_50m  : C4, 50.000 MHz (20.000 ns). HDMI PLL reference and DDR ref_clk.
#   cam_pclk : F14, measured 48.000 MHz (20.833 ns).
#   pixel_clk / serial_clk : derived from the 25.0/125.0 MHz HDMI PLL.
#   dhi_clk / ctl_clk / ddr_clk / mcu_clk / ref_clk : vendor DDR IP PLL.
#
# CDC audit (this design):
#   cam_pclk -> dhi_clk (usr_clk) :
#       async_fifo_gray (129-bit, Gray pointers) for camera beats;
#       level synchronizers for cap_en (2FF) and buf_free (2FF);
#       rst_n is only an asynchronous reset.
#   dhi_clk -> pixel_clk :
#       async_fifo_gray (128-bit display FIFO, Gray pointers);
#       2FF single-bit flags (prefill_done, underflow, error categories).
#   dhi_clk internal : writer/reader ping-pong indices and the PAXI arbiter
#       are all in the same domain; no CDC.
#
#   The DDR clock relationships are owned by the vendor IP SDC (ddr2.sdc):
#   its own mcu_clk group plus the appended
#   {ddr_clk usr_clk ctl_clk mcu_clk ref_clk} group. TD 6.2.1 reports a
#   second design-level async group for usr_clk vs pixel_clk as INVALID /
#   redundant, so it is not added here (same decision as the Stage 2 build).
#
#   cam_pclk is declared asynchronous to the 50 MHz/system/HDMI group. The
#   only paths across that boundary are the Gray FIFO, 2FF levels and the
#   asynchronous reset; this is a CDC declaration, not a false path hiding a
#   synchronous path.
#
# DVP input delays are provisional (10/2 ns), same as top_dvp_test and
# top_ov5640_line_to_hdmi. They must be tightened after a real board delay
# measurement.
# ============================================================================

create_clock -name clk_50m  -period 20.000 [get_ports {clk_50m}]
create_clock -name cam_pclk -period 20.833 [get_ports {cam_pclk}]

set_clock_uncertainty 0.200 [get_clocks clk_50m]
# No extra uncertainty on cam_pclk: the board-proven line-capture SDC
# (top_ov5640_line_to_hdmi.sdc) does not add one either. cam_pclk is an
# external camera clock, not a PLL output.

set_input_delay -clock cam_pclk -max 10.000 [get_ports {cam_data[0] cam_data[1] cam_data[2] cam_data[3] cam_data[4] cam_data[5] cam_data[6] cam_data[7] cam_href cam_vsync}]
set_input_delay -clock cam_pclk -min  2.000 [get_ports {cam_data[0] cam_data[1] cam_data[2] cam_data[3] cam_data[4] cam_data[5] cam_data[6] cam_data[7] cam_href cam_vsync}]

# Derive pixel_clk/serial_clk (HDMI PLL) and the DDR IP clocks.
derive_clocks

# Give the two HDMI clocks stable names (same as the Stage 2 SDC).
if {[llength [get_clocks -quiet {u_core/u_hdmi_pll/u_pll.clkc[0]}]] > 0} {
    rename_clock -name pixel_clk [get_clocks {u_core/u_hdmi_pll/u_pll.clkc[0]}]
}
if {[llength [get_clocks -quiet {u_core/u_hdmi_pll/u_pll.clkc[1]}]] > 0} {
    rename_clock -name serial_clk [get_clocks {u_core/u_hdmi_pll/u_pll.clkc[1]}]
}

# Camera PCLK is asynchronous to the system/HDMI clock group.
set_clock_groups -asynchronous \
    -group [get_clocks {cam_pclk}] \
    -group [get_clocks -include_generated_clocks {clk_50m}]
