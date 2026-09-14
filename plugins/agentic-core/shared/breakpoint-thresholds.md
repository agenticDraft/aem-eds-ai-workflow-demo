---
description: The breakpoint-threshold derivation — how a list of design frame widths becomes a list of switch points. Every reader or writer of a derived threshold references this file rather than restating the rule inline.
---

# Breakpoint thresholds

Pure arithmetic, no I/O: given the widths of a project's design frames, derive the widths at
which a layout should switch. Names no platform, no design tool and no unit — a width is a bare
number; where it came from and what unit it is in is the caller's concern, not this contract's.

## The rule

A design frame's width is a *canvas width* — the design source's own statement of what one layout
looks like. It is not a threshold: reading a frame width directly as the switch point gives a
design its own width as its own switch point, so a viewport just past it still renders the
narrower layout.

Instead: sort every given width ascending. The smallest is the **base** — the layout with no
threshold, the one every narrower viewport also gets. Every adjacent pair's threshold is the
**geometric mean of the two widths, rounded to the nearest 50**: `round(√(low × high), nearest 50)`.
Geometric rather than arithmetic mean because a layout's distortion is experienced as a
*proportional stretch*, not a fixed difference — the geometric mean is the point where that
stretch is equal in both directions.

Worked example, three frames at 375 / 800 / 1280:

- base: 375 (no threshold)
- `√(375 × 800) ≈ 548 → 550`
- `√(800 × 1280) ≈ 1012 → 1000`

A rounded threshold can never equal one of the input widths: two adjacent widths that were
themselves equal would produce a geometric mean equal to both, which is the exact defect this
rule exists to prevent, so the deriving script refuses that input rather than silently producing
a threshold indistinguishable from a frame width.

## Verification

`lib/derive-breakpoints.sh <width> [<width> ...]` is the deterministic deriver — no model
involved, and no file, network, or environment access of any kind. Exits `0` and prints one row
per line, tab-separated:

```
base	<smallest width>
threshold	<low>	<high>	<sqrt(low*high) rounded to the nearest integer>	<that value rounded to the nearest 50>
```

Exits `2` for a usage error: no width given, a width that is not a positive number, or two widths
equal to each other.

```bash
bash plugins/agentic-core/shared/lib/derive-breakpoints.test.sh
```

## Reference, not restatement

A skill or script that derives or displays a breakpoint threshold references this file with one
line rather than restating the geometric-mean rule inline, the same convention `design-manifest.md`
and `progress-output.md` use for their own contracts.

## Fixtures

`fixtures/breakpoints/` holds:

- `frame-widths.txt` — the worked example above (375 / 800 / 1280), one width per line.
- `frame-widths-unsorted.txt` — the same three widths, given out of order, proving order does not
  affect the result.
- `single-width.txt` — one width; the base row only, no threshold.
- `duplicate-widths.txt` — two frames sharing a width, for the rejection case.
- `negative-width.txt` — a non-positive width, for the rejection case.

## Where the widths come from

A platform pack that has run design-system onboarding already has every frame width on disk in
the design manifest's `frames` list (`design-manifest.md`, core contract §6.2) — this contract
derives from a list of numbers handed to it and calls the design role for nothing.
