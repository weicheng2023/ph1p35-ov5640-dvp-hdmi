#!/usr/bin/perl
# ============================================================================
# analyze_dvp_la.pl
#
# Analyze an ATK-Logic CSV capture of the OV5640 8-bit DVP bus.
#
# Default channel map (matches the 11-channel wiring in
# verification/board/la-dvp-11ch.md):
#   CH0  PCLK
#   CH1  VSYNC
#   CH2  HREF
#   CH3..CH10 D0..D7
#
# The CSV is a transition list: each data row contains the level of every
# channel at that timestamp; levels are held until the next row. PCLK edges
# are detected on the reconstructed levels. At an edge the script uses the
# levels *before* the row, because DVP data is stable before the sampling
# edge; coincident data/control changes are counted and reported.
#
# Usage:
#   perl tools/analyze_dvp_la.pl capture.csv [options]
#
# Options:
#   --pclk=N --vsync=N --href=N --d0=N    channel indices (default 0,1,2,3)
#   --edge=rise|fall                     PCLK sampling edge (default rise)
#   --href-active=low|high               default low (current board hypothesis)
#   --vsync-active=high|low              default high (0x4740=0x22 measured)
#   --max-lines=N                        lines kept for pixel analysis (default 8)
#   --max-line-bytes=N                   safety cap (default 8192)
#   --show-pixels=N                      pixels printed per line (default 32)
#   --bar-width=N                        expected bar width (default 80)
#   --expected=A,B,...                   expected RGB565 hex list; default is
#                                        the project checker hypothesis
#   --no-expected                        skip expected comparison
#   --min-line-bytes=N                   ignore shorter HREF pulses (default 64)
#
# The script is deliberately data-first: it prints the actual run lengths and
# RGB565 values before comparing to any expected pattern. This lets you tell
# whether the checker's assumed bar order/width is wrong.
# ============================================================================
use strict;
use warnings;
use Getopt::Long;

my %o = (
    pclk         => 0,
    vsync        => 1,
    href         => 2,
    d0           => 3,
    edge         => 'rise',
    href_active  => 'low',
    vsync_active => 'high',
    max_lines    => 8,
    max_line_bytes => 8192,
    show_pixels  => 32,
    bar_width    => 80,
    expected     => 'FFFF,FFE0,07FF,07E0,F81F,F800,001F,0000',
    min_line_bytes => 64,
);
GetOptions(
    'pclk=i'         => \$o{pclk},
    'vsync=i'        => \$o{vsync},
    'href=i'         => \$o{href},
    'd0=i'           => \$o{d0},
    'edge=s'         => \$o{edge},
    'href-active=s'  => \$o{href_active},
    'vsync-active=s' => \$o{vsync_active},
    'max-lines=i'    => \$o{max_lines},
    'max-line-bytes=i' => \$o{max_line_bytes},
    'show-pixels=i'  => \$o{show_pixels},
    'bar-width=i'    => \$o{bar_width},
    'expected=s'     => \$o{expected},
    'no-expected'    => sub { $o{expected} = '' },
    'min-line-bytes=i' => \$o{min_line_bytes},
    'help'           => sub { usage(); exit 0 },
) or usage();

my $path = shift @ARGV or usage();
usage() if @ARGV;
$o{edge} = lc $o{edge};
$o{href_active} = lc $o{href_active};
$o{vsync_active} = lc $o{vsync_active};
die "edge must be rise or fall\n" unless $o{edge} eq 'rise' || $o{edge} eq 'fall';
die "href-active must be low or high\n" unless $o{href_active} eq 'low' || $o{href_active} eq 'high';
die "vsync-active must be low or high\n" unless $o{vsync_active} eq 'low' || $o{vsync_active} eq 'high';

my $N = $o{d0} + 8;
die "channel indices must be non-negative and distinct\n"
    if $o{pclk} < 0 || $o{vsync} < 0 || $o{href} < 0 || $o{d0} < 0
    || $o{pclk} == $o{vsync} || $o{pclk} == $o{href}
    || $o{vsync} == $o{href};

open my $fh, '<:raw', $path or die "open $path: $!\n";

