# The runner — starting a route with nobody present

`route-agent.mjs` starts one SDK session for one literal prompt — a route, or a single
operation — and turns how that session ended into an exit code. It is the entry point a CI job
calls; it names no pack, no tracker and no CI product, and learns everything else from the
environment.

## What it guarantees

- **Fail-closed permissions.** The session runs in `dontAsk` mode with the allow rules in
  `ROUTE_ALLOWED_TOOLS`. A call no rule covers is denied, never asked and never waved through.
  Bypass is never used. The project's committed settings load too (`settingSources: ["project"]`),
  so their own allow rules apply beside `ROUTE_ALLOWED_TOOLS`; the effective allowlist is the
  union of the two.
- **A locked network allowlist.** At launch the runner reads `sandbox.network.allowedDomains` from
  the project's committed settings (`.claude/settings.json`, or `ROUTE_SETTINGS_FILE`) and passes
  it to the session's policy tier (`managedSettings`) with `strictAllowlist`,
  `allowUnsandboxedCommands: false`, `autoAllowBashIfSandboxed: false` and `failIfUnavailable`.
  The last but one keeps the allow rules binding: a sandboxed command is not approved just
  because it is sandboxed.
- **What it loads stays read-only.** The plugin directory, the committed settings file and the
  route policy are denied to every write the session can make — the file tools and sandboxed
  commands alike — so an allowed edit can never become an allowed command. The log names them
  (`protected from writes:`). A sandboxed command that reaches an
  unlisted host is denied, never prompted for, and never retried with the sandbox off; a sandbox
  that cannot start ends the session. The committed file is the only list: the copy lives only
  in the running process. A missing file, invalid JSON, or an absent or empty list starts nothing
  (exit `6`), and so does a lock that did not survive the settings merge (an administrator's
  managed tier on the machine drops a parent's policy tier by default).
- **Credentials stay in the environment.** The SDK inherits this process's environment and loads
  no file. Nothing here prints, copies or stores a credential. What each pack reads is the pack's
  business — its own README names the variables — and the caller exports them in the shell or
  maps them from the CI product's secret store onto the step that runs this script.
- **A verdict is read from an envelope, not guessed from prose.** The session's final text is
  written to `ROUTE_RESULT_FILE`; the caller runs `shared/lib/validate-result-envelope.sh` over
  it. A session that ends without a conformant envelope is a failure.
- **Bounded by the route policy.** Before anything starts it reads `.ai/route-policy.yaml`
  (`ROUTE_POLICY_FILE`) through `shared/lib/check-route-policy.sh`; a missing or invalid policy
  starts nothing (exit `3`). The policy's forbidden rules are denied in every call, a forked
  stage's included, with the policy named as the reason; its budget is the SDK's per-run budget;
  its caps bound turns and wall-clock time. `ROUTE_MAX_TURNS` and `ROUTE_TIMEOUT_MINUTES` may
  lower a cap, never raise it. See `shared/route-policy.md`.

Before the session starts, the caller checks the daily limits with
`shared/lib/check-run-limits.sh` and claims the event with `shared/lib/claim-run.sh`, so a
redelivered event starts no second session and a flood starts no extra ones (see those scripts'
headers).

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

A policy must exist for a local run too; point `ROUTE_POLICY_FILE` at a copy to try other values.
The sandbox must be able to start on the machine: a runner launched from inside another
sandboxed session cannot start its own, and the session ends with an error.

The log on stderr shows, in order: the prompt, the configured packs, the plugins found, the allow
rules, the policy, the effective sandbox block and the copied domain list, the caps; then the session's own init line (version, model, mode), the plugins the SDK
loaded, the skills and commands it registered, every tool call, every tool error, and how the
session ended.

## Reading the log

- `loaded plugins:` lists every plugin the SDK accepted. A plugin missing here was skipped; the
  `plugin errors:` line that follows says why.
- `commands (n):` is the registered command list. A plugin's command appearing twice means it was
  loaded twice (once by path, once by the project's own plugin settings).
- `-> Bash: …` lines prefixed `(subagent)` come from a forked stage; `!! tool error:` is a denied
  or failed call — under `dontAsk` a denial is what a missing allow rule looks like.
- `denied <tool>: forbidden by route policy (…)` is the policy refusing a call; the same reason
  follows as a tool error.
- `cap reached: <cap>=<n> (route policy)` names the cap that ended the run.
- `sandbox (effective, from managed/parent): … strictAllowlist=true` is the lock as the session
  will see it; `sandbox allowlist (copied from …)` lists every host a command may reach.
- `network allowlist refused: <reason>` is exit `6`; nothing was started.
- A tool error naming a host as denied is the lock refusing an undeclared host.

## The migration cost of the lock

A locked allowlist refuses per-command domain lists, so **every host every stage reaches must be
declared up front** in the committed settings' `sandbox.network.allowedDomains`. A route that
needs an undeclared host fails at the command that reaches it, with the host named in the tool
error. Declare it through a reviewed change to the settings file, then re-run. The lock covers
sandboxed commands only: in-process tools (web fetches, which follow their own allow rules), tool
servers and the model's own traffic are outside it, and so is anything that ran before the
session started.
- `ended: subtype=…` is the SDK's own verdict on the session. Only `success` exits `0`.

## Exit codes

| code | meaning |
| ---- | ------- |
| `0`  | the session ended with subtype `success` |
| `1`  | any other subtype, no result at all, or an error |
| `2`  | the wall-clock cap was reached |
| `3`  | the route policy is missing or invalid; nothing was started |
| `4`  | the turn cap was reached |
| `5`  | the budget cap was reached |
| `6`  | the network allowlist was refused; nothing was started |
| `64` | usage: no prompt given |
