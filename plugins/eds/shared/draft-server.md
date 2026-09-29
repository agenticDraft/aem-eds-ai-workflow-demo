---
description: The draft server — why no stage that needs to render `drafts/<item_id>.plain.html` can reuse `eds-serve`'s own server, and the exact start/cleanup/sandbox contract every stage that touches it follows. One long-lived server serves every item's draft; only `eds-serve`'s cleanup ever stops it or deletes a draft. Referenced by any stage adapter that renders a draft fixture through the real decoration pipeline, never restated inline.
---

# The draft server

## Why `eds-serve`'s own server can never be reused

`eds-serve` (core contract §4) always runs earlier in this pack's own route and is assumed already
up by the time a later stage runs. But it starts `.ai/project-config.yaml`'s `commands.serve`
exactly as configured — in this project, `npm run up`, which runs `aem up` with no `--html-folder`
flag. `drafts/` is mounted at a URL path only when `--html-folder` is passed, and nothing else
mounts it. So whatever `eds-serve` started never serves `drafts/<item_id>.plain.html` at all.

A stage that needs to render a draft fixture does not change what `eds-serve` started. It uses the
draft server: `aem up --html-folder drafts`, on the next port after the configured preview's,
mounted at `/drafts`.

## One server, long-lived

- **One server serves every item's draft.** A draft written after the server started is served
  without a restart; the file is resolved on every request.
- **No stage that renders a draft stops it.** `eds-verify` and `eds-verify-design` start it, or
  reuse the one already answering, and leave it running. The link a run reports stays live for the
  reviewer while the item's branch is checked out, because the server serves the working tree.
- **Its pid and log live at `.ai/logs/draft-server.pid` and `.ai/logs/draft-server.log`** — not in
  `.ai/run-context/`, which is archived before every run and would lose the only handle on the
  process.
- **Only `eds-serve`'s cleanup stops it or deletes a draft** — see **Cleanup**, below. No other
  stage calls `stop-draft-server.sh`.

## The sandbox denies loopback, deterministically, every time

The default Bash sandbox denies both `bind()` and `connect()` on `127.0.0.1`/`localhost`
outright — a hard `EPERM` on every attempt (G58, G87). **Every Bash invocation that polls this
server or starts it must set `dangerouslyDisableSandbox: true` on that call, unconditionally — not
as a retry after a first sandboxed attempt fails.** A first sandboxed attempt only spends a poll
ladder's worth of time confirming a fact this section already states as certain.

## Start, poll-first

```
bash ${CLAUDE_PLUGIN_ROOT}/../eds/shared/scripts/start-draft-server.sh \
  <paths.preview value> \
  .ai/logs/draft-server.log \
  .ai/logs/draft-server.pid
```

**Branch length first (D539).** Before it polls or starts anything, the script runs
`check-branch-length.sh` on the checked-out branch. The dev server refuses a branch over 23
characters, and that refusal reaches only its log. A too-long branch exits `1` with
`start-failed: branch name too long (<n> > 23)`, never the poll ladder's `no-answer`. This failure is
**not** transient: a restart fails the same way. The calling stage's question names the rename, not
the recovery command. No branch checked out (detached HEAD) leaves nothing to measure.

Polls before starting: the server an earlier stage or an earlier run started is normally still
answering, and is reused. Only starts a new one when nothing answered, and writes the pid file only
then. Prints `ready: origin=<url> port=<n> started=yes|no pid=<pid|none> log=<path|none>` on
success; the target URL every render/capture/measure call is built from is
`<origin>/drafts/<name>` — `.plain.html` never appears in the URL, the pipeline resolves it.
Exit `1` is a TRANSIENT failure (core contract §8) — per **D89**, the calling stage raises
`verdict: question` on exhaustion, naming the literal recovery command (`npm run up:draft`, or
`commands.serve` with `--html-folder drafts` appended, whichever this project's own configuration
makes correct) a human can run.

## Cleanup

`eds-serve` runs this first, before it starts or polls anything, from the project root:

```
bash ${CLAUDE_PLUGIN_ROOT}/../eds/shared/scripts/clean-drafts.sh <scm pack root | none>
```

Unsandboxed, because the scm role's script it runs reaches the provider over the network. For each
earlier run's change record, `.ai/scm/publish-change-<branch>.json`, it runs the scm pack's
`scripts.check_status` (`../../agentic-core/shared/pack-manifest.md`) once as a subprocess,
validates the envelope, and reads `change_state` whatever the verdict:

- `merged` or `closed` — deletes every `drafts/<id>.plain.html` whose derived branch name equals
  the record's branch, then moves the record to `.ai/logs/scm-closed/`, never overwriting one
  already there.
- `open` — keeps the draft and the record; counts as open.
- `none` — no change for that branch: deletes nothing and keeps the record; not open.
- **Unknown is never closed.** No `scripts.check_status`, a script that exits non-zero, an envelope
  that does not validate, or no `change_state` line: keeps the draft and the record, and counts as
  open.

A draft whose derived branch matches no merged or closed record is never touched. When no record is
open or unknown — including when there are no records at all — the cleanup stops the draft server
by `.ai/logs/draft-server.pid`. The current run has no record until `deliver`, so the server may be
stopped here and started again by `eds-verify`; that restart is expected.

It never calls the provider's tool itself. It prints one `record:` line per record, one `server:`
line, and a last `cleanup:` line counting each outcome. Exit `0` for every outcome; `2` for a usage
error.

## Port collision, a known limitation

The port is derived (`paths.preview`'s own port plus one), never configured. A project whose
preview port is itself one below something else already bound could collide.
