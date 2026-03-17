create or replace package load_aa_etl_fpt is
-- EVALUATIONS
PROCEDURE etl_aa_fpt_evaluations_schedule(jobnumber number, processid varchar2, processname varchar2); --- 12-07-2023  WGRIFFITH2  --Initial release
PROCEDURE etl_aa_fpt_evaluations_cohort(jobnumber number, processid varchar2, processname varchar2); --- 12-07-2023  WGRIFFITH2  --Initial release
PROCEDURE etl_aa_fpt_evaluations_status(jobnumber number, processid varchar2, processname varchar2); -- runs before AND after audit jobs 
PROCEDURE etl_aa_fpt_evaluations_audit_curv(jobnumber number, processid varchar2, processname varchar2); --- 12-07-2023  WGRIFFITH2  --Initial release
PROCEDURE etl_aa_fpt_evaluations_audit_self(jobnumber number, processid varchar2, processname varchar2); --- 12-07-2023  WGRIFFITH2  --Initial release
PROCEDURE etl_aa_fpt_evaluations_audit_dire(jobnumber number, processid varchar2, processname varchar2); --- 12-07-2023  WGRIFFITH2  --Initial release
PROCEDURE etl_aa_fpt_evaluations_audit_sume(jobnumber number, processid varchar2, processname varchar2); --- 12-07-2023  WGRIFFITH2  --Initial release
PROCEDURE etl_aa_fpt_evaluations_audit_dean(jobnumber number, processid varchar2, processname varchar2); --- 12-07-2023  WGRIFFITH2  --Initial release
PROCEDURE etl_aa_fpt_evaluations_tableau(jobnumber number, processid varchar2, processname varchar2); --- 12-07-2023  WGRIFFITH2  --Initial release
-- CREDENTIALING
PROCEDURE etl_aa_fpt_credentialing_audit(jobnumber number, processid varchar2, processname varchar2); --- 12-11-2024  WGRIFFITH2  --Initial release
PROCEDURE etl_aa_fpt_credentialing_tableau(jobnumber number, processid varchar2, processname varchar2); --- 12-11-2024  WGRIFFITH2  --Initial release
END load_aa_etl_fpt;
/
CREATE OR REPLACE PACKAGE BODY load_aa_etl_fpt IS

PROCEDURE etl_aa_fpt_credentialing_tableau(jobnumber   NUMBER,
processid   VARCHAR2,
processname VARCHAR2) IS
/*
Table: utl_d_lms.fpt_credentialing_tableau

Primary Keys: NONE

Unique index: UNIQUE_ID

Purpose: Table that stages the data for Faculty Credentialing that stores the instructor, college they relate to, and helps determine if the credentialing is completed in Etrieve

Conditions: instructor gets a record in cohort table when they first get a course


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
v_proc        VARCHAR2(100) := 'etl_aa_fpt_credentialing_tableau';
--CURSOR c_terms IS
BEGIN
-- dbms_output.enable(buffer_size => NULL);
--
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
v_count   := 0; -- reset count
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || 'ALL' || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
DELETE FROM utl_d_aa.fpt_credentialing_tableau WHERE 1 = 1; -- DELETE ALL / NO TRUNCATE TO KEEP RECORDS ON TABEAU WITH CONSTANT UPTIME
-- DO NOT COMMIT HERE
INSERT INTO utl_d_aa.fpt_credentialing_tableau
(pidm,
 instructor,
 instructor_username,
 email_address,
 coll_desc,
 im_usernames,
 chair_usernames,
 dean_usernames,
 fsc_usernames,
 admin_usernames,
 category_code,
 status,
 status_color,
 status_icon,
 status_desc,
 status_reason,
 url,
 category_desc,
 activity_date)
SELECT pidm,
       instructor,
       instructor_username,
       email_address,
       coll_desc,
       im_usernames,
       chair_usernames,
       dean_usernames,
       fsc_usernames,
       admin_usernames,
       category_code,
       status,
       status_color,
       status_icon,
       status_desc,
       status_reason,
       url,
       category_desc,
       activity_date
  FROM (SELECT cohort.pidm,
               cohort.instructor || ' - ' || cohort.instructor_username AS instructor,
               cohort.instructor_username,
               cohort.email_address,
               cohort.coll_desc, 
               regexp_replace(listagg(DISTINCT lower(fht.im_usernames), '-') within GROUP(ORDER BY 1), '([^-]*)(-\1)+($|-)', '\1\3') AS im_usernames,
               regexp_replace(listagg(DISTINCT lower(fht.chair_usernames), '-') within GROUP(ORDER BY 1), '([^-]*)(-\1)+($|-)', '\1\3') AS chair_usernames,
               regexp_replace(listagg(DISTINCT lower(fht.dean_usernames), '-') within GROUP(ORDER BY 1), '([^-]*)(-\1)+($|-)', '\1\3') AS dean_usernames,
               regexp_replace(listagg(DISTINCT lower(fht.fsc_usernames), '-') within GROUP(ORDER BY 1), '([^-]*)(-\1)+($|-)', '\1\3') AS fsc_usernames,
               regexp_replace(listagg(DISTINCT lower(fht.admin_usernames), '-') within GROUP(ORDER BY 1), '([^-]*)(-\1)+($|-)', '\1\3') AS admin_usernames,
               fca.category_code,
               MAX(CASE
                   WHEN status_code IN ('0', '1') THEN
                    'Completed Certification'
                   WHEN status_code = '2' THEN
                    'Pending Etrieve Certification'
                   WHEN status_code = '3' THEN
                    'Submission Required in FPT'
                   END) over(PARTITION BY cohort.pidm) AS status,
               fca.status_color,
               fca.status_icon,
               fca.status_desc,
               CASE
               WHEN status_code NOT IN ('0', '1') THEN
                substr(regexp_replace(listagg(DISTINCT fca.status_reason, ' ') within GROUP(ORDER BY 1), '([^-]*)(-\1)+($|-)', '\1\3'), 1, 3999)
               ELSE
                NULL
               END AS status_reason,
               fca.url,
               cat_codes.category_desc,
               dense_rank() over(PARTITION BY cohort.coll_desc, cohort.pidm, fca.category_code ORDER BY fca.status_code DESC) ranking,
               SYSDATE AS activity_date
          FROM (SELECT DISTINCT cohort.pidm,
                                cohort.instructor,
                                cohort.instructor_username,
                                cohort.email_address,
                                cohort.coll_code,
                                cohort.coll_desc
                  FROM utl_d_aa.fpt_cohort cohort
                 WHERE cohort.term_code IN (SELECT terms.term_code
                                              FROM zbtm.terms_by_group_v terms
                                             WHERE 1 = 1
                                               AND terms.group_code = 'STD'
                                               AND terms.semester IN ('FAL', 'SPR') -- only fall and spring terms are when we do evaluations
                                               AND SYSDATE BETWEEN terms.start_date - 21 AND terms.end_date + 365 -- run terms in the last year
                                               AND terms.term_code >= '202420' -- inception for FPT evaluations process
                                            )) cohort
          JOIN utl_d_aa.fpt_credentialing_audit fca
            ON fca.pidm = cohort.pidm
          JOIN utl_d_aa.fpt_cat_code cat_codes
            ON cat_codes.category_code = fca.category_code
          LEFT JOIN utl_d_aa.secfhtcoll fht
            ON fht.college_code = cohort.coll_code
         WHERE 1 = 1
         GROUP BY cohort.pidm,
                  cohort.instructor || ' - ' || cohort.instructor_username,
                  cohort.instructor_username,
                  cohort.email_address,
                  cohort.coll_desc,
                  fca.category_code,
                  fca.status_code,
                  fca.status_color,
                  fca.status_icon,
                  fca.status_desc,
                  fca.url,
                  cat_codes.category_desc)
 WHERE ranking = 1;
v_count := SQL%ROWCOUNT;
IF v_count > 0 THEN
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'DELETE/INSERT - ' || 'ALL' || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
ELSE
ROLLBACK;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'DELETE/INSERT - ' || 'ALL' || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
END IF;
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
END etl_aa_fpt_credentialing_tableau;

PROCEDURE etl_aa_fpt_credentialing_audit(jobnumber   NUMBER,
processid   VARCHAR2,
processname VARCHAR2) IS
/*
Table: utl_d_lms.fpt_credentialing_audit

Primary Keys: NONE

Unique index: UNIQUE_ID

Purpose: table that tracks FPT credentialing showing the progress of each phase

Conditions: instructor gets a record in cohort table when they first get a course


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
v_proc        VARCHAR2(100) := 'etl_aa_fpt_credentialing_audit';
-- CURSOR c_terms IS 
BEGIN
-- dbms_output.enable(buffer_size => NULL);
--
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
v_count   := 0; -- reset count
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || 'ALL' || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
MERGE INTO utl_d_aa.fpt_credentialing_audit tgt
USING (
WITH rec AS
 (SELECT DISTINCT pidm
    FROM utl_d_aa.fpt_cohort cohort
   WHERE cohort.term_code IN (SELECT terms.term_code
                                FROM zbtm.terms_by_group_v terms
                               WHERE 1 = 1
                                 AND terms.group_code = 'STD'
                                 AND terms.semester IN ('FAL', 'SPR') -- only fall and spring terms are when we do evaluations
                                 AND SYSDATE BETWEEN terms.start_date - 21 AND terms.end_date + 365 -- run terms in the last year
                                 AND terms.term_code >= '202440' -- inception v2
                              ))
SELECT src.pidm,
       src.category_code,
       src.status_code,
       src.status_color,
       src.status_icon,
       src.status_desc,
       src.status_reason,
       src.url,
       src.unique_id,
       src.activity_date
  FROM (SELECT rec.pidm,
               'DEGR' AS category_code,
               CASE
               WHEN status_reason IS NULL THEN
                '3'
               WHEN status_reason IS NOT NULL
                    AND document_id IS NULL THEN
                '2'
               WHEN status_reason IS NOT NULL
                    AND document_id IS NOT NULL THEN
                '0'
               END AS status_code,
               CASE
               WHEN status_reason IS NULL THEN
                'red'
               WHEN status_reason IS NOT NULL
                    AND document_id IS NULL THEN
                'yellow'
               WHEN status_reason IS NOT NULL
                    AND document_id IS NOT NULL THEN
                'green'
               END AS status_color,
               CASE
               WHEN status_reason IS NULL THEN
                'x-ray'
               WHEN status_reason IS NOT NULL
                    AND document_id IS NULL THEN
                'exclamation'
               WHEN status_reason IS NOT NULL
                    AND document_id IS NOT NULL THEN
                'check_mark'
               END AS status_icon,
               CASE
               WHEN status_reason IS NULL THEN
                'Degree(s) missing from Faculty Portfolio'
               WHEN status_reason IS NOT NULL
                    AND document_id IS NULL THEN
                'Degree(s) missing in Etrieve'
               WHEN status_reason IS NOT NULL
                    AND document_id IS NOT NULL THEN
                'Degree(s) validated'
               END AS status_desc,
               CASE
               WHEN status_reason IS NULL THEN
                'Instructor must enter the degree in the Faculty Portfolio'
               WHEN length(status_reason) > 57
                    AND document_id IS NULL THEN
                regexp_replace(substr(status_reason, 1, 57), '(\S+)$', '') || '...'
               ELSE
                NULL
               END AS status_reason,
               'https://facultyportfolio.liberty.edu/cv/' || rec.pidm AS url,
               standard_hash('DEGR' || rec.pidm || degr.unique_id, 'MD5') AS unique_id,
               v_etl_date AS activity_date
          FROM rec
          LEFT JOIN (SELECT pidm AS pidm,
                           degree_desc || ' - ' || nvl2(aed, listagg(subj2, ', ') within GROUP(ORDER BY subj2) || ': ' || listagg(focdesc, ', ') within GROUP(ORDER BY focdesc), listagg(subj2, ', ') within GROUP(ORDER BY subj2)) || ' from ' ||
                           college || ' (' || to_char(year_awarded) || ')' AS status_reason,
                           ed_id AS unique_id,
                           document_id
                      FROM (SELECT p.pidm,
                                   ed.id ed_id,
                                   degs.description degree_desc,
                                   coalesce(CASE
                                            WHEN dp.description = 'Not Listed' THEN
                                             NULL
                                            ELSE
                                             dp.description
                                            END, nvl(initcap(dis.subject), initcap(dis.other_subject))) subj2,
                                   CASE
                                   WHEN aoft.description IS NOT NULL THEN
                                    aoft.description || ' in '
                                   ELSE
                                    NULL
                                   END || listagg(dpaof.description, '/') within GROUP(ORDER BY dpaof.description) focdesc,
                                   inst.stvsbgi_desc college,
                                   aof.earned_degree aed,
                                   ed.year_awarded,
                                   cto_document_id AS document_id
                              FROM zfacultyportfolio.portfolio p
                              JOIN rec
                                ON rec.pidm = p.pidm
                              JOIN zfacultyportfolio.cv_v2 c
                                ON c.portfolio = p.id
                               AND c.certified_year IS NULL
                               AND c.soft_deleted IS NULL
                              JOIN zfacultyportfolio.earned_degree_v2 ed
                                ON ed.cv = c.id
                               AND ed.degree_id IS NOT NULL
                              JOIN zfacultyportfolio.degree_programs dp
                                ON dp.id = ed.program_id
                              JOIN zfacultyportfolio.degrees degs
                                ON degs.id = ed.degree_id
                              JOIN saturn.stvdlev dlev
                                ON dlev.stvdlev_code = degs.degree_level
                              JOIN saturn.stvsbgi inst
                                ON inst.stvsbgi_code = ed.institution
                              LEFT JOIN zfacultyportfolio.earned_degree_areas_of_focus aof
                                ON aof.earned_degree = ed.id
                              LEFT JOIN zfacultyportfolio.area_of_focus_types aoft
                                ON aoft.id = aof.type
                              LEFT JOIN zfacultyportfolio.degree_programs dpaof
                                ON dpaof.id = aof.program_id
                              LEFT JOIN zfacultyportfolio.discipline_v2 dis
                                ON dis.earned_degree = ed.id
                               AND aof.id IS NULL
                             WHERE 1 = 1
                             GROUP BY p.pidm,
                                      ed.id,
                                      degs.description,
                                      dis.subject,
                                      dis.other_subject,
                                      dp.description,
                                      aoft.description,
                                      inst.stvsbgi_desc,
                                      aof.earned_degree,
                                      cto_document_id,
                                      ed.year_awarded)
                     GROUP BY pidm,
                              degree_desc,
                              aed,
                              college,
                              year_awarded,
                              document_id,
                              ed_id) degr
            ON degr.pidm = rec.pidm
        UNION ALL
        SELECT rec.pidm,
               'LCSR' AS category_code,
               CASE
               WHEN status_reason IS NULL THEN
                '1'
               WHEN status_reason IS NOT NULL
                    AND document_id IS NULL THEN
                '2'
               WHEN status_reason IS NOT NULL
                    AND document_id IS NOT NULL THEN
                '0'
               END AS status_code,
               CASE
               WHEN status_reason IS NULL THEN
                'gray'
               WHEN status_reason IS NOT NULL
                    AND document_id IS NULL THEN
                'yellow'
               WHEN status_reason IS NOT NULL
                    AND document_id IS NOT NULL THEN
                'green'
               END AS status_color,
               CASE
               WHEN status_reason IS NULL THEN
                'minus'
               WHEN status_reason IS NOT NULL
                    AND document_id IS NULL THEN
                'exclamation'
               WHEN status_reason IS NOT NULL
                    AND document_id IS NOT NULL THEN
                'check_mark'
               END AS status_icon,
               CASE
               WHEN status_reason IS NULL THEN
                'Licensure(s) missing from Faculty Portfolio'
               WHEN status_reason IS NOT NULL
                    AND document_id IS NULL THEN
                'Licensure(s) missing in Etrieve'
               WHEN status_reason IS NOT NULL
                    AND document_id IS NOT NULL THEN
                'Licensure(s) validated'
               END AS status_desc,
               CASE
               WHEN status_reason IS NULL THEN
                'Instructor may need to enter licensure(s) in the Faculty Portfolio'
               WHEN length(status_reason) > 57
                    AND document_id IS NULL THEN
                regexp_replace(substr(status_reason, 1, 57), '(\S+)$', '') || '...'
               ELSE
                NULL
               END AS status_reason,
               'https://facultyportfolio.liberty.edu/cv/' || rec.pidm AS url,
               standard_hash('LCSR' || rec.pidm || lcsr.unique_id, 'MD5') AS unique_id,
               v_etl_date AS activity_date
          FROM rec
          LEFT JOIN (SELECT rec.pidm AS pidm,
                           licensure.title || ' - ' || dbms_lob.substr(licensure.description, 500) || ' from ' || licensure.issued_by || ' (' || to_char(licensure.start_date, 'MM/DD/YYYY') || ' - ' ||
                           nvl(to_char(licensure.end_date, 'MM/DD/YYYY'), 'Present') || ')' status_reason,
                           licensure.id AS unique_id,
                           licensure.document_id
                      FROM zfacultyportfolio.portfolio p
                      JOIN rec
                        ON rec.pidm = p.pidm
                      JOIN zfacultyportfolio.cv_v2 pcv
                        ON pcv.portfolio = p.id
                       AND pcv.certified_year IS NULL
                       AND pcv.soft_deleted IS NULL
                      JOIN zfacultyportfolio.licensure_v2 licensure
                        ON licensure.cv = pcv.id) lcsr
            ON lcsr.pidm = rec.pidm
         WHERE 1 = 1
        UNION ALL
        SELECT rec.pidm,
               'CERT' AS category_code,
               CASE
               WHEN status_reason IS NULL THEN
                '1'
               WHEN status_reason IS NOT NULL
                    AND document_id IS NULL THEN
                '2'
               WHEN status_reason IS NOT NULL
                    AND document_id IS NOT NULL THEN
                '0'
               END AS status_code,
               CASE
               WHEN status_reason IS NULL THEN
                'gray'
               WHEN status_reason IS NOT NULL
                    AND document_id IS NULL THEN
                'yellow'
               WHEN status_reason IS NOT NULL
                    AND document_id IS NOT NULL THEN
                'green'
               END AS status_color,
               CASE
               WHEN status_reason IS NULL THEN
                'minus'
               WHEN status_reason IS NOT NULL
                    AND document_id IS NULL THEN
                'exclamation'
               WHEN status_reason IS NOT NULL
                    AND document_id IS NOT NULL THEN
                'check_mark'
               END AS status_icon,
               CASE
               WHEN status_reason IS NULL THEN
                'Certification(s) missing from Faculty Portfolio'
               WHEN status_reason IS NOT NULL
                    AND document_id IS NULL THEN
                'Certification(s) missing in Etrieve'
               WHEN status_reason IS NOT NULL
                    AND document_id IS NOT NULL THEN
                'Certification(s) validated'
               END AS status_desc,
               CASE
               WHEN status_reason IS NULL THEN
                'Instructor may need to enter certification(s) in the Faculty Portfolio'
               WHEN length(status_reason) > 57
                    AND document_id IS NULL THEN
                regexp_replace(substr(status_reason, 1, 57), '(\S+)$', '') || '...'
               ELSE
                NULL
               END AS status_reason,
               'https://facultyportfolio.liberty.edu/cv/' || rec.pidm AS url,
               standard_hash('CERT' || rec.pidm || lcsr.unique_id, 'MD5') AS unique_id,
               v_etl_date AS activity_date
          FROM rec
          LEFT JOIN (SELECT rec.pidm AS pidm,
                           cert.title || ' - ' || dbms_lob.substr(cert.description, 500) || ' from ' || cert.issued_by || ' (' || to_char(cert.start_date, 'MM/DD/YYYY') || ' - ' || nvl(to_char(cert.end_date, 'MM/DD/YYYY'), 'Present') || ')' status_reason,
                           cert.id AS unique_id,
                           cert.document_id
                      FROM zfacultyportfolio.portfolio p
                      JOIN rec
                        ON rec.pidm = p.pidm
                      JOIN zfacultyportfolio.cv_v2 pcv
                        ON pcv.portfolio = p.id
                       AND pcv.certified_year IS NULL
                       AND pcv.soft_deleted IS NULL
                      JOIN zfacultyportfolio.certificate_v2 cert
                        ON cert.cv = pcv.id) lcsr
            ON lcsr.pidm = rec.pidm
         WHERE 1 = 1
        UNION ALL
        SELECT rec.pidm,
               'GRCW' AS category_code,
               CASE
               WHEN status_reason IS NULL THEN
                '1'
               WHEN status_reason IS NOT NULL
                    AND document_id IS NULL THEN
                '2'
               WHEN status_reason IS NOT NULL
                    AND document_id IS NOT NULL THEN
                '0'
               END AS status_code,
               CASE
               WHEN status_reason IS NULL THEN
                'gray'
               WHEN status_reason IS NOT NULL
                    AND document_id IS NULL THEN
                'yellow'
               WHEN status_reason IS NOT NULL
                    AND document_id IS NOT NULL THEN
                'green'
               END AS status_color,
               CASE
               WHEN status_reason IS NULL THEN
                'minus'
               WHEN status_reason IS NOT NULL
                    AND document_id IS NULL THEN
                'exclamation'
               WHEN status_reason IS NOT NULL
                    AND document_id IS NOT NULL THEN
                'check_mark'
               END AS status_icon,
               CASE
               WHEN status_reason IS NULL THEN
                'Graduate coursework is not in the Faculty Portfolio'
               WHEN status_reason IS NOT NULL
                    AND document_id IS NULL THEN
                'Graduate coursework is missing in Etrieve'
               WHEN status_reason IS NOT NULL
                    AND document_id IS NOT NULL THEN
                'Graduate coursework validated'
               END AS status_desc,
               CASE
               WHEN status_reason IS NULL THEN
                'Instructor may need to enter graduate coursework in the Faculty Portfolio'
               WHEN length(status_reason) > 57
                    AND document_id IS NULL THEN
                regexp_replace(substr(status_reason, 1, 57), '(\S+)$', '') || '...'
               ELSE
                NULL
               END AS status_reason,
               'https://facultyportfolio.liberty.edu/cv/' || rec.pidm AS url,
               standard_hash('GRCW' || rec.pidm || grcw.unique_id, 'MD5') AS unique_id,
               v_etl_date AS activity_date
          FROM rec
          LEFT JOIN (SELECT rec.pidm AS pidm,
                           gcc.course_title || ' (' || gcc.course_prefix || gcc.course_number || ')' || ' - ' || dp.description || ' - ' || gcc.hours || ' hours' || ' from ' || sbgi.stvsbgi_desc AS status_reason,
                           gcc.id AS unique_id,
                           gcc.cto_document_id AS document_id
                      FROM zfacultyportfolio.portfolio p
                      JOIN rec
                        ON rec.pidm = p.pidm
                      JOIN zfacultyportfolio.cv_v2 pcv
                        ON pcv.portfolio = p.id
                       AND pcv.certified_year IS NULL
                       AND pcv.soft_deleted IS NULL
                      JOIN zfacultyportfolio.graduate_coursework_v2 gc
                        ON gc.cv = pcv.id
                      JOIN zfacultyportfolio.graduate_coursework_courses gcc -- no replication yet
                        ON gcc.graduate_coursework_id = gc.id
                      JOIN zfacultyportfolio.degree_programs dp
                        ON dp.id = gc.teaching_discipline
                      LEFT JOIN saturn.stvsbgi sbgi
                        ON sbgi.stvsbgi_code = gcc.institution) grcw
            ON grcw.pidm = rec.pidm
         WHERE 1 = 1) src
  LEFT JOIN utl_d_aa.fpt_credentialing_audit tgt
    ON tgt.unique_id = src.unique_id
 WHERE 1 = 1
   AND (tgt.pidm IS NULL -- missing from target table
       OR coalesce(tgt.category_code, 'X') <> coalesce(src.category_code, 'X') -- compare category_code
       OR coalesce(tgt.status_code, 'X') <> coalesce(src.status_code, 'X') -- compare status_color
       OR coalesce(tgt.status_color, 'X') <> coalesce(src.status_color, 'X') -- compare status_color
       OR coalesce(tgt.status_icon, 'X') <> coalesce(src.status_icon, 'X') -- compare status_icon
       OR coalesce(tgt.status_desc, 'X') <> coalesce(src.status_desc, 'X') -- compare status_reason
       OR coalesce(tgt.status_reason, 'X') <> coalesce(src.status_reason, 'X') -- compare status_reason
       OR coalesce(tgt.url, 'X') <> coalesce(src.url, 'X') -- compare url  
       )) src ON (tgt.unique_id = src.unique_id) WHEN MATCHED THEN
UPDATE
   SET tgt.pidm          = src.pidm,
       tgt.category_code = src.category_code,
       tgt.status_code   = src.status_code,
       tgt.status_color  = src.status_color,
       tgt.status_icon   = src.status_icon,
       tgt.status_desc   = src.status_desc,
       tgt.status_reason = src.status_reason,
       tgt.url           = src.url,
       tgt.activity_date = src.activity_date
WHEN NOT MATCHED THEN
INSERT
(pidm,
 category_code,
 status_code,
 status_color,
 status_icon,
 status_desc,
 status_reason,
 url,
 unique_id,
 activity_date)
VALUES
(src.pidm,
 src.category_code,
 src.status_code,
 src.status_color,
 src.status_icon,
 src.status_desc,
 src.status_reason,
 src.url,
 src.unique_id,
 src.activity_date);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || 'ALL' || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
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
ROLLBACK;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
END etl_aa_fpt_credentialing_audit;

PROCEDURE etl_aa_fpt_evaluations_cohort(jobnumber NUMBER, processid VARCHAR2, processname VARCHAR2) IS
/*
Table: utl_d_lms.fpt_cohort

Primary Keys: NONE

Unique index: TERM_CODE, CAMP_CODE, COLL_CODE, PIDM

Purpose: Cohort table for the FPT dashboard that stores the instructor, college/campus they taught (can contain multiple), and helps determine when evaluations are required.

Conditions: instructor gets a record in cohort table when they first get a course; only run current terms

*/
--DECLARE
--- PARAMS
v_etl_date DATE := SYSDATE;
v_msg VARCHAR2(2000);
v_instance VARCHAR2(50) := upper('ALL'); -- inst from the jams job; used for determining instance
v_partition NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0


