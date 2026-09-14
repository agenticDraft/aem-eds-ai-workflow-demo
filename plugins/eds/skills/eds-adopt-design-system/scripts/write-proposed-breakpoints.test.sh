#!/usr/bin/env bash
# Tests for write-proposed-breakpoints.sh. Run with:
#   bash plugins/eds/skills/eds-adopt-design-system/scripts/write-proposed-breakpoints.test.sh
#
# No framework — exits 0 on success, 1 on first failure.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRITER="$SCRIPT_DIR/write-proposed-breakpoints.sh"
FIXDIR="$SCRIPT_DIR/fixtures"

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
    echo "    expected to contain: $needle"
    echo "    got: $haystack"
  fi
}

TMPDIR_ROOT="${TMPDIR:-/tmp}/write-proposed-breakpoints-test.$$"
mkdir -p "$TMPDIR_ROOT"
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

echo "=== write-proposed-breakpoints.sh tests ==="

echo "[write] three frames (375/800/1280) -> the exact D21 arithmetic, no design provider called"
OUT_FILE="$TMPDIR_ROOT/three.md"
OUT=$(bash "$WRITER" "$FIXDIR/manifest-three-frames.md" "$OUT_FILE" 2>&1); ST=$?
assert_exit "writer succeeds (exit 0)" 0 $ST "$OUT"
CONTENT=$(cat "$OUT_FILE")
assert_contains "frames section lists all three widths" "width 375" "$CONTENT"
assert_contains "frames section lists the tablet width" "width 800" "$CONTENT"
assert_contains "frames section lists the desktop width" "width 1280" "$CONTENT"
assert_contains "base is the smallest frame, no threshold" "base: 375 (no threshold)" "$CONTENT"
assert_contains "shows the first threshold's arithmetic, not only the result" "√(375×800) ≈ 548 → 550" "$CONTENT"
assert_contains "shows the second threshold's arithmetic, not only the result" "√(800×1280) ≈ 1012 → 1000" "$CONTENT"
assert_contains "no threshold equals a frame width (D21)" "550" "$CONTENT"

for bad in "  - name: \"550\"" "width: 550" "width: 1000"; do
  if grep -qF "$bad" "$OUT_FILE" 2>/dev/null; then
    FAIL=$((FAIL + 1))
    echo "  FAIL: a derived threshold must never be recorded as a frame width: $bad"
  fi
done

echo "[write] a single frame is the base, no threshold section content"
OUT_FILE2="$TMPDIR_ROOT/single.md"
OUT2=$(bash "$WRITER" "$FIXDIR/manifest-single-frame.md" "$OUT_FILE2" 2>&1); ST2=$?
assert_exit "writer succeeds (exit 0)" 0 $ST2 "$OUT2"
CONTENT2=$(cat "$OUT_FILE2")
assert_contains "base recorded" "base: 1280 (no threshold)" "$CONTENT2"

echo "[reject] two frames sharing a width — the core deriver's own refusal is forwarded"
OUT3=$(bash "$WRITER" "$FIXDIR/manifest-duplicate-widths.md" "$TMPDIR_ROOT/dup.md" 2>&1); ST3=$?
assert_exit "usage error (exit 2)" 2 $ST3 "$OUT3"
assert_contains "forwards the core deriver's own reason, not reworded" "geometric mean would equal both" "$OUT3"
[[ -f "$TMPDIR_ROOT/dup.md" ]] && { FAIL=$((FAIL + 1)); echo "  FAIL: no output file should be written on rejection"; } || { PASS=$((PASS + 1)); echo "  ok: no output file written on rejection"; }

echo "[reject] a manifest with no frames"
OUT4=$(bash "$WRITER" "$FIXDIR/manifest-no-frames.md" "$TMPDIR_ROOT/none.md" 2>&1); ST4=$?
assert_exit "usage error (exit 2)" 2 $ST4 "$OUT4"

echo "[usage] manifest not found"
OUT5=$(bash "$WRITER" "$FIXDIR/does-not-exist.md" "$TMPDIR_ROOT/x.md" 2>&1); ST5=$?
assert_exit "usage error (exit 2)" 2 $ST5 "$OUT5"

echo "[usage] missing arguments"
OUT6=$(bash "$WRITER" 2>&1); ST6=$?
assert_exit "usage error (exit 2)" 2 $ST6 "$OUT6"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
