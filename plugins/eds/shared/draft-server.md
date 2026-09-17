---
description: The dedicated draft server — why no stage that needs to render `drafts/<item_id>.plain.html` can reuse `eds-serve`'s own server, and the exact start/stop/sandbox contract every stage that needs one follows. Referenced by any stage adapter that renders a draft fixture through the real decoration pipeline, never restated inline.
---

# The dedicated draft server

## Why `eds-serve`'s own server can never be reused

`eds-serve` (core contract §4) always runs earlier in this pack's own route and is assumed already
up by the time a later stage runs. But it starts `.ai/project-config.yaml`'s `commands.serve`
exactly as configured — in this project, `npm run up`, which runs `aem up` with no `--html-folder`
flag. Confirmed by reading `@adobe/aem-cli`'s own source (`src/up.js`, `src/server/HelixServer.js`):
`drafts/` is mounted at a URL path only when `--html-folder` is passed, and nothing else mounts it.
So whatever `eds-serve` started never serves `drafts/<item_id>.plain.html` at all, regardless of
what runs later in the route — this is true for every stage, not particular to any one of them.

A stage that needs to render a draft fixture does not change what `eds-serve` started, and does not
ask a human to. It starts its own dedicated server, on the next port after the configured preview's,
mounted at `/drafts` — self-owned for that stage's own lifetime: started there, stopped there,
before that stage returns. Nothing later in the route needs a `drafts/` mount, so nothing is left
running the way `eds-serve`'s own server deliberately is.

## The sandbox denies loopback, deterministically, every time

The default Bash sandbox denies both `bind()` and `connect()` on `127.0.0.1`/`localhost`
outright — not a rate limit, not a flaky occasional denial, a hard `EPERM` on every attempt,
confirmed by direct measurement (G58, reproduced a second time by a different stage's own
server-start call — G87). **Every Bash invocation that polls this server or starts it must set
`dangerouslyDisableSandbox: true` on that call, unconditionally — not as a retry after a first
sandboxed attempt fails, and not left to judgment in the moment.** A first sandboxed attempt does
not give a different, more informative failure than a first unsandboxed one would; it only spends a
poll ladder's worth of time confirming a fact this section already states as certain.

## Start, poll-first

```
bash ${CLAUDE_PLUGIN_ROOT}/../eds/shared/scripts/start-draft-server.sh \
  <paths.preview value> \
  <log-path> \
  <pid-path>
```

Polls before starting, for the same reason `eds-serve`'s own `start-serve.sh` does: a previous run
of this same stage that crashed before its own teardown ran can leave one still answering, or a
different stage's own dedicated server from earlier in this same route may already be up. Only
starts a new one when nothing answered. Prints `ready: origin=<url> port=<n>
started=yes|no pid=<pid|none> log=<path|none>` on success; the target URL every render/capture/
measure call in the calling stage is built from is `<origin>/drafts/<item_id>` — `.plain.html`
never appears in the URL, the pipeline resolves it. Exit `1` is a TRANSIENT failure (core contract
§8) — per **D89**, the calling stage raises `verdict: question` on exhaustion rather than failing
silently, naming the literal recovery command (`npm run up:draft`, or `commands.serve` with
`--html-folder drafts` appended, whichever this project's own configuration makes correct) a human
can run.

## Stop, unconditionally

```
bash ${CLAUDE_PLUGIN_ROOT}/../eds/shared/scripts/stop-draft-server.sh \
  <pid-path>
```

Safe to call on every exit path, including a path that never started anything: `start-draft-
server.sh` only ever writes the pid file when it actually launched the process itself, never when
it found one already answering, so this call is a no-op exactly when nothing needs stopping. This
is what keeps the server genuinely self-owned — no later stage inherits it, and no earlier one is
touched.

## Port collision, a known limitation

The port is derived (`paths.preview`'s own port plus one), never configured. A project whose
preview port is itself one below something else already bound could collide. Not observed in this
project's own real runs to date.
