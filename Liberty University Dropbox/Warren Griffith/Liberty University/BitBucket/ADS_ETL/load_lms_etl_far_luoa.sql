create or replace package load_lms_etl_far_luoa IS 
procedure etl_lms_far_luoa_courses(jobnumber number, processid varchar2, processname varchar2);
procedure etl_lms_far_luoa_audit_fn(jobnumber number, processid varchar2, processname varchar2);
procedure etl_lms_far_luoa_audit_fg(jobnumber number, processid varchar2, processname varchar2);
procedure etl_lms_far_luoa_audit_gc(jobnumber number, processid varchar2, processname varchar2);
procedure etl_lms_far_luoa_audit_mm(jobnumber number, processid varchar2, processname varchar2);
procedure etl_lms_far_luoa_audit_mq(jobnumber number, processid varchar2, processname varchar2);
procedure etl_lms_far_luoa_audit_wa(jobnumber number, processid varchar2, processname varchar2);
procedure etl_lms_far_luoa_audit_log (jobnumber number, processid varchar2, processname varchar2);
procedure etl_lms_far_luoa_audit_tableau (jobnumber number, processid varchar2, processname varchar2);
end load_lms_etl_far_luoa;
/

CREATE OR REPLACE PACKAGE BODY load_lms_etl_far_luoa IS

PROCEDURE etl_lms_far_luoa_audit_tableau(jobnumber   NUMBER,
                                         processid   VARCHAR2,
                                         processname VARCHAR2) IS
--DECLARE
--- PARAMS
v_etl_date    DATE := SYSDATE;
v_instance    VARCHAR2(50) := upper('ACCAN'); -- inst from the jams job; used for determining instance
v_partition    NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_msg         VARCHAR2(2000);
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_lms_far_luoa_audit_tableau';
BEGIN
-- dbms_output.enable(buffer_size => NULL);
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
DELETE FROM utl_d_lms.far_luoa_audit_tableau; -- NO TRUNCATE; ENSURE CONSTANT UPTIME
v_count       := SQL%ROWCOUNT;
v_total_count := v_total_count + v_count;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'DELETE - ' || 'ALL' || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- NO COMMIT UNTIL INSERT HAPPENS; ENSURE CONSTANT UPTIME
INSERT INTO utl_d_lms.far_luoa_audit_tableau
(semester,
 coll_desc,
 course_code,
 course_name,
 url,
 unique_id,
 insm_code,
 faculty_name,
 instructor,
 instance,
 term_code,
 ptrm_code,
 category_code,
 category_desc,
 compliance_status_code,
 instructor_status_code,
 admin_status_code,
 compliance_status_reason,
 flag_count,
 audit_date,
 last_modified,
 last_refresh,
 hours_since_last_login,
 course_status,
 enrollment,
 faculty_email,
 instructor_username,
 im_usernames,
 chair_usernames,
 dean_usernames,
 fsc_usernames,
 sme_usernames,
 director_usernames,
 admin_usernames,
 all_usernames)
SELECT t.term_desc AS semester,
       courses.coll_desc,
       courses.course_section_name AS course_code, --"Course"
       courses.course_section_name || ' (' || to_char(courses.start_date, 'MM/DD/YYYY') || ')' AS course_name,
       coalesce(flags.url, courses.url) AS url,
       coalesce(flags.unique_id, courses.course_section_id || '_' || cat_codes.category_code || '0' || '_' || to_char(SYSDATE, 'YYYYMMDD')) AS unique_id,
       courses.insm_code,
       courses.faculty_name,
       CASE
       WHEN fht.instructor_username IS NULL THEN
        courses.faculty_name
       ELSE
        courses.faculty_name || ' - ' || fht.instructor_username
       END AS instructor,
       courses.instance,
       courses.term_code,
       courses.ptrm_code,
       cat_codes.category_code,
       cat_codes.category_desc,
       coalesce(flags.compliance_status_code, '0') AS compliance_status_code,
       -- 0 = green; 1 = yellow; 2 = red; 3 = grey
       CASE
       WHEN substr(flags.compliance_status_reason, 1, 25) = 'Canvas data feed is stale' THEN
        '3' -- show grey if CD2 is stale
       ELSE
        coalesce(flags.compliance_status_code, '0')
       END AS instructor_status_code,
       CASE
       WHEN fht.instructor_username IS NULL THEN
        '3' -- show grey if CD2 is stale
       WHEN substr(flags.compliance_status_reason, 1, 25) = 'Canvas data feed is stale' THEN
        '3' -- show grey if CD2 is stale
       ELSE
        coalesce(flags.compliance_status_code, '0')
       END AS admin_status_code,
       CASE
       WHEN fht.instructor_username IS NULL THEN
        'The Faculty Hierarchy Tool needs to be configured. ' || coalesce(flags.compliance_status_reason, '(no concerns)')
       ELSE
        coalesce(flags.compliance_status_reason, '(no action items)')
       END AS compliance_status_reason,
       flags.flag_count,
       flags.audit_date,
       flags.last_modified,
       CASE
       WHEN flags.last_modified IS NOT NULL THEN
        'Last refresh: ' || to_char(flags.last_modified, 'MM/DD/YYYY hh24:mi')
       ELSE
        'Last refresh: ' || to_char(courses.activity_date, 'MM/DD/YYYY hh24:mi')
       END AS last_refresh,
       CASE
       WHEN flags.compliance_category_code = 'LA' THEN
        round((to_number(flags.last_modified - flags.audit_date) * 24), 2)
       ELSE
        NULL
       END AS hours_since_last_login,
       CASE
       WHEN cal.week_number IS NULL THEN
        courses.course_section_name || ' (' || to_char(courses.start_date, 'MM/DD/YYYY') || ') has completed. '
       WHEN cal.week_number IS NOT NULL
            AND courses.exclusions IS NOT NULL THEN
        TRIM(courses.course_section_name || ' (' || to_char(courses.start_date, 'MM/DD/YYYY') || ') is currently in week ' || cal.week_number || '. ' || REPLACE(courses.exclusions, 'Other', 'Exclusion') || ' course. ')
       WHEN cal.week_number IS NOT NULL THEN
        TRIM(courses.course_section_name || ' (' || to_char(courses.start_date, 'MM/DD/YYYY') || ') is currently in week ' || cal.week_number || '. ')
       ELSE
        courses.course_section_name || ' (' || to_char(courses.start_date, 'MM/DD/YYYY') || ') in-progress'
       END AS course_status,
       courses.enrollment,
       -- Row level security:
       courses.faculty_email,
       coalesce(fht.instructor_username, TRIM(REPLACE(courses.faculty_email, '@liberty.edu', ''))) AS instructor_username,
       fht.im_usernames,
       fht.chair_usernames,
       fht.dean_usernames,
       fht.fsc_usernames,
       fht.sme_usernames,
       fht.director_usernames,
       fht.admin_usernames,
       '-' || fht.instructor_username || '-' || fht.im_usernames || '-' || fht.chair_usernames || '-' || fht.dean_usernames || '-' || fht.fsc_usernames || '-' || fht.sme_usernames || '-' || fht.director_usernames || '-' ||
       fht.admin_usernames || '-' AS all_usernames
  FROM utl_d_lms.far_luoa_courses courses -- controls population
  JOIN utl_d_lms.far_luoa_cat_code cat_codes
    ON 1 = 1
  LEFT JOIN utl_d_aa.crscalendar cal
    ON cal.crn = courses.crn
   AND cal.term_code = courses.term_code
   AND SYSDATE >= cal.dte
   AND SYSDATE < cal.dte + 1
  LEFT JOIN utl_d_lms.far_luoa_audit flags -- must be left join to show all categories on dashboard
    ON flags.term_code = courses.term_code
   AND flags.crn = courses.crn
   AND flags.compliance_category_code = cat_codes.category_code
   AND flags.status = 'ACTIVE'
   AND flags.deleted_ind = 'N'
  LEFT JOIN utl_d_aa.secfht fht
    ON courses.term_code = fht.term_code
   AND courses.crn = fht.crn
  LEFT JOIN zbtm.terms_by_group_v t
    ON t.term_code = courses.term_code
 WHERE 1 = 1;
v_count       := SQL%ROWCOUNT;
v_total_count := v_total_count + v_count;
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'INSERT - ' || 'ALL' || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
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
/*--------------------------------------------CHANGE LOG----------------------------------------
VERSION  DATE        USERNAME    UPDATES
---      02-06-2023  WGRIFFITH2  --Initial release
------------------------------------------------------------------------------------------------*/
END etl_lms_far_luoa_audit_tableau;

PROCEDURE etl_lms_far_luoa_audit_log(jobnumber   NUMBER,
                                     processid   VARCHAR2,
                                     processname VARCHAR2) IS
--DECLARE
--- PARAMS
v_etl_date    DATE := SYSDATE;
v_instance    VARCHAR2(50) := upper('ACCAN'); -- inst from the jams job; used for determining instance
v_partition    NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_msg         VARCHAR2(2000);
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_lms_far_luoa_audit_log';
-- CURSOR
CURSOR c_terms IS
SELECT ll.term_code,
       MAX(ll.end_date) end_date
  FROM zbtm.terms_by_group_v t
  JOIN utl_d_lms.lms_link ll
    ON ll.term_code = t.term_code
 WHERE 1 = 1
   AND SYSDATE >= ll.start_date - 14
   AND SYSDATE <= ll.end_date + 14
   AND ll.coll_code = 'AC'
 GROUP BY ll.term_code
 ORDER BY 1 DESC;
BEGIN
-- dbms_output.enable(buffer_size => NULL);
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
DELETE FROM utl_d_lms.far_luoa_audit fla -- REMOVE ANY ROWS THAT ARE NO LONGER CURRENT
 WHERE NOT EXISTS (SELECT 'X'
          FROM utl_d_lms.far_luoa_courses flc
         WHERE fla.instance = flc.instance
           AND fla.course_section_id = flc.course_section_id);
COMMIT;
FOR rec IN c_terms
LOOP
v_count   := 0; -- reset count
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || rec.term_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- CLEAR ANY RECORDS OF COURSES THAT NO LONGER EXIST IN BANNER
UPDATE utl_d_lms.far_luoa_audit fla
   SET (fla.status, fla.flag_count, fla.deleted_ind, fla.deleted_reason) =
       (SELECT 'EXPIRED',
               0,
               'Y',
               'SYSTEM: ' || 'Course no longer has enrollment in sfrstcr.'
          FROM dual)
 WHERE fla.instance = v_instance
   AND fla.term_code = rec.term_code
   AND fla.deleted_ind <> 'Y'
   AND coalesce(fla.deleted_reason, 'X') <> 'SYSTEM: ' || 'Course no longer has enrollment in sfrstcr.'
   AND NOT EXISTS (SELECT *
          FROM utl_d_lms.lms_link ll
         WHERE 1 = 1
           AND ll.instance = v_instance
           AND ll.enrollment > 0
           AND ll.instance = fla.instance
           AND ll.course_section_id = fla.course_section_id);
v_count := SQL%ROWCOUNT;
COMMIT;
COMMIT;
-- remove any courses that no longer exist in LMS LINK
UPDATE utl_d_lms.far_luoa_audit fla
   SET (fla.status, fla.flag_count, fla.deleted_ind, fla.deleted_reason) =
       (SELECT 'EXPIRED',
               0,
               'Y',
               'SYSTEM: ' || 'Course section no longer exists in LMS_LINK.'
          FROM dual)
 WHERE fla.term_code = rec.term_code
   AND fla.deleted_ind <> 'Y'
   AND to_char(SYSDATE, 'HH24') IN ('22') -- ONLY RUN ONCE A DAY
   AND NOT EXISTS (SELECT ll.course_section_id
          FROM utl_d_lms.lms_link ll
         WHERE ll.instance = v_instance
           AND fla.course_section_id = ll.course_section_id
           AND fla.instance = ll.instance);
v_count := v_count + SQL%ROWCOUNT;
COMMIT;
-- update what is currently on the far_luoa_audit table
MERGE INTO utl_d_lms.far_luoa_audit_log destination_table
USING (SELECT term_code,
              crn,
              coll_code,
              coll_desc,
              course_code,
              course_sis_id,
              section_sis_id,
              course_id,
              course_section_id,
              url,
              camp_code,
              ptrm_code,
              insm_code,
              faculty_pidm,
              faculty_name,
              faculty_email,
              compliance_category_code,
              compliance_status_code,
              compliance_status_reason,
              status,
              instance,
              deleted_ind,
              deleted_reason,
              unique_id,
              flag_count,
              audit_date,
              last_modified
         FROM utl_d_lms.far_luoa_audit fla
        WHERE fla.term_code = rec.term_code) new_records
ON (destination_table.unique_id = new_records.unique_id)
WHEN MATCHED THEN
UPDATE
   SET destination_table.coll_code                = new_records.coll_code,
       destination_table.coll_desc                = new_records.coll_desc,
       destination_table.course_code              = new_records.course_code,
       destination_table.course_sis_id            = new_records.course_sis_id,
       destination_table.section_sis_id           = new_records.section_sis_id,
       destination_table.course_id                = new_records.course_id,
       destination_table.course_section_id        = new_records.course_section_id,
       destination_table.url                      = new_records.url,
       destination_table.camp_code                = new_records.camp_code,
       destination_table.ptrm_code                = new_records.ptrm_code,
       destination_table.insm_code                = new_records.insm_code,
       destination_table.faculty_pidm             = new_records.faculty_pidm,
       destination_table.faculty_name             = new_records.faculty_name,
       destination_table.faculty_email            = new_records.faculty_email,
       destination_table.compliance_category_code = new_records.compliance_category_code,
       destination_table.compliance_status_code   = new_records.compliance_status_code,
       destination_table.compliance_status_reason = new_records.compliance_status_reason,
       destination_table.status                   = new_records.status,
       destination_table.instance                 = new_records.instance,
       destination_table.deleted_ind              = new_records.deleted_ind,
       destination_table.deleted_reason           = new_records.deleted_reason,
       destination_table.flag_count               = new_records.flag_count,
       destination_table.audit_date               = new_records.audit_date,
       destination_table.last_modified            = new_records.last_modified
