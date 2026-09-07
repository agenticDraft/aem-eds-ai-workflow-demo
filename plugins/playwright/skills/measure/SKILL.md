---
description: browser.measure — loads a target URL and returns each named CSS selector's geometry and computed style values (color, background-color, font-family, font-size, font-weight, line-height) from a real headless Chromium. Requires the playwright npm package installed on this machine and its Chromium browser binary downloaded (npx playwright install chromium).
---

# measure

Implements the `browser` role's `measure` operation: load a target URL and return, for each named
CSS selector, its geometry and a fixed set of computed style values from a real headless Chromium
browser. A selector matching the first element in document order is used; a selector matching
nothing is reported as not found rather than failing the whole operation.

## Input

One line naming the target, then one or more selector lines:

```
target: <a target URL, including scheme>
selector: <a CSS selector>
selector: <a CSS selector>
…
```

## What to do

1. Run `${CLAUDE_PLUGIN_ROOT}/skills/measure/scripts/measure.cjs <target> <selector> [selector...]`,
   substituting the `target` value and passing every `selector` line as its own argument, in order.
2. Output the script's entire stdout, unchanged, as your entire response. Do not add commentary,
   reformat it, or summarize it — the script's own output already ends with the `## Result` block
   this operation must return (see the `agentic-core` plugin's `shared/result-envelope.md`, which
   this pack depends on, for the exact shape).

The script alone decides `pass` versus `fail` from the live navigation outcome; nothing here makes
that decision, so there is no branch in this skill's own control flow.
