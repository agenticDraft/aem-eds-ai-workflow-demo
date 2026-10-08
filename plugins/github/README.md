# github — scm provider pack

Implements the `scm` role for the `agentic-core` plugin against a GitHub repository through the
`gh` command: three operations, each a skill that runs one script and returns the script's stdout
unchanged.

**`verdict` reports whether the operation could read or act; it never judges the change
itself.** A pull request with a failing check is still `pass` for `check_status`.

## The problem it solves

A delivery route needs a working branch before it writes anything, a pull request when it is
done, and a way to learn whether that pull request is open, merged or closed. The core names
those three operations and nothing about where the repository lives; this pack binds them to a
GitHub remote.

## How it handles it

1. **One script per operation.** Each `skills/<name>/SKILL.md` runs
   `${CLAUDE_PLUGIN_ROOT}/skills/<name>/scripts/<name>.sh` and outputs its stdout as the whole
   response. The output ends with the `## Result` block the core's `shared/result-envelope.md`
   defines.
2. **Authentication is the machine's, not the pack's.** Every skill requires `gh` to be
   authenticated on the machine (`gh auth status`); no token is read or stored here. With nobody
   logged in — a CI runner — that authentication is the environment variable `GH_TOKEN`, which
   `gh` reads in place of a stored login, plus `gh auth setup-git` run once so `git push` goes
   through the same token. A fine-grained personal access token scoped to the one repository
   covers every operation here with: Contents read and write (branches and tags are pushed),
   Pull requests read and write (`publish_change`, `check_status`), Commit statuses read and
   Actions read (`check_status`). Not the workflow's own token: an event it creates starts no
   workflow run, so a change it opened would carry no checks for `check_status` to read.
3. **`create_branch` ensures rather than creates.** An existing branch is reported, not refused,
   with `metrics` naming what happened: `branch_action=existing`, `switched` or `created`. A new
   branch bases on `origin/<default>` when the caller is on the default branch, on the current
   `HEAD` anywhere else, and on `origin/<base>` when `base` is given.
4. **One case is a question, not an action.** An existing branch that does not contain the
   caller's current `HEAD` cannot be checked out without losing commits; the envelope reports
   `verdict: question` naming how many would be lost, and nothing moves.
5. **`check_status` derives its answer from the payload, not the exit code.** The state of the
   pull request is reported as `change_state: open | merged | closed | none`. A lookup that failed
   carries no `change_state` at all, so an unknown state never reads as "no pull request".
6. **The scripts run outside the default command sandbox.** Each `SKILL.md` instructs the caller
   to run its script with the sandbox disabled on the first attempt; the reason is stated in the
   skill text.

## The flow

```text
stage adapter (a platform pack skill)
  │  Skill(github:create-branch)   branch: <name> [base: <name>]
  ↓  ... implement, verify, lint ...
  │  Skill(github:publish-change)  branch, title, body [, base]
  ↓
  │  Skill(github:check-status)    branch: <name>
  ↓
check-status.sh
  ├── no pull request      → pass, change_state: none, no checks
  ├── pull request found   → pass, change_state: open|merged|closed,
  │                           checks counted in summary and metrics
  └── lookup failed        → fail, no change_state line
  ↓
stdout, unchanged, is the skill's entire response
```

`publish_change` pushes the current branch and opens a pull request, or reuses the one already
open for it.

## Operations

| Operation        | Skill            | Input lines                                   |
| ---------------- | ---------------- | --------------------------------------------- |
| `create_branch`  | `create-branch`  | `branch`, optional `base`                     |
| `publish_change` | `publish-change` | `branch`, `title`, `body`, optional `base`    |
| `check_status`   | `check-status`   | `branch`                                      |

`pack.yaml` maps each operation to its skill, declares `unsupported: []`, and names
`skills/check-status/scripts/check-status.sh` under `scripts:` so a caller that needs the state
of a change without a model step can run it directly.

## What it looks like

**Manifest validation, this run:**

```text
$ claude plugin validate plugins/github
Validating plugin manifest: .../plugins/github/.claude-plugin/plugin.json

✔ Validation passed
```

**Pack manifest check by the core, this run:**

```text
$ bash plugins/github/core/lib/validate-pack-manifest.sh plugins/github/pack.yaml
valid: provider
```

**A usage error, this run:**

```text
$ bash plugins/github/skills/check-status/scripts/check-status.sh
usage: check-status.sh <branch-name>
```

Exit status 2. Every operational outcome, by contrast, exits 0 with an envelope.

**The offline test suites, this run:**

```text
$ bash plugins/github/skills/check-status/scripts/check-status.test.sh
...
=== 43 passed, 0 failed ===
$ bash plugins/github/skills/create-branch/scripts/create-branch.test.sh
...
=== 13 passed, 0 failed ===
```

## Running it yourself

1. Authenticate `gh` on the machine and confirm it: `gh auth status`. Headless: export
   `GH_TOKEN` instead (see *How it handles it*, point 2).
2. Load the pack next to the core, from the directory that holds `plugins/`:

   ```text
   claude --plugin-dir ./plugins/agentic-core --plugin-dir ./plugins/github
   ```

   This pack declares `"dependencies": ["agentic-core"]` in `.claude-plugin/plugin.json`.
3. Validate after any edit, and reload without restarting:

   ```text
   claude plugin validate plugins/github
   /reload-plugins
   ```
4. Invoke an operation. A stage adapter does it as `Skill(github:check-status)` with the input
   lines as the argument; from a prompt, `/github:check-status` followed by `branch: <name>`.
5. Run the offline tests:

   ```text
   bash plugins/github/skills/check-status/scripts/check-status.test.sh
   bash plugins/github/skills/create-branch/scripts/create-branch.test.sh
   ```

To make this pack the project's scm, set `packs.scm: github` in `.ai/project-config.yaml`.

## Limits you should know

- **Every operation needs the network and an authenticated `gh`.** Nothing in this README was
  produced by a live call.
- **`publish-change` has no offline test.** Two of the three scripts have one; the tests fake the
  `gh` command, so they cover the script's own branching, not the remote.
- **`create_branch` checks the working tree out.** It moves the caller onto the branch it ensured;
  a caller that was on another branch with unmerged work is expected to be there on purpose.
- **A check that fails does not fail the operation.** Read `summary` and `metrics` for the
  per-check outcome; `verdict` only says the checks could be retrieved.

## Design rules this pack follows

A provider operation reports what it could observe and leaves judgment to the adapter that asked.
That is why `check_status` separates `verdict` from `change_state` and from the check counts:
three questions, three fields, none collapsed into another.

This pack applies the rule to the one role that changes a repository. Where acting would discard
work, it asks instead of acting, and where a lookup did not succeed it says nothing about the
state rather than guessing one.

---

agenticDraft

License: not declared in `.claude-plugin/plugin.json`. No `NOTICE` ships with this pack.
