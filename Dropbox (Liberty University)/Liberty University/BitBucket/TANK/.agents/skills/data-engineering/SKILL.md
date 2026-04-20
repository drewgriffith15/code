---
name: data-engineering
description: Orchestrate Liberty University data engineering analysis, diagnostics, test-table generation, rewrite creation, and comparison scripts for Oracle 19c PL/SQL procedures, anonymous blocks, and package code. Use when a user provides Oracle SQL or PL/SQL and wants a repeatable workflow to extract table dependencies, generate diagnostics, build a mirrored test harness, produce an optimized rewrite, and create validation comparisons with a human approval gate.
---

# Data Engineering

## Purpose

Use this skill when the user provides a procedure, package body, or anonymous PL/SQL block and wants a repeatable Oracle 19c data-engineering workflow.
Keep the project-local artifact model: write planning docs to `prd/`, work in `sandbox/`, and save concise delivery notes in `worknotes/`.
Keep the instructions generic. Do not hardcode example object names, schemas, or business cases into the workflow guidance.
Treat the skill as the arbiter for a reusable Oracle PL/SQL workflow, not as a case-specific script library.
Assume schema-level permissions only unless the user explicitly says otherwise; do not rely on DBA-only access.

## Workflow

1. Read the supplied SQL or PL/SQL and identify the target procedure, package, or anonymous block.
2. Extract every referenced object that matters to the database footprint, including tables, views, packages, sequences, log tables, and helper routines.
3. Produce a diagnostics-first assessment before any rewrite work begins.
4. Write or update the active project PRD in `prd/`.
5. Generate a single consolidated diagnostic SQL artifact in `sandbox/` that can be pasted into a worksheet and run in one pass.
6. Pause after diagnostics and wait for human review before moving to test-table, rewrite, or comparison steps.
7. After approval, use the diagnostics output to design the test-table or test-harness script in `sandbox/`.
8. After the test table is validated, generate the proposed rewrite in `sandbox/`, and default the first rewrite pass to the `_TEST` target table for human validation.
9. After the test rewrite is run, generate comparison SQL that checks production versus test outputs.
10. After the comparison review is approved, generate a deployment-ready splice or procedure draft that removes `_TEST` from the target object references.
11. Pause again for human approval before applying the deployment-ready procedure into the package or source file.
12. After approval and commit, write a concise work note in `worknotes/`.
13. Generate an explicit cleanup SQL artifact when the workflow created temporary tables or other throwaway validation objects.
14. Do not clear `sandbox/` until the user confirms the work is closed out and any needed commit has already been made.
15. When outputting any artifact, show the exact absolute file path where it was written.
16. Keep generated SQL worksheet-safe by default: use `--` comment headers, not SQL*Plus `SET` or `PROMPT` commands.

## Output Conventions

When the user asks for the standard workflow, produce artifacts in this order:

- `get_diagnostics_YYYYMMDD.sql`
- `create_test_table_YYYYMMDD.sql`
- `etl_<object_name>_YYYYMMDD.sql`
- `get_comparison_YYYYMMDD.sql`
- `deploy_<object_name>_YYYYMMDD.sql`

Use the smallest diagnostic set that still answers the row-count, object-graph, partitioning, index, and plan-risk questions.
Prefer one consolidated diagnostics report over many separate scripts when the worksheet can support it.
Export diagnostics from PL/SQL Developer as CSV when direct database access is not available.
Use the same basename for the export as the SQL file, for example `get_diagnostics_20260417.sql` and `get_diagnostics_20260417.csv`.
Create a matching empty `.csv` placeholder in `sandbox/` when it helps the user save over the exact filename.
If the worksheet output would otherwise fragment across many blocks, normalize it into one query result set with section labels and ordered rows.
The consolidated diagnostics should always include a source-code scan section, an object-footprint section, target table structure, index and constraint inventory, partition metadata when relevant, and row-count or other read-only volume checks.
Do not reference `_TEST` objects in diagnostics unless the user already created them and explicitly wants them reviewed.

## Diagnostic Guidance

- Prefer read-only catalog queries for the first pass.
- Include table statistics, row counts, partition metadata, and index inventory when they are relevant to the problem.
- Call out missing or suspicious hints, unexpected full scans, runaway loops, deadlock retry patterns, and non-reset retry counters.
- Treat object and table names as the primary unit of analysis for large packages.
- If the user supplies a package body, identify the specific procedure or function before generating output.
- Keep diagnostics generic and infer object targets from the pasted source instead of assuming a fixed example.
- For handoff, prefer CSV export over HTML or XML because it is easier to parse back into Codex without live database access.
- After diagnostics are reviewed, use that evidence to drive the test-table shape, the rewrite plan, and the comparison coverage.
- Build diagnostics using schema-level accessible catalog views and object metadata only; do not assume DBA views or privileged access.
- When column metadata queries would otherwise hit `LONG` datatype issues, normalize them into worksheet-safe `VARCHAR2` output so the user can export to CSV cleanly.

