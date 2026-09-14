#!/usr/bin/env bash
# Tests for check-auto-fix-eligibility.sh. Run with:
#   bash plugins/agentic-core/shared/lib/check-auto-fix-eligibility.test.sh
#
# No framework — exits 0 on success, 1 on first failure. This checker
# reads live git state, so each case builds its own throwaway repo under
# ${TMPDIR:-/tmp} (never bare `mktemp`, matching every other *.test.sh in
# this directory) and removes it on exit via a trap, pass or fail.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/check-auto-fix-eligibility.sh"

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

# Builds an empty repo. Prints its absolute path.
new_repo() {
  local name="$1"
  local dir
  dir="$(mktemp -d "${TMPDIR:-/tmp}/check-auto-fix-eligibility-${name}.XXXXXX")"
  FIXTURE_ROOTS+=("$dir")
  (
    cd "$dir"
    git init --quiet >/dev/null
    git config user.email "t@example.com"
    git config user.name "t"
  ) >/dev/null 2>&1
  echo "$dir"
}

echo "=== check-auto-fix-eligibility.sh tests ==="

echo "[eligible] a file with exactly one commit — the import itself"
REPO="$(new_repo untouched)"
(
  cd "$REPO"
  echo "imported" > imported-only.css
  git add imported-only.css
  git commit --quiet -m "import"
)
OUT=$(bash "$CHECK" "$REPO" "imported-only.css" 2>&1); ST=$?
assert_exit "single-commit file is eligible (exit 0)" 0 $ST "$OUT"
assert_contains "reports eligible" "eligible: imported-only.css" "$OUT"

echo "[demoted] the same file, once edited and committed a second time"
(
  cd "$REPO"
  echo "edited by a human" >> imported-only.css
  git add imported-only.css
  git commit --quiet -m "human edit after import"
)
OUT=$(bash "$CHECK" "$REPO" "imported-only.css" 2>&1); ST=$?
assert_exit "twice-committed file is demoted (exit 1)" 1 $ST "$OUT"
assert_contains "reports demoted with the commit count" "demoted: imported-only.css (2 commits)" "$OUT"

echo "[demoted] a path with no commits at all"
REPO2="$(new_repo never-committed)"
(
  cd "$REPO2"
  echo "base" > README.md
  git add README.md
  git commit --quiet -m "initial"
)
OUT=$(bash "$CHECK" "$REPO2" "never-existed.css" 2>&1); ST=$?
assert_exit "zero-commit path is demoted (exit 1)" 1 $ST "$OUT"
assert_contains "reports demoted with zero commits" "demoted: never-existed.css (0 commits)" "$OUT"

echo "[mixed] several paths in one invocation, order preserved"
REPO3="$(new_repo mixed)"
(
  cd "$REPO3"
  echo "a" > a.css
  echo "b" > b.css
  git add a.css b.css
  git commit --quiet -m "import both"
  echo "a edited" >> a.css
  git add a.css
  git commit --quiet -m "human edit of a"
)
OUT=$(bash "$CHECK" "$REPO3" "a.css" "b.css" 2>&1); ST=$?
assert_exit "at least one demoted -> exit 1" 1 $ST "$OUT"
assert_contains "a.css demoted" "demoted: a.css (2 commits)" "$OUT"
assert_contains "b.css still eligible" "eligible: b.css" "$OUT"

echo "[usage] no arguments"
OUT=$(bash "$CHECK" 2>&1); ST=$?
assert_exit "no args -> usage error (exit 2)" 2 $ST "$OUT"

echo "[usage] project root not found"
OUT=$(bash "$CHECK" "/nonexistent/path/does-not-exist" "some.css" 2>&1); ST=$?
assert_exit "missing root -> usage error (exit 2)" 2 $ST "$OUT"

echo "[usage] not a git checkout"
NOTGIT="$(mktemp -d "${TMPDIR:-/tmp}/check-auto-fix-eligibility-notgit.XXXXXX")"
FIXTURE_ROOTS+=("$NOTGIT")
OUT=$(bash "$CHECK" "$NOTGIT" "some.css" 2>&1); ST=$?
assert_exit "non-git directory -> usage error (exit 2)" 2 $ST "$OUT"

echo "[usage] project root given but no path"
REPO4="$(new_repo no-path)"
OUT=$(bash "$CHECK" "$REPO4" 2>&1); ST=$?
assert_exit "root with no path -> usage error (exit 2)" 2 $ST "$OUT"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
