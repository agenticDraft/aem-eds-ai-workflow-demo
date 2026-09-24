#!/usr/bin/env bash
# Run: bash plugins/agentic-core/shared/lib/instructions-stamp.sh <instructions-file>
#      bash plugins/agentic-core/shared/lib/instructions-stamp.sh --write <instructions-file>
#
# instructions-stamp.sh [--write] <instructions-file>
#
# Prints the stamp of an instructions file as it exists on disk, and refuses
# to print one that does not match the file's own content.
#
# A caller's instructions can reach it as a copy made earlier than the file
# now on disk. The copy is self-consistent and reads as complete, so nothing
# in it reveals that a step added since is missing. What the copy does carry
# is the stamp that was current when it was made — so a caller comparing the
# stamp it holds against the one this prints can tell the two apart, and only
# then.
#
# The stamp is computed over the file with its own stamp line removed, so the
# value never feeds back into itself and two copies of the same content always
# stamp alike.
#
# `--write` recomputes and rewrites the line. It is idempotent, and it is what
# an author runs after editing the file; a file edited without it fails
# verification, which is the point.
#
# Exit codes: 0 — the file verifies, and its stamp is on stdout; 1 — the file
# carries no stamp, or one that does not match its content; 2 — usage.

set -uo pipefail

usage() {
  echo "usage: instructions-stamp.sh [--write] <instructions-file>" >&2
  if [ "$#" -gt 0 ]; then echo "$1" >&2; fi
  exit 2
}

WRITE=0
if [ "${1:-}" = "--write" ]; then
  WRITE=1
  shift
fi

[ "$#" -eq 1 ] || usage "expected exactly one file"
FILE="$1"
[ -f "$FILE" ] && [ -r "$FILE" ] || usage "'$FILE' is not a readable file"

MARKER="instructions-stamp:"

# The content the stamp covers: everything but the stamp line itself, with
# trailing blank lines dropped. Normalising them is what makes --write
# idempotent -- it appends a blank line before the stamp, and without this the
# next run would hash that blank line and disagree with itself.
content_without_stamp() {
  grep -v -- "$MARKER" "$FILE" \
    | awk '{ lines[NR] = $0; if (NF) last = NR } END { for (i = 1; i <= last; i++) print lines[i] }'
}

COMPUTED="$(content_without_stamp | git hash-object --stdin 2>/dev/null | cut -c1-12)"
if [ -z "$COMPUTED" ]; then
  echo "invalid: could not compute a stamp for '$FILE'" >&2
  exit 1
fi

if [ "$WRITE" -eq 1 ]; then
  TMP="$FILE.stamp.$$"
  {
    content_without_stamp
    printf '\n<!-- %s %s -->\n' "$MARKER" "$COMPUTED"
  } > "$TMP" || { rm -f "$TMP"; echo "invalid: could not write '$FILE'" >&2; exit 1; }
  mv "$TMP" "$FILE"
  echo "stamp: $COMPUTED"
  exit 0
fi

EMBEDDED="$(grep -- "$MARKER" "$FILE" | head -1 | sed -e "s/.*${MARKER}[[:space:]]*//" -e 's/[[:space:]]*-->.*//' -e 's/[[:space:]]*$//')"

if [ -z "$EMBEDDED" ]; then
  echo "invalid: '$FILE' carries no stamp. Regenerate it with --write." >&2
  exit 1
fi

if [ "$EMBEDDED" != "$COMPUTED" ]; then
  echo "invalid: '$FILE' was edited without regenerating its stamp (carries $EMBEDDED, content is $COMPUTED). Regenerate it with --write." >&2
  exit 1
fi

echo "stamp: $COMPUTED"
exit 0
