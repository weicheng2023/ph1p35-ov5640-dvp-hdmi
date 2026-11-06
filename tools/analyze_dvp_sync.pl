#!/usr/bin/perl
# ============================================================================
# analyze_dvp_sync.pl
#
# Pulse/period analysis for VSYNC + HREF only. Unlike analyze_dvp_la.pl,
# this does NOT need a real PCLK: it works on a transition-list CSV even
# when PCLK is undersampled (e.g. 50 MS/s capture of a 48 MHz clock).
#
# Input: CSV produced by ATK-Logic or tools/extract_atkdl.pl:
#   ; Sample rate: ...
#   SystemTime, Time(s), Channel 0, ...
#   '...,<time>,<level>,...
#
# Usage:
#   perl tools/analyze_dvp_sync.pl capture.csv [options]
#
# Options:
#   --vsync=N              VSYNC channel (default 1)
#   --href=N               HREF channel (default 2)
#   --min-vsync-us=N       ignore VSYNC highs shorter than N us (default 20)
#   --href-normal-min=N    normal HREF high minimum, us (default 35)
#   --href-normal-max=N    normal HREF high maximum, us (default 45)
#   --long-us=N            report HREF highs longer than N us (default 100)
#   --max-report=N         rows in each histogram (default 10)
#
# It reports:
#   - VSYNC high widths, periods, and the derived frame rate.
#   - HREF high-width bins: short glitches, normal lines, long blanking highs.
#   - Normal HREF period (15 kHz expected for 640x480).
#   - Real HREF lines per VSYNC frame (normal lines + long highs).
# ============================================================================
use strict;
use warnings;
use Getopt::Long;

my %o = (
    vsync            => 1,
    href             => 2,
    min_vsync_us     => 20,
    href_normal_min  => 35,
    href_normal_max  => 45,
    long_us          => 100,
    max_report       => 10,
);
GetOptions(
    'vsync=i'           => \$o{vsync},
    'href=i'            => \$o{href},
    'min-vsync-us=f'    => \$o{min_vsync_us},
    'href-normal-min=f' => \$o{href_normal_min},
    'href-normal-max=f' => \$o{href_normal_max},
    'long-us=f'         => \$o{long_us},
    'max-report=i'      => \$o{max_report},
    'help'              => sub { usage(); exit 0 },
) or usage();

my $path = shift @ARGV or usage();
usage() if @ARGV;
open my $fh, '<:raw', $path or die "open $path: $!\n";

sub usage {
    print STDERR <<"USAGE";
Usage: perl tools/analyze_dvp_sync.pl capture.csv [options]
  --vsync=N  --href=N  --min-vsync-us=N
  --href-normal-min=N  --href-normal-max=N
  --long-us=N  --max-report=N
USAGE
}

my $maxch = $o{vsync} > $o{href} ? $o{vsync} : $o{href};
my ($started, $rows) = (0, 0);
my (%prev, %last_t);
my (@v_high, @h_high);

while (my $line = <$fh>) {
    $line =~ s/\r?\n$//;
    next if $line =~ /^\s*;/;
    if (!$started) {
        $started = 1 if $line =~ /^SystemTime,/;
        next;
    }
    next if $line eq '';
    my @f = split /,/, $line;
    next unless @f >= 2 + $maxch + 1;
    my $t = $f[1] + 0;
    for my $ch ($o{vsync}, $o{href}) {
        my $v = $f[2 + $ch] + 0;
        if (!exists $prev{$ch}) {
            $prev{$ch} = $v;
            $last_t{$ch} = $t;
        } elsif ($v != $prev{$ch}) {
            if ($v == 1) {
                $last_t{$ch} = $t;          # rising: high starts
            } else {
                my $w = $t - $last_t{$ch};
                push @v_high, [ $last_t{$ch}, $t, $w ] if $ch == $o{vsync};
                push @h_high, [ $last_t{$ch}, $t, $w ] if $ch == $o{href};
            }
            $prev{$ch} = $v;
        }
    }
    $rows++;
}
close $fh;
die "no data rows\n" unless $rows;

sub us { $_[0] * 1e6 }
sub ms { $_[0] * 1e3 }

