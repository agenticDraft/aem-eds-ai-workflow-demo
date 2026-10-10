#!/usr/bin/env bash
# Run: bash plugins/agentic-core/shared/lib/register-plugin-root.sh
#
# SessionStart hook body, shared by every plugin. Writes the calling plugin's
# root to the root registry, <project dir>/.ai/run-context/plugin-roots/<name>,
# where resolve-plugin-root.sh reads it. Wired from each plugin's own
# hooks/hooks.json, so the root written is that plugin's, not this one's.
#
# Input, from the hook's environment:
#   CLAUDE_PLUGIN_ROOT  the calling plugin's root; <name> is the `name` in its
#                       .claude-plugin/plugin.json, never the folder name
#   CLAUDE_PROJECT_DIR  the project whose registry is written
# The hook input on stdin is not read.
#
# The root is written in canonical form and the file is replaced whole, so a
# later session's entry overwrites an earlier one and a reader never sees half
# a line. Nothing goes to stdout: a SessionStart hook's stdout is added to the
# session's context.
#
# Exit codes: 0 — written; 1 — refused, nothing written, the reason on stderr.

set -uo pipefail

refuse() { echo "register-plugin-root: $1" >&2; exit 1; }

[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] || refuse "CLAUDE_PLUGIN_ROOT is not set"
[ -n "${CLAUDE_PROJECT_DIR:-}" ] || refuse "CLAUDE_PROJECT_DIR is not set"
ROOT=$(cd "$CLAUDE_PLUGIN_ROOT" 2>/dev/null && pwd -P) || refuse "plugin root is not a directory: '$CLAUDE_PLUGIN_ROOT'"
PROJECT=$(cd "$CLAUDE_PROJECT_DIR" 2>/dev/null && pwd -P) || refuse "project dir is not a directory: '$CLAUDE_PROJECT_DIR'"

MANIFEST="$ROOT/.claude-plugin/plugin.json"
[ -f "$MANIFEST" ] || refuse "no plugin manifest at $MANIFEST"
NAME=$(jq -er '.name | strings' "$MANIFEST" 2>/dev/null) || refuse "no name in $MANIFEST"
[[ "$NAME" =~ ^[a-z0-9][a-z0-9._-]*$ ]] || refuse "not a plugin name: '$NAME' in $MANIFEST"

REGISTRY="$PROJECT/.ai/run-context/plugin-roots"
mkdir -p "$REGISTRY" || refuse "could not create $REGISTRY"
TMP=$(mktemp "$REGISTRY/.$NAME.XXXXXX") || refuse "could not write in $REGISTRY"
if ! printf '%s\n' "$ROOT" > "$TMP" || ! mv -f "$TMP" "$REGISTRY/$NAME"; then
  rm -f "$TMP"
  refuse "could not write $REGISTRY/$NAME"
fi
exit 0
