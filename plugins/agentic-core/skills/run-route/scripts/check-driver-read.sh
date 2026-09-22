#!/usr/bin/env bash
# check-driver-read.sh — Deny any read the route driver is not entitled to make.
#
# The driver owns control flow and process lifecycle only. Its legitimate read
# set is closed: its own bookkeeping files, which no stage writes, and the
# shared contracts it validates envelopes against. Everything else — a source
# file, a stage's own instructions, or a path an envelope lists under
# artifacts: — belongs to a stage, and is read inside that stage's isolated
# subagent. An unrecognised path is therefore a defect, not an unanticipated
# need, which is why this denies by default rather than warning.
#
# Wired via the skill-scoped hooks: frontmatter key in
# plugins/agentic-core/skills/run-route/SKILL.md (PreToolUse on Read).
# Exit 0 lets the read proceed. Exit 2 blocks it and returns the reason to the
# caller, leaving the run to continue: a blocked read is recoverable, a
# terminated route is not.
#
# Every decision, allowed or denied, is appended to the log so the discipline
# can be asserted against after a run rather than only watched live.
#
# Adapts the allowlist-then-denylist shape of an upstream check, inverted here
# to default-deny. Attribution is in this plugin's NOTICE.

set -uo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null || echo "")

# No path to judge — let the tool proceed and say nothing.
[ -z "$FILE_PATH" ] && exit 0

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
LOG_DIR="$PROJECT_DIR/.ai/logs"
LOG_FILE="$LOG_DIR/run-route-reads.log"

# Judge an absolute and a relative path identically.
REL="$FILE_PATH"
case "$REL" in
  "$PROJECT_DIR"/*) REL="${REL#"$PROJECT_DIR"/}" ;;
esac
REL="${REL#./}"

# The driver's own bookkeeping. No stage writes these, so reading one cannot
# pull stage content into the driver's context.
BOOKKEEPING=".ai/project-config.yaml .ai/run-state.json .ai/progress.md .ai/route-progress.txt"

# The shared contracts. Fixed-size, versioned with the plugin, read at run time
# by design.
CONTRACT_DIR="plugins/agentic-core/shared"

VERDICT=DENY

for allowed in $BOOKKEEPING; do
  if [ "$REL" = "$allowed" ]; then
    VERDICT=ALLOW
    break
  fi
done

# Contracts are the .md files directly in CONTRACT_DIR. Its lib/ subdirectory
# holds scripts, which the driver invokes and never reads, so a nested path
# stays denied.
if [ "$VERDICT" = DENY ]; then
  case "$REL" in
    "$CONTRACT_DIR"/*.md)
      REST="${REL#"$CONTRACT_DIR"/}"
      case "$REST" in
        */*) ;;
        *) VERDICT=ALLOW ;;
      esac
      ;;
  esac
fi

mkdir -p "$LOG_DIR" 2>/dev/null
printf '%s %s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$VERDICT" "$REL" >> "$LOG_FILE" 2>/dev/null

[ "$VERDICT" = ALLOW ] && exit 0

{
  echo "Denied: $REL"
  echo
  echo "The route driver may read only its own bookkeeping files:"
  for allowed in $BOOKKEEPING; do
    echo "  $allowed"
  done
  echo "and the shared contracts:"
  echo "  $CONTRACT_DIR/*.md"
  echo
  echo "Reading anything else is a stage's own job, done inside that stage's"
  echo "isolated subagent. Take a stage's output from the fields of its result"
  echo "envelope, never by opening a path the envelope lists under artifacts:."
} >&2

exit 2
