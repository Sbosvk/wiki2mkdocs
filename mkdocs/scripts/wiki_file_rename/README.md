# Wiki File Rename Helper

These scripts are optional helpers for large wiki filename refactors before running the main sync pipeline.

Run them from the root of your local wiki clone (the folder that contains the top-level `.md` wiki pages).

## Files

- `generate_wiki_rename_map.sh`
  - Generates a TSV template: `old_filename<TAB>new_filename`.
- `apply_wiki_rename_map.pl`
  - Rewrites links and renames files using `git mv`.
  - Supports dry-run and apply mode.
- `../check_wiki_links.pl`
  - Shared checker that scans wiki markdown files for broken wiki/local markdown links.

## Typical Workflow

1. Generate template map:

```bash
./mkdocs/scripts/wiki_file_rename/generate_wiki_rename_map.sh mkdocs/scripts/wiki_rename_map.tsv
```

2. Edit column 2 in `mkdocs/scripts/wiki_rename_map.tsv` with desired new names.

3. Validate current links before rename:

```bash
perl mkdocs/scripts/check_wiki_links.pl
```

4. Dry-run rename + link rewrites:

```bash
perl mkdocs/scripts/wiki_file_rename/apply_wiki_rename_map.pl --map mkdocs/scripts/wiki_rename_map.tsv
```

5. Apply changes:

```bash
perl mkdocs/scripts/wiki_file_rename/apply_wiki_rename_map.pl --map mkdocs/scripts/wiki_rename_map.tsv --apply
```

6. Validate links again:

```bash
perl mkdocs/scripts/check_wiki_links.pl
```

## Notes

- `apply_wiki_rename_map.pl` requires a git work tree and uses `git mv` intentionally.
- Use dry-run first; only use `--apply` once report looks correct.
