# Setting up the route runner — what the repository must hold before a token comment can run

`route-trigger.yaml` runs a delivery route on a GitHub-hosted runner with nobody logged in. It
gets every credential from this repository's **Actions secrets and variables**, mapped onto the
one step that runs the route. Nothing is read from a file, and nothing in this repository ever
holds a credential value. This page is the checklist a person works through once, in
*Settings → Secrets and variables → Actions*.

## 1. Secrets (values are never shown again after saving)

| name | what it is | where it comes from |
| ---- | ---------- | ------------------- |
| `ANTHROPIC_API_KEY` | the model credential the runner's SDK session uses | an API key from the Anthropic Console (the runner authenticates with a key; a claude.ai login has no headless form) |
| `JIRA_API_TOKEN` | the tracker pack's credential (`plugins/jira`) | an Atlassian API token for the account in `JIRA_EMAIL` |
| `ROUTE_GH_TOKEN` | the SCM pack's credential (`plugins/github`), used as `GH_TOKEN` by `gh` and, through `gh auth setup-git`, by `git push` | a **fine-grained personal access token** — see §3 |

## 2. Variables (plain values, visible in the settings)

| name | what it is |
| ---- | ---------- |
| `JIRA_SITE` | the tracker site the pack talks to, e.g. `https://<your-site>.atlassian.net` — the same value `plugins/jira/README.md` describes for a local shell |
| `JIRA_EMAIL` | the account the token in `JIRA_API_TOKEN` belongs to |
| `ROUTE_PROMPT` *(optional)* | the prompt the runner executes; `{item_id}` is replaced with the work item id. Default when unset: `/jira:fetch-item item_id: {item_id}` — the single-stage check. The whole route is `/agentic-core:run-route {item_id} autonomous` (Phase 9 / Task 5 switches to it) |
| `ROUTE_ALLOWED_TOOLS` *(optional)* | the allow rules the session runs under; `{workspace}` is replaced with the checkout path. Default: the tracker's `fetch-item` script only |
| `ROUTE_MAX_TURNS`, `ROUTE_TIMEOUT_MINUTES` *(optional)* | may only **lower** the caps in `.ai/route-policy.yaml`; a larger value is ignored |

## 3. The fine-grained token behind `ROUTE_GH_TOKEN`

Create it under your account's *Developer settings → Personal access tokens → Fine-grained
tokens*, **resource owner: this repository's owner, repository access: only this repository**,
with these repository permissions and nothing more:

| permission | access | why |
| ---------- | ------ | --- |
| Contents | read and write | the claim tag (`agentic-run/<item>-c<comment>`) and the working branch are pushed with it |
| Pull requests | read and write | `publish_change` opens or reuses a pull request; `check_status` lists them |
| Commit statuses | read | `check_status` reads the checks on the change |
| Actions | read | `check_status` reads workflow runs |
| Metadata | read | implied by any fine-grained token |

Source: GitHub's *Permissions required for fine-grained personal access tokens* page, read
2026-09-30. Why not the workflow's own `GITHUB_TOKEN`: an event it creates starts no workflow
run, so a pull request it opened would get no CI, and `deliver` reads that CI.

Set an expiry and put a reminder on it; a run after expiry fails at *Point git at the route's
token* with `gh auth status` naming the problem.

## 4. The route policy

`.ai/route-policy.yaml` is committed, and changed only through a pull request. Its shape and rules
are `plugins/agentic-core/shared/route-policy.md`. It holds the tool rules a run may never execute,
the daily run limits, the per-run budget, the turn and time caps, and the break-glass approvers. If
it is missing or invalid, every run stops at *Check the route policy* and nothing is started.

- **Break-glass:** an approver comments `@agentic-run override` to start one run over the daily
  limits. The tracker rule turns that into the payload's `override` field (rule version 2,
  `triggers/jira/README.md`). By hand: tick *override* in *Run workflow*.
- **Rate limited** in a run's summary means the daily limit stopped the event before it claimed
  anything. A later comment can run.

## 5. Verifying the setup

Trigger the workflow by hand: *Actions → route-trigger → Run workflow* with a real work item id
and any fresh integer as the comment id. A correct setup shows, in the run log:

1. *Name what cannot authenticate headlessly* — lists the packs and their variables; the
   `design` role (figma) has no headless credential path and says so.
2. *Point git at the route's token* — `gh auth status` reports the token from `GH_TOKEN`.
3. *Claim the event* — `claimed agentic-run/<item>-c<comment>`.
4. *Run* — the runner's log ends with `ended: subtype=success`.
5. *Validate the result envelope* — `verdict: pass`.
6. *Check that no credential reached the disk* — `found in 0 file(s)` for each secret.

Run it a second time with the same comment id: the duplicate check stops it. Run it a third time
with *skip duplicate check* ticked: the claim stops it (`duplicate`, exit 3). Both end green with
nothing started.

## 6. What is not covered

- The `design` role (`plugins/figma`) authenticates through a session-bound login that has no
  environment-variable form. A work item whose design source is a URL fails at `extract` until
  Phase 10 lands. An image attached to the item works.
- The daily limits are soft: two events counted at the same moment can both start.
- The budget stops a run once it is exceeded, so a run can overshoot it by about one turn's cost.
