# playwright — browser provider pack

Implements the `browser` role for the `agentic-core` plugin: four operations, `render`,
`capture`, `measure` and `interact`, each a skill that runs one script against a real headless
Chromium through the `playwright` library and returns the script's stdout unchanged. No MCP
server is involved.

**The pack declares what it needs in its manifest, and every reader of that declaration reports
the same remedy.** A missing tool is a `fail` envelope carrying the manifest's own text, never a
crash and never an install.

## The problem it solves

A verification stage needs a page's load state, a screenshot at a given width, the computed
styles of named elements, and the state of those elements after a click or a key press. It needs
them as data at fixed paths, and it needs a clear answer when the browser is not there at all.

## How it handles it

1. **One script per operation.** Each `skills/<name>/SKILL.md` runs
   `${CLAUDE_PLUGIN_ROOT}/skills/<name>/scripts/<name>.cjs` and outputs its stdout as the whole
   response. The output ends with the `## Result` block the core's `shared/result-envelope.md`
   defines.
2. **Preconditions are data in `pack.yaml`.** The `requires:` block names two tools, each with a
   probe and a remedy:

   ```yaml
   requires:
     - tool: playwright
       probe: [node, <pack>/scripts/probe-tool.cjs, module]
       remedy: "npm install -g playwright, or add playwright as a project devDependency"
     - tool: chromium
       probe: [node, <pack>/scripts/probe-tool.cjs, browser]
       remedy: "npx playwright install chromium"
   ```

   `scripts/probe-tool.cjs` answers by exit status alone and installs nothing.
   `scripts/requires.cjs` reads the same block so an operation refusing to run reports the same
   remedy the core's `health` diagnostic prints.
3. **`pass` means observed, not healthy.** `render` returns `pass` for an HTTP 404 or 500, because
   the page's state was observed; `fail` is reserved for a load that never completed or a browser
   that could not launch.
4. **A page is settled before it is read.** `scripts/settle.cjs` waits for fonts to load and for
   no named target to be blocked, so a measurement is taken on a page that has stopped moving.
5. **Artifacts get the next free name.** `scripts/next-artifact-path.cjs` names each file an
   operation writes so a re-run never overwrites an earlier capture.
6. **`measure` returns a fixed set of values, at the width it is given.** Geometry plus `color`,
   `background-color`, `font-family`, `font-size`, `font-weight`, `line-height`, the four
   `padding-*` values, `gap`, `border-radius` and `min-width`, per selector, plus `holds_text`
   (whether any element the selector matches has a non-whitespace text node inside it) and
   `broken_words` (the words whose line boxes lie on more than one line). An optional `width` sets
   the viewport, as tall as `capture`'s; the measurement records the width it was read at.
7. **`interact` snapshots before and after.** Every `read:` selector is captured once before the
   first action and once after the last, with geometry, `color`, `background-color`,
   `font-family`, `font-size`, `font-weight`, `line-height`, every `aria-*` attribute and `class`.

## The flow

```text
Skill(playwright:<operation>)   target: <URL> [+ width | selector… | click/press/type + read…]
  ↓
skills/<operation>/scripts/<operation>.cjs
  ├── requires.cjs: a declared tool is missing → fail envelope with the manifest's remedy
  ├── launch headless Chromium, load target
  │     └── load never completes / browser cannot launch → fail envelope
  ├── settle.cjs: fonts loaded, no blocked target
  └── read or act
        render   → final URL, HTTP status, title, console errors
        capture  → full-page PNG at <width>, path from next-artifact-path.cjs
        measure  → per-selector geometry, computed styles, holds_text and broken_words
        interact → per-selector state before and after the actions
  ↓
## Result on stdout, exit 0; the skill returns stdout unchanged
```

## Operations

| Operation  | Skill      | Input lines                                                     |
| ---------- | ---------- | --------------------------------------------------------------- |
| `render`   | `render`   | `target`                                                        |
| `capture`  | `capture`  | `target`, `width`                                               |
| `measure`  | `measure`  | `target`, optional `width`, one or more `selector`              |
| `interact` | `interact` | `target`, one or more of `click` / `press` / `type`, one or more `read` |

`pack.yaml` maps each operation to its skill, declares `unsupported: []`, and names
`skills/render/scripts/render.cjs` under `scripts:` for a caller that needs a load check without
a model step.

