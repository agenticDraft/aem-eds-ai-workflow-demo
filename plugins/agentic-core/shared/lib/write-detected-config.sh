#!/usr/bin/env bash
# write-detected-config.sh — Mechanical merge of the detected commands/paths
# sections into a project config file (see shared/project-config.md). No
# judgment involved: the caller has already detected and confirmed the
# values with a human; this script only places them in the fixed shape.
#
# Writes exactly two of the six sections defined in shared/project-config.md
# — `commands` and `paths`. It never touches `packs`, `routes` or `limits`:
# those are not detectable from a project's own files (they come from a
# pack-generation step and a tracker query), so a file this script produces
# standalone will not pass validate-project-config.sh until another step
# adds the remaining sections.
#
# Usage:
#   write-detected-config.sh <config-path> <lint> <test> <build> <serve> <spec_dir> <preview>
#
# Behavior:
#   - <config-path> does not exist: creates it with `version: 1` plus the
#     `commands:` and `paths:` blocks, in that order.
#   - <config-path> exists: it must already contain a `commands:` block
#     (four fixed subkeys) and a `paths:` block (two fixed subkeys) — i.e.
#     one this script wrote before. Their values are replaced in place;
#     every other line in the file is left untouched.
#
# `commands` subkeys (lint, test, build, serve) may be empty strings — an
# empty value means "not detected", per shared/project-config.md. `paths`
# subkeys (spec_dir, preview) must be non-empty, matching the same contract.
#
# Exit codes:
#   0 — success; "written: <path>" or "updated: <path>" on stdout
#   1 — contract violation: an empty paths value, a value containing a
#       double quote (would corrupt the quoted-string shape), or an
#       existing file missing the expected commands:/paths: blocks
#   2 — usage error: wrong argument count

set -uo pipefail

if [[ $# -ne 7 ]]; then
  echo "usage: write-detected-config.sh <config-path> <lint> <test> <build> <serve> <spec_dir> <preview>" >&2
  exit 2
fi

CONFIG_PATH="$1"
LINT="$2"
TEST_CMD="$3"
BUILD="$4"
SERVE="$5"
SPEC_DIR="$6"
PREVIEW="$7"

fail() {
  echo "invalid: $1" >&2
  exit 1
}

for pair in "lint:$LINT" "test:$TEST_CMD" "build:$BUILD" "serve:$SERVE" "spec_dir:$SPEC_DIR" "preview:$PREVIEW"; do
  key="${pair%%:*}"
  value="${pair#*:}"
  [[ "$value" == *'"'* ]] && fail "commands/paths value for '$key' contains a double quote, which would corrupt the quoted-string shape"
done

[[ -z "$SPEC_DIR" ]] && fail "paths.spec_dir is empty"
[[ -z "$PREVIEW" ]] && fail "paths.preview is empty"

commands_block() {
  cat <<EOF
commands:
  lint: "$LINT"
  test: "$TEST_CMD"
  build: "$BUILD"
  serve: "$SERVE"
EOF
}

paths_block() {
  cat <<EOF
paths:
  spec_dir: "$SPEC_DIR"
  preview: "$PREVIEW"
EOF
}

if [[ ! -f "$CONFIG_PATH" ]]; then
  {
    echo "version: 1"
    echo
    commands_block
    echo
    paths_block
  } > "$CONFIG_PATH"
  echo "written: $CONFIG_PATH"
  exit 0
fi

# --- update path: splice into an existing file ----------------------------
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

cmd_idx=$(find_line "commands:") || fail "existing file has no 'commands:' block"
path_idx=$(find_line "paths:") || fail "existing file has no 'paths:' block"

# The blocks this script owns are always exactly 5 lines (commands:) and
# 3 lines (paths:), in the shape this script itself writes.
cmd_block_len=5
path_block_len=3

for ((i = 0; i < 4; i++)); do
  subkey_line="${LINES[cmd_idx + 1 + i]}"
  [[ "$subkey_line" =~ ^\ \ [a-z]+:\ \" ]] || fail "existing 'commands:' block is not in the expected shape"
done
for ((i = 0; i < 2; i++)); do
  subkey_line="${LINES[path_idx + 1 + i]}"
  [[ "$subkey_line" =~ ^\ \ [a-z_]+:\ \" ]] || fail "existing 'paths:' block is not in the expected shape"
done

OUT=()
i=0
while ((i < n)); do
  if ((i == cmd_idx)); then
    while IFS= read -r line; do OUT+=("$line"); done < <(commands_block)
    i=$((i + cmd_block_len))
    continue
  fi
  if ((i == path_idx)); then
    while IFS= read -r line; do OUT+=("$line"); done < <(paths_block)
    i=$((i + path_block_len))
    continue
  fi
  OUT+=("${LINES[i]}")
  i=$((i + 1))
done

printf '%s\n' "${OUT[@]}" > "$CONFIG_PATH"
echo "updated: $CONFIG_PATH"
exit 0
