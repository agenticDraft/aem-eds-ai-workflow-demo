#!/usr/bin/env bash
# record-transcript-path.sh — Record the session transcript's path where the
# route driver can read it at a terminal state.
#
# The driver renders analytics.md from the session transcript (shared/
# analytics.md, D14), and the only place the runtime states that transcript's
# path is the input it hands a hook: `transcript_path`. A skill cannot read it
# from the environment, so this hook, wired through the driver's own
# frontmatter as a PreToolUse hook on Bash (the same mechanism as the Read
# hook beside it), copies the path into the run context the first time a
# command runs and every time it changes. The terminal nodes then hand that
# file to render-run-analytics.sh before the terminal line is printed.
#
# Writes <project>/.ai/run-context/transcript-path.txt — one line, the path —
# only when the project has an .ai/ directory (so a session in another
# directory records nothing) and only when the content would change (so the
# file's mtime is the moment the path was first seen or last changed, not the
# last command). A path under a subagents/ directory is a subagent's own
# transcript, not the session's, and is never recorded.
#
# Exit 0 always: a bookkeeping failure must never block a command. Prints
# nothing on stdout.

set -uo pipefail

INPUT=$(cat)
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // ""' 2>/dev/null || echo "")

[ -z "$TRANSCRIPT" ] && exit 0
case "$TRANSCRIPT" in
  */subagents/*) exit 0 ;;
esac

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
[ -d "$PROJECT_DIR/.ai" ] || exit 0

RECORD_DIR="$PROJECT_DIR/.ai/run-context"
RECORD="$RECORD_DIR/transcript-path.txt"

if [ -f "$RECORD" ] && [ "$(cat "$RECORD" 2>/dev/null)" = "$TRANSCRIPT" ]; then
  exit 0
fi

mkdir -p "$RECORD_DIR" 2>/dev/null || exit 0
printf '%s\n' "$TRANSCRIPT" > "$RECORD" 2>/dev/null || true
exit 0
