#!/usr/bin/env bash
# append-css-custom-properties.sh — Adopts a source stylesheet's :root
# custom properties into a target stylesheet's own :root block, as new
# declarations only. Never renames, removes or overwrites a property the
# target already declares — adopting a design system's values is not the
# same operation as deciding which of the project's own token names should
# carry them (that remapping is a human's own call, out of scope here).
#
# Reads only the first `:root { ... }` block in each file — a flat block,
# one declaration per line, no nested braces. Both this script's own
# fixtures and every stylesheet it is known to run against hold that shape;
# a file that does not is a usage error, not something to guess a fix for.
#
# Usage:
#   append-css-custom-properties.sh <target-css> <source-css>
#
# Exit codes:
#   0 — success; "appended: <n> properties to <target-css>" (or
#       "no new properties" if every source property already exists there)
#   1 — contract violation: no :root block found in one of the files
#   2 — usage error: wrong argument count, file not found

set -uo pipefail

TARGET="${1:-}"
SOURCE="${2:-}"
if [[ -z "$TARGET" || -z "$SOURCE" ]]; then
  echo "usage: append-css-custom-properties.sh <target-css> <source-css>" >&2
  exit 2
fi
if [[ ! -f "$TARGET" ]]; then
  echo "target file not found: $TARGET" >&2
  exit 2
fi
if [[ ! -f "$SOURCE" ]]; then
  echo "source file not found: $SOURCE" >&2
  exit 2
fi

fail() {
  echo "invalid: $1" >&2
  exit 1
}

# extract_root_declarations <file> — prints one custom-property declaration
# line per line of output, from the file's first `:root { ... }` block.
extract_root_declarations() {
  awk '
    /^:root[[:space:]]*\{/ { in_root = 1; found = 1; next }
    in_root && /^\}/ { in_root = 0; exit }
    in_root && /^[[:space:]]*--[A-Za-z0-9-]+[[:space:]]*:/ { print }
    END { if (!found) exit 3 }
  ' "$1"
}

SOURCE_DECLS="$(extract_root_declarations "$SOURCE")" || fail "no :root block found in $SOURCE"
TARGET_DECLS="$(extract_root_declarations "$TARGET")" || fail "no :root block found in $TARGET"

# Property name (the part before the first ':') of every declaration the
# target already has, one per line, for a membership test below.
EXISTING_NAMES="$(printf '%s\n' "$TARGET_DECLS" | sed -E 's/^[[:space:]]*(--[A-Za-z0-9-]+).*/\1/')"

NEW_DECLS=()
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  name="$(printf '%s' "$line" | sed -E 's/^[[:space:]]*(--[A-Za-z0-9-]+).*/\1/')"
  if ! grep -qxF -- "$name" <<< "$EXISTING_NAMES"; then
    # Re-indent to two spaces, matching this project's own stylesheet
    # convention, regardless of the source file's own indentation.
    trimmed="$(printf '%s' "$line" | sed -E 's/^[[:space:]]*//')"
    NEW_DECLS+=("  $trimmed")
  fi
done <<< "$SOURCE_DECLS"

if [[ ${#NEW_DECLS[@]} -eq 0 ]]; then
  echo "no new properties"
  exit 0
fi

# Insert the new declarations immediately before the target's :root block's
# own closing brace — the first `}` line after the first `:root {` line.
# A plain read/print loop, not awk with an embedded-newline -v assignment,
# since not every awk implementation this might run under accepts one.
TMP_FILE="$(mktemp "${TMPDIR:-/tmp}/append-css-custom-properties.XXXXXX")"
trap 'rm -f "$TMP_FILE"' EXIT

in_root=0
inserted=0
while IFS= read -r line || [[ -n "$line" ]]; do
  if [[ $inserted -eq 0 && $in_root -eq 0 && "$line" =~ ^:root[[:space:]]*\{ ]]; then
    in_root=1
    printf '%s\n' "$line"
    continue
  fi
  if [[ $inserted -eq 0 && $in_root -eq 1 && "$line" =~ ^\} ]]; then
    for decl in "${NEW_DECLS[@]}"; do
      printf '%s\n' "$decl"
    done
    inserted=1
    in_root=0
    printf '%s\n' "$line"
    continue
  fi
  printf '%s\n' "$line"
done < "$TARGET" > "$TMP_FILE"

mv "$TMP_FILE" "$TARGET"
trap - EXIT

echo "appended: ${#NEW_DECLS[@]} properties to $TARGET"
exit 0
