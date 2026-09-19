#!/usr/bin/env bash
# Tests for check-reachability.sh. Run with:
#   bash plugins/agentic-core/shared/lib/check-reachability.test.sh
#
# No framework — exits 0 on success, 1 on any failure. Every render attempt
# runs the fake-render.sh fixture instead of a real browser role, controlled
# entirely through environment variables, so these tests need no network
# access and no live provider.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECKER="$SCRIPT_DIR/check-reachability.sh"
FAKE_RENDER="$SCRIPT_DIR/../fixtures/reachability/fake-render.sh"

# Log files for the fake render command live under a directory created in
# the current working directory rather than via mktemp's default temp dir —
# some sandboxes deny writes to the system temp dir but always allow the
# working tree itself.
WORKDIR="$(mktemp -d ./.check-reachability-test.XXXXXX)"
trap 'rm -rf "$WORKDIR"' EXIT

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

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1))
    echo "  ok: $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc"
    echo "    expected: $expected"
    echo "    got: $actual"
  fi
}

# count_calls <log-file> — 0 if the file was never created.
count_calls() {
  local log="$1"
  [[ -f "$log" ]] && wc -l < "$log" | tr -d ' ' || echo 0
}

echo "=== check-reachability.sh tests ==="

# --- outcome 1: a loopback address is unreachable, no network call --------

echo "[unreachable] a loopback host, decided with no render attempt"
LOG="$WORKDIR/log-loopback"
OUT=$(FAKE_RENDER_LOG="$LOG" bash "$CHECKER" "http://localhost:3001/path" "$FAKE_RENDER" 2>&1); ST=$?
assert_exit "localhost URL accepted (exit 0)" 0 $ST "$OUT"
assert_contains "status is unreachable" "status: unreachable" "$OUT"
assert_contains "reason names the loopback address" "reason: loopback address" "$OUT"
assert_eq "no render attempt was made" 0 "$(count_calls "$LOG")"

echo "[unreachable] a loopback IPv4 literal"
OUT=$(bash "$CHECKER" "http://127.0.0.1:4502/" "$FAKE_RENDER" 2>&1); ST=$?
assert_exit "127.0.0.1 URL accepted (exit 0)" 0 $ST "$OUT"
assert_contains "status is unreachable" "status: unreachable" "$OUT"
assert_contains "reason names the loopback address" "reason: loopback address" "$OUT"

echo "[unreachable] a link-local IPv4 literal"
OUT=$(bash "$CHECKER" "http://169.254.169.254/meta" "$FAKE_RENDER" 2>&1); ST=$?
assert_exit "link-local URL accepted (exit 0)" 0 $ST "$OUT"
assert_contains "status is unreachable" "status: unreachable" "$OUT"
assert_contains "reason names the link-local address" "reason: link-local address" "$OUT"

echo "[unreachable] an IPv6 loopback literal, bracketed with a port"
OUT=$(bash "$CHECKER" "http://[::1]:4502/" "$FAKE_RENDER" 2>&1); ST=$?
assert_exit "IPv6 loopback URL accepted (exit 0)" 0 $ST "$OUT"
assert_contains "status is unreachable" "status: unreachable" "$OUT"
assert_contains "reason names the loopback address" "reason: loopback address" "$OUT"

echo "[unreachable] an IPv6 link-local literal, bracketed"
OUT=$(bash "$CHECKER" "http://[fe80::1]/next" "$FAKE_RENDER" 2>&1); ST=$?
assert_exit "IPv6 link-local URL accepted (exit 0)" 0 $ST "$OUT"
assert_contains "status is unreachable" "status: unreachable" "$OUT"
assert_contains "reason names the link-local address" "reason: link-local address" "$OUT"

# --- outcome 2: a routable address that answers is reachable --------------

echo "[reachable] a routable address whose render attempt succeeds"
LOG="$WORKDIR/log-reachable"
OUT=$(FAKE_RENDER_RESULT=pass FAKE_RENDER_LOG="$LOG" REACHABILITY_LADDER="0 0 0" \
  bash "$CHECKER" "https://example.test/page" "$FAKE_RENDER" 2>&1); ST=$?
assert_exit "routable, answering URL accepted (exit 0)" 0 $ST "$OUT"
assert_contains "status is reachable" "status: reachable" "$OUT"
assert_contains "reason carries the HTTP status" "reason: HTTP 200" "$OUT"
assert_eq "exactly one render attempt was made" 1 "$(count_calls "$LOG")"

# --- outcome 3: a routable address that does not answer -------------------

echo "[unconfirmed] a routable address whose one and only render attempt fails"
LOG="$WORKDIR/log-single-fail"
OUT=$(FAKE_RENDER_RESULT=fail FAKE_RENDER_LOG="$LOG" REACHABILITY_LADDER="0" \
  bash "$CHECKER" "https://example.test/down" "$FAKE_RENDER" 2>&1); ST=$?
assert_exit "routable, unanswering URL accepted (exit 0)" 0 $ST "$OUT"
assert_contains "status is unconfirmed, not unreachable or reachable" "status: unconfirmed" "$OUT"
assert_eq "one render attempt was made" 1 "$(count_calls "$LOG")"

# --- outcome 3 stays distinct from its neighbours --------------------------

echo "[distinct] unconfirmed never collapses into unreachable or reachable"
assert_contains "unconfirmed output does not also read unreachable" "status: unconfirmed" "$OUT"
if [[ "$OUT" == *"status: unreachable"* || "$OUT" == *"status: reachable"* ]]; then
  FAIL=$((FAIL + 1))
  echo "  FAIL: unconfirmed collapsed into a neighbouring outcome"
  echo "    got: $OUT"
else
  PASS=$((PASS + 1))
  echo "  ok: unconfirmed reported on its own, not as unreachable or reachable"
fi

# --- the backoff budget: every rung is spent before giving up -------------

echo "[budget] the retry ladder is exhausted, not abandoned after one try"
LOG="$WORKDIR/log-budget"
OUT=$(FAKE_RENDER_RESULT=fail FAKE_RENDER_LOG="$LOG" REACHABILITY_LADDER="0 0 0" \
  bash "$CHECKER" "https://example.test/never" "$FAKE_RENDER" 2>&1); ST=$?
assert_exit "exhausted budget still accepted (exit 0)" 0 $ST "$OUT"
assert_contains "status is unconfirmed" "status: unconfirmed" "$OUT"
assert_contains "reason names the attempt count" "reason: no successful render within 3 attempt(s)" "$OUT"
assert_eq "the full three-rung ladder was spent, not short-circuited" 3 "$(count_calls "$LOG")"

# --- usage errors -----------------------------------------------------------

echo "[usage] no arguments at all"
OUT=$(bash "$CHECKER" 2>&1); ST=$?
assert_exit "no args -> usage error (exit 2)" 2 $ST "$OUT"

echo "[usage] a url with no render command"
OUT=$(bash "$CHECKER" "https://example.test/" 2>&1); ST=$?
assert_exit "no render command -> usage error (exit 2)" 2 $ST "$OUT"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
