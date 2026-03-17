create or replace package load_aa_etl_pdb is
procedure etl_aa_pdb_enrollment_tableau(jobnumber number, processid varchar2, processname varchar2);
procedure etl_aa_pdb_retention_tableau(jobnumber number, processid varchar2, processname varchar2);
procedure etl_aa_pdb_persistence_tableau(jobnumber number, processid varchar2, processname varchar2);
procedure etl_aa_pdb_completion_time_tableau(jobnumber number, processid varchar2, processname varchar2);
procedure etl_aa_pdb_graduation_rate_tableau(jobnumber number, processid varchar2, processname varchar2);
procedure etl_aa_pdb_community_attendance_tableau(jobnumber number, processid varchar2, processname varchar2);
procedure etl_aa_pdb_convo_attendance_tableau(jobnumber number, processid varchar2, processname varchar2);
procedure etl_aa_pdb_cser_hours_tableau(jobnumber number, processid varchar2, processname varchar2);
procedure etl_aa_pdb_peak_convo_tableau(jobnumber number, processid varchar2, processname varchar2);
procedure etl_aa_pdb_eoc_surveys_tableau(jobnumber number, processid varchar2, processname varchar2);
procedure etl_aa_pdb_luo_credit_threshold_tableau(jobnumber number, processid varchar2, processname varchar2);
procedure etl_aa_pdb_course_success_tableau(jobnumber number, processid varchar2, processname varchar2);
procedure etl_aa_pdb_graduate_degrees_tableau(jobnumber number, processid varchar2, processname varchar2);
procedure etl_aa_pdb_student_fte_tableau(jobnumber number, processid varchar2, processname varchar2);
procedure etl_aa_pdb_gpa_tableau(jobnumber number, processid varchar2, processname varchar2);
end load_aa_etl_pdb;
/

create or replace package body load_aa_etl_pdb is

procedure etl_aa_pdb_enrollment_tableau(jobnumber number, processid varchar2, processname varchar2) IS
--DECLARE
--- PARAMS
v_etl_date  DATE := SYSDATE;
v_msg       VARCHAR2(2000);
v_instance  VARCHAR2(50) := upper('ALL'); -- inst from the jams job; used for determining instance
v_partition NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0 
v_count        NUMBER := 0;
v_delete_count NUMBER := 0;
v_insert_count NUMBER := 0;
v_elapsed      NUMBER := 0;
v_total_count  NUMBER := 0;
v_job_id       VARCHAR2(32);
v_proc         VARCHAR2(100) := 'etl_aa_pdb_enrollment_tableau';
CURSOR c_terms IS
-- ** THIS CURSOR MIGHT LOOK THE SAME, BUT IT IS DIFFERENT FROM THE RETENTION CURSOR **
SELECT DISTINCT terms.fa_proc_year AS aidy_code, -- distinct required
                CASE
                WHEN terms.fa_proc_year = (SELECT MIN(t1.fa_proc_year - 0) ady_code
                                             FROM zbtm.terms_by_group_v t1
                                            WHERE ((SYSDATE) BETWEEN t1.start_date AND t1.end_date)
                                               OR (SYSDATE) + 14 BETWEEN t1.start_date AND t1.end_date) THEN
                 to_date(to_char(trunc((SYSDATE) - 365.25 * 0) + (4 / 24), 'MM/DD/YYYY hh24:mi:ss'), 'MM/DD/YYYY hh24:mi:ss')
                WHEN terms.fa_proc_year = (SELECT MIN(t1.fa_proc_year - 101) ady_code
                                             FROM zbtm.terms_by_group_v t1
                                            WHERE ((SYSDATE) BETWEEN t1.start_date AND t1.end_date)
                                               OR (SYSDATE) + 14 BETWEEN t1.start_date AND t1.end_date) THEN
                 to_date(to_char(trunc((SYSDATE) - 365.25 * 1) + (4 / 24), 'MM/DD/YYYY hh24:mi:ss'), 'MM/DD/YYYY hh24:mi:ss')
                WHEN terms.fa_proc_year = (SELECT MIN(t1.fa_proc_year - 202) ady_code
                                             FROM zbtm.terms_by_group_v t1
                                            WHERE ((SYSDATE) BETWEEN t1.start_date AND t1.end_date)
                                               OR (SYSDATE) + 14 BETWEEN t1.start_date AND t1.end_date) THEN
                 to_date(to_char(trunc((SYSDATE) - 365.25 * 2) + (4 / 24), 'MM/DD/YYYY hh24:mi:ss'), 'MM/DD/YYYY hh24:mi:ss')
                WHEN terms.fa_proc_year = (SELECT MIN(t1.fa_proc_year - 303) ady_code
                                             FROM zbtm.terms_by_group_v t1
                                            WHERE ((SYSDATE) BETWEEN t1.start_date AND t1.end_date)
                                               OR (SYSDATE) + 14 BETWEEN t1.start_date AND t1.end_date) THEN
                 to_date(to_char(trunc((SYSDATE) - 365.25 * 3) + (4 / 24), 'MM/DD/YYYY hh24:mi:ss'), 'MM/DD/YYYY hh24:mi:ss')
                WHEN terms.fa_proc_year = (SELECT MIN(t1.fa_proc_year - 404) ady_code
                                             FROM zbtm.terms_by_group_v t1
                                            WHERE ((SYSDATE) BETWEEN t1.start_date AND t1.end_date)
                                               OR (SYSDATE) + 14 BETWEEN t1.start_date AND t1.end_date) THEN
                 to_date(to_char(trunc((SYSDATE) - 365.25 * 4) + (4 / 24), 'MM/DD/YYYY hh24:mi:ss'), 'MM/DD/YYYY hh24:mi:ss')
                WHEN terms.fa_proc_year = (SELECT MIN(t1.fa_proc_year - 505) ady_code
                                             FROM zbtm.terms_by_group_v t1
                                            WHERE ((SYSDATE) BETWEEN t1.start_date AND t1.end_date)
                                               OR (SYSDATE) + 14 BETWEEN t1.start_date AND t1.end_date) THEN
                 to_date(to_char(trunc((SYSDATE) - 365.25 * 5) + (4 / 24), 'MM/DD/YYYY hh24:mi:ss'), 'MM/DD/YYYY hh24:mi:ss')
                WHEN terms.fa_proc_year = (SELECT MIN(t1.fa_proc_year - 1806) ady_code
                                             FROM zbtm.terms_by_group_v t1
                                            WHERE ((SYSDATE) BETWEEN t1.start_date AND t1.end_date)
                                               OR (SYSDATE) + 14 BETWEEN t1.start_date AND t1.end_date) THEN
                 to_date(to_char(trunc((SYSDATE) - 365.25 * 6) + (4 / 24), 'MM/DD/YYYY hh24:mi:ss'), 'MM/DD/YYYY hh24:mi:ss')
                ELSE
                 NULL
                END AS ytd_timestamp, -- simulates runs at 4am everyday
                MIN(terms.term_code) over(PARTITION BY terms.fa_proc_year) AS min_cohort_term_code,
                MAX(terms.term_code) over(PARTITION BY terms.fa_proc_year) AS max_cohort_term_code
  FROM zbtm.terms_by_group_v terms
 WHERE to_date('06/30/20' || substr(terms.fa_proc_year, 3, 2), 'mm/dd/yyyy') > (SYSDATE) - (365.25 * 5) -- refresh the last 5 years
   AND to_date('07/01/20' || substr(terms.fa_proc_year, 1, 2), 'mm/dd/yyyy') < (SYSDATE) + (365.25 * 0)
   AND terms.semester NOT IN ('WIN')
   AND terms.group_code IN ('STD', 'MED') -- only get standard terms and med
   AND (NOT EXISTS (SELECT 1 FROM utl_d_aa.pdb_enrollment_tableau) -- Return rows if table is empty
        OR EXISTS (SELECT 1 FROM utl_d_aa.pdb_enrollment_tableau tgt HAVING MAX(trunc(tgt.activity_date)) <> trunc((SYSDATE)))) -- Check if data has already been loaded today
 ORDER BY terms.fa_proc_year DESC;
BEGIN
-- dbms_output.enable(buffer_size => NULL);
--
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
utl_d_aa.truncate_table(v_table_name => 'pdb_enrollment_tableau');
FOR rec IN c_terms
LOOP
v_count   := 0; -- reset count
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || rec.aidy_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- do not commit here; need constant uptime
INSERT INTO utl_d_aa.pdb_enrollment_tableau
(acad_year,
 campus,
 report_type,
 total_enrollment,
 total_seats,
 total_hours,
 activity_date)
-- get the cohort to determine what the student attributes are as of the last term of their enrollment; same definition as retention
WITH cohort AS
 (SELECT enrl.term_code,
         enrl.pidm,
         CASE
         WHEN enrl.camp_code = 'R' THEN
          'Resident'
         WHEN enrl.camp_code = 'D' THEN
          'LUO'
         END campus,
         degc_code_1 AS degc_code,
         stvdegc_acat_code,
         rank() over(PARTITION BY enrl.pidm, rec.aidy_code ORDER BY enrl.term_code DESC, rownum) last_enrl_rank -- return last enrollment of the year
    FROM utl_d_aim.szrenrl enrl
    JOIN zsaturn.szrlevl
      ON szrlevl_levl_code = enrl.levl_code
     AND szrlevl_is_univ = 'Y' -- this filter and the one below INCLUDES ('CT','IN','UG','GR','DR','JD','MD'); LUOA - Special Student High Schl-DE; Willmington School of the Bible
     AND szrlevl_has_awardable_cred = 'Y'
  -- IMPORTANT: we ARE looking for ALL enrollments - including zero (0) credit hours
    JOIN saturn.stvdegc
      ON enrl.degc_code_1 = stvdegc.stvdegc_code
    JOIN zbtm.terms_by_group_v terms
      ON terms.term_code = enrl.term_code
     AND terms.group_code IN ('STD', 'MED') -- only get standard terms and med
     AND terms.fa_proc_year = rec.aidy_code)
SELECT rec.aidy_code AS acad_year,
       cohort.campus, -- student campus; NOT course campus; and use the cohort campus here
       'ADY' AS report_type, -- YTD (year to date) OR ADY (as of the end);  we need the current academic year to run using szrenrl, but show that it is YTD.
       COUNT(DISTINCT crse.pidm) total_enrollment,
       COUNT(DISTINCT crse.pidm || crse.term_code || crse.crn) total_seats,
       round(SUM(crse.credit_hr)) total_hours,
       v_etl_date AS activity_date
  FROM utl_d_aim.szrcrse crse
  JOIN utl_d_aim.szrenrl enrl -- IMPORTANT: we ARE looking for ALL enrollments - including zero (0) credit hours
    ON enrl.term_code = crse.term_code
   AND enrl.pidm = crse.pidm
  JOIN cohort
    ON cohort.pidm = crse.pidm -- only join on pidm and not term or aidy
   AND cohort.last_enrl_rank = 1 -- select the student last term enrollment for the year
  JOIN zsaturn.szrlevl
    ON szrlevl_levl_code = enrl.levl_code
   AND szrlevl_is_univ = 'Y' -- this filter and the one below INCLUDES ('CT','IN','UG','GR','DR','JD','MD'); LUOA - Special Student High Schl-DE; Willmington School of the Bible
   AND szrlevl_has_awardable_cred = 'Y'
   AND crse.levl_code NOT IN ('PD') -- overkill; explicitly remove these courses because we do not want them to appear even if they are university level students
  JOIN zbtm.terms_by_group_v terms -- do not remove this join because we need to make sure we exclude any terms we do not want to pull into the totals
    ON terms.term_code = crse.term_code
   AND terms.group_code IN ('STD', 'MED') -- only get standard terms and med
   AND terms.fa_proc_year = rec.aidy_code
 WHERE terms.fa_proc_year NOT IN (SELECT DISTINCT t1.fa_proc_year FROM zbtm.terms_by_group_v t1 WHERE SYSDATE BETWEEN start_date AND end_date) -- do not run this for the current aidy
 GROUP BY cohort.campus;
v_insert_count := SQL%ROWCOUNT;
v_total_count  := v_total_count + v_insert_count; -- keep running total of rows processed
v_elapsed      := round((SYSDATE - v_etl_date) * 86400);
v_msg          := 'INSERT (ADY totals) - ' || rec.aidy_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_insert_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_insert_count);
INSERT INTO utl_d_aa.pdb_enrollment_tableau
(acad_year,
 campus,
 report_type,
 total_enrollment,
 total_seats,
 total_hours,
 activity_date)
-- get the cohort to determine what the student attributes are as of the last term of their enrollment; same definition as retention
WITH cohort AS
 (SELECT enrl.term_code,
         enrl.pidm,
         CASE
         WHEN enrl.camp_code = 'R' THEN
          'Resident'
         WHEN enrl.camp_code = 'D' THEN
          'LUO'
         END campus,
         degc_code_1 AS degc_code,
         stvdegc_acat_code,
         rank() over(PARTITION BY enrl.pidm, rec.aidy_code ORDER BY enrl.term_code DESC, rownum) last_enrl_rank -- return last enrollment of the year
    FROM utl_d_aim.szrenrl enrl
    JOIN zsaturn.szrlevl
      ON szrlevl_levl_code = enrl.levl_code
     AND szrlevl_is_univ = 'Y' -- this filter and the one below INCLUDES ('CT','IN','UG','GR','DR','JD','MD'); LUOA - Special Student High Schl-DE; Willmington School of the Bible
     AND szrlevl_has_awardable_cred = 'Y'
  -- IMPORTANT: we ARE looking for ALL enrollments - including zero (0) credit hours
    JOIN saturn.stvdegc
      ON enrl.degc_code_1 = stvdegc.stvdegc_code
    JOIN zbtm.terms_by_group_v terms
      ON terms.term_code = enrl.term_code
     AND terms.group_code IN ('STD', 'MED') -- only get standard terms and med
     AND terms.fa_proc_year = rec.aidy_code)
SELECT rec.aidy_code AS acad_year,
       cohort.campus, -- student campus; NOT course campus; and use the cohort campus here
       'YTD' AS report_type, -- ** THIS IS DIFFERENT FROM THE ABOVE INSERT ** -- YTD (year to date) OR ADY (as of the end);
       COUNT(DISTINCT sfrstca_pidm) AS total_enrollment, -- yes, we need the distinct here or we double/triple count
       COUNT(DISTINCT sfrstca_term_code || sfrstca_crn || sfrstca_pidm) AS total_seats, -- get all seats from the whole year; not shown in "aqua-marine" dashboard
       round(SUM(sfrstca_credit_hr)) AS total_hours, --get all hours from the whole year;  not shown in "aqua-marine" dashboard
       v_etl_date AS activity_date
  FROM saturn.sfrstca
  JOIN zbtm.terms_by_group_v terms -- do not remove this join because we need to make sure we exclude any terms we do not want to pull into the totals
    ON terms.term_code = sfrstca_term_code
   AND terms.group_code IN ('STD', 'MED') -- only get standard terms and med
   AND terms.fa_proc_year = rec.aidy_code
  JOIN cohort
    ON cohort.pidm = sfrstca_pidm -- only join on pidm and not term or aidy
   AND cohort.last_enrl_rank = 1 -- select the student last term enrollment for the year
  JOIN saturn.stvrsts
    ON stvrsts_code = sfrstca_rsts_code
   AND stvrsts_incl_sect_enrl = 'Y' -- aligns with AA tables
      --      AND stvrsts_incl_assess = 'Y' -- aligns with EM MR;
      -- IMPORTANT: we ARE looking for ALL enrollments - including zero (0) credit hours
   AND sfrstca_rsts_date <= rec.ytd_timestamp
   AND sfrstca_source_cde = 'BASE'
   AND sfrstca_levl_code <> 'PD' -- explicitly remove these courses because we do not want them to appear even if they are university level students
   AND sfrstca.sfrstca_seq_number = (SELECT MAX(d.sfrstca_seq_number)
                                       FROM saturn.sfrstca d
                                      WHERE d.sfrstca_pidm = sfrstca.sfrstca_pidm
                                        AND d.sfrstca_term_code = sfrstca.sfrstca_term_code
                                        AND d.sfrstca_crn = sfrstca.sfrstca_crn
                                        AND d.sfrstca_source_cde = sfrstca.sfrstca_source_cde
                                        AND d.sfrstca_rsts_date <= rec.ytd_timestamp -- simulates runs at 4am everyday
                                     )
  JOIN saturn.ssbsect
    ON ssbsect_term_code = sfrstca_term_code
   AND ssbsect_crn = sfrstca_crn
   AND ssbsect_subj_code <> 'NEWS' -- remove news cours
  JOIN zexec.zsavlcur lcur
    ON lcur.pidm = sfrstca_pidm
   AND sfrstca_term_code BETWEEN lcur.from_term AND lcur.end_term
  JOIN zsaturn.szrlevl
    ON szrlevl_levl_code = lcur.levl_code
   AND szrlevl_is_univ = 'Y' -- this filter and the one below INCLUDES ('CT','IN','UG','GR','DR','JD','MD'); LUOA - Special Student High Schl-DE; Willmington School of the Bible
   AND szrlevl_has_awardable_cred = 'Y'
 GROUP BY cohort.campus;
v_insert_count := v_insert_count + SQL%ROWCOUNT;
v_total_count  := v_total_count + v_insert_count; -- keep running total of rows processed
v_elapsed      := round((SYSDATE - v_etl_date) * 86400);
v_msg          := 'INSERT (YTD totals) - ' || rec.aidy_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_insert_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_insert_count);
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
END etl_aa_pdb_enrollment_tableau; --

procedure etl_aa_pdb_gpa_tableau(jobnumber number, processid varchar2, processname varchar2) is
/*
Table: pdb_gpa_tableau

Primary Keys: NONE

Unique index: NONE

Purpose:
- Staging data for the PDB that is used by the Provost Office.

Conditions:
-- - data should not show until the year is over
-- - hours must be > 0
-- - returning one row per academic year; show data associated with the last semester enrolled of the year
-- - student must be university level and in a program that has awardable credit; includes special students
-- - Current average GPA - (cumulative GPA as of report runtime);
-- - Report timing could cause drastic differences: If the we run anything during the semester, the only completions that we see are ones that are severely negative (equals 0 GPA)

--       SITE: UNIVERSITY DASHBOARDS
--   WORKBOOK: President's Dashboard
--DATA SOURCE: pdb_gpa_tableau
-- URL: https://reports.liberty.edu/#/site/Academics/views/ProgramEnrollmentNumbers/GPAByAcademicYear?:iid=1
*/
--DECLARE
--PARAMS
v_etl_date DATE := SYSDATE;
v_msg      VARCHAR2(2000);
v_instance VARCHAR2(50) := upper('ALL'); -- inst from the jams job; used for determining instance
v_partition NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
-- v_mod         NUMBER := 5; -- number of partitions to be created

v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_aa_pdb_gpa_tableau';
CURSOR c_terms IS
SELECT MIN(enrl.acad_year) AS min_aidy_code,MAX(enrl.acad_year) AS max_aidy_code,
       'College' AS dim_select,
       enrl.coll_desc_1 AS dim1,
       enrl.camp_code AS dim2
  FROM utl_d_aim.szrenrl enrl
  JOIN stvmajr
    ON stvmajr.stvmajr_code = enrl.majr_code_1
  JOIN zsaturn.szrlevl
    ON szrlevl_levl_code = enrl.levl_code
   AND szrlevl_is_univ = 'Y'
   AND szrlevl_has_awardable_cred = 'Y'
   AND enrl.yr_rank = 1 -- returns the last enrollment for the academic year
   AND enrl.term_hours > 0 -- must have hours
   AND enrl.acad_year IN (SELECT DISTINCT t.fa_proc_year AS aidy_code -- MUST BE A >= BC OF LAG FUNCTION
                            FROM zbtm.terms_by_group_v t
                           WHERE to_date('06/30/20' || substr(t.fa_proc_year, 3, 2), 'mm/dd/yyyy') > SYSDATE - (365 * 5) -- ALWAYS PULL 5 YEARS BACK
                             AND to_date('07/01/20' || substr(t.fa_proc_year, 1, 2), 'mm/dd/yyyy') <= SYSDATE - (365 * 1)
                             AND t.semester NOT IN ('WIN')
                             AND t.group_code IN ('STD'))
  JOIN stvlevl
    ON stvlevl.stvlevl_code = CASE
       WHEN enrl.levl_code IN ('UG', 'IN') THEN
        'UG'
       WHEN enrl.levl_code IN ('GR', 'DR', 'JD', 'MD') THEN
        'GR'
       ELSE
        enrl.levl_code
       END
 WHERE enrl.coll_desc_1 NOT IN ('English Language Institute')
   AND enrl.levl_code NOT IN ('CT')
 GROUP BY enrl.coll_desc_1,
          enrl.camp_code
