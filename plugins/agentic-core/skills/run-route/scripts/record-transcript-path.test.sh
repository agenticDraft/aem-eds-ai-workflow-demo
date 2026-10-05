#!/usr/bin/env bash
# Tests for record-transcript-path.sh. Run with:
#   bash plugins/agentic-core/skills/run-route/scripts/record-transcript-path.test.sh
#
# Each case drives the hook the way the harness does: the hook's JSON input on
# stdin, CLAUDE_PROJECT_DIR pointed at a scratch directory, so nothing lands in
# a real run's context.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/record-transcript-path.sh"

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); echo "  ok: $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; shift; for l in "$@"; do echo "    $l"; done; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected: $2" "got: $3"; fi; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/record-transcript-path.XXXXXX")"
if [ -z "$WORK" ] || [ ! -d "$WORK" ]; then
  echo "FAIL: could not create a scratch directory under ${TMPDIR:-/tmp}" >&2
  exit 1
fi
trap 'rm -rf "$WORK"' EXIT
RECORD="$WORK/.ai/run-context/transcript-path.txt"

# run_hook <stdin> — drives the hook; sets STATUS and OUT
run_hook() {
  OUT="$(printf '%s' "$1" | CLAUDE_PROJECT_DIR="$WORK" bash "$HOOK" 2>&1)"
  STATUS=$?
}
input() { printf '{"session_id":"s1","transcript_path":%s,"cwd":"%s","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"ls"}}' "$(printf '%s' "$1" | jq -R .)" "$WORK"; }

echo "a project with no .ai/ directory: nothing is written, the tool proceeds"
run_hook "$(input /home/u/.claude/projects/p/abc.jsonl)"
eq "exit 0" 0 "$STATUS"
eq "silent" "" "$OUT"
[ ! -e "$WORK/.ai" ] && ok "no .ai/ created" || bad "no .ai/ created"

echo "a project with .ai/: the transcript path is recorded under .ai/run-context/"
mkdir -p "$WORK/.ai"
run_hook "$(input /home/u/.claude/projects/p/abc.jsonl)"
eq "exit 0" 0 "$STATUS"
eq "silent" "" "$OUT"
eq "the path, one line" "/home/u/.claude/projects/p/abc.jsonl" "$(cat "$RECORD" 2>/dev/null)"
eq "exactly one line" "1" "$(wc -l < "$RECORD" | tr -d ' ')"

echo "the same path again leaves the file as it is; a different session's path replaces it"
touch -t 200001010000 "$RECORD"
BEFORE="$(stat -f %m "$RECORD" 2>/dev/null || stat -c %Y "$RECORD")"
run_hook "$(input /home/u/.claude/projects/p/abc.jsonl)"
AFTER="$(stat -f %m "$RECORD" 2>/dev/null || stat -c %Y "$RECORD")"
eq "not rewritten when unchanged (mtime kept)" "$BEFORE" "$AFTER"
run_hook "$(input /home/u/.claude/projects/p/def.jsonl)"
eq "replaced by the new path" "/home/u/.claude/projects/p/def.jsonl" "$(cat "$RECORD")"

echo "a subagent's own transcript is never recorded as the session's"
run_hook "$(input /home/u/.claude/projects/p/def/subagents/agent-123.jsonl)"
eq "exit 0" 0 "$STATUS"
eq "the session path stays" "/home/u/.claude/projects/p/def.jsonl" "$(cat "$RECORD")"

echo "an input with no transcript path, or no JSON at all, writes nothing and never blocks"
run_hook '{"tool_name":"Bash","tool_input":{"command":"ls"}}'
eq "exit 0 without a path" 0 "$STATUS"
eq "the file stays" "/home/u/.claude/projects/p/def.jsonl" "$(cat "$RECORD")"
run_hook 'not json'
eq "exit 0 on garbage" 0 "$STATUS"
run_hook ''
eq "exit 0 on empty input" 0 "$STATUS"
eq "the file still stays" "/home/u/.claude/projects/p/def.jsonl" "$(cat "$RECORD")"

echo "run-context/ is created when .ai/ exists but the directory does not yet"
rm -rf "$WORK/.ai/run-context"
run_hook "$(input /home/u/.claude/projects/p/ghi.jsonl)"
eq "recorded after creating the directory" "/home/u/.claude/projects/p/ghi.jsonl" "$(cat "$RECORD" 2>/dev/null)"

echo
echo "passed: $PASS, failed: $FAIL"
[ "$FAIL" -eq 0 ]
