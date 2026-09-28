#!/usr/bin/env bash
# Tests for measure.cjs. Run with:
#   bash plugins/playwright/skills/measure/scripts/measure.test.sh
#
# No browser — exits 0 on success, 1 if anything failed. Checks the fixed
# property set and the paths that end before a browser is launched.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MEASURE="$SCRIPT_DIR/measure.cjs"

PASS=0
FAIL=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1)); echo "  ok: $desc"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: $desc"
    echo "    expected: $expected"
    echo "    got:      $actual"
  fi
}

echo "=== measure.cjs tests ==="

echo "[properties] exactly the fixed set, in order"
assert_eq "property list" \
  "color,background-color,font-family,font-size,font-weight,line-height,padding-top,padding-right,padding-bottom,padding-left,gap,border-radius" \
  "$(node -e "process.stdout.write(require(process.argv[1]).PROPERTIES.join(','))" "$MEASURE" 2>&1)"

echo "[properties] no shorthand padding is reported"
assert_eq "no padding shorthand" "" \
  "$(node -e "process.stdout.write(require(process.argv[1]).PROPERTIES.filter((p) => /^padding(-inline|-block)?$/.test(p)).join(','))" "$MEASURE" 2>&1)"

echo "[require] loading the module runs no measurement"
assert_eq "no output on require" "" \
  "$(node -e "require(process.argv[1])" "$MEASURE" 2>&1)"

echo "[usage] no selector exits 2"
node "$MEASURE" http://localhost:1/ >/dev/null 2>&1
assert_eq "exit code" "2" "$?"

echo "[target] a non-http target fails in the envelope"
OUT="$(node "$MEASURE" file:///nowhere.html .x 2>&1)"
assert_eq "verdict fail" "verdict: fail" "$(printf '%s\n' "$OUT" | grep '^verdict:')"

echo ""
echo "passed: $PASS, failed: $FAIL"
[[ "$FAIL" -eq 0 ]]