sub href_active { return $o{href_active} eq 'high' ? $_[0] : !$_[0]; }
sub vsync_active { return $o{vsync_active} eq 'high' ? $_[0] : !$_[0]; }
sub rev8 {
    my $x = shift;
    my $r = 0;
    for (1 .. 8) { $r = ($r << 1) | ($x & 1); $x >>= 1; }
    return $r & 0xFF;
}
sub swap16 {
    my $p = shift;
    return (($p & 0xFF) << 8) | (($p >> 8) & 0xFF);
}
sub rgb565 {
    my $p = shift;
    my $r = ($p >> 11) & 0x1F;
    my $g = ($p >> 5) & 0x3F;
    my $b = $p & 0x1F;
    $r = ($r << 3) | ($r >> 2);
    $g = ($g << 2) | ($g >> 4);
    $b = ($b << 3) | ($b >> 2);
    return ($r, $g, $b);
}

my @state;
my @prev;
my $started = 0;
my $rows = 0;
my $t_first = 0;
my $t_last = 0;

my ($pclk_edges, $period_sum, $period_min, $period_max, $period_cnt) = (0, 0, 1e18, 0, 0);
my ($high_sum, $high_cnt, $low_sum, $low_cnt) = (0, 0, 0, 0);
my $last_rise = -1;
my $last_pclk_change = -1;

my @line_counts;
my @lines;                 # [ [byte,...], ... ] first max_lines valid lines
my @line_widths;           # active HREF width in ns, one per valid line
my $cur_line;
my $line_len = 0;
my $line_truncated = 0;
my $in_line = 0;
my $line_partial = 0;
my $line_start_t = 0;

my $frame_started = 0;
my $frame_lines = 0;
my @frame_line_counts;
my ($vsync_period_sum, $vsync_period_min, $vsync_period_max, $vsync_period_cnt) = (0, 1e18, 0, 0);
my $last_vsync_start = -1;

my ($byte_total, $zero_bytes, $ff_bytes, $coincident) = (0, 0, 0, 0);
my (@bit_high, @bit_low) = ((0) x 8, (0) x 8);

sub close_line {
    my ($t_end) = @_;
    return unless $in_line;
    my $n = $line_len;
    if (!$line_partial && $n >= $o{min_line_bytes}) {
        push @line_counts, $n;
        $line_widths[scalar @line_counts - 1] = $t_end - $line_start_t;
        if (!$line_truncated && @lines < $o{max_lines}) {
            push @lines, [ @$cur_line ];
        }
        $frame_lines++ if $frame_started;
    }
    $in_line = 0;
    $cur_line = undef;
    $line_len = 0;
    $line_truncated = 0;
    $line_partial = 0;
}

