#!/usr/bin/env bash
# Tests for check-preflight.sh. Run with:
#   bash plugins/agentic-core/shared/lib/check-preflight.test.sh
#
# No framework — exits 0 on success, 1 on first failure. assert_exit/
# assert_contains below compare expected vs. actual exit code and output
# against fixture inputs.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/check-preflight.sh"
FIXDIR="$SCRIPT_DIR/../fixtures/pre-flight"
PACKFIXDIR="$SCRIPT_DIR/../fixtures/pack-manifest"

PLATFORM="$PACKFIXDIR/platform-valid/pack.yaml"
TRACKER="$PACKFIXDIR/provider-valid/pack.yaml"
SCM="$FIXDIR/providers/scm-valid/pack.yaml"
SCM_MISSING="$FIXDIR/providers/scm-missing-operation/pack.yaml"
BROWSER="$FIXDIR/providers/browser-valid/pack.yaml"
DESIGN="$FIXDIR/providers/design-valid/pack.yaml"

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

echo "=== check-preflight.sh tests ==="

echo "[accept] every required pack installed, design not required"
OUT=$(bash "$CHECK" "$FIXDIR/config-valid.yaml" \
  "platform=$PLATFORM" "tracker=$TRACKER" "scm=$SCM" "browser=$BROWSER" 2>&1); ST=$?
assert_exit "ready (exit 0)" 0 $ST "$OUT"
assert_contains "reports ready" "ready" "$OUT"
assert_contains "design not required" "design: none" "$OUT"

echo "[accept] every required pack installed, design required and present"
OUT=$(bash "$CHECK" "$FIXDIR/config-design-required.yaml" \
  "platform=$PLATFORM" "tracker=$TRACKER" "scm=$SCM" "browser=$BROWSER" "design=$DESIGN" 2>&1); ST=$?
assert_exit "ready with design (exit 0)" 0 $ST "$OUT"
assert_contains "design checked ok" "design: ok" "$OUT"

echo "[reject] a required pack is missing (removed from the arguments)"
OUT=$(bash "$CHECK" "$FIXDIR/config-valid.yaml" \
  "platform=$PLATFORM" "scm=$SCM" "browser=$BROWSER" 2>&1); ST=$?
assert_exit "missing tracker pack rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the missing role" "role 'tracker'" "$OUT"

echo "[reject] a required pack's path does not exist"
OUT=$(bash "$CHECK" "$FIXDIR/config-valid.yaml" \
  "platform=$PLATFORM" "tracker=$FIXDIR/does-not-exist/pack.yaml" "scm=$SCM" "browser=$BROWSER" 2>&1); ST=$?
assert_exit "pack not installed rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names not installed" "not installed" "$OUT"

echo "[reject] a route uses a stage the platform pack does not declare"
OUT=$(bash "$CHECK" "$FIXDIR/config-unknown-stage.yaml" \
  "platform=$PLATFORM" "tracker=$TRACKER" "scm=$SCM" "browser=$BROWSER" 2>&1); ST=$?
assert_exit "unknown stage rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the unresolved stage" "plan-gate" "$OUT"

echo "[reject] a configured pack declares a required operation unsupported"
OUT=$(bash "$CHECK" "$FIXDIR/config-valid.yaml" \
  "platform=$PLATFORM" "tracker=$TRACKER" "scm=$SCM_MISSING" "browser=$BROWSER" 2>&1); ST=$?
assert_exit "unsupported operation rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the unavailable operation" "publish_change" "$OUT"

echo "[reject] a pack is installed under the wrong role"
OUT=$(bash "$CHECK" "$FIXDIR/config-valid.yaml" \
  "platform=$PLATFORM" "tracker=$TRACKER" "scm=$TRACKER" "browser=$BROWSER" 2>&1); ST=$?
assert_exit "role mismatch rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the declared role" "declares role 'tracker'" "$OUT"

echo "[usage] no arguments"
OUT=$(bash "$CHECK" 2>&1); ST=$?
assert_exit "no args -> usage error (exit 2)" 2 $ST "$OUT"

echo "[usage] config file not found"
OUT=$(bash "$CHECK" "$FIXDIR/does-not-exist.yaml" "platform=$PLATFORM" 2>&1); ST=$?
assert_exit "missing config -> usage error (exit 2)" 2 $ST "$OUT"

echo "[usage] malformed role=path argument"
OUT=$(bash "$CHECK" "$FIXDIR/config-valid.yaml" "platform" 2>&1); ST=$?
assert_exit "malformed argument -> usage error (exit 2)" 2 $ST "$OUT"

echo "[usage] unrecognized role name"
OUT=$(bash "$CHECK" "$FIXDIR/config-valid.yaml" "bogus=$PLATFORM" 2>&1); ST=$?
assert_exit "unrecognized role -> usage error (exit 2)" 2 $ST "$OUT"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
