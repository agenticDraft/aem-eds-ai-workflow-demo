#!/usr/bin/env bash
# check-spec.test.sh — Coverage for check-spec.py: one case per form rule it
# enforces, plus the readiness case a draft can fail without breaking any form
# rule (a visual change with no design reference attached).
#
# Every case is the conforming draft with one thing changed, written inline
# rather than shipped as a fixture file, so a case and the rule it covers stay
# in one place.
#
# Usage:
#   bash check-spec.test.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECKER="$SCRIPT_DIR/check-spec.py"
# An explicit template, not a bare "mktemp -d": on this platform the bare form
# ignores TMPDIR and picks a per-user directory a sandboxed run may not write to.
TMP="$(mktemp -d "${TMPDIR:-/tmp}/check-spec.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0

# A draft that satisfies every rule.
clean_draft() {
  cat <<'EOF'
---
item_type: Story
summary: Features carousel block
---

## Description

Add a features carousel to blocks/features-carousel/, authored through the
project's standard table-based content model.

## Design reference

https://www.figma.com/design/B1rwvloGdmUrozvkBQ0vKP/Zoki?node-id=1-167

## Acceptance criteria

AC-1 A block directory blocks/features-carousel/ exists.
AC-2 Every spacing value resolves to an adopted design-system token.

## Out of scope

Any change to another block.
EOF
}

# run_case <label> <expected exit> <expected substring> <draft text>
# The draft arrives as an argument rather than on stdin: a pipeline would run
# this function in a subshell, and the pass/fail counters would never survive it.
run_case() {
  local label="$1" expected_exit="$2" expected="$3" draft_text="$4"
  local draft="$TMP/${label// /-}.md" out actual_exit
  printf '%s\n' "$draft_text" > "$draft"
  out="$(python3 "$CHECKER" "$draft" 2>&1)"
  actual_exit=$?
  if [[ "$actual_exit" == "$expected_exit" && "$out" == *"$expected"* ]]; then
    echo "  ok: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label"
    echo "    expected exit $expected_exit containing: $expected"
    echo "    got exit $actual_exit:"
    echo "$out" | sed 's/^/      /'
    FAIL=$((FAIL + 1))
  fi
}

echo "[accepts a conforming draft]"
run_case "clean story" 0 "valid: write-specs" "$(clean_draft)"

echo "[form violations]"
run_case "criterion with no id" 1 "carries no AC-<n> id" \
  "$(clean_draft | sed 's|^AC-1 A block directory|- A block directory|')"

run_case "ids not sequential" 1 "not sequential from 1" \
  "$(clean_draft | sed 's|^AC-2 |AC-4 |')"

run_case "semicolon in a criterion" 1 "semicolon" \
  "$(clean_draft | sed 's|^AC-2 .*|AC-2 Spacing resolves to a token; colour does too.|')"

run_case "unverifiable wording" 1 "no pass/fail threshold" \
  "$(clean_draft | sed 's|^AC-2 .*|AC-2 The block renders properly.|')"

run_case "two sentences in a criterion" 1 "more than one sentence" \
  "$(clean_draft | sed 's|^AC-2 .*|AC-2 The list renders. The button renders.|')"

run_case "no out-of-scope section" 1 "an out-of-scope section" \
  "$(clean_draft | sed '/^## Out of scope$/,$d')"

run_case "summary is a sentence" 1 "ends in a full stop" \
  "$(clean_draft | sed 's|^summary: .*|summary: Add a features carousel block to the project.|')"

run_case "summary too long" 1 "more than 8" \
  "$(clean_draft | sed 's|^summary: .*|summary: Features carousel block with a numbered list and a button image|')"

run_case "component path without its slash" 1 "no trailing slash" \
  "$(clean_draft | sed 's|blocks/features-carousel/ exists|blocks/features-carousel exists|')"

echo "[readiness, not form]"
run_case "visual change with no design reference" 1 "readiness would fail" \
  "$(clean_draft | sed '/^https:\/\/www.figma.com/d')"

