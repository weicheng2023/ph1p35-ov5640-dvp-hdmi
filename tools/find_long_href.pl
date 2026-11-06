#!/usr/bin/perl
# Find abnormally long HREF-high intervals and relate them to VSYNC edges.
# Usage: perl tools/find_long_href.pl <capture.csv>
use strict;
use warnings;

my $path = $ARGV[0] or die "usage: $0 <capture.csv>\n";
open my $fh, '<:raw', $path or die "open $path: $!\n";

my $started = 0;
my @href = (1, 1);          # state, last_change_time(ns)
my @vsync = (0, 0);         # state, last_change_time
my @vsync_edges;            # [time_ns, new_value]
my @long_high;              # [start_ns, end_ns]
my $rows = 0;

while (my $line = <$fh>) {
    $line =~ s/\r?\n$//;
    if (!$started) {
        $started = 1 if $line =~ /^SystemTime,/;
        next;
    }
    next if $line eq '';
    my @f = split /,/, $line;
    next unless @f >= 5;

    my $t = int($f[1] * 1e9 + 0.5);
    my $v1 = $f[3] + 0;   # VSYNC
    my $v2 = $f[4] + 0;   # HREF
    $rows++;

    if ($rows == 1) {
        $href[0] = $v2; $href[1] = $t;
        $vsync[0] = $v1; $vsync[1] = $t;
        next;
    }

    if ($v1 != $vsync[0]) {
        push @vsync_edges, [$t, $v1];
        $vsync[0] = $v1;
        $vsync[1] = $t;
    }

    if ($v2 != $href[0]) {
        if ($href[0] == 1) {
            my $dur = $t - $href[1];
            push @long_high, [$href[1], $t] if $dur > 100_000;  # > 100 us
        }
        $href[0] = $v2;
        $href[1] = $t;
    }
}
close $fh;

printf "rows=%d long_href_high=%d vsync_edges=%d\n\n",
       $rows, scalar(@long_high), scalar(@vsync_edges);

my $n = 0;
for my $h (@long_high) {
    last if $n++ >= 6;
    my ($s, $e) = @$h;
    printf "LONG HREF HIGH: %.9f .. %.9f s (%.3f ms)\n",
           $s / 1e9, $e / 1e9, ($e - $s) / 1e6;
    for my $v (@vsync_edges) {
        my ($t, $val) = @$v;
        next if $t < $s - 2_000_000 || $t > $e + 2_000_000;
        printf "   VSYNC %s @ %.9f s  (offset from HREF start: %+.3f us)\n",
               $val ? "RISE" : "FALL", $t / 1e9, ($t - $s) / 1e3;
    }
    print "\n";
}
