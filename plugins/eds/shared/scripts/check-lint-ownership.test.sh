#!/usr/bin/env bash
# check-lint-ownership.test.sh — the pack's own skills conform, and each
# violation the checker names is caught on a copy made to break it.
#
# Usage:
#   bash check-lint-ownership.test.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/check-lint-ownership.sh"
SKILLS="$SCRIPT_DIR/../../skills"

PASS=0
FAIL=0

expect() {
  local desc="$1" want_exit="$2" want_text="$3" dir="$4" out rc
  out=$(bash "$CHECK" "$dir" 2>&1); rc=$?
  if [ "$rc" -eq "$want_exit" ] && [[ "$out" == *"$want_text"* ]]; then
    echo "  ok: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    echo "    expected exit=$want_exit containing: $want_text"
    echo "    got exit=$rc: $out"
    FAIL=$((FAIL + 1))
  fi
}

WORK=$(mktemp -d "${TMPDIR:-/tmp}/check-lint-ownership.XXXXXX") || { echo "cannot create a temp dir" >&2; exit 2; }
[ -n "$WORK" ] && [ -d "$WORK" ] || { echo "cannot create a temp dir" >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT

# A fresh copy of prototype, the lint stage and two other block-editing stages, per case.
fresh() {
  rm -rf "$WORK/skills"
  mkdir -p "$WORK/skills"
  cp -R "$SKILLS/eds-prototype" "$SKILLS/eds-lint" "$SKILLS/eds-implement" \
    "$SKILLS/eds-verify-design" "$WORK/skills/"
}

# Appends one line to a named section of a copied SKILL.md.
append_to_section() {
  local file="$1" heading="$2" line="$3"
  awk -v want="### $heading" -v add="$line" '
    $0 == want { on = 1; print; next }
    on && /^#{1,3} / { print add; print ""; on = 0 }
    { print }
  ' "$file" > "$file.new" && mv "$file.new" "$file"
}

echo "[accept] this pack's own skills"
expect "plugins/eds/skills conforms" 0 "valid: lint ownership" "$SKILLS"

fresh
printf '\nRun `npx eslint blocks/` and `npx stylelint "blocks/**/*.css"`.\n' \
  >> "$WORK/skills/eds-lint/SKILL.md"
expect "the lint stage may name a linter" 0 "valid: lint ownership" "$WORK/skills"

echo "[reject] a linter named outside the lint stage"
fresh
printf '\nAfter writing the CSS, run `npx stylelint blocks/<name>/<name>.css`.\n' \
  >> "$WORK/skills/eds-prototype/SKILL.md"
expect "prototype: bare stylelint" 1 "eds-prototype/SKILL.md" "$WORK/skills"

fresh
printf '\nCheck the JS with `eslint blocks/<name>/<name>.js`.\n' \
  >> "$WORK/skills/eds-verify-design/SKILL.md"
expect "any other stage: bare eslint" 1 "eds-verify-design/SKILL.md" "$WORK/skills"

fresh
printf '\nRun `.ai/project-config.yaml`'"'"'s `commands.lint` after each edit.\n' \
  >> "$WORK/skills/eds-implement/SKILL.md"
expect "any other stage: commands.lint" 1 "runs a linter outside the lint stage" "$WORK/skills"

echo "[reject] a lint result asked of the prototype report"
fresh
append_to_section "$WORK/skills/eds-prototype/SKILL.md" "Write the prototype report" \
  "Add a \`## Lint\` section: what the project's linters report on the changed files."
expect "report section names lint" 1 "'Write the prototype report' asks for a lint result" "$WORK/skills"

fresh
awk '/^### Write the prototype report$/ { skip = 1; next } skip && /^#{2,3} / { skip = 0 } !skip { print }' \
  "$WORK/skills/eds-prototype/SKILL.md" > "$WORK/p" && mv "$WORK/p" "$WORK/skills/eds-prototype/SKILL.md"
expect "a missing report node" 1 "no '### Write the prototype report' node" "$WORK/skills"

echo "[reject] prototype does not state the rule"
fresh
sed 's/runs no linter and reports no lint result/does its work/' \
  "$WORK/skills/eds-prototype/SKILL.md" > "$WORK/p" && mv "$WORK/p" "$WORK/skills/eds-prototype/SKILL.md"
expect "rule sentence removed" 1 "does not state it runs no linter" "$WORK/skills"

fresh
sed 's/the `lint` stage/a later stage/g' \
  "$WORK/skills/eds-prototype/SKILL.md" > "$WORK/p" && mv "$WORK/p" "$WORK/skills/eds-prototype/SKILL.md"
expect "owner not named" 1 'does not name the `lint` stage' "$WORK/skills"

fresh
rm -rf "$WORK/skills/eds-prototype"
expect "prototype missing" 1 "eds-prototype/SKILL.md: not found" "$WORK/skills"

echo "[usage]"
expect "no argument" 2 "usage" ""
expect "not a directory" 2 "is not a directory" "$WORK/absent"

echo ""
echo "=== $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
