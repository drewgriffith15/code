create or replace package load_aa_etl_golem is
procedure etl_aa_term_dates(jobnumber number, processid varchar2, processname varchar2); 
procedure etl_aa_year_dates(jobnumber number, processid varchar2, processname varchar2);
end load_aa_etl_golem;
/

create or replace package body load_aa_etl_golem is

procedure etl_aa_year_dates(jobnumber number, processid varchar2, processname varchar2) IS
v_etl_date     DATE := SYSDATE;
v_msg          VARCHAR2(2000);
v_instance     VARCHAR2(50) := upper('ALL');
v_partition    NUMBER := 0;
v_count        NUMBER := 0;
v_insert_count NUMBER := 0;
v_elapsed      NUMBER := 0;
v_total_count  NUMBER := 0;
v_job_id       VARCHAR2(32);
v_proc         VARCHAR2(100) := 'etl_aa_year_dates';
BEGIN
--
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
--
dbms_lock.sleep(1);
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
--
utl_d_aa.truncate_table(v_table_name => 'acad_year_dates');
--
v_count := 0;
dbms_lock.sleep(1);
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - acad_year_dates - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
--
-- ==========================================================================
-- FULL RELOAD: DATE SPINE INSERT
-- ==========================================================================
INSERT INTO utl_d_aa.acad_year_dates
(acad_year,
 group_code,
 report_date,
 acyr_year,
 acyr_desc,
 acad_year_active_ind,
 acad_year_rank,
 acad_year_next_rank,
 report_number,
 report_timestamp,
 expiration_date,
 acad_start_date,
 acad_end_date,
 timeframe_start_date,
 timeframe_end_date,
 timeframe_start_term,
 timeframe_current_term,
 timeframe_end_term,
 fiscal_day_number,
 current_fiscal_day_number,
 fiscal_week_number,
 current_fiscal_week_number,
 acad_day_number,
 current_acad_day_number,
 acad_week_number,
 current_acad_week_number,
 day_of_week,
 current_day_of_week)
WITH term_date AS
 (SELECT stvterm_fa_proc_yr AS acad_year,
         stvterm_acyr_code AS acyr_year,
         stvacyr_desc AS acyr_desc,
         tbg.group_code,
         MIN(stvterm_start_date) AS acad_year_start_date,
         MAX(stvterm_end_date) AS acad_year_end_date
    FROM stvterm s
    JOIN stvacyr
      ON stvacyr_code = stvterm_acyr_code
    JOIN zbtm.terms_by_group_v tbg
      ON tbg.term_code = s.stvterm_code
   WHERE s.stvterm_fa_proc_yr IS NOT NULL
   GROUP BY s.stvterm_fa_proc_yr,
            stvterm_acyr_code,
            stvacyr_desc,
            tbg.group_code),
--
curr_year AS
 (SELECT group_code,
         MIN(acyr_year) AS acad_year_curr
    FROM term_date t
   WHERE trunc(SYSDATE) < t.acad_year_end_date
   GROUP BY group_code),
--
year_meta AS
 (SELECT t.acad_year,
         t.acyr_year,
         t.acyr_desc,
         t.group_code,
         CASE
         WHEN t.acyr_year = cy.acad_year_curr THEN
          'Y'
         ELSE
          'N'
         END AS acad_year_active_ind,
         t.acad_year_start_date,
         t.acad_year_end_date,
         CASE
         WHEN t.acyr_year <= cy.acad_year_curr THEN
          rank() over(PARTITION BY t.group_code ORDER BY CASE
                      WHEN t.acyr_year <= cy.acad_year_curr THEN
                       0
                      ELSE
                       1
                      END, t.acyr_year DESC)
         END AS acad_year_rank,
         CASE
         WHEN t.acyr_year > cy.acad_year_curr THEN
          rank() over(PARTITION BY t.group_code ORDER BY CASE
                      WHEN t.acyr_year > cy.acad_year_curr THEN
                       0
                      ELSE
                       1
                      END, t.acyr_year ASC)
         END AS acad_year_next_rank
    FROM term_date t
    JOIN curr_year cy
      ON cy.group_code = t.group_code),
