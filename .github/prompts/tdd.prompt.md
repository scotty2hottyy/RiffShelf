---
agent: agent
description: Add or change behavior using focused tests and verification
---

# Test and implement

1. Inspect the existing code and test patterns for the requested behavior.
2. Add or update a focused test that checks the user-visible or contract-level requirement, including a meaningful edge case when relevant.
3. Run that test and confirm it fails for the expected reason when practical.
4. Implement the smallest change that makes it pass.
5. Run the focused test and the narrowest relevant analyzer, formatter, or backend checks.

Avoid tests that merely restate constants or language/framework behavior. Do not force a new coverage target or broaden the change to unrelated failures.