echo "[item type with its own rules]"
run_case "bug with no reproduction steps" 1 "reproduction steps" \
  "$(clean_draft | sed 's|^item_type: Story|item_type: Bug|')"

echo "[content an item cites]"
run_case "keyed item citing another item's draft" 1 "requires 'reproduction_content_ok'" \
  "$(clean_draft | sed 's|^item_type: Story|item_type: Story\
item_id: EDS-99|; s|^project.s standard.*|&\
Open http://localhost:3001/drafts/EDS-18 to see it.|')"
run_case "keyless draft citing a draft" 0 "review: reproduction_content_ok not checked" \
  "$(clean_draft | sed 's|^project.s standard.*|&\
Open http://localhost:3001/drafts/new-item to see it.|')"

echo "[review notes do not fail the run]"
run_case "criterion joined with and" 0 "review: AC-2 contains 'and'" \
  "$(clean_draft | sed 's|^AC-2 .*|AC-2 The list and the button render through the global styles.|')"

echo "[plugin roots come from the resolver]"
# A project of its own: these scripts, this project's config, and a registry
# naming copies of the plugins in a folder with another name. The copies are
# found through this project's own registry, the way the scripts find them.
REAL="$(cd "$SCRIPT_DIR/../../../.." && pwd -P)"
CORE_NAME="agentic-core"
REAL_CORE="$(head -n 1 "$REAL/.ai/run-context/plugin-roots/$CORE_NAME" 2>/dev/null)"
RESOLVER="$REAL_CORE/shared/lib/resolve-plugin-root.sh"
PROJ="$TMP/project"
CACHE="$TMP/cache"
mkdir -p "$PROJ/.claude/skills/write-specs" "$PROJ/.ai/run-context/plugin-roots" "$CACHE"
cp -R "$SCRIPT_DIR" "$PROJ/.claude/skills/write-specs/scripts"
cp "$REAL/.ai/project-config.yaml" "$PROJ/.ai/project-config.yaml"
role_pack() { sed -n "s/^  $1: *//p" "$PROJ/.ai/project-config.yaml"; }
register() { printf '%s\n' "$2" > "$PROJ/.ai/run-context/plugin-roots/$1"; }
for name in "$CORE_NAME" "$(role_pack platform)" "$(role_pack tracker)"; do
  root="$(bash "$RESOLVER" "$name" --project-dir "$REAL" 2>/dev/null)"
  [[ -n "$root" ]] && rsync -a --exclude node_modules "$root/" "$CACHE/$name/" \
    && register "$name" "$CACHE/$name"
done

# run_in <label> <expected exit> <expected substring> <command...> — in $PROJ
run_in() {
  local label="$1" expected_exit="$2" expected="$3" out actual_exit
  shift 3
  out="$(cd "$PROJ" && "$@" 2>&1)"
  actual_exit=$?
  if [[ "$actual_exit" == "$expected_exit" && "$out" == *"$expected"* ]]; then
    echo "  ok: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label"
    echo "    expected exit $expected_exit containing: $expected"
    echo "    got exit $actual_exit:"
    echo "$out" | sed 's/^/      /'
    FAIL=$((FAIL + 1))
  fi
}
PCHECK="$PROJ/.claude/skills/write-specs/scripts/check-spec.py"
PWRITE="$PROJ/.claude/skills/write-specs/scripts/write-item.py"
clean_draft > "$TMP/registry.md"
TRACKER="$(role_pack tracker)"

run_in "checks a draft against the registered copies" 0 "valid: write-specs" \
  python3 "$PCHECK" "$TMP/registry.md"
run_in "write-item reaches the registered tracker pack" 2 "this is a create" \
  python3 "$PWRITE" "$TMP/registry.md"

register "$TRACKER" "$TMP/gone"
run_in "a stale pack entry is refused" 2 "refused: $TRACKER" \
  python3 "$PCHECK" "$TMP/registry.md"
