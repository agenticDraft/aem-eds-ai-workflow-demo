---
description: The lint stage (core contract §4) — always runs, up to three attempts. Runs the project's configured lint command, edits what it flags when it fails, and re-runs it, before giving up and reporting what remains. Normalises the lint command's own output into this platform's own finding, never returns its raw output unchanged.
context: fork
---

# eds-lint

This stage always runs. It has no `tracker`/`scm`/`design`/`browser` role dependency — it runs the
project's configured lint command against this checkout and, if that command fails, edits the
files it names and tries again, up to three attempts before giving up and reporting what remains.

Read `../../../agentic-core/shared/project-config.md` for the shape referenced in **Read the
configured lint command**, `../../../agentic-core/shared/publish-criteria.md`'s "The change,
minimally" section for how this stage resolves the same merge-base diff `publish-gate` reviews
later, and `../../../agentic-core/shared/result-envelope.md` for the `## Result` block this stage
must end with.

## Input

None directly. This stage reads `.ai/project-config.yaml`'s `commands.lint` at its fixed path —
one whole-project command, not scoped to any particular file or block, so its own output routinely
names files nothing in this run touched: pre-existing issues elsewhere in the project. This stage
does not receive a file list from `implement` directly — the runner never forwards one stage's
artifacts to another (`stage-runner.md`) — but it does resolve, itself, the same merge-base diff
`publish-gate` reviews later (**Resolve this run's own changed files**, below), so it can tell its
own change's issues apart from the project's pre-existing debt without waiting for `publish-gate`
to be the one to notice.

## Flow

```dot
digraph eds_lint {
    "Read the configured lint command" [shape=box];
    "Lint command configured?" [shape=diamond];
    "Resolve this run's own changed files" [shape=box];
    "Run the lint command" [shape=box];
    "Lint command exited zero?" [shape=diamond];
    "Any in-scope issues reported?" [shape=diamond];
    "Attempts exhausted or no improvement?" [shape=diamond];
    "Edit the in-scope files the output names" [shape=box];
    "Report fail" [shape=doublecircle];
    "Report pass" [shape=doublecircle];

    "Read the configured lint command" -> "Lint command configured?";
    "Lint command configured?" -> "Resolve this run's own changed files" [label="non-empty"];
    "Lint command configured?" -> "Report fail" [label="empty"];
    "Resolve this run's own changed files" -> "Run the lint command";
    "Run the lint command" -> "Lint command exited zero?";
    "Lint command exited zero?" -> "Report pass" [label="yes"];
    "Lint command exited zero?" -> "Any in-scope issues reported?" [label="no"];
    "Any in-scope issues reported?" -> "Report pass" [label="no — only pre-existing, out of scope"];
    "Any in-scope issues reported?" -> "Attempts exhausted or no improvement?" [label="yes"];
    "Attempts exhausted or no improvement?" -> "Report fail" [label="yes"];
    "Attempts exhausted or no improvement?" -> "Edit the in-scope files the output names" [label="no"];
    "Edit the in-scope files the output names" -> "Run the lint command";
}
```

## Node Details

### Read the configured lint command

Read `.ai/project-config.yaml`'s `commands.lint` value.

### Lint command configured?

Non-empty — continue to **Resolve this run's own changed files**. Empty string — go to
**Report fail**: this is a configuration gap pre-flight should already have caught, and this stage
has nothing to run without it.

### Resolve this run's own changed files

Resolve the project root's changed-file set exactly the way `publish-criteria.md`'s "The change,
minimally" section defines it — the same diff `publish-gate` reviews later, computed here first so
this stage's own edits never grow it:

```
BASE=$(git symbolic-ref refs/remotes/origin/HEAD)
MERGE_BASE=$(git merge-base "${BASE#refs/remotes/}" HEAD)
git diff "$MERGE_BASE" --name-only
```

Record this file list — call it the in-scope set for the rest of this stage. It is resolved once,
before attempt 1, and does not change between attempts: every file this stage itself might go on to
edit is a file the lint command's own output names, and every such edit only ever happens inside
this set (see **Edit the in-scope files the output names**, below) — nothing this stage does can add
a new file to it. This is attempt 1 — continue to **Run the lint command**.

### Run the lint command

Run the configured command exactly as written. Record its exit code and its combined output
(stdout and stderr) in full — this attempt's output, kept only long enough to compare against the
next attempt's, and to write into the report if this stage ends in **Report fail**.

### Lint command exited zero?

A zero exit — continue to **Report pass**, regardless of what the command printed: a lint command
may print warnings on a run it still considers passing, and the exit code is the signal its own
configuration already uses to mean pass or fail, not the presence of any output. A non-zero exit —
continue to **Any in-scope issues reported?**.

### Any in-scope issues reported?

Read this attempt's output and identify the files it reports issues in. Any of those files appear
in the in-scope set resolved earlier — continue to **Attempts exhausted or no improvement?**. None
of them do (every reported file is outside the in-scope set) — go to **Report pass**: every
remaining issue predates this run's own change and belongs to no step in `plan.yaml`, the same test
`publish-gate` will apply to this stage's own edits later. Forcing this stage to either fail over
debt it has no standing to fix, or fix it anyway and hand `publish-gate` a diff wider than the plan,
would both be worse than reporting the project's pre-existing lint state plainly and moving on —
**Report pass**, below, names what was left alone rather than silently treating it as clean.

### Attempts exhausted or no improvement?

Either of the following — go to **Report fail**:

- This was the third run of the command.
- This run's combined output is identical to the immediately preceding run's — nothing changed, so
  another attempt would only repeat it.

Neither — continue to **Edit the in-scope files the output names**.

### Edit the in-scope files the output names

Read this attempt's output and, from it alone, identify the files and issues it reports. Edit only
the files that are both named by the output and present in the in-scope set resolved earlier —
nothing else: no file the output did not name, and no file outside this run's own change even when
the output names it (that file's issues are pre-existing debt, handled by **Any in-scope issues
reported?** above, not by editing it). Then return to **Run the lint command** for the next
attempt.

### Report fail

Emit the `## Result` block as plain `key: value` lines per `../../../agentic-core/shared/result-envelope.md` — never as a bulleted or backtick-wrapped list. Fields:

- `verdict: fail`
- `summary`: one sentence, 200 characters or fewer (the envelope's hard cap — an oversized summary fails validation and takes the whole run to `failed`) — either that no lint command is configured, or that lint attempts were
  exhausted (naming the attempt count) or stopped for lack of improvement, plus how many issues
  remain per the last run. Never the command's raw output verbatim.
- `artifacts`: empty when no lint command was configured. Otherwise, every file edited across all
  attempts, plus `.ai/run-context/lint-report.md` — written with the last attempt's full combined
  output, the attempt count, and which of the two stop conditions above applied.
- `next_action: none`

### Report pass

Reached from **Any in-scope issues reported?** (every remaining issue out of scope) rather than
from a literal zero exit — write `.ai/run-context/lint-report.md` first, naming exactly which
files/issues remain and that each is outside the in-scope set resolved earlier, i.e. pre-existing
and not introduced or touched by this run. Never omitted and never folded silently into a clean
pass, the same convention other stages use for their own downgrade cases.

Emit the `## Result` block as plain `key: value` lines per `../../../agentic-core/shared/result-envelope.md` — never as a bulleted or backtick-wrapped list. Fields:

- `verdict: pass`
- `summary`: one sentence, 200 characters or fewer (the envelope's hard cap — an oversized summary fails validation and takes the whole run to `failed`) naming how many attempts it took to exit
  zero, or, when reached with pre-existing issues left in place, how many remain and that they are
  out of scope.
- `artifacts`: every file edited across any earlier attempts, plus `.ai/run-context/lint-report.md`
  when reached with pre-existing issues left in place — both empty if it passed on the first
  attempt with nothing to report.
- `next_action: none`