## Test Harness Guidance

- Mirror the production table shape closely enough to validate behavior.
- Use a separate test table name ending in `_TEST` when that fits the workflow.
- Default the first rewrite pass to the `_TEST` target table, then use comparison SQL to validate test versus production before any promotion.
- When the test object is seeded from production for baseline comparison, make that seed step explicit in the artifact.
- Include the minimum keys, partitions, indexes, and constraints needed to run an honest comparison.
- Exclude grants from recreated metadata by default so test objects are not accidentally prepared for production-style access.
- Keep any seed load step explicit and reproducible.
- Do not silently change production semantics while building the test harness.

## Rewrite Guidance

- When generating a rewrite that the user will paste into PL/SQL Developer as-is, format it as a worksheet-runnable draft.
- Comment out the original procedure header line, insert a `DECLARE` section, and keep the body executable in a worksheet.
- Preserve the procedure name in the leading comment so the draft still maps back to the source routine.
- If the user instead wants a pure package-body splice fragment, say so explicitly and do not add the worksheet wrapper.
- Keep the rewrite generic enough to run in the same target environment that produced the diagnostics and test table.
- When the rewrite depends on a different source model than production, make that explicit in the header comments so comparison review is interpreted correctly.
- If the source routine targets a production table, rewrite the first validation draft against the mirrored `_TEST` table unless the user explicitly tells you to skip the test-table pass.

## Deployment Guidance

- Do not deploy directly from the first rewrite draft.
- After comparison review, generate a separate deployment artifact that removes `_TEST` from the target object references.
- If the source lives inside a package body, generate the deployment artifact as a package-body splice unless the user asks for a standalone worksheet draft.
- Preserve the exact validated logic from the test rewrite when creating the deployment version; only change environment-specific target names and any clearly intentional deployment wrappers.
- Treat deployment into the package as a distinct approval gate.
- Keep deployment prep separate from cleanup; cleanup should be its own final artifact after the package or source change has been accepted.

## Comparison Guidance

- Generate comparison SQL that checks row counts first, then metric-level drift, then row-level differences.
- Include both aggregate deltas and sampled row-level discrepancies when the user is validating a rewrite.
- Make the comparison output easy to read in SQLcl or SQL Developer.
- If the user wants a SQL*Plus wrapper, provide it as an optional separate wrapper script, not in the core comparison file.
- Do not include `SET PAGESIZE`, `SET LINESIZE`, `SET TRIMSPOOL`, `PROMPT`, or other SQL*Plus session commands in the default artifact.
- Use plain SQL plus comment headers so the file can be pasted directly into a SQL worksheet and run.
- Keep comparison templates generic so they can be reused across different procedures and target tables.

## Closeout Guidance

- Write a final cleanup SQL artifact in `sandbox/` when temporary test tables or validation objects were created.
- Cleanup scripts should be safe to rerun and should handle missing objects cleanly.
- Do not execute cleanup autonomously; hand the script to the user unless they explicitly ask you to run it.
- Before clearing `sandbox/`, propose the exact Git files to stage so the user can confirm the commit scope.
- After user approval, stage the intended files, create the commit with the approved message, and treat push as a separate explicit approval gate.
- If the user wants full BitBucket automation, TANK may run `git add`, `git commit`, and `git push` on the validated set of files, but only after confirming the scope and destination branch.
- Write the final work note to `worknotes/` after deployment approval or after the validated test cycle ends.
- After saving the work note file, paste the same ServiceNow-ready note block directly into chat so the user can copy it immediately without opening the file.
- Put the suggested commit message on the first line of the work note so it can be reused in BitBucket.
- Include an OCD check section that confirms logic review, target validation, doc sync, cleanup status, and remaining follow-ups.
- Include a ServiceNow-ready summary block that can be pasted directly into the ticket.
- Provide a practical time estimate based on the actual work span, not a minimal coding-only guess.
- Only recommend clearing `sandbox/` after the work note is written, cleanup is prepared, and the user confirms the local artifacts are no longer needed.

## Safety Rules

- Do not perform destructive DDL or DML unless the user explicitly asks.
- Ask before creating, dropping, truncating, or rewriting production objects.
- Keep PII and student data out of logs, summaries, and generated artifacts unless the user explicitly requires the data and the environment allows it.
- Keep the human in the loop for every promotion step.
- Never prefix output filenames with `~`; that marker is only for the discussion context, not for actual files.

