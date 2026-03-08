#!/usr/bin/env perl
use strict;
use warnings;

my $repo_root = '.';
my $base_file = "$repo_root/mkdocs/mkdocs.base.yml";
my $map_file = $ENV{WIKI_SYNC_MAP_FILE} // "$repo_root/mkdocs/scripts/wiki_sync_map.tsv";
my $out_file = "$repo_root/mkdocs/mkdocs.yml";

for my $f ($base_file, $map_file) {
  die "Missing required file: $f\n" unless -f $f;
}

sub titleize_segment {
  my ($s) = @_;
  $s =~ s/-/ /g;
  $s =~ s/\b(\w)/\U$1/g;

  # Acronym cleanup overrides
  # Examples:
  # $s =~ s/\bRcon\b/RCON/g;
  # $s =~ s/\bVip\b/VIP/g;
  # $s =~ s/\bVips\b/VIPs/g;
  # $s =~ s/\bApi\b/API/g;
  # $s =~ s/\bAws\b/AWS/g;
  # $s =~ s/\bSsh\b/SSH/g;
  # $s =~ s/\bVps\b/VPS/g;
  # $s =~ s/\bPostgresql\b/PostgreSQL/g;


  return $s;
}

# Node structure:
# {
#   sections => { key => node },
#   section_order => [],
#   pages => [ {label=>..., path=>...}, ... ],
#   page_seen => { path => 1 }
# }
sub new_node {
  return {
    sections => {},
    section_order => [],
    pages => [],
    page_seen => {},
  };
}

my $root = new_node();

open my $mf, '<', $map_file or die "Cannot read $map_file: $!\n";
while (my $line = <$mf>) {
  chomp $line;
  next if $line =~ /^\s*$/;
  next if $line =~ /^\s*#/;

  my ($src, $dest, $nav_label_override) = split /\t/, $line, 3;
  next unless defined $src && defined $dest;

  $dest =~ s/^\s+|\s+$//g;
  next if $dest eq '';
  if (defined $nav_label_override) {
    $nav_label_override =~ s/^\s+|\s+$//g;
  }

  my @parts = split m{/}, $dest;
  my $file = pop @parts;
  next unless defined $file && $file =~ /\.md$/;

  my $node = $root;
  for my $seg (@parts) {
    next if $seg eq '';
    if (!exists $node->{sections}{$seg}) {
      $node->{sections}{$seg} = new_node();
      push @{$node->{section_order}}, $seg;
    }
    $node = $node->{sections}{$seg};
  }

  next if $node->{page_seen}{$dest};
  $node->{page_seen}{$dest} = 1;

  (my $stem = $file) =~ s/\.md$//;
  my $label = (defined($nav_label_override) && length($nav_label_override))
    ? $nav_label_override
    : (($stem eq 'index') ? 'Home' : titleize_segment($stem));
  push @{$node->{pages}}, { label => $label, path => $dest };
}
close $mf;

sub emit_node {
  my ($fh, $node, $indent) = @_;

  for my $page (@{$node->{pages}}) {
    print {$fh} (' ' x $indent) . '- ' . $page->{label} . ': ' . $page->{path} . "\n";
  }

  for my $seg (@{$node->{section_order}}) {
    my $label = titleize_segment($seg);
    print {$fh} (' ' x $indent) . '- ' . $label . ":\n";
    emit_node($fh, $node->{sections}{$seg}, $indent + 2);
  }
}

open my $bf, '<', $base_file or die "Cannot read $base_file: $!\n";
my @base = <$bf>;
close $bf;

open my $out, '>', $out_file or die "Cannot write $out_file: $!\n";
print {$out} @base;
print {$out} "\n" unless @base && $base[-1] =~ /\n\z/;
print {$out} "\n" unless @base && $base[-1] =~ /^\s*\n\z/;
print {$out} "nav:\n";
emit_node($out, $root, 2);
close $out;

print "Generated $out_file from $base_file + $map_file\n";
