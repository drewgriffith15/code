create or replace package load_aa_etl_ml is
-- below are machine learning procs that send data to zlighthouse_whs... 
procedure etl_aa_ml_crscompcrs_refresh (jobnumber number, processid varchar2, processname varchar2);
procedure etl_aa_ml_crscompstu_refresh (jobnumber number, processid varchar2, processname varchar2);
procedure etl_aa_ml_crscompprd_refresh (jobnumber number, processid varchar2, processname varchar2);
procedure etl_aa_ml_msgasgn_refresh (jobnumber number, processid varchar2, processname varchar2);
procedure etl_aa_ml_crscomptag_refresh (jobnumber number, processid varchar2, processname varchar2);
-- building data model -- the procedures run in this order or simultaneously
procedure etl_aa_ml_course_success (jobnumber NUMBER, processid VARCHAR2, processname VARCHAR2);
procedure etl_aa_ml_persistence (jobnumber NUMBER, processid VARCHAR2, processname VARCHAR2);
procedure etl_aa_ml_graduation (jobnumber NUMBER, processid VARCHAR2, processname VARCHAR2);
procedure etl_aa_ml_student_academics (jobnumber NUMBER, processid VARCHAR2, processname VARCHAR2, inst VARCHAR2, nmbr NUMBER);
procedure etl_aa_ml_student_financials (jobnumber NUMBER, processid VARCHAR2, processname VARCHAR2);
procedure etl_aa_ml_student_emails (jobnumber NUMBER, processid VARCHAR2, processname VARCHAR2);
procedure etl_aa_ml_student_assignments (jobnumber NUMBER, processid VARCHAR2, processname VARCHAR2); --- 20250609  WGRIFFITH2 initial release
procedure etl_aa_ml_student_assignments_agg (jobnumber NUMBER, processid VARCHAR2, processname VARCHAR2); --- 20250609  WGRIFFITH2 initial release
procedure etl_aa_ml_student_assignments_all (jobnumber NUMBER, processid VARCHAR2, processname VARCHAR2); --- 20250609  WGRIFFITH2 initial release
end load_aa_etl_ml;
/

create or replace package body load_aa_etl_ml is

procedure etl_aa_ml_graduation (jobnumber NUMBER, processid VARCHAR2, processname VARCHAR2) is
--
-- TABLE: utl_d_aa.ml_graduation
--
-- UNIQUE INDEX: term_code, pidm
--
-- PURPOSE: Tracks graduation status and enrollment outcomes for students in standard academic terms to support predictive modeling and graduation analysis.
--
-- CONDITIONS:
-- Processes run each term from zbtm.terms_by_group_v where the term is not a winter semester, the group code is 'STD', and the current date falls within seven days before the term start date and seven days after the term end date (for current terms).
-- For non-current terms, includes terms where the current date is between 180 days before the term start date and 180 days after the term end date, but only during non-business hours (between 6pm and 11pm).
-- For each term, only students enrolled in utl_d_aim.szrenrl for that term are considered.
-- Removes records for students who are no longer enrolled in the given term.
-- For each student and term, determines graduation status by joining saturn.shrdgmr and zbtm.terms_by_group_v, considering only standard terms and degrees with code 'AW'.
-- Graduation is counted if the awarded degree code is greater than or equal to the enrollment degree code (except for 'MDV', which uses degree-in-passing logic).
-- For 'MDV' degrees, counts as awarded if the degree code matches the enrollment degree code.
-- Only considers graduation records where the graduation term is on or after the student's last enrolled term and on or before the maximum term code for the same academic year and summer semester.
-- Excludes students with level codes 'AC' and 'IN' (which do not graduate at the college level), except for those with level code 'JD' in the summer semester.
-- For each student, selects only the highest-ranked graduation record based on earliest graduation term and highest degree category.
-- Sets actual_result to 1 if the student graduated, 0 if the student did not register for the next term after the cohort term end date, and NULL otherwise.
-- Updates or inserts records only if there are changes in level code, semester, or actual_result.
-- Records the activity date as the ETL run date for each update or insert.
-- Iterates through all qualifying terms and processes each term individually.
--
-- URL: N/A
--
--DECLARE
--- PARAMS
v_etl_date DATE := SYSDATE;
v_msg      VARCHAR2(2000);
v_instance VARCHAR2(50) := upper('L2CAN'); -- inst from the jams job; used for determining instance
v_partition NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
-- v_mod         NUMBER := 5; -- number of partitions to be created
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_aa_ml_graduation';
v_loop_count  NUMBER := 0; -- Variable to track the current loop iteration
v_total_loops NUMBER := 0; -- Variable to track the total number of loops
v_retry_count NUMBER := 0;
v_max_retries NUMBER := 3; -- number of retries for WAIT
v_wait_time   NUMBER := 120; -- seconds for WAIT
TYPE r_rec IS RECORD(
term_code  VARCHAR2(6),
group_code VARCHAR2(3),
end_date   DATE,
active     NUMBER);
TYPE t_rec IS TABLE OF r_rec;
v_rec t_rec;
CURSOR c_rec IS
-- Run current terms - ALWAYS
SELECT terms.term_code,
       terms.group_code,
       terms.end_date,
       CASE
       WHEN SYSDATE <= terms.end_date + 7 THEN
        1
       ELSE
        0
       END AS active
  FROM zbtm.terms_by_group_v terms
 WHERE 1 = 1
   AND terms.semester NOT IN ('WIN')
   AND terms.group_code IN ('STD')
   AND SYSDATE >= terms.start_date - 7
   AND SYSDATE <= terms.end_date + 7
UNION
-- Run non-current terms - **ONLY RUN DURING NON-BUSINESS HOURS** 
SELECT terms.term_code,
       terms.group_code,
       terms.end_date,
       CASE
       WHEN SYSDATE <= terms.end_date + 7 THEN
        1
       ELSE
        0
       END AS active
  FROM zbtm.terms_by_group_v terms
 WHERE 1 = 1
   AND terms.semester NOT IN ('WIN')
   AND terms.group_code IN ('STD')
   AND SYSDATE >= terms.start_date - 180
   AND SYSDATE <= terms.end_date + 180
   AND (to_char(SYSDATE, 'HH24') BETWEEN '18' AND '23')
 ORDER BY 1;
BEGIN
-- dbms_output.enable(buffer_size => NULL);
--
-- Calculate total number of loops
OPEN c_rec;
FETCH c_rec BULK COLLECT
INTO v_rec;
v_total_loops := v_rec.count;
CLOSE c_rec;
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
FOR rec IN c_rec
LOOP
v_loop_count := v_loop_count + 1; -- Increment loop count
v_count      := 0; -- reset count
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - Loop ' || v_loop_count || ' of ' || v_total_loops || ' - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- remove any students NOT enrolled anymore
IF rec.active = 1 THEN
DELETE FROM utl_d_aa.ml_graduation tgt
 WHERE tgt.term_code = rec.term_code
   AND NOT EXISTS (SELECT 1
          FROM utl_d_aim.szrenrl src
         WHERE src.term_code = tgt.term_code
           AND src.pidm = tgt.pidm);
v_count := SQL%ROWCOUNT;
COMMIT;
dbms_lock.sleep(1); -- pause
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'DELETE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
END IF;
-- Retry mechanism for handling deadlocks
LOOP
BEGIN
v_count := 0; --reset count
MERGE INTO utl_d_aa.ml_graduation tgt
USING (
-- CTE to define the cohort of students for the given term
WITH cohort AS
 (SELECT /*+ MATERIALIZE */
   szrenrl.term_code,
   szrenrl.acad_year,
   szrenrl.pidm,
   szrenrl.levl_code,
   szrenrl.semester,
   szrenrl.degc_code_1
    FROM utl_d_aim.szrenrl
   WHERE szrenrl.term_code = rec.term_code)
SELECT CASE
       WHEN src.pidm IS NOT NULL
            AND tgt.pidm IS NULL THEN
        'INSERT' -- new record to source, add to table
       WHEN src.pidm IS NOT NULL
            AND tgt.pidm IS NOT NULL THEN
        'UPDATE' -- record exists in both places 
       END AS control_state,
       src.term_code,
       src.pidm,
       src.levl_code,
       src.semester,
       src.actual_result,
       src.activity_date
  FROM (SELECT cohort.term_code,
               cohort.pidm,
               cohort.levl_code,
               cohort.semester,
               NULL AS predicted_result, -- ** do not update here ** 
               CASE
                WHEN shrdgmr_pidm IS NOT NULL THEN
                 1 -- they graduated, so count them as successful (thus removing them from the pool to chase)
                WHEN v_etl_date > rec.end_date
                     AND shrdgmr_pidm IS NULL THEN
                 0 -- if they still didn't regsister for the next term after the cohort term end date, then lock in the result
                ELSE
                 NULL
                END AS actual_result,
                v_etl_date AS activity_date
           FROM cohort
           JOIN saturn.stvdegc
             ON cohort.degc_code_1 = stvdegc.stvdegc_code
            AND (cohort.levl_code NOT IN ('AC', 'IN') -- these do not gradudate at the college level
                OR (cohort.levl_code = 'JD' AND cohort.semester = 'SUM')) -- results in 0 actual, so it gets excluded
         -- graduation check; using the same logic as the "ordained" definition in the pdb
           LEFT JOIN (SELECT shrdgmr_pidm,
                            shrdgmr_term_code_grad,
                            shrdgmr_levl_code,
                            shrdgmr_degc_code,
                            stvdegc_acat_code,
                            rank() over(PARTITION BY shrdgmr_pidm ORDER BY shrdgmr_term_code_grad ASC, stvdegc_acat_code DESC, rownum) ranking -- RESOLVE MULTIPLE DEGREES; we only need one row returned
                       FROM saturn.shrdgmr
                       JOIN cohort
                         ON cohort.pidm = shrdgmr_pidm
                       JOIN zbtm.terms_by_group_v terms
                         ON terms.term_code = shrdgmr_term_code_grad
                        AND terms.group_code IN ('STD') -- only get standard terms and med
                       JOIN saturn.stvdegc
                         ON shrdgmr_degc_code = stvdegc_code
                        AND shrdgmr_term_code_grad >= rec.term_code -- this needs to be >= the STUDENT last term enrolled; casting a wider net; gets handled in the lower query
                        AND shrdgmr_term_code_grad <= (SELECT MAX(tbg.term_code)
                                                         FROM zbtm.terms_by_group_v tbg
                                                        WHERE tbg.fa_proc_year = cohort.acad_year -- must be same year
                                                          AND tbg.semester = 'SUM') -- leave this 'SUM' hard-coded; that's our target timeframe; seeing if they have graduated by the end of the year
                       AND shrdgmr_degs_code = 'AW'
                     WHERE ((stvdegc_acat_code >= stvdegc.stvdegc_acat_code AND shrdgmr_degc_code <> 'MDV') -- if not MDV, the degree code has to be >= the enrollment degree code
                           OR (shrdgmr_degc_code = 'MDV' AND shrdgmr_degc_code = cohort.degc_code_1)) -- if MDV, degree in passing in effect, we want to count this as an awarded degree
                    ) grads
            ON grads.shrdgmr_pidm = cohort.pidm
           AND grads.ranking = 1) src
-- for the control state
  LEFT JOIN utl_d_aa.ml_graduation tgt
    ON tgt.term_code = src.term_code
   AND tgt.pidm = src.pidm
 WHERE 1 = 1
      -- for inserts or deletes...
   AND (((src.pidm IS NULL AND tgt.pidm IS NOT NULL) OR (src.pidm IS NOT NULL AND tgt.pidm IS NULL)) OR --
       -- for updates if any data has changed...
       nvl(src.levl_code, 'X') <> nvl(tgt.levl_code, 'X') OR --
       nvl(src.semester, 'X') <> nvl(tgt.semester, 'X') OR --        
       nvl(src.actual_result, -1) <> nvl(tgt.actual_result, -1))) src --
 ON (tgt.term_code = src.term_code AND tgt.pidm = src.pidm) --
 WHEN MATCHED THEN
UPDATE
   SET tgt.levl_code     = src.levl_code,
       tgt.semester      = src.semester,
       tgt.actual_result = src.actual_result,
       tgt.activity_date = src.activity_date
WHEN NOT MATCHED THEN
INSERT
(term_code,
 pidm,
 levl_code,
 semester,
 actual_result,
 activity_date)
VALUES
(src.term_code,
 src.pidm,
 src.levl_code,
 src.semester,
 src.actual_result,
 v_etl_date);
v_count := SQL%ROWCOUNT;
COMMIT;
dbms_lock.sleep(1); -- pause
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
EXIT; -- If successful, exit the retry loop
EXCEPTION
WHEN OTHERS THEN
IF SQLCODE = -60 THEN
-- Deadlock detected
v_retry_count := v_retry_count + 1;
IF v_retry_count > v_max_retries THEN
-- Log error for max retries
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := '!!!-00060: deadlock detected while waiting for resource. Max retries exceeded after ' || (v_max_retries * v_wait_time) || ' seconds';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
EXIT; -- Add EXIT here to break out of the loop when max retries exceeded
ELSE
-- Log retry attempt
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'Deadlock detected while waiting for resource - waiting ' || v_wait_time || ' seconds for retry attempt number ' || v_retry_count;
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'WARNING', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
dbms_lock.sleep(v_wait_time); -- Wait between retries; short wait because it will need to cycle through all the GTTs again
CONTINUE; -- Add CONTINUE to explicitly indicate loop continuation
END IF;
ELSE
-- Other errors
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
EXIT; -- Add EXIT here to break out of the loop for non-deadlock errors
END IF;
END;
END LOOP; -- end deadlock detection
dbms_output.put_line(' --------- ');
END LOOP; -- c_rec
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
-- log any errors
EXCEPTION
WHEN OTHERS THEN
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
/*--------------------------------------------CHANGE LOG----------------------------------------
VERSION  DATE        USERNAME    UPDATES
---     08-25-2025  WGRIFFITH2  --Initial release;  
------------------------------------------------------------------------------------------------*/
END etl_aa_ml_graduation;

procedure etl_aa_ml_student_assignments_all (jobnumber NUMBER, processid VARCHAR2, processname VARCHAR2) is
--DECLARE
--- PARAMS
v_etl_date    DATE := SYSDATE;
v_msg         VARCHAR2(2000);
v_instance    VARCHAR2(50) := upper('L2CAN'); -- inst from the jams job; used for determining instance
v_partition    NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_aa_ml_student_assignments_all';
v_loop_count  NUMBER := 0; -- Variable to track the current loop iteration
v_total_loops NUMBER := 0; -- Variable to track the total number of loops
v_retry_count NUMBER := 0;
v_max_retries NUMBER := 3; -- number of retries for WAIT
v_wait_time   NUMBER := 120; -- seconds for WAIT
TYPE r_rec IS RECORD(
term_code VARCHAR2(6),
dte       DATE);
TYPE t_rec IS TABLE OF r_rec;
v_rec t_rec;
CURSOR c_rec IS
SELECT DISTINCT cal.term_code,
                cal.dte
  FROM utl_d_aa.crscalendar cal
  JOIN zbtm.terms_by_group_v terms
    ON terms.term_code = cal.term_code
   AND terms.group_code IN ('STD')
   AND terms.semester NOT IN ('WIN')
   AND cal.ptrm_code IN ('R', '1A', '1B', '1C', '1D')
   AND cal.week_number <= 8 -- only push 8 weeks into MyStudents
   AND cal.dte = cal.week_end_date -- onlu get one row per week
   AND cal.dte + 1 < SYSDATE -- do not run day until it is complete      
   AND cal.dte >= trunc(SYSDATE - 7) -- return days back in case of latency   
 ORDER BY term_code DESC,
          dte       DESC;
BEGIN
-- dbms_output.enable(buffer_size => NULL);
--
-- Calculate total number of loops
OPEN c_rec;
FETCH c_rec BULK COLLECT
INTO v_rec;
v_total_loops := v_rec.count;
CLOSE c_rec;
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
FOR rec IN c_rec
LOOP
v_loop_count := v_loop_count + 1; -- Increment loop count
v_count      := 0; -- reset count
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - Loop ' || v_loop_count || ' of ' || v_total_loops || ' - ' || rec.term_code || ' - ' || rec.dte || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- Retry mechanism for handling deadlocks
LOOP
BEGIN
v_count := 0; --reset count
-- step 3: update the all-time summary columns using the data we just loaded...
MERGE INTO utl_d_aa.ml_student_assignments_all tgt
USING (
-- get the distinct pidm from step 1
WITH msa AS
 (SELECT /* + MATERIALIZE */
  DISTINCT pidm
    FROM utl_d_aa.ml_student_assignments msa
   WHERE msa.term_code = rec.term_code
     AND msa.dte = rec.dte),
-- get the max of all cumulative stats up to the dte in time per course of those above
msa_max AS
 (SELECT /* + MATERIALIZE */
   msa_max.term_code,
   msa_max.pidm,
   msa_max.crn,
   MAX(msa_max.points_earned) AS max_points_earned,
   MAX(msa_max.points_possible) AS max_points_possible,
   MAX(msa_max.assignments_submitted_ontime) AS max_assignments_submitted_ontime,
   MAX(msa_max.assignments_due) AS max_assignments_due
    FROM utl_d_aa.ml_student_assignments msa_max
    JOIN msa
      ON msa.pidm = msa_max.pidm
   WHERE msa_max.term_code <= rec.term_code -- calc all assignment data on the table that we have up to this point 
     AND msa_max.dte <= rec.dte -- calc all assignment data on the table that we have up to this point
   GROUP BY msa_max.term_code,
            msa_max.pidm,
            msa_max.crn)
SELECT tgt.term_code,
       tgt.pidm,
       tgt.crn,
       tgt.dte,
       tgt.user_id,
       tgt.course_id,
       tgt.course_section_id,
       msa_all.all_grade_earned,
       msa_all.all_assignments_submitted_ontime_pct
  FROM utl_d_aa.ml_student_assignments tgt
  JOIN msa
    ON msa.pidm = tgt.pidm
  JOIN (SELECT msa_max.pidm,
               round(SUM(max_points_earned) / SUM(max_points_possible), 4) AS all_grade_earned,
               round(SUM(max_assignments_submitted_ontime) / SUM(max_assignments_due), 4) AS all_assignments_submitted_ontime_pct
          FROM msa_max
         GROUP BY msa_max.pidm) msa_all
    ON msa_all.pidm = tgt.pidm
 WHERE tgt.term_code = rec.term_code -- DO NOT JOIN ON PTRM_CODE HERE
   AND tgt.dte = rec.dte) src ON (tgt.term_code = src.term_code AND tgt.crn = src.crn AND tgt.pidm = src.pidm AND tgt.dte = src.dte) WHEN MATCHED THEN
UPDATE
   SET tgt.all_grade_earned                     = src.all_grade_earned,
       tgt.all_assignments_submitted_ontime_pct = src.all_assignments_submitted_ontime_pct,
       tgt.activity_date                        = v_etl_date
 WHERE
-- Only update if the value is different 
 (nvl(tgt.all_grade_earned, -1) != nvl(src.all_grade_earned, -1) AND src.all_grade_earned IS NOT NULL)
 OR (nvl(tgt.all_assignments_submitted_ontime_pct, -1) != nvl(src.all_assignments_submitted_ontime_pct, -1) AND src.all_assignments_submitted_ontime_pct IS NOT NULL)
WHEN NOT MATCHED THEN
INSERT
(term_code,
 crn,
 pidm,
 user_id,
 course_id,
 course_section_id,
 dte,
 all_grade_earned,
 all_assignments_submitted_ontime_pct,
 activity_date)
VALUES
(src.term_code,
 src.crn,
 src.pidm,
 src.user_id,
 src.course_id,
 src.course_section_id,
 src.dte,
 src.all_grade_earned,
 src.all_assignments_submitted_ontime_pct,
 v_etl_date);
v_count := SQL%ROWCOUNT;
COMMIT;
dbms_lock.sleep(1); -- pause
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - Step 3 - ' || rec.term_code || ' - ' || rec.dte || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_lock.sleep(1); -- pause
EXIT; -- If successful, exit the retry loop
EXCEPTION
WHEN OTHERS THEN
IF SQLCODE = -60 THEN
-- Deadlock detected
v_retry_count := v_retry_count + 1;
IF v_retry_count > v_max_retries THEN
-- Log error for max retries
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := '!!!-00060: deadlock detected while waiting for resource. Max retries exceeded after ' || (v_max_retries * v_wait_time) || ' seconds';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
EXIT; -- Add EXIT here to break out of the loop when max retries exceeded
ELSE
-- Log retry attempt
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'Deadlock detected while waiting for resource - waiting ' || v_wait_time || ' seconds for retry attempt number ' || v_retry_count;
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'WARNING', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
dbms_lock.sleep(v_wait_time); -- Wait between retries; short wait because it will need to cycle through all the GTTs again
CONTINUE; -- Add CONTINUE to explicitly indicate loop continuation
END IF;
ELSE
-- Other errors
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
EXIT; -- Add EXIT here to break out of the loop for non-deadlock errors
END IF;
END;
END LOOP; -- end deadlock detection
dbms_output.put_line(' --------- ');
END LOOP; -- c_rec 
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
-- log any errors
EXCEPTION
WHEN OTHERS THEN
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
END etl_aa_ml_student_assignments_all;

procedure etl_aa_ml_student_assignments_agg (jobnumber NUMBER, processid VARCHAR2, processname VARCHAR2) is

--
-- PURPOSE: Produces weekly aggregated student assignment performance used for academic analytics and early‑alert monitoring in the ML_STUDENT_ASSIGNMENTS_AGG dataset.
--
-- TABLE: utl_d_aa.ml_student_assignments_agg
--
-- UNIQUE INDEX: TERM_CODE, CRN, PIDM, DTE
--
-- CONDITIONS:
-- Processes one weekly slice at a time based on academic calendar rows where the date represents the week-end date.
-- Includes only standard academic terms belonging to group STD and excludes the WIN (winter) semester.
-- Includes only parts of term R, 1A, 1B, 1C, and 1D.
-- Includes only calendar dates within the first eight academic weeks of a term.
-- Includes only dates older than yesterday to ensure the week is fully completed.
-- Includes only dates within the last seven days to allow for latency or missed runs.
-- Aggregates assignment activity from ML_STUDENT_ASSIGNMENTS for the matching TERM_CODE and DTE of the current loop iteration.
-- Sums points earned, points possible, missing assignments, missing points, and upcoming-week assignment metrics per student and date.
-- Calculates a grade percentage as total earned points divided by total possible points for the student on that date.
-- Computes the average days since last submission for each student on that date.
-- Joins detailed assignment rows to aggregated results to produce one aggregated result per (TERM_CODE, PIDM, DTE, CRN).
-- Runs a MERGE to update existing rows only when the aggregated metrics have changed.
-- Inserts new rows when no existing row matches the TERM_CODE, CRN, PIDM, and DTE key.
-- Loops through all eligible (TERM_CODE, DTE) pairs generated by the CRSCALENDAR and TERMS_BY_GROUP_V logic.
-- Retries the MERGE operation when a deadlock occurs, up to a defined retry limit.
-- Skips weekly slices that contain no assignment data for the corresponding TERM_CODE and DTE.
--
-- URL: N/A
--

--DECLARE 
v_etl_date    DATE := SYSDATE;
v_msg         VARCHAR2(2000);
v_instance    VARCHAR2(50) := upper('L2CAN');
v_partition   NUMBER := 0;
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_aa_ml_student_assignments_agg';
v_loop_count  NUMBER := 0; -- loop iteration
v_total_loops NUMBER := 0; -- total planned loops
v_retry_count NUMBER := 0;
v_max_retries NUMBER := 3; -- WAIT retries on ORA-00060
v_wait_time   NUMBER := 120; -- seconds between retries
v_src_exists  NUMBER := 0; -- existence precheck
-- -----------------------------------
-- Types / collections
-- -----------------------------------
TYPE r_rec IS RECORD(
term_code VARCHAR2(6),
dte       DATE);
TYPE t_rec IS TABLE OF r_rec;
v_rec t_rec;
-- -----------------------------------
-- Driving cursor for slices (term_code,dte)
-- -----------------------------------
CURSOR c_rec IS
SELECT DISTINCT cal.term_code,
                cal.dte
  FROM utl_d_aa.crscalendar cal
  JOIN zbtm.terms_by_group_v terms
    ON terms.term_code = cal.term_code
 WHERE terms.group_code IN ('STD')
   AND terms.semester NOT IN ('WIN')
   AND cal.ptrm_code IN ('R', '1A', '1B', '1C', '1D')
   AND cal.week_number <= 8 -- only first 8 weeks
   AND cal.dte = cal.week_end_date -- 1 row per week
   AND cal.dte + 1 < SYSDATE -- only completed days
   AND cal.dte >= trunc(SYSDATE - 7) -- lookback for latency
