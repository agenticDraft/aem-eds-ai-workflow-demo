---
item_type: Story
summary: Features carousel block
item_id: EDS-5
labels: []
components: [features-carousel]
---

## Description

Add a new "Features Carousel" block: a two-column section with a title, a short intro
paragraph, a numbered list of feature callouts, and a button on the left, paired with a
product image on the right. This is a new block at blocks/features-carousel/ — no existing
block in this project covers this layout or content shape.

## Design reference

https://www.figma.com/design/B1rwvloGdmUrozvkBQ0vKP/Zoki?node-id=1-167

## Content

Title: "See the Big Picture"

Intro: "Area turns your data into clear, vibrant visuals that show you exactly what's
happening in each region."

Numbered list (01-04), each a short bolded lead-in plus a sentence:

1. Spot Trends in Seconds — No more digging through numbers.
2. Get Everyone on the Same Page — Share easy-to-understand reports with your team.
3. Make Presentations Pop — Interactive maps and dashboards keep your audience engaged.
4. Your Global Snapshot — Get a quick, clear overview of your entire operation.

A primary button (label per design), and a product image alongside the text column.

## Acceptance criteria

AC-1 A block directory blocks/features-carousel/ exists, authored through the project's
     standard table-based content model.
AC-2 The rendered block's layout matches the design's two-column composition — the text
     column (title, intro, numbered list, button) on the left, the product image on the
     right — at the design's own frame width.
AC-3 Every spacing, type-scale and colour value in the rendered block resolves to an
     adopted design-system token where the project defines an equivalent.
AC-4 A value with no project equivalent is the only kind taken raw from the design.
AC-5 The numbered list renders through the project's existing global styles.
AC-6 The button renders through the project's existing global styles, with no duplicate
     button styling added by the block.
AC-7 The block's layout holds at every project breakpoint, not only at the design frame
     width.
AC-8 The page loads with no new console errors.
AC-9 The block's decorate() follows this project's existing block conventions (e.g.
     async decorate()).

## Out of scope

Any change to another block, and any change to the global styles themselves.
