#!/usr/bin/env bash
# validate-pack-manifest.sh — Deterministic conformance check for a pack
# manifest (see shared/pack-manifest.md). No model involved: this is the
# CI floor a pack.yaml must clear before anything resolves a stage from it.
#
# Checks the fixed shape shared/pack-manifest.md defines, branching on
# `kind`:
#
#   platform — `stages` is a non-empty ordered list, each entry an `id` from
#     the fifteen-id vocabulary and a `skill`, optionally a `when:` condition
#     and a `fix_attempts` override; the list begins with intake and ends
#     with deliver, neither carrying a condition; every `when:` key and every
#     readiness criterion names a real fact-record field; `readiness_criteria`
#     declares at least one item type; every entry in `always_autonomous` and
#     every artifact's `produced_by` names a declared stage; every skill
#     resolves and declares isolated execution; and route.dot agrees with the
#     stage list node for node. Two further, optional keys — `onboarding_
#     state_path` and `audit_findings_path` (D80) — each, when present, must
#     be a well-formed relative path: non-empty, not absolute, no `..`
#     segment. Neither is checked for existence here; that is pre-flight's
#     job at runtime, against a real project. A third optional key,
#     `evidence_manifest` (D86), when present, must name an artifact id this
#     same pack registers in its own `artifacts:` list above.
#
#   provider — `role` is one of the four core roles; every key in
#     `operations` and every entry in `unsupported` is an operation that
#     role actually has; the two sets are disjoint; together they cover
#     every operation the role has; every skill named in `operations`
#     resolves. An optional `scripts` key (D95) maps an operation already in
#     `operations` to a script path, relative to the pack root, that must
#     also resolve — the shell-executable form of that operation, for a
#     caller that must run it as a subprocess rather than through `Skill()`.
#     The tracker role may carry `text_conventions`.
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

# --- the closed vocabularies ------------------------------------------------
# The fifteen stage ids the core defines, in route order. A pack implements an
# id or declines it; it may never add one.
STAGE_VOCAB=(intake readiness extract conventions serve baseline prototype
             verify-design plan plan-gate implement verify lint publish-gate
             deliver)

# The fact-record fields a condition or a readiness criterion may name, in the
# order shared/fact-record.md declares them — that order is also the one the
# canonical rendering sorts a condition block's keys into. The test suite
# asserts this list still equals that file's own Format block, so the two
# cannot drift apart silently.
#
# Each field carries its kind, which fixes the values a condition may compare
# it against: a list field takes `present` or `empty`, a boolean field takes
# `true` or `false`, a string field takes any literal.
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