;
BEGIN
-- -----------------------------------
-- Pre-calc total loops for logging
-- -----------------------------------
OPEN c_rec;
FETCH c_rec BULK COLLECT
INTO v_rec;
v_total_loops := v_rec.count;
CLOSE c_rec;
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
-- -----------------------------------
-- Main loop over driving cursor
-- (this FOR implicitly opens its own cursor instance)
-- -----------------------------------
FOR rec IN c_rec
LOOP
v_loop_count  := v_loop_count + 1;
v_count       := 0;
v_retry_count := 0; -- reset retries per slice
dbms_lock.sleep(1);
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - Loop ' || v_loop_count || ' of ' || v_total_loops || ' - ' || rec.term_code || ' - ' || to_char(rec.dte, 'YYYY-MM-DD') || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' ||
             to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- -----------------------------------
-- Fast-path existence check: skip slice if no source rows
-- -----------------------------------
SELECT /*+ RESULT_CACHE */
 COUNT(1)
  INTO v_src_exists
  FROM utl_d_aa.ml_student_assignments s
 WHERE s.term_code = rec.term_code
   AND s.dte = rec.dte;
IF v_src_exists = 0 THEN
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'SKIP - no source rows for ' || rec.term_code || ' - ' || to_char(rec.dte, 'YYYY-MM-DD');
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
dbms_output.put_line(' --------- ');
CONTINUE;
END IF;
-- -----------------------------------
-- Retry loop (deadlock handling)
-- -----------------------------------
<<retry_merge>>
LOOP
BEGIN
v_count := 0;
-- ==============================================================
-- Optimized MERGE:
--   * INLINE aggregator (no TEMP TABLE TRANSFORMATION)
--   * LEADING(src) + USE_NL(tgt)
--   * Forbid HASH JOIN / BLOOM / PARTIAL JOIN FILTER
--   * Probe target unique index on merge key
-- ==============================================================
MERGE /*+
		 LEADING(src)
		 USE_NL(tgt)
		 NO_USE_HASH(src) NO_USE_HASH(tgt)
		 NO_HASH_JOIN
		 NO_BLOOM_FILTER
		 NO_PARTIAL_JOIN_FILTER
		 INDEX(tgt ML_STUDENT_ASSIGNMENTS_AGG_UNIQUE_INDX)
		 INLINE
	  */
INTO utl_d_aa.ml_student_assignments_agg tgt
USING (SELECT s.term_code,
              s.crn,
              s.pidm,
              s.user_id,
              s.course_id,
              s.course_section_id,
              s.dte,
              round(CASE
                    WHEN SUM(a.points_possible) = 0 THEN
                     NULL
                    ELSE
                     SUM(a.points_earned) / SUM(a.points_possible)
                    END, 4) AS agg_grade_earned,
              SUM(a.missing_assignments) AS agg_missing_assignments,
              SUM(a.missing_points) AS agg_missing_points,
              SUM(a.assignments_next7d) AS agg_assignments_next7d,
              SUM(a.points_possible_next7d) AS agg_points_possible_next7d,
              round(AVG(a.days_since_last_submission), 0) AS agg_days_since_last_submission,
              v_etl_date AS activity_date
         FROM utl_d_aa.ml_student_assignments a
         JOIN utl_d_aa.ml_student_assignments s
           ON s.term_code = a.term_code
          AND s.pidm = a.pidm
          AND s.dte = a.dte
        WHERE a.term_code = rec.term_code
          AND a.dte = rec.dte
          AND s.term_code = rec.term_code
          AND s.dte = rec.dte
        GROUP BY s.term_code,
                 s.crn,
                 s.pidm,
                 s.user_id,
                 s.course_id,
                 s.course_section_id,
                 s.dte) src
ON (tgt.term_code = src.term_code AND tgt.crn = src.crn AND tgt.pidm = src.pidm AND tgt.dte = src.dte)
WHEN MATCHED THEN
UPDATE
   SET tgt.user_id                        = src.user_id,
       tgt.course_id                      = src.course_id,
       tgt.course_section_id              = src.course_section_id,
       tgt.agg_grade_earned               = src.agg_grade_earned,
       tgt.agg_missing_assignments        = src.agg_missing_assignments,
       tgt.agg_missing_points             = src.agg_missing_points,
       tgt.agg_assignments_next7d         = src.agg_assignments_next7d,
       tgt.agg_points_possible_next7d     = src.agg_points_possible_next7d,
       tgt.agg_days_since_last_submission = src.agg_days_since_last_submission,
       tgt.activity_date                  = src.activity_date
 WHERE (nvl(tgt.agg_grade_earned, -1) != nvl(src.agg_grade_earned, -1) AND src.agg_grade_earned IS NOT NULL)
    OR (nvl(tgt.agg_days_since_last_submission, -1) != nvl(src.agg_days_since_last_submission, -1) AND src.agg_days_since_last_submission IS NOT NULL)
    OR (nvl(tgt.agg_missing_points, -1) != nvl(src.agg_missing_points, -1) AND src.agg_missing_points IS NOT NULL)
WHEN NOT MATCHED THEN
INSERT
(term_code,
 crn,
 pidm,
 user_id,
 course_id,
 course_section_id,
 dte,
 agg_grade_earned,
 agg_missing_assignments,
 agg_missing_points,
 agg_assignments_next7d,
 agg_points_possible_next7d,
 agg_days_since_last_submission,
 activity_date)
VALUES
(src.term_code,
 src.crn,
 src.pidm,
 src.user_id,
 src.course_id,
 src.course_section_id,
 src.dte,
 src.agg_grade_earned,
 src.agg_missing_assignments,
 src.agg_missing_points,
 src.agg_assignments_next7d,
 src.agg_points_possible_next7d,
 src.agg_days_since_last_submission,
 src.activity_date);
v_count := SQL%ROWCOUNT;
COMMIT;
dbms_lock.sleep(1);
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || rec.term_code || ' - ' || to_char(rec.dte, 'YYYY-MM-DD') || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count;
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
EXIT; -- success
EXCEPTION
WHEN OTHERS THEN
IF SQLCODE = -60 THEN
-- ORA-00060 deadlock
v_retry_count := v_retry_count + 1;
IF v_retry_count > v_max_retries THEN
dbms_lock.sleep(1);
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := '!!!-00060: deadlock; max retries exceeded after ' || (v_max_retries * v_wait_time) || ' seconds';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
EXIT retry_merge;
ELSE
dbms_lock.sleep(1);
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'Deadlock; waiting ' || v_wait_time || 's for retry #' || v_retry_count;
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'WARNING', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
dbms_lock.sleep(v_wait_time);
-- continue loop
END IF;
ELSE
dbms_lock.sleep(1);
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
EXIT retry_merge;
END IF;
END;
END LOOP; -- retry_merge
dbms_output.put_line(' --------- ');
END LOOP; -- rec
dbms_lock.sleep(1);
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
EXCEPTION
WHEN OTHERS THEN
dbms_lock.sleep(1);
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
END etl_aa_ml_student_assignments_agg; 

procedure etl_aa_ml_student_assignments (jobnumber NUMBER, processid VARCHAR2, processname VARCHAR2) is
--DECLARE
--- PARAMS
v_etl_date    DATE := SYSDATE;
v_msg         VARCHAR2(2000);
v_instance    VARCHAR2(50) := upper('L2CAN'); -- inst from the jams job; used for determining instance
v_partition   NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_aa_ml_student_assignments';
v_loop_count  NUMBER := 0; -- Variable to track the current loop iteration
v_total_loops NUMBER := 0; -- Variable to track the total number of loops
v_retry_count NUMBER := 0;
v_max_retries NUMBER := 3; -- number of retries for WAIT
v_wait_time   NUMBER := 120; -- seconds for WAIT
TYPE r_rec IS RECORD(
term_code VARCHAR2(6),
dte       DATE);
TYPE t_rec IS TABLE OF r_rec;
v_rec t_rec;
CURSOR c_rec IS
-- always run current term dates
SELECT DISTINCT cal.term_code,
                cal.dte
  FROM utl_d_aa.crscalendar cal
  JOIN zbtm.terms_by_group_v terms
    ON terms.term_code = cal.term_code
   AND terms.group_code IN ('STD')
   AND terms.semester NOT IN ('WIN')
   AND cal.ptrm_code IN ('R', '1A', '1B', '1C', '1D')
   AND cal.week_number <= 8 -- only push 8 weeks into MyStudents
   AND cal.dte = cal.week_end_date -- onlu get one row per week
   AND cal.dte + 1 < SYSDATE -- do not run day until it is complete      
   AND cal.dte >= trunc(SYSDATE - 7); -- return days back in case of latency    
BEGIN
-- dbms_output.enable(buffer_size => NULL);
--
-- Calculate total number of loops
OPEN c_rec;
FETCH c_rec BULK COLLECT
INTO v_rec;
v_total_loops := v_rec.count;
CLOSE c_rec;
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
FOR rec IN c_rec
LOOP
v_loop_count := v_loop_count + 1; -- Increment loop count
v_count      := 0; -- reset count
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - Loop ' || v_loop_count || ' of ' || v_total_loops || ' - ' || rec.term_code || ' - ' || rec.dte || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- Retry mechanism for handling deadlocks
LOOP
BEGIN
v_count := 0; --reset count
-- first iteration of this merge loads the assignment data for the course itself; step 2-3 does the aggregations on all-time calcs
MERGE INTO utl_d_aa.ml_student_assignments tgt
USING (SELECT /*+ LEADING(se sca adt) USE_NL(sca adt) */
        rec.term_code        AS term_code,
        se.crn,
        se.pidm,
        se.user_id,
        se.course_id,
        se.course_section_id,
        rec.dte              AS dte,
        -- assignments
        SUM(CASE
            WHEN sca.submitted_date IS NOT NULL
                 AND sca.submitted_date < rec.dte THEN
             1
            WHEN sca.graded_date IS NOT NULL
                 AND sca.graded_date < rec.dte THEN
             1
            WHEN coalesce(sca.due_date, adt.dte, se.end_date) < rec.dte THEN
             1
            ELSE
             NULL
            END) AS assignments_due,
        SUM(CASE
            WHEN sca.submitted_date IS NOT NULL
                 AND sca.submitted_date < rec.dte THEN
             1
            WHEN sca.graded_date IS NOT NULL
                 AND sca.graded_date < rec.dte THEN
             1
            ELSE
             NULL
            END) AS assignments_submitted,
        SUM(CASE
            WHEN coalesce(sca.due_date, adt.dte, se.end_date) < rec.dte -- beyond due date
                 AND sca.submitted_date IS NULL -- no submission
                 AND sca.graded_date IS NULL -- no grade 
             THEN
             0 -- missing assignment (live situation)
            WHEN coalesce(sca.due_date, adt.dte, se.end_date) < rec.dte -- beyond due date
                 AND sca.submitted_date IS NULL -- no submission
                 AND sca.graded_date IS NOT NULL -- graded 
                 AND nvl(sca.score, 0) = 0 -- graded with zero as placeholder
             THEN
             0 -- missing assignment (live situation)
            WHEN coalesce(sca.due_date, adt.dte, se.end_date) < rec.dte -- beyond due date
                 AND (sca.submitted_date > coalesce(sca.due_date, adt.dte, se.end_date) -- submitted late 
                      OR sca.submitted_date IS NULL) -- or not submitted at all
                 AND sca.graded_date >= rec.dte -- grade found in the future
             THEN
             0 -- missing assignment (historical situation) 
            WHEN coalesce(sca.due_date, adt.dte, se.end_date) < rec.dte -- beyond due date
                 AND sca.graded_date > coalesce(sca.due_date, adt.dte, se.end_date) -- submitted late 
                 AND nvl(sca.score, 0) = 0 -- graded with zero as placeholder
                 AND sca.graded_date >= rec.dte -- grade found in the future
             THEN
             0 -- missing assignment (historical situation) 
            WHEN sca.submitted_date < sca.due_date
                 AND sca.submitted_date < rec.dte THEN
             1
            WHEN sca.graded_date < sca.due_date
                 AND sca.graded_date < rec.dte THEN
             1
            WHEN sca.due_date IS NULL
                 AND sca.graded_date <= adt.dte
                 AND sca.graded_date < rec.dte THEN
             1
            ELSE
             NULL
            END) AS assignments_submitted_ontime,
        round(SUM(CASE
                  WHEN coalesce(sca.due_date, adt.dte, se.end_date) < rec.dte
                       AND sca.submitted_date IS NULL
                       AND sca.graded_date IS NULL THEN
                   0
                  WHEN coalesce(sca.due_date, adt.dte, se.end_date) < rec.dte
                       AND sca.submitted_date IS NULL
                       AND sca.graded_date IS NOT NULL
                       AND nvl(sca.score, 0) = 0 THEN
                   0
                  WHEN coalesce(sca.due_date, adt.dte, se.end_date) < rec.dte
                       AND (sca.submitted_date > coalesce(sca.due_date, adt.dte, se.end_date) OR sca.submitted_date IS NULL)
                       AND sca.graded_date >= rec.dte THEN
                   0
                  WHEN coalesce(sca.due_date, adt.dte, se.end_date) < rec.dte
                       AND sca.graded_date > coalesce(sca.due_date, adt.dte, se.end_date)
                       AND nvl(sca.score, 0) = 0
                       AND sca.graded_date >= rec.dte THEN
                   0
                  WHEN sca.submitted_date < sca.due_date
                       AND sca.submitted_date < rec.dte THEN
                   1
                  WHEN sca.graded_date < sca.due_date
                       AND sca.graded_date < rec.dte THEN
                   1
                  WHEN sca.due_date IS NULL
                       AND sca.graded_date <= adt.dte
                       AND sca.graded_date < rec.dte THEN
                   1
                  ELSE
                   NULL
                  END) / SUM(CASE
                             WHEN sca.submitted_date IS NOT NULL
                                  AND sca.submitted_date < rec.dte THEN
                              1
                             WHEN sca.graded_date IS NOT NULL
                                  AND sca.graded_date < rec.dte THEN
                              1
                             WHEN coalesce(sca.due_date, adt.dte, se.end_date) < rec.dte THEN
                              1
                             ELSE
                              NULL
                             END), 4) AS assignments_submitted_ontime_pct,
        nvl(round(SUM(CASE
                      WHEN sca.submitted_date IS NOT NULL
                           AND sca.submitted_date < rec.dte THEN
                       1
                      WHEN sca.graded_date IS NOT NULL
                           AND sca.graded_date < rec.dte THEN
                       1
                      ELSE
                       NULL
                      END) / COUNT(sca.assignment_id), 4), 0) AS assignments_progress,
        nvl(round((SUM(CASE
                       WHEN sca.submitted_date IS NOT NULL
                            AND sca.submitted_date < rec.dte THEN
                        1
                       WHEN sca.graded_date IS NOT NULL
                            AND sca.graded_date < rec.dte THEN
                        1
                       ELSE
                        NULL
                       END) / COUNT(sca.assignment_id)) - nvl((SUM(CASE
                                                                   WHEN coalesce(sca.due_date, adt.dte, se.end_date) < rec.dte THEN
                                                                    1
                                                                   ELSE
                                                                    NULL
                                                                   END) / COUNT(sca.assignment_id)), 0), 4), 0) AS assignments_progress_delta,
        COUNT(sca.assignment_id) AS assignments_total,
        -- points
        SUM(CASE
            WHEN sca.submitted_date IS NOT NULL
                 AND sca.submitted_date < rec.dte THEN
             sca.points_possible
            WHEN sca.graded_date IS NOT NULL
                 AND sca.graded_date < rec.dte THEN
             sca.points_possible
            WHEN coalesce(sca.due_date, adt.dte, se.end_date) < rec.dte THEN
             sca.points_possible
            ELSE
             NULL
            END) AS points_due,
        SUM(CASE
            WHEN sca.submitted_date IS NOT NULL
                 AND sca.submitted_date < rec.dte THEN
             sca.points_possible
            WHEN sca.graded_date IS NOT NULL
                 AND sca.graded_date < rec.dte THEN
             sca.points_possible
            ELSE
             0
            END) AS points_submitted,
        SUM(CASE
            WHEN coalesce(sca.due_date, adt.dte, se.end_date) < rec.dte
                 AND sca.submitted_date IS NULL
                 AND sca.graded_date IS NULL THEN
             0
            WHEN coalesce(sca.due_date, adt.dte, se.end_date) < rec.dte
                 AND sca.submitted_date IS NULL
                 AND sca.graded_date IS NOT NULL
                 AND nvl(sca.score, 0) = 0 THEN
             0
            WHEN coalesce(sca.due_date, adt.dte, se.end_date) < rec.dte
                 AND (sca.submitted_date > coalesce(sca.due_date, adt.dte, se.end_date) OR sca.submitted_date IS NULL)
                 AND sca.graded_date >= rec.dte THEN
             0
            WHEN coalesce(sca.due_date, adt.dte, se.end_date) < rec.dte
                 AND sca.graded_date > coalesce(sca.due_date, adt.dte, se.end_date)
                 AND nvl(sca.score, 0) = 0
                 AND sca.graded_date >= rec.dte THEN
             0
            WHEN sca.submitted_date < sca.due_date
                 AND sca.submitted_date < rec.dte THEN
             sca.points_possible
            WHEN sca.graded_date < sca.due_date
                 AND sca.graded_date < rec.dte THEN
             sca.points_possible
            WHEN sca.due_date IS NULL
                 AND sca.graded_date <= adt.dte
                 AND sca.graded_date < rec.dte THEN
             sca.points_possible
            ELSE
             NULL
            END) AS points_submitted_ontime,
        round(SUM(CASE
                  WHEN coalesce(sca.due_date, adt.dte, se.end_date) < rec.dte
                       AND sca.submitted_date IS NULL
                       AND sca.graded_date IS NULL THEN
                   0
                  WHEN coalesce(sca.due_date, adt.dte, se.end_date) < rec.dte
                       AND sca.submitted_date IS NULL
                       AND sca.graded_date IS NOT NULL
                       AND nvl(sca.score, 0) = 0 THEN
                   0
                  WHEN coalesce(sca.due_date, adt.dte, se.end_date) < rec.dte
                       AND (sca.submitted_date > coalesce(sca.due_date, adt.dte, se.end_date) OR sca.submitted_date IS NULL)
                       AND sca.graded_date >= rec.dte THEN
                   0
                  WHEN coalesce(sca.due_date, adt.dte, se.end_date) < rec.dte
                       AND sca.graded_date > coalesce(sca.due_date, adt.dte, se.end_date)
                       AND nvl(sca.score, 0) = 0
                       AND sca.graded_date >= rec.dte THEN
                   0
                  WHEN sca.submitted_date < sca.due_date
                       AND sca.submitted_date < rec.dte THEN
                   sca.points_possible
                  WHEN sca.graded_date < sca.due_date
                       AND sca.graded_date < rec.dte THEN
                   sca.points_possible
                  WHEN sca.due_date IS NULL
                       AND sca.graded_date <= adt.dte
                       AND sca.graded_date < rec.dte THEN
                   sca.points_possible
                  ELSE
                   NULL
                  END) / SUM(CASE
                             WHEN sca.submitted_date IS NOT NULL
                                  AND sca.submitted_date < rec.dte THEN
                              sca.points_possible
                             WHEN sca.graded_date IS NOT NULL
                                  AND sca.graded_date < rec.dte THEN
                              sca.points_possible
                             WHEN coalesce(sca.due_date, adt.dte, se.end_date) < rec.dte THEN
                              sca.points_possible
                             ELSE
                              NULL
                             END), 4) AS points_submitted_ontime_pct,
        round(SUM(CASE
                  WHEN coalesce(sca.due_date, adt.dte, se.end_date) < rec.dte
                       AND sca.submitted_date IS NULL
                       AND sca.graded_date IS NULL THEN
                   0
                  WHEN coalesce(sca.due_date, adt.dte, se.end_date) < rec.dte
                       AND sca.submitted_date IS NULL
                       AND sca.graded_date IS NOT NULL
                       AND nvl(sca.score, 0) = 0 THEN
                   0
                  WHEN coalesce(sca.due_date, adt.dte, se.end_date) < rec.dte
                       AND (sca.submitted_date > coalesce(sca.due_date, adt.dte, se.end_date) OR sca.submitted_date IS NULL)
                       AND sca.graded_date >= rec.dte THEN
                   0
                  WHEN coalesce(sca.due_date, adt.dte, se.end_date) < rec.dte
                       AND sca.graded_date > coalesce(sca.due_date, adt.dte, se.end_date)
                       AND nvl(sca.score, 0) = 0
                       AND sca.graded_date >= rec.dte THEN
                   0
                  WHEN coalesce(sca.graded_date, sca.due_date, adt.dte, se.end_date) < rec.dte THEN
                   nvl(sca.score, 0)
                  ELSE
                   NULL
                  END), 0) AS points_earned,
        round(SUM(CASE
                  WHEN coalesce(sca.due_date, adt.dte, se.end_date) < rec.dte
                       AND sca.submitted_date IS NULL
                       AND sca.graded_date IS NULL THEN
                   sca.points_possible
                  WHEN coalesce(sca.due_date, adt.dte, se.end_date) < rec.dte
                       AND sca.submitted_date IS NULL
                       AND sca.graded_date IS NOT NULL
                       AND nvl(sca.score, 0) = 0 THEN
                   sca.points_possible
                  WHEN coalesce(sca.due_date, adt.dte, se.end_date) < rec.dte
                       AND (sca.submitted_date > coalesce(sca.due_date, adt.dte, se.end_date) OR sca.submitted_date IS NULL)
                       AND sca.graded_date >= rec.dte THEN
                   sca.points_possible
                  WHEN coalesce(sca.due_date, adt.dte, se.end_date) < rec.dte
                       AND sca.graded_date > coalesce(sca.due_date, adt.dte, se.end_date)
                       AND nvl(sca.score, 0) = 0
                       AND sca.graded_date >= rec.dte THEN
                   sca.points_possible
                  WHEN coalesce(sca.graded_date, adt.dte, se.end_date) < rec.dte
                       AND sca.graded_date IS NOT NULL THEN
                   sca.points_possible
                  ELSE
                   NULL
                  END), 0) AS points_possible,
        round(SUM(CASE
                  WHEN coalesce(sca.due_date, adt.dte, se.end_date) < rec.dte
                       AND sca.submitted_date IS NULL
                       AND sca.graded_date IS NULL THEN
                   0
                  WHEN coalesce(sca.due_date, adt.dte, se.end_date) < rec.dte
                       AND sca.submitted_date IS NULL
                       AND sca.graded_date IS NOT NULL
                       AND nvl(sca.score, 0) = 0 THEN
                   0
                  WHEN coalesce(sca.due_date, adt.dte, se.end_date) < rec.dte
                       AND (sca.submitted_date > coalesce(sca.due_date, adt.dte, se.end_date) OR sca.submitted_date IS NULL)
                       AND sca.graded_date >= rec.dte THEN
                   0
                  WHEN coalesce(sca.due_date, adt.dte, se.end_date) < rec.dte
                       AND sca.graded_date > coalesce(sca.due_date, adt.dte, se.end_date)
                       AND nvl(sca.score, 0) = 0
                       AND sca.graded_date >= rec.dte THEN
                   0
                  WHEN coalesce(sca.graded_date, sca.due_date, adt.dte, se.end_date) < rec.dte THEN
                   nvl(sca.score, 0)
                  ELSE
                   NULL
                  END) / SUM(CASE
                             WHEN coalesce(sca.due_date, adt.dte, se.end_date) < rec.dte
                                  AND sca.submitted_date IS NULL
                                  AND sca.graded_date IS NULL THEN
                              sca.points_possible
                             WHEN coalesce(sca.due_date, adt.dte, se.end_date) < rec.dte
                                  AND sca.submitted_date IS NULL
                                  AND sca.graded_date IS NOT NULL
                                  AND nvl(sca.score, 0) = 0 THEN
                              sca.points_possible
                             WHEN coalesce(sca.due_date, adt.dte, se.end_date) < rec.dte
                                  AND (sca.submitted_date > coalesce(sca.due_date, adt.dte, se.end_date) OR sca.submitted_date IS NULL)
                                  AND sca.graded_date >= rec.dte THEN
                              sca.points_possible
                             WHEN coalesce(sca.due_date, adt.dte, se.end_date) < rec.dte
                                  AND sca.graded_date > coalesce(sca.due_date, adt.dte, se.end_date)
                                  AND nvl(sca.score, 0) = 0
                                  AND sca.graded_date >= rec.dte THEN
                              sca.points_possible
                             WHEN coalesce(sca.graded_date, adt.dte, se.end_date) < rec.dte
                                  AND sca.graded_date IS NOT NULL THEN
                              sca.points_possible
                             ELSE
                              NULL
                             END), 4) AS grade_earned,
        nvl(round(SUM(CASE
                      WHEN sca.submitted_date IS NOT NULL
                           AND sca.submitted_date < rec.dte THEN
                       sca.points_possible
                      WHEN sca.graded_date IS NOT NULL
                           AND sca.graded_date < rec.dte THEN
                       sca.points_possible
                      ELSE
                       NULL
                      END) / SUM(sca.points_possible), 4), 0) AS points_progress,
        nvl(round((SUM(CASE
                       WHEN sca.submitted_date IS NOT NULL
                            AND sca.submitted_date < rec.dte THEN
                        sca.points_possible
                       WHEN sca.graded_date IS NOT NULL
                            AND sca.graded_date < rec.dte THEN
                        sca.points_possible
                       ELSE
                        NULL
                       END) / SUM(sca.points_possible)) - nvl((SUM(CASE
                                                                   WHEN coalesce(sca.due_date, adt.dte, se.end_date) < rec.dte THEN
                                                                    sca.points_possible
                                                                   ELSE
                                                                    NULL
                                                                   END) / SUM(sca.points_possible)), 0), 4), 0) AS points_progress_delta,
        SUM(sca.points_possible) AS points_total,
        -- 7d summaries
        SUM(CASE
            WHEN sca.submitted_date IS NOT NULL
                 AND sca.submitted_date BETWEEN rec.dte - 7 AND rec.dte THEN
             1
            WHEN sca.graded_date IS NOT NULL
                 AND sca.graded_date BETWEEN rec.dte - 7 AND rec.dte THEN
             1
            ELSE
             0
            END) AS assignments_submitted_7d,
        SUM(CASE
            WHEN sca.submitted_date IS NOT NULL
                 AND sca.submitted_date BETWEEN rec.dte - 7 AND rec.dte THEN
             sca.points_possible
            WHEN sca.graded_date IS NOT NULL
                 AND sca.graded_date BETWEEN rec.dte - 7 AND rec.dte THEN
             sca.points_possible
            ELSE
             0
            END) AS points_submitted_7d,
        -- missing assignments and upcoming assignments tally
        SUM(CASE
            WHEN coalesce(sca.due_date, adt.dte, se.end_date) < rec.dte
                 AND sca.submitted_date IS NULL
                 AND sca.graded_date IS NULL THEN
             1
            WHEN coalesce(sca.due_date, adt.dte, se.end_date) < rec.dte
                 AND sca.submitted_date IS NULL
                 AND sca.graded_date IS NOT NULL
                 AND nvl(sca.score, 0) = 0 THEN
             1
            WHEN coalesce(sca.due_date, adt.dte, se.end_date) < rec.dte
                 AND (sca.submitted_date > coalesce(sca.due_date, adt.dte, se.end_date) OR sca.submitted_date IS NULL)
                 AND sca.graded_date >= rec.dte THEN
             1
            WHEN coalesce(sca.due_date, adt.dte, se.end_date) < rec.dte
                 AND sca.graded_date > coalesce(sca.due_date, adt.dte, se.end_date)
                 AND nvl(sca.score, 0) = 0
                 AND sca.graded_date >= rec.dte THEN
             1
            ELSE
             0
            END) AS missing_assignments,
        SUM(CASE
            WHEN coalesce(sca.due_date, adt.dte, se.end_date) < rec.dte
                 AND sca.submitted_date IS NULL
                 AND sca.graded_date IS NULL THEN
             sca.points_possible
            WHEN coalesce(sca.due_date, adt.dte, se.end_date) < rec.dte
                 AND sca.submitted_date IS NULL
                 AND sca.graded_date IS NOT NULL
                 AND nvl(sca.score, 0) = 0 THEN
             sca.points_possible
            WHEN coalesce(sca.due_date, adt.dte, se.end_date) < rec.dte
                 AND (sca.submitted_date > coalesce(sca.due_date, adt.dte, se.end_date) OR sca.submitted_date IS NULL)
                 AND sca.graded_date >= rec.dte THEN
             sca.points_possible
            WHEN coalesce(sca.due_date, adt.dte, se.end_date) < rec.dte
                 AND sca.graded_date > coalesce(sca.due_date, adt.dte, se.end_date)
                 AND nvl(sca.score, 0) = 0
                 AND sca.graded_date >= rec.dte THEN
             sca.points_possible
            ELSE
             0
            END) AS missing_points,
        SUM(CASE
            WHEN coalesce(sca.due_date, sca.cached_due_date, adt.dte, se.end_date) > rec.dte
                 AND coalesce(sca.due_date, sca.cached_due_date, adt.dte, se.end_date) <= rec.dte + 7 THEN
             1
            ELSE
             0
            END) AS assignments_next7d,
        SUM(CASE
            WHEN coalesce(sca.due_date, sca.cached_due_date, adt.dte, se.end_date) > rec.dte
                 AND coalesce(sca.due_date, sca.cached_due_date, adt.dte, se.end_date) <= rec.dte + 7 THEN
             sca.points_possible
            ELSE
             0
            END) AS points_possible_next7d,
        floor(nvl(rec.dte + 1 - (MAX(CASE
                                     WHEN sca.submitted_date IS NULL
                                          AND sca.graded_date IS NULL
                                          AND rec.dte < se.start_date THEN
                                      se.start_date
                                     WHEN sca.submitted_date IS NOT NULL
                                          AND sca.submitted_date < rec.dte THEN
                                      CAST(sca.submitted_date AS DATE)
                                     WHEN sca.graded_date IS NOT NULL
                                          AND nvl(sca.score, 0) > 0
                                          AND sca.graded_date < rec.dte THEN
                                      CAST(sca.graded_date AS DATE)
                                     ELSE
                                      NULL
                                     END)), 0)) AS days_since_last_submission,
        v_etl_date AS activity_date
         FROM utl_d_lms.student_enrollments se
         JOIN utl_d_lms.student_assignments sca
           ON sca.instance = se.instance
          AND sca.course_section_id = se.course_section_id
          AND sca.user_id = se.user_id
          AND se.instance = v_instance
          AND se.term_code = rec.term_code
          AND sca.points_possible > 0
         LEFT JOIN /*+ INDEX(adt ASSIGNMENTS_DATES_INDX1) */
       utl_d_lms.assignments_dates adt
           ON adt.instance = sca.instance
          AND adt.course_section_id = sca.course_section_id
          AND adt.assignment_id = sca.assignment_id
          AND adt.date_field = 'effective_grade_date'
        GROUP BY se.crn,
                 se.pidm,
                 se.user_id,
                 se.course_id,
                 se.course_section_id,
                 rec.term_code,
                 rec.dte) src
