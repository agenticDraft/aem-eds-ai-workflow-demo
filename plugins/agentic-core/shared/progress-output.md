---
description: The progress-output contract — the per-stage line format and the once-only final status table. Every reader or writer of run output references this file rather than restating the shape inline.
---

# Progress output

Two responsibilities, both pure formatting with no side effects: the one-line-per-stage output a
run prints as each stage completes, and the final status table printed once, at the end of a run.
Neither reads or writes a run's on-disk state — that is `run-state.md`'s responsibility, not this
file's.

**Never does:** write to disk, decide whether a stage is skipped, or print the status table more
than once per run. Those decisions belong to whichever skill drives a full route; this contract
only shapes what gets printed once that decision is made.

## The per-stage line

```
Stage <n>/<total>: <stage id> — <verdict> · <summary>
```

`<verdict>` is one of the four result-envelope literals — `pass | warn | fail | question` — see
`result-envelope.md`. `<summary>` is that same envelope's `summary` field, quoted verbatim.

**`<total>` is the count of stages the route will actually run, not the count originally
resolved.** A stage the caller has determined will be skipped is excluded from both `<total>` and
from `<n>`'s count of preceding stages — recomputed fresh on every call from the route's current
skip state, never cached across calls. This is what keeps the counter from going stale: nothing
remembers yesterday's total, so a skip decided between two stages is reflected in the very next
line, not retroactively.

**A skipped stage does not itself get a `Stage <n>/<total>` line.** It has no result envelope —
the adapter never ran — so there is no verdict or summary to report through this format. Whether a
skip is otherwise surfaced to a human (for example, as a row in a persisted progress file) is
`run-state.md`'s concern, once that contract exists.

## The status table

One row per stage, `<stage id>` and its status, using the same status vocabulary a persisted
progress file uses: `done | skipped | failed | running | pending`.

**Emitted exactly once per run, in the final summary.** Re-emitting it mid-run re-anchors the
earlier copy in the caller's context and costs tokens for no new information — this file's
enforcement of that rule is documentation and a single deterministic renderer, not a mid-run
guard; the discipline itself belongs to whichever skill drives a full route and decides when a run
has reached its terminal state.

## Anti-patterns

- Caching or otherwise reusing a `<total>` computed before a skip was decided.
- Printing the status table more than once, or before a run reaches a terminal state.
- Inventing a fifth verdict literal for the per-stage line — `skipped` is a status, not a verdict;
  it never appears in that line's `<verdict>` slot.
- Reading a stage-produced file to build either output. Both formatters take only what the caller
  already knows: the route's skip state, and one stage's already-validated verdict and summary.

## Reference, not restatement

A skill or script that prints run output references this file with one line rather than restating
the line format or the status vocabulary inline, the same convention `stage-runner.md` and
`result-envelope.md` use for their own contracts.

## Fixtures

`fixtures/progress/` holds:

- `route-no-skip.txt`, `route-with-skip.txt`, `route-multi-skip.txt` — route skip-state files
  for `lib/print-progress-line.sh`, one stage id per line, a skipped stage written as
  `<stage-id>: skipped`.
- `status-table-mixed.txt` — a progress file covering all five status literals, for
  `lib/print-status-table.sh`.
- `status-table-invalid-status.txt` — a status literal outside the five, for the rejection case.

## Verification

`lib/print-progress-line.sh <route-file> <current-stage-id> <verdict> <summary>` prints the
per-stage line. Exits `0`, or `2` for a usage error (stage id absent from the route file or marked
skipped in it, a verdict outside the four literals, or a malformed summary).

`lib/print-status-table.sh <progress-file>` prints the status table. Exits `0`, or `2` for a usage
error (a status outside the five literals).

```bash
bash plugins/agentic-core/shared/lib/print-progress-line.test.sh
bash plugins/agentic-core/shared/lib/print-status-table.test.sh
```
