// Tests for shell-shape.mjs. Run with:
//   node --test plugins/agentic-core/shared/runner/shell-shape.test.mjs
//
// Every case below was measured against the SDK's own dontAsk decision
// (G130, 2026-10-02): "refused" cases were DENIED, "passes" cases were allowed.

import { test } from "node:test";
import assert from "node:assert/strict";
import { shapeProblem } from "./shell-shape.mjs";

const refused = [
  "echo exit=$?",
  "python3 plugins/pack/x.py; echo exit=$?",
  "mkdir -p .ai/run-context && python3 plugins/pack/x.py .ai/a.json; echo exit=$?",
  "E=.ai/run-context/e.txt; wc -c $E",
  "E=.ai/run-context/e.txt; head -1 $E",
  "E=.ai/run-context/e.txt; ls $E",
  "E=.ai/run-context/e.txt; grep hi $E",
  "E=.ai/run-context/e.txt; printf 'x\\n' > $E",
];

const passes = [
  "mkdir -p .ai/run-context && python3 plugins/pack/x.py",
  "python3 plugins/pack/x.py; echo done",
  "printf '## Result\\nverdict: fail\\n' > .ai/run-context/e.txt",
  "L=/w/plugins/agentic-core/shared/lib; $L/capture-envelope.sh .ai/run-context/e.txt",
  "P=/w/plugins; /w/plugins/agentic-core/shared/lib/run-stage.sh $P/pack/pack.yaml intake x",
  "L=/w/plugins/agentic-core/shared/lib; E=.ai/run-context/e.txt; $L/capture-envelope.sh $E",
  "E=.ai/run-context/e.txt; cat $E",
  "E=.ai/run-context/e.txt; echo $E",
  "E=.ai/run-context/e.txt; mkdir -p .ai/x; touch $E",
  "wc -c .ai/run-context/e.txt",
  "cat .ai/run-context/e.txt; echo \"rc=$?\"",
];

for (const c of refused) {
  test(`refused: ${c}`, () => assert.ok(shapeProblem(c), "expected a reason"));
}
for (const c of passes) {
  test(`passes: ${c}`, () => assert.equal(shapeProblem(c), null));
}

test("each refusal names what to do instead", () => {
  assert.match(shapeProblem("echo exit=$?"), /exit (code|status)/);
  assert.match(shapeProblem("E=a; wc -c $E"), /literal path/);
  assert.match(shapeProblem("E=a; printf x > $E"), /literal path/);
});

test("a quoted $? or a $ inside single quotes is not a problem", () => {
  assert.equal(shapeProblem("echo 'cost $? and $E'"), null);
  assert.equal(shapeProblem("grep -n 'a$' .ai/x.txt"), null);
});