WHEN NOT MATCHED THEN
INSERT
(term_code,
 crn,
 coll_code,
 coll_desc,
 course_code,
 course_sis_id,
 section_sis_id,
 course_id,
 course_section_id,
 url,
 camp_code,
 ptrm_code,
 insm_code,
 faculty_pidm,
 faculty_name,
 faculty_email,
 compliance_category_code,
 compliance_status_code,
 compliance_status_reason,
 status,
 instance,
 deleted_ind,
 deleted_reason,
 unique_id,
 flag_count,
 audit_date,
 last_modified)
VALUES
(new_records.term_code,
 new_records.crn,
 new_records.coll_code,
 new_records.coll_desc,
 new_records.course_code,
 new_records.course_sis_id,
 new_records.section_sis_id,
 new_records.course_id,
 new_records.course_section_id,
 new_records.url,
 new_records.camp_code,
 new_records.ptrm_code,
 new_records.insm_code,
 new_records.faculty_pidm,
 new_records.faculty_name,
 new_records.faculty_email,
 new_records.compliance_category_code,
 new_records.compliance_status_code,
 new_records.compliance_status_reason,
 new_records.status,
 new_records.instance,
 new_records.deleted_ind,
 new_records.deleted_reason,
 new_records.unique_id,
 new_records.flag_count,
 new_records.audit_date,
 new_records.last_modified);
v_count := v_count + SQL%ROWCOUNT;
COMMIT;
v_msg := 'MERGE - ' || rec.term_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
v_total_count := v_total_count + v_count;
-- remove all rows that have been expired
-- historical records live in the log table, but we want to keep far_luo_audit small as possible
DELETE FROM utl_d_lms.far_luoa_audit fla
 WHERE EXISTS (SELECT flal.unique_id
          FROM utl_d_lms.far_luoa_audit_log flal
         WHERE flal.status = 'EXPIRED'
           AND flal.deleted_ind = 'N' -- leave any deleted records on the table so they do not keep reappearing
           AND flal.unique_id = fla.unique_id
           AND flal.term_code = rec.term_code);
v_count := SQL%ROWCOUNT;
COMMIT;
v_msg := 'DELETE - ' || rec.term_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
v_total_count := v_total_count + v_count;
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
---      03-04-2022  WGRIFFITH2  --Initial release
---      04-14-2022  WGRIFFITH2  --Now removing EXPIRED records from far_luoa_audit instead of holding the expired records there until ptrm is over
------------------------------------------------------------------------------------------------*/
END etl_lms_far_luoa_audit_log;

PROCEDURE etl_lms_far_luoa_audit_wa(jobnumber   NUMBER,
                                    processid   VARCHAR2,
                                    processname VARCHAR2) IS
/*
* Purpose:
*    - Instructors must post this week's announcement in the faculty course section
* Conditions:
*    - Red: After the assignment due date
     - Yellow: 1 day prior to due date
     - Green: Announcement posted on-time
*/
--DECLARE
--- PARAMS
v_etl_date    DATE := SYSDATE;
v_instance    VARCHAR2(50) := upper('ACCAN'); -- inst from the jams job; used for determining instance
v_partition    NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_msg         VARCHAR2(2000);
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_lms_far_luoa_audit_wa';
v_cat_code    VARCHAR2(2) := 'WA';
-- CURSOR
CURSOR c_terms IS
SELECT ll.term_code,
       MAX(ll.end_date) end_date
  FROM zbtm.terms_by_group_v t
  JOIN utl_d_lms.lms_link ll
    ON ll.term_code = t.term_code
 WHERE 1 = 1
   AND SYSDATE >= ll.start_date - 14
   AND SYSDATE <= ll.end_date + 14
   AND ll.coll_code = 'AC'
 GROUP BY ll.term_code
 ORDER BY 1 DESC;
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
v_msg     := 'START - ' || rec.term_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
MERGE INTO utl_d_lms.far_luoa_audit destination_table
USING (SELECT courses.term_code,
              courses.crn,
              courses.coll_code,
              courses.coll_desc,
              courses.course_code,
              courses.course_sis_id,
              courses.section_sis_id,
              courses.course_id,
              courses.course_section_id,
              fac_course.url,
              courses.camp_code,
              courses.ptrm_code,
              courses.insm_code,
              courses.faculty_pidm,
              courses.faculty_name,
              courses.faculty_email,
              v_cat_code AS compliance_category_code,
              coalesce(fac_course.status_code, '3') AS compliance_status_code,
              coalesce(fac_course.status, 'Weekly Announcements not required at this time.') AS compliance_status_reason,
              v_etl_date audit_date,
              'N' AS deleted_ind,
              NULL AS deleted_reason,
              courses.course_section_id || '_' || v_cat_code || coalesce(fac_course.status_code, '3') || '_' || coalesce(fac_course.luid, courses.faculty_luid) || '_' || coalesce(to_char(fac_course.submission_id), '0987654321') AS unique_id, -- 20204054321_CM2_L2070201_0987654321
              CASE
              WHEN fla.deleted_ind = 'Y' THEN
               0
              WHEN coalesce(fac_course.status_code, '0') = '0' THEN
               0
              WHEN fla.course_section_id IS NOT NULL THEN
               ceil(v_etl_date - coalesce(fla.audit_date, v_etl_date - 1 / 24)) -- coalesce is for the first record entry
              ELSE
               1
              END AS flag_count,
              v_etl_date AS last_modified,
              'ACTIVE' AS status,
              courses.instance
         FROM utl_d_lms.far_luoa_courses courses
         LEFT JOIN (SELECT fu.pidm,
                          fu.luid,
                          s.id AS submission_id,
                          s.submitted_at,
                          a.due_at,
                          'https://luoa.instructure.com/courses/' || e.course_id || '/assignments/' || a.id AS url,
                          CASE
                          WHEN coalesce(s.submitted_at, s.graded_at) IS NULL
                               AND e.type = 'StudentEnrollment' THEN
                           to_char(a.title) || ' needs to be completed before: ' || to_char(CAST(a.due_at AS DATE), 'MM/DD/YYYY hh24:mi:ss')
                          WHEN coalesce(s.submitted_at, s.graded_at) IS NOT NULL THEN
                           to_char(a.title) || ' was completed at: ' || to_char(CAST(coalesce(s.submitted_at, s.graded_at) AS DATE), 'MM/DD/YYYY hh24:mi:ss')
                          ELSE
                           'User has admin role and is exempt.'
                          END AS status,
                          CASE
                          WHEN coalesce(s.submitted_at, s.graded_at) IS NULL
                               AND e.type = 'StudentEnrollment'
                               AND SYSDATE > CAST(a.due_at AS DATE) + 1 THEN -- show red if after the due date +1 - until THUR -then it turns back to green
                           '2'
                          WHEN coalesce(s.submitted_at, s.graded_at) IS NULL
                               AND e.type = 'StudentEnrollment'
                               AND SYSDATE - CAST(a.due_at AS DATE) >= -3 THEN -- show yellow on Friday before and not completed
                           '1'
                          ELSE
                           '0'
                          END AS status_code,
                          c.instance,
                          rank() over(PARTITION BY u.id ORDER BY decode('StudentEnrollment', '1', '0'), coalesce(s.submitted_at, s.graded_at), rownum) ranking
                     FROM zcanvas_data.courses c
                     JOIN zcanvas_data.enrollments e
                       ON e.course_id = c.id
                      AND e.instance = c.instance
                      AND e.workflow_state = 'active'
                      AND c.workflow_state <> 'deleted'
                     JOIN zcanvas_data.course_sections cs
                       ON cs.id = e.course_section_id
                      AND cs.instance = e.instance
                      AND cs.workflow_state <> 'deleted'
                     JOIN zcanvas_data.users u
                       ON u.id = e.user_id
                      AND u.instance = e.instance
                      AND u.workflow_state <> 'deleted'
                     JOIN zcanvas_data.assignments a
                       ON a.context_id = c.id
                      AND a.instance = c.instance
                      AND a.workflow_state <> 'deleted'
                      AND a.title LIKE '%Weekly%Announcement%'
                      AND a.due_at >= trunc(v_etl_date) - 3 -- show yellow on Friday before it was due
                      AND a.due_at < trunc(v_etl_date) + 4 -- show anything until Thursday after it was due
                     LEFT JOIN zcanvas_data.submissions s -- this must be a left join due to DesignerEnrollment
                       ON s.course_id = e.course_id
                      AND s.user_id = u.id
                      AND s.assignment_id = a.id
                      AND s.instance = a.instance
                     JOIN utl_d_lms.faculty_users fu
                       ON fu.instance = c.instance
                      AND fu.user_id = u.id
                    WHERE c.instance = v_instance
                      AND c.name LIKE '%Faculty%Resources%'
                      AND u.name <> 'Test Student') fac_course
           ON fac_course.pidm = courses.faculty_pidm -- have to join on the instructor here NOT the course
          AND fac_course.instance = courses.instance
          AND fac_course.ranking = 1
         LEFT JOIN utl_d_lms.far_luoa_audit fla
           ON fla.unique_id =
              courses.course_section_id || '_' || v_cat_code || coalesce(fac_course.status_code, '3') || '_' || coalesce(fac_course.luid, courses.faculty_luid) || '_' || coalesce(to_char(fac_course.submission_id), '0987654321')
          AND fla.audit_date < v_etl_date -- must be less than or the flag count will not work
        WHERE courses.term_code = rec.term_code) new_records
ON (destination_table.unique_id = new_records.unique_id)
WHEN MATCHED THEN
UPDATE
   SET destination_table.flag_count               = new_records.flag_count,
       destination_table.compliance_status_reason = new_records.compliance_status_reason,
       destination_table.url                      = new_records.url,
       destination_table.last_modified            = new_records.last_modified,
       destination_table.status                   = new_records.status,
       destination_table.instance                 = new_records.instance
WHEN NOT MATCHED THEN
INSERT
(term_code,
 crn,
 coll_code,
 coll_desc,
 course_code,
 course_sis_id,
 section_sis_id,
 course_id,
 course_section_id,
 url,
 camp_code,
 ptrm_code,
 insm_code,
 faculty_pidm,
 faculty_name,
 faculty_email,
 compliance_category_code,
 compliance_status_code,
 compliance_status_reason,
 status,
 instance,
 deleted_ind,
 deleted_reason,
 unique_id,
 flag_count,
 audit_date,
 last_modified)
VALUES
(new_records.term_code,
 new_records.crn,
 new_records.coll_code,
 new_records.coll_desc,
 new_records.course_code,
 new_records.course_sis_id,
 new_records.section_sis_id,
 new_records.course_id,
 new_records.course_section_id,
 new_records.url,
 new_records.camp_code,
 new_records.ptrm_code,
 new_records.insm_code,
 new_records.faculty_pidm,
 new_records.faculty_name,
 new_records.faculty_email,
 new_records.compliance_category_code,
 new_records.compliance_status_code,
 new_records.compliance_status_reason,
 new_records.status,
 new_records.instance,
 new_records.deleted_ind,
 new_records.deleted_reason,
 new_records.unique_id,
 new_records.flag_count,
 new_records.audit_date,
 new_records.last_modified);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'MERGE - ' || rec.term_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
--
dbms_output.put_line('Expiring records when FLAG OCCURRED **AFTER** THE GRADE: ' || rec.term_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ';');
UPDATE utl_d_lms.far_luo_audit fla
   SET (fla.status, fla.flag_count, fla.deleted_ind, fla.deleted_reason) =
       (SELECT 'EXPIRED',
               0,
               'Y',
               'SYSTEM: Latency on the data feed. FAR audit_date >= graded_date. Record deleted / expired.'
          FROM dual)
 WHERE EXISTS (SELECT sa.submission_id,
               flax.audit_date,
               sa.graded_date
          FROM utl_d_lms.far_luoa_audit flax
          JOIN utl_d_lms.rest_submissions sa
            ON sa.instance = flax.instance
           AND sa.term_code = flax.term_code
           AND sa.submission_id = substr(flax.unique_id, instr(flax.unique_id, '_', -1) + 1) -- parse out the submission ID that is in the ref no from the compliance_status_reason
         WHERE flax.compliance_category_code = v_cat_code
           AND flax.compliance_status_code IN ('1', '2')
           AND flax.term_code = rec.term_code
           AND sa.graded_date IS NOT NULL
           AND flax.audit_date >= sa.graded_date
           AND flax.instance = v_instance
           AND flax.unique_id = fla.unique_id);
v_count := v_count + SQL%ROWCOUNT;
COMMIT;
dbms_output.put_line('Expiring records that are no longer active in: ' || rec.term_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ';');
UPDATE utl_d_lms.far_luoa_audit fla
   SET fla.status = 'EXPIRED' -- if the last_modified did NOT get updated on the last run, it is no longer active; EXPIRE records on last day of ptrm
 WHERE fla.compliance_category_code = v_cat_code
   AND fla.term_code = rec.term_code
   AND fla.status = 'ACTIVE'
   AND ((fla.last_modified < v_etl_date) OR (v_etl_date >= rec.end_date + 7));
v_count := v_count + SQL%ROWCOUNT;
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'UPDATE - ' || rec.term_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
v_total_count := v_total_count + v_count;
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
---      06-28-2022  WGRIFFITH2  --Initial release
---      08-08-2022  WGRIFFITH2  --FN appeals, extensions, exemptions, etc. - TKT2537366
------------------------------------------------------------------------------------------------*/
END etl_lms_far_luoa_audit_wa;

PROCEDURE etl_lms_far_luoa_audit_mq(jobnumber   NUMBER,
                                    processid   VARCHAR2,
                                    processname VARCHAR2) IS
