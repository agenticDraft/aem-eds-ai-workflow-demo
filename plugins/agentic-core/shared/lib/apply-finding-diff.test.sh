#!/usr/bin/env bash
# Tests for apply-finding-diff.sh. Run with:
#   bash plugins/agentic-core/shared/lib/apply-finding-diff.test.sh
#
# No framework — exits 0 on success, 1 on first failure.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/apply-finding-diff.sh"
FIXDIR="$SCRIPT_DIR/../fixtures/finding-diff"
TMPDIR_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/apply-finding-diff-test.XXXXXX")"
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

echo "=== apply-finding-diff.sh tests ==="

echo "[apply] single-line replacement (F3 shape)"
TARGET="$TMPDIR_ROOT/package.json"
cp "$FIXDIR/package.json" "$TARGET"
OUT=$(bash "$SCRIPT" "$TARGET" "$FIXDIR/repository-url.diff" 2>&1); ST=$?
assert_exit "script exits 0" 0 $ST "$OUT"
assert_contains "reports applied" "applied: $TARGET" "$OUT"
CONTENT="$(cat "$TARGET")"
assert_contains "new url present" "agenticDraft/aem-eds-ai-workflow-demo.git" "$CONTENT"
assert_not_contains "old url gone" "adobe/aem-boilerplate.git" "$CONTENT"

echo "[apply] one removed line, two added lines (multi-line diff)"
TARGET2="$TMPDIR_ROOT/package2.json"
cp "$FIXDIR/package.json" "$TARGET2"
OUT2=$(bash "$SCRIPT" "$TARGET2" "$FIXDIR/two-line.diff" 2>&1); ST2=$?
assert_exit "script exits 0" 0 $ST2 "$OUT2"
CONTENT2="$(cat "$TARGET2")"
assert_contains "new name present" '"name": "acme-storefront",' "$CONTENT2"
assert_contains "new description present" '"description": "Acme'"'"'s storefront",' "$CONTENT2"
assert_not_contains "old name gone" "@adobe/aem-boilerplate" "$CONTENT2"

echo "[idempotent] applying twice fails the second time (line no longer present)"
OUT3=$(bash "$SCRIPT" "$TARGET" "$FIXDIR/repository-url.diff" 2>&1); ST3=$?
assert_exit "second apply rejected (exit 1)" 1 $ST3 "$OUT3"

echo "[reject] the '-' line is not present in the target"
TARGET4="$TMPDIR_ROOT/package4.json"
cp "$FIXDIR/package.json" "$TARGET4"
OUT4=$(bash "$SCRIPT" "$TARGET4" "$FIXDIR/no-match.diff" 2>&1); ST4=$?
assert_exit "no-match diff rejected (exit 1)" 1 $ST4 "$OUT4"

echo "[reject] malformed diff — a '+' line before a '-' line"
TARGET5="$TMPDIR_ROOT/package5.json"
cp "$FIXDIR/package.json" "$TARGET5"
OUT5=$(bash "$SCRIPT" "$TARGET5" "$FIXDIR/malformed-order.diff" 2>&1); ST5=$?
assert_exit "malformed-order diff rejected (exit 1)" 1 $ST5 "$OUT5"

echo "[usage] wrong argument count"
OUT6=$(bash "$SCRIPT" "$TARGET" 2>&1); ST6=$?
assert_exit "missing arg -> usage error (exit 2)" 2 $ST6 "$OUT6"

echo "[usage] target file not found"
OUT7=$(bash "$SCRIPT" "$TMPDIR_ROOT/does-not-exist.json" "$FIXDIR/repository-url.diff" 2>&1); ST7=$?
assert_exit "missing target -> usage error (exit 2)" 2 $ST7 "$OUT7"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
