#!/usr/bin/env bash
# Tests for publish-change.sh. Run with:
#   bash plugins/github/skills/publish-change/scripts/publish-change.test.sh
#
# No framework — exits 0 on success, 1 on any failure.
#
# Nothing here touches GitHub. `origin` is a local bare repository, so the push
# is a real git operation against a real remote; only `gh` is stubbed.
#
# The cases that matter are the refusals: the default branch, or a branch equal
# to its base, is refused before anything is pushed.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/publish-change.sh"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/publish-change.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); echo "  ok: $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; shift; for l in "$@"; do echo "    $l"; done; }

# A `gh` with no open pull request, whose `pr create` succeeds.
mkdir -p "$WORK/bin"
cat > "$WORK/bin/gh" <<'GH'
#!/usr/bin/env bash
case "${1:-} ${2:-}" in
  "auth status") exit 0 ;;
  "repo view") echo main ;;
  "pr list") exit 0 ;;
  "pr create") echo "https://example.invalid/pull/1" ;;
  "pr view") echo '{}' ;;
  *) exit 1 ;;
esac
GH
chmod +x "$WORK/bin/gh"
export PATH="$WORK/bin:$PATH"

echo "body" > "$WORK/body.md"

# fresh <name> — a repo with one commit on main, pushed to its own bare origin,
# plus one local commit not yet pushed. Echoes the repo path.
fresh() {
  local remote="$WORK/$1-remote.git" repo="$WORK/$1"
  git init --bare -q "$remote"
  git init -q "$repo"
  (
    cd "$repo" || exit 1
    git config user.email test@example.invalid
    git config user.name "test"
    git symbolic-ref HEAD refs/heads/main
    echo base > file.txt && git add file.txt && git commit -q -m "base"
    git remote add origin "$remote"
    git push -q -u origin main
    echo local > local.txt && git add local.txt && git commit -q -m "local only"
  ) >/dev/null 2>&1
  echo "$repo"
}

remote_sha() { git --git-dir="$WORK/$1-remote.git" rev-parse --verify -q "$2" 2>/dev/null; }

echo "=== publish-change.sh tests ==="

echo "[default] the default branch is refused, nothing pushed"
REPO="$(fresh on-main)"
BEFORE="$(remote_sha on-main main)"
OUT="$(cd "$REPO" && bash "$SCRIPT" main "A title" "$WORK/body.md" 2>&1)"; ST=$?
AFTER="$(remote_sha on-main main)"
if [[ "$OUT" == *"verdict: fail"* && "$OUT" == *"default branch"* && "$ST" == 0 && "$BEFORE" == "$AFTER" ]]; then
  ok "main -> fail, exit 0, origin/main unmoved"
else
  bad "main -> fail, exit 0, origin/main unmoved" \
      "exit $ST  remote moved: $([[ "$BEFORE" == "$AFTER" ]] && echo no || echo YES)" "output: $OUT"
fi

echo "[base] a branch equal to its base is refused, nothing pushed"
REPO="$(fresh same-base)"
(cd "$REPO" && git checkout -q -b release) >/dev/null 2>&1
OUT="$(cd "$REPO" && bash "$SCRIPT" release "A title" "$WORK/body.md" release 2>&1)"; ST=$?
if [[ "$OUT" == *"verdict: fail"* && "$OUT" == *"base branch"* && "$ST" == 0 && -z "$(remote_sha same-base release)" ]]; then
  ok "release onto release -> fail, exit 0, nothing pushed"
else
  bad "release onto release -> fail, exit 0, nothing pushed" "exit $ST" "output: $OUT"
fi

echo "[publish] a working branch is pushed and its pull request opened"
REPO="$(fresh feature)"
(cd "$REPO" && git checkout -q -b eds-1) >/dev/null 2>&1
OUT="$(cd "$REPO" && bash "$SCRIPT" eds-1 "A title" "$WORK/body.md" 2>&1)"; ST=$?
LOCAL="$(cd "$REPO" && git rev-parse eds-1)"
if [[ "$OUT" == *"verdict: pass"* && "$ST" == 0 && "$(remote_sha feature eds-1)" == "$LOCAL" ]]; then
  ok "eds-1 -> pass, pushed to origin"
else
  bad "eds-1 -> pass, pushed to origin" "exit $ST" "output: $OUT"
fi

echo "[usage] no argument"
OUT="$(bash "$SCRIPT" 2>&1)"; ST=$?
if [[ "$ST" == 2 ]]; then ok "no arg -> exit 2"; else bad "no arg -> exit 2" "got exit $ST"; fi

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
