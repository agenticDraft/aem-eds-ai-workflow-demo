// Tests for policy-match.mjs. Run with:
//   node --test plugins/agentic-core/shared/runner/policy-match.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";
import { forbiddenBy, parseRule } from "./policy-match.mjs";

const RULES = [
  "Bash(gh pr merge*)",
  "Bash(git push --force*)",
  "Bash(git push -f*)",
  "Bash(git push origin main*)",
  "WebFetch",
];
const bash = (command) => forbiddenBy(RULES, "Bash", { command });

test("a forbidden command is matched by its rule", () => {
  assert.equal(bash("gh pr merge 12 --squash"), "Bash(gh pr merge*)");
  assert.equal(bash("git push -f origin x"), "Bash(git push -f*)");
});

test("an allowed command matches nothing", () => {
  assert.equal(bash("gh pr view 12"), null);
  assert.equal(bash("git push -u origin phase-9-task-4-policy"), null);
  assert.equal(bash("git push origin mainline-fix"), "Bash(git push origin main*)",
    "a prefix rule is a prefix rule: name such rules with care");
});

test("whitespace cannot slip past a rule", () => {
  assert.equal(bash("git   push    --force   origin x"), "Bash(git push --force*)");
  assert.equal(bash("  gh\tpr  merge 3"), "Bash(gh pr merge*)");
});

test("each part of a compound command is checked", () => {
  assert.equal(bash("cd repo && gh pr merge 3"), "Bash(gh pr merge*)");
  assert.equal(bash("echo ok; git push -f"), "Bash(git push -f*)");
  assert.equal(bash("true || git push --force"), "Bash(git push --force*)");
  assert.equal(bash("ls | gh pr merge 1"), "Bash(gh pr merge*)");
  assert.equal(bash("echo a\ngh pr merge 1"), "Bash(gh pr merge*)");
});

test("a bare tool name forbids every call of that tool", () => {
  assert.equal(forbiddenBy(RULES, "WebFetch", { url: "https://example.com" }), "WebFetch");
});

test("a rule for one tool never matches another", () => {
  assert.equal(forbiddenBy(RULES, "Read", { file_path: "gh pr merge" }), null);
});

test("pattern characters other than * are literal", () => {
  assert.equal(forbiddenBy(["Read(/etc/pass.d)"], "Read", { file_path: "/etc/passXd" }), null);
  assert.equal(forbiddenBy(["Read(/etc/*)"], "Read", { file_path: "/etc/shadow" }), "Read(/etc/*)");
});

test("a malformed rule is refused, not ignored", () => {
  assert.throws(() => parseRule("rm -rf /"), /not a tool rule/);
});
