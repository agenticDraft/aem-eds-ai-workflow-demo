---
description: The on-disk run-state contract — run-state.json's fields, progress.md's per-stage rows, the 2-hour resume rule and its mtime-refresh companion. Every reader or writer of run state references this file rather than restating the shape inline.
---

# Run state

Two files, both on disk, both updated after every stage — see core contract §9. Neither formats
anything for a human to read mid-run; that is `progress-output.md`'s job. This contract covers
only what is written to disk and when it is deleted.

**Never does:** print the per-stage line or the status table (`progress-output.md`'s job), decide
*why* a stage is skipped, or retry a stage. Those decisions belong to whichever skill drives a full
route.

## `run-state.json`

One object, rewritten in full after every stage:

```json
{
  "route_id": "standard",
  "rule": "default: standard",
  "last_stage": "implement",
  "total": 6,
  "mode": "interactive",
  "questions_used": 0,
  "start_time": "2026-09-04T10:00:00Z"
}
```

- `route_id` — the id `resolve-route.sh` resolved.
- `rule` — the resolution rule that fired (`resolve-route.sh`'s own `rule:` line, verbatim).
- `last_stage` — the id of the last stage that completed.
- `total` — the current total stage count (the recomputed-on-skip total core contract §9 defines,
  same value `print-progress-line.sh` would report).
- `mode` — `interactive` or `autonomous` (core contract §8).
- `questions_used` — the per-run question count so far.
- `start_time` — when the run began, set once and never rewritten.

## `progress.md`

One row per stage, `<stage id>: <status>` — the same flat shape `print-status-table.sh` already
reads (see `progress-output.md`), so a `progress.md` this contract writes is that script's input
verbatim, with no translation step. `<status>` is one of `done | skipped | failed | running |
pending`.

## Resume and staleness

A `run-state.json` **less than 2 hours old** (by its own mtime) means *"previous run found at
stage {last_stage}/{total} — resume or start fresh?"* — the question is asked by whichever skill
drives a route; this contract only reports the age and the fields needed to phrase it. One **2
hours old or older** is stale: it is deleted, and the run starts fresh.

**On a successful terminal state (`delivered`), `run-state.json` is deleted.** `progress.md` is not
— it is the completed run's record, not resumable state.

**The state file's mtime must be refreshed after every stage**, so a long route does not trip its
own staleness check partway through. Rewriting `run-state.json` in full after every stage already
does this — there is no separate "touch" step, and no code path that updates only some fields
without rewriting the file.

## Anti-patterns

- Computing "resume or fresh" from anything but the file's own mtime — a field inside the JSON
  recording when the run started is `start_time`, kept for the record, not read back to decide
  staleness.
- Deleting `progress.md` on a successful run. It documents what happened; `run-state.json` is the
  only file this contract deletes on success.
- Writing `run-state.json` for some stages and skipping others "because nothing changed" — a
  skipped write is a skipped mtime refresh, and a long route can trip its own staleness check
  partway through.

## Reference, not restatement

A skill or script that reads or writes run state references this file with one line rather than
restating the field list, the status vocabulary, or the 2-hour rule inline, the same convention
`stage-runner.md` and `progress-output.md` use for their own contracts.

## Fixtures

No static fixtures: the resume/staleness behavior is mtime-dependent, so `lib/check-run-state.test.sh`
builds and backdates its own state files in a temp directory rather than reading committed ones
whose mtime git does not preserve meaningfully.

## Verification

`lib/write-run-state.sh <state-file> <route-id> <rule> <last-stage> <total> <mode>
<questions-used> <start-time>` writes the object above, creating the parent directory if needed.

`lib/check-run-state.sh <state-file>` prints `status: none` (no file), `status: resume` plus the
seven fields (mtime under 2 hours), or `status: stale-deleted` after removing the file (mtime 2
hours or older).

`lib/finalize-run-state.sh <state-file>` deletes the file (`status: deleted`) or reports
`status: not-found` — idempotent either way, for the successful-terminal-state case.

`lib/write-progress-row.sh <progress-file> <stage-id> <status>` upserts one row, creating the file
on the first call and preserving every other row's order and status on later calls.

```bash
bash plugins/agentic-core/shared/lib/write-run-state.test.sh
bash plugins/agentic-core/shared/lib/check-run-state.test.sh
bash plugins/agentic-core/shared/lib/finalize-run-state.test.sh
bash plugins/agentic-core/shared/lib/write-progress-row.test.sh
```
