This project is an Adobe AEM Edge Delivery boilerplate, used only as a DEMO and as the test bed
for the delivery automation we are building.

**The automation is the point of this repo.** It is an agnostic delivery core plus swappable
packs — this platform is one consumer, not the subject. Interfaces are in
`docs/implementation-plan/01-core-contracts.md` (the authority when documents
disagree); the standing rules and the full document index are in
`docs/implementation-plan/00-instructions.md`
(local-only, gitignored). Read both before changing anything under `.claude/` or `plugins/`, or
before starting any automation or tooling work.

When working on EDS components, blocks, styles or scripts — and for all commands, project
structure and house style — see @AGENTS.md

<!-- This file carries project POLICY plus an INDEX of documents to read on a trigger.
     Reference material — how EDS works, how a tool behaves — belongs in the referenced
     file, never here: every line loads into every session. Keep it under 200 lines. -->

This project alse serve as a learning project, so for every task in implementation provide details and documentation to cover and explain what is done. Use official docs, like claude skillr.
Also after every step create summary what is done and explain architecture and write task-1-done.md for example.
