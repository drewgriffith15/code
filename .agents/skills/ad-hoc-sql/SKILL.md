---
name: ad-hoc-sql
description: Write Oracle 19c ad-hoc queries and investigative SQL for Liberty University work. Use when Drew needs quick read-only analysis, joins, aggregations, window functions, or troubleshooting queries against Oracle 19c data.
---

# Ad-Hoc SQL

## Purpose

Use this skill for read-only Oracle 19c query work.
It is for exploratory SQL, validation queries, comparison queries, and one-off analysis that does not change data.

## Workflow

- Read the local `AGENTS.md` first.
- Start with the question the query needs to answer.
- Prefer read-only SQL unless the user explicitly requests a change.
- Keep queries targeted and easy to review.
- Use Oracle 19c syntax and behavior as the default assumption.
- Keep the result set useful for analysis, not decorative.
- If a query could touch sensitive student data, minimize columns and rows.

## Query Guidance

- Use clear aliases and explicit joins.
- Prefer CTEs when they make the logic easier to follow.
- Use analytic functions when they reduce complexity.
- Avoid unnecessary nested subqueries when a simpler form is readable.
- Include `order by` only when row order matters to the answer.
- Keep filter logic aligned with the business question.

## Safety Rules

- Do not recommend DML or destructive DDL unless the user explicitly asks.
- Do not expose PII or student records beyond what is needed to answer the question.
- Do not assume DBA-level visibility or privileges.