UNION ALL
SELECT MIN(enrl.acad_year) AS min_aidy_code,MAX(enrl.acad_year) AS max_aidy_code,
       'College' AS dim_select,
       enrl.coll_desc_1 AS dim1,
       'ALL' AS dim2
  FROM utl_d_aim.szrenrl enrl
  JOIN stvmajr
    ON stvmajr.stvmajr_code = enrl.majr_code_1
  JOIN zsaturn.szrlevl
    ON szrlevl_levl_code = enrl.levl_code
   AND szrlevl_is_univ = 'Y'
   AND szrlevl_has_awardable_cred = 'Y'
   AND enrl.yr_rank = 1 -- returns the last enrollment for the academic year
   AND enrl.term_hours > 0 -- must have hours
   AND enrl.acad_year IN (SELECT DISTINCT t.fa_proc_year AS aidy_code -- MUST BE A >= BC OF LAG FUNCTION
                            FROM zbtm.terms_by_group_v t
                           WHERE to_date('06/30/20' || substr(t.fa_proc_year, 3, 2), 'mm/dd/yyyy') > SYSDATE - (365 * 5) -- ALWAYS PULL 5 YEARS BACK
                             AND to_date('07/01/20' || substr(t.fa_proc_year, 1, 2), 'mm/dd/yyyy') <= SYSDATE - (365 * 1)
                             AND t.semester NOT IN ('WIN')
                             AND t.group_code IN ('STD'))
  JOIN stvlevl
    ON stvlevl.stvlevl_code = CASE
       WHEN enrl.levl_code IN ('UG', 'IN') THEN
        'UG'
       WHEN enrl.levl_code IN ('GR', 'DR', 'JD', 'MD') THEN
        'GR'
       ELSE
        enrl.levl_code
       END
 WHERE enrl.coll_desc_1 NOT IN ('English Language Institute')
   AND enrl.levl_code NOT IN ('CT')
 GROUP BY enrl.coll_desc_1
UNION ALL
SELECT MIN(enrl.acad_year) AS min_aidy_code,MAX(enrl.acad_year) AS max_aidy_code,
       'College' AS dim_select,
       'Total' AS dim1,
       enrl.camp_code AS dim2
  FROM utl_d_aim.szrenrl enrl
  JOIN stvmajr
    ON stvmajr.stvmajr_code = enrl.majr_code_1
  JOIN zsaturn.szrlevl
    ON szrlevl_levl_code = enrl.levl_code
   AND szrlevl_is_univ = 'Y'
   AND szrlevl_has_awardable_cred = 'Y'
   AND enrl.yr_rank = 1 -- returns the last enrollment for the academic year
   AND enrl.term_hours > 0 -- must have hours
   AND enrl.acad_year IN (SELECT DISTINCT t.fa_proc_year AS aidy_code -- MUST BE A >= BC OF LAG FUNCTION
                            FROM zbtm.terms_by_group_v t
                           WHERE to_date('06/30/20' || substr(t.fa_proc_year, 3, 2), 'mm/dd/yyyy') > SYSDATE - (365 * 5) -- ALWAYS PULL 5 YEARS BACK
                             AND to_date('07/01/20' || substr(t.fa_proc_year, 1, 2), 'mm/dd/yyyy') <= SYSDATE - (365 * 1)
                             AND t.semester NOT IN ('WIN')
                             AND t.group_code IN ('STD'))
  JOIN stvlevl
    ON stvlevl.stvlevl_code = CASE
       WHEN enrl.levl_code IN ('UG', 'IN') THEN
        'UG'
       WHEN enrl.levl_code IN ('GR', 'DR', 'JD', 'MD') THEN
        'GR'
       ELSE
        enrl.levl_code
       END
 WHERE enrl.coll_desc_1 NOT IN ('English Language Institute')
   AND enrl.levl_code NOT IN ('CT')
 GROUP BY enrl.camp_code
UNION ALL
SELECT MIN(enrl.acad_year) AS min_aidy_code,MAX(enrl.acad_year) AS max_aidy_code,
       'College' AS dim_select,
       'Total' AS dim1,
       'ALL' AS dim2
  FROM utl_d_aim.szrenrl enrl
  JOIN stvmajr
    ON stvmajr.stvmajr_code = enrl.majr_code_1
  JOIN zsaturn.szrlevl
    ON szrlevl_levl_code = enrl.levl_code
   AND szrlevl_is_univ = 'Y'
   AND szrlevl_has_awardable_cred = 'Y'
   AND enrl.yr_rank = 1 -- returns the last enrollment for the academic year
   AND enrl.term_hours > 0 -- must have hours
   AND enrl.acad_year IN (SELECT DISTINCT t.fa_proc_year AS aidy_code -- MUST BE A >= BC OF LAG FUNCTION
                            FROM zbtm.terms_by_group_v t
                           WHERE to_date('06/30/20' || substr(t.fa_proc_year, 3, 2), 'mm/dd/yyyy') > SYSDATE - (365 * 5) -- ALWAYS PULL 5 YEARS BACK
                             AND to_date('07/01/20' || substr(t.fa_proc_year, 1, 2), 'mm/dd/yyyy') <= SYSDATE - (365 * 1)
                             AND t.semester NOT IN ('WIN')
                             AND t.group_code IN ('STD'))
  JOIN stvlevl
    ON stvlevl.stvlevl_code = CASE
       WHEN enrl.levl_code IN ('UG', 'IN') THEN
        'UG'
       WHEN enrl.levl_code IN ('GR', 'DR', 'JD', 'MD') THEN
        'GR'
       ELSE
        enrl.levl_code
       END
 WHERE enrl.coll_desc_1 NOT IN ('English Language Institute')
   AND enrl.levl_code NOT IN ('CT')
UNION ALL
SELECT MIN(enrl.acad_year) AS min_aidy_code,MAX(enrl.acad_year) AS max_aidy_code,
       'Level' AS dim_select,
       stvlevl_desc AS dim1,
       enrl.camp_code AS dim2
  FROM utl_d_aim.szrenrl enrl
  JOIN stvmajr
    ON stvmajr.stvmajr_code = enrl.majr_code_1
  JOIN zsaturn.szrlevl
    ON szrlevl_levl_code = enrl.levl_code
   AND szrlevl_is_univ = 'Y'
   AND szrlevl_has_awardable_cred = 'Y'
   AND enrl.yr_rank = 1 -- returns the last enrollment for the academic year
   AND enrl.term_hours > 0 -- must have hours
   AND enrl.acad_year IN (SELECT DISTINCT t.fa_proc_year AS aidy_code -- MUST BE A >= BC OF LAG FUNCTION
                            FROM zbtm.terms_by_group_v t
                           WHERE to_date('06/30/20' || substr(t.fa_proc_year, 3, 2), 'mm/dd/yyyy') > SYSDATE - (365 * 5) -- ALWAYS PULL 5 YEARS BACK
                             AND to_date('07/01/20' || substr(t.fa_proc_year, 1, 2), 'mm/dd/yyyy') <= SYSDATE - (365 * 1)
                             AND t.semester NOT IN ('WIN')
                             AND t.group_code IN ('STD'))
  JOIN stvlevl
    ON stvlevl.stvlevl_code = CASE
       WHEN enrl.levl_code IN ('UG', 'IN') THEN
        'UG'
       WHEN enrl.levl_code IN ('GR', 'DR', 'JD', 'MD') THEN
        'GR'
       ELSE
        enrl.levl_code
       END
 WHERE enrl.coll_desc_1 NOT IN ('English Language Institute')
   AND enrl.levl_code NOT IN ('CT')
 GROUP BY stvlevl_desc,
          enrl.camp_code
UNION ALL
SELECT MIN(enrl.acad_year) AS min_aidy_code,MAX(enrl.acad_year) AS max_aidy_code,
       'Level' AS dim_select,
       stvlevl_desc AS dim1,
       'ALL' AS dim2
  FROM utl_d_aim.szrenrl enrl
  JOIN stvmajr
    ON stvmajr.stvmajr_code = enrl.majr_code_1
  JOIN zsaturn.szrlevl
    ON szrlevl_levl_code = enrl.levl_code
   AND szrlevl_is_univ = 'Y'
   AND szrlevl_has_awardable_cred = 'Y'
   AND enrl.yr_rank = 1 -- returns the last enrollment for the academic year
   AND enrl.term_hours > 0 -- must have hours
   AND enrl.acad_year IN (SELECT DISTINCT t.fa_proc_year AS aidy_code -- MUST BE A >= BC OF LAG FUNCTION
                            FROM zbtm.terms_by_group_v t
                           WHERE to_date('06/30/20' || substr(t.fa_proc_year, 3, 2), 'mm/dd/yyyy') > SYSDATE - (365 * 5) -- ALWAYS PULL 5 YEARS BACK
                             AND to_date('07/01/20' || substr(t.fa_proc_year, 1, 2), 'mm/dd/yyyy') <= SYSDATE - (365 * 1)
                             AND t.semester NOT IN ('WIN')
                             AND t.group_code IN ('STD'))
  JOIN stvlevl
    ON stvlevl.stvlevl_code = CASE
       WHEN enrl.levl_code IN ('UG', 'IN') THEN
        'UG'
       WHEN enrl.levl_code IN ('GR', 'DR', 'JD', 'MD') THEN
        'GR'
       ELSE
        enrl.levl_code
       END
 WHERE enrl.coll_desc_1 NOT IN ('English Language Institute')
   AND enrl.levl_code NOT IN ('CT')
 GROUP BY stvlevl_desc
UNION ALL
SELECT MIN(enrl.acad_year) AS min_aidy_code,MAX(enrl.acad_year) AS max_aidy_code,
       'Level' AS dim_select,
       'Total' AS dim1,
       enrl.camp_code AS dim2
  FROM utl_d_aim.szrenrl enrl
  JOIN stvmajr
    ON stvmajr.stvmajr_code = enrl.majr_code_1
  JOIN zsaturn.szrlevl
    ON szrlevl_levl_code = enrl.levl_code
   AND szrlevl_is_univ = 'Y'
   AND szrlevl_has_awardable_cred = 'Y'
   AND enrl.yr_rank = 1 -- returns the last enrollment for the academic year
   AND enrl.term_hours > 0 -- must have hours
   AND enrl.acad_year IN (SELECT DISTINCT t.fa_proc_year AS aidy_code -- MUST BE A >= BC OF LAG FUNCTION
                            FROM zbtm.terms_by_group_v t
                           WHERE to_date('06/30/20' || substr(t.fa_proc_year, 3, 2), 'mm/dd/yyyy') > SYSDATE - (365 * 5) -- ALWAYS PULL 5 YEARS BACK
                             AND to_date('07/01/20' || substr(t.fa_proc_year, 1, 2), 'mm/dd/yyyy') <= SYSDATE - (365 * 1)
                             AND t.semester NOT IN ('WIN')
                             AND t.group_code IN ('STD'))
  JOIN stvlevl
    ON stvlevl.stvlevl_code = CASE
       WHEN enrl.levl_code IN ('UG', 'IN') THEN
        'UG'
       WHEN enrl.levl_code IN ('GR', 'DR', 'JD', 'MD') THEN
        'GR'
       ELSE
        enrl.levl_code
       END
 WHERE enrl.coll_desc_1 NOT IN ('English Language Institute')
   AND enrl.levl_code NOT IN ('CT')
 GROUP BY enrl.camp_code
UNION ALL
SELECT MIN(enrl.acad_year) AS min_aidy_code,MAX(enrl.acad_year) AS max_aidy_code,
       'Level' AS dim_select,
       'Total' AS dim1,
       'ALL' AS dim2
  FROM utl_d_aim.szrenrl enrl
  JOIN stvmajr
    ON stvmajr.stvmajr_code = enrl.majr_code_1
  JOIN zsaturn.szrlevl
    ON szrlevl_levl_code = enrl.levl_code
   AND szrlevl_is_univ = 'Y'
   AND szrlevl_has_awardable_cred = 'Y'
   AND enrl.yr_rank = 1 -- returns the last enrollment for the academic year
   AND enrl.term_hours > 0 -- must have hours
   AND enrl.acad_year IN (SELECT DISTINCT t.fa_proc_year AS aidy_code -- MUST BE A >= BC OF LAG FUNCTION
                            FROM zbtm.terms_by_group_v t
                           WHERE to_date('06/30/20' || substr(t.fa_proc_year, 3, 2), 'mm/dd/yyyy') > SYSDATE - (365 * 5) -- ALWAYS PULL 5 YEARS BACK
                             AND to_date('07/01/20' || substr(t.fa_proc_year, 1, 2), 'mm/dd/yyyy') <= SYSDATE - (365 * 1)
                             AND t.semester NOT IN ('WIN')
                             AND t.group_code IN ('STD'))
  JOIN stvlevl
    ON stvlevl.stvlevl_code = CASE
       WHEN enrl.levl_code IN ('UG', 'IN') THEN
        'UG'
       WHEN enrl.levl_code IN ('GR', 'DR', 'JD', 'MD') THEN
        'GR'
       ELSE
        enrl.levl_code
       END
 WHERE enrl.coll_desc_1 NOT IN ('English Language Institute')
   AND enrl.levl_code NOT IN ('CT')
UNION ALL
SELECT MIN(enrl.acad_year) AS min_aidy_code,MAX(enrl.acad_year) AS max_aidy_code,
       'Program' AS dim_select,
       stvmajr_desc AS dim1,
       enrl.camp_code AS dim2
  FROM utl_d_aim.szrenrl enrl
  JOIN stvmajr
    ON stvmajr.stvmajr_code = enrl.majr_code_1
  JOIN zsaturn.szrlevl
    ON szrlevl_levl_code = enrl.levl_code
   AND szrlevl_is_univ = 'Y'
   AND szrlevl_has_awardable_cred = 'Y'
   AND enrl.yr_rank = 1 -- returns the last enrollment for the academic year
   AND enrl.term_hours > 0 -- must have hours
   AND enrl.acad_year IN (SELECT DISTINCT t.fa_proc_year AS aidy_code -- MUST BE A >= BC OF LAG FUNCTION
                            FROM zbtm.terms_by_group_v t
                           WHERE to_date('06/30/20' || substr(t.fa_proc_year, 3, 2), 'mm/dd/yyyy') > SYSDATE - (365 * 5) -- ALWAYS PULL 5 YEARS BACK
                             AND to_date('07/01/20' || substr(t.fa_proc_year, 1, 2), 'mm/dd/yyyy') <= SYSDATE - (365 * 1)
                             AND t.semester NOT IN ('WIN')
                             AND t.group_code IN ('STD'))
  JOIN stvlevl
    ON stvlevl.stvlevl_code = CASE
       WHEN enrl.levl_code IN ('UG', 'IN') THEN
        'UG'
       WHEN enrl.levl_code IN ('GR', 'DR', 'JD', 'MD') THEN
        'GR'
       ELSE
        enrl.levl_code
       END
 WHERE enrl.coll_desc_1 NOT IN ('English Language Institute')
   AND enrl.levl_code NOT IN ('CT')
 GROUP BY stvmajr_desc,
          enrl.camp_code
UNION ALL
SELECT MIN(enrl.acad_year) AS min_aidy_code,MAX(enrl.acad_year) AS max_aidy_code,
       'Program' AS dim_select,
       stvmajr_desc AS dim1,
       'ALL' AS dim2
  FROM utl_d_aim.szrenrl enrl
  JOIN stvmajr
    ON stvmajr.stvmajr_code = enrl.majr_code_1
  JOIN zsaturn.szrlevl
    ON szrlevl_levl_code = enrl.levl_code
   AND szrlevl_is_univ = 'Y'
   AND szrlevl_has_awardable_cred = 'Y'
   AND enrl.yr_rank = 1 -- returns the last enrollment for the academic year
   AND enrl.term_hours > 0 -- must have hours
   AND enrl.acad_year IN (SELECT DISTINCT t.fa_proc_year AS aidy_code -- MUST BE A >= BC OF LAG FUNCTION
                            FROM zbtm.terms_by_group_v t
                           WHERE to_date('06/30/20' || substr(t.fa_proc_year, 3, 2), 'mm/dd/yyyy') > SYSDATE - (365 * 5) -- ALWAYS PULL 5 YEARS BACK
                             AND to_date('07/01/20' || substr(t.fa_proc_year, 1, 2), 'mm/dd/yyyy') <= SYSDATE - (365 * 1)
                             AND t.semester NOT IN ('WIN')
                             AND t.group_code IN ('STD'))
  JOIN stvlevl
    ON stvlevl.stvlevl_code = CASE
       WHEN enrl.levl_code IN ('UG', 'IN') THEN
        'UG'
       WHEN enrl.levl_code IN ('GR', 'DR', 'JD', 'MD') THEN
        'GR'
       ELSE
        enrl.levl_code
       END
 WHERE enrl.coll_desc_1 NOT IN ('English Language Institute')
   AND enrl.levl_code NOT IN ('CT')
 GROUP BY stvmajr_desc
UNION ALL
SELECT MIN(enrl.acad_year) AS min_aidy_code,MAX(enrl.acad_year) AS max_aidy_code,
       'Program' AS dim_select,
       'Total' AS dim1,
       enrl.camp_code AS dim2
  FROM utl_d_aim.szrenrl enrl
  JOIN stvmajr
    ON stvmajr.stvmajr_code = enrl.majr_code_1
  JOIN zsaturn.szrlevl
    ON szrlevl_levl_code = enrl.levl_code
   AND szrlevl_is_univ = 'Y'
   AND szrlevl_has_awardable_cred = 'Y'
   AND enrl.yr_rank = 1 -- returns the last enrollment for the academic year
   AND enrl.term_hours > 0 -- must have hours
   AND enrl.acad_year IN (SELECT DISTINCT t.fa_proc_year AS aidy_code -- MUST BE A >= BC OF LAG FUNCTION
                            FROM zbtm.terms_by_group_v t
                           WHERE to_date('06/30/20' || substr(t.fa_proc_year, 3, 2), 'mm/dd/yyyy') > SYSDATE - (365 * 5) -- ALWAYS PULL 5 YEARS BACK
                             AND to_date('07/01/20' || substr(t.fa_proc_year, 1, 2), 'mm/dd/yyyy') <= SYSDATE - (365 * 1)
                             AND t.semester NOT IN ('WIN')
                             AND t.group_code IN ('STD'))
  JOIN stvlevl
    ON stvlevl.stvlevl_code = CASE
       WHEN enrl.levl_code IN ('UG', 'IN') THEN
        'UG'
       WHEN enrl.levl_code IN ('GR', 'DR', 'JD', 'MD') THEN
        'GR'
       ELSE
        enrl.levl_code
       END
 WHERE enrl.coll_desc_1 NOT IN ('English Language Institute')
   AND enrl.levl_code NOT IN ('CT')
 GROUP BY enrl.camp_code
UNION ALL
SELECT MIN(enrl.acad_year) AS min_aidy_code,MAX(enrl.acad_year) AS max_aidy_code,
       'Program' AS dim_select,
       'Total' AS dim1,
       'ALL' AS dim2
  FROM utl_d_aim.szrenrl enrl
  JOIN stvmajr
    ON stvmajr.stvmajr_code = enrl.majr_code_1
  JOIN zsaturn.szrlevl
    ON szrlevl_levl_code = enrl.levl_code
   AND szrlevl_is_univ = 'Y'
   AND szrlevl_has_awardable_cred = 'Y'
   AND enrl.yr_rank = 1 -- returns the last enrollment for the academic year
   AND enrl.term_hours > 0 -- must have hours
   AND enrl.acad_year IN (SELECT DISTINCT t.fa_proc_year AS aidy_code -- MUST BE A >= BC OF LAG FUNCTION
                            FROM zbtm.terms_by_group_v t
                           WHERE to_date('06/30/20' || substr(t.fa_proc_year, 3, 2), 'mm/dd/yyyy') > SYSDATE - (365 * 5) -- ALWAYS PULL 5 YEARS BACK
                             AND to_date('07/01/20' || substr(t.fa_proc_year, 1, 2), 'mm/dd/yyyy') <= SYSDATE - (365 * 1)
                             AND t.semester NOT IN ('WIN')
                             AND t.group_code IN ('STD'))
  JOIN stvlevl
    ON stvlevl.stvlevl_code = CASE
       WHEN enrl.levl_code IN ('UG', 'IN') THEN
        'UG'
       WHEN enrl.levl_code IN ('GR', 'DR', 'JD', 'MD') THEN
        'GR'
       ELSE
        enrl.levl_code
       END
 WHERE enrl.coll_desc_1 NOT IN ('English Language Institute')
   AND enrl.levl_code NOT IN ('CT')
 ORDER BY dim_select,
          dim1,
          dim2;
