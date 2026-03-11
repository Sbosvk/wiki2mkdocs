#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use Encode qw(decode);

binmode(STDOUT, ':encoding(UTF-8)');
binmode(STDERR, ':encoding(UTF-8)');

sub url_decode_utf8 {
  my ($text) = @_;
  return $text unless defined $text && $text =~ /%[0-9A-Fa-f]{2}/;
  my $bytes = $text;
  $bytes =~ s/%([0-9A-Fa-f]{2})/pack('C', hex($1))/ge;
  my $decoded = eval { decode('UTF-8', $bytes, 1) };
  return defined($decoded) ? $decoded : $text;
}

sub ensure_utf8 {
  my ($s) = @_;
  return $s if utf8::is_utf8($s);
  my $decoded = eval { decode('UTF-8', $s, 1) };
  return defined($decoded) ? $decoded : $s;
}

sub canon_key {
  my ($s) = @_;
  $s = ensure_utf8($s // '');
  $s = lc $s;
  $s =~ s/[^a-z0-9]+//g;
  return $s;
}

opendir my $dh, '.' or die "Cannot open current directory: $!\n";
my @md_files = sort map { ensure_utf8($_) } grep { /\.md$/ && -f $_ } readdir $dh;
closedir $dh;
if (!@md_files) {
  die "No markdown files found in current directory\n";
}

my %valid_file = map { $_ => 1 } @md_files;
my %valid_stem;
my %valid_stem_key;
for my $f (@md_files) {
  (my $stem = $f) =~ s/\.md$//;
  $valid_stem{$stem} = 1;
  $valid_stem_key{canon_key($stem)} = 1;
}
$valid_stem{'Home'} = 1 if exists $valid_file{'Home.md'};
$valid_stem_key{canon_key('Home')} = 1 if exists $valid_file{'Home.md'};

my @issues;
my $checked_wiki_links = 0;
my $checked_local_links = 0;

for my $file (@md_files) {
  open my $fh, '<:encoding(UTF-8)', $file or die "Cannot read $file: $!\n";
  my $line_no = 0;

  while (my $line = <$fh>) {
    $line_no++;

    while ($line =~ m{https://github\.com/[^/\s)"'>]+/[^/\s)"'>]+/wiki(?:/([^\s)"'>#]+))?(?:#[^\s)"'>]+)?}g) {
      $checked_wiki_links++;
      my $slug = defined($1) && length($1) ? $1 : 'Home';
      $slug = url_decode_utf8($slug);

      next if exists $valid_stem{$slug};
      next if exists $valid_stem_key{canon_key($slug)};
      next if $slug =~ m{^images/};

      push @issues, {
        file => $file,
        line => $line_no,
        type => 'wiki-url',
        target => $slug,
        msg => 'wiki page not found in repo',
      };
    }

    while ($line =~ m{\]\(([^)]+)\)}g) {
      my $ref = $1;
      next if $ref =~ m{^(?:[a-zA-Z][a-zA-Z0-9+.-]*:|//|#)};

      my ($path) = split(/#/, $ref, 2);
      next unless defined $path;

      if ($path =~ m{^(?:\./)?([^/]+\.md)$}) {
        $checked_local_links++;
        my $target = $1;
        if (!exists $valid_file{$target}) {
          push @issues, {
            file => $file,
            line => $line_no,
            type => 'md-link',
            target => $target,
            msg => 'local markdown target missing',
          };
        }
      }
    }

    while ($line =~ m{href=(['"])([^'"]+)\1}g) {
      my $ref = $2;
      next if $ref =~ m{^(?:[a-zA-Z][a-zA-Z0-9+.-]*:|//|#)};

      my ($path) = split(/#/, $ref, 2);
      next unless defined $path;

      if ($path =~ m{^(?:\./)?([^/]+\.md)$}) {
        $checked_local_links++;
        my $target = $1;
        if (!exists $valid_file{$target}) {
          push @issues, {
            file => $file,
            line => $line_no,
            type => 'href-md',
            target => $target,
            msg => 'html href markdown target missing',
          };
        }
      }
    }
  }

  close $fh;
}

print "Wiki link check summary\n";
print "- Files scanned: " . scalar(@md_files) . "\n";
print "- Wiki URLs checked: $checked_wiki_links\n";
print "- Local .md links checked: $checked_local_links\n";
print "- Issues: " . scalar(@issues) . "\n";

if (@issues) {
  print "\nBroken links\n";
  my %seen;
  for my $i (@issues) {
    my $k = join('|', $i->{file}, $i->{line}, $i->{type}, $i->{target});
    next if $seen{$k}++;
    print "$i->{file}:$i->{line} [$i->{type}] $i->{target} -> $i->{msg}\n";
  }
  exit 1;
}

print "\nNo broken internal wiki links found.\n";
exit 0;
