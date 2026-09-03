---
description: Report that the agentic-core plugin scaffold is loaded, and from where.
disable-model-invocation: true
---

Report, in a few short lines:

1. The plugin loaded as `agentic-core` (read the `name` field from
   `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json`).
2. The value of `${CLAUDE_PLUGIN_ROOT}`, so it is clear which copy on disk is active.
3. That no stage adapters exist yet — this skill exists only to prove the plugin scaffold,
   the `--plugin-dir` load path, and `/reload-plugins` all work before any real stage is built.

Do not invent config, routes, or stage behavior. This skill has no other purpose.
