#!/usr/bin/env bash
# create-item.sh <project-key> <draft-file>
#
# tracker.create_item — POST a new work item and print the result envelope.
# The draft is read from a file rather than an argument so arbitrary text
# never has to survive shell quoting.
# Credentials (JIRA_SITE, JIRA_EMAIL, JIRA_API_TOKEN) are read from the
# environment and handed to curl via a stdin config block (-K -), never as a
# command-line argument.
#
# Unlike every other operation here, this one has a result that does not exist
# until the tracker produces it: the key. The envelope has no field for a
# returned value, so the key is written to an artifact and that artifact is
# named in the envelope's artifacts list — the same way a fetch reports what
# it retrieved. A caller that predicts the key instead is wrong the first time
# two items are created at once.
#
# Exit codes: 0 with an envelope on stdout for every operational outcome
# (pass or fail); 2 for a usage error (missing argument, file not found).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACK_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
BUILD_FIELDS="$PACK_ROOT/scripts/build-item-fields.py"

PROJECT_KEY="${1:-}"
DRAFT_FILE="${2:-}"
if [[ -z "$PROJECT_KEY" || -z "$DRAFT_FILE" ]]; then
  echo "usage: create-item.sh <project-key> <draft-file>" >&2
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

# PROJECT_KEY and JIRA_SITE are interpolated into a curl -K config block below.
# A value containing a newline could inject an extra config line (a second
# `url =`, a forged `header =`, even a `user =` pointed at an attacker's
# host). This operation takes no item key — there is none yet — so the project
# key is the argument that reaches the config parser and it is validated as
# data, never trusted as shape-safe.
if [[ ! "$PROJECT_KEY" =~ ^[A-Za-z][A-Za-z0-9_]*$ ]]; then
  envelope_fail "the given project key does not match the Jira project-key grammar (e.g. ABC)."
fi
if [[ ! "$JIRA_SITE" =~ ^[A-Za-z0-9.-]+$ ]]; then
  envelope_fail "JIRA_SITE is not a bare hostname."
fi

OUT_DIR=".ai/tracker"
mkdir -p "$OUT_DIR"
BODY_FILE="${OUT_DIR}/create-item-${PROJECT_KEY}-body.json"
RESPONSE_FILE="${OUT_DIR}/create-item-${PROJECT_KEY}-response.json"

# The conversion refuses to emit a description it cannot reproduce, so a
# failure here means the draft would have been silently altered in the item.
# Reporting it as a failed write is the honest reading: nothing was sent.
BUILD_ERR="$(python3 "$BUILD_FIELDS" "$DRAFT_FILE" --project "$PROJECT_KEY" --out "$BODY_FILE" 2>&1)"
if [[ $? -ne 0 ]]; then
  envelope_fail "the draft could not be converted into a create payload — ${BUILD_ERR//$'\n'/ }"
fi

HTTP_CODE="$(curl -sS -K - -X POST --data-binary "@${BODY_FILE}" -H "Content-Type: application/json" \
  -o "$RESPONSE_FILE" -w '%{http_code}' <<EOF
url = "https://${JIRA_SITE}/rest/api/3/issue"
user = "${JIRA_EMAIL}:${JIRA_API_TOKEN}"
header = "Accept: application/json"
EOF
)"
CURL_EXIT=$?

if [[ $CURL_EXIT -ne 0 ]]; then
  envelope_fail "curl failed (exit ${CURL_EXIT}) creating an item in ${PROJECT_KEY}."
fi
# A rejected field comes back as 400 with the field named in the body. An item
# type this project does not offer is the common case, and "HTTP 400" alone
# tells nobody which of the two to change.
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
' "$RESPONSE_FILE" 2>/dev/null)"
  envelope_fail "Jira rejected the new item in ${PROJECT_KEY} (HTTP 400)${DETAIL:+ — ${DETAIL}}"
fi
if [[ "$HTTP_CODE" != "201" ]]; then
  envelope_fail "Jira returned HTTP ${HTTP_CODE} creating an item in ${PROJECT_KEY}."
fi

ITEM_ID="$(python3 -c '
import json, sys
try:
    print(json.load(open(sys.argv[1])).get("key", ""))
except Exception:
    print("")
' "$RESPONSE_FILE" 2>/dev/null)"

# A 201 with no key is not a success anyone can act on: the item exists and
# nothing can name it. Say so rather than reporting a pass with a blank key.
if [[ -z "$ITEM_ID" ]]; then
  envelope_fail "Jira accepted the new item in ${PROJECT_KEY} but returned no key; see ${RESPONSE_FILE}."
fi

KEY_FILE="${OUT_DIR}/create-item-${ITEM_ID}.json"
mv "$RESPONSE_FILE" "$KEY_FILE"
mv "$BODY_FILE" "${OUT_DIR}/create-item-${ITEM_ID}-body.json"

cat <<RESULT
## Result
verdict: pass
summary: Created item ${ITEM_ID} in project ${PROJECT_KEY}.
artifacts:
  - ${KEY_FILE}
  - ${OUT_DIR}/create-item-${ITEM_ID}-body.json
next_action: none
RESULT