BEGIN
-- dbms_output.enable(buffer_size => NULL);
--
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
utl_d_aa.truncate_table(v_table_name => 'pdb_gpa_tableau');
FOR rec IN c_terms
LOOP
v_count   := 0; -- reset count
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || rec.dim_select || ' - ' || rec.dim1 || ' - ' || rec.dim2 || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- all combinations
IF rec.dim1 <> 'Total'
   AND rec.dim2 <> 'ALL' THEN
INSERT INTO utl_d_aa.pdb_gpa_tableau
(aidy_code,
 dim_select,
 dim1,
 dim2,
 timeframe,
 avg_gpa,
 avg_gpa_previous,
 avg_gpa_difference,
 activity_date)
SELECT aidy_code,
       rec.dim_select,
       src.dim1,
       src.dim2,
       timeframe,
       AVG(src.gpa) AS avg_gpa,
       lag(AVG(src.gpa)) over(PARTITION BY src.dim1, src.dim2 ORDER BY aidy_code) AS avg_gpa_previous,
       AVG(src.gpa) - lag(AVG(src.gpa)) over(PARTITION BY src.dim1, src.dim2 ORDER BY aidy_code) AS avg_gpa_difference,
       v_etl_date AS activity_date
  FROM (SELECT enrl.pidm AS pidm,
               enrl.acad_year - 101 || ' vs. ' || enrl.acad_year AS timeframe,
               enrl.acad_year AS aidy_code,
               CASE
               WHEN rec.dim_select = 'College' THEN
                stvcoll.stvcoll_desc
               WHEN rec.dim_select = 'Level' THEN
                stvlevl.stvlevl_desc
               WHEN rec.dim_select = 'Program' THEN
                stvmajr.stvmajr_desc
               END AS dim1,
               CASE
               WHEN rec.dim2 = 'R' THEN
                'Resident'
               WHEN rec.dim2 = 'D' THEN
                'Online'
               ELSE
                'ALL'
               END dim2,
               enrl.cum_gpa AS gpa
          FROM utl_d_aim.szrenrl enrl
          JOIN zsaturn.szrlevl l
            ON l.szrlevl_levl_code = enrl.levl_code
           AND l.szrlevl_is_univ = 'Y'
           AND l.szrlevl_has_awardable_cred = 'Y'
           AND enrl.yr_rank = 1 -- returns the last enrollment for the academic year
           AND enrl.term_hours > 0 -- must have hours -- differences between enrollment and retention procs
           AND enrl.acad_year BETWEEN rec.min_aidy_code AND rec.max_aidy_code -- must remain between for the lag function to work
           AND enrl.camp_code = rec.dim2
          JOIN smrprle
            ON smrprle.smrprle_program = enrl.prog_code_1
          LEFT JOIN stvcoll -- must remain a left join for dim1 to work properly
            ON stvcoll.stvcoll_code = smrprle.smrprle_coll_code
           AND stvcoll.stvcoll_desc = rec.dim1
          LEFT JOIN stvlevl -- must remain a left join for dim1 to work properly
            ON stvlevl.stvlevl_code = enrl.levl_code
           AND stvlevl.stvlevl_desc = rec.dim1
          LEFT JOIN stvmajr -- must remain a left join for dim1 to work properly
            ON stvmajr.stvmajr_code = enrl.majr_code_1
           AND stvmajr.stvmajr_desc = rec.dim1
         WHERE 1 = 1
           AND CASE
               WHEN rec.dim_select = 'College' THEN
                stvcoll.stvcoll_desc
               WHEN rec.dim_select = 'Level' THEN
                stvlevl.stvlevl_desc
               WHEN rec.dim_select = 'Program' THEN
                stvmajr.stvmajr_desc
               END IS NOT NULL) src
 GROUP BY aidy_code,
          rec.dim_select,
          src.dim1,
          src.dim2,
          timeframe;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
ELSIF rec.dim1 = 'Total'
      AND rec.dim2 <> 'ALL' THEN
-- totals showing campus breakdowns
INSERT INTO utl_d_aa.pdb_gpa_tableau
(aidy_code,
 dim_select,
 dim1,
 dim2,
 timeframe,
 avg_gpa,
 avg_gpa_previous,
 avg_gpa_difference,
 activity_date)
SELECT aidy_code,
       rec.dim_select,
       src.dim1,
       src.dim2,
       timeframe,
       AVG(src.gpa) AS avg_gpa,
       lag(AVG(src.gpa)) over(PARTITION BY src.dim1, src.dim2 ORDER BY aidy_code) AS avg_gpa_previous,
       AVG(src.gpa) - lag(AVG(src.gpa)) over(PARTITION BY src.dim1, src.dim2 ORDER BY aidy_code) AS avg_gpa_difference,
       v_etl_date AS activity_date
  FROM (SELECT enrl.pidm AS pidm,
               enrl.acad_year - 101 || ' vs. ' || enrl.acad_year AS timeframe,
               enrl.acad_year AS aidy_code,
               rec.dim1 AS dim1,
               CASE
               WHEN rec.dim2 = 'R' THEN
                'Resident'
               WHEN rec.dim2 = 'D' THEN
                'Online'
               ELSE
                'ALL'
               END dim2,
               enrl.cum_gpa AS gpa
          FROM utl_d_aim.szrenrl enrl
          JOIN zsaturn.szrlevl l
            ON l.szrlevl_levl_code = enrl.levl_code
           AND l.szrlevl_is_univ = 'Y'
           AND l.szrlevl_has_awardable_cred = 'Y'
           AND enrl.yr_rank = 1 -- returns the last enrollment for the academic year
           AND enrl.term_hours > 0 -- must have hours
           AND enrl.acad_year BETWEEN rec.min_aidy_code AND rec.max_aidy_code -- must remain between for the lag function to work
           AND enrl.camp_code = rec.dim2
         WHERE 1 = 1) src
 GROUP BY aidy_code,
          rec.dim_select,
          src.dim1,
          src.dim2,
          timeframe;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
ELSIF rec.dim1 <> 'Total'
      AND rec.dim2 = 'ALL' THEN
-- all combinations for both campuses
INSERT INTO utl_d_aa.pdb_gpa_tableau
(aidy_code,
 dim_select,
 dim1,
 dim2,
 timeframe,
 avg_gpa,
 avg_gpa_previous,
 avg_gpa_difference,
 activity_date)
SELECT aidy_code,
       rec.dim_select,
       src.dim1,
       src.dim2,
       timeframe,
       AVG(src.gpa) AS avg_gpa,
       lag(AVG(src.gpa)) over(PARTITION BY src.dim1, src.dim2 ORDER BY aidy_code) AS avg_gpa_previous,
       AVG(src.gpa) - lag(AVG(src.gpa)) over(PARTITION BY src.dim1, src.dim2 ORDER BY aidy_code) AS avg_gpa_difference,
       v_etl_date AS activity_date
  FROM (SELECT enrl.pidm AS pidm,
               enrl.acad_year - 101 || ' vs. ' || enrl.acad_year AS timeframe,
               enrl.acad_year AS aidy_code,
               CASE
               WHEN rec.dim_select = 'College' THEN
                stvcoll.stvcoll_desc
               WHEN rec.dim_select = 'Level' THEN
                stvlevl.stvlevl_desc
               WHEN rec.dim_select = 'Program' THEN
                stvmajr.stvmajr_desc
               END AS dim1,
               rec.dim2,
               enrl.cum_gpa AS gpa
          FROM utl_d_aim.szrenrl enrl
          JOIN zsaturn.szrlevl l
            ON l.szrlevl_levl_code = enrl.levl_code
           AND l.szrlevl_is_univ = 'Y'
           AND l.szrlevl_has_awardable_cred = 'Y'
           AND enrl.yr_rank = 1 -- returns the last enrollment for the academic year
           AND enrl.term_hours > 0 -- must have hours
           AND enrl.acad_year BETWEEN rec.min_aidy_code AND rec.max_aidy_code -- must remain between for the lag function to work
          JOIN smrprle
            ON smrprle.smrprle_program = enrl.prog_code_1
          LEFT JOIN stvcoll -- must remain a left join for dim1 to work properly
            ON stvcoll.stvcoll_code = smrprle.smrprle_coll_code
           AND stvcoll.stvcoll_desc = rec.dim1
          LEFT JOIN stvlevl -- must remain a left join for dim1 to work properly
            ON stvlevl.stvlevl_code = enrl.levl_code
           AND stvlevl.stvlevl_desc = rec.dim1
          LEFT JOIN stvmajr -- must remain a left join for dim1 to work properly
            ON stvmajr.stvmajr_code = enrl.majr_code_1
           AND stvmajr.stvmajr_desc = rec.dim1
         WHERE 1 = 1
           AND CASE
               WHEN rec.dim_select = 'College' THEN
                stvcoll.stvcoll_desc
               WHEN rec.dim_select = 'Level' THEN
                stvlevl.stvlevl_desc
               WHEN rec.dim_select = 'Program' THEN
                stvmajr.stvmajr_desc
               END IS NOT NULL) src
 GROUP BY aidy_code,
          rec.dim_select,
          src.dim1,
          src.dim2,
          timeframe;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
ELSIF rec.dim1 = 'Total'
      AND rec.dim2 = 'ALL' THEN
-- only total for both campuses
INSERT INTO utl_d_aa.pdb_gpa_tableau
(aidy_code,
 dim_select,
 dim1,
 dim2,
 timeframe,
 avg_gpa,
 avg_gpa_previous,
 avg_gpa_difference,
 activity_date)
SELECT aidy_code,
       rec.dim_select,
       src.dim1,
       src.dim2,
       timeframe,
       AVG(src.gpa) AS avg_gpa,
       lag(AVG(src.gpa)) over(PARTITION BY src.dim1, src.dim2 ORDER BY aidy_code) AS avg_gpa_previous,
       AVG(src.gpa) - lag(AVG(src.gpa)) over(PARTITION BY src.dim1, src.dim2 ORDER BY aidy_code) AS avg_gpa_difference,
       v_etl_date AS activity_date
  FROM (SELECT enrl.pidm AS pidm,
               enrl.acad_year - 101 || ' vs. ' || enrl.acad_year AS timeframe,
               enrl.acad_year AS aidy_code,
               rec.dim1 AS dim1,
               rec.dim2 AS dim2,
               enrl.cum_gpa AS gpa
          FROM utl_d_aim.szrenrl enrl
          JOIN zsaturn.szrlevl l
            ON l.szrlevl_levl_code = enrl.levl_code
           AND l.szrlevl_is_univ = 'Y'
           AND l.szrlevl_has_awardable_cred = 'Y'
           AND enrl.yr_rank = 1 -- returns the last enrollment for the academic year
           AND enrl.term_hours > 0 -- must have hours
           AND enrl.acad_year BETWEEN rec.min_aidy_code AND rec.max_aidy_code -- must remain between for the lag function to work
         WHERE 1 = 1) src
 GROUP BY aidy_code,
          rec.dim_select,
          src.dim1,
          src.dim2,
          timeframe;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
END IF;
dbms_output.put_line(' --------- ');
END LOOP;
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
---     07-02-2025  MAPEELE     --Initial release
---     10-02-2025  WGRIFFITH2     --no longer shows current aidy, because the numbers are not completed yet
------------------------------------------------------------------------------------------------*/
END etl_aa_pdb_gpa_tableau;

procedure etl_aa_pdb_student_fte_tableau(jobnumber number, processid varchar2, processname varchar2) is
/*
Table: pdb_student_fte_tableau

Primary Keys: NONE

Unique index: NONE

Purpose:
- Populate Presidents Dashboard with Total Student Full-Time Equivalent (FTE) by campus
- Derived from IPEDS (Integrated Postsecondary Education Data System) data
- Includes Residential and LUO (Location Unknown Online) students during academic year

Conditions:
-- Data sourced from IPEDS Institution Profile (https://nces.ed.gov/ipeds/institution-profile/232557)
-- Joins based on fiscal/academic year processing date (fa_proc_year)
-- Supports ADS Academics reporting requirements
-- Managed by Matt Peele

Dashboard: Presidents Dashboard
Section: A
KPIs: Total FTE by campus
*/
--DECLARE
--- PARAMS
v_etl_date DATE := SYSDATE;
v_msg      VARCHAR2(2000);
v_instance VARCHAR2(50) := upper('ALL'); -- inst from the jams job; used for determining instance
v_partition NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
-- v_mod         NUMBER := 5; -- number of partitions to be created
-- v_cpu          NUMBER := 4; -- number of CPUs used for parallelization - do not exceed 20 CPUs [v_mod x --v_cpu] if running simultaneously
v_count        NUMBER := 0;
v_delete_count NUMBER := 0;
v_insert_count NUMBER := 0;
v_elapsed      NUMBER := 0;
v_total_count  NUMBER := 0;
v_job_id       VARCHAR2(32);
v_proc         VARCHAR2(100) := 'etl_aa_pdb_student_fte_tableau';
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
-- create  table utl_d_aa.pdb_student_fte_tableau as
MERGE INTO utl_d_aa.pdb_student_fte_tableau target
USING (
WITH fte AS
 (SELECT rsbbregfci.rsbbregfci_acyr_code fa_proc_year,
         'AY' || substr(rsbbregfci.rsbbregfci_acyr_code, 1, 2) || '-' || substr(rsbbregfci.rsbbregfci_acyr_code, 3, 2) yr_label,
         decode(rsbbregfci.rsbbregfci_camp_code, 'D', 'Online', 'Residential') campus,
         round(SUM(CASE
                   WHEN rsbbregfci.rsbbregfci_levl_code IN ('UG', 'IN') THEN
                    rsbbregfci.rsbbregfci_hours / 30
                   WHEN rsbbregfci.rsbbregfci_levl_code IN ('GR', 'DR') THEN
                    rsbbregfci.rsbbregfci_hours / 24
                   WHEN rsbbregfci.rsbbregfci_levl_code IN ('JD', 'MD') THEN
                    rsbbregfci.rsbbregfci_hours / 24
                   END)) student_fte
    FROM utl_d_aim.rsbbregfci
   WHERE rsbbregfci_report = 'ytd_reg'
     AND rsbbregfci.rsbbregfci_acyr_code = (SELECT tbg.fa_proc_year
                                              FROM zbtm.terms_by_group_v tbg
                                             WHERE tbg.group_code = 'STD'
                                               AND trunc(SYSDATE - 365.25 * 5) BETWEEN tbg.start_date AND tbg.end_date)
     AND rsbbregfci_report_date = (SELECT MAX(r.rsbbregfci_report_date)
                                     FROM utl_d_aim.rsbbregfci r
                                    WHERE r.rsbbregfci_report = rsbbregfci.rsbbregfci_report
                                      AND r.rsbbregfci_acyr_code = rsbbregfci.rsbbregfci_acyr_code
                                      AND r.rsbbregfci_report_date <= trunc(SYSDATE - 365.25 * 5))
   GROUP BY rsbbregfci.rsbbregfci_acyr_code,
            'AY' || substr(rsbbregfci.rsbbregfci_acyr_code, 1, 2) || '-' || substr(rsbbregfci.rsbbregfci_acyr_code, 3, 2),
            decode(rsbbregfci.rsbbregfci_camp_code, 'D', 'Online', 'Residential')
  UNION ALL
  SELECT rsbbregfci.rsbbregfci_acyr_code fa_proc_year,
         'AY' || substr(rsbbregfci.rsbbregfci_acyr_code, 1, 2) || '-' || substr(rsbbregfci.rsbbregfci_acyr_code, 3, 2) yr_label,
         decode(rsbbregfci.rsbbregfci_camp_code, 'D', 'Online', 'Residential') campus,
         round(SUM(CASE
                   WHEN rsbbregfci.rsbbregfci_levl_code IN ('UG', 'IN') THEN
                    rsbbregfci.rsbbregfci_hours / 30
                   WHEN rsbbregfci.rsbbregfci_levl_code IN ('GR', 'DR') THEN
                    rsbbregfci.rsbbregfci_hours / 24
                   WHEN rsbbregfci.rsbbregfci_levl_code IN ('JD', 'MD') THEN
                    rsbbregfci.rsbbregfci_hours / 24
                   END)) student_fte
    FROM utl_d_aim.rsbbregfci
   WHERE rsbbregfci_report = 'ytd_reg'
     AND rsbbregfci.rsbbregfci_acyr_code = (SELECT tbg.fa_proc_year
                                              FROM zbtm.terms_by_group_v tbg
                                             WHERE tbg.group_code = 'STD'
                                               AND trunc(SYSDATE - 365.25 * 4) BETWEEN tbg.start_date AND tbg.end_date)
     AND rsbbregfci_report_date = (SELECT MAX(r.rsbbregfci_report_date)
                                     FROM utl_d_aim.rsbbregfci r
                                    WHERE r.rsbbregfci_report = rsbbregfci.rsbbregfci_report
                                      AND r.rsbbregfci_acyr_code = rsbbregfci.rsbbregfci_acyr_code
                                      AND r.rsbbregfci_report_date <= trunc(SYSDATE - 365.25 * 4))
   GROUP BY rsbbregfci.rsbbregfci_acyr_code,
            'AY' || substr(rsbbregfci.rsbbregfci_acyr_code, 1, 2) || '-' || substr(rsbbregfci.rsbbregfci_acyr_code, 3, 2),
            decode(rsbbregfci.rsbbregfci_camp_code, 'D', 'Online', 'Residential')
  UNION ALL
  SELECT rsbbregfci.rsbbregfci_acyr_code fa_proc_year,
         'AY' || substr(rsbbregfci.rsbbregfci_acyr_code, 1, 2) || '-' || substr(rsbbregfci.rsbbregfci_acyr_code, 3, 2) yr_label,
         decode(rsbbregfci.rsbbregfci_camp_code, 'D', 'Online', 'Residential') campus,
         round(SUM(CASE
                   WHEN rsbbregfci.rsbbregfci_levl_code IN ('UG', 'IN') THEN
                    rsbbregfci.rsbbregfci_hours / 30
                   WHEN rsbbregfci.rsbbregfci_levl_code IN ('GR', 'DR') THEN
                    rsbbregfci.rsbbregfci_hours / 24
                   WHEN rsbbregfci.rsbbregfci_levl_code IN ('JD', 'MD') THEN
                    rsbbregfci.rsbbregfci_hours / 24
                   END)) student_fte
    FROM utl_d_aim.rsbbregfci
   WHERE rsbbregfci_report = 'ytd_reg'
     AND rsbbregfci.rsbbregfci_acyr_code = (SELECT tbg.fa_proc_year
                                              FROM zbtm.terms_by_group_v tbg
                                             WHERE tbg.group_code = 'STD'
                                               AND trunc(SYSDATE - 365.25 * 3) BETWEEN tbg.start_date AND tbg.end_date)
     AND rsbbregfci_report_date = (SELECT MAX(r.rsbbregfci_report_date)
                                     FROM utl_d_aim.rsbbregfci r
                                    WHERE r.rsbbregfci_report = rsbbregfci.rsbbregfci_report
                                      AND r.rsbbregfci_acyr_code = rsbbregfci.rsbbregfci_acyr_code
                                      AND r.rsbbregfci_report_date <= trunc(SYSDATE - 365.25 * 3))
   GROUP BY rsbbregfci.rsbbregfci_acyr_code,
            'AY' || substr(rsbbregfci.rsbbregfci_acyr_code, 1, 2) || '-' || substr(rsbbregfci.rsbbregfci_acyr_code, 3, 2),
            decode(rsbbregfci.rsbbregfci_camp_code, 'D', 'Online', 'Residential')
  UNION ALL
  SELECT rsbbregfci.rsbbregfci_acyr_code fa_proc_year,
         'AY' || substr(rsbbregfci.rsbbregfci_acyr_code, 1, 2) || '-' || substr(rsbbregfci.rsbbregfci_acyr_code, 3, 2) yr_label,
         decode(rsbbregfci.rsbbregfci_camp_code, 'D', 'Online', 'Residential') campus,
         round(SUM(CASE
                   WHEN rsbbregfci.rsbbregfci_levl_code IN ('UG', 'IN') THEN
                    rsbbregfci.rsbbregfci_hours / 30
                   WHEN rsbbregfci.rsbbregfci_levl_code IN ('GR', 'DR') THEN
                    rsbbregfci.rsbbregfci_hours / 24
                   WHEN rsbbregfci.rsbbregfci_levl_code IN ('JD', 'MD') THEN
                    rsbbregfci.rsbbregfci_hours / 24
                   END)) student_fte
    FROM utl_d_aim.rsbbregfci
   WHERE rsbbregfci_report = 'ytd_reg'
     AND rsbbregfci.rsbbregfci_acyr_code = (SELECT tbg.fa_proc_year
                                              FROM zbtm.terms_by_group_v tbg
                                             WHERE tbg.group_code = 'STD'
                                               AND trunc(SYSDATE - 365.25 * 2) BETWEEN tbg.start_date AND tbg.end_date)
     AND rsbbregfci_report_date = (SELECT MAX(r.rsbbregfci_report_date)
                                     FROM utl_d_aim.rsbbregfci r
                                    WHERE r.rsbbregfci_report = rsbbregfci.rsbbregfci_report
                                      AND r.rsbbregfci_acyr_code = rsbbregfci.rsbbregfci_acyr_code
                                      AND r.rsbbregfci_report_date <= trunc(SYSDATE - 365.25 * 2))
   GROUP BY rsbbregfci.rsbbregfci_acyr_code,
            'AY' || substr(rsbbregfci.rsbbregfci_acyr_code, 1, 2) || '-' || substr(rsbbregfci.rsbbregfci_acyr_code, 3, 2),
            decode(rsbbregfci.rsbbregfci_camp_code, 'D', 'Online', 'Residential')
  UNION ALL
  SELECT rsbbregfci.rsbbregfci_acyr_code fa_proc_year,
         'AY' || substr(rsbbregfci.rsbbregfci_acyr_code, 1, 2) || '-' || substr(rsbbregfci.rsbbregfci_acyr_code, 3, 2) yr_label,
         decode(rsbbregfci.rsbbregfci_camp_code, 'D', 'Online', 'Residential') campus,
         round(SUM(CASE
                   WHEN rsbbregfci.rsbbregfci_levl_code IN ('UG', 'IN') THEN
                    rsbbregfci.rsbbregfci_hours / 30
                   WHEN rsbbregfci.rsbbregfci_levl_code IN ('GR', 'DR') THEN
                    rsbbregfci.rsbbregfci_hours / 24
                   WHEN rsbbregfci.rsbbregfci_levl_code IN ('JD', 'MD') THEN
                    rsbbregfci.rsbbregfci_hours / 24
                   END)) student_fte
    FROM utl_d_aim.rsbbregfci
   WHERE rsbbregfci_report = 'ytd_reg'
     AND rsbbregfci.rsbbregfci_acyr_code = (SELECT tbg.fa_proc_year
                                              FROM zbtm.terms_by_group_v tbg
                                             WHERE tbg.group_code = 'STD'
                                               AND trunc(SYSDATE - 365.25 * 1) BETWEEN tbg.start_date AND tbg.end_date)
     AND rsbbregfci_report_date = (SELECT MAX(r.rsbbregfci_report_date)
                                     FROM utl_d_aim.rsbbregfci r
                                    WHERE r.rsbbregfci_report = rsbbregfci.rsbbregfci_report
                                      AND r.rsbbregfci_acyr_code = rsbbregfci.rsbbregfci_acyr_code
                                      AND r.rsbbregfci_report_date <= trunc(SYSDATE - 365.25 * 1))
   GROUP BY rsbbregfci.rsbbregfci_acyr_code,
            'AY' || substr(rsbbregfci.rsbbregfci_acyr_code, 1, 2) || '-' || substr(rsbbregfci.rsbbregfci_acyr_code, 3, 2),
            decode(rsbbregfci.rsbbregfci_camp_code, 'D', 'Online', 'Residential')
  UNION ALL
  SELECT rsbbregfci.rsbbregfci_acyr_code fa_proc_year,
         'AY' || substr(rsbbregfci.rsbbregfci_acyr_code, 1, 2) || '-' || substr(rsbbregfci.rsbbregfci_acyr_code, 3, 2) yr_label,
         decode(rsbbregfci.rsbbregfci_camp_code, 'D', 'Online', 'Residential') campus,
         round(SUM(CASE
                   WHEN rsbbregfci.rsbbregfci_levl_code IN ('UG', 'IN') THEN
                    rsbbregfci.rsbbregfci_hours / 30
                   WHEN rsbbregfci.rsbbregfci_levl_code IN ('GR', 'DR') THEN
                    rsbbregfci.rsbbregfci_hours / 24
                   WHEN rsbbregfci.rsbbregfci_levl_code IN ('JD', 'MD') THEN
                    rsbbregfci.rsbbregfci_hours / 24
                   END)) student_fte
    FROM utl_d_aim.rsbbregfci
   WHERE rsbbregfci_report = 'ytd_reg'
     AND rsbbregfci.rsbbregfci_acyr_code = (SELECT tbg.fa_proc_year
                                              FROM zbtm.terms_by_group_v tbg
                                             WHERE tbg.group_code = 'STD'
                                               AND trunc(SYSDATE) BETWEEN tbg.start_date AND tbg.end_date)
     AND rsbbregfci_report_date = (SELECT MAX(r.rsbbregfci_report_date)
                                     FROM utl_d_aim.rsbbregfci r
                                    WHERE r.rsbbregfci_report = rsbbregfci.rsbbregfci_report
                                      AND r.rsbbregfci_acyr_code = rsbbregfci.rsbbregfci_acyr_code
                                      AND r.rsbbregfci_report_date <= trunc(SYSDATE))
   GROUP BY rsbbregfci.rsbbregfci_acyr_code,
            'AY' || substr(rsbbregfci.rsbbregfci_acyr_code, 1, 2) || '-' || substr(rsbbregfci.rsbbregfci_acyr_code, 3, 2),
            decode(rsbbregfci.rsbbregfci_camp_code, 'D', 'Online', 'Residential'))
SELECT fte.fa_proc_year,
       fte.yr_label,
       fte.campus,
       fte.student_fte student_fte_ytd,
       lag(yr_label) over(PARTITION BY campus ORDER BY fa_proc_year) previous_academic_year,
       lag(student_fte) over(PARTITION BY campus ORDER BY fa_proc_year) previous_academic_ytd_student_fte,
       SYSDATE activity_date
  FROM fte) SOURCE
    ON (target.fa_proc_year = source.fa_proc_year AND target.yr_label = source.yr_label AND target.campus = source.campus) WHEN MATCHED THEN
