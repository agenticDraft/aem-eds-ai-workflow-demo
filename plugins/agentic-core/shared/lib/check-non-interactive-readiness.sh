#!/usr/bin/env bash
# check-non-interactive-readiness.sh — Refuses a `url`-sourced design reference
# up front, in `autonomous` mode only, when the configured design pack declares
# it cannot complete `fetch_reference` without an interactive session
# (shared/pack-manifest.md's `requires_interactive_session`, D100, G503,
# Phase 10 / Task 2).
#
# Reads three already-written files only — never probes a machine, never
# resolves or calls the design pack itself (a live probe would create the
# tracker/scm/design/browser dependency `eds-readiness/SKILL.md` states this
# gate does not have).
#
# Usage:
#   check-non-interactive-readiness.sh <fact-record.yaml> <run-state.json> <design-pack.yaml|none>
#
# Exit codes:
#   0 — proceed: not a url source, not autonomous mode, no design pack
#       configured, or the configured pack does not require an interactive
#       session for fetch_reference. "pass: <reason>" on stdout.
#   1 — refuse: url-sourced, autonomous, and the pack requires an interactive
#       session. "refuse: <reason>" on stdout.
#   2 — usage error (missing argument, a file not found); "invalid: <reason>"
#       on stderr

set -uo pipefail

FACT="${1:-}"
STATE="${2:-}"
DESIGN_PACK="${3:-}"

if [[ -z "$FACT" || -z "$STATE" || -z "$DESIGN_PACK" ]]; then
  echo "usage: check-non-interactive-readiness.sh <fact-record.yaml> <run-state.json> <design-pack.yaml|none>" >&2
  exit 2
fi
[[ -f "$FACT" ]] || { echo "invalid: file not found: $FACT" >&2; exit 2; }
[[ -f "$STATE" ]] || { echo "invalid: file not found: $STATE" >&2; exit 2; }
if [[ "$DESIGN_PACK" != "none" ]]; then
  [[ -f "$DESIGN_PACK" ]] || { echo "invalid: file not found: $DESIGN_PACK" >&2; exit 2; }
fi

# --- read the fact record's design_source_kind and item_id -----------------
fact_field() {
  local key="$1" line
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^${key}:\ *(.*)$ ]] && { echo "${BASH_REMATCH[1]}"; return 0; }
  done < "$FACT"
  return 1
}

ITEM_ID="$(fact_field item_id || echo "<unknown>")"
KIND="$(fact_field design_source_kind || true)"

if [[ "$KIND" != "url" ]]; then
  echo "pass: design_source_kind is '${KIND:-absent}', not url — nothing to refuse"
  exit 0
fi

# --- read run-state.json's mode ---------------------------------------------
state_field() {
  local key="$1" line
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^[[:space:]]*\"${key}\":\ (.*)$ ]]; then
      local value="${BASH_REMATCH[1]}"
      value="${value%,}"
      value="${value#\"}"; value="${value%\"}"
      echo "$value"
      return 0
    fi
  done < "$STATE"
  return 1
}

MODE="$(state_field mode || true)"

if [[ "$MODE" != "autonomous" ]]; then
  echo "pass: mode is '${MODE:-absent}', not autonomous — a human can complete the OAuth flow"
  exit 0
fi

if [[ "$DESIGN_PACK" == "none" ]]; then
  echo "pass: no design pack configured — nothing declares itself interactive-only"
  exit 0
fi

# --- read the design pack's requires_interactive_session -------------------
RIS_LINE=""
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ "$line" =~ ^requires_interactive_session:\ \[(.*)\]$ ]] && { RIS_LINE="${BASH_REMATCH[1]}"; break; }
done < "$DESIGN_PACK"

if [[ -z "$RIS_LINE" ]]; then
  echo "pass: '$DESIGN_PACK' declares no requires_interactive_session — absent means ungated"
  exit 0
fi

IFS=',' read -ra RAW <<< "$RIS_LINE"
GATED=0
for raw in "${RAW[@]:-}"; do
  op="${raw#"${raw%%[![:space:]]*}"}"
  op="${op%"${op##*[![:space:]]}"}"
  [[ "$op" == "fetch_reference" ]] && GATED=1
done

if [[ $GATED -eq 1 ]]; then
  echo "refuse: $ITEM_ID's design source is a URL, this run is autonomous, and the configured design pack ('$DESIGN_PACK') declares fetch_reference requires an interactive session — a headless run cannot complete the OAuth flow"
  exit 1
fi

echo "pass: '$DESIGN_PACK' does not declare fetch_reference under requires_interactive_session"
exit 0
