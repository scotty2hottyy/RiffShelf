---
agent: agent
description: Diagnose and fix a reproducible build, analyzer, or test failure
---

# Diagnose a failure

1. Capture the full relevant error and identify the command and affected project area.
2. Reproduce the failure with the narrowest available command.
3. Trace it to the root cause; inspect nearby code and configuration before changing anything.
4. Make the smallest corrective change. Do not suppress diagnostics, skip tests, or change unrelated behavior.
5. Rerun the failing check and any directly affected tests or analyzers.

For Flutter/Dart, use the repository's Flutter and Dart commands. For the FastAPI backend, run Python checks from `server/`. Report the exact checks run and any remaining failures.
