---
name: diagram-drift
description: Keep diagram-as-code sources (.dot, .d2, .mmd, .puml) truthful about the code they document. Use when a diagram may have gone stale, when changing a pipeline, command, or module that a diagram describes, before opening a PR that touches documented code, or when the user says diagram drift, stale diagram, diagram out of sync, update the diagram, or the diagram is lying.
---

# Diagram drift

A diagram-as-code file is documentation that nobody re-reads. It rots silently:
the pipeline gains a gate, the command loses a step, and the `.dot` still shows
last month's shape. Agents make this worse — code changes in seconds, the
diagram does not change at all.

This skill splits the problem in two. `scripts/check.mjs` decides what a machine
can decide with certainty. You decide the rest, and only when the script says
something moved.

## Setup (once per repo)

Every diagram declares what it documents, in a comment near the top of the file.
Use the comment syntax of the diagram language (`//` for DOT and D2, `%%` for
Mermaid, `'` for PlantUML):

```dot
digraph implement_ticket {
    // @documents: .claude/commands/implement-ticket.md
    // @rendered:  implement_ticket.dot.svg
```

- `@documents` — comma-separated paths or globs. The files this diagram claims
  to describe. Without it, drift cannot be detected and the script says so.
- `@rendered` — optional, relative to the diagram. Enables staleness checks on
  the committed image.

Then pin the current state:

```
node .claude/skills/diagram-drift/scripts/check.mjs --update
```

Commit `.diagram-lock.json`. It records, per diagram, a hash of the diagram and
a hash of the files it documents.

## Steps

1. **Run the check.**

   ```
   node .claude/skills/diagram-drift/scripts/check.mjs
   ```

   Exit code 0 means nothing to do — say so and stop. Do not open files, do not
   re-render, do not offer improvements. A clean run is the common case and it
   should cost nothing.

2. **Read the findings.** Only two levels need you:

   - `drift / code-moved` — the documented files changed and the diagram did
     not. This is the real signal. Go to step 3.
   - `error / dangling`, `unrendered`, `stale-render` — mechanical. Fix the path
     or re-render (step 5). No judgement needed.

   `info` findings are notes, not work. `unclaimed` means the diagram has no
   `@documents` header: mention it once, offer to add one, do not nag.

3. **For each `code-moved` finding, judge whether the diagram still tells the
   truth.** Read the diagram source and every file it documents. Then answer
   one question per node and per edge:

   - Does each node still correspond to something that happens?
   - Does each edge still correspond to a transition that can occur?
   - Did the code gain a step, branch, guard, or early exit that the diagram
     has no node for?

   Report what you found in that shape — node by node — not as "the diagram
   looks outdated". Name the specific node or edge and the specific line of
   code that contradicts it.

4. **If the diagram is still accurate, do not edit it.** Code changed without
   changing behaviour the diagram describes; that is normal. Re-pin and move on:

   ```
   node .claude/skills/diagram-drift/scripts/check.mjs --update
   ```

5. **If it is inaccurate, edit the diagram source, never the rendered image.**
   Keep the change minimal — add the missing gate, rename the step, delete the
   dead branch. Preserve the file's existing style: if every decision node uses
   `shape=diamond` or `class: odluka`, the new one does too.

   Then re-render with whatever the repo already uses, and re-pin:

   ```
   npm run diagrams        # or: dot -Tsvg <file> -O / d2 <file> <out>.svg
   node .claude/skills/diagram-drift/scripts/check.mjs --update
   ```

## Rules

- Never edit a rendered `.svg` or `.png` by hand. It is build output.
- Never update the lock to silence a finding you did not actually resolve.
  The lock records "a human or agent looked at this and it was true".
- Never add `@documents` globs so broad that every commit trips the check
  (`src/**/*` on a busy repo). Point at the files that define the behaviour the
  diagram draws, not the whole tree. If a diagram trips on every unrelated
  commit, narrow the glob rather than deleting the header.
- If a diagram's `@documents` files were deleted outright, ask before deleting
  the diagram — it may document something that moved rather than something gone.

## Verification

Before reporting done:

1. Re-run `check.mjs` with no flags. It must exit 0.
2. Confirm the rendered output exists, is non-empty, and contains `<svg`.
3. Confirm `git status` shows only the diagram source, its rendered output, and
   `.diagram-lock.json` — nothing else.
4. State which nodes or edges you changed and why, in one line each.

## Pre-commit hook

Match whatever the repo already uses. Plain git hook:

```sh
#!/bin/sh
# .git/hooks/pre-commit
node .claude/skills/diagram-drift/scripts/check.mjs || {
  echo
  echo "Diagram drift detected. Run Claude with the diagram-drift skill,"
  echo "or --update if you have verified the diagrams by hand."
  exit 1
}
```
