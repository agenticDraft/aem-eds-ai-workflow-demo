#!/usr/bin/env bash
# check-direct-script-calls.sh — Deterministic read of a stage adapter's
# transcript for provider-pack scripts it ran itself instead of through the
# role operation that owns them. No model involved.
#
# A stage reaches another pack only through that pack's declared operations,
# invoked as skills; the operation's script path is the pack's layout, not its
# contract, and a stage that runs it on its own skips the operation's own
# preconditions, its sandbox handling and its envelope. Nothing in a run's
# artifacts shows the difference — the script writes the same files either
# way — so the only record is the transcript the runtime writes for every
# subagent: one JSON object per line, each tool call under
# message.content[].type == "tool_use" with its name and input.
#
# Invoking an operation as a skill injects its instructions, and the stage
# then runs the operation's script itself, so a transcript that invoked the
# operation also holds a command running its script. The two are told apart by
# order: a command running plugins/<pack>/skills/<skill>/scripts/<file> is the
# operation's own when the most recent skill invocation before it named
# <pack>:<skill>, and direct otherwise. Only the executed path counts — the
# first word of each command segment, or the word after an interpreter — so a
# script path given as an argument or read by another command is never
# reported. A path behind a variable (`node $P/capture/scripts/capture.cjs`
# after `P=plugins/<pack>/skills`) is resolved from the same command. The
# stage's own pack is never reported.
#
# Usage:
#   check-direct-script-calls.sh <own pack> <transcript.jsonl> [<transcript.jsonl> ...]
#
# Output, one line per direct call:
#   direct TAB <pack>/<skill> TAB <transcript basename> TAB <command, first 120 characters>
# then one summary line:
#   ok: no provider script run directly (<n> commands read)          (exit 0)
#   invalid: <n> provider script(s) run directly                     (exit 1)
#
# Exit codes: 0 — none; 1 — at least one; 2 — usage error (missing argument,
# unreadable file, or a line that is not JSON).

set -uo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: check-direct-script-calls.sh <own pack> <transcript.jsonl> [<transcript.jsonl> ...]" >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "invalid: jq is required and was not found on PATH" >&2
  exit 2
fi

OWN="$1"
shift

COMMANDS=0
DIRECT=0

# executed_paths <command> — the path each segment of the command executes
executed_paths() {
  tr ';|&' '\n\n\n' <<<"$1" | awk '
    {
      i = 1
      while (i <= NF && $i ~ /^(do|then|else|if|elif|while|until|!)$/) i++
      while (i <= NF && $i ~ /^[A-Za-z_][A-Za-z0-9_]*=/) i++
      if (i <= NF && $i ~ /^(node|bash|sh|zsh|python|python3|perl|ruby|exec|env)$/) i++
      if (i <= NF) print $i
    }'
}

for transcript in "$@"; do
  if [[ ! -f "$transcript" || ! -r "$transcript" ]]; then
    echo "invalid: cannot read $transcript" >&2
    exit 2
  fi
  name="$(basename "$transcript")"
  # the ordered stream of tool calls: S<TAB><skill> or B<TAB><command on one line>
  if ! events="$(jq -r '
      select(type == "object")
      | .message? | select(type == "object")
      | .content? | select(type == "array")
      | .[] | select(type == "object" and .type == "tool_use")
      | if .name == "Skill" then "S\t" + (.input.skill? // "")
        elif .name == "Bash" then "B\t" + ((.input.command? // "") | gsub("[\r\n]+"; " "))
        else empty end
    ' "$transcript" 2>/dev/null)"; then
    echo "invalid: $transcript holds a line that is not JSON" >&2
    exit 2
  fi
  last_skill=""
  while IFS=$'\t' read -r kind payload; do
    [[ -z "$kind" ]] && continue
    if [[ "$kind" == "S" ]]; then
      last_skill="$payload"
      continue
    fi
    cmd="$payload"
    [[ -z "$cmd" ]] && continue
    COMMANDS=$((COMMANDS + 1))
    while IFS= read -r path; do
      [[ -z "$path" ]] && continue
      # a variable prefix resolves to its assignment in the same command
      if [[ "$path" =~ ^\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?/(.*)$ ]]; then
        var="${BASH_REMATCH[1]}"; tail="${BASH_REMATCH[2]}"
        value="$(grep -oE "(^|[^A-Za-z0-9_])${var}=[^ ;|&]+" <<<"$cmd" | head -1 | sed -E "s/^.*${var}=//")"
        [[ -z "$value" ]] && continue
        path="${value%/}/$tail"
      fi
      [[ "$path" =~ (^|/)plugins/([^/]+)/skills/([^/]+)/scripts/[^/]+$ ]] || continue
      pack="${BASH_REMATCH[2]}"; skill="${BASH_REMATCH[3]}"
      [[ "$pack" == "$OWN" ]] && continue
      [[ "$last_skill" == "$pack:$skill" ]] && continue
      DIRECT=$((DIRECT + 1))
      printf 'direct\t%s/%s\t%s\t%s\n' "$pack" "$skill" "$name" "${cmd:0:120}"
    done < <(executed_paths "$cmd" | sort -u)
  done <<<"$events"
done

if (( DIRECT > 0 )); then
  echo "invalid: $DIRECT provider script(s) run directly"
  exit 1
fi
echo "ok: no provider script run directly ($COMMANDS commands read)"
exit 0
