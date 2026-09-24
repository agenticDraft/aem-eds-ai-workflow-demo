#!/usr/bin/env bash
# Run: bash plugins/agentic-core/shared/lib/check-exec-bits.sh plugins/
#
# check-exec-bits.sh <plugins-directory>
#
# A script a skill invokes as a plain command must be executable. When it is
# not, the invocation fails with a permission error the caller cannot recover
# from -- it has no way to tell a missing bit from a missing file, and the
# failure surfaces mid-run, long after review.
#
# An invocation that names an interpreter ahead of the path does not need the
# bit, and is not required to carry one. This checker tells the two apart; a
# rule that flagged both would be noise, and noise is not read.
#
# `${CLAUDE_PLUGIN_ROOT}` resolves to the plugin directory containing the
# skill being read, so a `/../<pack>/` path is resolved against its sibling
# pack the same way the skills themselves resolve it.
#
# A path that resolves to no file at all is not reported: that is a broken
# reference, which is a different defect with a different fix.
#
# Exit codes: 0 — every plain invocation names an executable script; 1 — at
# least one does not, each named on its own line; 2 — usage.

set -uo pipefail

usage() {
  echo "usage: check-exec-bits.sh <plugins-directory>" >&2
  if [ "$#" -gt 0 ]; then echo "$1" >&2; fi
  exit 2
}

[ "$#" -eq 1 ] || usage "expected exactly one directory"
ROOT="$1"
[ -d "$ROOT" ] || usage "'$ROOT' is not a directory"

VIOLATIONS=0
SCANNED=0

while IFS= read -r skill; do
  SCANNED=$((SCANNED + 1))
  # The plugin root is everything above this skill's own /skills/ segment.
  PLUGIN_ROOT="${skill%%/skills/*}"
  SKILL_NAME="$(basename "$(dirname "$skill")")"

  # Every reference to a script under the plugin root, with whatever precedes
  # it on the line, so an interpreter-led invocation can be recognised.
  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    PREFIX="${ref%%\$\{CLAUDE_PLUGIN_ROOT\}*}"
    # A word immediately before the path means something else runs the file.
    case "$PREFIX" in
      *[A-Za-z0-9]*) continue ;;
    esac

    REL="${ref#*\$\{CLAUDE_PLUGIN_ROOT\}}"
    CANDIDATE="${PLUGIN_ROOT}${REL}"
    # Collapse one `<pack>/../` hop so a sibling pack resolves as the skills
    # themselves resolve it.
    while case "$CANDIDATE" in *'/../'*) true ;; *) false ;; esac; do
      CANDIDATE="$(printf '%s' "$CANDIDATE" | sed -e 's#/[^/]*/\.\./#/#')"
    done

    [ -f "$CANDIDATE" ] || continue
    if [ ! -x "$CANDIDATE" ]; then
      echo "invalid: ${CANDIDATE#"$ROOT"/} is invoked as a plain command by ${SKILL_NAME} but is not executable"
      VIOLATIONS=$((VIOLATIONS + 1))
    fi
  done < <(grep -oE '[^`]{0,12}\$\{CLAUDE_PLUGIN_ROOT\}[A-Za-z0-9_./-]+\.sh' "$skill" 2>/dev/null)
done < <(find "$ROOT" -name SKILL.md -type f 2>/dev/null)

if [ "$VIOLATIONS" -gt 0 ]; then
  echo "invalid: $VIOLATIONS plain invocation(s) of a script without the executable bit" >&2
  exit 1
fi

echo "valid: exec bits ($SCANNED SKILL.md files scanned)"
exit 0