v_count NUMBER := 0;
v_elapsed NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id VARCHAR2(32);
v_proc VARCHAR2(100) := 'etl_aa_fpt_evaluations_cohort';
CURSOR c_terms IS
SELECT DISTINCT fes.term_code,
                fes.group_code,
                fes.semester,
                fes.aidy_code
  FROM utl_d_aa.fpt_evaluations_schedule fes
 ORDER BY 1 DESC;
BEGIN
-- dbms_output.enable(buffer_size => NULL);
--
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
v_msg := 'START - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
FOR rec IN c_terms
LOOP
v_count   := 0; -- reset count
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
MERGE INTO utl_d_aa.fpt_cohort tgt
USING (SELECT src.aidy_code,
              src.term_code,
              src.portfolio,
              src.pidm,
              src.instructor,
              src.instructor_username,
              src.email_address,
              src.camp_code,
              src.coll_code,
              src.coll_desc,
              src.first_complete_date,
              src.course_list,
              src.activity_date,
              src.seats
         FROM (SELECT rec.aidy_code AS aidy_code,
                      rec.term_code AS term_code,
                      portfolio.id AS portfolio,
                      prof.spriden_pidm AS pidm,
                      spriden_last_name || ', ' || spriden_first_name AS instructor,
                      gob.gobtpac_external_user AS instructor_username,
                      NVL(emal.email_address,gob.gobtpac_external_user||'@liberty.edu') AS email_address,
                      ll.camp_code,
                      ll.coll_code,
                      stvcoll_desc AS coll_desc,
                      listagg(DISTINCT ll.subj_code || ll.crse_numb, ', ') within GROUP(ORDER BY ll.subj_code || ll.crse_numb) AS course_list,
                      MIN(CASE
                          WHEN ll.end_date <= v_etl_date + 1 THEN
                           ll.end_date
                          END) AS first_complete_date, -- date when instructors can start self evaluation
                      v_etl_date AS activity_date,
                      SUM(ll.enrollment) AS seats
                 FROM utl_d_lms.lms_link ll
                 JOIN saturn.spriden prof
                   ON prof.spriden_pidm = ll.faculty_pidm
                  AND prof.spriden_change_ind IS NULL
                  AND prof.spriden_pidm NOT IN (3248979) --exclude To Be Announced
                  AND ll.term_code = rec.term_code
                  AND ll.enrollment > 0 -- must have students
                  AND substr(ll.crse_numb, 1, 1) <> '0' -- exlcude any non-credit courses
                  AND ll.coll_code <> 'CS'
                 JOIN zfacultyportfolio.portfolio -- get portfolio.id
                   ON portfolio.pidm = ll.faculty_pidm
                 JOIN general.gobtpac gob -- get username
                   ON gob.gobtpac_pidm = prof.spriden_pidm
                 JOIN zgeneral.activefacultystaff afs
                   ON afs.emppidm = prof.spriden_pidm
                  AND afs.empstatus IN ('A') -- ensure employee is active
                 LEFT JOIN saturn.spbpers
                   ON spbpers_pidm = prof.spriden_pidm
                  AND spbpers_dead_ind IS NULL -- ensure employee is still alive
                 LEFT JOIN zexec.zsavemal emal
                   ON emal.pidm = prof.spriden_pidm
                  AND emal.emal_code = 'LU'
                  AND emal.emal_rank = 1
                 LEFT JOIN saturn.stvcoll
                   ON stvcoll_code = ll.coll_code
                GROUP BY rec.aidy_code,
                         rec.term_code,
                         portfolio.id,
                         prof.spriden_pidm,
                         spriden_last_name || ', ' || spriden_first_name,
                         gob.gobtpac_external_user,
                         NVL(emal.email_address,gob.gobtpac_external_user||'@liberty.edu'),
                         ll.camp_code,
                         ll.coll_code,
                         stvcoll_desc) src
         LEFT JOIN utl_d_aa.fpt_cohort tgt
           ON tgt.term_code = rec.term_code
          AND tgt.camp_code = src.camp_code
          AND tgt.coll_code = src.coll_code
          AND tgt.pidm = src.pidm
        WHERE 1 = 1
          AND (tgt.pidm IS NULL -- missing from target table
              OR coalesce(tgt.portfolio, 0) <> coalesce(src.portfolio, 0) --
              OR coalesce(tgt.course_list, 'X') <> coalesce(src.course_list, 'X') --
              OR coalesce(tgt.seats, 0) <> coalesce(src.seats, 0) --
              OR coalesce(tgt.instructor, 'X') <> coalesce(src.instructor, 'X') --
              OR coalesce(tgt.instructor_username, 'X') <> coalesce(src.instructor_username, 'X') --
              OR coalesce(tgt.email_address, 'X') <> coalesce(src.email_address, 'X') --
              OR coalesce(tgt.coll_desc, 'X') <> coalesce(src.coll_desc, 'X') --
              OR coalesce(tgt.first_complete_date, SYSDATE) <> coalesce(src.first_complete_date, SYSDATE) --
              )) src
ON (tgt.term_code = src.term_code AND tgt.camp_code = src.camp_code AND tgt.coll_code = src.coll_code AND tgt.pidm = src.pidm)
WHEN MATCHED THEN
UPDATE
   SET tgt.instructor          = src.instructor,
       tgt.instructor_username = src.instructor_username,
       tgt.portfolio           = src.portfolio,
       tgt.email_address       = src.email_address,
       tgt.coll_desc           = src.coll_desc,
       tgt.first_complete_date = src.first_complete_date,
       tgt.seats               = src.seats,
       tgt.course_list         = src.course_list,
       tgt.activity_date       = src.activity_date
WHEN NOT MATCHED THEN
INSERT
(aidy_code,
 term_code,
 portfolio,
 pidm,
 instructor,
 instructor_username,
 email_address,
 camp_code,
 coll_code,
 coll_desc,
 first_complete_date,
 seats,
 course_list,
 activity_date)
VALUES
(src.aidy_code,
 src.term_code,
 src.portfolio,
 src.pidm,
 src.instructor,
 src.instructor_username,
 src.email_address,
 src.camp_code,
 src.coll_code,
 src.coll_desc,
 src. first_complete_date,
 src.seats,
 src.course_list,
 src.activity_date);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- remove any records that no longer have enrollment from the FPT tables
-- **NEVER DELETE FROM THE LOG TABLE** just in case of recovery
IF to_char(v_etl_date, 'D') IN ('2', '6') -- only run at specific times outside of high demand
   AND to_char(SYSDATE, 'HH24') >= ('18') THEN
DELETE FROM utl_d_aa.fpt_cohort fc
 WHERE fc.term_code = rec.term_code
   AND (NOT EXISTS (SELECT 1
                      FROM utl_d_lms.lms_link ll
                     WHERE ll.term_code = fc.term_code
                       AND ll.camp_code = fc.camp_code
                       AND ll.coll_code = fc.coll_code
                       AND ll.faculty_pidm = fc.pidm) OR fc.seats = 0);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'DELETE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
DELETE FROM utl_d_aa.fpt_evaluations_audit tgt
 WHERE NOT EXISTS (SELECT 1
          FROM utl_d_aa.fpt_cohort src
         WHERE src.term_code = tgt.term_code
           AND src.pidm = tgt.pidm
           AND src.camp_code = tgt.camp_code
           AND src.coll_code = tgt.coll_code)
   AND term_code = rec.term_code;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'DELETE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
DELETE FROM utl_d_aa.fpt_evaluations_status tgt
 WHERE NOT EXISTS (SELECT 1
          FROM utl_d_aa.fpt_cohort src
         WHERE src.term_code = tgt.term_code
           AND src.pidm = tgt.pidm
           AND src.camp_code = tgt.camp_code
           AND src.coll_code = tgt.coll_code)
   AND term_code = rec.term_code;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'DELETE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
DELETE FROM utl_d_aa.fpt_evaluations_tableau tgt
 WHERE NOT EXISTS (SELECT 1
          FROM utl_d_aa.fpt_cohort src
         WHERE src.term_code = tgt.term_code
           AND src.pidm = tgt.pidm
           AND src.camp_code = tgt.camp_code
           AND src.coll_code = tgt.coll_code)
   AND term_code = rec.term_code;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'DELETE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
END IF;
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
END etl_aa_fpt_evaluations_cohort;
PROCEDURE etl_aa_fpt_evaluations_schedule(jobnumber NUMBER, processid VARCHAR2, processname VARCHAR2) IS
/*
Table: utl_d_aa.fpt_evaluations_schedule

Primary Keys: NONE

Unique index: TERM_CODE, CAMP_CODE

Purpose: This proc will determine the timeframes when evaluations need to trigger

Conditions: Only shows the last years of semesters. truncates and reloads

*/
--DECLARE
--- PARAMS
v_etl_date DATE := SYSDATE;
v_msg VARCHAR2(2000);
v_instance VARCHAR2(50) := upper('ALL'); -- inst from the jams job; used for determining instance
v_partition NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0


v_count NUMBER := 0;
v_elapsed NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id VARCHAR2(32);
v_proc VARCHAR2(100) := 'etl_aa_fpt_evaluations_schedule';
BEGIN
-- dbms_output.enable(buffer_size => NULL);
--
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
v_count   := 0; -- reset count
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
utl_d_aa.truncate_table(v_table_name => 'fpt_evaluations_schedule');
INSERT INTO utl_d_aa.fpt_evaluations_schedule
(term_code,
 group_code,
 aidy_code,
 camp_code,
 start_date,
 end_date,
 semester,
 semester_desc,
 self_start_date,
 dire_start_date,
 sume_start_date,
 dean_start_date,
 dean_end_date,
 retro_self_start_date,
 retro_dire_start_date,
 retro_sume_start_date,
 retro_dean_start_date,
 retro_dean_end_date,
 cv_start_date,
 cv_end_date,
 fpt_term_code,
 activity_date)
SELECT terms.term_code,
       terms.group_code,
       terms.fa_proc_year AS aidy_code,
       'D' AS camp_code,
       MIN(terms.start_date) AS start_date,
       MAX(terms.end_date) AS end_date,
       terms.semester AS semester,
       stvterm_desc AS semester_desc,
       MAX(ptrm_end_date + 7) AS self_start_date, -- when all self evaluations start; end date for B term + 7
       MAX(ptrm_end_date + 21) AS dire_start_date,
       MAX(ptrm_end_date + 35) AS sume_start_date,
       MAX(ptrm_end_date + 49) AS dean_start_date,
       MAX(ptrm_end_date + 63) AS dean_end_date,
       MAX(terms.end_date + 30) AS retro_self_start_date, -- when retroactive self evaluations start; semester end date for + 30
       MAX(terms.end_date + 44) AS retro_dire_start_date,
       MAX(terms.end_date + 58) AS retro_sume_start_date,
       MAX(terms.end_date + 72) AS retro_dean_start_date,
       MAX(terms.end_date + 86) AS retro_dean_end_date,
       MIN(to_date('01/01/20' || substr(terms.fa_proc_year, 3, 2), 'MM/DD/YYYY')) AS cv_start_date,
       MAX(to_date('05/15/20' || substr(terms.fa_proc_year, 3, 2), 'MM/DD/YYYY')) AS cv_end_date,
       terms.term_code AS fpt_term_code,
       SYSDATE AS activity_date
  FROM zbtm.terms_by_group_v terms
  JOIN stvterm
    ON stvterm_code = terms.term_code
  JOIN (SELECT terms.term_code,
               MIN(sobptrm.sobptrm_end_date) AS ptrm_end_date
          FROM saturn.sobptrm
          JOIN zbtm.terms_by_group_v terms
            ON terms.term_code = sobptrm.sobptrm_term_code
         WHERE sobptrm.sobptrm_ptrm_code = '1B'
           AND terms.term_code >= '202420' -- inception for FPT evaluations process
         GROUP BY terms.term_code) bterm
    ON bterm.term_code = terms.term_code
 WHERE 1 = 1
   AND terms.group_code = 'STD'
   AND terms.semester IN ('FAL', 'SPR') -- only fall and spring terms are when we do evaluations
   AND SYSDATE BETWEEN terms.start_date - 21 AND terms.end_date + 365 -- run terms in the last year
   AND terms.term_code >= '202420' -- inception for FPT evaluations process
 GROUP BY terms.term_code,
          terms.group_code,
          terms.fa_proc_year,
          terms.semester,
          stvterm_desc
UNION
SELECT terms.term_code,
       terms.group_code,
       terms.fa_proc_year AS aidy_code,
       'R' AS camp_code,
       MIN(terms.start_date) AS start_date,
       MAX(terms.end_date) AS end_date,
       terms.semester AS semester,
       stvterm_desc AS semester_desc,
       MAX(CASE
           WHEN terms.semester = 'SPR' THEN
            ptrm_end_date + INTERVAL '7' DAY
           ELSE
            to_date('09/01/' || substr(terms.term_code, 1, 4), 'MM/DD/YYYY')
           END) AS self_start_date,
       MAX(CASE
           WHEN terms.semester = 'SPR' THEN
            ptrm_end_date + INTERVAL '21' DAY
           ELSE
            to_date('09/20/' || substr(terms.term_code, 1, 4), 'MM/DD/YYYY')
           END) AS dire_start_date,
       MAX(CASE
           WHEN terms.semester = 'SPR' THEN
            ptrm_end_date + INTERVAL '35' DAY
           ELSE
            to_date('10/01/' || substr(terms.term_code, 1, 4), 'MM/DD/YYYY')
           END) AS sume_start_date,
       MAX(CASE
           WHEN terms.semester = 'SPR' THEN
            ptrm_end_date + INTERVAL '49' DAY
           ELSE
            to_date('10/15/' || substr(terms.term_code, 1, 4), 'MM/DD/YYYY')
           END) AS dean_start_date,
       MAX(CASE
           WHEN terms.semester = 'SPR' THEN
            ptrm_end_date + INTERVAL '63' DAY
           ELSE
            to_date('10/31/' || substr(terms.term_code, 1, 4), 'MM/DD/YYYY')
           END) AS dean_end_date,
       MAX(terms.end_date + 30) AS retro_self_start_date, -- when retroactive self evaluations start; semester end date for + 30
       MAX(terms.end_date + 44) AS retro_dire_start_date,
       MAX(terms.end_date + 58) AS retro_sume_start_date,
       MAX(terms.end_date + 72) AS retro_dean_start_date,
       MAX(terms.end_date + 86) AS retro_dean_end_date,
       MIN(to_date('01/01/20' || substr(terms.fa_proc_year, 3, 2), 'MM/DD/YYYY')) AS cv_start_date,
       MAX(to_date('05/15/20' || substr(terms.fa_proc_year, 3, 2), 'MM/DD/YYYY')) AS cv_end_date,
       terms.term_code AS fpt_term_code,
       SYSDATE AS activity_date
  FROM zbtm.terms_by_group_v terms
  JOIN stvterm
    ON stvterm_code = terms.term_code
  JOIN (SELECT terms.term_code,
               MIN(sobptrm.sobptrm_end_date) AS ptrm_end_date
          FROM saturn.sobptrm
          JOIN zbtm.terms_by_group_v terms
            ON terms.term_code = sobptrm.sobptrm_term_code
         WHERE sobptrm.sobptrm_ptrm_code = '1B'
         GROUP BY terms.term_code) bterm
    ON bterm.term_code = terms.term_code
 WHERE 1 = 1
   AND terms.group_code = 'STD'
   AND terms.semester IN ('FAL', 'SPR') -- only fall and spring terms are when we do evaluations
   AND SYSDATE BETWEEN terms.start_date - 21 AND terms.end_date + 365 -- get all terms within the last year
   AND terms.term_code >= '202420' -- inception for FPT evaluations process
 GROUP BY terms.term_code,
          terms.group_code,
          terms.fa_proc_year,
          terms.semester,
          stvterm_desc;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- NOW, WE NEED TO MAKE A COPY OF RESIDENT STD TERMS FOR MED
INSERT INTO utl_d_aa.fpt_evaluations_schedule
(term_code,
 group_code,
 aidy_code,
 camp_code,
 start_date,
 end_date,
 semester,
 semester_desc,
 self_start_date,
 dire_start_date,
 sume_start_date,
 dean_start_date,
 dean_end_date,
 retro_self_start_date,
 retro_dire_start_date,
 retro_sume_start_date,
 retro_dean_start_date,
 retro_dean_end_date,
 cv_start_date,
 cv_end_date,
 fpt_term_code,
 activity_date)
SELECT CASE
       WHEN substr(term_code, -2) = '20' THEN
        substr(term_code, 1, length(term_code) - 2) || '25'
       WHEN substr(term_code, -2) = '40' THEN
        substr(term_code, 1, length(term_code) - 2) || '45'
       ELSE
        term_code
       END AS term_code, -- convert std terms to med terms
       'MED' AS group_code,
       aidy_code,
       camp_code,
       start_date,
       end_date,
       semester,
       semester_desc,
       self_start_date,
       dire_start_date,
       sume_start_date,
       dean_start_date,
       dean_end_date,
       retro_self_start_date,
       retro_dire_start_date,
       retro_sume_start_date,
       retro_dean_start_date,
       retro_dean_end_date,
       cv_start_date,
       cv_end_date,
       term_code AS fpt_term_code,
       SYSDATE AS activity_date
  FROM utl_d_aa.fpt_evaluations_schedule
 WHERE camp_code = 'R';