ON (tgt.term_code = src.term_code AND tgt.crn = src.crn AND tgt.pidm = src.pidm AND tgt.dte = src.dte)
WHEN MATCHED THEN
UPDATE
   SET tgt.user_id                          = src.user_id,
       tgt.course_id                        = src.course_id,
       tgt.course_section_id                = src.course_section_id,
       tgt.assignments_due                  = src.assignments_due,
       tgt.assignments_submitted            = src.assignments_submitted,
       tgt.assignments_submitted_ontime     = src.assignments_submitted_ontime,
       tgt.assignments_submitted_ontime_pct = src.assignments_submitted_ontime_pct,
       tgt.assignments_progress             = src.assignments_progress,
       tgt.assignments_progress_delta       = src.assignments_progress_delta,
       tgt.assignments_total                = src.assignments_total,
       tgt.points_due                       = src.points_due,
       tgt.points_submitted                 = src.points_submitted,
       tgt.points_submitted_ontime          = src.points_submitted_ontime,
       tgt.points_submitted_ontime_pct      = src.points_submitted_ontime_pct,
       tgt.points_earned                    = src.points_earned,
       tgt.points_possible                  = src.points_possible,
       tgt.grade_earned                     = src.grade_earned,
       tgt.points_progress                  = src.points_progress,
       tgt.points_progress_delta            = src.points_progress_delta,
       tgt.points_total                     = src.points_total,
       tgt.assignments_submitted_7d         = src.assignments_submitted_7d,
       tgt.points_submitted_7d              = src.points_submitted_7d,
       tgt.missing_assignments              = src.missing_assignments,
       tgt.missing_points                   = src.missing_points,
       tgt.assignments_next7d               = src.assignments_next7d,
       tgt.points_possible_next7d           = src.points_possible_next7d,
       tgt.days_since_last_submission       = src.days_since_last_submission,
       tgt.activity_date                    = src.activity_date
 WHERE (nvl(tgt.points_submitted, -1) != nvl(src.points_submitted, -1) AND src.points_submitted IS NOT NULL)
    OR (nvl(tgt.points_earned, -1) != nvl(src.points_earned, -1) AND src.points_earned IS NOT NULL)
WHEN NOT MATCHED THEN
INSERT
(term_code,
 crn,
 pidm,
 user_id,
 course_id,
 course_section_id,
 dte,
 assignments_due,
 assignments_submitted,
 assignments_submitted_ontime,
 assignments_submitted_ontime_pct,
 assignments_progress,
 assignments_progress_delta,
 assignments_total,
 points_due,
 points_submitted,
 points_submitted_ontime,
 points_submitted_ontime_pct,
 points_earned,
 points_possible,
 grade_earned,
 points_progress,
 points_progress_delta,
 points_total,
 assignments_submitted_7d,
 points_submitted_7d,
 missing_assignments,
 missing_points,
 assignments_next7d,
 points_possible_next7d,
 days_since_last_submission,
 activity_date)
VALUES
(src.term_code,
 src.crn,
 src.pidm,
 src.user_id,
 src.course_id,
 src.course_section_id,
 src.dte,
 src.assignments_due,
 src.assignments_submitted,
 src.assignments_submitted_ontime,
 src.assignments_submitted_ontime_pct,
 src.assignments_progress,
 src.assignments_progress_delta,
 src.assignments_total,
 src.points_due,
 src.points_submitted,
 src.points_submitted_ontime,
 src.points_submitted_ontime_pct,
 src.points_earned,
 src.points_possible,
 src.grade_earned,
 src.points_progress,
 src.points_progress_delta,
 src.points_total,
 src.assignments_submitted_7d,
 src.points_submitted_7d,
 src.missing_assignments,
 src.missing_points,
 src.assignments_next7d,
 src.points_possible_next7d,
 src.days_since_last_submission,
 src.activity_date);
v_count := SQL%ROWCOUNT;
COMMIT;
dbms_lock.sleep(1); -- pause
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - Step 1 - ' || rec.term_code || ' - ' || rec.dte || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
EXIT; -- If successful, exit the retry loop
EXCEPTION
WHEN OTHERS THEN
IF SQLCODE = -60 THEN
-- Deadlock detected
v_retry_count := v_retry_count + 1;
IF v_retry_count > v_max_retries THEN
-- Log error for max retries
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := '!!!-00060: deadlock detected while waiting for resource. Max retries exceeded after ' || (v_max_retries * v_wait_time) || ' seconds';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
EXIT; -- Add EXIT here to break out of the loop when max retries exceeded
ELSE
-- Log retry attempt
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'Deadlock detected while waiting for resource - waiting ' || v_wait_time || ' seconds for retry attempt number ' || v_retry_count;
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'WARNING', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
dbms_lock.sleep(v_wait_time); -- Wait between retries; short wait because it will need to cycle through all the GTTs again
CONTINUE; -- Add CONTINUE to explicitly indicate loop continuation
END IF;
ELSE
-- Other errors
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
EXIT; -- Add EXIT here to break out of the loop for non-deadlock errors
END IF;
END;
END LOOP; -- end deadlock detection
dbms_output.put_line(' --------- ');
END LOOP; -- c_rec 
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
-- log any errors
EXCEPTION
WHEN OTHERS THEN
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
END etl_aa_ml_student_assignments;

procedure etl_aa_ml_persistence (jobnumber NUMBER, processid VARCHAR2, processname VARCHAR2) IS
/*
Table:

Primary Keys: None

Unique index: TERM_CODE, PIDM, DTE

Purpose:
- Staging data for academics predictive models

Conditions:
- Must be banner enrolled

*/
-- DECLARE
--- PARAMS
v_etl_date DATE := SYSDATE;
v_msg      VARCHAR2(2000);
v_instance VARCHAR2(50) := upper('L2CAN'); -- inst from the jams job; used for determining instance
v_partition NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0

v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_aa_ml_persistence';
v_loop_count  NUMBER := 0; -- Variable to track the current loop iteration
v_total_loops NUMBER := 0; -- Variable to track the total number of loops
v_retry_count NUMBER := 0;
v_max_retries NUMBER := 3; -- number of retries for WAIT
v_wait_time   NUMBER := 120; -- seconds for WAIT
TYPE r_rec IS RECORD(
term_code  VARCHAR2(6),
group_code VARCHAR2(3),
active     NUMBER);
TYPE t_rec IS TABLE OF r_rec;
v_rec t_rec;
CURSOR c_rec IS
-- Run current terms - ALWAYS
SELECT terms.term_code,
       terms.group_code,
       CASE
       WHEN SYSDATE <= terms.end_date + 7 THEN
        1
       ELSE
        0
       END AS active
  FROM zbtm.terms_by_group_v terms
 WHERE 1 = 1
   AND terms.semester NOT IN ('WIN')
   AND terms.group_code IN ('STD')
   AND SYSDATE >= terms.start_date - 7
   AND SYSDATE <= terms.end_date + 7
UNION
-- Run non-current terms - **ONLY RUN DURING NON-BUSINESS HOURS** 
SELECT terms.term_code,
       terms.group_code,
       CASE
       WHEN SYSDATE <= terms.end_date + 7 THEN
        1
       ELSE
        0
       END AS active
  FROM zbtm.terms_by_group_v terms
 WHERE 1 = 1
   AND terms.semester NOT IN ('WIN')
   AND terms.group_code IN ('STD')
   AND SYSDATE >= terms.start_date - 180
   AND SYSDATE <= terms.end_date + 180
   AND (to_char(SYSDATE, 'HH24') BETWEEN '18' AND '23')
 ORDER BY 1;
BEGIN
-- dbms_output.enable(buffer_size => NULL);
--
-- Calculate total number of loops
OPEN c_rec;
FETCH c_rec BULK COLLECT
INTO v_rec;
v_total_loops := v_rec.count;
CLOSE c_rec;
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
FOR rec IN c_rec
LOOP
v_loop_count := v_loop_count + 1; -- Increment loop count
v_count      := 0; -- reset count
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - Loop ' || v_loop_count || ' of ' || v_total_loops || ' - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- remove any students NOT enrolled anymore
IF rec.active = 1 THEN
DELETE FROM utl_d_aa.ml_persistence tgt
 WHERE tgt.term_code = rec.term_code
   AND NOT EXISTS (SELECT 1
          FROM utl_d_aim.szrenrl src
         WHERE src.term_code = tgt.term_code
           AND src.pidm = tgt.pidm);
v_count := SQL%ROWCOUNT;
COMMIT;
dbms_lock.sleep(1); -- pause
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'DELETE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
END IF;
-- Retry mechanism for handling deadlocks
LOOP
BEGIN
v_count := 0; --reset count
MERGE INTO utl_d_aa.ml_persistence tgt
USING (
-- CTE to define the cohort of students for the given term
WITH cohort AS
 (SELECT /*+ MATERIALIZE */
   szrenrl.term_code,
   szrenrl.pidm,
   szrenrl.camp_code,
   szrenrl.semester,
   szrenrl.degc_code_1,
   CASE
   WHEN szrenrl.first_enrl_term = 'Y' THEN
    1
   ELSE
    0
   END AS first_enrl_term -- first semester at LU (ever)
    FROM utl_d_aim.szrenrl
   WHERE szrenrl.term_code = rec.term_code)
SELECT CASE
       WHEN src.pidm IS NOT NULL
            AND tgt.pidm IS NULL THEN
        'INSERT' -- new record to source, add to table
       WHEN src.pidm IS NOT NULL
            AND tgt.pidm IS NOT NULL THEN
        'UPDATE' -- record exists in both places 
       END AS control_state,
       src.term_code,
       src.pidm,
       src.camp_code,
       src.first_enrl_term,
       src.start_date,
       src.end_date,
       src.day_number,
       src.dte,
       src.semester,
       src.actual_result,
       src.activity_date
  FROM (SELECT cohort.term_code,
                cohort.pidm,
                cohort.camp_code,
                cohort.first_enrl_term, -- first semester at LU (ever)
                cal.start_date,
                cal.end_date,
                cal.day_number,
                cal.dte,
                cohort.semester,
                NULL AS predicted_result, -- ** do not update here ** 
                CASE
                 WHEN shrdgmr_pidm IS NOT NULL THEN
                  1 -- they graduated, so count them as successful (thus removing them from the pool to chase)
                 WHEN szrenrl_next.pidm IS NOT NULL THEN
                  1 -- they have reg showing for the next term
                 WHEN v_etl_date > cal.end_date
                      AND szrenrl_next.pidm IS NULL THEN
                  0 -- if they still didn't regsister for the next term after the cohort term end date, then lock in the result
               END AS actual_result,
               v_etl_date AS activity_date
          FROM cohort
          JOIN saturn.stvdegc
            ON cohort.degc_code_1 = stvdegc.stvdegc_code
        -- only get full semester time frame
          JOIN (SELECT terms.term_code,
                      terms.group_code,
                      terms.start_date,
                      terms.end_date,
                      terms.start_date + daysin.numb AS dte,
                      daysin.numb + 1 AS day_number,
                      TRIM(to_char(terms.start_date + daysin.numb, 'Day')) AS day_of_week
                 FROM zbtm.terms_by_group_v terms
                 JOIN (SELECT LEVEL - 8 numb FROM dual CONNECT BY LEVEL <= 800) daysin
                   ON terms.start_date + daysin.numb <= terms.end_date
                WHERE 1 = 1
                  AND TRIM(to_char(terms.start_date + daysin.numb, 'Day')) = 'Monday' -- only return mondays to run model once a week
                  AND terms.group_code IN ('STD')
                  AND terms.term_code = rec.term_code
                  AND terms.start_date + daysin.numb < v_etl_date -- run today and everything prior
               ) cal
            ON cal.term_code = cohort.term_code
        -- graduation check; using the same logic as the "ordained" definition in the pdb
          LEFT JOIN (SELECT shrdgmr_pidm,
                           shrdgmr_term_code_grad,
                           shrdgmr_levl_code,
                           shrdgmr_degc_code,
                           stvdegc_acat_code,
                           rank() over(PARTITION BY shrdgmr_pidm ORDER BY shrdgmr_term_code_grad ASC, stvdegc_acat_code DESC, rownum) ranking -- RESOLVE MULTIPLE DEGREES; we only need one row returned
                      FROM saturn.shrdgmr
                      JOIN cohort
                        ON cohort.pidm = shrdgmr_pidm
                      JOIN zbtm.terms_by_group_v terms
                        ON terms.term_code = shrdgmr_term_code_grad
                       AND terms.group_code IN ('STD') -- only get standard terms and med
                      JOIN saturn.stvdegc
                        ON shrdgmr_degc_code = stvdegc_code
                       AND shrdgmr_term_code_grad >= rec.term_code -- this needs to be >= the STUDENT last term enrolled; casting a wider net; gets handled in the lower query
                       AND shrdgmr_term_code_grad <= ADS_ETL.GET_NEXT_TERM_CODE(cohort.term_code, cohort.camp_code) -- limit range... function used to get next term
                       AND shrdgmr_degs_code = 'AW'
                     WHERE ((stvdegc_acat_code >= stvdegc.stvdegc_acat_code AND shrdgmr_degc_code <> 'MDV') -- if not MDV, the degree code has to be >= the enrollment degree code
                           OR (shrdgmr_degc_code = 'MDV' AND shrdgmr_degc_code = cohort.degc_code_1)) -- if MDV, degree in passing in effect, we want to count this as an awarded degree
                    ) grads
            ON grads.shrdgmr_pidm = cohort.pidm
           AND grads.ranking = 1
          LEFT JOIN utl_d_aim.szrenrl szrenrl_next
            ON szrenrl_next.term_code = ADS_ETL.GET_NEXT_TERM_CODE(cohort.term_code, cohort.camp_code) -- function used to get next term
           AND szrenrl_next.pidm = cohort.pidm) src
-- for the control state
  LEFT JOIN utl_d_aa.ml_persistence tgt
    ON tgt.term_code = src.term_code
   AND tgt.pidm = src.pidm
   AND tgt.dte = src.dte
 WHERE 1 = 1
      -- for inserts or deletes...
   AND (((src.pidm IS NULL AND tgt.pidm IS NOT NULL) OR (src.pidm IS NOT NULL AND tgt.pidm IS NULL)) OR --
       -- for updates if any data has changed...
       nvl(src.camp_code, 'X') <> nvl(tgt.camp_code, 'X') OR --
       (nvl(src.first_enrl_term, -1) <> nvl(tgt.first_enrl_term, -1) OR --
       nvl(src.semester, 'X') <> nvl(tgt.semester, 'X') OR --        
       nvl(src.start_date, SYSDATE) <> nvl(tgt.start_date, SYSDATE) OR --
       nvl(src.end_date, SYSDATE) <> nvl(tgt.end_date, SYSDATE) OR --
       nvl(src.day_number, -1) <> nvl(tgt.day_number, -1) OR --  
       nvl(src.actual_result, -1) <> nvl(tgt.actual_result, -1)))) src --
 ON (tgt.term_code = src.term_code AND tgt.pidm = src.pidm AND tgt.dte = src.dte) --
 WHEN MATCHED THEN
UPDATE
   SET tgt.camp_code       = src.camp_code,
       tgt.first_enrl_term = src.first_enrl_term,
       tgt.start_date      = src.start_date,
       tgt.end_date        = src.end_date,
       tgt.day_number      = src.day_number,
       tgt.semester        = src.semester,
       tgt.actual_result   = src.actual_result,
       tgt.activity_date   = src.activity_date
WHEN NOT MATCHED THEN
INSERT
(term_code,
 pidm,
 camp_code,
 first_enrl_term,
 start_date,
 end_date,
 day_number,
 dte,
 semester,
 actual_result,
 activity_date)
VALUES
(src.term_code,
 src.pidm,
 src.camp_code,
 src.first_enrl_term,
 src.start_date,
 src.end_date,
 src.day_number,
 src.dte,
 src.semester,
 src.actual_result,
 v_etl_date);