/*
* Purpose:
*    - Looks for the meeting quiz for the current month
* Conditions:
*    - Red: 16th of the month
     - Yellow: 8-15th of the month
     - Green: <=7th day
   - Not required during May, July, and December
*/
--DECLARE
--- PARAMS
v_etl_date    DATE := SYSDATE;
v_instance    VARCHAR2(50) := upper('ACCAN'); -- inst from the jams job; used for determining instance
v_partition    NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_msg         VARCHAR2(2000);
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_lms_far_luoa_audit_mq';
v_cat_code    VARCHAR2(2) := 'MQ';
-- CURSOR
CURSOR c_terms IS
SELECT ll.term_code,
       MAX(ll.end_date) end_date
  FROM zbtm.terms_by_group_v t
  JOIN utl_d_lms.lms_link ll
    ON ll.term_code = t.term_code
 WHERE 1 = 1
   AND SYSDATE >= ll.start_date - 14
   AND SYSDATE <= ll.end_date + 14
   AND ll.coll_code = 'AC'
 GROUP BY ll.term_code
 ORDER BY 1 DESC;
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
v_msg     := 'START - ' || rec.term_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
IF to_char(v_etl_date, 'mm') IN ('05', '07', '12') THEN
MERGE INTO utl_d_lms.far_luoa_audit destination_table
USING (SELECT courses.term_code,
              courses.crn,
              courses.coll_code,
              courses.coll_desc,
              courses.course_code,
              courses.course_sis_id,
              courses.section_sis_id,
              courses.course_id,
              courses.course_section_id,
              courses.url,
              courses.camp_code,
              courses.ptrm_code,
              courses.insm_code,
              courses.faculty_pidm,
              courses.faculty_name,
              courses.faculty_email,
              v_cat_code AS compliance_category_code,
              '3' AS compliance_status_code,
              'Faculty Quiz is not required during this month.' AS compliance_status_reason,
              v_etl_date audit_date,
              'N' AS deleted_ind,
              NULL AS deleted_reason,
              courses.course_section_id || '_' || v_cat_code || '3' || '_' || courses.faculty_luid || '_' || to_char(v_etl_date, 'YYYYMM') AS unique_id, -- attaching YYYYMM on the end to make it unique
              0 AS flag_count,
              v_etl_date AS last_modified,
              'ACTIVE' AS status,
              courses.instance
         FROM utl_d_lms.far_luoa_courses courses
         LEFT JOIN utl_d_lms.far_luoa_audit fla
           ON fla.unique_id = courses.course_section_id || '_' || v_cat_code || '3' || '_' || courses.faculty_luid || '_' || to_char(v_etl_date, 'YYYYMM')
          AND fla.audit_date < v_etl_date -- must be less than or the flag count will not work
        WHERE courses.term_code = rec.term_code) new_records
ON (destination_table.unique_id = new_records.unique_id)
WHEN MATCHED THEN
UPDATE
   SET destination_table.flag_count               = new_records.flag_count,
       destination_table.compliance_status_reason = new_records.compliance_status_reason,
       destination_table.url                      = new_records.url,
       destination_table.last_modified            = new_records.last_modified,
       destination_table.status                   = new_records.status,
       destination_table.instance                 = new_records.instance
WHEN NOT MATCHED THEN
INSERT
(term_code,
 crn,
 coll_code,
 coll_desc,
 course_code,
 course_sis_id,
 section_sis_id,
 course_id,
 course_section_id,
 url,
 camp_code,
 ptrm_code,
 insm_code,
 faculty_pidm,
 faculty_name,
 faculty_email,
 compliance_category_code,
 compliance_status_code,
 compliance_status_reason,
 status,
 instance,
 deleted_ind,
 deleted_reason,
 unique_id,
 flag_count,
 audit_date,
 last_modified)
VALUES
(new_records.term_code,
 new_records.crn,
 new_records.coll_code,
 new_records.coll_desc,
 new_records.course_code,
 new_records.course_sis_id,
 new_records.section_sis_id,
 new_records.course_id,
 new_records.course_section_id,
 new_records.url,
 new_records.camp_code,
 new_records.ptrm_code,
 new_records.insm_code,
 new_records.faculty_pidm,
 new_records.faculty_name,
 new_records.faculty_email,
 new_records.compliance_category_code,
 new_records.compliance_status_code,
 new_records.compliance_status_reason,
 new_records.status,
 new_records.instance,
 new_records.deleted_ind,
 new_records.deleted_reason,
 new_records.unique_id,
 new_records.flag_count,
 new_records.audit_date,
 new_records.last_modified);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'MERGE - ' || rec.term_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
ELSE
MERGE INTO utl_d_lms.far_luoa_audit destination_table
USING (SELECT courses.term_code,
              courses.crn,
              courses.coll_code,
              courses.coll_desc,
              courses.course_code,
              courses.course_sis_id,
              courses.section_sis_id,
              courses.course_id,
              courses.course_section_id,
              fac_course.url,
              courses.camp_code,
              courses.ptrm_code,
              courses.insm_code,
              courses.faculty_pidm,
              courses.faculty_name,
              courses.faculty_email,
              v_cat_code AS compliance_category_code,
              coalesce(fac_course.status_code, '3') AS compliance_status_code,
              coalesce(fac_course.status, 'Instructor is not enrolled in faculty course or assignment not found') AS compliance_status_reason,
              v_etl_date audit_date,
              'N' AS deleted_ind,
              NULL AS deleted_reason,
              courses.course_section_id || '_' || v_cat_code || coalesce(fac_course.status_code, '3') || '_' || coalesce(fac_course.luid, courses.faculty_luid) || '_' || coalesce(to_char(fac_course.submission_id), '0987654321') AS unique_id, -- 20204054321_CM2_L2070201_0987654321
              CASE
              WHEN fla.deleted_ind = 'Y' THEN
               0
              WHEN coalesce(fac_course.status_code, '0') = '0' THEN
               0
              WHEN fla.course_section_id IS NOT NULL THEN
               ceil(v_etl_date - coalesce(fla.audit_date, v_etl_date - 1 / 24)) -- coalesce is for the first record entry
              ELSE
               1
              END AS flag_count,
              v_etl_date AS last_modified,
              'ACTIVE' AS status,
              courses.instance
         FROM utl_d_lms.far_luoa_courses courses
         LEFT JOIN (SELECT fu.pidm,
                          fu.luid,
                          s.id AS submission_id,
                          'https://luoa.instructure.com/courses/' || e.course_id || '/assignments/' || a.id AS url,
                          CASE
                          WHEN coalesce(s.submitted_at, s.graded_at) IS NULL
                               AND e.type = 'StudentEnrollment' THEN
                           to_char(a.title) || ' needs to be completed before: ' || to_char(SYSDATE, 'MM') || '/15/' || to_char(SYSDATE, 'YYYY') || ' 11:59 PM.'
                          WHEN coalesce(s.submitted_at, s.graded_at) IS NOT NULL
                               AND e.type = 'StudentEnrollment' THEN
                           to_char(a.title) || ' was completed at: ' || to_char(CAST(s.submitted_at AS DATE), 'MM/DD/YYYY hh24:mi:ss')
                          WHEN coalesce(s.submitted_at, s.graded_at) IS NOT NULL
                               AND e.type <> 'StudentEnrollment' THEN
                           to_char(a.title) || ' was completed at: ' || to_char(CAST(s.submitted_at AS DATE), 'MM/DD/YYYY hh24:mi:ss')
                          ELSE
                           'User has admin role and is exempt.'
                          END AS status,
                          CASE
                          WHEN coalesce(s.submitted_at, s.graded_at) IS NULL
                               AND e.type = 'StudentEnrollment'
                               AND to_number(to_char(SYSDATE, 'DD')) BETWEEN 7 AND 15 THEN
                           '1'
                          WHEN coalesce(s.submitted_at, s.graded_at) IS NULL
                               AND e.type = 'StudentEnrollment'
                               AND to_number(to_char(SYSDATE, 'DD')) > 15 THEN
                           '2'
                          ELSE
                           '0'
                          END AS status_code,
                          c.instance,
                          rank() over(PARTITION BY u.id ORDER BY decode('StudentEnrollment', '1', '0'), coalesce(s.submitted_at, s.graded_at), rownum) ranking
                     FROM zcanvas_data.courses c
                     JOIN zcanvas_data.enrollments e
                       ON e.course_id = c.id
                      AND e.instance = c.instance
                      AND e.workflow_state = 'active'
                      AND c.workflow_state <> 'deleted'
                     JOIN zcanvas_data.course_sections cs
                       ON cs.id = e.course_section_id
                      AND cs.instance = e.instance
                      AND cs.workflow_state <> 'deleted'
                     JOIN zcanvas_data.users u
                       ON u.id = e.user_id
                      AND u.instance = e.instance
                      AND u.workflow_state <> 'deleted'
                     JOIN zcanvas_data.assignments a
                       ON a.context_id = c.id
                      AND a.instance = c.instance
                      AND a.workflow_state <> 'deleted'
                      AND a.title LIKE '%Faculty%Meeting%'
                      AND a.due_at >= trunc(v_etl_date, 'mm') -- first day of the month
                      AND a.due_at < trunc(last_day(v_etl_date)) + 1
                     LEFT JOIN zcanvas_data.submissions s -- this must be a left join due to DesignerEnrollment
                       ON s.course_id = e.course_id
                      AND s.user_id = u.id
                      AND s.assignment_id = a.id
                      AND s.instance = a.instance
                     JOIN utl_d_lms.faculty_users fu
                       ON fu.instance = c.instance
                      AND fu.user_id = u.id
                    WHERE c.instance = v_instance
                      AND c.name LIKE '%Faculty%Resources%'
                      AND u.name <> 'Test Student') fac_course
           ON fac_course.pidm = courses.faculty_pidm -- have to join on the instructor here NOT the course
          AND fac_course.instance = courses.instance
          AND fac_course.ranking = 1
         LEFT JOIN utl_d_lms.far_luoa_audit fla
           ON fla.unique_id =
              courses.course_section_id || '_' || v_cat_code || coalesce(fac_course.status_code, '3') || '_' || coalesce(fac_course.luid, courses.faculty_luid) || '_' || coalesce(to_char(fac_course.submission_id), '0987654321')
          AND fla.audit_date < v_etl_date -- must be less than or the flag count will not work
        WHERE courses.term_code = rec.term_code) new_records
ON (destination_table.unique_id = new_records.unique_id)
WHEN MATCHED THEN
UPDATE
   SET destination_table.flag_count               = new_records.flag_count,
       destination_table.compliance_status_reason = new_records.compliance_status_reason,
       destination_table.url                      = new_records.url,
       destination_table.last_modified            = new_records.last_modified,
       destination_table.status                   = new_records.status,
       destination_table.instance                 = new_records.instance
WHEN NOT MATCHED THEN
INSERT
(term_code,
 crn,
 coll_code,
 coll_desc,
 course_code,
 course_sis_id,
 section_sis_id,
 course_id,
 course_section_id,
 url,
 camp_code,
 ptrm_code,
 insm_code,
 faculty_pidm,
 faculty_name,
 faculty_email,
 compliance_category_code,
 compliance_status_code,
 compliance_status_reason,
 status,
 instance,
 deleted_ind,
 deleted_reason,
 unique_id,
 flag_count,
 audit_date,
 last_modified)
VALUES
(new_records.term_code,
 new_records.crn,
 new_records.coll_code,
 new_records.coll_desc,
 new_records.course_code,
 new_records.course_sis_id,
 new_records.section_sis_id,
 new_records.course_id,
 new_records.course_section_id,
 new_records.url,
 new_records.camp_code,
 new_records.ptrm_code,
 new_records.insm_code,
 new_records.faculty_pidm,
 new_records.faculty_name,
 new_records.faculty_email,
 new_records.compliance_category_code,
 new_records.compliance_status_code,
 new_records.compliance_status_reason,
 new_records.status,
 new_records.instance,
 new_records.deleted_ind,
 new_records.deleted_reason,
 new_records.unique_id,
 new_records.flag_count,
 new_records.audit_date,
 new_records.last_modified);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'MERGE - ' || rec.term_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
END IF;
--
dbms_output.put_line('Expiring records when FLAG OCCURRED **AFTER** THE GRADE: ' || rec.term_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ';');
UPDATE utl_d_lms.far_luo_audit fla
   SET (fla.status, fla.flag_count, fla.deleted_ind, fla.deleted_reason) =
       (SELECT 'EXPIRED',
               0,
               'Y',
               'SYSTEM: Latency on the data feed. FAR audit_date >= graded_date. Record deleted / expired.'
          FROM dual)
 WHERE EXISTS (SELECT sa.submission_id,
               flax.audit_date,
               sa.graded_date
          FROM utl_d_lms.far_luoa_audit flax
          JOIN utl_d_lms.rest_submissions sa
            ON sa.instance = flax.instance
           AND sa.term_code = flax.term_code
           AND sa.submission_id = substr(flax.unique_id, instr(flax.unique_id, '_', -1) + 1) -- parse out the submission ID that is in the ref no from the compliance_status_reason
         WHERE flax.compliance_category_code = v_cat_code
           AND flax.compliance_status_code IN ('1', '2')
           AND flax.term_code = rec.term_code
           AND sa.graded_date IS NOT NULL
           AND flax.audit_date >= sa.graded_date
           AND flax.instance = v_instance
           AND flax.unique_id = fla.unique_id);
v_count := v_count + SQL%ROWCOUNT;
COMMIT;
dbms_output.put_line('Expiring records that are no longer active in: ' || rec.term_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ';');
UPDATE utl_d_lms.far_luoa_audit fla
   SET fla.status = 'EXPIRED' -- if the last_modified did NOT get updated on the last run, it is no longer active; EXPIRE records on last day of ptrm
 WHERE fla.compliance_category_code = v_cat_code
   AND fla.term_code = rec.term_code
   AND fla.status = 'ACTIVE'
   AND ((fla.last_modified < v_etl_date) OR (v_etl_date >= rec.end_date + 7));
v_count := v_count + SQL%ROWCOUNT;
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'UPDATE - ' || rec.term_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
v_total_count := v_total_count + v_count;
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
---      03-04-2022  WGRIFFITH2  --Initial release
---      05-03-2022  WGRIFFITH2  --Not required during May, July, and December
------------------------------------------------------------------------------------------------*/
END etl_lms_far_luoa_audit_mq;

PROCEDURE etl_lms_far_luoa_audit_mm(jobnumber   NUMBER,
                                    processid   VARCHAR2,
                                    processname VARCHAR2) IS
