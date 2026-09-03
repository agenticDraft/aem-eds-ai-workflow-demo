---
description: Detect this project's build/test/lint/serve commands and where it keeps specs and a local preview, confirm them with you, and write them into project-config.yaml. Re-runnable with keep / re-detect / edit. Covers detection only — choosing packs and seeding routes are separate, not-yet-built steps.
disable-model-invocation: true
---

You detect this project's own commands and layout, confirm them with the human, and write them into `project-config.yaml` at the project root. The full shape of that file is defined in `shared/project-config.md` — reference it, never restate it.

**What this skill does not do yet:** it never writes `packs`, `routes`, or `limits` — those come from steps this plugin does not yet implement. A file written by this skill alone will not pass `shared/lib/validate-project-config.sh` on its own; say so plainly in your final report rather than implying the file is complete.

## 0. Check for an existing file

Look for `project-config.yaml` at the project root.

- **It does not exist:** go to step 1.
- **It exists and already has `commands:` and `paths:` sections:** show their current values and ask, with `AskUserQuestion`: **keep** (stop here, nothing changes), **re-detect** (go to step 1, run detection fresh, then confirm and overwrite through step 3), or **edit** (skip detection — ask the human directly for each of the six values, then go straight to step 2 with those).
- **It exists but lacks `commands:` or `paths:`:** treat it the same as re-detect — detection and the write step only ever touch those two sections, so this is safe.

## 1. Detect

Inspect the project's own files for however it declares its steps and layout. This instruction names no specific ecosystem, build tool, or manifest format on purpose — read whatever the project actually contains and use your own knowledge of that project's conventions to answer:

- `lint`, `test`, `build`, `serve` — the exact command the project itself would run for each, taken verbatim from wherever the project declares it (a script, a task file, a build config — whatever form this particular project uses). Leave a value blank if the project declares nothing recognizable as that step. **Never invent one.**
- `spec_dir` — the directory in this project where written specifications live.
- `preview` — a URL where a running instance of this project can be viewed locally.

`spec_dir` and `preview` may not be obvious from the files alone. Unlike the four commands, they may **not** be left blank — if nothing in the project makes one obvious, ask the human for it directly rather than guessing.

This step only reads. It writes nothing and installs nothing.

## 2. Confirm

Before anything touches disk, list all six values exactly as they will be written, and ask the human to confirm them or say what to change, using `AskUserQuestion`. If they want changes, take the corrected value for each field they name and confirm the full set again before moving on. Do not proceed to step 3 until the human has explicitly accepted the values as shown.

## 3. Write

Run:

```
${CLAUDE_PLUGIN_ROOT}/shared/lib/write-detected-config.sh <config-path> <lint> <test> <build> <serve> <spec_dir> <preview>
```

against `project-config.yaml` at the project root, using the confirmed values. Report its output verbatim. If it exits non-zero — a value the human confirmed still violates the contract (for example an empty `spec_dir`) — do not retry with a guessed substitute; go back to step 2 for that field alone.

## 4. Report

State plainly:

- the path written or updated, and whether it was a fresh file or an update
- the six values as written
- that `packs`, `routes`, and `limits` are not part of this file yet, so it will not pass the full config validator on its own

## Rules

- **Show before write, always.** Nothing reaches disk that was not shown to the human first, verbatim.
- **Detect first, ask second** — auto-detect everything a command value can be; ask only what genuinely cannot be determined (and always ask for `spec_dir`/`preview` if detection comes up empty).
- **Never guess a path.** A blank `spec_dir` or `preview` is a contract violation, not a placeholder to fill in later.
- **This skill's own instructions name no product, platform, language, package manager, or file extension** — only the project being inspected may determine the concrete answer, and that answer is data written to `project-config.yaml`, never a name embedded back into this file.
- **Idempotent.** Re-running with unchanged values overwrites `commands`/`paths` with the same values; nothing is duplicated.
