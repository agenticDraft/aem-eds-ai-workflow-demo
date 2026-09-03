---
description: The convention record schema — the written form of a pack-generation interview's answers. Every reader of a convention record validates against this file rather than restating the shape inline.
---

# Convention record

Written once by `setup`'s generate step, alongside the platform pack it produces from the same
answers (core contract §7.1, step 4: "write the answers themselves out as the project's convention
record"). Re-runnable with the keep / re-detect / edit protocol, the same as `project-config.yaml`.

## Location

`.ai/project-conventions.yaml` at the project root. Committed — nothing in it is a secret, and it
is the durable record of what a human was actually asked and answered, kept separate from the pack
itself so the answers survive a pack regenerated from a template update.

## Format

```yaml
version: 1
pack_name: "<pack name>"
unit_of_work_location: "<where the units of work live>"
definition_of_done: "<what makes a change done>"
stage_conventions: "<conventions the stages must honour, or \"none\">"
verification_gate: "<the command or check that confirms correctness>"
```

## Top-level keys

Exactly six, in this order: `version`, `pack_name`, `unit_of_work_location`,
`definition_of_done`, `stage_conventions`, `verification_gate`. No other key may appear at this
level. A key outside this set, a required key missing, or the six out of order is a contract
violation.

## Field rules

- `version` — an integer, `>= 1`.
- `pack_name`, `unit_of_work_location`, `definition_of_done`, `stage_conventions`,
  `verification_gate` — each a non-empty quoted string. **None may be blank.** An interview
  question that produced no answer is a failed setup, not a record with a hole in it — the same
  rule the generated pack itself is held to (core contract §13 validator 10). A human with
  genuinely no stage conventions still answers explicitly (`"none"`); the field is never silently
  empty.

## Example

```yaml
version: 1
pack_name: "acme-storefront"
unit_of_work_location: "components/, one directory per component"
definition_of_done: "the component renders with no console errors and its story file is updated"
stage_conventions: "every component exports a single default function named after its directory"
verification_gate: "the project's lint and test commands both exit 0"
```

## Anti-patterns

- A top-level key outside the six named above.
- A required top-level key missing, or the six out of order.
- Any of the five string fields empty.

## Reference, not restatement

A skill or script that reads or writes a convention record references this file with one line
rather than restating the shape inline, the same convention `project-config.md` and
`pack-manifest.md` use for their own contracts.

## Fixtures

One well-formed example lives at `fixtures/convention-record/valid.yaml`.
`fixtures/convention-record/invalid/` holds one fixture per rejection case the validator must
catch: `empty-field.yaml`, `unknown-top-level-key.yaml`.

## Verification

`lib/validate-convention-record.sh <path>` is the deterministic checker — no model involved. It
exits `0` and prints `valid` for a conformant file, `1` with `invalid: <reason>` on stderr for a
contract violation, `2` for a usage error. Run its test suite with:

```bash
bash plugins/agentic-core/shared/lib/validate-convention-record.test.sh
```
