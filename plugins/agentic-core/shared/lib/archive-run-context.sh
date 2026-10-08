#!/usr/bin/env bash
# Run: bash plugins/agentic-core/shared/lib/archive-run-context.sh .ai/run-context .ai/logs .ai/progress.md .ai/route-progress.txt
#
# archive-run-context.sh <run-context dir> <archive root> [extra file ...]
#
# Moves everything a previous run left in the run-context directory — every
# entry, hidden ones included, plus each listed extra file that exists — into
# one new directory under the archive root, and leaves the run-context
# directory present and empty except for plugin-roots/, the root registry,
# which this session's SessionStart hooks wrote and resolve-plugin-root.sh
# reads for the rest of the run. A fresh run then reads nothing an earlier run
# wrote: a marker, a report or a merged manifest from last time cannot be
# taken for this run's own. The record is kept, not deleted, so a stopped
# run can still be read afterwards.
#
# The archive directory is named run-context-<UTC date>-<UTC time>; a second
# call within the same second gets a numeric suffix. Nothing to move is an
# ordinary outcome, reported and not failed, so a first run on a clean
# checkout and a repeated call both exit 0. A resumed run must not call this:
# the directory holds the run it is resuming.
#
# Exit codes: 0 — "archived: <n> entries -> <dir>" or "archived: nothing to
# move"; 2 — usage error, or an entry that could not be moved (what was
# already moved stays in the archive, and the message names the entry).

set -uo pipefail

usage() {
  echo "usage: archive-run-context.sh <run-context dir> <archive root> [extra file ...]" >&2
  if [ "$#" -gt 0 ]; then echo "$1" >&2; fi
  exit 2
}

[ "$#" -ge 2 ] || usage "expected a run-context directory and an archive root"
CONTEXT_DIR="$1"
ARCHIVE_ROOT="$2"
shift 2

[ -e "$CONTEXT_DIR" ] && [ ! -d "$CONTEXT_DIR" ] && usage "'$CONTEXT_DIR' exists and is not a directory"
[ -e "$ARCHIVE_ROOT" ] && [ ! -d "$ARCHIVE_ROOT" ] && usage "'$ARCHIVE_ROOT' exists and is not a directory"

mkdir -p "$CONTEXT_DIR" || usage "could not create '$CONTEXT_DIR'"

ENTRIES=()
for entry in "$CONTEXT_DIR"/* "$CONTEXT_DIR"/.[!.]* "$CONTEXT_DIR"/..?*; do
  [ -e "$entry" ] || [ -L "$entry" ] || continue
  [ "$entry" = "$CONTEXT_DIR/plugin-roots" ] && continue
  ENTRIES+=("$entry")
done
for extra in "$@"; do
  [ -e "$extra" ] || [ -L "$extra" ] || continue
  ENTRIES+=("$extra")
done

if [ "${#ENTRIES[@]}" -eq 0 ]; then
  echo "archived: nothing to move"
  exit 0
fi

mkdir -p "$ARCHIVE_ROOT" || usage "could not create '$ARCHIVE_ROOT'"

STAMP="$(date -u +%Y-%m-%d-%H%M%S)"
TARGET="$ARCHIVE_ROOT/run-context-$STAMP"
n=1
while [ -e "$TARGET" ]; do
  n=$((n + 1))
  TARGET="$ARCHIVE_ROOT/run-context-$STAMP-$n"
done
mkdir "$TARGET" || usage "could not create '$TARGET'"

MOVED=0
for entry in "${ENTRIES[@]}"; do
  if ! mv "$entry" "$TARGET/"; then
    echo "archived: $MOVED entries -> $TARGET, then stopped" >&2
    usage "could not move '$entry'"
  fi
  MOVED=$((MOVED + 1))
done

echo "archived: $MOVED entries -> $TARGET"
exit 0
