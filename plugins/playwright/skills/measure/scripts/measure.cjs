#!/usr/bin/env node
// measure.cjs <target-url> <selector> [selector...]
//
// browser.measure — load a target URL and return each named selector's
// geometry and a fixed set of computed style values from a real headless
// Chromium, plus whether any element each selector matches holds text,
// then print the result envelope. Same standalone precondition as
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
const { settle, notVisible } = require('../../../scripts/settle.cjs');

// Longhands only: no padding shorthand is ever reported.
const PROPERTIES = [
  'color', 'background-color', 'font-family', 'font-size', 'font-weight', 'line-height',
  'padding-top', 'padding-right', 'padding-bottom', 'padding-left', 'gap', 'border-radius',
];

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
// the settle check needs to decide visibility. `holds_text` reads every match;
// geometry and computed values are the first match's.
function readSelectors({ sels, props }) {
  const hasText = (node) => Array.from(node.childNodes).some((child) => (
    (child.nodeType === 3 && child.nodeValue.trim() !== '')
    || (child.nodeType === 1 && hasText(child))
  ));
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
  const target = process.argv[2];
  const selectors = process.argv.slice(3);
  if (!target || selectors.length === 0) {
    console.error('usage: measure.cjs <target-url> <selector> [selector...]');
    process.exit(2);
  }

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
    browser = await playwright.chromium.launch({ headless: true });
  } catch (e) {
    if (/Executable doesn't exist/.test(e.message)) {
      fail(missingToolSummary('chromium'));
      return;
    }
    fail(`could not launch Chromium: ${e.message.split('\n')[0]}`);
    return;
  }

  const page = await browser.newPage();

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
  fs.writeFileSync(outFile, JSON.stringify({ target, results }, null, 2));

  printEnvelope({
    verdict: 'pass',
    summary: `Measured ${selectors.length} selector(s) on ${target}: ${foundCount} found.`,
    artifacts: [outFile],
    next_action: 'none',
    metrics: `selectors=${selectors.length} found=${foundCount}`,
  });
}

module.exports = { PROPERTIES, readSelectors };

if (require.main === module) {
  main().catch((err) => {
    console.error(err && err.stack ? err.stack : err);
    process.exit(1);
  });
}
