create or replace package load_aa_etl_main is -- consists of maintenance routines that covers objects on AA, AIM, LMS schemas
procedure etl_aa_report_latency (jobnumber number, processid varchar2, processname varchar2);  -- checks all tables with activity_date to see if there is any latency
procedure etl_aa_recalc_stats (jobnumber number, processid varchar2, processname varchar2);  -- regularly recalculates stats
procedure etl_aa_compress_partitions (jobnumber number, processid varchar2, processname varchar2); -- compress any partitions that are in non-active terms
procedure etl_aa_reduce_tables (jobnumber number, processid varchar2, processname varchar2); -- reduce job_log, REST and GRAPH tables in size
end load_aa_etl_main;
/

create or replace package body load_aa_etl_main is

procedure etl_aa_report_latency (jobnumber number, processid varchar2, processname varchar2) is
--DECLARE
v_etl_date     DATE := SYSDATE;
v_msg          VARCHAR2(2000);
v_instance     VARCHAR2(50) := upper('ALL'); -- inst from the jams job; used for determining instance
v_partition     NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_count        NUMBER := 0;
v_elapsed      NUMBER := 0;
v_total_count  NUMBER := 0;
v_job_id       VARCHAR2(32);
v_proc         VARCHAR2(100) := 'etl_aa_report_latency';
v_max_date     DATE;
v_sql          VARCHAR2(4000);
v_stale_tables sys.odcivarchar2list := sys.odcivarchar2list();
v_current_time DATE := SYSDATE;
v_threshold    DATE := SYSDATE - 5; -- threshold in days
-- Cursor to find tables with specified date columns
CURSOR c_date_tables IS
SELECT owner,
       table_name,
       'ACTIVITY_DATE' AS date_column
  FROM all_tab_columns
 WHERE column_name IN ('ACTIVITY_DATE')
   AND table_name NOT LIKE '%_GTT'
   AND owner IN ('UTL_D_AA', 'UTL_D_AIM', 'UTL_D_LMS');
BEGIN
-- dbms_output.enable(buffer_size => NULL);
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
-- Log the beginning of the process
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
-- Output header
dbms_output.put_line('Latency Report - Generated on ' || to_char(v_current_time, 'YYYY-MM-DD HH24:MI:SS'));
dbms_output.put_line('---------------------------------------------');
-- Loop through tables with date columns
FOR table_rec IN c_date_tables
LOOP
BEGIN
-- Dynamic SQL to get max date
v_sql := 'SELECT MAX(' || table_rec.date_column || ') 
                      FROM ' || table_rec.owner || '.' || table_rec.table_name;
EXECUTE IMMEDIATE v_sql
INTO v_max_date;
-- Check if max date is older than threshold
IF v_max_date < v_threshold THEN
v_stale_tables.extend;
v_stale_tables(v_stale_tables.last) := table_rec.owner || '.' || table_rec.table_name || ' (Last ' || table_rec.date_column || ': ' || to_char(v_max_date, 'YYYY-MM-DD HH24:MI:SS') || ')';
v_count := v_count + 1;
END IF;
EXCEPTION
WHEN OTHERS THEN
-- Log any errors but continue processing
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'Error checking ' || table_rec.owner || '.' || table_rec.table_name || ': ' || substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
END;
END LOOP;
-- Output stale tables
IF v_stale_tables.count > 0 THEN
v_msg := v_stale_tables.count || ' Found tables with high latency:';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
FOR i IN 1 .. v_stale_tables.count
LOOP
v_msg := v_stale_tables(i);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 1);
end loop;
ELSE
v_msg := 'No tables with high latency found.';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
END IF;
-- Log the end of the process
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_total_count := nvl(v_count, 0);
v_msg         := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, nvl(v_total_count, 1));
dbms_output.put_line(' --------- ');
-- Log any errors
EXCEPTION
WHEN OTHERS THEN
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
END etl_aa_report_latency;

