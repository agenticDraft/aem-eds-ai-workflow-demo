This project is an Adobe AEM Edge Delivery boilerplate, used only as a DEMO and as the test bed
for the delivery automation we are building.

**The automation is the point of this repo.** It is an agnostic delivery core plus swappable
packs — this platform is one consumer, not the subject. Interfaces are in
`docs/implementation-plan/01-core-contracts.md` (the authority when documents
disagree); the standing rules and the full document index are in
`docs/implementation-plan/00-instructions.md`
(local-only, gitignored). Read both before changing anything under `.claude/` or `plugins/`, or
before starting any automation or tooling work.

**Load `AGENTS.md` and `AGENTS.project.md` only when the work is EDS.** Writing or changing
blocks, styles, `scripts/` or anything served to the site? Read both, in that order.
`AGENTS.md` is Adobe's upstream file, kept byte-identical to `adobe/aem-boilerplate` so it stays
mergeable — never edit it except the `## This project` pointer at the end; upstream changes come
in via `git fetch upstream`. `AGENTS.project.md` is our house style, commands and deployment
process, and holds only what upstream does not already say. Working on the delivery automation
(`.claude/`, `plugins/`, `docs/implementation-plan/`)? Do **not** read either: the core must name
no platform (D28, D34), and loading Edge Delivery vocabulary into a session that must not use it
works against that rule.

Neither is auto-imported, so nothing loads them for you.

<!-- This file carries project POLICY plus an INDEX of documents to read on a trigger.
     Reference material — how EDS works, how a tool behaves — belongs in the referenced
     file, never here: every line loads into every session. Keep it under 200 lines. -->

This project also serves as a learning project, so for every task in implementation provide details and documentation to cover and explain what is done. Use official docs, like Claude Skills.
Also after every step create summary what is done and explain architecture and write task-1-done.md for example.
