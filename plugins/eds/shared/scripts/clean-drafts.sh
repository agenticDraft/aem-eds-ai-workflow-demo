#!/usr/bin/env bash
# clean-drafts.sh — Removes the drafts of items whose change is merged or
# closed, and stops the draft server once no recorded change is still open.
# Deterministic, no model involved. Run from the project root, before the
# serve stage starts or polls anything.
#
# For each .ai/scm/publish-change-<branch>.json record, the scm role's
# check_status operation is run in its script form (the scm pack manifest's
# scripts.check_status), once, as a subprocess. Its envelope is validated and
# its change_state read whatever the verdict:
#
#   merged | closed — every drafts/<id>.plain.html whose derived branch name
#                     equals the record's branch is deleted, then the record
#                     moves to .ai/logs/scm-closed/.
#   open            — kept; the record counts as open.
#   none            — nothing is deleted and the record stays; not open.
#   unknown         — no scripts.check_status, a script that exits non-zero,
#                     an envelope that does not validate, or no change_state
#                     line. Kept, and counts as open.
#
# A draft whose derived branch matches no merged or closed record is never
# touched. When no record is open or unknown, the draft server is stopped by
# .ai/logs/draft-server.pid.
#
# The branch is taken from the record's file name, where a '/' in a branch
# name was written as '_'. Such a branch is asked about as written.
#
# Usage:
#   clean-drafts.sh <scm pack root | none>
#
# Output: one `record:` line per record, one `server:` line, then one
#   cleanup: records=<n> merged_or_closed=<n> open=<n> unknown=<n> none=<n> drafts_deleted=<n> server=<stopped|kept|nothing-to-stop>
# Exit codes: 0 — every outcome above; 2 — usage error.

set -uo pipefail

SCM_ROOT="${1:-}"
if [[ -z "$SCM_ROOT" ]]; then
  echo "usage: clean-drafts.sh <scm pack root | none>" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_LIB="$SCRIPT_DIR/../../core/lib"
DERIVE="$CORE_LIB/derive-branch-name.sh"
VALIDATE="$CORE_LIB/validate-result-envelope.sh"
STOP="$SCRIPT_DIR/stop-draft-server.sh"

RECORDS_DIR=".ai/scm"
CLOSED_DIR=".ai/logs/scm-closed"
DRAFTS_DIR="drafts"
PID_PATH=".ai/logs/draft-server.pid"

# The scm pack's script form of check_status, or empty with a reason.
SCM_SCRIPT=""
SCM_REASON=""
if [[ "$SCM_ROOT" == "none" ]]; then
  SCM_REASON="no scm pack"
elif [[ ! -f "$SCM_ROOT/pack.yaml" ]]; then
  SCM_REASON="no pack manifest at $SCM_ROOT"
else
  REL=$(awk '
    /^scripts:[[:space:]]*$/ { in_s = 1; next }
    in_s && /^[^[:space:]]/  { in_s = 0 }
    in_s && $1 == "check_status:" {
      v = $2; gsub(/^["\x27]|["\x27]$/, "", v); print v; exit
    }' "$SCM_ROOT/pack.yaml")
  if [[ -z "$REL" ]]; then
    SCM_REASON="no scripts.check_status in the scm pack manifest"
  elif [[ ! -f "$SCM_ROOT/$REL" ]]; then
    SCM_REASON="scripts.check_status names a missing file: $REL"
  else
    SCM_SCRIPT="$SCM_ROOT/$REL"
  fi
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/clean-drafts.XXXXXX" 2>/dev/null) || WORK=""
[[ -n "$WORK" && -d "$WORK" ]] || { echo "cannot create a temp dir" >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT

# state_of <branch> — prints open|merged|closed|none|unknown.
state_of() {
  local branch="$1" env="$WORK/envelope.txt" state
  [[ -n "$SCM_SCRIPT" ]] || { echo unknown; return; }
  if ! "$SCM_SCRIPT" "$branch" >"$env" 2>/dev/null; then
    echo unknown; return
  fi
  if ! bash "$VALIDATE" "$env" >/dev/null 2>&1; then
    echo unknown; return
  fi
  state=$(awk -F': *' '$1 == "change_state" { print $2; exit }' "$env")
  case "$state" in
    open|merged|closed|none) echo "$state" ;;
    *) echo unknown ;;
  esac
}

# delete_drafts <branch> — deletes each matching draft; prints the paths.
delete_drafts() {
  local branch="$1" f id derived
  [[ -d "$DRAFTS_DIR" ]] || return 0
  for f in "$DRAFTS_DIR"/*.plain.html; do
    [[ -f "$f" ]] || continue
    id="$(basename "$f" .plain.html)"
    derived="$(bash "$DERIVE" "$id" 2>/dev/null)" || continue
    if [[ "$derived" == "$branch" ]]; then
      rm -f "$f" && echo "$f"
    fi
  done
}

# move_record <record> — moves it to the closed dir, never overwriting.
move_record() {
  local src="$1" name base dest n=2
  mkdir -p "$CLOSED_DIR"
  name="$(basename "$src")"
  base="${name%.json}"
  dest="$CLOSED_DIR/$name"
  while [[ -e "$dest" ]]; do
    dest="$CLOSED_DIR/${base}-${n}.json"
    n=$((n + 1))
  done
  mv "$src" "$dest" && echo "$dest"
}

[[ -z "$SCM_REASON" ]] || echo "scm: unknown for every record ($SCM_REASON)"

TOTAL=0; TERMINAL=0; OPEN=0; UNKNOWN=0; NONE=0; DELETED=0
for rec in "$RECORDS_DIR"/publish-change-*.json; do
  [[ -f "$rec" ]] || continue
  TOTAL=$((TOTAL + 1))
  name="$(basename "$rec" .json)"
  branch="${name#publish-change-}"
  state="$(state_of "$branch")"
  case "$state" in
    merged|closed)
      TERMINAL=$((TERMINAL + 1))
      deleted="$(delete_drafts "$branch")"
      list="none"
      if [[ -n "$deleted" ]]; then
        DELETED=$((DELETED + $(printf '%s\n' "$deleted" | wc -l)))
        list="${deleted//$'\n'/,}"
      fi
      moved="$(move_record "$rec")"
      echo "record: $branch state=$state deleted=$list moved=${moved:-failed}"
      ;;
    open)    OPEN=$((OPEN + 1));       echo "record: $branch state=open kept" ;;
    none)    NONE=$((NONE + 1));       echo "record: $branch state=none kept" ;;
    *)       UNKNOWN=$((UNKNOWN + 1)); echo "record: $branch state=unknown kept" ;;
  esac
done

if (( OPEN + UNKNOWN > 0 )); then
  SERVER="kept"
  echo "server: kept (open=$OPEN unknown=$UNKNOWN)"
else
  STOPPED="$(bash "$STOP" "$PID_PATH" 2>/dev/null)"
  case "$STOPPED" in
    stopped:*) SERVER="stopped" ;;
    *)         SERVER="nothing-to-stop" ;;
  esac
  echo "server: ${STOPPED:-nothing-to-stop}"
fi

echo "cleanup: records=$TOTAL merged_or_closed=$TERMINAL open=$OPEN unknown=$UNKNOWN none=$NONE drafts_deleted=$DELETED server=$SERVER"
exit 0
