#!/usr/bin/env bash
# Tests for claim-run.sh. Run with:
#   bash plugins/agentic-core/shared/lib/claim-run.test.sh
#
# No framework — exits 0 on success, 1 if any case fails.
#
# The property under test is atomicity: for one event (item id + comment id)
# exactly one caller ever sees "claimed", every later or concurrent caller
# sees "duplicate", and a failure that is not a duplicate is reported as a
# failure. The remote is a local bare repository; two independent clones
# stand in for two runners that never saw each other's state.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAIM="$SCRIPT_DIR/claim-run.sh"

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); echo "  ok: $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; shift; for l in "$@"; do echo "    $l"; done; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/claim-run.XXXXXX")" || { echo "cannot create a temp dir" >&2; exit 2; }
[[ -n "$WORK" && -d "$WORK" ]] || { echo "cannot create a temp dir" >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT

# One bare remote, two clones that know nothing of each other.
git init -q --bare "$WORK/remote.git"
git -c init.defaultBranch=main init -q "$WORK/a"
(
  cd "$WORK/a"
  git config user.email t@example.invalid; git config user.name t
  echo one > f; git add f; git commit -q -m one
  git remote add origin "$WORK/remote.git"
  git push -q -u origin main
)
# -b main: a bare repository initialised elsewhere may point HEAD at another
# default branch name, and a clone of it would then have no commit checked out.
git clone -q -b main "$WORK/remote.git" "$WORK/b"

# run <dir> <args...> — runs the script from <dir>; sets OUT, ERR, STATUS
run() {
  local dir="$1"; shift
  OUT="$(cd "$dir" && bash "$CLAIM" "$@" 2>"$WORK/err")"; STATUS=$?
  ERR="$(cat "$WORK/err")"
}

echo "=== claim-run.sh tests ==="

echo "[usage errors exit 2]"
run "$WORK/a"; [[ "$STATUS" == 2 ]] && ok "no arguments" || bad "no arguments" "status $STATUS"
run "$WORK/a" ITEM-18; [[ "$STATUS" == 2 ]] && ok "one argument" || bad "one argument" "status $STATUS"
run "$WORK/a" "bad id" 100; [[ "$STATUS" == 2 ]] && ok "item id with a space" || bad "item id with a space" "status $STATUS"
run "$WORK/a" ITEM-18 "12a"; [[ "$STATUS" == 2 ]] && ok "comment id that is not a number" || bad "comment id that is not a number" "status $STATUS"
run "$WORK/a" "../x" 1; [[ "$STATUS" == 2 ]] && ok "item id with a path segment" || bad "item id with a path segment" "status $STATUS"

echo "[first claim]"
CLAIM_BY=bad\ id run "$WORK/a" ITEM-18 100; [[ "$STATUS" == 2 ]] && ok "CLAIM_BY that is not a handle: exit 2" || bad "CLAIM_BY shape" "status $STATUS"
CLAIM_OVERRIDE=yes run "$WORK/a" ITEM-18 100; [[ "$STATUS" == 2 ]] && ok "CLAIM_OVERRIDE that is not 0/1: exit 2" || bad "CLAIM_OVERRIDE shape" "status $STATUS"
! git -C "$WORK/remote.git" rev-parse --verify -q refs/tags/agentic-run/ITEM-18-c100 >/dev/null && ok "a usage error claims nothing" || bad "usage error claimed"

CLAIM_RUN_ID=run-a CLAIM_BY="557058:abc-def" CLAIM_OVERRIDE=1 run "$WORK/a" ITEM-18 100
if [[ "$STATUS" == 0 && "$OUT" == "claimed agentic-run/ITEM-18-c100" ]]; then ok "first claim: exit 0, 'claimed <tag>'"; else bad "first claim" "status $STATUS" "out: $OUT" "err: $ERR"; fi
HEAD_A="$(git -C "$WORK/a" rev-parse HEAD)"
REMOTE_TAG="$(git -C "$WORK/remote.git" rev-parse refs/tags/agentic-run/ITEM-18-c100 2>/dev/null)"
TAG_PARENTS="$(git -C "$WORK/remote.git" log -1 --format=%P refs/tags/agentic-run/ITEM-18-c100 2>/dev/null)"
TAG_TREE="$(git -C "$WORK/remote.git" log -1 --format=%T refs/tags/agentic-run/ITEM-18-c100 2>/dev/null)"
EMPTY_TREE="$(git -C "$WORK/a" mktree </dev/null)"
TAG_MSG="$(git -C "$WORK/remote.git" log -1 --format=%B refs/tags/agentic-run/ITEM-18-c100 2>/dev/null)"
[[ -n "$REMOTE_TAG" && -z "$TAG_PARENTS" && "$TAG_TREE" == "$EMPTY_TREE" ]] && ok "the tag points at a parentless claim commit with the empty tree" || bad "tag target" "remote: $REMOTE_TAG" "parents: $TAG_PARENTS" "tree: $TAG_TREE"
[[ "$TAG_MSG" == *"claim agentic-run/ITEM-18-c100"* && "$TAG_MSG" == *"run: run-a"* ]] && ok "the claim commit names the tag and the run id" || bad "claim commit message" "$TAG_MSG"
[[ "$TAG_MSG" == *$'\nby: 557058:abc-def\n'* && "$TAG_MSG" == *$'\noverride: 1\n'* && "$TAG_MSG" =~ $'\n'at:\ [0-9]{4}-[0-9]{2}-[0-9]{2}T && "$TAG_MSG" =~ $'\n'nonce:\ [0-9]+ ]] && ok "the claim commit records at, by, override and a nonce, one per line" || bad "claim commit fields" "$TAG_MSG"
[[ "$(git -C "$WORK/a" rev-parse HEAD)" == "$HEAD_A" ]] && ok "the claimer's HEAD did not move" || bad "HEAD moved"
[[ -z "$(git -C "$WORK/a" tag -l)" ]] && ok "no local tag was created" || bad "local tag created" "$(git -C "$WORK/a" tag -l)"
[[ -z "$(git -C "$WORK/a" status --porcelain)" ]] && ok "nothing written to the working tree" || bad "working tree changed" "$(git -C "$WORK/a" status --porcelain)"

echo "[repeat from the same clone]"
run "$WORK/a" ITEM-18 100
if [[ "$STATUS" == 3 && "$OUT" == "duplicate agentic-run/ITEM-18-c100" ]]; then ok "same event again: exit 3, 'duplicate <tag>'"; else bad "repeat, same clone" "status $STATUS" "out: $OUT" "err: $ERR"; fi

echo "[repeat from a clone that never saw the tag — the race]"
run "$WORK/b" ITEM-18 100
if [[ "$STATUS" == 3 && "$OUT" == "duplicate agentic-run/ITEM-18-c100" ]]; then ok "second runner: exit 3, 'duplicate <tag>'"; else bad "repeat, other clone" "status $STATUS" "out: $OUT" "err: $ERR"; fi
[[ "$(git -C "$WORK/remote.git" rev-parse refs/tags/agentic-run/ITEM-18-c100)" == "$REMOTE_TAG" ]] && ok "the remote tag still points at the first claim" || bad "tag moved"

echo "[a different event on the same item is a new claim]"
run "$WORK/b" ITEM-18 101
[[ "$STATUS" == 0 && "$OUT" == "claimed agentic-run/ITEM-18-c101" ]] && ok "new comment id: claimed" || bad "new comment id" "status $STATUS" "out: $OUT" "err: $ERR"
MSG101="$(git -C "$WORK/remote.git" log -1 --format=%B refs/tags/agentic-run/ITEM-18-c101)"
[[ "$MSG101" == *$'\nby: unknown\n'* && "$MSG101" == *$'\noverride: 0\n'* ]] && ok "defaults: by unknown, override 0" || bad "claim defaults" "$MSG101"

echo "[the same event twice in the same second, same run id — still refused]"
CLAIM_RUN_ID=same run "$WORK/a" ITEM-18 102
FIRST="$STATUS"
CLAIM_RUN_ID=same run "$WORK/b" ITEM-18 102
[[ "$FIRST" == 0 && "$STATUS" == 3 ]] && ok "the nonce keeps a repeat a refusable update" || bad "same-second repeat" "first $FIRST, second $STATUS" "out: $OUT"

echo "[failures that are not duplicates exit 1]"
CLAIM_REMOTE=nowhere run "$WORK/a" ITEM-18 200
[[ "$STATUS" == 1 && -n "$ERR" ]] && ok "unknown remote: exit 1 with a reason on stderr" || bad "unknown remote" "status $STATUS" "err: $ERR"
! git -C "$WORK/remote.git" rev-parse --verify -q refs/tags/agentic-run/ITEM-18-c200 >/dev/null && ok "no tag was created on the real remote" || bad "tag created despite failure"
mkdir -p "$WORK/notarepo"
run "$WORK/notarepo" ITEM-18 300
[[ "$STATUS" == 1 && -n "$ERR" ]] && ok "not a repository: exit 1 with a reason" || bad "not a repository" "status $STATUS" "err: $ERR"

echo
echo "passed: $PASS, failed: $FAIL"
[[ "$FAIL" == 0 ]]
