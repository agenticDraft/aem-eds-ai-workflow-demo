#!/usr/bin/env bash
# warn-source-read.sh — Warn, non-fatally, when the route driver reads a
# source file in its own (unforked) context. Core contract §4/§9: the driver
# owns control flow and process lifecycle only — it never reads a source
# file, and never opens a path an envelope's `artifacts:` lists. A stage's
# own work, including reading whatever it produced, happens inside that
# stage's own isolated subagent, not here. This hook does not enforce that
# mechanically (it cannot tell an ordinary project file from one an
# envelope's `artifacts:` just named); it appends a log line so the
# discipline can be asserted against later. The default-deny version of this
# check is deferred, on purpose, to a later task, gated on a real run.
#
# Wired via the skill-scoped `hooks:` frontmatter key in
# plugins/agentic-core/skills/run-route/SKILL.md (PreToolUse on Read).
#
# Adapted from dx-core's no-source-reads.sh pattern (MIT, © 2025-2026 Dragan
# Filipovic) — same "warn, never block" shape, ported to this core's own
# artifact and log paths rather than copied verbatim.

set -uo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null || echo "")

[ -z "$FILE_PATH" ] && exit 0

LOG_DIR="${CLAUDE_PROJECT_DIR:-.}/.ai/logs"
LOG_FILE="$LOG_DIR/run-route-reads.log"

case "$FILE_PATH" in
  *.js|*.ts|*.tsx|*.jsx|*.html|*.xml|*.scss|*.css)
    mkdir -p "$LOG_DIR" 2>/dev/null
    printf '%s WARN read: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$FILE_PATH" >> "$LOG_FILE" 2>/dev/null
    echo "WARN: run-route is reading $FILE_PATH directly. Reading a source file is a stage's own job, done inside that stage's isolated subagent — the driver only spawns it and reads the returned envelope. The read will proceed; logged to $LOG_FILE." >&2
    exit 0
    ;;
esac

exit 0
