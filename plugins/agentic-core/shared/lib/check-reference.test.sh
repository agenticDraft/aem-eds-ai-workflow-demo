#!/usr/bin/env bash
# Tests for check-reference.sh. Run with:
#   bash plugins/agentic-core/shared/lib/check-reference.test.sh
#
# No framework — exits 0 on success, 1 on first failure.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/check-reference.sh"
ROOT="$SCRIPT_DIR/../fixtures/check-reference/project"

PASS=0
FAIL=0

assert_exit() {
  local desc="$1" expected="$2" actual="$3" output="$4"
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1)); echo "  ok: $desc"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: $desc"
    echo "    expected exit=$expected, got exit=$actual"
    [[ -n "$output" ]] && echo "    output: $output"
  fi
}

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    PASS=$((PASS + 1)); echo "  ok: $desc"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: $desc"
    echo "    expected to contain: $needle"
    echo "    got: $haystack"
  fi
}

echo "=== check-reference.sh tests ==="

echo "[referenced] family used in a sibling file, excluding its own declaration"
OUT=$(bash "$SCRIPT" "sample-family" "$ROOT" "$ROOT/declares.css" 2>&1); ST=$?
assert_exit "exit 0 — referenced elsewhere" 0 $ST "$OUT"
assert_contains "names the file and line it was found in" "sub/uses.css:2" "$OUT"

echo "[not-referenced] family with no use outside its own declaration"
OUT=$(bash "$SCRIPT" "orphan-family" "$ROOT" "$ROOT/unused-only.css" 2>&1); ST=$?
assert_exit "exit 1 — nowhere else references it" 1 $ST "$OUT"
assert_contains "reports not-referenced" "not-referenced" "$OUT"

echo "[not-referenced] without an exclude file, its own declaration still counts as a hit"
OUT=$(bash "$SCRIPT" "orphan-family" "$ROOT" 2>&1); ST=$?
assert_exit "exit 0 — the declaration line itself is a match with no exclusion" 0 $ST "$OUT"
assert_contains "finds its own declaration" "unused-only.css" "$OUT"

echo "[referenced] no exclude-file argument given, still searches the whole tree"
OUT=$(bash "$SCRIPT" "sample-family" "$ROOT" 2>&1); ST=$?
assert_exit "exit 0" 0 $ST "$OUT"
assert_contains "finds both the declaration and the use" "declares.css" "$OUT"
assert_contains "finds both the declaration and the use" "uses.css" "$OUT"

echo "[usage] root-dir not found"
OUT=$(bash "$SCRIPT" "sample-family" "$SCRIPT_DIR/../fixtures/check-reference/does-not-exist" 2>&1); ST=$?
assert_exit "missing root -> usage error (exit 2)" 2 $ST "$OUT"

echo "[usage] too few arguments"
OUT=$(bash "$SCRIPT" "sample-family" 2>&1); ST=$?
assert_exit "no root given -> usage error (exit 2)" 2 $ST "$OUT"

echo "[usage] exclude-file given but does not exist"
OUT=$(bash "$SCRIPT" "sample-family" "$ROOT" "$ROOT/does-not-exist.css" 2>&1); ST=$?
assert_exit "missing exclude-file -> usage error (exit 2)" 2 $ST "$OUT"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
