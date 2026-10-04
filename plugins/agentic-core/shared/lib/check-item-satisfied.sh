#!/usr/bin/env bash
# check-item-satisfied.sh — Deterministic reading of a `check_status` envelope
# for the one question the route driver asks before it creates the working
# branch: is this item's work already merged? No model involved.
#
# The branch name is derived from the item id, so a merged change for that
# branch is the item's own earlier delivery. Running the route again would
# plan the delivered work, implement nothing, and be refused at the publish
# gate for an empty change; this check lets the run stop at once instead, with
# a note on the item that says why. It reads only the envelope's own
# `change_state` line (shared/result-envelope.md):
#
#   merged                 → satisfied: the item's change is already merged
#   open | closed | none   → continue: nothing is delivered yet
#   no change_state line   → unknown: the lookup did not succeed, and an
#                            unknown state is never read as "none" or as
#                            "merged"; the run continues and the publish gate's
#                            own empty-change check stays the backstop
#
# Usage:
#   check-item-satisfied.sh <check-status envelope file> <item id>
#
# Output:
#   satisfied TAB <reason>           then  note TAB <the text to post on the item>   (exit 1)
#   continue  TAB change_state=<s>                                                   (exit 0)
#   unknown   TAB <reason>                                                           (exit 0)
#
# Exit codes: 0 — continue or unknown; 1 — satisfied; 2 — usage error (missing
# argument, unreadable file, or a file with no `## Result` block).

set -uo pipefail

ENVELOPE="${1:-}"
ITEM="${2:-}"
if [[ -z "$ENVELOPE" || -z "$ITEM" ]]; then
  echo "usage: check-item-satisfied.sh <check-status envelope file> <item id>" >&2
  exit 2
fi
if [[ ! -f "$ENVELOPE" || ! -r "$ENVELOPE" ]]; then
  echo "invalid: cannot read $ENVELOPE" >&2
  exit 2
fi
if ! grep -q '^## Result$' "$ENVELOPE"; then
  echo "invalid: $ENVELOPE holds no ## Result block" >&2
  exit 2
fi

VERDICT="$(sed -n 's/^verdict:[[:space:]]*//p' "$ENVELOPE" | head -1)"
STATE="$(sed -n 's/^change_state:[[:space:]]*//p' "$ENVELOPE" | head -1)"
SUMMARY="$(sed -n 's/^summary:[[:space:]]*//p' "$ENVELOPE" | head -1)"

case "$STATE" in
  merged)
    printf 'satisfied\tthe change for this item is already merged (%s)\n' "${SUMMARY:-no summary}"
    printf 'note\tAlready satisfied: the change for %s is merged (%s). Nothing is left to deliver, so this run stopped before creating a branch. Close the item, or say what is still missing and run it again.\n' "$ITEM" "${SUMMARY:-no summary}"
    exit 1 ;;
  open|closed|none)
    printf 'continue\tchange_state=%s\n' "$STATE"
    exit 0 ;;
  "")
    printf 'unknown\tthe lookup carried no change_state (verdict %s: %s)\n' "${VERDICT:-?}" "${SUMMARY:-no summary}"
    exit 0 ;;
  *)
    printf 'unknown\tunrecognised change_state %s\n' "$STATE"
    exit 0 ;;
esac