/*
* Purpose:
*    - Looks for the monthly message for the current month
* Conditions:
*    - Red: 16th of the month
     - Yellow: 8-15th of the month
     - Green: <=7th day
*/
--DECLARE
--- PARAMS
v_etl_date    DATE := SYSDATE;
v_instance    VARCHAR2(50) := upper('ACCAN'); -- inst from the jams job; used for determining instance
v_partition    NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_msg         VARCHAR2(2000);
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_lms_far_luoa_audit_mm';
v_cat_code    VARCHAR2(2) := 'MM';
-- CURSOR
CURSOR c_terms IS
SELECT ll.term_code,
       MAX(ll.end_date) end_date
  FROM zbtm.terms_by_group_v t
  JOIN utl_d_lms.lms_link ll
    ON ll.term_code = t.term_code
 WHERE 1 = 1
   AND SYSDATE >= ll.start_date - 14
   AND SYSDATE <= ll.end_date + 14
   AND ll.coll_code = 'AC'
 GROUP BY ll.term_code
 ORDER BY 1 DESC;
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
v_msg     := 'START - ' || rec.term_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
IF to_char(v_etl_date, 'mm') IN ('13') THEN
MERGE INTO utl_d_lms.far_luoa_audit destination_table
USING (SELECT courses.term_code,
              courses.crn,
              courses.coll_code,
              courses.coll_desc,
              courses.course_code,
              courses.course_sis_id,
              courses.section_sis_id,
              courses.course_id,
              courses.course_section_id,
              courses.url,
              courses.camp_code,
              courses.ptrm_code,
              courses.insm_code,
              courses.faculty_pidm,
              courses.faculty_name,
              courses.faculty_email,
              v_cat_code AS compliance_category_code,
              '3' AS compliance_status_code, -- '3' means grayed out
              'Monthly Message is not required during this month.' AS compliance_status_reason,
              v_etl_date AS audit_date,
              'N' AS deleted_ind,
              NULL AS deleted_reason,
              courses.course_section_id || '_' || v_cat_code || '3' || '_' || courses.faculty_luid || '_' || to_char(v_etl_date, 'YYYYMM') AS unique_id, -- attaching YYYYMM on the end to make it unique
              0 AS flag_count,
              v_etl_date AS last_modified,
              'ACTIVE' AS status,
              courses.instance
         FROM utl_d_lms.far_luoa_courses courses
         LEFT JOIN utl_d_lms.far_luoa_audit fla
           ON fla.unique_id = courses.course_section_id || '_' || v_cat_code || '3' || '_' || courses.faculty_luid || '_' || to_char(v_etl_date, 'YYYYMM')
          AND fla.audit_date < v_etl_date -- must be less than or the flag count will not work
        WHERE courses.term_code = rec.term_code) new_records
ON (destination_table.unique_id = new_records.unique_id)
WHEN MATCHED THEN
UPDATE
   SET destination_table.flag_count               = new_records.flag_count,
       destination_table.compliance_status_reason = new_records.compliance_status_reason,
       destination_table.url                      = new_records.url,
       destination_table.last_modified            = new_records.last_modified,
       destination_table.status                   = new_records.status,
       destination_table.instance                 = new_records.instance
WHEN NOT MATCHED THEN
INSERT
(term_code,
 crn,
 coll_code,
 coll_desc,
 course_code,
 course_sis_id,
 section_sis_id,
 course_id,
 course_section_id,
 url,
 camp_code,
 ptrm_code,
 insm_code,
 faculty_pidm,
 faculty_name,
 faculty_email,
 compliance_category_code,
 compliance_status_code,
 compliance_status_reason,
 status,
 instance,
 deleted_ind,
 deleted_reason,
 unique_id,
 flag_count,
 audit_date,
 last_modified)
VALUES
(new_records.term_code,
 new_records.crn,
 new_records.coll_code,
 new_records.coll_desc,
 new_records.course_code,
 new_records.course_sis_id,
 new_records.section_sis_id,
 new_records.course_id,
 new_records.course_section_id,
 new_records.url,
 new_records.camp_code,
 new_records.ptrm_code,
 new_records.insm_code,
 new_records.faculty_pidm,
 new_records.faculty_name,
 new_records.faculty_email,
 new_records.compliance_category_code,
 new_records.compliance_status_code,
 new_records.compliance_status_reason,
 new_records.status,
 new_records.instance,
 new_records.deleted_ind,
 new_records.deleted_reason,
 new_records.unique_id,
 new_records.flag_count,
 new_records.audit_date,
 new_records.last_modified);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'MERGE - ' || rec.term_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
ELSE
MERGE INTO utl_d_lms.far_luoa_audit destination_table
USING (SELECT courses.term_code,
              courses.crn,
              courses.coll_code,
              courses.coll_desc,
              courses.course_code,
              courses.course_sis_id,
              courses.section_sis_id,
              courses.course_id,
              courses.course_section_id,
              fac_course.url,
              courses.camp_code,
              courses.ptrm_code,
              courses.insm_code,
              courses.faculty_pidm,
              courses.faculty_name,
              courses.faculty_email,
              v_cat_code AS compliance_category_code,
              coalesce(fac_course.status_code, '3') AS compliance_status_code,
              coalesce(fac_course.status, 'Instructor is not enrolled in faculty course or assignment not found') AS compliance_status_reason,
              v_etl_date audit_date,
              'N' AS deleted_ind,
              NULL AS deleted_reason,
              courses.course_section_id || '_' || v_cat_code || coalesce(fac_course.status_code, '3') || '_' || coalesce(fac_course.luid, courses.faculty_luid) || '_' || coalesce(to_char(fac_course.submission_id), '0987654321') AS unique_id,
              CASE
              WHEN fla.deleted_ind = 'Y' THEN
               0
              WHEN coalesce(fac_course.status_code, '0') = '0' THEN
               0
              WHEN fla.course_section_id IS NOT NULL THEN
               ceil(v_etl_date - coalesce(fla.audit_date, v_etl_date - 1 / 24)) -- coalesce is for the first record entry
              ELSE
               1
              END AS flag_count,
              v_etl_date AS last_modified,
              'ACTIVE' AS status,
              courses.instance
         FROM utl_d_lms.far_luoa_courses courses
         LEFT JOIN (SELECT fu.pidm,
                          fu.luid,
                          s.id AS submission_id,
                          'https://luoa.instructure.com/courses/' || e.course_id || '/assignments/' || a.id AS url,
                          CASE
                          WHEN coalesce(s.submitted_at, s.graded_at) IS NULL
                               AND e.type = 'StudentEnrollment' THEN
                           to_char(a.title) || ' needs to be completed before: ' || to_char(SYSDATE, 'MM') || '/15/' || to_char(SYSDATE, 'YYYY') || ' 11:59 PM.'
                          WHEN coalesce(s.submitted_at, s.graded_at) IS NOT NULL
                               AND e.type = 'StudentEnrollment' THEN
                           to_char(a.title) || ' was posted at: ' || to_char(CAST(s.submitted_at AS DATE), 'MM/DD/YYYY hh24:mi:ss')
                          WHEN coalesce(s.submitted_at, s.graded_at) IS NOT NULL
                               AND e.type <> 'StudentEnrollment' THEN
                           to_char(a.title) || ' was posted at: ' || to_char(CAST(s.submitted_at AS DATE), 'MM/DD/YYYY hh24:mi:ss')
                          ELSE
                           'User has admin role and is exempt.'
                          END AS status,
                          CASE
                          WHEN coalesce(s.submitted_at, s.graded_at) IS NULL
                               AND e.type = 'StudentEnrollment'
                               AND to_number(to_char(SYSDATE, 'DD')) BETWEEN 7 AND 15 THEN
                           '1'
                          WHEN coalesce(s.submitted_at, s.graded_at) IS NULL
                               AND e.type = 'StudentEnrollment'
                               AND to_number(to_char(SYSDATE, 'DD')) > 15 THEN
                           '2'
                          ELSE
                           '0'
                          END AS status_code,
                          c.instance,
                          rank() over(PARTITION BY u.id ORDER BY decode('StudentEnrollment', '1', '0'), coalesce(s.submitted_at, s.graded_at), rownum) ranking
                     FROM zcanvas_data.courses c
                     JOIN zcanvas_data.enrollments e
                       ON e.course_id = c.id
                      AND e.instance = c.instance
                      AND e.workflow_state = 'active'
                      AND c.workflow_state <> 'deleted'
                     JOIN zcanvas_data.course_sections cs
                       ON cs.id = e.course_section_id
                      AND cs.instance = e.instance
                      AND cs.workflow_state <> 'deleted'
                     JOIN zcanvas_data.users u
                       ON u.id = e.user_id
                      AND u.instance = e.instance
                      AND u.workflow_state <> 'deleted'
                     JOIN zcanvas_data.assignments a
                       ON a.context_id = c.id
                      AND a.instance = c.instance
                      AND a.workflow_state <> 'deleted'
                      AND a.title LIKE '%Monthly%Message%'
                      AND a.due_at >= trunc(v_etl_date, 'mm') -- first day of the month
                      AND a.due_at < trunc(last_day(v_etl_date)) + 1
                     LEFT JOIN zcanvas_data.submissions s -- this must be a left join due to DesignerEnrollment
                       ON s.course_id = e.course_id
                      AND s.user_id = u.id
                      AND s.assignment_id = a.id
                      AND s.instance = a.instance
                     JOIN utl_d_lms.faculty_users fu
                       ON fu.instance = c.instance
                      AND fu.user_id = u.id
                    WHERE c.instance = v_instance
                      AND c.name LIKE '%Faculty%Resources%'
                      AND u.name <> 'Test Student') fac_course
           ON fac_course.pidm = courses.faculty_pidm -- have to join on the instructor here NOT the course
          AND fac_course.instance = courses.instance
          AND fac_course.ranking = 1
         LEFT JOIN utl_d_lms.far_luoa_audit fla
           ON fla.unique_id =
              courses.course_section_id || '_' || v_cat_code || coalesce(fac_course.status_code, '3') || '_' || coalesce(fac_course.luid, courses.faculty_luid) || '_' || coalesce(to_char(fac_course.submission_id), '0987654321')
          AND fla.audit_date < v_etl_date -- must be less than or the flag count will not work
        WHERE courses.term_code = rec.term_code) new_records
ON (destination_table.unique_id = new_records.unique_id)
WHEN MATCHED THEN
UPDATE
   SET destination_table.flag_count               = new_records.flag_count,
       destination_table.compliance_status_reason = new_records.compliance_status_reason,
       destination_table.url                      = new_records.url,
       destination_table.last_modified            = new_records.last_modified,
       destination_table.status                   = new_records.status,
       destination_table.instance                 = new_records.instance
WHEN NOT MATCHED THEN
INSERT
(term_code,
 crn,
 coll_code,
 coll_desc,
 course_code,
 course_sis_id,
 section_sis_id,
 course_id,
 course_section_id,
 url,
 camp_code,
 ptrm_code,
 insm_code,
 faculty_pidm,
 faculty_name,
 faculty_email,
 compliance_category_code,
 compliance_status_code,
 compliance_status_reason,
 status,
 instance,
 deleted_ind,
 deleted_reason,
 unique_id,
 flag_count,
 audit_date,
 last_modified)
VALUES
(new_records.term_code,
 new_records.crn,
 new_records.coll_code,
 new_records.coll_desc,
 new_records.course_code,
 new_records.course_sis_id,
 new_records.section_sis_id,
 new_records.course_id,
 new_records.course_section_id,
 new_records.url,
 new_records.camp_code,
 new_records.ptrm_code,
 new_records.insm_code,
 new_records.faculty_pidm,
 new_records.faculty_name,
 new_records.faculty_email,
 new_records.compliance_category_code,
 new_records.compliance_status_code,
 new_records.compliance_status_reason,
 new_records.status,
 new_records.instance,
 new_records.deleted_ind,
 new_records.deleted_reason,
 new_records.unique_id,
 new_records.flag_count,
 new_records.audit_date,
 new_records.last_modified);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'MERGE - ' || rec.term_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
END IF;
--
dbms_output.put_line('Expiring records when FLAG OCCURRED **AFTER** THE GRADE: ' || rec.term_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ';');
UPDATE utl_d_lms.far_luo_audit fla
   SET (fla.status, fla.flag_count, fla.deleted_ind, fla.deleted_reason) =
       (SELECT 'EXPIRED',
               0,
               'Y',
               'SYSTEM: Latency on the data feed. FAR audit_date >= graded_date. Record deleted / expired.'
          FROM dual)
 WHERE EXISTS (SELECT sa.submission_id,
               flax.audit_date,
               sa.graded_date
          FROM utl_d_lms.far_luoa_audit flax
          JOIN utl_d_lms.rest_submissions sa
            ON sa.instance = flax.instance
           AND sa.term_code = flax.term_code
           AND sa.submission_id = substr(flax.unique_id, instr(flax.unique_id, '_', -1) + 1) -- parse out the submission ID that is in the ref no from the compliance_status_reason
         WHERE flax.compliance_category_code = v_cat_code
           AND flax.compliance_status_code IN ('1', '2')
           AND flax.term_code = rec.term_code
           AND sa.graded_date IS NOT NULL
           AND flax.audit_date >= sa.graded_date
           AND flax.instance = v_instance
           AND flax.unique_id = fla.unique_id);
v_count := v_count + SQL%ROWCOUNT;
COMMIT;
dbms_output.put_line('Expiring records that are no longer active in: ' || rec.term_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ';');
UPDATE utl_d_lms.far_luoa_audit fla
   SET fla.status = 'EXPIRED' -- if the last_modified did NOT get updated on the last run, it is no longer active; EXPIRE records on last day of ptrm
 WHERE fla.compliance_category_code = v_cat_code
   AND fla.term_code = rec.term_code
   AND fla.status = 'ACTIVE'
   AND ((fla.last_modified < v_etl_date) OR (v_etl_date >= rec.end_date + 7));
v_count := v_count + SQL%ROWCOUNT;
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'UPDATE - ' || rec.term_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
v_total_count := v_total_count + v_count;
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
---      03-04-2022  WGRIFFITH2  --Initial release
---      05-03-2022  WGRIFFITH2  --Monthly message not required during May, July, and December
------------------------------------------------------------------------------------------------*/
END etl_lms_far_luoa_audit_mm;

