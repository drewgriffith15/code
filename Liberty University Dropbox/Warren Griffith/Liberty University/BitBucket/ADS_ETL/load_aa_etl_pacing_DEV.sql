create or replace package load_aa_etl_pacing_dev is
procedure etl_aa_pacing_student_enrollment (jobnumber number, processid varchar2, processname varchar2); --- 20260112 - WGRIFFITH2  - Initial release 
procedure etl_aa_pacing_student_hours (jobnumber number, processid varchar2, processname varchar2); --- 20260112 - WGRIFFITH2  - Initial release 
procedure etl_aa_pacing_student_seats (jobnumber number, processid varchar2, processname varchar2); --- 20260112 - WGRIFFITH2  - Initial release 
procedure etl_aa_pacing_student_fci (jobnumber number, processid varchar2, processname varchar2); --- 20260112 - WGRIFFITH2  - Initial release 
procedure etl_aa_pacing_retention (jobnumber number, processid varchar2, processname varchar2); --- 20260112 - WGRIFFITH2  - Initial release 
procedure etl_aa_pacing_tableau (jobnumber number, processid varchar2, processname varchar2); --- 20260112 - WGRIFFITH2  - Initial release 
end load_aa_etl_pacing_dev;
/

create or replace package body load_aa_etl_pacing_dev is

procedure etl_aa_pacing_retention (jobnumber number, processid varchar2, processname varchar2) is 
-- DECLARE
-- Local control variables
v_etl_date     DATE := SYSDATE;
v_msg          VARCHAR2(2000);
v_instance     VARCHAR2(50) := upper('ALL'); -- instance identifier (can be overridden by processid)
v_partition    NUMBER := 0; -- partition / jobnumber (can be overridden by jobnumber)
v_count        NUMBER := 0;
v_delete_count NUMBER := 0;
v_insert_count NUMBER := 0;
v_elapsed      NUMBER := 0;
v_total_count  NUMBER := 0;
v_job_id       VARCHAR2(32);
v_proc         VARCHAR2(100) := 'etl_aa_pacing_retention';
v_report_code  VARCHAR2(7);
-- Cursor to enumerate report dates across cohort timeframes
CURSOR c_terms IS
SELECT to_char(dates.acad_year - 101) AS cohort_year,
       dates.acad_year AS return_year,
       dates.report_date,
       dates.report_timestamp,
       dates.timeframe_start_date,
       dates.timeframe_end_date
  FROM utl_d_aa.acad_year_dates dates
 WHERE dates.report_timestamp >= SYSDATE - 3 -- run overlap just in case of weekends/fails, but only n-1 is needed normally
   AND dates.group_code = 'STD' --only need standard group_code
 ORDER BY dates.acad_year        ASC,
          dates.report_timestamp ASC;
BEGIN
-- dbms_output.enable(buffer_size => NULL);
-- Generate a stable job identifier
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY HH24:MI:SS'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_proc || ' - ' || v_instance || ' - ' || to_char(v_partition) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY HH24:MI:SS') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
-- Main processing loop across computed report dates
FOR rec IN c_terms
LOOP
v_count   := 0;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || rec.return_year || ' - ' || rec.report_timestamp || ' - ' || to_char(v_partition) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY HH24:MI:SS') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-------------------------------------------------------------------------
-- Single INSERT covering all 9 report codes via UNION ALL.
--
-- The /*+ MATERIALIZE */ hint instructs Oracle to write the CTE result into
-- an internal temporary segment exactly once. Every UNION ALL branch then
-- reads from those materialized rowsets rather than re-executing subqueries.
--
-- Retention-specific notes:
--   - rbase filters retention_log rows to the current as-of timestamp and return_year.
--   - elog_yoy picks the end-of-year (yr_rank = 1) canonical enrollment row per cohort year
--     to ensure a single row per pidm with stable program attributes for grouping.
--   - Excludes WIN semester for consistency with legacy logic.
--
-- The outer LEFT JOIN to pacing_log filters out already-loaded row_hashes,
-- preserving the original incremental/idempotent load pattern.
-------------------------------------------------------------------------
INSERT INTO utl_d_aa.pacing_log
(report_code,
 report_date,
 acad_year,
 term_code,
 ptrm_code,
 coll_code,
 camp_code,
 metric_name,
 metric_value,
 row_hash,
 activity_date)
WITH rbase AS
 (SELECT rlog.pidm,
         rlog.cohort_year,
         rlog.return_year,
         rlog.returned,
         rlog.return_camp,
         rlog.graduated,
         rlog.from_date,
         rlog.to_date
    FROM utl_d_aa.retention_log rlog
   WHERE rlog.cohort_year = rec.cohort_year
     AND rlog.return_year = rec.return_year
     AND rec.report_timestamp BETWEEN rlog.from_date AND rlog.to_date), -- using report_timestamp for effective date to show YTD numbers
elog_yoy AS
 (SELECT /*+ MATERIALIZE */
   el.pidm,
   el.acad_year,
   el.term_code,
   el.camp_code,
   el.levl_code,
   el.coll_code,
   el.degc_code,
   el.majr_code
    FROM utl_d_aa.enrollments_log el
    JOIN rbase rb
      ON rb.pidm = el.pidm
     AND rb.cohort_year = el.acad_year
   WHERE rb.cohort_year = rec.cohort_year
     AND rec.report_timestamp BETWEEN el.from_date AND el.to_date -- using report_timestamp for effective date to show YTD numbers
     AND el.yr_rank = 1 -- you can only use this if the year is el; which it is; yr_rank pulls last term of enrollment 
     AND el.semester <> 'WIN'),
---------------------------------------------------------------------
-- TRS: Total returning by campus where returned and did not return to same campus
---------------------------------------------------------------------
trs_rows AS
 (SELECT 'TRS' AS report_code,
         rec.report_date AS report_date,
         rec.return_year AS acad_year,
         NULL AS term_code,
         NULL AS ptrm_code,
         NULL AS coll_code,
         el.camp_code AS camp_code,
         'Total' AS metric_name,
         COUNT(el.pidm) AS metric_value,
         standard_hash(nvl(to_char('TRS'), '<NULL>') || '#' || nvl(to_char(rec.report_date, 'YYYYMMDD'), '<NULL>') || '#' || nvl(to_char(rec.return_year), '<NULL>') || '#' || '<NULL>' || '#' || '<NULL>' || '#' || '<NULL>' || '#' ||
                       nvl(to_char(el.camp_code), '<NULL>') || '#' || nvl(to_char('Total'), '<NULL>'), 'MD5') AS row_hash,
         SYSDATE AS activity_date
    FROM rbase rb
    JOIN elog_yoy el
      ON el.pidm = rb.pidm
   WHERE rb.returned = 1
     AND rb.return_camp = 0 HAVING COUNT(el.pidm) > 0
   GROUP BY el.camp_code),
---------------------------------------------------------------------
-- TRC: Total returning by campus (any return)
---------------------------------------------------------------------
trc_rows AS
 (SELECT 'TRC' AS report_code,
         rec.report_date AS report_date,
         rec.return_year AS acad_year,
         NULL AS term_code,
         NULL AS ptrm_code,
         NULL AS coll_code,
         el.camp_code AS camp_code,
         'Total' AS metric_name,
         COUNT(el.pidm) AS metric_value,
         standard_hash(nvl(to_char('TRC'), '<NULL>') || '#' || nvl(to_char(rec.report_date, 'YYYYMMDD'), '<NULL>') || '#' || nvl(to_char(rec.return_year), '<NULL>') || '#' || '<NULL>' || '#' || '<NULL>' || '#' || '<NULL>' || '#' ||
                       nvl(to_char(el.camp_code), '<NULL>') || '#' || nvl(to_char('Total'), '<NULL>'), 'MD5') AS row_hash,
         SYSDATE AS activity_date
    FROM rbase rb
    JOIN elog_yoy el
      ON el.pidm = rb.pidm
   WHERE rb.returned = 1 HAVING COUNT(el.pidm) > 0
   GROUP BY el.camp_code),
---------------------------------------------------------------------
-- CRC: College Retention - Continuing (counts by college)
---------------------------------------------------------------------
crc_rows AS
 (SELECT 'CRC' AS report_code,
         rec.report_date AS report_date,
         rec.return_year AS acad_year,
         NULL AS term_code,
         NULL AS ptrm_code,
         el.coll_code AS coll_code,
         el.camp_code AS camp_code,
         el.coll_code AS metric_name,
         COUNT(el.pidm) AS metric_value,
         standard_hash(nvl(to_char('CRC'), '<NULL>') || '#' || nvl(to_char(rec.report_date, 'YYYYMMDD'), '<NULL>') || '#' || nvl(to_char(rec.return_year), '<NULL>') || '#' || '<NULL>' || '#' || '<NULL>' || '#' ||
                       nvl(to_char(el.coll_code), '<NULL>') || '#' || nvl(to_char(el.camp_code), '<NULL>') || '#' || nvl(to_char(el.coll_code), '<NULL>'), 'MD5') AS row_hash,
         SYSDATE AS activity_date
    FROM rbase rb
    JOIN elog_yoy el
      ON el.pidm = rb.pidm
   WHERE rb.returned = 1 HAVING COUNT(el.pidm) > 0
   GROUP BY el.camp_code,
            el.coll_code),
---------------------------------------------------------------------
-- LRC: Level Retention - Continuing (counts by level)
---------------------------------------------------------------------
lrc_rows AS
 (SELECT 'LRC' AS report_code,
         rec.report_date AS report_date,
         rec.return_year AS acad_year,
         NULL AS term_code,
         NULL AS ptrm_code,
         NULL AS coll_code,
         el.camp_code AS camp_code,
         el.levl_code AS metric_name,
         COUNT(el.pidm) AS metric_value,
         standard_hash(nvl(to_char('LRC'), '<NULL>') || '#' || nvl(to_char(rec.report_date, 'YYYYMMDD'), '<NULL>') || '#' || nvl(to_char(rec.return_year), '<NULL>') || '#' || '<NULL>' || '#' || '<NULL>' || '#' || '<NULL>' || '#' ||
                       nvl(to_char(el.camp_code), '<NULL>') || '#' || nvl(to_char(el.levl_code), '<NULL>'), 'MD5') AS row_hash,
         SYSDATE AS activity_date
    FROM rbase rb
    JOIN elog_yoy el
      ON el.pidm = rb.pidm
   WHERE rb.returned = 1 HAVING COUNT(el.pidm) > 0
   GROUP BY el.camp_code,
            el.levl_code),
---------------------------------------------------------------------
-- PRC: Program Retention - Continuing (counts by program)
---------------------------------------------------------------------
prc_rows AS
 (SELECT 'PRC' AS report_code,
         rec.report_date AS report_date,
         rec.return_year AS acad_year,
         NULL AS term_code,
         NULL AS ptrm_code,
         el.coll_code AS coll_code,
         el.camp_code AS camp_code,
         el.majr_code || '-' || el.degc_code || '-' || el.camp_code AS metric_name,
         COUNT(el.pidm) AS metric_value,
         standard_hash(nvl(to_char('PRC'), '<NULL>') || '#' || nvl(to_char(rec.report_date, 'YYYYMMDD'), '<NULL>') || '#' || nvl(to_char(rec.return_year), '<NULL>') || '#' || '<NULL>' || '#' || '<NULL>' || '#' ||
                       nvl(to_char(el.coll_code), '<NULL>') || '#' || nvl(to_char(el.camp_code), '<NULL>') || '#' || nvl(to_char(el.majr_code || '-' || el.degc_code || '-' || el.camp_code), '<NULL>'), 'MD5') AS row_hash,
         SYSDATE AS activity_date
    FROM rbase rb
    JOIN elog_yoy el
      ON el.pidm = rb.pidm
   WHERE rb.returned = 1 HAVING COUNT(el.pidm) > 0
   GROUP BY el.camp_code,
            el.coll_code,
            (el.majr_code || '-' || el.degc_code || '-' || el.camp_code))
SELECT src.report_code,
       src.report_date,
       src.acad_year,
       src.term_code,
       src.ptrm_code,
       src.coll_code,
       src.camp_code,
       src.metric_name,
       src.metric_value,
       src.row_hash,
       src.activity_date
  FROM (SELECT * FROM trs_rows UNION ALL SELECT * FROM trc_rows UNION ALL SELECT * FROM crc_rows UNION ALL SELECT * FROM lrc_rows UNION ALL SELECT * FROM prc_rows) src
  LEFT JOIN utl_d_aa.pacing_log tgt
    ON tgt.row_hash = src.row_hash
 WHERE tgt.report_date IS NULL;