procedure etl_aa_recalc_stats (jobnumber number, processid varchar2, processname varchar2) IS
-- =============================================================================
-- PURPOSE: Refreshes Oracle table statistics selectively for tables in ETL-related schemas to ensure query planner accuracy without needlessly re-gathering stats on recently analyzed objects.
--
-- TARGET(S): UTL_D_LMS.*, UTL_D_AA.*, UTL_D_AIM.* (table-level statistics in the Oracle data dictionary)
--
-- UNIQUE KEY / INDEX: owner + table_name (table identity used to select and invoke schema-specific gather routines)
--
-- BUSINESS LOGIC & CONDITIONS:
-- - Operates only on tables for which the ADS_ETL user has explicit TABLE privileges (checked via ALL_TAB_PRIVS).
-- - Limits candidate tables to owners: 'UTL_D_LMS', 'UTL_D_AA', 'UTL_D_AIM'.
-- - Excludes tables whose names match the regex '(_gtt|_tmp|_temp|_test)$' (case-insensitive), and excludes recycle bin names like '%BIN$%' and names containing '%#T%'.
-- - Requires a minimum approximate row count: COALESCE(tab.num_rows, 0) > 10000 (skips very small tables).
-- - Selects tables when any of these conditions are true:
--   - Oracle marks the table's existing statistics as stale (ast.stale_stats = 'YES').
--   - There is no statistics row yet for the table (ast.last_analyzed IS NULL).
--   - ALL_TABLES reports last_analyzed IS NULL (brand-new table as seen by ALL_TABLES).
--   - For very large tables (num_rows > 1,000,000): stats older than ~23 hours (tab.last_analyzed < SYSDATE - 23/24) are selected as a fallback if stale flag didn't trigger.
--   - For smaller tables (num_rows <= 1,000,000): stats older than 7 days (tab.last_analyzed < SYSDATE - 7) are selected as a weekly safety net.
-- - Orders candidate tables by descending num_rows so the largest tables are processed first.
-- - For each selected table, delegates the actual statistic gathering to a schema-specific package:
--   - UTL_D_LMS.gather_stats(table_name) when owner = 'UTL_D_LMS'
--   - UTL_D_AA.gather_stats(table_name) when owner = 'UTL_D_AA'
--   - UTL_D_AIM.gather_stats(table_name) when owner = 'UTL_D_AIM'
-- - Records job start, per-table info and completion info via ads_etl.insert_job_log, including a generated v_job_id based on a hash of proc/instance/partition/timestamp.
-- - Tracks and reports elapsed seconds and a running total of processed rows (v_total_count) reported back to the job log.
-- - Uses DBMS_OUTPUT to emit progress messages (primarily for interactive/operational visibility).
--
-- DEPENDENCIES:
-- - Dictionary views: SYS.ALL_TABLES, SYS.ALL_TAB_PRIVS, SYS.ALL_TAB_STATISTICS
-- - PL/SQL packages/procedures: UTL_D_LMS.gather_stats, UTL_D_AA.gather_stats, UTL_D_AIM.gather_stats
-- - Job logging utility: ADS_ETL.insert_job_log
-- - DBMS_OUTPUT for console messages
--
-- CONSTRAINTS & RISKS:
-- - Requires ADS_ETL to have explicit table privileges on candidate tables; missing privileges will exclude tables.
-- - Large-table processing can consume significant IO and CPU; the script avoids re-running on tables analyzed within ~23 hours (for very large tables) but will still potentially run long for many large tables in one batch.
-- - Running this too frequently wastes resources; intended to run as a "safety net" when auto-stats is disabled or in response to known large ETL changes.
-- - For very large systems, ordering by num_rows DESC may concentrate resource usage at start of run; consider windowing or parallelization if needed.
-- - Assumes schema-specific gather_stats procedures exist and behave idempotently and efficiently.
-- - If ADS_ETL lacks visibility into some objects due to grants or cross-schema issues, stats won't be gathered for those objects.
-- ============================================================================= 
-- DECLARE
v_etl_date    DATE := SYSDATE;
v_msg         VARCHAR2(2000);
v_instance    VARCHAR2(50) := upper('ALL'); -- inst from the jams job; used for determining instance
v_partition   NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_aa_recalc_stats';
-- CURSOR..
CURSOR c_terms IS
-- *** this only works on ADS_ETL ****
SELECT upper(tab.owner) AS table_owner,
       upper(tab.table_name) AS table_name,
       tab.last_analyzed,
       coalesce(tab.num_rows, 0) AS num_rows
  FROM sys.all_tables tab
-- make sure ADS_ETL has permissions on the table
  JOIN (SELECT DISTINCT atp.table_schema AS table_owner,
                        atp.table_name
          FROM sys.all_tab_privs atp
         WHERE atp.grantee = 'ADS_ETL'
           AND atp.type = 'TABLE'
           AND atp.table_schema IN ('UTL_D_LMS', 'UTL_D_AA', 'UTL_D_AIM')
           AND atp.table_name NOT LIKE '%#T%'
           AND atp.table_name NOT LIKE '%BIN$%') privs
    ON privs.table_owner = tab.owner
   AND privs.table_name = tab.table_name
-- leverage Oracle's stale stats indicator; include brand-new tables (no stats)
  LEFT JOIN sys.all_tab_statistics ast
    ON ast.owner = tab.owner
   AND ast.table_name = tab.table_name
   AND ast.partition_name IS NULL -- table-level stats
 WHERE tab.owner IN ('UTL_D_LMS', 'UTL_D_AA', 'UTL_D_AIM')
   AND NOT regexp_like(tab.table_name, '(_gtt|_tmp|_temp|_test)$', 'i')
   AND coalesce(tab.num_rows, 0) > 10000
   AND ((ast.stale_stats = 'YES' AND coalesce(tab.num_rows, 0) > 1000000) -- Oracle marks stats as stale (>= STALE_PERCENT change)
       OR ast.last_analyzed IS NULL -- no stats row yet
       OR tab.last_analyzed IS NULL -- brand new table from ALL_TABLES perspective
       OR (
       -- fallback drift for very large tables: if stats are older than ~23 hours,
       -- give them a refresh even if the stale flag didn't trip yet
         coalesce(tab.num_rows, 0) > 1000000 AND tab.last_analyzed < SYSDATE - (23 / 24)) OR (
        -- weekly cadence safety net for smaller tables
         coalesce(tab.num_rows, 0) <= 1000000 AND tab.last_analyzed < SYSDATE - 7))
 ORDER BY tab.num_rows DESC;
BEGIN
-- dbms_output.enable(buffer_size => NULL);
--
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
FOR rec IN c_terms
LOOP
v_count   := 0; -- reset count
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
-- isolate per-table errors so one failure doesn't stop the batch
BEGIN
IF rec.table_owner = 'UTL_D_LMS' THEN
utl_d_lms.gather_stats(rec.table_name);
ELSIF rec.table_owner = 'UTL_D_AA' THEN
utl_d_aa.gather_stats(rec.table_name);
ELSIF rec.table_owner = 'UTL_D_AIM' THEN
utl_d_aim.gather_stats(rec.table_name);
ELSE
dbms_output.put_line(' - schema disallowed -');
END IF;
v_count   := rec.num_rows; -- set count
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'Recalculating stats for ' || rec.table_name || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
EXCEPTION
WHEN OTHERS THEN
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr('Error on ' || rec.table_owner || '.' || rec.table_name || ': ' || REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
dbms_output.put_line(' --------- ');
END;
END LOOP; -- c_terms
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, nvl(v_total_count, 1));
-- log any errors
EXCEPTION
WHEN OTHERS THEN
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
END etl_aa_recalc_stats;

