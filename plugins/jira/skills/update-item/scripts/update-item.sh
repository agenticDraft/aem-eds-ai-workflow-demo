#!/usr/bin/env bash
# update-item.sh <item-key> <draft-file>
#
# tracker.update_item — PUT a work item's description and structured fields
# and print the result envelope. The draft is read from a file rather than an
# argument so arbitrary text never has to survive shell quoting.
# Credentials (JIRA_SITE, JIRA_EMAIL, JIRA_API_TOKEN) are read from the
# environment and handed to curl via a stdin config block (-K -), never as a
# command-line argument.
#
# This replaces the item's description. That is a destructive write on text
# someone may have edited in the tracker, so the previous description is saved
# beside the response before the write and named in the envelope's artifacts —
# an overwrite nobody can undo is worse than one nobody noticed.
#
# Exit codes: 0 with an envelope on stdout for every operational outcome
# (pass or fail); 2 for a usage error (missing argument, file not found).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACK_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
BUILD_FIELDS="$PACK_ROOT/scripts/build-item-fields.py"

ITEM_ID="${1:-}"
DRAFT_FILE="${2:-}"
if [[ -z "$ITEM_ID" || -z "$DRAFT_FILE" ]]; then
  echo "usage: update-item.sh <item-key> <draft-file>" >&2
  exit 2
fi
if [[ ! -f "$DRAFT_FILE" ]]; then
  echo "draft file not found: $DRAFT_FILE" >&2
  exit 2
fi

envelope_fail() {
  cat <<RESULT
## Result
verdict: fail
summary: $1
artifacts: []
next_action: none
RESULT
  exit 0
}

if [[ -z "${JIRA_SITE:-}" || -z "${JIRA_EMAIL:-}" || -z "${JIRA_API_TOKEN:-}" ]]; then
  envelope_fail "JIRA_SITE, JIRA_EMAIL or JIRA_API_TOKEN is not set in the environment."
fi

# ITEM_ID and JIRA_SITE are interpolated into a curl -K config block below.
# A value containing a newline could inject an extra config line (a second
# `url =`, a forged `header =`, even a `user =` pointed at an attacker's
# host) — the item key is tracker-sourced text and must be validated as
# data before it reaches curl's config parser, never trusted as shape-safe.
if [[ ! "$ITEM_ID" =~ ^[A-Za-z][A-Za-z0-9_]*-[0-9]+$ ]]; then
  envelope_fail "the given item_id does not match the Jira key grammar (e.g. ABC-123)."
fi
if [[ ! "$JIRA_SITE" =~ ^[A-Za-z0-9.-]+$ ]]; then
  envelope_fail "JIRA_SITE is not a bare hostname."
fi

OUT_DIR=".ai/tracker"
mkdir -p "$OUT_DIR"
BODY_FILE="${OUT_DIR}/update-item-${ITEM_ID}-body.json"
OUT_FILE="${OUT_DIR}/update-item-${ITEM_ID}-response.json"
PRIOR_FILE="${OUT_DIR}/update-item-${ITEM_ID}-previous.json"

# The conversion refuses to emit a description it cannot reproduce, so a
# failure here means the draft would have been silently altered in the item.
# Reporting it as a failed write is the honest reading: nothing was sent.
BUILD_ERR="$(python3 "$BUILD_FIELDS" "$DRAFT_FILE" --out "$BODY_FILE" 2>&1)"
if [[ $? -ne 0 ]]; then
  envelope_fail "the draft could not be converted without loss — ${BUILD_ERR//$'\n'/ }"
fi

# Keep what is about to be overwritten. A fetch that fails is not fatal: the
# item may not exist, which the write itself will report more precisely.
curl -sS -K - -o "$PRIOR_FILE" <<EOF >/dev/null 2>&1
url = "https://${JIRA_SITE}/rest/api/3/issue/${ITEM_ID}?fields=description,summary"
user = "${JIRA_EMAIL}:${JIRA_API_TOKEN}"
header = "Accept: application/json"
EOF

HTTP_CODE="$(curl -sS -K - -X PUT --data-binary "@${BODY_FILE}" -H "Content-Type: application/json" \
  -o "$OUT_FILE" -w '%{http_code}' <<EOF
url = "https://${JIRA_SITE}/rest/api/3/issue/${ITEM_ID}"
user = "${JIRA_EMAIL}:${JIRA_API_TOKEN}"
header = "Accept: application/json"
EOF
)"
CURL_EXIT=$?

if [[ $CURL_EXIT -ne 0 ]]; then
  envelope_fail "curl failed (exit ${CURL_EXIT}) updating ${ITEM_ID}."
fi
# A rejected field comes back as 400 with the field named in the body. Passing
# that through matters more here than elsewhere: a tracker configured without
# a field the draft carries is a fixable authoring problem, and "HTTP 400" on
# its own tells nobody which field to remove.
if [[ "$HTTP_CODE" == "400" ]]; then
  DETAIL="$(python3 -c '
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    print(""); sys.exit()
parts = list(d.get("errorMessages") or [])
parts += [f"{k}: {v}" for k, v in (d.get("errors") or {}).items()]
print("; ".join(parts)[:150])
' "$OUT_FILE" 2>/dev/null)"
  envelope_fail "Jira rejected the update to ${ITEM_ID} (HTTP 400)${DETAIL:+ — ${DETAIL}}"
fi
if [[ "$HTTP_CODE" != "204" ]]; then
  envelope_fail "Jira returned HTTP ${HTTP_CODE} updating ${ITEM_ID}."
fi

cat <<RESULT
## Result
verdict: pass
summary: Replaced the description and fields of item ${ITEM_ID}.
artifacts:
  - ${BODY_FILE}
  - ${PRIOR_FILE}
next_action: none
RESULT
