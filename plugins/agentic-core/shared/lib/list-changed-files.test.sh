#!/usr/bin/env bash
# Tests for list-changed-files.sh. Run with:
#   bash plugins/agentic-core/shared/lib/list-changed-files.test.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIST="$SCRIPT_DIR/list-changed-files.sh"

PASS=0
FAIL=0

check() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1)); echo "  ok: $desc"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: $desc"
    echo "    expected: $expected"
    echo "    actual:   $actual"
  fi
}

TMP="$(mktemp -d "${TMPDIR:-/tmp}/list-changed-files.XXXXXX")" || { echo "cannot create a temp dir" >&2; exit 2; }
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "cannot create a temp dir" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

# A remote with a default branch, and a clone working on a branch of its own.
git init -q --bare "$TMP/remote.git"
git -C "$TMP/remote.git" symbolic-ref HEAD refs/heads/main
git init -q -b main "$TMP/seed"
printf 'a\n' > "$TMP/seed/tracked.txt"
printf 'x\n' > "$TMP/seed/.gitignore"
git -C "$TMP/seed" add -A && git -C "$TMP/seed" -c user.email=t@t -c user.name=t commit -q -m base
git -C "$TMP/seed" push -q "$TMP/remote.git" main
git clone -q "$TMP/remote.git" "$TMP/work"
ROOT="$TMP/work"
git -C "$ROOT" switch -q -c item-1

echo "=== list-changed-files.sh tests ==="

echo "[none] a branch with nothing changed"
check "prints nothing" "" "$(bash "$LIST" "$ROOT")"

echo "[changed] a committed edit, an uncommitted edit and a new file"
printf 'b\n' >> "$ROOT/tracked.txt"
git -C "$ROOT" -c user.email=t@t -c user.name=t commit -qam edit
mkdir -p "$ROOT/src/new"
printf 'c\n' > "$ROOT/src/new/new.css"
printf 'ignored\n' > "$ROOT/x"
check "the union, sorted, without ignored files" "$(printf 'src/new/new.css\ntracked.txt')" "$(bash "$LIST" "$ROOT")"

echo "[env] no origin/HEAD"
git -C "$ROOT" remote set-head origin -d
OUT="$(bash "$LIST" "$ROOT" 2>&1)"; ST=$?
check "exits 2" "2" "$ST"
check "names the remedy" "1" "$(grep -c "git remote set-head origin -a" <<< "$OUT")"

echo "[usage] no argument"
bash "$LIST" >/dev/null 2>&1; check "exits 2" "2" "$?"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
