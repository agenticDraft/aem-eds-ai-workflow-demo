#!/usr/bin/env bash
# check-branch-length.test.sh — the branch-length checker (D539, D129). No
# framework; exits 0 when every case passes, 1 otherwise. Every config is a
# fixture built in a temp dir; nothing is read from the repository the suite
# sits in.
#
# Usage:
#   bash check-branch-length.test.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/check-branch-length.sh"

PASS=0
FAIL=0

ok()  { echo "  ok: $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "    $2"; FAIL=$((FAIL + 1)); }

assert_eq()  { if [ "$2" == "$3" ]; then ok "$1"; else bad "$1" "expected: $2 — got: $3"; fi; }
assert_has() { if [[ "$3" == *"$2"* ]]; then ok "$1"; else bad "$1" "expected to contain: $2 — got: $3"; fi; }

# name_of_length <n> — a branch name exactly <n> characters long
name_of_length() { printf 'b%.0s' $(seq 1 "$1"); }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/check-branch-length.XXXXXX")
[ -n "$WORK" ] && [ -d "$WORK" ] || { echo "cannot create a temporary directory"; exit 1; }
trap 'rm -rf "$WORK"' EXIT

# A fixture project's own values: a 40-character host suffix, so a limit of 23.
SUFFIX="--a-fixture-site-repository--fixture-org"
CONFIG="$WORK/config.yaml"
printf 'version: 1\n\nbranch_name:\n  max_length: 23\n\nplatform:\n  preview_host_suffix: "%s"\n' "$SUFFIX" > "$CONFIG"

run() { OUT=$(bash "$CHECK" "$@" 2>&1); CODE=$?; }

echo "[ok] 22 and 23 characters"
run "$(name_of_length 22)" --config "$CONFIG"
assert_eq "22 → exit 0" "0" "$CODE"
assert_has "22 → ok line" "ok: branch=$(name_of_length 22) length=22 limit=23" "$OUT"
run "$(name_of_length 23)" --config "$CONFIG"
assert_eq "23 → exit 0" "0" "$CODE"
assert_has "23 → ok line" "ok: branch=$(name_of_length 23) length=23 limit=23" "$OUT"

echo "[too-long] 24 characters"
run "$(name_of_length 24)" --config "$CONFIG"
assert_eq "24 → exit 1" "1" "$CODE"
assert_has "24 → too-long line" "too-long: branch=$(name_of_length 24) length=24 limit=23" "$OUT"

echo "[real names] a branch within the limit and one over it"
run "phase-28-task-4-verify" --config "$CONFIG"
assert_eq "phase-28-task-4-verify (22) → ok" "0" "$CODE"
run "phase-28-task-3-draft-server" --config "$CONFIG"
assert_eq "phase-28-task-3-draft-server (28) → too-long" "1" "$CODE"
assert_has "names the length" "length=28 limit=23" "$OUT"

echo "[slash] a slash counts as one character, as the dev server replaces it with '-'"
run "feature/$(name_of_length 16)" --config "$CONFIG"
assert_eq "feature/ + 16 = 24 → too-long" "1" "$CODE"
assert_has "length 24" "length=24" "$OUT"

echo "[config] the limit is the config's, not a number in the script"
printf 'version: 1\n\nbranch_name:\n  max_length: 30\n' > "$WORK/other.yaml"
run "$(name_of_length 30)" --config "$WORK/other.yaml"
assert_eq "30 under a limit of 30 → exit 0" "0" "$CODE"
assert_has "names that limit" "limit=30" "$OUT"
run "$(name_of_length 31)" --config "$WORK/other.yaml"
assert_eq "31 → exit 1" "1" "$CODE"

echo "[config] the default is .ai/project-config.yaml in the current directory"
mkdir -p "$WORK/project/.ai"
cp "$CONFIG" "$WORK/project/.ai/project-config.yaml"
OUT=$(cd "$WORK/project" && bash "$CHECK" "$(name_of_length 24)" 2>&1); CODE=$?
assert_eq "24 against the project's own config → exit 1" "1" "$CODE"
assert_has "limit read from it" "limit=23" "$OUT"

echo "[not-configured] no value is never a default limit"
run "$(name_of_length 1)" --config "$WORK/missing.yaml"
assert_eq "no config file → exit 4" "4" "$CODE"
assert_has "says not-configured" "not-configured: branch_name.max_length" "$OUT"
printf 'version: 1\n\nplatform:\n  max_length: 23\n' > "$WORK/nolimit.yaml"
run "$(name_of_length 1)" --config "$WORK/nolimit.yaml"
assert_eq "no branch_name.max_length → exit 4" "4" "$CODE"
for v in 0 abc; do
  printf 'version: 1\n\nbranch_name:\n  max_length: %s\n' "$v" > "$WORK/badlimit.yaml"
  run "$(name_of_length 1)" --config "$WORK/badlimit.yaml"
  assert_eq "max_length $v → exit 4" "4" "$CODE"
done
OUT=$(cd "$WORK" && bash "$CHECK" "$(name_of_length 1)" 2>&1); CODE=$?
assert_eq "no .ai/project-config.yaml in the current directory → exit 4" "4" "$CODE"

echo "[usage] no argument or an empty one"
run
assert_eq "no argument → exit 2" "2" "$CODE"
run ""
assert_eq "empty argument → exit 2" "2" "$CODE"
run x --config
assert_eq "--config without a path → exit 2" "2" "$CODE"
run x --bogus
assert_eq "unknown option → exit 2" "2" "$CODE"

echo "[formula] the fixture's limit is 63 minus its host suffix"
assert_eq "suffix is 40 characters" "40" "${#SUFFIX}"
assert_eq "63 − 40 = the fixture's limit" "23" "$(( 63 - ${#SUFFIX} ))"

echo "[manifest] the eds pack declares no length of its own (D129)"
if awk '/^branch_name:$/ { inside = 1; next } inside && !/^  / { exit } inside && /^  max_length:/ { found = 1 } END { exit !found }' "$SCRIPT_DIR/../../pack.yaml"; then
  bad "pack.yaml carries no max_length" "found one under branch_name"
else
  ok "pack.yaml carries no max_length"
fi

echo "=== $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
