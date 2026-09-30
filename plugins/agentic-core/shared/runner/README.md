# The runner — starting a route with nobody present

`route-agent.mjs` starts one SDK session for one literal prompt — a route, or a single
operation — and turns how that session ended into an exit code. It is the entry point a CI job
calls; it names no pack, no tracker and no CI product, and learns everything else from the
environment.

## What it guarantees

- **Fail-closed permissions.** The session runs in `dontAsk` mode with the allow rules in
  `ROUTE_ALLOWED_TOOLS`. A call no rule covers is denied, never asked and never waved through.
  Bypass is never used. The project's committed settings load too (`settingSources: ["project"]`),
  so their own allow rules and network domain list apply beside `ROUTE_ALLOWED_TOOLS`; the
  effective allowlist is the union of the two.
- **Credentials stay in the environment.** The SDK inherits this process's environment and loads
  no file. Nothing here prints, copies or stores a credential. What each pack reads is the pack's
  business — its own README names the variables — and the caller exports them in the shell or
  maps them from the CI product's secret store onto the step that runs this script.
- **A verdict is read from an envelope, not guessed from prose.** The session's final text is
  written to `ROUTE_RESULT_FILE`; the caller runs `shared/lib/validate-result-envelope.sh` over
  it. A session that ends without a conformant envelope is a failure.
- **Bounded.** `ROUTE_MAX_TURNS` caps turns; `ROUTE_TIMEOUT_MINUTES` caps wall-clock time and
  exits `2` when reached.

Before the session starts, the caller claims the event with `shared/lib/claim-run.sh`, so a
redelivered event starts no second session (see that script's header).

## Reproducing a run locally

Install the dependency once, inside this directory (it writes `node_modules/` here; that
directory is ignored by version control):

```
cd plugins/agentic-core/shared/runner && <package manager> install
```

Then, from the project root, with the credentials **exported in the shell** — never written to a
file:

```
export ANTHROPIC_API_KEY=…          # the model credential
export <whatever the configured packs read>
ROUTE_ALLOWED_TOOLS="Skill,Read,Glob,Grep,Bash(bash plugins/*)" \
ROUTE_RESULT_FILE=.ai/run-context/runner-result.txt \
node plugins/agentic-core/shared/runner/route-agent.mjs "/<pack>:<operation> item_id: <id>"
bash plugins/agentic-core/shared/lib/validate-result-envelope.sh .ai/run-context/runner-result.txt
```

The log on stderr shows, in order: the prompt, the configured packs, the plugins found, the allow
rules, the caps; then the session's own init line (version, model, mode), the plugins the SDK
loaded, the skills and commands it registered, every tool call, every tool error, and how the
session ended.

## Reading the log

- `loaded plugins:` lists every plugin the SDK accepted. A plugin missing here was skipped; the
  `plugin errors:` line that follows says why.
- `commands (n):` is the registered command list. A plugin's command appearing twice means it was
  loaded twice (once by path, once by the project's own plugin settings).
- `-> Bash: …` lines prefixed `(subagent)` come from a forked stage; `!! tool error:` is a denied
  or failed call — under `dontAsk` a denial is what a missing allow rule looks like.
- `ended: subtype=…` is the SDK's own verdict on the session. Only `success` exits `0`.

## Exit codes

| code | meaning |
| ---- | ------- |
| `0`  | the session ended with subtype `success` |
| `1`  | any other subtype, no result at all, or an error |
| `2`  | the wall-clock cap was reached |
| `64` | usage: no prompt given |
