# Diagnose Reference: Oracle PL/SQL ETL

Load this alongside SKILL.md when the bug is missing or dropped data in an Oracle 19c PL/SQL ETL procedure. The generic six-phase discipline still applies; this file supplies the Oracle-specific plumbing.

---

## Working Directory

Save all probe scripts, diagnostic SQL, and throwaway test files to:

`C:\Users\wgriffith2\Dropbox (Liberty University)\Liberty University\ADS_ETL\sandbox\`

Never write to `$env:TEMP`. The sandbox keeps work organized and lets Drew re-run probes later.

---

## Credentials and SQL*Plus Invocation

Service-account credentials live in `C:\Users\wgriffith2\.claude\.env.work` as `LU_USERNAME`, `LU_PASSWORD`, `LU_TNS`.

Run a diagnostic script:

```powershell
$e = @{}
Get-Content "C:\Users\wgriffith2\.claude\.env.work" |
  Where-Object { $_ -match '^\w' -and $_ -match '=' } |
  ForEach-Object { $k,$v = $_ -split '=',2; $e[$k.Trim()] = $v.Trim() }
sqlplus -S "$($e.LU_USERNAME)/$($e.LU_PASSWORD)@$($e.LU_TNS)" "@C:\Users\wgriffith2\Dropbox (Liberty University)\Liberty University\ADS_ETL\sandbox\probe.sql"
```

Standard SQL*Plus header for clean output:

```sql
SET PAGESIZE 500 LINESIZE 300 FEEDBACK OFF ECHO OFF TRIMOUT ON TRIMSPOOL ON
```

---

## Package References

Liberty procedures live in packages. Always schema-qualify:

```sql
ads_etl.load_aa_etl_casas.etl_aa_casas_advising_audit_tsi(...)
```

---

## Read-Only and FERPA Rules

- Diagnostics are SELECT-only. Never run INSERT, UPDATE, DELETE, MERGE, or DDL through SQL*Plus inside this skill.
- Proxy access permits DML on other schemas but DDL only on the current schema. Diagnose does not need either.
- Student data is PII. Do not SELECT and display name, SSN, address, or contact fields. Aggregate to counts or anonymized IDs when surfacing results in chat.
- If a fix needs DML or DDL, hand it back to Drew as a manual block, never execute it.

---

## Phase 1 (Feedback Loop) for Missing-Data Bugs

The loop here is a probe script that returns row counts at each stage of the procedure's data flow. Build it in three layers:

1. **Source counts.** Raw counts on each base table the procedure reads, filtered by the cohort that is missing (term, program, date window).
2. **Driver counts.** Counts after applying the procedure's driver cursor or CTE filter.
3. **Target counts.** Counts on the destination table for the same cohort.

A correct loop pinpoints the stage where the cohort disappears. That stage becomes the focus of Phase 3 hypotheses.

---

## Procedure Parsing Recipe

Before writing probes, read the procedure and extract:

1. **Driver source.** The cursor or CTE that seeds the row set. Look for `CURSOR c_name IS SELECT ...` or top-level `WITH name AS (...)`. If multiple, ask Drew which one feeds the missing category.
2. **Time-frame filter.** The `WHERE` clause on the driver. Common shapes: `term_code = p_term`, `effective_date BETWEEN ... AND ...`, `last_activity_date >= SYSDATE - n`. Confirm it returns rows for the missing cohort.
3. **Join chain.** Every `JOIN` after the driver. Each join is a potential dropout point (inner join with sparse right side, missing code in a lookup table).
4. **Filter predicates.** Every `AND` clause downstream of the driver. Each predicate is a potential exclusion.
5. **Parameter values.** Literal values to substitute for `p_term`, `p_instance`, etc., when running standalone probes.

List all schema-qualified table names. The probe script will hit each one.

---

## Hypothesis Patterns for Missing Data

Common root causes, ranked by frequency in this codebase:

1. **Upstream cohort cleared.** Source table no longer contains the rows. Confirm with a raw count on the base table for the cohort.
2. **Lookup code missing.** A join to a code table (`UTL_CODES`, `STVTERM`, ADMR codes) returns nothing because the code was retired or renamed. Confirm with a LEFT JOIN count vs INNER JOIN count.
3. **Date window expired.** Driver filter uses `SYSDATE - n` or a hardcoded date and the cohort falls outside. Confirm by widening the window.
4. **Term not in driver.** Procedure loops over a term list that no longer includes the target term. Confirm by inspecting the term-loop source.
5. **New filter added.** Recent code change introduced a predicate that excludes the cohort. Confirm with `git log` on the package file and bisect the filter.
6. **Schedule not running.** JAMS job disabled or failed. Out of scope for this skill; flag for Drew.

---

## Probe SQL Template

```sql
SET PAGESIZE 500 LINESIZE 300 FEEDBACK OFF ECHO OFF

