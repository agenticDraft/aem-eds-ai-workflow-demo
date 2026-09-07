---
description: browser.capture — loads a target URL and captures a full-page screenshot at a given viewport width in a real headless Chromium. Requires the playwright npm package installed on this machine and its Chromium browser binary downloaded (npx playwright install chromium).
---

# capture

Implements the `browser` role's `capture` operation: load a target URL and capture a full-page
screenshot at a given viewport width from a real headless Chromium browser.

## Input

Two lines in the invocation argument:

```
target: <a target URL, including scheme>
width: <viewport width in pixels, a positive integer>
```

## What to do

1. Run `${CLAUDE_PLUGIN_ROOT}/skills/capture/scripts/capture.cjs <target> <width>`, substituting
   the `target` and `width` values given above.
2. Output the script's entire stdout, unchanged, as your entire response. Do not add commentary,
   reformat it, or summarize it — the script's own output already ends with the `## Result` block
   this operation must return (see the `agentic-core` plugin's `shared/result-envelope.md`, which
   this pack depends on, for the exact shape).

The script alone decides `pass` versus `fail` from the live navigation outcome; nothing here makes
that decision, so there is no branch in this skill's own control flow.