UPDATE
   SET target.student_fte_ytd                   = source.student_fte_ytd,
       target.previous_academic_year            = source.previous_academic_year,
       target.previous_academic_ytd_student_fte = source.previous_academic_ytd_student_fte,
       target.activity_date                     = source.activity_date
WHEN NOT MATCHED THEN
INSERT
(fa_proc_year,
 yr_label,
 campus,
 student_fte_ytd,
 previous_academic_year,
 previous_academic_ytd_student_fte,
 activity_date)
VALUES
(source.fa_proc_year,
 source.yr_label,
 source.campus,
 source.student_fte_ytd,
 source.previous_academic_year,
 source.previous_academic_ytd_student_fte,
 source.activity_date);
v_insert_count := SQL%ROWCOUNT;
v_total_count  := v_total_count + v_insert_count; -- keep running total of rows processed
v_elapsed      := round((SYSDATE - v_etl_date) * 86400);
v_msg          := 'MERGE - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_insert_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_insert_count);
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
VERSION DATE        USERNAME    UPDATES
---     05-08-2025    WGRIFFITH2  --Initial release
------------------------------------------------------------------------------------------------*/
END etl_aa_pdb_student_fte_tableau; --

procedure etl_aa_pdb_graduate_degrees_tableau(jobnumber number, processid varchar2, processname varchar2) is
/*
Table: pdb_graduate_degrees_tableau

Primary Keys: NONE

Unique index: NONE

Purpose:
- Capture total graduates and degrees conferred by campus year over year
- Track distinct headcount of graduates
- Count total degrees conferred across campuses

Conditions:
-- Graduates are distinct headcount of those who have conferred a degree
-- Total count may not equal RES + LUO numbers due to potential multi-campus degree conferral
-- Uses fiscal/academic year dates (stvterm_fa_proc_yr = fa_proc_yr)

Dashboard: Presidents Dashboard
Section: G
KPIs: Total Graduates, Degrees Conferred
Support Group: ADS Academics
Support Individual: Matt Peele
*/
--DECLARE
--- PARAMS
v_etl_date DATE := SYSDATE;
v_msg      VARCHAR2(2000);
v_instance VARCHAR2(50) := upper('ALL'); -- inst from the jams job; used for determining instance
v_partition NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
-- v_mod         NUMBER := 5; -- number of partitions to be created
-- v_cpu          NUMBER := 4; -- number of CPUs used for parallelization - do not exceed 20 CPUs [v_mod x --v_cpu] if running simultaneously
v_count        NUMBER := 0;
v_delete_count NUMBER := 0;
v_insert_count NUMBER := 0;
v_elapsed      NUMBER := 0;
v_total_count  NUMBER := 0;
v_job_id       VARCHAR2(32);
v_proc         VARCHAR2(100) := 'etl_aa_pdb_graduate_degrees_tableau';
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
-- create  table utl_d_aa.pdb_graduate_degrees_tableau as
MERGE INTO utl_d_aa.pdb_graduate_degrees_tableau target
USING (
WITH grad AS
 (SELECT stvterm_fa_proc_yr,
         yr_label,
         nvl(campus, 'Total') campus,
         nvl(levl, 'Total') levl,
         COUNT(DISTINCT shrdgmr_pidm) total_graduates,
         CASE
         WHEN COUNT(DISTINCT shrdgmr_pidm) > 99999 THEN
          to_char(round(COUNT(DISTINCT shrdgmr_pidm) / 1000, 0)) || 'K'
         WHEN COUNT(DISTINCT shrdgmr_pidm) > 999 THEN
          to_char(round(COUNT(DISTINCT shrdgmr_pidm) / 1000, 1), 'FM999,999,999.0') || 'K'
         ELSE
          to_char(COUNT(DISTINCT shrdgmr_pidm), 'FM999,999,999')
         END AS total_grad_label,
         COUNT(shrdgmr_pidm) degrees_conferred,
         CASE
         WHEN COUNT(shrdgmr_pidm) > 99999 THEN
          to_char(round(COUNT(shrdgmr_pidm) / 1000, 0)) || 'K'
         WHEN COUNT(shrdgmr_pidm) > 999 THEN
          to_char(round(COUNT(shrdgmr_pidm) / 1000, 1), 'FM999,999,999.0') || 'K'
         ELSE
          to_char(COUNT(shrdgmr_pidm), 'FM999,999,999')
         END AS degress_conferred_label
    FROM (SELECT stvterm_fa_proc_yr,
                 'AY' || substr(stvterm_fa_proc_yr, 1, 2) || '-' || substr(stvterm_fa_proc_yr, 3, 2) yr_label,
                 decode(shrdgmr.shrdgmr_camp_code, 'D', 'LUO', 'R', 'Resident') campus,
                 CASE
                 WHEN stvlevl_code IN ('IN', 'UG') THEN
                  'Undergraduate'
                 WHEN stvlevl_code IN ('GR') THEN
                  'Graduate'
                 WHEN stvlevl_code IN ('JD', 'DR', 'MD') THEN
                  'Doctoral'
                 ELSE
                  stvlevl_desc
                 END levl,
                 shrdgmr_pidm
            FROM shrdgmr
            JOIN stvterm
              ON stvterm_code = shrdgmr_term_code_grad
            JOIN stvacyr
              ON stvacyr_code = stvterm_acyr_code
            JOIN stvlevl
              ON stvlevl_code = shrdgmr_levl_code
           WHERE shrdgmr_degs_code = 'AW'
             AND shrdgmr_levl_code <> 'AC'
             AND stvterm_fa_proc_yr BETWEEN (SELECT tbg4.fa_proc_year - 1806
                                               FROM zbtm.terms_by_group_v tbg4
                                              WHERE trunc(SYSDATE) BETWEEN tbg4.start_date AND tbg4.end_date
                                                AND tbg4.group_code = 'STD')
             AND (SELECT tbg2.fa_proc_year - 101
                    FROM zbtm.terms_by_group_v tbg2
                   WHERE trunc(SYSDATE) BETWEEN tbg2.start_date AND tbg2.end_date
                     AND tbg2.group_code = 'STD'))
   GROUP BY stvterm_fa_proc_yr,
            yr_label,
            ROLLUP(campus),
            ROLLUP(levl))
SELECT grad.*,
       lag(yr_label) over(PARTITION BY campus, levl ORDER BY stvterm_fa_proc_yr) previous_academic_year,
       lag(total_graduates) over(PARTITION BY campus, levl ORDER BY stvterm_fa_proc_yr) previous_academic_year_total_graduates,
       lag(degrees_conferred) over(PARTITION BY campus, levl ORDER BY stvterm_fa_proc_yr) previous_academic_year_degrees_confered,
       lag(total_grad_label) over(PARTITION BY campus, levl ORDER BY stvterm_fa_proc_yr) previous_academic_year_total_grad_label,
       lag(degress_conferred_label) over(PARTITION BY campus, levl ORDER BY stvterm_fa_proc_yr) previous_academic_year_degress_conferred_label,
       SYSDATE AS activity_date
  FROM grad) SOURCE
    ON (target.stvterm_fa_proc_yr = source.stvterm_fa_proc_yr AND target.campus = source.campus AND target.levl = source.levl) WHEN MATCHED THEN
UPDATE
   SET target.yr_label                                       = source.yr_label,
       target.total_graduates                                = source.total_graduates,
       target.total_grad_label                               = source.total_grad_label,
       target.degrees_conferred                              = source.degrees_conferred,
       target.degress_conferred_label                        = source.degress_conferred_label,
       target.previous_academic_year                         = source.previous_academic_year,
       target.previous_academic_year_total_graduates         = source.previous_academic_year_total_graduates,
       target.previous_academic_year_degrees_confered        = source.previous_academic_year_degrees_confered,
       target.previous_academic_year_total_grad_label        = source.previous_academic_year_total_grad_label,
       target.previous_academic_year_degress_conferred_label = source.previous_academic_year_degress_conferred_label,
       target.activity_date                                  = source.activity_date
WHEN NOT MATCHED THEN
INSERT
(stvterm_fa_proc_yr,
 yr_label,
 campus,
 levl,
 total_graduates,
 total_grad_label,
 degrees_conferred,
 degress_conferred_label,
 previous_academic_year,
 previous_academic_year_total_graduates,
 previous_academic_year_degrees_confered,
 previous_academic_year_total_grad_label,
 previous_academic_year_degress_conferred_label,
 activity_date)
VALUES
(source.stvterm_fa_proc_yr,
 source.yr_label,
 source.campus,
 source.levl,
 source.total_graduates,
 source.total_grad_label,
 source.degrees_conferred,
 source.degress_conferred_label,
 source.previous_academic_year,
 source.previous_academic_year_total_graduates,
 source.previous_academic_year_degrees_confered,
 source.previous_academic_year_total_grad_label,
 source.previous_academic_year_degress_conferred_label,
 source.activity_date);
v_insert_count := SQL%ROWCOUNT;
v_total_count  := v_total_count + v_insert_count; -- keep running total of rows processed
v_elapsed      := round((SYSDATE - v_etl_date) * 86400);
v_msg          := 'MERGE - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_insert_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_insert_count);
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
VERSION DATE        USERNAME    UPDATES
---     05-08-2025    WGRIFFITH2  --Initial release
------------------------------------------------------------------------------------------------*/
END etl_aa_pdb_graduate_degrees_tableau; --


procedure etl_aa_pdb_course_success_tableau(jobnumber number, processid varchar2, processname varchar2) is
/*
Table: pdb_course_success_tableau

Primary Keys: NONE

Unique index: NONE

Purpose:
- Track and analyze the success rate of students in courses for a given academic year
- Calculate the percentage of students with passing grades across different courses

Conditions:
- Filtered by academic year (fiscal year/academic year)
- Uses term_code to match specific academic periods
- Focuses on ADS Academics support group
- Supports reporting and analysis of student academic performance

Source Details:
- Dashboard: Presidents Dashboard - Success Rate
- Section: G
- KPIs: Success Rate
- Support Individual: Matt Peele
- Definition: % of students with a passing grade in a given course for the academic year
- Source Report: https://reports.liberty.edu/#/site/Academics/views/SubmissionandSuccessRates/SuccessRateTrends?:iid=1

Relationship Fields:
- terms.fa_proc_year = fa_proc_year (Fiscal/Academic Year Dates)
- term_code = term_code (Fiscal/Academic Year Dates)
*/
--DECLARE
--- PARAMS
v_etl_date DATE := SYSDATE;
v_msg      VARCHAR2(2000);
v_instance VARCHAR2(50) := upper('ALL'); -- inst from the jams job; used for determining instance
v_partition NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
-- v_mod         NUMBER := 5; -- number of partitions to be created
-- v_cpu          NUMBER := 4; -- number of CPUs used for parallelization - do not exceed 20 CPUs [v_mod x --v_cpu] if running simultaneously
v_count        NUMBER := 0;
v_delete_count NUMBER := 0;
v_insert_count NUMBER := 0;
v_elapsed      NUMBER := 0;
v_total_count  NUMBER := 0;
v_job_id       VARCHAR2(32);
v_proc         VARCHAR2(100) := 'etl_aa_pdb_course_success_tableau';
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
-- create  table utl_d_aa.pdb_course_success_tableau as
MERGE INTO utl_d_aa.pdb_course_success_tableau target
USING (
WITH sr AS
 (SELECT terms.fa_proc_year,
         nvl(decode(ll.camp_code, 'D', 'LUO', 'R', 'Resident'), 'Total') camp,
         round(SUM(cgs.success_cnt) / SUM(cgs.total_cnt), 3) success_rate_decimal,
         round(SUM(cgs.success_cnt) / SUM(cgs.total_cnt), 2) * 100 || '%' AS success_rate
    FROM utl_d_aa.crsgradestats cgs
    JOIN utl_d_lms.lms_link ll
      ON ll.term_code = cgs.term_code
     AND ll.crn = cgs.crn
    JOIN zbtm.terms_by_group_v terms
      ON terms.term_code = cgs.term_code
   WHERE terms.fa_proc_year BETWEEN (SELECT tbg4.fa_proc_year - 1806
                                       FROM zbtm.terms_by_group_v tbg4
                                      WHERE trunc(SYSDATE) BETWEEN tbg4.start_date AND tbg4.end_date
                                        AND tbg4.group_code = 'STD')
     AND (SELECT tbg2.fa_proc_year - 101
            FROM zbtm.terms_by_group_v tbg2
           WHERE trunc(SYSDATE) BETWEEN tbg2.start_date AND tbg2.end_date
             AND tbg2.group_code = 'STD')
   GROUP BY terms.fa_proc_year,
            ROLLUP(camp_code))
SELECT fa_proc_year,
       camp,
       success_rate_decimal,
       success_rate,
       lag('AY' || substr(fa_proc_year, 1, 2) || '-' || substr(fa_proc_year, 3, 2)) over(PARTITION BY camp ORDER BY fa_proc_year) AS previous_academic_year,
       lag(success_rate) over(PARTITION BY camp ORDER BY fa_proc_year) AS previous_fiscal_year_success_rate,
       SYSDATE AS activity_date
  FROM sr) SOURCE
    ON (target.fa_proc_year = source.fa_proc_year AND target.camp = source.camp) WHEN MATCHED THEN
UPDATE
   SET target.success_rate_decimal              = source.success_rate_decimal,
       target.success_rate                      = source.success_rate,
       target.previous_academic_year            = source.previous_academic_year,
       target.previous_fiscal_year_success_rate = source.previous_fiscal_year_success_rate,
       target.activity_date                     = source.activity_date
WHEN NOT MATCHED THEN
INSERT
(fa_proc_year,
 camp,
 success_rate_decimal,
 success_rate,
 previous_academic_year,
 previous_fiscal_year_success_rate,
 activity_date)
VALUES
(source.fa_proc_year,
 source.camp,
 source.success_rate_decimal,
 source.success_rate,
 source.previous_academic_year,
 source.previous_fiscal_year_success_rate,
 source.activity_date);