in_list() {
  local needle="$1"; shift
  local item
  for item in "$@"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

# --- unfilled template placeholder ------------------------------------------
# A generated pack must contain no unfilled placeholder anywhere under its
# root — not just in pack.yaml, but in every generated skill file too, since
# that is where an unanswered interview question would actually leak. The
# reserved marker is the literal two-character sequence "{{".
PLACEHOLDER_HIT="$(grep -rl '{{' "$PACK_ROOT" 2>/dev/null | head -n 1)"
if [[ -n "$PLACEHOLDER_HIT" ]]; then
  fail "unfilled template placeholder in ${PLACEHOLDER_HIT#$PACK_ROOT/}"
fi

skill_exists() {
  [[ -f "$PACK_ROOT/skills/$1/SKILL.md" ]]
}

# A declared value is a legitimate relative path: non-empty, not absolute, no
# '..' segment. Shared by every optional path-shaped key this manifest
# carries — platform's onboarding_state_path/audit_findings_path (D80) and
# provider's scripts (D95) alike.
validate_declared_path() {
  local key="$1" value="$2"
  [[ -n "$value" ]] || fail "'$key' is present but empty — omit the key instead"
  [[ "$value" != /* ]] || fail "'$key' must be a relative path, not absolute: '$value'"
  case "/$value/" in
    */../*) fail "'$key' may not contain a '..' path segment: '$value'" ;;
  esac
}

# Every skill a platform pack's stage list names must declare isolated
# execution in its own frontmatter — the literal key is "context: fork". Read
# as a flat scan of the lines between the file's first two "---" delimiters.
skill_declares_isolated_execution() {
  local skill_file="$PACK_ROOT/skills/$1/SKILL.md"
  local in_frontmatter=0 line
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == "---" ]]; then
      if (( in_frontmatter == 0 )); then in_frontmatter=1; continue; else break; fi
    fi
    if (( in_frontmatter )) && [[ "$line" =~ ^context:\ *fork\ *$ ]]; then
      return 0
    fi
  done < "$skill_file"
  return 1
}

# Read the file into an indexed array one line at a time, stripping blank
# lines and full-line comments, for maximum portability across shell versions.
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
  # --- stages ---------------------------------------------------------------
  require_line '^stages:$' "'stages:'"
  STAGE_IDS=()
  STAGE_SKILLS=()
  STAGE_WHEN=()          # canonical rendering, or "" for an always-on stage

  while [[ "${LINES[cursor]:-}" =~ ^\ \ -\ id:\ (.+)$ ]]; do
    stage_id="${BASH_REMATCH[1]}"
    cursor=$((cursor + 1))

    [[ "${LINES[cursor]:-}" =~ ^\ \ \ \ skill:\ (.+)$ ]] \
      || fail "stage '$stage_id' is missing its 'skill'"
    stage_skill="${BASH_REMATCH[1]}"
    cursor=$((cursor + 1))

    # optional when: — a list of blocks, each an inline mapping
    rendered=""
    if [[ "${LINES[cursor]:-}" =~ ^\ \ \ \ when:$ ]]; then
      cursor=$((cursor + 1))
      blocks=()
      while [[ "${LINES[cursor]:-}" =~ ^\ \ \ \ \ \ -\ \{(.*)\}[[:space:]]*$ ]]; do
        body="${BASH_REMATCH[1]}"
        cursor=$((cursor + 1))

        # Collect this block's key/value pairs, then emit them in
        # fact-record field order so one condition has exactly one string form.
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
          # Validator 12: a condition may only name a fact-record field, and
          # may only compare it against a value of that field's own kind.
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

    if [[ "${LINES[cursor]:-}" =~ ^\ \ \ \ fix_attempts:\ (.+)$ ]]; then
      fa="${BASH_REMATCH[1]}"
      [[ "$fa" =~ ^[1-9][0-9]*$ ]] \
        || fail "stage '$stage_id' has a non-positive 'fix_attempts': '$fa'"
      cursor=$((cursor + 1))
    fi

    # Validator 1: the id must be one of the fifteen the core defines.
    in_list "$stage_id" "${STAGE_VOCAB[@]}" \
      || fail "stage id is not one of the fifteen the core defines: '$stage_id'"
    for seen in "${STAGE_IDS[@]:-}"; do
      [[ "$seen" == "$stage_id" ]] && fail "stage '$stage_id' is declared twice"
    done

    STAGE_IDS+=("$stage_id")
    STAGE_SKILLS+=("$stage_skill")
    STAGE_WHEN+=("$rendered")
  done

  [[ ${#STAGE_IDS[@]} -eq 0 ]] && fail "stages has no entries"

  stage_known() {
    in_list "$1" "${STAGE_IDS[@]}"
  }

  # Validator 2: the list begins with intake, ends with deliver, and neither
  # is conditional.
  last=$(( ${#STAGE_IDS[@]} - 1 ))
  [[ "${STAGE_IDS[0]}" == "intake" ]] \
    || fail "the stage list must begin with 'intake', not '${STAGE_IDS[0]}'"
  [[ "${STAGE_IDS[$last]}" == "deliver" ]] \
    || fail "the stage list must end with 'deliver', not '${STAGE_IDS[$last]}'"
  [[ -z "${STAGE_WHEN[0]}" ]] \
    || fail "'intake' may not carry a 'when:' — every route begins with it"
  [[ -z "${STAGE_WHEN[$last]}" ]] \
    || fail "'deliver' may not carry a 'when:' — every route ends with it"

  for i in "${!STAGE_IDS[@]}"; do
    skill_exists "${STAGE_SKILLS[$i]}" \
      || fail "stage '${STAGE_IDS[$i]}' names a nonexistent skill: '${STAGE_SKILLS[$i]}'"
    skill_declares_isolated_execution "${STAGE_SKILLS[$i]}" \
      || fail "stage '${STAGE_IDS[$i]}' skill '${STAGE_SKILLS[$i]}' does not declare isolated execution ('context: fork') in its frontmatter"
  done

  # --- always_autonomous ----------------------------------------------------
  require_line '^always_autonomous: \[(.*)\]$' "'always_autonomous: [<stage id>, …]'"
  bracket_list "$MATCH"
  for id in "${LIST[@]:-}"; do
    [[ -z "$id" ]] && continue
    stage_known "$id" || fail "always_autonomous binds an unknown stage: '$id'"
  done

  # --- readiness_criteria (validator 13) ------------------------------------
  require_line '^readiness_criteria:( \{\})?$' "'readiness_criteria:' or 'readiness_criteria: {}'"
  CRITERIA_TYPES=()
  if [[ -z "$MATCH" ]]; then
    while [[ "${LINES[cursor]:-}" =~ ^\ \ ([A-Za-z0-9_.-]+):$ ]]; do
      item_type="${BASH_REMATCH[1]}"
      cursor=$((cursor + 1))
      [[ "${LINES[cursor]:-}" =~ ^\ \ \ \ require:\ \[(.*)\]$ ]] \
        || fail "readiness_criteria.$item_type is missing its 'require' list"
      bracket_list "${BASH_REMATCH[1]}"
      cursor=$((cursor + 1))
      [[ ${#LIST[@]} -eq 0 ]] \
        && fail "readiness_criteria.$item_type requires nothing — an item type with no criteria would pass every item"
      for f in "${LIST[@]}"; do
        [[ -z "$f" ]] && continue
        in_list "$f" "${FACT_FIELDS[@]}" \
          || fail "readiness_criteria.$item_type requires a field that is not in the fact record: '$f'"
      done
      CRITERIA_TYPES+=("$item_type")
    done
  fi
  [[ ${#CRITERIA_TYPES[@]} -eq 0 ]] \
    && fail "readiness_criteria declares no item type — a pack with none would fail every item it was given"

  # --- artifacts ------------------------------------------------------------
  require_line '^artifacts:( \[\])?$' "'artifacts:' or 'artifacts: []'"
  ARTIFACT_IDS=()
  if [[ -z "$MATCH" ]]; then
    while [[ "${LINES[cursor]:-}" =~ ^\ \ -\ id:\ (.+)$ ]]; do
      artifact_id="${BASH_REMATCH[1]}"
      cursor=$((cursor + 1))
      [[ "${LINES[cursor]:-}" =~ ^\ \ \ \ produced_by:\ (.+)$ ]] \
        || fail "an artifact is missing its 'produced_by' stage id"
      producer="${BASH_REMATCH[1]}"
      cursor=$((cursor + 1))
      stage_known "$producer" || fail "an artifact binds an unknown stage as producer: '$producer'"
      [[ "${LINES[cursor]:-}" =~ ^\ \ \ \ path:\ \".*\"$ ]] \
        || fail "an artifact is missing its 'path'"
      cursor=$((cursor + 1))
      ARTIFACT_IDS+=("$artifact_id")
    done
  fi

  # --- onboarding-state and audit-findings paths (validator 15, D80) --------
  # Both optional. The core never learns what either path is called beyond
  # this — only that a declared value is a legitimate relative path a later
  # structural read (pre-flight) may test for existence against a real
  # project's working tree. This validator never touches disk for either: a
  # pack has no fixed project to check against.
  if [[ "${LINES[cursor]:-}" =~ ^onboarding_state_path:\ \"(.*)\"$ ]]; then
    validate_declared_path "onboarding_state_path" "${BASH_REMATCH[1]}"
    cursor=$((cursor + 1))
  fi

  if [[ "${LINES[cursor]:-}" =~ ^audit_findings_path:\ \"(.*)\"$ ]]; then
    validate_declared_path "audit_findings_path" "${BASH_REMATCH[1]}"
    cursor=$((cursor + 1))
  fi

  # --- evidence_manifest (validator 16, D86) --------------------------------
  # Optional. When present, it must name an artifact id this same pack
  # registers above, in its own 'artifacts:' list — never an unregistered id,
  # and never a stage id. Checked structurally only: whether the artifact at
  # that id actually carries the evidence-manifest shape is a separate,
  # deterministic check (validate-evidence-manifest.sh) against the file
  # itself, not against this manifest.
  if [[ "${LINES[cursor]:-}" =~ ^evidence_manifest:\ (.+)$ ]]; then
    evidence_manifest_id="${BASH_REMATCH[1]}"
    in_list "$evidence_manifest_id" "${ARTIFACT_IDS[@]:-}" \
      || fail "evidence_manifest names an artifact this pack does not register: '$evidence_manifest_id'"
    cursor=$((cursor + 1))
  fi

  if (( cursor < n )); then
    fail "unexpected content after the last platform key: '${LINES[cursor]}'"
  fi

  # --- route digraph (validator 14) -----------------------------------------
  DOT="$PACK_ROOT/route.dot"
  [[ -f "$DOT" ]] || fail "a platform pack must ship route.dot at its root"

  # A node declaration is a quoted name carrying "[shape=" — an edge line's
  # quoted strings never do, which separates the two without parsing the
  # digraph.
  DOT_NODES=()
  DOT_DASHED=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*\"([^\"]+)\"[[:space:]]*\[([^]]*)\] ]] || continue
    node="${BASH_REMATCH[1]}"
    attrs="${BASH_REMATCH[2]}"
    [[ "$attrs" == *shape=* ]] || continue
    DOT_NODES+=("$node")
    if [[ "$attrs" == *style=dashed* ]]; then DOT_DASHED+=("$node"); fi
  done < "$DOT"

  for node in "${DOT_NODES[@]:-}"; do
    [[ -z "$node" ]] && continue
    stage_known "$node" || fail "route.dot declares a node that is not a declared stage: '$node'"
  done
  for id in "${STAGE_IDS[@]}"; do
    in_list "$id" "${DOT_NODES[@]:-}" || fail "route.dot has no node for declared stage '$id'"
  done

  # Edge labels, keyed by the edge's target node.
  EDGE_TARGETS=()
  EDGE_LABELS=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ \"([^\"]+)\"[[:space:]]*-\>[[:space:]]*\"([^\"]+)\" ]] || continue
    target="${BASH_REMATCH[2]}"
    label=""
    [[ "$line" =~ label=\"([^\"]*)\" ]] && label="${BASH_REMATCH[1]}"
    EDGE_TARGETS+=("$target")
    EDGE_LABELS+=("$label")
  done < "$DOT"

  # Exactly one edge may point into any stage node — "no bypass edges"
  # (shared/pack-manifest.md) means each stage after the first has one path
  # in. A second edge into the same target is a copy/paste leftover or a
  # second, contradictory rendering of the same condition; checked before
  # label_into so a stray duplicate is caught even when the first-seen edge's
  # label happens to match.
  for target in "${EDGE_TARGETS[@]:-}"; do
    [[ -z "$target" ]] && continue
    count=0
    for t in "${EDGE_TARGETS[@]}"; do
      [[ "$t" == "$target" ]] && count=$((count + 1))
    done
    (( count > 1 )) && fail "route.dot: more than one edge points into '$target'"
  done

  label_into() {
    local want="$1" i
    for i in "${!EDGE_TARGETS[@]}"; do
      [[ "${EDGE_TARGETS[$i]}" == "$want" ]] && { echo "${EDGE_LABELS[$i]}"; return 0; }
    done
    return 1
  }

  for i in "${!STAGE_IDS[@]}"; do
    id="${STAGE_IDS[$i]}"
    cond="${STAGE_WHEN[$i]}"
    dashed=1
    in_list "$id" "${DOT_DASHED[@]:-}" || dashed=0

    if [[ -n "$cond" ]]; then
      (( dashed )) \
        || fail "route.dot: conditional stage '$id' is not drawn dashed"
      actual="$(label_into "$id" || true)"
      [[ "$actual" == "$cond" ]] \
        || fail "route.dot: edge label into '$id' is '$actual', but its 'when:' renders as '$cond'"
    else
      (( dashed )) \
        && fail "route.dot: stage '$id' is drawn dashed but carries no 'when:'"
    fi
  done

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
    browser) ROLE_OPS=(render capture measure interact) ;;
  esac

  op_known() {
    in_list "$1" "${ROLE_OPS[@]}"
  }

  # --- operations -----------------------------------------------------------
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
    # An empty name is the expansion of an empty list, not a declared
    # operation: `operations: {}` is a pack that implements nothing yet, which
    # the format allows and a generated skeleton always produces. The
    # unsupported loop below has always guarded this; this one had not.
    [[ -z "$name" ]] && continue
    op_known "$name" || fail "operations declares an operation unknown to role '$role': '$name'"
  done
  for i in "${!OP_NAMES[@]}"; do
    skill_exists "${OP_SKILLS[$i]}" \
      || fail "operations.${OP_NAMES[$i]} names a nonexistent skill: '${OP_SKILLS[$i]}'"
  done

  # --- unsupported ----------------------------------------------------------
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

  # --- completeness ---------------------------------------------------------
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

  # --- scripts (validator 17, D95) -------------------------------------------
  # Optional. Maps an operation already in `operations:` to the path, relative
  # to the pack root, of a script implementing that same operation for a
  # caller that must run it as a subprocess rather than through `Skill()`.
  # Unlike onboarding_state_path/audit_findings_path (a *project's* path,
  # unresolvable here), a scripts: path names a file shipped inside this pack
  # itself, so it is resolved and checked the same way an operations: skill
  # name already is.
  if [[ "${LINES[cursor]:-}" =~ ^scripts:$ ]]; then
    cursor=$((cursor + 1))
    SCRIPT_OPS=()
    SCRIPT_PATHS=()
    while [[ "${LINES[cursor]:-}" =~ ^\ \ ([A-Za-z0-9_]+):\ \"(.*)\"$ ]]; do
      SCRIPT_OPS+=("${BASH_REMATCH[1]}")
      SCRIPT_PATHS+=("${BASH_REMATCH[2]}")
      cursor=$((cursor + 1))
    done
    [[ ${#SCRIPT_OPS[@]} -eq 0 ]] \
      && fail "'scripts:' is present but declares no entries — omit the key instead"
    for i in "${!SCRIPT_OPS[@]}"; do
      op_name="${SCRIPT_OPS[$i]}"
      script_path="${SCRIPT_PATHS[$i]}"
      found=0
      for implemented in "${OP_NAMES[@]:-}"; do
        [[ "$implemented" == "$op_name" ]] && found=1
      done
      [[ "$found" -eq 1 ]] \
        || fail "scripts.$op_name names an operation this pack does not implement in 'operations:'"
      validate_declared_path "scripts.$op_name" "$script_path"
      [[ -f "$PACK_ROOT/$script_path" ]] \
        || fail "scripts.$op_name names a script that does not exist: '$script_path'"
    done
  fi

  # --- text_conventions (tracker only, optional) ----------------------------
  if [[ "${LINES[cursor]:-}" =~ ^text_conventions:$ ]]; then
    [[ "$role" == "tracker" ]] \
      || fail "text_conventions belongs to the tracker role, not '$role'"
    cursor=$((cursor + 1))
    conv_count=0
    while [[ "${LINES[cursor]:-}" =~ ^\ \ (design_keywords|reproduction_headings|acceptance_criteria_headings):\ \[(.*)\]$ ]]; do
      cursor=$((cursor + 1))
      conv_count=$((conv_count + 1))
    done
    [[ $conv_count -eq 0 ]] \
      && fail "text_conventions is present but declares none of 'design_keywords', 'reproduction_headings' or 'acceptance_criteria_headings'"
  fi

  if (( cursor < n )); then
    fail "unexpected content after the last provider key: '${LINES[cursor]}'"
  fi

  echo "valid: provider"
  exit 0
fi
