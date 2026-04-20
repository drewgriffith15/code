---
name: ad-hoc-sql
description: Write Oracle 19c ad-hoc queries and investigative SQL for Liberty University work. Use when Drew needs to combine pasted snippets or locally sourced objects into one read-only worksheet query, inspect table metadata, and validate joins, filters, and row-level results without changing data.
---

# Ad-Hoc SQL

## Purpose

Use this skill for read-only Oracle 19c query work in a SQL window connected to Oracle 19c.
It is for exploratory SQL, validation queries, comparison queries, and one-off analysis that does not change data.
The usual pattern is to take multiple snippets, inline views, or source object references and compile them into one worksheet-safe query for execution and review.

## Workflow

- Read the local `AGENTS.md` first.
- Start with the output shape and the source inputs, not a fixed business question.
- Accept pasted SQL, inline views, or references to local source objects as the starting point.
- If source objects are involved, inspect the relevant object metadata before building the final query.
- Gather table structure, indexes, constraints, partitions, and row counts when they matter to the query design.
- Prefer read-only SQL unless the user explicitly requests a change.
- Keep queries targeted and easy to review.
- Use Oracle 19c syntax and behavior as the default assumption.
- Keep the result set useful for analysis, not decorative.
- If a query could touch sensitive student data, minimize columns and rows.
- After the query is assembled, wait for the user to run and validate it before any cleanup or follow-up refinement.
- Write work notes using the same naming convention as the data-engineering workflow, and keep them in the project `worknotes/` folder.

## Query Guidance

- Use clear aliases and explicit joins.
- Prefer CTEs when they make the logic easier to follow.
- Use analytic functions when they reduce complexity.
- Avoid unnecessary nested subqueries when a simpler form is readable.
- Include `order by` only when row order matters to the answer.
- Keep filter logic aligned with the business question.
- When the user is compiling snippets, preserve the intent of each snippet while making the combined query readable and worksheet-safe.

## Safety Rules

- Do not recommend DML or destructive DDL unless the user explicitly asks.
- Do not expose PII or student records beyond what is needed to answer the question.
- Do not assume DBA-level visibility or privileges.
- Do not clear the sandbox or discard temporary files until the user explicitly signs off.
- This skill does not stage, commit, or push to BitBucket.

## OCD Check

Use this as the closeout pass for ad hoc query work.

### Axis 1 - Query Fit

- Does the final query answer the stated ask without extra noise?
- Are the joins, filters, grouping, and ordering aligned with the requested output?
- Are any snippets or inline views still redundant or unused?
- Fix only the parts touched in this session.

### Axis 2 - Metadata & Risk

- Did the session review the needed table structure, indexes, constraints, partitions, and row counts where relevant?
- Did the query avoid unnecessary exposure of PII or student data?
- Are there any assumptions about DBA-only visibility that need to be removed?
- Fix any issues found.

### Axis 3 - Worknote Sync

- Write the work note in the project `worknotes/` folder using the same naming convention as the data-engineering workflow.
- Put a short top-line summary first, under 150 characters, and keep it concise enough to read at a glance.
- Include session start and end times.
- Include the key objects reviewed, the validation steps, and any follow-ups.

### Axis 4 - Session Timing & Closeout

- Capture the session start time when the workflow begins.
- Capture the session end time at closeout.
- Record total duration in whole minutes when possible.
- Do not clear the sandbox or remove temporary files until the user explicitly signs off.

### Axis 5 - Handoff Summary

- Summarize what was compiled, what was validated, and what remains for the user to run or review.
- Keep the summary concise enough to paste into a ticket or work note.
- Make the first line the shortest part of the note.

OCD Check complete. Build is done.

## Worknote Template

Use this exact structure for the project work note:

```md
<short summary under 150 characters>

- Session start: <timestamp>
- Session end: <timestamp>
- Duration: <elapsed time>
- What changed: <brief summary>
- Validation: <what was checked>
- OCD check: <pass/fail or short result>
- Follow-ups: <remaining items or "None">
```