v_count := SQL%ROWCOUNT;
COMMIT;
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
ROLLBACK;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
END etl_aa_fpt_evaluations_schedule;
PROCEDURE etl_aa_fpt_evaluations_status(jobnumber NUMBER, processid VARCHAR2, processname VARCHAR2) IS
/*
Table: utl_d_aa.fpt_evaluations_status

Primary Keys: NONE

Unique index: TERM_CODE, PIDM, CAMP_CODE, COLL_CODE

Purpose: This proc will determine if the instructor needs an evaluation for the term or not

Conditions:
	- This will run BEFORE and AFTER fpt_evaluations_audit procedures

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
v_proc        VARCHAR2(100) := 'etl_aa_fpt_evaluations_status';
CURSOR c_terms IS
SELECT fes.*
  FROM utl_d_aa.fpt_evaluations_schedule fes
 ORDER BY 1,
          3;
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
v_msg     := 'START - ' || rec.term_code || ' - ' || rec.camp_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
MERGE INTO utl_d_aa.fpt_evaluations_status tgt
USING (SELECT src.aidy_code,
              src.term_code,
              src.pidm,
              src.camp_code,
              src.coll_code,
              src.last_term_completed,
              src.last_term_evaluation,
              src.status,
              src.status_desc,
              src.activity_date
         FROM (SELECT cohort.aidy_code,
                      cohort.term_code,
                      cohort.pidm,
                      cohort.camp_code,
                      cohort.coll_code,
                      prior_decision.term_code AS last_term_completed,
                      prior_decision.evaluation_score AS last_term_evaluation,
                      CASE
                      WHEN (prior_term.pidm IS NULL AND cohort.first_complete_date IS NOT NULL) THEN
                       'Required' -- 'Required - Initial term'
                      WHEN (prior_term.pidm IS NULL AND cohort.first_complete_date IS NULL) THEN
                       'Pending' -- 'Pending - Required evaluation should start after first course ends'
                      WHEN (rec.semester = 'FAL' AND cohort.camp_code = 'R') THEN
                       'Required' -- 'Required - Resident evaluations are required during fall'
                      WHEN (nvl(prior_decision.evaluation_score, 0) < 3) THEN
                       'Required' -- 'Required - Missing/Failed prior evaluation'
                      WHEN (rec.semester = 'FAL' AND SYSDATE > rec.retro_self_start_date AND futr_term.pidm IS NULL) THEN
                       'Retroactive' -- 'Retroactive - Spring courses NOT found after teaching in fall'
                      WHEN (rec.semester = 'SPR' AND cohort.camp_code = 'R') THEN
                       'Not Required' --  'Not Required - Resident evaluations are not required during spring'
                      WHEN (rec.semester = 'SPR' AND cohort.camp_code = 'D' AND prior_decision.aidy_code = rec.aidy_code AND nvl(prior_decision.evaluation_score, 0) >= 3) THEN
                       'Not Required' --  'Not Required - Optional evaluation was completed in the fall'
                      WHEN (rec.semester = 'FAL' AND cohort.camp_code = 'D' AND SYSDATE > rec.retro_self_start_date AND current_started.pidm IS NULL) THEN
                       'Not Required' --  'Not Required - Optional evaluation was NOT started during fall'
                      WHEN (rec.semester = 'FAL' AND SYSDATE > rec.retro_self_start_date AND current_started.pidm IS NOT NULL) THEN
                       'Required' -- 'Required - Optional evaluation was started during fall'
                      WHEN (rec.semester = 'FAL' AND cohort.camp_code = 'D') THEN
                       'Optional' -- 'Optional - Optional evaluation can be started during fall once first course is complete'
                      WHEN (rec.semester = 'SPR' AND current_started.term_code < cohort.term_code AND prior_decision.term_code < current_started.term_code) THEN
                       'Pending' -- 'Pending - Prior term evaluation is in progress'
                      WHEN cohort.first_complete_date IS NULL THEN
                       'Pending' -- 'Pending - Evaluation should start after first course ends'
                      WHEN cohort.first_complete_date IS NOT NULL THEN
                       'Required' --'Required - Evaluation process has started'
                      ELSE
                       'Unknown' -- 'Unknown - If all else fails, try another approach...'
                      END AS status,
                      CASE
                      WHEN (prior_term.pidm IS NULL AND cohort.first_complete_date IS NOT NULL) THEN
                       'Required - Initial term'
                      WHEN (prior_term.pidm IS NULL AND cohort.first_complete_date IS NULL) THEN
                       'Pending - Required evaluation should start after first course ends'
                      WHEN (rec.semester = 'FAL' AND cohort.camp_code = 'R') THEN
                       'Required - Resident evaluations are required during fall'
                      WHEN (nvl(prior_decision.evaluation_score, 0) < 3) THEN
                       'Required - Missing/Failed prior evaluation'
                      WHEN (rec.semester = 'FAL' AND SYSDATE > rec.retro_self_start_date AND futr_term.pidm IS NULL) THEN
                       'Retroactive - Spring courses NOT found after teaching in fall'
                      WHEN (rec.semester = 'FAL' AND SYSDATE > rec.retro_self_start_date AND futr_term.pidm IS NULL) THEN
                       'Retroactive - No spring courses found after teaching in fall'
                      WHEN (rec.semester = 'SPR' AND cohort.camp_code = 'R') THEN
                       'Not Required - Resident evaluations are not required during spring'
                      WHEN (rec.semester = 'SPR' AND cohort.camp_code = 'D' AND prior_decision.aidy_code = rec.aidy_code AND nvl(prior_decision.evaluation_score, 0) >= 3) THEN
                       'Not Required - Optional evaluation was completed in the fall'
                      WHEN (rec.semester = 'FAL' AND cohort.camp_code = 'D' AND SYSDATE > rec.retro_self_start_date AND current_started.pidm IS NULL) THEN
                       'Not Required - Optional evaluation was NOT started during fall'
                      WHEN (rec.semester = 'FAL' AND SYSDATE > rec.retro_self_start_date AND current_started.pidm IS NOT NULL) THEN
                       'Required - Optional evaluation was started during fall'
                      WHEN (rec.semester = 'FAL' AND cohort.camp_code = 'D') THEN
                       'Optional - Optional evaluation can be started during fall once first course is complete'
                      WHEN (rec.semester = 'SPR' AND current_started.term_code < cohort.term_code AND prior_decision.term_code < current_started.term_code) THEN
                       'Pending - Prior term evaluation is in progress and must be completed first'
                      WHEN cohort.first_complete_date IS NULL THEN
                       'Pending - Evaluation should start after first course ends'
                      WHEN cohort.first_complete_date IS NOT NULL THEN
                       'Required - Evaluation process has started'
                      ELSE
                       'Unknown - If all else fails, try another approach...'
                      END AS status_desc,
                      SYSDATE AS activity_date
                 FROM utl_d_aa.fpt_cohort cohort
               -- GET PREVIOUS TEACHING TERMS 
                 LEFT JOIN (SELECT MAX(cohort.aidy_code) AS aidy_code,
                                  MAX(cohort.term_code) AS term_code,
                                  cohort.pidm,
                                  cohort.camp_code,
                                  cohort.coll_code
                             FROM utl_d_aa.fpt_cohort cohort
                            WHERE cohort.term_code < rec.term_code -- previous terms
                              AND cohort.camp_code = rec.camp_code
                            GROUP BY cohort.pidm,
                                     cohort.camp_code,
                                     cohort.coll_code) prior_term
               -- no term join here
                   ON prior_term.pidm = cohort.pidm
                  AND prior_term.camp_code = cohort.camp_code
                  AND prior_term.coll_code = cohort.coll_code
               -- GET FUTURE TEACHING TERMS 
                 LEFT JOIN (SELECT MAX(cohort.term_code) AS term_code,
                                  cohort.pidm,
                                  cohort.camp_code,
                                  cohort.coll_code
                             FROM utl_d_aa.fpt_cohort cohort
                            WHERE cohort.term_code > rec.term_code -- future terms
                              AND cohort.aidy_code = rec.aidy_code -- in same academic year
                              AND cohort.camp_code = rec.camp_code
                            GROUP BY cohort.pidm,
                                     cohort.camp_code,
                                     cohort.coll_code) futr_term
               -- no term join here
                   ON futr_term.pidm = cohort.pidm
                  AND futr_term.camp_code = cohort.camp_code
                  AND futr_term.coll_code = cohort.coll_code
               -- GET LATEST PREVIOUS TERM EVALUATIONS THAT HAD DECISIONS
                 LEFT JOIN (SELECT cohort.aidy_code,
                                  cohort.term_code,
                                  cohort.pidm,
                                  cohort.camp_code,
                                  cohort.coll_code,
                                  fea.evaluation_date, -- if date not null, the evaluation is complete (either dean or dire+sume)
                                  fea.evaluation_score, -- will dire show score as soon as we get it
                                  rank() over(PARTITION BY cohort.pidm, cohort.camp_code, cohort.coll_code ORDER BY cohort.term_code DESC) ranking
                             FROM utl_d_aa.fpt_cohort cohort
                             JOIN utl_d_aa.fpt_evaluations_audit fea
                               ON fea.term_code = cohort.term_code
                              AND fea.pidm = cohort.pidm
                              AND fea.camp_code = cohort.camp_code
                              AND fea.coll_code = cohort.coll_code
                              AND fea.category_code = 'DEAN' -- only check dean evaluation for completion; ensuring one row returns per pidm
                              AND (fea.status_color || fea.status_icon IN ('graycheck_mark', 'greenarrowhead', 'greencheck_mark') -- completed evaluation for dean evaluations
                                  OR fea.evaluation_score < 3) -- OR we do not have a dean evaluation and they failed 
                            WHERE cohort.term_code < rec.term_code -- get previous evaluations                            
                              AND cohort.camp_code = rec.camp_code) prior_decision
               -- no term join here
                   ON prior_decision.pidm = cohort.pidm
                  AND prior_decision.camp_code = cohort.camp_code
                  AND prior_decision.coll_code = cohort.coll_code
                  AND prior_decision.ranking = 1
               -- GET CURRENT EVALUATIONS STARTED
                 LEFT JOIN (SELECT MAX(cohort.term_code) AS term_code,
                                  cohort.pidm,
                                  cohort.camp_code,
                                  cohort.coll_code
                             FROM utl_d_aa.fpt_cohort cohort
                             JOIN utl_d_aa.fpt_evaluations_audit fea
                               ON fea.term_code = cohort.term_code
                              AND fea.pidm = cohort.pidm
                              AND fea.camp_code = cohort.camp_code
                              AND fea.coll_code = cohort.coll_code
                              AND fea.category_code NOT IN ('CURV') -- get ANY evaluations that have completion; distinct ensures one row returns per pidm
                              AND fea.evaluation_date IS NOT NULL -- evaluation was started 
                            WHERE cohort.term_code <= rec.term_code -- get current evaluations   
                              AND cohort.aidy_code = rec.aidy_code -- in same academic year                         
                              AND cohort.camp_code = rec.camp_code
                            GROUP BY cohort.pidm,
                                     cohort.camp_code,
                                     cohort.coll_code) current_started
                   ON current_started.pidm = cohort.pidm
                  AND current_started.camp_code = cohort.camp_code
                  AND current_started.coll_code = cohort.coll_code
                WHERE 1 = 1
                  AND cohort.term_code = rec.term_code
                  AND cohort.camp_code = rec.camp_code) src
         LEFT JOIN utl_d_aa.fpt_evaluations_status tgt
           ON tgt.term_code = src.term_code
          AND tgt.pidm = src.pidm
          AND tgt.camp_code = src.camp_code
          AND tgt.coll_code = src.coll_code
        WHERE 1 = 1
          AND (tgt.pidm IS NULL -- missing from target table
              OR coalesce(tgt.last_term_completed, 'X') <> coalesce(src.last_term_completed, 'X') --
              OR coalesce(tgt.last_term_evaluation, 0) <> coalesce(src.last_term_evaluation, 0) -- 
              OR coalesce(tgt.status, 'X') <> coalesce(src.status, 'X') --
              OR coalesce(tgt.status_desc, 'X') <> coalesce(src.status_desc, 'X') --
              OR trunc(coalesce(tgt.activity_date, SYSDATE)) <> trunc(coalesce(src.activity_date, SYSDATE)) -- !!! force a daily refresh !!!
              )) src
ON (tgt.term_code = src.term_code AND tgt.camp_code = src.camp_code AND tgt.coll_code = src.coll_code AND tgt.pidm = src.pidm)
WHEN MATCHED THEN
UPDATE
   SET tgt.last_term_completed  = src.last_term_completed,
       tgt.last_term_evaluation = src.last_term_evaluation,
       tgt.status               = src.status,
       tgt.status_desc          = src.status_desc,
       tgt.activity_date        = src.activity_date
WHEN NOT MATCHED THEN
INSERT
(aidy_code,
 term_code,
 pidm,
 camp_code,
 coll_code,
 last_term_completed,
 last_term_evaluation,
 status,
 status_desc,
 activity_date)
VALUES
(src.aidy_code,
 src.term_code,
 src.pidm,
 src.camp_code,
 src.coll_code,
 src.last_term_completed,
 src.last_term_evaluation,
 src.status,
 src.status_desc,
 src.activity_date);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || rec.term_code || ' - ' || rec.camp_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
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
ROLLBACK;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
END etl_aa_fpt_evaluations_status;

PROCEDURE etl_aa_fpt_evaluations_audit_curv(jobnumber NUMBER, processid VARCHAR2, processname VARCHAR2) IS
/*
Table: utl_d_lms.fpt_evaluations_audit

Primary Keys: NONE

Unique index: UNIQUE_ID

Purpose: Main auditing that tracks FPT certs and assessments showing the progress of each phase

Conditions: CVs are not term based, so we have to use a date range; CV certs open on JAN 1 - MAY 15

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
v_proc        VARCHAR2(100) := 'etl_aa_fpt_evaluations_audit_curv';
v_cat_code    VARCHAR2(4) := 'CURV';
CURSOR c_terms IS
SELECT DISTINCT fes.term_code,
                fes.aidy_code,
                fes.start_date,
                fes.end_date,
                fes.semester,
                fes.semester_desc,
                fes.cv_start_date,
                fes.cv_end_date
  FROM utl_d_aa.fpt_evaluations_schedule fes
 ORDER BY 1,
          3;
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
MERGE INTO utl_d_aa.fpt_evaluations_audit tgt
USING (SELECT src.aidy_code,
              src.term_code,
              src.pidm,
              src.camp_code,
              src.coll_code,
              src.approver,
              src.approver_username,
              src.approver_position,
              src.category_code,
              src.status_color,
              src.status_icon,
              src.status_desc,
              src.url,
              src.unique_id,
              src.evaluation_date,
              src.activity_date
         FROM (SELECT cohort.aidy_code,
                      cohort.term_code,
                      cohort.pidm,
                      cohort.camp_code,
                      cohort.coll_code,
                      cohort.coll_desc,
                      cohort.email_address AS email_address,
                      cohort.instructor AS approver,
                      cohort.instructor_username AS approver_username,
                      'Faculty' AS approver_position,
                      v_cat_code AS category_code,
                      CASE
                      WHEN curv.cv_submitted IS NOT NULL THEN -- EVALUATION COMPLETE
                       'green'
                      WHEN curv.cv_submitted IS NULL
                           AND v_etl_date > rec.cv_end_date THEN
                       'red'
                      WHEN curv.cv_submitted IS NULL
                           AND v_etl_date BETWEEN rec.cv_start_date AND rec.cv_end_date THEN
                       'yellow'
                      ELSE
                       'gray' -- OUTSIDE OF TIMEFRAME TO SUBMIT A CV
                      END AS status_color,
                      CASE
                      WHEN curv.cv_submitted IS NOT NULL THEN -- EVALUATION COMPLETE
                       'check_mark'
                      WHEN curv.cv_submitted IS NULL
                           AND v_etl_date > rec.cv_end_date THEN
                       'x-ray'
                      WHEN curv.cv_submitted IS NULL
                           AND v_etl_date BETWEEN rec.cv_start_date AND rec.cv_end_date THEN
                       'exclamation'
                      ELSE
                       'clock' -- OUTSIDE OF TIMEFRAME TO SUBMIT A CV
                      END AS status_icon,
                      CASE
                      WHEN curv.cv_submitted IS NOT NULL THEN -- EVALUATION COMPLETE
                       'CV was certified on ' || to_char(curv.cv_submitted, 'MM/DD/YYYY')
                      WHEN curv.cv_submitted IS NULL
                           AND v_etl_date > rec.cv_end_date THEN
                       'CV certification must be submitted before ' || to_char(rec.cv_end_date, 'MM/DD/YYYY')
                      WHEN curv.cv_submitted IS NULL
                           AND v_etl_date BETWEEN rec.cv_start_date AND rec.cv_end_date THEN
                       'CV certification must be submitted before ' || to_char(rec.cv_end_date, 'MM/DD/YYYY')
                      ELSE
                       'CV certification opens on ' || to_char(rec.cv_start_date, 'MM/DD/YYYY') || ' and ends on ' || to_char(rec.cv_end_date, 'MM/DD/YYYY')
                      END status_desc,
                      'https://facultyportfolio.liberty.edu/cv/' || cohort.pidm AS url,
                      standard_hash(v_cat_code || cohort.term_code || cohort.pidm || cohort.camp_code || cohort.coll_code, 'MD5') unique_id,
                      curv.cv_submitted AS evaluation_date,
                      v_etl_date AS activity_date
                 FROM utl_d_aa.fpt_cohort cohort
                 LEFT JOIN (SELECT cv2.portfolio,
                                  MIN(cv2.certified_date) AS cv_submitted -- unlimited completions allowed; there is not a term on this table, but we look for the first CV submission
                             FROM zfacultyportfolio.cv_v2 cv2
                            WHERE cv2.certified_date BETWEEN rec.cv_start_date AND rec.cv_end_date
                            GROUP BY cv2.portfolio) curv
                   ON curv.portfolio = cohort.portfolio
                WHERE 1 = 1
                  AND cohort.term_code = rec.term_code) src
         LEFT JOIN utl_d_aa.fpt_evaluations_audit tgt
           ON tgt.unique_id = standard_hash(v_cat_code || src.term_code || src.pidm || src.camp_code || src.coll_code, 'MD5') --unique_id
        WHERE 1 = 1
          AND (tgt.pidm IS NULL -- missing from target table
              OR coalesce(tgt.approver, 'X') <> coalesce(src.approver, 'X') --
              OR coalesce(tgt.approver_username, 'X') <> coalesce(src.approver_username, 'X') --
              OR coalesce(tgt.approver_position, 'X') <> coalesce(src.approver_position, 'X') --
              OR coalesce(tgt.category_code, 'X') <> coalesce(src.category_code, 'X') --
              OR coalesce(tgt.status_color, 'X') <> coalesce(src.status_color, 'X') --
              OR coalesce(tgt.status_icon, 'X') <> coalesce(src.status_icon, 'X') --
              OR coalesce(tgt.status_desc, 'X') <> coalesce(src.status_desc, 'X') --
              OR coalesce(tgt.url, 'X') <> coalesce(src.url, 'X') --
              OR coalesce(tgt.evaluation_date, v_etl_date) <> coalesce(src.evaluation_date, v_etl_date) --
              )) src
ON (tgt.unique_id = src.unique_id)
WHEN MATCHED THEN
UPDATE
   SET tgt.aidy_code         = src.aidy_code,
       tgt.term_code         = src.term_code,
       tgt.pidm              = src.pidm,
       tgt.camp_code         = src.camp_code,
       tgt.coll_code         = src.coll_code,
       tgt.approver          = src.approver,
       tgt.approver_username = src.approver_username,
       tgt.approver_position = src.approver_position,
       tgt.category_code     = src.category_code,
       tgt.status_color      = src.status_color,
       tgt.status_icon       = src.status_icon,
       tgt.status_desc       = src.status_desc,
       tgt.url               = src.url,
       tgt.evaluation_date   = src.evaluation_date,
       tgt.activity_date     = src.activity_date
WHEN NOT MATCHED THEN
INSERT
(aidy_code,
 term_code,
 pidm,
 camp_code,
 coll_code,
 approver,
 approver_username,
 approver_position,
 category_code,
 status_color,
 status_icon,
 status_desc,
 url,
 unique_id,
 evaluation_date,
 activity_date)
VALUES
(src.aidy_code,
 src.term_code,
 src.pidm,
 src.camp_code,
 src.coll_code,
 src.approver,
 src.approver_username,
 src.approver_position,
 src.category_code,
 src.status_color,
 src.status_icon,
 src.status_desc,
 src.url,
 src.unique_id,
 src.evaluation_date,
 src.activity_date);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
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
ROLLBACK;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
END etl_aa_fpt_evaluations_audit_curv;
PROCEDURE etl_aa_fpt_evaluations_audit_self(jobnumber NUMBER, processid VARCHAR2, processname VARCHAR2) IS
/*
Table: utl_d_lms.fpt_evaluations_audit

Primary Keys: NONE

Unique index: UNIQUE_ID

Purpose: Main auditing that tracks FPT certs and evaluations showing the progress of each phase

Conditions:
- Online Requirements for meets expectations in prior evaluation: Self (SE) evaluations are optional after the first course concludes; but required after springb_end_date
- Online Requirements for does NOT meet expectations in prior evaluation: Self (SE) evaluations are required after the first course concludes
- Resident requirements: Self (SE) evaluations are required on SEPT 1 - SEPT 20

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
v_proc        VARCHAR2(100) := 'etl_aa_fpt_evaluations_audit_self';
v_cat_code    VARCHAR2(4) := 'SELF';
CURSOR c_terms IS
SELECT fes.*
  FROM utl_d_aa.fpt_evaluations_schedule fes
 ORDER BY 1,
          3;
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
v_msg     := 'START - ' || rec.term_code || ' - ' || rec.camp_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
MERGE INTO utl_d_aa.fpt_evaluations_audit tgt
USING (SELECT src.aidy_code,
              src.term_code,
              src.pidm,
              src.camp_code,
              src.coll_code,
              src.approver,
              src.approver_username,
              src.approver_position,
              src.category_code,
              src.status_color,
              src.status_icon,
              src.status_desc,
              src.url,
              src.unique_id,
              src.evaluation_date,
              src.evaluation_score,
              src.activity_date
         FROM (SELECT cohort.aidy_code,
                       cohort.term_code,
                       cohort.pidm,
                       cohort.camp_code,
                       cohort.coll_code,
                       cohort.coll_desc,
                       cohort.email_address, 
                       cohort.instructor AS approver,
                       cohort.instructor_username AS approver_username,
                       'Faculty' AS approver_position,
                       v_cat_code AS category_code,
                       CASE
                       WHEN self_eval.evaluation_completed IS NOT NULL THEN -- EVALUATION COMPLETE
                        'green'
                       WHEN fes.status = 'Not Required' THEN
                        'gray'
                       WHEN fes.status = 'Pending' THEN
                        'gray'
                       WHEN fes.status = 'Optional' THEN
                        'blue'
                       -- first time teaching Required
                       WHEN fes.status = 'Required'
                            AND fes.status_desc = 'Required - Initial term'
                            AND v_etl_date >= cohort.first_complete_date + 21 THEN
                        'red'
                       WHEN fes.status = 'Required'
                            AND fes.status_desc = 'Required - Initial term'
                            AND v_etl_date >= cohort.first_complete_date + 7 THEN
                        'yellow'
                       WHEN fes.status = 'Required'
                            AND fes.status_desc = 'Required - Initial term'
                            AND v_etl_date < cohort.first_complete_date + 7 THEN
                        'gray'
                       -- all else Required
                       WHEN fes.status = 'Required'
                            AND v_etl_date >= rec.dire_start_date THEN
                        'red'
                       WHEN fes.status = 'Required'
                            AND v_etl_date >= rec.self_start_date THEN
                        'yellow'
                       WHEN fes.status = 'Retroactive'
                            AND v_etl_date >= rec.retro_dire_start_date THEN -- if they taught in fall but not spring or first course ended after the spring evaluations start
                        'red'
                       WHEN fes.status = 'Retroactive'
                            AND v_etl_date >= rec.retro_self_start_date THEN -- if they taught in fall but not spring or first course ended after the spring evaluations start
                        'yellow'
                       WHEN fes.status = 'Required'
                            AND v_etl_date < rec.self_start_date THEN
                        'blue'
                       ELSE
                        'gray' -- no evaluation completed by faculty
                       END AS status_color,
                       CASE
                       WHEN self_eval.evaluation_completed IS NOT NULL THEN -- EVALUATION COMPLETE
                        'check_mark'
                       WHEN fes.status = 'Not Required' THEN
                        'minus'
                       WHEN fes.status = 'Pending' THEN
                        'clock'
                       WHEN fes.status = 'Optional' THEN
                        'clock'
                       -- first time teaching Required
                       WHEN fes.status = 'Required'
                            AND fes.status_desc = 'Required - Initial term'
                            AND v_etl_date >= cohort.first_complete_date + 21 THEN
                        'x-ray'
                       WHEN fes.status = 'Required'
                            AND fes.status_desc = 'Required - Initial term'
                            AND v_etl_date >= cohort.first_complete_date + 7 THEN
                        'exclamation'
                       WHEN fes.status = 'Required'
                            AND fes.status_desc = 'Required - Initial term'
                            AND v_etl_date < cohort.first_complete_date + 7 THEN
                        'clock'
                       -- all else Required
                       WHEN fes.status = 'Required'
                            AND v_etl_date >= rec.dire_start_date THEN
                        'x-ray'
                       WHEN fes.status = 'Required'
                            AND v_etl_date >= rec.self_start_date THEN
                        'exclamation'
                       WHEN fes.status = 'Retroactive'
                            AND v_etl_date >= rec.retro_dire_start_date THEN
                        'x-ray'
                       WHEN fes.status = 'Retroactive'
                            AND v_etl_date >= rec.retro_self_start_date THEN
                        'exclamation'
                       WHEN fes.status = 'Required'
                            AND v_etl_date < rec.self_start_date THEN
                        'clock'
                       ELSE
                        'clock' -- no evaluation completed by faculty
                       END AS status_icon,
                       CASE
                       WHEN self_eval.evaluation_completed IS NOT NULL THEN -- EVALUATION COMPLETE
                        '1. Self evaluation for ' || rec.semester_desc || ' was completed by ' || cohort.instructor_username || ' on ' || to_char(self_eval.evaluation_completed, 'MM/DD/YYYY')
                       WHEN fes.status = 'Not Required' THEN
                        '1. Self evaluations for ' || rec.semester_desc || ' are not required'
                       WHEN fes.status = 'Pending'
                            AND fes.camp_code = 'D' THEN
                        '1. Self evaluations for ' || rec.semester_desc || ' are not ready to begin'
                       WHEN fes.status = 'Pending'
                            AND fes.camp_code = 'R' THEN
                        '1. Self evaluations for ' || rec.semester_desc || ' begin on ' || to_char(rec.self_start_date, 'MM/DD/YYYY')
                       WHEN fes.status = 'Optional' THEN
                        '1. Self evaluations for ' || rec.semester_desc || ' are available but not required'
                       -- first time teaching Required
                       WHEN fes.status = 'Required'
                            AND fes.status_desc = 'Required - Initial term'
                            AND v_etl_date >= cohort.first_complete_date + 21 THEN
                        '1. Self evaluations for ' || rec.semester_desc || ' must be completed before ' || to_char(cohort.first_complete_date + 21, 'MM/DD/YYYY')
                       WHEN fes.status = 'Required'
                            AND fes.status_desc = 'Required - Initial term'
                            AND v_etl_date >= cohort.first_complete_date + 7 THEN
                        '1. Self evaluations for ' || rec.semester_desc || ' must be completed before ' || to_char(cohort.first_complete_date + 21, 'MM/DD/YYYY')
                       WHEN fes.status = 'Required'
                            AND fes.status_desc = 'Required - Initial term'
                            AND v_etl_date < cohort.first_complete_date + 7 THEN
                        '1. Self evaluations for ' || rec.semester_desc || ' will be required after ' || to_char(cohort.first_complete_date + 7, 'MM/DD/YYYY')
                       -- all else Required
                       WHEN fes.status = 'Required'
                            AND v_etl_date >= rec.dire_start_date THEN
                        '1. Self evaluations for ' || rec.semester_desc || ' must be completed before ' || to_char(rec.dire_start_date, 'MM/DD/YYYY')
                       WHEN fes.status = 'Required'
                            AND v_etl_date >= rec.self_start_date THEN
                        '1. Self evaluations for ' || rec.semester_desc || ' must be completed before ' || to_char(rec.dire_start_date, 'MM/DD/YYYY')
                       WHEN fes.status = 'Retroactive'
                            AND v_etl_date >= rec.retro_dire_start_date THEN
                        '1. Self evaluations for ' || rec.semester_desc || ' must be completed before ' || to_char(rec.retro_dire_start_date, 'MM/DD/YYYY')
                       WHEN fes.status = 'Retroactive'
                            AND v_etl_date >= rec.retro_self_start_date THEN
                        '1. Self evaluations for ' || rec.semester_desc || ' must be completed before ' || to_char(rec.retro_dire_start_date, 'MM/DD/YYYY')
                       WHEN fes.status = 'Required'
                            AND v_etl_date < rec.self_start_date THEN
                        '1. Self evaluations for ' || rec.semester_desc || ' will be required after ' || to_char(rec.self_start_date, 'MM/DD/YYYY')
                       ELSE
                        '1. Self evaluation for ' || rec.semester_desc || ' will be needed for ' || cohort.instructor_username
                       END AS status_desc,
                       'https://facultyportfolio.liberty.edu/evaluations/' || cohort.pidm || '/' || rec.fpt_term_code AS url,
                       standard_hash(v_cat_code || cohort.term_code || cohort.pidm || cohort.camp_code || cohort.coll_code, 'MD5') unique_id,
                       self_eval.evaluation_completed AS evaluation_date,
                       CASE
                        WHEN self_eval.evaluation_completed IS NOT NULL
                             AND self_eval.evaluation_score IS NULL THEN
                         3 -- rare, but sometimes we don't get any scores back, so default to passing since this is self evaluations
                      ELSE
                       self_eval.evaluation_score
                      END AS evaluation_score,
                      v_etl_date AS activity_date
                 FROM utl_d_aa.fpt_cohort cohort
                 JOIN utl_d_aa.fpt_evaluations_status fes
                   ON fes.term_code = cohort.term_code
                  AND fes.pidm = cohort.pidm
                  AND fes.camp_code = cohort.camp_code
                  AND fes.coll_code = cohort.coll_code
                 LEFT JOIN (SELECT assessment.portfolio,
                                  assessment.id AS assessment_id,
                                  rec.term_code AS term_code,
                                  assessment.campus AS camp_code,
                                  assessment.activity_date AS evaluation_completed,
                                  gobtpac_external_user AS approver_username, 
                                  resp.question_choice AS evaluation_score,
                                  rank() over(PARTITION BY assessment.term, assessment.campus, assessment.portfolio ORDER BY assessment.activity_date ASC, nvl(resp.question_choice, 0) ASC, rownum) ranking -- get first evaluation and lowest score
                             FROM zfacultyportfolio.assessment
                             LEFT JOIN zfacultyportfolio.question_response resp
                               ON resp.assessment = assessment.id
                             LEFT JOIN general.gobtpac
                               ON gobtpac_pidm = assessment.pidm
                            WHERE assessment.assessmenttype = 1 -- faculty self evaluation
                              AND assessment.completed = 'Y' -- all questions answered
                              AND assessment.term = rec.fpt_term_code -- fpt_term_code here  
                              AND assessment.campus = rec.camp_code) self_eval
                   ON self_eval.term_code = cohort.term_code
                  AND self_eval.camp_code = cohort.camp_code
                  AND self_eval.portfolio = cohort.portfolio
                  AND self_eval.ranking = 1
                WHERE 1 = 1
                  AND cohort.term_code = rec.term_code
                  AND cohort.camp_code = rec.camp_code) src
         LEFT JOIN utl_d_aa.fpt_evaluations_audit tgt
           ON tgt.unique_id = standard_hash(v_cat_code || src.term_code || src.pidm || src.camp_code || src.coll_code, 'MD5') --unique_id
        WHERE 1 = 1
          AND (tgt.pidm IS NULL -- missing from target table
              OR coalesce(tgt.approver, 'X') <> coalesce(src.approver, 'X') --
              OR coalesce(tgt.approver_username, 'X') <> coalesce(src.approver_username, 'X') --
              OR coalesce(tgt.approver_position, 'X') <> coalesce(src.approver_position, 'X') --
              OR coalesce(tgt.category_code, 'X') <> coalesce(src.category_code, 'X') --
              OR coalesce(tgt.status_color, 'X') <> coalesce(src.status_color, 'X') --
              OR coalesce(tgt.status_icon, 'X') <> coalesce(src.status_icon, 'X') --
              OR coalesce(tgt.status_desc, 'X') <> coalesce(src.status_desc, 'X') --
              OR coalesce(tgt.url, 'X') <> coalesce(src.url, 'X') --
              OR coalesce(tgt.evaluation_score, 0) <> coalesce(src.evaluation_score, 0) --
              OR coalesce(tgt.evaluation_date, v_etl_date) <> coalesce(src.evaluation_date, v_etl_date) --
              )) src
ON (tgt.unique_id = src.unique_id)
WHEN MATCHED THEN
UPDATE
   SET tgt.aidy_code         = src.aidy_code,
       tgt.term_code         = src.term_code,
       tgt.pidm              = src.pidm,
       tgt.camp_code         = src.camp_code,
       tgt.coll_code         = src.coll_code,
       tgt.approver          = src.approver,
       tgt.approver_username = src.approver_username,
       tgt.approver_position = src.approver_position,
       tgt.category_code     = src.category_code,
       tgt.status_color      = src.status_color,
       tgt.status_icon       = src.status_icon,
       tgt.status_desc       = src.status_desc,
       tgt.url               = src.url,
       tgt.evaluation_score  = src.evaluation_score,
       tgt.evaluation_date   = src.evaluation_date,
       tgt.activity_date     = src.activity_date
WHEN NOT MATCHED THEN
INSERT
(aidy_code,
 term_code,
 pidm,
 camp_code,
 coll_code,
 approver,
 approver_username,
 approver_position,
 category_code,
 status_color,
 status_icon,
 status_desc,
 url,
 unique_id,
 evaluation_date,
 evaluation_score,
 activity_date)
VALUES
(src.aidy_code,
 src.term_code,
 src.pidm,
 src.camp_code,
 src.coll_code,
 src.approver,
 src.approver_username,
 src.approver_position,
 src.category_code,
 src.status_color,
 src.status_icon,
 src.status_desc,
 src.url,
 src.unique_id,
 src.evaluation_date,
 src.evaluation_score,
 src.activity_date);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || v_cat_code || ' - ' || rec.term_code || ' - ' || rec.camp_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
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
ROLLBACK;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
END etl_aa_fpt_evaluations_audit_self;
PROCEDURE etl_aa_fpt_evaluations_audit_dire(jobnumber NUMBER, processid VARCHAR2, processname VARCHAR2) IS
/*
Table: utl_d_lms.fpt_evaluations_audit

Primary Keys: NONE

Unique index: UNIQUE_ID

Purpose: Main auditing that tracks FPT certs and evaluations showing the progress of each phase

Conditions:
- Online Requirements for meets expectations in prior evaluation: Chair (CH) evaluations are required 28 days after SE is completed or 49 days after springb_end_date
- Online Requirements for does NOT meet expectations in prior evaluation: Chair (CH) evaluations are required 28 days after SE is completed or 49 days after springb_end_date
- Resident requirements: Chair (CH) evaluations are required on SEPT 20 - OCT 1

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
v_proc        VARCHAR2(100) := 'etl_aa_fpt_evaluations_audit_dire';
v_cat_code    VARCHAR2(4) := 'DIRE';
CURSOR c_terms IS
SELECT fes.*
  FROM utl_d_aa.fpt_evaluations_schedule fes
 ORDER BY 1,
          3;
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
v_msg     := 'START - ' || rec.term_code || ' - ' || rec.camp_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
MERGE INTO utl_d_aa.fpt_evaluations_audit tgt
USING (SELECT src.aidy_code,
              src.term_code,
              src.pidm,
              src.camp_code,
              src.coll_code,
              src.approver,
              src.approver_username,
              src.approver_position,
              src.category_code,
              src.status_color,
              src.status_icon,
              src.status_desc,
              src.url,
              src.unique_id,
              src.evaluation_date,
              src.evaluation_score,
              src.activity_date
         FROM (SELECT cohort.aidy_code,
                       cohort.term_code,
                       cohort.pidm,
                       cohort.camp_code,
                       cohort.coll_code,
                       cohort.coll_desc,
                       cohort.instructor,
                       cohort.instructor_username AS user_name,
                       cohort.email_address,
                       nvl(dire_eval.approver, fht.superior) AS approver,
                       nvl(dire_eval.approver_username, fht.superior_username) AS approver_username,
                       nvl(dire_eval.approver_position, fht.superior_position) AS approver_position,
                       v_cat_code AS category_code,
                       CASE
                       WHEN cohort.camp_code = 'R'
                            AND cohort.term_code <= '202420' -- direct assessments were broken for resident in 202420
                        THEN
                        'gray'
                       WHEN dire_eval.evaluation_completed IS NOT NULL -- EVALUATION COMPLETE
                        THEN
                        'green'
                       -- first time teaching Required
                       WHEN fes.status = 'Required'
                            AND fes.status_desc = 'Required - Initial term'
                            AND v_etl_date >= cohort.first_complete_date + 35
                            AND dire_eval.evaluation_completed IS NULL THEN
                        'red'
                       WHEN fes.status = 'Required'
                            AND fes.status_desc = 'Required - Initial term'
                            AND (v_etl_date >= cohort.first_complete_date + 21 OR self_eval.evaluation_completed IS NOT NULL)
                            AND dire_eval.evaluation_completed IS NULL THEN
                        'yellow'
                       WHEN fes.status = 'Required'
                            AND fes.status_desc = 'Required - Initial term'
                            AND v_etl_date < cohort.first_complete_date + 21 THEN
                        'gray'
                       -- all else Required
                       WHEN fes.status = 'Required'
                            AND v_etl_date >= rec.sume_start_date
                            AND dire_eval.evaluation_completed IS NULL THEN
                        'red'
                       WHEN fes.status = 'Required'
                            AND (v_etl_date >= rec.dire_start_date OR self_eval.evaluation_completed IS NOT NULL)
                            AND dire_eval.evaluation_completed IS NULL THEN
                        'yellow'
                       WHEN fes.status = 'Retroactive'
                            AND v_etl_date >= rec.retro_sume_start_date
                            AND dire_eval.evaluation_completed IS NULL THEN
                        'red'
                       WHEN fes.status = 'Retroactive'
                            AND (v_etl_date >= rec.retro_dire_start_date OR self_eval.evaluation_completed IS NOT NULL)
                            AND dire_eval.evaluation_completed IS NULL THEN
                        'yellow'
                       WHEN fes.status = 'Retroactive'
                            AND v_etl_date < rec.retro_dire_start_date
                            AND dire_eval.evaluation_completed IS NULL THEN
                        'gray'
                       WHEN self_eval.evaluation_completed + 14 < v_etl_date + 1 -- completed the optional self evaluation; self_approved_date is null otherwise
                            AND dire_eval.evaluation_completed IS NULL -- no eval completed yet
                        THEN
                        'red'
                       WHEN self_eval.evaluation_completed < v_etl_date + 1 -- completed the optional self evaluation; self_approved_date is null otherwise
                            AND dire_eval.evaluation_completed IS NULL -- no eval completed yet
                        THEN
                        'yellow'
                       WHEN fes.status = 'Required'
                            AND v_etl_date < rec.dire_start_date
                            AND dire_eval.evaluation_completed IS NULL THEN
                        'gray'
                       WHEN fes.status = 'Not Required' THEN
                        'gray'
                       WHEN fes.status = 'Pending' THEN
                        'gray'
                       WHEN fes.status = 'Optional' THEN
                        'gray'
                       END AS status_color,
                       CASE
                       WHEN cohort.camp_code = 'R'
                            AND cohort.term_code <= '202420' -- direct assessments were broken for resident in 202420
                        THEN
                        'minus'
                       WHEN dire_eval.evaluation_completed IS NOT NULL -- EVALUATION COMPLETE
                        THEN
                        'check_mark'
                       -- first time teaching Required
                       WHEN fes.status = 'Required'
                            AND fes.status_desc = 'Required - Initial term'
                            AND v_etl_date >= cohort.first_complete_date + 35
                            AND dire_eval.evaluation_completed IS NULL THEN
                        'x-ray'
                       WHEN fes.status = 'Required'
                            AND fes.status_desc = 'Required - Initial term'
                            AND (v_etl_date >= cohort.first_complete_date + 21 OR self_eval.evaluation_completed IS NOT NULL)
                            AND dire_eval.evaluation_completed IS NULL THEN
                        'exclamation'
                       WHEN fes.status = 'Required'
                            AND fes.status_desc = 'Required - Initial term'
                            AND v_etl_date < cohort.first_complete_date + 21 THEN
                        'clock'
                       -- all else Required
                       WHEN fes.status = 'Required'
                            AND v_etl_date >= rec.sume_start_date
                            AND dire_eval.evaluation_completed IS NULL THEN
                        'x-ray'
                       WHEN fes.status = 'Required'
                            AND (v_etl_date >= rec.dire_start_date OR self_eval.evaluation_completed IS NOT NULL)
                            AND dire_eval.evaluation_completed IS NULL THEN
                        'exclamation'
                       WHEN fes.status = 'Retroactive'
                            AND v_etl_date >= rec.retro_sume_start_date
                            AND dire_eval.evaluation_completed IS NULL THEN
                        'x-ray'
                       WHEN fes.status = 'Retroactive'
                            AND (v_etl_date >= rec.retro_dire_start_date OR self_eval.evaluation_completed IS NOT NULL)
                            AND dire_eval.evaluation_completed IS NULL THEN
                        'exclamation'
                       WHEN fes.status = 'Retroactive'
                            AND v_etl_date < rec.retro_dire_start_date
                            AND dire_eval.evaluation_completed IS NULL THEN
                        'clock'
                       WHEN self_eval.evaluation_completed + 14 < v_etl_date + 1 -- completed the optional self evaluation; self_approved_date is null otherwise
                            AND dire_eval.evaluation_completed IS NULL -- no eval completed yet
                        THEN
                        'x-ray'
                       WHEN self_eval.evaluation_completed < v_etl_date + 1 -- completed the optional self evaluation; self_approved_date is null otherwise
                            AND dire_eval.evaluation_completed IS NULL -- no eval completed yet
                        THEN
                        'exclamation'
                       WHEN fes.status = 'Required'
                            AND v_etl_date < rec.dire_start_date
                            AND dire_eval.evaluation_completed IS NULL THEN
                        'clock'
                       WHEN fes.status = 'Not Required' THEN
                        'minus'
                       WHEN fes.status = 'Pending' THEN
                        'clock'
                       WHEN fes.status = 'Optional' THEN
                        'clock'
                       END AS status_icon,
                       CASE
                       WHEN cohort.camp_code = 'R'
                            AND cohort.term_code <= '202420' -- direct assessments were broken for resident in 202420
                        THEN
                        '2. Direct evaluations were broken for resident in Spring 2024'
                       WHEN dire_eval.evaluation_completed IS NOT NULL -- EVALUATION COMPLETE
                        THEN
                        '2. Direct evaluation for ' || rec.semester_desc || ' was completed by ' || dire_eval.approver_username || ' on ' || to_char(dire_eval.evaluation_completed, 'MM/DD/YYYY')
                       -- first time teaching Required
                       WHEN fes.status = 'Required'
                            AND fes.status_desc = 'Required - Initial term'
                            AND v_etl_date >= cohort.first_complete_date + 35
                            AND dire_eval.evaluation_completed IS NULL THEN
                        '2. Direct evaluations for ' || rec.semester_desc || ' must be completed ' || nvl2(fht.superior_username, 'by ' || fht.superior_username || ' before ', 'before ') || to_char(cohort.first_complete_date + 35, 'MM/DD/YYYY')
                       WHEN fes.status = 'Required'
                            AND fes.status_desc = 'Required - Initial term'
                            AND (v_etl_date >= cohort.first_complete_date + 21 OR self_eval.evaluation_completed IS NOT NULL)
                            AND dire_eval.evaluation_completed IS NULL THEN
                        '2. Direct evaluations for ' || rec.semester_desc || ' must be completed ' || nvl2(fht.superior_username, 'by ' || fht.superior_username || ' before ', 'before ') || to_char(cohort.first_complete_date + 35, 'MM/DD/YYYY')
                       WHEN fes.status = 'Required'
                            AND fes.status_desc = 'Required - Initial term'
                            AND v_etl_date < cohort.first_complete_date + 21 THEN
                        '2. Direct evaluations for ' || rec.semester_desc || ' will be required after ' || to_char(cohort.first_complete_date + 21, 'MM/DD/YYYY')
                       -- all else Required
                       WHEN fes.status = 'Required'
                            AND v_etl_date >= rec.sume_start_date
                            AND dire_eval.evaluation_completed IS NULL THEN
                        '2. Direct evaluations for ' || rec.semester_desc || ' must be completed ' || nvl2(fht.superior_username, 'by ' || fht.superior_username || ' before ', 'before ') || to_char(rec.sume_start_date, 'MM/DD/YYYY')
                       WHEN fes.status = 'Required'
                            AND (v_etl_date >= rec.dire_start_date OR self_eval.evaluation_completed IS NOT NULL)
                            AND dire_eval.evaluation_completed IS NULL THEN
                        '2. Direct evaluations for ' || rec.semester_desc || ' must be completed ' || nvl2(fht.superior_username, 'by ' || fht.superior_username || ' before ', 'before ') || to_char(rec.sume_start_date, 'MM/DD/YYYY')
                       WHEN fes.status = 'Retroactive'
                            AND v_etl_date >= rec.retro_sume_start_date
                            AND dire_eval.evaluation_completed IS NULL THEN
                        '2. Direct evaluations for ' || rec.semester_desc || ' must be completed ' || nvl2(fht.superior_username, 'by ' || fht.superior_username || ' before ', 'before ') || to_char(rec.retro_sume_start_date, 'MM/DD/YYYY')
                       WHEN fes.status = 'Retroactive'
                            AND (v_etl_date >= rec.retro_dire_start_date OR self_eval.evaluation_completed IS NOT NULL)
                            AND dire_eval.evaluation_completed IS NULL THEN
                        '2. Direct evaluations for ' || rec.semester_desc || ' must be completed ' || nvl2(fht.superior_username, 'by ' || fht.superior_username || ' before ', 'before ') || to_char(rec.retro_sume_start_date, 'MM/DD/YYYY')
                       WHEN fes.status = 'Retroactive'
                            AND v_etl_date < rec.retro_dire_start_date
                            AND dire_eval.evaluation_completed IS NULL THEN
                        '2. Direct evaluations for ' || rec.semester_desc || ' will begin on ' || to_char(rec.retro_dire_start_date, 'MM/DD/YYYY')
                       WHEN self_eval.evaluation_completed + 14 < v_etl_date + 1 -- completed the optional self evaluation; self_approved_date is null otherwise
                            AND dire_eval.evaluation_completed IS NULL -- no eval completed yet
                        THEN
                        '2. Direct evaluations for ' || rec.semester_desc || ' must be completed ' || nvl2(fht.superior_username, 'by ' || fht.superior_username || ' before ', 'before ') ||
                        to_char(self_eval.evaluation_completed + 14, 'MM/DD/YYYY') -- same date for yellow and reds
                       WHEN self_eval.evaluation_completed < v_etl_date + 1 -- completed the optional self evaluation; self_approved_date is null otherwise
                            AND dire_eval.evaluation_completed IS NULL -- no eval completed yet
                        THEN
                        '2. Direct evaluations for ' || rec.semester_desc || ' must be completed ' || nvl2(fht.superior_username, 'by ' || fht.superior_username || ' before ', 'before ') ||
                        to_char(self_eval.evaluation_completed + 14, 'MM/DD/YYYY') -- same date for yellow and reds
                       WHEN fes.status = 'Required'
                            AND v_etl_date < rec.dire_start_date
                            AND dire_eval.evaluation_completed IS NULL THEN
                        '2. Direct evaluations for ' || rec.semester_desc || ' will begin on ' || to_char(rec.dire_start_date, 'MM/DD/YYYY')
                       WHEN fes.status = 'Not Required' THEN
                        '2. Direct evaluations for ' || rec.semester_desc || ' are not required'
                       WHEN fes.status = 'Pending'
                            AND fes.camp_code = 'D' THEN
                        'Self evaluations for ' || rec.semester_desc || ' are not ready to begin'
                       WHEN fes.status = 'Pending'
                            AND fes.camp_code = 'R' THEN
                        'Self evaluations for ' || rec.semester_desc || ' begin on ' || to_char(rec.self_start_date, 'MM/DD/YYYY')
                       WHEN fes.status = 'Optional' THEN
                        'Self evaluations for ' || rec.semester_desc || ' are available but not required'
                       END AS status_desc,
                       'https://facultyportfolio.liberty.edu/evaluations/' || cohort.pidm || '/' || rec.fpt_term_code AS url,
                       standard_hash(v_cat_code || cohort.term_code || cohort.pidm || cohort.camp_code || cohort.coll_code, 'MD5') unique_id,
                       CASE
                       WHEN cohort.camp_code = 'R'
                            AND cohort.term_code <= '202420' THEN -- direct assessments were broken for resident in 202420
                        cohort.first_complete_date -- auto push this date
                       ELSE
                        dire_eval.evaluation_completed
                       END AS evaluation_date,
                       CASE
                        WHEN cohort.camp_code = 'R'
                             AND cohort.term_code <= '202420' THEN -- direct assessments were broken for resident in 202420
                         3 -- auto push this score
                        WHEN dire_eval.evaluation_completed IS NOT NULL
                             AND dire_eval.evaluation_score IS NULL THEN
                         3 -- rare, but sometimes we don't get any scores back, so default to passing since this is self evaluations
                      ELSE
                       dire_eval.evaluation_score
                      END AS evaluation_score,
                      v_etl_date AS activity_date
                 FROM utl_d_aa.fpt_cohort cohort
                 JOIN utl_d_aa.fpt_evaluations_status fes
                   ON fes.term_code = cohort.term_code
                  AND fes.pidm = cohort.pidm
                  AND fes.camp_code = cohort.camp_code
                  AND fes.coll_code = cohort.coll_code
                 LEFT JOIN (SELECT assessment.portfolio,
                                  assessment.id AS assessment_id,
                                  rec.term_code AS term_code,
                                  assessment.campus AS camp_code,
                                  assessment.activity_date AS evaluation_completed,
                                  gobtpac_external_user AS approver_username,
                                  resp.question_choice AS evaluation_score,
                                  rank() over(PARTITION BY assessment.term, assessment.campus, assessment.portfolio ORDER BY assessment.activity_date ASC, nvl(resp.question_choice, 0) ASC, rownum) ranking -- get first evaluation and lowest score
                             FROM zfacultyportfolio.assessment
                             LEFT JOIN zfacultyportfolio.question_response resp
                               ON resp.assessment = assessment.id
                             LEFT JOIN general.gobtpac
                               ON gobtpac_pidm = assessment.pidm
                            WHERE assessment.assessmenttype = 1 -- faculty self evaluation
                              AND assessment.completed = 'Y' -- all questions answered
                              AND assessment.term = rec.fpt_term_code -- fpt_term_code here 
                              AND assessment.campus = rec.camp_code) self_eval
                   ON self_eval.term_code = cohort.term_code
                  AND self_eval.camp_code = cohort.camp_code
                  AND self_eval.portfolio = cohort.portfolio
                  AND self_eval.ranking = 1
                 LEFT JOIN (SELECT assessment.portfolio,
                                  assessment.id AS assessment_id,
                                  rec.term_code AS term_code,
                                  assessment.campus AS camp_code,
                                  assessment.activity_date AS evaluation_completed,
                                  gobtpac_external_user AS approver_username,
                                  assessment.pidm AS approver_pidm,
                                  spriden_last_name || ', ' || spriden_first_name AS approver,
                                  CASE
                                  WHEN assessment.assessmenttype = 2 THEN
                                   'Instructional Mentor'
                                  WHEN assessment.assessmenttype = 3 THEN
                                   'Chair'
                                  END AS approver_position,
                                  resp.question_choice AS evaluation_score,
                                  rank() over(PARTITION BY assessment.term, assessment.campus, assessment.portfolio ORDER BY assessment.activity_date ASC, resp.question_choice ASC, rownum) ranking -- get first evaluation and lowest score
                             FROM zfacultyportfolio.assessment
                             JOIN saturn.spriden
                               ON spriden_pidm = assessment.pidm
                              AND spriden_change_ind IS NULL
                             JOIN zfacultyportfolio.question_response resp
                               ON resp.assessment = assessment.id
                              AND resp.question_choice IS NOT NULL -- must have scores for direct evaluations to be considered
                             LEFT JOIN general.gobtpac
                               ON gobtpac_pidm = assessment.pidm
                            WHERE assessment.assessmenttype IN (2, 3) -- IM or Chair for direct evaluations 
                              AND assessment.completed = 'Y' -- all questions answered
                              AND assessment.term = rec.fpt_term_code -- fpt_term_code here 
                              AND assessment.campus = rec.camp_code) dire_eval
                   ON dire_eval.term_code = cohort.term_code
                  AND dire_eval.camp_code = cohort.camp_code
                  AND dire_eval.portfolio = cohort.portfolio
                  AND dire_eval.ranking = 1
               -- get current positions to find who should be the evaluator - so we can hunt them down :)
                 LEFT JOIN (SELECT fht.pidm,
                                  fht.superior_pidm,
                                  fht.superior_username,
                                  fht.superior,
                                  fht.superior_position,
                                  fht.camp_code,
                                  fht.coll_code,
                                  fht.from_date,
                                  fht.to_date,
                                  rank() over(PARTITION BY fht.pidm, fht.camp_code, fht.coll_code ORDER BY fht.from_date DESC, fht.activity_date DESC, rownum) ranking -- used to sort out the bad data in the FHT
                             FROM utl_d_aa.faculty_hierarchy fht
                            WHERE fht.hierarchy_title_id <> 0 -- exclude FSC role
                              AND ((fht.camp_code = 'D' AND fht.superior_position = 'Instructional Mentor') OR (fht.camp_code = 'R' AND fht.superior_position = 'Chair'))
                              AND v_etl_date BETWEEN fht.from_date AND fht.to_date -- get current role(s);  keep inside subquery
                           ) fht
                   ON fht.pidm = cohort.pidm
                  AND fht.camp_code = cohort.camp_code
                  AND fht.coll_code = cohort.coll_code
                  AND fht.ranking = 1
                WHERE cohort.term_code = rec.term_code
                  AND cohort.camp_code = rec.camp_code) src
         LEFT JOIN utl_d_aa.fpt_evaluations_audit tgt
           ON tgt.unique_id = standard_hash(v_cat_code || src.term_code || src.pidm || src.camp_code || src.coll_code, 'MD5') --unique_id
        WHERE (tgt.pidm IS NULL -- missing from target table
              OR coalesce(tgt.approver, 'X') <> coalesce(src.approver, 'X') --
              OR coalesce(tgt.approver_username, 'X') <> coalesce(src.approver_username, 'X') --
              OR coalesce(tgt.approver_position, 'X') <> coalesce(src.approver_position, 'X') --
              OR coalesce(tgt.category_code, 'X') <> coalesce(src.category_code, 'X') --
              OR coalesce(tgt.status_color, 'X') <> coalesce(src.status_color, 'X') --
              OR coalesce(tgt.status_icon, 'X') <> coalesce(src.status_icon, 'X') --
              OR coalesce(tgt.status_desc, 'X') <> coalesce(src.status_desc, 'X') --
              OR coalesce(tgt.url, 'X') <> coalesce(src.url, 'X') --
              OR coalesce(tgt.evaluation_score, 0) <> coalesce(src.evaluation_score, 0) --
              OR coalesce(tgt.evaluation_date, v_etl_date) <> coalesce(src.evaluation_date, v_etl_date) --
              )) src
ON (tgt.unique_id = src.unique_id)
WHEN MATCHED THEN
UPDATE
   SET tgt.aidy_code         = src.aidy_code,
       tgt.term_code         = src.term_code,
       tgt.pidm              = src.pidm,
       tgt.camp_code         = src.camp_code,
       tgt.coll_code         = src.coll_code,
       tgt.approver          = src.approver,
       tgt.approver_username = src.approver_username,
       tgt.approver_position = src.approver_position,
       tgt.category_code     = src.category_code,
       tgt.status_color      = src.status_color,
       tgt.status_icon       = src.status_icon,
       tgt.status_desc       = src.status_desc,
       tgt.url               = src.url,
       tgt.evaluation_score  = src.evaluation_score,
       tgt.evaluation_date   = src.evaluation_date,
       tgt.activity_date     = src.activity_date
WHEN NOT MATCHED THEN
INSERT
(aidy_code,
 term_code,
 pidm,
 camp_code,
 coll_code,
 approver,
 approver_username,
 approver_position,
 category_code,
 status_color,
 status_icon,
 status_desc,
 url,
 unique_id,
 evaluation_date,
 evaluation_score,
 activity_date)
VALUES
(src.aidy_code,
 src.term_code,
 src.pidm,
 src.camp_code,
 src.coll_code,
 src.approver,
 src.approver_username,
 src.approver_position,
 src.category_code,
 src.status_color,
 src.status_icon,
 src.status_desc,
 src.url,
 src.unique_id,
 src.evaluation_date,
 src.evaluation_score,
 src.activity_date);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || v_cat_code || ' - ' || rec.term_code || ' - ' || rec.camp_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
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
ROLLBACK;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0); 
END etl_aa_fpt_evaluations_audit_dire;

PROCEDURE etl_aa_fpt_evaluations_audit_sume(jobnumber NUMBER, processid VARCHAR2, processname VARCHAR2) IS
--
-- PURPOSE: Stage summative evaluation audit records to track approvers, statuses, deadlines, and scores by term, campus, and college for the faculty portfolio evaluations dashboard and follow-up.
--
-- TABLE: utl_d_aa.fpt_evaluations_audit
--
-- UNIQUE INDEX: UNIQUE_ID
--
-- CONDITIONS:
-- Processes every scheduled term and campus from utl_d_aa.fpt_evaluations_schedule; no filtering occurs in the cursor, so all rows are evaluated in ORDER BY term_code and camp_code.
-- Limits cohort rows to cohort.term_code = rec.term_code and cohort.camp_code = rec.camp_code; all assessment pulls use rec.fpt_term_code and rec.camp_code.
-- Includes only faculty present in utl_d_aa.fpt_cohort that also have a matching evaluation status record in utl_d_aa.fpt_evaluations_status (joined on term_code, pidm, camp_code, coll_code).
-- Determines the current supervisor (fallback approver) from utl_d_aa.faculty_hierarchy where v_etl_date is between from_date and to_date, excluding FSC roles (hierarchy_title_id <> 0); for campus D the required superior is 'Chair', and for campus R it is 'Assistant/Associate Dean'; selects the most recent row using RANK() over from_date/activity_date.
-- Self evaluation selection (optional): zfacultyportfolio.assessment with assessmenttype = 1, completed = 'Y', matching rec.fpt_term_code and rec.camp_code; LEFT JOINs question_response (score may be null) and general.gobtpac for username; when multiple exist, selects earliest completion and lowest score via RANK() over activity_date ASC and NVL(score,0) ASC.
-- Direct evaluation selection: zfacultyportfolio.assessment with assessmenttype IN (2,3), completed = 'Y', numeric score required, matching rec.fpt_term_code and rec.camp_code; joins evaluator name from saturn.spriden and username from general.gobtpac; selects earliest completion and lowest score via RANK().
-- Summative evaluation selection: zfacultyportfolio.assessment with assessmenttype IN (3,4), comments IS NOT NULL, completed = 'Y', matching rec.fpt_term_code and rec.camp_code; evaluator name and username included; when multiples exist, selects the latest completion using RANK() over activity_date DESC to avoid duplicating the direct evaluator.
-- Approver fields (name, username, position) prioritize the summative evaluator; if the summative evaluator username matches the direct evaluator username, all approver values fall back to the faculty_hierarchy supervisor; if no summative exists, supervisor values are used.
-- Category code is fixed to 'SUME' for all rows.
-- UNIQUE_ID is computed as MD5(category_code || term_code || pidm || camp_code || coll_code) and is used as the business key for MERGE upserts.
-- Evaluation date is the summative evaluation completed timestamp; each row generates a URL pointing to the faculty portfolio evaluation record for the PIDM and term.
-- Evaluation score logic: for campus R with term_code <= '202420', assigns a default score of 3; otherwise, if a direct evaluation was completed but returned no numeric score, defaults to 3; in all other cases uses the numeric direct evaluation score.
-- Status logic determines color, icon, and message based on timing windows, completion of evaluation types, and term requirements:
-- - Completed summative by same person as direct: yellow/exclamation with message instructing reassignment to supervisor.
-- - Completed summative by different evaluator: green/check_mark with completion date.
-- - Required – Initial term:
--   - Before first_complete_date + 35 days with no summative: gray/clock with future requirement message.
--   - After +35 days or when a direct eval is completed, no summative: yellow/exclamation with due date = first_complete_date + 49 days.
--   - After +49 days, no summative: red/x-ray with overdue due date.
-- - Required (non-initial):
--   - Before rec.sume_start_date: gray/clock with start date.
--   - After sume_start_date (or after direct completion) with no summative: yellow/exclamation with due date = rec.dean_start_date.
--   - After rec.dean_start_date: red/x-ray with the same dean_start_date.
-- - Retroactive terms follow the same 3-stage pattern using rec.retro_sume_start_date and rec.retro_dean_start_date.
-- - If direct evaluation completed and >14 days without summative: red/x-ray and due date = direct_completed + 14 days; if within 14 days: yellow/exclamation.
-- - If only self evaluation exists: after 14 days without direct eval: yellow/exclamation with due date = self_completed + 28 days; after 28 days: red/x-ray with the same due date.
-- - If fes.status = 'Not Required': gray/minus with description stating summative is not required.
-- - If fes.status = 'Pending': gray/clock; for campus D the message notes self evaluations are not ready; for campus R they begin on rec.dire_start_date.
-- - If fes.status = 'Optional': gray/clock with message stating self evaluations are available but not required.
-- MERGE updates or inserts only when approver, position, category_code, status fields, URL, evaluation_score, or evaluation_date differ, or when UNIQUE_ID does not exist.
-- activity_date stores the ETL run timestamp (v_etl_date).
--
-- URL: https://facultyportfolio.liberty.edu/evaluations/
--
--DECLARE
--- PARAMS
v_etl_date    DATE := SYSDATE;
v_msg         VARCHAR2(2000);
v_instance    VARCHAR2(50) := upper('ALL'); -- inst from the jams job; used for determining instance
v_partition   NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0 
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_aa_fpt_evaluations_audit_sume';
v_cat_code    VARCHAR2(4) := 'SUME';
CURSOR c_terms IS
SELECT fes.*
  FROM utl_d_aa.fpt_evaluations_schedule fes
 ORDER BY 1,
          3;
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
v_msg     := 'START - ' || rec.term_code || ' - ' || rec.camp_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
MERGE INTO utl_d_aa.fpt_evaluations_audit tgt
USING (SELECT src.aidy_code,
              src.term_code,
              src.pidm,
              src.camp_code,
              src.coll_code,
              src.approver,
              src.approver_username,
              src.approver_position,
              src.category_code,
              src.status_color,
              src.status_icon,
              src.status_desc,
              src.url,
              src.unique_id,
              src.evaluation_date,
              src.evaluation_score,
              src.activity_date
         FROM (SELECT cohort.aidy_code,
                       cohort.term_code,
                       cohort.pidm,
                       cohort.camp_code,
                       cohort.coll_code,
                       cohort.coll_desc,
                       cohort.instructor,
                       cohort.instructor_username AS user_name,
                       cohort.email_address,
                       CASE
                       WHEN upper(nvl(sume_eval.approver_username, '<NULL>')) = upper(nvl(dire_eval.approver_username, '<NULL>')) THEN
                        fht.superior
                       ELSE
                        nvl(sume_eval.approver, fht.superior)
                       END AS approver,
                       CASE
                       WHEN upper(nvl(sume_eval.approver_username, '<NULL>')) = upper(nvl(dire_eval.approver_username, '<NULL>')) THEN
                        fht.superior_username
                       ELSE
                        nvl(sume_eval.approver_username, fht.superior_username)
                       END AS approver_username,
                       CASE
                       WHEN upper(nvl(sume_eval.approver_username, '<NULL>')) = upper(nvl(dire_eval.approver_username, '<NULL>')) THEN
                        fht.superior_position
                       ELSE
                        nvl(sume_eval.approver_position, fht.superior_position)
                       END AS approver_position,
                       v_cat_code AS category_code,
                       -- status_color logic
                       CASE
                       WHEN sume_eval.evaluation_completed IS NOT NULL
                            AND v_etl_date >= rec.dean_start_date
                            AND upper(nvl(sume_eval.approver_username, '<NULL>')) = upper(nvl(dire_eval.approver_username, '<NULL>')) THEN
                        'red'
                       WHEN sume_eval.evaluation_completed IS NOT NULL
                            AND upper(nvl(sume_eval.approver_username, '<NULL>')) = upper(nvl(dire_eval.approver_username, '<NULL>')) THEN
                        'yellow'
                       WHEN sume_eval.evaluation_completed IS NOT NULL THEN
                        'green'
                       WHEN fes.status = 'Required'
                            AND fes.status_desc = 'Required - Initial term'
                            AND v_etl_date >= cohort.first_complete_date + 49
                            AND sume_eval.evaluation_completed IS NULL THEN
                        'red'
                       WHEN fes.status = 'Required'
                            AND fes.status_desc = 'Required - Initial term'
                            AND (v_etl_date >= cohort.first_complete_date + 35 OR dire_eval.evaluation_completed IS NOT NULL)
                            AND sume_eval.evaluation_completed IS NULL THEN
                        'yellow'
                       WHEN fes.status = 'Required'
                            AND fes.status_desc = 'Required - Initial term'
                            AND v_etl_date < cohort.first_complete_date + 35 THEN
                        'gray'
                       WHEN fes.status = 'Required'
                            AND v_etl_date >= rec.dean_start_date
                            AND sume_eval.evaluation_completed IS NULL THEN
                        'red'
                       WHEN fes.status = 'Required'
                            AND (v_etl_date >= rec.sume_start_date OR dire_eval.evaluation_completed IS NOT NULL)
                            AND sume_eval.evaluation_completed IS NULL THEN
                        'yellow'
                       WHEN fes.status = 'Retroactive'
                            AND v_etl_date >= rec.retro_dean_start_date
                            AND sume_eval.evaluation_completed IS NULL THEN
                        'red'
                       WHEN fes.status = 'Retroactive'
                            AND (v_etl_date >= rec.retro_sume_start_date OR dire_eval.evaluation_completed IS NOT NULL)
                            AND sume_eval.evaluation_completed IS NULL THEN
                        'yellow'
                       WHEN fes.status = 'Retroactive'
                            AND v_etl_date < rec.retro_sume_start_date
                            AND sume_eval.evaluation_completed IS NULL THEN
                        'gray'
                       WHEN dire_eval.evaluation_completed + 14 < v_etl_date + 1
                            AND sume_eval.evaluation_completed IS NULL THEN
                        'red'
                       WHEN dire_eval.evaluation_completed < v_etl_date + 1
                            AND sume_eval.evaluation_completed IS NULL THEN
                        'yellow'
                       WHEN self_eval.evaluation_completed + 28 < v_etl_date + 1
                            AND dire_eval.evaluation_completed IS NULL THEN
                        'red'
                       WHEN self_eval.evaluation_completed + 14 < v_etl_date + 1
                            AND dire_eval.evaluation_completed IS NULL THEN
                        'yellow'
                       WHEN fes.status = 'Required'
                            AND v_etl_date < rec.sume_start_date
                            AND sume_eval.evaluation_completed IS NULL THEN
                        'gray'
                       WHEN fes.status IN ('Not Required', 'Pending', 'Optional') THEN
                        'gray'
                       END AS status_color,
                       -- status_icon logic
                       CASE
                       WHEN sume_eval.evaluation_completed IS NOT NULL
                            AND v_etl_date >= rec.dean_start_date
                            AND upper(nvl(sume_eval.approver_username, '<NULL>')) = upper(nvl(dire_eval.approver_username, '<NULL>')) THEN
                        'x-ray'
                       WHEN sume_eval.evaluation_completed IS NOT NULL
                            AND upper(nvl(sume_eval.approver_username, '<NULL>')) = upper(nvl(dire_eval.approver_username, '<NULL>')) THEN
                        'exclamation'
                       WHEN sume_eval.evaluation_completed IS NOT NULL THEN
                        'check_mark'
                       WHEN fes.status = 'Required'
                            AND fes.status_desc = 'Required - Initial term'
                            AND v_etl_date >= cohort.first_complete_date + 49
                            AND sume_eval.evaluation_completed IS NULL THEN
                        'x-ray'
                       WHEN fes.status = 'Required'
                            AND fes.status_desc = 'Required - Initial term'
                            AND (v_etl_date >= cohort.first_complete_date + 35 OR dire_eval.evaluation_completed IS NOT NULL)
                            AND sume_eval.evaluation_completed IS NULL THEN
                        'exclamation'
                       WHEN fes.status = 'Required'
                            AND fes.status_desc = 'Required - Initial term'
                            AND v_etl_date < cohort.first_complete_date + 35 THEN
                        'clock'
                       WHEN fes.status = 'Required'
                            AND v_etl_date >= rec.dean_start_date
                            AND sume_eval.evaluation_completed IS NULL THEN
                        'x-ray'
                       WHEN fes.status = 'Required'
                            AND (v_etl_date >= rec.sume_start_date OR dire_eval.evaluation_completed IS NOT NULL)
                            AND sume_eval.evaluation_completed IS NULL THEN
                        'exclamation'
                       WHEN fes.status = 'Retroactive'
                            AND v_etl_date >= rec.retro_dean_start_date
                            AND sume_eval.evaluation_completed IS NULL THEN
                        'x-ray'
                       WHEN fes.status = 'Retroactive'
                            AND (v_etl_date >= rec.retro_sume_start_date OR dire_eval.evaluation_completed IS NOT NULL)
                            AND sume_eval.evaluation_completed IS NULL THEN
                        'exclamation'
                       WHEN fes.status = 'Retroactive'
                            AND v_etl_date < rec.retro_sume_start_date
                            AND sume_eval.evaluation_completed IS NULL THEN
                        'clock'
                       WHEN dire_eval.evaluation_completed + 14 < v_etl_date + 1
                            AND sume_eval.evaluation_completed IS NULL THEN
                        'x-ray'
                       WHEN dire_eval.evaluation_completed < v_etl_date + 1
                            AND sume_eval.evaluation_completed IS NULL THEN
                        'exclamation'
                       WHEN self_eval.evaluation_completed + 28 < v_etl_date + 1
                            AND dire_eval.evaluation_completed IS NULL THEN
                        'x-ray'
                       WHEN self_eval.evaluation_completed + 14 < v_etl_date + 1
                            AND dire_eval.evaluation_completed IS NULL THEN
                        'exclamation'
                       WHEN fes.status = 'Required'
                            AND v_etl_date < rec.sume_start_date
                            AND sume_eval.evaluation_completed IS NULL THEN
                        'clock'
                       WHEN fes.status = 'Not Required' THEN
                        'minus'
                       WHEN fes.status = 'Pending' THEN
                        'clock'
                       WHEN fes.status = 'Optional' THEN
                        'clock'
                       END AS status_icon,
                       -- status_desc message building
                       CASE
                       WHEN sume_eval.evaluation_completed IS NOT NULL
                            AND v_etl_date >= rec.dean_start_date
                            AND upper(nvl(sume_eval.approver_username, '<NULL>')) = upper(nvl(dire_eval.approver_username, '<NULL>')) THEN
                        '3. Summative evaluations for ' || rec.semester_desc || ' must be completed ' || nvl2(fht.superior_username, 'by ' || fht.superior_username || ' before ', 'before ') || to_char(rec.dean_start_date, 'MM/DD/YYYY')
                       WHEN sume_eval.evaluation_completed IS NOT NULL
                            AND upper(nvl(sume_eval.approver_username, '<NULL>')) = upper(nvl(dire_eval.approver_username, '<NULL>')) THEN
                        '3. Summative evaluations for ' || rec.semester_desc || ' must be completed by ' || fht.superior_username || ' as soon as possible' -- no clue on the timing here, so "ASAP"
                       WHEN sume_eval.evaluation_completed IS NOT NULL THEN
                        '3. Summative evaluation for ' || rec.semester_desc || ' was completed by ' || sume_eval.approver_username || ' on ' || to_char(sume_eval.evaluation_completed, 'MM/DD/YYYY')
                       WHEN fes.status = 'Required'
                            AND fes.status_desc = 'Required - Initial term'
                            AND v_etl_date >= cohort.first_complete_date + 49
                            AND sume_eval.evaluation_completed IS NULL THEN
                        '3. Summative evaluations for ' || rec.semester_desc || ' must be completed ' || nvl2(fht.superior_username, 'by ' || fht.superior_username || ' before ', 'before ') ||
                        to_char(cohort.first_complete_date + 49, 'MM/DD/YYYY')
                       WHEN fes.status = 'Required'
                            AND fes.status_desc = 'Required - Initial term'
                            AND (v_etl_date >= cohort.first_complete_date + 35 OR dire_eval.evaluation_completed IS NOT NULL)
                            AND sume_eval.evaluation_completed IS NULL THEN
                        '3. Summative evaluations for ' || rec.semester_desc || ' must be completed ' || nvl2(fht.superior_username, 'by ' || fht.superior_username || ' before ', 'before ') ||
                        to_char(cohort.first_complete_date + 49, 'MM/DD/YYYY')
                       WHEN fes.status = 'Required'
                            AND fes.status_desc = 'Required - Initial term'
                            AND v_etl_date < cohort.first_complete_date + 35 THEN
                        '3. Summative evaluations for ' || rec.semester_desc || ' will be required after ' || to_char(cohort.first_complete_date + 35, 'MM/DD/YYYY')
                       WHEN fes.status = 'Required'
                            AND v_etl_date >= rec.dean_start_date
                            AND sume_eval.evaluation_completed IS NULL THEN
                        '3. Summative evaluations for ' || rec.semester_desc || ' must be completed ' || nvl2(fht.superior_username, 'by ' || fht.superior_username || ' before ', 'before ') || to_char(rec.dean_start_date, 'MM/DD/YYYY')
                       WHEN fes.status = 'Required'
                            AND (v_etl_date >= rec.sume_start_date OR dire_eval.evaluation_completed IS NOT NULL)
                            AND sume_eval.evaluation_completed IS NULL THEN
                        '3. Summative evaluations for ' || rec.semester_desc || ' must be completed ' || nvl2(fht.superior_username, 'by ' || fht.superior_username || ' before ', 'before ') || to_char(rec.dean_start_date, 'MM/DD/YYYY')
                       WHEN fes.status = 'Retroactive'
                            AND v_etl_date >= rec.retro_sume_start_date
                            AND sume_eval.evaluation_completed IS NULL THEN
                        '3. Summative evaluations for ' || rec.semester_desc || ' must be completed ' || nvl2(fht.superior_username, 'by ' || fht.superior_username || ' before ', 'before ') || to_char(rec.retro_dean_start_date, 'MM/DD/YYYY')
                       WHEN fes.status = 'Retroactive'
                            AND (v_etl_date >= rec.retro_sume_start_date OR dire_eval.evaluation_completed IS NOT NULL)
                            AND sume_eval.evaluation_completed IS NULL THEN
                        '3. Summative evaluations for ' || rec.semester_desc || ' must be completed ' || nvl2(fht.superior_username, 'by ' || fht.superior_username || ' before ', 'before ') || to_char(rec.retro_dean_start_date, 'MM/DD/YYYY')
                       WHEN fes.status = 'Retroactive'
                            AND v_etl_date < rec.retro_sume_start_date
                            AND sume_eval.evaluation_completed IS NULL THEN
                        '3. Summative evaluations for ' || rec.semester_desc || ' will begin on ' || to_char(rec.retro_sume_start_date, 'MM/DD/YYYY')
                       WHEN dire_eval.evaluation_completed + 14 < v_etl_date + 1
                            AND sume_eval.evaluation_completed IS NULL THEN
                        '3. Summative evaluations for ' || rec.semester_desc || ' must be completed ' || nvl2(fht.superior_username, 'by ' || fht.superior_username || ' before ', 'before ') ||
                        to_char(dire_eval.evaluation_completed + 14, 'MM/DD/YYYY')
                       WHEN dire_eval.evaluation_completed < v_etl_date + 1
                            AND sume_eval.evaluation_completed IS NULL THEN
                        '3. Summative evaluations for ' || rec.semester_desc || ' must be completed ' || nvl2(fht.superior_username, 'by ' || fht.superior_username || ' before ', 'before ') ||
                        to_char(dire_eval.evaluation_completed + 14, 'MM/DD/YYYY')
                       WHEN self_eval.evaluation_completed + 28 < v_etl_date + 1
                            AND dire_eval.evaluation_completed IS NULL THEN
                        '3. Summative evaluations for ' || rec.semester_desc || ' must be completed ' || nvl2(fht.superior_username, 'by ' || fht.superior_username || ' before ', 'before ') ||
                        to_char(self_eval.evaluation_completed + 28, 'MM/DD/YYYY')
                       WHEN self_eval.evaluation_completed + 14 < v_etl_date + 1
                            AND dire_eval.evaluation_completed IS NULL THEN
                        '3. Summative evaluations for ' || rec.semester_desc || ' must be completed ' || nvl2(fht.superior_username, 'by ' || fht.superior_username || ' before ', 'before ') ||
                        to_char(self_eval.evaluation_completed + 28, 'MM/DD/YYYY')
                       WHEN fes.status = 'Required'
                            AND v_etl_date < rec.sume_start_date
                            AND sume_eval.evaluation_completed IS NULL THEN
                        '3. Summative evaluations for ' || rec.semester_desc || ' will begin on ' || to_char(rec.sume_start_date, 'MM/DD/YYYY')
                       WHEN fes.status = 'Not Required' THEN
                        '3. Summative evaluations for ' || rec.semester_desc || ' are not required'
                       WHEN fes.status = 'Pending'
                            AND fes.camp_code = 'D' THEN
                        'Self evaluations for ' || rec.semester_desc || ' are not ready to begin'
                       WHEN fes.status = 'Pending'
                            AND fes.camp_code = 'R' THEN
                        'Self evaluations for ' || rec.semester_desc || ' begin on ' || to_char(rec.dire_start_date, 'MM/DD/YYYY')
                       WHEN fes.status = 'Optional' THEN
                        'Self evaluations for ' || rec.semester_desc || ' are available but not required'
                       END AS status_desc,
                       'https://facultyportfolio.liberty.edu/evaluations/' || cohort.pidm || '/' || rec.fpt_term_code AS url,
                       standard_hash(v_cat_code || cohort.term_code || cohort.pidm || cohort.camp_code || cohort.coll_code, 'MD5') unique_id,
                       CASE
                       WHEN upper(nvl(sume_eval.approver_username, '<NULL>')) = upper(nvl(dire_eval.approver_username, '<NULL>')) THEN
                        NULL
                       ELSE
                        sume_eval.evaluation_completed
                       END AS evaluation_date,
                       CASE
                        WHEN cohort.camp_code = 'R'
                             AND cohort.term_code <= '202420' THEN -- direct assessments were broken for resident in 202420
                         3 -- auto push this score
                        WHEN dire_eval.evaluation_completed IS NOT NULL
                             AND dire_eval.evaluation_score IS NULL THEN
                         3 -- rare, but sometimes we don't get any scores back, so default to passing since this is self evaluations
                      ELSE
                       dire_eval.evaluation_score
                      END AS evaluation_score,
                      v_etl_date AS activity_date
                 FROM utl_d_aa.fpt_cohort cohort
                 JOIN utl_d_aa.fpt_evaluations_status fes
                   ON fes.term_code = cohort.term_code
                  AND fes.pidm = cohort.pidm
                  AND fes.camp_code = cohort.camp_code
                  AND fes.coll_code = cohort.coll_code
                 LEFT JOIN (SELECT assessment.portfolio,
                                  assessment.id AS assessment_id,
                                  rec.term_code AS term_code,
                                  assessment.campus AS camp_code,
                                  assessment.activity_date AS evaluation_completed,
                                  gobtpac_external_user AS approver_username,
                                  resp.question_choice AS evaluation_score,
                                  rank() over(PARTITION BY assessment.term, assessment.campus, assessment.portfolio ORDER BY assessment.activity_date ASC, nvl(resp.question_choice, 0) ASC, rownum) ranking -- get first evaluation and lowest score
                             FROM zfacultyportfolio.assessment
                             LEFT JOIN zfacultyportfolio.question_response resp
                               ON resp.assessment = assessment.id
                             LEFT JOIN general.gobtpac
                               ON gobtpac_pidm = assessment.pidm
                            WHERE assessment.assessmenttype = 1 -- faculty self evaluation
                              AND assessment.completed = 'Y' -- all questions answered
                              AND assessment.term = rec.fpt_term_code -- fpt_term_code here 
                              AND assessment.campus = rec.camp_code) self_eval
                   ON self_eval.term_code = cohort.term_code
                  AND self_eval.camp_code = cohort.camp_code
                  AND self_eval.portfolio = cohort.portfolio
                  AND self_eval.ranking = 1
                 LEFT JOIN (SELECT assessment.portfolio,
                                  assessment.id AS assessment_id,
                                  rec.term_code AS term_code,
                                  assessment.campus AS camp_code,
                                  assessment.activity_date AS evaluation_completed,
                                  gobtpac_external_user AS approver_username,
                                  spriden_last_name || ', ' || spriden_first_name AS approver,
                                  CASE
                                  WHEN assessment.assessmenttype = 2 THEN
                                   'Instructional Mentor'
                                  WHEN assessment.assessmenttype = 3 THEN
                                   'Chair'
                                  END AS approver_position,
                                  resp.question_choice AS evaluation_score,
                                  rank() over(PARTITION BY assessment.term, assessment.campus, assessment.portfolio ORDER BY assessment.activity_date ASC, resp.question_choice ASC, rownum) ranking -- get first evaluation and lowest score
                             FROM zfacultyportfolio.assessment
                             JOIN saturn.spriden
                               ON spriden_pidm = assessment.pidm
                              AND spriden_change_ind IS NULL
                             JOIN zfacultyportfolio.question_response resp
                               ON resp.assessment = assessment.id
                              AND resp.question_choice IS NOT NULL -- must have scores for direct evaluations to be considered
                             LEFT JOIN general.gobtpac
                               ON gobtpac_pidm = assessment.pidm
                            WHERE assessment.assessmenttype IN (2, 3) -- IM or Chair for direct evaluations 
                              AND assessment.completed = 'Y' -- all questions answered
                              AND assessment.term = rec.fpt_term_code -- fpt_term_code here 
                              AND assessment.campus = rec.camp_code) dire_eval
                   ON dire_eval.term_code = cohort.term_code
                  AND dire_eval.camp_code = cohort.camp_code
                  AND dire_eval.portfolio = cohort.portfolio
                  AND dire_eval.ranking = 1
                 LEFT JOIN (SELECT assessment.portfolio,
                                  assessment.id AS assessment_id,
                                  rec.term_code AS term_code,
                                  assessment.campus AS camp_code,
                                  assessment.activity_date AS evaluation_completed,
                                  gobtpac_external_user AS approver_username,
                                  assessment.pidm AS approver_pidm,
                                  spriden_last_name || ', ' || spriden_first_name AS approver,
                                  CASE
                                  WHEN assessment.assessmenttype = 3 THEN
                                   'Chair'
                                  WHEN assessment.assessmenttype = 4 -- this is messed up and not pulling anything...
                                   THEN
                                   'Assistant/Associate Dean'
                                  END AS approver_position,
                                  NULL AS evaluation_score, -- no numeric scores for summative evaluations
                                  rank() over(PARTITION BY assessment.term, assessment.campus, assessment.portfolio ORDER BY assessment.activity_date ASC, rownum) ranking -- MUST get the first evaluation for summatives to make sure they are not the same as the direct evals
                             FROM zfacultyportfolio.assessment
                             JOIN saturn.spriden
                               ON spriden_pidm = assessment.pidm
                              AND spriden_change_ind IS NULL
                             LEFT JOIN general.gobtpac
                               ON gobtpac_pidm = assessment.pidm
                            WHERE assessment.assessmenttype IN (3, 4) -- Chair or AD/Dean for summative evaluations
                              AND assessment.comments IS NOT NULL -- must have comments for summative evaluations
                              AND assessment.completed = 'Y' -- all questions answered
                              AND assessment.term = rec.fpt_term_code -- fpt_term_code here 
                              AND assessment.campus = rec.camp_code) sume_eval
                   ON sume_eval.term_code = cohort.term_code
                  AND sume_eval.camp_code = cohort.camp_code
                  AND sume_eval.portfolio = cohort.portfolio
                  AND sume_eval.ranking = 1
               -- get current positions to find who should be the evaluator - so we can hunt them down :)
                 LEFT JOIN (SELECT fht.pidm,
                                  fht.superior_pidm,
                                  fht.superior_username,
                                  fht.superior,
                                  fht.superior_position,
                                  fht.camp_code,
                                  fht.coll_code,
                                  fht.from_date,
                                  fht.to_date,
                                  rank() over(PARTITION BY fht.pidm, fht.camp_code, fht.coll_code ORDER BY fht.from_date DESC, fht.activity_date DESC, rownum) ranking -- used to sort out the bad data in the FHT
                             FROM utl_d_aa.faculty_hierarchy fht
                            WHERE fht.hierarchy_title_id <> 0 -- exclude FSC role
                              AND ((fht.camp_code = 'D' AND fht.superior_position = 'Chair') OR (fht.camp_code = 'R' AND fht.superior_position = 'Assistant/Associate Dean'))
                              AND v_etl_date BETWEEN fht.from_date AND fht.to_date -- get current role(s);  keep inside subquery
                           ) fht
                   ON fht.pidm = cohort.pidm
                  AND fht.camp_code = cohort.camp_code
                  AND fht.coll_code = cohort.coll_code
                  AND fht.ranking = 1
                WHERE cohort.term_code = rec.term_code
                  AND cohort.camp_code = rec.camp_code) src
         LEFT JOIN utl_d_aa.fpt_evaluations_audit tgt
           ON tgt.unique_id = standard_hash(v_cat_code || src.term_code || src.pidm || src.camp_code || src.coll_code, 'MD5') --unique_id
        WHERE 1 = 1
          AND (tgt.pidm IS NULL -- missing from target table
              OR coalesce(tgt.approver, 'X') <> coalesce(src.approver, 'X') --
              OR coalesce(tgt.approver_username, 'X') <> coalesce(src.approver_username, 'X') --
              OR coalesce(tgt.approver_position, 'X') <> coalesce(src.approver_position, 'X') --
              OR coalesce(tgt.category_code, 'X') <> coalesce(src.category_code, 'X') --
              OR coalesce(tgt.status_color, 'X') <> coalesce(src.status_color, 'X') --
              OR coalesce(tgt.status_icon, 'X') <> coalesce(src.status_icon, 'X') --
              OR coalesce(tgt.status_desc, 'X') <> coalesce(src.status_desc, 'X') --
              OR coalesce(tgt.url, 'X') <> coalesce(src.url, 'X') --
              OR coalesce(tgt.evaluation_score, 0) <> coalesce(src.evaluation_score, 0) --
              OR coalesce(tgt.evaluation_date, v_etl_date) <> coalesce(src.evaluation_date, v_etl_date) --
              )) src
ON (tgt.unique_id = src.unique_id)
WHEN MATCHED THEN
UPDATE
   SET tgt.aidy_code         = src.aidy_code,
       tgt.term_code         = src.term_code,
       tgt.pidm              = src.pidm,
       tgt.camp_code         = src.camp_code,
       tgt.coll_code         = src.coll_code,
       tgt.approver          = src.approver,
       tgt.approver_username = src.approver_username,
       tgt.approver_position = src.approver_position,
       tgt.category_code     = src.category_code,
       tgt.status_color      = src.status_color,
       tgt.status_icon       = src.status_icon,
       tgt.status_desc       = src.status_desc,
       tgt.url               = src.url,
       tgt.evaluation_score  = src.evaluation_score,
       tgt.evaluation_date   = src.evaluation_date,
       tgt.activity_date     = src.activity_date
WHEN NOT MATCHED THEN
INSERT
(aidy_code,
 term_code,
 pidm,
 camp_code,
 coll_code,
 approver,
 approver_username,
 approver_position,
 category_code,
 status_color,
 status_icon,
 status_desc,
 url,
 unique_id,
 evaluation_date,
 evaluation_score,
 activity_date)
VALUES
(src.aidy_code,
 src.term_code,
 src.pidm,
 src.camp_code,
 src.coll_code,
 src.approver,
 src.approver_username,
 src.approver_position,
 src.category_code,
 src.status_color,
 src.status_icon,
 src.status_desc,
 src.url,
 src.unique_id,
 src.evaluation_date,
 src.evaluation_score,
 src.activity_date);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || v_cat_code || ' - ' || rec.term_code || ' - ' || rec.camp_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
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
ROLLBACK;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
END etl_aa_fpt_evaluations_audit_sume;

PROCEDURE etl_aa_fpt_evaluations_audit_dean(jobnumber NUMBER, processid VARCHAR2, processname VARCHAR2) IS
--
-- PURPOSE: Audits and tracks Dean evaluation ownership, status, and timelines for faculty portfolios across terms and campuses to support compliance monitoring and executive/dashboard reporting.
--
-- TABLE: utl_d_aa.fpt_evaluations_audit
--
-- UNIQUE INDEX: UNIQUE_ID
--
-- CONDITIONS:
-- Processes data one term and campus at a time using fpt_evaluations_schedule; each loop iteration filters cohorts to rec.term_code and rec.camp_code and uses the corresponding Dean evaluation windows (dean_start_date/dean_end_date and retro_dean_start_date/retro_dean_end_date).
-- Includes only faculty cohort records that have a matching status row in fpt_evaluations_status (same term_code, pidm, camp_code, coll_code).
-- Determines the responsible approver (name/username/position) based on evaluation progress:
--   • If a direct evaluation is completed with a score < 3 and the summative and Dean evaluations are completed, the approver is the Dean (from Dean evaluation).
--   • If a direct evaluation is completed with a score < 3, the summative is not done, and the Dean evaluation is completed, the approver is the Dean.
--   • If a direct evaluation is completed with a score >= 3 and a summative evaluation is completed and the Dean evaluation is not completed (optional path), the approver is the Summative evaluator.
--   • If the Dean evaluation is completed (regardless of other steps), the approver is the Dean.
--   • Otherwise, the approver pre-populates from the current Dean in faculty_hierarchy (matching pidm/camp_code/coll_code as of v_etl_date; excludes FSC roles; selects most recent).
-- Sets CATEGORY_CODE = 'DEAN' for all rows.
-- Encodes status_color/status_icon/status_desc to reflect business timelines and completion:
--   • Completed Dean path (any case where Dean evaluation is done): color = green, icon = check_mark or arrowhead, description states completion by approver and date.
--   • Direct score >= 3 with completed Summative and no Dean (optional Dean): color = gray, icon = check_mark, description states Dean is optional due to meets/exceeds expectations.
--   • First-time teaching (fes.status = 'Required' and fes.status_desc = 'Required - Initial term'):
--     - Before first_complete_date + 49 days: color = gray, icon = clock, description states evaluations will be required after that date.
--     - From first_complete_date + 49 days (or earlier if Summative completed and Direct score < 3) up to first_complete_date + 63 days with no Dean: color = yellow, icon = exclamation, description requires completion by +63 days.
--     - At or after first_complete_date + 63 days with no Dean: color = red, icon = x-ray, description requires immediate completion (deadline passed).
--   • All other Required (fes.status = 'Required'):
--     - Before dean_start_date with no Dean: color = gray, icon = clock, description states evaluations begin on dean_start_date.
--     - From dean_start_date (or earlier if Summative completed and Direct score < 3) up to dean_end_date with no Dean: color = yellow, icon = exclamation, description requires completion by dean_end_date.
--     - At or after dean_end_date with no Dean: color = red, icon = x-ray, description requires immediate completion (deadline passed).
--   • Retroactive (fes.status = 'Retroactive'):
--     - Before retro_dean_start_date with no Dean: color = gray, icon = clock, description states retroactive evaluations will begin (retro window not yet open).
--     - From retro_dean_start_date (or earlier if Summative completed and Direct score < 3) up to retro_dean_end_date with no Dean: color = yellow, icon = exclamation, description requires completion by retro_dean_end_date.
--     - At or after retro_dean_end_date with no Dean: color = red, icon = x-ray, description requires immediate completion (retro deadline passed).
--   • After Summative completion (when Direct has a score):
--     - Within 14 days after Summative completion and before Dean completion: color = yellow, icon = exclamation, description requires completion by Summative + 14 days.
--     - More than 14 days after Summative completion and before Dean completion: color = red, icon = x-ray, description requires completion by Summative + 14 days (overdue).
--   • After Self evaluation only (no Direct and no Summative yet):
--     - More than 28 days after Self completion and before any subsequent evaluation: color = yellow, icon = exclamation, description requires completion by Self + 42 days.
--     - More than 42 days after Self completion and before any subsequent evaluation: color = red, icon = x-ray, description requires completion by Self + 42 days (overdue).
--   • fes.status in ('Not Required','Pending','Optional') yields neutral states:
--     - Not Required: color = gray, icon = minus, description states Dean evaluations are not required.
--     - Pending: color = gray, icon = clock; description indicates when self evaluations are ready or start (varies by campus; Resident uses dire_start_date).
--     - Optional: color = gray, icon = clock; description states self evaluations are available but not required.
-- URL field points to the Faculty Portfolio evaluations page for the person and term: https://facultyportfolio.liberty.edu/evaluations/{PIDM}/{FPT_TERM_CODE}.
-- Evaluation date selection:
--   • If Dean evaluation is completed, uses Dean completed date.
--   • If Dean is optional (Direct score >= 3 and Summative completed, Dean not done), uses Summative completed date.
--   • Otherwise uses the relevant completed date per the above completion path.
-- Evaluation score selection:
--   • For Resident (camp_code = 'R') and term_code <= '202420', defaults to 3 due to known issue with direct assessments in that term.
--   • If a Direct evaluation is completed but its score is null, defaults to 3.
--   • Otherwise uses the lowest Direct evaluation score among completed direct assessments (Instructional Mentor or Chair).
-- Evaluation sampling rules:
--   • Self evaluations: assessmenttype = 1, completed = 'Y', partitioned by term/campus/portfolio; selects the earliest completion and, where present, the lowest numeric choice.
--   • Direct evaluations: assessmenttype in (2,3), completed = 'Y', requires a non-null numeric score; selects the earliest completion with the lowest score.
--   • Summative evaluations: assessmenttype in (3,4), comments is not null, completed = 'Y'; selects the earliest completion; no numeric score.
--   • Dean evaluations: completed = 'Y'; selects the earliest completed_date; for terms before campus was populated, treats null campus as the current campus (NVL to rec.camp_code).
-- Approver fallback uses current faculty_hierarchy as of v_etl_date (filters to superior_position = 'Dean', excludes hierarchy_title_id = 0) and picks the most recent assignment per faculty/campus/college.
-- Rows are upserted when missing or when any business attributes change (approver fields, category_code, status fields, url, evaluation score/date), keyed by UNIQUE_ID derived from category_code, term_code, pidm, camp_code, and coll_code.
--
-- URL: https://facultyportfolio.liberty.edu/evaluations/{PIDM}/{FPT_TERM_CODE}
--
--DECLARE
--- PARAMS
v_etl_date    DATE := SYSDATE;
v_msg         VARCHAR2(2000);
v_instance    VARCHAR2(50) := upper('ALL'); -- inst from the jams job; used for determining instance
v_partition   NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0 
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_aa_fpt_evaluations_audit_dean';
v_cat_code    VARCHAR2(4) := 'DEAN';
CURSOR c_terms IS
SELECT fes.*
  FROM utl_d_aa.fpt_evaluations_schedule fes
 ORDER BY 1,
          3;
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
v_msg     := 'START - ' || rec.term_code || ' - ' || rec.camp_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
MERGE INTO utl_d_aa.fpt_evaluations_audit tgt
USING (SELECT src.aidy_code,
              src.term_code,
              src.pidm,
              src.camp_code,
              src.coll_code,
              src.approver,
              src.approver_username,
              src.approver_position,
              src.category_code,
              src.status_color,
              src.status_icon,
              src.status_desc,
              src.url,
              src.unique_id,
              src.evaluation_date,
              src.evaluation_score,
              src.activity_date
         FROM (SELECT cohort.aidy_code,
                       cohort.term_code,
                       cohort.pidm,
                       cohort.camp_code,
                       cohort.coll_code,
                       cohort.coll_desc,
                       cohort.instructor,
                       cohort.instructor_username AS user_name,
                       cohort.email_address,
                       CASE
                       WHEN dire_eval.evaluation_completed IS NOT NULL -- direct evaluation done
                            AND dire_eval.evaluation_score < 3 -- direct evaluation scored
                            AND sume_eval.evaluation_completed IS NOT NULL -- sume evaluation done
                            AND upper(nvl(sume_eval.approver_username, '<NULL>')) <> upper(nvl(dire_eval.approver_username, '<NULL>')) -- cannot be the same person do direct and summative 
                            AND dean_eval.evaluation_completed IS NOT NULL -- dean evaluation done
                        THEN
                        dean_eval.approver
                       WHEN dire_eval.evaluation_completed IS NOT NULL -- direct evaluation done
                            AND dire_eval.evaluation_score < 3 -- direct evaluation scored                            
                            AND dean_eval.evaluation_completed IS NOT NULL -- dean evaluation done
                        THEN
                        dean_eval.approver
                       WHEN dire_eval.evaluation_completed IS NOT NULL -- direct evaluation done
                            AND dire_eval.evaluation_score >= 3 -- direct evaluation scored               
                            AND sume_eval.evaluation_completed IS NOT NULL -- sume evaluation done
                            AND upper(nvl(sume_eval.approver_username, '<NULL>')) <> upper(nvl(dire_eval.approver_username, '<NULL>')) -- cannot be the same person do direct and summative
                            AND dean_eval.evaluation_completed IS NULL -- dean evaluation OPTIONAL 
                        THEN
                        sume_eval.approver
                       WHEN dean_eval.evaluation_completed IS NOT NULL -- dean evaluation done
                        THEN
                        dean_eval.approver
                       ELSE
                        fht.superior
                       END AS approver,
                       CASE
                       WHEN dire_eval.evaluation_completed IS NOT NULL -- direct evaluation done
                            AND dire_eval.evaluation_score < 3 -- direct evaluation scored
                            AND sume_eval.evaluation_completed IS NOT NULL -- sume evaluation done
                            AND upper(nvl(sume_eval.approver_username, '<NULL>')) <> upper(nvl(dire_eval.approver_username, '<NULL>')) -- cannot be the same person do direct and summative 
                            AND dean_eval.evaluation_completed IS NOT NULL -- dean evaluation done
                        THEN
                        dean_eval.approver_username
                       WHEN dire_eval.evaluation_completed IS NOT NULL -- direct evaluation done
                            AND dire_eval.evaluation_score < 3 -- direct evaluation scored 
                            AND dean_eval.evaluation_completed IS NOT NULL -- dean evaluation done
                        THEN
                        dean_eval.approver_username
                       WHEN dire_eval.evaluation_completed IS NOT NULL -- direct evaluation done
                            AND dire_eval.evaluation_score >= 3 -- direct evaluation scored               
                            AND sume_eval.evaluation_completed IS NOT NULL -- sume evaluation done
                            AND upper(nvl(sume_eval.approver_username, '<NULL>')) <> upper(nvl(dire_eval.approver_username, '<NULL>')) -- cannot be the same person do direct and summative 
                            AND dean_eval.evaluation_completed IS NULL -- dean evaluation OPTIONAL 
                        THEN
                        sume_eval.approver_username
                       WHEN dean_eval.evaluation_completed IS NOT NULL -- dean evaluation done
                        THEN
                        dean_eval.approver_username
                       ELSE
                        fht.superior_username
                       END AS approver_username,
                       CASE
                       WHEN dire_eval.evaluation_completed IS NOT NULL -- direct evaluation done
                            AND dire_eval.evaluation_score < 3 -- direct evaluation scored
                            AND sume_eval.evaluation_completed IS NOT NULL -- sume evaluation done
                            AND upper(nvl(sume_eval.approver_username, '<NULL>')) <> upper(nvl(dire_eval.approver_username, '<NULL>')) -- cannot be the same person do direct and summative 
                            AND dean_eval.evaluation_completed IS NOT NULL -- dean evaluation done
                        THEN
                        dean_eval.approver_position
                       WHEN dire_eval.evaluation_completed IS NOT NULL -- direct evaluation done
                            AND dire_eval.evaluation_score < 3 -- direct evaluation scored 
                            AND dean_eval.evaluation_completed IS NOT NULL -- dean evaluation done
                        THEN
                        dean_eval.approver_position
                       WHEN dire_eval.evaluation_completed IS NOT NULL -- direct evaluation done
                            AND dire_eval.evaluation_score >= 3 -- direct evaluation scored               
                            AND sume_eval.evaluation_completed IS NOT NULL -- sume evaluation done
                            AND upper(nvl(sume_eval.approver_username, '<NULL>')) <> upper(nvl(dire_eval.approver_username, '<NULL>')) -- cannot be the same person do direct and summative 
                            AND dean_eval.evaluation_completed IS NULL -- dean evaluation OPTIONAL 
                        THEN
                        sume_eval.approver_position
                       WHEN dean_eval.evaluation_completed IS NOT NULL -- dean evaluation done
                        THEN
                        dean_eval.approver_position
                       ELSE
                        fht.superior_position
                       END AS approver_position,
                       v_cat_code AS category_code,
                       CASE
                       WHEN dire_eval.evaluation_completed IS NOT NULL -- direct evaluation done
                            AND dire_eval.evaluation_score < 3 -- direct evaluation scored
                            AND sume_eval.evaluation_completed IS NOT NULL -- sume evaluation done
                            AND upper(nvl(sume_eval.approver_username, '<NULL>')) <> upper(nvl(dire_eval.approver_username, '<NULL>')) -- cannot be the same person do direct and summative 
                            AND dean_eval.evaluation_completed IS NOT NULL -- dean evaluation done
                        THEN
                        'green'
                       WHEN dire_eval.evaluation_completed IS NOT NULL -- direct evaluation done
                            AND dire_eval.evaluation_score < 3 -- direct evaluation scored                            
                            AND dean_eval.evaluation_completed IS NOT NULL -- dean evaluation done
                        THEN
                        'green'
                       WHEN dire_eval.evaluation_completed IS NOT NULL -- direct evaluation done
                            AND dire_eval.evaluation_score >= 3 -- direct evaluation scored               
                            AND sume_eval.evaluation_completed IS NOT NULL -- sume evaluation done
                            AND upper(nvl(sume_eval.approver_username, '<NULL>')) <> upper(nvl(dire_eval.approver_username, '<NULL>')) -- cannot be the same person do direct and summative 
                            AND dean_eval.evaluation_completed IS NULL -- dean evaluation OPTIONAL 
                        THEN
                        'gray'
                       WHEN dean_eval.evaluation_completed IS NOT NULL -- dean evaluation done
                        THEN
                        'green'
                       -- first time teaching Required
                       WHEN fes.status = 'Required'
                            AND fes.status_desc = 'Required - Initial term'
                            AND v_etl_date >= cohort.first_complete_date + 63
                            AND dean_eval.evaluation_completed IS NULL THEN
                        'red'
                       WHEN fes.status = 'Required'
                            AND fes.status_desc = 'Required - Initial term'
                            AND (v_etl_date >= cohort.first_complete_date + 49 OR (sume_eval.evaluation_completed IS NOT NULL AND dire_eval.evaluation_score < 3))
                            AND dean_eval.evaluation_completed IS NULL THEN
                        'yellow'
                       WHEN fes.status = 'Required'
                            AND fes.status_desc = 'Required - Initial term'
                            AND v_etl_date < cohort.first_complete_date + 49 THEN
                        'gray'
                       -- all else Required
                       WHEN fes.status = 'Required'
                            AND v_etl_date >= rec.dean_end_date
                            AND dean_eval.evaluation_completed IS NULL THEN
                        'red'
                       WHEN fes.status = 'Required'
                            AND (v_etl_date >= rec.dean_start_date OR (sume_eval.evaluation_completed IS NOT NULL AND dire_eval.evaluation_score < 3))
                            AND dean_eval.evaluation_completed IS NULL THEN
                        'yellow'
                       WHEN fes.status = 'Retroactive'
                            AND v_etl_date >= rec.retro_dean_end_date
                            AND dean_eval.evaluation_completed IS NULL THEN
                        'red'
                       WHEN fes.status = 'Retroactive'
                            AND (v_etl_date >= rec.retro_dean_start_date OR (sume_eval.evaluation_completed IS NOT NULL AND dire_eval.evaluation_score < 3))
                            AND dean_eval.evaluation_completed IS NULL THEN
                        'yellow'
                       WHEN fes.status = 'Retroactive'
                            AND v_etl_date < rec.retro_dean_start_date
                            AND dean_eval.evaluation_completed IS NULL THEN
                        'gray'
                       WHEN sume_eval.evaluation_completed + 14 < v_etl_date + 1 -- completed the sume evaluation; evaluation_completed is null otherwise
                            AND dean_eval.evaluation_completed IS NULL -- no eval completed yet
                        THEN
                        'red'
                       WHEN sume_eval.evaluation_completed < v_etl_date + 1 -- completed the sume evaluation; evaluation_completed is null otherwise
                            AND dean_eval.evaluation_completed IS NULL -- no eval completed yet
                        THEN
                        'yellow'
                       WHEN self_eval.evaluation_completed + 42 < v_etl_date + 1 -- completed the optional self evaluation; evaluation_completed is null otherwise
                            AND dire_eval.evaluation_completed IS NULL -- no eval completed yet
                            AND sume_eval.evaluation_completed IS NULL -- no eval completed yet
                        THEN
                        'red'
                       WHEN self_eval.evaluation_completed + 28 < v_etl_date + 1 -- completed the optional self evaluation; evaluation_completed is null otherwise
                            AND dire_eval.evaluation_completed IS NULL -- no eval completed yet
                            AND sume_eval.evaluation_completed IS NULL -- no eval completed yet
                        THEN
                        'yellow'
                       WHEN fes.status = 'Required'
                            AND v_etl_date < rec.dean_start_date
                            AND dean_eval.evaluation_completed IS NULL THEN
                        'gray'
                       WHEN fes.status = 'Not Required' THEN
                        'gray'
                       WHEN fes.status = 'Pending' THEN
                        'gray'
                       WHEN fes.status = 'Optional' THEN
                        'gray'
                       END AS status_color,
                       CASE
                       WHEN dire_eval.evaluation_completed IS NOT NULL -- direct evaluation done
                            AND dire_eval.evaluation_score < 3 -- direct evaluation scored
                            AND sume_eval.evaluation_completed IS NOT NULL -- sume evaluation done
                            AND upper(nvl(sume_eval.approver_username, '<NULL>')) <> upper(nvl(dire_eval.approver_username, '<NULL>')) -- cannot be the same person do direct and summative 
                            AND dean_eval.evaluation_completed IS NOT NULL -- dean evaluation done
                        THEN
                        'arrowhead'
                       WHEN dire_eval.evaluation_completed IS NOT NULL -- direct evaluation done
                            AND dire_eval.evaluation_score < 3 -- direct evaluation scored                            
                            AND dean_eval.evaluation_completed IS NOT NULL -- dean evaluation done
                        THEN
                        'arrowhead'
                       WHEN dire_eval.evaluation_completed IS NOT NULL -- direct evaluation done
                            AND dire_eval.evaluation_score >= 3 -- direct evaluation scored               
                            AND sume_eval.evaluation_completed IS NOT NULL -- sume evaluation done
                            AND upper(nvl(sume_eval.approver_username, '<NULL>')) <> upper(nvl(dire_eval.approver_username, '<NULL>')) -- cannot be the same person do direct and summative 
                            AND dean_eval.evaluation_completed IS NULL -- dean evaluation OPTIONAL 
                        THEN
                        'check_mark'
                       WHEN dean_eval.evaluation_completed IS NOT NULL -- dean evaluation done
                        THEN
                        'check_mark'
                       -- first time teaching Required
                       WHEN fes.status = 'Required'
                            AND fes.status_desc = 'Required - Initial term'
                            AND v_etl_date >= cohort.first_complete_date + 63
                            AND dean_eval.evaluation_completed IS NULL THEN
                        'x-ray'
                       WHEN fes.status = 'Required'
                            AND fes.status_desc = 'Required - Initial term'
                            AND (v_etl_date >= cohort.first_complete_date + 49 OR (sume_eval.evaluation_completed IS NOT NULL AND dire_eval.evaluation_score < 3))
                            AND dean_eval.evaluation_completed IS NULL THEN
                        'exclamation'
                       WHEN fes.status = 'Required'
                            AND fes.status_desc = 'Required - Initial term'
                            AND v_etl_date < cohort.first_complete_date + 49 THEN
                        'clock'
                       -- all else Required
                       WHEN fes.status = 'Required'
                            AND v_etl_date >= rec.dean_end_date
                            AND dean_eval.evaluation_completed IS NULL THEN
                        'x-ray'
                       WHEN fes.status = 'Required'
                            AND (v_etl_date >= rec.dean_start_date OR (sume_eval.evaluation_completed IS NOT NULL AND dire_eval.evaluation_score < 3))
                            AND dean_eval.evaluation_completed IS NULL THEN
                        'exclamation'
                       WHEN fes.status = 'Retroactive'
                            AND v_etl_date >= rec.retro_dean_end_date
                            AND dean_eval.evaluation_completed IS NULL THEN
                        'x-ray'
                       WHEN fes.status = 'Retroactive'
                            AND (v_etl_date >= rec.retro_dean_start_date OR (sume_eval.evaluation_completed IS NOT NULL AND dire_eval.evaluation_score < 3))
                            AND dean_eval.evaluation_completed IS NULL THEN
                        'exclamation'
                       WHEN fes.status = 'Retroactive'
                            AND v_etl_date < rec.retro_dean_start_date
                            AND dean_eval.evaluation_completed IS NULL THEN
                        'clock'
                       WHEN sume_eval.evaluation_completed + 14 < v_etl_date + 1 -- completed the sume evaluation; evaluation_completed is null otherwise
                            AND dean_eval.evaluation_completed IS NULL -- no eval completed yet
                        THEN
                        'x-ray'
                       WHEN sume_eval.evaluation_completed < v_etl_date + 1 -- completed the sume evaluation; evaluation_completed is null otherwise
                            AND dean_eval.evaluation_completed IS NULL -- no eval completed yet
                        THEN
                        'exclamation'
                       WHEN self_eval.evaluation_completed + 42 < v_etl_date + 1 -- completed the optional self evaluation; evaluation_completed is null otherwise
                            AND dire_eval.evaluation_completed IS NULL -- no eval completed yet
                            AND sume_eval.evaluation_completed IS NULL -- no eval completed yet
                        THEN
                        'x-ray'
                       WHEN self_eval.evaluation_completed + 28 < v_etl_date + 1 -- completed the optional self evaluation; evaluation_completed is null otherwise
                            AND dire_eval.evaluation_completed IS NULL -- no eval completed yet
                            AND sume_eval.evaluation_completed IS NULL -- no eval completed yet
                        THEN
                        'exclamation'
                       WHEN fes.status = 'Required'
                            AND v_etl_date < rec.dean_start_date
                            AND dean_eval.evaluation_completed IS NULL THEN
                        'clock'
                       WHEN fes.status = 'Not Required' THEN
                        'minus'
                       WHEN fes.status = 'Pending' THEN
                        'clock'
                       WHEN fes.status = 'Optional' THEN
                        'clock'
                       END AS status_icon,
                       CASE
                       WHEN dire_eval.evaluation_completed IS NOT NULL -- direct evaluation done
                            AND dire_eval.evaluation_score < 3 -- direct evaluation scored
                            AND sume_eval.evaluation_completed IS NOT NULL -- sume evaluation done
                            AND upper(nvl(sume_eval.approver_username, '<NULL>')) <> upper(nvl(dire_eval.approver_username, '<NULL>')) -- cannot be the same person do direct and summative 
                            AND dean_eval.evaluation_completed IS NOT NULL -- dean evaluation done
                        THEN
                        '4. Dean evaluation for ' || rec.semester_desc || ' was completed by ' || dean_eval.approver_username || ' on ' || to_char(dean_eval.evaluation_completed, 'MM/DD/YYYY')
                       WHEN dire_eval.evaluation_completed IS NOT NULL -- direct evaluation done
                            AND dire_eval.evaluation_score < 3 -- direct evaluation scored                            
                            AND dean_eval.evaluation_completed IS NOT NULL -- dean evaluation done
                        THEN
                        '4. Dean evaluation for ' || rec.semester_desc || ' was completed by ' || dean_eval.approver_username || ' on ' || to_char(dean_eval.evaluation_completed, 'MM/DD/YYYY')
                       WHEN dire_eval.evaluation_completed IS NOT NULL -- direct evaluation done
                            AND dire_eval.evaluation_score >= 3 -- direct evaluation scored               
                            AND sume_eval.evaluation_completed IS NOT NULL -- sume evaluation done
                            AND upper(nvl(sume_eval.approver_username, '<NULL>')) <> upper(nvl(dire_eval.approver_username, '<NULL>')) -- cannot be the same person do direct and summative 
                            AND dean_eval.evaluation_completed IS NULL -- dean evaluation OPTIONAL 
                        THEN
                        '4. Dean evaluation is optional for ' || rec.semester_desc || '. Faculty meets/exeeds expectations. Scored by ' || dire_eval.approver_username || ' on ' || to_char(dire_eval.evaluation_completed, 'MM/DD/YYYY')
                       WHEN dean_eval.evaluation_completed IS NOT NULL -- dean evaluation done
                        THEN
                        '4. Dean evaluation for ' || rec.semester_desc || ' was completed by ' || dean_eval.approver_username || ' on ' || to_char(dean_eval.evaluation_completed, 'MM/DD/YYYY')
                       -- first time teaching Required
                       WHEN fes.status = 'Required'
                            AND fes.status_desc = 'Required - Initial term'
                            AND v_etl_date >= cohort.first_complete_date + 63
                            AND dean_eval.evaluation_completed IS NULL THEN
                        '4. Dean evaluations for ' || rec.semester_desc || ' must be completed ' || nvl2(fht.superior_username, 'by ' || fht.superior_username || ' before ', 'before ') || to_char(cohort.first_complete_date + 63, 'MM/DD/YYYY')
                       WHEN fes.status = 'Required'
                            AND fes.status_desc = 'Required - Initial term'
                            AND (v_etl_date >= cohort.first_complete_date + 49 OR (sume_eval.evaluation_completed IS NOT NULL AND dire_eval.evaluation_score < 3))
                            AND dean_eval.evaluation_completed IS NULL THEN
                        '4. Dean evaluations for ' || rec.semester_desc || ' must be completed ' || nvl2(fht.superior_username, 'by ' || fht.superior_username || ' before ', 'before ') || to_char(cohort.first_complete_date + 63, 'MM/DD/YYYY')
                       WHEN fes.status = 'Required'
                            AND fes.status_desc = 'Required - Initial term'
                            AND v_etl_date < cohort.first_complete_date + 49 THEN
                        '4. Dean evaluations for ' || rec.semester_desc || ' will be required after ' || to_char(cohort.first_complete_date + 49, 'MM/DD/YYYY')
                       -- all else Required
                       WHEN fes.status = 'Required'
                            AND v_etl_date >= rec.dean_end_date
                            AND dean_eval.evaluation_completed IS NULL THEN
                        '4. Dean evaluations for ' || rec.semester_desc || ' must be completed ' || nvl2(fht.superior_username, 'by ' || fht.superior_username || ' before ', 'before ') || to_char(rec.dean_end_date, 'MM/DD/YYYY')
                       WHEN fes.status = 'Required'
                            AND (v_etl_date >= rec.dean_start_date OR (sume_eval.evaluation_completed IS NOT NULL AND dire_eval.evaluation_score < 3))
                            AND dean_eval.evaluation_completed IS NULL THEN
                        '4. Dean evaluations for ' || rec.semester_desc || ' must be completed ' || nvl2(fht.superior_username, 'by ' || fht.superior_username || ' before ', 'before ') || to_char(rec.dean_end_date, 'MM/DD/YYYY')
                       WHEN fes.status = 'Retroactive'
                            AND v_etl_date >= rec.retro_dean_end_date
                            AND dean_eval.evaluation_completed IS NULL THEN
                        '4. Dean evaluations for ' || rec.semester_desc || ' must be completed ' || nvl2(fht.superior_username, 'by ' || fht.superior_username || ' before ', 'before ') || to_char(rec.retro_dean_end_date, 'MM/DD/YYYY')
                       WHEN fes.status = 'Retroactive'
                            AND (v_etl_date >= rec.retro_dean_start_date OR (sume_eval.evaluation_completed IS NOT NULL AND dire_eval.evaluation_score < 3))
                            AND dean_eval.evaluation_completed IS NULL THEN
                        '4. Dean evaluations for ' || rec.semester_desc || ' must be completed ' || nvl2(fht.superior_username, 'by ' || fht.superior_username || ' before ', 'before ') || to_char(rec.retro_dean_end_date, 'MM/DD/YYYY')
                       WHEN fes.status = 'Retroactive'
                            AND v_etl_date < rec.retro_dean_start_date
                            AND dean_eval.evaluation_completed IS NULL THEN
                        '4. Dean evaluations for ' || rec.semester_desc || ' will begin on ' || to_char(rec.retro_dean_end_date, 'MM/DD/YYYY')
                       WHEN sume_eval.evaluation_completed + 14 < v_etl_date + 1 -- completed the sume evaluation; evaluation_completed is null otherwise
                            AND dire_eval.evaluation_score IS NOT NULL -- must have score to be dire evaluation
                            AND dean_eval.evaluation_completed IS NULL -- no eval completed yet
                        THEN
                        '4. Dean evaluations for ' || rec.semester_desc || ' must be completed ' || nvl2(fht.superior_username, 'by ' || fht.superior_username || ' before ', 'before ') ||
                        to_char(sume_eval.evaluation_completed + 14, 'MM/DD/YYYY') -- same date for yellow and reds
                       WHEN sume_eval.evaluation_completed < v_etl_date + 1 -- completed the sume evaluation; evaluation_completed is null otherwise
                            AND dire_eval.evaluation_score IS NOT NULL -- must have score to be dire evaluation
                            AND dean_eval.evaluation_completed IS NULL -- no eval completed yet
                        THEN
                        '4. Dean evaluations for ' || rec.semester_desc || ' must be completed ' || nvl2(fht.superior_username, 'by ' || fht.superior_username || ' before ', 'before ') ||
                        to_char(sume_eval.evaluation_completed + 14, 'MM/DD/YYYY') -- same date for yellow and reds
                       WHEN self_eval.evaluation_completed + 42 < v_etl_date + 1 -- completed the optional self evaluation; evaluation_completed is null otherwise
                            AND dire_eval.evaluation_completed IS NULL -- no eval completed yet
                            AND sume_eval.evaluation_completed IS NULL -- no eval completed yet
                        THEN
                        '4. Dean evaluations for ' || rec.semester_desc || ' must be completed ' || nvl2(fht.superior_username, 'by ' || fht.superior_username || ' before ', 'before ') ||
                        to_char(self_eval.evaluation_completed + 42, 'MM/DD/YYYY') -- same date for yellow and reds
                       WHEN self_eval.evaluation_completed + 28 < v_etl_date + 1 -- completed the optional self evaluation; evaluation_completed is null otherwise
                            AND dire_eval.evaluation_completed IS NULL -- no eval completed yet
                            AND sume_eval.evaluation_completed IS NULL -- no eval completed yet
                        THEN
                        '4. Dean evaluations for ' || rec.semester_desc || ' must be completed ' || nvl2(fht.superior_username, 'by ' || fht.superior_username || ' before ', 'before ') ||
                        to_char(self_eval.evaluation_completed + 42, 'MM/DD/YYYY') -- same date for yellow and reds
                       WHEN fes.status = 'Required'
                            AND v_etl_date < rec.dean_start_date
                            AND dean_eval.evaluation_completed IS NULL THEN
                        '4. Dean evaluations will begin on ' || to_char(rec.dean_start_date, 'MM/DD/YYYY')
                       WHEN fes.status = 'Not Required' THEN
                        '4. Dean evaluations for ' || rec.semester_desc || ' are not required'
                       WHEN fes.status = 'Pending'
                            AND fes.camp_code = 'D' THEN
                        'Self evaluations for ' || rec.semester_desc || ' are not ready to begin'
                       WHEN fes.status = 'Pending'
                            AND fes.camp_code = 'R' THEN
                        'Self evaluations for ' || rec.semester_desc || ' begin on ' || to_char(rec.dire_start_date, 'MM/DD/YYYY')
                       WHEN fes.status = 'Optional' THEN
                        'Self evaluations for ' || rec.semester_desc || ' are available but not required'
                       END AS status_desc,
                       'https://facultyportfolio.liberty.edu/evaluations/' || cohort.pidm || '/' || rec.fpt_term_code AS url,
                       standard_hash(v_cat_code || cohort.term_code || cohort.pidm || cohort.camp_code || cohort.coll_code, 'MD5') unique_id,
                       CASE
                       WHEN dire_eval.evaluation_completed IS NOT NULL -- direct evaluation done
                            AND dire_eval.evaluation_score < 3 -- direct evaluation scored
                            AND sume_eval.evaluation_completed IS NOT NULL -- sume evaluation done
                            AND upper(nvl(sume_eval.approver_username, '<NULL>')) <> upper(nvl(dire_eval.approver_username, '<NULL>')) -- cannot be the same person do direct and summative 
                            AND dean_eval.evaluation_completed IS NOT NULL -- dean evaluation done
                        THEN
                        dean_eval.evaluation_completed
                       WHEN dire_eval.evaluation_completed IS NOT NULL -- direct evaluation done
                            AND dire_eval.evaluation_score < 3 -- direct evaluation scored 
                            AND dean_eval.evaluation_completed IS NOT NULL -- dean evaluation done
                        THEN
                        dean_eval.evaluation_completed
                       WHEN dire_eval.evaluation_completed IS NOT NULL -- direct evaluation done
                            AND dire_eval.evaluation_score >= 3 -- direct evaluation scored               
                            AND sume_eval.evaluation_completed IS NOT NULL -- sume evaluation done
                            AND upper(nvl(sume_eval.approver_username, '<NULL>')) <> upper(nvl(dire_eval.approver_username, '<NULL>')) -- cannot be the same person do direct and summative 
                            AND dean_eval.evaluation_completed IS NULL -- dean evaluation OPTIONAL 
                        THEN
                        sume_eval.evaluation_completed
                       WHEN dean_eval.evaluation_completed IS NOT NULL -- dean evaluation done
                        THEN
                        dean_eval.evaluation_completed
                       END AS evaluation_date,
                       CASE
                        WHEN cohort.camp_code = 'R'
                             AND cohort.term_code <= '202420' THEN -- direct assessments were broken for resident in 202420
                         3 -- auto push this score
                        WHEN dire_eval.evaluation_completed IS NOT NULL
                             AND dire_eval.evaluation_score IS NULL THEN
                         3 -- rare, but sometimes we don't get any scores back, so default to passing since this is self evaluations
                      ELSE
                       dire_eval.evaluation_score
                      END AS evaluation_score, -- once the dean evaluation is done, get the LOWEST direct evaluation scored 
                      v_etl_date AS activity_date
                 FROM utl_d_aa.fpt_cohort cohort
                 JOIN utl_d_aa.fpt_evaluations_status fes
                   ON fes.term_code = cohort.term_code
                  AND fes.pidm = cohort.pidm
                  AND fes.camp_code = cohort.camp_code
                  AND fes.coll_code = cohort.coll_code
                 LEFT JOIN (SELECT assessment.portfolio,
                                  assessment.id AS assessment_id,
                                  rec.term_code AS term_code,
                                  assessment.campus AS camp_code,
                                  assessment.activity_date AS evaluation_completed,
                                  gobtpac_external_user AS approver_username,
                                  resp.question_choice AS evaluation_score,
                                  rank() over(PARTITION BY assessment.term, assessment.campus, assessment.portfolio ORDER BY assessment.activity_date ASC, nvl(resp.question_choice, 0) ASC, rownum) ranking -- get first evaluation and lowest score
                             FROM zfacultyportfolio.assessment
                             LEFT JOIN zfacultyportfolio.question_response resp
                               ON resp.assessment = assessment.id
                             LEFT JOIN general.gobtpac
                               ON gobtpac_pidm = assessment.pidm
                            WHERE assessment.assessmenttype = 1 -- faculty self evaluation
                              AND assessment.completed = 'Y' -- all questions answered
                              AND assessment.term = rec.fpt_term_code -- fpt_term_code here 
                              AND assessment.campus = rec.camp_code) self_eval
                   ON self_eval.term_code = cohort.term_code
                  AND self_eval.camp_code = cohort.camp_code
                  AND self_eval.portfolio = cohort.portfolio
                  AND self_eval.ranking = 1
                 LEFT JOIN (SELECT assessment.portfolio,
                                  assessment.id AS assessment_id,
                                  rec.term_code AS term_code,
                                  assessment.campus AS camp_code,
                                  assessment.activity_date AS evaluation_completed,
                                  gobtpac_external_user AS approver_username,
                                  spriden_last_name || ', ' || spriden_first_name AS approver,
                                  CASE
                                  WHEN assessment.assessmenttype = 2 THEN
                                   'Instructional Mentor'
                                  WHEN assessment.assessmenttype = 3 THEN
                                   'Chair'
                                  END AS approver_position,
                                  resp.question_choice AS evaluation_score,
                                  rank() over(PARTITION BY assessment.term, assessment.campus, assessment.portfolio ORDER BY assessment.activity_date ASC, resp.question_choice ASC, rownum) ranking -- get first evaluation and lowest score
                             FROM zfacultyportfolio.assessment
                             JOIN saturn.spriden
                               ON spriden_pidm = assessment.pidm
                              AND spriden_change_ind IS NULL
                             JOIN zfacultyportfolio.question_response resp
                               ON resp.assessment = assessment.id
                              AND resp.question_choice IS NOT NULL -- must have scores for direct evaluations to be considered
                             LEFT JOIN general.gobtpac
                               ON gobtpac_pidm = assessment.pidm
                            WHERE assessment.assessmenttype IN (2, 3) -- IM or Chair for direct evaluations 
                              AND assessment.completed = 'Y' -- all questions answered
                              AND assessment.term = rec.fpt_term_code -- fpt_term_code here 
                              AND assessment.campus = rec.camp_code) dire_eval
                   ON dire_eval.term_code = cohort.term_code
                  AND dire_eval.camp_code = cohort.camp_code
                  AND dire_eval.portfolio = cohort.portfolio
                  AND dire_eval.ranking = 1
                 LEFT JOIN (SELECT assessment.portfolio,
                                  assessment.id AS assessment_id,
                                  rec.term_code AS term_code,
                                  assessment.campus AS camp_code,
                                  assessment.activity_date AS evaluation_completed,
                                  gobtpac_external_user AS approver_username,
                                  assessment.pidm AS approver_pidm,
                                  spriden_last_name || ', ' || spriden_first_name AS approver,
                                  CASE
                                  WHEN assessment.assessmenttype = 3 THEN
                                   'Chair'
                                  WHEN assessment.assessmenttype = 4 THEN
                                   'Assistant/Associate Dean'
                                  END AS approver_position,
                                  NULL AS evaluation_score, -- no numeric scores for summative evaluations
                                  rank() over(PARTITION BY assessment.term, assessment.campus, assessment.portfolio ORDER BY assessment.activity_date ASC, rownum) ranking -- get first evaluation and lowest score
                             FROM zfacultyportfolio.assessment
                             JOIN saturn.spriden
                               ON spriden_pidm = assessment.pidm
                              AND spriden_change_ind IS NULL
                             LEFT JOIN general.gobtpac
                               ON gobtpac_pidm = assessment.pidm
                            WHERE assessment.assessmenttype IN (3, 4) -- Chair or AD/Dean for summative evaluations
                              AND assessment.comments IS NOT NULL -- must have comments for summative evaluations
                              AND assessment.completed = 'Y' -- all questions answered
                              AND assessment.term = rec.fpt_term_code -- fpt_term_code here 
                              AND assessment.campus = rec.camp_code) sume_eval
                   ON sume_eval.term_code = cohort.term_code
                  AND sume_eval.camp_code = cohort.camp_code
                  AND sume_eval.portfolio = cohort.portfolio
                  AND sume_eval.ranking = 1
                 LEFT JOIN (SELECT dean_evaluation.portfolio,
                                  dean_evaluation.id AS assessment_id,
                                  rec.term_code AS term_code,
                                  nvl(dean_evaluation.campus, rec.camp_code) AS camp_code,
                                  dean_evaluation.completed_date AS evaluation_completed,
                                  gobtpac_external_user AS approver_username,
                                  dean_evaluation.author AS approver_pidm,
                                  spriden_last_name || ', ' || spriden_first_name AS approver,
                                  'Dean' AS approver_position,
                                  NULL AS evaluation_score, -- no numeric scores for dean evaluations
                                  rank() over(PARTITION BY dean_evaluation.term, dean_evaluation.campus, dean_evaluation.portfolio ORDER BY dean_evaluation.completed_date ASC, rownum) ranking -- get first evaluation and lowest score 
                             FROM zfacultyportfolio.dean_evaluation
                             JOIN saturn.spriden
                               ON spriden_pidm = dean_evaluation.author
                              AND spriden_change_ind IS NULL
                             LEFT JOIN general.gobtpac
                               ON gobtpac_pidm = dean_evaluation.author
                            WHERE dean_evaluation.completed = 'Y' -- all questions answered 
                              AND dean_evaluation.term = rec.fpt_term_code -- fpt_term_code here 
                              AND nvl(dean_evaluation.campus, rec.camp_code) = rec.camp_code -- NVL required here; no campus listed until 202520
                           ) dean_eval
                   ON dean_eval.term_code = cohort.term_code
                  AND dean_eval.camp_code = cohort.camp_code
                  AND dean_eval.portfolio = cohort.portfolio
                  AND dean_eval.ranking = 1
               -- get current positions to find who should be the evaluator - so we can hunt them down :)
                 LEFT JOIN (SELECT fht.pidm,
                                  fht.superior_pidm,
                                  fht.superior_username,
                                  fht.superior,
                                  fht.superior_position,
                                  fht.camp_code,
                                  fht.coll_code,
                                  fht.from_date,
                                  fht.to_date,
                                  rank() over(PARTITION BY fht.pidm, fht.camp_code, fht.coll_code ORDER BY fht.from_date DESC, fht.activity_date DESC, rownum) ranking -- used to sort out the bad data in the FHT
                             FROM utl_d_aa.faculty_hierarchy fht
                            WHERE fht.hierarchy_title_id <> 0 -- exclude FSC role
                              AND fht.superior_position = 'Dean'
                              AND v_etl_date BETWEEN fht.from_date AND fht.to_date -- get current role(s);  keep inside subquery
                           ) fht
                   ON fht.pidm = cohort.pidm
                  AND fht.camp_code = cohort.camp_code
                  AND fht.coll_code = cohort.coll_code
                  AND fht.ranking = 1
                WHERE cohort.term_code = rec.term_code
                  AND cohort.camp_code = rec.camp_code) src
         LEFT JOIN utl_d_aa.fpt_evaluations_audit tgt
           ON tgt.unique_id = standard_hash(v_cat_code || src.term_code || src.pidm || src.camp_code || src.coll_code, 'MD5') --unique_id
        WHERE 1 = 1
          AND (tgt.pidm IS NULL -- missing from target table
              OR coalesce(tgt.approver, 'X') <> coalesce(src.approver, 'X') --
              OR coalesce(tgt.approver_username, 'X') <> coalesce(src.approver_username, 'X') --
              OR coalesce(tgt.approver_position, 'X') <> coalesce(src.approver_position, 'X') --
              OR coalesce(tgt.category_code, 'X') <> coalesce(src.category_code, 'X') --
              OR coalesce(tgt.status_color, 'X') <> coalesce(src.status_color, 'X') --
              OR coalesce(tgt.status_icon, 'X') <> coalesce(src.status_icon, 'X') --
              OR coalesce(tgt.status_desc, 'X') <> coalesce(src.status_desc, 'X') --
              OR coalesce(tgt.url, 'X') <> coalesce(src.url, 'X') --
              OR coalesce(tgt.evaluation_score, 0) <> coalesce(src.evaluation_score, 0) --
              OR coalesce(tgt.evaluation_date, v_etl_date) <> coalesce(src.evaluation_date, v_etl_date) --
              )) src
ON (tgt.unique_id = src.unique_id)
WHEN MATCHED THEN
UPDATE
   SET tgt.aidy_code         = src.aidy_code,
       tgt.term_code         = src.term_code,
       tgt.pidm              = src.pidm,
       tgt.camp_code         = src.camp_code,
       tgt.coll_code         = src.coll_code,
       tgt.approver          = src.approver,
       tgt.approver_username = src.approver_username,
       tgt.approver_position = src.approver_position,
       tgt.category_code     = src.category_code,
       tgt.status_color      = src.status_color,
       tgt.status_icon       = src.status_icon,
       tgt.status_desc       = src.status_desc,
       tgt.url               = src.url,
       tgt.evaluation_score  = src.evaluation_score,
       tgt.evaluation_date   = src.evaluation_date,
       tgt.activity_date     = src.activity_date
WHEN NOT MATCHED THEN
INSERT
(aidy_code,
 term_code,
 pidm,
 camp_code,
 coll_code,
 approver,
 approver_username,
 approver_position,
 category_code,
 status_color,
 status_icon,
 status_desc,
 url,
 unique_id,
 evaluation_date,
 evaluation_score,
 activity_date)
VALUES
(src.aidy_code,
 src.term_code,
 src.pidm,
 src.camp_code,
 src.coll_code,
 src.approver,
 src.approver_username,
 src.approver_position,
 src.category_code,
 src.status_color,
 src.status_icon,
 src.status_desc,
 src.url,
 src.unique_id,
 src.evaluation_date,
 src.evaluation_score,
 src.activity_date);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || v_cat_code || ' - ' || rec.term_code || ' - ' || rec.camp_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
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
ROLLBACK;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
END etl_aa_fpt_evaluations_audit_dean;

PROCEDURE etl_aa_fpt_evaluations_tableau(jobnumber NUMBER, processid VARCHAR2, processname VARCHAR2) IS
/*
Table: utl_d_lms.fpt_evaluations_tableau

Primary Keys: NONE

Unique index: TERM_CODE, CAMP_CODE, COLL_CODE, PIDM

Purpose: Table that stages the data for the FPT dashboard that stores the instructor, college/campus they taught (can contain multiple), and helps determine when evaluations are required.

Conditions: instructor gets a record in cohort table when they first get a course; only run current terms

*/
--DECLARE
--- PARAMS
v_etl_date  DATE := SYSDATE;
v_msg       VARCHAR2(2000);
v_instance  VARCHAR2(50) := upper('ALL'); -- inst from the jams job; used for determining instance
v_partition NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0


