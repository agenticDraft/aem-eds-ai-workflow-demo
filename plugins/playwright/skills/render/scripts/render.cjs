#!/usr/bin/env node
// render.cjs <target-url>
//
// browser.render — load a target URL in a real headless Chromium and report
// its load state, then print the result envelope. `playwright` is resolved
// as an ordinary Node module (the pack's own declared dependency first, then
// the machine's global npm root) — the same "installed on the machine"
// precondition the scm pack holds `gh` to; nothing here calls a live Claude
// session's MCP tools.
//
// `verdict: pass` reports that the page could be loaded and its state
// observed — an HTTP 404/500 is a successfully observed state, not an
// operation failure. `verdict: fail` is reserved for the read itself not
// happening: no playwright, no browser binary, or navigation never
// completing (DNS, connection refused, timeout).
//
// A watchdog (PLAYWRIGHT_OPERATION_TIMEOUT_MS, 30 s by default) ends a run
// that does not finish — a page that blocks its own main thread after load —
// with a failed envelope. Every console error and uncaught page exception is
// appended to a log the moment it happens, and the log is listed in the
// envelope's artifacts on pass and on fail.
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
// Ends an operation that hangs, and logs what the page did as it did it.
const { createGuard } = require('../../../scripts/operation-guard.cjs');

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

function fail(summary, artifacts = []) {
  printEnvelope({ verdict: 'fail', summary, artifacts });
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

async function main(guard) {
  const target = process.argv[2];
  if (!target) {
    console.error('usage: render.cjs <target-url>');
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

  guard.openLog();
  guard.step('launching Chromium');
  let browser;
  try {
    browser = await playwright.chromium.launch(launchOptions(process.env));
    guard.setBrowser(browser);
  } catch (e) {
    if (/Executable doesn't exist/.test(e.message)) {
      fail(missingToolSummary('chromium'), guard.artifacts());
      return;
    }
    fail(`could not launch Chromium: ${e.message.split('\n')[0]}`, guard.artifacts());
    return;
  }

  const consoleErrors = [];
  const page = await browser.newPage();
  guard.watch(page, (text) => consoleErrors.push(text));

  const start = Date.now();
  let response;
  guard.step(`loading ${target}`);
  try {
    response = await page.goto(target, { waitUntil: 'load', timeout: 15000 });
  } catch (e) {
    await browser.close();
    fail(`could not load ${target}: ${e.message.split('\n')[0]}`, guard.artifacts());
    return;
  }
  const loadTimeMs = Date.now() - start;

  guard.step('reading the page title');
  const state = {
    target,
    final_url: page.url(),
    status: response ? response.status() : null,
    title: await page.title(),
    console_errors: consoleErrors,
    load_time_ms: loadTimeMs,
  };

  await browser.close();

  const outDir = '.ai/playwright';
  fs.mkdirSync(outDir, { recursive: true });
  const outFile = nextArtifactPath(outDir, `render-${slugify(target)}`, 'json');
  fs.writeFileSync(outFile, JSON.stringify(state, null, 2));

  printEnvelope({
    verdict: 'pass',
    summary: `Rendered ${target}: HTTP ${state.status}, ${consoleErrors.length} console error(s).`,
    artifacts: [outFile, ...guard.artifacts()],
    next_action: 'none',
    metrics: `status=${state.status} console_errors=${consoleErrors.length} load_time_ms=${loadTimeMs}`,
  });
}

const guard = createGuard({ operation: 'render', slug: slugify(process.argv[2] || ''), env: process.env });
guard.run(() => main(guard), fail).catch((err) => {
  console.error(err && err.stack ? err.stack : err);
  process.exit(1);
});