v_count := SQL%ROWCOUNT;
COMMIT;
dbms_lock.sleep(1); -- pause
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
EXIT; -- If successful, exit the retry loop
EXCEPTION
WHEN OTHERS THEN
IF SQLCODE = -60 THEN
-- Deadlock detected
v_retry_count := v_retry_count + 1;
IF v_retry_count > v_max_retries THEN
-- Log error for max retries
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := '!!!-00060: deadlock detected while waiting for resource. Max retries exceeded after ' || (v_max_retries * v_wait_time) || ' seconds';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
EXIT; -- Add EXIT here to break out of the loop when max retries exceeded
ELSE
-- Log retry attempt
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'Deadlock detected while waiting for resource - waiting ' || v_wait_time || ' seconds for retry attempt number ' || v_retry_count;
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'WARNING', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
dbms_lock.sleep(v_wait_time); -- Wait between retries; short wait because it will need to cycle through all the GTTs again
CONTINUE; -- Add CONTINUE to explicitly indicate loop continuation
END IF;
ELSE
-- Other errors
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
EXIT; -- Add EXIT here to break out of the loop for non-deadlock errors
END IF;
END;
END LOOP; -- end deadlock detection
dbms_output.put_line(' --------- ');
END LOOP; -- c_rec
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
-- log any errors
EXCEPTION
WHEN OTHERS THEN
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
/*--------------------------------------------CHANGE LOG----------------------------------------
VERSION  DATE        USERNAME    UPDATES
---     07-01-2025  WGRIFFITH2  --Initial release; 
---     07-03-2025  WGRIFFITH2  --Added THE "graduation check;" using the same logic as the "ordained" definition in the pdb
---     07-29-2025  WGRIFFITH2  --CTE added to resolve duplication when students have conferred multiple degrees; MDV check moved into the WHERE clause inside the "grads" subquery to fix the runaway
------------------------------------------------------------------------------------------------*/
END etl_aa_ml_persistence;

procedure etl_aa_ml_course_success (jobnumber NUMBER, processid VARCHAR2, processname VARCHAR2) IS

--
-- PURPOSE: Stages weekly course completion outcomes to support the ML course success model and operational monitoring by term, section (CRN), and student.
--
-- TABLE: utl_d_aa.ml_course_success
--
-- UNIQUE INDEX: TERM_CODE, CRN, PIDM, DTE
--
-- CONDITIONS:
-- Processes one academic term at a time selected from zbtm.terms_by_group_v where the term group is Standard (STD) and the semester is not Winter (WIN).
-- Current terms are processed when SYSDATE falls within 7 days before the term start_date through 7 days after the term end_date.
-- Non-current terms within 180 days before/after the term dates are processed only during evening hours (18:00–23:59), to run outside business hours.
-- Includes only students who have an enrollment record (utl_d_aim.szrenrl) in the same term as the section (utl_d_aim.szrcrse) based on TERM_CODE and PIDM.
-- Enrollment filter: group_code must be 'STD' and semester must not be 'WIN'.
-- Maps sections to the instructional calendar (utl_d_aa.crscalendar) by TERM_CODE and CRN, but only for part-of-term codes R, 1A, 1B, 1C, or 1D.
-- Limits weekly tracking to the first 8 instructional weeks to align with the course completion model.
-- Generates one record per student-section per week by selecting only calendar rows where DTE equals WEEK_END_DATE (ensures a single row per week).
-- Only includes calendar dates strictly earlier than today (DTE < SYSDATE); the load runs for today and all prior weeks.
-- Stops tracking a student-section once the final grade has been posted; a week is included only if GRADE_DATE is null or occurs after that week’s DTE.
-- Derives FIRST_ENRL_TERM as 1 when the student’s first_enrl_term = 'Y'; otherwise 0 (indicates first-ever LU enrollment).
-- Derives ACTUAL_RESULT as:
--   1 when the final grade begins with 'A' or 'B', or 'P' (pass),
--   0 when the final grade is 'PR' (in progress) or any other non-success letter,
--   NULL when the final grade is not yet posted (NULL).
-- Sets ACTIVITY_DATE to the ETL run timestamp for all inserted or updated rows.
-- Keys TERM_CODE, CRN, PIDM, and DTE uniquely identify a weekly tracking record for each student-section.
-- Inserts a new record when a qualifying source row exists but no matching target row is present for the key.
-- Updates an existing record only when any tracked attribute changes: FIRST_ENRL_TERM, PTRM_CODE, SEMESTER, PTRM_START, PTRM_END, WEEK_NUMBER, WEEK_START_DATE, WEEK_END_DATE, DAY_NUMBER, FINAL_GRADE, GRADE_DATE, or ACTUAL_RESULT.
-- Deletes a record when a previously tracked student-section-week no longer qualifies in the source (i.e., the joined source row disappears for the key).
-- Processes rows in batches up to 200,000 per fetch to manage large terms efficiently.
--
-- URL: N/A
--
--DECLARE
v_etl_date    DATE := SYSDATE;
v_msg         VARCHAR2(2000);
v_instance    VARCHAR2(50) := upper('L2CAN'); -- inst from the jams job; used for determining instance
v_partition   NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0 
v_row_max     NUMBER := 200000; -- max number of rows to be processed at one time
v_count       NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_aa_ml_course_success';
v_loop_count  NUMBER := 0; -- Variable to track the current loop iteration
v_total_loops NUMBER := 0; -- Variable to track the total number of loops
v_retry_count NUMBER := 0;
v_max_retries NUMBER := 3; -- number of retries for WAIT
v_wait_time   NUMBER := 120; -- seconds for WAIT
-- cursors
CURSOR c_terms IS
-- Run current terms - ALWAYS
SELECT terms.term_code,
       terms.group_code
  FROM zbtm.terms_by_group_v terms
 WHERE 1 = 1
   AND terms.semester NOT IN ('WIN')
   AND terms.group_code IN ('STD')
   AND SYSDATE >= terms.start_date - 7
   AND SYSDATE <= terms.end_date + 7
UNION
-- Run non-current terms - **ONLY RUN DURING NON-BUSINESS HOURS** 
SELECT terms.term_code,
       terms.group_code
  FROM zbtm.terms_by_group_v terms
 WHERE 1 = 1
   AND terms.semester NOT IN ('WIN')
   AND terms.group_code IN ('STD')
   AND SYSDATE >= terms.start_date - 180
   AND SYSDATE <= terms.end_date + 180
   AND (to_char(SYSDATE, 'HH24') BETWEEN '18' AND '23')
 ORDER BY 1;
CURSOR c1(v_term_code VARCHAR) IS
SELECT CASE
       WHEN src.crn IS NOT NULL
            AND tgt.crn IS NULL THEN
        'INSERT' -- new record to source, add to table
       WHEN src.crn IS NOT NULL
            AND tgt.crn IS NOT NULL THEN
        'UPDATE' -- record exists in both places
       WHEN src.crn IS NULL
            AND tgt.crn IS NOT NULL THEN
        'DELETE' -- no record longer exists on the source data, remove it
       END AS control_state,
       nvl(src.term_code, tgt.term_code) AS term_code,
       nvl(src.crn, tgt.crn) AS crn,
       nvl(src.pidm, tgt.pidm) AS pidm,
       src.first_enrl_term,
       src.ptrm_code,
       src.ptrm_start,
       src.ptrm_end,
       src.week_number,
       src.week_start_date,
       src.week_end_date,
       src.day_number,
       nvl(src.dte, tgt.dte) AS dte,
       src.semester,
       src.actual_result,
       src.final_grade,
       src.grade_date,
       src.activity_date
  FROM (SELECT szrcrse.term_code,
               szrcrse.crn,
               szrcrse.pidm,
               szrcrse.ptrm_code,
               szrcrse.ptrm_start,
               szrcrse.ptrm_end,
               cal.week_number AS week_number,
               cal.week_start_date AS week_start_date,
               cal.week_end_date AS week_end_date,
               cal.day_number AS day_number,
               cal.dte AS dte,
               szrenrl.semester,
               NULL AS predicted_result, -- ** do not update here ** 
               CASE
               WHEN szrenrl.first_enrl_term = 'Y' THEN
                1
               ELSE
                0
               END AS first_enrl_term, -- first semester at LU (ever)
               CASE
               WHEN szrcrse.final_grade = 'PR' THEN
                0
               WHEN substr(szrcrse.final_grade, 1, 1) IN ('A', 'B', 'P') THEN
                1
               WHEN szrcrse.final_grade IS NULL THEN
                NULL
               ELSE
                0
               END AS actual_result,
               szrcrse.final_grade,
               szrcrse.grade_date,
               v_etl_date AS activity_date
        -- szrcrse - section | course joins
          FROM utl_d_aim.szrcrse
        -- szrenrl - term to term enrollment joins
          JOIN utl_d_aim.szrenrl
            ON szrenrl.term_code = szrcrse.term_code
           AND szrenrl.pidm = szrcrse.pidm
           AND szrcrse.term_code = v_term_code
           AND szrenrl.group_code IN ('STD')
           AND szrenrl.semester NOT IN ('WIN')
          JOIN utl_d_aa.crscalendar cal
            ON cal.term_code = szrcrse.term_code
           AND cal.crn = szrcrse.crn
           AND cal.ptrm_code IN ('R', '1A', '1B', '1C', '1D')
           AND cal.week_number <= 8 -- 0-8 weeks are needed for course completion model
           AND cal.dte < SYSDATE -- run today and all prior
           AND cal.dte = cal.week_end_date -- only get one row per week
           AND (szrcrse.grade_date IS NULL OR szrcrse.grade_date > cal.dte) -- stop tracking once grade is submitted
        ) src
-- for the control state
  FULL JOIN (SELECT tgt.* FROM utl_d_aa.ml_course_success tgt WHERE tgt.term_code = v_term_code) tgt
    ON tgt.term_code = src.term_code
   AND tgt.crn = src.crn
   AND tgt.pidm = src.pidm
   AND tgt.dte = src.dte
 WHERE 1 = 1
      -- for inserts or deletes...
   AND (((src.crn IS NULL AND tgt.crn IS NOT NULL) OR (src.crn IS NOT NULL AND tgt.crn IS NULL)) OR --
       -- for updates if any data has changed...
       (nvl(src.first_enrl_term, -1) <> nvl(tgt.first_enrl_term, -1) OR --
       nvl(src.ptrm_code, 'X') <> nvl(tgt.ptrm_code, 'X') OR --
       nvl(src.semester, 'X') <> nvl(tgt.semester, 'X') OR --
       nvl(src.ptrm_start, SYSDATE) <> nvl(tgt.ptrm_start, SYSDATE) OR --
       nvl(src.ptrm_end, SYSDATE) <> nvl(tgt.ptrm_end, SYSDATE) OR --
       nvl(src.week_number, -1) <> nvl(tgt.week_number, -1) OR --
       nvl(src.week_start_date, SYSDATE) <> nvl(tgt.week_start_date, SYSDATE) OR --
       nvl(src.week_end_date, SYSDATE) <> nvl(tgt.week_end_date, SYSDATE) OR --
       nvl(src.day_number, -1) <> nvl(tgt.day_number, -1) OR --
       nvl(src.final_grade, 'X') <> nvl(tgt.final_grade, 'X') OR --
       nvl(src.grade_date, SYSDATE) <> nvl(tgt.grade_date, SYSDATE) OR --
       nvl(src.actual_result, -1) <> nvl(tgt.actual_result, -1)));
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
update_dml index_pointer_u := index_pointer_u();
TYPE index_pointer_d IS TABLE OF PLS_INTEGER;
delete_dml    index_pointer_d := index_pointer_d();
v_total_count NUMBER := 0;
insert_count  NUMBER := 0;
update_count  NUMBER := 0;
delete_count  NUMBER := 0;
v_elapsed     NUMBER := 0;
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
-- Reset retry count **per term** to avoid carrying retries across terms
v_retry_count := 0;
-- Retry mechanism for handling deadlocks
LOOP
BEGIN
v_count := 0; --reset count
-- Defensive close: ensure the cursor is not left open from a prior attempt; **necessary for bulk collect**
IF c1%ISOPEN THEN
CLOSE c1;
END IF;
OPEN c1(rec.term_code);
LOOP
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
FETCH c1 BULK COLLECT
INTO rec_input LIMIT v_row_max;
v_count := rec_input.count;
IF v_count = 0 THEN
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'SELECT - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
ELSIF v_count > 0 THEN
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'SELECT - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
insert_dml := index_pointer_i();
update_dml := index_pointer_u();
delete_dml := index_pointer_d();
FOR idx IN coalesce(rec_input.first, 1) .. coalesce(rec_input.last, 1)
LOOP
BEGIN
IF rec_input(idx).control_state = 'INSERT' THEN
insert_dml.extend;
insert_dml(insert_dml.last) := idx;
END IF;
IF rec_input(idx).control_state = 'UPDATE' THEN
update_dml.extend;
update_dml(update_dml.last) := idx;
END IF;
IF rec_input(idx).control_state = 'DELETE' THEN
delete_dml.extend;
delete_dml(delete_dml.last) := idx;
END IF;
EXCEPTION
WHEN OTHERS THEN
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200) || ' exception raised for ' || rec.term_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || round(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
CONTINUE;
END;
END LOOP;
insert_count := insert_dml.count;
update_count := update_dml.count;
delete_count := delete_dml.count;
FORALL i IN VALUES OF insert_dml -- DML INSERTS
INSERT INTO utl_d_aa.ml_course_success tab
(term_code,
 crn,
 pidm,
 first_enrl_term,
 ptrm_code,
 ptrm_start,
 ptrm_end,
 week_number,
 week_start_date,
 week_end_date,
 day_number,
 dte,
 semester,
 actual_result,
 final_grade,
 grade_date,
 activity_date)
VALUES
(rec_input(i).term_code,
 rec_input(i).crn,
 rec_input(i).pidm,
 rec_input(i).first_enrl_term,
 rec_input(i).ptrm_code,
 rec_input(i).ptrm_start,
 rec_input(i).ptrm_end,
 rec_input(i).week_number,
 rec_input(i).week_start_date,
 rec_input(i).week_end_date,
 rec_input(i).day_number,
 rec_input(i).dte,
 rec_input(i).semester,
 rec_input(i).actual_result,
 rec_input(i).final_grade,
 rec_input(i).grade_date,
 v_etl_date);
v_count := SQL%ROWCOUNT;
COMMIT;
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'INSERT - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
FORALL i IN VALUES OF update_dml -- DML UPDATES
UPDATE utl_d_aa.ml_course_success tgt
   SET (first_enrl_term, ptrm_code, ptrm_start, ptrm_end, week_number, week_start_date, week_end_date, day_number, semester, actual_result, final_grade, grade_date, activity_date) =
       (SELECT rec_input (i).first_enrl_term,
               rec_input (i).ptrm_code,
               rec_input (i).ptrm_start,
               rec_input (i).ptrm_end,
               rec_input (i).week_number,
               rec_input (i).week_start_date,
               rec_input (i).week_end_date,
               rec_input (i).day_number,
               rec_input (i).semester,
               rec_input (i).actual_result,
               rec_input (i).final_grade,
               rec_input (i).grade_date,
               v_etl_date
          FROM dual)
 WHERE tgt.term_code = rec_input(i).term_code
   AND tgt.crn = rec_input(i).crn
   AND tgt.pidm = rec_input(i).pidm
   AND tgt.dte = rec_input(i).dte;
v_count := SQL%ROWCOUNT;
COMMIT;
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'UPDATE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
FORALL i IN VALUES OF delete_dml -- DML DELETES
DELETE FROM utl_d_aa.ml_course_success tgt
 WHERE tgt.term_code = rec_input(i).term_code
   AND tgt.crn = rec_input(i).crn
   AND tgt.pidm = rec_input(i).pidm
   AND tgt.dte = rec_input(i).dte;
v_count := SQL%ROWCOUNT;
COMMIT;
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'DELETE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
END IF;
dbms_lock.sleep(1); -- pause
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_total_count := v_total_count + rec_input.count;
-- Exit inner fetch loop when batch is smaller than the fetch limit
EXIT WHEN(rec_input.count < v_row_max);
END LOOP;
-- Close the cursor after successful processing
IF c1%ISOPEN THEN
CLOSE c1;
END IF;
EXIT; -- If successful, exit the retry loop
EXCEPTION
WHEN OTHERS THEN
-- **ALWAYS** close the cursor on any exception to prevent ORA-06511
IF c1%ISOPEN THEN
CLOSE c1;
END IF;
IF SQLCODE = -60 THEN
-- Deadlock detected
v_retry_count := v_retry_count + 1;
IF v_retry_count > v_max_retries THEN
-- Log error for max retries and exit retry loop
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := '!!!-00060: deadlock detected while waiting for resource. Max retries exceeded after ' || (v_max_retries * v_wait_time) || ' seconds';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
EXIT; -- break out of the retry loop when max retries exceeded
ELSE
-- Log retry attempt and wait before retrying
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'Deadlock detected while waiting for resource - waiting ' || v_wait_time || ' seconds for retry attempt number ' || v_retry_count;
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'WARNING', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
dbms_lock.sleep(v_wait_time); -- Wait between retries
CONTINUE; -- retry the term; cursor is already closed safely
END IF;
ELSE
-- Other errors: log and exit retry loop
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
EXIT; -- exit retry loop for non-deadlock errors
END IF;
END;
END LOOP; -- end deadlock detection
dbms_output.put_line(' --------- ');
END LOOP; -- c_terms
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
-- log any errors
EXCEPTION
WHEN OTHERS THEN
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
/*--------------------------------------------CHANGE LOG----------------------------------------
VERSION  DATE        USERNAME    UPDATES
---     06-09-2025  WGRIFFITH2  --Initial release
---     12-04-2025  WGRIFFITH2  --adding deadlock avoidance
-- 20251218 - WGRIFFITH2 - Fixed deadlock retry logic by resetting retries per term and ensuring the cursor is closed before retry/exit to prevent OR
------------------------------------------------------------------------------------------------*/
END etl_aa_ml_course_success;

procedure etl_aa_ml_student_emails (jobnumber NUMBER, processid VARCHAR2, processname VARCHAR2) IS
/*
Table: 

Primary Keys: None

Unique index: TERM_CODE, PIDM, DTE

Purpose:
- Staging data for academics predictive models

Conditions:
- Must be banner enrolled
- Summaries are based on start of the term if date is required

*/
-- DECLARE
--- PARAMS
v_etl_date    DATE := SYSDATE;
v_msg         VARCHAR2(2000);
v_instance VARCHAR2(50) := upper('L2CAN'); -- inst from the jams job; used for determining instance
v_partition NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0 
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_aa_ml_student_emails';
v_loop_count  NUMBER := 0; -- Variable to track the current loop iteration
v_total_loops NUMBER := 0; -- Variable to track the total number of loops
v_retry_count NUMBER := 0;
v_max_retries NUMBER := 3; -- number of retries for WAIT
v_wait_time   NUMBER := 120; -- seconds for WAIT
TYPE r_rec IS RECORD(
term_code VARCHAR2(6),
dte       DATE);
TYPE t_rec IS TABLE OF r_rec;
v_rec t_rec;
CURSOR c_rec IS
SELECT DISTINCT cal.term_code,
                cal.dte
  FROM utl_d_aa.crscalendar cal
  JOIN zbtm.terms_by_group_v terms
    ON terms.term_code = cal.term_code
   AND terms.group_code IN ('STD')
   AND terms.semester NOT IN ('WIN')
   AND cal.ptrm_code IN ('R', '1A', '1B', '1C', '1D') 
   AND cal.dte + 1 < SYSDATE -- do not run day until it is complete      
   AND cal.dte >= trunc(SYSDATE - 2) -- return days back in case of latency
   AND (to_char(SYSDATE, 'HH24') BETWEEN '00' AND '06' OR to_char(SYSDATE, 'HH24') BETWEEN '18' AND '23')
 ORDER BY term_code DESC,
          dte       DESC;
BEGIN
-- dbms_output.enable(buffer_size => NULL);
--
-- Calculate total number of loops
OPEN c_rec;
FETCH c_rec BULK COLLECT
INTO v_rec;
v_total_loops := v_rec.count;
CLOSE c_rec;
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
FOR rec IN c_rec
LOOP
v_loop_count := v_loop_count + 1; -- Increment loop count
v_count      := 0; -- reset count
dbms_lock.sleep(1); -- pause
v_elapsed    := round((SYSDATE - v_etl_date) * 86400);
v_msg        := 'START - Loop ' || v_loop_count || ' of ' || v_total_loops || ' - ' || rec.term_code || ' - ' || rec.dte || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) ||
                ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- Retry mechanism for handling deadlocks
LOOP
BEGIN
v_count := 0; --reset count
MERGE INTO utl_d_aa.ml_student_emails tgt
USING (SELECT /*+ USE_HASH(mre SZRENRL ma) LEADING(SZRENRL mre ma) INDEX(mre MKTG_REC_EM_SENTDATETIME) INDEX(SZRENRL SZRENRL_IDX2) INDEX(ma MKTG_ACT_SNRITM_IDX) */
        src.term_code,
        src.pidm,
        src.dte,
        src.sent_90d,
        src.sent_7d,
        src.sent_casas_90d,
        src.sent_casas_7d,
        src.sent_registrar_90d,
        src.sent_registrar_7d,
        src.sent_finaid_90d,
        src.sent_finaid_7d,
        src.sent_sao_90d,
        src.sent_sao_7d,
        src.sent_luo_90d,
        src.sent_luo_7d,
        v_etl_date AS activity_date,
        ora_hash(src.term_code || src.pidm || src.dte || src.sent_90d) AS row_hash
         FROM (SELECT mre.pidm,
                       rec.term_code,
                       rec.dte AS dte,
                       -- count /*DISTINCT*/ emails; using /*DISTINCT*/ as precaution because there is no unique constraint on the marketing analytics table and rogue jobs might cause duplication
                       -- opens, clicks and their rates are not reliable thus not included...
                       -- opens are hard to evaluate due to security features and settings on different ESPs; ex: some will not return an open if they don't download images
                      -- 180d metrics
                      COUNT( /*DISTINCT*/ messguid) AS sent_90d,
                      COUNT( /*DISTINCT*/ CASE
                             WHEN mre.sentdatetime BETWEEN rec.dte - 7 AND rec.dte - 1 THEN
                              messguid
                             ELSE
                              NULL
                             END) AS sent_7d,
                      COUNT( /*DISTINCT*/ CASE
                             WHEN mktg_department = 'CASAS' THEN
                              messguid
                             ELSE
                              NULL
                             END) AS sent_casas_90d,
                      COUNT( /*DISTINCT*/ CASE
                             WHEN mktg_department = 'CASAS'
                                  AND mre.sentdatetime BETWEEN rec.dte - 7 AND rec.dte - 1 THEN
                              messguid
                             ELSE
                              NULL
                             END) AS sent_casas_7d,
                      COUNT( /*DISTINCT*/ CASE
                             WHEN mktg_department = 'Registrar' THEN
                              messguid
                             ELSE
                              NULL
                             END) AS sent_registrar_90d,
                      COUNT( /*DISTINCT*/ CASE
                             WHEN mktg_department = 'Registrar'
                                  AND mre.sentdatetime BETWEEN rec.dte - 7 AND rec.dte - 1 THEN
                              messguid
                             ELSE
                              NULL
                             END) AS sent_registrar_7d,
                      COUNT( /*DISTINCT*/ CASE
                             WHEN mktg_department = 'Financial Aid' THEN
                              messguid
                             ELSE
                              NULL
                             END) AS sent_finaid_90d,
                      COUNT( /*DISTINCT*/ CASE
                             WHEN mktg_department = 'Financial Aid'
                                  AND mre.sentdatetime BETWEEN rec.dte - 7 AND rec.dte - 1 THEN
                              messguid
                             ELSE
                              NULL
                             END) AS sent_finaid_7d,
                      COUNT( /*DISTINCT*/ CASE
                             WHEN mktg_department = 'Student Accounts' THEN
                              messguid
                             ELSE
                              NULL
                             END) AS sent_sao_90d,
                      COUNT( /*DISTINCT*/ CASE
                             WHEN mktg_department = 'Student Accounts'
                                  AND mre.sentdatetime BETWEEN rec.dte - 7 AND rec.dte - 1 THEN
                              messguid
                             ELSE
                              NULL
                             END) AS sent_sao_7d,
                      COUNT( /*DISTINCT*/ CASE
                             WHEN mktg_department = 'LU Online' THEN
                              messguid
                             ELSE
                              NULL
                             END) AS sent_luo_90d,
                      COUNT( /*DISTINCT*/ CASE
                             WHEN mktg_department = 'LU Online'
                                  AND mre.sentdatetime BETWEEN rec.dte - 7 AND rec.dte - 1 THEN
                              messguid
                             ELSE
                              NULL
                             END) AS sent_luo_7d
                 FROM am_mktg_analytics.mktg_receipt_email mre
                 JOIN utl_d_aim.szrenrl -- just to confirm student enrollment
                   ON szrenrl.term_code = rec.term_code
                  AND szrenrl.pidm = mre.pidm
                 JOIN am_mktg_analytics.mktg_activity ma
                   ON ma.snritm = mre.ticket
                WHERE mre.deliverable = 'Y'
                  AND mre.sentdatetime BETWEEN rec.dte - 180 AND rec.dte - 1
                  AND mre.email LIKE '%liberty.edu' -- only get lu emails
                     -- exclude any known departments unrelated to student success
                  AND ma.mktg_department NOT IN ('LU Online Academy', 'William Byron', 'Standing for Freedom Center', 'Homecoming', --
                                                 'Liberty Journal', 'Alumni', 'Marketing', 'Branding', 'Development', 'Special Projects', 'Giving Day', --
                                                 'President', 'Athletics\Football', 'Flames Club', 'Journey FM', 'Commencement', 'Planned Giving', --
                                                 'Donor Relations & Stewardship', 'Business Relations', 'University Events', 'Legal Affairs', --
                                                 'Office of Equity and Compliance', 'Human Resources', 'Procurement', 'CFAW', 'Scaremare', --
                                                 'Auxiliary Services', 'Card Services', 'Ticket Office', 'Winterfest', 'Student Health Center', --
                                                 'Analytics and Decision Support', 'IT', 'Special Project', 'Military Affairs', 'Church Ministries', --
                                                 'RR On Campus Events', 'Transit', 'Government Relations', 'Inclusion Diversity and Equity', 'Dining Services', --
                                                 'Access Control', 'Campus Recreation', 'LaHaye Student Union', 'Honors Department', 'LUPD', --
                                                 'Student Activities', 'Student Government Association', 'Athletics', 'Club Sports', 'Club Sports\Hockey')
                GROUP BY mre.pidm) src
       -- check for diffs comparing with ora_hash ** needs to match the select **
         LEFT JOIN /*+ INDEX(tgt ML_STUDENT_EMAILS_UNIQUE_INDX) */
       utl_d_aa.ml_student_emails tgt
           ON tgt.row_hash = ora_hash(src.term_code || src.pidm || src.dte || src.sent_90d)
        WHERE tgt.row_hash IS NULL) src