procedure etl_aa_compress_partitions (jobnumber number, processid varchar2, processname varchar2) IS
-- =============================================================================
-- PURPOSE: Compresses inactive partitions across learning management system tables to reduce storage footprint and improve query performance.
--
-- TARGET(S): UTL_D_LMS.*, UTL_D_AA.*, UTL_D_AIM.*
--
-- UNIQUE KEY / INDEX: table_owner, table_name, partition_name
--
-- BUSINESS LOGIC & CONDITIONS:
-- - Targets only partitions from three specific schemas: UTL_D_LMS, UTL_D_AA, and UTL_D_AIM.
-- - Excludes all partitions where compression is already enabled.
-- - Excludes system-generated tables (those matching BIN$% naming pattern).
-- - Excludes the default/catch-all partition for each table (identified by maximum partition position, typically MAXVALUE boundary).
-- - Excludes empty partitions (those with zero or null row counts).
-- - Derives protection window using partition HIGH_VALUE boundary (the authoritative Oracle partition definition), extracting either a 6-digit term code or 4-digit academic year.
-- - Protects (skips compression of) any partition covering an active or near-future academic period, defined as the current date falling within or before the partition's end date plus 365 days.
-- - Applies zero-code guard: treats any partition with a HIGH_VALUE resolving to '000000' or '0000' as a protected default partition to prevent accidental compression.
-- - Applies ROW STORE COMPRESS ADVANCED compression (Oracle 19c OLTP-optimized compression) to each unprotected, compressible partition while maintaining index usability via UPDATE INDEXES clause.
-- - Implements retry logic with exponential backoff (120-second delays) for resource contention (ORA-00054), allowing up to 30 retry attempts per partition before logging failure and moving to the next partition.
-- - Triggers post-compression operations (index rebuild and statistics gathering) once per table after all its compressible partitions have been processed.
-- - Processes partitions ordered by row count descending, attempting to compress largest partitions first.
-- - Tracks cumulative row count of successfully compressed partitions across the entire execution.
--
-- DEPENDENCIES: all_tab_partitions (Oracle data dictionary), zbtm.terms_by_group_v (academic term/year reference view), ads_etl.insert_job_log (logging procedure), ads_etl.rebuild_indexes (index maintenance procedure), dbms_stats (Oracle statistics gathering package), dbms_lock (sleep utility), dbms_assert (identifier quoting), dbms_output (console logging).
--
-- CONSTRAINTS & RISKS:
-- - Partition compression via ALTER TABLE MOVE is a blocking DDL operation; concurrent user activity on affected tables will cause ORA-00054 resource busy errors, triggering automatic retry logic.
-- - Requires that zbtm.terms_by_group_v view is accessible and correctly populated with end_date values; missing or incorrect term data may result in over-compression of active partitions.
-- - HIGH_VALUE extraction via regex is defensively designed but may fail silently on non-standard partition boundary formats; partitions with unrecognizable codes default to unprotected status.
-- - Memory and temporary tablespace usage scales with partition size during MOVE operations; very large partitions may cause temporary resource exhaustion.
-- - Index rebuild operations may take significant time on heavily indexed tables; concurrent queries may be queued during this phase.
-- - Full table statistics recalculation via dbms_stats.gather_table_stats may lock table briefly and consume CPU resources.
-- - Job logging via ads_etl.insert_job_log relies on external logging infrastructure; logging failures do not halt compression but may mask audit trails.
-- =============================================================================
-- DECLARE
v_etl_date    DATE := SYSDATE;
v_msg         VARCHAR2(2000);
v_instance    VARCHAR2(50) := upper('ALL');
v_partition   NUMBER := 0;
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_aa_compress_partitions';
-- Work buffers
l_tmp_long    LONG;
l_tmp_string  VARCHAR2(2000);
l_code6       VARCHAR2(6);
l_code4       VARCHAR2(4);
l_exists      NUMBER;
l_exec_string VARCHAR2(4000);
-- Retry config
v_max_retries NUMBER := 30;
v_retry_delay NUMBER := 120; -- seconds
-- Table-boundary tracking
v_current_table_owner             VARCHAR2(128) := NULL;
v_current_table_name              VARCHAR2(128) := NULL;
v_table_has_compressed_partitions BOOLEAN := FALSE;
-- -------------------------------------------------------------------------
-- CURSOR
-- KEY CHANGE: Removed "AND atp.partition_name NOT LIKE 'SYS%'"
--             Removed name-based term/year exclusions (handled by HIGH_VALUE)
--             Kept structural exclusions (BIN$, P000000, DISABLED, num_rows)
-- -------------------------------------------------------------------------
CURSOR c_compress IS
SELECT atp.table_owner,
       atp.table_name,
       atp.partition_name,
       atp.high_value,
       atp.num_rows,
       atp.tablespace_name
  FROM all_tab_partitions atp
 WHERE atp.table_owner IN ('UTL_D_LMS', 'UTL_D_AA', 'UTL_D_AIM')
   AND atp.compression = 'DISABLED'
   AND atp.table_name NOT LIKE 'BIN$%'
      -- Exclude the catch-all/default partition (high_value = MAXVALUE).
      -- We identify it by position rather than by name so it works whether
      -- the partition is called P000000, SYS_P######, or anything else.
   AND atp.partition_position != (SELECT MAX(p2.partition_position)
                                    FROM all_tab_partitions p2
                                   WHERE p2.table_owner = atp.table_owner
                                     AND p2.table_name = atp.table_name)
   AND nvl(atp.num_rows, 0) > 0
 ORDER BY atp.table_owner,
          atp.table_name,
          atp.num_rows DESC;
