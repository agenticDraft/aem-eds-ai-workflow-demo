#!/usr/bin/env bash
# Tests for check-tree-clean.sh. Run with:
#   bash plugins/agentic-core/shared/lib/check-tree-clean.test.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="$SCRIPT_DIR/check-tree-clean.sh"
LIST="$SCRIPT_DIR/list-changed-files.sh"

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); echo "  ok: $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; shift; for l in "$@"; do echo "    $l"; done; }
check() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then ok "$desc"; else bad "$desc" "expected: $expected" "actual:   $actual"; fi
}

TMP="$(mktemp -d "${TMPDIR:-/tmp}/check-tree-clean.XXXXXX")" || { echo "cannot create a temp dir" >&2; exit 2; }
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "cannot create a temp dir" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

commit() { git -C "$1" -c user.email=t@t -c user.name=t commit -q "${@:2}"; }

# A remote with a default branch, and a fresh clone of it on that branch.
git init -q --bare "$TMP/remote.git"
git -C "$TMP/remote.git" symbolic-ref HEAD refs/heads/main
git init -q -b main "$TMP/seed"
printf 'a\n' > "$TMP/seed/tracked.txt"
printf 'b\n' > "$TMP/seed/other.txt"
printf 's\n' > "$TMP/seed/my file.txt"
printf 'ignored.log\n' > "$TMP/seed/.gitignore"
git -C "$TMP/seed" add -A && commit "$TMP/seed" -m base
git -C "$TMP/seed" push -q "$TMP/remote.git" main

fresh_clone() {
  rm -rf "$TMP/work"
  git clone -q "$TMP/remote.git" "$TMP/work"
  ROOT="$TMP/work"
}

echo "=== check-tree-clean.sh tests ==="

echo "[clean] a fresh clone on the default branch"
fresh_clone
OUT="$(bash "$GUARD" "$ROOT" 2>&1)"; ST=$?
check "exit 0" "0" "$ST"
check "reports clean" "clean: no change and no untracked path" "$OUT"

echo "[ignored] a file the ignore rules exclude is not a change"
fresh_clone
printf 'x\n' > "$ROOT/ignored.log"
OUT="$(bash "$GUARD" "$ROOT" 2>&1)"; ST=$?
check "exit 0" "0" "$ST"
check "reports clean" "clean: no change and no untracked path" "$OUT"

# refused <desc> <expected changed: paths, newline-separated>
refused() {
  local desc="$1" expected="$2" n
  OUT="$(bash "$GUARD" "$ROOT" 2>&1)"; ST=$?
  n="$(printf '%s\n' "$expected" | grep -c .)"
  check "$desc -> exit 1" "1" "$ST"
  check "$desc -> the count line" "refused: $n paths changed before this run" "$(head -1 <<< "$OUT")"
  check "$desc -> every path named" "$(printf '%s\n' "$expected" | sed 's/^/changed: /')" "$(tail -n +2 <<< "$OUT")"
}

echo "[modified] a tracked file edited and not staged"
fresh_clone
printf 'edit\n' >> "$ROOT/tracked.txt"
refused "modified" "tracked.txt"

echo "[staged] a new file added to the index"
fresh_clone
printf 'n\n' > "$ROOT/staged.txt"
git -C "$ROOT" add staged.txt
refused "staged" "staged.txt"

echo "[untracked] a new file nobody added"
fresh_clone
mkdir -p "$ROOT/drafts"
printf 'u\n' > "$ROOT/drafts/new.html"
refused "untracked" "drafts/new.html"

echo "[deleted] a tracked file removed from the working tree"
fresh_clone
rm "$ROOT/other.txt"
refused "deleted" "other.txt"

echo "[spaces] paths with spaces are named whole"
fresh_clone
printf 'edit\n' >> "$ROOT/my file.txt"
mkdir -p "$ROOT/a dir"
printf 'u\n' > "$ROOT/a dir/b c.txt"
refused "spaces" "$(printf 'a dir/b c.txt\nmy file.txt')"

echo "[several] every kind at once, sorted, each named once"
fresh_clone
printf 'edit\n' >> "$ROOT/tracked.txt"
git -C "$ROOT" add tracked.txt
printf 'again\n' >> "$ROOT/tracked.txt"
rm "$ROOT/other.txt"
printf 'u\n' > "$ROOT/zz-new.txt"
printf 'x\n' > "$ROOT/ignored.log"
refused "several" "$(printf 'other.txt\ntracked.txt\nzz-new.txt')"

echo "[ahead] a commit not on origin's default branch is refused too: the gate counts it"
fresh_clone
git -C "$ROOT" switch -q -c item-1
printf 'committed\n' >> "$ROOT/tracked.txt"
commit "$ROOT" -am "on the branch only"
refused "ahead" "tracked.txt"

echo "[agree] the refused set is exactly the publish gate's change set"
fresh_clone
printf 'edit\n' >> "$ROOT/tracked.txt"
rm "$ROOT/other.txt"
printf 'u\n' > "$ROOT/a b.txt"
OUT="$(bash "$GUARD" "$ROOT" 2>&1)"
check "changed: lines == list-changed-files.sh" "$(bash "$LIST" "$ROOT")" "$(tail -n +2 <<< "$OUT" | sed 's/^changed: //')"

echo "[read-only] a refusal changes nothing in the tree"
BEFORE="$(git -C "$ROOT" status --porcelain=v1 -uall)"
bash "$GUARD" "$ROOT" >/dev/null 2>&1
check "git status identical before and after" "$BEFORE" "$(git -C "$ROOT" status --porcelain=v1 -uall)"

echo "[env] the change set cannot be computed"
fresh_clone
git -C "$ROOT" remote set-head origin -d
OUT="$(bash "$GUARD" "$ROOT" 2>&1)"; ST=$?
check "no origin/HEAD -> exit 2" "2" "$ST"
check "passes the remedy through" "1" "$(grep -c "git remote set-head origin -a" <<< "$OUT")"
OUT="$(bash "$GUARD" "$TMP" 2>&1)"; ST=$?
check "not a checkout -> exit 2" "2" "$ST"

echo "[usage] errors"
bash "$GUARD" >/dev/null 2>&1; check "no argument -> exit 2" "2" "$?"
bash "$GUARD" "$TMP/does-not-exist" >/dev/null 2>&1; check "missing root -> exit 2" "2" "$?"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
