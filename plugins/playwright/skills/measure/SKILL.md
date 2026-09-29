---
description: browser.measure — loads a target URL and returns each named CSS selector's geometry and computed style values (color, background-color, font-family, font-size, font-weight, line-height, padding-top, padding-right, padding-bottom, padding-left, gap, border-radius), plus whether any element the selector matches holds text, from a real headless Chromium. Its preconditions are declared in this pack's manifest; a missing one is reported in the envelope with the remedy the manifest states.
---

# measure

Implements the `browser` role's `measure` operation: load a target URL and return, for each named
CSS selector, its geometry and a fixed set of computed style values from a real headless Chromium
browser. A selector matching the first element in document order is used; a selector matching
nothing is reported as not found rather than failing the whole operation.

The computed values are exactly `color`, `background-color`, `font-family`, `font-size`,
`font-weight`, `line-height`, `padding-top`, `padding-right`, `padding-bottom`, `padding-left`, `gap`
and `border-radius`, each as the browser's computed string. Padding is reported as the four
longhands only, never a shorthand; `border-radius` is one string, a single length when all four
corners are equal.

Each found selector also carries `holds_text`: `true` when any element the selector matches, not
only the first, has a descendant text node that is not only whitespace, else `false`. It sits
beside `geometry`, not among the computed values, and is never compared as a style value. A
consumer uses it to tell an element that holds text from one that holds only an image or an icon.

The read is taken only once the page has settled:

- every named selector that matches an element matches a visible one (a non-empty box, not
  `visibility: hidden`);
- the document's fonts have finished loading;
- two consecutive snapshots of every selector, taken 250 ms apart, are identical.

The wait is bounded at 10 s. A page that does not settle within it fails, with the reason in the
envelope's `summary`, and no file is written; an unsettled read is never returned. A selector that
matches nothing is not waited for, and is reported as not found (`found: false`) once the page has
settled.

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

The script alone decides `pass` versus `fail` from the live navigation and settle outcome; nothing here makes
that decision, so there is no branch in this skill's own control flow.