-- -------------------------------------------------------------------------
-- Defensive identifier quoting
-- -------------------------------------------------------------------------
FUNCTION qn(p_name VARCHAR2) RETURN VARCHAR2 IS
BEGIN
RETURN dbms_assert.enquote_name(p_name, FALSE);
END qn;

-- -------------------------------------------------------------------------
-- is_protected_partition
-- Derives term/year code directly from HIGH_VALUE (authoritative Oracle
-- partition boundary). Completely independent of partition naming.
--
-- Returns TRUE  -> partition covers an active or near-future period;
--                  do NOT compress.
-- Returns FALSE -> safe to compress.
--
-- Protection window mirrors original scripts: end_date + 365 days.
-- -------------------------------------------------------------------------
FUNCTION is_protected_partition(p_high_value LONG) RETURN BOOLEAN IS
l_protected BOOLEAN := FALSE;
BEGIN
-- Sanitize HIGH_VALUE to alphanumerics only
l_tmp_long   := substr(p_high_value, 1, 2000);
l_tmp_string := regexp_replace(l_tmp_long, '[^[:alnum:]]', '');
-- Prefer 6-digit term code; fall back to 4-digit academic year
l_code6 := regexp_substr(l_tmp_string, '([0-9]{6})', 1, 1);
l_code4 := CASE
           WHEN l_code6 IS NULL THEN
            regexp_substr(l_tmp_string, '([0-9]{4})', 1, 1)
           END;
-- -----------------------------------------------------------------------
-- ZERO-CODE GUARD
-- A HIGH_VALUE that resolves to all zeros is a default/catch-all partition
-- boundary (e.g., term_code = '000000' or acad_year = '0000').
-- These must NEVER be compressed regardless of any other logic.
-- -----------------------------------------------------------------------
IF l_code6 = '000000'
   OR l_code4 = '0000'
   OR l_tmp_string LIKE '%000000%' -- belt-and-suspenders: raw value check
 THEN
RETURN TRUE; -- treat as protected = do not compress
END IF;
IF l_code6 IS NOT NULL THEN
-- Check against term codes
SELECT COUNT(*)
  INTO l_exists
  FROM zbtm.terms_by_group_v t
 WHERE lower(t.term_code) = lower(l_code6)
   AND SYSDATE <= t.end_date + 365;
l_protected := (l_exists > 0);
ELSIF l_code4 IS NOT NULL THEN
-- Check against academic years (use max end_date within year)
SELECT COUNT(*)
  INTO l_exists
  FROM (SELECT DISTINCT fa_proc_year,
                        MAX(end_date) over(PARTITION BY fa_proc_year) AS max_end_date
          FROM zbtm.terms_by_group_v) y
 WHERE to_char(y.fa_proc_year) = l_code4
   AND SYSDATE <= y.max_end_date + 365;
l_protected := (l_exists > 0);
ELSE
-- No recognizable numeric code in HIGH_VALUE.
-- Treat as NOT protected  these are likely non-term partitions
-- (e.g., MAXVALUE catch-alls, or tables not keyed on term/year).
-- The MAXVALUE guard in the cursor already excludes the default
-- partition by position, so this branch should be rare.
l_protected := FALSE;
END IF;
RETURN l_protected;
EXCEPTION
WHEN OTHERS THEN
-- Defensive: if we cannot determine protection status, protect it.
v_msg := substr('WARN: is_protected_partition error (' || SQLERRM || ') - treating partition as protected.', 1, 2000);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'WARNING', v_msg, v_instance, v_partition, v_job_id, round((SYSDATE - v_etl_date) * 86400), 0);
RETURN TRUE; -- fail-safe: do not compress
END is_protected_partition;

-- -------------------------------------------------------------------------
-- compress_partition
-- ROW STORE COMPRESS ADVANCED = OLTP compression (19c standard).
-- UPDATE INDEXES keeps local indexes usable without a full rebuild.
-- -------------------------------------------------------------------------
FUNCTION compress_partition(p_owner      VARCHAR2,
                            p_table      VARCHAR2,
                            p_partition  VARCHAR2,
                            p_tablespace VARCHAR2) RETURN BOOLEAN IS
v_retry_count NUMBER := 0;
v_success     BOOLEAN := FALSE;
owner_q       VARCHAR2(261) := qn(p_owner);
table_q       VARCHAR2(261) := qn(p_table);
part_q        VARCHAR2(261) := qn(p_partition);
tspace_q      VARCHAR2(261) := qn(p_tablespace);
BEGIN
l_exec_string := 'ALTER TABLE ' || owner_q || '.' || table_q || ' MOVE PARTITION ' || part_q || ' TABLESPACE ' || tspace_q || ' ROW STORE COMPRESS ADVANCED UPDATE INDEXES';
WHILE v_retry_count <= v_max_retries
      AND NOT v_success
LOOP
BEGIN
EXECUTE IMMEDIATE l_exec_string;
v_success := TRUE;
EXCEPTION
WHEN OTHERS THEN
IF SQLCODE = -54 THEN
-- ORA-00054: resource busy
v_retry_count := v_retry_count + 1;
IF v_retry_count <= v_max_retries THEN
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr('Resource busy (ORA-00054): ' || p_owner || '.' || p_table || '.' || p_partition || ' (attempt ' || v_retry_count || ' of ' || v_max_retries || ')', 1, 2000);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'WARNING', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
dbms_lock.sleep(v_retry_delay);
ELSE
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr('Max retries exceeded: ' || p_owner || '.' || p_table || '.' || p_partition || ' - skipping.', 1, 2000);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
RETURN FALSE;
END IF;
ELSE
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr('Error compressing ' || p_owner || '.' || p_table || '.' || p_partition || ': ' || SQLERRM || ' (SQL: ' || l_exec_string || ')', 1, 2000);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
RETURN FALSE;
END IF;
END;
END LOOP;
RETURN v_success;
END compress_partition;

