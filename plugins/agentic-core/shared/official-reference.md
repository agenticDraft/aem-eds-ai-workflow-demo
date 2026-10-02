---
description: Where no rule exists, the platform's official reference is read before deciding — the reference a platform pack declares in its manifest as reference_docs, what counts as "no rule", how a read is cited, and what a stage does when the reference does not answer. Every stage that writes or changes code, and the item-authoring skill, points here instead of restating it.
---

# Official reference

**A question no rule answers is answered from the platform's official reference, never from
memory.** The platform pack declares that reference as `reference_docs` in its manifest
(`pack-manifest.md`). The core never learns what it is.

## When it applies

A stage is about to decide something — a property, a value, an element, a behaviour — and none of
these answers it:

- the work item's own criteria and content;
- the project's convention record and the conventions artifact this run wrote;
- a decision or rule the pack ships (its shared contracts, its scripts' output);
- a value the design reference carries.

Then, before deciding: read the page of `reference_docs` that covers the question, and decide from
what it says.

## How a read is recorded

The stage's own report carries one line per read:

```
reference: <url read> — <what it settled, in one sentence>
```

An item draft carries the same line under the criterion it shaped.

## When the reference does not answer

Say so in the report — `reference: <url read> — does not answer <question>` — and then either
raise a `question` (the stage cannot proceed without the answer) or proceed with the choice and
mark it unverified. Never fill the gap from memory and present it as read.

## When the pack declares none

The stage has no reference to read. It does not substitute a search; it records
`reference: none declared` beside the decision.

## Reaching it

The reference's host must be in the runner's network allowlist, or a headless run cannot read it.
A read that fails is reported like a reference that does not answer.
