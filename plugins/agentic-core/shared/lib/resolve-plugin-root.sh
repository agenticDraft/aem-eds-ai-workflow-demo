#!/usr/bin/env bash
# Run: bash plugins/agentic-core/shared/lib/resolve-plugin-root.sh <name>
#
# resolve-plugin-root.sh <name> [--project-dir <dir>]
#
# Prints the root directory of the plugin called <name>. The only reader of
# the root registry, <project dir>/.ai/run-context/plugin-roots/<name>, which
# each plugin's own SessionStart hook writes through register-plugin-root.sh.
# The name comes from the caller (project config's `packs:` map, or its own
# manifest); this script names no plugin. Deterministic, no model involved.
#
#   --project-dir  the project whose registry is read (default
#                  $CLAUDE_PROJECT_DIR, else the git top level of the working
#                  directory, else the working directory)
#
# Order, first match wins:
#   1. a registry entry naming a directory that exists → that directory;
#   2. a registry entry that names a missing directory, a relative path, a
#      file or nothing → refused; never skipped in favour of step 3;
#   3. no registry entry → the folder <name> beside this plugin's own root,
#      which exists only when every plugin is loaded by path from one tree;
#   4. otherwise → not resolved.
# Every path is compared and printed in canonical form, so one directory
# spelled two ways gives one answer.
#
# Output: on success, one line on stdout, the absolute root. On failure,
# nothing on stdout and one line on stderr:
#   refused: <name> — registry entry <file> names <path>, not a directory  (exit 3)
#   not resolved: <name> — no registry entry at <file>, no folder at <path> (exit 1)
# A caller that gets a non-zero exit stops; it never guesses a path.
#
# Exit codes: 0 — resolved; 1 — not resolved; 2 — usage error; 3 — refused.

set -uo pipefail

usage() {
  echo "usage: resolve-plugin-root.sh <name> [--project-dir <dir>]" >&2
  [ "$#" -gt 0 ] && echo "$1" >&2
  exit 2
}

# canonical <dir> — the directory's physical path, or nothing if it is not one
canonical() { [ -d "$1" ] && (cd "$1" 2>/dev/null && pwd -P); }

NAME="${1:-}"
[ "$#" -ge 1 ] || usage
shift
[[ "$NAME" =~ ^[a-z0-9][a-z0-9._-]*$ ]] || usage "not a plugin name: '$NAME'"

PROJECT_DIR=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --project-dir) [ "$#" -ge 2 ] || usage "--project-dir needs a value"; PROJECT_DIR="$2"; shift 2 ;;
    *) usage "unknown argument: '$1'" ;;
  esac
done
if [ -z "$PROJECT_DIR" ]; then
  PROJECT_DIR="${CLAUDE_PROJECT_DIR:-}"
  [ -n "$PROJECT_DIR" ] || PROJECT_DIR=$(git rev-parse --show-toplevel 2>/dev/null) || PROJECT_DIR=""
  [ -n "$PROJECT_DIR" ] || PROJECT_DIR="$PWD"
fi
PROJECT=$(canonical "$PROJECT_DIR") || usage "project dir is not a directory: '$PROJECT_DIR'"

ENTRY="$PROJECT/.ai/run-context/plugin-roots/$NAME"
if [ -e "$ENTRY" ] || [ -L "$ENTRY" ]; then
  REGISTERED=""
  [ -f "$ENTRY" ] && IFS= read -r REGISTERED < "$ENTRY"
  ROOT=""
  [[ "$REGISTERED" == /* ]] && ROOT=$(canonical "$REGISTERED")
  if [ -z "$ROOT" ]; then
    echo "refused: $NAME — registry entry $ENTRY names '$REGISTERED', not a directory" >&2
    exit 3
  fi
  printf '%s\n' "$ROOT"
  exit 0
fi

OWN_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd "$(pwd -P)/../.." && pwd -P)
SIBLING="$(dirname "$OWN_ROOT")/$NAME"
ROOT=$(canonical "$SIBLING")
if [ -n "$ROOT" ]; then
  printf '%s\n' "$ROOT"
  exit 0
fi

echo "not resolved: $NAME — no registry entry at $ENTRY, no folder at $SIBLING" >&2
exit 1
