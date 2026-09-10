---
description: The publish gate's four criteria, written as answerable yes/no questions, plus how "the actual change" is resolved — through git, from the project root, never from a description of the change. Every reader or writer of a publish-gate outcome references this file rather than restating the criteria inline.
---

# Publish criteria

`gate-contract.md` fixes what a gate is; this file is the publish gate's own deliverable — its
four criteria, each one a question with only two possible answers. A criterion that cannot be
answered yes or no does not belong here — see `gate-contract.md`'s reject condition.

1. **Is there a change to review?**
2. **Does the change avoid every path the project marked never-tracked?**
3. **Does the change implement what the plan proposed, and nothing else?**
4. **Is the change free of anything that must not reach publication as-is?**

Criteria 1 and 2 are structural: whether the working tree differs from the merge base, and
whether any of the paths that differ match a `.gitignore` rule, are both checkable by running git
and comparing lists — no interpretation involved. Criteria 3 and 4 are not: whether the diff's
content actually satisfies what `plan.yaml` proposed, and whether anything in it should stop
publication, requires reading what changed, not just which paths changed. Per `gate-contract.md`'s
fixed order, 1 and 2 are a deterministic check that runs first; 3 and 4 are what the gate's
reviewing model answers on whatever survives.

## The change, minimally

Unlike `plan-criteria.md`, this file defines no artifact shape — there is no file called "the
change" for a stage to write and this gate to read. **The change is resolved through git,
directly, from the project root**, the same way `gate-contract.md`'s "review the actual change
rather than a description of it" is stated: reviewing a description would mean reading some
stage's summary of what it did, and a summary is exactly the kind of description this gate exists
not to trust.

- **Base** — wherever `origin/HEAD` points, resolved with `git symbolic-ref
  refs/remotes/origin/HEAD`. Not a hardcoded branch name: a project's default branch is whatever
  its remote says it is, and this is the same ref the isolated worktree itself branches from
  (`gate-contract.md`'s "Adapter hardening"), so the gate's notion of "base" and the
  worktree's actual base never disagree.
- **Review side** — the project root's current branch and its working tree, at the moment the
  gate runs — committed and uncommitted alike. `implement` writes files; nothing in this pack
  commits them before `deliver` runs `scm.publish_change`, so by the time `publish-gate` runs, the
  change under review is very often still sitting uncommitted in the working tree. A check that
  only read committed history would review nothing.
- **The diff** — `git diff <merge-base of base and review> -- ` against the project root's working
  tree, not `<base>...<review>` between two commits. The merge base, not `HEAD`, is the compare
  point specifically so uncommitted edits are included; a plain two-ref diff would stop at the last
  commit and silently miss whatever has not been committed yet.

## Resolution rules

- **Every git invocation resolves the project root through `--git-dir`/`--work-tree`, never
  through `cd`.** The gate runs in an isolated worktree (`isolation: worktree`), which shares the
  same object database and refs as the project root but has its own working tree checked out at
  the default branch, not at the branch under review. Reading refs and history works the
  same from either location, because git plumbing over `--git-dir`/`--work-tree` reads the object
  database and the given working tree, not the caller's own current directory. What would not
  work is `cd`-ing into the project root and running git there: that changes the running command's
  own working directory to a path outside the isolated checkout, which is exactly what the gate's
  isolation exists to refuse.
- **A criterion that cannot resolve — no `origin/HEAD`, no merge base, a detached `HEAD` — is not
  criterion 1 or 2 answered "no."** It is the check failing to reach a verdict at all, the same
  distinction `plan-criteria.md`'s exit `2` draws for a plan file that cannot be parsed. Collapsing
  "could not determine" into "no change" would let an environment problem masquerade as a clean
  pass, and collapsing it into "change rejected" would blame the change for an environment fact
  that has nothing to do with it.
- **`.gitignore`, not a maintained denylist.** Criterion 2 asks whether any changed path matches a
  pattern the project's own `.gitignore` already states — nothing this contract invents and
  nothing a future change to what must never be tracked requires updating in two places. This
  project's own `.gitignore` already carries the comment this criterion exists to enforce:
  "Secrets — THIS REPO IS PUBLIC. Never remove these lines," and "Delivery-automation run
  artifacts — ephemeral, instance-local, never committed." A path matching either block reaching
  the diff at all means something forced past `.gitignore` (`git add -f`, most often), which is
  precisely what this criterion catches.

## Anti-patterns

- Reading a stage's summary of its own change instead of the change itself — the distinction
  `gate-contract.md` draws between `publish-gate` and `plan-gate` collapses if this gate trusts
  prose over git.
- Diffing `<base>...<review>` (two commits) instead of `<merge-base>` against the working tree —
  silently excludes whatever has not been committed yet, which is often everything.
- Treating an unresolvable base or a detached `HEAD` as "nothing changed" — see Resolution rules.
- A criterion phrased so its answer could be "sort of" or "mostly" — see `gate-contract.md`'s
  reject condition.

## Reference, not restatement

A skill or script that resolves or reads a change or a publish-gate outcome references this file
with one line rather than restating the criteria or the resolution rules inline, the same
convention `plan-criteria.md` and `artifact-registry.md` use for their own contracts.

## Fixtures

No static fixtures: unlike `plan-criteria.md`'s plan shape, this criteria's inputs are live git
state, not a file this contract can pin a shape to. `check-publish-criteria.test.sh` builds and
tears down a throwaway git checkout per case instead.

## Verification

`lib/check-publish-criteria.sh <project-root>` is the deterministic checker for criteria 1 and 2 —
no model involved. It exits `0` and prints `valid: publish (<n> files changed)` when the working
tree differs from the merge base and nothing in that diff matches `.gitignore`, `1` with
`invalid: <reason>` on stderr naming the empty diff or the offending path, `2` for a usage or
environment error (missing project root, not a git checkout, no `origin/HEAD`, detached `HEAD`).

```bash
bash plugins/agentic-core/shared/lib/check-publish-criteria.test.sh
```
