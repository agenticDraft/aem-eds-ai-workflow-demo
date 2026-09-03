# agentic-core

The agnostic delivery core (Phase 2). Names no tracker, SCM, design tool, browser, language or
package manager — that vocabulary belongs to a pack, never to the core.

This is a scaffold: one placeholder skill (`health`) proves the plugin loads and namespaces
correctly. Stage runner, envelope contract, config schema and route resolver land in later Phase 2
tasks.

## Load locally (development)

From the repo root:

```bash
claude --plugin-dir ./plugins/agentic-core
```

Then, inside the session:

```
/agentic-core:health
```

To load alongside the platform pack once it exists:

```bash
claude --plugin-dir ./plugins/agentic-core --plugin-dir ./plugins/<pack>
```

## Validate the manifest

```bash
claude plugin validate plugins/agentic-core
```

## Pick up an edit without restarting

With the plugin already loaded via `--plugin-dir`, edit any file under `skills/`, then run:

```
/reload-plugins
```

No restart, no re-launch. This is the testing story D38 depends on — if a change to a skill ever
needs a restart to take effect, that decision is invalidated and must be revisited, not worked
around.
