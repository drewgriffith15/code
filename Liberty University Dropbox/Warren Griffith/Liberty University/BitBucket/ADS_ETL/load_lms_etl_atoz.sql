create or replace package load_lms_etl_atoz IS
-- ATOZ procedures
procedure etl_lms_atoz_student_roster (jobnumber number, processid varchar2, processname varchar2, inst varchar2, nmbr number);
procedure etl_lms_atoz_teacher_roster (jobnumber number, processid varchar2, processname varchar2, inst varchar2, nmbr number);
procedure etl_lms_atoz_teacher_section (jobnumber number, processid varchar2, processname varchar2, inst varchar2, nmbr number);
procedure etl_lms_atoz_student_section (jobnumber number, processid varchar2, processname varchar2, inst varchar2, nmbr number);
end load_lms_etl_atoz;
/
create or replace package body load_lms_etl_atoz IS

procedure etl_lms_atoz_student_section (jobnumber number, processid varchar2, processname varchar2, inst varchar2, nmbr number) is
--
-- PURPOSE: Assigns LUOA students into homeroom sections for the Learning A‑Z feed, sized to approximately 36 students per section.
--
-- TABLE: utl_d_lms.atoz_student_section
--
-- UNIQUE INDEX: N/A - Full data refresh
--
-- CONDITIONS:
-- Refreshes the table by deleting all existing records before inserting the new section assignments.
-- Builds the student list from the current LUOA Learning A‑Z student roster (utl_d_lms.atoz_student_roster).
-- Includes only students whose Banner identity record is current (SPRIDENT change indicator is null).
-- Calculates the number of sections needed as CEIL(total students ÷ 36).
-- Assigns numeric section_id values starting at 1 and distributes students evenly across sections in round‑robin order to target ~36 students per section.
--
-- URL: N/A
--
--DECLARE
v_etl_date DATE := SYSDATE;
v_msg      VARCHAR2(2000);
v_instance VARCHAR2(50) := upper(inst); -- inst from the jams job; used for determining instance
v_partition NUMBER := nmbr; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_lms_atoz_student_section';
BEGIN
-- dbms_output.enable(buffer_size => NULL);
--
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
DELETE FROM utl_d_lms.atoz_student_section;
-- DO NOT COMMIT HERE!!
INSERT INTO utl_d_lms.atoz_student_section
(student_id,
 section_id)
WITH rec AS
 (SELECT ceil(COUNT(*) / 36) AS sects_needed,
         COUNT(*) AS total_students
    FROM utl_d_lms.atoz_student_roster r)
SELECT r.student_id,
       MOD(rownum - 1, rec.sects_needed) + 1 AS section_id -- Assign section ID starting at 1
  FROM utl_d_lms.atoz_student_roster r
  JOIN spriden
    ON spriden_id = r.student_id
   AND spriden_change_ind IS NULL
 CROSS JOIN rec
 ORDER BY section_id;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'DELETE/INSERT - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
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
ROLLBACK; -- ROLLBACK IF ANY ERRORS
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
/*--------------------------------------------CHANGE LOG----------------------------------------
VERSION  DATE        USERNAME    UPDATES
---      09-18-2024  WGRIFFITH2/WRMARTIN   --Initial release
------------------------------------------------------------------------------------------------*/
END etl_lms_atoz_student_section;

