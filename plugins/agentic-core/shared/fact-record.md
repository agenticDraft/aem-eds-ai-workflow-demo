---
description: The fact record contract. Every reader or writer of a fact record references this file rather than restating the shape inline.
---

# Fact record

Emitted by `intake`. Consumed by the `readiness` gate and by every stage's `when:` condition — it is
the only thing a condition may name. Facts only — no conclusions. The stage that produces this record
must not decide anything from it: a field it cannot determine is omitted, or written as the literal
`null` — never guessed.

## Format

```yaml
item_id: <string>
item_type: <string>
labels: [<string>, …]
components: [<string>, …]
files_named: [<path>, …]

design_source: true | false
design_mentioned: true | false

has_description: true | false
has_acceptance_criteria: true | false
has_reproduction_url: true | false
has_reproduction_steps: true | false
```

## Field rules

- `item_id` — non-empty string. Required.
- `item_type` — verbatim from the tracker, not normalised. Required.
- `labels` — the work item's labels/tags, verbatim. May be an empty list.
- `components` — the work item's declared components, verbatim. May be an empty list.
- `files_named` — paths the work item's text names, if any. May be an empty list.
- `design_source` — whether a design reference is **present**, in any accepted form. `true` or
  `false`.
- `design_mentioned` — whether the text **asks for** a visual change. `true` or `false`.
- `has_description`, `has_acceptance_criteria`, `has_reproduction_url`, `has_reproduction_steps` —
  whether the item carries each. `true` or `false`. Consumed by the `readiness` gate's declared
  criteria.

**`design_source` and `design_mentioned` are two different questions**, and the pair is what makes
four cases separable. Present-and-wanted and neither-nor are the easy ones. **Wanted but absent** —
an item asking for a visual change with nothing attached — is the case the pair exists for, and it is
terminal at the `readiness` gate. **Absent but present** runs the design stages anyway: a resolvable
reference is stronger evidence than a word list.

**Every boolean is a literal match, never a judgement.** The pack declares the word lists and heading
names — a tracker pack's `text_conventions` (see `pack-manifest.md`) — and `intake` applies them to
the sanitized text, recording which token matched so a run can be audited afterwards. A model reading
the item and forming an opinion would be a conclusion in a facts-only record, and would make two runs
on the same item diverge.

**The word list is deliberately wide.** Its two errors cost very different amounts. A false positive
raises one question a human dismisses. A false negative ships a visual change with no design
verification at all, and nothing reports it. Over-matching is the cheap direction.

**Fields may be omitted.** Unlike the project config's top-level keys, a fact record field with
no determinable value does not appear at all, or appears as `null`. A missing key and an explicit
`null` are equivalent to every reader of this file. Field order is not significant.

**A condition may name only the fields above.** A stage's `when:` key that names anything else can
never match, and would silently disable its stage forever — which is why it is rejected mechanically
rather than left to be noticed (see **Verification**).

**Each field has a kind, and a condition must compare it against a value of that kind.** Three
list fields — `labels`, `components`, `files_named` — are tested with `present` or `empty`, because
"does the item name a component" is a question about the list's emptiness, not about a value in it.
Every `design_*` and `has_*` field is boolean, tested with `true` or `false`. The rest are strings,
tested for equality. A field this record omits, or carries as `null`, matches nothing except a
list's `empty`.

## Example

```yaml
item_id: "1234"
item_type: task
labels: [backend]
components: [api]
files_named: []

design_source: false
design_mentioned: false

has_description: true
has_acceptance_criteria: true
has_reproduction_url: false
has_reproduction_steps: false
```

## Anti-patterns

- A guessed value in place of an omitted or `null` field.
- A conclusion (a chosen route, a classification, a readiness verdict) recorded alongside the facts.
- A derived field computed from two others — a single "design required" boolean standing in for
  `design_source` and `design_mentioned` is a conclusion, and this record holds facts only.
- A boolean set from a model's reading of the item rather than from a declared word list or heading
  name matching the sanitized text.

## Reference, not restatement

A skill, script or stage adapter that reads or writes a fact record references this file with one
line rather than restating the shape inline, the same convention `project-config.md` and
`result-envelope.md` use for their own contracts.

## Fixtures

`fixtures/fact-record/valid.yaml` — a well-formed record.
`fixtures/fact-record/no-design-no-components.yaml` — `design_source`, `design_mentioned` both
`false` and `components` empty, the record that skips every conditional stage.
`fixtures/fact-record/no-design-with-component.yaml` — the same, but naming a component, so the
component-gated stage runs and the design-gated ones do not.

## Verification

The field names above are the closed set a stage condition and a readiness criterion may name.
`lib/validate-pack-manifest.sh` enforces that, and its own test suite asserts the list it checks
against equals the field names in this file's **Format** block — so the two cannot drift apart
silently.

```bash
bash plugins/agentic-core/shared/lib/validate-pack-manifest.test.sh
```
