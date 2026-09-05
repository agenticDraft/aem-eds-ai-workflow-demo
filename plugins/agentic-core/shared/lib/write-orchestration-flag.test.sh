#!/usr/bin/env bash
# Tests for write-orchestration-flag.sh. Run with:
#   bash plugins/agentic-core/shared/lib/write-orchestration-flag.test.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRITER="$SCRIPT_DIR/write-orchestration-flag.sh"

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

TMPDIR_TEST="$(mktemp -d "${TMPDIR:-/tmp}/write-orchestration-flag-test.XXXXXX")"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

echo "=== write-orchestration-flag.sh tests ==="

echo "[create] flag does not exist yet, parent directory does not exist yet"
FLAG="$TMPDIR_TEST/nested/run-context/orchestrating.flag"
OUT=$(bash "$WRITER" "$FLAG" 2>&1); ST=$?
assert_exit "exits 0" 0 $ST "$OUT"
assert_contains "reports written" "written: $FLAG" "$OUT"
[[ -f "$FLAG" ]] && { PASS=$((PASS + 1)); echo "  ok: file now exists"; } \
  || { FAIL=$((FAIL + 1)); echo "  FAIL: file must exist after a create"; }

echo "[refresh] flag already exists — mtime moves forward, content untouched"
OLD_MTIME="$(stat -f %m "$FLAG" 2>/dev/null || stat -c %Y "$FLAG" 2>/dev/null)"
sleep 1
OUT=$(bash "$WRITER" "$FLAG" 2>&1); ST=$?
assert_exit "exits 0" 0 $ST "$OUT"
assert_contains "reports refreshed" "refreshed: $FLAG" "$OUT"
NEW_MTIME="$(stat -f %m "$FLAG" 2>/dev/null || stat -c %Y "$FLAG" 2>/dev/null)"
if (( NEW_MTIME > OLD_MTIME )); then
  PASS=$((PASS + 1)); echo "  ok: mtime moved forward on refresh"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: mtime did not move forward (old=$OLD_MTIME new=$NEW_MTIME)"
fi

echo "[usage] missing argument"
OUT=$(bash "$WRITER" 2>&1); ST=$?
assert_exit "no arg -> usage error (exit 2)" 2 $ST "$OUT"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
