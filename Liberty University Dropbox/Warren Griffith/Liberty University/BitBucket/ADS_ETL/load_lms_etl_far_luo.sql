create or replace package load_lms_etl_far_luo IS 
procedure etl_lms_course_exclusions(jobnumber number, processid varchar2, processname varchar2);
procedure etl_lms_far_luo_courses (jobnumber number, processid varchar2, processname varchar2);
procedure etl_lms_far_luo_audit_an (jobnumber number, processid varchar2, processname varchar2);
procedure etl_lms_far_luo_audit_fg (jobnumber number, processid varchar2, processname varchar2);
procedure etl_lms_far_luo_audit_fn (jobnumber number, processid varchar2, processname varchar2);
procedure etl_lms_far_luo_audit_gc (jobnumber number, processid varchar2, processname varchar2);
procedure etl_lms_far_luo_audit_la (jobnumber number, processid varchar2, processname varchar2);
procedure etl_lms_far_luo_audit_pc (jobnumber number, processid varchar2, processname varchar2);
procedure etl_lms_far_luo_audit_vr (jobnumber number, processid varchar2, processname varchar2);
procedure etl_lms_far_luo_audit_log (jobnumber number, processid varchar2, processname varchar2);
procedure etl_lms_far_luo_audit_tableau(jobnumber number, processid varchar2, processname varchar2); 
end load_lms_etl_far_luo;
/

create or replace package body load_lms_etl_far_luo IS

procedure etl_lms_course_exclusions(jobnumber number, processid varchar2, processname varchar2) is
/*
Table: utl_d_lms.course_exclusions

Primary Keys: SURROGATE_ID

Unique index: TERM_CODE, CRN

Purpose:
- Pull inclusions/exclusions from submissions in the RAFT form
- https://apex.liberty.edu/banprd/f?p=253:100:6960369044313::NO:RP,100:FORM_NAME:FAR_EXCLUSION_FORM

Conditions:
- Only for courses that connect to Banner

Dependencies: utl_d_lms.lms_link;
*/
--DECLARE
--- PARAMS
v_etl_date    DATE := SYSDATE;
v_instance    VARCHAR2(50) := upper('L2CAN'); -- inst from the jams job; used for determining instance
v_partition    NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_msg         VARCHAR2(2000);
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_lms_course_exclusions';
--
BEGIN
-- dbms_output.enable(buffer_size => NULL);
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
--
IF v_instance IN ('ACCAN', 'BLACKBOARD') THEN
dbms_output.put_line(v_instance || ' is not active on this table');
ELSE
MERGE INTO utl_d_lms.course_exclusions destination
USING (SELECT ssbsect.ssbsect_term_code AS term_code,
              ssbsect.ssbsect_crn AS crn,
              ssbsect.ssbsect_subj_code AS subj_code,
              ssbsect.ssbsect_crse_numb AS crse_numb,
              ssbsect.ssbsect_ptrm_code AS ptrm_code,
              ssbsect.ssbsect_insm_code insm_code,
              CASE
              WHEN coalesce(act_reg.seats, 0) = 1 THEN
               'Independent Study'
              WHEN cc.ssrsprt_crn IS NOT NULL THEN
               'Disparate' || ', ' || gtvinsm_desc
              WHEN ssrxlst_crn IS NOT NULL THEN
               'Cross-Listed' || ', ' || gtvinsm_desc
              ELSE
               nvl(gtvinsm_desc, 'Online')
              END AS instructional_method,
              -- include by default
              CASE
              WHEN ssbsect.ssbsect_ptrm_code NOT IN ('R', '1A', '1B', '1C', '1D', '1J') THEN
               'Exclude'
              ELSE
               coalesce(vr, 'Include')
              END AS verified_roster,
              CASE
              WHEN ssbsect.ssbsect_ptrm_code NOT IN ('R', '1A', '1B', '1C', '1D', '1J') THEN
               'Exclude'
              WHEN ssrxlst_crn IS NOT NULL -- cross-listed Bb course get auto exclusion NO MATTER WHAT
                   AND coalesce(ssbsect_intg_cde, 'BLACKBOARD') = 'BLACKBOARD' THEN
               'Exclude'
              ELSE
               coalesce(fn, 'Include')
              END AS fn_compliance,
              CASE
              WHEN ssbsect.ssbsect_ptrm_code NOT IN ('R', '1A', '1B', '1C', '1D', '1J') THEN
               'Exclude'
              WHEN ssrxlst_crn IS NOT NULL -- cross-listed Bb course get auto exclusion NO MATTER WHAT
                   AND coalesce(ssbsect_intg_cde, 'BLACKBOARD') = 'BLACKBOARD' THEN
               'Exclude'
              ELSE
               coalesce(pc, 'Include')
              END AS pre_course,
              CASE               
              WHEN ssbsect.ssbsect_ptrm_code NOT IN ('R', '1A', '1B', '1C', '1D', '1J') THEN
               'Exclude'
              WHEN ssrxlst_crn IS NOT NULL -- cross-listed Bb course get auto exclusion NO MATTER WHAT
                   AND coalesce(ssbsect_intg_cde, 'BLACKBOARD') = 'BLACKBOARD' THEN
               'Exclude'
              ELSE
               coalesce(an, 'Include')
              END AS announcements,
              CASE
              WHEN ssbsect.ssbsect_ptrm_code NOT IN ('R', '1A', '1B', '1C', '1D', '1J') THEN
               'Exclude'
              WHEN ssrxlst_crn IS NOT NULL -- cross-listed Bb course get auto exclusion NO MATTER WHAT
                   AND coalesce(ssbsect_intg_cde, 'BLACKBOARD') = 'BLACKBOARD' THEN
               'Exclude'
              ELSE
               coalesce(la, 'Include')
              END AS last_activity,
              CASE
              WHEN ssbsect.ssbsect_ptrm_code NOT IN ('R', '1A', '1B', '1C', '1D', '1J') THEN
               'Exclude'
              WHEN ssrxlst_crn IS NOT NULL -- cross-listed Bb course get auto exclusion NO MATTER WHAT
                   AND coalesce(ssbsect_intg_cde, 'BLACKBOARD') = 'BLACKBOARD' THEN
               'Exclude'
              ELSE
               coalesce(gc, 'Include')
              END AS grading_compliance,
              CASE
              WHEN ssbsect.ssbsect_ptrm_code NOT IN ('R', '1A', '1B', '1C', '1D', '1J') THEN
               'Exclude'
              WHEN ssrxlst_crn IS NOT NULL -- cross-listed Bb course get auto exclusion NO MATTER WHAT
                   AND coalesce(ssbsect_intg_cde, 'BLACKBOARD') = 'BLACKBOARD' THEN
               'Exclude'
              ELSE
               coalesce(fc, 'Include')
              END AS faculty_card,
              CASE
              WHEN ssbsect.ssbsect_ptrm_code NOT IN ('R', '1A', '1B', '1C', '1D', '1J') THEN
               'Exclude'
              ELSE
               coalesce(fg, 'Include')
              END AS final_grades,
              CASE
              WHEN ssbsect.ssbsect_ptrm_code NOT IN ('R', '1A', '1B', '1C', '1D', '1J') THEN
               'Exclude'
              WHEN ssrxlst_crn IS NOT NULL -- cross-listed Bb course get auto exclusion NO MATTER WHAT
                   AND coalesce(ssbsect_intg_cde, 'BLACKBOARD') = 'BLACKBOARD' THEN
               'Exclude'
              ELSE
               coalesce(nudges, 'Include')
              END AS nudges,
              coalesce(ssbsect_intg_cde, 'BLACKBOARD') AS instance,
              SYSDATE activity_date
         FROM saturn.ssbsect
         LEFT JOIN gtvinsm
           ON gtvinsm_code = ssbsect.ssbsect_insm_code
         LEFT JOIN saturn.ssrxlst
           ON ssrxlst_term_code = ssbsect_term_code
          AND ssrxlst_crn = ssbsect_term_code
         LEFT JOIN (SELECT DISTINCT ssrsprt_term_code,
                                   ssrsprt_crn
                     FROM saturn.ssrsprt cc
                    WHERE cc.ssrsprt_pars_code IN ('EXPSMMT', 'EXPSMSL', 'EXILERN', 'EXINONE', 'EXPRGRN', 'EXPSMIT')) cc
           ON cc.ssrsprt_term_code = ssbsect_term_code
          AND cc.ssrsprt_crn = ssbsect_crn
         LEFT JOIN (SELECT sfrstcr.sfrstcr_crn AS crn,
                          sfrstcr.sfrstcr_term_code AS trm,
                          COUNT(DISTINCT sfrstcr_pidm) seats
                     FROM saturn.sfrstcr sfrstcr
                     JOIN saturn.stvrsts stvrsts
                       ON stvrsts.stvrsts_code = sfrstcr.sfrstcr_rsts_code
                      AND sfrstcr.sfrstcr_levl_code NOT IN ('JD', 'MD', 'PD', 'AC')
                      AND sfrstcr_rsts_code <> 'AU'
                      AND stvrsts.stvrsts_incl_sect_enrl = 'Y'
                      AND stvrsts.stvrsts_withdraw_ind = 'N'
                      AND stvrsts.stvrsts_incl_assess = 'Y'
                    WHERE sfrstcr_term_code IN (SELECT t.term_code
                                                  FROM zbtm.terms_by_group_v t
                                                 WHERE 1 = 1
                                                   AND SYSDATE < t.end_date + 21 -- Current or future enrollment
                                                   AND SYSDATE >= t.start_date
                                                   AND t.group_code IN ('STD')
                                                   AND t.term_code IN (SELECT DISTINCT ssbsect_term_code FROM ssbsect WHERE ssbsect_enrl > 0))
                    GROUP BY sfrstcr.sfrstcr_crn,
                             sfrstcr.sfrstcr_term_code) act_reg
           ON act_reg.crn = ssbsect.ssbsect_crn
          AND act_reg.trm = ssbsect.ssbsect_term_code
         LEFT JOIN (SELECT rsa_pivot.submission_id,
                          rsa_pivot.submission_pidm,
                          rsa_pivot.last_submission_date,
                          rsa_pivot.subj_code,
                          rsa_pivot.crse_numb,
                          CASE
                          WHEN rsa_pivot.vr = 'Y' THEN
                           'Include'
                          WHEN rsa_pivot.vr = 'N' THEN
                           'Exclude'
                          ELSE
                           'Unknown'
                          END AS vr,
                          CASE
                          WHEN rsa_pivot.fn = 'Y' THEN
                           'Include'
                          WHEN rsa_pivot.fn = 'N' THEN
                           'Exclude'
                          ELSE
                           'Unknown'
                          END AS fn,
                          CASE
                          WHEN rsa_pivot.pc = 'Y' THEN
                           'Include'
                          WHEN rsa_pivot.pc = 'N' THEN
                           'Exclude'
                          ELSE
                           'Unknown'
                          END AS pc,
                          CASE
                          WHEN rsa_pivot.an = 'Y' THEN
                           'Include'
                          WHEN rsa_pivot.an = 'N' THEN
                           'Exclude'
                          ELSE
                           'Unknown'
                          END AS an,
                          CASE
                          WHEN rsa_pivot.la = 'Y' THEN
                           'Include'
                          WHEN rsa_pivot.la = 'N' THEN
                           'Exclude'
                          ELSE
                           'Unknown'
                          END AS la,
                          CASE
                          WHEN rsa_pivot.gc = 'Y' THEN
                           'Include'
                          WHEN rsa_pivot.gc = 'N' THEN
                           'Exclude'
                          ELSE
                           'Unknown'
                          END AS gc,
                          CASE
                          WHEN rsa_pivot.fc = 'Y' THEN
                           'Include'
                          WHEN rsa_pivot.fc = 'N' THEN
                           'Exclude'
                          ELSE
                           'Unknown'
                          END AS fc,
                          CASE
                          WHEN rsa_pivot.fg = 'Y' THEN
                           'Include'
                          WHEN rsa_pivot.fg = 'N' THEN
                           'Exclude'
                          ELSE
                           'Unknown'
                          END AS fg,
                          CASE
                          WHEN rsa_pivot.nudges = 'Y' THEN
                           'Include'
                          WHEN rsa_pivot.nudges = 'N' THEN
                           'Exclude'
                          WHEN rsa_pivot.gc = 'Y' THEN
                           'Include'
                          WHEN rsa_pivot.gc = 'N' THEN
                           'Exclude'
                          ELSE
                           'Unknown'
                          END AS nudges,
                          rank() over(PARTITION BY rsa_pivot.subj_code, rsa_pivot.crse_numb ORDER BY rsa_pivot.last_submission_date DESC, rownum) ranking
                     FROM (SELECT sub.szbsubm_id AS submission_id,
                                  sub.szbsubm_locked_date AS last_submission_date,
                                  sub.szbsubm_pidm AS submission_pidm,
                                  MAX(CASE
                                      WHEN qest.szrqest_orig_qest_id = 95074 THEN
                                       ans.szresan_short_ans
                                      END) AS subj_code,
                                  MAX(CASE
                                      WHEN qest.szrqest_orig_qest_id = 95055 THEN
                                       ans.szresan_short_ans
                                      END) AS crse_numb,
                                  MAX(CASE
                                      WHEN qest.szrqest_orig_qest_id = 93323 THEN
                                       ans.szresan_short_ans
                                      END) AS vr,
                                  MAX(CASE
                                      WHEN qest.szrqest_orig_qest_id = 93338 THEN
                                       ans.szresan_short_ans
                                      END) AS fn,
                                  MAX(CASE
                                      WHEN qest.szrqest_orig_qest_id = 93322 THEN
                                       ans.szresan_short_ans
                                      END) AS pc,
                                  MAX(CASE
                                      WHEN qest.szrqest_orig_qest_id = 93337 THEN
                                       ans.szresan_short_ans
                                      END) AS an,
                                  MAX(CASE
                                      WHEN qest.szrqest_orig_qest_id = 93321 THEN
                                       ans.szresan_short_ans
                                      END) AS la,
                                  MAX(CASE
                                      WHEN qest.szrqest_orig_qest_id = 93356 THEN
                                       ans.szresan_short_ans
                                      END) AS gc,
                                  MAX(CASE
                                      WHEN qest.szrqest_orig_qest_id = 93318 THEN
                                       ans.szresan_short_ans
                                      END) AS fc,
                                  MAX(CASE
                                      WHEN qest.szrqest_orig_qest_id = 93355 THEN
                                       ans.szresan_short_ans
                                      END) AS fg,
                                  MAX(CASE
                                      WHEN qest.szrqest_orig_qest_id = 95914 THEN
                                       ans.szresan_short_ans
                                      END) AS nudges
                             FROM zraft.szbsubm sub
                           -- approval bottleneck
                             JOIN zgeneral.zgbwfpr pr
                               ON pr.zgbwfpr_proc_id = sub.szbsubm_wf_proc_id
                              AND pr.zgbwfpr_disposition IN ('Completed', 'Approved')
                             JOIN zraft.szresan ans
                               ON ans.szresan_szbsubm_id = sub.szbsubm_id
                              AND ans.szresan_to_date IS NULL
                             JOIN zraft.szrqest qest
                               ON qest.szrqest_id = ans.szresan_question_id
                            WHERE sub.szbsubm_szrfrms_id = 7201
                              AND sub.szbsubm_orig_sub_date IS NOT NULL
                            GROUP BY sub.szbsubm_id,
                                     sub.szbsubm_locked_date,
                                     sub.szbsubm_pidm) rsa_pivot) rp
           ON rp.subj_code = ssbsect_subj_code
          AND rp.crse_numb = ssbsect_crse_numb
          AND rp.ranking = 1
        WHERE ssbsect_term_code IN (SELECT t.term_code
                                      FROM zbtm.terms_by_group_v t
                                     WHERE 1 = 1
                                       AND SYSDATE < t.end_date + 21 -- Current or future enrollment
                                       AND t.group_code IN ('STD')
                                       AND t.term_code IN (SELECT DISTINCT ssbsect_term_code FROM ssbsect WHERE ssbsect_enrl > 0))) new_records
ON (destination.crn = new_records.crn AND destination.term_code = new_records.term_code)
WHEN MATCHED THEN
UPDATE
   SET destination.subj_code            = new_records.subj_code,
       destination.crse_numb            = new_records.crse_numb,
       destination.ptrm_code            = new_records.ptrm_code,
       destination.insm_code            = new_records.insm_code,
       destination.instructional_method = new_records.instructional_method,
       destination.verified_roster      = new_records.verified_roster,
       destination.fn_compliance        = new_records.fn_compliance,
       destination.pre_course           = new_records.pre_course,
       destination.announcements        = new_records.announcements,
       destination.last_activity        = new_records.last_activity,
       destination.grading_compliance   = new_records.grading_compliance,
       destination.faculty_card         = new_records.faculty_card,
       destination.final_grades         = new_records.final_grades,
       destination.nudges               = new_records.nudges,
       destination.instance             = new_records.instance,
       destination.activity_date        = new_records.activity_date
WHEN NOT MATCHED THEN
INSERT
(term_code,
 crn,
 subj_code,
 crse_numb,
 ptrm_code,
 insm_code,
 instructional_method,
 verified_roster,
 fn_compliance,
 pre_course,
 announcements,
 last_activity,
 grading_compliance,
 faculty_card,
 final_grades,
 nudges,
 instance,
 activity_date)
VALUES
(new_records.term_code,
 new_records.crn,
 new_records.subj_code,
 new_records.crse_numb,
 new_records.ptrm_code,
 new_records.insm_code,
 new_records.instructional_method,
 new_records.verified_roster,
 new_records.fn_compliance,
 new_records.pre_course,
 new_records.announcements,
 new_records.last_activity,
 new_records.grading_compliance,
 new_records.faculty_card,
 new_records.final_grades,
 new_records.nudges,
 new_records.instance,
 new_records.activity_date);
v_count := SQL%ROWCOUNT;
COMMIT;
v_msg := 'MERGE - ' || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
v_total_count := v_total_count + v_count;
COMMIT;
END IF;
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
VERSION DATE        USERNAME    UPDATES
---     06-23-2021  WGRIFFITH2  --Initial release
---     08-11-2021  WGRIFFITH2  --Adding in the approval level to RAFT form sub-select
---     05-15-2025  WGRIFFITH2  --'Independent Study' was forcing gray on the FAR for announcements. removed 
------------------------------------------------------------------------------------------------*/
END etl_lms_course_exclusions;

