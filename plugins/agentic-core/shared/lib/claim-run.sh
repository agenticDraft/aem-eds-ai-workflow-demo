#!/usr/bin/env bash
# claim-run.sh — Claim one trigger event, so a second delivery of the same
# event starts no second run. Deterministic: one ref update on the remote,
# no model involved.
#
# The claim is a tag on the remote, agentic-run/<item_id>-c<comment_id>,
# created with a lease that expects the ref to be absent. The remote applies
# that lease atomically, so of two callers racing for the same event exactly
# one sees "claimed"; the other, and every later caller, sees "duplicate".
#
# What the tag points at is a claim commit: an otherwise empty commit on top
# of the caller's HEAD whose message names the tag, the run id and the time.
# Every claim is therefore a new object, so a repeat is a real ref update
# the remote can refuse, never a no-op "already up to date" that would read
# as success. The commit is built without touching HEAD, the index, the
# working tree or any local ref; it exists locally only as a loose object.
#
# A refused push is a duplicate only if the remote really holds the tag —
# that is asked of the remote directly, never read out of git's message text.
# Any other failure (no repository, unknown remote, no credentials, network)
# is a failure, not a duplicate.
#
# Recovery is human: a run that crashed after claiming is not retried here. A
# new token comment carries a new comment id and therefore claims a new tag.
#
# Usage:
#   claim-run.sh <item_id> <comment_id>
#
# Environment:
#   CLAIM_REMOTE — the remote to claim on (default: origin)
#   CLAIM_RUN_ID — recorded in the claim commit's message (default: unknown)
#
# Exit codes:
#   0 — claimed;   "claimed <tag>" on stdout
#   3 — duplicate; "duplicate <tag>" on stdout — the event was already claimed
#   1 — failure;   reason on stderr
#   2 — usage error (wrong argument count or shape)

set -uo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: claim-run.sh <item_id> <comment_id>" >&2
  exit 2
fi

ITEM_ID="$1"
COMMENT_ID="$2"

# Both values reach a ref name, so their shape is checked as data before
# anything is built from them: an item key as a tracker issues it, and a
# comment id as a plain integer.
if [[ ! "$ITEM_ID" =~ ^[A-Za-z][A-Za-z0-9_]*-[0-9]+$ ]]; then
  echo "usage: item_id '$ITEM_ID' does not match <KEY>-<number>" >&2
  exit 2
fi
if [[ ! "$COMMENT_ID" =~ ^[0-9]+$ ]]; then
  echo "usage: comment_id '$COMMENT_ID' is not a number" >&2
  exit 2
fi

REMOTE="${CLAIM_REMOTE:-origin}"
RUN_ID="${CLAIM_RUN_ID:-unknown}"
TAG="agentic-run/${ITEM_ID}-c${COMMENT_ID}"
REF="refs/tags/${TAG}"

if ! HEAD_SHA="$(git rev-parse --verify HEAD 2>/dev/null)"; then
  echo "claim failed for ${TAG}: not inside a repository with a HEAD commit" >&2
  exit 1
fi

# The claim commit. A fixed identity, so the object does not depend on the
# machine's own configuration and a runner with no identity set can claim.
CLAIM_SHA="$(
  GIT_AUTHOR_NAME="agentic-core claim" GIT_AUTHOR_EMAIL="claim@agentic-core.invalid" \
  GIT_COMMITTER_NAME="agentic-core claim" GIT_COMMITTER_EMAIL="claim@agentic-core.invalid" \
  git commit-tree "${HEAD_SHA}^{tree}" -p "$HEAD_SHA" \
    -m "claim ${TAG}" -m "run: ${RUN_ID}" -m "at: $(date -u +%Y-%m-%dT%H:%M:%SZ)" 2>/dev/null
)"
if [[ -z "$CLAIM_SHA" ]]; then
  echo "claim failed for ${TAG}: could not build the claim commit" >&2
  exit 1
fi

# The lease "<ref>:" (empty expected value) means: create it only if it does
# not exist. The remote checks that at the moment of the update.
if PUSH_ERR="$(git push "$REMOTE" "${CLAIM_SHA}:${REF}" --force-with-lease="${REF}:" 2>&1 >/dev/null)"; then
  echo "claimed ${TAG}"
  exit 0
fi

# Refused. Ask the remote whether the tag is there; only then is it a duplicate.
if git ls-remote --exit-code --tags "$REMOTE" "$REF" >/dev/null 2>&1; then
  echo "duplicate ${TAG}"
  exit 3
fi

echo "claim failed for ${TAG} on remote '${REMOTE}': ${PUSH_ERR}" >&2
exit 1
