# figma — design provider pack

Implements the `design` role for the `agentic-core` plugin: one operation, `fetch_reference`,
which retrieves a Figma node's layout, colour and typography values, the images and icons it
references, and a reference screenshot through the `figma` marketplace plugin's MCP server.

**The scripts own every classification decision. The model fetches what they name and never
picks a frame on its own.**

## The problem it solves

A design reference is a URL to one node in a file. Behind that URL the node may be a single
frame, a set of viewport variants of the same page, a whole page, or several unrelated frames,
and the tool responses carry short-lived download URLs that must not be written anywhere. A
stage adapter needs the values and images on disk, in a fixed shape, with the ambiguity resolved
or turned into a question.

## How it handles it

1. **Four MCP tools, each with one job.** `get_metadata` confirms the node and gives its geometry;
   `get_design_context` returns the reference code whose classes carry the values, plus the
   styles line; `get_variable_defs` returns the token map; `get_screenshot` returns the reference
   image. The skill's `allowed-tools` lists exactly these four plus `ToolSearch` and `Skill`.
2. **The URL is checked before any tool is loaded.** A design URL without a `node-id` is a
   `question`; a URL that is not a supported design URL is a `fail` with `error_class:
   VALIDATION`.
3. **Authentication is reported, never started.** When the marketplace plugin is installed but not
   authenticated, the envelope carries this exact summary and the operation never calls
   `authenticate`:

   ```text
   Figma is not authenticated: run /plugin, select figma, choose Authenticate, finish sign-in in the browser, then re-run.
   ```

4. **Classification is a script.** `scripts/classify-node.py` reads the metadata and answers
   `single`, `variants`, `page` or `multi-frame`. `page` and `multi-frame` become a `question`;
   the skill never picks a candidate, even one whose name matches the work item.
5. **Viewport variants are planned by a script.** `scripts/viewports.py plan` prints one target per
   variant, widest first; the skill fetches exactly those and no other.
6. **Asset URLs never reach a file.** The code block goes to `scripts/fetch-assets.py` on stdin;
   the script downloads each asset, names its format from its bytes (`scripts/sniff-asset.py`),
   and rewrites the code with local paths. `scripts/screenshot-size.py` records each screenshot's
   requested and actual size and marks a downscaled render.
7. **Tool errors are classified, and only `TRANSIENT` is retried.** The class rides in the
   envelope's `error_class`.

## The flow

```text
Skill(figma:fetch-reference)   reference: https://www.figma.com/design/<file_key>/...?node-id=<id>
  ↓
parse URL ── no node-id → question
  ↓
load the four MCP tools ── not installed / not authenticated → fail (PERMANENT)
  ↓
get_metadata → .ai/figma/<file_key>-<node_id>.metadata.xml
  ↓
classify-node.py → .ai/figma/<file_key>-<node_id>.classification.tsv
  ├── single      → one target
  ├── variants    → viewports.py plan → one target per variant, widest first
  └── page | multi-frame → question
  ↓  per target
get_design_context → fetch-assets.py → <target>.context.txt, <target>.assets.json, assets/
get_variable_defs  (once)
get_screenshot     → <target>.png, sized by screenshot-size.py
  ↓
.ai/figma/<file_key>-<node_id>.json   (reference, geometry, variables, design_context,
                                       screenshots, assets, viewports when variants)
  ↓
## Result  verdict: pass  artifacts: every file written  metrics: variables=… design_context=… node_class=…
```

A design context the tool returns as structure only, or cut short by its size cap, is recorded as
`structure_only`, not as an error: metadata, variables and the screenshot still cover the node.

## What it looks like

**Manifest validation, this run:**

```text
$ claude plugin validate plugins/figma
Validating plugin manifest: .../plugins/figma/.claude-plugin/plugin.json

✔ Validation passed
```

**Pack manifest check by the core, this run:**

```text
$ bash plugins/figma/core/lib/validate-pack-manifest.sh plugins/figma/pack.yaml
valid: provider
```

**The offline test suites, this run:**

```text
$ bash plugins/figma/skills/fetch-reference/scripts/classify-node.test.sh
passed: 75, failed: 0
$ bash plugins/figma/skills/fetch-reference/scripts/fetch-assets.test.sh
passed: 50, failed: 0
$ bash plugins/figma/skills/fetch-reference/scripts/screenshot-size.test.sh
passed: 29, failed: 0
$ bash plugins/figma/skills/fetch-reference/scripts/sniff-asset.test.sh
passed: 25, failed: 0
$ bash plugins/figma/skills/fetch-reference/scripts/viewports.test.sh
passed: 42, failed: 0
```

Five files, 221 assertions, no network.

## Running it yourself

1. Install the `figma` marketplace plugin and authenticate it: `/plugin`, select `figma`, choose
   Authenticate, finish sign-in in the browser. This pack calls that plugin's MCP tools; it ships
   no server of its own.
2. Load the pack next to the core, from the directory that holds `plugins/`:

   ```text
   claude --plugin-dir ./plugins/agentic-core --plugin-dir ./plugins/figma
   ```

   This pack declares `"dependencies": ["agentic-core"]` in `.claude-plugin/plugin.json`.
3. Validate after any edit, and reload without restarting:

   ```text
   claude plugin validate plugins/figma
   /reload-plugins
   ```
4. Invoke the operation. A stage adapter does it as `Skill(figma:fetch-reference)` with one
   input line, `reference: <design URL with node-id>`; from a prompt, `/figma:fetch-reference`
   followed by that line. Outputs land under `.ai/figma/` at the project root.
5. Run the offline tests, listed above.

To make this pack the project's design source, set `packs.design: figma` in
`.ai/project-config.yaml`.

## Limits you should know

- **The operation needs the marketplace plugin, its authentication and the network.** The five
  test files cover the scripts; the MCP calls and the skill's own branching were not exercised
  in producing this README.
- **`/design/` URLs only.** `/file/`, `/board/`, `/slides/` and `/make/` URLs are refused as
  `VALIDATION`.
- **One pack, one name shared with what it wraps.** This pack and the marketplace plugin are both
  named `figma`. In the session that produced this README both were loaded and their skills
  resolved side by side under the `figma:` prefix; other setups were not tested.
- **`get_design_context` needs a skill from the wrapped plugin.** The operation loads
  `figma:figma-design-to-code` for that prerequisite only and writes no application code.
- **Screenshot and asset URLs are short-lived.** They exist in the tool response and in the
  download command, never in a file or the envelope.

## Design rules this pack follows

Where a decision can be made from data on disk, a script makes it, and the model does what the
script printed. A frame chosen by name would be a guess dressed as a fetch; a question is the
honest answer when the reference is ambiguous.

This pack adapts patterns from earlier work under the terms recorded in [NOTICE](NOTICE).

---

agenticDraft

License: not declared in `.claude-plugin/plugin.json`. Attribution and terms for adapted
material: [NOTICE](NOTICE).
