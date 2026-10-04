#!/usr/bin/env node
// measure.cjs [--width <n>] <target-url> <selector> [selector...]
//
// browser.measure — load a target URL and return each named selector's
// geometry and a fixed set of computed style values from a real headless
// Chromium, plus whether any element each selector matches holds text and
// which of its words are broken across lines, then print the result
// envelope. With --width the viewport is that wide (the height capture uses);
// without, the browser's default. The measurement records the width read at. Same standalone precondition as
// render.cjs. A selector matching no element is a normal, successful result
// (found: false) — not a reason to fail the whole read, the same reading
// the design pack's fetch_reference gives an empty variable map.
//
// The read is taken only once the page has settled (settle.cjs): fonts
// loaded, every named target that matches an element visible, and two
// consecutive snapshots identical. A page that does not settle within the
// bound fails with the reason, and no artifact is written.
//
// Exit codes: 0 with an envelope on stdout for every operational outcome
// (pass or fail); 2 for a usage error (missing argument).

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
// A missing tool is reported with the remedy this pack's own manifest
// declares, so the operation and the diagnostic cannot drift apart.
const { missingToolSummary } = require('../../../scripts/requires.cjs');
// Every call writes a new file; an earlier call's artifact is never replaced.
const { nextArtifactPath } = require('../../../scripts/next-artifact-path.cjs');
const { launchOptions } = require('../../../scripts/launch-options.cjs');
const { settle, notVisible } = require('../../../scripts/settle.cjs');

// Longhands only: no padding shorthand is ever reported.
const PROPERTIES = [
  'color', 'background-color', 'font-family', 'font-size', 'font-weight', 'line-height',
  'padding-top', 'padding-right', 'padding-bottom', 'padding-left', 'gap', 'border-radius',
  'min-width',
];

// The viewport height a capture uses, so a measure and a capture given the
// same width read the same viewport.
const VIEWPORT_HEIGHT = 800;

// [--width <n>] anywhere, then the target, then the selectors in order.
// `error` is `usage` for a missing argument, `width` for a width that is not
// a positive integer (with `raw`, the value given).
function parseArgs(argv) {
  const rest = [];
  let width = null;
  for (let i = 0; i < argv.length; i += 1) {
    if (argv[i] === '--width') {
      if (i + 1 >= argv.length) return { error: 'usage' };
      const raw = argv[i + 1];
      i += 1;
      if (!/^[1-9][0-9]*$/.test(raw)) return { error: 'width', raw };
      width = Number(raw);
    } else {
      rest.push(argv[i]);
    }
  }
  if (rest.length < 2) return { error: 'usage' };
  return { width, target: rest[0], selectors: rest.slice(1) };
}

function printEnvelope(fields) {
  const lines = ['## Result', `verdict: ${fields.verdict}`, `summary: ${fields.summary}`];
  if (fields.artifacts && fields.artifacts.length) {
    lines.push('artifacts:');
    for (const a of fields.artifacts) lines.push(`  - ${a}`);
  } else {
    lines.push('artifacts: []');
  }
  lines.push(`next_action: ${fields.next_action || 'none'}`);
  if (fields.metrics) lines.push(`metrics: ${fields.metrics}`);
  console.log(lines.join('\n'));
}

function fail(summary) {
  printEnvelope({ verdict: 'fail', summary, artifacts: [] });
}

function resolvePlaywright() {
  try {
    return require('playwright');
  } catch (e) {
    if (e.code !== 'MODULE_NOT_FOUND') throw e;
  }
  try {
    const globalRoot = execSync('npm root -g', { encoding: 'utf8' }).trim();
    return require(path.join(globalRoot, 'playwright'));
  } catch (e) {
    return null;
  }
}

