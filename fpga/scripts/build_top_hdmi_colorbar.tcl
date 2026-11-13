# ============================================================================
# build_top_hdmi_colorbar.tcl
# Build the independent HDMI color-bar source with TD 6.2.1.
#
# Usage:
#   td_commands_prompt.exe fpga/scripts/build_top_hdmi_colorbar.tcl
# or double-click build_top_hdmi_colorbar.bat.
#
# Outputs (git-ignored):
#   build/bitstream/top_hdmi_colorbar.bit
#   build/bitstream/top_hdmi_colorbar_route.qor
#   build/bitstream/top_hdmi_colorbar_final_timing.rpt
# ============================================================================

set bc_script_dir [file dirname [file normalize [info script]]]
set bc_fpga_dir   [file dirname $bc_script_dir]
set bc_repo_dir   [file dirname $bc_fpga_dir]
set bc_rtl_dir    [file join $bc_fpga_dir rtl]
set bc_con_dir    [file join $bc_fpga_dir constraints]
set bc_out_dir    [file join $bc_repo_dir build bitstream]

file mkdir $bc_out_dir
cd $bc_out_dir

set bc_top_v    [file join $bc_rtl_dir top     top_hdmi_colorbar.v]
set bc_timing_v [file join $bc_rtl_dir display video_timing.v]
set bc_bar_v    [file join $bc_rtl_dir display color_bar.v]
set bc_enc_v    [file join $bc_rtl_dir display tmds_encoder.v]
set bc_ser_v    [file join $bc_rtl_dir display tmds_serializer.v]
set bc_load_v   [file join $bc_rtl_dir display serial_load_gen.v]
set bc_pll_v    [file join $bc_rtl_dir display pll_hdmi.v]
set bc_adc      [file join $bc_con_dir top_hdmi_colorbar.adc]
set bc_sdc      [file join $bc_con_dir top_hdmi_colorbar.sdc]

set bc_hdl_files "$bc_top_v $bc_timing_v $bc_bar_v $bc_enc_v $bc_ser_v $bc_load_v $bc_pll_v"

puts "=== build_top_hdmi_colorbar ==="
puts "repo: $bc_repo_dir"
puts "out : $bc_out_dir"
puts "hdl : $bc_hdl_files"
puts "adc : $bc_adc"
puts "sdc : $bc_sdc"

import_device ph1_35p.db -package PH1P35MDG324 -speed 3

read_hdl -file $bc_hdl_files

read_adc $bc_adc
optimize_rtl

read_sdc $bc_sdc
optimize_gate
legalize_phy_inst
read_sdc $bc_sdc

place
route

report_qor -step route -file top_hdmi_colorbar_route.qor
report_timing_summary -file top_hdmi_colorbar_final_timing.rpt
check_timing
write_csv top_hdmi_colorbar_netlist.csv
bitgen -bit top_hdmi_colorbar.bit

puts "=== DONE: top_hdmi_colorbar.bit ==="
exit
