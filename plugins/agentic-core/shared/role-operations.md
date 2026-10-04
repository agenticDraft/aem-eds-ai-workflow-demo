---
description: How a stage adapter calls another pack's role operation — always as that operation's skill, never by running the pack's script itself — and how a transcript proves it did. Every stage that reaches a provider pack references this file rather than restating the rule inline.
---

# Calling a role operation

A stage reaches another pack only through the operations that pack declares in its manifest, each
invoked as a skill: `Skill(<pack>:<operation skill name>)` with the operation's input lines. The
operation's script path is the pack's layout, not its contract.

Invoking the operation injects its instructions into the stage, and the command those instructions
name — the operation's own script, with whatever sandbox grant the operation declares for it — is
then the stage's to run exactly as written, once per invocation. That is the whole of the stage's
part: input lines in, the operation's `## Result` block out.

**Never does:** run a provider pack's script on its own account. A script run without the
operation's instructions skips the pack's preconditions, its sandbox handling and the envelope it
promises; the files it writes look the same, so nothing downstream can tell. An operation that
returns `fail` is the stage's input, reported as the stage's own finding under the node that
handles a failed call, never worked around by running the script directly. A script path a stage
hands to a core script as an argument (a reachability check given the render script's path) is not
a call and is not covered here.

## Anti-patterns

- Running `plugins/<pack>/skills/<skill>/scripts/<file>` for an operation whose skill the stage did
  not just invoke — including after that operation returned `fail`.
- Invoking an operation once and running its script for every later call "because it is the same
  script".
- Reading an operation's script to learn its arguments instead of giving the operation its input
  lines.

## Reference, not restatement

A stage adapter that calls a role operation references this file with one line rather than
restating the rule inline, the same convention `stage-runner.md` and `result-envelope.md` use for
their own contracts.

## Verification

`lib/check-direct-script-calls.sh <own pack> <transcript.jsonl> [...]` reads a stage adapter's
transcript (one JSON object per line, as the runtime writes it for every subagent) and names every
command that executed another pack's `skills/<skill>/scripts/` file when the most recent skill
invocation before it was not that operation's. It prints `ok: no provider script run directly
(<n> commands read)` and exits `0`, or one `direct TAB <pack>/<skill> TAB <transcript> TAB <command>`
line per call and `invalid: <n> provider script(s) run directly`, exit `1`; `2` for a usage error.
A run's live check passes the stage's pack name and the transcripts of the stages that call
provider operations.

```bash
bash plugins/agentic-core/shared/lib/check-direct-script-calls.test.sh
```
