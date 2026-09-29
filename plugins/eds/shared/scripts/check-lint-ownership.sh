#!/usr/bin/env bash
# Run: bash plugins/eds/shared/scripts/check-lint-ownership.sh plugins/eds/skills
#
# check-lint-ownership.sh <skills dir>
#
# Deterministic. The lint stage owns lint: it alone runs the project's
# configured lint command, inside its own edit budget. Fails when another
# skill's text would run a linter, or when prototype's text would report a
# lint result. Three checks:
#
#   1. Every skill except `eds-lint`: no line names `eslint`, `stylelint` or
#      `commands.lint`.
#   2. `eds-prototype`: its `### Write the prototype report` node exists and
#      names no lint.
#   3. `eds-prototype`: states "runs no linter and reports no lint result" and
#      names the `lint` stage as the owner.
#
# Exit codes: 0 — every skill conforms; 1 — at least one violation, each named
# on stderr; 2 — usage.

set -uo pipefail

usage() {
  echo "usage: check-lint-ownership.sh <skills dir>" >&2
  if [ "$#" -gt 0 ]; then echo "$1" >&2; fi
  exit 2
}

[ "$#" -eq 1 ] || usage "expected exactly 1 argument"
DIR="$1"
[ -d "$DIR" ] || usage "'$DIR' is not a directory"

VIOLATIONS=0
SKILLS=0

violation() {
  echo "invalid: $1" >&2
  VIOLATIONS=$((VIOLATIONS + 1))
}

# Prints the body of one `### <heading>` section: every line after the heading
# up to the next `#`/`##`/`###` heading outside a fenced block.
section() {
  awk -v want="### $2" '
    /^```/ { if (on) print; fence = !fence; next }
    !fence && /^#{1,3} / { if (on) exit; if ($0 == want) { on = 1; next } }
    on { print }
  ' "$1"
}

for skill in "$DIR"/*/SKILL.md; do
  [ -f "$skill" ] || continue
  SKILLS=$((SKILLS + 1))
  [ "$(basename "$(dirname "$skill")")" = "eds-lint" ] && continue

  hits=$(grep -niE '(^|[^a-z.])(eslint|stylelint)([^a-z]|$)|commands\.lint' "$skill")
  if [ -n "$hits" ]; then
    while IFS= read -r hit; do
      violation "$skill:${hit%%:*}: runs a linter outside the lint stage"
    done <<< "$hits"
  fi
done

PROTOTYPE="$DIR/eds-prototype/SKILL.md"
if [ ! -f "$PROTOTYPE" ]; then
  violation "$PROTOTYPE: not found"
else
  body=$(section "$PROTOTYPE" "Write the prototype report")
  if [ -z "$body" ]; then
    violation "$PROTOTYPE: no '### Write the prototype report' node"
  elif printf '%s\n' "$body" | grep -qi 'lint'; then
    violation "$PROTOTYPE: 'Write the prototype report' asks for a lint result"
  fi

  grep -qF 'runs no linter and reports no lint result' "$PROTOTYPE" \
    || violation "$PROTOTYPE: does not state it runs no linter and reports no lint result"
  grep -qF 'the `lint` stage' "$PROTOTYPE" \
    || violation "$PROTOTYPE: does not name the \`lint\` stage as lint's owner"
fi

if [ "$VIOLATIONS" -gt 0 ]; then
  exit 1
fi
echo "valid: lint ownership ($SKILLS skills)"
exit 0
