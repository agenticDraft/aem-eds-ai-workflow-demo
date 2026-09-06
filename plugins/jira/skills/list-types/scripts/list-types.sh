#!/usr/bin/env bash
# list-types.sh <project-key>
#
# tracker.list_types — GET the issue types valid for a project (the
# createmeta issue-types endpoint) and print the result envelope.
# Credentials (JIRA_SITE, JIRA_EMAIL, JIRA_API_TOKEN) are read from the
# environment and handed to curl via a stdin config block (-K -), never as a
# command-line argument.
#
# Exit codes: 0 with an envelope on stdout for every operational outcome
# (pass or fail); 2 for a usage error (missing argument).

set -uo pipefail

PROJECT="${1:-}"
if [[ -z "$PROJECT" ]]; then
  echo "usage: list-types.sh <project-key>" >&2
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
OUT_FILE="${OUT_DIR}/list-types-${PROJECT}.json"

HTTP_CODE="$(curl -sS -K - -o "$OUT_FILE" -w '%{http_code}' <<EOF
url = "https://${JIRA_SITE}/rest/api/3/issue/createmeta/${PROJECT}/issuetypes"
user = "${JIRA_EMAIL}:${JIRA_API_TOKEN}"
header = "Accept: application/json"
EOF
)"
CURL_EXIT=$?

if [[ $CURL_EXIT -ne 0 ]]; then
  envelope_fail "curl failed (exit ${CURL_EXIT}) listing issue types for project ${PROJECT}."
fi
if [[ "$HTTP_CODE" != "200" ]]; then
  envelope_fail "Jira returned HTTP ${HTTP_CODE} listing issue types for project ${PROJECT}."
fi

TYPE_COUNT="$(python3 -c '
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
print(len(data.get("issueTypes", [])))
' "$OUT_FILE" 2>/dev/null)"
[[ -z "$TYPE_COUNT" ]] && TYPE_COUNT="an unknown number of"

cat <<RESULT
## Result
verdict: pass
summary: Listed ${TYPE_COUNT} issue type(s) for project ${PROJECT}.
artifacts:
  - ${OUT_FILE}
next_action: none
RESULT
