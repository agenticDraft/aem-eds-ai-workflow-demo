#!/usr/bin/env node
// hang-fixture-server.cjs <port-file>
//
// A local server for the operation-guard tests. Binds an ephemeral port,
// writes it to <port-file>, and serves pages whose scripts misbehave after
// the `load` event:
//   /ok     a page that loads and settles
//   /hang   blocks the main thread in a busy loop right after load
//   /err    on load logs a console error and throws an uncaught exception,
//           then blocks the main thread

const http = require('http');
const fs = require('fs');

const PAGES = {
  '/ok': '<!doctype html><title>ok</title><button id="b">go</button><p class="t">text</p>',
  '/hang': '<!doctype html><title>hang</title><button id="b">go</button><p class="t">text</p><script>'
    + 'window.addEventListener("load", function () {'
    + ' setTimeout(function () { while (true) {} }, 0); });</script>',
  '/err': '<!doctype html><title>err</title><button id="b">go</button><p class="t">text</p><script>'
    + 'window.addEventListener("load", function () {'
    + ' console.error("fixture-console-error"); throw new Error("fixture-uncaught"); });'
    + 'window.addEventListener("load", function () {'
    + ' setTimeout(function () { while (true) {} }, 0); });</script>',
};

const server = http.createServer((req, res) => {
  const body = PAGES[req.url];
  if (!body) {
    res.writeHead(404, { 'content-type': 'text/plain' });
    res.end('not found');
    return;
  }
  res.writeHead(200, { 'content-type': 'text/html' });
  res.end(body);
});

server.listen(0, '127.0.0.1', () => {
  fs.writeFileSync(process.argv[2], String(server.address().port));
});
