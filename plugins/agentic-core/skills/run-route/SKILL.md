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
  (`shared/progress-output.md`) — one stage id per line, in route order, a skipped stage written
  as `<stage-id>: skipped`
- `.ai/logs/run-route-reads.log` — the read-hook's log (see frontmatter above)

**`.ai/run-context/` — crosses the driver↔stage boundary. A stage adapter reads these as its own
input.**
- `.ai/run-context/orchestrating.flag` — the orchestration marker (`shared/orchestration-flag.md`)
- `.ai/run-context/fact-record.yaml` — the fact record `intake` emits (`shared/fact-record.md`)
- `.ai/run-context/route.yaml` — the resolved route: `route: <id>`, `stages: [...]`, `rule: <...>`,
  written once right after route resolution, never rewritten
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
stage adapter this session cannot resolve, exactly like a stage id the manifest dropped. Go to
**step 3** with `failed`, and say which pack was not loaded, so the fix is obvious.

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
route: .ai/run-context/route.yaml
question_answer: .ai/run-context/question-answer.yaml   # only when the previous stage asked one
```

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

## 0. Pre-flight, before anything else exists

Resolve each role's pack path from `.ai/project-config.yaml`'s `packs:` map
(`.ai/packs/<pack name>/pack.yaml`), then run:

```
${CLAUDE_PLUGIN_ROOT}/shared/lib/check-preflight.sh .ai/project-config.yaml \
  platform=<path> tracker=<path> scm=<path> browser=<path> [design=<path>]
