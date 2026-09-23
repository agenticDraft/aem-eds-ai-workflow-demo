#!/usr/bin/env bash
# Tests for create-branch.sh. Run with:
#   bash plugins/github/skills/create-branch/scripts/create-branch.test.sh
#
# No framework — exits 0 on success, 1 on first failure.
#
# Nothing here touches GitHub. `origin` is a local bare repository, so fetch,
# ls-remote and push are real git operations against a real remote; only `gh`
# is stubbed, because the script uses it for two facts (is auth present, what
# is the default branch) rather than for any operation on the repository.
#
# The case that matters is `base is the current branch when HEAD is not the
# default branch`. The script used to resolve its base from the repository's
# default branch unconditionally, so a route run started on a feature branch
# checked the working tree out to origin/main and silently discarded the
# unmerged work it was meant to be running.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/create-branch.sh"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/create-branch.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); echo "  ok: $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; shift; for l in "$@"; do echo "    $l"; done; }

# A `gh` that answers the only two questions create-branch.sh asks it.
mkdir -p "$WORK/bin"
cat > "$WORK/bin/gh" <<'GH'
#!/usr/bin/env bash
case "${1:-}" in
  auth) exit 0 ;;
  repo) echo main ;;
  *) exit 1 ;;
esac
GH
chmod +x "$WORK/bin/gh"
export PATH="$WORK/bin:$PATH"

# fresh <name> — a repo with one commit on main, pushed to its own bare origin.
# Echoes the repo path.
fresh() {
  local name="$1" remote="$WORK/$1-remote.git" repo="$WORK/$1"
  git init --bare -q "$remote"
  git init -q "$repo"
  (
    cd "$repo" || exit 1
    git config user.email test@example.invalid
    git config user.name "test"
    git symbolic-ref HEAD refs/heads/main
    echo base > file.txt
    git add file.txt
    git commit -q -m "base"
    git remote add origin "$remote"
    git push -q -u origin main
  ) >/dev/null 2>&1
  echo "$repo"
}

# commit_on <repo> <branch> <text> — new branch off HEAD with one extra commit.
commit_on() {
  (
    cd "$1" || exit 1
    git checkout -q -b "$2"
    echo "$3" > extra.txt
    git add extra.txt
    git commit -q -m "$3"
  ) >/dev/null 2>&1
}

echo "=== create-branch.sh tests ==="

echo "[base] HEAD is the default branch"
REPO="$(fresh default-head)"
OUT="$(cd "$REPO" && bash "$SCRIPT" feature-one 2>&1)"
EXPECTED="$(cd "$REPO" && git rev-parse origin/main)"
ACTUAL="$(cd "$REPO" && git rev-parse feature-one 2>/dev/null)"
if [[ "$OUT" == *"verdict: pass"* && "$EXPECTED" == "$ACTUAL" ]]; then
  ok "branches from origin/main, as the stale-local-main rule requires"
else
  bad "branches from origin/main, as the stale-local-main rule requires" \
      "expected $EXPECTED, got $ACTUAL" "output: $OUT"
fi

echo "[base] HEAD is NOT the default branch — the regression this test exists for"
REPO="$(fresh feature-head)"
commit_on "$REPO" my-work "unmerged work"
WORK_SHA="$(cd "$REPO" && git rev-parse my-work)"
OUT="$(cd "$REPO" && bash "$SCRIPT" feature-two 2>&1)"
ACTUAL="$(cd "$REPO" && git rev-parse feature-two 2>/dev/null)"
if [[ "$OUT" == *"verdict: pass"* && "$WORK_SHA" == "$ACTUAL" ]]; then
  ok "branches from current HEAD, carrying the unmerged commit"
else
  bad "branches from current HEAD, carrying the unmerged commit" \
      "expected $WORK_SHA (my-work), got $ACTUAL" "output: $OUT"
fi

echo "[base] the new branch actually contains the unmerged file"
if [[ -f "$REPO/extra.txt" ]]; then
  ok "extra.txt survives the checkout"
else
  bad "extra.txt survives the checkout" "the working tree was switched to a base without it"
fi

echo "[base] an explicit base argument still wins"
REPO="$(fresh explicit-base)"
commit_on "$REPO" my-work "unmerged work"
MAIN_SHA="$(cd "$REPO" && git rev-parse origin/main)"
OUT="$(cd "$REPO" && bash "$SCRIPT" feature-three main 2>&1)"
ACTUAL="$(cd "$REPO" && git rev-parse feature-three 2>/dev/null)"
if [[ "$OUT" == *"verdict: pass"* && "$MAIN_SHA" == "$ACTUAL" ]]; then
  ok "explicit base overrides the HEAD-aware default"
else
  bad "explicit base overrides the HEAD-aware default" \
      "expected $MAIN_SHA, got $ACTUAL" "output: $OUT"
fi

echo "[reject] a branch name git itself will not accept"
REPO="$(fresh bad-name)"
OUT="$(cd "$REPO" && bash "$SCRIPT" "--not-a-branch" 2>&1)"; ST=$?
if [[ "$OUT" == *"verdict: fail"* && "$ST" == 0 ]]; then
  ok "invalid ref name reports fail in an envelope, exit 0"
else
  bad "invalid ref name reports fail in an envelope, exit 0" "exit $ST" "output: $OUT"
fi

echo "[usage] no argument"
OUT="$(bash "$SCRIPT" 2>&1)"; ST=$?
if [[ "$ST" == 2 ]]; then ok "no arg -> exit 2"; else bad "no arg -> exit 2" "got exit $ST"; fi

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
