// Tests for route-agent.mjs's start-up refusals. Run with:
//   node --test plugins/agentic-core/shared/runner/route-agent.test.mjs
//
// Each case starts the runner in a scratch directory with a refusal it must
// hit before any session starts, so no credential and no network is needed.

import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const RUNNER = join(dirname(fileURLToPath(import.meta.url)), "route-agent.mjs");

function start(env) {
  const cwd = mkdtempSync(join(process.env.TMPDIR || tmpdir(), "route-agent-"));
  const base = { ...process.env };
  delete base.ROUTE_PLUGIN_DIR;
  const run = spawnSync(process.execPath, [RUNNER, "/a-pack:an-operation item_id: X-1"], {
    cwd,
    env: { ...base, ROUTE_RESULT_FILE: "result.txt", ROUTE_POLICY_FILE: "no-policy.yaml", ...env },
    encoding: "utf8",
  });
  let result = "";
  try {
    result = readFileSync(join(cwd, "result.txt"), "utf8");
  } catch {}
  rmSync(cwd, { recursive: true, force: true });
  return { status: run.status, stderr: run.stderr, result };
}

test("an unset ROUTE_PLUGIN_DIR starts nothing: exit 7, said in the log and the result", () => {
  const r = start({});
  assert.equal(r.status, 7, r.stderr);
  assert.match(r.stderr, /plugin directory refused: ROUTE_PLUGIN_DIR is not set/);
  assert.match(r.result, /plugin directory refused: ROUTE_PLUGIN_DIR is not set/);
});

test("an empty ROUTE_PLUGIN_DIR is refused the same way", () => {
  assert.equal(start({ ROUTE_PLUGIN_DIR: "" }).status, 7);
});

test("a set ROUTE_PLUGIN_DIR passes on to the next refusal, the missing policy", () => {
  const r = start({ ROUTE_PLUGIN_DIR: "absent-folder" });
  assert.equal(r.status, 3, r.stderr);
  assert.doesNotMatch(r.stderr, /plugin directory refused/);
});
