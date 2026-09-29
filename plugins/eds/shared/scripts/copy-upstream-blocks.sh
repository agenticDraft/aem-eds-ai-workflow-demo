#!/usr/bin/env bash
# copy-upstream-blocks.sh — Copies every block the work item names that the
# reuse check answered `upstream=` into `<project-root>/blocks/<name>/`, as the
# starting point the item's own changes are then applied to (D528).
#
# Each copied file's first line is the change notice Apache-2.0 §4(b) asks of a
# modified copy, naming the upstream repo, path and pinned commit; the
# upstream bytes follow unchanged. Every copied file is a `.css` or `.js`
# (the only kinds the collection's blocks hold), so `/* … */` fits both.
#
# prototype, plan and implement all call this. Whichever runs first while
# `blocks/<name>/` is absent copies; for a later call the reuse check already
# answers `reuse=`, so nothing is copied and nothing is overwritten. No stage
# copies by hand or picks the names itself.
#
# Usage:
#   copy-upstream-blocks.sh <path-to-fact-record.yaml> [project-root] [manifest]
#
# Output:
#   copied=blocks/<name>/<file>   # one line per file copied
#   copied=(none)                 # when nothing was copied
#   upstream_unknown=<name>       # manifest missing or malformed: nothing to
#                                 # copy from; the caller warns, builds it new
#   upstream_manifest=...         # passed through from the reuse check
#
# Exit codes:
#   0 — decided (every branch above)
#   1 — a copy failed
#   2 — usage error
#
# Reads from disk only; never touches the network. Bash 3.2-safe.

set -uo pipefail

FACT="${1:-}"
ROOT="${2:-.}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="${3:-$SCRIPT_DIR/../block-collection/manifest.txt}"
CHECK="$SCRIPT_DIR/../../skills/eds-conventions-component-reuse/scripts/check-component-reuse.sh"

if [[ -z "$FACT" ]]; then
  echo "usage: copy-upstream-blocks.sh <path-to-fact-record.yaml> [project-root] [manifest]" >&2
  exit 2
fi

answer="$(bash "$CHECK" "$FACT" "$ROOT" "$MANIFEST")" || exit $?
SRC_BLOCKS="$(dirname "$MANIFEST")/blocks"
# The reuse check has already validated the manifest whenever it answered `upstream=`.
REPO="$(sed -n 's/^repo=//p' "$MANIFEST" 2>/dev/null | head -n 1)"
REPO="${REPO%.git}"
PIN="$(sed -n 's/^upstream_manifest=\([0-9a-f]\{40\}\)$/\1/p' <<< "$answer")"

seen=" "
copied=0
while IFS= read -r line; do
  case "$line" in
    upstream_manifest=*|upstream_unknown=*) echo "$line" ;;
    upstream=*)
      name="${line#upstream=}"
      name="$(basename "$name")"; name="${name%.*}"
      [[ "$seen" == *" $name "* ]] && continue
      seen="$seen$name "
      dest="$ROOT/blocks/$name"
      # The reuse check saw no directory; a plain file in the way is not ours to replace.
      [[ -e "$dest" ]] && { echo "copy-upstream-blocks: $dest exists and is not a block directory" >&2; exit 1; }
      mkdir -p "$dest" || exit 1
      for f in "$SRC_BLOCKS/$name"/*; do
        [[ -f "$f" ]] || continue
        case "$f" in
          *.css|*.js) ;;
          *) echo "copy-upstream-blocks: no comment syntax for $f" >&2; exit 1 ;;
        esac
        {
          echo "/* Changed in this project. Derived from $REPO blocks/$name/$(basename "$f") at $PIN, Apache-2.0. */"
          cat "$f"
        } > "$dest/$(basename "$f")" || exit 1
        echo "copied=blocks/$name/$(basename "$f")"
        copied=$((copied + 1))
      done
      ;;
  esac
done <<< "$answer"

[[ $copied -eq 0 ]] && echo "copied=(none)"
exit 0
