#!/usr/bin/env bash
# check-branch-command.sh — PreToolUse hook on Bash (D544). Blocks a command
# that creates a branch whose name fails the configured platform pack's
# `branch_name:` rule, as check-branch-name.sh answers it.
#
# Wired via this plugin's hooks/hooks.json. Reads the tool call as JSON on
# stdin. Exit 0 lets the command proceed; exit 2 blocks it, with the reason on
# stderr.
#
# Only a segment whose first command word is `git` is read, so text that merely
# mentions a command is never judged. Creating forms: `switch -c|-C|--create`,
# `checkout -b|-B`, `branch <name>` (not a list, delete, move or copy),
# `worktree add -b|-B`, and `push` (each refspec's destination, not a tag,
# not HEAD, not a delete). A redirection, and a target written apart from its
# operator, is dropped before any word is read. A name the shell has not expanded yet is allowed
# and appended to .ai/logs/branch-name-hook.log under the project root.
#
# A project without .ai/project-config.yaml, or input that is not a Bash call,
# passes silently. A configured platform pack that cannot be resolved blocks.
#
# The platform pack is resolved against the main checkout's registry, so a
# command run in a linked worktree is judged by the same rule.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/check-branch-name.sh"

INPUT=$(cat)
COMMAND=$(printf '%s' "$INPUT" | jq -r 'if .tool_name == "Bash" then .tool_input.command // "" else "" end' 2>/dev/null) || exit 0
[[ -n "$COMMAND" ]] || exit 0
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null)
[[ -n "$CWD" && -d "$CWD" ]] || CWD="$PWD"

ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || exit 0
CONFIG="$ROOT/.ai/project-config.yaml"
[[ -f "$CONFIG" ]] || exit 0

COMMON=$(git -C "$CWD" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || COMMON=""
MAIN=$(dirname "${COMMON:-$ROOT/.git}")
CHECK_ARGS=(--config "$CONFIG" --project-dir "$MAIN")

log() {
  mkdir -p "$ROOT/.ai/logs" 2>/dev/null || return 0
  printf '%s allow: not expanded: %s in: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" \
    >> "$ROOT/.ai/logs/branch-name-hook.log" 2>/dev/null
}

# judge <name> <segment> — exit 2 when the name fails the rule
judge() {
  local name="$1" segment="$2" out code
  name="${name#[\"\']}"; name="${name%[\"\']}"
  [[ -n "$name" ]] || return 0
  if [[ "$name" == *'$'* || "$name" == *'`'* || "$name" == *'('* ]]; then
    log "$name" "$segment"
    return 0
  fi
  out=$(bash "$CHECK" "$name" "${CHECK_ARGS[@]}" 2>/dev/null); code=$?
  if [[ "$code" -eq 1 || "$code" -eq 3 ]]; then
    echo "$out — rename the branch; check a name first with check-branch-name.sh <name>" >&2
    exit 2
  fi
  if [[ "$code" -eq 4 ]]; then
    echo "$out — the branch rule cannot be read; resolve the platform pack first" >&2
    exit 2
  fi
}

# names_in <tokens after "git"…> — prints each branch name the command creates
names_in() {
  local -a t=("$@")
  local i=0 n=${#t[@]}
  while (( i < n )); do
    case "${t[i]}" in
      -C|-c|--git-dir|--work-tree|--namespace) i=$((i + 2)) ;;
      -*) i=$((i + 1)) ;;
      *) break ;;
    esac
  done
  (( i < n )) || return 0
  local verb="${t[i]}"; i=$((i + 1))
  local -a rest=("${t[@]:i}")
  local j tok
  case "$verb" in
    switch)
      for (( j = 0; j < ${#rest[@]}; j++ )); do
        tok="${rest[j]}"
        case "$tok" in
          -c|-C|--create|--force-create) echo "${rest[j + 1]:-}"; return 0 ;;
          --create=*|--force-create=*) echo "${tok#*=}"; return 0 ;;
        esac
      done ;;
    checkout)
      for (( j = 0; j < ${#rest[@]}; j++ )); do
        case "${rest[j]}" in
          -b|-B) echo "${rest[j + 1]:-}"; return 0 ;;
          --) return 0 ;;
        esac
      done ;;
    branch)
      for tok in "${rest[@]}"; do
        case "$tok" in
          -d|-D|--delete|-m|-M|--move|-c|-C|--copy|-l|--list|-a|--all|-r|--remotes|\
          --show-current|-v|-vv|--verbose|--contains|--no-contains|--merged|--no-merged|\
          --points-at|--set-upstream-to*|-u|--unset-upstream|--edit-description|--format*|--sort*)
            return 0 ;;
        esac
      done
      for tok in "${rest[@]}"; do
        [[ "$tok" == -* ]] && continue
        echo "$tok"; return 0
      done ;;
    worktree)
      [[ "${rest[0]:-}" == "add" ]] || return 0
      for (( j = 1; j < ${#rest[@]}; j++ )); do
        case "${rest[j]}" in
          -b|-B) echo "${rest[j + 1]:-}"; return 0 ;;
        esac
      done ;;
    push)
      local -a positional=()
      for (( j = 0; j < ${#rest[@]}; j++ )); do
        tok="${rest[j]}"
        case "$tok" in
          -d|--delete|--tags|--all|--mirror|--prune) return 0 ;;
          -o|--push-option|--repo|--receive-pack|--exec) j=$((j + 1)) ;;
          -*) ;;
          *) positional+=("$tok") ;;
        esac
      done
      (( ${#positional[@]} > 1 )) || return 0
      local spec dst
      for spec in "${positional[@]:1}"; do
        spec="${spec#+}"
        dst="${spec##*:}"
        dst="${dst#refs/heads/}"
        [[ "$dst" == refs/* || "$dst" == "HEAD" || -z "$dst" ]] && continue
        echo "$dst"
      done ;;
  esac
}

# A redirection word: an optional fd or `&`, the operator, an optional `&fd`,
# then the target when it is joined to the operator.
REDIRECT='^([0-9]*|&)(>>?|>\||<<?<?|<>)(&[0-9]*-?)?'

SEGMENTS="$COMMAND"
SEGMENTS="${SEGMENTS//&&/$'\n'}"
SEGMENTS="${SEGMENTS//||/$'\n'}"
SEGMENTS="${SEGMENTS//;/$'\n'}"
SEGMENTS="${SEGMENTS//|/$'\n'}"

while IFS= read -r segment; do
  read -ra words <<< "$segment"
  k=0
  while (( k < ${#words[@]} )) && [[ "${words[k]}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do
    k=$((k + 1))
  done
  [[ "${words[k]:-}" == "git" ]] || continue
  args=()
  target=0
  for word in "${words[@]:k+1}"; do
    if (( target )); then target=0; continue; fi
    if [[ "$word" =~ $REDIRECT ]]; then
      [[ "$word" == "${BASH_REMATCH[0]}" && -z "${BASH_REMATCH[3]}" ]] && target=1
      continue
    fi
    args+=("$word")
  done
  while IFS= read -r name; do
    judge "$name" "$segment"
  done < <(names_in ${args[@]+"${args[@]}"})
done <<< "$SEGMENTS"

exit 0
