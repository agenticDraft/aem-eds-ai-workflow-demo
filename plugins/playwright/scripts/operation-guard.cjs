// operation-guard.cjs — what stops an operation from hanging in silence.
//
// A page can block its own main thread; every browser call that evaluates in
// that page then waits forever, and a per-call timeout covers only the calls
// that carry one. The guard gives an operation two things:
//
//   - a log under .ai/playwright/ that every console error, uncaught page
//     exception and step is appended to the moment it happens, so a run that
//     is killed still leaves what it saw;
//   - a watchdog around the whole operation. On expiry it records what was
//     last being done, reports a failed envelope that names the timeout and
//     lists the log, closes the browser (bounded), and exits 0.
//
// Used as a module by this pack's operation scripts.

const fs = require('fs');
const { nextArtifactPath } = require('./next-artifact-path.cjs');
const { operationTimeoutMs } = require('./launch-options.cjs');

const BROWSER_CLOSE_GRACE_MS = 2000;
const OUT_DIR = '.ai/playwright';

function createGuard({ operation, slug, env }) {
  const limitMs = operationTimeoutMs(env);
  let browser = null;
  let logFile = null;
  let step = 'starting';

  function note(line) {
    if (logFile) fs.appendFileSync(logFile, `${new Date().toISOString()} ${line}\n`);
  }

  return {
    limitMs,

    // Reserve the log file. Called once the operation has decided to start a
    // browser, so a usage error leaves no file behind.
    openLog() {
      logFile = nextArtifactPath(OUT_DIR, `${operation}-${slug}-log`, 'log');
      note(`${operation} started`);
    },

    // The artifacts a failed envelope lists: the log, once it exists.
    artifacts() {
      return logFile ? [logFile] : [];
    },

    setBrowser(b) {
      browser = b;
    },

    // Record the step the operation is about to take; the watchdog reports
    // the last one.
    step(name) {
      step = name;
      note(`step: ${name}`);
    },

    // Append every console error and uncaught page exception to the log as
    // it happens. `onConsoleError` lets the caller keep its own list.
    watch(page, onConsoleError) {
      page.on('console', (msg) => {
        if (msg.type() !== 'error') return;
        note(`console error: ${msg.text()}`);
        if (onConsoleError) onConsoleError(msg.text());
      });
      page.on('pageerror', (err) => {
        note(`pageerror: ${err && err.stack ? err.stack : err}`);
      });
    },

    // Runs `work()` under the watchdog. `fail(summary, artifacts)` prints the
    // failed envelope. Resolves when the work finishes; on expiry it does not
    // resolve — it reports, closes the browser and exits the process with 0.
    async run(work, fail) {
      let timer;
      const expired = new Promise((resolve) => {
        timer = setTimeout(() => resolve(true), limitMs);
      });
      const finished = await Promise.race([work().then(() => false), expired]);
      clearTimeout(timer);
      if (!finished) return;

      note(`watchdog: no result after ${limitMs} ms, last step: ${step}`);
      fail(`${operation} timed out after ${limitMs} ms while ${step}; the page may be blocking its main thread.`, this.artifacts());
      if (browser) {
        await Promise.race([
          browser.close().catch(() => {}),
          new Promise((resolve) => { setTimeout(resolve, BROWSER_CLOSE_GRACE_MS); }),
        ]);
      }
      process.stdout.write('', () => process.exit(0));
      await new Promise(() => {});
    },
  };
}

module.exports = { createGuard };
