---
description: Runs one whole delivery route end to end — the route driver. Resolves pre-flight and the route, then for every stage spawns that stage's adapter as an isolated forked subagent, validates its result envelope, branches on the verdict, persists run state and progress after every stage, and drives the run to exactly one of the three terminal states (delivered, blocked, failed). This is the only component allowed to spawn a stage adapter. Use only to actually execute a configured route against a real work item — never to author a stage adapter, a contract, or project config, and never as a substitute for running one stage standalone.
disable-model-invocation: true
argument-hint: "<work item id or URL>"
hooks:
  PreToolUse:
    - matcher: Read
      command: "${CLAUDE_PLUGIN_ROOT}/skills/run-route/scripts/warn-source-read.sh"
      timeout: 5
---

You are the route driver. You own exactly two things: **control flow** and **process lifecycle**.
You never read a source file, never open a path listed under an envelope's `artifacts:`, never
retry a stage, and never restate a contract inline — every shape and rule below is defined once in
`shared/*.md` and referenced here by filename. You are the one component in this core allowed to
spawn a stage adapter; every other script in this plugin is deterministic and has no model step at
all (see `shared/stage-runner.md`).

These contracts govern what follows, each already shipped with its own passing test suite. Read them
if a step below is unclear, but never restate their shapes here: `shared/result-envelope.md`,
`shared/stage-runner.md`, `shared/progress-output.md`, `shared/run-state.md`,
`shared/orchestration-flag.md`, `shared/question-protocol.md`, `shared/terminal-states.md`,
`shared/pre-flight.md`, `shared/pack-manifest.md`, `shared/project-config.md`.

## Fixed paths

Every path below is this skill's own convention, chosen because it crosses (or does not cross) the
driver↔stage boundary — see `shared/pack-manifest.md`'s own examples, which already use the
`.ai/run-context/` half of this split. Use these exact paths; do not invent alternatives.

**Root `.ai/` — this skill's own bookkeeping. No stage ever reads these.**
- `.ai/project-config.yaml` — project config (`shared/project-config.md`)
- `.ai/run-state.json` — run state (`shared/run-state.md`)
- `.ai/progress.md` — persisted progress (`shared/run-state.md`)
- `.ai/route-progress.txt` — the flat, skip-annotated stage list `print-progress-line.sh` reads
  (`shared/progress-output.md`) — one stage id per line, in list order, a skipped stage written
  as `<stage-id>: skipped`
- `.ai/run-context/stage-conditions.txt` — `evaluate-stage-conditions.sh`'s output, written once
  after `intake` and read back by `write-run-state.sh`, which turns its `skipped:` lines into run
  state's `skipped` array (`shared/run-state.md`)
- `.ai/logs/run-route-reads.log` — the read-hook's log (see frontmatter above)

**`.ai/run-context/` — crosses the driver↔stage boundary. A stage adapter reads these as its own
input.**
- `.ai/run-context/orchestrating.flag` — the orchestration marker (`shared/orchestration-flag.md`)
- `.ai/run-context/fact-record.yaml` — the fact record `intake` emits (`shared/fact-record.md`)
- `.ai/run-context/question-answer.yaml` — the question/answer pair, when a stage asked one
  (`shared/question-protocol.md`)
- `.ai/run-context/envelope-<stage id>.txt` — one stage's captured envelope, overwritten per
  stage; not an artifact any later stage reads, purely this skill's own scratch space for handing
  a captured envelope to `run-stage.sh`

**Pack roots**, resolved from project config's `packs:` map: `.ai/packs/<pack name>/pack.yaml`.

## How a stage adapter is invoked

Every stage id in the resolved route names a skill in the platform pack's `stages:` map
(`shared/pack-manifest.md`), at `<platform pack root>/skills/<skill name>/SKILL.md`. That file
declares `context: fork` in its own frontmatter — checked mechanically by
`validate-pack-manifest.sh` (core contract §13 rule 11) — meaning it is *written* as a skill meant
to run in an isolated subagent whose content becomes the subagent's entire prompt.

