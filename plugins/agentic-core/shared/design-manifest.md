---
description: The design manifest schema — the written record of a project's adopted design tokens and the frames they were extracted from. Every reader of a design manifest validates against this file rather than restating the shape inline.
---

# Design manifest

Written once by the platform pack's design-system onboarding skill, from values retrieved through
the `design` role's `fetch_reference` operation (core contract §6) and nothing else. Names no
platform, no design tool, and no file extension — the pack supplies where the values come from and
where the promoted file lands; this contract only fixes what it contains.

## Location

`.ai/design/design-system.md` while the project is still reviewing an onboarding proposal. A
platform pack may promote it into project source as part of a human-approved change; that move is
the pack's own concern; this contract describes the file's contents either way.

## Format

```yaml
version: 1
tokens:
  provenance: resolved-value-set
  values:
    - name: "<string>"
      value: "<string>"
  unresolvable:
    - name: "<string>"
      reason: "<string>"
frames:
  - reference: "<string>"
    width: <number>
```

## Top-level keys

Exactly three, in this order: `version`, `tokens`, `frames`. No other key may appear at this
level.

## `tokens`

Three sub-keys, in order: `provenance`, `values`, `unresolvable`.

- **`provenance`** — how the recorded token set may be compared against a later extraction. The
  only value this contract currently defines is the literal `resolved-value-set`: compare by
  variable name and value, because no installed design provider exposes which collection or
  library a variable resolves to — only the resolved value itself. This was tested, not assumed:
  a design provider's `fetch_reference` operation returns a flat name-to-value map with no
  provenance field, and a file-level list of subscribed libraries (where a provider exposes one)
  does not map to individual variables either. A provider that one day exposes real per-variable
  provenance is a new value for this field and a version bump on this contract, not a silent
  change of meaning for `resolved-value-set`.
- **`values`** — every variable a design source resolved to a value this format can represent
  directly: a color or a plain numeric/dimensioned value. May be empty — a frame that genuinely
  uses no such variables is a normal result, not a contract violation. An empty list is always
  written as the literal `[]` on the `values:` line, never `values:` followed by nothing, the same
  convention `pack-manifest.md`'s `unsupported: []` already uses — a reader tells "empty" from "the
  next key" without counting indentation.
- **`unresolvable`** — every variable a design source resolved to a value this format cannot
  represent — a composite or structured value (for example a typography style bundling family,
  weight and size in one token) — recorded with `name` and a `reason` stating why, so it survives
  as a fact for a human to read rather than being silently dropped or guessed into a value it never
  had. May be empty, written the same `[]` way.

A variable name appears in exactly one of `values` or `unresolvable`, never both, and never twice
within either list. Two source frames resolving the same variable name to two different raw
values is a conflict the manifest cannot represent at all — the writer that produces this file
refuses to write one, rather than picking either value.

## `frames`

A non-empty list. Each entry has exactly two keys, in order: `reference` (the same opaque
design-tool reference `fetch_reference` was called with — a URL, not a file path) and `width` (the
frame's own geometry, a positive number, in the design tool's own units). A frame width is a
canvas width — the design tool's statement of what that layout looks like — not a threshold; this
contract records the fact and derives nothing from it.

## Field rules

- `version` — an integer, `>= 1`.
- `tokens.provenance` — the non-empty string `resolved-value-set`. No other value is defined yet.
- `tokens.values[].name`, `tokens.values[].value` — each a non-empty string.
- `tokens.unresolvable[].name`, `tokens.unresolvable[].reason` — each a non-empty string.
- `frames[].reference` — a non-empty string.
- `frames[].width` — a number greater than `0`.

## Example

```yaml
version: 1
tokens:
  provenance: resolved-value-set
  values:
    - name: "Accent/Accent 4"
      value: "#000000"
    - name: "Dividers/Divider 1"
      value: "#E9E9E9"
  unresolvable:
    - name: "Heading 1"
      reason: "value is not a recognized color or dimension: provider returned a composite type"
frames:
  - reference: "https://example-design-tool.test/file/abc123?node=1-118"
    width: 1280
```

## Anti-patterns

- A top-level key outside the three named above, or the three out of order.
- `tokens.provenance` set to anything other than `resolved-value-set`.
- A variable name present in both `tokens.values` and `tokens.unresolvable`, or repeated within
  either list.
- Any `name`, `value`, or `reason` field empty.
- `frames` empty, or a `frames[].width` that is zero or negative.
- A resolved value silently omitted, or an unresolved value written into `tokens.values` with a
  guessed or partial conversion instead of appearing in `tokens.unresolvable`.

## Reference, not restatement

A skill or script that reads or writes a design manifest references this file with one line rather
than restating the shape inline, the same convention `project-config.md` and
`convention-record.md` use for their own contracts.

## Fixtures

One well-formed example lives at `fixtures/design-manifest/valid.yaml`.
`fixtures/design-manifest/invalid/` holds one fixture per rejection case the validator must catch.
`fixtures/design-manifest/artifacts/` holds `fetch_reference`-shaped input artifacts the writer
consumes, for its own test suite.

## Verification

`lib/validate-design-manifest.sh <path>` is the deterministic checker — no model involved. It
exits `0` and prints `valid` for a conformant file, `1` with `invalid: <reason>` on stderr for a
contract violation, `2` for a usage error. Run its test suite with:

```bash
bash plugins/agentic-core/shared/lib/validate-design-manifest.test.sh
```

`lib/write-design-manifest.sh` is the deterministic writer — it never guesses: a value it cannot
classify goes to `tokens.unresolvable`, never a guessed entry in `tokens.values`, and a same-name
conflict across input frames aborts rather than picking one value. Run its test suite with:

```bash
bash plugins/agentic-core/shared/lib/write-design-manifest.test.sh
```
