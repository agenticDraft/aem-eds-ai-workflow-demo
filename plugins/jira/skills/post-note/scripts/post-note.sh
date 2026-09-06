#!/usr/bin/env bash
# post-note.sh <item-key> <note-text-file>
#
# tracker.post_note — POST a comment (Atlassian Document Format body) and
# print the result envelope. The note text is read from a file rather than
# an argument so arbitrary text never has to survive shell quoting.
# Credentials (JIRA_SITE, JIRA_EMAIL, JIRA_API_TOKEN) are read from the
# environment and handed to curl via a stdin config block (-K -), never as a
# command-line argument.
#
# Exit codes: 0 with an envelope on stdout for every operational outcome
# (pass or fail); 2 for a usage error (missing argument, file not found).

set -uo pipefail

ITEM_ID="${1:-}"
NOTE_FILE="${2:-}"
if [[ -z "$ITEM_ID" || -z "$NOTE_FILE" ]]; then
  echo "usage: post-note.sh <item-key> <note-text-file>" >&2
  exit 2
fi
if [[ ! -f "$NOTE_FILE" ]]; then
  echo "note text file not found: $NOTE_FILE" >&2
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
BODY_FILE="${OUT_DIR}/post-note-${ITEM_ID}-body.json"
OUT_FILE="${OUT_DIR}/post-note-${ITEM_ID}-response.json"

python3 -c '
import json, sys
with open(sys.argv[1]) as f:
    text = f.read()
doc = {
    "body": {
        "type": "doc",
        "version": 1,
        "content": [{"type": "paragraph", "content": [{"type": "text", "text": text}]}],
    }
}
with open(sys.argv[2], "w") as f:
    json.dump(doc, f)
' "$NOTE_FILE" "$BODY_FILE"

HTTP_CODE="$(curl -sS -K - -X POST --data-binary "@${BODY_FILE}" -H "Content-Type: application/json" \
  -o "$OUT_FILE" -w '%{http_code}' <<EOF
url = "https://${JIRA_SITE}/rest/api/3/issue/${ITEM_ID}/comment"
user = "${JIRA_EMAIL}:${JIRA_API_TOKEN}"
header = "Accept: application/json"
EOF
)"
CURL_EXIT=$?

if [[ $CURL_EXIT -ne 0 ]]; then
  envelope_fail "curl failed (exit ${CURL_EXIT}) posting a note to ${ITEM_ID}."
fi
if [[ "$HTTP_CODE" != "201" ]]; then
  envelope_fail "Jira returned HTTP ${HTTP_CODE} posting a note to ${ITEM_ID}."
fi

cat <<RESULT
## Result
verdict: pass
summary: Posted a note to item ${ITEM_ID}.
artifacts:
  - ${OUT_FILE}
next_action: none
RESULT
