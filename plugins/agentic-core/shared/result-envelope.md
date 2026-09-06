---
description: The result envelope contract. Every stage adapter and every provider operation must reference this file rather than restate the shape inline.
---

# Result envelope

Every stage adapter and every provider operation **ends** its output with this block. It must be
the last thing emitted. Anything above it is for a human debugging that stage — the runner reads
only the block.

## Format

```markdown
## Result
verdict: pass | warn | fail | question
summary: <one sentence, <=200 chars, plain prose, no markdown, no line breaks>
artifacts:
  - <relative path written or updated>
next_action: <short phrase, or "none">
```

Additional fields, valid only with the verdict shown:

```markdown
question: <the question text>          # verdict: question only
options:                               # verdict: question, optional
  - <short option label>
blocker: <what is missing>             # verdict: question, required
metrics: <key=value pairs>             # optional, any verdict
```

## Field rules

- `verdict` — exactly one of the four literals above. The runner branches on the literal; an
  unknown value is a contract violation and terminates the run as `failed`.
- `summary` — one sentence, no line breaks. The runner may quote it verbatim into its status
  line, so a table or multi-line value pollutes the runner's context.
- `artifacts` — every file written or updated, so the runner can hand paths to a later stage
  without having read them. Present on every verdict, even as an empty list.
- `next_action` — a short phrase, or the literal string `"none"`. Never an instruction to the
  runner — a name, not a directive. In particular, a stage cannot steer the route from here: a
  skipped stage is declared by the pack and evaluated from disk (`pack-manifest.md`'s
  `skip_when_missing`), never announced by a stage that ran.
- `question` — the question text. Required when `verdict: question`, absent otherwise.
- `options` — short option labels for the human or the `tracker` role to choose from. Optional,
  `verdict: question` only.
- `blocker` — what is missing that stopped the stage from reaching a `pass`/`warn`/`fail`
  verdict. Required when `verdict: question`, absent otherwise.
- `metrics` — free-form `key=value` pairs. Optional on any verdict.

## Example — pass

```markdown
## Result
verdict: pass
summary: Fetched the work item, sanitized its text, and wrote the fact record.
artifacts:
  - .ai/run-context/fact-record.yaml
next_action: none
```

## Example — warn

```markdown
## Result
verdict: warn
summary: Route resolved to the default row; no signal table entry matched the fact record.
artifacts:
  - .ai/run-context/route.yaml
next_action: continue to the first resolved stage
```

## Example — fail

```markdown
## Result
verdict: fail
summary: The work item's declared route id does not exist in the configured route table.
artifacts: []
next_action: none
```

## Example — question

```markdown
## Result
verdict: question
summary: Two config values are required before the route can be resolved and neither is set.
artifacts: []
next_action: none
question: Which pack should own the tracker role for this project?
options:
  - Use the pack already declared for scm
  - List available tracker packs
blocker: packs.tracker is unset in project config
```

## Anti-patterns

- Prose after the block — the block must be the last thing emitted.
- A `verdict` outside the four literals.
- A missing `artifacts` list, even when empty.
- Tables or ASCII art inside `summary`.
- `question` or `blocker` present with a verdict other than `question`.
- `blocker` absent when `verdict: question`.

## Reference, not restatement

A stage adapter's own text must not copy this shape inline — it references this file with one
line, e.g. `See shared/result-envelope.md for the required ## Result block.` A deterministic
validator checks this: every stage adapter's text references the envelope contract, rather than
each adapter drifting from its own copy.

## Fixtures

One example file per verdict literal lives in `fixtures/result-envelope/`: `pass.md`, `warn.md`,
`fail.md`, `question.md`. Each is a realistic stage transcript ending in a valid `## Result`
block for that verdict. `fixtures/result-envelope/invalid/` holds one fixture per rejection case
the validator must catch: `unknown-verdict.md`, `multiline-summary.md`, `missing-artifacts.md`,
`trailing-text.md`.

## Verification

`lib/validate-result-envelope.sh <path>` is the deterministic checker (§13 — no model involved).
It exits `0` and prints `verdict: <literal>` for a conformant file, `1` with `invalid: <reason>`
on stderr for a contract violation, `2` for a usage error. Run its test suite with:

```bash
bash plugins/agentic-core/shared/lib/validate-result-envelope.test.sh
```
