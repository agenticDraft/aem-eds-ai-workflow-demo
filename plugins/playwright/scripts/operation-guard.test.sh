#!/usr/bin/env bash
# Tests for the hang-and-silence guard every operation runs under. Run with:
#   bash plugins/playwright/scripts/operation-guard.test.sh
#
# Needs a real headless Chromium and the playwright package; with either
# missing the suite reports SKIP and exits 0. Exits 1 if anything failed.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACK="$(cd "$SCRIPT_DIR/.." && pwd)"
TMP_ROOT="${TMPDIR:-/tmp}"
WORK="$(mktemp -d "${TMP_ROOT%/}/operation-guard-test.XXXXXX")"

PASS=0
FAIL=0

cleanup() {
  [[ -n "${SERVER_PID:-}" ]] && kill "$SERVER_PID" 2>/dev/null
  rm -rf "$WORK"
}
trap cleanup EXIT

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

assert_match() {
  local desc="$1" pattern="$2" actual="$3"
  if [[ "$actual" =~ $pattern ]]; then
    PASS=$((PASS + 1)); echo "  ok: $desc"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: $desc"
    echo "    pattern: $pattern"
    echo "    got:     $actual"
  fi
}

if ! node -e "const fs=require('fs');const p=require('playwright');process.exit(fs.existsSync(p.chromium.executablePath())?0:1)" 2>/dev/null; then
  echo "SKIP: playwright or its Chromium is not available here"
  exit 0
fi

# run_bounded <seconds> <outfile> <cmd...> — runs the command in the working
# directory, killing it hard once the bound passes. Sets BOUNDED_TIMED_OUT
# (1 when the bound had to kill it) and BOUNDED_SECONDS.
run_bounded() {
  local limit="$1" out="$2"; shift 2
  local start=$SECONDS pid
  "$@" >"$out" 2>"$out.err" &
  pid=$!
  BOUNDED_TIMED_OUT=0
  while kill -0 "$pid" 2>/dev/null; do
    if (( SECONDS - start >= limit )); then
      kill -9 "$pid" 2>/dev/null
      BOUNDED_TIMED_OUT=1
      break
    fi
    sleep 0.2
  done
  wait "$pid" 2>/dev/null
  BOUNDED_EXIT=$?
  BOUNDED_SECONDS=$((SECONDS - start))
}

node "$SCRIPT_DIR/hang-fixture-server.cjs" "$WORK/port" &
SERVER_PID=$!
for _ in $(seq 1 50); do [[ -s "$WORK/port" ]] && break; sleep 0.1; done
BASE="http://127.0.0.1:$(cat "$WORK/port")"

RENDER="$PACK/skills/render/scripts/render.cjs"

echo "=== operation guard tests ==="

echo "[render] a page that blocks its main thread after load"
D="$WORK/render-hang"; mkdir -p "$D"
cd "$D" && PLAYWRIGHT_OPERATION_TIMEOUT_MS=3000 run_bounded 25 "$D/out" node "$RENDER" "$BASE/hang"; cd "$PACK"
OUT="$(cat "$D/out")"
assert_eq "render returns instead of hanging" "0" "$BOUNDED_TIMED_OUT"
assert_eq "render exits 0" "0" "$BOUNDED_EXIT"
assert_match "verdict is fail" "verdict: fail" "$OUT"
assert_match "summary names the timeout" "summary: [^"$'\n'"]*timed out" "$OUT"
assert_match "the failed envelope lists the log" "artifacts:"$'\n'"  - \\.ai/playwright/render-[^ ]*\\.log" "$OUT"

echo "[render] errors reach disk even when the run is killed"
D="$WORK/render-err"; mkdir -p "$D"
cd "$D" && PLAYWRIGHT_OPERATION_TIMEOUT_MS=60000 run_bounded 6 "$D/out" node "$RENDER" "$BASE/err"; cd "$PACK"
LOG="$(ls "$D"/.ai/playwright/render-*.log 2>/dev/null | head -1)"
assert_eq "the run was killed by the bound" "1" "$BOUNDED_TIMED_OUT"
assert_match "a log file exists" "render-.*\\.log" "$LOG"
CONTENT="$(cat "$LOG" 2>/dev/null)"
assert_match "the console error is in the log" "fixture-console-error" "$CONTENT"
assert_match "the uncaught exception is in the log" "fixture-uncaught" "$CONTENT"

echo "[render] a healthy page passes and lists the log beside its state"
D="$WORK/render-ok"; mkdir -p "$D"
cd "$D" && run_bounded 25 "$D/out" node "$RENDER" "$BASE/ok"; cd "$PACK"
OUT="$(cat "$D/out")"
assert_match "verdict is pass" "verdict: pass" "$OUT"
assert_match "the envelope lists the log" "  - \\.ai/playwright/render-[^ ]*\\.log" "$OUT"
assert_match "the envelope lists the state" "  - \\.ai/playwright/render-[^ ]*\\.json" "$OUT"

# The sibling operations share the guard: each takes its own arguments.
op_args() {
  case "$1" in
    capture) echo "$2 800" ;;
    measure) echo "$2 .t" ;;
    interact) echo "$2 click:#b read:.t" ;;
  esac
}

for OP in capture measure interact; do
  SCRIPT="$PACK/skills/$OP/scripts/$OP.cjs"

  echo "[$OP] a page that blocks its main thread after load"
  D="$WORK/$OP-hang"; mkdir -p "$D"
  # shellcheck disable=SC2046
  cd "$D" && PLAYWRIGHT_OPERATION_TIMEOUT_MS=3000 run_bounded 25 "$D/out" node "$SCRIPT" $(op_args "$OP" "$BASE/hang"); cd "$PACK"
  OUT="$(cat "$D/out")"
  assert_eq "$OP returns instead of hanging" "0" "$BOUNDED_TIMED_OUT"
  assert_eq "$OP exits 0" "0" "$BOUNDED_EXIT"
  assert_match "$OP verdict is fail" "verdict: fail" "$OUT"
  assert_match "$OP summary names the timeout" "summary: [^"$'\n'"]*timed out" "$OUT"
  assert_match "$OP envelope lists the log" "  - \\.ai/playwright/$OP-[^ ]*\\.log" "$OUT"

  echo "[$OP] errors reach disk even when the run is killed"
  D="$WORK/$OP-err"; mkdir -p "$D"
  # shellcheck disable=SC2046
  cd "$D" && PLAYWRIGHT_OPERATION_TIMEOUT_MS=60000 run_bounded 6 "$D/out" node "$SCRIPT" $(op_args "$OP" "$BASE/err"); cd "$PACK"
  LOG="$(ls "$D"/.ai/playwright/$OP-*.log 2>/dev/null | head -1)"
  CONTENT="$(cat "$LOG" 2>/dev/null)"
  assert_eq "$OP was killed by the bound" "1" "$BOUNDED_TIMED_OUT"
  assert_match "$OP console error is in the log" "fixture-console-error" "$CONTENT"
  assert_match "$OP uncaught exception is in the log" "fixture-uncaught" "$CONTENT"
done

echo "=== $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
