create or replace package load_aa_etl_ret is
procedure etl_aa_enrollments_log(jobnumber number, processid varchar2, processname varchar2); ---     11-20-2025  WGRIFFITH2  --Initial release
procedure etl_aa_retention_grads(jobnumber number, processid varchar2, processname varchar2); ---     11-20-2025  WGRIFFITH2  --Initial release
procedure etl_aa_course_sections_log(jobnumber number, processid varchar2, processname varchar2); ---     11-20-2025  WGRIFFITH2  --Initial release
procedure etl_aa_retention_log(jobnumber number, processid varchar2, processname varchar2); ---     11-20-2025  WGRIFFITH2  --Initial release
procedure etl_aa_persistence_log(jobnumber number, processid varchar2, processname varchar2); ---     11-20-2025  WGRIFFITH2  --Initial release
end load_aa_etl_ret;
/

create or replace package body load_aa_etl_ret is

procedure etl_aa_course_sections_log(jobnumber number, processid varchar2, processname varchar2) is 
--
-- PURPOSE: Builds a daily, point-in-time snapshot of course section enrollment counts and credit-hour totals for each academic year to support accurate section-level reporting by campus, level, college, and part-of-term.
--
-- TABLE: utl_d_aa.course_sections_log
--
-- UNIQUE INDEX: TERM_CODE, CRN
--
-- CONDITIONS:
-- Processes one academic year (AIDY_CODE) at a time, based on financial aid processing year (FA_PROC_YEAR) from zbtm.terms_by_group_v.
-- Uses only Standard and Medical terms (GROUP_CODE in 'STD', 'MED') and excludes Winter terms (SEMESTER <> 'WIN') when determining which terms are in-scope.
-- Limits academic years considered to those whose timeframe has started (TERM START_DATE - 90 < SYSDATE) and are not too far in the past (TERM END_DATE + 6 years > SYSDATE).
-- For each eligible academic year, sets an effective course-attribute term as the last term of that academic year (EFFECTIVE_TERM_CODE = MAX TERM_CODE for the year among STD/MED, non-WIN terms).
-- Sets the processing timeframe start date to 90 days before the earliest term start date in the academic year, and sets the timeframe end date to the latest term end date in the following year (AIDY_CODE + 101) among STD/MED, non-WIN terms.
-- Generates daily report timestamps at 11:59:00 PM for each day in the timeframe and an expiration timestamp one second earlier (11:58:59 PM).
-- Runs only for completed days (no processing for the current day) and only within the last 7 days to recover missed refreshes.
-- Stops generating daily timestamps once the timeframe end date is reached.
-- Prevents re-processing of already completed days per academic year by comparing each candidate day to the latest previously processed FROM_DATE in utl_d_aa.course_sections_log for that ACAD_YEAR.
-- Builds source enrollment activity from saturn.sfrstca using only BASE source rows (SFRSTCA_SOURCE_CDE = 'BASE') and only activity on or before the daily report timestamp (SFRSTCA_RSTS_DATE <= REPORT_TIMESTAMP).
-- Includes only enrollments tied to in-scope terms by joining sfrstca to zbtm.terms_by_group_v with filters for STD/MED terms and the requested academic year (FA_PROC_YEAR = AIDY_CODE).
-- For each student, term, and CRN, keeps only the most recent SFRSTCA record by selecting the highest sequence number (ROW_NUMBER() over PIDM/TERM/CRN ordered by SEQ_NUMBER desc = 1).
-- Includes only enrollment statuses marked as included in section enrollment by joining saturn.stvrsts and requiring STVRSTS_INCL_SECT_ENRL = 'Y'.
-- Includes only course sections found in saturn.ssbsect for the matching term and CRN.
-- Excludes specific placeholder/service section subjects by removing sections where SSBSECT_SUBJ_CODE is 'NEWS' or 'CSER'.
-- Includes only university-eligible student levels by joining zsaturn.szrlevl on the student level from SFRSTCA and requiring SZRLEVL_IS_UNIV = 'Y'.
-- Determines the course college (COLL_CODE) from the latest effective saturn.scbcrse record as-of the effective term (SCBCRSE_EFF_TERM <= EFFECTIVE_TERM_CODE), selecting one row per subject/course number using ROW_NUMBER() ordered by effective term descending.
-- Determines the course level (LEVL_CODE) as the highest/most appropriate level from saturn.scrlevl as-of the effective term (SCRLEVL_EFF_TERM <= EFFECTIVE_TERM_CODE), selecting one row per subject/course number using ROW_NUMBER() ordered by effective term descending, program order descending, then level code descending.
-- If no course level is found, defaults the output level to '00'.
-- Restricts the snapshot population to students who are financially checked-in for the term/day by joining dm_person.fci_d__01 where REPORT_NUMBER is within the FCI numeric date range (REPORT_NUMBER >= FCI_FROM_DATE and REPORT_NUMBER < FCI_TO_DATE) and FCI_STATUS = 'Y'.
-- Excludes students flagged as deceased at the report timestamp by left joining utl_d_aim.szriden and removing rows where DEAD_IND = 'Y' is active during REPORT_TIMESTAMP.
-- Excludes students with active financial-aid fraud-related holds at the report timestamp by left joining rorhold for hold codes ('FC','FD','FO','EH','FI','FY','FF') active during REPORT_TIMESTAMP.
-- Produces one summarized row per course section (CRN + TERM_CODE) with section attributes (campus, part-of-term, subject, course number, sequence, group_code, semester) and the academic year code (ACAD_YEAR = AIDY_CODE).
-- Sets REG_DATE to the earliest enrollment status date observed for the section (MIN SFRSTCA_RSTS_DATE) within the snapshot timing.
-- Calculates SEATS as the distinct count of students enrolled in the section (COUNT(DISTINCT PIDM)), including enrollments with zero credit hours.
-- Calculates HOURS as the total credit hours summed across enrolled students (SUM CREDIT_HR).
-- Calculates campus hour splits using the section campus code: RES_HOURS sums hours where CAMP_CODE = 'R', and LUO_HOURS sums hours where CAMP_CODE = 'D'.
-- Calculates AU_HOURS as hours associated with enrollment statuses flagged as not included in section enrollment (STVRSTS_INCL_SECT_ENRL = 'N').
-- Calculates part-of-term hour buckets based on PTRM_CODE: A_HOURS for '1A', B_HOURS for '1B', C_HOURS for '1C', D_HOURS for '1D', J_HOURS for '1J', and R_HOURS for 'R'.
-- Calculates WD_HOURS as hours associated with withdrawal-indicated statuses (STVRSTS_WITHDRAW_IND = 'Y').
-- Uses an MD5 row hash of the output business fields to detect change between the computed source snapshot and the existing active target row.
-- Compares the computed source snapshot to the existing active record in utl_d_aa.course_sections_log for the same TERM_CODE and CRN where TO_DATE = 2099-12-31 to classify each row as NEW, CHANGE, or EXPIRE.
-- Expires existing active rows (for CHANGE or EXPIRE) by setting TO_DATE to the daily EXPIRATION_DATE (one second before the day’s REPORT_TIMESTAMP) for matching TERM_CODE and CRN.
-- Inserts new active rows (for NEW or CHANGE) with FROM_DATE = the daily REPORT_TIMESTAMP and TO_DATE = 2099-12-31 to represent the current snapshot as-of that day.
-- Processes rows in batches (up to 200,000 rows per fetch) while iterating day-by-day within each academic year timeframe.
--
-- URL: N/A
--
--DECLARE
v_etl_date  DATE := SYSDATE;
v_msg       VARCHAR2(2000);
v_instance  VARCHAR2(50) := upper('ALL'); -- inst from the jams job; used for determining instance
v_partition NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_row_max   NUMBER := 200000; -- max number of rows to be processed at one time
v_count     NUMBER := 0;
v_job_id    VARCHAR2(32);
v_proc      VARCHAR2(100) := 'etl_aa_course_sections_log';
-- cursors
CURSOR c_terms IS
SELECT dates.acad_year,
       dates.timeframe_current_term AS effective_term_code,
       dates.report_number,
       dates.report_timestamp,
       dates.expiration_date
  FROM utl_d_aa.acad_year_dates dates
  LEFT JOIN (SELECT acad_year,
                    MAX(from_date) AS report_date
               FROM utl_d_aa.course_sections_log
              GROUP BY acad_year) tgt
    ON tgt.acad_year = dates.acad_year
 WHERE dates.report_timestamp >= SYSDATE - 3 -- run overlap just in case of weekends/fails, but only n-1 is needed normally
   AND dates.group_code = 'STD' --only need standard group_code
   AND (tgt.report_date IS NULL OR dates.report_date > tgt.report_date)
 ORDER BY dates.acad_year        ASC,
          dates.report_timestamp ASC;
CURSOR c1(v_acad_year           VARCHAR,
          v_effective_term_code VARCHAR,
          v_report_number       NUMBER,
          v_report_timestamp    DATE,
          v_expiration_date     DATE) IS
