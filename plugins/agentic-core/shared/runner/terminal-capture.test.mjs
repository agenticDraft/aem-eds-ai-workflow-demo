// Tests for terminal-capture.mjs. Run with:
//   node --test plugins/agentic-core/shared/runner/terminal-capture.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";
import { isTerminalCall, resultText, terminalOutput, TerminalCapture } from "./terminal-capture.mjs";

const SCRIPT = "/w/plugins/agentic-core/shared/lib/resolve-terminal-state.sh";

test("the formatter called by path is a terminal call", () => {
  assert.equal(isTerminalCall(`${SCRIPT} failed serve "no answer"`), true);
  assert.equal(isTerminalCall(`bash ${SCRIPT} blocked q .ai/x`), true);
  assert.equal(isTerminalCall(`  plugins/agentic-core/shared/lib/resolve-terminal-state.sh delivered p s`), true);
});

test("anything that does not start with the formatter is not a terminal call", () => {
  assert.equal(isTerminalCall(`echo terminal: delivered; ${SCRIPT} delivered p s`), false);
  assert.equal(isTerminalCall(`cat ${SCRIPT}`), false);
  assert.equal(isTerminalCall(`${SCRIPT}.bak delivered p s`), false);
  assert.equal(isTerminalCall(`${SCRIPT} warn x y`), false);
  assert.equal(isTerminalCall(""), false);
  assert.equal(isTerminalCall(undefined), false);
});

test("output whose first line is a terminal state is returned trimmed", () => {
  assert.equal(terminalOutput("terminal: failed\nstage: serve\nsummary: s\n"),
    "terminal: failed\nstage: serve\nsummary: s");
  assert.equal(terminalOutput("terminal: delivered\n| a |\npublished: x"),
    "terminal: delivered\n| a |\npublished: x");
});

test("output that does not open with a terminal state is refused", () => {
  assert.equal(terminalOutput("invalid: 'warn' is never a terminal state"), null);
  assert.equal(terminalOutput("note\nterminal: delivered"), null);
  assert.equal(terminalOutput("terminal: warn"), null);
  assert.equal(terminalOutput(""), null);
});

test("a tool result's text is read from a string or from text blocks", () => {
  assert.equal(resultText("a"), "a");
  assert.equal(resultText([{ type: "text", text: "a" }, { type: "text", text: "b" }]), "a\nb");
  assert.equal(resultText(undefined), "");
});

const call = (id, command, parent = null) => ({
  type: "assistant",
  parent_tool_use_id: parent,
  message: { content: [{ type: "tool_use", id, name: "Bash", input: { command } }] },
});
const result = (id, content, isError = false, parent = null) => ({
  type: "user",
  parent_tool_use_id: parent,
  message: { content: [{ type: "tool_result", tool_use_id: id, content, is_error: isError }] },
});

test("the driver's formatter call and its output are captured", () => {
  const c = new TerminalCapture();
  c.observe(call("t1", `${SCRIPT} failed serve "no answer"`));
  c.observe(result("t1", "terminal: failed\nstage: serve\nsummary: no answer\n"));
  assert.equal(c.terminal, "terminal: failed\nstage: serve\nsummary: no answer");
});

test("the last captured terminal state wins", () => {
  const c = new TerminalCapture();
  c.observe(call("t1", `${SCRIPT} blocked q r`));
  c.observe(result("t1", "terminal: blocked\nmissing: q\nrecorded: r"));
  c.observe(call("t2", `${SCRIPT} failed s x`));
  c.observe(result("t2", "terminal: failed\nstage: s\nsummary: x"));
  assert.match(c.terminal, /^terminal: failed/);
});

test("nothing is captured from a session that never reaches the formatter", () => {
  const c = new TerminalCapture();
  c.observe(call("b1", "plugins/github/skills/create-branch/scripts/create-branch.sh eds-22"));
  c.observe(result("b1", "## Result\nverdict: pass\nsummary: branch ready"));
  assert.equal(c.terminal, null);
});

test("an errored call, a subagent's call and an unrelated result are ignored", () => {
  const c = new TerminalCapture();
  c.observe(call("e1", `${SCRIPT} delivered p s`));
  c.observe(result("e1", "terminal: delivered", true));
  c.observe(call("s1", `${SCRIPT} delivered p s`, "parent"));
  c.observe(result("s1", "terminal: delivered", false, "parent"));
  c.observe(result("unknown", "terminal: delivered"));
  assert.equal(c.terminal, null);
});
