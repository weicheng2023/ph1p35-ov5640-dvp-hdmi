# ============================================================================
# build_top_ov5640_line_to_hdmi.tcl
# Build "OV5640 internal color bar -> one-line buffer -> proven HDMI" with
# TD 6.2.1.
#
# Usage:
#   td_commands_prompt.exe fpga/scripts/build_top_ov5640_line_to_hdmi.tcl
# or double-click build_top_ov5640_line_to_hdmi.bat.
#
# Outputs (git-ignored):
#   build/bitstream/top_ov5640_line_to_hdmi.bit
#   build/bitstream/top_ov5640_line_to_hdmi_route.qor
#   build/bitstream/top_ov5640_line_to_hdmi_final_timing.rpt
#   build/bitstream/top_ov5640_line_to_hdmi_route.check_timing
# ============================================================================

set bc_script_dir [file dirname [file normalize [info script]]]
set bc_fpga_dir   [file dirname $bc_script_dir]
set bc_repo_dir   [file dirname $bc_fpga_dir]
set bc_rtl_dir    [file join $bc_fpga_dir rtl]
set bc_con_dir    [file join $bc_fpga_dir constraints]
set bc_out_dir    [file join $bc_repo_dir build bitstream]

file mkdir $bc_out_dir
cd $bc_out_dir

set bc_top_v    [file join $bc_rtl_dir top     top_ov5640_line_to_hdmi.v]
set bc_core_v   [file join $bc_rtl_dir top     ov5640_line_to_hdmi_core.v]
set bc_bring_v  [file join $bc_rtl_dir camera  ov5640_bringup.v]
set bc_cfg_v    [file join $bc_rtl_dir camera  ov5640_cfg.v]
set bc_rom_v    [file join $bc_rtl_dir camera  ov5640_cfg_rom.v]
set bc_id_v     [file join $bc_rtl_dir camera  ov5640_id_reader.v]
set bc_sccb_v   [file join $bc_rtl_dir camera  sccb_master.v]
set bc_line_v   [file join $bc_rtl_dir camera  ov5640_line_capture.v]
set bc_ram_v    [file join $bc_rtl_dir common  line_buffer_dpram.v]
set bc_timing_v [file join $bc_rtl_dir display video_timing.v]
set bc_cvt_v    [file join $bc_rtl_dir display rgb565_to_rgb888.v]
set bc_enc_v    [file join $bc_rtl_dir display tmds_encoder.v]
set bc_ser_v    [file join $bc_rtl_dir display tmds_serializer.v]
set bc_load_v   [file join $bc_rtl_dir display serial_load_gen.v]
set bc_pll_v    [file join $bc_rtl_dir display pll_hdmi.v]

set bc_adc      [file join $bc_con_dir top_ov5640_line_to_hdmi.adc]
set bc_sdc      [file join $bc_con_dir top_ov5640_line_to_hdmi.sdc]

set bc_hdl_files "$bc_top_v $bc_core_v $bc_bring_v $bc_cfg_v $bc_rom_v $bc_id_v $bc_sccb_v $bc_line_v $bc_ram_v $bc_timing_v $bc_cvt_v $bc_enc_v $bc_ser_v $bc_load_v $bc_pll_v"

puts "=== build_top_ov5640_line_to_hdmi ==="
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

report_qor -step route -file top_ov5640_line_to_hdmi_route.qor
report_timing_summary -file top_ov5640_line_to_hdmi_final_timing.rpt
check_timing
write_csv top_ov5640_line_to_hdmi_netlist.csv
bitgen -bit top_ov5640_line_to_hdmi.bit

puts "=== DONE: top_ov5640_line_to_hdmi.bit ==="
exit