## What it looks like

**Manifest validation, this run:**

```text
$ claude plugin validate plugins/playwright
Validating plugin manifest: .../plugins/playwright/.claude-plugin/plugin.json

✔ Validation passed
```

**The core reading this pack's preconditions, this run, on a machine with both tools present:**

```text
$ bash plugins/agentic-core/shared/lib/validate-pack-manifest.sh plugins/playwright/pack.yaml
valid: provider
$ bash plugins/agentic-core/shared/lib/check-requires.sh plugins/playwright/pack.yaml
ok: playwright
ok: chromium
```

**A browser that could not launch, this run.** The command ran inside a command sandbox that
blocks the browser process; the operation still returned an envelope and exit status 0:

```text
$ node plugins/playwright/skills/render/scripts/render.cjs http://127.0.0.1:1/
## Result
verdict: fail
summary: could not launch Chromium: browserType.launch: Target page, context or browser has been closed
artifacts: []
next_action: none
```

**A usage error, this run:**

```text
$ node plugins/playwright/skills/measure/scripts/measure.cjs
usage: measure.cjs [--width <n>] <target-url> <selector> [selector...]
```

Exit status 2.

**The offline test suites, this run:**

```text
$ bash plugins/playwright/scripts/next-artifact-path.test.sh
passed: 13, failed: 0
$ bash plugins/playwright/scripts/settle.test.sh
passed: 34, failed: 0
$ bash plugins/playwright/skills/measure/scripts/measure.test.sh
passed: 13, failed: 0
```

## Running it yourself

1. Make the two declared tools present, using the manifest's own remedies:
   `npm install -g playwright` (or add `playwright` as a project devDependency), then
   `npx playwright install chromium`.
2. Load the pack next to the core, from the directory that holds `plugins/`:

   ```text
   claude --plugin-dir ./plugins/agentic-core --plugin-dir ./plugins/playwright
   ```

   This pack declares `"dependencies": ["agentic-core"]` in `.claude-plugin/plugin.json`.
3. Check the preconditions the way the core does:

   ```text
   bash plugins/agentic-core/shared/lib/check-requires.sh plugins/playwright/pack.yaml
   ```

   or, in a session with the core loaded and the project configured, `/agentic-core:health`.
4. Validate after any edit, and reload without restarting:

   ```text
   claude plugin validate plugins/playwright
   /reload-plugins
   ```
5. Invoke an operation. A stage adapter does it as `Skill(playwright:render)` with the input
   lines as the argument; from a prompt, `/playwright:render` followed by `target: <URL>`.
   Every operation writes its artifact under `.ai/playwright/` at the project root: a PNG for
   `capture`, a JSON file for the other three, each named `<operation>-<target slug>[-<width>]-<n>`.
6. Run the offline tests, listed above.

To make this pack the project's browser, set `packs.browser: playwright` in
`.ai/project-config.yaml`.

## Limits you should know

- **Chromium only.** The scripts launch one engine; no other browser is declared or probed.
- **A sandbox that blocks the browser process turns every operation into `fail`.** The envelope
  above is what that looks like; it is indistinguishable from a missing binary except by its
  summary text. Each operation skill therefore runs its script with the command sandbox off,
  unconditionally; a caller that runs a script itself, sandboxed, gets that envelope.
- **Three test files cover the helpers and `measure`'s parsing.** `render`, `capture` and
  `interact` have no offline test; a real page was not loaded in producing this README.
- **A local preview needs loopback.** The operations connect to whatever URL they are given;
  a sandbox that denies loopback connections denies them too.
- **The style set is fixed.** A value outside the list under `measure` is not returned.
- **`broken_words` reads one text node at a time.** A word an inline element splits into two text
  nodes (`<b>Web</b>Surge`) is read as two words, and a break between them is not reported.

## Design rules this pack follows

One declaration, many readers: the manifest states what the pack needs and how to fix its
absence, and the probe, the core's diagnostic and the operation itself all read that one text.
Two hand-written copies of a remedy agree only until one is edited.

This pack is the one provider here that depends on a binary outside the session, which is why
the declaration exists at all. The operations refuse without their tool; nothing here ever
installs it.

---

agenticDraft

License: not declared in `.claude-plugin/plugin.json`. No `NOTICE` ships with this pack.
