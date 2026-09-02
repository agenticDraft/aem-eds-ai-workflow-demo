# AGENTS.project.md

Project policy for this Edge Delivery Services site, built from `adobe/aem-boilerplate`. Follow
the boilerplate's style; add functionality as the site needs it.

Read `AGENTS.md` first — it is Adobe's upstream file, kept byte-identical so it stays mergeable.
This file is what *we* do on top of it, and never repeats a rule already stated there.

Both files load only when the work is EDS — never for delivery-automation work (D28, D34).

## Constraints — do not work around them

They are what lets an EDS site score 100/100/100/100 on Core Web Vitals.

- Vanilla JavaScript (ES6+). No TypeScript, no transpiling.
- Pure CSS3. No preprocessors, no Tailwind, no CSS framework.
- No frameworks. No React, Vue or similar.
- No runtime dependencies.
- HTML5 semantic markup served by the aem.live backend; our code decorates it.
- Docs at https://www.aem.live/ — restrict web searches with `site:www.aem.live`.

## Commands — these override the CLI in `AGENTS.md` and in Adobe's skills

- `npm install` — includes `@adobe/aem-cli` as a devDependency. Never install it globally, never
  run `npx @adobe/aem-cli` directly.
- `npm run up` — dev server at `http://localhost:3000`, auto-reload. Run it in the background.
  Open it with playwright or puppeteer; if neither is available, ask the human.
- `npm run up:draft` — serve static files from `drafts/` instead.
- `npm run lint` before committing; `npm run lint:fix` to auto-fix. **Always go through the npm
  script** — `lint:js` loads a project rule via `--rulesdir scripts/eslint-rules`, and a bare
  `eslint .` silently skips it.

## Structure

```
blocks/{name}/{name}.js, {name}.css   one directory per block
styles/styles.css                     global + LCP
styles/lazy-styles.css                below-the-fold
styles/fonts.css
scripts/aem.js                        vendored; import from it freely
scripts/scripts.js                    entry point; owns loadPage()
scripts/consent-check.js              delayed phase: consent gate
scripts/consented.js                  analytics/martech; loads only after consent
fonts/  icons/  tools/  head.html  404.html
```

A `fstab.yaml` is still committed at the root, pointing at a Google Drive folder. `AGENTS.md`
lists it as retired in favour of tools.aem.live. **Unverified which is authoritative for this
site** — do not delete it and do not add config to it until a human confirms where this site's
mountpoint actually lives.

## Code style

**JavaScript** — ES6+. Airbnb ESLint rules. Always include `.js` extensions in imports. Unix line
endings.

**CSS** — Stylelint standard. Grid, Flexbox, custom properties. Mobile first, range syntax:
`@media (width >= 900px)`. **900px is the only breakpoint in this project** — do not add another
without a design source, and add it to `styles/styles.css` first.

→ Full CSS conventions: the `building-blocks` skill, `references/css-guidelines.md`.

**HTML** — semantic elements, WCAG 2.1 AA, AEM markup conventions for blocks and sections.

## These files vs Adobe's skills

`AGENTS.md` and this file are project policy — what *we* do. Adobe's `aem-edge-delivery-services`
skills are the platform reference — how EDS works. Install them with the marketplace command in
`AGENTS.md`.

- **These files win** on house style, commands, deployment.
- **The skills win** on block anatomy, authored shapes, platform behaviour.
- Where they genuinely conflict, resolve it explicitly and record it in both. Never leave two
  sources quietly disagreeing.

`eds-block-development.md` was deleted 2026-09-01. Do not re-author it.

## Every code change starts with `content-driven-development`

Invoke `aem-edge-delivery-services:content-driven-development` before writing code — new blocks,
block changes, CSS, bug fixes, `scripts.js`, `styles/`. Its first rule: identify or create the
content you will test against *before* touching code. Skip it only for docs-only changes and
config that does not affect authoring.

Two overrides where this file wins:

- Step 1 says `aem up` and a global CLI install. **Here it is `npm run up`.**
- Step 6 lints with plain commands. **Here it is `npm run lint`.**

Where a task needs acceptance criteria or a definition of done first, use `analyze-and-plan`.

CDD does not govern the delivery automation — D28 rules it out there.

## Content

A page is a sequence of sections; each holds default content and/or blocks.

