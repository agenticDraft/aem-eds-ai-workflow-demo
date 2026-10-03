#!/usr/bin/env bash
# check-status.sh [--envelope <file>] <branch>
#
# scm.check_status — find the branch's pull request in any state, report its
# state as `change_state` (open | merged | closed | none, D534) and the
# automated checks recorded against it, then print the result envelope. `verdict` here reports whether
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
# `none` means the lookup succeeded and found no pull request for the branch:
# verdict pass, no checks. A lookup that did not succeed reports no
# change_state at all — an unknown state is never `none`, because a caller
# cleans up after a change that is gone.
#
# Every envelope this script reports is spelled by the agentic-core plugin's
# emitter (shared/lib/emit-envelope.sh), resolved as the sibling plugin of
# this pack's root. With `--envelope <file>` the same block is left in that
# file, so a caller that names the file (the route driver) reads the
# operation's own envelope and never transcribes it.
#
# Exit codes: 0 with an envelope on stdout for every operational outcome
# (pass or fail); 2 for a usage error (missing argument, `--envelope` without
# a value, the emitter not installed beside this pack, or an envelope that
# could not be written).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EMITTER="$SCRIPT_DIR/../../../../agentic-core/shared/lib/emit-envelope.sh"

usage() {
  echo "usage: check-status.sh [--envelope <file>] <branch-name>" >&2
  if [[ $# -gt 0 ]]; then echo "$1" >&2; fi
  exit 2
}

ENVELOPE_FILE=""
BRANCH=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --envelope)
      [[ $# -ge 2 ]] || usage "--envelope needs a value"
      ENVELOPE_FILE="$2"; shift 2 ;;
    --envelope=*)
      ENVELOPE_FILE="${1#--envelope=}"; shift ;;
    *)
      if [[ -z "$BRANCH" ]]; then BRANCH="$1"
      else usage "unexpected argument '$1'"
      fi
      shift ;;
  esac
done
[[ -n "$BRANCH" ]] || usage
[[ -f "$EMITTER" ]] || usage "the agentic-core plugin's emit-envelope.sh was not found beside this pack: $EMITTER"

# emit <emitter options...> — spells the block with the core emitter, prints
# it as this script's final output and, when the caller named an envelope
# file, leaves the same block there. The emitter refuses a malformed request
# whole, so a block that reaches stdout or the file is always conformant.
emit() {
  local out
  if [[ -n "$ENVELOPE_FILE" ]]; then
    out="$ENVELOPE_FILE"
  else
    out="$(mktemp "${TMPDIR:-/tmp}/check-status-envelope.XXXXXX")" || usage "could not create a temporary file"
  fi
  bash "$EMITTER" "$out" "$@" >/dev/null 2>&1
  if [[ ! -s "$out" ]]; then
    [[ -n "$ENVELOPE_FILE" ]] || rm -f "$out"
    usage "could not write the result envelope to '$out'"
  fi
  cat "$out"
  [[ -n "$ENVELOPE_FILE" ]] || rm -f "$out"
  exit 0
}

# envelope_fail <summary> [change_state] — the state only when the lookup
# succeeded, so a failure before it can never read as a state.
envelope_fail() {
  if [[ -n "${2:-}" ]]; then
    emit --verdict fail --summary "$1" --change-state "$2"
  else
    emit --verdict fail --summary "$1"
  fi
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
#
# `--state all` (D534): a merged or closed change is still this branch's
# change. With several, an open one wins; otherwise the newest (highest
# number). Measured 2026-09-29: an unknown branch returns `[]` with exit 0.
LIST="$(gh pr list --head "$BRANCH" --state all --json number,state 2>/dev/null)" \
  || envelope_fail "could not look up a pull request for branch ${BRANCH} (gh error)."

PICK="$(printf '%s' "$LIST" | python3 -c '
import json, sys
prs = json.load(sys.stdin)
if not prs:
    print("none")
    sys.exit(0)
open_prs = [p for p in prs if p["state"] == "OPEN"]
pr = max(open_prs or prs, key=lambda p: p["number"])
print(pr["state"].lower(), pr["number"])
' 2>/dev/null)"

CHANGE_STATE="${PICK%% *}"
case "$CHANGE_STATE" in
  none)
    emit --verdict pass \
      --summary "No pull request exists for branch ${BRANCH}, so there are no checks to report." \
      --change-state none ;;
  open|merged|closed) PR_NUMBER="${PICK##* }" ;;
  *) envelope_fail "could not read the pull request lookup for branch ${BRANCH}." ;;
esac

RAW="$(gh pr checks "$PR_NUMBER" --json name,state,bucket,link 2>/dev/null)"
if ! printf '%s' "$RAW" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
  envelope_fail "no checks could be retrieved for branch ${BRANCH} (pull request #${PR_NUMBER}, or a gh error)." "$CHANGE_STATE"
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
print("total=" + str(total) + " " + " ".join(f"{b}={buckets[b]}" for b in order))
' "$OUT_FILE")"

CHECK_SUMMARY="$(printf '%s\n' "$PY_OUT" | head -n 1)"
METRICS="$(printf '%s\n' "$PY_OUT" | tail -n 1)"

emit --verdict pass \
  --summary "Retrieved checks for ${BRANCH} (#${PR_NUMBER}: ${CHECK_SUMMARY})." \
  --artifact "$OUT_FILE" \
  --change-state "$CHANGE_STATE" \
  --metrics "$METRICS"
