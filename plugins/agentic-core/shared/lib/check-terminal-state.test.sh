#!/usr/bin/env bash
# Tests for check-terminal-state.sh. Run with:
#   bash plugins/agentic-core/shared/lib/check-terminal-state.test.sh
#
# No framework — exits 0 on success, 1 on any failure.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/check-terminal-state.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/check-terminal-state.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0

# case <description> <expected exit> <expected output fragment> <file content | __absent__>
case_() {
  local desc="$1" expected="$2" needle="$3" content="$4" file="$WORK/terminal-state.txt"
  rm -f "$file"
  [[ "$content" == "__absent__" ]] || printf '%s\n' "$content" > "$file"
  local out status
  out="$(bash "$CHECK" "$file" 2>&1)"; status=$?
  if [[ "$status" == "$expected" && "$out" == *"$needle"* ]]; then
    PASS=$((PASS + 1)); echo "  ok: $desc"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: $desc"
    echo "    expected exit=$expected containing '$needle', got exit=$status: $out"
  fi
}

case_ "delivered passes"            0 "verdict: pass"  $'terminal: delivered\n| stage | verdict |\npublished: PR #1'
case_ "failed fails, stage named"   1 "stage: serve"   $'terminal: failed\nstage: serve\nsummary: no answer'
case_ "blocked fails, cause named"  1 "missing: q"     $'terminal: blocked\nmissing: q\nrecorded: .ai/x'
case_ "no file: no terminal state"  1 "route ended without a terminal state" "__absent__"
case_ "empty file is invalid"       1 "invalid"        ""
case_ "a stage envelope is invalid" 1 "invalid"        $'## Result\nverdict: pass\nsummary: branch ready'
case_ "warn is invalid"             1 "invalid"        $'terminal: warn'

out="$(bash "$CHECK" 2>&1)"; status=$?
if [[ "$status" == 2 ]]; then PASS=$((PASS + 1)); echo "  ok: no argument is a usage error"
else FAIL=$((FAIL + 1)); echo "  FAIL: no argument: exit=$status: $out"; fi

echo "passed: $PASS, failed: $FAIL"
[[ "$FAIL" -eq 0 ]]
