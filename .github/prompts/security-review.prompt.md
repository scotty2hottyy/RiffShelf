---
agent: agent
description: Review selected changes for security issues with evidence
---

# Security review

Review only the requested code or diff. Do not modify files.

Check relevant risks such as untrusted imported/provider data, unsafe file handling, database query construction, secret exposure, backend input validation, and error/log data leakage. Do not report a checklist item as a finding without evidence in the code.

For each finding, provide severity, file and line, the risky behavior and impact, and a concrete mitigation. Separate confirmed findings from questions or hardening suggestions. If no actionable issue is found, say so and mention any meaningful scope limitation.
