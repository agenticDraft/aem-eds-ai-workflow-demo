#!/usr/bin/env bash
# Tests for evaluate-skip-conditions.sh. Run with:
#   bash plugins/agentic-core/shared/lib/evaluate-skip-conditions.test.sh
#
# Manifests are written inline here rather than added to
# shared/fixtures/pack-manifest/, except where a case is also a
# validator-conformance case: the committed fixtures exist to prove what
# validate-pack-manifest.sh accepts and rejects, and most cases below are
# about path presence on disk, which no committed fixture can express.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVALUATOR="$SCRIPT_DIR/evaluate-skip-conditions.sh"
FIXDIR="$(cd "$SCRIPT_DIR/../fixtures/pack-manifest" && pwd)"

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

assert_equals() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1))
    echo "  ok: $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc"
    echo "    expected: '$expected'"
    echo "    got:      '$actual'"
  fi
}

TMPDIR_TEST="$(mktemp -d "${TMPDIR:-/tmp}/evaluate-skip-conditions-test.XXXXXX")"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

PROJECT="$TMPDIR_TEST/project"
mkdir -p "$PROJECT/.ai/run-context"

write_manifest() {
  local name="$1"
  cat > "$TMPDIR_TEST/$name.yaml"
  echo "$TMPDIR_TEST/$name.yaml"
}

echo "=== evaluate-skip-conditions.sh tests ==="

echo "[none] a manifest with no skip_when_missing key"
M=$(write_manifest no-key <<'YAML'
kind: platform
stages:
  intake: intake
  deliver: deliver
always_autonomous: [deliver]
artifacts: []
YAML
)
OUT=$(bash "$EVALUATOR" "$M" "$PROJECT" 2>&1); ST=$?
assert_exit "exits 0" 0 $ST "$OUT"
assert_equals "reports nothing skipped" "" "$OUT"

echo "[skip] a declared precondition path that does not exist"
M=$(write_manifest one-missing <<'YAML'
kind: platform
stages:
  intake: intake
  publish-gate: gate
  deliver: deliver
always_autonomous: [deliver]
artifacts: []
skip_when_missing:
  publish-gate: ".ai/run-context/gate-input.yaml"
YAML
)
OUT=$(bash "$EVALUATOR" "$M" "$PROJECT" 2>&1); ST=$?
assert_exit "exits 0" 0 $ST "$OUT"
assert_equals "reports the stage skipped" "skipped: publish-gate" "$OUT"

echo "[no skip] the same manifest once the precondition path exists"
touch "$PROJECT/.ai/run-context/gate-input.yaml"
OUT=$(bash "$EVALUATOR" "$M" "$PROJECT" 2>&1); ST=$?
assert_exit "exits 0" 0 $ST "$OUT"
assert_equals "the stage is no longer skipped" "" "$OUT"
rm -f "$PROJECT/.ai/run-context/gate-input.yaml"

echo "[re-evaluation] the same manifest flips back once the path is gone again"
OUT=$(bash "$EVALUATOR" "$M" "$PROJECT" 2>&1)
assert_equals "skipped again" "skipped: publish-gate" "$OUT"

echo "[directory] a precondition satisfied by a directory, not a file"
M=$(write_manifest dir-condition <<'YAML'
kind: platform
stages:
  intake: intake
  design-sync: sync
always_autonomous: []
artifacts: []
skip_when_missing:
  design-sync: ".ai/design"
YAML
)
OUT=$(bash "$EVALUATOR" "$M" "$PROJECT" 2>&1)
assert_equals "absent directory skips the stage" "skipped: design-sync" "$OUT"
mkdir -p "$PROJECT/.ai/design"
OUT=$(bash "$EVALUATOR" "$M" "$PROJECT" 2>&1)
assert_equals "present directory does not" "" "$OUT"

echo "[order] several conditions report in manifest order"
M=$(write_manifest several <<'YAML'
kind: platform
stages:
  intake: intake
  alpha: a
  beta: b
  gamma: c
  deliver: deliver
always_autonomous: [deliver]
artifacts: []
skip_when_missing:
  gamma: ".ai/absent-three"
  alpha: ".ai/absent-one"
  beta: ".ai/absent-two"
YAML
)
OUT=$(bash "$EVALUATOR" "$M" "$PROJECT" 2>&1)
assert_equals "manifest order, not alphabetical" \
  "skipped: gamma
