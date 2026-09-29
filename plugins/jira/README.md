# jira — tracker provider pack

Implements the `tracker` role for the `agentic-core` plugin against a Jira Cloud site over its
REST API: six operations, each a skill that runs one script and returns the script's stdout
unchanged.

**The skill has no branch of its own. The script decides `pass` or `fail`, and prints the
result envelope.**

## The problem it solves

A stage adapter needs a work item's fields and text, needs to write a note or an attachment back,
and must never handle a credential or an HTTP response itself. The core names the `tracker` role
and its operations; this pack is the one place that knows those operations mean Jira.

## How it handles it

1. **One script per operation.** Each `skills/<name>/SKILL.md` runs
   `${CLAUDE_PLUGIN_ROOT}/skills/<name>/scripts/<name>.sh` and outputs its stdout as the whole
   response. The script's output already ends with the `## Result` block the core's
   `shared/result-envelope.md` defines.
2. **Credentials stay in the environment.** `JIRA_SITE`, `JIRA_EMAIL` and `JIRA_API_TOKEN` are
   read by the script and handed to the HTTP client through a stdin config block, never as a
   command-line argument. A missing variable is a `fail` envelope, not a crash.
3. **Tracker-sourced text is validated as data.** An item key must match
   `^[A-Za-z][A-Za-z0-9_]*-[0-9]+$` before it reaches the request; a key with a newline cannot
   inject a config line.
4. **Every operational outcome exits 0 with an envelope on stdout.** Exit 2 is reserved for a
   usage error such as a missing argument.
5. **Authored text becomes the tracker's own document format.** `scripts/md-to-adf.py` converts a
   Markdown draft to the document format `create_item` and `update_item` send;
   `scripts/build-item-fields.py` builds the structured fields from the draft's front matter.
6. **Text conventions ship with the pack.** `pack.yaml` declares the design keywords, the
   reproduction-steps headings and the acceptance-criteria headings a platform pack's intake stage
   uses to derive its fact record from an item fetched here.

## The flow

```text
stage adapter (a platform pack skill)
  │  Skill(jira:fetch-item)  with  item_id: ABC-123
  ↓
skills/fetch-item/SKILL.md
  │  runs scripts/fetch-item.sh ABC-123
  ↓
fetch-item.sh
  ├── JIRA_SITE / JIRA_EMAIL / JIRA_API_TOKEN unset → fail envelope, exit 0
  ├── item key fails the shape check          → fail envelope, exit 0
  └── GET the item over the REST API
        ├── HTTP success → pass envelope, item fields and text on stdout
        └── HTTP error   → fail envelope naming the status
  ↓
stdout, unchanged, is the skill's entire response
```

The adapter that called the operation normalises the output into its own artifact; nothing here
writes to the project tree.

## Operations

| Operation      | Skill         | Input lines                     |
| -------------- | ------------- | ------------------------------- |
| `fetch_item`   | `fetch-item`  | `item_id`                       |
| `post_note`    | `post-note`   | `item_id`, `note`               |
| `attach_file`  | `attach-file` | `item_id`, `file_path`          |
| `list_types`   | `list-types`  | `project`                       |
| `update_item`  | `update-item` | `item_id`, `draft`              |
| `create_item`  | `create-item` | `project_key`, `draft`          |

`pack.yaml` maps each operation to its skill and declares `unsupported: []`.

## What it looks like

**Manifest validation, this run:**

```text
$ claude plugin validate plugins/jira
Validating plugin manifest: .../plugins/jira/.claude-plugin/plugin.json

✔ Validation passed
```

**Pack manifest check by the core, this run:**

```text
$ bash plugins/agentic-core/shared/lib/validate-pack-manifest.sh plugins/jira/pack.yaml
valid: provider
$ bash plugins/agentic-core/shared/lib/check-requires.sh plugins/jira/pack.yaml
ok: no requirements declared
```

**The operation without credentials, this run:**

```text
$ env -u JIRA_SITE -u JIRA_EMAIL -u JIRA_API_TOKEN bash plugins/jira/skills/fetch-item/scripts/fetch-item.sh ABC-1
## Result
verdict: fail
summary: JIRA_SITE, JIRA_EMAIL or JIRA_API_TOKEN is not set in the environment.
artifacts: []
next_action: none
```

Exit status 0: the envelope is the result, and the caller branches on `verdict`.

**The offline test suite, this run:**

```text
$ bash plugins/jira/scripts/md-to-adf.test.sh
...
=== 20 passed, 0 failed ===
```

## Running it yourself

1. Set the three environment variables in the environment that will start the session:
   `JIRA_SITE`, `JIRA_EMAIL`, `JIRA_API_TOKEN`. Nothing in this pack reads a file for them.
2. Load the pack next to the core, from the directory that holds `plugins/`:

   ```text
   claude --plugin-dir ./plugins/agentic-core --plugin-dir ./plugins/jira
   ```

   This pack declares `"dependencies": ["agentic-core"]` in `.claude-plugin/plugin.json`, so an
   install from a marketplace enables the core with it.
3. Validate after any edit, and reload without restarting:

   ```text
   claude plugin validate plugins/jira
   /reload-plugins
   ```
4. Invoke an operation. A stage adapter does it as `Skill(jira:fetch-item)` with the input lines
   as the argument; from a prompt, `/jira:fetch-item` followed by `item_id: <key>`.
5. Run the offline tests:

   ```text
   bash plugins/jira/scripts/md-to-adf.test.sh
   ```

To make this pack the project's tracker, set `packs.tracker: jira` in `.ai/project-config.yaml`
(the core's `setup` skill writes that file).

## Limits you should know

- **Every operation needs the network and a real site.** Nothing in this README was produced by a
  live call; the observed outputs above are the credential-less and usage-error paths.
- **One test file.** `scripts/md-to-adf.test.sh` covers the Markdown-to-document conversion. The
  six operation scripts have no offline test of their own.
- **`update_item` replaces the description.** It does not merge; re-check the live item after a
  write.
- **The site value is used as given.** `JIRA_SITE` is interpolated into the request; the script
  checks the item key's shape, not the site's.

## Design rules this pack follows

A provider operation is a thin, deterministic edge: the model reads one input block, runs one
script, and returns what the script printed. Every decision that can be made by a script is made
by one, so the same input produces the same envelope every time and a failure names its cause.

This pack is the smallest instance of that rule: six skills with no branch in their own control
flow, six scripts that each exit 0 with an envelope. What the tracker returned is the adapter's
to interpret, never this pack's.

---

agenticDraft

License: not declared in `.claude-plugin/plugin.json`. No `NOTICE` ships with this pack.
