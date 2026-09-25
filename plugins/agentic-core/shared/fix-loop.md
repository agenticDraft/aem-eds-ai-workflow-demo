---
description: The fix loop — what one fix attempt is, how many checks a budget of N allows, who counts, and how an edit is chosen. Every stage with an internal check-edit-recheck loop references this file rather than restating the rule or its number.
---

# Fix loop

A stage that checks its own work and edits what the check found runs this loop inside itself. The
component that drives a route never retries a stage (`stage-runner.md`); every fix loop is internal
to the stage that owns it.

## The unit

- A **check** is what the stage measures — a validation, a command run, a comparison against a
  reference.
- An **edit** is everything the stage changes in answer to one check, however many files it
  touches, before it checks again.
- **One fix attempt is one edit.** A stage whose budget is **N** makes **up to N edits and up to
  N+1 checks**: the initial check, and one re-check after each edit. The last check's findings
  decide the stage's verdict.

The budget is the stage's own `fix_attempts` in the pack manifest (`pack-manifest.md`), or, when the
stage declares none, `limits.fix_attempts_default` in the project config (`project-config.md`).

## Who counts

The stage never counts against the number itself, and its instructions never restate the number.
Before each edit it runs:

```
check-fix-budget.sh <pack.yaml> <project-config.yaml> <stage id> <edits-made>
```

- `decision: edit` (exit 0) — make the edit, then check again.
- `decision: exhausted` (exit 4) — make no further edit; report on the last check's findings.
- `decision: terminate-contract-violation` (exit 1) — the count or the budget is malformed, or the
  stage is not declared; report `fail` with the `invalid:` line as the reason.

`edits-made` starts at `0` and goes up by one after each edit, never after a check.

## No improvement

Whether a check improved on the one before stays the stage's own judgment — its inputs are the
stage's own findings, not numbers, so the script does not answer it. A check that found nothing
better than the last may end the loop before the budget does. It never extends the loop.

## Causes, not symptoms

Within one edit, group what the check found **by cause** and change each cause once. A finding that
another change in the same edit is expected to move is left alone until the next check has measured
it. Two changes for one finding in one edit over-correct it, and the next check cannot tell which
change did what.

This is not one change per edit: an edit changes as many causes as the check found.

## Reporting

For each edit, the stage's report names what was changed and which finding each change answered,
then what the check after it measured.