skipped: alpha
skipped: beta" "$OUT"

echo "[partial] only the unsatisfied conditions are reported"
touch "$PROJECT/.ai/absent-two"
OUT=$(bash "$EVALUATOR" "$M" "$PROJECT" 2>&1)
assert_equals "the satisfied one drops out" \
  "skipped: gamma
skipped: alpha" "$OUT"
rm -f "$PROJECT/.ai/absent-two"

echo "[unquoted] a path written without surrounding quotes"
M=$(write_manifest unquoted <<'YAML'
kind: platform
stages:
  intake: intake
  extra: extra
always_autonomous: []
artifacts: []
skip_when_missing:
  extra: .ai/no-such-path
YAML
)
OUT=$(bash "$EVALUATOR" "$M" "$PROJECT" 2>&1)
assert_equals "quotes are optional" "skipped: extra" "$OUT"

echo "[block end] a later top-level key closes the block"
M=$(write_manifest block-end <<'YAML'
kind: platform
stages:
  intake: intake
  extra: extra
skip_when_missing:
  extra: ".ai/no-such-path"
always_autonomous: [intake]
artifacts:
  - id: fact-record
    produced_by: intake
    path: ".ai/run-context/fact-record.yaml"
YAML
)
OUT=$(bash "$EVALUATOR" "$M" "$PROJECT" 2>&1)
assert_equals "only the block's own entries are read" "skipped: extra" "$OUT"

echo "[no cross-talk] a stages: map is never read as a condition"
M=$(write_manifest stages-only <<'YAML'
kind: platform
stages:
  intake: intake
  implement: implement
  deliver: deliver
always_autonomous: [deliver]
artifacts: []
YAML
)
OUT=$(bash "$EVALUATOR" "$M" "$PROJECT" 2>&1)
assert_equals "stage-to-skill entries are not conditions" "" "$OUT"

echo "[fixture] the committed platform-valid fixture declares no conditions"
OUT=$(bash "$EVALUATOR" "$FIXDIR/platform-valid/pack.yaml" "$PROJECT" 2>&1); ST=$?
assert_exit "exits 0" 0 $ST "$OUT"
assert_equals "nothing skipped" "" "$OUT"

echo "[fixture] the committed platform-valid-skip-conditions fixture"
OUT=$(bash "$EVALUATOR" "$FIXDIR/platform-valid-skip-conditions/pack.yaml" "$PROJECT" 2>&1); ST=$?
assert_exit "exits 0" 0 $ST "$OUT"
assert_equals "its one declared stage is skipped against an empty project" \
  "skipped: implement" "$OUT"

echo "[default root] project root defaults to the current directory"
mkdir -p "$TMPDIR_TEST/cwd-test/.ai"
M=$(write_manifest cwd-relative <<'YAML'
kind: platform
stages:
  intake: intake
  extra: extra
always_autonomous: []
artifacts: []
skip_when_missing:
  extra: ".ai/present"
YAML
)
touch "$TMPDIR_TEST/cwd-test/.ai/present"
OUT=$(cd "$TMPDIR_TEST/cwd-test" && bash "$EVALUATOR" "$M" 2>&1)
assert_equals "resolves against cwd when no root is given" "" "$OUT"
rm -f "$TMPDIR_TEST/cwd-test/.ai/present"
OUT=$(cd "$TMPDIR_TEST/cwd-test" && bash "$EVALUATOR" "$M" 2>&1)
assert_equals "and skips when it is absent there" "skipped: extra" "$OUT"

echo "[usage] missing argument"
OUT=$(bash "$EVALUATOR" 2>&1); ST=$?
assert_exit "no args -> usage error (exit 2)" 2 $ST "$OUT"

echo "[usage] manifest not found"
OUT=$(bash "$EVALUATOR" "$TMPDIR_TEST/no-such.yaml" "$PROJECT" 2>&1); ST=$?
assert_exit "missing manifest -> usage error (exit 2)" 2 $ST "$OUT"

echo "[usage] project root is not a directory"
OUT=$(bash "$EVALUATOR" "$M" "$TMPDIR_TEST/no-such-dir" 2>&1); ST=$?
assert_exit "bad project root -> usage error (exit 2)" 2 $ST "$OUT"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
