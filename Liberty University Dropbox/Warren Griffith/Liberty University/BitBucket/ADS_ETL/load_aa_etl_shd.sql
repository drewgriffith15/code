create or replace package load_aa_etl_shd is
procedure etl_aa_shd_retention_tableau(jobnumber number, processid varchar2, processname varchar2);
procedure etl_aa_shd_new_return_tableau(jobnumber number, processid varchar2, processname varchar2);
procedure etl_aa_shd_students_tableau(jobnumber number, processid varchar2, processname varchar2);
procedure etl_aa_shd_program_enrollment_tableau(jobnumber number, processid varchar2, processname varchar2);
procedure etl_aa_shd_gpa_tableau(jobnumber number, processid varchar2, processname varchar2);
procedure etl_aa_shd_courses_tableau(jobnumber number, processid varchar2, processname varchar2);
procedure etl_aa_shd_demographics_tableau(jobnumber   NUMBER, processid   VARCHAR2, processname VARCHAR2);
end load_aa_etl_shd;
/

create or replace package body load_aa_etl_shd is

PROCEDURE etl_aa_shd_demographics_tableau(jobnumber   NUMBER, processid   VARCHAR2, processname VARCHAR2) IS
-- =============================================================================
-- PURPOSE: Provides a curated staging dataset of student demographic and enrollment attributes to support the School Health Dashboard Tableau data source.
--
-- TARGET(S): UTL_D_AA.SHD_DEMOGRAPHICS_TABLEAU
--
-- UNIQUE KEY / INDEX: pidm, acad_year, term_code  -- (one row per student per academic year/term scope; rsb.yr_rank = 1 enforces single row per student per acad_year)
--
-- BUSINESS LOGIC & CONDITIONS:
-- - Establishes a window of relevant academic years/terms by selecting terms from zbtm.terms_by_group_v where group_code = 'STD' and the current date falls within a range from 180 days before a term start to two years after a term end. The latest term_code per academic year (fa_proc_year) is captured as max_term_code.
-- - Prefilters enrollment records (utl_d_aim.szrenrl aliased rsb) for:
--   - group_code <> 'ACD' (exclude academy students; include STD and MED terms only)
--   - yr_rank = 1 to obtain a single representative row per student per academic year
--   - acad_year limited to those academic years returned by the terms CTE
-- - Detects repeated course enrollments within a term (repeat_courses CTE) by counting occurrences of the same subj/numb per pidm and term_code; flags course_take_count > 1 as repeated course.
-- - Identifies students with an honors attendance code in saturn.sgrsatt (honr CTE), using the latest effective term not later than the maximum term_code from terms.
-- - Aggregates student athletic participation types (ath CTE) from utl_d_or.cohort_membership into boolean-like indicators for NCAA Athlete, Club Sports, and Intramurals per pidm and term.
-- - Main selection (commented-out block) enriches rsb records with lookups and translations:
--   - Joins to shrlgpa for attempted/earned hours and GPA context (gpa type 'I').
--   - Maps program/college via saturn.smrprle and saturn.stvcoll; program_group via utl_d_aim.progcolldept with fallback to program description.
--   - Pulls personal attributes from spbpers, stvmrtl (marital), stvrelg (religion), stvstat (state descriptor), stvnatn (nation code), and general.gobintl (international issuance).
--   - Pulls standardized test scores and high school GPA from utl_d_aa.* test score and stuhsgpa tables with versioning rules for SAT/ACT.
--   - Business value transformations:
--     - student_status derived from styp_code with explicit labels for 'Continuing', 'New', 'Transfer', 'Readmit', 'Student New to Program', 'Dual Enrolled', and 'Unknown'.
--     - CLASS produced by removing underscores and digits from rsb.classification.
--     - Age bucketed into: '<18', '18-22', '23-27', '28-34', '35-44', '45-60', '>60'.
--     - on_off_campus from rsb.housing; marital and religion default to 'Not Known' when null.
--     - cross_campus_students indicator set to 1 when both res_hours > 0 and luo_hours > 0, otherwise 0.
--     - international_student indicator is 1 when ipeds_visa = 'Nonresident_Alien', otherwise 0.
--     - repeated_course indicator uses presence of repeat_courses CTE match (nvl2(rc.pidm,1,0)).
--     - honors derived via honr CTE presence.
-- - Processing strategy: CTEs are MATERIALIZE-hinted to prefilter large source tables once per query plan (terms, rsb, repeat_courses) to reduce repeated reads across multiple joins.
-- - Note: In the supplied final SELECT block, the view currently returns only rsb.pidm while retaining the join scaffolding to support the richer commented projection; the commented projection shows intended full column set for the dashboard.
--
-- DEPENDENCIES:
-- - Source schemas/tables/views: utl_d_aim.szrenrl, utl_d_aim.szrcrse, zbtm.terms_by_group_v, saturn.sgrsatt, utl_d_or.cohort_membership, utl_d_aa.stutestscores, utl_d_aa.stuhsgpa, utl_d_aa.stuhsgpa (hs), utl_d_aa.stuhsgpa (if duplicated), utl_d_aim.progcolldept, general.gobintl, saturn.smrprle, saturn.stvcoll, saturn.stvstat, saturn.stvmrtl, saturn.stvrelg, saturn.stvterm, saturn.stvnatn, shrlgpa (alias g), spbpers, and any other tables referenced in commented section.
-- - Execution environment: Oracle Database (19c+ recommended to respect MATERIALIZE hint behavior). SQL*Plus/SQLcl can use the trailing slash to run.
-- - Consumer access: consumers require SELECT privilege on UTL_D_AA.SHD_DEMOGRAPHICS_TABLEAU. If consumers want an unqualified object name, they must have CREATE SYNONYM privilege in their schema to create a private synonym pointing to UTL_D_AA.SHD_DEMOGRAPHICS_TABLEAU.
--
-- CONSTRAINTS & RISKS:
-- - Performance risk: multiple large source tables are read/joined (szrenrl, szrcrse, saturn.*). Heavy concurrency or missing indexes on join keys (pidm, term_code, acad_year, prog_code) can cause slow query plans and high resource consumption.
-- - Materialize hints may increase temporary storage usage; plan choice depends on Oracle optimizer and statistics accuracy.
-- - The view owner must have SELECT privileges on all underlying objects (or use definer's rights with appropriate grants). Granting consumers SELECT on the view does not automatically grant them access to underlying base tables.
-- - Schema privileges to grant:
--   - To allow consumers to query the view, UTL_D_AA needs to GRANT SELECT ON UTL_D_AA.SHD_DEMOGRAPHICS_TABLEAU to each consuming user/role.
--   - Consumers do NOT need EXECUTE on the view (EXECUTE is for procedures/functions/packages). Only SELECT is required for views.
--   - If some consumers need to reference the view without schema prefix, they require CREATE SYNONYM in their schema (or a DB-level PUBLIC synonym granted by a DBA).
-- - Data completeness risk: use of latest-term logic and yr_rank = 1 may exclude multi-enrollment edge cases; ensure this matches business expectations for "one row per student per acad_year".
-- =============================================================================
--DECLARE 
v_etl_date    DATE := SYSDATE;
v_msg         VARCHAR2(2000);
v_instance    VARCHAR2(50) := upper('ALL'); -- inst from the jams job; used for determining instance
v_partition   NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_aa_shd_demographics_tableau';
BEGIN
-- dbms_output.enable(buffer_size => NULL);
--
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
utl_d_aa.truncate_table(v_table_name => 'shd_demographics_tableau');
v_count   := 0; -- reset count
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
INSERT INTO utl_d_aa.shd_demographics_tableau
(pidm,
 aidy_code,
 lu_id,
 term_code,
 campus,
 levl_code,
 degree_code,
 program,
 gender,
 total_credits,
 cumulative_credits,
 enrollment_status,
 student_status,
 CLASS,
 state,
 zip_code,
 country,
 college,
 program_description,
 race,
 program_group,
 minor,
 age,
 age_group,
 on_off_campus,
 sat_score,
 act_score,
 lsat_score,
 high_school_gpa,
 hours_attempted,
 hours_earned,
 cum_hours,
 transfer_hours,
 cross_campus_students,
 marital_status,
 religion,
 gpa,
 military,
 honors,
 transferred_out,
 transferred_to,
 international_student,
 nation_issued,
 ncaa_athlete,
 club_sports,
 intramurals,
 rnk_desc,
 lu_email,
 lu_student_lname,
 lu_student_fname,
 repeated_course,
 activity_date)
WITH terms AS
 (SELECT /*+ MATERIALIZE */
   t.fa_proc_year AS aidy_code,
   MAX(term_code) AS max_term_code
    FROM zbtm.terms_by_group_v t
   WHERE t.group_code IN ('STD')
     AND SYSDATE >= t.start_date - 180 -- anything upcoming
     AND SYSDATE <= t.end_date + (365 * 2)
   GROUP BY fa_proc_year),
-- Prefilter SZRENRL once per AIDY to avoid re-reading the large table per-join
rsb AS
 (SELECT /*+ MATERIALIZE */
   rsb.pidm,
   rsb.acad_year,
   rsb.luid,
   rsb.term_code,
   rsb.camp_code,
   rsb.levl_code,
   rsb.prog_code_1,
   rsb.gender,
   rsb.term_hours,
   rsb.cum_hours_asof_term,
   rsb.status,
   rsb.styp_code,
   rsb.degc_code_1,
   rsb.classification,
   rsb.state,
   rsb.zip5,
   rsb.nation,
   rsb.coll_desc_1,
   rsb.ipeds_ethn,
   rsb.minr_1,
   rsb.age,
   rsb.housing,
   rsb.gpa_asof_term,
   rsb.milt_status,
   rsb.cum_hours,
   rsb.tran_hours,
   rsb.res_hours,
   rsb.luo_hours,
   rsb.ipeds_visa,
   rsb.yr_rank,
   rsb.lu_email,
   rsb.last_name,
   rsb.first_name
    FROM utl_d_aim.szrenrl rsb
   WHERE rsb.group_code <> 'ACD' -- remove academy students, returning STD and MED terms only
     AND rsb.yr_rank = 1 -- getting one row per student per acad year
     AND rsb.acad_year IN (SELECT aidy_code FROM terms)),
repeat_courses AS
 (SELECT /*+ MATERIALIZE */
  DISTINCT pidm,
           term_code
    FROM (SELECT z.pidm,
                 z.term_code,
                 z.subj,
                 z.numb,
                 COUNT(*) over(PARTITION BY z.pidm, z.term_code, nvl(z.subj, ' '), nvl(z.numb, ' ')) AS course_take_count
            FROM utl_d_aim.szrcrse z
           WHERE z.acad_year IN (SELECT aidy_code FROM terms))
   WHERE course_take_count > 1),
honr AS
 (SELECT honr.sgrsatt_pidm AS pidm
    FROM saturn.sgrsatt honr
   WHERE honr.sgrsatt_atts_code = 'HONR'
     AND honr.sgrsatt_term_code_eff = (SELECT MAX(sgrsatt1.sgrsatt_term_code_eff)
                                         FROM saturn.sgrsatt sgrsatt1
                                        WHERE sgrsatt1.sgrsatt_pidm = honr.sgrsatt_pidm
                                          AND sgrsatt1.sgrsatt_term_code_eff <= (SELECT MAX(max_term_code) FROM terms))),
ath AS
 (SELECT ath.engage_pidm AS pidm,
         ath.engage_term AS term_code,
         MAX(CASE
             WHEN ath.engage_type = 'NCAA Athlete' THEN
              ath.engage_pidm
             ELSE
              NULL
             END) AS ncaa_athlete,
         MAX(CASE
             WHEN ath.engage_type = 'Club Sports' THEN
              ath.engage_pidm
             ELSE
              NULL
             END) AS club_sports,
         MAX(CASE
             WHEN ath.engage_type = 'Intramurals' THEN
              ath.engage_pidm
             ELSE
              NULL
             END) AS intramurals
    FROM utl_d_or.cohort_membership ath
   WHERE ath.engage_type IN ('Club Sports', 'NCAA Athlete', 'Intramurals')
   GROUP BY ath.engage_pidm,
            ath.engage_term)
SELECT rsb.pidm AS pidm,
       rsb.acad_year AS acad_year,
       rsb.luid AS lu_id,
       rsb.term_code AS term_code,
       rsb.camp_code AS campus,
       rsb.levl_code AS levl_code,
       smrprle.smrprle_degc_code AS degree_code,
       rsb.prog_code_1 AS program,
       nvl(rsb.gender, 'Unknown') AS gender,
       rsb.term_hours AS total_credits,
       rsb.cum_hours_asof_term AS cumulative_credits,
       rsb.status AS enrollment_status,
       CASE
       WHEN rsb.styp_code = 'C' THEN
        'Continuing Student'
       WHEN rsb.styp_code = 'N' THEN
        'New Student'
       WHEN rsb.styp_code = 'T' THEN
        'Transfer Student'
       WHEN rsb.styp_code = 'R' THEN
        'Readmit Student'
       WHEN rsb.styp_code = 'M' THEN
        'Student New to Program'
       WHEN rsb.degc_code_1 = 'DPL' THEN
        'Dual Enrolled'
       ELSE
        'Unknown'
       END AS student_status,
       regexp_replace(REPLACE(rsb.classification, '_', NULL), '[0-9]', NULL) AS CLASS,
       stvstat.stvstat_desc AS state,
       rsb.zip5 AS zip_code,
       rsb.nation AS country,
       rsb.coll_desc_1 AS college,
       smrprle.smrprle_program_desc AS program_description,
       REPLACE(rsb.ipeds_ethn, '_', ' ') AS race,
       nvl(pcd.majr_degc_group, smrprle.smrprle_program_desc) AS program_group,
       rsb.minr_1 AS minor,
       rsb.age AS age,
       CASE
       WHEN rsb.age BETWEEN 18 AND 22 THEN
        '18-22'
       WHEN rsb.age BETWEEN 23 AND 27 THEN
        '23-27'
       WHEN rsb.age BETWEEN 28 AND 34 THEN
        '28-34'
       WHEN rsb.age BETWEEN 35 AND 44 THEN
        '35-44'
       WHEN rsb.age BETWEEN 45 AND 60 THEN
        '45-60'
       WHEN rsb.age < 18 THEN
        '<18'
       WHEN rsb.age > 60 THEN
        '>60'
       END AS age_group,
       rsb.housing AS on_off_campus,
       nvl(satc1.test_score, satc2.test_score) AS sat_score,
       actc1.test_score AS act_score,
       lsat.test_score AS lsat_score,
       hs.hs_gpa AS high_school_gpa,
       g.shrlgpa_hours_attempted AS hours_attempted,
       g.shrlgpa_hours_earned AS hours_earned,
       rsb.cum_hours AS cum_hours,
       rsb.tran_hours AS transfer_hours,
       CASE
       WHEN rsb.res_hours > 0
            AND rsb.luo_hours > 0 THEN
        1
       ELSE
        0
       END AS cross_campus_students,
       nvl(stvmrtl.stvmrtl_desc, 'Not Known') AS marital_status,
       nvl(stvrelg.stvrelg_desc, 'Not Known') AS religion,
       rsb.gpa_asof_term AS gpa,
       nvl(substr(rsb.milt_status, 3), 'No Affiliation') AS military,
       honr.pidm AS honors,
       NULL AS transferred_out,
       NULL AS transferred_to,
       CASE
       WHEN rsb.ipeds_visa = 'Nonresident_Alien' THEN
        1
       ELSE
        0
       END AS international_student,
       stvnatn.stvnatn_nation AS nation_issued,
       ath.ncaa_athlete,
       ath.club_sports,
       ath.intramurals,
       rsb.yr_rank AS rnk_desc,
       rsb.lu_email AS lu_email,
       rsb.last_name AS lu_student_lname,
       rsb.first_name AS lu_student_fname,
       nvl2(rc.pidm, 1, 0) AS repeated_course,
       SYSDATE AS activity_date
  FROM rsb
  LEFT JOIN repeat_courses rc
    ON rc.pidm = rsb.pidm
   AND rc.term_code = rsb.term_code
  LEFT JOIN shrlgpa g
    ON g.shrlgpa_pidm = rsb.pidm
   AND g.shrlgpa_levl_code = rsb.levl_code
   AND g.shrlgpa_gpa_type_ind = 'I'
  LEFT JOIN saturn.smrprle smrprle
    ON smrprle.smrprle_program = rsb.prog_code_1
  LEFT JOIN saturn.stvcoll stvcoll
    ON smrprle.smrprle_coll_code = stvcoll.stvcoll_code
  LEFT JOIN utl_d_aim.progcolldept pcd
    ON pcd.prog_code = rsb.prog_code_1
  LEFT JOIN spbpers
    ON spbpers_pidm = rsb.pidm
  LEFT JOIN stvmrtl
    ON stvmrtl_code = spbpers_mrtl_code
  LEFT JOIN stvrelg
    ON stvrelg_code = spbpers_relg_code
  LEFT JOIN stvstat
    ON stvstat_code = rsb.state
  LEFT JOIN honr
    ON honr.pidm = rsb.pidm
  LEFT JOIN ath
    ON ath.pidm = rsb.pidm
   AND ath.term_code = rsb.term_code
  LEFT JOIN utl_d_aa.stutestscores satc1
    ON satc1.pidm = rsb.pidm
   AND satc1.test_desc = 'SAT Composite'
   AND satc1.version_number = 1
  LEFT JOIN utl_d_aa.stutestscores satc2
    ON satc2.pidm = rsb.pidm
   AND satc2.test_desc = 'SAT Composite'
   AND satc2.version_number = 2
  LEFT JOIN utl_d_aa.stutestscores actc1
    ON actc1.pidm = rsb.pidm
   AND actc1.test_desc = 'ACT Composite'
   AND actc1.version_number = 1
  LEFT JOIN utl_d_aa.stutestscores lsat
    ON lsat.pidm = rsb.pidm
   AND lsat.test_desc = 'LSAT'
   AND lsat.version_number = 1
  LEFT JOIN utl_d_aa.stuhsgpa hs
    ON hs.pidm = rsb.pidm
  LEFT JOIN stvterm
    ON stvterm_code = rsb.term_code
  LEFT JOIN general.gobintl
    ON gobintl.gobintl_pidm = rsb.pidm
  LEFT JOIN saturn.stvnatn
    ON stvnatn.stvnatn_code = gobintl.gobintl_natn_code_issue;
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
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
END etl_aa_shd_demographics_tableau;

procedure etl_aa_shd_gpa_tableau(jobnumber number, processid varchar2, processname varchar2) is
/*
Table: shd_program_gpa_tableau

Primary Keys: NONE

Unique index: NONE

Purpose:
- Staging data for the SHD that is used by the Provost Office. 

Conditions: 
-- - data should not show until the year is over
-- - hours must be > 0
-- - returning one row per academic year; show data associated with the last semester enrolled of the year
-- - student must be university level and in a program that has awardable credit; includes special students
-- - Current average GPA - (cumulative GPA as of report runtime); 
-- - Report timing could cause drastic differences: If the we run anything during the semester, the only completions that we see are ones that are severely negative (equals 0 GPA)
 
--       SITE: ACADEMICS 
--   WORKBOOK: Program Enrollment Numbers
--DATA SOURCE: shd_gpa_tableau
-- URL: https://reports.liberty.edu/#/site/Academics/views/ProgramEnrollmentNumbers/GPAByAcademicYear?:iid=1

*/
--DECLARE
--PARAMS
v_etl_date DATE := SYSDATE;
v_msg      VARCHAR2(2000);
v_instance VARCHAR2(50) := upper('ALL'); -- inst from the jams job; used for determining instance
v_partition NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
-- v_mod         NUMBER := 5; -- number of partitions to be created
-- --v_cpu         NUMBER := 4; -- number of CPUs used for parallelization - do not exceed 20 CPUs [v_mod x --v_cpu] if running simultaneously
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_aa_shd_gpa_tableau';
CURSOR c_terms IS
SELECT MIN(enrl.acad_year) AS min_aidy_code,
       MAX(enrl.acad_year) AS max_aidy_code,
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
       WHEN enrl.levl_code IN ('DR', 'JD', 'MD') THEN
        'DR'
       ELSE
        enrl.levl_code
       END
 WHERE enrl.coll_desc_1 NOT IN ('English Language Institute')
   AND enrl.levl_code NOT IN ('CT')
 GROUP BY enrl.coll_desc_1,
          enrl.camp_code
UNION ALL
SELECT MIN(enrl.acad_year) AS min_aidy_code,
       MAX(enrl.acad_year) AS max_aidy_code,
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
       WHEN enrl.levl_code IN ('DR', 'JD', 'MD') THEN
        'DR'
       ELSE
        enrl.levl_code
       END
 WHERE enrl.coll_desc_1 NOT IN ('English Language Institute')
   AND enrl.levl_code NOT IN ('CT')
 GROUP BY enrl.coll_desc_1
UNION ALL
SELECT MIN(enrl.acad_year) AS min_aidy_code,
       MAX(enrl.acad_year) AS max_aidy_code,
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
       WHEN enrl.levl_code IN ('DR', 'JD', 'MD') THEN
        'DR'
       ELSE
        enrl.levl_code
       END
 WHERE enrl.coll_desc_1 NOT IN ('English Language Institute')
   AND enrl.levl_code NOT IN ('CT')
 GROUP BY enrl.camp_code
UNION ALL
SELECT MIN(enrl.acad_year) AS min_aidy_code,
       MAX(enrl.acad_year) AS max_aidy_code,
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
       WHEN enrl.levl_code IN ('DR', 'JD', 'MD') THEN
        'DR'
       ELSE
        enrl.levl_code
       END
 WHERE enrl.coll_desc_1 NOT IN ('English Language Institute')
   AND enrl.levl_code NOT IN ('CT')
UNION ALL
SELECT MIN(enrl.acad_year) AS min_aidy_code,
       MAX(enrl.acad_year) AS max_aidy_code,
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
       WHEN enrl.levl_code IN ('DR', 'JD', 'MD') THEN
        'DR'
       ELSE
        enrl.levl_code
       END
 WHERE enrl.coll_desc_1 NOT IN ('English Language Institute')
   AND enrl.levl_code NOT IN ('CT')
 GROUP BY stvlevl_desc,
          enrl.camp_code
UNION ALL
SELECT MIN(enrl.acad_year) AS min_aidy_code,
       MAX(enrl.acad_year) AS max_aidy_code,
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
       WHEN enrl.levl_code IN ('DR', 'JD', 'MD') THEN
        'DR'
       ELSE
        enrl.levl_code
       END
 WHERE enrl.coll_desc_1 NOT IN ('English Language Institute')
   AND enrl.levl_code NOT IN ('CT')
 GROUP BY stvlevl_desc
UNION ALL
SELECT MIN(enrl.acad_year) AS min_aidy_code,
       MAX(enrl.acad_year) AS max_aidy_code,
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
       WHEN enrl.levl_code IN ('DR', 'JD', 'MD') THEN
        'DR'
       ELSE
        enrl.levl_code
       END
 WHERE enrl.coll_desc_1 NOT IN ('English Language Institute')
   AND enrl.levl_code NOT IN ('CT')
 GROUP BY enrl.camp_code
UNION ALL
SELECT MIN(enrl.acad_year) AS min_aidy_code,
       MAX(enrl.acad_year) AS max_aidy_code,
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
       WHEN enrl.levl_code IN ('DR', 'JD', 'MD') THEN
        'DR'
       ELSE
        enrl.levl_code
       END
 WHERE enrl.coll_desc_1 NOT IN ('English Language Institute')
   AND enrl.levl_code NOT IN ('CT')
UNION ALL
SELECT MIN(enrl.acad_year) AS min_aidy_code,
       MAX(enrl.acad_year) AS max_aidy_code,
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
       WHEN enrl.levl_code IN ('DR', 'JD', 'MD') THEN
        'DR'
       ELSE
        enrl.levl_code
       END
 WHERE enrl.coll_desc_1 NOT IN ('English Language Institute')
   AND enrl.levl_code NOT IN ('CT')
 GROUP BY stvmajr_desc,
          enrl.camp_code
UNION ALL
SELECT MIN(enrl.acad_year) AS min_aidy_code,
       MAX(enrl.acad_year) AS max_aidy_code,
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
       WHEN enrl.levl_code IN ('DR', 'JD', 'MD') THEN
        'DR'
       ELSE
        enrl.levl_code
       END
 WHERE enrl.coll_desc_1 NOT IN ('English Language Institute')
   AND enrl.levl_code NOT IN ('CT')
 GROUP BY stvmajr_desc
UNION ALL
SELECT MIN(enrl.acad_year) AS min_aidy_code,
       MAX(enrl.acad_year) AS max_aidy_code,
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
       WHEN enrl.levl_code IN ('DR', 'JD', 'MD') THEN
        'DR'
       ELSE
        enrl.levl_code
       END
 WHERE enrl.coll_desc_1 NOT IN ('English Language Institute')
   AND enrl.levl_code NOT IN ('CT')
 GROUP BY enrl.camp_code
UNION ALL
SELECT MIN(enrl.acad_year) AS min_aidy_code,
       MAX(enrl.acad_year) AS max_aidy_code,
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
       WHEN enrl.levl_code IN ('DR', 'JD', 'MD') THEN
        'DR'
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
utl_d_aa.truncate_table(v_table_name => 'shd_gpa_tableau');
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
INSERT INTO utl_d_aa.shd_gpa_tableau
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
           AND enrl.term_hours > 0 -- must have hours
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
INSERT INTO utl_d_aa.shd_gpa_tableau
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
INSERT INTO utl_d_aa.shd_gpa_tableau
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
INSERT INTO utl_d_aa.shd_gpa_tableau
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
---     07-30-2025  MAPEELE     --Updated level grouping to break out GR/DR
---     10-02-2025  WGRIFFITH2     --no longer shows current aidy, because the numbers are not completed yet
------------------------------------------------------------------------------------------------*/
END etl_aa_shd_gpa_tableau;

procedure etl_aa_shd_program_enrollment_tableau(jobnumber number, processid varchar2, processname varchar2) is
/*
Table: shd_students_tableau

Primary Keys: NONE

Unique index: NONE

Purpose:
- Staging data for the SHD that is used by the Provost Office. 

Conditions: 
-- - returning one row per academic year; show data associated with the last semester enrolled
-- - student must be university level and in a program that has awardable credit
 
--       SITE: ACADEMICS 
--   WORKBOOK: Program Enrollment by Term
--DATA SOURCE: Program Enrollment by Term 
-- URL: https://reports.liberty.edu/#/site/Academics/views/ProgramEnrollmentNumbers/ProgramEnrollmentNumbers?:iid=1

*/
--DECLARE
--- PARAMS
v_etl_date DATE := SYSDATE;
v_msg      VARCHAR2(2000);
v_instance VARCHAR2(50) := upper('ALL'); -- inst from the jams job; used for determining instance
v_partition NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
-- v_mod         NUMBER := 5; -- number of partitions to be created
-- --v_cpu         NUMBER := 4; -- number of CPUs used for parallelization - do not exceed 20 CPUs [v_mod x --v_cpu] if running simultaneously
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_aa_shd_program_enrollment_tableau';
BEGIN
-- dbms_output.enable(buffer_size => NULL);
--
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
utl_d_aa.truncate_table(v_table_name => 'shd_program_enrollment_tableau');
INSERT 
INTO utl_d_aa.shd_program_enrollment_tableau
(aidy_code,
 term,
 semester,
 levl_code,
 degc,
 camp,
 college,
 department,
 majr_code,
 major_description,
 program,
 program_description,
 pidm,
 seats,
 hours,
 state,
 tc_tl,
 all_placeholder)
SELECT enrl.acad_year,
       enrl.term_code term,
       CASE
       WHEN terms.group_code IN ('MED', 'ACD') THEN
        'Year'
       ELSE
        terms.semester_desc
       END AS semester,
       enrl.levl_code,
       enrl.degc_code_1 degc,
       enrl.camp_code camp,
       enrl.coll_desc_1 college,
       enrl.dept_desc_1 department,
       enrl.majr_code_1 majr_code,
       enrl.majr_desc_1 major_description,
       enrl.prog_code_1 program,
       prl.szvprle_web_display_degc AS program_description,
       COUNT(enrl.pidm) AS pidm,
       SUM(enrl.term_seats) AS seats, -- not shown in dashboard
       SUM(enrl.term_hours) AS hours, -- not shown in dashboard
       enrl.state,
       CASE
       WHEN enrl.majr_desc_1 LIKE '%(TL)%' THEN
        1
       WHEN enrl.majr_desc_1 LIKE '%(TC)%' THEN
        1
       WHEN enrl.coll_desc_1 = 'School of Education' THEN
        1
       ELSE
        2
       END tc_tl,
       'All' AS all_placeholder
  FROM utl_d_aim.szrenrl enrl
  JOIN zsaturn.szrlevl l
    ON l.szrlevl_levl_code = enrl.levl_code
   AND szrlevl_is_univ = 'Y'
   AND szrlevl_has_awardable_cred = 'Y'
  JOIN zbtm.terms_by_group_v terms
    ON terms.term_code = enrl.term_code
  LEFT JOIN zexec.szvprle prl
    ON prl.szvprle_program = prog_code_1
 WHERE enrl.term_code >= '200840'
 GROUP BY enrl.acad_year,
          enrl.term_code,
          CASE
          WHEN terms.group_code IN ('MED', 'ACD') THEN
           'Year'
          ELSE
           terms.semester_desc
          END,
          enrl.levl_code,
          enrl.degc_code_1,
          enrl.camp_code,
          enrl.coll_desc_1,
          enrl.dept_desc_1,
          enrl.majr_code_1,
          enrl.majr_desc_1,
          enrl.prog_code_1,
          prl.szvprle_web_display_degc,
          enrl.state,
          CASE
          WHEN enrl.majr_desc_1 LIKE '%(TL)%' THEN
           1
          WHEN enrl.majr_desc_1 LIKE '%(TC)%' THEN
           1
          WHEN enrl.coll_desc_1 = 'School of Education' THEN
           1
          ELSE
           2
          END;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'TRUNCATE/INSERT - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
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
VERSION DATE        USERNAME    UPDATES
---     01-27-2025  WGRIFFITH2  --Initial release 
------------------------------------------------------------------------------------------------*/
END etl_aa_shd_program_enrollment_tableau;

procedure etl_aa_shd_students_tableau(jobnumber number, processid varchar2, processname varchar2) is
/*
Table: shd_students_tableau

Primary Keys: NONE

Unique index: NONE

Purpose:
- Staging data for the SHD that is used by the Provost Office. 

Conditions: 
-- - hours must be > 0
-- - returning one row per academic year; show data associated with the last semester enrolled
-- - student must be university level and in a program that has awardable credit

*/
--DECLARE
--- PARAMS
v_etl_date DATE := SYSDATE;
v_msg      VARCHAR2(2000);
v_instance VARCHAR2(50) := upper('ALL'); -- inst from the jams job; used for determining instance
v_partition NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
-- v_mod         NUMBER := 5; -- number of partitions to be created
-- --v_cpu         NUMBER := 4; -- number of CPUs used for parallelization - do not exceed 20 CPUs [v_mod x --v_cpu] if running simultaneously
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_aa_shd_students_tableau';
CURSOR c_terms IS
SELECT t.fa_proc_year AS aidy_code,
       MIN(t.term_code) min_cohort_term_code,
       MAX(t.term_code) max_cohort_term_code
  FROM zbtm.terms_by_group_v t
 WHERE to_date('06/30/20' || substr(t.fa_proc_year, 3, 2), 'mm/dd/yyyy') > SYSDATE - (365 * 16)
   AND to_date('07/01/20' || substr(t.fa_proc_year, 1, 2), 'mm/dd/yyyy') < SYSDATE + (365 * 5) -- need to look to the future for refreshing forecasts
   AND t.semester NOT IN ('WIN')
   AND t.group_code IN ('STD')
 GROUP BY t.fa_proc_year
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
FOR rec IN c_terms
LOOP
v_count   := 0; -- reset count
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || rec.aidy_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
DELETE 
FROM utl_d_aa.shd_students_tableau tgt
 WHERE 1 = 1
   AND tgt.aidy_code = rec.aidy_code;
-- DO NOT COMMIT HERE
INSERT 
INTO utl_d_aa.shd_students_tableau
(students,
 aidy_code,
 credits,
 seats, 
 previous_students,
 college,
 college_code,
 camp_code,
 levl_code,
 program_group,
 projected_enrollment,
 projected_credits,
 period,
 activity_date,
 chair_usernames,
 ad_usernames,
 dean_usernames,
 director_usernames,
 fsc_usernames,
 admin_usernames)
SELECT students,
       aidy_code,
       credits,
       seats, 
       previous_students,
       college,
       src.college_code,
       camp_code,
       levl_code,
       program_group,
       projected_enrollment,
       projected_credits,
       period,
       v_etl_date AS activity_date,
       chair_usernames,
       ad_usernames,
       dean_usernames,
       director_usernames,
       fsc_usernames,
       admin_usernames
  FROM (SELECT COUNT(zz.students) students,
               zz.aidy_code,
               SUM(zz.credits) AS credits,
               SUM(zz.seats) AS seats, 
               zz.previous_students,
               zz.college,
               zz.college_code,
               zz.camp_code,
               zz.levl_code,
               zz.program_group,
               NULL AS projected_enrollment,
               NULL AS projected_credits,
               'Actual' AS period
          FROM (SELECT rsb.pidm        students,
                       rsb.term_code   term,
                       rsb.acad_year   aidy_code,
                       rsb.prog_code_1 program,
                       rsb.term_hours  credits, 
                       rsb.term_seats seats,
                       previous_year.students previous_students,
                       rsb.coll_desc_1 college,
                       smrprle.smrprle_coll_code college_code,
                       smrprle.smrprle_program_desc program_desc,
                       rsb.camp_code camp_code,
                       rsb.levl_code levl_code,
                       nvl(pcd.majr_degc_group, smrprle.smrprle_program_desc) program_group
                  FROM utl_d_aim.szrenrl rsb
                  LEFT JOIN saturn.smrprle
                    ON smrprle.smrprle_program = rsb.prog_code_1
                  LEFT JOIN utl_d_aim.progcolldept pcd
                    ON pcd.prog_code = rsb.prog_code_1
                  LEFT JOIN (SELECT COUNT(DISTINCT py.students) students,
                                   py.report_year report_year,
                                   py.program_group,
                                   py.camp_code,
                                   py.levl,
                                   py.college
                              FROM (SELECT rsb2.pidm students,
                                           rsb2.term_code term_code,
                                           rsb2.acad_year report_year,
                                           rsb2.camp_code camp_code,
                                           smrprle2.smrprle_coll_code college,
                                           rsb2.levl_code levl,
                                           nvl(pcd2.majr_degc_group, smrprle2.smrprle_program_desc) program_group
                                      FROM utl_d_aim.szrenrl rsb2
                                      LEFT JOIN saturn.smrprle smrprle2
                                        ON smrprle2.smrprle_program = rsb2.prog_code_1
                                      LEFT JOIN utl_d_aim.progcolldept pcd2
                                        ON pcd2.prog_code = rsb2.prog_code_1
                                     WHERE rsb2.group_code <> 'ACD'
                                       AND rsb2.term_hours > 0
                                       AND rsb2.acad_year = rec.aidy_code - 101) py
                             GROUP BY py.report_year,
                                      py.program_group,
                                      py.camp_code,
                                      py.levl,
                                      py.college) previous_year
                    ON previous_year.program_group = nvl(pcd.majr_degc_group, smrprle.smrprle_program_desc)
                   AND previous_year.camp_code = rsb.camp_code
                   AND previous_year.college = smrprle.smrprle_coll_code
                   AND previous_year.levl = rsb.levl_code
                 WHERE rsb.group_code <> 'ACD'
                   AND rsb.acad_year = rec.aidy_code) zz
         GROUP BY zz.aidy_code,
                  zz.previous_students,
                  zz.college,
                  zz.college_code, 
                  zz.camp_code,
                  zz.levl_code,
                  zz.program_group
        UNION
        SELECT NULL          students,
               rec.aidy_code report_year,
               NULL          credits,
               NULL          seats, 
               NULL previous_students,
               stvcoll.stvcoll_desc college,
               stvcoll.stvcoll_code college_code,
               hours.group2 camp_code,
               smrprle.smrprle_levl_code levl_code,
               pcd.majr_degc_group program_group,
               SUM(enrl.total) enrl_model,
               SUM(hours.total) projected_credits,
               'Projected' AS period
          FROM utl_d_aa.stufcstaidyhours hours
        -- this join is only to remove NULLS
          JOIN (SELECT DISTINCT hist.group1,
                               hist.group2
                 FROM utl_d_aa.stupaceaidyep hist
                 JOIN utl_d_aa.stuhist_stg stg
                   ON stg.aidy_code = hist.aidy_code
                  AND (stg.current_year = 'Y' OR stg.previous_year = 'Y')) hist
            ON hours.group1 = hist.group1
           AND hours.group2 = hist.group2
           AND hours.aidy_code = rec.aidy_code
          LEFT JOIN utl_d_aa.stufcstaidyseats seats
            ON seats.group1 = hours.group1
           AND seats.group2 = hours.group2
           AND seats.aidy_code = hours.aidy_code
          LEFT JOIN utl_d_aa.stufcstaidyenrl enrl
            ON enrl.group1 = hours.group1
           AND enrl.group2 = hours.group2
           AND enrl.aidy_code = hours.aidy_code
          LEFT JOIN utl_d_aim.progcolldept pcd
            ON pcd.prog_code = hours.group1
          LEFT JOIN smrprle smrprle
            ON smrprle.smrprle_program = hours.group1
          LEFT JOIN stvcoll stvcoll
            ON stvcoll.stvcoll_code = smrprle.smrprle_coll_code
         WHERE hours.grouping1 = 'Program'
         GROUP BY hours.aidy_code,
                  stvcoll.stvcoll_desc,
                  stvcoll.stvcoll_code,
                  hours.group2,
                  smrprle.smrprle_levl_code,
                  pcd.majr_degc_group) src
-- get the FHT data for row level security; there is no join on camp_code here
  LEFT JOIN utl_d_aa.secfhtcoll fhtc
    ON fhtc.college_code = src.college_code;
v_count := SQL%ROWCOUNT;
IF v_count > 0 THEN
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'DELETE/INSERT - ' || rec.aidy_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
ELSE
ROLLBACK;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'DELETE/INSERT - ' || rec.aidy_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
END IF;
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
VERSION DATE        USERNAME    UPDATES
---     10-18-2024  WGRIFFITH2  --Initial release 
------------------------------------------------------------------------------------------------*/
END etl_aa_shd_students_tableau;

procedure etl_aa_shd_new_return_tableau(jobnumber number, processid varchar2, processname varchar2) is
/*
Table: shd_new_return_tableau

Primary Keys: NONE

Unique index: NONE

Purpose:
- Staging data for the SHD that is used by the Provost Office. 

Conditions: 
-- - hours must be > 0
-- - returning one row per academic year; show data associated with the last semester enrolled
-- - student must be university level and in a program that has awardable credit

*/
-- DECLARE
--- PARAMS
v_etl_date DATE := SYSDATE;
v_msg      VARCHAR2(2000);
v_instance VARCHAR2(50) := upper('ALL'); -- inst from the jams job; used for determining instance
v_partition NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
-- v_mod         NUMBER := 5; -- number of partitions to be created
--v_cpu         NUMBER := 4; -- number of CPUs used for parallelization - do not exceed 20 CPUs [v_mod x --v_cpu] if running simultaneously
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_aa_shd_new_return_tableau';
CURSOR c_terms IS
SELECT t.fa_proc_year AS aidy_code,
       MIN(t.term_code) min_cohort_term_code,
       MAX(t.term_code) max_cohort_term_code
  FROM zbtm.terms_by_group_v t
 WHERE to_date('06/30/20' || substr(t.fa_proc_year, 3, 2), 'mm/dd/yyyy') > SYSDATE - (365 * 5)
   AND to_date('07/01/20' || substr(t.fa_proc_year, 1, 2), 'mm/dd/yyyy') < SYSDATE + (365 * 1)
   AND t.semester NOT IN ('WIN')
   AND t.group_code IN ('STD')
 GROUP BY t.fa_proc_year
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
-- remove older years during the first week of july; only keep the last 5 years in the dashboard
IF to_char(SYSDATE, 'MM') = '07'
   AND to_number(to_char(SYSDATE, 'DD')) BETWEEN 1 AND 7 THEN
DELETE FROM utl_d_aa.shd_new_return_tableau tgt
 WHERE tgt.aidy < (SELECT MIN(t.fa_proc_year)
                     FROM zbtm.terms_by_group_v t
                    WHERE to_date('06/30/20' || substr(t.fa_proc_year, 3, 2), 'mm/dd/yyyy') > SYSDATE - (365 * 5)
                      AND t.group_code IN ('STD'));
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'DELETE (< 5 years) - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
END IF;
FOR rec IN c_terms
LOOP
v_count   := 0; -- reset count
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || rec.aidy_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
DELETE FROM utl_d_aa.shd_new_return_tableau tgt
 WHERE 1 = 1
   AND tgt.aidy = rec.aidy_code;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'DELETE - ' || rec.aidy_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
INSERT INTO utl_d_aa.shd_new_return_tableau
(cnt,
 levl,
 aidy,
 camp,
 stutype,
 college,
 activity_date,
 chair_usernames,
 ad_usernames,
 dean_usernames,
 director_usernames,
 fsc_usernames,
 admin_usernames)
SELECT cnt,
       levl,
       aidy,
       camp,
       stutype,
       college,
       v_etl_date,
       chair_usernames,
       ad_usernames,
       dean_usernames,
       director_usernames,
       fsc_usernames,
       admin_usernames
  FROM (SELECT COUNT(cy.pidm) cnt,
               cy.levl,
               cy.aidy,
               cy.camp,
               CASE
               WHEN reg_last_yr IS NULL THEN
                'New' -- LUO student definition for not reg last year
               ELSE
                'Returning'
               END stutype,
               college,
               coll_code
          FROM (SELECT szrenrl.pidm AS pidm,
                       szrenrl.acad_year AS aidy,
                       stvlevl_desc AS levl,
                       szrenrl.camp_code AS camp,
                       (SELECT DISTINCT 'Returning'
                          FROM utl_d_aim.szrenrl e2
                         WHERE e2.pidm = szrenrl.pidm
                           AND e2.acad_year = rec.aidy_code - 101
                           AND e2.term_hours > 0
                           AND e2.yr_rank = 1) AS reg_last_yr,
                       szrenrl.coll_desc_1 AS college,
                       smrprle_coll_code AS coll_code
                  FROM utl_d_aim.szrenrl szrenrl
                  LEFT JOIN smrprle
                    ON smrprle_program = szrenrl.prog_code_1
                  LEFT JOIN stvlevl
                    ON stvlevl_code = szrenrl.levl_code
                 WHERE szrenrl.group_code <> 'ACD'
                   AND szrenrl.term_hours > 0
                   AND szrenrl.yr_rank = 1
                   AND szrenrl.acad_year = rec.aidy_code) cy
         GROUP BY cy.levl,
                  cy.aidy,
                  cy.camp,
                  CASE
                  WHEN reg_last_yr IS NULL THEN
                   'New' -- LUO student not reg last year
                  ELSE
                   'Returning'
                  END,
                  college,
                  coll_code) src
-- get the FHT data for row level security; there is no join on camp_code here
  LEFT JOIN utl_d_aa.secfhtcoll fhtc
    ON fhtc.college_code = src.coll_code;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || rec.aidy_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
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
VERSION DATE        USERNAME    UPDATES
---     10-18-2024  WGRIFFITH2  --Initial release 
-- 20251211 - WGRIFFITH2 - Mitigated ORA-12839 by adding commit boundaries after DELETEs and documenting PDML disable / MERGE / partition-exchange options
------------------------------------------------------------------------------------------------*/
END etl_aa_shd_new_return_tableau;

procedure etl_aa_shd_retention_tableau(jobnumber number, processid varchar2, processname varchar2) IS
-- =============================================================================
-- PURPOSE: Populates a Tableau-compatible student retention dashboard with end-of-year (ADY) and year-to-date (YTD) cohort retention metrics, segmented by program, major, and campus, along with administrative row-level security assignments.
--
-- TARGET(S): utl_d_aa.shd_retention_tableau
--
-- UNIQUE KEY / INDEX: N/A - Full data refresh (table is truncated before each run)
--
-- BUSINESS LOGIC & CONDITIONS:
-- - Processes student retention data one academic cohort year at a time, iterating through all available academic years.
-- - Retrieves the current academic day of the academic year and aligns it to historical comparisons across prior years.
-- - Generates three distinct report types for each cohort:
--   - ADY (End of Year): Uses academic end date (acad_end_date) as the effective date snapshot to show "unrevised" finalized year-end enrollment and graduation counts. Only processes cohorts where the academic end date has passed (acad_end_date < v_etl_date).
--   - YTD (Year to Date): Uses the current report timestamp as the effective date to show progressive enrollment and retention metrics for the in-progress academic year.
--   - TOTALS: Aggregates ADY and YTD metrics across all programs, majors, and campuses by retention type and level, visible only to administrative users.
-- - For ADY and YTD data, joins enrollment and retention logs on academic year and student ID (PIDM), ensuring each student appears only once per academic year (yr_rank = 1 selects the final term of enrollment).
-- - Classifies students by cohort attributes: school (college), program, major group, major description (with campus designation: RES for Resident or LUO for Online/Lubbock Online), program code, level, and campus.
-- - Counts total enrolled students, graduates, and students who returned to the same program (ret_prog), returned to the institution (ret_school), and total students returning to Lubbock University.
-- - Determines certification program inclusion based on degree code (CRT or CTG degree codes are flagged as certifications).
-- - Applies row-level security by attaching chair, academic dean, financial services coordinator, and director usernames to each program-level record, and administrative usernames to all records.
-- - Uses effective dating to ensure enrollment and retention records are valid within their from_date and to_date ranges at the snapshot date.
-- - Hardcodes all program-level records as active (active_prog = 'Y') and includes special students ('Y') per business requirement.
--
-- DEPENDENCIES: utl_d_aa.acad_year_dates, utl_d_aa.retention_log, utl_d_aa.enrollments_log, utl_d_aa.progcolldept, utl_d_aa.secfhtcoll, utl_d_aa.secadmin, smrprle, stvcoll, stvmajr, stvlevl
--
-- CONSTRAINTS & RISKS:
-- - Full table truncation occurs at the start of each execution; any concurrent reads will be blocked during the clear operation.
-- - Cartesian product risk if smrprle records fail to join on the concatenated program key (majr_code || '-' || degc_code || '-' || camp_code).
-- - Row-level security effectiveness depends on accurate maintenance of secfhtcoll college code mappings; misaligned college codes will expose rows to unintended users.
-- - The admin_usernames field is computed via a sub-select with regex deduplication for every row inserted, which may cause performance degradation on large cohorts; consider materialization if volume exceeds 100,000 rows per cohort.
-- - YTD snapshot uses current report_timestamp, which may not align with closed period boundaries; use acad_end_date for audited, final numbers only.
-- - Retention counts (ret_prog, ret_school, ret_level) depend on accurate flagging in the retention_log table; upstream data quality issues will cascade directly into the dashboard.
-- - URL: https://reports.liberty.edu/#/site/Academics/views/ProgramEnrollmentNumbers
-- =============================================================================
-- DECLARE
--- PARAMS
v_etl_date    DATE := SYSDATE;
v_msg         VARCHAR2(2000);
v_instance    VARCHAR2(50) := upper('ALL'); -- inst from the jams job; used for determining instance
v_partition   NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0 
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_aa_shd_retention_tableau';
CURSOR c_terms IS
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
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
utl_d_aa.truncate_table(v_table_name => 'shd_retention_tableau');
dbms_output.put_line(' --------- ');
FOR rec IN c_terms
LOOP
v_count   := 0; -- reset count
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || rec.cohort_year || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- ADY (End of Year) numbers
INSERT INTO utl_d_aa.shd_retention_tableau
(cohort_aidy_code,
 retention_aidy_code,
 retention_type,
 cohort_school,
 cohort_program,
 cohort_major_group,
 cohort_major_desc,
 cohort_prog_code,
 cohort_levl,
 cohort_campus,
 total_students,
 graduated,
 ret_prog,
 -- percentages are computed in tableau dashboard
 ret_school,
 ret_level,
 active_prog,
 activity_date,
 include_special_students,
 include_certifications,
 chair_usernames,
 ad_usernames,
 dean_usernames,
 director_usernames,
 fsc_usernames,
 admin_usernames)
SELECT rlog.cohort_year,
       rlog.return_year,
       'ADY' AS report_type,
       stvcoll.stvcoll_desc AS cohort_school,
       smrprle.smrprle_program_desc AS cohort_program,
       pcd.majr_degc_group AS cohort_major_group,
       stvmajr.stvmajr_desc || '-' || CASE
       WHEN elog.camp_code = 'R' THEN
        'RES'
       ELSE
        'LUO'
       END AS cohort_major_desc,
       smrprle.smrprle_program AS cohort_prog_code,
       stvlevl.stvlevl_desc AS cohort_levl,
       CASE
       WHEN elog.camp_code = 'R' THEN
        'Resident'
       ELSE
        'Online'
       END AS cohort_campus,
       COUNT(rlog.pidm) AS total_enrollment,
       SUM(rlog.graduated) AS total_graduated,
       SUM(rlog.return_majr) AS ret_prog,
       SUM(rlog.return_coll) AS ret_school,
       SUM(rlog.returned) AS total_ret, -- total should match to level on this; this is a miss named field in tableau that we did want to change and mess up the configuration; this ret_level as really a total return
       'Y' AS active_prog, -- removed logic per mshenkle; no longer applicable
       v_etl_date AS activity_date,
       'Y' AS include_special_students, -- removed logic per mshenkle; no longer applicable
       CASE
       WHEN elog.degc_code IN ('CRT', 'CTG') THEN
        'Y'
       ELSE
        'N'
       END AS include_certifications,
       chair_usernames,
       ad_usernames,
       dean_usernames,
       director_usernames,
       fsc_usernames,
       (SELECT regexp_replace(listagg(lower(username), '-') within GROUP(ORDER BY 1), '([^-]*)(-\1)+($|-)', '\1\3') usernames FROM utl_d_aa.secadmin) AS admin_usernames
  FROM utl_d_aa.retention_log rlog
  JOIN utl_d_aa.enrollments_log elog
    ON elog.acad_year = rlog.cohort_year
   AND elog.pidm = rlog.pidm
-- getting all the extras we need for this dashboard; difference from SHD and PDB 
  JOIN smrprle
    ON smrprle.smrprle_program = elog.majr_code || '-' || elog.degc_code || '-' || elog.camp_code
  LEFT JOIN utl_d_aim.progcolldept pcd
    ON pcd.prog_code = smrprle.smrprle_program
  LEFT JOIN stvcoll
    ON stvcoll.stvcoll_code = smrprle.smrprle_coll_code
  LEFT JOIN stvmajr
    ON stvmajr.stvmajr_code = elog.majr_code
  LEFT JOIN stvlevl
    ON stvlevl.stvlevl_code = elog.levl_code
-- get the FHT data for row level security; there is no join on camp_code here
  LEFT JOIN utl_d_aa.secfhtcoll fhtc
    ON fhtc.college_code = elog.coll_code
 WHERE rlog.cohort_year = rec.cohort_year
   AND rec.acad_end_date BETWEEN elog.from_date AND elog.to_date -- using acad_end_date for effective date to show as "unrevised" EOY numbers
   AND elog.yr_rank = 1 -- yr_rank pulls last term of enrollment once the academic year is complete to make headcount unique
   AND rec.acad_end_date BETWEEN rlog.from_date AND rlog.to_date -- using acad_end_date for effective date to show as "unrevised" EOY numbers
   AND rec.acad_end_date < v_etl_date -- do not show rows until year is over 
 GROUP BY rlog.cohort_year,
          rlog.return_year,
          stvcoll.stvcoll_desc,
          smrprle.smrprle_program_desc,
          pcd.majr_degc_group,
          stvmajr.stvmajr_desc,
          elog.camp_code,
          smrprle.smrprle_program,
          stvlevl.stvlevl_desc,
          elog.majr_code,
          elog.degc_code,
          chair_usernames,
          ad_usernames,
          dean_usernames,
          director_usernames,
          fsc_usernames;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'INSERT (ADY) - ' || rec.cohort_year || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
v_total_count := v_total_count + v_count; -- keep running total of rows processed
-- YTD (Year to Date) numbers
INSERT INTO utl_d_aa.shd_retention_tableau
(cohort_aidy_code,
 retention_aidy_code,
 retention_type,
 cohort_school,
 cohort_program,
 cohort_major_group,
 cohort_major_desc,
 cohort_prog_code,
 cohort_levl,
 cohort_campus,
 total_students,
 graduated,
 ret_prog,
 -- percentages are computed in tableau dashboard
 ret_school,
 ret_level,
 active_prog,
 activity_date,
 include_special_students,
 include_certifications,
 chair_usernames,
 ad_usernames,
 dean_usernames,
 director_usernames,
 fsc_usernames,
 admin_usernames)
SELECT rlog.cohort_year,
       rlog.return_year,
       'YTD' AS report_type,
       stvcoll.stvcoll_desc AS cohort_school,
       smrprle.smrprle_program_desc AS cohort_program,
       pcd.majr_degc_group AS cohort_major_group,
       stvmajr.stvmajr_desc || '-' || CASE
       WHEN elog.camp_code = 'R' THEN
        'RES'
       ELSE
        'LUO'
       END AS cohort_major_desc,
       smrprle.smrprle_program AS cohort_prog_code,
       stvlevl.stvlevl_desc AS cohort_levl,
       CASE
       WHEN elog.camp_code = 'R' THEN
        'Resident'
       ELSE
        'Online'
       END AS cohort_campus,
       COUNT(rlog.pidm) AS total_enrollment,
       SUM(rlog.graduated) AS total_graduated,
       SUM(rlog.return_majr) AS ret_prog,
       SUM(rlog.return_coll) AS ret_school,
       SUM(rlog.returned) AS total_ret, -- total should match to level on this; this is a miss named field in tableau that we did want to change and mess up the configuration; this ret_level as really a total return
       'Y' AS active_prog, -- removed logic per mshenkle; no longer applicable
       v_etl_date AS activity_date,
       'Y' AS include_special_students, -- removed logic per mshenkle; no longer applicable
       CASE
       WHEN elog.degc_code IN ('CRT', 'CTG') THEN
        'Y'
       ELSE
        'N'
       END AS include_certifications,
       chair_usernames,
       ad_usernames,
       dean_usernames,
       director_usernames,
       fsc_usernames,
       (SELECT regexp_replace(listagg(lower(username), '-') within GROUP(ORDER BY 1), '([^-]*)(-\1)+($|-)', '\1\3') usernames FROM utl_d_aa.secadmin) AS admin_usernames
  FROM utl_d_aa.retention_log rlog
  JOIN utl_d_aa.enrollments_log elog
    ON elog.acad_year = rlog.cohort_year
   AND elog.pidm = rlog.pidm
-- getting all the extras we need for this dashboard; difference from SHD and PDB 
  JOIN smrprle
    ON smrprle.smrprle_program = elog.majr_code || '-' || elog.degc_code || '-' || elog.camp_code
  LEFT JOIN utl_d_aim.progcolldept pcd
    ON pcd.prog_code = smrprle.smrprle_program
  LEFT JOIN stvcoll
    ON stvcoll.stvcoll_code = smrprle.smrprle_coll_code
  LEFT JOIN stvmajr
    ON stvmajr.stvmajr_code = elog.majr_code
  LEFT JOIN stvlevl
    ON stvlevl.stvlevl_code = elog.levl_code
-- get the FHT data for row level security; there is no join on camp_code here
  LEFT JOIN utl_d_aa.secfhtcoll fhtc
    ON fhtc.college_code = elog.coll_code
 WHERE rlog.cohort_year = rec.cohort_year
   AND rec.report_timestamp BETWEEN elog.from_date AND elog.to_date -- using report_timestamp for effective date to show YTD numbers
   AND elog.yr_rank = 1 -- yr_rank pulls last term of enrollment once the academic year is complete to make headcount unique
   AND rec.report_timestamp BETWEEN rlog.from_date AND rlog.to_date -- using report_timestamp for effective date to show YTD numbers
 GROUP BY rlog.cohort_year,
          rlog.return_year,
          stvcoll.stvcoll_desc,
          smrprle.smrprle_program_desc,
          pcd.majr_degc_group,
          stvmajr.stvmajr_desc,
          elog.camp_code,
          smrprle.smrprle_program,
          stvlevl.stvlevl_desc,
          elog.majr_code,
          elog.degc_code,
          chair_usernames,
          ad_usernames,
          dean_usernames,
          director_usernames,
          fsc_usernames;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'INSERT (YTD) - ' || rec.cohort_year || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
v_total_count := v_total_count + v_count; -- keep running total of rows processed
-- now get the totals
INSERT INTO utl_d_aa.shd_retention_tableau
(cohort_aidy_code,
 retention_aidy_code,
 retention_type,
 cohort_school,
 cohort_program,
 cohort_major_group,
 cohort_major_desc,
 cohort_prog_code,
 cohort_levl,
 cohort_campus,
 total_students,
 graduated,
 ret_level,
 active_prog,
 activity_date,
 include_special_students,
 include_certifications,
 -- only admins see numbers on this segment
 admin_usernames)
SELECT src.cohort_aidy_code AS cohort_year,
       src.retention_aidy_code AS retention_aidy_code,
       src.retention_type,
       'TOTAL' AS cohort_school,
       '*' AS cohort_program,
       '*' AS cohort_major_group,
       '*' AS cohort_major_desc,
       '*' AS cohort_prog_code,
       src.cohort_levl,
       src.cohort_campus,
       SUM(src.total_students) total_students,
       SUM(src.graduated) graduated,
       SUM(src.ret_level) ret_level, -- this is misnamed; because it is actually returning to LU periodt. it's just that it would break the dashboard if the name changed.
       active_prog,
       v_etl_date AS activity_date,
       include_special_students,
       include_certifications,
       admin_usernames
  FROM utl_d_aa.shd_retention_tableau src
 WHERE src.cohort_aidy_code = rec.cohort_year
 GROUP BY cohort_aidy_code,
          retention_aidy_code,
          retention_type,
          cohort_school,
          cohort_program,
          cohort_major_group,
          cohort_major_desc,
          cohort_prog_code,
          cohort_levl,
          cohort_campus,
          active_prog,
          include_special_students,
          include_certifications,
          admin_usernames;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'INSERT (TOTALS) - ' || rec.cohort_year || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
v_total_count := v_total_count + v_count; -- keep running total of rows processed
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
END etl_aa_shd_retention_tableau;

procedure etl_aa_shd_courses_tableau(jobnumber number, processid varchar2, processname varchar2) is
/*
Table: shd_courses_tableau

Primary Keys: NONE

Unique index: NONE

Purpose:
- Staging data for the SHD that is used by the Provost Office. 

Conditions: 
-- - hours must be > 0
-- - returning one row per academic year; show data associated with the last semester enrolled
-- - student must be university level and in a program that has awardable credit

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
v_proc        VARCHAR2(100) := 'etl_aa_shd_courses_tableau';
CURSOR c_terms IS
SELECT DISTINCT term_code
  FROM zbtm.terms_by_group_v t
 WHERE to_date('06/30/20' || substr(t.fa_proc_year, 3, 2), 'mm/dd/yyyy') > SYSDATE - (365 * 5)
   AND to_date('07/01/20' || substr(t.fa_proc_year, 1, 2), 'mm/dd/yyyy') < SYSDATE + (365 * 1) -- need to look to the future for refreshing forecasts 
   AND t.fa_proc_year <= (SELECT MIN(aidy_code) FROM utl_d_aa.crsfcstptrmhours) -- current year overlap needed; using forecast table the min year to determine evaluation steps below
   AND t.semester NOT IN ('WIN')
   AND t.group_code IN ('STD')
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
-- remove older years during the first week of july; only keep the last 5 years in the dashboard
IF to_char(SYSDATE, 'MM') = '07'
   AND to_number(to_char(SYSDATE, 'DD')) BETWEEN 1 AND 7 THEN
DELETE FROM utl_d_aa.shd_courses_tableau tgt
 WHERE tgt.report_year < (SELECT MIN(t.fa_proc_year)
                            FROM zbtm.terms_by_group_v t
                           WHERE to_date('06/30/20' || substr(t.fa_proc_year, 3, 2), 'mm/dd/yyyy') > SYSDATE - (365 * 5)
                             AND t.group_code IN ('STD'));
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'DELETE (< 5 years) - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
END IF;
FOR rec IN c_terms
LOOP
v_count := 0; -- reset count
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
DELETE FROM utl_d_aa.shd_courses_tableau tgt
 WHERE 1 = 1
   AND tgt.term = rec.term_code;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'DELETE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
INSERT INTO utl_d_aa.shd_courses_tableau
(students,
 credits,
 report_year,
 term,
 subj_code,
 crse_numb,
 course,
 coll_code,
 college,
 campus,
 insm_code,
 levl_code,
 program_group,
 placeholder,
 projected_enrollment,
 projected_hours,
 ad_usernames,
 im_usernames,
 chair_usernames,
 dean_usernames,
 director_usernames,
 prov_usernames,
 fsc_usernames,
 sme_usernames,
 admin_usernames,
 activity_date)
SELECT students,
       credits,
       report_year,
       term,
       subj_code,
       crse_numb,
       course,
       coll_code,
       college,
       src.campus,
       insm_code,
       levl_code,
       program_group,
       placeholder,
       projected_enrollment,
       projected_hours,
       fhtc.ad_usernames,
       fhtc.im_usernames,
       fhtc.chair_usernames,
       fhtc.dean_usernames,
       fhtc.director_usernames,
       fhtc.prov_usernames,
       fhtc.fsc_usernames,
       fhtc.sme_usernames,
       fhtc.admin_usernames,
       v_etl_date AS activity_date
  FROM ( -- First part - Actual enrollment data
        SELECT /*+ LEADING(rsb) USE_NL(enrl) INDEX(rsb szrcrse_indx3) INDEX(enrl szrenrl_idx2) */
         COUNT(rsb.pidm) students,
          SUM(rsb.credit_hr) credits,
          rsb.acad_year AS report_year,
          rsb.term_code AS term,
          rsb.subj subj_code,
          rsb.numb crse_numb,
          rsb.subj || '_' || rsb.numb AS course,
          smrprle.smrprle_coll_code AS coll_code,
          rsb.college college,
          rsb.camp_code campus,
          rsb.insm_code insm_code,
          rsb.levl_code,
          nvl(pcd.majr_degc_group, smrprle.smrprle_program_desc) AS program_group,
          'Actual' AS placeholder,
          NULL AS projected_enrollment,
          NULL AS projected_hours
          FROM utl_d_aim.szrcrse rsb
          JOIN utl_d_aim.szrenrl enrl
            ON enrl.term_code = rsb.term_code
           AND enrl.pidm = rsb.pidm
           AND rsb.term_code = rec.term_code
           AND rsb.group_code <> 'ACD'
           AND enrl.term_hours > 0
          LEFT JOIN saturn.smrprle
            ON smrprle.smrprle_program = enrl.prog_code_1
          LEFT JOIN utl_d_aim.progcolldept pcd
            ON pcd.prog_code = enrl.prog_code_1
         GROUP BY rsb.acad_year,
                   rsb.subj,
                   rsb.numb,
                   rsb.subj || '_' || rsb.numb,
                   rsb.term_code,
                   smrprle.smrprle_coll_code,
                   rsb.college,
                   rsb.camp_code,
                   rsb.insm_code,
                   rsb.levl_code,
                   nvl(pcd.majr_degc_group, smrprle.smrprle_program_desc)) src