sub hist {
    my ($name, $arr, $scale, $unit, $maxr) = @_;
    my %h;
    $h{ sprintf("%.0f", $_->[2] * $scale) }++ for @$arr;
    my @k = sort { $a <=> $b } keys %h;
    my @top = sort { $h{$b} <=> $h{$a} } @k;
    @top = @top[ 0 .. ($#top < $maxr ? $#top : $maxr) ];
    print "$name: n=", scalar(@$arr), " top=",
          join(' ', map { "$_:$h{$_}$unit" } @top), "\n";
}

my @vreal = grep { $_->[2] * 1e6 >= $o{min_vsync_us} } @v_high;
print "rows=$rows\n";
print "VSYNC: high pulses=", scalar(@v_high),
      " real(>=", $o{min_vsync_us}, "us)=", scalar(@vreal), "\n";
if (@vreal) {
    my ($sum, $mn, $mx) = (0, 1e9, 0);
    for (@vreal) { $sum += $_->[2]; $mn = $_->[2] if $_->[2] < $mn; $mx = $_->[2] if $_->[2] > $mx; }
    printf "  high avg=%.3f us min=%.3f max=%.3f\n", us($sum/@vreal), us($mn), us($mx);
    for my $i (1 .. $#vreal) {
        printf "  period %.3f ms\n", ms($vreal[$i][0] - $vreal[$i-1][0])
            if $i <= $o{max_report};
    }
    printf "  frame rate %.3f Hz (from first/last)\n",
           1.0 / (($vreal[-1][0] - $vreal[0][0]) / ($#vreal || 1))
           if $#vreal >= 1;
}

my @hshort = grep { $_->[2] * 1e6 < 1 } @h_high;
my @hlong  = grep { $_->[2] * 1e6 >= $o{long_us} } @h_high;
my @hnormal = grep {
    my $u = $_->[2] * 1e6;
    $u >= $o{href_normal_min} && $u <= $o{href_normal_max}
} @h_high;
my @hreal = grep { $_->[2] * 1e6 > 1 } @h_high;   # exclude sub-us glitches

print "HREF: high pulses=", scalar(@h_high),
      " normal(", $o{href_normal_min}, "-", $o{href_normal_max}, "us)=",
      scalar(@hnormal), " long(>=", $o{long_us}, "us)=", scalar(@hlong),
      " short(<1us)=", scalar(@hshort), "\n";
hist('  high widths', \@h_high, 1e6, 'us', $o{max_report});

if (@hnormal) {
    my ($sum, $mn, $mx) = (0, 1e9, 0);
    for (@hnormal) { $sum += $_->[2]; $mn = $_->[2] if $_->[2] < $mn; $mx = $_->[2] if $_->[2] > $mx; }
    printf "  normal high avg=%.3f us min=%.3f max=%.3f\n", us($sum/@hnormal), us($mn), us($mx);
    my @p;
    for my $i (1 .. $#hreal) {
        my ($a, $b) = ($hreal[$i-1], $hreal[$i]);
        next unless $a->[2] * 1e6 >= $o{href_normal_min}
                 && $a->[2] * 1e6 <= $o{href_normal_max}
                 && $b->[2] * 1e6 >= $o{href_normal_min}
                 && $b->[2] * 1e6 <= $o{href_normal_max};
        push @p, $b->[0] - $a->[0];
    }
    if (@p) {
        my ($s, $mn2, $mx2) = (0, 1e9, 0);
        for (@p) { $s += $_; $mn2 = $_ if $_ < $mn2; $mx2 = $_ if $_ > $mx2; }
        printf "  normal period avg=%.3f us min=%.3f max=%.3f (%d intervals)\n",
               us($s/@p), us($mn2), us($mx2), scalar(@p);
    }
}

if (@hlong) {
    print "  long HREF highs:\n";
    for my $p (@hlong) {
        printf "    %.3f..%.3f ms width %.3f ms\n",
               ms($p->[0]), ms($p->[1]), ms($p->[2]);
    }
}

if (@vreal && @hreal) {
    print "  HREF high pulses per VSYNC interval:\n";
    for my $i (1 .. $#vreal) {
        my ($a, $b) = ($vreal[$i-1][0], $vreal[$i][0]);
        my $normal = grep { $_->[0] > $a && $_->[0] <= $b } @hnormal;
        my $all    = grep { $_->[0] > $a && $_->[0] <= $b } @hreal;
        printf "    frame %d: %.3f ms normal=%d all(>1us)=%d\n",
               $i, ms($b - $a), $normal, $all;
    }
}
