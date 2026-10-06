---
item_type: Story
summary: Testimonial quote block
item_id: EDS-19
components: [quote]
---

## Description

Add a quote block at blocks/quote/ (blocks/quote/quote.js, blocks/quote/quote.css), which this
project does not yet have, and give it a `testimonial` variation styled to the design reference
below.

The base block renders an authored quotation as a semantic blockquote, the same way the upstream
block collection's own quote block does — the first authored row is the quotation, an optional
second row is the attribution, and italic text inside the attribution is the citation. The
`testimonial` variation adds what the design shows on top of that: an authored image beside the
quotation, the person's name as the attribution and their role as the citation in the distinct
style the design gives it.

No block in this project renders a quotation today, and blocks/columns/ lays an image beside text
without any quotation semantics, so there is nothing here to extend.

## Design reference

Desktop, 1200 wide, image on the left and quotation on the right:
https://www.figma.com/design/B1rwvloGdmUrozvkBQ0vKP/Zoki?node-id=1-223

Tablet, 720 wide, image above the quotation:
https://www.figma.com/design/B1rwvloGdmUrozvkBQ0vKP/Zoki?node-id=1-379

Mobile, 375 wide, image above the quotation with a rule between them:
https://www.figma.com/design/B1rwvloGdmUrozvkBQ0vKP/Zoki?node-id=1-534

attached: design-reference.png — a capture of the desktop node, 1200 by 790 pixels, showing the
image on the left, the quotation in large serif type on the right, and below it the name in the
body typeface and the role in the green monospace treatment on its own line.
attached: design-reference-tablet.png — a capture of the tablet node, 720 by 1256 pixels, showing
the image full width above the quotation, and the name and role together on one line.
attached: design-reference-mobile.png — a capture of the mobile node, 375 by 909 pixels, showing
the image full width above a horizontal rule, then the quotation, and the name and role together
on one line.

The desktop capture is what AC-8, AC-9 and AC-10 are compared against at the widest project
breakpoint; the tablet and mobile captures are what they are compared against below it. This
project defines a single breakpoint, so the tablet and mobile arrangements are both the
below-breakpoint case.

## Authoring

Base block, one column, two rows; the second row is optional:

| Quote |
| “quotation text” |
| Name *Role* |

Testimonial variation, one column, three rows; the first row holds the image:

| Quote (testimonial) |
| image |
| “quotation text” |
| Name *Role* |

In the attribution row the name comes first and the role follows it in italics on its own line; the
italic text is what renders as the citation.

## Content

Image: the photograph in the design node, exported from node 1-224, alt text "Stacked stone
spheres".

Quotation: “I was skeptical, but Area has completely transformed the way I manage my business. The
data visualizations are so clear and intuitive, and the platform is so easy to use. I can't imagine
running my company without it.”

Attribution name: John Smith
Attribution role: Head of Data

## Acceptance criteria

AC-1 A block directory blocks/quote/ exists.
AC-2 The authored quotation renders inside a blockquote element.
AC-3 An authored attribution row renders inside the same blockquote, after the quotation.
AC-4 Italic text in the attribution row renders as a cite element.
AC-5 The quotation renders with exactly one pair of quotation marks around it.
AC-6 The block placed without an attribution row renders the quotation alone, with no empty
     attribution element.
AC-7 The testimonial variation is selected by naming it on the block table.
AC-8 In the testimonial variation, the authored image and the quotation render in the arrangement
     the design reference shows for the matching width.
AC-9 In the testimonial variation, the quotation renders in the type treatment shown in the design
     reference.
AC-10 In the testimonial variation, the citation renders in the distinct treatment the design
     reference gives the role line.
AC-11 In the testimonial variation, the image is served with responsive sources, as the project's
     other image-bearing blocks serve theirs.
AC-12 Every colour value applied resolves to an adopted design-system token where the project
     defines an equivalent colour.
AC-13 A colour value with no project-defined equivalent token is the only kind taken raw from the
     design.
AC-14 The block's rendered layout holds at every breakpoint the project defines.
AC-15 The block placed without the testimonial variation renders none of that variation's
     layout.
AC-16 A page containing the block loads with no new console errors.

## Out of scope

Any change to another block, and any change to the shared styles in styles/styles.css. Any
rotation, carousel or slider of several testimonials. Any variation beyond `testimonial`. Any
authored content beyond the quotation, name, role and image given above. Any responsive treatment
not shown in the design reference, such as a specific stacking order on a narrow viewport.
