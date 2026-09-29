#!/usr/bin/env bash
# Tests for check-trigger-identity.sh. Run with:
#   bash plugins/agentic-core/shared/lib/check-trigger-identity.test.sh
#
# No framework — exits 0 on success, 1 on first failure.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECKER="$SCRIPT_DIR/check-trigger-identity.sh"
FIXDIR="$SCRIPT_DIR/../fixtures/project-config"

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

echo "=== check-trigger-identity.sh tests ==="

echo "[allow] an identity on the list"
OUT=$(bash "$CHECKER" "$FIXDIR/valid.yaml" "example-identity-1" 2>&1); ST=$?
assert_exit "first listed identity allowed (exit 0)" 0 $ST "$OUT"
assert_contains "reports allowed" "allowed" "$OUT"

echo "[allow] the last identity on the list"
OUT=$(bash "$CHECKER" "$FIXDIR/valid.yaml" "example-identity-2" 2>&1); ST=$?
assert_exit "last listed identity allowed (exit 0)" 0 $ST "$OUT"

echo "[refuse] an identity not on the list"
OUT=$(bash "$CHECKER" "$FIXDIR/valid.yaml" "example-identity-9" 2>&1); ST=$?
assert_exit "unlisted identity refused (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the identity" "example-identity-9" "$OUT"

echo "[refuse] a prefix of a listed identity is not a match"
OUT=$(bash "$CHECKER" "$FIXDIR/valid.yaml" "example-identity" 2>&1); ST=$?
assert_exit "prefix refused (exit 1)" 1 $ST "$OUT"

echo "[usage] missing arguments"
OUT=$(bash "$CHECKER" "$FIXDIR/valid.yaml" 2>&1); ST=$?
assert_exit "one arg -> usage error (exit 2)" 2 $ST "$OUT"

echo "[usage] file not found"
OUT=$(bash "$CHECKER" "$FIXDIR/does-not-exist.yaml" "example-identity-1" 2>&1); ST=$?
assert_exit "missing file -> usage error (exit 2)" 2 $ST "$OUT"

echo "[security] decoy allowed_identities block in packs: is not honoured"
OUT=$(bash "$CHECKER" "$FIXDIR/invalid/decoy-allowed-identities.yaml" "decoy-identity" 2>&1); ST=$?
assert_exit "decoy identity refused (exit 1)" 1 $ST "$OUT"

echo "[security] real trigger.allowed_identities is used despite decoy"
OUT=$(bash "$CHECKER" "$FIXDIR/invalid/decoy-allowed-identities.yaml" "example-identity-1" 2>&1); ST=$?
assert_exit "real identity allowed (exit 0)" 0 $ST "$OUT"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