procedure etl_lms_atoz_teacher_section (jobnumber number, processid varchar2, processname varchar2, inst varchar2, nmbr number) is
--
-- PURPOSE: Creates homeroom section records per teacher for the Learning A‑Z feed, allocating more capacity to the first set of teachers.
--
-- TABLE: utl_d_lms.atoz_teacher_section
--
-- UNIQUE INDEX: N/A - Full data refresh
--
-- CONDITIONS:
-- Refreshes the table by deleting all existing records before inserting the new teacher sections.
-- Processes every teacher in the Learning A‑Z teacher roster (utl_d_lms.atoz_teacher_roster).
-- For the first 20 teachers encountered, creates two homeroom sections each; for all remaining teachers, creates one homeroom section.
-- Assigns section_ numbers sequentially starting at 1 across the entire load (not per teacher).
-- Sets teaching_method to 'Homeroom' for all records.
--
-- URL: N/A
--
-- DECLARE
v_etl_date DATE := SYSDATE;
v_msg      VARCHAR2(2000);
v_instance VARCHAR2(50) := upper(inst); -- inst from the jams job; used for determining instance
v_partition NUMBER := nmbr; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_lms_atoz_teacher_section';
teach_cnt     NUMBER := 0;
sect_cnt      NUMBER := 0;
BEGIN
-- dbms_output.enable(buffer_size => NULL);
--
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
DELETE FROM utl_d_lms.atoz_teacher_section;
-- DO NOT COMMIT HERE!!
FOR rec IN (SELECT r.* FROM utl_d_lms.atoz_teacher_roster r)
LOOP
teach_cnt := teach_cnt + 1;
IF teach_cnt <= 20 THEN
-- Insert 2 records for the first 20 records
sect_cnt := sect_cnt + 1;
INSERT INTO utl_d_lms.atoz_teacher_section
(teacher_id,
 section_,
 teaching_method)
VALUES
(rec.teacher_id,
 sect_cnt,
 'Homeroom');
sect_cnt      := sect_cnt + 1;
v_count       := SQL%ROWCOUNT;
v_total_count := v_total_count + v_count; -- keep running total of rows processed
INSERT INTO utl_d_lms.atoz_teacher_section
(teacher_id,
 section_,
 teaching_method)
VALUES
(rec.teacher_id,
 sect_cnt,
 'Homeroom');
v_count       := SQL%ROWCOUNT;
v_total_count := v_total_count + v_count; -- keep running total of rows processed
ELSE
-- Insert 1 record for the rest of the records
sect_cnt := sect_cnt + 1;
INSERT INTO utl_d_lms.atoz_teacher_section
(teacher_id,
 section_,
 teaching_method)
VALUES
(rec.teacher_id,
 sect_cnt,
 'Homeroom');
v_count       := SQL%ROWCOUNT;
v_total_count := v_total_count + v_count; -- keep running total of rows processed
END IF;
end loop;
dbms_output.put_line(' --------- ');
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
-- log any errors
EXCEPTION
WHEN OTHERS THEN
ROLLBACK; -- rollback if there are any errors
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
/*--------------------------------------------CHANGE LOG----------------------------------------
VERSION  DATE        USERNAME    UPDATES
---      09-18-2024  WGRIFFITH2/WRMARTIN   --Initial release
------------------------------------------------------------------------------------------------*/
END etl_lms_atoz_teacher_section;

procedure etl_lms_atoz_teacher_roster (jobnumber number, processid varchar2, processname varchar2, inst varchar2, nmbr number) is
--
-- PURPOSE: Builds the teacher roster used by LUOA Learning A‑Z from ACCAN Canvas enrollments in eligible K–5 LAN and specified courses, tagging district admins for SPL0012.
--
-- TABLE: utl_d_lms.atoz_teacher_roster
--
-- UNIQUE INDEX: N/A - Full data refresh
--
-- CONDITIONS:
-- Refreshes the table by truncating all existing records before loading the current roster.
-- Sources instructors from Canvas (zcanvas_data) where enrollments are active (workflow_state != 'deleted') and type is TeacherEnrollment; for SPL0012 also includes DesignerEnrollment.
-- Restricts courses to instance 'ACCAN' with active workflow_state; explicitly includes special courses by ID: 2301335 (SPL0013) and 2303823 (SPL0012).
-- For non‑special courses, requires sis_source_id present with a numeric term segment (characters 9–14) and excludes masters (“_mr”), staging, and EMBR courses.
-- Includes K–5 LAN courses with SIS prefixes LAN0K, LAN01, LAN02, LAN03, LAN04, LAN05 where the term code (chars 9–14) is ≥ 202438; also includes APP0K00, HIS0100, HIS0200, SCI0100, SCI0200 where the term code is ≥ 202538.
-- Resolves teacher_id, name, and email in priority order: faculty profile (utl_d_lms.faculty_users) when present; otherwise Banner identity (SPRIDENT, current record) and active LU email (GOREMAL code 'LU', status 'A').
-- Sets school_organization to 'Liberty University' for all rows.
-- Sets role_ to 'district_admin' only for SPL0012 (course ID 2303823) with DesignerEnrollment; otherwise role_ is 'Teacher'.
-- Deduplicates output rows using DISTINCT to avoid multiple entries per person.
--
-- URL: N/A
--
-- DECLARE
v_etl_date DATE := SYSDATE;
v_msg      VARCHAR2(2000);
v_instance VARCHAR2(50) := upper(inst); -- inst from the jams job; used for determining instance
v_partition NUMBER := nmbr; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_lms_atoz_teacher_roster';
BEGIN
-- dbms_output.enable(buffer_size => NULL);
--
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
utl_d_lms.truncate_table(v_table_name => 'atoz_teacher_roster');
INSERT INTO utl_d_lms.atoz_teacher_roster
(teacher_id,
 first_name,
 last_name,
 email,
 school_organization,
 role_)
