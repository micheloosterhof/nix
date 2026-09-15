#!/usr/bin/env bash
# ABOUTME: Merges the authored Claude Code settings fragment into the live
# ABOUTME: settings.json, which Claude Code itself also writes to.
set -euo pipefail

if [ $# -ne 2 ]; then
  echo "usage: merge-settings.sh FRAGMENT.json TARGET.json" >&2
  exit 2
fi
fragment=$1
target=$2

# Only JSON objects can be merged; anything else is refused so a damaged
# file is never overwritten.
is_object() {
  jq -e 'type == "object"' "$1" >/dev/null 2>&1
}

is_object "$fragment" || {
  echo "merge-settings: $fragment is not a JSON object" >&2
  exit 1
}
if [ -e "$target" ]; then
  is_object "$target" || {
    echo "merge-settings: $target is not a JSON object, leaving it alone" >&2
    exit 1
  }
else
  mkdir -p "$(dirname "$target")"
  echo '{}' >"$target"
fi

tmp=$(mktemp "$(dirname "$target")/.settings.XXXXXX")
trap 'rm -f "$tmp"' EXIT
# `*` merges objects recursively; on scalars and arrays the fragment wins.
jq --indent 2 -s '.[0] * .[1]' "$target" "$fragment" >"$tmp"
if ! cmp -s "$tmp" "$target"; then
  mv "$tmp" "$target"
fi
