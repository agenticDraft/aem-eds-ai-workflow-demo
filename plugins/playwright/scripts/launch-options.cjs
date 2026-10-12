// launch-options.cjs — the options every operation launches its browser with.
//
// A caller whose network goes only through a proxy (a sandboxed one) names
// it in the environment; the browser does not read that variable itself, so
// it is passed explicitly, credentials included. With no proxy set the
// options are headless and nothing else.
//
// The operation watchdog's limit is read from the environment here too.

function proxyFrom(env) {
  const raw = env.HTTP_PROXY || env.http_proxy;
  if (!raw) return null;
  let url;
  try {
    url = new URL(raw);
  } catch {
    return null;
  }
  const proxy = { server: `${url.protocol}//${url.host}` };
  if (url.username) proxy.username = decodeURIComponent(url.username);
  if (url.password) proxy.password = decodeURIComponent(url.password);
  return proxy;
}

function launchOptions(env) {
  const proxy = proxyFrom(env);
  return proxy ? { headless: true, proxy } : { headless: true };
}

// The longest an operation may run, in milliseconds, before its watchdog
// ends it. PLAYWRIGHT_OPERATION_TIMEOUT_MS overrides the default; a value
// that is not a positive integer is ignored.
const DEFAULT_OPERATION_TIMEOUT_MS = 30000;

function operationTimeoutMs(env) {
  const raw = env.PLAYWRIGHT_OPERATION_TIMEOUT_MS;
  if (!/^[1-9][0-9]*$/.test(raw || '')) return DEFAULT_OPERATION_TIMEOUT_MS;
  return Number(raw);
}

module.exports = { launchOptions, operationTimeoutMs, DEFAULT_OPERATION_TIMEOUT_MS };
