// settle.cjs — the condition a read waits for before it is taken.
//
// A page is settled when its fonts have finished loading, no probe reports a
// blocker (a named target that matched an element which is not visible, or
// fonts still loading), and two consecutive snapshots taken a fixed interval
// apart are identical. The whole wait has an upper bound; a page that does
// not settle within it is reported as not settled, with the reason, and no
// snapshot is returned.
//
// Used as a module by this pack's operation scripts. The probe, the fonts
// wait and the clock are passed in, so the condition runs without a browser.

const SETTLE_INTERVAL_MS = 250;
const SETTLE_TIMEOUT_MS = 10000;

const realClock = {
  now: () => Date.now(),
  sleep: (ms) => new Promise((resolve) => { setTimeout(resolve, ms); }),
  timer: (ms) => {
    let handle;
    const promise = new Promise((resolve) => { handle = setTimeout(resolve, ms); });
    return { promise, cancel: () => clearTimeout(handle) };
  },
};

function sameSnapshot(a, b) {
  return JSON.stringify(a) === JSON.stringify(b);
}

// states: { <selector>: { found, width, height, hidden } }. A selector that
// matched nothing is not a blocker; it is reported as not found once settled.
function notVisible(states) {
  return Object.keys(states).filter((sel) => {
    const s = states[sel];
    return s.found && (s.hidden || !(s.width > 0 || s.height > 0));
  });
}

const TIMED_OUT = Symbol('timed out');

// Resolves to the promise's value, or TIMED_OUT once `ms` have passed. A
// promise that loses the race and rejects later is not an unhandled
// rejection.
async function within(clock, promise, ms) {
  promise.catch(() => {});
  const timer = clock.timer(Math.max(ms, 0));
  try {
    return await Promise.race([promise, timer.promise.then(() => TIMED_OUT)]);
  } finally {
    timer.cancel();
  }
}

// probe() resolves to { value, blockers: [string] }.
// Resolves to { settled: true, value } or { settled: false, reason }.
async function settle({
  probe,
  fontsReady,
  intervalMs = SETTLE_INTERVAL_MS,
  timeoutMs = SETTLE_TIMEOUT_MS,
  clock = realClock,
}) {
  const deadline = clock.now() + timeoutMs;
  const notSettled = (why) => ({
    settled: false,
    reason: `the page did not settle within ${timeoutMs} ms: ${why}`,
  });

  if ((await within(clock, fontsReady(), deadline - clock.now())) === TIMED_OUT) {
    return notSettled('document fonts never finished loading');
  }

  let previous = null;
  for (;;) {
    // eslint-disable-next-line no-await-in-loop
    const snap = await within(clock, probe(), deadline - clock.now());
    if (snap === TIMED_OUT) return notSettled('a snapshot did not return');

    const blocked = snap.blockers.length > 0;
    if (!blocked && previous !== null && sameSnapshot(previous, snap.value)) {
      return { settled: true, value: snap.value };
    }
    previous = blocked ? null : snap.value;

    if (clock.now() + intervalMs > deadline) {
      return notSettled(blocked
        ? snap.blockers.join('; ')
        : `consecutive snapshots ${intervalMs} ms apart still differ`);
    }
    // eslint-disable-next-line no-await-in-loop
    await clock.sleep(intervalMs);
  }
}

module.exports = {
  SETTLE_INTERVAL_MS, SETTLE_TIMEOUT_MS, settle, sameSnapshot, notVisible,
};