v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_aa_fpt_evaluations_tableau';
CURSOR c_terms IS
SELECT fes.term_code,
       fes.group_code,
       fes.aidy_code,
       fes.camp_code,
       fes.start_date,
       fes.end_date,
       fes.semester,
       REPLACE(fes.semester_desc, ' Med', '') AS semester_desc, -- remove med to match the std term description
       fes.self_start_date,
       fes.dire_start_date,
       fes.sume_start_date,
       fes.dean_start_date,
       fes.dean_end_date,
       fes.retro_self_start_date,
       fes.retro_dire_start_date,
       fes.retro_sume_start_date,
       fes.retro_dean_start_date,
       fes.retro_dean_end_date,
       fes.cv_start_date,
       fes.cv_end_date,
       fes.fpt_term_code,
       fes.activity_date
  FROM utl_d_aa.fpt_evaluations_schedule fes
 WHERE 1 = 1
   AND fes.group_code IN ('STD', 'MED')
   AND fes.semester IN ('FAL', 'SPR') -- only fall and spring fes are when we do evaluations
   AND SYSDATE BETWEEN fes.start_date - 21 AND fes.end_date -- start earlier to get the dashboard to show records when the Provost Office needs them (ex: JAN 1 start showing spring)
   AND ((fes.semester = 'FAL' AND SYSDATE >= to_date(extract(YEAR FROM SYSDATE) || '-08-15', 'YYYY-MM-DD') --
       AND SYSDATE <= to_date(extract(YEAR FROM SYSDATE) || '-12-31', 'YYYY-MM-DD') + 1) --
       OR (fes.semester = 'SPR' AND SYSDATE <= to_date(extract(YEAR FROM SYSDATE) || '-08-15', 'YYYY-MM-DD') --
       AND SYSDATE >= to_date(extract(YEAR FROM SYSDATE) || '-01-01', 'YYYY-MM-DD')))
   AND fes.term_code >= '202440' -- inception for tableau dashboard