PROCEDURE etl_lms_far_luoa_audit_gc(jobnumber   NUMBER,
                                    processid   VARCHAR2,
                                    processname VARCHAR2) IS
/*
* Purpose:
*    - Looks for assignments that need to be graded
* Conditions:
*    - Red: > 48 hours for quizzes; >4 days for non-quiz
     - Yellow: 0 – 47.99 hours; 0-3.99 days for non-quiz
     - Green: No grading required
   - DO NOT COUNT WEEKENDS OR HOLIDAYS TIME AGAINST CLOCK
*/
--DECLARE
--- PARAMS
v_etl_date    DATE := SYSDATE;
v_instance    VARCHAR2(50) := upper('ACCAN'); -- inst from the jams job; used for determining instance
v_partition    NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_msg         VARCHAR2(2000);
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_lms_far_luoa_audit_gc';
v_cat_code    VARCHAR2(2) := 'GC';
-- CURSOR
CURSOR c_terms IS
SELECT ll.term_code,
       MAX(ll.end_date) end_date
  FROM zbtm.terms_by_group_v t
  JOIN utl_d_lms.lms_link ll
    ON ll.term_code = t.term_code
 WHERE 1 = 1
   AND SYSDATE >= ll.start_date - 14
   AND SYSDATE <= ll.end_date + 14
   AND ll.coll_code = 'AC'
 GROUP BY ll.term_code
 ORDER BY 1 DESC;
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
v_msg     := 'START - ' || rec.term_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
INSERT INTO utl_d_lms.far_luoa_audit_gc_gtt
(term_code,
 crn,
 course_section_id,
 luid,
 pidm,
 user_id,
 first_name,
 last_name,
 assignment_id,
 submission_id,
 submitted_at,
 submitted_date,
 submission_type,
 title,
 url,
 instance)
SELECT ll.term_code,
       ll.crn,
       ll.course_section_id,
       su.luid,
       su.pidm,
       su.user_id,
       su.first_name,
       su.last_name,
       sa.assignment_id,
       sa.submission_id,
       sa.submitted_date AS submitted_at,
       trunc(CAST(sa.submitted_date AS DATE)) - 1 / (24 * 60 * 60) + 1 AS submitted_date, -- -- add the 11:59PM to the date
       sa.submission_types AS submission_type,
       sa.title,
       'https://luoa.instructure.com/users/' || fu.user_id || '/teacher_activity/course/' || ll.course_id AS url,
       ll.instance
  FROM utl_d_lms.student_assignments sa
  JOIN utl_d_lms.lms_link ll
    ON sa.course_section_id = ll.course_section_id
   AND ll.instance = v_instance
   AND ll.term_code = rec.term_code
  JOIN utl_d_lms.far_luoa_courses courses
    ON courses.course_section_id = ll.course_section_id
   AND courses.instance = ll.instance
  JOIN utl_d_lms.faculty_users fu
    ON fu.instance = ll.instance
   AND fu.pidm = courses.faculty_pidm
  JOIN utl_d_lms.student_users su
    ON su.user_id = sa.user_id
   AND su.instance = ll.instance
  JOIN utl_d_aim.szrcrse crse -- student must be enrolled and have banner connection
    ON crse.pidm = su.pidm
   AND crse.crn = ll.crn
   AND crse.term_code = ll.term_code
   AND crse.final_grade IS NULL
  JOIN zsaturn.szrlevl l
    ON l.szrlevl_levl_code = crse.levl_code
   AND l.szrlevl_has_awardable_cred = 'Y' -- remove EM
 WHERE 1 = 1
   AND coalesce(sa.points_possible, 0) > 0
   AND sa.submitted_date IS NOT NULL
   AND sa.workflow_state IN ('submitted', 'pending_review')
   AND trunc(CAST(sa.submitted_date AS DATE)) < trunc(SYSDATE); -- show day after submit
v_count := SQL%ROWCOUNT; -- DO NOT COMMIT HERE!!
v_msg   := ' rows inserted into far_luoa_audit_gc_gtt: ' || v_count;
dbms_output.put_line(v_msg);
MERGE INTO utl_d_lms.far_luoa_audit destination_table
USING (SELECT courses.term_code,
              courses.crn,
              courses.coll_code,
              courses.coll_desc,
              courses.course_code,
              courses.course_sis_id,
              courses.section_sis_id,
              courses.course_id,
              courses.course_section_id,
              submitted.url,
              courses.camp_code,
              courses.ptrm_code,
              courses.insm_code,
              courses.faculty_pidm,
              courses.faculty_name,
              courses.faculty_email,
              v_cat_code AS compliance_category_code,
              CASE
              WHEN lap.fn_grade_appeal IS NOT NULL -- if there is a recent FN appeal and they have submissions, they will remain yellow until completed
               THEN
               to_char(submitted.title) || ' needs grading before: ' || to_char(lap.fn_grade_appeal + (coalesce(weekends.counted, 0) + coalesce(holi_days.counted, 0)) + 0, 'MM/DD/YYYY hh24:mi:ss') || '. Student: ' || submitted.first_name || ' ' ||
               submitted.last_name || '-' || lpad(to_char(submitted.luid), 9, 'L00000000')
              WHEN coalesce(submitted.submission_type, 'X') = 'online_quiz'
                   AND v_etl_date > submitted.submitted_date + (coalesce(weekends.counted, 0) + coalesce(holi_days.counted, 0))
                   AND v_etl_date <= submitted.submitted_date + (coalesce(weekends.counted, 0) + coalesce(holi_days.counted, 0)) + 3 THEN
               to_char(submitted.title) || ' needs grading before: ' || to_char(submitted.submitted_date + (coalesce(weekends.counted, 0) + coalesce(holi_days.counted, 0)) + 3, 'MM/DD/YYYY hh24:mi:ss') || '. Student: ' ||
               submitted.first_name || ' ' || submitted.last_name || '-' || lpad(to_char(submitted.luid), 9, 'L00000000')
              WHEN coalesce(submitted.submission_type, 'X') = 'online_quiz'
                   AND v_etl_date > submitted.submitted_date + (coalesce(weekends.counted, 0) + coalesce(holi_days.counted, 0)) + 3 THEN
               to_char(submitted.title) || ' needs grading before: ' || to_char(submitted.submitted_date + (coalesce(weekends.counted, 0) + coalesce(holi_days.counted, 0)) + 3, 'MM/DD/YYYY hh24:mi:ss') || '. Student: ' ||
               submitted.first_name || ' ' || submitted.last_name || '-' || lpad(to_char(submitted.luid), 9, 'L00000000')
              WHEN coalesce(submitted.submission_type, 'X') <> 'online_quiz'
                   AND v_etl_date > submitted.submitted_date + (coalesce(weekends.counted, 0) + coalesce(holi_days.counted, 0))
                   AND v_etl_date <= submitted.submitted_date + (coalesce(weekends.counted, 0) + coalesce(holi_days.counted, 0)) + 4 THEN
               to_char(submitted.title) || ' needs grading before: ' || to_char(submitted.submitted_date + (coalesce(weekends.counted, 0) + coalesce(holi_days.counted, 0)) + 4, 'MM/DD/YYYY hh24:mi:ss') || '. Student: ' ||
               submitted.first_name || ' ' || submitted.last_name || '-' || lpad(to_char(submitted.luid), 9, 'L00000000')
              WHEN coalesce(submitted.submission_type, 'X') <> 'online_quiz'
                   AND v_etl_date > submitted.submitted_date + (coalesce(weekends.counted, 0) + coalesce(holi_days.counted, 0)) + 4 THEN
               to_char(submitted.title) || ' needs grading before: ' || to_char(submitted.submitted_date + (coalesce(weekends.counted, 0) + coalesce(holi_days.counted, 0)) + 4, 'MM/DD/YYYY hh24:mi:ss') || '. Student: ' ||
               submitted.first_name || ' ' || submitted.last_name || '-' || lpad(to_char(submitted.luid), 9, 'L00000000')
              WHEN coalesce(submitted.submission_type, 'X') = 'online_quiz' -- show info even though it is green
                   AND v_etl_date > submitted.submitted_date + (coalesce(weekends.counted, 0) + coalesce(holi_days.counted, 0))
                   AND v_etl_date <= submitted.submitted_date + (coalesce(weekends.counted, 0) + coalesce(holi_days.counted, 0)) + 1 THEN
               to_char(submitted.title) || ' needs grading before: ' || to_char(submitted.submitted_date + (coalesce(weekends.counted, 0) + coalesce(holi_days.counted, 0)) + 3, 'MM/DD/YYYY hh24:mi:ss') || '. Student: ' ||
               submitted.first_name || ' ' || submitted.last_name || '-' || lpad(to_char(submitted.luid), 9, 'L00000000')
              WHEN coalesce(submitted.submission_type, 'X') <> 'online_quiz'
                   AND v_etl_date > submitted.submitted_date + (coalesce(weekends.counted, 0) + coalesce(holi_days.counted, 0))
                   AND v_etl_date <= submitted.submitted_date + (coalesce(weekends.counted, 0) + coalesce(holi_days.counted, 0)) + 1 THEN
               to_char(submitted.title) || ' needs grading before: ' || to_char(submitted.submitted_date + (coalesce(weekends.counted, 0) + coalesce(holi_days.counted, 0)) + 4, 'MM/DD/YYYY hh24:mi:ss') || '. Student: ' ||
               submitted.first_name || ' ' || submitted.last_name || '-' || lpad(to_char(submitted.luid), 9, 'L00000000')
              ELSE
               'No grading required'
              END AS compliance_status_reason,
              CASE
              WHEN lap.fn_grade_appeal IS NOT NULL THEN -- if there is a recent FN appeal and they have submissions, they will remain yellow until completed
               '1'
              WHEN coalesce(submitted.submission_type, 'X') = 'online_quiz'
                   AND v_etl_date > submitted.submitted_date + (coalesce(weekends.counted, 0) + coalesce(holi_days.counted, 0))
                   AND v_etl_date <= submitted.submitted_date + (coalesce(weekends.counted, 0) + coalesce(holi_days.counted, 0)) + 3 THEN
               '1'
              WHEN coalesce(submitted.submission_type, 'X') = 'online_quiz'
                   AND v_etl_date > submitted.submitted_date + (coalesce(weekends.counted, 0) + coalesce(holi_days.counted, 0)) + 3 THEN
               '2'
              WHEN coalesce(submitted.submission_type, 'X') <> 'online_quiz'
                   AND v_etl_date > submitted.submitted_date + (coalesce(weekends.counted, 0) + coalesce(holi_days.counted, 0))
                   AND v_etl_date <= submitted.submitted_date + (coalesce(weekends.counted, 0) + coalesce(holi_days.counted, 0)) + 4 THEN
               '1'
              WHEN coalesce(submitted.submission_type, 'X') <> 'online_quiz'
                   AND v_etl_date > submitted.submitted_date + (coalesce(weekends.counted, 0) + coalesce(holi_days.counted, 0)) + 4 THEN
               '2'
              ELSE
               '0'
              END AS compliance_status_code,
              v_etl_date audit_date,
              'N' AS deleted_ind,
              NULL AS deleted_reason,
              CASE
              WHEN lap.fn_grade_appeal IS NOT NULL THEN -- if there is a recent FN appeal and they have submissions, they will remain yellow until completed
               courses.course_section_id || '_' || v_cat_code || '1' || '_' || submitted.luid || '_' || to_char(submitted.submission_id)
              WHEN coalesce(submitted.submission_type, 'X') = 'online_quiz'
                   AND v_etl_date > submitted.submitted_date + (coalesce(weekends.counted, 0) + coalesce(holi_days.counted, 0))
                   AND v_etl_date <= submitted.submitted_date + (coalesce(weekends.counted, 0) + coalesce(holi_days.counted, 0)) + 3 THEN
               courses.course_section_id || '_' || v_cat_code || '1' || '_' || submitted.luid || '_' || to_char(submitted.submission_id)
              WHEN coalesce(submitted.submission_type, 'X') = 'online_quiz'
                   AND v_etl_date > submitted.submitted_date + (coalesce(weekends.counted, 0) + coalesce(holi_days.counted, 0)) + 3 THEN
               courses.course_section_id || '_' || v_cat_code || '2' || '_' || submitted.luid || '_' || to_char(submitted.submission_id)
              WHEN coalesce(submitted.submission_type, 'X') <> 'online_quiz'
                   AND v_etl_date > submitted.submitted_date + (coalesce(weekends.counted, 0) + coalesce(holi_days.counted, 0))
                   AND v_etl_date <= submitted.submitted_date + (coalesce(weekends.counted, 0) + coalesce(holi_days.counted, 0)) + 4 THEN
               courses.course_section_id || '_' || v_cat_code || '1' || '_' || submitted.luid || '_' || to_char(submitted.submission_id)
              WHEN coalesce(submitted.submission_type, 'X') <> 'online_quiz'
                   AND v_etl_date > submitted.submitted_date + (coalesce(weekends.counted, 0) + coalesce(holi_days.counted, 0)) + 4 THEN
               courses.course_section_id || '_' || v_cat_code || '2' || '_' || submitted.luid || '_' || to_char(submitted.submission_id)
              ELSE
               courses.course_section_id || '_' || v_cat_code || '0' || '_' || submitted.luid || '_' || to_char(submitted.submission_id)
              END AS unique_id,
              CASE
              WHEN fla.deleted_ind = 'Y' THEN
               0
              WHEN submitted.course_section_id IS NOT NULL THEN
               ceil(v_etl_date - coalesce(fla.audit_date, v_etl_date - 1 / 24)) -- coalesce is for the first record entry
              ELSE
               1
              END AS flag_count,
              v_etl_date AS last_modified,
              'ACTIVE' AS status,
              courses.instance
         FROM utl_d_lms.far_luoa_courses courses
         JOIN utl_d_lms.far_luoa_audit_gc_gtt submitted
           ON submitted.course_section_id = courses.course_section_id
          AND submitted.instance = courses.instance
         LEFT JOIN (SELECT submitted.crn, -- COUNT NUMBER OF WEEKEND DAYS SINCE SUBMITTED_AT
                          submitted.term_code,
                          submitted.user_id,
                          submitted.submission_id,
                          COUNT(*) AS counted
                     FROM utl_d_lms.far_luoa_audit_gc_gtt submitted
                     JOIN utl_d_aa.crscalendar cal
                       ON cal.crn = submitted.crn
                      AND cal.term_code = submitted.term_code
                      AND cal.dte >= submitted.submitted_at
                      AND cal.dte < (v_etl_date)
                      AND cal.day_of_week IN ('Saturday', 'Sunday')
                    GROUP BY submitted.crn,
                             submitted.term_code,
                             submitted.user_id,
                             submitted.submission_id) weekends
           ON weekends.crn = submitted.crn
          AND weekends.term_code = submitted.term_code
          AND weekends.user_id = submitted.user_id
          AND weekends.submission_id = submitted.submission_id
         LEFT JOIN (SELECT submitted.crn, -- COUNT NUMBER OF HOLIDAYS SINCE SUBMITTED_AT
                          submitted.term_code,
                          submitted.user_id,
                          submitted.submission_id,
                          COUNT(*) AS counted
                     FROM utl_d_lms.far_luoa_audit_gc_gtt submitted
                     JOIN zsailmaker.blackout_days holi
                       ON holi.day >= submitted.submitted_at
                      AND holi.day < (v_etl_date)
                    GROUP BY submitted.crn,
                             submitted.term_code,
                             submitted.user_id,
                             submitted.submission_id) holi_days
           ON holi_days.crn = submitted.crn
          AND holi_days.term_code = submitted.term_code
          AND holi_days.user_id = submitted.user_id
          AND holi_days.submission_id = submitted.submission_id
         LEFT JOIN utl_d_lms.last_activity_pivot lap -- check for FN appeals
           ON lap.instance = courses.instance
          AND lap.course_section_id = courses.course_section_id
          AND lap.user_id = submitted.user_id
          AND lap.fn_grade_appeal IS NOT NULL
          AND lap.fn_grade_appeal > lap.last_submission -- FN appeal must be greater than last submission to be used
         LEFT JOIN utl_d_lms.far_luoa_audit fla
           ON fla.unique_id = CASE
              WHEN lap.fn_grade_appeal IS NOT NULL -- if there is a recent FN appeal and they have submissions, they will remain yellow until completed
               THEN
               courses.course_section_id || '_' || v_cat_code || '1' || '_' || submitted.luid || '_' || to_char(submitted.submission_id)
              WHEN coalesce(submitted.submission_type, 'X') = 'online_quiz'
                   AND v_etl_date > submitted.submitted_date + (coalesce(weekends.counted, 0) + coalesce(holi_days.counted, 0))
                   AND v_etl_date <= submitted.submitted_date + (coalesce(weekends.counted, 0) + coalesce(holi_days.counted, 0)) + 3 THEN
               courses.course_section_id || '_' || v_cat_code || '1' || '_' || submitted.luid || '_' || to_char(submitted.submission_id)
              WHEN coalesce(submitted.submission_type, 'X') = 'online_quiz'
                   AND v_etl_date > submitted.submitted_date + (coalesce(weekends.counted, 0) + coalesce(holi_days.counted, 0)) + 3 THEN
               courses.course_section_id || '_' || v_cat_code || '2' || '_' || submitted.luid || '_' || to_char(submitted.submission_id)
              WHEN coalesce(submitted.submission_type, 'X') <> 'online_quiz'
                   AND v_etl_date > submitted.submitted_date + (coalesce(weekends.counted, 0) + coalesce(holi_days.counted, 0))
                   AND v_etl_date <= submitted.submitted_date + (coalesce(weekends.counted, 0) + coalesce(holi_days.counted, 0)) + 4 THEN
               courses.course_section_id || '_' || v_cat_code || '1' || '_' || submitted.luid || '_' || to_char(submitted.submission_id)
              WHEN coalesce(submitted.submission_type, 'X') <> 'online_quiz'
                   AND v_etl_date > submitted.submitted_date + (coalesce(weekends.counted, 0) + coalesce(holi_days.counted, 0)) + 4 THEN
               courses.course_section_id || '_' || v_cat_code || '2' || '_' || submitted.luid || '_' || to_char(submitted.submission_id)
              ELSE
               courses.course_section_id || '_' || v_cat_code || '0' || '_' || submitted.luid || '_' || to_char(submitted.submission_id)
              END
          AND fla.audit_date < v_etl_date -- must be less than or the flag count will not work
       -- filter  down to what we need including the weekends and holidays counted
        WHERE v_etl_date > submitted.submitted_date + (coalesce(weekends.counted, 0) + coalesce(holi_days.counted, 0))) new_records
