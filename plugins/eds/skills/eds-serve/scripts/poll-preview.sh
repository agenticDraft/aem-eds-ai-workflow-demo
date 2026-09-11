#!/usr/bin/env bash
# poll-preview.sh — Deterministic readiness poll against a preview URL. No
# model involved.
#
# Answers one question: is something bound and responding at this URL? It
# polls on a fixed backoff ladder — attempt first, then wait — so a preview
# that is already up costs one immediate request and no delay at all, while
# one still starting gets a bounded wait rather than a fixed sleep that is
# either wasteful or flaky.
#
# The ladder is 0, 2, 4, 8, 16 seconds: five polls, the last of which begins
# roughly thirty seconds in. A stage that wants a different budget changes
# the ladder here, in one place, rather than at each call site.
#
# **Any HTTP status counts as an answer, including 4xx and 5xx.** The
# question is whether the origin is bound, not whether this particular path
# exists: a preview path is configuration and may name something the project
# does not serve, while every consumer of this stage builds its own URL from
# the same origin. A status of `000` is curl reporting no HTTP response at
# all — nothing bound, the request refused, or the request blocked before it
# left the host — and those are indistinguishable from here, so an
# exhausted ladder reports that nothing answered without claiming why.
#
# Usage:
#   poll-preview.sh <url>
#
# Output on success: one line,
#   answered: status=<http status> poll=<n> elapsed=<n>s
#
# Exit codes:
#   0 — the URL answered; the line above is on stdout
#   1 — the ladder was exhausted with no answer; reason on stderr
#   2 — usage error (missing or empty argument)

set -uo pipefail

URL="${1:-}"

if [[ -z "$URL" ]]; then
  echo "usage: poll-preview.sh <url>" >&2
  exit 2
fi

STARTED=$(date +%s)
POLL=0

for DELAY in 0 2 4 8 16; do
  if [[ "$DELAY" -gt 0 ]]; then
    sleep "$DELAY"
  fi
  POLL=$(( POLL + 1 ))
  STATUS=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "$URL" 2>/dev/null)
  if [[ -n "$STATUS" && "$STATUS" != "000" ]]; then
    echo "answered: status=$STATUS poll=$POLL elapsed=$(( $(date +%s) - STARTED ))s"
    exit 0
  fi
done

echo "no-answer: nothing answered at $URL across $POLL polls over $(( $(date +%s) - STARTED ))s" >&2
exit 1
