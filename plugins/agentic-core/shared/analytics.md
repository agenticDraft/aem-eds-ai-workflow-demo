---
description: The run-analytics contract — what render-analytics.sh measures, from which files, with which formulas, and the markdown shape it writes. Every reader or writer of run analytics references this file rather than restating the formulas inline.
---

# Run analytics

A run's token measurements, rendered by a script from records the harness itself already writes to
disk for every turn and every subagent — never asked of the model, never estimated.

**Never does:** call a model to ask how many tokens were used, read or write `run-state.json` or
`progress.md` (those are `run-state.md`'s contract), or decide which subagents belong to which
stage — that correspondence is carried by whichever field the caller used to label a subagent
when it was spawned, not decided by this contract.

## Source files

Two kinds of file, both already written by the harness with no extra instrumentation:

- **The session transcript** — one JSON object per line. A line is counted only when
  `.type == "assistant"`, `.message.usage` is present, and `.isSidechain == false`.
- **A subagent transcript** — one JSON object per line, same shape as above but without the
  `isSidechain` filter (a subagent's own file holds only its own turns). Each subagent transcript
  has a sibling `.meta.json` file carrying at least `agentType`; when a `description` is present it
  is the label that subagent's row is reported under.

  **`description` is not always present, and that is a known gap, not a defect in a transcript.**
  It appears for a subagent spawned through the general subagent tool, which takes a `description`
  argument. A subagent spawned by invoking a skill declared `context: fork` has no such argument to
  pass, and its sidecar carries only `agentType` and `spawnDepth` — verified against a real run, not
  assumed. Such a row is reported unlabelled rather than dropped, so the run's totals stay correct
  even when the per-stage attribution is not available. Deciding how to recover that attribution is
  open work; it is deliberately not solved by inference here, for the reason stated above.

A subagent transcript's file and its sidecar live at `<session-transcript-path-without-.jsonl>/subagents/agent-*.jsonl` and the matching `agent-*.meta.json`. A session with no such directory has zero subagents — not an error.

## Deduplication

**A streamed turn appears as more than one line sharing the same `.message.id`,** each line's
`output_tokens` larger than the last as the turn's response grows; `input_tokens` and both cache
fields stay fixed across every line for that id, since they describe the turn's input, not its
still-growing output. **Only the last line for a given `.message.id`, in file order, counts** —
every earlier line for that id is a superseded partial snapshot of the same turn, not a second
turn.

## Two measurements, never confused

- **Peak context** — the input and output token total of the transcript's own last counted line:
  `input_tokens + cache_creation_input_tokens + cache_read_input_tokens + output_tokens`, from
  whichever turn is last in file order. No deduplication needed here — being last in the file
  already makes it the final state of its own id.
- **Cumulative billed input** — `input_tokens + cache_creation_input_tokens +
  cache_read_input_tokens`, summed across every *deduplicated* turn. This is always several times
  peak context, because most tools resend the whole conversation as input on every turn.
- **Cumulative output** — `output_tokens`, summed the same way.

Report both peak and cumulative under distinct labels. Never let one stand in for the other.

## Wall clock

The transcript's own last line carrying a `.timestamp` field minus the first line carrying one —
every conversation line carries one, not only the counted ones, but a harness bookkeeping line
(for example, a `cost-state` line) may not, so lines with no `.timestamp` are skipped rather than
treated as zero.

## `analytics.md`

```
# Run analytics

Source: <session transcript path>

## Orchestrator

- Turns counted: <n>
- Peak context: <tokens> tokens
- Cumulative billed input: <tokens> tokens
- Cumulative output: <tokens> tokens
- Wall clock: <duration>

## Subagents

| Label | Type | Turns | Peak context | Cumulative billed input | Cumulative output | Ratio | Wall clock |
| ----- | ---- | ----- | ------------- | ------------------------ | ------------------ | ----- | ---------- |
| <description> | <agentType> | <n> | <tokens> | <tokens> | <tokens> | <cumulative / peak, one decimal>x | <duration> |

## Totals

- Cumulative billed input, whole run: <tokens> tokens
- Cumulative output, whole run: <tokens> tokens
```

A run with no subagents still prints the `## Subagents` heading, with no rows under it.

## Ceilings, optional

A ceilings file, one `<label>: <max peak context>` line per label, checked only when the caller
supplies one. Every subagent row whose label has a matching ceiling line gets a `PASS` or `FAIL`
by comparing its peak context against that number; a label with no matching line is not checked. A
`## Ceilings` section is appended, one row per checked label plus an overall `PASS` or `FAIL` —
`FAIL` if any checked row failed. This contract does not fix what a ceiling *should* be — a pack
that wants regression protection supplies its own numbers.

## Anti-patterns

- Asking the model to report its own token usage, or transcribing a number that came from
  anywhere but a counted transcript line.
- Summing `output_tokens` across every line for a streamed turn instead of taking only the last —
  this overcounts a single turn as if it happened several times.
- Confusing peak context with cumulative billed input in a report, or omitting either.
- Inventing a per-stage ceiling inside this contract. Ceilings are supplied by the caller, never
  fixed here.

## Reference, not restatement

A skill or script that renders or reads run analytics references this file with one line rather
than restating the formulas or the file format inline, the same convention `run-state.md` and
`progress-output.md` use for their own contracts.

## Fixtures

`fixtures/analytics/` holds two full sessions so a reader can see the same shape render two
different numbers:

- `session-a.jsonl` plus `session-a/subagents/` (two subagents, one of them with a streamed,
  duplicate-`.message.id` turn) — the primary fixture, covering deduplication, multiple subagents,
  and the ratio calculation.
- `session-b.jsonl` plus `session-b/subagents/` — same shape, different numbers, proving the
  render is not a fixed template.
- `no-subagents.jsonl` — an orchestrator-only transcript with no `subagents/` directory alongside
  it, for the zero-subagents case.
- `trailing-untimestamped-line.jsonl` — ends in a line with `timestamp: null` and no `usage`, for
  the wall-clock skip rule.
- `ceilings.txt` — one passing and one failing ceiling line, matched against `session-a`'s labels.

## Verification

`lib/render-analytics.sh <session-transcript.jsonl> <output-path.md> [ceilings-file]` requires
`jq`. It writes `analytics.md` in the shape above to `<output-path.md>` and exits `0`, printing
`written: <output-path.md>`, unless a ceilings file was given and the overall ceilings result is
`FAIL`, in which case it still writes the file but exits `1` — the file is written either way, so a
caller can always see which row failed. Exits `2` for a usage error (missing argument, transcript
file not found, or a ceilings file argument that does not exist).

```bash
bash plugins/agentic-core/shared/lib/render-analytics.test.sh
```
