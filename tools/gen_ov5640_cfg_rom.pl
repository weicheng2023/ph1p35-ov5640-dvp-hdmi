#!/usr/bin/perl
# Generate fpga/rtl/camera/ov5640_cfg_rom.v from a reviewed reference table.
#
# The reference is the ALIENTEK OV5640 RGB565 configuration table (V1.0,
# 2020-05-04). Only register values are extracted; the generated module has its
# own structure. The source file is not stored in this repository.
#
# Usage:
#   perl tools/gen_ov5640_cfg_rom.pl <reference_cfg.v> <output.v>
#
# Deviations from the reference table:
#   - Dummy writes to 0x300A/0x300B at indices 0 and 1 are not emitted.
#   - 0x4740 is written explicitly as 0x22 (PCLK/HREF active high, VSYNC active
#     low), matching the measured LA polarity.
#   - 0x503D is parameterised by COLOR_BAR.
#   - 0x3808..0x380F are parameterised by H_PIX/V_PIX/H_TOTAL/V_TOTAL.

use strict;
use warnings;

my ($src, $out) = @ARGV;
die "usage: $0 <reference_cfg.v> <output.v>\n" unless defined $out;

open my $in, '<:raw', $src or die "open $src: $!\n";
my %entries;
while (my $line = <$in>) {
    if ($line =~ /\b8'd(\d+)\s*:\s*i2c_data\s*<=\s*\{\s*16'h([0-9a-fA-F]+)\s*,\s*8'h([0-9a-fA-F]+)\s*\}\s*;/) {
        my ($idx, $reg, $data) = ($1, hex($2), hex($3));
        $entries{$idx} = [$reg, sprintf("8'h%02X", $data)];
    }
}
close $in;
die "no register entries found\n" unless %entries;

# The reference writes 0x3017 as {8'h30, 8'h17, 8'hFF}, which the simple
# 16-bit-address pattern does not match. Add it explicitly.
$entries{5} = [0x3017, "8'hFF"];

# Parameterised geometry entries. Indices 220..227 in the reference table.
my %geom = (
    0x3808 => "{4'd0, h_pix[11:8]}",
    0x3809 => "h_pix[7:0]",
    0x380A => "{5'd0, v_pix[10:8]}",
    0x380B => "v_pix[7:0]",
    0x380C => "{3'd0, h_total[12:8]}",
    0x380D => "h_total[7:0]",
    0x380E => "{3'd0, v_total[12:8]}",
    0x380F => "v_total[7:0]",
);
for my $idx (220 .. 227) {
    my $reg = 0x3808 + ($idx - 220);
    $entries{$idx} = [$reg, $geom{$reg}] if exists $geom{$reg};
}

# Build the final ordered list with our deviations.
my @ordered;
my $inserted = 0;
for my $idx (sort { $a <=> $b } keys %entries) {
    next if $idx == 0 || $idx == 1;    # dummy Chip ID writes
    my ($reg, $expr) = @{ $entries{$idx} };
    if ($reg == 0x503D) {
        push @ordered, [0x4740, "8'h22"] unless $inserted;
        $inserted = 1;
        push @ordered, [0x503D, "COLOR_BAR ? 8'h80 : 8'h00"];
    } else {
        push @ordered, [$reg, $expr];
    }
}
unless ($inserted) {
    push @ordered, [0x4740, "8'h22"];
    push @ordered, [0x503D, "COLOR_BAR ? 8'h80 : 8'h00"];
}

open my $fh, '>:raw', $out or die "open $out: $!\n";
print $fh "// ============================================================================\n";
print $fh "// ov5640_cfg_rom.v\n";
print $fh "// GENERATED FILE - do not edit by hand.\n";
print $fh "// Generator: tools/gen_ov5640_cfg_rom.pl\n";
print $fh "// Source: ALIENTEK OV5640 FPGA driver V1.0 (2020-05-04) RGB565 table,\n";
print $fh "//         values cross-checked against OV5640 Product Specification V2.03.\n";
print $fh "// Deviations: 0x4740=0x22 (HREF/PCLK active high, VSYNC active low),\n";
print $fh "//             0x503D by COLOR_BAR, geometry by parameters, dummy\n";
print $fh "//             0x300A/0x300B writes omitted.\n";
print $fh "// ============================================================================\n";
print $fh "`timescale 1ns / 1ps\n\n";
print $fh "module ov5640_cfg_rom #(\n";
print $fh "    parameter integer H_PIX     = 640,\n";
print $fh "    parameter integer V_PIX     = 480,\n";
print $fh "    parameter integer H_TOTAL   = 1600,\n";
print $fh "    parameter integer V_TOTAL   = 1000,\n";
print $fh "    parameter integer COLOR_BAR = 0\n";
print $fh ") (\n";
print $fh "    input  wire [7:0]  idx,\n";
print $fh "    output reg  [23:0] word\n";
print $fh ");\n\n";
print $fh "    wire [12:0] h_pix   = H_PIX;\n";
print $fh "    wire [12:0] v_pix   = V_PIX;\n";
print $fh "    wire [12:0] h_total = H_TOTAL;\n";
print $fh "    wire [12:0] v_total = V_TOTAL;\n\n";
print $fh "    always @* begin\n";
print $fh "        case (idx)\n";
my $i = 0;
for my $e (@ordered) {
    my ($reg, $expr) = @$e;
    printf $fh "            8'd%d: word = {16'h%04X, %s};\n", $i, $reg, $expr;
    $i++;
}
print $fh "            default: word = 24'hFFFFFF;\n";
print $fh "        endcase\n";
print $fh "    end\n\n";
print $fh "endmodule\n";
close $fh;

print "wrote $out: " . scalar(@ordered) . " entries\n";