while (my $line = <$fh>) {
    $line =~ s/\r?\n$//;
    next if $line =~ /^\s*;/;
    if (!$started) {
        $started = 1 if $line =~ /^SystemTime,/;
        next;
    }
    next if $line eq '';
    my @f = split /,/, $line;
    next unless @f >= 2 + $N;

    my $t = $f[1] + 0;
    my @v = map { $_ + 0 } @f[2 .. 2 + $N - 1];

    if (!$rows) {
        @state = @v;
        $t_first = $t;
        $t_last = $t;
        $rows = 1;
        $in_line = href_active($state[$o{href}]) ? 1 : 0;
        $line_partial = $in_line;
        $line_start_t = $t;
        $cur_line = [];
        $line_len = 0;
        $line_truncated = 0;
        $last_pclk_change = $t if $state[$o{pclk}];
        next;
    }
    $rows++;
    $t_last = $t;

    my $href_prev = href_active($state[$o{href}]);
    my $href_new  = href_active($v[$o{href}]);
    my $vsync_prev = vsync_active($state[$o{vsync}]);
    my $vsync_new  = vsync_active($v[$o{vsync}]);
    my $pclk_rise  = (!$state[$o{pclk}] &&  $v[$o{pclk}]);
    my $pclk_fall  = ( $state[$o{pclk}] && !$v[$o{pclk}]);
    my $pclk_edge  = $o{edge} eq 'rise' ? $pclk_rise : $pclk_fall;

    if (!$vsync_prev && $vsync_new) {
        if ($frame_started) {
            push @frame_line_counts, $frame_lines;
            if ($last_vsync_start >= 0) {
                my $p = $t - $last_vsync_start;
                $vsync_period_sum += $p;
                $vsync_period_cnt++;
                $vsync_period_min = $p if $p < $vsync_period_min;
                $vsync_period_max = $p if $p > $vsync_period_max;
            }
            $last_vsync_start = $t;
        } else {
            $frame_started = 1;
            $last_vsync_start = $t;
        }
        $frame_lines = 0;
    }

    if ($pclk_edge && $href_prev) {
        my $b = 0;
        for my $i (0 .. 7) {
            $b |= (($state[$o{d0} + $i] & 1) << $i);
        }
        if ($in_line) {
            $line_len++;
            if (@$cur_line < $o{max_line_bytes}) {
                push @$cur_line, $b;
            } else {
                $line_truncated = 1;
            }
            $byte_total++;
            $zero_bytes++ if $b == 0;
            $ff_bytes++   if $b == 0xFF;
            for my $i (0 .. 7) {
                if (($b >> $i) & 1) { $bit_high[$i]++; } else { $bit_low[$i]++; }
            }
        }
        # PCLK itself changes by definition at this edge; only data/control
        # changes coincident with the edge are suspicious.
        my $coinc = 0;
        $coinc = 1 if $v[$o{href}] != $state[$o{href}];
        $coinc = 1 if $v[$o{vsync}] != $state[$o{vsync}];
        for my $i (0 .. 7) {
            $coinc = 1 if $v[$o{d0} + $i] != $state[$o{d0} + $i];
        }
        $coincident++ if $coinc;
    }

    # HREF is processed after the PCLK sample: a byte on the same row as the
    # final HREF deassertion still belongs to the line; a byte on the same row
    # as HREF assertion does not (in_line was still 0 at the sample).
    if ($href_prev && !$href_new) {
        close_line($t);
    }
    if (!$href_prev && $href_new) {
        $cur_line = [];
        $line_len = 0;
        $line_truncated = 0;
        $in_line = 1;
        $line_partial = 0;
        $line_start_t = $t;
    }

    if ($pclk_rise) {
        $pclk_edges++;
        if ($last_rise >= 0) {
            my $p = ($t - $last_rise) * 1e9;
            $period_sum += $p;
            $period_cnt++;
            $period_min = $p if $p < $period_min;
            $period_max = $p if $p > $period_max;
        }
        $last_rise = $t;
    }
    if ($state[$o{pclk}] != $v[$o{pclk}]) {
        if ($last_pclk_change >= 0) {
            my $d = ($t - $last_pclk_change) * 1e9;
            if ($state[$o{pclk}]) { $high_sum += $d; $high_cnt++; }
            else                  { $low_sum  += $d; $low_cnt++;  }
        }
        $last_pclk_change = $t;
    }

    @state = @v;
}
close $fh;
if ($in_line) {
    $line_partial = 1;
    close_line($t_last);
}

sub usage {
    print STDERR <<"EOF";
usage: perl tools/analyze_dvp_la.pl capture.csv [options]
  --pclk=N --vsync=N --href=N --d0=N
  --edge=rise|fall  --href-active=low|high  --vsync-active=high|low
  --max-lines=N --max-line-bytes=N --show-pixels=N --bar-width=N
  --expected=A,B,... | --no-expected
EOF
    exit 1;
}
sub fmt_s {
    my $s = shift;
    return sprintf("%.3f ms", $s * 1e3) if $s >= 1e-3;
    return sprintf("%.3f us", $s * 1e6) if $s >= 1e-6;
    return sprintf("%.0f ns", $s * 1e9);
}
sub fmt_ns {
    my $ns = shift;
    return sprintf("%.3f ms", $ns / 1e6) if $ns >= 1e6;
    return sprintf("%.3f us", $ns / 1e3) if $ns >= 1e3;
    return sprintf("%.0f ns", $ns);
}

print "file: $path\n";
printf "rows=%d  time=%s  (first=%.9f s last=%.9f s)\n",
       $rows, fmt_s($t_last - $t_first), $t_first, $t_last;
print "channel map: PCLK=CH$o{pclk} VSYNC=CH$o{vsync} HREF=CH$o{href} "
    . "D0..D7=CH$o{d0}..CH" . ($o{d0}+7) . "\n";
print "polarity: HREF active $o{href_active}, VSYNC active $o{vsync_active}, "
    . "sample on PCLK $o{edge}\n";