PROMPT === Source counts ===
SELECT 'base_table_1' src, COUNT(*) n FROM schema.base_table_1
 WHERE term_code = '202640' AND program_code = 'L2GOV';

PROMPT === Driver counts (matches cursor filter) ===
SELECT COUNT(*) FROM schema.base_table_1 b
  JOIN schema.lookup l ON l.code = b.code
 WHERE b.term_code = '202640' AND b.program_code = 'L2GOV';

PROMPT === Inner vs Left join (detects lookup dropouts) ===
SELECT
  (SELECT COUNT(*) FROM schema.base b JOIN schema.lookup l ON l.code = b.code WHERE ...) inner_n,
  (SELECT COUNT(*) FROM schema.base b LEFT JOIN schema.lookup l ON l.code = b.code WHERE ...) left_n
FROM dual;

PROMPT === Target counts ===
SELECT COUNT(*) FROM schema.target_table
 WHERE term_code = '202640' AND program_code = 'L2GOV';

EXIT;
```

A gap between `inner_n` and `left_n` means a lookup join is dropping rows. A gap between driver counts and target counts means a downstream filter or insert path is dropping them.

---

## Output Conventions

- Show probe results inline in chat as small tables. Do not paste raw SQL*Plus output dumps.
- When the dropout stage is identified, state it plainly: "Rows present at source. Driver cursor returns zero because lookup `UTL_ADMR_CODE` has no row for `GOV`."
- Never write a handoff document. The conversation is the record.

---

# Runaway Procedures (JAMS Timeout)

Use this section when the procedure runs over the JAMS 1-hour limit, a scheduled ETL took too long, or a query is slow and needs plan tuning. Same six-phase discipline applies; the feedback loop is EXPLAIN PLAN plus the queries below.

## Phase 1 (Feedback Loop) for Runaway Procedures

The loop is a single diagnostic script that returns four things: the execution plan, indexes on touched tables, row counts, and stats freshness. Re-run after any change (stats gather, new index, hint added) to confirm the plan improved.

## Procedure Parsing Recipe for Runaways

Before writing diagnostics, read the procedure and extract:

1. **Problem statement.** The single large SQL (MERGE, INSERT-SELECT, BULK COLLECT cursor) that is consuming time. If multiple candidates, ask Drew which one.
2. **Table list.** All unique schema-qualified table names referenced.
3. **Literal parameter values.** Infer values for `p_term`, `p_instance`, etc. from WHERE-clause literals so EXPLAIN PLAN can run standalone with no bind variables.

## Diagnostic SQL Template

Substitute actual table names and literal values before running. Write to the sandbox, not `$env:TEMP`.

```sql
SET PAGESIZE 500 LINESIZE 300 FEEDBACK OFF ECHO OFF TRIMOUT ON TRIMSPOOL ON

-- ====================================================
-- STEP 1: EXPLAIN PLAN
-- ====================================================
EXPLAIN PLAN FOR
[paste problem SQL here — replace all PL/SQL variables with literal values];

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', NULL, 'ALL'));

-- ====================================================
-- STEP 2: INDEXES
-- ====================================================
SELECT DISTINCT table_name,
                index_name,
                column_name,
                column_position
  FROM all_ind_columns
 WHERE lower(table_name) IN ('table1', 'table2', 'table3')
   AND index_name NOT LIKE 'BIN$%'
 ORDER BY table_name, index_name, column_position;

-- ====================================================
-- STEP 3: ROW COUNTS
-- ====================================================
SELECT owner,
       table_name,
       num_rows,
       last_analyzed
  FROM all_tables
 WHERE owner IN ('UTL_D_LMS', 'UTL_D_AA', 'UTL_D_AIM', 'ZCANVAS_DATA')
   AND lower(table_name) IN ('table1', 'table2', 'table3')
 ORDER BY num_rows DESC NULLS LAST;