ON (destination_table.unique_id = new_records.unique_id)
WHEN MATCHED THEN
UPDATE
   SET destination_table.flag_count               = new_records.flag_count,
       destination_table.compliance_status_reason = new_records.compliance_status_reason,
       destination_table.url                      = new_records.url,
       destination_table.last_modified            = new_records.last_modified,
       destination_table.status                   = new_records.status,
       destination_table.instance                 = new_records.instance
WHEN NOT MATCHED THEN
INSERT
(term_code,
 crn,
 coll_code,
 coll_desc,
 course_code,
 course_sis_id,
 section_sis_id,
 course_id,
 course_section_id,
 url,
 camp_code,
 ptrm_code,
 insm_code,
 faculty_pidm,
 faculty_name,
 faculty_email,
 compliance_category_code,
 compliance_status_code,
 compliance_status_reason,
 status,
 instance,
 deleted_ind,
 deleted_reason,
 unique_id,
 flag_count,
 audit_date,
 last_modified)
VALUES
(new_records.term_code,
 new_records.crn,
 new_records.coll_code,
 new_records.coll_desc,
 new_records.course_code,
 new_records.course_sis_id,
 new_records.section_sis_id,
 new_records.course_id,
 new_records.course_section_id,
 new_records.url,
 new_records.camp_code,
 new_records.ptrm_code,
 new_records.insm_code,
 new_records.faculty_pidm,
 new_records.faculty_name,
 new_records.faculty_email,
 new_records.compliance_category_code,
 new_records.compliance_status_code,
 new_records.compliance_status_reason,
 new_records.status,
 new_records.instance,
 new_records.deleted_ind,
 new_records.deleted_reason,
 new_records.unique_id,
 new_records.flag_count,
 new_records.audit_date,
 new_records.last_modified);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'MERGE - ' || rec.term_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- removing for performance reasons
/*dbms_output.put_line('Expiring records when FLAG OCCURRED **AFTER** THE GRADE: ' || rec.term_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ';');
UPDATE utl_d_lms.far_luoa_audit fla
   SET (fla.status, fla.flag_count, fla.deleted_ind, fla.deleted_reason) =
       (SELECT 'EXPIRED',
               0,
               'Y',
               'SYSTEM: Latency on the data feed. FAR audit_date >= graded_date. Record deleted / expired.'
          FROM dual)
 WHERE EXISTS (SELECT sa.submission_id,
               flax.audit_date,
               sa.graded_date
          FROM utl_d_lms.far_luoa_audit flax
          JOIN utl_d_lms.student_assignments sa
            ON sa.instance = flax.instance
           AND sa.term_code = flax.term_code
           AND sa.submission_id = substr(flax.unique_id, instr(flax.unique_id, '_', -1) + 1) -- parse out the submission ID that is in the ref no from the compliance_status_reason
         WHERE flax.compliance_category_code = v_cat_code
           AND flax.compliance_status_code IN ('1', '2')
           AND flax.term_code = rec.term_code
           AND sa.graded_date IS NOT NULL
           AND flax.audit_date >= sa.graded_date
           AND flax.instance = v_instance
           AND flax.unique_id = fla.unique_id);
v_count := v_count + SQL%ROWCOUNT;
COMMIT;
dbms_output.put_line('Expiring records that are no longer active in: ' || rec.term_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ';');*/
UPDATE utl_d_lms.far_luoa_audit fla
   SET fla.status = 'EXPIRED' -- if the last_modified did NOT get updated on the last run, it is no longer active; EXPIRE records on last day of ptrm
 WHERE fla.compliance_category_code = v_cat_code
   AND fla.term_code = rec.term_code
   AND fla.status = 'ACTIVE'
   AND ((fla.last_modified < v_etl_date) OR (v_etl_date >= rec.end_date + 7));
v_count := v_count + SQL%ROWCOUNT;
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'UPDATE - ' || rec.term_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
v_total_count := v_total_count + v_count;
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
---      03-04-2022  WGRIFFITH2  --Initial release
---      07-12-2022  WGRIFFITH2  --TKT2527188 - LUOA Grading Logic Change
---      12-06-2022  WGRIFFITH2  --Moved code from CANVAS_ETL to UTL_D_LMS
---      12-08-2022  WGRIFFITH2  --Quiz grading moved from +2 to +3 days so it would match the Teacher Activity Report per Kelley Niblett
---      12-09-2022  WGRIFFITH2  --TKT2593495 - Add FN appeals to grading compliance
---      11-19-2022  WGRIFFITH2  --switching to zsailmaker.blackout_days for determining holidays
------------------------------------------------------------------------------------------------*/
END etl_lms_far_luoa_audit_gc;

PROCEDURE etl_lms_far_luoa_audit_fg(jobnumber   NUMBER,
                                    processid   VARCHAR2,
                                    processname VARCHAR2) IS
