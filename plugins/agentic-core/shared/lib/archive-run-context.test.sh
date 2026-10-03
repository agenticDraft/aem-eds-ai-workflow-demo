#!/usr/bin/env bash
# Tests for archive-run-context.sh. Run with:
#   bash plugins/agentic-core/shared/lib/archive-run-context.test.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARCHIVER="$SCRIPT_DIR/archive-run-context.sh"

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); echo "  ok: $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; shift; for l in "$@"; do echo "    $l"; done; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/archive-run-context-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

echo "=== archive-run-context.sh tests ==="

echo "[archive] a run context from an earlier run is moved whole, hidden entries and subdirectories included"
CTX="$WORK/one/run-context"
LOGS="$WORK/one/logs"
mkdir -p "$CTX/nested"
printf 'x' > "$CTX/envelope-verify.txt"
: > "$CTX/evidence-attached-by-verify"
: > "$CTX/orchestrating.flag"
printf 'h' > "$CTX/.hidden"
printf 'n' > "$CTX/nested/report.md"
printf 'p' > "$WORK/one/progress.md"
OUT="$(bash "$ARCHIVER" "$CTX" "$LOGS" "$WORK/one/progress.md" "$WORK/one/never-existed.txt" 2>&1)"; ST=$?
TARGET="$(ls -d "$LOGS"/run-context-* 2>/dev/null | head -1)"
if [[ "$ST" == 0 && "$OUT" == "archived: 6 entries -> $TARGET" ]]; then
  ok "exit 0 and reports the count and the archive directory"
else
  bad "exit 0 and reports the count and the archive directory" "exit $ST" "output: $OUT" "target: $TARGET"
fi
if [[ -d "$CTX" && -z "$(ls -A "$CTX")" ]]; then
  ok "the run-context directory is present and empty afterwards"
else
  bad "the run-context directory is present and empty afterwards" "$(ls -A "$CTX" 2>&1)"
fi
if [[ -f "$TARGET/envelope-verify.txt" && -f "$TARGET/evidence-attached-by-verify" && -f "$TARGET/orchestrating.flag" \
      && -f "$TARGET/.hidden" && -f "$TARGET/nested/report.md" && -f "$TARGET/progress.md" ]]; then
  ok "every entry, the hidden file, the subdirectory and the extra file are in the archive"
else
  bad "every entry, the hidden file, the subdirectory and the extra file are in the archive" "$(find "$TARGET" 2>&1)"
fi
if [[ ! -e "$WORK/one/progress.md" ]]; then
  ok "the extra file is gone from where it was"
else
  bad "the extra file is gone from where it was"
fi
if [[ "$(cat "$TARGET/envelope-verify.txt")" == "x" && "$(cat "$TARGET/nested/report.md")" == "n" ]]; then
  ok "contents survive the move"
else
  bad "contents survive the move"
fi
if [[ "$TARGET" =~ /run-context-[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{6}$ ]]; then
  ok "the archive directory is named run-context-<date>-<time>"
else
  bad "the archive directory is named run-context-<date>-<time>" "$TARGET"
fi

echo "[nothing] a clean run context is an ordinary outcome"
OUT="$(bash "$ARCHIVER" "$CTX" "$LOGS" "$WORK/one/progress.md" 2>&1)"; ST=$?
if [[ "$ST" == 0 && "$OUT" == "archived: nothing to move" ]]; then
  ok "second call -> exit 0, nothing to move"
else
  bad "second call -> exit 0, nothing to move" "exit $ST" "output: $OUT"
fi
COUNT="$(ls -d "$LOGS"/run-context-* 2>/dev/null | wc -l | tr -d ' ')"
if [[ "$COUNT" == 1 ]]; then
  ok "no empty archive directory is created when there is nothing to move"
else
  bad "no empty archive directory is created when there is nothing to move" "count: $COUNT"
fi

echo "[absent] a run context that does not exist yet is created empty"
CTX2="$WORK/two/run-context"
OUT="$(bash "$ARCHIVER" "$CTX2" "$WORK/two/logs" 2>&1)"; ST=$?
if [[ "$ST" == 0 && -d "$CTX2" && -z "$(ls -A "$CTX2")" && "$OUT" == "archived: nothing to move" ]]; then
  ok "missing directory -> created, empty, exit 0"
else
  bad "missing directory -> created, empty, exit 0" "exit $ST" "output: $OUT"
fi
if [[ ! -e "$WORK/two/logs" ]]; then
  ok "the archive root is not created when nothing is archived"
else
  bad "the archive root is not created when nothing is archived"
fi

echo "[twice] two archives in the same second get distinct names"
CTX3="$WORK/three/run-context"
LOGS3="$WORK/three/logs"
mkdir -p "$CTX3"; : > "$CTX3/a"
OUT1="$(bash "$ARCHIVER" "$CTX3" "$LOGS3" 2>&1)"
: > "$CTX3/b"
OUT2="$(bash "$ARCHIVER" "$CTX3" "$LOGS3" 2>&1)"
T1="${OUT1##*-> }"; T2="${OUT2##*-> }"
if [[ "$T1" != "$T2" && -f "$T1/a" && -f "$T2/b" ]]; then
  ok "distinct archive directories, each holding its own run"
else
  bad "distinct archive directories, each holding its own run" "$OUT1" "$OUT2"
fi

echo "[usage] errors"
OUT="$(bash "$ARCHIVER" 2>&1)"; ST=$?
[[ "$ST" == 2 ]] && ok "no arguments -> exit 2" || bad "no arguments -> exit 2" "exit $ST"
OUT="$(bash "$ARCHIVER" "$CTX3" 2>&1)"; ST=$?
[[ "$ST" == 2 ]] && ok "one argument -> exit 2" || bad "one argument -> exit 2" "exit $ST"
: > "$WORK/a-file"
OUT="$(bash "$ARCHIVER" "$WORK/a-file" "$LOGS3" 2>&1)"; ST=$?
[[ "$ST" == 2 ]] && ok "run context that is a file -> exit 2" || bad "run context that is a file -> exit 2" "exit $ST" "$OUT"
mkdir -p "$CTX3"; : > "$CTX3/c"
OUT="$(bash "$ARCHIVER" "$CTX3" "$WORK/a-file" 2>&1)"; ST=$?
if [[ "$ST" == 2 && -f "$CTX3/c" ]]; then
  ok "archive root that is a file -> exit 2, nothing moved"
else
  bad "archive root that is a file -> exit 2, nothing moved" "exit $ST" "$OUT"
fi

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
