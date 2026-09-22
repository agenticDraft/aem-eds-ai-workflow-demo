#!/usr/bin/env bash
# Tests for check-preflight.sh. Run with:
#   bash plugins/agentic-core/shared/lib/check-preflight.test.sh
#
# No framework — exits 0 on success, 1 on first failure. assert_exit/
# assert_contains below compare expected vs. actual exit code and output
# against fixture inputs.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/check-preflight.sh"
FIXDIR="$SCRIPT_DIR/../fixtures/pre-flight"
PACKFIXDIR="$SCRIPT_DIR/../fixtures/pack-manifest"

PLATFORM="$PACKFIXDIR/platform-valid/pack.yaml"
TRACKER="$PACKFIXDIR/provider-valid/pack.yaml"
SCM="$FIXDIR/providers/scm-valid/pack.yaml"
SCM_MISSING="$FIXDIR/providers/scm-missing-operation/pack.yaml"
TRACKER_MISSING="$FIXDIR/providers/tracker-missing-operation/pack.yaml"
BROWSER="$FIXDIR/providers/browser-valid/pack.yaml"
DESIGN="$FIXDIR/providers/design-valid/pack.yaml"

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

echo "=== check-preflight.sh tests ==="

echo "[accept] every required pack installed, design not required"
OUT=$(bash "$CHECK" "$FIXDIR/config-valid.yaml" \
  "platform=$PLATFORM" "tracker=$TRACKER" "scm=$SCM" "browser=$BROWSER" 2>&1); ST=$?
assert_exit "ready (exit 0)" 0 $ST "$OUT"
assert_contains "reports ready" "ready" "$OUT"
assert_contains "design not required" "design: none" "$OUT"

echo "[accept] every required pack installed, design required and present"
OUT=$(bash "$CHECK" "$FIXDIR/config-design-required.yaml" \
  "platform=$PLATFORM" "tracker=$TRACKER" "scm=$SCM" "browser=$BROWSER" "design=$DESIGN" 2>&1); ST=$?
assert_exit "ready with design (exit 0)" 0 $ST "$OUT"
assert_contains "design checked ok" "design: ok" "$OUT"

echo "[reject] a required pack is missing (removed from the arguments)"
OUT=$(bash "$CHECK" "$FIXDIR/config-valid.yaml" \
  "platform=$PLATFORM" "scm=$SCM" "browser=$BROWSER" 2>&1); ST=$?
assert_exit "missing tracker pack rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the missing role" "role 'tracker'" "$OUT"

echo "[reject] a required pack's path does not exist"
OUT=$(bash "$CHECK" "$FIXDIR/config-valid.yaml" \
  "platform=$PLATFORM" "tracker=$FIXDIR/does-not-exist/pack.yaml" "scm=$SCM" "browser=$BROWSER" 2>&1); ST=$?
assert_exit "pack not installed rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names not installed" "not installed" "$OUT"

echo "[reject] a configured pack declares a required operation unsupported"
OUT=$(bash "$CHECK" "$FIXDIR/config-valid.yaml" \
  "platform=$PLATFORM" "tracker=$TRACKER" "scm=$SCM_MISSING" "browser=$BROWSER" 2>&1); ST=$?
assert_exit "unsupported operation rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the unavailable operation" "publish_change" "$OUT"

# An operation no stage can reach must not block a run: the rule is that an
# unsupported operation makes *a stage needing it* unrunnable, and nothing in a
# route needs these. The pairing matters more than either case alone — the
# first says the exemption works, the second says it did not swallow the check
# it was carved out of.
echo "[accept] a tracker declaring only the authoring operations unsupported"
OUT=$(bash "$CHECK" "$FIXDIR/config-valid.yaml" \
  "platform=$PLATFORM" "tracker=$TRACKER" "scm=$SCM" "browser=$BROWSER" 2>&1); ST=$?
