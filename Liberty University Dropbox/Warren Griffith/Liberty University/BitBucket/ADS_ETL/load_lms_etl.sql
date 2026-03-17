create or replace package load_lms_etl IS
--courses
procedure etl_lms_link (jobnumber number, processid varchar2, processname varchar2, inst varchar2, nmbr number); ---      09-09-2020  WGRIFFITH2  --Initial release
procedure etl_lms_course_surveys(jobnumber number, processid varchar2, processname varchar2, inst varchar2, nmbr number); -- EOCs only
procedure etl_lms_course_surveys_tableau(jobnumber number, processid varchar2, processname varchar2, inst varchar2, nmbr number); -- EOCs only
-- enrollments
procedure etl_lms_student_enrollments (jobnumber number, processid varchar2, processname varchar2, inst varchar2, nmbr number); -- 20230314 - WGRIFFITH2 - Initial release
procedure etl_lms_student_users (jobnumber number, processid varchar2, processname varchar2, inst varchar2, nmbr number); ---      09-09-2020  WGRIFFITH2  --Initial release
procedure etl_lms_faculty_users (jobnumber number, processid varchar2, processname varchar2, inst varchar2, nmbr number); ---      09-09-2020  WGRIFFITH2  --Initial release
-- assignments
procedure etl_lms_student_assignments (jobnumber number, processid varchar2, processname varchar2, inst varchar2, nmbr number); ---      09-09-2020  WGRIFFITH2  --Initial release
procedure etl_lms_assignments_dates (jobnumber number, processid varchar2, processname varchar2, inst varchar2, nmbr number); ---      09-09-2020  WGRIFFITH2  --Initial release
procedure etl_lms_assignments_stats (jobnumber number, processid varchar2, processname varchar2, inst varchar2, nmbr number); ---      09-09-2020  WGRIFFITH2  --Initial release
procedure etl_lms_zduebot (jobnumber number, processid varchar2, processname varchar2, inst varchar2, nmbr number); ---      11-22-2024  WGRIFFITH2  -- Initial release
-- progress
procedure etl_lms_last_activity (jobnumber number, processid varchar2, processname varchar2, inst varchar2, nmbr number); -- 20210601 - WGRIFFITH2 - Initial release 
procedure etl_lms_student_progress (jobnumber number, processid varchar2, processname varchar2, inst varchar2, nmbr number); -- 20210601 - WGRIFFITH2 - Initial release 
-- announcements and discussions
procedure etl_lms_announcements (jobnumber number, processid varchar2, processname varchar2, inst varchar2, nmbr number); ---      09-08-2021  WGRIFFITH2  --Initial release
procedure etl_lms_discussions (jobnumber number, processid varchar2, processname varchar2, inst varchar2, nmbr number); ---      09-08-2021  WGRIFFITH2  --Initial release
-- quizzes (only select courses)
procedure etl_lms_quizzes (jobnumber number, processid varchar2, processname varchar2, inst varchar2, nmbr number);
procedure etl_lms_student_quiz_answers (jobnumber number, processid varchar2, processname varchar2, inst varchar2, nmbr number);
procedure etl_lms_quiz_questions_answers (jobnumber number, processid varchar2, processname varchar2, inst varchar2, nmbr number);
procedure etl_lms_student_quizzes (jobnumber number, processid varchar2, processname varchar2, inst varchar2, nmbr number);
-- rubrics (not active)
procedure etl_lms_rubric_structure (jobnumber number, processid varchar2, processname varchar2, inst varchar2, nmbr number);
procedure etl_lms_rubric_ratings (jobnumber number, processid varchar2, processname varchar2, inst varchar2, nmbr number);
procedure etl_lms_rubric_scores (jobnumber number, processid varchar2, processname varchar2, inst varchar2, nmbr number);
end load_lms_etl;
/

create or replace package body load_lms_etl IS

procedure etl_lms_zduebot (jobnumber NUMBER, processid VARCHAR2, processname VARCHAR2, inst varchar2, nmbr number) IS
--
-- PURPOSE: Stages two-week discussion board reply due dates for active Canvas courses to support timely grading and instructional reminders.
--
-- TABLE: utl_d_lms.zduebot
--
-- UNIQUE INDEX: INSTANCE, COURSE_SECTION_ID, ASSIGNMENT_ID
--
-- CONDITIONS:
-- Processes data one academic term at a time based on zbtm.terms_by_group_v for term groups STD, MED, and ACD.
-- For the L2CAN instance (STD and MED), runs “current” terms when today is within 7 days before the start date through 7 days after the end date.
-- For the ACCAN instance (ACD), runs “current” terms when today is within 7 days before the start date through 8 days after the end date.
-- For “non-current” terms, runs only during evening low‑demand hours (18:00–23:00); for L2CAN (STD/MED) within 180 days before/after the term window; for ACCAN (ACD) within 180 days before to 365 days after.
-- Additionally, for L2CAN during evening hours, processes non‑Banner courses using a synthetic term code ‘000000’ spanning ±365 days around today.
-- Restricts processing to the selected LMS instance and term (ll.instance = v_instance and ll.term_code = rec.term_code).
-- Matches Canvas assignments to LMS courses via Canvas context_id = course_id.
-- Includes only assignments that count toward the final grade (omit_from_final_grade is NULL).
-- Includes only published assignments; excludes deleted or unpublished items (workflow_state NOT IN ('deleted', 'unpublished')).
-- Excludes assignments whose migration_id prefix indicates deletion (substr(coalesce(migration_id,'X'),1,10) <> 'deletedsub').
-- Includes only discussion assignments (submission_types = 'discussion_topic').
-- Identifies two week discussion boards by due date day and course level: Graduate/Doctoral (GR, DR) due on Sunday; Undergraduate (UG) due on Monday.
-- Computes the reply due date as 7 days after the assignment due date; if this exceeds the course end date, caps the reply due date at the course end date; if no assignment due date exists, uses the course end date.
-- Captures the source assignment’s last updated timestamp and term; stamps activity_date with the ETL run time.
-- Inserts new rows, deletes obsolete rows, and updates existing rows only when title, reply due date, or source updated timestamp has changed.
-- Ensures uniqueness and change detection per LMS instance, course section, and assignment.
--
-- URL: N/A
--
--DECLARE
v_etl_date DATE := SYSDATE;
v_msg      VARCHAR2(2000);
v_instance VARCHAR2(50) := upper(inst); -- inst from the jams job; used for determining instance
v_partition NUMBER := nmbr; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
--v_row_max     NUMBER := 100000; -- max number of rows to be processed at one time
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_count       NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_lms_zduebot';
CURSOR c_terms IS
-- Run current terms
SELECT terms.term_code,
       terms.start_date,
       terms.end_date,
       terms.group_code
  FROM zbtm.terms_by_group_v terms
 WHERE 1 = 1
   AND terms.group_code IN ('STD', 'MED', 'ACD')
   -- controls what terms run for which instances (only)
   AND ((terms.group_code = 'STD' AND SYSDATE BETWEEN terms.start_date - 7 AND terms.end_date + 7 AND v_instance = 'L2CAN') OR
       (terms.group_code = 'MED' AND SYSDATE BETWEEN terms.start_date - 7 AND terms.end_date + 7 AND v_instance = 'L2CAN') OR
       (terms.group_code = 'ACD' AND SYSDATE BETWEEN terms.start_date - 7 AND terms.end_date + 8 AND v_instance = 'ACCAN'))
UNION
-- Run non-current terms - **ONLY RUN DURING NON-BUSINESS HOURS** 
SELECT terms.term_code,
       terms.start_date,
       terms.end_date,
       terms.group_code
  FROM zbtm.terms_by_group_v terms
 WHERE 1 = 1
   AND terms.group_code IN ('STD', 'MED', 'ACD')
   AND ((terms.group_code = 'STD' AND SYSDATE BETWEEN terms.start_date - 180 AND terms.end_date + 180 AND v_instance = 'L2CAN') OR
       (terms.group_code = 'MED' AND SYSDATE BETWEEN terms.start_date - 180 AND terms.end_date + 180 AND v_instance = 'L2CAN') OR
       (terms.group_code = 'ACD' AND SYSDATE BETWEEN terms.start_date - 180 AND terms.end_date + 365 AND v_instance = 'ACCAN'))
   AND (to_char(SYSDATE, 'HH24') BETWEEN '18' AND '23') -- *outside of high demand*
UNION ALL
-- Run non-banner terms - **ONLY RUN DURING NON-BUSINESS HOURS** 
SELECT '000000' AS term_code,
       trunc(SYSDATE - 365) AS start_date,
       trunc(SYSDATE + 365) AS end_date,
       '000' AS group_code
  FROM dual
 WHERE 1 = 1
   AND v_instance = 'L2CAN' -- only non term instance  
   AND (to_char(SYSDATE, 'HH24') BETWEEN '18' AND '23') -- *outside of high demand*
 ORDER BY group_code DESC,
          start_date DESC;
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
v_msg     := 'START - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
MERGE INTO utl_d_lms.zduebot destination_table
USING (SELECT src.course_section_id,
              src.assignment_id,
              src.title,
              src.due_date,
              src.updated_date,
              src.instance,
              src.term_code
         FROM (SELECT ll.course_section_id,
                      a.id AS assignment_id,
                      a.title,
                      CASE
                      -- due date + 7 cannot exceed the end date of the course
                      -- instructors must have final grades done before end_date + 7
                      WHEN a.due_at + 7 > ll.end_date THEN
                       ll.end_date -- assignment due date should not exceed the end date of the course
                      WHEN a.due_at IS NOT NULL THEN
                       a.due_at + 7 -- add 7 days to the due date (this is when replies are due)
                      WHEN a.due_at IS NULL THEN
                       ll.end_date -- no due dates found, force end date as due date
                      END AS due_date,
                      a.updated_at AS updated_date,
                      ll.instance,
                      ll.term_code
                 FROM utl_d_lms.lms_link ll
                 JOIN zcanvas_data.assignments a
                   ON a.instance = ll.instance
                  AND a.context_id = ll.course_id
                  AND a.omit_from_final_grade IS NULL
                  AND a.workflow_state NOT IN ('deleted', 'unpublished')
                  AND substr(coalesce(a.migration_id, 'X'), 1, 10) NOT IN ('deletedsub')
                  AND nvl(a.submission_types, 'X') = 'discussion_topic'
               -- filter to only get two week DBs
               -- this is how to identify two week DBs based on dates and course level
                WHERE ((to_char(a.due_at, 'D') = 1 -- SUN
                      AND ll.levl_code IN ('GR', 'DR')) -- grad or doc course
                      OR (to_char(a.due_at, 'D') = 2 -- MON
                      AND ll.levl_code IN ('UG'))) -- grad or doc course
                  AND ll.instance = v_instance
                  AND ll.term_code = rec.term_code) src
         LEFT JOIN utl_d_lms.zduebot tgt
           ON tgt.instance = src.instance
          AND tgt.course_section_id = src.course_section_id
          AND tgt.assignment_id = src.assignment_id
        WHERE 1 = 1
             -- for inserts or deletes...
          AND (((src.course_section_id IS NULL AND tgt.course_section_id IS NOT NULL) OR (src.course_section_id IS NOT NULL AND tgt.course_section_id IS NULL)) OR --
              -- for updates only if the source data is more recent
              (coalesce(src.title, 'xxxxx') <> coalesce(tgt.title, 'xxxxx')) OR -- title has changed
              (coalesce(src.due_date, systimestamp) <> coalesce(tgt.due_date, systimestamp)) OR -- only update if source is in the future from what we have already; there is no going back :)
              (coalesce(src.updated_date, systimestamp) <> coalesce(tgt.updated_date, systimestamp)))) new_records
ON (destination_table.instance = new_records.instance AND destination_table.course_section_id = new_records.course_section_id AND destination_table.assignment_id = new_records.assignment_id)
WHEN MATCHED THEN
UPDATE
   SET destination_table.title         = new_records.title,
       destination_table.updated_date  = new_records.updated_date,
       destination_table.due_date      = new_records.due_date,
       destination_table.term_code     = new_records.term_code,
       destination_table.activity_date = v_etl_date
WHEN NOT MATCHED THEN
INSERT
(course_section_id,
 assignment_id,
 title,
 due_date,
 updated_date,
 instance,
 activity_date,
 term_code)
VALUES
(new_records.course_section_id,
 new_records.assignment_id,
 new_records.title,
 new_records.due_date,
 new_records.updated_date,
 new_records.instance,
 v_etl_date,
 new_records.term_code);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
end loop; -- c_terms
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
END etl_lms_zduebot;



procedure etl_lms_course_surveys_tableau(jobnumber number, processid varchar2, processname varchar2, inst varchar2, nmbr number) IS
--
-- PURPOSE: Aggregates quantitative and qualitative end-of-course survey data into a Tableau-ready reporting table for faculty performance and academic quality dashboards.
--
-- TABLE: utl_d_lms.course_surveys_tableau
--
-- UNIQUE INDEX: INSTANCE, COURSE_SECTION_ID, SURVEY_ID, QUESTION_ID, RESPONSE_UNIQUE_ID, OPTION_ID
--
-- CONDITIONS:
-- Runs for academic terms in groups STD, MED, and ACD based on current or historical windows, with different time ranges for active and past terms.
-- Executes only during off-peak hours (00:00–08:00 for current terms; 18:00–23:00 for historical/non-banner terms).
-- Includes non-banner terms for instance L2CAN during off-peak hours.
-- Deletes records older than one year from the dashboard once per month to maintain retention policy.
-- Processes only surveys where survey_title contains "End of Course Survey" and excludes survey_id 1601905.
-- Includes quantitative responses (question_type = 3) for Likert-scale scoring and qualitative responses (question_type = 1) for text comments.
-- Filters out qualitative responses that are empty or contain non-informative text such as "none", "n/a", "no comment", or similar phrases.
-- Joins course_surveys with LMS link data to ensure valid course-section mapping and instance alignment.
-- Derives campus type (Online vs Resident) based on camp_code, insm_code, and subject code rules; excludes subjects like CSER, CAFE, SFME, FRSM, NEWS, NSSR.
-- Maps instructor details from faculty_users and secfht tables; defaults instructor name to "To Be Announced" if missing.
-- Tags questions using course_surveys_question_tags for classification (e.g., Instructor vs Course).
-- Calculates current_survey and current_year flags based on term start and end dates (Current if within 180 days for survey, 365 days for year).
-- Converts numeric answers into descriptive responses: "Strongly Agree/Agree" for 3–4, "Strongly Disagree/Disagree" for 1–2, else "N/A".
-- Ensures updates occur when any instructor or administrative role assignments change (chair, dean, FSC, SME, admin, director) or college changes.
-- Implements retry logic for deadlocks with up to 3 attempts and 60-second waits between retries.
-- Inserts or updates rows only when differences exist between source and target for survey status, year, instructor roles, or college.
--
-- URL: https://reports.liberty.edu/#/site/Academics/views/EndofCourseSurveys/EndofCourseSurveyScores?:iid=1
--
--DECLARE
-- Parameters
v_etl_date    DATE := SYSDATE;
v_msg         VARCHAR2(2000);
v_instance    VARCHAR2(50) := upper(inst); -- inst from the jams job; used for determining instance
v_partition   NUMBER := nmbr; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_lms_course_surveys_tableau';
v_retry_count NUMBER := 0;
v_max_retries NUMBER := 3; -- number of retries for WAIT
v_wait_time   NUMBER := 60; -- seconds for WAIT
v_term_code   VARCHAR2(6);
CURSOR c_terms IS
-- Run current terms
SELECT terms.term_code,
       terms.start_date,
       terms.end_date,
       terms.group_code
  FROM zbtm.terms_by_group_v terms
 WHERE 1 = 1
   AND terms.group_code IN ('STD', 'MED', 'ACD')
      -- controls what terms run for which instances (only)
   AND ((terms.group_code = 'STD' AND SYSDATE BETWEEN terms.start_date - 7 AND terms.end_date + 7 AND v_instance = 'L2CAN') OR
       (terms.group_code = 'MED' AND SYSDATE BETWEEN terms.start_date - 7 AND terms.end_date + 7 AND v_instance = 'L2CAN') OR
       (terms.group_code = 'ACD' AND SYSDATE BETWEEN terms.start_date - 7 AND terms.end_date + 8 AND v_instance = 'ACCAN'))
   AND (to_char(SYSDATE, 'HH24') BETWEEN '00' AND '08') -- *outside of high demand*
UNION
-- Run non-current terms - **ONLY RUN DURING NON-BUSINESS HOURS** 
SELECT terms.term_code,
       terms.start_date,
       terms.end_date,
       terms.group_code
  FROM zbtm.terms_by_group_v terms
 WHERE 1 = 1
   AND terms.group_code IN ('STD', 'MED', 'ACD')
   AND ((terms.group_code = 'STD' AND SYSDATE BETWEEN terms.start_date - 180 AND terms.end_date + 180 AND v_instance = 'L2CAN') OR
       (terms.group_code = 'MED' AND SYSDATE BETWEEN terms.start_date - 180 AND terms.end_date + 180 AND v_instance = 'L2CAN') OR
       (terms.group_code = 'ACD' AND SYSDATE BETWEEN terms.start_date - 180 AND terms.end_date + 365 AND v_instance = 'ACCAN'))
   AND (to_char(SYSDATE, 'HH24') BETWEEN '18' AND '23') -- *outside of high demand*
UNION ALL
-- Run non-banner terms - **ONLY RUN DURING NON-BUSINESS HOURS** 
SELECT '000000' AS term_code,
       trunc(SYSDATE - 365) AS start_date,
       trunc(SYSDATE + 365) AS end_date,
       '000' AS group_code
  FROM dual
 WHERE 1 = 1
   AND v_instance = 'L2CAN' -- only non term instance 
      --  *outside of high demand*
   AND (to_char(SYSDATE, 'HH24') BETWEEN '18' AND '23') -- *outside of high demand*
 ORDER BY group_code DESC,
          start_date DESC;
BEGIN
-- dbms_output.enable(buffer_size => NULL);
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
-- once a MONTH, check for older years and only keep the last years worth of data in the dashboard
IF to_number(to_char(SYSDATE, 'DD')) = 1 THEN
DELETE FROM utl_d_lms.course_surveys_tableau tgt
 WHERE EXISTS (SELECT 1
          FROM utl_d_lms.lms_link ll
         WHERE ll.instance = tgt.instance
           AND ll.course_section_id = tgt.course_section_id
           AND ll.instance = v_instance
           AND ll.partition = v_partition)
   AND EXISTS (SELECT 1
          FROM zbtm.terms_by_group_v t
         WHERE t.term_code = tgt.term_code
           AND t.end_date < SYSDATE - (365 * 1));
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'DELETE - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
-- recalc stats if we found rows to delete
IF v_count > 0 THEN
utl_d_lms.gather_stats('course_surveys_tableau');
END IF;
END IF;
FOR rec IN c_terms
LOOP
v_term_code := rec.term_code;
v_count     := 0; -- reset count
v_elapsed   := round((SYSDATE - v_etl_date) * 86400);
v_msg       := 'START - ' || v_term_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- Retry mechanism for handling deadlocks
v_retry_count := 0;
LOOP
BEGIN
MERGE INTO utl_d_lms.course_surveys_tableau tgt
USING (SELECT src.term_code,
              src.ptrm_code,
              src.crn,
              src.course_section_id,
              src.camp_code,
              src.course_code,
              src.subj_code,
              src.crse_numb,
              src.seq_numb,
              src.levl_code,
              src.course,
              src.instructor_luid,
              src.instructor_pidm,
              src.instructor_name,
              src.question_number,
              src.response,
              src.survey_id,
              src.question_id,
              src.question_text,
              src.numeric_answer,
              src.option_id,
              src.full_text_answer,
              src.question_type,
              src.current_survey,
              src.current_year,
              src.response_unique_id,
              src.question_source,
              src.activity_date,
              src.instructor_username,
              src.im_usernames,
              src.chair_usernames,
              src.dean_usernames,
              src.fsc_usernames,
              src.sme_usernames,
              src.admin_usernames,
              src.director_usernames,
              src.college,
              src.faculty_status,
              src.instance,
              src.survey_source
         FROM (SELECT ll.term_code,
                      ll.ptrm_code,
                      ll.crn,
                      ll.course_section_id,
                      CASE
                      WHEN (ll.camp_code = 'D' OR (ll.camp_code = 'R' AND ll.insm_code = 'ON' AND ll.subj_code IN ('INQR', 'RSCH', 'UNIV')))
                           AND ll.subj_code NOT IN ('CSER', 'CAFE', 'SFME', 'FRSM', 'NEWS', 'NSSR') THEN
                       'Online'
                      ELSE
                       'Resident'
                      END AS camp_code,
                      ll.course_code,
                      ll.subj_code,
                      ll.crse_numb,
                      ll.seq_numb,
                      ll.levl_code,
                      ll.subj_code || ll.crse_numb AS course,
                      fu.luid AS instructor_luid,
                      fu.pidm AS instructor_pidm,
                      CASE
                      WHEN fu.last_name || fu.first_name IS NULL THEN
                       'To Be Announced'
                      ELSE
                       fu.last_name || ', ' || fu.first_name
                      END AS instructor_name,
                      cs.question_sequence AS question_number,
                      CASE
                      WHEN round(cs.numeric_answer, 0) IN (3, 4) THEN
                       'Strongly Agree/Agree'
                      WHEN round(cs.numeric_answer, 0) IN (1, 2) THEN
                       'Strongly Disagree/Disagree'
                      ELSE
                       'N/A'
                      END AS response,
                      cs.survey_id,
                      cs.question_id,
                      TRIM(to_char(regexp_replace(cs.question, '(<.*?>)|[' || chr(10) || chr(9) || chr(13) || ']|[^' || chr(1) || '-' || chr(127) || ']'))) AS question_text,
                      round(cs.numeric_answer, 0) AS numeric_answer,
                      cs.option_id,
                      cs.full_text_answer,
                      tags.question_tag AS question_type,
                      CASE
                      WHEN t.end_date >= (SYSDATE - 180)
                           AND t.start_date <= SYSDATE THEN
                       'Current'
                      ELSE
                       'Historical - ' || t.term_code
                      END AS current_survey,
                      CASE
                      WHEN t.end_date >= (SYSDATE - 365)
                           AND t.start_date <= SYSDATE THEN
                       'Current'
                      ELSE
                       'Historical - ' || t.fa_proc_year
                      END AS current_year,
                      cs.response_unique_id,
                      cs.question_type AS question_source,
                      v_etl_date AS activity_date,
                      fht.instructor_username,
                      fht.im_usernames,
                      fht.chair_usernames,
                      fht.dean_usernames,
                      fht.fsc_usernames,
                      fht.sme_usernames,
                      fht.admin_usernames,
                      fht.director_usernames,
                      fht.college,
                      'Not Listed' AS faculty_status,
                      cs.instance,
                      cs.survey_source
                 FROM utl_d_lms.course_surveys cs
                 JOIN utl_d_lms.lms_link ll
                   ON ll.instance = cs.instance
                  AND ll.course_section_id = cs.course_section_id
                  AND ll.instance = v_instance
                  AND cs.term_code = v_term_code
                  AND ll.partition = v_partition
                  AND lower(cs.survey_title) LIKE lower('%end of course survey%')
                  AND cs.survey_id NOT IN ('1601905')
                  AND cs.question_type = 3 -- quant scores
                 JOIN zbtm.terms_by_group_v t
                   ON t.term_code = ll.term_code
                  AND t.group_code IN ('STD')
                 JOIN utl_d_aa.secfht fht
                   ON fht.term_code = ll.term_code
                  AND fht.crn = ll.crn
                 LEFT JOIN utl_d_lms.faculty_users fu
                   ON fu.instance = ll.instance
                  AND fu.pidm = fht.pidm
                 LEFT JOIN utl_d_lms.course_surveys_question_tags tags
                   ON tags.survey_id = cs.survey_id
                  AND tags.question_id = cs.question_id
                  AND tags.instance = ll.instance
                 JOIN saturn.stvcoll
                   ON stvcoll_code = ll.coll_code) src
         LEFT JOIN utl_d_lms.course_surveys_tableau tgt
           ON tgt.instance = src.instance
          AND tgt.course_section_id = src.course_section_id
          AND tgt.survey_id = src.survey_id
          AND tgt.question_id = src.question_id
          AND tgt.response_unique_id = src.response_unique_id
          AND tgt.option_id = src.option_id
        WHERE 1 = 1
          AND (((src.current_survey IS NULL AND tgt.current_survey IS NOT NULL) OR (src.current_survey IS NOT NULL AND tgt.current_survey IS NULL)) OR -- new
              (coalesce(src.current_year, 'X') <> coalesce(tgt.current_year, 'X')) OR -- updates...
              (coalesce(src.instructor_username, 'X') <> coalesce(tgt.instructor_username, 'X')) OR --
              (coalesce(src.im_usernames, 'X') <> coalesce(tgt.im_usernames, 'X')) OR --
              (coalesce(src.chair_usernames, 'X') <> coalesce(tgt.chair_usernames, 'X')) OR --
              (coalesce(src.dean_usernames, 'X') <> coalesce(tgt.dean_usernames, 'X')) OR --
              (coalesce(src.fsc_usernames, 'X') <> coalesce(tgt.fsc_usernames, 'X')) OR --
              (coalesce(src.sme_usernames, 'X') <> coalesce(tgt.sme_usernames, 'X')) OR --
              (coalesce(src.admin_usernames, 'X') <> coalesce(tgt.admin_usernames, 'X')) OR --
              (coalesce(src.director_usernames, 'X') <> coalesce(tgt.director_usernames, 'X')) OR --
              (coalesce(src.college, 'X') <> coalesce(tgt.college, 'X')))) src
ON (tgt.instance = src.instance AND tgt.course_section_id = src.course_section_id AND tgt.survey_id = src.survey_id AND tgt.question_id = src.question_id AND tgt.response_unique_id = src.response_unique_id AND tgt.option_id = src.option_id)
WHEN MATCHED THEN
UPDATE
   SET tgt.current_survey      = src.current_survey,
       tgt.current_year        = src.current_year,
       tgt.activity_date       = src.activity_date,
       tgt.instructor_username = src.instructor_username,
       tgt.im_usernames        = src.im_usernames,
       tgt.chair_usernames     = src.chair_usernames,
       tgt.dean_usernames      = src.dean_usernames,
       tgt.fsc_usernames       = src.fsc_usernames,
       tgt.sme_usernames       = src.sme_usernames,
       tgt.admin_usernames     = src.admin_usernames,
       tgt.director_usernames  = src.director_usernames,
       tgt.college             = src.college
WHEN NOT MATCHED THEN
INSERT
(term_code,
 ptrm_code,
 crn,
 course_section_id,
 camp_code,
 course_code,
 subj_code,
 crse_numb,
 seq_numb,
 levl_code,
 course,
 instructor_luid,
 instructor_pidm,
 instructor_name,
 question_number,
 response,
 survey_id,
 question_id,
 question_text,
 numeric_answer,
 option_id,
 full_text_answer,
 question_type,
 current_survey,
 current_year,
 response_unique_id,
 question_source,
 activity_date,
 instructor_username,
 im_usernames,
 chair_usernames,
 dean_usernames,
 fsc_usernames,
 sme_usernames,
 admin_usernames,
 director_usernames,
 college,
 faculty_status,
 survey_source,
 instance)
VALUES
(src.term_code,
 src.ptrm_code,
 src.crn,
 src.course_section_id,
 src.camp_code,
 src.course_code,
 src.subj_code,
 src.crse_numb,
 src.seq_numb,
 src.levl_code,
 src.course,
 src.instructor_luid,
 src.instructor_pidm,
 src.instructor_name,
 src.question_number,
 src.response,
 src.survey_id,
 src.question_id,
 src.question_text,
 src.numeric_answer,
 src.option_id,
 src.full_text_answer,
 src.question_type,
 src.current_survey,
 src.current_year,
 src.response_unique_id,
 src.question_source,
 src.activity_date,
 src.instructor_username,
 src.im_usernames,
 src.chair_usernames,
 src.dean_usernames,
 src.fsc_usernames,
 src.sme_usernames,
 src.admin_usernames,
 src.director_usernames,
 src.college,
 src.faculty_status,
 src.survey_source,
 src.instance);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'MERGE - ' || v_term_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
v_total_count := v_total_count + v_count;
MERGE INTO utl_d_lms.course_surveys_tableau tgt
USING (SELECT src.term_code,
              src.ptrm_code,
              src.crn,
              src.course_section_id,
              src.camp_code,
              src.course_code,
              src.subj_code,
              src.crse_numb,
              src.seq_numb,
              src.levl_code,
              src.course,
              src.instructor_luid,
              src.instructor_pidm,
              src.instructor_name,
              src.question_number,
              src.response,
              src.survey_id,
              src.question_id,
              src.question_text,
              src.numeric_answer,
              src.option_id,
              src.full_text_answer,
              src.question_type,
              src.current_survey,
              src.current_year,
              src.response_unique_id,
              src.question_source,
              src.activity_date,
              src.instructor_username,
              src.im_usernames,
              src.chair_usernames,
              src.dean_usernames,
              src.fsc_usernames,
              src.sme_usernames,
              src.admin_usernames,
              src.director_usernames,
              src.college,
              src.faculty_status,
              src.instance,
              src.survey_source
         FROM (SELECT ll.term_code term_code,
                      ll.ptrm_code ptrm_code,
                      ll.crn,
                      ll.course_section_id,
                      CASE
                      WHEN (ll.camp_code = 'D' OR (ll.camp_code = 'R' AND ll.insm_code = 'ON' AND ll.subj_code IN ('INQR', 'RSCH', 'UNIV')))
                           AND ll.subj_code NOT IN ('CSER', 'CAFE', 'SFME', 'FRSM', 'NEWS', 'NSSR') THEN
                       'Online'
                      ELSE
                       'Resident'
                      END AS camp_code,
                      ll.course_code,
                      ll.subj_code,
                      ll.crse_numb,
                      ll.seq_numb,
                      ll.levl_code,
                      ll.subj_code || ll.crse_numb AS course,
                      fu.luid AS instructor_luid,
                      fu.pidm AS instructor_pidm,
                      CASE
                      WHEN fu.last_name || fu.first_name IS NULL THEN
                       'To Be Announced'
                      ELSE
                       fu.last_name || ', ' || fu.first_name
                      END AS instructor_name,
                      cs.question_sequence AS question_number,
                      CASE
                      WHEN round(cs.numeric_answer, 0) IN (3, 4) THEN
                       'Strongly Agree/Agree'
                      WHEN round(cs.numeric_answer, 0) IN (1, 2) THEN
                       'Strongly Disagree/Disagree'
                      ELSE
                       'N/A'
                      END response,
                      cs.survey_id AS survey_id,
                      cs.question_id,
                      TRIM(to_char(regexp_replace(cs.question, '(<.*?>)|[' || chr(10) || chr(9) || chr(13) || ']|[^' || chr(1) || '-' || chr(127) || ']'))) question_text,
                      round(cs.numeric_answer, 0) AS numeric_answer,
                      cs.option_id,
                      cs.full_text_answer,
                      tags.question_tag AS question_type,
                      CASE
                      WHEN t.end_date >= (SYSDATE - 180)
                           AND t.start_date <= SYSDATE THEN
                       'Current'
                      ELSE
                       'Historical - ' || t.term_code
                      END AS current_survey,
                      CASE
                      WHEN t.end_date >= (SYSDATE - 365)
                           AND t.start_date <= SYSDATE THEN
                       'Current'
                      ELSE
                       'Historical - ' || t.fa_proc_year
                      END AS current_year,
                      cs.response_unique_id,
                      cs.question_type AS question_source,
                      v_etl_date AS activity_date,
                      fht.instructor_username,
                      fht.im_usernames,
                      fht.chair_usernames,
                      fht.dean_usernames,
                      fht.fsc_usernames,
                      fht.sme_usernames,
                      fht.admin_usernames,
                      fht.director_usernames,
                      fht.college,
                      'Not Listed' AS faculty_status,
                      cs.instance,
                      cs.survey_source
                 FROM utl_d_lms.course_surveys cs
                 JOIN utl_d_lms.lms_link ll
                   ON ll.instance = cs.instance
                  AND ll.course_section_id = cs.course_section_id
                  AND ll.instance = v_instance
                  AND cs.term_code = v_term_code
                  AND ll.partition = v_partition
                  AND lower(cs.survey_title) LIKE lower('%end of course survey%')
                  AND cs.survey_id NOT IN ('1601905')
                  AND cs.question_type = 1 -- qual scores
                 JOIN zbtm.terms_by_group_v t
                   ON t.term_code = ll.term_code
                  AND t.group_code IN ('STD')
                 JOIN utl_d_aa.secfht fht
                   ON fht.term_code = ll.term_code
                  AND fht.crn = ll.crn
                 LEFT JOIN utl_d_lms.faculty_users fu
                   ON fu.instance = ll.instance
                  AND fu.pidm = fht.pidm
                 LEFT JOIN utl_d_lms.course_surveys_question_tags tags
                   ON tags.survey_id = cs.survey_id
                  AND tags.question_id = cs.question_id
                  AND tags.instance = ll.instance
                 JOIN saturn.stvcoll
                   ON stvcoll_code = ll.coll_code
                WHERE 1 = 1
                  AND NOT
                       regexp_like(lower(TRIM(to_char(regexp_replace(cs.full_text_answer, '(<.*?>)|[' || chr(10) || chr(9) || chr(13) || ']|[^' || chr(1) || '-' || chr(127) || ']')))), 'none|na|n/a|no recommendation|nothing|no comment|not applicable|no improvements|no suggestions')
                  AND length(TRIM(to_char(regexp_replace(cs.full_text_answer, '(<.*?>)|[' || chr(10) || chr(9) || chr(13) || ']|[^' || chr(1) || '-' || chr(127) || ']')))) > 3) src
         LEFT JOIN utl_d_lms.course_surveys_tableau tgt
           ON tgt.instance = src.instance
          AND tgt.course_section_id = src.course_section_id
          AND tgt.survey_id = src.survey_id
          AND tgt.question_id = src.question_id
          AND tgt.response_unique_id = src.response_unique_id
          AND tgt.option_id = src.option_id
        WHERE 1 = 1
          AND (((src.current_survey IS NULL AND tgt.current_survey IS NOT NULL) OR (src.current_survey IS NOT NULL AND tgt.current_survey IS NULL)) OR -- new
              (coalesce(src.current_year, 'X') <> coalesce(tgt.current_year, 'X')) OR -- updates...
              (coalesce(src.instructor_username, 'X') <> coalesce(tgt.instructor_username, 'X')) OR --
              (coalesce(src.im_usernames, 'X') <> coalesce(tgt.im_usernames, 'X')) OR --
              (coalesce(src.chair_usernames, 'X') <> coalesce(tgt.chair_usernames, 'X')) OR --
              (coalesce(src.dean_usernames, 'X') <> coalesce(tgt.dean_usernames, 'X')) OR --
              (coalesce(src.fsc_usernames, 'X') <> coalesce(tgt.fsc_usernames, 'X')) OR --
              (coalesce(src.sme_usernames, 'X') <> coalesce(tgt.sme_usernames, 'X')) OR --
              (coalesce(src.admin_usernames, 'X') <> coalesce(tgt.admin_usernames, 'X')) OR --
              (coalesce(src.director_usernames, 'X') <> coalesce(tgt.director_usernames, 'X')) OR --
              (coalesce(src.college, 'X') <> coalesce(tgt.college, 'X')))) src
ON (tgt.instance = src.instance AND tgt.course_section_id = src.course_section_id AND tgt.survey_id = src.survey_id AND tgt.question_id = src.question_id AND tgt.response_unique_id = src.response_unique_id AND tgt.option_id = src.option_id)
WHEN MATCHED THEN
UPDATE
   SET tgt.current_survey      = src.current_survey,
       tgt.current_year        = src.current_year,
       tgt.activity_date       = src.activity_date,
       tgt.instructor_username = src.instructor_username,
       tgt.im_usernames        = src.im_usernames,
       tgt.chair_usernames     = src.chair_usernames,
       tgt.dean_usernames      = src.dean_usernames,
       tgt.fsc_usernames       = src.fsc_usernames,
       tgt.sme_usernames       = src.sme_usernames,
       tgt.admin_usernames     = src.admin_usernames,
       tgt.director_usernames  = src.director_usernames,
       tgt.college             = src.college
WHEN NOT MATCHED THEN
INSERT
(term_code,
 ptrm_code,
 crn,
 course_section_id,
 camp_code,
 course_code,
 subj_code,
 crse_numb,
 seq_numb,
 levl_code,
 course,
 instructor_luid,
 instructor_pidm,
 instructor_name,
 question_number,
 response,
 survey_id,
 question_id,
 question_text,
 numeric_answer,
 option_id,
 full_text_answer,
 question_type,
 current_survey,
 current_year,
 response_unique_id,
 question_source,
 activity_date,
 instructor_username,
 im_usernames,
 chair_usernames,
 dean_usernames,
 fsc_usernames,
 sme_usernames,
 admin_usernames,
 director_usernames,
 college,
 faculty_status,
 survey_source,
 instance)
VALUES
(src.term_code,
 src.ptrm_code,
 src.crn,
 src.course_section_id,
 src.camp_code,
 src.course_code,
 src.subj_code,
 src.crse_numb,
 src.seq_numb,
 src.levl_code,
 src.course,
 src.instructor_luid,
 src.instructor_pidm,
 src.instructor_name,
 src.question_number,
 src.response,
 src.survey_id,
 src.question_id,
 src.question_text,
 src.numeric_answer,
 src.option_id,
 src.full_text_answer,
 src.question_type,
 src.current_survey,
 src.current_year,
 src.response_unique_id,
 src.question_source,
 src.activity_date,
 src.instructor_username,
 src.im_usernames,
 src.chair_usernames,
 src.dean_usernames,
 src.fsc_usernames,
 src.sme_usernames,
 src.admin_usernames,
 src.director_usernames,
 src.college,
 src.faculty_status,
 src.survey_source,
 src.instance);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'MERGE - ' || v_term_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
v_total_count := v_total_count + v_count;
EXIT; -- If successful, exit the retry loop
EXCEPTION
WHEN OTHERS THEN
IF SQLCODE = -60 THEN
-- Deadlock detected
v_retry_count := v_retry_count + 1;
IF v_retry_count > v_max_retries THEN
-- Log error for max retries
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := '!!!-00060: deadlock detected while waiting for resource. Max retries exceeded after ' || (v_max_retries * v_wait_time) || ' seconds';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
EXIT; -- Add EXIT here to break out of the loop when max retries exceeded
ELSE
-- Log retry attempt
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'Deadlock detected while waiting for resource - waiting ' || v_wait_time || ' seconds for retry attempt number ' || v_retry_count;
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'WARNING', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
dbms_lock.sleep(v_wait_time); -- Wait between retries; short wait because it will need to cycle through all the GTTs again
CONTINUE; -- Add CONTINUE to explicitly indicate loop continuation
END IF;
ELSE
-- Other errors
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
/*--------------------------------------------CHANGE LOG----------------------------------------
VERSION  DATE        USERNAME    UPDATES
---      05-26-2023  WGRIFFITH2  --Initial release
---      10-10-2023  WGRIFFITH2  --related to course_surveys table updates
---      02-25-2025  WGRIFFITH2  --inserts -> merge becuase all FHT data needs refresh when positions change (TKT3054991); adding WAIT to avoid deadlocks
---     20251117      WGRIFFITH2      --Added one-year retention logic and instructor fallback to TBA
-- 20251215 - WGRIFFITH2 - Added [zhalibut.course_survey_response_reporting_view]; integrated ZHALIBUT MERGE into [etl_lms_course_surveys]
------------------------------------------------------------------------------------------------*/
END etl_lms_course_surveys_tableau;

procedure etl_lms_announcements (jobnumber number, processid varchar2, processname varchar2, inst varchar2, nmbr number) is
/*
Table: utl_d_lms.announcements

Primary Keys: SURROGATE_ID

Unique index: INSTANCE, COURSE_SECTION_ID, ANNOUNCEMENT_ID

Purpose: Contains announcements in CANVAS

Conditions:

Dependencies:  utl_d_lms.lms_link
*/
--DECLARE
v_etl_date DATE := SYSDATE;
v_msg      VARCHAR2(2000);
v_instance VARCHAR2(50) := upper(inst); -- inst from the jams job; used for determining instance
v_partition NUMBER := nmbr; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
--v_row_max     NUMBER := 100000; -- max number of rows to be processed at one time
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_count       NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_lms_announcements';
CURSOR c_terms IS
-- Run current terms
SELECT terms.term_code,
       terms.start_date,
       terms.end_date,
       terms.group_code
  FROM zbtm.terms_by_group_v terms
 WHERE 1 = 1
   AND terms.group_code IN ('STD', 'MED', 'ACD')
   -- controls what terms run for which instances (only)
   AND ((terms.group_code = 'STD' AND SYSDATE BETWEEN terms.start_date - 7 AND terms.end_date + 7 AND v_instance = 'L2CAN') OR
       (terms.group_code = 'MED' AND SYSDATE BETWEEN terms.start_date - 7 AND terms.end_date + 7 AND v_instance = 'L2CAN') OR
       (terms.group_code = 'ACD' AND SYSDATE BETWEEN terms.start_date - 7 AND terms.end_date + 8 AND v_instance = 'ACCAN'))
   AND (to_char(SYSDATE, 'HH24') BETWEEN '00' AND '08') -- *outside of high demand*
UNION
-- Run non-current terms - **ONLY RUN DURING NON-BUSINESS HOURS** 
SELECT terms.term_code,
       terms.start_date,
       terms.end_date,
       terms.group_code
  FROM zbtm.terms_by_group_v terms
 WHERE 1 = 1
   AND terms.group_code IN ('STD', 'MED', 'ACD')
   AND ((terms.group_code = 'STD' AND SYSDATE BETWEEN terms.start_date - 180 AND terms.end_date + 180 AND v_instance = 'L2CAN') OR
       (terms.group_code = 'MED' AND SYSDATE BETWEEN terms.start_date - 180 AND terms.end_date + 180 AND v_instance = 'L2CAN') OR
       (terms.group_code = 'ACD' AND SYSDATE BETWEEN terms.start_date - 180 AND terms.end_date + 365 AND v_instance = 'ACCAN'))
   AND (to_char(SYSDATE, 'HH24') BETWEEN '18' AND '23') -- *outside of high demand*
UNION ALL
-- Run non-banner terms - **ONLY RUN DURING NON-BUSINESS HOURS** 
SELECT '000000' AS term_code,
       trunc(SYSDATE - 365) AS start_date,
       trunc(SYSDATE + 365) AS end_date,
       '000' AS group_code
  FROM dual
 WHERE 1 = 2 -- DO NOT RUN NON-TERM FOR THIS PROCEDURE
   AND v_instance = 'L2CAN' -- only non term instance  
   AND (to_char(SYSDATE, 'HH24') BETWEEN '18' AND '23') -- *outside of high demand*
 ORDER BY group_code DESC,
          start_date DESC;
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
v_msg     := 'START - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
MERGE INTO utl_d_lms.announcements destination_table
USING (SELECT src.course_section_id,
              src.announcement_id,
              src.user_id,
              src.editor_id,
              src.title,
              src.message_text,
              src.discussion_type,
              src.type,
              src.position AS position,
              src.created_date,
              src.posted_date,
              src.delayed_posted_date,
              src.updated_date,
              src.workflow_state,
              src.instance,
              src.activity_date,
              src.term_code,
              'CDE' AS data_source
         FROM (SELECT ll.course_section_id,
                       dt.id AS announcement_id,
                       CASE
                       WHEN dt.user_id IS NULL THEN
                        dt.editor_id
                       ELSE
                        dt.user_id
                       END AS user_id,
                       CASE
                       WHEN dt.editor_id IS NULL THEN
                        dt.user_id
                       ELSE
                        dt.editor_id
                       END AS editor_id,
                       dt.title,
                       to_char(dbms_lob.substr(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(TRIM(dt.message), '(<.*?>)|[^' || chr(1) || '-' || chr(127) || ']') --getting rid of non-printable ascii
                                                                                                                                                        , '(' || chr(38) || 'nbsp;)|[' || chr(10) || chr(9) || chr(13) || ']', ' ', 1, 0, 'i') --replacing html tags, &nbsp;, <tab>, new lines with a space
                                                                                                                                         , '[ ]{2,}', ' ') --replacing mutliple spaces with a single space
                                                                                                                          , chr(38) || 'amp;', '&', 1, 0, 'i') --replacing &amp; with &
                                                                                                           , chr(38) || 'lt;', '<', 1, 0, 'i') --replacing &lt; with <
                                                                                            , chr(38) || 'gt;', '>', 1, 0, 'i') --replacing &gt; with >
                                                                             , chr(38) || 'quot;', '"', 1, 0, 'i') --replacing &quot; with "
                                                              , chr(38) || 'apos;', '''', 1, 0, 'i') --replacing &apos; with '
                                              , 3900, 1)) AS message_text,
                      coalesce(dt.type, 'none') AS TYPE,
                      coalesce(dt.discussion_type, 'none') AS discussion_type,
                      dt.position,
                      dt.created_at AS created_date,
                      dt.posted_at AS posted_date,
                      dt.delayed_post_at AS delayed_posted_date,
                      dt.updated_at AS updated_date,
                      dt.workflow_state,
                      v_instance AS instance,
                      v_etl_date AS activity_date,
                      ll.term_code
                 FROM utl_d_lms.lms_link ll
                 JOIN zcanvas_data.discussion_topics dt
                   ON dt.context_id = ll.course_id
                  AND dt.instance = ll.instance
                  AND dt.type = 'Announcement'
                  AND dt.title <> 'Welcome to Canvas!'
                WHERE 1 = 1
                  AND ll.instance = v_instance
                  AND v_instance = 'L2CAN' -- DO NOT REMOVE
                  AND ll.term_code = rec.term_code
                  AND ll.partition = v_partition
                  AND dt.updated_at >= trunc(v_etl_date - 7)) src
         LEFT JOIN utl_d_lms.announcements tgt
           ON tgt.instance = src.instance
          AND tgt.course_section_id = src.course_section_id
          AND tgt.announcement_id = src.announcement_id
        WHERE 1 = 1 -- jic there overlap running different v_partition at the same time
             -- for inserts or deletes...
          AND (((src.course_section_id IS NULL AND tgt.course_section_id IS NOT NULL) OR (src.course_section_id IS NOT NULL AND tgt.course_section_id IS NULL)) OR --
              -- for updates only if the source data is more recent
              (coalesce(src.created_date, systimestamp - 365) > coalesce(tgt.created_date, systimestamp)) OR --
              (coalesce(src.posted_date, systimestamp - 365) > coalesce(tgt.posted_date, systimestamp)) OR --
              (coalesce(src.delayed_posted_date, systimestamp - 365) > coalesce(tgt.delayed_posted_date, systimestamp)))) new_records
ON (destination_table.instance = new_records.instance AND destination_table.course_section_id = new_records.course_section_id AND destination_table.announcement_id = new_records.announcement_id)
WHEN MATCHED THEN
UPDATE
   SET destination_table.user_id             = new_records.user_id,
       destination_table.editor_id           = new_records.editor_id,
       destination_table.title               = new_records.title,
       destination_table.message_text        = new_records.message_text,
       destination_table.type                = new_records.type,
       destination_table.discussion_type     = new_records.discussion_type,
       destination_table.position            = new_records.position,
       destination_table.created_date        = new_records.created_date,
       destination_table.posted_date         = new_records.posted_date,
       destination_table.delayed_posted_date = new_records.delayed_posted_date,
       destination_table.updated_date        = new_records.updated_date,
       destination_table.workflow_state      = new_records.workflow_state,
       destination_table.term_code           = new_records.term_code,
       destination_table.data_source         = new_records.data_source,
       destination_table.activity_date       = v_etl_date
WHEN NOT MATCHED THEN
INSERT
(course_section_id,
 announcement_id,
 user_id,
 editor_id,
 title,
 message_text,
 TYPE,
 discussion_type,
 position,
 created_date,
 posted_date,
 delayed_posted_date,
 updated_date,
 workflow_state,
 instance,
 activity_date,
 term_code,
 data_source)
VALUES
(new_records.course_section_id,
 new_records.announcement_id,
 new_records.user_id,
 new_records.editor_id,
 new_records.title,
 new_records.message_text,
 new_records.type,
 new_records.discussion_type,
 new_records.position,
 new_records.created_date,
 new_records.posted_date,
 new_records.delayed_posted_date,
 new_records.updated_date,
 new_records.workflow_state,
 new_records.instance,
 new_records.activity_date,
 new_records.term_code,
 new_records.data_source);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
end loop; -- c_terms
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
END etl_lms_announcements;
procedure etl_lms_discussions (jobnumber number, processid varchar2, processname varchar2, inst varchar2, nmbr number) is
/*
Table: utl_d_lms.discussions

Primary Keys: SURROGATE_ID

Unique index: INSTANCE, COURSE_SECTION_ID, DISCUSSION_ID

Purpose: Contains discussions in CANVAS for instructors/faculty (only)

Conditions:

Dependencies:  utl_d_lms.lms_link
*/
--DECLARE
v_etl_date DATE := SYSDATE;
v_msg      VARCHAR2(2000);
v_instance VARCHAR2(50) := upper(inst); -- inst from the jams job; used for determining instance
v_partition NUMBER := nmbr; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_row_max NUMBER := 100000; -- max number of rows to be processed at one time
v_count   NUMBER := 0;
v_job_id  VARCHAR2(32);
v_proc    VARCHAR2(100) := 'etl_lms_discussions';
CURSOR c_terms IS
-- Run current terms
SELECT terms.term_code,
       terms.start_date,
       terms.end_date,
       terms.group_code
  FROM zbtm.terms_by_group_v terms
 WHERE 1 = 1
   AND terms.group_code IN ('STD', 'MED', 'ACD')
   -- controls what terms run for which instances (only)
   AND ((terms.group_code = 'STD' AND SYSDATE BETWEEN terms.start_date - 7 AND terms.end_date + 7 AND v_instance = 'L2CAN') OR
       (terms.group_code = 'MED' AND SYSDATE BETWEEN terms.start_date - 7 AND terms.end_date + 7 AND v_instance = 'L2CAN') OR
       (terms.group_code = 'ACD' AND SYSDATE BETWEEN terms.start_date - 7 AND terms.end_date + 8 AND v_instance = 'ACCAN'))
   AND (to_char(SYSDATE, 'HH24') BETWEEN '00' AND '08') -- *outside of high demand*
UNION
-- Run non-current terms - **ONLY RUN DURING NON-BUSINESS HOURS** 
SELECT terms.term_code,
       terms.start_date,
       terms.end_date,
       terms.group_code
  FROM zbtm.terms_by_group_v terms
 WHERE 1 = 1
   AND terms.group_code IN ('STD', 'MED', 'ACD')
   AND ((terms.group_code = 'STD' AND SYSDATE BETWEEN terms.start_date - 180 AND terms.end_date + 180 AND v_instance = 'L2CAN') OR
       (terms.group_code = 'MED' AND SYSDATE BETWEEN terms.start_date - 180 AND terms.end_date + 180 AND v_instance = 'L2CAN') OR
       (terms.group_code = 'ACD' AND SYSDATE BETWEEN terms.start_date - 180 AND terms.end_date + 365 AND v_instance = 'ACCAN'))
   AND (to_char(SYSDATE, 'HH24') BETWEEN '18' AND '23') -- *outside of high demand*
UNION ALL
-- Run non-banner terms - **ONLY RUN DURING NON-BUSINESS HOURS** 
SELECT '000000' AS term_code,
       trunc(SYSDATE - 365) AS start_date,
       trunc(SYSDATE + 365) AS end_date,
       '000' AS group_code
  FROM dual
 WHERE 1 = 2 -- DO NOT RUN NON-TERM FOR THIS PROCEDURE
   AND v_instance = 'L2CAN' -- only non term instance  
   AND (to_char(SYSDATE, 'HH24') BETWEEN '18' AND '23') -- *outside of high demand*
 ORDER BY group_code DESC,
          start_date DESC;
CURSOR c1(v_term_code VARCHAR) IS
SELECT DISTINCT ll.course_section_id, -- required field in constraint
                de.id                AS discussion_id,
                dt.id                AS discussion_topic_id,
                de.user_id,
                dt.title,
                /* to_char(dbms_lob.substr(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(TRIM(de.message), '(<.*?>)|[^' || chr(1) || '-' || chr(127) || ']') --getting rid of non-printable ascii
                                                                                                                         , '(' || chr(38) || 'nbsp;)|[' || chr(10) || chr(9) || chr(13) || ']', ' ', 1, 0, 'i') --replacing html tags, &nbsp;, <tab>, new lines with a space
                                                                                                          , '[ ]{2,}', ' ') --replacing mutliple spaces with a single space
                                                                                           , chr(38) || 'amp;', '&', 1, 0, 'i') --replacing &amp; with &
                                                                            , chr(38) || 'lt;', '<', 1, 0, 'i') --replacing &lt; with <
                                                             , chr(38) || 'gt;', '>', 1, 0, 'i') --replacing &gt; with >
                                              , chr(38) || 'quot;', '"', 1, 0, 'i') --replacing &quot; with "
                               , chr(38) || 'apos;', '''', 1, 0, 'i') --replacing &apos; with '
                , 3900, 1)) AS message_text,*/
                'Currently unavailable' AS message_text,
                coalesce(dt.discussion_type, 'none') AS discussion_type,
                de.depth AS message_depth, -- initial [1] or reply [>1]
                de.created_at AS created_date,
                de.updated_at AS updated_date,
                de.workflow_state,
                NULL AS orderid,
                'L2CAN' AS instance,
                SYSDATE AS activity_date,
                CASE
                WHEN de.workflow_state = 'deleted' THEN
                 'DELETE'
                WHEN ds.discussion_id IS NOT NULL THEN
                 'UPDATE'
                WHEN ds.discussion_id IS NULL THEN
                 'INSERT'
                ELSE
                 'NONE'
                END AS control_state,
                COUNT(*) over() total_rows,
                ll.term_code
  FROM zcanvas_data.enrollments e
  JOIN zcanvas_data.course_sections cs
    ON cs.id = e.course_section_id
   AND e.instance = cs.instance
   AND e.type IN ('TeacherEnrollment', 'TaEnrollment', 'DesignerEnrollment', 'ObserverEnrollment')
   AND e.workflow_state = 'active'
  JOIN zcanvas_data.courses c
    ON c.id = cs.course_id
   AND e.instance = c.instance
  JOIN utl_d_lms.lms_link ll
    ON cs.id = ll.course_section_id
   AND e.instance = ll.instance
   AND e.instance = v_instance
   AND v_instance = 'L2CAN' -- DO NOT REMOVE HARD CODED VALUE
   AND ll.term_code = v_term_code
   AND ll.partition = v_partition
  JOIN zcanvas_data.users u
    ON u.id = e.user_id
   AND u.instance = e.instance
  JOIN zcanvas_data.discussion_topics dt
    ON dt.context_id = c.id
   AND e.instance = dt.instance
   AND coalesce(dt.type, 'XX') <> 'Announcement'
  JOIN zcanvas_data.discussion_entries de
    ON de.discussion_topic_id = dt.id
   AND e.instance = de.instance
   AND de.user_id = u.id
  LEFT JOIN utl_d_lms.discussions ds
    ON ds.discussion_id = de.id
   AND ds.course_section_id = ll.course_section_id
   AND ds.instance = de.instance
 WHERE 1 = 1 -- get anything more recent or new
   AND (de.updated_at > ds.updated_date OR ds.updated_date IS NULL);
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
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
--
FOR rec IN c_terms
LOOP
OPEN c1(rec.term_code);
LOOP
v_count   := 0; -- reset count
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
FETCH c1 BULK COLLECT
INTO rec_input LIMIT v_row_max;
v_count := rec_input.count;
IF v_count = 0 THEN
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'SELECT - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
ELSIF v_count > 0 THEN
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
INSERT INTO utl_d_lms.discussions tab
(course_section_id,
 discussion_id,
 discussion_topic_id,
 user_id,
 title,
 message_text,
 discussion_type,
 message_depth,
 created_date,
 updated_date,
 workflow_state,
 instance,
 activity_date,
 term_code)
VALUES
(rec_input(i).course_section_id,
 rec_input(i).discussion_id,
 rec_input(i).discussion_topic_id,
 rec_input(i).user_id,
 rec_input(i).title,
 rec_input(i).message_text,
 rec_input(i).discussion_type,
 rec_input(i).message_depth,
 rec_input(i).created_date,
 rec_input(i).updated_date,
 rec_input(i).workflow_state,
 rec_input(i).instance,
 rec_input(i).activity_date,
 rec_input(i).term_code);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'INSERT - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
FORALL i IN VALUES OF update_dml -- DML UPDATES
UPDATE utl_d_lms.discussions tab
   SET (course_section_id, discussion_id, discussion_topic_id, user_id, title, message_text, discussion_type, message_depth, created_date, updated_date, workflow_state, instance, activity_date, term_code) =
       (SELECT rec_input(i).course_section_id,
               rec_input(i).discussion_id,
               rec_input(i).discussion_topic_id,
               rec_input(i).user_id,
               rec_input(i).title,
               rec_input(i).message_text,
               rec_input(i).discussion_type,
               rec_input(i).message_depth,
               rec_input(i).created_date,
               rec_input(i).updated_date,
               rec_input(i).workflow_state,
               rec_input(i).instance,
               rec_input(i).activity_date,
               rec_input(i).term_code
          FROM dual)
 WHERE tab.course_section_id = rec_input(i).course_section_id
   AND tab.discussion_id = rec_input(i).discussion_id
   AND tab.instance = rec_input(i).instance;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'UPDATE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
FORALL i IN VALUES OF delete_dml -- DML DELETES
DELETE FROM utl_d_lms.discussions tab
 WHERE tab.course_section_id = rec_input(i).course_section_id
   AND tab.discussion_id = rec_input(i).discussion_id
   AND tab.instance = rec_input(i).instance;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'DELETE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
END IF;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_total_count := v_total_count + rec_input.count;
EXIT WHEN(rec_input.count < v_row_max);
END LOOP;
CLOSE c1;
dbms_output.put_line(' --------- ');
end loop; -- c_terms
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
END etl_lms_discussions;
procedure etl_lms_student_enrollments (jobnumber number, processid varchar2, processname varchar2, inst varchar2, nmbr number) IS
--
-- PURPOSE: Synchronizes Banner enrollment data with Canvas to maintain accurate LMS student enrollment records.
--
-- TABLE: utl_d_lms.student_enrollments
--
-- UNIQUE INDEX: TERM_CODE, CRN, PIDM
--
-- CONDITIONS:
-- Processes enrollment data for current academic terms (STD, MED, ACD) within ±7 days of term start and end dates for L2CAN and ACCAN instances.
-- Includes historical term data within ±180 days for L2CAN and ±365 days for ACCAN, but only during non-business hours (6 PM to 11 PM).
-- Handles non-term Canvas courses (term_code = '000000') exclusively during non-business hours for L2CAN instance.
-- Excludes courses with subject code 'NEWS' from enrollment processing.
-- Includes only Banner enrollment statuses where section enrollment is allowed and excludes audit status ('AU').
-- For ACCAN instance, excludes withdrawn students and ensures assessment inclusion.
-- Joins Banner tables to retrieve course details, faculty assignments, cross-listed sections, and microsections; uses latest effective term for course attributes.
-- Calculates course start and end dates based on part-of-term dates, LUOA extension dates, or credit-hour-based duration adjustments for specific LAN courses.
-- For Canvas non-term courses, identifies sections without SIS source IDs and excludes accounts labeled as sandbox, curriculum, staging, archive, or manually created.
-- Ensures only active Canvas courses, sections, enrollments, and users are included; excludes deleted or unpublished workflow states.
-- Deduplicates Canvas enrollments using ranking logic based on last login and update timestamps.
-- Updates or inserts records when row-level hash comparison indicates new or changed data.
-- Deletes Banner-based enrollments that no longer exist in Banner for the same term and instance (except Blackboard).
-- Removes older course sections without microsection labels when a newer microsection exists for the same student and CRN.
-- Deletes Canvas non-term enrollments marked as deleted in Canvas when processing partition 0.
-- Applies partitioning logic using MOD function on PIDM or user_id for parallel processing.
--
-- URL: N/A
--
--DECLARE
v_etl_date    DATE := SYSDATE;
v_msg         VARCHAR2(2000);
v_instance    VARCHAR2(50) := upper(inst); -- inst from the jams job; used for determining instance
v_partition   NUMBER := nmbr; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_mod         NUMBER := 5; -- !!! KEEP HARDCODED !!!; how many parallels/partitions we run; **if changed** jams jobs will need updating
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_lms_student_enrollments';
v_retry_count NUMBER := 0;
v_max_retries NUMBER := 3; -- number of retries for WAIT
v_wait_time   NUMBER := 60; -- seconds for WAIT
v_term_code VARCHAR2(6);
CURSOR c_terms IS
-- Run current terms
SELECT terms.term_code,
       terms.start_date,
       terms.end_date,
       terms.group_code
  FROM zbtm.terms_by_group_v terms
 WHERE 1 = 1
   AND terms.group_code IN ('STD', 'MED', 'ACD') 
   -- controls what terms run for which instances (only)
   AND ((terms.group_code = 'STD' AND SYSDATE BETWEEN terms.start_date - 7 AND terms.end_date + 7 AND v_instance = 'L2CAN') OR
       (terms.group_code = 'MED' AND SYSDATE BETWEEN terms.start_date - 7 AND terms.end_date + 7 AND v_instance = 'L2CAN') OR
       (terms.group_code = 'ACD' AND SYSDATE BETWEEN terms.start_date - 7 AND terms.end_date + 8 AND v_instance = 'ACCAN'))
UNION
-- Run non-current terms - **ONLY RUN DURING NON-BUSINESS HOURS** 
SELECT terms.term_code,
       terms.start_date,
       terms.end_date,
       terms.group_code
  FROM zbtm.terms_by_group_v terms
 WHERE 1 = 1
   AND terms.group_code IN ('STD', 'MED', 'ACD')
   AND ((terms.group_code = 'STD' AND SYSDATE BETWEEN terms.start_date - 180 AND terms.end_date + 180 AND v_instance = 'L2CAN') OR
       (terms.group_code = 'MED' AND SYSDATE BETWEEN terms.start_date - 180 AND terms.end_date + 180 AND v_instance = 'L2CAN') OR
       (terms.group_code = 'ACD' AND SYSDATE BETWEEN terms.start_date - 180 AND terms.end_date + 365 AND v_instance = 'ACCAN'))
   AND (to_char(SYSDATE, 'HH24') BETWEEN '18' AND '23') -- *outside of high demand*
UNION ALL
-- Run non-banner terms - **ONLY RUN DURING NON-BUSINESS HOURS** 
SELECT '000000' AS term_code,
       trunc(SYSDATE - 365) AS start_date,
       trunc(SYSDATE + 365) AS end_date,
       '000' AS group_code
  FROM dual
 WHERE 1 = 1
   AND v_instance = 'L2CAN' -- only non term instance  
   AND (to_char(SYSDATE, 'HH24') BETWEEN '18' AND '23') -- *outside of high demand*
 ORDER BY group_code DESC,
          start_date DESC;
BEGIN
-- dbms_output.enable(buffer_size => NULL);
-- -- this runs ALTER SESSION ENABLE PARALLEL DML
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
FOR rec IN c_terms
LOOP
-- setting vars for looping (not already set)
v_term_code := rec.term_code;
v_count     := 0; -- reset count
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || v_term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
IF v_term_code NOT IN ('000000') THEN
-- BANNER (TERM) ENROLLMENTS
IF v_instance = 'L2CAN' THEN
INSERT INTO utl_d_lms.student_enrollments_gtt
(course_code,
 term_code,
 crn,
 pidm,
 luid,
 course_sis_id,
 section_sis_id,
 course_name,
 subj_code,
 crse_numb,
 seq_numb,
 ptrm_code,
 camp_code,
 insm_code,
 levl_code,
 coll_code,
 instance,
 start_date,
 end_date,
 base_course,
 faculty_pidm,
 microsection,
 cross_listed,
 data_source,
 PARTITION,
 activity_date)
SELECT ssbsect_subj_code || ssbsect_crse_numb || '_' || ssbsect_seq_numb || '_' || ssbsect_term_code AS course_code,
       sfrstcr_term_code AS term_code,
       sfrstcr_crn AS crn,
       spriden_pidm AS pidm,
       spriden_id AS luid,
       NULL AS course_sis_id, -- fill in downstream with courses table
       CASE
       WHEN szbmssc_crn IS NOT NULL THEN
        szbmssc_term_code || szbmssc_crn || '_' || szbmssc_seq
       ELSE
        ssbsect_term_code || ssbsect_crn
       END AS section_sis_id, -- used to matched to sis import in canvas 
       scbcrse_title AS course_name,
       ssbsect_subj_code AS subj_code,
       ssbsect_crse_numb AS crse_numb,
       ssbsect_seq_numb AS seq_numb,
       nvl(ssbsect_ptrm_code, '00') AS ptrm_code,
       ssbsect_camp_code AS camp_code,
       ssbsect_insm_code AS insm_code,
       sfrstcr_levl_code AS levl_code,
       scbcrse_coll_code AS coll_code,
       v_instance AS instance,
       trunc(ssbsect_ptrm_start_date) AS start_date,
       trunc(ssbsect_ptrm_end_date + 1) - 1 / (24 * 60 * 60) AS end_date,
       NULL AS base_course,
       sirasgn_pidm AS faculty_pidm,
       CASE
       WHEN szbmssc_crn IS NOT NULL THEN
        szbmssc_term_code || szbmssc_crn || '_' || szbmssc_seq
       ELSE
        NULL
       END AS microsection, -- show null if not microsection
       CASE
       WHEN ssrxlst_crn IS NOT NULL THEN
        'Y'
       ELSE
        'N'
       END AS cross_listed,
       'CDE' AS data_source,
       MOD(sfrstcr_pidm, v_mod) AS PARTITION,
       v_etl_date AS activity_date
  FROM saturn.sfrstcr sfrstcr
  JOIN saturn.stvrsts stvrsts
    ON stvrsts.stvrsts_code = sfrstcr_rsts_code
   AND sfrstcr_rsts_code <> 'AU'
   AND stvrsts_incl_sect_enrl = 'Y'
   AND sfrstcr_term_code = v_term_code
   AND MOD(sfrstcr_pidm, v_mod) = v_partition
  JOIN saturn.spriden
    ON spriden_pidm = sfrstcr_pidm
   AND spriden_change_ind IS NULL
  JOIN saturn.ssbsect
    ON ssbsect_term_code = sfrstcr_term_code
   AND ssbsect_crn = sfrstcr_crn
   AND ssbsect_intg_cde = v_instance
   AND ssbsect_subj_code <> 'NEWS'
  LEFT JOIN saturn.scbcrse
    ON scbcrse_subj_code = ssbsect_subj_code
   AND scbcrse_crse_numb = ssbsect_crse_numb
   AND scbcrse_eff_term = (SELECT MAX(scbcrse2.scbcrse_eff_term)
                             FROM saturn.scbcrse scbcrse2
                            WHERE scbcrse2.scbcrse_subj_code = scbcrse.scbcrse_subj_code
                              AND scbcrse2.scbcrse_crse_numb = scbcrse.scbcrse_crse_numb
                              AND scbcrse2.scbcrse_eff_term <= v_term_code)
  LEFT JOIN saturn.sirasgn
    ON sirasgn_crn = sfrstcr_crn
   AND sirasgn_term_code = sfrstcr_term_code
   AND sirasgn_primary_ind = 'Y'
-- LU cross listed 
  LEFT JOIN saturn.ssrxlst
    ON ssrxlst.ssrxlst_term_code = sfrstcr_term_code
   AND ssrxlst.ssrxlst_crn = sfrstcr_crn
-- LU microsections                           
  LEFT JOIN zsaturn.szbmssc mssc
    ON mssc.szbmssc_term_code = sfrstcr_term_code
   AND mssc.szbmssc_crn = sfrstcr_crn
   AND mssc.szbmssc_seq = (SELECT MAX(sc.szbmssc_seq)
                             FROM zsaturn.szbmssc sc
                            WHERE sc.szbmssc_term_code = mssc.szbmssc_term_code
                              AND sc.szbmssc_crn = mssc.szbmssc_crn);
v_count := SQL%ROWCOUNT;
COMMIT;
IF v_count > 100000 THEN
utl_d_lms.gather_stats('student_enrollments_gtt');
END IF;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || v_term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
ELSIF v_instance = 'ACCAN' THEN
INSERT INTO utl_d_lms.student_enrollments_gtt
(course_code,
 term_code,
 crn,
 pidm,
 luid,
 course_sis_id,
 section_sis_id,
 course_name,
 subj_code,
 crse_numb,
 seq_numb,
 ptrm_code,
 camp_code,
 insm_code,
 levl_code,
 coll_code,
 instance,
 start_date,
 end_date,
 base_course,
 faculty_pidm,
 microsection,
 cross_listed,
 data_source,
 PARTITION,
 activity_date)
SELECT NULL AS course_code, -- fill in downstream with courses table
       sfrstcr_term_code AS term_code,
       sfrstcr_crn AS crn,
       spriden_pidm AS pidm,
       spriden_id AS luid,
       NULL AS course_sis_id, -- fill in downstream with courses table
       nvl(sis.section_sis_id, ssbsect_term_code || ssbsect_crn) AS section_sis_id,
       scbcrse_title AS course_name,
       ssbsect_subj_code AS subj_code,
       ssbsect_crse_numb AS crse_numb,
       ssbsect_seq_numb AS seq_numb,
       CASE
       WHEN areg.crn IS NOT NULL THEN
        '00'
       ELSE
        nvl(ssbsect_ptrm_code, '00')
       END AS ptrm_code,
       ssbsect_camp_code AS camp_code,
       ssbsect_insm_code AS insm_code,
       sfrstcr_levl_code AS levl_code,
       scbcrse_coll_code AS coll_code,
       v_instance AS instance,
       CASE
       WHEN areg.crn IS NOT NULL THEN
        areg.start_date
       ELSE
        trunc(ssbsect_ptrm_start_date)
       END AS start_date,
       CASE
       WHEN areg.crn IS NOT NULL THEN
        trunc(areg.end_date + 1) - 1 / (24 * 60 * 60)
       WHEN ssbsect_subj_code = 'LAN'
            AND ssbsect_crse_numb = '2180' THEN
        trunc((ssbsect_ptrm_start_date + (41 * 7) - 1) + 1) - 1 / (24 * 60 * 60) -- billing hours <> credit hours
       WHEN ssbsect_subj_code = 'LAN'
            AND ssbsect_crse_numb = '2170' THEN
        trunc((ssbsect_ptrm_start_date + (41 * 7) - 1) + 1) - 1 / (24 * 60 * 60) -- billing hours <> credit hours
       WHEN ssbsect_subj_code = 'LAN'
            AND ssbsect_crse_numb IN ('2171', '2172', '2182') THEN
        trunc((ssbsect_ptrm_start_date + (22 * 7) - 1) + 1) - 1 / (24 * 60 * 60) -- billing hours <> credit hours
       WHEN sfrstcr_credit_hr = 0.500 THEN
        trunc((ssbsect_ptrm_start_date + (22 * 7) - 1) + 1) - 1 / (24 * 60 * 60)
       WHEN sfrstcr_credit_hr = 1.000 THEN
        trunc((ssbsect_ptrm_start_date + (41 * 7) - 1) + 1) - 1 / (24 * 60 * 60)
       WHEN sfrstcr_credit_hr = .25 THEN
        trunc((ssbsect_ptrm_start_date + (12 * 7) - 1) + 1) - 1 / (24 * 60 * 60)
       WHEN sfrstcr_credit_hr = 0 THEN
        trunc((ssbsect_ptrm_start_date + (41 * 7) - 1) + 1) - 1 / (24 * 60 * 60)
       ELSE
        trunc(ssbsect_ptrm_end_date + 1) - 1 / (24 * 60 * 60)
       END AS end_date,
       scbsupp.base_course AS base_course,
       sirasgn_pidm AS faculty_pidm,
       NULL AS microsection,
       'N' AS cross_listed,
       'CDE' AS data_source,
       MOD(sfrstcr_pidm, v_mod) AS PARTITION,
       v_etl_date AS activity_date
  FROM saturn.sfrstcr sfrstcr
  JOIN saturn.stvrsts stvrsts
    ON stvrsts.stvrsts_code = sfrstcr_rsts_code
   AND sfrstcr_rsts_code <> 'AU'
   AND stvrsts.stvrsts_incl_sect_enrl = 'Y'
   AND stvrsts.stvrsts_withdraw_ind = 'N'
   AND stvrsts.stvrsts_incl_assess = 'Y'
   AND MOD(sfrstcr_pidm, v_mod) = v_partition
   AND sfrstcr_term_code = v_term_code
  JOIN saturn.spriden
    ON spriden_pidm = sfrstcr_pidm
   AND spriden_change_ind IS NULL
  JOIN saturn.ssbsect
    ON ssbsect_term_code = sfrstcr_term_code
   AND ssbsect_crn = sfrstcr_crn
   AND ssbsect_intg_cde = v_instance
   AND ssbsect_subj_code <> 'NEWS'
  LEFT JOIN saturn.scbcrse
    ON scbcrse_subj_code = ssbsect_subj_code
   AND scbcrse_crse_numb = ssbsect_crse_numb
   AND scbcrse_eff_term = (SELECT MAX(scbcrse2.scbcrse_eff_term)
                             FROM saturn.scbcrse scbcrse2
                            WHERE scbcrse2.scbcrse_subj_code = scbcrse.scbcrse_subj_code
                              AND scbcrse2.scbcrse_crse_numb = scbcrse.scbcrse_crse_numb
                              AND scbcrse2.scbcrse_eff_term <= v_term_code)
  LEFT JOIN saturn.sirasgn
    ON sirasgn_crn = sfrstcr_crn
   AND sirasgn_term_code = sfrstcr_term_code
   AND sirasgn_primary_ind = 'Y'
-- get course sections join to canvas
  LEFT JOIN (SELECT ssbsect_term_code AS term_code,
                    ssbsect_crn AS crn,
                    ssbsect_subj_code || ssbsect_crse_numb || '_' || ssbsect_term_code || '_' || s1.ssrsprt_pars_code || '_' || s2.ssrsprt_pars_code || '_' || ssbsect_crn AS section_sis_id,
                    rank() over(PARTITION BY ssbsect_term_code, ssbsect_crn ORDER BY s1.ssrsprt_activity_date DESC, s1.ssrsprt_pars_code, s2.ssrsprt_pars_code) AS ranking -- there should only be one teacher group per crn, but Banner data is messed up
               FROM saturn.ssbsect
               LEFT JOIN saturn.ssrsprt s1
                 ON s1.ssrsprt_term_code = ssbsect.ssbsect_term_code
                AND s1.ssrsprt_crn = ssbsect.ssbsect_crn
                AND substr(s1.ssrsprt_pars_code, 1, 2) = 'AP'
               LEFT JOIN saturn.ssrsprt s2
                 ON s2.ssrsprt_crn = ssbsect_crn
                AND s2.ssrsprt_term_code = ssbsect_term_code
                AND substr(s2.ssrsprt_pars_code, 1, 4) = 'ACTG'
              WHERE ssbsect.ssbsect_term_code < '202338' -- only need this if it is before open learning
                AND ssbsect.ssbsect_term_code = v_term_code) sis
    ON sis.term_code = sfrstcr_term_code
   AND sis.crn = sfrstcr_crn
   AND sis.ranking = 1
-- luoa start and end dates 
  LEFT JOIN (SELECT areg.sfrareg_term_code AS term_code,
                    areg.sfrareg_crn AS crn,
                    areg.sfrareg_pidm AS pidm,
                    MAX(areg.sfrareg_start_date) keep(dense_rank FIRST ORDER BY areg.sfrareg_extension_number) AS start_date, -- yes MAX, we want the MAX
                    MAX(areg.sfrareg_completion_date) keep(dense_rank FIRST ORDER BY areg.sfrareg_extension_number DESC) AS end_date
               FROM saturn.sfrareg areg
              WHERE (areg.sfrareg_term_code IN ('201440') OR areg.sfrareg_term_code >= '202338') -- DO NOT REMOVE HARD CODED VALUES
                AND areg.sfrareg_term_code = v_term_code
                AND MOD(areg.sfrareg_pidm, v_mod) = v_partition
              GROUP BY areg.sfrareg_term_code,
                       areg.sfrareg_crn,
                       areg.sfrareg_pidm) areg
    ON areg.term_code = sfrstcr_term_code
   AND areg.crn = sfrstcr_crn
   AND areg.pidm = sfrstcr_pidm
-- luoa base course 
  LEFT JOIN (SELECT scbsupp.scbsupp_subj_code,
                    scbsupp.scbsupp_crse_numb,
                    scbsupp.scbsupp_perm_dist_ind AS base_course,
                    rank() over(PARTITION BY scbsupp.scbsupp_subj_code, scbsupp.scbsupp_crse_numb ORDER BY scbsupp.scbsupp_eff_term DESC, rownum) ranking
               FROM saturn.scbsupp
              WHERE scbsupp.scbsupp_eff_term <= v_term_code) scbsupp
    ON scbsupp.scbsupp_subj_code = ssbsect_subj_code
   AND scbsupp.scbsupp_crse_numb = ssbsect_crse_numb
   AND scbsupp.ranking = 1;
v_count := SQL%ROWCOUNT;
COMMIT;
IF v_count > 100000 THEN
utl_d_lms.gather_stats('student_enrollments_gtt');
END IF;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || v_term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
END IF; -- if instance 
-- Retry mechanism for handling deadlocks
LOOP
BEGIN
MERGE /*+ LEADING(src) USE_NL(tgt) INDEX(tgt STUDENT_ENROLLMENTS_IDX1) */
INTO utl_d_lms.student_enrollments tgt
USING (SELECT src.course_code,
              src.term_code,
              src.crn,
              src.pidm,
              src.luid,
              src.course_sis_id,
              src.section_sis_id,
              src.course_id,
              src.course_section_id,
              src.user_id,
              src.enrollment_id,
              src.role_id,
              src.course_name,
              src.subj_code,
              src.crse_numb,
              src.seq_numb,
              src.ptrm_code,
              src.camp_code,
              src.insm_code,
              src.levl_code,
              src.coll_code,
              src.created_date,
              src.updated_date,
              src.last_request,
              src.workflow_state,
              src.type,
              src.instance,
              src.start_date,
              src.end_date,
              src.partition,
              src.base_course,
              src.faculty_pidm,
              src.microsection,
              src.cross_listed,
              src.data_source,
              src.activity_date,
              src.row_hash
         FROM (SELECT nvl(gtt.course_code, c.course_code) AS course_code,
                      gtt.term_code,
                      gtt.crn,
                      gtt.pidm,
                      gtt.luid,
                      nvl(gtt.course_sis_id, c.sis_source_id) AS course_sis_id,
                      nvl(gtt.section_sis_id, cs.sis_source_id) AS section_sis_id,
                      c.id AS course_id,
                      cs.id AS course_section_id,
                      p.user_id AS user_id,
                      e.id AS enrollment_id,
                      e.role_id,
                      gtt.course_name,
                      gtt.subj_code,
                      gtt.crse_numb,
                      gtt.seq_numb,
                      gtt.ptrm_code,
                      gtt.camp_code,
                      gtt.insm_code,
                      gtt.levl_code,
                      gtt.coll_code,
                      e.created_at AS created_date,
                      e.updated_at AS updated_date,
                      p.last_request_at AS last_request,
                      e.workflow_state,
                      e.type,
                      gtt.instance,
                      gtt.start_date,
                      gtt.end_date,
                      gtt.partition,
                      gtt.base_course,
                      gtt.faculty_pidm,
                      gtt.microsection,
                      gtt.cross_listed,
                      gtt.data_source,
                      gtt.activity_date,
                      standard_hash(nvl(to_char(nvl(gtt.course_code, c.course_code)), '<NULL>') || '#' || nvl(to_char(gtt.term_code), '<NULL>') || '#' || nvl(to_char(gtt.crn), '<NULL>') || '#' || nvl(to_char(gtt.pidm), '<NULL>') || '#' ||
                                    nvl(to_char(gtt.luid), '<NULL>') || '#' || nvl(to_char(nvl(gtt.course_sis_id, c.sis_source_id)), '<NULL>') || '#' || nvl(to_char(nvl(gtt.section_sis_id, cs.sis_source_id)), '<NULL>') || '#' ||
                                    nvl(to_char(c.id), '<NULL>') || '#' || nvl(to_char(cs.id), '<NULL>') || '#' || nvl(to_char(p.user_id), '<NULL>') || '#' || nvl(to_char(e.id), '<NULL>') || '#' || nvl(to_char(e.role_id), '<NULL>') || '#' ||
                                    nvl(to_char(gtt.course_name), '<NULL>') || '#' || nvl(to_char(gtt.subj_code), '<NULL>') || '#' || nvl(to_char(gtt.crse_numb), '<NULL>') || '#' || nvl(to_char(gtt.seq_numb), '<NULL>') || '#' ||
                                    nvl(to_char(gtt.ptrm_code), '<NULL>') || '#' || nvl(to_char(gtt.camp_code), '<NULL>') || '#' || nvl(to_char(gtt.insm_code), '<NULL>') || '#' || nvl(to_char(gtt.levl_code), '<NULL>') || '#' ||
                                    nvl(to_char(gtt.coll_code), '<NULL>') || '#' || nvl(to_char(e.created_at, 'YYYYMMDDHH24MISS'), '<NULL>') || '#' || nvl(to_char(e.updated_at, 'YYYYMMDDHH24MISS'), '<NULL>') || '#' ||
                                    nvl(to_char(p.last_request_at, 'YYYYMMDDHH24MISS'), '<NULL>') || '#' || nvl(to_char(e.workflow_state), '<NULL>') || '#' || nvl(to_char(e.type), '<NULL>') || '#' || nvl(to_char(gtt.instance), '<NULL>') || '#' ||
                                    nvl(to_char(gtt.start_date, 'YYYYMMDD'), '<NULL>') || '#' || nvl(to_char(gtt.end_date, 'YYYYMMDD'), '<NULL>') || '#' || nvl(to_char(gtt.partition), '<NULL>') || '#' ||
                                    nvl(to_char(gtt.base_course), '<NULL>') || '#' || nvl(to_char(gtt.faculty_pidm), '<NULL>') || '#' || nvl(to_char(gtt.microsection), '<NULL>') || '#' || nvl(to_char(gtt.cross_listed), '<NULL>') || '#' ||
                                    nvl(to_char(gtt.data_source), '<NULL>'), 'MD5') AS row_hash
                 FROM utl_d_lms.student_enrollments_gtt gtt
                 LEFT JOIN zcanvas_data.course_sections cs
                   ON cs.instance = gtt.instance
                  AND cs.sis_source_id = gtt.section_sis_id -- banner <-> canvas course connection
                  AND cs.workflow_state NOT IN ('deleted', 'unpublished')
                 LEFT JOIN zcanvas_data.pseudonyms p
                   ON p.instance = gtt.instance
                  AND p.sis_user_id = gtt.luid -- banner <-> canvas student connection
                  AND length(p.unique_id) <= 30 -- remove any test or temp users that get a hash from impersonate
                  AND p.workflow_state <> 'deleted'
                 LEFT JOIN zcanvas_data.enrollments e
                   ON e.instance = gtt.instance
                  AND e.course_section_id = cs.id
                  AND e.user_id = p.user_id
                  AND e.type = 'StudentEnrollment'
                  AND e.workflow_state NOT IN ('deleted', 'rejected')
                 LEFT JOIN zcanvas_data.courses c
                   ON c.instance = gtt.instance
                  AND c.id = cs.course_id
                  AND c.workflow_state <> 'deleted'
                WHERE gtt.partition = v_partition -- ensure we get the same student records 
                  AND gtt.instance = v_instance
                  AND gtt.term_code = v_term_code) src
         LEFT JOIN utl_d_lms.student_enrollments tgt
           ON tgt.term_code = src.term_code
          AND tgt.crn = src.crn
          AND tgt.pidm = src.pidm
        WHERE 1 = 1
             -- <- new record, change record -> --
          AND ((src.row_hash <> tgt.row_hash) OR tgt.row_hash IS NULL)) src
ON (tgt.term_code = src.term_code AND tgt.crn = src.crn AND tgt.pidm = src.pidm)
WHEN MATCHED THEN
UPDATE
   SET tgt.course_id         = src.course_id,
       tgt.course_section_id = src.course_section_id,
       tgt.instance          = src.instance,
       tgt.user_id           = src.user_id,
       tgt.enrollment_id     = src.enrollment_id,
       tgt.luid              = src.luid,
       tgt.role_id           = src.role_id,
       tgt.course_code       = src.course_code,
       tgt.course_sis_id     = src.course_sis_id,
       tgt.section_sis_id    = src.section_sis_id,
       tgt.course_name       = src.course_name,
       tgt.subj_code         = src.subj_code,
       tgt.crse_numb         = src.crse_numb,
       tgt.seq_numb          = src.seq_numb,
       tgt.ptrm_code         = src.ptrm_code,
       tgt.camp_code         = src.camp_code,
       tgt.insm_code         = src.insm_code,
       tgt.levl_code         = src.levl_code,
       tgt.coll_code         = src.coll_code,
       tgt.created_date      = src.created_date,
       tgt.updated_date      = src.updated_date,
       tgt.last_request      = src.last_request,
       tgt.workflow_state    = src.workflow_state,
       tgt.type              = src.type,
       tgt.start_date        = src.start_date,
       tgt.end_date          = src.end_date,
       tgt.partition         = src.partition,
       tgt.base_course       = src.base_course,
       tgt.faculty_pidm      = src.faculty_pidm,
       tgt.microsection      = src.microsection,
       tgt.cross_listed      = src.cross_listed,
       tgt.data_source       = src.data_source,
       tgt.activity_date     = src.activity_date,
       tgt.row_hash          = src.row_hash
WHEN NOT MATCHED THEN
INSERT
(course_code,
 term_code,
 crn,
 pidm,
 luid,
 course_sis_id,
 section_sis_id,
 course_id,
 course_section_id,
 user_id,
 enrollment_id,
 role_id,
 course_name,
 subj_code,
 crse_numb,
 seq_numb,
 ptrm_code,
 camp_code,
 insm_code,
 levl_code,
 coll_code,
 created_date,
 updated_date,
 last_request,
 workflow_state,
 TYPE,
 instance,
 start_date,
 end_date,
 PARTITION,
 base_course,
 faculty_pidm,
 microsection,
 cross_listed,
 data_source,
 activity_date,
 row_hash)
VALUES
(src.course_code,
 src.term_code,
 src.crn,
 src.pidm,
 src.luid,
 src.course_sis_id,
 src.section_sis_id,
 src.course_id,
 src.course_section_id,
 src.user_id,
 src.enrollment_id,
 src.role_id,
 src.course_name,
 src.subj_code,
 src.crse_numb,
 src.seq_numb,
 src.ptrm_code,
 src.camp_code,
 src.insm_code,
 src.levl_code,
 src.coll_code,
 src.created_date,
 src.updated_date,
 src.last_request,
 src.workflow_state,
 src.type,
 src.instance,
 src.start_date,
 src.end_date,
 src.partition,
 src.base_course,
 src.faculty_pidm,
 src.microsection,
 src.cross_listed,
 src.data_source,
 src.activity_date,
 src.row_hash);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || v_term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- only run deletes if the 0 partition is running bc we are searching for all students no matter the partition here to avoid any fragmenting / orphan records
IF v_partition = 0 THEN
-- remove courses that no longer exists on the banner side from all instances
DELETE FROM utl_d_lms.student_enrollments se
 WHERE se.instance <> 'BLACKBOARD' -- never remove blackboard 
   AND se.instance = v_instance
   AND se.term_code = v_term_code
   AND se.term_code NOT IN ('000000') -- do not get non term courses 
   AND NOT EXISTS (SELECT 1
          FROM saturn.sfrstcr sfrstcr
          JOIN saturn.stvrsts stvrsts
            ON stvrsts.stvrsts_code = sfrstcr_rsts_code
           AND sfrstcr_rsts_code <> 'AU'
           AND stvrsts.stvrsts_incl_sect_enrl = 'Y'
           AND sfrstcr_term_code = v_term_code
          JOIN saturn.spriden
            ON spriden_pidm = sfrstcr_pidm
           AND spriden_change_ind IS NULL
          JOIN saturn.ssbsect
            ON ssbsect_term_code = sfrstcr_term_code
           AND ssbsect_crn = sfrstcr_crn
           AND ssbsect_intg_cde = v_instance
           AND ssbsect_subj_code <> 'NEWS'
         WHERE se.term_code = sfrstcr_term_code
           AND se.crn = sfrstcr_crn
           AND se.pidm = sfrstcr_pidm);
v_count := SQL%ROWCOUNT;
COMMIT;
-- Remove the old(er) course section that has a new microsection; we need to delete the base course because it is staying "active" even after the student gets added to the new microsection (new course section id) 
-- I do not think it should work this way, IMO, but it does
-- By deleting this old(er) course section, it will fix any downstream duplication on all the rest of the LMS tables
DELETE FROM utl_d_lms.student_enrollments se
 WHERE se.instance = 'L2CAN' --HARD-CODED: leave it so we do not delete from ACCAN
   AND se.instance = v_instance
   AND se.term_code = v_term_code
   AND se.term_code NOT IN ('000000') -- do not get non term courses  
   AND se.microsection IS NULL -- get row that does NOT have microsection label
   AND EXISTS (SELECT 1
          FROM utl_d_lms.student_enrollments e
         WHERE e.term_code = se.term_code
           AND e.crn = se.crn
           AND e.pidm = se.pidm
           AND e.microsection IS NOT NULL); -- get row that has microsection label
v_count := v_count + SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'DELETE - ' || v_term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
END IF;
EXIT; -- If successful, exit the retry loop
EXCEPTION
WHEN OTHERS THEN
IF SQLCODE = -60 THEN
-- Deadlock detected
v_retry_count := v_retry_count + 1;
IF v_retry_count > v_max_retries THEN
-- Log error for max retries
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := '!!!-00060: deadlock detected while waiting for resource. Max retries exceeded after ' || (v_max_retries * v_wait_time) || ' seconds';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
EXIT; -- Add EXIT here to break out of the loop when max retries exceeded
ELSE
-- Log retry attempt
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'Deadlock detected while waiting for resource - waiting ' || v_wait_time || ' seconds for retry attempt number ' || v_retry_count;
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'WARNING', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
dbms_lock.sleep(v_wait_time); -- Wait between retries; short wait because it will need to cycle through all the GTTs again
CONTINUE; -- Add CONTINUE to explicitly indicate loop continuation
END IF;
ELSE
-- Other errors
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
EXIT; -- Add EXIT here to break out of the loop for non-deadlock errors
END IF;
END;
END LOOP; -- end deadlock detection 
ELSIF v_term_code IN ('000000') THEN
-- CANVAS NON-TERM
MERGE INTO utl_d_lms.student_enrollments tgt
USING (SELECT src.course_code,
              src.term_code,
              src.crn,
              src.pidm,
              src.luid,
              src.course_sis_id,
              src.section_sis_id,
              src.course_id,
              src.course_section_id,
              src.user_id,
              src.enrollment_id,
              src.role_id,
              src.course_name,
              src.subj_code,
              src.crse_numb,
              src.seq_numb,
              src.ptrm_code,
              src.camp_code,
              src.insm_code,
              src.levl_code,
              src.coll_code,
              src.created_date,
              src.updated_date,
              src.last_request,
              src.workflow_state,
              src.type,
              src.instance,
              src.start_date,
              src.end_date,
              src.partition,
              src.base_course,
              src.faculty_pidm,
              src.microsection,
              src.cross_listed,
              src.data_source,
              src.activity_date,
              src.row_hash
         FROM (SELECT c.course_code AS course_code,
                      v_term_code AS term_code, -- always '000000' to avoid the NOT NULL on the table
                      lpad(substr(to_char(cs.id), 1, 9), 9, '0') AS crn, -- pad zeros to the course section id to avoid the NOT NULL on the table
                      0 - e.user_id AS pidm, -- make negative number using the userid to avoid the NOT NULL on the table
                      CASE
                      WHEN substr(p.sis_user_id, 1, 1) = 'L' -- must be a valid LUID
                           AND p.sis_user_id IS NOT NULL THEN
                       p.sis_user_id
                      ELSE
                       NULL
                      END AS luid, -- LUID - will only populate if there has been a banner enrollment at some point
                      coalesce(c.sis_source_id, v_term_code || lpad(substr(to_char(cs.id), 1, 9), 9, '0')) AS course_sis_id,
                      coalesce(cs.sis_source_id, v_term_code || lpad(substr(to_char(cs.id), 1, 9), 9, '0')) AS section_sis_id,
                      c.id AS course_id,
                      cs.id AS course_section_id, -- always use this to join between canvas only data; NOT term/crn/pidm
                      p.user_id AS user_id, -- always use this to join between canvas only data; NOT term/crn/pidm
                      e.id AS enrollment_id,
                      e.role_id,
                      c.name AS course_name,
                      NULL AS subj_code,
                      NULL AS crse_numb,
                      NULL AS seq_numb,
                      '00' AS ptrm_code,
                      NULL AS camp_code,
                      NULL AS insm_code,
                      NULL AS levl_code,
                      NULL AS coll_code,
                      e.created_at AS created_date,
                      e.updated_at AS updated_date,
                      p.last_request_at AS last_request,
                      e.workflow_state,
                      e.type,
                      v_instance AS instance,
                      trunc(CAST(coalesce(cs.start_at, cs.end_at - 365, cs.created_at) AS DATE)) AS start_date,
                      trunc((CAST(coalesce(cs.end_at, cs.start_at + 365, cs.created_at + 365) AS DATE)) + 1) - 1 / (24 * 60 * 60) AS end_date,
                      nvl(MOD(p.user_id, v_mod), 0) AS PARTITION, -- for consistency across all LMS tables, the partition field will always use the p.user_id
                      NULL AS base_course,
                      NULL AS faculty_pidm,
                      NULL AS microsection,
                      NULL AS cross_listed,
                      'CDE' AS data_source,
                      v_etl_date AS activity_date,
                      standard_hash(nvl(to_char(c.course_code), '<NULL>') || '#' || nvl(to_char(v_term_code), '<NULL>') || '#' || nvl(to_char(lpad(substr(to_char(cs.id), 1, 9), 9, '0')), '<NULL>') || '#' ||
                                    nvl(to_char(0 - e.user_id), '<NULL>') || '#' || nvl(to_char(CASE
                                                                                                WHEN substr(p.sis_user_id, 1, 1) = 'L'
                                                                                                     AND p.sis_user_id IS NOT NULL THEN
                                                                                                 p.sis_user_id
                                                                                                ELSE
                                                                                                 NULL
                                                                                                END), '<NULL>') || '#' || nvl(to_char(coalesce(c.sis_source_id, v_term_code || lpad(substr(to_char(cs.id), 1, 9), 9, '0'))), '<NULL>') || '#' ||
                                    nvl(to_char(coalesce(cs.sis_source_id, v_term_code || lpad(substr(to_char(cs.id), 1, 9), 9, '0'))), '<NULL>') || '#' || nvl(to_char(c.id), '<NULL>') || '#' || nvl(to_char(cs.id), '<NULL>') || '#' ||
                                    nvl(to_char(p.user_id), '<NULL>') || '#' || nvl(to_char(e.id), '<NULL>') || '#' || nvl(to_char(e.role_id), '<NULL>') || '#' || nvl(to_char(c.name), '<NULL>') || '#' ||
                                    nvl(to_char(e.created_at, 'YYYYMMDDHH24MISS'), '<NULL>') || '#' || nvl(to_char(e.updated_at, 'YYYYMMDDHH24MISS'), '<NULL>') || '#' || nvl(to_char(p.last_request_at, 'YYYYMMDDHH24MISS'), '<NULL>') || '#' ||
                                    nvl(to_char(e.workflow_state), '<NULL>') || '#' || nvl(to_char(e.type), '<NULL>') || '#' || nvl(to_char(v_instance), '<NULL>') || '#' ||
                                    nvl(to_char(trunc(CAST(coalesce(cs.start_at, cs.end_at - 365, cs.created_at) AS DATE)), 'YYYYMMDD'), '<NULL>') || '#' ||
                                    nvl(to_char(trunc((CAST(coalesce(cs.end_at, cs.start_at + 365, cs.created_at + 365) AS DATE)) + 1) - 1 / (24 * 60 * 60), 'YYYYMMDD'), '<NULL>') || '#' ||
                                    nvl(to_char(nvl(MOD(p.user_id, v_mod), 0)), '<NULL>'), 'MD5') AS row_hash,
                      rank() over(PARTITION BY e.instance, cs.id, p.user_id ORDER BY p.last_login_at DESC, e.updated_at DESC, p.updated_at DESC, rownum) ranking --to remedy DUP_PIDM or multiple enrollments
                 FROM zcanvas_data.courses c
                 JOIN zcanvas_data.course_sections cs
                   ON cs.instance = c.instance
                  AND cs.course_id = c.id
                  AND cs.workflow_state NOT IN ('deleted', 'unpublished')
                  AND cs.instance = v_instance
                  AND cs.sis_source_id IS NULL -- how to determine this is a non-term course
                 JOIN zcanvas_data.enrollments e
                   ON e.instance = c.instance
                  AND e.course_section_id = cs.id
                  AND e.type = 'StudentEnrollment'
                  AND e.workflow_state <> 'deleted'
                 JOIN zcanvas_data.pseudonyms p
                   ON p.instance = c.instance
                  AND p.user_id = e.user_id
                  AND length(p.unique_id) <= 30
                  AND p.workflow_state <> 'deleted'
                  AND nvl(MOD(p.user_id, v_mod), 0) = v_partition -- need nvl here because students may not have a user_id yet
                 JOIN zcanvas_data.accounts acc -- join to accounts to validate user
                   ON acc.instance = c.instance
                  AND acc.id = c.account_id
                  AND (lower(acc.name) NOT LIKE '%sandbox%' OR --
                      lower(acc.name) NOT LIKE '%curriculum%' OR --
                      lower(acc.name) NOT LIKE '%staging%' OR --
                      lower(acc.name) NOT LIKE '%archive%' OR -- 
                      lower(acc.name) NOT LIKE '%manually%')) src
         LEFT JOIN utl_d_lms.student_enrollments tgt
           ON tgt.term_code = src.term_code
          AND tgt.crn = src.crn
          AND tgt.pidm = src.pidm
        WHERE src.ranking = 1
             -- <- new record, change record -> --
          AND ((src.row_hash <> tgt.row_hash) OR tgt.row_hash IS NULL)) src
ON (tgt.term_code = src.term_code AND tgt.crn = src.crn AND tgt.pidm = src.pidm)
WHEN MATCHED THEN
UPDATE
   SET tgt.course_id         = src.course_id,
       tgt.course_section_id = src.course_section_id,
       tgt.instance          = src.instance,
       tgt.user_id           = src.user_id,
       tgt.enrollment_id     = src.enrollment_id,
       tgt.luid              = src.luid,
       tgt.role_id           = src.role_id,
       tgt.course_code       = src.course_code,
       tgt.course_sis_id     = src.course_sis_id,
       tgt.section_sis_id    = src.section_sis_id,
       tgt.course_name       = src.course_name,
       tgt.subj_code         = src.subj_code,
       tgt.crse_numb         = src.crse_numb,
       tgt.seq_numb          = src.seq_numb,
       tgt.ptrm_code         = src.ptrm_code,
       tgt.camp_code         = src.camp_code,
       tgt.insm_code         = src.insm_code,
       tgt.levl_code         = src.levl_code,
       tgt.coll_code         = src.coll_code,
       tgt.created_date      = src.created_date,
       tgt.updated_date      = src.updated_date,
       tgt.last_request      = src.last_request,
       tgt.workflow_state    = src.workflow_state,
       tgt.type              = src.type,
       tgt.start_date        = src.start_date,
       tgt.end_date          = src.end_date,
       tgt.partition         = src.partition,
       tgt.base_course       = src.base_course,
       tgt.faculty_pidm      = src.faculty_pidm,
       tgt.microsection      = src.microsection,
       tgt.cross_listed      = src.cross_listed,
       tgt.data_source       = src.data_source,
       tgt.activity_date     = src.activity_date,
       tgt.row_hash          = src.row_hash
WHEN NOT MATCHED THEN
INSERT
(course_code,
 term_code,
 crn,
 pidm,
 luid,
 course_sis_id,
 section_sis_id,
 course_id,
 course_section_id,
 user_id,
 enrollment_id,
 role_id,
 course_name,
 subj_code,
 crse_numb,
 seq_numb,
 ptrm_code,
 camp_code,
 insm_code,
 levl_code,
 coll_code,
 created_date,
 updated_date,
 last_request,
 workflow_state,
 TYPE,
 instance,
 start_date,
 end_date,
 PARTITION,
 base_course,
 faculty_pidm,
 microsection,
 cross_listed,
 data_source,
 activity_date,
 row_hash)
VALUES
(src.course_code,
 src.term_code,
 src.crn,
 src.pidm,
 src.luid,
 src.course_sis_id,
 src.section_sis_id,
 src.course_id,
 src.course_section_id,
 src.user_id,
 src.enrollment_id,
 src.role_id,
 src.course_name,
 src.subj_code,
 src.crse_numb,
 src.seq_numb,
 src.ptrm_code,
 src.camp_code,
 src.insm_code,
 src.levl_code,
 src.coll_code,
 src.created_date,
 src.updated_date,
 src.last_request,
 src.workflow_state,
 src.type,
 src.instance,
 src.start_date,
 src.end_date,
 src.partition,
 src.base_course,
 src.faculty_pidm,
 src.microsection,
 src.cross_listed,
 src.data_source,
 src.activity_date,
 src.row_hash);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || v_term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- only run deletes if the 0 partition is running bc we are searching for all students no matter the partition here to avoid any fragmenting / orphan records
IF v_partition = 0 THEN
DELETE FROM utl_d_lms.student_enrollments se
 WHERE se.instance = 'L2CAN' --HARD-CODED: 
   AND se.instance = v_instance
   AND se.term_code IN ('000000') -- get non term courses only
   AND EXISTS (SELECT 1
          FROM zcanvas_data.enrollments e
         WHERE e.instance = se.instance
           AND e.id = se.enrollment_id -- we need to join on enrollment ID here for NON-TERM
           AND e.workflow_state = 'deleted');
v_count       := SQL%ROWCOUNT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'DELETE - ' || v_term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
END IF; -- if then delete 
END IF; -- if then term_code
-- CLEAR GTTs on each successful loop
utl_d_lms.truncate_table(v_table_name => 'student_enrollments_gtt');
dbms_output.put_line(' --------- ');
END LOOP; -- c_terms
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
-- log any errors
EXCEPTION
WHEN OTHERS THEN
-- CLEAR GTTs on error 
utl_d_lms.truncate_table(v_table_name => 'student_enrollments_gtt');
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
END etl_lms_student_enrollments;

procedure etl_lms_last_activity(jobnumber number, processid varchar2, processname varchar2, inst varchar2, nmbr number) is
-- =============================================================================
-- PURPOSE: Populate and maintain LMS last-activity records (detail and pivot) by loading enrollment-driven activity data and merging calculated activity types for each term/instance.
--
-- TARGET(S): utl_d_lms.last_activity_gtt, utl_d_lms.last_activity, utl_d_lms.last_activity_pivot
--
-- UNIQUE KEY / INDEX:
-- - utl_d_lms.last_activity: (term_code, crn, pidm, type)
-- - utl_d_lms.last_activity_pivot: (term_code, crn, pidm)
-- - utl_d_lms.last_activity_gtt: staging/gtt table keyed by (term_code, crn, pidm, partition, instance) for processing
--
-- BUSINESS LOGIC & CONDITIONS:
-- - Processing strategy:
--   - Determines a job_id and runs for a set of terms from zbtm.terms_by_group_v using three UNIONed sections: (1) "current terms" run during early hours (00-08) for select instances/group codes; (2) "non-current terms" run during evening hours (18-23) for a wider term window; (3) a non-banner synthetic term ('000000') for non-term instances (only when v_instance = 'L2CAN') during evening hours.
--   - Iterates term-by-term (FOR rec IN c_terms) and for each term:
--     - Loads a GTT (utl_d_lms.last_activity_gtt) with enrollments filtered by instance, term_code and partition.
--     - Aggregates max grade_date per (term_code, crn, pidm) from utl_d_aim.szrcrse and attaches it to GTT rows.
--     - After populating the GTT, computes multiple "activity type" values and merges them into the persistent last_activity table.
--     - Builds a pivoted view/summary from last_activity joined back to the GTT and merges into last_activity_pivot to produce per-enrollment consolidated last_activity and end_date / start_date columns.
-- - GTT population:
--   - Selects from utl_d_lms.student_enrollments for the configured instance/term/partition, materializes the filtered set, and left-joins precomputed course-level MAX(grade_date) by term/crn/pidm.
--   - Uses INSERT /*+ APPEND */ into the GTT to stage rows for subsequent merges.
-- - last_activity merges (per instance variations):
--   - start_date / end_date types:
--     - For each GTT row emits two rows (TYPE = 'start_date' and TYPE = 'end_date').
--     - Status = 'active' when grade_date IS NULL, otherwise 'expired'.
--     - Includes rows only when key attributes differ between GTT and existing last_activity (pidm presence, course_section_id, user_id) OR when the existing max_date equals the incoming date condition (coalesce comparisons used).
--     - start_date uses gtt.start_date as max_date; end_date uses gtt.end_date.
--   - last_submission type:
--     - For assignments joined to student_enrollments, considers either submitted_date OR graded_date when graded score > 0.
--     - Computes MAX(trunc(coalesce(submitted_date, graded_date) + 1) - 1/(24*60*60)) to effectively include the 11:59:59 PM of that date (i.e., treat the date as end-of-day).
--     - Only includes assignments with submitted_date IS NOT NULL OR graded_date IS NOT NULL and coalesce(score,0) > 0 for graded rows.
--     - Produces TYPE = 'last_submission' with status 'active' if grade_date IS NULL else 'expired'.
--   - last_submission_due_date type:
--     - Identifies students who regularly turn in assignments early by computing:
--         - AVG(days early) > 7 (average difference between due_date and submitted_date/graded_date when submitted earlier)
--         - AND MAX(due_date for early submissions) > v_etl_date (a future due date exists)
--     - Only considers assignments with a non-null due_date.
--     - Emits TYPE = 'last_submission_due_date' with status based on grade_date nullness and MAX(due_date) as max_date (end-of-day semantics).
--   - af_holds type:
--     - Joins GTT to saturn.sprhold for sprhold_hldd_code IN ('AF').
--     - Uses the most recent sprhold_to_date (rank() OVER (PARTITION BY term_code, crn, pidm ORDER BY sprhold_to_date DESC, rownum)).
--     - Status = 'active' when v_etl_date <= sprhold_to_date, else 'expired'.
--     - Stores trunc(sprhold_to_date + 1) - 1/(24*60*60) to represent end-of-day expiration.
--   - luoa_at_risk_exemptions type:
--     - Joins GTT to zformdata.zfrlist where upper(zfrlist_char_01) = gtt.luid and list_code = 'luoa_at_risk_exemptions'.
--     - Uses zfrlist_date_02 to determine exemption end; status active when v_etl_date <= zfrlist_date_02.
--     - Selects most recent exemption per user/course using RANK and uses that zfrlist_date_02 as max_date (end-of-day adjustments applied).
--   - For all types merged into last_activity:
--     - Merge predicate matches on term_code, crn, pidm, type.
--     - If a matched row is found, updates status, course_section_id, user_id, max_date and sets activity_date to the ETL run timestamp.
--     - If not matched, inserts a new last_activity row with the computed values.
-- - last_activity_pivot assembly:
--   - Aggregates last_activity rows joined to the GTT for the current instance/term/partition and computes one-row-per (term_code, crn, pidm) with:
--     - last_activity: MAX of selected types depending on instance (ACCAN uses most types except 'end_date'; L2CAN uses only 'start_date' and 'last_submission' for last_activity).
--     - end_date: MAX of types that can change the end_date (instance-specific list).
--     - start_date, default_end_date, af_holds, fn_grade_appeal, last_submission, last_submission_due_date, luoa_at_risk_exemptions, luoa_extensions taken as MAX(CASE WHEN type = '...' THEN max_date END).
--   - Wraps course_section_id with MAX() to avoid multi-row insert scenarios when consolidating.
--   - Merges aggregated pivot rows into utl_d_lms.last_activity_pivot keyed by term_code, crn, pidm; updates pivot columns and activity_date on change, or inserts when not present.
-- - GTT lifecycle:
--   - The GTT (utl_d_lms.last_activity_gtt) is cleared (ads_etl.clear_table) after each successful term loop and also on exceptions to prevent leftover GTT rows between term iterations.
-- - Cleanup step (targeted delete):
--   - Optionally removes records from utl_d_lms.last_activity and utl_d_lms.last_activity_pivot that no longer have matching enrollments in utl_d_lms.student_enrollments (exists check).
--   - This cleanup runs only during specific off-peak windows: when to_char(v_etl_date,'D') IN ('4'), current hour between '18' and '23', and only when v_partition = 0 (intended as a single-threaded cleanup).
--
-- DEPENDENCIES:
-- - Schemas/tables/views:
--   - zbtm.terms_by_group_v (term selection)
--   - utl_d_lms.student_enrollments (source enrollments)
--   - utl_d_aim.szrcrse (grade_date aggregation)
--   - utl_d_lms.student_assignments (assignment submissions and grades)
--   - utl_d_lms.last_activity_gtt (global temporary staging table)
--   - utl_d_lms.last_activity (detail activity table)
--   - utl_d_lms.last_activity_pivot (consolidated/pivoted activity summary)
--   - saturn.sprhold (financial hold data)
--   - zformdata.zfrlist (LUOA exemption forms)
-- - PL/SQL package/functions:
--   - ads_etl.set_parallel_session(p_enabled, p_degree, p_mode)
--   - ads_etl.insert_job_log(...)
--   - ads_etl.clear_table(v_schema, v_table)
-- - Oracle features / hints used:
--   - Parallel DML session control, /*+ APPEND */, /*+ MATERIALIZE */, /*+ USE_HASH(...) LEADING(...) */, analytic function RANK(), aggregate functions and date arithmetic.
--
-- CONSTRAINTS & RISKS:
-- - Scheduling constraints:
--   - Many operations are gated to run only during off-peak hours (00-08 and 18-23) and certain day-of-week checks; running outside these windows may impact production performance.
-- - High resource usage:
--   - INSERT /*+ APPEND */ and large MERGE operations (with parallel session enabled) can generate significant temporary space, redo, and undo; risk of long-running transactions and heavy I/O.
-- - Locking / concurrency:
--   - The processing updates/merges large target tables and may encounter deadlocks or resource waits under concurrent activity; the procedure's design assumes occasional retries for such conflicts.
-- - Data correctness assumptions:
--   - Logic depends on consistent matching keys between GTT rows, last_activity, enrollments, assignments, and external systems (PIDM, CRN, term_code). Mismatched or missing PIDM/IDs can cause duplicate/extra rows or skipped merges.
--   - Use of coalesce comparisons (e.g., coalesce(max_date, v_etl_date) = incoming_date) relies on v_etl_date as a neutral default and may mask true null-vs-value differences in certain edge cases.
-- - Ranking and row selection:
--   - RANK() with ORDER BY sprhold_to_date DESC, rownum is used to pick the most recent row; relying on rownum for deterministic tie-breaking can be non-deterministic if multiple identical dates exist.
-- - Date math semantics:
--   - Several expressions attempt to add end-of-day semantics (trunc(... + 1) - 1/(24*60*60)). This relies on fractional-second math and may be brittle or confusing; timezone or session NLS settings could affect behavior.
-- - GTT handling:
--   - Clearing/truncating the GTT between terms is essential; failure to clear may cause incorrect merges for subsequent terms.
-- - Locale / NLS settings:
--   - to_char(v_etl_date,'D') depends on NLS_TERRITORY for day-number mapping; it may yield unexpected values across databases with different NLS settings and thus skip or erroneously run cleanup.
-- - Hard-coded defaults:
--   - v_instance is defaulted to 'ACCAN' and v_partition = 0; callers must set these appropriately if other instances/partitions are intended.
-- - External package risk:
--   - Relies on ads_etl package for parallel control, job logging, and table clearing; if ads_etl behaves unexpectedly the ETL may not be controllable or logged properly.
-- =============================================================================
-- DECLARE
v_etl_date    DATE := SYSDATE;
v_msg         VARCHAR2(2000);
v_instance    VARCHAR2(50) := upper(inst); -- inst from the jams job; used for determining instance
v_partition    NUMBER := nmbr; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_lms_last_activity';
v_retry_count NUMBER := 0;
v_max_retries NUMBER := 3; -- number of retries for WAIT
v_wait_time   NUMBER := 60; -- seconds for WAIT 
CURSOR c_terms IS
-- Run current terms
SELECT terms.term_code,
       terms.start_date,
       terms.end_date,
       terms.group_code
  FROM zbtm.terms_by_group_v terms
 WHERE 1 = 1
   AND terms.group_code IN ('STD', 'MED', 'ACD')
      -- controls what terms run for which instances (only)
   AND ((terms.group_code = 'STD' AND SYSDATE BETWEEN terms.start_date - 7 AND terms.end_date + 7 AND v_instance = 'L2CAN') OR
       (terms.group_code = 'MED' AND SYSDATE BETWEEN terms.start_date - 7 AND terms.end_date + 7 AND v_instance = 'L2CAN') OR
       (terms.group_code = 'ACD' AND SYSDATE BETWEEN terms.start_date - 7 AND terms.end_date + 8 AND v_instance = 'ACCAN'))
   AND (to_char(SYSDATE, 'HH24') BETWEEN '00' AND '08') -- *outside of high demand*
UNION
-- Run non-current terms - **ONLY RUN DURING NON-BUSINESS HOURS** 
SELECT terms.term_code,
       terms.start_date,
       terms.end_date,
       terms.group_code
  FROM zbtm.terms_by_group_v terms
 WHERE 1 = 1
   AND terms.group_code IN ('STD', 'MED', 'ACD')
   AND ((terms.group_code = 'STD' AND SYSDATE BETWEEN terms.start_date - 180 AND terms.end_date + 180 AND v_instance = 'L2CAN') OR
       (terms.group_code = 'MED' AND SYSDATE BETWEEN terms.start_date - 180 AND terms.end_date + 180 AND v_instance = 'L2CAN') OR
       (terms.group_code = 'ACD' AND SYSDATE BETWEEN terms.start_date - 180 AND terms.end_date + 365 AND v_instance = 'ACCAN'))
   AND (to_char(SYSDATE, 'HH24') BETWEEN '18' AND '23') -- *outside of high demand*
UNION ALL
-- Run non-banner terms - **ONLY RUN DURING NON-BUSINESS HOURS** 
SELECT '000000' AS term_code,
       trunc(SYSDATE - 365) AS start_date,
       trunc(SYSDATE + 365) AS end_date,
       '000' AS group_code
  FROM dual
 WHERE 1 = 1
   AND v_instance = 'L2CAN' -- only non term instance  
   AND (to_char(SYSDATE, 'HH24') BETWEEN '18' AND '23') -- *outside of high demand*
 ORDER BY group_code DESC,
          start_date DESC;
BEGIN
-- dbms_output.enable(buffer_size => NULL);
ads_etl.set_parallel_session(p_enabled => 'Y', p_degree => 4, p_mode => 'ALL'); -- Do heavy set-based DML. Turn on full Parallel DML.
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
v_msg     := 'START - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- Retry mechanism for handling deadlocks
v_retry_count := 0;
LOOP
BEGIN
-- both instances are the same query for loading last_activity_gtt ...
INSERT /*+ APPEND */
INTO utl_d_lms.last_activity_gtt
(user_id,
 course_section_id,
 instance,
 term_code,
 pidm,
 crn,
 luid,
 start_date,
 end_date,
 grade_date,
 PARTITION)
WITH se_filt AS
 (SELECT /*+ MATERIALIZE */
   se.user_id,
   se.course_section_id,
   se.instance,
   se.term_code,
   se.pidm,
   se.crn,
   se.luid,
   se.start_date,
   se.end_date,
   se.partition
    FROM utl_d_lms.student_enrollments se
   WHERE se.instance = v_instance
     AND se.term_code = rec.term_code
     AND se.partition = v_partition),
crse_agg AS
 (SELECT /*+ MATERIALIZE */
   c.term_code,
   c.crn,
   c.pidm,
   MAX(c.grade_date) AS grade_date
    FROM utl_d_aim.szrcrse c
   WHERE c.term_code = rec.term_code
   GROUP BY c.term_code,
            c.crn,
            c.pidm)
SELECT /*+ USE_HASH(se_filt crse_agg) LEADING(se_filt crse_agg) */
 se_filt.user_id,
 se_filt.course_section_id,
 se_filt.instance,
 se_filt.term_code,
 se_filt.pidm,
 se_filt.crn,
 se_filt.luid,
 se_filt.start_date,
 se_filt.end_date,
 crse_agg.grade_date,
 se_filt.partition
  FROM se_filt
  LEFT JOIN crse_agg
    ON crse_agg.term_code = se_filt.term_code
   AND crse_agg.crn = se_filt.crn
   AND crse_agg.pidm = se_filt.pidm;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
IF v_instance IN ('ACCAN') THEN
MERGE INTO utl_d_lms.last_activity tgt
USING (SELECT gtt.user_id,
              gtt.course_section_id,
              gtt.instance,
              gtt.term_code,
              gtt.crn,
              gtt.pidm,
              'start_date' AS TYPE,
              CASE
              WHEN gtt.grade_date IS NULL THEN
               'active'
              ELSE
               'expired'
              END AS status,
              gtt.start_date AS max_date -- start dates do not add the 11:59PM to end date
         FROM utl_d_lms.last_activity_gtt gtt
         LEFT JOIN utl_d_lms.last_activity la
           ON la.term_code = gtt.term_code
          AND la.crn = gtt.crn
          AND la.pidm = gtt.pidm
          AND la.type = 'start_date'
          AND (coalesce(la.max_date, v_etl_date) = gtt.start_date)
        WHERE gtt.instance = v_instance
          AND gtt.term_code = rec.term_code
          AND gtt.partition = v_partition
          AND (((gtt.pidm IS NULL AND la.pidm IS NOT NULL) OR --
              (gtt.pidm IS NOT NULL AND la.pidm IS NULL)) OR --  
              (coalesce(gtt.course_section_id, -1) <> coalesce(la.course_section_id, -1)) OR --
              (coalesce(gtt.user_id, -1) <> coalesce(la.user_id, -1)))
       UNION ALL
       SELECT gtt.user_id,
              gtt.course_section_id,
              gtt.instance,
              gtt.term_code,
              gtt.crn,
              gtt.pidm,
              'end_date' AS TYPE,
              CASE
              WHEN gtt.grade_date IS NULL THEN
               'active'
              ELSE
               'expired'
              END AS status,
              gtt.end_date AS max_date -- start dates do not add the 11:59PM to end date
         FROM utl_d_lms.last_activity_gtt gtt
         LEFT JOIN utl_d_lms.last_activity la
           ON la.term_code = gtt.term_code
          AND la.crn = gtt.crn
          AND la.pidm = gtt.pidm
          AND la.type = 'end_date'
          AND (coalesce(la.max_date, v_etl_date) = gtt.end_date)
        WHERE gtt.instance = v_instance
          AND gtt.term_code = rec.term_code
          AND gtt.partition = v_partition
          AND (((gtt.pidm IS NULL AND la.pidm IS NOT NULL) OR --
              (gtt.pidm IS NOT NULL AND la.pidm IS NULL)) OR --  
              (coalesce(gtt.course_section_id, -1) <> coalesce(la.course_section_id, -1)) OR --
              (coalesce(gtt.user_id, -1) <> coalesce(la.user_id, -1)))) src
ON (tgt.term_code = src.term_code AND tgt.crn = src.crn AND tgt.pidm = src.pidm AND tgt.type = src.type)
WHEN MATCHED THEN
UPDATE
   SET tgt.status            = src.status,
       tgt.course_section_id = src.course_section_id,
       tgt.user_id           = src.user_id,
       tgt.max_date          = src.max_date,
       tgt.activity_date     = v_etl_date
WHEN NOT MATCHED THEN
INSERT
(user_id,
 course_section_id,
 instance,
 term_code,
 crn,
 pidm,
 TYPE,
 status,
 max_date)
VALUES
(src.user_id,
 src.course_section_id,
 src.instance,
 src.term_code,
 src.crn,
 src.pidm,
 src.type,
 src.status,
 src.max_date);
v_count   := SQL%ROWCOUNT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'MERGE - start_date / end_date - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
v_total_count := v_total_count + v_count;
COMMIT;
MERGE INTO utl_d_lms.last_activity tgt
USING (SELECT src.user_id,
              src.course_section_id,
              src.type,
              src.instance,
              src.term_code,
              src.crn,
              src.pidm,
              src.status,
              src.max_date
         FROM (SELECT /*+ MATERIALIZE USE_HASH(sa) USE_HASH(se) LEADING(se sa) */
                gtt.user_id,
                gtt.course_section_id,
                gtt.instance,
                gtt.term_code,
                gtt.crn,
                gtt.pidm,
                'last_submission' AS TYPE,
                CASE
                WHEN gtt.grade_date IS NULL THEN
                 'active'
                ELSE
                 'expired'
                END AS status,
                MAX(trunc(coalesce(sa.submitted_date, sa.graded_date) + 1) - 1 / (24 * 60 * 60)) AS max_date -- add the 11:59PM to end date
                 FROM utl_d_lms.last_activity_gtt gtt
                 JOIN utl_d_lms.student_enrollments se
                   ON se.term_code = gtt.term_code
                  AND se.crn = gtt.crn
                  AND se.pidm = gtt.pidm
                 JOIN utl_d_lms.student_assignments sa
                   ON sa.instance = se.instance
                  AND sa.course_section_id = se.course_section_id
                  AND sa.user_id = se.user_id
                WHERE ((sa.submitted_date IS NOT NULL) -- submitted assignment
                      OR (sa.graded_date IS NOT NULL AND coalesce(sa.score, 0) > 0)) -- assignment was graded but score has to be greater than zero; avoiding instructor putting a zero in for missing assignments because that cannot count for activity
                  AND gtt.instance = v_instance
                  AND gtt.term_code = rec.term_code
                  AND gtt.partition = v_partition
                GROUP BY gtt.user_id,
                         gtt.course_section_id,
                         gtt.instance,
                         gtt.term_code,
                         gtt.crn,
                         gtt.pidm,
                         CASE
                         WHEN gtt.grade_date IS NULL THEN
                          'active'
                         ELSE
                          'expired'
                         END) src
         LEFT JOIN utl_d_lms.last_activity la
           ON la.term_code = src.term_code
          AND la.crn = src.crn
          AND la.pidm = src.pidm
          AND la.type = 'last_submission'
          AND (coalesce(la.max_date, v_etl_date) = src.max_date)
        WHERE (((src.pidm IS NULL AND la.pidm IS NOT NULL) OR --
              (src.pidm IS NOT NULL AND la.pidm IS NULL)) OR --  
              (coalesce(src.course_section_id, -1) <> coalesce(la.course_section_id, -1)) OR --
              (coalesce(src.user_id, -1) <> coalesce(la.user_id, -1)))) src
ON (tgt.term_code = src.term_code AND tgt.crn = src.crn AND tgt.pidm = src.pidm AND tgt.type = src.type)
WHEN MATCHED THEN
UPDATE
   SET tgt.status            = src.status,
       tgt.course_section_id = src.course_section_id,
       tgt.user_id           = src.user_id,
       tgt.max_date          = src.max_date,
       tgt.activity_date     = v_etl_date
WHEN NOT MATCHED THEN
INSERT
(user_id,
 course_section_id,
 instance,
 term_code,
 crn,
 pidm,
 TYPE,
 status,
 max_date)
VALUES
(src.user_id,
 src.course_section_id,
 src.instance,
 src.term_code,
 src.crn,
 src.pidm,
 src.type,
 src.status,
 src.max_date);
v_count   := SQL%ROWCOUNT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'MERGE - last_submission - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
v_total_count := v_total_count + v_count;
COMMIT;
MERGE INTO utl_d_lms.last_activity tgt
USING (SELECT src.user_id,
              src.course_section_id,
              src.type,
              src.instance,
              src.term_code,
              src.crn,
              src.pidm,
              src.status,
              src.max_date
         FROM (SELECT /*+ MATERIALIZE USE_HASH(sa) USE_HASH(se) LEADING(se sa) */
                 gtt.user_id,
                 gtt.course_section_id,
                 gtt.instance,
                 gtt.term_code,
                 gtt.crn,
                 gtt.pidm,
                 -- "last_submission_due_date" is to help determine if the student is working ahead so we do not count inactivity against them if they are
                 -- we allow them to work ahead and then we don't count time against them until assignments have caught back up to them
                'last_submission_due_date' AS TYPE,
                CASE
                WHEN gtt.grade_date IS NULL THEN
                 'active'
                ELSE
                 'expired'
                END AS status,
                MAX(CASE
                    WHEN sa.submitted_date IS NOT NULL
                         AND sa.submitted_date < sa.due_date THEN
                     sa.due_date
                    WHEN (sa.graded_date IS NOT NULL AND coalesce(sa.score, 0) > 0)
                         AND sa.graded_date < sa.due_date THEN
                     sa.due_date
                    END) AS max_date -- add the 11:59PM to end date
                 FROM utl_d_lms.last_activity_gtt gtt
                 JOIN utl_d_lms.student_enrollments se
                   ON se.term_code = gtt.term_code
                  AND se.crn = gtt.crn
                  AND se.pidm = gtt.pidm
                 JOIN utl_d_lms.student_assignments sa
                   ON sa.instance = se.instance
                  AND sa.course_section_id = se.course_section_id
                  AND sa.user_id = se.user_id
                WHERE 1 = 1
                  AND sa.due_date IS NOT NULL -- must have a due date for the assignment to track this
                  AND gtt.instance = v_instance
                  AND gtt.term_code = rec.term_code
                  AND gtt.partition = v_partition
               -- we are looking for...
                HAVING AVG(CASE
                          WHEN sa.submitted_date IS NOT NULL
                               AND sa.submitted_date < sa.due_date THEN
                           (CAST(sa.due_date AS DATE) - CAST(sa.submitted_date AS DATE))
                          WHEN (sa.graded_date IS NOT NULL AND coalesce(sa.score, 0) > 0)
                               AND sa.graded_date < sa.due_date THEN
                           (CAST(sa.due_date AS DATE) - CAST(sa.graded_date AS DATE))
                          END) > 7 -- looking for any student regularly turning in assignments early
                  AND MAX(CASE
                          WHEN sa.submitted_date IS NOT NULL
                               AND sa.submitted_date < sa.due_date THEN
                           sa.due_date
                          WHEN (sa.graded_date IS NOT NULL AND coalesce(sa.score, 0) > 0)
                               AND sa.graded_date < sa.due_date THEN
                           sa.due_date
                          END) > v_etl_date -- due date must be greater than today
                GROUP BY gtt.user_id,
                         gtt.course_section_id,
                         gtt.instance,
                         gtt.term_code,
                         gtt.crn,
                         gtt.pidm,
                         CASE
                         WHEN gtt.grade_date IS NULL THEN
                          'active'
                         ELSE
                          'expired'
                         END) src
         LEFT JOIN utl_d_lms.last_activity la
           ON la.term_code = src.term_code
          AND la.crn = src.crn
          AND la.pidm = src.pidm
          AND la.type = 'last_submission_due_date'
          AND (coalesce(la.max_date, v_etl_date) = src.max_date)
        WHERE (((src.pidm IS NULL AND la.pidm IS NOT NULL) OR --
              (src.pidm IS NOT NULL AND la.pidm IS NULL)) OR --  
              (coalesce(src.course_section_id, -1) <> coalesce(la.course_section_id, -1)) OR --
              (coalesce(src.user_id, -1) <> coalesce(la.user_id, -1)))) src
ON (tgt.term_code = src.term_code AND tgt.crn = src.crn AND tgt.pidm = src.pidm AND tgt.type = src.type)
WHEN MATCHED THEN
UPDATE
   SET tgt.status            = src.status,
       tgt.course_section_id = src.course_section_id,
       tgt.user_id           = src.user_id,
       tgt.max_date          = src.max_date,
       tgt.activity_date     = v_etl_date
WHEN NOT MATCHED THEN
INSERT
(user_id,
 course_section_id,
 instance,
 term_code,
 crn,
 pidm,
 TYPE,
 status,
 max_date)
VALUES
(src.user_id,
 src.course_section_id,
 src.instance,
 src.term_code,
 src.crn,
 src.pidm,
 src.type,
 src.status,
 src.max_date);
v_count   := SQL%ROWCOUNT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'MERGE - last_submission_due_date - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
v_total_count := v_total_count + v_count;
COMMIT;
MERGE INTO utl_d_lms.last_activity tgt
USING (SELECT src.user_id,
              src.course_section_id,
              src.type,
              src.instance,
              src.term_code,
              src.crn,
              src.pidm,
              src.status,
              src.max_date
         FROM (SELECT gtt.user_id,
                      gtt.course_section_id,
                      gtt.instance,
                      gtt.term_code,
                      gtt.crn,
                      gtt.pidm,
                      'af_holds' AS TYPE,
                      CASE
                      WHEN v_etl_date <= sprhold_to_date THEN
                       'active'
                      ELSE
                       'expired'
                      END AS status,
                      trunc(sprhold_to_date + 1) - 1 / (24 * 60 * 60) AS max_date, -- add the 11:59PM to end date
                      rank() over(PARTITION BY gtt.term_code, gtt.crn, gtt.pidm ORDER BY sprhold_to_date DESC, rownum) ranking -- GET MOST RECENT (IF MULTIPLE)
                 FROM utl_d_lms.last_activity_gtt gtt
                 JOIN saturn.sprhold
                   ON sprhold_pidm = gtt.pidm
                  AND sprhold_hldd_code IN ('AF')
                WHERE gtt.instance = v_instance
                  AND gtt.term_code = rec.term_code
                  AND gtt.partition = v_partition) src
         LEFT JOIN utl_d_lms.last_activity la
           ON la.term_code = src.term_code
          AND la.crn = src.crn
          AND la.pidm = src.pidm
          AND la.type = 'af_holds'
          AND (coalesce(la.max_date, v_etl_date) = src.max_date)
        WHERE src.ranking = 1
          AND (((src.pidm IS NULL AND la.pidm IS NOT NULL) OR --
              (src.pidm IS NOT NULL AND la.pidm IS NULL)) OR --  
              (coalesce(src.course_section_id, -1) <> coalesce(la.course_section_id, -1)) OR --
              (coalesce(src.user_id, -1) <> coalesce(la.user_id, -1)))) src
ON (tgt.term_code = src.term_code AND tgt.crn = src.crn AND tgt.pidm = src.pidm AND tgt.type = src.type)
WHEN MATCHED THEN
UPDATE
   SET tgt.status            = src.status,
       tgt.course_section_id = src.course_section_id,
       tgt.user_id           = src.user_id,
       tgt.max_date          = src.max_date,
       tgt.activity_date     = v_etl_date
WHEN NOT MATCHED THEN
INSERT
(user_id,
 course_section_id,
 instance,
 term_code,
 crn,
 pidm,
 TYPE,
 status,
 max_date)
VALUES
(src.user_id,
 src.course_section_id,
 src.instance,
 src.term_code,
 src.crn,
 src.pidm,
 src.type,
 src.status,
 src.max_date);
v_count   := SQL%ROWCOUNT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'MERGE - af_holds - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
v_total_count := v_total_count + v_count;
COMMIT;
MERGE INTO utl_d_lms.last_activity tgt
USING (SELECT src.user_id,
              src.course_section_id,
              src.type,
              src.instance,
              src.term_code,
              src.crn,
              src.pidm,
              src.status,
              src.max_date
         FROM (SELECT gtt.user_id,
                      gtt.course_section_id,
                      gtt.instance,
                      gtt.term_code,
                      gtt.crn,
                      gtt.pidm,
                      'luoa_at_risk_exemptions' AS TYPE,
                      CASE
                      WHEN v_etl_date <= exemptions.zfrlist_date_02 THEN
                       'active'
                      ELSE
                       'expired'
                      END AS status,
                      trunc(exemptions.zfrlist_date_02 + 1) - 1 / (24 * 60 * 60) AS max_date, -- add the 11:59PM to end date
                      rank() over(PARTITION BY gtt.user_id, gtt.course_section_id ORDER BY exemptions.zfrlist_date_02 DESC, rownum) ranking -- GET MOST RECENT (IF MULTIPLE)
                 FROM utl_d_lms.last_activity_gtt gtt
                 JOIN zformdata.zfrlist exemptions
                   ON upper(exemptions.zfrlist_char_01) = gtt.luid
                  AND lower(exemptions.zfrlist_list_code) = 'luoa_at_risk_exemptions'
                WHERE gtt.instance = v_instance
                  AND gtt.term_code = rec.term_code
                  AND gtt.partition = v_partition) src
         LEFT JOIN utl_d_lms.last_activity la
           ON la.term_code = src.term_code
          AND la.crn = src.crn
          AND la.pidm = src.pidm
          AND la.type = 'luoa_at_risk_exemptions'
          AND (coalesce(la.max_date, v_etl_date) = src.max_date)
        WHERE src.ranking = 1
          AND (((src.pidm IS NULL AND la.pidm IS NOT NULL) OR --
              (src.pidm IS NOT NULL AND la.pidm IS NULL)) OR --  
              (coalesce(src.course_section_id, -1) <> coalesce(la.course_section_id, -1)) OR --
              (coalesce(src.user_id, -1) <> coalesce(la.user_id, -1)))) src
ON (tgt.term_code = src.term_code AND tgt.crn = src.crn AND tgt.pidm = src.pidm AND tgt.type = src.type)
WHEN MATCHED THEN
UPDATE
   SET tgt.status            = src.status,
       tgt.course_section_id = src.course_section_id,
       tgt.user_id           = src.user_id,
       tgt.max_date          = src.max_date,
       tgt.activity_date     = v_etl_date
WHEN NOT MATCHED THEN
INSERT
(user_id,
 course_section_id,
 instance,
 term_code,
 crn,
 pidm,
 TYPE,
 status,
 max_date)
VALUES
(src.user_id,
 src.course_section_id,
 src.instance,
 src.term_code,
 src.crn,
 src.pidm,
 src.type,
 src.status,
 src.max_date);
v_count   := SQL%ROWCOUNT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'MERGE - luoa_at_risk_exemptions - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
v_total_count := v_total_count + v_count;
COMMIT;
ELSIF v_instance = 'L2CAN' THEN
MERGE INTO utl_d_lms.last_activity tgt
USING (SELECT gtt.user_id,
              gtt.course_section_id,
              gtt.instance,
              gtt.term_code,
              gtt.crn,
              gtt.pidm,
              'start_date' AS TYPE,
              CASE
              WHEN gtt.grade_date IS NULL THEN
               'active'
              ELSE
               'expired'
              END AS status,
              gtt.start_date AS max_date -- start dates do not add the 11:59PM to end date
         FROM utl_d_lms.last_activity_gtt gtt
         LEFT JOIN utl_d_lms.last_activity la
           ON la.term_code = gtt.term_code
          AND la.crn = gtt.crn
          AND la.pidm = gtt.pidm
          AND la.type = 'start_date'
          AND (coalesce(la.max_date, v_etl_date) = gtt.start_date)
        WHERE gtt.instance = v_instance
          AND gtt.term_code = rec.term_code
          AND gtt.partition = v_partition
          AND (((gtt.pidm IS NULL AND la.pidm IS NOT NULL) OR --
              (gtt.pidm IS NOT NULL AND la.pidm IS NULL)) OR --    
              (coalesce(gtt.course_section_id, -1) <> coalesce(la.course_section_id, -1)) OR --
              (coalesce(gtt.user_id, -1) <> coalesce(la.user_id, -1)))
       UNION ALL
       SELECT gtt.user_id,
              gtt.course_section_id,
              gtt.instance,
              gtt.term_code,
              gtt.crn,
              gtt.pidm,
              'end_date' AS TYPE,
              CASE
              WHEN gtt.grade_date IS NULL THEN
               'active'
              ELSE
               'expired'
              END AS status,
              gtt.end_date AS max_date -- add the 11:59PM to end date
         FROM utl_d_lms.last_activity_gtt gtt
         LEFT JOIN utl_d_lms.last_activity la
           ON la.term_code = gtt.term_code
          AND la.crn = gtt.crn
          AND la.pidm = gtt.pidm
          AND la.type = 'end_date'
          AND (coalesce(la.max_date, v_etl_date) = gtt.end_date)
        WHERE gtt.instance = v_instance
          AND gtt.term_code = rec.term_code
          AND gtt.partition = v_partition
          AND (((gtt.pidm IS NULL AND la.pidm IS NOT NULL) OR --
              (gtt.pidm IS NOT NULL AND la.pidm IS NULL)) OR -- 
              (coalesce(la.max_date, v_etl_date) = gtt.end_date) OR --  
              (coalesce(gtt.course_section_id, -1) <> coalesce(la.course_section_id, -1)) OR --
              (coalesce(gtt.user_id, -1) <> coalesce(la.user_id, -1)))) src
ON (tgt.term_code = src.term_code AND tgt.crn = src.crn AND tgt.pidm = src.pidm AND tgt.type = src.type)
WHEN MATCHED THEN
UPDATE
   SET tgt.status            = src.status,
       tgt.course_section_id = src.course_section_id,
       tgt.user_id           = src.user_id,
       tgt.max_date          = src.max_date,
       tgt.activity_date     = v_etl_date
WHEN NOT MATCHED THEN
INSERT
(user_id,
 course_section_id,
 instance,
 term_code,
 crn,
 pidm,
 TYPE,
 status,
 max_date)
VALUES
(src.user_id,
 src.course_section_id,
 src.instance,
 src.term_code,
 src.crn,
 src.pidm,
 src.type,
 src.status,
 src.max_date);
v_count   := SQL%ROWCOUNT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'MERGE - start_date / end_date - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
v_total_count := v_total_count + v_count;
COMMIT;
MERGE INTO utl_d_lms.last_activity tgt
USING (SELECT src.user_id,
              src.course_section_id,
              src.type,
              src.instance,
              src.term_code,
              src.crn,
              src.pidm,
              src.status,
              src.max_date
         FROM (SELECT /*+ MATERIALIZE USE_HASH(sa) USE_HASH(se) LEADING(se sa) */
                gtt.user_id,
                gtt.course_section_id,
                gtt.instance,
                gtt.term_code,
                gtt.crn,
                gtt.pidm,
                'last_submission' AS TYPE,
                CASE
                WHEN gtt.grade_date IS NULL THEN
                 'active'
                ELSE
                 'expired'
                END AS status,
                MAX(trunc(coalesce(sa.submitted_date, sa.graded_date) + 1) - 1 / (24 * 60 * 60)) AS max_date -- add the 11:59PM to end date
                 FROM utl_d_lms.last_activity_gtt gtt
                 JOIN utl_d_lms.student_enrollments se
                   ON se.term_code = gtt.term_code
                  AND se.crn = gtt.crn
                  AND se.pidm = gtt.pidm
                 JOIN utl_d_lms.student_assignments sa
                   ON sa.instance = se.instance
                  AND sa.course_section_id = se.course_section_id
                  AND sa.user_id = se.user_id
                WHERE 1 = 1
                  AND gtt.instance = v_instance
                  AND gtt.term_code = rec.term_code
                  AND gtt.partition = v_partition
                  AND ((sa.submitted_date IS NOT NULL) -- submitted assignment
                      OR (sa.graded_date IS NOT NULL AND coalesce(sa.score, 0) > 0)) -- assignment was graded but score has to be greater than zero; avoiding instructor putting a zero in for missing assignments because that cannot count for activity
                GROUP BY gtt.user_id,
                         gtt.course_section_id,
                         gtt.instance,
                         gtt.term_code,
                         gtt.crn,
                         gtt.pidm,
                         CASE
                         WHEN gtt.grade_date IS NULL THEN
                          'active'
                         ELSE
                          'expired'
                         END) src
         LEFT JOIN utl_d_lms.last_activity la
           ON la.term_code = src.term_code
          AND la.crn = src.crn
          AND la.pidm = src.pidm
          AND la.type = 'last_submission'
          AND (coalesce(la.max_date, v_etl_date) = src.max_date)
        WHERE (((src.pidm IS NULL AND la.pidm IS NOT NULL) OR --
              (src.pidm IS NOT NULL AND la.pidm IS NULL)) OR -- 
              (coalesce(la.max_date, v_etl_date) = src.max_date) OR --  
              (coalesce(src.course_section_id, -1) <> coalesce(la.course_section_id, -1)) OR --
              (coalesce(src.user_id, -1) <> coalesce(la.user_id, -1)))) src
ON (tgt.term_code = src.term_code AND tgt.crn = src.crn AND tgt.pidm = src.pidm AND tgt.type = src.type)
WHEN MATCHED THEN
UPDATE
   SET tgt.status            = src.status,
       tgt.course_section_id = src.course_section_id,
       tgt.user_id           = src.user_id,
       tgt.max_date          = src.max_date,
       tgt.activity_date     = v_etl_date
WHEN NOT MATCHED THEN
INSERT
(user_id,
 course_section_id,
 instance,
 term_code,
 crn,
 pidm,
 TYPE,
 status,
 max_date)
VALUES
(src.user_id,
 src.course_section_id,
 src.instance,
 src.term_code,
 src.crn,
 src.pidm,
 src.type,
 src.status,
 src.max_date);
v_count   := SQL%ROWCOUNT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'MERGE - last_submission - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
v_total_count := v_total_count + v_count;
COMMIT;
MERGE INTO utl_d_lms.last_activity tgt
USING (SELECT src.user_id,
              src.course_section_id,
              src.type,
              src.instance,
              src.term_code,
              src.crn,
              src.pidm,
              src.status,
              src.max_date
         FROM (SELECT /*+ MATERIALIZE USE_HASH(sa) USE_HASH(se) LEADING(se sa) */
                 gtt.user_id,
                 gtt.course_section_id,
                 gtt.instance,
                 gtt.term_code,
                 gtt.crn,
                 gtt.pidm,
                 -- "last_submission_due_date" is to help determine if the student is working ahead so we do not count inactivity against them if they are
                 -- we allow them to work ahead and then we don't count time against them until assignments have caught back up to them
                'last_submission_due_date' AS TYPE,
                CASE
                WHEN gtt.grade_date IS NULL THEN
                 'active'
                ELSE
                 'expired'
                END AS status,
                MAX(CASE
                    WHEN sa.submitted_date IS NOT NULL
                         AND sa.submitted_date < sa.due_date THEN
                     sa.due_date
                    WHEN (sa.graded_date IS NOT NULL AND coalesce(sa.score, 0) > 0)
                         AND sa.graded_date < sa.due_date THEN
                     sa.due_date
                    END) AS max_date -- add the 11:59PM to end date
                 FROM utl_d_lms.last_activity_gtt gtt
                 JOIN utl_d_lms.student_enrollments se
                   ON se.term_code = gtt.term_code
                  AND se.crn = gtt.crn
                  AND se.pidm = gtt.pidm
                 JOIN utl_d_lms.student_assignments sa
                   ON sa.instance = se.instance
                  AND sa.course_section_id = se.course_section_id
                  AND sa.user_id = se.user_id
                WHERE 1 = 1
                  AND sa.due_date IS NOT NULL -- must have a due date for the assignment to track this
                  AND gtt.instance = v_instance
                  AND gtt.term_code = rec.term_code
                  AND gtt.partition = v_partition
               -- we are looking for...
                HAVING AVG(CASE
                          WHEN sa.submitted_date IS NOT NULL
                               AND sa.submitted_date < sa.due_date THEN
                           (CAST(sa.due_date AS DATE) - CAST(sa.submitted_date AS DATE))
                          WHEN (sa.graded_date IS NOT NULL AND coalesce(sa.score, 0) > 0)
                               AND sa.graded_date < sa.due_date THEN
                           (CAST(sa.due_date AS DATE) - CAST(sa.graded_date AS DATE))
                          END) > 7 -- looking for any student regularly turning in assignments early
                  AND MAX(CASE
                          WHEN sa.submitted_date IS NOT NULL
                               AND sa.submitted_date < sa.due_date THEN
                           sa.due_date
                          WHEN (sa.graded_date IS NOT NULL AND coalesce(sa.score, 0) > 0)
                               AND sa.graded_date < sa.due_date THEN
                           sa.due_date
                          END) > v_etl_date -- due date must be greater than today
                GROUP BY gtt.user_id,
                         gtt.course_section_id,
                         gtt.instance,
                         gtt.term_code,
                         gtt.crn,
                         gtt.pidm,
                         CASE
                         WHEN gtt.grade_date IS NULL THEN
                          'active'
                         ELSE
                          'expired'
                         END) src
         LEFT JOIN utl_d_lms.last_activity la
           ON la.term_code = src.term_code
          AND la.crn = src.crn
          AND la.pidm = src.pidm
          AND la.type = 'last_submission_due_date'
          AND (coalesce(la.max_date, v_etl_date) = src.max_date)
        WHERE (((src.pidm IS NULL AND la.pidm IS NOT NULL) OR --
              (src.pidm IS NOT NULL AND la.pidm IS NULL)) OR --   
              (coalesce(src.course_section_id, -1) <> coalesce(la.course_section_id, -1)) OR --
              (coalesce(src.user_id, -1) <> coalesce(la.user_id, -1)))) src
ON (tgt.term_code = src.term_code AND tgt.crn = src.crn AND tgt.pidm = src.pidm AND tgt.type = src.type)
WHEN MATCHED THEN
UPDATE
   SET tgt.status            = src.status,
       tgt.course_section_id = src.course_section_id,
       tgt.user_id           = src.user_id,
       tgt.max_date          = src.max_date,
       tgt.activity_date     = v_etl_date
WHEN NOT MATCHED THEN
INSERT
(user_id,
 course_section_id,
 instance,
 term_code,
 crn,
 pidm,
 TYPE,
 status,
 max_date)
VALUES
(src.user_id,
 src.course_section_id,
 src.instance,
 src.term_code,
 src.crn,
 src.pidm,
 src.type,
 src.status,
 src.max_date);
v_count   := SQL%ROWCOUNT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'MERGE - last_submission_due_date - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
v_total_count := v_total_count + v_count;
COMMIT;
END IF;
-- RUN ANY INSTANCE BELOW
MERGE INTO utl_d_lms.last_activity_pivot tgt
USING (SELECT src.*
         FROM (SELECT la.instance,
                      MAX(la.course_section_id) AS course_section_id, -- wrapping with max to pull the id if it exists (and does not create a multiple row scenario)
                      la.user_id,
                      la.term_code,
                      la.crn,
                      la.pidm,
                      MAX(CASE
                          WHEN gtt.instance = 'ACCAN'
                               AND la.type NOT IN ('end_date') -- types that are not used for last activity
                           THEN
                           la.max_date
                          WHEN gtt.instance = 'L2CAN'
                               AND la.type IN ('start_date', 'last_submission') -- types that are used for last activity
                           THEN
                           la.max_date
                          END) AS last_activity,
                      MAX(CASE
                          WHEN gtt.instance = 'ACCAN'
                               AND la.type IN ('end_date', 'fn_grade_appeal', 'luoa_at_risk_exemptions', 'luoa_extensions') -- only these types can change the end_date
                           THEN
                           la.max_date
                          WHEN gtt.instance = 'L2CAN'
                               AND la.type IN ('end_date') -- only these types can change the end_date
                           THEN
                           la.max_date
                          END) AS end_date,
                      MAX(CASE
                          WHEN la.type = 'start_date' THEN
                           la.max_date
                          END) AS start_date,
                      MAX(CASE
                          WHEN la.type = 'end_date' THEN
                           la.max_date
                          END) AS default_end_date,
                      MAX(CASE
                          WHEN la.type = 'af_holds' THEN
                           la.max_date
                          END) AS af_holds,
                      MAX(CASE
                          WHEN la.type = 'fn_grade_appeal' THEN
                           la.max_date
                          END) AS fn_grade_appeal,
                      MAX(CASE
                          WHEN la.type = 'last_submission' THEN
                           la.max_date
                          END) AS last_submission,
                      MAX(CASE
                          WHEN la.type = 'last_submission_due_date' THEN
                           la.max_date
                          END) AS last_submission_due_date,
                      MAX(CASE
                          WHEN la.type = 'luoa_at_risk_exemptions' THEN
                           la.max_date
                          END) AS luoa_at_risk_exemptions,
                      MAX(CASE
                          WHEN la.type = 'luoa_extensions' THEN
                           la.max_date
                          END) AS luoa_extensions
                 FROM utl_d_lms.last_activity la
                 JOIN utl_d_lms.last_activity_gtt gtt
                   ON gtt.term_code = la.term_code
                  AND gtt.crn = la.crn
                  AND gtt.pidm = la.pidm
                  AND gtt.instance = v_instance
                  AND gtt.term_code = rec.term_code
                  AND gtt.partition = v_partition
                GROUP BY la.instance,
                         la.user_id,
                         la.term_code,
                         la.crn,
                         la.pidm) src
         LEFT JOIN utl_d_lms.last_activity_pivot tgt
           ON tgt.term_code = src.term_code
          AND tgt.crn = src.crn
          AND tgt.pidm = src.pidm
        WHERE 1 = 1
          AND (((src.pidm IS NULL AND tgt.pidm IS NOT NULL) OR --
              (src.pidm IS NOT NULL AND tgt.pidm IS NULL)) OR -- 
              (coalesce(src.start_date, SYSDATE) <> coalesce(tgt.start_date, SYSDATE)) OR --
              (coalesce(src.course_section_id, -1) <> coalesce(tgt.course_section_id, -1)) OR --
              (coalesce(src.user_id, -1) <> coalesce(tgt.user_id, -1)) OR --
              (coalesce(src.end_date, SYSDATE) <> coalesce(tgt.end_date, SYSDATE)) OR --
              (coalesce(src.default_end_date, SYSDATE) <> coalesce(tgt.default_end_date, SYSDATE)) OR --           
              (coalesce(src.last_activity, SYSDATE) <> coalesce(tgt.last_activity, SYSDATE)) OR --
              (coalesce(src.af_holds, SYSDATE) <> coalesce(tgt.af_holds, SYSDATE)) OR --
              (coalesce(src.fn_grade_appeal, SYSDATE) <> coalesce(tgt.fn_grade_appeal, SYSDATE)) OR --
              (coalesce(src.last_submission, SYSDATE) <> coalesce(tgt.last_submission, SYSDATE)) OR --                                                            
              (coalesce(src.last_submission_due_date, SYSDATE) <> coalesce(tgt.last_submission_due_date, SYSDATE)) OR --                                                            
              (coalesce(src.luoa_at_risk_exemptions, SYSDATE) <> coalesce(tgt.luoa_at_risk_exemptions, SYSDATE)) OR --                                                                          
              (coalesce(src.luoa_extensions, SYSDATE) <> coalesce(tgt.luoa_extensions, SYSDATE)))) src
ON (tgt.term_code = src.term_code AND tgt.crn = src.crn AND tgt.pidm = src.pidm)
WHEN MATCHED THEN
UPDATE
   SET tgt.course_section_id        = src.course_section_id,
       tgt.user_id                  = src.user_id,
       tgt.last_activity            = src.last_activity,
       tgt.end_date                 = src.end_date,
       tgt.start_date               = src.start_date,
       tgt.default_end_date         = src.default_end_date,
       tgt.af_holds                 = src.af_holds,
       tgt.fn_grade_appeal          = src.fn_grade_appeal,
       tgt.last_submission          = src.last_submission,
       tgt.last_submission_due_date = src.last_submission_due_date,
       tgt.luoa_at_risk_exemptions  = src.luoa_at_risk_exemptions,
       tgt.luoa_extensions          = src.luoa_extensions,
       tgt.activity_date            = v_etl_date
WHEN NOT MATCHED THEN
INSERT
(instance,
 course_section_id,
 user_id,
 term_code,
 crn,
 pidm,
 last_activity,
 end_date,
 start_date,
 default_end_date,
 af_holds,
 fn_grade_appeal,
 last_submission,
 last_submission_due_date,
 luoa_at_risk_exemptions,
 luoa_extensions)
VALUES
(src.instance,
 src.course_section_id,
 src.user_id,
 src.term_code,
 src.crn,
 src.pidm,
 src.last_activity,
 src.end_date,
 src.start_date,
 src.default_end_date,
 src.af_holds,
 src.fn_grade_appeal,
 src.last_submission,
 src.last_submission_due_date,
 src.luoa_at_risk_exemptions,
 src.luoa_extensions);
v_count   := SQL%ROWCOUNT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'MERGE - last_activity_pivot - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
v_total_count := v_total_count + v_count;
COMMIT;
EXIT; -- If successful, exit the retry loop
EXCEPTION
WHEN OTHERS THEN
IF SQLCODE = -60 THEN
-- Deadlock detected
v_retry_count := v_retry_count + 1;
IF v_retry_count > v_max_retries THEN
-- Log error for max retries
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := '!!!-00060: deadlock detected while waiting for resource. Max retries exceeded after ' || (v_max_retries * v_wait_time) || ' seconds';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
EXIT; -- Add EXIT here to break out of the loop when max retries exceeded
ELSE
-- Log retry attempt
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'Deadlock detected while waiting for resource - waiting ' || v_wait_time || ' seconds for retry attempt number ' || v_retry_count;
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'WARNING', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
dbms_lock.sleep(v_wait_time); -- Wait between retries; short wait because it will need to cycle through all the GTTs again
CONTINUE; -- Add CONTINUE to explicitly indicate loop continuation
END IF;
ELSE
-- Other errors
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
EXIT; -- Add EXIT here to break out of the loop for non-deadlock errors
END IF;
END;
END LOOP; -- end deadlock detection
-- CLEAR GTTs on each successful loop
utl_d_lms.truncate_table(v_table_name => 'last_activity_gtt');
dbms_output.put_line(' --ALL GTTs truncated-- ');
dbms_output.put_line(' --------- ');
END LOOP; -- c_terms
-- Retry mechanism for handling deadlocks
v_retry_count := 0;
v_wait_time   := 60; -- seconds for WAIT; !!! UNIQUE TO THIS PROCEDURE !!! longer wait time since this is outside of the main for loop above
LOOP
BEGIN
-- REMOVING ANY RECORDS THAT NO LONGER HAVE ENROLLMENT 
-- Target cleanup during off-peak windows
IF to_char(v_etl_date, 'D') IN ('4') -- only run at specific times outside of high demand
   AND to_char(SYSDATE, 'HH24') BETWEEN '18' AND '23'
   AND v_partition = 0 -- only run delete on 0 parallel
 THEN
DELETE FROM utl_d_lms.last_activity tgt
 WHERE NOT EXISTS (SELECT 1
          FROM utl_d_lms.student_enrollments se
         WHERE 1 = 1
           AND se.term_code = tgt.term_code
           AND se.crn = tgt.crn
           AND se.pidm = tgt.pidm)
   AND tgt.instance = v_instance;
v_count   := SQL%ROWCOUNT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'DELETE - last_activity - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
v_total_count := v_total_count + v_count;
COMMIT;
DELETE FROM utl_d_lms.last_activity_pivot tgt
 WHERE NOT EXISTS (SELECT 1
          FROM utl_d_lms.student_enrollments se
         WHERE 1 = 1
           AND se.term_code = tgt.term_code
           AND se.crn = tgt.crn
           AND se.pidm = tgt.pidm)
   AND tgt.instance = v_instance;
v_count   := SQL%ROWCOUNT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'DELETE - last_activity_pivot - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
v_total_count := v_total_count + v_count;
COMMIT;
END IF;
EXIT; -- If successful, exit the retry loop
EXCEPTION
WHEN OTHERS THEN
IF SQLCODE = -60 THEN
-- Deadlock detected
v_retry_count := v_retry_count + 1;
IF v_retry_count > v_max_retries THEN
-- Log error for max retries
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := '!!!-00060: deadlock detected while waiting for resource. Max retries exceeded after ' || (v_max_retries * v_wait_time) || ' seconds';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
EXIT; -- Add EXIT here to break out of the loop when max retries exceeded
ELSE
-- Log retry attempt
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'Deadlock detected while waiting for resource - waiting ' || v_wait_time || ' seconds for retry attempt number ' || v_retry_count;
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'WARNING', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
dbms_lock.sleep(v_wait_time); -- Wait between retries;
CONTINUE; -- Add CONTINUE to explicitly indicate loop continuation
END IF;
ELSE
-- Other errors
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
EXIT; -- Add EXIT here to break out of the loop for non-deadlock errors
END IF;
END;
END LOOP; -- end deadlock detection
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
-- log any errors
EXCEPTION
WHEN OTHERS THEN
-- CLEAR GTTs on ERROR
utl_d_lms.truncate_table(v_table_name => 'last_activity_gtt');
dbms_output.put_line(' --ALL GTTs truncated-- ');
dbms_output.put_line(' --------- ');
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
END etl_lms_last_activity;

procedure etl_lms_rubric_scores (jobnumber number, processid varchar2, processname varchar2, inst varchar2, nmbr number) is
/*
Table: utl_d_lms.rubric_scores

Primary Keys: SURROGATE_ID

Unique index: COURSE_SECTION_ID, SUBMISSION_ID, USER_ID, RUBRIC_ID, RATING_ID, RATING_CRITERION_ID, INSTANCE

Purpose: Holds the all the rubric elements for possible answers/responses

Conditions:

Dependencies: utl_d_lms.student_assignments
*/
--DECLARE

v_etl_date DATE := SYSDATE;
v_msg      VARCHAR2(2000);
v_instance VARCHAR2(50) := upper(inst); -- inst from the jams job; used for determining instance
v_partition NUMBER := nmbr; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_row_max  NUMBER := 100000; -- max number of rows to be processed at one time
v_count    NUMBER := 0;
v_job_id   VARCHAR2(32);
v_proc     VARCHAR2(100) := 'etl_lms_rubric_scores';
-- cursors
CURSOR c_terms IS
SELECT DISTINCT ll.term_code
  FROM zbtm.terms_by_group_v t
  JOIN utl_d_lms.lms_link ll
    ON ll.term_code = t.term_code
 WHERE 1 = 2 -- **NOT CURRENTLY ACTIVE**
   AND SYSDATE >= ll.start_date - 180
   AND SYSDATE <= ll.end_date + 30
   AND ll.term_code <> '000000' -- DO NOT RUN NON-TERM
   AND ll.instance = v_instance
 ORDER BY 1 DESC;
CURSOR c1(v_term_code VARCHAR) IS
SELECT
 CASE
 WHEN src.course_section_id IS NOT NULL
      AND target.course_section_id IS NULL THEN
  'INSERT' -- new record to source, add to table
 WHEN src.course_section_id IS NOT NULL
      AND target.course_section_id IS NOT NULL THEN
  'UPDATE' -- record exists in both places
 WHEN src.course_section_id IS NULL
      AND target.course_section_id IS NOT NULL THEN
  'DELETE' -- no record longer exists on the source data, remove it
 END AS control_state,
 coalesce(src.course_section_id, target.course_section_id) AS course_section_id,
 coalesce(src.user_id, target.user_id) AS user_id,
 src.assignment_id,
 coalesce(src.submission_id, target.submission_id) AS submission_id,
 src.assessor_id,
 coalesce(src.rubric_id, target.rubric_id) AS rubric_id,
 coalesce(src.rating_id, target.rating_id) AS rating_id,
 coalesce(src.rating_criterion_id, target.rating_criterion_id) AS rating_criterion_id,
 src.learning_outcomes_id,
 src.rubric_element_description,
 src.rubric_element_long_description,
 src.rubric_rating_long_description,
 src.rubric_rating_description,
 src.comments_enabled,
 src.comments,
 src.posted_date,
 src.points_earned,
 src.rating_points,
 src.points_possible,
 src.workflow_state,
 coalesce(src.instance, target.instance) AS instance,
 SYSDATE AS activity_date
  FROM (SELECT rr.course_section_id,
               rr.user_id,
               rr.assignment_id,
               rr.submission_id,
               rr.assessor_id,
               rr.rubric_id,
               rr.rating_id,
               rr.rating_criterion_id,
               rr.learning_outcomes_id,
               rs.rubric_element_description,
               rs.rubric_element_long_description,
               rs.rubric_rating_long_description,
               rr.rubric_rating_description,
               rr.comments_enabled,
               rr.comments,
               rr.posted_date,
               rr.points_earned,
               rs.rating_points,
               rs.points_possible,
               rr.workflow_state, -- there is no workflow_state on rubric_assessments
               rr.instance
          FROM utl_d_lms.rubric_ratings rr
          JOIN utl_d_lms.lms_link ll
            ON rr.course_section_id = ll.course_section_id
           AND rr.instance = ll.instance
           AND ll.instance = v_instance
           AND ll.partition = v_partition
           AND ll.term_code = v_term_code
          LEFT JOIN utl_d_lms.rubric_structure rs
            ON rs.course_section_id = rr.course_section_id
           AND rs.rubric_id = rr.rubric_id
           AND rs.rating_id = rr.rating_id
           AND rs.rating_criterion_id = rr.rating_criterion_id
           AND rs.instance = rr.instance) src
-- for the control state
  FULL JOIN (SELECT rs.*
               FROM utl_d_lms.rubric_scores rs
               JOIN utl_d_lms.lms_link ll
                 ON ll.instance = rs.instance
                AND ll.course_section_id = rs.course_section_id
              WHERE ll.instance = v_instance
                AND ll.term_code = v_term_code
                AND ll.partition = v_partition) target
    ON target.instance = src.instance
   AND target.course_section_id = src.course_section_id
   AND target.rubric_id = src.rubric_id
   AND target.rating_id = src.rating_id
   AND target.rating_criterion_id = src.rating_criterion_id
   AND target.submission_id = src.submission_id
   AND target.user_id = src.user_id
 WHERE 1 = 1
      -- for inserts or deletes...
   AND (((src.course_section_id IS NULL AND target.course_section_id IS NOT NULL) OR (src.course_section_id IS NOT NULL AND target.course_section_id IS NULL)) OR --
       -- for updates if any data has changed...
       (coalesce(src.rubric_rating_description, 'X') <> coalesce(target.rubric_rating_description, 'X')) OR --
       (coalesce(src.comments, 'X') <> coalesce(target.comments, 'X')) OR --
       (coalesce(src.comments_enabled, 'X') <> coalesce(target.comments_enabled, 'X')) OR --
       (coalesce(src.assignment_id, -1) <> coalesce(target.assignment_id, -1)) OR --
       (coalesce(src.assessor_id, -1) <> coalesce(target.assessor_id, -1)) OR --
       (coalesce(src.learning_outcomes_id, 'X') <> coalesce(target.learning_outcomes_id, 'X')) OR --
       (coalesce(src.posted_date, SYSDATE) <> coalesce(target.posted_date, SYSDATE)) OR --
       (coalesce(src.points_earned, -1) <> coalesce(target.points_earned, -1)) OR --
       (coalesce(src.workflow_state, 'X') <> coalesce(target.workflow_state, 'X')));
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
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
--
FOR rec IN c_terms
LOOP
OPEN c1(rec.term_code);
LOOP v_count := 0; -- reset count
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
FETCH c1 BULK COLLECT
INTO rec_input LIMIT v_row_max;
v_count := rec_input.count;
IF v_count = 0 THEN
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'SELECT - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
ELSIF v_count > 0 THEN
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
WHEN OTHERS THEN v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg := SUBSTR(REPLACE(SQLERRM,'ORA','!!!'),1,200) || ' exception raised for ' || rec.term_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || round(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
CONTINUE;
END;
END LOOP;
insert_count := insert_dml.count;
update_count := update_dml.count;
delete_count := delete_dml.count;
FORALL i IN VALUES OF insert_dml -- DML INSERTS
INSERT INTO utl_d_lms.rubric_scores tab
(course_section_id,
 user_id,
 assignment_id,
 submission_id,
 assessor_id,
 rubric_id,
 rating_id,
 rating_criterion_id,
 learning_outcomes_id,
 rubric_element_description,
 rubric_element_long_description,
 rubric_rating_long_description,
 rubric_rating_description,
 comments_enabled,
 comments,
 posted_date,
 points_earned,
 rating_points,
 points_possible,
 workflow_state,
 instance,
 activity_date)
VALUES
(rec_input(i).course_section_id,
 rec_input(i).user_id,
 rec_input(i).assignment_id,
 rec_input(i).submission_id,
 rec_input(i).assessor_id,
 rec_input(i).rubric_id,
 rec_input(i).rating_id,
 rec_input(i).rating_criterion_id,
 rec_input(i).learning_outcomes_id,
 rec_input(i).rubric_element_description,
 rec_input(i).rubric_element_long_description,
 rec_input(i).rubric_rating_long_description,
 rec_input(i).rubric_rating_description,
 rec_input(i).comments_enabled,
 rec_input(i).comments,
 rec_input(i).posted_date,
 rec_input(i).points_earned,
 rec_input(i).rating_points,
 rec_input(i).points_possible,
 rec_input(i).workflow_state,
 rec_input(i).instance,
 rec_input(i).activity_date);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'INSERT - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
FORALL i IN VALUES OF update_dml -- DML UPDATES
UPDATE utl_d_lms.rubric_scores tab
   SET (course_section_id, user_id, assignment_id, submission_id, assessor_id, rubric_id, rating_id, rating_criterion_id, learning_outcomes_id, rubric_element_description, rubric_element_long_description, rubric_rating_long_description, rubric_rating_description, comments_enabled, comments, posted_date, points_earned, rating_points, points_possible, workflow_state, instance, activity_date) =
       (SELECT rec_input(i).course_section_id,
               rec_input(i).user_id,
               rec_input(i).assignment_id,
               rec_input(i).submission_id,
               rec_input(i).assessor_id,
               rec_input(i).rubric_id,
               rec_input(i).rating_id,
               rec_input(i).rating_criterion_id,
               rec_input(i).learning_outcomes_id,
               rec_input(i).rubric_element_description,
               rec_input(i).rubric_element_long_description,
               rec_input(i).rubric_rating_long_description,
               rec_input(i).rubric_rating_description,
               rec_input(i).comments_enabled,
               rec_input(i).comments,
               rec_input(i).posted_date,
               rec_input(i).points_earned,
               rec_input(i).rating_points,
               rec_input(i).points_possible,
               rec_input(i).workflow_state,
               (rec_input(i).instance),
               rec_input(i).activity_date
          FROM dual)
 WHERE tab.course_section_id = rec_input(i).course_section_id
   AND tab.rubric_id = rec_input(i).rubric_id
   AND tab.rating_id = rec_input(i).rating_id
   AND tab.rating_criterion_id = rec_input(i).rating_criterion_id
   AND tab.submission_id = rec_input(i).submission_id
   AND tab.user_id = rec_input(i).user_id
   AND tab.instance = rec_input(i).instance;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'UPDATE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
FORALL i IN VALUES OF delete_dml -- DML DELETES
DELETE FROM utl_d_lms.rubric_scores tab
 WHERE tab.course_section_id = rec_input(i).course_section_id
   AND tab.rubric_id = rec_input(i).rubric_id
   AND tab.rating_id = rec_input(i).rating_id
   AND tab.rating_criterion_id = rec_input(i).rating_criterion_id
   AND tab.submission_id = rec_input(i).submission_id
   AND tab.user_id = rec_input(i).user_id
   AND tab.instance = rec_input(i).instance;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'DELETE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
END IF;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_total_count := v_total_count + rec_input.count;
EXIT WHEN(rec_input.count < v_row_max);
END LOOP;
CLOSE c1;
dbms_output.put_line(' --------- ');
end loop; -- c_terms
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
-- log any errors
EXCEPTION
WHEN OTHERS THEN v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg := SUBSTR(REPLACE(SQLERRM,'ORA','!!!'),1,200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
/*--------------------------------------------CHANGE LOG----------------------------------------
VERSION  DATE        USERNAME    UPDATES
---      07-05-2021  WGRIFFITH2  --Initial release
---      10-12-2021  WGRIFFITH2  --LUOA CD1 -> CD2
---      12-27-2022  WGRIFFITH2  --performance improvements
------------------------------------------------------------------------------------------------*/
END etl_lms_rubric_scores;
procedure etl_lms_rubric_structure (jobnumber number, processid varchar2, processname varchar2, inst varchar2, nmbr number) is
/*
Table: utl_d_lms.rubric_structure

Primary Keys: SURROGATE_ID

Unique index: COURSE_SECTION_ID, RUBRIC_ID, RATING_ID, RATING_CRITERION_ID, INSTANCE

Purpose: Holds the all the rubric elements for possible answers/responses

Conditions:

Dependencies: utl_d_lms.lms_link
*/
--DECLARE
v_etl_date DATE := SYSDATE;
v_msg      VARCHAR2(2000);
v_instance VARCHAR2(50) := upper(inst); -- inst from the jams job; used for determining instance
v_partition NUMBER := nmbr; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_row_max  NUMBER := 100000; -- max number of rows to be processed at one time
v_count    NUMBER := 0;
v_job_id   VARCHAR2(32);
v_proc     VARCHAR2(100) := 'etl_lms_rubric_structure';
-- cursors
CURSOR c_terms IS
SELECT DISTINCT ll.term_code
  FROM zbtm.terms_by_group_v t
  JOIN utl_d_lms.lms_link ll
    ON ll.term_code = t.term_code
 WHERE 1 = 2 -- **NOT CURRENTLY ACTIVE**
   AND SYSDATE >= ll.start_date - 180
   AND SYSDATE <= ll.end_date + 30
   AND ll.term_code <> '000000' -- DO NOT RUN NON-TERM
   AND ll.instance = v_instance
 ORDER BY 1 DESC;
CURSOR c1(v_term_code VARCHAR) IS
SELECT
 CASE
 WHEN src.course_section_id IS NOT NULL
      AND target.course_section_id IS NULL THEN
  'INSERT' -- new record to source, add to table
 WHEN src.course_section_id IS NOT NULL
      AND target.course_section_id IS NOT NULL THEN
  'UPDATE' -- record exists in both places
 WHEN src.course_section_id IS NULL
      AND target.course_section_id IS NOT NULL THEN
  'DELETE' -- no record longer exists on the source data, remove it
 END AS control_state,
 coalesce(src.course_section_id, target.course_section_id) AS course_section_id,
 coalesce(src.rubric_id, target.rubric_id) AS rubric_id,
 src.rubric_element_description,
 src.rating_points,
 src.points_possible,
 coalesce(src.rating_id, target.rating_id) AS rating_id,
 coalesce(src.rating_criterion_id, target.rating_criterion_id) AS rating_criterion_id,
 src.workflow_state,
 coalesce(src.instance, target.instance) AS instance,
 src.rubric_element_long_description,
 src.rubric_rating_long_description,
 SYSDATE AS activity_date
  FROM (SELECT ll.course_section_id, -- required field in constraint
               r.id AS rubric_id,
               rdata.description AS rubric_element_description,
               rdata.long_description AS rubric_element_long_description,
               rdata.rating_long_description AS rubric_rating_long_description,
               rdata.rating_points, -- points earned for answer
               rdata.points AS points_possible, -- points possible for full credit answer
               rdata.rating_id,
               coalesce(rdata.id, rdata.rating_criterion_id) AS rating_criterion_id, -- id and rating_criterion_id look to be the same
               r.workflow_state,
               ll.instance
          FROM zcanvas_data.rubrics r
          JOIN utl_d_lms.lms_link ll
            ON r.context_id = ll.course_id
           AND r.instance = ll.instance
           AND ll.instance = v_instance
           AND ll.partition = v_partition
           AND ll.term_code = v_term_code
          JOIN json_table(regexp_replace(regexp_replace(r.data, '("[^"]*)(\$)([^"]*"\t*:)', '\1s\3', 1, 0), '("[^"]*)(\@)([^"]*"\t*:)', '\1a\3', 1, 0), '$[*]' NULL
            ON error columns(description VARCHAR2(300) path '$.description', long_description VARCHAR2(500) path '$.long_description', points NUMBER path '$.points', id VARCHAR2(100) path '$.id', criterion_use_range VARCHAR2(10) path
                        '$.criterion_use_range', NESTED path '$.ratings[*]' columns(rating_description VARCHAR2(100) path '$.description', rating_long_description VARCHAR2(300) path '$.long_description', rating_points NUMBER path
                                 '$.points', rating_criterion_id VARCHAR2(100) path '$.criterion_id', rating_id VARCHAR2(100) path '$.id'))) rdata ON 1 = 1) src
-- for the control state
  FULL JOIN (SELECT rs.*
               FROM utl_d_lms.rubric_structure rs
               JOIN utl_d_lms.lms_link ll
                 ON ll.instance = rs.instance
                AND ll.course_section_id = rs.course_section_id
              WHERE ll.instance = v_instance
                AND ll.term_code = v_term_code
                AND ll.partition = v_partition) target
    ON target.instance = src.instance
   AND target.course_section_id = src.course_section_id
   AND target.rubric_id = src.rubric_id
   AND target.rating_id = src.rating_id
   AND target.rating_criterion_id = src.rating_criterion_id
 WHERE 1 = 1
      -- for inserts or deletes...
   AND (((src.course_section_id IS NULL AND target.course_section_id IS NOT NULL) OR (src.course_section_id IS NOT NULL AND target.course_section_id IS NULL)) OR --
       -- for updates if any data has changed...
       (coalesce(src.rubric_element_description, 'X') <> coalesce(target.rubric_element_description, 'X')) OR --
       (coalesce(src.rubric_rating_long_description, 'X') <> coalesce(target.rubric_rating_long_description, 'X')) OR --
       (coalesce(src.rating_points, -1) <> coalesce(target.rating_points, -1)) OR --
       (coalesce(src.points_possible, -1) <> coalesce(target.points_possible, -1)) OR --
       (coalesce(src.workflow_state, 'X') <> coalesce(target.workflow_state, 'X')));
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
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
--
FOR rec IN c_terms
LOOP
OPEN c1(rec.term_code);
LOOP v_count := 0; -- reset count
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
FETCH c1 BULK COLLECT
INTO rec_input LIMIT v_row_max;
v_count := rec_input.count;
IF v_count = 0 THEN
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'SELECT - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
ELSIF v_count > 0 THEN
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
WHEN OTHERS THEN v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg := SUBSTR(REPLACE(SQLERRM,'ORA','!!!'),1,200) || ' exception raised for ' || rec.term_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || round(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
CONTINUE;
END;
END LOOP;
insert_count := insert_dml.count;
update_count := update_dml.count;
delete_count := delete_dml.count;
FORALL i IN VALUES OF insert_dml -- DML INSERTS
INSERT INTO utl_d_lms.rubric_structure tab
(course_section_id,
 rubric_id,
 rubric_element_description,
 rating_points,
 points_possible,
 rating_id,
 rating_criterion_id,
 workflow_state,
 instance,
 activity_date,
 rubric_element_long_description,
 rubric_rating_long_description)
VALUES
(rec_input(i).course_section_id,
 rec_input(i).rubric_id,
 rec_input(i).rubric_element_description,
 rec_input(i).rating_points,
 rec_input(i).points_possible,
 rec_input(i).rating_id,
 rec_input(i).rating_criterion_id,
 rec_input(i).workflow_state,
 rec_input(i).instance,
 rec_input(i).activity_date,
 rec_input(i).rubric_element_long_description,
 rec_input(i).rubric_rating_long_description);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'INSERT - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
FORALL i IN VALUES OF update_dml -- DML UPDATES
UPDATE utl_d_lms.rubric_structure tab
   SET (course_section_id, rubric_id, rubric_element_description, rating_points, points_possible, rating_id, rating_criterion_id, workflow_state, instance, activity_date, rubric_element_long_description, rubric_rating_long_description) =
       (SELECT rec_input(i).course_section_id,
               rec_input(i).rubric_id,
               rec_input(i).rubric_element_description,
               rec_input(i).rating_points,
               rec_input(i).points_possible,
               rec_input(i).rating_id,
               rec_input(i).rating_criterion_id,
               rec_input(i).workflow_state,
               rec_input(i).instance,
               rec_input(i).activity_date,
               rec_input(i).rubric_element_long_description,
               rec_input(i).rubric_rating_long_description
          FROM dual)
 WHERE tab.instance = rec_input(i).instance
   AND tab.course_section_id = rec_input(i).course_section_id
   AND tab.rubric_id = rec_input(i).rubric_id
   AND tab.rating_id = rec_input(i).rating_id
   AND tab.rating_criterion_id = rec_input(i).rating_criterion_id;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'UPDATE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
FORALL i IN VALUES OF delete_dml -- DML DELETES
DELETE FROM utl_d_lms.rubric_structure tab
 WHERE tab.instance = rec_input(i).instance
   AND tab.course_section_id = rec_input(i).course_section_id
   AND tab.rubric_id = rec_input(i).rubric_id
   AND tab.rating_id = rec_input(i).rating_id
   AND tab.rating_criterion_id = rec_input(i).rating_criterion_id;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'DELETE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
END IF;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_total_count := v_total_count + rec_input.count;
EXIT WHEN(rec_input.count < v_row_max);
END LOOP;
CLOSE c1;
dbms_output.put_line(' --------- ');
end loop; -- c_terms
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
-- log any errors
EXCEPTION
WHEN OTHERS THEN v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg := SUBSTR(REPLACE(SQLERRM,'ORA','!!!'),1,200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
/*--------------------------------------------CHANGE LOG----------------------------------------
VERSION  DATE        USERNAME    UPDATES
---      07-05-2021  WGRIFFITH2  --Initial release
---      10-12-2021  WGRIFFITH2  --LUOA CD1 -> CD2
---      12-27-2022  WGRIFFITH2  --performance improvements
------------------------------------------------------------------------------------------------*/
END etl_lms_rubric_structure;
procedure etl_lms_rubric_ratings (jobnumber number, processid varchar2, processname varchar2, inst varchar2, nmbr number) is
/*
Table: utl_d_lms.rubric_ratings

Primary Keys: SURROGATE_ID

Unique index: COURSE_SECTION_ID, SUBMISSION_ID, USER_ID, RUBRIC_ID, RATING_ID, RATING_CRITERION_ID, INSTANCE

Purpose: Holds the all the rubric elements for possible answers/responses; For staging only; Truncated regularly

Conditions:

Dependencies: utl_d_lms.student_assignments
*/
--DECLARE

v_etl_date DATE := SYSDATE;
v_msg      VARCHAR2(2000);
v_instance VARCHAR2(50) := upper(inst); -- inst from the jams job; used for determining instance
v_partition NUMBER := nmbr; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_row_max  NUMBER := 100000; -- max number of rows to be processed at one time
v_count    NUMBER := 0;
v_job_id   VARCHAR2(32);
v_proc     VARCHAR2(100) := 'etl_lms_rubric_ratings';
-- cursors
CURSOR c_terms IS
SELECT DISTINCT ll.term_code
  FROM zbtm.terms_by_group_v t
  JOIN utl_d_lms.lms_link ll
    ON ll.term_code = t.term_code
 WHERE 1 = 2 -- **NOT CURRENTLY ACTIVE**
   AND SYSDATE >= ll.start_date - 180
   AND SYSDATE <= ll.end_date + 30
   AND ll.term_code <> '000000' -- DO NOT RUN NON-TERM
   AND ll.instance = v_instance
 ORDER BY 1 DESC;
CURSOR c1(v_term_code VARCHAR) IS
SELECT
 CASE
 WHEN src.course_section_id IS NOT NULL
      AND target.course_section_id IS NULL THEN
  'INSERT' -- new record to source, add to table
 WHEN src.course_section_id IS NOT NULL
      AND target.course_section_id IS NOT NULL THEN
  'UPDATE' -- record exists in both places
 WHEN src.course_section_id IS NULL
      AND target.course_section_id IS NOT NULL THEN
  'DELETE' -- no record longer exists on the source data, remove it
 END AS control_state,
 coalesce(src.course_section_id, target.course_section_id) AS course_section_id,
 coalesce(src.user_id, target.user_id) AS user_id,
 coalesce(src.rubric_id, target.rubric_id) AS rubric_id,
 src.assignment_id,
 src.assessor_id,
 coalesce(src.submission_id, target.submission_id) AS submission_id,
 coalesce(src.rating_id, target.rating_id) AS rating_id,
 coalesce(src.rating_criterion_id, target.rating_criterion_id) AS rating_criterion_id,
 src.learning_outcomes_id,
 src.points_earned,
 src.rubric_rating_description,
 src.comments_enabled,
 src.comments,
 src.posted_date,
 src.workflow_state,
 coalesce(src.instance, target.instance) AS instance,
 SYSDATE AS activity_date
  FROM (SELECT sa.course_section_id,
               sa.user_id,
               sa.assignment_id,
               sa.submission_id,
               ra.assessor_id,
               ra.rubric_id AS rubric_id,
               coalesce(radata.id, 'blank') AS rating_id,
               radata.criterion_id AS rating_criterion_id,
               radata.learning_outcomes_id,
               radata.points AS points_earned, -- points earned for answer
               radata.description AS rubric_rating_description,
               radata.comments_enabled,
               radata.comments,
               sa.posted_date,
               sa.workflow_state, -- there is no workflow_state on rubric_assessments
               sa.instance
          FROM utl_d_lms.student_assignments sa
          JOIN utl_d_lms.lms_link ll
            ON sa.course_section_id = ll.course_section_id
           AND sa.instance = ll.instance
           AND ll.instance = v_instance
           AND ll.partition = v_partition
           AND ll.term_code = v_term_code
          JOIN zcanvas_data.rubric_assessments ra
            ON ra.artifact_id = sa.submission_id
           AND ra.instance = sa.instance
           AND ra.assessment_type = 'grading'
          JOIN json_table(regexp_replace(regexp_replace(ra.data, '("[^"]*)(\$)([^"]*"\t*:)', '\1s\3', 1, 0), '("[^"]*)(\@)([^"]*"\t*:)', '\1a\3', 1, 0), '$[*]' NULL
            ON error columns(id VARCHAR2(100) path '$.id', points NUMBER path '$.points', criterion_id VARCHAR2(100) path '$.criterion_id', learning_outcomes_id VARCHAR2(100) path '$.learning_outcomes_id', description VARCHAR2(300) path
                        '$.description', comments_enabled VARCHAR2(10) path '$.comments_enabled', comments VARCHAR2(300) path '$.comments')) radata ON 1 = 1) src
-- for the control state
  FULL JOIN (SELECT rs.*
               FROM utl_d_lms.rubric_ratings rs
               JOIN utl_d_lms.lms_link ll
                 ON ll.instance = rs.instance
                AND ll.course_section_id = rs.course_section_id
              WHERE ll.instance = v_instance
                AND ll.term_code = v_term_code
                AND ll.partition = v_partition) target
    ON target.instance = src.instance
   AND target.course_section_id = src.course_section_id
   AND target.rubric_id = src.rubric_id
   AND target.rating_id = src.rating_id
   AND target.rating_criterion_id = src.rating_criterion_id
   AND target.submission_id = src.submission_id
   AND target.user_id = src.user_id
 WHERE 1 = 1
      -- for inserts or deletes...
   AND (((src.course_section_id IS NULL AND target.course_section_id IS NOT NULL) OR (src.course_section_id IS NOT NULL AND target.course_section_id IS NULL)) OR --
       -- for updates if any data has changed...
       (coalesce(src.rubric_rating_description, 'X') <> coalesce(target.rubric_rating_description, 'X')) OR --
       (coalesce(src.comments, 'X') <> coalesce(target.comments, 'X')) OR --
       (coalesce(src.comments_enabled, 'X') <> coalesce(target.comments_enabled, 'X')) OR --
       (coalesce(src.assignment_id, -1) <> coalesce(target.assignment_id, -1)) OR --
       (coalesce(src.assessor_id, -1) <> coalesce(target.assessor_id, -1)) OR --
       (coalesce(src.learning_outcomes_id, 'X') <> coalesce(target.learning_outcomes_id, 'X')) OR --
       (coalesce(src.posted_date, SYSDATE) <> coalesce(target.posted_date, SYSDATE)) OR --
       (coalesce(src.points_earned, -1) <> coalesce(target.points_earned, -1)) OR --
       (coalesce(src.workflow_state, 'X') <> coalesce(target.workflow_state, 'X')));
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
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
--
FOR rec IN c_terms
LOOP
OPEN c1(rec.term_code);
LOOP v_count := 0; -- reset count
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
FETCH c1 BULK COLLECT
INTO rec_input LIMIT v_row_max;
v_count := rec_input.count;
IF v_count = 0 THEN
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'SELECT - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
ELSIF v_count > 0 THEN
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
WHEN OTHERS THEN v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg := SUBSTR(REPLACE(SQLERRM,'ORA','!!!'),1,200) || ' exception raised for ' || rec.term_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || round(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
CONTINUE;
END;
END LOOP;
insert_count := insert_dml.count;
update_count := update_dml.count;
delete_count := delete_dml.count;
FORALL i IN VALUES OF insert_dml -- DML INSERTS
INSERT INTO utl_d_lms.rubric_ratings tab
(course_section_id,
 user_id,
 assignment_id,
 submission_id,
 assessor_id,
 rubric_id,
 rating_id,
 rating_criterion_id,
 learning_outcomes_id,
 points_earned,
 rubric_rating_description,
 comments_enabled,
 comments,
 posted_date,
 workflow_state,
 instance,
 activity_date)
VALUES
(rec_input(i).course_section_id,
 rec_input(i).user_id,
 rec_input(i).assignment_id,
 rec_input(i).submission_id,
 rec_input(i).assessor_id,
 rec_input(i).rubric_id,
 rec_input(i).rating_id,
 rec_input(i).rating_criterion_id,
 rec_input(i).learning_outcomes_id,
 rec_input(i).points_earned,
 rec_input(i).rubric_rating_description,
 rec_input(i).comments_enabled,
 rec_input(i).comments,
 rec_input(i).posted_date,
 rec_input(i).workflow_state,
 (rec_input(i).instance),
 rec_input(i).activity_date);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'INSERT - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
FORALL i IN VALUES OF update_dml -- DML UPDATES
UPDATE utl_d_lms.rubric_ratings tab
   SET (course_section_id, user_id, assignment_id, submission_id, assessor_id, rubric_id, rating_id, rating_criterion_id, learning_outcomes_id, points_earned, rubric_rating_description, comments_enabled, comments, posted_date, workflow_state, instance, activity_date) =
       (SELECT rec_input(i).course_section_id,
               rec_input(i).user_id,
               rec_input(i).assignment_id,
               rec_input(i).submission_id,
               rec_input(i).assessor_id,
               rec_input(i).rubric_id,
               rec_input(i).rating_id,
               rec_input(i).rating_criterion_id,
               rec_input(i).learning_outcomes_id,
               rec_input(i).points_earned,
               rec_input(i).rubric_rating_description,
               rec_input(i).comments_enabled,
               rec_input(i).comments,
               rec_input(i).posted_date,
               rec_input(i).workflow_state,
               (rec_input(i).instance),
               rec_input(i).activity_date
          FROM dual)
 WHERE tab.course_section_id = rec_input(i).course_section_id
   AND tab.rubric_id = rec_input(i).rubric_id
   AND tab.rating_id = rec_input(i).rating_id
   AND tab.rating_criterion_id = rec_input(i).rating_criterion_id
   AND tab.submission_id = rec_input(i).submission_id
   AND tab.user_id = rec_input(i).user_id
   AND tab.instance = rec_input(i).instance;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'UPDATE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
FORALL i IN VALUES OF delete_dml -- DML DELETES
DELETE FROM utl_d_lms.rubric_ratings tab
 WHERE tab.course_section_id = rec_input(i).course_section_id
   AND tab.rubric_id = rec_input(i).rubric_id
   AND tab.rating_id = rec_input(i).rating_id
   AND tab.rating_criterion_id = rec_input(i).rating_criterion_id
   AND tab.submission_id = rec_input(i).submission_id
   AND tab.user_id = rec_input(i).user_id
   AND tab.instance = rec_input(i).instance;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'DELETE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
END IF;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_total_count := v_total_count + rec_input.count;
EXIT WHEN(rec_input.count < v_row_max);
END LOOP;
CLOSE c1;
dbms_output.put_line(' --------- ');
end loop; -- c_terms
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
-- log any errors
EXCEPTION
WHEN OTHERS THEN v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg := SUBSTR(REPLACE(SQLERRM,'ORA','!!!'),1,200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
/*--------------------------------------------CHANGE LOG----------------------------------------
VERSION  DATE        USERNAME    UPDATES
---      07-05-2021  WGRIFFITH2  --Initial release
---      10-12-2021  WGRIFFITH2  --LUOA CD1 -> CD2
---      12-27-2022  WGRIFFITH2  --performance improvements
------------------------------------------------------------------------------------------------*/
END etl_lms_rubric_ratings;

procedure etl_lms_student_progress (jobnumber number, processid varchar2, processname varchar2, inst varchar2, nmbr number) is
-- =============================================================================
-- PURPOSE: Aggregate Canvas/learning-management assignment and activity data per student-section and upsert daily progress metrics into the student_progress table for downstream reporting.
--
-- TARGET(S): utl_d_lms.student_progress
--
-- UNIQUE KEY / INDEX: instance, course_section_id, user_id
--
-- BUSINESS LOGIC & CONDITIONS:
-- - Term selection (c_terms):
--   - Selects terms from zbtm.terms_by_group_v restricted to group_code IN ('STD','MED','ACD').
--   - "Current" window: includes terms where SYSDATE is between start_date - 7 and end_date + 7 and instance-specific mappings (L2CAN for 'STD'/'MED', ACCAN for 'ACD'); runs during hours 00-08 and 12 to avoid peak load.
--   - "Non-current" window: expanded ranges per group (e.g., STD: start_date - 30 .. end_date + 90) and restricted to off-peak hours 18-23.
--   - Synthetic non-banner term '000000' for L2CAN only, created during off-peak hours (18-23) covering a wide 2-year range around today.
--
-- - Staging extraction (c_stage_data):
--   - Builds se_filt = student_enrollments rows for p_instance and p_term_code where no student_progress row exists stamped today (sp.user_id IS NULL), i.e., enrollments not yet processed today or never present.
--   - Joins student_assignments (sa) to se_filt to produce a t_progress_rec collection per assignment; includes related enrichment: course final grade (utl_d_aim.szrcrse), canvas scores (zcanvas_data.scores with course_score='Y' and workflow_state <> 'deleted'), assignment effective grade date (assignments_dates), and last_activity pivot.
--   - Only includes assignments with points_possible > 0 and group_name <> 'Tier 0'.
--   - Marks each staging row with activity_date = v_etl_date to scope downstream DML to "rows touched today".
--
-- - Processing strategy:
--   - Outer loop: iterate terms from c_terms.
--   - For each term: open parameterized staging cursor and BULK COLLECT into an in-memory collection (v_progress_tab) in chunks of c_bulk_limit (default 1,000,000).
--   - For each fetched chunk: perform an aggregated MERGE (upsert) into utl_d_lms.student_progress using the in-memory collection via TABLE(CAST(...)) as the MERGE source. Commit after each successful chunk to bound UNDO.
--   - MERGE is retried on ORA-00060 deadlock up to c_max_retries with a sleep interval c_wait_seconds between retries. Non-deadlock errors rollback, mark the term failed, and exit the term processing loop.
--   - Per-term retry counter resets at the start of each term iteration.
--
-- - Core aggregation and business rules inside the MERGE source:
--   - Grouping keys: src.instance, src.course_section_id, src.user_id, src.enrollment_id, src.term_code (aggregated later by instance/course_section/user/enrollment).
--   - current_score: MAX(coalesce(override_score, current_score, unposted_current_score)) to prefer overrides then posted/unposted scores.
--   - completed_assignments: counts assignments considered complete when submitted_date IS NOT NULL, OR submissions_workflow_state IN ('pending_review','submitted'), OR graded_date IS NOT NULL AND score > 0, OR submissions_workflow_state = 'graded' AND score > 0.
--   - total_assignments: COUNT(assignment_id).
--   - assignments_progress: completed_assignments / total_assignments (rounded to 4 decimals).
--   - completed_points: sum points_possible for the same "completed" definition as assignments.
--   - total_points: SUM(points_possible).
--   - points_progress: completed_points / total_points (rounded to 4 decimals).
--   - points_earned, points_possible, grade_earned: computed only for assignments with effective grading cutoff prior to trunc(v_etl_date) + 1 and for specific workflow_state rules; includes special handling for deleted submissions with failing/withdrawn final grade where grade_date is before cutoff.
--   - missing_assignments: counts assignments missing both submission and grade where due_date < v_etl_date, plus manually graded zero-with-due-date cases.
--   - zero_grades: counts graded assignments with score = 0 and workflow_state = 'graded'.
--   - last_activity, last_submission, last_submission_due_date: MAX aggregations from last_activity pivot.
--   - workflow_state: MIN(enrollments_workflow_state) used as the enrollment-level workflow state aggregation.
--   - start_date, end_date, final_grade_date, credit_hr: aggregated via MIN/MAX as appropriate.
--   - completed_eoc (ACCAN only): flags end-of-course-survey or specific week-18 half-credit rules using title pattern matching and graded/submitted indicators.
--   - missing_tier3 (ACCAN only): counts Tier 3 assignments that are missing and past due.
--
-- - MERGE behavior:
--   - MATCH condition: tgt.instance = src.instance AND tgt.course_section_id = src.course_section_id AND tgt.user_id = src.user_id.
--   - WHEN MATCHED: update the wide set of computed metrics and stamp activity_date = v_etl_date.
--   - WHEN NOT MATCHED: insert a new row with the computed metrics and activity_date = v_etl_date.
--   - Commit per-chunk after each successful MERGE to limit UNDO/transaction size.
--
-- - Post-merge supplemental updates (targeted to rows activity_date = v_etl_date, term_code = current term, instance = v_instance):
--   - inactive_days: update per-row inactivity calculation:
--       - If final_grade IS NOT NULL => inactive_days = 0.
--       - For ACCAN: compute raw calendar days since last_activity, subtract weekend_days (ISO-week arithmetic) and blackout_days (zsailmaker.blackout_days) and floor at 0; if result <= 0 then 0.
--       - For non-ACCAN: use raw calendar days (trunc(v_etl_date) + 1 - last_activity).
--   - first_half_score / second_half_score (ACCAN only): MERGE from a computed pivot that:
--       - Splits assignments into H1/H2 using a REGEXP_SUBSTR on sa.title to extract numeric week and compares to 19.
--       - Aggregates per-group_weight the sum of scores and points (grp_score/grp_points), applies weighting (25/35/40) with special denominator handling when less than 3 different weights exist, and computes weighted_score per half per user-section.
--       - Performance guard: inner computation only considers course_section_id values that were touched in this ETL run (SELECT DISTINCT w2.course_section_id from student_progress where activity_date = v_etl_date and term_code = v_term_code).
--   - Orphan delete: delete rows in student_progress (excluding instance = 'BLACKBOARD') for the current instance/term where no corresponding student_enrollments row exists for the same instance AND term_code AND course_section_id AND user_id.
--
-- - Error handling & control flow (architectural rules, summarized; not implementation mechanics):
--   - Term-level failures are flagged by v_term_failed without aborting the entire job; outer loop continues to next term.
--   - Inner unhandled exceptions close the staging cursor, rollback, log the error, mark term failed, and allow the outer loop to continue.
--   - On outer-most error, the job re-raises to surface a non-zero exit code to the scheduler (JAMS).
--
-- DEPENDENCIES:
-- - Database objects:
--   - Target and staging types: utl_d_lms.student_progress (primary physical target), utl_d_lms.t_progress_tab, utl_d_lms.t_progress_rec, utl_d_lms.student_enrollments, utl_d_lms.student_assignments, utl_d_lms.assignments_dates, utl_d_lms.last_activity_pivot.
--   - Reference/enrichment views/tables: zbtm.terms_by_group_v, utl_d_aim.szrcrse, zcanvas_data.scores, zsailmaker.blackout_days.
-- - Packages and utilities:
--   - ads_etl package: set_parallel_session, insert_job_log.
--   - dbms_output, dbms_session.sleep, standard_hash, SQL built-ins (trunc, to_char, regexp_substr, coalesce/nvl).
-- - External job inputs:
--   - Bind/job parameters: inst (upper-cased into v_instance) and nmbr (into v_partition) must be provided by the scheduler.
--
-- CONSTRAINTS & RISKS:
-- - Memory & PGA: c_bulk_limit default of 1,000,000 can require large PGA; the collection is held in-memory (TABLE(CAST(...))) and may cause memory pressure if a chunk contains many rows. Tune c_bulk_limit based on observed row volumes and available PGA.
-- - Concurrency & Deadlocks: MERGE is retried for ORA-00060 but repeated contention may still cause term failure; heavy concurrent DML against utl_d_lms.student_progress can increase deadlock frequency.
-- - Performance hotspots:
--   - Aggregation over TABLE(CAST(v_progress_tab AS t_progress_tab)) can be CPU/memory intensive for large batches.
--   - The ACCAN half-score calculations use REGEXP and grouping and are guarded to only run on sections touched today, but can still be expensive.
-- - Data dependencies/accuracy risks:
--   - Holiday/blackout logic depends on zsailmaker.blackout_days; missing rows lead to incorrect inactive_days for ACCAN.
--   - Title parsing with regexp_substr assumes a particular naming convention for assignment titles; malformed titles may misclassify H1/H2.
--   - Using to_char(SYSDATE,'HH24') for business-hour gating is subject to server timezone; comments recommend SYSTIMESTAMP AT TIME ZONE for robust timezone-aware checks.
-- - Permissions & object availability: job must have privileges to read referenced schemas/tables and to execute ads_etl package functions.
-- - Edge cases: final grade handling, deleted submissions, and special ACCAN logic (completed_eoc, missing_tier3) introduce business-specific edge rules that must be maintained and understood by stakeholders.
-- =========================================================================
--DECLARE
v_progress_tab utl_d_lms.t_progress_tab := utl_d_lms.t_progress_tab();
v_etl_date     DATE := SYSDATE;
v_msg          VARCHAR2(2000);
v_instance     VARCHAR2(50) := upper(inst); -- inst from the jams job; used for determining instance
v_partition    NUMBER := nmbr; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_count        NUMBER := 0;
v_elapsed      NUMBER := 0;
v_total_count  NUMBER := 0;
v_job_id       VARCHAR2(32);
v_proc         VARCHAR2(100) := 'etl_lms_student_progress';
v_term_code    VARCHAR2(6);
v_term_failed  BOOLEAN := FALSE; -- Architectural Requirement: flag per-term failures without swallowing them
c_bulk_limit   CONSTANT PLS_INTEGER := 1000000; -- TUNABLE: this might seem high, but it's pulling ALL rows for assignment data because we need all this to calculate progress 
c_max_retries  CONSTANT NUMBER := 3; --DEADLOCK RETRY CONTROLS
c_wait_seconds CONSTANT NUMBER := 60; -- DEADLOCK RETRY CONTROLS
-- =========================================================================
-- TERM CURSOR
-- Architectural Requirement: Timezone-aware business-hours filtering.
-- Replace to_char(SYSDATE,'HH24') with SYSTIMESTAMP AT TIME ZONE to
-- eliminate UTC/local mismatch. Adjust zone string to your institution's zone.
-- v_partition reference removed entirely.
-- The UNION vs UNION ALL pattern is preserved intentionally:
--   UNION   = deduplication between current and non-current windows (correct)
--   UNION ALL = non-banner synthetic term has no overlap risk (correct)
-- =========================================================================
CURSOR c_terms IS
-- Current terms: run any hour
SELECT terms.term_code,
       terms.start_date,
       terms.end_date,
       terms.group_code
  FROM zbtm.terms_by_group_v terms
 WHERE 1 = 1
   AND terms.group_code IN ('STD', 'MED', 'ACD')
      -- controls what terms run for which instances (only)
   AND ((terms.group_code = 'STD' AND SYSDATE BETWEEN terms.start_date - 7 AND terms.end_date + 7 AND v_instance = 'L2CAN') OR
       (terms.group_code = 'MED' AND SYSDATE BETWEEN terms.start_date - 7 AND terms.end_date + 7 AND v_instance = 'L2CAN') OR
       (terms.group_code = 'ACD' AND SYSDATE BETWEEN terms.start_date - 7 AND terms.end_date + 7 AND v_instance = 'ACCAN'))
   AND ((to_char(SYSDATE, 'HH24') BETWEEN '00' AND '08' OR to_char(SYSDATE, 'HH24') = '12')) -- *outside of high demand* and running a mid-day check in case of Canvas latency
UNION
-- Non-current terms: ONLY during off-peak hours
SELECT terms.term_code,
       terms.start_date,
       terms.end_date,
       terms.group_code
  FROM zbtm.terms_by_group_v terms
 WHERE terms.group_code IN ('STD', 'MED', 'ACD')
   AND ((terms.group_code IN ('STD') AND SYSDATE BETWEEN terms.start_date - 30 AND terms.end_date + 90 AND v_instance = 'L2CAN') OR
       (terms.group_code IN ('MED') AND SYSDATE BETWEEN terms.start_date - 30 AND terms.end_date + 180 AND v_instance = 'L2CAN') OR
       (terms.group_code = 'ACD' AND SYSDATE BETWEEN terms.start_date - 30 AND terms.end_date + 365 AND v_instance = 'ACCAN'))
   AND to_char(SYSDATE, 'HH24') BETWEEN '18' AND '23'
UNION ALL
-- Non-Banner (no-term) data: off-peak only; L2CAN instance only
SELECT '000000' AS term_code,
       trunc(SYSDATE - 365) AS start_date,
       trunc(SYSDATE + 365) AS end_date,
       '000' AS group_code
  FROM dual
 WHERE v_instance = 'L2CAN'
   AND to_char(SYSDATE, 'HH24') BETWEEN '18' AND '23'
 ORDER BY group_code DESC,
          start_date DESC;
-- =========================================================================
-- STAGING DATA CURSOR (THE REPLACEMENT FOR THE GTT INSERT)
-- Architectural Requirement: This cursor feeds the BULK COLLECT fetch loop.
-- It replaces the single monolithic INSERT /*+ APPEND */ INTO student_progress_gtt.
-- The cursor is parameterized by term_code so it is opened fresh each term.
-- Do NOT alter the SELECT list — it must match t_progress_rec field-for-field.
-- The APPEND hint is intentionally removed (invalid on GTTs and now irrelevant).
-- =========================================================================
CURSOR c_stage_data(p_instance  IN VARCHAR2,
                    p_term_code IN VARCHAR2) IS
WITH se_filt AS
 (SELECT /*+ MATERIALIZE */
   se.user_id,
   se.course_section_id,
   se.instance,
   se.term_code,
   se.enrollment_id,
   se.workflow_state,
   se.partition,
   se.crn,
   se.pidm,
   se.start_date,
   se.end_date,
   se.updated_date
    FROM utl_d_lms.student_enrollments se
    LEFT JOIN utl_d_lms.student_progress sp
      ON sp.instance = se.instance
     AND sp.course_section_id = se.course_section_id
     AND sp.user_id = se.user_id
     AND trunc(sp.activity_date) = trunc(v_etl_date) -- Row-level: only consider it "touched" if it was stamped today
   WHERE se.instance = p_instance
     AND se.term_code = p_term_code
     AND sp.user_id IS NULL -- If NULL: user_id either never existed in student_progress OR exists but was NOT touched today; either way, pull it
  )
SELECT /*+ LEADING(se_filt sa) USE_HASH(se_filt sa sc adt last_act crse) */
 utl_d_lms.t_progress_rec(sa.course_section_id, sa.user_id, se_filt.enrollment_id, sa.assignment_id, sa.submission_id, sa.submitted_date, sa.graded_date, sa.score, sa.points_possible, sa.due_date, adt.dte, -- AS effective_grade_date,
                          sa.group_name, sa.workflow_state, -- AS submissions_workflow_state,
                          se_filt.workflow_state, -- AS enrollments_workflow_state,
                          sa.instance, sc.current_score, sc.unposted_current_score, sc.override_score, crse.final_grade, crse.grade_date, crse.credit_hr, se_filt.term_code, se_filt.crn, last_act.start_date, last_act.end_date, last_act.last_activity, last_act.last_submission, last_act.last_submission_due_date, CASE
                           WHEN last_act.last_activity = last_act.af_holds THEN
                            'af_holds'
                           WHEN last_act.last_activity = last_act.fn_grade_appeal THEN
                            'fn_grade_appeal'
                           WHEN last_act.last_activity = last_act.luoa_extensions THEN
                            'luoa_extensions'
                           WHEN last_act.last_activity = last_act.luoa_at_risk_exemptions THEN
                            'luoa_at_risk_exemptions'
                           WHEN last_act.last_activity = last_act.last_submission_due_date THEN
                            'last_submission_due_date'
                           WHEN last_act.last_activity = last_act.last_submission THEN
                            'last_submission'
                           WHEN last_act.last_activity = last_act.end_date THEN
                            'end_date'
                           WHEN last_act.last_activity = last_act.start_date THEN
                            'start_date'
                           END, -- AS last_activity_type,
                          se_filt.updated_date, v_etl_date, --AS activity_date,
                          sa.title)
  FROM utl_d_lms.student_assignments sa
  JOIN se_filt
    ON se_filt.instance = sa.instance
   AND se_filt.course_section_id = sa.course_section_id
   AND se_filt.user_id = sa.user_id
  LEFT JOIN utl_d_aim.szrcrse crse
    ON crse.term_code = se_filt.term_code
   AND crse.crn = se_filt.crn
   AND crse.pidm = se_filt.pidm
  LEFT JOIN zcanvas_data.scores sc
    ON sc.instance = sa.instance
   AND sc.enrollment_id = se_filt.enrollment_id
   AND sc.course_score = 'Y'
   AND sc.workflow_state <> 'deleted'
  LEFT JOIN utl_d_lms.assignments_dates adt
    ON adt.instance = sa.instance
   AND adt.course_section_id = sa.course_section_id
   AND adt.assignment_id = sa.assignment_id
   AND adt.date_field = 'effective_grade_date'
  LEFT JOIN utl_d_lms.last_activity_pivot last_act
    ON last_act.instance = se_filt.instance
   AND last_act.course_section_id = se_filt.course_section_id
   AND last_act.user_id = se_filt.user_id
 WHERE 1 = 1
   AND coalesce(sa.points_possible, 0) > 0
   AND coalesce(sa.group_name, 'None') <> 'Tier 0';
BEGIN
-- =========================================================================
-- JOB INITIALIZATION
-- Architectural Requirement: Job ID derived without v_partition.
-- Parallel DML set ONCE before the term loop, not toggled inside it.
-- =========================================================================
-- dbms_output.enable(buffer_size => NULL);
ads_etl.set_parallel_session('Y', 8, 'QUERY'); -- FORALL statements. We must SET to QUERY.
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, 0, v_job_id, v_elapsed, 0);
dbms_output.put_line(' --------- ');
-- =========================================================================
-- OUTER TERM LOOP
-- =========================================================================
FOR rec IN c_terms
LOOP
v_count       := 0;
v_term_failed := FALSE;
v_term_code   := rec.term_code;
-- Architectural Requirement: Declare retry counter INSIDE the term loop
-- so it resets to 0 for every term. Original placement in DECLARE block
-- caused retry exhaustion to persist across terms silently.
DECLARE
v_retry_count NUMBER := 0; -- resets each term iteration
BEGIN
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
-- =================================================================
-- BULK COLLECT FETCH LOOP (REPLACES THE GTT INSERT)
-- Architectural Requirement: Open the staging cursor for this term,
-- fetch in chunks of c_bulk_limit, and FORALL-drive the MERGE
-- directly from the in-memory collection.
-- This eliminates the GTT, the APPEND hint, the gather_stats call
-- inside the loop, and the TEMP tablespace pressure entirely.
-- =================================================================
OPEN c_stage_data(v_instance, v_term_code);
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'c_stage_data - ' || v_term_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss');
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
LOOP
-- Fetch the next chunk into the PGA collection
FETCH c_stage_data BULK COLLECT
INTO v_progress_tab LIMIT c_bulk_limit;
EXIT WHEN v_progress_tab.count = 0; -- No rows returned; nothing to process
-- =============================================================
-- DEADLOCK RETRY LOOP (WRAPS THE MERGE ONLY)
-- Architectural Requirement: Retry scope is the MERGE operation,
-- not the fetch. Do not re-fetch rows on retry — the collection
-- is already populated in PGA.
-- 
-- FORALL MERGE (CORE DML)
-- Architectural Requirement: Drive the MERGE from the
-- in-memory collection using FORALL. The MERGE USING
-- clause should reference the collection, not the src.
--
-- NOTE ON ORACLE MERGE + FORALL:
-- Oracle does not support FORALL directly with MERGE syntax.
-- The correct pattern is to use FORALL with a helper
-- pipelined function, OR to build the MERGE USING clause
-- as a SELECT from TABLE(CAST(v_progress_tab AS t_progress_tab)). 
--
-- Architectural Requirement: Move row_hash (deprecated) computation INTO
-- this MERGE USING subquery (it is already there in your original).
-- Do NOT pre-compute it separately.
--
-- Architectural Requirement: REMOVE the inner
--   LEFT JOIN utl_d_lms.student_progress tgt ... WHERE src.row_hash (deprecated) <> tgt.row_hash (deprecated)
-- from inside the USING source. Use WHEN MATCHED THEN UPDATE
--   WHERE tgt.row_hash (deprecated) <> src.row_hash (deprecated)  instead.
-- This eliminates the redundant full target-table scan.
-- =====================================================  
LOOP
BEGIN
MERGE /*+ PQ_DISTRIBUTE(tgt HASH HASH) */
INTO utl_d_lms.student_progress tgt
USING (SELECT /*+ NO_MERGE */
        src.instance,
        src.course_section_id,
        src.user_id,
        src.enrollment_id,
        MAX(coalesce(src.override_score, src.current_score, src.unposted_current_score)) AS current_score, -- needed for LUCOM
        SUM(CASE
            WHEN src.submitted_date IS NOT NULL THEN
             1
            WHEN src.submissions_workflow_state IN ('pending_review', 'submitted') THEN
             1
            WHEN src.graded_date IS NOT NULL
                 AND coalesce(src.score, 0) > 0 THEN
             1
            WHEN src.submissions_workflow_state IN ('graded')
                 AND coalesce(src.score, 0) > 0 THEN
             1
            ELSE
             0
            END) AS completed_assignments,
        COUNT(src.assignment_id) AS total_assignments,
        round(SUM(CASE
                  WHEN src.submitted_date IS NOT NULL THEN
                   1
                  WHEN src.submissions_workflow_state IN ('pending_review', 'submitted') THEN
                   1
                  WHEN src.graded_date IS NOT NULL
                       AND coalesce(src.score, 0) > 0 THEN
                   1
                  WHEN src.submissions_workflow_state IN ('graded')
                       AND coalesce(src.score, 0) > 0 THEN
                   1
                  ELSE
                   0
                  END) / COUNT(src.assignment_id), 4) assignments_progress,
        SUM(CASE
            WHEN src.submitted_date IS NOT NULL THEN
             src.points_possible
            WHEN src.submissions_workflow_state IN ('pending_review', 'submitted') THEN
             src.points_possible
            WHEN src.graded_date IS NOT NULL
                 AND coalesce(src.score, 0) > 0 THEN
             src.points_possible
            WHEN src.submissions_workflow_state IN ('graded')
                 AND coalesce(src.score, 0) > 0 THEN
             src.points_possible
            ELSE
             0
            END) AS completed_points,
        SUM(src.points_possible) AS total_points,
        round(SUM(CASE
                  WHEN src.submitted_date IS NOT NULL THEN
                   src.points_possible
                  WHEN src.submissions_workflow_state IN ('pending_review', 'submitted') THEN
                   src.points_possible
                  WHEN src.graded_date IS NOT NULL
                       AND coalesce(src.score, 0) > 0 THEN
                   src.points_possible
                  WHEN src.submissions_workflow_state IN ('graded')
                       AND coalesce(src.score, 0) > 0 THEN
                   src.points_possible
                  ELSE
                   0
                  END) / SUM(src.points_possible), 4) points_progress,
        -- earned points, possible, grade
        round(SUM(CASE
                  WHEN coalesce(src.graded_date, src.effective_grade_date, src.end_date) < trunc(v_etl_date) + 1
                       AND src.submissions_workflow_state IN ('graded', 'unsubmitted') THEN
                   coalesce(src.score, 0)
                  WHEN coalesce(src.graded_date, src.effective_grade_date, src.end_date) < trunc(v_etl_date) + 1
                       AND src.submissions_workflow_state IN ('pending_review', 'submitted')
                       AND coalesce(src.score, 0) > 0 THEN
                   coalesce(src.score, 0)
                  WHEN coalesce(src.graded_date, src.effective_grade_date, src.end_date) < trunc(v_etl_date) + 1
                       AND src.submissions_workflow_state IN ('deleted')
                       AND substr(src.final_grade, 1, 1) IN ('F', 'W')
                       AND src.grade_date < trunc(v_etl_date) + 1 THEN
                   coalesce(src.score, 0)
                  ELSE
                   NULL
                  END), 0) AS points_earned,
        round(SUM(CASE
                  WHEN coalesce(src.graded_date, src.effective_grade_date, src.end_date) < trunc(v_etl_date) + 1
                       AND src.submissions_workflow_state IN ('graded', 'unsubmitted') THEN
                   src.points_possible
                  WHEN coalesce(src.graded_date, src.effective_grade_date, src.end_date) < trunc(v_etl_date) + 1
                       AND src.submissions_workflow_state IN ('pending_review', 'submitted')
                       AND coalesce(src.score, 0) > 0 THEN
                   src.points_possible
                  WHEN coalesce(src.graded_date, src.effective_grade_date, src.end_date) < trunc(v_etl_date) + 1
                       AND src.submissions_workflow_state IN ('deleted')
                       AND substr(src.final_grade, 1, 1) IN ('F', 'W')
                       AND src.grade_date < trunc(v_etl_date) + 1 THEN
                   src.points_possible
                  ELSE
                   NULL
                  END), 0) AS points_possible,
        round(SUM(CASE
                  WHEN coalesce(src.graded_date, src.effective_grade_date, src.end_date) < trunc(v_etl_date) + 1
                       AND src.submissions_workflow_state IN ('graded', 'unsubmitted') THEN
                   coalesce(src.score, 0)
                  WHEN coalesce(src.graded_date, src.effective_grade_date, src.end_date) < trunc(v_etl_date) + 1
                       AND src.submissions_workflow_state IN ('pending_review', 'submitted')
                       AND coalesce(src.score, 0) > 0 THEN
                   coalesce(src.score, 0)
                  WHEN coalesce(src.graded_date, src.effective_grade_date, src.end_date) < trunc(v_etl_date) + 1
                       AND src.submissions_workflow_state IN ('deleted')
                       AND substr(src.final_grade, 1, 1) IN ('F', 'W')
                       AND src.grade_date < trunc(v_etl_date) + 1 THEN
                   coalesce(src.score, 0)
                  ELSE
                   NULL
                  END) / SUM(CASE
                             WHEN coalesce(src.graded_date, src.effective_grade_date, src.end_date) < trunc(v_etl_date) + 1
                                  AND src.submissions_workflow_state IN ('graded', 'unsubmitted') THEN
                              src.points_possible
                             WHEN coalesce(src.graded_date, src.effective_grade_date, src.end_date) < trunc(v_etl_date) + 1
                                  AND src.submissions_workflow_state IN ('pending_review', 'submitted')
                                  AND coalesce(src.score, 0) > 0 THEN
                              src.points_possible
                             WHEN coalesce(src.graded_date, src.effective_grade_date, src.end_date) < trunc(v_etl_date) + 1
                                  AND src.submissions_workflow_state IN ('deleted')
                                  AND substr(src.final_grade, 1, 1) IN ('F', 'W')
                                  AND src.grade_date < trunc(v_etl_date) + 1 THEN
                              src.points_possible
                             ELSE
                              NULL
                             END), 4) AS grade_earned,
        SUM(CASE
            WHEN src.submitted_date IS NULL -- NO SUB
                 AND src.graded_date IS NULL -- NO GRADE
                 AND src.due_date IS NOT NULL
                 AND src.due_date < v_etl_date THEN
             1
            WHEN src.submitted_date IS NULL -- NO SUB
                 AND src.graded_date IS NOT NULL -- MANUALLY GRADED
                 AND coalesce(src.score, 0) = 0 -- EARNED ZERO
                 AND src.due_date IS NOT NULL
                 AND src.due_date < v_etl_date THEN
             1
            ELSE
             0
            END) AS missing_assignments,
        SUM(CASE
            WHEN src.score = 0 --Only pull grades of 0.
                 AND src.graded_date IS NOT NULL --Assignment has to actually be graded
                 AND src.submissions_workflow_state = 'graded' --Assignment workflow state has to actually be graded
             THEN
             1
            ELSE
             0
            END) AS zero_grades,
        MAX(src.last_activity) AS last_activity,
        MAX(src.last_submission) AS last_submission,
        MAX(src.last_submission_due_date) AS last_submission_due_date,
        MIN(src.enrollments_workflow_state) AS workflow_state,
        MIN(src.start_date) AS start_date,
        MAX(src.end_date) AS end_date,
        MAX(src.grade_date) AS final_grade_date,
        MAX(src.credit_hr) AS credit_hr,
        MIN(src.final_grade) AS final_grade,
        MIN(src.term_code) AS term_code,
        MAX(src.last_activity_type) AS last_activity_type,
        MAX(src.updated_date) AS updated_date,
        MAX(CASE
            WHEN src.instance <> 'ACCAN' THEN
             NULL
            WHEN ((src.graded_date IS NOT NULL OR --
                 src.submitted_date IS NOT NULL) AND --
                 lower(src.title) LIKE '%end of course survey%' OR --
                 lower(src.title) LIKE '%course completion survey%') THEN
             1
            WHEN src.credit_hr = 0.5 -- HALF credit courses >= 202338 do not have EOC assignments, so we have to look to see if they completed week 18 assignments
                 AND ((src.graded_date IS NOT NULL OR --
                 src.submitted_date IS NOT NULL))
                 AND substr(src.title, 3, 2) = '18' THEN
             1
            ELSE
             0
            END) completed_eoc, -- ACCAN only field
        SUM(CASE
            WHEN src.instance <> 'ACCAN' THEN
             NULL
            WHEN src.group_name = 'Tier 3'
                 AND src.submitted_date IS NULL -- NO SUB
                 AND src.graded_date IS NULL -- NO GRADE
                 AND src.due_date IS NOT NULL
                 AND src.due_date < v_etl_date THEN
             1
            ELSE
             0
            END) missing_tier3 -- ACCAN only field
         FROM TABLE(CAST(v_progress_tab AS utl_d_lms.t_progress_tab)) src
        WHERE src.instance = v_instance
          AND src.term_code = rec.term_code
        GROUP BY src.instance,
                 src.course_section_id,
                 src.user_id,
                 src.enrollment_id,
                 src.term_code) src
ON (tgt.instance = src.instance AND tgt.course_section_id = src.course_section_id AND tgt.user_id = src.user_id)
WHEN MATCHED THEN
UPDATE
   SET tgt.completed_assignments    = src.completed_assignments,
       tgt.total_assignments        = src.total_assignments,
       tgt.assignments_progress     = src.assignments_progress,
       tgt.completed_points         = src.completed_points,
       tgt.total_points             = src.total_points,
       tgt.points_progress          = src.points_progress,
       tgt.current_score            = src.current_score,
       tgt.points_earned            = src.points_earned,
       tgt.points_possible          = src.points_possible,
       tgt.grade_earned             = src.grade_earned,
       tgt.missing_assignments      = src.missing_assignments,
       tgt.zero_grades              = src.zero_grades,
       tgt.last_submission          = src.last_submission,
       tgt.last_submission_due_date = src.last_submission_due_date,
       tgt.last_activity            = src.last_activity,
       tgt.start_date               = src.start_date,
       tgt.end_date                 = src.end_date,
       tgt.final_grade              = src.final_grade,
       tgt.final_grade_date         = src.final_grade_date,
       tgt.credit_hr                = src.credit_hr,
       tgt.workflow_state           = src.workflow_state,
       tgt.activity_date            = v_etl_date,
       tgt.term_code                = src.term_code,
       tgt.last_activity_type       = src.last_activity_type,
       tgt.completed_eoc            = src.completed_eoc,
       tgt.missing_tier3            = src.missing_tier3,
       tgt.updated_date             = src.updated_date
WHEN NOT MATCHED THEN
INSERT
(course_section_id,
 user_id,
 completed_assignments,
 total_assignments,
 assignments_progress,
 completed_points,
 total_points,
 points_progress,
 current_score,
 points_earned,
 points_possible,
 grade_earned,
 missing_assignments,
 zero_grades,
 last_submission,
 last_submission_due_date,
 last_activity,
 start_date,
 end_date,
 final_grade,
 final_grade_date,
 credit_hr,
 workflow_state,
 instance,
 activity_date,
 term_code,
 last_activity_type,
 completed_eoc,
 missing_tier3,
 updated_date)
VALUES
(src.course_section_id,
 src.user_id,
 src.completed_assignments,
 src.total_assignments,
 src.assignments_progress,
 src.completed_points,
 src.total_points,
 src.points_progress,
 src.current_score,
 src.points_earned,
 src.points_possible,
 src.grade_earned,
 src.missing_assignments,
 src.zero_grades,
 src.last_submission,
 src.last_submission_due_date,
 src.last_activity,
 src.start_date,
 src.end_date,
 src.final_grade,
 src.final_grade_date,
 src.credit_hr,
 src.workflow_state,
 src.instance,
 v_etl_date,
 src.term_code,
 src.last_activity_type,
 src.completed_eoc,
 src.missing_tier3,
 src.updated_date);
v_count       := SQL%ROWCOUNT;
v_total_count := v_total_count + v_count;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE (batch) - ' || v_term_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- Architectural Requirement: Commit after each chunk MERGE,
-- not after the full term. Keeps UNDO bounded.
COMMIT;
EXIT; -- Successful MERGE; exit retry loop and fetch next chunk
EXCEPTION
WHEN OTHERS THEN
IF SQLCODE = -60 THEN
-- Deadlock on MERGE: wait and retry the same chunk
v_retry_count := v_retry_count + 1;
IF v_retry_count > c_max_retries THEN
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := '!!!-00060: Deadlock max retries exceeded after ' || (c_max_retries * c_wait_seconds) || ' seconds on term ' || v_term_code;
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, 0, v_job_id, v_elapsed, 0);
v_term_failed := TRUE;
EXIT; -- Abort retry loop; outer fetch loop will EXIT WHEN on next check
ELSE
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'Deadlock detected - retry attempt ' || v_retry_count || ' of ' || c_max_retries || ' after ' || c_wait_seconds || 's on term ' || v_term_code;
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'WARNING', v_msg, v_instance, 0, v_job_id, v_elapsed, 0);
dbms_session.sleep(c_wait_seconds);
CONTINUE; -- Retry the MERGE on the same chunk
END IF;
ELSE
-- Non-deadlock error: log, mark term failed, break all loops
ROLLBACK; -- Architectural Requirement: explicit rollback on non-deadlock errors
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, 0, v_job_id, v_elapsed, 0);
v_term_failed := TRUE;
EXIT; -- Exit retry loop
END IF;
END;
END LOOP; -- End deadlock retry loop
EXIT WHEN v_term_failed; -- Architectural Requirement: propagate failure flag out of fetch loop cleanly
END LOOP; -- End bulk collect fetch loop
CLOSE c_stage_data;
-- =========================================================================
-- POST-MERGE SUPPLEMENTAL UPDATES
-- Architectural Requirement: Each DML targets ONLY rows stamped today via
-- activity_date predicate. This confines each update to the exact set of
-- rows touched by the MERGE in the current execution window, avoiding
-- full-table churn and keeping UNDO bounded per-term.
-- Placement: Insert each block AFTER the COMMIT that follows the DELETE,
-- still inside the IF NOT v_term_failed THEN guard, still inside the
-- inner DECLARE block, once per term iteration.
-- =========================================================================
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'MERGE (complete) - ' || v_term_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs) - rows: ' || to_char(v_total_count); -- getting v_total_count (instead of v_count) to determine total of merges before moving on
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, 0, v_job_id, v_elapsed, v_count);
ads_etl.set_parallel_session('Y', 8); -- DML statements, use default mode
-- =========================================================================
-- UPDATE: inactive_days
-- =========================================================================
UPDATE /*+ NO_MERGE */ utl_d_lms.student_progress tgt
   SET tgt.inactive_days =
       (SELECT /*+ NO_MERGE */
         floor(CASE
               -- Finalist: final grade present; inactivity is moot regardless of instance
               WHEN final_grade IS NOT NULL THEN
                0
               -- ACCAN: net business days (raw - weekends - holidays), floored at zero;
               -- a negative result means the student was recently active
               WHEN v_instance = 'ACCAN'
                    AND (raw_days - weekend_days - holiday_days) <= 0 THEN
                0
               WHEN v_instance = 'ACCAN' THEN
                raw_days - weekend_days - holiday_days
               -- Non-ACCAN: raw calendar days; no weekend or holiday exclusion
               WHEN final_grade IS NULL THEN
                raw_days
               WHEN workflow_state = 'active' THEN
                raw_days
               ELSE
                0
               END) AS inactive_days
          FROM (SELECT /*+ NO_MERGE */
                 tgt.final_grade,
                 tgt.workflow_state,
                 -- Raw calendar distance: last_activity through v_etl_date inclusive
                 floor(coalesce(trunc(v_etl_date) + 1 - tgt.last_activity, 0)) AS raw_days,
                 -- Weekend arithmetic (ACCAN only); replaces crscalendar join entirely.
                 -- Formula:  full ISO-weeks * 2
                 --         + trailing partial-week Saturday/Sunday count
                 --         - leading partial-week Saturday/Sunday count
                 CASE
                 WHEN v_instance = 'ACCAN'
                      AND tgt.last_activity IS NOT NULL THEN
                  ((trunc(v_etl_date, 'IW') - trunc(tgt.last_activity, 'IW')) / 7) * 2 + greatest(trunc(v_etl_date) - trunc(v_etl_date, 'IW') - 4, 0) - greatest(tgt.last_activity - trunc(tgt.last_activity, 'IW') - 5, 0)
                 ELSE
                  0
                 END AS weekend_days,
                 -- Holiday count (ACCAN only): correlated scalar against small reference
                 -- table only; student_enrollments and last_activity_pivot not required.
                 -- Range mirrors the original: [last_activity, v_etl_date)
                 CASE
                 WHEN v_instance = 'ACCAN' -- ACCAN only; DO NOT REMOVE
                      AND tgt.last_activity IS NOT NULL THEN
                  (SELECT COUNT(*)
                     FROM zsailmaker.blackout_days holi
                    WHERE holi.day >= tgt.last_activity
                      AND holi.day < trunc(v_etl_date))
                 ELSE
                  0
                 END AS holiday_days
                  FROM dual) computed)
 WHERE tgt.instance = v_instance
   AND tgt.term_code = v_term_code
   AND tgt.activity_date = v_etl_date; -- Scope: only rows stamped by today's MERGE
v_count       := SQL%ROWCOUNT;
v_total_count := v_total_count + v_count;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'UPDATE inactive_days - ' || v_term_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs) - rows: ' || to_char(v_count);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, 0, v_job_id, v_elapsed, v_count);
COMMIT;
-- =========================================================================
-- UPDATE: first_half_score & second_half_score
-- =========================================================================
IF v_instance = 'ACCAN' THEN
MERGE INTO utl_d_lms.student_progress tgt
USING (
       -- ── Outer layer: pivot H1 / H2 scores into two columns per student ──
       SELECT course_section_id,
               user_id,
               MAX(CASE
                   WHEN half_flag = 'H1' THEN
                    weighted_score
                   END) AS first_half_score,
               MAX(CASE
                   WHEN half_flag = 'H2' THEN
                    weighted_score
                   END) AS second_half_score
         FROM (
                -- ── Middle layer: apply weighting formula per (section, user, half) ──
                --    Denominator logic preserved exactly from original function:
                --      COUNT(DISTINCT group_weight) here is equivalent to the original
                --      SUM(CASE WHEN COUNT(DISTINCT group_weight) < 3 THEN 1 END)
                --      because the inner layer already has exactly one row per weight.
                SELECT course_section_id,
                        user_id,
                        half_flag,
                        round((SUM(CASE
                                   WHEN group_weight IN (25, 35, 40) THEN
                                    (grp_score / grp_points) * group_weight
                                   END) / CASE
                              WHEN COUNT(DISTINCT group_weight) < 3 THEN
                               SUM(group_weight) -- partial-weight denominator
                              ELSE
                               100 -- full 25+35+40 denominator
                              END) * 100, 2) AS weighted_score
                  FROM (
                         -- ── Inner layer: sum score/points per (section, user, weight, half) ──
                         --    Mirrors the GROUP BY sa.group_weight in the original function.
                         --    REGEXP filter for half is applied here so the aggregate is clean.
                         SELECT sa.course_section_id,
                                 sa.user_id,
                                 sa.group_weight,
                                 CASE
                                 WHEN to_number(regexp_substr(sa.title, '\.([a-zA-Z0-9]+)\.', 1, 1, NULL, 1)) < 19 THEN
                                  'H1'
                                 ELSE
                                  'H2'
                                 END AS half_flag,
                                 SUM(sa.score) AS grp_score,
                                 SUM(sa.points_possible) AS grp_points
                           FROM utl_d_lms.student_assignments sa
                          WHERE sa.instance = 'ACCAN'
                            AND sa.graded_date IS NOT NULL
                            AND nvl(sa.points_possible, 0) > 0
                            AND sa.workflow_state <> 'pending_review'
                               -- Performance guard: restrict student_assignments to only the
                               -- course sections present in this ETL batch; avoids a full-table
                               -- scan across all terms when computing scores.
                            AND sa.course_section_id IN (SELECT /*+ NO_MERGE */
                                                         DISTINCT w2.course_section_id
                                                           FROM utl_d_lms.student_progress w2
                                                          WHERE w2.instance = 'ACCAN'
                                                            AND w2.term_code = v_term_code
                                                            AND w2.activity_date = v_etl_date)
                          GROUP BY sa.course_section_id,
                                    sa.user_id,
                                    sa.group_weight,
                                    CASE
                                    WHEN to_number(regexp_substr(sa.title, '\.([a-zA-Z0-9]+)\.', 1, 1, NULL, 1)) < 19 THEN
                                     'H1'
                                    ELSE
                                     'H2'
                                    END) grp_level
                 GROUP BY course_section_id,
                           user_id,
                           half_flag) scored
        GROUP BY course_section_id,
                  user_id) src
ON (tgt.course_section_id = src.course_section_id AND tgt.user_id = src.user_id AND tgt.instance = v_instance AND tgt.term_code = v_term_code AND tgt.activity_date = v_etl_date)
WHEN MATCHED THEN
UPDATE
   SET tgt.first_half_score  = src.first_half_score,
       tgt.second_half_score = src.second_half_score;
v_count       := SQL%ROWCOUNT;
v_total_count := v_total_count + v_count;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
-- Preserve original log entry for first_half_score
v_msg := 'UPDATE first_half_score - ' || v_term_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs) - rows: ' || to_char(v_count);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, 0, v_job_id, v_elapsed, v_count);
-- Preserve original log entry for second_half_score
-- Row count is shared because both columns are set in a single MERGE.
v_msg := 'UPDATE second_half_score - ' || v_term_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs) - rows: ' || to_char(v_count);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, 0, v_job_id, v_elapsed, v_count);
COMMIT;
END IF;
-- =================================================================
-- ORPHAN RECORD DELETE
-- Architectural Requirement: Add AND se.term_code = sp.term_code
-- to the NOT EXISTS subquery. Original code retained rows for students
-- enrolled in ANY term, not specifically the term being processed.
-- The BLACKBOARD instance guard is preserved as-is.
-- =================================================================
IF NOT v_term_failed THEN
DELETE /*+ USE_HASH(se) */
FROM utl_d_lms.student_progress sp
 WHERE sp.instance <> 'BLACKBOARD'
   AND sp.instance = v_instance
   AND sp.term_code = v_term_code
   AND NOT EXISTS (SELECT 1
          FROM utl_d_lms.student_enrollments se
         WHERE se.instance = sp.instance
           AND se.term_code = sp.term_code -- Architectural Fix: was missing in original
           AND se.course_section_id = sp.course_section_id
           AND se.user_id = sp.user_id);
v_count       := SQL%ROWCOUNT;
v_total_count := v_total_count + v_count;
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'DELETE - ' || v_term_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs) - rows removed: ' || to_char(v_count);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, 0, v_job_id, v_elapsed, v_count);
END IF;
dbms_output.put_line(' --------- ');
EXCEPTION
-- Architectural Requirement: Catch any unhandled exception from the
-- inner DECLARE block (e.g., cursor open failure, collection type error).
-- Log it, mark the term failed, and allow the outer term loop to continue
-- to the next term rather than aborting the entire job.
WHEN OTHERS THEN
IF c_stage_data%ISOPEN THEN
CLOSE c_stage_data;
END IF;
ROLLBACK;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'UNHANDLED - term ' || v_term_code || ': ' || substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 150);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, 0, v_job_id, v_elapsed, 0);
END; -- End inner DECLARE block for this term
END LOOP; -- End c_terms loop
-- =========================================================================
-- JOB COMPLETION
-- Architectural Requirement: Turn off parallelism ONCE here, not inside
-- the term loop. A single post-loop stats gather against the physical target
-- =========================================================================
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, 0, v_job_id, v_elapsed, v_total_count);
-- Architectural Requirement: Run stats once on the physical target table after
-- all terms complete. Removed from inside the loop; removed GTT dependency.
ads_etl.set_parallel_session('N');
-- =========================================================================
-- OUTER EXCEPTION HANDLER
-- Architectural Requirement: Original block incorrectly cleared
-- student_enrollments_gtt here. Corrected to student_progress_gtt (if GTT
-- is retained in a hybrid migration) or removed entirely if full collection
-- migration is complete.
-- If GTT is fully removed, delete the clear_table call below.
-- =========================================================================
EXCEPTION
WHEN OTHERS THEN
IF c_stage_data%ISOPEN THEN
CLOSE c_stage_data;
END IF;
ROLLBACK;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, 0, v_job_id, v_elapsed, 0);
ads_etl.set_parallel_session('N');
RAISE; -- Architectural Requirement: re-raise so JAMS receives a non-zero exit code
END etl_lms_student_progress;

procedure etl_lms_student_quizzes (jobnumber number, processid varchar2, processname varchar2, inst varchar2, nmbr number) is
/*
Table: utl_d_lms.student_quizzes

Primary Keys: SURROGATE_ID

Unique index: COURSE_SECTION_ID, USER_ID, QUIZ_ID, QUESTION_ID, ANSWER_ID, INSTANCE

Purpose: Table that holds data for all quiz questions and answers in CANVAS

Conditions:

Dependencies:  utl_d_lms.quizzes; utl_d_lms.quiz_questions_answers; utl_d_lms.student_quiz_answers
*/
--DECLARE
v_etl_date DATE := SYSDATE;
v_msg      VARCHAR2(2000);
v_instance VARCHAR2(50) := upper(inst); -- inst from the jams job; used for determining instance
v_partition NUMBER := nmbr; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_lms_student_quizzes';
CURSOR c_terms IS
-- Run current terms
SELECT terms.term_code,
       terms.start_date,
       terms.end_date,
       terms.group_code
  FROM zbtm.terms_by_group_v terms
 WHERE 1 = 1
   AND terms.group_code IN ('STD', 'MED', 'ACD')
   -- controls what terms run for which instances (only)
   AND ((terms.group_code = 'STD' AND SYSDATE BETWEEN terms.start_date - 7 AND terms.end_date + 7 AND v_instance = 'L2CAN') OR
       (terms.group_code = 'MED' AND SYSDATE BETWEEN terms.start_date - 7 AND terms.end_date + 7 AND v_instance = 'L2CAN') OR
       (terms.group_code = 'ACD' AND SYSDATE BETWEEN terms.start_date - 7 AND terms.end_date + 8 AND v_instance = 'ACCAN'))
   AND (to_char(SYSDATE, 'HH24') BETWEEN '00' AND '08') -- *outside of high demand*
UNION
-- Run non-current terms - **ONLY RUN DURING NON-BUSINESS HOURS** 
SELECT terms.term_code,
       terms.start_date,
       terms.end_date,
       terms.group_code
  FROM zbtm.terms_by_group_v terms
 WHERE 1 = 1
   AND terms.group_code IN ('STD', 'MED', 'ACD')
   AND ((terms.group_code = 'STD' AND SYSDATE BETWEEN terms.start_date - 180 AND terms.end_date + 180 AND v_instance = 'L2CAN') OR
       (terms.group_code = 'MED' AND SYSDATE BETWEEN terms.start_date - 180 AND terms.end_date + 180 AND v_instance = 'L2CAN') OR
       (terms.group_code = 'ACD' AND SYSDATE BETWEEN terms.start_date - 180 AND terms.end_date + 365 AND v_instance = 'ACCAN'))
   AND (to_char(SYSDATE, 'HH24') BETWEEN '18' AND '23') -- *outside of high demand*
UNION ALL
-- Run non-banner terms - **ONLY RUN DURING NON-BUSINESS HOURS** 
SELECT '000000' AS term_code,
       trunc(SYSDATE - 365) AS start_date,
       trunc(SYSDATE + 365) AS end_date,
       '000' AS group_code
  FROM dual
 WHERE 1 = 1
   AND v_instance = 'L2CAN' -- only non term instance  
   AND (to_char(SYSDATE, 'HH24') BETWEEN '18' AND '23') -- *outside of high demand*
 ORDER BY group_code DESC,
          start_date DESC;
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
v_msg     := 'START - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
INSERT /*+ APPEND LEADING(se qd sqa qqa caqb tgt) */
INTO utl_d_lms.student_quizzes_gtt
(control_state,
 course_section_id,
 user_id,
 quiz_id,
 assignment_id,
 assignment_group_id,
 question_id,
 answer_id,
 title,
 submission_types,
 scoring_policy,
 show_correct_answers,
 show_correct_answers_last_attempt,
 shuffle_answers,
 question_title,
 question,
 answer,
 weight,
 points_possible,
 time_limit,
 allowed_attempts,
 question_count,
 correct,
 points,
 due_date,
 workflow_state,
 instance,
 activity_date,
 submission_id,
 foundational_skill,
 updated_date,
 term_code,
 quiz_version,
 started_date,
 finished_date,
 end_date,
 quiz_score,
 quiz_points_possible,
 position)
SELECT CASE
       WHEN tgt.course_section_id IS NULL THEN
        'INSERT'
       ELSE
        'UPDATE'
       END AS control_state,
       src.course_section_id,
       src.user_id,
       src.quiz_id,
       src.assignment_id,
       src.assignment_group_id,
       src.question_id,
       src.answer_id,
       src.title,
       src.submission_types,
       src.scoring_policy,
       src.show_correct_answers,
       src.show_correct_answers_last_attempt,
       src.shuffle_answers,
       src.question_title,
       src.question,
       src.answer,
       src.weight,
       src.points_possible,
       src.time_limit,
       src.allowed_attempts,
       src.question_count,
       src.correct,
       src.points,
       src.due_date,
       src.workflow_state,
       src.instance,
       v_etl_date AS activity_date,
       src.submission_id,
       src.foundational_skill,
       src.updated_date,
       src.term_code,
       src.quiz_version,
       src.started_date,
       src.finished_date,
       src.end_date,
       src.quiz_score,
       src.quiz_points_possible,
       src.position
  FROM (SELECT /*+ INDEX(sqa STUDENT_QUIZ_ANSWERS_OPT_IDX) INDEX(qd QUIZZES_UNIQUE_INDX) INDEX(se STUDENT_ENROLLMENTS_UNIQUE_INDX) INDEX(qqa QUIZ_QUESTIONS_ANSWERS_UNIQUE_INDX) */
         qd.course_section_id,
         sqa.user_id,
         qd.quiz_id,
         qd.assignment_id,
         qd.assignment_group_id,
         sqa.submission_id,
         sqa.question_id,
         sqa.answer_id,
         qd.title,
         qd.submission_types,
         qd.scoring_policy,
         qd.show_correct_answers,
         qd.show_correct_answers_last_attempt,
         qd.shuffle_answers,
         qqa.question_title,
         qqa.question,
         qqa.answer,
         qqa.weight,
         qqa.points_possible,
         qd.time_limit,
         qd.allowed_attempts,
         qd.question_count,
         sqa.correct,
         sqa.points,
         qd.due_date,
         caqb.title                           AS foundational_skill,
         sqa.workflow_state,
         v_instance                           AS instance,
         sqa.updated_date,
         rec.term_code                        AS term_code,
         sqa.quiz_version,
         sqa.started_date,
         sqa.finished_date,
         sqa.end_date,
         sqa.quiz_score,
         sqa.quiz_points_possible,
         qqa.position
          FROM (SELECT /*+ INDEX(STUDENT_ENROLLMENTS STUDENT_ENROLLMENTS_UNIQUE_INDX) */
                 instance,
                 course_section_id,
                 course_id,
                 user_id
                  FROM utl_d_lms.student_enrollments
                 WHERE instance = v_instance
                   AND term_code = rec.term_code
                   AND PARTITION = v_partition) se
          JOIN (SELECT /*+ INDEX(QUIZZES QUIZZES_UNIQUE_INDX) */
                instance,
                course_section_id,
                quiz_id,
                due_date,
                question_count,
                time_limit,
                allowed_attempts,
                title,
                submission_types,
                scoring_policy,
                show_correct_answers,
                show_correct_answers_last_attempt,
                shuffle_answers,
                assignment_group_id,
                assignment_id
                 FROM utl_d_lms.quizzes
                WHERE instance = v_instance
                  AND term_code = rec.term_code) qd
            ON qd.instance = se.instance
           AND qd.course_section_id = se.course_section_id
          JOIN (SELECT /*+ INDEX(STUDENT_QUIZ_ANSWERS STUDENT_QUIZ_ANSWERS_UNIQUE_INDX) */
                instance,
                course_section_id,
                quiz_id,
                user_id,
                question_id,
                answer_id,
                quiz_score,
                quiz_points_possible,
                quiz_version,
                started_date,
                finished_date,
                end_date,
                updated_date,
                workflow_state,
                correct,
                points,
                submission_id,
                assignment_id
                 FROM utl_d_lms.student_quiz_answers
                WHERE instance = v_instance
                  AND term_code = rec.term_code) sqa
            ON sqa.instance = qd.instance
           AND sqa.course_section_id = qd.course_section_id
           AND sqa.quiz_id = qd.quiz_id
           AND sqa.user_id = se.user_id
          LEFT JOIN (SELECT /*+ INDEX(QUIZ_QUESTIONS_ANSWERS QUIZ_QUESTIONS_ANSWERS_UNIQUE_INDX) */
                     instance,
                     course_section_id,
                     quiz_id,
                     user_id,
                     question_id,
                     answer_id,
                     assessment_question_bank_id,
                     position,
                     question_title,
                     question,
                     answer,
                     weight,
                     points_possible
                      FROM utl_d_lms.quiz_questions_answers
                     WHERE instance = v_instance
                       AND term_code = rec.term_code) qqa
            ON qqa.instance = qd.instance
           AND qqa.course_section_id = qd.course_section_id
           AND qqa.quiz_id = qd.quiz_id
           AND qqa.user_id = se.user_id
           AND qqa.question_id = sqa.question_id
           AND qqa.answer_id = sqa.answer_id
          LEFT JOIN (SELECT * FROM zcanvas_data.assessment_question_banks WHERE instance = v_instance) caqb
            ON caqb.instance = qd.instance
           AND caqb.context_id = se.course_id
           AND caqb.id = qqa.assessment_question_bank_id) src
  LEFT JOIN (SELECT /*+ INDEX(STUDENT_QUIZZES STUDENT_QUIZZES_UNIQUE_INDX) */
              instance,
              course_section_id,
              quiz_id,
              user_id,
              question_id,
              answer_id,
              updated_date
               FROM utl_d_lms.student_quizzes
              WHERE instance = v_instance
                AND term_code = rec.term_code) tgt
    ON tgt.instance = src.instance
   AND tgt.course_section_id = src.course_section_id
   AND tgt.quiz_id = src.quiz_id
   AND tgt.user_id = src.user_id
   AND tgt.question_id = src.question_id
   AND tgt.answer_id = src.answer_id
 WHERE src.updated_date > nvl(tgt.updated_date, to_date('19000101', 'YYYYMMDD'));
v_count       := SQL%ROWCOUNT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
INSERT INTO utl_d_lms.student_quizzes_gtt
(control_state,
 course_section_id,
 user_id,
 quiz_id,
 assignment_id,
 assignment_group_id,
 question_id,
 answer_id,
 title,
 submission_types,
 scoring_policy,
 show_correct_answers,
 show_correct_answers_last_attempt,
 shuffle_answers,
 question_title,
 question,
 answer,
 weight,
 points_possible,
 time_limit,
 allowed_attempts,
 question_count,
 correct,
 points,
 due_date,
 workflow_state,
 instance,
 activity_date,
 submission_id,
 foundational_skill,
 updated_date,
 term_code)
SELECT src.control_state,
       src.course_section_id,
       src.user_id,
       src.quiz_id,
       src.assignment_id,
       src.assignment_group_id,
       src.question_id,
       src.answer_id,
       src.title,
       src.submission_types,
       src.scoring_policy,
       src.show_correct_answers,
       src.show_correct_answers_last_attempt,
       src.shuffle_answers,
       src.question_title,
       src.question,
       src.answer,
       src.weight,
       src.points_possible,
       src.time_limit,
       src.allowed_attempts,
       src.question_count,
       src.correct,
       src.points,
       src.due_date,
       src.workflow_state,
       src.instance,
       v_etl_date AS activity_date,
       src.submission_id,
       src.foundational_skill,
       src.updated_date,
       src.term_code
  FROM ( -- ALL INSTANCES
        SELECT 'DELETE' AS control_state,
                ll.course_section_id,
                ll.instance,
                ll.term_code,
                qd.user_id,
                qd.quiz_id,
                qd.assignment_id,
                qd.assignment_group_id,
                qd.question_id,
                qd.answer_id,
                qd.title,
                qd.submission_types,
                qd.scoring_policy,
                qd.show_correct_answers,
                qd.show_correct_answers_last_attempt,
                qd.shuffle_answers,
                qd.question_title,
                qd.question,
                qd.answer,
                qd.weight,
                qd.points_possible,
                qd.time_limit,
                qd.allowed_attempts,
                qd.question_count,
                qd.correct,
                qd.points,
                qd.due_date,
                qd.workflow_state,
                qd.activity_date,
                qd.submission_id,
                qd.foundational_skill,
                qd.updated_date
          FROM utl_d_lms.student_quizzes qd -- still exists on target
          JOIN utl_d_lms.lms_link ll
            ON qd.course_section_id = ll.course_section_id
           AND qd.instance = ll.instance
           AND ll.instance = v_instance
           AND ll.term_code = rec.term_code
           AND ll.partition = v_partition
          LEFT JOIN zcanvas_data.quiz_submissions ceq
            ON ceq.instance = qd.instance
           AND ceq.quiz_id = qd.quiz_id
           AND ceq.user_id = qd.user_id
           AND ceq.submission_id = qd.submission_id
         WHERE 1 = 1
           AND (coalesce(ceq.workflow_state, 'X') = 'deleted' -- but no longer exists on source
               OR ceq.id IS NULL)) src;
v_count       := SQL%ROWCOUNT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'DELETE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
MERGE INTO utl_d_lms.student_quizzes tgt
USING (SELECT gtt.control_state,
              gtt.course_section_id,
              gtt.user_id,
              gtt.quiz_id,
              gtt.assignment_id,
              gtt.assignment_group_id,
              gtt.question_id,
              gtt.answer_id,
              gtt.title,
              gtt.submission_types,
              gtt.scoring_policy,
              gtt.show_correct_answers,
              gtt.show_correct_answers_last_attempt,
              gtt.shuffle_answers,
              gtt.question_title,
              gtt.question,
              gtt.answer,
              gtt.weight,
              gtt.points_possible,
              gtt.time_limit,
              gtt.allowed_attempts,
              gtt.question_count,
              gtt.correct,
              gtt.points,
              gtt.due_date,
              gtt.workflow_state,
              gtt.instance,
              gtt.activity_date,
              gtt.submission_id,
              gtt.foundational_skill,
              gtt.updated_date,
              gtt.term_code,
              gtt.quiz_version,
              gtt.started_date,
              gtt.finished_date,
              gtt.end_date,
              gtt.quiz_score,
              gtt.quiz_points_possible,
              position
         FROM utl_d_lms.student_quizzes_gtt gtt
        WHERE 1 = 1
          AND gtt.instance = v_instance
          AND gtt.term_code = rec.term_code
          AND gtt.control_state IN ('INSERT', 'UPDATE')) src
ON (tgt.instance = src.instance AND tgt.course_section_id = src.course_section_id AND tgt.user_id = src.user_id AND tgt.quiz_id = src.quiz_id AND tgt.question_id = src.question_id AND tgt.answer_id = src.answer_id)
WHEN MATCHED THEN
UPDATE
   SET tgt.assignment_id                     = src.assignment_id,
       tgt.assignment_group_id               = src.assignment_group_id,
       tgt.title                             = src.title,
       tgt.submission_types                  = src.submission_types,
       tgt.scoring_policy                    = src.scoring_policy,
       tgt.show_correct_answers              = src.show_correct_answers,
       tgt.show_correct_answers_last_attempt = src.show_correct_answers_last_attempt,
       tgt.shuffle_answers                   = src.shuffle_answers,
       tgt.question_title                    = src.question_title,
       tgt.question                          = src.question,
       tgt.answer                            = src.answer,
       tgt.weight                            = src.weight,
       tgt.points_possible                   = src.points_possible,
       tgt.time_limit                        = src.time_limit,
       tgt.allowed_attempts                  = src.allowed_attempts,
       tgt.question_count                    = src.question_count,
       tgt.correct                           = src.correct,
       tgt.points                            = src.points,
       tgt.due_date                          = src.due_date,
       tgt.workflow_state                    = src.workflow_state,
       tgt.activity_date                     = src.activity_date,
       tgt.submission_id                     = src.submission_id,
       tgt.foundational_skill                = src.foundational_skill,
       tgt.updated_date                      = src.updated_date,
       tgt.term_code                         = src.term_code,
       tgt.quiz_version                      = src.quiz_version,
       tgt.started_date                      = src.started_date,
       tgt.finished_date                     = src.finished_date,
       tgt.end_date                          = src.end_date,
       tgt.quiz_score                        = src.quiz_score,
       tgt.quiz_points_possible              = src.quiz_points_possible,
       tgt.position                          = src.position
WHEN NOT MATCHED THEN
INSERT
(course_section_id,
 user_id,
 quiz_id,
 assignment_id,
 assignment_group_id,
 question_id,
 answer_id,
 title,
 submission_types,
 scoring_policy,
 show_correct_answers,
 show_correct_answers_last_attempt,
 shuffle_answers,
 question_title,
 question,
 answer,
 weight,
 points_possible,
 time_limit,
 allowed_attempts,
 question_count,
 correct,
 points,
 due_date,
 workflow_state,
 instance,
 activity_date,
 submission_id,
 foundational_skill,
 updated_date,
 term_code,
 quiz_version,
 started_date,
 finished_date,
 end_date,
 quiz_score,
 quiz_points_possible,
 position)
VALUES
(src.course_section_id,
 src.user_id,
 src.quiz_id,
 src.assignment_id,
 src.assignment_group_id,
 src.question_id,
 src.answer_id,
 src.title,
 src.submission_types,
 src.scoring_policy,
 src.show_correct_answers,
 src.show_correct_answers_last_attempt,
 src.shuffle_answers,
 src.question_title,
 src.question,
 src.answer,
 src.weight,
 src.points_possible,
 src.time_limit,
 src.allowed_attempts,
 src.question_count,
 src.correct,
 src.points,
 src.due_date,
 src.workflow_state,
 src.instance,
 src.activity_date,
 src.submission_id,
 src.foundational_skill,
 src.updated_date,
 src.term_code,
 src.quiz_version,
 src.started_date,
 src.finished_date,
 src.end_date,
 src.quiz_score,
 src.quiz_points_possible,
 src.position);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- DML DELETES
DELETE FROM utl_d_lms.student_quizzes tab
 WHERE EXISTS (SELECT 1
          FROM utl_d_lms.student_quizzes_gtt gtt
         WHERE 1 = 1
           AND gtt.instance = v_instance
           AND gtt.control_state = 'DELETE'
           AND tab.instance = gtt.instance
           AND tab.course_section_id = gtt.course_section_id
           AND tab.user_id = gtt.user_id
           AND tab.quiz_id = gtt.quiz_id
           AND tab.question_id = gtt.question_id
           AND tab.answer_id = gtt.answer_id);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'DELETE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
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
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
/*--------------------------------------------CHANGE LOG----------------------------------------
VERSION  DATE        USERNAME    UPDATES
---      07-05-2021  WGRIFFITH2  --Initial release
---      10-12-2021  WGRIFFITH2  --LUOA CD1 -> CD2
---      09-19-2022  WGRIFFITH2  --REMOVING FROM SCHEDULE. Only runs ad-hoc now
---      10-19-2022  WGRIFFITH2  --ADDING BACK SCHEDULE. Only select courses
---      12-27-2022  WGRIFFITH2  --performance improvements
---      05-22-2023  WGRIFFITH2  --performance improvements; adding updated_date and term_code
---      09-20-2023  WGRIFFITH2  --opening it up to all courses, because we need to get CRC data for all courses; limits/filters need to happen more downstream
---      09-28-2023  WGRIFFITH2  --adding new fields
-- 20250919      WGRIFFITH2      --Index creation, inline views and valid index hints added, join order forced, and early filtering applied to resolve optimizer ignoring indexes and excessive temp space.
------------------------------------------------------------------------------------------------*/
END etl_lms_student_quizzes;

procedure etl_lms_student_quiz_answers (jobnumber number, processid varchar2, processname varchar2, inst varchar2, nmbr number) IS
/*
Table: utl_d_lms.student_quiz_answers

Primary Keys: SURROGATE_ID

Unique index: COURSE_SECTION_ID, USER_ID, QUIZ_ID, QUESTION_ID, ANSWER_ID, INSTANCE

Purpose: Table that holds data for all quiz questions and answers in CANVAS.

Conditions:

Dependencies:  utl_d_lms.quizzes
*/
--DECLARE
v_etl_date DATE := SYSDATE;
v_msg      VARCHAR2(2000);
v_instance VARCHAR2(50) := upper(inst); -- inst from the jams job; used for determining instance
v_partition NUMBER := nmbr; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_lms_student_quiz_answers';
CURSOR c_terms IS
-- Run current terms
SELECT terms.term_code,
       terms.start_date,
       terms.end_date,
       terms.group_code
  FROM zbtm.terms_by_group_v terms
 WHERE 1 = 1
   AND terms.group_code IN ('STD', 'MED', 'ACD')
   -- controls what terms run for which instances (only)
   AND ((terms.group_code = 'STD' AND SYSDATE BETWEEN terms.start_date - 7 AND terms.end_date + 7 AND v_instance = 'L2CAN') OR
       (terms.group_code = 'MED' AND SYSDATE BETWEEN terms.start_date - 7 AND terms.end_date + 7 AND v_instance = 'L2CAN') OR
       (terms.group_code = 'ACD' AND SYSDATE BETWEEN terms.start_date - 7 AND terms.end_date + 8 AND v_instance = 'ACCAN'))
   AND (to_char(SYSDATE, 'HH24') BETWEEN '00' AND '08') -- *outside of high demand*
UNION
-- Run non-current terms - **ONLY RUN DURING NON-BUSINESS HOURS** 
SELECT terms.term_code,
       terms.start_date,
       terms.end_date,
       terms.group_code
  FROM zbtm.terms_by_group_v terms
 WHERE 1 = 1
   AND terms.group_code IN ('STD', 'MED', 'ACD')
   AND ((terms.group_code = 'STD' AND SYSDATE BETWEEN terms.start_date - 180 AND terms.end_date + 180 AND v_instance = 'L2CAN') OR
       (terms.group_code = 'MED' AND SYSDATE BETWEEN terms.start_date - 180 AND terms.end_date + 180 AND v_instance = 'L2CAN') OR
       (terms.group_code = 'ACD' AND SYSDATE BETWEEN terms.start_date - 180 AND terms.end_date + 365 AND v_instance = 'ACCAN'))
   AND (to_char(SYSDATE, 'HH24') BETWEEN '18' AND '23') -- *outside of high demand*
UNION ALL
-- Run non-banner terms - **ONLY RUN DURING NON-BUSINESS HOURS** 
SELECT '000000' AS term_code,
       trunc(SYSDATE - 365) AS start_date,
       trunc(SYSDATE + 365) AS end_date,
       '000' AS group_code
  FROM dual
 WHERE 1 = 1
   AND v_instance = 'L2CAN' -- only non term instance  
   AND (to_char(SYSDATE, 'HH24') BETWEEN '18' AND '23') -- *outside of high demand*
 ORDER BY group_code DESC,
          start_date DESC;
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
v_msg     := 'START - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- !!! GLOBAL TEMP TABLE - PRESERVES ROWS ON COMMIT !!!
-- multiple runs per session with cause unique constraint (constraint_name) violated
-- truncate table quiz_questions_answers_gtt;
INSERT INTO utl_d_lms.student_quiz_answers_gtt
(control_state,
 course_section_id,
 user_id,
 quiz_id,
 assignment_id,
 assignment_group_id,
 question_id,
 answer_id,
 correct,
 points,
 updated_date,
 workflow_state,
 instance,
 activity_date,
 submission_id,
 term_code,
 quiz_version,
 started_date,
 finished_date,
 end_date,
 quiz_score,
 quiz_points_possible)
SELECT CASE
       WHEN src.course_section_id IS NOT NULL
            AND tgt.course_section_id IS NULL THEN
        'INSERT' -- new record to source, add to table
       WHEN src.course_section_id IS NOT NULL
            AND tgt.course_section_id IS NOT NULL THEN
        'UPDATE' -- record exists in both places
       END AS control_state,
       src.course_section_id,
       src.user_id,
       src.quiz_id,
       src.assignment_id,
       src.assignment_group_id,
       src.question_id,
       src.answer_id,
       src.correct,
       src.points,
       src.updated_date,
       src.workflow_state,
       src.instance,
       v_etl_date AS activity_date,
       src.submission_id,
       src.term_code,
       src.quiz_version,
       src.started_date,
       src.finished_date,
       src.end_date,
       src.score,
       src.quiz_points_possible
  FROM (SELECT qd.course_section_id,
               qs.user_id,
               qd.quiz_id,
               qd.assignment_id,
               qd.assignment_group_id,
               qs.submission_id,
               answers.question_id,
               coalesce(answers.answer_id, -1) AS answer_id,
               answers.correct,
               answers.points,
               qs.updated_at AS updated_date,
               qs.workflow_state,
               v_instance AS instance,
               se.term_code,
               qs.quiz_version,
               qs.started_at AS started_date,
               qs.finished_at AS finished_date,
               qs.end_at AS end_date,
               qs.score,
               qs.quiz_points_possible
          FROM utl_d_lms.student_enrollments se
          JOIN utl_d_lms.quizzes qd
            ON qd.instance = se.instance
           AND qd.course_section_id = se.course_section_id
           AND ((qd.title = 'End of Course Survey') -- TESTING / POC --PRJTASK0698254
               OR (qd.title = 'Course Requirements Checklist') -- WE ARE LOOKING FOR SPECIFIC THINGS TO LIMIT THE SCOPE AND SIZE OF THE DATA
               -- WE ARE LOOKING FOR SPECIFIC THINGS TO LIMIT THE SCOPE AND SIZE OF THE DATA
               OR (se.course_section_id IN (570780, 618673)) -- added for Bill - PRJTASK0688083
               OR (se.subj_code || se.crse_numb IN -- ** ONLY COURSES THAT WE ARE TRACKING QUIZ DATA**
               ('BIBL104', 'BIBL105', 'BIBL110', 'CINE101', 'EDUC201', 'ENGL102', 'ENGL215', -- added for Nicholas TKT2835857
                     'HIUS222', 'INFT110', 'INQR101', 'INQR102', 'MATH128', 'PHIL201', 'RSCH201', -- added for Nicholas TKT2835857
                     'THEO201', 'THEO202', 'UNIV101', 'UNIV104', -- added for Nicholas TKT2835857
                     'EDAS645', 'EDAS740', 'EDUC305', 'EDUC360', 'EDLC504', 'EDLC704', 'COSC604', -- added for Nicholas TKT2835857
                     'PSYC510', 'PSYC515' -- add for Ethan TKT3033356
                     )))
           AND se.instance = v_instance
           AND se.term_code = rec.term_code
           AND se.partition = v_partition
          JOIN zcanvas_data.quiz_submissions qs
            ON qd.instance = qs.instance
           AND qd.quiz_id = qs.quiz_id
           AND qs.user_id = se.user_id
          JOIN json_table(qs.submission_data, '$[*]' NULL
            ON error columns(correct VARCHAR2(300) path '$.correct', --
                       points NUMBER path '$.points', --
                       question_id NUMBER path '$.question_id', --
                       answer_id NUMBER path '$.answer_id')) answers --
         ON 1 = 1) src
  LEFT JOIN utl_d_lms.student_quiz_answers tgt
    ON tgt.instance = src.instance
   AND tgt.course_section_id = src.course_section_id
   AND tgt.quiz_id = src.quiz_id
   AND tgt.user_id = src.user_id
   AND tgt.question_id = src.question_id
   AND tgt.answer_id = src.answer_id
 WHERE 1 = 1 -- get anything more recent or new
   AND (src.updated_date > tgt.updated_date OR tgt.updated_date IS NULL);
v_count       := SQL%ROWCOUNT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
INSERT INTO utl_d_lms.student_quiz_answers_gtt
(control_state,
 course_section_id,
 user_id,
 quiz_id,
 assignment_id,
 assignment_group_id,
 question_id,
 answer_id,
 correct,
 points,
 updated_date,
 workflow_state,
 instance,
 activity_date,
 submission_id,
 term_code)
SELECT src.control_state,
       src.course_section_id,
       src.user_id,
       src.quiz_id,
       src.assignment_id,
       src.assignment_group_id,
       src.question_id,
       src.answer_id,
       src.correct,
       src.points,
       src.updated_date,
       src.workflow_state,
       src.instance,
       src.activity_date,
       src.submission_id,
       src.term_code
  FROM ( -- ALL INSTANCES
        SELECT 'DELETE' AS control_state,
                ll.course_section_id,
                ll.instance,
                ll.term_code,
                qd.user_id,
                qd.quiz_id,
                qd.assignment_id,
                qd.assignment_group_id,
                qd.question_id,
                qd.answer_id,
                qd.correct,
                qd.points,
                qd.updated_date,
                qd.workflow_state,
                qd.activity_date,
                qd.submission_id
          FROM utl_d_lms.student_quiz_answers qd -- still exists on target
          JOIN utl_d_lms.lms_link ll
            ON qd.course_section_id = ll.course_section_id
           AND qd.instance = ll.instance
           AND ll.instance = v_instance
           AND ll.term_code = rec.term_code
           AND ll.partition = v_partition
          LEFT JOIN zcanvas_data.quiz_submissions ceq
            ON ceq.instance = qd.instance
           AND ceq.quiz_id = qd.quiz_id
           AND ceq.user_id = qd.user_id
           AND ceq.submission_id = qd.submission_id
         WHERE 1 = 1
           AND (coalesce(ceq.workflow_state, 'X') = 'deleted' -- but no longer exists on source
               OR ceq.id IS NULL)) src;
v_count       := SQL%ROWCOUNT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'DELETE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
MERGE INTO utl_d_lms.student_quiz_answers tgt
USING (SELECT gtt.control_state,
              gtt.course_section_id,
              gtt.user_id,
              gtt.quiz_id,
              gtt.assignment_id,
              gtt.assignment_group_id,
              gtt.question_id,
              gtt.answer_id,
              gtt.correct,
              gtt.points,
              gtt.updated_date,
              gtt.workflow_state,
              gtt.instance,
              gtt.activity_date,
              gtt.submission_id,
              gtt.term_code,
              gtt.quiz_version,
              gtt.started_date,
              gtt.finished_date,
              gtt.end_date,
              gtt.quiz_score,
              gtt.quiz_points_possible
         FROM utl_d_lms.student_quiz_answers_gtt gtt
        WHERE 1 = 1
          AND gtt.instance = v_instance
          AND gtt.term_code = rec.term_code
          AND gtt.control_state IN ('INSERT', 'UPDATE')) src
ON (tgt.instance = src.instance AND tgt.course_section_id = src.course_section_id AND tgt.user_id = src.user_id AND tgt.quiz_id = src.quiz_id AND tgt.question_id = src.question_id AND tgt.answer_id = src.answer_id)
WHEN MATCHED THEN
UPDATE
   SET tgt.assignment_id        = src.assignment_id,
       tgt.assignment_group_id  = src.assignment_group_id,
       tgt.correct              = src.correct,
       tgt.points               = src.points,
       tgt.updated_date         = src.updated_date,
       tgt.workflow_state       = src.workflow_state,
       tgt.activity_date        = src.activity_date,
       tgt.submission_id        = src.submission_id,
       tgt.term_code            = src.term_code,
       tgt.quiz_version         = src.quiz_version,
       tgt.started_date         = src.started_date,
       tgt.finished_date        = src.finished_date,
       tgt.end_date             = src.end_date,
       tgt.quiz_score           = src.quiz_score,
       tgt.quiz_points_possible = src.quiz_points_possible
WHEN NOT MATCHED THEN
INSERT
(course_section_id,
 user_id,
 quiz_id,
 assignment_id,
 assignment_group_id,
 question_id,
 answer_id,
 correct,
 points,
 updated_date,
 workflow_state,
 instance,
 activity_date,
 submission_id,
 term_code,
 quiz_version,
 started_date,
 finished_date,
 end_date,
 quiz_score,
 quiz_points_possible)
VALUES
(src.course_section_id,
 src.user_id,
 src.quiz_id,
 src.assignment_id,
 src.assignment_group_id,
 src.question_id,
 src.answer_id,
 src.correct,
 src.points,
 src.updated_date,
 src.workflow_state,
 src.instance,
 src.activity_date,
 src.submission_id,
 src.term_code,
 src.quiz_version,
 src.started_date,
 src.finished_date,
 src.end_date,
 src.quiz_score,
 src.quiz_points_possible);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- DML DELETES
DELETE FROM utl_d_lms.student_quiz_answers tab
 WHERE EXISTS (SELECT 1
          FROM utl_d_lms.student_quiz_answers_gtt gtt
         WHERE 1 = 1
           AND gtt.instance = v_instance
           AND gtt.control_state = 'DELETE'
           AND tab.instance = gtt.instance
           AND tab.course_section_id = gtt.course_section_id
           AND tab.user_id = gtt.user_id
           AND tab.quiz_id = gtt.quiz_id
           AND tab.question_id = gtt.question_id
           AND tab.answer_id = gtt.answer_id);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'DELETE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
end loop; -- c_terms
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
---      07-05-2021  WGRIFFITH2  --Initial release
---      10-12-2021  WGRIFFITH2  --LUOA CD1 -> CD2
---      09-19-2022  WGRIFFITH2  --REMOVING FROM SCHEDULE. Only runs ad-hoc now
---      10-19-2022  WGRIFFITH2  --ADDING BACK SCHEDULE. Only select courses
---      12-27-2022  WGRIFFITH2  --performance improvements
---      05-22-2023  WGRIFFITH2  --performance improvements; adding updated_date and term_code
---      09-20-2023  WGRIFFITH2  --opening it up to all courses, because we need to get CRC data for all courses; limits/filters need to happen more downstream
---      09-27-2023  WGRIFFITH2  --adding new fields
------------------------------------------------------------------------------------------------*/
END etl_lms_student_quiz_answers;

procedure etl_lms_quiz_questions_answers (jobnumber number, processid varchar2, processname varchar2, inst varchar2, nmbr number) is
/*
Table: utl_d_lms.quiz_questions_answers

Primary Keys: SURROGATE_ID

Unique index: QUIZ_ID, COURSE_SECTION_ID, QUESTION_ID, ANSWER_ID, INSTANCE

Purpose: Table that holds data for all quiz questions and answers in CANVAS. Used for staging only. Truncated regularly

Conditions:

Dependencies:  utl_d_lms.quizzes
*/
--DECLARE
v_etl_date DATE := SYSDATE;
v_msg      VARCHAR2(2000);
v_instance VARCHAR2(50) := upper(inst); -- inst from the jams job; used for determining instance
v_partition NUMBER := nmbr; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_lms_quiz_questions_answers';
CURSOR c_terms IS
-- Run current terms
SELECT terms.term_code,
       terms.start_date,
       terms.end_date,
       terms.group_code
  FROM zbtm.terms_by_group_v terms
 WHERE 1 = 1
   AND terms.group_code IN ('STD', 'MED', 'ACD')
   -- controls what terms run for which instances (only)
   AND ((terms.group_code = 'STD' AND SYSDATE BETWEEN terms.start_date - 7 AND terms.end_date + 7 AND v_instance = 'L2CAN') OR
       (terms.group_code = 'MED' AND SYSDATE BETWEEN terms.start_date - 7 AND terms.end_date + 7 AND v_instance = 'L2CAN') OR
       (terms.group_code = 'ACD' AND SYSDATE BETWEEN terms.start_date - 7 AND terms.end_date + 8 AND v_instance = 'ACCAN'))
   AND (to_char(SYSDATE, 'HH24') BETWEEN '00' AND '08') -- *outside of high demand*
UNION
-- Run non-current terms - **ONLY RUN DURING NON-BUSINESS HOURS** 
SELECT terms.term_code,
       terms.start_date,
       terms.end_date,
       terms.group_code
  FROM zbtm.terms_by_group_v terms
 WHERE 1 = 1
   AND terms.group_code IN ('STD', 'MED', 'ACD')
   AND ((terms.group_code = 'STD' AND SYSDATE BETWEEN terms.start_date - 180 AND terms.end_date + 180 AND v_instance = 'L2CAN') OR
       (terms.group_code = 'MED' AND SYSDATE BETWEEN terms.start_date - 180 AND terms.end_date + 180 AND v_instance = 'L2CAN') OR
       (terms.group_code = 'ACD' AND SYSDATE BETWEEN terms.start_date - 180 AND terms.end_date + 365 AND v_instance = 'ACCAN'))
   AND (to_char(SYSDATE, 'HH24') BETWEEN '18' AND '23') -- *outside of high demand*
UNION ALL
-- Run non-banner terms - **ONLY RUN DURING NON-BUSINESS HOURS** 
SELECT '000000' AS term_code,
       trunc(SYSDATE - 365) AS start_date,
       trunc(SYSDATE + 365) AS end_date,
       '000' AS group_code
  FROM dual
 WHERE 1 = 1
   AND v_instance = 'L2CAN' -- only non term instance  
   AND (to_char(SYSDATE, 'HH24') BETWEEN '18' AND '23') -- *outside of high demand*
 ORDER BY group_code DESC,
          start_date DESC;
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
v_msg     := 'START - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- !!! GLOBAL TEMP TABLE - PRESERVES ROWS ON COMMIT !!!
-- multiple runs per session with cause unique constraint (constraint_name) violated
-- truncate table quiz_questions_answers_gtt;
INSERT INTO utl_d_lms.quiz_questions_answers_gtt
(control_state,
 course_section_id,
 quiz_id,
 user_id,
 assignment_id,
 assignment_group_id,
 question_id,
 answer_id,
 question_title,
 question_type,
 question,
 answer,
 weight,
 workflow_state,
 instance,
 activity_date,
 assessment_question_bank_id,
 updated_date,
 term_code,
 title,
 position,
 correct_comments,
 incorrect_comments,
 points_possible)
SELECT CASE
       WHEN src.course_section_id IS NOT NULL
            AND tgt.course_section_id IS NULL THEN
        'INSERT' -- new record to source, add to table
       WHEN src.course_section_id IS NOT NULL
            AND tgt.course_section_id IS NOT NULL THEN
        'UPDATE' -- record exists in both places
       END AS control_state,
       src.course_section_id,
       src.quiz_id,
       src.user_id,
       src.assignment_id,
       src.assignment_group_id,
       src.question_id,
       src.answer_id,
       src.question_title,
       src.question_type,
       src.question,
       src.answer,
       src.weight,
       src.workflow_state,
       src.instance,
       v_etl_date AS activity_date,
       src.assessment_question_bank_id,
       src.updated_date,
       src.term_code,
       src.title,
       src.position,
       src.correct_comments,
       src.incorrect_comments,
       src.points_possible
  FROM (SELECT qd.course_section_id,
               qd.quiz_id,
               se.user_id,
               qd.assignment_id,
               qd.assignment_group_id,
               ceqq.id AS question_id,
               coalesce(ceqq.answer_id, -1) AS answer_id,
               caq.assessment_question_bank_id AS assessment_question_bank_id,
               coalesce(caq.name, ceqq.name) AS question_title,
               ceqq.question_type AS question_type,
               regexp_replace(ceqq.question_text, '<[^>]+>', '') AS question,
               ceqq.answer_text AS answer,
               ceqq.answer_weight AS weight,
               ceqq.workflow_state,
               se.instance AS instance,
               ceqq.updated_at AS updated_date,
               se.term_code,
               qd.title,
               ceqq.position,
               ceqq.correct_comments,
               ceqq.incorrect_comments,
               ceqq.points_possible
           FROM utl_d_lms.student_enrollments se
          JOIN utl_d_lms.quizzes qd
            ON qd.instance = se.instance
           AND qd.course_section_id = se.course_section_id
           AND ((qd.title = 'End of Course Survey') -- TESTING / POC --PRJTASK0698254
               OR (qd.title = 'Course Requirements Checklist') -- WE ARE LOOKING FOR SPECIFIC THINGS TO LIMIT THE SCOPE AND SIZE OF THE DATA
               -- WE ARE LOOKING FOR SPECIFIC THINGS TO LIMIT THE SCOPE AND SIZE OF THE DATA
               OR (se.course_section_id IN (570780, 618673)) -- added for Bill - PRJTASK0688083
               OR (se.subj_code || se.crse_numb IN -- ** ONLY COURSES THAT WE ARE TRACKING QUIZ DATA**
               ('BIBL104', 'BIBL105', 'BIBL110', 'CINE101', 'EDUC201', 'ENGL102', 'ENGL215', -- added for Nicholas TKT2835857
                     'HIUS222', 'INFT110', 'INQR101', 'INQR102', 'MATH128', 'PHIL201', 'RSCH201', -- added for Nicholas TKT2835857
                     'THEO201', 'THEO202', 'UNIV101', 'UNIV104', -- added for Nicholas TKT2835857
                     'EDAS645', 'EDAS740', 'EDUC305', 'EDUC360', 'EDLC504', 'EDLC704', 'COSC604', -- added for Nicholas TKT2835857
                     'PSYC510', 'PSYC515' -- add for Ethan TKT3033356
                     )))
           AND se.instance = v_instance
           AND se.term_code = rec.term_code
           AND se.partition = v_partition
          JOIN utl_d_lms.student_quiz_answers sqa
            ON sqa.instance = se.instance
           AND sqa.course_section_id = se.course_section_id
           AND sqa.quiz_id = qd.quiz_id
           AND sqa.user_id = se.user_id
          JOIN (SELECT qq.*,
                      json_value(qq.question_data, '$.name') AS NAME,
                      json_value(qq.question_data, '$.question_type') AS question_type,
                      json_value(qq.question_data, '$.question_text') AS question_text,
                      json_value(qq.question_data, '$.correct_comments') AS correct_comments,
                      json_value(qq.question_data, '$.incorrect_comments') AS incorrect_comments,
                      to_number(json_value(qq.question_data, '$.points_possible')) AS points_possible,
                      jt.weight AS answer_weight,
                      jt.id AS answer_id,
                      jt.text AS answer_text
                 FROM zcanvas_data.quiz_questions qq,
                      json_table(json_value(qq.question_data, '$.answers'), '$[*]' columns(weight NUMBER path '$.weight', migration_id VARCHAR2(100) path '$.migration_id', id NUMBER path '$.id', text VARCHAR2(1000) path '$.text')) jt
                WHERE 1 = 1
                  AND nvl(qq.workflow_state, 'X') <> 'deleted') ceqq
            ON qd.instance = ceqq.instance
           AND qd.quiz_id = ceqq.quiz_id
           AND ceqq.answer_id = sqa.answer_id
           AND ceqq.id = sqa.question_id
          LEFT JOIN zcanvas_data.assessment_questions caq
            ON ceqq.instance = caq.instance
           AND ceqq.assessment_question_id = caq.id
         WHERE 1 = 1) src
  LEFT JOIN utl_d_lms.quiz_questions_answers tgt
    ON tgt.instance = src.instance
   AND tgt.course_section_id = src.course_section_id
   AND tgt.quiz_id = src.quiz_id
   AND tgt.user_id = src.user_id
   AND tgt.question_id = src.question_id
   AND tgt.answer_id = src.answer_id
 WHERE 1 = 1 -- get anything more recent or new
   AND (src.updated_date > tgt.updated_date OR tgt.updated_date IS NULL);
v_count       := SQL%ROWCOUNT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
INSERT INTO utl_d_lms.quiz_questions_answers_gtt
(control_state,
 course_section_id,
 quiz_id,
 user_id,
 assignment_id,
 assignment_group_id,
 question_id,
 answer_id,
 question_title,
 question_type,
 question,
 answer,
 weight,
 workflow_state,
 instance,
 activity_date,
 assessment_question_bank_id,
 updated_date,
 term_code,
 title,
 position)
SELECT src.control_state,
       src.course_section_id,
       src.quiz_id,
       src.user_id,
       src.assignment_id,
       src.assignment_group_id,
       src.question_id,
       src.answer_id,
       src.question_title,
       src.question_type,
       src.question,
       src.answer,
       src.weight,
       src.workflow_state,
       src.instance,
       src.activity_date,
       src.assessment_question_bank_id,
       src.updated_date,
       src.term_code,
       src.title,
       src.position
  FROM ( -- ALL INSTANCES
        SELECT 'DELETE' AS control_state,
                ll.course_section_id,
                ll.instance,
                ll.term_code,
                qd.quiz_id,
                qd.user_id,
                qd.assignment_id,
                qd.assignment_group_id,
                qd.question_id,
                qd.answer_id,
                qd.question_title,
                qd.question_type,
                qd.question,
                qd.answer,
                qd.weight,
                qd.workflow_state,
                qd.activity_date,
                qd.assessment_question_bank_id,
                qd.updated_date,
                qd.title,
                qd.position
          FROM utl_d_lms.quiz_questions_answers qd -- still exists on target
          JOIN utl_d_lms.lms_link ll
            ON qd.course_section_id = ll.course_section_id
           AND qd.instance = ll.instance
           AND ll.instance = v_instance
           AND ll.term_code = rec.term_code
           AND ll.partition = v_partition
          LEFT JOIN zcanvas_data.quiz_questions ceq
            ON ceq.instance = qd.instance
           AND ceq.id = qd.quiz_id
         WHERE 1 = 1
           AND (coalesce(ceq.workflow_state, 'X') = 'deleted' -- but no longer exists on source
               OR ceq.id IS NULL)) src;
v_count       := SQL%ROWCOUNT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'DELETE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
MERGE INTO utl_d_lms.quiz_questions_answers tgt
USING (SELECT gtt.course_section_id,
              gtt.quiz_id,
              gtt.user_id,
              gtt.assignment_id,
              gtt.assignment_group_id,
              gtt.question_id,
              gtt.answer_id,
              gtt.question_title,
              gtt.question_type,
              gtt.question,
              gtt.answer,
              gtt.weight,
              gtt.workflow_state,
              gtt.instance,
              gtt.activity_date,
              gtt.assessment_question_bank_id,
              gtt.updated_date,
              gtt.term_code,
              gtt.title,
              gtt.position,
              gtt.correct_comments,
              gtt.incorrect_comments,
              gtt.points_possible
         FROM utl_d_lms.quiz_questions_answers_gtt gtt
        WHERE 1 = 1
          AND gtt.instance = v_instance
          AND gtt.term_code = rec.term_code
          AND gtt.control_state IN ('INSERT', 'UPDATE')) src
ON (tgt.instance = src.instance AND tgt.course_section_id = src.course_section_id AND tgt.quiz_id = src.quiz_id AND tgt.user_id = src.user_id AND tgt.question_id = src.question_id AND tgt.answer_id = src.answer_id)
WHEN MATCHED THEN
UPDATE
   SET tgt.assignment_id               = src.assignment_id,
       tgt.assignment_group_id         = src.assignment_group_id,
       tgt.question_title              = src.question_title,
       tgt.question_type               = src.question_type,
       tgt.question                    = src.question,
       tgt.answer                      = src.answer,
       tgt.weight                      = src.weight,
       tgt.workflow_state              = src.workflow_state,
       tgt.activity_date               = src.activity_date,
       tgt.assessment_question_bank_id = src.assessment_question_bank_id,
       tgt.updated_date                = src.updated_date,
       tgt.term_code                   = src.term_code,
       tgt.title                       = src.title,
       tgt.position                    = src.position,
       tgt.correct_comments            = src.correct_comments,
       tgt.incorrect_comments          = src.incorrect_comments,
       tgt.points_possible             = src.points_possible
WHEN NOT MATCHED THEN
INSERT
(course_section_id,
 quiz_id,
 user_id,
 assignment_id,
 assignment_group_id,
 question_id,
 answer_id,
 question_title,
 question_type,
 question,
 answer,
 weight,
 workflow_state,
 instance,
 activity_date,
 assessment_question_bank_id,
 updated_date,
 term_code,
 title,
 position,
 correct_comments,
 incorrect_comments,
 points_possible)
VALUES
(src.course_section_id,
 src.quiz_id,
 src.user_id,
 src.assignment_id,
 src.assignment_group_id,
 src.question_id,
 src.answer_id,
 src.question_title,
 src.question_type,
 src.question,
 src.answer,
 src.weight,
 src.workflow_state,
 src.instance,
 src.activity_date,
 src.assessment_question_bank_id,
 src.updated_date,
 src.term_code,
 src.title,
 src.position,
 src.correct_comments,
 src.incorrect_comments,
 src.points_possible);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- DML DELETES
DELETE FROM utl_d_lms.quiz_questions_answers tab
 WHERE EXISTS (SELECT 1
          FROM utl_d_lms.quiz_questions_answers_gtt gtt
         WHERE 1 = 1
           AND gtt.instance = v_instance
           AND gtt.control_state = 'DELETE'
           AND tab.instance = gtt.instance
           AND tab.course_section_id = gtt.course_section_id
           AND tab.quiz_id = gtt.quiz_id
           AND tab.user_id = gtt.user_id
           AND tab.question_id = gtt.question_id
           AND tab.answer_id = gtt.answer_id);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'DELETE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
end loop; -- c_terms
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
---      07-05-2021  WGRIFFITH2  --Initial release
---      10-12-2021  WGRIFFITH2  --LUOA CD1 -> CD2
---      09-19-2022  WGRIFFITH2  --REMOVING FROM SCHEDULE. Only runs ad-hoc now
---      10-19-2022  WGRIFFITH2  --ADDING BACK SCHEDULE. Only select courses
---      12-27-2022  WGRIFFITH2  --performance improvements
---      05-22-2023  WGRIFFITH2  --performance improvements; adding updated_date and term_code
---      09-20-2023  WGRIFFITH2  --opening it up to all courses, because we need to get CRC data for all courses; limits/filters need to happen more downstream
---      09-28-2023  WGRIFFITH2  --major update - adding the user_id to get the specific question and answer for the users
------------------------------------------------------------------------------------------------*/
END etl_lms_quiz_questions_answers;
procedure etl_lms_quizzes (jobnumber number, processid varchar2, processname varchar2, inst varchar2, nmbr number) is
/*
Table: utl_d_lms.quizzes

Primary Keys: SURROGATE_ID

Unique index: QUIZ_ID, COURSE_SECTION_ID, INSTANCE

Purpose: Table that holds all meta data for all quizzes in CANVAS

Conditions:

Dependencies:  utl_d_lms.lms_link
*/
--DECLARE
v_etl_date DATE := SYSDATE;
v_msg      VARCHAR2(2000);
v_instance VARCHAR2(50) := upper(inst); -- inst from the jams job; used for determining instance
v_partition NUMBER := nmbr; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_lms_quizzes';
CURSOR c_terms IS
-- Run current terms
SELECT terms.term_code,
       terms.start_date,
       terms.end_date,
       terms.group_code
  FROM zbtm.terms_by_group_v terms
 WHERE 1 = 1
   AND terms.group_code IN ('STD', 'MED', 'ACD')
   -- controls what terms run for which instances (only)
   AND ((terms.group_code = 'STD' AND SYSDATE BETWEEN terms.start_date - 7 AND terms.end_date + 7 AND v_instance = 'L2CAN') OR
       (terms.group_code = 'MED' AND SYSDATE BETWEEN terms.start_date - 7 AND terms.end_date + 7 AND v_instance = 'L2CAN') OR
       (terms.group_code = 'ACD' AND SYSDATE BETWEEN terms.start_date - 7 AND terms.end_date + 8 AND v_instance = 'ACCAN'))
   AND (to_char(SYSDATE, 'HH24') BETWEEN '00' AND '08') -- *outside of high demand*
UNION
-- Run non-current terms - **ONLY RUN DURING NON-BUSINESS HOURS** 
SELECT terms.term_code,
       terms.start_date,
       terms.end_date,
       terms.group_code
  FROM zbtm.terms_by_group_v terms
 WHERE 1 = 1
   AND terms.group_code IN ('STD', 'MED', 'ACD')
   AND ((terms.group_code = 'STD' AND SYSDATE BETWEEN terms.start_date - 180 AND terms.end_date + 180 AND v_instance = 'L2CAN') OR
       (terms.group_code = 'MED' AND SYSDATE BETWEEN terms.start_date - 180 AND terms.end_date + 180 AND v_instance = 'L2CAN') OR
       (terms.group_code = 'ACD' AND SYSDATE BETWEEN terms.start_date - 180 AND terms.end_date + 365 AND v_instance = 'ACCAN'))
   AND (to_char(SYSDATE, 'HH24') BETWEEN '18' AND '23') -- *outside of high demand*
UNION ALL
-- Run non-banner terms - **ONLY RUN DURING NON-BUSINESS HOURS** 
SELECT '000000' AS term_code,
       trunc(SYSDATE - 365) AS start_date,
       trunc(SYSDATE + 365) AS end_date,
       '000' AS group_code
  FROM dual
 WHERE 1 = 1
   AND v_instance = 'L2CAN' -- only non term instance  
   AND (to_char(SYSDATE, 'HH24') BETWEEN '18' AND '23') -- *outside of high demand*
 ORDER BY group_code DESC,
          start_date DESC;
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
v_msg     := 'START - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- !!! GLOBAL TEMP TABLE - PRESERVES ROWS ON COMMIT !!!
-- multiple runs per session with cause unique constraint (constraint_name) violated
-- truncate table quizzes_GTT;
INSERT INTO utl_d_lms.quizzes_gtt
(control_state,
 course_section_id,
 quiz_id,
 assignment_id,
 assignment_group_id,
 title,
 submission_types,
 scoring_policy,
 show_correct_answers,
 show_correct_answers_last_attempt,
 shuffle_answers,
 points_possible,
 time_limit,
 allowed_attempts,
 question_count,
 due_date,
 workflow_state,
 instance,
 activity_date,
 updated_date,
 term_code)
SELECT CASE
       WHEN src.course_section_id IS NOT NULL
            AND tgt.course_section_id IS NULL THEN
        'INSERT' -- new record to source, add to table
       WHEN src.course_section_id IS NOT NULL
            AND tgt.course_section_id IS NOT NULL THEN
        'UPDATE' -- record exists in both places
       END AS control_state,
       src.course_section_id,
       src.quiz_id,
       src.assignment_id,
       src.assignment_group_id,
       src.title,
       src.submission_types,
       src.scoring_policy,
       src.show_correct_answers,
       src.show_correct_answers_last_attempt,
       src.shuffle_answers,
       src.points_possible,
       src.time_limit,
       src.allowed_attempts,
       src.question_count,
       src.due_date,
       src.workflow_state,
       src.instance,
       v_etl_date AS activity_date,
       src.updated_date,
       src.term_code
  FROM (SELECT ll.course_section_id,
               ceq.id AS quiz_id,
               ceq.assignment_id,
               ceq.assignment_group_id,
               ceq.title,
               coalesce(ceq.quiz_type, 'none') AS submission_types,
               ceq.scoring_policy,
               ceq.show_correct_answers,
               ceq.show_correct_answers_last_attempt,
               ceq.shuffle_answers,
               ceq.points_possible,
               ceq.time_limit,
               ceq.allowed_attempts,
               ceq.question_count,
               ceq.due_at AS due_date,
               ceq.workflow_state,
               ll.instance AS instance,
               ceq.updated_at AS updated_date,
               ll.term_code
          FROM zcanvas_data.quizzes ceq
          JOIN utl_d_lms.lms_link ll
            ON ceq.context_id = ll.course_id
           AND ceq.instance = ll.instance
           AND ll.instance = v_instance
           AND ll.term_code = rec.term_code
           AND ll.partition = v_partition
         WHERE 1 = 1
           AND coalesce(ceq.workflow_state, 'X') <> 'deleted') src
  LEFT JOIN utl_d_lms.quizzes tgt
    ON tgt.instance = src.instance
   AND tgt.course_section_id = src.course_section_id
   AND tgt.quiz_id = src.quiz_id
 WHERE 1 = 1 -- get anything more recent or new
   AND (src.updated_date > tgt.updated_date OR tgt.updated_date IS NULL);
v_count       := SQL%ROWCOUNT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
INSERT INTO utl_d_lms.quizzes_gtt
(control_state,
 course_section_id,
 quiz_id,
 assignment_id,
 assignment_group_id,
 title,
 submission_types,
 scoring_policy,
 show_correct_answers,
 show_correct_answers_last_attempt,
 shuffle_answers,
 points_possible,
 time_limit,
 allowed_attempts,
 question_count,
 due_date,
 workflow_state,
 instance,
 activity_date,
 updated_date,
 term_code)
SELECT src.control_state,
       src.course_section_id,
       src.quiz_id,
       src.assignment_id,
       src.assignment_group_id,
       src.title,
       src.submission_types,
       src.scoring_policy,
       src.show_correct_answers,
       src.show_correct_answers_last_attempt,
       src.shuffle_answers,
       src.points_possible,
       src.time_limit,
       src.allowed_attempts,
       src.question_count,
       src.due_date,
       src.workflow_state,
       src.instance,
       v_etl_date AS activity_date,
       src.updated_date,
       src.term_code
  FROM ( -- ALL INSTANCES
        SELECT 'DELETE' AS control_state,
         ll.course_section_id,
         qd.quiz_id,
         qd.assignment_id,
         qd.assignment_group_id,
         qd.title,
         qd.submission_types,
         qd.scoring_policy,
         qd.show_correct_answers,
         qd.show_correct_answers_last_attempt,
         qd.shuffle_answers,
         qd.points_possible,
         qd.time_limit,
         qd.allowed_attempts,
         qd.question_count,
         qd.due_date,
         qd.workflow_state,
         ll.instance AS instance,
         qd.updated_date,
         ll.term_code
          FROM utl_d_lms.quizzes qd -- still exists on target
          JOIN utl_d_lms.lms_link ll
            ON qd.course_section_id = ll.course_section_id
           AND qd.instance = ll.instance
           AND ll.instance = v_instance
           AND ll.term_code = rec.term_code
           AND ll.partition = v_partition
          LEFT JOIN zcanvas_data.quizzes ceq
            ON ceq.instance = qd.instance
           AND ceq.context_id = ll.course_id
           AND ceq.id = qd.quiz_id
         WHERE 1 = 1
           AND (coalesce(ceq.workflow_state, 'X') = 'deleted' -- but no longer exists on source
               OR ceq.id IS NULL)) src;
v_count       := SQL%ROWCOUNT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'DELETE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
MERGE INTO utl_d_lms.quizzes tgt
USING (SELECT control_state,
              course_section_id,
              quiz_id,
              assignment_id,
              assignment_group_id,
              title,
              submission_types,
              scoring_policy,
              show_correct_answers,
              show_correct_answers_last_attempt,
              shuffle_answers,
              points_possible,
              time_limit,
              allowed_attempts,
              question_count,
              due_date,
              workflow_state,
              instance,
              activity_date,
              updated_date,
              term_code
         FROM utl_d_lms.quizzes_gtt gtt
        WHERE 1 = 1
          AND gtt.instance = v_instance
          AND gtt.term_code = rec.term_code
          AND gtt.control_state IN ('INSERT', 'UPDATE')) src
ON (tgt.instance = src.instance AND tgt.course_section_id = src.course_section_id AND tgt.quiz_id = src.quiz_id)
WHEN MATCHED THEN
UPDATE
   SET tgt.assignment_id                     = src.assignment_id,
       tgt.assignment_group_id               = src.assignment_group_id,
       tgt.title                             = src.title,
       tgt.submission_types                  = src.submission_types,
       tgt.scoring_policy                    = src.scoring_policy,
       tgt.show_correct_answers              = src.show_correct_answers,
       tgt.show_correct_answers_last_attempt = src.show_correct_answers_last_attempt,
       tgt.shuffle_answers                   = src.shuffle_answers,
       tgt.points_possible                   = src.points_possible,
       tgt.time_limit                        = src.time_limit,
       tgt.allowed_attempts                  = src.allowed_attempts,
       tgt.question_count                    = src.question_count,
       tgt.due_date                          = src.due_date,
       tgt.workflow_state                    = src.workflow_state,
       tgt.activity_date                     = src.activity_date,
       tgt.updated_date                      = src.updated_date,
       tgt.term_code                         = src.term_code
WHEN NOT MATCHED THEN
INSERT
(course_section_id,
 quiz_id,
 assignment_id,
 assignment_group_id,
 title,
 submission_types,
 scoring_policy,
 show_correct_answers,
 show_correct_answers_last_attempt,
 shuffle_answers,
 points_possible,
 time_limit,
 allowed_attempts,
 question_count,
 due_date,
 workflow_state,
 instance,
 activity_date,
 updated_date,
 term_code)
VALUES
(src.course_section_id,
 src.quiz_id,
 src.assignment_id,
 src.assignment_group_id,
 src.title,
 src.submission_types,
 src.scoring_policy,
 src.show_correct_answers,
 src.show_correct_answers_last_attempt,
 src.shuffle_answers,
 src.points_possible,
 src.time_limit,
 src.allowed_attempts,
 src.question_count,
 src.due_date,
 src.workflow_state,
 src.instance,
 src.activity_date,
 src.updated_date,
 src.term_code);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- DML DELETES
DELETE FROM utl_d_lms.quizzes tab
 WHERE EXISTS (SELECT 1
          FROM utl_d_lms.quizzes_gtt gtt
         WHERE 1 = 1
           AND gtt.instance = v_instance
           AND gtt.control_state = 'DELETE'
           AND tab.instance = gtt.instance
           AND tab.course_section_id = gtt.course_section_id
           AND tab.quiz_id = gtt.quiz_id);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'DELETE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
end loop; -- c_terms
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
---      07-05-2021  WGRIFFITH2  --Initial release
---      10-12-2021  WGRIFFITH2  --LUOA CD1 -> CD2
---      09-19-2022  WGRIFFITH2  --REMOVING FROM SCHEDULE. Only runs ad-hoc now
---      10-19-2022  WGRIFFITH2  --ADDING BACK SCHEDULE. Only select courses
---      12-27-2022  WGRIFFITH2  --performance improvements
---      05-22-2023  WGRIFFITH2  --performance improvements; adding updated_date and term_code
---      09-20-2023  WGRIFFITH2  --opening it up to all courses, because we need to get CRC data for all courses; limits/filters need to happen more downstream
---      02-25-2025  WGRIFFITH2  --renaming quiz_dim to quizzes
------------------------------------------------------------------------------------------------*/
END etl_lms_quizzes;
procedure etl_lms_student_assignments (jobnumber NUMBER, processid VARCHAR2, processname VARCHAR2, inst varchar2, nmbr number) IS

--
-- PURPOSE: Refreshes LMS student assignment submission data per term, keeping grades, due dates, and statuses current for reporting across L2CAN and ACCAN.
--
-- TABLE: utl_d_lms.student_assignments, utl_d_lms.student_assignments_gtt
--
-- UNIQUE INDEX: INSTANCE, COURSE_SECTION_ID, ASSIGNMENT_ID, USER_ID
--
-- CONDITIONS:
-- Processes data one term_code at a time from zbtm.terms_by_group_v, constrained by instance and business-hour windows.
-- For L2CAN current STD/MED terms: includes terms where SYSDATE is within 7 days before start_date and 7 days after end_date.
-- For ACCAN current ACD terms: includes terms where SYSDATE is within 7 days before start_date and 7 days after end_date.
-- For L2CAN non-current STD/MED terms: includes terms where SYSDATE is within 180 days before start_date and 180 days after end_date; runs only 00–06 or 18–23.
-- For ACCAN non-current ACD terms: includes terms where SYSDATE is within 365 days before start_date and 365 days after end_date; runs only 00–06 or 18–23.
-- For L2CAN non-banner courses: processes synthetic term_code '000000' over SYSDATE-365 to SYSDATE+365; runs only 00–06 or 18–23.
-- Work is partitioned by se.partition = v_partition to segment processing across parallel bins.
-- Limits processing to the chosen instance: se.instance = v_instance (either 'L2CAN' or 'ACCAN') and to the current loop term: se.term_code = rec.term_code.
-- Joins assignments to enrollments by course: a.instance = se.instance and a.context_id = se.course_id.
-- Joins submissions to enrollments and assignments: s.instance = se.instance and s.course_id = se.course_id and s.user_id = se.user_id and s.assignment_id = a.id.
-- Includes only assignments that count toward final grade: a.omit_from_final_grade IS NULL.
-- Excludes deleted or unpublished assignments: a.workflow_state NOT IN ('deleted', 'unpublished').
-- Excludes assignments created by course migration cleanup: substr(coalesce(a.migration_id, 'X'), 1, 10) NOT IN ('deletedsub').
-- Includes only non-deleted submissions: s.workflow_state <> 'deleted'.
-- For ACCAN inserts/updates, ignores excused submissions entirely: s.excused IS NULL.
-- Flags records as INSERT when an enrollment exists and no matching student_assignments row exists; flags as UPDATE when both exist.
-- Determines records to insert/update only when data is new or changed: sa.updated_date IS NULL OR s.updated_at > sa.updated_date OR a.due_at <> sa.due_date OR (s.quiz_submission_id IS NOT NULL AND sa.quiz_submission_id IS NULL).
-- L2CAN due dates: due_date = coalesce(a.due_at, s.cached_due_date).
-- ACCAN due dates: due_date = coalesce(aod.due_at, a.due_at, s.cached_due_date), honoring section-level overrides (assignment_overrides) when active (aod.workflow_state <> 'deleted').
-- ACCAN populates assignment group context when available: group_name = coalesce(ag.name, 'Not Listed') and group_weight = ag.group_weight, limited to active groups (ag.workflow_state <> 'deleted').
-- L2CAN submission types prefer the submission record when present: submission_types = coalesce(s.submission_type, a.submission_types); ACCAN uses a.submission_types.
-- Points_possible is never NULL; defaults to 0: points_possible = coalesce(a.points_possible, 0).
-- Sets activity_date to the ETL run timestamp (v_etl_date) and carries through per-record workflow_state and date stamps (submitted, graded, posted, last_comment, updated).
-- L2CAN deletions: removes records when enrollment no longer exists (se.course_section_id IS NULL).
-- L2CAN deletions: removes records when the submission is deleted and GraphQL either shows it deleted or not a newer record (coalesce(gs.workflow_state, 'deleted') = 'deleted' OR s.updated_at >= gs.updated_date).
-- L2CAN deletions: removes records when the assignment is deleted or unpublished (a.workflow_state IN ('deleted', 'unpublished')).
-- L2CAN deletions: removes records associated with migration cleanup (substr(coalesce(a.migration_id, 'X'), 1, 10) IN ('deletedsub')).
-- L2CAN deletions: removes records now omitted from final grade (a.omit_from_final_grade IS NOT NULL).
-- ACCAN deletions: does NOT delete based solely on submission workflow_state; retains historical data even if submissions become 'deleted'.
-- ACCAN deletions: removes records when enrollment no longer exists (se.course_section_id IS NULL).
-- ACCAN deletions: removes records when the assignment is deleted or unpublished (a.workflow_state IN ('deleted', 'unpublished')).
-- ACCAN deletions: removes records associated with migration cleanup (substr(coalesce(a.migration_id, 'X'), 1, 10) IN ('deletedsub')).
-- ACCAN deletions: removes any excused assignments present in the table (sa.excused = 'Y').
-- Upserts into utl_d_lms.student_assignments using the business key (INSTANCE, COURSE_SECTION_ID, ASSIGNMENT_ID, USER_ID); updates existing rows and inserts new rows as needed.
-- Sets data_source = 'CDE' for all merged rows.
-- Deletes from utl_d_lms.student_assignments any rows matching keys flagged as 'DELETE' in utl_d_lms.student_assignments_gtt for the current instance and term.
--
-- URL: N/A
--DECLARE
v_etl_date    DATE := SYSDATE;
v_msg         VARCHAR2(2000);
v_instance    VARCHAR2(50) := upper(inst); -- inst from the jams job; used for determining instance
v_partition    NUMBER := nmbr; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_lms_student_assignments';
v_retry_count NUMBER := 0;
v_max_retries NUMBER := 3; -- number of retries for WAIT
v_wait_time   NUMBER := 120; -- seconds for WAIT
v_term_code   VARCHAR2(6);
CURSOR c_terms IS
-- Run current terms
SELECT terms.term_code,
       terms.start_date,
       terms.end_date,
       terms.group_code
  FROM zbtm.terms_by_group_v terms
 WHERE 1 = 1
   AND terms.group_code IN ('STD', 'MED', 'ACD')
   -- controls what terms run for which instances (only)
   AND ((terms.group_code = 'STD' AND SYSDATE BETWEEN terms.start_date - 7 AND terms.end_date + 7 AND v_instance = 'L2CAN') OR
       (terms.group_code = 'MED' AND SYSDATE BETWEEN terms.start_date - 7 AND terms.end_date + 7 AND v_instance = 'L2CAN') OR
       (terms.group_code = 'ACD' AND SYSDATE BETWEEN terms.start_date - 7 AND terms.end_date + 8 AND v_instance = 'ACCAN'))
UNION
-- Run non-current terms - **ONLY RUN DURING NON-BUSINESS HOURS** 
SELECT terms.term_code,
       terms.start_date,
       terms.end_date,
       terms.group_code
  FROM zbtm.terms_by_group_v terms
 WHERE 1 = 1
   AND terms.group_code IN ('STD', 'MED', 'ACD')
   AND ((terms.group_code = 'STD' AND SYSDATE BETWEEN terms.start_date - 180 AND terms.end_date + 180 AND v_instance = 'L2CAN') OR
       (terms.group_code = 'MED' AND SYSDATE BETWEEN terms.start_date - 180 AND terms.end_date + 180 AND v_instance = 'L2CAN') OR
       (terms.group_code = 'ACD' AND SYSDATE BETWEEN terms.start_date - 180 AND terms.end_date + 365 AND v_instance = 'ACCAN'))
   AND (to_char(SYSDATE, 'HH24') BETWEEN '18' AND '23') -- *outside of high demand*
UNION ALL
-- Run non-banner terms - **ONLY RUN DURING NON-BUSINESS HOURS** 
SELECT '000000' AS term_code,
       trunc(SYSDATE - 365) AS start_date,
       trunc(SYSDATE + 365) AS end_date,
       '000' AS group_code
  FROM dual
 WHERE 1 = 1
   AND v_instance = 'L2CAN' -- only non term instance  
   AND (to_char(SYSDATE, 'HH24') BETWEEN '18' AND '23') -- *outside of high demand*
 ORDER BY group_code DESC,
          start_date DESC;
BEGIN
-- dbms_output.enable(buffer_size => NULL);
ads_etl.set_parallel_session('Y', 4);
-- utl_d_lms.enable_trace('enable'); -- for dbms_application_info.set_module(
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_application_info.set_module(module_name => v_proc, action_name => v_msg);
dbms_application_info.set_client_info(client_info => v_job_id); -- added on 20251201 for additional logging
dbms_output.put_line(' --------- ');
FOR rec IN c_terms
LOOP
v_term_code := rec.term_code; -- setting term for better tracking when errors occur
v_count     := 0; -- reset count
v_elapsed   := round((SYSDATE - v_etl_date) * 86400);
v_msg       := 'START - ' || v_term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_application_info.set_module(module_name => v_proc, action_name => v_msg);
IF v_instance = 'L2CAN' THEN
INSERT /*+ USE_HASH(se a s) */
INTO utl_d_lms.student_assignments_gtt
(control_state,
 course_section_id,
 user_id,
 assignment_id,
 title,
 submission_types,
 lti_user_id,
 submission_id,
 quiz_submission_id,
 media_comment_id,
 media_object_id,
 attempt,
 excused,
 extra_attempts,
 score,
 points_possible,
 grade,
 grade_matches_current_submission,
 points_deducted,
 url,
 due_date,
 cached_due_date,
 submitted_date,
 graded_date,
 posted_date,
 last_comment_date,
 updated_date,
 workflow_state,
 instance,
 activity_date,
 group_name,
 group_weight,
 term_code)
SELECT control_state,
       course_section_id,
       user_id,
       assignment_id,
       title,
       submission_types,
       lti_user_id,
       submission_id,
       quiz_submission_id,
       media_comment_id,
       media_object_id,
       attempt,
       excused,
       extra_attempts,
       score,
       points_possible,
       grade,
       grade_matches_current_submission,
       points_deducted,
       url,
       due_date,
       cached_due_date,
       submitted_date,
       graded_date,
       posted_date,
       last_comment_date,
       updated_date,
       workflow_state,
       instance,
       activity_date,
       group_name,
       group_weight,
       term_code
  FROM (SELECT control_state,
               course_section_id,
               user_id,
               assignment_id,
               title,
               submission_types,
               lti_user_id,
               migration_id,
               submission_id,
               quiz_submission_id,
               media_comment_id,
               media_object_id,
               attempt,
               excused,
               extra_attempts,
               score,
               points_possible,
               grade,
               grade_matches_current_submission,
               points_deducted,
               url,
               due_date,
               cached_due_date,
               submitted_date,
               graded_date,
               posted_date,
               last_comment_date,
               updated_date,
               workflow_state,
               instance,
               activity_date,
               group_name,
               group_weight,
               term_code
          FROM (
                -- L2CAN INSTANCE FOR TERM COURSES
                SELECT CASE
                        WHEN se.course_section_id IS NOT NULL
                             AND sa.course_section_id IS NULL THEN
                         'INSERT' -- new record to source, add to table
                        WHEN se.course_section_id IS NOT NULL
                             AND sa.course_section_id IS NOT NULL THEN
                         'UPDATE' -- record exists in both places
                        END AS control_state,
                        se.course_section_id,
                        se.user_id,
                        a.id AS assignment_id,
                        a.title,
                        coalesce(s.submission_type, a.submission_types) AS submission_types,
                        s.lti_user_id,
                        a.migration_id,
                        s.id AS submission_id,
                        s.quiz_submission_id,
                        s.media_comment_id,
                        s.media_object_id,
                        s.attempt,
                        s.excused,
                        s.extra_attempts,
                        s.score,
                        coalesce(a.points_possible, 0) AS points_possible,
                        s.grade,
                        s.grade_matches_current_submission,
                        s.points_deducted,
                        s.url,
                        NULL AS comment_content, -- only first comment of instructor feedback
                        coalesce(a.due_at, s.cached_due_date) AS due_date,
                        s.cached_due_date,
                        s.submitted_at AS submitted_date,
                        s.graded_at AS graded_date,
                        s.posted_at AS posted_date,
                        s.last_comment_at AS last_comment_date,
                        s.updated_at AS updated_date,
                        s.workflow_state,
                        se.instance AS instance,
                        v_etl_date AS activity_date,
                        NULL AS group_name,
                        NULL AS group_weight,
                        se.term_code
                  FROM utl_d_lms.student_enrollments se
                  JOIN /*+ USE_NL(a) INDEX(a ASGN_IDX_01) */
                zcanvas_data.assignments a
                    ON a.instance = se.instance
                   AND a.context_id = se.course_id
                   AND se.instance = v_instance
                   AND se.partition = v_partition
                   AND se.term_code = rec.term_code
                   AND rec.term_code <> '000000' -- DO NOT REMOVE THIS LINE - HARD CODED VALUE
                   AND a.omit_from_final_grade IS NULL
                   AND a.workflow_state NOT IN ('deleted', 'unpublished')
                   AND substr(coalesce(a.migration_id, 'X'), 1, 10) NOT IN ('deletedsub')
                  JOIN /*+ USE_NL(s) INDEX(s SUBM_IDX_01) */
                zcanvas_data.submissions s
                    ON s.instance = se.instance
                   AND s.course_id = se.course_id
                   AND s.user_id = se.user_id
                   AND s.assignment_id = a.id
                   AND s.workflow_state <> 'deleted'
                  LEFT JOIN /*+ USE_NL(sa) INDEX(sa STUDENT_ASSIGNMENTS_IDX2) */
                utl_d_lms.student_assignments sa
                    ON sa.instance = se.instance
                   AND sa.course_section_id = se.course_section_id
                   AND sa.user_id = se.user_id
                   AND sa.assignment_id = a.id
                 WHERE 1 = 1 -- get anything more recent or new
                   AND ((sa.updated_date IS NULL) OR --
                       (s.updated_at > sa.updated_date) OR --
                       (a.due_at <> sa.due_date) OR --
                       (s.quiz_submission_id IS NOT NULL AND sa.quiz_submission_id IS NULL))));
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || v_term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_application_info.set_module(module_name => v_proc, action_name => v_msg);
INSERT /*+ USE_HASH(se a s) */
INTO utl_d_lms.student_assignments_gtt
(control_state,
 course_section_id,
 user_id,
 assignment_id,
 title,
 submission_types,
 lti_user_id,
 submission_id,
 quiz_submission_id,
 media_comment_id,
 media_object_id,
 attempt,
 excused,
 extra_attempts,
 score,
 points_possible,
 grade,
 grade_matches_current_submission,
 points_deducted,
 url,
 due_date,
 cached_due_date,
 submitted_date,
 graded_date,
 posted_date,
 last_comment_date,
 updated_date,
 workflow_state,
 instance,
 activity_date,
 group_name,
 group_weight,
 term_code)
SELECT control_state,
       course_section_id,
       user_id,
       assignment_id,
       title,
       submission_types,
       lti_user_id,
       submission_id,
       quiz_submission_id,
       media_comment_id,
       media_object_id,
       attempt,
       excused,
       extra_attempts,
       score,
       points_possible,
       grade,
       grade_matches_current_submission,
       points_deducted,
       url,
       due_date,
       cached_due_date,
       submitted_date,
       graded_date,
       posted_date,
       last_comment_date,
       updated_date,
       workflow_state,
       instance,
       activity_date,
       group_name,
       group_weight,
       term_code
  FROM (
        -- L2CAN INSTANCE FOR **NON**TERM COURSES
        SELECT CASE
                WHEN se.course_section_id IS NOT NULL
                     AND sa.course_section_id IS NULL THEN
                 'INSERT' -- new record to source, add to table
                WHEN se.course_section_id IS NOT NULL
                     AND sa.course_section_id IS NOT NULL THEN
                 'UPDATE' -- record exists in both places
                END AS control_state,
                se.course_section_id,
                se.user_id,
                a.id AS assignment_id,
                a.title,
                coalesce(s.submission_type, a.submission_types) AS submission_types,
                s.lti_user_id,
                s.id AS submission_id,
                s.quiz_submission_id,
                s.media_comment_id,
                s.media_object_id,
                s.attempt,
                s.excused,
                s.extra_attempts,
                s.score,
                coalesce(a.points_possible, 0) AS points_possible,
                s.grade,
                s.grade_matches_current_submission,
                s.points_deducted,
                s.url,
                NULL AS comment_content, -- only first comment of instructor feedback
                coalesce(a.due_at, s.cached_due_date) AS due_date,
                s.cached_due_date,
                s.submitted_at AS submitted_date,
                s.graded_at AS graded_date,
                s.posted_at AS posted_date,
                s.last_comment_at AS last_comment_date,
                s.updated_at AS updated_date,
                s.workflow_state,
                se.instance AS instance,
                v_etl_date AS activity_date,
                NULL AS group_name,
                NULL AS group_weight,
                se.term_code
          FROM utl_d_lms.student_enrollments se
          JOIN /*+ USE_NL(a) INDEX(a ASGN_IDX_01) */
        zcanvas_data.assignments a
            ON a.instance = se.instance
           AND a.context_id = se.course_id
           AND se.instance = v_instance
           AND se.partition = v_partition
           AND se.term_code = rec.term_code
           AND v_instance = 'L2CAN' -- DO NOT REMOVE THIS LINE - HARD CODED VALUE
           AND rec.term_code = '000000' -- DO NOT REMOVE THIS LINE - HARD CODED VALUE
           AND a.omit_from_final_grade IS NULL
           AND a.workflow_state NOT IN ('deleted', 'unpublished')
           AND substr(coalesce(a.migration_id, 'X'), 1, 10) NOT IN ('deletedsub')
          JOIN /*+ USE_NL(s) INDEX(s SUBM_IDX_01) */
        zcanvas_data.submissions s
            ON s.instance = se.instance
           AND s.course_id = se.course_id
           AND s.user_id = se.user_id
           AND s.assignment_id = a.id
           AND s.workflow_state <> 'deleted'
          LEFT JOIN /*+ USE_NL(sa) INDEX(sa STUDENT_ASSIGNMENTS_IDX2) */
        utl_d_lms.student_assignments sa
            ON sa.instance = se.instance
           AND sa.course_section_id = se.course_section_id
           AND sa.user_id = se.user_id
           AND sa.assignment_id = a.id
         WHERE 1 = 1 -- get anything more recent or new
           AND ((sa.updated_date IS NULL) OR --
               (s.updated_at > sa.updated_date) OR --
               (a.due_at <> sa.due_date) OR --
               (s.quiz_submission_id IS NOT NULL AND sa.quiz_submission_id IS NULL)));
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || v_term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_application_info.set_module(module_name => v_proc, action_name => v_msg);
INSERT /*+*/
INTO utl_d_lms.student_assignments_gtt
(control_state,
 course_section_id,
 user_id,
 assignment_id,
 title,
 submission_types,
 lti_user_id,
 submission_id,
 quiz_submission_id,
 media_comment_id,
 media_object_id,
 attempt,
 excused,
 extra_attempts,
 score,
 points_possible,
 grade,
 grade_matches_current_submission,
 points_deducted,
 url,
 due_date,
 cached_due_date,
 submitted_date,
 graded_date,
 posted_date,
 last_comment_date,
 updated_date,
 workflow_state,
 instance,
 activity_date,
 group_name,
 group_weight,
 term_code)
SELECT src.control_state,
       src.course_section_id,
       src.user_id,
       src.assignment_id,
       src.title,
       src.submission_types,
       src.lti_user_id,
       src.submission_id,
       src.quiz_submission_id,
       src.media_comment_id,
       src.media_object_id,
       src.attempt,
       src.excused,
       src.extra_attempts,
       src.score,
       src.points_possible,
       src.grade,
       src.grade_matches_current_submission,
       src.points_deducted,
       src.url,
       src.due_date,
       src.cached_due_date,
       src.submitted_date,
       src.graded_date,
       src.posted_date,
       src.last_comment_date,
       src.updated_date,
       src.workflow_state,
       src.instance,
       src.activity_date,
       src.group_name,
       src.group_weight,
       src.term_code
  FROM ( -- L2CAN INSTANCE FOR TERM COURSES
        SELECT CASE
                WHEN se.course_section_id IS NULL THEN
                 'DELETE' -- enrollment no longer exists
                WHEN coalesce(s.workflow_state, 'deleted') = 'deleted'
                     AND (coalesce(gs.workflow_state, 'deleted') = 'deleted' OR --
                          coalesce(s.updated_at, systimestamp - 365) >= coalesce(gs.updated_date, systimestamp - 366)) THEN
                 'DELETE' -- submission has been deleted, but is also not a new record found in GraphQL
                WHEN coalesce(a.workflow_state, 'deleted') IN ('deleted', 'unpublished') THEN
                 'DELETE' -- assignment has been deleted or unpublished
                WHEN substr(coalesce(a.migration_id, 'X'), 1, 10) IN ('deletedsub') THEN
                 'DELETE' -- course migration occurred and orphaned the old assignment
                WHEN a.omit_from_final_grade IS NOT NULL THEN
                 'DELETE' -- assignment omitted from final grade now
                END AS control_state,
                sa.course_section_id,
                sa.user_id,
                sa.assignment_id,
                sa.title,
                sa.submission_types,
                sa.lti_user_id,
                sa.submission_id,
                sa.quiz_submission_id,
                sa.media_comment_id,
                sa.media_object_id,
                sa.attempt,
                sa.excused,
                sa.extra_attempts,
                sa.score,
                sa.points_possible,
                sa.grade,
                sa.grade_matches_current_submission,
                sa.points_deducted,
                sa.url,
                sa.due_date,
                sa.cached_due_date,
                sa.submitted_date,
                sa.graded_date,
                sa.posted_date,
                sa.last_comment_date,
                sa.updated_date,
                sa.workflow_state,
                sa.instance,
                sa.activity_date,
                sa.group_name,
                sa.group_weight,
                sa.term_code,
                sa.data_source
          FROM utl_d_lms.student_assignments sa
          LEFT JOIN utl_d_lms.student_enrollments se
            ON se.instance = sa.instance
           AND se.course_section_id = sa.course_section_id
           AND se.user_id = sa.user_id
          LEFT JOIN zcanvas_data.submissions s
            ON sa.instance = s.instance
           AND sa.submission_id = s.id
          LEFT JOIN utl_d_lms.graph_submissions gs
            ON sa.instance = gs.instance
           AND sa.submission_id = gs.submission_id
          LEFT JOIN zcanvas_data.assignments a
            ON a.instance = se.instance
           AND a.context_id = se.course_id
           AND a.id = sa.assignment_id
         WHERE 1 = 1
           AND sa.instance = 'L2CAN' -- DO NOT REMOVE HARD CODED VALUE
           AND sa.instance = v_instance
           AND sa.term_code = rec.term_code
           AND coalesce(se.partition, v_partition) = v_partition) src
 WHERE src.control_state = 'DELETE';
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || v_term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_application_info.set_module(module_name => v_proc, action_name => v_msg);
ELSIF v_instance = 'ACCAN' THEN
INSERT /*+ USE_HASH(se a s) */
INTO utl_d_lms.student_assignments_gtt
(control_state,
 course_section_id,
 user_id,
 assignment_id,
 title,
 submission_types,
 lti_user_id,
 submission_id,
 quiz_submission_id,
 media_comment_id,
 media_object_id,
 attempt,
 excused,
 extra_attempts,
 score,
 points_possible,
 grade,
 grade_matches_current_submission,
 points_deducted,
 url,
 due_date,
 cached_due_date,
 submitted_date,
 graded_date,
 posted_date,
 last_comment_date,
 updated_date,
 workflow_state,
 instance,
 activity_date,
 group_name,
 group_weight,
 term_code)
SELECT control_state,
       course_section_id,
       user_id,
       assignment_id,
       title,
       submission_types,
       lti_user_id,
       submission_id,
       quiz_submission_id,
       media_comment_id,
       media_object_id,
       attempt,
       excused,
       extra_attempts,
       score,
       points_possible,
       grade,
       grade_matches_current_submission,
       points_deducted,
       url,
       due_date,
       cached_due_date,
       submitted_date,
       graded_date,
       posted_date,
       last_comment_date,
       updated_date,
       workflow_state,
       instance,
       activity_date,
       group_name,
       group_weight,
       term_code
  FROM (
        -- ACCAN INSTANCE FOR TERM COURSES
        SELECT CASE
                WHEN se.course_section_id IS NOT NULL
                     AND sa.course_section_id IS NULL THEN
                 'INSERT' -- new record to source, add to table
                WHEN se.course_section_id IS NOT NULL
                     AND sa.course_section_id IS NOT NULL THEN
                 'UPDATE' -- record exists in both places
                END AS control_state,
                se.course_section_id,
                se.user_id,
                a.id AS assignment_id,
                a.title,
                a.submission_types,
                s.lti_user_id,
                s.id AS submission_id,
                s.quiz_submission_id,
                s.media_comment_id,
                s.media_object_id,
                s.attempt,
                s.excused,
                s.extra_attempts,
                s.score,
                coalesce(a.points_possible, 0) AS points_possible,
                s.grade,
                s.grade_matches_current_submission,
                s.points_deducted,
                s.url,
                NULL AS comment_content, -- only first comment of instructor feedback
                coalesce(aod.due_at, a.due_at, s.cached_due_date) AS due_date,
                s.cached_due_date,
                s.submitted_at AS submitted_date,
                s.graded_at AS graded_date,
                s.posted_at AS posted_date,
                s.last_comment_at AS last_comment_date,
                s.updated_at AS updated_date,
                s.workflow_state,
                se.instance AS instance,
                v_etl_date AS activity_date,
                coalesce(ag.name, 'Not Listed') AS group_name,
                ag.group_weight,
                se.term_code AS term_code
          FROM utl_d_lms.student_enrollments se
          JOIN /*+ USE_NL(a) INDEX(a ASGN_IDX_01) */
        zcanvas_data.assignments a
            ON a.instance = se.instance
           AND a.context_id = se.course_id
           AND se.instance = v_instance
           AND se.partition = v_partition
           AND se.term_code = rec.term_code
           AND rec.term_code <> '000000' -- DO NOT REMOVE THIS LINE - HARD CODED VALUE
           AND a.omit_from_final_grade IS NULL
           AND a.workflow_state NOT IN ('deleted', 'unpublished')
           AND substr(coalesce(a.migration_id, 'X'), 1, 10) NOT IN ('deletedsub')
          JOIN /*+ USE_NL(s) INDEX(s SUBM_IDX_01) */
        zcanvas_data.submissions s
            ON s.instance = se.instance
           AND s.course_id = se.course_id
           AND s.user_id = se.user_id
           AND s.assignment_id = a.id
           AND s.workflow_state <> 'deleted'
           AND s.excused IS NULL -- ignore any excused assignments
          LEFT JOIN zcanvas_data.assignment_overrides aod -- THIS JOIN IS REQUIRED FOR LUOA DUE DATES
            ON aod.instance = a.instance
           AND aod.set_id = se.course_section_id
           AND aod.assignment_id = a.id
           AND aod.workflow_state <> 'deleted'
          LEFT JOIN zcanvas_data.assignment_groups ag
            ON ag.instance = a.instance
           AND ag.id = a.assignment_group_id
           AND ag.workflow_state <> 'deleted'
          LEFT JOIN /*+ USE_NL(sa) INDEX(sa STUDENT_ASSIGNMENTS_IDX2) */
        utl_d_lms.student_assignments sa
            ON sa.instance = se.instance
           AND sa.course_section_id = se.course_section_id
           AND sa.user_id = se.user_id
           AND sa.assignment_id = a.id
         WHERE 1 = 1 -- get anything more recent or new
           AND ((sa.updated_date IS NULL) OR --
               (s.updated_at > sa.updated_date) OR --
               (a.due_at <> sa.due_date) OR --
               (s.quiz_submission_id IS NOT NULL AND sa.quiz_submission_id IS NULL)));
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || v_term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_application_info.set_module(module_name => v_proc, action_name => v_msg);
INSERT /*+*/
INTO utl_d_lms.student_assignments_gtt
(control_state,
 course_section_id,
 user_id,
 assignment_id,
 title,
 submission_types,
 lti_user_id,
 submission_id,
 quiz_submission_id,
 media_comment_id,
 media_object_id,
 attempt,
 excused,
 extra_attempts,
 score,
 points_possible,
 grade,
 grade_matches_current_submission,
 points_deducted,
 url,
 due_date,
 cached_due_date,
 submitted_date,
 graded_date,
 posted_date,
 last_comment_date,
 updated_date,
 workflow_state,
 instance,
 activity_date,
 group_name,
 group_weight,
 term_code)
SELECT src.control_state,
       src.course_section_id,
       src.user_id,
       src.assignment_id,
       src.title,
       src.submission_types,
       src.lti_user_id,
       src.submission_id,
       src.quiz_submission_id,
       src.media_comment_id,
       src.media_object_id,
       src.attempt,
       src.excused,
       src.extra_attempts,
       src.score,
       src.points_possible,
       src.grade,
       src.grade_matches_current_submission,
       src.points_deducted,
       src.url,
       src.due_date,
       src.cached_due_date,
       src.submitted_date,
       src.graded_date,
       src.posted_date,
       src.last_comment_date,
       src.updated_date,
       src.workflow_state,
       src.instance,
       src.activity_date,
       src.group_name,
       src.group_weight,
       src.term_code
  FROM (
        -- ACCAN INSTANCE FOR TERM COURSES
        SELECT CASE
                -- !!! DO NOT DELETE ANY DELETED SUBMISSIONS FOR ACCAN !!!
                --    The workflow_state goes to deleted after a certain time, which does not
                --    allow students to go back into the course, but we need to retain the data historically
                WHEN se.course_section_id IS NULL THEN
                 'DELETE' -- enrollment no longer exists 
                WHEN coalesce(a.workflow_state, 'deleted') IN ('deleted', 'unpublished') THEN
                 'DELETE' -- assignment has been deleted or unpublished
                WHEN substr(coalesce(a.migration_id, 'X'), 1, 10) IN ('deletedsub') THEN
                 'DELETE' -- course migration occurred and orphaned the old assignment
                WHEN a.omit_from_final_grade IS NOT NULL THEN
                 'DELETE' -- assignment omitted from final grade now
                WHEN sa.excused = 'Y' THEN
                 'DELETE' -- REMOVE any excused assignments
                END AS control_state,
                sa.course_section_id,
                sa.user_id,
                sa.assignment_id,
                sa.title,
                sa.submission_types,
                sa.lti_user_id,
                sa.submission_id,
                sa.quiz_submission_id,
                sa.media_comment_id,
                sa.media_object_id,
                sa.attempt,
                sa.excused,
                sa.extra_attempts,
                sa.score,
                sa.points_possible,
                sa.grade,
                sa.grade_matches_current_submission,
                sa.points_deducted,
                sa.url,
                sa.due_date,
                sa.cached_due_date,
                sa.submitted_date,
                sa.graded_date,
                sa.posted_date,
                sa.last_comment_date,
                sa.updated_date,
                sa.workflow_state,
                sa.instance,
                sa.activity_date,
                sa.group_name,
                sa.group_weight,
                sa.term_code,
                sa.data_source
          FROM utl_d_lms.student_assignments sa
          LEFT JOIN utl_d_lms.student_enrollments se
            ON se.instance = sa.instance
           AND se.course_section_id = sa.course_section_id
           AND se.user_id = sa.user_id
          LEFT JOIN zcanvas_data.submissions s
            ON sa.instance = s.instance
           AND sa.submission_id = s.id
          LEFT JOIN zcanvas_data.assignments a
            ON a.instance = se.instance
           AND a.context_id = se.course_id
           AND a.id = sa.assignment_id
         WHERE 1 = 1
           AND sa.instance = v_instance
           AND sa.term_code = rec.term_code
           AND coalesce(se.partition, v_partition) = v_partition) src
 WHERE src.control_state = 'DELETE';
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || v_term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_application_info.set_module(module_name => v_proc, action_name => v_msg);
END IF;
-- Retry mechanism for handling deadlocks
LOOP
BEGIN
MERGE /*+*/
INTO utl_d_lms.student_assignments tgt
USING (SELECT gtt.course_section_id,
              gtt.user_id,
              gtt.assignment_id,
              gtt.title,
              gtt.submission_types,
              gtt.lti_user_id,
              gtt.submission_id,
              gtt.quiz_submission_id,
              gtt.media_comment_id,
              gtt.media_object_id,
              gtt.attempt,
              gtt.excused,
              gtt.extra_attempts,
              gtt.score,
              gtt.points_possible,
              gtt.grade,
              gtt.grade_matches_current_submission,
              gtt.points_deducted,
              gtt.url,
              gtt.due_date,
              gtt.cached_due_date,
              gtt.submitted_date,
              gtt.graded_date,
              gtt.posted_date,
              gtt.last_comment_date,
              gtt.updated_date,
              gtt.workflow_state,
              gtt.instance,
              gtt.activity_date,
              gtt.group_name,
              gtt.group_weight,
              gtt.term_code,
              'CDE' AS data_source
         FROM utl_d_lms.student_assignments_gtt gtt
        WHERE 1 = 1
          AND gtt.instance = v_instance
          AND gtt.term_code = rec.term_code
          AND gtt.control_state IN ('INSERT', 'UPDATE')) src
ON (tgt.instance = src.instance AND tgt.course_section_id = src.course_section_id AND tgt.assignment_id = src.assignment_id AND tgt.user_id = src.user_id)
WHEN MATCHED THEN
UPDATE
   SET tgt.title                            = src.title,
       tgt.submission_types                 = src.submission_types,
       tgt.lti_user_id                      = src.lti_user_id,
       tgt.submission_id                    = src.submission_id,
       tgt.quiz_submission_id               = src.quiz_submission_id,
       tgt.media_comment_id                 = src.media_comment_id,
       tgt.media_object_id                  = src.media_object_id,
       tgt.attempt                          = src.attempt,
       tgt.excused                          = src.excused,
       tgt.extra_attempts                   = src.extra_attempts,
       tgt.score                            = src.score,
       tgt.points_possible                  = src.points_possible,
       tgt.grade                            = src.grade,
       tgt.grade_matches_current_submission = src.grade_matches_current_submission,
       tgt.points_deducted                  = src.points_deducted,
       tgt.url                              = src.url,
       tgt.due_date                         = src.due_date,
       tgt.cached_due_date                  = src.cached_due_date,
       tgt.submitted_date                   = src.submitted_date,
       tgt.graded_date                      = src.graded_date,
       tgt.posted_date                      = src.posted_date,
       tgt.last_comment_date                = src.last_comment_date,
       tgt.updated_date                     = src.updated_date,
       tgt.workflow_state                   = src.workflow_state,
       tgt.activity_date                    = src.activity_date,
       tgt.group_name                       = src.group_name,
       tgt.group_weight                     = src.group_weight,
       tgt.term_code                        = src.term_code,
       tgt.data_source                      = src.data_source
WHEN NOT MATCHED THEN
INSERT
(course_section_id,
 user_id,
 assignment_id,
 title,
 submission_types,
 lti_user_id,
 submission_id,
 quiz_submission_id,
 media_comment_id,
 media_object_id,
 attempt,
 excused,
 extra_attempts,
 score,
 points_possible,
 grade,
 grade_matches_current_submission,
 points_deducted,
 url,
 due_date,
 cached_due_date,
 submitted_date,
 graded_date,
 posted_date,
 last_comment_date,
 updated_date,
 workflow_state,
 instance,
 activity_date,
 group_name,
 group_weight,
 term_code,
 data_source)
VALUES
(src.course_section_id,
 src.user_id,
 src.assignment_id,
 src.title,
 src.submission_types,
 src.lti_user_id,
 src.submission_id,
 src.quiz_submission_id,
 src.media_comment_id,
 src.media_object_id,
 src.attempt,
 src.excused,
 src.extra_attempts,
 src.score,
 src.points_possible,
 src.grade,
 src.grade_matches_current_submission,
 src.points_deducted,
 src.url,
 src.due_date,
 src.cached_due_date,
 src.submitted_date,
 src.graded_date,
 src.posted_date,
 src.last_comment_date,
 src.updated_date,
 src.workflow_state,
 src.instance,
 src.activity_date,
 src.group_name,
 src.group_weight,
 src.term_code,
 src.data_source);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || v_term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_application_info.set_module(module_name => v_proc, action_name => v_msg);
-- DML DELETES
DELETE /*+*/
FROM utl_d_lms.student_assignments tab
 WHERE EXISTS (SELECT 1
          FROM utl_d_lms.student_assignments_gtt gtt
         WHERE 1 = 1
           AND gtt.instance = v_instance
           AND gtt.term_code = rec.term_code
           AND gtt.control_state = 'DELETE'
           AND tab.instance = gtt.instance
           AND tab.course_section_id = gtt.course_section_id
           AND tab.assignment_id = gtt.assignment_id
           AND tab.user_id = gtt.user_id);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'DELETE - ' || v_term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_application_info.set_module(module_name => v_proc, action_name => v_msg);
EXIT; -- If successful, exit the retry loop
EXCEPTION
WHEN OTHERS THEN
IF SQLCODE = -60 THEN
-- Deadlock detected
v_retry_count := v_retry_count + 1;
IF v_retry_count > v_max_retries THEN
-- Log error for max retries
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := '!!!-00060: deadlock detected while waiting for resource. Max retries exceeded after ' || (v_max_retries * v_wait_time) || ' seconds for ' || v_term_code || ' - ' || v_partition || ' at ' ||
             to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
EXIT; -- Add EXIT here to break out of the loop when max retries exceeded
ELSE
-- Log retry attempt
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'Deadlock detected while waiting for resource - waiting ' || v_wait_time || ' seconds for retry attempt number ' || v_retry_count || ' for ' || v_term_code || ' - ' || v_partition || ' at ' ||
             to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'WARNING', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
dbms_lock.sleep(v_wait_time); -- Wait between retries; short wait because it will need to cycle through all the GTTs again
CONTINUE; -- Add CONTINUE to explicitly indicate loop continuation
END IF;
ELSE
-- Other errors
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200) || ' for ' || v_term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
EXIT; -- Add EXIT here to break out of the loop for non-deadlock errors
END IF;
END;
END LOOP; -- end deadlock detection
-- CLEAR GTTs on each successful loop
utl_d_lms.truncate_table(v_table_name => 'student_assignments_gtt');
dbms_output.put_line(' --ALL GTTs truncated-- ');
dbms_output.put_line(' --------- ');
END LOOP; -- c_terms
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
ads_etl.set_parallel_session('N'); -- Job is done. Turn parallelism off for this session.
dbms_application_info.set_module(module_name => v_proc, action_name => v_msg);
-- log any errors
EXCEPTION
WHEN OTHERS THEN
IF SQLCODE = -1555 THEN
-- Snapshot too old error
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := '!!!-01555: Snapshot too old error detected. Consider breaking the process into smaller batches for ' || v_term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) ||' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
ads_etl.set_parallel_session('N'); -- Job is done. Turn parallelism off for this session.
ELSIF SQLCODE = -12801 THEN
-- Parallel query server error
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := '!!!-12801: Parallel query server error. Consider reducing the degree of parallelism for ' || v_term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
ads_etl.set_parallel_session('N'); -- Job is done. Turn parallelism off for this session.
ELSE
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200) || ' for ' || v_term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
ads_etl.set_parallel_session('N'); -- Job is done. Turn parallelism off for this session.
END IF;
dbms_application_info.set_module(module_name => v_proc, action_name => v_msg);
/*--------------------------------------------CHANGE LOG----------------------------------------
VERSION  DATE        USERNAME    UPDATES
---      09-09-2020  WGRIFFITH2  --Initial release
---      09-10-2020  WGRIFFITH2  --Adding record removal
---      09-16-2020  WGRIFFITH2  --Full integration of ACCAN & LUCAN
---      10-06-2020  WGRIFFITH2  --Adding new fields to table - ATTEMPT,CACHED_DUE_DATE,EXCUSED,EXTRA_ATTEMPTS,GRADE,GRADE_MATCHES_CURRENT_SUBMISSION,LAST_COMMENT_AT,MEDIA_COMMENT_ID,MEDIA_OBJECT_ID,POINTS_DEDUCTED,QUIZ_SUBMISSION_ID,UPDATED_AT,URL
---      05-24-2021  WGRIFFITH2  --Performance updates; removing course and student detail columns
---      07-12-2021  WGRIFFITH2  --Adding the comment_content field
---      09-08-2021  WGRIFFITH2  --Adding Blackboard instance
---      09-16-2021  WGRIFFITH2  --Adding enrollment check
---      09-30-2021  WGRIFFITH2  --New parallelization tactics
---      10-12-2021  WGRIFFITH2  --LUOA CD1 -> CD2
---      11-03-2021  WGRIFFITH2  --Update to control_state
---      11-24-2021  WGRIFFITH2  --Using lms_table_bins to control the query population
---      12-13-2021  WGRIFFITH2  --Adding cd2_submission_validation to check API for anything out of sync in ETL
---      08-29-2022  WGRIFFITH2  --AND api.updated_at >= s.updated_at
---      09-06-2022  WGRIFFITH2  --adding the group_name and group_weight
---      11-09-2022  WGRIFFITH2  --major releaseCREATE INDEX STUDENT_ENROLLMENTS_IDX2 ON STUDENT_ENROLLMENTS(instance);
---      12-15-2022  WGRIFFITH2  --performance improvements now using a GTT
---      01-12-2023  WGRIFFITH2  --ACCAN only - left join to submissions table to help ID missing records from Canvas; removed student_users and szrcrse from the queries as a result of the changes
---      03-24-2023  WGRIFFITH2  --now using GraphQL to validate submissions
---      04-12-2023  WGRIFFITH2  --improvements working with GraphQL
---      04-18-2023  WGRIFFITH2  --better identification of records we need to remove from the table
---      03-06-2024  WGRIFFITH2  --temp space errors. breaking the union all up into their own statements; removing blackboard code
---      04-19-2024  WGRIFFITH2  --"excused" assignments are no longer in the table for ACCAN.
---      02-14-2025  WGRIFFITH2  -- no longer allowing NULL points possible with "coalesce(a.points_possible, 0) as points_possible"
---      03-12-2025  WGRIFFITH2  -- Adding WAIT to help with deadlocks; removing all LMS LINK dependencies; query optimization
---      03-26-2025  WGRIFFITH2  -- fixing issues with ACCAN submissions not updating related to "AND s.excused <> 'Y'" changed to "AND s.excused IS NULL -- ignore any excused assignments"
---      12-01-2025  WGRIFFITH2  -- Added error logging context including [instance], [partition], and [timestamp]
------------------------------------------------------------------------------------------------*/
-- utl_d_lms.enable_trace('disable'); -- for dbms_application_info.set_module(
END etl_lms_student_assignments;

procedure etl_lms_course_surveys(jobnumber number, processid varchar2, processname varchar2, inst varchar2, nmbr number) IS
--
-- PURPOSE: Consolidates end-of-course survey responses from multiple sources into a unified reporting table for academic performance and quality analysis.
--
-- TABLE: utl_d_lms.course_surveys
--
-- UNIQUE INDEX: INSTANCE, COURSE_SECTION_ID, SURVEY_ID, QUESTION_ID, RESPONSE_UNIQUE_ID, OPTION_ID
--
-- CONDITIONS:
-- Processes only courses linked to standard academic groups (group_code = 'STD') and valid LMS links with enrollment greater than zero.
-- Includes courses from specific part-of-term codes: R, 1A, 1B, 1C, 1D, 1J.
-- Runs only for courses whose end date has passed and within 90 days after the end date.
-- Filters LMS link records by instance = 'L2CAN' and partition = provided job parameter.
-- For ZEKITBATCH source:
--   Includes only surveys and questions tied to projects and courses in zekitbatch schema.
--   Joins raw response data where question_id matches and username maps to an active student in LMS.
--   Cleans question text by removing HTML tags, non-printable characters, and replacing special entities.
--   Excludes responses with invalid text payloads (e.g., excessive emojis) by setting text fields to NULL.
--   Includes only new rows not already present in course_surveys for the same instance, section, survey, question, response, and option.
-- For ZHALIBUT source:
--   Includes only surveys linked to sections for the current term and part-of-term being processed.
--   Requires survey responses with response_state = 'SUBMITTED'.
--   Includes questions and display order; assigns question_type = 1 for freeform responses, 3 for numeric responses.
--   Includes only responses where either a select option was chosen or a freeform text value exists.
--   Joins enrollment and student user data to ensure respondent is an active student in the section.
-- Assigns survey_source as 'ZEKITBATCH' for legacy data and 'ZHALIBUT' for current LMS data.
-- Tags questions in course_surveys_question_tags based on keyword matching (e.g., 'faculty', 'course', 'rubric') when partition = 0.
-- Processes data iteratively for each term and part-of-term combination returned by the cursor.
--
-- URL: https://reports.liberty.edu/#/site/Academics/views/EndofCourseSurveys/EndofCourseSurveyScores?:iid=1
--
--DECLARE
v_etl_date    DATE := SYSDATE;
v_msg         VARCHAR2(2000);
v_instance    VARCHAR2(50) := upper(inst); -- inst from the jams job; used for determining instance
v_partition   NUMBER := nmbr; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_lms_course_surveys';
v_term_code   VARCHAR2(6);
v_ptrm_code   VARCHAR2(2);
CURSOR c_terms IS
SELECT ll.term_code,
       ll.ptrm_code,
       MIN(ll.start_date) AS start_date,
       MAX(ll.end_date) AS end_date
  FROM zbtm.terms_by_group_v t
  JOIN utl_d_lms.lms_link ll
    ON ll.term_code = t.term_code
 WHERE 1 = 1
   AND ll.enrollment > 0
   AND ll.instance = 'L2CAN'
   AND t.group_code = 'STD'
   AND ll.ptrm_code IN ('R', '1A', '1B', '1C', '1D', '1J', 'L')
   AND (ll.ptrm_code || ll.term_code NOT IN '1J202620') -- ignore this look because of ORA-00001: unique constraint (UTL_D_LMS.COURSE_SURVEYS_UNIQUE_INDX) violated
   AND SYSDATE BETWEEN ll.end_date AND ll.end_date + 90 --start on the end date of the course; stop running 90 days afterward
   AND (to_char(SYSDATE, 'HH24') BETWEEN '00' AND '08') -- *outside of high demand* 
 GROUP BY ll.term_code,
          ll.ptrm_code
 ORDER BY end_date DESC;
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
v_term_code := rec.term_code;
v_ptrm_code := rec.ptrm_code;
v_count     := 0; -- reset count
v_elapsed   := round((SYSDATE - v_etl_date) * 86400);
v_msg       := 'START - ' || v_term_code || ' - ' || v_ptrm_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- first merge is for the old survey source data from ZEKITBATCH
MERGE /*+*/
INTO utl_d_lms.course_surveys destination
USING (SELECT src.*
         FROM (SELECT ll.course_code,
                       ll.course_sis_id,
                       ll.section_sis_id,
                       ll.course_section_id,
                       ll.term_code,
                       ll.crn,
                       ll.ptrm_code,
                       s.id AS survey_id,
                       s.title AS survey_title,
                       s.description AS survey_desc,
                       q.id AS question_id,
                       q.sequence AS question_sequence,
                       q.question_type,
                       regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(TRIM(q.text), '(<.*?>)|[^' || chr(1) || '-' || chr(127) || ']') --getting rid of non-printable ascii
                                                                                                                                , '(' || chr(38) || 'nbsp;)|[' || chr(10) || chr(9) || chr(13) || ']', ' ', 1, 0, 'i') --replacing html tags, &nbsp;, <tab>, new lines with a space
                                                                                                                 , '[ ]{2,}', ' ') --replacing mutliple spaces with a single space
                                                                                                  , chr(38) || 'amp;', '&', 1, 0, 'i') --replacing &amp; with &
                                                                                   , chr(38) || 'lt;', '<', 1, 0, 'i') --replacing &lt; with <
                                                                    , chr(38) || 'gt;', '>', 1, 0, 'i') --replacing &gt; with >
                                                     , chr(38) || 'quot;', '"', 1, 0, 'i') --replacing &quot; with "
                                      , chr(38) || 'apos;', '''', 1, 0, 'i') --replacing &apos; with '
                      AS question,
                      rd.response_unique_id,
                      rd.submit_date,
                      rd.submit_device,
                      CASE
                      WHEN rd.response_unique_id = '2517648487688115173555' -- user respose was ~1000 clapping emojis that broke the dbms_lob.substr function
                       THEN
                       NULL
                      ELSE
                       dbms_lob.substr(rd.text_answer, 3900)
                      END AS full_text_answer,
                      CASE
                      WHEN rd.response_unique_id = '2517648487688115173555' -- user respose was ~1000 clapping emojis that broke the dbms_lob.substr function
                       THEN
                       NULL
                      ELSE
                       rd.text_answer
                      END AS full_text_answer_clob,
                      rd.numeric_answer,
                      rd.username AS user_name,
                      su.pidm,
                      su.user_id,
                      nvl(o.id, 0) AS option_id,
                      o.text AS text_answer,
                      o.weight weight_answer,
                      rd.matrix_id,
                      v_instance AS instance,
                      v_etl_date AS activity_date,
                      'ZEKITBATCH' AS survey_source
                 FROM zekitbatch.surveys s
                 JOIN zekitbatch.questions q
                   ON q.survey_id = s.id
                 JOIN zekitbatch.project_surveys ps
                   ON ps.survey_id = s.id
                 JOIN zekitbatch.project_courses pc
                   ON pc.project_id = ps.project_id
                 JOIN zekitbatch.courses c
                   ON c.id = pc.course_id
                 JOIN zekitbatch.raw_data rd
                   ON rd.project_id = ps.project_id
                  AND rd.course_id = c.id
                  AND rd.question_id = q.id
                 JOIN utl_d_lms.lms_link ll -- inner join to make sure there is a valid course_sis_id from zekitbatch
                   ON ll.course_sis_id = CASE
                      WHEN regexp_like(c.unique_id, '^[0-9_]+$') THEN
                       substr(c.unique_id, 1, 11)
                      ELSE
                       c.unique_id
                      END
                  AND ll.instance = v_instance -- return only ptrm that are ending and allow for time for EOCS to trickle in
                  AND ll.partition = v_partition
                  AND ll.term_code = v_term_code
                  AND ll.ptrm_code = v_ptrm_code
                 JOIN utl_d_lms.student_users su -- inner join to make sure there is an active student from zekitbatch
                   ON su.instance = ll.instance
                  AND su.user_name = rd.username -- must join on username
                 LEFT JOIN zekitbatch.options o
                   ON o.id = rd.option_id) src
         LEFT JOIN utl_d_lms.course_surveys tgt
           ON tgt.instance = src.instance
          AND tgt.course_section_id = src.course_section_id
          AND tgt.survey_id = src.survey_id
          AND tgt.question_id = src.question_id
          AND tgt.response_unique_id = src.response_unique_id
          AND tgt.option_id = src.option_id
          AND tgt.term_code = v_term_code
          AND tgt.ptrm_code = v_ptrm_code
        WHERE tgt.response_unique_id IS NULL -- only return new rows that are not the same as source
       ) new_records
ON (destination.instance = new_records.instance AND destination.course_section_id = new_records.course_section_id AND destination.survey_id = new_records.survey_id AND destination.question_id = new_records.question_id AND destination.response_unique_id = new_records.response_unique_id AND destination.option_id = new_records.option_id)
WHEN MATCHED THEN
UPDATE
   SET destination.course_code           = new_records.course_code,
       destination.course_sis_id         = new_records.course_sis_id,
       destination.section_sis_id        = new_records.section_sis_id,
       destination.term_code             = new_records.term_code,
       destination.crn                   = new_records.crn,
       destination.ptrm_code             = new_records.ptrm_code,
       destination.user_name             = new_records.user_name,
       destination.user_id               = new_records.user_id,
       destination.pidm                  = new_records.pidm,
       destination.survey_title          = new_records.survey_title,
       destination.survey_desc           = new_records.survey_desc,
       destination.question_sequence     = new_records.question_sequence,
       destination.question_type         = new_records.question_type,
       destination.question              = new_records.question,
       destination.submit_date           = new_records.submit_date,
       destination.submit_device         = new_records.submit_device,
       destination.full_text_answer      = new_records.full_text_answer,
       destination.full_text_answer_clob = new_records.full_text_answer_clob,
       destination.text_answer           = new_records.text_answer,
       destination.numeric_answer        = new_records.numeric_answer,
       destination.weight_answer         = new_records.weight_answer,
       destination.activity_date         = new_records.activity_date,
       destination.survey_source         = new_records.survey_source
WHEN NOT MATCHED THEN
INSERT
(course_code,
 course_sis_id,
 section_sis_id,
 course_section_id,
 term_code,
 crn,
 ptrm_code,
 user_name,
 user_id,
 pidm,
 survey_id,
 survey_title,
 survey_desc,
 question_id,
 question_sequence,
 question_type,
 question,
 response_unique_id,
 submit_date,
 submit_device,
 full_text_answer,
 full_text_answer_clob,
 numeric_answer,
 option_id,
 text_answer,
 weight_answer,
 matrix_id,
 instance,
 activity_date,
 survey_source)
VALUES
(new_records.course_code,
 new_records.course_sis_id,
 new_records.section_sis_id,
 new_records.course_section_id,
 new_records.term_code,
 new_records.crn,
 new_records.ptrm_code,
 new_records.user_name,
 new_records.user_id,
 new_records.pidm,
 new_records.survey_id,
 new_records.survey_title,
 new_records.survey_desc,
 new_records.question_id,
 new_records.question_sequence,
 new_records.question_type,
 new_records.question,
 new_records.response_unique_id,
 new_records.submit_date,
 new_records.submit_device,
 new_records.full_text_answer,
 new_records.full_text_answer_clob,
 new_records.numeric_answer,
 new_records.option_id,
 new_records.text_answer,
 new_records.weight_answer,
 new_records.matrix_id,
 new_records.instance,
 new_records.activity_date,
 new_records.survey_source);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'MERGE - ' || v_term_code || ' - ' || v_ptrm_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- second merge is for the old survey source data from ZEKITBATCH
MERGE INTO utl_d_lms.course_surveys destination
USING (SELECT src.*
         FROM (SELECT
               -- enrollment & section
                se.course_code,
                se.course_sis_id,
                se.section_sis_id,
                se.course_section_id,
                se.term_code,
                se.crn,
                se.ptrm_code,
                -- student identity
                su.user_name, -- student
                se.user_id, -- student
                se.pidm, -- student
                -- survey header
                survey.id          AS survey_id,
                survey.name        AS survey_title,
                survey.description AS survey_desc,
                -- question detail
                question_response.question_id,
                qdo.display_order             AS question_sequence,
                -- Quantitative items: cs.question_type = 3 (numeric/scale responses).
                -- Qualitative items: cs.question_type = 1 (free-text comments).
                CASE
                WHEN freeform_response.val IS NOT NULL THEN
                 1
                ELSE
                 3
                END AS question_type,
                q.text AS question,
                -- response identifiers & timing
                question_response.id       AS response_unique_id,
                base_response.submitted_at AS submit_date,
                NULL                       AS submit_device, -- device not captured by source tables
                -- answer payloads
                freeform_response.val AS full_text_answer,
                to_clob(freeform_response.val) AS full_text_answer_clob,
                round(so.numeric_value, 2) AS numeric_answer,
                nvl(select_option_response.select_option_id, 0) AS option_id,
                so.display_text AS text_answer,
                round(so.numeric_value, 0) AS weight_answer,
                -- additional metadata
                0 AS matrix_id, -- matrix not utilized by current model
                se.instance AS instance, -- prefer true instance from enrollments
                SYSDATE AS activity_date,
                'ZHALIBUT' AS survey_source
               --start with all surveys
                 FROM zhalibut.survey survey
               --limit to only Course Survey data
                 JOIN zhalibut.course_survey course_survey
                   ON survey.id = course_survey.id
               --limit to only surveys that have been linked to sections
                 JOIN zhalibut.section_survey_link link
                   ON survey.id = link.course_survey_id
                  AND link.term_code = v_term_code
               --get the section classification information
                 JOIN zhalibut.section_classification_config config
                   ON config.id = link.classification_config_id
               --exclude surveys with no questions configured and get the question data
                 JOIN zhalibut.question q
                   ON course_survey.id = q.survey_id
               --get the display order
                 JOIN zhalibut.question_display_order qdo
                   ON qdo.question_id = q.id
               --left join because not all questions are select-options
                 LEFT JOIN zhalibut.select_option so
                   ON so.question_id = q.id
               --limit to only surveys with responses
               --this and the SURVEY_RESPONSE join can be changed to left joins if there is a need
                 JOIN zhalibut.course_survey_response course_survey_response
                   ON course_survey_response.term_code = link.term_code
                  AND course_survey_response.crn = link.crn
               -- enrollment join (maps respondent to section)
                 JOIN utl_d_lms.student_enrollments se
                   ON se.term_code = link.term_code
                  AND se.crn = link.crn
                  AND se.luid = course_survey_response.luid
                  AND se.term_code = v_term_code
                  AND se.ptrm_code = v_ptrm_code
               -- student user for user_name
                 JOIN utl_d_lms.student_users su
                   ON su.instance = se.instance
                  AND su.pidm = se.pidm
               -- base response metadata
                 JOIN zhalibut.survey_response base_response
                   ON base_response.id = course_survey_response.id
                  AND base_response.survey_id = survey.id
               --left join in case we change the logic to generate a response header record when the survey opens instead of on first question answered
                 LEFT JOIN zhalibut.question_response question_response
                   ON question_response.survey_response_id = course_survey_response.id
                  AND question_response.question_id = q.id
                 LEFT JOIN zhalibut.select_option_question_response select_option_response
                   ON select_option_response.question_response_id = question_response.id
                  AND so.id = select_option_response.select_option_id
                 LEFT JOIN zhalibut.freeform_question_response freeform_response
                   ON freeform_response.question_response_id = question_response.id
                WHERE base_response.response_state = 'SUBMITTED'
                  AND ((so.id IS NOT NULL AND select_option_response.select_option_id IS NOT NULL) OR freeform_response.val IS NOT NULL)) src
         LEFT JOIN utl_d_lms.course_surveys tgt
           ON tgt.instance = src.instance
          AND tgt.course_section_id = src.course_section_id
          AND tgt.survey_id = src.survey_id
          AND tgt.question_id = src.question_id
          AND tgt.response_unique_id = src.response_unique_id
          AND tgt.option_id = src.option_id
          AND tgt.term_code = v_term_code
          AND tgt.ptrm_code = v_ptrm_code
        WHERE tgt.response_unique_id IS NULL -- only return new rows that are not the same as source
       ) new_records
ON (destination.instance = new_records.instance AND destination.course_section_id = new_records.course_section_id AND destination.survey_id = new_records.survey_id AND destination.question_id = new_records.question_id AND destination.response_unique_id = new_records.response_unique_id AND destination.option_id = new_records.option_id)
WHEN MATCHED THEN
UPDATE
   SET destination.course_code           = new_records.course_code,
       destination.course_sis_id         = new_records.course_sis_id,
       destination.section_sis_id        = new_records.section_sis_id,
       destination.term_code             = new_records.term_code,
       destination.crn                   = new_records.crn,
       destination.ptrm_code             = new_records.ptrm_code,
       destination.user_name             = new_records.user_name,
       destination.user_id               = new_records.user_id,
       destination.pidm                  = new_records.pidm,
       destination.survey_title          = new_records.survey_title,
       destination.survey_desc           = new_records.survey_desc,
       destination.question_sequence     = new_records.question_sequence,
       destination.question_type         = new_records.question_type,
       destination.question              = new_records.question,
       destination.submit_date           = new_records.submit_date,
       destination.submit_device         = new_records.submit_device,
       destination.full_text_answer      = new_records.full_text_answer,
       destination.full_text_answer_clob = new_records.full_text_answer_clob,
       destination.text_answer           = new_records.text_answer,
       destination.numeric_answer        = new_records.numeric_answer,
       destination.weight_answer         = new_records.weight_answer,
       destination.activity_date         = new_records.activity_date,
       destination.survey_source         = new_records.survey_source
WHEN NOT MATCHED THEN
INSERT
(course_code,
 course_sis_id,
 section_sis_id,
 course_section_id,
 term_code,
 crn,
 ptrm_code,
 user_name,
 user_id,
 pidm,
 survey_id,
 survey_title,
 survey_desc,
 question_id,
 question_sequence,
 question_type,
 question,
 response_unique_id,
 submit_date,
 submit_device,
 full_text_answer,
 full_text_answer_clob,
 numeric_answer,
 option_id,
 text_answer,
 weight_answer,
 matrix_id,
 instance,
 activity_date,
 survey_source)
VALUES
(new_records.course_code,
 new_records.course_sis_id,
 new_records.section_sis_id,
 new_records.course_section_id,
 new_records.term_code,
 new_records.crn,
 new_records.ptrm_code,
 new_records.user_name,
 new_records.user_id,
 new_records.pidm,
 new_records.survey_id,
 new_records.survey_title,
 new_records.survey_desc,
 new_records.question_id,
 new_records.question_sequence,
 new_records.question_type,
 new_records.question,
 new_records.response_unique_id,
 new_records.submit_date,
 new_records.submit_device,
 new_records.full_text_answer,
 new_records.full_text_answer_clob,
 new_records.numeric_answer,
 new_records.option_id,
 new_records.text_answer,
 new_records.weight_answer,
 new_records.matrix_id,
 new_records.instance,
 new_records.activity_date,
 new_records.survey_source);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'MERGE - ' || v_term_code || ' - ' || v_ptrm_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
v_total_count := v_total_count + v_count;
END LOOP;
--
IF v_partition = 0 THEN
-- ONLY delete/insert if the v_partition = 0
DELETE FROM utl_d_lms.course_surveys_question_tags
 WHERE instance = v_instance
   AND instance <> 'BLACKBOARD'; -- leave any BLACKBOARD
INSERT INTO utl_d_lms.course_surveys_question_tags
(survey_id,
 survey_title,
 question_id,
 question_sequence,
 question,
 question_tag,
 activity_date,
 instance)
SELECT q.survey_id,
       surv.title AS survey_title,
       q.id question_id,
       q.sequence AS question_number,
       TRIM(to_char(regexp_replace(q.text, '(<.*?>)|[' || chr(10) || chr(9) || chr(13) || ']|[^' || chr(1) || '-' || chr(127) || ']'))) question,
       CASE
       WHEN lower(TRIM(to_char(regexp_replace(q.text, '(<.*?>)|[' || chr(10) || chr(9) || chr(13) || ']|[^' || chr(1) || '-' || chr(127) || ']')))) LIKE '%faculty%' THEN
        'Instructor'
       WHEN lower(TRIM(to_char(regexp_replace(q.text, '(<.*?>)|[' || chr(10) || chr(9) || chr(13) || ']|[^' || chr(1) || '-' || chr(127) || ']')))) LIKE '%instructor%' THEN
        'Instructor'
       WHEN lower(TRIM(to_char(regexp_replace(q.text, '(<.*?>)|[' || chr(10) || chr(9) || chr(13) || ']|[^' || chr(1) || '-' || chr(127) || ']')))) LIKE '%professor%' THEN
        'Instructor'
       WHEN lower(TRIM(to_char(regexp_replace(q.text, '(<.*?>)|[' || chr(10) || chr(9) || chr(13) || ']|[^' || chr(1) || '-' || chr(127) || ']')))) LIKE '%christian principles%' THEN
        'Instructor'
       WHEN lower(TRIM(to_char(regexp_replace(q.text, '(<.*?>)|[' || chr(10) || chr(9) || chr(13) || ']|[^' || chr(1) || '-' || chr(127) || ']')))) LIKE '%Course%' THEN
        'Course'
       WHEN lower(TRIM(to_char(regexp_replace(q.text, '(<.*?>)|[' || chr(10) || chr(9) || chr(13) || ']|[^' || chr(1) || '-' || chr(127) || ']')))) LIKE '%assignment instructions%' THEN
        'Course'
       WHEN lower(TRIM(to_char(regexp_replace(q.text, '(<.*?>)|[' || chr(10) || chr(9) || chr(13) || ']|[^' || chr(1) || '-' || chr(127) || ']')))) LIKE '%rubric%' THEN
        'Course'
       WHEN lower(TRIM(to_char(regexp_replace(q.text, '(<.*?>)|[' || chr(10) || chr(9) || chr(13) || ']|[^' || chr(1) || '-' || chr(127) || ']')))) LIKE '%textbook%' THEN
        'Course'
       WHEN lower(TRIM(to_char(regexp_replace(q.text, '(<.*?>)|[' || chr(10) || chr(9) || chr(13) || ']|[^' || chr(1) || '-' || chr(127) || ']')))) LIKE '%course%' THEN
        'Course'
       WHEN lower(TRIM(to_char(regexp_replace(q.text, '(<.*?>)|[' || chr(10) || chr(9) || chr(13) || ']|[^' || chr(1) || '-' || chr(127) || ']')))) LIKE '%timely fashion%' THEN
        'Instructor'
       WHEN lower(TRIM(to_char(regexp_replace(q.text, '(<.*?>)|[' || chr(10) || chr(9) || chr(13) || ']|[^' || chr(1) || '-' || chr(127) || ']')))) LIKE '%utilization of class time%' THEN
        'Instructor'
       WHEN lower(TRIM(to_char(regexp_replace(q.text, '(<.*?>)|[' || chr(10) || chr(9) || chr(13) || ']|[^' || chr(1) || '-' || chr(127) || ']')))) LIKE '%prevent cheating%' THEN
        'Instructor'
       WHEN lower(TRIM(to_char(regexp_replace(q.text, '(<.*?>)|[' || chr(10) || chr(9) || chr(13) || ']|[^' || chr(1) || '-' || chr(127) || ']')))) LIKE '%teaching%' THEN
        'Instructor'
       WHEN lower(TRIM(to_char(regexp_replace(q.text, '(<.*?>)|[' || chr(10) || chr(9) || chr(13) || ']|[^' || chr(1) || '-' || chr(127) || ']')))) LIKE '%book%' THEN
        'Course'
       END AS question_tag, -- specifics that dont exactly fit wildcard search
       v_etl_date,
       v_instance AS instance
  FROM zekitbatch.questions q
  JOIN (SELECT s.id,
               s.title
          FROM zekitbatch.surveys s
         WHERE lower(s.title) LIKE '%end of course survey%'
           AND s.id NOT IN (1601905, 1615134)) surv
    ON q.survey_id = surv.id;
COMMIT;
END IF;
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
/*--------------------------------------------CHANGE LOG----------------------------------------
VERSION  DATE        USERNAME    UPDATES
---      09-23-2020  WGRIFFITH2  --Initial release
---      09-24-2020  WGRIFFITH2  --Adding enrollment requirement
---      06-23-2021  WGRIFFITH2  --Combining course_surveys_question_tags proc into course_surveys
---      08-09-2021  WGRIFFITH2  --Adding Bb into the table for easier retrieval
---      05-27-2022  WGRIFFITH2  --removing Bb code;
---      01-03-2023  WGRIFFITH2  --new output
---      03-01-2023  WGRIFFITH2  --Performance updates - added row_hash; paritioning; compression
---      04-04-2023  WGRIFFITH2  --Change loop to pull based on when individual courses end; not based on sobptrm any longer
---      10-10-2023  WGRIFFITH2  --Removing hash value - missing records. Using a normal constraint method
---      05-21-2025  WGRIFFITH2  --Process in smaller batches with regular commits to avoid "snapshot too old" 
-- 20251215 - WGRIFFITH2 - Added [zhalibut.course_survey_response_reporting_view]; integrated ZHALIBUT MERGE into [etl_lms_course_surveys]
------------------------------------------------------------------------------------------------*/
END etl_lms_course_surveys;

procedure etl_lms_faculty_users(jobnumber number, processid varchar2, processname varchar2, inst varchar2, nmbr number) IS
/*
Table: utl_d_lms.faculty_users

Primary Keys: SURROGATE_ID

Unique index: USER_ID, INSTANCE

Purpose:
- Create a link for distinct faculty users between CANVAS and BANNER; includes all instances

Conditions:
- Must have been a primary for at least one course. **NOT TERM_CODE BASED**

Dependencies: utl_d_lms.lms_link;
*/
--DECLARE
v_etl_date DATE := SYSDATE;
v_msg      VARCHAR2(2000);
v_instance VARCHAR2(50) := upper(inst); -- inst from the jams job; used for determining instance
v_partition NUMBER := nmbr; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_row_max NUMBER := 100000; -- max number of rows to be processed at one time
v_count   NUMBER := 0;
v_job_id  VARCHAR2(32);
v_proc    VARCHAR2(100) := 'etl_lms_faculty_users';
-- cursors
CURSOR c1 IS
SELECT CASE
       WHEN src.user_id IS NOT NULL
            AND target.user_id IS NULL THEN
        'INSERT' -- new record to source, add to table
       WHEN src.user_id IS NOT NULL
            AND target.user_id IS NOT NULL THEN
        'UPDATE' -- record exists in both places
       WHEN src.user_id IS NULL
            AND target.user_id IS NOT NULL THEN
        'DELETE' -- no record longer exists on the source data, remove it
       END AS control_state,
       coalesce(src.user_id, target.user_id) AS user_id,
       src.pidm,
       src.luid,
       src.user_name,
       src.first_name,
       src.last_name,
       src.lu_email,
       src.workflow_state,
       coalesce(src.instance, target.instance) AS instance,
       v_etl_date AS activity_date,
       src.updated_date,
       src.last_request_date
  FROM (
        -- L2CAN
        SELECT sirasgn_pidm AS pidm,
                spriden_id AS luid,
                lower(p.unique_id) AS user_name,
                u.id AS user_id, -- users.id
                coalesce(spriden_first_name, substr(u.short_name, 1, instr(u.short_name, ' ') - 1)) AS first_name,
                coalesce(spriden_last_name, substr(u.short_name, instr(u.short_name, ' ') + 1)) AS last_name,
                stu_emal.email_address AS lu_email,
                p.workflow_state,
                u.instance,
                MAX(e.updated_at) AS updated_date,
                MAX(p.last_request_at) AS last_request_date
          FROM zcanvas_data.courses c
          JOIN zcanvas_data.enrollments e
            ON e.course_id = c.id
           AND e.instance = c.instance
           AND e.type IN ('TeacherEnrollment', 'TaEnrollment', 'DesignerEnrollment', 'ObserverEnrollment')
           AND c.workflow_state <> 'deleted'
           AND c.instance = v_instance
           AND v_instance = 'L2CAN' -- DO NOT REMOVE HARD CODED VALUE
          JOIN zcanvas_data.pseudonyms p
            ON p.user_id = e.user_id
           AND p.instance = e.instance
          JOIN zcanvas_data.users u
            ON p.user_id = u.id
           AND u.instance = p.instance
          JOIN utl_d_lms.lms_link ll
            ON ll.course_section_id = e.course_section_id
           AND ll.instance = c.instance
          JOIN saturn.sirasgn
            ON sirasgn_crn = ll.crn
           AND sirasgn_term_code = ll.term_code
           AND sirasgn.sirasgn_primary_ind = 'Y'
          JOIN saturn.spriden
            ON spriden_pidm = sirasgn_pidm
           AND spriden_change_ind IS NULL
           AND spriden_id <> 'L00981424' -- TBD
          JOIN general.gobtpac
            ON gobtpac_pidm = spriden_pidm
           AND lower(p.unique_id) = lower(gobtpac.gobtpac_external_user)
          LEFT JOIN zexec.zsavemal stu_emal
            ON stu_emal.pidm = spriden_pidm
           AND stu_emal.emal_code = 'LU'
           AND stu_emal.emal_code_rank = 1
         GROUP BY sirasgn_pidm,
                   spriden_id,
                   lower(p.unique_id),
                   u.id,
                   coalesce(spriden_first_name, substr(u.short_name, 1, instr(u.short_name, ' ') - 1)),
                   coalesce(spriden_last_name, substr(u.short_name, instr(u.short_name, ' ') + 1)),
                   stu_emal.email_address,
                   p.workflow_state,
                   u.instance
        UNION ALL
        -- ACCAN
        SELECT sirasgn_pidm AS pidm,
                spriden_id AS luid,
                lower(p.unique_id) AS user_name,
                u.id AS user_id, -- users.id
                coalesce(spriden_first_name, substr(u.short_name, 1, instr(u.short_name, ' ') - 1)) AS first_name,
                coalesce(spriden_last_name, substr(u.short_name, instr(u.short_name, ' ') + 1)) AS last_name,
                stu_emal.email_address AS lu_email,
                p.workflow_state,
                u.instance,
                MAX(e.updated_at) AS updated_date,
                MAX(p.last_request_at) AS last_request_date
          FROM zcanvas_data.courses c
          JOIN zcanvas_data.enrollments e
            ON e.course_id = c.id
           AND e.instance = c.instance
           AND e.type IN ('TeacherEnrollment', 'TaEnrollment', 'DesignerEnrollment', 'ObserverEnrollment')
           AND c.workflow_state <> 'deleted'
           AND c.instance = v_instance
           AND v_instance = 'ACCAN' -- DO NOT REMOVE HARD CODED VALUE
          JOIN zcanvas_data.pseudonyms p
            ON p.user_id = e.user_id
           AND p.instance = e.instance
          JOIN zcanvas_data.users u
            ON p.user_id = u.id
           AND u.instance = p.instance
          JOIN utl_d_lms.lms_link ll
            ON ll.course_section_id = e.course_section_id
           AND ll.instance = c.instance
          JOIN saturn.sirasgn
            ON sirasgn_crn = ll.crn
           AND sirasgn_term_code = ll.term_code
           AND sirasgn.sirasgn_primary_ind = 'Y'
          JOIN saturn.spriden
            ON spriden_pidm = sirasgn_pidm
           AND spriden_change_ind IS NULL
           AND spriden_id <> 'L00981424' -- TBD
          JOIN general.gobtpac
            ON gobtpac_pidm = spriden_pidm
           AND lower(p.unique_id) = lower(gobtpac.gobtpac_external_user)
          LEFT JOIN zexec.zsavemal stu_emal
            ON stu_emal.pidm = spriden_pidm
           AND stu_emal.emal_code = 'LU'
           AND stu_emal.emal_code_rank = 1
         GROUP BY sirasgn_pidm,
                   spriden_id,
                   lower(p.unique_id),
                   u.id,
                   coalesce(spriden_first_name, substr(u.short_name, 1, instr(u.short_name, ' ') - 1)),
                   coalesce(spriden_last_name, substr(u.short_name, instr(u.short_name, ' ') + 1)),
                   stu_emal.email_address,
                   p.workflow_state,
                   u.instance) src
-- for the control state
  FULL JOIN (SELECT fu.* FROM utl_d_lms.faculty_users fu WHERE fu.instance = v_instance) target
    ON target.instance = src.instance
   AND target.user_id = src.user_id
 WHERE 1 = 1
      -- for inserts or deletes...
   AND (((src.user_id IS NULL AND target.user_id IS NOT NULL) OR (src.user_id IS NOT NULL AND target.user_id IS NULL)) OR --
       -- for updates if any data has changed...
       (coalesce(src.pidm, -1) <> coalesce(target.pidm, -1)) OR --
       (coalesce(src.luid, 'X') <> coalesce(target.luid, 'X')) OR --
       (coalesce(src.user_name, 'X') <> coalesce(target.user_name, 'X')) OR --
       (coalesce(src.first_name, 'X') <> coalesce(target.first_name, 'X')) OR --
       (coalesce(src.last_name, 'X') <> coalesce(target.last_name, 'X')) OR --
       (coalesce(src.lu_email, 'X') <> coalesce(target.lu_email, 'X')) OR --
       (coalesce(src.last_request_date, systimestamp) <> coalesce(target.last_request_date, systimestamp)) OR --
       (coalesce(src.updated_date, systimestamp) <> coalesce(target.updated_date, systimestamp)) OR --
       (coalesce(src.workflow_state, 'X') <> coalesce(target.workflow_state, 'X')));
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
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
--
OPEN c1;
LOOP
v_count   := 0; -- reset count
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
FETCH c1 BULK COLLECT
INTO rec_input LIMIT v_row_max;
v_count := rec_input.count;
IF v_count = 0 THEN
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'SELECT - ' || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
ELSIF v_count > 0 THEN
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'SELECT - ' || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
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
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200) || ' exception raised for ' || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || round(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
CONTINUE;
END;
END LOOP;
insert_count := insert_dml.count;
update_count := update_dml.count;
delete_count := delete_dml.count;
FORALL i IN VALUES OF insert_dml -- DML INSERTS
INSERT INTO utl_d_lms.faculty_users tab
(pidm,
 luid,
 user_name,
 user_id,
 first_name,
 last_name,
 lu_email,
 workflow_state,
 instance,
 activity_date,
 updated_date,
 last_request_date)
VALUES
(rec_input(i).pidm,
 rec_input(i).luid,
 rec_input(i).user_name,
 rec_input(i).user_id,
 rec_input(i).first_name,
 rec_input(i).last_name,
 rec_input(i).lu_email,
 rec_input(i).workflow_state,
 TRIM(rec_input(i).instance),
 rec_input(i).activity_date,
 rec_input(i).updated_date,
 rec_input(i).last_request_date);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'INSERT - ' || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
FORALL i IN VALUES OF update_dml -- DML UPDATES
UPDATE utl_d_lms.faculty_users tab
   SET (pidm, luid, user_name, user_id, first_name, last_name, lu_email, workflow_state, instance, activity_date, updated_date, last_request_date) =
       (SELECT rec_input(i).pidm,
               rec_input(i).luid,
               rec_input(i).user_name,
               rec_input(i).user_id,
               rec_input(i).first_name,
               rec_input(i).last_name,
               rec_input(i).lu_email,
               rec_input(i).workflow_state,
               TRIM(rec_input(i).instance),
               rec_input(i).activity_date,
               rec_input(i).updated_date,
               rec_input(i).last_request_date
          FROM dual)
 WHERE tab.user_id = rec_input(i).user_id
   AND tab.instance = rec_input(i).instance;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'UPDATE - ' || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
FORALL i IN VALUES OF delete_dml -- DML DELETES
DELETE FROM utl_d_lms.faculty_users tab
 WHERE tab.user_id = rec_input(i).user_id
   AND tab.instance = rec_input(i).instance;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'DELETE - ' || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
END IF;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_total_count := v_total_count + rec_input.count;
EXIT WHEN(rec_input.count < v_row_max);
END LOOP;
CLOSE c1;
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
---      09-09-2020  WGRIFFITH2  --Initial release
---      09-16-2020  WGRIFFITH2  --Full integration of ACCAN & LUCAN
---      10-22-2020  WGRIFFITH2  --Adding advisors to ACCAN
---      11-30-2020  WGRIFFITH2  --UTL_P_CANVAS will be used until we get new data feed from Instructure
---      05-10-2021  WGRIFFITH2  --On CD2, facultys no longer required to have a Banner record.
---      05-24-2021  WGRIFFITH2  --Performance updates; removing course and faculty detail columns
---      10-12-2021  WGRIFFITH2  --LUOA CD1 -> CD2
---      11-09-2022  WGRIFFITH2  --major release
---      11-18-2024  WGRIFFITH2  --adding the updated_date field; fixed bad code related to this on 12/4
---      01-06-2025  WGRIFFITH2  --adding the last_request_date field
------------------------------------------------------------------------------------------------*/
END etl_lms_faculty_users;
procedure etl_lms_student_users(jobnumber number, processid varchar2, processname varchar2, inst varchar2, nmbr number) IS
/*
Table: utl_d_lms.student_users

Primary Keys: SURROGATE_ID

Unique index: USER_ID, INSTANCE

Purpose:
- Create a link for distinct student users between CANVAS and BANNER; includes all instances

Conditions:
- Must have been enrolled for at least one course. **NOT TERM_CODE BASED*

- Only students in Canvas (not Blackboard)

Dependencies: utl_d_lms.lms_link;
*/
--DECLARE
v_etl_date    DATE := SYSDATE;
v_msg         VARCHAR2(2000);
v_instance    VARCHAR2(50) := upper(inst); -- inst from the jams job; used for determining instance
v_partition    NUMBER := nmbr; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_mod         NUMBER := 5; -- number of partitions to be created
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_lms_student_users';
CURSOR c_terms IS
-- Run current terms
SELECT terms.term_code,
       terms.start_date,
       terms.end_date,
       terms.group_code
  FROM zbtm.terms_by_group_v terms
 WHERE 1 = 1
   AND terms.group_code IN ('STD', 'MED', 'ACD')
   -- controls what terms run for which instances (only)
   AND ((terms.group_code = 'STD' AND SYSDATE BETWEEN terms.start_date - 7 AND terms.end_date + 7 AND v_instance = 'L2CAN') OR
       (terms.group_code = 'MED' AND SYSDATE BETWEEN terms.start_date - 7 AND terms.end_date + 7 AND v_instance = 'L2CAN') OR
       (terms.group_code = 'ACD' AND SYSDATE BETWEEN terms.start_date - 7 AND terms.end_date + 8 AND v_instance = 'ACCAN'))
   AND (to_char(SYSDATE, 'HH24') BETWEEN '00' AND '08') -- *outside of high demand*
UNION
-- Run non-current terms - **ONLY RUN DURING NON-BUSINESS HOURS** 
SELECT terms.term_code,
       terms.start_date,
       terms.end_date,
       terms.group_code
  FROM zbtm.terms_by_group_v terms
 WHERE 1 = 1
   AND terms.group_code IN ('STD', 'MED', 'ACD')
   AND ((terms.group_code = 'STD' AND SYSDATE BETWEEN terms.start_date - 180 AND terms.end_date + 180 AND v_instance = 'L2CAN') OR
       (terms.group_code = 'MED' AND SYSDATE BETWEEN terms.start_date - 180 AND terms.end_date + 180 AND v_instance = 'L2CAN') OR
       (terms.group_code = 'ACD' AND SYSDATE BETWEEN terms.start_date - 180 AND terms.end_date + 365 AND v_instance = 'ACCAN'))
   AND (to_char(SYSDATE, 'HH24') BETWEEN '18' AND '23') -- *outside of high demand*
UNION ALL
-- Run non-banner terms - **ONLY RUN DURING NON-BUSINESS HOURS** 
SELECT '000000' AS term_code,
       trunc(SYSDATE - 365) AS start_date,
       trunc(SYSDATE + 365) AS end_date,
       '000' AS group_code
  FROM dual
 WHERE 1 = 1
   AND v_instance = 'L2CAN' -- only non term instance  
   AND (to_char(SYSDATE, 'HH24') BETWEEN '18' AND '23') -- *outside of high demand*
 ORDER BY group_code DESC,
          start_date DESC;
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
v_msg     := 'START - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- !!! GLOBAL TEMP TABLE - PRESERVES ROWS ON COMMIT !!!
-- multiple runs per session with cause unique constraint (constraint_name) violated
-- truncate table student_users_gtt;
INSERT INTO utl_d_lms.student_users_gtt
(control_state,
 pidm,
 luid,
 user_name,
 user_id,
 first_name,
 last_name,
 lu_email,
 advisor_name,
 advisor_username,
 advisor_pidm,
 affiliate_ind,
 last_request,
 last_login,
 workflow_state,
 instance,
 activity_date,
 updated_date,
 PARTITION)
-- L2CAN
SELECT CASE
       WHEN usr.user_id IS NOT NULL
            AND su.user_id IS NULL THEN
        'INSERT' -- new record to source, add to table
       WHEN usr.user_id IS NOT NULL
            AND su.user_id IS NOT NULL THEN
        'UPDATE' -- record exists in both places
       END AS control_state,
       usr.pidm,
       usr.luid,
       usr.user_name,
       usr.user_id,
       usr.first_name,
       usr.last_name,
       usr.lu_email,
       usr.advisor_name,
       usr.advisor_username,
       usr.advisor_pidm,
       usr.affiliate_ind,
       usr.last_request,
       usr.last_login,
       usr.workflow_state,
       usr.instance,
       v_etl_date AS activity_date,
       usr.updated_date,
       MOD(usr.user_id, v_mod) AS PARTITION
  FROM (SELECT spriden_pidm AS pidm,
               CASE
               WHEN spriden_id IS NOT NULL THEN
                spriden_id
               WHEN length(p.sis_user_id) > 9 THEN
                NULL -- non-standard LUIDs
               ELSE
                coalesce(spriden_id, p.sis_user_id)
               END AS luid,
               lower(p.unique_id) AS user_name,
               u.id AS user_id, -- users.id
               coalesce(spriden_first_name, substr(u.short_name, 1, instr(u.short_name, ' ') - 1)) AS first_name,
               coalesce(spriden_last_name, substr(u.short_name, instr(u.short_name, ' ') + 1)) AS last_name,
               stu_emal.email_address AS lu_email,
               NULL AS advisor_name,
               NULL AS advisor_username,
               NULL AS advisor_pidm,
               e.updated_at AS updated_date,
               CASE
               WHEN aff.studentid IS NOT NULL THEN
                'Y'
               ELSE
                'N'
               END AS affiliate_ind, -- needed for dual enrollment students
               p.last_request_at AS last_request,
               p.last_login_at AS last_login,
               u.workflow_state,
               u.instance,
               rank() over(PARTITION BY u.id, u.instance ORDER BY spriden_pidm DESC NULLS LAST, p.unique_id DESC NULLS LAST, p.last_login_at DESC, rownum) ranking -- "spriden_pidm DESC NULLS LAST" to remedy DUP_PIDM
          FROM zcanvas_data.enrollments e
          JOIN zcanvas_data.pseudonyms p
            ON p.user_id = e.user_id
           AND p.instance = e.instance
           AND e.type = 'StudentEnrollment'
           AND e.workflow_state <> 'deleted'
           AND e.instance = v_instance
           AND v_instance = 'L2CAN' -- DO NOT REMOVE HARD CODED VALUE
           AND length(p.unique_id) <= 30 -- remove any test or temp users that get a hash
           AND p.workflow_state <> 'deleted'
          JOIN zcanvas_data.users u
            ON p.user_id = u.id
           AND u.instance = p.instance
          LEFT JOIN saturn.spriden -- LEFT JOIN HERE TO ALLOW FOR NON-TERM STUDENTS
            ON spriden.spriden_id = p.sis_user_id
           AND spriden.spriden_change_ind IS NULL
          LEFT JOIN zexec.zsavemal stu_emal
            ON stu_emal.pidm = spriden.spriden_pidm
           AND stu_emal.emal_code = 'LU'
           AND stu_emal.emal_code_rank = 1
        -- affiliate students
          LEFT JOIN (SELECT a.studentid,
                           a.studentpidm,
                           szrattr.szrattr_atts_code     schl_code,
                           szrattr.szrattr_contract_pidm schl_pidm,
                           szrattr_term_code_to
                      FROM utl_d_luo.rsbbluoaenrl a
                      JOIN zsaturn.szrattr
                        ON szrattr.szrattr_atts_code = a.affl_attr
                     WHERE szrattr_zbrd_code = 'LUOA'
                       AND a.last_term = (SELECT MAX(a2.last_term) FROM utl_d_luo.rsbbluoaenrl a2 WHERE a.studentpidm = a2.studentpidm)) aff
            ON aff.studentid = spriden_id) usr
  LEFT JOIN utl_d_lms.student_users su
    ON su.instance = usr.instance
   AND su.user_id = usr.user_id
 WHERE 1 = 1 -- get anything more recent or new
   AND ranking = 1
   AND (usr.updated_date > su.updated_date OR su.updated_date IS NULL);
v_count       := SQL%ROWCOUNT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
INSERT INTO utl_d_lms.student_users_gtt
(control_state,
 pidm,
 luid,
 user_name,
 user_id,
 first_name,
 last_name,
 lu_email,
 advisor_name,
 advisor_username,
 advisor_pidm,
 affiliate_ind,
 last_request,
 last_login,
 workflow_state,
 instance,
 activity_date,
 updated_date,
 PARTITION)
-- ACCAN
SELECT CASE
       WHEN usr.user_id IS NOT NULL
            AND su.user_id IS NULL THEN
        'INSERT' -- new record to source, add to table
       WHEN usr.user_id IS NOT NULL
            AND su.user_id IS NOT NULL THEN
        'UPDATE' -- record exists in both places
       END AS control_state,
       usr.pidm,
       usr.luid,
       usr.user_name,
       usr.user_id,
       usr.first_name,
       usr.last_name,
       usr.lu_email,
       usr.advisor_name,
       usr.advisor_username,
       usr.advisor_pidm,
       usr.affiliate_ind,
       usr.last_request,
       usr.last_login,
       usr.workflow_state,
       usr.instance,
       v_etl_date AS activity_date,
       usr.updated_date,
       MOD(usr.user_id, v_mod) AS PARTITION
  FROM (SELECT spriden_pidm AS pidm,
               CASE
               WHEN spriden.spriden_id IS NOT NULL THEN
                spriden.spriden_id
               WHEN length(p.sis_user_id) > 9 THEN
                NULL -- non-standard LUIDs
               ELSE
                coalesce(spriden.spriden_id, p.sis_user_id)
               END AS luid,
               lower(p.unique_id) AS user_name,
               u.id AS user_id, -- users.id
               coalesce(spriden.spriden_first_name, substr(u.short_name, 1, instr(u.short_name, ' ') - 1)) AS first_name,
               coalesce(spriden.spriden_last_name, substr(u.short_name, instr(u.short_name, ' ') + 1)) AS last_name,
               stu_emal.email_address AS lu_email,
               advr.advisor AS advisor_name,
               advr.advisor_username AS advisor_username,
               advr.advisor_pidm AS advisor_pidm,
               CASE
               WHEN aff.studentid IS NOT NULL THEN
                'Y'
               ELSE
                'N'
               END AS affiliate_ind,
               p.last_request_at AS last_request,
               p.last_login_at AS last_login,
               u.workflow_state,
               u.instance,
               e.updated_at AS updated_date,
               rank() over(PARTITION BY u.id, u.instance ORDER BY spriden_pidm DESC NULLS LAST, p.unique_id DESC NULLS LAST, p.last_login_at DESC, rownum) ranking -- "spriden_pidm DESC NULLS LAST" to remedy DUP_PIDM
          FROM zcanvas_data.enrollments e
          JOIN zcanvas_data.pseudonyms p
            ON p.user_id = e.user_id
           AND p.instance = e.instance
           AND e.instance = v_instance
           AND v_instance = 'ACCAN' -- DO NOT REMOVE HARD CODED VALUE
           AND e.type = 'StudentEnrollment'
           AND e.workflow_state <> 'deleted'
           AND p.workflow_state <> 'deleted'
           AND length(p.unique_id) <= 30 -- remove any test or temp users that get a hash
          JOIN zcanvas_data.users u
            ON p.user_id = u.id
           AND u.instance = p.instance
          JOIN saturn.spriden -- FORCE BANNER CONNECTION FOR ACCAN
            ON spriden.spriden_id = p.sis_user_id
           AND spriden.spriden_change_ind IS NULL
          LEFT JOIN zexec.zsavemal stu_emal
            ON stu_emal.pidm = spriden_pidm
           AND stu_emal.emal_code = 'LU'
           AND stu_emal.emal_code_rank = 1
        -- affiliate students
          LEFT JOIN (SELECT a.studentid,
                           a.studentpidm,
                           szrattr.szrattr_atts_code     schl_code,
                           szrattr.szrattr_contract_pidm schl_pidm,
                           szrattr_term_code_to
                      FROM utl_d_luo.rsbbluoaenrl a
                      JOIN zsaturn.szrattr
                        ON szrattr.szrattr_atts_code = a.affl_attr
                     WHERE szrattr.szrattr_zbrd_code = 'LUOA'
                       AND a.last_term = (SELECT MAX(a2.last_term) FROM utl_d_luo.rsbbluoaenrl a2 WHERE a.studentpidm = a2.studentpidm)) aff
            ON aff.studentid = spriden.spriden_id
        -- advisors
          LEFT JOIN (SELECT DISTINCT coalesce(agnt.gzragnt_full_name, spriden.spriden_first_name || ' ' || spriden.spriden_last_name) AS advisor,
                                    sgradvr.sgradvr_advr_pidm AS advisor_pidm,
                                    gobtpac.gobtpac_external_user AS advisor_username,
                                    sgradvr.sgradvr_pidm AS student_pidm
                      FROM saturn.spriden
                      JOIN general.gobtpac
                        ON gobtpac.gobtpac_pidm = spriden.spriden_pidm
                      JOIN saturn.sgradvr sgradvr
                        ON sgradvr.sgradvr_advr_pidm = spriden.spriden_pidm
                       AND sgradvr.sgradvr_advr_code IN ('LUOA', 'LUAA')
                       AND sgradvr.sgradvr_prim_ind = 'Y'
                       AND sgradvr.sgradvr_term_code_eff = (SELECT MAX(sgradvr2.sgradvr_term_code_eff)
                                                              FROM saturn.sgradvr sgradvr2
                                                             WHERE sgradvr2.sgradvr_pidm = sgradvr.sgradvr_pidm
                                                               AND sgradvr2.sgradvr_term_code_eff <= (SELECT MAX(t.term_code)
                                                                                                        FROM zbtm.terms_by_group_v t
                                                                                                       WHERE 1 = 1
                                                                                                         AND t.start_date >= (SYSDATE - (365 * 3)) -- prior to 3 years
                                                                                                         AND t.start_date <= (SYSDATE + 14)
                                                                                                         AND group_code IN ('ACD')))
                      LEFT JOIN zgeneral.gzragnt agnt
                        ON agnt.gzragnt_pidm = spriden.spriden_pidm
                     WHERE spriden.spriden_change_ind IS NULL) advr
            ON advr.student_pidm = spriden.spriden_pidm) usr
  LEFT JOIN utl_d_lms.student_users su
    ON su.instance = usr.instance
   AND su.user_id = usr.user_id
 WHERE 1 = 1 -- get anything more recent or new
   AND usr.ranking = 1
   AND (usr.updated_date > su.updated_date OR su.updated_date IS NULL);
v_count       := SQL%ROWCOUNT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
INSERT INTO utl_d_lms.student_users_gtt
(control_state,
 pidm,
 luid,
 user_name,
 user_id,
 first_name,
 last_name,
 lu_email,
 advisor_name,
 advisor_username,
 advisor_pidm,
 affiliate_ind,
 last_request,
 last_login,
 workflow_state,
 instance,
 activity_date,
 updated_date,
 PARTITION)
SELECT control_state,
       pidm,
       luid,
       user_name,
       user_id,
       first_name,
       last_name,
       lu_email,
       advisor_name,
       advisor_username,
       advisor_pidm,
       affiliate_ind,
       last_request,
       last_login,
       workflow_state,
       instance,
       activity_date,
       updated_date,
       PARTITION
  FROM ( -- ALL INSTANCES
        SELECT 'DELETE' AS control_state, -- no longer exists
                su.pidm,
                su.luid,
                su.user_name,
                su.user_id,
                su.first_name,
                su.last_name,
                su.lu_email,
                su.advisor_name,
                su.advisor_username,
                su.advisor_pidm,
                su.affiliate_ind,
                su.last_request,
                su.last_login,
                su.workflow_state,
                su.instance,
                su.activity_date,
                su.updated_date,
                su.partition
          FROM utl_d_lms.student_users su
          LEFT JOIN zcanvas_data.users u
            ON u.instance = su.instance
           AND u.id = su.user_id
         WHERE 1 = 1
           AND su.instance IN ('ACCAN', 'L2CAN') -- DO NOT REMOVE HARD CODED VALUE
           AND su.instance = v_instance
           AND coalesce(u.workflow_state, 'deleted') = 'deleted') src
 WHERE src.control_state = 'DELETE';
v_count       := SQL%ROWCOUNT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'DELETE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
MERGE INTO utl_d_lms.student_users tgt
USING (SELECT src.pidm,
              src.luid,
              src.user_name,
              src.user_id,
              src.first_name,
              src.last_name,
              src.lu_email,
              src.advisor_name,
              src.advisor_username,
              src.advisor_pidm,
              src.affiliate_ind,
              src.last_request,
              src.last_login,
              src.workflow_state,
              src.instance,
              src.activity_date,
              src.updated_date,
              src.partition,
              src.data_source
         FROM (SELECT gtt.pidm,
                      gtt.luid,
                      gtt.user_name,
                      gtt.user_id,
                      gtt.first_name,
                      gtt.last_name,
                      gtt.lu_email,
                      gtt.advisor_name,
                      gtt.advisor_username,
                      gtt.advisor_pidm,
                      gtt.affiliate_ind,
                      gtt.last_request,
                      gtt.last_login,
                      gtt.workflow_state,
                      gtt.instance,
                      gtt.activity_date,
                      gtt.updated_date,
                      gtt.partition,
                      'CDE' AS data_source,
                      rank() over(PARTITION BY gtt.user_id, gtt.instance ORDER BY gtt.pidm DESC NULLS LAST, gtt.last_request DESC, gtt.updated_date DESC, rownum) ranking -- "gobtpac_pidm DESC NULLS LAST" to remedy DUP_PIDM
                 FROM utl_d_lms.student_users_gtt gtt
                WHERE 1 = 1
                  AND gtt.instance = v_instance
                  AND gtt.control_state IN ('INSERT', 'UPDATE')) src
         LEFT JOIN utl_d_lms.student_users tgt
           ON tgt.instance = src.instance
          AND tgt.user_id = src.user_id
        WHERE src.ranking = 1
             -- for inserts or deletes...
          AND (((src.user_id IS NULL AND tgt.user_id IS NOT NULL) OR (src.user_id IS NOT NULL AND tgt.user_id IS NULL)) OR --
              -- for updates if any data has changed...
              (nvl(src.pidm, -1) <> nvl(tgt.pidm, -1) OR --
              nvl(src.luid, 'X') <> nvl(tgt.luid, 'X') OR --
              nvl(src.user_name, 'X') <> nvl(tgt.user_name, 'X') OR --
              nvl(src.first_name, 'X') <> nvl(tgt.first_name, 'X') OR --
              nvl(src.last_name, 'X') <> nvl(tgt.last_name, 'X') OR --
              nvl(src.lu_email, 'X') <> nvl(tgt.lu_email, 'X') OR --
              nvl(src.advisor_name, 'X') <> nvl(tgt.advisor_name, 'X') OR --
              nvl(src.advisor_username, 'X') <> nvl(tgt.advisor_username, 'X') OR --
              nvl(src.advisor_pidm, -1) <> nvl(tgt.advisor_pidm, -1) OR --
              nvl(src.affiliate_ind, 'X') <> nvl(tgt.affiliate_ind, 'X') OR --
              nvl(src.last_request, to_timestamp('1900-01-01 00:00:00', 'YYYY-MM-DD HH24:MI:SS')) <> nvl(tgt.last_request, to_timestamp('1900-01-01 00:00:00', 'YYYY-MM-DD HH24:MI:SS')) OR --
              nvl(src.last_login, to_timestamp('1900-01-01 00:00:00', 'YYYY-MM-DD HH24:MI:SS')) <> nvl(tgt.last_login, to_timestamp('1900-01-01 00:00:00', 'YYYY-MM-DD HH24:MI:SS')) OR --
              nvl(src.workflow_state, 'X') <> nvl(tgt.workflow_state, 'X') OR --
              nvl(src.activity_date, to_date('1900-01-01', 'YYYY-MM-DD')) <> nvl(tgt.activity_date, to_date('1900-01-01', 'YYYY-MM-DD')) OR --
              nvl(src.updated_date, to_timestamp('1900-01-01 00:00:00', 'YYYY-MM-DD HH24:MI:SS')) <> nvl(tgt.updated_date, to_timestamp('1900-01-01 00:00:00', 'YYYY-MM-DD HH24:MI:SS')) OR --
              nvl(src.data_source, 'X') <> nvl(tgt.data_source, 'X')))) src
ON (tgt.instance = src.instance AND tgt.user_id = src.user_id)
WHEN MATCHED THEN
UPDATE
   SET tgt.pidm             = src.pidm,
       tgt.luid             = src.luid,
       tgt.user_name        = src.user_name,
       tgt.first_name       = src.first_name,
       tgt.last_name        = src.last_name,
       tgt.lu_email         = src.lu_email,
       tgt.advisor_name     = src.advisor_name,
       tgt.advisor_username = src.advisor_username,
       tgt.advisor_pidm     = src.advisor_pidm,
       tgt.affiliate_ind    = src.affiliate_ind,
       tgt.last_request     = src.last_request,
       tgt.last_login       = src.last_login,
       tgt.workflow_state   = src.workflow_state,
       tgt.activity_date    = src.activity_date,
       tgt.updated_date     = src.updated_date,
       tgt.data_source      = src.data_source
WHEN NOT MATCHED THEN
INSERT
(pidm,
 luid,
 user_name,
 user_id,
 first_name,
 last_name,
 lu_email,
 advisor_name,
 advisor_username,
 advisor_pidm,
 affiliate_ind,
 last_request,
 last_login,
 workflow_state,
 instance,
 activity_date,
 updated_date,
 PARTITION,
 data_source)
VALUES
(src.pidm,
 src.luid,
 src.user_name,
 src.user_id,
 src.first_name,
 src.last_name,
 src.lu_email,
 src.advisor_name,
 src.advisor_username,
 src.advisor_pidm,
 src.affiliate_ind,
 src.last_request,
 src.last_login,
 src.workflow_state,
 src.instance,
 src.activity_date,
 src.updated_date,
 src.partition,
 src.data_source);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- DML DELETES
DELETE FROM utl_d_lms.student_users tab
 WHERE EXISTS (SELECT 1
          FROM utl_d_lms.student_users_gtt gtt
         WHERE 1 = 1
           AND gtt.instance = v_instance
           AND gtt.control_state = 'DELETE'
           AND tab.instance = gtt.instance
           AND tab.user_id = gtt.user_id);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'DELETE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
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
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
/*--------------------------------------------CHANGE LOG----------------------------------------
VERSION  DATE        USERNAME    UPDATES
---      09-09-2020  WGRIFFITH2  --Initial release
---      09-16-2020  WGRIFFITH2  --Full integration of ACCAN & LUCAN
---      10-22-2020  WGRIFFITH2  --Adding advisors to ACCAN
---      11-30-2020  WGRIFFITH2  --UTL_P_CANVAS will be used until we get new data feed from Instructure
---      05-10-2021  WGRIFFITH2  --On CD2, facultys no longer required to have a Banner record.
---      05-24-2021  WGRIFFITH2  --Performance updates; removing course and faculty detail columns
---      10-12-2021  WGRIFFITH2  --LUOA CD1 -> CD2
---      11-09-2022  WGRIFFITH2  --major release
---      05-03-2022  WGRIFFITH2  --performance updates -- adding GTT
---      03-04-2024  WGRIFFITH2  --updated rank "spriden_pidm DESC NULLS LAST" to remedy DUP_PIDM
---      03-18-2025  WGRIFFITH2  --adding partition field
------------------------------------------------------------------------------------------------*/
END etl_lms_student_users;
procedure etl_lms_assignments_dates(jobnumber NUMBER, processid VARCHAR2, processname VARCHAR2, inst varchar2, nmbr number) IS
--
-- PURPOSE: Stages effective assignment date records for LMS sections to support downstream grading timelines and reporting.
--
-- TABLE: utl_d_lms.assignments_dates
-- UNIQUE INDEX: INSTANCE, COURSE_SECTION_ID, ASSIGNMENT_ID
--
-- CONDITIONS:
-- Processes data one academic term at a time based on a term cursor drawn from zbtm.terms_by_group_v.
-- Includes only terms in groups STD, MED, or ACD.
-- For current terms: runs when the system time is between 00:00 and 08:00; STD and MED terms are processed for instance L2CAN, and ACD terms are processed for instance ACCAN, each within a window from 7 days before the term start to 7 days after the term end.
-- For non-current terms: runs only during non-business hours (18:00–23:00); STD and MED terms (instance L2CAN) are included within ±180 days of the term’s start/end, and ACD terms (instance ACCAN) are included from 180 days before the start to 365 days after the end.
-- For non‑Banner coverage: when instance is L2CAN and during non‑business hours (18:00–23:00), a synthetic term '000000' is added spanning one year back to one year forward from the current date.
-- Filters student_enrollments early by the current instance (v_instance), the loop’s term code (rec.term_code), and the ETL partition (v_partition) to restrict the join volume.
-- Considers only assignments where the student was enrolled: joins student_assignments to filtered enrollments on instance, term_code, course_section_id, and user_id.
-- Aggregates per (course_section_id, assignment_id, instance): computes MEDIAN graded_date, MEDIAN of COALESCE(due_date, cached_due_date), MAX end_date, COUNT of assignment_id (total), and percent_graded as the ratio of positively graded submissions to total, rounded to four decimals; carries forward the MAX term_code.
-- Includes records for further processing only when either at least half of submissions are graded (percent_graded ≥ 0.50) or a due_date exists.
-- Derives the effective date (dte) using business rules: if due_date is missing and total submissions ≤ 2 with percent_graded ≥ 0.50, set dte to the day after median graded_date at 11:59pm; if due_date is missing and total > 2 with percent_graded ≥ 0.55, also set dte to the day after median graded_date at 11:59pm; otherwise set dte to 7 days after COALESCE(due_date, end_date) at 11:59pm.
-- Sets date_field to 'effective_grade_date', workflow_state to 'published', and stamps activity_date with the current ETL run date.
-- Loads or updates rows by matching on (instance, course_section_id, assignment_id); only updates when the computed row_hash differs from the stored row_hash (or the target hash is null), ensuring changes are applied solely when relevant fields have changed.
-- During off‑peak windows when v_partition = 0 and day-of-week code equals '4' and the hour is between 18:00–23:00, deletes target rows for the term that no longer have a corresponding student_assignments record (removing orphaned assignment dates).
--
-- URL: N/A
--
--DECLARE
v_etl_date    DATE := SYSDATE;
v_msg         VARCHAR2(2000);
v_instance    VARCHAR2(50) := upper(inst); -- inst from the jams job; used for determining instance
v_partition    NUMBER := nmbr; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_lms_assignments_dates';
v_retry_count NUMBER := 0;
v_max_retries NUMBER := 3; -- number of retries for WAIT
v_wait_time   NUMBER := 120; -- seconds for WAIT
CURSOR c_terms IS
-- Run current terms
SELECT terms.term_code,
       terms.start_date,
       terms.end_date,
       terms.group_code
  FROM zbtm.terms_by_group_v terms
 WHERE 1 = 1
   AND terms.group_code IN ('STD', 'MED', 'ACD')
   -- controls what terms run for which instances (only)
   AND ((terms.group_code = 'STD' AND SYSDATE BETWEEN terms.start_date - 7 AND terms.end_date + 7 AND v_instance = 'L2CAN') OR
       (terms.group_code = 'MED' AND SYSDATE BETWEEN terms.start_date - 7 AND terms.end_date + 7 AND v_instance = 'L2CAN') OR
       (terms.group_code = 'ACD' AND SYSDATE BETWEEN terms.start_date - 7 AND terms.end_date + 8 AND v_instance = 'ACCAN'))
   AND (to_char(SYSDATE, 'HH24') BETWEEN '00' AND '08') -- *outside of high demand*
UNION
-- Run non-current terms - **ONLY RUN DURING NON-BUSINESS HOURS** 
SELECT terms.term_code,
       terms.start_date,
       terms.end_date,
       terms.group_code
  FROM zbtm.terms_by_group_v terms
 WHERE 1 = 1
   AND terms.group_code IN ('STD', 'MED', 'ACD')
   AND ((terms.group_code = 'STD' AND SYSDATE BETWEEN terms.start_date - 180 AND terms.end_date + 180 AND v_instance = 'L2CAN') OR
       (terms.group_code = 'MED' AND SYSDATE BETWEEN terms.start_date - 180 AND terms.end_date + 180 AND v_instance = 'L2CAN') OR
       (terms.group_code = 'ACD' AND SYSDATE BETWEEN terms.start_date - 180 AND terms.end_date + 365 AND v_instance = 'ACCAN'))
   AND (to_char(SYSDATE, 'HH24') BETWEEN '18' AND '23') -- *outside of high demand*
UNION ALL
-- Run non-banner terms - **ONLY RUN DURING NON-BUSINESS HOURS** 
SELECT '000000' AS term_code,
       trunc(SYSDATE - 365) AS start_date,
       trunc(SYSDATE + 365) AS end_date,
       '000' AS group_code
  FROM dual
 WHERE 1 = 1
   AND v_instance = 'L2CAN' -- only non term instance  
   AND (to_char(SYSDATE, 'HH24') BETWEEN '18' AND '23') -- *outside of high demand*
 ORDER BY group_code DESC,
          start_date DESC;
BEGIN
-- dbms_output.enable(buffer_size => NULL);
--
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_application_info.set_module(module_name => v_proc, action_name => v_msg);
dbms_output.put_line(' --------- ');
FOR rec IN c_terms
LOOP
v_count := 0; -- reset count
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- Retry mechanism for handling deadlocks
v_retry_count := 0;
LOOP
BEGIN
--FIX: Move WITH clause inside USING subquery (MERGE cannot directly follow WITH; must follow a SELECT)
MERGE INTO utl_d_lms.assignments_dates tgt
USING (
WITH se_filt AS
 (SELECT /*+ MATERIALIZE */
   se.instance,
   se.term_code,
   se.course_section_id,
   se.user_id,
   se.end_date
    FROM utl_d_lms.student_enrollments se
   WHERE se.instance = v_instance
     AND se.term_code = rec.term_code
     AND se.partition = v_partition),
adt_src AS
 (SELECT /*+ MATERIALIZE USE_HASH(sa) USE_HASH(se_filt) LEADING(se_filt sa) */
   sa.course_section_id,
   sa.assignment_id,
   sa.instance,
   median(sa.graded_date) AS graded_date,
   median(coalesce(sa.due_date, sa.cached_due_date)) AS due_date,
   MAX(se_filt.end_date) AS end_date,
   COUNT(sa.assignment_id) AS total,
   round(SUM(CASE
             WHEN sa.graded_date IS NOT NULL
                  AND coalesce(sa.score, 0) > 0 THEN
              1
             WHEN sa.workflow_state IN ('graded')
                  AND coalesce(sa.score, 0) > 0 THEN
              1
             ELSE
              NULL
             END) / COUNT(sa.assignment_id), 4) AS percent_graded,
   MAX(sa.term_code) AS term_code
    FROM utl_d_lms.student_assignments sa
    JOIN se_filt
      ON se_filt.instance = sa.instance
     AND se_filt.term_code = sa.term_code
     AND se_filt.course_section_id = sa.course_section_id
     AND se_filt.user_id = sa.user_id
   GROUP BY sa.course_section_id,
            sa.assignment_id,
            sa.instance)
SELECT adt.course_section_id,
       adt.assignment_id,
       adt.instance,
       adt.term_code,
       -- goal: determine when to calculate "earned grades" if we do not have due dates
       --        if we have due dates, use them
       CASE
       WHEN adt.due_date IS NULL
            AND adt.total <= 2
            AND adt.percent_graded >= .50 THEN
        trunc(adt.graded_date + 1) - 1 / (24 * 60 * 60) -- modified to 11:59pm
       WHEN adt.due_date IS NULL
            AND adt.total > 2
            AND adt.percent_graded >= .55 THEN
        trunc(adt.graded_date + 1) - 1 / (24 * 60 * 60) -- modified to 11:59pm
       ELSE
        trunc(nvl(adt.due_date, adt.end_date) + 7) - 1 / (24 * 60 * 60) -- modified to 11:59pm
       END AS dte,
       'effective_grade_date' AS date_field,
       'published' AS workflow_state,
       v_etl_date AS activity_date,
       -- row_hash for easier comps - keys + comparison fields 
       standard_hash(nvl(to_char(adt.instance), '<NULL>') || '#' || nvl(to_char(adt.course_section_id), '<NULL>') || '#' || nvl(to_char(adt.assignment_id), '<NULL>') || '#' ||
                     nvl(to_char(CASE
                                 WHEN adt.due_date IS NULL
                                      AND adt.total <= 2
                                      AND adt.percent_graded >= .50 THEN
                                  trunc(adt.graded_date + 1) - 1 / (24 * 60 * 60) -- modified to 11:59pm
                                 WHEN adt.due_date IS NULL
                                      AND adt.total > 2
                                      AND adt.percent_graded >= .55 THEN
                                  trunc(adt.graded_date + 1) - 1 / (24 * 60 * 60) -- modified to 11:59pm
                                 ELSE
                                  trunc(nvl(adt.due_date, adt.end_date) + 7) - 1 / (24 * 60 * 60) -- modified to 11:59pm
                                 END, 'YYYYMMDDHH24MISS'), '<NULL>') || '#' || 'effective_grade_date' || '#' || -- constant: do not TO_CHAR
                     nvl(to_char(adt.term_code), '<NULL>') || '#' || 'published', -- constant: do not TO_CHAR
                     'MD5') AS row_hash
  FROM adt_src adt
 WHERE adt.percent_graded >= .50
    OR adt.due_date IS NOT NULL) src ON (tgt.instance = src.instance AND tgt.course_section_id = src.course_section_id AND tgt.assignment_id = src.assignment_id) WHEN MATCHED THEN
UPDATE
   SET tgt.dte            = src.dte,
       tgt.date_field     = src.date_field,
       tgt.term_code      = src.term_code,
       tgt.workflow_state = src.workflow_state,
       tgt.activity_date  = src.activity_date,
       tgt.row_hash       = src.row_hash
 WHERE (tgt.row_hash IS NULL OR tgt.row_hash <> src.row_hash)
WHEN NOT MATCHED THEN
INSERT
(course_section_id,
 assignment_id,
 dte,
 date_field,
 workflow_state,
 instance,
 term_code,
 activity_date,
 row_hash)
VALUES
(src.course_section_id,
 src.assignment_id,
 src.dte,
 src.date_field,
 src.workflow_state,
 src.instance,
 src.term_code,
 src.activity_date,
 src.row_hash);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- Target cleanup during off-peak windows
IF to_char(v_etl_date, 'D') IN ('4') -- only run at specific times outside of high demand
   AND to_char(SYSDATE, 'HH24') BETWEEN '18' AND '23'
   AND v_partition = 0 -- only run delete on 0 parallel
 THEN
DELETE FROM utl_d_lms.assignments_dates tgt
 WHERE tgt.instance = v_instance
   AND tgt.term_code = rec.term_code
   AND NOT EXISTS (SELECT 1
          FROM utl_d_lms.student_assignments sa
         WHERE tgt.instance = sa.instance
           AND tgt.term_code = sa.term_code
           AND tgt.course_section_id = sa.course_section_id
           AND tgt.assignment_id = sa.assignment_id);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'DELETE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
END IF;
EXIT; -- If successful, exit the retry loop
EXCEPTION
WHEN OTHERS THEN
IF SQLCODE = -60 THEN
-- Deadlock detected
v_retry_count := v_retry_count + 1;
IF v_retry_count > v_max_retries THEN
-- Log error for max retries
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := '!!!-00060: deadlock detected while waiting for resource. Max retries exceeded after ' || (v_max_retries * v_wait_time) || ' seconds';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
EXIT; -- break out of the loop when max retries exceeded
ELSE
-- Log retry attempt
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'Deadlock detected while waiting for resource - waiting ' || v_wait_time || ' seconds for retry attempt number ' || v_retry_count;
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'WARNING', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
dbms_lock.sleep(v_wait_time); -- Wait between retries; short wait because it will need to cycle through all the GTTs again
CONTINUE; -- explicitly indicate loop continuation
END IF;
ELSE
-- Other errors
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
EXIT; -- break out for non-deadlock errors
END IF;
END;
END LOOP; -- end deadlock detection
dbms_output.put_line(' --------- ');
END LOOP; -- c_terms
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
---      09-09-2020  WGRIFFITH2  --Initial release
---      09-16-2020  WGRIFFITH2  --Full integration of ACCAN & LUCAN
---      10-05-2020  WGRIFFITH2  --Complete table structure rebuild
---      11-13-2020  WGRIFFITH2  --Removing deleted workflow_state assignments that still exist
---      05-24-2021  WGRIFFITH2  --Performance updates; removing course and student detail columns
---      09-10-2021  WGRIFFITH2  --Adding Blackboard instance
---      10-12-2021  WGRIFFITH2  --LUOA CD1 -> CD2
---      11-03-2021  WGRIFFITH2  --Update to control_state
---      11-24-2021  WGRIFFITH2  --Using lms_table_bins to control the query population
---      11-09-2022  WGRIFFITH2  --major release
---      03-20-2025  WGRIFFITH2  -- dte field modified to 11:59pm
-- 20251210 WGRIFFITH2 - Fixed ORA-00928 by moving WITH inside USING; corrected HTML entities; kept row_hash-based updates; retained MATERIALIZE + filtered enrollments
------------------------------------------------------------------------------------------------*/
END etl_lms_assignments_dates;
procedure etl_lms_assignments_stats(jobnumber NUMBER, processid VARCHAR2, processname VARCHAR2, inst varchar2, nmbr number) IS
/*
Table: utl_d_lms.assignments_stats

Primary Keys: SURROGATE_ID

Unique index: ASSIGNMENT_ID, COURSE_SECTION_ID, INSTANCE

Purpose: Used to create aggregated statistics for determining submission and success rates for all courses.

Conditions: Does not pull any assignments of students AFTER they WD; Does not count assignments until effective grade date occurred

Dependencies: utl_d_lms.student_assignments; utl_d_lms.assignments_dates
*/
--DECLARE
v_etl_date DATE := SYSDATE;
v_msg      VARCHAR2(2000);
v_instance VARCHAR2(50) := upper(inst); -- inst from the jams job; used for determining instance
v_partition NUMBER := nmbr; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_row_max  NUMBER := 100000; -- max number of rows to be processed at one time
v_count    NUMBER := 0;
v_job_id   VARCHAR2(32);
v_proc     VARCHAR2(100) := 'etl_lms_assignments_stats';
CURSOR c_terms IS
-- Run current terms
SELECT terms.term_code,
       terms.start_date,
       terms.end_date,
       terms.group_code
  FROM zbtm.terms_by_group_v terms
 WHERE 1 = 1
   AND terms.group_code IN ('STD', 'MED', 'ACD')
   -- controls what terms run for which instances (only)
   AND ((terms.group_code = 'STD' AND SYSDATE BETWEEN terms.start_date - 7 AND terms.end_date + 7 AND v_instance = 'L2CAN') OR
       (terms.group_code = 'MED' AND SYSDATE BETWEEN terms.start_date - 7 AND terms.end_date + 7 AND v_instance = 'L2CAN') OR
       (terms.group_code = 'ACD' AND SYSDATE BETWEEN terms.start_date - 7 AND terms.end_date + 8 AND v_instance = 'ACCAN'))
   AND (to_char(SYSDATE, 'HH24') BETWEEN '00' AND '08') -- *outside of high demand*
UNION
-- Run non-current terms - **ONLY RUN DURING NON-BUSINESS HOURS** 
SELECT terms.term_code,
       terms.start_date,
       terms.end_date,
       terms.group_code
  FROM zbtm.terms_by_group_v terms
 WHERE 1 = 1
   AND terms.group_code IN ('STD', 'MED', 'ACD')
   AND ((terms.group_code = 'STD' AND SYSDATE BETWEEN terms.start_date - 180 AND terms.end_date + 180 AND v_instance = 'L2CAN') OR
       (terms.group_code = 'MED' AND SYSDATE BETWEEN terms.start_date - 180 AND terms.end_date + 180 AND v_instance = 'L2CAN') OR
       (terms.group_code = 'ACD' AND SYSDATE BETWEEN terms.start_date - 180 AND terms.end_date + 365 AND v_instance = 'ACCAN'))
   AND (to_char(SYSDATE, 'HH24') BETWEEN '18' AND '23') -- *outside of high demand*
UNION ALL
-- Run non-banner terms - **ONLY RUN DURING NON-BUSINESS HOURS** 
SELECT '000000' AS term_code,
       trunc(SYSDATE - 365) AS start_date,
       trunc(SYSDATE + 365) AS end_date,
       '000' AS group_code
  FROM dual
 WHERE 1 = 1
   AND v_instance = 'L2CAN' -- only non term instance  
   AND (to_char(SYSDATE, 'HH24') BETWEEN '18' AND '23') -- *outside of high demand*
 ORDER BY group_code DESC,
          start_date DESC;
CURSOR c1(v_term_code VARCHAR) IS
SELECT
 CASE
 WHEN src.course_section_id IS NOT NULL
      AND target.course_section_id IS NULL THEN
  'INSERT' -- new record to source, add to table
 WHEN src.course_section_id IS NOT NULL
      AND target.course_section_id IS NOT NULL THEN
  'UPDATE' -- record exists in both places
 WHEN src.course_section_id IS NULL
      AND target.course_section_id IS NOT NULL THEN
  'DELETE' -- no record longer exists on the source data, remove it
 END AS control_state,
 coalesce(src.course_section_id, target.course_section_id) AS course_section_id,
 coalesce(src.assignment_id, target.assignment_id) AS assignment_id,
 src.title,
 src.points_possible,
 src.credit_hr,
 src.total_cnt,
 src.points_earned,
 src.attempt_cnt,
 src.no_attempt_cnt,
 src.success_cnt,
 coalesce(src.instance, target.instance) AS instance,
 SYSDATE AS activity_date,
 src.term_code,
 src.ptrm_code
  FROM (SELECT course_section_id,
               assignment_id,
               MAX(title) AS title,
               median(points_possible) AS points_possible,
               median(credit_hr) AS credit_hr,
               COUNT(DISTINCT user_id) AS total_cnt,
               AVG(score) AS points_earned,
               SUM(attempt) attempt_cnt,
               SUM(no_attempt) no_attempt_cnt,
               SUM(success) AS success_cnt,
               instance,
               MAX(term_code) AS term_code,
               MAX(ptrm_code) AS ptrm_code
          FROM (SELECT crse.credit_hr AS credit_hr,
                       sa.course_section_id,
                       sa.assignment_id,
                       sa.user_id,
                       sa.title,
                       coalesce(sa.score, 0) AS score,
                       sa.points_possible,
                       CASE
                       WHEN coalesce(sa.score, 0) > 0 THEN
                        1
                       ELSE
                        0
                       END AS attempt,
                       CASE
                       WHEN coalesce(sa.score, 0) = 0 THEN
                        1
                       ELSE
                        0
                       END AS no_attempt,
                       CASE
                       WHEN ll.instance IN ('BLACKBOARD', 'L2CAN')
                            AND substr(ll.course_code, 5, 1) IN ('5', '6', '7', '8', '9')
                            AND (coalesce(sa.score, 0) / sa.points_possible) >= 0.76 THEN
                        1
                       WHEN ll.instance IN ('BLACKBOARD', 'L2CAN')
                            AND substr(ll.course_code, 5, 1) IN ('0', '1', '2', '3', '4')
                            AND (coalesce(sa.score, 0) / sa.points_possible) >= 0.70 THEN
                        1
                       WHEN ll.instance NOT IN ('BLACKBOARD', 'L2CAN')
                            AND (coalesce(sa.score, 0) / sa.points_possible) >= 0.70 THEN
                        1
                       ELSE
                        0
                       END AS success,
                       ll.instance AS instance,
                       sa.workflow_state,
                       ll.term_code,
                       ll.ptrm_code
                  FROM utl_d_lms.student_assignments sa
                  JOIN utl_d_lms.lms_link ll
                    ON ll.course_section_id = sa.course_section_id
                   AND ll.instance = sa.instance
                   AND sa.instance = v_instance
                   AND v_instance IN ('ACCAN', 'L2CAN', 'BLACKBOARD') -- DO NOT REMOVE HARD CODED VALUE; WORKS THE SAME FOR ALL INSTANCES
                   AND ll.term_code = v_term_code
                   AND ll.partition = v_partition
                  JOIN utl_d_lms.student_users su
                    ON su.user_id = sa.user_id
                   AND su.instance = sa.instance
                  JOIN utl_d_aim.szrcrse crse
                    ON crse.pidm = su.pidm
                   AND crse.crn = ll.crn
                   AND crse.term_code = ll.term_code
                  JOIN utl_d_lms.assignments_dates adt
                    ON adt.assignment_id = sa.assignment_id
                   AND adt.course_section_id = ll.course_section_id
                   AND adt.instance = ll.instance
                   AND adt.date_field = 'effective_grade_date'
                 WHERE 1 = 1
                      -- do not pull any assignments of students AFTER they WD
                      -- do not count assignments until effective grade date occured
                   AND ((sa.graded_date IS NOT NULL AND nvl(adt.dte, ll.end_date) < SYSDATE) OR --
                       (nvl(crse.final_grade, 'I') = 'I' AND sa.submitted_date IS NULL AND nvl(adt.dte, ll.end_date) < SYSDATE))
                   AND nvl(sa.points_possible, 0) > 0)
         GROUP BY course_section_id,
                  instance,
                  assignment_id) src
-- for the control state
  FULL JOIN (SELECT adt.*
               FROM utl_d_lms.assignments_stats adt
               JOIN utl_d_lms.lms_link ll
                 ON ll.instance = adt.instance
                AND ll.course_section_id = adt.course_section_id
              WHERE ll.instance = v_instance
                AND ll.term_code = v_term_code
                AND ll.partition = v_partition) target
    ON target.instance = src.instance
   AND target.course_section_id = src.course_section_id
   AND target.assignment_id = src.assignment_id
 WHERE 1 = 1
      -- for inserts or deletes...
   AND (((src.course_section_id IS NULL AND target.course_section_id IS NOT NULL) OR (src.course_section_id IS NOT NULL AND target.course_section_id IS NULL)) OR --
       -- for updates if any data has changed...
       (coalesce(src.title, 'X') <> coalesce(target.title, 'X')) OR --
       (coalesce(src.points_possible, -1) <> coalesce(target.points_possible, -1)) OR --
       (coalesce(src.credit_hr, -1) <> coalesce(target.credit_hr, -1)) OR --
       (coalesce(src.total_cnt, -1) <> coalesce(target.total_cnt, -1)) OR --
       (coalesce(src.points_earned, -1) <> coalesce(target.points_earned, -1)) OR --
       (coalesce(src.attempt_cnt, -1) <> coalesce(target.attempt_cnt, -1)) OR --
       (coalesce(src.no_attempt_cnt, -1) <> coalesce(target.no_attempt_cnt, -1)) OR --
       (coalesce(src.success_cnt, -1) <> coalesce(target.success_cnt, -1)) OR --
       (coalesce(src.term_code, 'X') <> coalesce(target.term_code, 'X')) OR --
       (coalesce(src.ptrm_code, 'X') <> coalesce(target.ptrm_code, 'X')));
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
delete_dml   index_pointer_d := index_pointer_d();
v_total_count NUMBER := 0;
insert_count NUMBER := 0;
update_count NUMBER := 0;
delete_count NUMBER := 0;
v_elapsed    NUMBER := 0;
BEGIN
-- dbms_output.enable(buffer_size => NULL);
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
--
FOR rec IN c_terms
LOOP
OPEN c1(rec.term_code);
LOOP v_count := 0; -- reset count
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
FETCH c1 BULK COLLECT
INTO rec_input LIMIT v_row_max;
v_count := rec_input.count;
IF v_count = 0 THEN
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'SELECT - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
ELSIF v_count > 0 THEN
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
WHEN OTHERS THEN v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg := SUBSTR(REPLACE(SQLERRM,'ORA','!!!'),1,200) || ' exception raised for ' || rec.term_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || round(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
CONTINUE;
END;
END LOOP;
insert_count := insert_dml.count;
update_count := update_dml.count;
delete_count := delete_dml.count;
FORALL i IN VALUES OF insert_dml -- DML INSERTS
INSERT INTO utl_d_lms.assignments_stats tab
(course_section_id,
 assignment_id,
 title,
 points_possible,
 credit_hr,
 total_cnt,
 points_earned,
 attempt_cnt,
 no_attempt_cnt,
 success_cnt,
 instance,
 activity_date,
 term_code,
 ptrm_code)
VALUES
(rec_input(i).course_section_id,
 rec_input(i).assignment_id,
 rec_input(i).title,
 rec_input(i).points_possible,
 rec_input(i).credit_hr,
 rec_input(i).total_cnt,
 rec_input(i).points_earned,
 rec_input(i).attempt_cnt,
 rec_input(i).no_attempt_cnt,
 rec_input(i).success_cnt,
 rec_input(i).instance,
 rec_input(i).activity_date,
 rec_input(i).term_code,
 rec_input(i).ptrm_code);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'INSERT - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
FORALL i IN VALUES OF update_dml -- DML UPDATES
UPDATE utl_d_lms.assignments_stats tab
   SET (course_section_id, assignment_id, title, points_possible, credit_hr, total_cnt, points_earned, attempt_cnt, no_attempt_cnt, success_cnt, instance, activity_date, term_code, ptrm_code) =
       (SELECT rec_input(i).course_section_id,
               rec_input(i).assignment_id,
               rec_input(i).title,
               rec_input(i).points_possible,
               rec_input(i).credit_hr,
               rec_input(i).total_cnt,
               rec_input(i).points_earned,
               rec_input(i).attempt_cnt,
               rec_input(i).no_attempt_cnt,
               rec_input(i).success_cnt,
               rec_input(i).instance,
               rec_input(i).activity_date,
               rec_input(i).term_code,
               rec_input(i).ptrm_code
          FROM dual)
 WHERE tab.course_section_id = rec_input(i).course_section_id
   AND tab.assignment_id = rec_input(i).assignment_id
   AND tab.instance = rec_input(i).instance;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'UPDATE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
FORALL i IN VALUES OF delete_dml -- DML DELETES
DELETE FROM utl_d_lms.assignments_stats tab
 WHERE tab.course_section_id = rec_input(i).course_section_id
   AND tab.assignment_id = rec_input(i).assignment_id
   AND tab.instance = rec_input(i).instance;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'DELETE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
END IF;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_total_count := v_total_count + rec_input.count;
EXIT WHEN(rec_input.count < v_row_max);
END LOOP;
CLOSE c1;
dbms_output.put_line(' --------- ');
end loop; -- c_terms
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
-- log any errors
EXCEPTION
WHEN OTHERS THEN v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg := SUBSTR(REPLACE(SQLERRM,'ORA','!!!'),1,200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
END etl_lms_assignments_stats;

procedure etl_lms_link(jobnumber number, processid varchar2, processname varchar2, inst varchar2, nmbr number) IS
/*
Table: utl_d_lms.lms_link

Primary Keys: SURROGATE_ID

Unique index: INSTANCE, TERM_CODE, CRN

Purpose:
- Create a link between CANVAS courses and BANNER courses. Includes ALL instances.

Conditions:
- Does not allow for microsections; **use the student_enrollments table**

Dependencies: Banner; all baseline/source tables
*/
--DECLARE
v_etl_date DATE := SYSDATE;
v_msg      VARCHAR2(2000);
v_instance VARCHAR2(50) := upper(inst); -- inst from the jams job; used for determining instance
v_partition NUMBER := 0; -- !!! KEEP HARDCODED !!!; always zero for LMS LINK
v_mod      NUMBER := 5; -- !!! KEEP HARDCODED !!!; how many parallels/partitions we run; **if changed** jams jobs will need updating
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_lms_link';
CURSOR c_terms IS
-- Run current terms
SELECT terms.term_code,
       terms.start_date,
       terms.end_date,
       terms.group_code
  FROM zbtm.terms_by_group_v terms
 WHERE 1 = 1
   AND terms.group_code IN ('STD', 'MED', 'ACD')
   -- controls what terms run for which instances (only)
   AND ((terms.group_code = 'STD' AND SYSDATE BETWEEN terms.start_date - 7 AND terms.end_date + 7 AND v_instance = 'L2CAN') OR
       (terms.group_code = 'MED' AND SYSDATE BETWEEN terms.start_date - 7 AND terms.end_date + 7 AND v_instance = 'L2CAN') OR
       (terms.group_code = 'ACD' AND SYSDATE BETWEEN terms.start_date - 7 AND terms.end_date + 8 AND v_instance = 'ACCAN'))
   AND (to_char(SYSDATE, 'HH24') BETWEEN '00' AND '08') -- *outside of high demand*
UNION
-- Run non-current terms - **ONLY RUN DURING NON-BUSINESS HOURS** 
SELECT terms.term_code,
       terms.start_date,
       terms.end_date,
       terms.group_code
  FROM zbtm.terms_by_group_v terms
 WHERE 1 = 1
   AND terms.group_code IN ('STD', 'MED', 'ACD')
   AND ((terms.group_code = 'STD' AND SYSDATE BETWEEN terms.start_date - 180 AND terms.end_date + 180 AND v_instance = 'L2CAN') OR
       (terms.group_code = 'MED' AND SYSDATE BETWEEN terms.start_date - 180 AND terms.end_date + 180 AND v_instance = 'L2CAN') OR
       (terms.group_code = 'ACD' AND SYSDATE BETWEEN terms.start_date - 180 AND terms.end_date + 365 AND v_instance = 'ACCAN'))
   AND (to_char(SYSDATE, 'HH24') BETWEEN '18' AND '23') -- *outside of high demand*
UNION ALL
-- Run non-banner terms - **ONLY RUN DURING NON-BUSINESS HOURS** 
SELECT '000000' AS term_code,
       trunc(SYSDATE - 365) AS start_date,
       trunc(SYSDATE + 365) AS end_date,
       '000' AS group_code
  FROM dual
 WHERE 1 = 1
   AND v_instance = 'L2CAN' -- only non term instance 
      --  *outside of high demand*
   AND (to_char(SYSDATE, 'HH24') BETWEEN '18' AND '23') -- *outside of high demand*
 ORDER BY group_code DESC,
          start_date DESC;
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
v_msg     := 'START - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
MERGE INTO utl_d_lms.lms_link tgt
USING (SELECT src.course_code,
              src.course_sis_id,
              src.section_sis_id,
              src.course_id,
              src.course_section_id,
              src.course_name,
              src.subj_code,
              src.crse_numb,
              src.seq_numb,
              src.term_code,
              src.crn,
              src.ptrm_code,
              src.camp_code,
              src.insm_code,
              src.levl_code,
              src.coll_code,
              src.workflow_state,
              src.instance,
              src.lms_source,
              src.start_date,
              src.end_date,
              src.activity_date,
              src.updated_date,
              src.partition,
              src.enrollment,
              src.data_source,
              src.base_course,
              src.faculty_pidm,
              src.microsection,
              src.cross_listed
         FROM (SELECT se.course_code,
                      se.course_sis_id,
                      case when se.microsection IS NOT NULL then se.course_sis_id -- to avoid confusion about joining on this to get microsections
					  else se.section_sis_id end as section_sis_id, 
                      se.course_id,
                      se.course_section_id,
                      se.course_name,
                      se.subj_code,
                      se.crse_numb,
                      se.seq_numb,
                      se.term_code,
                      se.crn,
                      se.ptrm_code,
                      se.camp_code,
                      se.insm_code,
                      se.levl_code,
                      se.coll_code,
                      se.workflow_state,
                      se.instance,
                      'CANVAS' AS lms_source,
                      se.start_date,
                      se.end_date,
                      se.updated_date,
                      MOD(se.course_section_id, v_mod) AS PARTITION,
                      COUNT(*) over(PARTITION BY term_code, crn) AS enrollment,
                      se.data_source,
                      se.base_course,
                      se.faculty_pidm,
                      CASE
                      WHEN se.microsection IS NOT NULL THEN
                       'Y'
                      ELSE
                       'N'
                      END AS microsection,
                      se.cross_listed,
                      se.activity_date,
                      rank() over(PARTITION BY se.term_code, se.crn ORDER BY szrlevl_prog_order DESC, course_section_id DESC, rownum) AS ranking
                 FROM utl_d_lms.student_enrollments se
                 LEFT JOIN zsaturn.szrlevl
                   ON szrlevl_levl_code = se.levl_code
                WHERE 1 = 1
                  AND se.instance = v_instance
                  AND se.term_code = rec.term_code) src
         LEFT JOIN utl_d_lms.lms_link tgt
           ON tgt.instance = src.instance
          AND tgt.term_code = src.term_code
          AND tgt.crn = src.crn
        WHERE 1 = 1
          AND ranking = 1
          AND (((src.course_section_id IS NULL AND tgt.course_section_id IS NOT NULL) OR --
              (src.course_section_id IS NOT NULL AND tgt.course_section_id IS NULL)) OR -- 
              (coalesce(src.course_code, 'xxxxx') <> coalesce(tgt.course_code, 'xxxxx')) OR -- 
              (coalesce(src.course_name, 'xxxxx') <> coalesce(tgt.course_name, 'xxxxx')) OR --
              (coalesce(src.course_id, -1) <> coalesce(tgt.course_id, -1)) OR --
              (coalesce(src.course_sis_id, 'xxxxx') <> coalesce(tgt.course_sis_id, 'xxxxx')) OR --
              (coalesce(src.subj_code, 'xxxxx') <> coalesce(tgt.subj_code, 'xxxxx')) OR --
              (coalesce(src.crse_numb, 'xxxxx') <> coalesce(tgt.crse_numb, 'xxxxx')) OR --
              (coalesce(src.seq_numb, 'xxxxx') <> coalesce(tgt.seq_numb, 'xxxxx')) OR --
              (coalesce(src.ptrm_code, 'xxxxx') <> coalesce(tgt.ptrm_code, 'xxxxx')) OR --
              (coalesce(src.camp_code, 'xxxxx') <> coalesce(tgt.camp_code, 'xxxxx')) OR --
              (coalesce(src.insm_code, 'xxxxx') <> coalesce(tgt.insm_code, 'xxxxx')) OR --
              (coalesce(src.levl_code, 'xxxxx') <> coalesce(tgt.levl_code, 'xxxxx')) OR --
              (coalesce(src.coll_code, 'xxxxx') <> coalesce(tgt.coll_code, 'xxxxx')) OR -- 
              (coalesce(src.workflow_state, 'xxxxx') <> coalesce(tgt.workflow_state, 'xxxxx')) OR --
              (coalesce(src.start_date, SYSDATE) <> coalesce(tgt.start_date, SYSDATE)) OR --
              (coalesce(src.end_date, SYSDATE) <> coalesce(tgt.end_date, SYSDATE)) OR --
              (coalesce(src.base_course, 'xxxxx') <> coalesce(tgt.base_course, 'xxxxx')) OR --
              (coalesce(src.partition, -1) <> coalesce(tgt.partition, -1)) OR --
              (coalesce(src.enrollment, -1) <> coalesce(tgt.enrollment, -1)) OR --
              (coalesce(src.faculty_pidm, -1) <> coalesce(tgt.faculty_pidm, -1)) OR --
              (coalesce(src.microsection, 'xxxxx') <> coalesce(tgt.microsection, 'xxxxx')) OR --
              (coalesce(src.cross_listed, 'xxxxx') <> coalesce(tgt.cross_listed, 'xxxxx')) OR --
              (coalesce(src.data_source, 'xxxxx') <> coalesce(tgt.data_source, 'xxxxx')))) src
ON (tgt.instance = src.instance AND tgt.term_code = src.term_code AND tgt.crn = src.crn)
WHEN MATCHED THEN
UPDATE
   SET tgt.course_code       = src.course_code,
       tgt.course_sis_id     = src.course_sis_id,
       tgt.section_sis_id    = src.section_sis_id,
       tgt.course_id         = src.course_id,
       tgt.course_name       = src.course_name,
       tgt.subj_code         = src.subj_code,
       tgt.crse_numb         = src.crse_numb,
       tgt.seq_numb          = src.seq_numb,
       tgt.course_section_id = src.course_section_id,
       tgt.ptrm_code         = src.ptrm_code,
       tgt.camp_code         = src.camp_code,
       tgt.insm_code         = src.insm_code,
       tgt.levl_code         = src.levl_code,
       tgt.coll_code         = src.coll_code,
       tgt.workflow_state    = src.workflow_state,
       tgt.lms_source        = src.lms_source,
       tgt.start_date        = src.start_date,
       tgt.end_date          = src.end_date,
       tgt.activity_date     = src.activity_date,
       tgt.updated_date      = src.updated_date,
       tgt.partition         = src.partition,
       tgt.enrollment        = src.enrollment,
       tgt.data_source       = src.data_source,
       tgt.base_course       = src.base_course,
       tgt.faculty_pidm      = src.faculty_pidm,
       tgt.microsection      = src.microsection,
       tgt.cross_listed      = src.cross_listed
WHEN NOT MATCHED THEN
INSERT
(course_code,
 course_sis_id,
 section_sis_id,
 course_id,
 course_section_id,
 course_name,
 subj_code,
 crse_numb,
 seq_numb,
 term_code,
 crn,
 ptrm_code,
 camp_code,
 insm_code,
 levl_code,
 coll_code,
 workflow_state,
 instance,
 lms_source,
 start_date,
 end_date,
 activity_date,
 updated_date,
 PARTITION,
 enrollment,
 data_source,
 base_course,
 faculty_pidm,
 microsection,
 cross_listed)
VALUES
(src.course_code,
 src.course_sis_id,
 src.section_sis_id,
 src.course_id,
 src.course_section_id,
 src.course_name,
 src.subj_code,
 src.crse_numb,
 src.seq_numb,
 src.term_code,
 src.crn,
 src.ptrm_code,
 src.camp_code,
 src.insm_code,
 src.levl_code,
 src.coll_code,
 src.workflow_state,
 src.instance,
 src.lms_source,
 src.start_date,
 src.end_date,
 src.activity_date,
 src.updated_date,
 src.partition,
 src.enrollment,
 src.data_source,
 src.base_course,
 src.faculty_pidm,
 src.microsection,
 src.cross_listed);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
DELETE FROM utl_d_lms.lms_link ll
 WHERE ll.instance <> 'BLACKBOARD' -- never remove blackboard 
   AND ll.instance = v_instance
   AND ll.term_code = rec.term_code
   AND NOT EXISTS (SELECT 1
          FROM utl_d_lms.student_enrollments se
         WHERE 1 = 1
           AND se.instance = v_instance
           AND se.instance = ll.instance
           AND se.term_code = ll.term_code
           AND se.crn = ll.crn
           AND se.term_code = rec.term_code);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'DELETE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
UPDATE utl_d_lms.lms_link ll
   SET ll.status =
       (SELECT CASE
               WHEN SYSDATE < trunc(start_date) - 7 THEN
                'pending' -- has not started yet
               WHEN SYSDATE >= trunc(start_date) - 7
                    AND SYSDATE <= trunc(end_date) + 7
                    AND enrollment > 0 THEN
                'active' -- started with enrollment after week 0 and a week after complete
               WHEN rec.group_code = 'MED'
                    AND SYSDATE >= trunc(start_date) - 7
                    AND SYSDATE <= trunc(end_date) + 365
                    AND enrollment > 0 THEN
                'active' -- med school to update final grades WAY late
               WHEN SYSDATE > trunc(end_date) + 1
                    AND SYSDATE <= trunc(end_date) + 365
                    AND enrollment > 0 THEN
                'concluded' -- course ended within 365 days
               WHEN SYSDATE > trunc(end_date) + 365
                    AND enrollment > 0 THEN
                'completed' -- lock in place after 365 days
               WHEN SYSDATE >= trunc(start_date) + 0
                    AND enrollment = 0 THEN
                'inactive' -- no enrollment after start date
               END
          FROM utl_d_lms.lms_link l2
         WHERE 1 = 1
           AND l2.instance = ll.instance
           AND l2.course_section_id = ll.course_section_id
           AND l2.term_code = rec.term_code
           AND (ll.status IS NULL OR CASE
               WHEN SYSDATE < trunc(l2.start_date) - 7 THEN
                'pending' -- has not started yet
               WHEN SYSDATE >= trunc(l2.start_date) - 7
                    AND SYSDATE <= trunc(l2.end_date) + 7
                    AND l2.enrollment > 0 THEN
                'active' -- started with enrollment after week 0 and a week after complete
               WHEN rec.group_code = 'MED'
                    AND SYSDATE >= trunc(l2.start_date) - 7
                    AND SYSDATE <= trunc(l2.end_date) + 365
                    AND l2.enrollment > 0 THEN
                'active' -- med school to update final grades WAY late
               WHEN SYSDATE > trunc(l2.end_date) + 1
                    AND SYSDATE <= trunc(l2.end_date) + 365
                    AND l2.enrollment > 0 THEN
                'concluded' -- course ended within 365 days
               WHEN SYSDATE > trunc(l2.end_date) + 365
                    AND l2.enrollment > 0 THEN
                'completed' -- lock in place after 365 days
               WHEN SYSDATE >= trunc(l2.start_date) + 0
                    AND l2.enrollment = 0 THEN
                'inactive' -- no enrollment after start date
               END <> ll.status))
 WHERE EXISTS (SELECT 'x'
          FROM utl_d_lms.lms_link l2
         WHERE l2.instance = ll.instance
           AND l2.course_section_id = ll.course_section_id
           AND l2.term_code = rec.term_code
           AND (ll.status IS NULL OR CASE
               WHEN SYSDATE < trunc(l2.start_date) - 7 THEN
                'pending' -- has not started yet
               WHEN SYSDATE >= trunc(l2.start_date) - 7
                    AND SYSDATE <= trunc(l2.end_date) + 7
                    AND l2.enrollment > 0 THEN
                'active' -- started with enrollment after week 0 and a week after complete
               WHEN rec.group_code = 'MED'
                    AND SYSDATE >= trunc(l2.start_date) - 7
                    AND SYSDATE <= trunc(l2.end_date) + 365
                    AND l2.enrollment > 0 THEN
                'active' -- med school to update final grades WAY late
               WHEN SYSDATE > trunc(l2.end_date) + 1
                    AND SYSDATE <= trunc(l2.end_date) + 365
                    AND l2.enrollment > 0 THEN
                'concluded' -- course ended within 365 days
               WHEN SYSDATE > trunc(end_date) + 365
                    AND l2.enrollment > 0 THEN
                'completed' -- lock in place after 365 days
               WHEN SYSDATE >= trunc(start_date) + 0
                    AND l2.enrollment = 0 THEN
                'inactive' -- no enrollment after start date
               END <> ll.status));
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'UPDATE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
end loop; -- c_terms
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
---      09-09-2020  WGRIFFITH2  --Initial release
---      09-16-2020  WGRIFFITH2  --Full integration of ACCAN & LUCAN
---      10-22-2020  WGRIFFITH2  --Adding advisors to ACCAN
---      11-30-2020  WGRIFFITH2  --UTL_P_CANVAS will be used until we get new data feed from Instructure
---      05-10-2021  WGRIFFITH2  --On CD2, students no longer required to have a Banner record.
---      05-24-2021  WGRIFFITH2  --Performance updates; removing course and student detail columns
---      06-02-2021  WGRIFFITH2  --Records being missed when using the "greatest" function in the where clause. Changed left join to course_sections to inner join
---      06-02-2021  WGRIFFITH2  --Adding a rank to take the "best" course record
---      10-12-2021  WGRIFFITH2  --LUOA CD1 -> CD2
---      10-14-2021  WGRIFFITH2  --Remove any courses that had a INTG = NULL and then changed to L2CAN
---      11-04-2021  WGRIFFITH2  --major release; adding start and end date of course
---      11-14-2022  WGRIFFITH2  --adding partition field
---      12-15-2022  WGRIFFITH2  --performance improvements now using a GTT
---      12-28-2022  WGRIFFITH2  --now using sfrareg for open learning terms
---      01-03-2023 WGRIFFITH2   --stage pars code data for a subquery that was really inefficient!
---      03-07-2023 WGRIFFITH2   --performance improvements; adding partition field
---      04-26-2023 WGRIFFITH2   --better identification of records we need to remove from the table
---      05-05-2023 WGRIFFITH2   --updates to the course_sis_id and section_sis_id. using what comes from canvas when it exists. needed for graphQL requests.
---      05-16-2023 WGRIFFITH2   --adding lms_link_active_gtt to help with performance and management of new EM (ember) levl_code
---      06-14-2023 WGRIFFITH2   --Minor adjustments to non term courses. Adding a way to get Banner data into the table when it does not exist in Canvas data
---      07-19-2023 WGRIFFITH2   --Adding EMber courses (removed on 20230908)
---      08-11-2023 WGRIFFITH2   --course section remove when no longer has enrollment after the course start date +21
---      08-25-2023 WGRIFFITH2   --Adding base course field for ACCAN
---      09-25-2023 WGRIFFITH2   --Adjustments to status field
---      09-04-2024 WGRIFFITH2   --Adding microsections for L2CAN
---      09-13-2024 WGRIFFITH2   --Adding faculty_pidm field to show the primary instructor
---      01-14-2025 WGRIFFITH2   --missing data in zsaturn.szrmsin forced a work-around "coalesce(sirasgn_pidm, i.szrmsin_instructor_pidm) AS faculty_pidm"
---      02-21-2025 WGRIFFITH2   --adding microsection field Y/N. Microsections are NOT supported by the LMS LINK framework; Use utl_d_lms.students_enrollments table instead
---      03-05-2025 WGRIFFITH2   --student enrollment becomes the dependency on all LMS tables replacing lms_link to be able to support microsections
------------------------------------------------------------------------------------------------*/
END etl_lms_link;
END load_lms_etl;