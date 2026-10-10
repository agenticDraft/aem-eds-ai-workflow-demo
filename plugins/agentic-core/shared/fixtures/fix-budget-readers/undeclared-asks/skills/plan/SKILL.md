---
description: Fixture stub for the plan stage, used by fix-budget reader check tests. Not a real adapter.
context: fork
---

# plan

Fixture stub. Asks the budget before each edit:

   ```
   bash ${CLAUDE_PLUGIN_ROOT}/core/lib/check-fix-budget.sh \
     ${CLAUDE_PLUGIN_ROOT}/pack.yaml .ai/project-config.yaml plan <edits-made>
   ```