SELECT CASE
       WHEN src.row_hash IS NOT NULL
            AND tgt.row_hash IS NULL THEN
        'NEW' -- new record to source, add it
       WHEN src.row_hash <> tgt.row_hash THEN
        'CHANGE' -- record exists but changed, expire old row and add new row
       WHEN src.row_hash IS NULL
            AND tgt.row_hash IS NOT NULL THEN
        'EXPIRE' -- record no longer exists on the source data, expire old row and **do not** add new row
       END AS control_state,
       nvl(src.row_hash, tgt.row_hash) AS row_hash,
       nvl(src.crn, tgt.crn) AS crn,
       nvl(src.term_code, tgt.term_code) AS term_code,
       src.start_date,
       src.end_date,
       src.camp_code,
       src.levl_code,
       src.coll_code,
       src.ptrm_code,
       src.subj_code,
       src.crse_numb,
       src.seq_numb,
       src.group_code,
       src.semester,
       src.acad_year,
       src.reg_date,
       src.seats,
       src.hours,
       src.res_hours,
       src.luo_hours,
       src.au_hours,
       src.a_hours,
       src.b_hours,
       src.c_hours,
       src.d_hours,
       src.j_hours,
       src.r_hours,
       src.wd_hours
  FROM (
       -- Source build with analytics & deterministic picks
       -- Combine SFRSTCA with TERMS early (critical!)
       -- Remove correlated subqueries from main query
       WITH sfrstca_terms AS (SELECT /*+ MATERIALIZE */
                               sfrstca_crn, -- needed downstream
                               sfrstca_term_code, -- needed downstream
                               sfrstca_pidm, -- for COUNT(DISTINCT pidm)
                               sfrstca_rsts_code, -- for join to STVRSTS
                               sfrstca_credit_hr, -- for hour sums
                               sfrstca_rsts_date, -- for MIN(reg_date)
                               sfrstca_levl_code, -- for join to SZRLEVL
                               start_date, -- carry TERMS attrs to eliminate re-join
                               end_date, -- carry TERMS attrs to eliminate re-join
                               group_code, -- carry TERMS attrs to eliminate re-join
                               semester -- carry TERMS attrs to eliminate re-join
                                FROM (SELECT s.sfrstca_crn,
                                             s.sfrstca_term_code,
                                             s.sfrstca_pidm,
                                             s.sfrstca_rsts_code,
                                             s.sfrstca_credit_hr,
                                             s.sfrstca_rsts_date,
                                             s.sfrstca_seq_number,
                                             s.sfrstca_levl_code,
                                             t.start_date AS start_date,
                                             t.end_date AS end_date,
                                             t.group_code AS group_code,
                                             t.semester AS semester,
                                             row_number() over(PARTITION BY s.sfrstca_pidm, s.sfrstca_term_code, s.sfrstca_crn ORDER BY s.sfrstca_seq_number DESC) AS ranking
                                        FROM saturn.sfrstca s
                                        JOIN zbtm.terms_by_group_v t
                                          ON t.term_code = s.sfrstca_term_code
                                         AND t.group_code IN ('STD', 'MED') -- iso just these terms; **do not remove this filter or join**                  
                                         AND t.fa_proc_year = v_acad_year -- get all terms for the year
                                       WHERE s.sfrstca_source_cde = 'BASE'
                                         AND s.sfrstca_rsts_date <= v_report_timestamp)
                               WHERE ranking = 1), --
       -- Latest SCBCRSE effective record as-of v_effective_term_code
       scbcrse_eff AS (SELECT /*+ MATERIALIZE */
                        subq.scbcrse_subj_code,
                        subq.scbcrse_crse_numb,
                        subq.scbcrse_coll_code
                         FROM (SELECT c.scbcrse_subj_code,
                                      c.scbcrse_crse_numb,
                                      c.scbcrse_coll_code,
                                      row_number() over(PARTITION BY c.scbcrse_subj_code, c.scbcrse_crse_numb ORDER BY c.scbcrse_eff_term DESC) ranking
                                 FROM saturn.scbcrse c
                                WHERE c.scbcrse_eff_term <= v_effective_term_code) subq
                        WHERE subq.ranking = 1), --
       -- getting the highest course section level using scrlevl & szrlevl (deterministic ROW_NUMBER)
       clvl AS (SELECT /*+ MATERIALIZE */
                 subj_code,
                 crse_numb,
                 levl_code
                  FROM (SELECT l.scrlevl_subj_code AS subj_code,
                               l.scrlevl_crse_numb AS crse_numb,
                               l.scrlevl_levl_code AS levl_code,
                               row_number() over(PARTITION BY l.scrlevl_subj_code, l.scrlevl_crse_numb ORDER BY l.scrlevl_eff_term DESC, z.szrlevl_prog_order DESC, l.scrlevl_levl_code DESC) ranking
                          FROM saturn.scrlevl l
                          JOIN zsaturn.szrlevl z
                            ON z.szrlevl_levl_code = l.scrlevl_levl_code
                         WHERE l.scrlevl_eff_term <= v_effective_term_code)
                 WHERE ranking = 1), --
       sr AS (SELECT st.sfrstca_crn AS crn, -- course reg number
                     st.sfrstca_term_code AS term_code, -- should be the variable hard coded and NOT pulled from sfrstca; **there should be no group by**
                     st.start_date, -- semester start date
                     st.end_date, -- semester end date 
                     sct.ssbsect_camp_code AS camp_code,
                     nvl(cl.levl_code, '00') AS levl_code, -- if level NULL, use the standard filler of '00' that exists in zsaturn.szrlevl
                     cr.scbcrse_coll_code AS coll_code,
                     sct.ssbsect_ptrm_code AS ptrm_code,
                     sct.ssbsect_subj_code AS subj_code,
                     sct.ssbsect_crse_numb AS crse_numb,
                     sct.ssbsect_seq_numb AS seq_numb,
                     st.group_code, -- standard or med; should be the variable hard coded
                     st.semester, -- semester type code; should be the variable hard coded
                     v_acad_year AS acad_year, -- should be the variable hard coded
                     MIN(st.sfrstca_rsts_date) AS reg_date, -- registration date that triggers reg change; must be MIN
                     -- Term seat and hour calculations
                     nvl(COUNT(DISTINCT st.sfrstca_pidm), 0) AS seats, -- counts up unique number of students enrolled including zero credit hour courses
                     nvl(SUM(st.sfrstca_credit_hr), 0) AS hours, -- total of hours for term
                     nvl(SUM(CASE
                             WHEN sct.ssbsect_camp_code = 'R' THEN
                              st.sfrstca_credit_hr
                             END), 0) AS res_hours, -- resident course hours
                     nvl(SUM(CASE
                             WHEN sct.ssbsect_camp_code = 'D' THEN
                              st.sfrstca_credit_hr
                             END), 0) AS luo_hours, -- online course hours
                     nvl(SUM(CASE
                             WHEN rsts.stvrsts_incl_sect_enrl = 'N' THEN
                              st.sfrstca_credit_hr
                             END), 0) AS au_hours, -- audit course hours
                     nvl(SUM(CASE
                             WHEN sct.ssbsect_ptrm_code = '1A' THEN
                              st.sfrstca_credit_hr
                             END), 0) AS a_hours, -- ptrm_code is part of term or sub-term
                     nvl(SUM(CASE
                             WHEN sct.ssbsect_ptrm_code = '1B' THEN
                              st.sfrstca_credit_hr
                             END), 0) AS b_hours,
                     nvl(SUM(CASE
                             WHEN sct.ssbsect_ptrm_code = '1C' THEN
                              st.sfrstca_credit_hr
                             END), 0) AS c_hours,
                     nvl(SUM(CASE
                             WHEN sct.ssbsect_ptrm_code = '1D' THEN
                              st.sfrstca_credit_hr
                             END), 0) AS d_hours,
                     nvl(SUM(CASE
                             WHEN sct.ssbsect_ptrm_code = '1J' THEN
                              st.sfrstca_credit_hr
                             END), 0) AS j_hours,
                     nvl(SUM(CASE
                             WHEN sct.ssbsect_ptrm_code = 'R' THEN
                              st.sfrstca_credit_hr
                             END), 0) AS r_hours,
                     nvl(SUM(CASE
                             WHEN rsts.stvrsts_withdraw_ind = 'Y' THEN
                              st.sfrstca_credit_hr
                             END), 0) AS wd_hours
              -- start with course related tables to get min reg date, hours and seats data; using SFRSTCA because rolling courses changes the SFRSTCR dates because Banner recalculates 
              -- IMPORTANT: we ARE looking for ALL enrollments - including zero (0) credit hours
                FROM sfrstca_terms st
                JOIN saturn.stvrsts rsts
                  ON rsts.stvrsts_code = st.sfrstca_rsts_code -- filtering types in the where clause      
                 AND rsts.stvrsts_incl_sect_enrl = 'Y' -- ind that determines valid enrollment which will include courses being audited; this is exclusively used by academics, and for reporting, use the wd_hours fields if you need to exclude these students                  
                JOIN saturn.ssbsect sct
                  ON sct.ssbsect_term_code = st.sfrstca_term_code
                 AND sct.ssbsect_crn = st.sfrstca_crn
                 AND sct.ssbsect_subj_code NOT IN ('NEWS', 'CSER') -- removing new student placeholder courses, Christian service courses 
                JOIN zsaturn.szrlevl -- we still need to evaluate the student level to keep with the enrollment definition
                  ON szrlevl_levl_code = st.sfrstca_levl_code -- must be joining on the course level for this (not program level)
                 AND szrlevl_is_univ = 'Y' -- this indicator INCLUDES ('CT','DR','GR','IN','JD','MD','UG'); INCLUDES LUOA dual enroll
              -- getting the college connection to course 
                LEFT JOIN scbcrse_eff cr
                  ON cr.scbcrse_subj_code = sct.ssbsect_subj_code
                 AND cr.scbcrse_crse_numb = sct.ssbsect_crse_numb
              -- getting the highest course section level using scrlevl & szrlevl
                LEFT JOIN clvl cl
                  ON cl.subj_code = sct.ssbsect_subj_code
                 AND cl.crse_numb = sct.ssbsect_crse_numb
                LEFT JOIN dm_person.fci_d__01 fci
                  ON fci.fci_b_pidm = st.sfrstca_pidm
                 AND fci.fci_b_term_code = st.sfrstca_term_code
                 AND v_report_number >= fci.fci_from_date
                 AND v_report_number < fci.fci_to_date -- do not use between here; the dates for this table is number format (20251113) and that is why we have the var report_date_number
                 AND fci.fci_status = 'Y' -- this indicator means the student is checked-in and NOT withdrawn their financial check-in
                LEFT JOIN utl_d_aim.szriden dead
                  ON dead.szriden_pidm = st.sfrstca_pidm
                 AND v_report_timestamp BETWEEN dead.szriden_from_date AND dead.szriden_to_date
                 AND dead.szriden_dead_ind = 'Y' -- only looking for student's who may have been enrolled in cohort and then death occurred preventing their return
                LEFT JOIN rorhold fin_fraud
                  ON fin_fraud.rorhold_pidm = st.sfrstca_pidm
                 AND fin_fraud.rorhold_hold_code IN ('FC', 'FD', 'FO', 'EH', 'FI', 'FY', 'FF') -- financial aid side fraud ID'ed
                 AND v_report_timestamp BETWEEN fin_fraud.rorhold_from_date AND fin_fraud.rorhold_to_date
               WHERE dead.szriden_pidm IS NULL -- removing deceased from the cohort population
                 AND fin_fraud.rorhold_pidm IS NULL -- removing any financial aid fraudsters
               GROUP BY st.sfrstca_crn,
                        st.sfrstca_term_code,
                        st.start_date, -- semester start date
                        st.end_date, -- semester end date 
                        sct.ssbsect_camp_code,
                        nvl(cl.levl_code, '00'),
                        cr.scbcrse_coll_code,
                        sct.ssbsect_ptrm_code,
                        sct.ssbsect_subj_code,
                        sct.ssbsect_crse_numb,
                        sct.ssbsect_seq_numb,
                        st.group_code,
                        st.semester,
                        v_acad_year)
       SELECT standard_hash(nvl(to_char(crn), '<NULL>') || '#' || nvl(to_char(term_code), '<NULL>') || '#' || nvl(to_char(camp_code), '<NULL>') || '#' || nvl(to_char(levl_code), '<NULL>') || '#' || nvl(to_char(coll_code), '<NULL>') || '#' ||
                            nvl(to_char(ptrm_code), '<NULL>') || '#' || nvl(to_char(subj_code), '<NULL>') || '#' || nvl(to_char(crse_numb), '<NULL>') || '#' || nvl(to_char(seq_numb), '<NULL>') || '#' || nvl(to_char(group_code), '<NULL>') || '#' ||
                            nvl(to_char(semester), '<NULL>') || '#' || nvl(to_char(acad_year), '<NULL>') || '#' || nvl(to_char(reg_date, 'YYYYMMDD'), '<NULL>') || '#' || nvl(to_char(seats), '<NULL>') || '#' || nvl(to_char(hours), '<NULL>') || '#' ||
                            nvl(to_char(res_hours), '<NULL>') || '#' || nvl(to_char(luo_hours), '<NULL>') || '#' || nvl(to_char(au_hours), '<NULL>') || '#' || nvl(to_char(a_hours), '<NULL>') || '#' || nvl(to_char(b_hours), '<NULL>') || '#' ||
                            nvl(to_char(c_hours), '<NULL>') || '#' || nvl(to_char(d_hours), '<NULL>') || '#' || nvl(to_char(j_hours), '<NULL>') || '#' || nvl(to_char(r_hours), '<NULL>') || '#' || nvl(to_char(wd_hours), '<NULL>'), 'MD5') AS row_hash,
              sr.*
         FROM sr) src
       -- for the control state
         FULL JOIN (SELECT *
                      FROM utl_d_aa.course_sections_log
                     WHERE acad_year = v_acad_year
                       AND to_date = DATE '2099-12-31' -- active record; infinity date signifies that they retained enrollment through the term; an expired date means, they did not (and likely were fully dropped from courses)
                    ) tgt
           ON tgt.term_code = src.term_code
          AND tgt.crn = src.crn
        WHERE 1 = 1
             -- <- new record, change record or expire -> --
          AND (((src.row_hash IS NULL AND tgt.row_hash IS NOT NULL) OR (src.row_hash IS NOT NULL AND tgt.row_hash IS NULL)) OR (src.row_hash <> tgt.row_hash));

TYPE rec_input_t IS TABLE OF c1%ROWTYPE;
rec_input rec_input_t;
TYPE index_pointer_t IS TABLE OF PLS_INTEGER;
ttab_dml index_pointer_t := index_pointer_t();
CURSOR cur_idx_dat(schema_ VARCHAR2,
                   table_  VARCHAR2) IS(
SELECT lower(a_idx.owner || '.' || a_idx.index_name) idx
  FROM all_indexes a_idx
 WHERE a_idx.owner = upper(schema_)
   AND a_idx.table_name = upper(table_));
