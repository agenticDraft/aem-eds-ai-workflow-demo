// Tests for denials.mjs. Run with:
//   node --test plugins/agentic-core/shared/runner/denials.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";
import { denialLines } from "./denials.mjs";

const LONG = `L=/home/runner/work/x/x/plugins/agentic-core/shared/lib; F=.ai/run-context/envelope-intake.txt; $L/capture-envelope.sh "$F" && $L/run-stage.sh plugins/pack/pack.yaml intake "$F" 2>&1`;

test("a denied Bash call is printed with its whole command, never cut", () => {
  const lines = denialLines([{ tool_name: "Bash", tool_use_id: "t1", tool_input: { command: LONG } }]);
  assert.equal(lines.length, 2);
  assert.equal(lines[0], "permission denials (1):");
  assert.ok(lines[1].endsWith(LONG), lines[1]);
  assert.ok(lines[1].includes("Bash"));
});

test("a multi-line command stays on one log line", () => {
  const lines = denialLines([{ tool_name: "Bash", tool_use_id: "t1", tool_input: { command: "a\nb" } }]);
  assert.equal(lines.length, 2);
  assert.ok(lines[1].endsWith("a\\nb"), lines[1]);
});

test("any other tool is printed with its whole input as JSON", () => {
  const input = { file_path: "/w/plugins/pack/pack.yaml", old_string: "x".repeat(400), new_string: "y" };
  const lines = denialLines([{ tool_name: "Edit", tool_use_id: "t2", tool_input: input }]);
  assert.ok(lines[1].includes(JSON.stringify(input)), lines[1]);
});

test("no denials prints nothing", () => {
  assert.deepEqual(denialLines([]), []);
  assert.deepEqual(denialLines(undefined), []);
});
