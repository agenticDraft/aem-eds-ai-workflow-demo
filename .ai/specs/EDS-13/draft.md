---
item_type: Story
summary: Button block with green variation
item_id: EDS-13
---

## Description

Add a button block at blocks/button/ (blocks/button/button.js, blocks/button/button.css) so an
author can place a standalone call-to-action link through a block table, and add a `green`
variation of that block styled to the design reference below.

Today this project has no blocks/button/ directory. Buttons are default content: decorateButtons
in scripts/scripts.js turns an emphasised link into a.button and assigns primary, secondary or
accent from the authored emphasis, and styles/styles.css carries the shared button styling. All
three emphasis combinations are already taken, so a further variation cannot be selected that
way. The new block supplies the missing selection mechanism — the author names the variation on
the block table — while continuing to reuse the existing global button styling rather than
restating it.

The shared a.button rule in styles/styles.css carries geometry only — box model, border radius,
padding and type — and no fill or text colour; every colour in the project's buttons comes from
the primary, secondary or accent class. So a block instance with no variation name has no colour
to inherit, and must not invent one.

## Design reference

https://www.figma.com/design/B1rwvloGdmUrozvkBQ0vKP/Zoki?node-id=1-185

The node is a single button component instance, 138 by 48 pixels, not a page frame, so it fixes
the button's own appearance rather than a viewport width.

attached: design-reference.png — a capture of that same node, carrying its colours but no
machine-readable values.

## Content

Two block instances, so the variation case and the no-variation case are both authored. Both
carry the same link text.

- Button (green): Discover More
- Button: Discover More

## Acceptance criteria

AC-1 A block directory blocks/button/ exists.
AC-2 The block renders an authored link as a button.
AC-3 The green variation is selected by naming it on the block table, leaving unchanged how every
     existing button is authored.
AC-4 The green variation renders with the background colour, border colour and text colour shown
     in the design reference.
AC-5 Every colour value applied resolves to an adopted design-system token where the project
     defines an equivalent colour.
AC-6 A colour value with no project-defined equivalent token is the only kind taken raw from the
     design.
AC-7 The block reuses the project's existing global button styling, declaring no button sizing,
     border radius or typography of its own.
AC-8 The block's stylesheet declares colour only within the green variation's own scope.
AC-9 A block instance placed without a variation name renders with the border radius, padding,
     font weight and line height the project's shared a.button rule declares.
AC-10 No button outside blocks/button/ changes appearance as a result of this work.
AC-11 The block's rendered layout holds at every breakpoint the project defines.
AC-12 A page containing the block loads with no new console errors.

## Out of scope

Any change to the shared button rules in styles/styles.css, and any change to decorateButtons in
scripts/scripts.js. Any change to blocks/cards/ or to the button colour inside any other block —
EDS-13 does not cover the cards button work. Any further button variation, size or state beyond
the green variation. Any hover, focus or disabled treatment not shown in the design reference.
Giving a no-variation instance a fill or text colour of its own: the project's shared rule
defines none, and this item does not add one.
