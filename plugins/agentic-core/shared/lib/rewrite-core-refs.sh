#!/usr/bin/env bash
# Run: bash plugins/agentic-core/shared/lib/rewrite-core-refs.sh [--dry-run] <pack root>...
#
# Moves a pack's references to the core onto the pack's own `core` link, the
# link to the core's shared folder every pack carries at its root. The core's
# folder name and the link's target are read from that link, never assumed.
# Rewritten forms, where <core>/<shared> is the link's target:
#
#   ${CLAUDE_PLUGIN_ROOT}/../<core>/<shared>  → ${CLAUDE_PLUGIN_ROOT}/core
#   $SCRIPT_DIR/<n × ../><core>/<shared>      → $SCRIPT_DIR/<n-1 × ../>core
#   <n × ../><core>/<shared>  (relative to the file's own folder)
#                                             → ${CLAUDE_PLUGIN_ROOT}/core
#   <plugins folder>/<core>/<shared>          → <plugins folder>/<pack>/core
#
# Every old reference must reach the core and every new path must exist
# through the link (a path broken after a "/" or "-" at a line end is joined
# to the next line first); otherwise nothing is written in any pack. Files under the link are never
# read. Prints how many files and lines it rewrote per file type, then the
# total.
#
# Exit codes: 0 — rewritten (or nothing to rewrite); 1 — refused, nothing
# written, each reason on stderr; 2 — usage.

set -uo pipefail

usage() {
  echo "rewrite-core-refs: $1" >&2
  echo "usage: rewrite-core-refs.sh [--dry-run] <pack root>..." >&2
  exit 2
}

