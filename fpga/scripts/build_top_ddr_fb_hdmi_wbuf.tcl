# ============================================================================
# build_top_ddr_fb_hdmi_wbuf.tcl
#
# EXPERIMENTAL build: the Stage 2 DDR frame buffer -> HDMI test image, with
# the registered 128-bit word-buffer pixel gearbox (pixel_gearbox_wbuf).
#
# This is a separate top (top_ddr_fb_hdmi_wbuf) and writes separate output
# files. It does NOT overwrite build/bitstream/
# top_ddr_fb_hdmi_paxi_fix_20261109.bit (the board-proven Stage 2 build).
#
# Everything else (vendor DDR2 512Mb x16 IP, CAL_EN=0, 50 MHz reference,
# HDMI PLL, TMDS chain, video timing, PAXI contract, pin constraints) is
# identical to build_top_ddr_fb_hdmi.tcl. The same ADC/SDC files are
# reused: the pin list is top-independent and the SDC clock paths reference
# u_core/u_hdmi_pll/u_pll, which this top keeps.
#
# Outputs (git-ignored):
#   build/bitstream/top_ddr_fb_hdmi_wbuf_20261109.bit
#   build/bitstream/top_ddr_fb_hdmi_wbuf_20261109_route.qor
#   build/bitstream/top_ddr_fb_hdmi_wbuf_20261109_final_timing.rpt
#   build/bitstream/top_ddr_fb_hdmi_wbuf_20261109_route.check_timing
# ============================================================================

set dt_script_dir [file dirname [file normalize [info script]]]
set dt_fpga_dir   [file dirname $dt_script_dir]
set dt_repo_dir   [file dirname $dt_fpga_dir]
set dt_rtl_dir    [file join $dt_fpga_dir rtl]
set dt_con_dir    [file join $dt_fpga_dir constraints]
set dt_ip_dir     [file join $dt_repo_dir build ddr_ip]
set dt_out_dir    [file join $dt_repo_dir build bitstream]
set dt_inc_dir    [file join $dt_repo_dir build ddr_ip_inc]

if {![file exists [file join $dt_ip_dir src rtl phy ph1p_ddrphy_top.v]]} {
    puts "ERROR: DDR IP tree not found under $dt_ip_dir"
    puts "Run fpga/scripts/prepare_ddr_ip.sh first (see docs/display/ddr-investigation.md)."
    exit 1
}

file mkdir $dt_out_dir
file mkdir $dt_inc_dir
cd $dt_out_dir

# $readmemh("ddrphy_cfg_rom.txt") is relative to the build directory.
file copy -force [file join $dt_ip_dir src rtl phy ddrphy_cfg_rom.txt] \
                 [file join $dt_out_dir ddrphy_cfg_rom.txt]

foreach f [glob -nocomplain [file join $dt_ip_dir src rtl include *.vh]] {
    file copy -force $f [file join $dt_inc_dir [file tail $f]]
}
foreach f [glob -nocomplain [file join $dt_ip_dir src rtl phy include *.vh]] {
    file copy -force $f [file join $dt_inc_dir [file tail $f]]
}
foreach f [glob -nocomplain [file join $dt_ip_dir src rtl timing ddr2 *.vh]] {
    file copy -force $f [file join $dt_inc_dir [file tail $f]]
}

set dt_top_v      [file join $dt_rtl_dir top     top_ddr_fb_hdmi_wbuf.v]
set dt_core_v     [file join $dt_rtl_dir fb      ddr_fb_hdmi_core.v]
set dt_ddr2_v     [file join $dt_rtl_dir ddr     ddr2_top.v]
set dt_pattern_v  [file join $dt_rtl_dir ddr     ddr_axi_pattern_test.v]
set dt_fbpat_v    [file join $dt_rtl_dir ddr     fb_pattern.v]
set dt_crc_v      [file join $dt_rtl_dir ddr     crc32_16.v]
set dt_writer_v   [file join $dt_rtl_dir ddr     fb_writer.v]
set dt_reader_v   [file join $dt_rtl_dir ddr     fb_reader.v]
set dt_gearbox_v  [file join $dt_rtl_dir ddr     pixel_gearbox.v]
set dt_wbuf_v     [file join $dt_rtl_dir ddr     pixel_gearbox_wbuf.v]
set dt_fifo_v     [file join $dt_rtl_dir common  async_fifo_gray.v]
set dt_cvt_v      [file join $dt_rtl_dir display rgb565_to_rgb888.v]
set dt_pll_v      [file join $dt_rtl_dir display pll_hdmi.v]
set dt_timing_v   [file join $dt_rtl_dir display video_timing.v]
set dt_enc_v      [file join $dt_rtl_dir display tmds_encoder.v]
set dt_load_v     [file join $dt_rtl_dir display serial_load_gen.v]
set dt_ser_v      [file join $dt_rtl_dir display tmds_serializer.v]

set dt_adc        [file join $dt_con_dir top_ddr_fb_hdmi.adc]
set dt_sdc        [file join $dt_con_dir top_ddr_fb_hdmi.sdc]
set dt_ip_adc     [file join $dt_ip_dir src adc ddr2.adc]
set dt_ip_sdc     [file join $dt_ip_dir src sdc ddr2.sdc]

