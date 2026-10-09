#!/usr/bin/env bash
# Tests for check-branch-name.sh (D544, D129). Run with:
#   bash plugins/agentic-core/shared/lib/check-branch-name.test.sh
#
# No framework — exits 0 when every case passes, 1 otherwise. Every pack,
# config and registry is built in a temp dir; only [shipped] reads the real
# plugins, registered into a temp project first.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/check-branch-name.sh"

PASS=0
FAIL=0

ok()  { echo "  ok: $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "    $2"; FAIL=$((FAIL + 1)); }

assert_eq()  { if [ "$2" == "$3" ]; then ok "$1"; else bad "$1" "expected: $2 — got: $3"; fi; }
assert_has()   { if [[ "$3" == *"$2"* ]]; then ok "$1"; else bad "$1" "expected to contain: $2 — got: $3"; fi; }
assert_lacks() { if [[ "$3" == *"$2"* ]]; then bad "$1" "must not contain: $2 — got: $3"; else ok "$1"; fi; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/check-branch-name.XXXXXX") || { echo "cannot create a temp dir" >&2; exit 2; }
[ -n "$WORK" ] && [ -d "$WORK" ] || { echo "cannot create a temp dir" >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT

PROJECT="$WORK/project"
REGISTRY="$PROJECT/.ai/run-context/plugin-roots"
mkdir -p "$REGISTRY"

# pack <name> <branch_name lines…> — a platform manifest under $WORK/plugins/<name>,
# registered in this test's project as its SessionStart hook would register it
pack() {
  local name="$1"; shift
  mkdir -p "$WORK/plugins/$name"
  { echo "kind: platform"; printf '%s\n' "$@"; } > "$WORK/plugins/$name/pack.yaml"
  printf '%s\n' "$WORK/plugins/$name" > "$REGISTRY/$name"
}
# config <platform> [max_length] — a project config naming that platform pack,
# with the project's branch_name.max_length when one is given
config() {
  printf 'version: 1\n\npacks:\n  platform: %s\n  tracker: example-tracker\n' "$1" > "$WORK/config.yaml"
  [ -n "${2:-}" ] && printf '\nbranch_name:\n  max_length: %s\n' "$2" >> "$WORK/config.yaml"
  return 0
}

run() { OUT=$(bash "$CHECK" "$@" --config "$WORK/config.yaml" --project-dir "$PROJECT" 2>&1); CODE=$?; }

pack example-platform "branch_name:" '  pattern: "^[a-z0-9/-]+$"'
config example-platform 12

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
pack length-only
config length-only 5
run ABC_D
assert_eq "no pattern → any characters, exit 0" "0" "$CODE"
run abcdef
assert_eq "too long → exit 1" "1" "$CODE"
assert_eq "the limit is the config's" "too-long: branch=abcdef length=6 limit=5" "$OUT"
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
printf 'version: 1\n' > "$WORK/config.yaml"
run Anything_Goes
assert_eq "config names no platform → exit 0" "0" "$CODE"

echo "[D129] the limit is read from the config, never from the pack"
pack stale-limit "branch_name:" "  max_length: 3" '  pattern: "^[a-z-]+$"'
config stale-limit
run abcdefgh
assert_eq "a max_length left in a manifest is not read → exit 0" "0" "$CODE"
run ab_c
assert_eq "its pattern still is → exit 3" "3" "$CODE"
config stale-limit 6
run abcdefgh
assert_eq "the config's limit applies → exit 1" "1" "$CODE"
assert_has "names the config's limit" "limit=6" "$OUT"
printf 'version: 1\n\nbranch_name:\n  max_length: 4\n' > "$WORK/config.yaml"
run abcde
assert_eq "a limit with no platform named still applies → exit 1" "1" "$CODE"
run Ab_c
assert_eq "and no pattern is checked → exit 0" "0" "$CODE"
printf 'version: 1\n\nbranch_name:\n\nplatform:\n  max_length: 2\n' > "$WORK/config.yaml"
run abcde
assert_eq "max_length is read only under branch_name → exit 0" "0" "$CODE"
for v in abc 0 -2; do
  printf 'version: 1\n\nbranch_name:\n  max_length: %s\n' "$v" > "$WORK/config.yaml"
  run abcde
  assert_eq "max_length '$v' → exit 4, never a silent pass" "4" "$CODE"
  assert_has "names the bad value" "invalid-config: branch_name.max_length=$v" "$OUT"
done
OUT=$(bash "$CHECK" Anything_Goes --config "$WORK/missing.yaml" --project-dir "$PROJECT" 2>&1); CODE=$?
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

echo "[fails closed] a named platform pack that cannot be resolved"
config not-installed 40
run anything
assert_eq "not resolved → exit 4" "4" "$CODE"
assert_has "says not-resolved, naming the pack" "not-resolved: platform=not-installed" "$OUT"
assert_lacks "never 'no constraint'" "no constraint" "$OUT"
printf '%s\n' "$WORK/gone/stale-platform" > "$REGISTRY/stale-platform"
config stale-platform
run anything
assert_eq "stale registry entry → exit 4" "4" "$CODE"
assert_has "carries the resolver's refusal" "refused" "$OUT"
mkdir -p "$WORK/plugins/no-manifest"
printf '%s\n' "$WORK/plugins/no-manifest" > "$REGISTRY/no-manifest"
config no-manifest
run anything
assert_eq "resolved root without pack.yaml → exit 4" "4" "$CODE"
assert_has "names the missing manifest" "no pack.yaml" "$OUT"
assert_lacks "never 'no constraint'" "no constraint" "$OUT"

echo "[registered] a valid name with the pack registered"
config example-platform
run feature-1
assert_eq "exit 0" "0" "$CODE"
assert_eq "ok line" "ok: branch=feature-1 length=9" "$OUT"

echo "[shipped] each shipped platform pack, registered in a temp project"
. "$SCRIPT_DIR/register-source-tree.sh"
REAL="$WORK/real-project"
register_source_tree "$REAL"; CODE=$?
assert_eq "the source tree's plugins are registered" "0" "$CODE"
LISTED=$(bash "$SCRIPT_DIR/resolve-plugin-root.sh" --list --project-dir "$REAL")
SEEN=0
while IFS=$'\t' read -r name root; do
  [ -n "$name" ] || continue
  [ -f "$root/pack.yaml" ] && grep -q '^kind: platform$' "$root/pack.yaml" || continue
  SEEN=$((SEEN + 1))
  printf 'version: 1\n\npacks:\n  platform: %s\n' "$name" > "$WORK/real.yaml"
  OUT=$(bash "$CHECK" x --config "$WORK/real.yaml" --project-dir "$REAL" 2>&1); CODE=$?
  assert_eq "shipped platform pack '$name' resolves through the registry" "0" "$CODE"
done <<< "$LISTED"
[ "$SEEN" -gt 0 ] && ok "at least one shipped platform pack checked ($SEEN)" || bad "no shipped platform pack was found"

echo "=== $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