UNION
SELECT fes.term_code,
       fes.group_code,
       fes.aidy_code,
       fes.camp_code,
       fes.start_date,
       fes.end_date,
       fes.semester,
       REPLACE(fes.semester_desc, ' Med', '') AS semester_desc, -- remove med to match the std term description
       fes.self_start_date,
       fes.dire_start_date,
       fes.sume_start_date,
       fes.dean_start_date,
       fes.dean_end_date,
       fes.retro_self_start_date,
       fes.retro_dire_start_date,
       fes.retro_sume_start_date,
       fes.retro_dean_start_date,
       fes.retro_dean_end_date,
       fes.cv_start_date,
       fes.cv_end_date,
       fes.fpt_term_code,
       fes.activity_date
  FROM utl_d_aa.fpt_evaluations_schedule fes
 WHERE 1 = 1
   AND fes.group_code IN ('STD', 'MED')
   AND fes.semester IN ('FAL', 'SPR') -- only fall and spring fes are when we do evaluations
   AND SYSDATE BETWEEN fes.start_date AND fes.end_date + 365 -- ONLY run fes in the last year
   AND fes.term_code >= '202440' -- inception for tableau dashboard
 ORDER BY 1,
          3;
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
v_msg     := 'START - ' || rec.term_code || ' - ' || rec.camp_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'DELETE (PENDING) - ' || rec.term_code || ' - ' || rec.camp_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_lock.sleep(0.5); -- pause half second
DELETE FROM utl_d_aa.fpt_evaluations_tableau
 WHERE term_code = rec.term_code
   AND camp_code = rec.camp_code;
