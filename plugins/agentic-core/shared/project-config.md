---
description: The project config schema. Every reader of the config validates against this file rather than restating the shape inline.
---

# Project config

Written once by setup, read by everything. Detect → confirm → write; re-runnable with
keep / re-detect / edit.

## Location

`.ai/project-config.yaml` at the project root. Committed — nothing in it is a secret, and every
teammate and every pack reads the same one file.

## Format

```yaml
version: 1

packs:
  platform: <pack name>
  tracker:  <pack name>
  scm:      <pack name>
  design:   <pack name> | none
  browser:  <pack name>

commands:
  lint:  "<command>"
  test:  "<command>"
  build: "<command>"
  serve: "<command>"

paths:
  spec_dir: "<dir>"
  preview:  "<url>"

limits:
  questions_per_run: <int>
  fix_attempts_default: <int>
```

## Top-level keys

Exactly five, in this order: `version`, `packs`, `commands`, `paths`, `limits`. No other key may
appear at this level. A key outside this set, a required key missing, or the five out of order is
a contract violation.

## Field rules

- `version` — an integer, `>= 1`.
- `packs` — five sub-keys in order: `platform`, `tracker`, `scm`, `design`, `browser`. Each is a
  non-empty pack name, except `design`, which may also be the literal `none`.
- `commands` — four sub-keys in order: `lint`, `test`, `build`, `serve`. Each a quoted string;
  detected from the project and refreshable, so an empty string (`""`) is valid — a command that
  was not detected, not a command that was skipped.
- `paths` — two sub-keys in order: `spec_dir`, `preview`. Each a non-empty quoted string.
- `limits` — two sub-keys in order: `questions_per_run`, `fix_attempts_default`. Each a
  non-negative integer.

**No stage list lives here.** The platform pack owns the one stage list and every stage's own
condition (`pack-manifest.md`'s Condition semantics section); this file describes the project and
nothing else. An item type can only ever run a **subset** of that one stage list, in that order —
a type needing a genuinely different sequence cannot be expressed.

## Example

```yaml
version: 1

packs:
  platform: example-platform
  tracker: example-tracker
  scm: example-scm
  design: none
  browser: example-browser

commands:
  lint: "run-lint"
  test: "run-test"
  build: "run-build"
  serve: "run-serve"

paths:
  spec_dir: "specs"
  preview: "http://localhost:0000/preview"

limits:
  questions_per_run: 3
  fix_attempts_default: 2
```

## Anti-patterns

- A top-level key outside the five named above.
- A required top-level key missing, or the five out of order.
- A negative value under `limits`.

## Reference, not restatement

A skill or script that reads project config references this file with one line rather than
restating the shape inline, the same convention `result-envelope.md` uses for the envelope
contract.

## Fixtures

One well-formed example lives at `fixtures/project-config/valid.yaml`.
`fixtures/project-config/invalid/` holds one fixture per rejection case the validator must catch:
`unknown-top-level-key.yaml`.

## Verification

`lib/validate-project-config.sh <path>` is the deterministic checker — no model involved. It exits
`0` and prints `valid` for a conformant file, `1` with `invalid: <reason>` on stderr for a contract
violation, `2` for a usage error. Run its test suite with:

```bash
bash plugins/agentic-core/shared/lib/validate-project-config.test.sh
```
