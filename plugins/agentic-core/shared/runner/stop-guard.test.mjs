// Tests for stop-guard.mjs. Run with:
//   node --test plugins/agentic-core/shared/runner/stop-guard.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";
import { isRoutePrompt, stopDecision } from "./stop-guard.mjs";

test("a route that has no terminal state yet is not allowed to stop", () => {
  const d = stopDecision({ isRoute: true, terminal: null, stopHookActive: false });
  assert.equal(d.decision, "block");
  assert.match(d.reason, /resolve-terminal-state\.sh/);
  assert.match(d.reason, /delivered, blocked or failed/);
});

test("a route that recorded its terminal state stops", () => {
  assert.equal(stopDecision({ isRoute: true, terminal: "terminal: blocked\nstage: extract", stopHookActive: false }), null);
});

test("a second stop after one refusal is let through, so a session never loops", () => {
  assert.equal(stopDecision({ isRoute: true, terminal: null, stopHookActive: true }), null);
});

test("a single-stage prompt has no terminal state to wait for", () => {
  assert.equal(stopDecision({ isRoute: false, terminal: null, stopHookActive: false }), null);
});

test("only the route command is a route prompt", () => {
  assert.equal(isRoutePrompt("/agentic-core:run-route ITEM-1 autonomous"), true);
  assert.equal(isRoutePrompt("/pack:pack-intake ITEM-1"), false);
  assert.equal(isRoutePrompt(undefined), false);
});