if (!$pclk_edges) {
    print "\nERROR: no PCLK $o{edge} edge found. Check channel map, probe, and ground.\n";
}
if ($period_cnt) {
    my $avg = $period_sum / $period_cnt;
    printf "\nPCLK: edges=%d  period avg=%.3f ns (%.3f MHz)  min=%.3f max=%.3f ns\n",
           $pclk_edges, $avg, 1e3 / $avg, $period_min, $period_max;
    printf "      high avg=%.3f ns  low avg=%.3f ns\n",
           $high_cnt ? $high_sum / $high_cnt : 0,
           $low_cnt  ? $low_sum  / $low_cnt  : 0;
}
if (@line_counts) {
    my ($min, $max, $sum) = ($line_counts[0], $line_counts[0], 0);
    my %hist;
    for my $n (@line_counts) {
        $min = $n if $n < $min;
        $max = $n if $n > $max;
        $sum += $n;
        $hist{$n}++;
    }
    printf "\nHREF active lines=%d  bytes/line min=%d avg=%.2f max=%d\n",
           scalar @line_counts, $min, $sum / @line_counts, $max;
    print "  byte-count histogram: ";
    print join(' ', map { "$_ x$hist{$_}" } sort { $a <=> $b } keys %hist), "\n";
    my $wmin = 1e18; my $wmax = 0; my $wsum = 0;
    for my $w (@line_widths) {
        $wmin = $w if $w < $wmin;
        $wmax = $w if $w > $wmax;
        $wsum += $w;
    }
    printf "  HREF active width: min=%s avg=%s max=%s\n",
           fmt_s($wmin), fmt_s($wsum / @line_widths), fmt_s($wmax);
} else {
    print "\nNo HREF active line found (check HREF polarity and --min-line-bytes).\n";
}
if (@frame_line_counts) {
    my ($min, $max, $sum) = ($frame_line_counts[0], $frame_line_counts[0], 0);
    for my $n (@frame_line_counts) {
        $min = $n if $n < $min;
        $max = $n if $n > $max;
        $sum += $n;
    }
    printf "\nVSYNC frames=%d  lines/frame min=%d avg=%.2f max=%d\n",
           scalar @frame_line_counts, $min, $sum / @frame_line_counts, $max;
}
if ($vsync_period_cnt) {
    printf "VSYNC period: avg=%.6f ms (%.3f Hz) min=%.6f max=%.6f ms\n",
           ($vsync_period_sum / $vsync_period_cnt) * 1e3,
           1e3 / (($vsync_period_sum / $vsync_period_cnt) * 1e3),
           $vsync_period_min * 1e3, $vsync_period_max * 1e3;
}
printf "\nActive bytes=%d  zero=%d  FF=%d  edge-coincident changes=%d\n",
       $byte_total, $zero_bytes, $ff_bytes, $coincident;
print "D0..D7 high counts: " . join(' ', @bit_high) . "\n";
print "D0..D7 low  counts: " . join(' ', @bit_low) . "\n";

if (!@lines) {
    print "\nNo captured line available for pixel analysis.\n";
    exit 0;
}

# Pick the first line whose byte count is the mode; prefer an even count.
my %lc;
$lc{$_}++ for @line_counts;
my ($mode_n) = sort { $lc{$b} <=> $lc{$a} || $b <=> $a } keys %lc;
my $line_ref;
for my $l (@lines) {
    if (scalar(@$l) == $mode_n) { $line_ref = $l; last; }
}
$line_ref ||= $lines[0];

print "\n=== First/most-common line ===\n";
printf "bytes=%d  pixels(phase0)=%d  pixels(phase1)=%d\n",
       scalar(@$line_ref), int(scalar(@$line_ref) / 2), int((scalar(@$line_ref) - 1) / 2);
