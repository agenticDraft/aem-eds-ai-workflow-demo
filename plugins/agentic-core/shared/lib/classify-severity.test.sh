#!/usr/bin/env bash
# Tests for classify-severity.sh. Run with:
#   bash plugins/agentic-core/shared/lib/classify-severity.test.sh
#
# No framework — exits 0 on success, 1 on first failure.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/classify-severity.sh"
LIST="$SCRIPT_DIR/../fixtures/classify-severity/trusted-files.txt"

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

echo "=== classify-severity.sh tests ==="

echo "[poisoning] file is a member of the trusted list"
OUT=$(bash "$SCRIPT" "house-style.md" "$LIST" 2>&1); ST=$?
assert_exit "exit 0" 0 $ST "$OUT"
assert_contains "classified poisoning" "severity: poisoning" "$OUT"

echo "[poisoning] second member of the trusted list, nested path"
OUT=$(bash "$SCRIPT" "conventions/style-guide.md" "$LIST" 2>&1); ST=$?
assert_exit "exit 0" 0 $ST "$OUT"
assert_contains "classified poisoning" "severity: poisoning" "$OUT"

echo "[cosmetic] file is not a member"
OUT=$(bash "$SCRIPT" "fonts/unused.woff2" "$LIST" 2>&1); ST=$?
assert_exit "exit 0" 0 $ST "$OUT"
assert_contains "classified cosmetic" "severity: cosmetic" "$OUT"

echo "[cosmetic] a path that merely ends the same is not a match"
OUT=$(bash "$SCRIPT" "old/house-style.md" "$LIST" 2>&1); ST=$?
assert_exit "exit 0" 0 $ST "$OUT"
assert_contains "no partial-path match" "severity: cosmetic" "$OUT"

echo "[usage] trusted-files list not found"
OUT=$(bash "$SCRIPT" "house-style.md" "$SCRIPT_DIR/../fixtures/classify-severity/does-not-exist.txt" 2>&1); ST=$?
assert_exit "missing list -> usage error (exit 2)" 2 $ST "$OUT"

echo "[usage] too few arguments"
OUT=$(bash "$SCRIPT" "house-style.md" 2>&1); ST=$?
assert_exit "no list given -> usage error (exit 2)" 2 $ST "$OUT"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
