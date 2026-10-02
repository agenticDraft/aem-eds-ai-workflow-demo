// Tests for shell-shape.mjs. Run with:
//   node --test plugins/agentic-core/shared/runner/shell-shape.test.mjs
//
// Every case below was measured against the SDK's own decision under the
// runner's sandbox with autoAllowBashIfSandboxed (G130, D116, 2026-10-02):
// "refused" cases were DENIED, "passes" cases ran.

import { test } from "node:test";
import assert from "node:assert/strict";
import { shapeProblem } from "./shell-shape.mjs";

const refused = [
  "E=.ai/run-context/e.txt; wc -c $E",
  "E=.ai/run-context/e.txt; head -1 $E",
  "E=.ai/run-context/e.txt; ls $E",
  "E=.ai/run-context/e.txt; grep hi $E",
  "BASE=$(git symbolic-ref HEAD); echo \"base=$BASE\"",
  "MB=$(git rev-parse HEAD)",
  "echo \"base=$(git symbolic-ref HEAD)\"",
];

const passes = [
  "echo exit=$?",
  "mkdir -p .ai/run-context && python3 plugins/pack/x.py; echo exit=$?",
  "E=.ai/run-context/e.txt; printf 'x\\n' > $E",
  "plugins/pack/eval.sh a b | tee .ai/run-context/sc.txt",
  "cat > .ai/run-context/r.md <<'EOF'\nhello\nEOF",
  "sed -E 's/^run: //' .ai/run-context/sc.txt > .ai/route-progress.txt",
  "E=.ai/run-context/e.txt; cat $E",
  "plugins/pack/eval.sh \"$(git symbolic-ref HEAD)\" x",
  "git log $(git rev-parse HEAD) -1 --oneline",
  "echo `git symbolic-ref HEAD`",
  "wc -c .ai/run-context/e.txt",
];

for (const c of refused) {
  test(`refused: ${c}`, () => assert.ok(shapeProblem(c), "expected a reason"));
}
for (const c of passes) {
  test(`passes: ${c}`, () => assert.equal(shapeProblem(c), null));
}

test("each refusal names what to do instead", () => {
  assert.match(shapeProblem("E=a; wc -c $E"), /literal path/);
  assert.match(shapeProblem("MB=$(git rev-parse HEAD)"), /run the inner command on its own/i);
  assert.match(shapeProblem("echo \"b=$(git rev-parse HEAD)\""), /run the inner command on its own/i);
});

test("a $ inside single quotes is not a problem", () => {
  assert.equal(shapeProblem("echo 'cost $(x) and $E'"), null);
  assert.equal(shapeProblem("grep -n 'a$' .ai/x.txt"), null);
});
