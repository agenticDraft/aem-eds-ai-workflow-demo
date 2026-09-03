#!/usr/bin/env bash
# Tests for write-convention-record.sh. Run with:
#   bash plugins/agentic-core/shared/lib/write-convention-record.test.sh
#
# No framework — exits 0 on success, 1 on first failure.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRITER="$SCRIPT_DIR/write-convention-record.sh"
VALIDATOR="$SCRIPT_DIR/validate-convention-record.sh"
TMPDIR_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/write-convention-record-test.XXXXXX")"
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

echo "=== write-convention-record.sh tests ==="

echo "[write] fresh file, then validates"
OUT_PATH="$TMPDIR_ROOT/fresh/.ai/project-conventions.yaml"
OUT=$(bash "$WRITER" "$OUT_PATH" "acme" "components/" "renders with no errors" "none" "lint and test both exit 0" 2>&1); ST=$?
assert_exit "writer exits 0" 0 $ST "$OUT"
assert_contains "reports written" "written: $OUT_PATH" "$OUT"
VALID_OUT=$(bash "$VALIDATOR" "$OUT_PATH" 2>&1); VALID_ST=$?
assert_exit "written file passes the validator" 0 $VALID_ST "$VALID_OUT"

echo "[write] re-run overwrites in place"
OUT2=$(bash "$WRITER" "$OUT_PATH" "acme" "components/" "renders with no errors" "none" "lint only" 2>&1); ST2=$?
assert_exit "re-run exits 0" 0 $ST2 "$OUT2"
assert_contains "reports updated" "updated: $OUT_PATH" "$OUT2"
assert_contains "new value present" "lint only" "$(cat "$OUT_PATH")"

echo "[reject] a value containing a double quote"
BAD_PATH="$TMPDIR_ROOT/bad/.ai/project-conventions.yaml"
OUT3=$(bash "$WRITER" "$BAD_PATH" "acme" 'components/"' "done" "none" "lint" 2>&1); ST3=$?
assert_exit "double-quote value rejected (exit 1)" 1 $ST3 "$OUT3"

echo "[reject] an empty value"
OUT4=$(bash "$WRITER" "$BAD_PATH" "acme" "" "done" "none" "lint" 2>&1); ST4=$?
assert_exit "empty value rejected (exit 1)" 1 $ST4 "$OUT4"

echo "[usage] wrong argument count"
OUT5=$(bash "$WRITER" "$BAD_PATH" "acme" 2>&1); ST5=$?
assert_exit "wrong arg count -> usage error (exit 2)" 2 $ST5 "$OUT5"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