--
terms_spine AS
 (SELECT t.fa_proc_year AS acad_year,
         ym.acyr_year,
         ym.acyr_desc,
         ym.group_code,
         ym.acad_year_active_ind,
         ym.acad_year_rank,
         ym.acad_year_next_rank,
         (ym.acad_year_start_date - 180) AS timeframe_start_date,
         ym.acad_year_end_date AS timeframe_end_date,
         ym.acad_year_start_date AS acad_start_date,
         to_date('01-JUL-' || to_char(ym.acad_year_start_date, 'YYYY'), 'DD-MON-YYYY') AS fiscal_year_start_date,
         MAX((SELECT MAX(t2.end_date)
               FROM zbtm.terms_by_group_v t2
              WHERE t2.fa_proc_year = to_char(t.fa_proc_year)
                AND t2.group_code = t.group_code
                AND t2.semester NOT IN ('WIN'))) AS acad_end_date,
         MIN((SELECT MIN(t2.term_code)
               FROM zbtm.terms_by_group_v t2
              WHERE t2.fa_proc_year = to_char(t.fa_proc_year)
                AND t2.group_code = t.group_code
                AND t2.semester NOT IN ('WIN'))) AS timeframe_start_term,
         MAX((SELECT MAX(t2.term_code)
               FROM zbtm.terms_by_group_v t2
              WHERE t2.fa_proc_year = to_char(t.fa_proc_year)
                AND t2.group_code = t.group_code
                AND t2.semester NOT IN ('WIN'))) AS timeframe_end_term
    FROM zbtm.terms_by_group_v t
    JOIN year_meta ym
      ON ym.acad_year = t.fa_proc_year
     AND ym.group_code = t.group_code
   WHERE t.term_code NOT IN ('000000')
     AND t.semester NOT IN ('WIN')
     AND t.start_date >= DATE '2008-08-15'
     AND (ym.acad_year_start_date - 180) < SYSDATE
   GROUP BY t.fa_proc_year,
            ym.acyr_year,
            ym.acyr_desc,
            ym.group_code,
            ym.acad_year_active_ind,
            ym.acad_year_rank,
            ym.acad_year_next_rank,
            ym.acad_year_start_date,
            ym.acad_year_end_date),
--
date_spine AS
 (SELECT LEVEL - 1 AS numb FROM dual CONNECT BY LEVEL <= 600),
--
-- =========================================================================
-- ROOT SPINE: cross-join date offsets onto each academic year per group
-- =========================================================================
raw_spine AS
 (SELECT ts.acad_year,
         ts.group_code,
         ts.acyr_year,
         ts.acyr_desc,
         ts.acad_year_active_ind,
         ts.acad_year_rank,
         ts.acad_year_next_rank,
         ts.acad_start_date,
         ts.acad_end_date,
         ts.timeframe_start_date,
         ts.timeframe_end_date,
         ts.timeframe_start_term,
         ts.timeframe_end_term,
         ts.fiscal_year_start_date,
         ds.numb,
         trunc(ts.timeframe_start_date + ds.numb) AS report_date
    FROM terms_spine ts
    JOIN date_spine ds
      ON ts.timeframe_start_date + ds.numb < trunc(SYSDATE)
     AND to_char(trunc(ts.timeframe_start_date + ds.numb), 'MM/DD') <> '02/29')
-- =========================================================================
-- MAIN SELECT
-- =========================================================================
SELECT
 rs.acad_year,
 rs.group_code,
 rs.report_date,
 rs.acyr_year,
 rs.acyr_desc,
 rs.acad_year_active_ind,
 rs.acad_year_rank,
 rs.acad_year_next_rank,
 -- Report Timestamp Fields
 to_number(to_char(rs.report_date + 1, 'YYYYMMDD')) AS report_number,
 to_date(to_char(rs.report_date, 'MM/DD/YYYY') || ' 23:59:00', 'MM/DD/YYYY HH24:MI:SS') AS report_timestamp,
 to_date(to_char(rs.report_date, 'MM/DD/YYYY') || ' 23:58:59', 'MM/DD/YYYY HH24:MI:SS') AS expiration_date,
 -- Academic Year Boundary Dates
 rs.acad_start_date,
 rs.acad_end_date,
 rs.timeframe_start_date,
 to_date(to_char(rs.timeframe_end_date, 'MM/DD/YYYY') || ' 23:59:00', 'MM/DD/YYYY HH24:MI:SS') AS timeframe_end_date,
 -- Timeframe Term Anchors
 rs.timeframe_start_term,
 nvl((SELECT MIN(CASE
                WHEN to_date(to_char(rs.report_date, 'MM/DD/YYYY') || ' 23:59:00', 'MM/DD/YYYY HH24:MI:SS')
                       BETWEEN t2.start_date - 180 AND t2.end_date + 7 THEN
                 t2.term_code
                END)
       FROM zbtm.terms_by_group_v t2
      WHERE t2.fa_proc_year = to_char(rs.acad_year)
        AND t2.group_code = rs.group_code
        AND t2.semester NOT IN ('WIN')), rs.timeframe_end_term) AS timeframe_current_term,
 rs.timeframe_end_term,
 -- Fiscal Day Number
 (rs.report_date - rs.fiscal_year_start_date) AS fiscal_day_number,
 -- -------------------------------------------------------------------------
 -- FIX: PARTITION BY group_code so each group resolves its own "today" row.
 --      The fallback derives the live fiscal anchor from SYSDATE directly
 --      using the 4-digit YYYY format to avoid century truncation with 'YY'.
 -- -------------------------------------------------------------------------
 coalesce(MAX(CASE
              WHEN rs.report_date = trunc(SYSDATE - 1)
               AND rs.acad_year_active_ind = 'Y' THEN
               (rs.report_date - rs.fiscal_year_start_date)
              END) over(PARTITION BY rs.group_code),
          (trunc(SYSDATE - 1) - CASE
           WHEN to_number(to_char(trunc(SYSDATE - 1), 'MM')) >= 7 THEN
            to_date('01-JUL-' || to_char(trunc(SYSDATE - 1), 'YYYY'), 'DD-MON-YYYY')
           ELSE
            to_date('01-JUL-' || to_char(add_months(trunc(SYSDATE - 1), -12), 'YYYY'), 'DD-MON-YYYY')
           END)) AS current_fiscal_day_number,
 -- Fiscal Week Number
 floor((rs.report_date - rs.fiscal_year_start_date) / 7) AS fiscal_week_number,
 -- FIX: PARTITION BY group_code
 coalesce(MAX(CASE
              WHEN rs.report_date = trunc(SYSDATE - 1)
               AND rs.acad_year_active_ind = 'Y' THEN
               floor((rs.report_date - rs.fiscal_year_start_date) / 7)
              END) over(PARTITION BY rs.group_code),
          floor((trunc(SYSDATE - 1) - CASE
                 WHEN to_number(to_char(trunc(SYSDATE - 1), 'MM')) >= 7 THEN
                  to_date('01-JUL-' || to_char(trunc(SYSDATE - 1), 'YYYY'), 'DD-MON-YYYY')
                 ELSE
                  to_date('01-JUL-' || to_char(add_months(trunc(SYSDATE - 1), -12), 'YYYY'), 'DD-MON-YYYY')
                 END) / 7)) AS current_fiscal_week_number,
 -- Academic Day Number
 CASE
 WHEN rs.acad_start_date IS NOT NULL THEN
  (rs.report_date - trunc(rs.acad_start_date))
 END AS acad_day_number,
