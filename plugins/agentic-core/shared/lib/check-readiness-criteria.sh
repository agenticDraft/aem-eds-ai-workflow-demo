#!/usr/bin/env bash
# check-readiness-criteria.sh — The whole deterministic check behind the
# `readiness` gate (see shared/readiness-criteria.md, core contract §4). No
# model involved: unlike `plan-gate`/`publish-gate`, this gate has no
# judgment half at all — every criterion it states is answerable by
# comparing the fact record against the pack manifest, so this script is the
# entire gate, not a first pass before a reviewing model.
#
# Checks two things:
#   1. The fact record's item_type has a declared `readiness_criteria` entry
#      in the pack manifest, and every field that entry requires holds —
#      `true` for a boolean field, `present` (non-empty) for a list field,
#      non-null/non-empty for a string field. Kind comes from
#      shared/fact-record.md, the same closed vocabulary
#      evaluate-stage-conditions.sh uses for `when:`.
#   2. The fixed rule shared/fact-record.md states directly (§5): an item
#      whose text asks for a visual change but carries no design reference
#      — `design_mentioned: true` and `design_source: false` — is never
#      ready, regardless of what the pack declares for its item_type.
#
# Usage:
#   check-readiness-criteria.sh <path-to-pack.yaml> <path-to-fact-record.yaml>
#
# Exit codes:
#   0 — every criterion holds; "valid: readiness (<item_type>, <n> fields
#       checked)" on stdout
#   1 — a criterion fails, including an item_type with no declared
#       criteria; "invalid: <reason>" on stderr
#   2 — usage error (missing argument, file not found, fact record has no
#       usable item_type, pack manifest has no 'readiness_criteria:' key)

set -uo pipefail

PACK="${1:-}"
FACT="${2:-}"

if [[ -z "$PACK" || -z "$FACT" ]]; then
  echo "usage: check-readiness-criteria.sh <path-to-pack.yaml> <path-to-fact-record.yaml>" >&2
  exit 2
fi
for f in "$PACK" "$FACT"; do
  [[ -f "$f" ]] || { echo "invalid: file not found: $f" >&2; exit 2; }
done

usage_error() {
  echo "invalid: $1" >&2
  exit 2
}

fail() {
  echo "invalid: $1" >&2
  exit 1
}

# The fact-record fields a readiness criterion may require, and the kind
# that fixes what "required" means for each — identical to
# evaluate-stage-conditions.sh's own closed vocabulary, since
# shared/fact-record.md defines both from the one Format block.
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

# --- read the fact record: a flat "key: value" file, every key optional ----
FACT_KEYS=()
FACT_VALS=()
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -z "${line//[[:space:]]/}" ]] && continue
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  [[ "$line" =~ ^([A-Za-z0-9_]+):[[:space:]]*(.*)$ ]] || continue
  key="${BASH_REMATCH[1]}"
  val="${BASH_REMATCH[2]}"
  val="${val%"${val##*[![:space:]]}"}"
  val="${val%\"}"; val="${val#\"}"
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

ITEM_TYPE="$(fact_get item_type || true)"
[[ -n "$ITEM_TYPE" && "$ITEM_TYPE" != "null" ]] \
  || usage_error "fact record '$FACT' has no usable item_type"

# field_holds <field> — true if a required field's own value satisfies
# "required" for its kind: `true` for bool, non-empty for list, non-null/
# non-empty for string. Absent or `null` never satisfies any kind — a field
# the fact record could not determine can never count as met.
field_holds() {
  local field="$1" kind have
  kind="$(field_kind "$field" || true)"
  [[ -n "$kind" ]] || fail "readiness_criteria.$ITEM_TYPE requires a field that is not in the fact record: '$field'"
  have="$(fact_get "$field" || true)"
  case "$kind" in
    list)
      local stripped="${have//[[:space:]]/}"
      [[ -n "$stripped" && "$stripped" != "[]" && "$stripped" != "null" ]]
      ;;
    bool)
      [[ "$have" == "true" ]]
      ;;
    *)
      [[ -n "$have" && "$have" != "null" ]]
      ;;
  esac
}

field_condition() {
  local field="$1" kind
  kind="$(field_kind "$field" || true)"
  case "$kind" in
    list) echo "present" ;;
    bool) echo "true" ;;
    *) echo "non-empty" ;;
  esac
}

field_found() {
  local field="$1" have
  have="$(fact_get "$field" || true)"
  [[ -n "$have" && "$have" != "null" ]] && { echo "$have"; return; }
  echo "absent"
}

# --- walk the pack manifest's readiness_criteria block ----------------------
LINES=()
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -z "${line//[[:space:]]/}" ]] && continue
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  LINES+=("$line")
done < "$PACK"
n=${#LINES[@]}

cursor=0
while (( cursor < n )) && [[ "${LINES[cursor]}" != "readiness_criteria:" ]]; do
  cursor=$((cursor + 1))
done
(( cursor >= n )) && usage_error "no 'readiness_criteria:' key found in $PACK"
cursor=$((cursor + 1))

FOUND_TYPE=0
REQUIRED_FIELDS=()
while [[ "${LINES[cursor]:-}" =~ ^\ \ ([A-Za-z0-9_.-]+):$ ]]; do
  item_type="${BASH_REMATCH[1]}"
  cursor=$((cursor + 1))

  [[ "${LINES[cursor]:-}" =~ ^\ \ \ \ require:\ \[(.*)\]$ ]] \
    || usage_error "readiness_criteria.$item_type is missing its 'require' list"
  require_body="${BASH_REMATCH[1]}"
  cursor=$((cursor + 1))

  if [[ "$item_type" == "$ITEM_TYPE" ]]; then
    FOUND_TYPE=1
    IFS=',' read -ra raw_fields <<< "$require_body"
    for raw in "${raw_fields[@]:-}"; do
      f="${raw#"${raw%%[![:space:]]*}"}"
      f="${f%"${f##*[![:space:]]}"}"
      [[ -n "$f" ]] && REQUIRED_FIELDS+=("$f")
    done
  fi
done

# `readiness` (core contract §4): "An item_type with no declared criteria
# returns fail naming the missing declaration — it never falls through to
# another type's rules and never guesses." This is a gate verdict, not a
# usage error: exit 1.
(( FOUND_TYPE )) \
  || fail "item_type '$ITEM_TYPE' has no declared readiness criteria"

for field in "${REQUIRED_FIELDS[@]}"; do
  field_holds "$field" \
    || fail "item_type '$ITEM_TYPE' requires '$field' to be $(field_condition "$field"), found $(field_found "$field")"
done

# The fixed rule shared/fact-record.md states directly (§5): "wanted but
# absent" — the text asks for a visual change and none is attached — is
# terminal at this gate, independent of what the pack declares per
# item_type. Only fires when both fields are actually determined; a field
# the fact record could not resolve is never treated as a match either way.
DESIGN_MENTIONED="$(fact_get design_mentioned || true)"
DESIGN_SOURCE="$(fact_get design_source || true)"
if [[ "$DESIGN_MENTIONED" == "true" && "$DESIGN_SOURCE" == "false" ]]; then
  fail "design_mentioned is true but design_source is false — the item asks for a visual change with no design reference attached"
fi

echo "valid: readiness ($ITEM_TYPE, ${#REQUIRED_FIELDS[@]} fields checked)"
exit 0
