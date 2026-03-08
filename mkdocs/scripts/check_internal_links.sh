#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."

if ! command -v rg >/dev/null 2>&1; then
  echo "Missing dependency: ripgrep (rg) is required for link checks" >&2
  exit 2
fi

failed=0

if rg -nP '\]\((?![a-zA-Z][a-zA-Z0-9+.-]*:|#)[^)]+\.md(?:#[^)]+)?\)' mkdocs/docs; then
  echo "Found markdown links still targeting .md files" >&2
  failed=1
fi

if rg -nP 'href=["\x27](?![a-zA-Z][a-zA-Z0-9+.-]*:|#)[^"\x27]+\.md(?:#[^"\x27]+)?["\x27]' mkdocs/docs; then
  echo "Found HTML href links still targeting .md files" >&2
  failed=1
fi

if [[ "$failed" -ne 0 ]]; then
  echo "Internal link normalization check failed" >&2
  exit 1
fi

echo "Internal link normalization check passed"
