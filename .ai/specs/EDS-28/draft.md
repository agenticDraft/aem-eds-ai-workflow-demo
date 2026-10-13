---
item_type: Story
summary: Link list block
item_id: EDS-28
---

## Description

Add a link list block at blocks/link-list/, authored through the project's standard content model.
It renders a short list of text links whose labels and URLs the author supplies. The markup is a
navigation landmark holding one unordered list with one anchor per item, so search engines and
assistive technology read it as a list of real links. That markup is a requirement of this item,
not an implementation choice. It renders no icons.

## Design reference

Desktop (1200 wide): https://www.figma.com/design/B1rwvloGdmUrozvkBQ0vKP/Zoki?node-id=1-258
Tablet (720 wide): https://www.figma.com/design/B1rwvloGdmUrozvkBQ0vKP/Zoki?node-id=1-414
Mobile (343 wide): https://www.figma.com/design/B1rwvloGdmUrozvkBQ0vKP/Zoki?node-id=1-569

The desktop and tablet frames show the links in one horizontal row; the mobile frame shows them
stacked in one column. This project defines a single breakpoint, 900 pixels, so the layout switches
there: at 720 pixels the block renders as a column, which deliberately differs from the tablet frame.

## Content

Benefits
Specifications
How-to

## Acceptance criteria

AC-1 A block directory blocks/link-list/ exists, authored through the project's standard content
     model.
AC-2 The rendered block contains exactly one nav element.
AC-3 The nav element has a non-empty accessible name.
     reference: https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/nav — a
     document may hold several nav elements, and labelling each is how they are told apart.
AC-4 The nav element contains exactly one ul element.
AC-5 Each authored link renders as one li element that is a direct child of that ul.
AC-6 The ul contains no li element beyond the authored links.
AC-7 Each li contains exactly one a element.
AC-8 Each a element's href equals the URL the author supplied for that item.
AC-9 Each a element's visible text equals the label the author supplied for that item.
AC-10 The block contains no img element.
AC-11 The block contains no svg element.
AC-12 Every authored link's URL is present in the HTML the server delivers for the page, before
      any script runs.
AC-13 Every authored link's label is present in the HTML the server delivers for the page, before
      any script runs.
AC-14 At every viewport width below 900 pixels, the links render stacked in one column, one link
      per line.
AC-15 At every viewport width of 900 pixels or more, the links render in one horizontal row.
AC-16 The space between two adjacent links is 27 pixels at every viewport width.
AC-17 The link text renders at a 14 pixel font size at every viewport width.
AC-18 The link text renders at font weight 700.
AC-19 The link text renders at line height 1.4.
AC-20 The link text renders in colour #000000.
AC-21 Every spacing, type-scale and colour value in the rendered block resolves to an adopted
      design-system token where the project defines an equivalent.
AC-22 A value with no project equivalent is the only kind taken raw from the design.
AC-23 A page containing the block loads with no new console errors.

## Out of scope

Icons of any kind, hover and focus styles beyond the project's global link styles, the design's
letter spacing, loading the design's typeface, a second breakpoint for the tablet frame, any other
block, and any change to the global styles.
