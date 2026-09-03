#!/usr/bin/env bash
# validate-pack-manifest.sh — Deterministic conformance check for a pack
# manifest (see shared/pack-manifest.md). No model involved: this is the
# CI floor a pack.yaml must clear before the runner resolves anything from
# it.
#
# Checks the fixed shape shared/pack-manifest.md defines, branching on
# `kind`:
#
#   platform — `stages` is a non-empty mapping of stage id to skill name;
#     every entry in `always_autonomous` and every artifact's
#     `produced_by` names a stage id present in `stages`; every skill
#     named anywhere resolves to <pack root>/skills/<skill>/SKILL.md.
#
#   provider — `role` is one of the four core roles; every key in
#     `operations` and every entry in `unsupported` is an operation that
#     role actually has; the two sets are disjoint; together they cover
#     every operation the role has (an operation in neither is a contract
#     violation); every skill named in `operations` resolves to
#     <pack root>/skills/<skill>/SKILL.md.
#
# The pack root is the directory containing the manifest, matching
# "pack.yaml at the pack root".
#
# Usage:
#   validate-pack-manifest.sh <path-to-pack.yaml>
#
# Exit codes:
#   0 — conformant; "valid: <kind>" on stdout
#   1 — contract violation; "invalid: <reason>" on stderr
#   2 — usage error (no argument, file not found)

set -uo pipefail

FILE="${1:-}"

if [[ -z "$FILE" ]]; then
  echo "usage: validate-pack-manifest.sh <path-to-pack.yaml>" >&2
  exit 2
fi

if [[ ! -f "$FILE" ]]; then
  echo "invalid: file not found: $FILE" >&2
  exit 2
fi

PACK_ROOT="$(cd "$(dirname "$FILE")" && pwd)"

fail() {
  echo "invalid: $1" >&2
  exit 1
}

# --- unfilled template placeholder (core contract §13 validator 10) -------
# A pack generated from a template (core contract §7.1) must contain no
# unfilled placeholder anywhere under its root — not just in pack.yaml, but
# in every generated skill file too, since that is where an unanswered
# interview question would actually leak. The reserved marker is the
# literal two-character sequence "{{", which never appears in a
# conformant pack.yaml or SKILL.md.
PLACEHOLDER_HIT="$(grep -rl '{{' "$PACK_ROOT" 2>/dev/null | head -n 1)"
if [[ -n "$PLACEHOLDER_HIT" ]]; then
  fail "unfilled template placeholder in ${PLACEHOLDER_HIT#$PACK_ROOT/}"
fi

skill_exists() {
  local skill="$1"
  [[ -f "$PACK_ROOT/skills/$skill/SKILL.md" ]]
}