**Spawn it with `Skill(<skill name>)`. That is the only way.** `Skill()` resolves a skill this
session has actually discovered, so **every configured pack must be loaded as a plugin before a
route can run** — via its own `--plugin-dir`, or installed. A session that has the pack manifest on
disk but has not loaded the pack cannot run its stages.

**If `Skill()` reports the skill unknown, that is a contract violation** — the manifest names a
stage adapter this session cannot resolve, exactly like a stage id the manifest dropped. Route to
**failed**, and say which pack was not loaded, so the fix is obvious.

Resist the temptation to read the adapter's `SKILL.md` and paste its body into a general subagent
instead. It looks equivalent — `context: fork` does say the skill's content becomes the subagent's
prompt — but only the frontmatter the harness reads makes that true: `allowed-tools`, any
skill-scoped `hooks:`, and the enforced isolation `validate-pack-manifest.sh` checks for. Pasting
the body hands the subagent the instructions without the sandbox those instructions assume, and
does it silently. An unloaded pack is a configuration error to report, not a gap to route around.

Pass the stage's inputs as the invocation's argument text, one `key: value` line per input:

```
stage: <stage id>
fact_record: .ai/run-context/fact-record.yaml
question_answer: .ai/run-context/question-answer.yaml   # only when the previous stage asked one
```

A stage is never told the shape of the run it is part of. It gets the fact record and, when one was
asked, the previous stage's answer; which stages ran before it, and which were skipped, are yours to
know and not its business to branch on.

**Wait for its result before doing anything else.** A forked skill's result arrives in your
conversation when it completes — do not invoke the next stage until you have captured this one's
envelope and branched on it. This is what makes the loop sequential; nothing about `context: fork`
itself limits you to one at a time, your own discipline does.

**You cannot label the spawn, and you should not try.** `Skill()` takes the skill and its
arguments, nothing else — there is no `description` to set. `shared/analytics.md` labels a
subagent's row by the `description` in its sidecar metadata, and a skill-spawned fork's sidecar has
none, so a run's per-stage cost rows come back unlabelled. That is a known, recorded gap in
attribution, not something to work around by reaching for a different spawn mechanism: a correct
run with unlabelled cost rows is strictly better than a mislabelled one that ran its stages outside
their declared sandbox.

The subagent's output ends with a `## Result` block — the result envelope (`shared/result-envelope.md`).
Capture everything from that block onward into `.ai/run-context/envelope-<stage id>.txt`,
overwriting any previous stage's file there. Never parse anything above that block.

## Skipped stages

A skip is declared by the **pack**, not by a running stage: each stage in the platform manifest's
`stages:` list may carry a `when:` condition naming fact-record fields (`shared/pack-manifest.md`).
You never decide a skip yourself, and you never read a skip out of an envelope —
`shared/result-envelope.md` is explicit that `next_action` is a name, not a directive to you.

To evaluate the conditions, run:

```
${CLAUDE_PLUGIN_ROOT}/shared/lib/evaluate-stage-conditions.sh <platform pack.yaml> .ai/run-context/fact-record.yaml
```

It prints one line per stage in list order — `run: <stage id>`, or
`skipped: <stage id> — <condition>`. Capture its output to
`.ai/run-context/stage-conditions.txt`, then write `.ai/route-progress.txt` from it: a bare stage id
for each `run:` line, `<stage id>: skipped` for each `skipped:` one.

**Run it exactly once per run**, right after `intake` produces the fact record. Conditions name
fact-record fields only, and that record is written once and never rewritten, so no stage can change
another stage's skip state part way through. A stage's condition cannot go stale, and nothing needs
re-evaluating between stages.

Do not restate a condition in your own words anywhere. `write-run-state.sh` reads
`.ai/run-context/stage-conditions.txt` directly, so the condition recorded against a skipped stage
is the evaluator's own rendering rather than your paraphrase of it.

## Flow

