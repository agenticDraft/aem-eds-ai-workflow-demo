#!/usr/bin/env bash
# check-role-operations-read.test.sh — the pack's own skills read the
# role-operations contract, and a copy made to break one is caught.
#
# Usage:
#   bash check-role-operations-read.test.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/check-role-operations-read.sh"
SKILLS="$SCRIPT_DIR/../../skills"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/check-role-operations-read.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0

expect() {
  local desc="$1" want_exit="$2" want_text="$3" dir="$4" out rc
  out=$(bash "$CHECK" "$dir" 2>&1); rc=$?
  if [ "$rc" -eq "$want_exit" ] && [[ "$out" == *"$want_text"* ]]; then
    echo "  ok: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    echo "    expected exit=$want_exit containing: $want_text"
    echo "    got exit=$rc: $out"
    FAIL=$((FAIL + 1))
  fi
}

echo "# the pack's own skills"
expect "every stage naming the contract reads it" 0 "valid: role-operations read (2 stages)" "$SKILLS"

echo "# a stage that only names the contract"
mkdir -p "$WORK/names/stage-a"
printf '%s\n' '# stage-a' '' 'Every call goes through the skill (`../shared/role-operations.md`).' \
  > "$WORK/names/stage-a/SKILL.md"
expect "a pointer alone is refused" 1 "missing: stage-a" "$WORK/names"

echo "# a stage with the read step"
mkdir -p "$WORK/reads/stage-b"
printf '%s\n' '# stage-b' '' '1. Read `../shared/role-operations.md` before the first call.' \
  > "$WORK/reads/stage-b/SKILL.md"
expect "a numbered read step passes" 0 "valid: role-operations read (1 stages)" "$WORK/reads"

echo "# a stage that never names the contract"
mkdir -p "$WORK/none/stage-c"
printf '%s\n' '# stage-c' '' 'No provider calls.' > "$WORK/none/stage-c/SKILL.md"
expect "a stage without operations is not checked" 0 "valid: role-operations read (0 stages)" "$WORK/none"

echo "# usage errors"
expect "no argument" 2 "usage:" ""
expect "a missing directory" 2 "usage:" "$WORK/absent"

echo
echo "=== $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