-- DO NOT COMMIT HERE;
-- needs constant uptime 
INSERT INTO utl_d_aa.fpt_evaluations_tableau
(aidy_code,
 term_code,
 semester,
 pidm,
 instructor,
 instructor_username,
 email_address,
 camp_code,
 campus,
 coll_code,
 coll_desc,
 im_usernames,
 chair_usernames,
 dean_usernames,
 fsc_usernames,
 admin_usernames,
 approver,
 approver_username,
 category_code,
 status,
 status_color,
 status_icon,
 status_desc,
 status_reason,
 url,
 unique_id,
 first_complete_date,
 evaluation_date,
 evaluation_score,
 category_desc,
 course_list,
 seats,
 fht_configuration,
 activity_date)
SELECT cohort.aidy_code,
       cohort.term_code,
       rec.semester_desc AS semester,
       cohort.pidm,
       cohort.instructor || ' - ' || cohort.instructor_username AS instructor,
       cohort.instructor_username,
       cohort.email_address,
       cohort.camp_code,
       CASE
       WHEN cohort.camp_code = 'R' THEN
        'Resident'
       ELSE
        'Online'
       END AS campus,
       cohort.coll_code,
       cohort.coll_desc,
       fht_im.usernames AS im_usernames,
       fht_chair.usernames AS chair_usernames,
       fht_dean.usernames AS dean_usernames,
       fht_fsc.usernames AS fsc_usernames,
       (SELECT regexp_replace(listagg(lower(username), '-') within GROUP(ORDER BY 1), '([^-]*)(-\1)+($|-)', '\1\3') usernames FROM utl_d_aa.secadmin) AS admin_usernames,
       CASE
       WHEN fea.approver IS NULL THEN -- avoid only the ' - ' to show up when there is no approver found
        NULL
       ELSE
        fea.approver || ' - ' || fea.approver_username
       END AS approver,
       fea.approver_username,
       fea.category_code,
       nvl((SELECT 'Complete' -- this is the ONLY place where we want to mark status='Complete'
             FROM utl_d_aa.fpt_evaluations_audit dean_eval
            WHERE dean_eval.term_code = cohort.term_code
              AND dean_eval.pidm = cohort.pidm
              AND dean_eval.camp_code = cohort.camp_code
              AND dean_eval.coll_code = cohort.coll_code
              AND dean_eval.category_code = 'DEAN' -- only check dean evaluation for completion; ensuring one row returns per pidm
              AND (dean_eval.status_color || dean_eval.status_icon IN ('graycheck_mark', 'greenarrowhead', 'greencheck_mark')) -- completed evaluation for dean evaluations
           ), fes.status) AS status,
       fea.status_color,
       fea.status_icon,
       fea.status_desc, -- short desc
       CASE
       WHEN fea.category_code = 'CURV' THEN
        fea.status_desc
       WHEN fea.status_icon IN ('minus', 'check_mark') THEN
        fea.status_desc
       ELSE
        fea.status_desc || '. ' || fes.status_desc
       END AS status_reason, -- long desc
       fea.url,
       fea.unique_id,
       cohort.first_complete_date,
       fea.evaluation_date,
       fes.evaluation_score,
       cat_codes.category_desc,
       cohort.course_list,
       cohort.seats,
       CASE
       WHEN fea.approver IS NULL THEN
        'FHT role needed! Contact FSC(s) ' || REPLACE(fht_fsc.usernames, '-', '; ')
       ELSE
        ' ' -- white space so NULL does not show up on the dashboard tooltip :|
       END AS fht_configuration,
       v_etl_date AS activity_date
  FROM utl_d_aa.fpt_cohort cohort
  JOIN utl_d_aa.fpt_evaluations_audit fea
    ON fea.term_code = cohort.term_code
   AND fea.pidm = cohort.pidm
   AND fea.camp_code = cohort.camp_code
   AND fea.coll_code = cohort.coll_code
  JOIN utl_d_aa.fpt_cat_code cat_codes
    ON cat_codes.category_code = fea.category_code
  JOIN utl_d_aa.fpt_evaluations_status fes
    ON fes.term_code = cohort.term_code
   AND fes.pidm = cohort.pidm
   AND fes.camp_code = cohort.camp_code
   AND fes.coll_code = cohort.coll_code
   AND fes.status NOT IN ('Not Required') -- DO NOT SHOW COMPLETED RECORDS ON THE DASHBOARD 
