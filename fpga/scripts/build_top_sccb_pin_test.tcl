set bc_script_dir [file dirname [file normalize [info script]]]
set bc_fpga_dir   [file dirname $bc_script_dir]
set bc_repo_dir   [file dirname $bc_fpga_dir]
set bc_out_dir    [file join $bc_repo_dir build bitstream]
file mkdir $bc_out_dir
cd $bc_out_dir

set bc_top_v [file join $bc_fpga_dir rtl top top_sccb_pin_test.v]
set bc_adc   [file join $bc_fpga_dir constraints top_sccb_pin_test.adc]

import_device ph1_35p.db -package PH1P35MDG324 -speed 3
read_hdl -file $bc_top_v
read_adc $bc_adc
optimize_rtl
optimize_gate
legalize_phy_inst
place
route
bitgen -bit top_sccb_pin_test.bit
puts "=== DONE: top_sccb_pin_test.bit ==="
exit
