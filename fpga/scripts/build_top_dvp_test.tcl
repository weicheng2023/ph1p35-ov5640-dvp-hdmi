# ============================================================================
# build_top_dvp_test.tcl
# Build top_dvp_test with TD 6.2.1 command line.
#
# Usage:
#   td_commands_prompt.exe fpga/scripts/build_top_dvp_test.tcl
# or double-click build_top_dvp_test.bat.
#
# Outputs (git-ignored):
#   build/bitstream/top_dvp_test.bit
#   build/bitstream/top_dvp_test_route.qor
#   build/bitstream/top_dvp_test_final_timing.rpt
# ============================================================================

set bc_script_dir [file dirname [file normalize [info script]]]
set bc_fpga_dir   [file dirname $bc_script_dir]
set bc_repo_dir   [file dirname $bc_fpga_dir]
set bc_rtl_dir    [file join $bc_fpga_dir rtl]
set bc_con_dir    [file join $bc_fpga_dir constraints]
set bc_out_dir    [file join $bc_repo_dir build bitstream]

file mkdir $bc_out_dir
cd $bc_out_dir

set bc_top_v    [file join $bc_rtl_dir top top_dvp_test.v]
set bc_bring_v  [file join $bc_rtl_dir camera ov5640_bringup.v]
set bc_cfg_v    [file join $bc_rtl_dir camera ov5640_cfg.v]
set bc_rom_v    [file join $bc_rtl_dir camera ov5640_cfg_rom.v]
set bc_id_v     [file join $bc_rtl_dir camera ov5640_id_reader.v]
set bc_sccb_v   [file join $bc_rtl_dir camera sccb_master.v]
set bc_cap_v    [file join $bc_rtl_dir camera dvp_capture.v]
set bc_mon_v    [file join $bc_rtl_dir camera dvp_status_monitor.v]
set bc_fifo_v   [file join $bc_rtl_dir common async_fifo_gray.v]
set bc_adc      [file join $bc_con_dir top_dvp_test.adc]
set bc_sdc      [file join $bc_con_dir top_dvp_test.sdc]

set bc_hdl_files "$bc_top_v $bc_bring_v $bc_cfg_v $bc_rom_v $bc_id_v $bc_sccb_v $bc_cap_v $bc_mon_v $bc_fifo_v"

puts "=== build_top_dvp_test ==="
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

report_qor -step route -file top_dvp_test_route.qor
report_timing_summary -file top_dvp_test_final_timing.rpt
bitgen -bit top_dvp_test.bit

puts "=== DONE: top_dvp_test.bit ==="
exit
