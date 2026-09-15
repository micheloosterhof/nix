#!/usr/bin/env bash
# ABOUTME: Tests merge-settings.sh: managed keys win, everything else in the
# ABOUTME: live file survives, and a corrupt live file is never clobbered.
set -euo pipefail

merge=$1
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

cat >"$tmp/fragment.json" <<'JSON'
{"env":{"SHELL":"/bin/bash","DISABLE_TELEMETRY":"1"},"permissions":{"deny":["Bash(nc *)"]}}
JSON

# Live file with keys Claude Code wrote itself, plus stale managed values.
cat >"$tmp/live.json" <<'JSON'
{"model":"x","env":{"SHELL":"/bin/zsh","FOO":"1"},"permissions":{"allow":["Bash(ls *)"],"deny":["Bash(old)"]}}
JSON
bash "$merge" "$tmp/fragment.json" "$tmp/live.json"
[ "$(jq -r .model "$tmp/live.json")" = x ] || fail "foreign top-level key lost"
[ "$(jq -r '.permissions.allow[0]' "$tmp/live.json")" = 'Bash(ls *)' ] || fail "allow list lost"
[ "$(jq -r .env.FOO "$tmp/live.json")" = 1 ] || fail "foreign env key lost"
[ "$(jq -r .env.SHELL "$tmp/live.json")" = /bin/bash ] || fail "managed env value not applied"
[ "$(jq -r .env.DISABLE_TELEMETRY "$tmp/live.json")" = 1 ] || fail "new managed env key missing"
[ "$(jq -c .permissions.deny "$tmp/live.json")" = '["Bash(nc *)"]' ] || fail "deny list not replaced wholesale"

# A second run must be a no-op.
cp "$tmp/live.json" "$tmp/first.json"
bash "$merge" "$tmp/fragment.json" "$tmp/live.json"
cmp -s "$tmp/first.json" "$tmp/live.json" || fail "second run changed the file"

# No live file yet: create it from the fragment.
bash "$merge" "$tmp/fragment.json" "$tmp/new/settings.json"
[ "$(jq -r .env.SHELL "$tmp/new/settings.json")" = /bin/bash ] || fail "missing live file not created"

# A corrupt live file fails the run and is left untouched.
echo '{not json' >"$tmp/bad.json"
if bash "$merge" "$tmp/fragment.json" "$tmp/bad.json" 2>/dev/null; then
  fail "corrupt live file accepted"
fi
[ "$(cat "$tmp/bad.json")" = '{not json' ] || fail "corrupt live file clobbered"

echo ok