/*
* Purpose:
*    - Tracks when final grade compliance
* Conditions:
*    - Showing 100% assignment completion (including EOC) without a final grade submitted or end date has surpassed
*    - yellow: on day 1 thru 7, NOT all grades turned = in compliance (warning)
*    - red: after day 7
*/
--DECLARE
--- PARAMS
v_etl_date    DATE := SYSDATE;
v_instance    VARCHAR2(50) := upper('ACCAN'); -- inst from the jams job; used for determining instance
v_partition    NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_msg         VARCHAR2(2000);
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_lms_far_luoa_audit_fg';
v_cat_code    VARCHAR2(2) := 'FG';
-- CURSOR
CURSOR c_terms IS
SELECT ll.term_code,
       MAX(ll.end_date) end_date
  FROM zbtm.terms_by_group_v t
  JOIN utl_d_lms.lms_link ll
    ON ll.term_code = t.term_code
 WHERE 1 = 1
   AND SYSDATE >= ll.start_date - 14
   AND SYSDATE <= ll.end_date + 14
   AND ll.coll_code = 'AC'
 GROUP BY ll.term_code
 ORDER BY 1 DESC;
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
v_msg     := 'START - ' || rec.term_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
MERGE INTO utl_d_lms.far_luoa_audit destination_table
USING (SELECT courses.term_code,
              courses.crn,
              courses.coll_code,
              courses.coll_desc,
              courses.course_code,
              courses.course_sis_id,
              courses.section_sis_id,
              courses.course_id,
              courses.course_section_id,
              'https://luoa.instructure.com/courses/' || courses.course_id || '/external_tools/425889' AS url,
              courses.camp_code,
              courses.ptrm_code,
              courses.insm_code,
              courses.faculty_pidm,
              courses.faculty_name,
              courses.faculty_email,
              v_cat_code AS compliance_category_code,
              status_code AS compliance_status_code,
              final_grd.status AS compliance_status_reason,
              v_etl_date audit_date,
              'N' deleted_ind,
              NULL deleted_reason,
              courses.course_section_id || '_' || v_cat_code || status_code || '_' || lpad(to_char(final_grd.luid), 9, 'L00000000') AS unique_id, -- 20204054321_FG2_L20070201
              CASE
              WHEN fla.deleted_ind = 'Y' THEN
               0
              WHEN status_code = '0' THEN
               0
              WHEN fla.course_section_id IS NOT NULL THEN
               ceil(v_etl_date - coalesce(fla.audit_date, v_etl_date - 1 / 24)) -- coalesce is for the first record entry
              ELSE
               1
              END AS flag_count,
              v_etl_date AS last_modified,
              'ACTIVE' AS status,
              courses.instance
         FROM utl_d_lms.far_luoa_courses courses
         JOIN (SELECT crse.term_code term_code,
                     crse.crn,
                     ll.course_section_id,
                     su.luid,
                     su.pidm,
                     su.first_name || ' ' || su.last_name AS student_name,
                     CASE
                     -- yellow - incompletes show indefinately until changed
                     WHEN coalesce(crse.final_grade, 'M') = 'I' -- incompletes show yellow
                      THEN
                      '1'
                     -- yellow - course completed, before end date
                     WHEN coalesce(crse.final_grade, 'M') = 'M'
                          AND sp.assignments_progress = 1
                          AND coalesce(completed_eoc, 0) > 0
                          AND sp.end_date > v_etl_date
                          AND v_etl_date <= trunc(sp.last_submission + 1) - 1 / (24 * 60 * 60) + 7 THEN
                      '1'
                     -- red - course completed, before end date
                     WHEN coalesce(crse.final_grade, 'M') = 'M'
                          AND sp.assignments_progress = 1
                          AND coalesce(completed_eoc, 0) > 0
                          AND sp.end_date > v_etl_date
                          AND v_etl_date > trunc(sp.last_submission + 1) - 1 / (24 * 60 * 60) + 7 THEN
                      '2'
                     -- yellow - course completed, after end date
                     WHEN coalesce(crse.final_grade, 'M') = 'M'
                          AND v_etl_date > sp.end_date + 0 -- is beyond end date
                          AND v_etl_date <= sp.end_date + 7 THEN -- is beyond end date
                      '1'
                     -- red - course completed, after end date
                     WHEN coalesce(crse.final_grade, 'M') = 'M'
                          AND v_etl_date > sp.end_date + 7 THEN -- is beyond end date
                      '2'
                     WHEN coalesce(crse.final_grade, 'M') NOT IN ('I', 'M') THEN
                      '0'
                     END status_code,
                     CASE
                     -- yellow - incompletes show indefinately until changed
                     WHEN coalesce(crse.final_grade, 'M') = 'I' -- incompletes show yellow
                      THEN
                      'Incomplete grade for ' || su.first_name || ' ' || su.last_name || '-' || lpad(to_char(su.luid), 9, 'L00000000')
                     -- yellow - course completed, before end date
                     WHEN coalesce(crse.final_grade, 'M') = 'M'
                          AND sp.assignments_progress = 1
                          AND coalesce(completed_eoc, 0) > 0
                          AND sp.end_date > v_etl_date
                          AND v_etl_date <= trunc(sp.last_submission + 1) - 1 / (24 * 60 * 60) + 7 THEN
                      'Final grade needed for ' || su.first_name || ' ' || su.last_name || '-' || lpad(to_char(su.luid), 9, 'L00000000') || '. Grade due: ' ||
                      to_char(trunc(sp.last_submission + 1) - 1 / (24 * 60 * 60) + 7, 'MM/DD/YYYY hh24:mi:ss') || '. Earned Grade: ' || to_char(round(sp.grade_earned, 1)) || '%'
                     -- red - course completed, before end date
                     WHEN coalesce(crse.final_grade, 'M') = 'M'
                          AND sp.assignments_progress = 1
                          AND coalesce(completed_eoc, 0) > 0
                          AND sp.end_date > v_etl_date
                          AND v_etl_date > trunc(sp.last_submission + 1) - 1 / (24 * 60 * 60) + 7 THEN
                      'Final grade needed for ' || su.first_name || ' ' || su.last_name || '-' || lpad(to_char(su.luid), 9, 'L00000000') || '. Grade due: ' ||
                      to_char(trunc(sp.last_submission + 1) - 1 / (24 * 60 * 60) + 7, 'MM/DD/YYYY hh24:mi:ss') || '. Earned Grade: ' || to_char(round(sp.grade_earned, 1)) || '%'
                     -- yellow - course completed, after end date (submit FN)
                     WHEN coalesce(crse.final_grade, 'M') = 'M'
                          AND coalesce(missing_tier3, 0) > 0 -- missing a T3 assignment
                          AND v_etl_date > sp.end_date + 0 -- is beyond end date
                          AND v_etl_date <= sp.end_date + 7 THEN -- is beyond end date
                      'Student missing Tier 3 assignments (' || coalesce(missing_tier3, 0) || '). FN grade needed for ' || su.first_name || ' ' || su.last_name || '-' || lpad(to_char(su.luid), 9, 'L00000000') || '. Grade due: ' ||
                      to_char(sp.end_date, 'MM/DD/YYYY hh24:mi:ss') || '. Earned Grade: ' || to_char(round(sp.grade_earned, 1)) || '%'
                     -- yellow - course completed, after end date (submit A-F)
                     WHEN coalesce(crse.final_grade, 'M') = 'M'
                          AND v_etl_date > sp.end_date + 0 -- is beyond end date
                          AND v_etl_date <= sp.end_date + 7 THEN -- is beyond end date
                      'Final grade needed for ' || su.first_name || ' ' || su.last_name || '-' || lpad(to_char(su.luid), 9, 'L00000000') || '. Grade due: ' || to_char(sp.end_date, 'MM/DD/YYYY hh24:mi:ss') || '. Earned Grade: ' ||
                      to_char(round(sp.grade_earned, 1)) || '%'
                     -- red - course completed, after end date  (submit FN)
                     WHEN coalesce(crse.final_grade, 'M') = 'M'
                          AND coalesce(missing_tier3, 0) > 0 -- missing a T3 assignment
                          AND v_etl_date > sp.end_date + 7 THEN -- is beyond end date
                      'Student missing Tier 3 assignments (' || coalesce(missing_tier3, 0) || '). FN grade needed for ' || su.first_name || ' ' || su.last_name || '-' || lpad(to_char(su.luid), 9, 'L00000000') || '. Grade due: ' ||
                      to_char(sp.end_date, 'MM/DD/YYYY hh24:mi:ss') || '. Earned Grade: ' || to_char(round(sp.grade_earned, 1)) || '%'
                     -- red - course completed, after end date  (submit A-F)
                     WHEN coalesce(crse.final_grade, 'M') = 'M'
                          AND v_etl_date > sp.end_date + 7 THEN -- is beyond end date
                      'Final grade needed for ' || su.first_name || ' ' || su.last_name || '-' || lpad(to_char(su.luid), 9, 'L00000000') || '. Grade due: ' || to_char(sp.end_date, 'MM/DD/YYYY hh24:mi:ss') || '. Earned Grade: ' ||
                      to_char(round(sp.grade_earned, 1)) || '%'
                     WHEN coalesce(crse.final_grade, 'M') NOT IN ('I', 'M') THEN
                      '0'
                     END status,
                     ll.instance
                FROM utl_d_aim.szrcrse crse
                JOIN utl_d_lms.lms_link ll
                  ON ll.instance = v_instance
                 AND ll.term_code = crse.term_code
                 AND ll.crn = crse.crn
                 AND coalesce(crse.final_grade, 'M') IN ('M', 'I')
                JOIN utl_d_lms.student_users su
                  ON su.instance = ll.instance
                 AND su.pidm = crse.pidm
                 AND su.affiliate_ind = 'N'
                JOIN utl_d_lms.student_progress sp
                  ON sp.instance = ll.instance
                 AND ll.course_section_id = sp.course_section_id
                 AND su.user_id = sp.user_id
               WHERE 1 = 1
                 AND ((sp.assignments_progress = 1 AND coalesce(completed_eoc, 0) > 0 AND sp.workflow_state = 'active' AND sp.start_date < v_etl_date - 30) OR --
                     (sp.end_date < v_etl_date AND sp.workflow_state = 'active'))) final_grd
           ON final_grd.course_section_id = courses.course_section_id
          AND final_grd.instance = courses.instance
         LEFT JOIN utl_d_lms.far_luoa_audit fla
           ON fla.unique_id = courses.course_section_id || '_' || v_cat_code || status_code || '_' || lpad(to_char(final_grd.luid), 9, 'L00000000')
          AND fla.audit_date < v_etl_date -- must be less than or the flag count will not work
       ) new_records
ON (destination_table.unique_id = new_records.unique_id)
WHEN MATCHED THEN
UPDATE
   SET destination_table.flag_count               = new_records.flag_count,
       destination_table.compliance_status_reason = new_records.compliance_status_reason,
       destination_table.url                      = new_records.url,
       destination_table.last_modified            = new_records.last_modified,
       destination_table.status                   = new_records.status,
       destination_table.instance                 = new_records.instance
WHEN NOT MATCHED THEN
INSERT
(term_code,
 crn,
 coll_code,
 coll_desc,
 course_code,
 course_sis_id,
 section_sis_id,
 course_id,
 course_section_id,
 url,
 camp_code,
 ptrm_code,
 insm_code,
 faculty_pidm,
 faculty_name,
 faculty_email,
 compliance_category_code,
 compliance_status_code,
 compliance_status_reason,
 status,
 instance,
 deleted_ind,
 deleted_reason,
 unique_id,
 flag_count,
 audit_date,
 last_modified)
VALUES
(new_records.term_code,
 new_records.crn,
 new_records.coll_code,
 new_records.coll_desc,
 new_records.course_code,
 new_records.course_sis_id,
 new_records.section_sis_id,
 new_records.course_id,
 new_records.course_section_id,
 new_records.url,
 new_records.camp_code,
 new_records.ptrm_code,
 new_records.insm_code,
 new_records.faculty_pidm,
 new_records.faculty_name,
 new_records.faculty_email,
 new_records.compliance_category_code,
 new_records.compliance_status_code,
 new_records.compliance_status_reason,
 new_records.status,
 new_records.instance,
 new_records.deleted_ind,
 new_records.deleted_reason,
 new_records.unique_id,
 new_records.flag_count,
 new_records.audit_date,
 new_records.last_modified);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'MERGE - ' || rec.term_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
--
dbms_output.put_line('Expiring records that are no longer active in: ' || rec.term_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ';');
UPDATE utl_d_lms.far_luoa_audit fla
   SET fla.status = 'EXPIRED' -- if the last_modified did NOT get updated on the last run, it is no longer active; EXPIRE records on last day of ptrm
 WHERE fla.compliance_category_code = v_cat_code
   AND fla.term_code = rec.term_code
   AND fla.status = 'ACTIVE'
   AND ((fla.last_modified < v_etl_date) OR (v_etl_date >= rec.end_date + 7));
v_count := v_count + SQL%ROWCOUNT;
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'UPDATE - ' || rec.term_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
v_total_count := v_total_count + v_count;
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
---      03-04-2022  WGRIFFITH2  --Initial release
---      08-11-2022  WGRIFFITH2  --Extending timeframe from 5 days to 7 for final grades. Adjustments for FN appeals, extensions, exemptions, etc. - TKT2537366
---      11-02-2022  WGRIFFITH2  --Now using the student_progress table instead of the luoa activity table (deprecated)
---      01-19-2023  WGRIFFITH2  --Adding directions for instructors to submit FN if they are beyond end date and are missing a tier 3 assignment
---      04-12-2023  WGRIFFITH2  --Students must complete the EOC assignment before it appears on the FAR
---      06-19-2023 WGRIFFITH2   --change related to issues with recent warehouse updates. had to add COMPLETED_EOC and MISSING_TIER3 fields to student_progress to help
---      02-14-2023 WGRIFFITH2   --fixing issues with student progress not updating the final grade TKT2858990
------------------------------------------------------------------------------------------------*/
END etl_lms_far_luoa_audit_fg;

PROCEDURE etl_lms_far_luoa_audit_fn(jobnumber   NUMBER,
                                    processid   VARCHAR2,
                                    processname VARCHAR2) IS
/*
* Purpose:
*    - Tracks when an FN should be given to a student for inactivity in a course
* Conditions:
*    - student must be registered for the course
*    - yellow: Students reaches 30 days of inactivity in the course
*    - red: Student is not marked with an FN by 11:59PM on day 34 of student inactivity
*/
--DECLARE
--- PARAMS
v_etl_date    DATE := SYSDATE;
v_instance    VARCHAR2(50) := upper('ACCAN'); -- inst from the jams job; used for determining instance
v_partition    NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_msg         VARCHAR2(2000);
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_lms_far_luoa_audit_fn';
v_cat_code    VARCHAR2(2) := 'FN';
-- CURSOR
CURSOR c_terms IS
SELECT ll.term_code,
       MAX(ll.end_date) end_date
  FROM zbtm.terms_by_group_v t
  JOIN utl_d_lms.lms_link ll
    ON ll.term_code = t.term_code
 WHERE 1 = 1
   AND SYSDATE >= ll.start_date - 14
   AND SYSDATE <= ll.end_date + 14
   AND ll.coll_code = 'AC'
 GROUP BY ll.term_code
 ORDER BY 1 DESC;
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
v_msg     := 'START - ' || rec.term_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
MERGE INTO utl_d_lms.far_luoa_audit destination_table
USING (SELECT courses.term_code,
              courses.crn,
              courses.coll_code,
              courses.coll_desc,
              courses.course_code,
              courses.course_sis_id,
              courses.section_sis_id,
              courses.course_id,
              courses.course_section_id,
              'https://luoa.instructure.com/courses/' || courses.course_id || '/external_tools/406482' AS url,
              courses.camp_code,
              courses.ptrm_code,
              courses.insm_code,
              courses.faculty_pidm,
              courses.faculty_name,
              courses.faculty_email,
              v_cat_code AS compliance_category_code,
              CASE
              WHEN sp.inactive_days BETWEEN 28 AND 34 THEN
               '1'
              WHEN sp.inactive_days > 34 THEN
               '2'
              END compliance_status_code,
              CASE
              WHEN sp.inactive_days BETWEEN 28 AND 29.9 THEN
               'FN risk for ' || su.first_name || ' ' || su.last_name || '-' || lpad(to_char(su.luid), 9, 'L00000000') || ' who has been inactive for ' || sp.inactive_days || ' days and has been contacted automatically through email.'
              WHEN sp.inactive_days BETWEEN 30 AND 34 THEN
               'Submit FN grade before day 34 of inactivity for ' || su.first_name || ' ' || su.last_name || '-' || lpad(to_char(su.luid), 9, 'L00000000') || ' who has been inactive for ' || sp.inactive_days || ' days.'
              WHEN sp.inactive_days > 34 THEN
               'FN required immediately for ' || su.first_name || ' ' || su.last_name || '-' || lpad(to_char(su.luid), 9, 'L00000000') || ' who has been inactive for ' || sp.inactive_days || ' days.'
              END compliance_status_reason,
              v_etl_date audit_date,
              'N' deleted_ind,
              NULL deleted_reason,
              CASE
              WHEN sp.inactive_days BETWEEN 28 AND 34 THEN
               courses.course_section_id || '_' || v_cat_code || '1' || '_' || lpad(to_char(su.luid), 9, 'L00000000') || '_' || to_char(sp.last_activity, 'YYYYMMDD') -- 20204054330_FN1_L20070201_YYYYMMDD
              WHEN sp.inactive_days > 34 THEN
               courses.course_section_id || '_' || v_cat_code || '2' || '_' || lpad(to_char(su.luid), 9, 'L00000000') || '_' || to_char(sp.last_activity, 'YYYYMMDD') -- 20204054330_FN1_L20070201_YYYYMMDD
              END AS unique_id,
              CASE
              WHEN fla.deleted_ind = 'Y' THEN
               0
              WHEN fla.course_section_id IS NOT NULL THEN
               ceil(v_etl_date - coalesce(fla.audit_date, v_etl_date - 1 / 24)) -- coalesce is for the first record entry
              ELSE
               1
              END AS flag_count,
              v_etl_date AS last_modified,
              'ACTIVE' AS status,
              courses.instance
         FROM utl_d_lms.far_luoa_courses courses
         JOIN utl_d_lms.student_progress sp
           ON sp.course_section_id = courses.course_section_id
          AND sp.instance = courses.instance
          AND sp.inactive_days >= 28 --
          AND sp.workflow_state = 'active' -- must be active in the course
          AND sp.completed_assignments > 1 -- anything between 0 and 1 goes to Kelley and April; those get DD/WD
          AND courses.term_code = rec.term_code
         JOIN utl_d_lms.student_users su
           ON su.instance = courses.instance
          AND su.user_id = sp.user_id
          AND su.affiliate_ind = 'N'
         JOIN utl_d_aim.szrcrse crse
           ON crse.term_code = courses.term_code
          AND crse.crn = courses.crn
          AND crse.pidm = su.pidm
          AND crse.final_grade IS NULL -- does not have grade posted
         JOIN zsaturn.szrlevl l
           ON l.szrlevl_levl_code = crse.levl_code
          AND l.szrlevl_has_awardable_cred = 'Y' -- remove EM
         LEFT JOIN utl_d_lms.far_luoa_audit fla
           ON fla.unique_id = CASE
              WHEN sp.inactive_days BETWEEN 28 AND 34 THEN
               courses.course_section_id || '_' || v_cat_code || '1' || '_' || lpad(to_char(su.luid), 9, 'L00000000') || '_' || to_char(sp.last_activity, 'YYYYMMDD') -- 20204054330_FN1_L20070201_YYYYMMDD
              WHEN sp.inactive_days > 34 THEN
               courses.course_section_id || '_' || v_cat_code || '2' || '_' || lpad(to_char(su.luid), 9, 'L00000000') || '_' || to_char(sp.last_activity, 'YYYYMMDD') -- 20204054330_FN1_L20070201_YYYYMMDD
              END
          AND fla.audit_date < v_etl_date -- must be less than or the flag count will not work
       ) new_records
