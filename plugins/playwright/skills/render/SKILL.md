---
description: browser.render — loads a target URL in a real headless Chromium and reports its load state (final URL, HTTP status, title, console errors). Requires the playwright npm package installed on this machine and its Chromium browser binary downloaded (npx playwright install chromium).
---

# render

Implements the `browser` role's `render` operation: load a target URL in a real headless
Chromium browser and report its load state.

## Input

One line in the invocation argument:

```
target: <a target URL, including scheme>
```

## What to do

1. Run `${CLAUDE_PLUGIN_ROOT}/skills/render/scripts/render.cjs <target>`, substituting the
   `target` value given above.
2. Output the script's entire stdout, unchanged, as your entire response. Do not add commentary,
   reformat it, or summarize it — the script's own output already ends with the `## Result` block
   this operation must return (see the `agentic-core` plugin's `shared/result-envelope.md`, which
   this pack depends on, for the exact shape).

The script alone decides `pass` versus `fail` from the live navigation outcome; nothing here makes
that decision, so there is no branch in this skill's own control flow. `verdict: pass` means the
page's state was observed, including an error status such as HTTP 404 or 500 — `verdict: fail` is
reserved for the load never completing at all (DNS failure, connection refused, timeout) or the
browser itself being unavailable.