-- -------------------------------------------------------------------------
 -- ROOT CAUSE FIX for current_acad_day_number:
 --
 -- The original fallback used Oracle 'YY' 2-digit format to reconstruct the
 -- fa_proc_year key (e.g. '25'||'26' = '2526').  This is correct for years
 -- 2000-2099 but is fragile.  More critically, the analytic window used
 -- over() with NO partition, meaning a match found in group_code 'A' for
 -- acad_year 2526 was broadcast to ALL groups and ALL years including prior
 -- years that are still present in the spine.  A prior-year row (e.g. 2425)
 -- would inherit the day-offset that was computed relative to the 2526
 -- acad_start_date, producing a number that is ~365 days too large for every
 -- non-current year row.
 --
 -- Fix 1: PARTITION BY rs.group_code  — limits the broadcast to rows that
 --         share the same institutional group so each group resolves its own
 --         "today" independently.
 --
 -- Fix 2: Add AND rs.acad_year_active_ind = 'Y' inside the CASE guard so the
 --         MAX only captures the row from the academically current year.
 --         Without this guard, if SYSDATE-1 happened to fall inside the
 --         pre-window of a future year that also has spine rows (because the
 --         timeframe_start_date extends 180 days before its acad_start_date),
 --         two competing rows could produce an ambiguous MAX.
 --
 -- Fix 3: Fallback uses 4-digit 'YYYY' format via TO_CHAR to build the
 --         fa_proc_year lookup key, removing the implicit century dependency
 --         on 'YY'.  The two-year concat logic (YYYY suffix pair) is preserved
 --         as it correctly mirrors the Banner fa_proc_year convention.
 --
 -- Syntax Fix: Corrected Oracle MOD() usage from infix operator (A MOD B)
 --             to function notation MOD(A, B).
 -- -------------------------------------------------------------------------
 CASE
     WHEN rs.acad_start_date IS NOT NULL THEN
         COALESCE(
             -- Primary path: find the spine row for SYSDATE-1 that belongs to the
             -- active academic year within this group and broadcast its day offset.
             MAX(CASE
                 WHEN rs.report_date = TRUNC(SYSDATE - 1)
                  AND rs.acad_start_date IS NOT NULL
                  AND rs.acad_year_active_ind = 'Y' THEN
                  (rs.report_date - TRUNC(rs.acad_start_date))
                 END) OVER(PARTITION BY rs.group_code),
             -- Fallback path: SYSDATE-1 is not yet in the spine (e.g. procedure runs
             -- before today's row exists).  Derive the active AY start date directly
             -- from zbtm using the same group_code as the current row so the result
             -- is always group-scoped.  Uses 4-digit YYYY to avoid 'YY' ambiguity.
             (TRUNC(SYSDATE - 1) -
              (SELECT MIN(t_curr.start_date)
                 FROM zbtm.terms_by_group_v t_curr
                WHERE t_curr.fa_proc_year =
                         -- Reconstruct the Banner 4-char fa_proc_year for the current AY.
                         -- July or later  →  current calendar year is the "start" year.
                         -- Before July    →  prior calendar year is the "start" year.
                         CASE
                             WHEN TO_NUMBER(TO_CHAR(TRUNC(SYSDATE - 1), 'MM')) >= 7 THEN
                                 LPAD(TO_CHAR(MOD(TO_NUMBER(TO_CHAR(TRUNC(SYSDATE - 1), 'YYYY')), 100)), 2, '0') ||
                                 LPAD(TO_CHAR(MOD(TO_NUMBER(TO_CHAR(TRUNC(SYSDATE - 1), 'YYYY')) + 1, 100)), 2, '0')
                             ELSE
                                 LPAD(TO_CHAR(MOD(TO_NUMBER(TO_CHAR(TRUNC(SYSDATE - 1), 'YYYY')) - 1, 100)), 2, '0') ||
                                 LPAD(TO_CHAR(MOD(TO_NUMBER(TO_CHAR(TRUNC(SYSDATE - 1), 'YYYY')), 100)), 2, '0')
                         END
                  AND t_curr.group_code = rs.group_code
                  AND t_curr.semester   != 'WIN')))
 END AS current_acad_day_number,
 -- Academic Week Number
 CASE
 WHEN rs.acad_start_date IS NOT NULL THEN
  floor((rs.report_date - trunc(rs.acad_start_date)) / 7)
 END AS acad_week_number,
-- FIX: Corrected Oracle MOD() usage and ensured proper handling of analytic 
 -- function nesting. The MOD operator is not supported in Oracle PL/SQL/SQL; 
 -- the MOD(n, m) function must be used.
 CASE
     WHEN rs.acad_start_date IS NOT NULL THEN
         COALESCE(
             MAX(CASE
                 WHEN rs.report_date = TRUNC(SYSDATE - 1)
                  AND rs.acad_start_date IS NOT NULL
                  AND rs.acad_year_active_ind = 'Y' THEN
                  FLOOR((rs.report_date - TRUNC(rs.acad_start_date)) / 7)
                 END) OVER(PARTITION BY rs.group_code),
             FLOOR((TRUNC(SYSDATE - 1) -
                    (SELECT MIN(t_curr.start_date)
                       FROM zbtm.terms_by_group_v t_curr
                      WHERE t_curr.fa_proc_year =
                               CASE
                                   WHEN TO_NUMBER(TO_CHAR(TRUNC(SYSDATE - 1), 'MM')) >= 7 THEN
                                       LPAD(TO_CHAR(MOD(TO_NUMBER(TO_CHAR(TRUNC(SYSDATE - 1), 'YYYY')), 100)), 2, '0') ||
                                       LPAD(TO_CHAR(MOD(TO_NUMBER(TO_CHAR(TRUNC(SYSDATE - 1), 'YYYY')) + 1, 100)), 2, '0')
                                   ELSE
                                       LPAD(TO_CHAR(MOD(TO_NUMBER(TO_CHAR(TRUNC(SYSDATE - 1), 'YYYY')) - 1, 100)), 2, '0') ||
                                       LPAD(TO_CHAR(MOD(TO_NUMBER(TO_CHAR(TRUNC(SYSDATE - 1), 'YYYY')), 100)), 2, '0')
                               END
                        AND t_curr.group_code = rs.group_code
                        AND t_curr.semester   != 'WIN')) / 7)
         )
 END AS current_acad_week_number,
 -- Calendar Day-of-Week Fields
 to_number(to_char(rs.report_date, 'D')) AS day_of_week,
 -- FIX: PARTITION BY group_code for consistency; active-year guard added
 coalesce(MAX(CASE
              WHEN rs.report_date = trunc(SYSDATE - 1)
               AND rs.acad_year_active_ind = 'Y' THEN
               to_number(to_char(rs.report_date, 'D'))
              END) over(PARTITION BY rs.group_code),
          to_number(to_char(trunc(SYSDATE - 1), 'D'))) AS current_day_of_week
  FROM raw_spine rs
 ORDER BY rs.acad_year,
          rs.group_code,
          rs.numb;
--
v_insert_count := SQL%ROWCOUNT;
v_total_count  := v_total_count + v_insert_count;
COMMIT;
--
dbms_lock.sleep(1);
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'INSERT - acad_year_dates - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_insert_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_insert_count);
dbms_output.put_line(' --------- ');
--
dbms_lock.sleep(1);
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
--
EXCEPTION
WHEN OTHERS THEN
ROLLBACK;
dbms_lock.sleep(1);
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
RAISE;
END etl_aa_year_dates;

END load_aa_etl_golem;