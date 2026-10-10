#!/usr/bin/env bash
# Run: bash plugins/agentic-core/shared/lib/resolve-plugin-root.sh <name>
#
# resolve-plugin-root.sh <name> [--project-dir <dir>]
# resolve-plugin-root.sh --list [--siblings] [--project-dir <dir>]
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
# --list prints every registry entry as '<name><TAB><root>', sorted by name,
# each entry checked as in steps 1 and 2; one refused entry refuses the whole
# list. --siblings adds step 3 for listing: every folder beside this plugin's
# own root that holds .claude-plugin/plugin.json, named by its folder, unless a
# registry entry already names it. Nothing to list → not resolved.
#
# Output: on success, one line on stdout, the absolute root. On failure,
# nothing on stdout and one line on stderr:
#   refused: <name> — registry entry <file> names <path>, not a directory  (exit 3)
#   not resolved: <name> — no registry entry at <file>, no folder at <path> (exit 1)
#   not resolved: no plugin registered at <dir>                            (exit 1)
# A caller that gets a non-zero exit stops; it never guesses a path.
#
# Exit codes: 0 — resolved; 1 — not resolved; 2 — usage error; 3 — refused.

set -uo pipefail

usage() {
  echo "usage: resolve-plugin-root.sh <name> [--project-dir <dir>]" >&2
  echo "       resolve-plugin-root.sh --list [--siblings] [--project-dir <dir>]" >&2
  [ "$#" -gt 0 ] && echo "$1" >&2
  exit 2
}

# canonical <dir> — the directory's physical path, or nothing if it is not one
canonical() { [ -d "$1" ] && (cd "$1" 2>/dev/null && pwd -P); }

NAME_RE='^[a-z0-9][a-z0-9._-]*$'
[ "$#" -ge 1 ] || usage
LIST=0
SIBLINGS=0
NAME=""
if [ "$1" = "--list" ]; then
  LIST=1
else
  NAME="$1"
  [[ "$NAME" =~ $NAME_RE ]] || usage "not a plugin name: '$NAME'"
fi
shift

PROJECT_DIR=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --project-dir) [ "$#" -ge 2 ] || usage "--project-dir needs a value"; PROJECT_DIR="$2"; shift 2 ;;
    --siblings) [ "$LIST" -eq 1 ] || usage "--siblings needs --list"; SIBLINGS=1; shift ;;
    *) usage "unknown argument: '$1'" ;;
  esac
done
if [ -z "$PROJECT_DIR" ]; then
  PROJECT_DIR="${CLAUDE_PROJECT_DIR:-}"
  [ -n "$PROJECT_DIR" ] || PROJECT_DIR=$(git rev-parse --show-toplevel 2>/dev/null) || PROJECT_DIR=""
  [ -n "$PROJECT_DIR" ] || PROJECT_DIR="$PWD"
fi
PROJECT=$(canonical "$PROJECT_DIR") || usage "project dir is not a directory: '$PROJECT_DIR'"

REGISTRY="$PROJECT/.ai/run-context/plugin-roots"
OWN_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd "$(pwd -P)/../.." && pwd -P)

# registered <file> — the canonical root an entry names, or nothing
registered() {
  local value=""
  [ -f "$1" ] && IFS= read -r value < "$1"
  [[ "$value" == /* ]] && canonical "$value"
}

if [ "$LIST" -eq 1 ]; then
  LINES=""
  NAMES=" "
  if [ -d "$REGISTRY" ]; then
    for entry in "$REGISTRY"/*; do
      [ -e "$entry" ] || [ -L "$entry" ] || continue
      name=$(basename "$entry")
      [[ "$name" =~ $NAME_RE ]] || continue
      root=$(registered "$entry")
      if [ -z "$root" ]; then
        value=""; [ -f "$entry" ] && IFS= read -r value < "$entry"
        echo "refused: $name — registry entry $entry names '$value', not a directory" >&2
        exit 3
      fi
      LINES+="$name"$'\t'"$root"$'\n'
      NAMES+="$name "
    done
  fi
  if [ "$SIBLINGS" -eq 1 ]; then
    for dir in "$(dirname "$OWN_ROOT")"/*/; do
      [ -f "$dir.claude-plugin/plugin.json" ] || continue
      name=$(basename "$dir")
      [[ "$name" =~ $NAME_RE ]] || continue
      case "$NAMES" in *" $name "*) continue ;; esac
      LINES+="$name"$'\t'"$(canonical "$dir")"$'\n'
    done
  fi
  if [ -z "$LINES" ]; then
    echo "not resolved: no plugin registered at $REGISTRY" >&2
    exit 1
  fi
  printf '%s' "$LINES" | LC_ALL=C sort
  exit 0
fi

ENTRY="$REGISTRY/$NAME"
if [ -e "$ENTRY" ] || [ -L "$ENTRY" ]; then
  REGISTERED=""
  [ -f "$ENTRY" ] && IFS= read -r REGISTERED < "$ENTRY"
  ROOT=$(registered "$ENTRY")
  if [ -z "$ROOT" ]; then
    echo "refused: $NAME — registry entry $ENTRY names '$REGISTERED', not a directory" >&2
    exit 3
  fi
  printf '%s\n' "$ROOT"
  exit 0
fi

SIBLING="$(dirname "$OWN_ROOT")/$NAME"
ROOT=$(canonical "$SIBLING")
if [ -n "$ROOT" ]; then
  printf '%s\n' "$ROOT"
  exit 0
fi

echo "not resolved: $NAME — no registry entry at $ENTRY, no folder at $SIBLING" >&2
exit 1
