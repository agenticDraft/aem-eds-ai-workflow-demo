#!/usr/bin/env bash
# fetch-item.sh <item-key>
#
# tracker.fetch_item — GET the work item and print the result envelope.
# Credentials (JIRA_SITE, JIRA_EMAIL, JIRA_API_TOKEN) are read from the
# environment and handed to curl via a stdin config block (-K -), never as a
# command-line argument, so they never appear in `ps -ef` or a log.
#
# Exit codes: 0 with an envelope on stdout for every operational outcome
# (pass or fail); 2 for a usage error (missing argument).

set -uo pipefail

ITEM_ID="${1:-}"
if [[ -z "$ITEM_ID" ]]; then
  echo "usage: fetch-item.sh <item-key>" >&2
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

OUT_DIR=".ai/tracker"
mkdir -p "$OUT_DIR"
OUT_FILE="${OUT_DIR}/fetch-item-${ITEM_ID}.json"

HTTP_CODE="$(curl -sS -K - -o "$OUT_FILE" -w '%{http_code}' <<EOF
url = "https://${JIRA_SITE}/rest/api/3/issue/${ITEM_ID}"
user = "${JIRA_EMAIL}:${JIRA_API_TOKEN}"
header = "Accept: application/json"
EOF
)"
CURL_EXIT=$?

if [[ $CURL_EXIT -ne 0 ]]; then
  envelope_fail "curl failed (exit ${CURL_EXIT}) fetching item ${ITEM_ID}."
fi
if [[ "$HTTP_CODE" != "200" ]]; then
  envelope_fail "Jira returned HTTP ${HTTP_CODE} fetching item ${ITEM_ID}."
fi

FIELD_SUMMARY="$(python3 -c '
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
fields = data.get("fields", {})
issuetype = fields.get("issuetype", {}).get("name", "?")
status = fields.get("status", {}).get("name", "?")
print(f"type={issuetype} status={status}")
' "$OUT_FILE" 2>/dev/null)"
[[ -z "$FIELD_SUMMARY" ]] && FIELD_SUMMARY="fields unavailable"

cat <<RESULT
## Result
verdict: pass
summary: Fetched item ${ITEM_ID} (${FIELD_SUMMARY}) and wrote its fields to disk.
artifacts:
  - ${OUT_FILE}
next_action: none
RESULT
