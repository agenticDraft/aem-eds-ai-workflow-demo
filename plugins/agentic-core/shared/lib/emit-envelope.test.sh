#!/usr/bin/env bash
# Tests for emit-envelope.sh. Run with:
#   bash plugins/agentic-core/shared/lib/emit-envelope.test.sh
#
# No framework — exits 0 on success, 1 if any case fails.
#
# Two halves, and the second matters as much as the first. The emitting half
# asserts the exact bytes written, because the point of this script is that a
# caller never chooses them. The refusing half asserts that a request the
# contract forbids writes nothing at all: a partially written envelope would
# be worse than the free-text one this replaces, since it would look
# deliberate.
#
# Every envelope this script emits is also put through the real validator, so
# the two can never drift apart without a test saying so.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EMIT="$SCRIPT_DIR/emit-envelope.sh"
VALIDATE="$SCRIPT_DIR/validate-result-envelope.sh"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/emit-envelope.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); echo "  ok: $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; shift; for l in "$@"; do echo "    $l"; done; }

N=0
outfile() { N=$((N + 1)); echo "$WORK/env-$N.txt"; }

# assert_emits <desc> <expected-content> -- <emit args...>
assert_emits() {
  local desc="$1" expected="$2"; shift 2; [ "$1" = "--" ] && shift
  local f; f="$(outfile)"
  local out status
  out="$(bash "$EMIT" "$f" "$@" 2>&1)"; status=$?
  if [[ "$status" != 0 ]]; then
    bad "$desc" "expected exit 0, got $status" "output: $out"; return
  fi
  local got; got="$(cat "$f")"
  if [[ "$got" != "$expected" ]]; then
    bad "$desc" "--- expected ---" "$expected" "--- got ---" "$got"; return
  fi
  bash "$VALIDATE" "$f" >/dev/null 2>&1
  if [[ $? != 0 ]]; then
    bad "$desc" "the real validator rejected what this script emitted" "$got"; return
  fi
  ok "$desc"
}

# assert_refuses <desc> -- <emit args...>
assert_refuses() {
  local desc="$1"; shift; [ "$1" = "--" ] && shift
  local f; f="$(outfile)"
  printf 'PREEXISTING\n' > "$f"
  local status
  bash "$EMIT" "$f" "$@" >/dev/null 2>&1; status=$?
  if [[ "$status" != 2 ]]; then
    bad "$desc" "expected exit 2, got $status"; return
  fi
  if [[ "$(cat "$f")" != "PREEXISTING" ]]; then
    bad "$desc" "a refused call wrote to the file anyway" "got: $(cat "$f")"; return
  fi
  ok "$desc"
}

echo "=== emit-envelope.sh tests ==="

echo "[emits] the exact bytes, for each verdict"

assert_emits "minimal pass — artifacts is an empty list, next_action defaults to none" \
'## Result
verdict: pass
summary: it worked.
artifacts: []
next_action: none' \
-- --verdict pass --summary "it worked."

assert_emits "warn with artifacts and metrics" \
'## Result
verdict: warn
summary: something degraded.
artifacts:
  - .ai/run-context/design-reference.json
  - .ai/run-context/design-reference.png
next_action: none
metrics: has_values=false fallback=attachment' \
-- --verdict warn --summary "something degraded." \
   --artifact .ai/run-context/design-reference.json \
   --artifact .ai/run-context/design-reference.png \
   --metrics "has_values=false fallback=attachment"

assert_emits "fail carries its error class" \
'## Result
verdict: fail
summary: it broke.
artifacts: []
next_action: none
error_class: PERMANENT' \
-- --verdict fail --summary "it broke." --error-class PERMANENT

assert_emits "question carries class, question, options and blocker, in contract order" \
'## Result
verdict: question
summary: a human has to choose.
artifacts: []
next_action: none
error_class: TRANSIENT
question: which attachment is the design reference?
options:
  - a.png
  - b.png
blocker: no attachment is named design-reference.png.' \
-- --verdict question --summary "a human has to choose." \
   --error-class TRANSIENT \
   --question "which attachment is the design reference?" \
   --option a.png --option b.png \
   --blocker "no attachment is named design-reference.png."

assert_emits "a non-default next_action is carried through" \
'## Result
verdict: pass
summary: it worked.
artifacts: []
next_action: review the draft' \
-- --verdict pass --summary "it worked." --next-action "review the draft"

