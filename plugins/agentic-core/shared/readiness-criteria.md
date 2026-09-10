---
description: The readiness gate's criteria — what "can this item be worked at all" reduces to, and why (unlike plan-gate and publish-gate) this gate has no judgment half. Every reader or writer of a readiness outcome references this file rather than restating the criteria inline.
---

# Readiness criteria

`readiness` (core contract §4) answers whether a work item can be worked at all, against criteria
the platform pack declares per `item_type` in its `readiness_criteria:` block
(`pack-manifest.md`). It reads the fact record (`fact-record.md`); it never re-reads the item's
own text, so its verdict stays deterministic across runs.

**This gate has no reviewing model.** `gate-contract.md` fixes the shared contract for the other
two gates — deterministic checks first, a reviewing model second on whatever survives — and scopes
itself to exactly two stage ids, `plan-gate` and `publish-gate`. `readiness` is not one of them.
Every criterion below is a comparison between the fact record and the pack manifest: whether a
declared field is `true`, or a declared list is non-empty. None of that is judgment — a criterion
a script can answer is not handed to a model (`gate-contract.md`'s own reasoning), and every one of
`readiness`'s criteria is exactly that kind. So this gate has no confidence-filtered findings list
and no `warn` verdict: it is `pass` or `fail`, never "ready, with reservations."

## The criteria

1. **Does the item's `item_type` have declared readiness criteria at all?** No — `fail`, naming the
   missing declaration. It never falls through to another type's rules and never guesses (§4).
2. **Does every field that item_type's `require` list names hold?** A boolean field must be `true`;
   a list field must be non-empty (`present`); a string field must be non-null and non-empty. A
   field the fact record could not determine — absent, or the literal `null` — never counts as
   holding, the same "never guessed" rule `fact-record.md` states for the record itself.
3. **Is the item wanted-but-design-absent?** Fixed by `fact-record.md` §5 directly, independent of
   what any item_type declares: `design_mentioned: true` with `design_source: false` — the text
   asks for a visual change and nothing is attached — is terminal at this gate. Only fires when
   both fields are actually determined.

Criteria 1 and 2 are the pack's own declared checks; criterion 3 is fixed by the core contract and
runs regardless of what the pack declares. All three are answerable yes/no with no judgment
involved, which is why `check-readiness-criteria.sh` is the whole gate rather than a first pass.

## Known limitation — the `question` path (G36) is not implemented here

Core contract §6.1 and gap G36 describe a fourth case: when an image attachment is the work item's
**only** design source, the reference is ambiguous — a defect screenshot and an intended-state
mockup are structurally identical — and `readiness` is specified to return `verdict: question`
naming the attachments and asking which is the reference.

That case cannot be built from the fact record as it stands today. `design_source` is a single
boolean, `true` whether the reference is a resolvable design-tool URL, an image attachment, or
both (`fact-record.md`'s own field rule: "whether a design reference is present, in any accepted
form"). Nothing in the record distinguishes an image-only item from a URL-backed one, and nothing
carries the attachment names a `question` would need to name. Re-reading the raw fetched item to
recover that distinction is exactly what §4 forbids this gate from doing ("it never re-reads the
item's text, so its criteria stay deterministic").

Filed as its own gap, referencing G36, in the gap register — see that entry for what a fix would
require. This check and this gate answer criteria 1–3 only; a `design_source: true` item is never
asked about, regardless of whether its source is an image or a URL.

## Field rules

- `require` — a non-empty list of fact-record field names, keyed by `item_type`
  (`pack-manifest.md`, `readiness_criteria`). `validate-pack-manifest.sh` already rejects a field
  name outside `fact-record.md`'s closed set and an `item_type` with an empty `require` list, so
  this check can assume both hold for a manifest that passed pack validation.
- The design-wanted-but-absent rule is not declared anywhere in the manifest — it is fixed by the
  core contract and applies to every item_type equally.

## Anti-patterns

- Treating a missing declaration as `pass` because the item "seems fine" — an item_type with no
  declared criteria has nothing to check it against, and guessing readiness is exactly what this
  gate exists to prevent.
- A field counted as holding because it is merely absent rather than explicitly `false` or
  `empty` — an undetermined field is not a met criterion.
- Re-reading the fetched work item to resolve the `question` case above. Extend the fact record
  first; see the referenced gap.

## Reference, not restatement

A skill or script that reads or writes a readiness outcome references this file with one line
rather than restating the criteria inline, the same convention `plan-criteria.md` and
`publish-criteria.md` use for their own.

## Fixtures

`fixtures/pack-manifest/platform-valid-full-route/pack.yaml` and `fixtures/fact-record/valid.yaml`
— an item_type whose declared criteria all hold. `fixtures/readiness-criteria/` — one fixture per
rejection case: `undeclared-item-type.yaml` (an item_type the pack declares no criteria for),
`missing-required-field.yaml` (a declared field that is `false`), `design-wanted-absent.yaml`
(`design_mentioned: true`, `design_source: false`).

## Verification

`lib/check-readiness-criteria.sh <path-to-pack.yaml> <path-to-fact-record.yaml>` is the entire
deterministic check — no model involved. It exits `0` and prints `valid: readiness (<item_type>,
<n> fields checked)` when every criterion holds, `1` with `invalid: <reason>` on stderr naming the
undeclared item_type or the exact field that failed, `2` for a usage error.

```bash
bash plugins/agentic-core/shared/lib/check-readiness-criteria.test.sh
```
