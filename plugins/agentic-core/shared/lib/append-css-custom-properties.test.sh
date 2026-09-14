#!/usr/bin/env bash
# Tests for append-css-custom-properties.sh. Run with:
#   bash plugins/agentic-core/shared/lib/append-css-custom-properties.test.sh
#
# No framework — exits 0 on success, 1 on first failure.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/append-css-custom-properties.sh"
FIXDIR="$SCRIPT_DIR/../fixtures/css-custom-properties"
TMPDIR_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/append-css-custom-properties-test.XXXXXX")"
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

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

assert_not_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    PASS=$((PASS + 1))
    echo "  ok: $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc"
    echo "    expected output NOT to contain: $needle"
    echo "    got: $haystack"
  fi
}

echo "=== append-css-custom-properties.sh tests ==="

echo "[append] new properties added, existing property left untouched"
TARGET="$TMPDIR_ROOT/target.css"
cp "$FIXDIR/target.css" "$TARGET"
OUT=$(bash "$SCRIPT" "$TARGET" "$FIXDIR/source.css" 2>&1); ST=$?
assert_exit "script exits 0" 0 $ST "$OUT"
assert_contains "reports 2 properties appended" "appended: 2 properties" "$OUT"
CONTENT="$(cat "$TARGET")"
assert_contains "new property --accent-accent-1 present" "--accent-accent-1: #485C11;" "$CONTENT"
assert_contains "new property --dividers-divider-1 present" "--dividers-divider-1: #E9E9E9;" "$CONTENT"
assert_contains "existing --link-color value untouched" "--link-color: #3b63fb;" "$CONTENT"
assert_not_contains "source's own --link-color value never written" "--link-color: #000000;" "$CONTENT"
assert_contains "body rule after :root block preserved" "color: var(--text-color);" "$CONTENT"

echo "[idempotent] a second run finds nothing new to add"
OUT2=$(bash "$SCRIPT" "$TARGET" "$FIXDIR/source.css" 2>&1); ST2=$?
assert_exit "second run exits 0" 0 $ST2 "$OUT2"
assert_contains "reports no new properties" "no new properties" "$OUT2"
COUNT_AFTER="$(grep -c -- '--accent-accent-1' "$TARGET")"
if [[ "$COUNT_AFTER" -eq 1 ]]; then
  PASS=$((PASS + 1)); echo "  ok: property not duplicated"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: property not duplicated (found $COUNT_AFTER times)"
fi

echo "[reject] source has no :root block"
TARGET2="$TMPDIR_ROOT/target2.css"
cp "$FIXDIR/target.css" "$TARGET2"
OUT3=$(bash "$SCRIPT" "$TARGET2" "$FIXDIR/no-root.css" 2>&1); ST3=$?
assert_exit "no :root in source rejected (exit 1)" 1 $ST3 "$OUT3"

echo "[reject] target has no :root block"
TARGET3="$TMPDIR_ROOT/target3.css"
cp "$FIXDIR/no-root.css" "$TARGET3"
OUT4=$(bash "$SCRIPT" "$TARGET3" "$FIXDIR/source.css" 2>&1); ST4=$?
assert_exit "no :root in target rejected (exit 1)" 1 $ST4 "$OUT4"

echo "[usage] wrong argument count"
OUT5=$(bash "$SCRIPT" "$TARGET" 2>&1); ST5=$?
assert_exit "missing arg -> usage error (exit 2)" 2 $ST5 "$OUT5"

echo "[usage] file not found"
OUT6=$(bash "$SCRIPT" "$TMPDIR_ROOT/does-not-exist.css" "$FIXDIR/source.css" 2>&1); ST6=$?
assert_exit "missing target file -> usage error (exit 2)" 2 $ST6 "$OUT6"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