v_insert_count := SQL%ROWCOUNT;
v_total_count  := v_total_count + v_insert_count; -- keep running total of rows processed
v_elapsed      := round((SYSDATE - v_etl_date) * 86400);
v_msg          := 'MERGE - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_insert_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_insert_count);
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
VERSION DATE        USERNAME    UPDATES
---     05-08-2025    WGRIFFITH2  --Initial release
------------------------------------------------------------------------------------------------*/
END etl_aa_pdb_course_success_tableau; --

procedure etl_aa_pdb_persistence_tableau(jobnumber number, processid varchar2, processname varchar2) is
--
-- PURPOSE: Stages end-of-year persistence (retention) summary metrics by cohort and campus for Tableau dashboards.
--
-- TABLE: utl_d_aa.pdb_persistence_tableau
--
-- UNIQUE INDEX: N/A - Full data refresh
--
-- CONDITIONS:
-- Truncates utl_d_aa.pdb_persistence_tableau at the start of the run and then inserts refreshed rows (full table refresh).
-- Selects cohort_term, return_term and timeframe_end_date from ads_etl.get_term_dates for Resident (v_camp_code='R') and LUO (v_camp_code='D') campuses only.
-- Excludes terms with dates.group_code = 'MED' (medical school).
-- Only includes terms whose timeframe_end_date is before the current date (term must have ended).
-- Determines which terms to process by comparing get_term_dates.report_timestamp to the last loaded activity_date in the target (uses MAX(TRUNC(activity_date)) grouped by cohort_term, return_term); includes terms with no prior report or with a later report_timestamp than the target (TRUNC comparison at day precision).
-- Processes the selected cohort_term/return_term pairs in ascending order (cursor c_terms).
-- For each term pair, joins utl_d_aa.persistence_log (plog) to utl_d_aa.enrollments_log (elog) on elog.term_code = plog.cohort_term and elog.pidm = plog.pidm to align enrollment records with persistence records.
-- Filters persistence_log to the current cohort_term and return_term (plog.cohort_term = rec.cohort_term AND plog.return_term = rec.return_term).
-- Requires the cursor's timeframe_end_date to fall within both the enrollment and persistence log effective date ranges (rec.timeframe_end_date BETWEEN elog.from_date AND elog.to_date AND BETWEEN plog.from_date AND plog.to_date); timeframe_end_date is used as the effective "unrevised" end-of-year snapshot date.
-- Derives campus from elog.camp_code (CASE: 'R' => 'Resident', 'D' => 'LUO') and aggregates results by that derived campus.
-- Inserts report_type as the constant 'ADY' for every row.
-- total_enrollment is COUNT(plog.pidm) — the count of persistence_log pidm occurrences for the snapshot.
-- total_graduated is SUM(plog.graduated) — counts students marked graduated in persistence_log for the snapshot.
-- total_ret is SUM(plog.returned) — counts students recorded as having returned/persisted in persistence_log for the snapshot.
-- ret_percent is calculated as SUM(plog.returned) / (COUNT(plog.pidm) - SUM(plog.graduated)), rounded to four decimal places; if the denominator is zero the percentage is set to 0.
-- Aggregation yields one row per campus (Resident or LUO) for each processed cohort_term/return_term combination.
-- activity_date for each inserted row is set to the procedure run timestamp (v_etl_date).
-- Because the target table is truncated at the start, any existing rows not re-inserted by this run will be removed.
-- URL: https://reports.liberty.edu/#/site/Academics/views/ProgramEnrollmentNumbers/PacingModel-Historical
--
--DECLARE
--- PARAMS
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
v_proc         VARCHAR2(100) := 'etl_aa_pdb_persistence_tableau';
CURSOR c_terms IS
SELECT DISTINCT dates.cohort_term,
                dates.return_term,
                dates.return_end_date
  FROM ads_etl.get_term_dates(v_acad_year => NULL, v_days_back => NULL, v_camp_code => 'R') dates -- search for RES 
 WHERE dates.return_end_date < SYSDATE -- term must have ended to show numbers
UNION
SELECT DISTINCT dates.cohort_term,
                dates.return_term,
                dates.return_end_date
  FROM ads_etl.get_term_dates(v_acad_year => NULL, v_days_back => NULL, v_camp_code => 'D') dates -- search for LUO 
 WHERE dates.return_end_date < SYSDATE -- term must have ended to show numbers
 ORDER BY cohort_term ASC,
          return_term ASC;
BEGIN
-- dbms_output.enable(buffer_size => NULL);
--
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
utl_d_aa.truncate_table(v_table_name => 'pdb_persistence_tableau');
FOR rec IN c_terms
LOOP
v_count   := 0; -- reset count
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || rec.cohort_term || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
INSERT INTO utl_d_aa.pdb_persistence_tableau
(cohort_term,
 return_term,
 campus,
 report_type,
 total_enrollment,
 total_graduated,
 total_ret,
 ret_percent,
 activity_date)
SELECT rec.cohort_term AS cohort_term,
       rec.return_term AS return_term,
       CASE
       WHEN elog.camp_code = 'R' THEN
        'Resident'
       WHEN elog.camp_code = 'D' THEN
        'LUO'
       END AS campus,
       'ADY' AS persistence_type,
       COUNT(plog.pidm) AS total_enrollment,
       SUM(plog.graduated) AS total_graduated,
       SUM(plog.returned) AS total_ret,
       CASE
       WHEN COUNT(plog.pidm) - SUM(plog.graduated) = 0 THEN
        0
       ELSE
        round(SUM(plog.returned) / (COUNT(plog.pidm) - SUM(plog.graduated)), 4)
       END AS ret_percent,
       v_etl_date AS activity_date
  FROM utl_d_aa.persistence_log plog
  JOIN utl_d_aa.enrollments_log elog
    ON elog.term_code = plog.cohort_term
   AND elog.pidm = plog.pidm
 WHERE plog.cohort_term = rec.cohort_term
   AND plog.return_term = rec.return_term
   AND rec.return_end_date BETWEEN elog.from_date AND elog.to_date -- using return_end_date for effective date to show as "unrevised" EOY numbers
   AND rec.return_end_date BETWEEN plog.from_date AND plog.to_date -- using return_end_date for effective date to show as "unrevised" EOY numbers
 GROUP BY CASE
          WHEN elog.camp_code = 'R' THEN
           'Resident'
          WHEN elog.camp_code = 'D' THEN
           'LUO'
          END;
v_insert_count := SQL%ROWCOUNT;
v_total_count  := v_total_count + v_insert_count; -- keep running total of rows processed
v_elapsed      := round((SYSDATE - v_etl_date) * 86400);
v_msg          := 'INSERT - ' || rec.cohort_term || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_insert_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_insert_count);
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
RAISE;
END etl_aa_pdb_persistence_tableau;

procedure etl_aa_pdb_luo_credit_threshold_tableau(jobnumber number, processid varchar2, processname varchar2) is
/*
Table: pdb_luo_credit_threshold_tableau

Primary Keys: NONE

Unique index: NONE

Purpose:
- Track LUO Graduates who have conferred a degree with at least 60 hours of credits from LU
- Support Presidents Dashboard in Section G
- Monitor KPIs: Total Graduates, Degrees Conferred

Conditions:
-- Graduates must have 60+ credit hours from LU
-- Match fiscal/academic year processing dates (fa_proc_yr)

Support Details:
-- Support Group: ADS Academics
-- Support Individual: Matt Peele

Definition:
Number of LUO Graduates who have conferred a degree with at least 60 hours of their credits coming from LU

*/
--DECLARE
--- PARAMS
v_etl_date DATE := SYSDATE;
v_msg      VARCHAR2(2000);
v_instance VARCHAR2(50) := upper('ALL'); -- inst from the jams job; used for determining instance
v_partition NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
-- v_mod         NUMBER := 5; -- number of partitions to be created
-- v_cpu          NUMBER := 4; -- number of CPUs used for parallelization - do not exceed 20 CPUs [v_mod x --v_cpu] if running simultaneously
v_count        NUMBER := 0;
v_delete_count NUMBER := 0;
v_insert_count NUMBER := 0;
v_elapsed      NUMBER := 0;
v_total_count  NUMBER := 0;
v_job_id       VARCHAR2(32);
v_proc         VARCHAR2(100) := 'etl_aa_pdb_luo_credit_threshold_tableau';
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
-- create  table utl_d_aa.pdb_luo_credit_threshold_tableau as
MERGE INTO utl_d_aa.pdb_luo_credit_threshold_tableau target
USING (
WITH grad AS
 (SELECT fa_proc_yr,
         yr_label,
         campus,
         metric,
         total
    FROM (SELECT stvterm_fa_proc_yr AS fa_proc_yr,
                 'AY' || substr(stvterm_fa_proc_yr, 1, 2) || '-' || substr(stvterm_fa_proc_yr, 3, 2) AS yr_label,
                 'LUO' AS campus,
                 COUNT(DISTINCT shrdgmr_pidm) AS "Total Graduates",
                 CASE
                 WHEN COUNT(DISTINCT shrdgmr_pidm) > 99999 THEN
                  to_char(round(COUNT(DISTINCT shrdgmr_pidm) / 1000, 0)) || 'K'
                 WHEN COUNT(DISTINCT shrdgmr_pidm) > 999 THEN
                  to_char(round(COUNT(DISTINCT shrdgmr_pidm) / 1000, 1)) || 'K'
                 ELSE
                  to_char(COUNT(DISTINCT shrdgmr_pidm), 'FM999,999,999')
                 END AS total_grad_label,
                 COUNT(shrdgmr_pidm) AS "Degrees Conferred",
                 CASE
                 WHEN COUNT(shrdgmr_pidm) > 99999 THEN
                  to_char(round(COUNT(shrdgmr_pidm) / 1000, 0)) || 'K'
                 WHEN COUNT(shrdgmr_pidm) > 999 THEN
                  to_char(round(COUNT(shrdgmr_pidm) / 1000, 1)) || 'K'
                 ELSE
                  to_char(COUNT(shrdgmr_pidm), 'FM999,999,999')
                 END AS degress_conferred_label
            FROM shrdgmr
            JOIN stvterm
              ON stvterm_code = shrdgmr_term_code_grad
            JOIN stvacyr
              ON stvacyr_code = stvterm_acyr_code
            JOIN shrlgpa
              ON shrlgpa_pidm = shrdgmr_pidm
             AND shrlgpa_levl_code = shrdgmr_levl_code
             AND shrlgpa_gpa_type_ind = 'I'
             AND shrlgpa.shrlgpa_hours_earned > 60
           WHERE shrdgmr_degs_code = 'AW'
             AND shrdgmr_camp_code = 'D'
             AND stvterm_fa_proc_yr BETWEEN (SELECT tbg4.fa_proc_year - 1806
                                               FROM zbtm.terms_by_group_v tbg4
                                              WHERE trunc(SYSDATE) BETWEEN tbg4.start_date AND tbg4.end_date
                                                AND tbg4.group_code = 'STD')
             AND (SELECT tbg2.fa_proc_year - 101
                    FROM zbtm.terms_by_group_v tbg2
                   WHERE trunc(SYSDATE) BETWEEN tbg2.start_date AND tbg2.end_date
                     AND tbg2.group_code = 'STD')
           GROUP BY stvterm_fa_proc_yr,
                    'AY' || substr(stvterm_fa_proc_yr, 1, 2) || '-' || substr(stvterm_fa_proc_yr, 3, 2)) src unpivot(total FOR metric IN("Total Graduates", "Degrees Conferred")))
SELECT grad.fa_proc_yr,
       grad.yr_label,
       grad.campus,
       grad.metric,
       grad.total,
       decode(grad.metric, 'Total Graduates', 'Graduates', 'Degrees Conferred', 'Degrees') AS metric_label,
       lag(grad.yr_label) over(PARTITION BY grad.metric ORDER BY grad.fa_proc_yr) AS previous_academic_year,
       lag(grad.total) over(PARTITION BY grad.metric ORDER BY grad.fa_proc_yr) AS previous_academic_year_total,
       SYSDATE AS activity_date
  FROM grad) SOURCE
    ON (target.fa_proc_yr = source.fa_proc_yr AND target.campus = source.campus AND target.metric = source.metric) WHEN MATCHED THEN
UPDATE
   SET target.yr_label                     = source.yr_label,
       target.total                        = source.total,
       target.metric_label                 = source.metric_label,
       target.previous_academic_year       = source.previous_academic_year,
       target.previous_academic_year_total = source.previous_academic_year_total,
       target.activity_date                = source.activity_date
WHEN NOT MATCHED THEN
INSERT
(fa_proc_yr,
 yr_label,
 campus,
 metric,
 total,
 metric_label,
 previous_academic_year,
 previous_academic_year_total,
 activity_date)
VALUES
(source.fa_proc_yr,
 source.yr_label,
 source.campus,
 source.metric,
 source.total,
 source.metric_label,
 source.previous_academic_year,
 source.previous_academic_year_total,
 source.activity_date);
v_insert_count := SQL%ROWCOUNT;
v_total_count  := v_total_count + v_insert_count; -- keep running total of rows processed
v_elapsed      := round((SYSDATE - v_etl_date) * 86400);
v_msg          := 'MERGE - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_insert_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_insert_count);
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
VERSION DATE        USERNAME    UPDATES
---     05-08-2025    WGRIFFITH2  --Initial release
------------------------------------------------------------------------------------------------*/
END etl_aa_pdb_luo_credit_threshold_tableau; --

procedure etl_aa_pdb_peak_convo_tableau(jobnumber number, processid varchar2, processname varchar2) is
/*
Table: pdb_peak_convo_tableau

Primary Keys: NONE

Unique index: NONE

Purpose:
- Track the largest Convocation attendance for the Presidents Dashboard
- Capture the highest count of individuals marked present at a Convocation during the academic year

Conditions:
-- Sourced from https://reports.liberty.edu/#/site/Convocation/workbooks/5124/views
-- Relationship based on fiscal/academic year dates (fa_proc_year = fa_proc_year)
-- Supported by ADS Academics
-- Individuals tracking: Lauren Gallagher/Ciara Volkov
-- Section C KPI metric

*/
--DECLARE
--- PARAMS
v_etl_date DATE := SYSDATE;
v_msg      VARCHAR2(2000);
v_instance VARCHAR2(50) := upper('ALL'); -- inst from the jams job; used for determining instance
v_partition NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
-- v_mod         NUMBER := 5; -- number of partitions to be created
-- v_cpu          NUMBER := 4; -- number of CPUs used for parallelization - do not exceed 20 CPUs [v_mod x --v_cpu] if running simultaneously
v_count        NUMBER := 0;
v_delete_count NUMBER := 0;
v_insert_count NUMBER := 0;
v_elapsed      NUMBER := 0;
v_total_count  NUMBER := 0;
v_job_id       VARCHAR2(32);
v_proc         VARCHAR2(100) := 'etl_aa_pdb_peak_convo_tableau';
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
-- create  table utl_d_aa.pdb_peak_convo_tableau as
MERGE INTO utl_d_aa.pdb_peak_convo_tableau target
USING (
WITH ytd AS
 (SELECT t.fa_proc_year,
         MIN(t.start_date) ay_start,
         to_date(CASE
                 WHEN to_char(SYSDATE, 'MMDD') >= to_char(MIN(t.start_date), 'MMDD') THEN
                  REPLACE(to_char(SYSDATE, 'YYYY-MM-DD'), to_char(SYSDATE, 'YYYY'), to_char(SYSDATE, 'YYYY') - floor(months_between(trunc(SYSDATE, 'YEAR'), trunc(MIN(t.start_date), 'YEAR')) / 12))
                 ELSE
                  REPLACE(to_char(SYSDATE, 'YYYY-MM-DD'), to_char(SYSDATE, 'YYYY'), to_char(SYSDATE, 'YYYY') - floor(months_between(trunc(SYSDATE, 'YEAR'), trunc(MIN(t.start_date), 'YEAR')) / 12) + 1)
                 END, 'YYYY-MM-DD') report_date
    FROM zbtm.terms_by_group_v t
   WHERE t.group_code = 'STD'
   GROUP BY t.fa_proc_year),
max_c AS
 (SELECT r.fa_proc_year,
         MAX(r.attendance) largest_convo_attendance,
         MAX(r.attendance_ytd) largest_convo_attendance_ytd
    FROM (SELECT t.fa_proc_year,
                 c_date convocation_date,
                 COUNT(DISTINCT pidm) attendance,
                 CASE
                 WHEN c_date BETWEEN ytd.ay_start AND ytd.report_date THEN
                  COUNT(DISTINCT pidm)
                 ELSE
                  0
                 END attendance_ytd
            FROM (SELECT h.szrahst_convo_date c_date,
                         h.szrahst_pidm       pidm
                    FROM zconvocation.szrahst h
                   WHERE h.szrahst_attendance = 'P'
                     AND h.szrahst_to_date IS NULL
                     AND h.szrahst_convo_date >= add_months(trunc(SYSDATE, 'mon'), -36)
                  UNION
                  SELECT trunc(a2.time_in) c_date,
                         a2.pidm pidm
                    FROM zquickpass_reporting.attendance a2
                   WHERE a2.location_code = 'CONVO'
                     AND a2.time_in >= add_months(trunc(SYSDATE, 'mon'), -36)
                  UNION
                  SELECT trunc(a.time_in) c_date,
                         a.pidm pidm
                    FROM zswiper.attendance a
                   WHERE a.location_id IN (11641026, 7608093, 10979923)
                     AND a.time_in >= add_months(trunc(SYSDATE, 'mon'), -36)) x
            JOIN zbtm.terms_by_group_v t
              ON x.c_date BETWEEN t.start_date AND t.end_date
             AND t.group_code = 'STD'
            JOIN ytd
              ON ytd.fa_proc_year = t.fa_proc_year
           GROUP BY t.fa_proc_year,
                    c_date,
                    ytd.ay_start,
                    ytd.report_date) r
   GROUP BY r.fa_proc_year)
SELECT max_c.fa_proc_year,
       max_c.largest_convo_attendance,
       max_c.largest_convo_attendance_ytd,
       lag('AY' || substr(fa_proc_year, 1, 2) || '-' || substr(fa_proc_year, 3, 2)) over(ORDER BY fa_proc_year) AS previous_academic_year,
       lag(largest_convo_attendance) over(ORDER BY fa_proc_year) AS previous_academic_largest_convo_attendance,
       lag(largest_convo_attendance_ytd) over(ORDER BY fa_proc_year) AS previous_academic_ytd_largest_convo_attendance,
       SYSDATE AS activity_date
  FROM max_c) SOURCE
    ON (target.fa_proc_year = source.fa_proc_year) WHEN MATCHED THEN
UPDATE
   SET target.largest_convo_attendance                       = source.largest_convo_attendance,
       target.largest_convo_attendance_ytd                   = source.largest_convo_attendance_ytd,
       target.previous_academic_year                         = source.previous_academic_year,
       target.previous_academic_largest_convo_attendance     = source.previous_academic_largest_convo_attendance,
       target.previous_academic_ytd_largest_convo_attendance = source.previous_academic_ytd_largest_convo_attendance,
       target.activity_date                                  = source.activity_date
WHEN NOT MATCHED THEN
INSERT
(fa_proc_year,
 largest_convo_attendance,
 largest_convo_attendance_ytd,
 previous_academic_year,
 previous_academic_largest_convo_attendance,
 previous_academic_ytd_largest_convo_attendance,
 activity_date)
VALUES
(source.fa_proc_year,
 source.largest_convo_attendance,
 source.largest_convo_attendance_ytd,
 source.previous_academic_year,
 source.previous_academic_largest_convo_attendance,
 source.previous_academic_ytd_largest_convo_attendance,
 source.activity_date);
v_insert_count := SQL%ROWCOUNT;
v_total_count  := v_total_count + v_insert_count; -- keep running total of rows processed
v_elapsed      := round((SYSDATE - v_etl_date) * 86400);
v_msg          := 'MERGE - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_insert_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_insert_count);
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
VERSION DATE        USERNAME    UPDATES
---     05-08-2025    WGRIFFITH2  --Initial release
------------------------------------------------------------------------------------------------*/
END etl_aa_pdb_peak_convo_tableau; --

