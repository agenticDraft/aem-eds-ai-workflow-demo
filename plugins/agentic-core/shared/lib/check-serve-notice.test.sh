#!/usr/bin/env bash
# Tests for check-serve-notice.sh. Run with:
#   bash plugins/agentic-core/shared/lib/check-serve-notice.test.sh
#
# No framework — exits 0 on success, 1 on first failure. assert_exit/
# assert_contains below compare expected vs. actual exit code and output
# against the fixtures in ../fixtures/pre-flight/serve/ (plus the shared
# ../fixtures/pre-flight/config-valid.yaml, whose serve command is set).
#
# Nothing here starts, polls or binds anything: the check under test reads
# declarations only, so its tests are file inputs and string outputs.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/check-serve-notice.sh"
FIXDIR="$SCRIPT_DIR/../fixtures/pre-flight"
SERVEDIR="$FIXDIR/serve"

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
    echo "    expected output to contain: $needle"
    echo "    got: $haystack"
  fi
}

assert_not_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    PASS=$((PASS + 1)); echo "  ok: $desc"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: $desc"
    echo "    expected output NOT to contain: $needle"
    echo "    got: $haystack"
  fi
}

echo "=== check-serve-notice.sh tests ==="

echo "[accept] a platform pack declaring no serve stage — no-op"
OUT=$(bash "$CHECK" "$FIXDIR/config-valid.yaml" "$SERVEDIR/pack-without-serve.yaml" 2>&1); ST=$?
assert_exit "not-declared (exit 0)" 0 $ST "$OUT"
assert_contains "reports not-declared" "not-declared" "$OUT"
assert_not_contains "says nothing about a preview" "preview" "$OUT"

echo "[accept] serve stage declared, serve command configured"
OUT=$(bash "$CHECK" "$FIXDIR/config-valid.yaml" "$SERVEDIR/pack-with-serve.yaml" 2>&1); ST=$?
assert_exit "ok (exit 0)" 0 $ST "$OUT"
assert_contains "names the preview URL" "http://localhost:0000/preview" "$OUT"
assert_contains "names the serve command" "run-serve" "$OUT"
assert_contains "reports ok, not warn" "serve: ok" "$OUT"

echo "[warn] serve stage declared, serve command empty"
OUT=$(bash "$CHECK" "$SERVEDIR/config-serve-empty.yaml" "$SERVEDIR/pack-with-serve.yaml" 2>&1); ST=$?
assert_exit "warn is still exit 0 — this check never blocks" 0 $ST "$OUT"
assert_contains "reports warn" "serve: warn" "$OUT"
assert_contains "names the preview URL" "http://localhost:0000/preview" "$OUT"
assert_contains "says it must already be answering" "must already be answering" "$OUT"

echo "[reject] usage errors"
OUT=$(bash "$CHECK" 2>&1); ST=$?
assert_exit "no arguments (exit 2)" 2 $ST "$OUT"
assert_contains "prints usage" "usage:" "$OUT"

OUT=$(bash "$CHECK" "$FIXDIR/config-valid.yaml" 2>&1); ST=$?
assert_exit "one argument (exit 2)" 2 $ST "$OUT"

OUT=$(bash "$CHECK" "$FIXDIR/nonexistent.yaml" "$SERVEDIR/pack-with-serve.yaml" 2>&1); ST=$?
assert_exit "config not found (exit 2)" 2 $ST "$OUT"
assert_contains "names the missing file" "file not found" "$OUT"

OUT=$(bash "$CHECK" "$FIXDIR/config-valid.yaml" "$SERVEDIR/nonexistent.yaml" 2>&1); ST=$?
assert_exit "pack not found (exit 2)" 2 $ST "$OUT"

echo
echo "=== $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] || exit 1
exit 0
