#!/usr/bin/perl
# ============================================================================
# extract_atkdl.pl
#
# Convert an ATK-Logic .atkdl archive into the transition-list CSV format
# consumed by tools/analyze_dvp_la.pl.
#
# .atkdl is a ZIP:
#   channel.ini          session keys (SamplingFrequency in kHz)
#   set.ini              UI/settings; settingData.setHz is the true rate in Hz
#   N/channel.ini        line 2 = start sample, line 3 = valid sample count
#   N/<off>-<idx>.bin    raw samples, 8 samples per byte, LSB first
#
# The output is a transition list: one row whenever any channel changes.
# Levels are held until the next row, so the CSV stays small for DVP captures.
#
# Usage:
#   perl tools/extract_atkdl.pl capture.atkdl [options] > capture.csv
#
# Options:
#   --out=FILE          output file (default: stdout)
#   --max-samples=N     process at most N samples (default: 2,000,000)
#   --start=N           start sample (default: 0)
#   --channels=N        number of channel columns to emit (default: 32)
#   --rate=HZ           override sample rate
#   --help
#
# Requires `unzip` on PATH (Git Bash / MSYS2 provides it). The project's
# normal analysis flow is:
#   perl tools/extract_atkdl.pl capture.atkdl --max-samples=200000 > line.csv
#   perl tools/analyze_dvp_la.pl line.csv --href-active=low
#   perl tools/analyze_dvp_la.pl line.csv --href-active=high
# ============================================================================
use strict;
use warnings;
use Getopt::Long;
use File::Basename qw(basename);

my %o = (
    out         => '-',
    max_samples => 2_000_000,
    start       => 0,
    channels    => 32,
    rate        => 0,
);
GetOptions(
    'out=s'         => \$o{out},
    'max-samples=i' => \$o{max_samples},
    'start=i'       => \$o{start},
    'channels=i'    => \$o{channels},
    'rate=i'        => \$o{rate},
    'help'          => sub { usage(); exit 0 },
) or usage();

my $path = shift @ARGV or usage();
usage() if @ARGV;
die "not found: $path\n" unless -f $path;
die "--channels must be 1..32\n" unless $o{channels} >= 1 && $o{channels} <= 32;
die "--max-samples must be > 0\n" unless $o{max_samples} > 0;

sub usage {
    print STDERR <<"USAGE";
Usage: perl tools/extract_atkdl.pl capture.atkdl [options]
  --out=FILE          output file (default: stdout)
  --max-samples=N     process at most N samples (default: 2,000,000)
  --start=N           start sample (default: 0)
  --channels=N        channel columns, 1..32 (default: 32)
  --rate=HZ           override sample rate
  --help
USAGE
}

# ---------------------------------------------------------------- read zip
sub list_zip {
    my ($file) = @_;
    open my $fh, '-|', 'unzip', '-Z1', $file or die "unzip -Z1: $!\n";
    my @n = <$fh>;
    close $fh;
    chomp @n;
    return @n;
}

sub read_member {
    my ($file, $name) = @_;
    open my $fh, '-|', 'unzip', '-p', $file, $name
        or die "unzip -p $name: $!\n";
    binmode $fh;
    local $/;
    my $d = <$fh>;
    close $fh;
    return defined $d ? $d : '';
}

my @names = list_zip($path);
my %raw;
for my $n (@names) {
    next if $n =~ m{/$};
    next unless $n =~ m{^(?:channel\.ini|set\.ini|vernier\.ini|\d+/\d+-\d+\.bin|\d+/channel\.ini)$};
    $raw{$n} = read_member($path, $n);
}

my $top = $raw{'channel.ini'} // '';
my %kv;
for my $line (split /[\r\n]+/, $top) {
    $kv{$1} = $2 if $line =~ /^([^=]+)=(.*)$/;
}
my $rate = $o{rate};
if (!$rate) {
    my $set = $raw{'set.ini'} // '';
    my ($hz) = $set =~ /"setHz"\s*:\s*(\d+)/;
    $rate = $hz || (($kv{SamplingFrequency} // 0) * 1000);
}
die "cannot determine sample rate (use --rate=HZ)\n" unless $rate > 0;

my $depth = $kv{SamplingDepth} // 0;

# ---------------------------------------------------------------- channels
my %ch;    # ch -> { data, start, valid }
for my $n (keys %raw) {
    if ($n =~ m{^(\d+)/(\d+)-(\d+)\.bin$}) {
        my ($c, $off, $idx) = ($1 + 0, $2 + 0, $3 + 0);
        push @{ $ch{$c}{parts} }, [ $idx, $off, $raw{$n} ];
    } elsif ($n =~ m{^(\d+)/channel\.ini$}) {
        $ch{$1 + 0}{ini} = $raw{$n};
    }
}
for my $c (keys %ch) {
    if ($ch{$c}{parts}) {
        my @p = sort { $a->[0] <=> $b->[0] || $a->[1] <=> $b->[1] }
                @{ $ch{$c}{parts} };
        $ch{$c}{data} = join('', map { $_->[2] } @p);
    }
    my @l = split /[\r\n]+/, ($ch{$c}{ini} // '');
    $ch{$c}{start} = $l[1] // 0;
    $ch{$c}{valid} = $l[2] // 0;
}

my @active = sort { $a <=> $b }
             grep { defined $ch{$_}{data} && length $ch{$_}{data} }
             keys %ch;

my $valid_max = 0;
for my $c (@active) {
    my $cap = length($ch{$c}{data}) * 8;
    my $v = $ch{$c}{valid} || $cap;
    $v = $cap if $v > $cap;
    $ch{$c}{valid} = $v;
    $valid_max = $v if $v > $valid_max;
}
$valid_max ||= $depth;
die "no samples found\n" unless $valid_max > 0;

my $start = $o{start};
$start = 0 if $start < 0;
$start = $valid_max - 1 if $start >= $valid_max;
my $count = $o{max_samples};
$count = $valid_max - $start if $count > $valid_max - $start;

my @levels = (0) x 32;
for my $c (@active) {
    next if $c > 31;
    $levels[$c] = vec($ch{$c}{data}, $start, 1);
}

my $out = $o{out};
my $oh;
if ($out eq '-') {
    $oh = \*STDOUT;
} else {
    open $oh, '>:raw', $out or die "open $out: $!\n";
}

print $oh "; CSV, generated by extract_atkdl.pl from ", basename($path), "\n";
print $oh "; Channels (", scalar(@active), "/32)\n";
printf $oh "; Sample rate: %.6f MHz\n", $rate / 1e6;
print $oh "; Sample count: $count\n";
print $oh "; Start sample: $start\n";
print $oh "SystemTime, Time(s), ",
          join(', ', map { "Channel $_" } 0 .. $o{channels} - 1), "\n";

sub emit_row {
    my ($i) = @_;
    printf $oh "'1970-01-01 00:00:00.000000000,%.9f", $i / $rate;
    print $oh ",", join(',', @levels[0 .. $o{channels} - 1]), "\n";
}

emit_row($start);
for (my $i = $start + 1; $i < $start + $count; $i++) {
    my $changed = 0;
    for my $c (@active) {
        next if $c > 31;
        my $v = vec($ch{$c}{data}, $i, 1);
        if ($v != $levels[$c]) {
            $levels[$c] = $v;
            $changed = 1;
        }
    }
    emit_row($i) if $changed;
}

close $oh unless $out eq '-';

printf STDERR "extract_atkdl: %s ch=%s rate=%.6f MHz samples=%d..%d rows emitted\n",
    basename($path), join(',', @active), $rate / 1e6,
    $start, $start + $count - 1;
