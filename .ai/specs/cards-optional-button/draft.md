---
item_type: Story
summary: Optional CTA button on cards
labels: []
components: [cards]
---

## Description

Extend the existing blocks/cards/ block (blocks/cards/cards.js, blocks/cards/cards.css) so a
single card can optionally carry a call-to-action button below its body text. The button is off
by default: an author adds one to a specific card by authoring a link at the end of that card's
content, with its own visible text. A card authored without such a link is unaffected.

## Design reference

attached: cards-button-placement.png — a wireframe of a four-card row, two cards carrying a
button below the body text and two without one. It shows placement and optionality only:
placeholder label text, no new visual button styling. Reused as-is once attached to the real
item; not yet attached to this draft (see hand-over notes).

## Acceptance criteria

AC-1 A card authored with a button link at the end of its content renders that link as a button,
     through the project's existing global button convention, with no duplicate button styling
     added in blocks/cards/cards.css.
AC-2 A card authored without a button link renders exactly as it does today, with no button
     element present.
AC-3 A card's button opens its link in a new browser tab.
AC-4 A card's button, where present, sits below that card's body text, regardless of whether
     other cards in the same row carry one.
AC-5 The page loads with no new console errors.

## Out of scope

Support for more than one button per card. New button visual variants beyond the project's
existing global button convention. Any change to another block, and any change to the global
button styles themselves.