-- get current positions to find who should be the evaluator - so we can hunt them down :)
  LEFT JOIN (SELECT fht.pidm,
                    fht.camp_code,
                    fht.coll_code,
                    'Instructional Mentor' AS superior_position,
                    regexp_replace(listagg(DISTINCT lower(fht.superior_username), '-') within GROUP(ORDER BY 1), '([^-]*)(-\1)+($|-)', '\1\3') AS usernames
               FROM utl_d_aa.faculty_hierarchy fht
              WHERE v_etl_date BETWEEN fht.from_date AND fht.to_date -- get current role(s);  keep inside subquery
                AND fht.superior_position = 'Instructional Mentor'
              GROUP BY fht.pidm,
                       fht.camp_code,
                       fht.coll_code) fht_im
    ON fht_im.pidm = cohort.pidm
   AND fht_im.camp_code = cohort.camp_code
   AND fht_im.coll_code = cohort.coll_code
  LEFT JOIN (SELECT fht.pidm,
                    fht.camp_code,
                    fht.coll_code,
                    'Chair' AS superior_position,
                    regexp_replace(listagg(DISTINCT lower(fht.superior_username), '-') within GROUP(ORDER BY 1), '([^-]*)(-\1)+($|-)', '\1\3') AS usernames
               FROM utl_d_aa.faculty_hierarchy fht
              WHERE v_etl_date BETWEEN fht.from_date AND fht.to_date -- get current role(s);  keep inside subquery
                AND fht.superior_position = 'Chair'
              GROUP BY fht.pidm,
                       fht.camp_code,
                       fht.coll_code) fht_chair
    ON fht_chair.pidm = cohort.pidm
   AND fht_chair.camp_code = cohort.camp_code
   AND fht_chair.coll_code = cohort.coll_code
  LEFT JOIN (SELECT fht.pidm,
                    fht.camp_code,
                    fht.coll_code,
                    'Dean' AS superior_position,
                    regexp_replace(listagg(DISTINCT lower(fht.superior_username), '-') within GROUP(ORDER BY 1), '([^-]*)(-\1)+($|-)', '\1\3') AS usernames
               FROM utl_d_aa.faculty_hierarchy fht
              WHERE v_etl_date BETWEEN fht.from_date AND fht.to_date -- get current role(s);  keep inside subquery
                AND fht.superior_position IN ('Assistant/Associate Dean', 'Dean', 'Provost', 'Vice Provost')
              GROUP BY fht.pidm,
                       fht.camp_code,
                       fht.coll_code) fht_dean
    ON fht_dean.pidm = cohort.pidm
   AND fht_dean.camp_code = cohort.camp_code
   AND fht_dean.coll_code = cohort.coll_code
  LEFT JOIN (SELECT fht.pidm,
                    fht.camp_code,
                    fht.coll_code,
                    'Faculty Support Coordinator' AS superior_position,
                    regexp_replace(listagg(DISTINCT lower(fht.superior_username), '-') within GROUP(ORDER BY 1), '([^-]*)(-\1)+($|-)', '\1\3') AS usernames
               FROM utl_d_aa.faculty_hierarchy fht
              WHERE v_etl_date BETWEEN fht.from_date AND fht.to_date -- get current role(s);  keep inside subquery
                AND fht.superior_position IN ('Faculty Support Coordinator')
              GROUP BY fht.pidm,
                       fht.camp_code,
                       fht.coll_code) fht_fsc
    ON fht_fsc.pidm = cohort.pidm
   AND fht_fsc.camp_code = cohort.camp_code
   AND fht_fsc.coll_code = cohort.coll_code
 WHERE cohort.term_code = rec.term_code
   AND cohort.camp_code = rec.camp_code;
