#!/usr/bin/env bash
# Run: bash plugins/agentic-core/shared/lib/check-own-root-refs.sh <plugin root>...
#
# check-own-root-refs.sh <plugin root>...
#
# A plugin reaches its own files as ${CLAUDE_PLUGIN_ROOT}/<path>. Through the
# parent folder and its own name, the same path breaks once the plugin is
# installed under a versioned directory or renamed. This check reports every
# such reference, the braced and the bare form, in every file under each root.
# The name is read from each root's .claude-plugin/plugin.json, never from its
# folder, so the check names no plugin. A linked directory is not followed.
# Deterministic, no model involved.
#
# Output: one line per reference, '<file>:<line>: <text>', then
#   valid: own-root references (<n> plugins, <m> files scanned)     (exit 0)
#   invalid: <k> own-root references through the parent folder      (exit 1)
#
# Exit codes: 0 — none found; 1 — at least one; 2 — usage.

set -uo pipefail

usage() {
  echo "usage: check-own-root-refs.sh <plugin root>..." >&2
  [ "$#" -gt 0 ] && echo "$1" >&2
  exit 2
}

[ "$#" -ge 1 ] || usage

NAMES=()
for root in "$@"; do
  [ -d "$root" ] || usage "not a directory: '$root'"
  manifest="$root/.claude-plugin/plugin.json"
  [ -f "$manifest" ] || usage "no plugin manifest at $manifest"
  name=$(jq -er '.name | strings' "$manifest" 2>/dev/null) || usage "no name in $manifest"
  [[ "$name" =~ ^[a-z0-9][a-z0-9._-]*$ ]] || usage "not a plugin name: '$name' in $manifest"
  NAMES+=("$name")
done

FOUND=0
SCANNED=0
i=0
for root in "$@"; do
  name="${NAMES[$i]}"; i=$((i + 1))
  escaped=${name//./\\.}
  pattern="\\\$\\{?CLAUDE_PLUGIN_ROOT\\}?/\\.\\./${escaped}/"
  while IFS= read -r -d '' file; do
    SCANNED=$((SCANNED + 1))
    while IFS= read -r hit; do
      [ -n "$hit" ] || continue
      echo "$file:$hit"
      FOUND=$((FOUND + 1))
    done < <(grep -InE -- "$pattern" "$file" 2>/dev/null)
  done < <(find "$root" -path '*/.git' -prune -o -path '*/node_modules' -prune -o -type f -print0)
done

if [ "$FOUND" -gt 0 ]; then
  echo "invalid: $FOUND own-root references through the parent folder"
  exit 1
fi
echo "valid: own-root references ($# plugins, $SCANNED files scanned)"
exit 0
