#!/usr/bin/env bash
# create-branch.sh <branch-name> [base-branch]
#
# scm.create_branch — ensure the named branch exists and is checked out, based
# on the caller's current HEAD (or on the repo's default branch when that is
# where the caller is), push it to origin, then print the result envelope.
#
# Idempotent. An existing branch is an outcome, not a failure: `metrics`
# carries branch_action=created|existing|switched so a caller can tell which
# happened. The one case it refuses is an existing branch that does not
# contain the caller's HEAD -- checking that out would discard work, so it
# reports `question` and moves nothing. Operates on the git repository
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

# An existing branch is an outcome, not a failure. A run that is resumed, or
# re-started on the same work item, has to be able to call this and land back
# on the branch it was already using.
LOCAL_EXISTS=0
git show-ref --verify --quiet "refs/heads/${BRANCH}" 2>/dev/null && LOCAL_EXISTS=1
REMOTE_EXISTS=0
git ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1 && REMOTE_EXISTS=1

if [[ "$LOCAL_EXISTS" -eq 1 || "$REMOTE_EXISTS" -eq 1 ]]; then
  if [[ "$LOCAL_EXISTS" -eq 1 ]]; then
    EXISTING_REF="refs/heads/${BRANCH}"
  else
    if ! git fetch origin "+refs/heads/${BRANCH}:refs/remotes/origin/${BRANCH}" --quiet 2>/dev/null; then
      envelope_fail "branch ${BRANCH} is on origin but could not be fetched."
    fi
    EXISTING_REF="refs/remotes/origin/${BRANCH}"
  fi

  # The branch must already contain everything the caller's HEAD has. When it
  # does not, checking it out silently discards commits the caller is standing
  # on -- the same class of loss this script's base resolution exists to
  # prevent, arriving from the other direction. Nothing is moved; the caller is
  # asked.
  if ! git merge-base --is-ancestor HEAD "$EXISTING_REF" >/dev/null 2>&1; then
    BEHIND="$(git rev-list --count "${EXISTING_REF}..HEAD" 2>/dev/null || echo unknown)"
    cat <<RESULT
## Result
verdict: question
summary: Branch ${BRANCH} already exists but does not contain the current HEAD, so checking it out would discard work.
artifacts: []
next_action: none
question: Branch ${BRANCH} exists and is missing ${BEHIND} commit(s) that HEAD has. Should it be used, or should a differently named branch be created for this work?
blocker: Checking out ${BRANCH} would discard ${BEHIND} commit(s) present on HEAD. Delete or rename the existing ${BRANCH}, or name a different branch for this work.
metrics: branch_action=stale behind=${BEHIND}
RESULT
    exit 0
  fi

  CURRENT_HEAD_BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
  if [[ "$CURRENT_HEAD_BRANCH" == "$BRANCH" ]]; then
    BRANCH_ACTION="existing"
  else
    if [[ "$LOCAL_EXISTS" -eq 1 ]]; then
      CHECKOUT_OK=0
      git checkout "$BRANCH" --quiet 2>/dev/null && CHECKOUT_OK=1
    else
      CHECKOUT_OK=0
      git checkout -b "$BRANCH" "$EXISTING_REF" --quiet 2>/dev/null && CHECKOUT_OK=1
    fi
    if [[ "$CHECKOUT_OK" -ne 1 ]]; then
      envelope_fail "branch ${BRANCH} exists but could not be checked out."
    fi
    BRANCH_ACTION="switched"
  fi
else
  if ! git checkout -b "$BRANCH" "$BASE_REF" --quiet 2>/dev/null; then
    envelope_fail "could not create local branch ${BRANCH} from ${BASE_REF}."
  fi
  BRANCH_ACTION="created"
fi

if ! git push -u origin "$BRANCH" --quiet 2>/dev/null; then
  envelope_fail "have ${BRANCH} locally but could not push it to origin."
fi

if [[ "$BRANCH_ACTION" == "created" ]]; then
  SUMMARY="Created branch ${BRANCH} from ${BASE_REF} and pushed it to origin."
else
  SUMMARY="Branch ${BRANCH} already existed; it is checked out and pushed to origin."
fi

cat <<RESULT
## Result
verdict: pass
summary: ${SUMMARY}
artifacts: []
next_action: none
metrics: branch_action=${BRANCH_ACTION}
RESULT
