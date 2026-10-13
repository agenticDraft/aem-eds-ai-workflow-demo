#!/usr/bin/env bash
# Run: bash .claude/scripts/update-plugin-pin.sh [--check]
#
# Moves the project's plugin pin to the newest vX.Y.Z tag of the plugins repository, then
# refreshes the local marketplace and installed plugins.
#   --check   report only; exit 10 when a newer tag exists, 0 when the pin is current.
# Edits two files and never commits: .claude/settings.json (extraKnownMarketplaces ref) and
# .github/workflows/route-trigger.yaml (the `_plugins` checkout ref).
# A third pin, the user-level ~/.claude/settings.json entry for the same marketplace, is only
# read: while it differs from the tag the CLI refuses to re-register the marketplace, so the
# script stops (exit 3) and prints the command that moves it.
# Overrides for tests: PIN_SETTINGS, PIN_WORKFLOW, PIN_USER_SETTINGS, PIN_REPO_URL, PIN_SKIP_CLI=1.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SETTINGS="${PIN_SETTINGS:-$ROOT/.claude/settings.json}"
WORKFLOW="${PIN_WORKFLOW:-$ROOT/.github/workflows/route-trigger.yaml}"
USER_SETTINGS="${PIN_USER_SETTINGS:-$HOME/.claude/settings.json}"
REPO_URL="${PIN_REPO_URL:-git@github.com:agenticDraft/plugins.git}"
MARKETPLACE="agenticdraft"
CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1

die() { echo "update-plugin-pin: $*" >&2; exit 2; }

latest_tag() {
  git ls-remote --tags --refs "$REPO_URL" 'refs/tags/v*' \
    | sed 's|.*refs/tags/||' \
    | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' \
    | sort -V | tail -n 1
}

TAG="$(latest_tag)"
[ -n "$TAG" ] || die "no vX.Y.Z tag found at $REPO_URL"

CURRENT="$(jq -r --arg m "$MARKETPLACE" '.extraKnownMarketplaces[$m].source.ref // empty' "$SETTINGS")"
[ -n "$CURRENT" ] || die "no extraKnownMarketplaces.$MARKETPLACE.source.ref in $SETTINGS"

WF_CURRENT="$(awk '/repository: agenticDraft\/plugins/ {f=1; next} f && /ref:/ {print $2; exit}' "$WORKFLOW")"
[ -n "$WF_CURRENT" ] || die "no plugins checkout ref in $WORKFLOW"

USER_CURRENT=""
[ -f "$USER_SETTINGS" ] && USER_CURRENT="$(jq -r --arg m "$MARKETPLACE" '.extraKnownMarketplaces[$m].source.ref // empty' "$USER_SETTINGS")"

echo "settings.json: $CURRENT   route-trigger.yaml: $WF_CURRENT   user settings: ${USER_CURRENT:-none}   latest tag: $TAG"

if [ "$CURRENT" = "$TAG" ] && [ "$WF_CURRENT" = "$TAG" ] && { [ -z "$USER_CURRENT" ] || [ "$USER_CURRENT" = "$TAG" ]; }; then
  echo "pin is current"
  exit 0
fi
if [ "$CHECK" -eq 1 ]; then
  echo "newer tag available: $TAG"
  exit 10
fi

if [ -n "$USER_CURRENT" ] && [ "$USER_CURRENT" != "$TAG" ]; then
  echo "update-plugin-pin: $USER_SETTINGS pins $MARKETPLACE at $USER_CURRENT; the CLI refuses a different ref while it does." >&2
  echo "Move it, then run this script again:" >&2
  echo "  jq '.extraKnownMarketplaces.$MARKETPLACE.source.ref=\"$TAG\"' $USER_SETTINGS > $USER_SETTINGS.new && mv $USER_SETTINGS.new $USER_SETTINGS" >&2
  exit 3
fi

# Line-level edits keep the files' formatting. Both new contents are built and checked before
# either file is written, so a layout the edit cannot read leaves both files as they were.
NEW_SETTINGS="$(mktemp "${TMPDIR:?TMPDIR must be set}/pin-settings.XXXXXX")"
NEW_WORKFLOW="$(mktemp "${TMPDIR:?TMPDIR must be set}/pin-workflow.XXXXXX")"
trap 'rm -f "$NEW_SETTINGS" "$NEW_WORKFLOW"' EXIT

# The ref sits on the repo's own line or on a later line of the same object.
awk -v tag="$TAG" '
  /"repo": *"agenticDraft\/plugins"/ {f=1}
  f && /"ref": *"[^"]*"/ {sub(/"ref": *"[^"]*"/, "\"ref\": \"" tag "\""); f=0}
  {print}' "$SETTINGS" > "$NEW_SETTINGS"
awk -v tag="$TAG" '
  /repository: agenticDraft\/plugins/ {f=1}
  f && /ref:/ {sub(/ref:.*/, "ref: " tag); f=0}
  {print}' "$WORKFLOW" > "$NEW_WORKFLOW"

[ "$(jq -r --arg m "$MARKETPLACE" '.extraKnownMarketplaces[$m].source.ref' "$NEW_SETTINGS" 2>/dev/null)" = "$TAG" ] \
  || die "could not set the ref in $SETTINGS to $TAG; nothing was written"
grep -q "ref: $TAG\$" "$NEW_WORKFLOW" || die "could not set the ref in $WORKFLOW to $TAG; nothing was written"
cat "$NEW_SETTINGS" > "$SETTINGS"
cat "$NEW_WORKFLOW" > "$WORKFLOW"
echo "pin moved to $TAG"

if [ "${PIN_SKIP_CLI:-0}" != "1" ]; then
  # `marketplace update` alone keeps the ref registered in known_marketplaces.json; re-adding
  # with the new ref is what moves the clone. Plugins are installed at project scope.
  claude plugin marketplace add "agenticDraft/plugins#$TAG" --scope project
  claude plugin marketplace update "$MARKETPLACE"
  while IFS= read -r plugin; do
    claude plugin update "$plugin" --scope project
  done < <(jq -r --arg m "@$MARKETPLACE" '.enabledPlugins | keys[] | select(endswith($m))' "$SETTINGS")
fi

echo "done: commit the two edited files, then restart the session so the new SKILL.md files load"
