#!/usr/bin/env bash
# check-status.sh <branch>
#
# scm.check_status — report automated checks on the branch's open pull
# request, then print the result envelope. `verdict` here reports whether
# the checks could be retrieved, not whether the checks themselves are
# green — the same reading Task 1 gave `fetch_item` (pass means "the read
# succeeded," not a judgment on the item's own state). The per-check outcome
# (how many passed/failed/are pending) is reported in `summary`/`metrics`.
#
# Confirmed live, not assumed: `gh pr checks <branch>` can exit 0 with a
# `bucket: fail` entry present in its own JSON (a non-required check failing
# does not fail the command), so the operation's own verdict is derived by
# parsing the JSON payload, never from gh's exit code.
#
# Exit codes: 0 with an envelope on stdout for every operational outcome
# (pass or fail); 2 for a usage error (missing argument).

set -uo pipefail

BRANCH="${1:-}"
if [[ -z "$BRANCH" ]]; then
  echo "usage: check-status.sh <branch-name>" >&2
  exit 2
fi

envelope_fail() {
  cat <<RESULT
## Result
verdict: fail
summary: $1
artifacts: []
next_action: none
RESULT
  exit 0
}

# See create-branch.sh for why git's own ref-name checker is used here
# instead of a hand-rolled grammar.
if ! git check-ref-format --branch "$BRANCH" >/dev/null 2>&1; then
  envelope_fail "the given branch name is not a valid git ref name."
fi

if ! gh auth status >/dev/null 2>&1; then
  envelope_fail "gh is not authenticated to GitHub on this machine."
fi

OUT_DIR=".ai/scm"
mkdir -p "$OUT_DIR"
OUT_FILE="${OUT_DIR}/check-status-${BRANCH//\//_}.json"

# `gh pr checks` accepts `<number> | <url> | <branch>` as one ambiguous
# positional selector, and a purely-numeric BRANCH (which git's own ref
# grammar allows, e.g. "31") resolves as a PR *number* rather than a branch,
# silently returning another pull request's checks. Resolved live and fixed
# same session: PR_NUMBER is looked up first via `--head`, an exact-match
# flag with no such ambiguity, and only that trusted number is ever handed
# to `gh pr checks`.
PR_NUMBER="$(gh pr list --head "$BRANCH" --state open --json number --jq '.[0].number // empty' 2>/dev/null)"
if [[ -z "$PR_NUMBER" ]]; then
  envelope_fail "no open pull request found for branch ${BRANCH}."
fi

RAW="$(gh pr checks "$PR_NUMBER" --json name,state,bucket,link 2>/dev/null)"
if ! printf '%s' "$RAW" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
  envelope_fail "no checks could be retrieved for branch ${BRANCH} (pull request #${PR_NUMBER}, or a gh error)."
fi

printf '%s' "$RAW" > "$OUT_FILE"

# Two lines read via `read`, not `mapfile` — this project's scripts target
# macOS's default `/bin/bash` (3.2, resolved by `#!/usr/bin/env bash` here),
# which predates bash 4's mapfile builtin.
PY_OUT="$(python3 -c '
import json, sys
with open(sys.argv[1]) as f:
    checks = json.load(f)
order = ["pass", "fail", "pending", "skipping", "cancel"]
buckets = {b: 0 for b in order}
for c in checks:
    b = c.get("bucket", "unknown")
    buckets[b] = buckets.get(b, 0) + 1
total = len(checks)
parts = ", ".join(f"{buckets[b]} {b}" for b in order if buckets[b])
print(parts if parts else "no checks configured")
print("metrics: total=" + str(total) + " " + " ".join(f"{b}={buckets[b]}" for b in order))
' "$OUT_FILE")"

CHECK_SUMMARY="$(printf '%s\n' "$PY_OUT" | head -n 1)"
METRICS_LINE="$(printf '%s\n' "$PY_OUT" | tail -n 1)"

cat <<RESULT
## Result
verdict: pass
summary: Retrieved checks for ${BRANCH} (${CHECK_SUMMARY}).
artifacts:
  - ${OUT_FILE}
next_action: none
${METRICS_LINE}
RESULT
