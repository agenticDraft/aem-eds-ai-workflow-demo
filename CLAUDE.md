This project is an Adobe AEM Edge Delivery boilerplate, used only as a DEMO and as the test bed
for the delivery automation we are building.

**The automation is the point of this repo.** It is an agnostic delivery core plus swappable
packs — this platform is one consumer, not the subject. Interfaces are in
`docs/implementation-plan/01-core-contracts.md` (the authority when documents
disagree); the standing rules and the full document index are in
`docs/implementation-plan/00-instructions.md`
(local-only, gitignored). Read both before changing anything under `.claude/`, or before starting any
automation or tooling work. The plugins live in `agenticDraft/plugins` and are edited only there.

**Load `AGENTS.md` and `AGENTS.project.md` only when the work is EDS.** Writing or changing
blocks, styles, `scripts/` or anything served to the site? Read both, in that order.
`AGENTS.md` is Adobe's upstream file, kept byte-identical to `adobe/aem-boilerplate` so it stays
mergeable — never edit it except the `## This project` pointer at the end; upstream changes come
in via `git fetch upstream`. `AGENTS.project.md` is our house style, commands and deployment
process, and holds only what upstream does not already say. Working on the delivery automation
(`.claude/`, `docs/implementation-plan/`)? Do **not** read either: the core must name
no platform (D28, D34), and loading Edge Delivery vocabulary into a session that must not use it
works against that rule.

Neither is auto-imported, so nothing loads them for you.

**Writing, reviewing or rewriting a Jira work item?** Invoke the `agentic-core:write-specs` skill
(from the `agentic-core` plugin) rather than writing it by hand — it owns the ticket shape and
proves conformance with its own checker before anything is pasted in.

<!-- This file carries project POLICY plus an INDEX of documents to read on a trigger.
     Reference material — how EDS works, how a tool behaves — belongs in the referenced
     file, never here: every line loads into every session. Keep it under 200 lines. -->

**Plugin pin check.** First reply of every interactive session, before other work, run
`bash .claude/scripts/update-plugin-pin.sh --check` with `dangerouslyDisableSandbox: true`
(SSH remote). Skip it in route-runner, `-p` and other headless sessions.
- Exit 0: say nothing.
- Exit 10: ask with `AskUserQuestion` — current pin, newest tag, options "update now" /
  "skip this session". On "update now", give `! bash .claude/scripts/update-plugin-pin.sh`
  and stop; afterwards the human commits the two edited files and restarts the session.
- Any other exit: report it in one line and continue.
- Never edit the plugin `ref` in `.claude/settings.json` or `.github/workflows/route-trigger.yaml` by hand.

This project also serves as a learning project, so for every task in implementation provide details and documentation to cover and explain what is done. Use official docs, like Claude Skills.
Also after every step create summary what is done and explain architecture and write task-1-done.md for example.
