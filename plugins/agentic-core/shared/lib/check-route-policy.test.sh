#!/usr/bin/env bash
# Tests for check-route-policy.sh. Run with:
#   bash plugins/agentic-core/shared/lib/check-route-policy.test.sh
#
# No framework — exits 0 on success, 1 if any case fails.
#
# The property under test is fail-closed: a policy the checker cannot read
# completely is refused, never filled in with a default.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/check-route-policy.sh"

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); echo "  ok: $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; shift; for l in "$@"; do echo "    $l"; done; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/check-route-policy.XXXXXX")" || { echo "cannot create a temp dir" >&2; exit 2; }
[[ -n "$WORK" && -d "$WORK" ]] || { echo "cannot create a temp dir" >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT

GOOD='version: 1

# deny beats allow
forbidden:
  - "Bash(gh pr merge*)"
  - "Bash(git push -f*)"   # short form too
  - "WebFetch"

limits:
  runs_per_identity_per_day: 10
  runs_per_day: 30

budget:
  max_usd_per_run: 15.5

caps:
  max_turns: 200
  timeout_minutes: 45

break_glass:
  word: "override"
  approvers:
    - "557058:abc-def"
    - "someone_else"'

# run <policy text> — writes it, runs the checker; sets OUT, ERR, STATUS
run() {
  printf '%s\n' "$1" > "$WORK/policy.yaml"
  OUT="$(bash "$CHECK" "$WORK/policy.yaml" 2>"$WORK/err")"; STATUS=$?
  ERR="$(cat "$WORK/err")"
}

# refuses <name> <policy text> <expected stderr fragment>
refuses() {
  run "$2"
  if [[ "$STATUS" == 1 && "$ERR" == *"$3"* && -z "$OUT" ]]; then ok "$1"; else bad "$1" "status $STATUS" "out: $OUT" "err: $ERR"; fi
}

# without <line regex> — the good policy with matching lines removed
without() { printf '%s\n' "$GOOD" | grep -vE "$1"; }
# replace <from> <to> — the good policy with one literal substitution
# (unquoted inside the expansion: older shells keep quotes there literally;
# no case below uses a glob character in <from>)
replace() { local p="$GOOD" from="$1" to="$2"; printf '%s\n' "${p/$from/$to}"; }

echo "=== check-route-policy.sh tests ==="

echo "[usage]"
OUT="$(bash "$CHECK" 2>/dev/null)"; STATUS=$?
[[ "$STATUS" == 2 ]] && ok "no argument: exit 2" || bad "no argument" "status $STATUS"

echo "[a complete policy]"
run "$GOOD"
EXPECTED='version=1
forbidden=Bash(gh pr merge*)
forbidden=Bash(git push -f*)
forbidden=WebFetch
limits.runs_per_identity_per_day=10
limits.runs_per_day=30
budget.max_usd_per_run=15.5
caps.max_turns=200
caps.timeout_minutes=45
break_glass.word=override
break_glass.approver=557058:abc-def
break_glass.approver=someone_else'
if [[ "$STATUS" == 0 && "$OUT" == "$EXPECTED" ]]; then ok "valid: exit 0, normalized, comments dropped, order kept"; else bad "valid policy" "status $STATUS" "err: $ERR" "out:" "$OUT"; fi

echo "[missing or unreadable — fail closed]"
OUT="$(bash "$CHECK" "$WORK/nope.yaml" 2>"$WORK/err")"; STATUS=$?
[[ "$STATUS" == 1 && "$(cat "$WORK/err")" == *"not found"* ]] && ok "missing file: exit 1" || bad "missing file" "status $STATUS"
refuses "empty file" "" "version is missing"

echo "[version]"
refuses "unknown version" "$(replace 'version: 1' 'version: 2')" "unknown version '2'"
refuses "no version" "$(without '^version:')" "version is missing"

echo "[forbidden list]"
refuses "no forbidden list" "$(without 'forbidden|Bash\(|WebFetch')" "forbidden is empty or missing"
refuses "empty forbidden list" "$(without 'Bash\(|WebFetch')" "forbidden is empty or missing"
refuses "a rule that is not a tool rule" "$(replace '"WebFetch"' '"rm -rf /"')" "is not <Tool> or <Tool>(<pattern>)"

echo "[numbers — no defaults]"
refuses "missing daily limit" "$(without 'runs_per_day:')" "'limits.runs_per_day' is missing"
refuses "missing budget" "$(without 'max_usd_per_run')" "'budget.max_usd_per_run' is missing"
refuses "missing turn cap" "$(without 'max_turns')" "'caps.max_turns' is missing"
refuses "zero limit" "$(replace 'runs_per_day: 30' 'runs_per_day: 0')" "positive whole number"
refuses "negative limit" "$(replace 'runs_per_day: 30' 'runs_per_day: -3')" "positive whole number"
refuses "fractional turn cap" "$(replace 'max_turns: 200' 'max_turns: 2.5')" "positive whole number"
refuses "zero budget" "$(replace 'max_usd_per_run: 15.5' 'max_usd_per_run: 0.00')" "greater than zero"
refuses "budget with a unit" "$(replace 'max_usd_per_run: 15.5' 'max_usd_per_run: 15usd')" "positive number"
run "$(replace 'timeout_minutes: 45' 'timeout_minutes: 0.2')"
[[ "$STATUS" == 0 && "$OUT" == *"caps.timeout_minutes=0.2"* ]] && ok "a fractional timeout is allowed" || bad "fractional timeout" "status $STATUS" "err: $ERR"

echo "[break-glass]"
refuses "no approvers" "$(without '557058|someone_else')" "break_glass.approvers is empty"
refuses "approvers key missing" "$(without 'approvers|557058|someone_else')" "'break_glass.approvers' is missing"
refuses "an approver that is not a handle" "$(replace '"someone_else"' '"two words"')" "is not an identity handle"
refuses "a break-glass word with spaces" "$(replace 'word: "override"' 'word: "please override"')" "one lower-case word"

echo "[typos are refused, not ignored]"
refuses "unknown top-level key" "$(printf '%s\nextra: 1' "$GOOD")" "unknown key 'extra'"
refuses "misspelt second-level key" "$(replace 'runs_per_day: 30' 'runs_per_dya: 30')" "unknown key 'limits.runs_per_dya'"
refuses "a key given twice" "$(replace 'max_turns: 200' 'max_turns: 200
  max_turns: 9')" "given twice"
refuses "a block given twice" "$(printf '%s\ncaps:\n  max_turns: 1' "$GOOD")" "'caps' given twice"
refuses "a list item outside a list" "$(replace 'runs_per_day: 30' 'runs_per_day: 30
  - "Bash(x)"')" "a list item outside a list"

echo ""
echo "passed: $PASS, failed: $FAIL"
[[ "$FAIL" == 0 ]]
