---
item_type: Bug
summary: Cards block never marks its first image eager
components: [cards]
---

## Description

`scripts/aem.js`'s `createOptimizedPicture(src, alt, eager, breakpoints)` takes an `eager`
parameter (its third argument) that the function passes through to the fallback `<img>`'s
`loading` attribute. `blocks/cards/cards.js` line 15 calls it inside a `forEach` over every
`picture > img` element found in the block, always passing the literal `false`:

```
ul.querySelectorAll('picture > img').forEach((img) => img.closest('picture').replaceWith(createOptimizedPicture(img.src, img.alt, false, [{ width: '750' }])));
```

Every image the cards block renders is therefore built with `eager: false`, including the very
first one in document order.

## Steps to reproduce

1. Open https://main--aem-eds-ai-workflow-demo--agenticDraft.aem.page/ (or any page authoring a
   cards block with at least two image cards)
2. Inspect the rendered markup inside `blocks/cards/cards.js`'s output `<ul>`
3. Read the `loading` attribute on the `<img>` inside the first `<li>`'s `picture`, and on the
   `<img>` inside every later `<li>`'s `picture`

Expected: the first image's `<img>` carries `loading="eager"`; every later image's `<img>` keeps
`loading="lazy"`.
Actual: every image's `<img>`, first included, carries `loading="lazy"` — `createOptimizedPicture`
was called with `eager: false` on all of them.

## Acceptance criteria

AC-1 In `blocks/cards/cards.js`, the first element (index 0) returned by
     `querySelectorAll('picture > img')` is passed to `createOptimizedPicture` with its `eager`
     argument set to `true`.
AC-2 Every element after index 0 returned by that same `querySelectorAll('picture > img')` call
     keeps `eager: false`.
AC-3 No argument to `createOptimizedPicture` other than `eager` changes for any image, on any
     call.
AC-4 No other behavior of the cards block changes — the `cards-card-image`/`cards-card-body`
     classification and the `<ul>`/`<li>` restructuring are unaffected.
AC-5 The page loads with no new console errors.

## Out of scope

`blocks/columns/columns.js` and `blocks/features-carousel/features-carousel.js`, which call
`createOptimizedPicture` with the same hardcoded `false` and have the identical defect — tracked
separately, not fixed by this item.
