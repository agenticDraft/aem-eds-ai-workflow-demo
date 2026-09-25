---
description: The question protocol — boundary-only questions, interactive and autonomous execution modes, the per-run question cap, and the always-autonomous override. Every reader or writer of a verdict:question outcome references this file rather than restating the shape inline.
---

# Question protocol

`stage-runner.md` reads `verdict: question` like any other verdict but defines no decision for
it — this file is that decision. **Questions are asked at stage boundaries only.** A stage that
cannot resolve something does not suspend: it finishes everything that does not depend on the
answer and returns `verdict: question` with `blocker`. Once answered, **the stage that asked is
re-invoked, exactly once, with the answer among its inputs**. No stage is ever suspended or resumed
mid-run.

**Never does:** pause a stage mid-run, retry a stage, or call a `tracker` pack's `post_note`
operation itself — that call belongs to whichever skill drives a full route, the same boundary
`run-stage.sh` draws around spawning an adapter.

## Execution modes

Set by an explicit flag, never inferred from wording.

- **interactive** (default) — the human is asked the `question` (with `options` when given).
  Counts against the per-run cap. On exhaustion the run ends `blocked`.
- **autonomous** — no question reaches a human. The `blocker` is handed to whichever skill drives
  the route, to write back through a `tracker` pack's `post_note` operation, and the run ends
  `blocked`. Nothing is guessed.

## Always-autonomous override

A platform pack may mark a stage `always_autonomous` in its manifest (`pack-manifest.md`). A
`question` from that stage is treated as `fail` in **both** modes, checked before either mode's
own handling — the stage is never asked about, and autonomous mode's write-back does not apply to
it either.

## How the answer reaches the stage that asked

The answer is written to a stage-readable file crossing the runner-stage boundary, the same bucket
as the fact record and the resolved route:

```yaml
stage: "<the id of the stage that asked>"
question: "<the question text, verbatim>"
answer: "<the answer text>"
```

Then the stage named in `stage` is invoked again, with the same invocation argument it was given
the first time. This contract fixes only the file's shape and where it lives conceptually (the
stage-readable boundary); the exact path is the route driver's to place.

- **The answer belongs to `stage`.** The file stays on disk after the re-invocation, so a stage
  reads it only through `lib/read-question-answer.sh` with its own id, which returns the answer
  only when `stage` matches. Any other stage ignores it.
- **Exactly once per answer.** The re-invocation's envelope is judged like any other stage's. A
  `question` from it is a new question: same mode rules, same per-run cap, and — when asked — its
  own single re-invocation.
- **Recorded after, never before.** The asking stage is recorded as completed only when its
  re-invocation continues. Until then, run state names the stage before it, so a resumed run
  re-invokes the asking stage rather than skipping it.
- **Not a retry.** A retry re-runs a stage on the same inputs after `fail`, and never happens. A
  re-invocation runs it on an input it asked for.

## Decision vocabulary

Extends `stage-runner.md`'s vocabulary with one new outcome; two entries reuse an existing
literal rather than inventing a parallel one for the same meaning:

| Outcome                       | From                                            | Meaning                                          |
| ------------------------------ | ------------------------------------------------ | ------------------------------------------------- |
| `ask`                         | interactive, budget left                       | The human is asked; the budget is consumed by one; `next_stage` names the stage to re-invoke. |
| `terminate-blocked`           | interactive budget exhausted, or autonomous mode | The run ends `blocked` (core contract §10).      |
| `terminate-failed`            | an always-autonomous stage's `question`         | Reuses `stage-runner.md`'s literal — the override has no separate meaning from an ordinary `fail`. |

## Anti-patterns

- Asking a human in autonomous mode.
- Consuming the per-run budget for an always-autonomous stage's question (it never reaches either
  mode's own handling).
- Handing the answer forward to the next stage instead of re-invoking the stage that asked.
- Re-invoking the asking stage more than once for one answer, or re-invoking it without having
  asked (that is a retry).
- Recording the asking stage as completed before its re-invocation returns.
- A stage acting on an answer whose `stage` is not its own id, or reading the file directly
  rather than through `lib/read-question-answer.sh`.

## Reference, not restatement

A skill or script that decides on a `verdict: question` outcome references this file with one
line rather than restating the mode rules or the always-autonomous override inline, the same
convention `stage-runner.md` and `run-state.md` use for their own contracts.

## Fixtures

No fixtures of its own: `lib/handle-question.sh` exercises the platform pack manifest fixture
already under `fixtures/pack-manifest/platform-valid/` (its `always_autonomous: [deliver]` entry
is the override case) together with `fixtures/result-envelope/question.md`.

## Verification

`lib/handle-question.sh <path-to-pack.yaml> <mode> <stage id> <path-to-envelope>
<questions-used> <questions-cap>` is the deterministic decision — no model involved, no side
effects. It exits `0` and prints `decision: ask` plus the question, its options if any, the
incremented budget, and `next_stage:` naming the stage to re-invoke once answered; `3` and `decision: terminate-failed` for the always-autonomous override; `4`
and `decision: terminate-blocked` for an exhausted budget or autonomous mode (with a
`write-blocker:` line in the autonomous case); `1` with `invalid: <reason>` on stderr and
`decision: terminate-contract-violation` for a malformed argument or a non-question envelope; `2`
for a usage error.

`lib/write-question-answer.sh <path> <stage id> <question> <answer>` writes the file above,
creating the parent directory if needed.

`lib/read-question-answer.sh <path> <stage id>` exits `0` and prints the answer when the file
exists and its `stage` is `<stage id>`; `3` with nothing on stdout when the file is absent or
belongs to another stage; `1` for a malformed file; `2` for a usage error.

```bash
bash plugins/agentic-core/shared/lib/handle-question.test.sh
bash plugins/agentic-core/shared/lib/write-question-answer.test.sh
bash plugins/agentic-core/shared/lib/read-question-answer.test.sh
```
