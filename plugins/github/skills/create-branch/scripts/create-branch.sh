#!/usr/bin/env bash
# create-branch.sh <branch-name> [base-branch]
#
# scm.create_branch — create a branch from the caller's current HEAD (or from
# the repo's default branch when that is where the caller is), push it to
# origin, then print the result envelope. Operates on the git repository
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

# Resolving the base when the caller named none. Two cases, because they have
# opposite failure modes and one rule cannot serve both.
#
# On the default branch, the base is `origin/<default>`: a local default branch
# left behind by an already-merged change silently drags that change's
# pre-merge commit onto the new branch. Fetching first is the fix for that, and
# it is the case this script was originally written for.
#
# Anywhere else, the base is the current `HEAD`. Being on another branch is a
# deliberate act, and its commits are the thing the caller is working on. This
# script checks the working tree out to the branch it creates, so basing on the
# default branch here would discard that work mid-operation while still
# reporting `pass` -- which is exactly what it did before this branch existed.
if [[ -n "$BASE" ]]; then
  BASE_REF="origin/${BASE}"
else
  DEFAULT_BRANCH="$(gh repo view --json defaultBranchRef -q '.defaultBranchRef.name' 2>/dev/null)"
  if [[ -z "$DEFAULT_BRANCH" ]]; then
    envelope_fail "could not determine the repository's default branch."
  fi
  CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
  if [[ "$CURRENT_BRANCH" == "$DEFAULT_BRANCH" ]]; then
    BASE="$DEFAULT_BRANCH"
    BASE_REF="origin/${BASE}"
  else
    # Covers a detached HEAD too, where --abbrev-ref prints "HEAD": basing on
    # the current commit is the branch of the two that cannot lose work.
    BASE="$CURRENT_BRANCH"
    BASE_REF="HEAD"
  fi
fi

# Only a remote-tracking base needs fetching; HEAD is already local.
if [[ "$BASE_REF" != "HEAD" ]] && ! git fetch origin "$BASE" --quiet 2>/dev/null; then
  envelope_fail "could not fetch base branch ${BASE} from origin."
fi

if git ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1; then
  envelope_fail "branch ${BRANCH} already exists on origin."
fi

if ! git checkout -b "$BRANCH" "$BASE_REF" --quiet 2>/dev/null; then
  envelope_fail "could not create local branch ${BRANCH} from ${BASE_REF}."
fi

if ! git push -u origin "$BRANCH" --quiet 2>/dev/null; then
  envelope_fail "created ${BRANCH} locally but could not push it to origin."
fi

cat <<RESULT
## Result
verdict: pass
summary: Created branch ${BRANCH} from ${BASE_REF} and pushed it to origin.
artifacts: []
next_action: none
RESULT
