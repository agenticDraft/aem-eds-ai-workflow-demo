#!/usr/bin/env bash
# evaluate-stage-conditions.sh — Deterministic evaluation of a platform pack's
# per-stage conditions against a fact record (see shared/pack-manifest.md for
# the condition grammar and shared/fact-record.md for the record). No model
# involved.
#
# A stage with no `when:` always runs. A `when:` is a list of blocks: any block
# matching runs the stage, and within one block every key must match. A key may
# name a fact-record field and nothing else — never the environment, a previous
# stage's output, or the clock — so a run's shape depends on the work item and
# on nothing about the machine it runs on.
#
# Conditions are evaluated once, as soon as the fact record exists. That record
# is written once and never rewritten, so a stage's skip state cannot change
# part way through a run.
#
# Usage:
#   evaluate-stage-conditions.sh <path-to-pack.yaml> <path-to-fact-record.yaml>
#
# Output, one line per stage in list order:
#   run: <stage id>
#   skipped: <stage id> — <canonical rendering of the condition that skipped it>
#
# Exit codes:
#   0 — evaluated
#   1 — contract violation (a `when:` key that is not a fact-record field, a
#       value outside the field's kind, a malformed block); "invalid: <reason>"
#       on stderr
#   2 — usage error (missing argument, file not found)

set -uo pipefail

PACK="${1:-}"
FACT="${2:-}"

if [[ -z "$PACK" || -z "$FACT" ]]; then
  echo "usage: evaluate-stage-conditions.sh <path-to-pack.yaml> <path-to-fact-record.yaml>" >&2
  exit 2
fi
for f in "$PACK" "$FACT"; do
  [[ -f "$f" ]] || { echo "invalid: file not found: $f" >&2; exit 2; }
done

fail() {
  echo "invalid: $1" >&2
  exit 1
}

# The fact-record fields a condition may name, in declaration order — that
# order is also the one a block's keys are rendered in, so one condition has
# exactly one string form. Each field carries its kind, which fixes the values
# a condition may compare it against:
#   list   — `present` (non-empty) or `empty`
#   bool   — `true` or `false`
#   string — any literal, compared for equality
FACT_FIELDS=(item_id item_type labels components files_named
             design_source design_mentioned
             has_description has_acceptance_criteria
             has_reproduction_url has_reproduction_steps)
FACT_KINDS=(string string list list list
            bool bool
            bool bool
            bool bool)

field_kind() {
  local want="$1" i
  for i in "${!FACT_FIELDS[@]}"; do
    [[ "${FACT_FIELDS[$i]}" == "$want" ]] && { echo "${FACT_KINDS[$i]}"; return 0; }
  done
  return 1
}

# --- read the fact record: a flat "key: value" file, every key optional -----
FACT_KEYS=()
FACT_VALS=()
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -z "${line//[[:space:]]/}" ]] && continue
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  [[ "$line" =~ ^([A-Za-z0-9_]+):[[:space:]]*(.*)$ ]] || continue
  key="${BASH_REMATCH[1]}"
  val="${BASH_REMATCH[2]}"
  val="${val%"${val##*[![:space:]]}"}"
  FACT_KEYS+=("$key")
  FACT_VALS+=("$val")
done < "$FACT"

fact_get() {
  local want="$1" i
  for i in "${!FACT_KEYS[@]}"; do
    [[ "${FACT_KEYS[$i]}" == "$want" ]] && { echo "${FACT_VALS[$i]}"; return 0; }
  done
  return 1
}

# one_key_matches <field> <kind> <wanted value> — the record's own value for
# that field against what the condition asks for.
one_key_matches() {
  local field="$1" kind="$2" want="$3"
  local have
  have="$(fact_get "$field" || true)"

  case "$kind" in
    list)
      # An absent list and an empty one are the same thing to a reader of the
      # fact record, so both count as `empty`.
      local stripped="${have//[[:space:]]/}"
      if [[ -z "$stripped" || "$stripped" == "[]" || "$stripped" == "null" ]]; then
        [[ "$want" == "empty" ]]
      else
        [[ "$want" == "present" ]]
      fi
      ;;
    *)
      # A field the record does not carry, or carries as null, matches nothing:
      # it was never determined, and guessing is what the record forbids.
      [[ -n "$have" && "$have" != "null" ]] || return 1
      [[ "$have" == "$want" ]]
      ;;
  esac
}

