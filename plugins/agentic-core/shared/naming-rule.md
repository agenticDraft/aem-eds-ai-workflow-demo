---
description: The naming rule made executable — core contract §13 validator 8. What counts as a product, platform or tool name, the denylist that encodes it, and the two documented exceptions. Every reader checking core source for neutrality runs the validator this file points at, rather than re-deciding the rule by eye.
---

# Naming rule

**No file under the core names a product, a platform or a tool.** The core names a *role*
(`tracker`, `scm`, `design`, `browser`) and the operations that role must support; which concrete
product implements a role is a pack's business, never the core's. This is the property the whole
agnostic-core design rests on, and the one that erodes silently — a stray brand name in a comment
or a test fixture costs nothing to write and nothing to notice, which is exactly why it needs a
mechanical check rather than a habit.

## What counts as a name

A product, platform or tool name: a tracker, an SCM host, a design tool, a browser engine or
browser-automation tool, a delivery platform or CMS, a package manager or build tool — anything a
pack would name to say *which one it is*. A role name is not one of these (`tracker` is core
vocabulary; the tracker product behind it is not).

## The denylist

`lib/naming-denylist.txt` is the list — one term per line, case-sensitive, matched as a whole word
or phrase. It targets concrete names, grouped by the role or concern each belongs to; it is not a
claim of completeness, and grows the same way a real denylist grows: a new concrete name gets added
when it comes up. This document does not restate the list — read the file — the same
"reference, not restatement" convention `pack-manifest.md` and `project-config.md` already use for
their own contracts, and for the same reason this document itself follows: naming a real product
here, even as an example, would be the rule's own text failing its own rule.

## Documented exceptions

Core contract §13 declares exactly two, both about naming the reference implementation this core's
envelope, artifact registry and config-once principle were adapted from:

1. **The attribution line** — `` `dx-aem-flow` — MIT, © 2025-2026 Dragan Filipovic ``, verbatim.
2. **A citation of the deviations record** — the literal filename `06-dx-core-deviations.md`.

Both are narrow: a line matching one of these two literal strings verbatim is exempt, but any other
mention of either name outside that exact wording is still a violation. Nothing else is exempt — a
validator with a growing exception list stops being a check.

## Scope

The validator's target is `plugins/agentic-core` — the shipped core, the only tree a real CI run
can see. It excludes three paths from the scan, not as rule exceptions but because their content is
necessarily literal denylist data rather than core vocabulary — the same status a fetched work
item's text has under `external-content-safety.md`, data rather than a directive:

- `lib/naming-denylist.txt` itself — the list has to spell out every term it forbids.
- `fixtures/naming-rule/` — this validator's own fixtures, which have to contain both violating and
  exempted text to prove the validator can tell them apart.
- `lib/validate-naming-rule.test.sh` itself — its assertions have to compare the validator's output
  against the literal term it is expected to name, for the same reason the denylist file does.

The fixtures exclusion does not fire when the fixtures tree (or a fixture inside it) is itself the
thing being scanned — pointing the validator directly at a fixture, as its test suite does, sees
the fixture's content in full.

## Anti-patterns

- A concrete product, platform or tool name anywhere under the core, in code, comments, docs or
  test data, outside the two documented exceptions above.
- A bare mention of either borrowed-material name that is not the exact attribution sentence or the
  exact citation filename.
- A test using a real, ecosystem-specific command string where a neutral placeholder proves the
  same thing without naming a package manager.

## Fixtures

`fixtures/naming-rule/clean/` names roles only, no violation. `fixtures/naming-rule/violation/`
names a tracker product directly, and must fail. `fixtures/naming-rule/exception-attribution/` and
`fixtures/naming-rule/exception-citation/` each carry one of the two documented exceptions verbatim,
and must pass despite containing a denylisted term. `fixtures/naming-rule/bare-dx-terms/` names both
borrowed-material terms outside either exception's exact wording, and must fail — proving the
exceptions are narrow, not a blanket pass for the term.

## Verification

`lib/validate-naming-rule.sh <path-to-core-root>` is the deterministic checker — no model involved.
It exits `0` and prints `valid: naming rule (<n> files scanned, <m> terms checked)` when nothing
under the given root trips the denylist outside a documented exception; `1` with one
`invalid: '<term>' — <path>:<line>:<content>` line per hit, then a count, on stderr; `2` for a usage
error. Run its test suite with:

```bash
bash plugins/agentic-core/shared/lib/validate-naming-rule.test.sh
```

Check the real core with:

```bash
bash plugins/agentic-core/shared/lib/validate-naming-rule.sh plugins/agentic-core
```
