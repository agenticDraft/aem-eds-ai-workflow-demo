#!/usr/bin/env bash
# attach-file.sh <item-key> <file-path>
#
# tracker.attach_file — POST a multipart file attachment and print the
# result envelope. `X-Atlassian-Token: no-check` is required by Jira Cloud
# on this endpoint to bypass XSRF protection for the attachment upload.
# Credentials (JIRA_SITE, JIRA_EMAIL, JIRA_API_TOKEN) are read from the
# environment and handed to curl via a stdin config block (-K -), never as a
# command-line argument.
#
# Exit codes: 0 with an envelope on stdout for every operational outcome
# (pass or fail); 2 for a usage error (missing argument, file not found).

set -uo pipefail

ITEM_ID="${1:-}"
FILE_PATH="${2:-}"
if [[ -z "$ITEM_ID" || -z "$FILE_PATH" ]]; then
  echo "usage: attach-file.sh <item-key> <file-path>" >&2
  exit 2
fi
if [[ ! -f "$FILE_PATH" ]]; then
  echo "file not found: $FILE_PATH" >&2
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
OUT_FILE="${OUT_DIR}/attach-file-${ITEM_ID}-response.json"

HTTP_CODE="$(curl -sS -K - -X POST -H "X-Atlassian-Token: no-check" -F "file=@${FILE_PATH}" \
  -o "$OUT_FILE" -w '%{http_code}' <<EOF
url = "https://${JIRA_SITE}/rest/api/3/issue/${ITEM_ID}/attachments"
user = "${JIRA_EMAIL}:${JIRA_API_TOKEN}"
header = "Accept: application/json"
EOF
)"
CURL_EXIT=$?

if [[ $CURL_EXIT -ne 0 ]]; then
  envelope_fail "curl failed (exit ${CURL_EXIT}) attaching a file to ${ITEM_ID}."
fi
if [[ "$HTTP_CODE" != "200" ]]; then
  envelope_fail "Jira returned HTTP ${HTTP_CODE} attaching a file to ${ITEM_ID}."
fi

cat <<RESULT
## Result
verdict: pass
summary: Attached ${FILE_PATH##*/} to item ${ITEM_ID}.
artifacts:
  - ${OUT_FILE}
next_action: none
RESULT