SELECT DISTINCT coalesce(fac.luid, spr.spriden_id, spr2.spriden_id) teacher_id,
                coalesce(fac.first_name, spr.spriden_first_name, spr2.spriden_first_name) first_name,
                coalesce(fac.last_name, spr.spriden_last_name, spr2.spriden_last_name) last_name,
                coalesce(fac.lu_email, g.goremal_email_address, g2.goremal_email_address) email,
                'Liberty University' AS school_organization,
                'Teacher' AS role_
  FROM zcanvas_data.courses c
  JOIN zcanvas_data.course_sections cs
    ON cs.course_id = c.id
   AND cs.instance = c.instance
  JOIN zcanvas_data.enrollments e
    ON e.course_section_id = cs.id
   AND e.instance = cs.instance
   AND e.type = 'TeacherEnrollment'
   AND e.workflow_state != 'deleted'
  JOIN zcanvas_data.users u
    ON u.id = e.user_id
   AND u.instance = e.instance
  JOIN zcanvas_data.pseudonyms usr
    ON usr.user_id = u.id
   AND usr.instance = u.instance
   AND usr.workflow_state != 'deleted'
  LEFT JOIN spriden spr
    ON spr.spriden_id = usr.sis_user_id
   AND spr.spriden_change_ind IS NULL
  LEFT JOIN goremal g
    ON g.goremal_pidm = spr.spriden_pidm
   AND g.goremal_emal_code = 'LU'
   AND g.goremal_status_ind = 'A'
  LEFT JOIN gobtpac gp
    ON gp.gobtpac_pidm = spr.spriden_pidm
  LEFT JOIN spriden spr2
    ON spr2.spriden_id = usr.sis_user_id
   AND spr.spriden_change_ind IS NULL
  LEFT JOIN goremal g2
    ON g2.goremal_pidm = spr2.spriden_pidm
   AND g2.goremal_emal_code = 'LU'
   AND g2.goremal_status_ind = 'A'
  LEFT JOIN gobtpac gp2
    ON gp2.gobtpac_pidm = spr2.spriden_pidm
  LEFT JOIN utl_d_lms.faculty_users fac
    ON fac.user_id = e.user_id
   AND fac.instance = e.instance
   AND fac.workflow_state != 'deleted'
 WHERE (c.instance = 'ACCAN' AND c.id IN (2301335) AND c.workflow_state <> 'deleted') --  special course SPL0013 used for IXL and LAZ students outside normal criteria
      --  as well as teacher that manages them in LAZ
    OR (c.instance = 'ACCAN' AND c.workflow_state <> 'deleted' AND length(TRIM(translate(substr(c.sis_source_id, 9, 6), '0123456789', ' '))) IS NULL -- makes sure char 9-14 is numeric so we know we are looking
       -- at a term code in the past the format was different
       AND c.sis_source_id IS NOT NULL -- makes sure sis id is not null
       AND lower(c.sis_source_id) NOT LIKE '%_mr%' -- eliminates masters courses
       AND lower(c.sis_source_id) NOT LIKE '%staging%' -- eliminates staging courses
       AND lower(c.sis_source_id) NOT LIKE '%embr%' -- eliminates EMBR courses
       AND ((substr(c.sis_source_id, 1, 5) IN ('LAN0K', 'LAN01', 'LAN02', 'LAN03', 'LAN04', 'LAN05') -- LAN AND MAT K-5TH GRADE
       AND substr(c.sis_source_id, 9, 6) >= '202438') --24/25 YR AND FUTURE 
       OR (substr(c.sis_source_id, 1, 7) IN ('APP0K00', 'HIS0100', 'HIS0200', 'SCI0100', 'SCI0200') -- SPECIFIC COURSES
       AND substr(c.sis_source_id, 9, 6) >= '202538') --25/26 YR AND FUTURE
       ))