ON (destination_table.unique_id = new_records.unique_id)
WHEN MATCHED THEN
UPDATE
   SET destination_table.flag_count               = new_records.flag_count,
       destination_table.compliance_status_reason = new_records.compliance_status_reason,
       destination_table.url                      = new_records.url,
       destination_table.last_modified            = new_records.last_modified,
       destination_table.status                   = new_records.status,
       destination_table.instance                 = new_records.instance
WHEN NOT MATCHED THEN
INSERT
(term_code,
 crn,
 coll_code,
 coll_desc,
 course_code,
 course_sis_id,
 section_sis_id,
 course_id,
 course_section_id,
 url,
 camp_code,
 ptrm_code,
 insm_code,
 faculty_pidm,
 faculty_name,
 faculty_email,
 compliance_category_code,
 compliance_status_code,
 compliance_status_reason,
 status,
 instance,
 deleted_ind,
 deleted_reason,
 unique_id,
 flag_count,
 audit_date,
 last_modified)
VALUES
(new_records.term_code,
 new_records.crn,
 new_records.coll_code,
 new_records.coll_desc,
 new_records.course_code,
 new_records.course_sis_id,
 new_records.section_sis_id,
 new_records.course_id,
 new_records.course_section_id,
 new_records.url,
 new_records.camp_code,
 new_records.ptrm_code,
 new_records.insm_code,
 new_records.faculty_pidm,
 new_records.faculty_name,
 new_records.faculty_email,
 new_records.compliance_category_code,
 new_records.compliance_status_code,
 new_records.compliance_status_reason,
 new_records.status,
 new_records.instance,
 new_records.deleted_ind,
 new_records.deleted_reason,
 new_records.unique_id,
 new_records.flag_count,
 new_records.audit_date,
 new_records.last_modified);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'MERGE - ' || rec.term_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
--
dbms_output.put_line('Expiring records that are no longer active in: ' || rec.term_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ';');
UPDATE utl_d_lms.far_luoa_audit fla
   SET fla.status = 'EXPIRED' -- if the last_modified did NOT get updated on the last run, it is no longer active; EXPIRE records on last day of ptrm
 WHERE fla.compliance_category_code = v_cat_code
   AND fla.term_code = rec.term_code
   AND fla.status = 'ACTIVE'
   AND ((fla.last_modified < v_etl_date) OR (v_etl_date >= rec.end_date + 7));
v_count := v_count + SQL%ROWCOUNT;
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'UPDATE - ' || rec.term_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
v_total_count := v_total_count + v_count;
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
---      03-04-2022  WGRIFFITH2  --Initial release
---      06-30-2022  WGRIFFITH2  --Updates to align with the LUOA activity table
---      11-02-2022  WGRIFFITH2  --Now using the student_progress table instead of the luoa activity table (deprecated)
---      12-12-2022  WGRIFFITH2  --AND sp.completed_assignments > 1 -- anything between 0 and 1 goes to Kelley and April; those get DD/WD
------------------------------------------------------------------------------------------------*/
END etl_lms_far_luoa_audit_fn;

PROCEDURE etl_lms_far_luoa_courses(jobnumber   NUMBER,
                                   processid   VARCHAR2,
                                   processname VARCHAR2) IS
/*
* Purpose:
*    - Contains the active courses for the LUOA FAR
* Conditions:
*    - Excluding 1P ptrm_code courses - clubs, assessments, readiness, etc.
*/
--DECLARE
--- PARAMS
v_etl_date    DATE := SYSDATE;
v_instance    VARCHAR2(50) := upper('ACCAN'); -- inst from the jams job; used for determining instance
v_partition    NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_msg         VARCHAR2(2000);
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_lms_far_luoa_courses';
-- cursors
CURSOR c_terms IS
SELECT DISTINCT ll.term_code
  FROM zbtm.terms_by_group_v t
  JOIN utl_d_lms.lms_link ll
    ON ll.term_code = t.term_code
 WHERE 1 = 1
   AND SYSDATE >= ll.start_date - 14
   AND SYSDATE <= ll.end_date + 14
   AND ll.coll_code = 'AC'
 ORDER BY 1 DESC;
BEGIN
-- dbms_output.enable(buffer_size => NULL);
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
-- remove any courses that no longer exist in LMS LINK
DELETE FROM utl_d_lms.far_luoa_courses far_luoa_courses
 WHERE EXISTS (SELECT flc.course_section_id
          FROM utl_d_lms.far_luoa_courses flc
          LEFT JOIN utl_d_lms.lms_link ll
            ON ll.course_section_id = flc.course_section_id
           AND ll.instance = flc.instance
         WHERE ll.course_section_id IS NULL
           AND flc.instance = v_instance
           AND flc.course_section_id = far_luoa_courses.course_section_id
           AND flc.instance = far_luoa_courses.instance);
v_count := SQL%ROWCOUNT;
-- remove any courses that no longer have active enrollments
DELETE FROM utl_d_lms.far_luoa_courses far_luoa_courses
 WHERE NOT EXISTS (SELECT DISTINCT e.course_section_id
          FROM zcanvas_data.enrollments e
         WHERE e.instance = far_luoa_courses.instance
           AND e.course_section_id = far_luoa_courses.course_section_id
           AND e.instance = v_instance
           AND e.type = 'StudentEnrollment'
           AND e.workflow_state = 'active');
v_count := v_count + SQL%ROWCOUNT;
COMMIT;
IF v_count > 0 THEN
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'DELETE - ' || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
ELSE
v_count := 0;
END IF;
FOR rec IN c_terms
LOOP
v_count   := 0; -- reset count
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || rec.term_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- MUST BE A MERGE TO ENSURE CONSTANT UP-TIME IN DASHBOARD
MERGE INTO utl_d_lms.far_luoa_courses destination_table
USING (SELECT ll.term_code,
              ll.crn,
              ll.ptrm_code,
              ll.coll_code,
              stvcoll_desc AS coll_desc,
              ll.subj_code || ll.crse_numb AS course,
              ll.course_code,
              ll.course_sis_id,
              ll.section_sis_id,
              ll.course_id,
              ll.course_section_id,
              cs.name AS course_section_name,
              'https://luoa.instructure.com/courses/' || ll.course_id AS url,
              ll.camp_code,
              ll.insm_code,
              spriden_pidm AS faculty_pidm,
              spriden_id AS faculty_luid,
              spriden_last_name || ', ' || spriden_first_name AS faculty_name,
              prof_emal.email_address AS faculty_email,
              ll.instance,
              act_reg.cnt AS enrollment,
              ll.start_date,
              ll.end_date,
              v_etl_date AS activity_date,
              gtvinsm.gtvinsm_desc AS exclusions
         FROM utl_d_lms.lms_link ll
         JOIN zsaturn.szrlevl l
           ON l.szrlevl_levl_code = ll.levl_code
          AND l.szrlevl_has_awardable_cred = 'Y' -- remove EM
         JOIN saturn.ssbsect
           ON ssbsect_crn = ll.crn
          AND ssbsect_term_code = ll.term_code
          AND ll.term_code = rec.term_code
          AND ll.ptrm_code NOT IN ('1P') --Excluding 1P ptrm_code courses - clubs, assessments, readiness, etc.
          AND ll.course_section_id NOT IN (2566873, 2567080) -- CBSA broken for these two
       -- make sure we have active enrollments in the course section
         JOIN (SELECT DISTINCT e.course_section_id,
                              e.instance
                FROM zcanvas_data.enrollments e
               WHERE e.type = 'StudentEnrollment'
                 AND e.workflow_state = 'active'
                 AND e.instance = v_instance) e
           ON e.instance = ll.instance
          AND e.course_section_id = ll.course_section_id
       -- confirm Banner connection
         JOIN (SELECT sfrstcr.sfrstcr_crn crn,
                     sfrstcr.sfrstcr_term_code term_code,
                     COUNT(DISTINCT sfrstcr_pidm) cnt
                FROM saturn.sfrstcr sfrstcr
                JOIN saturn.stvrsts stvrsts
                  ON stvrsts.stvrsts_code = sfrstcr.sfrstcr_rsts_code
                 AND sfrstcr_rsts_code <> 'AU'
                 AND stvrsts.stvrsts_incl_sect_enrl = 'Y'
                 AND stvrsts.stvrsts_withdraw_ind = 'N'
                 AND stvrsts.stvrsts_incl_assess = 'Y'
                 AND sfrstcr_term_code = rec.term_code
               GROUP BY sfrstcr.sfrstcr_crn,
                        sfrstcr.sfrstcr_term_code) act_reg
           ON act_reg.crn = ssbsect.ssbsect_crn
          AND act_reg.term_code = ssbsect.ssbsect_term_code
         LEFT JOIN gtvinsm
           ON gtvinsm_code = ssbsect.ssbsect_insm_code
         JOIN saturn.sirasgn sir
           ON sir.sirasgn_crn = ll.crn
          AND sir.sirasgn_term_code = ll.term_code
          AND sir.sirasgn_primary_ind = 'Y'
         JOIN saturn.spriden
           ON spriden_pidm = sir.sirasgn_pidm
          AND spriden_change_ind IS NULL
          AND spriden_pidm NOT IN (3248979) --exclude To Be Announced
          AND spriden_pidm NOT IN (12940274, 314984, 11825787, 6411998, 327684, 67331, 230162, 4115274, 113336, 12991653, 7747323) -- remove per request from Kelley
         LEFT JOIN zexec.zsavemal prof_emal
           ON prof_emal.pidm = sir.sirasgn_pidm
          AND prof_emal.emal_code = 'LU'
          AND prof_emal.emal_code_rank = 1
         LEFT JOIN saturn.stvcoll
           ON stvcoll_code = ll.coll_code
       -- used to get the course_name
         LEFT JOIN zcanvas_data.course_sections cs
           ON cs.id = ll.course_section_id
          AND cs.workflow_state <> 'deleted'
          AND cs.instance = ll.instance) new_records
ON (destination_table.instance = new_records.instance AND destination_table.course_section_id = new_records.course_section_id)
WHEN MATCHED THEN
UPDATE
   SET destination_table.term_code           = new_records.term_code,
       destination_table.crn                 = new_records.crn,
       destination_table.ptrm_code           = new_records.ptrm_code,
       destination_table.coll_code           = new_records.coll_code,
       destination_table.coll_desc           = new_records.coll_desc,
       destination_table.course              = new_records.course,
       destination_table.course_code         = new_records.course_code,
       destination_table.course_sis_id       = new_records.course_sis_id,
       destination_table.section_sis_id      = new_records.section_sis_id,
       destination_table.course_id           = new_records.course_id,
       destination_table.course_section_name = new_records.course_section_name,
       destination_table.url                 = new_records.url,
       destination_table.camp_code           = new_records.camp_code,
       destination_table.insm_code           = new_records.insm_code,
       destination_table.faculty_pidm        = new_records.faculty_pidm,
       destination_table.faculty_luid        = new_records.faculty_luid,
       destination_table.faculty_name        = new_records.faculty_name,
       destination_table.faculty_email       = new_records.faculty_email,
       destination_table.enrollment          = new_records.enrollment,
       destination_table.start_date          = new_records.start_date,
       destination_table.end_date            = new_records.end_date,
       destination_table.activity_date       = v_etl_date,
       destination_table.exclusions          = new_records.exclusions
WHEN NOT MATCHED THEN
INSERT
(term_code,
 crn,
 ptrm_code,
 coll_code,
 coll_desc,
 course,
 course_code,
 course_sis_id,
 section_sis_id,
 course_id,
 course_section_id,
 course_section_name,
 camp_code,
 insm_code,
 faculty_pidm,
 faculty_luid,
 faculty_name,
 faculty_email,
 instance,
 exclusions,
 enrollment,
 start_date,
 end_date,
 activity_date)
VALUES
(new_records.term_code,
 new_records.crn,
 new_records.ptrm_code,
 new_records.coll_code,
 new_records.coll_desc,
 new_records.course,
 new_records.course_code,
 new_records.course_sis_id,
 new_records.section_sis_id,
 new_records.course_id,
 new_records.course_section_id,
 new_records.course_section_name,
 new_records.camp_code,
 new_records.insm_code,
 new_records.faculty_pidm,
 new_records.faculty_luid,
 new_records.faculty_name,
 new_records.faculty_email,
 new_records.instance,
 new_records.exclusions,
 new_records.enrollment,
 new_records.start_date,
 new_records.end_date,
 new_records.activity_date);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'MERGE - ' || rec.term_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
v_total_count := v_total_count + v_count;
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
---      03-04-2022  WGRIFFITH2  --Initial release
---      04-14-2022  WGRIFFITH2  --Excluding 1P ptrm_code courses - clubs, assessments, readiness, etc.
---      07-13-2022  WGRIFFITH2  --Make sure we have active enrollments in the course section
---      11-22-2022  WGRIFFITH2  --Removing courses when all active enrollment has concluded
------------------------------------------------------------------------------------------------*/
END etl_lms_far_luoa_courses;

END load_lms_etl_far_luoa;