-- get the FHT data for row level security; there is no join on camp_code here
  LEFT JOIN utl_d_aa.secfhtcoll fhtc
    ON fhtc.college_code = src.coll_code;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
END LOOP; -- c_terms
-- next step should remain outside the looping; no aidy/term code join needed; just insert all at once
DELETE FROM utl_d_aa.shd_courses_tableau tgt
 WHERE 1 = 1
   AND tgt.term IS NULL; -- projections do not have a term
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'DELETE - ' || '000000' || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
INSERT INTO utl_d_aa.shd_courses_tableau
(students,
 credits,
 report_year,
 term,
 subj_code,
 crse_numb,
 course,
 coll_code,
 college,
 campus,
 insm_code,
 levl_code,
 program_group,
 placeholder,
 projected_enrollment,
 projected_hours,
 ad_usernames,
 im_usernames,
 chair_usernames,
 dean_usernames,
 director_usernames,
 prov_usernames,
 fsc_usernames,
 sme_usernames,
 admin_usernames,
 activity_date)
-- Second part - Projected data
SELECT students,
       credits,
       report_year,
       term,
       subj_code,
       crse_numb,
       course,
       coll_code,
       college,
       src.campus,
       insm_code,
       levl_code,
       program_group,
       placeholder,
       projected_enrollment,
       projected_hours,
       fhtc.ad_usernames,
       fhtc.im_usernames,
       fhtc.chair_usernames,
       fhtc.dean_usernames,
       fhtc.director_usernames,
       fhtc.prov_usernames,
       fhtc.fsc_usernames,
       fhtc.sme_usernames,
       fhtc.admin_usernames,
       v_etl_date AS activity_date
  FROM (SELECT /*+ LEADING(hours hist) USE_HASH(seats) USE_HASH(sects) USE_NL(scbcrse) USE_NL(stvcoll) 
                                                         INDEX(hours crsfcstptrmhours_pk) INDEX(seats crsfcstptrmseats_pk) INDEX(sects crsfcstptrmsects_pk) */
         NULL AS students, -- no actuals shown; does not exist
         NULL AS credits, -- no actuals shown; does not exist
         hours.aidy_code AS report_year,
         NULL AS term,
         substr(hours.group1, 0, 4) AS subj_code,
         substr(hours.group1, 6, 3) AS crse_numb,
         hours.group1 AS course,
         stvcoll.stvcoll_code AS coll_code,
         stvcoll.stvcoll_desc AS college,
         hours.group2 AS campus,
         NULL AS insm_code,
         CASE
         WHEN substr(hours.group1, 6, 3) <= '499' THEN
          'UG'
         WHEN substr(hours.group1, 6, 3) <= '699' THEN
          'GR'
         WHEN substr(hours.group1, 6, 3) > '699' THEN
          'DR'
         END,
         NULL AS levl_code,
         NULL AS program_group,
         'Projected' AS placeholder,
         SUM(seats.total) AS projected_enrollment,
         SUM(hours.total) AS projected_hours
          FROM utl_d_aa.crsfcstptrmhours hours
        -- this join is only to remove NULLS
          JOIN (SELECT /*+ NO_MERGE */
               DISTINCT hist.group1,
                        hist.group2
                 FROM utl_d_aa.crspaceaidyep hist
                 JOIN utl_d_aa.crshist_stg stg
                   ON stg.aidy_code = hist.aidy_code
                  AND (stg.current_year = 'Y' OR stg.previous_year = 'Y')) hist
            ON hours.group1 = hist.group1
           AND hours.group2 = hist.group2
        -- no aidy/term code join needed; just insert all at once
          LEFT JOIN utl_d_aa.crsfcstptrmseats seats
            ON seats.group1 = hours.group1
           AND seats.group2 = hours.group2
           AND seats.aidy_code = hours.aidy_code
           AND seats.semester = hours.semester
           AND seats.ptrm_code = hours.ptrm_code
          LEFT JOIN utl_d_aa.crsfcstptrmsects sects
            ON sects.group1 = hours.group1
           AND sects.group2 = hours.group2
           AND sects.aidy_code = hours.aidy_code
           AND sects.semester = hours.semester
           AND sects.ptrm_code = hours.ptrm_code
          LEFT JOIN saturn.scbcrse
            ON scbcrse_subj_code || '_' || scbcrse_crse_numb = hours.group1
           AND scbcrse_eff_term = (SELECT /*+ NO_MERGE */
                                    MAX(d.scbcrse_eff_term)
                                     FROM saturn.scbcrse d
                                    WHERE d.scbcrse_subj_code = scbcrse.scbcrse_subj_code
                                      AND d.scbcrse_crse_numb = scbcrse.scbcrse_crse_numb)
          LEFT JOIN stvcoll
            ON stvcoll_code = scbcrse_coll_code
         WHERE hours.grouping1 = 'Course'
           AND hours.grouping2 = 'Campus'
         GROUP BY hours.aidy_code,
                  hours.group1,
                  stvcoll.stvcoll_code,
                  stvcoll.stvcoll_desc,
                  hours.group2,
                  CASE
                  WHEN substr(hours.group1, 6, 3) <= '499' THEN
                   'UG'
                  WHEN substr(hours.group1, 6, 3) <= '699' THEN
                   'GR'
                  WHEN substr(hours.group1, 6, 3) > '699' THEN
                   'DR'
                  END) src