-- ====================================================
-- STEP 4: STATS FRESHNESS
-- ====================================================
SELECT owner,
       table_name,
       last_analyzed,
       stale_stats,
       num_rows
  FROM all_tab_statistics
 WHERE owner IN ('UTL_D_LMS', 'UTL_D_AA', 'UTL_D_AIM', 'ZCANVAS_DATA')
   AND lower(table_name) IN ('table1', 'table2', 'table3')
   AND partition_name IS NULL
 ORDER BY last_analyzed ASC NULLS FIRST;

EXIT
```

## Hypothesis Patterns for Runaways

Find the bottleneck in the plan: highest `TempSpc`, highest `Cost`, or `TABLE ACCESS STORAGE FULL` on a large table. Then check in order:

1. **Stale stats.** `stale_stats = 'YES'` or `last_analyzed IS NULL`. Most common root cause.
2. **Missing or unusable index.** Join or filter columns not covered.
3. **Wrong join method.** Large table (>1M rows) used as hash-join build side.

## Explain Plan Warning Signs

| Pattern | Meaning | Fix |
|---|---|---|
| `TempSpc` column has large values | Hash join spilling to disk | Force NL + index on the offending table |
| `TABLE ACCESS STORAGE FULL` on large table | Full scan ignoring available index | Check join columns vs index columns; add `INDEX` hint |
| `PARTITION LIST ALL` across all partitions | Partition pruning not happening | Verify instance/term_code filter reaches the partitioned table |
| Note: `dynamic statistics used` | Oracle doesn't trust its own stats | Gather stats first; re-run explain plan after |
| Note: `this is an adaptive plan` | Plan may have switched mid-execution | Add `OPT_PARAM('_adaptive_plans' 'false')` hint |
| Rows estimate wildly off vs reality | Stale stats or missing histogram | Gather stats; or override with CARDINALITY hint |

## Covering Index Analysis (Check Before Adding Hints)

When EXPLAIN PLAN shows "TABLE ACCESS BY GLOBAL INDEX ROWID BATCHED" on a large table:

- Check if filter columns are in the composite index with join columns
- If not, a covering index often beats hints by 3-5x (eliminates ROWID lookups entirely)
- Example: join on `(instance, course_section_id, user_id)` but filter on `points_possible > 0`
  - Old: index covers joins, then 751K ROWID lookups for filter
  - New: covering index with `points_possible` → fast full scan, no ROWID overhead
- Pattern: `CREATE INDEX idx(join_col1, join_col2, join_col3, filter_col) COMPRESS 2;`
- Always re-run EXPLAIN PLAN after creating index and gathering stats before applying hints

## Hint Patterns

All hints go inside the outermost `SELECT` of the problem statement.

**Force nested loop + index** (most common fix for hash join temp spill):
```sql
SELECT /*+ USE_NL(alias) INDEX(alias INDEX_NAME) */ ...
```

**Prevent hash join on a specific table:**
```sql
SELECT /*+ NO_USE_HASH(alias) */ ...
```

**Control join order** (smallest/most-filtered first):
```sql
SELECT /*+ LEADING(se qd sqa qqa caqb tgt) */ ...
```

**Lock in the plan** (prevent adaptive plan mid-execution switch):
```sql
SELECT /*+ OPT_PARAM('_adaptive_plans' 'false') */ ...
```

**Override cardinality estimate** when stats can't be gathered:
```sql
SELECT /*+ CARDINALITY(alias, 310000) */ ...
```

**Combine multiple hints:**
```sql
SELECT /*+ LEADING(se qd sqa)
           USE_NL(tgt)
           INDEX(tgt STUDENT_QUIZZES_UNIQUE_INDX)
           OPT_PARAM('_adaptive_plans' 'false') */ ...
```

## Fix Options (lowest to highest invasiveness)

### Option 1: Stats Gather (zero code change)

Self-service for `UTL_D_LMS`, `UTL_D_AA`, `UTL_D_AIM` only. Output as a manual handback — Drew runs this proxied in:

```sql
BEGIN utl_d_lms.gather_stats('TABLE_NAME'); END;
BEGIN utl_d_aa.gather_stats('TABLE_NAME');  END;
BEGIN utl_d_aim.gather_stats('TABLE_NAME'); END;
```

All other schemas (`ZCANVAS_DATA`, etc.): flag as DBA escalation item. After gathering, re-run EXPLAIN PLAN to confirm the plan improved before applying hints.

### Option 2: Optimizer Hints

Show the proposed hint addition in chat. Wait for Drew's explicit "yes" before touching the file.

### Option 3: Query Rewrite

Last resort. Show the full rewrite in chat. Wait for explicit confirmation.

**Never edit the package file without Drew's confirmed approval.**

## Apply and Test

After confirmation:

1. Edit the file at the original path.
2. Output a ready-to-run test block:

```sql
-- Run in SQLcl to confirm the fix
BEGIN
  schema_name.procedure_name(
    p_instance  => 'inferred_value',
    p_term_code => 'inferred_value'
  );
