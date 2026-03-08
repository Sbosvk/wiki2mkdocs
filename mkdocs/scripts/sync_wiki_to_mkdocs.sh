#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MAP_GENERATOR="$SCRIPT_DIR/generate_wiki_sync_map.pl"
ADMONITION_NORMALIZER="$SCRIPT_DIR/normalize_admonitions.pl"
LINK_NORMALIZER="$SCRIPT_DIR/normalize_wiki_links.pl"
MKDOCS_GENERATOR="$SCRIPT_DIR/generate_mkdocs_yml.pl"

SRC_ROOT="${SOURCE_ROOT:-$REPO_ROOT}"
DST_ROOT="${DEST_ROOT:-$REPO_ROOT/mkdocs/docs}"
TMP_ROOT="$REPO_ROOT/mkdocs/.docs_tmp"
MAP_FILE="$(mktemp)"

cleanup() {
  rm -f "$MAP_FILE"
}
trap cleanup EXIT

if [[ ! -d "$SRC_ROOT" ]]; then
  echo "Missing source root: $SRC_ROOT" >&2
  exit 1
fi

if [[ ! -x "$MAP_GENERATOR" ]]; then
  echo "Missing or non-executable map generator: $MAP_GENERATOR" >&2
  exit 1
fi

if [[ ! -x "$ADMONITION_NORMALIZER" ]]; then
  echo "Missing or non-executable admonition normalizer: $ADMONITION_NORMALIZER" >&2
  exit 1
fi

if [[ ! -x "$LINK_NORMALIZER" ]]; then
  echo "Missing or non-executable link normalizer: $LINK_NORMALIZER" >&2
  exit 1
fi

if [[ ! -x "$MKDOCS_GENERATOR" ]]; then
  echo "Missing or non-executable MkDocs generator: $MKDOCS_GENERATOR" >&2
  exit 1
fi

"$MAP_GENERATOR" "$SRC_ROOT" "$MAP_FILE"

if [[ ! -f "$MAP_FILE" ]]; then
  echo "Failed to generate mapping file: $MAP_FILE" >&2
  exit 1
fi

echo "===== GENERATED WIKI MAP ====="
cat "$MAP_FILE"
echo "===== END GENERATED WIKI MAP ====="

rm -rf "$TMP_ROOT"
mkdir -p "$TMP_ROOT"

mapped_count=0
while IFS=$'\t' read -r src rel_dst _rest; do
  [[ -z "${src// }" ]] && continue
  [[ "${src:0:1}" == "#" ]] && continue

  src_path="$SRC_ROOT/$src"
  dst_path="$TMP_ROOT/$rel_dst"

  if [[ ! -f "$src_path" ]]; then
    echo "Mapped source is missing: $src (looked in SOURCE_ROOT=$SRC_ROOT)" >&2
    echo "If running from a separate pages repo, clone the wiki first and run:" >&2
    echo "  SOURCE_ROOT=<path-to-wiki-repo> ./mkdocs/scripts/sync_wiki_to_mkdocs.sh" >&2
    exit 1
  fi

  mkdir -p "$(dirname "$dst_path")"
  cp "$src_path" "$dst_path"
  mapped_count=$((mapped_count + 1))
done < "$MAP_FILE"

# Copy images so old relative image paths continue to work.
if [[ -d "$SRC_ROOT/images" ]]; then
  mkdir -p "$TMP_ROOT/images" "$TMP_ROOT/assets/images"
  cp -R "$SRC_ROOT/images/." "$TMP_ROOT/images/"
  cp -R "$SRC_ROOT/images/." "$TMP_ROOT/assets/images/"
fi

# Guardrail: ensure every top-level wiki page is explicitly mapped.
actual_pages_file="$(mktemp)"
mapped_pages_file="$(mktemp)"

find "$SRC_ROOT" -maxdepth 1 -type f -name '*.md' \
  ! -name '_Sidebar.md' \
  ! -name '_Footer.md' \
  -printf '%f\n' | sort > "$actual_pages_file"

awk -F'\t' 'NF >= 2 && $1 !~ /^#/ && $1 !~ /^\s*$/ { print $1 }' "$MAP_FILE" | sort > "$mapped_pages_file"

unmapped="$(comm -23 "$actual_pages_file" "$mapped_pages_file" || true)"
if [[ -n "$unmapped" ]]; then
  echo "Unmapped wiki markdown files detected:" >&2
  echo "$unmapped" >&2
  rm -f "$actual_pages_file" "$mapped_pages_file"
  exit 1
fi

rm -f "$actual_pages_file" "$mapped_pages_file"

rm -rf "$DST_ROOT"
mv "$TMP_ROOT" "$DST_ROOT"

"$ADMONITION_NORMALIZER"
WIKI_SYNC_MAP_FILE="$MAP_FILE" "$LINK_NORMALIZER"
WIKI_SYNC_MAP_FILE="$MAP_FILE" "$MKDOCS_GENERATOR"

final_md_count=$(find "$DST_ROOT" -type f -name '*.md' | wc -l | tr -d ' ')
echo "Synced $mapped_count pages into mkdocs/docs ($final_md_count markdown files after normalization)."
