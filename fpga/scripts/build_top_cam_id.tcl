# ============================================================================
# build_top_cam_id.tcl
# Build top_cam_id with TD 6.2.1 command line (validated on 2026-10-24).
#
# Usage:
#   td_commands_prompt.exe fpga/scripts/build_top_cam_id.tcl
# or double-click build_top_cam_id.bat.
#
# Outputs (git-ignored):
#   build/bitstream/top_cam_id.bit
#   build/bitstream/top_cam_id_route.qor
#   build/bitstream/top_cam_id_final_timing.rpt
#
# Note: all Tcl variable names use the bc_ prefix to avoid collisions with
#       TD's own global variables (e.g. out_dir).
# ============================================================================

set bc_script_dir [file dirname [file normalize [info script]]]
set bc_fpga_dir   [file dirname $bc_script_dir]
set bc_repo_dir   [file dirname $bc_fpga_dir]
set bc_rtl_dir    [file join $bc_fpga_dir rtl]
set bc_con_dir    [file join $bc_fpga_dir constraints]
set bc_out_dir    [file join $bc_repo_dir build bitstream]

file mkdir $bc_out_dir
cd $bc_out_dir

set bc_top_v    [file join $bc_rtl_dir top top_cam_id.v]
set bc_sccb_v   [file join $bc_rtl_dir camera sccb_master.v]
set bc_reader_v [file join $bc_rtl_dir camera ov5640_id_reader.v]
set bc_adc      [file join $bc_con_dir top_cam_id.adc]
set bc_sdc      [file join $bc_con_dir top_cam_id.sdc]

set bc_hdl_files "$bc_top_v $bc_sccb_v $bc_reader_v"

puts "=== build_top_cam_id ==="
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

report_qor -step route -file top_cam_id_route.qor
report_timing_summary -file top_cam_id_final_timing.rpt
bitgen -bit top_cam_id.bit

puts "=== DONE: top_cam_id.bit ==="
exit
