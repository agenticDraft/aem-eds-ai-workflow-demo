#!/usr/bin/env bash
# check-run-limits.sh — May one more run start today? Deterministic: counts
# the claims already on the remote, compares them with the route policy's
# daily limits, and answers. No model involved, no store of its own.
#
# A claim is a commit a tag under refs/tags/agentic-run/ points at (see
# claim-run.sh); its message carries "at: <UTC time>" and "by: <identity>".
# Today means the current UTC date. A claim with no "by:" line counts toward
# the day's total and toward no identity.
#
# Run it before claim-run.sh: a refused event then leaves no claim, so it does
# not count against anyone.
#
# Break-glass: with <override> 1 and <identity> on the policy's approvers
# list, the limits are reported but not applied. With <override> 1 and an
# identity that is not an approver, the flag is ignored, said so on stderr,
# and the limits apply. Nothing else in the policy is lifted here.
#
# Fail-closed: a policy the checker refuses, or a remote whose claims cannot
# be read, is exit 1, never a "proceed".
#
# The limits are soft under concurrency: two callers counting at the same
# moment can both see room for one more run.
#
# Usage:
#   check-run-limits.sh <policy-path> <identity> <override 0|1>
#
# Environment:
#   CLAIM_REMOTE — the remote the claims live on (default: origin)
#   LIMITS_TODAY — the UTC date to count, YYYY-MM-DD (default: today)
#
# Exit codes and stdout:
#   0 — "proceed identity <n>/<limit> day <n>/<limit>"
#       or "proceed override identity <n>/<limit> day <n>/<limit>"
#   4 — "limited identity <n>/<limit>" or "limited day <n>/<limit>"
#   1 — "invalid: <reason>" or "failed: <reason>" on stderr
#   2 — usage error

set -uo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: check-run-limits.sh <policy-path> <identity> <override 0|1>" >&2
  exit 2
fi

POLICY="$1"
IDENTITY="$2"
OVERRIDE="$3"

if [[ ! "$IDENTITY" =~ ^[A-Za-z0-9:_-]+$ ]]; then
  echo "usage: identity '$IDENTITY' is not an identity handle" >&2
  exit 2
fi
if [[ ! "$OVERRIDE" =~ ^[01]$ ]]; then
  echo "usage: override '$OVERRIDE' is not 0 or 1" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REMOTE="${CLAIM_REMOTE:-origin}"
TODAY="${LIMITS_TODAY:-$(date -u +%Y-%m-%d)}"
if [[ ! "$TODAY" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  echo "usage: LIMITS_TODAY '$TODAY' is not YYYY-MM-DD" >&2
  exit 2
fi

# The policy, through its own checker. Any refusal there is a refusal here.
if ! NORMALIZED="$(bash "$SCRIPT_DIR/check-route-policy.sh" "$POLICY")"; then
  exit 1
fi
value() { printf '%s\n' "$NORMALIZED" | sed -n "s/^$1=//p"; }
PER_IDENTITY="$(value 'limits\.runs_per_identity_per_day')"
PER_DAY="$(value 'limits\.runs_per_day')"
IS_APPROVER=0
while IFS= read -r a; do
  [[ "$a" == "$IDENTITY" ]] && IS_APPROVER=1
done < <(value 'break_glass\.approver')

git rev-parse --git-dir >/dev/null 2>&1 || { echo "failed: not inside a repository" >&2; exit 1; }

# Every claim tag on the remote. A remote that cannot be listed fails closed.
if ! LISTING="$(git ls-remote --tags "$REMOTE" 'refs/tags/agentic-run/*' 2>&1)"; then
  echo "failed: cannot list claims on remote '$REMOTE': $LISTING" >&2
  exit 1
fi
SHAS="$(printf '%s\n' "$LISTING" | awk '$2 !~ /\^\{\}$/ && $1 ~ /^[0-9a-f]+$/ {print $1}' | sort -u)"

COUNT_DAY=0
COUNT_ID=0
if [[ -n "$SHAS" ]]; then
  # Fetch only the claim commits that are not here yet, into a private
  # namespace, one level deep; the refs are removed again below.
  MISSING=()
  while IFS= read -r sha; do
    git cat-file -e "${sha}^{commit}" 2>/dev/null || MISSING+=("$sha")
  done <<< "$SHAS"
  if (( ${#MISSING[@]} > 0 )); then
    NS="refs/agentic-claims-$$"
    if ! FETCH_ERR="$(git fetch -q --no-tags --depth=1 "$REMOTE" "+refs/tags/agentic-run/*:${NS}/*" 2>&1)"; then
      git for-each-ref --format='delete %(refname)' "$NS" | git update-ref --stdin 2>/dev/null
      echo "failed: cannot fetch claims from remote '$REMOTE': $FETCH_ERR" >&2
      exit 1
    fi
    git for-each-ref --format='delete %(refname)' "$NS" | git update-ref --stdin 2>/dev/null
  fi

  while IFS= read -r sha; do
    if ! MSG="$(git log -1 --format=%B "$sha" 2>/dev/null)"; then
      echo "failed: claim $sha could not be read" >&2
      exit 1
    fi
    AT="$(printf '%s\n' "$MSG" | sed -n 's/^at: \([0-9-]\{10\}\)T.*/\1/p' | head -1)"
    [[ "$AT" == "$TODAY" ]] || continue
    COUNT_DAY=$((COUNT_DAY + 1))
    BY="$(printf '%s\n' "$MSG" | sed -n 's/^by: //p' | head -1)"
    [[ "$BY" == "$IDENTITY" ]] && COUNT_ID=$((COUNT_ID + 1))
  done <<< "$SHAS"
fi

COUNTS="identity ${COUNT_ID}/${PER_IDENTITY} day ${COUNT_DAY}/${PER_DAY}"

if [[ "$OVERRIDE" == 1 ]]; then
  if [[ "$IS_APPROVER" == 1 ]]; then
    echo "proceed override $COUNTS"
    exit 0
  fi
  echo "override ignored: '$IDENTITY' is not on break_glass.approvers" >&2
fi

if (( COUNT_ID >= PER_IDENTITY )); then
  echo "limited identity ${COUNT_ID}/${PER_IDENTITY}"
  exit 4
fi
if (( COUNT_DAY >= PER_DAY )); then
  echo "limited day ${COUNT_DAY}/${PER_DAY}"
  exit 4
fi
echo "proceed $COUNTS"
exit 0
