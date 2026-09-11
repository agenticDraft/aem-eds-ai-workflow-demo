#!/usr/bin/env bash
# check-markup-conventions.sh — Deterministic survey of this project's own
# block CSS scoping form (D30). No model involved; the calling skill's own
# job is naming which files (if any) drift from the form the majority use.
#
# Usage:
#   check-markup-conventions.sh [project-root]
#
# `project-root` defaults to the current directory. Surveys every
# `blocks/*/*.css` file's top-level selectors and classifies each file by
# which scoping form it uses:
#   scoped      — every top-level selector starts with `.<blockname>` (the
#                 `.blockname .child` form D30 measured) or with the bare
#                 `<blockname>` tag itself, no leading dot — the form this
#                 project's own `header`/`footer` blocks use, since those two
#                 render as the semantic element itself rather than a
#                 `<div class="blockname block">` wrapper. Both are a file
#                 correctly scoped to its own block; which of the two a given
#                 file uses is not itself a drift.
#   at-scope    — the file uses an `@scope` rule
#   main-prefix — a top-level selector starts with `main .`
#   mixed       — more than one of the three forms above appears in the file
#   unclassified — no top-level selector matched any of the above (an empty
#                 or comment-only file, or a form none of the checks above
#                 anticipated) — reported by name rather than silently
#                 folded into `scoped`'s count or dropped from the total.
#
# Output:
#   decision=no-blocks
#     — or —
#   decision=surveyed blocks=<n> scoped=<n> at-scope=<n> main-prefix=<n> mixed=<n> unclassified=<n>
#   drift=<blockname>[,<blockname>…]          # only when at-scope/main-prefix/mixed > 0
#   review=<blockname>[,<blockname>…]         # only when unclassified > 0
#
# Exit codes:
#   0 — decided (every branch above is a decision, not an error)
#   2 — usage error

set -uo pipefail

ROOT="${1:-.}"

shopt -s nullglob
css_files=("$ROOT"/blocks/*/*.css)
shopt -u nullglob

if [[ ${#css_files[@]} -eq 0 ]]; then
  echo "decision=no-blocks"
  exit 0
fi

scoped=0
at_scope=0
main_prefix=0
mixed=0
unclassified=0
drift=()
review=()

for f in "${css_files[@]}"; do
  blockname="$(basename "$(dirname "$f")")"
  has_dot_scoped=0
  has_tag_scoped=0
  has_at_scope=0
  has_main_prefix=0

  grep -qE '@scope[[:space:]]*\(' "$f" && has_at_scope=1
  grep -qE '^main[[:space:]]+\.' "$f" && has_main_prefix=1
  grep -qE "^\\.${blockname}([[:space:]>.]|\$)" "$f" && has_dot_scoped=1
  grep -qE "^${blockname}([[:space:]{]|\$)" "$f" && has_tag_scoped=1

  has_scoped=$(( has_dot_scoped || has_tag_scoped ))
  count_true=$(( has_scoped + has_at_scope + has_main_prefix ))

  if (( count_true > 1 )); then
    mixed=$((mixed + 1))
    drift+=("$blockname")
  elif (( has_at_scope == 1 )); then
    at_scope=$((at_scope + 1))
    drift+=("$blockname")
  elif (( has_main_prefix == 1 )); then
    main_prefix=$((main_prefix + 1))
    drift+=("$blockname")
  elif (( has_scoped == 1 )); then
    scoped=$((scoped + 1))
  else
    unclassified=$((unclassified + 1))
    review+=("$blockname")
  fi
done

echo "decision=surveyed blocks=${#css_files[@]} scoped=$scoped at-scope=$at_scope main-prefix=$main_prefix mixed=$mixed unclassified=$unclassified"
if [[ ${#drift[@]} -gt 0 ]]; then
  IFS=,; echo "drift=${drift[*]}"; unset IFS
fi
if [[ ${#review[@]} -gt 0 ]]; then
  IFS=,; echo "review=${review[*]}"; unset IFS
fi
exit 0