-- -------------------------------------------------------------------------
-- rebuild_indexes_with_retry
-- -------------------------------------------------------------------------
PROCEDURE rebuild_indexes_with_retry(p_owner VARCHAR2,
                                     p_table VARCHAR2) IS
v_retry_count NUMBER := 0;
v_success     BOOLEAN := FALSE;
v_error_msg   VARCHAR2(4000);
BEGIN
WHILE v_retry_count <= v_max_retries
      AND NOT v_success
LOOP
BEGIN
ads_etl.rebuild_indexes(p_table_name => p_table); -- procedure 
v_success := TRUE;
EXCEPTION
WHEN OTHERS THEN
v_error_msg := SQLERRM;
IF SQLCODE = -54 THEN
v_retry_count := v_retry_count + 1;
IF v_retry_count <= v_max_retries THEN
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr('Resource busy (ORA-00054) rebuilding indexes: ' || p_owner || '.' || p_table || ' (attempt ' || v_retry_count || ' of ' || v_max_retries || ')', 1, 2000);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'WARNING', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
dbms_lock.sleep(v_retry_delay);
ELSE
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr('Max retries exceeded rebuilding indexes: ' || p_owner || '.' || p_table || '. Error: ' || v_error_msg, 1, 2000);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
END IF;
ELSE
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr('Error rebuilding indexes: ' || p_owner || '.' || p_table || ': ' || v_error_msg, 1, 2000);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
v_retry_count := v_max_retries + 1; -- exit loop
END IF;
END;
END LOOP;
IF v_success THEN
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr('Indexes rebuilt: ' || p_owner || '.' || p_table, 1, 2000);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
END IF;
END rebuild_indexes_with_retry;

-- -------------------------------------------------------------------------
-- gather_table_stats
-- -------------------------------------------------------------------------
PROCEDURE gather_table_stats(p_owner VARCHAR2,
                             p_table VARCHAR2) IS
BEGIN
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr('Gathering stats: ' || p_owner || '.' || p_table || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 1, 2000);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
IF p_owner = 'UTL_D_LMS' THEN
utl_d_lms.gather_stats(p_table);
ELSIF p_owner = 'UTL_D_AA' THEN
utl_d_aa.gather_stats(p_table);
ELSIF p_owner = 'UTL_D_AIM' THEN
utl_d_aim.gather_stats(p_table);
ELSE
dbms_output.put_line(' - schema disallowed -');
END IF;
v_msg := substr('Stats gathered: ' || p_owner || '.' || p_table, 1, 2000);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
EXCEPTION
WHEN OTHERS THEN
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr('Error gathering stats: ' || p_owner || '.' || p_table || ': ' || SQLERRM, 1, 2000);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
END gather_table_stats;

-- -------------------------------------------------------------------------
-- process_table_operations
-- Called once per table after all its partitions are compressed.
-- -------------------------------------------------------------------------
PROCEDURE process_table_operations(p_owner VARCHAR2,
                                   p_table VARCHAR2) IS
BEGIN
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr('Post-compress ops: ' || p_owner || '.' || p_table || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 1, 2000);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
rebuild_indexes_with_retry(p_owner, p_table);
gather_table_stats(p_owner, p_table);
dbms_output.put_line(' --------- ');
END process_table_operations;

-- =============================================================================
-- MAIN
-- =============================================================================
BEGIN
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr('BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')', 1, 2000);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
FOR rec IN c_compress
LOOP
-- Table boundary: run post-compress ops when moving to a new table
IF v_current_table_owner IS NULL
   OR v_current_table_owner != rec.table_owner
   OR v_current_table_name != rec.table_name THEN
IF v_current_table_owner IS NOT NULL
   AND v_table_has_compressed_partitions THEN
process_table_operations(v_current_table_owner, v_current_table_name);
END IF;
v_current_table_owner             := rec.table_owner;
v_current_table_name              := rec.table_name;
v_table_has_compressed_partitions := FALSE;
v_elapsed                         := round((SYSDATE - v_etl_date) * 86400);
END IF;
-- Protection check via HIGH_VALUE (authoritative; name-independent)
IF is_protected_partition(rec.high_value) THEN
v_msg := ''; -- no output needed
CONTINUE;
END IF;
-- Log start of compression attempt
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr('START compress: ' || rec.table_owner || '.' || rec.table_name || '.' || rec.partition_name || ' (' || to_char(nvl(rec.num_rows, 0), 'FM999,999,999') || ' rows) at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 1, 2000);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- Compress
IF compress_partition(rec.table_owner, rec.table_name, rec.partition_name, rec.tablespace_name) THEN
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_total_count := v_total_count + nvl(rec.num_rows, 0);
v_msg         := substr('Compressed: ' || rec.partition_name || ' on ' || rec.table_owner || '.' || rec.table_name || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)', 1, 2000);
dbms_output.put_line(v_msg || ' rows: ' || to_char(nvl(rec.num_rows, 0)));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, nvl(rec.num_rows, 0));
v_table_has_compressed_partitions := TRUE;
END IF;
dbms_output.put_line(' --------- ');
END LOOP; -- c_compress
-- Final table's post-compress ops
IF v_current_table_owner IS NOT NULL
   AND v_table_has_compressed_partitions THEN
process_table_operations(v_current_table_owner, v_current_table_name);
END IF;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr('END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)', 1, 2000);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, nvl(v_total_count, 1));
EXCEPTION
WHEN OTHERS THEN
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 2000);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
-- Best-effort: still run post-compress ops if any partitions were compressed
IF v_current_table_owner IS NOT NULL
   AND v_table_has_compressed_partitions THEN
