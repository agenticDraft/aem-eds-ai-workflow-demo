#!/usr/bin/env bash
# poll-preview.test.sh — the readiness poll, with `curl` stubbed first on PATH.
# The stub records its arguments and answers 200, so each case is one poll.
#
# Usage:
#   bash poll-preview.test.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POLL="$SCRIPT_DIR/poll-preview.sh"

PASS=0
FAIL=0

ok()  { echo "  ok: $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "    $2"; FAIL=$((FAIL + 1)); }

assert_eq()    { if [ "$2" == "$3" ]; then ok "$1"; else bad "$1" "expected: $2 — got: $3"; fi; }
assert_has()   { if [[ "$3" == *"$2"* ]]; then ok "$1"; else bad "$1" "expected to contain: $2 — got: $3"; fi; }
assert_lacks() { if [[ "$3" != *"$2"* ]]; then ok "$1"; else bad "$1" "expected not to contain: $2 — got: $3"; fi; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/poll-preview.XXXXXX") || { echo "cannot create a temp dir" >&2; exit 2; }
[ -n "$WORK" ] && [ -d "$WORK" ] || { echo "cannot create a temp dir" >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/bin"
printf '#!/usr/bin/env bash\nprintf "[%%s]" "$@" >> "%s/curl-calls"; echo >> "%s/curl-calls"\nprintf 200\n' "$WORK" "$WORK" > "$WORK/bin/curl"
chmod +x "$WORK/bin/curl"
export PATH="$WORK/bin:$PATH"

echo "[answer] a server that answers on the first poll"
rm -f "$WORK/curl-calls"
OUT=$(env -u HTTP_PROXY -u http_proxy bash "$POLL" "http://localhost:3000/preview" 2>&1); CODE=$?
assert_eq "exit 0" "0" "$CODE"
assert_has "answered on poll 1" "answered: status=200 poll=1" "$OUT"
assert_lacks "no proxy in the environment: no --noproxy" "--noproxy" "$(cat "$WORK/curl-calls")"

echo "[proxy] with a proxy in the environment, the poll goes through it, local address included"
rm -f "$WORK/curl-calls"
OUT=$(HTTP_PROXY="http://localhost:3128" bash "$POLL" "http://localhost:3000/preview" 2>&1); CODE=$?
assert_eq "exit 0" "0" "$CODE"
assert_has "curl told to proxy every host" "[--noproxy][]" "$(cat "$WORK/curl-calls")"

echo "[proxy] the lower-case variable counts too"
rm -f "$WORK/curl-calls"
OUT=$(env -u HTTP_PROXY http_proxy="http://localhost:3128" bash "$POLL" "http://localhost:3000/preview" 2>&1); CODE=$?
assert_has "curl told to proxy every host" "[--noproxy][]" "$(cat "$WORK/curl-calls")"

echo "[usage] a missing argument is exit 2"
OUT=$(bash "$POLL" 2>&1); CODE=$?
assert_eq "exit 2" "2" "$CODE"

echo "=== $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
