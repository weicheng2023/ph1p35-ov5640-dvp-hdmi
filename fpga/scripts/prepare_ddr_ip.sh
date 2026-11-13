#!/usr/bin/env bash
# ============================================================================
# prepare_ddr_ip.sh
#
# Assemble the vendor-generated "PH1P35MDG324 Integrated" DDR2 512Mb x16
# IP into build/ddr_ip/ for the independent top_ddr_test build.
#
# The reference tree is a local, git-ignored third-party project that was
# generated for the same PH1P35MDG324 device. Its plain config files
# (cfg ROM, bus matrix, ddrio, pad type) are byte-identical to the TD
# MDG324 files. This script copies the generated tree to build/ddr_ip/.
#
# Interface choice: this tree uses the wrapper's simplified *native*
# paxi_* interface (word-addressed, no B channel), which is what the
# reference `ddr2.v` example drives. Do NOT define MC0_MIS_AXI: that
# switches the wrapper to the full AXI4 port set (axi_* with ID/len/size/
# burst/B channel) and requires the extra mc0_axi2mc adapter. The minimal
# pattern test targets the native paxi_* interface.
#
# Build artifacts under build/ are git-ignored. Do not commit the vendor
# IP, encrypted files, or bitstreams.
# ============================================================================
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "$script_dir/../.." && pwd)"
ref_dir="$repo_dir/build/ref/anlogic-ph1p35-vision/user_source/hdl_source/ph1p35_ddr/ddr2"
out_dir="$repo_dir/build/ddr_ip"
td_home="${TD_HOME:-D:/Software/Anlogic/TD_6.2.1}"
cal_dir="$td_home/ip/depot/MIS_DDRF6F1D0P0_1.1/PH1P_DDRPHY_IP/Other/ph1p_ddrphy_ip/cal"

if [ ! -f "$ref_dir/ph1p_ddrmc_wrapper_63f4ac254419.v" ]; then
    echo "ERROR: reference DDR IP tree not found: $ref_dir" >&2
    echo "Set up build/ref/anlogic-ph1p35-vision or point this script at a" >&2
    echo "TD-generated PH1P35MDG324 Integrated DDR2 IP tree." >&2
    exit 1
fi

if [ ! -d "$cal_dir" ]; then
    echo "ERROR: TD DDR PHY calibration sources not found: $cal_dir" >&2
    echo "Check TD_HOME (current: $td_home)." >&2
    exit 1
fi

rm -rf "$out_dir"
mkdir -p "$out_dir"
cp -r "$ref_dir"/* "$out_dir"/

# The reference tree was generated with CAL_EN=0 and lacks the PHY
# calibration modules. The minimal test enables CAL_EN=1, so add the
# vendor calibration RTL from the TD installation.
mkdir -p "$out_dir/src/rtl/cal"
cp "$cal_dir"/*.v "$out_dir/src/rtl/cal/"

# The reference tree was generated with CAL_EN=0 and its IP SDC only groups
# mcu_clk. The minimal test enables CAL_EN=1, and the PHY initialization/
# calibration logic has CDC paths between usr_clk and the 50 MHz ref clock.
# Parse this group inside the IP SDC context, where the renamed clocks exist.
cat >> "$out_dir/src/sdc/ddr2.sdc" <<'EOF'

# Minimal DDR test: DDR PHY/MC clocks are asynchronous to the 50 MHz
# ref/POR domain. Single group => asynchronous to every clock outside it.
set_clock_groups -asynchronous -group [get_clocks {ddr_clk usr_clk ctl_clk mcu_clk ref_clk}]
EOF

echo "Prepared DDR IP at: $out_dir"
echo "Defines:"
grep -E '^`define' "$out_dir/src/rtl/include/ph1p_mis_define.vh"
