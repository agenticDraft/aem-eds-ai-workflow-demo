#!/usr/bin/env bash
# Tests for capture-envelope.sh. Run with:
#   bash plugins/agentic-core/shared/lib/capture-envelope.test.sh
#
# No framework — exits 0 on success, 1 if any case fails. Every case builds its
# input file in a temporary directory, because each one is a handful of lines
# whose only interesting property is its shape.
#
# Three things are asserted on every case, not just the interesting ones: the
# resulting file content, the exit code, and what was reported on stdout. The
# report is part of the contract — a normalization nobody can see is
# indistinguishable from an envelope that was already correct.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CAPTURE="$SCRIPT_DIR/capture-envelope.sh"
VALIDATE="$SCRIPT_DIR/validate-result-envelope.sh"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/capture-envelope.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); echo "  ok: $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; shift; for l in "$@"; do echo "    $l"; done; }

VALID_ENVELOPE='## Result
verdict: warn
summary: a stage said something.
artifacts:
  - .ai/run-context/thing.json
next_action: none'

# case <name> <input-content> -- echoes the file path
case_file() {
  local name="$1" content="$2"
  local f="$WORK/$name.txt"
  printf '%s\n' "$content" > "$f"
  echo "$f"
}

# assert_capture <desc> <file> <expected-content> <expected-stdout-substring>
assert_capture() {
  local desc="$1" f="$2" expected="$3" report="$4"
  local out status
  out="$(bash "$CAPTURE" "$f" 2>&1)"; status=$?
  if [[ "$status" != 0 ]]; then
    bad "$desc" "expected exit 0, got $status" "output: $out"; return
  fi
  local got; got="$(cat "$f")"
  if [[ "$got" != "$expected" ]]; then
    bad "$desc" "content differs" "--- expected ---" "$expected" "--- got ---" "$got"; return
  fi
  if [[ "$out" != *"$report"* ]]; then
    bad "$desc" "expected stdout to contain: $report" "got: $out"; return
  fi
  ok "$desc"
}

echo "=== capture-envelope.sh tests ==="

echo "[no change] an envelope that is already correct is left exactly alone"
assert_capture "a conformant envelope is unchanged, and says so" \
  "$(case_file clean "$VALID_ENVELOPE")" \
  "$VALID_ENVELOPE" \
  "unchanged"

echo "[blank lines] the defect this exists for"
assert_capture "one blank line between the heading and verdict is removed" \
  "$(case_file one-blank '## Result

verdict: warn
summary: a stage said something.
artifacts:
  - .ai/run-context/thing.json
next_action: none')" \
  "$VALID_ENVELOPE" \
  "normalized"

assert_capture "several blank lines are removed" \
  "$(case_file many-blanks '## Result



verdict: warn
summary: a stage said something.
artifacts:
  - .ai/run-context/thing.json
next_action: none')" \
  "$VALID_ENVELOPE" \
  "normalized"

echo "[preamble] everything above the block is not part of the envelope"
assert_capture "prose above the heading is dropped" \
  "$(case_file preamble 'I did the thing, and here is what happened.

Some more narration.

## Result
verdict: warn
summary: a stage said something.
artifacts:
  - .ai/run-context/thing.json
next_action: none')" \
  "$VALID_ENVELOPE" \
  "normalized"

assert_capture "prose above the heading AND a blank line below it" \
  "$(case_file both 'Narration first.

## Result

verdict: warn
summary: a stage said something.
artifacts:
  - .ai/run-context/thing.json
next_action: none')" \
  "$VALID_ENVELOPE" \
  "normalized"

assert_capture "a heading quoted in prose does not win over the real block at the end" \
  "$(case_file quoted 'I will end with a ## Result block.

## Result
verdict: pass
summary: an example nobody meant as the envelope.
artifacts: []
next_action: none

## Result
verdict: warn
summary: a stage said something.
artifacts:
  - .ai/run-context/thing.json
next_action: none')" \
  "$VALID_ENVELOPE" \
  "normalized"

echo "[restraint] anything that is not a blank line is left for the validator to reject"
NOT_VERDICT='## Result

- verdict: warn
- summary: wrapped in a list, which the contract forbids.'
assert_capture "a non-verdict first line is left untouched, blank line and all" \
  "$(case_file not-verdict "$NOT_VERDICT")" \
  "$NOT_VERDICT" \
  "left unchanged"

echo "[idempotent] running twice changes nothing the second time"
F="$(case_file twice '## Result

verdict: warn
summary: a stage said something.
artifacts:
  - .ai/run-context/thing.json
next_action: none')"
bash "$CAPTURE" "$F" >/dev/null 2>&1
assert_capture "a second pass reports unchanged" "$F" "$VALID_ENVELOPE" "unchanged"

echo "[end to end] the normalized file passes the validator that rejected it"
F="$(case_file e2e '## Result

verdict: warn
summary: a stage said something.
artifacts:
  - .ai/run-context/thing.json
next_action: none')"
bash "$VALIDATE" "$F" >/dev/null 2>&1; BEFORE=$?
[[ "$BEFORE" != 0 ]] && ok "the validator rejects it before capture" || bad "the validator rejects it before capture" "it passed, so this case proves nothing"
bash "$CAPTURE" "$F" >/dev/null 2>&1
bash "$VALIDATE" "$F" >/dev/null 2>&1; AFTER=$?
[[ "$AFTER" == 0 ]] && ok "the validator accepts it after capture" || bad "the validator accepts it after capture" "still rejected, exit $AFTER"

echo "[errors] the two non-zero exits"
assert_exit() {
  local desc="$1" want="$2"; shift 2
  local status
  "$@" >/dev/null 2>&1; status=$?
  [[ "$status" == "$want" ]] && ok "$desc" || bad "$desc" "expected exit $want, got $status"
}

F="$(case_file noheading 'There is no envelope here at all.')"
assert_exit "no '## Result' heading -> exit 1" 1 bash "$CAPTURE" "$F"
assert_exit "missing argument -> exit 2" 2 bash "$CAPTURE"
assert_exit "unreadable file -> exit 2" 2 bash "$CAPTURE" "$WORK/nope.txt"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
