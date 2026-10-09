#!/usr/bin/env bash
# Tests for validate-project-config.sh. Run with:
#   bash plugins/agentic-core/shared/lib/validate-project-config.test.sh
#
# No framework — exits 0 on success, 1 on first failure. assert_exit below
# compares expected vs. actual exit code per case, against fixture inputs.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATOR="$SCRIPT_DIR/validate-project-config.sh"
FIXDIR="$SCRIPT_DIR/../fixtures/project-config"

PASS=0
FAIL=0

assert_exit() {
  local desc="$1" expected="$2" actual="$3" output="$4"
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1))
    echo "  ok: $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc"
    echo "    expected exit=$expected, got exit=$actual"
    [[ -n "$output" ]] && echo "    output: $output"
  fi
}

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    PASS=$((PASS + 1))
    echo "  ok: $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc"
    echo "    expected output to contain: $needle"
    echo "    got: $haystack"
  fi
}

echo "=== validate-project-config.sh tests ==="

echo "[accept] a well-formed config"
OUT=$(bash "$VALIDATOR" "$FIXDIR/valid.yaml" 2>&1); ST=$?
assert_exit "valid.yaml accepted (exit 0)" 0 $ST "$OUT"
assert_contains "reports valid" "valid" "$OUT"

echo "[reject] unknown top-level key"
OUT=$(bash "$VALIDATOR" "$FIXDIR/invalid/unknown-top-level-key.yaml" 2>&1); ST=$?
assert_exit "unknown-top-level-key.yaml rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the bad key" "notes" "$OUT"

echo "[usage] no argument"
OUT=$(bash "$VALIDATOR" 2>&1); ST=$?
assert_exit "no arg -> usage error (exit 2)" 2 $ST "$OUT"

echo "[usage] file not found"
OUT=$(bash "$VALIDATOR" "$FIXDIR/does-not-exist.yaml" 2>&1); ST=$?
assert_exit "missing file -> usage error (exit 2)" 2 $ST "$OUT"

echo "[reject] trigger.allowed_identities is an empty list"
OUT=$(bash "$VALIDATOR" "$FIXDIR/invalid/trigger-empty-list.yaml" 2>&1); ST=$?
assert_exit "trigger-empty-list.yaml rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the empty list" "at least one identity" "$OUT"

echo "[reject] trigger block absent"
OUT=$(bash "$VALIDATOR" "$FIXDIR/invalid/trigger-missing.yaml" 2>&1); ST=$?
assert_exit "trigger-missing.yaml rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the missing block" "trigger:" "$OUT"

echo "[reject] trigger before limits"
OUT=$(bash "$VALIDATOR" "$FIXDIR/invalid/trigger-out-of-order.yaml" 2>&1); ST=$?
assert_exit "trigger-out-of-order.yaml rejected (exit 1)" 1 $ST "$OUT"

echo "[reject] trigger.token is empty"
OUT=$(bash "$VALIDATOR" "$FIXDIR/invalid/trigger-empty-token.yaml" 2>&1); ST=$?
assert_exit "trigger-empty-token.yaml rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the empty token" "trigger.token is empty" "$OUT"

# The two optional trailing keys (D129), built on valid.yaml in a scratch
# directory: valid.yaml ends with the trigger block.
WORK="$(mktemp -d "${TMPDIR:-/tmp}/validate-project-config.XXXXXX")"
[[ -n "$WORK" && -d "$WORK" ]] || { echo "cannot create a temporary directory"; exit 1; }
trap 'rm -rf "$WORK"' EXIT

# with <name> <text> — valid.yaml followed by <text>; prints the file's path
with() {
  { cat "$FIXDIR/valid.yaml"; printf '\n%s\n' "$2"; } > "$WORK/$1.yaml"
  echo "$WORK/$1.yaml"
}

check() { OUT=$(bash "$VALIDATOR" "$1" 2>&1); ST=$?; }

echo "[accept] branch_name.max_length after trigger"
check "$(with limit $'branch_name:\n  max_length: 23')"
assert_exit "branch_name with a positive max_length accepted" 0 $ST "$OUT"

echo "[accept] a platform block, nested values included"
check "$(with platform $'platform:\n  some_value: "--a--b"\n  nested:\n    deeper: 1')"
assert_exit "platform block accepted" 0 $ST "$OUT"

echo "[accept] both, branch_name first"
check "$(with both $'branch_name:\n  max_length: 40\n\nplatform:\n  some_value: "x"')"
assert_exit "branch_name then platform accepted" 0 $ST "$OUT"

echo "[reject] platform before branch_name"
check "$(with order $'platform:\n  some_value: "x"\n\nbranch_name:\n  max_length: 40')"
assert_exit "platform before branch_name rejected" 1 $ST "$OUT"
assert_contains "reason names the key" "branch_name" "$OUT"

echo "[reject] branch_name.max_length not a positive integer"
for v in 0 -1 x '"23"'; do
  check "$(with "bad-limit-$RANDOM" "branch_name:
  max_length: $v")"
  assert_exit "max_length $v rejected" 1 $ST "$OUT"
done
check "$(with bad-limit-text $'branch_name:\n  max_length: 0')"
assert_contains "reason names the field" "branch_name.max_length" "$OUT"

echo "[reject] branch_name with no max_length, or another sub-key"
check "$(with no-limit $'branch_name:')"
assert_exit "an empty branch_name rejected" 1 $ST "$OUT"
check "$(with pattern-here $'branch_name:\n  pattern: "^[a-z]+$"')"
assert_exit "pattern under the config's branch_name rejected" 1 $ST "$OUT"
check "$(with extra-sub $'branch_name:\n  max_length: 23\n  pattern: "^[a-z]+$"')"
assert_exit "a second sub-key rejected" 1 $ST "$OUT"

echo "[reject] a platform block that is not a non-empty mapping"
check "$(with platform-empty $'platform:')"
assert_exit "an empty platform block rejected" 1 $ST "$OUT"
assert_contains "reason names the block" "platform" "$OUT"
check "$(with platform-scalar $'platform: x')"
assert_exit "a scalar platform rejected" 1 $ST "$OUT"

echo "[reject] nothing after platform"
check "$(with after $'platform:\n  some_value: "x"\n\nnotes:\n  a: 1')"
assert_exit "a key after platform rejected" 1 $ST "$OUT"
assert_contains "reason names the bad key" "notes" "$OUT"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
