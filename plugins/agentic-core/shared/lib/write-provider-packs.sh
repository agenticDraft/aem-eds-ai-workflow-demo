#!/usr/bin/env bash
# write-provider-packs.sh — Mechanical merge of the
# packs.tracker/packs.scm/packs.design values into a project config file (see
# shared/project-config.md). No judgment involved: the caller has already
# detected and confirmed the values with a human; this script only places
# them in the fixed shape.
#
# Writes exactly three of the five sub-keys under `packs:` — `tracker`, `scm`
# and `design`. It never touches `packs.platform` or `packs.browser`: no pack
# for either role is selected by this script, so a file it produces
# standalone will not pass validate-project-config.sh until another step adds
# the remaining sub-keys.
#
# The three are written together, as one block, because the block is replaced
# wholesale rather than edited line by line. A caller with a value for only
# one of them has not finished detecting; it either carries the other two
# forward from the file it is updating, or it has nothing to write yet.
#
# Usage:
#   write-provider-packs.sh <config-path> <tracker> <scm> <design>
#
# Behavior:
#   - <config-path> does not exist: creates its parent directory if needed,
#     then creates it with `version: 1` plus a `packs:` block holding only
#     `tracker`, `scm` and `design`.
#   - <config-path> exists and already has a `packs:` block in a shape this
#     script wrote — tracker/scm, with or without a following design — the
#     whole block is replaced; every other line in the file is left untouched.
#   - <config-path> exists, has a `version:` line, but no `packs:` block yet
#     (the shape write-detected-config.sh alone produces): a `packs:` block
#     is inserted immediately after `version:` (and the blank line that
#     follows it, if any); every other line is left untouched.
#
# Unlike commands/paths values, a pack name is written unquoted — see
# shared/project-config.md's own example (`platform: example-platform`).
#
# Exit codes:
#   0 — success; "written: <path>" or "updated: <path>" on stdout
#   1 — contract violation: an empty tracker/scm/design value, a value containing a
#       double quote (would corrupt the line), an existing `packs:` block
#       not in the shape this script wrote, or no `version:` line to anchor
#       an insertion against
#   2 — usage error: wrong argument count

set -uo pipefail

if [[ $# -ne 4 ]]; then
  echo "usage: write-provider-packs.sh <config-path> <tracker> <scm> <design>" >&2
  exit 2
fi

CONFIG_PATH="$1"
TRACKER="$2"
SCM="$3"
DESIGN="$4"

fail() {
  echo "invalid: $1" >&2
  exit 1
}

for pair in "tracker:$TRACKER" "scm:$SCM" "design:$DESIGN"; do
  key="${pair%%:*}"
  value="${pair#*:}"
  [[ -z "$value" ]] && fail "packs.${key} is empty"
  [[ "$value" == *'"'* ]] && fail "packs.${key} value contains a double quote, which would corrupt the line"
done

# Sub-key order is the config schema's own: platform, tracker, scm, design,
# browser. The two this script does not write are simply absent, so what it
# writes is a prefix-consistent slice of that order rather than a reordering.
packs_block() {
  cat <<EOF
packs:
  tracker: $TRACKER
  scm: $SCM
  design: $DESIGN
EOF
}

if [[ ! -f "$CONFIG_PATH" ]]; then
  mkdir -p "$(dirname "$CONFIG_PATH")"
  {
    echo "version: 1"
    echo
    packs_block
  } > "$CONFIG_PATH"
  echo "written: $CONFIG_PATH"
  exit 0
fi

# --- update/insert path: splice into an existing file ----------------------
# Read line-by-line into an array rather than a single builtin call, for
# portability across installed shell versions (the same reason
# validate-project-config.sh reads this way).
LINES=()
while IFS= read -r line || [[ -n "$line" ]]; do
  LINES+=("$line")
done < "$CONFIG_PATH"
n=${#LINES[@]}

find_line() {
  local pattern="$1"
  local i
  for ((i = 0; i < n; i++)); do
    [[ "${LINES[i]}" == "$pattern" ]] && { echo "$i"; return 0; }
  done
  return 1
}

if packs_idx=$(find_line "packs:"); then
  # Two shapes are recognised, because a file written before this script grew
  # its third sub-key is still a file this script owns: the header plus
  # tracker/scm (3 lines), or the header plus tracker/scm/design (4 lines).
  # Either is replaced wholesale by the current block; anything else is a
  # block this script did not write and must not rewrite blind.
  SHAPE="'packs:' followed by tracker/scm, optionally then design"
  [[ "${LINES[packs_idx + 1]:-}" =~ ^\ \ tracker:\  ]] || fail "existing 'packs:' block is not in the expected shape ($SHAPE)"
  [[ "${LINES[packs_idx + 2]:-}" =~ ^\ \ scm:\  ]] || fail "existing 'packs:' block is not in the expected shape ($SHAPE)"
  if [[ "${LINES[packs_idx + 3]:-}" =~ ^\ \ design:\  ]]; then
    packs_block_len=4
  else
    packs_block_len=3
  fi

  OUT=()
  i=0
  while ((i < n)); do
    if ((i == packs_idx)); then
      while IFS= read -r line; do OUT+=("$line"); done < <(packs_block)
      i=$((i + packs_block_len))
      continue
    fi
    OUT+=("${LINES[i]}")
    i=$((i + 1))
  done

  printf '%s\n' "${OUT[@]}" > "$CONFIG_PATH"
  echo "updated: $CONFIG_PATH"
  exit 0
fi

version_idx=$(find_line "version: 1") || {
  # version's integer isn't fixed at 1 forever — fall back to a pattern match
  # for any "version: <int>" line before failing.
  for ((i = 0; i < n; i++)); do
    [[ "${LINES[i]}" =~ ^version:\ [0-9]+$ ]] && { version_idx=$i; break; }
  done
  [[ -z "${version_idx:-}" ]] && fail "no 'version:' line found to insert a 'packs:' block after"
}

insert_at=$((version_idx + 1))
if [[ "${LINES[insert_at]:-}" == "" ]]; then
  insert_at=$((insert_at + 1))
fi

OUT=()
i=0
while ((i < n)); do
  if ((i == insert_at)); then
    while IFS= read -r line; do OUT+=("$line"); done < <(packs_block)
    OUT+=("")
  fi
  OUT+=("${LINES[i]}")
  i=$((i + 1))
done
if ((insert_at == n)); then
  OUT+=("")
  while IFS= read -r line; do OUT+=("$line"); done < <(packs_block)
fi

printf '%s\n' "${OUT[@]}" > "$CONFIG_PATH"
echo "updated: $CONFIG_PATH"
exit 0
