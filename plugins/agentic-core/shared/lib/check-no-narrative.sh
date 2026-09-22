#!/usr/bin/env bash
# check-no-narrative.sh — Deterministic conformance check for the rule that a
# shipped file carries only what a consumer needs to operate.
#
# Files under a plugin ship with it, including once extracted to a separate
# repository. A reader of the extracted copy has none of this repository's
# planning documents, so a shipped file that cites one is citing something the
# reader cannot open, and a shipped file carrying a rationale section is
# carrying reasoning that belongs with the task that produced it.
#
# Two rules, each one mechanical:
#   1. no path that this repository does not publish. Resolved through
#      `git check-ignore` rather than a maintained list of directories, so the
#      check follows the ignore rules instead of drifting from them.
#   2. no provenance or rationale section heading.
#
# A third rule exists on paper — borrowed-material attribution belongs in one
# central place rather than repeated per file — and is deliberately NOT
# enforced here, because enforcing it as written would do damage. The two
# central locations it names are both unpublished, so the only copies of the
# borrowed-material notice that reach a shipped plugin are the per-file lines
# the rule asks to remove. Deleting them would leave the shipped copy carrying
# adapted material with no notice at all. That is a question about where the
# notice should live, not about the files, and a checker is the wrong place to
# answer it.
#
# Deliberately NOT checked: whether a command, shell or platform name is a
# legitimate invocation or narration. That distinction needs a reader — a
# shebang, a "run with <command> <path>" line and a comment naming the command
# whose arguments it is describing are all legitimate, and a pattern cannot
# separate them from a comment that names a tool to justify a choice. The
# denylisted subset of that rule is already enforced for the core by
# validate-naming-rule.sh. Faking the rest as a script check would produce a
# green result that means nothing, which is worse than an unchecked rule
# someone still remembers to read for.
#
# Usage:
#   check-no-narrative.sh <root>
#
# Exit codes:
#   0 — "valid: no narrative (<n> files scanned)"
#   1 — "invalid: <reason>" on stderr, one line per finding
#   2 — usage error: no root argument, or a root that is not a directory

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$SCRIPT_DIR/check-no-narrative.sh"
SELF_TEST="$SCRIPT_DIR/check-no-narrative.test.sh"

ROOT="${1:-}"
if [[ -z "$ROOT" ]]; then
  echo "usage: check-no-narrative.sh <root>" >&2
  exit 2
fi
if [[ ! -d "$ROOT" ]]; then
  echo "invalid: not a directory: $ROOT" >&2
  exit 2
fi

REPO_ROOT="$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null)"
if [[ -z "$REPO_ROOT" ]]; then
  echo "invalid: '$ROOT' is not inside a repository, so publication cannot be determined" >&2
  exit 2
fi

FINDINGS=0
SCANNED=0

report() {
  echo "invalid: $1" >&2
  FINDINGS=$((FINDINGS + 1))
}

# This file, its test, and its fixtures necessarily carry the patterns they
# detect, the same way the naming validator excludes its own denylist and
# suite. The fixtures are excluded only when they are not themselves the root
# under scan — pointing this check at them is how the test drives it.
OWN_FIXTURES="$SCRIPT_DIR/../fixtures/no-narrative"
[[ -d "$OWN_FIXTURES" ]] && OWN_FIXTURES="$(cd "$OWN_FIXTURES" && pwd)" || OWN_FIXTURES=""
ROOT_ABS="$(cd "$ROOT" && pwd)"
if [[ -n "$OWN_FIXTURES" && ( "$ROOT_ABS" == "$OWN_FIXTURES" || "$ROOT_ABS" == "$OWN_FIXTURES"/* ) ]]; then
  OWN_FIXTURES=""
fi

is_self() {
  local resolved
  resolved="$(cd "$(dirname "$1")" 2>/dev/null && pwd)/$(basename "$1")"
  [[ "$resolved" == "$SELF" || "$resolved" == "$SELF_TEST" ]] && return 0
  [[ -n "$OWN_FIXTURES" && "$resolved" == "$OWN_FIXTURES"/* ]] && return 0
  return 1
}

while IFS= read -r file; do
  is_self "$file" && continue
  SCANNED=$((SCANNED + 1))

  # --- rule 2: a provenance or rationale section ----------------------------
  while IFS=: read -r lineno text; do
    [[ -z "$lineno" ]] && continue
    report "${file#"$REPO_ROOT"/}:${lineno} carries a provenance section — '${text## }'; that reasoning belongs with the task that produced it, not in a shipped file"
  # Anchored to end-of-heading on purpose. A heading that merely begins with
  # one of these words is usually doing something else — "## Source files" is a
  # list of inputs, not an account of where the design came from — and a check
  # that flags it teaches people the check is wrong rather than the file.
  done < <(grep -nE '^#{1,6}[[:space:]]+(Source|Sources|Sources consulted|Rationale|Provenance|References consulted)[[:space:]]*$' "$file" 2>/dev/null)

  # --- rule 1: a path this repository does not publish ----------------------
  # A candidate must resolve to something that is actually here before it
  # counts as a citation. Ignore rules match on shape, so a URL fragment or a
  # runtime path that has never existed matches them just as a real file does —
  # a fixture's `…example.test/drafts/4001` is not a citation of anything. The
  # cost of requiring existence is that a citation of a file since deleted goes
  # unreported; the alternative is a check that cries wolf on every fixture
  # holding a plausible-looking URL, which is a check people learn to ignore.
  while IFS= read -r candidate; do
    [[ -z "$candidate" ]] && continue
    [[ -e "$REPO_ROOT/$candidate" ]] || continue
    if git -C "$REPO_ROOT" check-ignore -q -- "$candidate" 2>/dev/null; then
      lineno="$(grep -nF -m1 -- "$candidate" "$file" | cut -d: -f1)"
      report "${file#"$REPO_ROOT"/}:${lineno:-?} names '$candidate', which this repository does not publish — a reader of the shipped copy cannot open it"
    fi
  done < <(grep -ohE '[A-Za-z0-9_][A-Za-z0-9_.-]*/[A-Za-z0-9_./-]+' "$file" 2>/dev/null \
             | sed 's/[.,;:)"`]*$//' | sort -u)
done < <(find "$ROOT" -type f \
           \( -name '*.md' -o -name '*.sh' -o -name '*.py' -o -name '*.yaml' \
              -o -name '*.yml' -o -name '*.js' -o -name '*.cjs' -o -name '*.json' \) \
           -not -path '*/node_modules/*' -print)

if [[ "$FINDINGS" -gt 0 ]]; then
  echo "invalid: $FINDINGS finding(s) across $SCANNED file(s)" >&2
  exit 1
fi

echo "valid: no narrative ($SCANNED files scanned)"