BEGIN
v_msg := substr('Post-error cleanup ops: ' || v_current_table_owner || '.' || v_current_table_name, 1, 2000);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, round((SYSDATE - v_etl_date) * 86400), 0);
process_table_operations(v_current_table_owner, v_current_table_name);
EXCEPTION
WHEN OTHERS THEN
v_msg := substr('Error during cleanup: ' || SQLERRM, 1, 2000);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, round((SYSDATE - v_etl_date) * 86400), 0);
END;
END IF;
END etl_aa_compress_partitions;

procedure etl_aa_reduce_tables (jobnumber number, processid varchar2, processname varchar2) is
-- =============================================================================
-- PURPOSE: Removes archived rows older than 30 days from designated ETL tables and reclaims unused disk space through intelligent batched deletion and high-water-mark reset operations.
--
-- TARGET(S): UTL_D_LMS.*, UTL_D_AA.*, UTL_D_AIM.* (tables matching pattern %rest_%, %graph_%, or job_log with ACTIVITY_DATE column)
--
-- UNIQUE KEY / INDEX: ROWID (internal row identifier used for batch-scoped deletion)
--
-- BUSINESS LOGIC & CONDITIONS:
-- - Discovers tables within three designated schemas (UTL_D_LMS, UTL_D_AA, UTL_D_AIM) where the current user (ADS_ETL) has explicit TABLE privileges.
-- - Excludes shadow tables (marked with #T or BIN$ patterns) and the SHD_DEMOGRAPHICS_TABLEAU reference table.
-- - Identifies only tables with active row populations (num_rows > 0) whose names match either 'rest_*', 'graph_*', or the literal 'job_log' table.
-- - Processes tables in descending order of row count (largest first) to optimize cleanup impact.
-- - For each eligible table, counts rows where activity_date is older than 30 days (activity_date < SYSDATE - 30).
-- - Skips tables that do not possess an ACTIVITY_DATE column or have zero eligible rows for deletion.
-- - Executes a batched deletion strategy in fixed chunks of 10,000 rows per batch, with an intermediate COMMIT after each batch to prevent undo segment exhaustion and ORA-01555 snapshot-too-old errors.
-- - Within each batch, identifies candidate rows using a ROWNUM-bounded subquery scan to force Oracle to use a STOPKEY execution plan, ensuring efficient early termination per batch.
-- - Temporarily enables ROW MOVEMENT on the table if not already enabled (required to allow Oracle to physically relocate rows during space compaction).
-- - Performs a two-phase SHRINK SPACE operation: first COMPACT CASCADE (compacts row data below high-water mark without moving HWM, allows concurrent DML), then SHRINK SPACE CASCADE (resets HWM to last populated block and returns freed extents to tablespace).
-- - Restores the original ROW MOVEMENT state after completion to maintain schema integrity and prevent interference with partition operations.
-- - Gathers fresh table statistics via schema-specific gather_stats procedures after HWM reset to ensure optimizer accuracy.
-- - Logs all major lifecycle events (activation, batch progress, completion, errors) via ads_etl.insert_job_log() with elapsed time and row counts.
-- - Isolates each table within its own exception handler to prevent a single table failure from aborting the entire job; always attempts to restore original ROW MOVEMENT state on error.
--
-- DEPENDENCIES: sys.all_tables, sys.all_tab_privs, sys.all_tab_columns, ads_etl.insert_job_log(), utl_d_lms.gather_stats(), utl_d_aa.gather_stats(), utl_d_aim.gather_stats()
--
-- CONSTRAINTS & RISKS:
-- - Requires ALTER TABLE privilege on all target tables; permission-based discovery guards against unauthorized access attempts.
-- - Batching strategy with 10,000-row chunks is tunable but fixed; very large tables may require extended runtime if thousands of batches are needed.
-- - Two-phase SHRINK SPACE CASCADE operation requires brief exclusive lock during final HWM adjustment; should be scheduled during low-concurrency windows to minimize contention.
-- - SHRINK SPACE COMPACT CASCADE depends on successful row relocation; tables with unusual block fragmentation or PCTFREE settings may experience slower compaction.
-- - Dynamic SQL is used for all table operations (DELETE, ALTER); malformed table names in sys.all_tables could cause parse errors (mitigated by permission join on all_tab_privs).
-- - Statistics gathering dispatches to three separate schema-specific procedures; failure in any gather_stats call will log a warning but does not halt the job or block the next table.
-- - Per-table exception handler performs best-effort ROW MOVEMENT restore on error; if restore itself fails, exception is silently suppressed to prevent cascading failures.
-- =============================================================================
-- DECLARE
v_etl_date     DATE := SYSDATE;
v_msg          VARCHAR2(2000);
v_instance     VARCHAR2(50) := upper('ALL');
v_partition    NUMBER := 0;
v_count        NUMBER := 0;
v_batch_count  NUMBER := 0;
v_elapsed      NUMBER := 0;
v_total_count  NUMBER := 0;
v_job_id       VARCHAR2(32);
v_proc         VARCHAR2(100) := 'etl_aa_reduce_tables';
v_can_shrink   NUMBER := 0;
v_row_move_on  NUMBER := 0;
v_row_move_pre VARCHAR2(10); -- captures original ROW MOVEMENT state before we touch it
-- Batch size: tunable.  10k rows per commit cycle keeps undo segments
-- small, allows concurrent sessions to interleave, and prevents
-- snapshot-too-old errors on busy tables.
c_batch_size CONSTANT PLS_INTEGER := 10000;
-- -------------------------------------------------------------------------
-- Discovery cursor: permission-guarded, unchanged from original
-- -------------------------------------------------------------------------
CURSOR c_terms IS
SELECT upper(tab.owner) AS table_owner,
       upper(tab.table_name) AS table_name,
       tab.num_rows,
       tab.row_movement -- need current state before ALTER
  FROM sys.all_tables tab
  JOIN (SELECT DISTINCT atp.table_schema AS table_owner,
                        atp.table_name
          FROM sys.all_tab_privs atp
         WHERE atp.grantee = 'ADS_ETL'
           AND atp.type = 'TABLE'
           AND atp.table_schema IN ('UTL_D_LMS', 'UTL_D_AA', 'UTL_D_AIM')
           AND atp.table_name NOT LIKE '%#T%'
           AND atp.table_name NOT LIKE '%BIN$%') privs
    ON privs.table_owner = tab.owner
   AND privs.table_name = tab.table_name
 WHERE tab.owner IN ('UTL_D_LMS', 'UTL_D_AA', 'UTL_D_AIM')
   AND tab.table_name <> 'SHD_DEMOGRAPHICS_TABLEAU'
   and tab.NUM_ROWS > 0 -- ensure that the table is still active and has rows
   AND (lower(tab.table_name) LIKE '%rest_%' OR lower(tab.table_name) LIKE '%graph_%' OR lower(tab.table_name) IN ('job_log'))
 ORDER BY tab.num_rows DESC;
-- ============================================================================
BEGIN
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
-- ==========================================================================
-- STRATEGY: Batched DELETE + SHRINK SPACE CASCADE
-- --------------------------------------------------------------------------
-- PROBLEM WITH PLAIN DELETE:
--   A single DELETE of millions of rows in one shot generates a massive undo
--   segment, holds row-level locks for the entire duration, risks ORA-01555
--   (snapshot too old) on busy tables, and does NOT lower the high-water mark
--   even after a COMMIT.  Subsequent full scans still read every block up to
--   the old HWM regardless of how many rows were removed.
--
-- WHAT BATCHING FIXES:
--   Breaking the DELETE into c_batch_size chunks with an intermediate COMMIT
--   after each batch means:
--     - Undo is released incrementally; no single massive undo segment.
--     - Row locks are held only for the current batch window (~milliseconds).
--     - Concurrent sessions can read/write between batches without blocking.
--     - ORA-01555 risk is eliminated because the consistent-read snapshot
--       is refreshed at each COMMIT boundary.
--
-- WHAT SHRINK SPACE FIXES:
--   After the batched DELETE the blocks are empty but the high-water mark is
--   still at its original position.  SHRINK SPACE CASCADE:
--     - Compacts row data below the HWM (requires ROW MOVEMENT ENABLED
--       so Oracle can physically relocate rows to lower blocks).
--     - Resets the HWM to the last populated block.
--     - CASCADE also shrinks all indexes on the table in the same pass.
--     - Requires only ALTER TABLE privilege  no DBA role needed.
--     - Does NOT lock the table exclusively during the compact phase;
--       Oracle uses a series of short row-migration locks, leaving the
--       table available for concurrent DML throughout.
--     - The final HWM adjustment at the end of SHRINK requires a brief
--       exclusive lock, but this is sub-second on compacted data.
--
-- SEQUENCE PER TABLE:
--   1. Check ACTIVITY_DATE column exists.
--   2. Count eligible rows.
--   3. Save current ROW MOVEMENT state.
--   4. ENABLE ROW MOVEMENT (required by SHRINK; restore state afterward).
--   5. Batched DELETE loop with per-batch COMMIT.
--   6. SHRINK SPACE COMPACT CASCADE  (compacts rows + indexes, no HWM move yet)
--   7. SHRINK SPACE CASCADE           (moves HWM, brief exclusive lock)
--   8. Restore original ROW MOVEMENT state.
--   9. Gather statistics.
-- ==========================================================================
FOR rec IN c_terms
LOOP
v_count        := 0;
v_batch_count  := 0;
v_row_move_pre := nvl(rec.row_movement, 'DISABLED');
-- -----------------------------------------------------------------------
-- GUARD: Verify ACTIVITY_DATE column exists on this table.
-- -----------------------------------------------------------------------
SELECT COUNT(*)
  INTO v_can_shrink -- reusing variable; 1 = column present
  FROM sys.all_tab_columns
 WHERE owner = rec.table_owner
   AND table_name = rec.table_name
   AND column_name = 'ACTIVITY_DATE';
IF v_can_shrink = 0 THEN
v_msg := 'SKIP (no ACTIVITY_DATE) - ' || rec.table_owner || '.' || rec.table_name;
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'WARN', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
dbms_output.put_line(' --------- ');
CONTINUE;
END IF;
-- -----------------------------------------------------------------------
-- COUNT rows eligible for removal
-- -----------------------------------------------------------------------
EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM ' || rec.table_owner || '.' || rec.table_name || ' WHERE activity_date < SYSDATE - 30'
INTO v_count;
dbms_output.put_line(rec.table_owner || '.' || rec.table_name || ' - rows eligible for removal: ' || v_count);
IF v_count = 0 THEN
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'NO ACTION - ' || rec.table_owner || '.' || rec.table_name || ' (0 rows older than 30 days)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
dbms_output.put_line(' --------- ');
CONTINUE;
END IF;
-- -----------------------------------------------------------------------
-- Per-table block: isolated so one table failure does not abort the job
-- -----------------------------------------------------------------------
BEGIN
-- -------------------------------------------------------------------
-- STEP 1: Enable ROW MOVEMENT so SHRINK SPACE can relocate rows.
--         We only issue the ALTER if it is not already enabled,
--         and we record the pre-existing state so we can restore it.
-- -------------------------------------------------------------------
IF v_row_move_pre = 'DISABLED' THEN
EXECUTE IMMEDIATE 'ALTER TABLE ' || rec.table_owner || '.' || rec.table_name || ' ENABLE ROW MOVEMENT';
v_msg := 'ROW MOVEMENT ENABLED - ' || rec.table_owner || '.' || rec.table_name;
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
END IF;
-- -------------------------------------------------------------------
-- STEP 2: Batched DELETE loop.
--         Each iteration removes at most c_batch_size rows and
--         commits immediately.  SQL%ROWCOUNT drives the loop exit
--         so we never over-scan.  ROWNUM bounding on the inner
--         query ensures Oracle uses a STOPKEY plan rather than a
--         full delete scan on every iteration.
-- -------------------------------------------------------------------
LOOP
EXECUTE IMMEDIATE 'DELETE FROM ' || rec.table_owner || '.' || rec.table_name || ' WHERE ROWID IN (' || '    SELECT r FROM (' || '        SELECT ROWID AS r' || '          FROM ' || rec.table_owner || '.' || rec.table_name ||
                  '         WHERE activity_date < SYSDATE - 30' || '           AND ROWNUM <= ' || c_batch_size || '    )' || ')';
v_batch_count := SQL%ROWCOUNT;
COMMIT; -- release undo and row locks for this batch
EXIT WHEN v_batch_count = 0; -- no more eligible rows
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BATCH DELETE - ' || rec.table_owner || '.' || rec.table_name || ' batch rows: ' || v_batch_count || ' running total: ' || (v_total_count + v_batch_count) || ' (' || v_elapsed || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_batch_count);
v_total_count := v_total_count + v_batch_count;
END LOOP;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'DELETE COMPLETE - ' || rec.table_owner || '.' || rec.table_name || ' total rows removed: ' || v_count || ' (' || v_elapsed || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- -------------------------------------------------------------------
-- STEP 3: SHRINK SPACE COMPACT CASCADE
--         Phase 1 of the two-phase shrink.  Compacts row data by
--         migrating rows from high blocks to low blocks and rebuilds
--         index entries for relocated rows (CASCADE).
--         Does NOT move the HWM yet  the table stays fully online.
--         Run this first to minimise the duration of the exclusive
--         lock in STEP 4.
-- -------------------------------------------------------------------
EXECUTE IMMEDIATE 'ALTER TABLE ' || rec.table_owner || '.' || rec.table_name || ' SHRINK SPACE COMPACT CASCADE';
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'SHRINK COMPACT DONE - ' || rec.table_owner || '.' || rec.table_name || ' (' || v_elapsed || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
-- -------------------------------------------------------------------
-- STEP 4: SHRINK SPACE CASCADE
--         Phase 2.  Moves the HWM down to the last populated block
--         and returns freed extents to the tablespace.  CASCADE
--         also finalises index shrink.  Requires a brief exclusive
--         lock only for the HWM adjustment  typically sub-second
--         after the COMPACT pass has already relocated all rows.
-- -------------------------------------------------------------------
EXECUTE IMMEDIATE 'ALTER TABLE ' || rec.table_owner || '.' || rec.table_name || ' SHRINK SPACE CASCADE';
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'SHRINK HWM RESET DONE - ' || rec.table_owner || '.' || rec.table_name || ' (' || v_elapsed || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
-- -------------------------------------------------------------------
-- STEP 5: Restore original ROW MOVEMENT state.
--         If ROW MOVEMENT was DISABLED before we started, turn it
--         back off.  Leaving it enabled on tables that do not need
--         it can interfere with partition operations and rowid-based
--         application logic in some schemas.
-- -------------------------------------------------------------------
IF v_row_move_pre = 'DISABLED' THEN
EXECUTE IMMEDIATE 'ALTER TABLE ' || rec.table_owner || '.' || rec.table_name || ' DISABLE ROW MOVEMENT';
v_msg := 'ROW MOVEMENT RESTORED (DISABLED) - ' || rec.table_owner || '.' || rec.table_name;
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
END IF;
-- -------------------------------------------------------------------
-- STEP 6: Gather statistics  HWM reset invalidates all prior stats.
-- -------------------------------------------------------------------
IF rec.table_owner = 'UTL_D_LMS' THEN
utl_d_lms.gather_stats(rec.table_name);
ELSIF rec.table_owner = 'UTL_D_AA' THEN
utl_d_aa.gather_stats(rec.table_name);
ELSIF rec.table_owner = 'UTL_D_AIM' THEN
utl_d_aim.gather_stats(rec.table_name);
ELSE
v_msg := 'WARN - schema not in gather_stats dispatch: ' || rec.table_owner;
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'WARN', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
END IF;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'STATS GATHERED - ' || rec.table_owner || '.' || rec.table_name || ' (' || v_elapsed || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
EXCEPTION
-- -------------------------------------------------------------------
-- Per-table handler: attempt to restore ROW MOVEMENT before moving
-- on so the table is not left in an altered state after a failure.
-- -------------------------------------------------------------------
WHEN OTHERS THEN
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'ERROR on ' || rec.table_owner || '.' || rec.table_name || ' - ' || substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
-- Best-effort ROW MOVEMENT restore so the table is not left
-- in an unintended state regardless of where the failure occurred
IF v_row_move_pre = 'DISABLED' THEN
BEGIN
EXECUTE IMMEDIATE 'ALTER TABLE ' || rec.table_owner || '.' || rec.table_name || ' DISABLE ROW MOVEMENT';
EXCEPTION
WHEN OTHERS THEN
NULL; -- restore must not cascade
END;
END IF;
END; -- per-table block
dbms_output.put_line(' --------- ');
END LOOP; -- c_terms
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows removed total: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
EXCEPTION
WHEN OTHERS THEN
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
RAISE;
END etl_aa_reduce_tables;

end load_aa_etl_main;