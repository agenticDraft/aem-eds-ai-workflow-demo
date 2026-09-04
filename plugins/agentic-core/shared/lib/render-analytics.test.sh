#!/usr/bin/env bash
# Tests for render-analytics.sh. Run with:
#   bash plugins/agentic-core/shared/lib/render-analytics.test.sh
#
# No framework — exits 0 on success, 1 on first failure. Confirms: figures
# are computed from the fixture transcripts' own usage records (exact
# numbers, hand-verified against the fixtures); a streamed turn's repeated
# `.message.id` is deduplicated rather than double-counted; a run with no
# subagents renders an empty (but present) Subagents section; supplying
# ceilings produces a Ceilings section with the right PASS/FAIL per row and
# exit 1 on an overall FAIL; and session-a and session-b — two different
# fixture runs — render two different sets of numbers, proving this is not
# a fixed template.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RENDERER="$SCRIPT_DIR/render-analytics.sh"
FIXDIR="$SCRIPT_DIR/../fixtures/analytics"

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

TMPDIR_TEST="$(mktemp -d "${TMPDIR:-/tmp}/render-analytics-test.XXXXXX")"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

echo "=== render-analytics.sh tests ==="

echo "[compute] session-a: orchestrator figures come from its own usage records"
OUT_A="$TMPDIR_TEST/session-a.md"
OUT=$(bash "$RENDERER" "$FIXDIR/session-a.jsonl" "$OUT_A" 2>&1); ST=$?
assert_exit "exits 0 (no ceilings supplied)" 0 $ST "$OUT"
assert_contains "reports written path" "written: $OUT_A" "$OUT"
RENDERED_A="$(cat "$OUT_A")"
assert_contains "orchestrator turns counted (2 distinct message ids)" "Turns counted: 2" "$RENDERED_A"
assert_contains "orchestrator peak context (last turn's own total)" "Peak context: 145 tokens" "$RENDERED_A"
assert_contains "orchestrator cumulative billed input (both turns summed)" "Cumulative billed input: 225 tokens" "$RENDERED_A"
assert_contains "orchestrator cumulative output" "Cumulative output: 50 tokens" "$RENDERED_A"
assert_contains "orchestrator wall clock (first line to last line)" "Wall clock: 4m 10s" "$RENDERED_A"

echo "[compute] session-a: a streamed subagent turn is deduplicated, not double-counted"
assert_contains "intake counts 2 deduplicated turns, not the 3 raw lines" \
  "| intake | general-purpose | 2 | 226 | 413 | 55 |" "$RENDERED_A"
assert_not_contains "cumulative output is not the 3-line sum (5+40+15=60) — the superseded partial (5) is dropped" \
  "| 60 | " "$RENDERED_A"

echo "[compute] session-a: second subagent and the run-wide totals"
assert_contains "plan row present with its own figures" "| plan | general-purpose | 1 | 63 | 53 | 10 |" "$RENDERED_A"
assert_contains "totals sum orchestrator plus every subagent" "Cumulative billed input, whole run: 691 tokens" "$RENDERED_A"
assert_contains "totals sum cumulative output too" "Cumulative output, whole run: 115 tokens" "$RENDERED_A"

echo "[zero] a run with no subagents/ directory still renders the section, empty"
OUT_NONE="$TMPDIR_TEST/no-subagents.md"
OUT=$(bash "$RENDERER" "$FIXDIR/no-subagents.jsonl" "$OUT_NONE" 2>&1); ST=$?
assert_exit "exits 0" 0 $ST "$OUT"
RENDERED_NONE="$(cat "$OUT_NONE")"
assert_contains "Subagents heading present" "## Subagents" "$RENDERED_NONE"
assert_not_contains "no subagent row rendered" "| general-purpose |" "$RENDERED_NONE"
assert_contains "orchestrator-only totals" "Cumulative billed input, whole run: 10 tokens" "$RENDERED_NONE"

echo "[changes] session-b renders different numbers than session-a — not a fixed template"
OUT_B="$TMPDIR_TEST/session-b.md"
bash "$RENDERER" "$FIXDIR/session-b.jsonl" "$OUT_B" >/dev/null
RENDERED_B="$(cat "$OUT_B")"
assert_contains "session-b's own peak context" "Peak context: 1050 tokens" "$RENDERED_B"
assert_not_contains "session-a's peak context does not leak into session-b's render" "Peak context: 145 tokens" "$RENDERED_B"

echo "[ceilings] a breached ceiling fails that row, the overall result, and the exit code"
OUT_CEIL="$TMPDIR_TEST/session-a-ceilings.md"
OUT=$(bash "$RENDERER" "$FIXDIR/session-a.jsonl" "$OUT_CEIL" "$FIXDIR/ceilings.txt" 2>&1); ST=$?
assert_exit "exits 1 (intake breaches its ceiling)" 1 $ST "$OUT"
assert_contains "stderr names the ceilings failure" "ceilings: FAIL" "$OUT"
assert_contains "the file is still written despite the failing exit code" "written: $OUT_CEIL" "$OUT"
RENDERED_CEIL="$(cat "$OUT_CEIL")"
assert_contains "intake row marked FAIL (226 > 200)" "| intake | 226 | 200 | FAIL |" "$RENDERED_CEIL"
assert_contains "plan row marked PASS (63 <= 100)" "| plan | 63 | 100 | PASS |" "$RENDERED_CEIL"
assert_contains "overall result is FAIL" "Overall: FAIL" "$RENDERED_CEIL"

echo "[robustness] a trailing line with no timestamp (a harness bookkeeping line) is skipped, not fatal"
OUT_UNSTAMPED="$TMPDIR_TEST/trailing-untimestamped.md"
OUT=$(bash "$RENDERER" "$FIXDIR/trailing-untimestamped-line.jsonl" "$OUT_UNSTAMPED" 2>&1); ST=$?
assert_exit "exits 0 rather than failing on the null timestamp" 0 $ST "$OUT"
RENDERED_UNSTAMPED="$(cat "$OUT_UNSTAMPED")"
assert_contains "wall clock uses the last line that does carry a timestamp" "Wall clock: 30s" "$RENDERED_UNSTAMPED"
assert_contains "the untimestamped line is not counted as a turn" "Turns counted: 1" "$RENDERED_UNSTAMPED"

echo "[usage] missing arguments"
OUT=$(bash "$RENDERER" "$FIXDIR/session-a.jsonl" 2>&1); ST=$?
assert_exit "missing output path -> usage error (exit 2)" 2 $ST "$OUT"

echo "[usage] transcript file not found"
OUT=$(bash "$RENDERER" "$FIXDIR/does-not-exist.jsonl" "$TMPDIR_TEST/x.md" 2>&1); ST=$?
assert_exit "missing transcript -> usage error (exit 2)" 2 $ST "$OUT"

echo "[usage] ceilings file argument given but not found"
OUT=$(bash "$RENDERER" "$FIXDIR/session-a.jsonl" "$TMPDIR_TEST/x.md" "$FIXDIR/does-not-exist.txt" 2>&1); ST=$?
assert_exit "missing ceilings file -> usage error (exit 2)" 2 $ST "$OUT"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
