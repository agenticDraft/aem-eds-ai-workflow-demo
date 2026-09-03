#!/usr/bin/env bash
# run-stage.sh — Deterministic half of one stage-runner step (see
# shared/stage-runner.md). No model involved: resolves the stage id's
# adapter from the platform pack manifest, validates the already-captured
# result envelope against shared/result-envelope.md, and prints the
# decision the runner branches on. It does not spawn the adapter itself —
# that is the one step above this script that genuinely needs a model, left
# to whichever skill drives a full route.
#
# Usage:
#   run-stage.sh <path-to-pack.yaml> <stage id> <path-to-envelope>
#
# Exit codes and the "decision:" line they print:
#   0 — decision: continue           (verdict: pass)
#   0 — decision: continue-warn      (verdict: warn; the warning is reported, not dropped)
#   3 — decision: terminate-failed   (verdict: fail — the stage's own judgment, not a
#                                      contract violation)
#   1 — decision: terminate-contract-violation ("invalid: <reason>" on stderr — an
#                                      unresolvable stage id, or an envelope that fails
#                                      shared/result-envelope.md's validator)
#   2 — usage error (missing argument, pack manifest or envelope file not found)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATE_ENVELOPE="$SCRIPT_DIR/validate-result-envelope.sh"

PACK="${1:-}"
STAGE_ID="${2:-}"
ENVELOPE="${3:-}"

if [[ -z "$PACK" || -z "$STAGE_ID" || -z "$ENVELOPE" ]]; then
  echo "usage: run-stage.sh <path-to-pack.yaml> <stage id> <path-to-envelope>" >&2
  exit 2
fi

if [[ ! -f "$PACK" ]]; then
  echo "invalid: file not found: $PACK" >&2
  exit 2
fi

if [[ ! -f "$ENVELOPE" ]]; then
  echo "invalid: file not found: $ENVELOPE" >&2
  exit 2
fi

contract_violation() {
  echo "invalid: $1" >&2
  echo "decision: terminate-contract-violation"
  exit 1
}

# --- resolve the adapter: <stage id> -> skill name, from the manifest's
# 'stages:' map. Reads the manifest as a flat line scan rather than the full
# validate-pack-manifest.sh shape check — a manifest this script is handed
# is assumed already valid (the same "assumed already validated" precedent
# resolve-route.sh sets for its project-config argument); this script only
# needs the one mapping.
ADAPTER=""
in_stages=0
while IFS= read -r line || [[ -n "$line" ]]; do
  if [[ "$line" == "stages:" ]]; then
    in_stages=1
    continue
  fi
  if (( in_stages )); then
    if [[ "$line" =~ ^\ \ ([A-Za-z0-9_-]+):\ (.+)$ ]]; then
      if [[ "${BASH_REMATCH[1]}" == "$STAGE_ID" ]]; then
        ADAPTER="${BASH_REMATCH[2]}"
        break
      fi
      continue
    fi
    break # first non-'  id: skill' line ends the stages: map
  fi
done < "$PACK"

if [[ -z "$ADAPTER" ]]; then
  contract_violation "stage '$STAGE_ID' has no adapter in ${PACK}'s stages map"
fi

echo "adapter: $ADAPTER"

# --- read the envelope: shared/result-envelope.md's own validator is the
# single source of truth for what "unparseable" means, so this script
# reads the envelope only through it rather than re-parsing the block.
ENVELOPE_OUT="$("$VALIDATE_ENVELOPE" "$ENVELOPE" 2>&1)"
ENVELOPE_STATUS=$?

if (( ENVELOPE_STATUS != 0 )); then
  contract_violation "envelope failed validation: $ENVELOPE_OUT"
fi

verdict="${ENVELOPE_OUT#verdict: }"
echo "verdict: $verdict"

case "$verdict" in
  pass)
    echo "decision: continue"
    exit 0
    ;;
  warn)
    echo "decision: continue-warn"
    exit 0
    ;;
  fail)
    echo "decision: terminate-failed"
    exit 3
    ;;
  question)
    # The question protocol (asking at the boundary, autonomous write-back,
    # the per-run budget) is a separate contract this script does not
    # implement — see shared/stage-runner.md.
    echo "decision: question"
    exit 0
    ;;
  *)
    contract_violation "validate-result-envelope.sh reported an unrecognised verdict '$verdict'"
    ;;
esac