# Read the file into an indexed array one line at a time, stripping blank
# lines and full-line comments, for maximum portability across shell
# versions.
LINES=()
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -z "${line//[[:space:]]/}" ]] && continue
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  LINES+=("$line")
done < "$FILE"
n=${#LINES[@]}
cursor=0

MATCH=""
require_line() {
  local regex="$1" desc="$2"
  local line="${LINES[cursor]:-}"
  if [[ "$line" =~ $regex ]]; then
    cursor=$((cursor + 1))
    MATCH="${BASH_REMATCH[1]:-}"
  else
    fail "expected $desc, got '${line:-<end of file>}'"
  fi
}

# bracket_list <text> — splits "a, b, c" (already stripped of [ ]) into a
# newline-separated list on the global LIST array; empty text yields an
# empty array.
LIST=()
bracket_list() {
  local text="$1"
  LIST=()
  local trimmed="${text//[[:space:]]/}"
  [[ -z "$trimmed" ]] && return
  IFS=',' read -ra LIST <<< "$trimmed"
}

require_line '^kind: (platform|provider)$' "'kind: platform' or 'kind: provider'"
kind="$MATCH"

if [[ "$kind" == "platform" ]]; then
  # --- stages --------------------------------------------------------------
  require_line '^stages:$' "'stages:'"
  STAGE_IDS=()
  STAGE_SKILLS=()
  while [[ "${LINES[cursor]:-}" =~ ^\ \ ([A-Za-z0-9_-]+):\ (.+)$ ]]; do
    STAGE_IDS+=("${BASH_REMATCH[1]}")
    STAGE_SKILLS+=("${BASH_REMATCH[2]}")
    cursor=$((cursor + 1))
  done
  if [[ ${#STAGE_IDS[@]} -eq 0 ]]; then
    fail "stages has no entries"
  fi

  stage_known() {
    local id="$1"
    for existing in "${STAGE_IDS[@]}"; do
      [[ "$existing" == "$id" ]] && return 0
    done
    return 1
  }

  for i in "${!STAGE_IDS[@]}"; do
    skill_exists "${STAGE_SKILLS[$i]}" \
      || fail "stages.${STAGE_IDS[$i]} names a nonexistent skill: '${STAGE_SKILLS[$i]}'"
  done

  # --- always_autonomous -----------------------------------------------------
  require_line '^always_autonomous: \[(.*)\]$' "'always_autonomous: [<stage id>, …]'"
  bracket_list "$MATCH"
  for id in "${LIST[@]:-}"; do
    [[ -z "$id" ]] && continue
    stage_known "$id" || fail "always_autonomous binds an unknown stage: '$id'"
  done

  # --- artifacts ---------------------------------------------------------
  require_line '^artifacts:( \[\])?$' "'artifacts:' or 'artifacts: []'"
  if [[ -z "$MATCH" ]]; then
    while [[ "${LINES[cursor]:-}" =~ ^\ \ -\ id:\ (.+)$ ]]; do
      cursor=$((cursor + 1))
      [[ "${LINES[cursor]:-}" =~ ^\ \ \ \ produced_by:\ (.+)$ ]] \
        || fail "an artifact is missing its 'produced_by' stage id"
      producer="${BASH_REMATCH[1]}"
      cursor=$((cursor + 1))
      stage_known "$producer" || fail "an artifact binds an unknown stage as producer: '$producer'"
      [[ "${LINES[cursor]:-}" =~ ^\ \ \ \ path:\ \".*\"$ ]] \
        || fail "an artifact is missing its 'path'"
      cursor=$((cursor + 1))
    done
  fi

  if (( cursor < n )); then
    fail "unexpected content after 'artifacts:': '${LINES[cursor]}'"
  fi

  echo "valid: platform"
  exit 0
fi

if [[ "$kind" == "provider" ]]; then
  require_line '^role: (tracker|scm|design|browser)$' "'role: tracker|scm|design|browser'"
  role="$MATCH"

  case "$role" in
    tracker) ROLE_OPS=(fetch_item post_note attach_file list_types) ;;
    scm)     ROLE_OPS=(create_branch publish_change check_status) ;;
    design)  ROLE_OPS=(fetch_reference) ;;
    browser) ROLE_OPS=(render capture measure) ;;
  esac

  op_known() {
    local op="$1"
    for existing in "${ROLE_OPS[@]}"; do
      [[ "$existing" == "$op" ]] && return 0
    done
    return 1
  }

  # --- operations ------------------------------------------------------------
  require_line '^operations:( \{\})?$' "'operations:' or 'operations: {}'"
  OP_NAMES=()
  OP_SKILLS=()
  if [[ -z "$MATCH" ]]; then
    while [[ "${LINES[cursor]:-}" =~ ^\ \ ([A-Za-z0-9_]+):\ (.+)$ ]]; do
      OP_NAMES+=("${BASH_REMATCH[1]}")
      OP_SKILLS+=("${BASH_REMATCH[2]}")
      cursor=$((cursor + 1))
    done
  fi
  for name in "${OP_NAMES[@]:-}"; do
    op_known "$name" || fail "operations declares an operation unknown to role '$role': '$name'"
  done
  for i in "${!OP_NAMES[@]}"; do
    skill_exists "${OP_SKILLS[$i]}" \
      || fail "operations.${OP_NAMES[$i]} names a nonexistent skill: '${OP_SKILLS[$i]}'"
  done

  # --- unsupported -------------------------------------------------------
  require_line '^unsupported: \[(.*)\]$' "'unsupported: [<operation name>, …]'"
  bracket_list "$MATCH"
  UNSUPPORTED=("${LIST[@]:-}")
  for name in "${UNSUPPORTED[@]:-}"; do
    [[ -z "$name" ]] && continue
    op_known "$name" || fail "unsupported declares an operation unknown to role '$role': '$name'"
    for implemented in "${OP_NAMES[@]:-}"; do
      [[ "$implemented" == "$name" ]] && fail "operation '$name' is both implemented and declared unsupported"
    done
  done

  # --- completeness: every role operation is implemented or unsupported ---
  for op in "${ROLE_OPS[@]}"; do
    found=0
    for implemented in "${OP_NAMES[@]:-}"; do
      [[ "$implemented" == "$op" ]] && found=1
    done
    for unsup in "${UNSUPPORTED[@]:-}"; do
      [[ "$unsup" == "$op" ]] && found=1
    done
    if [[ "$found" -eq 0 ]]; then
      fail "operation '$op' is neither implemented nor declared unsupported"
    fi
  done

  if (( cursor < n )); then
    fail "unexpected content after 'unsupported:': '${LINES[cursor]}'"
  fi

  echo "valid: provider"
  exit 0
fi