procedure etl_lms_far_luo_audit_tableau(jobnumber NUMBER, processid VARCHAR2, processname VARCHAR2) IS
--DECLARE
--- PARAMS
v_etl_date    DATE := SYSDATE;
v_instance    VARCHAR2(50) := upper('L2CAN'); -- inst from the jams job; used for determining instance
v_partition    NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_msg         VARCHAR2(2000);
v_count_delete   NUMBER := 0;
v_elapsed_delete NUMBER := 0;
v_msg_delete     VARCHAR2(2000);
v_count_insert   NUMBER := 0;
v_elapsed_insert NUMBER := 0;
v_msg_insert     VARCHAR2(2000);
v_job_id VARCHAR2(32);
v_proc   VARCHAR2(100) := 'etl_lms_far_luo_audit_tableau';
BEGIN
-- dbms_output.enable(buffer_size => NULL);
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
DELETE FROM utl_d_lms.far_luo_audit_tableau; -- NO TRUNCATE; ENSURE CONSTANT UPTIME
v_count_delete   := SQL%ROWCOUNT;
v_total_count    := v_total_count + v_count_delete;
v_elapsed_delete := round((SYSDATE - v_etl_date) * 86400);
v_msg_delete     := 'DELETE - ' || 'ALL' || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
-- NO COMMIT UNTIL INSERT HAPPENS; ENSURE CONSTANT UPTIME
INSERT INTO utl_d_lms.far_luo_audit_tableau
(unique_id,
 semester,
 coll_desc,
 course_code,
 url,
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
SELECT coalesce(flags.unique_id, courses.course_section_id || '_' || cat_codes.category_code || '0' || '_' || to_char(SYSDATE, 'YYYYMMDD')) AS unique_id,
       t.term_desc AS semester,
       courses.coll_desc,
       courses.course_code,
       coalesce(flags.url, courses.url) AS url,
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
       nvl(flags.compliance_status_code, '0') AS compliance_status_code,
       -- this is where we split up between what colors the instructor will see vs >=IM
       -- currently, the only difference is >=IM see color for last activity, but color does NOT show for instructors [only]
       -- in tableau, we will check for their username in a calculated field
       -- 0 = green; 1 = yellow; 2 = red; 3 = grey
       CASE
       WHEN substr(flags.compliance_status_reason, 1, 25) = 'Canvas data feed is stale' THEN
        '3' -- show grey if CD2 is stale
       WHEN cat_codes.category_code = 'LA' THEN
        '3' -- ** NOT SHOWING ACTIVITY TO INSTRUCTORS **
       WHEN coalesce(ce.verified_roster, 'Include') = 'Exclude'
            AND cat_codes.category_code = 'VR' THEN
        '3'
       WHEN coalesce(ce.fn_compliance, 'Include') = 'Exclude'
            AND cat_codes.category_code = 'FN' THEN
        '3'
       WHEN coalesce(ce.pre_course, 'Include') = 'Exclude'
            AND cat_codes.category_code = 'PC' THEN
        '3'
       WHEN coalesce(ce.announcements, 'Include') = 'Exclude'
            AND cat_codes.category_code = 'AN' THEN
        '3'
       WHEN coalesce(ce.grading_compliance, 'Include') = 'Exclude'
            AND cat_codes.category_code = 'GC' THEN
        '3'
       WHEN coalesce(ce.faculty_card, 'Include') = 'Exclude'
            AND cat_codes.category_code = 'FC' THEN
        '3'
       WHEN coalesce(ce.final_grades, 'Include') = 'Exclude'
            AND cat_codes.category_code = 'FG' THEN
        '3'
       ELSE
        nvl(flags.compliance_status_code, '0')
       END AS instructor_status_code,
       CASE
       WHEN substr(flags.compliance_status_reason, 1, 25) = 'Canvas data feed is stale' THEN
        '3' -- show grey if CD2 is stale
       WHEN coalesce(ce.last_activity, 'Include') = 'Exclude'
            AND cat_codes.category_code = 'LA' THEN
        '3'
       WHEN coalesce(ce.verified_roster, 'Include') = 'Exclude'
            AND cat_codes.category_code = 'VR' THEN
        '3'
       WHEN coalesce(ce.fn_compliance, 'Include') = 'Exclude'
            AND cat_codes.category_code = 'FN' THEN
        '3'
       WHEN coalesce(ce.pre_course, 'Include') = 'Exclude'
            AND cat_codes.category_code = 'PC' THEN
        '3'
       WHEN coalesce(ce.announcements, 'Include') = 'Exclude'
            AND cat_codes.category_code = 'AN' THEN
        '3'
       WHEN coalesce(ce.grading_compliance, 'Include') = 'Exclude'
            AND cat_codes.category_code = 'GC' THEN
        '3'
       WHEN coalesce(ce.faculty_card, 'Include') = 'Exclude'
            AND cat_codes.category_code = 'FC' THEN
        '3'
       WHEN coalesce(ce.final_grades, 'Include') = 'Exclude'
            AND cat_codes.category_code = 'FG' THEN
        '3'
       ELSE
        nvl(flags.compliance_status_code, '0')
       END AS admin_status_code,
       nvl(flags.compliance_status_reason, '(no action items)') AS compliance_status_reason,
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
        courses.course_code || ' has completed. '
       WHEN cal.week_number IS NOT NULL
            AND courses.exclusions IS NOT NULL THEN
        TRIM(courses.course_code || ' is currently in week ' || cal.week_number || '. ' || REPLACE(courses.exclusions, 'Other', 'Exclusion') || ' course. ')
       WHEN cal.week_number IS NOT NULL THEN
        TRIM(courses.course_code || ' is currently in week ' || cal.week_number || '. ')
       ELSE
        courses.course_code || ' in-progress'
       END AS course_status,
       courses.enrollment,
       -- Row level security:
       courses.faculty_email,
       fht.instructor_username,
       fht.im_usernames,
       fht.chair_usernames,
       fht.dean_usernames,
       fht.fsc_usernames,
       fht.sme_usernames,
       fht.director_usernames,
       fht.admin_usernames,
       '-' || fht.instructor_username || '-' || fht.im_usernames || '-' || fht.chair_usernames || '-' || fht.dean_usernames || '-' || fht.fsc_usernames || '-' || fht.sme_usernames || '-' || fht.director_usernames || '-' ||
       fht.admin_usernames || '-' AS all_usernames
  FROM utl_d_lms.far_luo_courses courses -- controls population
  JOIN utl_d_lms.far_luo_cat_code cat_codes
    ON 1 = 1
   AND cat_codes.category_code NOT IN ('FC') -- EXPIRED 20220323
  LEFT JOIN utl_d_aa.crscalendar cal
    ON cal.crn = courses.crn
   AND cal.term_code = courses.term_code
   AND SYSDATE >= cal.dte
   AND SYSDATE < cal.dte + 1
  LEFT JOIN utl_d_lms.far_luo_audit flags -- must be left join to show all categories on dashboard
    ON flags.term_code = courses.term_code
   AND flags.crn = courses.crn
   AND flags.compliance_category_code = cat_codes.category_code
   AND flags.status = 'ACTIVE'
   AND flags.deleted_ind <> 'Y'
  LEFT JOIN utl_d_aa.secfht fht
    ON courses.term_code = fht.term_code
   AND courses.crn = fht.crn
  LEFT JOIN zbtm.terms_by_group_v t
    ON t.term_code = courses.term_code
  LEFT JOIN utl_d_lms.course_exclusions ce
    ON ce.term_code = courses.term_code
   AND ce.crn = courses.crn
 WHERE 1 = 1;
v_count_insert   := SQL%ROWCOUNT;
v_total_count    := v_total_count + v_count_insert;
v_elapsed_insert := round((SYSDATE - v_etl_date) * 86400);
v_msg_insert     := 'INSERT - ' || 'ALL' || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
IF v_count_insert > 1 THEN
COMMIT; -- commit! (we found records on the insert)
dbms_output.put_line(v_msg_delete || ' - rows processed: ' || to_char(v_count_delete));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg_delete, v_instance, v_partition, v_job_id, v_elapsed_delete, v_count_delete);
dbms_output.put_line(v_msg_insert || ' - rows processed: ' || to_char(v_count_insert));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg_insert, v_instance, v_partition, v_job_id, v_elapsed_insert, v_count_insert);
dbms_output.put_line(' --------- ');
ELSE
ROLLBACK; -- rollback!! (if no records found in the insert)
dbms_output.put_line(v_msg_delete || ' - rows processed: ' || to_char(v_count_delete));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg_delete, v_instance, v_partition, v_job_id, v_elapsed_delete, v_count_delete);
dbms_output.put_line(v_msg_insert || ' - rows processed: ' || to_char(v_count_insert));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg_insert, v_instance, v_partition, v_job_id, v_elapsed_insert, v_count_insert);
dbms_output.put_line(' --------- ');
END IF;
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
---      02-03-2023  WGRIFFITH2  --Initial release
---      06-26-2023  WGRIFFITH2  --we have to remove rows for cross listed courses that have the same course code, but different crn/term and course_section_id; ROLLBACK ON 20240820
---      10-02-2024  WGRIFFITH2  --adding in the IF v_count > 1 THEN commit else rollback for constant up-time on the dashboard
------------------------------------------------------------------------------------------------*/
END etl_lms_far_luo_audit_tableau;
procedure etl_lms_far_luo_audit_log(jobnumber NUMBER, processid VARCHAR2, processname VARCHAR2) IS
--DECLARE
--- PARAMS
v_etl_date    DATE := SYSDATE;
v_instance    VARCHAR2(50) := upper('L2CAN'); -- inst from the jams job; used for determining instance
v_partition    NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_msg         VARCHAR2(2000);
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_lms_far_luo_audit_log';
CURSOR c_terms IS
SELECT ll.term_code,
       ll.ptrm_code,
       MIN(ll.start_date) AS start_date,
       MAX(ll.end_date) AS end_date,
       MAX(ll.end_date + 21) - 1 AS expiration_date -- leave the minus one; need expirations to occur on last day reports run
  FROM zbtm.terms_by_group_v t
  JOIN utl_d_lms.lms_link ll
    ON ll.term_code = t.term_code
 WHERE 1 = 1
   AND ll.status IN ('active', 'concluded')
   AND ll.enrollment > 0
   AND ll.instance = 'L2CAN'
   AND t.group_code = 'STD'
   AND t.semester <> 'WIN'
   AND ll.ptrm_code IN ('R', '1A', '1B', '1C', '1D', '1J')
   AND SYSDATE <= (ll.end_date + 21) --stop running;
 GROUP BY ll.term_code,
          ll.ptrm_code
 ORDER BY end_date DESC;
BEGIN
-- dbms_output.enable(buffer_size => NULL);
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
DELETE FROM utl_d_lms.far_luo_audit fla -- REMOVE ANY ROWS THAT ARE NO LONGER CURRENT
 WHERE NOT EXISTS (SELECT 'X'
          FROM utl_d_lms.far_luo_courses flc
         WHERE fla.instance = flc.instance
           AND fla.course_section_id = flc.course_section_id);
COMMIT;
FOR rec IN c_terms
LOOP
v_count   := 0; -- reset count
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || rec.term_code || rec.ptrm_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- CLEAR ANY RECORDS OF COURSES THAT NO LONGER EXIST IN BANNER
-- often these are courses that get rolled week 1
UPDATE utl_d_lms.far_luo_audit fla
   SET (fla.status, fla.flag_count, fla.deleted_ind, fla.deleted_reason) =
       (SELECT 'EXPIRED',
               0,
               'Y',
               'SYSTEM: ' || 'Course no longer has enrollment in sfrstcr.'
          FROM dual)
 WHERE fla.instance = v_instance
   AND fla.term_code = rec.term_code
   AND fla.ptrm_code = rec.ptrm_code
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
-- look for red flags that appeared before the start date of the course; this is impossible! only yellows can appear
-- this occurs when course creation triggers FAR refresh with wrong [J-term] start date, causing error; fixed by updating dates and manually removing orphaned dashboard records.
UPDATE utl_d_lms.far_luo_audit fla
   SET (fla.status, fla.flag_count, fla.deleted_ind, fla.deleted_reason) =
       (SELECT 'EXPIRED',
               0,
               'Y',
               'SYSTEM: ' || 'Incorrect start date recognized.'
          FROM dual)
 WHERE fla.instance = v_instance
   AND fla.term_code = rec.term_code
   AND fla.ptrm_code = rec.ptrm_code
   AND EXISTS (SELECT 1
          FROM utl_d_lms.far_luo_courses flc
         WHERE fla.term_code = flc.term_code
           AND fla.crn = flc.crn
           AND fla.audit_date < flc.start_date - 1 -- first found is less start date
           AND fla.compliance_status_code = '2' -- dead red
           AND fla.deleted_ind <> 'Y'
           AND fla.compliance_category_code <> 'LA');
v_count := v_count + SQL%ROWCOUNT;
COMMIT;
-- update what is currently on the far_luo_audit table
MERGE INTO utl_d_lms.far_luo_audit_log destination_table
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
         FROM utl_d_lms.far_luo_audit fla
        WHERE fla.term_code = rec.term_code
          AND fla.ptrm_code = rec.ptrm_code) new_records
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
v_msg := 'MERGE - ' || rec.term_code || rec.ptrm_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
v_total_count := v_total_count + v_count;
-- remove all rows that have been expired
-- historical records live in the log table, but we want to keep far_luo_audit small as possible
DELETE FROM utl_d_lms.far_luo_audit fla
 WHERE EXISTS (SELECT flal.unique_id
          FROM utl_d_lms.far_luo_audit_log flal
         WHERE flal.status = 'EXPIRED'
           AND flal.deleted_ind = 'N' -- leave any deleted records on the table so they do not keep reappearing
           AND flal.unique_id = fla.unique_id
           AND flal.term_code = rec.term_code
           AND flal.ptrm_code = rec.ptrm_code);
v_count := SQL%ROWCOUNT;
COMMIT;
v_msg := 'DELETE - ' || rec.term_code || rec.ptrm_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
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
---      11-23-2020  WGRIFFITH2  --Initial release
---      11-29-2020  WGRIFFITH2  --Adding unique_id
---      06-25-2021  WGRIFFITH2  --Now using the RAFT form to track exclusions
---      03-28-2022  WGRIFFITH2  --Deprecated Bb code; moved to using the course_section_id instead of section_sis_id
---      04-14-2022  WGRIFFITH2  --Now removing EXPIRED records from far_luo_audit instead of holding the expired records there until ptrm is over
---      06-17-2025  WGRIFFITH2  --Course creation with wrong J-term date causes impossible red flags; fixed by updating dates, removing orphaned records.
------------------------------------------------------------------------------------------------*/
END etl_lms_far_luo_audit_log;

procedure etl_lms_far_luo_audit_pc (jobnumber number, processid varchar2, processname varchar2) IS
/*
* Purpose:
*     - Looks for sections in which the prof did not post an welcome announcement before first day of course
*     -
* Conditions:
*    - The announcement cannot be one of the default announcements in the LUO_Announcements course
*/
--DECLARE
--- PARAMS
v_etl_date    DATE := SYSDATE;
v_instance    VARCHAR2(50) := upper('L2CAN'); -- inst from the jams job; used for determining instance
v_partition    NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_msg         VARCHAR2(2000);
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_lms_far_luo_audit_pc';
v_cat_code    VARCHAR2(2) := 'PC';
-- CURSOR
CURSOR c_terms IS
SELECT ll.term_code,
       ll.ptrm_code,
       MIN(ll.start_date) AS start_date,
       MAX(ll.end_date) AS end_date,
       MAX(ll.start_date + 3) - 1 AS expiration_date -- leave the minus one; need expirations to occur on last day reports run
  FROM zbtm.terms_by_group_v t
  JOIN utl_d_lms.lms_link ll
    ON ll.term_code = t.term_code
 WHERE 1 = 1
   AND ll.status IN ('active', 'concluded')
   AND ll.enrollment > 0
   AND ll.instance = 'L2CAN'
   AND t.group_code = 'STD'
   AND t.semester <> 'WIN'
   AND ll.ptrm_code IN ('R', '1A', '1B', '1C', '1D', '1J')
   AND SYSDATE <= (ll.start_date + 3) --stop running; ** needs to match expiration date **
