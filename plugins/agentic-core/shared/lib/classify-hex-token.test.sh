#!/usr/bin/env bash
# Tests for classify-hex-token.sh. Run with:
#   bash plugins/agentic-core/shared/lib/classify-hex-token.test.sh
#
# No framework — exits 0 on success, 1 on first failure.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/classify-hex-token.sh"
MANIFEST="$SCRIPT_DIR/../fixtures/design-manifest/valid.yaml"

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

echo "=== classify-hex-token.sh tests ==="

echo "[mechanical] exact match, same case"
OUT=$(bash "$SCRIPT" "#000000" "$MANIFEST" 2>&1); ST=$?
assert_exit "exit 0" 0 $ST "$OUT"
assert_contains "classified mechanical" "mechanical: exact match" "$OUT"
assert_contains "names the matching token" "Accent/Accent 4" "$OUT"

echo "[mechanical] exact match, different case is still exact"
OUT=$(bash "$SCRIPT" "#e9e9e9" "$MANIFEST" 2>&1); ST=$?
assert_exit "exit 0" 0 $ST "$OUT"
assert_contains "classified mechanical regardless of hex case" "mechanical: exact match" "$OUT"
assert_contains "names Divider 1" "Dividers/Divider 1" "$OUT"

echo "[judgment] close but not equal (#dadada vs Divider 1 #E9E9E9)"
OUT=$(bash "$SCRIPT" "#dadada" "$MANIFEST" 2>&1); ST=$?
assert_exit "exit 0" 0 $ST "$OUT"
assert_contains "classified judgment" "judgment: close match" "$OUT"
assert_contains "names the nearest token" "Dividers/Divider 1" "$OUT"

echo "[no-match] far from every adopted token"
OUT=$(bash "$SCRIPT" "#3b63fb" "$MANIFEST" 2>&1); ST=$?
assert_exit "exit 0" 0 $ST "$OUT"
assert_contains "reports no-match" "no-match" "$OUT"

echo "[shorthand] a 3-digit hex expands before comparing"
OUT=$(bash "$SCRIPT" "#000" "$MANIFEST" 2>&1); ST=$?
assert_exit "exit 0" 0 $ST "$OUT"
assert_contains "3-digit #000 exactly matches #000000" "mechanical: exact match" "$OUT"

echo "[usage] not a recognizable hex"
OUT=$(bash "$SCRIPT" "not-a-color" "$MANIFEST" 2>&1); ST=$?
assert_exit "not a hex -> usage error (exit 2)" 2 $ST "$OUT"

echo "[usage] manifest file not found"
OUT=$(bash "$SCRIPT" "#000000" "$SCRIPT_DIR/../fixtures/design-manifest/does-not-exist.yaml" 2>&1); ST=$?
assert_exit "missing manifest -> usage error (exit 2)" 2 $ST "$OUT"

echo "[usage] too few arguments"
OUT=$(bash "$SCRIPT" "#000000" 2>&1); ST=$?
assert_exit "no manifest given -> usage error (exit 2)" 2 $ST "$OUT"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
