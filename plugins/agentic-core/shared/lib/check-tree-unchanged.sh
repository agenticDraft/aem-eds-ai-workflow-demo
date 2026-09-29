#!/usr/bin/env bash
# check-tree-unchanged.sh — Deterministic guard the route driver runs around
# a gate stage (shared/gate-contract.md, "The driver guards the tree").
#
# A gate is read-only. Whether its harness isolation actually applied is not
# something the driver can see, so the driver proves the outcome instead:
# it snapshots the project root before the gate runs and compares after it
# returns. Any change outside the named allowlist fails the gate's stage.
#
# What a snapshot records:
#   - HEAD: the commit and the symbolic ref (a commit or a switch moves it);
#   - every path `git status` reports — tracked changes and untracked files,
#     one line per file — with its status code, its index blob and a hash of
#     its working-tree content.
# So a path already dirty before the stage (the change under review) is
# left alone, and any edit, revert, stage or delete of it is caught.
# Files ignored by version control are outside the snapshot.
#
# The snapshot file itself is never counted as a change, wherever it lives.
#
# Usage:
#   check-tree-unchanged.sh snapshot <project-root> <snapshot-file>
#   check-tree-unchanged.sh compare  <project-root> <snapshot-file> [<allowed path>...]
#
# Allowed paths are relative to <project-root>, matched exactly.
#
# Exit codes:
#   0 — snapshot written ("snapshot: <n> paths, HEAD <sha>"), or compare
#       found no change outside the allowlist ("pass: ...")
#   1 — compare found changes: "fail: <n> changed outside the allowlist",
#       then one "changed: <path>" line per path ("changed: HEAD" when HEAD
#       moved)
#   2 — usage error: bad subcommand or arguments, root missing or not a git
#       checkout, snapshot file missing or unreadable

set -uo pipefail

usage() {
  echo "usage: check-tree-unchanged.sh snapshot <project-root> <snapshot-file>" >&2
  echo "       check-tree-unchanged.sh compare <project-root> <snapshot-file> [<allowed path>...]" >&2
  exit 2
}

MODE="${1:-}"
ROOT="${2:-}"
SNAP="${3:-}"
[[ -z "$MODE" || -z "$ROOT" || -z "$SNAP" ]] && usage
[[ "$MODE" == "snapshot" || "$MODE" == "compare" ]] || usage
shift 3

if [[ ! -d "$ROOT" ]]; then
  echo "invalid: project root not found: $ROOT" >&2
  exit 2
fi
ROOT="$(cd "$ROOT" && pwd -P)"
if [[ "$(git -C "$ROOT" rev-parse --is-inside-work-tree 2>/dev/null)" != "true" ]]; then
  echo "invalid: not a git checkout: $ROOT" >&2
  exit 2
fi

# Writes a snapshot of ROOT to $1. Line shapes (tab-separated):
#   h <commit|none> <ref|detached>
#   p <status> <index blob|-> <content hash|-> <path>
write_snapshot() {
  local out="$1" head ref entry xy path content index
  head="$(git -C "$ROOT" rev-parse --verify -q HEAD)" || head="none"
  ref="$(git -C "$ROOT" symbolic-ref -q HEAD)" || ref="detached"
  {
    printf 'h\t%s\t%s\n' "$head" "$ref"
    while IFS= read -r -d '' entry; do
      xy="${entry:0:2}"
      path="${entry:3}"
      if [[ -f "$ROOT/$path" || -L "$ROOT/$path" ]]; then
        content="$(git -C "$ROOT" hash-object --no-filters -- "$path")" || content="unreadable"
      else
        content="-"
      fi
      index="$(git -C "$ROOT" ls-files -s -- ":(literal)$path" | awk '{print $2}' | tr '\n' ',')"
      [[ -z "$index" ]] && index="-"
      printf 'p\t%s\t%s\t%s\t%s\n' "$xy" "$index" "$content" "$path"
    done < <(git -C "$ROOT" status --porcelain=v1 -z --untracked-files=all --no-renames) \
      | LC_ALL=C sort
  } >"$out"
}

# The snapshot file's path relative to ROOT, or empty when it lies outside.
snapshot_rel() {
  local dir base
  dir="$(cd "$(dirname "$SNAP")" 2>/dev/null && pwd -P)" || return 0
  base="$(basename "$SNAP")"
  case "$dir/$base" in
    "$ROOT"/*) echo "${dir#"$ROOT"/}/$base" ;;
  esac
}

if [[ "$MODE" == "snapshot" ]]; then
  mkdir -p "$(dirname "$SNAP")" || { echo "invalid: cannot create $(dirname "$SNAP")" >&2; exit 2; }
  TMP="$(mktemp "${TMPDIR:-/tmp}/check-tree-unchanged.XXXXXX")" || exit 2
  write_snapshot "$TMP"
  mv "$TMP" "$SNAP" || { rm -f "$TMP"; echo "invalid: cannot write $SNAP" >&2; exit 2; }
  echo "snapshot: $(grep -c '^p' "$SNAP") paths, HEAD $(awk -F'\t' '$1=="h"{print $2}' "$SNAP")"
  exit 0
fi

# compare
if [[ ! -f "$SNAP" || ! -r "$SNAP" ]]; then
  echo "invalid: snapshot not found: $SNAP" >&2
  exit 2
fi
if ! grep -q '^h' "$SNAP"; then
  echo "invalid: not a snapshot file: $SNAP" >&2
  exit 2
fi

AFTER="$(mktemp "${TMPDIR:-/tmp}/check-tree-unchanged-after.XXXXXX")" || exit 2
trap 'rm -f "$AFTER"' EXIT
write_snapshot "$AFTER"

SELF="$(snapshot_rel)"
declare -a ALLOWED=()
for a in "$@"; do ALLOWED+=("${a#./}"); done
[[ -n "$SELF" ]] && ALLOWED+=("$SELF")

is_allowed() {
  local p="$1" a
  for a in "${ALLOWED[@]:-}"; do [[ "$p" == "$a" ]] && return 0; done
  return 1
}

declare -a CHANGED=()
if [[ "$(grep '^h' "$SNAP")" != "$(grep '^h' "$AFTER")" ]]; then
  CHANGED+=("HEAD")
fi

ALLOWED_SEEN=0
while IFS= read -r path; do
  [[ -z "$path" ]] && continue
  if is_allowed "$path"; then
    ALLOWED_SEEN=$((ALLOWED_SEEN + 1))
  else
    CHANGED+=("$path")
  fi
done < <(
  awk -F'\t' '
    $1 != "p" { next }
    NR == FNR { before[$5] = $0; next }
              { after[$5] = $0 }
    END {
      for (k in before) if (!(k in after) || after[k] != before[k]) print k
      for (k in after)  if (!(k in before)) print k
    }
  ' "$SNAP" "$AFTER" | LC_ALL=C sort -u
)

if [[ "${#CHANGED[@]}" -eq 0 ]]; then
  echo "pass: no change outside the allowlist (allowed paths changed: $ALLOWED_SEEN)"
  exit 0
fi

echo "fail: ${#CHANGED[@]} changed outside the allowlist"
for p in "${CHANGED[@]}"; do echo "changed: $p"; done
exit 1
