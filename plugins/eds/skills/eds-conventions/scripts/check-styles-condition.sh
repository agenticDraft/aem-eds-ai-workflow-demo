#!/usr/bin/env bash
# check-styles-condition.sh — Deterministic answer to "does the `styles`
# subagent have anything to grade?" No model involved.
#
# Mirrors the identical OR-block this pack's own `pack.yaml` already uses to
# gate `extract`/`prototype`/`verify-design`: { design_source: true } OR
# { design_mentioned: true }. `conventions` itself carries no `when:` — it
# always runs — but its own `styles` subagent is meaningless with neither
# field set, since there is nothing a design source could have supplied to
# grade.
#
# Usage:
#   check-styles-condition.sh <path-to-fact-record.yaml>
#
# Output: one line, `decision=run` or `decision=skip`.
#
# Exit codes:
#   0 — decided (both outcomes above are decisions, not errors)
#   2 — usage error (missing argument, file not found)

set -uo pipefail

FACT="${1:-}"

if [[ -z "$FACT" ]]; then
  echo "usage: check-styles-condition.sh <path-to-fact-record.yaml>" >&2
  exit 2
fi
[[ -f "$FACT" ]] || { echo "invalid: file not found: $FACT" >&2; exit 2; }

field() {
  local want="$1" line
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^${want}:[[:space:]]*(.*)$ ]] || continue
    local val="${BASH_REMATCH[1]}"
    val="${val%"${val##*[![:space:]]}"}"
    echo "$val"
    return 0
  done < "$FACT"
  return 1
}

design_source="$(field design_source || true)"
design_mentioned="$(field design_mentioned || true)"

if [[ "$design_source" == "true" || "$design_mentioned" == "true" ]]; then
  echo "decision=run"
else
  echo "decision=skip"
fi
exit 0
