#!/usr/bin/env bash
# Run: bash plugins/agentic-core/shared/lib/derive-branch-name.sh <item id>
#
# derive-branch-name.sh <item-id>
#
# Turns a work item's id into the branch name a run works on. Deterministic and
# total: the same id always yields the same name, so a resumed run, a re-run,
# and a second machine all arrive at the same branch without any of them having
# to agree on one first. Nothing here is a judgement, which is why it is a
# script and not a line of prose asking a caller to pick a name.
#
# The id is lowercased, every run of characters outside a-z0-9 becomes a single
# separator, and leading and trailing separators are dropped. An id that leaves
# nothing usable is refused rather than turned into a name nobody could have
# predicted.
#
# No length limit is applied. A platform that needs one — some hosting tools
# derive a hostname from the branch and cap its length — applies it where that
# constraint is declared, not here, because the core knows of no such limit.
#
# Exit codes: 0 with the name on stdout; 2 for a usage error or an id that
# yields no valid name.

set -uo pipefail

usage() {
  echo "usage: derive-branch-name.sh <item-id>" >&2
  if [ "$#" -gt 0 ]; then echo "$1" >&2; fi
  exit 2
}

[ "$#" -eq 1 ] || usage "expected exactly 1 argument"

ITEM_ID="$1"
[ -n "$ITEM_ID" ] || usage "the item id is empty"

NAME="$(printf '%s' "$ITEM_ID" \
  | tr '[:upper:]' '[:lower:]' \
  | sed -e 's/[^a-z0-9]\{1,\}/-/g' -e 's/^-\{1,\}//' -e 's/-\{1,\}$//')"

[ -n "$NAME" ] || usage "item id '$ITEM_ID' leaves no usable branch name"

# git's own grammar, not a guess at one — the same check the scm operation
# applies before the name reaches any command as an argument.
git check-ref-format --branch "$NAME" >/dev/null 2>&1 \
  || usage "item id '$ITEM_ID' yields '$NAME', which is not a valid branch name"

printf '%s\n' "$NAME"
exit 0
