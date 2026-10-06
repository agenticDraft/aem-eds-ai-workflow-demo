---
item_type: Story
summary: Logo cloud block
item_id: EDS-20
---

## Description

Add a logo cloud block at blocks/logo-cloud/ (blocks/logo-cloud/logo-cloud.js,
blocks/logo-cloud/logo-cloud.css), which this project does not yet have, styled to the design
references below.

The block renders a set of authored logo images as one row that wraps: at the widest width every
logo sits in a single row, and at narrower widths the logos flow into as many rows as fit, with a
row that is not full centred. Nothing scrolls, nothing is hidden and there are no controls. The
design gives three widths; this project defines a single breakpoint, so the tablet and mobile
arrangements are both the below-breakpoint case and differ only in how many logos fit a row.

blocks/cards/ renders a list of image-plus-body cards and blocks/columns/ lays out a fixed number of
columns, and neither wraps a run of bare images, so there is nothing here to extend.

## Design reference

Desktop, 1200 wide, six logos in one row:
https://www.figma.com/design/B1rwvloGdmUrozvkBQ0vKP/Zoki?node-id=1-126

Tablet, 720 wide, four logos in the first row and two centred in the second:
https://www.figma.com/design/B1rwvloGdmUrozvkBQ0vKP/Zoki?node-id=1-282

Mobile, 375 wide, two columns and three rows:
https://www.figma.com/design/B1rwvloGdmUrozvkBQ0vKP/Zoki?node-id=1-435

attached: design-reference.png — a capture of the desktop node, 1200 by 84 pixels.
attached: design-reference-tablet.png — a capture of the tablet node, 720 by 184 pixels.
attached: design-reference-mobile.png — a capture of the mobile node, 375 by 437 pixels; it
includes the "Trusted by:" line above the logos, which is default content and not part of the
block.

The desktop capture is what AC-3 and AC-7 are compared against at the widest project breakpoint;
the tablet and mobile captures are what AC-4, AC-5 and AC-7 are compared against below it.

## Authoring

One column, one row per logo, image only:

| Logo cloud |
| logo image |
| logo image |
| logo image |
| logo image |
| logo image |
| logo image |

## Content

Six logos, in the order the design shows them, each an image exported from the named desktop node
with the alt text given:

Logo 1: node 1-128, alt text "Logo 1"
Logo 2: node 1-130, alt text "Logo 2"
Logo 3: node 1-132, alt text "Logo 3"
Logo 4: node 1-134, alt text "Logo 4"
Logo 5: node 1-136, alt text "Logo 5"
Logo 6: node 1-138, alt text "Logo 6"

The "Trusted by:" line above the logos in the design is a plain paragraph authored before the
block, not part of it.

## Acceptance criteria

AC-1 A block directory blocks/logo-cloud/ exists.
AC-2 Each authored row renders as one logo image.
AC-3 At the widest project breakpoint, all six logos render in a single row, as laid out in the
     desktop design reference.
AC-4 Below the widest project breakpoint, the logos wrap into as many rows as the viewport needs,
     as laid out in the tablet and mobile design references.
AC-5 A row that is not full renders centred, as the tablet design reference shows for its second
     row.
AC-6 No logo is clipped or reachable only by scrolling at any project breakpoint.
AC-7 Every logo renders inside a cell of the size and spacing shown in the design reference at the
     matching width.
AC-8 Each logo image is served with responsive sources, as the project's other image-bearing
     blocks serve theirs.
AC-9 Each logo image carries the authored alt text.
AC-10 Every colour value applied resolves to an adopted design-system token where the project
     defines an equivalent colour.
AC-11 A colour value with no project-defined equivalent token is the only kind taken raw from the
     design.
AC-12 The block's rendered layout holds at every breakpoint the project defines.
AC-13 A page containing the block loads with no new console errors.

## Out of scope

Any change to another block, and any change to the shared styles in styles/styles.css. Any
carousel, slider, auto-scroll or other motion. Any link on a logo. Any hover or colour treatment
of the logos, which are grey in the exported images themselves. The "Trusted by:" line. A second
project breakpoint. Any authored content beyond the six logos given above.
