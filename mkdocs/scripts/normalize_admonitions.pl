#!/usr/bin/env perl
use strict;
use warnings;
use File::Find;
use File::Spec;

my $repo_root = '.';
my $docs_root = $ENV{DOCS_ROOT} // File::Spec->rel2abs("$repo_root/mkdocs/docs");

die "Missing docs root: $docs_root\n" unless -d $docs_root;

sub normalize_github_alerts {
  my ($content) = @_;
  my @lines = split /\n/, $content, -1;
  my @out;
  my $in_fence = 0;

  my %alert_map = (
    caution   => 'warning',
    important => 'info',
    note      => 'note',
    tip       => 'tip',
    warning   => 'warning',
  );

  for (my $i = 0; $i < @lines; $i++) {
    my $line = $lines[$i];

    if ($line =~ /^\s*```/) {
      $in_fence = !$in_fence;
      push @out, $line;
      next;
    }

    if (!$in_fence && $line =~ /^\s*>\s*\[!([A-Za-z]+)\]\s*(.*)\s*$/) {
      my $alert_raw = lc($1);
      my $admonition = $alert_map{$alert_raw} // 'note';
      my @body;

      my $first = $2 // '';
      push @body, $first if length($first);

      # Consume following blockquote lines as admonition body.
      while ($i + 1 < @lines && $lines[$i + 1] =~ /^\s*>\s?(.*)$/) {
        $i++;
        my $b = $1 // '';
        push @body, $b;
      }

      push @out, "!!! $admonition";
      for my $b (@body) {
        push @out, (length($b) ? "    $b" : '    ');
      }
      next;
    }

    push @out, $line;
  }

  return join("\n", @out);
}

my @files;
find(
  sub {
    return unless -f $_;
    return unless $_ =~ /\.md$/;
    push @files, $File::Find::name;
  },
  $docs_root
);

my $changed = 0;
for my $file (@files) {
  open my $in, '<', $file or die "Cannot read $file: $!\n";
  local $/;
  my $content = <$in>;
  close $in;

  my $normalized = normalize_github_alerts($content);
  next if $normalized eq $content;

  open my $out, '>', $file or die "Cannot write $file: $!\n";
  print {$out} $normalized;
  close $out;
  $changed++;
}

print "Processed ", scalar(@files), " markdown files ($changed modified)\n";
