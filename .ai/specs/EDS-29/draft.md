---
item_type: Story
summary: List block
---

## Description

Add a list block at blocks/list/, which this project does not yet have, authored through the
project's standard content model. It renders a numbered list of short text items the author
supplies: each item shows a two-digit sequence number ("01", "02", ...) followed by its text, with a
thin divider above every item. The markup is one ordered list with one list item per authored row,
so search engines and assistive technology read it as a list. That markup is a requirement of this
item, not an implementation choice.

The block is independent. In the design it sits inside a carousel; the carousel is not part of this
item, and the block must render correctly on its own, directly in a page section, with no knowledge
of any carousel. The design shows the list as a block, whereas the AEM block collection treats
lists as default content (`<ol>` and `<ul>` with no JavaScript); this item asks for a dedicated
block so the numbered, divided presentation is available as a component.

## Design reference

Desktop (590 wide): https://www.figma.com/design/B1rwvloGdmUrozvkBQ0vKP/Zoki?node-id=1-172
Tablet (720 wide): https://www.figma.com/design/B1rwvloGdmUrozvkBQ0vKP/Zoki?node-id=1-328
Mobile (311 wide): https://www.figma.com/design/B1rwvloGdmUrozvkBQ0vKP/Zoki?node-id=1-483

The mobile link in the request pointed at the tablet node; node 1-483 is the List frame inside the
Mobile frame. The three frames share every value except two: wrapping follows the width, and the
desktop and tablet frames give each item 80 pixels of right padding where the mobile frame gives
none. This project defines a single breakpoint, 900 pixels, so the 80 pixels apply at 900 pixels
and up, and below it the list is full width. That deliberately differs from the tablet frame.

## Authoring

One column, one row per item, text only. The sequence number is not authored.

| List |
| item text |
| item text |
| item text |
| item text |

## Content

Four items, in this order:

Spot Trends in Seconds: No more digging through numbers.
Get Everyone on the Same Page: Share easy-to-understand reports with your team.
Make Presentations Pop: Interactive maps and dashboards keep your audience engaged.
Your Global Snapshot: Get a quick, clear overview of your entire operation.

## Acceptance criteria

AC-1 A block directory blocks/list/ exists, authored through the project's standard content model.
AC-2 The rendered block contains exactly one ol element.
AC-3 Each authored row renders as one li element that is a direct child of that ol.
AC-4 The ol contains no li element beyond the authored rows.
AC-5 Each li's text equals the text the author supplied for that row, with no sequence number in it.
AC-6 The text of every authored row is present in the HTML the server delivers for the page, before
     any script runs.
AC-7 Each item displays its sequence number before its text, as a two-digit number with a leading
     zero, starting at 01 and increasing by one per item.
AC-8 Placed directly in a page section with no carousel around it, the block displays every item
     with its sequence number and divider.
AC-9 Every selector in the block's stylesheet is scoped to the block.
AC-10 The block renders with no other block's script loaded.
AC-11 The block contains no button element.
AC-12 The block contains no horizontally scrolling container.
AC-13 Each item has a 1 pixel solid divider along its top edge, in colour #E9E9E9.
AC-14 The last item has no divider along its bottom edge.
AC-15 Each item has 20 pixels of padding at its top.
AC-16 Each item has 20 pixels of padding at its bottom.
AC-17 The space between an item's sequence number and its text is 30 pixels.
AC-18 The sequence number renders at a 15 pixel font size.
AC-19 The sequence number renders at font weight 700.
AC-20 The sequence number renders at line height 1.4.
AC-21 The sequence number renders in colour #6F6F6F.
AC-22 The item text renders at a 15 pixel font size.
AC-23 The item text renders at font weight 400.
AC-24 The item text renders at line height 1.4.
AC-25 The item text renders in colour #000000.
AC-26 When an item's text wraps, each continuation line starts at the same left edge as the first
      line of that text.
AC-27 When an item's text wraps, the sequence number stays beside the first line only.
AC-28 At every viewport width of 900 pixels or more, each item has 80 pixels of padding on its
      right.
AC-29 At every viewport width below 900 pixels, each item has no padding on its right.
AC-30 At a 311 pixel wide container, the items render with no horizontal scrolling.
AC-31 At a 311 pixel wide container, no item text is clipped.
AC-32 Every spacing, type-scale and colour value in the rendered block resolves to an adopted
      design-system token where the project defines an equivalent.
AC-33 A value with no project equivalent is the only kind taken raw from the design.
AC-34 A page containing the block loads with no new console errors.

## Out of scope

The carousel the design places the block in, the design's per-item aria-label text ("Area value prop
1 of 4"), the design's letter spacing, loading the design's typeface, a second breakpoint for the
tablet frame, aligning the text column across items whose numbers differ in width, any other block,
and any change to the global styles.
