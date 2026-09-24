---
item_type: Story
summary: Feature comparison table block
item_id: EDS-18
---

## Description

Add a table block at blocks/table/ (blocks/table/table.js, blocks/table/table.css), which this
project does not yet have, and give it a `comparison` variation styled to the design reference
below.

The base block renders an authored block table as a semantic table, the same way the upstream block
collection's own table block does — a header row of column headings, then one row per feature. The
`comparison` variation adds what the design shows on top of that: the first data column emphasised
against the others, and a mark on every cell saying whether that product supports the feature.

No block in this project builds a table today, and blocks/columns/ handles multi-column layout
rather than tabular data, so there is nothing here to extend.

## Design reference

https://www.figma.com/design/B1rwvloGdmUrozvkBQ0vKP/Zoki?node-id=1-195

attached: design-reference.png — a capture of that same node, 1364 by 654 pixels, showing the three
columns, the emphasised first column, and the supported/unsupported mark on each cell.

**The reference represents one viewport width only, a wide one.** It shows the table laid out with
all three columns side by side, which is what AC-5, AC-6 and AC-7 are compared against. It says
nothing about narrower widths, so AC-11 is satisfied by the table remaining readable and unbroken at
the project's other breakpoints — not by matching this capture at them.

## Content

Column headings: Area, WebSurge, HyperView

Row 1: Ultra-fast browsing (supported) | Fast browsing (supported) | Moderate speeds (unsupported)
Row 2: Advanced AI insights (supported) | Basic AI recommendations (supported) | No AI assistance (unsupported)
Row 3: Seamless integration (supported) | Restricts customization (supported) | Steep learning curve (unsupported)
Row 4: Advanced AI insights (supported) | Basic AI insights (unsupported) | No AI assistance (unsupported)
Row 5: Ultra-fast browsing (supported) | Fast browsing (supported) | Moderate speeds (unsupported)
Row 6: Full UTF-8 support (supported) | Potential display errors (unsupported) | Partial UTF-8 support (unsupported)

## Acceptance criteria

AC-1 A block directory blocks/table/ exists.
AC-2 The block renders an authored block table as a semantic table element.
AC-3 The first authored row renders as the table's column headings.
AC-4 The comparison variation is selected by naming it on the block table.
AC-5 In the comparison variation, the first data column renders with the emphasis shown in the
     design reference.
AC-6 Every cell renders the supported or unsupported mark shown for it in the design reference.
AC-7 A cell's supported or unsupported state is conveyed by something other than colour alone.
AC-8 Every colour value applied resolves to an adopted design-system token where the project
     defines an equivalent colour.
AC-9 A colour value with no project-defined equivalent token is the only kind taken raw from the
     design.
AC-10 The block placed without the comparison variation renders as a plain semantic table, with
     none of that variation's emphasis or marks.
AC-11 The block's rendered layout holds at every breakpoint the project defines.
AC-12 A page containing the block loads with no new console errors.

## Out of scope

Any change to another block, and any change to the shared styles in styles/styles.css. Any sorting,
filtering, row selection or other interactive behaviour. Any variation beyond `comparison`. Any
authored content beyond the rows given above. Any responsive treatment not shown in the design
reference, such as collapsing the table into cards on a narrow viewport.
