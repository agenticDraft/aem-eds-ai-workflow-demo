---
description: The delivery evidence manifest schema — what a platform pack's evidence_manifest artifact must contain. Every writer and every reader validates against this file rather than restating the shape inline.
---

# Evidence manifest

Registered by a platform pack (core contract §11's optional `evidence_manifest` key), written by
that pack's own verification stage(s), read by its delivery stage. Machine-readable, and that is
the whole reason it exists as a separate file from a stage's own prose report: a later stage must
learn what to attach without parsing a sentence a model wrote. Names no platform, no browser
provider and no tracker — this contract only fixes what the file contains; a pack supplies the
path (its own `artifacts:` entry) and which of its stages write it.

## Location

Wherever the declaring pack's own `artifacts:` entry for this id names — alongside that pack's
other run-context artifacts. This contract does not fix the path; the pack does, the same way it
fixes every other artifact's path in its own manifest.

## Format

This is real JSON, read with a real parser — unlike this project's other line-ordered YAML-ish
shapes, key order carries no meaning here.

```json
{
  "version": "1.0",
  "item_id": "<string>",
  "target": "<string>",
  "target_reachable": true,
  "target_reachable_reason": "<string>",
  "coverage_gaps": ["<string>", "…"],
  "attachments": [
    { "path": "<string>", "width": <number>, "label": "<string>" }
  ]
}
```

Seven required top-level keys. No other key may appear.

## Field rules

- **`version`** — the non-empty string `"1.0"`. No other value is defined yet.
- **`item_id`**, **`target`**, **`target_reachable_reason`** — each a non-empty string.
- **`target_reachable`** — a real JSON boolean, never the string `"true"`/`"false"` and never a
  number. States whether the `target` value can be handed to a person as an openable location.
  Collapses the reachability rule's three outcomes to two: `reachable` sets it `true`;
  `unreachable` and `unconfirmed` both set it `false` — the distinction between "known impossible
  to open" and "could not be proven either way" lives in the words `target_reachable_reason`
  carries, never in the boolean alone. Full rule, including the deterministic script that decides
  it: `shared/pre-flight.md`'s sibling reachability contract is not yet written as its own file —
  until it is, this field's value is set by whichever stage writes it, stated honestly rather than
  guessed (see that stage's own skill for how it currently derives it).
- **`coverage_gaps`** — an array of non-empty strings, one entry per thing this run could not
  exercise. `[]` (written as the literal, never omitted) when nothing was missed. Each entry must
  be consistent with what the writing stage's own prose report says for the same run — a manifest
  that drops a gap its own report names is the exact defect this contract exists to prevent (G86,
  `03-core-design.md` D86).
- **`attachments`** — an array of objects, each carrying `path` (a non-empty string, the file the
  delivery stage attaches, in order), `width` (a positive number — the capture's own viewport
  width; this is why `attachments` is scoped to visual captures, not every file a stage wrote) and
  `label` (a non-empty string, what the attachment shows). `[]` when a run genuinely captured
  nothing. A path that no longer exists by the time the delivery stage reads it is reported and
  skipped, never silently dropped — that stage's own concern, not this contract's; this contract
  never checks a listed path resolves on disk (the same reason core contract §13 validator 15
  never checks `onboarding_state_path`/`audit_findings_path` resolve: a static shape has no fixed
  project to check against).

## Both verification stages write it, merging

A design-driven route runs a design-verification stage before the (always-run) verification stage.
**The later writer merges rather than overwrites.** The natural implementation — read nothing,
write the file — silently discards the earlier stage's evidence on exactly the routes that produce
the most of it, and the loss is invisible in the run's own output: nothing fails, the file is just
thinner than the route's actual evidence. Concretely: union `attachments` (each stage's own
entries, in the order each stage produced them); union `coverage_gaps`; the later stage's own
`target`, `target_reachable`, `target_reachable_reason` and `item_id` win, since the later stage is
the more recent measurement of the same target.

## Example

```json
{
  "version": "1.0",
  "item_id": "4001",
  "target": "https://main--example--example.example.test/drafts/4001",
  "target_reachable": true,
  "target_reachable_reason": "loaded through the browser role, HTTP 200",
  "coverage_gaps": ["keyboard activation of the carousel's own controls was not exercised"],
  "attachments": [
    { "path": "captures/375.png", "width": 375, "label": "mobile width" },
    { "path": "captures/1024.png", "width": 1024, "label": "desktop width" }
  ]
}
```

## Anti-patterns

- A top-level key missing, or one present beyond the seven named above.
- `target_reachable` written as a string or number instead of a real JSON boolean.
- `coverage_gaps` empty on a run whose own prose report names a gap the manifest should have
  carried too.
- An `attachments` entry missing `path`, `width` or `label`, or a non-positive `width`.
- The later of two writing stages overwriting instead of merging.

## Reference, not restatement

A skill or script that reads or writes an evidence manifest references this file with one line
rather than restating the shape inline, the same convention `design-manifest.md` and
`pack-manifest.md` use for their own contracts.

## Fixtures

One well-formed example lives at `fixtures/evidence-manifest/valid.json`, plus
`valid-empty-attachments.json` and `valid-nonexistent-attachment-path.json` for the two
deliberately-accepted edge cases. `fixtures/evidence-manifest/invalid/` holds one fixture per
rejection case the validator must catch.

## Verification

`lib/validate-evidence-manifest.sh <path>` is the deterministic checker — no model involved. It
exits `0` and prints `valid: evidence manifest (<n> attachments, <m> coverage gaps)` for a
conformant file, `1` with `invalid: <reason>` on stderr for a contract violation naming the
offending field, `2` for a usage error. Run its test suite with:

```bash
bash plugins/agentic-core/shared/lib/validate-evidence-manifest.test.sh
```

Core contract §13 validator 16 is a separate, narrower check: it verifies a platform pack's
declared `evidence_manifest` key names an id that pack's own `artifacts:` list registers. It never
opens the artifact file itself — that is this contract's own validator's job.
