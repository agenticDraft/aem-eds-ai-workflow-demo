#!/usr/bin/env bash
# render-analytics.sh — Renders a run's token measurements from the session
# transcript the harness already wrote to disk (see shared/analytics.md).
# No model involved: every number is read from a transcript line's own
# `usage` object, deduplicated by `.message.id`, and summed or compared by
# this script alone.
#
# Usage:
#   render-analytics.sh <session-transcript.jsonl> <output-path.md> [ceilings-file]
#
# Exit codes:
#   0 — success, no ceilings breached (or none supplied); "written: <path>" on stdout
#   1 — success writing the file, but a supplied ceilings file has at least
#       one FAIL row; "written: <path>" still printed, "ceilings: FAIL" on stderr
#   2 — usage error: missing argument, transcript file not found, or a
#       supplied ceilings file that does not exist
#
# Requires: jq.

set -uo pipefail
shopt -s nullglob

SESSION="${1:-}"
OUTPUT="${2:-}"
CEILINGS="${3:-}"

if [[ -z "$SESSION" || -z "$OUTPUT" ]]; then
  echo "usage: render-analytics.sh <session-transcript.jsonl> <output-path.md> [ceilings-file]" >&2
  exit 2
fi

if [[ ! -f "$SESSION" ]]; then
  echo "invalid: file not found: $SESSION" >&2
  exit 2
fi

if [[ -n "$CEILINGS" && ! -f "$CEILINGS" ]]; then
  echo "invalid: file not found: $CEILINGS" >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "invalid: jq is required and was not found on PATH" >&2
  exit 2
fi

