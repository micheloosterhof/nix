#!/usr/bin/env bash
# ABOUTME: Merges the authored Claude Code settings fragment into the live
# ABOUTME: settings.json, which Claude Code itself also writes to.
set -euo pipefail

fragment=$1
target=$2

if [ -e "$target" ]; then
  if ! jq -e . "$target" >/dev/null 2>&1; then
    echo "merge-settings: $target is not valid JSON, leaving it alone" >&2
    exit 1
  fi
else
  mkdir -p "$(dirname "$target")"
  echo '{}' >"$target"
fi

tmp=$(mktemp "$(dirname "$target")/.settings.XXXXXX")
# `*` merges objects recursively; on scalars and arrays the fragment wins.
jq --indent 2 -s '.[0] * .[1]' "$target" "$fragment" >"$tmp"
if cmp -s "$tmp" "$target"; then
  rm -f "$tmp"
else
  mv "$tmp" "$target"
fi