```dot
digraph run_route {
    "Resolve pre-flight" [shape=box];
    "Pre-flight passed?" [shape=diamond];
    "Check run-state" [shape=box];
    "Run-state status?" [shape=diamond];
    "Resume or start fresh?" [shape=diamond];
    "Fresh start: write flag, run intake" [shape=box];
    "Intake decision?" [shape=diamond];
    "Evaluate stage conditions" [shape=box];
    "Record intake stage" [shape=box];
    "Resume: re-evaluate stage conditions" [shape=box];
    "Stage list matches?" [shape=diamond];
    "Drive next stage" [shape=box];
    "Stage skipped?" [shape=diamond];
    "Record skipped stage" [shape=box];
    "Resolve stage adapter" [shape=box];
    "Adapter resolvable?" [shape=diamond];
    "Invoke adapter, capture envelope" [shape=box];
    "Validate envelope" [shape=box];
    "Envelope decision?" [shape=diamond];
    "Record stage, refresh flag" [shape=box];
    "Stage is deliver?" [shape=diamond];
    "Handle question" [shape=box];
    "Question decision?" [shape=diamond];
    "Ask human, record answer" [shape=box];
    "blocked" [shape=doublecircle];
    "failed" [shape=doublecircle];
    "delivered" [shape=doublecircle];

    "Resolve pre-flight" -> "Pre-flight passed?";
    "Pre-flight passed?" -> "blocked" [label="no"];
    "Pre-flight passed?" -> "Check run-state" [label="yes"];
    "Check run-state" -> "Run-state status?";
    "Run-state status?" -> "Resume or start fresh?" [label="resume (fresh, <2h)"];
    "Run-state status?" -> "Fresh start: write flag, run intake" [label="none, or stale-deleted"];
    "Resume or start fresh?" -> "Resume: re-evaluate stage conditions" [label="resume"];
    "Resume or start fresh?" -> "Fresh start: write flag, run intake" [label="start fresh"];
    "Fresh start: write flag, run intake" -> "Intake decision?";
    "Intake decision?" -> "failed" [label="terminate-failed / terminate-contract-violation"];
    "Intake decision?" -> "Evaluate stage conditions" [label="continue / continue-warn"];
    "Evaluate stage conditions" -> "Record intake stage";
    "Record intake stage" -> "Handle question" [label="intake asked a question"];
    "Record intake stage" -> "Drive next stage" [label="no question asked"];
    "Resume: re-evaluate stage conditions" -> "Stage list matches?";
    "Stage list matches?" -> "failed" [label="no — the pack or the fact record changed"];
    "Stage list matches?" -> "Drive next stage" [label="yes"];
    "Drive next stage" -> "Stage skipped?";
    "Stage skipped?" -> "Record skipped stage" [label="yes"];
    "Stage skipped?" -> "Resolve stage adapter" [label="no"];
    "Record skipped stage" -> "Drive next stage" [label="next stage"];
    "Resolve stage adapter" -> "Adapter resolvable?";
    "Adapter resolvable?" -> "failed" [label="no — unresolvable or unloaded"];
    "Adapter resolvable?" -> "Invoke adapter, capture envelope" [label="yes"];
    "Invoke adapter, capture envelope" -> "Validate envelope";
    "Validate envelope" -> "Envelope decision?";
    "Envelope decision?" -> "Record stage, refresh flag" [label="continue / continue-warn"];
    "Envelope decision?" -> "Handle question" [label="question"];
    "Envelope decision?" -> "failed" [label="terminate-failed / terminate-contract-violation"];
    "Record stage, refresh flag" -> "Stage is deliver?";
    "Stage is deliver?" -> "delivered" [label="yes"];
    "Stage is deliver?" -> "Drive next stage" [label="no — next stage"];
    "Handle question" -> "Question decision?";
    "Question decision?" -> "Ask human, record answer" [label="ask"];
    "Question decision?" -> "blocked" [label="terminate-blocked"];
    "Question decision?" -> "failed" [label="terminate-failed (autonomous override)"];
    "Ask human, record answer" -> "Record stage, refresh flag";
}
```

## Node Details

### Resolve pre-flight

Resolve each role's pack path from `.ai/project-config.yaml`'s `packs:` map
(`.ai/packs/<pack name>/pack.yaml`), then run:

