# aem-eds-ai-workflow-demo
AEM EDS demo with AI workflow

## Environments

- Preview: https://main--aem-eds-ai-workflow-demo--agenticDraft.aem.page/
- Live: https://main--aem-eds-ai-workflow-demo--agenticDraft.aem.live/
- Content source (Google Drive):
  https://drive.google.com/drive/folders/1f0yNL8IysQGG0QNzo7sJg8CcpgORXwWY

AEM Code Sync is enabled on the GitHub repo; pushes to a branch publish to
`https://{branch}--aem-eds-ai-workflow-demo--agenticDraft.aem.page/`.

## Documentation

Before using this project, go through the documentation on https://www.aem.live/docs/ and more specifically:
1. [Developer Tutorial](https://www.aem.live/developer/tutorial)
2. [The Anatomy of a Project](https://www.aem.live/developer/anatomy-of-a-project)
3. [Web Performance](https://www.aem.live/developer/keeping-it-100)
4. [Markup, Sections, Blocks, and Auto Blocking](https://www.aem.live/developer/markup-sections-blocks)

## Installation

```sh
npm i
```

`@adobe/aem-cli` is a devDependency, so this installs it too — no global install needed.

## Local development

1. Install the Chrome extension [AEM Sidekick](https://chromewebstore.google.com/detail/aem-sidekick/igkmdomcgoebiipaifhmpfjhbjccggml)
2. Start the dev server: `npm run up` — serves `http://localhost:3000` with auto-reload
   - `npm run up:draft` serves static files from `drafts/` instead of authored content
3. Open this directory in your favorite IDE and start coding :)

## Linting

```sh
npm run lint       # eslint + stylelint
npm run lint:fix   # auto-fix what can be fixed
```

Always go through the npm script. `lint:js` loads a project-local ESLint rule via
`--rulesdir scripts/eslint-rules`; a bare `eslint .` silently skips it.

## Credentials

This project's automation never creates or edits `.claude/settings.local.json` — you manage it
yourself. It is gitignored and personal, never `.claude/settings.json`, which is shared. Add an
`env` block with these four variables (create the file if you don't have it yet):

| Variable | Purpose |
| --- | --- |
| `JIRA_SITE` | Your Atlassian Cloud site, e.g. `your-site.atlassian.net` |
| `JIRA_EMAIL` | The email address of the Jira account the token belongs to |
| `JIRA_API_TOKEN` | A token from https://id.atlassian.com/manage-profile/security/api-tokens |
| `GH_TOKEN` | A GitHub fine-grained personal access token, scoped to this repo, with Contents and Pull requests read/write |

The pipeline also calls your Atlassian Cloud site directly (`https://<your-site>.atlassian.net`),
not just `api.atlassian.com`. Since that hostname is specific to your Jira instance, add it to the
same file's sandbox allowlist — Claude Code merges it with the shared `.claude/settings.json`
allowlist, so you don't need to touch the committed file:

```json
{
  "env": {
    "JIRA_SITE": "your-site.atlassian.net",
    "JIRA_EMAIL": "you@example.com",
    "JIRA_API_TOKEN": "your_api_token_here",
    "GH_TOKEN": "your_github_token_here"
  },
  "sandbox": {
    "network": {
      "allowedDomains": ["<your-site>.atlassian.net"]
    }
  }
}
```

Claude Code loads this file's `env` block into every session's subprocesses, foreground or
backgrounded — which is what a `run-route` invocation needs, since it runs detached. Every script
and skill in the pipeline reads these variables from the environment, never as a command-line
argument, so they never appear in `ps -ef`, shell history, or a log.

**The `scm` pack (`plugins/github/`) authenticates through the `gh` CLI, which reads `GH_TOKEN`
from the environment before it ever needs its own keychain-backed login.** `gh`'s own local
credential store (`gh auth login`) still works for your own interactive use of `gh` elsewhere on
this machine, but the pipeline's stages run as sandboxed subprocesses that cannot read that
keychain — so `GH_TOKEN` above is required for the pipeline specifically, not optional the way
`gh auth login` alone might suggest.

**The `design` pack (`plugins/figma/`) also needs no entry here.** It calls the Figma MCP server
through the official `figma` Claude Code plugin instead. Install it once
(`claude plugin install figma@claude-plugins-official` or via `/plugin`) and complete its OAuth
flow in a Claude Code session — the plugin's own `authenticate` tool opens a browser link for you
to approve. This means the operation only runs inside a session where that plugin is installed
and already authenticated, unlike the `tracker`/`scm` packs, which run unattended.

## Claude Code setup

This project's agent instructions (`AGENTS.md`, `CLAUDE.md`) delegate all Edge Delivery *platform*
reference to Adobe's first-party skills rather than restating it. Install them once, or the
agent will hit instructions pointing at skills that do not resolve.

```sh
claude plugin marketplace add adobe/skills
claude plugin install aem-edge-delivery-services@adobe-skills
```

Or from inside a Claude Code session, using the slash command and the interactive picker:

```
/plugin marketplace add adobe/skills
/plugin
```

Verify — the plugin should be listed, and skills should resolve as
`aem-edge-delivery-services:<name>`:

```sh
claude plugin list | grep aem-edge-delivery-services
```

The plugin installs as one unit: **25 skills**, Apache-2.0, © Adobe. The ones this project's
instructions name are `content-driven-development` (the process every code change starts from),
plus `aem-cli`, `building-blocks`, `content-modeling`, `block-collection-and-party`,
`docs-search`, `testing-blocks`, `analyze-and-plan`, `find-test-content` and `da-content`. The
rest install alongside them and are available, but are not part of this project's documented
workflow.
