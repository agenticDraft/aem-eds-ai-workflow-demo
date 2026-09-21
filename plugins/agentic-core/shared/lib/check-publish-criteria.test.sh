#!/usr/bin/env bash
# Tests for check-publish-criteria.sh. Run with:
#   bash plugins/agentic-core/shared/lib/check-publish-criteria.test.sh
#
# No framework — exits 0 on success, 1 on first failure. Unlike
# check-plan-criteria.sh's static YAML fixtures, this checker reads live
# git state, so each case builds its own throwaway repo under
# ${TMPDIR:-/tmp} (never bare `mktemp`, matching every other *.test.sh in
# this directory) and removes it on exit via a trap, pass or fail.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/check-publish-criteria.sh"

FIXTURE_ROOTS=()
cleanup() {
  for d in "${FIXTURE_ROOTS[@]:-}"; do
    [[ -n "$d" && -d "$d" ]] && rm -rf "$d"
  done
}
trap cleanup EXIT

PASS=0
FAIL=0

assert_exit() {
  local desc="$1" expected="$2" actual="$3" output="$4"
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1))
    echo "  ok: $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc"
    echo "    expected exit=$expected, got exit=$actual"
    [[ -n "$output" ]] && echo "    output: $output"
  fi
}

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    PASS=$((PASS + 1))
    echo "  ok: $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc"
    echo "    expected output to contain: $needle"
    echo "    got: $haystack"
  fi
}

# Builds a bare "origin" plus a clone with origin/HEAD set, one commit on
# the default branch, checked out. Prints the clone's absolute path.
new_fixture() {
  local name="$1"
  local root
  root="$(mktemp -d "${TMPDIR:-/tmp}/check-publish-criteria-${name}.XXXXXX")"
  FIXTURE_ROOTS+=("$root")
  # The default branch is named explicitly at both ends. Left to the
  # environment, the bare repository's own HEAD is whatever that machine
  # configures as its initial branch, while the push below always creates
  # `main` — and on a machine where those two differ, `set-head -a` cannot
  # resolve a remote default at all, so every fixture built here ends up
  # without origin/HEAD and every case using one fails for a reason that has
  # nothing to do with what it was testing.
  git init --quiet --bare --initial-branch=main "$root/upstream.git" >/dev/null
  git clone --quiet "$root/upstream.git" "$root/work" >/dev/null 2>&1
  (
    cd "$root/work"
    git config user.email "t@example.com"
    git config user.name "t"
    echo "base" > README.md
    git add README.md
    git commit --quiet -m "initial"
    git push --quiet origin HEAD:main
    # Named rather than asked for (`-a`): this fixture built the remote, so
    # what its default branch is was decided here, not discovered.
    git remote set-head origin main >/dev/null
  ) >/dev/null 2>&1
  echo "$root/work"
}

echo "=== check-publish-criteria.sh tests ==="

echo "[accept] a committed change on a branch past the merge base"
WORK="$(new_fixture accept-committed)"
(
  cd "$WORK"
  git checkout --quiet -b task-branch
  echo "line2" >> README.md
  git add README.md
  git commit --quiet -m "task change"
)
OUT=$(bash "$CHECK" "$WORK" 2>&1); ST=$?
assert_exit "committed change accepted (exit 0)" 0 $ST "$OUT"
assert_contains "reports file count" "valid: publish (1 files changed)" "$OUT"

echo "[accept] a brand-new file nothing has 'git add'ed yet is also part of the change"
WORK="$(new_fixture accept-untracked)"
(
  cd "$WORK"
  git checkout --quiet -b task-branch
  echo "new content" > new-file.txt
)
OUT=$(bash "$CHECK" "$WORK" 2>&1); ST=$?
assert_exit "untracked-only new file accepted (exit 0)" 0 $ST "$OUT"
assert_contains "reports file count" "valid: publish (1 files changed)" "$OUT"

echo "[accept] an uncommitted edit is also part of the change under review"
WORK="$(new_fixture accept-uncommitted)"
(
  cd "$WORK"
  git checkout --quiet -b task-branch
  echo "uncommitted line" >> README.md
)
OUT=$(bash "$CHECK" "$WORK" 2>&1); ST=$?
assert_exit "uncommitted-only change accepted (exit 0)" 0 $ST "$OUT"
assert_contains "reports file count" "valid: publish (1 files changed)" "$OUT"

echo "[reject] nothing changed since the merge base"
WORK="$(new_fixture reject-empty)"
(
  cd "$WORK"
  git checkout --quiet -b task-branch
)
OUT=$(bash "$CHECK" "$WORK" 2>&1); ST=$?
assert_exit "empty change rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason says no change" "no change to review" "$OUT"

echo "[reject] the diff includes a path .gitignore marks never-tracked"
WORK="$(new_fixture reject-ignored)"
(
  cd "$WORK"
  git checkout --quiet -b task-branch
  echo ".ai/credentials" > .gitignore
  git add .gitignore
  git commit --quiet -m "add gitignore"
  mkdir -p .ai
  echo "SECRET=1" > .ai/credentials
  git add -f .ai/credentials
)
OUT=$(bash "$CHECK" "$WORK" 2>&1); ST=$?
assert_exit "forced-add of ignored path rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the path" "'.ai/credentials'" "$OUT"
assert_contains "reason explains why" "never publish" "$OUT"

