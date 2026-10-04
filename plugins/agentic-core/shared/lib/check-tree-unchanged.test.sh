#!/usr/bin/env bash
# Tests for check-tree-unchanged.sh. Run with:
#   bash plugins/agentic-core/shared/lib/check-tree-unchanged.test.sh
#
# No framework — exits 0 when every case passes, 1 otherwise. This check
# reads live git state, so each case builds its own throwaway repo under
# ${TMPDIR:-/tmp} (never bare `mktemp`) and removes it on exit via a trap.
#
# The allowed paths below are the two a gate writes (shared/gate-contract.md).
# The fixture repos do not ignore them, so they show up as untracked files —
# the case the allowlist exists for.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/check-tree-unchanged.sh"

REPORT=".ai/run-context/plan-gate-report.md"
ENVELOPE=".ai/run-context/envelope-plan-gate.txt"
SNAP_NAME="tree-before-plan-gate.txt"

FIXTURE_ROOTS=()
cleanup() {
  for d in "${FIXTURE_ROOTS[@]:-}"; do
    [[ -n "$d" && -d "$d" ]] && rm -rf "$d"
  done
}
trap cleanup EXIT

PASS=0
FAIL=0

ok()   { PASS=$((PASS + 1)); echo "  ok: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; shift; for l in "$@"; do echo "    $l"; done; }

assert_exit() {
  local desc="$1" expected="$2" actual="$3" output="$4"
  if [[ "$expected" == "$actual" ]]; then ok "$desc"
  else fail "$desc" "expected exit=$expected, got exit=$actual" "output: $output"; fi
}

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then ok "$desc"
  else fail "$desc" "expected output to contain: $needle" "got: $haystack"; fi
}

assert_not_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if [[ "$haystack" != *"$needle"* ]]; then ok "$desc"
  else fail "$desc" "expected output NOT to contain: $needle" "got: $haystack"; fi
}

# A repo with one commit: a.txt, dir/b.txt, and "with space.txt".
# Prints its absolute path.
new_repo() {
  local dir
  dir="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/check-tree-unchanged-$1.XXXXXX")" && pwd -P)"
  FIXTURE_ROOTS+=("$dir")
  (
    cd "$dir"
    git init --quiet -b main >/dev/null
    git config user.email t@example.invalid
    git config user.name t
    git config commit.gpgsign false
    mkdir -p dir .ai/run-context
    echo a >a.txt
    echo b >dir/b.txt
    echo s >"with space.txt"
    git add a.txt dir/b.txt "with space.txt"
    git commit --quiet -m init
  )
  echo "$dir"
}

# snapshot, then run a mutation in the repo, then compare. Sets OUT and CODE.
run_case() {
  local repo="$1" mutation="$2"
  shift 2
  local snap="$repo/.ai/run-context/$SNAP_NAME"
  bash "$CHECK" snapshot "$repo" "$snap" >/dev/null 2>&1
  (cd "$repo" && eval "$mutation")
  OUT="$(bash "$CHECK" compare "$repo" "$snap" "$@" 2>&1)"
  CODE=$?
}

echo "check-tree-unchanged.sh"

echo "# no change"
R="$(new_repo none)"
run_case "$R" ":" "$REPORT" "$ENVELOPE"
assert_exit "no change → exit 0" 0 "$CODE" "$OUT"
assert_contains "no change → pass line" "pass:" "$OUT"

echo "# only the gate's own two files"
R="$(new_repo own)"
run_case "$R" "echo r >'$REPORT'; echo e >'$ENVELOPE'" "$REPORT" "$ENVELOPE"
assert_exit "report + envelope written → exit 0" 0 "$CODE" "$OUT"
assert_contains "report + envelope written → pass line" "pass:" "$OUT"

echo "# the snapshot file itself is never a change"
R="$(new_repo self)"
run_case "$R" ":"
assert_exit "snapshot file under root, no allowlist → exit 0" 0 "$CODE" "$OUT"

echo "# a tracked file modified"
R="$(new_repo tracked)"
run_case "$R" "echo x >>a.txt" "$REPORT" "$ENVELOPE"
assert_exit "tracked edit → exit 1" 1 "$CODE" "$OUT"
assert_contains "tracked edit → names the path" "changed: a.txt" "$OUT"

echo "# a tracked file deleted"
R="$(new_repo deleted)"
run_case "$R" "rm dir/b.txt" "$REPORT" "$ENVELOPE"
assert_exit "tracked delete → exit 1" 1 "$CODE" "$OUT"
assert_contains "tracked delete → names the path" "changed: dir/b.txt" "$OUT"

echo "# an untracked file created"
R="$(new_repo untracked)"
run_case "$R" "mkdir -p new/deep; echo n >new/deep/c.txt" "$REPORT" "$ENVELOPE"
assert_exit "untracked file → exit 1" 1 "$CODE" "$OUT"
assert_contains "untracked file → names the file, not its directory" \
  "changed: new/deep/c.txt" "$OUT"

echo "# a path with a space"
R="$(new_repo space)"
run_case "$R" "echo y >>'with space.txt'" "$REPORT" "$ENVELOPE"
assert_exit "space in path → exit 1" 1 "$CODE" "$OUT"
assert_contains "space in path → names the whole path" "changed: with space.txt" "$OUT"

echo "# the gate's files plus one other change"
R="$(new_repo mixed)"
run_case "$R" "echo r >'$REPORT'; echo e >'$ENVELOPE'; echo x >>a.txt" "$REPORT" "$ENVELOPE"
assert_exit "own files + tracked edit → exit 1" 1 "$CODE" "$OUT"
assert_contains "own files + tracked edit → names the other path" "changed: a.txt" "$OUT"
assert_not_contains "own files + tracked edit → does not name the report" "$REPORT" "$OUT"

