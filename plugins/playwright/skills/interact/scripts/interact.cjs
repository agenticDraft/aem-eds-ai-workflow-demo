#!/usr/bin/env node
// interact.cjs <target-url> <op> [op...]
//
// browser.interact — load a target URL, act on it (click, press a key,
// type), then report the resulting state of one or more named selectors,
// both before the first action and after the last one. Same standalone
// precondition as render.cjs/capture.cjs/measure.cjs: playwright resolved
// as an ordinary Node module, no MCP tool call, no live Claude session.
//
// Each op is one of:
//   click:<selector>
//   press:<key>:<selector>
//   type:<text>:<selector>          (text must not itself contain ':')
//   read:<selector>
// Actions (click/press/type) run in argv order. Every read selector is
// snapshotted once before the first action and once after the last one.
//
// `verdict: pass` requires every action to have actually taken effect: an
// action naming a selector matching nothing, or a selector Playwright could
// not act on, is `verdict: fail` — an interaction that did not happen must
// never read as one that did. A read selector matching nothing is reported
// `found: false`, the same non-failing reading measure.cjs gives a missing
// selector, since a read is a passive observation, not a precondition.
//
// Exit codes: 0 with an envelope on stdout for every operational outcome
// (pass or fail); 2 for a usage error (missing argument, malformed op).

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
// A missing tool is reported with the remedy this pack's own manifest
// declares, so the operation and the diagnostic cannot drift apart.
const { missingToolSummary } = require('../../../scripts/requires.cjs');

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

function parseOps(rawOps) {
  const actions = [];
  const reads = [];
  for (const raw of rawOps) {
    const colon = raw.indexOf(':');
    if (colon === -1) return { error: `op has no ':' separator: ${raw}` };
    const verb = raw.slice(0, colon);
    const rest = raw.slice(colon + 1);
    if (verb === 'click') {
      if (!rest) return { error: `click: is missing a selector: ${raw}` };
      actions.push({ verb, selector: rest });
    } else if (verb === 'press') {
      const sep = rest.indexOf(':');
      if (sep === -1) return { error: `press: needs <key>:<selector>: ${raw}` };
      const key = rest.slice(0, sep);
      const selector = rest.slice(sep + 1);
      if (!key || !selector) return { error: `press: needs <key>:<selector>: ${raw}` };
      actions.push({ verb, key, selector });
    } else if (verb === 'type') {
      const sep = rest.indexOf(':');
      if (sep === -1) return { error: `type: needs <text>:<selector>: ${raw}` };
      const text = rest.slice(0, sep);
      const selector = rest.slice(sep + 1);
      if (!selector) return { error: `type: needs <text>:<selector>: ${raw}` };
      actions.push({ verb, text, selector });
    } else if (verb === 'read') {
      if (!rest) return { error: `read: is missing a selector: ${raw}` };
      reads.push(rest);
    } else {
      return { error: `unknown op verb '${verb}' in: ${raw}` };
    }
  }
  return { actions, reads };
}

async function snapshot(page, selectors) {
  const out = {};
  for (const selector of selectors) {
    // eslint-disable-next-line no-await-in-loop
    const data = await page.evaluate(({ sel, props }) => {
      const el = document.querySelector(sel);
      if (!el) return { found: false };
      const rect = el.getBoundingClientRect();
      const style = getComputedStyle(el);
      const computed = {};
      for (const p of props) computed[p] = style.getPropertyValue(p);
      const attributes = {};
      for (const name of el.getAttributeNames()) {
        if (name.startsWith('aria-') || name === 'class') attributes[name] = el.getAttribute(name);
      }
      return {
        found: true,
        geometry: { x: rect.x, y: rect.y, width: rect.width, height: rect.height },
        computed,
        attributes,
      };
    }, { sel: selector, props: PROPERTIES });
    out[selector] = data;
  }
  return out;
}

async function main() {
  const target = process.argv[2];
  const rawOps = process.argv.slice(3);
  if (!target || rawOps.length === 0) {
    console.error('usage: interact.cjs <target-url> <click:sel|press:key:sel|type:text:sel|read:sel> [...]');
    process.exit(2);
  }

  const parsed = parseOps(rawOps);
  if (parsed.error) {
    console.error(`usage: ${parsed.error}`);
    process.exit(2);
  }
  const { actions, reads } = parsed;
  if (actions.length === 0) {
    console.error('usage: at least one click:/press:/type: action is required');
    process.exit(2);
  }
  if (reads.length === 0) {
    console.error('usage: at least one read:<selector> is required');
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

  const before = await snapshot(page, reads);

  for (let i = 0; i < actions.length; i += 1) {
    const action = actions[i];
    const n = i + 1;
    // eslint-disable-next-line no-await-in-loop
    const count = await page.locator(action.selector).count();
    if (count === 0) {
      await browser.close();
      fail(`action ${n} (${action.verb}) selector matched nothing: ${action.selector}`);
      return;
    }
    try {
      if (action.verb === 'click') {
        // eslint-disable-next-line no-await-in-loop
        await page.locator(action.selector).first().click({ timeout: 5000 });
      } else if (action.verb === 'press') {
        // eslint-disable-next-line no-await-in-loop
        await page.locator(action.selector).first().press(action.key, { timeout: 5000 });
      } else if (action.verb === 'type') {
        // eslint-disable-next-line no-await-in-loop
        await page.locator(action.selector).first().fill(action.text, { timeout: 5000 });
      }
    } catch (e) {
      await browser.close();
      fail(`action ${n} (${action.verb} on ${action.selector}) failed to take effect: ${e.message.split('\n')[0]}`);
      return;
    }
  }

  const after = await snapshot(page, reads);

  await browser.close();

  const outDir = '.ai/playwright';
  fs.mkdirSync(outDir, { recursive: true });
  const outFile = path.join(outDir, `interact-${slugify(target)}.json`);
  fs.writeFileSync(outFile, JSON.stringify({
    target,
    actions: actions.map((a) => (a.verb === 'click' ? { verb: a.verb, selector: a.selector }
      : a.verb === 'press' ? { verb: a.verb, key: a.key, selector: a.selector }
        : { verb: a.verb, text: a.text, selector: a.selector })),
    before,
    after,
  }, null, 2));

  printEnvelope({
    verdict: 'pass',
    summary: `Performed ${actions.length} action(s) on ${target}, read ${reads.length} selector(s) before and after.`,
    artifacts: [outFile],
    next_action: 'none',
    metrics: `actions=${actions.length} reads=${reads.length}`,
  });
}

main().catch((err) => {
  console.error(err && err.stack ? err.stack : err);
  process.exit(1);
});