ON (tgt.term_code = src.term_code AND tgt.pidm = src.pidm AND tgt.dte = src.dte)
WHEN MATCHED THEN
UPDATE
   SET tgt.sent_90d           = src.sent_90d,
       tgt.sent_7d            = src.sent_7d,
       tgt.sent_casas_90d     = src.sent_casas_90d,
       tgt.sent_casas_7d      = src.sent_casas_7d,
       tgt.sent_registrar_90d = src.sent_registrar_90d,
       tgt.sent_registrar_7d  = src.sent_registrar_7d,
       tgt.sent_finaid_90d    = src.sent_finaid_90d,
       tgt.sent_finaid_7d     = src.sent_finaid_7d,
       tgt.sent_sao_90d       = src.sent_sao_90d,
       tgt.sent_sao_7d        = src.sent_sao_7d,
       tgt.sent_luo_90d       = src.sent_luo_90d,
       tgt.sent_luo_7d        = src.sent_luo_7d,
       tgt.activity_date      = src.activity_date
WHEN NOT MATCHED THEN
INSERT
(term_code,
 pidm,
 dte,
 sent_90d,
 sent_7d,
 sent_casas_90d,
 sent_casas_7d,
 sent_registrar_90d,
 sent_registrar_7d,
 sent_finaid_90d,
 sent_finaid_7d,
 sent_sao_90d,
 sent_sao_7d,
 sent_luo_90d,
 sent_luo_7d,
 activity_date,
 row_hash)
VALUES
(src.term_code,
 src.pidm,
 src.dte,
 src.sent_90d,
 src.sent_7d,
 src.sent_casas_90d,
 src.sent_casas_7d,
 src.sent_registrar_90d,
 src.sent_registrar_7d,
 src.sent_finaid_90d,
 src.sent_finaid_7d,
 src.sent_sao_90d,
 src.sent_sao_7d,
 src.sent_luo_90d,
 src.sent_luo_7d,
 src.activity_date,
 src.row_hash);
v_count := SQL%ROWCOUNT;
COMMIT;
dbms_lock.sleep(1); -- pause
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || rec.term_code || ' - ' || rec.dte || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
EXIT; -- If successful, exit the retry loop
EXCEPTION
WHEN OTHERS THEN
IF SQLCODE = -60 THEN
-- Deadlock detected
v_retry_count := v_retry_count + 1;
IF v_retry_count > v_max_retries THEN
-- Log error for max retries
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := '!!!-00060: deadlock detected while waiting for resource. Max retries exceeded after ' || (v_max_retries * v_wait_time) || ' seconds';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
EXIT; -- Add EXIT here to break out of the loop when max retries exceeded
ELSE
-- Log retry attempt
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'Deadlock detected while waiting for resource - waiting ' || v_wait_time || ' seconds for retry attempt number ' || v_retry_count;
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'WARNING', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
dbms_lock.sleep(v_wait_time); -- Wait between retries; short wait because it will need to cycle through all the GTTs again
CONTINUE; -- Add CONTINUE to explicitly indicate loop continuation
END IF;
ELSE
-- Other errors
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
EXIT; -- Add EXIT here to break out of the loop for non-deadlock errors
END IF;
END;
END LOOP; -- end deadlock detection
dbms_output.put_line(' --------- ');
END LOOP; -- c_rec 
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
-- log any errors
EXCEPTION
WHEN OTHERS THEN
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
/*--------------------------------------------CHANGE LOG----------------------------------------
VERSION  DATE        USERNAME    UPDATES
---     06-09-2025  WGRIFFITH2  --Initial release 
------------------------------------------------------------------------------------------------*/
END etl_aa_ml_student_emails;

procedure etl_aa_ml_student_financials (jobnumber NUMBER, processid VARCHAR2, processname VARCHAR2) IS
/*
Table: 

Primary Keys: None

Unique index: TERM_CODE, PIDM

Purpose:
- Staging data for academics predictive models

Conditions:
- Must be banner enrolled
- Summaries are based on start of the term if date is required
- Attempting to get the data as of term start to try to avoid model hallucination

*/
--DECLARE
--- PARAMS
v_etl_date    DATE := SYSDATE;
v_msg         VARCHAR2(2000);
v_instance    VARCHAR2(50) := upper('L2CAN'); -- inst from the jams job; used for determining instance
v_partition    NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0 
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_aa_ml_student_financials';
v_loop_count  NUMBER := 0; -- Variable to track the current loop iteration
v_total_loops NUMBER := 0; -- Variable to track the total number of loops
v_retry_count NUMBER := 0;
v_max_retries NUMBER := 3; -- number of retries for WAIT
v_wait_time   NUMBER := 120; -- seconds for WAIT
TYPE r_rec IS RECORD(
aidy_code  VARCHAR2(4),
term_code  VARCHAR2(6),
group_code VARCHAR2(3),
start_date DATE,
active     NUMBER);
TYPE t_rec IS TABLE OF r_rec;
v_rec t_rec;
CURSOR c_rec IS
SELECT terms.fa_proc_year AS aidy_code,
       terms.term_code,
       terms.group_code,
       terms.start_date,
       CASE
       WHEN SYSDATE <= terms.end_date + 7 THEN
        1
       ELSE
        0
       END AS active
  FROM zbtm.terms_by_group_v terms
 WHERE 1 = 1
   AND terms.semester NOT IN ('WIN')
   AND terms.group_code IN ('STD')
   AND SYSDATE >= terms.start_date - 180
   AND SYSDATE <= terms.end_date + 180
 ORDER BY 1,2;
BEGIN
-- dbms_output.enable(buffer_size => NULL);
--
-- Calculate total number of loops
OPEN c_rec;
FETCH c_rec BULK COLLECT
INTO v_rec;
v_total_loops := v_rec.count;
CLOSE c_rec;
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
FOR rec IN c_rec
LOOP
v_loop_count := v_loop_count + 1; -- Increment loop count
v_count      := 0; -- reset count
dbms_lock.sleep(1); -- pause
v_elapsed    := round((SYSDATE - v_etl_date) * 86400);
v_msg        := 'START - Loop ' || v_loop_count || ' of ' || v_total_loops || ' - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- remove any students NOT enrolled anymore
IF rec.active = 1 THEN
DELETE FROM utl_d_aa.ml_student_financials tgt
 WHERE tgt.term_code = rec.term_code
   AND NOT EXISTS (SELECT 1
          FROM utl_d_aim.szrenrl src
         WHERE src.term_code = tgt.term_code
           AND src.pidm = tgt.pidm
           AND src.term_code = tgt.term_code);
v_count := SQL%ROWCOUNT;
COMMIT;
dbms_lock.sleep(1); -- pause
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'DELETE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
END IF;
-- Retry mechanism for handling deadlocks
LOOP
BEGIN
v_count := 0; --reset count
MERGE INTO utl_d_aa.ml_student_financials tgt
USING (SELECT src.term_code,
              src.pidm,
              src.scholarship,
              src.payments,
              src.tuition,
              src.outta_pocket,
              src.efc,
              src.burden,
              src.dgia,
              src.continuing_ed,
              src.hardship,
              src.activity_date,
              ora_hash(src.term_code || src.pidm || src.scholarship || src.payments || src.tuition || -- 
                       src.outta_pocket || src.efc || src.burden || src.dgia || src.continuing_ed || src.hardship) AS row_hash
         FROM (SELECT rec.term_code AS term_code,
                      fin.pidm,
                      coalesce(SUM(CASE
                                   WHEN tbbdetc_type_ind = 'P'
                                        AND tbbdetc_priority = 999 THEN
                                    fin.amount
                                   ELSE
                                    NULL
                                   END), 0) AS scholarship,
                      coalesce(SUM(CASE
                                   WHEN tbbdetc_type_ind = 'P'
                                        AND tbbdetc_priority < 999 THEN
                                    fin.amount
                                   ELSE
                                    NULL
                                   END), 0) AS payments,
                      coalesce(SUM(CASE
                                   WHEN tbbdetc_type_ind = 'C'
                                        AND tbbdetc_priority = 999 THEN
                                    fin.amount
                                   ELSE
                                    NULL
                                   END), 0) AS tuition,
                      coalesce(SUM(CASE
                                   WHEN tbbdetc_type_ind = 'C'
                                        AND tbbdetc_priority = 999 THEN
                                    fin.amount
                                   ELSE
                                    NULL
                                   END), 0) - coalesce(SUM(CASE
                                                           WHEN tbbdetc_type_ind = 'P'
                                                                AND tbbdetc_priority = 999 THEN
                                                            fin.amount
                                                           ELSE
                                                            NULL
                                                           END), 0) AS outta_pocket,
                      coalesce(MAX(efc), 0) AS efc,
                      CASE
                      WHEN (coalesce(SUM(CASE
                                         WHEN tbbdetc_type_ind = 'C'
                                              AND tbbdetc_priority = 999 THEN
                                          fin.amount
                                         ELSE
                                          NULL
                                         END), 0) - coalesce(SUM(CASE
                                                                  WHEN tbbdetc_type_ind = 'P'
                                                                       AND tbbdetc_priority = 999 THEN
                                                                   fin.amount
                                                                  ELSE
                                                                   NULL
                                                                  END), 0)) - coalesce(MAX(efc), 0) < 0 THEN
                       0
                      ELSE
                       (coalesce(SUM(CASE
                                     WHEN tbbdetc_type_ind = 'C'
                                          AND tbbdetc_priority = 999 THEN
                                      fin.amount
                                     ELSE
                                      NULL
                                     END), 0) - coalesce(SUM(CASE
                                                              WHEN tbbdetc_type_ind = 'P'
                                                                   AND tbbdetc_priority = 999 THEN
                                                               fin.amount
                                                              ELSE
                                                               NULL
                                                              END), 0)) - coalesce(MAX(efc), 0)
                      END AS burden,
                      MAX(CASE
                          WHEN detail_code IN ('F151', 'F152', 'F863', 'F864', 'F865') THEN
                           1
                          ELSE
                           0
                          END) AS dgia, -- Dependent Grant in Aid
                      MAX(CASE
                          WHEN detail_code IN ('F154', 'F866', 'F867', 'F868') THEN
                           1
                          ELSE
                           0
                          END) AS continuing_ed,
                      MAX(CASE
                          WHEN rrrareq_pidm IS NOT NULL THEN
                           1
                          ELSE
                           0
                          END) AS hardship,
                      v_etl_date AS activity_date
                 FROM (SELECT tbraccd.tbraccd_amount amount,
                              tbraccd_detail_code    detail_code,
                              tbraccd_pidm           AS pidm,
                              tbraccd_term_code      AS term_code
                         FROM tbraccd
                        WHERE 1 = 1
                          AND (tbraccd.tbraccd_term_code = rec.term_code)
                          AND tbraccd_detail_code NOT IN ('INSP', 'INPA')
                       UNION ALL
                       SELECT tbrmemo.tbrmemo_amount      amount,
                              tbrmemo.tbrmemo_detail_code detail_code,
                              tbrmemo_pidm                AS pidm,
                              tbrmemo_term_code           AS term_code
                         FROM tbrmemo
                        WHERE 1 = 1
                          AND trunc(coalesce(tbrmemo.tbrmemo_effective_date, rec.start_date)) <= rec.start_date
                          AND trunc(coalesce(tbrmemo.tbrmemo_expiration_date, rec.start_date + 1)) > rec.start_date
                          AND (tbrmemo.tbrmemo_term_code = rec.term_code)
                          AND tbrmemo_detail_code NOT IN ('INSP', 'INPA')
                       UNION ALL
                       SELECT rprauth.rprauth_amount      amount,
                              rfrbase.rfrbase_detail_code detail_code,
                              rprauth_pidm                AS pidm,
                              rprauth_term_code           AS term_code
                         FROM rprauth
                         JOIN rfrbase
                           ON rprauth.rprauth_fund_code = rfrbase.rfrbase_fund_code
                        WHERE 1 = 1
                          AND (rprauth.rprauth_term_code = rec.term_code)
                       UNION ALL
                       SELECT tbrdepo.tbrdepo_amount              amount,
                              tbrdepo.tbrdepo_detail_code_payment detail_code,
                              tbrdepo_pidm                        AS pidm,
                              tbrdepo_term_code                   AS term_code
                         FROM tbrdepo
                        WHERE 1 = 1
                          AND (tbrdepo.tbrdepo_term_code = rec.term_code OR tbrdepo.tbrdepo_term_code < rec.term_code)
                          AND tbrdepo.tbrdepo_effective_date <= rec.start_date
                          AND (tbrdepo.tbrdepo_expiration_date > rec.start_date OR tbrdepo.tbrdepo_expiration_date IS NULL)
                          AND tbrdepo_release_date > rec.start_date) fin
                 JOIN tbbdetc
                   ON tbbdetc.tbbdetc_detail_code = fin.detail_code
               -- FINANCIAL HARDSHIP 
                 LEFT JOIN rrrareq
                   ON rrrareq_pidm = fin.pidm
                  AND rrrareq_aidy_code = rec.aidy_code
                  AND rrrareq_treq_code IN ('PJAPP', 'PJCOA', 'PJDECI', 'PJLETT', 'PJUNTX')
               -- EFC
                 LEFT JOIN (SELECT rcrapp1_pidm AS pidm,
                                  rcrapp1_aidy_code AS aidy_code,
                                  CASE
                                  WHEN rcrapp2_pell_pgi < 0 THEN
                                   0
                                  ELSE
                                   rcrapp2_pell_pgi
                                  END AS efc
                             FROM rcrapp1
                             JOIN rcrapp2
                               ON rcrapp2_pidm = rcrapp1_pidm
                              AND rcrapp2_aidy_code = rcrapp1_aidy_code
                              AND rcrapp2_infc_code = rcrapp1_infc_code
                              AND rcrapp2_seq_no = rcrapp1_seq_no
                            WHERE rcrapp1_curr_rec_ind = 'Y'
                              AND rcrapp1_infc_code = 'EDE'
                              AND rcrapp1_aidy_code = rec.aidy_code) ede
                   ON ede.pidm = fin.pidm
                GROUP BY fin.pidm) src
       -- check for diffs comparing with ora_hash ** needs to match the select **
         LEFT JOIN utl_d_aa.ml_student_financials tgt
           ON tgt.row_hash = ora_hash(src.term_code || src.pidm || src.scholarship || src.payments || src.tuition || -- 
                                      src.outta_pocket || src.efc || src.burden || src.dgia || src.continuing_ed || src.hardship)
        WHERE tgt.row_hash IS NULL) src
ON (tgt.term_code = src.term_code AND tgt.pidm = src.pidm)
WHEN MATCHED THEN
UPDATE
   SET tgt.scholarship   = src.scholarship,
       tgt.payments      = src.payments,
       tgt.tuition       = src.tuition,
       tgt.outta_pocket  = src.outta_pocket,
       tgt.efc           = src.efc,
       tgt.burden        = src.burden,
       tgt.dgia          = src.dgia,
       tgt.continuing_ed = src.continuing_ed,
       tgt.hardship      = src.hardship,
       tgt.activity_date = src.activity_date
WHEN NOT MATCHED THEN
INSERT
(term_code,
 pidm,
 scholarship,
 payments,
 tuition,
 outta_pocket,
 efc,
 burden,
 dgia,
 continuing_ed,
 hardship,
 activity_date,
 row_hash)
VALUES
(src.term_code,
 src.pidm,
 src.scholarship,
 src.payments,
 src.tuition,
 src.outta_pocket,
 src.efc,
 src.burden,
 src.dgia,
 src.continuing_ed,
 src.hardship,
 src.activity_date,
 src.row_hash);
v_count := SQL%ROWCOUNT;
COMMIT;
dbms_lock.sleep(1); -- pause
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
EXIT; -- If successful, exit the retry loop
EXCEPTION
WHEN OTHERS THEN
IF SQLCODE = -60 THEN
-- Deadlock detected
v_retry_count := v_retry_count + 1;
IF v_retry_count > v_max_retries THEN
-- Log error for max retries
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := '!!!-00060: deadlock detected while waiting for resource. Max retries exceeded after ' || (v_max_retries * v_wait_time) || ' seconds';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
EXIT; -- Add EXIT here to break out of the loop when max retries exceeded
ELSE
-- Log retry attempt
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'Deadlock detected while waiting for resource - waiting ' || v_wait_time || ' seconds for retry attempt number ' || v_retry_count;
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'WARNING', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
dbms_lock.sleep(v_wait_time); -- Wait between retries; short wait because it will need to cycle through all the GTTs again
CONTINUE; -- Add CONTINUE to explicitly indicate loop continuation
END IF;
ELSE
-- Other errors
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
EXIT; -- Add EXIT here to break out of the loop for non-deadlock errors
END IF;
END;
END LOOP; -- end deadlock detection
dbms_output.put_line(' --------- ');
END LOOP; -- c_rec 
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
-- log any errors
EXCEPTION
WHEN OTHERS THEN
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
/*--------------------------------------------CHANGE LOG----------------------------------------
VERSION  DATE        USERNAME    UPDATES
---     06-09-2025  WGRIFFITH2  --Initial release 
------------------------------------------------------------------------------------------------*/
END etl_aa_ml_student_financials;

procedure etl_aa_ml_student_academics (jobnumber NUMBER, processid VARCHAR2, processname VARCHAR2, inst VARCHAR2, nmbr NUMBER) IS
/*

Unique index: TERM_CODE, CRN, PIDM

Purpose:
- Staging data for academics predictive models

Conditions:
- Must be banner enrolled

*/ 
--DECLARE
--- PARAMS
v_etl_date    DATE := SYSDATE;
v_msg         VARCHAR2(2000);
v_instance    VARCHAR2(50) := upper('L2CAN'); -- inst from the jams job; used for determining instance
v_partition    NUMBER := nmbr; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_mod         NUMBER := 5; -- number of partitions to be created 
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_aa_ml_student_academics';
v_loop_count  NUMBER := 0; -- Variable to track the current loop iteration
v_total_loops NUMBER := 0; -- Variable to track the total number of loops
v_retry_count NUMBER := 0;
v_max_retries NUMBER := 3; -- number of retries for WAIT
v_wait_time   NUMBER := 120; -- seconds for WAIT
TYPE r_rec IS RECORD(
term_code  VARCHAR2(6),
group_code VARCHAR2(3),
active     NUMBER);
TYPE t_rec IS TABLE OF r_rec;
v_rec t_rec;
CURSOR c_rec IS
SELECT terms.term_code,
       terms.group_code,
       CASE
       WHEN SYSDATE <= terms.end_date + 7 THEN
        1
       ELSE
        0
       END AS active
  FROM zbtm.terms_by_group_v terms
 WHERE 1 = 1
   AND terms.semester NOT IN ('WIN')
   AND terms.group_code IN ('STD')
   AND SYSDATE >= terms.start_date - 180
   AND SYSDATE <= terms.end_date + 180
 ORDER BY 1;
BEGIN
-- dbms_output.enable(buffer_size => NULL);
--
-- Calculate total number of loops
OPEN c_rec;
FETCH c_rec BULK COLLECT
INTO v_rec;
v_total_loops := v_rec.count;
CLOSE c_rec;
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
FOR rec IN c_rec
LOOP
v_loop_count := v_loop_count + 1; -- Increment loop count
v_count      := 0; -- reset count
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - Loop ' || v_loop_count || ' of ' || v_total_loops || ' - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- Retry mechanism for handling deadlocks
LOOP
BEGIN
  -- remove any students NOT enrolled anymore
IF rec.active = 1 THEN
DELETE FROM utl_d_aa.ml_student_academics tgt
 WHERE tgt.term_code = rec.term_code
   AND NOT EXISTS (SELECT 1
          FROM utl_d_aim.szrcrse src
         WHERE src.term_code = tgt.term_code
           AND src.crn = tgt.crn
           AND src.pidm = tgt.pidm
           AND src.term_code = tgt.term_code);