-- get the FHT data for row level security; there is no join on camp_code here
  LEFT JOIN utl_d_aa.secfhtcoll fhtc
    ON fhtc.college_code = src.coll_code;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || '000000' || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
-- log any errors
EXCEPTION
WHEN OTHERS THEN
ROLLBACK; -- leaving data as-is since we didn't return records for the insert
dbms_lock.sleep(0.5); -- pause half second
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'ROLLBACK - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
v_msg         := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
/*--------------------------------------------CHANGE LOG----------------------------------------
--- 10-23-2024 WGRIFFITH2 - Initial release
--- 05-19-2025 WGRIFFITH2 - optimization due to runaways
-- 20251211 - WGRIFFITH2 - Mitigated ORA-12839 by adding commit boundaries after DELETEs and documenting PDML disable / MERGE / partition-exchange options
------------------------------------------------------------------------------------------------*/
END etl_aa_shd_courses_tableau;

END load_aa_etl_shd;
-- GRANT EXECUTE ON load_aa_etl_shd TO utl_d_aim;
-- GRANT EXECUTE ON load_aa_etl_shd TO utl_d_aa;
-- GRANT EXECUTE ON load_aa_etl_shd TO utl_d_lms;
-- GRANT EXECUTE ON load_aa_etl_shd TO wgriffith2;
-- GRANT EXECUTE ON load_aa_etl_shd TO ZETL_JAMS_SVC;