UNION
SELECT DISTINCT coalesce(fac.luid, spr.spriden_id, spr2.spriden_id) teacher_id,
                coalesce(fac.first_name, spr.spriden_first_name, spr2.spriden_first_name) first_name,
                coalesce(fac.last_name, spr.spriden_last_name, spr2.spriden_last_name) last_name,
                coalesce(fac.lu_email, g.goremal_email_address, g2.goremal_email_address) email,
                'Liberty University' AS school_organization,
                CASE
                WHEN c.sis_source_id = 'SPL0012'
                     AND e.type = 'DesignerEnrollment' THEN
                 'district_admin'
                ELSE
                 'Teacher'
                END AS role_
  FROM zcanvas_data.courses c
  JOIN zcanvas_data.course_sections cs
    ON cs.course_id = c.id
   AND cs.instance = c.instance
  JOIN zcanvas_data.enrollments e
    ON e.course_section_id = cs.id
   AND e.instance = cs.instance
   AND e.type IN ('TeacherEnrollment', 'DesignerEnrollment')
   AND e.workflow_state != 'deleted'
  JOIN zcanvas_data.users u
    ON u.id = e.user_id
   AND u.instance = e.instance
  JOIN zcanvas_data.pseudonyms usr
    ON usr.user_id = u.id
   AND usr.instance = u.instance
   AND usr.workflow_state != 'deleted'
  LEFT JOIN spriden spr
    ON spr.spriden_id = usr.sis_user_id
   AND spr.spriden_change_ind IS NULL
  LEFT JOIN goremal g
    ON g.goremal_pidm = spr.spriden_pidm
   AND g.goremal_emal_code = 'LU'
   AND g.goremal_status_ind = 'A'
  LEFT JOIN gobtpac gp
    ON gp.gobtpac_pidm = spr.spriden_pidm
  LEFT JOIN spriden spr2
    ON spr2.spriden_id = usr.sis_user_id
   AND spr.spriden_change_ind IS NULL
  LEFT JOIN goremal g2
    ON g2.goremal_pidm = spr2.spriden_pidm
   AND g2.goremal_emal_code = 'LU'
   AND g2.goremal_status_ind = 'A'
  LEFT JOIN gobtpac gp2
    ON gp2.gobtpac_pidm = spr2.spriden_pidm
  LEFT JOIN utl_d_lms.faculty_users fac
    ON fac.user_id = e.user_id
   AND fac.instance = e.instance
   AND fac.workflow_state != 'deleted'
 WHERE c.instance = 'ACCAN'
   AND c.id IN (2303823)
   AND c.workflow_state <> 'deleted'; -- special course SPL0012 used for faculty that do not teach a LAN course
-- but need LAZ access.  Those enrolled as teachers will get teacher and
-- designers will get district_admin
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
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
-- ROLLBACK IF ANY ERRORS OCCUR
ROLLBACK;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
/*--------------------------------------------CHANGE LOG----------------------------------------
VERSION  DATE        USERNAME    UPDATES
---      09-18-2024  WGRIFFITH2/WRMARTIN   --Initial release
---      08-26-2025  WRMARTIN   -- removed subject restriction from SSBSECT join limiting courses to LAN subject
------------------------------------------------------------------------------------------------*/
END etl_lms_atoz_teacher_roster;

