---
description: The subagent outcome contract — the inner tier. Any stage adapter that dispatches subagents of its own must have those subagents end their output with this block, and must reference this file rather than restate the shape inline.
---

# Subagent outcome

**This is a second, separate tier from `result-envelope.md`.** The result envelope is what a
stage adapter returns to the driver that dispatched *it*. This block is what a subagent returns to
the stage adapter that dispatched *that subagent* — one tier further in, for adapters that fan out
to subagents of their own rather than doing all of a stage's work inline.

The two tiers share no status literal, on purpose: a block from the wrong tier read as if it were
the other one is a contract violation, loud and mechanical, rather than a value that happens to
match a branch. See `result-envelope.md`'s own note on this before wiring an adapter that uses
both.

Every dispatched subagent **ends** its output with this block. It must be the last thing emitted.
Anything above it is for a human debugging that subagent — the dispatching adapter reads only the
block.

## Format

```markdown
## Outcome
status: success | warning | failure
summary: <one sentence, <=200 chars, plain prose, no markdown, no line breaks>
artifacts:
  - <relative path written or updated>
next_action: <short phrase, or "none">
```

Additional field, valid only with the status shown:

```markdown
blocker: <what is missing or what went wrong>   # status: failure only, required
```

## Field rules

- `status` — exactly one of `success`, `warning`, `failure`. None of these three literals appears
  in the result envelope's `verdict` vocabulary (`pass | warn | fail | question`) or vice versa.
  The dispatching adapter branches on the literal; an unknown value is a contract violation. There
  is no status equivalent of `question` — a subagent that cannot resolve something either resolves
  it itself or returns `failure` with the gap named in `blocker`; the adapter is the one that may
  raise a `question` at the stage boundary, never the subagent underneath it.
- `summary` — one sentence, no line breaks. The adapter may quote it verbatim into its own
  reasoning, so a table or multi-line value pollutes the adapter's context the same way it would
  the driver's.
- `artifacts` — every file written or updated, so the adapter can hand paths onward without having
  read them itself. Present on every status, even as an empty list.
- `next_action` — a short phrase, or the literal string `"none"`. A name for the adapter's own use,
  not an instruction — the same rule the result envelope's `next_action` follows, for the same
  reason.
- `blocker` — what is missing or what went wrong. Required when `status: failure`, absent
  otherwise.

## Example — success

```markdown
## Outcome
status: success
summary: Rendered the three named selectors and wrote their computed values.
artifacts:
  - .ai/run-context/measurements.json
next_action: none
```

## Example — warning

```markdown
## Outcome
status: warning
summary: Two of five target files matched the pattern; the other three were skipped as binary.
artifacts:
  - .ai/run-context/matched-files.txt
next_action: report the skipped count upward
```

## Example — failure

```markdown
## Outcome
status: failure
summary: The named selector does not exist in the rendered page.
artifacts: []
next_action: none
blocker: selector '.hero-banner' not found in the rendered DOM
```

## Anti-patterns

- Prose after the block — the block must be the last thing emitted.
- A `status` outside `success | warning | failure` — including any result-envelope verdict
  literal (`pass`, `warn`, `fail`, `question`) used here by mistake.
- A missing `artifacts` list, even when empty.
- `blocker` present with a status other than `failure`.
- `blocker` absent when `status: failure`.

## Reference, not restatement

A dispatched subagent's own instructions must not copy this shape inline — they reference this
file with one line, e.g. `See shared/subagent-outcome.md for the required ## Outcome block.`

## Fixtures

One example file per status literal lives in `fixtures/subagent-outcome/`: `success.md`,
`warning.md`, `failure.md`. `fixtures/subagent-outcome/invalid/` holds one fixture per rejection
case the validator must catch: `unknown-status.md`, `outer-literal.md` (a result-envelope verdict
used as this contract's `status`), `multiline-summary.md`, `missing-artifacts.md`,
`trailing-text.md`, `missing-blocker.md`, `blocker-without-failure.md`.

## Verification

`lib/validate-subagent-outcome.sh <path>` is the deterministic checker (§13 — no model involved).
It exits `0` and prints `status: <literal>` for a conformant file, `1` with `invalid: <reason>` on
stderr for a contract violation, `2` for a usage error. Run its test suite with:

```bash
bash plugins/agentic-core/shared/lib/validate-subagent-outcome.test.sh
```