DRY=0
if [ "${1:-}" = "--dry-run" ]; then DRY=1; shift; fi
[ $# -ge 1 ] || usage "no pack root given"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/rewrite-core-refs.XXXXXX") || usage "cannot create a temp dir"
[ -n "$WORK" ] && [ -d "$WORK" ] || usage "cannot create a temp dir"
trap 'rm -rf "$WORK"' EXIT

ups() { local i out=""; for ((i = 0; i < $1; i++)); do out="$out../"; done; printf '%s' "$out"; }
canon() { (cd "$1" 2>/dev/null && pwd -P); }

ERRORS="$WORK/errors"
: > "$ERRORS"
PENDING=()   # "<tmp file>|<target file>|<type>|<changed lines>"
N=0

rewrite_awk='
{ L[NR] = $0 }
END {
  re = "([$][{]?[A-Za-z_][A-Za-z0-9_]*[}]?/([.][.]/)+|([.][.]/)+|[A-Za-z0-9_][A-Za-z0-9_.-]*/)" core_re "/" shared_re
  tail = corelen + 1 + sharedlen
  changed = 0
  for (i = 1; i <= NR; i++) {
    line = L[i]; out = ""; hit = 0
    while (match(line, re)) {
      start = RSTART; len = RLENGTH
      m = substr(line, start, len)
      after = substr(line, start + len)
      if (after ~ /^[A-Za-z0-9_.-]/) {
        out = out substr(line, 1, start + len - 1); line = after; continue
      }
      prefix = substr(m, 1, len - tail)
      if (substr(prefix, 1, 1) == "$") {
        slash = index(prefix, "/")
        anchor = substr(prefix, 1, slash - 1)
        name = anchor; gsub(/[${}]/, "", name)
        n = (length(prefix) - slash) / 3
        repl = anchor "/"
        for (k = 1; k < n; k++) repl = repl "../"
        repl = repl "core"
        kind = (name == "CLAUDE_PLUGIN_ROOT") ? "plugin" : (name == "SCRIPT_DIR") ? "script" : "anchor:" name
      } else if (substr(prefix, 1, 1) == ".") {
        n = length(prefix) / 3
        repl = "${CLAUDE_PLUGIN_ROOT}/core"
        kind = "file"
      } else {
        n = 0
        dir = substr(prefix, 1, length(prefix) - 1)
        repl = dir "/" pack "/core"
        kind = "dir:" dir
      }
      rest = ""
      if (match(after, /^\/[A-Za-z0-9_.\/-]*/)) rest = substr(after, 2, RLENGTH - 1)
      wrapped = (after == "" || (RLENGTH == length(after) && after ~ /[\/-]$/))
      if (wrapped && i < NR) {
        nl = L[i + 1]; sub(/^[ \t]+/, "", nl)
        if (match(nl, /^[A-Za-z0-9_.\/-]+/)) rest = rest substr(nl, 1, RLENGTH)
      }
      while (rest ~ /[.]$/) rest = substr(rest, 1, length(rest) - 1)
      sub(/^\//, "", rest)
      print i "\t" kind "\t" n "\t" rest > checks
      out = out substr(line, 1, start - 1) repl
      line = after
      hit = 1
    }
    out = out line
    if (hit) changed++
    printf "%s%s", out, (i < NR || trailing) ? "\n" : ""
  }
  print "COUNT\t" changed > checks
}'

for ARG in "$@"; do
  PACK=$(canon "$ARG") || usage "not a folder: '$ARG'"
  [ -L "$PACK/core" ] || usage "no core link at $PACK/core"
  CORE_SHARED=$(canon "$PACK/core") || usage "the core link does not resolve: $PACK/core"
  CORE_NAME=$(basename "$(dirname "$CORE_SHARED")")
  SHARED_NAME=$(basename "$CORE_SHARED")
  PACK_NAME=$(basename "$PACK")
  PLUGINS_NAME=$(basename "$(dirname "$PACK")")
  CORE_RE=$(printf '%s' "$CORE_NAME" | sed 's/[.]/[.]/g')
  SHARED_RE=$(printf '%s' "$SHARED_NAME" | sed 's/[.]/[.]/g')

  while IFS= read -r -d '' FILE; do
    grep -qIF -- "$CORE_NAME/$SHARED_NAME" "$FILE" || continue
    REL="${FILE#"$PACK"/}"
    DIR=$(dirname "$FILE")
    N=$((N + 1))
    TMP="$WORK/out.$N"
    CHECKS="$WORK/checks.$N"
    TRAILING=1
    [ -n "$(tail -c 1 "$FILE")" ] && TRAILING=0
    awk -v core_re="$CORE_RE" -v shared_re="$SHARED_RE" -v corelen="${#CORE_NAME}" \
      -v sharedlen="${#SHARED_NAME}" -v pack="$PACK_NAME" -v trailing="$TRAILING" \
      -v checks="$CHECKS" "$rewrite_awk" "$FILE" > "$TMP" || { echo "$REL: could not be read" >> "$ERRORS"; continue; }

    CHANGED=0
    while IFS=$'\t' read -r LINE KIND COUNT REST; do
      if [ "$LINE" = "COUNT" ]; then CHANGED="$KIND"; continue; fi
      WHERE="$PACK_NAME/$REL:$LINE"
      case "$KIND" in
        plugin|script|file)
          BASE="$PACK"; [ "$KIND" = "plugin" ] || BASE="$DIR"
          if [ "$(canon "$BASE/$(ups "$COUNT")$CORE_NAME/$SHARED_NAME")" != "$CORE_SHARED" ]; then
            echo "$WHERE: does not reach the core: $(ups "$COUNT")$CORE_NAME/$SHARED_NAME" >> "$ERRORS"; continue
          fi
          NEWBASE="$PACK"
          if [ "$KIND" != "file" ]; then
            NEWBASE="$BASE/$(ups $((COUNT - 1)))"
            if [ "$(canon "$NEWBASE")" != "$PACK" ]; then
              echo "$WHERE: one level up from the core is not this pack's root" >> "$ERRORS"; continue
            fi
          fi
          ;;
        dir:*)
          if [ "${KIND#dir:}" != "$PLUGINS_NAME" ]; then
            echo "$WHERE: cannot place '${KIND#dir:}/$CORE_NAME/$SHARED_NAME'" >> "$ERRORS"; continue
          fi
          NEWBASE="$PACK"
          ;;
        anchor:*)
          echo "$WHERE: cannot place the anchor '\$${KIND#anchor:}'" >> "$ERRORS"; continue
          ;;
      esac
      if [ ! -e "$NEWBASE/core/$REST" ]; then
        echo "$WHERE: the new path does not exist: core/$REST" >> "$ERRORS"
      fi
    done < "$CHECKS"

    TYPE="other"
    case "$(basename "$FILE")" in *.*) TYPE="${FILE##*.}" ;; esac
    [ "$CHANGED" -gt 0 ] && PENDING+=("$TMP|$FILE|$TYPE|$CHANGED")
  done < <(find "$PACK" -type f -not -path '*/node_modules/*' -print0 | LC_ALL=C sort -z)
done

if [ -s "$ERRORS" ]; then
  cat "$ERRORS" >&2
  echo "rewrite-core-refs: refused, nothing written ($(wc -l < "$ERRORS" | tr -d ' ') reference(s))" >&2
  exit 1
fi

SUMMARY="$WORK/summary"
: > "$SUMMARY"
for P in ${PENDING[@]+"${PENDING[@]}"}; do
  IFS='|' read -r TMP FILE TYPE CHANGED <<< "$P"
  [ "$DRY" -eq 1 ] || cat "$TMP" > "$FILE"
  printf '%s\t%s\n' "$TYPE" "$CHANGED" >> "$SUMMARY"
done

if [ "$DRY" -eq 1 ]; then echo "would rewrite (dry run):"; else echo "rewrote:"; fi
LC_ALL=C sort "$SUMMARY" | awk -F'\t' '
  { files[$1]++; lines[$1] += $2; tf++; tl += $2 }
  END {
    for (t in files) printf "  %s: files=%d lines=%d\n", t, files[t], lines[t] | "LC_ALL=C sort"
    close("LC_ALL=C sort")
    printf "total: files=%d lines=%d\n", tf, tl
  }'
