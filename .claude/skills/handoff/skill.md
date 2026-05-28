---
name: handoff
description: Compact the current conversation into a handoff document for another agent to pick up.
argument-hint: "What will the next session be used for?"
---

Write a handoff document summarising the current conversation so a fresh agent can continue the work. Save to: C:\Users\wgriffith2\Dropbox (Liberty University)\Code\temp\ — always use this path, not the OS temp directory.

**File naming:** `handoff_YYYYMMDDHHMM_<topic>.md` where YYYYMMDDHHMM is the current date and time (e.g. `handoff_202605281139_skills_git_ocd.md`). Get the current time before saving. The timestamp ensures uniqueness — multiple handoffs in the same session are handled automatically since the minute will differ. Never use vague names like `handoff.md` or add `_v2` suffixes.

Include a "suggested skills" section in the document, which suggests skills that the agent should invoke.

Do not duplicate content already captured in other artifacts (PRDs, plans, ADRs, issues, commits, diffs). Reference them by path or URL instead.

Redact any sensitive information, such as API keys, passwords, or personally identifiable information.

If the user passed arguments, treat them as a description of what the next session will focus on and tailor the doc accordingly.
