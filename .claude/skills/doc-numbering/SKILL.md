---
name: doc-numbering
description: Check that numbered record documents — gap registers, decision logs, anything using `### G<n>` or `## D<n>` headings — have not filed the same identifier twice. Use right after appending a new numbered entry, before opening a PR that adds one, when two people or two sessions have been writing to the same register, or when the user says duplicate gap, duplicate decision, numbering collision, renumber, or asks which number is free.
---

# Numbered-record collisions

A register that several people or sessions append to has no allocation
mechanism. Two authors each read the same "next free" number, minutes apart,
and both write it. Nothing notices: the file is still valid markdown, the
duplicate sits in the middle of thousands of lines, and from then on every
reference to that number is ambiguous — including references written before
the collision, which silently acquire a second meaning.

The window between "I picked a number" and "the number is on disk" is where
this happens, and it cannot be closed by being careful. So the check runs
*after* writing, not before.

## Run the checker

```
.claude/skills/doc-numbering/scripts/check-numbering.sh <file> [<file> …]
```

Exit 0 means no identifier is claimed twice. Exit 1 lists each duplicated
identifier with every `file:line` claiming it.

**Name the files that own numbers, not the directory that contains them.**
A register owns its identifiers. A spec, a design note or a completion record
that *discusses* one restates the heading, and those restatements are not
collisions. Pointing the checker at a whole directory reports them as if they
were, and a report full of false positives is one nobody reads — which is
worse than no check, because it looks like coverage.

## When to run it

- **Immediately after appending a numbered entry**, in the same session that
  wrote it. That is the moment when fixing it costs one renumber; a week of
  references later it costs an audit.
- **Before opening a pull request** that adds one.
- **After merging work from a second track**, which is the case that produces
  collisions in the first place.

## What to do with a duplicate

Renumber the **later** entry — the one whose references are fewest and
youngest — and update every reference to it. Then re-run the checker: the
renumber can collide again if more than one number was taken while you were
working. That is not hypothetical; it is the ordinary case when two tracks
are active.

**Never resolve a duplicate by deleting an entry.** A register's value is
that a decision, once made, stays findable with its reasoning — including
decisions that turned out wrong. Renumbering preserves both; deleting
destroys one to tidy the other.

## Preventing rather than detecting

The checker finds collisions; it does not stop them. When two tracks are
knowingly running at once, give each a number range — one continues the
existing sequence, the other starts somewhere far above it. No coordination
is needed, nothing has to be locked, and the number itself then says which
track filed it. This costs a convention and removes the race entirely, which
is a better trade than any locking scheme over a file two sessions append to
independently.