assert_exit "not blocked (exit 0)" 0 $ST "$OUT"
[[ "$OUT" != *"create_item"* && "$OUT" != *"update_item"* ]]
assert_exit "and neither operation is mentioned" 0 $? "$OUT"

echo "[reject] a tracker declaring an operation a stage does need unsupported"
OUT=$(bash "$CHECK" "$FIXDIR/config-valid.yaml" \
  "platform=$PLATFORM" "tracker=$TRACKER_MISSING" "scm=$SCM" "browser=$BROWSER" 2>&1); ST=$?
assert_exit "still blocked (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the reachable operation" "fetch_item" "$OUT"
[[ "$OUT" != *"create_item"* ]]
assert_exit "and does not name the exempt ones alongside it" 0 $? "$OUT"

echo "[reject] a pack is installed under the wrong role"
OUT=$(bash "$CHECK" "$FIXDIR/config-valid.yaml" \
  "platform=$PLATFORM" "tracker=$TRACKER" "scm=$TRACKER" "browser=$BROWSER" 2>&1); ST=$?
assert_exit "role mismatch rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the declared role" "declares role 'tracker'" "$OUT"

# --- check 3: the onboarding gate (D80) -------------------------------------
# platform-valid-onboarding declares onboarding_state_path=onboarding/manifest.md
# and audit_findings_path=onboarding/audit.md, both resolved relative to the
# current working directory — the same convention every project-relative path
# in this system uses. Each case cd's into its own temp "project root" first.
GATED_PLATFORM="$PACKFIXDIR/platform-valid-onboarding/pack.yaml"

run_gated() {
  local dir="$1"; shift
  (cd "$dir" && bash "$CHECK" "$@" 2>&1)
}

ONBOARD_TMP="$(mktemp -d "${TMPDIR:-/tmp}/check-preflight-onboarding.XXXXXX")"
trap 'rm -rf "$ONBOARD_TMP"' EXIT

echo "[accept] onboarding gate: neither declared path present in the project — warns, still ready"
mkdir -p "$ONBOARD_TMP/no-paths/onboarding"
OUT=$(run_gated "$ONBOARD_TMP/no-paths" "$FIXDIR/config-valid.yaml" \
  "platform=$GATED_PLATFORM" "tracker=$TRACKER" "scm=$SCM" "browser=$BROWSER"); ST=$?
assert_exit "still ready (exit 0)" 0 $ST "$OUT"
assert_contains "reports ready" "ready" "$OUT"
assert_contains "onboarding warns" "onboarding: warn" "$OUT"
assert_contains "audit ok, nothing to check yet" "audit: ok — no audit yet" "$OUT"

echo "[accept] onboarding gate: onboarding-state file present"
mkdir -p "$ONBOARD_TMP/onboarded/onboarding"
: > "$ONBOARD_TMP/onboarded/onboarding/manifest.md"
OUT=$(run_gated "$ONBOARD_TMP/onboarded" "$FIXDIR/config-valid.yaml" \
  "platform=$GATED_PLATFORM" "tracker=$TRACKER" "scm=$SCM" "browser=$BROWSER"); ST=$?
assert_exit "ready (exit 0)" 0 $ST "$OUT"
assert_contains "onboarding ok" "onboarding: ok" "$OUT"

echo "[reject] onboarding gate: an open poisoning finding blocks before any branch/file exists"
mkdir -p "$ONBOARD_TMP/poisoned/onboarding"
cat > "$ONBOARD_TMP/poisoned/onboarding/audit.md" <<'EOF'
- id: "F1"
  class: mechanical
  severity: poisoning
  file: "AGENTS.project.md"
  finding: "the breakpoint claim in this house-style document contradicts what the code actually enforces"
  diff: |
    -    the breakpoint is 1024px
    +    the breakpoint is 900px
EOF
OUT=$(run_gated "$ONBOARD_TMP/poisoned" "$FIXDIR/config-valid.yaml" \
  "platform=$GATED_PLATFORM" "tracker=$TRACKER" "scm=$SCM" "browser=$BROWSER"); ST=$?