run_in "write-item refuses a stale pack entry" 2 "refused: $TRACKER" \
  python3 "$PWRITE" "$TMP/registry.md"
register "$TRACKER" "$CACHE/$TRACKER"

register "$CORE_NAME" "$TMP/gone"
run_in "a stale core entry is refused" 2 "refused: $CORE_NAME" \
  python3 "$PCHECK" "$TMP/registry.md"
rm "$PROJ/.ai/run-context/plugin-roots/$CORE_NAME"
run_in "no core entry is not resolved" 2 "not resolved: $CORE_NAME" \
  python3 "$PCHECK" "$TMP/registry.md"

echo "[an item is never rewritten onto another component]"
# A tracker pack whose fetch returns the item in $STUB_ITEM and whose update
# only reports success, so write-item's own decision is what is under test.
register "$CORE_NAME" "$CACHE/$CORE_NAME"
STUB="$TMP/stub-tracker"
rsync -a "$CACHE/$TRACKER/" "$STUB/"
fetch_op="$(sed -n 's/^  fetch_item: *//p' "$STUB/pack.yaml")"
update_op="$(sed -n 's/^  update_item: *//p' "$STUB/pack.yaml")"
cat > "$STUB/skills/$fetch_op/scripts/$fetch_op.sh" <<'EOF'
#!/usr/bin/env bash
mkdir -p .ai/tracker
cp "$STUB_ITEM" ".ai/tracker/fetch-item-$1.json"
printf '## Result\nverdict: pass\nsummary: Fetched %s.\nartifacts: []\nnext_action: none\n' "$1"
EOF
cat > "$STUB/skills/$update_op/scripts/$update_op.sh" <<'EOF'
#!/usr/bin/env bash
printf '## Result\nverdict: pass\nsummary: Stub updated %s.\nartifacts: []\nnext_action: none\n' "$1"
EOF
register "$TRACKER" "$STUB"

# live_item <components, comma-separated> <block named in its text>
live_item() {
  local comps="" c
  for c in ${1//,/ }; do comps="$comps${comps:+,}{\"name\":\"$c\"}"; done
  cat > "$TMP/live.json" <<EOF
{"key":"EDS-99","fields":{"issuetype":{"name":"Story"},"summary":"Live item","labels":[],
 "components":[$comps],"attachment":[],
 "description":{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text",
  "text":"Change blocks/$2/ as the design shows."}]}]}}}
EOF
}
export STUB_ITEM="$TMP/live.json"
clean_draft | sed 's|^item_type: Story|item_type: Story\
item_id: EDS-99|' > "$TMP/keyed.md"
clean_draft | sed 's|^item_type: Story|item_type: Story\
item_id: EDS-99\
components: [features-carousel]|' > "$TMP/keyed-component.md"

live_item "carousel" "features-carousel"
run_in "live component the draft drops is refused" 1 "create a new item" \
  python3 "$PWRITE" "$TMP/keyed.md"
live_item "" "carousel"
run_in "draft naming none of the live blocks is refused" 1 "create a new item" \
  python3 "$PWRITE" "$TMP/keyed.md"
live_item "" "features-carousel"
run_in "same block, no components, is updated" 0 "Stub updated EDS-99" \
  python3 "$PWRITE" "$TMP/keyed.md"
live_item "features-carousel" "features-carousel"
run_in "same component kept in the draft is updated" 0 "Stub updated EDS-99" \
  python3 "$PWRITE" "$TMP/keyed-component.md"

# Both spellings: a path literal, and a path built from a "plugins" segment.
if grep -nE "plugins/|[\"']plugins[\"']" "$CHECKER" "$SCRIPT_DIR/write-item.py"; then
  echo "  FAIL: a script names a plugins/ path"
  FAIL=$((FAIL + 1))
else
  echo "  ok: neither script names a plugins/ path"
  PASS=$((PASS + 1))
fi

echo
echo "passed: $PASS  failed: $FAIL"
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
