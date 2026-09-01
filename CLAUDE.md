@AGENTS.md

<!-- This file carries project POLICY plus an INDEX of documents to read on a trigger.
     Reference material — how EDS works, how a tool behaves — belongs in the referenced
     file, never here: every line loads into every session. Keep it under 200 lines. -->

## Reference documents

Read these when the trigger applies. Do not guess at their contents.

- **`docs/implementation-plan/automated-eds-delivery-plan.md`** — design and gap analysis for the
  delivery automation we are building. Read before changing anything under `.claude/`, or before
  starting any new automation/tooling feature anywhere in the repo.
- **`docs/implementation-plan/automated-eds-delivery-tasks.md`** — the plan broken into
  independently verifiable tasks, each with the check a human runs to accept it. Read before
  implementing any part of the delivery automation.
- **`docs/implementation-plan/adobe-skills-audit.md`** — per-skill verdicts on Adobe's
  `aem-edge-delivery-services` and `skojic/aem-eds-figma-to-code`. Read before adopting,
  replacing or duplicating any EDS skill.
- **`docs/implementation-plan/automated-eds-delivery-dx-core-deviations.md`** — every case where
  the standing rule **D9** (follow `dx-core`'s patterns; deviate only where EDS forces it, and
  name the constraint) was applied: standing deviations, ones walked back after review, and
  material rejected as not transferable. Compiled *from* the plan — the plan stays the source of
  truth. Read it before the *deviation* rule below fires, so you don't re-litigate a settled case.
- **`docs/implementation-plan/automated-eds-delivery-plan-enhancements.md`** — the research trail
  behind D11–D14, which are already merged into the plan. Rejected alternatives and reasoning
  only; **nothing in it is a pending change and nothing in it is built.** Read only to find out
  why an option was rejected.
- **`docs/implementation-plan/automated-eds-delivery-tasks-summary.md`** — the same tasks as
  `automated-eds-delivery-tasks.md`, flattened into one dependency-ordered list, Task 1 → 41, each
  with a *Done when* check. Read it to answer "what's next"; read the tasks file for the full
  acceptance criteria.

All six are gitignored (`.gitignore` ignores `docs/`) — local only, never pushed.

## EDS platform knowledge comes from Adobe's skills, not from us

Decided 2026-09-01 (see the plan's D27/D28). We hand-wrote `helix-cli-docs.md` and
`eds-block-development.md`; Adobe now ships maintained equivalents, so **both were deleted** and
this project does not re-author platform reference material.

Install once — steps in the README's *Claude Code setup* section. Verified installed 2026-09-01:
`aem-edge-delivery-services@adobe-skills` v1.0.0, user scope. Invoke as
`aem-edge-delivery-services:<name>`. These eight are the ones this project adopts:

- **`aem-cli`** — the `aem` CLI: flags, `--html-folder`, `.env` / `AEM_*`, TLS, troubleshooting.
- **`building-blocks`** — block scaffolding, `decorate()` patterns, scoped CSS.
- **`content-modeling`** — the author/developer contract; the four canonical block models.
- **`block-collection-and-party`** — live search for an existing block, instead of a frozen list.
- **`docs-search`** — ranked search over aem.live with deprecation warnings.
- **`testing-blocks`**, **`analyze-and-plan`**, **`find-test-content`** — verify, spec, fixtures.
- **`content-driven-development`** — the 8-step process wrapper that **hand-written** EDS work in
  this repo starts from (D32, 2026-09-01). Used as Adobe ships it; two of its commands are
  overridden by `AGENTS.md`, see the *development process* section there. **It remains ruled out
  as the delivery automation's orchestrator (D28)** — those are separate scopes, do not merge
  them.

The plugin ships **25 skills as one unit** — the other 17 are installed and invocable but are not
project policy. Check `adobe-skills-audit.md` before reaching for one.

**Section- and page-metadata rules** are in `da-content`'s `references/html-content.md`. It is
installed (same plugin) but the audit marks it **WATCH, not adopted**: its markup half is
platform-level and applies to us, its DA/`admin.da.live` API half does not — this site is sourced
from Google Drive. Read it for markup rather than guessing; ignore its DA API instructions.

## Working on the delivery automation

Any new feature that is automation or tooling — not a block, component, or other EDS site
content — gets a `Gx`/`Dx` entry in `automated-eds-delivery-plan.md` before it's built, and
ships as part of the Automated EDS Delivery plugin (`.claude/`, promoted per the plan's
*Packaging* section) — never as a standalone script or tool living outside it. Applies
regardless of where in the repo the work would otherwise land.

**Always write changes back into the plan.** Any decision taken, assumption settled, gap found or
approach changed goes into `automated-eds-delivery-plan.md` in the same session it happens —
including corrections to what the plan already says. The plan is the record; a decision that lives
only in a conversation is lost. When a change also affects the task list, update
`automated-eds-delivery-tasks.md` with it.

**Always ask before deviating from `dx-core`.** Where our design differs from how `dx-core` solved
the same problem, stop and ask for confirmation — do not resolve it alone, and do not treat an
existing line in the plan as settled if it conflicts with `dx-core`. Present what `dx-core` does,
what we do, and what the difference costs. Once confirmed, record the deviation and its reason in
the plan, then reflect it in `automated-eds-delivery-dx-core-deviations.md`, which is compiled
from it.

When working on the plan above, or on the `.claude/` automation built from it, check how
`dx-core` solved the problem **before** asking or choosing an approach:

```
/Users/zoranmarkovic/github/filipovic/dx-aem-flow/plugins/dx-core
```

`shared/` holds its cross-skill contracts, `skills/` has 49 worked examples, `skills/dx-figma-*`
covers design-to-code. Sibling plugins `dx-aem`, `dx-automation`, `dx-hub` rarely apply.

**This is not a fork.** Adopt patterns, not code — dx-core targets AEMaaCS (JCR, Maven) on Azure
DevOps. Anything naming `mcp__ado__*`, JCR or Maven does not transfer. Record in the plan what
was borrowed and what changed, with attribution (MIT, © 2025-2026 Dragan Filipovic). If the path
does not exist, say so rather than guessing.
