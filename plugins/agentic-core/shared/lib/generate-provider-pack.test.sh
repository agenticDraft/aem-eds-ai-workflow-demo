#!/usr/bin/env bash
# Tests for generate-provider-pack.sh. Run with:
#   bash plugins/agentic-core/shared/lib/generate-provider-pack.test.sh
#
# No framework — exits 0 on success, 1 on first failure.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GENERATOR="$SCRIPT_DIR/generate-provider-pack.sh"
MANIFEST_VALIDATOR="$SCRIPT_DIR/validate-pack-manifest.sh"
TMPDIR_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/generate-provider-pack-test.XXXXXX")"
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

PASS=0
FAIL=0

assert_exit() {
  local desc="$1" expected="$2" actual="$3" output="$4"
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1))
    echo "  ok: $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc"
    echo "    expected exit=$expected, got exit=$actual"
    [[ -n "$output" ]] && echo "    output: $output"
  fi
}

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    PASS=$((PASS + 1))
    echo "  ok: $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc"
    echo "    expected output to contain: $needle"
    echo "    got: $haystack"
  fi
}

assert_equal() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1))
    echo "  ok: $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc"
    echo "    expected: $expected"
    echo "    got:      $actual"
  fi
}

echo "=== generate-provider-pack.sh tests ==="

# --- usage ------------------------------------------------------------------
OUT="$("$GENERATOR" 2>&1)"; assert_exit "no arguments -> usage error" 2 $? "$OUT"
OUT="$("$GENERATOR" "$TMPDIR_ROOT/a" 2>&1)"; assert_exit "one argument -> usage error" 2 $? "$OUT"
OUT="$("$GENERATOR" "$TMPDIR_ROOT/a" tracker extra 2>&1)"; assert_exit "three arguments -> usage error" 2 $? "$OUT"

# --- role checking ----------------------------------------------------------
OUT="$("$GENERATOR" "$TMPDIR_ROOT/unknown" reviewer 2>&1)"; RC=$?
assert_exit "unknown role -> contract violation" 1 "$RC" "$OUT"
assert_contains "unknown role is named back" "'reviewer'" "$OUT"
assert_contains "unknown role lists the real roles" "tracker scm design browser" "$OUT"
if [[ -e "$TMPDIR_ROOT/unknown" ]]; then
  FAIL=$((FAIL + 1)); echo "  FAIL: an unknown role must not create a pack root"
else
  PASS=$((PASS + 1)); echo "  ok: an unknown role creates nothing"
fi

OUT="$("$GENERATOR" "" tracker 2>&1)"; assert_exit "empty pack root -> contract violation" 1 $? "$OUT"

# --- every role produces a valid skeleton ------------------------------------
for role in tracker scm design browser; do
  ROOT="$TMPDIR_ROOT/$role"
  OUT="$("$GENERATOR" "$ROOT" "$role" 2>&1)"; RC=$?
  assert_exit "$role: generates" 0 "$RC" "$OUT"
  assert_contains "$role: reports the file it wrote" "written: $ROOT/pack.yaml" "$OUT"

  VOUT="$("$MANIFEST_VALIDATOR" "$ROOT/pack.yaml" 2>&1)"; VRC=$?
  assert_exit "$role: skeleton validates" 0 "$VRC" "$VOUT"
  assert_contains "$role: validates as a provider" "valid: provider" "$VOUT"

  assert_contains "$role: declares the role" "role: $role" "$(cat "$ROOT/pack.yaml")"
  assert_contains "$role: implements nothing" "operations: {}" "$(cat "$ROOT/pack.yaml")"
done

# --- completeness: the skeleton's list is the validator's own list -----------
# The generator carries its own copy of the role -> operations table. This is
# the check that the copy has not drifted from the one the validator enforces:
# both lists are read back out and compared, per role, name for name.
for role in tracker scm design browser; do
  FROM_VALIDATOR="$(
    grep -E "^[[:space:]]*$role\)[[:space:]]*ROLE_OPS=\(" "$MANIFEST_VALIDATOR" \
      | sed -E 's/.*ROLE_OPS=\(([^)]*)\).*/\1/' \
      | tr ' ' '\n' | sed '/^$/d' | sort | tr '\n' ' '
  )"
  FROM_SKELETON="$(
    grep -E '^unsupported: \[' "$TMPDIR_ROOT/$role/pack.yaml" \
      | sed -E 's/^unsupported: \[(.*)\]$/\1/' \
      | tr ',' '\n' | tr -d ' ' | sed '/^$/d' | sort | tr '\n' ' '
  )"
  assert_equal "$role: skeleton lists exactly the operations the validator knows" \
    "$FROM_VALIDATOR" "$FROM_SKELETON"
done

# --- never overwrites --------------------------------------------------------
GUARDED="$TMPDIR_ROOT/installed"
mkdir -p "$GUARDED"
printf 'kind: provider\nrole: tracker\noperations:\n  fetch_item: fetch\nunsupported: [post_note, attach_file, list_types]\n' \
  > "$GUARDED/pack.yaml"
BEFORE="$(cat "$GUARDED/pack.yaml")"

OUT="$("$GENERATOR" "$GUARDED" tracker 2>&1)"; RC=$?
assert_exit "an installed pack is not overwritten" 1 "$RC" "$OUT"
assert_contains "the collision names the manifest" "$GUARDED/pack.yaml" "$OUT"
assert_contains "the collision says to ask first" "ask first" "$OUT"
assert_equal "the installed manifest is byte-identical afterwards" "$BEFORE" "$(cat "$GUARDED/pack.yaml")"

# A different role against the same root is still a collision: the root holds
# a pack, and which role it declares is not this script's to second-guess.
OUT="$("$GENERATOR" "$GUARDED" browser 2>&1)"; RC=$?
assert_exit "a different role against an installed pack is still refused" 1 "$RC" "$OUT"

# --- no operation logic ------------------------------------------------------
ROOT="$TMPDIR_ROOT/tracker"
SKILL_COUNT="$(find "$ROOT" -name 'SKILL.md' 2>/dev/null | wc -l | tr -d ' ')"
assert_equal "the skeleton ships no operation logic" "0" "$SKILL_COUNT"

echo
if [[ "$FAIL" -eq 0 ]]; then
  echo "=== $PASS passed, 0 failed ==="
  exit 0
fi
echo "=== $PASS passed, $FAIL failed ==="
exit 1
