#!/usr/bin/perl
# Stream an ATK logic-analyzer CSV export and summarize PCLK/VSYNC/HREF.
#
# Columns: SystemTime, Time(s), Channel 0 (PCLK), Channel 1 (VSYNC),
#          Channel 2 (HREF)
#
# Usage:
#   perl tools/analyze_la_csv.pl <capture.csv>
#
# The CSV is a transition list at the sample rate (200 MHz -> 5 ns grid).
# This script does not load the file into memory.
use strict;
use warnings;

my $path = $ARGV[0] or die "usage: $0 <capture.csv>\n";
open my $fh, '<:raw', $path or die "open $path: $!\n";

my @state       = (0, 0, 0);       # Ch0 PCLK, Ch1 VSYNC, Ch2 HREF
my @last_change = (-1, -1, -1);
my @seen        = (0, 0, 0);
my @last_rise   = (-1, -1, -1);
my @last_fall   = (-1, -1, -1);
my @rise_cnt    = (0, 0, 0);
my @fall_cnt    = (0, 0, 0);

my @hi_min = (1e18, 1e18, 1e18);
my @hi_max = (0, 0, 0);
my @hi_sum = (0, 0, 0);
my @hi_cnt = (0, 0, 0);
my @lo_min = (1e18, 1e18, 1e18);
my @lo_max = (0, 0, 0);
my @lo_sum = (0, 0, 0);
my @lo_cnt = (0, 0, 0);

my @rp_min = (1e18, 1e18, 1e18);
my @rp_max = (0, 0, 0);
my @rp_sum = (0, 0, 0);
my @rp_cnt = (0, 0, 0);
my @fp_min = (1e18, 1e18, 1e18);
my @fp_max = (0, 0, 0);
my @fp_sum = (0, 0, 0);
my @fp_cnt = (0, 0, 0);

my $pclk_last_rise = -1;
my $pclk_p_min = 1e18;
my $pclk_p_max = 0;
my $pclk_p_sum = 0;
my $pclk_p_cnt = 0;

my $href_pclk = 0;
my $href_pclk_min = 1e18;
my $href_pclk_max = 0;
my $href_pclk_sum = 0;
my $href_pclk_cnt = 0;

my $lines_rise = 0;
my $lines_fall = 0;
my $lines_rise_min = 1e18;
my $lines_rise_max = 0;
my $lines_rise_sum = 0;
my $lines_rise_cnt = 0;
my $lines_fall_min = 1e18;
my $lines_fall_max = 0;
my $lines_fall_sum = 0;
my $lines_fall_cnt = 0;

my $started = 0;
my $rows = 0;
my $t_first = 0;
my $t_last = 0;
my @vsync_edges;

while (my $line = <$fh>) {
    $line =~ s/\r?\n$//;
    if (!$started) {
        $started = 1 if $line =~ /^SystemTime,/;
        next;
    }
    next if $line eq '';

    my @f = split /,/, $line;
    next unless @f >= 5;

    my $t = int($f[1] * 1e9 + 0.5);   # ns
    my @v = ($f[2] + 0, $f[3] + 0, $f[4] + 0);
    $rows++;

    if ($rows == 1) {
        @state = @v;
        @last_change = ($t, $t, $t);
        $t_first = $t;
        $t_last = $t;
        next;
    }
    $t_last = $t;

    # ---- cross-channel timing: use the new levels at this transition ----
    my $href_rise = (!$state[2] &&  $v[2]);
    my $href_fall = ( $state[2] && !$v[2]);
    my $pclk_rise = (!$state[0] &&  $v[0]);
    my $vsync_rise = (!$state[1] &&  $v[1]);
    my $vsync_fall = ( $state[1] && !$v[1]);

    if ($href_rise) {
        $href_pclk = 0;
        $lines_rise++;
        $lines_fall++;
    }
    if ($pclk_rise && $v[2]) {
        $href_pclk++;
    }
    if ($href_fall) {
        if ($seen[2]) {
            $href_pclk_sum += $href_pclk;
            $href_pclk_cnt++;
            $href_pclk_min = $href_pclk if $href_pclk < $href_pclk_min;
            $href_pclk_max = $href_pclk if $href_pclk > $href_pclk_max;
        }
    }
    if ($vsync_rise) {
        if ($seen[1]) {
            $lines_rise_sum += $lines_rise;
            $lines_rise_cnt++;
            $lines_rise_min = $lines_rise if $lines_rise < $lines_rise_min;
            $lines_rise_max = $lines_rise if $lines_rise > $lines_rise_max;
        }
        $lines_rise = 0;
    }
    if ($vsync_fall) {
        if ($seen[1]) {
            $lines_fall_sum += $lines_fall;
            $lines_fall_cnt++;
            $lines_fall_min = $lines_fall if $lines_fall < $lines_fall_min;
            $lines_fall_max = $lines_fall if $lines_fall > $lines_fall_max;
        }
        $lines_fall = 0;
    }

    # ---- per-channel durations and edge periods ----
    for my $ch (0 .. 2) {
        next if $v[$ch] == $state[$ch];

        my $dur = $t - $last_change[$ch];
        if ($seen[$ch]) {
            if ($state[$ch]) {
                $hi_sum[$ch] += $dur;
                $hi_cnt[$ch]++;
                $hi_min[$ch] = $dur if $dur < $hi_min[$ch];
                $hi_max[$ch] = $dur if $dur > $hi_max[$ch];
            } else {
                $lo_sum[$ch] += $dur;
                $lo_cnt[$ch]++;
                $lo_min[$ch] = $dur if $dur < $lo_min[$ch];
                $lo_max[$ch] = $dur if $dur > $lo_max[$ch];
            }
        }
        $seen[$ch] = 1;

        if ($v[$ch]) {
            $rise_cnt[$ch]++;
            if ($last_rise[$ch] >= 0) {
                my $p = $t - $last_rise[$ch];
                $rp_sum[$ch] += $p;
                $rp_cnt[$ch]++;
                $rp_min[$ch] = $p if $p < $rp_min[$ch];
                $rp_max[$ch] = $p if $p > $rp_max[$ch];
            }
            $last_rise[$ch] = $t;
            if ($ch == 1 && @vsync_edges < 8) {
                push @vsync_edges, sprintf("RISE @ %.9f s", $t / 1e9);
            }
        } else {
            $fall_cnt[$ch]++;
            if ($last_fall[$ch] >= 0) {
                my $p = $t - $last_fall[$ch];
                $fp_sum[$ch] += $p;
                $fp_cnt[$ch]++;
                $fp_min[$ch] = $p if $p < $fp_min[$ch];
                $fp_max[$ch] = $p if $p > $fp_max[$ch];
            }
            $last_fall[$ch] = $t;
            if ($ch == 1 && @vsync_edges < 8) {
                push @vsync_edges, sprintf("FALL @ %.9f s", $t / 1e9);
            }
        }

        $state[$ch] = $v[$ch];
        $last_change[$ch] = $t;
    }
}
close $fh;