v_count := SQL%ROWCOUNT;
COMMIT;
dbms_lock.sleep(1); -- pause
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'DELETE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
END IF;
v_count := 0; --reset count
MERGE INTO utl_d_aa.ml_student_academics tgt
USING (SELECT src.term_code,
              src.crn,
              src.pidm,
              src.fci_complete_delta,
              src.reg_complete_delta,
              src.enrl_status,
              src.term_seats,
              src.term_hours,
              src.res_hours,
              src.luo_hours,
              src.a_hours,
              src.b_hours,
              src.c_hours,
              src.d_hours,
              src.j_hours,
              src.r_hours,
              src.gpa_asof_term,
              src.cum_hours_asof_term,
              src.tran_hours,
              src.hs_gpa,
              src.stu_acad_avg_grade,
              src.stu_acad_p_pct,
              src.stu_acad_w_pct,
              src.stu_acad_fn_pct,
              src.stu_acad_seat_cnt,
              src.crse_avg_grade_peer,
              src.crse_p_pct_peer,
              src.crse_w_pct_peer,
              src.crse_fn_pct_peer,
              src.stu_crse_seat_cnt,
              src.subj_avg_grade_peer,
              src.subj_p_pct_peer,
              src.subj_w_pct_peer,
              src.subj_fn_pct_peer,
              src.stu_subj_avg_grade,
              src.stu_subj_p_pct,
              src.stu_subj_w_pct,
              src.stu_subj_fn_pct,
              src.stu_subj_seat_cnt,
              src.coll_avg_grade_peer,
              src.coll_p_pct_peer,
              src.coll_w_pct_peer,
              src.coll_fn_pct_peer,
              src.stu_coll_avg_grade,
              src.stu_coll_p_pct,
              src.stu_coll_w_pct,
              src.stu_coll_fn_pct,
              src.stu_coll_seat_cnt,
              src.prof_avg_grade_peer,
              src.prof_p_pct_peer,
              src.prof_w_pct_peer,
              src.prof_fn_pct_peer,
              src.stu_prof_seat_cnt,
              src.age,
              src.gender,
              src.ethnicity,
              src.miltary,
              src.activity_date,
              -- check for diffs comparing with ora_hash ** needs to match the where clause **
              ora_hash(src.term_code || src.crn || src.pidm || src.term_hours || src.gpa_asof_term || src.fci_complete_delta || src.reg_complete_delta || --
                       src.stu_acad_avg_grade || src.crse_avg_grade_peer || src.subj_avg_grade_peer || src.stu_subj_avg_grade || src.coll_avg_grade_peer || src.stu_coll_avg_grade || src.prof_avg_grade_peer || --
                       src.age || src.gender || src.ethnicity || src.miltary) AS row_hash
         FROM (SELECT szrcrse.term_code,
                      szrcrse.crn,
                      szrcrse.pidm,
                      -- REG/FCI STATUS
                      CASE
                      WHEN round(szrenrl.fci_date - szrcrse.ptrm_start) > 99 THEN
                       99
                      ELSE
                       nvl(round(szrenrl.fci_date - szrcrse.ptrm_start), 99)
                      END AS fci_complete_delta, -- max out at 99 days if null
                      CASE
                      WHEN round(szrcrse.add_date - szrcrse.ptrm_start) > 99 THEN
                       99
                      ELSE
                       nvl(round(szrcrse.add_date - szrcrse.ptrm_start), 99)
                      END AS reg_complete_delta, -- max out at 99 days if null
                      CASE
                      WHEN szrenrl.status = 'FT' THEN
                       1
                      ELSE
                       0
                      END AS enrl_status,
                      nvl(szrenrl.term_seats, 0) AS term_seats,
                      nvl(szrenrl.term_hours, 0) AS term_hours,
                      nvl(szrenrl.res_hours, 0) AS res_hours,
                      nvl(szrenrl.luo_hours, 0) AS luo_hours,
                      nvl(szrenrl.a_hours, 0) AS a_hours,
                      nvl(szrenrl.b_hours, 0) AS b_hours,
                      nvl(szrenrl.c_hours, 0) AS c_hours,
                      nvl(szrenrl.d_hours, 0) AS d_hours,
                      nvl(szrenrl.j_hours, 0) AS j_hours,
                      nvl(szrenrl.r_hours, 0) AS r_hours,
                      -- HISTORICAL ACADEMICS
                      coalesce(szrenrl.gpa_asof_term, hs.hs_gpa - 0.45, acadperform.avg_grade_asof_term_peer - 0.1) AS gpa_asof_term, -- assigning penalties if student is new
                      nvl(szrenrl.cum_hours_asof_term, 0) AS cum_hours_asof_term,
                      nvl(szrenrl.tran_hours, 0) AS tran_hours,
                      hs.hs_gpa AS hs_gpa,
                      -- ALL academic performance
                      -- PEER is average of all students performance in each measure
                      -- STU is average of the specific student performance in each measure
                      -- NULL data will be imputed with average of dataset
                      -- ALL academic STU performance
                      coalesce(acadperform.avg_grade_asof_term, acadperform.avg_grade_asof_term_peer, acadperform.avg_grade_peer) AS stu_acad_avg_grade,
                      coalesce(acadperform.p_pct_asof_term, acadperform.p_pct_asof_term_peer, acadperform.p_pct_peer) AS stu_acad_p_pct,
                      coalesce(acadperform.w_pct_asof_term, acadperform.w_pct_asof_term_peer, acadperform.w_pct_peer) AS stu_acad_w_pct,
                      coalesce(acadperform.fn_pct_asof_term, acadperform.fn_pct_asof_term_peer, acadperform.fn_pct_peer) AS stu_acad_fn_pct,
                      coalesce(acadperform.seat_cnt, 0) AS stu_acad_seat_cnt, -- how many total courses taken so far
                      -- course PEER performance (there is not course / student performance because it is too rare)
                      coalesce(crseperform.avg_grade_asof_term_peer, crseperform.avg_grade_peer, subjperform.avg_grade_asof_term_peer, subjperform.avg_grade_peer, collperform.avg_grade_asof_term_peer, collperform.avg_grade_peer, acadperform.avg_grade_asof_term_peer, acadperform.avg_grade_peer) AS crse_avg_grade_peer,
                      coalesce(crseperform.p_pct_asof_term_peer, crseperform.p_pct_peer, subjperform.p_pct_asof_term_peer, subjperform.p_pct_peer, collperform.p_pct_asof_term_peer, collperform.p_pct_peer, acadperform.p_pct_asof_term, acadperform.p_pct_asof_term_peer) AS crse_p_pct_peer,
                      coalesce(crseperform.w_pct_asof_term_peer, crseperform.w_pct_peer, subjperform.w_pct_asof_term_peer, subjperform.w_pct_peer, collperform.w_pct_asof_term_peer, collperform.w_pct_peer, acadperform.w_pct_asof_term, acadperform.w_pct_asof_term_peer) AS crse_w_pct_peer,
                      coalesce(crseperform.fn_pct_asof_term_peer, crseperform.fn_pct_peer, subjperform.fn_pct_asof_term_peer, subjperform.fn_pct_peer, collperform.fn_pct_asof_term_peer, collperform.fn_pct_peer, acadperform.fn_pct_asof_term, acadperform.fn_pct_asof_term_peer) AS crse_fn_pct_peer,
                      coalesce((SELECT COUNT(*)
                                 FROM utl_d_aim.szrcrse rt
                                WHERE rt.term_code <= rec.term_code
                                  AND rt.pidm = szrcrse.pidm
                                  AND rt.subj || rt.numb = szrcrse.subj || szrcrse.numb), 0) AS stu_crse_seat_cnt, -- RETAKING COURSE IF > 1
                      -- subject PEER performance
                      coalesce(subjperform.avg_grade_asof_term_peer, subjperform.avg_grade_peer, collperform.avg_grade_asof_term_peer, collperform.avg_grade_peer, acadperform.avg_grade_asof_term_peer, acadperform.avg_grade_peer) AS subj_avg_grade_peer,
                      coalesce(subjperform.p_pct_asof_term_peer, subjperform.p_pct_peer, collperform.p_pct_asof_term_peer, collperform.p_pct_peer, acadperform.p_pct_asof_term_peer, acadperform.p_pct_peer) AS subj_p_pct_peer,
                      coalesce(subjperform.w_pct_asof_term_peer, subjperform.w_pct_peer, collperform.w_pct_asof_term_peer, collperform.w_pct_peer, acadperform.w_pct_asof_term_peer, acadperform.w_pct_peer) AS subj_w_pct_peer,
                      coalesce(subjperform.fn_pct_asof_term_peer, subjperform.fn_pct_peer, collperform.fn_pct_asof_term_peer, collperform.fn_pct_peer, acadperform.fn_pct_asof_term_peer, acadperform.fn_pct_peer) AS subj_fn_pct_peer,
                      -- subject STU performance
                      coalesce(subjperform.avg_grade_asof_term, collperform.avg_grade_asof_term, acadperform.avg_grade_asof_term, subjperform.avg_grade_asof_term_peer) AS stu_subj_avg_grade,
                      coalesce(subjperform.p_pct_asof_term, collperform.p_pct_asof_term, acadperform.p_pct_asof_term, subjperform.p_pct_asof_term_peer) AS stu_subj_p_pct,
                      coalesce(subjperform.w_pct_asof_term, collperform.w_pct_asof_term, acadperform.w_pct_asof_term, subjperform.w_pct_asof_term_peer) AS stu_subj_w_pct,
                      coalesce(subjperform.fn_pct_asof_term, collperform.fn_pct_asof_term, acadperform.fn_pct_asof_term, subjperform.fn_pct_asof_term_peer) AS stu_subj_fn_pct,
                      coalesce(subjperform.seat_cnt, 0) AS stu_subj_seat_cnt, -- how many courses in same subject taken so far
                      -- college PEER performance
                      coalesce(collperform.avg_grade_asof_term_peer, collperform.avg_grade_peer, acadperform.avg_grade_asof_term_peer, acadperform.avg_grade_peer) AS coll_avg_grade_peer,
                      coalesce(collperform.p_pct_asof_term_peer, collperform.p_pct_peer, acadperform.p_pct_asof_term_peer, acadperform.p_pct_peer) AS coll_p_pct_peer,
                      coalesce(collperform.w_pct_asof_term_peer, collperform.w_pct_peer, acadperform.w_pct_asof_term_peer, acadperform.w_pct_peer) AS coll_w_pct_peer,
                      coalesce(collperform.fn_pct_asof_term_peer, collperform.fn_pct_peer, acadperform.fn_pct_asof_term_peer, acadperform.fn_pct_peer) AS coll_fn_pct_peer,
                      -- college STU performance
                      coalesce(collperform.avg_grade_asof_term, acadperform.avg_grade_asof_term, collperform.avg_grade_asof_term_peer, acadperform.avg_grade_peer) AS stu_coll_avg_grade,
                      coalesce(collperform.p_pct_asof_term, acadperform.p_pct_asof_term, collperform.p_pct_asof_term_peer, acadperform.p_pct_peer) AS stu_coll_p_pct,
                      coalesce(collperform.w_pct_asof_term, acadperform.w_pct_asof_term, collperform.w_pct_asof_term_peer, acadperform.w_pct_peer) AS stu_coll_w_pct,
                      coalesce(collperform.fn_pct_asof_term, acadperform.fn_pct_asof_term, collperform.fn_pct_asof_term_peer, acadperform.fn_pct_peer) AS stu_coll_fn_pct,
                      coalesce(collperform.seat_cnt, 0) AS stu_coll_seat_cnt, -- how many courses in same college taken so far
                      -- instructor PEER performance (there is not instructor / student performance because it is too rare)
                      coalesce(profperform.avg_grade_asof_term_peer, profperform.avg_grade_peer, crseperform.avg_grade_asof_term_peer, crseperform.avg_grade_peer, subjperform.avg_grade_asof_term_peer, subjperform.avg_grade_peer, collperform.avg_grade_asof_term_peer, collperform.avg_grade_peer, acadperform.avg_grade_asof_term_peer, acadperform.avg_grade_peer) AS prof_avg_grade_peer,
                      coalesce(profperform.p_pct_asof_term_peer, profperform.p_pct_peer, crseperform.p_pct_asof_term_peer, crseperform.p_pct_peer, subjperform.p_pct_asof_term_peer, subjperform.p_pct_peer, collperform.p_pct_asof_term_peer, collperform.p_pct_peer, acadperform.p_pct_asof_term_peer, acadperform.p_pct_peer) AS prof_p_pct_peer,
                      coalesce(profperform.w_pct_asof_term_peer, profperform.w_pct_peer, crseperform.w_pct_asof_term_peer, crseperform.w_pct_peer, subjperform.w_pct_asof_term_peer, subjperform.w_pct_peer, collperform.w_pct_asof_term_peer, collperform.w_pct_peer, acadperform.w_pct_asof_term_peer, acadperform.w_pct_peer) AS prof_w_pct_peer,
                      coalesce(profperform.fn_pct_asof_term_peer, profperform.fn_pct_peer, crseperform.fn_pct_asof_term_peer, crseperform.fn_pct_peer, subjperform.fn_pct_asof_term_peer, subjperform.fn_pct_peer, collperform.fn_pct_asof_term_peer, collperform.fn_pct_peer, acadperform.fn_pct_asof_term_peer, acadperform.fn_pct_peer) AS prof_fn_pct_peer,
                      coalesce(profperform.seat_cnt_peer, 0) AS stu_prof_seat_cnt, -- how many students this instructor had so far
                      -- BIOGRAPHICAL
                      szrenrl.age AS age,
                      CASE
                      WHEN szrenrl.gender = 'F' THEN
                       1
                      WHEN szrenrl.gender = 'M' THEN
                       2
                      ELSE
                       0
                      END AS gender,
                      CASE
                      WHEN szrenrl.ipeds_ethn = 'American_Indian_Alaska_Native' THEN
                       1
                      WHEN szrenrl.ipeds_ethn = 'Black_or_African_American' THEN
                       2
                      WHEN szrenrl.ipeds_ethn = 'Hispanic_Latino' THEN
                       3
                      WHEN szrenrl.ipeds_ethn = 'Native_Hawaiian_Pacific_Islander' THEN
                       4
                      WHEN szrenrl.ipeds_ethn = 'Two_or_more_races' THEN
                       5
                      WHEN szrenrl.ipeds_ethn = 'Nonresident_Alien' THEN
                       6
                      WHEN szrenrl.ipeds_ethn = 'White' THEN
                       7
                      WHEN szrenrl.ipeds_ethn = 'Asian' THEN
                       8
                      ELSE
                       0
                      END AS ethnicity,
                      to_number(nvl(substr(szrenrl.milt_status, 1, 1), '0')) AS miltary, -- first char is a number value on this field and that is all we need
                      v_etl_date AS activity_date
               -- szrcrse - section | course joins
                 FROM utl_d_aim.szrcrse
               -- szrenrl - term to term enrollment joins
                 JOIN utl_d_aim.szrenrl
                   ON szrenrl.term_code = szrcrse.term_code
                  AND szrenrl.pidm = szrcrse.pidm
                  AND szrcrse.term_code = rec.term_code
                  AND szrenrl.group_code IN ('STD')
                  AND szrenrl.semester NOT IN ('WIN')
                  AND szrcrse.ptrm_code NOT IN ('1P')
                  AND MOD(szrcrse.pidm, v_mod) = v_partition
               -- academic performance
                 LEFT JOIN utl_d_aa.stuacadperform acadperform
                   ON acadperform.term_code = szrcrse.term_code
                  AND acadperform.pidm = szrcrse.pidm
               -- college performance
                 LEFT JOIN utl_d_aa.stucollperform collperform
                   ON collperform.term_code = szrcrse.term_code
                  AND collperform.pidm = szrcrse.pidm
                  AND collperform.coll_code = szrcrse.coll_code
               -- subject performance
                 LEFT JOIN utl_d_aa.stusubjperform subjperform
                   ON subjperform.term_code = szrcrse.term_code
                  AND subjperform.pidm = szrcrse.pidm
                  AND subjperform.subj_code = szrcrse.subj
               -- course performance (peer only)
                 LEFT JOIN utl_d_aa.stucrseperform crseperform
                   ON crseperform.term_code = szrcrse.term_code
                  AND crseperform.course = szrcrse.course -- only join on course and not student pidm
               -- professor performance (peer only)
                 LEFT JOIN utl_d_aa.stuprofperform profperform
                   ON profperform.term_code = szrcrse.term_code
                  AND profperform.prof_pidm = szrcrse.faculty_pidm -- only join on prof_pidm and not student pidm
               -- HS GPA
                 LEFT JOIN utl_d_aa.stuhsgpa hs
                   ON hs.pidm = szrcrse.pidm) src
       -- check for diffs comparing with ora_hash ** needs to match the select **
         LEFT JOIN utl_d_aa.ml_student_academics tgt
           ON tgt.row_hash = ora_hash(src.term_code || src.crn || src.pidm || src.term_hours || src.gpa_asof_term || src.fci_complete_delta || src.reg_complete_delta || --
                                      src.stu_acad_avg_grade || src.crse_avg_grade_peer || src.subj_avg_grade_peer || src.stu_subj_avg_grade || src.coll_avg_grade_peer || src.stu_coll_avg_grade || src.prof_avg_grade_peer || --
                                      src.age || src.gender || src.ethnicity || src.miltary)
        WHERE tgt.row_hash IS NULL) src
ON (tgt.term_code = src.term_code AND tgt.crn = src.crn AND tgt.pidm = src.pidm)
WHEN MATCHED THEN
UPDATE
   SET tgt.fci_complete_delta  = src.fci_complete_delta,
       tgt.reg_complete_delta  = src.reg_complete_delta,
       tgt.enrl_status         = src.enrl_status,
       tgt.term_seats          = src.term_seats,
       tgt.term_hours          = src.term_hours,
       tgt.res_hours           = src.res_hours,
       tgt.luo_hours           = src.luo_hours,
       tgt.a_hours             = src.a_hours,
       tgt.b_hours             = src.b_hours,
       tgt.c_hours             = src.c_hours,
       tgt.d_hours             = src.d_hours,
       tgt.j_hours             = src.j_hours,
       tgt.r_hours             = src.r_hours,
       tgt.gpa_asof_term       = src.gpa_asof_term,
       tgt.cum_hours_asof_term = src.cum_hours_asof_term,
       tgt.tran_hours          = src.tran_hours,
       tgt.hs_gpa              = src.hs_gpa,
       tgt.stu_acad_avg_grade  = src.stu_acad_avg_grade,
       tgt.stu_acad_p_pct      = src.stu_acad_p_pct,
       tgt.stu_acad_w_pct      = src.stu_acad_w_pct,
       tgt.stu_acad_fn_pct     = src.stu_acad_fn_pct,
       tgt.stu_acad_seat_cnt   = src.stu_acad_seat_cnt,
       tgt.crse_avg_grade_peer = src.crse_avg_grade_peer,
       tgt.crse_p_pct_peer     = src.crse_p_pct_peer,
       tgt.crse_w_pct_peer     = src.crse_w_pct_peer,
       tgt.crse_fn_pct_peer    = src.crse_fn_pct_peer,
       tgt.stu_crse_seat_cnt   = src.stu_crse_seat_cnt,
       tgt.subj_avg_grade_peer = src.subj_avg_grade_peer,
       tgt.subj_p_pct_peer     = src.subj_p_pct_peer,
       tgt.subj_w_pct_peer     = src.subj_w_pct_peer,
       tgt.subj_fn_pct_peer    = src.subj_fn_pct_peer,
       tgt.stu_subj_avg_grade  = src.stu_subj_avg_grade,
       tgt.stu_subj_p_pct      = src.stu_subj_p_pct,
       tgt.stu_subj_w_pct      = src.stu_subj_w_pct,
       tgt.stu_subj_fn_pct     = src.stu_subj_fn_pct,
       tgt.stu_subj_seat_cnt   = src.stu_subj_seat_cnt,
       tgt.coll_avg_grade_peer = src.coll_avg_grade_peer,
       tgt.coll_p_pct_peer     = src.coll_p_pct_peer,
       tgt.coll_w_pct_peer     = src.coll_w_pct_peer,
       tgt.coll_fn_pct_peer    = src.coll_fn_pct_peer,
       tgt.stu_coll_avg_grade  = src.stu_coll_avg_grade,
       tgt.stu_coll_p_pct      = src.stu_coll_p_pct,
       tgt.stu_coll_w_pct      = src.stu_coll_w_pct,
       tgt.stu_coll_fn_pct     = src.stu_coll_fn_pct,
       tgt.stu_coll_seat_cnt   = src.stu_coll_seat_cnt,
       tgt.prof_avg_grade_peer = src.prof_avg_grade_peer,
       tgt.prof_p_pct_peer     = src.prof_p_pct_peer,
       tgt.prof_w_pct_peer     = src.prof_w_pct_peer,
       tgt.prof_fn_pct_peer    = src.prof_fn_pct_peer,
       tgt.stu_prof_seat_cnt   = src.stu_prof_seat_cnt,
       tgt.age                 = src.age,
       tgt.gender              = src.gender,
       tgt.ethnicity           = src.ethnicity,
       tgt.miltary             = src.miltary,
       tgt.activity_date       = src.activity_date
WHEN NOT MATCHED THEN
INSERT
(term_code,
 crn,
 pidm,
 fci_complete_delta,
 reg_complete_delta,
 enrl_status,
 term_seats,
 term_hours,
 res_hours,
 luo_hours,
 a_hours,
 b_hours,
 c_hours,
 d_hours,
 j_hours,
 r_hours,
 gpa_asof_term,
 cum_hours_asof_term,
 tran_hours,
 hs_gpa,
 stu_acad_avg_grade,
 stu_acad_p_pct,
 stu_acad_w_pct,
 stu_acad_fn_pct,
 stu_acad_seat_cnt,
 crse_avg_grade_peer,
 crse_p_pct_peer,
 crse_w_pct_peer,
 crse_fn_pct_peer,
 stu_crse_seat_cnt,
 subj_avg_grade_peer,
 subj_p_pct_peer,
 subj_w_pct_peer,
 subj_fn_pct_peer,
 stu_subj_avg_grade,
 stu_subj_p_pct,
 stu_subj_w_pct,
 stu_subj_fn_pct,
 stu_subj_seat_cnt,
 coll_avg_grade_peer,
 coll_p_pct_peer,
 coll_w_pct_peer,
 coll_fn_pct_peer,
 stu_coll_avg_grade,
 stu_coll_p_pct,
 stu_coll_w_pct,
 stu_coll_fn_pct,
 stu_coll_seat_cnt,
 prof_avg_grade_peer,
 prof_p_pct_peer,
 prof_w_pct_peer,
 prof_fn_pct_peer,
 stu_prof_seat_cnt,
 age,
 gender,
 ethnicity,
 miltary,
 activity_date,
 row_hash)
VALUES
(src.term_code,
 src.crn,
 src.pidm,
 src.fci_complete_delta,
 src.reg_complete_delta,
 src.enrl_status,
 src.term_seats,
 src.term_hours,
 src.res_hours,
 src.luo_hours,
 src.a_hours,
 src.b_hours,
 src.c_hours,
 src.d_hours,
 src.j_hours,
 src.r_hours,
 src.gpa_asof_term,
 src.cum_hours_asof_term,
 src.tran_hours,
 src.hs_gpa,
 src.stu_acad_avg_grade,
 src.stu_acad_p_pct,
 src.stu_acad_w_pct,
 src.stu_acad_fn_pct,
 src.stu_acad_seat_cnt,
 src.crse_avg_grade_peer,
 src.crse_p_pct_peer,
 src.crse_w_pct_peer,
 src.crse_fn_pct_peer,
 src.stu_crse_seat_cnt,
 src.subj_avg_grade_peer,
 src.subj_p_pct_peer,
 src.subj_w_pct_peer,
 src.subj_fn_pct_peer,
 src.stu_subj_avg_grade,
 src.stu_subj_p_pct,
 src.stu_subj_w_pct,
 src.stu_subj_fn_pct,
 src.stu_subj_seat_cnt,
 src.coll_avg_grade_peer,
 src.coll_p_pct_peer,
 src.coll_w_pct_peer,
 src.coll_fn_pct_peer,
 src.stu_coll_avg_grade,
 src.stu_coll_p_pct,
 src.stu_coll_w_pct,
 src.stu_coll_fn_pct,
 src.stu_coll_seat_cnt,
 src.prof_avg_grade_peer,
 src.prof_p_pct_peer,
 src.prof_w_pct_peer,
 src.prof_fn_pct_peer,
 src.stu_prof_seat_cnt,
 src.age,
 src.gender,
 src.ethnicity,
 src.miltary,
 src.activity_date,
 src.row_hash);
v_count := SQL%ROWCOUNT;
COMMIT;
dbms_lock.sleep(1); -- pause
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
EXIT; -- If successful, exit the retry loop
EXCEPTION
WHEN OTHERS THEN
IF SQLCODE = -60 THEN
-- Deadlock detected
v_retry_count := v_retry_count + 1;
IF v_retry_count > v_max_retries THEN
-- Log error for max retries
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := '!!!-00060: deadlock detected while waiting for resource. Max retries exceeded after ' || (v_max_retries * v_wait_time) || ' seconds';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
EXIT; -- Add EXIT here to break out of the loop when max retries exceeded
ELSE
-- Log retry attempt
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'Deadlock detected while waiting for resource - waiting ' || v_wait_time || ' seconds for retry attempt number ' || v_retry_count;
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'WARNING', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
dbms_lock.sleep(v_wait_time); -- Wait between retries; short wait because it will need to cycle through all the GTTs again
CONTINUE; -- Add CONTINUE to explicitly indicate loop continuation
END IF;
ELSE
-- Other errors
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
EXIT; -- Add EXIT here to break out of the loop for non-deadlock errors
END IF;
END;
END LOOP; -- end deadlock detection
dbms_output.put_line(' --------- ');
END LOOP; -- c_rec
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
-- log any errors
EXCEPTION
WHEN OTHERS THEN
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
/*--------------------------------------------CHANGE LOG----------------------------------------
VERSION  DATE        USERNAME    UPDATES
---     06-09-2025  wgriffith2  --Initial release
---     07-03-2025  wgriffith2  --Updated fields to accomodate changes on the stuprofperform table 
---     07-09-2025  wgriffith2  --Update to code related to changes to the etl_aa_stucrseperform_refresh procedure
---     07-21-2025  wgriffith2  --adding partitioning with v_partition and v_mod on the pidm 
------------------------------------------------------------------------------------------------*/
END etl_aa_ml_student_academics;

