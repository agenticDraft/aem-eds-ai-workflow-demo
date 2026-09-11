#!/usr/bin/env bash
# download-attachment.sh <content-url> <out-file>
#
# Downloads a tracker attachment's binary content — the mechanism core
# contract §6.1's image design-source form actually needs ("arrives through
# tracker.fetch_item, not the design role"): `fetch_item` already returned
# the attachment's metadata, including this content URL, and this script
# finishes the retrieval it started. Credentials (JIRA_EMAIL,
# JIRA_API_TOKEN) are read from the environment and handed to curl via a
# stdin config block (-K -), never as a command-line argument, the same
# pattern this pack's own tracker fetch already uses, so they never appear
# in `ps -ef` or a log.
#
# Jira's attachment content endpoint responds with a redirect to a signed,
# short-lived download URL (observed: HTTP 303) rather than the bytes
# directly, so this follows redirects (-L) the same way this pack's design
# provider pack already does for its own reference-image download.
#
# Exit codes: 0 on a successful download; 1 if the download failed (missing
# credentials, a non-2xx final response, or curl itself failing) — printed
# to stderr, nothing written to <out-file>; 2 for a usage error.

set -uo pipefail

CONTENT_URL="${1:-}"
OUT_FILE="${2:-}"

if [[ -z "$CONTENT_URL" || -z "$OUT_FILE" ]]; then
  echo "usage: download-attachment.sh <content-url> <out-file>" >&2
  exit 2
fi

if [[ -z "${JIRA_EMAIL:-}" || -z "${JIRA_API_TOKEN:-}" ]]; then
  echo "error: JIRA_EMAIL or JIRA_API_TOKEN is not set in the environment." >&2
  exit 1
fi

# CONTENT_URL is tracker-sourced data (a `content` field from a fetched
# item's JSON) and must be validated as data before it reaches curl's config
# parser, never trusted as shape-safe — the same newline-injection risk
# fetch-item.sh's own ITEM_ID check guards against.
if [[ "$CONTENT_URL" == *$'\n'* || "$CONTENT_URL" != https://* ]]; then
  echo "error: content URL is not a plain https:// URL with no embedded newline." >&2
  exit 1
fi

mkdir -p "$(dirname "$OUT_FILE")"

HTTP_CODE="$(curl -sS -L -K - -o "$OUT_FILE" -w '%{http_code}' <<EOF
url = "${CONTENT_URL}"
user = "${JIRA_EMAIL}:${JIRA_API_TOKEN}"
EOF
)"
CURL_EXIT=$?

if [[ $CURL_EXIT -ne 0 ]]; then
  rm -f "$OUT_FILE"
  echo "error: curl failed (exit ${CURL_EXIT}) downloading attachment." >&2
  exit 1
fi
if [[ "$HTTP_CODE" != 2* ]]; then
  rm -f "$OUT_FILE"
  echo "error: attachment download returned HTTP ${HTTP_CODE}." >&2
  exit 1
fi

echo "downloaded: ${OUT_FILE}"
exit 0
