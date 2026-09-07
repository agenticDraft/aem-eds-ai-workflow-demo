#!/usr/bin/env bash
# Tests for write-provider-packs.sh. Run with:
#   bash plugins/agentic-core/shared/lib/write-provider-packs.test.sh
#
# No framework — exits 0 on success, 1 on first failure. Mirrors the harness
# in write-detected-config.test.sh.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRITER="$SCRIPT_DIR/write-provider-packs.sh"

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

assert_file_equals() {
  local desc="$1" expected="$2" path="$3"
  local actual
  actual="$(cat "$path" 2>/dev/null || echo "<no file>")"
  if [[ "$actual" == "$expected" ]]; then
    PASS=$((PASS + 1))
    echo "  ok: $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc"
    echo "    --- expected ---"
    echo "$expected"
    echo "    --- actual ---"
    echo "$actual"
  fi
}

TMPDIR_TEST="$(mktemp -d "${TMPDIR:-/tmp}/write-provider-packs-test.XXXXXX")"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

echo "=== write-provider-packs.sh tests ==="

echo "[insert] existing file with commands/paths but no packs: block gets one inserted before commands:"
CFG="$TMPDIR_TEST/existing.yaml"
cat > "$CFG" <<'EOF'
version: 1

commands:
  lint: "run lint"
  test: ""
  build: ""
  serve: "start server"

paths:
  spec_dir: ".ai/specs"
  preview: "http://localhost:3000/preview"
EOF
OUT=$(bash "$WRITER" "$CFG" "jira" "github" 2>&1); ST=$?
assert_exit "insert succeeds (exit 0)" 0 $ST "$OUT"
assert_contains "reports updated, not written" "updated" "$OUT"
EXPECTED_INSERTED='version: 1

packs:
  tracker: jira
  scm: github

commands:
  lint: "run lint"
  test: ""
  build: ""
  serve: "start server"

paths:
  spec_dir: ".ai/specs"
  preview: "http://localhost:3000/preview"'
assert_file_equals "packs: block inserted right after version, rest untouched" "$EXPECTED_INSERTED" "$CFG"

echo "[cross-check] tracker/scm inserted next to platform/design/browser (added by hand) plus routes/limits passes validate-project-config.sh"
COMBINED="$TMPDIR_TEST/combined.yaml"
{
  sed -n '/^version:/,/^packs:$/p' "$CFG" | sed '$d'
  echo "packs:"
  echo "  platform: example-platform"
  sed -n '/^  tracker:/,/^  scm:/p' "$CFG"
  echo "  design: none"
  echo "  browser: example-browser"
  echo
  sed -n '/^commands:$/,$p' "$CFG"
  echo
  echo "routes:"
  echo "  - id: standard"
  echo "    stages: [intake, deliver]"
  echo "  default: standard"
  echo
  echo "limits:"
  echo "  questions_per_run: 3"
  echo "  fix_attempts_default: 2"
} > "$COMBINED"
OUT=$(bash "$SCRIPT_DIR/validate-project-config.sh" "$COMBINED" 2>&1); ST=$?
assert_exit "spliced file passes validate-project-config.sh (exit 0)" 0 $ST "$OUT"

echo "[create] fresh file gets version + packs, nothing else"
FRESH="$TMPDIR_TEST/fresh.yaml"
OUT=$(bash "$WRITER" "$FRESH" "jira" "github" 2>&1); ST=$?
assert_exit "fresh create succeeds (exit 0)" 0 $ST "$OUT"
assert_contains "reports the path written" "$FRESH" "$OUT"
EXPECTED_FRESH='version: 1

packs:
  tracker: jira
  scm: github'
assert_file_equals "fresh file matches expected shape exactly" "$EXPECTED_FRESH" "$FRESH"

echo "[update] re-running on a file that already has a packs: block updates values in place, no duplication"
OUT=$(bash "$WRITER" "$CFG" "jira-cloud" "github-enterprise" 2>&1); ST=$?
assert_exit "update succeeds (exit 0)" 0 $ST "$OUT"
assert_contains "reports updated" "updated" "$OUT"
EXPECTED_UPDATED='version: 1

packs:
  tracker: jira-cloud
  scm: github-enterprise

commands:
  lint: "run lint"
  test: ""
  build: ""
  serve: "start server"

paths:
  spec_dir: ".ai/specs"
  preview: "http://localhost:3000/preview"'
assert_file_equals "packs: values updated in place, no dup blocks" "$EXPECTED_UPDATED" "$CFG"

echo "[reject] empty tracker name"
CFG2="$TMPDIR_TEST/empty-tracker.yaml"
OUT=$(bash "$WRITER" "$CFG2" "" "github" 2>&1); ST=$?
assert_exit "empty tracker rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names tracker" "tracker" "$OUT"
if [[ -f "$CFG2" ]]; then
  FAIL=$((FAIL + 1))
  echo "  FAIL: no file written on rejection"
else
  PASS=$((PASS + 1))
  echo "  ok: no file written on rejection"
fi

echo "[reject] empty scm name"
CFG3="$TMPDIR_TEST/empty-scm.yaml"
OUT=$(bash "$WRITER" "$CFG3" "jira" "" 2>&1); ST=$?
assert_exit "empty scm rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names scm" "scm" "$OUT"

echo "[reject] a value containing a double quote"
CFG4="$TMPDIR_TEST/bad-quote.yaml"
OUT=$(bash "$WRITER" "$CFG4" 'jira"cloud' "github" 2>&1); ST=$?
assert_exit "quote-containing value rejected (exit 1)" 1 $ST "$OUT"

echo "[usage] wrong argument count"
OUT=$(bash "$WRITER" "$TMPDIR_TEST/x.yaml" "jira" 2>&1); ST=$?
assert_exit "wrong arg count -> usage error (exit 2)" 2 $ST "$OUT"

echo "[create] parent directory does not exist yet — script creates it"
CFG5="$TMPDIR_TEST/nested/dir/config.yaml"
OUT=$(bash "$WRITER" "$CFG5" "jira" "github" 2>&1); ST=$?
assert_exit "create under a missing parent directory succeeds (exit 0)" 0 $ST "$OUT"
if [[ -f "$CFG5" ]]; then
  PASS=$((PASS + 1))
  echo "  ok: file exists under the newly created parent directory"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: file was not created under the newly created parent directory"
fi

echo "[reject] existing packs: block not in the expected two-line shape"
CFG6="$TMPDIR_TEST/malformed-packs.yaml"
cat > "$CFG6" <<'EOF'
version: 1

packs:
  platform: example-platform
  tracker: example-tracker
  scm: example-scm
  design: none
  browser: example-browser

commands:
  lint: ""
  test: ""
  build: ""
  serve: ""

paths:
  spec_dir: "specs"
  preview: "http://localhost:3000/preview"
EOF
OUT=$(bash "$WRITER" "$CFG6" "jira" "github" 2>&1); ST=$?
assert_exit "malformed existing packs: block rejected (exit 1)" 1 $ST "$OUT"

echo "[reject] no 'version:' line to anchor an insertion against"
CFG7="$TMPDIR_TEST/no-version.yaml"
cat > "$CFG7" <<'EOF'
commands:
  lint: ""
EOF
OUT=$(bash "$WRITER" "$CFG7" "jira" "github" 2>&1); ST=$?
assert_exit "missing version: line rejected (exit 1)" 1 $ST "$OUT"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