v_count := SQL%ROWCOUNT;
IF v_count > 0 THEN
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'DELETE/INSERT - ' || rec.term_code || ' - ' || rec.camp_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
ELSE
ROLLBACK;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'ROLLBACK - ' || rec.term_code || ' - ' || rec.camp_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(0));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
dbms_output.put_line(' --------- ');
END IF;
END LOOP; -- c_terms
-- remove any records older than a year;
DELETE utl_d_aa.fpt_evaluations_tableau fet
 WHERE NOT EXISTS (SELECT 1
          FROM utl_d_aa.fpt_evaluations_schedule fes
         WHERE 1 = 1
           AND fes.group_code IN ('STD', 'MED')
           AND fes.semester IN ('FAL', 'SPR') -- only fall and spring fes are when we do evaluations
           AND SYSDATE BETWEEN fes.start_date AND fes.end_date + 365 -- ONLY run fes in the last year 
           AND fes.term_code = fet.term_code);
v_count       := SQL%ROWCOUNT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'DELETE - ' || 'ALL' || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
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
ROLLBACK; -- leaving data as-is since we got errors
dbms_lock.sleep(0.5); -- pause half second
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'ROLLBACK - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
v_msg         := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
END etl_aa_fpt_evaluations_tableau;
 
END load_aa_etl_fpt;
