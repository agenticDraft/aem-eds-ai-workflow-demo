#!/usr/bin/env bash
# Tests for design-names.py. Run with:
#   bash plugins/eds/shared/scripts/design-names.test.sh
#
# No framework — exits 0 when every case passes, 1 otherwise. Each case calls
# the module's functions directly through python3 and compares what it prints.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE="$SCRIPT_DIR/design-names.py"

PASS=0
FAIL=0

ok()   { PASS=$((PASS + 1)); echo "  ok: $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; shift; for l in "$@"; do echo "    $l"; done; }

# py <code> — runs <code> with the module loaded as `dn`; prints its stdout
py() {
  python3 - "$MODULE" "$1" <<'EOF'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("design_names", sys.argv[1])
dn = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dn)
exec(sys.argv[2])
EOF
}

is() {
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want: $3" "got:  $2"; fi
}

K1="$(printf 'a%.0s' {1..64})"
K2="b${K1:1}"
K3="c${K1:1}"

echo "content_key is the SHA-256 hex of the bytes"
is "matches shasum" "$(py 'print(dn.content_key(b"abc"))')" "$(printf abc | shasum -a 256 | cut -d' ' -f1)"

echo "component_key ignores key order and whitespace, and tells values apart"
is "same values, other key order" \
  "$(py 'print(dn.component_key({"color": "#485C11", "size": {"w": 24, "h": 24}}) == dn.component_key({"size": {"h": 24, "w": 24}, "color": "#485C11"}))')" "True"
is "different values" \
  "$(py 'print(dn.component_key({"color": "#485C11"}) == dn.component_key({"color": "#6F6F6F"}))')" "False"
is "a 64-hex SHA-256" "$(py 'k = dn.component_key({"a": 1}); print(len(k), all(c in "0123456789abcdef" for c in k))')" "64 True"

echo "a name used by one design keeps its base"
is "base kept" "$(py "print(dn.split_names([('check', '$K1'), ('check', '$K1')])[('check', '$K1')])")" "check"

echo "different designs under one name all get hash4, the first included"
is "every design split" \
  "$(py "n = dn.split_names([('check', '$K1'), ('check', '$K2'), ('check', '$K3')]); print(sorted(n.values()))")" \
  "['check-aaaa', 'check-baaa', 'check-caaa']"

echo "the names do not depend on input order"
is "reversed input, same names" \
  "$(py "a = dn.split_names([('x', '$K1'), ('x', '$K2')]); b = dn.split_names([('x', '$K2'), ('x', '$K1')]); print(a == b)")" "True"

echo "two keys sharing a hash4 both widen to 8"
is "widened" \
  "$(py "n = dn.split_names([('x', 'f81b9b09' + '0' * 56), ('x', 'f81b884d' + '0' * 56), ('x', '$K1')]); print(sorted(n.values()))")" \
  "['x-aaaa', 'x-f81b884d', 'x-f81b9b09']"

echo "a held base name with another key counts as one more design"
is "single design splits" \
  "$(py "print(dn.split_names([('x', '$K1')], held=lambda name: '$K2' if name == 'x' else None))")" \
  "{('x', '$K1'): 'x-aaaa'}"
is "held by the same key: base kept" \
  "$(py "print(dn.split_names([('x', '$K1')], held=lambda name: '$K1' if name == 'x' else None))")" \
  "{('x', '$K1'): 'x'}"

echo "a held hash4 name with another key widens that design to 8"
is "widened alone" \
  "$(py "n = dn.split_names([('x', '$K1'), ('x', '$K2')], held=lambda name: '$K3' if name == 'x-aaaa' else None); print(sorted(n.values()))")" \
  "['x-aaaaaaaa', 'x-baaa']"

echo "component keys split the same way as file keys"
is "two components, one name" \
  "$(py "a = dn.component_key({'fill': '#485C11'}); b = dn.component_key({'fill': '#6F6F6F'}); n = dn.split_names([('check', a), ('check', b)]); print(n[('check', a)] == 'check-' + a[:4], n[('check', b)] == 'check-' + b[:4])")" \
  "True True"

echo
echo "passed: $PASS, failed: $FAIL"
[ "$FAIL" -eq 0 ]