PROCEDURE etl_aa_ml_crscompcrs_refresh(jobnumber NUMBER, processid VARCHAR2, processname VARCHAR2) IS
/*
Table: zlighthouse_whs.ml_crscompcrs

Primary Keys: None

Unique index: PIDM, TERM_CODE, CRN

Purpose:
- Controls the courses that show for MyStudents

Conditions:
-

*/
--DECLARE
--- PARAMS
v_etl_date DATE := SYSDATE;
v_msg      VARCHAR2(2000);
v_instance VARCHAR2(50) := upper('ALL'); -- inst from the jams job; used for determining instance
v_partition NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_aa_ml_crscompcrs_refresh';
CURSOR c_terms IS
SELECT DISTINCT term_code
  FROM utl_d_aim.szrcrse
 WHERE group_code = 'STD'
   AND ptrm_code IN ('R', '1A', '1B', '1C', '1D', '1J')
   AND trunc(SYSDATE) BETWEEN ptrm_start - 7 AND ptrm_end + 1
 ORDER BY 1;
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
v_count := 0; -- reset count
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
MERGE INTO zlighthouse_whs.ml_crscompcrs t1
USING (SELECT src.activity_date,
              src.pidm,
              src.crn,
              src.term_code,
              src.bb_crse_id,
              src.ptrm_code,
              src.ptrm_start,
              src.ptrm_end,
              src.retake_course,
              src.insm_code,
              src.camp_code,
              src.exclusions,
              src.in_ccp
         FROM (SELECT v_etl_date AS activity_date,
                      szrcrse.pidm,
                      szrcrse.crn,
                      szrcrse.term_code,
                      szrcrse.subj || szrcrse.numb || '_' || szrcrse.sect || '_' || szrcrse.term_code AS bb_crse_id,
                      szrcrse.ptrm_code,
                      szrcrse.ptrm_start,
                      szrcrse.ptrm_end,
                      CASE
                      WHEN coalesce(rt.seat_cnt, 0) > 1 THEN
                       'Yes (' || coalesce(rt.seat_cnt, 0) || ')' -- number of times student has taken the course
                      ELSE
                       'No'
                      END AS retake_course,
                      szrcrse.insm_code,
                      szrcrse.camp_code,
                      CASE
                      WHEN xl.crn IS NOT NULL THEN
                       'Other'
                      ELSE
                       NULL
                      END AS exclusions,
                      CASE
                      WHEN substr(szrcrse.numb, 1, 1) IN ('0') THEN
                       'N'
                      WHEN szrcrse.subj IN ('CSER', 'CAFE', 'SFME', 'FRSM', 'NEWS', 'NSSR', 'LAW') THEN
                       'N'
                      WHEN substr(szrcrse.sect, 2, 1) = 'E' THEN
                       'N'
                      WHEN szrcrse.ptrm_code IN ('1J') THEN
                       'N'
                      WHEN szrcrse.ptrm_code IN ('1A', '1B', '1C', '1D')
                           AND szrcrse.insm_code = 'ON' THEN
                       'Y'
                      WHEN (szrcrse.camp_code = 'D' OR (szrcrse.camp_code = 'R' AND szrcrse.insm_code = 'ON')) THEN
                       'Y'
                      ELSE
                       'N'
                      END AS in_ccp
                 FROM utl_d_aim.szrcrse
                 JOIN zsaturn.szrlevl lvl
                   ON lvl.szrlevl_levl_code = szrcrse.levl_code
                  AND lvl.szrlevl_has_awardable_cred = 'Y' -- remove EM
                  AND szrcrse.subj NOT IN ('CSER', 'CAFE', 'SFME', 'FRSM', 'NEWS', 'NSSR')
                  AND szrcrse.ptrm_code IN ('R', '1A', '1B', '1C', '1D', '1J')
                  AND szrcrse.group_code = 'STD'
               -- RETAKES
                 LEFT JOIN (SELECT rt.pidm,
                                  rt.course,
                                  COUNT(*) AS seat_cnt
                             FROM utl_d_aim.szrcrse rt
                            WHERE rt.term_code <= rec.term_code
                            GROUP BY rt.pidm,
                                     rt.course) rt
                   ON rt.pidm = szrcrse.pidm
                  AND rt.course = szrcrse.course
               -- EXCLUSIONS 
                 LEFT JOIN (SELECT ce.crn,
                                  ce.term_code,
                                  ce.instructional_method
                             FROM utl_d_lms.course_exclusions ce
                            WHERE ce.term_code = rec.term_code
                              AND ce.nudges = 'Exclude') xl
                   ON xl.term_code = szrcrse.term_code
                  AND xl.crn = szrcrse.crn
                WHERE szrcrse.term_code = rec.term_code
                  AND szrcrse.final_grade IS NULL -- REMOVE ANYONE THAT WITHDRAW/FN
                  AND v_etl_date >= szrcrse.ptrm_start - 7
                  AND v_etl_date < szrcrse.ptrm_end + 1) src
       -- target table
         LEFT JOIN zlighthouse_whs.ml_crscompcrs tgt
           ON tgt.term_code = src.term_code
          AND tgt.crn = src.crn
          AND tgt.pidm = src.pidm
        WHERE 1 = 1
          AND (
              -- Check for inserts
               ((src.pidm IS NULL AND tgt.pidm IS NOT NULL) OR (src.pidm IS NOT NULL AND tgt.pidm IS NULL)) OR --
              -- Check for updates if any data has changed
               (coalesce(src.bb_crse_id, 'X') <> coalesce(tgt.bb_crse_id, 'X')) OR --
               (coalesce(src.ptrm_code, 'X') <> coalesce(tgt.ptrm_code, 'X')) OR --
               (coalesce(src.ptrm_start, SYSDATE) <> coalesce(tgt.ptrm_start, SYSDATE)) OR --
               (coalesce(src.ptrm_end, SYSDATE) <> coalesce(tgt.ptrm_end, SYSDATE)) OR --
               (coalesce(src.retake_course, 'X') <> coalesce(tgt.retake_course, 'X')) OR --
               (coalesce(src.insm_code, 'X') <> coalesce(tgt.insm_code, 'X')) OR --
               (coalesce(src.camp_code, 'X') <> coalesce(tgt.camp_code, 'X')) OR --
               (coalesce(src.exclusions, 'X') <> coalesce(tgt.exclusions, 'X')) OR --
               (coalesce(src.in_ccp, 'X') <> coalesce(tgt.in_ccp, 'X')))) t2
ON (t1.pidm = t2.pidm AND t1.crn = t2.crn AND t1.term_code = t2.term_code)
WHEN MATCHED THEN
UPDATE
   SET t1.bb_crse_id    = t2.bb_crse_id,
       t1.ptrm_code     = t2.ptrm_code,
       t1.ptrm_start    = t2.ptrm_start,
       t1.ptrm_end      = t2.ptrm_end,
       t1.retake_course = t2.retake_course,
       t1.insm_code     = t2.insm_code,
       t1.camp_code     = t2.camp_code,
       t1.exclusions    = t2.exclusions,
       t1.in_ccp        = t2.in_ccp,
       t1.activity_date = t2.activity_date
WHEN NOT MATCHED THEN
INSERT
VALUES
(v_etl_date,
 t2.pidm,
 t2.crn,
 t2.term_code,
 t2.bb_crse_id,
 t2.ptrm_code,
 t2.ptrm_start,
 t2.ptrm_end,
 t2.retake_course,
 t2.insm_code,
 t2.camp_code,
 t2.exclusions,
 t2.in_ccp);
v_count := SQL%ROWCOUNT;
COMMIT;
dbms_lock.sleep(1); -- pause
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
END LOOP; -- c_terms
IF to_char(v_etl_date, 'D') IN ('2', '5')
   AND to_char(SYSDATE, 'HH24') >= ('18') THEN
-- only run at specific times outside of high demand
-- remove any students NOT currently enrolled [dropped NOT withdraw]
DELETE FROM zlighthouse_whs.ml_crscompcrs a
 WHERE NOT EXISTS (SELECT 1
          FROM utl_d_aim.szrcrse
         WHERE group_code = 'STD'
           AND ptrm_code IN ('R', '1A', '1B', '1C', '1D', '1J')
           AND a.pidm = szrcrse.pidm
           AND a.crn = szrcrse.crn
           AND a.term_code = szrcrse.term_code);
v_count := SQL%ROWCOUNT;
COMMIT;
dbms_lock.sleep(1); -- pause
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'DELETE - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
END IF;
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
-- log any errors
EXCEPTION
WHEN OTHERS THEN
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
/*--------------------------------------------CHANGE LOG----------------------------------------
VERSION  DATE        USERNAME    UPDATES
---     07-18-2019  WGRIFFITH2  --Initial release
---     08-05-2019  WGRIFFITH2  --Moving from UTL_D_AA to zlighthouse_whs
---     10-25-2019  WGRIFFITH2  --Opening up the timeframe bc they need historical data [removing end of course delete]
---     11-18-2019  WGRIFFITH2  --Using utl_d_aim.szrcrse instead of the ml_crscompout; DEV team needs resident students and courses not in the model
---     03-06-2019  WGRIFFITH2  --Adding new columns CHG0125714
---     04-02-2020  WGRIFFITH2  --Old to new
---     01-23-2023  WGRIFFITH2  --Adding 1J ptrm with [IN_CCP]='N'
---     03-15-2023  WGRIFFITH2  --Switch to use LMS LINK; adding output to insert_job_log
---     02-13-2025  WGRIFFITH2  --Update to merge where only records that are new or need updating
---     03-10-2025  WGRIFFITH2  --Removing all LMS_LINK table dependencies; replaced with STUDENT_ENROLLMENTS table
---     07-09-2025  WGRIFFITH2  --Update to code related to changes to the etl_aa_stucrseperform_refresh procedure
------------------------------------------------------------------------------------------------*/
END etl_aa_ml_crscompcrs_refresh; --
PROCEDURE etl_aa_ml_crscompstu_refresh(jobnumber NUMBER, processid VARCHAR2, processname VARCHAR2) IS
/*
Table: zlighthouse_whs.ml_crscompstu

Primary Keys: None

Unique index: PIDM, TERM_CODE

Purpose:
- Controls the students that show for MyStudents

Conditions:
-

*/
--DECLARE
--- PARAMS
v_etl_date DATE := SYSDATE;
v_msg      VARCHAR2(2000);
v_instance VARCHAR2(50) := upper('ALL'); -- inst from the jams job; used for determining instance
v_partition NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0

v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_aa_ml_crscompstu_refresh';
CURSOR c_terms IS
SELECT DISTINCT term_code
  FROM utl_d_aim.szrcrse
 WHERE group_code = 'STD'
   AND ptrm_code IN ('R', '1A', '1B', '1C', '1D', '1J')
   AND trunc(SYSDATE) BETWEEN ptrm_start - 7 AND ptrm_end + 1
 ORDER BY 1;
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
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
MERGE INTO zlighthouse_whs.ml_crscompstu t1
USING (SELECT src.activity_date,
              src.pidm,
              src.luid,
              src.username,
              src.prog_code,
              src.prog_desc,
              src.gpa_asof_term,
              src.terms_cnt,
              src.phone
         FROM (SELECT v_etl_date AS activity_date,
                      enrl.pidm AS pidm,
                      spriden.spriden_id AS luid,
                      gobtpac_external_user AS username,
                      trm_cnt.cnt AS terms_cnt,
                      enrl.prog_code_1 AS prog_code,
                      prl.szvprle_web_display_degc AS prog_desc,
                      enrl.gpa_asof_term AS gpa_asof_term,
                      tele.phone_combo AS phone,
                      rank() over(PARTITION BY enrl.pidm ORDER BY trm_cnt.cnt DESC, rownum) AS ranking
                 FROM utl_d_aim.szrenrl enrl
                 JOIN spriden
                   ON spriden_pidm = enrl.pidm
                  AND enrl.term_code = rec.term_code
                  AND group_code = 'STD' -- standard terms ONLY
                  AND spriden_change_ind IS NULL
                 LEFT JOIN zexec.szvprle prl
                   ON prl.szvprle_program = enrl.prog_code_1
                 JOIN general.gobtpac
                   ON gobtpac_pidm = enrl.pidm
                 LEFT JOIN zexec.zsavtele tele
                   ON tele.pidm = enrl.pidm
                  AND tele.tele_rank = 1
               -- count how many semesters enrolled at current level
                 JOIN (SELECT szrenrl.pidm AS pidm,
                             szrenrl.levl_code AS levl_code,
                             COUNT(szrenrl.pidm) cnt
                        FROM utl_d_aim.szrenrl
                       WHERE szrenrl.term_code <= rec.term_code
                       GROUP BY szrenrl.pidm,
                                szrenrl.levl_code) trm_cnt
                   ON trm_cnt.pidm = enrl.pidm
                  AND trm_cnt.levl_code = enrl.levl_code) src
         LEFT JOIN zlighthouse_whs.ml_crscompstu tgt
           ON tgt.pidm = src.pidm
        WHERE ranking = 1
          AND (
              -- Check for inserts
               ((src.pidm IS NULL AND tgt.pidm IS NOT NULL) OR (src.pidm IS NOT NULL AND tgt.pidm IS NULL)) OR
              -- Check for updates if any data has changed
               (coalesce(src.luid, 'X') <> coalesce(tgt.luid, 'X')) OR (coalesce(src.username, 'X') <> coalesce(tgt.username, 'X')) OR (coalesce(src.prog_code, 'X') <> coalesce(tgt.prog_code, 'X')) OR
               (coalesce(src.prog_desc, 'X') <> coalesce(tgt.prog_desc, 'X')) OR (coalesce(src.gpa_asof_term, -1) <> coalesce(tgt.gpa_asof_term, -1)) OR (coalesce(src.terms_cnt, -1) <> coalesce(tgt.terms_cnt, -1)) OR
               (coalesce(src.phone, 'X') <> coalesce(tgt.phone, 'X')))) t2
ON (t1.pidm = t2.pidm)
WHEN MATCHED THEN
UPDATE
   SET t1.luid          = t2.luid,
       t1.username      = t2.username,
       t1.prog_code     = t2.prog_code,
       t1.prog_desc     = t2.prog_desc,
       t1.gpa_asof_term = t2.gpa_asof_term,
       t1.terms_cnt     = t2.terms_cnt,
       t1.phone         = t2.phone,
       t1.activity_date = t2.activity_date
WHEN NOT MATCHED THEN
INSERT
VALUES
(SYSDATE,
 t2.pidm,
 t2.luid,
 t2.username,
 t2.prog_code,
 t2.prog_desc,
 t2.gpa_asof_term,
 t2.terms_cnt,
 t2.phone);
v_count := SQL%ROWCOUNT;
COMMIT;
dbms_lock.sleep(1); -- pause
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
END LOOP; -- c_terms
IF to_char(v_etl_date, 'D') IN ('2', '5')
   AND to_char(SYSDATE, 'HH24') >= ('18') THEN
-- only run at specific times outside of high demand
-- remove any students NOT currently enrolled [dropped NOT withdraw]
DELETE FROM zlighthouse_whs.ml_crscompstu a
 WHERE NOT EXISTS (SELECT 'Y'
          FROM utl_d_aim.szrenrl
         WHERE group_code = 'STD'
           AND a.pidm = szrenrl.pidm);
v_count := SQL%ROWCOUNT;
COMMIT;
dbms_lock.sleep(1); -- pause
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'DELETE - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
END IF;
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
-- log any errors
EXCEPTION
WHEN OTHERS THEN
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
/*--------------------------------------------CHANGE LOG----------------------------------------
VERSION  DATE        USERNAME    UPDATES
---     07-18-2019  WGRIFFITH2  --Initial release
---     08-05-2019  WGRIFFITH2  --Moving from UTL_D_AA to zlighthouse_whs
---     10-25-2019  WGRIFFITH2  --Opening up the timeframe bc they need historical data [removing end of course delete]
---     10-29-2019  WGRIFFITH2  --Request to open student information for all students; now pulling source data from utl_d_aim.szrenrl instead of ml_crscompout; swap to szvprle_web_display_degc
---    03-15-2023  WGRIFFITH2  --Switch to use LMS LINK; adding output to insert_job_log
---    02-13-2025  WGRIFFITH2  --Update to merge where only records that are new or need updating
------------------------------------------------------------------------------------------------*/
END etl_aa_ml_crscompstu_refresh; --
PROCEDURE etl_aa_ml_crscompprd_refresh(jobnumber NUMBER, processid VARCHAR2, processname VARCHAR2) IS
/*
Table: ZLIGHTHOUSE_WHS.ML_CRSCOMPPRD

Primary Keys: None

Unique index: PIDM, TERM_CODE, CRN, WEEK_NUMBER

Purpose:
- Sending predictions over to MyStudents

Conditions:
- PREDICTIONS RUN AFTER THE DAY HAS COMPLETED, SO WE HAVE TO USE THE "DAY FORWARD" METHOD TO GET DATA TO SHOW FOR TODAY

*/
--DECLARE
--- PARAMS
v_etl_date DATE := SYSDATE;
v_msg      VARCHAR2(2000);
v_instance VARCHAR2(50) := upper('ALL'); -- inst from the jams job; used for determining instance
v_partition NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
-- v_mod         NUMBER := 5; -- number of partitions to be created
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_aa_ml_crscompprd_refresh';
CURSOR c_terms IS
SELECT cal.week_number AS week_number,
       MIN(cal.week_start_date) AS week_start,
       MAX(trunc(cal.week_end_date + 1) - (1 / (24 * 60 * 60))) AS week_end, -- format as 11:59pm
       cal.term_code,
       cal.ptrm_code,
       MAX(cal.end_date) AS end_date
  FROM utl_d_aa.crscalendar cal
  JOIN zbtm.terms_by_group_v z
    ON z.term_code = cal.term_code
   AND z.semester <> 'WIN'
   AND z.group_code = 'STD'
   AND cal.ptrm_code IN ('R', '1A', '1B', '1C', '1D')
 WHERE SYSDATE >= cal.start_date - 7
   AND SYSDATE < cal.end_date + 1
   AND cal.dte < SYSDATE -- ** INCLUDE TODAY - we have to have it here! **
   AND cal.dte >= SYSDATE - 7 -- get dates from only last week (to get current week)
   AND cal.week_number <= 8 -- only push 8 weeks into MyStudents
 GROUP BY cal.term_code,
          cal.ptrm_code,
          cal.week_number;
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
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || rec.term_code || ' - ' || rec.ptrm_code || ' - ' || rec.week_number || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- Lighthouse will hold current term data only
MERGE INTO zlighthouse_whs.ml_crscompprd tgt
USING (SELECT src.activity_date,
              src.pidm,
              src.term_code,
              src.crn,
              src.bb_crse_id,
              src.week_number,
              src.week_start,
              src.week_end,
              src.score,
              src.score_desc,
              src.ovrl_grade,
              src.ovrl_pts_earned
         FROM (SELECT v_etl_date AS activity_date,
                      msc.pidm,
                      msc.term_code,
                      msc.crn,
                      msc.course_code AS bb_crse_id,
                      rec.week_number AS week_number,
                      rec.week_start AS week_start,
                      rec.week_end AS week_end,
                      CASE
                      WHEN mcs.predicted_result = 1
                           AND mcs.prediction_confidence > .7 THEN
                       4
                      WHEN mcs.predicted_result = 0
                           AND mcs.prediction_confidence > .7 THEN
                       0
                      ELSE
                       2
                      END AS score,
                      CASE
                      WHEN mcs.predicted_result = 1
                           AND mcs.prediction_confidence > .7 THEN
                       'Course Success Probability - High'
                      WHEN mcs.predicted_result = 0
                           AND mcs.prediction_confidence > .7 THEN
                       'Course Success Probability - Low'
                      ELSE
                       'Course Success Probability - Unlikely'
                      END AS score_desc,
                      msc.grade_earned AS ovrl_grade,
                      msc.points_earned AS ovrl_pts_earned
                 FROM (SELECT crse.term_code,
                              crse.crn,
                              crse.pidm,
                              crse.subj || crse.numb || '_' || crse.sect || '_' || crse.term_code AS course_code,
                              -- earned points, possible, grade
                              -- we need to use student_assignments because it needs to be flexible enough to calculate based on the "as of date" instead of just "live"
                              -- this is why you see "least(rec.week_end_date, v_etl_date) + 1" throughout this code
                              -- using the calcs as what exists in student_progress
                              round(SUM(CASE
                                        WHEN coalesce(sa.graded_date, adt.dte, rec.end_date) < least(rec.week_end, v_etl_date) + 1
                                             AND sa.workflow_state IN ('graded', 'unsubmitted') THEN
                                         coalesce(sa.score, 0)
                                        WHEN coalesce(sa.graded_date, adt.dte, rec.end_date) < least(rec.week_end, v_etl_date) + 1
                                             AND sa.workflow_state IN ('pending_review', 'submitted')
                                             AND coalesce(sa.score, 0) > 0 THEN
                                         coalesce(sa.score, 0)
                                        WHEN coalesce(sa.graded_date, adt.dte, rec.end_date) < least(rec.week_end, v_etl_date) + 1
                                             AND sa.workflow_state IN ('deleted')
                                             AND substr(crse.final_grade, 1, 1) IN ('F', 'W')
                                             AND crse.grade_date < least(rec.week_end, v_etl_date) + 1 THEN
                                         coalesce(sa.score, 0)
                                        ELSE
                                         NULL
                                        END), 0) AS points_earned,
                              round(SUM(CASE
                                        WHEN coalesce(sa.graded_date, adt.dte, rec.end_date) < least(rec.week_end, v_etl_date) + 1
                                             AND sa.workflow_state IN ('graded', 'unsubmitted') THEN
                                         coalesce(sa.score, 0)
                                        WHEN coalesce(sa.graded_date, adt.dte, rec.end_date) < least(rec.week_end, v_etl_date) + 1
                                             AND sa.workflow_state IN ('pending_review', 'submitted')
                                             AND coalesce(sa.score, 0) > 0 THEN
                                         coalesce(sa.score, 0)
                                        WHEN coalesce(sa.graded_date, adt.dte, rec.end_date) < least(rec.week_end, v_etl_date) + 1
                                             AND sa.workflow_state IN ('deleted')
                                             AND substr(crse.final_grade, 1, 1) IN ('F', 'W')
                                             AND crse.grade_date < least(rec.week_end, v_etl_date) + 1 THEN
                                         coalesce(sa.score, 0)
                                        ELSE
                                         NULL
                                        END) / SUM(CASE
                                                   WHEN coalesce(sa.graded_date, adt.dte, rec.end_date) < least(rec.week_end, v_etl_date) + 1
                                                        AND sa.workflow_state IN ('graded', 'unsubmitted') THEN
                                                    sa.points_possible
                                                   WHEN coalesce(sa.graded_date, adt.dte, rec.end_date) < least(rec.week_end, v_etl_date) + 1
                                                        AND sa.workflow_state IN ('pending_review', 'submitted')
                                                        AND coalesce(sa.score, 0) > 0 THEN
                                                    sa.points_possible
                                                   WHEN coalesce(sa.graded_date, adt.dte, rec.end_date) < least(rec.week_end, v_etl_date) + 1
                                                        AND sa.workflow_state IN ('deleted')
                                                        AND substr(crse.final_grade, 1, 1) IN ('F', 'W')
                                                        AND crse.grade_date < least(rec.week_end, v_etl_date) + 1 THEN
                                                    sa.points_possible
                                                   ELSE
                                                    NULL
                                                   END), 4) AS grade_earned
                         FROM utl_d_aim.szrcrse crse
                         JOIN utl_d_lms.student_enrollments se
                           ON se.term_code = crse.term_code
                          AND se.crn = crse.crn
                          AND se.pidm = crse.pidm
                          AND se.term_code = rec.term_code
                          AND se.ptrm_code = rec.ptrm_code
                         JOIN zsaturn.szrlevl lvl
                           ON lvl.szrlevl_levl_code = se.levl_code
                          AND lvl.szrlevl_has_awardable_cred = 'Y' -- remove EM
                         JOIN utl_d_lms.student_assignments sa
                           ON sa.instance = se.instance
                          AND sa.course_section_id = se.course_section_id
                          AND sa.user_id = se.user_id
                          AND coalesce(sa.points_possible, 0) > 0 -- points_possible must be greater than 0
                         LEFT JOIN utl_d_lms.assignments_dates adt
                           ON adt.instance = sa.instance
                          AND adt.course_section_id = sa.course_section_id
                          AND adt.assignment_id = sa.assignment_id
                          AND adt.date_field = 'effective_grade_date' -- to know when grades should be due and graded
                        GROUP BY crse.term_code,
                                 crse.crn,
                                 crse.subj || crse.numb || '_' || crse.sect || '_' || crse.term_code,
                                 crse.pidm) msc
               -- left join just in case we do not have predictions
                 LEFT JOIN (SELECT mcs.term_code,
                                  mcs.crn,
                                  mcs.pidm,
                                  mcs.predicted_result,
                                  mcs.prediction_confidence,
                                  rank() over(PARTITION BY mcs.term_code, mcs.crn, mcs.pidm ORDER BY mcs.week_number DESC, mcs.day_number DESC) ranking -- pull the last prediction we observed, so no need to do the "minus 1 thingy" here to get yesterdays prediction to show today
                             FROM utl_d_aa.ml_course_success mcs
                            WHERE mcs.term_code = rec.term_code
                              AND mcs.ptrm_code = rec.ptrm_code
                              AND mcs.dte < least(rec.week_end, v_etl_date) + 1
                              AND mcs.predicted_result IS NOT NULL) mcs
                   ON msc.term_code = mcs.term_code -- no join on week_number
                  AND msc.crn = mcs.crn
                  AND msc.pidm = mcs.pidm
                WHERE mcs.ranking = 1 -- get the latest prediction
               ) src
         LEFT JOIN zlighthouse_whs.ml_crscompprd tgt
           ON tgt.pidm = src.pidm
          AND tgt.term_code = src.term_code
          AND tgt.crn = src.crn
          AND tgt.week_number = src.week_number
        WHERE 1 = 1
          AND (((src.pidm IS NULL AND tgt.pidm IS NOT NULL) OR (src.pidm IS NOT NULL AND tgt.pidm IS NULL)) OR --
              (coalesce(src.bb_crse_id, 'X') <> coalesce(tgt.bb_crse_id, 'X')) OR --
              (coalesce(src.week_start, SYSDATE) <> coalesce(tgt.week_start, SYSDATE)) OR --
              (coalesce(src.week_end, SYSDATE) <> coalesce(tgt.week_end, SYSDATE)) OR --
              (coalesce(src.score, -1) <> coalesce(tgt.score, -1)) OR --
              (coalesce(src.score_desc, 'X') <> coalesce(tgt.score_desc, 'X')) OR --
              (coalesce(src.ovrl_grade, -1) <> coalesce(tgt.ovrl_grade, -1)) OR --
              (coalesce(src.ovrl_pts_earned, -1) <> coalesce(tgt.ovrl_pts_earned, -1)))) src