echo "[accept] an ordinary tracked file with the same name pattern as no .gitignore rule is unaffected"
WORK="$(new_fixture accept-with-gitignore)"
(
  cd "$WORK"
  git checkout --quiet -b task-branch
  echo "*.log" > .gitignore
  git add .gitignore
  git commit --quiet -m "add gitignore"
  echo "line2" >> README.md
  git add README.md
)
OUT=$(bash "$CHECK" "$WORK" 2>&1); ST=$?
assert_exit "unrelated .gitignore rule does not block a clean change (exit 0)" 0 $ST "$OUT"

echo "[accept] a clean change is unaffected by which directory the checker's own process was started from (G96)"
WORK="$(new_fixture g96-cwd-independence)"
(
  cd "$WORK"
  git checkout --quiet -b task-branch
  echo "sub/artifacts/" > .gitignore
  git add .gitignore
  git commit --quiet -m "add gitignore"
  mkdir -p artifacts sub
  echo "line2" >> README.md
  echo "not a secret" > artifacts/note.txt
  git add README.md artifacts/note.txt
)
# check-ignore resolves a relative pathspec against the calling process's
# own cwd, not --work-tree — invoking from "$WORK/sub" reproduces exactly
# the failure a linked worktree nested under the project root hit live: a
# real, unignored path ("artifacts/note.txt") got tested as though it were
# "sub/artifacts/note.txt", which the .gitignore rule above does match.
OUT=$(cd "$WORK/sub" && bash "$CHECK" "$WORK" 2>&1); ST=$?
assert_exit "clean change accepted regardless of the checker's own cwd (exit 0)" 0 $ST "$OUT"
assert_contains "reports file count" "valid: publish (3 files changed)" "$OUT"

echo "[accept] a linked worktree is a reviewable project root, not a usage error (G89)"
WORK="$(new_fixture g89-worktree-root)"
(
  cd "$WORK"
  git worktree add --quiet -b wt-branch ../wt >/dev/null 2>&1
  cd ../wt
  echo "worktree line" >> README.md
  git add README.md
) >/dev/null 2>&1
# A linked worktree's .git is a file holding a gitdir pointer, not a
# directory — testing for a directory rejected every worktree root before
# this check asked git for the real path instead.
WT="$(cd "$WORK/../wt" && pwd)"
OUT=$(bash "$CHECK" "$WT" 2>&1); ST=$?
assert_exit "worktree root reaches a real verdict, not exit 2" 0 $ST "$OUT"
assert_contains "reports the worktree's own change" "valid: publish (1 files changed)" "$OUT"

echo "[accept] an untracked file matching .gitignore is not part of the change at all"
WORK="$(new_fixture accept-untracked-ignored)"
(
  cd "$WORK"
  echo "*.log" > .gitignore
  git add .gitignore
  git commit --quiet -m "add gitignore"
  git push --quiet origin HEAD:main
  git checkout --quiet -b task-branch
  echo "line2" >> README.md
  git add README.md
  echo "scratch" > debug.log
)
OUT=$(bash "$CHECK" "$WORK" 2>&1); ST=$?
assert_exit "ignored untracked file does not block a clean change (exit 0)" 0 $ST "$OUT"
assert_contains "counts only the real change, not the ignored scratch file" "valid: publish (1 files changed)" "$OUT"

echo "[usage] no argument"
OUT=$(bash "$CHECK" 2>&1); ST=$?
assert_exit "no arg -> usage error (exit 2)" 2 $ST "$OUT"

echo "[usage] project root not found"
OUT=$(bash "$CHECK" "/nonexistent/path/does-not-exist" 2>&1); ST=$?
assert_exit "missing path -> usage error (exit 2)" 2 $ST "$OUT"

echo "[usage] not a git checkout"
NOTGIT="$(mktemp -d "${TMPDIR:-/tmp}/check-publish-criteria-notgit.XXXXXX")"
FIXTURE_ROOTS+=("$NOTGIT")
OUT=$(bash "$CHECK" "$NOTGIT" 2>&1); ST=$?
assert_exit "non-git directory -> usage error (exit 2)" 2 $ST "$OUT"

echo "[usage] origin/HEAD not set"
NOHEAD="$(mktemp -d "${TMPDIR:-/tmp}/check-publish-criteria-nohead.XXXXXX")"
FIXTURE_ROOTS+=("$NOHEAD")
(
  cd "$NOHEAD"
  git init --quiet >/dev/null
  git config user.email "t@example.com"
  git config user.name "t"
  echo "base" > README.md
  git add README.md
  git commit --quiet -m "initial"
) >/dev/null 2>&1
OUT=$(bash "$CHECK" "$NOHEAD" 2>&1); ST=$?
assert_exit "no origin/HEAD -> usage error (exit 2)" 2 $ST "$OUT"
assert_contains "reason names origin/HEAD" "origin/HEAD" "$OUT"

echo "[usage] detached HEAD in the project root"
WORK="$(new_fixture detached)"
(
  cd "$WORK"
  git checkout --quiet --detach >/dev/null 2>&1
)
OUT=$(bash "$CHECK" "$WORK" 2>&1); ST=$?
assert_exit "detached HEAD -> usage error (exit 2)" 2 $ST "$OUT"
assert_contains "reason says detached" "detached HEAD" "$OUT"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
