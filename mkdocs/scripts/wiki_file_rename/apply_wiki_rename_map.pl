#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use Encode qw(encode decode);
use File::Find;

my $map_file = 'mkdocs/scripts/wiki_rename_map.tsv';
my $apply = 0;
my $help = 0;

for (my $i = 0; $i < @ARGV; $i++) {
  my $arg = $ARGV[$i];
  if ($arg eq '--map') {
    $i++;
    die "Missing value for --map\n" if $i >= @ARGV;
    $map_file = $ARGV[$i];
  } elsif ($arg eq '--apply') {
    $apply = 1;
  } elsif ($arg eq '--help' || $arg eq '-h') {
    $help = 1;
  } else {
    die "Unknown argument: $arg\n";
  }
}

if ($help) {
  print <<'USAGE';
Usage:
  mkdocs/scripts/apply_wiki_rename_map.pl [--map <file>] [--apply]

Behavior:
  - Reads TSV map: old_filename<TAB>new_filename
  - Rewrites wiki/local links in all top-level *.md files
  - With --apply: renames files + writes updated content
  - Without --apply: dry-run report only
USAGE
  exit 0;
}

sub trim {
  my ($s) = @_;
  $s =~ s/^\s+|\s+$//g;
  return $s;
}

sub url_encode_utf8 {
  my ($text) = @_;
  my $bytes = encode('UTF-8', $text);
  my $out = '';
  for my $ord (unpack('C*', $bytes)) {
    my $ch = chr($ord);
    if ($ch =~ /[A-Za-z0-9\-._~]/) {
      $out .= $ch;
    } else {
      $out .= sprintf("%%%02X", $ord);
    }
  }
  return $out;
}

sub url_decode_utf8 {
  my ($text) = @_;
  return $text unless $text =~ /%[0-9A-Fa-f]{2}/;
  my $bytes = $text;
  $bytes =~ s/%([0-9A-Fa-f]{2})/pack('C', hex($1))/ge;
  my $decoded = eval { decode('UTF-8', $bytes, 1) };
  return defined($decoded) ? $decoded : $text;
}

-d '.' or die "Run from repo root\n";
-f $map_file or die "Missing map file: $map_file\n";
my $git_check = `git rev-parse --is-inside-work-tree 2>/dev/null`;
chomp $git_check;
($? == 0 && $git_check eq 'true')
  or die "This script must be run inside a git work tree\n";
binmode(STDOUT, ':encoding(UTF-8)');
binmode(STDERR, ':encoding(UTF-8)');

my (%old_to_new_file, %old_to_new_stem, %new_files_seen);
my (%changed_old_to_new_file, %changed_old_to_new_stem);
my @ordered_pairs;

open my $mf, '<:encoding(UTF-8)', $map_file or die "Cannot read $map_file: $!\n";
while (my $line = <$mf>) {
  chomp $line;
  next if $line =~ /^\s*$/;
  next if $line =~ /^\s*#/;

  my ($old, $new) = split /\t/, $line, 3;
  die "Invalid mapping row (need 2 columns): $line\n" unless defined $old && defined $new;

  $old = trim($old);
  $new = trim($new);

  die "Invalid old filename (must end with .md): $old\n" unless $old =~ /\.md$/;
  die "Invalid new filename (must end with .md): $new\n" unless $new =~ /\.md$/;

  die "Duplicate old filename in map: $old\n" if exists $old_to_new_file{$old};
  die "Duplicate new filename in map: $new\n" if exists $new_files_seen{$new};

  my $old_stem = $old;
  $old_stem =~ s/\.md$//;
  my $new_stem = $new;
  $new_stem =~ s/\.md$//;

  $old_to_new_file{$old} = $new;
  $old_to_new_stem{$old_stem} = $new_stem;
  $new_files_seen{$new} = 1;
  if ($old ne $new) {
    $changed_old_to_new_file{$old} = $new;
    $changed_old_to_new_stem{$old_stem} = $new_stem;
  }

  push @ordered_pairs, [$old, $new, $old_stem, $new_stem];
}
close $mf;

my @md_files = sort grep { -f $_ } map { decode('UTF-8', $_) } glob('*.md');
my %current_file_set = map { $_ => 1 } @md_files;

for my $pair (@ordered_pairs) {
  my ($old, $new) = @$pair[0,1];
  die "Mapped source does not exist: $old\n" unless -f $old;
  if ($old ne $new && -f $new && !exists $old_to_new_file{$new}) {
    die "Target filename already exists and is not remapped away: $new\n";
  }
}

my (%file_change_counts, %content_updates);
my $total_ref_changes = 0;

sub git_mv {
  my ($from, $to) = @_;
  my $rc = system('git', 'mv', '-f', '--', $from, $to);
  if ($rc != 0) {
    die "Failed git mv $from -> $to (exit=$rc)\n";
  }
}