set dt_ip_files [list \
    [file join $dt_ip_dir ph1p_ddrmc_wrapper_63f4ac254419.v] \
    [file join $dt_ip_dir src rtl top ph1p_ddrmc_top.v] \
    [file join $dt_ip_dir src rtl clk ph1p_ddrphy_clk_top.v] \
    [file join $dt_ip_dir src rtl clk ph1p_ddrphy_pll0.v] \
    [file join $dt_ip_dir src rtl clk ph1p_ddrphy_pll1.v] \
    [file join $dt_ip_dir src rtl init ph1p_ddrphy_dram_init_ddr2.v] \
    [file join $dt_ip_dir src rtl misc ph1p_ddrphy_sync_rst_gen.v] \
    [file join $dt_ip_dir src rtl misc ph1p_ddr_fifo_dram_sync.v] \
    [file join $dt_ip_dir src rtl mc alc_mc_top_all.enc.sv] \
    [file join $dt_ip_dir src rtl mc alc_phy2mc_fifo_ctrl.v] \
    [file join $dt_ip_dir src rtl phy ph1p_ddrphy_wrapper.v] \
    [file join $dt_ip_dir src rtl phy ph1p_ddrphy_apb_bridge.v] \
    [file join $dt_ip_dir src rtl phy ph1p_ddrphy_bankref_cfg.v] \
    [file join $dt_ip_dir src rtl phy ph1p_ddrphy_init.v] \
    [file join $dt_ip_dir src rtl phy ph1p_ddrphy_mdl_cal.v] \
    [file join $dt_ip_dir src rtl phy ph1p_ddrphy_mdl_cal_wrapper.v] \
    [file join $dt_ip_dir src rtl phy ph1p_ddrphy_fast_init.v] \
    [file join $dt_ip_dir src rtl phy ph1p_ddrphy_fast_init_wrapper.v] \
    [file join $dt_ip_dir src rtl phy ph1p_ddrphy_dcu.v] \
    [file join $dt_ip_dir src rtl phy ph1p_ddrphy_dcu_wrapper.v] \
    [file join $dt_ip_dir src rtl phy ph1p_ddrphy_wphase_ctl.v] \
    [file join $dt_ip_dir src rtl phy ph1p_ddrphy_rphase_ctl.v] \
    [file join $dt_ip_dir src rtl phy ph1p_ddrphy_cmd_decode.v] \
    [file join $dt_ip_dir src rtl phy ph1p_ddrphy_cmd_execution.v] \
    [file join $dt_ip_dir src rtl phy ph1p_ddrphy_cmd_wrapper.v] \
    [file join $dt_ip_dir src rtl phy ph1p_ddrphy_byte_wrapper.v] \
    [file join $dt_ip_dir src rtl phy ph1p_ddrphy.v] \
    [file join $dt_ip_dir src rtl phy ph1p_ddrphy_top.v] \
    [file join $dt_ip_dir src rtl cal ph1p_ddrphy_cal_wrapper.v] \
    [file join $dt_ip_dir src rtl cal ph1p_ddrphy_cal_gate.v] \
    [file join $dt_ip_dir src rtl cal ph1p_ddrphy_cal_gate_wrapper.v] \
    [file join $dt_ip_dir src rtl cal ph1p_ddrphy_cal_wla.v] \
    [file join $dt_ip_dir src rtl cal ph1p_ddrphy_cal_wla_wrapper.v] \
    [file join $dt_ip_dir src rtl cal ph1p_ddrphy_cal_wrlvl.v] \
    [file join $dt_ip_dir src rtl cal ph1p_ddrphy_cal_wrlvl_wrapper.v] \
]

set dt_hdl_files [concat [list \
    $dt_top_v $dt_core_v $dt_ddr2_v $dt_pattern_v $dt_fbpat_v $dt_crc_v \
    $dt_writer_v $dt_reader_v $dt_gearbox_v $dt_wbuf_v $dt_fifo_v $dt_cvt_v \
    $dt_pll_v $dt_timing_v $dt_enc_v $dt_load_v $dt_ser_v] $dt_ip_files]
set dt_hdl_str [join $dt_hdl_files " "]

puts "=== build_top_ddr_fb_hdmi_wbuf (EXPERIMENTAL) ==="
puts "hdl: [llength $dt_hdl_files] files"
puts "out : $dt_out_dir"

import_device ph1_35p.db -package PH1P35MDG324 -speed 3

read_hdl -file $dt_hdl_str -include_dir $dt_inc_dir -top top_ddr_fb_hdmi_wbuf

puts "adc : $dt_adc"
puts "sdc : $dt_sdc"
puts "len : [string length $dt_adc]"
read_adc $dt_adc
read_ip_adc -ip ddr2 -file $dt_ip_adc
optimize_rtl

read_sdc $dt_sdc
read_sdc -ip ddr2 $dt_ip_sdc
optimize_gate
legalize_phy_inst
read_sdc $dt_sdc
read_sdc -ip ddr2 $dt_ip_sdc

place
route

report_qor -step route -file top_ddr_fb_hdmi_wbuf_20261109_route.qor
report_timing_summary -file top_ddr_fb_hdmi_wbuf_20261109_final_timing.rpt
check_timing
file copy -force top_ddr_fb_hdmi_wbuf_route.check_timing \
                 top_ddr_fb_hdmi_wbuf_20261109_route.check_timing
write_csv top_ddr_fb_hdmi_wbuf_20261109_netlist.csv
bitgen -bit top_ddr_fb_hdmi_wbuf_20261109.bit

puts "=== DONE: top_ddr_fb_hdmi_wbuf_20261109.bit ==="
exit