ON (tgt.pidm = src.pidm AND tgt.term_code = src.term_code AND tgt.crn = src.crn AND tgt.week_number = src.week_number)
WHEN MATCHED THEN
UPDATE
   SET tgt.activity_date   = v_etl_date,
       tgt.bb_crse_id      = src.bb_crse_id,
       tgt.week_start      = src.week_start,
       tgt.week_end        = src.week_end,
       tgt.score           = src.score,
       tgt.score_desc      = src.score_desc,
       tgt.ovrl_grade      = src.ovrl_grade,
       tgt.ovrl_pts_earned = src.ovrl_pts_earned
WHEN NOT MATCHED THEN
INSERT
VALUES
(v_etl_date,
 src.pidm,
 src.term_code,
 src.crn,
 src.bb_crse_id,
 src.week_number,
 src.week_start,
 src.week_end,
 src.score,
 src.score_desc,
 src.ovrl_grade,
 src.ovrl_pts_earned);
v_count := SQL%ROWCOUNT;
COMMIT;
dbms_lock.sleep(1); -- pause
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || rec.term_code || ' - ' || rec.ptrm_code || ' - ' || rec.week_number || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
END LOOP; -- c_terms 
IF to_char(v_etl_date, 'D') IN ('2', '5')
   AND to_char(SYSDATE, 'HH24') >= ('18') THEN
-- only run at specific times outside of high demand
-- remove any students NOT currently enrolled [dropped NOT withdrawn]
DELETE FROM zlighthouse_whs.ml_crscompprd tgt
 WHERE NOT EXISTS (SELECT term_code
          FROM zlighthouse_whs.ml_crscompcrs src
         WHERE src.term_code = tgt.term_code
           AND src.crn = tgt.crn
           AND src.pidm = tgt.pidm);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'DELETE - ALL - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- remove anything older than 365 days
DELETE FROM zlighthouse_whs.ml_crscompprd tgt WHERE tgt.week_end < SYSDATE - 365;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'DELETE - ALL - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
END IF;
dbms_lock.sleep(1); -- pause
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
-- log any errors
EXCEPTION
WHEN OTHERS THEN
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
/*--------------------------------------------CHANGE LOG----------------------------------------
VERSION  DATE        USERNAME    UPDATES
---     07-18-2019  WGRIFFITH2  --Initial release
---     08-05-2019  WGRIFFITH2  --Moving from UTL_D_AA to zlighthouse_whs
---     08-27-2019  WGRIFFITH2  --Fixing week_start and week_end for 'week forward' logic
---     09-13-2019  WGRIFFITH2  --Deprecating utl_d_aa.rslbmsngasgn; now using utl_d_aa.rswbmsgasgn
---     12-31-2019  WGRIFFITH2  --Prep for removing missed_assignments_text and ml_plain_text from zlighthouse_whs.ml_crscompprd, so creating table on utl_d_aa to handle transition period - leaving those fields accessible for the tableau dashboard
---     01-02-2020  WGRIFFITH2  --Update the predicted score field to account for the new model outputs
---     01-09-2020  WGRIFFITH2  --Removing missed_assignments_text and ml_plain_text from zlighthouse_whs.ml_crscompprd
---     01-23-2020  WGRIFFITH2  --Adjusting the score case statement to look for students that need to be manually moved to the 2-opportunity bucket
---     01-27-2020  WGRIFFITH2  --Adding delete to remove any courses that got switched to exclusions after the course start date
---     01-29-2020  WGRIFFITH2  --zlighthouse_whs.ml_crscompprd merge updates anything in current part of term instead of current week
---     03-25-2020  WGRIFFITH2  --Removing the utl_d_aa ml_crscompprd bc it is no longer necessary; update fields in lighthouse from the new model
---     08-07-2020  WGRIFFITH2  --adding utl_d_lms.student_assignments_rollsum for canvas grade data
---     03-17-2021  WGRIFFITH2  --migrating to new ML_OUTPUT table
---     03-01-2022  WGRIFFITH2  --migrating to new ML_SUBMISSION_RATES table
---     03-14-2022  WGRIFFITH2  --now using "day forward" method to show yesterdays predictions for today; todays data needed for MyStudents
---     04-09-2022  WGRIFFITH2  --migrating to new ML_COURSE_SUCCESS table after the submissions rates model was producing too many "red" predictions
---     03-15-2023  WGRIFFITH2  --Switch to use LMS LINK; adding output to insert_job_log
---     09-17-2024  WGRIFFITH2  --to keep size small on zlighthouse_whs.ml_crscompprd, adding delete to anything older than 365 days. keeping historical data on utl_d_aa.ml_crscompprd
---     06-07-2025  WGRIFFITH2  --Update to merge where only records that are new or need updating
---     06-10-2025  WGRIFFITH2  --(ROLLBACK ON 06-14-2025 to use predictions weeks 0-8) ML model implemented works weeks 0-4, then switches to Canvas grades afterwards; removing the old staging table from the AA schema and using the new one
------------------------------------------------------------------------------------------------*/
END etl_aa_ml_crscompprd_refresh; --

PROCEDURE etl_aa_ml_crscomptag_refresh(jobnumber NUMBER, processid VARCHAR2, processname VARCHAR2) IS
/*
Table: zlighthouse_whs.ml_crscomptag

Primary Keys: None

Unique index: PIDM, TERM_CODE, CRN, WEEK_NUMBER

Purpose:
- Sending predictions tags over to MyStudents

Conditions:
- PREDICTIONS RUN AFTER THE DAY HAS COMPLETED, SO WE HAVE TO USE THE "DAY FORWARD" METHOD TO GET DATA TO SHOW FOR TODAY

*/
--DECLARE
--- PARAMS
v_etl_date DATE := SYSDATE;
v_msg      VARCHAR2(2000);
v_instance VARCHAR2(50) := upper('ALL'); -- inst from the jams job; used for determining instance
v_partition NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
-- v_mod         NUMBER := 5; -- number of partitions to be created

v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_aa_ml_crscomptag_refresh';
CURSOR c_terms IS
SELECT DISTINCT term_code
  FROM utl_d_aim.szrcrse
 WHERE group_code = 'STD'
   AND ptrm_code IN ('R', '1A', '1B', '1C', '1D')
   AND trunc(SYSDATE) BETWEEN ptrm_start - 7 AND ptrm_end + 7
 ORDER BY 1;
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
v_count := 0; -- reset count
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- Nothing gets deleted from the AA schema tag table; it is our log table
-- Lighthouse will hold our "current" tags
MERGE INTO utl_d_aa.ml_crscomptag tgt
USING (
WITH prd AS
 (SELECT /*+ materialize*/
   src.pidm,
   src.term_code,
   src.crn,
   src.bb_crse_id,
   src.week_number,
   src.tag_start_date,
   src.tag_end_date
    FROM (SELECT prd.pidm,
                 prd.term_code,
                 prd.crn,
                 prd.bb_crse_id,
                 prd.week_number,
                 prd.score,
                 trunc(prd.week_start) AS tag_start_date,
                 trunc(prd.week_end + 1) - 1 / (24 * 60 * 60) AS tag_end_date, -- converting to 11:59 pm
                 rank() over(PARTITION BY prd.term_code, prd.crn, prd.pidm ORDER BY prd.week_number DESC, rownum) ranking
            FROM zlighthouse_whs.ml_crscompprd prd
           WHERE 1 = 1
             AND prd.term_code = rec.term_code
             AND trunc(prd.activity_date) = trunc(SYSDATE) -- only need to merge data that was updated within last hour
          ) src
   WHERE ranking = 1
     AND src.score < 4 -- ONLY SHOW IF YELLOW OR RED
  )
-- Missing Assignments
SELECT v_etl_date      AS activity_date,
       prd.pidm,
       prd.term_code,
       prd.crn,
       prd.bb_crse_id,
       prd.week_number,
       tag_start_date,
       tag_end_date,
       1               AS tag_id
  FROM prd
 WHERE EXISTS (SELECT 1
          FROM zlighthouse_whs.msgasgn msg
         WHERE msg.term_code = prd.term_code
           AND msg.crn = prd.crn
           AND msg.pidm = prd.pidm)
UNION ALL
-- Withdraw Rate
SELECT v_etl_date      AS activity_date,
       prd.pidm,
       prd.term_code,
       prd.crn,
       prd.bb_crse_id,
       prd.week_number,
       tag_start_date,
       tag_end_date,
       5               AS tag_id
  FROM prd
  JOIN utl_d_aim.szrcrse crse
    ON prd.term_code = crse.term_code
   AND prd.crn = crse.crn
   AND prd.pidm = crse.pidm
-- academic performance
  LEFT JOIN utl_d_aa.stuacadperform acadperform
    ON acadperform.pidm = crse.pidm
   AND acadperform.term_code = crse.term_code
-- college performance
  LEFT JOIN utl_d_aa.stucollperform collperform
    ON collperform.pidm = crse.pidm
   AND collperform.coll_code = crse.coll_code
   AND collperform.term_code = crse.term_code
 WHERE 1 = 1
   AND ((acadperform.w_pct > acadperform.w_pct_peer) OR (collperform.w_pct > collperform.w_pct_peer) OR (acadperform.fn_pct > acadperform.fn_pct_peer) OR (collperform.fn_pct > collperform.fn_pct_peer))
UNION ALL
-- Low GPA
SELECT v_etl_date      AS activity_date,
       prd.pidm,
       prd.term_code,
       prd.crn,
       prd.bb_crse_id,
       prd.week_number,
       tag_start_date,
       tag_end_date,
       6               AS tag_id
  FROM prd
-- szrenrl - term to term enrollment joins
  JOIN utl_d_aim.szrenrl
    ON szrenrl.term_code = prd.term_code
   AND szrenrl.pidm = prd.pidm
 WHERE 1 = 1
   AND (szrenrl.gpa_asof_term < 2.0 OR szrenrl.cum_gpa < 2.0)
UNION ALL
-- Course Retake
SELECT v_etl_date      AS activity_date,
       prd.pidm,
       prd.term_code,
       prd.crn,
       prd.bb_crse_id,
       prd.week_number,
       tag_start_date,
       tag_end_date,
       7               AS tag_id
  FROM prd
  JOIN utl_d_aim.szrcrse crse
    ON prd.term_code = crse.term_code
   AND prd.crn = crse.crn
   AND prd.pidm = crse.pidm
  JOIN zsaturn.szrlevl l
    ON l.szrlevl_levl_code = crse.levl_code
   AND l.szrlevl_has_awardable_cred = 'Y'
-- RETAKES
  LEFT JOIN (SELECT rt.pidm,
                    rt.course,
                    COUNT(*) AS seat_cnt
               FROM utl_d_aim.szrcrse rt
              WHERE rt.term_code <= rec.term_code
              GROUP BY rt.pidm,
                       rt.course) rt
    ON rt.pidm = crse.pidm
   AND rt.course = crse.course
 WHERE 1 = 1
   AND coalesce(rt.seat_cnt, 0) > 1 -- number of times student has taken the course
 ) src ON (tgt.pidm = src.pidm AND tgt.crn = src.crn AND tgt.term_code = src.term_code AND tgt.week_number = src.week_number AND tgt.tag_id = src.tag_id) WHEN MATCHED THEN
UPDATE
   SET tgt.bb_crse_id    = src.bb_crse_id,
       tgt.tag_end_date  = src.tag_end_date,
       tgt.activity_date = src.activity_date
WHEN NOT MATCHED THEN
INSERT
VALUES
(v_etl_date,
 src.pidm,
 src.term_code,
 src.crn,
 src.bb_crse_id,
 src.week_number,
 src.tag_start_date,
 src.tag_end_date,
 src.tag_id);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
-- Only live tags go to zlighthouse_whs.ml_crscomptag
DELETE FROM zlighthouse_whs.ml_crscomptag;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'DELETE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
-- insert into zlighthouse_whs schema tag table
INSERT INTO zlighthouse_whs.ml_crscomptag
(activity_date,
 pidm,
 term_code,
 crn,
 bb_crse_id,
 tag_id,
 tag_desc,
 tag_ext_desc)
SELECT tag.activity_date,
       tag.pidm,
       tag.term_code,
       tag.crn,
       tag.bb_crse_id,
       tag.tag_id,
       v.tag_desc,
       v.tag_ext_desc
  FROM utl_d_aa.ml_crscomptag tag
  JOIN utl_d_aa.ml_crscomptagv v
    ON v.tag_id = tag.tag_id
 WHERE 1 = 1
   AND tag.term_code = rec.term_code
   AND tag.activity_date >= v_etl_date - (1 / 24); -- insert all records that were updated in the current job run
v_count := SQL%ROWCOUNT;
COMMIT;
dbms_lock.sleep(1); -- pause
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
END LOOP;
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
-- log any errors
EXCEPTION
WHEN OTHERS THEN
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
/*--------------------------------------------CHANGE LOG----------------------------------------
VERSION  DATE        USERNAME    UPDATES
---     10-29-2019  WGRIFFITH2  --Initial release
---     11-04-2019  WGRIFFITH2  --Swap code to pull from utl_d_aa.ml_crscompin instead of utl_d_aa.ml_crscompout
---     11-06-2019  WGRIFFITH2  --Added tag_ext_desc
---     03-25-2020  WGRIFFITH2  --using utl_d_aa.ml_crscompout now and update fields in lighthouse from the new model
---     08-24-2020  WGRIFFITH2  --removing INTERVAL
---     03-17-2021  WGRIFFITH2  --migrating to new ML_OUTPUT table
---     03-01-2022  WGRIFFITH2  --migrating to new ML_SUBMISSION_RATES table
---     03-14-2022  WGRIFFITH2  --now using "day forward" method to show yesterdays predictions for today; todays data needed for MyStudents
---     04-09-2022  WGRIFFITH2  --migrating to new ML_COURSE_SUCCESS table after the submissions rates model was producing too many "red" predictions
---     03-15-2023  WGRIFFITH2  --Switch to use LMS LINK; adding output to insert_job_log
---     09-18-2024  WGRIFFITH2  --performance updates
---     06-17-2025  WGRIFFITH2  --accomodations for new ML model code
---     07-09-2025  WGRIFFITH2  --Update to code related to changes to the etl_aa_stucrseperform_refresh procedure
------------------------------------------------------------------------------------------------*/
END etl_aa_ml_crscomptag_refresh;

PROCEDURE etl_aa_ml_msgasgn_refresh(jobnumber NUMBER, processid VARCHAR2, processname VARCHAR2) IS
/*
Table: zlighthouse_whs.msgasgn

Primary Keys: None

Unique index: PIDM, TERM_CODE, CRN

Purpose:
- Show missing assignments for MyStudents

Conditions:
-

*/
--DECLARE
--- PARAMS
v_etl_date DATE := SYSDATE;
v_msg      VARCHAR2(2000);
v_instance VARCHAR2(50) := upper('ALL'); -- inst from the jams job; used for determining instance
v_partition NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
-- v_mod         NUMBER := 5; -- number of partitions to be created

v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_aa_ml_msgasgn_refresh';
CURSOR c_terms IS
SELECT DISTINCT term_code
  FROM utl_d_aim.szrcrse
 WHERE group_code = 'STD'
   AND ptrm_code IN ('R', '1A', '1B', '1C', '1D', '1J')
   AND trunc(SYSDATE) BETWEEN ptrm_start - 7 AND ptrm_end + 1
 ORDER BY 1;
BEGIN
-- dbms_output.enable(buffer_size => NULL);
--
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
-- delete any students once they have a final grade
DELETE FROM zlighthouse_whs.msgasgn ma
 WHERE EXISTS (SELECT *
          FROM utl_d_aim.szrcrse crse
         WHERE crse.term_code = ma.term_code
           AND crse.pidm = ma.pidm
           AND crse.crn = ma.crn
           AND crse.final_grade IS NOT NULL);
COMMIT;
FOR rec IN c_terms
LOOP
v_count   := 0; -- reset count
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- refresh zlighthouse_whs table
DELETE FROM zlighthouse_whs.msgasgn ma WHERE ma.term_code = rec.term_code;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'DELETE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
INSERT INTO zlighthouse_whs.msgasgn
(pidm,
 cm_pk1,
 gm_pk1,
 assignment,
 points_possible,
 term_code,
 ptrm_code,
 crn,
 bb_crse_id,
 bb_batchuid,
 is_live_feed,
 is_assessment,
 is_crc,
 is_forum,
 due_date,
 activity_date)
SELECT crse.pidm,
       se.course_section_id AS cm_pk1,
       sa.assignment_id AS gm_pk1,
       substr(sa.title, 1, 100) AS assignment,
       sa.points_possible AS points_possible,
       rec.term_code AS term_code,
       crse.ptrm_code AS ptrm_code,
       crse.crn AS crn,
       se.course_code AS bb_crse_id,
       se.section_sis_id AS bb_batchuid,
       CASE
       -- ONLINE COURSE TAUGHT TO RESIDENT STUDENTS ONLY
       WHEN se.camp_code = 'R'
            AND se.insm_code = 'ON' THEN
        'Y'
       -- exclusion courses are NOT live feeds
       WHEN xl.crn IS NOT NULL THEN
        'N'
       -- REMOVE RESIDENT TAUGHT COURSES
       WHEN se.camp_code = 'R' THEN
        'N'
       -- REMOVE TRADITIONAL TAUGHT COURSES
       WHEN se.insm_code = 'TR' THEN
        'N'
       -- REMOVE LABS, THESIS, PRACTICUM, DISSERTATION
       WHEN se.insm_code IN ('IP', 'IS', 'TH')  THEN
        'N'
       ELSE
        'Y'
       END AS is_live_feed,
       CASE
       WHEN regexp_like(lower(sa.title), 'assessment') THEN
        'Y'
       ELSE
        'N'
       END is_assessment,
       CASE
       WHEN regexp_like(lower(sa.title), 'course requirements checklist') THEN
        'Y'
       ELSE
        'N'
       END is_crc,
       CASE
       WHEN coalesce(sa.submission_types, 'none') = 'discussion_topic' THEN
        'Y'
       ELSE
        'N'
       END is_forum,
       CAST(sa.due_date AS DATE) due_date,
       v_etl_date AS activity_date
  FROM utl_d_aim.szrcrse crse
  JOIN utl_d_lms.student_enrollments se
    ON se.term_code = crse.term_code
   AND se.crn = crse.crn
   AND se.pidm = crse.pidm
   AND crse.term_code = rec.term_code
   AND se.instance = 'L2CAN'
   AND crse.final_grade IS NULL -- remove any audit, withdraw, FN and stop returning data once the final grade is submitted
   AND se.subj_code NOT IN ('CSER', 'CAFE', 'SFME', 'FRSM', 'NEWS', 'NSSR')
  JOIN zsaturn.szrlevl lvl
    ON lvl.szrlevl_levl_code = se.levl_code
   AND lvl.szrlevl_has_awardable_cred = 'Y' -- remove EM
  JOIN utl_d_lms.student_assignments sa
    ON sa.course_section_id = se.course_section_id
   AND sa.user_id = se.user_id
   AND sa.instance = se.instance
-- EXCLUSIONS
  LEFT JOIN (SELECT ce.crn,
                    ce.term_code,
                    ce.instructional_method
               FROM utl_d_lms.course_exclusions ce
              WHERE ce.term_code = rec.term_code
                AND ce.grading_compliance = 'Exclude') xl
    ON xl.term_code = crse.term_code
   AND xl.crn = crse.crn
-- this pulls students who have not submitted
 WHERE sa.submitted_date IS NULL -- no submit
   AND sa.graded_date IS NULL -- no grade
   AND sa.due_date IS NOT NULL
   AND coalesce(sa.points_possible, 0) > 0 -- must be worth points
   AND CAST(sa.due_date AS DATE) < v_etl_date + (8 / 24) -- adding lag time
   AND CASE
       -- ONLINE COURSE TAUGHT TO RESIDENT STUDENTS ONLY
       WHEN se.camp_code = 'R'
            AND se.insm_code = 'ON' THEN
        'Y'
       -- exclusion courses are NOT live feeds
       WHEN xl.crn IS NOT NULL THEN
        'N'
       -- REMOVE RESIDENT TAUGHT COURSES
       WHEN se.camp_code = 'R' THEN
        'N'
       -- REMOVE TRADITIONAL TAUGHT COURSES
       WHEN se.insm_code = 'TR' THEN
        'N'
       -- REMOVE LABS, THESIS, PRACTICUM, DISSERTATION
       WHEN se.insm_code IN ('IP', 'IS', 'TH') THEN
        'N'
       ELSE
        'Y'
       END = 'Y';
v_count := SQL%ROWCOUNT;
COMMIT;
dbms_lock.sleep(1); -- pause
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
END LOOP; -- c_terms
dbms_lock.sleep(1); -- pause
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
/*--------------------------------------------CHANGE LOG----------------------------------------
VERSION  DATE        USERNAME    UPDATES
---     07-18-2019  WGRIFFITH2  --Initial release
---     03-15-2023  WGRIFFITH2  --Switch to use LMS LINK; adding output to insert_job_log
---     04-26-2023  WGRIFFITH2  --now using ce.grading_compliance to filter out missing assignments from showing on MyStudents
---     03-10-2025  WGRIFFITH2  --Removing all LMS_LINK table dependencies; replaced with STUDENT_ENROLLMENTS table
------------------------------------------------------------------------------------------------*/
END etl_aa_ml_msgasgn_refresh;
END load_aa_etl_ml;
