---
description: The naming rule made executable — core contract §13 validator 8. What counts as a product, platform or tool name, the denylist that encodes it, and why no third-party plugin's name — including one this project's own design was adapted from — is ever spelled out anywhere under the core, the denylist itself included. Every reader checking core source for neutrality runs the validator this file points at, rather than re-deciding the rule by eye.
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

## No exceptions

This core's envelope, artifact registry and config-once principle were adapted from a reference
implementation — a third-party Claude Code plugin. That plugin's name is never spelled out
anywhere under `plugins/agentic-core`, the denylist file included: not as a denylist entry, not in
a fixture, not in a test assertion, not in an attribution line or a citation. `00-instructions.md`'s
own rule already says why in general terms: attribution "lives once, centrally" in the gitignored
planning record, "not duplicated into every shared file" — which means it is never duplicated into
a *shipped* file at all, in any form, including one written to *prove a denylist entry works*. A
denylist entry that spelled out the name to forbid it would still be spelling it out; the rule
holds by never writing the name here, not by writing it and then forbidding it.

## Scope

The validator's target is `plugins/agentic-core` — the shipped core, the only tree a real CI run
can see. It excludes three paths from the scan, not as rule exceptions but because their content is
necessarily literal denylist data rather than core vocabulary — the same status a fetched work
item's text has under `external-content-safety.md`, data rather than a directive:

- `lib/naming-denylist.txt` itself — the list has to spell out every term it forbids.
- `fixtures/naming-rule/` — this validator's own fixtures, which have to contain violating text to
  prove the validator catches it.
- `lib/validate-naming-rule.test.sh` itself — its assertions have to compare the validator's output
  against the literal term it is expected to name, for the same reason the denylist file does.

The fixtures exclusion does not fire when the fixtures tree (or a fixture inside it) is itself the
thing being scanned — pointing the validator directly at a fixture, as its test suite does, sees
the fixture's content in full.

## Anti-patterns

- A concrete product, platform or tool name anywhere under the core, in code, comments, docs or
  test data — no exception, including a third-party plugin this project's own design was adapted
  from.
- An attribution or citation naming a third-party plugin, added to a shipped file instead of the
  gitignored planning record it already lives in.
- Adding a real third-party plugin's name to the denylist itself, or to a fixture proving detection
  of it — spelling the name out to forbid it still spells it out. The general categories already on
  the denylist (tracker, SCM, design tool, browser, delivery platform, package manager) are what a
  pack would plausibly name; a specific tool this project's own patterns were adapted from is kept
  out of the shipped core by never writing it here, not by an entry that names it.
- A test using a real, ecosystem-specific command string where a neutral placeholder proves the
  same thing without naming a package manager.

## Fixtures

`fixtures/naming-rule/clean/` names roles only, no violation. `fixtures/naming-rule/violation/`
names a tracker product directly, and must fail.

## Verification

`lib/validate-naming-rule.sh <path-to-core-root>` is the deterministic checker — no model involved.
It exits `0` and prints `valid: naming rule (<n> files scanned, <m> terms checked)` when nothing
under the given root trips the denylist; `1` with one
`invalid: '<term>' — <path>:<line>:<content>` line per hit, then a count, on stderr; `2` for a usage
error. Run its test suite with:

```bash
bash plugins/agentic-core/shared/lib/validate-naming-rule.test.sh
```

Check the real core with:

```bash
bash plugins/agentic-core/shared/lib/validate-naming-rule.sh plugins/agentic-core
```