printf "first bytes: %s\n", join(' ', map { sprintf("%02X", $_) } @$line_ref[0 .. ($#{$line_ref} < 31 ? $#{$line_ref} : 31)]);

sub make_pixels {
    my ($l, $phase) = @_;
    my @p;
    for (my $i = $phase; $i + 1 < @$l; $i += 2) {
        push @p, (($l->[$i] << 8) | $l->[$i + 1]);
    }
    return @p;
}
sub print_pixels {
    my ($label, @p) = @_;
    my $n = @p < $o{show_pixels} ? @p : $o{show_pixels};
    print "$label (" . scalar(@p) . " px): ";
    for my $i (0 .. $n - 1) {
        printf "%04X ", $p[$i];
    }
    print "\n";
}
my @pix0 = make_pixels($line_ref, 0);
my @pix1 = make_pixels($line_ref, 1);
print_pixels("pixels phase0", @pix0);
print_pixels("pixels phase1", @pix1);

sub print_runs {
    my ($label, $p) = @_;
    return unless @$p;
    my @runs;
    my $start = 0;
    my $last = $p->[0];
    for (my $i = 1; $i < @$p; $i++) {
        if ($p->[$i] != $last) {
            push @runs, [$start, $i - $start, $last];
            $start = $i;
            $last = $p->[$i];
        }
    }
    push @runs, [$start, scalar(@$p) - $start, $last];
    print "\n$label runs (" . scalar(@runs) . "):\n";
    print "  start  len   RGB565   R   G   B\n";
    my $shown = 0;
    for my $r (@runs) {
        last if $shown++ >= 40;
        my ($rr, $gg, $bb) = rgb565($r->[2]);
        printf "  %5d  %4d   %04X   %3d %3d %3d\n", $r->[0], $r->[1], $r->[2], $rr, $gg, $bb;
    }
}
print_runs("phase0", \@pix0);
print_runs("phase1", \@pix1) if @pix1 && @pix0 && $pix0[0] != $pix1[0];

if ($o{expected} ne '') {
    my @exp = map { hex($_) } split /,/, $o{expected};
    my $barw = $o{bar_width};
    print "\n=== Expected comparison (hypothesis only) ===\n";
    print "expected RGB565: " . join(' ', map { sprintf("%04X", $_) } @exp) . "\n";
    print "bar width assumption: $barw px; expected list has " . scalar(@exp) . " colors.\n";
    print "If the actual run table above shows a different width/order, the checker assumption is wrong.\n";

    sub compare {
        my ($p, $xform, $label) = @_;
        my ($match, $first, $errs) = (0, -1, 0);
        for my $i (0 .. $#$p) {
            my $v = $xform->($p->[$i]);
            my $idx = int($i / $barw);
            my $e = $idx < @exp ? $exp[$idx] : $exp[-1];
            if ($v == $e) { $match++; }
            else {
                $errs++;
                if ($first < 0) {
                    $first = $i;
                    printf "  %s first error: idx=%d got=%04X exp=%04X (bar %d)\n",
                           $label, $i, $v, $e, $idx;
                }
            }
        }
        printf "  %s: match=%d/%d errors=%d first=%d\n",
               $label, $match, scalar(@$p), $errs, $first;
        return $match;
    }
    my $m0 = compare(\@pix0, sub { $_[0] }, "normal phase0");
    my $m1 = @pix1 ? compare(\@pix1, sub { $_[0] }, "normal phase1") : -1;
    my $ms = compare(\@pix0, sub { swap16($_[0]) }, "byte-swapped");
    my $mb = compare(\@pix0, sub {
        my $p = shift;
        return (rev8(($p >> 8) & 0xFF) << 8) | rev8($p & 0xFF);
    }, "bit-reversed bytes");

    # Pixel shift search: compare shifted actual pixels to expected.
    my $best = -1; my $best_off = 0;
    for my $off (-8 .. 8) {
        my $m = 0;
        for my $i (0 .. $#pix0) {
            my $j = $i + $off;
            next if $j < 0 || $j > $#pix0;
            my $idx = int($i / $barw);
            my $e = $idx < @exp ? $exp[$idx] : $exp[-1];
            $m++ if $pix0[$j] == $e;
        }
        if ($m > $best) { $best = $m; $best_off = $off; }
    }
    print "  best pixel shift: offset=$best_off match=$best/" . scalar(@pix0) . "\n";

    if ($ms > $m0 && $ms > $m1) {
        print "  DIAGNOSIS: byte-swapped interpretation matches better; check 0x4300/byte pairing.\n";
    }
    if ($mb > $m0 && $mb > $m1) {
        print "  DIAGNOSIS: bit-reversed interpretation matches better; check D0..D7 mapping.\n";
    }
}

print "\nDone.\n";
