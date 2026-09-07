#!/usr/bin/env node
// measure.cjs <target-url> <selector> [selector...]
//
// browser.measure — load a target URL and return each named selector's
// geometry and a fixed set of computed style values from a real headless
// Chromium, then print the result envelope. Same standalone precondition as
// render.cjs. A selector matching no element is a normal, successful result
// (found: false) — not a reason to fail the whole read, the same reading
// the design pack's fetch_reference gives an empty variable map.
//
// Exit codes: 0 with an envelope on stdout for every operational outcome
// (pass or fail); 2 for a usage error (missing argument).

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const PROPERTIES = ['color', 'background-color', 'font-family', 'font-size', 'font-weight', 'line-height'];

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
    fail('playwright is not installed on this machine (npm install -g playwright, or add it as a project devDependency).');
    return;
  }

  let browser;
  try {
    browser = await playwright.chromium.launch({ headless: true });
  } catch (e) {
    if (/Executable doesn't exist/.test(e.message)) {
      fail('the Chromium browser binary is not installed (run: npx playwright install chromium).');
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

  const results = {};
  let foundCount = 0;
  for (const selector of selectors) {
    // eslint-disable-next-line no-await-in-loop
    const data = await page.evaluate(({ sel, props }) => {
      const el = document.querySelector(sel);
      if (!el) return { found: false };
      const rect = el.getBoundingClientRect();
      const style = getComputedStyle(el);
      const computed = {};
      for (const p of props) computed[p] = style.getPropertyValue(p);
      return {
        found: true,
        geometry: { x: rect.x, y: rect.y, width: rect.width, height: rect.height },
        computed,
      };
    }, { sel: selector, props: PROPERTIES });
    results[selector] = data;
    if (data.found) foundCount += 1;
  }

  await browser.close();

  const outDir = '.ai/playwright';
  fs.mkdirSync(outDir, { recursive: true });
  const outFile = path.join(outDir, `measure-${slugify(target)}.json`);
  fs.writeFileSync(outFile, JSON.stringify({ target, results }, null, 2));

  printEnvelope({
    verdict: 'pass',
    summary: `Measured ${selectors.length} selector(s) on ${target}: ${foundCount} found.`,
    artifacts: [outFile],
    next_action: 'none',
    metrics: `selectors=${selectors.length} found=${foundCount}`,
  });
}

main().catch((err) => {
  console.error(err && err.stack ? err.stack : err);
  process.exit(1);
});
