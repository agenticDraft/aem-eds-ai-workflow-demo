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
git clone -q "$WORK/remote.git" "$WORK/b"

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
CLAIM_RUN_ID=run-a run "$WORK/a" ITEM-18 100
if [[ "$STATUS" == 0 && "$OUT" == "claimed agentic-run/ITEM-18-c100" ]]; then ok "first claim: exit 0, 'claimed <tag>'"; else bad "first claim" "status $STATUS" "out: $OUT" "err: $ERR"; fi
HEAD_A="$(git -C "$WORK/a" rev-parse HEAD)"
REMOTE_TAG="$(git -C "$WORK/remote.git" rev-parse refs/tags/agentic-run/ITEM-18-c100 2>/dev/null)"
TAG_PARENT="$(git -C "$WORK/remote.git" rev-parse "refs/tags/agentic-run/ITEM-18-c100^" 2>/dev/null)"
TAG_MSG="$(git -C "$WORK/remote.git" log -1 --format=%B refs/tags/agentic-run/ITEM-18-c100 2>/dev/null)"
[[ -n "$REMOTE_TAG" && "$TAG_PARENT" == "$HEAD_A" ]] && ok "the tag on the remote points at a claim commit whose parent is the claimer's HEAD" || bad "tag target" "remote: $REMOTE_TAG" "parent: $TAG_PARENT" "head: $HEAD_A"
[[ "$TAG_MSG" == *"claim agentic-run/ITEM-18-c100"* && "$TAG_MSG" == *"run: run-a"* ]] && ok "the claim commit names the tag and the run id" || bad "claim commit message" "$TAG_MSG"
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