procedure etl_lms_atoz_student_roster (jobnumber number, processid varchar2, processname varchar2, inst varchar2, nmbr number) is
--
-- PURPOSE: Builds the student roster used by LUOA Learning A‑Z from ACCAN Canvas enrollments in eligible K–5 LAN and specified courses.
--
-- TABLE: utl_d_lms.atoz_student_roster
--
-- UNIQUE INDEX: N/A - Full data refresh
--
-- CONDITIONS:
-- Refreshes the table by truncating all existing records before loading the current roster.
-- Primary source is ACCAN instance Canvas courses/sections mapped to Banner CRN/term via utl_d_lms.lms_link; only active course/section records are considered.
-- For non‑special courses, requires sis_source_id present with a numeric term segment (characters 9–14) and excludes masters (“_mr”), staging, and EMBR courses.
-- Includes K–5 LAN courses with SIS prefixes LAN0K, LAN01, LAN02, LAN03, LAN04, LAN05 where the term code (chars 9–14) is ≥ 202438; also includes APP0K00, HIS0100, HIS0200, SCI0100, SCI0200 where the term code is ≥ 202538.
-- Limits sections to level 'K8' based on Banner section attributes (SSBSECT).
-- Includes only enrollments flagged for roster inclusion (STVRSTS.INCL_SECT_ENRL = 'Y').
-- Includes students whose section start_date is on or before today (no future‑dated starts).
-- Includes students with no final grade or a final grade of 'AU'.
-- Uses current Banner identity records (SPRIDENT with no change indicator) and active LU email (GOREMAL code 'LU', status 'A') to populate identifiers and email.
-- Derives roster context from the original registration record (extension_number = 0) and, when present, the most recent extension record to determine inclusion/withdrawal and key dates; these derivations support the above filters.
-- Requires the student to hold an active LUOA attribute (ZFRLIST list 'LUOA_ATTRIBUTE_EXT') as of their latest effective student attributes (SGRSATT).
-- Additionally includes student enrollments from special Canvas course SPL0013 (ID 2301335) and excludes the specific LUID 'L01439799' from that inclusion set.
--
-- URL: N/A
--
--DECLARE
v_etl_date DATE := SYSDATE;
v_msg      VARCHAR2(2000);
v_instance VARCHAR2(50) := upper('L2cAN'); -- inst from the jams job; used for determining instance
v_partition NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_lms_atoz_student_roster';
BEGIN
-- dbms_output.enable(buffer_size => NULL);
--
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
utl_d_lms.truncate_table(v_table_name => 'atoz_student_roster');
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
INSERT INTO utl_d_lms.atoz_student_roster
(student_id,
 first_name,
 last_name,
 email_address)