-- Capture total rows inserted across all 9 report codes this iteration.
-- Single COMMIT per loop iteration: all 9 report codes land atomically,
-- so a failure on any acad_year + report_timestamp combination rolls back
-- cleanly without partial metric sets entering pacing_log.
v_count       := SQL%ROWCOUNT;
v_total_count := v_total_count + v_count; -- keep running total of rows processed
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'INSERT - ALL RETENTION CODES - ' || rec.return_year || ' - ' || rec.report_timestamp || ' - ' || to_char(v_partition) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY HH24:MI:SS') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
END LOOP; -- c_terms
-- Final summary log
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY HH24:MI:SS') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
EXCEPTION
WHEN OTHERS THEN
-- Attempt to rollback any uncommitted work for safety; earlier commits remain as intended.
BEGIN
ROLLBACK;
EXCEPTION
WHEN OTHERS THEN
NULL;
END;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA-', 'ORA-'), 1, 200);
dbms_output.put_line('FATAL ERROR: ' || v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
RAISE;
END etl_aa_pacing_retention;

procedure etl_aa_pacing_student_fci (jobnumber number, processid varchar2, processname varchar2) is 
-- DECLARE
v_etl_date     DATE := SYSDATE;
v_msg          VARCHAR2(2000);
v_instance     VARCHAR2(50) := upper('ALL');
v_partition    NUMBER := 0;
v_count        NUMBER := 0;
v_delete_count NUMBER := 0;
v_insert_count NUMBER := 0;
v_elapsed      NUMBER := 0;
v_total_count  NUMBER := 0;
v_job_id       VARCHAR2(32);
v_proc         VARCHAR2(100) := 'etl_aa_pacing_student_fci';
CURSOR c_terms IS
SELECT dates.acad_year,
       dates.report_date,
       dates.report_timestamp,
       dates.timeframe_start_date,
       dates.timeframe_end_date
  FROM utl_d_aa.acad_year_dates dates
 WHERE dates.report_timestamp >= SYSDATE - 3 -- run overlap just in case of weekends/fails, but only n-1 is needed normally
   AND dates.group_code = 'STD' --only need standard group_code
 ORDER BY dates.acad_year        ASC,
          dates.report_timestamp ASC;
BEGIN
-- dbms_output.enable(buffer_size => NULL);
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
FOR rec IN c_terms
LOOP
v_count   := 0;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || rec.acad_year || ' - ' || rec.report_timestamp || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- Insert all 8 FCI report codes in one pass using a materialized CTE of deduplicated students with FCI completed.
INSERT INTO utl_d_aa.pacing_log
(report_code,
 report_date,
 acad_year,
 term_code,
 ptrm_code,
 coll_code,
 camp_code,
 metric_name,
 metric_value,
 row_hash,
 activity_date)
WITH elog AS
 (
  -- Deduplicated, canonical student rows by acad_year with FCI completed (elog.fci_date IS NOT NULL).
  SELECT /*+ MATERIALIZE */
   el.pidm,
    el.term_code,
    el.start_date,
    el.end_date,
    el.group_code,
    el.semester,
    el.camp_code,
    el.levl_code,
    el.coll_code,
    el.degc_code,
    el.majr_code,
    el.acat_code
    FROM (SELECT elog.pidm,
                  elog.term_code,
                  elog.start_date,
                  elog.end_date,
                  elog.from_date,
                  elog.to_date,
                  elog.group_code,
                  elog.semester,
                  elog.acad_year,
                  elog.camp_code,
                  elog.levl_code,
                  elog.coll_code,
                  elog.degc_code,
                  elog.majr_code,
                  elog.acat_code,
                  -- Ranking favors rows active on report_timestamp; tiebreak by latest from_date then earliest to_date.
                  row_number() over(PARTITION BY elog.pidm, elog.acad_year ORDER BY greatest(sign(rec.report_timestamp - elog.start_date), 0) * greatest(sign(elog.end_date - rec.report_timestamp), 0) DESC, elog.from_date DESC, elog.to_date ASC) AS ranking
             FROM utl_d_aa.enrollments_log elog
            WHERE elog.acad_year = rec.acad_year
              AND rec.report_timestamp BETWEEN elog.from_date AND elog.to_date
              AND elog.semester <> 'WIN'
              AND elog.fci_date IS NOT NULL) el
   WHERE el.ranking = 1),
-- Term-based Total>Student>FCI by campus and term
tsft_rows AS
 (SELECT 'TSFT' AS report_code,
         rec.report_date AS report_date,
         rec.acad_year AS acad_year,
         el.term_code AS term_code,
         NULL AS ptrm_code,
         NULL AS coll_code,
         el.camp_code AS camp_code,
         'Total' AS metric_name,
         COUNT(el.pidm) AS metric_value,
         standard_hash(nvl(to_char('TSFT'), '<NULL>') || '#' || nvl(to_char(rec.report_date, 'YYYYMMDD'), '<NULL>') || '#' || nvl(to_char(rec.acad_year), '<NULL>') || '#' || nvl(to_char(el.term_code), '<NULL>') || '#' || '<NULL>' || '#' ||
                       '<NULL>' || '#' || nvl(to_char(el.camp_code), '<NULL>') || '#' || nvl(to_char('Total'), '<NULL>'), 'MD5') AS row_hash,
         SYSDATE AS activity_date
    FROM elog el
   WHERE rec.report_timestamp < el.end_date -- stop when semester is over
   HAVING COUNT(el.pidm) > 0
   GROUP BY el.camp_code,
            el.term_code),
-- Total>Student>FCI by campus (no term)
tsf_rows AS
 (SELECT 'TSF' AS report_code,
         rec.report_date AS report_date,
         rec.acad_year AS acad_year,
         NULL AS term_code,
         NULL AS ptrm_code,
         NULL AS coll_code,
         el.camp_code AS camp_code,
         'Total' AS metric_name,
         COUNT(el.pidm) AS metric_value,
         standard_hash(nvl(to_char('TSF'), '<NULL>') || '#' || nvl(to_char(rec.report_date, 'YYYYMMDD'), '<NULL>') || '#' || nvl(to_char(rec.acad_year), '<NULL>') || '#' || '<NULL>' || '#' || '<NULL>' || '#' || '<NULL>' || '#' ||
                       nvl(to_char(el.camp_code), '<NULL>') || '#' || nvl(to_char('Total'), '<NULL>'), 'MD5') AS row_hash,
         SYSDATE AS activity_date
    FROM elog el
   WHERE 1 = 1 HAVING COUNT(el.pidm) > 0
   GROUP BY el.camp_code),
-- College>Student>FCI>Term by campus, term, college (metric_name=coll_code)
csft_rows AS
 (SELECT 'CSFT' AS report_code,
         rec.report_date AS report_date,
         rec.acad_year AS acad_year,
         el.term_code AS term_code,
         NULL AS ptrm_code,
         NULL AS coll_code,
         el.camp_code AS camp_code,
         el.coll_code AS metric_name,
         COUNT(el.pidm) AS metric_value,
         standard_hash(nvl(to_char('CSFT'), '<NULL>') || '#' || nvl(to_char(rec.report_date, 'YYYYMMDD'), '<NULL>') || '#' || nvl(to_char(rec.acad_year), '<NULL>') || '#' || nvl(to_char(el.term_code), '<NULL>') || '#' || '<NULL>' || '#' ||
                       '<NULL>' || '#' || nvl(to_char(el.camp_code), '<NULL>') || '#' || nvl(to_char(el.coll_code), '<NULL>'), 'MD5') AS row_hash,
         SYSDATE AS activity_date
    FROM elog el
   WHERE rec.report_timestamp < el.end_date -- stop when semester is over
   HAVING COUNT(el.pidm) > 0
   GROUP BY el.camp_code,
            el.term_code,
            el.coll_code),
-- College>Student>FCI by campus, college (metric_name=coll_code)
csf_rows AS
 (SELECT 'CSF' AS report_code,
         rec.report_date AS report_date,
         rec.acad_year AS acad_year,
         NULL AS term_code,
         NULL AS ptrm_code,
         NULL AS coll_code,
         el.camp_code AS camp_code,
         el.coll_code AS metric_name,
         COUNT(el.pidm) AS metric_value,
         standard_hash(nvl(to_char('CSF'), '<NULL>') || '#' || nvl(to_char(rec.report_date, 'YYYYMMDD'), '<NULL>') || '#' || nvl(to_char(rec.acad_year), '<NULL>') || '#' || '<NULL>' || '#' || '<NULL>' || '#' || '<NULL>' || '#' ||
                       nvl(to_char(el.camp_code), '<NULL>') || '#' || nvl(to_char(el.coll_code), '<NULL>'), 'MD5') AS row_hash,
         SYSDATE AS activity_date
    FROM elog el
   WHERE 1 = 1 HAVING COUNT(el.pidm) > 0
   GROUP BY el.camp_code,
            el.coll_code),
-- Level>Student>FCI>Term by campus, term, level (metric_name=levl_code)
lsft_rows AS
 (SELECT 'LSFT' AS report_code,
         rec.report_date AS report_date,
         rec.acad_year AS acad_year,
         el.term_code AS term_code,
         NULL AS ptrm_code,
         NULL AS coll_code,
         el.camp_code AS camp_code,
         el.levl_code AS metric_name,
         COUNT(el.pidm) AS metric_value,
         standard_hash(nvl(to_char('LSFT'), '<NULL>') || '#' || nvl(to_char(rec.report_date, 'YYYYMMDD'), '<NULL>') || '#' || nvl(to_char(rec.acad_year), '<NULL>') || '#' || nvl(to_char(el.term_code), '<NULL>') || '#' || '<NULL>' || '#' ||
                       '<NULL>' || '#' || nvl(to_char(el.camp_code), '<NULL>') || '#' || nvl(to_char(el.levl_code), '<NULL>'), 'MD5') AS row_hash,
         SYSDATE AS activity_date
    FROM elog el
   WHERE rec.report_timestamp < el.end_date -- stop when semester is over
   HAVING COUNT(el.pidm) > 0
   GROUP BY el.camp_code,
            el.term_code,
            el.levl_code),
-- Level>Student>FCI by campus, level (metric_name=levl_code)
lsf_rows AS
 (SELECT 'LSF' AS report_code,
         rec.report_date AS report_date,
         rec.acad_year AS acad_year,
         NULL AS term_code,
         NULL AS ptrm_code,
         NULL AS coll_code,
         el.camp_code AS camp_code,
         el.levl_code AS metric_name,
         COUNT(el.pidm) AS metric_value,
         standard_hash(nvl(to_char('LSF'), '<NULL>') || '#' || nvl(to_char(rec.report_date, 'YYYYMMDD'), '<NULL>') || '#' || nvl(to_char(rec.acad_year), '<NULL>') || '#' || '<NULL>' || '#' || '<NULL>' || '#' || '<NULL>' || '#' ||
                       nvl(to_char(el.camp_code), '<NULL>') || '#' || nvl(to_char(el.levl_code), '<NULL>'), 'MD5') AS row_hash,
         SYSDATE AS activity_date
    FROM elog el
   WHERE 1 = 1 HAVING COUNT(el.pidm) > 0
   GROUP BY el.camp_code,
            el.levl_code),
-- Program>Student>FCI>Term by campus, term, college (metric_name=majr-degc-camp)
psft_rows AS
 (SELECT 'PSFT' AS report_code,
         rec.report_date AS report_date,
         rec.acad_year AS acad_year,
         el.term_code AS term_code,
         NULL AS ptrm_code,
         el.coll_code AS coll_code,
         el.camp_code AS camp_code,
         el.majr_code || '-' || el.degc_code || '-' || el.camp_code AS metric_name,
         COUNT(el.pidm) AS metric_value,
         standard_hash(nvl(to_char('PSFT'), '<NULL>') || '#' || nvl(to_char(rec.report_date, 'YYYYMMDD'), '<NULL>') || '#' || nvl(to_char(rec.acad_year), '<NULL>') || '#' || nvl(to_char(el.term_code), '<NULL>') || '#' || '<NULL>' || '#' ||
                       nvl(to_char(el.coll_code), '<NULL>') || '#' || nvl(to_char(el.camp_code), '<NULL>') || '#' || nvl(to_char(el.majr_code || '-' || el.degc_code || '-' || el.camp_code), '<NULL>'), 'MD5') AS row_hash,
         SYSDATE AS activity_date
    FROM elog el
   WHERE rec.report_timestamp < el.end_date -- stop when semester is over
   HAVING COUNT(el.pidm) > 0
   GROUP BY el.camp_code,
            el.term_code,
            el.coll_code,
            el.majr_code || '-' || el.degc_code || '-' || el.camp_code),
-- Program>Student>FCI by campus, college (metric_name=majr-degc-camp)
psf_rows AS
 (SELECT 'PSF' AS report_code,
         rec.report_date AS report_date,
         rec.acad_year AS acad_year,
         NULL AS term_code,
         NULL AS ptrm_code,
         el.coll_code AS coll_code,
         el.camp_code AS camp_code,
         el.majr_code || '-' || el.degc_code || '-' || el.camp_code AS metric_name,
         COUNT(el.pidm) AS metric_value,
         standard_hash(nvl(to_char('PSF'), '<NULL>') || '#' || nvl(to_char(rec.report_date, 'YYYYMMDD'), '<NULL>') || '#' || nvl(to_char(rec.acad_year), '<NULL>') || '#' || '<NULL>' || '#' || '<NULL>' || '#' ||
                       nvl(to_char(el.coll_code), '<NULL>') || '#' || nvl(to_char(el.camp_code), '<NULL>') || '#' || nvl(to_char(el.majr_code || '-' || el.degc_code || '-' || el.camp_code), '<NULL>'), 'MD5') AS row_hash,
         SYSDATE AS activity_date
    FROM elog el
   WHERE 1 = 1 HAVING COUNT(el.pidm) > 0
   GROUP BY el.camp_code,
            el.coll_code,
            el.majr_code || '-' || el.degc_code || '-' || el.camp_code)
SELECT src.report_code,
       src.report_date,
       src.acad_year,
       src.term_code,
       src.ptrm_code,
       src.coll_code,
       src.camp_code,
       src.metric_name,
       src.metric_value,
       src.row_hash,
       src.activity_date
  FROM (SELECT *
          FROM tsft_rows
        UNION ALL
        SELECT *
          FROM tsf_rows
        UNION ALL
        SELECT *
          FROM csft_rows
        UNION ALL
        SELECT *
          FROM csf_rows
        UNION ALL
        SELECT *
          FROM lsft_rows
        UNION ALL
        SELECT *
          FROM lsf_rows
        UNION ALL
        SELECT *
          FROM psft_rows
        UNION ALL
        SELECT *
          FROM psf_rows) src
  LEFT JOIN utl_d_aa.pacing_log tgt
    ON tgt.row_hash = src.row_hash
 WHERE tgt.report_date IS NULL;
v_count       := SQL%ROWCOUNT;
v_total_count := v_total_count + v_count;
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'INSERT - ALL FCI CODES - ' || rec.acad_year || ' - ' || rec.report_timestamp || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
END LOOP;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
EXCEPTION
WHEN OTHERS THEN
ROLLBACK;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
RAISE;
END etl_aa_pacing_student_fci;

procedure etl_aa_pacing_student_hours (jobnumber number, processid varchar2, processname varchar2) is 
-- DECLARE
v_etl_date     DATE := SYSDATE;
v_msg          VARCHAR2(2000);
v_instance     VARCHAR2(50) := upper('ALL'); -- inst from the jams job; used for determining instance
v_partition    NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_count        NUMBER := 0;
v_delete_count NUMBER := 0;
v_insert_count NUMBER := 0;
v_elapsed      NUMBER := 0;
v_total_count  NUMBER := 0;
v_job_id       VARCHAR2(32);
v_proc         VARCHAR2(100) := 'etl_aa_pacing_student_hours';
CURSOR c_terms IS
SELECT dates.acad_year,
       dates.report_date,
       dates.report_timestamp,
       dates.timeframe_start_date,
       dates.timeframe_end_date
  FROM utl_d_aa.acad_year_dates dates
 WHERE dates.report_timestamp >= SYSDATE - 3 -- run overlap just in case of weekends/fails, but only n-1 is needed normally
   AND dates.group_code = 'STD' --only need standard group_code
 ORDER BY dates.acad_year        ASC,
          dates.report_timestamp ASC;
BEGIN
-- dbms_output.enable(buffer_size => NULL);
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
FOR rec IN c_terms
LOOP
v_count   := 0;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || rec.acad_year || ' - ' || rec.report_timestamp || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- Insert all report codes in one pass using a materialized CTE of deduplicated students
INSERT INTO utl_d_aa.pacing_log
(report_code,
 report_date,
 acad_year,
 term_code,
 ptrm_code,
 coll_code,
 camp_code,
 metric_name,
 metric_value,
 row_hash,
 activity_date)
WITH elog AS
 (SELECT /*+ MATERIALIZE */
   el.pidm,
   el.term_code,
   el.start_date,
   el.end_date,
   el.group_code,
   el.semester,
   el.camp_code,
   el.levl_code,
   el.coll_code,
   el.degc_code,
   el.majr_code,
   el.acat_code,
   el.term_hours, -- used by all "T" suffix (term-level) report codes
   el.acad_res_hours, -- resident hours for year-level splits
   el.acad_luo_hours -- LUO hours for year-level splits
    FROM (SELECT elog.pidm,
                 elog.term_code,
                 elog.start_date,
                 elog.end_date,
                 elog.from_date,
                 elog.to_date,
                 elog.group_code,
                 elog.semester,
                 elog.acad_year,
                 elog.camp_code,
                 elog.levl_code,
                 elog.coll_code,
                 elog.degc_code,
                 elog.majr_code,
                 elog.acat_code,
                 elog.term_hours,
                 elog.acad_res_hours,
                 elog.acad_luo_hours,
                 -- Ranking expression: prefer rows that are "active" on rec.report_timestamp
                 -- (start_date <= rec.report_timestamp <= end_date), then latest from_date, earliest to_date.
                 row_number() over(PARTITION BY elog.pidm, elog.acad_year ORDER BY greatest(sign(rec.report_timestamp - elog.start_date), 0) * greatest(sign(elog.end_date - rec.report_timestamp), 0) DESC, elog.from_date DESC, elog.to_date ASC) AS ranking
            FROM utl_d_aa.enrollments_log elog
           WHERE elog.acad_year = rec.acad_year
             AND rec.report_timestamp BETWEEN elog.from_date AND elog.to_date -- active snapshot window
             AND elog.semester <> 'WIN' -- excluding winter terms
          ) el
   WHERE el.ranking = 1 -- one canonical row per student per academic year
  ),
-- -------------------------------------------------------------------------
-- TSHT: Total hours by term + camp (term_hours; with term boundary enforcement)
-- -------------------------------------------------------------------------
tsht_rows AS
 (SELECT 'TSHT' AS report_code,
         rec.report_date AS report_date, -- unique date truncated
         rec.acad_year AS acad_year,
         el.term_code AS term_code,
         NULL AS ptrm_code,
         NULL AS coll_code,
         el.camp_code AS camp_code,
         'Total' AS metric_name, -- **codes** for what will be displayed for each node; will need to connect to stv's later
         round(SUM(el.term_hours)) AS metric_value,
         standard_hash(nvl(to_char('TSHT'), '<NULL>') || '#' || nvl(to_char(rec.report_date, 'YYYYMMDD'), '<NULL>') || '#' || nvl(to_char(rec.acad_year), '<NULL>') || '#' || nvl(to_char(el.term_code), '<NULL>') || '#' || '<NULL>' || '#' ||
                       '<NULL>' || '#' || nvl(to_char(el.camp_code), '<NULL>') || '#' || nvl(to_char('Total'), '<NULL>'), 'MD5') AS row_hash,
         SYSDATE AS activity_date
    FROM elog el
   WHERE rec.report_timestamp < el.end_date -- stop when semester is over
   HAVING round(SUM(el.term_hours)) > 0
   GROUP BY el.camp_code,
            el.term_code),
-- -------------------------------------------------------------------------
-- TSH (resident): Total hours by camp only, no term breakdown (acad_res_hours; year-level rollup)
-- HARD CODE camp_code = 'R'; metric_name stays 'Total'; NO GROUP BY camp from source
-- -------------------------------------------------------------------------
tsh_rows_res AS
 (SELECT 'TSH' AS report_code,
         rec.report_date AS report_date, -- unique date truncated
         rec.acad_year AS acad_year,
         NULL AS term_code,
         NULL AS ptrm_code,
         NULL AS coll_code,
         'R' AS camp_code, -- HARD CODE 'R'
         'Total' AS metric_name,
         round(SUM(el.acad_res_hours)) AS metric_value,
         standard_hash(nvl(to_char('TSH'), '<NULL>') || '#' || nvl(to_char(rec.report_date, 'YYYYMMDD'), '<NULL>') || '#' || nvl(to_char(rec.acad_year), '<NULL>') || '#' || '<NULL>' || '#' || '<NULL>' || '#' || '<NULL>' || '#' ||
                       nvl(to_char('R'), '<NULL>') || '#' || nvl(to_char('Total'), '<NULL>'), 'MD5') AS row_hash,
         SYSDATE AS activity_date
    FROM elog el
   WHERE 1 = 1 HAVING round(SUM(el.acad_res_hours)) > 0),
-- -------------------------------------------------------------------------
-- TSH (LUO): Total hours by camp only, no term breakdown (acad_luo_hours; year-level rollup)
-- HARD CODE camp_code = 'D'; metric_name stays 'Total'; NO GROUP BY camp from source
-- -------------------------------------------------------------------------
tsh_rows_luo AS
 (SELECT 'TSH' AS report_code,
         rec.report_date AS report_date,
         rec.acad_year AS acad_year,
         NULL AS term_code,
         NULL AS ptrm_code,
         NULL AS coll_code,
         'D' AS camp_code, -- HARD CODE 'D'
         'Total' AS metric_name,
         round(SUM(el.acad_luo_hours)) AS metric_value,
         standard_hash(nvl(to_char('TSH'), '<NULL>') || '#' || nvl(to_char(rec.report_date, 'YYYYMMDD'), '<NULL>') || '#' || nvl(to_char(rec.acad_year), '<NULL>') || '#' || '<NULL>' || '#' || '<NULL>' || '#' || '<NULL>' || '#' ||
                       nvl(to_char('D'), '<NULL>') || '#' || nvl(to_char('Total'), '<NULL>'), 'MD5') AS row_hash,
         SYSDATE AS activity_date
    FROM elog el
   WHERE 1 = 1 HAVING round(SUM(el.acad_luo_hours)) > 0),
-- -------------------------------------------------------------------------
-- CSHT: College hours by term + camp (term_hours; with term boundary enforcement)
-- NULL; **only used if the measure grain is lower than college**
-- -------------------------------------------------------------------------
csht_rows AS
 (SELECT 'CSHT' AS report_code,
         rec.report_date AS report_date, -- unique date truncated
         rec.acad_year AS acad_year,
         el.term_code AS term_code,
         NULL AS ptrm_code,
         NULL AS coll_code, -- NULL; **only used if the measure grain is lower than college**
         el.camp_code AS camp_code,
         el.coll_code AS metric_name, -- **codes** for what will be displayed for each node; will need to connect to stv's later
         round(SUM(el.term_hours)) AS metric_value,
         standard_hash(nvl(to_char('CSHT'), '<NULL>') || '#' || nvl(to_char(rec.report_date, 'YYYYMMDD'), '<NULL>') || '#' || nvl(to_char(rec.acad_year), '<NULL>') || '#' || nvl(to_char(el.term_code), '<NULL>') || '#' || '<NULL>' || '#' ||
                       '<NULL>' || '#' || nvl(to_char(el.camp_code), '<NULL>') || '#' || nvl(to_char(el.coll_code), '<NULL>'), 'MD5') AS row_hash,
         SYSDATE AS activity_date
    FROM elog el
   WHERE rec.report_timestamp < el.end_date -- stop when semester is over
   HAVING round(SUM(el.term_hours)) > 0
   GROUP BY el.camp_code,
            el.term_code,
            el.coll_code),
-- -------------------------------------------------------------------------
-- CSH (resident): College hours by camp only, no term breakdown (acad_res_hours; year-level rollup)
-- HARD CODE camp_code = 'R'; metric_name = coll_code; NO GROUP BY camp from source
-- NULL; **only used if the measure grain is lower than college**
-- -------------------------------------------------------------------------
csh_rows_res AS
 (SELECT 'CSH' AS report_code,
         rec.report_date AS report_date, -- unique date truncated
         rec.acad_year AS acad_year,
         NULL AS term_code,
         NULL AS ptrm_code,
         NULL AS coll_code, -- NULL; **only used if the measure grain is lower than college**
         'R' AS camp_code,
         el.coll_code AS metric_name,
         round(SUM(el.acad_res_hours)) AS metric_value,
         standard_hash(nvl(to_char('CSH'), '<NULL>') || '#' || nvl(to_char(rec.report_date, 'YYYYMMDD'), '<NULL>') || '#' || nvl(to_char(rec.acad_year), '<NULL>') || '#' || '<NULL>' || '#' || '<NULL>' || '#' || '<NULL>' || '#' ||
                       nvl(to_char('R'), '<NULL>') || '#' || nvl(to_char(el.coll_code), '<NULL>'), 'MD5') AS row_hash,
         SYSDATE AS activity_date
    FROM elog el
   WHERE 1 = 1 HAVING round(SUM(el.acad_res_hours)) > 0
   GROUP BY el.coll_code),
-- -------------------------------------------------------------------------
-- CSH (LUO): College hours by camp only, no term breakdown (acad_luo_hours; year-level rollup)
-- HARD CODE camp_code = 'D'; metric_name = coll_code; NO GROUP BY camp from source
-- -------------------------------------------------------------------------
csh_rows_luo AS
 (SELECT 'CSH' AS report_code,
         rec.report_date AS report_date,
         rec.acad_year AS acad_year,
         NULL AS term_code,
         NULL AS ptrm_code,
         NULL AS coll_code,
         'D' AS camp_code,
         el.coll_code AS metric_name,
         round(SUM(el.acad_luo_hours)) AS metric_value,
         standard_hash(nvl(to_char('CSH'), '<NULL>') || '#' || nvl(to_char(rec.report_date, 'YYYYMMDD'), '<NULL>') || '#' || nvl(to_char(rec.acad_year), '<NULL>') || '#' || '<NULL>' || '#' || '<NULL>' || '#' || '<NULL>' || '#' ||
                       nvl(to_char('D'), '<NULL>') || '#' || nvl(to_char(el.coll_code), '<NULL>'), 'MD5') AS row_hash,
         SYSDATE AS activity_date
    FROM elog el
   WHERE 1 = 1 HAVING round(SUM(el.acad_luo_hours)) > 0
   GROUP BY el.coll_code),
-- -------------------------------------------------------------------------
-- LSHT: Level hours by term + camp (term_hours; with term boundary enforcement)
-- -------------------------------------------------------------------------
lsht_rows AS
 (SELECT 'LSHT' AS report_code,
         rec.report_date AS report_date, -- unique date truncated
         rec.acad_year AS acad_year,
         el.term_code AS term_code,
         NULL AS ptrm_code,
         NULL AS coll_code,
         el.camp_code AS camp_code,
         el.levl_code AS metric_name, -- **codes** for what will be displayed for each node; will need to connect to stv's later
         round(SUM(el.term_hours)) AS metric_value,
         standard_hash(nvl(to_char('LSHT'), '<NULL>') || '#' || nvl(to_char(rec.report_date, 'YYYYMMDD'), '<NULL>') || '#' || nvl(to_char(rec.acad_year), '<NULL>') || '#' || nvl(to_char(el.term_code), '<NULL>') || '#' || '<NULL>' || '#' ||
                       '<NULL>' || '#' || nvl(to_char(el.camp_code), '<NULL>') || '#' || nvl(to_char(el.levl_code), '<NULL>'), 'MD5') AS row_hash,
         SYSDATE AS activity_date
    FROM elog el
   WHERE rec.report_timestamp < el.end_date -- stop when semester is over
   HAVING round(SUM(el.term_hours)) > 0
   GROUP BY el.camp_code,
            el.term_code,
            el.levl_code),
-- -------------------------------------------------------------------------
-- LSH (resident): Level hours by camp only, no term breakdown (acad_res_hours; year-level rollup)
-- HARD CODE camp_code = 'R'; metric_name = levl_code; NO GROUP BY camp from source
-- -------------------------------------------------------------------------
lsh_rows_res AS
 (SELECT 'LSH' AS report_code,
         rec.report_date AS report_date, -- unique date truncated
         rec.acad_year AS acad_year,
         NULL AS term_code,
         NULL AS ptrm_code,
         NULL AS coll_code,
         'R' AS camp_code,
         el.levl_code AS metric_name, -- **codes** for what will be displayed for each node; will need to connect to stv's later
         round(SUM(el.acad_res_hours)) AS metric_value,
         standard_hash(nvl(to_char('LSH'), '<NULL>') || '#' || nvl(to_char(rec.report_date, 'YYYYMMDD'), '<NULL>') || '#' || nvl(to_char(rec.acad_year), '<NULL>') || '#' || '<NULL>' || '#' || '<NULL>' || '#' || '<NULL>' || '#' ||
                       nvl(to_char('R'), '<NULL>') || '#' || nvl(to_char(el.levl_code), '<NULL>'), 'MD5') AS row_hash,
         SYSDATE AS activity_date
    FROM elog el
   WHERE 1 = 1 HAVING round(SUM(el.acad_res_hours)) > 0
   GROUP BY el.levl_code),
-- -------------------------------------------------------------------------
-- LSH (LUO): Level hours by camp only, no term breakdown (acad_luo_hours; year-level rollup)
-- HARD CODE camp_code = 'D'; metric_name = levl_code; NO GROUP BY camp from source
-- -------------------------------------------------------------------------
lsh_rows_luo AS
 (SELECT 'LSH' AS report_code,
         rec.report_date AS report_date,
         rec.acad_year AS acad_year,
         NULL AS term_code,
         NULL AS ptrm_code,
         NULL AS coll_code,
         'D' AS camp_code,
         el.levl_code AS metric_name,
         round(SUM(el.acad_luo_hours)) AS metric_value,
         standard_hash(nvl(to_char('LSH'), '<NULL>') || '#' || nvl(to_char(rec.report_date, 'YYYYMMDD'), '<NULL>') || '#' || nvl(to_char(rec.acad_year), '<NULL>') || '#' || '<NULL>' || '#' || '<NULL>' || '#' || '<NULL>' || '#' ||
                       nvl(to_char('D'), '<NULL>') || '#' || nvl(to_char(el.levl_code), '<NULL>'), 'MD5') AS row_hash,
         SYSDATE AS activity_date
    FROM elog el
   WHERE 1 = 1 HAVING round(SUM(el.acad_luo_hours)) > 0
   GROUP BY el.levl_code),
-- -------------------------------------------------------------------------
-- PSHT: Program hours by term + camp + college (term_hours; with term boundary enforcement)
-- metric_name is a composite key: majr_code-degc_code-camp_code
-- -------------------------------------------------------------------------
psht_rows AS
 (SELECT 'PSHT' AS report_code,
         rec.report_date AS report_date, -- unique date truncated
         rec.acad_year AS acad_year,
         el.term_code AS term_code,
         NULL AS ptrm_code,
         el.coll_code AS coll_code,
         el.camp_code AS camp_code,
         el.majr_code || '-' || el.degc_code || '-' || el.camp_code AS metric_name, -- **codes** for what will be displayed for each node; will need to connect to stv's later
         round(SUM(el.term_hours)) AS metric_value,
         standard_hash(nvl(to_char('PSHT'), '<NULL>') || '#' || nvl(to_char(rec.report_date, 'YYYYMMDD'), '<NULL>') || '#' || nvl(to_char(rec.acad_year), '<NULL>') || '#' || nvl(to_char(el.term_code), '<NULL>') || '#' || '<NULL>' || '#' ||
                       nvl(to_char(el.coll_code), '<NULL>') || '#' || nvl(to_char(el.camp_code), '<NULL>') || '#' || nvl(to_char(el.majr_code || '-' || el.degc_code || '-' || el.camp_code), '<NULL>'), 'MD5') AS row_hash,
         SYSDATE AS activity_date
    FROM elog el
   WHERE rec.report_timestamp < el.end_date -- stop when semester is over
   HAVING round(SUM(el.term_hours)) > 0
   GROUP BY el.camp_code,
            el.term_code,
            el.coll_code,
            el.majr_code || '-' || el.degc_code || '-' || el.camp_code),
-- -------------------------------------------------------------------------
-- PSH (resident): Program hours by camp + college only, no term breakdown (acad_res_hours; year-level rollup)
-- HARD CODE camp_code = 'R'; metric_name is a composite key: majr_code-degc_code-R; NO GROUP BY camp from source
-- -------------------------------------------------------------------------
psh_rows_res AS
 (SELECT 'PSH' AS report_code,
         rec.report_date AS report_date, -- unique date truncated
         rec.acad_year AS acad_year,
         NULL AS term_code,
         NULL AS ptrm_code,
         el.coll_code AS coll_code,
         'R' AS camp_code,
         el.majr_code || '-' || el.degc_code || '-' || 'R' AS metric_name, -- **codes** for what will be displayed for each node; will need to connect to stv's later
         round(SUM(el.acad_res_hours)) AS metric_value,
         standard_hash(nvl(to_char('PSH'), '<NULL>') || '#' || nvl(to_char(rec.report_date, 'YYYYMMDD'), '<NULL>') || '#' || nvl(to_char(rec.acad_year), '<NULL>') || '#' || '<NULL>' || '#' || '<NULL>' || '#' ||
                       nvl(to_char(el.coll_code), '<NULL>') || '#' || nvl(to_char('R'), '<NULL>') || '#' || nvl(to_char(el.majr_code || '-' || el.degc_code || '-' || 'R'), '<NULL>'), 'MD5') AS row_hash,
         SYSDATE AS activity_date
    FROM elog el
   WHERE 1 = 1 HAVING round(SUM(el.acad_res_hours)) > 0
   GROUP BY el.coll_code,
            el.majr_code,
            el.degc_code),
-- -------------------------------------------------------------------------
-- PSH (LUO): Program hours by camp + college only, no term breakdown (acad_luo_hours; year-level rollup)
-- HARD CODE camp_code = 'D'; metric_name is a composite key: majr_code-degc_code-D; NO GROUP BY camp from source
-- -------------------------------------------------------------------------
psh_rows_luo AS
 (SELECT 'PSH' AS report_code,
         rec.report_date AS report_date,
         rec.acad_year AS acad_year,
         NULL AS term_code,
         NULL AS ptrm_code,
         el.coll_code AS coll_code,
         'D' AS camp_code,
         el.majr_code || '-' || el.degc_code || '-' || 'D' AS metric_name,
         round(SUM(el.acad_luo_hours)) AS metric_value,
         standard_hash(nvl(to_char('PSH'), '<NULL>') || '#' || nvl(to_char(rec.report_date, 'YYYYMMDD'), '<NULL>') || '#' || nvl(to_char(rec.acad_year), '<NULL>') || '#' || '<NULL>' || '#' || '<NULL>' || '#' ||
                       nvl(to_char(el.coll_code), '<NULL>') || '#' || nvl(to_char('D'), '<NULL>') || '#' || nvl(to_char(el.majr_code || '-' || el.degc_code || '-' || 'D'), '<NULL>'), 'MD5') AS row_hash,
         SYSDATE AS activity_date
    FROM elog el
   WHERE 1 = 1 HAVING round(SUM(el.acad_luo_hours)) > 0
   GROUP BY el.coll_code,
            el.majr_code,
            el.degc_code),
-- -------------------------------------------------------------------------
-- Final union of all branches into a single source set.
-- -------------------------------------------------------------------------
src AS
 (SELECT report_code,
         report_date,
         acad_year,
         term_code,
         ptrm_code,
         coll_code,
         camp_code,
         metric_name,
         metric_value,
         row_hash,
         activity_date
    FROM tsht_rows
  UNION ALL
  SELECT report_code,
         report_date,
         acad_year,
         term_code,
         ptrm_code,
         coll_code,
         camp_code,
         metric_name,
         metric_value,
         row_hash,
         activity_date
    FROM tsh_rows_res
  UNION ALL
  SELECT report_code,
         report_date,
         acad_year,
         term_code,
         ptrm_code,
         coll_code,
         camp_code,
         metric_name,
         metric_value,
         row_hash,
         activity_date
    FROM tsh_rows_luo
  UNION ALL
  SELECT report_code,
         report_date,
         acad_year,
         term_code,
         ptrm_code,
         coll_code,
         camp_code,
         metric_name,
         metric_value,
         row_hash,
         activity_date
    FROM csht_rows
  UNION ALL
  SELECT report_code,
         report_date,
         acad_year,
         term_code,
         ptrm_code,
         coll_code,
         camp_code,
         metric_name,
         metric_value,
         row_hash,
         activity_date
    FROM csh_rows_res
  UNION ALL
  SELECT report_code,
         report_date,
         acad_year,
         term_code,
         ptrm_code,
         coll_code,
         camp_code,
         metric_name,
         metric_value,
         row_hash,
         activity_date
    FROM csh_rows_luo
  UNION ALL
  SELECT report_code,
         report_date,
         acad_year,
         term_code,
         ptrm_code,
         coll_code,
         camp_code,
         metric_name,
         metric_value,
         row_hash,
         activity_date
    FROM lsht_rows
  UNION ALL
  SELECT report_code,
         report_date,
         acad_year,
         term_code,
         ptrm_code,
         coll_code,
         camp_code,
         metric_name,
         metric_value,
         row_hash,
         activity_date
    FROM lsh_rows_res
  UNION ALL
  SELECT report_code,
         report_date,
         acad_year,
         term_code,
         ptrm_code,
         coll_code,
         camp_code,
         metric_name,
         metric_value,
         row_hash,
         activity_date
    FROM lsh_rows_luo
  UNION ALL
  SELECT report_code,
         report_date,
         acad_year,
         term_code,
         ptrm_code,
         coll_code,
         camp_code,
         metric_name,
         metric_value,
         row_hash,
         activity_date
    FROM psht_rows
  UNION ALL
  SELECT report_code,
         report_date,
         acad_year,
         term_code,
         ptrm_code,
         coll_code,
         camp_code,
         metric_name,
         metric_value,
         row_hash,
         activity_date
    FROM psh_rows_res
  UNION ALL
  SELECT report_code,
         report_date,
         acad_year,
         term_code,
         ptrm_code,
         coll_code,
         camp_code,
         metric_name,
         metric_value,
         row_hash,
         activity_date
    FROM psh_rows_luo)
SELECT sr.report_code,
       sr.report_date,
       sr.acad_year,
       sr.term_code,
       sr.ptrm_code,
       sr.coll_code,
       sr.camp_code,
       sr.metric_name,
       sr.metric_value,
       sr.row_hash,
       sr.activity_date
  FROM src sr
 WHERE NOT EXISTS (SELECT 1 FROM utl_d_aa.pacing_log t WHERE t.row_hash = sr.row_hash);
v_count       := SQL%ROWCOUNT;
v_total_count := v_total_count + v_count; -- keep running total of rows processed
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'INSERT - ALL HOURS CODES - ' || rec.acad_year || ' - ' || rec.report_timestamp || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
END LOOP;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
EXCEPTION
WHEN OTHERS THEN
ROLLBACK;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
RAISE;
END etl_aa_pacing_student_hours;

procedure etl_aa_pacing_student_seats (jobnumber number, processid varchar2, processname varchar2) is
-- =============================================================================
-- PURPOSE: Populate the institutional pacing_log with aggregated student seats metrics (multiple grains: term/college/program/level and year-level splits) for each academic-date snapshot, skipping rows that would violate NOT NULL constraints.
--
-- TARGET(S): utl_d_aa.pacing_log
--
-- UNIQUE KEY / INDEX: row_hash (used to deduplicate inserts; IGNORE_ROW_ON_DUPKEY_INDEX on utl_d_aa.pacing_log(row_hash))
--
-- BUSINESS LOGIC & CONDITIONS:
-- - Iteration strategy:
--   - Iterate over academic snapshot dates returned by utl_d_aa.acad_year_dates for acad_year = '1920', ordered by acad_year and report_timestamp.
--   - For each snapshot (rec.report_timestamp), produce a full set of seat-based metrics (multiple report codes) and insert them as one atomic insert per snapshot. Each loop iteration commits once after insert.
-- - Canonical enrollment selection (CTE "elog"):
--   - Source: utl_d_aa.enrollments_log filtered to records where elog.acad_year = rec.acad_year.
--   - Snapshot-window enforcement: include only enrollment rows where rec.report_timestamp BETWEEN elog.from_date AND elog.to_date (i.e., rows active in the snapshot window).
--   - Exclude enrollments with elog.semester = 'WIN' (winter).
--   - For each student (pidm) and academic year, assign ROW_NUMBER ordered to prefer rows that are active on the snapshot (start_date <= rec.report_timestamp <= end_date), then prefer the most recent from_date (DESC) and the earliest to_date (ASC). Only rows with ranking = 1 are retained as the canonical row for that pidm/acad_year.
--   - Canonical row exposes attributes used downstream: term_code, start_date, group_code, semester, camp_code, levl_code, coll_code, degc_code, majr_code, acat_code, term_seats, acad_res_seats, acad_luo_seats.
-- - Aggregation branches (each branch computes metric rows from the canonical enrollment set "elog"):
--   - TSST (term-level total seats by term + camp):
--     - Grain: term_code + camp_code for the academic snapshot.
--     - Metric uses el.term_seats and enforces term boundary via using canonical rows whose term is active for the snapshot.
--     - metric_name = 'Total'; metric_value = ROUND(SUM(term_seats)).
--     - row_hash includes report_code, report_date, acad_year, term_code, camp_code, and metric_name.
--   - TSS (year-level total seats split by camp):
--     - Two branches: TSS resident (camp_code hard-coded to 'R') using acad_res_seats and TSS LUO (camp_code 'D') using acad_luo_seats.
--     - Grain: academic-year only (no term_code or coll_code grouping); metric_name remains 'Total'.
--     - Each branch sums the appropriate year-level seat column across canonical rows.
--   - CSST (term-level college seats by term + camp):
--     - Grain: term_code + coll_code + camp_code.
--     - Metric uses el.term_seats aggregated and metric_name = coll_code (college code).
--     - Intended for measure grain lower than college (comment notes usage condition).
--   - CSS (year-level college seats split by camp):
--     - Two branches: CSS resident (camp_code 'R', uses acad_res_seats) and CSS LUO ('D', uses acad_luo_seats).
--     - Grain: academic-year + coll_code (no term breakdown).
--     - metric_name = coll_code; metric_value = ROUND(SUM(...)).
--   - LSST (term-level level seats by term + camp):
--     - Grain: term_code + levl_code + camp_code.
--     - Metric uses el.term_seats, metric_name = levl_code (level code).
--   - LSS (year-level level seats split by camp):
--     - Two branches: LSS resident (camp_code 'R', uses acad_res_seats) and LSS LUO ('D', uses acad_luo_seats).
--     - Grain: academic-year + levl_code (no term breakdown); metric_name = levl_code.
--   - PSST (term-level program seats by term + camp + college):
--     - Grain: term_code + coll_code + camp_code + program composite.
--     - metric_name is composite: majr_code-degc_code-camp_code; metric uses term_seats.
--   - PSS (year-level program seats split by camp):
--     - Two branches: PSS resident (camp_code 'R', metric_name majr_code-degc_code-R using acad_res_seats) and PSS LUO ('D', analogous using acad_luo_seats).
--     - Grain: academic-year + coll_code + program composite (no term breakdown).
-- - Final assembly & insert behavior:
--   - Each aggregation branch constructs a row_hash using standard_hash(MD5) of concatenated identifying fields to create a deterministic unique key for deduplication.
--   - All branches are UNION ALL into a single "src" set; an INSERT INTO utl_d_aa.pacing_log selects only rows from src where NOT EXISTS a target row with the same row_hash.
--   - The INSERT uses the hint IGNORE_ROW_ON_DUPKEY_INDEX(utl_d_aa.pacing_log (row_hash)) to avoid duplicate-key errors.
--   - A single COMMIT occurs per snapshot iteration after the INSERT; if insert violates NOT NULL constraints, the exception logic rolls back that iteration and logs a warning, then continues to the next snapshot.
-- - NOT NULL handling:
--   - The procedure explicitly recognizes possible NOT NULL violations during insert; when ORA-01400 occurs, the procedure ROLLBACKs the iteration, logs a WARNING, and skips that snapshot (prevents partial/invalid rows in pacing_log).
--
-- DEPENDENCIES:
-- - Oracle objects: utl_d_aa.acad_year_dates (function returning snapshot dates), utl_d_aa.enrollments_log (source staging table/view), utl_d_aa.pacing_log (target table), ads_etl.insert_job_log (logging helper), utl_d_aa.enable_parallel_dml (commented), standard_hash function available in DB.
-- - Implicit: SYSDATE usage, DBMS_OUTPUT, Oracle analytic functions and hints.
--
-- CONSTRAINTS & RISKS:
-- - High-level transaction behavior: single commit per snapshot iteration; large inserts per iteration may cause significant undo/redo and lock resources for the duration of the transaction.
-- - Memory/temp risk: the /*+ MATERIALIZE */ hint and large UNION ALL may create internal temporary segment usage; can affect temp tablespace usage for large datasets.
-- - Deduplication relies solely on deterministic row_hash; any change in hashing expression or input canonicalization may alter dedup behavior and create duplicates or skip intended rows.
-- - NOT NULL violations on any inserted column will cause the entire snapshot iteration to be skipped (logged as WARNING), potentially resulting in missing metric rows for that snapshot.
-- - Assumes enrollments_log rows are correctly bounded with from_date/to_date and that start_date/end_date are populated consistently; mismatches may affect canonical row selection.
-- - The script is hard-coded to acad_year = '1920' when calling get_acad_dates; to process other years the call must be changed.
-- - The process assumes exact matching of pidm and acad_year for canonicalization; inconsistent pidm usage across sources will affect dedup/aggregation.
-- =============================================================================
--DECLARE
v_etl_date     DATE := SYSDATE;
v_msg          VARCHAR2(2000);
v_instance     VARCHAR2(50) := upper('ALL'); -- inst from the jams job; used for determining instance
v_partition    NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_count        NUMBER := 0;
v_delete_count NUMBER := 0;
v_insert_count NUMBER := 0;
v_elapsed      NUMBER := 0;
v_total_count  NUMBER := 0;
v_job_id       VARCHAR2(32);
v_proc         VARCHAR2(100) := 'etl_aa_pacing_student_seats';
CURSOR c_terms IS
SELECT dates.acad_year,
       dates.report_date,
       dates.report_timestamp,
       dates.timeframe_start_date,
       dates.timeframe_end_date
  FROM utl_d_aa.acad_year_dates dates
 WHERE dates.report_timestamp >= SYSDATE - 3 -- run overlap just in case of weekends/fails, but only n-1 is needed normally
   AND dates.group_code = 'STD' --only need standard group_code
 ORDER BY dates.acad_year        ASC,
          dates.report_timestamp ASC;
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
v_msg     := 'START - ' || rec.acad_year || ' - ' || rec.report_timestamp || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- -------------------------------------------------------------------------
-- Single INSERT covering all 8 seat-based report codes via UNION ALL.
-- Uses NOT EXISTS anti-join against target on row_hash to skip existing rows.
-- The /*+ MATERIALIZE */ hint writes the CTE result into an internal temp
-- segment exactly once per loop iteration. All UNION ALL branches read from
-- that materialized rowset rather than re-scanning enrollments_log.
--
-- NOTE (per direction): For academic-year (non-term) report codes (TSS/CSS/LSS/PSS),
-- do NOT suffix metric_name with '-resident'/'-LUO' and do NOT group by the
-- source camp_code. Instead, UNION two branches per code with camp_code hard-coded
-- to 'R' (resident) and 'D' (LUO), while keeping metric_name unchanged for that code.
-- -------------------------------------------------------------------------
BEGIN
INSERT /*+ IGNORE_ROW_ON_DUPKEY_INDEX(utl_d_aa.pacing_log (row_hash)) */
INTO utl_d_aa.pacing_log
(report_code,
 report_date,
 acad_year,
 term_code,
 ptrm_code,
 coll_code,
 camp_code,
 metric_name,
 metric_value,
 row_hash,
 activity_date)
WITH elog AS
 (SELECT /*+ MATERIALIZE */
   el.pidm,
   el.term_code,
   el.start_date,
   el.end_date,
   el.group_code,
   el.semester,
   el.camp_code,
   el.levl_code,
   el.coll_code,
   el.degc_code,
   el.majr_code,
   el.acat_code,
   el.term_seats, -- used by all "T" suffix (term-level) report codes for seats
   el.acad_res_seats, -- resident seats for year-level splits
   el.acad_luo_seats -- LUO seats for year-level splits
    FROM (SELECT elog.pidm,
                 elog.term_code,
                 elog.start_date,
                 elog.end_date,
                 elog.from_date,
                 elog.to_date,
                 elog.group_code,
                 elog.semester,
                 elog.acad_year,
                 elog.camp_code,
                 elog.levl_code,
                 elog.coll_code,
                 elog.degc_code,
                 elog.majr_code,
                 elog.acat_code,
                 elog.term_seats,
                 elog.acad_res_seats,
                 elog.acad_luo_seats,
                 -- Ranking expression: prefer rows that are "active" on rec.report_timestamp
                 -- (start_date <= rec.report_timestamp <= end_date), then latest from_date, earliest to_date.
                 row_number() over(PARTITION BY elog.pidm, elog.acad_year ORDER BY greatest(sign(rec.report_timestamp - elog.start_date), 0) * greatest(sign(elog.end_date - rec.report_timestamp), 0) DESC, elog.from_date DESC, elog.to_date ASC) AS ranking
            FROM utl_d_aa.enrollments_log elog
           WHERE elog.acad_year = rec.acad_year
             AND rec.report_timestamp BETWEEN elog.from_date AND elog.to_date -- active snapshot window
             AND elog.semester <> 'WIN' -- excluding winter terms
          ) el
   WHERE el.ranking = 1 -- one canonical row per student per academic year
  ),
-- -------------------------------------------------------------------------
-- TSST: Total seats by term + camp (term_seats; with term boundary enforcement)
-- -------------------------------------------------------------------------
tsst_rows AS
 (SELECT 'TSST' AS report_code,
         rec.report_date AS report_date, -- unique date truncated
         rec.acad_year AS acad_year,
         el.term_code AS term_code,
         NULL AS ptrm_code,
         NULL AS coll_code,
         el.camp_code AS camp_code,
         'Total' AS metric_name,
         round(SUM(el.term_seats)) AS metric_value,
         standard_hash(nvl(to_char('TSST'), '<NULL>') || '#' || nvl(to_char(rec.report_date, 'YYYYMMDD'), '<NULL>') || '#' || nvl(to_char(rec.acad_year), '<NULL>') || '#' || nvl(to_char(el.term_code), '<NULL>') || '#' || '<NULL>' || '#' ||
                       '<NULL>' || '#' || nvl(to_char(el.camp_code), '<NULL>') || '#' || nvl(to_char('Total'), '<NULL>'), 'MD5') AS row_hash,
         SYSDATE AS activity_date
    FROM elog el
   WHERE rec.report_timestamp < el.end_date -- stop when semester is over
   HAVING round(SUM(el.term_seats)) > 0
   GROUP BY el.camp_code,
            el.term_code),
-- -------------------------------------------------------------------------
-- TSS (resident): Total seats by camp only, no term breakdown (acad_res_seats; year-level rollup)
-- HARD CODE camp_code = 'R'; metric_name stays 'Total'; NO GROUP BY camp from source
-- -------------------------------------------------------------------------
tss_rows_res AS
 (SELECT 'TSS' AS report_code,
         rec.report_date AS report_date, -- unique date truncated
         rec.acad_year AS acad_year,
         NULL AS term_code,
         NULL AS ptrm_code,
         NULL AS coll_code,
         'R' AS camp_code, -- HARD CODE 'R'
         'Total' AS metric_name,
         round(SUM(el.acad_res_seats)) AS metric_value,
         standard_hash(nvl(to_char('TSS'), '<NULL>') || '#' || nvl(to_char(rec.report_date, 'YYYYMMDD'), '<NULL>') || '#' || nvl(to_char(rec.acad_year), '<NULL>') || '#' || '<NULL>' || '#' || '<NULL>' || '#' || '<NULL>' || '#' ||
                       nvl(to_char('R'), '<NULL>') || '#' || nvl(to_char('Total'), '<NULL>'), 'MD5') AS row_hash,
         SYSDATE AS activity_date
    FROM elog el
   WHERE rec.report_timestamp < el.end_date -- stop when semester is over
   HAVING round(SUM(el.acad_res_seats)) > 0),
-- -------------------------------------------------------------------------
-- TSS (LUO): Total seats by camp only, no term breakdown (acad_luo_seats; year-level rollup)
-- HARD CODE camp_code = 'D'; metric_name stays 'Total'; NO GROUP BY camp from source
-- -------------------------------------------------------------------------
tss_rows_luo AS
 (SELECT 'TSS' AS report_code,
         rec.report_date AS report_date,
         rec.acad_year AS acad_year,
         NULL AS term_code,
         NULL AS ptrm_code,
         NULL AS coll_code,
         'D' AS camp_code, -- HARD CODE 'D'
         'Total' AS metric_name,
         round(SUM(el.acad_luo_seats)) AS metric_value,
         standard_hash(nvl(to_char('TSS'), '<NULL>') || '#' || nvl(to_char(rec.report_date, 'YYYYMMDD'), '<NULL>') || '#' || nvl(to_char(rec.acad_year), '<NULL>') || '#' || '<NULL>' || '#' || '<NULL>' || '#' || '<NULL>' || '#' ||
                       nvl(to_char('D'), '<NULL>') || '#' || nvl(to_char('Total'), '<NULL>'), 'MD5') AS row_hash,
         SYSDATE AS activity_date
    FROM elog el
   WHERE 1 = 1 HAVING round(SUM(el.acad_luo_seats)) > 0),
-- -------------------------------------------------------------------------
-- CSST: College seats by term + camp (term_seats; with term boundary enforcement)
-- NULL; **only used if the measure grain is lower than college**
-- -------------------------------------------------------------------------
csst_rows AS
 (SELECT 'CSST' AS report_code,
         rec.report_date AS report_date, -- unique date truncated
         rec.acad_year AS acad_year,
         el.term_code AS term_code,
         NULL AS ptrm_code,
         NULL AS coll_code, -- NULL; **only used if the measure grain is lower than college**
         el.camp_code AS camp_code,
         el.coll_code AS metric_name, -- **codes** for what will be displayed for each node; will need to connect to stv's later
         round(SUM(el.term_seats)) AS metric_value,
         standard_hash(nvl(to_char('CSST'), '<NULL>') || '#' || nvl(to_char(rec.report_date, 'YYYYMMDD'), '<NULL>') || '#' || nvl(to_char(rec.acad_year), '<NULL>') || '#' || nvl(to_char(el.term_code), '<NULL>') || '#' || '<NULL>' || '#' ||
                       '<NULL>' || '#' || nvl(to_char(el.camp_code), '<NULL>') || '#' || nvl(to_char(el.coll_code), '<NULL>'), 'MD5') AS row_hash,
         SYSDATE AS activity_date
    FROM elog el
   WHERE rec.report_timestamp < el.end_date -- stop when semester is over
   HAVING round(SUM(el.term_seats)) > 0
   GROUP BY el.camp_code,
            el.term_code,
            el.coll_code),
-- -------------------------------------------------------------------------
-- CSS (resident): College seats by camp only, no term breakdown (acad_res_seats; year-level rollup)
-- HARD CODE camp_code = 'R'; metric_name = coll_code; NO GROUP BY camp from source
-- NULL; **only used if the measure grain is lower than college**
-- -------------------------------------------------------------------------
css_rows_res AS
 (SELECT 'CSS' AS report_code,
         rec.report_date AS report_date, -- unique date truncated
         rec.acad_year AS acad_year,
         NULL AS term_code,
         NULL AS ptrm_code,
         NULL AS coll_code, -- NULL; **only used if the measure grain is lower than college**
         'R' AS camp_code,
         el.coll_code AS metric_name,
         round(SUM(el.acad_res_seats)) AS metric_value,
         standard_hash(nvl(to_char('CSS'), '<NULL>') || '#' || nvl(to_char(rec.report_date, 'YYYYMMDD'), '<NULL>') || '#' || nvl(to_char(rec.acad_year), '<NULL>') || '#' || '<NULL>' || '#' || '<NULL>' || '#' || '<NULL>' || '#' ||
                       nvl(to_char('R'), '<NULL>') || '#' || nvl(to_char(el.coll_code), '<NULL>'), 'MD5') AS row_hash,
         SYSDATE AS activity_date
    FROM elog el
   WHERE 1 = 1 HAVING round(SUM(el.acad_res_seats)) > 0
   GROUP BY el.coll_code),
-- -------------------------------------------------------------------------
-- CSS (LUO): College seats by camp only, no term breakdown (acad_luo_seats; year-level rollup)
-- HARD CODE camp_code = 'D'; metric_name = coll_code; NO GROUP BY camp from source
-- -------------------------------------------------------------------------
css_rows_luo AS
 (SELECT 'CSS' AS report_code,
         rec.report_date AS report_date,
         rec.acad_year AS acad_year,
         NULL AS term_code,
         NULL AS ptrm_code,
         NULL AS coll_code,
         'D' AS camp_code,
         el.coll_code AS metric_name,
         round(SUM(el.acad_luo_seats)) AS metric_value,
         standard_hash(nvl(to_char('CSS'), '<NULL>') || '#' || nvl(to_char(rec.report_date, 'YYYYMMDD'), '<NULL>') || '#' || nvl(to_char(rec.acad_year), '<NULL>') || '#' || '<NULL>' || '#' || '<NULL>' || '#' || '<NULL>' || '#' ||
                       nvl(to_char('D'), '<NULL>') || '#' || nvl(to_char(el.coll_code), '<NULL>'), 'MD5') AS row_hash,
         SYSDATE AS activity_date
    FROM elog el
   WHERE 1 = 1 HAVING round(SUM(el.acad_luo_seats)) > 0
   GROUP BY el.coll_code),
-- -------------------------------------------------------------------------
-- LSST: Level seats by term + camp (term_seats; with term boundary enforcement)
-- -------------------------------------------------------------------------
lsst_rows AS
 (SELECT 'LSST' AS report_code,
         rec.report_date AS report_date, -- unique date truncated
         rec.acad_year AS acad_year,
         el.term_code AS term_code,
         NULL AS ptrm_code,
         NULL AS coll_code,
         el.camp_code AS camp_code,
         el.levl_code AS metric_name, -- **codes** for what will be displayed for each node; will need to connect to stv's later
         round(SUM(el.term_seats)) AS metric_value,
         standard_hash(nvl(to_char('LSST'), '<NULL>') || '#' || nvl(to_char(rec.report_date, 'YYYYMMDD'), '<NULL>') || '#' || nvl(to_char(rec.acad_year), '<NULL>') || '#' || nvl(to_char(el.term_code), '<NULL>') || '#' || '<NULL>' || '#' ||
                       '<NULL>' || '#' || nvl(to_char(el.camp_code), '<NULL>') || '#' || nvl(to_char(el.levl_code), '<NULL>'), 'MD5') AS row_hash,
         SYSDATE AS activity_date
    FROM elog el
   WHERE rec.report_timestamp < el.end_date -- stop when semester is over
   HAVING round(SUM(el.term_seats)) > 0
   GROUP BY el.camp_code,
            el.term_code,
            el.levl_code),
-- -------------------------------------------------------------------------
-- LSS (resident): Level seats by camp only, no term breakdown (acad_res_seats; year-level rollup)
-- HARD CODE camp_code = 'R'; metric_name = levl_code; NO GROUP BY camp from source
-- -------------------------------------------------------------------------
lss_rows_res AS
 (SELECT 'LSS' AS report_code,
         rec.report_date AS report_date, -- unique date truncated
         rec.acad_year AS acad_year,
         NULL AS term_code,
         NULL AS ptrm_code,
         NULL AS coll_code,
         'R' AS camp_code,
         el.levl_code AS metric_name, -- **codes** for what will be displayed for each node; will need to connect to stv's later
         round(SUM(el.acad_res_seats)) AS metric_value,
         standard_hash(nvl(to_char('LSS'), '<NULL>') || '#' || nvl(to_char(rec.report_date, 'YYYYMMDD'), '<NULL>') || '#' || nvl(to_char(rec.acad_year), '<NULL>') || '#' || '<NULL>' || '#' || '<NULL>' || '#' || '<NULL>' || '#' ||
                       nvl(to_char('R'), '<NULL>') || '#' || nvl(to_char(el.levl_code), '<NULL>'), 'MD5') AS row_hash,
         SYSDATE AS activity_date
    FROM elog el
   WHERE 1 = 1 HAVING round(SUM(el.acad_res_seats)) > 0
   GROUP BY el.levl_code),
-- -------------------------------------------------------------------------
-- LSS (LUO): Level seats by camp only, no term breakdown (acad_luo_seats; year-level rollup)
-- HARD CODE camp_code = 'D'; metric_name = levl_code; NO GROUP BY camp from source
-- -------------------------------------------------------------------------
lss_rows_luo AS
 (SELECT 'LSS' AS report_code,
         rec.report_date AS report_date,
         rec.acad_year AS acad_year,
         NULL AS term_code,
         NULL AS ptrm_code,
         NULL AS coll_code,
         'D' AS camp_code,
         el.levl_code AS metric_name,
         round(SUM(el.acad_luo_seats)) AS metric_value,
         standard_hash(nvl(to_char('LSS'), '<NULL>') || '#' || nvl(to_char(rec.report_date, 'YYYYMMDD'), '<NULL>') || '#' || nvl(to_char(rec.acad_year), '<NULL>') || '#' || '<NULL>' || '#' || '<NULL>' || '#' || '<NULL>' || '#' ||
                       nvl(to_char('D'), '<NULL>') || '#' || nvl(to_char(el.levl_code), '<NULL>'), 'MD5') AS row_hash,
         SYSDATE AS activity_date
    FROM elog el
   WHERE 1 = 1 HAVING round(SUM(el.acad_luo_seats)) > 0
   GROUP BY el.levl_code),
-- -------------------------------------------------------------------------
-- PSST: Program seats by term + camp + college (term_seats; with term boundary enforcement)
-- metric_name is a composite key: majr_code-degc_code-camp_code
-- -------------------------------------------------------------------------
psst_rows AS
 (SELECT 'PSST' AS report_code,
         rec.report_date AS report_date, -- unique date truncated
         rec.acad_year AS acad_year,
         el.term_code AS term_code,
         NULL AS ptrm_code,
         el.coll_code AS coll_code,
         el.camp_code AS camp_code,
         el.majr_code || '-' || el.degc_code || '-' || el.camp_code AS metric_name, -- **codes** for what will be displayed for each node; will need to connect to stv's later
         round(SUM(el.term_seats)) AS metric_value,
         standard_hash(nvl(to_char('PSST'), '<NULL>') || '#' || nvl(to_char(rec.report_date, 'YYYYMMDD'), '<NULL>') || '#' || nvl(to_char(rec.acad_year), '<NULL>') || '#' || nvl(to_char(el.term_code), '<NULL>') || '#' || '<NULL>' || '#' ||
                       nvl(to_char(el.coll_code), '<NULL>') || '#' || nvl(to_char(el.camp_code), '<NULL>') || '#' || nvl(to_char(el.majr_code || '-' || el.degc_code || '-' || el.camp_code), '<NULL>'), 'MD5') AS row_hash,
         SYSDATE AS activity_date
    FROM elog el
   WHERE rec.report_timestamp < el.end_date -- stop when semester is over
   HAVING round(SUM(el.term_seats)) > 0
   GROUP BY el.camp_code,
            el.term_code,
            el.coll_code,
            el.majr_code || '-' || el.degc_code || '-' || el.camp_code),
-- -------------------------------------------------------------------------
-- PSS (resident): Program seats by camp + college only, no term breakdown (acad_res_seats; year-level rollup)
-- HARD CODE camp_code = 'R'; metric_name is a composite key: majr_code-degc_code-R; NO GROUP BY camp from source
-- -------------------------------------------------------------------------
pss_rows_res AS
 (SELECT 'PSS' AS report_code,
         rec.report_date AS report_date, -- unique date truncated
         rec.acad_year AS acad_year,
         NULL AS term_code,
         NULL AS ptrm_code,
         el.coll_code AS coll_code,
         'R' AS camp_code,
         el.majr_code || '-' || el.degc_code || '-' || 'R' AS metric_name, -- **codes** for what will be displayed for each node; will need to connect to stv's later
         round(SUM(el.acad_res_seats)) AS metric_value,
         standard_hash(nvl(to_char('PSS'), '<NULL>') || '#' || nvl(to_char(rec.report_date, 'YYYYMMDD'), '<NULL>') || '#' || nvl(to_char(rec.acad_year), '<NULL>') || '#' || '<NULL>' || '#' || '<NULL>' || '#' ||
                       nvl(to_char(el.coll_code), '<NULL>') || '#' || nvl(to_char('R'), '<NULL>') || '#' || nvl(to_char(el.majr_code || '-' || el.degc_code || '-' || 'R'), '<NULL>'), 'MD5') AS row_hash,
         SYSDATE AS activity_date
    FROM elog el
   WHERE 1 = 1 HAVING round(SUM(el.acad_res_seats)) > 0
   GROUP BY el.coll_code,
            el.majr_code,
            el.degc_code),
-- -------------------------------------------------------------------------
-- PSS (LUO): Program seats by camp + college only, no term breakdown (acad_luo_seats; year-level rollup)
-- HARD CODE camp_code = 'D'; metric_name is a composite key: majr_code-degc_code-D; NO GROUP BY camp from source
-- -------------------------------------------------------------------------
pss_rows_luo AS
 (SELECT 'PSS' AS report_code,
         rec.report_date AS report_date,
         rec.acad_year AS acad_year,
         NULL AS term_code,
         NULL AS ptrm_code,
         el.coll_code AS coll_code,
         'D' AS camp_code,
         el.majr_code || '-' || el.degc_code || '-' || 'D' AS metric_name,
         round(SUM(el.acad_luo_seats)) AS metric_value,
         standard_hash(nvl(to_char('PSS'), '<NULL>') || '#' || nvl(to_char(rec.report_date, 'YYYYMMDD'), '<NULL>') || '#' || nvl(to_char(rec.acad_year), '<NULL>') || '#' || '<NULL>' || '#' || '<NULL>' || '#' ||
                       nvl(to_char(el.coll_code), '<NULL>') || '#' || nvl(to_char('D'), '<NULL>') || '#' || nvl(to_char(el.majr_code || '-' || el.degc_code || '-' || 'D'), '<NULL>'), 'MD5') AS row_hash,
         SYSDATE AS activity_date
    FROM elog el
   WHERE 1 = 1 HAVING round(SUM(el.acad_luo_seats)) > 0
   GROUP BY el.coll_code,
            el.majr_code,
            el.degc_code),
-- -------------------------------------------------------------------------
-- Final union of all branches into a single source set.
-- -------------------------------------------------------------------------
src AS
 (SELECT report_code,
         report_date,
         acad_year,
         term_code,
         ptrm_code,
         coll_code,
         camp_code,
         metric_name,
         metric_value,
         row_hash,
         activity_date
    FROM tsst_rows
  UNION ALL
  SELECT report_code,
         report_date,
         acad_year,
         term_code,
         ptrm_code,
         coll_code,
         camp_code,
         metric_name,
         metric_value,
         row_hash,
         activity_date
    FROM tss_rows_res
  UNION ALL
  SELECT report_code,
         report_date,
         acad_year,
         term_code,
         ptrm_code,
         coll_code,
         camp_code,
         metric_name,
         metric_value,
         row_hash,
         activity_date
    FROM tss_rows_luo
  UNION ALL
  SELECT report_code,
         report_date,
         acad_year,
         term_code,
         ptrm_code,
         coll_code,
         camp_code,
         metric_name,
         metric_value,
         row_hash,
         activity_date
    FROM csst_rows
  UNION ALL
  SELECT report_code,
         report_date,
         acad_year,
         term_code,
         ptrm_code,
         coll_code,
         camp_code,
         metric_name,
         metric_value,
         row_hash,
         activity_date
    FROM css_rows_res
  UNION ALL
  SELECT report_code,
         report_date,
         acad_year,
         term_code,
         ptrm_code,
         coll_code,
         camp_code,
         metric_name,
         metric_value,
         row_hash,
         activity_date
    FROM css_rows_luo
  UNION ALL
  SELECT report_code,
         report_date,
         acad_year,
         term_code,
         ptrm_code,
         coll_code,
         camp_code,
         metric_name,
         metric_value,
         row_hash,
         activity_date
    FROM lsst_rows
  UNION ALL
  SELECT report_code,
         report_date,
         acad_year,
         term_code,
         ptrm_code,
         coll_code,
         camp_code,
         metric_name,
         metric_value,
         row_hash,
         activity_date
    FROM lss_rows_res
  UNION ALL
  SELECT report_code,
         report_date,
         acad_year,
         term_code,
         ptrm_code,
         coll_code,
         camp_code,
         metric_name,
         metric_value,
         row_hash,
         activity_date
    FROM lss_rows_luo
  UNION ALL
  SELECT report_code,
         report_date,
         acad_year,
         term_code,
         ptrm_code,
         coll_code,
         camp_code,
         metric_name,
         metric_value,
         row_hash,
         activity_date
    FROM psst_rows
  UNION ALL
  SELECT report_code,
         report_date,
         acad_year,
         term_code,
         ptrm_code,
         coll_code,
         camp_code,
         metric_name,
         metric_value,
         row_hash,
         activity_date
    FROM pss_rows_res
  UNION ALL
  SELECT report_code,
         report_date,
         acad_year,
         term_code,
         ptrm_code,
         coll_code,
         camp_code,
         metric_name,
         metric_value,
         row_hash,
         activity_date
    FROM pss_rows_luo)
SELECT sr.report_code,
       sr.report_date,
       sr.acad_year,
       sr.term_code,
       sr.ptrm_code,
       sr.coll_code,
       sr.camp_code,
       sr.metric_name,
       sr.metric_value,
       sr.row_hash,
       sr.activity_date
  FROM src sr
 WHERE NOT EXISTS (SELECT 1 FROM utl_d_aa.pacing_log t WHERE t.row_hash = sr.row_hash);
-- -------------------------------------------------------------------------
-- Capture total rows inserted across all report codes this iteration.
-- Single COMMIT per loop iteration: all report codes land atomically,
-- so a failure on any acad_year + report_timestamp combination rolls back
-- cleanly without partial metric sets entering pacing_log.
-- -------------------------------------------------------------------------
v_count       := SQL%ROWCOUNT;
v_total_count := v_total_count + v_count; -- keep running total of rows processed
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'INSERT (dedup) - ' || rec.acad_year || ' - ' || rec.report_timestamp || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows inserted: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
EXCEPTION
WHEN OTHERS THEN
-- If any unexpected NOT NULL violations occur, log WARNING and continue to next day.
IF SQLCODE = -1400 THEN
ROLLBACK;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'WARNING - ' || rec.acad_year || ' - ' || rec.report_timestamp || ' - ' || v_partition || ' encountered NULL-constrained value(s) during insert; iteration skipped.';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'WARNING', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
-- continue to next loop iteration
ELSE
RAISE;
END IF;
END;
END LOOP; -- c_terms
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
EXCEPTION
WHEN OTHERS THEN
ROLLBACK;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
RAISE;
END etl_aa_pacing_student_seats;

procedure etl_aa_pacing_student_enrollment (jobnumber number, processid varchar2, processname varchar2) is 
--DECLARE
v_etl_date     DATE := SYSDATE;
v_msg          VARCHAR2(2000);
v_instance     VARCHAR2(50) := upper('ALL');
v_partition    NUMBER := 0;
v_count        NUMBER := 0;
v_delete_count NUMBER := 0;
v_insert_count NUMBER := 0;
v_elapsed      NUMBER := 0;
v_total_count  NUMBER := 0;
v_job_id       VARCHAR2(32);
v_proc         VARCHAR2(100) := 'etl_aa_pacing_student_enrollment';
CURSOR c_terms IS
SELECT dates.acad_year,
       dates.report_date,
       dates.report_timestamp,
       dates.timeframe_start_date,
       dates.timeframe_end_date
  FROM utl_d_aa.acad_year_dates dates
 WHERE dates.report_timestamp >= SYSDATE - 3 -- run overlap just in case of weekends/fails, but only n-1 is needed normally
   AND dates.group_code = 'STD' --only need standard group_code
 ORDER BY dates.acad_year        ASC,
          dates.report_timestamp ASC;
BEGIN
-- dbms_output.enable(buffer_size => NULL);
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
v_msg     := 'START - ' || rec.acad_year || ' - ' || rec.report_timestamp || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- -------------------------------------------------------------------------
-- Single INSERT covering all 8 report codes via UNION ALL.
--
-- The /*+ MATERIALIZE */ hint instructs Oracle to write the CTE result into
-- an internal temporary segment exactly once. Every UNION ALL branch then
-- reads from that materialized rowset rather than re-executing the ranking
-- subquery against enrollments_log. This replaces the PTT pattern entirely
-- and requires no DDL privileges whatsoever.
--
-- The ranking logic guarantees exactly one row per (pidm, acad_year):
--   - Prefer rows where report_timestamp falls within [start_date, end_date]
--   - Tiebreak: latest from_date, then earliest to_date
--
-- Because the CTE already produces one row per pidm, COUNT(pidm) is
-- semantically equivalent to COUNT(DISTINCT pidm) on the raw log table
-- and is cheaper to execute (no sort-distinct operation needed).
--
-- The outer LEFT JOIN to pacing_log filters out already-loaded row_hashes,
-- preserving the original incremental/idempotent load pattern.
-- -------------------------------------------------------------------------
INSERT INTO utl_d_aa.pacing_log
(report_code,
 report_date,
 acad_year,
 term_code,
 ptrm_code,
 coll_code,
 camp_code,
 metric_name,
 metric_value,
 row_hash,
 activity_date)
WITH elog AS
 (SELECT /*+ MATERIALIZE */
   el.pidm,
   el.term_code,
   el.start_date,
   el.end_date,
   el.group_code,
   el.semester,
   el.camp_code,
   el.levl_code,
   el.coll_code,
   el.degc_code,
   el.majr_code,
   el.acat_code
    FROM (SELECT elog.pidm,
                 elog.term_code,
                 elog.start_date,
                 elog.end_date,
                 elog.from_date,
                 elog.to_date,
                 elog.group_code,
                 elog.semester,
                 elog.acad_year,
                 elog.camp_code,
                 elog.levl_code,
                 elog.coll_code,
                 elog.degc_code,
                 elog.majr_code,
                 elog.acat_code,
                 -- Ranking expression: prefer rows that are "active" on rec.report_timestamp
                 -- (start_date <= rec.report_timestamp <= end_date).
                 row_number() over(PARTITION BY elog.pidm, elog.acad_year ORDER BY greatest(sign(rec.report_timestamp - elog.start_date), 0) * greatest(sign(elog.end_date - rec.report_timestamp), 0) DESC, elog.from_date DESC, elog.to_date ASC) AS ranking
            FROM utl_d_aa.enrollments_log elog
           WHERE elog.acad_year = rec.acad_year
             AND rec.report_timestamp BETWEEN elog.from_date AND elog.to_date -- active snapshot window
             AND elog.semester <> 'WIN' -- excluding winter terms
          ) el
   WHERE el.ranking = 1 -- one canonical row per student per academic year
  ),
-- -------------------------------------------------------------------------
-- All 8 aggregation branches are defined as named CTEs for readability.
-- Each branch groups the already-deduplicated elog rowset differently.
-- -------------------------------------------------------------------------
tset_rows AS
 (
  -- TSET: Total enrollment by term + camp (with term boundary enforcement)
  SELECT 'TSET' AS report_code,
          rec.report_date AS report_date, -- unique date truncated
          rec.acad_year AS acad_year,
          el.term_code AS term_code,
          NULL AS ptrm_code,
          NULL AS coll_code,
          el.camp_code AS camp_code,
          'Total' AS metric_name, -- **codes** for what will be displayed for each node; will need to connect to stv's later
          COUNT(el.pidm) AS metric_value, -- already 1-row-per-pidm; DISTINCT not required
          standard_hash(nvl(to_char('TSET'), '<NULL>') || '#' || --
                        nvl(to_char(rec.report_date, 'YYYYMMDD'), '<NULL>') || '#' || --
                        nvl(to_char(rec.acad_year), '<NULL>') || '#' || --
                        nvl(to_char(el.term_code), '<NULL>') || '#' || --
                        '<NULL>' || '#' || --
                        '<NULL>' || '#' || --
                        nvl(to_char(el.camp_code), '<NULL>') || '#' || --
                        nvl(to_char('Total'), '<NULL>'), 'MD5') AS row_hash,
          SYSDATE AS activity_date
    FROM elog el
   WHERE rec.report_timestamp < el.end_date -- stop when semester is over
   HAVING COUNT(el.pidm) > 0
   GROUP BY el.camp_code,
             el.term_code),
tse_rows AS
 (
  -- TSE: Total enrollment by camp only (no term breakdown)
  SELECT 'TSE' AS report_code,
          rec.report_date AS report_date, -- unique date truncated
          rec.acad_year AS acad_year,
          NULL AS term_code,
          NULL AS ptrm_code,
          NULL AS coll_code,
          el.camp_code AS camp_code,
          'Total' AS metric_name, -- **codes** for what will be displayed for each node; will need to connect to stv's later
          COUNT(el.pidm) AS metric_value, -- already 1-row-per-pidm; DISTINCT not required
          standard_hash(nvl(to_char('TSE'), '<NULL>') || '#' || --
                        nvl(to_char(rec.report_date, 'YYYYMMDD'), '<NULL>') || '#' || --
                        nvl(to_char(rec.acad_year), '<NULL>') || '#' || --
                        '<NULL>' || '#' || --
                        '<NULL>' || '#' || --
                        '<NULL>' || '#' || --
                        nvl(to_char(el.camp_code), '<NULL>') || '#' || --
                        nvl(to_char('Total'), '<NULL>'), 'MD5') AS row_hash,
          SYSDATE AS activity_date
    FROM elog el
   WHERE 1 = 1 HAVING COUNT(el.pidm) > 0
   GROUP BY el.camp_code),
cset_rows AS
 (
  -- CSET: College enrollment by term + camp (with term boundary enforcement)
  SELECT 'CSET' AS report_code,
          rec.report_date AS report_date, -- unique date truncated
          rec.acad_year AS acad_year,
          el.term_code AS term_code,
          NULL AS ptrm_code,
          NULL AS coll_code,
          el.camp_code AS camp_code,
          el.coll_code AS metric_name, -- **codes** for what will be displayed for each node; will need to connect to stv's later
          COUNT(el.pidm) AS metric_value, -- already 1-row-per-pidm; DISTINCT not required
          standard_hash(nvl(to_char('CSET'), '<NULL>') || '#' || --
                        nvl(to_char(rec.report_date, 'YYYYMMDD'), '<NULL>') || '#' || --
                        nvl(to_char(rec.acad_year), '<NULL>') || '#' || --
                        nvl(to_char(el.term_code), '<NULL>') || '#' || --
                        '<NULL>' || '#' || --
                        '<NULL>' || '#' || --
                        nvl(to_char(el.camp_code), '<NULL>') || '#' || --
                        nvl(to_char(el.coll_code), '<NULL>'), 'MD5') AS row_hash,
          SYSDATE AS activity_date
    FROM elog el
   WHERE rec.report_timestamp < el.end_date -- stop when semester is over
   HAVING COUNT(el.pidm) > 0
   GROUP BY el.camp_code,
             el.term_code,
             el.coll_code),
cse_rows AS
 (
  -- CSE: College enrollment by camp only (no term breakdown)
  SELECT 'CSE' AS report_code,
          rec.report_date AS report_date, -- unique date truncated
          rec.acad_year AS acad_year,
          NULL AS term_code,
          NULL AS ptrm_code,
          NULL AS coll_code,
          el.camp_code AS camp_code,
          el.coll_code AS metric_name, -- **codes** for what will be displayed for each node; will need to connect to stv's later
          COUNT(el.pidm) AS metric_value, -- already 1-row-per-pidm; DISTINCT not required
          standard_hash(nvl(to_char('CSE'), '<NULL>') || '#' || --
                        nvl(to_char(rec.report_date, 'YYYYMMDD'), '<NULL>') || '#' || --
                        nvl(to_char(rec.acad_year), '<NULL>') || '#' || --
                        '<NULL>' || '#' || --
                        '<NULL>' || '#' || --
                        '<NULL>' || '#' || --
                        nvl(to_char(el.camp_code), '<NULL>') || '#' || --
                        nvl(to_char(el.coll_code), '<NULL>'), 'MD5') AS row_hash,
          SYSDATE AS activity_date
    FROM elog el
   WHERE 1 = 1 HAVING COUNT(el.pidm) > 0
   GROUP BY el.camp_code,
             el.coll_code),
lset_rows AS
 (
  -- LSET: Level enrollment by term + camp (with term boundary enforcement)
  SELECT 'LSET' AS report_code,
          rec.report_date AS report_date, -- unique date truncated
          rec.acad_year AS acad_year,
          el.term_code AS term_code,
          NULL AS ptrm_code,
          NULL AS coll_code,
          el.camp_code AS camp_code,
          el.levl_code AS metric_name, -- **codes** for what will be displayed for each node; will need to connect to stv's later
          COUNT(el.pidm) AS metric_value, -- already 1-row-per-pidm; DISTINCT not required
          standard_hash(nvl(to_char('LSET'), '<NULL>') || '#' || --
                        nvl(to_char(rec.report_date, 'YYYYMMDD'), '<NULL>') || '#' || --
                        nvl(to_char(rec.acad_year), '<NULL>') || '#' || --
                        nvl(to_char(el.term_code), '<NULL>') || '#' || --
                        '<NULL>' || '#' || --
                        '<NULL>' || '#' || --
                        nvl(to_char(el.camp_code), '<NULL>') || '#' || --
                        nvl(to_char(el.levl_code), '<NULL>'), 'MD5') AS row_hash,
          SYSDATE AS activity_date
    FROM elog el
   WHERE rec.report_timestamp < el.end_date -- stop when semester is over
   HAVING COUNT(el.pidm) > 0
   GROUP BY el.camp_code,
             el.term_code,
             el.levl_code),
lse_rows AS
 (
  -- LSE: Level enrollment by camp only (no term breakdown)
  SELECT 'LSE' AS report_code,
          rec.report_date AS report_date, -- unique date truncated
          rec.acad_year AS acad_year,
          NULL AS term_code,
          NULL AS ptrm_code,
          NULL AS coll_code,
          el.camp_code AS camp_code,
          el.levl_code AS metric_name, -- **codes** for what will be displayed for each node; will need to connect to stv's later
          COUNT(el.pidm) AS metric_value, -- already 1-row-per-pidm; DISTINCT not required
          standard_hash(nvl(to_char('LSE'), '<NULL>') || '#' || --
                        nvl(to_char(rec.report_date, 'YYYYMMDD'), '<NULL>') || '#' || --
                        nvl(to_char(rec.acad_year), '<NULL>') || '#' || --
                        '<NULL>' || '#' || --
                        '<NULL>' || '#' || --
                        '<NULL>' || '#' || --
                        nvl(to_char(el.camp_code), '<NULL>') || '#' || --
                        nvl(to_char(el.levl_code), '<NULL>'), 'MD5') AS row_hash,
          SYSDATE AS activity_date
    FROM elog el
   WHERE 1 = 1 HAVING COUNT(el.pidm) > 0
   GROUP BY el.camp_code,
             el.levl_code),
pset_rows AS
 (
  -- PSET: Program enrollment by term + camp + college (with term boundary enforcement)
  -- metric_name is a composite key: majr_code-degc_code-camp_code
  SELECT 'PSET' AS report_code,
          rec.report_date AS report_date, -- unique date truncated
          rec.acad_year AS acad_year,
          el.term_code AS term_code,
          NULL AS ptrm_code,
          el.coll_code AS coll_code,
          el.camp_code AS camp_code,
          el.majr_code || '-' || el.degc_code || '-' || el.camp_code AS metric_name, -- **codes** for what will be displayed for each node; will need to connect to stv's later
          COUNT(el.pidm) AS metric_value, -- already 1-row-per-pidm; DISTINCT not required
          standard_hash(nvl(to_char('PSET'), '<NULL>') || '#' || --
                        nvl(to_char(rec.report_date, 'YYYYMMDD'), '<NULL>') || '#' || --
                        nvl(to_char(rec.acad_year), '<NULL>') || '#' || --
                        nvl(to_char(el.term_code), '<NULL>') || '#' || --
                        '<NULL>' || '#' || --
                        nvl(to_char(el.coll_code), '<NULL>') || '#' || --
                        nvl(to_char(el.camp_code), '<NULL>') || '#' || --
                        nvl(to_char(el.majr_code || '-' || el.degc_code || '-' || el.camp_code), '<NULL>'), 'MD5') AS row_hash,
          SYSDATE AS activity_date
    FROM elog el
   WHERE rec.report_timestamp < el.end_date -- stop when semester is over
   HAVING COUNT(el.pidm) > 0
   GROUP BY el.camp_code,
             el.term_code,
             el.coll_code,
             el.majr_code || '-' || el.degc_code || '-' || el.camp_code),
pse_rows AS
 (
  -- PSE: Program enrollment by camp + college only (no term breakdown)
  -- metric_name is a composite key: majr_code-degc_code-camp_code
  SELECT 'PSE' AS report_code,
          rec.report_date AS report_date, -- unique date truncated
          rec.acad_year AS acad_year,
          NULL AS term_code,
          NULL AS ptrm_code,
          el.coll_code AS coll_code,
          el.camp_code AS camp_code,
          el.majr_code || '-' || el.degc_code || '-' || el.camp_code AS metric_name, -- **codes** for what will be displayed for each node; will need to connect to stv's later
          COUNT(el.pidm) AS metric_value, -- already 1-row-per-pidm; DISTINCT not required
          standard_hash(nvl(to_char('PSE'), '<NULL>') || '#' || --
                        nvl(to_char(rec.report_date, 'YYYYMMDD'), '<NULL>') || '#' || --
                        nvl(to_char(rec.acad_year), '<NULL>') || '#' || --
                        '<NULL>' || '#' || --
                        '<NULL>' || '#' || --
                        nvl(to_char(el.coll_code), '<NULL>') || '#' || --
                        nvl(to_char(el.camp_code), '<NULL>') || '#' || --
                        nvl(to_char(el.majr_code || '-' || el.degc_code || '-' || el.camp_code), '<NULL>'), 'MD5') AS row_hash,
          SYSDATE AS activity_date
    FROM elog el
   WHERE 1 = 1 HAVING COUNT(el.pidm) > 0
   GROUP BY el.camp_code,
             el.coll_code,
             el.majr_code || '-' || el.degc_code || '-' || el.camp_code)
-- -------------------------------------------------------------------------
-- Final SELECT unions all 8 named CTE branches into one result set.
-- The LEFT JOIN to pacing_log on row_hash filters out any already-loaded
-- rows across ALL report codes in a single pass, preserving the original
-- incremental/idempotent load pattern.
-- -------------------------------------------------------------------------
SELECT src.report_code,
       src.report_date,
       src.acad_year,
       src.term_code,
       src.ptrm_code,
       src.coll_code,
       src.camp_code,
       src.metric_name,
       src.metric_value,
       src.row_hash,
       src.activity_date
  FROM (SELECT report_code,
               report_date,
               acad_year,
               term_code,
               ptrm_code,
               coll_code,
               camp_code,
               metric_name,
               metric_value,
               row_hash,
               activity_date
          FROM tset_rows
        UNION ALL
        SELECT report_code,
               report_date,
               acad_year,
               term_code,
               ptrm_code,
               coll_code,
               camp_code,
               metric_name,
               metric_value,
               row_hash,
               activity_date
          FROM tse_rows
        UNION ALL
        SELECT report_code,
               report_date,
               acad_year,
               term_code,
               ptrm_code,
               coll_code,
               camp_code,
               metric_name,
               metric_value,
               row_hash,
               activity_date
          FROM cset_rows
        UNION ALL
        SELECT report_code,
               report_date,
               acad_year,
               term_code,
               ptrm_code,
               coll_code,
               camp_code,
               metric_name,
               metric_value,
               row_hash,
               activity_date
          FROM cse_rows
        UNION ALL
        SELECT report_code,
               report_date,
               acad_year,
               term_code,
               ptrm_code,
               coll_code,
               camp_code,
               metric_name,
               metric_value,
               row_hash,
               activity_date
          FROM lset_rows
        UNION ALL
        SELECT report_code,
               report_date,
               acad_year,
               term_code,
               ptrm_code,
               coll_code,
               camp_code,
               metric_name,
               metric_value,
               row_hash,
               activity_date
          FROM lse_rows
        UNION ALL
        SELECT report_code,
               report_date,
               acad_year,
               term_code,
               ptrm_code,
               coll_code,
               camp_code,
               metric_name,
               metric_value,
               row_hash,
               activity_date
          FROM pset_rows
        UNION ALL
        SELECT report_code,
               report_date,
               acad_year,
               term_code,
               ptrm_code,
               coll_code,
               camp_code,
               metric_name,
               metric_value,
               row_hash,
               activity_date
          FROM pse_rows) src
  LEFT JOIN utl_d_aa.pacing_log tgt
    ON tgt.row_hash = src.row_hash
 WHERE tgt.report_date IS NULL;
-- -------------------------------------------------------------------------
-- Capture total rows inserted across all 8 report codes this iteration.
-- Single COMMIT per loop iteration: all 8 report codes land atomically,
-- so a failure on any acad_year + report_timestamp combination rolls back
-- cleanly without partial metric sets entering pacing_log.
-- -------------------------------------------------------------------------
v_count       := SQL%ROWCOUNT;
v_total_count := v_total_count + v_count; -- keep running total of rows processed
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'INSERT - ALL CODES - ' || rec.acad_year || ' - ' || rec.report_timestamp || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
END LOOP; -- c_terms
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
-- log any errors
EXCEPTION
WHEN OTHERS THEN
ROLLBACK;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
RAISE;
END etl_aa_pacing_student_enrollment;

procedure etl_aa_pacing_tableau (jobnumber number, processid varchar2, processname varchar2) is
-- =============================================================================
-- PURPOSE: Populates a Tableau reporting table with academic advising pacing metrics normalized across multiple academic years and report types.
--
-- TARGET(S): utl_d_aa.pacing_tableau
--
-- UNIQUE KEY / INDEX: N/A - Full data refresh (table is truncated before each load)
--
-- BUSINESS LOGIC & CONDITIONS:
-- - Processes data independently for each distinct academic year found in the pacing_schedule table, ordered from most recent to oldest.
-- - Normalizes report dates to the correct calendar year based on the academic year start and end years (resolves cross-calendar-year academic periods).
-- - Filters metrics to only those days where the academic day of week matches the calendar day of week (via utl_d_aa.acad_year_dates).
-- - Excludes all rows with zero metric values to prevent NULL gaps in the dashboard display.
-- - Includes only metric names that appear in at least one row within the current academic year (filters out stale or deprecated metrics).
-- - Classifies part-of-term codes starting with 'Y' or 'L' as 'Med/Law'; all others retain their original code or default to '*'.
-- - Maps campus codes to human-readable labels: 'R' becomes 'Resident', 'D' becomes 'LUO'.
-- - Resolves college descriptions from the saturn.stvcoll table; marks as '*' if the college code is missing AND the report name contains the word 'college'.
-- - Dynamically enriches metric names based on report type: replaces metric code with full college description for college-type reports, level description for level-type reports, and program name with metric context for program-type reports.
-- - Carries forward the current_year flag ('Yes' or 'No') and years_ago context from the academic schedule for downstream dashboard filtering.
-- - Loads data in batches of 100,000 rows per commit to optimize transaction throughput and memory usage.
-- - Stamps all inserted rows with the maximum activity_date from the source pacing_log table for lineage tracking.
--
-- DEPENDENCIES: utl_d_aa.pacing_schedule, utl_d_aa.pacing_log, utl_d_aa.pacing_reports, utl_d_aa.acad_year_dates, zbtm.terms_by_group_v, saturn.stvcoll, saturn.stvlevl, stvmajr, ads_etl.insert_job_log procedure
--
-- CONSTRAINTS & RISKS:
-- - Full table truncation prior to load means any failure mid-process leaves the target table empty; consider implementing a staging table approach for resilience.
-- - Joins to saturn.stvcoll, saturn.stvlevl, and stvmajr are LEFT JOINs; missing dimension records will result in '*' or metric_name passthrough, which may mask data quality issues.
-- - The EXISTS subquery filtering on current-year metric names may significantly reduce row volume if the current academic year has few active metrics.
-- - Bulk fetch LIMIT of 100,000 rows combined with multiple complex joins may consume substantial sort/temp tablespace, especially across many academic years.
-- - If pacing_log does not contain data for all report codes listed, some reports will silently produce no output.
-- - Job ID is generated once at start; if the procedure is re-executed within the same second on the same instance, the hash will collide with prior executions.
-- ============================================================================= 
-- DECLARE
v_etl_date      DATE := SYSDATE;
v_msg           VARCHAR2(2000);
v_instance      VARCHAR2(50) := upper('ALL'); -- inst from the jams job; used for determining instance
v_partition     NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0 
v_count         NUMBER := 0;
v_delete_count  NUMBER := 0;
v_insert_count  NUMBER := 0;
v_elapsed       NUMBER := 0;
v_total_count   NUMBER := 0;
v_job_id        VARCHAR2(32);
v_proc          VARCHAR2(100) := 'etl_aa_pacing_tableau';
v_activity_date DATE;
c_batch_limit   PLS_INTEGER := 100000;
-- Cursor #1 (terms): drives work per academic year and provides year-context for graph_date
CURSOR c_terms IS
SELECT dates.acad_year,
       CASE
       WHEN dates.acad_year_active_ind = 'Y' THEN
        'Yes'
       ELSE
        'No'
       END AS current_year, -- the yes/no is a pass-thru to the dashboard
       dates.report_date,
       dates.report_timestamp,
       dates.timeframe_start_date,
       dates.timeframe_end_date,
       MIN((SELECT MIN('20' || substr(dates.acad_year, 1, 2))
             FROM zbtm.terms_by_group_v t1
            WHERE (SYSDATE BETWEEN to_date('07/01/20' || substr(dates.acad_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(dates.acad_year, 3, 2), 'mm/dd/yyyy') OR
                  SYSDATE + 14 BETWEEN to_date('07/01/20' || substr(dates.acad_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(dates.acad_year, 3, 2), 'mm/dd/yyyy')))) over() AS start_yyyy,
       MIN((SELECT MIN('20' || substr(dates.acad_year, 3, 2))
             FROM zbtm.terms_by_group_v t1
            WHERE (SYSDATE BETWEEN to_date('07/01/20' || substr(dates.acad_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(dates.acad_year, 3, 2), 'mm/dd/yyyy') OR
                  SYSDATE + 14 BETWEEN to_date('07/01/20' || substr(dates.acad_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(dates.acad_year, 3, 2), 'mm/dd/yyyy')))) over() AS end_yyyy,
       dates.acad_year_rank - 1 AS years_ago -- simluate the way we show it in the dashboard
  FROM utl_d_aa.acad_year_dates dates
 WHERE dates.acad_day_number = dates.current_acad_day_number -- get the properly aligned acad day of the year to compare to previous years
   AND dates.group_code = 'STD' -- only need standard group_code
   AND dates.acad_year >= '1920' -- no historical prior to 1920
 ORDER BY 1 DESC;
-- Cursor #2 (main data): parameterized by year-context; produces rows for pacing_tableau
--   * graph_date is normalized to the proper calendar year using start_yyyy/end_yyyy
--   * limit to last 5 years & academic day_number alignment (replaces NLS weekday)
--   * coll_desc is resolved from plog.coll_code (renamed from coll_code -> coll_desc)
CURSOR c_data(p_acad_year  VARCHAR2,
              p_start_yyyy NUMBER,
              p_end_yyyy   NUMBER,
              p_current_yr VARCHAR2,
              p_years_ago  NUMBER,
              p_etl_date   DATE) IS
SELECT plog.report_date,
       to_date(to_char(plog.report_date, 'MM/DD') || CASE
               WHEN to_char(plog.report_date, 'YY') = substr(plog.acad_year, 1, 2) THEN
                to_char(p_start_yyyy)
               ELSE
                to_char(p_end_yyyy)
               END, 'MM/DDYYYY') AS graph_date,
       plog.acad_year,
       nvl(plog.term_code, '*') AS term_code,
       CASE
       WHEN substr(plog.ptrm_code, 1, 1) IN ('Y', 'L') THEN
        'Med/Law'
       ELSE
        nvl(plog.ptrm_code, '*')
       END AS ptrm_code,
       CASE
       WHEN c4.stvcoll_desc IS NULL
            AND lower(prep.report_name) LIKE '%college%' THEN
        '*'
       ELSE
        nvl(c4.stvcoll_desc, '*')
       END AS coll_desc,
       CASE
       WHEN plog.camp_code = 'R' THEN
        'Resident'
       WHEN plog.camp_code = 'D' THEN
        'LUO'
       END AS campus,
       nvl(terms.semester_desc, '*') AS semester,
       p_current_yr AS current_year,
       p_years_ago AS years_ago,
       prep.report_code,
       prep.report_name,
       prep.report_desc,
       CASE
       WHEN s_desc.stvcoll_code IS NOT NULL
            AND lower(prep.report_name) LIKE '%college%' THEN
        s_desc.stvcoll_desc
       WHEN l_desc.stvlevl_code IS NOT NULL
            AND lower(prep.report_name) LIKE '%level%' THEN
        l_desc.stvlevl_desc
       WHEN stvmajr_code IS NOT NULL
            AND lower(prep.report_name) LIKE '%program%' THEN
        stvmajr_desc || ' (' || plog.metric_name || ')'
       ELSE
        plog.metric_name
       END AS metric_name,
       plog.metric_value,
       plog.row_hash
  FROM utl_d_aa.pacing_log plog
  JOIN utl_d_aa.pacing_reports prep
    ON prep.report_code = plog.report_code
   AND plog.report_code IN ('CRC', 'CRP', 'CSE', 'CSF', 'CSH', 'CSS', 'TRC', 'TRP', 'TRS', 'TSE', 'TSF', 'TSH', 'TSS') -- only select reports
  JOIN utl_d_aa.acad_year_dates dates
    ON dates.acad_year = plog.acad_year
   AND dates.report_date = plog.report_date
   AND dates.acad_year = p_acad_year
   AND dates.current_day_of_week = dates.day_of_week -- return weekly dates
   AND dates.group_code = 'STD' -- only need standard group_code
  LEFT JOIN zbtm.terms_by_group_v terms
    ON terms.term_code = plog.term_code
  LEFT JOIN saturn.stvcoll c4
    ON c4.stvcoll_code = plog.coll_code
  LEFT JOIN saturn.stvcoll s_desc
    ON s_desc.stvcoll_code = plog.metric_name
  LEFT JOIN saturn.stvlevl l_desc
    ON l_desc.stvlevl_code = plog.metric_name
  LEFT JOIN stvmajr
    ON stvmajr.stvmajr_code = substr(plog.metric_name, 1, 4)
 WHERE plog.metric_value <> 0 --  excludes zeros at source so dashboard renders NULL gaps
   AND EXISTS (SELECT 1
          FROM utl_d_aa.pacing_log cur_pl
          JOIN utl_d_aa.pacing_schedule cur_sched
            ON cur_sched.acad_year = cur_pl.acad_year
           AND cur_sched.current_year = 'Y' -- 'Y' matches the raw schedule flag (c_terms maps this to 'Yes'); only carry metric_names that appear in a current acad year
         WHERE cur_pl.metric_name = plog.metric_name);
-- bulk collection types
TYPE rec_data_t IS TABLE OF c_data%ROWTYPE;
BEGIN
dbms_output.enable(buffer_size => NULL);
--
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
utl_d_aa.truncate_table(v_table_name => 'pacing_tableau');
-- determine activity_date once to avoid analytic in-row computation
SELECT MAX(activity_date) INTO v_activity_date FROM utl_d_aa.pacing_log;
-- Main processing loop per academic year
FOR rec IN c_terms
LOOP
v_count := 0; -- reset count
dbms_lock.sleep(1); -- pause a second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || rec.acad_year || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- open main data cursor and bulk insert in chunks of 100,000
DECLARE
l_batch rec_data_t;
BEGIN
OPEN c_data(rec.acad_year, rec.start_yyyy, rec.end_yyyy, rec.current_year, rec.years_ago, v_etl_date);
LOOP
FETCH c_data BULK COLLECT
INTO l_batch LIMIT c_batch_limit;
EXIT WHEN l_batch.count = 0;
BEGIN
-- bulk insert; commit limited to 100,000 rows per loop by LIMIT clause
FORALL i IN 1 .. l_batch.count
INSERT INTO utl_d_aa.pacing_tableau
(report_date,
 graph_date,
 acad_year,
 term_code,
 ptrm_code,
 coll_desc,
 campus,
 semester,
 current_year,
 years_ago,
 report_code,
 report_name,
 report_desc,
 metric_name,
 metric_value,
 row_hash,
 activity_date)
VALUES
(l_batch(i).report_date,
 l_batch(i).graph_date,
 l_batch(i).acad_year,
 l_batch(i).term_code,
 l_batch(i).ptrm_code,
 l_batch(i).coll_desc,
 l_batch(i).campus,
 l_batch(i).semester,
 l_batch(i).current_year,
 l_batch(i).years_ago,
 l_batch(i).report_code,
 l_batch(i).report_name,
 l_batch(i).report_desc,
 l_batch(i).metric_name,
 l_batch(i).metric_value,
 l_batch(i).row_hash,
 v_activity_date);
v_insert_count := SQL%ROWCOUNT;
v_total_count  := v_total_count + v_insert_count;
COMMIT; -- commit each batch of up to 100,000 rows
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'INSERT - ' || rec.acad_year || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_insert_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_insert_count);
EXCEPTION
WHEN OTHERS THEN
-- simple batch-level logging (no SAVE EXCEPTIONS, no per-row logging)
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200) || ' - AIDY ' || rec.acad_year || ' batch failed at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss');
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
-- skip this batch and continue
END;
-- optional pacing for I/O
dbms_lock.sleep(1);
END LOOP;
CLOSE c_data;
END;
END LOOP; -- c_terms 
dbms_lock.sleep(1); -- pause a second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
EXCEPTION
WHEN OTHERS THEN
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
RAISE;
END etl_aa_pacing_tableau;

END load_aa_etl_pacing_dev;