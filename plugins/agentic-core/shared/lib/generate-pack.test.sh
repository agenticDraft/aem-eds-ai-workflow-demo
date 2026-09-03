#!/usr/bin/env bash
# Tests for generate-pack.sh. Run with:
#   bash plugins/agentic-core/shared/lib/generate-pack.test.sh
#
# No framework — exits 0 on success, 1 on first failure.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GENERATOR="$SCRIPT_DIR/generate-pack.sh"
MANIFEST_VALIDATOR="$SCRIPT_DIR/validate-pack-manifest.sh"
TMPDIR_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/generate-pack-test.XXXXXX")"
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

echo "=== generate-pack.sh tests ==="

echo "[generate] against a directory with no code at all"
PACK_ROOT="$TMPDIR_ROOT/zero-code-project/.ai/packs/acme"
OUT=$(bash "$GENERATOR" "$PACK_ROOT" \
  "components/, one directory per component" \
  "the component renders with no console errors" \
  "none" \
  "the project's lint and test commands both exit 0" \
  2>&1); ST=$?
assert_exit "generator exits 0 (exit 0)" 0 $ST "$OUT"
assert_contains "reports written" "written: $PACK_ROOT" "$OUT"

echo "[structure] every declared stage has a SKILL.md"
for stage in intake implement publish-gate deliver; do
  if [[ -f "$PACK_ROOT/skills/$stage/SKILL.md" ]]; then
    PASS=$((PASS + 1)); echo "  ok: skills/$stage/SKILL.md exists"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: skills/$stage/SKILL.md missing"
  fi
done

echo "[content] the answers reach the relevant stage stubs"
IMPLEMENT_BODY="$(cat "$PACK_ROOT/skills/implement/SKILL.md")"
assert_contains "implement mentions unit of work location" "components/, one directory per component" "$IMPLEMENT_BODY"
assert_contains "implement mentions definition of done" "the component renders with no console errors" "$IMPLEMENT_BODY"
GATE_BODY="$(cat "$PACK_ROOT/skills/publish-gate/SKILL.md")"
assert_contains "publish-gate mentions the verification gate" "the project's lint and test commands both exit 0" "$GATE_BODY"

echo "[validates] the generated pack passes validate-pack-manifest.sh"
VALID_OUT=$(bash "$MANIFEST_VALIDATOR" "$PACK_ROOT/pack.yaml" 2>&1); VALID_ST=$?
assert_exit "generated pack.yaml passes the manifest validator" 0 $VALID_ST "$VALID_OUT"
assert_contains "reports platform kind" "valid: platform" "$VALID_OUT"

echo "[no placeholders] nothing under the pack root still carries {{"
if grep -rq '{{' "$PACK_ROOT"; then
  FAIL=$((FAIL + 1)); echo "  FAIL: a {{ placeholder survived generation"
else
  PASS=$((PASS + 1)); echo "  ok: no {{ anywhere under the pack root"
fi

echo "[re-run] a second run against the same root updates rather than errors"
OUT2=$(bash "$GENERATOR" "$PACK_ROOT" \
  "components/, one directory per component" \
  "the component renders with no console errors" \
  "none" \
  "lint only now" \
  2>&1); ST2=$?
assert_exit "re-run exits 0" 0 $ST2 "$OUT2"
assert_contains "reports updated" "updated: $PACK_ROOT" "$OUT2"
assert_contains "new answer present" "lint only now" "$(cat "$PACK_ROOT/skills/publish-gate/SKILL.md")"

echo "[reject] an empty answer"
OUT3=$(bash "$GENERATOR" "$TMPDIR_ROOT/reject-empty" "" "done" "none" "lint" 2>&1); ST3=$?
assert_exit "empty answer rejected (exit 1)" 1 $ST3 "$OUT3"

echo "[reject] an answer carrying the placeholder marker itself"
OUT4=$(bash "$GENERATOR" "$TMPDIR_ROOT/reject-marker" "components/" "done {{whoops}}" "none" "lint" 2>&1); ST4=$?
assert_exit "placeholder-marker answer rejected (exit 1)" 1 $ST4 "$OUT4"

echo "[usage] wrong argument count"
OUT5=$(bash "$GENERATOR" "$TMPDIR_ROOT/reject-usage" "only-one-arg" 2>&1); ST5=$?
assert_exit "wrong arg count -> usage error (exit 2)" 2 $ST5 "$OUT5"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
