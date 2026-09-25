#!/usr/bin/env bash
# check-fix-budget.sh — Deterministic answer to "may this stage make another
# edit?" for a stage's internal fix loop (see shared/fix-loop.md). One fix
# attempt is one edit: a stage whose budget is N makes up to N edits and N+1
# checks. No model involved and no side effects — the stage asks before each
# edit and acts on the printed decision; it never counts against the number
# itself. Whether the last check improved on the one before is not asked
# here: that stays the stage's own judgment.
#
# The budget is the stage's own `fix_attempts` in the pack manifest, or, when
# the stage declares none, `limits.fix_attempts_default` in the project config.
#
# Usage:
#   check-fix-budget.sh <path-to-pack.yaml> <path-to-project-config.yaml> <stage id> <edits-made>
#
# Exit codes and the "decision:" line they print:
#   0 — decision: edit        (edits-made is below the budget; "fix_attempts:",
#                               "source:", "edits_made:" and "edits_left_after:" follow)
#   4 — decision: exhausted   (edits-made has reached the budget; the stage ends its
#                               loop on its last check's findings)
#   1 — decision: terminate-contract-violation ("invalid: <reason>" on stderr — a
#                               malformed edits-made count, a malformed or missing
#                               budget, or a stage id the pack does not declare)
#   2 — usage error (wrong argument count, pack manifest or project config not found)

set -uo pipefail

if [[ $# -ne 4 ]]; then
  echo "usage: check-fix-budget.sh <path-to-pack.yaml> <path-to-project-config.yaml> <stage id> <edits-made>" >&2
  exit 2
fi

PACK="$1"
CONFIG="$2"
STAGE_ID="$3"
EDITS_MADE="$4"

for f in "$PACK" "$CONFIG"; do
  if [[ ! -f "$f" ]]; then
    echo "invalid: file not found: $f" >&2
    exit 2
  fi
done

fail() {
  echo "invalid: $1" >&2
  echo "decision: terminate-contract-violation"
  exit 1
}

[[ "$EDITS_MADE" =~ ^(0|[1-9][0-9]*)$ ]] || fail "edits-made '$EDITS_MADE' is not a non-negative integer"

# --- the stage's own entry: from "  - id: <stage>" to the next entry or key --
# Read inside the top-level `stages:` list only — other lists (artifacts) use
# the same "  - id:" shape and may reuse a stage's id. Prints "found" once the
# entry exists, then its fix_attempts value if any.
STAGE_LOOKUP="$(awk -v id="$STAGE_ID" '
  /^[^ ]/                   { in_stages = ($0 ~ /^stages:[ ]*$/); in_stage = 0; next }
  in_stages && /^  - id: / { in_stage = ($0 == "  - id: " id); if (in_stage) print "found"; next }
  in_stage && /^    fix_attempts:/ { sub(/^    fix_attempts:[ ]*/, ""); print "value:" $0 }
' "$PACK")"

[[ "$STAGE_LOOKUP" == found* ]] || fail "stage '$STAGE_ID' is not declared in $PACK"

BUDGET=""
SOURCE=""
if [[ "$STAGE_LOOKUP" == *"value:"* ]]; then
  BUDGET="${STAGE_LOOKUP#*value:}"
  SOURCE="stage"
  [[ "$BUDGET" =~ ^[1-9][0-9]*$ ]] \
    || fail "stage '$STAGE_ID' has a non-positive-integer 'fix_attempts': '$BUDGET'"
else
  # --- limits.fix_attempts_default in the project config -------------------
  BUDGET="$(awk '
    /^limits:/ { in_limits = 1; next }
    /^[^ ]/    { in_limits = 0 }
    in_limits && /^  fix_attempts_default:/ { sub(/^  fix_attempts_default:[ ]*/, ""); print; exit }
  ' "$CONFIG")"
  SOURCE="default"
  [[ -n "$BUDGET" ]] \
    || fail "stage '$STAGE_ID' declares no 'fix_attempts' and $CONFIG has no 'limits.fix_attempts_default'"
  [[ "$BUDGET" =~ ^(0|[1-9][0-9]*)$ ]] \
    || fail "'limits.fix_attempts_default' is not a non-negative integer: '$BUDGET'"
fi

if (( EDITS_MADE < BUDGET )); then
  echo "decision: edit"
  echo "fix_attempts: $BUDGET"
  echo "source: $SOURCE"
  echo "edits_made: $EDITS_MADE"
  echo "edits_left_after: $((BUDGET - EDITS_MADE - 1))"
  exit 0
fi

echo "decision: exhausted"
echo "fix_attempts: $BUDGET"
echo "source: $SOURCE"
echo "edits_made: $EDITS_MADE"
exit 4
