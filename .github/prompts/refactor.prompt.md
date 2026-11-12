---
agent: agent
description: Refactor selected RiffShelf code without changing behavior
---

# Refactor safely

1. Confirm the scope and inspect existing tests and call sites.
2. Identify one concrete maintainability issue within that scope.
3. Make a minimal structural change; do not add abstractions or dependencies without a demonstrated need.
4. Preserve observable behavior and update tests only if needed to protect that behavior.
5. Run focused tests and relevant formatting/analyzer checks.

Do not combine cleanup with feature work or fix unrelated pre-existing issues. Summarize the structural change and validation results.
