# ============================================================================
# top_ov5640_line_to_hdmi.sdc
# Timing constraints for OV5640 line capture -> HDMI.
#
# Clocks:
#   clk_50m  : C4, 50.000 MHz (20.000 ns)
#   cam_pclk : F14, measured 48.000 MHz (20.833 ns)
#   pixel_clk / serial_clk : derived from the 25.0/125.0 MHz PLL
#
# The camera PCLK and the HDMI clocks are asynchronous. The line buffer is a
# true dual-port RAM (write cam_pclk, read pixel_clk), and capture_done is
# synchronized with two flops. The clock-group constraint is the CDC
# declaration for those structures, not a false path used to hide a timing
# problem.
#
# DVP input delays are still provisional (10/2 ns), same as top_dvp_test.
# They must be tightened after a real board delay measurement.
# ============================================================================

create_clock -name clk_50m  -period 20.000 [get_ports {clk_50m}]
create_clock -name cam_pclk -period 20.833 [get_ports {cam_pclk}]

set_input_delay -clock cam_pclk -max 10.000 [get_ports {cam_data[0] cam_data[1] cam_data[2] cam_data[3] cam_data[4] cam_data[5] cam_data[6] cam_data[7] cam_href cam_vsync}]
set_input_delay -clock cam_pclk -min  2.000 [get_ports {cam_data[0] cam_data[1] cam_data[2] cam_data[3] cam_data[4] cam_data[5] cam_data[6] cam_data[7] cam_href cam_vsync}]

# Derive pixel_clk and serial_clk from the PLL instance.
derive_clocks

# PCLK is asynchronous to the 50 MHz/system/PLL clocks.
set_clock_groups -asynchronous \
    -group [get_clocks {cam_pclk}] \
    -group [get_clocks -include_generated_clocks {clk_50m}]