```
${CLAUDE_PLUGIN_ROOT}/shared/lib/check-preflight.sh .ai/project-config.yaml \
  platform=<path> tracker=<path> scm=<path> browser=<path> [design=<path>]
```

### Pre-flight passed?

If it exits non-zero: no branch, run state, or marker exists yet, so there is nothing to finalize.
Report `terminal: blocked` immediately, naming exactly what pre-flight's `invalid: <reason>` says is
missing and that it was never recorded anywhere (core contract §4 — pre-flight failure is one of
`shared/terminal-states.md`'s `blocked` causes). Route to **blocked**; do not proceed.

If it passes, go to **Check run-state**.

### Check run-state

Run `${CLAUDE_PLUGIN_ROOT}/shared/lib/check-run-state.sh .ai/run-state.json`.

### Run-state status?

- **`status: resume`** — a previous run exists inside the 2-hour window. Go to **Resume or start
  fresh?**.
- **`status: stale-deleted`** — the file was 2 hours old or older and is already removed. Note this
  plainly in your report, then go to **Fresh start: write flag, run intake**.
- **`status: none`** — go to **Fresh start: write flag, run intake**.

### Resume or start fresh?

Ask, with `AskUserQuestion`: *"Previous run found at stage {last_stage}/{total} — resume or start
fresh?"* using the fields `check-run-state.sh` reported.

- **resume** — go to **Resume: re-derive route**.
- **start fresh** — treat exactly as `status: none`, and go to **Fresh start: write flag, run
  intake**. Nothing deletes the old `run-state.json` for you here; overwrite it there the same way
  a fresh run always does.

### Fresh start: write flag, run intake

1. `${CLAUDE_PLUGIN_ROOT}/shared/lib/write-orchestration-flag.sh .ai/run-context/orchestrating.flag`
2. Invoke the `intake` stage adapter (see "How a stage adapter is invoked" — `intake` needs no
   `fact_record`/`route` input yet, since it is what produces the fact record). Capture its
   envelope to `.ai/run-context/envelope-intake.txt`.
3. `${CLAUDE_PLUGIN_ROOT}/shared/lib/run-stage.sh <platform pack.yaml> intake .ai/run-context/envelope-intake.txt`
   → go to **Intake decision?**.

### Intake decision?

`terminate-failed` or `terminate-contract-violation` here means core contract §4's guarantee
already held — no branch, file, or route exists — so route to **failed**, after removing the
marker you just wrote (`finalize-orchestration-flag.sh .ai/run-context/orchestrating.flag`); no
run state was ever written, so there is nothing else to finalize.

On `continue`/`continue-warn`: `intake`'s envelope must list the fact record among its
`artifacts:` at `.ai/run-context/fact-record.yaml` (`shared/fact-record.md`). Go to **Evaluate
stage conditions**.

### Evaluate stage conditions

The platform pack owns the stage list; nothing selects it, and there is no route to resolve. Read
`stages:` from the platform pack's `pack.yaml` — that list, in that order, is the run.

Evaluate each stage's condition against the fact record and write both files — see **Skipped
stages** above. Then go to **Record intake stage**.

### Record intake stage

1. `${CLAUDE_PLUGIN_ROOT}/shared/lib/print-progress-line.sh .ai/route-progress.txt intake <verdict> <summary>`
   — read `<total>` from its own output line; do not recompute it separately.
2. `${CLAUDE_PLUGIN_ROOT}/shared/lib/write-run-state.sh .ai/run-state.json <pack name> stage-list intake <total> <mode> 0 <now> .ai/run-context/stage-conditions.txt`,
   where `<now>` is the output of `date -u +%Y-%m-%dT%H:%M:%SZ` — call it once, right here, and use
   the same value in every later `write-run-state.sh` call this run (`start_time` is set once and
   never rewritten, per `shared/run-state.md`). Do not stash it in a file of your own; it is one
   short value to carry forward in your own working memory for the rest of the run. The script reads
   the skipped stages and their conditions out of the conditions file itself, so you never restate
   one.
3. `${CLAUDE_PLUGIN_ROOT}/shared/lib/write-progress-row.sh .ai/progress.md intake done`
4. `${CLAUDE_PLUGIN_ROOT}/shared/lib/write-orchestration-flag.sh .ai/run-context/orchestrating.flag`
   (refresh)

If `intake` returned `verdict: question`, go to **Handle question**, with `intake` as the asking
stage. Otherwise go to **Drive next stage**, starting at the stage after `intake` in
`.ai/route-progress.txt`.

### Resume: re-evaluate stage conditions

1. Read `last_stage`, `total`, `mode`, `questions_used` and `skipped` from `check-run-state.sh`'s
   `status: resume` output.
2. Re-evaluate the conditions against the fact record already on disk (it was never deleted — only
   `run-state.json` and the marker are removed on a terminal state), exactly as in **Skipped
   stages** above, rewriting both `.ai/run-context/stage-conditions.txt` and
   `.ai/route-progress.txt`.

Go to **Stage list matches?**.

### Stage list matches?

The re-evaluated result must have the same total, and the same stages skipped, as the run state
recorded. Both inputs are unchanged files — the pack's stage list and a fact record written once —
so a difference means one of them was edited underneath a run in progress. Treat that as a contract
violation and route to **failed**, naming which changed.

If it matches: `${CLAUDE_PLUGIN_ROOT}/shared/lib/write-orchestration-flag.sh
.ai/run-context/orchestrating.flag` (refresh — the same file `check-orchestration-flag.sh` would
otherwise report as absent or stale if this run had crashed instead of merely paused). Go to
**Drive next stage**, starting at the stage after `last_stage` in `.ai/route-progress.txt`.

### Drive next stage

For each stage id after your starting point, in `.ai/route-progress.txt` order, until a terminal
state is reached: go to **Stage skipped?**. This cannot run out of stages without first reaching
**delivered** — `deliver` is always the last stage of every list and never carries a condition
(`shared/pack-manifest.md`).

### Stage skipped?

**Marked `: skipped`** in `.ai/route-progress.txt` → go to **Record skipped stage**.

**Otherwise** → go to **Resolve stage adapter**.

Do not re-evaluate anything here. The conditions were evaluated once, against a fact record that is
never rewritten, so this file already says what it will say for the rest of the run.

### Record skipped stage

`write-progress-row.sh .ai/progress.md <stage> skipped`. Do not invoke it, and print no progress
line for it (`shared/progress-output.md`: a skipped stage has no envelope, so it gets no `Stage
<n>/<total>` line of its own). Go back to **Drive next stage**, at the next stage.

### Resolve stage adapter

Look up the stage's adapter skill name in the platform pack's `stages:` map. Go to **Adapter
resolvable?**.

### Adapter resolvable?

**Unresolvable** — dropped from the manifest since the route was resolved, or named but not loaded
in this session → route to **failed** (contract violation), naming the stage and which of the two
it was.

**Resolvable** → go to **Invoke adapter, capture envelope**.

### Invoke adapter, capture envelope

Invoke it (see "How a stage adapter is invoked" above). Capture its envelope to
`.ai/run-context/envelope-<stage id>.txt`. Go to **Validate envelope**.

### Validate envelope

`run-stage.sh <platform pack.yaml> <stage id> .ai/run-context/envelope-<stage id>.txt` → go to
**Envelope decision?**.

### Envelope decision?

**`continue` / `continue-warn`** → go to **Record stage, refresh flag**.

**`question`** → go to **Handle question**.

**`terminate-failed` / `terminate-contract-violation`** → route to **failed**.

### Record stage, refresh flag

- `print-progress-line.sh .ai/route-progress.txt <stage> <verdict> <summary>` — read the new
  `<total>` from its output.
- `write-run-state.sh .ai/run-state.json <pack name> stage-list <stage> <total> <mode> <questions_used> <start_time> .ai/run-context/stage-conditions.txt`
- `write-progress-row.sh .ai/progress.md <stage> done`
- `write-orchestration-flag.sh .ai/run-context/orchestrating.flag` (refresh)

Go to **Stage is deliver?**.

### Stage is deliver?

If `<stage>` is `deliver`: route to **delivered** — `deliver` is the last stage of every route
(core contract §4); there is no next stage to advance to.

Otherwise, go back to **Drive next stage**, at the next stage.

### Handle question

```
${CLAUDE_PLUGIN_ROOT}/shared/lib/handle-question.sh <platform pack.yaml> <mode> <stage> \
  .ai/run-context/envelope-<stage id>.txt <questions_used> <questions_cap>
```

Go to **Question decision?**.

### Question decision?

**`ask`** → go to **Ask human, record answer**.

**`terminate-blocked`** → route to **blocked**. In autonomous mode the script's own
`write-blocker:` line is what to post through the `tracker` role's `post_note` operation before
reporting; that call belongs here, at this boundary, never inside a stage.

**`terminate-failed`** (the always-autonomous override) → route to **failed**.

### Ask human, record answer

Put the reported `question` (and `options`, if any) to the human with `AskUserQuestion`. Write the
answer: `write-question-answer.sh .ai/run-context/question-answer.yaml "<question>" "<answer>"`.
Go to **Record stage, refresh flag** — the questions-used counter this script reported is already
incremented, and the answer's path is included among the next stage's inputs. This is not a
terminal state.

### blocked

1. `finalize-orchestration-flag.sh .ai/run-context/orchestrating.flag` — the marker is absent
   after every terminal state alike.
2. `${CLAUDE_PLUGIN_ROOT}/shared/lib/resolve-terminal-state.sh blocked <missing> <recorded-at>`
   (`shared/terminal-states.md`) and report its output verbatim. `run-state.json` is **not**
   deleted — left in place for a human to inspect (`shared/run-state.md`).

### failed

1. `finalize-orchestration-flag.sh .ai/run-context/orchestrating.flag` — the marker is absent
   after every terminal state alike.
2. `${CLAUDE_PLUGIN_ROOT}/shared/lib/resolve-terminal-state.sh failed <stage-id> <summary>`
   (`shared/terminal-states.md`) and report its output verbatim. `run-state.json` is **not**
   deleted — left in place for a human to inspect (`shared/run-state.md`).

### delivered

1. `finalize-run-state.sh .ai/run-state.json` (deletes it — the only terminal state that does).
2. `finalize-orchestration-flag.sh .ai/run-context/orchestrating.flag`.
3. `${CLAUDE_PLUGIN_ROOT}/shared/lib/resolve-terminal-state.sh delivered <progress-file>
   <published-location>` (`shared/terminal-states.md`) and report its output verbatim. For
   `<published-location>`, use `deliver`'s own envelope `summary` verbatim — the envelope contract
   gives the driver no separate "published location" field, so the `deliver` stage's one-sentence
   summary is what this skill reports rather than inventing a second channel. **Do not call
   `print-status-table.sh` yourself here** — `resolve-terminal-state.sh` already renders the status
   table internally for `delivered`; calling it again would print the table twice, which
   `shared/progress-output.md` forbids.

## Anti-patterns

- Spawning the next stage before this one's envelope has been captured and branched on.
- Reading a source file, or a path an envelope's `artifacts:` lists, in this skill's own turn — that
  is a stage's job, inside its own isolated subagent (the read hook above logs, but does not block,
  a lapse here).
- Retrying a stage that returned `fail`, with or without changed input.
- Spawning an adapter by pasting its `SKILL.md` body into a general subagent because `Skill()` did
  not resolve it, or deciding a skip from anything other than `evaluate-stage-conditions.sh`.
- Re-evaluating a stage's condition mid-run, or restating one in your own words instead of letting
  `write-run-state.sh` read the evaluator's own output.
- Calling `finalize-run-state.sh` on `blocked` or `failed` — only `delivered` deletes `run-state.json`.
- Printing `print-status-table.sh` more than once, or before the run reaches `delivered`.
- Restating any shared contract's shape here instead of referencing its file.