procedure etl_aa_pdb_eoc_surveys_tableau(jobnumber number, processid varchar2, processname varchar2) is
/*
Table: pdb_eoc_surveys_tableau

Primary Keys: NONE

Unique index: NONE

Purpose:
- Capture Presidents Dashboard metrics for End of Course Surveys
- Track student responses to course quality on a 4-point scale
- Provide key performance indicators (KPIs) for academic surveys

Conditions:
-- Measures student responses from the last term
-- Uses term_code as the relationship field
-- Supports ADS Academics group
-- Managed by Matt Peele

KPIs Tracked:
- Average EOC Score (1 = Completely Disagree, 4 = Completely Agree)
- Survey Response Count

Source: Source Report with term_code matching current fiscal/academic year
*/
--DECLARE
--- PARAMS
v_etl_date DATE := SYSDATE;
v_msg      VARCHAR2(2000);
v_instance VARCHAR2(50) := upper('ALL'); -- inst from the jams job; used for determining instance
v_partition NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
-- v_mod         NUMBER := 5; -- number of partitions to be created
-- v_cpu          NUMBER := 4; -- number of CPUs used for parallelization - do not exceed 20 CPUs [v_mod x --v_cpu] if running simultaneously
v_count        NUMBER := 0;
v_delete_count NUMBER := 0;
v_insert_count NUMBER := 0;
v_elapsed      NUMBER := 0;
v_total_count  NUMBER := 0;
v_job_id       VARCHAR2(32);
v_proc         VARCHAR2(100) := 'etl_aa_pdb_eoc_surveys_tableau';
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
-- create  table utl_d_aa.pdb_eoc_surveys_tableau as
MERGE INTO utl_d_aa.pdb_eoc_surveys_tableau target
USING (
WITH eoc AS
 (SELECT stvterm_code AS term_code,
         upper(substr(term, 1, 3)) || ' ' || substr(term, -2) term_label,
         nvl(decode(camp, 'Online', 'LUO', 'Resident', 'Resident'), 'Total') campus,
         round(AVG(resp), 2) avg_eoc_survey_score,
         COUNT(*) survey_resp_count,
         SUM(decode(resp, 0, 1, 0)) star_0,
         SUM(decode(resp, 1, 1, 0)) star_1,
         SUM(decode(resp, 2, 1, 0)) star_2,
         SUM(decode(resp, 3, 1, 0)) star_3,
         SUM(decode(resp, 4, 1, 0)) star_4,
         SUM(decode(resp, 5, 1, 0)) star_5
    FROM (SELECT stvterm_desc            AS term,
                 stvterm_code            AS stvterm_code,
                 cst.college,
                 NULL                    AS department,
                 cst.subj_code           AS subj,
                 cst.crse_numb           AS numb,
                 cst.course,
                 cst.course_code,
                 cst.seq_numb            AS sect,
                 cst.levl_code           AS levl,
                 cst.camp_code           AS camp,
                 cst.camp_code           AS far_camp,
                 cst.survey_id,
                 cst.question_number     AS question,
                 cst.question_text       AS qt,
                 cst.numeric_answer      AS resp,
                 cst.response_unique_id,
                 cst.response,
                 cst.instructor_name     AS prof,
                 cst.instructor_luid     AS prof_luid,
                 cst.instructor_username AS "Instructor Username",
                 cst.im_usernames        AS "IM Usernames",
                 cst.chair_usernames     AS "Chair Usernames",
                 cst.dean_usernames      AS "Dean Usernames",
                 cst.fsc_usernames       AS "FSC Usernames",
                 cst.sme_usernames       AS "SME Usernames",
                 cst.admin_usernames     AS "Admin Usernames",
                 cst.director_usernames  AS "Director Usernames",
                 cst.question_type,
                 cst.current_survey,
                 cst.current_year,
                 cst.faculty_status,
                 cst.activity_date
            FROM utl_d_lms.course_surveys_tableau cst
            JOIN stvterm
              ON stvterm_code = cst.term_code
           WHERE cst.question_source = 3 -- quant scores
          )
   GROUP BY term,
            stvterm_code,
            ROLLUP(camp))
SELECT term_code,
       term_label,
       campus,
       'Average Score Data' data_category,
       avg_eoc_survey_score,
       survey_resp_count,
       lag(term_label) over(PARTITION BY campus ORDER BY term_code) previous_academic_year_term,
       lag(avg_eoc_survey_score) over(PARTITION BY campus ORDER BY term_code) previous_academic_year_term_avg_eoc_survey_score,
       lag(survey_resp_count) over(PARTITION BY campus ORDER BY term_code) previous_academic_year_survey_resp_count,
       NULL score,
       NULL score_cnt
  FROM eoc
UNION ALL
SELECT term_code,
       term_label,
       campus,
       'Score Count Data',
       NULL,
       NULL,
       NULL,
       NULL,
       NULL,
       score,
       total
  FROM eoc unpivot(total FOR score IN(star_0 AS '0 Stars', star_1 AS '1 Star', star_2 AS '2 Stars', star_3 AS '3 Stars', star_4 AS '4 Stars', star_5 AS '5 Stars'))) SOURCE
    ON (target.term_code = source.term_code AND target.campus = source.campus AND target.data_category = source.data_category AND nvl(target.score, 'NULL') = nvl(source.score, 'NULL')) WHEN MATCHED THEN
UPDATE
   SET target.term_label                                       = source.term_label,
       target.avg_eoc_survey_score                             = source.avg_eoc_survey_score,
       target.survey_resp_count                                = source.survey_resp_count,
       target.previous_academic_year_term                      = source.previous_academic_year_term,
       target.previous_academic_year_term_avg_eoc_survey_score = source.previous_academic_year_term_avg_eoc_survey_score,
       target.previous_academic_year_survey_resp_count         = source.previous_academic_year_survey_resp_count,
       target.score_cnt                                        = source.score_cnt,
       target.activity_date                                    = SYSDATE
WHEN NOT MATCHED THEN
INSERT
(term_code,
 term_label,
 campus,
 data_category,
 avg_eoc_survey_score,
 survey_resp_count,
 previous_academic_year_term,
 previous_academic_year_term_avg_eoc_survey_score,
 previous_academic_year_survey_resp_count,
 score,
 score_cnt,
 activity_date)
VALUES
(source.term_code,
 source.term_label,
 source.campus,
 source.data_category,
 source.avg_eoc_survey_score,
 source.survey_resp_count,
 source.previous_academic_year_term,
 source.previous_academic_year_term_avg_eoc_survey_score,
 source.previous_academic_year_survey_resp_count,
 source.score,
 source.score_cnt,
 SYSDATE);
v_insert_count := SQL%ROWCOUNT;
v_total_count  := v_total_count + v_insert_count; -- keep running total of rows processed
v_elapsed      := round((SYSDATE - v_etl_date) * 86400);
v_msg          := 'MERGE -' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_insert_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_insert_count);
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
VERSION DATE        USERNAME    UPDATES
---     05-08-2025    WGRIFFITH2  --Initial release
------------------------------------------------------------------------------------------------*/
END etl_aa_pdb_eoc_surveys_tableau; --

procedure etl_aa_pdb_cser_hours_tableau(jobnumber number, processid varchar2, processname varchar2) is
/*
Table: pdb_cser_hours_tableau

Primary Keys: NONE

Unique index: NONE

Purpose:
- Track and report total CSER (Community Service and Experiential Learning) hours
- Capture completed CSER registrations for Academic Year reporting
- Support Presidents Dashboard KPI tracking for CSER hours

Conditions:
-- CSER registration must be in 'Registration Complete' status
-- CSER evaluation must be in 'Evaluation Complete' status
-- Hours are summed for a specific Academic Year
-- Supports ADS Academics support group
-- Managed by Lauren Gallagher/Ciara Volkov

Source:
- Report: https://argosprod03.liberty.edu/Argos/AWV/#explorer/Banner%00CSER%00Reports%00Self-Service%00Admin/Hours%20Logged
- Relationship Field: fa_proc_year = fa_proc_year (fy/ay Dates)

Exclusions:
-- Registrations in statuses:
   - Pending (various approvals)
   - Contract Denied
   - Registration Denied
   - Registration Cancelled
   - Registration Dropped

-- Evaluations in statuses:
   - Evaluation Cancelled
   - Pending Student Reflection
   - Pending Supervisor Evaluation
*/
--DECLARE
--- PARAMS
v_etl_date DATE := SYSDATE;
v_msg      VARCHAR2(2000);
v_instance VARCHAR2(50) := upper('ALL'); -- inst from the jams job; used for determining instance
v_partition NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
-- v_mod         NUMBER := 5; -- number of partitions to be created
-- v_cpu          NUMBER := 4; -- number of CPUs used for parallelization - do not exceed 20 CPUs [v_mod x --v_cpu] if running simultaneously
v_count        NUMBER := 0;
v_delete_count NUMBER := 0;
v_insert_count NUMBER := 0;
v_elapsed      NUMBER := 0;
v_total_count  NUMBER := 0;
v_job_id       VARCHAR2(32);
v_proc         VARCHAR2(100) := 'etl_aa_pdb_cser_hours_tableau';
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
-- CREATE  table utl_d_aa.pdb_cser_hours_tableau as
MERGE INTO utl_d_aa.pdb_cser_hours_tableau target
USING (
WITH ytd AS
 (SELECT t.fa_proc_year,
         MIN(t.start_date) ay_start,
         to_date(CASE
                 WHEN to_char(SYSDATE, 'MMDD') >= to_char(MIN(t.start_date), 'MMDD') THEN
                  REPLACE(to_char(SYSDATE, 'YYYY-MM-DD'), to_char(SYSDATE, 'YYYY'), to_char(SYSDATE, 'YYYY') - floor(months_between(trunc(SYSDATE, 'YEAR'), trunc(MIN(t.start_date), 'YEAR')) / 12))
                 ELSE
                  REPLACE(to_char(SYSDATE, 'YYYY-MM-DD'), to_char(SYSDATE, 'YYYY'), to_char(SYSDATE, 'YYYY') - floor(months_between(trunc(SYSDATE, 'YEAR'), trunc(MIN(t.start_date), 'YEAR')) / 12) + 1)
                 END, 'YYYY-MM-DD') report_date
    FROM zbtm.terms_by_group_v t
   WHERE t.group_code = 'STD'
   GROUP BY t.fa_proc_year),
cser AS
 (SELECT t.fa_proc_year,
         ytd.report_date,
         floor(SUM(e.szbcsev_hours_completed)) total_cser_hours,
         floor(SUM(CASE
                   WHEN e.szbcsev_create_date BETWEEN ytd.ay_start AND ytd.report_date THEN
                    e.szbcsev_hours_completed
                   ELSE
                    0
                   END)) AS total_cser_hours_ytd
    FROM zsaturn.szbcsrf r
    JOIN zsaturn.szbcsev e
      ON e.szbcsev_reg_recnum = r.szbcsrf_surrogate_id
     AND e.szbcsev_status_ind = 'C'
    JOIN zbtm.terms_by_group_v t
      ON t.term_code = r.szbcsrf_term_code
     AND t.group_code = 'STD'
    LEFT JOIN ytd
      ON ytd.fa_proc_year = t.fa_proc_year
   WHERE r.szbcsrf_status_ind = 'R'
   GROUP BY t.fa_proc_year,
            ytd.ay_start,
            ytd.report_date
   ORDER BY 1 DESC
   FETCH FIRST 5 rows ONLY)
SELECT cser.fa_proc_year,
       cser.report_date,
       cser.total_cser_hours,
       cser.total_cser_hours_ytd,
       'AY' || substr(cser.fa_proc_year, 1, 2) || '-' || substr(cser.fa_proc_year, 3, 2) AS academic_year,
       lag('AY' || substr(cser.fa_proc_year, 1, 2) || '-' || substr(cser.fa_proc_year, 3, 2)) over(ORDER BY cser.fa_proc_year) AS previous_academic_year,
       lag(cser.total_cser_hours) over(ORDER BY cser.fa_proc_year) AS previous_academic_year_total_cser_hours,
       lag(cser.total_cser_hours_ytd) over(ORDER BY cser.fa_proc_year) AS previous_total_cser_hours_ytd,
       SYSDATE AS activity_date
  FROM cser) SOURCE
    ON (target.fa_proc_year = source.fa_proc_year) WHEN MATCHED THEN
UPDATE
   SET target.report_date                             = source.report_date,
       target.total_cser_hours                        = source.total_cser_hours,
       target.total_cser_hours_ytd                    = source.total_cser_hours_ytd,
       target.academic_year                           = source.academic_year,
       target.previous_academic_year                  = source.previous_academic_year,
       target.previous_academic_year_total_cser_hours = source.previous_academic_year_total_cser_hours,
       target.previous_total_cser_hours_ytd           = source.previous_total_cser_hours_ytd,
       target.activity_date                           = source.activity_date
WHEN NOT MATCHED THEN
INSERT
(fa_proc_year,
 report_date,
 total_cser_hours,
 total_cser_hours_ytd,
 academic_year,
 previous_academic_year,
 previous_academic_year_total_cser_hours,
 previous_total_cser_hours_ytd,
 activity_date)
VALUES
(source.fa_proc_year,
 source.report_date,
 source.total_cser_hours,
 source.total_cser_hours_ytd,
 source.academic_year,
 source.previous_academic_year,
 source.previous_academic_year_total_cser_hours,
 source.previous_total_cser_hours_ytd,
 source.activity_date);
v_insert_count := SQL%ROWCOUNT;
v_total_count  := v_total_count + v_insert_count; -- keep running total of rows processed
v_elapsed      := round((SYSDATE - v_etl_date) * 86400);
v_msg          := 'MERGE -' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_insert_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_insert_count);
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
VERSION DATE        USERNAME    UPDATES
---     05-08-2025    WGRIFFITH2  --Initial release
------------------------------------------------------------------------------------------------*/
END etl_aa_pdb_cser_hours_tableau; --

procedure etl_aa_pdb_convo_attendance_tableau(jobnumber number, processid varchar2, processname varchar2) is
/*
Table: pdb_convo_attendance_tableau

Primary Keys: NONE

Unique index: NONE

Purpose:
- Track average attendance for Convocation events in an Academic Year
- Capture attendance through Convocation Check In application or QuickPass system

Conditions:
-- Attendance is counted for:
-- 1. Individuals marked as present in Convocation Check In application
-- 2. Individuals who swiped into Convocation QuickPass system

*/
--DECLARE
--- PARAMS
v_etl_date DATE := SYSDATE;
v_msg      VARCHAR2(2000);
v_instance VARCHAR2(50) := upper('ALL'); -- inst from the jams job; used for determining instance
v_partition NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
-- v_mod         NUMBER := 5; -- number of partitions to be created
-- v_cpu          NUMBER := 4; -- number of CPUs used for parallelization - do not exceed 20 CPUs [v_mod x --v_cpu] if running simultaneously
v_count        NUMBER := 0;
v_delete_count NUMBER := 0;
v_insert_count NUMBER := 0;
v_elapsed      NUMBER := 0;
v_total_count  NUMBER := 0;
v_job_id       VARCHAR2(32);
v_proc         VARCHAR2(100) := 'etl_aa_pdb_convo_attendance_tableau';
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
-- CREATE  table utl_d_aa.pdb_convo_attendance_tableau as
MERGE INTO utl_d_aa.pdb_convo_attendance_tableau target
USING (
WITH ytd AS
 (SELECT t.fa_proc_year,
         MIN(t.start_date) ay_start,
         to_date(CASE
                 WHEN to_char(SYSDATE, 'MMDD') >= to_char(MIN(t.start_date), 'MMDD') THEN
                  REPLACE(to_char(SYSDATE, 'YYYY-MM-DD'), to_char(SYSDATE, 'YYYY'), to_char(SYSDATE, 'YYYY') - floor(months_between(trunc(SYSDATE, 'YEAR'), trunc(MIN(t.start_date), 'YEAR')) / 12))
                 ELSE
                  REPLACE(to_char(SYSDATE, 'YYYY-MM-DD'), to_char(SYSDATE, 'YYYY'), to_char(SYSDATE, 'YYYY') - floor(months_between(trunc(SYSDATE, 'YEAR'), trunc(MIN(t.start_date), 'YEAR')) / 12) + 1)
                 END, 'YYYY-MM-DD') report_date
    FROM zbtm.terms_by_group_v t
   WHERE t.group_code = 'STD'
   GROUP BY t.fa_proc_year),
ca AS
 (SELECT x.fa_proc_year,
         x.report_date,
         floor(AVG(x.present_count)) academic_year_attendance,
         floor(AVG(x.present_count_ytd)) academic_ytd_attendance
    FROM (SELECT t.fa_proc_year,
                 t.term_code term,
                 ytd.report_date,
                 d.szrcond_convo_date convo_date,
                 COUNT(DISTINCT x.pidm) present_count,
                 CASE
                 WHEN x.c_date BETWEEN ytd.ay_start AND ytd.report_date THEN
                  COUNT(DISTINCT x.pidm)
                 ELSE
                  NULL
                 END present_count_ytd
            FROM ( ----Convocation Application Attendance
                  SELECT h.szrahst_convo_date c_date,
                          h.szrahst_pidm       pidm
                    FROM zconvocation.szrahst h
                   WHERE h.szrahst_attendance = 'P'
                     AND h.szrahst_to_date IS NULL
                  UNION
                  ---QuickPass Convocation Attendance
                  SELECT trunc(a2.time_in) c_date,
                          a2.pidm pidm
                    FROM zquickpass_reporting.attendance a2
                   WHERE a2.location_code = 'CONVO'
                  UNION
                  --Convo - Manual Attendance, LWC - Vines Center, Convocation - Floor Seating
                  SELECT trunc(a.time_in) c_date,
                          a.pidm pidm
                    FROM zswiper.attendance a
                   WHERE a.location_id IN (11641026, 7608093, 10979923)) x
          --Excluding Cancelled (No Convocation) or Exempt (No Convocation IRs / Attendance Tracking)
            JOIN zconvocation.szrcond d
              ON d.szrcond_convo_date = x.c_date
             AND d.szrcond_cancelled = 'N'
             AND d.szrcond_exempted = 'N'
          --Term and Academic Year of Convo Date
            JOIN zbtm.terms_by_group_v t
              ON d.szrcond_convo_date BETWEEN t.start_date AND t.end_date
             AND t.group_code = 'STD'
            JOIN ytd
              ON ytd.fa_proc_year = t.fa_proc_year
           WHERE 1 = 1
           GROUP BY t.fa_proc_year,
                    t.term_code,
                    d.szrcond_convo_date,
                    ytd.report_date,
                    ytd.ay_start,
                    x.c_date) x
   GROUP BY x.fa_proc_year,
            x.report_date
   ORDER BY 1 DESC
   FETCH FIRST 5 rows ONLY)
SELECT ca.*,
       'AY' || substr(fa_proc_year, 1, 2) || '-' || substr(fa_proc_year, 3, 2) AS academic_year,
       lag('AY' || substr(fa_proc_year, 1, 2) || '-' || substr(fa_proc_year, 3, 2)) over(ORDER BY fa_proc_year) AS previous_academic_year,
       lag(academic_year_attendance) over(ORDER BY fa_proc_year) AS previous_academic_year_attendance,
       lag(academic_ytd_attendance) over(ORDER BY fa_proc_year) AS previous_academic_ytd_attendance
  FROM ca) SOURCE
    ON (target.fa_proc_year = source.fa_proc_year) WHEN MATCHED THEN
UPDATE
   SET target.academic_year_attendance          = source.academic_year_attendance,
       target.academic_ytd_attendance           = source.academic_ytd_attendance,
       target.academic_year                     = source.academic_year,
       target.previous_academic_year            = source.previous_academic_year,
       target.previous_academic_year_attendance = source.previous_academic_year_attendance,
       target.previous_academic_ytd_attendance  = source.previous_academic_ytd_attendance,
       target.activity_date                     = SYSDATE
WHEN NOT MATCHED THEN
INSERT
(fa_proc_year,
 academic_year_attendance,
 academic_ytd_attendance,
 academic_year,
 previous_academic_year,
 previous_academic_year_attendance,
 previous_academic_ytd_attendance,
 activity_date)
VALUES
(source.fa_proc_year,
 source.academic_year_attendance,
 source.academic_ytd_attendance,
 source.academic_year,
 source.previous_academic_year,
 source.previous_academic_year_attendance,
 source.previous_academic_ytd_attendance,
 SYSDATE);
v_insert_count := SQL%ROWCOUNT;
v_total_count  := v_total_count + v_insert_count; -- keep running total of rows processed
v_elapsed      := round((SYSDATE - v_etl_date) * 86400);
v_msg          := 'MERGE -' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_insert_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_insert_count);
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
VERSION DATE        USERNAME    UPDATES
---     05-08-2025    WGRIFFITH2  --Initial release
---     09-23-2025    lagallagher  -- Identified and fixed issue with YTD averages showing low attendance; previous years were counted as 0 instead of null
------------------------------------------------------------------------------------------------*/
END etl_aa_pdb_convo_attendance_tableau; --