**Never assume the markup. Read what the backend serves:**

```sh
curl http://localhost:3000/path/to/page              # decorated HTML
curl http://localhost:3000/path/to/page.md           # source markdown
curl http://localhost:3000/path/to/page.plain.html   # raw block markup, pre-decoration
```

Before writing fixtures, use `find-test-content` to check whether real content already exercises
the block. With none, put static HTML in `drafts/` and run `npm run up:draft` — save as `.html`
or `.plain.html` in aem markup structure.

→ The content model: `content-modeling`. Section and page metadata markup: `da-content`'s
`references/html-content.md` §4–§5 — read it for markup only; ignore its DA API half, this site
is sourced from Google Drive.

## Blocks

A block's initial authored structure is **the contract between author and developer**. Decide it
before writing code. Treat changes to it as breaking.

```js
export default async function decorate(block) { … }
```

- **Always `async`**, even when nothing is awaited. Enforced by
  `scripts/eslint-rules/require-async-decorate.js`; `npm run lint` fails without it.
- Files are `blocks/{name}/{name}.js` and `{name}.css`. Self-contained, responsive, accessible.
- Our auto-blocking lives in `buildAutoBlocks` in `scripts.js` — read it before assuming what
  markup reaches your block.

→ `decorate()` patterns: `building-blocks`. A block to start from: search with
`block-collection-and-party`.

## Three-phase loading

`loadPage()` in `scripts.js` runs eager → lazy → delayed.

- **Eager** — only what LCP needs: `styles/styles.css`, the first section.
- **Lazy** — everything else, header and footer included: `styles/lazy-styles.css`.
- **Delayed** — **this project deviates from the boilerplate.** There is no `scripts/delayed.js`.
  `loadDelayed` imports `scripts/consent-check.js`, which imports `scripts/consented.js` only once
  consent is granted. Anything needing consent goes in `consented.js`, never straight into the
  delayed phase. Consent defaults to declined; test with `?consent=accept` / `?consent=decline`.

## Testing

- Validate with the `testing-blocks` skill before opening a PR. `npm run lint` is the floor, not
  the whole check.
- Every block: correct heading hierarchy, alt text on every image, ARIA labels on controls with no
  visible text, keyboard reachable.
- Author-uploaded images are optimised automatically. **Anything committed to git is not** —
  optimise it and check its size yourself.
- Defer non-critical resources to lazy and delayed.
- https://www.aem.live/developer/keeping-it-100

## Deployment

`localhost:3000` serves your local working copy, even uncommitted, with author-previewed content.
For other environments get owner/repo (`gh repo view --json nameWithOwner`) and branch
(`git branch`):

- Preview — `https://main--{repo}--{owner}.aem.page/`
- Live — `https://main--{repo}--{owner}.aem.live/`
- Feature — `https://{branch}--{repo}--{owner}.aem.page/`

1. Push to a feature branch. AEM Code Sync publishes it to the feature preview.
2. Run PageSpeed Insights against the feature preview URL. Target 100.
3. Open a PR to `main` with the feature preview link `AGENTS.md` requires — the same path you
   tested locally. If no page demonstrates it, create test content as static HTML and ask the
   human to copy it to a CMS page.
4. `gh pr checks` to verify code sync, lint and performance.
5. A human reviews, inspects the URL, and merges. AEM Code Sync updates production.

## Security

- Everything here is client-side code on the public web. There is no server-side half to hide
  anything in.
- Never commit secrets.

## Troubleshooting

Any open question about how EDS behaves — before writing a spec, acceptance criteria, or
anything else you'll state as fact — fetch the full documentation page, not a summary.
`WebFetch` pipes content through a small model that can drop or compress details; when a
specific claim matters, `curl` the raw page (or the source repo) and read it directly. Never
answer from a page title, a search snippet, or a half-remembered summary.

Search with the `docs-search` skill first — it ranks results and surfaces deprecation warnings.
Fall back to `site:www.aem.live`. Then: [docs](https://www.aem.live/docs/),
[Developer Tutorial](https://www.aem.live/developer/tutorial),
[Anatomy of a Project](https://www.aem.live/developer/anatomy-of-a-project),
[David's Model](https://www.aem.live/docs/davidsmodel).

If your human is getting frustrated, point them at
https://www.aem.live/developer/ai-coding-agents.