# --- stats_for <file> <parent|sub>: prints one JSON object with the
# deduplicated cumulative billed input, cumulative output, turn count and
# peak context for the counted lines in <file>. The parent transcript is
# filtered to isSidechain==false (its own turns only, per shared/analytics.md);
# a subagent transcript holds only its own turns and is read without that
# filter — its own lines are marked isSidechain:true by the harness.
stats_for() {
  local file="$1" mode="$2" filter
  if [[ "$mode" == "parent" ]]; then
    filter='select(.type=="assistant" and .message.usage != null and (.isSidechain == false))'
  else
    filter='select(.type=="assistant" and .message.usage != null)'
  fi
  jq -s "
    [ .[] | $filter ] as \$turns
    | (\$turns | group_by(.message.id) | map(.[-1])) as \$deduped
    | {
        turns: (\$deduped | length),
        cum_input: ((\$deduped | map(.message.usage.input_tokens // 0) | add) // 0),
        cum_cache_creation: ((\$deduped | map(.message.usage.cache_creation_input_tokens // 0) | add) // 0),
        cum_cache_read: ((\$deduped | map(.message.usage.cache_read_input_tokens // 0) | add) // 0),
        cum_output: ((\$deduped | map(.message.usage.output_tokens // 0) | add) // 0),
        peak_input: (if (\$turns | length) > 0 then \$turns[-1].message.usage.input_tokens // 0 else 0 end),
        peak_cache_creation: (if (\$turns | length) > 0 then \$turns[-1].message.usage.cache_creation_input_tokens // 0 else 0 end),
        peak_cache_read: (if (\$turns | length) > 0 then \$turns[-1].message.usage.cache_read_input_tokens // 0 else 0 end),
        peak_output: (if (\$turns | length) > 0 then \$turns[-1].message.usage.output_tokens // 0 else 0 end)
      }
      | . + {
          cum_billed: (.cum_input + .cum_cache_creation + .cum_cache_read),
          peak: (.peak_input + .peak_cache_creation + .peak_cache_read + .peak_output)
        }
  " "$file"
}

# --- wallclock_seconds <file>: last timestamped line's timestamp minus the
# first timestamped line's, across every line in the file that carries one
# (not only counted lines) — a harness bookkeeping line (for example, a
# cost-state line) may carry no timestamp and is skipped rather than
# treated as zero.
wallclock_seconds() {
  local file="$1"
  jq -s '
    [ .[] | select(.timestamp != null) ] as $stamped
    | if ($stamped | length) == 0 then 0
      else
        ($stamped[0].timestamp | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) as $first
        | ($stamped[-1].timestamp | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) as $last
        | ($last - $first)
      end
  ' "$file"
}

format_duration() {
  local secs="$1"
  if (( secs >= 60 )); then
    printf '%dm %ds' "$((secs / 60))" "$((secs % 60))"
  else
    printf '%ds' "$secs"
  fi
}

format_ratio() {
  local cum="$1" peak="$2"
  if (( peak == 0 )); then
    echo "n/a"
  else
    awk -v c="$cum" -v p="$peak" 'BEGIN { printf "%.1fx", c / p }'
  fi
}

mkdir -p "$(dirname "$OUTPUT")"

ORCH_STATS="$(stats_for "$SESSION" parent)"
ORCH_TURNS="$(jq -r '.turns' <<<"$ORCH_STATS")"
ORCH_PEAK="$(jq -r '.peak' <<<"$ORCH_STATS")"
ORCH_CUM_BILLED="$(jq -r '.cum_billed' <<<"$ORCH_STATS")"
ORCH_CUM_OUTPUT="$(jq -r '.cum_output' <<<"$ORCH_STATS")"
ORCH_WALLCLOCK="$(format_duration "$(wallclock_seconds "$SESSION")")"

SUBAGENTS_DIR="${SESSION%.jsonl}/subagents"

TOTAL_CUM_BILLED="$ORCH_CUM_BILLED"
TOTAL_CUM_OUTPUT="$ORCH_CUM_OUTPUT"

SUB_ROWS=""
CEILING_ROWS=""
CEILING_OVERALL="PASS"

for AGENT_FILE in "$SUBAGENTS_DIR"/agent-*.jsonl; do
  META_FILE="${AGENT_FILE%.jsonl}.meta.json"
  if [[ -f "$META_FILE" ]]; then
    LABEL="$(jq -r '.description // empty' "$META_FILE")"
    TYPE="$(jq -r '.agentType // empty' "$META_FILE")"
  fi
  [[ -z "${LABEL:-}" ]] && LABEL="$(basename "$AGENT_FILE" .jsonl)"
  [[ -z "${TYPE:-}" ]] && TYPE="unknown"

  STATS="$(stats_for "$AGENT_FILE" sub)"
  TURNS="$(jq -r '.turns' <<<"$STATS")"
  PEAK="$(jq -r '.peak' <<<"$STATS")"
  CUM_BILLED="$(jq -r '.cum_billed' <<<"$STATS")"
  CUM_OUTPUT="$(jq -r '.cum_output' <<<"$STATS")"
  WALLCLOCK="$(format_duration "$(wallclock_seconds "$AGENT_FILE")")"
  RATIO="$(format_ratio "$CUM_BILLED" "$PEAK")"

  SUB_ROWS="${SUB_ROWS}| ${LABEL} | ${TYPE} | ${TURNS} | ${PEAK} | ${CUM_BILLED} | ${CUM_OUTPUT} | ${RATIO} | ${WALLCLOCK} |
"
  TOTAL_CUM_BILLED=$(( TOTAL_CUM_BILLED + CUM_BILLED ))
  TOTAL_CUM_OUTPUT=$(( TOTAL_CUM_OUTPUT + CUM_OUTPUT ))

  if [[ -n "$CEILINGS" ]]; then
    CEILING_LINE="$(grep -E "^${LABEL}: " "$CEILINGS" 2>/dev/null || true)"
    if [[ -n "$CEILING_LINE" ]]; then
      CEILING_VALUE="${CEILING_LINE#*: }"
      if (( PEAK > CEILING_VALUE )); then
        ROW_RESULT="FAIL"
        CEILING_OVERALL="FAIL"
      else
        ROW_RESULT="PASS"
      fi
      CEILING_ROWS="${CEILING_ROWS}| ${LABEL} | ${PEAK} | ${CEILING_VALUE} | ${ROW_RESULT} |
"
    fi
  fi

  unset LABEL TYPE
done

{
  echo "# Run analytics"
  echo
  echo "Source: ${SESSION}"
  echo
  echo "## Orchestrator"
  echo
  echo "- Turns counted: ${ORCH_TURNS}"
  echo "- Peak context: ${ORCH_PEAK} tokens"
  echo "- Cumulative billed input: ${ORCH_CUM_BILLED} tokens"
  echo "- Cumulative output: ${ORCH_CUM_OUTPUT} tokens"
  echo "- Wall clock: ${ORCH_WALLCLOCK}"
  echo
  echo "## Subagents"
  echo
  echo "| Label | Type | Turns | Peak context | Cumulative billed input | Cumulative output | Ratio | Wall clock |"
  echo "| ----- | ---- | ----- | ------------- | ------------------------ | ------------------ | ----- | ---------- |"
  printf '%s' "$SUB_ROWS"
  echo
  echo "## Totals"
  echo
  echo "- Cumulative billed input, whole run: ${TOTAL_CUM_BILLED} tokens"
  echo "- Cumulative output, whole run: ${TOTAL_CUM_OUTPUT} tokens"
  if [[ -n "$CEILINGS" ]]; then
    echo
    echo "## Ceilings"
    echo
    echo "| Label | Peak context | Ceiling | Result |"
    echo "| ----- | ------------- | ------- | ------ |"
    printf '%s' "$CEILING_ROWS"
    echo
    echo "Overall: ${CEILING_OVERALL}"
  fi
} > "$OUTPUT"

echo "written: ${OUTPUT}"

if [[ -n "$CEILINGS" && "$CEILING_OVERALL" == "FAIL" ]]; then
  echo "ceilings: FAIL" >&2
  exit 1
fi

exit 0