procedure etl_aa_pdb_community_attendance_tableau(jobnumber number, processid varchar2, processname varchar2) is
/*
Table: pdb_community_attendance_tableau

Primary Keys: NONE

Unique index: NONE

Purpose:
- Provides data for the Presidents Dashboard - Community Group Attendance (Section C)
- Calculates the average community group attendance for on-campus students
- Supports KPI tracking for Avg Community Group Attendance

Conditions:
- Data is sourced from [REPORT] LU Shepherd Admin Dashboard-NEW LU Shepherd Dashboard (Tableau)
- Relationship field mapping is fa_proc_year = fa_proc_year (fy/ay Dates)
- Measures attendance during the academic year only
- Support provided by ADS Academics team (Lauren Gallagher/Ciara Volkov)

*/
--DECLARE
--- PARAMS
v_etl_date DATE := SYSDATE;
v_msg      VARCHAR2(2000);
v_instance VARCHAR2(50) := upper('ALL'); -- inst from the jams job; used for determining instance
v_partition NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
-- v_mod         NUMBER := 5; -- number of partitions to be created
-- v_cpu          NUMBER := 4; -- number of CPUs used for parallelization - do not exceed 20 CPUs [v_mod x --v_cpu] if running simultaneously
v_count        NUMBER := 0;
v_delete_count NUMBER := 0;
v_insert_count NUMBER := 0;
v_elapsed      NUMBER := 0;
v_total_count  NUMBER := 0;
v_job_id       VARCHAR2(32);
v_proc         VARCHAR2(100) := 'etl_aa_pdb_community_attendance_tableau';
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
-- CREATE  table utl_d_aa.pdb_community_attendance_tableau as
MERGE INTO utl_d_aa.pdb_community_attendance_tableau target
USING (
WITH ytd AS
 (SELECT t.fa_proc_year,
         MIN(t.start_date) ay_start,
         to_date(CASE
                 WHEN to_char(SYSDATE, 'MMDD') >= to_char(MIN(t.start_date), 'MMDD') THEN
                  REPLACE(to_char(SYSDATE, 'YYYY-MM-DD'), to_char(SYSDATE, 'YYYY'), to_char(SYSDATE, 'YYYY') - floor(months_between(trunc(SYSDATE, 'YEAR'), trunc(MIN(t.start_date), 'YEAR')) / 12))
                 ELSE
                  REPLACE(to_char(SYSDATE, 'YYYY-MM-DD'), to_char(SYSDATE, 'YYYY'), to_char(SYSDATE, 'YYYY') - floor(months_between(trunc(SYSDATE, 'YEAR'), trunc(MIN(t.start_date), 'YEAR')) / 12) + 1)
                 END, 'YYYY-MM-DD') report_date
    FROM zbtm.terms_by_group_v t
   WHERE t.group_code = 'STD'
   GROUP BY t.fa_proc_year),
cga AS
 (SELECT x.fa_proc_year,
         floor(AVG(x.present_count)) academic_year_attendance,
         floor(AVG(x.present_count_ytd)) academic_ytd_attendance
    FROM (SELECT t.fa_proc_year,
                 ytd.report_date,
                 t.term_code term,
                 d.szrcond_cg_date convo_date,
                 COUNT(DISTINCT a.szrahst_pidm) present_count,
                 CASE
                 WHEN d.szrcond_cg_date BETWEEN ytd.ay_start AND ytd.report_date THEN
                  COUNT(DISTINCT a.szrahst_pidm)
                 ELSE
                  NULL
                 END present_count_ytd
            FROM zcommunitygroups.szrahst a
            JOIN zcommunitygroups.szrcond d
              ON d.szrcond_cg_date = a.szrahst_cg_date
             AND d.szrcond_to_date IS NULL
             AND d.szrcond_cancelled = 'N'
            JOIN zbtm.terms_by_group_v t
              ON d.szrcond_cg_date BETWEEN t.start_date AND t.end_date
             AND t.group_code = 'STD'
            JOIN ytd
              ON ytd.fa_proc_year = t.fa_proc_year
           WHERE a.szrahst_to_date IS NULL
             AND a.szrahst_attendance = 'P'
           GROUP BY t.fa_proc_year,
                    t.term_code,
                    d.szrcond_cg_date,
                    ytd.report_date,
                    ytd.ay_start) x
   GROUP BY x.fa_proc_year
   ORDER BY 1 DESC
   FETCH FIRST 5 rows ONLY)
SELECT cga.*,
       'AY' || substr(fa_proc_year, 1, 2) || '-' || substr(fa_proc_year, 3, 2) AS academic_year,
       lag('AY' || substr(fa_proc_year, 1, 2) || '-' || substr(fa_proc_year, 3, 2)) over(ORDER BY fa_proc_year) AS previous_academic_year,
       lag(academic_year_attendance) over(ORDER BY fa_proc_year) AS previous_academic_year_attendance,
       lag(academic_ytd_attendance) over(ORDER BY fa_proc_year) AS previous_academic_ytd_attendance,
       SYSDATE AS activity_date
  FROM cga) SOURCE
    ON (target.fa_proc_year = source.fa_proc_year) WHEN MATCHED THEN
UPDATE
   SET target.academic_year_attendance          = source.academic_year_attendance,
       target.academic_ytd_attendance           = source.academic_ytd_attendance,
       target.academic_year                     = source.academic_year,
       target.previous_academic_year            = source.previous_academic_year,
       target.previous_academic_year_attendance = source.previous_academic_year_attendance,
       target.previous_academic_ytd_attendance  = source.previous_academic_ytd_attendance,
       target.activity_date                     = source.activity_date
WHEN NOT MATCHED THEN
INSERT
(fa_proc_year,
 academic_year_attendance,
 academic_ytd_attendance,
 academic_year,
 previous_academic_year,
 previous_academic_year_attendance,
 previous_academic_ytd_attendance,
 activity_date)
VALUES
(source.fa_proc_year,
 source.academic_year_attendance,
 source.academic_ytd_attendance,
 source.academic_year,
 source.previous_academic_year,
 source.previous_academic_year_attendance,
 source.previous_academic_ytd_attendance,
 source.activity_date);
v_insert_count := SQL%ROWCOUNT;
v_total_count  := v_total_count + v_insert_count; -- keep running total of rows processed
v_elapsed      := round((SYSDATE - v_etl_date) * 86400);
v_msg          := 'MERGE - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_insert_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_insert_count);
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
VERSION DATE        USERNAME    UPDATES
---     05-08-2025    WGRIFFITH2  -- Initial release
---     09-23-2025    lagallagher  -- Identified and fixed issue with YTD averages showing low attendance; previous years were counted as 0 instead of null
------------------------------------------------------------------------------------------------*/
END etl_aa_pdb_community_attendance_tableau; --

procedure etl_aa_pdb_graduation_rate_tableau(jobnumber number, processid varchar2, processname varchar2) is
/*
Table:pdb_graduation_rate_tableau

Primary Keys: NONE

Unique index: NONE

Purpose:
- Populates data for the President's Dashboard (Section G) - 6-year Graduation Rate KPI
- Calculates the IPEDS-defined 6-year graduation rate for first-time, full-time, undergraduate students
- Supports analytics maintained by ADS Academics (Matt Peele)

Conditions:
- Cohort defined as First Time Full Time Degree Seeking students
- Calculates percentage of cohort students who graduate within 6 years
- Students marked as deceased during the 6-year timeframe are excluded from calculations
- Results displayed in President's Dashboard visualization tools

*/
--DECLARE
--- PARAMS
v_etl_date DATE := SYSDATE;
v_msg      VARCHAR2(2000);
v_instance VARCHAR2(50) := upper('ALL'); -- inst from the jams job; used for determining instance
v_partition NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
-- v_mod         NUMBER := 5; -- number of partitions to be created
-- v_cpu          NUMBER := 4; -- number of CPUs used for parallelization - do not exceed 20 CPUs [v_mod x --v_cpu] if running simultaneously
v_count        NUMBER := 0;
v_delete_count NUMBER := 0;
v_insert_count NUMBER := 0;
v_elapsed      NUMBER := 0;
v_total_count  NUMBER := 0;
v_job_id       VARCHAR2(32);
v_proc         VARCHAR2(100) := 'etl_aa_pdb_graduation_rate_tableau';
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
-- create table utl_d_aa.pdb_graduation_rate_tableau as
MERGE INTO utl_d_aa.pdb_graduation_rate_tableau target
USING (
WITH gr AS
 (
  -- 4 year Freshmen Grads
  SELECT stvterm.stvterm_code starting_cohort,
          to_char(to_number(stvterm.stvterm_code) + 400) starting_cohort_plus_four_years,
          upper(substr(stvterm.stvterm_desc, 1, 3)) || ' ' || substr(stvterm.stvterm_desc, -2) term_label,
          substr(stvterm.stvterm_desc, 1, length(stvterm.stvterm_desc) - 4) || substr(stvterm.stvterm_desc, -2) term_label_long,
          '4 year Freshmen Grads' category,
          nvl(decode(shrdgmr_camp_code, 'R', 'Resident', 'D', 'LUO'), 'Total') camp,
          COUNT(DISTINCT zsrcefa.zsrcefa_pidm) COUNT,
          CASE
          WHEN COUNT(DISTINCT zsrcefa.zsrcefa_pidm) > 99999 THEN
           to_char(round(COUNT(DISTINCT zsrcefa.zsrcefa_pidm) / 1000, 0)) || 'K'
          WHEN COUNT(DISTINCT zsrcefa.zsrcefa_pidm) > 999 THEN
           to_char(round(COUNT(DISTINCT zsrcefa.zsrcefa_pidm) / 1000, 1)) || 'K'
          ELSE
           to_char(COUNT(DISTINCT zsrcefa.zsrcefa_pidm), 'FM999,999,999')
          END AS count_label
    FROM zsaturn.zsrcefa
   INNER JOIN stvterm
      ON stvterm.stvterm_code = zsrcefa.zsrcefa_term_code
   INNER JOIN shrdgmr
      ON shrdgmr.shrdgmr_pidm = zsrcefa.zsrcefa_pidm
     AND shrdgmr.shrdgmr_degs_code = 'AW'
     AND shrdgmr.shrdgmr_grad_date >= (SELECT MIN(stvterm_start_date) FROM stvterm WHERE stvterm_code = zsrcefa.zsrcefa_term_code)
     AND shrdgmr.shrdgmr_grad_date < (SELECT MIN(stvterm_start_date) FROM stvterm WHERE stvterm_code = zsrcefa.zsrcefa_term_code + 400)
    LEFT JOIN spbpers
      ON spbpers_pidm = zsrcefa.zsrcefa_pidm
     AND spbpers.spbpers_dead_date IS NULL
   WHERE 1 = 1
     AND zsrcefa.zsrcefa_rectype = 'FROZ'
     AND zsrcefa.zsrcefa_sfrstcr_ind = 'Y'
     AND zsrcefa.zsrcefa_stustat = '1'
     AND zsrcefa.zsrcefa_level_ IN ('21', '22', '41', '42')
     AND zsrcefa.zsrcefa_term_code IN (SELECT tbg1.term_code
                                         FROM zbtm.terms_by_group_v tbg1
                                        WHERE tbg1.semester = 'FAL'
                                          AND tbg1.group_code = 'STD'
                                          AND tbg1.fa_proc_year BETWEEN (SELECT tbg4.fa_proc_year - 1806
                                                                           FROM zbtm.terms_by_group_v tbg4
                                                                          WHERE trunc(SYSDATE) BETWEEN tbg4.start_date AND tbg4.end_date
                                                                            AND tbg4.group_code = 'STD')
                                          AND (SELECT tbg2.fa_proc_year - 404
                                                 FROM zbtm.terms_by_group_v tbg2
                                                WHERE trunc(SYSDATE) BETWEEN tbg2.start_date AND tbg2.end_date
                                                  AND tbg2.group_code = 'STD'))
     AND zsrcefa.zsrcefa_levl_code <> 'AC'
   GROUP BY stvterm.stvterm_desc,
             stvterm.stvterm_code,
             ROLLUP(decode(shrdgmr_camp_code, 'R', 'Resident', 'D', 'LUO'))
  UNION
  -- 2 year Transfer Grads
  SELECT stvterm.stvterm_code cohort_term,
          to_char(to_number(stvterm.stvterm_code) + 400) starting_cohort_plus_six_years,
          upper(substr(stvterm.stvterm_desc, 1, 3)) || ' ' || substr(stvterm.stvterm_desc, -2) term_label,
          substr(stvterm.stvterm_desc, 1, length(stvterm.stvterm_desc) - 4) || substr(stvterm.stvterm_desc, -2) term_label_long,
          '2 year Transfer Grads' category,
          nvl(decode(shrdgmr_camp_code, 'R', 'Resident', 'D', 'LUO'), 'Total') camp,
          COUNT(DISTINCT zsrcefa.zsrcefa_pidm) COUNT,
          CASE
          WHEN COUNT(DISTINCT zsrcefa.zsrcefa_pidm) > 99999 THEN
           to_char(round(COUNT(DISTINCT zsrcefa.zsrcefa_pidm) / 1000, 0)) || 'K'
          WHEN COUNT(DISTINCT zsrcefa.zsrcefa_pidm) > 999 THEN
           to_char(round(COUNT(DISTINCT zsrcefa.zsrcefa_pidm) / 1000, 1)) || 'K'
          ELSE
           to_char(COUNT(DISTINCT zsrcefa.zsrcefa_pidm), 'FM999,999,999')
          END AS count_label
    FROM zsaturn.zsrcefa
   INNER JOIN stvterm
      ON stvterm.stvterm_code = zsrcefa.zsrcefa_term_code
   INNER JOIN shrdgmr
      ON shrdgmr.shrdgmr_pidm = zsrcefa.zsrcefa_pidm
     AND shrdgmr.shrdgmr_degs_code = 'AW'
     AND shrdgmr.shrdgmr_grad_date >= (SELECT MIN(stvterm_start_date) FROM stvterm WHERE stvterm_code = zsrcefa.zsrcefa_term_code)
     AND shrdgmr.shrdgmr_grad_date < (SELECT MIN(stvterm_start_date) FROM stvterm WHERE stvterm_code = zsrcefa.zsrcefa_term_code + 200)
    LEFT JOIN spbpers
      ON spbpers_pidm = zsrcefa.zsrcefa_pidm
     AND spbpers.spbpers_dead_date IS NULL
   WHERE 1 = 1
     AND zsrcefa.zsrcefa_rectype = 'FROZ'
     AND zsrcefa.zsrcefa_sfrstcr_ind = 'Y'
     AND zsrcefa.zsrcefa_stustat = '2'
     AND zsrcefa.zsrcefa_level_ IN ('21', '22', '41', '42')
     AND zsrcefa.zsrcefa_term_code IN (SELECT tbg1.term_code
                                         FROM zbtm.terms_by_group_v tbg1
                                        WHERE tbg1.semester = 'FAL'
                                          AND tbg1.group_code = 'STD'
                                          AND tbg1.fa_proc_year BETWEEN (SELECT tbg4.fa_proc_year - 1806
                                                                           FROM zbtm.terms_by_group_v tbg4
                                                                          WHERE trunc(SYSDATE) BETWEEN tbg4.start_date AND tbg4.end_date
                                                                            AND tbg4.group_code = 'STD')
                                          AND (SELECT tbg2.fa_proc_year - 404
                                                 FROM zbtm.terms_by_group_v tbg2
                                                WHERE trunc(SYSDATE) BETWEEN tbg2.start_date AND tbg2.end_date
                                                  AND tbg2.group_code = 'STD'))
     AND zsrcefa.zsrcefa_levl_code <> 'AC'
   GROUP BY stvterm.stvterm_desc,
             stvterm.stvterm_code,
             ROLLUP(decode(shrdgmr_camp_code, 'R', 'Resident', 'D', 'LUO')))
SELECT gr.starting_cohort,
       gr.starting_cohort_plus_four_years,
       gr.term_label,
       gr.term_label_long,
       gr.category,
       gr.camp,
       gr.count,
       gr.count_label,
       lag(gr.term_label) over(PARTITION BY gr.category, gr.camp ORDER BY gr.category, gr.camp, gr.starting_cohort) AS previous_academic_year_term,
       lag(gr.term_label_long) over(PARTITION BY gr.category, gr.camp ORDER BY gr.category, gr.camp, gr.starting_cohort) AS previous_academic_year_term_long,
       lag(gr.count) over(PARTITION BY gr.category, gr.camp ORDER BY gr.category, gr.camp, gr.starting_cohort) AS previous_academic_year_count,
       lag(gr.count_label) over(PARTITION BY gr.category, gr.camp ORDER BY gr.category, gr.camp, gr.starting_cohort) AS previous_academic_year_count_label
  FROM gr) SOURCE
    ON (target.starting_cohort = source.starting_cohort AND target.category = source.category AND target.camp = source.camp) WHEN MATCHED THEN
UPDATE
   SET target.starting_cohort_plus_four_years    = source.starting_cohort_plus_four_years,
       target.term_label                         = source.term_label,
       target.term_label_long                    = source.term_label_long,
       target.count                              = source.count,
       target.count_label                        = source.count_label,
       target.previous_academic_year_term        = source.previous_academic_year_term,
       target.previous_academic_year_term_long   = source.previous_academic_year_term_long,
       target.previous_academic_year_count       = source.previous_academic_year_count,
       target.previous_academic_year_count_label = source.previous_academic_year_count_label
WHEN NOT MATCHED THEN
INSERT
(starting_cohort,
 starting_cohort_plus_four_years,
 term_label,
 term_label_long,
 category,
 camp,
 COUNT,
 count_label,
 previous_academic_year_term,
 previous_academic_year_term_long,
 previous_academic_year_count,
 previous_academic_year_count_label)
VALUES
(source.starting_cohort,
 source.starting_cohort_plus_four_years,
 source.term_label,
 source.term_label_long,
 source.category,
 source.camp,
 source.count,
 source.count_label,
 source.previous_academic_year_term,
 source.previous_academic_year_term_long,
 source.previous_academic_year_count,
 source.previous_academic_year_count_label);
v_insert_count := SQL%ROWCOUNT;
v_total_count  := v_total_count + v_insert_count; -- keep running total of rows processed
v_elapsed      := round((SYSDATE - v_etl_date) * 86400);
v_msg          := 'MERGE -' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_insert_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_insert_count);
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
VERSION DATE        USERNAME    UPDATES
---     05-08-2025    WGRIFFITH2  --Initial release
------------------------------------------------------------------------------------------------*/
END etl_aa_pdb_graduation_rate_tableau; --

