#!/usr/bin/env bash
# check-external-content-safety.sh — Demonstrates the one mechanical piece of
# shared/external-content-safety.md's contract: fetched content survives into
# a later artifact as an unmodified byte string, never interpreted as code.
#
# This script proves only that; it cannot prove a stage adapter's judgment,
# which is a model-behavior property no deterministic script can stand in
# for. See shared/external-content-safety.md's "Verification" section.
#
# What it does: copies the fixture at <fixture-path> verbatim into
# <out-dir>/sanitized.md using file copy only — no eval, no source, no shell
# expansion of the fixture's own content — then exits 0. It never reads the
# fixture into a variable that a later command could expand or execute.
#
# Usage:
#   check-external-content-safety.sh <fixture-path> <out-dir>
#
# Exit codes:
#   0 — "ok: processed as data", then "sanitized: <out-dir>/sanitized.md"
#   2 — usage error: missing argument, fixture not found

set -uo pipefail

usage() {
  echo "usage: check-external-content-safety.sh <fixture-path> <out-dir>" >&2
  exit 2
}

FIXTURE="${1:-}"
OUT_DIR="${2:-}"
[[ -z "$FIXTURE" || -z "$OUT_DIR" ]] && usage

if [[ ! -f "$FIXTURE" ]]; then
  echo "usage: fixture not found: $FIXTURE" >&2
  exit 2
fi

mkdir -p "$OUT_DIR" || { echo "usage: cannot create out-dir: $OUT_DIR" >&2; exit 2; }
cp "$FIXTURE" "$OUT_DIR/sanitized.md" || { echo "usage: copy failed" >&2; exit 2; }

echo "ok: processed as data"
echo "sanitized: $OUT_DIR/sanitized.md"
exit 0
