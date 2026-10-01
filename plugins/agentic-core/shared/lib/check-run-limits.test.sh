#!/usr/bin/env bash
# Tests for check-run-limits.sh. Run with:
#   bash plugins/agentic-core/shared/lib/check-run-limits.test.sh
#
# No framework — exits 0 on success, 1 if any case fails.
#
# The remote is a local bare repository holding claims made by claim-run.sh
# itself, plus hand-made claims for another day and in the older message
# shape. A second clone that never fetched a claim stands in for a fresh
# runner.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIMITS="$SCRIPT_DIR/check-run-limits.sh"
CLAIM="$SCRIPT_DIR/claim-run.sh"

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); echo "  ok: $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; shift; for l in "$@"; do echo "    $l"; done; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/check-run-limits.XXXXXX")" || { echo "cannot create a temp dir" >&2; exit 2; }
[[ -n "$WORK" && -d "$WORK" ]] || { echo "cannot create a temp dir" >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT

TODAY="$(date -u +%Y-%m-%d)"

git init -q --bare "$WORK/remote.git"
git -c init.defaultBranch=main init -q "$WORK/a"
(
  cd "$WORK/a"
  git config user.email t@example.invalid; git config user.name t
  echo one > f; git add f; git commit -q -m one
  git remote add origin "$WORK/remote.git"
  git push -q -u origin main
)
git clone -q -b main "$WORK/remote.git" "$WORK/fresh"

cat > "$WORK/policy.yaml" <<'EOF'
version: 1
forbidden:
  - "Bash(gh pr merge*)"
limits:
  runs_per_identity_per_day: 2
  runs_per_day: 3
budget:
  max_usd_per_run: 5
caps:
  max_turns: 50
  timeout_minutes: 30
break_glass:
  word: "override"
  approvers:
    - "approver-1"
EOF

# run <dir> <args...> — sets OUT, ERR, STATUS
run() {
  local dir="$1"; shift
  OUT="$(cd "$dir" && bash "$LIMITS" "$@" 2>"$WORK/err")"; STATUS=$?
  ERR="$(cat "$WORK/err")"
}
claim() {  # claim <comment id> <by> [override]
  (cd "$WORK/a" && CLAIM_BY="$2" CLAIM_OVERRIDE="${3:-0}" bash "$CLAIM" ITEM-1 "$1" >/dev/null 2>&1)
}
# handmade <tag> <message> — a claim commit pushed as-is, for shapes
# claim-run.sh no longer writes
handmade() {
  local sha
  sha="$(cd "$WORK/a" && git commit-tree "$(git mktree </dev/null)" -m "$2")"
  git -C "$WORK/a" push -q origin "$sha:refs/tags/agentic-run/$1"
}

echo "=== check-run-limits.sh tests ==="

echo "[usage]"
run "$WORK/a"; [[ "$STATUS" == 2 ]] && ok "no arguments: exit 2" || bad "no arguments" "status $STATUS"
run "$WORK/a" "$WORK/policy.yaml" "two words" 0; [[ "$STATUS" == 2 ]] && ok "identity with a space: exit 2" || bad "identity shape" "status $STATUS"
run "$WORK/a" "$WORK/policy.yaml" dev-1 yes; [[ "$STATUS" == 2 ]] && ok "override that is not 0/1: exit 2" || bad "override shape" "status $STATUS"

echo "[fail closed]"
run "$WORK/a" "$WORK/missing.yaml" dev-1 0
[[ "$STATUS" == 1 && "$ERR" == *"invalid: policy file not found"* && -z "$OUT" ]] && ok "missing policy: exit 1, no proceed" || bad "missing policy" "status $STATUS" "out: $OUT" "err: $ERR"
CLAIM_REMOTE=nowhere run "$WORK/a" "$WORK/policy.yaml" dev-1 0
[[ "$STATUS" == 1 && "$ERR" == *"failed: cannot list claims"* && -z "$OUT" ]] && ok "unreadable remote: exit 1, no proceed" || bad "unreadable remote" "status $STATUS" "out: $OUT" "err: $ERR"
mkdir -p "$WORK/notarepo"
run "$WORK/notarepo" "$WORK/policy.yaml" dev-1 0
[[ "$STATUS" == 1 && -z "$OUT" ]] && ok "not a repository: exit 1" || bad "not a repository" "status $STATUS" "out: $OUT"

echo "[no claims yet]"
run "$WORK/fresh" "$WORK/policy.yaml" dev-1 0
[[ "$STATUS" == 0 && "$OUT" == "proceed identity 0/2 day 0/3" ]] && ok "empty remote: proceed 0/2, 0/3" || bad "empty remote" "status $STATUS" "out: $OUT" "err: $ERR"

echo "[counting today's claims]"
claim 1 dev-1
handmade ITEM-1-c90 "claim agentic-run/ITEM-1-c90

run: old
at: 2020-01-01T10:00:00Z
by: dev-1
override: 0"
handmade ITEM-1-c91 "claim agentic-run/ITEM-1-c91

run: 1

at: ${TODAY}T00:00:01Z"
run "$WORK/fresh" "$WORK/policy.yaml" dev-1 0
[[ "$STATUS" == 0 && "$OUT" == "proceed identity 1/2 day 2/3" ]] && ok "today's claim counts; another day's does not; an old-shape claim counts toward the day only" || bad "counting" "status $STATUS" "out: $OUT" "err: $ERR"
[[ -z "$(git -C "$WORK/fresh" for-each-ref 'refs/agentic-claims-*')" && -z "$(git -C "$WORK/fresh" tag -l)" ]] && ok "no refs left behind in the fresh clone" || bad "refs left behind" "$(git -C "$WORK/fresh" for-each-ref)"
[[ -z "$(git -C "$WORK/fresh" status --porcelain)" ]] && ok "working tree untouched" || bad "working tree changed"
LIMITS_TODAY=2020-01-01 run "$WORK/fresh" "$WORK/policy.yaml" dev-1 0
[[ "$STATUS" == 0 && "$OUT" == "proceed identity 1/2 day 1/3" ]] && ok "LIMITS_TODAY selects the day counted" || bad "LIMITS_TODAY" "status $STATUS" "out: $OUT"

echo "[the identity limit]"
claim 2 dev-1
run "$WORK/fresh" "$WORK/policy.yaml" dev-1 0
[[ "$STATUS" == 4 && "$OUT" == "limited identity 2/2" ]] && ok "identity at its limit: exit 4, 'limited identity 2/2'" || bad "identity limit" "status $STATUS" "out: $OUT" "err: $ERR"
run "$WORK/fresh" "$WORK/policy.yaml" dev-2 0
[[ "$STATUS" == 4 && "$OUT" == "limited day 3/3" ]] && ok "another identity is stopped by the day limit: 'limited day 3/3'" || bad "day limit" "status $STATUS" "out: $OUT" "err: $ERR"

echo "[break-glass]"
run "$WORK/fresh" "$WORK/policy.yaml" approver-1 1
[[ "$STATUS" == 0 && "$OUT" == "proceed override identity 0/2 day 3/3" ]] && ok "an approver's override proceeds over the limit" || bad "approver override" "status $STATUS" "out: $OUT" "err: $ERR"
run "$WORK/fresh" "$WORK/policy.yaml" dev-1 1
[[ "$STATUS" == 4 && "$OUT" == "limited identity 2/2" && "$ERR" == *"override ignored: 'dev-1' is not on break_glass.approvers"* ]] && ok "a non-approver's override is ignored and said so" || bad "non-approver override" "status $STATUS" "out: $OUT" "err: $ERR"
run "$WORK/fresh" "$WORK/policy.yaml" approver-1 0
[[ "$STATUS" == 4 ]] && ok "an approver without the override is limited like anyone" || bad "approver without override" "status $STATUS" "out: $OUT"

echo "[a second count reuses what it fetched]"
run "$WORK/fresh" "$WORK/policy.yaml" dev-1 0
[[ "$STATUS" == 4 && "$OUT" == "limited identity 2/2" ]] && ok "same answer on a repeat" || bad "repeat count" "status $STATUS" "out: $OUT"

echo ""
echo "passed: $PASS, failed: $FAIL"
[[ "$FAIL" == 0 ]]
