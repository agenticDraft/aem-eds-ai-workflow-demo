---
description: browser.interact — loads a target URL, acts on it (click, press a key, type into a field), and returns the resulting state (geometry, a fixed set of computed style values, and every aria-* attribute plus class) for one or more named selectors, snapshotted both before the first action and after the last one, from a real headless Chromium. Requires the playwright npm package installed on this machine and its Chromium browser binary downloaded (npx playwright install chromium).
---

# interact

Implements the `browser` role's `interact` operation: load a target URL, perform one or more
actions on it in order, then report the resulting state — not only load-time state, the state
*after* acting — for one or more named selectors, from a real headless Chromium browser. This is
the operation a check like "opening one item closes another" or "a key still toggles a control"
needs; `render`/`capture`/`measure` can only read a page as loaded, never act on it first (core
contract §6, D69).

An action naming a selector that matches nothing, or that Playwright cannot carry out, fails the
whole operation — an interaction that did not happen must never be reported as one that did. A
*read* selector matching nothing is reported `found: false` instead, the same non-failing reading
`measure` gives a missing selector, since a read is a passive observation made after the fact, not
a precondition the operation depends on.

## Input

One `target:` line, then one or more action lines and one or more `read:` lines, in any order —
actions run in the order given; every `read:` selector is snapshotted once before the first action
and once after the last one:

```
target: <a target URL, including scheme>
click: <a CSS selector>
press: <a key name>:<a CSS selector>
type: <text to type, must not contain ':'>:<a CSS selector>
read: <a CSS selector>
…
```

`press` focuses the matched element before dispatching the key, the same as a real keyboard user
tabbing to it first. `type` fills the matched element's value directly. At least one action and at
least one `read:` are required — an invocation with only `read:` lines is what `measure` is for.

## What to do

1. Build the script's argument list from the input lines, one argument per line, preserving order:
   the `target` value first, then one argument per remaining line rendered as `click:<selector>`,
   `press:<key>:<selector>`, `type:<text>:<selector>`, or `read:<selector>`.
2. Run `${CLAUDE_PLUGIN_ROOT}/skills/interact/scripts/interact.cjs <target> <op> [op...]` with that
   argument list.
3. Output the script's entire stdout, unchanged, as your entire response. Do not add commentary,
   reformat it, or summarize it — the script's own output already ends with the `## Result` block
   this operation must return (see the `agentic-core` plugin's `shared/result-envelope.md`, which
   this pack depends on, for the exact shape).

The script alone decides `pass` versus `fail` from the live actions' outcome; nothing here makes
that decision, so there is no branch in this skill's own control flow.
