#!/usr/bin/env bash
# fake-render.sh — stand-in render command for check-reachability.test.sh.
# Prints a minimal `## Result` envelope shaped like a real browser role's
# render operation, controlled entirely by environment variables so the
# test file never has to touch the network or a real browser:
#
#   FAKE_RENDER_RESULT — "pass" or "fail" (default "fail").
#   FAKE_RENDER_LOG    — when set, one line is appended to this path per
#                         invocation, so a test can assert the attempt count.
#
# Takes the target URL as its one argument (unused beyond the pass-case
# summary line) — the same calling convention check-reachability.sh uses
# for any render command.

set -uo pipefail

: "${FAKE_RENDER_RESULT:=fail}"
TARGET="${1:-}"

if [[ -n "${FAKE_RENDER_LOG:-}" ]]; then
  echo "call" >> "$FAKE_RENDER_LOG"
fi

echo "## Result"
if [[ "$FAKE_RENDER_RESULT" == "pass" ]]; then
  echo "verdict: pass"
  echo "summary: Rendered $TARGET: HTTP 200, 0 console error(s)."
  echo "artifacts: []"
  echo "next_action: none"
  echo "metrics: status=200 console_errors=0 load_time_ms=42"
else
  echo "verdict: fail"
  echo "summary: could not load $TARGET: connection refused"
  echo "artifacts: []"
  echo "next_action: none"
fi