```

If it exits non-zero: no branch, run state, or marker exists yet, so there is nothing to finalize.
Report `terminal: blocked` immediately, naming exactly what pre-flight's `invalid: <reason>` says is
missing and that it was never recorded anywhere (core contract §4 — pre-flight failure is one of
`shared/terminal-states.md`'s `blocked` causes). Stop; do not proceed to step 1.

If it passes, continue.

## 1. Resume or start fresh

Run `${CLAUDE_PLUGIN_ROOT}/shared/lib/check-run-state.sh .ai/run-state.json`.

- **`status: resume`** — a previous run exists inside the 2-hour window. Ask, with
  `AskUserQuestion`: *"Previous run found at stage {last_stage}/{total} — resume or start fresh?"*
  using the fields the check reported.
  - **resume** — go to **1b**.
  - **start fresh** — treat exactly as `status: none` below, and go to **1a**. (Nothing deletes the
    old `run-state.json` for you here; overwrite it in 1a the same way a fresh run always does.)
- **`status: stale-deleted`** — the file was 2 hours old or older and is already removed. Note this
  plainly in your report, then go to **1a**.
- **`status: none`** — go to **1a**.

### 1a. Fresh start

1. `${CLAUDE_PLUGIN_ROOT}/shared/lib/write-orchestration-flag.sh .ai/run-context/orchestrating.flag`
2. Invoke the `intake` stage adapter (see "How a stage adapter is invoked" — `intake` needs no
   `fact_record`/`route` input yet, since it is what produces the fact record). Capture its
   envelope to `.ai/run-context/envelope-intake.txt`.
3. `${CLAUDE_PLUGIN_ROOT}/shared/lib/run-stage.sh <platform pack.yaml> intake .ai/run-context/envelope-intake.txt`
   → a decision. `terminate-failed` or `terminate-contract-violation` here means core contract §4's
   guarantee already held — no branch, file, or route exists — so go straight to **step 3** with
   `failed`, after removing the marker you just wrote
   (`finalize-orchestration-flag.sh .ai/run-context/orchestrating.flag`); no run state was ever
   written, so there is nothing else to finalize.
4. On `continue`/`continue-warn`: `intake`'s envelope must list the fact record among its
   `artifacts:` at `.ai/run-context/fact-record.yaml` (`shared/fact-record.md`). Resolve the route:
   ```
   ${CLAUDE_PLUGIN_ROOT}/shared/lib/resolve-route.sh .ai/project-config.yaml .ai/run-context/fact-record.yaml
   ```
   Write `.ai/run-context/route.yaml` with the three reported fields (`route`, `stages`, `rule`),
   and write `.ai/route-progress.txt` with one bare stage id per line, in that order. Then apply
   the platform pack's declared skip conditions to it — see **Skipped stages** below.
5. `${CLAUDE_PLUGIN_ROOT}/shared/lib/print-progress-line.sh .ai/route-progress.txt intake <verdict> <summary>`
   — read `<total>` from its own output line; do not recompute it separately.
6. `${CLAUDE_PLUGIN_ROOT}/shared/lib/write-run-state.sh .ai/run-state.json <route id> <rule> intake <total> <mode> 0 <now>`,
   where `<now>` is the output of `date -u +%Y-%m-%dT%H:%M:%SZ` — call it once, right here, and use
   the same value in every later `write-run-state.sh` call this run (`start_time` is set once and
   never rewritten, per `shared/run-state.md`). Do not stash it in a file of your own; it is one
   short value to carry forward in your own working memory for the rest of the run.
7. `${CLAUDE_PLUGIN_ROOT}/shared/lib/write-progress-row.sh .ai/progress.md intake done`
8. `${CLAUDE_PLUGIN_ROOT}/shared/lib/write-orchestration-flag.sh .ai/run-context/orchestrating.flag`
   (refresh)
9. If `intake` returned `verdict: question`, handle it exactly as step 2 describes for any other
   stage, with `intake` as the asking stage. Otherwise go to **step 2**, starting at the stage after
   `intake` in `.ai/route-progress.txt`.

### 1b. Resume

1. Read `route_id`, `rule`, `last_stage`, `mode`, `questions_used` from `check-run-state.sh`'s
   `status: resume` output.
2. Re-derive the stage list from the fact record already on disk (it was never deleted — only
   `run-state.json` and the marker are removed on a terminal state):
   ```
   ${CLAUDE_PLUGIN_ROOT}/shared/lib/resolve-route.sh .ai/project-config.yaml .ai/run-context/fact-record.yaml
   ```
   This must report the same `route_id`; if it does not, treat it as a contract violation (project
   config or the fact record changed underneath a run in progress) and go to step 3 with `failed`.
3. Rewrite `.ai/route-progress.txt` from this stage list, then apply the skip conditions to it
   afresh — see **Skipped stages** below. Nothing about a skip needs to survive the interruption:
   the conditions are evaluated from what is on disk right now, so the rebuilt file is correct by
   construction, including for a stage whose precondition appeared between the interruption and the
   resume.
4. `${CLAUDE_PLUGIN_ROOT}/shared/lib/write-orchestration-flag.sh .ai/run-context/orchestrating.flag`
   (refresh — the same file `check-orchestration-flag.sh` would otherwise report as absent or
   stale if this run had crashed instead of merely paused).
5. Go to **step 2**, starting at the stage after `last_stage` in `.ai/route-progress.txt`.

## 2. Drive the remaining stages

For each stage id after your starting point, in `.ai/route-progress.txt` order, until a terminal
state is reached. **Re-apply the skip conditions at the top of every iteration** (see **Skipped
stages** below) — an earlier stage may have just written the file a later stage was waiting on, and
that stage must un-skip before you reach it.

- **Marked `: skipped`** after that re-evaluation:
  `write-progress-row.sh .ai/progress.md <stage> skipped`. Do not invoke it, and print no progress
  line for it (`shared/progress-output.md`: a skipped stage has no envelope, so it gets no
  `Stage <n>/<total>` line of its own). Move to the next stage.
- **Otherwise:**
  1. Look up the stage's adapter skill name in the platform pack's `stages:` map. Unresolvable —
     dropped from the manifest since the route was resolved, or named but not loaded in this
     session → go to step 3 with `failed` (contract violation), naming the stage and which of the
     two it was.
  2. Invoke it (see "How a stage adapter is invoked"). Capture its envelope to
     `.ai/run-context/envelope-<stage id>.txt`.
  3. `run-stage.sh <platform pack.yaml> <stage id> .ai/run-context/envelope-<stage id>.txt` → a
     decision.
  4. **`continue` / `continue-warn`:**
     - `print-progress-line.sh .ai/route-progress.txt <stage> <verdict> <summary>` — read the new
       `<total>` from its output.
     - `write-run-state.sh .ai/run-state.json <route id> <rule> <stage> <total> <mode> <questions_used> <start_time>`
     - `write-progress-row.sh .ai/progress.md <stage> done`
     - `write-orchestration-flag.sh .ai/run-context/orchestrating.flag` (refresh)
     - If `<stage>` is `deliver`: go to **step 3** with `delivered` — `deliver` is the last stage of
       every route (core contract §4); there is no next stage to advance to.
     - Otherwise, continue the loop at the next stage.
  5. **`question`:**
     ```
     ${CLAUDE_PLUGIN_ROOT}/shared/lib/handle-question.sh <platform pack.yaml> <mode> <stage> \
       .ai/run-context/envelope-<stage id>.txt <questions_used> <questions_cap>
     ```
     - `ask` — put the reported `question` (and `options`, if any) to the human with
       `AskUserQuestion`. Write the answer:
       `write-question-answer.sh .ai/run-context/question-answer.yaml "<question>" "<answer>"`.
       Update run state and progress exactly as the `continue` case above (the questions-used
       counter this script reported is already incremented), then continue the loop at the next
       stage — the answer's path is included among that stage's inputs. This is not a terminal
       state.
     - `terminate-blocked` — go to step 3 with `blocked`. In autonomous mode the script's own
       `write-blocker:` line is what to post through the `tracker` role's `post_note` operation
       before reporting; that call belongs here, at this boundary, never inside a stage.
     - `terminate-failed` (the always-autonomous override) — go to step 3 with `failed`.
  6. **`terminate-failed` / `terminate-contract-violation`:** go to step 3 with `failed`.

### Skipped stages

A skip is declared by the **pack**, not by a running stage: the platform manifest's optional
`skip_when_missing:` map names, per stage, one path whose absence means that stage has nothing to
do on this run (`shared/pack-manifest.md`). You never decide a skip yourself, and you never read a
skip out of an envelope — `shared/result-envelope.md` is explicit that `next_action` is a name, not
a directive to you.

To apply the conditions, run:

```
${CLAUDE_PLUGIN_ROOT}/shared/lib/evaluate-skip-conditions.sh <platform pack.yaml> .
```

It prints one `skipped: <stage id>` line per skipped stage, and nothing when none is. Rewrite
`.ai/route-progress.txt` so that exactly those stage ids read `<stage id>: skipped` and every other
line is a bare stage id — **exactly those**, because a stage skipped a moment ago un-skips the
instant its path appears, and the file has to say so. Do this before printing any further progress
line, so the very next line already reflects the current total.

Nothing here is remembered between calls, and that is the point: the skip state is a function of
what is on disk, recomputed whenever you need it, which is why an interrupted run can rebuild it
from scratch and why `shared/progress-output.md` forbids caching a `<total>` across a skip.

## 3. Terminal state

1. **Only on `delivered`:** `finalize-run-state.sh .ai/run-state.json` (deletes it — `blocked` and
   `failed` leave it in place for a human to inspect, per `shared/run-state.md`; do not call this on
   those two).
2. **On all three:** `finalize-orchestration-flag.sh .ai/run-context/orchestrating.flag` — the
   marker is absent after every terminal state alike, including the failing ones
   (`shared/orchestration-flag.md`).
3. `${CLAUDE_PLUGIN_ROOT}/shared/lib/resolve-terminal-state.sh <delivered|blocked|failed> <state-specific args>`
   (`shared/terminal-states.md`) and report its output verbatim. **Do not call `print-status-table.sh`
   yourself here** — for `delivered`, `resolve-terminal-state.sh` already renders the status table
   internally as part of its own output; calling it again would print the table twice, which
   `shared/progress-output.md` forbids. `blocked` and `failed` carry their own required output
   instead (what is missing and where it was recorded; the failing stage and its summary) and do
   not render the table at all.
   - `delivered <progress-file> <published-location>` — for `<published-location>`, use `deliver`'s
     own envelope `summary` verbatim. The envelope contract gives the driver no separate
     "published location" field; the `deliver` stage's one-sentence summary is the only thing every
     `deliver` adapter is already required to produce, so it is what this skill reports rather than
     inventing a second channel.
   - `blocked <missing> <recorded-at>` / `failed <stage-id> <summary>` — as already gathered in
     step 2's handling of that outcome.

## Anti-patterns

- Spawning the next stage before this one's envelope has been captured and branched on.
- Reading a source file, or a path an envelope's `artifacts:` lists, in this skill's own turn — that
  is a stage's job, inside its own isolated subagent (the read hook above logs, but does not block,
  a lapse here).
- Retrying a stage that returned `fail`, with or without changed input.
- Spawning an adapter by pasting its `SKILL.md` body into a general subagent because `Skill()` did
  not resolve it, or deciding a skip from anything other than `evaluate-skip-conditions.sh`.
- Calling `finalize-run-state.sh` on `blocked` or `failed` — only `delivered` deletes `run-state.json`.
- Printing `print-status-table.sh` more than once, or before step 3.
- Restating any shared contract's shape here instead of referencing its file.