echo "# already dirty before the stage (the change under review)"
R="$(new_repo dirty-kept)"
(cd "$R" && echo pre >>a.txt && echo u >untracked-before.txt)
run_case "$R" ":" "$REPORT" "$ENVELOPE"
assert_exit "pre-existing edits left alone → exit 0" 0 "$CODE" "$OUT"

R="$(new_repo dirty-edited)"
(cd "$R" && echo pre >>a.txt)
run_case "$R" "echo more >>a.txt" "$REPORT" "$ENVELOPE"
assert_exit "pre-existing edit edited again → exit 1" 1 "$CODE" "$OUT"
assert_contains "pre-existing edit edited again → names the path" "changed: a.txt" "$OUT"

R="$(new_repo dirty-reverted)"
(cd "$R" && echo pre >>a.txt)
run_case "$R" "git checkout --quiet -- a.txt" "$REPORT" "$ENVELOPE"
assert_exit "pre-existing edit reverted → exit 1" 1 "$CODE" "$OUT"
assert_contains "pre-existing edit reverted → names the path" "changed: a.txt" "$OUT"

R="$(new_repo staged)"
(cd "$R" && echo pre >>a.txt)
run_case "$R" "git add a.txt" "$REPORT" "$ENVELOPE"
assert_exit "pre-existing edit staged → exit 1" 1 "$CODE" "$OUT"
assert_contains "pre-existing edit staged → names the path" "changed: a.txt" "$OUT"

echo "# HEAD moves"
R="$(new_repo commit)"
(cd "$R" && echo pre >>a.txt)
run_case "$R" "git commit --quiet -am gate-commit" "$REPORT" "$ENVELOPE"
assert_exit "a commit → exit 1" 1 "$CODE" "$OUT"
assert_contains "a commit → says HEAD moved" "changed: HEAD" "$OUT"

R="$(new_repo switch)"
run_case "$R" "git switch --quiet -c other" "$REPORT" "$ENVELOPE"
assert_exit "a branch switch → exit 1" 1 "$CODE" "$OUT"
assert_contains "a branch switch → says HEAD moved" "changed: HEAD" "$OUT"

echo "# an allowed path that is tracked"
R="$(new_repo tracked-allowed)"
(cd "$R" && echo r >"$REPORT" && git add "$REPORT" && git commit --quiet -m report)
run_case "$R" "echo r2 >>'$REPORT'" "$REPORT" "$ENVELOPE"
assert_exit "tracked allowed path edited → exit 0" 0 "$CODE" "$OUT"

echo "# a linked worktree as the project root"
R="$(new_repo linked)"
W="$R-wt"
FIXTURE_ROOTS+=("$W")
(cd "$R" && git worktree add --quiet "$W" -b wt >/dev/null 2>&1)
mkdir -p "$W/.ai/run-context"
run_case "$W" "echo x >>a.txt" "$REPORT" "$ENVELOPE"
assert_exit "linked worktree edit → exit 1" 1 "$CODE" "$OUT"
assert_contains "linked worktree edit → names the path" "changed: a.txt" "$OUT"

echo "# the guard is the only consequence of isolation"
# The driver's text around this guard and the gate contract both describe an
# unisolated gate. Neither may tie a verdict to the isolation line: the verdict
# is the review's, and this guard alone fails a gate that wrote elsewhere.
DRIVER="$SCRIPT_DIR/../../skills/run-route/SKILL.md"
CONTRACT="$SCRIPT_DIR/../gate-contract.md"
CAPS=0
for f in "$DRIVER" "$CONTRACT"; do
  n="$(grep -i -B1 -A1 'isolat' "$f" | grep -c -E 'at most `?(warn|pass)`?|capped|lowered to')"
  [[ "$n" -gt 0 ]] && { CAPS=$((CAPS + n)); echo "    cap in $(basename "$f")"; }
done
if [[ "$CAPS" -eq 0 ]]; then ok "no text caps a gate's verdict on its isolation"
else fail "no text caps a gate's verdict on its isolation" "found $CAPS capping line(s)"; fi

echo "# usage errors"
OUT="$(bash "$CHECK" 2>&1)"; CODE=$?
assert_exit "no arguments → exit 2" 2 "$CODE" "$OUT"
OUT="$(bash "$CHECK" frobnicate "$R" x 2>&1)"; CODE=$?
assert_exit "unknown subcommand → exit 2" 2 "$CODE" "$OUT"
NOT_GIT="$(mktemp -d "${TMPDIR:-/tmp}/check-tree-unchanged-notgit.XXXXXX")"
FIXTURE_ROOTS+=("$NOT_GIT")
OUT="$(bash "$CHECK" snapshot "$NOT_GIT" "$NOT_GIT/s.txt" 2>&1)"; CODE=$?
assert_exit "snapshot outside a git checkout → exit 2" 2 "$CODE" "$OUT"
OUT="$(bash "$CHECK" compare "$R" "$R/.ai/run-context/missing.txt" 2>&1)"; CODE=$?
assert_exit "compare with a missing snapshot → exit 2" 2 "$CODE" "$OUT"
OUT="$(bash "$CHECK" snapshot "$R/does-not-exist" "$R/s.txt" 2>&1)"; CODE=$?
assert_exit "snapshot of a missing root → exit 2" 2 "$CODE" "$OUT"

echo
echo "=== $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
