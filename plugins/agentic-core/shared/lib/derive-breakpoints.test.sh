#!/usr/bin/env bash
# Tests for derive-breakpoints.sh. Run with:
#   bash plugins/agentic-core/shared/lib/derive-breakpoints.test.sh
#
# No framework — exits 0 on success, 1 on first failure.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DERIVER="$SCRIPT_DIR/derive-breakpoints.sh"
FIXDIR="$SCRIPT_DIR/../fixtures/breakpoints"

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

assert_equals() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1))
    echo "  ok: $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc"
    echo "    expected: $expected"
    echo "    got:      $actual"
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
    echo "    expected to contain: $needle"
    echo "    got: $haystack"
  fi
}

read_widths() {
  # Reads a fixture file's lines into the global WIDTHS array, one width per line.
  WIDTHS=()
  while IFS= read -r w; do
    [[ -z "$w" ]] && continue
    WIDTHS+=("$w")
  done < "$1"
}

echo "=== derive-breakpoints.sh tests ==="

echo "[derive] the fixture's 375 / 800 / 1280 -> base, 550, 1000 (D21, no design provider, no pack)"
read_widths "$FIXDIR/frame-widths.txt"
OUT=$(bash "$DERIVER" "${WIDTHS[@]}" 2>&1); ST=$?
assert_exit "exits 0" 0 $ST "$OUT"
assert_equals "prints the exact three rows, in order" \
"$(printf 'base\t375\nthreshold\t375\t800\t548\t550\nthreshold\t800\t1280\t1012\t1000')" "$OUT"

echo "[derive] no threshold equals a frame width (D21's own defect)"
assert_contains "550 is not one of the input frame widths" "550" "$OUT"
for w in "${WIDTHS[@]}"; do
  if [[ "$w" == "550" || "$w" == "1000" ]]; then
    FAIL=$((FAIL + 1))
    echo "  FAIL: a derived threshold must never equal a frame width"
  fi
done

echo "[derive] input order does not matter — widths are sorted before deriving"
read_widths "$FIXDIR/frame-widths-unsorted.txt"
OUT2=$(bash "$DERIVER" "${WIDTHS[@]}" 2>&1); ST2=$?
assert_exit "exits 0" 0 $ST2 "$OUT2"
assert_equals "same result regardless of argument order" "$OUT" "$OUT2"

echo "[derive] a single frame is the base, no threshold produced"
read_widths "$FIXDIR/single-width.txt"
OUT3=$(bash "$DERIVER" "${WIDTHS[@]}" 2>&1); ST3=$?
assert_exit "exits 0" 0 $ST3 "$OUT3"
assert_equals "prints only the base row" "$(printf 'base\t375')" "$OUT3"

echo "[reject] two frames of the same width would make a threshold equal a frame width"
read_widths "$FIXDIR/duplicate-widths.txt"
OUT4=$(bash "$DERIVER" "${WIDTHS[@]}" 2>&1); ST4=$?
assert_exit "usage error (exit 2)" 2 $ST4 "$OUT4"
assert_contains "names the shared width" "375" "$OUT4"

echo "[reject] a non-positive width"
read_widths "$FIXDIR/negative-width.txt"
OUT5=$(bash "$DERIVER" "${WIDTHS[@]}" 2>&1); ST5=$?
assert_exit "usage error (exit 2)" 2 $ST5 "$OUT5"

echo "[reject] a non-numeric width"
OUT6=$(bash "$DERIVER" 375 wide 2>&1); ST6=$?
assert_exit "usage error (exit 2)" 2 $ST6 "$OUT6"

echo "[usage] no widths given"
OUT7=$(bash "$DERIVER" 2>&1); ST7=$?
assert_exit "usage error (exit 2)" 2 $ST7 "$OUT7"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
