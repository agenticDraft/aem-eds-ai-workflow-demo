#!/usr/bin/env bash
# Tests for render-run-analytics.sh. Run with:
#   bash plugins/agentic-core/shared/lib/render-run-analytics.test.sh
#
# No framework — exits 0 when every case passes, 1 otherwise. Uses the
# analytics fixtures (fixtures/analytics/session-a.jsonl) as the transcript.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRAPPER="$SCRIPT_DIR/render-run-analytics.sh"
FIXDIR="$SCRIPT_DIR/../fixtures/analytics"

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); echo "  ok: $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; shift; for l in "$@"; do echo "    $l"; done; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected: $2" "got: $3"; fi; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/render-run-analytics.XXXXXX")"
if [ -z "$WORK" ] || [ ! -d "$WORK" ]; then
  echo "FAIL: could not create a scratch directory under ${TMPDIR:-/tmp}" >&2
  exit 1
fi
trap 'rm -rf "$WORK"' EXIT

run_wrapper() { OUT="$(bash "$WRAPPER" "$@" 2>&1)"; STATUS=$?; }

echo "no transcript path recorded: skipped, exit 0, nothing written"
CTX="$WORK/none"; mkdir -p "$CTX"
run_wrapper "$CTX"
eq "exit 0" 0 "$STATUS"
eq "says why" "skipped: no transcript path recorded in $CTX" "$OUT"
[ ! -e "$CTX/analytics.md" ] && ok "no analytics.md" || bad "no analytics.md"

echo "a recorded path whose transcript does not exist: skipped, naming the path"
CTX="$WORK/gone"; mkdir -p "$CTX"
printf '%s\n' "$WORK/missing.jsonl" > "$CTX/transcript-path.txt"
run_wrapper "$CTX"
eq "exit 0" 0 "$STATUS"
eq "names the missing transcript" "skipped: transcript not found: $WORK/missing.jsonl" "$OUT"
[ ! -e "$CTX/analytics.md" ] && ok "no analytics.md" || bad "no analytics.md"

echo "an empty record file counts as none recorded"
CTX="$WORK/empty"; mkdir -p "$CTX"; : > "$CTX/transcript-path.txt"
run_wrapper "$CTX"
eq "exit 0" 0 "$STATUS"
eq "says why" "skipped: no transcript path recorded in $CTX" "$OUT"

echo "a recorded path to a real transcript: analytics.md is rendered beside it"
CTX="$WORK/run"; mkdir -p "$CTX"
printf '%s\n' "$FIXDIR/session-a.jsonl" > "$CTX/transcript-path.txt"
run_wrapper "$CTX"
eq "exit 0" 0 "$STATUS"
eq "forwards the renderer's own line" "written: $CTX/analytics.md" "$OUT"
[ -s "$CTX/analytics.md" ] && ok "analytics.md written" || bad "analytics.md written"
eq "it is the analytics contract's file" "# Run analytics" "$(head -1 "$CTX/analytics.md")"
if grep -q 'Source: '"$FIXDIR"'/session-a.jsonl' "$CTX/analytics.md"; then ok "names the transcript it read"; else bad "names the transcript it read"; fi

echo "usage: no directory, or a path that is not a directory → exit 2"
run_wrapper
eq "exit 2 with no argument" 2 "$STATUS"
run_wrapper "$WORK/not-a-dir"
eq "exit 2 for a missing directory" 2 "$STATUS"

echo
echo "passed: $PASS, failed: $FAIL"
[ "$FAIL" -eq 0 ]