--    AND to_number(to_char(SYSDATE, 'HH24')) = v_partition -- ONLY RUN DURING THIS TIME; running one partition at a time to avoid deadlocks
 GROUP BY ll.term_code,
          ll.ptrm_code
 ORDER BY MIN(ll.start_date) DESC,
          ll.ptrm_code;
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
v_msg     := 'START - ' || rec.term_code || rec.ptrm_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
MERGE /*+ USE_MERGE(courses ll) USE_NL(ann) */
INTO utl_d_lms.far_luo_audit destination_table
USING (SELECT /*+ LEADING(courses ll) USE_NL(ann) */
        courses.term_code,
        courses.crn,
        courses.coll_code,
        courses.coll_desc,
        courses.course_code,
        courses.course_sis_id,
        courses.section_sis_id,
        courses.course_id,
        courses.course_section_id,
        'https://libertyuniversity.instructure.com/courses/' || to_char(courses.course_id) || '/announcements' AS url,
        courses.camp_code,
        courses.ptrm_code,
        courses.insm_code,
        courses.faculty_pidm,
        courses.faculty_name,
        courses.faculty_email,
        v_cat_code compliance_category_code,
        CASE
        WHEN ann.posted_date IS NOT NULL THEN -- show announcement(s) if posted
         '0'
        WHEN ann.posted_date IS NULL
             AND v_etl_date < ll.start_date THEN -- yellow if not posted and it's prior to day one
          '1'
         WHEN ann.posted_date IS NULL
              AND v_etl_date >= ll.start_date THEN -- red if not posted and it's day one or after
         '2'
        END AS compliance_status_code,
        CASE
         WHEN ann.posted_date IS NOT NULL THEN -- show announcement(s) if posted
          '"' || TRIM(ann.title) || '" was posted at: ' || to_char(ann.posted_date, 'MM/DD/YYYY hh24:mi:ss')
         WHEN ann.posted_date IS NULL
              AND ann.created_date IS NOT NULL
              AND v_etl_date < ll.start_date THEN -- yellow; -- record exists but is not visable to students
          '"' || TRIM(ann.title) || '" was created at: ' || to_char(ann.created_date, 'MM/DD/YYYY hh24:mi:ss') || ' but the delayed posted date must be set on any preloaded announcement before ' ||
          to_char(trunc(courses.start_date) - 1 / (24 * 60 * 60), 'MM/DD/YYYY hh24:mi:ss')
         WHEN ann.posted_date IS NULL
              AND ann.created_date IS NULL
              AND v_etl_date < ll.start_date THEN -- yellow if not posted and it's prior to day one
         'Pre-course announcement needed before ' || to_char(trunc(courses.start_date) - 1 / (24 * 60 * 60), 'MM/DD/YYYY hh24:mi:ss')
        WHEN ann.posted_date IS NULL
             AND ann.created_date IS NOT NULL
             AND v_etl_date >= ll.start_date THEN -- red if not posted and it's day one or after
          '"' || TRIM(ann.title) || '" was created at: ' || to_char(ann.created_date, 'MM/DD/YYYY hh24:mi:ss') || ' but the delayed posted date must be set on any preloaded announcement before ' ||
          to_char(trunc(courses.start_date) - 1 / (24 * 60 * 60), 'MM/DD/YYYY hh24:mi:ss')
         WHEN ann.posted_date IS NULL
              AND v_etl_date >= ll.start_date THEN -- red if not posted and it's day one or after
         'No pre-course announcement found before ' || to_char(trunc(courses.start_date) - 1 / (24 * 60 * 60), 'MM/DD/YYYY hh24:mi:ss')
        END AS compliance_status_reason,
        v_etl_date audit_date,
        'N' deleted_ind,
        NULL deleted_reason,
        CASE
        WHEN ann.posted_date IS NOT NULL THEN -- show announcement(s) if posted
         courses.course_section_id || '_' || v_cat_code || '0' || '_' || ann.announcement_id
        WHEN ann.posted_date IS NULL
             AND v_etl_date < ll.start_date THEN -- yellow if not posted and it's prior to day one
          courses.course_section_id || '_' || v_cat_code || '1' || '_' || to_char(courses.start_date, 'YYYYMMDD')
         WHEN ann.posted_date IS NULL
              AND v_etl_date >= ll.start_date THEN -- red if not posted and it's day one or after
         courses.course_section_id || '_' || v_cat_code || '2' || '_' || to_char(courses.start_date, 'YYYYMMDD')
        END AS unique_id,
        CASE
        WHEN fla.deleted_ind = 'Y' THEN
         0
        WHEN ann.posted_date IS NOT NULL THEN
         0
        WHEN fla.course_section_id IS NOT NULL THEN
         ceil(v_etl_date - coalesce(fla.audit_date, v_etl_date - 1 / 24)) -- coalesce is for the first record entry
        ELSE
         1
        END AS flag_count,
        v_etl_date AS last_modified,
        'ACTIVE' AS status,
        courses.instance
         FROM utl_d_lms.far_luo_courses courses
         JOIN utl_d_lms.lms_link ll
           ON ll.course_section_id = courses.course_section_id
          AND ll.instance = courses.instance
          AND courses.instance = v_instance
          AND courses.term_code = rec.term_code
          AND courses.ptrm_code = rec.ptrm_code
         JOIN (SELECT courses.course_section_id, -- this join has all active courses in it
                     courses.course_id,
                     courses.instance,
                     ann.title,
                     ann.announcement_id,
                     -- **this rank determines the FIRST announcement posted**
                     rank() over(PARTITION BY courses.course_section_id, courses.instance ORDER BY coalesce(ann.delayed_posted_date, ann.posted_date) ASC NULLS LAST, ann.position ASC, ann.created_date ASC, ann.announcement_id ASC) AS ranking,
                     ann.created_date,
                     coalesce(ann.delayed_posted_date, ann.posted_date) AS posted_date,
                     CASE
                     WHEN ann.created_date IS NOT NULL
                          AND coalesce(ann.delayed_posted_date, ann.posted_date) < courses.start_date THEN -- posted before start, so count starts on start date
                      trunc(coalesce(ann.delayed_posted_date, ann.posted_date, courses.start_date - 0) + 1) - 1 / (24 * 60 * 60) + 7
                     ELSE
                      trunc(coalesce(ann.delayed_posted_date, ann.posted_date, courses.start_date - 7) + 1) - 1 / (24 * 60 * 60) + 7
                     END AS posted_date_plus7, -- next announcement due
                     CASE
                     WHEN ann.created_date IS NOT NULL
                          AND coalesce(ann.delayed_posted_date, ann.posted_date) < courses.start_date THEN -- posted before start, so count starts on start date
                      ceil(v_etl_date - (trunc(coalesce(ann.delayed_posted_date, ann.posted_date, courses.start_date - 0) + 1) - 1 / (24 * 60 * 60)))
                     ELSE
                      ceil(v_etl_date - (trunc(coalesce(ann.delayed_posted_date, ann.posted_date, courses.start_date - 7) + 1) - 1 / (24 * 60 * 60)))
                     END AS days_since
                FROM utl_d_lms.far_luo_courses courses
                JOIN utl_d_lms.lms_link ll
                  ON ll.course_section_id = courses.course_section_id
                 AND ll.instance = courses.instance
                 AND courses.instance = v_instance
                 AND courses.term_code = rec.term_code
                 AND courses.ptrm_code = rec.ptrm_code
                LEFT JOIN utl_d_lms.announcements ann -- using utl_d_lms.announcements table for optimization and api validation
                  ON courses.course_section_id = ann.course_section_id
                 AND courses.instance = ann.instance
                 AND coalesce(ann.delayed_posted_date, ann.posted_date, ann.created_date) < trunc(v_etl_date) - 1 / (24 * 60 * 60) + 1 -- time when students see the announcement
              ) ann
           ON ann.course_section_id = courses.course_section_id
          AND ann.instance = courses.instance
          AND ann.ranking = 1
         LEFT JOIN utl_d_lms.far_luo_audit fla
           ON fla.unique_id = CASE
              WHEN ann.posted_date IS NOT NULL THEN -- show announcement(s) if posted
               courses.course_section_id || '_' || v_cat_code || '0' || '_' || ann.announcement_id
              WHEN ann.posted_date IS NULL
                   AND v_etl_date < ll.start_date THEN -- yellow if not posted and it's prior to day one
               courses.course_section_id || '_' || v_cat_code || '1' || '_' || to_char(courses.start_date, 'YYYYMMDD')
              WHEN ann.posted_date IS NULL
                   AND v_etl_date >= ll.start_date THEN -- red if not posted and it's day one or after
               courses.course_section_id || '_' || v_cat_code || '2' || '_' || to_char(courses.start_date, 'YYYYMMDD')
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
v_msg     := 'MERGE - ' || rec.term_code || rec.ptrm_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line('Applying any exclusions for courses in: ' || rec.term_code || rec.ptrm_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ';');
UPDATE utl_d_lms.far_luo_audit fla
   SET fla.deleted_ind              = 'Y',
       fla.compliance_category_code = v_cat_code,
       fla.flag_count               = 0,
       fla.deleted_reason          =
       (SELECT 'Exclusion(s): ' || xl.instructional_method || ' course'
          FROM utl_d_lms.course_exclusions xl
          JOIN utl_d_lms.far_luo_courses flc
            ON flc.crn = xl.crn
           AND flc.term_code = xl.term_code
         WHERE xl.pre_course = 'Exclude'
           AND xl.term_code = rec.term_code
           AND xl.crn = fla.crn
           AND xl.term_code = fla.term_code)
 WHERE fla.term_code = rec.term_code
   AND fla.ptrm_code = rec.ptrm_code
   AND fla.compliance_category_code = v_cat_code
   AND fla.compliance_status_code IN ('1', '2') -- ONLY YELLOW AND RED FLAGS GET INVALIDATED
   AND fla.deleted_ind = 'N'
   AND EXISTS (SELECT 'Exclusion(s): ' || xl.instructional_method || ' course'
          FROM utl_d_lms.course_exclusions xl
          JOIN utl_d_lms.far_luo_courses flc
            ON flc.crn = xl.crn
           AND flc.term_code = xl.term_code
         WHERE xl.pre_course = 'Exclude'
           AND xl.term_code = rec.term_code
           AND xl.crn = fla.crn
           AND xl.term_code = fla.term_code);
v_count := v_count + SQL%ROWCOUNT;
COMMIT;
dbms_output.put_line('Expiring records that are no longer active in: ' || rec.term_code || rec.ptrm_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ';');
UPDATE utl_d_lms.far_luo_audit fla
   SET fla.status = 'EXPIRED' -- if the last_modified did NOT get updated on the last run, it is no longer active;
 WHERE fla.compliance_category_code = v_cat_code
   AND fla.term_code = rec.term_code
   AND fla.ptrm_code = rec.ptrm_code
   AND fla.instance = v_instance
   AND fla.status = 'ACTIVE'
   AND ((fla.last_modified < v_etl_date) OR (v_etl_date >= rec.expiration_date)); -- expire records if still active on expiration date
v_count := v_count + SQL%ROWCOUNT;
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'UPDATE - ' || rec.term_code || rec.ptrm_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
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
---      11-05-2020  WGRIFFITH2  --Initial release
---      11-29-2020  WGRIFFITH2  --Adding unique_id
---      04-15-2021  WGRIFFITH2  --Changing unique_id
---      06-25-2021  WGRIFFITH2  --Now using the RAFT form to track exclusions
---      07-26-2021  WGRIFFITH2  --Adding a way to fill in the gaps for certain zoct misses
---      03-28-2022  WGRIFFITH2  --Deprecated Bb code; moved to using the course_section_id instead of section_sis_id
---      01-20-2023  WGRIFFITH2  --remains red for the first 14 days of the course as long as no announcements are posted
---      04-07-2023  WGRIFFITH2  --Update to how the proc works with REST API validation
---      05-18-2023  WGRIFFITH2  --Fixed ranking. It was incorrectly sorting the best announcement to return when there were imported announcements
---      08-12-2024  WGRIFFITH2  --Perfomance issues that were only resolved by adding partitions - TKT2952695 --ROLLED BACK ON 08-20-2024
---      08-11-2025  WGRIFFITH2  --Used optimizer hints for faster large joins
------------------------------------------------------------------------------------------------*/
END etl_lms_far_luo_audit_pc;
procedure etl_lms_far_luo_audit_vr(jobnumber NUMBER, processid VARCHAR2, processname VARCHAR2) IS
/*
* Purpose:
*    - Track roster verifications in Banner
* Conditions:
*    - student must be registered for the course and instructor has verified they are in the course in the LMS
*/
--DECLARE
--- PARAMS
v_etl_date    DATE := SYSDATE;
v_instance    VARCHAR2(50) := upper('L2CAN'); -- inst from the jams job; used for determining instance
v_partition    NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_msg         VARCHAR2(2000);
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_lms_far_luo_audit_vr';
v_cat_code    VARCHAR2(2) := 'VR';
-- CURSOR
CURSOR c_terms IS
SELECT ll.term_code,
       ll.ptrm_code,
       MIN(ll.start_date) AS start_date,
       MAX(ll.end_date) AS end_date,
       MAX(ll.end_date + 0) - 1 AS expiration_date -- leave the minus one; need expirations to occur on last day reports run
  FROM zbtm.terms_by_group_v t
  JOIN utl_d_lms.lms_link ll
    ON ll.term_code = t.term_code
 WHERE 1 = 1
   AND ll.status IN ('active', 'concluded')
   AND ll.enrollment > 0
   AND ll.instance = 'L2CAN'
   AND t.group_code = 'STD'
   AND t.semester <> 'WIN'
   AND ll.ptrm_code IN ('R', '1A', '1B', '1C', '1D', '1J')
   AND SYSDATE <= (ll.end_date + 0) --stop running; ** needs to match expiration date **
 GROUP BY ll.term_code,
          ll.ptrm_code
 ORDER BY end_date DESC;
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
v_msg     := 'START - ' || rec.term_code || rec.ptrm_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
MERGE INTO utl_d_lms.far_luo_audit destination_table
USING (SELECT courses.term_code,
              courses.crn,
              courses.coll_code,
              courses.coll_desc,
              courses.course_code,
              courses.course_sis_id,
              courses.section_sis_id,
              courses.course_id,
              courses.course_section_id,
              'https://libertyuniversity.instructure.com/courses/' || to_char(courses.course_id) || '/external_tools/163054' AS url,
              courses.camp_code,
              courses.ptrm_code,
              courses.insm_code,
              courses.faculty_pidm,
              courses.faculty_name,
              courses.faculty_email,
              v_cat_code compliance_category_code,
              roster_verification.compliance_status_code,
              roster_verification.compliance_status_reason,
              v_etl_date audit_date,
              'N' deleted_ind,
              NULL deleted_reason,
              courses.course_section_id || '_' || v_cat_code || roster_verification.compliance_status_code || '_' || lpad(to_char(roster_verification.luid), 9, 'L00000000') AS unique_id, -- 20204054321_VR2_L20070201
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
         FROM utl_d_lms.far_luo_courses courses
         JOIN (SELECT stcr.sfrstcr_term_code term_code,
                     stcr.sfrstcr_crn crn,
                     spriden_id AS luid,
                     CASE
                     WHEN stcr.sfrstcr_attend_hr IS NULL
                          AND stcr.sfrstcr_add_date <= flc.start_date -- registered before START
                          AND v_etl_date < flc.start_date + 9 THEN
                      '1' -- This field will turn yellow if a student has not been verified before the end of first week
                     WHEN stcr.sfrstcr_attend_hr IS NULL
                          AND stcr.sfrstcr_add_date <= flc.start_date -- registered before START
                          AND v_etl_date >= flc.start_date + 9 THEN
                      '2' -- This field will turn red if a student has not been verified after the end of first week
                     WHEN stcr.sfrstcr_attend_hr IS NULL -- NOTHING MARKED YET
                          AND stcr.sfrstcr_add_date >= flc.start_date -- registered AFTER START
                          AND v_etl_date < stcr.sfrstcr_add_date + 7 THEN
                      '1' -- This field will turn yellow if a student has not been verified before the end of first week
                     WHEN stcr.sfrstcr_attend_hr IS NULL -- NOTHING MARKED YET
                          AND stcr.sfrstcr_add_date >= flc.start_date -- registered AFTER START
                          AND v_etl_date >= stcr.sfrstcr_add_date + 7 THEN
                      '1' -- always showing yellow in this situation... if a student has not been verified after the end of first week
                     WHEN stcr.sfrstcr_attend_hr = 0
                          AND v_etl_date >= flc.start_date + 9 THEN
                      '1'
                     END compliance_status_code, -- **must update the WHERE clause to match this**
                     CASE
                     WHEN stcr.sfrstcr_attend_hr IS NULL
                          AND stcr.sfrstcr_add_date <= flc.start_date -- registered before START
                          AND v_etl_date < flc.start_date + 9 THEN
                      'Roster verification for ' || spriden_first_name || ' ' || spriden_last_name || '-' || lpad(to_char(spriden_id), 9, 'L00000000') || ' is due: ' ||
                      to_char(trunc(flc.start_date + 1) - 1 / (24 * 60 * 60) + 8, 'MM/DD/YYYY hh24:mi:ss') || '. Student was added to the course on ' || to_char(stcr.sfrstcr_add_date, 'MM/DD/YYYY hh24:mi:ss')
                     WHEN stcr.sfrstcr_attend_hr IS NULL
                          AND stcr.sfrstcr_add_date <= flc.start_date -- registered before START
                          AND v_etl_date >= flc.start_date + 9 THEN
                      'No roster verification marked before ' || to_char(trunc(flc.start_date + 1) - 1 / (24 * 60 * 60) + 8, 'MM/DD/YYYY hh24:mi:ss') || ' for ' || spriden_first_name || ' ' || spriden_last_name || '-' || spriden_id ||
                      '. Student registered for the course on ' || to_char(stcr.sfrstcr_add_date, 'MM/DD/YYYY') || '. Final grades cannot be posted until this gets corrected.'
                     WHEN stcr.sfrstcr_attend_hr IS NULL
                          AND stcr.sfrstcr_add_date >= flc.start_date -- registered AFTER START
                          AND v_etl_date < stcr.sfrstcr_add_date + 7 THEN
                      'Roster verification for ' || spriden_first_name || ' ' || spriden_last_name || '-' || lpad(to_char(spriden_id), 9, 'L00000000') || ' should be completed as soon as possible. Student was added to the course on ' || to_char(stcr.sfrstcr_add_date, 'MM/DD/YYYY') || '. Final grades cannot be posted until this gets completed.'
                     WHEN stcr.sfrstcr_attend_hr IS NULL
                          AND stcr.sfrstcr_add_date >= flc.start_date -- registered AFTER START
                          AND v_etl_date >= stcr.sfrstcr_add_date + 7 THEN
                      'Roster verification for ' || spriden_first_name || ' ' || spriden_last_name || '-' || lpad(to_char(spriden_id), 9, 'L00000000') || ' should be completed as soon as possible. Student was added to the course on ' || to_char(stcr.sfrstcr_add_date, 'MM/DD/YYYY') || '. Final grades cannot be posted until this gets completed.'
                     WHEN stcr.sfrstcr_attend_hr = 0
                          AND v_etl_date >= flc.start_date + 9 THEN
                      'Student marked as not-attended after non-attendance drops that occurred on ' || to_char(flc.start_date + 8, 'MM/DD/YYYY') || ' for ' || spriden_first_name || ' ' || spriden_last_name || '-' || spriden_id ||
                      '. Student registered for the course on ' || to_char(stcr.sfrstcr_add_date, 'MM/DD/YYYY') || '. Final grades cannot be posted until this gets corrected.'
                     END AS compliance_status_reason
                FROM saturn.sfrstcr stcr
              -- we have to use the start dates from far_luo_courses (via lms_link) to get accurate start dates for J term courses
                JOIN utl_d_lms.far_luo_courses flc
                  ON flc.term_code = stcr.sfrstcr_term_code
                 AND flc.crn = stcr.sfrstcr_crn
                JOIN saturn.spriden
                  ON stcr.sfrstcr_pidm = spriden_pidm
                 AND spriden_change_ind IS NULL
              -- ACCOUNT MUST BE CLAIMED
                JOIN general.gobtpac
                  ON gobtpac_pidm = stcr.sfrstcr_pidm
                JOIN saturn.stvrsts rsts
                  ON stcr.sfrstcr_rsts_code = rsts.stvrsts_code
                 AND rsts.stvrsts_incl_sect_enrl = 'Y'
                 AND rsts.stvrsts_withdraw_ind = 'N'
                 AND rsts.stvrsts_incl_assess = 'Y'
               WHERE stcr.sfrstcr_rsts_code <> 'AU'
                 AND CASE
                     WHEN stcr.sfrstcr_attend_hr IS NULL
                          AND stcr.sfrstcr_add_date <= flc.start_date -- registered before START
                          AND v_etl_date < flc.start_date + 9 THEN
                      '1' -- This field will turn yellow if a student has not been verified before the end of first week
                     WHEN stcr.sfrstcr_attend_hr IS NULL
                          AND stcr.sfrstcr_add_date <= flc.start_date -- registered before START
                          AND v_etl_date >= flc.start_date + 9 THEN
                      '2' -- This field will turn red if a student has not been verified after the end of first week
                     WHEN stcr.sfrstcr_attend_hr IS NULL -- NOTHING MARKED YET
                          AND stcr.sfrstcr_add_date >= flc.start_date -- registered AFTER START
                          AND v_etl_date < stcr.sfrstcr_add_date + 7 THEN
                      '1' -- This field will turn yellow if a student has not been verified before the end of first week
                     WHEN stcr.sfrstcr_attend_hr IS NULL -- NOTHING MARKED YET
                          AND stcr.sfrstcr_add_date >= flc.start_date -- registered AFTER START
                          AND v_etl_date >= stcr.sfrstcr_add_date + 7 THEN
                      '1' -- always showing yellow in this situation... if a student has not been verified after the end of first week
                     WHEN stcr.sfrstcr_attend_hr = 0
                          AND v_etl_date >= flc.start_date + 9 THEN
                      '1'
                     END IN ('1','2')
                 AND stcr.sfrstcr_term_code = rec.term_code
                 AND stcr.sfrstcr_ptrm_code = rec.ptrm_code
                 AND stcr.sfrstcr_levl_code NOT IN ('AC', 'K8', 'HS', 'PD')) roster_verification
           ON courses.term_code = roster_verification.term_code
          AND courses.crn = roster_verification.crn
          AND courses.term_code = rec.term_code
          AND courses.ptrm_code = rec.ptrm_code
         LEFT JOIN utl_d_lms.far_luo_audit fla
           ON fla.unique_id = courses.course_section_id || '_' || v_cat_code || roster_verification.compliance_status_code || '_' || lpad(to_char(roster_verification.luid), 9, 'L00000000')
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
v_msg     := 'MERGE - ' || rec.term_code || rec.ptrm_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line('Applying any exclusions for courses in: ' || rec.term_code || rec.ptrm_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ';');
UPDATE utl_d_lms.far_luo_audit fla
   SET fla.deleted_ind              = 'Y',
       fla.compliance_category_code = v_cat_code,
       fla.flag_count               = 0,
       fla.deleted_reason          =
       (SELECT 'Exclusion(s): ' || xl.instructional_method || ' course'
          FROM utl_d_lms.course_exclusions xl
          JOIN utl_d_lms.far_luo_courses flc
            ON flc.crn = xl.crn
           AND flc.term_code = xl.term_code
         WHERE xl.verified_roster = 'Exclude'
           AND xl.term_code = rec.term_code
           AND xl.crn = fla.crn
           AND xl.term_code = fla.term_code)
 WHERE fla.term_code = rec.term_code
   AND fla.ptrm_code = rec.ptrm_code
   AND fla.compliance_category_code = v_cat_code
   AND fla.compliance_status_code IN ('1', '2') -- ONLY YELLOW AND RED FLAGS GET INVALIDATED
   AND fla.deleted_ind = 'N'
   AND EXISTS (SELECT 'Exclusion(s): ' || xl.instructional_method || ' course'
          FROM utl_d_lms.course_exclusions xl
          JOIN utl_d_lms.far_luo_courses flc
            ON flc.crn = xl.crn
           AND flc.term_code = xl.term_code
         WHERE xl.verified_roster = 'Exclude'
           AND xl.term_code = rec.term_code
           AND xl.crn = fla.crn
           AND xl.term_code = fla.term_code);
v_count := v_count + SQL%ROWCOUNT;
COMMIT;
dbms_output.put_line('Expiring records that are no longer active in: ' || rec.term_code || rec.ptrm_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ';');
UPDATE utl_d_lms.far_luo_audit fla
   SET fla.status = 'EXPIRED' -- if the last_modified did NOT get updated on the last run, it is no longer active;
 WHERE fla.compliance_category_code = v_cat_code
   AND fla.term_code = rec.term_code
   AND fla.ptrm_code = rec.ptrm_code
   AND fla.instance = v_instance
   AND fla.status = 'ACTIVE'
   AND ((fla.last_modified < v_etl_date) OR (v_etl_date >= rec.expiration_date)); -- expire records if still active on expiration date
v_count := v_count + SQL%ROWCOUNT;
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'UPDATE - ' || rec.term_code || rec.ptrm_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
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
---      11-05-2020  WGRIFFITH2  --Initial release
---      11-29-2020  WGRIFFITH2  --Adding unique_id
---      01-27-2021  WGRIFFITH2  --Fixing timeframe of when flags occur
---      06-25-2021  WGRIFFITH2  --Now using the RAFT form to track exclusions
---      10-20-2021  WGRIFFITH2  --Adjustment to roster verification column in FAR after drops for non-attendance occur
---      03-28-2022  WGRIFFITH2  --Deprecated Bb code; moved to using the course_section_id instead of section_sis_id
---      06-19-2025  WGRIFFITH2  --Must use the start dates from far_luo_courses (via lms_link) to get accurate start dates for J term courses
---      07-15-2025  WGRIFFITH2  --students added after course start get 7 days for roster verification; yellow flag turns red after 7 days 
------------------------------------------------------------------------------------------------*/
END etl_lms_far_luo_audit_vr;

procedure etl_lms_far_luo_audit_la(jobnumber NUMBER, processid VARCHAR2, processname VARCHAR2) IS
/*
* Purpose:
*    - Looks to see when the Last activity occurred for instructor
* Conditions:
*    -
*/
--DECLARE
--- PARAMS
v_etl_date    DATE := SYSDATE;
v_instance    VARCHAR2(50) := upper('L2CAN'); -- inst from the jams job; used for determining instance
v_partition    NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_msg         VARCHAR2(2000);
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_lms_far_luo_audit_la';
v_cat_code    VARCHAR2(2) := 'LA';
-- CURSOR
CURSOR c_terms IS
SELECT ll.term_code,
       ll.ptrm_code,
       MIN(ll.start_date) AS start_date,
       MAX(ll.end_date) AS end_date,
       MAX(ll.end_date + 7) - 1 AS expiration_date -- leave the minus one; need expirations to occur on last day reports run
  FROM zbtm.terms_by_group_v t
  JOIN utl_d_lms.lms_link ll
    ON ll.term_code = t.term_code
 WHERE 1 = 1
   AND ll.status IN ('active', 'concluded')
   AND ll.enrollment > 0
   AND ll.instance = 'L2CAN'
   AND t.group_code = 'STD'
   AND t.semester <> 'WIN'
   AND ll.ptrm_code IN ('R', '1A', '1B', '1C', '1D', '1J')
   AND SYSDATE BETWEEN ll.start_date - 7 AND ll.end_date + 7 --stop running; ** needs to match expiration date **
 GROUP BY ll.term_code,
          ll.ptrm_code
 ORDER BY end_date DESC;
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
v_msg     := 'START - ' || rec.term_code || rec.ptrm_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
MERGE INTO utl_d_lms.far_luo_audit destination_table
USING (SELECT courses.term_code,
              courses.crn,
              courses.coll_code,
              courses.coll_desc,
              courses.course_code,
              courses.course_sis_id,
              courses.section_sis_id,
              courses.course_id,
              courses.course_section_id,
              'https://libertyuniversity.instructure.com/courses/' || to_char(courses.course_id) || '/users' AS url,
              courses.camp_code,
              courses.ptrm_code,
              courses.insm_code,
              courses.faculty_pidm,
              courses.faculty_name,
              courses.faculty_email,
              v_cat_code compliance_category_code,
              CASE
              WHEN mg.crn IS NULL THEN
               '0' -- FINAL GRADES HAVE BEEN SUBMITTED
              WHEN ceil(v_etl_date - coalesce(last_act.modified_last_activity, courses.start_date)) < 7 THEN
               '0'
              WHEN ceil(v_etl_date - coalesce(last_act.modified_last_activity, courses.start_date)) >= 7 THEN
               '1'
              END compliance_status_code,
              'Last activity was ' || coalesce(to_char(last_act.last_activity, 'MM/DD/YYYY hh24:mi:ss'), 'unknown') AS compliance_status_reason,
              v_etl_date audit_date,
              'N' deleted_ind,
              NULL deleted_reason,
              CASE
              WHEN mg.crn IS NULL THEN
               courses.course_section_id || '_' || v_cat_code || '0' || '_' || to_char(coalesce(last_act.modified_last_activity, courses.start_date), 'YYYYMMDD') -- 20204054321_LA1_YYYYMMDD
              WHEN ceil(v_etl_date - coalesce(last_act.modified_last_activity, courses.start_date)) < 7 THEN
               courses.course_section_id || '_' || v_cat_code || '0' || '_' || to_char(coalesce(last_act.modified_last_activity, courses.start_date), 'YYYYMMDD') -- 20204054321_LA1_YYYYMMDD
              WHEN ceil(v_etl_date - coalesce(last_act.modified_last_activity, courses.start_date)) >= 7 THEN
               courses.course_section_id || '_' || v_cat_code || '1' || '_' || to_char(coalesce(last_act.modified_last_activity, courses.start_date), 'YYYYMMDD') -- 20204054321_LA1_YYYYMMDD
              END AS unique_id,
              CASE
              WHEN mg.crn IS NULL THEN
               0
              WHEN ceil(v_etl_date - coalesce(last_act.modified_last_activity, courses.start_date)) <= 2 THEN
               0
              WHEN fla.deleted_ind = 'Y' THEN
               0
              WHEN fla.course_section_id IS NOT NULL THEN
               ceil(v_etl_date - fla.audit_date)
              ELSE
               1
              END AS flag_count,
              v_etl_date AS last_modified,
              'ACTIVE' AS status,
              courses.instance
         FROM utl_d_lms.far_luo_courses courses
         JOIN (SELECT ll.course_code,
                     ll.course_sis_id,
                     ll.course_section_id,
                     ll.crn,
                     ll.term_code,
                     ll.ptrm_code,
                     fu.first_name || ' ' || fu.last_name AS full_name,
                     fu.user_name AS user_name,
                     ll.instance,
                     MAX(CASE
                         WHEN last_graded_assignment > fu.last_request_date THEN
                          (trunc(last_graded_assignment + 1) - 1 / (24 * 60 * 60) + 0) -- last time a manual grade occurred
                         ELSE
                          (trunc(fu.last_request_date + 1) - 1 / (24 * 60 * 60) + 0) -- last web page view held for more than 2 minutes
                         END) AS modified_last_activity, -- modified to 11:59pm
                     MAX(CASE
                         WHEN last_graded_assignment > fu.last_request_date THEN
                          last_graded_assignment
                         ELSE
                          fu.last_request_date
                         END) AS last_activity,
                     SYSDATE AS activity_date
                FROM utl_d_lms.lms_link ll
                JOIN utl_d_lms.far_luo_courses courses
                  ON courses.course_section_id = ll.course_section_id
                 AND courses.instance = ll.instance
                 AND ll.instance = v_instance
                 AND ll.term_code = rec.term_code
                 AND ll.ptrm_code = rec.ptrm_code
                JOIN utl_d_lms.faculty_users fu
                  ON fu.instance = ll.instance
                 AND fu.pidm = courses.faculty_pidm
                JOIN saturn.sirasgn sirasgn
                  ON sirasgn.sirasgn_term_code = ll.term_code
                 AND sirasgn.sirasgn_crn = ll.crn
                 AND sirasgn.sirasgn_pidm = fu.pidm
                 AND sirasgn.sirasgn_primary_ind = 'Y'
                LEFT JOIN (SELECT MAX(sa.graded_date) AS last_graded_assignment,
                                 sa.instance,
                                 sa.course_section_id
                            FROM utl_d_lms.lms_link ll
                            JOIN utl_d_lms.student_assignments sa
                              ON sa.instance = ll.instance
                             AND sa.course_section_id = ll.course_section_id
                             AND ll.instance = v_instance
                             AND ll.term_code = rec.term_code
                             AND ll.ptrm_code = rec.ptrm_code
                           WHERE 1 = 1
                             AND sa.submitted_date IS NOT NULL
                             AND sa.graded_date IS NOT NULL
                             AND sa.graded_date > SYSDATE - 7
                             AND sa.graded_date > sa.submitted_date + (1 / 24) -- grade has to come in later than the submission to confirm a manually graded assignment
                           GROUP BY sa.instance,
                                    sa.course_section_id) sa
                  ON sa.instance = ll.instance
                 AND sa.course_section_id = ll.course_section_id
               WHERE 1 = 1
               GROUP BY ll.course_code,
                        ll.course_sis_id,
                        ll.course_section_id,
                        ll.crn,
                        ll.term_code,
                        ll.ptrm_code,
                        ll.instance,
                        fu.first_name || ' ' || fu.last_name,
                        fu.user_name) last_act
           ON last_act.course_section_id = courses.course_section_id
          AND last_act.instance = courses.instance
          AND courses.instance = v_instance
         LEFT JOIN (SELECT COUNT(crse.pidm) AS cnt,
                          crse.term_code,
                          crse.crn
                     FROM utl_d_aim.szrcrse crse
                    WHERE 1 = 1
                      AND crse.term_code = rec.term_code
                      AND crse.ptrm_code = rec.ptrm_code
                      AND coalesce(crse.final_grade, 'M') IN ('M')
                    GROUP BY crse.term_code,
                             crse.crn) mg
           ON mg.term_code = courses.term_code
          AND mg.crn = courses.crn
         LEFT JOIN utl_d_lms.far_luo_audit fla
           ON fla.unique_id = CASE
              WHEN mg.crn IS NULL THEN
               courses.course_section_id || '_' || v_cat_code || '0' || '_' || to_char(coalesce(last_act.modified_last_activity, courses.start_date), 'YYYYMMDD') -- 20204054321_LA1_YYYYMMDD
              WHEN ceil(v_etl_date - coalesce(last_act.modified_last_activity, courses.start_date)) <= 2 THEN
               courses.course_section_id || '_' || v_cat_code || '0' || '_' || to_char(coalesce(last_act.modified_last_activity, courses.start_date), 'YYYYMMDD') -- 20204054321_LA1_YYYYMMDD
              WHEN ceil(v_etl_date - coalesce(last_act.modified_last_activity, courses.start_date)) BETWEEN 3 AND 4.99 THEN
               courses.course_section_id || '_' || v_cat_code || '1' || '_' || to_char(coalesce(last_act.modified_last_activity, courses.start_date), 'YYYYMMDD') -- 20204054321_LA1_YYYYMMDD
              WHEN ceil(v_etl_date - coalesce(last_act.modified_last_activity, courses.start_date)) >= 5 THEN
               courses.course_section_id || '_' || v_cat_code || '2' || '_' || to_char(coalesce(last_act.modified_last_activity, courses.start_date), 'YYYYMMDD') -- 20204054321_LA1_YYYYMMDD
              END
          AND audit_date < v_etl_date -- must be less than or the flag count will not work
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
v_msg     := 'MERGE - ' || rec.term_code || rec.ptrm_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line('Applying any exclusions for courses in: ' || rec.term_code || rec.ptrm_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ';');
UPDATE utl_d_lms.far_luo_audit fla
   SET fla.deleted_ind              = 'Y',
       fla.compliance_category_code = v_cat_code,
       fla.flag_count               = 0,
       fla.deleted_reason          =
       (SELECT 'Exclusion(s): ' || xl.instructional_method || ' course'
          FROM utl_d_lms.course_exclusions xl
          JOIN utl_d_lms.far_luo_courses flc
            ON flc.crn = xl.crn
           AND flc.term_code = xl.term_code
         WHERE xl.last_activity = 'Exclude'
           AND xl.term_code = rec.term_code
           AND xl.crn = fla.crn
           AND xl.term_code = fla.term_code)
 WHERE fla.term_code = rec.term_code
   AND fla.ptrm_code = rec.ptrm_code
   AND fla.compliance_category_code = v_cat_code
   AND fla.compliance_status_code IN ('1', '2') -- ONLY YELLOW AND RED FLAGS GET INVALIDATED
   AND fla.deleted_ind = 'N'
   AND EXISTS (SELECT 'Exclusion(s): ' || xl.instructional_method || ' course'
          FROM utl_d_lms.course_exclusions xl
          JOIN utl_d_lms.far_luo_courses flc
            ON flc.crn = xl.crn
           AND flc.term_code = xl.term_code
         WHERE xl.last_activity = 'Exclude'
           AND xl.term_code = rec.term_code
           AND xl.crn = fla.crn
           AND xl.term_code = fla.term_code);
v_count := v_count + SQL%ROWCOUNT;
COMMIT;
dbms_output.put_line('Expiring records that are no longer active in: ' || rec.term_code || rec.ptrm_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ';');
UPDATE utl_d_lms.far_luo_audit fla
   SET fla.status = 'EXPIRED' -- if the last_modified did NOT get updated on the last run, it is no longer active;
 WHERE fla.compliance_category_code = v_cat_code
   AND fla.term_code = rec.term_code
   AND fla.ptrm_code = rec.ptrm_code
   AND fla.instance = v_instance
   AND fla.status = 'ACTIVE'
   AND ((fla.last_modified < v_etl_date) OR (v_etl_date >= rec.expiration_date)); -- expire records if still active on expiration date
v_count := v_count + SQL%ROWCOUNT;
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'UPDATE - ' || rec.term_code || rec.ptrm_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
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
---      11-05-2020  WGRIFFITH2  --Initial release
---      11-29-2020  WGRIFFITH2  --Adding unique_id
---      04-15-2021  WGRIFFITH2  --Changing unique_id
---      06-25-2021  WGRIFFITH2  --Now using the RAFT form to track exclusions
---      07-26-2021  WGRIFFITH2  --Adding a way to fill in the gaps for certain zoct misses
---      03-28-2022  WGRIFFITH2  --Deprecated Bb code; moved to using the course_section_id instead of section_sis_id
---      03-16-2023  WGRIFFITH2  --We will no longer show yellow or red when all final grades have been submitted
---      09-27-2023  WGRIFFITH2  --Adding additional checks for acitvity JIC it is not caught by ps.last_request_at
---      01-06-2025  WGRIFFITH2  --now using the fu.last_request_date field for last activity
---      08-15-2025  WGRIFFITH2  --last activity will not show until course starts and will never go red
------------------------------------------------------------------------------------------------*/
END etl_lms_far_luo_audit_la;
procedure etl_lms_far_luo_audit_gc(jobnumber NUMBER, processid VARCHAR2, processname VARCHAR2) IS
/*
* Purpose:
*    - Looks for assignments graded after 6 days for red flag; day 5 yellow for warning
* Conditions:
*    - Assignments worth more than 0 points
*    - Assignments that have a due date
*/
--DECLARE
--- PARAMS
v_etl_date    DATE := SYSDATE;
v_instance    VARCHAR2(50) := upper('L2CAN'); -- inst from the jams job; used for determining instance
v_partition    NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_msg         VARCHAR2(2000);
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_lms_far_luo_audit_gc';
v_cat_code    VARCHAR2(2) := 'GC';
-- CURSOR
CURSOR c_terms IS
SELECT ll.term_code,
       ll.ptrm_code,
       MIN(ll.start_date) AS start_date,
       MAX(ll.end_date) AS end_date,
       MAX(ll.end_date + 7) - 1 AS expiration_date -- leave the minus one; need expirations to occur on last day reports run
  FROM zbtm.terms_by_group_v t
  JOIN utl_d_lms.lms_link ll
    ON ll.term_code = t.term_code
 WHERE 1 = 1
   AND ll.status IN ('active', 'concluded')
   AND ll.enrollment > 0
   AND ll.instance = 'L2CAN'
   AND t.group_code = 'STD'
   AND t.semester <> 'WIN'
   AND ll.ptrm_code IN ('R', '1A', '1B', '1C', '1D', '1J')
   AND SYSDATE <= (ll.end_date + 7) --stop running; ** needs to match expiration date **
 GROUP BY ll.term_code,
          ll.ptrm_code
 ORDER BY end_date DESC;
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
v_msg     := 'START - ' || rec.term_code || rec.ptrm_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- *** CANVAS Regular Assignments {NON-DB) ***
-- RED FLAGS
MERGE INTO utl_d_lms.far_luo_audit destination_table
USING (SELECT courses.term_code,
              courses.crn,
              courses.coll_code,
              courses.coll_desc,
              courses.course_code,
              courses.course_sis_id,
              courses.section_sis_id,
              courses.course_id,
              courses.course_section_id,
              'https://libertyuniversity.instructure.com/courses/' || courses.course_id || '/gradebook' AS url,
              courses.camp_code,
              courses.ptrm_code,
              courses.insm_code,
              courses.faculty_pidm,
              courses.faculty_name,
              courses.faculty_email,
              v_cat_code compliance_category_code,
              '2' compliance_status_code,
              CASE
              -- SPECIAL CASE - THESE COURSES AND SPECIFIC ASSIGNMENTS ALLOW FOR 10 DAYS AFTER SUBMISSION
              WHEN ll.subj_code || ll.crse_numb IN ('EDUC887', 'EDUC987', 'EDDR98')
                   AND substr(sa.title, 1, 9) = 'Milestone'
                   AND sa.submitted_date IS NOT NULL
                   AND v_etl_date > trunc(sa.submitted_date) - 1 / (24 * 60 * 60) + 10 THEN
               TRIM(to_char(sa.title)) || ' needed grading before: ' || to_char(trunc(sa.submitted_date) - 1 / (24 * 60 * 60) + 10, 'MM/DD/YYYY hh24:mi:ss') || '. Student: ' || su.first_name || ' ' || su.last_name || '-' ||
               lpad(to_char(su.luid), 9, 'L00000000')
              WHEN CAST(sa.submitted_date AS DATE) < sa.due_date
                   AND v_etl_date > trunc(sa.due_date) - 1 / (24 * 60 * 60) + 7 THEN
               TRIM(to_char(sa.title)) || ' needed grading before: ' || to_char(trunc(sa.due_date) - 1 / (24 * 60 * 60) + 7, 'MM/DD/YYYY hh24:mi:ss') || '. Student: ' || su.first_name || ' ' || su.last_name || '-' ||
               lpad(to_char(su.luid), 9, 'L00000000')
              WHEN CAST(sa.submitted_date AS DATE) >= sa.due_date
                   AND v_etl_date > trunc(CAST(sa.submitted_date AS DATE)) - 1 / (24 * 60 * 60) + 7 THEN
               TRIM(to_char(sa.title)) || ' needed grading before: ' || to_char(trunc(sa.submitted_date) - 1 / (24 * 60 * 60) + 7, 'MM/DD/YYYY hh24:mi:ss') || '. Student: ' || su.first_name || ' ' || su.last_name || '-' ||
               lpad(to_char(su.luid), 9, 'L00000000')
              ELSE
               'NEEDS GRADING'
              END AS compliance_status_reason,
              v_etl_date audit_date,
              'N' AS deleted_ind,
              NULL AS deleted_reason,
              ll.course_section_id || '_' || v_cat_code || '2' || '_' || su.luid || '_' || to_char(sa.submission_id) AS unique_id, -- 20204054321_GC2_L2070201_0987654321
              CASE
              WHEN fla.deleted_ind = 'Y' THEN
               0
              WHEN fla.course_section_id IS NOT NULL THEN
               ceil(v_etl_date - fla.audit_date)
              ELSE
               1
              END AS flag_count,
              v_etl_date AS last_modified,
              'ACTIVE' AS status,
              courses.instance
         FROM utl_d_lms.student_assignments sa
         JOIN utl_d_lms.lms_link ll
           ON sa.course_section_id = ll.course_section_id
          AND ll.instance = v_instance
          AND ll.term_code = rec.term_code
          AND ll.ptrm_code = rec.ptrm_code
          AND coalesce(sa.submission_types, 'X') <> 'discussion_topic'
          AND sa.workflow_state IN ('submitted', 'pending_review')
          AND coalesce(sa.points_possible, 0) > 0
         JOIN utl_d_lms.far_luo_courses courses
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
         LEFT JOIN zneedsgrading.submissions_in_review rev
           ON rev.course_sis_id = ll.course_sis_id
          AND rev.submission_id = sa.submission_id
          AND rev.status = 'IN_REVIEW'
          AND rev.expires > SYSDATE
         LEFT JOIN utl_d_lms.far_luo_audit fla
           ON fla.unique_id = ll.course_section_id || '_' || v_cat_code || '2' || '_' || su.luid || '_' || to_char(sa.submission_id)
          AND fla.audit_date < v_etl_date -- must be less than or the flag count will not work
        WHERE 1 = 1
          AND rev.submission_id IS NULL
             -- after 6 days until late grading
          AND CASE
              -- SPECIAL CASE - THESE COURSES AND SPECIFIC ASSIGNMENTS ALLOW FOR 10 DAYS AFTER SUBMISSION
              WHEN ll.subj_code || ll.crse_numb IN ('EDUC887', 'EDUC987', 'EDDR98')
                   AND substr(sa.title, 1, 9) = 'Milestone'
                   AND sa.submitted_date IS NOT NULL
                   AND v_etl_date > trunc(sa.submitted_date) - 1 / (24 * 60 * 60) + 10 THEN
               'LATE'
              WHEN CAST(sa.submitted_date AS DATE) < sa.due_date
                   AND v_etl_date > trunc(sa.due_date) - 1 / (24 * 60 * 60) + 7 THEN
               'LATE'
              WHEN CAST(sa.submitted_date AS DATE) >= sa.due_date
                   AND v_etl_date > trunc(CAST(sa.submitted_date AS DATE)) - 1 / (24 * 60 * 60) + 7 THEN
               'LATE'
              ELSE
               'NEEDS GRADING'
              END = 'LATE') new_records
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
-- *** CANVAS Regular Assignments {NON-DB) ***
-- YELLOW FLAGS
MERGE INTO utl_d_lms.far_luo_audit destination_table
USING (SELECT courses.term_code,
              courses.crn,
              courses.coll_code,
              courses.coll_desc,
              courses.course_code,
              courses.course_sis_id,
              courses.section_sis_id,
              courses.course_id,
              courses.course_section_id,
              'https://libertyuniversity.instructure.com/courses/' || courses.course_id || '/gradebook' AS url,
              courses.camp_code,
              courses.ptrm_code,
              courses.insm_code,
              courses.faculty_pidm,
              courses.faculty_name,
              courses.faculty_email,
              v_cat_code compliance_category_code,
              '1' compliance_status_code,
              CASE
              -- SPECIAL CASE - THESE COURSES AND SPECIFIC ASSIGNMENTS ALLOW FOR 10 DAYS AFTER SUBMISSION
              WHEN ll.subj_code || ll.crse_numb IN ('EDUC887', 'EDUC987', 'EDDR98')
                   AND substr(sa.title, 1, 9) = 'Milestone'
                   AND sa.submitted_date IS NOT NULL
                   AND v_etl_date <= trunc(sa.submitted_date) - 1 / (24 * 60 * 60) + 10
                   AND v_etl_date > trunc(sa.submitted_date) - 1 / (24 * 60 * 60) + 9 THEN
               TRIM(to_char(sa.title)) || ' needed grading before: ' || to_char(trunc(sa.submitted_date) - 1 / (24 * 60 * 60) + 10, 'MM/DD/YYYY hh24:mi:ss') || '. Student: ' || su.first_name || ' ' || su.last_name || '-' ||
               lpad(to_char(su.luid), 9, 'L00000000')
              WHEN CAST(sa.submitted_date AS DATE) < sa.due_date
                   AND v_etl_date <= trunc(sa.due_date) - 1 / (24 * 60 * 60) + 7
                   AND v_etl_date > trunc(sa.due_date) - 1 / (24 * 60 * 60) + 6 THEN
               TRIM(to_char(sa.title)) || ' needs grading before: ' || to_char(trunc(sa.due_date) - 1 / (24 * 60 * 60) + 7, 'MM/DD/YYYY hh24:mi:ss') || '. Student: ' || su.first_name || ' ' || su.last_name || '-' ||
               lpad(to_char(su.luid), 9, 'L00000000')
              WHEN CAST(sa.submitted_date AS DATE) >= sa.due_date
                   AND v_etl_date <= trunc(CAST(sa.submitted_date AS DATE)) - 1 / (24 * 60 * 60) + 7
                   AND v_etl_date > trunc(CAST(sa.submitted_date AS DATE)) - 1 / (24 * 60 * 60) + 6 THEN
               TRIM(to_char(sa.title)) || ' needs grading before: ' || to_char(trunc(sa.submitted_date) - 1 / (24 * 60 * 60) + 7, 'MM/DD/YYYY hh24:mi:ss') || '. Student: ' || su.first_name || ' ' || su.last_name || '-' ||
               lpad(to_char(su.luid), 9, 'L00000000')
              ELSE
               'NEEDS GRADING'
              END AS compliance_status_reason,
              v_etl_date audit_date,
              'N' AS deleted_ind,
              NULL AS deleted_reason,
              ll.course_section_id || '_' || v_cat_code || '1' || '_' || su.luid || '_' || to_char(sa.submission_id) AS unique_id, -- 20204054321_GC2_L2070201_0987654321
              CASE
              WHEN fla.deleted_ind = 'Y' THEN
               0
              WHEN fla.course_section_id IS NOT NULL THEN
               ceil(v_etl_date - fla.audit_date)
              ELSE
               1
              END AS flag_count,
              v_etl_date AS last_modified,
              'ACTIVE' AS status,
              courses.instance
         FROM utl_d_lms.student_assignments sa
         JOIN utl_d_lms.lms_link ll
           ON sa.course_section_id = ll.course_section_id
          AND ll.instance = v_instance
          AND ll.term_code = rec.term_code
          AND ll.ptrm_code = rec.ptrm_code
          AND coalesce(sa.submission_types, 'X') <> 'discussion_topic'
          AND sa.workflow_state IN ('submitted', 'pending_review')
          AND coalesce(sa.points_possible, 0) > 0
         JOIN utl_d_lms.far_luo_courses courses
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
         LEFT JOIN zneedsgrading.submissions_in_review rev
           ON rev.course_sis_id = ll.course_sis_id
          AND rev.submission_id = sa.submission_id
          AND rev.status = 'IN_REVIEW'
          AND rev.expires > SYSDATE
         LEFT JOIN utl_d_lms.far_luo_audit fla
           ON fla.unique_id = ll.course_section_id || '_' || v_cat_code || '1' || '_' || su.luid || '_' || to_char(sa.submission_id)
          AND fla.audit_date < v_etl_date -- must be less than or the flag count will not work
        WHERE 1 = 1
          AND rev.submission_id IS NULL
             -- warning before red flag
          AND CASE
              -- SPECIAL CASE - THESE COURSES AND SPECIFIC ASSIGNMENTS ALLOW FOR 10 DAYS AFTER SUBMISSION
              WHEN ll.subj_code || ll.crse_numb IN ('EDUC887', 'EDUC987', 'EDDR98')
                   AND substr(sa.title, 1, 9) = 'Milestone'
                   AND sa.submitted_date IS NOT NULL
                   AND v_etl_date <= trunc(sa.submitted_date) - 1 / (24 * 60 * 60) + 10
                   AND v_etl_date > trunc(sa.submitted_date) - 1 / (24 * 60 * 60) + 9 THEN
               'CAUTION'
              WHEN CAST(sa.submitted_date AS DATE) < sa.due_date
                   AND v_etl_date <= trunc(sa.due_date) - 1 / (24 * 60 * 60) + 7
                   AND v_etl_date > trunc(sa.due_date) - 1 / (24 * 60 * 60) + 6 THEN
               'CAUTION'
              WHEN CAST(sa.submitted_date AS DATE) >= sa.due_date
                   AND v_etl_date <= trunc(CAST(sa.submitted_date AS DATE)) - 1 / (24 * 60 * 60) + 7
                   AND v_etl_date > trunc(CAST(sa.submitted_date AS DATE)) - 1 / (24 * 60 * 60) + 6 THEN
               'CAUTION'
              ELSE
               'NEEDS GRADING'
              END = 'CAUTION') new_records
ON (destination_table.unique_id = new_records.unique_id)
WHEN MATCHED THEN
UPDATE
   SET destination_table.flag_count               = new_records.flag_count,
       destination_table.compliance_status_reason = new_records.compliance_status_reason,
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
v_count := v_count + SQL%ROWCOUNT;
COMMIT;
-- *** Discussion Board Assignments in CANVAS ***
-- RED FLAGS
MERGE INTO utl_d_lms.far_luo_audit destination_table
USING (SELECT courses.term_code,
              courses.crn,
              courses.coll_code,
              courses.coll_desc,
              courses.course_code,
              courses.course_sis_id,
              courses.section_sis_id,
              courses.course_id,
              courses.course_section_id,
              'https://libertyuniversity.instructure.com/courses/' || courses.course_id || '/gradebook' AS url,
              courses.camp_code,
              courses.ptrm_code,
              courses.insm_code,
              courses.faculty_pidm,
              courses.faculty_name,
              courses.faculty_email,
              v_cat_code compliance_category_code,
              '2' compliance_status_code,
              CASE
              WHEN tw.assignment_id IS NOT NULL
                   AND CAST(sa.submitted_date AS DATE) < tw.due_date -- TWO WEEK DBS; if submitted BEFORE  tw.due_date
                   AND v_etl_date > trunc(CAST(tw.due_date AS DATE)) - 1 / (24 * 60 * 60) + 14 THEN
               'Two Week DB: "' || TRIM(to_char(sa.title)) || '" needed grading before: ' || to_char(trunc(tw.due_date) - 1 / (24 * 60 * 60) + 14, 'MM/DD/YYYY hh24:mi:ss') || '. Student: ' || su.first_name || ' ' || su.last_name || '-' ||
               lpad(to_char(su.luid), 9, 'L00000000')
              WHEN tw.assignment_id IS NOT NULL
                   AND CAST(sa.submitted_date AS DATE) >= tw.due_date -- TWO WEEK DBS; if submitted AFTER tw.due_date
                   AND v_etl_date > trunc(CAST(sa.submitted_date AS DATE)) - 1 / (24 * 60 * 60) + 14 THEN
               'Two Week DB: "' || TRIM(to_char(sa.title)) || '" needed grading before: ' || to_char(trunc(sa.submitted_date) - 1 / (24 * 60 * 60) + 14, 'MM/DD/YYYY hh24:mi:ss') || '. Student: ' || su.first_name || ' ' || su.last_name || '-' ||
               lpad(to_char(su.luid), 9, 'L00000000')
              WHEN tw.assignment_id IS NULL
                   AND CAST(sa.submitted_date AS DATE) < cal.week_end_date -- if submitted BEFORE week_end_date
                   AND v_etl_date > (cal.week_end_date + 1) - 1 / (24 * 60 * 60) + 7 THEN
               TRIM(to_char(sa.title)) || ' needed grading before: ' || to_char((cal.week_end_date + 1) - 1 / (24 * 60 * 60) + 7, 'MM/DD/YYYY hh24:mi:ss') || '. Student: ' || su.first_name || ' ' || su.last_name || '-' ||
               lpad(to_char(su.luid), 9, 'L00000000')
              WHEN tw.assignment_id IS NULL
                   AND CAST(sa.submitted_date AS DATE) >= cal.week_end_date -- if submitted AFTER week_end_date
                   AND v_etl_date > trunc(CAST(sa.submitted_date AS DATE)) - 1 / (24 * 60 * 60) + 7 THEN
               TRIM(to_char(sa.title)) || ' needed grading before: ' || to_char(trunc(sa.submitted_date) - 1 / (24 * 60 * 60) + 7, 'MM/DD/YYYY hh24:mi:ss') || '. Student: ' || su.first_name || ' ' || su.last_name || '-' ||
               lpad(to_char(su.luid), 9, 'L00000000')
              ELSE
               'NEEDS GRADING'
              END AS compliance_status_reason,
              v_etl_date audit_date,
              'N' AS deleted_ind,
              NULL AS deleted_reason,
              ll.course_section_id || '_' || v_cat_code || '2' || '_' || su.luid || '_' || to_char(sa.submission_id) AS unique_id, -- 20204054321_GC2_L2070201_0987654321
              CASE
              WHEN fla.deleted_ind = 'Y' THEN
               0
              WHEN fla.course_section_id IS NOT NULL THEN
               ceil(v_etl_date - fla.audit_date)
              ELSE
               1
              END AS flag_count,
              v_etl_date AS last_modified,
              'ACTIVE' AS status,
              courses.instance
         FROM utl_d_lms.student_assignments sa
         JOIN utl_d_lms.lms_link ll
           ON sa.course_section_id = ll.course_section_id
          AND ll.instance = v_instance
          AND ll.term_code = rec.term_code
          AND ll.ptrm_code = rec.ptrm_code
          AND coalesce(sa.submission_types, 'X') = 'discussion_topic'
          AND sa.workflow_state IN ('submitted', 'pending_review')
          AND coalesce(sa.points_possible, 0) > 0
         JOIN utl_d_lms.far_luo_courses courses
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
         LEFT JOIN zneedsgrading.submissions_in_review rev
           ON rev.course_sis_id = ll.course_sis_id
          AND rev.submission_id = sa.submission_id
          AND rev.status = 'IN_REVIEW'
          AND rev.expires > v_etl_date
         JOIN utl_d_aa.crscalendar cal
           ON cal.crn = ll.crn
          AND cal.term_code = ll.term_code
          AND sa.due_date >= cal.dte
          AND sa.due_date < cal.dte + 1
         LEFT JOIN (SELECT zduebot.course_section_id,
                          zduebot.assignment_id,
                          zduebot.due_date
                     FROM utl_d_lms.zduebot
                    WHERE zduebot.instance = v_instance
                      AND zduebot.term_code = rec.term_code) tw
           ON tw.course_section_id = sa.course_section_id
          AND tw.assignment_id = sa.assignment_id
         LEFT JOIN utl_d_lms.far_luo_audit fla
           ON fla.unique_id = ll.course_section_id || '_' || v_cat_code || '2' || '_' || su.luid || '_' || to_char(sa.submission_id)
          AND fla.audit_date < v_etl_date -- must be less than or the flag count will not work
        WHERE 1 = 1
          AND rev.submission_id IS NULL
             -- after 6 days until late grading
          AND CASE
              WHEN tw.assignment_id IS NOT NULL
                   AND CAST(sa.submitted_date AS DATE) < tw.due_date -- TWO WEEK DBS; if submitted BEFORE  tw.due_date
                   AND v_etl_date > trunc(CAST(tw.due_date AS DATE)) - 1 / (24 * 60 * 60) + 14 THEN
               'LATE'
              WHEN tw.assignment_id IS NOT NULL
                   AND CAST(sa.submitted_date AS DATE) >= tw.due_date -- TWO WEEK DBS; if submitted AFTER tw.due_date
                   AND v_etl_date > trunc(CAST(sa.submitted_date AS DATE)) - 1 / (24 * 60 * 60) + 14 THEN
               'LATE'
              WHEN tw.assignment_id IS NULL
                   AND CAST(sa.submitted_date AS DATE) < cal.week_end_date -- if submitted BEFORE week_end_date
                   AND v_etl_date > (cal.week_end_date + 1) - 1 / (24 * 60 * 60) + 7 THEN
               'LATE'
              WHEN tw.assignment_id IS NULL
                   AND CAST(sa.submitted_date AS DATE) >= cal.week_end_date -- if submitted AFTER week_end_date
                   AND v_etl_date > trunc(CAST(sa.submitted_date AS DATE)) - 1 / (24 * 60 * 60) + 7 THEN
               'LATE'
              ELSE
               'NEEDS GRADING'
              END = 'LATE') new_records
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
v_count := v_count + SQL%ROWCOUNT;
COMMIT;
-- *** Discussion Board Assignments in CANVAS ***
-- YELLOW FLAGS
MERGE INTO utl_d_lms.far_luo_audit destination_table
USING (SELECT courses.term_code,
              courses.crn,
              courses.coll_code,
              courses.coll_desc,
              courses.course_code,
              courses.course_sis_id,
              courses.section_sis_id,
              courses.course_id,
              courses.course_section_id,
              'https://libertyuniversity.instructure.com/courses/' || courses.course_id || '/gradebook' AS url,
              courses.camp_code,
              courses.ptrm_code,
              courses.insm_code,
              courses.faculty_pidm,
              courses.faculty_name,
              courses.faculty_email,
              v_cat_code compliance_category_code,
              '1' compliance_status_code,
              CASE
              WHEN tw.assignment_id IS NOT NULL -- TWO WEEK DBS; if submitted BEFORE week_end_date
                   AND CAST(sa.submitted_date AS DATE) < tw.due_date
                   AND v_etl_date <= trunc(CAST(tw.due_date AS DATE)) - 1 / (24 * 60 * 60) + 14
                   AND v_etl_date > trunc(CAST(tw.due_date AS DATE)) - 1 / (24 * 60 * 60) + 13 THEN
               'Two Week DB: "' || TRIM(to_char(sa.title)) || '" needs grading before: ' || to_char((cal.week_end_date + 1) - 1 / (24 * 60 * 60) + 14, 'MM/DD/YYYY hh24:mi:ss') || '. Student: ' || su.first_name || ' ' || su.last_name || '-' ||
               lpad(to_char(su.luid), 9, 'L00000000')
              WHEN tw.assignment_id IS NOT NULL -- TWO WEEK DBS; if submitted AFTER week_end_date
                   AND CAST(sa.submitted_date AS DATE) >= tw.due_date
                   AND v_etl_date <= trunc(CAST(sa.submitted_date AS DATE)) - 1 / (24 * 60 * 60) + 14
                   AND v_etl_date > trunc(CAST(sa.submitted_date AS DATE)) - 1 / (24 * 60 * 60) + 13 THEN
               'Two Week DB: "' || TRIM(to_char(sa.title)) || '" needs grading before: ' || to_char(trunc(sa.submitted_date) - 1 / (24 * 60 * 60) + 14, 'MM/DD/YYYY hh24:mi:ss') || '. Student: ' || su.first_name || ' ' || su.last_name || '-' ||
               lpad(to_char(su.luid), 9, 'L00000000')
              WHEN tw.assignment_id IS NULL
                   AND CAST(sa.submitted_date AS DATE) < CAST(cal.week_end_date AS DATE)
                   AND v_etl_date <= trunc(CAST(cal.week_end_date AS DATE)) - 1 / (24 * 60 * 60) + 7
                   AND v_etl_date > trunc(CAST(cal.week_end_date AS DATE)) - 1 / (24 * 60 * 60) + 6 THEN
               TRIM(to_char(sa.title)) || ' needs grading before: ' || to_char((cal.week_end_date + 1) - 1 / (24 * 60 * 60) + 7, 'MM/DD/YYYY hh24:mi:ss') || '. Student: ' || su.first_name || ' ' || su.last_name || '-' ||
               lpad(to_char(su.luid), 9, 'L00000000')
              WHEN tw.assignment_id IS NULL
                   AND CAST(sa.submitted_date AS DATE) >= CAST(cal.week_end_date AS DATE)
                   AND v_etl_date <= trunc(CAST(sa.submitted_date AS DATE)) - 1 / (24 * 60 * 60) + 7
                   AND v_etl_date > trunc(CAST(sa.submitted_date AS DATE)) - 1 / (24 * 60 * 60) + 6 THEN
               TRIM(to_char(sa.title)) || ' needs grading before: ' || to_char(trunc(sa.submitted_date) - 1 / (24 * 60 * 60) + 7, 'MM/DD/YYYY hh24:mi:ss') || '. Student: ' || su.first_name || ' ' || su.last_name || '-' ||
               lpad(to_char(su.luid), 9, 'L00000000')
              ELSE
               'NEEDS GRADING'
              END AS compliance_status_reason,
              v_etl_date audit_date,
              'N' AS deleted_ind,
              NULL AS deleted_reason,
              ll.course_section_id || '_' || v_cat_code || '1' || '_' || su.luid || '_' || to_char(sa.submission_id) AS unique_id, -- 20204054321_GC2_L2070201_0987654321
              CASE
              WHEN fla.deleted_ind = 'Y' THEN
               0
              WHEN fla.course_section_id IS NOT NULL THEN
               ceil(v_etl_date - fla.audit_date)
              ELSE
               1
              END AS flag_count,
              v_etl_date AS last_modified,
              'ACTIVE' AS status,
              courses.instance
         FROM utl_d_lms.student_assignments sa
         JOIN utl_d_lms.lms_link ll
           ON sa.course_section_id = ll.course_section_id
          AND ll.instance = v_instance
          AND ll.term_code = rec.term_code
          AND ll.ptrm_code = rec.ptrm_code
          AND coalesce(sa.submission_types, 'X') = 'discussion_topic'
          AND sa.workflow_state IN ('submitted', 'pending_review')
          AND coalesce(sa.points_possible, 0) > 0
         JOIN utl_d_lms.far_luo_courses courses
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
         LEFT JOIN zneedsgrading.submissions_in_review rev
           ON rev.course_sis_id = ll.course_sis_id
          AND rev.submission_id = sa.submission_id
          AND rev.status = 'IN_REVIEW'
          AND rev.expires > v_etl_date
         JOIN utl_d_aa.crscalendar cal
           ON cal.crn = ll.crn
          AND cal.term_code = ll.term_code
          AND sa.due_date >= cal.dte
          AND sa.due_date < cal.dte + 1
         LEFT JOIN (SELECT zduebot.course_section_id,
                          zduebot.assignment_id,
                          zduebot.due_date
                     FROM utl_d_lms.zduebot
                    WHERE zduebot.instance = v_instance
                      AND zduebot.term_code = rec.term_code) tw
           ON tw.course_section_id = sa.course_section_id
          AND tw.assignment_id = sa.assignment_id
         LEFT JOIN utl_d_lms.far_luo_audit fla
           ON fla.unique_id = ll.course_section_id || '_' || v_cat_code || '1' || '_' || su.luid || '_' || to_char(sa.submission_id)
          AND fla.audit_date < v_etl_date -- must be less than or the flag count will not work
        WHERE 1 = 1
          AND rev.submission_id IS NULL
             -- warning before red flag
          AND CASE
              WHEN tw.assignment_id IS NOT NULL -- TWO WEEK DBS; if submitted BEFORE week_end_date
                   AND CAST(sa.submitted_date AS DATE) < CAST(cal.week_end_date AS DATE)
                   AND v_etl_date <= trunc(CAST(cal.week_end_date AS DATE)) - 1 / (24 * 60 * 60) + 14
                   AND v_etl_date > trunc(CAST(cal.week_end_date AS DATE)) - 1 / (24 * 60 * 60) + 13 THEN
               'CAUTION'
              WHEN tw.assignment_id IS NOT NULL -- TWO WEEK DBS; if submitted AFTER week_end_date
                   AND CAST(sa.submitted_date AS DATE) >= CAST(cal.week_end_date AS DATE)
                   AND v_etl_date <= trunc(CAST(sa.submitted_date AS DATE)) - 1 / (24 * 60 * 60) + 14
                   AND v_etl_date > trunc(CAST(sa.submitted_date AS DATE)) - 1 / (24 * 60 * 60) + 13 THEN
               'CAUTION'
              WHEN tw.assignment_id IS NULL
                   AND CAST(sa.submitted_date AS DATE) < CAST(cal.week_end_date AS DATE)
                   AND v_etl_date <= trunc(CAST(cal.week_end_date AS DATE)) - 1 / (24 * 60 * 60) + 7
                   AND v_etl_date > trunc(CAST(cal.week_end_date AS DATE)) - 1 / (24 * 60 * 60) + 6 THEN
               'CAUTION'
              WHEN tw.assignment_id IS NULL
                   AND CAST(sa.submitted_date AS DATE) >= CAST(cal.week_end_date AS DATE)
                   AND v_etl_date <= trunc(CAST(sa.submitted_date AS DATE)) - 1 / (24 * 60 * 60) + 7
                   AND v_etl_date > trunc(CAST(sa.submitted_date AS DATE)) - 1 / (24 * 60 * 60) + 6 THEN
               'CAUTION'
              ELSE
               'NEEDS GRADING'
              END = 'CAUTION') new_records
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
v_count := v_count + SQL%ROWCOUNT;
COMMIT;
-- YELLOW FLAGS for
MERGE INTO utl_d_lms.far_luo_audit destination_table
USING (SELECT courses.term_code,
              courses.crn,
              courses.coll_code,
              courses.coll_desc,
              courses.course_code,
              courses.course_sis_id,
              courses.section_sis_id,
              courses.course_id,
              courses.course_section_id,
              'https://libertyuniversity.instructure.com/courses/' || courses.course_id || '/gradebook' AS url,
              courses.camp_code,
              courses.ptrm_code,
              courses.insm_code,
              courses.faculty_pidm,
              courses.faculty_name,
              courses.faculty_email,
              v_cat_code compliance_category_code,
              '1' compliance_status_code,
              TRIM(to_char(sa.title)) || ' is currently under review for ' || lower(rev.reason_for_review) || ' until ' || to_char(trunc(rev.expires) - 1 / (24 * 60 * 60) + 7, 'MM/DD/YYYY hh24:mi:ss') || '. Student: ' || su.first_name || ' ' ||
              su.last_name || '-' || lpad(to_char(su.luid), 9, 'L00000000') AS compliance_status_reason,
              v_etl_date audit_date,
              'N' AS deleted_ind,
              NULL AS deleted_reason,
              ll.course_section_id || '_' || v_cat_code || '1' || '_' || su.luid || '_' || to_char(sa.submission_id) AS unique_id, -- 20204054321_GC2_L2070201_0987654321
              CASE
              WHEN fla.deleted_ind = 'Y' THEN
               0
              WHEN fla.course_section_id IS NOT NULL THEN
               ceil(v_etl_date - fla.audit_date)
              ELSE
               1
              END AS flag_count,
              v_etl_date AS last_modified,
              'ACTIVE' AS status,
              courses.instance
         FROM utl_d_lms.student_assignments sa
         JOIN utl_d_lms.lms_link ll
           ON sa.course_section_id = ll.course_section_id
          AND ll.instance = v_instance
          AND ll.term_code = rec.term_code
          AND ll.ptrm_code = rec.ptrm_code
          AND coalesce(sa.points_possible, 0) > 0
         JOIN utl_d_lms.far_luo_courses courses
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
         JOIN zneedsgrading.submissions_in_review rev
           ON rev.course_sis_id = ll.course_sis_id
          AND rev.submission_id = sa.submission_id
          AND rev.status = 'IN_REVIEW'
          AND rev.expires > v_etl_date
         LEFT JOIN utl_d_lms.far_luo_audit fla
           ON fla.unique_id = ll.course_section_id || '_' || v_cat_code || '1' || '_' || su.luid || '_' || to_char(sa.submission_id)
          AND fla.audit_date < v_etl_date -- must be less than or the flag count will not work
       ) new_records
ON (destination_table.unique_id = new_records.unique_id)
WHEN MATCHED THEN
UPDATE
   SET destination_table.flag_count               = new_records.flag_count,
       destination_table.compliance_status_reason = new_records.compliance_status_reason,
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
v_count := v_count + SQL%ROWCOUNT;
COMMIT;
v_msg := 'MERGE - ' || rec.term_code || rec.ptrm_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line('Applying any exclusions for courses in: ' || rec.term_code || rec.ptrm_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ';');
UPDATE utl_d_lms.far_luo_audit fla
   SET fla.deleted_ind              = 'Y',
       fla.compliance_category_code = v_cat_code,
       fla.flag_count               = 0,
       fla.deleted_reason          =
       (SELECT 'Exclusion(s): ' || xl.instructional_method || ' course'
          FROM utl_d_lms.course_exclusions xl
          JOIN utl_d_lms.far_luo_courses flc
            ON flc.crn = xl.crn
           AND flc.term_code = xl.term_code
         WHERE xl.grading_compliance = 'Exclude'
           AND xl.term_code = rec.term_code
           AND xl.crn = fla.crn
           AND xl.term_code = fla.term_code)
 WHERE fla.term_code = rec.term_code
   AND fla.ptrm_code = rec.ptrm_code
   AND fla.compliance_category_code = v_cat_code
   AND fla.compliance_status_code IN ('1', '2') -- ONLY YELLOW AND RED FLAGS GET INVALIDATED
   AND fla.deleted_ind = 'N'
   AND EXISTS (SELECT 'Exclusion(s): ' || xl.instructional_method || ' course'
          FROM utl_d_lms.course_exclusions xl
          JOIN utl_d_lms.far_luo_courses flc
            ON flc.crn = xl.crn
           AND flc.term_code = xl.term_code
         WHERE xl.grading_compliance = 'Exclude'
           AND xl.term_code = rec.term_code
           AND xl.crn = fla.crn
           AND xl.term_code = fla.term_code);
v_count := v_count + SQL%ROWCOUNT;
COMMIT;
dbms_output.put_line('Expiring records when FLAG OCCURRED **AFTER** THE GRADE: ' || rec.term_code || rec.ptrm_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ';');
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
          FROM utl_d_lms.far_luo_audit flax
          JOIN utl_d_lms.lms_link ll
            ON ll.course_section_id = flax.course_section_id
           AND ll.instance = flax.instance
          JOIN utl_d_lms.student_assignments sa
            ON sa.instance = flax.instance
           AND sa.term_code = flax.term_code
           AND sa.submission_id = substr(flax.unique_id, instr(flax.unique_id, '_', -1) + 1) -- parse out the submission ID that is in the ref no from the compliance_status_reason
          LEFT JOIN zneedsgrading.submissions_in_review rev
            ON rev.course_sis_id = ll.course_sis_id
           AND rev.submission_id = sa.submission_id
           AND rev.status = 'IN_REVIEW'
           AND rev.expires > SYSDATE
         WHERE flax.compliance_category_code = v_cat_code
           AND rev.submission_id IS NULL
           AND flax.compliance_status_code IN ('1', '2')
           AND flax.term_code = rec.term_code
           AND flax.ptrm_code = rec.ptrm_code
           AND sa.graded_date IS NOT NULL
           AND flax.audit_date >= sa.graded_date
           AND flax.instance = v_instance
           AND flax.unique_id = fla.unique_id);
v_count := v_count + SQL%ROWCOUNT;
COMMIT;
dbms_output.put_line('Expiring records that are no longer active in: ' || rec.term_code || rec.ptrm_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ';');
UPDATE utl_d_lms.far_luo_audit fla
   SET fla.status = 'EXPIRED' -- if the last_modified did NOT get updated on the last run, it is no longer active;
 WHERE fla.compliance_category_code = v_cat_code
   AND fla.term_code = rec.term_code
   AND fla.ptrm_code = rec.ptrm_code
   AND fla.instance = v_instance
   AND fla.status = 'ACTIVE'
   AND ((fla.last_modified < v_etl_date) OR (v_etl_date >= rec.expiration_date)); -- expire records if still active on expiration date
v_count := v_count + SQL%ROWCOUNT;
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'UPDATE - ' || rec.term_code || rec.ptrm_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
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
---      11-05-2020  WGRIFFITH2  --Initial release
---      11-12-2020  WGRIFFITH2  --Adding in ALL records instead of just compliance. Adding in Blackboard data
---      11-29-2020  WGRIFFITH2  --Adding unique_id
---      02-03-2021  WGRIFFITH2  --Expire records that have inaccurate workflow state for grading compliance
---      04-01-2021  WGRIFFITH2  --Adding in a way to invalidate flags when the CD2 feed is stale
---      05-13-2021  WGRIFFITH2  --Adding in the two week DB calculations
---      06-25-2021  WGRIFFITH2  --Now using the RAFT form to track exclusions
---      03-24-2022  WGRIFFITH2  --Bb ist kaputt!
---      12-26-2022  WGRIFFITH2  --now using student_assignments table
---      04-03-2023  WGRIFFITH2  --REST API validation being removed. Now using GraphQL to update the student_assignments table directly.
---      07-26-2023  WGRIFFITH2  --TKT2755526 - Hooking into the zneedsgrading.submissions_in_review to ignore any assignments  on the FAR that are pending review
---      08-14-2024  WGRIFFITH2  --TKT2954919 - Select EDUC courses, milestones are 10 days from submission, the rest are normal
---      11-22-2024  WGRIFFITH2  --TKT3011626 - Replacing zduebot.due_date_metadata (broken) with utl_d_lms.zduebot
---      02-11-2025  WGRIFFITH2  -- now using the zduebot.due_date for accurate grading due dates
------------------------------------------------------------------------------------------------*/
END etl_lms_far_luo_audit_gc;
procedure etl_lms_far_luo_audit_fn(jobnumber NUMBER, processid VARCHAR2, processname VARCHAR2) IS
/*
* Purpose:
*    - Tracks when an FN should be given to a student for inactivity in a course
* Conditions:
*    - student must be registered for the course
*    - yellow: Students reaches 21 days of inactivity in the course
*    - red: Student is not marked with an FN by 11:59PM on day 23 of student inactivity
*    - known issues: If a student re-enters the course and does not submit an assignment immediately it flags the faculty member until the student submits an assignment (these can be removed manually by having an IM submit a ticket).
*/
--DECLARE
--- PARAMS
v_etl_date    DATE := SYSDATE;
v_instance    VARCHAR2(50) := upper('L2CAN'); -- inst from the jams job; used for determining instance
v_partition    NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_msg         VARCHAR2(2000);
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_lms_far_luo_audit_fn';
v_cat_code    VARCHAR2(2) := 'FN';
-- CURSOR
CURSOR c_terms IS
SELECT ll.term_code,
       ll.ptrm_code,
       MIN(ll.start_date) AS start_date,
       MAX(ll.end_date) AS end_date,
       MAX(ll.end_date + 0) - 1 AS expiration_date -- leave the minus one; need expirations to occur on last day reports run
  FROM zbtm.terms_by_group_v t
  JOIN utl_d_lms.lms_link ll
    ON ll.term_code = t.term_code
 WHERE 1 = 1
   AND ll.status IN ('active')
   AND ll.enrollment > 0
   AND ll.instance = 'L2CAN'
   AND t.group_code = 'STD'
   AND t.semester <> 'WIN'
   AND ll.ptrm_code IN ('R', '1A', '1B', '1C', '1D', '1J')
   AND SYSDATE >= ll.start_date - 0 -- start on day 1
   AND SYSDATE <= (ll.end_date + 0) --stop running; ** needs to match expiration date **
 GROUP BY ll.term_code,
          ll.ptrm_code
 ORDER BY end_date DESC;
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
v_msg     := 'START - ' || rec.term_code || rec.ptrm_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
MERGE INTO utl_d_lms.far_luo_audit destination_table
USING (SELECT courses.term_code,
              courses.crn,
              courses.coll_code,
              courses.coll_desc,
              courses.course_code,
              courses.course_sis_id,
              courses.section_sis_id,
              courses.course_id,
              courses.course_section_id,
              'https://libertyuniversity.instructure.com/courses/' || to_char(courses.course_id) || '/external_tools/163054' AS url,
              courses.camp_code,
              courses.ptrm_code,
              courses.insm_code,
              courses.faculty_pidm,
              courses.faculty_name,
              courses.faculty_email,
              v_cat_code AS compliance_category_code,
              CASE
              WHEN floor(v_etl_date - coalesce(last_act.last_activity, courses.start_date)) > 23 THEN
               '2'
              WHEN floor(v_etl_date - coalesce(last_act.last_activity, courses.start_date)) BETWEEN 21 AND 23 THEN
               '1'
              END compliance_status_code,
              CASE
              -- military only
              WHEN szrenrl.milt_status IS NOT NULL
                   AND floor(v_etl_date - coalesce(last_act.last_activity, courses.start_date)) > 23 THEN
               'FN required immediately for ' || szrenrl.first_name || ' ' || szrenrl.last_name || '-' || lpad(to_char(szrenrl.luid), 9, 'L00000000') || ' (Military: ' || substr(szrenrl.milt_status, 3, 50) || ') who has been inactive for ' ||
               floor(v_etl_date - coalesce(last_act.last_activity, courses.start_date)) || ' days. FN grade was due: ' || to_char(coalesce(last_act.last_activity, trunc(courses.start_date) - 1 / (24 * 60 * 60)) + 23, 'MM/DD/YYYY hh24:mi:ss')
              WHEN szrenrl.milt_status IS NOT NULL
                   AND floor(v_etl_date - coalesce(last_act.last_activity, courses.start_date)) BETWEEN 21 AND 23 THEN
               'Submit FN grade before ' || to_char(coalesce(last_act.last_activity, trunc(courses.start_date) - 1 / (24 * 60 * 60)) + 23, 'MM/DD/YYYY hh24:mi:ss') || ' for ' || szrenrl.first_name || ' ' || szrenrl.last_name || '-' ||
               lpad(to_char(szrenrl.luid), 9, 'L00000000') || ' (Military: ' || substr(szrenrl.milt_status, 3, 50) || ') who has been inactive for ' || floor(v_etl_date - coalesce(last_act.last_activity, courses.start_date)) || ' days.'
              -- everyone else
              WHEN floor(v_etl_date - coalesce(last_act.last_activity, courses.start_date)) > 23 THEN
               'FN required immediately for ' || szrenrl.first_name || ' ' || szrenrl.last_name || '-' || lpad(to_char(szrenrl.luid), 9, 'L00000000') || ' who has been inactive for ' ||
               floor(v_etl_date - coalesce(last_act.last_activity, courses.start_date)) || ' days. FN grade was due: ' || to_char(coalesce(last_act.last_activity, trunc(courses.start_date) - 1 / (24 * 60 * 60)) + 23, 'MM/DD/YYYY hh24:mi:ss')
              WHEN floor(v_etl_date - coalesce(last_act.last_activity, courses.start_date)) BETWEEN 21 AND 23 THEN
               'Submit FN grade before ' || to_char(coalesce(last_act.last_activity, trunc(courses.start_date) - 1 / (24 * 60 * 60)) + 23, 'MM/DD/YYYY hh24:mi:ss') || ' for ' || szrenrl.first_name || ' ' || szrenrl.last_name || '-' ||
               lpad(to_char(szrenrl.luid), 9, 'L00000000') || ' who has been inactive for ' || floor(v_etl_date - coalesce(last_act.last_activity, courses.start_date)) || ' days.'
              END compliance_status_reason,
              nvl(fla.audit_date, v_etl_date) audit_date,
              'N' deleted_ind,
              NULL deleted_reason,
              CASE
              WHEN floor(v_etl_date - coalesce(last_act.last_activity, courses.start_date)) > 23 THEN
               courses.course_section_id || '_' || v_cat_code || '2' || '_' || lpad(to_char(szrenrl.luid), 9, 'L00000000') || '_' || to_char(coalesce(last_act.last_activity, courses.start_date), 'YYYYMMDD')
              WHEN floor(v_etl_date - coalesce(last_act.last_activity, courses.start_date)) BETWEEN 21 AND 23 THEN
               courses.course_section_id || '_' || v_cat_code || '1' || '_' || lpad(to_char(szrenrl.luid), 9, 'L00000000') || '_' || to_char(coalesce(last_act.last_activity, courses.start_date), 'YYYYMMDD')
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
         FROM utl_d_lms.far_luo_courses courses
         JOIN (SELECT pidm,
                     term_code,
                     crn,
                     MAX(trunc(last_activity + 1) - 1 / (24 * 60 * 60)) last_activity -- modified to 11:59pm
                FROM (
                      -- CANVAS COURSES INTERNAL ACTIVITY
                      SELECT spriden_pidm AS pidm,
                              ll.crn,
                              ll.term_code,
                              MAX(oct.activity_date) AS last_activity
                        FROM zoctopus.latest_course_activity oct
                        JOIN utl_d_lms.lms_link ll
                          ON ll.course_sis_id = oct.course_sis_id
                         AND ll.term_code = rec.term_code
                         AND ll.ptrm_code = rec.ptrm_code
                         AND ll.instance = v_instance
                        JOIN saturn.spriden
                          ON spriden_id = oct.user_sis_id
                         AND spriden_change_ind IS NULL
                       WHERE activity_source = 'CANVAS'
                       GROUP BY spriden_pidm,
                                 ll.crn,
                                 ll.term_code
                      UNION
                      -- CANVAS COURSES EXTERNAL ACTIVITY
                      SELECT spriden_pidm AS pidm,
                              ll.crn,
                              ll.term_code,
                              MAX(ea.activity_date) AS last_activity
                        FROM zlighthouse.external_activity ea
                        JOIN utl_d_lms.lms_link ll
                          ON ll.term_code || ll.crn = substr(ea.enrollment_id, 1, instr(ea.enrollment_id, '_') - 1)
                         AND ll.term_code = rec.term_code
                         AND ll.ptrm_code = rec.ptrm_code
                         AND ll.instance = v_instance
                        JOIN saturn.spriden
                          ON spriden_id = substr(ea.enrollment_id, instr(ea.enrollment_id, '_') + 1)
                         AND spriden_change_ind IS NULL
                       WHERE ea.deleted = 'N'
                       GROUP BY spriden_pidm,
                                 ll.crn,
                                 ll.term_code
                      UNION
                      -- FN GRADE WAS SUBMITTED ALREADY, BUT USING THIS AS ACTIVITY DATE JIC THERE IS A RE-ENROLL; RESETTING THE CLOCK (MAJOR CHANGE ON 08/06)
                      SELECT spriden_pidm AS pidm,
                              ll.crn,
                              ll.term_code,
                              MAX(coalesce(fnl.grade_date, fnl.activity_date)) AS last_activity -- using the final grade date as their activity
                        FROM utl_d_aa.stufngrade_log fnl
                        JOIN utl_d_lms.lms_link ll
                          ON ll.term_code = fnl.term_code
                         AND ll.crn = fnl.crn
                         AND ll.term_code = rec.term_code
                         AND ll.ptrm_code = rec.ptrm_code
                         AND ll.instance = v_instance
                        JOIN saturn.spriden
                          ON spriden_pidm = fnl.pidm
                         AND spriden_change_ind IS NULL
                       GROUP BY spriden_pidm,
                                 ll.crn,
                                 ll.term_code)
               GROUP BY pidm,
                        term_code,
                        crn) last_act
           ON last_act.crn = courses.crn
          AND last_act.term_code = courses.term_code
         JOIN utl_d_aim.szrenrl
           ON szrenrl.term_code = last_act.term_code
          AND szrenrl.pidm = last_act.pidm
          AND szrenrl.group_code = 'STD' -- standard terms ONLY
         JOIN utl_d_aim.szrcrse crse
           ON crse.term_code = last_act.term_code
          AND crse.crn = last_act.crn
          AND crse.pidm = last_act.pidm
          AND crse.final_grade IS NULL -- normal grades not posted
         JOIN saturn.sfrstcr
           ON sfrstcr_pidm = last_act.pidm
          AND sfrstcr_term_code = last_act.term_code
          AND sfrstcr_crn = last_act.crn
          AND sfrstcr_grde_code IS NULL -- FN grades post here; but does not have fn grade posted
         LEFT JOIN utl_d_lms.far_luo_audit fla
           ON fla.unique_id = CASE
              WHEN floor(v_etl_date - coalesce(last_act.last_activity, courses.start_date)) > 23 THEN
               courses.course_section_id || '_' || v_cat_code || '2' || '_' || lpad(to_char(szrenrl.luid), 9, 'L00000000') || '_' || to_char(coalesce(last_act.last_activity, courses.start_date), 'YYYYMMDD')
              WHEN floor(v_etl_date - coalesce(last_act.last_activity, courses.start_date)) BETWEEN 21 AND 23 THEN
               courses.course_section_id || '_' || v_cat_code || '1' || '_' || lpad(to_char(szrenrl.luid), 9, 'L00000000') || '_' || to_char(coalesce(last_act.last_activity, courses.start_date), 'YYYYMMDD')
              END
          AND fla.audit_date < v_etl_date -- must be less than or the flag count will not work
        WHERE floor(v_etl_date - coalesce(last_act.last_activity, courses.start_date)) >= 21) new_records
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
v_msg     := 'MERGE - ' || rec.term_code || rec.ptrm_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line('Applying any exclusions for courses in: ' || rec.term_code || rec.ptrm_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ';');
UPDATE utl_d_lms.far_luo_audit fla
   SET fla.deleted_ind              = 'Y',
       fla.compliance_category_code = v_cat_code,
       fla.flag_count               = 0,
       fla.deleted_reason          =
       (SELECT 'Exclusion(s): ' || xl.instructional_method || ' course'
          FROM utl_d_lms.course_exclusions xl
          JOIN utl_d_lms.far_luo_courses flc
            ON flc.crn = xl.crn
           AND flc.term_code = xl.term_code
         WHERE xl.fn_compliance = 'Exclude'
           AND xl.term_code = rec.term_code
           AND xl.crn = fla.crn
           AND xl.term_code = fla.term_code)
 WHERE fla.term_code = rec.term_code
   AND fla.ptrm_code = rec.ptrm_code
   AND fla.compliance_category_code = v_cat_code
   AND fla.compliance_status_code IN ('1', '2') -- ONLY YELLOW AND RED FLAGS GET INVALIDATED
   AND fla.deleted_ind = 'N'
   AND EXISTS (SELECT 'Exclusion(s): ' || xl.instructional_method || ' course'
          FROM utl_d_lms.course_exclusions xl
          JOIN utl_d_lms.far_luo_courses flc
            ON flc.crn = xl.crn
           AND flc.term_code = xl.term_code
         WHERE xl.fn_compliance = 'Exclude'
           AND xl.term_code = rec.term_code
           AND xl.crn = fla.crn
           AND xl.term_code = fla.term_code);
v_count := v_count + SQL%ROWCOUNT;
COMMIT;
dbms_output.put_line('Expiring records that are no longer active in: ' || rec.term_code || rec.ptrm_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ';');
UPDATE utl_d_lms.far_luo_audit fla
   SET fla.status = 'EXPIRED' -- if the last_modified did NOT get updated on the last run, it is no longer active;
 WHERE fla.compliance_category_code = v_cat_code
   AND fla.term_code = rec.term_code
   AND fla.ptrm_code = rec.ptrm_code
   AND fla.instance = v_instance
   AND fla.status = 'ACTIVE'
   AND ((fla.last_modified < v_etl_date) OR (v_etl_date >= rec.expiration_date)); -- expire records if still active on expiration date
v_count := v_count + SQL%ROWCOUNT;
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'UPDATE - ' || rec.term_code || rec.ptrm_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
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
---      11-05-2020  WGRIFFITH2  --Initial release
---      11-29-2020  WGRIFFITH2  --Adding unique_id
---      04-15-2021  WGRIFFITH2  --Changing unique_id
---      06-25-2021  WGRIFFITH2  --Now using the RAFT form to track exclusions
---      07-26-2021  WGRIFFITH2  --Adding a way to fill in the gaps for certain zoct misses
---      03-28-2022  WGRIFFITH2  --Deprecated Bb code; moved to using the course_section_id instead of section_sis_id
---      03-10-2023  WGRIFFITH2  --Fixing re-enrolled no activity from student
---      04-27-2023  WGRIFFITH2  --Fixing issue with inactive days not matching MyStudents; updates to the military status in compliance_status_reason
---      02-10-2025  WGRIFFITH2  --Updated this line of code to fix the join ON ll.term_code || ll.crn = substr(ea.enrollment_id, 1, instr(ea.enrollment_id, '_') - 1)
---      08-06-2025  WGRIFFITH2  --Fixed issues with re-enrollment flagging red immediately upon re-enroll
------------------------------------------------------------------------------------------------*/
END etl_lms_far_luo_audit_fn;
procedure etl_lms_far_luo_audit_fg(jobnumber NUMBER, processid VARCHAR2, processname VARCHAR2) IS
/*
* Purpose:
*    - Tracks when final grade compliance
* Conditions:
*    -
*/
--DECLARE
--- PARAMS
v_etl_date    DATE := SYSDATE;
v_instance    VARCHAR2(50) := upper('L2CAN'); -- inst from the jams job; used for determining instance
v_partition    NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_msg         VARCHAR2(2000);
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_lms_far_luo_audit_fg';
v_cat_code    VARCHAR2(2) := 'FG';
-- CURSOR
CURSOR c_terms IS
SELECT ll.term_code,
       ll.ptrm_code,
       MIN(ll.start_date) AS start_date,
       MAX(ll.end_date) AS end_date,
       MAX(ll.end_date + 21) - 1 AS expiration_date -- leave the minus one; need expirations to occur on last day reports run
  FROM zbtm.terms_by_group_v t
  JOIN utl_d_lms.lms_link ll
    ON ll.term_code = t.term_code
 WHERE 1 = 1
   AND ll.status in ('active','concluded')
   AND ll.enrollment > 0
   AND ll.instance = 'L2CAN'
   AND t.group_code = 'STD'
   AND t.semester <> 'WIN'
   AND ll.ptrm_code IN ('R', '1A', '1B', '1C', '1D', '1J')
   AND SYSDATE <= (ll.end_date + 21) --stop running; ** needs to be less than expiration date **
 GROUP BY ll.term_code,
          ll.ptrm_code
 ORDER BY end_date DESC;
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
v_msg     := 'START - ' || rec.term_code || rec.ptrm_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
MERGE INTO utl_d_lms.far_luo_audit destination_table
USING (SELECT courses.term_code,
              courses.crn,
              courses.coll_code,
              courses.coll_desc,
              courses.course_code,
              courses.course_sis_id,
              courses.section_sis_id,
              courses.course_id,
              courses.course_section_id,
              'https://libertyuniversity.instructure.com/courses/' || to_char(courses.course_id) || '/external_tools/163054' AS url,
              courses.camp_code,
              courses.ptrm_code,
              courses.insm_code,
              courses.faculty_pidm,
              courses.faculty_name,
              courses.faculty_email,
              v_cat_code compliance_category_code,
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
         FROM utl_d_lms.far_luo_courses courses
         JOIN (SELECT sfrstcr_term_code term_code,
                     sfrstcr_crn crn,
                     spriden.spriden_id luid,
                     spriden.spriden_pidm pidm,
                     spriden.spriden_first_name || ' ' || spriden.spriden_last_name AS student_name,
                     CASE
                     WHEN coalesce(shrtckg_grde_code_final, sfrstcr_grde_code, 'M') = 'I' -- incompletes show yellow only after 7 days beyond end_date
                          AND v_etl_date >= ssbsect_ptrm_end_date THEN
                      '1'
                     WHEN coalesce(shrtckg_grde_code_final, sfrstcr_grde_code, 'M') = 'M'
                          AND v_etl_date >= ssbsect_ptrm_end_date
                          AND v_etl_date <= ssbsect_ptrm_end_date + 8 THEN
                      '1' -- on day 1 thru 7, NOT all grades turned in after the term = in compliance (warning)
                     WHEN coalesce(shrtckg_grde_code_final, sfrstcr_grde_code, 'M') = 'M'
                          AND v_etl_date > ssbsect_ptrm_end_date + 8 THEN
                      '2' -- after day 7, red
                     WHEN coalesce(shrtckg_grde_code_final, sfrstcr_grde_code, 'M') NOT IN ('M', 'I') THEN
                      '0' -- posted all grades
                     WHEN coalesce(shrtckg_grde_code_final, sfrstcr_grde_code, 'M') IN ('M', 'I') THEN
                      '0' -- still in-progress
                     END status_code,
                     CASE
                     WHEN coalesce(shrtckg_grde_code_final, sfrstcr_grde_code, 'M') = 'I' -- incompletes show yellow only after 7 days beyond end_date
                          AND v_etl_date >= ssbsect_ptrm_end_date THEN
                      'Incomplete grade for ' || spriden.spriden_first_name || ' ' || spriden.spriden_last_name || '-' || lpad(to_char(spriden_id), 9, 'L00000000')
                     WHEN coalesce(shrtckg_grde_code_final, sfrstcr_grde_code, 'M') = 'M'
                          AND v_etl_date >= ssbsect_ptrm_end_date THEN
                      'Missing grade for ' || spriden.spriden_first_name || ' ' || spriden.spriden_last_name || '-' || lpad(to_char(spriden_id), 9, 'L00000000') || '. Final grades due: ' ||
                      to_char(trunc(ssbsect_ptrm_end_date + 1) - 1 / (24 * 60 * 60) + 7, 'MM/DD/YYYY hh24:mi:ss')
                     WHEN coalesce(shrtckg_grde_code_final, sfrstcr_grde_code, 'M') NOT IN ('M', 'I') THEN
                      'Posted final grade (' || coalesce(shrtckg_grde_code_final, sfrstcr_grde_code, 'M') || ') for ' || spriden.spriden_first_name || ' ' || spriden.spriden_last_name || '-' ||
                      lpad(to_char(spriden.spriden_id), 9, 'L00000000') || ' at: ' || to_char(coalesce(shrtckg_final_grde_chg_date, sfrstcr_grde_date), 'MM/DD/YYYY hh24:mi:ss')
                     WHEN coalesce(shrtckg_grde_code_final, sfrstcr_grde_code, 'M') IN ('M', 'I') THEN
                      'Course still in-progress for ' || spriden.spriden_first_name || ' ' || spriden.spriden_last_name || '-' || lpad(to_char(spriden_id), 9, 'L00000000') || '. Final grades due: ' ||
                      to_char(trunc(ssbsect_ptrm_end_date + 1) - 1 / (24 * 60 * 60) + 7, 'MM/DD/YYYY hh24:mi:ss')
                     END status
                FROM saturn.sfrstcr
                JOIN saturn.ssbsect
                  ON ssbsect_crn = sfrstcr_crn
                 AND ssbsect_term_code = sfrstcr_term_code
                 AND sfrstcr_term_code = rec.term_code
                 AND sfrstcr_ptrm_code = rec.ptrm_code
                JOIN saturn.spriden spriden
                  ON spriden.spriden_pidm = sfrstcr_pidm
                 AND spriden.spriden_change_ind IS NULL
                JOIN saturn.stvrsts stvrsts
                  ON stvrsts.stvrsts_code = sfrstcr.sfrstcr_rsts_code
                 AND sfrstcr_rsts_code <> 'AU'
                 AND stvrsts.stvrsts_incl_sect_enrl = 'Y'
                 AND stvrsts.stvrsts_withdraw_ind = 'N'
                 AND stvrsts.stvrsts_incl_assess = 'Y'
                JOIN utl_d_lms.student_users su -- user account must be claimed and have student enrollment type
                  ON su.instance = v_instance
                 AND su.pidm = sfrstcr_pidm
                LEFT JOIN (SELECT shrtckg_grde_code_final             AS shrtckg_grde_code_final,
                                 shrtckn_pidm,
                                 shrtckn_term_code,
                                 shrtckn_crn,
                                 shrtckg.shrtckg_final_grde_chg_date AS shrtckg_final_grde_chg_date
                            FROM saturn.shrtckn
                            JOIN saturn.shrtckg
                              ON shrtckg_pidm = shrtckn_pidm
                             AND shrtckg_term_code = shrtckn_term_code
                             AND shrtckg_tckn_seq_no = shrtckn_seq_no
                             AND shrtckg_seq_no = (SELECT MAX(d.shrtckg_seq_no)
                                                     FROM shrtckg d
                                                    WHERE d.shrtckg_pidm = shrtckg.shrtckg_pidm
                                                      AND d.shrtckg_tckn_seq_no = shrtckg.shrtckg_tckn_seq_no
                                                      AND d.shrtckg_term_code = shrtckg.shrtckg_term_code)
                           WHERE shrtckg_term_code = rec.term_code) shrtckn
                  ON shrtckn_pidm = sfrstcr_pidm
                 AND shrtckn_term_code = sfrstcr_term_code
                 AND shrtckn_crn = sfrstcr_crn
                 AND sfrstcr_term_code = rec.term_code) final_grd
           ON final_grd.term_code = courses.term_code
          AND final_grd.crn = courses.crn
         LEFT JOIN utl_d_lms.far_luo_audit fla
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
v_msg     := 'MERGE - ' || rec.term_code || rec.ptrm_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line('Applying any exclusions for courses in: ' || rec.term_code || rec.ptrm_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ';');
UPDATE utl_d_lms.far_luo_audit fla
   SET fla.deleted_ind              = 'Y',
       fla.compliance_category_code = v_cat_code,
       fla.flag_count               = 0,
       fla.deleted_reason          =
       (SELECT 'Exclusion(s): ' || xl.instructional_method || ' course'
          FROM utl_d_lms.course_exclusions xl
          JOIN utl_d_lms.far_luo_courses flc
            ON flc.crn = xl.crn
           AND flc.term_code = xl.term_code
         WHERE xl.final_grades = 'Exclude'
           AND xl.term_code = rec.term_code
           AND xl.crn = fla.crn
           AND xl.term_code = fla.term_code)
 WHERE fla.term_code = rec.term_code
   AND fla.ptrm_code = rec.ptrm_code
   AND fla.compliance_category_code = v_cat_code
   AND fla.compliance_status_code IN ('1', '2') -- ONLY YELLOW AND RED FLAGS GET INVALIDATED
   AND fla.deleted_ind = 'N'
   AND EXISTS (SELECT 'Exclusion(s): ' || xl.instructional_method || ' course'
          FROM utl_d_lms.course_exclusions xl
          JOIN utl_d_lms.far_luo_courses flc
            ON flc.crn = xl.crn
           AND flc.term_code = xl.term_code
         WHERE xl.final_grades = 'Exclude'
           AND xl.term_code = rec.term_code
           AND xl.crn = fla.crn
           AND xl.term_code = fla.term_code);
v_count := v_count + SQL%ROWCOUNT;
COMMIT;
dbms_output.put_line('Expiring records that are no longer active in: ' || rec.term_code || rec.ptrm_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ';');
UPDATE utl_d_lms.far_luo_audit fla
   SET fla.status = 'EXPIRED' -- if the last_modified did NOT get updated on the last run, it is no longer active;
 WHERE fla.compliance_category_code = v_cat_code
   AND fla.term_code = rec.term_code
   AND fla.ptrm_code = rec.ptrm_code
   AND fla.instance = v_instance
   AND fla.status = 'ACTIVE'
   AND ((fla.last_modified < v_etl_date) OR (v_etl_date >= rec.expiration_date)); -- expire records if still active on expiration date
v_count := v_count + SQL%ROWCOUNT;
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'UPDATE - ' || rec.term_code || rec.ptrm_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
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
---      11-05-2020  WGRIFFITH2  --Initial release
---      11-29-2020  WGRIFFITH2  --Adding unique_id
---      04-29-2020  WGRIFFITH2  --Update to how the final grades show for incompletes. Yellow after end_date + 7
---      05-28-2020  WGRIFFITH2  --Final grades now using shrtckn table
---      06-25-2021  WGRIFFITH2  --Now using the RAFT form to track exclusions
---      03-28-2022  WGRIFFITH2  --Deprecated Bb code; moved to using the course_section_id instead of section_sis_id
---      04-24-2023  WGRIFFITH2  -- Adding JOIN utl_d_lms.student_users su -- user account must be claimed and have student enrollment type
------------------------------------------------------------------------------------------------*/
END etl_lms_far_luo_audit_fg;
procedure etl_lms_far_luo_audit_an(jobnumber NUMBER, processid VARCHAR2, processname VARCHAR2) IS
/*
* Purpose:
*     - Looks for sections in which the prof did not post an announcement this week.
*     - A prof can post an announcement as early as the Sunday before the week starts, and no later than Wed.
* Conditions:
*    - The announcement cannot be one of the default announcements in the LUO_Announcements course
*/
--DECLARE
--- PARAMS
v_etl_date    DATE := SYSDATE;
v_instance    VARCHAR2(50) := upper('L2CAN'); -- inst from the jams job; used for determining instance
v_partition    NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_msg         VARCHAR2(2000);
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_lms_far_luo_audit_an';
v_cat_code    VARCHAR2(2) := 'AN';
-- CURSOR
CURSOR c_terms IS
SELECT ll.term_code,
       ll.ptrm_code,
       MIN(ll.start_date) AS start_date,
       MAX(ll.end_date) AS end_date,
       MAX(ll.end_date + 0) - 1 AS expiration_date -- leave the minus one; need expirations to occur on last day reports run
  FROM zbtm.terms_by_group_v t
  JOIN utl_d_lms.lms_link ll
    ON ll.term_code = t.term_code
 WHERE 1 = 1
   AND ll.status IN ('active', 'concluded')
   AND ll.enrollment > 0
   AND ll.instance = 'L2CAN'
   AND t.group_code = 'STD'
   AND t.semester <> 'WIN'
   AND ll.ptrm_code IN ('R', '1A', '1B', '1C', '1D', '1J')
   AND SYSDATE <= (ll.end_date + 0) --stop running; ** needs to be less than expiration date **
 GROUP BY ll.term_code,
          ll.ptrm_code
 ORDER BY MIN(ll.start_date),
          ll.ptrm_code;
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
v_msg     := 'START - ' || rec.term_code || rec.ptrm_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
MERGE /*+ USE_MERGE(courses ll) USE_NL(ann) */
INTO utl_d_lms.far_luo_audit destination_table
USING (SELECT /*+ LEADING(courses ll) USE_NL(ann) */
        courses.term_code,
        courses.crn,
        courses.coll_code,
        courses.coll_desc,
        courses.course_code,
        courses.course_sis_id,
        courses.section_sis_id,
        courses.course_id,
        courses.course_section_id,
        'https://libertyuniversity.instructure.com/courses/' || to_char(courses.course_id) || '/announcements' AS url,
        courses.camp_code,
        courses.ptrm_code,
        courses.insm_code,
        courses.faculty_pidm,
        courses.faculty_name,
        courses.faculty_email,
        v_cat_code compliance_category_code,
        CASE
        WHEN posted_date IS NOT NULL
             AND days_since < 8 THEN
         '0'
        WHEN posted_date IS NULL
             AND days_since <= 8 THEN -- week 1 and still not posted
         '1'
        WHEN days_since <= 8 THEN
         '1'
        WHEN days_since IN (8, 15, 22) THEN
         '1'
        WHEN days_since > 8 THEN
         '2'
        END AS compliance_status_code,
        CASE
        WHEN posted_date IS NOT NULL
             AND days_since < 8 THEN -- show announcement(s) if posted
         '"' || TRIM(ann.title) || '" was posted at: ' || to_char(posted_date, 'MM/DD/YYYY hh24:mi:ss')
        WHEN posted_date IS NULL
             AND created_date IS NOT NULL
             AND days_since <= 8 THEN -- created but not posted in the last 7 days
         '"' || TRIM(ann.title) || '" was created at: ' || to_char(created_date, 'MM/DD/YYYY hh24:mi:ss') || ' but the delayed posted date must be set on any preloaded announcement'
        WHEN days_since <= 8 THEN -- not created or posted in the last 7 days
         'No announcements found in the last 7 days. Please post an announcement today'
        WHEN posted_date IS NULL
             AND created_date IS NOT NULL
             AND days_since > 8 THEN -- created but not posted in the last 7 days
         '"' || TRIM(ann.title) || '" was created at: ' || to_char(created_date, 'MM/DD/YYYY hh24:mi:ss') || ' but the delayed posted date must be set on any preloaded announcement'
        WHEN days_since > 8
             AND days_since <= 15 THEN
         'Announcement was needed prior to: ' || to_char(posted_date_plus7, 'MM/DD/YYYY hh24:mi:ss') || '. Please post an announcement today'
        WHEN days_since > 15
             AND days_since <= 22 THEN
         'Announcement was needed prior to: ' || to_char(posted_date_plus14, 'MM/DD/YYYY hh24:mi:ss') || '. Please post an announcement today'
        WHEN days_since > 22 THEN
         'Announcement was needed prior to: ' || to_char(posted_date_plus21, 'MM/DD/YYYY hh24:mi:ss') || '. Please post an announcement today'
        END AS compliance_status_reason,
        v_etl_date audit_date,
        'N' deleted_ind,
        NULL deleted_reason,
        CASE
        WHEN posted_date IS NOT NULL
             AND days_since < 8 THEN
         courses.course_section_id || '_' || v_cat_code || '0' || '_' || ann.announcement_id
        WHEN days_since <= 8 THEN
         courses.course_section_id || '_' || v_cat_code || '1' || '_' || to_char(posted_date_plus7, 'YYYYMMDD')
        WHEN days_since > 8
             AND days_since < 15 THEN
         courses.course_section_id || '_' || v_cat_code || '2' || '_' || to_char(posted_date_plus7, 'YYYYMMDD')
        WHEN days_since = 15 THEN
         courses.course_section_id || '_' || v_cat_code || '1' || '_' || to_char(posted_date_plus14, 'YYYYMMDD')
        WHEN days_since > 15
             AND days_since < 22 THEN
         courses.course_section_id || '_' || v_cat_code || '2' || '_' || to_char(posted_date_plus14, 'YYYYMMDD')
        WHEN days_since = 22 THEN
         courses.course_section_id || '_' || v_cat_code || '1' || '_' || to_char(posted_date_plus21, 'YYYYMMDD')
        WHEN days_since > 22 THEN
         courses.course_section_id || '_' || v_cat_code || '2' || '_' || to_char(posted_date_plus21, 'YYYYMMDD')
        END AS unique_id, -- every seven days no announcement is posted, a new ID is created
        CASE
        WHEN fla.deleted_ind = 'Y' THEN
         0
        WHEN posted_date IS NOT NULL
             AND days_since < 8 THEN
         0
        WHEN fla.course_section_id IS NOT NULL THEN
         ceil(v_etl_date - coalesce(fla.audit_date, v_etl_date - 1 / 24)) -- coalesce is for the first record entry
        ELSE
         1
        END AS flag_count,
        v_etl_date AS last_modified,
        'ACTIVE' AS status,
        courses.instance,
        days_since
         FROM utl_d_lms.far_luo_courses courses
         JOIN utl_d_lms.lms_link ll
           ON ll.course_section_id = courses.course_section_id
          AND ll.instance = courses.instance
          AND courses.instance = v_instance
          AND courses.term_code = rec.term_code
          AND courses.ptrm_code = rec.ptrm_code
         JOIN (SELECT courses.course_section_id, -- this join has all active courses in it
                     courses.course_id,
                     courses.instance,
                     ann.title,
                     ann.announcement_id,
                     -- pulls the most recent announcement
                     rank() over(PARTITION BY courses.course_section_id, courses.instance ORDER BY coalesce(ann.delayed_posted_date, ann.posted_date) DESC NULLS LAST, ann.position DESC, ann.created_date DESC, ann.announcement_id DESC) AS ranking,
                     ann.created_date,
                     coalesce(ann.delayed_posted_date, ann.posted_date) AS posted_date,
                     CASE
                     WHEN ann.created_date IS NOT NULL
                          AND coalesce(ann.delayed_posted_date, ann.posted_date) < courses.start_date THEN -- posted before start, so count starts on start date
                      trunc(courses.start_date + 1) - 1 / (24 * 60 * 60) + 8
                     ELSE
                      trunc(coalesce(ann.delayed_posted_date, ann.posted_date, courses.start_date - 8) + 1) - 1 / (24 * 60 * 60) + 8
                     END AS posted_date_plus7, -- next announcement due
                     CASE
                     WHEN ann.created_date IS NOT NULL
                          AND coalesce(ann.delayed_posted_date, ann.posted_date) < courses.start_date THEN -- posted before start, so count starts on start date
                      trunc(courses.start_date + 1) - 1 / (24 * 60 * 60) + 15
                     ELSE
                      trunc(coalesce(ann.delayed_posted_date, ann.posted_date, courses.start_date - 8) + 1) - 1 / (24 * 60 * 60) + 15
                     END AS posted_date_plus14, -- next announcement due
                     CASE
                     WHEN ann.created_date IS NOT NULL
                          AND coalesce(ann.delayed_posted_date, ann.posted_date) < courses.start_date THEN -- posted before start, so count starts on start date
                      trunc(courses.start_date + 1) - 1 / (24 * 60 * 60) + 22
                     ELSE
                      trunc(coalesce(ann.delayed_posted_date, ann.posted_date, courses.start_date - 8) + 1) - 1 / (24 * 60 * 60) + 22
                     END AS posted_date_plus21, -- next announcement due
                     CASE
                     WHEN ann.created_date IS NOT NULL
                          AND coalesce(ann.delayed_posted_date, ann.posted_date) < courses.start_date THEN -- posted before start, so count starts on start date
                      ceil(SYSDATE - (trunc(trunc(courses.start_date + 1) - 1 / (24 * 60 * 60) + 8 + 1) - 1 / (24 * 60 * 60)))
                     ELSE
                      ceil(SYSDATE - (trunc(coalesce(ann.delayed_posted_date, ann.posted_date, courses.start_date - 8) + 1) - 1 / (24 * 60 * 60)))
                     END AS days_since
                FROM utl_d_lms.far_luo_courses courses
                LEFT JOIN utl_d_lms.announcements ann -- using utl_d_lms.announcements table for optimization and api validation
                  ON courses.course_section_id = ann.course_section_id
                 AND courses.instance = ann.instance
                 AND coalesce(ann.delayed_posted_date, ann.posted_date, ann.created_date) < trunc(v_etl_date) - 1 / (24 * 60 * 60) + 1 -- time when students see the announcement
               WHERE courses.instance = v_instance
                 AND courses.term_code = rec.term_code
                 AND courses.ptrm_code = rec.ptrm_code) ann
           ON ann.course_section_id = courses.course_section_id
          AND ann.instance = courses.instance
          AND ann.ranking = 1
         LEFT JOIN utl_d_lms.far_luo_audit fla
           ON fla.unique_id = CASE
              WHEN posted_date IS NOT NULL
                   AND days_since < 8 THEN
               courses.course_section_id || '_' || v_cat_code || '0' || '_' || ann.announcement_id
              WHEN days_since <= 8 THEN
               courses.course_section_id || '_' || v_cat_code || '1' || '_' || to_char(posted_date_plus7, 'YYYYMMDD')
              WHEN days_since > 8
                   AND days_since < 15 THEN
               courses.course_section_id || '_' || v_cat_code || '2' || '_' || to_char(posted_date_plus7, 'YYYYMMDD')
              WHEN days_since = 15 THEN
               courses.course_section_id || '_' || v_cat_code || '1' || '_' || to_char(posted_date_plus14, 'YYYYMMDD')
              WHEN days_since > 15
                   AND days_since < 22 THEN
               courses.course_section_id || '_' || v_cat_code || '2' || '_' || to_char(posted_date_plus14, 'YYYYMMDD')
              WHEN days_since = 22 THEN
               courses.course_section_id || '_' || v_cat_code || '1' || '_' || to_char(posted_date_plus21, 'YYYYMMDD')
              WHEN days_since > 22 THEN
               courses.course_section_id || '_' || v_cat_code || '2' || '_' || to_char(posted_date_plus21, 'YYYYMMDD')
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
v_msg     := 'MERGE - ' || rec.term_code || rec.ptrm_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line('Applying any exclusions for courses in: ' || rec.term_code || rec.ptrm_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ';');
UPDATE utl_d_lms.far_luo_audit fla
   SET fla.deleted_ind              = 'Y',
       fla.compliance_category_code = v_cat_code,
       fla.flag_count               = 0,
       fla.deleted_reason          =
       (SELECT 'Exclusion(s): ' || xl.instructional_method || ' course'
          FROM utl_d_lms.course_exclusions xl
          JOIN utl_d_lms.far_luo_courses flc
            ON flc.crn = xl.crn
           AND flc.term_code = xl.term_code
           AND flc.instance = v_instance
         WHERE xl.announcements = 'Exclude'
           AND xl.term_code = rec.term_code
           AND xl.crn = fla.crn
           AND xl.term_code = fla.term_code)
 WHERE fla.term_code = rec.term_code
   AND fla.ptrm_code = rec.ptrm_code
   AND fla.compliance_category_code = v_cat_code
   AND fla.compliance_status_code IN ('1', '2') -- ONLY YELLOW AND RED FLAGS GET INVALIDATED
   AND fla.deleted_ind = 'N'
   AND EXISTS (SELECT 'Exclusion(s): ' || xl.instructional_method || ' course'
          FROM utl_d_lms.course_exclusions xl
          JOIN utl_d_lms.far_luo_courses flc
            ON flc.crn = xl.crn
           AND flc.term_code = xl.term_code
           AND flc.instance = v_instance
         WHERE xl.announcements = 'Exclude'
           AND xl.term_code = rec.term_code
           AND xl.crn = fla.crn
           AND xl.term_code = fla.term_code);
v_count := v_count + SQL%ROWCOUNT;
COMMIT;
dbms_output.put_line('Expiring records that are no longer active in: ' || rec.term_code || rec.ptrm_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ';');
UPDATE utl_d_lms.far_luo_audit fla
   SET fla.status = 'EXPIRED' -- if the last_modified did NOT get updated on the last run, it is no longer active;
 WHERE fla.compliance_category_code = v_cat_code
   AND fla.term_code = rec.term_code
   AND fla.ptrm_code = rec.ptrm_code
   AND fla.instance = v_instance
   AND fla.status = 'ACTIVE'
   AND ((fla.last_modified < v_etl_date) OR (v_etl_date >= rec.expiration_date)); -- expire records if still active on expiration date
v_count := v_count + SQL%ROWCOUNT;
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'UPDATE - ' || rec.term_code || rec.ptrm_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
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
---      11-05-2020  WGRIFFITH2  --Initial release
---      11-29-2020  WGRIFFITH2  --Adding unique_id
---      04-15-2021  WGRIFFITH2  --Changing unique_id
---      06-25-2021  WGRIFFITH2  --Now using the RAFT form to track exclusions
---      07-26-2021  WGRIFFITH2  --Adding a way to fill in the gaps for certain zoct misses
---      03-28-2022  WGRIFFITH2  --Deprecated Bb code; moved to using the course_section_id instead of section_sis_id
---      12-24-2022  WGRIFFITH2  --etl_announcements proc moved here - it is only used for the FAR
---      03-28-2023  WGRIFFITH2  --Update to how the proc works with REST API validation
---      04-07-2023  WGRIFFITH2  --Update to how the proc works with REST API validation
---      05-11-2023  WGRIFFITH2  --Adding a rolling 7 day regular reset in case the Argos tool was used. up to 21 days after the last announcement was made
---      05-18-2023  WGRIFFITH2  --Fixed ranking. It was incorrectly sorting the best announcement to return when there were imported announcements
---      08-01-2025  WGRIFFITH2  --Adjusting timing to fix a problem with flags appearing a day too early
---      08-11-2025  WGRIFFITH2  --Used optimizer hints for faster large joins
------------------------------------------------------------------------------------------------*/
END etl_lms_far_luo_audit_an;

procedure etl_lms_far_luo_courses(jobnumber NUMBER, processid VARCHAR2, processname VARCHAR2) IS
--DECLARE
--- PARAMS
v_etl_date    DATE := SYSDATE;
v_instance    VARCHAR2(50) := upper('L2CAN'); -- inst from the jams job; used for determining instance
v_partition    NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_msg         VARCHAR2(2000);
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_lms_far_luo_courses';
-- CURSOR
CURSOR c_terms IS
SELECT ll.term_code,
       ll.ptrm_code,
       MIN(ll.start_date) AS start_date,
       MAX(ll.end_date) AS end_date,
       MAX(ll.end_date + 21) - 1 AS expiration_date -- leave the minus one; need expirations to occur on last day reports run
  FROM zbtm.terms_by_group_v t
  JOIN utl_d_lms.lms_link ll
    ON ll.term_code = t.term_code
 WHERE 1 = 1
   AND ll.status IN ('active', 'concluded')
   AND ll.enrollment > 0
   AND ll.instance = 'L2CAN'
   AND t.group_code = 'STD'
   AND t.semester <> 'WIN'
   AND ll.ptrm_code IN ('R', '1A', '1B', '1C', '1D', '1J')
   AND SYSDATE <= (ll.end_date + 21) --stop running;
 GROUP BY ll.term_code,
          ll.ptrm_code
 ORDER BY start_date DESC;
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
v_msg     := 'START - ' || rec.term_code || rec.ptrm_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
IF rec.ptrm_code IN ('R', '1A', '1B', '1C', '1D') THEN
-- MUST BE A MERGE TO ENSURE CONSTANT UP-TIME IN DASHBOARD
MERGE INTO utl_d_lms.far_luo_courses destination_table
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
              'https://libertyuniversity.instructure.com/courses/' || to_char(ll.course_id) AS url,
              ll.camp_code,
              ll.insm_code,
              spriden_pidm AS faculty_pidm,
              spriden_last_name || ', ' || spriden_first_name AS faculty_name,
              prof_emal.email_address AS faculty_email,
              ll.instance,
              act_reg.cnt AS enrollment,
              ll.start_date,
              ll.end_date,
              v_etl_date AS activity_date,
              instructional_method AS exclusions
         FROM utl_d_lms.lms_link ll
         JOIN zsaturn.szrlevl l
           ON l.szrlevl_levl_code = ll.levl_code
          AND l.szrlevl_has_awardable_cred = 'Y' -- remove EM          
         JOIN saturn.ssbsect
           ON ssbsect_crn = ll.crn
          AND ssbsect_term_code = ll.term_code
          AND ll.term_code = rec.term_code
          AND ll.ptrm_code = rec.ptrm_code
          AND ll.instance = v_instance
          AND ll.status IN ('active', 'concluded')
		  AND ll.course_section_id IS NOT NULL -- ensure LMS connection before allow records through
             -- online instruction only
          AND (ssbsect.ssbsect_camp_code = 'D' OR (ssbsect.ssbsect_camp_code = 'R' AND ssbsect_insm_code = 'ON' AND ssbsect.ssbsect_subj_code IN ('INQR', 'RSCH', 'UNIV')))
          AND ssbsect_subj_code NOT IN ('CSER', 'CAFE', 'SFME', 'FRSM', 'NEWS', 'NSSR')
         JOIN (SELECT sfrstcr.sfrstcr_crn crn,
                     sfrstcr.sfrstcr_term_code term_code,
                     COUNT(DISTINCT sfrstcr_pidm) cnt
                FROM saturn.sfrstcr sfrstcr
                JOIN saturn.stvrsts stvrsts
                  ON stvrsts.stvrsts_code = sfrstcr.sfrstcr_rsts_code
                 AND sfrstcr.sfrstcr_levl_code NOT IN ('PD', 'AC')
                 AND sfrstcr_rsts_code <> 'AU'
                 AND stvrsts.stvrsts_incl_sect_enrl = 'Y'
                 AND stvrsts.stvrsts_withdraw_ind = 'N'
                 AND stvrsts.stvrsts_incl_assess = 'Y'
                 AND sfrstcr_term_code = rec.term_code
                 AND sfrstcr_ptrm_code = rec.ptrm_code
               GROUP BY sfrstcr.sfrstcr_crn,
                        sfrstcr.sfrstcr_term_code) act_reg
           ON act_reg.crn = ssbsect.ssbsect_crn
          AND act_reg.term_code = ssbsect.ssbsect_term_code
         JOIN saturn.sirasgn sir
           ON sir.sirasgn_crn = ll.crn
          AND sir.sirasgn_term_code = ll.term_code
          AND sir.sirasgn_primary_ind = 'Y'
         JOIN saturn.spriden
           ON spriden_pidm = sir.sirasgn_pidm
          AND spriden_change_ind IS NULL
          AND spriden_pidm NOT IN (3248979) --exclude To Be Announced
         LEFT JOIN zexec.zsavemal prof_emal
           ON prof_emal.pidm = sir.sirasgn_pidm
          AND prof_emal.emal_code = 'LU'
          AND prof_emal.emal_code_rank = 1
         LEFT JOIN saturn.stvcoll
           ON stvcoll_code = ll.coll_code
       -- EXCLUSIONS
         LEFT JOIN (SELECT ce.crn,
                          ce.term_code,
                          ce.instructional_method
                     FROM utl_d_lms.course_exclusions ce
                    WHERE ce.term_code = rec.term_code) xl
           ON xl.crn = ll.crn
          AND xl.term_code = ll.term_code) new_records
ON (destination_table.course_section_id = new_records.course_section_id AND destination_table.instance = new_records.instance)
WHEN MATCHED THEN
UPDATE
   SET destination_table.ptrm_code      = new_records.ptrm_code,
       destination_table.coll_code      = new_records.coll_code,
       destination_table.coll_desc      = new_records.coll_desc,
       destination_table.course         = new_records.course,
       destination_table.course_code    = new_records.course_code,
       destination_table.course_sis_id  = new_records.course_sis_id,
       destination_table.section_sis_id = new_records.section_sis_id,
       destination_table.course_id      = new_records.course_id,
       destination_table.url            = new_records.url,
       destination_table.camp_code      = new_records.camp_code,
       destination_table.insm_code      = new_records.insm_code,
       destination_table.faculty_pidm   = new_records.faculty_pidm,
       destination_table.faculty_name   = new_records.faculty_name,
       destination_table.faculty_email  = new_records.faculty_email,
       destination_table.enrollment     = new_records.enrollment,
       destination_table.start_date     = new_records.start_date,
       destination_table.end_date       = new_records.end_date,
       destination_table.activity_date  = v_etl_date,
       destination_table.exclusions     = new_records.exclusions
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
 camp_code,
 insm_code,
 faculty_pidm,
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
 new_records.camp_code,
 new_records.insm_code,
 new_records.faculty_pidm,
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
v_msg     := 'MERGE - ' || rec.term_code || rec.ptrm_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
ELSIF rec.ptrm_code IN ('1J') THEN
-- MUST BE A MERGE TO ENSURE CONSTANT UP-TIME IN DASHBOARD
MERGE INTO utl_d_lms.far_luo_courses destination_table
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
              'https://libertyuniversity.instructure.com/courses/' || to_char(ll.course_id) AS url,
              ll.camp_code,
              ll.insm_code,
              spriden_pidm AS faculty_pidm,
              spriden_last_name || ', ' || spriden_first_name AS faculty_name,
              prof_emal.email_address AS faculty_email,
              ll.instance,
              act_reg.cnt AS enrollment,
              ll.start_date,
              ll.end_date,
              v_etl_date AS activity_date,
              instructional_method AS exclusions
         FROM utl_d_lms.lms_link ll
         JOIN zsaturn.szrlevl l
           ON l.szrlevl_levl_code = ll.levl_code
          AND l.szrlevl_has_awardable_cred = 'Y' -- remove EM
         JOIN saturn.ssbsect
           ON ssbsect_crn = ll.crn
          AND ssbsect_term_code = ll.term_code
          AND ll.term_code = rec.term_code
          AND ll.ptrm_code = rec.ptrm_code -- ** 1J PTRM ONLY **
          AND ll.instance = v_instance
          AND ll.status IN ('active', 'concluded')
		  AND ll.course_section_id IS NOT NULL -- ensure LMS connection before allow records through
             -- online instruction only
          AND (ssbsect.ssbsect_camp_code = 'D' AND ssbsect.ssbsect_subj_code IN ('BMAL', 'BUSI', 'COUC'))
          AND ssbsect_subj_code NOT IN ('CSER', 'CAFE', 'SFME', 'FRSM', 'NEWS', 'NSSR')
         JOIN (SELECT sfrstcr.sfrstcr_crn crn,
                     sfrstcr.sfrstcr_term_code term_code,
                     COUNT(DISTINCT sfrstcr_pidm) cnt
                FROM saturn.sfrstcr sfrstcr
                JOIN saturn.stvrsts stvrsts
                  ON stvrsts.stvrsts_code = sfrstcr.sfrstcr_rsts_code
                 AND sfrstcr.sfrstcr_levl_code NOT IN ('PD', 'AC')
                 AND sfrstcr_rsts_code <> 'AU'
                 AND stvrsts.stvrsts_incl_sect_enrl = 'Y'
                 AND stvrsts.stvrsts_withdraw_ind = 'N'
                 AND stvrsts.stvrsts_incl_assess = 'Y'
                 AND sfrstcr_term_code = rec.term_code
                 AND sfrstcr_ptrm_code = rec.ptrm_code
               GROUP BY sfrstcr.sfrstcr_crn,
                        sfrstcr.sfrstcr_term_code) act_reg
           ON act_reg.crn = ssbsect.ssbsect_crn
          AND act_reg.term_code = ssbsect.ssbsect_term_code
         JOIN saturn.sirasgn sir
           ON sir.sirasgn_crn = ll.crn
          AND sir.sirasgn_term_code = ll.term_code
          AND sir.sirasgn_primary_ind = 'Y'
         JOIN saturn.spriden
           ON spriden_pidm = sir.sirasgn_pidm
          AND spriden_change_ind IS NULL
          AND spriden_pidm NOT IN (3248979) --exclude To Be Announced
         LEFT JOIN zexec.zsavemal prof_emal
           ON prof_emal.pidm = sir.sirasgn_pidm
          AND prof_emal.emal_code = 'LU'
          AND prof_emal.emal_code_rank = 1
         LEFT JOIN saturn.stvcoll
           ON stvcoll_code = ll.coll_code
       -- EXCLUSIONS
         LEFT JOIN (SELECT ce.crn,
                          ce.term_code,
                          ce.instructional_method
                     FROM utl_d_lms.course_exclusions ce
                    WHERE ce.term_code = rec.term_code) xl
           ON xl.crn = ll.crn
          AND xl.term_code = ll.term_code) new_records
ON (destination_table.course_section_id = new_records.course_section_id AND destination_table.instance = new_records.instance)
WHEN MATCHED THEN
UPDATE
   SET destination_table.ptrm_code      = new_records.ptrm_code,
       destination_table.coll_code      = new_records.coll_code,
       destination_table.coll_desc      = new_records.coll_desc,
       destination_table.course         = new_records.course,
       destination_table.course_code    = new_records.course_code,
       destination_table.course_sis_id  = new_records.course_sis_id,
       destination_table.section_sis_id = new_records.section_sis_id,
       destination_table.course_id      = new_records.course_id,
       destination_table.url            = new_records.url,
       destination_table.camp_code      = new_records.camp_code,
       destination_table.insm_code      = new_records.insm_code,
       destination_table.faculty_pidm   = new_records.faculty_pidm,
       destination_table.faculty_name   = new_records.faculty_name,
       destination_table.faculty_email  = new_records.faculty_email,
       destination_table.enrollment     = new_records.enrollment,
       destination_table.start_date     = new_records.start_date,
       destination_table.end_date       = new_records.end_date,
       destination_table.activity_date  = v_etl_date,
       destination_table.exclusions     = new_records.exclusions
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
 camp_code,
 insm_code,
 faculty_pidm,
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
 new_records.camp_code,
 new_records.insm_code,
 new_records.faculty_pidm,
 new_records.faculty_name,
 new_records.faculty_email,
 new_records.instance,
 new_records.exclusions,
 new_records.enrollment,
 new_records.start_date,
 new_records.end_date,
 new_records.activity_date);
v_count := v_count + SQL%ROWCOUNT;
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'MERGE - ' || rec.term_code || rec.ptrm_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
ELSE
v_count := 0;
END IF;
dbms_output.put_line(' --------- ');
v_total_count := v_total_count + v_count;
END LOOP; -- c_terms 
-- remove all courses that are no longer active
DELETE FROM utl_d_lms.far_luo_courses far_luo_courses
 WHERE NOT EXISTS (SELECT ll.term_code,
               ll.ptrm_code,
               ll.crn,
               MIN(ll.start_date) AS start_date,
               MAX(ll.end_date) AS end_date,
               MAX(ll.end_date + 21) - 1 AS expiration_date -- leave the minus one; need expirations to occur on last day reports run
          FROM zbtm.terms_by_group_v t
          JOIN utl_d_lms.lms_link ll
            ON ll.term_code = t.term_code
         WHERE 1 = 1
           AND ll.instance = v_instance
           AND ll.status IN ('active', 'concluded')
           AND ll.enrollment > 0
           AND ll.instance = 'L2CAN'
           AND ll.ptrm_code IN ('R', '1A', '1B', '1C', '1D', '1J')
           AND SYSDATE <= (ll.end_date + 21) --stop running;
           AND far_luo_courses.term_code = ll.term_code
           AND far_luo_courses.crn = ll.crn
         GROUP BY ll.term_code,
                  ll.ptrm_code,
                  ll.crn);
v_count := SQL%ROWCOUNT;
-- remove any courses when all final grades are submitted for the course
DELETE FROM utl_d_lms.far_luo_courses flc
 WHERE NOT EXISTS (SELECT 1
          FROM utl_d_aim.szrcrse crse
         WHERE crse.term_code = flc.term_code
           AND crse.crn = flc.crn
           AND crse.final_grade IS NULL);
v_count := v_count + SQL%ROWCOUNT;
-- remove any courses that no longer exist in LMS LINK
DELETE FROM utl_d_lms.far_luo_courses flc
 WHERE flc.instance = v_instance
   AND NOT EXISTS (SELECT 1
          FROM utl_d_lms.lms_link ll
         WHERE 1 = 1
           AND ll.instance = flc.instance
           AND ll.course_section_id = flc.course_section_id);
v_count := v_count + SQL%ROWCOUNT;
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'DELETE - ' || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
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
---      11-04-2020  WGRIFFITH2  --Initial release
---      04-09-2021  WGRIFFITH2  --Adding course_ID and URL fields
---      06-25-2021  WGRIFFITH2  --Now using the RAFT form to track exclusions
---      03-24-2022  WGRIFFITH2  --Bb ist kaputt!
---      09-05-2022  WGRIFFITH2  --J term added to the FAR for Business dissertation courses (TKT2550031)
---      09-14-2023  WGRIFFITH2  --J term added MORE to the FAR for Business dissertation courses (TKT2784515)
---      06-13-2025  WGRIFFITH2  --Removing courses when all final grades are submitted for the course (TKT3113401)
---      07-04-2025  WGRIFFITH2  --Ensure LMS connection before allow records through
------------------------------------------------------------------------------------------------*/
END etl_lms_far_luo_courses;
END load_lms_etl_far_luo;