END;
```

Infer parameters from WHERE clause literals. Ask Drew if not confident.

## Schema Access Matrix

| Schema | Stats self-service | DDL self-service | Notes |
|---|---|---|---|
| `UTL_D_LMS` | Yes — proxied, via `gather_stats()` | Yes | Primary LMS schema |
| `UTL_D_AA` | Yes — proxied, via `gather_stats()` | Yes | Academic Affairs |
| `UTL_D_AIM` | Yes — proxied, via `gather_stats()` | Yes | AIM schema |
| `ZCANVAS_DATA` | No — DBA required | No — DBA required | Raw Canvas source data |
| All others | No — DBA required | No — DBA required | |

## Rules for Runaways

- Never edit the package file without explicit confirmation from Drew.
- Diagnostics are SELECT-only. Never run DML or DDL via SQL*Plus inside this skill.
- Always output a DBA escalation section when non-`UTL_` schemas need stats or DDL.

---

# ORA-00001: Unique Constraint Violated

Use this section when a procedure throws `ORA-00001: unique constraint (SCHEMA.CONSTRAINT_NAME) violated`. Same six-phase discipline applies; the feedback loop is a duplicate check query built from the constraint's column list.

## What Drew Provides

- The full ORA-00001 error text (contains the constraint name)
- The package file path
- Any additional context from the error (term code, instance, etc.)

## Phase 1 (Feedback Loop) for ORA-00001

1. Parse the constraint name from the error: `SCHEMA.CONSTRAINT_NAME`
2. Query `ALL_CONS_COLUMNS` to get the exact column list for that constraint
3. Read the proc file; locate the INSERT, MERGE, or BULK COLLECT statement whose target table matches the constraint's table name
   - If multiple statements target the same table and the responsible one is ambiguous, ask Drew explicitly before proceeding
4. **Find the loop driver.** Read the proc and identify what it loops on - typically a CURSOR or FOR loop over term codes, instances, or similar. Extract the loop variable name and its data source. The current value being processed is usually visible in the error context (e.g., `p_term = '202540'`). If not clear from the error, inspect the loop driver source to determine the filter.
5. Extract the source SELECT from the INSERT/MERGE/BULK COLLECT statement
6. **Apply the loop filter to the source SELECT.** Add the loop variable value as a literal WHERE clause filter (e.g., `AND term_code = '202540'`). Never run the dup check unfiltered on a large table.
7. Build the dup check query (template below) with the constraint columns in the `PARTITION BY`
8. Run via SQL*Plus; report only the top 10 rows if dupes are found - these become the sample keys for all subsequent probes

## Constraint Column Lookup

```sql
SET PAGESIZE 500 LINESIZE 300 FEEDBACK OFF ECHO OFF TRIMOUT ON TRIMSPOOL ON

PROMPT === Constraint columns ===
SELECT c.owner,
       c.constraint_name,
       c.constraint_type,
       cc.column_name,
       cc.position
  FROM all_constraints c
  JOIN all_cons_columns cc
    ON cc.owner           = c.owner
   AND cc.constraint_name = c.constraint_name
 WHERE c.owner           = UPPER('&constraint_schema')
   AND c.constraint_name = UPPER('&constraint_name')
 ORDER BY cc.position;

EXIT;
```

Substitute the schema and constraint name parsed from the error. The `column_name` rows at each `position` become the `PARTITION BY` list.

## Duplicate Check Template

```sql
SET PAGESIZE 500 LINESIZE 300 FEEDBACK OFF ECHO OFF TRIMOUT ON TRIMSPOOL ON

