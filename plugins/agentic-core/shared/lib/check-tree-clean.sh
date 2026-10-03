#!/usr/bin/env bash
# Run: bash plugins/agentic-core/shared/lib/check-tree-clean.sh <project-root>
#
# check-tree-clean.sh <project-root> — the fresh-start tree guard.
#
# A fresh run must begin on a tree with nothing in it the run did not write.
# The publish gate reviews, and the deliver stage publishes, everything in
# list-changed-files.sh's change set; a path already in that set before the
# run began would be published unreviewed, or refused by the gate only at
# the end of the run. This guard asks the same script for the same set
# before anything of the run exists, so the two can never disagree: every
# tracked change against the merge base of origin/HEAD and HEAD (edited,
# staged, deleted, or committed on this branch only) and every untracked
# path the ignore rules do not exclude.
#
# It reads and never writes. A resumed run must not call this: its tree
# holds the run being resumed, and this check at its fresh start is what
# guarantees that everything dirty on resume is the run's own.
#
# Exit codes:
#   0 — "clean: no change and no untracked path"
#   1 — "refused: <n> paths changed before this run", then one
#       "changed: <path>" line per path, sorted, each once
#   2 — usage error, or the change set could not be computed (the
#       reason from list-changed-files.sh is passed through on stderr)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIST="$SCRIPT_DIR/list-changed-files.sh"

ROOT="${1:-}"
if [[ -z "$ROOT" || ! -d "$ROOT" || $# -ne 1 ]]; then
  echo "usage: check-tree-clean.sh <project-root>" >&2
  exit 2
fi

CHANGED="$(bash "$LIST" "$ROOT")" || exit 2

if [[ -z "$CHANGED" ]]; then
  echo "clean: no change and no untracked path"
  exit 0
fi

COUNT="$(printf '%s\n' "$CHANGED" | grep -c .)"
echo "refused: $COUNT paths changed before this run"
printf '%s\n' "$CHANGED" | sed 's/^/changed: /'
exit 1
