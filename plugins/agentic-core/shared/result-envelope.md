---
description: The result envelope contract. Every stage adapter and every provider operation must reference this file rather than restate the shape inline.
---

# Result envelope

Every stage adapter and every provider operation **ends** its output with this block. It must be
the last thing emitted. Anything above it is for a human debugging that stage — the runner reads
only the block. **This is where a narrative summary of what ran belongs, if one is worth writing at
all** — before the heading, never after. Labeling trailing text as commentary, context, or
explicitly "not part of the envelope" does not exempt it: the rule is positional, not semantic, and
`validate-result-envelope.sh` enforces it the same way regardless of how the text describes itself.

**This block governs one tier only: an adapter returning to the runner.** A stage adapter that
dispatches subagents of its own uses a second, separate contract for what those return to it —
see `subagent-outcome.md`. The two share no status literal, so a block from the wrong tier read as
if it were the other one is a contract violation rather than a value that happens to match a
branch.

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
error_class: TRANSIENT | VALIDATION | PERMANENT   # verdict: fail or question only
question: <the question text>          # verdict: question only
options:                               # verdict: question, optional
  - <short option label>
blocker: <what is missing>             # verdict: question, required
metrics: <key=value pairs>             # optional, any verdict
```

The fields appear in the order shown, after `next_action` — `error_class` before `question`,
`metrics` last.

## How a stage writes it

**Write it with the emitter, not by hand:**

```
bash <agentic-core plugin root>/shared/lib/emit-envelope.sh \
  .ai/run-context/envelope-<stage id>.txt \
  --verdict <verdict> --summary "<one sentence>" [--artifact <path>]…
```

It spells the block, in the field order below, from values the caller supplies, and refuses a
field this contract does not allow on the verdict given — writing nothing at all when it refuses.
A stage that calls it cannot emit a malformed block, and cannot fail to emit one by ending its
output with something else: the envelope is a file it wrote, not a shape its last message has to
carry.

Options beyond the two required: `--artifact <path>` (repeatable; none emits `artifacts: []`),
`--next-action <phrase>` (default `none`), `--error-class <class>`, `--question <text>`,
`--option <label>` (repeatable), `--blocker <text>`, `--metrics <key=value …>`.

A stage that has not yet adopted the emitter still ends its output with the block, and everything
below still governs what that block must contain. Both paths are read the same way.

## Field rules

- `verdict` — exactly one of the four literals above. The runner branches on the literal; an
  unknown value is a contract violation and terminates the run as `failed`.
- `summary` — one sentence, no line breaks. The runner may quote it verbatim into its status
  line, so a table or multi-line value pollutes the runner's context.
- `artifacts` — every file written or updated, so the runner can hand paths to a later stage
  without having read them. Present on every verdict, even as an empty list.
- `next_action` — a short phrase, or the literal string `"none"`. Never an instruction to the
  runner — a name, not a directive. In particular, a stage cannot steer the route from here: a
  skipped stage is declared by the pack as that stage's `when:` condition and evaluated against the
  fact record (`pack-manifest.md`), never announced by a stage that ran.
- `error_class` — which of the three classes the failure belongs to. Valid only with
  `verdict: fail` or `verdict: question`; a contract violation on `pass` or `warn`, which report no
  failure to classify. Exactly one of the three literals — the caller branches on it, so a literal
  no contract defines is rejected the same way an unknown `verdict` is. See `error-handling.md` for
  what each class means and what recovery each one permits. **The validator checks the literal and
  the verdict it sits on, not that it is present** — a `question` raised as a clarification rather
  than as an escalation has no failure to classify, and an operation written before this field
  existed still validates. `error-handling.md` is what asks an operation that *did* classify a
  failure to report the class it determined.
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
summary: Implemented the change; one pre-existing style warning remains, unrelated to this change.
artifacts:
  - .ai/run-context/change-summary.md
next_action: none
```

## Example — fail

```markdown
## Result
verdict: fail
summary: The item's type has no declared readiness criteria, so this pack cannot judge whether it can be worked.
artifacts: []
next_action: none
error_class: VALIDATION
```

## Example — question

```markdown
## Result
verdict: question
summary: The item's only design reference is an attached image, which could be the intended state or the defect.
artifacts: []
next_action: none
question: Which attachment is the design reference for this change?
options:
  - The first attachment
  - The second attachment
blocker: An image-only design source cannot be identified as reference or evidence without a human
```

## Anti-patterns

- Prose after the block — the block must be the last thing emitted, even prose explicitly
  labeled as commentary, context, or "not part of the envelope." Put it before the heading
  instead, where it is already sanctioned.
- A blank line, or any other line, between `## Result` and `verdict:` — `verdict:` is always the
  line immediately following the heading, with nothing between them.
- A `verdict` outside the four literals.
- A missing `artifacts` list, even when empty.
- `artifacts:` written as an inline scalar (`artifacts: path/to/file`) instead of a list — even a
  single path is still a list: `artifacts:` on its own line, followed by `  - path/to/file`.
  Writing exactly one path is not license to drop the list form.
- Tables or ASCII art inside `summary`.
- `question` or `blocker` present with a verdict other than `question`.
- `blocker` absent when `verdict: question`.
- An `error_class` outside the three literals, or one present with `verdict: pass` or
  `verdict: warn`.
- `error_class` carried as a `metrics` key instead of as its own field — nothing validates
  `metrics`, so a caller reading the class from there branches on an unchecked string.
- The block rendered as a bulleted or backtick-wrapped list (e.g. `` - `verdict: pass` `` instead
  of `verdict: pass`) — a stage adapter's own instructions that describe each field with a bullet
  (see the next section) are guidance for a human reading the skill, never a template to reproduce
  literally in the emitted block.

## Reference, not restatement

A stage adapter's own text must not copy this shape inline — it references this file with one
line, e.g. `See shared/result-envelope.md for the required ## Result block.`, the same convention
`fact-record.md`, `project-config.md`, `pack-manifest.md`, `external-content-safety.md` and
`stage-runner.md` each use for their own contracts. No validator checks this mechanically today
(G60) — it is enforced by review, the same as every other shared file's own reference rule.

## Fixtures

One example file per verdict literal lives in `fixtures/result-envelope/`: `pass.md`, `warn.md`,
`fail.md`, `question.md`. Each is a realistic stage transcript ending in a valid `## Result`
block for that verdict. `fixtures/result-envelope/invalid/` holds one fixture per rejection case
the validator must catch: `unknown-verdict.md`, `multiline-summary.md`, `missing-artifacts.md`,
`trailing-text.md`. `fail-error-class.md` and `question-error-class.md` carry `error_class` on the
two verdicts it is valid with; `invalid/unknown-error-class.md` and
`invalid/error-class-with-pass.md` are its two rejection cases.

## Verification

`lib/validate-result-envelope.sh <path>` is the deterministic checker (§13 — no model involved).
It exits `0` and prints `verdict: <literal>` for a conformant file, `1` with `invalid: <reason>`
on stderr for a contract violation, `2` for a usage error. Run its test suite with:

```bash
bash plugins/agentic-core/shared/lib/validate-result-envelope.test.sh
```
