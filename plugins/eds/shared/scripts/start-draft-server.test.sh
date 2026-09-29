#!/usr/bin/env bash
# start-draft-server.test.sh — the draft server's branch-length gate (D539),
# with `curl` and `npx` stubbed first on PATH. Each stub records its calls, so
# the suite can assert that a too-long branch never polls and never starts.
# Each case runs from a throwaway git repository with the branch checked out,
# because the script measures the branch of its working directory.
#
# Usage:
#   bash start-draft-server.test.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
START="$SCRIPT_DIR/start-draft-server.sh"

PASS=0
FAIL=0

ok()  { echo "  ok: $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "    $2"; FAIL=$((FAIL + 1)); }

assert_eq()      { if [ "$2" == "$3" ]; then ok "$1"; else bad "$1" "expected: $2 — got: $3"; fi; }
assert_has()     { if [[ "$3" == *"$2"* ]]; then ok "$1"; else bad "$1" "expected to contain: $2 — got: $3"; fi; }
assert_lacks()   { if [[ "$3" != *"$2"* ]]; then ok "$1"; else bad "$1" "expected not to contain: $2 — got: $3"; fi; }
assert_no_file() { if [ ! -e "$2" ]; then ok "$1"; else bad "$1" "present: $2"; fi; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/start-draft-server.XXXXXX") || { echo "cannot create a temp dir" >&2; exit 2; }
[ -n "$WORK" ] && [ -d "$WORK" ] || { echo "cannot create a temp dir" >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT

# Stubs: curl answers 200 (a server is already up); npx records and exits.
mkdir -p "$WORK/bin"
printf '#!/usr/bin/env bash\necho "$*" >> "%s/curl-calls"\nprintf 200\n' "$WORK" > "$WORK/bin/curl"
printf '#!/usr/bin/env bash\necho "$*" >> "%s/npx-calls"\nexit 1\n' "$WORK" > "$WORK/bin/npx"
chmod +x "$WORK/bin/curl" "$WORK/bin/npx"
export PATH="$WORK/bin:$PATH"

# repo_on <branch> — a fresh repository with <branch> checked out; prints its path
repo_on() {
  local dir="$WORK/repo-$RANDOM$RANDOM"
  git init -q -b "$1" "$dir" >/dev/null 2>&1 || return 1
  echo "$dir"
}

run_in() {
  rm -f "$WORK/curl-calls" "$WORK/npx-calls"
  OUT=$(cd "$1" && bash "$START" "http://localhost:3000/preview" "$1/.ai/logs/draft-server.log" "$1/.ai/logs/draft-server.pid" 2>&1)
  CODE=$?
}

echo "[too-long] a 24-character branch fails before any poll or start"
DIR=$(repo_on "bbbbbbbbbbbbbbbbbbbbbbbb")
if [ -z "$DIR" ]; then
  bad "throwaway repository created" "git init -b failed"
else
  run_in "$DIR"
  assert_eq "exit 1" "1" "$CODE"
  assert_has "start-failed names the cause" "start-failed: branch name too long (24 > 23)" "$OUT"
  assert_lacks "never the poll ladder's no-answer" "no-answer" "$OUT"
  assert_no_file "curl never called (no poll)" "$WORK/curl-calls"
  assert_no_file "npx never called (no start)" "$WORK/npx-calls"
  assert_no_file "no pid file" "$DIR/.ai/logs/draft-server.pid"
fi

echo "[too-long] Task 3's real 28-character branch"
DIR=$(repo_on "phase-28-task-3-draft-server")
run_in "$DIR"
assert_eq "exit 1" "1" "$CODE"
assert_has "names 28 > 23" "start-failed: branch name too long (28 > 23)" "$OUT"
assert_no_file "curl never called" "$WORK/curl-calls"

echo "[ok] a 23-character branch reaches the poll and reuses the answering server"
DIR=$(repo_on "bbbbbbbbbbbbbbbbbbbbbbb")
run_in "$DIR"
assert_eq "exit 0" "0" "$CODE"
assert_has "ready, reused" "ready: origin=http://localhost:3001 port=3001 started=no pid=none log=none" "$OUT"
if [ -s "$WORK/curl-calls" ]; then ok "curl polled"; else bad "curl polled" "no curl call recorded"; fi
assert_no_file "npx not called (reused)" "$WORK/npx-calls"

echo "[ok] this task's own 22-character branch"
DIR=$(repo_on "phase-28-task-4-verify")
run_in "$DIR"
assert_eq "exit 0" "0" "$CODE"

echo "[no branch] outside a repository there is nothing to measure; the poll runs"
mkdir -p "$WORK/plain"
run_in "$WORK/plain"
assert_eq "exit 0" "0" "$CODE"
assert_lacks "no branch-length failure" "branch name too long" "$OUT"

echo "[usage] a missing argument is still exit 2, before any check"
OUT=$(bash "$START" "http://localhost:3000/preview" 2>&1); CODE=$?
assert_eq "exit 2" "2" "$CODE"

echo "=== $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