echo "[overwrite] a previous stage's file is replaced, not appended to"
F="$(outfile)"
printf 'STALE CONTENT FROM ANOTHER STAGE\n' > "$F"
bash "$EMIT" "$F" --verdict pass --summary "fresh." >/dev/null 2>&1
[[ "$(cat "$F")" == '## Result
verdict: pass
summary: fresh.
artifacts: []
next_action: none' ]] && ok "an existing file is overwritten whole" || bad "an existing file is overwritten whole" "got: $(cat "$F")"

echo "[refuses] a request the contract forbids writes nothing"

assert_refuses "an unknown verdict" -- --verdict done --summary "x."
assert_refuses "no verdict at all" -- --summary "x."
assert_refuses "no summary at all" -- --verdict pass
assert_refuses "no arguments beyond the file" --

LONG="$(printf 'x%.0s' $(seq 1 201))"
assert_refuses "a summary over 200 characters" -- --verdict pass --summary "$LONG"
assert_refuses "a summary containing a line break" -- --verdict pass --summary "one
two"

assert_refuses "error_class on pass, which reports no failure to classify" \
  -- --verdict pass --summary "x." --error-class TRANSIENT
assert_refuses "error_class on warn" \
  -- --verdict warn --summary "x." --error-class TRANSIENT
assert_refuses "an unknown error class" \
  -- --verdict fail --summary "x." --error-class FLAKY

assert_refuses "question verdict with no question text" \
  -- --verdict question --summary "x." --blocker "y."
assert_refuses "question verdict with no blocker" \
  -- --verdict question --summary "x." --question "y?"
assert_refuses "question text on a warn verdict" \
  -- --verdict warn --summary "x." --question "y?"
assert_refuses "blocker on a fail verdict" \
  -- --verdict fail --summary "x." --blocker "y."
assert_refuses "options on a pass verdict" \
  -- --verdict pass --summary "x." --option a

assert_refuses "an unknown flag" -- --verdict pass --summary "x." --colour green

echo "[reset] the file is emptied so a stale one cannot pass for this stage's"
RESET="$SCRIPT_DIR/reset-envelope.sh"

F="$(outfile)"
printf 'AN EARLIER RUN LEFT THIS HERE\n' > "$F"
bash "$RESET" "$F" >/dev/null 2>&1
[[ -f "$F" && ! -s "$F" ]] && ok "an existing file is emptied, not deleted" || bad "an existing file is emptied, not deleted" "still: $(cat "$F" 2>&1)"

F="$WORK/never-existed.txt"
bash "$RESET" "$F" >/dev/null 2>&1
[[ -f "$F" && ! -s "$F" ]] && ok "a file that did not exist is created empty" || bad "a file that did not exist is created empty"

bash "$RESET" >/dev/null 2>&1; S=$?
[[ "$S" == 2 ]] && ok "missing argument -> exit 2" || bad "missing argument -> exit 2" "got exit $S"

bash "$RESET" "$WORK/no/such/dir/x.txt" >/dev/null 2>&1; S=$?
[[ "$S" == 2 ]] && ok "a path in no directory -> exit 2" || bad "a path in no directory -> exit 2" "got exit $S"

echo "[round trip] reset, emit, capture — the shape the driver runs"
F="$(outfile)"
printf 'STALE\n' > "$F"
bash "$RESET" "$F" >/dev/null 2>&1
bash "$EMIT" "$F" --verdict warn --summary "round trip." --artifact a.json >/dev/null 2>&1
bash "$SCRIPT_DIR/capture-envelope.sh" "$F" >/dev/null 2>&1
bash "$VALIDATE" "$F" >/dev/null 2>&1; S=$?
[[ "$S" == 0 ]] && ok "the validator accepts what came out the far end" || bad "the validator accepts what came out the far end" "exit $S: $(cat "$F")"

echo "[capture] what this script writes needs no reduction afterwards"
F="$(outfile)"
bash "$EMIT" "$F" --verdict warn --summary "already correct." --artifact a.json >/dev/null 2>&1
BEFORE="$(cat "$F")"
CAP="$(bash "$SCRIPT_DIR/capture-envelope.sh" "$F" 2>&1)"
[[ "$(cat "$F")" == "$BEFORE" && "$CAP" == *"unchanged"* ]] \
  && ok "capture-envelope.sh reports it unchanged" \
  || bad "capture-envelope.sh reports it unchanged" "report: $CAP"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
