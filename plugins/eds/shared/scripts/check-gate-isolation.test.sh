#!/usr/bin/env bash
# check-gate-isolation.test.sh — the gate isolation check (D537, D121). No framework; exits 0 when every case passes, 1 otherwise.
#
# Usage:
#   bash check-gate-isolation.test.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/check-gate-isolation.sh"

PASS=0
FAIL=0

ok()  { echo "  ok: $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "    $2"; FAIL=$((FAIL + 1)); }

assert_eq()  { if [ "$2" == "$3" ]; then ok "$1"; else bad "$1" "expected: $2 — got: $3"; fi; }
assert_has() { if [[ "$3" == *"$2"* ]]; then ok "$1"; else bad "$1" "expected to contain: $2 — got: $3"; fi; }

# run_in <dir> <args...> — run the check with <dir> as its working directory
run_in() { local d="$1"; shift; OUT=$(cd "$d" && bash "$CHECK" "$@" 2>&1); CODE=$?; }
run()    { OUT=$(bash "$CHECK" "$@" 2>&1); CODE=$?; }

TMP=$(mktemp -d "${TMPDIR:-/tmp}/gate-isolation.XXXXXX") || { echo "mktemp failed" >&2; exit 1; }
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp returned no directory" >&2; exit 1; }
trap 'rm -rf "$TMP"' EXIT

ROOT="$TMP/project"
mkdir -p "$ROOT/.claude/worktrees/agent-1" "$TMP/elsewhere"
ln -s "$ROOT" "$TMP/root-link"

echo "[isolation present] the gate runs in a different directory"
run_in "$ROOT/.claude/worktrees/agent-1" isolation "$ROOT"
assert_eq "worktree under the root → exit 0" "0" "$CODE"
assert_eq "worktree under the root → present" "isolation: present" "$OUT"
run_in "$TMP/elsewhere" isolation "$ROOT"
assert_eq "unrelated directory → present" "isolation: present" "$OUT"

echo "[isolation absent] the gate runs in the project root itself"
run_in "$ROOT" isolation "$ROOT"
assert_eq "same directory → exit 0" "0" "$CODE"
assert_eq "same directory → absent" "isolation: absent" "$OUT"
run_in "$TMP/root-link" isolation "$ROOT"
assert_eq "cwd reached through a symlink → absent" "isolation: absent" "$OUT"
run_in "$ROOT" isolation "$TMP/root-link"
assert_eq "project_root given through a symlink → absent" "isolation: absent" "$OUT"
run_in "$ROOT" isolation "$ROOT/"
assert_eq "trailing slash on project_root → absent" "isolation: absent" "$OUT"

echo "[isolation usage] missing or non-directory project_root"
run_in "$ROOT" isolation
assert_eq "no project_root → exit 2" "2" "$CODE"
run_in "$ROOT" isolation ""
assert_eq "empty project_root → exit 2" "2" "$CODE"
run_in "$ROOT" isolation "$TMP/does-not-exist"
assert_eq "missing directory → exit 2" "2" "$CODE"
touch "$TMP/a-file"
run_in "$ROOT" isolation "$TMP/a-file"
assert_eq "a file, not a directory → exit 2" "2" "$CODE"
assert_has "names the path" "$TMP/a-file" "$OUT"
run_in "$ROOT" isolation "$ROOT" extra
assert_eq "an extra argument → exit 2" "2" "$CODE"

echo "[no cap] the verdict is the review's; isolation is information only (D121)"
run cap absent pass
assert_eq "the cap mode is gone → exit 2" "2" "$CODE"
assert_has "it is named as an unknown mode" "unknown mode 'cap'" "$OUT"

echo "[usage] no mode or an unknown one"
run
assert_eq "no arguments → exit 2" "2" "$CODE"
run compare "$ROOT"
assert_eq "unknown mode → exit 2" "2" "$CODE"

echo
echo "passed: $PASS, failed: $FAIL"
[ "$FAIL" -eq 0 ]
