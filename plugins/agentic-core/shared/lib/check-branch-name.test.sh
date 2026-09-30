#!/usr/bin/env bash
# Tests for check-branch-name.sh (D544). Run with:
#   bash plugins/agentic-core/shared/lib/check-branch-name.test.sh
#
# No framework — exits 0 when every case passes, 1 otherwise. Every pack and
# config is built in a temp dir, so no real pack is read.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/check-branch-name.sh"

PASS=0
FAIL=0

ok()  { echo "  ok: $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "    $2"; FAIL=$((FAIL + 1)); }

assert_eq()  { if [ "$2" == "$3" ]; then ok "$1"; else bad "$1" "expected: $2 — got: $3"; fi; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/check-branch-name.XXXXXX") || { echo "cannot create a temp dir" >&2; exit 2; }
[ -n "$WORK" ] && [ -d "$WORK" ] || { echo "cannot create a temp dir" >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT

# pack <name> <branch_name lines…> — a platform manifest under $WORK/plugins/<name>
pack() {
  local name="$1"; shift
  mkdir -p "$WORK/plugins/$name"
  { echo "kind: platform"; printf '%s\n' "$@"; } > "$WORK/plugins/$name/pack.yaml"
}
# config <platform> — a project config naming that platform pack
config() {
  printf 'version: 1\n\npacks:\n  platform: %s\n  tracker: example-tracker\n' "$1" > "$WORK/config.yaml"
}

run() { OUT=$(bash "$CHECK" "$@" --config "$WORK/config.yaml" --plugins-root "$WORK/plugins" 2>&1); CODE=$?; }

pack example-platform "branch_name:" "  max_length: 12" '  pattern: "^[a-z0-9/-]+$"'
config example-platform

echo "[ok] within both rules"
run feature-1
assert_eq "exit 0" "0" "$CODE"
assert_eq "ok line" "ok: branch=feature-1 length=9" "$OUT"
run "$(printf 'b%.0s' $(seq 1 12))"
assert_eq "exactly max_length → exit 0" "0" "$CODE"

echo "[too-long]"
run feature-12345
assert_eq "13 > 12 → exit 1" "1" "$CODE"
assert_eq "too-long line" "too-long: branch=feature-12345 length=13 limit=12" "$OUT"

echo "[bad-chars] checked before length"
run Feature_1
assert_eq "exit 3" "3" "$CODE"
assert_eq "bad-chars line" 'bad-chars: branch=Feature_1 pattern=^[a-z0-9/-]+$' "$OUT"
run "a_very_long_name_indeed"
assert_eq "long and bad → bad-chars (exit 3)" "3" "$CODE"

echo "[one rule only]"
pack length-only "branch_name:" "  max_length: 5"
config length-only
run ABC_D
assert_eq "no pattern → any characters, exit 0" "0" "$CODE"
run abcdef
assert_eq "too long → exit 1" "1" "$CODE"
pack pattern-only "branch_name:" '  pattern: "^[a-z]+$"'
config pattern-only
run "$(printf 'a%.0s' $(seq 1 90))"
assert_eq "no max_length → any length, exit 0" "0" "$CODE"
run abc1
assert_eq "pattern fails → exit 3" "3" "$CODE"

echo "[no constraint declared] every way it can be absent"
pack bare
config bare
run Anything_Goes
assert_eq "pack without branch_name → exit 0" "0" "$CODE"
assert_eq "says so" "ok: no constraint declared" "$OUT"
config not-installed
run Anything_Goes
assert_eq "platform pack not found → exit 0" "0" "$CODE"
assert_eq "says so" "ok: no constraint declared" "$OUT"
printf 'version: 1\n' > "$WORK/config.yaml"
run Anything_Goes
assert_eq "config names no platform → exit 0" "0" "$CODE"
OUT=$(bash "$CHECK" Anything_Goes --config "$WORK/missing.yaml" --plugins-root "$WORK/plugins" 2>&1); CODE=$?
assert_eq "no config file → exit 0" "0" "$CODE"
assert_eq "says so" "ok: no constraint declared" "$OUT"

echo "[usage]"
config example-platform
OUT=$(bash "$CHECK" 2>&1); CODE=$?
assert_eq "no argument → exit 2" "2" "$CODE"
OUT=$(bash "$CHECK" "" 2>&1); CODE=$?
assert_eq "empty branch → exit 2" "2" "$CODE"
OUT=$(bash "$CHECK" x --bogus 2>&1); CODE=$?
assert_eq "unknown option → exit 2" "2" "$CODE"

echo "[default plugins root] the sibling of this plugin's root"
REAL_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
for manifest in "$REAL_ROOT"/*/pack.yaml; do
  name=$(basename "$(dirname "$manifest")")
  grep -q '^kind: platform$' "$manifest" || continue
  printf 'version: 1\n\npacks:\n  platform: %s\n' "$name" > "$WORK/real.yaml"
  OUT=$(bash "$CHECK" x --config "$WORK/real.yaml" 2>&1); CODE=$?
  assert_eq "installed platform pack '$name' resolves without --plugins-root" "0" "$CODE"
done

echo "=== $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
