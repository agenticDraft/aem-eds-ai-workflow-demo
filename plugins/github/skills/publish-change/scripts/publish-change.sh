#!/usr/bin/env bash
# publish-change.sh <branch> <title> <body-file> [base-branch]
#
# scm.publish_change — push the branch and open (or reuse) a pull request,
# then print the result envelope. Must be run from a checkout already on
# <branch>, so a possibly-dirty working tree from an earlier stage's edits is
# never switched out from under it. The PR body is read from a file rather
# than an argument so arbitrary text never has to survive shell quoting, the
# same reasoning Task 1's post-note.sh applied to note text.
#
# Exit codes: 0 with an envelope on stdout for every operational outcome
# (pass or fail); 2 for a usage error (missing argument, file not found).

set -uo pipefail

BRANCH="${1:-}"
TITLE="${2:-}"
BODY_FILE="${3:-}"
BASE="${4:-}"
if [[ -z "$BRANCH" || -z "$TITLE" || -z "$BODY_FILE" ]]; then
  echo "usage: publish-change.sh <branch> <title> <body-file> [base-branch]" >&2
  exit 2
fi
if [[ ! -f "$BODY_FILE" ]]; then
  echo "body text file not found: $BODY_FILE" >&2
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

# BRANCH/BASE validated with git's own ref-name checker (see create-branch.sh
# for why). TITLE flows into `gh`'s --title argument as a literal argv
# element, never a shell string, so it cannot inject a second command — the
# residual risk is a leading `-` being parsed as a flag, and a title that is
# not the single sentence the envelope's own `summary` field requires.
if ! git check-ref-format --branch "$BRANCH" >/dev/null 2>&1; then
  envelope_fail "the given branch name is not a valid git ref name."
fi
if [[ -n "$BASE" ]] && ! git check-ref-format --branch "$BASE" >/dev/null 2>&1; then
  envelope_fail "the given base branch name is not a valid git ref name."
fi
if [[ "$TITLE" == -* ]]; then
  envelope_fail "title must not start with a hyphen."
fi
if [[ "$TITLE" == *$'\n'* ]]; then
  envelope_fail "title must be a single line."
fi

if ! gh auth status >/dev/null 2>&1; then
  envelope_fail "gh is not authenticated to GitHub on this machine."
fi

CURRENT="$(git branch --show-current 2>/dev/null)"
if [[ "$CURRENT" != "$BRANCH" ]]; then
  envelope_fail "not on branch ${BRANCH} (currently on ${CURRENT:-detached HEAD})."
fi

if [[ -z "$BASE" ]]; then
  BASE="$(gh repo view --json defaultBranchRef -q '.defaultBranchRef.name' 2>/dev/null)"
  if [[ -z "$BASE" ]]; then
    envelope_fail "could not determine the repository's default branch."
  fi
fi

if ! git push -u origin "$BRANCH" --quiet 2>/dev/null; then
  envelope_fail "could not push ${BRANCH} to origin."
fi

OUT_DIR=".ai/scm"
mkdir -p "$OUT_DIR"
OUT_FILE="${OUT_DIR}/publish-change-${BRANCH//\//_}.json"

# `gh pr view` takes the same ambiguous `<number> | <url> | <branch>`
# positional selector `gh pr checks` does, and a purely-numeric BRANCH
# (which git's own ref grammar allows) resolves as a PR number, not this
# branch — silently writing a different, unrelated pull request's data into
# this operation's own artifact file. `gh pr list --head` has no such
# ambiguity (exact match only), so every `gh pr view` call below is made
# against a PR *number* already resolved through it, never against BRANCH
# directly.
EXISTING="$(gh pr list --head "$BRANCH" --state open --json number,url --jq '.[0] // empty' 2>/dev/null)"
if [[ -n "$EXISTING" ]]; then
  EXISTING_NUMBER="$(printf '%s' "$EXISTING" | python3 -c 'import json,sys; print(json.load(sys.stdin)["number"])')"
  EXISTING_URL="$(printf '%s' "$EXISTING" | python3 -c 'import json,sys; print(json.load(sys.stdin)["url"])')"
  gh pr view "$EXISTING_NUMBER" --json number,url,state,baseRefName > "$OUT_FILE" 2>/dev/null
  cat <<RESULT
## Result
verdict: pass
summary: An open pull request already exists for ${BRANCH}: ${EXISTING_URL}.
artifacts:
  - ${OUT_FILE}
next_action: none
RESULT
  exit 0
fi

PR_URL="$(gh pr create --title "$TITLE" --body-file "$BODY_FILE" --base "$BASE" --head "$BRANCH" 2>&1)"
PR_EXIT=$?
if [[ $PR_EXIT -ne 0 ]]; then
  envelope_fail "gh pr create failed (exit ${PR_EXIT}) for branch ${BRANCH}."
fi

NEW_NUMBER="$(gh pr list --head "$BRANCH" --state open --json number --jq '.[0].number // empty' 2>/dev/null)"
ARTIFACTS_BLOCK="artifacts: []"
if [[ -n "$NEW_NUMBER" ]]; then
  gh pr view "$NEW_NUMBER" --json number,url,state,baseRefName > "$OUT_FILE" 2>/dev/null
  ARTIFACTS_BLOCK="artifacts:
  - ${OUT_FILE}"
fi

cat <<RESULT
## Result
verdict: pass
summary: Opened a pull request for ${BRANCH} against ${BASE}: ${PR_URL}.
${ARTIFACTS_BLOCK}
next_action: none
RESULT
