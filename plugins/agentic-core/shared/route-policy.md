---
description: The route policy — the second rail an unattended route needs beside its allow rules. Its file shape, the fail-closed rule, the forbidden-rule grammar, how daily run limits are counted from the claims, break-glass, and the exit codes that name each cap. Every reader validates against this file and reads the policy only through check-route-policy.sh.
---

# Route policy

An unattended route runs only under a committed policy that bounds it: tool rules it may never
run, how many runs may start per day, how much one run may spend, how long it may take, and who
may deliberately start one run over the daily limit.

**Never does:** hold a credential, name a product, or fall back to a default. A value nobody wrote
cannot let a run through.

## Location

`.ai/route-policy.yaml` at the project root. Committed, and changed only through a reviewed
change. The project owns the values; this file owns the shape. It is not part of the project
config, so a broken policy stops unattended runs and nothing else.

## Shape

```yaml
version: 1

forbidden:                       # one or more tool rules; deny beats allow
  - "Bash(<command pattern>)"
  - "<Tool>"

limits:
  runs_per_identity_per_day: <positive whole number>
  runs_per_day: <positive whole number>

budget:
  max_usd_per_run: <positive number>

caps:
  max_turns: <positive whole number>
  timeout_minutes: <positive number>

break_glass:
  word: "<one lower-case word>"
  approvers:                     # one or more opaque identity handles
    - "<identity>"
```

Full-line comments and comments after a value are allowed. Nothing else is.

## Fail-closed

`shared/lib/check-route-policy.sh <path>` is the only reader. It refuses (exit `1`,
`invalid: <reason>`) a missing or unreadable file, a version other than `1`, an unknown or repeated
key, a missing value, a number that is not positive, an empty `forbidden` list (refused rather than
read as "nothing is forbidden"), and an empty `approvers` list. On success it prints the policy
normalized, one `key=value` per line, and callers read that output, never the file.

## Forbidden rules

The allow-rule grammar:

- `Tool` — every call of that tool.
- `Tool(pattern)` — a call whose primary argument matches `pattern`, anchored, where `*` is any run
  of characters and every other character is literal. The primary argument is the command for a
  shell call, the file path for a file tool, the URL for a fetch, the pattern for a search.

A shell command is matched after runs of whitespace are collapsed. A compound command is split on
`&&`, `||`, `;`, `|` and newlines, and each part is matched on its own, as is the whole.

A rule is a prefix rule only where it ends in `*`. `git push * main*` would also refuse a branch
named `mainline`, so a rule about one name states it exactly (`git push * main`) and again with
what may follow it (`git push * main *`).

The runner enforces the list twice: as the SDK's own deny list, and in a `PreToolUse` hook that
sees every call, a forked stage's included, and refuses a match with the reason
`forbidden by route policy (<path>): <rule>`.

**Limit, stated:** a rule matches what the call says, not what it eventually executes. A command
wrapped in another interpreter's string is not unwrapped. A command a script runs is not seen at
all, and a push that does not name its branch matches no rule about that branch. So a forbidden rule
is never the only guard against pushing the default branch: the `scm` operations refuse it
themselves, and a policy also forbids the forms that push the current branch without naming it
(`git push`, `git push origin`, `git push * HEAD`).

## Daily limits

Counted by `shared/lib/check-run-limits.sh <policy> <identity> <override>` from the claims already
on the remote (`shared/lib/claim-run.sh`). Each claim's message carries `at:` (UTC time) and
`by:` (the identity that started the event). Today is the current UTC date. A claim with no `by:`
line counts toward the day and toward no identity.

- Run it **before** the claim. A refused event then leaves no claim and counts against nobody.
- `limited identity <n>/<limit>` or `limited day <n>/<limit>` (exit `4`) is a correct outcome, not
  a failure: the caller ends green and starts nothing.
- A remote whose claims cannot be read is exit `1`. The caller stops and starts nothing.
- **Soft under concurrency:** two callers counting at the same moment can both see room for one
  more run.

## Break-glass

An identity on `break_glass.approvers` starts an event whose trigger carries `override` = `1`.
How a tracker sets that field without carrying the comment text is the trigger contract's
business: the comment contains the trigger token followed by `break_glass.word`.

- It lifts **the daily limits only**, for that one event. The forbidden list, the budget and the
  caps are never lifted.
- An override from an identity not on the list is ignored, said so, and the limits apply.
- The claim records `override: 1`.

## The runner's caps and exit codes

`shared/runner/route-agent.mjs` reads the policy before anything starts (`ROUTE_POLICY_FILE`,
default `.ai/route-policy.yaml`), passes `budget.max_usd_per_run` as the SDK's budget, and takes
each cap from the policy. A cap variable in the environment may lower a cap, never raise it.

| exit | meaning | logged and written to the result file |
| ---- | ------- | ------------------------------------- |
| `2`  | wall-clock cap | `cap reached: timeout_minutes=<n> (route policy)` |
| `3`  | policy refused; nothing started | `policy refused: <checker's reason>` |
| `4`  | turn cap | `cap reached: max_turns=<n> (route policy)` |
| `5`  | budget cap | `cap reached: max_usd_per_run=<n> (route policy)` |

## Order, one unattended run

1. Trigger gates (shape, identity, duplicate) — see `trigger-contract.md`.
2. `check-route-policy.sh` — refusal stops the run.
3. `check-run-limits.sh` — `limited` ends the run green with no claim.
4. `claim-run.sh` with `CLAIM_BY` and `CLAIM_OVERRIDE`.
5. `route-agent.mjs` — reads the policy again and bounds the session by it.