rec_idx_dat cur_idx_dat%ROWTYPE;
TYPE index_pointer_i IS TABLE OF PLS_INTEGER;
insert_dml index_pointer_i := index_pointer_i();
TYPE index_pointer_u IS TABLE OF PLS_INTEGER;
update_dml    index_pointer_u := index_pointer_u();
v_total_count NUMBER := 0;
insert_count  NUMBER := 0;
update_count  NUMBER := 0;
v_elapsed     NUMBER := 0;
-- Added for error tracking on insert
TYPE error_log_t IS TABLE OF VARCHAR2(4000);
error_log error_log_t := error_log_t();
TYPE error_row_hash_t IS TABLE OF VARCHAR2(100);
error_row_hash error_row_hash_t := error_row_hash_t();
BEGIN
-- dbms_output.enable(buffer_size => NULL);
ads_etl.set_parallel_session('Y', 8, 'QUERY'); -- FORALL statements. We must SET to QUERY.
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
--
FOR rec IN c_terms
LOOP
OPEN c1(rec.acad_year, rec.effective_term_code, rec.report_number, rec.report_timestamp, rec.expiration_date);
LOOP
v_count := 0; -- reset count
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || rec.acad_year || ' - ' || rec.report_number || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
FETCH c1 BULK COLLECT
INTO rec_input LIMIT v_row_max;
v_count := rec_input.count;
IF v_count = 0 THEN
dbms_lock.sleep(0.5);
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'SELECT - AIDY ' || rec.acad_year || ' - ' || rec.report_number || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
ELSIF v_count > 0 THEN
dbms_lock.sleep(0.5);
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'SELECT - AIDY ' || rec.acad_year || ' - ' || rec.report_number || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
insert_dml := index_pointer_i();
update_dml := index_pointer_u();
IF rec_input.count > 0 THEN
FOR idx IN 1 .. rec_input.count
LOOP
BEGIN
IF rec_input(idx).control_state IN ('EXPIRE', 'CHANGE') THEN
update_dml.extend; -- expiring changes; must run first
update_dml(update_dml.last) := idx;
END IF;
IF rec_input(idx).control_state IN ('NEW', 'CHANGE') THEN
insert_dml.extend; -- new or changes get a new row 
insert_dml(insert_dml.last) := idx;
END IF;
EXCEPTION
WHEN OTHERS THEN
dbms_lock.sleep(0.5);
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200) || ' exception raised for AIDY ' || rec.acad_year || ' - ' || rec.report_number || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || round(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
CONTINUE;
END;
END LOOP;
END IF;
insert_count := insert_dml.count;
update_count := update_dml.count;
IF update_count > 0 THEN
DECLARE
v_success NUMBER := 0;
BEGIN
FORALL i IN VALUES OF update_dml
SAVE EXCEPTIONS --
UPDATE utl_d_aa.course_sections_log tab SET tab.to_date = rec.expiration_date, -- set to_date to the report timestamp to expire it
tab.activity_date = v_etl_date WHERE tab.term_code = rec_input(i).term_code AND tab.crn = rec_input(i).crn AND tab.to_date = DATE '2099-12-31';
-- If no exception, all succeeded
v_success := SQL%ROWCOUNT;
COMMIT;
dbms_lock.sleep(0.5);
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'UPDATE - AIDY ' || rec.acad_year || ' - ' || rec.report_number || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:SS') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_success; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_success));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_success);
EXCEPTION
WHEN OTHERS THEN
-- Partial success case with SAVE EXCEPTIONS
IF SQL%bulk_exceptions.count > 0 THEN
v_success := update_count - SQL%bulk_exceptions.count;
FOR j IN 1 .. SQL%bulk_exceptions.count
LOOP
error_log.extend;
error_row_hash.extend;
error_log(error_log.last) := 'UPDATE error idx=' || SQL%BULK_EXCEPTIONS(j).error_index || ' code=' || SQL%BULK_EXCEPTIONS(j).error_code || ' msg=' || substr(REPLACE(SQLERRM(-SQL%BULK_EXCEPTIONS(j).error_code), 'ORA', '!!!'), 1, 200);
error_row_hash(error_row_hash.last) := rec_input(update_dml(SQL%BULK_EXCEPTIONS(j).error_index)).row_hash;
END LOOP;
ELSE
v_success := 0;
error_log.extend;
error_log(error_log.last) := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
END IF;
COMMIT; -- commit successful rows
v_total_count := v_total_count + v_success;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
ads_etl.insert_job_log(v_proc, 'ERROR', 'UPDATE batch had errors; successes=' || v_success || ', errors=' || SQL%bulk_exceptions.count, v_instance, v_partition, v_job_id, v_elapsed, v_success);
END;
END IF;
IF insert_count > 0 THEN
DECLARE
v_success NUMBER := 0;
BEGIN
FORALL i IN VALUES OF insert_dml
SAVE EXCEPTIONS INSERT
INTO utl_d_aa.course_sections_log(row_hash, from_date, to_date, activity_date, crn, term_code, start_date, end_date, camp_code, levl_code, coll_code, ptrm_code, subj_code, crse_numb, seq_numb, group_code, semester, acad_year, reg_date, seats, hours, res_hours, luo_hours, au_hours, a_hours, b_hours, c_hours, d_hours, j_hours, r_hours, wd_hours) --
VALUES(rec_input(i).row_hash, rec.report_timestamp, DATE '2099-12-31', -- active record; infinity date signifies that they retained enrollment through the term; an expired date means, they did not (and likely were fully dropped from courses)
       v_etl_date, rec_input(i).crn, rec_input(i).term_code, rec_input(i).start_date, rec_input(i).end_date, rec_input(i).camp_code, rec_input(i).levl_code, rec_input(i).coll_code, rec_input(i).ptrm_code, rec_input(i).subj_code, rec_input(i).crse_numb, rec_input(i).seq_numb, rec_input(i).group_code, rec_input(i).semester, rec_input(i).acad_year, rec_input(i).reg_date, rec_input(i).seats, rec_input(i).hours, rec_input(i).res_hours, rec_input(i).luo_hours, rec_input(i).au_hours, rec_input(i).a_hours, rec_input(i).b_hours, rec_input(i).c_hours, rec_input(i).d_hours, rec_input(i).j_hours, rec_input(i).r_hours, rec_input(i).wd_hours);
v_success := SQL%ROWCOUNT;
COMMIT;
dbms_lock.sleep(0.5);
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - AIDY ' || rec.acad_year || ' - ' || rec.report_number || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_success; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_success));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_success);
EXCEPTION
WHEN OTHERS THEN
IF SQL%bulk_exceptions.count > 0 THEN
FOR j IN 1 .. SQL%bulk_exceptions.count
LOOP
error_log.extend;
error_row_hash.extend;
error_log(error_log.last) := 'INSERT error idx=' || SQL%BULK_EXCEPTIONS(j).error_index || ' code=' || SQL%BULK_EXCEPTIONS(j).error_code || ' msg=' || substr(REPLACE(SQLERRM(-SQL%BULK_EXCEPTIONS(j).error_code), 'ORA', '!!!'), 1, 200);
error_row_hash(error_row_hash.last) := rec_input(insert_dml(SQL%BULK_EXCEPTIONS(j).error_index)).row_hash;
END LOOP;
v_count := insert_count - SQL%bulk_exceptions.count;
ELSE
v_count := 0;
error_log.extend;
error_log(error_log.last) := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
END IF;
COMMIT; -- commit successful rows
v_total_count := v_total_count + v_count;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
ads_etl.insert_job_log(v_proc, 'ERROR', 'INSERT batch had errors; successes=' || v_count || ', errors=' || SQL%bulk_exceptions.count, v_instance, v_partition, v_job_id, v_elapsed, v_count);
END;
END IF;
END IF;
EXIT WHEN(rec_input.count < v_row_max);
END LOOP;
CLOSE c1;
dbms_output.put_line(' --------- ');
END LOOP; -- c_terms
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
-- log any errors
IF error_log.count > 0 THEN
FOR i IN 1 .. error_log.count
LOOP
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(error_log(i), 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
END LOOP;
END IF;
EXCEPTION
WHEN OTHERS THEN
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
ads_etl.set_parallel_session('N'); -- Job is done. Turn parallelism off for this session.
END etl_aa_course_sections_log;

procedure etl_aa_persistence_log(jobnumber number, processid varchar2, processname varchar2) IS
--
-- PURPOSE: Generates daily persistence snapshots showing whether each student graduated, returned, or exited between a cohort term and its designated return term.
--
-- TABLE: utl_d_aa.persistence_log
--
-- UNIQUE INDEX: pidm, cohort_term, return_term
--
-- CONDITIONS:
-- Builds a per-day processing calendar for each cohort term using the next-term window:
--   For Resident (camp_code = 'R'): timeframe_start_date = MIN(next term start_date - 90) across groups STD and MED; timeframe_end_date = MAX(next term end_date) across STD and MED; excludes WIN.
--   For Online/Distance (camp_code = 'D'): timeframe_start_date = MIN(next term start_date - 90) across group STD only; timeframe_end_date = MAX(next term end_date) across STD only; excludes WIN.
-- The next-term code is derived by utl_d_aa.get_next_term_code(cohort_term, camp_code), producing return_term specific to campus.
-- Excludes dummy terms where term_code = '000000'.
-- Excludes winter terms (semester = 'WIN') from both cohort and timeframe derivation.
-- Limits candidate cohort terms to those near-current: terms where (start_date - 90) < SYSDATE and (end_date + 7 years) > SYSDATE.
-- Expands calendar by days via a generator up to 1000 days but restricts to the valid timeframe window per term.
-- Processes only days strictly before today (no current-day or future processing).
-- Limits daily processing to the trailing 7 days to catch missed refreshes.
-- Prevents reprocessing previously completed days by skipping any date that is less than or equal to the maximum from_date already written for that cohort_term in persistence_log.
-- For each selected day, sets from_date = report_timestamp at 23:59:00 of that day and uses expiration_date = 23:58:59 to close prior active rows.
-- Executes separately for Resident ('R') and Online ('D'), yielding campus-specific persistence windows.
-- Cohort selection pulls one record per enrolled student from utl_d_aa.enrollments_log where:
--   term_code = cohort_term,
--   camp_code = the campus being processed,
--   to_date = 2099-12-31 (the enrollment remained active through the cohort term).
-- Captures cohort attributes for comparison on return: levl_code, coll_code, degc_code, majr_code, acat_code, and camp_code.
-- Graduation identification joins cohort students to utl_d_aa.retention_grads within the persistence window where:
--   term_code_grad >= cohort_term and term_code_grad < return_term,
--   and either (degc_code <> 'MDV' and acat_code >= cohort acat_code) or (degc_code = 'MDV' and degc_code = cohort degc_code) to implement MDV degree-in-passing rules and non-MDV level thresholds.
-- Among all qualifying awards per student in the window, ranks by highest acat_code then most recent grad_date (ties resolved by ranking) and keeps only the top-ranked award.
-- Sets graduated = 1 if a qualifying ranked award exists for the student; otherwise 0.
-- Return identification checks utl_d_aa.enrollments_log for the derived return_term where:
--   ret.pidm = cohort.pidm,
--   ret.term_code = return_term,
--   the snapshot report_timestamp falls within the ret record’s active window (report_timestamp between ret.from_date and ret.to_date),
--   and the student did not graduate in the window (graduates are intentionally excluded from counting as returned by keeping the graduation filter in the JOIN and not in the WHERE).
-- Sets returned = 1 when a qualifying return record is found; otherwise 0.
-- Compares return attributes to the cohort to flag whether the student returned in the same unit:
--   return_camp = 1 if return camp_code equals cohort camp_code; else 0.
--   return_levl = 1 if return levl_code equals cohort levl_code; else 0.
--   return_coll = 1 if return coll_code equals cohort coll_code; else 0.
--   return_degr = 1 if return degc_code equals cohort degc_code; else 0.
--   return_majr = 1 if return majr_code equals cohort majr_code; else 0.
-- Captures ret.reg_date and ret.fci_date from the return-term enrollment record to represent earliest registration and first-course-interaction timing used in persistence reporting.
-- Computes a row_hash (MD5) across pidm, cohort_term, return_term, reg_date, fci_date, graduated, returned, return_camp, return_levl, return_coll, return_degr, return_majr to detect any change in persistence attributes.
-- Compares the current-day source snapshot to existing active rows in utl_d_aa.persistence_log (to_date = 2099-12-31) for the same pidm, cohort_term, return_term:
--   NEW when the source exists and no active target row exists.
--   CHANGE when both exist but row_hash differs, indicating one or more attribute changes.
--   EXPIRE when the active target exists but no current source row exists for that student and key.
-- Applies a slowly changing dimension type 2 pattern:
--   For EXPIRE and CHANGE, closes the prior active row by setting to_date = expiration_date (23:58:59 of the same day).
--   For NEW and CHANGE, inserts a new active row with from_date = report_timestamp (23:59:00 of the day) and to_date = 2099-12-31.
-- Processes records in batches up to 200,000 rows per fetch for each cohort-date combination.
-- FULL JOIN logic between source and target ensures detection of both newly appearing and disappearing students relative to the prior active snapshot.
--
-- DECLARE
v_etl_date  DATE := SYSDATE;
v_msg       VARCHAR2(2000);
v_instance  VARCHAR2(50) := upper('ALL'); -- inst from the jams job; used for determining instance
v_partition NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_row_max   NUMBER := 200000; -- max number of rows to be processed at one time
v_count     NUMBER := 0;
v_job_id    VARCHAR2(32);
v_proc      VARCHAR2(100) := 'etl_aa_persistence_log';
-- cursors
CURSOR c_terms IS
SELECT dates.cohort_term      AS cohort_term,
       dates.return_term      AS return_term,
       dates.camp_code,
       dates.report_number,
       dates.report_timestamp,
       dates.expiration_date
  FROM ads_etl.get_term_dates(v_acad_year => NULL, v_days_back => 7, v_camp_code => 'R', v_extend_end_date => 365) dates -- search for RES; -- continue running v_extend_end_date days after the year is over to capture any audited changes (death/fraud/registrar)
  LEFT JOIN (SELECT cohort_term,
                    return_term,
                    MAX(to_date) AS report_date
               FROM utl_d_aa.persistence_log
              WHERE to_date < DATE '2099-12-31'
              GROUP BY cohort_term,
                       return_term) tgt
    ON tgt.cohort_term = dates.cohort_term -- join on cohort_term AND return_term to detect campus
   AND tgt.return_term = dates.return_term
 WHERE tgt.report_date IS NULL
    OR trunc(dates.report_timestamp) > trunc(tgt.report_date)
UNION
SELECT dates.cohort_term      AS cohort_term,
       dates.return_term      AS return_term,
       dates.camp_code,
       dates.report_number,
       dates.report_timestamp,
       dates.expiration_date
  FROM ads_etl.get_term_dates(v_acad_year => NULL, v_days_back => 7, v_camp_code => 'D', v_extend_end_date => 365) dates -- search for LUO; -- continue running v_extend_end_date days after the year is over to capture any audited changes (death/fraud/registrar)
  LEFT JOIN (SELECT cohort_term,
                    return_term,
                    MAX(to_date) AS report_date
               FROM utl_d_aa.persistence_log
              WHERE to_date < DATE '2099-12-31'
              GROUP BY cohort_term,
                       return_term) tgt
    ON tgt.cohort_term = dates.cohort_term -- join on cohort_term AND return_term to detect campus
   AND tgt.return_term = dates.return_term
 WHERE tgt.report_date IS NULL
    OR trunc(dates.report_timestamp) > trunc(tgt.report_date)
 ORDER BY cohort_term      ASC,
          return_term      ASC,
          report_timestamp ASC;
CURSOR c1(v_cohort_term      VARCHAR,
          v_return_term      VARCHAR,
          v_camp_code        VARCHAR,
          v_report_number    NUMBER,
          v_report_timestamp DATE,
          v_expiration_date  DATE) IS
-- CTE to define the cohort of students for the given term
WITH cohort AS
 (SELECT /*+ MATERIALIZE */
   elog.pidm,
   elog.term_code  AS cohort_term,
   v_return_term   AS return_term,
   elog.start_date,
   elog.group_code,
   elog.semester,
   elog.acad_year,
   elog.camp_code,
   elog.levl_code,
   elog.coll_code,
   elog.degc_code,
   elog.majr_code,
   elog.acat_code
    FROM utl_d_aa.enrollments_log elog
   WHERE elog.term_code = v_cohort_term
     AND elog.camp_code = v_camp_code -- gotta get campus for persistence
     AND elog.to_date = DATE '2099-12-31' -- active record at the end; infinity date signifies that they retained enrollment through the term; an expired date means, they did not (and likely were fully dropped from courses)
  ),
grads AS
 (SELECT /*+ MATERIALIZE */
   rg.pidm,
   rank() over(PARTITION BY rg.pidm ORDER BY rg.acat_code DESC, rg.grad_date DESC, rownum) ranking -- we only want to get one degree per student within the timeframe; highest and last award of the timeframe
    FROM utl_d_aa.retention_grads rg
    JOIN cohort elog
      ON elog.pidm = rg.pidm
     AND rg.term_code_grad >= elog.cohort_term -- the graduation term has to be >= to the last enrolled term of the student; 
     AND rg.term_code_grad < elog.return_term -- before the retention term
     AND ((rg.acat_code >= elog.acat_code AND rg.degc_code <> 'MDV') -- if not MDV, the degree code has to be >= the enrollment degree code
         OR (rg.degc_code = 'MDV' AND rg.degc_code = elog.degc_code))) -- if MDV, degree in passing in effect, we want to count this as an awarded degree
SELECT CASE
       WHEN src.row_hash IS NOT NULL
            AND tgt.row_hash IS NULL THEN
        'NEW' -- New record in source, add it
       WHEN src.row_hash <> tgt.row_hash THEN
        'CHANGE' -- Record exists but changed, expire old row and add new row
       WHEN src.row_hash IS NULL
            AND tgt.row_hash IS NOT NULL THEN
        'EXPIRE' -- Record no longer exists in source, expire old row and do NOT add new row
       END AS control_state,
       nvl(src.row_hash, tgt.row_hash) AS row_hash,
       nvl(src.pidm, tgt.pidm) AS pidm,
       nvl(src.cohort_term, tgt.cohort_term) AS cohort_term,
       nvl(src.return_term, tgt.return_term) AS return_term,
       src.group_code,
       src.reg_date,
       src.fci_date,
       src.graduated,
       src.returned,
       src.return_camp,
       src.return_levl,
       src.return_coll,
       src.return_degr,
       src.return_majr
  FROM (SELECT standard_hash(nvl(to_char(pidm), '<NULL>') || '#' || nvl(to_char(cohort_term), '<NULL>') || '#' || nvl(to_char(return_term), '<NULL>') || '#' || nvl(to_char(reg_date, 'YYYYMMDD'), '<NULL>') || '#' ||
                             nvl(to_char(fci_date, 'YYYYMMDD'), '<NULL>') || '#' || nvl(to_char(graduated), '<NULL>') || '#' || nvl(to_char(returned), '<NULL>') || '#' || nvl(to_char(return_camp), '<NULL>') || '#' ||
                             nvl(to_char(return_levl), '<NULL>') || '#' || nvl(to_char(return_coll), '<NULL>') || '#' || nvl(to_char(return_degr), '<NULL>') || '#' || nvl(to_char(return_majr), '<NULL>'), 'MD5') AS row_hash,
               sr.pidm,
               sr.cohort_term,
               sr.return_term,
               sr.group_code,
               sr.reg_date,
               sr.fci_date,
               sr.graduated,
               sr.returned,
               sr.return_camp,
               sr.return_levl,
               sr.return_coll,
               sr.return_degr,
               sr.return_majr
          FROM (SELECT elog.pidm,
                       elog.cohort_term,
                       elog.return_term,
                       elog.group_code,
                       ret.reg_date, -- based on the ranking the ret subquery, we get the earliest sfrstca_rsts_date found 
                       ret.fci_date,
                       CASE
                       WHEN grads.pidm IS NOT NULL THEN
                        1
                       ELSE
                        0
                       END AS graduated,
                       CASE
                       WHEN ret.pidm IS NOT NULL THEN
                        1
                       ELSE
                        0
                       END AS returned,
                       CASE
                       WHEN ret.pidm IS NOT NULL
                            AND ret.camp_code = elog.camp_code THEN
                        1
                       ELSE
                        0
                       END AS return_camp,
                       CASE
                       WHEN ret.pidm IS NOT NULL
                            AND ret.levl_code = elog.levl_code THEN
                        1
                       ELSE
                        0
                       END AS return_levl,
                       CASE
                       WHEN ret.pidm IS NOT NULL
                            AND ret.coll_code = elog.coll_code THEN
                        1
                       ELSE
                        0
                       END AS return_coll,
                       CASE
                       WHEN ret.pidm IS NOT NULL
                            AND ret.degc_code = elog.degc_code THEN
                        1
                       ELSE
                        0
                       END AS return_degr,
                       CASE
                       WHEN ret.pidm IS NOT NULL
                            AND ret.majr_code = elog.majr_code THEN
                        1
                       ELSE
                        0
                       END AS return_majr,
                       v_etl_date AS activity_date
                  FROM cohort elog
                -- check to see if the student graduated after the cohort term
                  LEFT JOIN grads -- this is a strict definition coming from the PDB / BOT definition. no checks here for graduation on level or degc, etc.
                    ON grads.pidm = elog.pidm
                   AND grads.ranking = 1 -- returning the "best" awarded degree
                -- check to see if they came back the next term; 
                  LEFT JOIN utl_d_aa.enrollments_log ret
                    ON ret.pidm = elog.pidm
                   AND ret.term_code = v_return_term
                   AND v_report_timestamp BETWEEN ret.from_date AND ret.to_date
                   AND grads.pidm IS NULL -- **do not put this line in the where clause;** we are removing grads from the return count; do not move this to the where clause. needs to be here on the ret join; **KEEP THIS ON THE LEFT JOIN and NOT THE WHERE CLAUSE**
                ) sr) src
-- for the control state
  FULL JOIN (SELECT tgt.*
               FROM utl_d_aa.persistence_log tgt
               JOIN cohort elog
                 ON elog.cohort_term = tgt.cohort_term
                AND elog.return_term = tgt.return_term
                AND elog.pidm = tgt.pidm
              WHERE tgt.to_date = DATE '2099-12-31' -- active record; infinity date signifies that they retained enrollment through the term; an expired date means, they did not (and likely were fully dropped from courses)
             ) tgt
    ON tgt.cohort_term = src.cohort_term
   AND tgt.return_term = src.return_term
   AND tgt.pidm = src.pidm
 WHERE 1 = 1
      -- <- new record, change record or expire -> --
   AND (((src.row_hash IS NULL AND tgt.row_hash IS NOT NULL) OR (src.row_hash IS NOT NULL AND tgt.row_hash IS NULL)) OR (src.row_hash <> tgt.row_hash));
TYPE rec_input_t IS TABLE OF c1%ROWTYPE;
rec_input rec_input_t;
TYPE index_pointer_t IS TABLE OF PLS_INTEGER;
ttab_dml index_pointer_t := index_pointer_t();
CURSOR cur_idx_dat(schema_ VARCHAR2,
                   table_  VARCHAR2) IS(
SELECT lower(a_idx.owner || '.' || a_idx.index_name) idx
  FROM all_indexes a_idx
 WHERE a_idx.owner = upper(schema_)
   AND a_idx.table_name = upper(table_));
rec_idx_dat cur_idx_dat%ROWTYPE;
TYPE index_pointer_i IS TABLE OF PLS_INTEGER;
insert_dml index_pointer_i := index_pointer_i();
TYPE index_pointer_u IS TABLE OF PLS_INTEGER;
update_dml    index_pointer_u := index_pointer_u();
v_total_count NUMBER := 0;
insert_count  NUMBER := 0;
update_count  NUMBER := 0;
v_elapsed     NUMBER := 0;
-- Added for error tracking on insert
TYPE error_log_t IS TABLE OF VARCHAR2(4000);
error_log error_log_t := error_log_t();
TYPE error_row_hash_t IS TABLE OF VARCHAR2(100);
error_row_hash error_row_hash_t := error_row_hash_t();
BEGIN
-- dbms_output.enable(buffer_size => NULL);
--
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
--
FOR rec IN c_terms
LOOP
OPEN c1(rec.cohort_term, rec.return_term, rec.camp_code, rec.report_number, rec.report_timestamp, rec.expiration_date);
LOOP
v_etl_date := SYSDATE; -- reset timestamp for tracking
v_count    := 0; -- reset count
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || rec.return_term || ' - ' || rec.report_number || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
FETCH c1 BULK COLLECT
INTO rec_input LIMIT v_row_max;
v_count := rec_input.count;
IF v_count = 0 THEN
dbms_lock.sleep(0.5);
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'SELECT - TERM ' || rec.return_term || ' - ' || rec.report_number || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
ELSIF v_count > 0 THEN
dbms_lock.sleep(0.5);
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'SELECT - TERM ' || rec.return_term || ' - ' || rec.report_number || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
insert_dml := index_pointer_i();
update_dml := index_pointer_u();
IF rec_input.count > 0 THEN
FOR idx IN 1 .. rec_input.count
LOOP
BEGIN
IF rec_input(idx).control_state IN ('EXPIRE', 'CHANGE') THEN
update_dml.extend; -- expiring changes; must run first
update_dml(update_dml.last) := idx;
END IF;
IF rec_input(idx).control_state IN ('NEW', 'CHANGE') THEN
insert_dml.extend; -- new or changes get a new row 
insert_dml(insert_dml.last) := idx;
END IF;
EXCEPTION
WHEN OTHERS THEN
dbms_lock.sleep(0.5);
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200) || ' exception raised for TERM ' || rec.return_term || ' - ' || rec.report_number || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || round(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
CONTINUE;
END;
END LOOP;
END IF;
insert_count := insert_dml.count;
update_count := update_dml.count;
IF update_count > 0 THEN
FORALL i IN VALUES OF update_dml
UPDATE utl_d_aa.persistence_log tab
   SET tab.to_date       = rec.expiration_date, -- set to_date to the report timestamp to expire it
       tab.activity_date = v_etl_date
 WHERE tab.cohort_term = rec_input(i).cohort_term
   AND tab.return_term = rec_input(i).return_term
   AND tab.pidm = rec_input(i).pidm
   AND tab.to_date = DATE '2099-12-31';
v_count := SQL%ROWCOUNT;
COMMIT;
dbms_lock.sleep(0.5);
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'UPDATE - TERM ' || rec.return_term || ' - ' || rec.report_number || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
END IF;
IF insert_dml.count > 0 THEN
FORALL i IN VALUES OF insert_dml
INSERT INTO utl_d_aa.persistence_log
(row_hash,
 from_date,
 to_date,
 activity_date,
 pidm,
 cohort_term,
 return_term,
 group_code,
 reg_date,
 fci_date,
 graduated,
 returned,
 return_camp,
 return_levl,
 return_coll,
 return_degr,
 return_majr)
VALUES
(rec_input(i).row_hash,
 rec.report_timestamp,
 DATE '2099-12-31', -- active record; infinity date signifies that they retained enrollment through the term; an expired date means, they did not (and likely were fully dropped from courses)
 v_etl_date,
 rec_input(i).pidm,
 rec_input(i).cohort_term,
 rec_input(i).return_term,
 rec_input(i).group_code,
 rec_input(i).reg_date,
 rec_input(i).fci_date,
 rec_input(i).graduated,
 rec_input(i).returned,
 rec_input(i).return_camp,
 rec_input(i).return_levl,
 rec_input(i).return_coll,
 rec_input(i).return_degr,
 rec_input(i).return_majr);
v_count := SQL%ROWCOUNT;
COMMIT;
dbms_lock.sleep(0.5);
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - TERM ' || rec.return_term || ' - ' || rec.report_number || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
END IF;
END IF;
EXIT WHEN(rec_input.count < v_row_max);
END LOOP;
CLOSE c1;
dbms_output.put_line(' --------- ');
END LOOP; -- c_terms
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
-- log any errors
IF error_log.count > 0 THEN
FOR i IN 1 .. error_log.count
LOOP
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(error_log(i), 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
END LOOP;
END IF;
EXCEPTION
WHEN OTHERS THEN
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
END etl_aa_persistence_log;

procedure etl_aa_retention_log(jobnumber number, processid varchar2, processname varchar2) IS
-- =============================================================================
-- PURPOSE: Builds and maintains yearly student retention records by comparing current cohort enrollment snapshots to existing retention_log rows, expiring changed records and inserting new active retention rows.
--
-- TARGET(S): utl_d_aa.retention_log
--
-- UNIQUE KEY / INDEX: ROW_HASH, FROM_DATE, TO_DATE (RETENTION_UQ_ROW_HASH_DATE)
--
-- BUSINESS LOGIC & CONDITIONS:
-- - Iterates over academic reporting periods returned by ads_etl.get_acad_dates (looks back 7 days and can extend the end date by 365 days).
-- - For each reporting period (cohort_year / return_year / report_timestamp), assembles a source cohort using utl_d_aa.enrollments_log limited to the cohort academic year and excludes 'WIN' semester.
-- - Ranks enrollments per student (pidm) and acad_year to choose the "best" enrollment row active at report_timestamp (row_number() window with priority for rows active on the report timestamp, then most recent from_date, then earliest to_date).
-- - Builds a grads temporary set from utl_d_aa.retention_grads to detect awarded degrees after the cohort year (ranked to pick one degree per pidm), and joins this to the cohort to set graduated flags.
-- - Uses a secondary enrollments_log table-function result (for v_return_year) to detect returns in the following year, excluding graduated students from return counts (LEFT JOIN with grads.pidm IS NULL).
-- - Constructs a deterministic ROW_HASH (MD5 via standard_hash) of business key columns (pidm, group_code, cohort_year, return_year, reg_date, fci_date, graduated, returned, return_camp, return_levl, return_coll, return_degr, return_majr) so source-to-target comparisons can detect NEW, CHANGE, and EXPIRE states.
-- - Performs a FULL JOIN between source and target active rows (target.to_date = DATE '2099-12-31') on cohort_year, return_year and pidm to classify each record as NEW, CHANGE, or EXPIRE:
--   - NEW: present in source, not in target -> INSERT
--   - CHANGE: present in both but row_hash differs -> EXPIRE existing row (update to_date) and INSERT new active row
--   - EXPIRE: present in target, not in source -> expire existing row (update to_date) and do NOT insert a new row
-- - Batches processing using BULK COLLECT from the c1 cursor with LIMIT v_row_max (default 200000) and processes rows in memory-by-chunk.
-- - For each batch:
--   - Builds index lists for UPDATE (EXPIRE/CHANGE) and INSERT (NEW/CHANGE).
--   - Performs FORALL UPDATE ... SAVE EXCEPTIONS to set to_date = rec.expiration_date for expiring rows, restricted to rows with to_date = DATE '2099-12-31'.
--   - Performs FORALL INSERT ... SAVE EXCEPTIONS to insert active rows with to_date = DATE '2099-12-31'.
-- - On SAVE EXCEPTIONS failures (SQL%BULK_EXCEPTIONS):
--   - Maps bulk error indices back to the original rec_input index via the index pointer arrays (insert_dml / update_dml).
--   - Captures error details (error_index, error_code, truncated SQLERRM) and the offending row_hash plus helpful business keys (PIDM, COHORT, RETURN, and constructed FROM_DATE/TO_DATE) into in-memory error_log and error_row_hash collections.
--   - Commits successful rows despite failures; increments overall processed counters by number of successes.
-- - After each batch, logs INFO or ERROR to ADS_ETL job_log via ads_etl.insert_job_log, and on completion iterates error_log to persist each error message as ERROR-level job_log entries so scheduler can mark job failures.
-- - Processing strategy: loop per reporting period, nested loop reading c1 in batches, exit when fetched rows < v_row_max, maintain running totals and per-batch elapsed timing.
--
-- DEPENDENCIES:
-- - Tables/Views: utl_d_aa.retention_log, utl_d_aa.enrollments_log, utl_d_aa.retention_grads
-- - Packages/Functions: ads_etl.get_acad_dates (or ads_etl.get_acad_dates wrapper shown as ads_etl.get_acad_dates), ads_etl.insert_job_log, dbms_lock
-- - Oracle features: FORALL, SAVE EXCEPTIONS, SQL%BULK_EXCEPTIONS, standard_hash(...,'MD5'), window functions (row_number), bulk collect
--
-- CONSTRAINTS & RISKS:
-- - Unique constraint on (ROW_HASH, FROM_DATE, TO_DATE) (RETENTION_UQ_ROW_HASH_DATE) can raise ORA-00001 on INSERT; this implementation captures offending row_hash and business keys for diagnosis.
-- - FORALL ... SAVE EXCEPTIONS can partially commit rows; commits are issued within the loop which can lead to partial state if downstream steps fail—careful review required for transactional consistency.
-- - High-volume memory use: BULK COLLECT LIMIT v_row_max (default 200k) may exhaust PGA/UGA if many wide rows are fetched; tune v_row_max to available memory.
-- - Concurrency/locking risk: UPDATEs set to_date on active rows (to_date = DATE '2099-12-31') and subsequent INSERTs may contend with other processes updating the same target rows; potential row locking or serialization.
-- - Exception logging blocks are defensive; however, any failure in the error-capture logic is swallowed (NULL in inner EXCEPTION), which could hide logging failures—ensure alerts surface when error logging itself fails.
-- - If SQL%BULK_EXCEPTIONS is not populated as expected, some failures are reported as a single generic error row; ensure enough contextual logging is kept to find problematic keys.
-- - Dependent objects (ads_etl package, retention_log indexes) must exist and be accessible with appropriate privileges in the executing schema.
-- =============================================================================
-- DECLARE
v_etl_date  DATE := SYSDATE;
v_msg       VARCHAR2(2000);
v_instance  VARCHAR2(50) := upper('ALL'); -- inst from the jams job; used for determining instance
v_partition NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_row_max   NUMBER := 200000; -- max number of rows to be processed at one time
v_count     NUMBER := 0;
v_job_id    VARCHAR2(32);
v_proc      VARCHAR2(100) := 'etl_aa_retention_log';
-- cursors
CURSOR c_terms IS
SELECT to_char(dates.acad_year - 101) AS cohort_year,
       dates.acad_year AS return_year,
       dates.report_number,
       dates.report_timestamp,
       dates.expiration_date,
       dates.timeframe_start_term
  FROM utl_d_aa.acad_year_dates dates
  LEFT JOIN (SELECT return_year,
                    MAX(to_date) AS report_date
               FROM utl_d_aa.retention_log
              WHERE to_date < DATE '2099-12-31'
              GROUP BY return_year) tgt
    ON tgt.return_year = dates.acad_year
 WHERE dates.report_timestamp >= SYSDATE - 3 -- run overlap just in case of weekends/fails, but only n-1 is needed normally
   AND dates.group_code = 'STD' --only need standard group_code
   AND (tgt.report_date IS NULL OR dates.report_date > tgt.report_date)
 ORDER BY dates.acad_year        ASC,
          dates.report_timestamp ASC;
CURSOR c1(v_cohort_year          VARCHAR,
          v_return_year          VARCHAR,
          v_timeframe_start_term VARCHAR,
          v_report_number        NUMBER,
          v_report_timestamp     DATE,
          v_expiration_date      DATE) IS
-- CTE to define the cohort of students for the given time
-- in order to get direct comparisons year to year, DO NOT use the "revised" cohort like this: to_date = DATE '2099-12-31'
-- the table function gets the "best" row for cohort year based on the report_timestamp of the return year
WITH cohort AS
 (SELECT /*+ MATERIALIZE */
   elog.pidm,
   v_cohort_year   AS cohort_year,
   v_return_year   AS return_year,
   elog.term_code,
   elog.start_date,
   elog.group_code,
   elog.semester,
   elog.camp_code,
   elog.levl_code,
   elog.coll_code,
   elog.degc_code,
   elog.majr_code,
   elog.acat_code,
   -- Ranking expression: prefer rows that are "active" on v_report_timestamp (start_date <= v_report_timestamp <= end_date).
   row_number() over(PARTITION BY elog.pidm, elog.acad_year ORDER BY greatest(sign(v_report_timestamp - elog.start_date), 0) * greatest(sign(elog.end_date - v_report_timestamp), 0) DESC, elog.from_date DESC, elog.to_date ASC) AS ranking
    FROM utl_d_aa.enrollments_log elog
   WHERE elog.acad_year = v_cohort_year
     AND v_report_timestamp BETWEEN elog.from_date AND elog.to_date
     AND elog.semester <> 'WIN'),
grads AS
 (SELECT /*+ MATERIALIZE */
   rg.pidm,
   rank() over(PARTITION BY rg.pidm ORDER BY rg.acat_code DESC, rg.grad_date DESC, rownum) ranking -- we only want to get one degree per student within the timeframe; highest and last award of the timeframe
    FROM utl_d_aa.retention_grads rg
    JOIN cohort elog
      ON elog.pidm = rg.pidm
     AND elog.ranking = 1
     AND rg.term_code_grad >= elog.term_code -- the graduation term has to be >= to the last enrolled term of the student; 
     AND rg.term_code_grad < v_timeframe_start_term -- limit timeframe for the end of yearly retention;
     AND ((rg.acat_code >= elog.acat_code AND rg.degc_code <> 'MDV') -- if not MDV, the degree code has to be >= the enrollment degree code
         OR (rg.degc_code = 'MDV' AND rg.degc_code = elog.degc_code)) -- if MDV, degree in passing in effect, we want to count this as an awarded degree
  )
SELECT CASE
       WHEN src.row_hash IS NOT NULL
            AND tgt.row_hash IS NULL THEN
        'NEW' -- New record in source, add it
       WHEN src.row_hash <> tgt.row_hash THEN
        'CHANGE' -- Record exists but changed, expire old row and add new row
       WHEN src.row_hash IS NULL
            AND tgt.row_hash IS NOT NULL THEN
        'EXPIRE' -- Record no longer exists in source, expire old row and do NOT add new row
       END AS control_state,
       nvl(src.row_hash, tgt.row_hash) AS row_hash,
       nvl(src.pidm, tgt.pidm) AS pidm,
       nvl(src.cohort_year, tgt.cohort_year) AS cohort_year,
       nvl(src.return_year, tgt.return_year) AS return_year,
       nvl(src.group_code, tgt.group_code) AS group_code,
       src.reg_date,
       src.fci_date,
       src.graduated,
       src.returned,
       src.return_camp,
       src.return_levl,
       src.return_coll,
       src.return_degr,
       src.return_majr
  FROM (SELECT standard_hash(nvl(to_char(pidm), '<NULL>') || '#' || nvl(to_char(group_code), '<NULL>') || '#' || nvl(to_char(cohort_year), '<NULL>') || '#' || nvl(to_char(return_year), '<NULL>') || '#' ||
                             nvl(to_char(reg_date, 'YYYYMMDD'), '<NULL>') || '#' || nvl(to_char(fci_date, 'YYYYMMDD'), '<NULL>') || '#' || nvl(to_char(graduated), '<NULL>') || '#' || nvl(to_char(returned), '<NULL>') || '#' ||
                             nvl(to_char(return_camp), '<NULL>') || '#' || nvl(to_char(return_levl), '<NULL>') || '#' || nvl(to_char(return_coll), '<NULL>') || '#' || nvl(to_char(return_degr), '<NULL>') || '#' ||
                             nvl(to_char(return_majr), '<NULL>'), 'MD5') AS row_hash,
               sr.pidm,
               sr.cohort_year,
               sr.return_year,
               sr.group_code,
               sr.reg_date,
               sr.fci_date,
               sr.graduated,
               sr.returned,
               sr.return_camp,
               sr.return_levl,
               sr.return_coll,
               sr.return_degr,
               sr.return_majr
          FROM (SELECT elog.pidm,
                       elog.cohort_year,
                       elog.return_year,
                       elog.group_code,
                       ret.reg_date, -- based on the ranking the ret subquery, we get the earliest sfrstca_rsts_date found 
                       ret.fci_date,
                       CASE
                       WHEN grads.pidm IS NOT NULL THEN
                        1
                       ELSE
                        0
                       END AS graduated,
                       CASE
                       WHEN ret.pidm IS NOT NULL THEN
                        1
                       ELSE
                        0
                       END AS returned,
                       CASE
                       WHEN ret.pidm IS NOT NULL
                            AND ret.camp_code = elog.camp_code THEN
                        1
                       ELSE
                        0
                       END AS return_camp,
                       CASE
                       WHEN ret.pidm IS NOT NULL
                            AND ret.levl_code = elog.levl_code THEN
                        1
                       ELSE
                        0
                       END AS return_levl,
                       CASE
                       WHEN ret.pidm IS NOT NULL
                            AND ret.coll_code = elog.coll_code THEN
                        1
                       ELSE
                        0
                       END AS return_coll,
                       CASE
                       WHEN ret.pidm IS NOT NULL
                            AND ret.degc_code = elog.degc_code THEN
                        1
                       ELSE
                        0
                       END AS return_degr,
                       CASE
                       WHEN ret.pidm IS NOT NULL
                            AND ret.majr_code = elog.majr_code THEN
                        1
                       ELSE
                        0
                       END AS return_majr,
                       v_etl_date AS activity_date
                  FROM cohort elog
                -- check to see if the student graduated after the cohort year
                  LEFT JOIN grads -- this is a strict definition coming from the PDB / BOT definition. no checks here for graduation on level or degc, etc.
                    ON grads.pidm = elog.pidm
                   AND grads.ranking = 1 -- returning the "best" awarded degree; 
                -- check to see if they came back the next year using table function to get the "best" row per academic year based on the timestamp
                  LEFT JOIN (SELECT elog.pidm,
                                   elog.term_code,
                                   elog.start_date,
                                   elog.group_code,
                                   elog.semester,
                                   elog.reg_date,
                                   elog.fci_date,
                                   elog.camp_code,
                                   elog.levl_code,
                                   elog.coll_code,
                                   elog.degc_code,
                                   elog.majr_code,
                                   elog.acat_code,
                                   -- Ranking expression: prefer rows that are "active" on v_report_timestamp (start_date <= v_report_timestamp <= end_date).
                                   row_number() over(PARTITION BY elog.pidm, elog.acad_year ORDER BY greatest(sign(v_report_timestamp - elog.start_date), 0) * greatest(sign(elog.end_date - v_report_timestamp), 0) DESC, elog.from_date DESC, elog.to_date ASC) AS ranking
                              FROM utl_d_aa.enrollments_log elog
                             WHERE elog.acad_year = v_return_year
                               AND v_report_timestamp BETWEEN elog.from_date AND elog.to_date
                               AND elog.semester <> 'WIN') ret
                    ON ret.pidm = elog.pidm
                   AND ret.ranking = 1
                   AND grads.pidm IS NULL -- **KEEP THIS ON THE LEFT JOIN and NOT THE WHERE CLAUSE** - removing grads from the return count; do not move this to the where clause. needs to be here on the ret join; 
                 WHERE elog.ranking = 1) sr) src
-- for the control state
  FULL JOIN (SELECT tgt.*
               FROM utl_d_aa.retention_log tgt
              WHERE tgt.cohort_year = v_cohort_year
                AND tgt.return_year = v_return_year
                AND tgt.to_date = DATE '2099-12-31' -- active record; infinity date signifies that they retained enrollment through the term; an expired date means, they did not (and likely were fully dropped from courses)
             ) tgt
    ON tgt.cohort_year = src.cohort_year
   AND tgt.return_year = src.return_year
   AND tgt.pidm = src.pidm
 WHERE 1 = 1
      -- <- new record, change record or expire -> --
   AND (((src.row_hash IS NULL AND tgt.row_hash IS NOT NULL) OR (src.row_hash IS NOT NULL AND tgt.row_hash IS NULL)) OR (src.row_hash <> tgt.row_hash));
TYPE rec_input_t IS TABLE OF c1%ROWTYPE;
rec_input rec_input_t;
TYPE index_pointer_t IS TABLE OF PLS_INTEGER;
ttab_dml index_pointer_t := index_pointer_t();
CURSOR cur_idx_dat(schema_ VARCHAR2,
                   table_  VARCHAR2) IS(
SELECT lower(a_idx.owner || '.' || a_idx.index_name) idx
  FROM all_indexes a_idx
 WHERE a_idx.owner = upper(schema_)
   AND a_idx.table_name = upper(table_));
rec_idx_dat cur_idx_dat%ROWTYPE;
TYPE index_pointer_i IS TABLE OF PLS_INTEGER;
insert_dml index_pointer_i := index_pointer_i();
TYPE index_pointer_u IS TABLE OF PLS_INTEGER;
update_dml    index_pointer_u := index_pointer_u();
v_total_count NUMBER := 0;
insert_count  NUMBER := 0;
update_count  NUMBER := 0;
v_elapsed     NUMBER := 0;
-- Added for error tracking on insert
TYPE error_log_t IS TABLE OF VARCHAR2(4000);
error_log error_log_t := error_log_t();
TYPE error_row_hash_t IS TABLE OF VARCHAR2(100);
error_row_hash error_row_hash_t := error_row_hash_t();
-- Additional vars for SAVE EXCEPTIONS processing
v_success    NUMBER := 0;
v_fail_count NUMBER := 0;
BEGIN
-- dbms_output.enable(buffer_size => NULL);
--
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
--
FOR rec IN c_terms
LOOP
OPEN c1(rec.cohort_year, rec.return_year, rec.timeframe_start_term, rec.report_number, rec.report_timestamp, rec.expiration_date);
LOOP
v_etl_date := SYSDATE; -- reset timestamp for tracking
v_count    := 0; -- reset count
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || rec.return_year || ' - ' || rec.report_number || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
FETCH c1 BULK COLLECT
INTO rec_input LIMIT v_row_max;
v_count := rec_input.count;
IF v_count = 0 THEN
dbms_lock.sleep(0.5);
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'SELECT - AIDY ' || rec.return_year || ' - ' || rec.report_number || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
ELSIF v_count > 0 THEN
dbms_lock.sleep(0.5);
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'SELECT - AIDY ' || rec.return_year || ' - ' || rec.report_number || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
insert_dml := index_pointer_i();
update_dml := index_pointer_u();
IF rec_input.count > 0 THEN
FOR idx IN 1 .. rec_input.count
LOOP
BEGIN
IF rec_input(idx).control_state IN ('EXPIRE', 'CHANGE') THEN
update_dml.extend; -- expiring changes; must run first
update_dml(update_dml.last) := idx;
END IF;
IF rec_input(idx).control_state IN ('NEW', 'CHANGE') THEN
insert_dml.extend; -- new or changes get a new row 
insert_dml(insert_dml.last) := idx;
END IF;
EXCEPTION
WHEN OTHERS THEN
dbms_lock.sleep(0.5);
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200) || ' exception raised for AIDY ' || rec.return_year || ' - ' || rec.report_number || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || round(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
CONTINUE;
END;
END LOOP;
END IF;
insert_count := insert_dml.count;
update_count := update_dml.count;
-- UPDATE block with SAVE EXCEPTIONS to ensure partial success and capture row-level errors
IF update_count > 0 THEN
BEGIN
FORALL i IN VALUES OF update_dml
SAVE EXCEPTIONS UPDATE utl_d_aa.retention_log tab SET tab.to_date = rec.expiration_date, -- set to_date to the report timestamp to expire it
tab.activity_date = v_etl_date WHERE tab.cohort_year = rec_input(i).cohort_year AND tab.return_year = rec_input(i).return_year AND tab.pidm = rec_input(i).pidm AND tab.to_date = DATE '2099-12-31';
v_count := SQL%ROWCOUNT;
COMMIT;
dbms_lock.sleep(0.5);
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'UPDATE - AIDY ' || rec.return_year || ' - ' || rec.report_number || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
EXCEPTION
WHEN OTHERS THEN
IF SQL%bulk_exceptions.count > 0 THEN
v_success    := update_count - SQL%bulk_exceptions.count;
v_fail_count := SQL%bulk_exceptions.count;
FOR j IN 1 .. SQL%bulk_exceptions.count
LOOP
error_log.extend;
error_row_hash.extend;
error_log(error_log.last) := 'UPDATE error idx=' || SQL%BULK_EXCEPTIONS(j).error_index || ' code=' || SQL%BULK_EXCEPTIONS(j).error_code || ' msg=' || substr(REPLACE(SQLERRM(-SQL%BULK_EXCEPTIONS(j).error_code), 'ORA', '!!!'), 1, 200);
error_row_hash(error_row_hash.last) := rec_input(update_dml(SQL%BULK_EXCEPTIONS(j).error_index)).row_hash;
END LOOP;
ELSE
v_success    := 0;
v_fail_count := 1;
error_log.extend;
error_log(error_log.last) := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
END IF;
COMMIT; -- commit successful rows
v_total_count := v_total_count + v_success;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
ads_etl.insert_job_log(v_proc, 'ERROR', 'UPDATE batch had errors; successes=' || v_success || ', errors=' || v_fail_count, v_instance, v_partition, v_job_id, v_elapsed, v_success);
END;
END IF;
-- INSERT block with SAVE EXCEPTIONS to capture unique constraint violations and identify offending rows
IF insert_dml.count > 0 THEN
BEGIN
FORALL i IN VALUES OF insert_dml
SAVE EXCEPTIONS --
INSERT
INTO utl_d_aa.retention_log(row_hash, from_date, to_date, activity_date, pidm, cohort_year, return_year, group_code, reg_date, fci_date, graduated, returned, return_camp, return_levl, return_coll, return_degr, return_majr) VALUES(rec_input(i).row_hash, rec.report_timestamp, DATE
                                                                                                                                                                                                                                       '2099-12-31', -- active record; infinity date signifies that they retained enrollment through the term; an expired date means, they did not (and likely were fully dropped from courses)
                                                                                                                                                                                                                                      v_etl_date, rec_input(i).pidm, rec_input(i).cohort_year, rec_input(i).return_year, rec_input(i).group_code, rec_input(i).reg_date, rec_input(i).fci_date, rec_input(i).graduated, rec_input(i).returned, rec_input(i).return_camp, rec_input(i).return_levl, rec_input(i).return_coll, rec_input(i).return_degr, rec_input(i).return_majr);
v_count := SQL%ROWCOUNT;
COMMIT;
dbms_lock.sleep(0.5);
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - AIDY ' || rec.return_year || ' - ' || rec.report_number || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
EXCEPTION
WHEN OTHERS THEN
IF SQL%bulk_exceptions.count > 0 THEN
v_success    := insert_count - SQL%bulk_exceptions.count;
v_fail_count := SQL%bulk_exceptions.count;
FOR j IN 1 .. SQL%bulk_exceptions.count
LOOP
-- Map bulk error index -> actual rec_input index
DECLARE
v_input_idx PLS_INTEGER := insert_dml(SQL%BULK_EXCEPTIONS(j).error_index);
v_hash      VARCHAR2(100) := rec_input(v_input_idx).row_hash;
v_pidm      VARCHAR2(50) := to_char(rec_input(v_input_idx).pidm);
v_keys      VARCHAR2(200) := 'PIDM=' || v_pidm || ', COHORT=' || rec_input(v_input_idx).cohort_year || ', RETURN=' || rec_input(v_input_idx).return_year;
v_cols      VARCHAR2(200) := 'ROW_HASH=' || v_hash || ', FROM_DATE=' || to_char(rec.report_timestamp, 'YYYY-MM-DD HH24:MI:SS') || ', TO_DATE=2099-12-31';
BEGIN
error_log.extend;
error_row_hash.extend;
error_row_hash(error_row_hash.last) := v_hash;
-- Include exact unique key plus helpful business keys for fast diagnosis
error_log(error_log.last) := 'INSERT error idx=' || SQL%BULK_EXCEPTIONS(j).error_index || ' code=' || SQL%BULK_EXCEPTIONS(j).error_code || ' msg=' || substr(REPLACE(SQLERRM(-SQL%BULK_EXCEPTIONS(j).error_code), 'ORA', '!!!'), 1, 90) ||
                             ' | ' || substr(v_cols || ' | ' || v_keys, 1, 200);
EXCEPTION
WHEN OTHERS THEN
NULL; -- defensive: don't let logging blow up the batch
END;
END LOOP;
ELSE
v_success    := 0;
v_fail_count := 1;
error_log.extend;
error_log(error_log.last) := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
END IF;
COMMIT; -- commit successful rows despite failures
v_total_count := v_total_count + v_success;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
-- Promote to ERROR so the scheduler flags the job as failing attention
ads_etl.insert_job_log(v_proc, 'ERROR', 'INSERT batch had errors; successes=' || v_success || ', errors=' || v_fail_count, v_instance, v_partition, v_job_id, v_elapsed, v_success);
END;
END IF;
END IF;
EXIT WHEN(rec_input.count < v_row_max);
END LOOP;
CLOSE c1;
dbms_output.put_line(' --------- ');
END LOOP; -- c_terms
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
-- log any errors
IF error_log.count > 0 THEN
FOR i IN 1 .. error_log.count
LOOP
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(error_log(i), 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
END LOOP;
END IF;
EXCEPTION
WHEN OTHERS THEN
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
END etl_aa_retention_log;

procedure etl_aa_enrollments_log(jobnumber number, processid varchar2, processname varchar2) IS
--
-- PURPOSE: Logs daily student term enrollment seat and credit hour metrics with change history to support academic year pacing reporting and dashboards.
--
-- TABLE: utl_d_aa.enrollments_log
--
-- UNIQUE INDEX: PIDM, TERM_CODE, ROW_HASH
--
-- CONDITIONS:
-- Processes each eligible financial aid processing year (AIDY) from zbtm.terms_by_group_v where term_code is not '000000'.
-- Includes only term groups 'STD' and 'MED' and excludes winter semester terms (semester not 'WIN').
-- Builds a reporting timeframe per AIDY starting 90 days before the earliest term start date and ending at the latest term end date of the following aid year (fa_proc_year + 101) for 'STD'/'MED' non-winter terms.
-- Generates daily report dates with report_timestamp set to 11:59:00 PM and expiration_date set to 11:58:59 PM for each day.
-- Only processes report days up to the prior calendar day (no processing for the current day or any future day).
-- Only considers the most recent 7 days of report days to backfill missed refreshes.
-- Skips any report day that is already completed for an AIDY by comparing against the maximum existing from_date in utl_d_aa.enrollments_log for that acad_year.
-- Includes only SFRSTCA enrollment activity with source code 'BASE' and registration status date on or before the report_timestamp.
-- Uses only the latest SFRSTCA sequence per student, term, and CRN as of the report_timestamp (max sfrstca_seq_number where rsts_date <= report_timestamp and source_cde = 'BASE').
-- Includes only registration statuses whose STVRSTS flag indicates the enrollment should be included in section enrollment (stvrsts_incl_sect_enrl = 'Y').
-- Includes only course sections that exist in SSBSECT for the same term and CRN and excludes subject codes 'NEWS' and 'CSER'.
-- Assigns student attributes (campus, level, college, degree, major) from zexec.zsavlcur where the term is between the student program from_term and end_term.
-- Excludes students in degree code 'THG' and excludes program codes with prefixes 'LEL' and 'SPC'.
-- Includes only enrollments where the course level is university-level per zsaturn.szrlevl (szrlevl_is_univ = 'Y').
-- Excludes students flagged as deceased where a matching utl_d_aim.szriden record has dead_ind = 'Y' and the report_timestamp falls within the deceased effective date range.
-- Excludes students with active financial aid fraud holds where rorhold_hold_code is in ('FC','FD','FO','EH','FI','FY','FF') and the report_timestamp falls within the hold effective date range.
-- Links Financial Check-In (FCI) data only when the student and term match and the student is checked-in (fci_status = 'Y').
-- Matches FCI coverage using the numeric report_number within the FCI effective window (report_number >= fci_from_date and report_number < fci_to_date).
-- Sets reg_date as the earliest registration status date (MIN sfrstca_rsts_date) per student and term as of the report_timestamp.
-- Sets fci_date as the earliest derived FCI date per student and term, preferring the first FCI date that occurs after the registration date; otherwise fabricates an FCI date as registration date plus one day when an FCI date exists but is not after the registration date.
-- Calculates term_seats as the distinct count of CRNs enrolled per student and term (includes zero credit hour enrollments).
-- Calculates term_res_seats as the distinct count of CRNs where campus code is 'R' and term_luo_seats where campus code is 'D'.
-- Calculates term_hours as the sum of registered credit hours per student and term, plus campus-specific hour totals for 'R' and 'D'.
-- Calculates term_au_hours as the sum of credit hours for registration statuses flagged not to be included in section enrollment (stvrsts_incl_sect_enrl = 'N').
-- Calculates part-of-term hour totals by summing credit hours by SSBSECT part-of-term code: 1A, 1B, 1C, 1D, 1J, and R.
-- Calculates term_wd_hours as the sum of credit hours for registration statuses marked as withdrawn (stvrsts_withdraw_ind = 'Y').
-- Constructs row_hash as an MD5 hash of the student-term key and all tracked attributes and calculated metrics to detect changes over time.
-- Compares the newly computed source state to the current active target state (to_date = DATE '2099-12-31') for the same acad_year to identify NEW, CHANGE, and EXPIRE records.
-- Expires existing active records by setting to_date to expiration_date for student-term rows that changed or no longer exist in the source as of the report day.
-- Inserts new active rows for NEW records and for CHANGE records with from_date set to report_timestamp and to_date set to DATE '2099-12-31'.
-- After applying daily changes, recalculates academic-year running totals per student across terms up to the report_timestamp using cumulative sums ordered by term_code (acad_seats, acad_hours, and all related campus/part-of-term/withdrawal breakdowns).
-- Calculates yr_rank as the descending term order rank per student and academic year on active rows only (to_date = DATE '2099-12-31') for reporting the most recent term position within the year.
--
--DECLARE
v_etl_date  DATE := SYSDATE;
v_msg       VARCHAR2(2000);
v_instance  VARCHAR2(50) := upper('ALL'); -- inst from the jams job; used for determining instance
v_partition NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_row_max   NUMBER := 200000; -- max number of rows to be processed at one time
v_count     NUMBER := 0;
v_job_id    VARCHAR2(32);
v_proc      VARCHAR2(100) := 'etl_aa_enrollments_log';
-- cursors
CURSOR c_terms IS
SELECT dates.acad_year,
       dates.report_number,
       dates.report_timestamp,
       dates.expiration_date
  FROM utl_d_aa.acad_year_dates dates
  LEFT JOIN (SELECT acad_year,
                    MAX(from_date) AS report_date
               FROM utl_d_aa.enrollments_log
              GROUP BY acad_year) tgt
    ON tgt.acad_year = dates.acad_year
 WHERE dates.report_timestamp >= SYSDATE - 3 -- run overlap just in case of weekends/fails, but only n-1 is needed normally
   AND dates.group_code = 'STD' --only need standard group_code
   AND (tgt.report_date IS NULL OR dates.report_date > tgt.report_date)
 ORDER BY dates.acad_year        ASC,
          dates.report_timestamp ASC;
CURSOR c1(v_acad_year        VARCHAR,
          v_report_number    NUMBER,
          v_report_timestamp DATE,
          v_expiration_date  DATE) IS
SELECT CASE
       WHEN src.row_hash IS NOT NULL
            AND tgt.row_hash IS NULL THEN
        'NEW' -- new record to source, add it
       WHEN src.row_hash <> tgt.row_hash THEN
        'CHANGE' -- record exists but changed, expire old row and add new row
       WHEN src.row_hash IS NULL
            AND tgt.row_hash IS NOT NULL THEN
        'EXPIRE' -- record no longer exists on the source data, expire old row and **do not** add new row
       END AS control_state,
       nvl(src.row_hash, tgt.row_hash) AS row_hash,
       nvl(src.pidm, tgt.pidm) AS pidm,
       nvl(src.term_code, tgt.term_code) AS term_code,
       src.start_date,
       src.end_date,
       src.camp_code,
       src.levl_code,
       src.coll_code,
       src.degc_code,
       src.majr_code,
       src.acat_code,
       src.group_code,
       src.semester,
       src.acad_year,
       src.reg_date,
       src.fci_date,
       src.term_seats,
       src.term_res_seats,
       src.term_luo_seats,
       src.term_hours,
       src.term_res_hours,
       src.term_luo_hours,
       src.term_au_hours,
       src.term_a_hours,
       src.term_b_hours,
       src.term_c_hours,
       src.term_d_hours,
       src.term_j_hours,
       src.term_r_hours,
       src.term_wd_hours
  FROM (SELECT standard_hash(nvl(to_char(pidm), '<NULL>') || '#' || nvl(to_char(term_code), '<NULL>') || '#' || nvl(to_char(camp_code), '<NULL>') || '#' || nvl(to_char(levl_code), '<NULL>') || '#' || nvl(to_char(coll_code), '<NULL>') || '#' ||
                             nvl(to_char(degc_code), '<NULL>') || '#' || nvl(to_char(majr_code), '<NULL>') || '#' || nvl(to_char(acat_code), '<NULL>') || '#' || nvl(to_char(group_code), '<NULL>') || '#' || nvl(to_char(semester), '<NULL>') || '#' ||
                             nvl(to_char(acad_year), '<NULL>') || '#' || nvl(to_char(reg_date, 'YYYYMMDD'), '<NULL>') || '#' || nvl(to_char(fci_date, 'YYYYMMDD'), '<NULL>') || '#' || nvl(to_char(term_seats), '<NULL>') || '#' ||
                             nvl(to_char(term_res_seats), '<NULL>') || '#' || nvl(to_char(term_luo_seats), '<NULL>') || '#' || nvl(to_char(term_hours), '<NULL>') || '#' || nvl(to_char(term_res_hours), '<NULL>') || '#' ||
                             nvl(to_char(term_luo_hours), '<NULL>') || '#' || nvl(to_char(term_au_hours), '<NULL>') || '#' || nvl(to_char(term_a_hours), '<NULL>') || '#' || nvl(to_char(term_b_hours), '<NULL>') || '#' ||
                             nvl(to_char(term_c_hours), '<NULL>') || '#' || nvl(to_char(term_d_hours), '<NULL>') || '#' || nvl(to_char(term_j_hours), '<NULL>') || '#' || nvl(to_char(term_r_hours), '<NULL>') || '#' ||
                             nvl(to_char(term_wd_hours), '<NULL>'), 'MD5') AS row_hash,
               sr.pidm,
               sr.term_code,
               sr.start_date,
               sr.end_date,
               sr.camp_code,
               sr.levl_code,
               sr.coll_code,
               sr.degc_code,
               sr.majr_code,
               sr.acat_code,
               sr.group_code,
               sr.semester,
               sr.acad_year,
               sr.reg_date,
               sr.fci_date,
               sr.term_seats,
               sr.term_res_seats,
               sr.term_luo_seats,
               sr.term_hours,
               sr.term_res_hours,
               sr.term_luo_hours,
               sr.term_au_hours,
               sr.term_a_hours,
               sr.term_b_hours,
               sr.term_c_hours,
               sr.term_d_hours,
               sr.term_j_hours,
               sr.term_r_hours,
               sr.term_wd_hours
          FROM (SELECT sfrstca_pidm AS pidm, -- student ID 
                       sfrstca_term_code AS term_code, -- should be the variable hard coded and NOT pulled from sfrstca; **there should be no group by**
                       terms.start_date, -- semester start date
                       terms.end_date, -- semester end date 
                       lcur.camp_code, -- campus code
                       lcur.levl_code, -- level code
                       lcur.prog_coll_1 AS coll_code, -- college code
                       lcur.degc_code_1 AS degc_code, -- degree code
                       lcur.majr_code_1 AS majr_code, -- major code
                       stvdegc_acat_code AS acat_code, -- numberic degree academic category code
                       terms.group_code, -- standard or med; should be the variable hard coded
                       terms.semester, -- semester type code; should be the variable hard coded
                       v_acad_year AS acad_year, -- should be the variable hard coded
                       MIN(sfrstca_rsts_date) AS reg_date, -- registration date that triggers reg change; must be MIN here
                       MIN(CASE
                           WHEN fci.fci_orig_date > sfrstca_rsts_date THEN
                            fci.fci_orig_date -- use if greater than reg date
                           WHEN fci.fci_checkin_date > sfrstca_rsts_date THEN
                            fci.fci_checkin_date -- use if greater than reg date
                           WHEN fci.fci_current_checkin_date > sfrstca_rsts_date THEN
                            fci.fci_current_checkin_date -- use if greater than reg date
                           WHEN fci.fci_orig_date IS NOT NULL
                                AND sfrstca_rsts_date IS NOT NULL THEN
                            sfrstca_rsts_date + 1 -- adding a day to the fabricated FCI date
                           WHEN fci.fci_checkin_date IS NOT NULL
                                AND sfrstca_rsts_date IS NOT NULL THEN
                            sfrstca_rsts_date + 1 -- adding a day to the fabricated FCI date
                           WHEN fci.fci_current_checkin_date IS NOT NULL
                                AND sfrstca_rsts_date IS NOT NULL THEN
                            sfrstca_rsts_date + 1 -- adding a day to the fabricated FCI date
                           END) AS fci_date, -- financial check-in date; must be MIN; forcing the FCI date to be after the sfrstca_rsts_date so it makes logical sense; not sure why the FCI data shows up before registering sometimes
                       -- Term seat and hour calculations
                       nvl(COUNT(DISTINCT sfrstca_crn), 0) AS term_seats, -- counts up unique number of course sections enrolled; including zero credit hour courses
                       nvl(COUNT(DISTINCT CASE
                                 WHEN lcur.camp_code = 'R' THEN
                                  sfrstca_crn
                                 END), 0) AS term_res_seats, -- counts up unique number of course sections enrolled including zero credit hour courses taken as a **resident student**
                       nvl(COUNT(DISTINCT CASE
                                 WHEN lcur.camp_code = 'D' THEN
                                  sfrstca_crn
                                 END), 0) AS term_luo_seats, -- counts up unique number of course sections enrolled including zero credit hour courses taken as a **online student**
                       nvl(SUM(sfrstca_credit_hr), 0) AS term_hours, -- total of hours for term
                       nvl(SUM(CASE
                               WHEN lcur.camp_code = 'R' THEN
                                sfrstca_credit_hr
                               END), 0) AS term_res_hours, -- hours taken as a **resident student**
                       nvl(SUM(CASE
                               WHEN lcur.camp_code = 'D' THEN
                                sfrstca_credit_hr
                               END), 0) AS term_luo_hours, -- hours taken as a **online student**
                       nvl(SUM(CASE
                               WHEN stvrsts.stvrsts_incl_sect_enrl = 'N' THEN
                                sfrstca_credit_hr
                               END), 0) AS term_au_hours, -- audit course hours
                       nvl(SUM(CASE
                               WHEN ssbsect.ssbsect_ptrm_code = '1A' THEN
                                sfrstca_credit_hr
                               END), 0) AS term_a_hours, -- ptrm_code is part of term or sub-term
                       nvl(SUM(CASE
                               WHEN ssbsect.ssbsect_ptrm_code = '1B' THEN
                                sfrstca_credit_hr
                               END), 0) AS term_b_hours,
                       nvl(SUM(CASE
                               WHEN ssbsect.ssbsect_ptrm_code = '1C' THEN
                                sfrstca_credit_hr
                               END), 0) AS term_c_hours,
                       nvl(SUM(CASE
                               WHEN ssbsect.ssbsect_ptrm_code = '1D' THEN
                                sfrstca_credit_hr
                               END), 0) AS term_d_hours,
                       nvl(SUM(CASE
                               WHEN ssbsect.ssbsect_ptrm_code = '1J' THEN
                                sfrstca_credit_hr
                               END), 0) AS term_j_hours,
                       nvl(SUM(CASE
                               WHEN ssbsect.ssbsect_ptrm_code = 'R' THEN
                                sfrstca_credit_hr
                               END), 0) AS term_r_hours,
                       nvl(SUM(CASE
                               WHEN stvrsts.stvrsts_withdraw_ind = 'Y' THEN
                                sfrstca_credit_hr
                               END), 0) AS term_wd_hours
                -- start with course related tables to get min reg date, hours and seats data; using SFRSTCA because rolling courses changes the SFRSTCR dates because Banner recalculates 
                -- IMPORTANT: we ARE looking for ALL enrollments - including zero (0) credit hours
                  FROM saturn.sfrstca
                  JOIN saturn.stvrsts
                    ON stvrsts_code = sfrstca_rsts_code -- filtering types in the where clause      
                   AND stvrsts_incl_sect_enrl = 'Y' -- ind that determines valid enrollment which will include courses being audited; this is exclusively used by academics, and for reporting, use the wd_hours fields if you need to exclude these students                  
                  JOIN zbtm.terms_by_group_v terms -- we need this join to pull all rows per academic year to calculate both term and yearly stats
                    ON terms.term_code = sfrstca_term_code
                   AND terms.group_code IN ('STD', 'MED') -- iso just these terms; **do not remove this filter or join**                  
                   AND terms.fa_proc_year = v_acad_year -- get all terms for the year
                   AND sfrstca_rsts_date <= v_report_timestamp
                   AND sfrstca_source_cde = 'BASE'
                   AND sfrstca.sfrstca_seq_number = (SELECT MAX(d.sfrstca_seq_number)
                                                       FROM saturn.sfrstca d
                                                      WHERE d.sfrstca_pidm = sfrstca.sfrstca_pidm
                                                        AND d.sfrstca_term_code = sfrstca.sfrstca_term_code
                                                        AND d.sfrstca_crn = sfrstca.sfrstca_crn
                                                        AND d.sfrstca_source_cde = 'BASE'
                                                        AND d.sfrstca_rsts_date <= v_report_timestamp)
                  JOIN saturn.ssbsect
                    ON ssbsect_term_code = sfrstca_term_code
                   AND ssbsect_crn = sfrstca_crn
                   AND ssbsect_subj_code NOT IN ('NEWS', 'CSER') -- removing new student placeholder courses, Christian service courses 
                -- student program joins... and this is where we need to start defining our cohort population (on student attributes and NOT course attributes)
                  JOIN zexec.zsavlcur lcur
                    ON lcur.pidm = sfrstca_pidm
                   AND sfrstca_term_code BETWEEN lcur.from_term AND lcur.end_term -- **careful with this if you're running yearly numbers** because if you're not, you will pull multiple rows on aggregates
                   AND lcur.degc_code_1 NOT IN ('THG') -- excluding Willmington School of the Bible students
                   AND substr(lcur.prog_code_1, 1, 3) NOT IN ('LEL', 'SPC') -- excluding english lang institute students (no longer active) and special students
                  JOIN saturn.stvdegc
                    ON lcur.degc_code_1 = stvdegc_code -- need this later/downstream to determine if degree is "in passing"
                  JOIN zsaturn.szrlevl
                    ON szrlevl_levl_code = sfrstca_levl_code -- must be joining on the course level for this (not program level)
                   AND szrlevl_is_univ = 'Y' -- this indicator INCLUDES ('CT','DR','GR','IN','JD','MD','UG'); INCLUDES LUOA dual enroll; excludes 1P
                  LEFT JOIN dm_person.fci_d__01 fci
                    ON fci.fci_b_pidm = sfrstca_pidm
                   AND fci.fci_b_term_code = sfrstca_term_code
                   AND v_report_number >= fci.fci_from_date
                   AND v_report_number < fci.fci_to_date -- do not use between here; the dates for this table is number format (20251113) and that is why we have the var report_date_number
                   AND fci.fci_status = 'Y' -- this indicator means the student is checked-in and NOT withdrawn their financial check-in
                  LEFT JOIN utl_d_aim.szriden dead
                    ON dead.szriden_pidm = sfrstca_pidm
                   AND v_report_timestamp BETWEEN dead.szriden_from_date AND dead.szriden_to_date
                   AND dead.szriden_dead_ind = 'Y' -- only looking for student's who may have been enrolled in cohort and then death occurred preventing their return
                    LEFT JOIN rorhold fin_fraud
                      ON fin_fraud.rorhold_pidm = sfrstca_pidm
                     AND fin_fraud.rorhold_hold_code IN ('FC', 'FD', 'FO', 'EH', 'FI', 'FY', 'FF') -- financial aid side fraud ID'ed
                   AND v_report_timestamp BETWEEN fin_fraud.rorhold_from_date AND fin_fraud.rorhold_to_date
                 WHERE dead.szriden_pidm IS NULL -- removing deceased from the cohort population
                   AND fin_fraud.rorhold_pidm IS NULL -- removing any financial aid fraudsters
                 GROUP BY sfrstca_pidm,
                          sfrstca_term_code,
                          terms.start_date,
                          terms.end_date,
                          terms.group_code,
                          terms.semester,
                          v_acad_year,
                          lcur.camp_code,
                          lcur.levl_code,
                          lcur.prog_coll_1,
                          lcur.degc_code_1,
                          lcur.majr_code_1,
                          stvdegc_acat_code) sr) src
-- for the control state
  FULL JOIN (SELECT *
               FROM utl_d_aa.enrollments_log
              WHERE acad_year = v_acad_year
                AND to_date = DATE '2099-12-31' -- active record; infinity date signifies that they retained enrollment through the term; an expired date means, they did not (and likely were fully dropped from courses)
             ) tgt
    ON tgt.term_code = src.term_code
   AND tgt.pidm = src.pidm
 WHERE 1 = 1
      -- <- new record, change record or expire -> --
   AND (((src.row_hash IS NULL AND tgt.row_hash IS NOT NULL) OR (src.row_hash IS NOT NULL AND tgt.row_hash IS NULL)) OR (src.row_hash <> tgt.row_hash));
TYPE rec_input_t IS TABLE OF c1%ROWTYPE;
rec_input rec_input_t;
TYPE index_pointer_t IS TABLE OF PLS_INTEGER;
ttab_dml index_pointer_t := index_pointer_t();
CURSOR cur_idx_dat(schema_ VARCHAR2,
                   table_  VARCHAR2) IS(
SELECT lower(a_idx.owner || '.' || a_idx.index_name) idx
  FROM all_indexes a_idx
 WHERE a_idx.owner = upper(schema_)
   AND a_idx.table_name = upper(table_));
rec_idx_dat cur_idx_dat%ROWTYPE;
TYPE index_pointer_i IS TABLE OF PLS_INTEGER;
insert_dml index_pointer_i := index_pointer_i();
TYPE index_pointer_u IS TABLE OF PLS_INTEGER;
update_dml    index_pointer_u := index_pointer_u();
v_total_count NUMBER := 0;
insert_count  NUMBER := 0;
update_count  NUMBER := 0;
v_elapsed     NUMBER := 0;
-- Added for error tracking on insert
TYPE error_log_t IS TABLE OF VARCHAR2(4000);
error_log error_log_t := error_log_t();
TYPE error_row_hash_t IS TABLE OF VARCHAR2(100);
error_row_hash error_row_hash_t := error_row_hash_t();
BEGIN
-- dbms_output.enable(buffer_size => NULL);
ads_etl.set_parallel_session('Y', 8, 'QUERY'); -- FORALL statements. We must SET to QUERY.
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
--
FOR rec IN c_terms
LOOP
OPEN c1(rec.acad_year, rec.report_number, rec.report_timestamp, rec.expiration_date);
LOOP
v_count := 0; -- reset count
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || rec.acad_year || ' - ' || rec.report_number || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
FETCH c1 BULK COLLECT
INTO rec_input LIMIT v_row_max;
v_count := rec_input.count;
IF v_count = 0 THEN
dbms_lock.sleep(0.5);
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'SELECT - AIDY ' || rec.acad_year || ' - ' || rec.report_number || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
ELSIF v_count > 0 THEN
dbms_lock.sleep(0.5);
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'SELECT - AIDY ' || rec.acad_year || ' - ' || rec.report_number || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
insert_dml := index_pointer_i();
update_dml := index_pointer_u();
IF rec_input.count > 0 THEN
FOR idx IN 1 .. rec_input.count
LOOP
BEGIN
IF rec_input(idx).control_state IN ('EXPIRE', 'CHANGE') THEN
update_dml.extend; -- expiring changes; must run first
update_dml(update_dml.last) := idx;
END IF;
IF rec_input(idx).control_state IN ('NEW', 'CHANGE') THEN
insert_dml.extend; -- new or changes get a new row 
insert_dml(insert_dml.last) := idx;
END IF;
EXCEPTION
WHEN OTHERS THEN
dbms_lock.sleep(0.5);
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200) || ' exception raised for AIDY ' || rec.acad_year || ' - ' || rec.report_number || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || round(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
CONTINUE;
END;
END LOOP;
END IF;
insert_count := insert_dml.count;
update_count := update_dml.count;
IF update_count > 0 THEN
FORALL i IN VALUES OF update_dml
UPDATE utl_d_aa.enrollments_log tab
   SET tab.to_date       = rec.expiration_date, -- set to_date to the report timestamp to expire it
       tab.activity_date = v_etl_date
 WHERE tab.term_code = rec_input(i).term_code
   AND tab.pidm = rec_input(i).pidm
   AND tab.to_date = DATE '2099-12-31';
v_count := SQL%ROWCOUNT;
COMMIT;
dbms_lock.sleep(0.5);
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'UPDATE - AIDY ' || rec.acad_year || ' - ' || rec.report_number || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
END IF;
IF insert_dml.count > 0 THEN
FORALL i IN VALUES OF insert_dml
INSERT INTO utl_d_aa.enrollments_log
(row_hash,
 from_date,
 to_date,
 activity_date,
 pidm,
 term_code,
 start_date,
 end_date,
 camp_code,
 levl_code,
 coll_code,
 degc_code,
 majr_code,
 acat_code,
 group_code,
 semester,
 acad_year,
 reg_date,
 fci_date,
 term_seats,
 term_res_seats,
 term_luo_seats,
 term_hours,
 term_res_hours,
 term_luo_hours,
 term_au_hours,
 term_a_hours,
 term_b_hours,
 term_c_hours,
 term_d_hours,
 term_j_hours,
 term_r_hours,
 term_wd_hours)
VALUES
(rec_input(i).row_hash,
 rec.report_timestamp,
 DATE '2099-12-31', -- active record; infinity date signifies that they retained enrollment through the term; an expired date means, they did not (and likely were fully dropped from courses)
 v_etl_date,
 rec_input(i).pidm,
 rec_input(i).term_code,
 rec_input(i).start_date,
 rec_input(i).end_date,
 rec_input(i).camp_code,
 rec_input(i).levl_code,
 rec_input(i).coll_code,
 rec_input(i).degc_code,
 rec_input(i).majr_code,
 rec_input(i).acat_code,
 rec_input(i).group_code,
 rec_input(i).semester,
 rec_input(i).acad_year,
 rec_input(i).reg_date,
 rec_input(i).fci_date,
 rec_input(i).term_seats,
 rec_input(i).term_res_seats,
 rec_input(i).term_luo_seats,
 rec_input(i).term_hours,
 rec_input(i).term_res_hours,
 rec_input(i).term_luo_hours,
 rec_input(i).term_au_hours,
 rec_input(i).term_a_hours,
 rec_input(i).term_b_hours,
 rec_input(i).term_c_hours,
 rec_input(i).term_d_hours,
 rec_input(i).term_j_hours,
 rec_input(i).term_r_hours,
 rec_input(i).term_wd_hours);
v_count := SQL%ROWCOUNT;
COMMIT;
dbms_lock.sleep(0.5);
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - AIDY ' || rec.acad_year || ' - ' || rec.report_number || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
END IF;
END IF;
EXIT WHEN(rec_input.count < v_row_max);
END LOOP;
CLOSE c1;
IF v_count > 0 THEN
-- only need to run step 2-3 if we have changes found in step 1
-- now, we need to do step 2; calculating the academic year numbers up to that point in time...
ads_etl.set_parallel_session('Y', 8, 'ALL'); -- Do heavy set-based DML. Turn on full Parallel DML.
MERGE INTO utl_d_aa.enrollments_log tgt
USING (SELECT rc.pidm,
              rc.term_code,
              rc.row_hash,
              -- Calculate cumulative sums for all terms in the academic year up to the current report_timestamp
              nvl(SUM(rc.term_seats) over(PARTITION BY rc.pidm, rc.acad_year ORDER BY rc.term_code rows BETWEEN unbounded preceding AND CURRENT ROW), 0) AS acad_seats,
              nvl(SUM(rc.term_res_seats) over(PARTITION BY rc.pidm, rc.acad_year ORDER BY rc.term_code rows BETWEEN unbounded preceding AND CURRENT ROW), 0) AS acad_res_seats,
              nvl(SUM(rc.term_luo_seats) over(PARTITION BY rc.pidm, rc.acad_year ORDER BY rc.term_code rows BETWEEN unbounded preceding AND CURRENT ROW), 0) AS acad_luo_seats,
              nvl(SUM(rc.term_hours) over(PARTITION BY rc.pidm, rc.acad_year ORDER BY rc.term_code rows BETWEEN unbounded preceding AND CURRENT ROW), 0) AS acad_hours,
              nvl(SUM(rc.term_res_hours) over(PARTITION BY rc.pidm, rc.acad_year ORDER BY rc.term_code rows BETWEEN unbounded preceding AND CURRENT ROW), 0) AS acad_res_hours,
              nvl(SUM(rc.term_luo_hours) over(PARTITION BY rc.pidm, rc.acad_year ORDER BY rc.term_code rows BETWEEN unbounded preceding AND CURRENT ROW), 0) AS acad_luo_hours,
              nvl(SUM(rc.term_au_hours) over(PARTITION BY rc.pidm, rc.acad_year ORDER BY rc.term_code rows BETWEEN unbounded preceding AND CURRENT ROW), 0) AS acad_au_hours,
              nvl(SUM(rc.term_a_hours) over(PARTITION BY rc.pidm, rc.acad_year ORDER BY rc.term_code rows BETWEEN unbounded preceding AND CURRENT ROW), 0) AS acad_a_hours,
              nvl(SUM(rc.term_b_hours) over(PARTITION BY rc.pidm, rc.acad_year ORDER BY rc.term_code rows BETWEEN unbounded preceding AND CURRENT ROW), 0) AS acad_b_hours,
              nvl(SUM(rc.term_c_hours) over(PARTITION BY rc.pidm, rc.acad_year ORDER BY rc.term_code rows BETWEEN unbounded preceding AND CURRENT ROW), 0) AS acad_c_hours,
              nvl(SUM(rc.term_d_hours) over(PARTITION BY rc.pidm, rc.acad_year ORDER BY rc.term_code rows BETWEEN unbounded preceding AND CURRENT ROW), 0) AS acad_d_hours,
              nvl(SUM(rc.term_j_hours) over(PARTITION BY rc.pidm, rc.acad_year ORDER BY rc.term_code rows BETWEEN unbounded preceding AND CURRENT ROW), 0) AS acad_j_hours,
              nvl(SUM(rc.term_r_hours) over(PARTITION BY rc.pidm, rc.acad_year ORDER BY rc.term_code rows BETWEEN unbounded preceding AND CURRENT ROW), 0) AS acad_r_hours,
              nvl(SUM(rc.term_wd_hours) over(PARTITION BY rc.pidm, rc.acad_year ORDER BY rc.term_code rows BETWEEN unbounded preceding AND CURRENT ROW), 0) AS acad_wd_hours
         FROM utl_d_aa.enrollments_log rc
        WHERE rc.to_date = DATE '2099-12-31' -- active record; infinity date signifies that they retained enrollment through the term; an expired date means, they did not (and likely were fully dropped from courses)
          AND rc.acad_year = rec.acad_year -- get year and NOT term on this join
          AND rc.from_date <= rec.report_timestamp -- Only include terms up to the current report date
       ) src
ON (tgt.pidm = src.pidm AND tgt.term_code = src.term_code AND tgt.row_hash = src.row_hash)
WHEN MATCHED THEN
UPDATE
   SET tgt.acad_seats     = src.acad_seats,
       tgt.acad_res_seats = src.acad_res_seats,
       tgt.acad_luo_seats = src.acad_luo_seats,
       tgt.acad_hours     = src.acad_hours,
       tgt.acad_res_hours = src.acad_res_hours,
       tgt.acad_luo_hours = src.acad_luo_hours,
       tgt.acad_au_hours  = src.acad_au_hours,
       tgt.acad_a_hours   = src.acad_a_hours,
       tgt.acad_b_hours   = src.acad_b_hours,
       tgt.acad_c_hours   = src.acad_c_hours,
       tgt.acad_d_hours   = src.acad_d_hours,
       tgt.acad_j_hours   = src.acad_j_hours,
       tgt.acad_r_hours   = src.acad_r_hours,
       tgt.acad_wd_hours  = src.acad_wd_hours,
       tgt.activity_date  = v_etl_date
 WHERE (nvl(tgt.acad_seats, 0) <> nvl(src.acad_seats, 0) OR nvl(tgt.acad_res_seats, 0) <> nvl(src.acad_res_seats, 0) OR nvl(tgt.acad_luo_seats, 0) <> nvl(src.acad_luo_seats, 0) OR nvl(tgt.acad_hours, 0) <> nvl(src.acad_hours, 0) OR
       nvl(tgt.acad_res_hours, 0) <> nvl(src.acad_res_hours, 0) OR nvl(tgt.acad_luo_hours, 0) <> nvl(src.acad_luo_hours, 0) OR nvl(tgt.acad_au_hours, 0) <> nvl(src.acad_au_hours, 0) OR nvl(tgt.acad_a_hours, 0) <> nvl(src.acad_a_hours, 0) OR
       nvl(tgt.acad_b_hours, 0) <> nvl(src.acad_b_hours, 0) OR nvl(tgt.acad_c_hours, 0) <> nvl(src.acad_c_hours, 0) OR nvl(tgt.acad_d_hours, 0) <> nvl(src.acad_d_hours, 0) OR nvl(tgt.acad_j_hours, 0) <> nvl(src.acad_j_hours, 0) OR
       nvl(tgt.acad_r_hours, 0) <> nvl(src.acad_r_hours, 0) OR nvl(tgt.acad_wd_hours, 0) <> nvl(src.acad_wd_hours, 0));
v_count := SQL%ROWCOUNT;
COMMIT;
dbms_lock.sleep(0.5); -- pause half second
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE (ACAD) - ' || rec.acad_year || ' - ' || rec.report_number || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- now, we need to do step 3; calculating the year rank; calc on all active rows for the year
MERGE INTO utl_d_aa.enrollments_log tgt
USING (SELECT rc.pidm,
              rc.term_code,
              rc.row_hash,
              rank() over(PARTITION BY rc.pidm, rc.acad_year ORDER BY rc.term_code DESC) AS yr_rank -- for reporting purposes, yr_rank will ONLY be valid/accurate when to_date = DATE '2099-12-31'
         FROM utl_d_aa.enrollments_log rc
        WHERE rc.acad_year = rec.acad_year
          AND rc.to_date = DATE '2099-12-31') src
ON (tgt.pidm = src.pidm AND tgt.term_code = src.term_code AND tgt.row_hash = src.row_hash)
WHEN MATCHED THEN
UPDATE SET tgt.yr_rank = src.yr_rank WHERE nvl(tgt.yr_rank, 0) <> nvl(src.yr_rank, 0);
v_count := SQL%ROWCOUNT;
COMMIT;
dbms_lock.sleep(0.5); -- pause half second
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE (yr_rank field) - ' || rec.acad_year || ' - ' || rec.report_number || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
END IF;
dbms_output.put_line(' --------- ');
END LOOP; -- c_terms
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
-- log any errors
IF error_log.count > 0 THEN
FOR i IN 1 .. error_log.count
LOOP
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(error_log(i), 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
END LOOP;
END IF;
EXCEPTION
WHEN OTHERS THEN
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
ads_etl.set_parallel_session('N'); -- Job is done. Turn parallelism off for this session.
END etl_aa_enrollments_log;

procedure etl_aa_retention_grads(jobnumber number, processid varchar2, processname varchar2) is
--
-- PURPOSE: Stages awarded graduation records by student and term to support retention and graduation analytics and reporting.
--
-- TABLE: utl_d_aa.retention_grads
--
-- UNIQUE INDEX: PIDM, TERM_CODE_GRAD
--
-- CONDITIONS:
-- Includes only degree records where the degree status is 'AW' (awarded) and the graduation term is populated.
-- Associates each degree record to its academic category by joining SATURN.SHRDGMR to SATURN.STVDEGC on degree code.
-- For students with multiple degree rows in the same graduation term, selects a single record per (student, grad term) preferring higher academic category (STVDEGC.ACAT_CODE), then the most recent graduation date.
-- If duplicates remain after those preferences, an arbitrary tie-breaker is applied to keep one record.
-- Inserts only (PIDM, TERM_CODE_GRAD) combinations that do not already exist in UTL_D_AA.RETENTION_GRADS; existing rows are left unchanged (no updates).
-- Sets ACTIVITY_DATE on inserted rows to the ETL run timestamp (current system date/time).
-- Processes the full population in a single pass (no explicit term or date range filtering).
--
-- URL: N/A

--DECLARE
--- PARAMS
v_etl_date DATE := SYSDATE;
v_msg      VARCHAR2(2000);
v_instance VARCHAR2(50) := upper('ALL'); -- inst from the jams job; used for determining instance
v_partition NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_count        NUMBER := 0;
v_delete_count NUMBER := 0;
v_insert_count NUMBER := 0;
v_elapsed      NUMBER := 0;
v_total_count  NUMBER := 0;
v_job_id       VARCHAR2(32);
v_proc         VARCHAR2(100) := 'etl_aa_retention_grads';
BEGIN
-- dbms_output.enable(buffer_size => NULL);
--
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
MERGE /*+ use_nl(src) */
INTO utl_d_aa.retention_grads tgt
USING (
       -- pick one degree row per (pidm, term_code_grad) - prefer higher acat_code, most recent grad_date
       SELECT src_inner.shrdgmr_pidm           AS pidm,
               src_inner.shrdgmr_term_code_grad AS term_code_grad,
               src_inner.shrdgmr_grad_date      AS grad_date,
               src_inner.shrdgmr_degc_code      AS degc_code,
               src_inner.stvdegc_acat_code      AS acat_code
         FROM (SELECT shrdgmr_pidm,
                       shrdgmr_term_code_grad,
                       shrdgmr_grad_date,
                       shrdgmr_degc_code,
                       stvdegc_acat_code,
                       rank() over(PARTITION BY shrdgmr_pidm, shrdgmr_term_code_grad ORDER BY stvdegc_acat_code DESC, shrdgmr_grad_date DESC, rownum) AS ranking
                  FROM saturn.shrdgmr
                  JOIN saturn.stvdegc
                    ON shrdgmr_degc_code = stvdegc_code
                 WHERE shrdgmr_degs_code = 'AW' -- only awarded degrees
                   AND shrdgmr_term_code_grad IS NOT NULL) src_inner
        WHERE src_inner.ranking = 1) src
ON (tgt.pidm = src.pidm AND tgt.term_code_grad = src.term_code_grad)
WHEN NOT MATCHED THEN
INSERT
(pidm,
 term_code_grad,
 grad_date,
 degc_code,
 acat_code,
 activity_date)
VALUES
(src.pidm,
 src.term_code_grad,
 src.grad_date,
 src.degc_code,
 src.acat_code,
 v_etl_date);
v_count := SQL%ROWCOUNT;
COMMIT;
dbms_lock.sleep(0.5); -- pause half second
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
-- log any errors
EXCEPTION
WHEN OTHERS THEN
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
RAISE;
END etl_aa_retention_grads;

END load_aa_etl_ret; 