---
name: note
description: Fixture only — stands in for a tracker pack's post_note implementation so the manifest validator's skill-exists check resolves. Implements nothing and is never invoked.
---

# note

A fixture. The manifest beside it maps `post_note` to this directory, and the manifest validator
requires every operation it names to resolve to a real `SKILL.md`. That requirement is what this
file satisfies — nothing reads past the frontmatter.

The pack this belongs to exists to exercise one case: a tracker declaring an operation a stage
genuinely needs as unsupported, so a check can be shown to still block on it.