assert_exit "blocked (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the contradiction" "breakpoint claim" "$OUT"
assert_contains "reason names the remedy" "onboarding-completion flow" "$OUT"

echo "[accept] a platform pack declaring neither onboarding path runs ungated, output unchanged"
OUT=$(bash "$CHECK" "$FIXDIR/config-valid.yaml" \
  "platform=$PLATFORM" "tracker=$TRACKER" "scm=$SCM" "browser=$BROWSER" 2>&1); ST=$?
assert_exit "ready (exit 0)" 0 $ST "$OUT"
if [[ "$OUT" == *"onboarding:"* || "$OUT" == *"audit:"* ]]; then
  FAIL=$((FAIL + 1)); echo "  FAIL: ungated pack prints no onboarding/audit line"
  echo "    got: $OUT"
else
  PASS=$((PASS + 1)); echo "  ok: ungated pack prints no onboarding/audit line"
fi

# --- check 4: the serve notice (D94) ----------------------------------------
# platform-valid declares no `serve` stage, so every case above proves the
# no-op path already — nothing there prints a serve line. These two cover the
# pack that does declare one. The check itself is tested in full by
# check-serve-notice.test.sh; what is proven here is that pre-flight runs it
# and that its line reaches pre-flight's own ready output.
SERVE_PLATFORM="$PACKFIXDIR/platform-valid-full-route/pack.yaml"

echo "[accept] a platform pack declaring no serve stage prints no serve line"
if [[ "$OUT" == *"serve:"* ]]; then
  FAIL=$((FAIL + 1)); echo "  FAIL: ungated pack prints no serve line"
  echo "    got: $OUT"
else
  PASS=$((PASS + 1)); echo "  ok: ungated pack prints no serve line"
fi

echo "[accept] a platform pack declaring a serve stage gets the notice, still ready"
OUT=$(bash "$CHECK" "$FIXDIR/config-valid.yaml" \
  "platform=$SERVE_PLATFORM" "tracker=$TRACKER" "scm=$SCM" "browser=$BROWSER" 2>&1); ST=$?
assert_exit "ready (exit 0)" 0 $ST "$OUT"
assert_contains "serve notice reaches pre-flight's output" "serve: ok" "$OUT"
assert_contains "notice names the preview URL" "http://localhost:0000/preview" "$OUT"
assert_contains "notice names the serve command" "run-serve" "$OUT"

echo "[accept] a serve stage with no configured serve command warns, never blocks"
OUT=$(bash "$CHECK" "$FIXDIR/serve/config-serve-empty.yaml" \
  "platform=$SERVE_PLATFORM" "tracker=$TRACKER" "scm=$SCM" "browser=$BROWSER" 2>&1); ST=$?
assert_exit "still ready (exit 0)" 0 $ST "$OUT"
assert_contains "serve warns" "serve: warn" "$OUT"

echo "[usage] no arguments"
OUT=$(bash "$CHECK" 2>&1); ST=$?
assert_exit "no args -> usage error (exit 2)" 2 $ST "$OUT"

echo "[usage] config file not found"
OUT=$(bash "$CHECK" "$FIXDIR/does-not-exist.yaml" "platform=$PLATFORM" 2>&1); ST=$?
assert_exit "missing config -> usage error (exit 2)" 2 $ST "$OUT"

echo "[usage] malformed role=path argument"
OUT=$(bash "$CHECK" "$FIXDIR/config-valid.yaml" "platform" 2>&1); ST=$?
assert_exit "malformed argument -> usage error (exit 2)" 2 $ST "$OUT"

echo "[usage] unrecognized role name"
OUT=$(bash "$CHECK" "$FIXDIR/config-valid.yaml" "bogus=$PLATFORM" 2>&1); ST=$?
assert_exit "unrecognized role -> usage error (exit 2)" 2 $ST "$OUT"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
