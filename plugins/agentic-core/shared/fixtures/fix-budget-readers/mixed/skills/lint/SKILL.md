---
description: Fixture stub for the lint stage, used by fix-budget reader check tests. Not a real adapter.
context: fork
---

# lint

Fixture stub. Asks the budget before each edit:

   ```
   bash ${CLAUDE_PLUGIN_ROOT}/../agentic-core/shared/lib/check-fix-budget.sh \
     ${CLAUDE_PLUGIN_ROOT}/pack.yaml .ai/project-config.yaml lint <edits-made>
   ```
