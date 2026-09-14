#!/usr/bin/env bash
# Tests for check-shallow-clone.sh. Run with:
#   bash plugins/agentic-core/shared/lib/check-shallow-clone.test.sh
#
# No framework — exits 0 on success, 1 on first failure. This checker
# reads live git state, so each case builds its own throwaway repo under
# ${TMPDIR:-/tmp} (never bare `mktemp`, matching every other *.test.sh in
# this directory) and removes it on exit via a trap, pass or fail.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/check-shallow-clone.sh"

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

# Builds a full (non-shallow) repo with two commits. Prints its absolute path.
new_full_repo() {
  local name="$1"
  local dir
  dir="$(mktemp -d "${TMPDIR:-/tmp}/check-shallow-clone-${name}.XXXXXX")"
  FIXTURE_ROOTS+=("$dir")
  (
    cd "$dir"
    git init --quiet >/dev/null
    git config user.email "t@example.com"
    git config user.name "t"
    echo "base" > README.md
    git add README.md
    git commit --quiet -m "initial"
    echo "line2" >> README.md
    git add README.md
    git commit --quiet -m "second"
  ) >/dev/null 2>&1
  echo "$dir"
}

echo "=== check-shallow-clone.sh tests ==="

echo "[ok] a full clone with real history"
SRC="$(new_full_repo full)"
OUT=$(bash "$CHECK" "$SRC" 2>&1); ST=$?
assert_exit "full clone accepted (exit 0)" 0 $ST "$OUT"
assert_contains "reports ok" "ok: full clone" "$OUT"

echo "[permanent-abort] a --depth 1 clone of that same repo"
SRC="$(new_full_repo shallow-source)"
SHALLOW_DIR="$(mktemp -d "${TMPDIR:-/tmp}/check-shallow-clone-shallow.XXXXXX")"
FIXTURE_ROOTS+=("$SHALLOW_DIR")
# `--depth` is silently ignored for a plain local-path clone (git prints
# "warning: --depth is ignored in local clones; use file:// instead.") —
# the `file://` transport is what actually negotiates a shallow clone.
git clone --quiet --depth 1 "file://$SRC" "$SHALLOW_DIR/clone" >/dev/null 2>&1
OUT=$(bash "$CHECK" "$SHALLOW_DIR/clone" 2>&1); ST=$?
assert_exit "shallow clone aborted (exit 1)" 1 $ST "$OUT"
assert_contains "labels the abort permanent" "permanent-abort" "$OUT"
assert_contains "names the remedy" "git fetch --unshallow" "$OUT"

echo "[usage] no argument"
OUT=$(bash "$CHECK" 2>&1); ST=$?
assert_exit "no arg -> usage error (exit 2)" 2 $ST "$OUT"

echo "[usage] project root not found"
OUT=$(bash "$CHECK" "/nonexistent/path/does-not-exist" 2>&1); ST=$?
assert_exit "missing path -> usage error (exit 2)" 2 $ST "$OUT"

echo "[usage] not a git checkout"
NOTGIT="$(mktemp -d "${TMPDIR:-/tmp}/check-shallow-clone-notgit.XXXXXX")"
FIXTURE_ROOTS+=("$NOTGIT")
OUT=$(bash "$CHECK" "$NOTGIT" 2>&1); ST=$?
assert_exit "non-git directory -> usage error (exit 2)" 2 $ST "$OUT"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