# --- walk the manifest's stage list -----------------------------------------
LINES=()
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -z "${line//[[:space:]]/}" ]] && continue
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  LINES+=("$line")
done < "$PACK"
n=${#LINES[@]}

cursor=0
while (( cursor < n )) && [[ "${LINES[cursor]}" != "stages:" ]]; do
  cursor=$((cursor + 1))
done
(( cursor >= n )) && fail "no 'stages:' key found in $PACK"
cursor=$((cursor + 1))

emitted=0

while [[ "${LINES[cursor]:-}" =~ ^\ \ -\ id:\ (.+)$ ]]; do
  stage_id="${BASH_REMATCH[1]}"
  cursor=$((cursor + 1))

  [[ "${LINES[cursor]:-}" =~ ^\ \ \ \ skill:\ (.+)$ ]] \
    || fail "stage '$stage_id' is missing its 'skill'"
  cursor=$((cursor + 1))

  rendered=""
  any_block_matched=0
  has_when=0

  if [[ "${LINES[cursor]:-}" =~ ^\ \ \ \ when:$ ]]; then
    has_when=1
    cursor=$((cursor + 1))
    blocks=()
    while [[ "${LINES[cursor]:-}" =~ ^\ \ \ \ \ \ -\ \{(.*)\}[[:space:]]*$ ]]; do
      body="${BASH_REMATCH[1]}"
      cursor=$((cursor + 1))

      keys=() vals=()
      IFS=',' read -ra pairs <<< "$body"
      for pair in "${pairs[@]}"; do
        pair="${pair#"${pair%%[![:space:]]*}"}"
        pair="${pair%"${pair##*[![:space:]]}"}"
        [[ -z "$pair" ]] && continue
        [[ "$pair" =~ ^([A-Za-z0-9_]+):[[:space:]]*(.+)$ ]] \
          || fail "stage '$stage_id' has a malformed condition entry: '$pair'"
        k="${BASH_REMATCH[1]}"
        v="${BASH_REMATCH[2]}"
        v="${v%"${v##*[![:space:]]}"}"
        kind="$(field_kind "$k" || true)"
        [[ -n "$kind" ]] \
          || fail "stage '$stage_id' has a 'when:' key that is not a fact-record field: '$k'"
        case "$kind" in
          list) [[ "$v" == "present" || "$v" == "empty" ]] \
                  || fail "stage '$stage_id' compares list field '$k' against '$v' — use 'present' or 'empty'" ;;
          bool) [[ "$v" == "true" || "$v" == "false" ]] \
                  || fail "stage '$stage_id' compares boolean field '$k' against '$v' — use 'true' or 'false'" ;;
        esac
        keys+=("$k"); vals+=("$v")
      done
      [[ ${#keys[@]} -eq 0 ]] && fail "stage '$stage_id' has an empty 'when:' block"

      # Every key in a block must match for the block to match.
      block_matched=1
      for i in "${!keys[@]}"; do
        one_key_matches "${keys[$i]}" "$(field_kind "${keys[$i]}")" "${vals[$i]}" || { block_matched=0; break; }
      done
      (( block_matched )) && any_block_matched=1

      block_str=""
      for field in "${FACT_FIELDS[@]}"; do
        for i in "${!keys[@]}"; do
          if [[ "${keys[$i]}" == "$field" ]]; then
            [[ -n "$block_str" ]] && block_str+=" AND "
            block_str+="$field=${vals[$i]}"
          fi
        done
      done
      blocks+=("$block_str")
    done

    [[ ${#blocks[@]} -eq 0 ]] \
      && fail "stage '$stage_id' has 'when:' present but no condition blocks — omit the key instead"

    for b in "${blocks[@]}"; do
      [[ -n "$rendered" ]] && rendered+=" OR "
      rendered+="$b"
    done
  fi

  if [[ "${LINES[cursor]:-}" =~ ^\ \ \ \ fix_attempts:\ .+$ ]]; then
    cursor=$((cursor + 1))
  fi

  if (( has_when == 0 || any_block_matched )); then
    echo "run: $stage_id"
  else
    echo "skipped: $stage_id — $rendered"
  fi
  emitted=$((emitted + 1))
done

(( emitted == 0 )) && fail "the stage list has no entries"

exit 0
