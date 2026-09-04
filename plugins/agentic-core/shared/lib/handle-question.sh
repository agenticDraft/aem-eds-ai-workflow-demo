#!/usr/bin/env bash
# handle-question.sh — Deterministic decision for one verdict: question
# envelope (see shared/question-protocol.md). No model involved, and no
# side effects: like run-stage.sh, this script only decides — it never asks
# a human, never calls a tracker pack, and never writes state. The caller
# acts on the printed decision.
#
# Usage:
#   handle-question.sh <path-to-pack.yaml> <mode> <stage id> <path-to-envelope> <questions-used> <questions-cap>
#
# Exit codes and the "decision:" line they print:
#   0 — decision: ask                 (interactive, budget left — "question:"/"options:" lines
#                                       follow, plus the incremented "questions_used:")
#   3 — decision: terminate-failed    (the stage is always-autonomous — its question is treated
#                                       as fail, in both modes)
#   4 — decision: terminate-blocked   (interactive budget exhausted, or autonomous mode — for
#                                       autonomous a "write-blocker:" line follows, for whichever
#                                       skill drives the route to hand to a tracker pack)
#   1 — decision: terminate-contract-violation ("invalid: <reason>" on stderr — the envelope is
#                                       not verdict: question, or an argument value is malformed)
#   2 — usage error (wrong argument count, pack manifest or envelope file not found)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATE_ENVELOPE="$SCRIPT_DIR/validate-result-envelope.sh"

if [[ $# -ne 6 ]]; then
  echo "usage: handle-question.sh <path-to-pack.yaml> <mode> <stage id> <path-to-envelope> <questions-used> <questions-cap>" >&2
  exit 2
fi

PACK="$1"
MODE="$2"
STAGE_ID="$3"
ENVELOPE="$4"
QUESTIONS_USED="$5"
QUESTIONS_CAP="$6"

if [[ ! -f "$PACK" ]]; then
  echo "invalid: file not found: $PACK" >&2
  exit 2
fi

if [[ ! -f "$ENVELOPE" ]]; then
  echo "invalid: file not found: $ENVELOPE" >&2
  exit 2
fi

fail() {
  echo "invalid: $1" >&2
  echo "decision: terminate-contract-violation"
  exit 1
}

case "$MODE" in
  interactive|autonomous) ;;
  *) fail "mode '$MODE' must be one of interactive, autonomous" ;;
esac

[[ "$QUESTIONS_USED" =~ ^[0-9]+$ ]] || fail "questions-used '$QUESTIONS_USED' is not a non-negative integer"
[[ "$QUESTIONS_CAP" =~ ^[0-9]+$ ]] || fail "questions-cap '$QUESTIONS_CAP' is not a non-negative integer"

# --- the envelope must already conform, and must be a question ------------
ENVELOPE_OUT="$("$VALIDATE_ENVELOPE" "$ENVELOPE" 2>&1)"
ENVELOPE_STATUS=$?
if (( ENVELOPE_STATUS != 0 )); then
  fail "envelope failed validation: $ENVELOPE_OUT"
fi
verdict="${ENVELOPE_OUT#verdict: }"
if [[ "$verdict" != "question" ]]; then
  fail "handle-question.sh called on an envelope with verdict: $verdict, expected verdict: question"
fi

# --- pull the question's own fields out of the already-conformant file ----
QUESTION="$(grep -m1 '^question: ' "$ENVELOPE" | sed 's/^question: //')"
BLOCKER="$(grep -m1 '^blocker: ' "$ENVELOPE" | sed 's/^blocker: //')"
OPTIONS="$(awk '/^options:$/{flag=1; next} /^blocker: /{flag=0} flag' "$ENVELOPE")"

# --- always_autonomous: [<stage id>, ...] on one line ----------------------
ALWAYS_LINE="$(grep -m1 '^always_autonomous: \[' "$PACK")"
always_autonomous=0
if [[ "$ALWAYS_LINE" =~ ^always_autonomous:\ \[(.*)\]$ ]]; then
  IFS=',' read -ra ids <<< "${BASH_REMATCH[1]}"
  for id in "${ids[@]}"; do
    id="${id// /}"
    [[ "$id" == "$STAGE_ID" ]] && always_autonomous=1
  done
fi

if (( always_autonomous )); then
  echo "decision: terminate-failed"
  echo "reason: verdict: question from always-autonomous stage '$STAGE_ID' is treated as fail in both modes"
  exit 3
fi

if [[ "$MODE" == "interactive" ]]; then
  if (( QUESTIONS_USED < QUESTIONS_CAP )); then
    echo "decision: ask"
    echo "question: $QUESTION"
    if [[ -n "$OPTIONS" ]]; then
      echo "options:"
      echo "$OPTIONS"
    fi
    echo "questions_used: $((QUESTIONS_USED + 1))"
    exit 0
  else
    echo "decision: terminate-blocked"
    echo "reason: questions_per_run budget exhausted ($QUESTIONS_CAP)"
    exit 4
  fi
else
  echo "decision: terminate-blocked"
  echo "write-blocker: $BLOCKER"
  echo "reason: autonomous mode blocks without asking a human"
  exit 4
fi