SELECT DISTINCT student_id,
                first_name,
                last_name,
                student_email AS email_address
  FROM (WITH course_list AS (SELECT ll.crn,
                                    ll.term_code
                               FROM zcanvas_data.courses c
                               JOIN zcanvas_data.course_sections cs
                                 ON cs.course_id = c.id
                                AND cs.instance = c.instance
                                AND cs.workflow_state <> 'deleted'
                               JOIN utl_d_lms.lms_link ll
                                 ON ll.course_id = c.id
                                AND ll.course_section_id = cs.id
                                AND ll.instance = cs.instance
                                AND ll.workflow_state <> 'deleted'
                              WHERE c.instance = 'ACCAN'
                                AND c.workflow_state <> 'deleted'
                                AND length(TRIM(translate(substr(c.sis_source_id, 9, 6), '0123456789', ' '))) IS NULL -- makes sure char 9-14 is numeric so we know we are looking
                                   -- at a term code in the past the format was different
                                AND c.sis_source_id IS NOT NULL -- makes sure sis id is not null                                                                                       
                                AND lower(c.sis_source_id) NOT LIKE '%_mr%' -- eliminates masters courses
                                AND lower(c.sis_source_id) NOT LIKE '%staging%' -- eliminates staging courses
                                AND lower(c.sis_source_id) NOT LIKE '%embr%' -- eliminates EMBR courses
                                AND ((substr(c.sis_source_id, 1, 5) IN ('LAN0K', 'LAN01', 'LAN02', 'LAN03', 'LAN04', 'LAN05') -- LAN AND MAT K-5TH GRADE
                                    AND substr(c.sis_source_id, 9, 6) >= '202438') --24/25 YR AND FUTURE 
                                    OR (substr(c.sis_source_id, 1, 7) IN ('APP0K00', 'HIS0100', 'HIS0200', 'SCI0100', 'SCI0200') -- SPECIFIC COURSES
                                    AND substr(c.sis_source_id, 9, 6) >= '202538') --25/26 YR AND FUTURE
                                    )), holds AS (SELECT sprhold_pidm,
                                                         COUNT(sprhold_hldd_code) AS num_holds
                                                    FROM saturn.sprhold
                                                   WHERE 1 = 1
                                                     AND SYSDATE BETWEEN sprhold_from_date AND sprhold_to_date
                                                     AND sprhold_hldd_code = 'AF'
                                                   GROUP BY sprhold_pidm), first_record AS (SELECT sfrareg_term_code,
                                                                                                   sfrareg_crn,
                                                                                                   sfrareg_pidm,
                                                                                                   sfrareg_start_date       AS start_date,
                                                                                                   sfrareg_completion_date  AS completion_date,
                                                                                                   sfrareg_extension_number AS extension_number,
                                                                                                   sfrareg_rsts_date        AS registration_date,
                                                                                                   stvrsts_incl_sect_enrl   AS include_in_roster,
                                                                                                   stvrsts_withdraw_ind     AS withdrawn_indicator,
                                                                                                   stvrsts_extension_ind    AS extension_indicator
                                                                                              FROM saturn.sfrareg
                                                                                              JOIN zbtm.terms_by_group_v term_groups
                                                                                                ON term_groups.term_code = sfrareg_term_code
                                                                                               AND term_groups.group_code = 'ACD'
                                                                                               AND term_groups.term_code >= '202438'
                                                                                              JOIN course_list cl -- course changes need to be made in the COURSE_LIST CTE AT TOP
                                                                                                ON cl.crn = sfrareg.sfrareg_crn
                                                                                               AND cl.term_code = sfrareg.sfrareg_term_code
                                                                                              JOIN saturn.stvrsts
                                                                                                ON sfrareg_rsts_code = stvrsts_code
                                                                                               AND stvrsts_incl_assess = 'Y'
                                                                                             WHERE sfrareg_extension_number = 0), max_extension_record AS (SELECT *
                                                                                                                                                             FROM (SELECT sfrareg_term_code,
                                                                                                                                                                          sfrareg_crn,
                                                                                                                                                                          sfrareg_pidm,
                                                                                                                                                                          sfrareg_start_date AS start_date,
                                                                                                                                                                          sfrareg_completion_date AS completion_date,
                                                                                                                                                                          sfrareg_extension_number AS extension_number,
                                                                                                                                                                          sfrareg_rsts_date AS registration_date,
                                                                                                                                                                          stvrsts_incl_sect_enrl AS include_in_roster,
                                                                                                                                                                          stvrsts_withdraw_ind AS withdrawn_indicator,
                                                                                                                                                                          stvrsts_extension_ind AS extension_indicator,
                                                                                                                                                                          row_number() over(PARTITION BY sfrareg_term_code, sfrareg_crn, sfrareg_pidm ORDER BY sfrareg_extension_number DESC) AS row_num
                                                                                                                                                                     FROM saturn.sfrareg
                                                                                                                                                                     JOIN zbtm.terms_by_group_v term_groups
                                                                                                                                                                       ON term_groups.term_code = sfrareg_term_code
                                                                                                                                                                      AND term_groups.group_code = 'ACD'
                                                                                                                                                                      AND term_groups.term_code >= '202438'
                                                                                                                                                                     JOIN course_list cl -- course changes need to be made in the COURSE_LIST CTE AT TOP
                                                                                                                                                                       ON cl.crn = sfrareg.sfrareg_crn
                                                                                                                                                                      AND cl.term_code = sfrareg.sfrareg_term_code
                                                                                                                                                                     JOIN saturn.stvrsts
                                                                                                                                                                       ON sfrareg_rsts_code = stvrsts_code
                                                                                                                                                                    WHERE sfrareg_extension_number > 0) extension_records
                                                                                                                                                            WHERE extension_records.row_num = 1)
       SELECT DISTINCT luid          student_id,
                       last_name,
                       first_name,
                       grade_level   AS grade,
                       student_email
         FROM (SELECT sfrstcr_term_code AS term_code,
                      sfrstcr_crn AS course_reference_number,
                      sfrstcr_levl_code AS course_level_code,
                      sfrstcr_pidm AS pidm,
                      spriden_id AS luid,
                      gobtpac_external_user AS username,
                      spriden_first_name first_name,
                      spriden_last_name last_name,
                      goremal_email_address student_email,
                      CASE
                      WHEN gobtpac_external_user IS NOT NULL THEN
                       'Y'
                      ELSE
                       'N'
                      END AS has_claimed_account,
                      least(nvl(max_extension_record.completion_date, first_record.completion_date), nvl(sfrstcr_grde_date, nvl(max_extension_record.completion_date, first_record.completion_date))) AS last_active_date,
                      nvl(holds.num_holds, 0) AS number_of_holds,
                      CASE
                      WHEN EXISTS (SELECT NULL
                              FROM zfincheckin.zfrfcis
                             WHERE 1 = 1
                               AND zfrfcis.zfrfcis_pidm = sfrstcr_pidm
                               AND zfrfcis.zfrfcis_term = sfrstcr_term_code
                               AND (zfrfcis.zfrfcis_withdrawn != 'Y' OR zfrfcis.zfrfcis_withdrawn IS NULL)) THEN
                       'Y'
                      ELSE
                       'N'
                      END AS fci_indicator,
                      nvl(max_extension_record.include_in_roster, first_record.include_in_roster) AS include_in_roster,
                      nvl(max_extension_record.withdrawn_indicator, first_record.withdrawn_indicator) AS withdrawn_indicator,
                      sfrstcr_incomplete_ext_date AS incomplete_ext_date,
                      nvl(max_extension_record.extension_indicator, first_record.extension_indicator) AS extension_indicator,
                      nvl(max_extension_record.extension_number, first_record.extension_number) AS extension_number,
                      sfrstcr_grde_code AS final_grade,
                      nvl(max_extension_record.registration_date, first_record.registration_date) AS registration_date,
                      nvl(max_extension_record.start_date, first_record.start_date) AS start_date,
                      sfrstcr_grde_date AS grade_date,
                      nvl(max_extension_record.completion_date, first_record.completion_date) AS completion_date,
                      NULL AS grade_level
                 FROM saturn.sfrstcr
                 JOIN zbtm.terms_by_group_v term_groups
                   ON term_groups.term_code = sfrstcr.sfrstcr_term_code
                  AND term_groups.group_code = 'ACD'
                  AND term_groups.term_code >= '202438'
                 JOIN saturn.spriden
                   ON spriden.spriden_pidm = sfrstcr_pidm
                  AND spriden.spriden_change_ind IS NULL
                 JOIN goremal
                   ON goremal_pidm = sfrstcr_pidm
                  AND goremal_status_ind = 'A'
                  AND goremal.goremal_emal_code = 'LU'
                 JOIN course_list cl -- course changes need to be made in the COURSE_LIST CTE AT TOP
                   ON cl.crn = sfrstcr.sfrstcr_crn
                  AND cl.term_code = sfrstcr.sfrstcr_term_code
                 JOIN general.gobtpac
                   ON gobtpac.gobtpac_pidm = sfrstcr_pidm
                 JOIN saturn.sgrsatt sgrsatt1
                   ON sgrsatt_pidm = sfrstcr_pidm
                  AND sgrsatt_term_code_eff = (SELECT MAX(sgrsatt_term_code_eff)
                                                 FROM sgrsatt sgrsatt2
                                                WHERE sgrsatt1.sgrsatt_pidm = sgrsatt2.sgrsatt_pidm
                                                  AND sgrsatt2.sgrsatt_term_code_eff <= (SELECT MAX(abg.term_code) term_code
                                                                                           FROM zbtm.terms_by_group_v abg
                                                                                          WHERE abg.group_code = 'ACD'
                                                                                            AND trunc(abg.start_date) <= trunc(SYSDATE)))
                 JOIN zformdata.zfrlist d
                   ON d.zfrlist_key1_code = sgrsatt1.sgrsatt_atts_code
                  AND zfrlist_list_code = 'LUOA_ATTRIBUTE_EXT'
                  AND zfrlist_active_yn = 'Y'
                 LEFT JOIN holds
                   ON sfrstcr_pidm = holds.sprhold_pidm
                 LEFT JOIN first_record
                   ON first_record.sfrareg_pidm = sfrstcr_pidm
                  AND first_record.sfrareg_term_code = sfrstcr_term_code
                  AND first_record.sfrareg_crn = sfrstcr_crn
                 LEFT JOIN max_extension_record
                   ON max_extension_record.sfrareg_pidm = sfrstcr_pidm
                  AND max_extension_record.sfrareg_term_code = sfrstcr_term_code
                  AND max_extension_record.sfrareg_crn = sfrstcr_crn
                WHERE 1 = 1) results
         JOIN ssbsect
           ON ssbsect_crn = results.course_reference_number
          AND ssbsect_term_code = results.term_code
        WHERE (final_grade IS NULL OR final_grade = 'AU')
          AND course_level_code = 'K8'
          AND include_in_roster = 'Y'
          AND start_date <= trunc(SYSDATE)
       UNION
       SELECT DISTINCT su.luid       student_id,
                       su.last_name,
                       su.first_name,
                       NULL          AS grade_level,
                       su.lu_email   student_email
         FROM zcanvas_data.courses c
         JOIN zcanvas_data.course_sections cs
           ON cs.course_id = c.id
          AND cs.instance = c.instance
         JOIN zcanvas_data.enrollments e
           ON e.course_section_id = cs.id
          AND e.instance = cs.instance
          AND e.type = 'StudentEnrollment'
          AND e.workflow_state != 'deleted'
         JOIN zcanvas_data.users u
           ON u.id = e.user_id
          AND u.instance = e.instance
          AND u.workflow_state != 'deleted'
         JOIN utl_d_lms.student_users su
           ON su.user_id = u.id
          AND su.instance = u.instance
        WHERE c.id IN (2301335)
          AND su.luid != 'L01439799');
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
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
/*--------------------------------------------CHANGE LOG----------------------------------------
VERSION  DATE        USERNAME    UPDATES
---      09-18-2024  WRMARTIN   -- Initial release
---      01-17-2025  WRMARTIN   -- Preserve original registration date instead of extension date to prevent premature access loss
---      08-26-2025  WRMARTIN   -- removed subject restriction from SSBSECT join limiting courses to LAN subject
------------------------------------------------------------------------------------------------*/
END etl_lms_atoz_student_roster;

END load_lms_etl_atoz;
-- GRANT EXECUTE ON load_lms_etl_atoz TO utl_d_aim;
-- GRANT EXECUTE ON load_lms_etl_atoz TO utl_d_aa;
-- GRANT EXECUTE ON load_lms_etl_atoz TO utl_d_lms;
-- GRANT EXECUTE ON load_lms_etl_atoz TO utl_d_luo;
-- GRANT EXECUTE ON load_lms_etl_atoz TO wgriffith2;
-- GRANT EXECUTE ON load_lms_etl_atoz TO ZETL_JAMS_SVC;
