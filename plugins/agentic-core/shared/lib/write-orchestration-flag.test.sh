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
OLD_MTIME="$(date -r "$FLAG" +%s 2>/dev/null)"
sleep 1
OUT=$(bash "$WRITER" "$FLAG" 2>&1); ST=$?
assert_exit "exits 0" 0 $ST "$OUT"
assert_contains "reports refreshed" "refreshed: $FLAG" "$OUT"
NEW_MTIME="$(date -r "$FLAG" +%s 2>/dev/null)"
if (( NEW_MTIME > OLD_MTIME )); then
  PASS=$((PASS + 1)); echo "  ok: mtime moved forward on refresh"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: mtime did not move forward (old=$OLD_MTIME new=$NEW_MTIME)"
fi

echo "[usage] missing argument"
OUT=$(bash "$WRITER" 2>&1); ST=$?
assert_exit "no arg -> usage error (exit 2)" 2 $ST "$OUT"

echo "[driver] the marker is first written together with the first run state, never before it"
# A marker without a run state is a run nothing can resume and nothing can
# finish: the driver's fresh start must not write the marker before intake
# returns, and the node that first writes the run state writes the marker too.
DRIVER="$SCRIPT_DIR/../../skills/run-route/SKILL.md"
node_body() {  # node_body <heading text> — the node's lines up to the next heading
  awk -v h="### $1" '$0 == h {on=1; next} on && /^### / {exit} on' "$DRIVER"
}
FRESH="$(node_body "Fresh start: run intake")"
RECORD="$(node_body "Record intake stage")"
if [[ -n "$FRESH" && "$FRESH" != *"write-orchestration-flag.sh"* ]]; then
  PASS=$((PASS + 1)); echo "  ok: the fresh-start node writes no marker before intake"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: the fresh-start node must exist and write no marker before intake"
fi
if [[ "$RECORD" == *"write-run-state.sh"* && "$RECORD" == *"write-orchestration-flag.sh"* ]]; then
  PASS=$((PASS + 1)); echo "  ok: the node that first writes run state writes the marker too"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: the record-intake node must write both run state and the marker"
fi

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
