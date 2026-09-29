Please always provide the [GitHub issue(s)](../issues) your PR is for, as well as test URLs where your change can be observed (before and after):

Fix #<gh-issue-id>

Test URLs:
- Before: https://main--{repo}--{owner}.aem.live/
- After: https://<branch>--{repo}--{owner}.aem.live/

Automation-only PR (no served path changed — only `plugins/`, `.claude/`, `.github/`, `docs/` or
Markdown): delete the test URLs. This PR is expected to fail `aem-psi-check`; the check is not
required. See `AGENTS.project.md`, Deployment.
