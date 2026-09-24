#!/usr/bin/env bash
# Run: bash plugins/agentic-core/shared/lib/emit-envelope.sh .ai/run-context/envelope-<stage id>.txt --verdict warn --summary "..." --artifact <path>
#
# emit-envelope.sh <output-file> --verdict <v> --summary <s> [options]
#
# Writes a stage's result envelope (`../result-envelope.md`) to a file, in the
# contract's own field order, from values the caller supplies. The caller
# decides what the envelope says; this script decides how it is spelled, so a
# stage never formats a machine-read artifact by hand and never has to get the
# block into its final message for the envelope to exist.
#
# Options:
#   --artifact <path>        a file written or updated; repeatable; none emits `artifacts: []`
#   --next-action <phrase>   default `none`
#   --error-class <class>    fail or question only
#   --question <text>        question only, required there
#   --option <label>         question only; repeatable
#   --blocker <text>         question only, required there
#   --metrics <key=value …>  any verdict
#
# Every rule the contract states about which field may appear with which
# verdict is checked here, before anything is written. A request that breaks
# one is refused whole: the output file is left exactly as it was. A partly
# written envelope would be worse than none, because it would look deliberate
# to everything downstream.
#
# Exit codes: 0 — the file now holds a conformant envelope; 2 — the request was
# refused and nothing was written.

set -uo pipefail

usage() {
  echo "usage: emit-envelope.sh <output-file> --verdict <v> --summary <s> [options]" >&2
  if [ "$#" -gt 0 ]; then echo "$1" >&2; fi
  exit 2
}

[ "$#" -ge 1 ] || usage "expected an output file"
OUT="$1"; shift

VERDICT=""
SUMMARY=""
NEXT_ACTION="none"
ERROR_CLASS=""
QUESTION=""
BLOCKER=""
METRICS=""
ARTIFACTS=()
OPTIONS=()

HAVE_VERDICT=0
HAVE_SUMMARY=0
HAVE_QUESTION=0
HAVE_BLOCKER=0
HAVE_METRICS=0
HAVE_ERROR_CLASS=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --verdict)      [ "$#" -ge 2 ] || usage "--verdict needs a value"; VERDICT="$2"; HAVE_VERDICT=1; shift 2 ;;
    --summary)      [ "$#" -ge 2 ] || usage "--summary needs a value"; SUMMARY="$2"; HAVE_SUMMARY=1; shift 2 ;;
    --artifact)     [ "$#" -ge 2 ] || usage "--artifact needs a value"; ARTIFACTS+=("$2"); shift 2 ;;
    --next-action)  [ "$#" -ge 2 ] || usage "--next-action needs a value"; NEXT_ACTION="$2"; shift 2 ;;
    --error-class)  [ "$#" -ge 2 ] || usage "--error-class needs a value"; ERROR_CLASS="$2"; HAVE_ERROR_CLASS=1; shift 2 ;;
    --question)     [ "$#" -ge 2 ] || usage "--question needs a value"; QUESTION="$2"; HAVE_QUESTION=1; shift 2 ;;
    --option)       [ "$#" -ge 2 ] || usage "--option needs a value"; OPTIONS+=("$2"); shift 2 ;;
    --blocker)      [ "$#" -ge 2 ] || usage "--blocker needs a value"; BLOCKER="$2"; HAVE_BLOCKER=1; shift 2 ;;
    --metrics)      [ "$#" -ge 2 ] || usage "--metrics needs a value"; METRICS="$2"; HAVE_METRICS=1; shift 2 ;;
    *)              usage "unknown argument '$1'" ;;
  esac
done

[ "$HAVE_VERDICT" -eq 1 ] || usage "--verdict is required"
[ "$HAVE_SUMMARY" -eq 1 ] || usage "--summary is required"

case "$VERDICT" in
  pass|warn|fail|question) ;;
  *) usage "--verdict must be one of: pass warn fail question (got '$VERDICT')" ;;
esac

case "$SUMMARY" in
  *$'\n'*) usage "--summary must be one line" ;;
esac
[ "${#SUMMARY}" -le 200 ] || usage "--summary must be 200 characters or fewer (got ${#SUMMARY})"

if [ "$HAVE_ERROR_CLASS" -eq 1 ]; then
  case "$VERDICT" in
    fail|question) ;;
    *) usage "--error-class is valid only with verdict fail or question (got '$VERDICT')" ;;
  esac
  case "$ERROR_CLASS" in
    TRANSIENT|VALIDATION|PERMANENT) ;;
    *) usage "--error-class must be one of: TRANSIENT VALIDATION PERMANENT (got '$ERROR_CLASS')" ;;
  esac
fi

if [ "$VERDICT" = "question" ]; then
  [ "$HAVE_QUESTION" -eq 1 ] || usage "verdict question requires --question"
  [ "$HAVE_BLOCKER" -eq 1 ]  || usage "verdict question requires --blocker"
else
  [ "$HAVE_QUESTION" -eq 0 ] || usage "--question is valid only with verdict question"
  [ "$HAVE_BLOCKER" -eq 0 ]  || usage "--blocker is valid only with verdict question"
  [ "${#OPTIONS[@]}" -eq 0 ] || usage "--option is valid only with verdict question"
fi

BODY="## Result
verdict: $VERDICT
summary: $SUMMARY"

if [ "${#ARTIFACTS[@]}" -eq 0 ]; then
  BODY="$BODY
artifacts: []"
else
  BODY="$BODY
artifacts:"
  for a in "${ARTIFACTS[@]}"; do BODY="$BODY
  - $a"; done
fi

BODY="$BODY
next_action: $NEXT_ACTION"

if [ "$HAVE_ERROR_CLASS" -eq 1 ]; then BODY="$BODY
error_class: $ERROR_CLASS"; fi

if [ "$HAVE_QUESTION" -eq 1 ]; then BODY="$BODY
question: $QUESTION"; fi

if [ "${#OPTIONS[@]}" -gt 0 ]; then
  BODY="$BODY
options:"
  for o in "${OPTIONS[@]}"; do BODY="$BODY
  - $o"; done
fi

if [ "$HAVE_BLOCKER" -eq 1 ]; then BODY="$BODY
blocker: $BLOCKER"; fi

if [ "$HAVE_METRICS" -eq 1 ]; then BODY="$BODY
metrics: $METRICS"; fi

printf '%s\n' "$BODY" > "$OUT"
echo "emitted: $VERDICT envelope with ${#ARTIFACTS[@]} artifact(s) -> $OUT"
exit 0
