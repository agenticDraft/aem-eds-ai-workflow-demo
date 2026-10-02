// Tests for network-allowlist.mjs. Run with:
//   node --test plugins/agentic-core/shared/runner/network-allowlist.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  AllowlistRefused,
  lockedSandbox,
  parseAllowedDomains,
  parsePreviewHost,
  readAllowedDomains,
  withHost,
} from "./network-allowlist.mjs";

const settings = (network) => JSON.stringify({ sandbox: { enabled: true, network } });
const refused = (fn, pattern) =>
  assert.throws(fn, (err) => err instanceof AllowlistRefused && pattern.test(err.message));

test("a committed list is returned as written", () => {
  const text = settings({ allowedDomains: ["github.com", "*.example.org"] });
  assert.deepEqual(parseAllowedDomains(text), ["github.com", "*.example.org"]);
});

test("a missing file is refused", () => {
  const dir = mkdtempSync(join(tmpdir(), "allowlist-"));
  refused(() => readAllowedDomains(join(dir, "settings.json")), /not found/);
});

test("a file on disk is read", () => {
  const dir = mkdtempSync(join(tmpdir(), "allowlist-"));
  const path = join(dir, "settings.json");
  writeFileSync(path, settings({ allowedDomains: ["api.github.com"] }));
  assert.deepEqual(readAllowedDomains(path), ["api.github.com"]);
});

test("invalid JSON is refused", () => {
  refused(() => parseAllowedDomains("{ not json"), /not valid JSON/);
});

test("an absent list is refused", () => {
  refused(() => parseAllowedDomains(JSON.stringify({})), /absent/);
  refused(() => parseAllowedDomains(settings({})), /absent/);
});

test("an empty list is refused", () => {
  refused(() => parseAllowedDomains(settings({ allowedDomains: [] })), /empty/);
});

test("a list that is not a list is refused", () => {
  refused(() => parseAllowedDomains(settings({ allowedDomains: "github.com" })), /not a list/);
});

test("a blank, padded or non-string entry is refused", () => {
  refused(() => parseAllowedDomains(settings({ allowedDomains: ["github.com", ""] })), /not a plain host/);
  refused(() => parseAllowedDomains(settings({ allowedDomains: [" github.com"] })), /not a plain host/);
  refused(() => parseAllowedDomains(settings({ allowedDomains: [42] })), /not a plain host/);
});

test("the locked block carries the lock, the copy, no retry, sandboxed auto-approval and a hard start", () => {
  const domains = ["github.com"];
  const block = lockedSandbox(domains);
  assert.deepEqual(block, {
    enabled: true,
    failIfUnavailable: true,
    autoAllowBashIfSandboxed: true,
    allowUnsandboxedCommands: false,
    network: { strictAllowlist: true, allowedDomains: ["github.com"] },
  });
  domains.push("example.com");
  assert.deepEqual(block.network.allowedDomains, ["github.com"], "the block holds its own copy");
});

const config = (preview) =>
  ["version: 1", "", "commands:", '  serve: "start"', "", "paths:", '  spec_dir: ".ai/specs"',
   ...(preview === undefined ? [] : [`  preview: ${preview}`]), "", "limits:", "  x: 1", ""].join("\n");

test("the preview's host is read from the paths block", () => {
  assert.equal(parsePreviewHost(config('"http://localhost:3000/preview"')), "localhost");
  assert.equal(parsePreviewHost(config("http://127.0.0.1:8080/")), "127.0.0.1");
  assert.equal(parsePreviewHost(config("'https://preview.example.org/x'")), "preview.example.org");
});

test("no preview, an empty one or one that is not a URL gives no host", () => {
  assert.equal(parsePreviewHost(config(undefined)), null);
  assert.equal(parsePreviewHost(config('""')), null);
  assert.equal(parsePreviewHost(config('"not a url"')), null);
  assert.equal(parsePreviewHost("version: 1\n"), null);
});

test("a preview key outside the paths block is not read", () => {
  const text = ["other:", '  preview: "http://elsewhere.example/"', "paths:", '  spec_dir: "x"', ""].join("\n");
  assert.equal(parsePreviewHost(text), null);
});

test("a host is appended once, and a list that has it is unchanged", () => {
  assert.deepEqual(withHost(["github.com"], "localhost"), ["github.com", "localhost"]);
  assert.deepEqual(withHost(["github.com", "localhost"], "localhost"), ["github.com", "localhost"]);
  assert.deepEqual(withHost(["github.com"], null), ["github.com"]);
  const list = ["github.com"];
  withHost(list, "localhost");
  assert.deepEqual(list, ["github.com"], "the input list is not modified");
});
