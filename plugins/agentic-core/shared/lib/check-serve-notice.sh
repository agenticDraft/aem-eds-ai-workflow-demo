#!/usr/bin/env bash
# check-serve-notice.sh — Pre-flight's fourth check (see shared/pre-flight.md,
# core contract §6.4, D94, closing G100). No model, no side effects, no live
# calls: reads the platform pack's own stage list and two values the project
# config already declares, and says what the run will need — never a running
# process, never the network, never a port.
#
# The question it answers is "what does this run need a human to know before
# it starts", not "is it up". Those are different questions and only the
# first one can be answered from a declaration. A probe would have to reach
# a local address, and an environment that refuses that reports a running
# server as absent — a false negative at pre-flight aborts a run before any
# branch or file exists, which is why pre-flight tests declarations only.
#
# Three declarations are read:
#   - the platform pack's stages: list, for a `serve` stage
#   - the project config's paths.preview
#   - the project config's commands.serve
#
# A platform pack whose stage list has no `serve` stage runs this check as a
# no-op — the same shape check 3 uses for a pack declaring neither onboarding
# path: the core acts on a declaration, never on knowledge of the thing
# declared.
#
# It never blocks, in either case it can report:
#   (a) a serve command is configured -> say where the preview will be and
#       what will start it. The run needs nothing from the human.
#   (b) no serve command is configured -> warn. Nothing in this project can
#       start that preview, so it must already be answering, or the `serve`
#       stage fails several stages into the run. A warning and not a block
#       because a preview that is already answering is the case that makes
#       an unconfigured serve command harmless, and only a probe could tell
#       the two apart.
#
# Usage:
#   check-serve-notice.sh <project-config path> <path-to-platform-pack.yaml>
#
# Exit codes:
#   0 — "not-declared" (the platform pack declares no `serve` stage), or one
#       line: "serve: ok — <preview url>, started by '<serve command>'" /
#       "serve: warn — <preview url> has no configured serve command; it must
#       already be answering before this run reaches the serve stage"
#   2 — usage error: a missing argument, or a file not found
#
# There is no exit 1. This check cannot fail a run.

set -uo pipefail

CONFIG="${1:-}"
PACK="${2:-}"

if [[ -z "$CONFIG" || -z "$PACK" ]]; then
  echo "usage: check-serve-notice.sh <project-config path> <path-to-platform-pack.yaml>" >&2
  exit 2
fi

if [[ ! -f "$CONFIG" ]]; then
  echo "invalid: file not found: $CONFIG" >&2
  exit 2
fi

if [[ ! -f "$PACK" ]]; then
  echo "invalid: file not found: $PACK" >&2
  exit 2
fi

# --- does this platform pack declare a serve stage? ------------------------
# A stage entry is a list item under stages:, one id per line. The id is read
# on its own line rather than by walking the block, the same single-line grep
# every other reader of these two files already uses.
if ! grep -qE '^[[:space:]]*-[[:space:]]+id:[[:space:]]+serve[[:space:]]*$' "$PACK"; then
  echo "not-declared"
  exit 0
fi

# --- the two declared values ----------------------------------------------
# Both live one level under their own top-level key, in the fixed order
# shared/project-config.md defines, so the first match of each is the value.
# A quoted value is the written form; the quotes are not part of it.
unquote() {
  local value="$1"
  value="${value#\"}"
  value="${value%\"}"
  printf '%s' "$value"
}

PREVIEW="$(grep -m1 -E '^  preview:[[:space:]]*' "$CONFIG" | sed -E 's/^  preview:[[:space:]]*//')"
PREVIEW="$(unquote "$PREVIEW")"

SERVE="$(grep -m1 -E '^  serve:[[:space:]]*' "$CONFIG" | sed -E 's/^  serve:[[:space:]]*//')"
SERVE="$(unquote "$SERVE")"

if [[ -z "$SERVE" ]]; then
  echo "serve: warn — ${PREVIEW} has no configured serve command; it must already be answering before this run reaches the serve stage"
  exit 0
fi

echo "serve: ok — ${PREVIEW}, started by '${SERVE}'"
exit 0
