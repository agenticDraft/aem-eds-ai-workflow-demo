#!/usr/bin/env node
// capture.cjs <target-url> <width>
//
// browser.capture — load a target URL and capture a full-page screenshot at
// the given viewport width in a real headless Chromium, then print the
// result envelope. Same standalone precondition as render.cjs: playwright
// resolved as an ordinary Node module, no MCP tool call, no live Claude
// session.
//
// Exit codes: 0 with an envelope on stdout for every operational outcome
// (pass or fail); 2 for a usage error (missing argument).

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

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
  const widthArg = process.argv[3];
  if (!target || !widthArg) {
    console.error('usage: capture.cjs <target-url> <width>');
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

  const width = Number(widthArg);
  if (!Number.isInteger(width) || width <= 0) {
    fail(`the given width is not a positive integer: ${widthArg}`);
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

  const page = await browser.newPage({ viewport: { width, height: 800 } });

  try {
    await page.goto(target, { waitUntil: 'load', timeout: 15000 });
  } catch (e) {
    await browser.close();
    fail(`could not load ${target}: ${e.message.split('\n')[0]}`);
    return;
  }

  const outDir = '.ai/playwright';
  fs.mkdirSync(outDir, { recursive: true });
  const outFile = path.join(outDir, `capture-${slugify(target)}-${width}.png`);
  await page.screenshot({ path: outFile, fullPage: true });

  await browser.close();

  const bytes = fs.statSync(outFile).size;

  printEnvelope({
    verdict: 'pass',
    summary: `Captured ${target} at width ${width} to ${outFile}.`,
    artifacts: [outFile],
    next_action: 'none',
    metrics: `width=${width} bytes=${bytes}`,
  });
}

main().catch((err) => {
  console.error(err && err.stack ? err.stack : err);
  process.exit(1);
});