PROMPT === Duplicate check (top 10) ===
SELECT *
  FROM (
        SELECT chkdup.*,
               COUNT(1) OVER (PARTITION BY col1, col2) AS dupcnt
          FROM (
                [SOURCE SELECT HERE]
               ) chkdup
       )
 WHERE dupcnt > 1
   AND ROWNUM <= 10;

EXIT;
```

Replace `col1, col2` with the column list from the constraint lookup. Replace `[SOURCE SELECT HERE]` with the source SELECT extracted from the proc. Substitute literal values for any PL/SQL bind variables (`p_term`, `p_instance`, etc.) using context from the error or ask Drew.

If the dup check returns zero rows, the duplicate is not in the source query - state this and ask Drew for more context (may be a concurrent session issue or a prior load left orphaned rows).

## Hypothesis Patterns for ORA-00001

Ranked by frequency in this codebase:

1. **Fan-out join.** A JOIN to a table with multiple matching rows per key multiplies the row set. The dup check will show many rows with the same constraint-column values differing only on non-key columns. Probe by progressively stripping joins from the source SELECT and counting rows at each step until the count stabilizes.
2. **Missing DISTINCT.** Source returns logically duplicate rows across all constraint columns. The dup check rows will be identical on every column, not just the key. Probe by adding `SELECT DISTINCT` to the source and comparing counts.
3. **Dirty source data.** The upstream table already contains duplicate values for the constraint columns before the proc runs. Confirm by running the dup check against the raw source table directly (no joins). If confirmed, this is a data-layer issue - stop, hand back to Drew as a manual block. Do not attempt a code fix.

## Fan-Out Probe Template

After the dup check returns the top 10 sample rows, extract the key identifiers from those rows (PIDM, LUID, username, or whatever natural key applies). Use those literal values to scope all subsequent probes - never re-run the full source query unfiltered.

```sql
PROMPT === Row count at each join layer (scoped to sample keys) ===
-- Replace the IN list with the key values from the top 10 dup check results
SELECT COUNT(*) n FROM (
  [SOURCE SELECT with one JOIN removed]
)
WHERE pidm IN (12345, 67890, ...);  -- substitute actual key column and values
```

Strip joins one at a time, outermost first, and count after each removal. The count that jumps identifies the offending join. Keeping the key filter means each probe runs against a handful of rows rather than the full population.

## Fix Options (lowest to highest invasiveness)

Show proposed fix in chat. Wait for Drew's explicit confirmation before editing the package file.

### Option 1: Add DISTINCT

Only valid when the dup check confirms rows are fully identical across every column - meaning no JOIN is producing extra rows, the source data itself simply contains literal duplicates.

Do NOT suggest DISTINCT if the duplicate rows differ on any non-key column. That pattern means a fan-out join is present and DISTINCT would hide it rather than fix it. Confirm the root cause via the fan-out probe before proposing this option.

### Option 2: ROW_NUMBER() Dedup Subquery

When rows differ on non-key columns (fan-out root cause), pick one row per key. Before proposing the fix, query the target table's indexes to determine the tiebreak column - use the index column list from `ALL_IND_COLUMNS` (same query already run in the runaway diagnostic) to identify a suitable ordering column. Pick the most selective non-key indexed column as the tiebreak. If no clear candidate exists from the indexes, ask Drew.

First validate the dedup logic against the sample key values from the dup check:

```sql
-- Validate on sample keys first
SELECT *
  FROM (
        SELECT t.*,
               ROW_NUMBER() OVER (PARTITION BY col1, col2 ORDER BY tiebreak_col DESC) AS rn
          FROM ([SOURCE SELECT]) t
         WHERE pidm IN (12345, 67890, ...)  -- sample keys from dup check
       )
 WHERE rn = 1;
```

Confirm the result looks correct for those sample records before proposing the same pattern on the full filtered source query.

### Option 3: Data Fix

If dirty source data is confirmed: hand back to Drew as a manual block. Never run DML autonomously.

### Option 4: DDL (Drop/Recreate)

If Drew determines the target table itself is corrupt or needs restructuring: hand back as a manual block. Never run DDL autonomously.

## Rules for ORA-00001

- Never edit the package file without explicit confirmation from Drew.
- Diagnostics are SELECT-only. Never run INSERT, UPDATE, DELETE, or DDL via SQL*Plus.
- Surface only top 10 sample rows - never dump full duplicate sets.
- Student PII rules apply: aggregate to counts or anonymized IDs when surfacing results.
- Stay in the loop until Drew explicitly says to stop.