procedure etl_aa_pdb_completion_time_tableau(jobnumber number, processid varchar2, processname varchar2) is
/*
Table: pdb_completion_time_tableau

Primary Keys: NONE

Unique index: NONE

Purpose:
- Populates the Presidents Dashboard (Section G) with graduation completion time metrics
- Tracks two Key Performance Indicators (KPIs):
  1. Number of First Time Students (Freshmen) who completed a degree within 4 years
  2. Number of Transfer students who completed an Undergraduate Degree within 2 years

Conditions:
- Uses cohort data with term codes
- Calculates completion based on a plus-four-years relationship field
- Relationship field formula: to_char(to_number(stvterm.stvterm_code) +400) starting_cohort_plus_four_years = TERM_CODE
- Support provided by Matt Peele (ADS Academics)
*/
--DECLARE
--- PARAMS
v_etl_date DATE := SYSDATE;
v_msg      VARCHAR2(2000);
v_instance VARCHAR2(50) := upper('ALL'); -- inst from the jams job; used for determining instance
v_partition NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
-- v_mod         NUMBER := 5; -- number of partitions to be created
-- v_cpu          NUMBER := 4; -- number of CPUs used for parallelization - do not exceed 20 CPUs [v_mod x --v_cpu] if running simultaneously
v_count        NUMBER := 0;
v_delete_count NUMBER := 0;
v_insert_count NUMBER := 0;
v_elapsed      NUMBER := 0;
v_total_count  NUMBER := 0;
v_job_id       VARCHAR2(32);
v_proc         VARCHAR2(100) := 'etl_aa_pdb_completion_time_tableau';
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
MERGE INTO utl_d_aa.pdb_completion_time_tableau target
USING (
WITH gr AS
 (
  -- 4 year Freshmen Grads
  SELECT stvterm.stvterm_code starting_cohort,
          to_char(to_number(stvterm.stvterm_code) + 400) starting_cohort_plus_four_years,
          upper(substr(stvterm.stvterm_desc, 1, 3)) || ' ' || substr(stvterm.stvterm_desc, -2) term_label,
          substr(stvterm.stvterm_desc, 1, length(stvterm.stvterm_desc) - 4) || substr(stvterm.stvterm_desc, -2) term_label_long,
          '4 year Freshmen Grads' category,
          nvl(decode(shrdgmr_camp_code, 'R', 'Resident', 'D', 'LUO'), 'Total') camp,
          COUNT(DISTINCT zsrcefa.zsrcefa_pidm) COUNT,
          CASE
          WHEN COUNT(DISTINCT zsrcefa.zsrcefa_pidm) > 99999 THEN
           to_char(round(COUNT(DISTINCT zsrcefa.zsrcefa_pidm) / 1000, 0)) || 'K'
          WHEN COUNT(DISTINCT zsrcefa.zsrcefa_pidm) > 999 THEN
           to_char(round(COUNT(DISTINCT zsrcefa.zsrcefa_pidm) / 1000, 1)) || 'K'
          ELSE
           to_char(COUNT(DISTINCT zsrcefa.zsrcefa_pidm), 'FM999,999,999')
          END AS count_label
    FROM zsaturn.zsrcefa
   INNER JOIN stvterm
      ON stvterm.stvterm_code = zsrcefa.zsrcefa_term_code
   INNER JOIN shrdgmr
      ON shrdgmr.shrdgmr_pidm = zsrcefa.zsrcefa_pidm
     AND shrdgmr.shrdgmr_degs_code = 'AW'
     AND shrdgmr.shrdgmr_grad_date >= (SELECT MIN(stvterm_start_date) FROM stvterm WHERE stvterm_code = zsrcefa.zsrcefa_term_code)
     AND shrdgmr.shrdgmr_grad_date < (SELECT MIN(stvterm_start_date) FROM stvterm WHERE stvterm_code = zsrcefa.zsrcefa_term_code + 400)
    LEFT JOIN spbpers
      ON spbpers_pidm = zsrcefa.zsrcefa_pidm
     AND spbpers.spbpers_dead_date IS NULL
   WHERE 1 = 1
     AND zsrcefa.zsrcefa_rectype = 'FROZ'
     AND zsrcefa.zsrcefa_sfrstcr_ind = 'Y'
     AND zsrcefa.zsrcefa_stustat = '1'
     AND zsrcefa.zsrcefa_level_ IN ('21', '22', '41', '42')
     AND zsrcefa.zsrcefa_term_code IN (SELECT tbg1.term_code
                                         FROM zbtm.terms_by_group_v tbg1
                                        WHERE tbg1.semester = 'FAL'
                                          AND tbg1.group_code = 'STD'
                                          AND tbg1.fa_proc_year BETWEEN (SELECT tbg4.fa_proc_year - 1806
                                                                           FROM zbtm.terms_by_group_v tbg4
                                                                          WHERE trunc(SYSDATE) BETWEEN tbg4.start_date AND tbg4.end_date
                                                                            AND tbg4.group_code = 'STD')
                                          AND (SELECT tbg2.fa_proc_year - 404
                                                 FROM zbtm.terms_by_group_v tbg2
                                                WHERE trunc(SYSDATE) BETWEEN tbg2.start_date AND tbg2.end_date
                                                  AND tbg2.group_code = 'STD'))
     AND zsrcefa.zsrcefa_levl_code <> 'AC'
   GROUP BY stvterm.stvterm_desc,
             stvterm.stvterm_code,
             ROLLUP(decode(shrdgmr_camp_code, 'R', 'Resident', 'D', 'LUO'))
  UNION
  -- 2 year Transfer Grads
  SELECT stvterm.stvterm_code cohort_term,
          to_char(to_number(stvterm.stvterm_code) + 400) starting_cohort_plus_six_years,
          upper(substr(stvterm.stvterm_desc, 1, 3)) || ' ' || substr(stvterm.stvterm_desc, -2) term_label,
          substr(stvterm.stvterm_desc, 1, length(stvterm.stvterm_desc) - 4) || substr(stvterm.stvterm_desc, -2) term_label_long,
          '2 year Transfer Grads' category,
          nvl(decode(shrdgmr_camp_code, 'R', 'Resident', 'D', 'LUO'), 'Total') camp,
          COUNT(DISTINCT zsrcefa.zsrcefa_pidm) COUNT,
          CASE
          WHEN COUNT(DISTINCT zsrcefa.zsrcefa_pidm) > 99999 THEN
           to_char(round(COUNT(DISTINCT zsrcefa.zsrcefa_pidm) / 1000, 0)) || 'K'
          WHEN COUNT(DISTINCT zsrcefa.zsrcefa_pidm) > 999 THEN
           to_char(round(COUNT(DISTINCT zsrcefa.zsrcefa_pidm) / 1000, 1)) || 'K'
          ELSE
           to_char(COUNT(DISTINCT zsrcefa.zsrcefa_pidm), 'FM999,999,999')
          END AS count_label
    FROM zsaturn.zsrcefa
   INNER JOIN stvterm
      ON stvterm.stvterm_code = zsrcefa.zsrcefa_term_code
   INNER JOIN shrdgmr
      ON shrdgmr.shrdgmr_pidm = zsrcefa.zsrcefa_pidm
     AND shrdgmr.shrdgmr_degs_code = 'AW'
     AND shrdgmr.shrdgmr_grad_date >= (SELECT MIN(stvterm_start_date) FROM stvterm WHERE stvterm_code = zsrcefa.zsrcefa_term_code)
     AND shrdgmr.shrdgmr_grad_date < (SELECT MIN(stvterm_start_date) FROM stvterm WHERE stvterm_code = zsrcefa.zsrcefa_term_code + 200)
    LEFT JOIN spbpers
      ON spbpers_pidm = zsrcefa.zsrcefa_pidm
     AND spbpers.spbpers_dead_date IS NULL
   WHERE 1 = 1
     AND zsrcefa.zsrcefa_rectype = 'FROZ'
     AND zsrcefa.zsrcefa_sfrstcr_ind = 'Y'
     AND zsrcefa.zsrcefa_stustat = '2'
     AND zsrcefa.zsrcefa_level_ IN ('21', '22', '41', '42')
     AND zsrcefa.zsrcefa_term_code IN (SELECT tbg1.term_code
                                         FROM zbtm.terms_by_group_v tbg1
                                        WHERE tbg1.semester = 'FAL'
                                          AND tbg1.group_code = 'STD'
                                          AND tbg1.fa_proc_year BETWEEN (SELECT tbg4.fa_proc_year - 1806
                                                                           FROM zbtm.terms_by_group_v tbg4
                                                                          WHERE trunc(SYSDATE) BETWEEN tbg4.start_date AND tbg4.end_date
                                                                            AND tbg4.group_code = 'STD')
                                          AND (SELECT tbg2.fa_proc_year - 404
                                                 FROM zbtm.terms_by_group_v tbg2
                                                WHERE trunc(SYSDATE) BETWEEN tbg2.start_date AND tbg2.end_date
                                                  AND tbg2.group_code = 'STD'))
     AND zsrcefa.zsrcefa_levl_code <> 'AC'
   GROUP BY stvterm.stvterm_desc,
             stvterm.stvterm_code,
             ROLLUP(decode(shrdgmr_camp_code, 'R', 'Resident', 'D', 'LUO')))
SELECT gr.starting_cohort,
       gr.starting_cohort_plus_four_years,
       gr.term_label,
       gr.term_label_long,
       gr.category,
       gr.camp,
       gr.count,
       gr.count_label,
       lag(gr.term_label) over(PARTITION BY gr.category, gr.camp ORDER BY gr.category, gr.camp, gr.starting_cohort) AS previous_academic_year_term,
       lag(gr.term_label_long) over(PARTITION BY gr.category, gr.camp ORDER BY gr.category, gr.camp, gr.starting_cohort) AS previous_academic_year_term_long,
       lag(gr.count) over(PARTITION BY gr.category, gr.camp ORDER BY gr.category, gr.camp, gr.starting_cohort) AS previous_academic_year_count,
       lag(gr.count_label) over(PARTITION BY gr.category, gr.camp ORDER BY gr.category, gr.camp, gr.starting_cohort) AS previous_academic_year_count_label
  FROM gr) SOURCE
    ON (target.starting_cohort = source.starting_cohort AND target.category = source.category AND target.camp = source.camp) WHEN MATCHED THEN
UPDATE
   SET target.starting_cohort_plus_four_years    = source.starting_cohort_plus_four_years,
       target.term_label                         = source.term_label,
       target.term_label_long                    = source.term_label_long,
       target.count                              = source.count,
       target.count_label                        = source.count_label,
       target.previous_academic_year_term        = source.previous_academic_year_term,
       target.previous_academic_year_term_long   = source.previous_academic_year_term_long,
       target.previous_academic_year_count       = source.previous_academic_year_count,
       target.previous_academic_year_count_label = source.previous_academic_year_count_label,
       target.activity_date                      = v_etl_date
WHEN NOT MATCHED THEN
INSERT
(starting_cohort,
 starting_cohort_plus_four_years,
 term_label,
 term_label_long,
 category,
 camp,
 COUNT,
 count_label,
 previous_academic_year_term,
 previous_academic_year_term_long,
 previous_academic_year_count,
 previous_academic_year_count_label)
VALUES
(source.starting_cohort,
 source.starting_cohort_plus_four_years,
 source.term_label,
 source.term_label_long,
 source.category,
 source.camp,
 source.count,
 source.count_label,
 source.previous_academic_year_term,
 source.previous_academic_year_term_long,
 source.previous_academic_year_count,
 source.previous_academic_year_count_label);
v_insert_count := SQL%ROWCOUNT;
v_total_count  := v_total_count + v_insert_count; -- keep running total of rows processed
v_elapsed      := round((SYSDATE - v_etl_date) * 86400);
v_msg          := 'MERGE - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_insert_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_insert_count);
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
VERSION DATE        USERNAME    UPDATES
---     05-08-2025    WGRIFFITH2  --Initial release
------------------------------------------------------------------------------------------------*/
END etl_aa_pdb_completion_time_tableau; --

procedure etl_aa_pdb_retention_tableau(jobnumber number, processid varchar2, processname varchar2) is
-- =============================================================================
-- PURPOSE: Stages campus-level cohort retention summaries (end-of-year and year-to-date snapshots) for Tableau reporting on student progression and graduation retention rates.
--
-- TARGET(S): utl_d_aa.pdb_retention_tableau
--
-- UNIQUE KEY / INDEX: cohort_year, return_year, campus, report_type
--
-- BUSINESS LOGIC & CONDITIONS:
-- - Retrieves academic calendar metadata from ads_etl.get_acad_dates filtered to rows where the current academic day number matches the same relative day position in prior academic years (enables year-over-year comparison at identical calendar positions).
-- - Cohort year is calculated as (academic_year - 101); return year is set to the academic year itself.
-- - Processes each matched academic calendar row in ascending academic year and report timestamp order.
-- - Generates two distinct report types per cohort: ADY (end-of-year) and YTD (year-to-date).
-- - Joins retention_log (rlog) to enrollments_log (elog) on matching academic year (elog.acad_year = rlog.cohort_year) and student ID (elog.pidm = rlog.pidm) to ensure retention flags are paired with the student's enrollment record.
-- - Restricts enrollment rows to yr_rank = 1 to use only each student's last term of enrollment for counting purposes.
-- - Excludes Winter semester enrollment records (elog.semester <> 'WIN').
-- - Maps campus codes to display names: camp_code 'R' maps to 'Resident'; camp_code 'D' maps to 'LUO' (Liberty University Online); all other codes are excluded from output.
-- - ADY (end-of-year) rows: Uses acad_end_date as the effective date snapshot. Requires acad_end_date to fall between both elog.from_date and elog.to_date AND between rlog.from_date and rlog.to_date (produces "unrevised" end-of-year numbers). Only inserts ADY rows when acad_end_date is strictly prior to the ETL execution date (ensures year is fully complete before reporting EOY figures).
-- - YTD (year-to-date) rows: Uses report_timestamp as the effective date snapshot. Requires report_timestamp to fall between both elog.from_date and elog.to_date AND between rlog.from_date and rlog.to_date (produces running year-to-date numbers).
-- - Aggregates data at the campus level: total_enrollment = count of distinct student IDs; total_graduated = sum of graduated flags; total_ret = sum of returned flags.
-- - Retention percentage calculation: if (total_enrollment - total_graduated) equals zero then ret_percent = 0; otherwise ret_percent = round(total_ret / (total_enrollment - total_graduated), 4) to four decimal places.
-- - Activity date for all inserted rows is set to the ETL execution date (v_etl_date).
-- - Both ADY and YTD use identical join and aggregation logic; only the effective date source differs.
-- - Data is appended to the target table via INSERT statements (no truncation or replacement of existing retention data).
-- - Each cohort/return year/campus combination may generate one aggregated ADY row and one aggregated YTD row (maximum two rows per unique campus per cohort cycle).
--
-- DEPENDENCIES: ads_etl.get_acad_dates, utl_d_aa.retention_log, utl_d_aa.enrollments_log, ads_etl.insert_job_log, ads_etl.clear_table
--
-- CONSTRAINTS & RISKS:
-- - Requires exact PIDM and academic year matching between retention_log and enrollments_log; mismatched or missing foreign keys will result in zero retention records for affected cohorts.
-- - ADY rows will not appear in the staging table until the academic year end date has passed the ETL run date; early-in-year runs will produce only YTD rows.
-- - Processing is sequential per cohort; large volumes of historical retention and enrollment data may incur extended runtime.
-- - Calendar-based filtering (acad_day_number = current_acad_day_number) assumes get_acad_dates returns consistent and complete academic calendar metadata for all years under comparison.
-- URL: https://reports.liberty.edu/#/site/Academics/views/ProgramEnrollmentNumbers/PacingModel-Historical
-- =============================================================================
-- DECLARE
--- PARAMS
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
v_proc         VARCHAR2(100) := 'etl_aa_pdb_retention_tableau';
CURSOR c_terms IS
-- ---------------------------------------------------------------------------
--   fiscal_day_number / current_fiscal_day_number  -> July 1-June 30 positional matching
--   acad_day_number  / current_acad_day_number      -> academic term calendar positional matching
-- ---------------------------------------------------------------------------
SELECT to_char(dates.acad_year - 101) AS cohort_year,
       dates.acad_year AS return_year,
       to_date(to_char(trunc(dates.report_timestamp), 'MM/DD/YYYY'), 'MM/DD/YYYY') AS report_date,
       dates.report_timestamp,
       dates.timeframe_start_date,
       dates.timeframe_end_date,
       dates.acad_start_date,
       dates.acad_end_date
  FROM utl_d_aa.acad_year_dates dates
 WHERE dates.acad_day_number = dates.current_acad_day_number -- get the properly aligned acad day of the year to compare to previous years
    AND dates.group_code = 'STD' -- only need standard group_code
   AND dates.acad_year >= '1920' -- no historical prior to 1920
 ORDER BY dates.acad_year        ASC,
          dates.report_timestamp ASC;
BEGIN
-- dbms_output.enable(buffer_size => NULL);
--
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
utl_d_aa.truncate_table(v_table_name => 'pdb_retention_tableau');
FOR rec IN c_terms
LOOP
v_count := 0; -- reset count
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || rec.cohort_year || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
--============================================
-- END OF YEAR STUFF
--============================================
INSERT INTO utl_d_aa.pdb_retention_tableau
(cohort_year,
 return_year,
 campus,
 report_type,
 total_enrollment,
 total_graduated,
 total_ret,
 ret_percent,
 activity_date)
SELECT rec.cohort_year AS cohort_year,
       rec.return_year AS return_year,
       CASE
       WHEN elog.camp_code = 'R' THEN
        'Resident'
       WHEN elog.camp_code = 'D' THEN
        'LUO'
       END AS campus,
       'ADY' AS retention_type,
       COUNT(rlog.pidm) AS total_enrollment,
       SUM(rlog.graduated) AS total_graduated,
       SUM(rlog.returned) AS total_ret,
       CASE
       WHEN COUNT(rlog.pidm) - SUM(rlog.graduated) = 0 THEN
        0
       ELSE
        round(SUM(rlog.returned) / (COUNT(rlog.pidm) - SUM(rlog.graduated)), 4)
       END AS ret_percent,
       v_etl_date AS activity_date
  FROM utl_d_aa.retention_log rlog
  JOIN utl_d_aa.enrollments_log elog
    ON elog.acad_year = rlog.cohort_year
   AND elog.pidm = rlog.pidm
 WHERE rlog.cohort_year = rec.cohort_year
   AND rec.acad_end_date BETWEEN elog.from_date AND elog.to_date -- using acad_end_date for effective date to show as "unrevised" EOY numbers
   AND elog.yr_rank = 1 -- yr_rank pulls last term of enrollment once the academic year is complete
   AND rec.acad_end_date BETWEEN rlog.from_date AND rlog.to_date -- using acad_end_date for effective date to show as "unrevised" EOY numbers
   AND rec.acad_end_date < v_etl_date -- do not show rows until year is over 
   AND elog.semester <> 'WIN'
 GROUP BY CASE
          WHEN elog.camp_code = 'R' THEN
           'Resident'
          WHEN elog.camp_code = 'D' THEN
           'LUO'
          END;
v_insert_count := SQL%ROWCOUNT;
v_total_count  := v_total_count + v_insert_count; -- keep running total of rows processed
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'INSERT (EOY) - ' || rec.cohort_year || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_insert_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_insert_count);
--============================================
-- YEAR TO DATE STUFF
--============================================
INSERT INTO utl_d_aa.pdb_retention_tableau
(cohort_year,
 return_year,
 campus,
 report_type,
 total_enrollment,
 total_graduated,
 total_ret,
 ret_percent,
 activity_date)
SELECT rec.cohort_year AS cohort_year,
       rec.return_year AS return_year,
       CASE
       WHEN elog.camp_code = 'R' THEN
        'Resident'
       WHEN elog.camp_code = 'D' THEN
        'LUO'
       END AS cohort_campus,
       'YTD' AS retention_type,
       COUNT(rlog.pidm) AS total_enrollment,
       SUM(rlog.graduated) AS total_graduated,
       SUM(rlog.returned) AS total_ret,
       CASE
       WHEN COUNT(rlog.pidm) - SUM(rlog.graduated) = 0 THEN
        0
       ELSE
        round(SUM(rlog.returned) / (COUNT(rlog.pidm) - SUM(rlog.graduated)), 4)
       END AS ret_percent,
       v_etl_date AS activity_date
  FROM utl_d_aa.retention_log rlog
  JOIN utl_d_aa.enrollments_log elog
    ON elog.acad_year = rlog.cohort_year
   AND elog.pidm = rlog.pidm
 WHERE rlog.cohort_year = rec.cohort_year
   AND rec.report_timestamp BETWEEN elog.from_date AND elog.to_date -- using report_timestamp for effective date to show YTD numbers
   AND elog.yr_rank = 1 -- yr_rank pulls last term of enrollment once the academic year is complete
   AND rec.report_timestamp BETWEEN rlog.from_date AND rlog.to_date -- using report_timestamp for effective date to show YTD numbers
   AND elog.semester <> 'WIN'
 GROUP BY CASE
          WHEN elog.camp_code = 'R' THEN
           'Resident'
          WHEN elog.camp_code = 'D' THEN
           'LUO'
          END;
v_insert_count := SQL%ROWCOUNT;
v_total_count  := v_total_count + v_insert_count; -- keep running total of rows processed
dbms_lock.sleep(1); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'INSERT (YTD) - ' || rec.cohort_year || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_insert_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_insert_count);
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
RAISE;
END etl_aa_pdb_retention_tableau;

END load_aa_etl_pdb;
-- GRANT EXECUTE ON load_aa_etl_pdb TO utl_d_aim;
-- GRANT EXECUTE ON load_aa_etl_pdb TO utl_d_aa;
-- GRANT EXECUTE ON load_aa_etl_pdb TO utl_d_lms;
-- GRANT EXECUTE ON load_aa_etl_pdb TO utl_d_luo;
-- GRANT EXECUTE ON load_aa_etl_pdb TO wgriffith2;
-- GRANT EXECUTE ON load_aa_etl_pdb TO ZETL_JAMS_SVC;
