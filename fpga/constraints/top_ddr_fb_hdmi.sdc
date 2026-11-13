# ============================================================================
# top_ddr_fb_hdmi.sdc
# Timing constraints for the DDR frame buffer -> HDMI test.
#
# Input clock: C4 = 50.000 MHz (period 20.000 ns).
#   - clk_50m is the HDMI PLL reference and the DDR IP ref_clk.
#   - pll_hdmi derives pixel_clk 25.0 MHz and serial_clk 125.0 MHz.
#   - The DDR IP PLL derives usr_clk (dhi_clk, 133.333 MHz), ctl_clk,
#     ddr_clk, mcu_clk and ref_clk inside the vendor IP.
#
# CDC audit (no constraint hides a real synchronous path):
#   The ONLY paths crossing between the DDR user domain (usr_clk/dhi_clk)
#   and the HDMI pixel domain (pixel_clk) are:
#     - async_fifo_gray: Gray-coded pointers + dual-clock FIFO memory;
#     - 2FF synchronizers for ddrphy_rdy, reader_prefill_done, underflow,
#       fatal_dhi and display_error_dhi.
#     - rst_n (clk_50m POR) is used only as an asynchronous reset in the
#       other domains, never as data.
#   There are no shared counters or multi-bit data buses between these
#   domains.
#
#   The DDR clock relationships are owned by the vendor IP SDC
#   (ddr2.sdc): its own mcu_clk group plus the appended
#   {ddr_clk usr_clk ctl_clk mcu_clk ref_clk} single group (added by
#   prepare_ddr_ip.sh for the PHY init/cal usr_clk -> clk_50m paths).
#   TD 6.2.1 reports a second, design-level async group for
#   {usr_clk} vs {pixel_clk serial_clk} as an INVALID redundant constraint,
#   so it is deliberately not added here. The audit above is the
#   justification that the vendor boundary does not hide a real
#   synchronous path in this design.
#
#   pixel_clk and serial_clk are synchronous (5:1, same PLL) and their real
#   paths (TMDS encoder -> serializer load) stay timed.
#
# No external input/output delay is invented for the TMDS outputs: there is
# no board-level monitor-side timing specification.
# ============================================================================

create_clock -name clk_50m -period 20.000 [get_ports {clk_50m}]
set_clock_uncertainty 0.200 [get_clocks clk_50m]

# Derive pixel_clk/serial_clk from pll_hdmi. TD 6.2.1 marks
# derive_pll_clocks obsolete; derive_clocks handles PLL outputs.
derive_clocks

# TD names PLL output clocks after the PLL pins. Give the two HDMI clocks
# stable names so the explicit CDC group (appended to the build-time IP SDC
# copy, where usr_clk has been renamed) can reference them. The guards make
# the second read_sdc pass (after optimize_gate) a no-op.
if {[llength [get_clocks -quiet {u_core/u_hdmi_pll/u_pll.clkc[0]}]] > 0} {
    rename_clock -name pixel_clk [get_clocks {u_core/u_hdmi_pll/u_pll.clkc[0]}]
}
if {[llength [get_clocks -quiet {u_core/u_hdmi_pll/u_pll.clkc[1]}]] > 0} {
    rename_clock -name serial_clk [get_clocks {u_core/u_hdmi_pll/u_pll.clkc[1]}]
}