function slugify(url) {
  const slug = url.replace(/^https?:\/\//, '').replace(/[^a-zA-Z0-9]+/g, '-').replace(/^-+|-+$/g, '');
  return (slug || 'target').slice(0, 80);
}

// Runs in the page: every selector's reading in the output shape, and what
// the settle check needs to decide visibility. `holds_text` and
// `broken_words` read every match; geometry and computed values are the
// first match's. A word is a run between whitespace, split again after a
// hyphen; it is broken when its client rects sit on more than one line.
function readSelectors({ sels, props }) {
  const hasText = (node) => Array.from(node.childNodes).some((child) => (
    (child.nodeType === 3 && child.nodeValue.trim() !== '')
    || (child.nodeType === 1 && hasText(child))
  ));
  const textNodes = (node, into) => {
    for (const child of Array.from(node.childNodes)) {
      if (child.nodeType === 3) into.add(child);
      else if (child.nodeType === 1) textNodes(child, into);
    }
    return into;
  };
  const brokenWords = (matches) => {
    const nodes = new Set();
    for (const m of matches) textNodes(m, nodes);
    const out = [];
    for (const node of nodes) {
      for (const word of node.nodeValue.matchAll(/[^\s-]*-+|[^\s-]+/g)) {
        const range = document.createRange();
        range.setStart(node, word.index);
        range.setEnd(node, word.index + word[0].length);
        const tops = Array.from(range.getClientRects())
          .filter((r) => r.width > 0 && r.height > 0)
          .map((r) => Math.round(r.top));
        if (new Set(tops).size > 1) out.push(word[0]);
      }
    }
    return out;
  };
  const out = {};
  const vis = {};
  for (const sel of sels) {
    const all = document.querySelectorAll(sel);
    const el = all[0];
    if (!el) {
      out[sel] = { found: false };
      vis[sel] = { found: false };
    } else {
      const rect = el.getBoundingClientRect();
      const style = getComputedStyle(el);
      const computed = {};
      for (const p of props) computed[p] = style.getPropertyValue(p);
      out[sel] = {
        found: true,
        geometry: { x: rect.x, y: rect.y, width: rect.width, height: rect.height },
        computed,
        holds_text: Array.from(all).some(hasText),
        broken_words: brokenWords(Array.from(all)),
      };
      vis[sel] = {
        found: true, width: rect.width, height: rect.height, hidden: style.visibility === 'hidden',
      };
    }
  }
  return { results: out, states: vis, fontsLoading: document.fonts.status !== 'loaded' };
}

// One snapshot: every selector's reading in the output shape, plus what
// still stops the page counting as settled.
async function probe(page, selectors) {
  const { results, states, fontsLoading } = await page.evaluate(
    readSelectors,
    { sels: selectors, props: PROPERTIES },
  );
  const blockers = [];
  const hidden = notVisible(states);
  if (hidden.length) blockers.push(`named target(s) not visible: ${hidden.join(', ')}`);
  if (fontsLoading) blockers.push('document fonts still loading');
  return { value: results, blockers };
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.error === 'usage') {
    console.error('usage: measure.cjs [--width <n>] <target-url> <selector> [selector...]');
    process.exit(2);
  }
  if (args.error === 'width') {
    fail(`the given width is not a positive integer: ${args.raw}`);
    return;
  }
  const { target, selectors } = args;

  let parsedUrl;
  try {
    parsedUrl = new URL(target);
  } catch (e) {
    fail(`the given target is not a valid URL: ${target}`);
    return;
  }
  if (!['http:', 'https:'].includes(parsedUrl.protocol)) {
    fail(`the given target is not an http(s) URL: ${target}`);
    return;
  }

  const playwright = resolvePlaywright();
  if (!playwright) {
    fail(missingToolSummary('playwright'));
    return;
  }

  let browser;
  try {
    browser = await playwright.chromium.launch(launchOptions(process.env));
  } catch (e) {
    if (/Executable doesn't exist/.test(e.message)) {
      fail(missingToolSummary('chromium'));
      return;
    }
    fail(`could not launch Chromium: ${e.message.split('\n')[0]}`);
    return;
  }

  const page = await browser.newPage(
    args.width ? { viewport: { width: args.width, height: VIEWPORT_HEIGHT } } : {},
  );
  const width = page.viewportSize().width;

  try {
    await page.goto(target, { waitUntil: 'load', timeout: 15000 });
  } catch (e) {
    await browser.close();
    fail(`could not load ${target}: ${e.message.split('\n')[0]}`);
    return;
  }

  const read = await settle({
    fontsReady: () => page.evaluate(() => document.fonts.ready.then(() => true)),
    probe: () => probe(page, selectors),
  });
  await browser.close();
  if (!read.settled) {
    fail(`could not measure ${target}: ${read.reason}`);
    return;
  }
  const results = read.value;
  const foundCount = selectors.filter((sel) => results[sel].found).length;

  const outDir = '.ai/playwright';
  fs.mkdirSync(outDir, { recursive: true });
  const outFile = nextArtifactPath(outDir, `measure-${slugify(target)}`, 'json');
  fs.writeFileSync(outFile, JSON.stringify({ target, width, results }, null, 2));

  printEnvelope({
    verdict: 'pass',
    summary: `Measured ${selectors.length} selector(s) on ${target} at width ${width}: ${foundCount} found.`,
    artifacts: [outFile],
    next_action: 'none',
    metrics: `width=${width} selectors=${selectors.length} found=${foundCount}`,
  });
}

module.exports = { PROPERTIES, parseArgs, readSelectors };

if (require.main === module) {
  main().catch((err) => {
    console.error(err && err.stack ? err.stack : err);
    process.exit(1);
  });
}