sub fmt {
    my ($ns) = @_;
    return "n/a" if $ns >= 1e17;
    return sprintf("%.3f ms", $ns / 1e6) if $ns >= 1e6;
    return sprintf("%.3f us", $ns / 1e3) if $ns >= 1e3;
    return sprintf("%.0f ns", $ns);
}

sub avg {
    my ($sum, $cnt) = @_;
    return $cnt ? $sum / $cnt : 0;
}

my $dur = $t_last - $t_first;
printf "rows=%d  time=%.6f s  (first=%.9f last=%.9f)\n",
       $rows, $dur / 1e9, $t_first / 1e9, $t_last / 1e9;

my @names = ("Ch0 PCLK", "Ch1 VSYNC", "Ch2 HREF");
for my $ch (0 .. 2) {
    printf "\n[%s] initial=%d rises=%d falls=%d\n",
           $names[$ch], $state[$ch], $rise_cnt[$ch], $fall_cnt[$ch];
    printf "  high: min=%s avg=%s max=%s (n=%d)\n",
           fmt($hi_min[$ch]), fmt(avg($hi_sum[$ch], $hi_cnt[$ch])),
           fmt($hi_max[$ch]), $hi_cnt[$ch];
    printf "  low : min=%s avg=%s max=%s (n=%d)\n",
           fmt($lo_min[$ch]), fmt(avg($lo_sum[$ch], $lo_cnt[$ch])),
           fmt($lo_max[$ch]), $lo_cnt[$ch];
    printf "  rise period: min=%s avg=%s max=%s (n=%d)\n",
           fmt($rp_min[$ch]), fmt(avg($rp_sum[$ch], $rp_cnt[$ch])),
           fmt($rp_max[$ch]), $rp_cnt[$ch];
    printf "  fall period: min=%s avg=%s max=%s (n=%d)\n",
           fmt($fp_min[$ch]), fmt(avg($fp_sum[$ch], $fp_cnt[$ch])),
           fmt($fp_max[$ch]), $fp_cnt[$ch];
}

printf "\nHREF-high PCLK rises: min=%d avg=%.3f max=%d (n=%d)\n",
       $href_pclk_min, avg($href_pclk_sum, $href_pclk_cnt),
       $href_pclk_max, $href_pclk_cnt;

printf "HREF rises between VSYNC rises: min=%d avg=%.3f max=%d (n=%d)\n",
       $lines_rise_min, avg($lines_rise_sum, $lines_rise_cnt),
       $lines_rise_max, $lines_rise_cnt;
printf "HREF rises between VSYNC falls: min=%d avg=%.3f max=%d (n=%d)\n",
       $lines_fall_min, avg($lines_fall_sum, $lines_fall_cnt),
       $lines_fall_max, $lines_fall_cnt;

printf "\nFirst VSYNC edges:\n";
print "  $_\n" for @vsync_edges;
