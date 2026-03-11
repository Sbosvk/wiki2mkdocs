#!/usr/bin/env bash
set -euo pipefail

OUT_FILE="${1:-mkdocs/scripts/wiki_rename_map.tsv}"
INCLUDE_META="${INCLUDE_META:-0}"

if [[ "$INCLUDE_META" == "1" ]]; then
  find . -maxdepth 1 -type f -name '*.md' -printf '%f\n' | LC_ALL=C sort > /tmp/wiki_pages_list.$$ 
else
  find . -maxdepth 1 -type f -name '*.md' \
    ! -name '_Sidebar.md' \
    ! -name '_Footer.md' \
    -printf '%f\n' | LC_ALL=C sort > /tmp/wiki_pages_list.$$ 
fi

{
  echo "# Wiki rename mapping template"
  echo "# old_filename<TAB>new_filename"
  echo "# Edit column 2, keep column 1 unchanged."
  echo "#"
  while IFS= read -r f; do
    printf '%s\t%s\n' "$f" "$f"
  done < /tmp/wiki_pages_list.$$
} > "$OUT_FILE"

rm -f /tmp/wiki_pages_list.$$ 

echo "Wrote template mapping: $OUT_FILE"
