#!/usr/bin/env bash
# create-branch.sh <branch-name> [base-branch]
#
# scm.create_branch — create a branch from the repo's base branch and push it
# to origin, then print the result envelope. Operates on the git repository
# in the current working directory; auth comes from gh's own local, per-
# machine credential store (`gh auth status`), never a live Claude session.
#
# Exit codes: 0 with an envelope on stdout for every operational outcome
# (pass or fail); 2 for a usage error (missing argument).

set -uo pipefail

BRANCH="${1:-}"
BASE="${2:-}"
if [[ -z "$BRANCH" ]]; then
  echo "usage: create-branch.sh <branch-name> [base-branch]" >&2
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

# BRANCH/BASE are validated with git's own ref-name checker rather than a
# hand-rolled regex — the authoritative grammar, not a guess at one — before
# either reaches `git`/`gh` as an argument. This also rejects a leading `-`,
# which would otherwise be parsed as a flag by those commands (argument
# injection), the analogous risk here to Task 1's curl-config injection.
if ! git check-ref-format --branch "$BRANCH" >/dev/null 2>&1; then
  envelope_fail "the given branch name is not a valid git ref name."
fi
if [[ -n "$BASE" ]] && ! git check-ref-format --branch "$BASE" >/dev/null 2>&1; then
  envelope_fail "the given base branch name is not a valid git ref name."
fi

if ! gh auth status >/dev/null 2>&1; then
  envelope_fail "gh is not authenticated to GitHub on this machine."
fi

if [[ -z "$BASE" ]]; then
  BASE="$(gh repo view --json defaultBranchRef -q '.defaultBranchRef.name' 2>/dev/null)"
  if [[ -z "$BASE" ]]; then
    envelope_fail "could not determine the repository's default branch."
  fi
fi

if ! git fetch origin "$BASE" --quiet 2>/dev/null; then
  envelope_fail "could not fetch base branch ${BASE} from origin."
fi

if git ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1; then
  envelope_fail "branch ${BRANCH} already exists on origin."
fi

if ! git checkout -b "$BRANCH" "origin/${BASE}" --quiet 2>/dev/null; then
  envelope_fail "could not create local branch ${BRANCH} from origin/${BASE}."
fi

if ! git push -u origin "$BRANCH" --quiet 2>/dev/null; then
  envelope_fail "created ${BRANCH} locally but could not push it to origin."
fi

cat <<RESULT
## Result
verdict: pass
summary: Created branch ${BRANCH} from ${BASE} and pushed it to origin.
artifacts: []
next_action: none
RESULT
