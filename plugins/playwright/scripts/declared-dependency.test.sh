#!/usr/bin/env bash
# Tests that this pack declares its own automation package, in the form the
# host installs, and that nothing in the pack installs it. Run with:
#   bash plugins/playwright/scripts/declared-dependency.test.sh
#
# No framework, no network, no browser — exits 0 when every case passes, 1
# otherwise.
#
# The host installs a plugin's dependencies only from a `package.json` and a
# lockfile at the plugin root: an exact registry version, `https` download
# links, the same dependency list in both files. The installed copy lives in
# the pack's own directory, so the package is resolved from there; nothing
# above the pack root is reached. The browser binary is not part of that
# install, so its remedy runs the pinned version of the tool.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACK_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); echo "  ok: $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; shift; for l in "$@"; do echo "    $l"; done; }

# check <description> <node program> — the program prints nothing on success
# and one line per problem otherwise.
check() {
  local desc="$1" prog="$2" out
  out="$(cd "$PACK_DIR" && node -e "$prog" 2>&1)"
  if [[ -z "$out" ]]; then ok "$desc"; else bad "$desc" "$out"; fi
}

echo "the declared dependency"

check "package.json pins playwright to an exact version, as a runtime dependency" '
  const fs = require("fs");
  if (!fs.existsSync("package.json")) { console.log("no package.json at the pack root"); process.exit(); }
  const p = JSON.parse(fs.readFileSync("package.json", "utf8"));
  const v = (p.dependencies || {}).playwright;
  if (!/^[0-9]+\.[0-9]+\.[0-9]+$/.test(v || "")) console.log("dependencies.playwright is not an exact version: " + v);
  if (p.devDependencies) console.log("devDependencies are not installed for a plugin");
  if (p.overrides) console.log("overrides stop the host install");
  for (const s of Object.keys(p.scripts || {})) console.log("lifecycle or run script declared: " + s);
'

check "package-lock.json is version 2 or 3 and lists what package.json lists" '
  const fs = require("fs");
  if (!fs.existsSync("package-lock.json")) { console.log("no package-lock.json at the pack root"); process.exit(); }
  const l = JSON.parse(fs.readFileSync("package-lock.json", "utf8"));
  const p = JSON.parse(fs.readFileSync("package.json", "utf8"));
  if (![2, 3].includes(l.lockfileVersion)) console.log("lockfileVersion " + l.lockfileVersion);
  const root = (l.packages || {})[""] || {};
  const a = JSON.stringify(root.dependencies || {}), b = JSON.stringify(p.dependencies || {});
  if (a !== b) console.log("lockfile root lists " + a + ", package.json lists " + b);
  if (root.name !== p.name) console.log("lockfile root name " + root.name + " is not " + p.name);
'

check "every locked package is a registry download over https with an integrity hash" '
  const l = JSON.parse(require("fs").readFileSync("package-lock.json", "utf8"));
  const entries = Object.entries(l.packages || {}).filter(([k]) => k !== "");
  if (!entries.length) console.log("no locked packages");
  for (const [k, e] of entries) {
    if (!/^https:\/\//.test(e.resolved || "")) console.log(k + ": resolved " + e.resolved);
    if (!e.integrity) console.log(k + ": no integrity");
    if (e.link) console.log(k + ": a linked dependency is not installed");
  }
'

check "every declared dependency is locked at its pinned version" '
  const fs = require("fs");
  const l = JSON.parse(fs.readFileSync("package-lock.json", "utf8"));
  const p = JSON.parse(fs.readFileSync("package.json", "utf8"));
  for (const [name, pin] of Object.entries(p.dependencies || {})) {
    // a lockfile keys each package by the folder it installs into
    const e = (l.packages || {})[["node_modules", name].join("/")] || {};
    if (e.version !== pin) console.log(name + ": locked " + e.version + ", pinned " + pin);
    if (e.dev) console.log(name + ": locked as a dev dependency");
  }
'

check "the pack ships no node_modules" '
  const fs = require("fs");
  const ig = fs.existsSync(".gitignore") ? fs.readFileSync(".gitignore", "utf8").split("\n") : [];
  if (!ig.includes("node_modules/")) console.log(".gitignore at the pack root does not ignore node_modules/");
'

echo "the declared remedies"

check "the playwright remedy names the host install, not a project or global install" '
  const { remedyFor } = require("./scripts/requires.cjs");
  const r = remedyFor("playwright") || "";
  if (!r) console.log("no remedy declared");
  if (/devDependenc/.test(r)) console.log("still names a project devDependency: " + r);
  if (/ -g /.test(r)) console.log("still names a global install: " + r);
  if (!/package\.json/.test(r)) console.log("does not name the package.json the host installs from: " + r);
'

check "the chromium remedy runs the pinned version of the tool" '
  const { remedyFor } = require("./scripts/requires.cjs");
  const v = require("./package.json").dependencies.playwright;
  const r = remedyFor("chromium") || "";
  if (!r.includes("playwright@" + v + " install chromium")) console.log("remedy does not pin " + v + ": " + r);
'

echo "nothing in the pack installs"

hits="$(cd "$PACK_DIR" && find . -path ./node_modules -prune -o -type f \( -name '*.cjs' -o -name '*.js' -o -name '*.mjs' -o -name '*.sh' \) ! -name '*.test.sh' -print \
  | xargs grep -nE '(npm|pnpm|yarn|bun)[^A-Za-z]+(install|ci|add|i)([^A-Za-z]|$)|playwright[^A-Za-z]+install' 2>/dev/null)"
if [[ -z "$hits" ]]; then ok "no pack script runs an install command"; else bad "no pack script runs an install command" "$hits"; fi

echo "where the package is resolved from"

# A copy of the pack outside any tree that holds the package, with a stand-in
# package where the host puts the real one. The probe must find that one.
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/declared-dependency.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT
COPY="$TMP_ROOT/pack"
mkdir -p "$COPY"
cp -R "$PACK_DIR/scripts" "$PACK_DIR/pack.yaml" "$COPY/"

probe() { (cd "$TMP_ROOT" && NODE_PATH= node "$COPY/scripts/probe-tool.cjs" "$1" >/dev/null 2>&1); echo $?; }

mkdir -p "$COPY/node_modules/playwright"
cat > "$COPY/node_modules/playwright/index.js" <<'EOF'
module.exports = { chromium: { executablePath: () => __dirname + '/no-such-browser' } };
EOF
echo '{"name":"playwright","version":"0.0.0","main":"index.js"}' > "$COPY/node_modules/playwright/package.json"

[[ "$(probe module)" == 0 ]] && ok "module: found in the pack's own node_modules" \
  || bad "module: found in the pack's own node_modules" "exit $(probe module)"
[[ "$(probe browser)" == 1 ]] && ok "browser: a package without its binary is absent" \
  || bad "browser: a package without its binary is absent" "exit $(probe browser)"

touch "$COPY/node_modules/playwright/no-such-browser"
[[ "$(probe browser)" == 0 ]] && ok "browser: the binary the pack's package names is present" \
  || bad "browser: the binary the pack's package names is present" "exit $(probe browser)"

echo
echo "passed: $PASS, failed: $FAIL"
[[ "$FAIL" -eq 0 ]]