sub rewrite_content {
  my ($content) = @_;
  my $changed = 0;

  # Rewrite GitHub wiki links (markdown text, html href, bare links).
  $content =~ s{https://github\.com/([^/\s)"'>]+)/([^/\s)"'>]+)/wiki/([^\s)"'>#]+)(#[^\s)"'>]+)?}{
    my ($owner, $repo, $slug_raw, $anchor) = ($1, $2, $3, $4 // '');
    my $decoded = url_decode_utf8($slug_raw);

    if (exists $changed_old_to_new_stem{$decoded}) {
      $changed++;
      my $new_slug = url_encode_utf8($changed_old_to_new_stem{$decoded});
      "https://github.com/$owner/$repo/wiki/$new_slug$anchor";
    } else {
      "https://github.com/$owner/$repo/wiki/$slug_raw$anchor";
    }
  }ge;

  # Rewrite local markdown links to renamed pages.
  $content =~ s{\]\(([^)]+)\)}{
    my $ref = $1;
    my $orig = $ref;

    my ($path, $anchor) = split(/#/, $ref, 2);
    if (defined $path && $path =~ m{^(?:\./)?([^/]+\.md)$}) {
      my $base = $1;
      if (exists $changed_old_to_new_file{$base}) {
        my $new_base = $changed_old_to_new_file{$base};
        $ref = $new_base . (defined($anchor) ? "#$anchor" : '');
      }
    }

    $changed++ if $ref ne $orig;
    "]($ref)";
  }ge;

  # Rewrite html href links to renamed pages.
  $content =~ s{href=(['"])([^'"]+)\1}{
    my ($q, $ref) = ($1, $2);
    my $orig = $ref;

    my ($path, $anchor) = split(/#/, $ref, 2);
    if (defined $path && $path =~ m{^(?:\./)?([^/]+\.md)$}) {
      my $base = $1;
      if (exists $changed_old_to_new_file{$base}) {
        my $new_base = $changed_old_to_new_file{$base};
        $ref = $new_base . (defined($anchor) ? "#$anchor" : '');
      }
    }

    $changed++ if $ref ne $orig;
    "href=$q$ref$q";
  }ge;

  return ($content, $changed);
}

for my $file (@md_files) {
  open my $in, '<:encoding(UTF-8)', $file or die "Cannot read $file: $!\n";
  local $/;
  my $content = <$in>;
  close $in;

  my ($new_content, $changes) = rewrite_content($content);
  next if $changes == 0;

  $file_change_counts{$file} = $changes;
  $content_updates{$file} = $new_content;
  $total_ref_changes += $changes;
}

my @renames = grep { $_->[0] ne $_->[1] } @ordered_pairs;

print "Map entries: ", scalar(@ordered_pairs), "\n";
print "Planned file renames: ", scalar(@renames), "\n";
print "Files with link updates: ", scalar(keys %file_change_counts), "\n";
print "Total link replacements: $total_ref_changes\n";

if (%file_change_counts) {
  print "\nLink update details:\n";
  for my $f (sort keys %file_change_counts) {
    print "  $f: $file_change_counts{$f}\n";
  }
}

if (!$apply) {
  print "\nDry-run only. Re-run with --apply to write changes and rename files.\n";
  exit 0;
}

# Two-phase rename to handle name swaps safely.
my @tmp_moves;
my $tmp_idx = 0;
for my $pair (@renames) {
  my ($old, $new) = @$pair[0,1];
  my $tmp = ".rename_tmp_$tmp_idx.md";
  $tmp_idx++;
  while (-e $tmp) {
    $tmp = ".rename_tmp_$tmp_idx.md";
    $tmp_idx++;
  }

  git_mv($old, $tmp);
  push @tmp_moves, [$tmp, $new, $old];
}

for my $mv (@tmp_moves) {
  my ($tmp, $new, $old) = @$mv;
  git_mv($tmp, $new);
}

for my $file (sort keys %content_updates) {
  my $target = $file;
  $target = $old_to_new_file{$file} if exists $old_to_new_file{$file};

  open my $out, '>:encoding(UTF-8)', $target or die "Cannot write $target: $!\n";
  print {$out} $content_updates{$file};
  close $out;
}

# Validation pass.
my @post_md = sort grep { -f $_ } map { decode('UTF-8', $_) } glob('*.md');
my %post_file_set = map { $_ => 1 } @post_md;
my %post_stem_set = map { (my $s = $_) =~ s/\.md$//; $s => 1 } @post_md;

my @errors;
for my $pair (@renames) {
  my ($old, $new) = @$pair[0,1];
  push @errors, "Old filename still exists after rename: $old" if -f $old;
  push @errors, "New filename missing after rename: $new" unless -f $new;
}

for my $file (@post_md) {
  open my $in, '<:encoding(UTF-8)', $file or die "Cannot read $file: $!\n";
  local $/;
  my $content = <$in>;
  close $in;

  while ($content =~ m{https://github\.com/[^/\s)"'>]+/[^/\s)"'>]+/wiki/([^\s)"'>#]+)}g) {
    my $slug_raw = $1;
    my $decoded = url_decode_utf8($slug_raw);

    if (exists $changed_old_to_new_stem{$decoded}) {
      push @errors, "$file still references old wiki slug: $decoded";
      next;
    }

    next if exists $post_stem_set{$decoded};
    next if $decoded eq 'Home';
    next if $decoded =~ m{^images/};

    push @errors, "$file has wiki link to missing page slug: $decoded";
  }

  while ($content =~ m{\]\(([^)]+)\)}g) {
    my $ref = $1;
    my ($path) = split(/#/, $ref, 2);
    next unless defined $path;
    if ($path =~ m{^(?:\./)?([^/]+\.md)$}) {
      my $base = $1;
      if (!exists $post_file_set{$base}) {
        push @errors, "$file has markdown link to missing file: $base";
      }
    }
  }

  while ($content =~ m{href=(['"])([^'"]+)\1}g) {
    my $ref = $2;
    my ($path) = split(/#/, $ref, 2);
    next unless defined $path;
    if ($path =~ m{^(?:\./)?([^/]+\.md)$}) {
      my $base = $1;
      if (!exists $post_file_set{$base}) {
        push @errors, "$file has href link to missing file: $base";
      }
    }
  }
}

if (@errors) {
  print "\nValidation failed (", scalar(@errors), " issues):\n";
  my %seen;
  for my $e (@errors) {
    next if $seen{$e}++;
    print "  - $e\n";
  }
  exit 1;
}

print "\nApplied successfully. Validation passed.\n";
