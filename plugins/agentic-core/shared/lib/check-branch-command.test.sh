#!/usr/bin/env bash
# Tests for check-branch-command.sh (D544), the PreToolUse hook. Run with:
#   bash plugins/agentic-core/shared/lib/check-branch-command.test.sh
#
# No framework — exits 0 when every case passes, 1 otherwise. Each case feeds
# the hook the JSON a tool call would, against a temp repository whose config
# names a temp platform pack.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/check-branch-command.sh"

PASS=0
FAIL=0

ok()  { echo "  ok: $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "    $2"; FAIL=$((FAIL + 1)); }

assert_eq()  { if [ "$2" == "$3" ]; then ok "$1"; else bad "$1" "expected: $2 — got: $3"; fi; }
assert_has() { if [[ "$3" == *"$2"* ]]; then ok "$1"; else bad "$1" "expected to contain: $2 — got: $3"; fi; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/check-branch-command.XXXXXX") || { echo "cannot create a temp dir" >&2; exit 2; }
[ -n "$WORK" ] && [ -d "$WORK" ] || { echo "cannot create a temp dir" >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/plugins/example-platform"
printf 'kind: platform\nbranch_name:\n  max_length: 12\n  pattern: "^[a-z0-9/-]+$"\n' \
  > "$WORK/plugins/example-platform/pack.yaml"

REPO="$WORK/repo"
git init -q -b main "$REPO"
mkdir -p "$REPO/.ai/run-context/plugin-roots" "$REPO/sub/dir"
printf 'version: 1\n\npacks:\n  platform: example-platform\n' > "$REPO/.ai/project-config.yaml"
printf '%s\n' "$WORK/plugins/example-platform" > "$REPO/.ai/run-context/plugin-roots/example-platform"
LOG="$REPO/.ai/logs/branch-name-hook.log"

# hook <command> [cwd] — run the hook on a Bash tool call
hook() {
  local input
  input=$(jq -n --arg c "$1" --arg d "${2:-$REPO}" \
    '{hook_event_name: "PreToolUse", tool_name: "Bash", cwd: $d, tool_input: {command: $c}}')
  ERR=$(printf '%s' "$input" | bash "$HOOK" 2>&1 >/dev/null); CODE=$?
}
blocked() { hook "$2" "${3:-}"; assert_eq "blocked: $1" "2" "$CODE"; }
allowed() { hook "$2" "${3:-}"; assert_eq "allowed: $1" "0" "$CODE"; }

echo "[block] every creating form, with a name that fails"
blocked "switch -c, too long"        "git switch -c feature-12345"
assert_has "reason carries the check's line" "too-long: branch=feature-12345 length=13 limit=12" "$ERR"
assert_has "reason says what to do" "rename the branch" "$ERR"
blocked "switch -C"                  "git switch -C Feature"
assert_has "reason for characters" "bad-chars: branch=Feature" "$ERR"
blocked "switch --create"            "git switch --create a_b"
blocked "switch --create="           "git switch --create=a_b"
blocked "checkout -b"                "git checkout -b a_b"
blocked "checkout -B"                "git checkout -B a_b origin/main"
blocked "branch <n>"                 "git branch a_b"
blocked "branch <n> <start>"         "git branch a_b origin/main"
blocked "worktree add -b"            "git worktree add -b a_b ../wt"
blocked "push remote name"           "git push -u origin a_b"
blocked "push src:dst"               "git push origin HEAD:refs/heads/a_b"
blocked "push +src:dst"              "git push origin +main:a_b"
blocked "-C <dir> before the verb"   "git -C sub switch -c a_b"
blocked "-c key=value before the verb" "git -c user.name=x checkout -b a_b"
blocked "env assignment before git"  "GIT_TRACE=0 git switch -c a_b"
blocked "quoted name"                "git switch -c 'a_b'"

echo "[block] inside a chain"
blocked "after &&"                   "git fetch origin main && git switch -c a_b"
blocked "after ;"                    "cd . ; git checkout -b a_b"
blocked "on its own line"            $'git status\ngit switch -c a_b'
blocked "first of two"               "git switch -c a_b && git push -u origin a_b"

echo "[redirection] a redirection or its target is never read as a name"
allowed "push, 2>&1 then a pipe"     "git push -q -u origin feature-1 2>&1 | tail -2"
allowed "push, 2>/dev/null"          "git push origin feature-1 2>/dev/null"
allowed "push, > and a spaced target" "git push origin feature-1 > out_log.txt"
allowed "push, &>file"               "git push origin feature-1 &>out_log.txt"
allowed "push, 2>> spaced target"    "git push origin feature-1 2>> out_log.txt"
allowed "switch -c, 2>&1"            "git switch -c feature-1 2>&1"
blocked "push, bad name then 2>&1"   "git push -u origin a_b 2>&1 | tail -2"
blocked "push, redirection first"    "git push 2>&1 origin a_b"
blocked "push, spaced target first"  "git push > out.txt origin a_b"
blocked "switch -c, bad name, 2>&1"  "git switch -c a_b 2>&1"

echo "[allow] a name that passes, and commands that create nothing"
allowed "switch -c, fits"            "git switch -c feature-1"
allowed "push the same good name"    "git push -u origin feature-1"
allowed "plain switch"               "git switch main"
allowed "checkout a path"            "git checkout -- a_b.txt"
allowed "branch list"                "git branch"
allowed "branch -a"                  "git branch -a"
allowed "branch --show-current"      "git branch --show-current"
allowed "branch -d"                  "git branch -d Old_Name"
allowed "branch -D"                  "git branch -D Old_Name"
allowed "branch -m"                  "git branch -m Old_Name"
allowed "push HEAD"                  "git push -u origin HEAD"
allowed "push with no refspec"       "git push"
allowed "push --delete"              "git push origin --delete Old_Name"
allowed "push a tag"                 "git push origin refs/tags/V1_0"
allowed "push --tags"                "git push --tags"
allowed "not git"                    "echo git switch -c a_b"
allowed "text that mentions it"      $'cat > f <<EOF\n1. `git switch -c a_b` is blocked\nEOF'
allowed "another tool entirely"      "make test"

echo "[allow and log] a name the shell has not expanded yet"
rm -f "$LOG"
allowed "variable"                   'N=a_b; git switch -c "$N"'
allowed "command substitution"       'git switch -c "$(cat name.txt)"'
allowed "backticks"                  'git switch -c `cat name.txt`'
LINES=$(wc -l < "$LOG" 2>/dev/null | tr -d ' ')
assert_eq "three lines logged" "3" "${LINES:-0}"
assert_has "log names the reason" "not expanded" "$(cat "$LOG" 2>/dev/null)"

echo "[cwd] a subdirectory resolves the same project config"
blocked "from sub/dir"               "git switch -c a_b" "$REPO/sub/dir"

echo "[fails closed] a configured platform pack that cannot be resolved blocks"
UNREG="$WORK/unregistered"
git init -q -b main "$UNREG"
mkdir -p "$UNREG/.ai"
printf 'version: 1\n\npacks:\n  platform: not-registered-platform\n' > "$UNREG/.ai/project-config.yaml"
blocked "unresolved pack, any name"  "git switch -c ok-name" "$UNREG"
assert_has "reason carries the check's line" "not-resolved: platform=not-registered-platform" "$ERR"

echo "[worktree] a linked worktree reads the main checkout's registry"
printf '.ai/run-context/\n.ai/logs/\n' > "$REPO/.gitignore"
git -C "$REPO" add .gitignore .ai/project-config.yaml
git -C "$REPO" -c user.name=t -c user.email=t@t commit -q -m config
git -C "$REPO" worktree add -q -b wt-base "$WORK/wt" 2>/dev/null
[ -f "$WORK/wt/.ai/project-config.yaml" ] && [ ! -e "$WORK/wt/.ai/run-context" ] \
  && ok "the worktree holds the config but no registry" || bad "worktree fixture is not as expected"
blocked "too long, from the worktree" "git switch -c feature-12345" "$WORK/wt"
assert_has "judged by the registered pack's rule" "too-long: branch=feature-12345" "$ERR"
allowed "passing name, from the worktree" "git switch -c ok-name" "$WORK/wt"

echo "[silent] a project with no config, and a path outside any repository"
mkdir -p "$WORK/other"
git init -q -b main "$WORK/other"
allowed "repository without config"  "git switch -c a_b" "$WORK/other"
allowed "no repository at all"       "git switch -c a_b" "$WORK"

echo "[silent] input that is not a Bash command"
ERR=$(printf '%s' '{"tool_name":"Read","tool_input":{"file_path":"x"}}' | bash "$HOOK" 2>&1); CODE=$?
assert_eq "Read call → exit 0" "0" "$CODE"
ERR=$(printf 'not json' | bash "$HOOK" 2>&1); CODE=$?
assert_eq "unparsable input → exit 0" "0" "$CODE"

echo "=== $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
