#!/usr/bin/env bash
# check-reachability.sh — Deterministic check for D87's reachability rule
# (03-core-design.md). No model involved.
#
# Two conditions, both required, kept as three distinct outcomes because two
# of them are routinely conflated and mean opposite things:
#
#   unreachable  — the host is a loopback or link-local address. Decided
#                  from the URL string alone: no network call at all.
#   reachable    — condition 1 passed, and a render attempt's own result
#                  envelope reported `verdict: pass`.
#   unconfirmed  — condition 1 passed, but no attempt reported
#                  `verdict: pass` within the retry ladder below. Not a
#                  failure: a freshly published page that has not
#                  propagated yet is the common case, and the common case
#                  must not produce the strongest negative claim.
#
# Condition 2 runs the given render command against the URL, once per rung
# of a fixed backoff ladder, and reads its stdout for a `verdict:` line.
# The render command is supplied by the caller — this script names no
# browser role provider. Any command that takes a URL as its final
# argument and prints a `## Result` envelope (shared/result-envelope.md) on
# stdout satisfies the contract; `verdict: pass` is read as success, any
# other verdict (or a command that fails to run at all) as one failed
# attempt.
#
# The ladder is 0, 2, 4, 8, 16 seconds by default (five attempts) — the
# same shape eds-serve's own poll-preview.sh ladder uses. Override it with
# REACHABILITY_LADDER (space-separated seconds) for a bounded budget other
# than the default; this script's own tests do, since sleeping the real
# ladder would make every test run take over half a minute.
#
# Usage:
#   check-reachability.sh <url> <render-command> [render-command-args...]
#
# Output: two lines on stdout,
#   status: unreachable | reachable | unconfirmed
#   reason: <one phrase>
#
# Exit codes:
#   0 — a status was determined (any of the three above)
#   2 — usage error: missing url or render-command

set -uo pipefail

URL="${1:-}"
shift 2>/dev/null || true
RENDER_CMD=("$@")

if [[ -z "$URL" || "${#RENDER_CMD[@]}" -eq 0 ]]; then
  echo "usage: check-reachability.sh <url> <render-command> [render-command-args...]" >&2
  exit 2
fi

report() {
  echo "status: $1"
  echo "reason: $2"
  exit 0
}

# extract_host <url> — the URL's host, with scheme, userinfo, port, path and
# IPv6 brackets stripped. No DNS resolution: a name is returned as written.
extract_host() {
  local rest="$1"
  rest="${rest#*://}"
  rest="${rest%%/*}"
  rest="${rest##*@}"
  if [[ "$rest" == \[* ]]; then
    rest="${rest#\[}"
    rest="${rest%%]*}"
  else
    rest="${rest%%:*}"
  fi
  printf '%s' "$rest"
}

HOST="$(extract_host "$URL")"
LC_HOST="$(printf '%s' "$HOST" | tr '[:upper:]' '[:lower:]')"

# --- condition 1: loopback or link-local, decided with no network call ----

case "$LC_HOST" in
  localhost|::1)
    report unreachable "loopback address" ;;
esac

if [[ "$LC_HOST" =~ ^127\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
  report unreachable "loopback address"
fi

if [[ "$LC_HOST" =~ ^169\.254\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
  report unreachable "link-local address"
fi

if [[ "$LC_HOST" =~ ^fe[89ab][0-9a-f]: ]]; then
  report unreachable "link-local address"
fi

# --- condition 2: a bounded, backing-off series of render attempts --------

read -r -a LADDER <<< "${REACHABILITY_LADDER:-0 2 4 8 16}"

ATTEMPT=0
for DELAY in "${LADDER[@]}"; do
  if [[ "$DELAY" -gt 0 ]]; then
    sleep "$DELAY"
  fi
  ATTEMPT=$((ATTEMPT + 1))
  OUTPUT="$("${RENDER_CMD[@]}" "$URL" 2>&1)"
  VERDICT_LINE="$(printf '%s\n' "$OUTPUT" | grep -m1 '^verdict:')"
  if [[ "$VERDICT_LINE" == "verdict: pass" ]]; then
    STATUS_TOKEN="$(printf '%s\n' "$OUTPUT" | grep -oE 'status=[0-9]+' | head -1)"
    if [[ -n "$STATUS_TOKEN" ]]; then
      report reachable "${STATUS_TOKEN/status=/HTTP }"
    fi
    report reachable "render succeeded"
  fi
done

report unconfirmed "no successful render within $ATTEMPT attempt(s)"
