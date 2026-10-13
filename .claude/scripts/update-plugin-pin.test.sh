#!/usr/bin/env bash
# Run: bash .claude/scripts/update-plugin-pin.test.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/update-plugin-pin.sh"
: "${TMPDIR:?TMPDIR must be set}"
W="$(mktemp -d "$TMPDIR/pin-test.XXXXXX")" || exit 2
trap 'rm -rf "$W"' EXIT

fail=0
check() { # check <name> <expected> <actual>
  if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: expected '$2', got '$3'"; fail=$((fail + 1)); fi
}

# A local repository with tags stands in for the plugins repository.
git init -q "$W/remote" && git -C "$W/remote" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
for t in v0.2.0 v0.2.1 v0.10.0 v0.3.0-rc1 not-a-version; do git -C "$W/remote" tag "$t"; done

cat > "$W/settings.json" <<'EOF'
{
  "extraKnownMarketplaces": {
    "agenticdraft": {
      "source": { "source": "github", "repo": "agenticDraft/plugins", "ref": "v0.2.0" }
    }
  },
  "enabledPlugins": { "agentic-core@agenticdraft": true, "other@elsewhere": true }
}
EOF
cat > "$W/route-trigger.yaml" <<'EOF'
      - name: Check out the plugins
        uses: actions/checkout@v7
        with:
          repository: agenticDraft/plugins
          ref: v0.2.0
          path: _plugins
EOF
cat > "$W/user-settings.json" <<'EOF'
{ "extraKnownMarketplaces": { "agenticdraft": { "source": { "source": "github", "repo": "agenticDraft/plugins", "ref": "v0.2.0" } } } }
EOF
export PIN_USER_SETTINGS="$W/user-settings.json"
export PIN_SETTINGS="$W/settings.json" PIN_WORKFLOW="$W/route-trigger.yaml" PIN_REPO_URL="$W/remote" PIN_SKIP_CLI=1

bash "$SCRIPT" --check >/dev/null; check "check reports a newer tag (exit 10)" 10 $?
check "check leaves settings untouched" v0.2.0 "$(jq -r '.extraKnownMarketplaces.agenticdraft.source.ref' "$W/settings.json")"

bash "$SCRIPT" >/dev/null 2>"$W/err"; check "apply stops while the user-level pin differs (exit 3)" 3 $?
check "nothing edited before the stop" v0.2.0 "$(jq -r '.extraKnownMarketplaces.agenticdraft.source.ref' "$W/settings.json")"
check "stop prints the jq command" 1 "$(grep -c 'source.ref=' "$W/err")"
jq '.extraKnownMarketplaces.agenticdraft.source.ref="v0.10.0"' "$W/user-settings.json" > "$W/u.new" && mv "$W/u.new" "$W/user-settings.json"

bash "$SCRIPT" >/dev/null; check "apply succeeds" 0 $?
check "settings ref is the highest vX.Y.Z (v0.10.0, not rc or non-version)" v0.10.0 "$(jq -r '.extraKnownMarketplaces.agenticdraft.source.ref' "$W/settings.json")"
check "workflow ref moved" "          ref: v0.10.0" "$(grep 'ref:' "$W/route-trigger.yaml")"
check "workflow keeps the other lines" 4 "$(grep -c -E 'name:|uses:|repository:|path:' "$W/route-trigger.yaml")"

bash "$SCRIPT" --check >/dev/null; check "second check is current (exit 0)" 0 $?

# settings.json reformatted over several lines (an editor or the CLI can do this)
cat > "$W/settings-multi.json" <<'EOF'
{
  "extraKnownMarketplaces": {
    "agenticdraft": {
      "source": {
        "source": "github",
        "repo": "agenticDraft/plugins",
        "ref": "v0.2.0"
      }
    }
  },
  "enabledPlugins": { "agentic-core@agenticdraft": true }
}
EOF
sed 's/v0.10.0/v0.2.0/' "$W/route-trigger.yaml" > "$W/wf-multi.yaml"
PIN_SETTINGS="$W/settings-multi.json" PIN_WORKFLOW="$W/wf-multi.yaml" bash "$SCRIPT" >/dev/null; check "multi-line settings: apply succeeds" 0 $?
check "multi-line settings: ref moved" v0.10.0 "$(jq -r '.extraKnownMarketplaces.agenticdraft.source.ref' "$W/settings-multi.json")"
check "multi-line settings: keeps the layout" 12 "$(wc -l < "$W/settings-multi.json" | tr -d ' ')"
check "multi-line settings: workflow moved too" "          ref: v0.10.0" "$(grep 'ref:' "$W/wf-multi.yaml")"

# neither file is written unless both edits took: the ref sits before the repo, so the settings edit cannot find it
cat > "$W/settings-odd.json" <<'EOF'
{
  "extraKnownMarketplaces": {
    "agenticdraft": {
      "source": {
        "ref": "v0.2.0",
        "source": "github",
        "repo": "agenticDraft/plugins"
      }
    }
  }
}
EOF
sed 's/v0.10.0/v0.2.0/' "$W/route-trigger.yaml" > "$W/wf-odd.yaml"
PIN_SETTINGS="$W/settings-odd.json" PIN_WORKFLOW="$W/wf-odd.yaml" bash "$SCRIPT" >/dev/null 2>&1; check "unreadable layout: exit 2" 2 $?
check "unreadable layout: workflow left untouched" "          ref: v0.2.0" "$(grep 'ref:' "$W/wf-odd.yaml")"
check "unreadable layout: settings left untouched" v0.2.0 "$(jq -r '.extraKnownMarketplaces.agenticdraft.source.ref' "$W/settings-odd.json")"

echo "fail=$fail"
[ "$fail" -eq 0 ]
