create or replace package load_aa_etl_pacing is
-- student pacing/forecasts
procedure etl_aa_stuhist_refresh (jobnumber number, processid varchar2, processname varchar2);
procedure etl_aa_stuhistaidydim_refresh (jobnumber number, processid varchar2, processname varchar2);
procedure etl_aa_stumultaidygen_refresh (jobnumber number, processid varchar2, processname varchar2);
procedure etl_aa_stupaceaidy_refresh (jobnumber number, processid varchar2, processname varchar2);
procedure etl_aa_stupaceaidyep_refresh (jobnumber number, processid varchar2, processname varchar2);
procedure etl_aa_stupaceaidyep_log (jobnumber number, processid varchar2, processname varchar2);
-- course pacing/forecasts
procedure etl_aa_crshist_refresh (jobnumber number, processid varchar2, processname varchar2);
procedure etl_aa_crshistaidydim_refresh (jobnumber number, processid varchar2, processname varchar2);
procedure etl_aa_crsmultaidygen_refresh (jobnumber number, processid varchar2, processname varchar2);
procedure etl_aa_crsmultptrmgen_refresh (jobnumber number, processid varchar2, processname varchar2);
procedure etl_aa_crspaceaidy_refresh (jobnumber number, processid varchar2, processname varchar2);
procedure etl_aa_crspaceaidyep_refresh(jobnumber number, processid varchar2, processname varchar2);
procedure etl_aa_crsmultptrmgenx_refresh (jobnumber number, processid varchar2, processname varchar2);
procedure etl_aa_crshistptrmdim_refresh (jobnumber number, processid varchar2, processname varchar2, inst varchar2, nmbr number); 
procedure etl_aa_crspaceptrm_refresh (jobnumber number, processid varchar2, processname varchar2, inst varchar2, nmbr number); 
procedure etl_aa_crspaceptrmep_refresh (jobnumber number, processid varchar2, processname varchar2);
procedure etl_aa_crspaceptrmep_log (jobnumber number, processid varchar2, processname varchar2);
-- retention/persistence/melt pacing
procedure etl_aa_stumelt (jobnumber number, processid varchar2, processname varchar2);
-- LUOA course pacing
procedure etl_aa_crshist_luoa (jobnumber number, processid varchar2, processname varchar2);
procedure etl_aa_crshistaidydim_luoa (jobnumber number, processid varchar2, processname varchar2);
procedure etl_aa_crsmultaidygen_luoa (jobnumber number, processid varchar2, processname varchar2);
procedure etl_aa_crspaceaidy_luoa (jobnumber number, processid varchar2, processname varchar2);
procedure etl_aa_crspaceaidyep_luoa (jobnumber number, processid varchar2, processname varchar2);
end load_aa_etl_pacing;
/

create or replace package body load_aa_etl_pacing is

procedure etl_aa_stumelt (jobnumber number, processid varchar2, processname varchar2) is
-- DECLARE
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
v_proc         VARCHAR2(100) := 'etl_aa_stumelt';
CURSOR c_terms IS
SELECT DISTINCT terms.fa_proc_year AS cohort_aidy_code, -- distinct required becuase it would dup on term
                to_char(terms.fa_proc_year + 101) AS retention_aidy_code, -- get next year 
                trunc(terms.start_date + dates.numb) AS report_date, -- this aligns with cohort_aidy_code
                to_date(to_char(trunc(terms.start_date + dates.numb) + 365 + (4 / 24), 'MM/DD/YYYY hh24:mi:ss'), 'MM/DD/YYYY hh24:mi:ss') AS retention_ytd_timestamp -- this aligns with retention_aidy_code timing pushed to 4am of the day to simulate overnight run
  FROM zbtm.terms_by_group_v terms
-- START TRACKING DATA 90 DAYS PRIOR TO TERM START DATE
  JOIN (SELECT LEVEL - 90 numb FROM dual CONNECT BY LEVEL <= 410) dates
    ON terms.start_date + dates.numb <= to_date('06/30/20' || substr(terms.fa_proc_year, 3, 2), 'mm/dd/yyyy') -- cut off for the end of ADY
   AND terms.start_date + dates.numb <= SYSDATE
   AND terms.term_code BETWEEN '202040' AND '203040'
   AND terms.group_code IN ('STD', 'MED')
   AND terms.semester IN ('FAL', 'SPR', 'SUM')
  LEFT JOIN (SELECT DISTINCT report_date,
                             aidy_code
               FROM utl_d_aa.stumelt hist) hist
    ON hist.aidy_code = terms.fa_proc_year
   AND terms.start_date + dates.numb = hist.report_date -- must match the day of retention_ytd_timestamp
 WHERE hist.report_date IS NULL
   AND to_date(to_char(trunc(terms.start_date + dates.numb) + 365 + (4 / 24), 'MM/DD/YYYY hh24:mi:ss'), 'MM/DD/YYYY hh24:mi:ss') < SYSDATE -- do not get future dates
   AND terms.start_date + dates.numb >= to_date('07/01/20' || substr(terms.fa_proc_year, 1, 2), 'mm/dd/yyyy')
   AND terms.start_date + dates.numb <= to_date('06/30/20' || substr(terms.fa_proc_year, 3, 2), 'mm/dd/yyyy')
 ORDER BY 1 ASC,
          2 ASC,
          3 ASC;
BEGIN
-- dbms_output.enable(buffer_size => NULL);
--
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
utl_d_aa.truncate_table(v_table_name => 'stumelt_stg');
INSERT INTO utl_d_aa.stumelt_stg
(aidy_code,
 aidy_start_date,
 aidy_end_date,
 current_year,
 previous_year,
 start404_yyyy,
 end404_yyyy,
 aidy_code303,
 aidy_code202,
 aidy_code101,
 aidy_code000)
SELECT DISTINCT t.fa_proc_year aidy_code,
                to_date('07/01/20' || substr(t.fa_proc_year, 1, 2), 'mm/dd/yyyy') AS aidy_start_date,
                to_date('06/30/20' || substr(t.fa_proc_year, 3, 2), 'mm/dd/yyyy') AS aidy_end_date,
                CASE
                WHEN t.fa_proc_year = (SELECT MIN(t1.fa_proc_year - 101) start_yyyy
                                         FROM zbtm.terms_by_group_v t1
                                        WHERE (SYSDATE BETWEEN to_date('07/01/20' || substr(t1.fa_proc_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(t1.fa_proc_year, 3, 2), 'mm/dd/yyyy') OR
                                              SYSDATE + 14 BETWEEN to_date('07/01/20' || substr(t1.fa_proc_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(t1.fa_proc_year, 3, 2), 'mm/dd/yyyy'))) THEN
                 'Y'
                ELSE
                 'N'
                END AS current_year,
                CASE
                WHEN t.fa_proc_year = (SELECT MIN(t1.fa_proc_year - 202) start_yyyy
                                         FROM zbtm.terms_by_group_v t1
                                        WHERE (SYSDATE BETWEEN to_date('07/01/20' || substr(t1.fa_proc_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(t1.fa_proc_year, 3, 2), 'mm/dd/yyyy') OR
                                              SYSDATE + 14 BETWEEN to_date('07/01/20' || substr(t1.fa_proc_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(t1.fa_proc_year, 3, 2), 'mm/dd/yyyy'))) THEN
                 'Y'
                ELSE
                 'N'
                END AS previous_year,
                (SELECT MIN('20' || substr(t1.fa_proc_year - 404, 1, 2)) start_yyyy
                   FROM zbtm.terms_by_group_v t1
                  WHERE (SYSDATE BETWEEN to_date('07/01/20' || substr(t1.fa_proc_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(t1.fa_proc_year, 3, 2), 'mm/dd/yyyy') OR
                        SYSDATE + 14 BETWEEN to_date('07/01/20' || substr(t1.fa_proc_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(t1.fa_proc_year, 3, 2), 'mm/dd/yyyy'))) start404_yyyy,
                (SELECT MIN('20' || substr(t1.fa_proc_year - 404, 3, 2)) end_yyyy
                   FROM zbtm.terms_by_group_v t1
                  WHERE (SYSDATE BETWEEN to_date('07/01/20' || substr(t1.fa_proc_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(t1.fa_proc_year, 3, 2), 'mm/dd/yyyy') OR
                        SYSDATE + 14 BETWEEN to_date('07/01/20' || substr(t1.fa_proc_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(t1.fa_proc_year, 3, 2), 'mm/dd/yyyy'))) end404_yyyy,
                (SELECT MIN(t1.fa_proc_year - 303) start_yyyy
                   FROM zbtm.terms_by_group_v t1
                  WHERE (SYSDATE BETWEEN to_date('07/01/20' || substr(t1.fa_proc_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(t1.fa_proc_year, 3, 2), 'mm/dd/yyyy') OR
                        SYSDATE + 14 BETWEEN to_date('07/01/20' || substr(t1.fa_proc_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(t1.fa_proc_year, 3, 2), 'mm/dd/yyyy'))) aidy_code303,
                (SELECT MIN(t1.fa_proc_year - 202) start_yyyy
                   FROM zbtm.terms_by_group_v t1
                  WHERE (SYSDATE BETWEEN to_date('07/01/20' || substr(t1.fa_proc_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(t1.fa_proc_year, 3, 2), 'mm/dd/yyyy') OR
                        SYSDATE + 14 BETWEEN to_date('07/01/20' || substr(t1.fa_proc_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(t1.fa_proc_year, 3, 2), 'mm/dd/yyyy'))) aidy_code202,
                (SELECT MIN(t1.fa_proc_year - 101) start_yyyy
                   FROM zbtm.terms_by_group_v t1
                  WHERE (SYSDATE BETWEEN to_date('07/01/20' || substr(t1.fa_proc_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(t1.fa_proc_year, 3, 2), 'mm/dd/yyyy') OR
                        SYSDATE + 14 BETWEEN to_date('07/01/20' || substr(t1.fa_proc_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(t1.fa_proc_year, 3, 2), 'mm/dd/yyyy'))) aidy_code101,
                (SELECT MIN(t1.fa_proc_year - 0) start_yyyy
                   FROM zbtm.terms_by_group_v t1
                  WHERE (SYSDATE BETWEEN to_date('07/01/20' || substr(t1.fa_proc_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(t1.fa_proc_year, 3, 2), 'mm/dd/yyyy') OR
                        SYSDATE + 14 BETWEEN to_date('07/01/20' || substr(t1.fa_proc_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(t1.fa_proc_year, 3, 2), 'mm/dd/yyyy'))) aidy_code000
  FROM zbtm.terms_by_group_v t
  JOIN saturn.sobptrm
    ON sobptrm_term_code = t.term_code
   AND sobptrm_ptrm_code IN ('R', '1A', '1B', '1C', '1D', '1J', 'L')
 WHERE t.fa_proc_year IN (SELECT DISTINCT t.fa_proc_year aidy_code
                            FROM zbtm.terms_by_group_v t
                           WHERE t.end_date > SYSDATE - (365 * 5)
                             AND t.end_date < SYSDATE -- **this is different than stuhist and crshist**
                             AND t.semester NOT IN ('WIN')
                             AND t.group_code IN ('STD', 'MED'))
   AND t.semester NOT IN ('WIN')
   AND t.group_code IN ('STD', 'MED');
COMMIT;
FOR rec IN c_terms
LOOP
v_count   := 0; -- reset count
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || rec.cohort_aidy_code || ' - ' || rec.retention_ytd_timestamp || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
INSERT INTO utl_d_aa.stumelt
(report_date,
 aidy_code,
 prog_code,
 levl_code,
 camp_code,
 coll_code,
 cohort_enrollment,
 graduated,
 return_enrollment,
 campus_switchers,
 activity_date)
-- get the graduates population, so we can determine if they graduated >= their last term of enrollment 
WITH grads AS
 (SELECT shrdgmr_pidm,
         shrdgmr_term_code_grad,
         shrdgmr_levl_code,
         shrdgmr_degc_code,
         stvdegc_acat_code
    FROM saturn.shrdgmr
    JOIN saturn.stvdegc
      ON shrdgmr_degc_code = stvdegc_code
     AND shrdgmr_term_code_grad IN (SELECT term_code
                                      FROM zbtm.terms_by_group_v terms
                                     WHERE terms.group_code IN ('STD', 'MED') -- only get standard terms and med 
                                       AND terms.fa_proc_year = rec.cohort_aidy_code)
     AND shrdgmr_degs_code = 'AW'),
cohort AS
 (SELECT enrl.term_code,
         enrl.pidm,
         enrl.degc_code_1 AS degc_code,
         stvdegc_acat_code,
         coalesce(enrl.prog_code_1, enrl.majr_code_1 || '-' || enrl.degc_code_1 || '-' || enrl.camp_code, 'XXXX-XX-X') AS prog_code,
         enrl.levl_code,
         enrl.camp_code,
         enrl.coll_code_1 AS coll_code,
         rank() over(PARTITION BY enrl.pidm, rec.cohort_aidy_code ORDER BY enrl.term_code DESC, rownum) last_enrl_rank -- return last enrollment of the year
    FROM utl_d_aim.szrenrl enrl
    JOIN zsaturn.szrlevl
      ON szrlevl_levl_code = enrl.levl_code
     AND szrlevl_is_univ = 'Y'
     AND szrlevl_has_awardable_cred = 'Y'
     AND enrl.term_hours > 0 -- hours must be > 0 
    JOIN zbtm.terms_by_group_v terms
      ON terms.term_code = enrl.term_code
     AND terms.group_code IN ('STD', 'MED') -- only get standard terms and med 
     AND terms.fa_proc_year = rec.cohort_aidy_code
    JOIN saturn.stvdegc
      ON enrl.degc_code_1 = stvdegc.stvdegc_code)
-- MAIN SELECT 
SELECT rec.report_date AS report_date, -- cohort 
       rec.cohort_aidy_code AS aidy_code, -- cohort
       cohort.prog_code AS prog_code, -- cohort
       cohort.levl_code AS levl_code, -- cohort
       cohort.camp_code AS camp_code, -- cohort
       cohort.coll_code AS coll_code, -- cohort
       COUNT(cohort.pidm) AS cohort_enrollment, -- cohort 
       COUNT(grads.shrdgmr_pidm) AS graduated, -- graduated from the cohort
       COUNT(ret.pidm) AS return_enrollment, -- retention  
       COUNT(CASE
             WHEN cohort.camp_code <> ret.camp_code THEN
              1
             ELSE
              NULL
             END) AS campus_switchers,
       SYSDATE AS activity_date
  FROM cohort
  LEFT JOIN grads
    ON grads.shrdgmr_pidm = cohort.pidm
   AND grads.shrdgmr_term_code_grad >= cohort.term_code -- the graduation term has to be >= to the last enrolled term
   AND ((grads.stvdegc_acat_code >= cohort.stvdegc_acat_code AND grads.shrdgmr_degc_code <> 'MDV') -- if not MDV, the degree code has to be >= the enrollment degree code
       OR (grads.shrdgmr_degc_code = 'MDV' AND grads.shrdgmr_degc_code = cohort.degc_code)) -- if MDV, degree in passing in effect, we want to count this as an awarded degree
  LEFT JOIN (SELECT sfrstca_pidm AS pidm,
                    coalesce(lcur.prog_code_1, lcur.majr_code_1 || '-' || lcur.degc_code_1 || '-' || lcur.camp_code,  'XXXX-XX-X') AS prog_code,
                    lcur.levl_code AS levl_code,
                    lcur.camp_code AS camp_code,
                    lcur.prog_coll_1 AS coll_code,
                    rank() over(PARTITION BY sfrstca_pidm, rec.retention_aidy_code ORDER BY sfrstca_term_code DESC, sfrstca_rsts_date DESC, rownum) last_enrl_rank -- return last enrollment of the year
               FROM saturn.sfrstca
               JOIN saturn.stvrsts
                 ON stvrsts_code = sfrstca_rsts_code
                AND stvrsts_incl_sect_enrl = 'Y' -- aligns with AA tables
                   --      AND stvrsts_incl_assess = 'Y' -- aligns with EM MR;
                   -- we are looking for ALL enrollments - including zero (0) credit hours
                AND sfrstca_rsts_date <= rec.retention_ytd_timestamp
                AND sfrstca_source_cde = 'BASE'
                AND sfrstca_levl_code <> 'PD' -- remove these courses because we do not want them to appear even if they are university level students
                AND sfrstca.sfrstca_seq_number = (SELECT MAX(d.sfrstca_seq_number)
                                                    FROM saturn.sfrstca d
                                                   WHERE d.sfrstca_pidm = sfrstca.sfrstca_pidm
                                                     AND d.sfrstca_term_code = sfrstca.sfrstca_term_code
                                                     AND d.sfrstca_crn = sfrstca.sfrstca_crn
                                                     AND d.sfrstca_source_cde = 'BASE'
                                                     AND d.sfrstca_rsts_date <= rec.retention_ytd_timestamp -- simulates runs at 4am everyday
                                                  )
               JOIN zbtm.terms_by_group_v terms -- do not remove this join because we need to make sure we exclude any terms we do not want to pull into the totals
                 ON terms.term_code = sfrstca_term_code
                AND terms.group_code IN ('STD', 'MED') -- only get standard terms and med 
                AND terms.fa_proc_year = rec.retention_aidy_code
               JOIN saturn.spriden
                 ON spriden_pidm = sfrstca_pidm
                AND spriden_change_ind IS NULL -- ensure valid student record still exists
               JOIN saturn.ssbsect
                 ON ssbsect_term_code = sfrstca_term_code
                AND ssbsect_crn = sfrstca_crn
                AND ssbsect_subj_code <> 'NEWS'
               JOIN zexec.zsavlcur lcur
                 ON lcur.pidm = sfrstca_pidm
                AND sfrstca_term_code BETWEEN lcur.from_term AND lcur.end_term
               JOIN zsaturn.szrlevl
                 ON szrlevl_levl_code = lcur.levl_code
                AND szrlevl_is_univ = 'Y' -- student must be university level and in a program that has awardable credit
                AND szrlevl_has_awardable_cred = 'Y') ret
    ON ret.pidm = cohort.pidm
   AND ret.last_enrl_rank = 1 -- iso last term of enrollment 
   AND grads.shrdgmr_pidm IS NULL -- remove grads from the return count; do not move this to the where clause. needs to be here on the ret join 
  LEFT JOIN saturn.spbpers dead
    ON dead.spbpers_pidm = cohort.pidm
   AND dead.spbpers_dead_ind = 'Y'
  LEFT JOIN rorhold fin_fraud
    ON fin_fraud.rorhold_pidm = cohort.pidm
   AND fin_fraud.rorhold_hold_code IN ('FC', 'FD', 'FO', 'EH', 'FI', 'FY', 'FF') -- financial aid side fraud ID'ed
   AND trunc(nvl(rec.retention_ytd_timestamp, SYSDATE)) BETWEEN fin_fraud.rorhold_from_date AND fin_fraud.rorhold_to_date
 WHERE dead.spbpers_pidm IS NULL -- removing deceased from the cohort population
   AND fin_fraud.rorhold_pidm IS NULL -- removing any financial aid fraudsters 
   AND cohort.last_enrl_rank = 1 -- iso last term of enrollment 
 GROUP BY rec.report_date,
          rec.retention_aidy_code,
          cohort.prog_code,
          cohort.levl_code,
          cohort.camp_code,
          cohort.coll_code;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || rec.cohort_aidy_code || ' - ' || rec.retention_ytd_timestamp || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
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
RAISE;
/*--------------------------------------------CHANGE LOG----------------------------------------
VERSION DATE        USERNAME    UPDATES
---     09-26-2025  WGRIFFITH2  --Initial release
-- 20250930      WGRIFFITH2      --REPORT_DATE field in UTL_D_AA.STUMELT updated to be one year earlier to match the cohort year
---     10-24-2025  wgriffith2  --utl_d_aim.szrregs deprecation; removing all szrcurr joins from etl procedures live code
------------------------------------------------------------------------------------------------*/
END etl_aa_stumelt;

procedure etl_aa_crspaceptrmep_log (jobnumber number, processid varchar2, processname varchar2) is
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
v_proc        VARCHAR2(100) := 'etl_aa_crspaceptrmep_log';
BEGIN
-- dbms_output.enable(buffer_size => NULL);
--
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
dbms_output.put_line('Started at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ';');
IF to_char(v_etl_date, 'D') = '2' THEN
-- log once a week on Monday
MERGE INTO utl_d_aa.crspaceptrmep_log t1
USING (SELECT ep.aidy_code,
              ep.semester,
              ep.ptrm_code,
              ep.group1,
              ep.grouping1,
              ep.group2,
              ep.grouping2,
              ep.dim,
              ep.pace_model,
              ep.hours_final_pace,
              ep.seats_final_pace,
              ep.sects_final_pace,
              ep.activity_date
         FROM utl_d_aa.crspaceptrmep ep
         JOIN utl_d_aa.crshist_stg stg
           ON stg.aidy_code = ep.aidy_code
          AND stg.semester = ep.semester
          AND stg.ptrm_code = ep.ptrm_code
          AND stg.current_year = 'Y') t2
ON (t1.aidy_code = t2.aidy_code AND t1.semester = t2.semester AND t1.ptrm_code = t2.ptrm_code AND t1.group1 = t2.group1 AND t1.group2 = t2.group2 AND trunc(t1.activity_date) = trunc(t2.activity_date))
WHEN MATCHED THEN
UPDATE
   SET t1.grouping1        = t2.grouping1,
       t1.grouping2        = t2.grouping2,
       t1.dim              = t2.dim,
       t1.pace_model       = t2.pace_model,
       t1.hours_final_pace = t2.hours_final_pace,
       t1.seats_final_pace = t2.seats_final_pace,
       t1.sects_final_pace = t2.sects_final_pace
WHEN NOT MATCHED THEN
INSERT
VALUES
(t2.aidy_code,
 t2.semester,
 t2.ptrm_code,
 t2.group1,
 t2.grouping1,
 t2.group2,
 t2.grouping2,
 t2.dim,
 t2.pace_model,
 t2.hours_final_pace,
 t2.seats_final_pace,
 t2.sects_final_pace,
 t2.activity_date);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
ELSE
ROLLBACK;
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
---     07-27-2020  WGRIFFITH2  --Initial release
---     07-06-2021  WGRIFFITH2  --Adding IFELSE to only run on Monday. It is not necessary to run it everyday.
---     06-28-2023  WGRIFFITH2  --Updates related to performance issues; adding logging
------------------------------------------------------------------------------------------------*/
END etl_aa_crspaceptrmep_log;

procedure etl_aa_crspaceptrmep_refresh(jobnumber number, processid varchar2, processname varchar2) is
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
v_proc        VARCHAR2(100) := 'etl_aa_crspaceptrmep_refresh';
CURSOR c_terms IS
-- Using start_date - 80 corresponds with term logic in crshist_refresh
-- **This code cannot pull historically because it is using the crspace table
-- **so reloading historical data must be done ad-hoc with crshist table
SELECT DISTINCT aidy_code FROM utl_d_aa.crshist_stg stg WHERE stg.current_year = 'Y';
BEGIN
-- dbms_output.enable(buffer_size => NULL);
--
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
dbms_output.put_line('Started at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ';');
FOR rec IN c_terms
LOOP
v_count   := 0; -- reset count
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || rec.aidy_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
MERGE INTO utl_d_aa.crspaceptrmep t1
USING (SELECT DISTINCT rec.aidy_code AS aidy_code,
                       semester,
                       ptrm_code,
                       group1,
                       grouping1,
                       group2,
                       grouping2,
                       dim,
                       pace_model,
                       coalesce(last_value(hours_current_actual ignore NULLS) over(PARTITION BY group1, group2, semester, ptrm_code ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following), 0) hours_final_ct,
                       coalesce(last_value(seats_current_actual ignore NULLS) over(PARTITION BY group1, group2, semester, ptrm_code ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following), 0) seats_final_ct,
                       coalesce(last_value(sects_current_actual ignore NULLS) over(PARTITION BY group1, group2, semester, ptrm_code ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following), 0) sects_final_ct,
                       coalesce(last_value(hours_pacing ignore NULLS) over(PARTITION BY group1, group2, semester, ptrm_code ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following), 0) hours_final_pace,
                       coalesce(last_value(seats_pacing ignore NULLS) over(PARTITION BY group1, group2, semester, ptrm_code ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following), 0) seats_final_pace,
                       coalesce(last_value(sects_pacing ignore NULLS) over(PARTITION BY group1, group2, semester, ptrm_code ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following), 0) sects_final_pace,
                       SYSDATE AS activity_date
         FROM (SELECT cp.graph_date,
                      semester,
                      ptrm_code,
                      cp.group1,
                      cp.group2,
                      cp.grouping1,
                      cp.grouping2,
                      REPLACE(cp.group1 || '_' || cp.group2 || '_' || semester || '_' || ptrm_code, ' ', '') AS dim,
                      CASE
                      WHEN cp.hours_lastyear_delta = least(cp.hours_lastyear_delta, cp.hours_twoback_delta, cp.hours_threeback_delta) THEN
                       'Last Year'
                      WHEN cp.hours_twoback_delta = least(cp.hours_lastyear_delta, cp.hours_twoback_delta, cp.hours_threeback_delta) THEN
                       'Two Years Back'
                      WHEN cp.hours_threeback_delta = least(cp.hours_lastyear_delta, cp.hours_twoback_delta, cp.hours_threeback_delta) THEN
                       'Three Years Back'
                      ELSE
                       'X-Pace'
                      END AS pace_model,
                      cp.hours_current_actual,
                      CASE
                      WHEN cp.hours_lastyear_delta = least(cp.hours_lastyear_delta, cp.hours_twoback_delta, cp.hours_threeback_delta) THEN
                       cp.hours_lastyear_pacing
                      WHEN cp.hours_twoback_delta = least(cp.hours_lastyear_delta, cp.hours_twoback_delta, cp.hours_threeback_delta) THEN
                       cp.hours_twoback_pacing
                      WHEN cp.hours_threeback_delta = least(cp.hours_lastyear_delta, cp.hours_twoback_delta, cp.hours_threeback_delta) THEN
                       cp.hours_threeback_pacing
                      ELSE
                       cp.hours_lastyear_pacing -- xpace
                      END AS hours_pacing,
                      cp.seats_current_actual,
                      CASE
                      WHEN cp.seats_lastyear_delta = least(cp.seats_lastyear_delta, cp.seats_twoback_delta, cp.seats_threeback_delta) THEN
                       cp.seats_lastyear_pacing
                      WHEN cp.seats_twoback_delta = least(cp.seats_lastyear_delta, cp.seats_twoback_delta, cp.seats_threeback_delta) THEN
                       cp.seats_twoback_pacing
                      WHEN cp.seats_threeback_delta = least(cp.seats_lastyear_delta, cp.seats_twoback_delta, cp.seats_threeback_delta) THEN
                       cp.seats_threeback_pacing
                      ELSE
                       cp.seats_lastyear_pacing -- xpace
                      END AS seats_pacing,
                      cp.sects_current_actual,
                      CASE
                      WHEN cp.sects_lastyear_delta = least(cp.sects_lastyear_delta, cp.sects_twoback_delta, cp.sects_threeback_delta) THEN
                       cp.sects_lastyear_pacing
                      WHEN cp.sects_twoback_delta = least(cp.sects_lastyear_delta, cp.sects_twoback_delta, cp.sects_threeback_delta) THEN
                       cp.sects_twoback_pacing
                      WHEN cp.sects_threeback_delta = least(cp.sects_lastyear_delta, cp.sects_twoback_delta, cp.sects_threeback_delta) THEN
                       cp.sects_threeback_pacing
                      ELSE
                       cp.sects_lastyear_pacing -- xpace
                      END AS sects_pacing
                 FROM utl_d_aa.crspaceptrm cp)) t2
ON (t1.aidy_code = t2.aidy_code AND t1.semester = t2.semester AND t1.ptrm_code = t2.ptrm_code AND t1.group1 = t2.group1 AND t1.group2 = t2.group2)
WHEN MATCHED THEN
UPDATE
   SET t1.grouping1        = t2.grouping1,
       t1.grouping2        = t2.grouping2,
       t1.dim              = t2.dim,
       t1.pace_model       = t2.pace_model,
       t1.hours_final_ct   = t2.hours_final_ct,
       t1.seats_final_ct   = t2.seats_final_ct,
       t1.sects_final_ct   = t2.sects_final_ct,
       t1.hours_final_pace = t2.hours_final_pace,
       t1.seats_final_pace = t2.seats_final_pace,
       t1.sects_final_pace = t2.sects_final_pace,
       t1.activity_date    = t2.activity_date
WHEN NOT MATCHED THEN
INSERT
VALUES
(t2.aidy_code,
 t2.semester,
 t2.ptrm_code,
 t2.group1,
 t2.grouping1,
 t2.group2,
 t2.grouping2,
 t2.dim,
 t2.pace_model,
 t2.hours_final_ct,
 t2.seats_final_ct,
 t2.sects_final_ct,
 t2.hours_final_pace,
 t2.seats_final_pace,
 t2.sects_final_pace,
 t2.activity_date);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || rec.aidy_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
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
--------------------------------------------CHANGE LOG----------------------------------------
-- VERSION DATE        USERNAME    UPDATES
-- ---     12-17-2019  WGRIFFITH2  --Initial release
-- ---     05-06-2019  WGRIFFITH2  --Updating logic for timeframes to use the ADY start and end dates of 7/1-6/30
-- ---     08-11-2021  WGRIFFITH2  --Accommodating zero credit hour courses
---     06-28-2023  WGRIFFITH2  --Updates related to performance issues; adding logging
------------------------------------------------------------------------------------------------
END etl_aa_crspaceptrmep_refresh;
PROCEDURE etl_aa_crspaceptrm_refresh(jobnumber NUMBER, processid VARCHAR2, processname VARCHAR2, inst VARCHAR2, nmbr NUMBER) IS
--DECLARE
--- PARAMS
v_etl_date DATE := SYSDATE;
v_msg VARCHAR2(2000);
v_instance VARCHAR2(50) := upper(inst); -- inst from the jams job; used for determining instance
v_partition NUMBER := nmbr; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_mod NUMBER := 5; -- number of partitions to be created
v_cpu NUMBER := 4; -- number of CPUs used for parallelization - do not exceed 20 CPUs [v_mod x --v_cpu] if running simultaneously
v_count NUMBER := 0;
v_elapsed NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id VARCHAR2(32);
v_proc VARCHAR2(100) := 'etl_aa_crspaceptrm_refresh';
CURSOR c_terms IS
SELECT group1,
       group2,
       ptrm_code,
       semester,
       rownum AS rownumber,
       COUNT(*) over() total_rows
  FROM (SELECT DISTINCT 'Course' AS group1,
                        'Campus' AS group2,
                        stg.ptrm_code,
                        stg.semester -- **DO NOT LOOP BY AIDY_CODE**
          FROM utl_d_aa.crshist_stg stg
        UNION ALL
        SELECT DISTINCT 'College' AS group1,
                        'Campus' AS group2,
                        stg.ptrm_code,
                        stg.semester -- **DO NOT LOOP BY AIDY_CODE**
          FROM utl_d_aa.crshist_stg stg
        UNION ALL
        SELECT DISTINCT 'ALL' AS group1,
                        'Campus' AS group2,
                        stg.ptrm_code,
                        stg.semester -- **DO NOT LOOP BY AIDY_CODE**
          FROM utl_d_aa.crshist_stg stg
         ORDER BY 1 DESC,
                  2,
                  3,
                  4);
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
v_msg     := 'START - ' || rec.group1 || rec.group2 || rec.semester || rec.ptrm_code || ' (' || rec.rownumber || '/' || rec.total_rows || ')' || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' ||
             to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
INSERT /*+*/
INTO utl_d_aa.crspaceptrm_gtt
(graph_date,
 graph_today,
 report_date,
 aidy_code,
 ptrm_code,
 semester,
 group1,
 group2,
 hours_prior_year_mult,
 hours_two_years_back_mult,
 hours_three_years_back_mult,
 seats_prior_year_mult,
 seats_two_years_back_mult,
 seats_three_years_back_mult,
 sects_prior_year_mult,
 sects_two_years_back_mult,
 sects_three_years_back_mult,
 hours_xpace,
 seats_xpace,
 sects_xpace,
 hours,
 seats,
 sects)
SELECT crsdt.graph_date,
       crsdt.graph_today,
       crsdt.report_date,
       crsdt.aidy_code,
       crsdt.ptrm_code,
       crsdt.semester,
       crsdt.group1,
       crsdt.group2,
       -- need 0s here to populate rows for any upcoming ptrms
       coalesce(MAX(genmult.hours_prior_year_mult), 1) AS hours_prior_year_mult,
       coalesce(MAX(genmult.hours_two_years_back_mult), 1) AS hours_two_years_back_mult,
       coalesce(MAX(genmult.hours_three_years_back_mult), 1) AS hours_three_years_back_mult,
       coalesce(MAX(genmult.seats_prior_year_mult), 1) AS seats_prior_year_mult,
       coalesce(MAX(genmult.seats_two_years_back_mult), 1) AS seats_two_years_back_mult,
       coalesce(MAX(genmult.seats_three_years_back_mult), 1) AS seats_three_years_back_mult,
       coalesce(MAX(genmult.sects_prior_year_mult), 1) AS sects_prior_year_mult,
       coalesce(MAX(genmult.sects_two_years_back_mult), 1) AS sects_two_years_back_mult,
       coalesce(MAX(genmult.sects_three_years_back_mult), 1) AS sects_three_years_back_mult,
       MAX(pacex.hours_xpace) hours_xpace,
       MAX(pacex.seats_xpace) seats_xpace,
       MAX(pacex.sects_xpace) sects_xpace,
       SUM(hist.hours) hours,
       SUM(hist.seats) seats,
       SUM(hist.sections) sects
  FROM utl_d_aa.crshistptrmdim crsdt
  LEFT JOIN utl_d_aa.crshist hist
    ON hist.report_date = crsdt.report_date
   AND hist.aidy_code = crsdt.aidy_code
   AND hist.ptrm_code = crsdt.ptrm_code
   AND hist.semester = crsdt.semester
   AND CASE
       WHEN rec.group1 = 'ALL' THEN
        'ALL'
       WHEN rec.group1 = 'College' THEN
        hist.coll_desc
       WHEN rec.group1 = 'Course' THEN
        hist.subj_code || ' ' || hist.crse_numb
       END = crsdt.group1
   AND CASE
       WHEN rec.group2 = 'ALL' THEN
        'ALL'
       WHEN rec.group2 = 'Campus' THEN
        hist.camp_code
       END = crsdt.group2
-- USING GENERALIZED PACE IF WE DONT HAVE ANY HISTORICAL DATA
  LEFT JOIN utl_d_aa.crsmultptrmgen genmult
    ON genmult.graph_date = crsdt.graph_date
   AND genmult.group1 = crsdt.gen_group1
   AND genmult.group2 = crsdt.gen_group2
   AND genmult.ptrm_code = crsdt.ptrm_code
   AND genmult.semester = crsdt.semester
-- USING EXPECTED GEN PACE IF WE DO NOT HAVE OPEN ENROLLMENT FOR THE PTRM
-- ONLY POPULATES DATA FOR DIMS THAT EXISTED BEFORE
  LEFT JOIN utl_d_aa.crsmultptrmgenx pacex
    ON pacex.graph_date = crsdt.graph_date
   AND pacex.ptrm_code = crsdt.ptrm_code
   AND pacex.semester = crsdt.semester
   AND pacex.group1 = crsdt.group1
   AND pacex.group2 = crsdt.group2
   AND rec.group1 = pacex.grouping1
   AND rec.group2 = pacex.grouping2
 WHERE 1 = 1
   AND crsdt.ptrm_code = rec.ptrm_code
   AND crsdt.semester = rec.semester
   AND crsdt.grouping1 = rec.group1
   AND crsdt.grouping2 = rec.group2
   AND MOD(to_number(standard_hash(crsdt.group1 || crsdt.group2 || crsdt.ptrm_code || crsdt.semester, 'MD5'), 'XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX'), v_mod) = v_partition -- partitioning
 GROUP BY crsdt.graph_date,
          crsdt.graph_today,
          crsdt.report_date,
          crsdt.aidy_code,
          crsdt.ptrm_code,
          crsdt.semester,
          crsdt.group1,
          crsdt.group2;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || rec.group1 || rec.group2 || rec.semester || rec.ptrm_code || ' (' || rec.rownumber || '/' || rec.total_rows || ')' || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' ||
                 to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
DELETE /*+*/
FROM utl_d_aa.crspaceptrm cp
 WHERE cp.grouping1 = rec.group1
   AND cp.grouping2 = rec.group2
   AND cp.ptrm_code = rec.ptrm_code
   AND cp.semester = rec.semester
   AND MOD(to_number(standard_hash(group1 || group2 || ptrm_code || semester, 'MD5'), 'XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX'), v_mod) = v_partition -- partitioning
;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'DELETE - ' || rec.group1 || rec.group2 || rec.semester || rec.ptrm_code || ' (' || rec.rownumber || '/' || rec.total_rows || ')' || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' ||
                 to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
INSERT /*+*/
INTO utl_d_aa.crspaceptrm
(graph_date,
 graph_today,
 graph_start_date,
 semester,
 ptrm_code,
 grouping1,
 group1,
 grouping2,
 group2,
 is_historical,
 hours_current_actual,
 hours_prior_year,
 hours_two_years_back,
 hours_three_years_back,
 hours_lastyear_pacing,
 hours_twoback_pacing,
 hours_threeback_pacing,
 seats_current_actual,
 seats_prior_year,
 seats_two_years_back,
 seats_three_years_back,
 seats_lastyear_pacing,
 seats_twoback_pacing,
 seats_threeback_pacing,
 sects_current_actual,
 sects_prior_year,
 sects_two_years_back,
 sects_three_years_back,
 sects_lastyear_pacing,
 sects_twoback_pacing,
 sects_threeback_pacing,
 hours_lastyear_delta,
 hours_twoback_delta,
 hours_threeback_delta,
 seats_lastyear_delta,
 seats_twoback_delta,
 seats_threeback_delta,
 sects_lastyear_delta,
 sects_twoback_delta,
 sects_threeback_delta,
 activity_date)
SELECT graph_date,
       graph_today,
       graph_start_date,
       semester,
       ptrm_code,
       rec.group1 AS grouping1,
       group1,
       rec.group2 AS grouping2,
       group2,
       is_historical,
       CASE
       WHEN hours_current_actual < .1 THEN
        0
       ELSE
        round(hours_current_actual, 0)
       END AS hours_current_actual, -- TURN THE ZERO CREDIT HOUR COURSES BACK TO 0 AND ROUND DOWN THE TOTALS
       CASE
       WHEN hours_prior_year < .1 THEN
        0
       ELSE
        round(hours_prior_year, 0)
       END AS hours_prior_year, -- TURN THE ZERO CREDIT HOUR COURSES BACK TO 0 AND ROUND DOWN THE TOTALS
       CASE
       WHEN hours_two_years_back < .1 THEN
        0
       ELSE
        round(hours_two_years_back, 0)
       END AS hours_two_years_back, -- TURN THE ZERO CREDIT HOUR COURSES BACK TO 0 AND ROUND DOWN THE TOTALS
       CASE
       WHEN hours_three_years_back < .1 THEN
        0
       ELSE
        round(hours_three_years_back, 0)
       END AS hours_three_years_back, -- TURN THE ZERO CREDIT HOUR COURSES BACK TO 0 AND ROUND DOWN THE TOTALS
       CASE
       WHEN hours_lastyear_pacing < .1 THEN
        0
       ELSE
        round(hours_lastyear_pacing, 0)
       END AS hours_lastyear_pacing, -- TURN THE ZERO CREDIT HOUR COURSES BACK TO 0 AND ROUND DOWN THE TOTALS
       CASE
       WHEN hours_twoback_pacing < .1 THEN
        0
       ELSE
        round(hours_twoback_pacing, 0)
       END AS hours_twoback_pacing, -- TURN THE ZERO CREDIT HOUR COURSES BACK TO 0 AND ROUND DOWN THE TOTALS
       CASE
       WHEN hours_threeback_pacing < .1 THEN
        0
       ELSE
        round(hours_threeback_pacing, 0)
       END AS hours_threeback_pacing, -- TURN THE ZERO CREDIT HOUR COURSES BACK TO 0 AND ROUND DOWN THE TOTALS
       seats_current_actual,
       seats_prior_year,
       seats_two_years_back,
       seats_three_years_back,
       seats_lastyear_pacing,
       seats_twoback_pacing,
       seats_threeback_pacing,
       sects_current_actual,
       sects_prior_year,
       sects_two_years_back,
       sects_three_years_back,
       sects_lastyear_pacing,
       sects_twoback_pacing,
       sects_threeback_pacing,
       round(abs(first_value(hours_lastyear_pacing ignore NULLS)
                 over(PARTITION BY group1, group2, semester, ptrm_code ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) - last_value(hours_current_actual ignore NULLS)
                 over(PARTITION BY group1, group2, semester, ptrm_code ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following)), 0) AS hours_lastyear_delta,
       round(abs(first_value(hours_twoback_pacing ignore NULLS)
                 over(PARTITION BY group1, group2, semester, ptrm_code ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) - last_value(hours_current_actual ignore NULLS)
                 over(PARTITION BY group1, group2, semester, ptrm_code ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following)), 0) AS hours_twoback_delta,
       round(abs(first_value(hours_threeback_pacing ignore NULLS)
                 over(PARTITION BY group1, group2, semester, ptrm_code ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) - last_value(hours_current_actual ignore NULLS)
                 over(PARTITION BY group1, group2, semester, ptrm_code ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following)), 0) AS hours_threeback_delta,
       --
       abs(first_value(seats_lastyear_pacing ignore NULLS) over(PARTITION BY group1, group2, semester, ptrm_code ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) - last_value(seats_current_actual ignore NULLS)
           over(PARTITION BY group1, group2, semester, ptrm_code ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following)) AS seats_lastyear_delta,
       abs(first_value(seats_twoback_pacing ignore NULLS) over(PARTITION BY group1, group2, semester, ptrm_code ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) - last_value(seats_current_actual ignore NULLS)
           over(PARTITION BY group1, group2, semester, ptrm_code ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following)) AS seats_twoback_delta,
       abs(first_value(seats_threeback_pacing ignore NULLS)
           over(PARTITION BY group1, group2, semester, ptrm_code ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) - last_value(seats_current_actual ignore NULLS)
           over(PARTITION BY group1, group2, semester, ptrm_code ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following)) AS seats_threeback_delta,
       --
       abs(first_value(sects_lastyear_pacing ignore NULLS) over(PARTITION BY group1, group2, semester, ptrm_code ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) - last_value(sects_current_actual ignore NULLS)
           over(PARTITION BY group1, group2, semester, ptrm_code ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following)) AS sects_lastyear_delta,
       abs(first_value(sects_twoback_pacing ignore NULLS) over(PARTITION BY group1, group2, semester, ptrm_code ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) - last_value(sects_current_actual ignore NULLS)
           over(PARTITION BY group1, group2, semester, ptrm_code ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following)) AS sects_twoback_delta,
       abs(first_value(sects_threeback_pacing ignore NULLS)
           over(PARTITION BY group1, group2, semester, ptrm_code ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) - last_value(sects_current_actual ignore NULLS)
           over(PARTITION BY group1, group2, semester, ptrm_code ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following)) AS sects_threeback_delta,
       v_etl_date AS activity_date
  FROM (SELECT sub1.graph_date,
               sub1.graph_today,
               sub1.graph_start_date,
               sub1.semester,
               sub1.ptrm_code,
               rec.group1 AS grouping1,
               sub1.group1,
               rec.group2 AS grouping2,
               sub1.group2,
               CASE
               WHEN sub1.graph_date <= sub1.graph_today THEN
                'Y'
               ELSE
                'N'
               END AS is_historical,
               --
               sub1.hours_current_actual,
               round(CASE
                     -- use actuals + 8 of ptrm start date
                     WHEN sub1.graph_today >= sub1.graph_start_date + 8
                          AND sub1.hours_current_actual IS NULL THEN
                      last_value(sub1.hours_current_actual ignore NULLS) over(PARTITION BY sub1.group1, sub1.group2, sub1.ptrm_code, sub1.semester ORDER BY sub1.graph_date RANGE BETWEEN unbounded preceding AND unbounded following)
                     -- use pace model
                     WHEN sub1.graph_today < sub1.graph_start_date + 8
                          AND sub1.hours_current_actual IS NULL
                          AND sub1.hours_current_final IS NOT NULL THEN
                      (last_value(sub1.hours_current_actual ignore NULLS) over(PARTITION BY sub1.group1, sub1.group2, sub1.ptrm_code, sub1.semester ORDER BY sub1.graph_date RANGE BETWEEN unbounded preceding AND unbounded following) /
                       first_value(CASE
                                                                                      WHEN sub1.graph_date = sub1.graph_today THEN
                                                                                       sub1.hours_prior_year_mult
                                                                                      END ignore NULLS)
                       over(PARTITION BY sub1.group1, sub1.group2, sub1.ptrm_code, sub1.semester ORDER BY sub1.graph_date RANGE BETWEEN unbounded preceding AND unbounded following)) * sub1.hours_prior_year_mult
                     -- if enrollment is not open yet, we use magic to get this number using the AIDY EOY pace mult by the pct of the ptrm historically
                     WHEN sub1.hours_current_actual IS NULL
                          AND sub1.hours_current_final IS NULL
                          AND sub1.hours_xpace IS NOT NULL THEN
                      sub1.hours_xpace
                     -- new course AND new dimension; gets actual; best we can do for now...
                     WHEN coalesce(sub1.hours_xpace, 0) + coalesce(sub1.hours_prior_year, 0) + coalesce(sub1.hours_two_years_back, 0) + coalesce(sub1.hours_three_years_back, 0) = 0 THEN
                      coalesce(sub1.hours_current_actual, sub1.hours_current_final)
                     END, 0) hours_lastyear_pacing,
               round(CASE
                     -- use actuals + 8 of ptrm start date
                     WHEN sub1.graph_today >= sub1.graph_start_date + 8
                          AND sub1.hours_current_actual IS NULL THEN
                      last_value(sub1.hours_current_actual ignore NULLS) over(PARTITION BY sub1.group1, sub1.group2, sub1.ptrm_code, sub1.semester ORDER BY sub1.graph_date RANGE BETWEEN unbounded preceding AND unbounded following)
                     -- use pace model
                     WHEN sub1.graph_today < sub1.graph_start_date + 8
                          AND sub1.hours_current_actual IS NULL
                          AND sub1.hours_current_final IS NOT NULL THEN
                      (last_value(sub1.hours_current_actual ignore NULLS) over(PARTITION BY sub1.group1, sub1.group2, sub1.ptrm_code, sub1.semester ORDER BY sub1.graph_date RANGE BETWEEN unbounded preceding AND unbounded following) /
                       first_value(CASE
                                                                                      WHEN sub1.graph_date = sub1.graph_today THEN
                                                                                       sub1.hours_two_years_back_mult
                                                                                      END ignore NULLS)
                       over(PARTITION BY sub1.group1, sub1.group2, sub1.ptrm_code, sub1.semester ORDER BY sub1.graph_date RANGE BETWEEN unbounded preceding AND unbounded following)) * sub1.hours_two_years_back_mult
                     -- if enrollment is not open yet, we use magic to get this number using the AIDY EOY pace mult by the pct of the ptrm historically
                     WHEN sub1.hours_current_actual IS NULL
                          AND sub1.hours_current_final IS NULL
                          AND sub1.hours_xpace IS NOT NULL THEN
                      sub1.hours_xpace
                     -- new course AND new dimension; gets actual; best we can do for now...
                     WHEN coalesce(sub1.hours_xpace, 0) + coalesce(sub1.hours_prior_year, 0) + coalesce(sub1.hours_two_years_back, 0) + coalesce(sub1.hours_three_years_back, 0) = 0 THEN
                      coalesce(sub1.hours_current_actual, sub1.hours_current_final)
                     END, 0) hours_twoback_pacing,
               round(CASE
                     -- use actuals + 8 of ptrm start date
                     WHEN sub1.graph_today >= sub1.graph_start_date + 8
                          AND sub1.hours_current_actual IS NULL THEN
                      last_value(sub1.hours_current_actual ignore NULLS) over(PARTITION BY sub1.group1, sub1.group2, sub1.ptrm_code, sub1.semester ORDER BY sub1.graph_date RANGE BETWEEN unbounded preceding AND unbounded following)
                     -- use pace model
                     WHEN sub1.graph_today < sub1.graph_start_date + 8
                          AND sub1.hours_current_actual IS NULL
                          AND sub1.hours_current_final IS NOT NULL THEN
                      (last_value(sub1.hours_current_actual ignore NULLS) over(PARTITION BY sub1.group1, sub1.group2, sub1.ptrm_code, sub1.semester ORDER BY sub1.graph_date RANGE BETWEEN unbounded preceding AND unbounded following) /
                       first_value(CASE
                                                                                      WHEN sub1.graph_date = sub1.graph_today THEN
                                                                                       sub1.hours_three_years_back_mult
                                                                                      END ignore NULLS)
                       over(PARTITION BY sub1.group1, sub1.group2, sub1.ptrm_code, sub1.semester ORDER BY sub1.graph_date RANGE BETWEEN unbounded preceding AND unbounded following)) * sub1.hours_three_years_back_mult
                     -- if enrollment is not open yet, we use magic to get this number using the AIDY EOY pace mult by the pct of the ptrm historically
                     WHEN sub1.hours_current_actual IS NULL
                          AND sub1.hours_current_final IS NULL
                          AND sub1.hours_xpace IS NOT NULL THEN
                      sub1.hours_xpace
                     -- new course AND new dimension; gets actual; best we can do for now...
                     WHEN coalesce(sub1.hours_xpace, 0) + coalesce(sub1.hours_prior_year, 0) + coalesce(sub1.hours_two_years_back, 0) + coalesce(sub1.hours_three_years_back, 0) = 0 THEN
                      coalesce(sub1.hours_current_actual, sub1.hours_current_final)
                     END, 0) hours_threeback_pacing,
               sub1.hours_prior_year,
               sub1.hours_two_years_back,
               sub1.hours_three_years_back,
               --
               sub1.seats_current_actual,
               round(CASE
                     -- use actuals + 8 of ptrm start date
                     WHEN sub1.graph_today >= sub1.graph_start_date + 8
                          AND sub1.seats_current_actual IS NULL THEN
                      last_value(sub1.seats_current_actual ignore NULLS) over(PARTITION BY sub1.group1, sub1.group2, sub1.ptrm_code, sub1.semester ORDER BY sub1.graph_date RANGE BETWEEN unbounded preceding AND unbounded following)
                     -- use pace model
                     WHEN sub1.graph_today < sub1.graph_start_date + 8
                          AND sub1.seats_current_actual IS NULL
                          AND sub1.seats_current_final IS NOT NULL THEN
                      (last_value(sub1.seats_current_actual ignore NULLS) over(PARTITION BY sub1.group1, sub1.group2, sub1.ptrm_code, sub1.semester ORDER BY sub1.graph_date RANGE BETWEEN unbounded preceding AND unbounded following) /
                       first_value(CASE
                                                                                      WHEN sub1.graph_date = sub1.graph_today THEN
                                                                                       sub1.seats_prior_year_mult
                                                                                      END ignore NULLS)
                       over(PARTITION BY sub1.group1, sub1.group2, sub1.ptrm_code, sub1.semester ORDER BY sub1.graph_date RANGE BETWEEN unbounded preceding AND unbounded following)) * sub1.seats_prior_year_mult
                     -- if enrollment is not open yet, we use magic to get this number using the AIDY EOY pace mult by the pct of the ptrm historically
                     WHEN sub1.seats_current_actual IS NULL
                          AND sub1.seats_current_final IS NULL
                          AND sub1.seats_xpace IS NOT NULL THEN
                      sub1.seats_xpace
                     -- new course AND new dimension; gets actual; best we can do for now...
                     WHEN coalesce(sub1.seats_xpace, 0) + coalesce(sub1.seats_prior_year, 0) + coalesce(sub1.seats_two_years_back, 0) + coalesce(sub1.seats_three_years_back, 0) = 0 THEN
                      coalesce(sub1.seats_current_actual, sub1.seats_current_final)
                     END, 0) seats_lastyear_pacing,
               round(CASE
                     -- use actuals + 8 of ptrm start date
                     WHEN sub1.graph_today >= sub1.graph_start_date + 8
                          AND sub1.seats_current_actual IS NULL THEN
                      last_value(sub1.seats_current_actual ignore NULLS) over(PARTITION BY sub1.group1, sub1.group2, sub1.ptrm_code, sub1.semester ORDER BY sub1.graph_date RANGE BETWEEN unbounded preceding AND unbounded following)
                     -- use pace model
                     WHEN sub1.graph_today < sub1.graph_start_date + 8
                          AND sub1.seats_current_actual IS NULL
                          AND sub1.seats_current_final IS NOT NULL THEN
                      (last_value(sub1.seats_current_actual ignore NULLS) over(PARTITION BY sub1.group1, sub1.group2, sub1.ptrm_code, sub1.semester ORDER BY sub1.graph_date RANGE BETWEEN unbounded preceding AND unbounded following) /
                       first_value(CASE
                                                                                      WHEN sub1.graph_date = sub1.graph_today THEN
                                                                                       sub1.seats_two_years_back_mult
                                                                                      END ignore NULLS)
                       over(PARTITION BY sub1.group1, sub1.group2, sub1.ptrm_code, sub1.semester ORDER BY sub1.graph_date RANGE BETWEEN unbounded preceding AND unbounded following)) * sub1.seats_two_years_back_mult
                     -- if enrollment is not open yet, we use magic to get this number using the AIDY EOY pace mult by the pct of the ptrm historically
                     WHEN sub1.seats_current_actual IS NULL
                          AND sub1.seats_current_final IS NULL
                          AND sub1.seats_xpace IS NOT NULL THEN
                      sub1.seats_xpace
                     -- new course AND new dimension; gets actual; best we can do for now...
                     WHEN coalesce(sub1.seats_xpace, 0) + coalesce(sub1.seats_prior_year, 0) + coalesce(sub1.seats_two_years_back, 0) + coalesce(sub1.seats_three_years_back, 0) = 0 THEN
                      coalesce(sub1.seats_current_actual, sub1.seats_current_final)
                     END, 0) seats_twoback_pacing,
               round(CASE
                     -- use actuals + 8 of ptrm start date
                     WHEN sub1.graph_today >= sub1.graph_start_date + 8
                          AND sub1.seats_current_actual IS NULL THEN
                      last_value(sub1.seats_current_actual ignore NULLS) over(PARTITION BY sub1.group1, sub1.group2, sub1.ptrm_code, sub1.semester ORDER BY sub1.graph_date RANGE BETWEEN unbounded preceding AND unbounded following)
                     -- use pace model
                     WHEN sub1.graph_today < sub1.graph_start_date + 8
                          AND sub1.seats_current_actual IS NULL
                          AND sub1.seats_current_final IS NOT NULL THEN
                      (last_value(sub1.seats_current_actual ignore NULLS) over(PARTITION BY sub1.group1, sub1.group2, sub1.ptrm_code, sub1.semester ORDER BY sub1.graph_date RANGE BETWEEN unbounded preceding AND unbounded following) /
                       first_value(CASE
                                                                                      WHEN sub1.graph_date = sub1.graph_today THEN
                                                                                       sub1.seats_three_years_back_mult
                                                                                      END ignore NULLS)
                       over(PARTITION BY sub1.group1, sub1.group2, sub1.ptrm_code, sub1.semester ORDER BY sub1.graph_date RANGE BETWEEN unbounded preceding AND unbounded following)) * sub1.seats_three_years_back_mult
                     -- if enrollment is not open yet, we use magic to get this number using the AIDY EOY pace mult by the pct of the ptrm historically
                     WHEN sub1.seats_current_actual IS NULL
                          AND sub1.seats_current_final IS NULL
                          AND sub1.seats_xpace IS NOT NULL THEN
                      sub1.seats_xpace
                     -- new course AND new dimension; gets actual; best we can do for now...
                     WHEN coalesce(sub1.seats_xpace, 0) + coalesce(sub1.seats_prior_year, 0) + coalesce(sub1.seats_two_years_back, 0) + coalesce(sub1.seats_three_years_back, 0) = 0 THEN
                      coalesce(sub1.seats_current_actual, sub1.seats_current_final)
                     END, 0) seats_threeback_pacing,
               sub1.seats_prior_year,
               sub1.seats_two_years_back,
               sub1.seats_three_years_back,
               --
               sub1.sects_current_actual,
               round(CASE
                     -- use actuals + 8 of ptrm start date
                     WHEN sub1.graph_today >= sub1.graph_start_date + 8
                          AND sub1.sects_current_actual IS NULL THEN
                      last_value(sub1.sects_current_actual ignore NULLS) over(PARTITION BY sub1.group1, sub1.group2, sub1.ptrm_code, sub1.semester ORDER BY sub1.graph_date RANGE BETWEEN unbounded preceding AND unbounded following)
                     -- use pace model
                     WHEN sub1.graph_today < sub1.graph_start_date + 8
                          AND sub1.sects_current_actual IS NULL
                          AND sub1.sects_current_final IS NOT NULL THEN
                      (last_value(sub1.sects_current_actual ignore NULLS) over(PARTITION BY sub1.group1, sub1.group2, sub1.ptrm_code, sub1.semester ORDER BY sub1.graph_date RANGE BETWEEN unbounded preceding AND unbounded following) /
                       first_value(CASE
                                                                                      WHEN sub1.graph_date = sub1.graph_today THEN
                                                                                       sub1.sects_prior_year_mult
                                                                                      END ignore NULLS)
                       over(PARTITION BY sub1.group1, sub1.group2, sub1.ptrm_code, sub1.semester ORDER BY sub1.graph_date RANGE BETWEEN unbounded preceding AND unbounded following)) * sub1.sects_prior_year_mult
                     -- if enrollment is not open yet, we use magic to get this number using the AIDY EOY pace mult by the pct of the ptrm historically
                     WHEN sub1.sects_current_actual IS NULL
                          AND sub1.sects_current_final IS NULL
                          AND sub1.sects_xpace IS NOT NULL THEN
                      sub1.sects_xpace
                     -- new course AND new dimension; gets actual; best we can do for now...
                     WHEN coalesce(sub1.sects_xpace, 0) + coalesce(sub1.sects_prior_year, 0) + coalesce(sub1.sects_two_years_back, 0) + coalesce(sub1.sects_three_years_back, 0) = 0 THEN
                      coalesce(sub1.sects_current_actual, sub1.sects_current_final)
                     END, 0) sects_lastyear_pacing,
               round(CASE
                     -- use actuals + 8 of ptrm start date
                     WHEN sub1.graph_today >= sub1.graph_start_date + 8
                          AND sub1.sects_current_actual IS NULL THEN
                      last_value(sub1.sects_current_actual ignore NULLS) over(PARTITION BY sub1.group1, sub1.group2, sub1.ptrm_code, sub1.semester ORDER BY sub1.graph_date RANGE BETWEEN unbounded preceding AND unbounded following)
                     -- use pace model
                     WHEN sub1.graph_today < sub1.graph_start_date + 8
                          AND sub1.sects_current_actual IS NULL
                          AND sub1.sects_current_final IS NOT NULL THEN
                      (last_value(sub1.sects_current_actual ignore NULLS) over(PARTITION BY sub1.group1, sub1.group2, sub1.ptrm_code, sub1.semester ORDER BY sub1.graph_date RANGE BETWEEN unbounded preceding AND unbounded following) /
                       first_value(CASE
                                                                                      WHEN sub1.graph_date = sub1.graph_today THEN
                                                                                       sub1.sects_two_years_back_mult
                                                                                      END ignore NULLS)
                       over(PARTITION BY sub1.group1, sub1.group2, sub1.ptrm_code, sub1.semester ORDER BY sub1.graph_date RANGE BETWEEN unbounded preceding AND unbounded following)) * sub1.sects_two_years_back_mult
                     -- if enrollment is not open yet, we use magic to get this number using the AIDY EOY pace mult by the pct of the ptrm historically
                     WHEN sub1.sects_current_actual IS NULL
                          AND sub1.sects_current_final IS NULL
                          AND sub1.sects_xpace IS NOT NULL THEN
                      sub1.sects_xpace
                     -- new course AND new dimension; gets actual; best we can do for now...
                     WHEN coalesce(sub1.sects_xpace, 0) + coalesce(sub1.sects_prior_year, 0) + coalesce(sub1.sects_two_years_back, 0) + coalesce(sub1.sects_three_years_back, 0) = 0 THEN
                      coalesce(sub1.sects_current_actual, sub1.sects_current_final)
                     END, 0) sects_twoback_pacing,
               round(CASE
                     -- use actuals + 8 of ptrm start date
                     WHEN sub1.graph_today >= sub1.graph_start_date + 8
                          AND sub1.sects_current_actual IS NULL THEN
                      last_value(sub1.sects_current_actual ignore NULLS) over(PARTITION BY sub1.group1, sub1.group2, sub1.ptrm_code, sub1.semester ORDER BY sub1.graph_date RANGE BETWEEN unbounded preceding AND unbounded following)
                     -- use pace model
                     WHEN sub1.graph_today < sub1.graph_start_date + 8
                          AND sub1.sects_current_actual IS NULL
                          AND sub1.sects_current_final IS NOT NULL THEN
                      (last_value(sub1.sects_current_actual ignore NULLS) over(PARTITION BY sub1.group1, sub1.group2, sub1.ptrm_code, sub1.semester ORDER BY sub1.graph_date RANGE BETWEEN unbounded preceding AND unbounded following) /
                       first_value(CASE
                                                                                      WHEN sub1.graph_date = sub1.graph_today THEN
                                                                                       sub1.sects_three_years_back_mult
                                                                                      END ignore NULLS)
                       over(PARTITION BY sub1.group1, sub1.group2, sub1.ptrm_code, sub1.semester ORDER BY sub1.graph_date RANGE BETWEEN unbounded preceding AND unbounded following)) * sub1.sects_three_years_back_mult
                     -- if enrollment is not open yet, we use magic to get this number using the AIDY EOY pace mult by the pct of the ptrm historically
                     WHEN sub1.sects_current_actual IS NULL
                          AND sub1.sects_current_final IS NULL
                          AND sub1.sects_xpace IS NOT NULL THEN
                      sub1.sects_xpace
                     -- new course AND new dimension; gets actual; best we can do for now...
                     WHEN coalesce(sub1.sects_xpace, 0) + coalesce(sub1.sects_prior_year, 0) + coalesce(sub1.sects_two_years_back, 0) + coalesce(sub1.sects_three_years_back, 0) = 0 THEN
                      coalesce(sub1.sects_current_actual, sub1.sects_current_final)
                     END, 0) sects_threeback_pacing,
               sub1.sects_prior_year,
               sub1.sects_two_years_back,
               sub1.sects_three_years_back,
               v_etl_date AS activity_date
          FROM (SELECT sub0.graph_date,
                       sub0.graph_today,
                       stg.graph_start_date,
                       sub0.group1,
                       sub0.group2,
                       sub0.ptrm_code,
                       sub0.semester,
                       MAX(hours_prior_year_mult) hours_prior_year_mult,
                       MAX(hours_two_years_back_mult) hours_two_years_back_mult,
                       MAX(hours_three_years_back_mult) hours_three_years_back_mult,
                       MAX(seats_prior_year_mult) seats_prior_year_mult,
                       MAX(seats_two_years_back_mult) seats_two_years_back_mult,
                       MAX(seats_three_years_back_mult) seats_three_years_back_mult,
                       MAX(sects_prior_year_mult) sects_prior_year_mult,
                       MAX(sects_two_years_back_mult) sects_two_years_back_mult,
                       MAX(sects_three_years_back_mult) sects_three_years_back_mult,
                       MAX(hours_xpace) hours_xpace,
                       MAX(seats_xpace) seats_xpace,
                       MAX(sects_xpace) sects_xpace,
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code000 THEN
                            hours
                           END) hours_current_actual,
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code000 THEN
                            hours_final_ct
                           END) hours_current_final,
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code101 THEN
                            hours
                           END) hours_prior_year,
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code101 THEN
                            hours_final_ct
                           END) hours_prior_final,
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code202 THEN
                            hours
                           END) hours_two_years_back,
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code303 THEN
                            hours
                           END) hours_three_years_back,
                       --
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code000 THEN
                            seats
                           END) seats_current_actual,
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code000 THEN
                            seats_final_ct
                           END) seats_current_final,
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code101 THEN
                            seats
                           END) seats_prior_year,
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code101 THEN
                            seats_final_ct
                           END) seats_prior_final,
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code202 THEN
                            seats
                           END) seats_two_years_back,
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code303 THEN
                            seats
                           END) seats_three_years_back,
                       --
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code000 THEN
                            sects
                           END) sects_current_actual,
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code000 THEN
                            sects_final_ct
                           END) sects_current_final,
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code101 THEN
                            sects
                           END) sects_prior_year,
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code101 THEN
                            sects_final_ct
                           END) sects_prior_final,
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code202 THEN
                            sects
                           END) sects_two_years_back,
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code303 THEN
                            sects
                           END) sects_three_years_back
                  FROM (SELECT graph_date,
                               graph_today,
                               report_date,
                               aidy_code,
                               group1,
                               group2,
                               ptrm_code,
                               semester,
                               hours_prior_year_mult,
                               hours_two_years_back_mult,
                               hours_three_years_back_mult,
                               seats_prior_year_mult,
                               seats_two_years_back_mult,
                               seats_three_years_back_mult,
                               sects_prior_year_mult,
                               sects_two_years_back_mult,
                               sects_three_years_back_mult,
                               hours_xpace,
                               seats_xpace,
                               sects_xpace,
                               hours,
                               last_value(hours ignore NULLS) over(PARTITION BY aidy_code, group1, group2, ptrm_code, semester ORDER BY report_date RANGE BETWEEN unbounded preceding AND unbounded following) hours_final_ct,
                               seats,
                               last_value(seats ignore NULLS) over(PARTITION BY aidy_code, group1, group2, ptrm_code, semester ORDER BY report_date RANGE BETWEEN unbounded preceding AND unbounded following) seats_final_ct,
                               sects,
                               last_value(sects ignore NULLS) over(PARTITION BY aidy_code, group1, group2, ptrm_code, semester ORDER BY report_date RANGE BETWEEN unbounded preceding AND unbounded following) sects_final_ct
                          FROM utl_d_aa.crspaceptrm_gtt
                        -- this line of code below needs to be here to match up the joins between the ptrm tables in the query above
                        -- in all but last week of the year, one record per week to reduce record counts
                        -- last week of the ADY runs daily numbers to continue to produce forecasts through 06/30 for the current ADY
                         WHERE 1 = 1
                           AND MOD(to_number(standard_hash(group1 || group2 || ptrm_code || semester, 'MD5'), 'XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX'), v_mod) = v_partition -- partitioning
                           AND ((to_char(v_etl_date, 'mm/dd') NOT IN ('06/22', '06/23', '06/24', '06/25', '06/26', '06/27', '06/28', '06/29', '06/30') AND to_char(v_etl_date - (365.25 * 4), 'D') = to_char(graph_date, 'D')
                               ) OR (to_char(v_etl_date, 'mm/dd') IN ('06/22', '06/23', '06/24', '06/25', '06/26', '06/27', '06/28', '06/29', '06/30')))) sub0
                  JOIN (SELECT DISTINCT aidy_code,
                                       ptrm_code,
                                       ptrm_start_date,
                                       (SELECT MAX(to_date(to_char(ptrm_start_date, 'mm/dd') || CASE
                                                           WHEN to_char(ptrm_start_date, 'yy') = substr(aidy_code000, 1, 2) THEN
                                                            start404_yyyy
                                                           ELSE
                                                            end404_yyyy
                                                           END, 'mm/dd/yyyy')) ptrmst
                                          FROM utl_d_aa.crshist_stg hs
                                         WHERE hs.current_year = 'Y'
                                           AND hs.semester = stg.semester
                                           AND hs.ptrm_code = stg.ptrm_code) graph_start_date,
                                       semester,
                                       start404_yyyy,
                                       end404_yyyy,
                                       aidy_code303,
                                       aidy_code202,
                                       aidy_code101,
                                       aidy_code000
                         FROM utl_d_aa.crshist_stg stg) stg
                    ON stg.aidy_code = sub0.aidy_code
                   AND stg.semester = sub0.semester
                   AND stg.ptrm_code = sub0.ptrm_code
                 GROUP BY sub0.graph_date,
                          sub0.graph_today,
                          stg.graph_start_date,
                          sub0.group1,
                          sub0.group2,
                          sub0.ptrm_code,
                          sub0.semester) sub1
         WHERE 1 = 1
           AND ((coalesce(seats_current_actual, 0) > 0 AND graph_date <= graph_today) OR
               (coalesce(sub1.seats_current_final, 0) + coalesce(sub1.seats_xpace, 0) + coalesce(sub1.seats_prior_year, 0) + coalesce(sub1.seats_two_years_back, 0) + coalesce(sub1.seats_three_years_back, 0) > 0 AND graph_date > graph_today)));
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || rec.group1 || rec.group2 || rec.semester || rec.ptrm_code || ' (' || rec.rownumber || '/' || rec.total_rows || ')' || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' ||
                 to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
utl_d_aa.truncate_table(v_table_name => 'crspaceptrm_gtt');
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
--------------------------------------------CHANGE LOG----------------------------------------
-- VERSION DATE        USERNAME    UPDATES
-- ---     12-17-2019  WGRIFFITH2  --Initial release
-- ---     05-06-2019  WGRIFFITH2  --Updating logic for timeframes to use the ADY start and end dates of 7/1-6/30
-- ---     08-11-2021  WGRIFFITH2  --Accommodating zero credit hour courses
-- ---     06-28-2023  WGRIFFITH2  --Updates related to performance issues; adding logging
---     09-29-2023  WGRIFFITH2  --Updates related to performance issues; adding partitioning
---     11-07-2023  WGRIFFITH2  --Updates related to performance issues TKT2809907
------------------------------------------------------------------------------------------------
END etl_aa_crspaceptrm_refresh; --
PROCEDURE etl_aa_crsmultptrmgenx_refresh(jobnumber NUMBER, processid VARCHAR2, processname VARCHAR2) IS
--DECLARE
--- PARAMS
v_etl_date DATE := SYSDATE;
v_msg VARCHAR2(2000);
v_instance VARCHAR2(50) := upper('ALL'); -- inst from the jams job; used for determining instance
v_partition NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
-- v_mod         NUMBER := 5; -- number of partitions to be created

v_count NUMBER := 0;
v_elapsed NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id VARCHAR2(32);
v_proc VARCHAR2(100) := 'etl_aa_crsmultptrmgenx_refresh';
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
dbms_output.put_line('Started at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ';');
utl_d_aa.truncate_table(v_table_name => 'crsmultptrmgenx');
INSERT INTO utl_d_aa.crsmultptrmgenx
(graph_date,
 ptrm_code,
 semester,
 group1,
 grouping1,
 group2,
 grouping2,
 hours_xpace,
 seats_xpace,
 sects_xpace,
 activity_date)
SELECT graph_date,
       ptrm_code,
       semester,
       group1,
       grouping1,
       group2,
       grouping2,
       hours_xpace,
       CASE
       WHEN hours_xpace > 0
            AND seats_xpace <= 0 THEN
        1
       ELSE
        seats_xpace
       END seats_xpace,
       CASE
       WHEN hours_xpace > 0
            AND sects_xpace <= 0 THEN
        1
       ELSE
        sects_xpace
       END AS sects_xpace,
       activity_date
  FROM (SELECT mp.graph_date,
               mp.ptrm_code,
               mp.semester,
               hist.group1,
               grouping1,
               hist.group2,
               grouping2,
               nvl(CASE
                   WHEN hist.pace_model = 'Last Year' THEN
                    round(hours_pace_eoy * hours_prior_year_mult)
                   WHEN hist.pace_model = 'Two Years Back' THEN
                    round(hours_pace_eoy * hours_two_years_back_mult)
                   WHEN hist.pace_model = 'Three Years Back' THEN
                    round(hours_pace_eoy * hours_three_years_back_mult)
                   END, 0) AS hours_xpace,
               nvl(CASE
                   WHEN hist.pace_model = 'Last Year' THEN
                    round(seats_pace_eoy * seats_prior_year_mult)
                   WHEN hist.pace_model = 'Two Years Back' THEN
                    round(seats_pace_eoy * seats_two_years_back_mult)
                   WHEN hist.pace_model = 'Three Years Back' THEN
                    round(seats_pace_eoy * seats_three_years_back_mult)
                   END, 0) AS seats_xpace,
               nvl(CASE
                   WHEN hist.pace_model = 'Last Year' THEN
                    round(sects_pace_eoy * sects_prior_year_mult)
                   WHEN hist.pace_model = 'Two Years Back' THEN
                    round(sects_pace_eoy * sects_two_years_back_mult)
                   WHEN hist.pace_model = 'Three Years Back' THEN
                    round(sects_pace_eoy * sects_three_years_back_mult)
                   END, 0) AS sects_xpace,
               v_etl_date AS activity_date
          FROM (SELECT mpg.graph_date,
                       mpg.group1,
                       mpg.group2,
                       mpg.ptrm_code,
                       mpg.semester,
                       mpg.hours_prior_year / mag.hours_prior_year_final AS hours_prior_year_mult,
                       mpg.hours_two_years_back / mag.hours_two_years_back_final AS hours_two_years_back_mult,
                       mpg.hours_three_years_back / mag.hours_three_years_back_final AS hours_three_years_back_mult,
                       mpg.seats_prior_year / mag.seats_prior_year_final AS seats_prior_year_mult,
                       mpg.seats_two_years_back / mag.seats_two_years_back_final AS seats_two_years_back_mult,
                       mpg.seats_three_years_back / mag.seats_three_years_back_final AS seats_three_years_back_mult,
                       mpg.sects_prior_year / mag.sects_prior_year_final AS sects_prior_year_mult,
                       mpg.sects_two_years_back / mag.sects_two_years_back_final AS sects_two_years_back_mult,
                       mpg.sects_three_years_back / mag.sects_three_years_back_final AS sects_three_years_back_mult
                  FROM utl_d_aa.crsmultaidygen mag
                  JOIN utl_d_aa.crsmultptrmgen mpg
                    ON mpg.graph_date = mag.graph_date
                   AND mpg.group1 = mag.group1
                   AND mpg.group2 = mag.group2
                 WHERE nvl(mpg.hours_prior_year, 0) + nvl(mpg.hours_two_years_back, 0) + nvl(mpg.hours_three_years_back, 0) > 0) mp
        -- IF THERE IS HISTORICAL DATA USE THIS JOIN
          JOIN (SELECT hist.aidy_code,
                      hist.grouping1,
                      hist.grouping2,
                      hist.group1,
                      hist.group2,
                      hist.pace_model,
                      CASE
                      WHEN hist.grouping1 = 'ALL' THEN
                       'ALL'
                      WHEN hist.grouping1 = 'College' THEN
                       'ALL'
                      ELSE
                       substr(hist.group1, 6, 1)
                      END AS gen_group1,
                      CASE
                      WHEN hist.grouping2 = 'ALL' THEN
                       'ALL'
                      ELSE
                       hist.group2
                      END AS gen_group2,
                      hist.hours_final_pace AS hours_pace_eoy,
                      hist.seats_final_pace AS seats_pace_eoy,
                      hist.sects_final_pace AS sects_pace_eoy,
                      rank() over(PARTITION BY group1, group2 ORDER BY aidy_code DESC) ranking
                 FROM utl_d_aa.crspaceaidyep hist) hist
            ON mp.group1 = hist.gen_group1
           AND mp.group2 = hist.gen_group2
           AND hist.ranking = 1
         WHERE nvl(CASE
                   WHEN hist.pace_model = 'Last Year' THEN
                    round(seats_pace_eoy * seats_prior_year_mult)
                   WHEN hist.pace_model = 'Two Years Back' THEN
                    round(seats_pace_eoy * seats_two_years_back_mult)
                   WHEN hist.pace_model = 'Three Years Back' THEN
                    round(seats_pace_eoy * seats_three_years_back_mult)
                   END, 0) > 0);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
-- END LOOP; -- c_terms
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
--------------------------------------------CHANGE LOG----------------------------------------
-- VERSION DATE        USERNAME    UPDATES
-- ---     12-17-2019  WGRIFFITH2  --Initial release
-- ---     08-11-2021  WGRIFFITH2  --Accommodating zero credit hour courses
---     06-28-2023  WGRIFFITH2  --Updates related to performance issues; adding logging
------------------------------------------------------------------------------------------------
END etl_aa_crsmultptrmgenx_refresh; --
PROCEDURE etl_aa_crspaceaidyep_refresh(jobnumber NUMBER, processid VARCHAR2, processname VARCHAR2) IS
--DECLARE
--- PARAMS
v_etl_date DATE := SYSDATE;
v_msg VARCHAR2(2000);
v_instance VARCHAR2(50) := upper('ALL'); -- inst from the jams job; used for determining instance
v_partition NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
-- v_mod         NUMBER := 5; -- number of partitions to be created

v_count NUMBER := 0;
v_elapsed NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id VARCHAR2(32);
v_proc VARCHAR2(100) := 'etl_aa_crspaceaidyep_refresh';
CURSOR c_terms IS
-- Using start_date - 80 corresponds with term logic in crshist_refresh
-- **This code cannot pull historically because it is using the crspace table
-- **so reloading historical data must be done ad-hoc with crshist table
SELECT DISTINCT aidy_code FROM utl_d_aa.crshist_stg stg WHERE stg.current_year = 'Y';
BEGIN
-- dbms_output.enable(buffer_size => NULL);
--
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
dbms_output.put_line('Started at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ';');
FOR rec IN c_terms
LOOP
v_count   := 0; -- reset count
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || rec.aidy_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
MERGE INTO utl_d_aa.crspaceaidyep t1
USING (SELECT DISTINCT rec.aidy_code AS aidy_code,
                       group1,
                       group2,
                       grouping1,
                       grouping2,
                       dim,
                       pace_model,
                       last_value(hours_current_actual ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) hours_final_ct,
                       last_value(seats_current_actual ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) seats_final_ct,
                       last_value(sects_current_actual ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) sects_final_ct,
                       last_value(hours_pacing ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) hours_final_pace,
                       last_value(seats_pacing ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) seats_final_pace,
                       last_value(sects_pacing ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) sects_final_pace,
                       SYSDATE AS activity_date
         FROM (SELECT cp.graph_date,
                      cp.group1,
                      cp.group2,
                      cp.grouping1,
                      cp.grouping2,
                      REPLACE(cp.group1 || '_' || cp.group2, ' ', '') AS dim,
                      CASE
                      WHEN cp.hours_lastyear_delta = least(cp.hours_lastyear_delta, cp.hours_twoback_delta, cp.hours_threeback_delta) THEN
                       'Last Year'
                      WHEN cp.hours_twoback_delta = least(cp.hours_lastyear_delta, cp.hours_twoback_delta, cp.hours_threeback_delta) THEN
                       'Two Years Back'
                      WHEN cp.hours_threeback_delta = least(cp.hours_lastyear_delta, cp.hours_twoback_delta, cp.hours_threeback_delta) THEN
                       'Three Years Back'
                      ELSE
                       'UNKNOWN'
                      END AS pace_model,
                      cp.hours_current_actual,
                      CASE
                      WHEN cp.hours_lastyear_delta = least(cp.hours_lastyear_delta, cp.hours_twoback_delta, cp.hours_threeback_delta) THEN
                       cp.hours_lastyear_pacing
                      WHEN cp.hours_twoback_delta = least(cp.hours_lastyear_delta, cp.hours_twoback_delta, cp.hours_threeback_delta) THEN
                       cp.hours_twoback_pacing
                      WHEN cp.hours_threeback_delta = least(cp.hours_lastyear_delta, cp.hours_twoback_delta, cp.hours_threeback_delta) THEN
                       cp.hours_threeback_pacing
                      END AS hours_pacing,
                      cp.seats_current_actual,
                      CASE
                      WHEN cp.seats_lastyear_delta = least(cp.seats_lastyear_delta, cp.seats_twoback_delta, cp.seats_threeback_delta) THEN
                       cp.seats_lastyear_pacing
                      WHEN cp.seats_twoback_delta = least(cp.seats_lastyear_delta, cp.seats_twoback_delta, cp.seats_threeback_delta) THEN
                       cp.seats_twoback_pacing
                      WHEN cp.seats_threeback_delta = least(cp.seats_lastyear_delta, cp.seats_twoback_delta, cp.seats_threeback_delta) THEN
                       cp.seats_threeback_pacing
                      END AS seats_pacing,
                      cp.sects_current_actual,
                      CASE
                      WHEN cp.sects_lastyear_delta = least(cp.sects_lastyear_delta, cp.sects_twoback_delta, cp.sects_threeback_delta) THEN
                       cp.sects_lastyear_pacing
                      WHEN cp.sects_twoback_delta = least(cp.sects_lastyear_delta, cp.sects_twoback_delta, cp.sects_threeback_delta) THEN
                       cp.sects_twoback_pacing
                      WHEN cp.sects_threeback_delta = least(cp.sects_lastyear_delta, cp.sects_twoback_delta, cp.sects_threeback_delta) THEN
                       cp.sects_threeback_pacing
                      END AS sects_pacing
                 FROM utl_d_aa.crspaceaidy cp)
        WHERE seats_pacing IS NOT NULL) t2
ON (t1.aidy_code = t2.aidy_code AND t1.group1 = t2.group1 AND t1.group2 = t2.group2)
WHEN MATCHED THEN
UPDATE
   SET t1.grouping1        = t2.grouping1,
       t1.grouping2        = t2.grouping2,
       t1.dim              = t2.dim,
       t1.pace_model       = t2.pace_model,
       t1.hours_final_ct   = t2.hours_final_ct,
       t1.seats_final_ct   = t2.seats_final_ct,
       t1.sects_final_ct   = t2.sects_final_ct,
       t1.hours_final_pace = t2.hours_final_pace,
       t1.seats_final_pace = t2.seats_final_pace,
       t1.sects_final_pace = t2.sects_final_pace,
       t1.activity_date    = t2.activity_date
WHEN NOT MATCHED THEN
INSERT
VALUES
(t2.aidy_code,
 t2.group1,
 t2.grouping1,
 t2.group2,
 t2.grouping2,
 t2.dim,
 t2.pace_model,
 t2.hours_final_ct,
 t2.seats_final_ct,
 t2.sects_final_ct,
 t2.hours_final_pace,
 t2.seats_final_pace,
 t2.sects_final_pace,
 t2.activity_date);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || rec.aidy_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
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
--------------------------------------------CHANGE LOG----------------------------------------
-- VERSION DATE        USERNAME    UPDATES
-- ---     12-17-2019  WGRIFFITH2  --Initial release
-- ---     05-06-2019  WGRIFFITH2  --Updating logic for timeframes to use the ADY start and end dates of 7/1-6/30
-- ---     08-11-2021  WGRIFFITH2  --Accommodating zero credit hour courses
---     06-28-2023  WGRIFFITH2  --Updates related to performance issues; adding logging
------------------------------------------------------------------------------------------------
END etl_aa_crspaceaidyep_refresh;
PROCEDURE etl_aa_crspaceaidy_refresh(jobnumber NUMBER, processid VARCHAR2, processname VARCHAR2) IS
--DECLARE
--- PARAMS
v_etl_date DATE := SYSDATE;
v_msg VARCHAR2(2000);
v_instance VARCHAR2(50) := upper('ALL'); -- inst from the jams job; used for determining instance
v_partition NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
-- v_mod         NUMBER := 5; -- number of partitions to be created
v_cpu NUMBER := 4; -- number of CPUs used for parallelization - do not exceed 20 CPUs [v_mod x --v_cpu] if running simultaneously
v_count NUMBER := 0;
v_elapsed NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id VARCHAR2(32);
v_proc VARCHAR2(100) := 'etl_aa_crspaceaidy_refresh';
CURSOR c_terms IS
SELECT *
  FROM (SELECT 'College' AS group1,
               'Campus' AS group2
          FROM dual
        UNION
        SELECT 'ALL' AS group1,
               'Campus' AS group2
          FROM dual
        UNION
        SELECT 'Course' AS group1,
               'Campus' AS group2
          FROM dual)
 WHERE 1 = 1;
BEGIN
-- dbms_output.enable(buffer_size => NULL);
--
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
utl_d_aa.truncate_table(v_table_name => 'crspaceaidy');
FOR rec IN c_terms
LOOP
v_count   := 0; -- reset count
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || rec.group1 || rec.group2 || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
INSERT /*+*/
INTO utl_d_aa.crspaceaidy_gtt
(graph_date,
 graph_today,
 report_date,
 aidy_code,
 group1,
 group2,
 hours_prior_year_mult,
 hours_two_years_back_mult,
 hours_three_years_back_mult,
 seats_prior_year_mult,
 seats_two_years_back_mult,
 seats_three_years_back_mult,
 sects_prior_year_mult,
 sects_two_years_back_mult,
 sects_three_years_back_mult,
 hours,
 seats,
 sects)
SELECT crsdt.graph_date AS graph_date,
       crsdt.graph_today AS graph_today,
       crsdt.report_date report_date,
       crsdt.aidy_code aidy_code,
       crsdt.group1,
       crsdt.group2,
       MAX(genmult.hours_prior_year_mult) AS hours_prior_year_mult,
       MAX(genmult.hours_two_years_back_mult) AS hours_two_years_back_mult,
       MAX(genmult.hours_three_years_back_mult) AS hours_three_years_back_mult,
       MAX(genmult.seats_prior_year_mult) AS seats_prior_year_mult,
       MAX(genmult.seats_two_years_back_mult) AS seats_two_years_back_mult,
       MAX(genmult.seats_three_years_back_mult) AS seats_three_years_back_mult,
       MAX(genmult.sects_prior_year_mult) AS sects_prior_year_mult,
       MAX(genmult.sects_two_years_back_mult) AS sects_two_years_back_mult,
       MAX(genmult.sects_three_years_back_mult) AS sects_three_years_back_mult,
       SUM(CASE
           WHEN crsdt.report_date <= trunc(v_etl_date) THEN
            a.hours
           ELSE
            NULL
           END) hours,
       SUM(CASE
           WHEN crsdt.report_date <= trunc(v_etl_date) THEN
            a.seats
           ELSE
            NULL
           END) seats,
       SUM(CASE
           WHEN crsdt.report_date <= trunc(v_etl_date) THEN
            a.sections
           ELSE
            NULL
           END) sects
  FROM utl_d_aa.crshistaidydim crsdt
  LEFT JOIN utl_d_aa.crshist a
    ON a.report_date = crsdt.report_date
   AND a.aidy_code = crsdt.aidy_code
   AND CASE
       WHEN rec.group1 = 'ALL' THEN
        'ALL'
       WHEN rec.group1 = 'College' THEN
        a.coll_desc
       WHEN rec.group1 = 'Course' THEN
        a.subj_code || ' ' || a.crse_numb
       END = crsdt.group1
   AND CASE
       WHEN rec.group2 = 'ALL' THEN
        'ALL'
       WHEN rec.group2 = 'Campus' THEN
        a.camp_code
       END = crsdt.group2
-- USING GENERALIZED PACE IF WE DONT HAVE ANY HISTORICAL DATA
  LEFT JOIN utl_d_aa.crsmultaidygen genmult
    ON genmult.graph_date = crsdt.graph_date
   AND genmult.group1 = crsdt.gen_group1
   AND genmult.group2 = crsdt.gen_group2
-- this line of code needs to be here to match up the joins between the ptrm tables in the subqquery above
-- in all but last week of the year, one record per week to reduce record counts
-- last week of the ADY runs daily numbers to continue to produce forecasts through 06/30 for the current ADY
 WHERE ((to_char(v_etl_date, 'mm/dd') NOT IN ('06/22', '06/23', '06/24', '06/25', '06/26', '06/27', '06/28', '06/29', '06/30') AND to_char(v_etl_date - (365.25 * 4), 'D') = to_char(crsdt.graph_date, 'D')) OR
       (to_char(v_etl_date, 'mm/dd') IN ('06/22', '06/23', '06/24', '06/25', '06/26', '06/27', '06/28', '06/29', '06/30')))
 GROUP BY crsdt.graph_date,
          crsdt.graph_today,
          crsdt.report_date,
          crsdt.aidy_code,
          crsdt.group1,
          crsdt.group2;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || rec.group1 || rec.group2 || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
INSERT /*+*/
INTO utl_d_aa.crspaceaidy
(graph_date,
 graph_today,
 grouping1,
 group1,
 grouping2,
 group2,
 is_historical,
 hours_current_actual,
 hours_prior_year,
 hours_two_years_back,
 hours_three_years_back,
 hours_lastyear_pacing,
 hours_twoback_pacing,
 hours_threeback_pacing,
 seats_current_actual,
 seats_prior_year,
 seats_two_years_back,
 seats_three_years_back,
 seats_lastyear_pacing,
 seats_twoback_pacing,
 seats_threeback_pacing,
 sects_current_actual,
 sects_prior_year,
 sects_two_years_back,
 sects_three_years_back,
 sects_lastyear_pacing,
 sects_twoback_pacing,
 sects_threeback_pacing,
 hours_lastyear_delta,
 hours_twoback_delta,
 hours_threeback_delta,
 seats_lastyear_delta,
 seats_twoback_delta,
 seats_threeback_delta,
 sects_lastyear_delta,
 sects_twoback_delta,
 sects_threeback_delta,
 activity_date)
SELECT graph_date,
       graph_today,
       rec.group1 AS grouping1,
       group1,
       rec.group2 AS grouping2,
       group2,
       is_historical,
       CASE
       WHEN hours_current_actual < .1 THEN
        0
       ELSE
        round(hours_current_actual, 0)
       END AS hours_current_actual, -- TURN THE ZERO CREDIT HOUR COURSES BACK TO 0 AND ROUND DOWN THE TOTALS
       CASE
       WHEN hours_prior_year < .1 THEN
        0
       ELSE
        round(hours_prior_year, 0)
       END AS hours_prior_year, -- TURN THE ZERO CREDIT HOUR COURSES BACK TO 0 AND ROUND DOWN THE TOTALS
       CASE
       WHEN hours_two_years_back < .1 THEN
        0
       ELSE
        round(hours_two_years_back, 0)
       END AS hours_two_years_back, -- TURN THE ZERO CREDIT HOUR COURSES BACK TO 0 AND ROUND DOWN THE TOTALS
       CASE
       WHEN hours_three_years_back < .1 THEN
        0
       ELSE
        round(hours_three_years_back, 0)
       END AS hours_three_years_back, -- TURN THE ZERO CREDIT HOUR COURSES BACK TO 0 AND ROUND DOWN THE TOTALS
       CASE
       WHEN hours_lastyear_pacing < .1 THEN
        0
       ELSE
        round(hours_lastyear_pacing, 0)
       END AS hours_lastyear_pacing, -- TURN THE ZERO CREDIT HOUR COURSES BACK TO 0 AND ROUND DOWN THE TOTALS
       CASE
       WHEN hours_twoback_pacing < .1 THEN
        0
       ELSE
        round(hours_twoback_pacing, 0)
       END AS hours_twoback_pacing, -- TURN THE ZERO CREDIT HOUR COURSES BACK TO 0 AND ROUND DOWN THE TOTALS
       CASE
       WHEN hours_threeback_pacing < .1 THEN
        0
       ELSE
        round(hours_threeback_pacing, 0)
       END AS hours_threeback_pacing, -- TURN THE ZERO CREDIT HOUR COURSES BACK TO 0 AND ROUND DOWN THE TOTALS
       seats_current_actual,
       seats_prior_year,
       seats_two_years_back,
       seats_three_years_back,
       seats_lastyear_pacing,
       seats_twoback_pacing,
       seats_threeback_pacing,
       sects_current_actual,
       sects_prior_year,
       sects_two_years_back,
       sects_three_years_back,
       sects_lastyear_pacing,
       sects_twoback_pacing,
       sects_threeback_pacing,
       round(abs(first_value(hours_lastyear_pacing ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) - last_value(hours_current_actual ignore NULLS)
                 over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following)), 0) AS hours_lastyear_delta,
       round(abs(first_value(hours_twoback_pacing ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) - last_value(hours_current_actual ignore NULLS)
                 over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following)), 0) AS hours_twoback_delta,
       round(abs(first_value(hours_threeback_pacing ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) - last_value(hours_current_actual ignore NULLS)
                 over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following)), 0) AS hours_threeback_delta,
       --
       abs(first_value(seats_lastyear_pacing ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) - last_value(seats_current_actual ignore NULLS)
           over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following)) AS seats_lastyear_delta,
       abs(first_value(seats_twoback_pacing ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) - last_value(seats_current_actual ignore NULLS)
           over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following)) AS seats_twoback_delta,
       abs(first_value(seats_threeback_pacing ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) - last_value(seats_current_actual ignore NULLS)
           over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following)) AS seats_threeback_delta,
       --
       abs(first_value(sects_lastyear_pacing ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) - last_value(sects_current_actual ignore NULLS)
           over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following)) AS sects_lastyear_delta,
       abs(first_value(sects_twoback_pacing ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) - last_value(sects_current_actual ignore NULLS)
           over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following)) AS sects_twoback_delta,
       abs(first_value(sects_threeback_pacing ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) - last_value(sects_current_actual ignore NULLS)
           over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following)) AS sects_threeback_delta,
       v_etl_date AS activity_date
  FROM (SELECT graph_date,
               graph_today,
               group1,
               group2,
               CASE
               WHEN hours_current_actual IS NOT NULL THEN
                'Y'
               ELSE
                'N'
               END AS is_historical,
               --
               hours_current_actual,
               hours_prior_year,
               hours_two_years_back,
               hours_three_years_back,
               --
               round(CASE
                     WHEN hours_current_actual IS NULL THEN
                      (last_value(hours_current_actual ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) /
                       first_value(CASE
                                                                                 WHEN graph_date = graph_today THEN
                                                                                  hours_prior_year_mult
                                                                                 END ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following)) * hours_prior_year_mult
                     END, 0) hours_lastyear_pacing,
               round(CASE
                     WHEN hours_current_actual IS NULL THEN
                      (last_value(hours_current_actual ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) /
                       first_value(CASE
                                                                                 WHEN graph_date = graph_today THEN
                                                                                  hours_two_years_back_mult
                                                                                 END ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following)) * hours_two_years_back_mult
                     END, 0) hours_twoback_pacing,
               round(CASE
                     WHEN hours_current_actual IS NULL THEN
                      (last_value(hours_current_actual ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) /
                       first_value(CASE
                                                                                 WHEN graph_date = graph_today THEN
                                                                                  hours_three_years_back_mult
                                                                                 END ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following)) * hours_three_years_back_mult
                     END, 0) hours_threeback_pacing,
               --
               seats_current_actual,
               seats_prior_year,
               seats_two_years_back,
               seats_three_years_back,
               round(CASE
                     WHEN seats_current_actual IS NULL THEN
                      (last_value(seats_current_actual ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) /
                       first_value(CASE
                                                                                 WHEN graph_date = graph_today THEN
                                                                                  seats_prior_year_mult
                                                                                 END ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following)) * seats_prior_year_mult
                     END, 0) seats_lastyear_pacing,
               round(CASE
                     WHEN seats_current_actual IS NULL THEN
                      (last_value(seats_current_actual ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) /
                       first_value(CASE
                                                                                 WHEN graph_date = graph_today THEN
                                                                                  seats_two_years_back_mult
                                                                                 END ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following)) * seats_two_years_back_mult
                     END, 0) seats_twoback_pacing,
               round(CASE
                     WHEN seats_current_actual IS NULL THEN
                      (last_value(seats_current_actual ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) /
                       first_value(CASE
                                                                                 WHEN graph_date = graph_today THEN
                                                                                  seats_three_years_back_mult
                                                                                 END ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following)) * seats_three_years_back_mult
                     END, 0) seats_threeback_pacing,
               --
               sects_current_actual,
               sects_prior_year,
               sects_two_years_back,
               sects_three_years_back,
               round(CASE
                     WHEN sects_current_actual IS NULL THEN
                      (last_value(sects_current_actual ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) /
                       first_value(CASE
                                                                                 WHEN graph_date = graph_today THEN
                                                                                  sects_prior_year_mult
                                                                                 END ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following)) * sects_prior_year_mult
                     END, 0) sects_lastyear_pacing,
               round(CASE
                     WHEN sects_current_actual IS NULL THEN
                      (last_value(sects_current_actual ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) /
                       first_value(CASE
                                                                                 WHEN graph_date = graph_today THEN
                                                                                  sects_two_years_back_mult
                                                                                 END ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following)) * sects_two_years_back_mult
                     END, 0) sects_twoback_pacing,
               round(CASE
                     WHEN sects_current_actual IS NULL THEN
                      (last_value(sects_current_actual ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) /
                       first_value(CASE
                                                                                 WHEN graph_date = graph_today THEN
                                                                                  sects_three_years_back_mult
                                                                                 END ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following)) * sects_three_years_back_mult
                     END, 0) sects_threeback_pacing
          FROM (SELECT graph_date,
                       graph_today,
                       group1,
                       group2,
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code000 THEN
                            hours
                           END) hours_current_actual,
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code000 THEN
                            hours_final_ct
                           END) hours_current_final,
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code101 THEN
                            hours
                           END) hours_prior_year,
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code101 THEN
                            hours_final_ct
                           END) hours_prior_final,
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code202 THEN
                            hours
                           END) hours_two_years_back,
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code202 THEN
                            hours / hours_final_ct
                           END) hours_two_years_back_per,
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code303 THEN
                            hours
                           END) hours_three_years_back,
                       --
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code000 THEN
                            seats
                           END) seats_current_actual,
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code000 THEN
                            seats_final_ct
                           END) seats_current_final,
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code101 THEN
                            seats
                           END) seats_prior_year,
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code101 THEN
                            seats_final_ct
                           END) seats_prior_final,
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code202 THEN
                            seats
                           END) seats_two_years_back,
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code303 THEN
                            seats
                           END) seats_three_years_back,
                       --
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code000 THEN
                            sects
                           END) sects_current_actual,
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code000 THEN
                            sects_final_ct
                           END) sects_current_final,
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code101 THEN
                            sects
                           END) sects_prior_year,
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code101 THEN
                            sects_final_ct
                           END) sects_prior_final,
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code202 THEN
                            sects
                           END) sects_two_years_back,
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code303 THEN
                            sects
                           END) sects_three_years_back,
                       MAX(hours_prior_year_mult) AS hours_prior_year_mult,
                       MAX(hours_two_years_back_mult) AS hours_two_years_back_mult,
                       MAX(hours_three_years_back_mult) AS hours_three_years_back_mult,
                       MAX(seats_prior_year_mult) AS seats_prior_year_mult,
                       MAX(seats_two_years_back_mult) AS seats_two_years_back_mult,
                       MAX(seats_three_years_back_mult) AS seats_three_years_back_mult,
                       MAX(sects_prior_year_mult) AS sects_prior_year_mult,
                       MAX(sects_two_years_back_mult) AS sects_two_years_back_mult,
                       MAX(sects_three_years_back_mult) AS sects_three_years_back_mult
                  FROM (SELECT graph_date,
                               graph_today,
                               report_date,
                               aidy_code,
                               group1,
                               group2,
                               hours,
                               last_value(hours ignore NULLS) over(PARTITION BY aidy_code, group1, group2 ORDER BY report_date RANGE BETWEEN unbounded preceding AND unbounded following) hours_final_ct,
                               seats,
                               last_value(seats ignore NULLS) over(PARTITION BY aidy_code, group1, group2 ORDER BY report_date RANGE BETWEEN unbounded preceding AND unbounded following) seats_final_ct,
                               sects,
                               last_value(sects ignore NULLS) over(PARTITION BY aidy_code, group1, group2 ORDER BY report_date RANGE BETWEEN unbounded preceding AND unbounded following) sects_final_ct,
                               hours_prior_year_mult,
                               hours_two_years_back_mult,
                               hours_three_years_back_mult,
                               seats_prior_year_mult,
                               seats_two_years_back_mult,
                               seats_three_years_back_mult,
                               sects_prior_year_mult,
                               sects_two_years_back_mult,
                               sects_three_years_back_mult
                          FROM utl_d_aa.crspaceaidy_gtt) sub0
                  JOIN (SELECT DISTINCT aidy_code,
                                       start404_yyyy,
                                       end404_yyyy,
                                       aidy_code303,
                                       aidy_code202,
                                       aidy_code101,
                                       aidy_code000
                         FROM utl_d_aa.crshist_stg stg) stg
                    ON stg.aidy_code = sub0.aidy_code
                 GROUP BY graph_date,
                          graph_today,
                          group1,
                          group2) tbl0) tbl1
 WHERE 1 = 1
   AND ((nvl(seats_current_actual, 0) > 0 AND graph_date <= graph_today) OR (nvl(seats_lastyear_pacing, 0) + nvl(seats_twoback_pacing, 0) + nvl(seats_threeback_pacing, 0) > 0 AND graph_date > graph_today));
v_count := SQL%ROWCOUNT;
COMMIT;
-- only outout every [n] loops
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || rec.group1 || rec.group2 || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
utl_d_aa.truncate_table(v_table_name => 'crspaceaidy_gtt');
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
--------------------------------------------CHANGE LOG----------------------------------------
-- VERSION DATE        USERNAME    UPDATES
-- ---     12-17-2019  WGRIFFITH2  --Initial release
-- ---     08-11-2021  WGRIFFITH2  --Accommodating zero credit hour courses
-- ---     06-28-2023  WGRIFFITH2  --Updates related to performance issues; adding logging
------------------------------------------------------------------------------------------------*/
END etl_aa_crspaceaidy_refresh; --
PROCEDURE etl_aa_crshistptrmdim_refresh(jobnumber NUMBER, processid VARCHAR2, processname VARCHAR2, inst VARCHAR2, nmbr NUMBER) IS
--DECLARE
--- PARAMS
v_etl_date DATE := SYSDATE;
v_msg VARCHAR2(2000);
v_instance VARCHAR2(50) := upper(inst); -- inst from the jams job; used for determining instance
v_partition NUMBER := nmbr; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_mod NUMBER := 5; -- number of partitions to be created
v_cpu NUMBER := 4; -- number of CPUs used for parallelization - do not exceed 20 CPUs [v_mod x --v_cpu] if running simultaneously
v_count NUMBER := 0;
v_elapsed NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id VARCHAR2(32);
v_proc VARCHAR2(100) := 'etl_aa_crshistptrmdim_refresh';
CURSOR c_terms IS
SELECT 'ALL' AS group1,
       'Campus' AS group2
  FROM dual
 WHERE 1 = 1
UNION
SELECT 'College' AS group1,
       'Campus' AS group2
  FROM dual
 WHERE 1 = 1
UNION
SELECT 'Course' AS group1,
       'Campus' AS group2
  FROM dual
 WHERE 1 = 1;
BEGIN
-- dbms_output.enable(buffer_size => NULL);
-- 
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
dbms_output.put_line('Started at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ';');
IF v_partition = 0 THEN
-- only truncate one time on the 0 partition
utl_d_aa.truncate_table(v_table_name => 'crshistptrmdim');
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'TRUNCATE' || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
ELSE
dbms_output.put_line(' procedure does not truncate on this partition');
END IF;
FOR rec IN c_terms
LOOP
v_count   := 0; -- reset count
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || rec.group1 || rec.group2 || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
INSERT /*+*/
INTO utl_d_aa.crshistptrmdim_gtt
(group1,
 group2,
 gen_group1,
 gen_group2,
 ptrm_code,
 semester,
 grouping1,
 grouping2)
SELECT DISTINCT CASE
                WHEN rec.group1 = 'ALL' THEN
                 'ALL'
                WHEN rec.group1 = 'College' THEN
                 hist.coll_desc
                WHEN rec.group1 = 'Course' THEN
                 hist.subj_code || ' ' || hist.crse_numb
                END group1,
                CASE
                WHEN rec.group2 = 'ALL' THEN
                 'ALL'
                WHEN rec.group2 = 'Campus' THEN
                 hist.camp_code
                END group2,
                CASE
                WHEN rec.group1 = 'ALL' THEN
                 'ALL'
                WHEN rec.group1 = 'College' THEN
                 'ALL'
                WHEN rec.group1 = 'Course' THEN
                 substr(hist.crse_numb, 1, 1)
                END AS gen_group1,
                CASE
                WHEN rec.group2 = 'ALL' THEN
                 'ALL'
                WHEN rec.group2 = 'Campus' THEN
                 hist.camp_code
                END AS gen_group2,
                hist.ptrm_code,
                stg.semester,
                rec.group1 AS grouping1,
                rec.group2 AS grouping2
  FROM utl_d_aa.crshist hist
  JOIN utl_d_aa.crshist_stg stg
    ON stg.aidy_code = hist.aidy_code
   AND stg.term_code = hist.term_code
   AND stg.ptrm_code = hist.ptrm_code
   AND (stg.current_year = 'Y' OR stg.previous_year = 'Y');
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || rec.group1 || rec.group2 || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
INSERT /*+*/
INTO utl_d_aa.crshistptrmdim
(report_date,
 graph_date,
 graph_today,
 aidy_code,
 semester,
 ptrm_code,
 group1,
 group2,
 gen_group1,
 gen_group2,
 activity_date,
 grouping1,
 grouping2)
SELECT DISTINCT date_value report_date,
                to_date(to_char(date_value, 'mm/dd') || CASE
                        WHEN to_char(date_value, 'yy') = substr(date_b_u_acyr, 1, 2) THEN
                         start404_yyyy
                        ELSE
                         end404_yyyy
                        END, 'mm/dd/yyyy') graph_date,
                to_date(to_char(v_etl_date, 'mm/dd') || CASE
                        WHEN to_char(v_etl_date, 'yy') = substr(stg.aidy_code000, 1, 2) THEN
                         start404_yyyy
                        ELSE
                         end404_yyyy
                        END, 'mm/dd/yyyy') graph_today,
                date_b_u_acyr AS aidy_code,
                crss.semester,
                crss.ptrm_code,
                crss.group1,
                crss.group2,
                gen_group1,
                gen_group2,
                v_etl_date AS activity_date,
                crss.grouping1,
                crss.grouping2
  FROM dm_common.date_d__01
  JOIN (SELECT DISTINCT stg.aidy_code,
                        start404_yyyy,
                        end404_yyyy,
                        aidy_code000
          FROM utl_d_aa.crshist_stg stg) stg
    ON stg.aidy_code = date_b_u_acyr
-- this will only pull dims that appear in the current ADY
  JOIN utl_d_aa.crshistptrmdim_gtt crss
    ON crss.grouping1 = rec.group1
   AND crss.grouping2 = rec.group2
 WHERE 1 = 1
   AND MOD(to_number(standard_hash(crss.group1 || crss.group1, 'MD5'), 'XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX'), v_mod) = v_partition
   AND to_char(date_value, 'mm/dd') <> '02/29'
   AND date_value >= to_date('07/01/20' || to_char(v_etl_date - (365 * 4), 'YY'), 'mm/dd/yyyy')
   AND date_value <= to_date('06/30/20' || to_char(v_etl_date + (365 * 1), 'YY'), 'mm/dd/yyyy');
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || rec.group1 || rec.group2 || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
utl_d_aa.truncate_table(v_table_name => 'crshistptrmdim_gtt');
END LOOP; -- c_terms
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
-- log any errors
EXCEPTION
WHEN OTHERS THEN
utl_d_aa.truncate_table(v_table_name => 'crshistptrmdim_gtt');
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
/*--------------------------------------------CHANGE LOG----------------------------------------
VERSION DATE        USERNAME    UPDATES
---     12-13-2019  WGRIFFITH2  --Initial release;
---     04-08-2022  WGRIFFITH2  --adding crshistptrmdim_gtt to help with loads
---     06-28-2023  WGRIFFITH2  --Updates related to performance issues; adding logging
---     11-07-2023  WGRIFFITH2  --adding parallelization to load balance the volume of record transactions TKT2809907
------------------------------------------------------------------------------------------------*/
END etl_aa_crshistptrmdim_refresh; --
PROCEDURE etl_aa_crshistaidydim_refresh(jobnumber NUMBER, processid VARCHAR2, processname VARCHAR2) IS
--DECLARE
--- PARAMS
v_etl_date DATE := SYSDATE;
v_msg VARCHAR2(2000);
v_instance VARCHAR2(50) := upper('ALL'); -- inst from the jams job; used for determining instance
v_partition NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
-- v_mod         NUMBER := 5; -- number of partitions to be created

v_count NUMBER := 0;
v_elapsed NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id VARCHAR2(32);
v_proc VARCHAR2(100) := 'etl_aa_crshistaidydim_refresh';
CURSOR c_terms IS
SELECT 'ALL' AS group1,
       'Campus' AS group2
  FROM dual
 WHERE 1 = 1
UNION
SELECT 'College' AS group1,
       'Campus' AS group2
  FROM dual
 WHERE 1 = 1
UNION
SELECT 'Course' AS group1,
       'Campus' AS group2
  FROM dual
 WHERE 1 = 1;
BEGIN
-- dbms_output.enable(buffer_size => NULL);
--
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
utl_d_aa.truncate_table(v_table_name => 'crshistaidydim');
FOR rec IN c_terms
LOOP
v_count   := 0; -- reset count
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || rec.group1 || rec.group2 || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
INSERT INTO utl_d_aa.crshistaidydim_gtt
(group1,
 group2,
 gen_group1,
 gen_group2)
SELECT DISTINCT CASE
                WHEN rec.group1 = 'ALL' THEN
                 'ALL'
                WHEN rec.group1 = 'College' THEN
                 a.coll_desc
                WHEN rec.group1 = 'Course' THEN
                 a.subj_code || ' ' || a.crse_numb
                END group1,
                CASE
                WHEN rec.group2 = 'ALL' THEN
                 'ALL'
                WHEN rec.group2 = 'Campus' THEN
                 a.camp_code
                END group2,
                CASE
                WHEN rec.group1 = 'ALL' THEN
                 'ALL'
                WHEN rec.group1 = 'College' THEN
                 'ALL'
                WHEN rec.group1 = 'Course' THEN
                 substr(a.crse_numb, 1, 1)
                END AS gen_group1,
                CASE
                WHEN rec.group2 = 'ALL' THEN
                 'ALL'
                WHEN rec.group2 = 'Campus' THEN
                 a.camp_code
                END AS gen_group2
  FROM utl_d_aa.crshist a
  JOIN utl_d_aa.crshist_stg stg
    ON stg.aidy_code = a.aidy_code
   AND stg.term_code = a.term_code
   AND stg.ptrm_code = a.ptrm_code
   AND (stg.current_year = 'Y' OR stg.previous_year = 'Y');
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || rec.group1 || rec.group2 || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
INSERT INTO utl_d_aa.crshistaidydim
(report_date,
 graph_date,
 graph_today,
 aidy_code,
 group1,
 group2,
 gen_group1,
 gen_group2,
 activity_date)
SELECT DISTINCT date_value report_date,
                to_date(to_char(date_value, 'mm/dd') || CASE
                        WHEN to_char(date_value, 'yy') = substr(date_b_u_acyr, 1, 2) THEN
                         start404_yyyy
                        ELSE
                         end404_yyyy
                        END, 'mm/dd/yyyy') graph_date,
                to_date(to_char(v_etl_date, 'mm/dd') || CASE
                        WHEN to_char(v_etl_date, 'yy') = substr(stg.aidy_code000, 1, 2) THEN
                         start404_yyyy
                        ELSE
                         end404_yyyy
                        END, 'mm/dd/yyyy') graph_today,
                date_b_u_acyr AS aidy_code,
                crss.group1,
                crss.group2,
                gen_group1,
                gen_group2,
                v_etl_date AS activity_date
  FROM dm_common.date_d__01
  JOIN (SELECT DISTINCT stg.aidy_code,
                        start404_yyyy,
                        end404_yyyy,
                        aidy_code000
          FROM utl_d_aa.crshist_stg stg) stg
    ON stg.aidy_code = date_b_u_acyr
-- this will only pull dims that appear in the current ADY
 CROSS JOIN utl_d_aa.crshistaidydim_gtt crss
 WHERE 1 = 1
   AND to_char(date_value, 'mm/dd') <> '02/29'
   AND date_value >= to_date('07/01/20' || to_char(v_etl_date - (365 * 4), 'YY'), 'mm/dd/yyyy')
   AND date_value <= to_date('06/30/20' || to_char(v_etl_date + (365 * 1), 'YY'), 'mm/dd/yyyy');
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || rec.group1 || rec.group2 || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
utl_d_aa.truncate_table(v_table_name => 'crshistaidydim_gtt');
END LOOP; -- c_terms
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
-- log any errors
EXCEPTION
WHEN OTHERS THEN
utl_d_aa.truncate_table(v_table_name => 'crshistaidydim_gtt');
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
/*--------------------------------------------CHANGE LOG----------------------------------------
VERSION DATE        USERNAME    UPDATES
---     12-13-2019  WGRIFFITH2  --Initial release;
---     04-08-2022  WGRIFFITH2  --adding crshistaidydim_gtt to help with loads
---     06-28-2023  WGRIFFITH2  --Updates related to performance issues; adding logging
------------------------------------------------------------------------------------------------*/
END etl_aa_crshistaidydim_refresh; --
PROCEDURE etl_aa_crsmultptrmgen_refresh(jobnumber NUMBER, processid VARCHAR2, processname VARCHAR2) IS
--DECLARE
--- PARAMS
v_etl_date DATE := SYSDATE;
v_msg VARCHAR2(2000);
v_instance VARCHAR2(50) := upper('ALL'); -- inst from the jams job; used for determining instance
v_partition NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
-- v_mod         NUMBER := 5; -- number of partitions to be created

v_count NUMBER := 0;
v_elapsed NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id VARCHAR2(32);
v_proc VARCHAR2(100) := 'etl_aa_crsmultptrmgen_refresh';
CURSOR c_terms IS
SELECT *
  FROM (SELECT 'ALL' AS group1,
               'R' AS group2
          FROM dual
        UNION
        SELECT 'ALL' AS group1,
               'D' AS group2
          FROM dual
        UNION --
        SELECT '0' AS group1,
               'R' AS group2
          FROM dual
        UNION
        SELECT '0' AS group1,
               'D' AS group2
          FROM dual
        UNION --
        SELECT '1' AS group1,
               'R' AS group2
          FROM dual
        UNION
        SELECT '1' AS group1,
               'D' AS group2
          FROM dual
        UNION --
        SELECT '2' AS group1,
               'R' AS group2
          FROM dual
        UNION
        SELECT '2' AS group1,
               'D' AS group2
          FROM dual
        UNION
        SELECT '3' AS group1,
               'R' AS group2
          FROM dual
        UNION
        SELECT '3' AS group1,
               'D' AS group2
          FROM dual
        UNION --
        SELECT '4' AS group1,
               'R' AS group2
          FROM dual
        UNION
        SELECT '4' AS group1,
               'D' AS group2
          FROM dual
        UNION
        SELECT '5' AS group1,
               'R' AS group2
          FROM dual
        UNION
        SELECT '5' AS group1,
               'D' AS group2
          FROM dual
        UNION
        SELECT '6' AS group1,
               'R' AS group2
          FROM dual
        UNION
        SELECT '6' AS group1,
               'D' AS group2
          FROM dual
        UNION
        SELECT '7' AS group1,
               'R' AS group2
          FROM dual
        UNION
        SELECT '7' AS group1,
               'D' AS group2
          FROM dual
        UNION --
        SELECT '8' AS group1,
               'R' AS group2
          FROM dual
        UNION
        SELECT '8' AS group1,
               'D' AS group2
          FROM dual
        UNION
        SELECT '9' AS group1,
               'R' AS group2
          FROM dual
        UNION
        SELECT '9' AS group1,
               'D' AS group2
          FROM dual)
 WHERE 1 = 1;
BEGIN
-- dbms_output.enable(buffer_size => NULL);
--
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
dbms_output.put_line('Started at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ';');
utl_d_aa.truncate_table(v_table_name => 'crsmultptrmgen');
FOR rec IN c_terms
LOOP
v_count   := 0; -- reset count
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || rec.group1 || rec.group2 || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
INSERT INTO utl_d_aa.crsmultptrmgen
(graph_date,
 semester,
 ptrm_code,
 group1,
 group2,
 hours_prior_year_mult,
 hours_prior_year,
 hours_prior_year_final,
 hours_two_years_back_mult,
 hours_two_years_back,
 hours_two_years_back_final,
 hours_three_years_back_mult,
 hours_three_years_back,
 hours_three_years_back_final,
 seats_prior_year_mult,
 seats_prior_year,
 seats_prior_year_final,
 seats_two_years_back_mult,
 seats_two_years_back,
 seats_two_years_back_final,
 seats_three_years_back_mult,
 seats_three_years_back,
 seats_three_years_back_final,
 sects_prior_year_mult,
 sects_prior_year,
 sects_prior_year_final,
 sects_two_years_back_mult,
 sects_two_years_back,
 sects_two_years_back_final,
 sects_three_years_back_mult,
 sects_three_years_back,
 sects_three_years_back_final,
 activity_date)
SELECT sub0.graph_date,
       stg.semester,
       stg.ptrm_code,
       sub0.group1,
       sub0.group2,
       -- ** these mults are based on the measure of the total of the AIDY **
       MAX(CASE
           WHEN report_year = aidy_code101 THEN
            hours / hours_final_ct
           END) hours_prior_year_mult,
       MAX(CASE
           WHEN report_year = aidy_code101 THEN
            hours
           END) hours_prior_year,
       MAX(CASE
           WHEN report_year = aidy_code101 THEN
            hours_final_ct
           END) hours_prior_year_final,
       --
       MAX(CASE
           WHEN report_year = aidy_code202 THEN
            hours / hours_final_ct
           END) hours_two_years_back_mult,
       MAX(CASE
           WHEN report_year = aidy_code202 THEN
            hours
           END) hours_two_years_back,
       MAX(CASE
           WHEN report_year = aidy_code202 THEN
            hours_final_ct
           END) hours_two_years_back_final,
       --
       MAX(CASE
           WHEN report_year = aidy_code303 THEN
            hours / hours_final_ct
           END) hours_three_years_back_mult,
       MAX(CASE
           WHEN report_year = aidy_code303 THEN
            hours
           END) hours_three_years_back,
       MAX(CASE
           WHEN report_year = aidy_code303 THEN
            hours_final_ct
           END) hours_three_years_back_final,
       --
       MAX(CASE
           WHEN report_year = aidy_code101 THEN
            seats / seats_final_ct
           END) seats_prior_year_mult,
       MAX(CASE
           WHEN report_year = aidy_code101 THEN
            seats
           END) seats_prior_year,
       MAX(CASE
           WHEN report_year = aidy_code101 THEN
            seats_final_ct
           END) seats_prior_year_final,
       --
       MAX(CASE
           WHEN report_year = aidy_code202 THEN
            seats / seats_final_ct
           END) seats_two_years_back_mult,
       MAX(CASE
           WHEN report_year = aidy_code202 THEN
            seats
           END) seats_two_years_back,
       MAX(CASE
           WHEN report_year = aidy_code202 THEN
            seats_final_ct
           END) seats_two_years_back_final,
       --
       MAX(CASE
           WHEN report_year = aidy_code303 THEN
            seats / seats_final_ct
           END) seats_three_years_back_mult,
       MAX(CASE
           WHEN report_year = aidy_code303 THEN
            seats
           END) seats_three_years_back,
       MAX(CASE
           WHEN report_year = aidy_code303 THEN
            seats_final_ct
           END) seats_three_years_back_final,
       --
       MAX(CASE
           WHEN report_year = aidy_code101 THEN
            sects / sects_final_ct
           END) sects_prior_year_mult,
       MAX(CASE
           WHEN report_year = aidy_code101 THEN
            sects
           END) sects_prior_year,
       MAX(CASE
           WHEN report_year = aidy_code101 THEN
            sects_final_ct
           END) sects_prior_year_final,
       --
       MAX(CASE
           WHEN report_year = aidy_code202 THEN
            sects / sects_final_ct
           END) sects_two_years_back_mult,
       MAX(CASE
           WHEN report_year = aidy_code202 THEN
            sects
           END) sects_two_years_back,
       MAX(CASE
           WHEN report_year = aidy_code202 THEN
            sects_final_ct
           END) sects_two_years_back_final,
       --
       MAX(CASE
           WHEN report_year = aidy_code303 THEN
            sects / sects_final_ct
           END) sects_three_years_back_mult,
       MAX(CASE
           WHEN report_year = aidy_code303 THEN
            sects
           END) sects_three_years_back,
       MAX(CASE
           WHEN report_year = aidy_code303 THEN
            sects_final_ct
           END) sects_three_years_back_final,
       --
       v_etl_date AS activity_date
  FROM (SELECT graph_date,
               ptrm_code,
               semester,
               report_date,
               report_year,
               group1,
               group2,
               hours,
               last_value(hours) over(PARTITION BY report_year, semester, ptrm_code, group1, group2 ORDER BY report_date RANGE BETWEEN unbounded preceding AND unbounded following) hours_final_ct,
               seats,
               last_value(seats) over(PARTITION BY report_year, semester, ptrm_code, group1, group2 ORDER BY report_date RANGE BETWEEN unbounded preceding AND unbounded following) seats_final_ct,
               sects,
               last_value(sects) over(PARTITION BY report_year, semester, ptrm_code, group1, group2 ORDER BY report_date RANGE BETWEEN unbounded preceding AND unbounded following) sects_final_ct
          FROM (SELECT to_date(to_char(hist.report_date, 'mm/dd') || CASE
                               WHEN to_char(hist.report_date, 'yy') = substr(hist.aidy_code, 1, 2) THEN
                                start404_yyyy
                               ELSE
                                end404_yyyy
                               END, 'mm/dd/yyyy') graph_date,
                       hist.report_date report_date,
                       hist.aidy_code report_year,
                       stg.semester, --FAL, SPR, SUM
                       hist.ptrm_code,
                       SUM(hist.hours) hours,
                       SUM(hist.seats) seats,
                       SUM(hist.sections) sects,
                       rec.group1 AS group1,
                       rec.group2 AS group2
                  FROM utl_d_aa.crshist hist
                  JOIN utl_d_aa.crshist_stg stg
                    ON stg.term_code = hist.term_code
                   AND stg.ptrm_code = hist.ptrm_code
                      --AND hist.subj_code IN ('BUSI', 'ACCT', 'COUC' ,'UNIV')
                   AND stg.current_year <> 'Y'
                 WHERE 1 = 1
                   AND to_char(hist.report_date, 'mm/dd') <> '02/29'
                   AND hist.report_date >= to_date('07/01/20' || substr(hist.aidy_code, 1, 2), 'mm/dd/yyyy')
                   AND hist.report_date <= to_date('06/30/20' || substr(hist.aidy_code, 3, 2), 'mm/dd/yyyy')
                   AND substr(hist.crse_numb, 1, 1) = CASE
                       WHEN rec.group1 = 'ALL' THEN
                        substr(hist.crse_numb, 1, 1)
                       ELSE
                        rec.group1
                       END
                   AND hist.camp_code = CASE
                       WHEN rec.group2 = 'ALL' THEN
                        hist.camp_code
                       ELSE
                        rec.group2
                       END
                 GROUP BY hist.report_date,
                          stg.semester,
                          hist.ptrm_code,
                          hist.aidy_code,
                          to_date(to_char(hist.report_date, 'mm/dd') || CASE
                                  WHEN to_char(hist.report_date, 'yy') = substr(hist.aidy_code, 1, 2) THEN
                                   start404_yyyy
                                  ELSE
                                   end404_yyyy
                                  END, 'mm/dd/yyyy')
                HAVING SUM(hist.hours) > .1 -- DO NOT WANT ZERO CREDIT HOUR COURSES HERE
                )
        -- this line of code needs to be here to match up the joins between the ptrm tables in the subqquery above
        -- in all but last week of the year, one record per week to reduce record counts
        -- last week of the ADY runs daily numbers to continue to produce forecasts through 06/30 for the current ADY
         WHERE ((to_char(v_etl_date, 'mm/dd') NOT IN ('06/22', '06/23', '06/24', '06/25', '06/26', '06/27', '06/28', '06/29', '06/30') AND to_char(v_etl_date - (365.25 * 4), 'D') = to_char(graph_date, 'D')
               ) OR (to_char(v_etl_date, 'mm/dd') IN ('06/22', '06/23', '06/24', '06/25', '06/26', '06/27', '06/28', '06/29', '06/30')))) sub0
  JOIN (SELECT DISTINCT aidy_code,
                        ptrm_code,
                        semester,
                        start404_yyyy,
                        end404_yyyy,
                        aidy_code303,
                        aidy_code202,
                        aidy_code101,
                        aidy_code000
          FROM utl_d_aa.crshist_stg) stg
    ON stg.aidy_code = sub0.report_year
   AND stg.semester = sub0.semester
   AND stg.ptrm_code = sub0.ptrm_code
 GROUP BY sub0.graph_date,
          stg.ptrm_code,
          stg.semester,
          sub0.group1,
          sub0.group2;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || rec.group1 || rec.group2 || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
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
--------------------------------------------CHANGE LOG----------------------------------------
-- VERSION DATE        USERNAME    UPDATES
-- ---     12-17-2019  WGRIFFITH2  --Initial release
-- ---     08-11-2021  WGRIFFITH2  --Accommodating zero credit hour courses
---     06-28-2023  WGRIFFITH2  --Updates related to performance issues; adding logging
------------------------------------------------------------------------------------------------*/
END etl_aa_crsmultptrmgen_refresh; --
PROCEDURE etl_aa_crsmultaidygen_refresh(jobnumber NUMBER, processid VARCHAR2, processname VARCHAR2) IS
--DECLARE
--- PARAMS
v_etl_date DATE := SYSDATE;
v_msg VARCHAR2(2000);
v_instance VARCHAR2(50) := upper('ALL'); -- inst from the jams job; used for determining instance
v_partition NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
-- v_mod         NUMBER := 5; -- number of partitions to be created

v_count NUMBER := 0;
v_elapsed NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id VARCHAR2(32);
v_proc VARCHAR2(100) := 'etl_aa_crsmultaidygen_refresh';
CURSOR c_terms IS
SELECT *
  FROM (SELECT 'ALL' AS group1,
               'R' AS group2
          FROM dual
        UNION
        SELECT 'ALL' AS group1,
               'D' AS group2
          FROM dual
        UNION --
        SELECT '0' AS group1,
               'R' AS group2
          FROM dual
        UNION
        SELECT '0' AS group1,
               'D' AS group2
          FROM dual
        UNION --
        SELECT '1' AS group1,
               'R' AS group2
          FROM dual
        UNION
        SELECT '1' AS group1,
               'D' AS group2
          FROM dual
        UNION --
        SELECT '2' AS group1,
               'R' AS group2
          FROM dual
        UNION
        SELECT '2' AS group1,
               'D' AS group2
          FROM dual
        UNION
        SELECT '3' AS group1,
               'R' AS group2
          FROM dual
        UNION
        SELECT '3' AS group1,
               'D' AS group2
          FROM dual
        UNION --
        SELECT '4' AS group1,
               'R' AS group2
          FROM dual
        UNION
        SELECT '4' AS group1,
               'D' AS group2
          FROM dual
        UNION
        SELECT '5' AS group1,
               'R' AS group2
          FROM dual
        UNION
        SELECT '5' AS group1,
               'D' AS group2
          FROM dual
        UNION
        SELECT '6' AS group1,
               'R' AS group2
          FROM dual
        UNION
        SELECT '6' AS group1,
               'D' AS group2
          FROM dual
        UNION
        SELECT '7' AS group1,
               'R' AS group2
          FROM dual
        UNION
        SELECT '7' AS group1,
               'D' AS group2
          FROM dual
        UNION --
        SELECT '8' AS group1,
               'R' AS group2
          FROM dual
        UNION
        SELECT '8' AS group1,
               'D' AS group2
          FROM dual
        UNION
        SELECT '9' AS group1,
               'R' AS group2
          FROM dual
        UNION
        SELECT '9' AS group1,
               'D' AS group2
          FROM dual)
 WHERE 1 = 1;
BEGIN
-- dbms_output.enable(buffer_size => NULL);
--
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
dbms_output.put_line('Started at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ';');
utl_d_aa.truncate_table(v_table_name => 'crsmultaidygen');
FOR rec IN c_terms
LOOP
v_count   := 0; -- reset count
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || rec.group1 || rec.group2 || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
INSERT INTO utl_d_aa.crsmultaidygen
(graph_date,
 group1,
 group2,
 hours_prior_year_mult,
 hours_prior_year,
 hours_prior_year_final,
 hours_two_years_back_mult,
 hours_two_years_back,
 hours_two_years_back_final,
 hours_three_years_back_mult,
 hours_three_years_back,
 hours_three_years_back_final,
 seats_prior_year_mult,
 seats_prior_year,
 seats_prior_year_final,
 seats_two_years_back_mult,
 seats_two_years_back,
 seats_two_years_back_final,
 seats_three_years_back_mult,
 seats_three_years_back,
 seats_three_years_back_final,
 sects_prior_year_mult,
 sects_prior_year,
 sects_prior_year_final,
 sects_two_years_back_mult,
 sects_two_years_back,
 sects_two_years_back_final,
 sects_three_years_back_mult,
 sects_three_years_back,
 sects_three_years_back_final,
 activity_date)
SELECT graph_date,
       group1,
       group2,
       --
       MAX(CASE
           WHEN report_year = aidy_code101 THEN
            hours / hours_final_ct
           END) hours_prior_year_mult,
       MAX(CASE
           WHEN report_year = aidy_code101 THEN
            hours
           END) hours_prior_year,
       MAX(CASE
           WHEN report_year = aidy_code101 THEN
            hours_final_ct
           END) hours_prior_year_final,
       --
       MAX(CASE
           WHEN report_year = aidy_code202 THEN
            hours / hours_final_ct
           END) hours_two_years_back_mult,
       MAX(CASE
           WHEN report_year = aidy_code202 THEN
            hours
           END) hours_two_years_back,
       MAX(CASE
           WHEN report_year = aidy_code202 THEN
            hours_final_ct
           END) hours_two_years_back_final,
       --
       MAX(CASE
           WHEN report_year = aidy_code303 THEN
            hours / hours_final_ct
           END) hours_three_years_back_mult,
       MAX(CASE
           WHEN report_year = aidy_code303 THEN
            hours
           END) hours_three_years_back,
       MAX(CASE
           WHEN report_year = aidy_code303 THEN
            hours_final_ct
           END) hours_three_years_back_final,
       --
       MAX(CASE
           WHEN report_year = aidy_code101 THEN
            seats / seats_final_ct
           END) seats_prior_year_mult,
       MAX(CASE
           WHEN report_year = aidy_code101 THEN
            seats
           END) seats_prior_year,
       MAX(CASE
           WHEN report_year = aidy_code101 THEN
            seats_final_ct
           END) seats_prior_year_final,
       --
       MAX(CASE
           WHEN report_year = aidy_code202 THEN
            seats / seats_final_ct
           END) seats_two_years_back_mult,
       MAX(CASE
           WHEN report_year = aidy_code202 THEN
            seats
           END) seats_two_years_back,
       MAX(CASE
           WHEN report_year = aidy_code202 THEN
            seats_final_ct
           END) seats_two_years_back_final,
       --
       MAX(CASE
           WHEN report_year = aidy_code303 THEN
            seats / seats_final_ct
           END) seats_three_years_back_mult,
       MAX(CASE
           WHEN report_year = aidy_code303 THEN
            seats
           END) seats_three_years_back,
       MAX(CASE
           WHEN report_year = aidy_code303 THEN
            seats_final_ct
           END) seats_three_years_back_final,
       --
       MAX(CASE
           WHEN report_year = aidy_code101 THEN
            sects / sects_final_ct
           END) sects_prior_year_mult,
       MAX(CASE
           WHEN report_year = aidy_code101 THEN
            sects
           END) sects_prior_year,
       MAX(CASE
           WHEN report_year = aidy_code101 THEN
            sects_final_ct
           END) sects_prior_year_final,
       --
       MAX(CASE
           WHEN report_year = aidy_code202 THEN
            sects / sects_final_ct
           END) sects_two_years_back_mult,
       MAX(CASE
           WHEN report_year = aidy_code202 THEN
            sects
           END) sects_two_years_back,
       MAX(CASE
           WHEN report_year = aidy_code202 THEN
            sects_final_ct
           END) sects_two_years_back_final,
       --
       MAX(CASE
           WHEN report_year = aidy_code303 THEN
            sects / sects_final_ct
           END) sects_three_years_back_mult,
       MAX(CASE
           WHEN report_year = aidy_code303 THEN
            sects
           END) sects_three_years_back,
       MAX(CASE
           WHEN report_year = aidy_code303 THEN
            sects_final_ct
           END) sects_three_years_back_final,
       --
       v_etl_date AS activity_date
  FROM (SELECT graph_date,
               report_date,
               report_year,
               group1,
               group2,
               hours,
               last_value(hours) over(PARTITION BY report_year, group1, group2 ORDER BY report_date RANGE BETWEEN unbounded preceding AND unbounded following) hours_final_ct,
               seats,
               last_value(seats) over(PARTITION BY report_year, group1, group2 ORDER BY report_date RANGE BETWEEN unbounded preceding AND unbounded following) seats_final_ct,
               sects,
               last_value(sects) over(PARTITION BY report_year, group1, group2 ORDER BY report_date RANGE BETWEEN unbounded preceding AND unbounded following) sects_final_ct
          FROM (SELECT to_date(to_char(hist.report_date, 'mm/dd') || CASE
                               WHEN to_char(hist.report_date, 'yy') = substr(hist.aidy_code, 1, 2) THEN
                                start404_yyyy
                               ELSE
                                end404_yyyy
                               END, 'mm/dd/yyyy') graph_date,
                       hist.report_date report_date,
                       hist.aidy_code report_year,
                       SUM(hist.hours) hours,
                       SUM(hist.seats) seats,
                       SUM(hist.sections) sects,
                       rec.group1 AS group1,
                       rec.group2 AS group2
                  FROM utl_d_aa.crshist hist
                  JOIN utl_d_aa.crshist_stg stg
                    ON stg.term_code = hist.term_code
                   AND stg.ptrm_code = hist.ptrm_code
                   AND stg.current_year <> 'Y'
                 WHERE 1 = 1
                      --AND hist.subj_code IN ('BUSI', 'ACCT', 'COUC', 'UNIV')
                   AND to_char(hist.report_date, 'mm/dd') <> '02/29'
                   AND hist.report_date >= to_date('07/01/20' || substr(hist.aidy_code, 1, 2), 'mm/dd/yyyy')
                   AND hist.report_date <= to_date('06/30/20' || substr(hist.aidy_code, 3, 2), 'mm/dd/yyyy')
                   AND substr(hist.crse_numb, 1, 1) = CASE
                       WHEN rec.group1 = 'ALL' THEN
                        substr(hist.crse_numb, 1, 1)
                       ELSE
                        rec.group1
                       END
                   AND hist.camp_code = CASE
                       WHEN rec.group2 = 'ALL' THEN
                        hist.camp_code
                       ELSE
                        rec.group2
                       END
                 GROUP BY hist.report_date,
                          hist.aidy_code,
                          to_date(to_char(hist.report_date, 'mm/dd') || CASE
                                  WHEN to_char(hist.report_date, 'yy') = substr(hist.aidy_code, 1, 2) THEN
                                   start404_yyyy
                                  ELSE
                                   end404_yyyy
                                  END, 'mm/dd/yyyy')
                HAVING SUM(hist.hours) > .1 -- DO NOT WANT ZERO CREDIT HOUR COURSES HERE
                )
        -- this line of code needs to be here to match up the joins between the ptrm tables in the subqquery above
        -- in all but last week of the year, one record per week to reduce record counts
        -- last week of the ADY runs daily numbers to continue to produce forecasts through 06/30 for the current ADY
         WHERE ((to_char(v_etl_date, 'mm/dd') NOT IN ('06/22', '06/23', '06/24', '06/25', '06/26', '06/27', '06/28', '06/29', '06/30') AND to_char(v_etl_date - (365.25 * 4), 'D') = to_char(graph_date, 'D')
               ) OR (to_char(v_etl_date, 'mm/dd') IN ('06/22', '06/23', '06/24', '06/25', '06/26', '06/27', '06/28', '06/29', '06/30')))) sub0
  JOIN (SELECT DISTINCT aidy_code,
                        start404_yyyy,
                        end404_yyyy,
                        aidy_code303,
                        aidy_code202,
                        aidy_code101,
                        aidy_code000
          FROM utl_d_aa.crshist_stg stg) stg
    ON stg.aidy_code = sub0.report_year
 GROUP BY graph_date,
          group1,
          group2;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || rec.group1 || rec.group2 || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
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
--------------------------------------------CHANGE LOG----------------------------------------
-- VERSION DATE        USERNAME    UPDATES
-- ---     12-17-2019  WGRIFFITH2  --Initial release
-- ---     08-11-2021  WGRIFFITH2  --Accommodating zero credit hour courses
---     06-28-2023  WGRIFFITH2  --Updates related to performance issues; adding logging
------------------------------------------------------------------------------------------------*/
END etl_aa_crsmultaidygen_refresh; --
PROCEDURE etl_aa_crshist_refresh(jobnumber NUMBER, processid VARCHAR2, processname VARCHAR2) IS
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
v_proc        VARCHAR2(100) := 'etl_aa_crshist_refresh';
CURSOR c_terms IS
SELECT terms.fa_proc_year aidy_code,
       terms.term_code,
       terms.semester,
       to_date('07/01/20' || substr(terms.fa_proc_year, 1, 2), 'mm/dd/yyyy') stage_start,
       to_date('06/30/20' || substr(terms.fa_proc_year, 3, 2), 'mm/dd/yyyy') stage_end,
      to_date(to_char(trunc(terms.start_date + dates.numb) + (4 / 24), 'MM/DD/YYYY hh24:mi:ss'), 'MM/DD/YYYY hh24:mi:ss') AS ytd_timestamp
  FROM zbtm.terms_by_group_v terms
-- START TRACKING DATA 90 DAYS PRIOR TO TERM START DATE
  JOIN (SELECT LEVEL - 90 numb FROM dual CONNECT BY LEVEL <= 410) dates
    ON terms.start_date + dates.numb <= to_date('06/30/20' || substr(terms.fa_proc_year, 3, 2), 'mm/dd/yyyy') -- cut off for the end of ADY
   AND terms.start_date + dates.numb <= SYSDATE
   AND terms.term_code BETWEEN '202040' AND '203040'
   AND terms.group_code IN ('STD', 'MED')
   AND terms.semester IN ('FAL', 'SPR', 'SUM')
  LEFT JOIN (SELECT DISTINCT report_date,
                             term_code,
                             aidy_code
               FROM utl_d_aa.crshist hist) hist
    ON hist.aidy_code = terms.fa_proc_year
   AND hist.term_code = terms.term_code
   AND terms.start_date + dates.numb = hist.report_date
 WHERE hist.report_date IS NULL
   AND terms.start_date + dates.numb >= to_date('07/01/20' || substr(terms.fa_proc_year, 1, 2), 'mm/dd/yyyy')
   AND terms.start_date + dates.numb <= to_date('06/30/20' || substr(terms.fa_proc_year, 3, 2), 'mm/dd/yyyy')
 ORDER BY 1 ASC,
          2 ASC,
          6 ASC;
BEGIN
-- dbms_output.enable(buffer_size => NULL);
--
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
utl_d_aa.truncate_table(v_table_name => 'crshist_stg');
INSERT INTO utl_d_aa.crshist_stg
(aidy_code,
 term_code,
 term_start_date,
 term_end_date,
 semester,
 semester_desc,
 ptrm_code,
 ptrm_start_date,
 ptrm_end_date,
 current_year,
 previous_year,
 start404_yyyy,
 end404_yyyy,
 aidy_code303,
 aidy_code202,
 aidy_code101,
 aidy_code000)
SELECT DISTINCT t.fa_proc_year aidy_code,
                t.term_code,
                t.start_date term_start_date,
                t.end_date term_end_date,
                t.semester,
                t.semester_desc,
                sobptrm_ptrm_code AS ptrm_code,
                sobptrm_start_date AS ptrm_start_date,
                sobptrm_end_date ptrm_end_date,
                CASE
                WHEN t.fa_proc_year = (SELECT MIN(t1.fa_proc_year - 0) start_yyyy
                                         FROM zbtm.terms_by_group_v t1
                                        WHERE (v_etl_date BETWEEN to_date('07/01/20' || substr(t1.fa_proc_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(t1.fa_proc_year, 3, 2), 'mm/dd/yyyy') OR
                                              v_etl_date + 14 BETWEEN to_date('07/01/20' || substr(t1.fa_proc_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(t1.fa_proc_year, 3, 2), 'mm/dd/yyyy'))) THEN
                 'Y'
                ELSE
                 'N'
                END AS current_year,
                CASE
                WHEN t.fa_proc_year = (SELECT MIN(t1.fa_proc_year - 101) start_yyyy
                                         FROM zbtm.terms_by_group_v t1
                                        WHERE (v_etl_date BETWEEN to_date('07/01/20' || substr(t1.fa_proc_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(t1.fa_proc_year, 3, 2), 'mm/dd/yyyy') OR
                                              v_etl_date + 14 BETWEEN to_date('07/01/20' || substr(t1.fa_proc_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(t1.fa_proc_year, 3, 2), 'mm/dd/yyyy'))) THEN
                 'Y'
                ELSE
                 'N'
                END AS previous_year,
                (SELECT MIN('20' || substr(t1.fa_proc_year - 404, 1, 2)) start_yyyy
                   FROM zbtm.terms_by_group_v t1
                  WHERE (v_etl_date BETWEEN to_date('07/01/20' || substr(t1.fa_proc_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(t1.fa_proc_year, 3, 2), 'mm/dd/yyyy') OR
                        v_etl_date + 14 BETWEEN to_date('07/01/20' || substr(t1.fa_proc_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(t1.fa_proc_year, 3, 2), 'mm/dd/yyyy'))) start404_yyyy,
                (SELECT MIN('20' || substr(t1.fa_proc_year - 404, 3, 2)) end_yyyy
                   FROM zbtm.terms_by_group_v t1
                  WHERE (v_etl_date BETWEEN to_date('07/01/20' || substr(t1.fa_proc_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(t1.fa_proc_year, 3, 2), 'mm/dd/yyyy') OR
                        v_etl_date + 14 BETWEEN to_date('07/01/20' || substr(t1.fa_proc_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(t1.fa_proc_year, 3, 2), 'mm/dd/yyyy'))) end404_yyyy,
                (SELECT MIN(t1.fa_proc_year - 303) start_yyyy
                   FROM zbtm.terms_by_group_v t1
                  WHERE (v_etl_date BETWEEN to_date('07/01/20' || substr(t1.fa_proc_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(t1.fa_proc_year, 3, 2), 'mm/dd/yyyy') OR
                        v_etl_date + 14 BETWEEN to_date('07/01/20' || substr(t1.fa_proc_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(t1.fa_proc_year, 3, 2), 'mm/dd/yyyy'))) aidy_code303,
                (SELECT MIN(t1.fa_proc_year - 202) start_yyyy
                   FROM zbtm.terms_by_group_v t1
                  WHERE (v_etl_date BETWEEN to_date('07/01/20' || substr(t1.fa_proc_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(t1.fa_proc_year, 3, 2), 'mm/dd/yyyy') OR
                        v_etl_date + 14 BETWEEN to_date('07/01/20' || substr(t1.fa_proc_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(t1.fa_proc_year, 3, 2), 'mm/dd/yyyy'))) aidy_code202,
                (SELECT MIN(t1.fa_proc_year - 101) start_yyyy
                   FROM zbtm.terms_by_group_v t1
                  WHERE (v_etl_date BETWEEN to_date('07/01/20' || substr(t1.fa_proc_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(t1.fa_proc_year, 3, 2), 'mm/dd/yyyy') OR
                        v_etl_date + 14 BETWEEN to_date('07/01/20' || substr(t1.fa_proc_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(t1.fa_proc_year, 3, 2), 'mm/dd/yyyy'))) aidy_code101,
                (SELECT MIN(t1.fa_proc_year - 0) start_yyyy
                   FROM zbtm.terms_by_group_v t1
                  WHERE (v_etl_date BETWEEN to_date('07/01/20' || substr(t1.fa_proc_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(t1.fa_proc_year, 3, 2), 'mm/dd/yyyy') OR
                        v_etl_date + 14 BETWEEN to_date('07/01/20' || substr(t1.fa_proc_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(t1.fa_proc_year, 3, 2), 'mm/dd/yyyy'))) aidy_code000
  FROM zbtm.terms_by_group_v t
  JOIN saturn.sobptrm
    ON sobptrm_term_code = t.term_code
   AND sobptrm_ptrm_code IN ('R', '1A', '1B', '1C', '1D', '1J', 'L')
 WHERE t.fa_proc_year IN (SELECT DISTINCT t.fa_proc_year aidy_code
                            FROM zbtm.terms_by_group_v t
                           WHERE t.end_date > v_etl_date - (365 * 5)
                             AND t.start_date < v_etl_date + 180
                             AND t.semester NOT IN ('WIN')
                             AND t.group_code IN ('STD', 'MED'))
   AND t.semester NOT IN ('WIN')
   AND t.group_code IN ('STD', 'MED');
COMMIT;
FOR rec IN c_terms
LOOP
v_count   := 0; -- reset count
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || rec.term_code || ' - ' || rec.ytd_timestamp || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
INSERT INTO utl_d_aa.crshist
(subj_code,
 crse_numb,
 term_code,
 aidy_code,
 semester,
 ptrm_code,
 camp_code,
 coll_code,
 coll_desc,
 sections,
 seats,
 hours,
 report_date,
 activity_date)
SELECT ssbsect_subj_code AS subj_code,
       ssbsect_crse_numb AS crse_numb,
       sfrstca_term_code AS term_code,
       rec.aidy_code AS aidy_code,
       rec.semester AS semester,
       nvl(ssbsect_ptrm_code, '00') AS ptrm_code,
       ssbsect_camp_code AS camp_code,
       scbcrse_coll_code AS coll_code,
       stvcoll_desc AS coll_desc,
       COUNT(DISTINCT sfrstca_crn) sections,
       COUNT(*) seats,
       -- this will get should rounded at the end of the progress
       SUM(CASE
           WHEN sfrstca_credit_hr < .1 THEN
            .0000001 -- this is to allow zero credit hour courses and not cause divisor oracle error
           ELSE
            sfrstca_credit_hr
           END) AS hours,
       trunc(rec.ytd_timestamp) AS report_date,
       SYSDATE AS activity_date
  FROM saturn.sfrstca
  JOIN saturn.stvrsts
    ON stvrsts_code = sfrstca_rsts_code
   AND stvrsts_incl_sect_enrl = 'Y' -- aligns with AA tables
      --      AND stvrsts_incl_assess = 'Y' -- aligns with EM MR;
      -- we are looking for ALL enrollments - including zero (0) credit hours
   AND sfrstca_term_code = rec.term_code
   AND sfrstca_rsts_date <= rec.ytd_timestamp
   AND sfrstca_source_cde = 'BASE'
   AND sfrstca_levl_code <> 'PD' -- must explicitly exclude PD
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
  JOIN zsaturn.szrlevl
    ON szrlevl_levl_code = sfrstca_levl_code -- join on course level NOT student
   AND szrlevl_is_univ = 'Y' -- student must be university level and in a program that has awardable credit
   AND szrlevl_has_awardable_cred = 'Y'
  LEFT JOIN saturn.scbcrse
    ON scbcrse_subj_code = ssbsect_subj_code
   AND scbcrse_crse_numb = ssbsect_crse_numb
   AND scbcrse_eff_term = (SELECT MAX(scbcrse2.scbcrse_eff_term)
                             FROM saturn.scbcrse scbcrse2
                            WHERE scbcrse2.scbcrse_subj_code = scbcrse.scbcrse_subj_code
                              AND scbcrse2.scbcrse_crse_numb = scbcrse.scbcrse_crse_numb
                              AND scbcrse2.scbcrse_eff_term <= rec.term_code)
  LEFT JOIN stvcoll
    ON stvcoll_code = scbcrse_coll_code
 GROUP BY ssbsect_subj_code,
          ssbsect_crse_numb,
          sfrstca_term_code,
          rec.aidy_code,
          rec.semester,
          nvl(ssbsect_ptrm_code, '00'),
          ssbsect_camp_code,
          scbcrse_coll_code,
          stvcoll_desc,
          rec.ytd_timestamp;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || rec.term_code || ' - ' || rec.ytd_timestamp || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
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
--------------------------------------------CHANGE LOG----------------------------------------
-- VERSION DATE        USERNAME    UPDATES
---     12-17-2019  WGRIFFITH2  --Initial release
---     05-06-2019  WGRIFFITH2  --Updating logic for timeframes to use the ADY start and end dates of 7/1-6/30
---     08-11-2021  WGRIFFITH2  --Accommodating zero credit hour courses
---     05-17-2023  WGRIFFITH2  --Dealing with EM courses and updating code to use job_log
---     09-25-2025  WGRIFFITH2  --Matching code to what shows in the PDB enrollments
------------------------------------------------------------------------------------------------*/
END etl_aa_crshist_refresh; --

procedure etl_aa_crspaceaidyep_luoa (jobnumber number, processid varchar2, processname varchar2) is
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
v_proc        VARCHAR2(100) := 'etl_aa_crspaceaidyep_luoa';
CURSOR c_terms IS
-- Using start_date - 80 corresponds with term logic in crshist_refresh
-- **This code cannot pull historically because it is using the crspace table
-- **so reloading historical data must be done ad-hoc with crshist table
SELECT DISTINCT aidy_code FROM utl_d_aa.crshist_stg stg WHERE stg.current_year = 'Y';
BEGIN
-- dbms_output.enable(buffer_size => NULL);
--
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
dbms_output.put_line('Started at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ';');
FOR rec IN c_terms
LOOP
v_count   := 0; -- reset count
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || rec.aidy_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
MERGE INTO utl_d_aa.crspaceaidyep_luoa t1
USING (SELECT DISTINCT rec.aidy_code AS aidy_code,
                       group1,
                       group2,
                       grouping1,
                       grouping2,
                       dim,
                       pace_model,
                       last_value(hours_current_actual ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) hours_final_ct,
                       last_value(seats_current_actual ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) seats_final_ct,
                       last_value(sects_current_actual ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) sects_final_ct,
                       last_value(hours_pacing ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) hours_final_pace,
                       last_value(seats_pacing ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) seats_final_pace,
                       last_value(sects_pacing ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) sects_final_pace,
                       SYSDATE AS activity_date
         FROM (SELECT cp.graph_date,
                      cp.group1,
                      cp.group2,
                      cp.grouping1,
                      cp.grouping2,
                      REPLACE(cp.group1 || '_' || cp.group2, ' ', '') AS dim,
                      CASE
                      WHEN cp.hours_lastyear_delta = least(cp.hours_lastyear_delta, cp.hours_twoback_delta, cp.hours_threeback_delta) THEN
                       'Last Year'
                      WHEN cp.hours_twoback_delta = least(cp.hours_lastyear_delta, cp.hours_twoback_delta, cp.hours_threeback_delta) THEN
                       'Two Years Back'
                      WHEN cp.hours_threeback_delta = least(cp.hours_lastyear_delta, cp.hours_twoback_delta, cp.hours_threeback_delta) THEN
                       'Three Years Back'
                      ELSE
                       'UNKNOWN'
                      END AS pace_model,
                      cp.hours_current_actual,
                      CASE
                      WHEN cp.hours_lastyear_delta = least(cp.hours_lastyear_delta, cp.hours_twoback_delta, cp.hours_threeback_delta) THEN
                       cp.hours_lastyear_pacing
                      WHEN cp.hours_twoback_delta = least(cp.hours_lastyear_delta, cp.hours_twoback_delta, cp.hours_threeback_delta) THEN
                       cp.hours_twoback_pacing
                      WHEN cp.hours_threeback_delta = least(cp.hours_lastyear_delta, cp.hours_twoback_delta, cp.hours_threeback_delta) THEN
                       cp.hours_threeback_pacing
                      END AS hours_pacing,
                      cp.seats_current_actual,
                      CASE
                      WHEN cp.seats_lastyear_delta = least(cp.seats_lastyear_delta, cp.seats_twoback_delta, cp.seats_threeback_delta) THEN
                       cp.seats_lastyear_pacing
                      WHEN cp.seats_twoback_delta = least(cp.seats_lastyear_delta, cp.seats_twoback_delta, cp.seats_threeback_delta) THEN
                       cp.seats_twoback_pacing
                      WHEN cp.seats_threeback_delta = least(cp.seats_lastyear_delta, cp.seats_twoback_delta, cp.seats_threeback_delta) THEN
                       cp.seats_threeback_pacing
                      END AS seats_pacing,
                      cp.sects_current_actual,
                      CASE
                      WHEN cp.sects_lastyear_delta = least(cp.sects_lastyear_delta, cp.sects_twoback_delta, cp.sects_threeback_delta) THEN
                       cp.sects_lastyear_pacing
                      WHEN cp.sects_twoback_delta = least(cp.sects_lastyear_delta, cp.sects_twoback_delta, cp.sects_threeback_delta) THEN
                       cp.sects_twoback_pacing
                      WHEN cp.sects_threeback_delta = least(cp.sects_lastyear_delta, cp.sects_twoback_delta, cp.sects_threeback_delta) THEN
                       cp.sects_threeback_pacing
                      END AS sects_pacing
                 FROM utl_d_aa.crspaceaidy_luoa cp)
        WHERE seats_pacing IS NOT NULL) t2
ON (t1.aidy_code = t2.aidy_code AND t1.group1 = t2.group1 AND t1.group2 = t2.group2)
WHEN MATCHED THEN
UPDATE
   SET t1.grouping1        = t2.grouping1,
       t1.grouping2        = t2.grouping2,
       t1.dim              = t2.dim,
       t1.pace_model       = t2.pace_model,
       t1.hours_final_ct   = t2.hours_final_ct,
       t1.seats_final_ct   = t2.seats_final_ct,
       t1.sects_final_ct   = t2.sects_final_ct,
       t1.hours_final_pace = t2.hours_final_pace,
       t1.seats_final_pace = t2.seats_final_pace,
       t1.sects_final_pace = t2.sects_final_pace,
       t1.activity_date    = t2.activity_date
WHEN NOT MATCHED THEN
INSERT
VALUES
(t2.aidy_code,
 t2.group1,
 t2.grouping1,
 t2.group2,
 t2.grouping2,
 t2.dim,
 t2.pace_model,
 t2.hours_final_ct,
 t2.seats_final_ct,
 t2.sects_final_ct,
 t2.hours_final_pace,
 t2.seats_final_pace,
 t2.sects_final_pace,
 t2.activity_date);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || rec.aidy_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
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
--------------------------------------------CHANGE LOG----------------------------------------
-- VERSION DATE        USERNAME    UPDATES
---     04-10-2024  WGRIFFITH2  --Initial release;
------------------------------------------------------------------------------------------------
END etl_aa_crspaceaidyep_luoa;

procedure etl_aa_crspaceaidy_luoa (jobnumber number, processid varchar2, processname varchar2) is
--DECLARE
--- PARAMS
v_etl_date DATE := SYSDATE;
v_msg      VARCHAR2(2000);
v_instance VARCHAR2(50) := upper('ALL'); -- inst from the jams job; used for determining instance
v_partition NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
-- v_mod         NUMBER := 5; -- number of partitions to be created
v_cpu         NUMBER := 4; -- number of CPUs used for parallelization - do not exceed 20 CPUs [v_mod x --v_cpu] if running simultaneously
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_aa_crspaceaidy_luoa';
CURSOR c_terms IS
SELECT *
  FROM (SELECT 'ALL' AS group1,
               'Campus' AS group2
          FROM dual
        UNION
        SELECT 'Course' AS group1,
               'Campus' AS group2
          FROM dual
        )
 WHERE 1 = 1;
BEGIN
-- dbms_output.enable(buffer_size => NULL);
--
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
utl_d_aa.truncate_table(v_table_name => 'crspaceaidy_luoa');
FOR rec IN c_terms
LOOP
v_count   := 0; -- reset count
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || rec.group1 || rec.group2 || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
INSERT /*+*/
INTO utl_d_aa.crspaceaidy_luoa_gtt
(graph_date,
 graph_today,
 report_date,
 aidy_code,
 group1,
 group2,
 hours_prior_year_mult,
 hours_two_years_back_mult,
 hours_three_years_back_mult,
 seats_prior_year_mult,
 seats_two_years_back_mult,
 seats_three_years_back_mult,
 sects_prior_year_mult,
 sects_two_years_back_mult,
 sects_three_years_back_mult,
 hours,
 seats,
 sects)
SELECT crsdt.graph_date AS graph_date,
       crsdt.graph_today AS graph_today,
       crsdt.report_date report_date,
       crsdt.aidy_code aidy_code,
       crsdt.group1,
       crsdt.group2,
       MAX(genmult.hours_prior_year_mult) AS hours_prior_year_mult,
       MAX(genmult.hours_two_years_back_mult) AS hours_two_years_back_mult,
       MAX(genmult.hours_three_years_back_mult) AS hours_three_years_back_mult,
       MAX(genmult.seats_prior_year_mult) AS seats_prior_year_mult,
       MAX(genmult.seats_two_years_back_mult) AS seats_two_years_back_mult,
       MAX(genmult.seats_three_years_back_mult) AS seats_three_years_back_mult,
       MAX(genmult.sects_prior_year_mult) AS sects_prior_year_mult,
       MAX(genmult.sects_two_years_back_mult) AS sects_two_years_back_mult,
       MAX(genmult.sects_three_years_back_mult) AS sects_three_years_back_mult,
       SUM(CASE
           WHEN crsdt.report_date <= trunc(v_etl_date) THEN
            a.hours
           ELSE
            NULL
           END) hours,
       SUM(CASE
           WHEN crsdt.report_date <= trunc(v_etl_date) THEN
            a.seats
           ELSE
            NULL
           END) seats,
       SUM(CASE
           WHEN crsdt.report_date <= trunc(v_etl_date) THEN
            a.sections
           ELSE
            NULL
           END) sects
  FROM utl_d_aa.crshistaidydim_luoa crsdt
  LEFT JOIN utl_d_aa.crshist_luoa a
    ON a.report_date = crsdt.report_date
   AND a.aidy_code = crsdt.aidy_code
   AND CASE
       WHEN rec.group1 = 'ALL' THEN
        'ALL'
       WHEN rec.group1 = 'College' THEN
        a.coll_desc
       WHEN rec.group1 = 'Course' THEN
        coalesce(a.base_course, a.subj_code || '_' || a.crse_numb)
       END = crsdt.group1
   AND CASE
       WHEN rec.group2 = 'ALL' THEN
        'ALL'
       WHEN rec.group2 = 'Campus' THEN
        a.camp_code
       END = crsdt.group2
-- USING GENERALIZED PACE IF WE DONT HAVE ANY HISTORICAL DATA
  LEFT JOIN utl_d_aa.crsmultaidygen_luoa genmult
    ON genmult.graph_date = crsdt.graph_date
   AND genmult.group1 = crsdt.gen_group1
   AND genmult.group2 = crsdt.gen_group2
-- this line of code needs to be here to match up the joins between the ptrm tables in the subqquery above
-- in all but last week of the year, one record per week to reduce record counts
-- last week of the ADY runs daily numbers to continue to produce forecasts through 06/30 for the current ADY
 WHERE ((to_char(v_etl_date, 'mm/dd') NOT IN ('06/22', '06/23', '06/24', '06/25', '06/26', '06/27', '06/28', '06/29', '06/30') /*AND to_char(v_etl_date - (365.25 * 4), 'D') = to_char(crsdt.graph_date, 'D')*/) OR
       (to_char(v_etl_date, 'mm/dd') IN ('06/22', '06/23', '06/24', '06/25', '06/26', '06/27', '06/28', '06/29', '06/30')))
 GROUP BY crsdt.graph_date,
          crsdt.graph_today,
          crsdt.report_date,
          crsdt.aidy_code,
          crsdt.group1,
          crsdt.group2;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || rec.group1 || rec.group2 || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
INSERT /*+*/
INTO utl_d_aa.crspaceaidy_luoa
(graph_date,
 graph_today,
 grouping1,
 group1,
 grouping2,
 group2,
 is_historical,
 hours_current_actual,
 hours_prior_year,
 hours_two_years_back,
 hours_three_years_back,
 hours_lastyear_pacing,
 hours_twoback_pacing,
 hours_threeback_pacing,
 seats_current_actual,
 seats_prior_year,
 seats_two_years_back,
 seats_three_years_back,
 seats_lastyear_pacing,
 seats_twoback_pacing,
 seats_threeback_pacing,
 sects_current_actual,
 sects_prior_year,
 sects_two_years_back,
 sects_three_years_back,
 sects_lastyear_pacing,
 sects_twoback_pacing,
 sects_threeback_pacing,
 hours_lastyear_delta,
 hours_twoback_delta,
 hours_threeback_delta,
 seats_lastyear_delta,
 seats_twoback_delta,
 seats_threeback_delta,
 sects_lastyear_delta,
 sects_twoback_delta,
 sects_threeback_delta,
 activity_date)
SELECT graph_date,
       graph_today,
       rec.group1 AS grouping1,
       group1,
       rec.group2 AS grouping2,
       group2,
       is_historical,
       CASE
       WHEN hours_current_actual < .1 THEN
        0
       ELSE
        round(hours_current_actual, 0)
       END AS hours_current_actual, -- TURN THE ZERO CREDIT HOUR COURSES BACK TO 0 AND ROUND DOWN THE TOTALS
       CASE
       WHEN hours_prior_year < .1 THEN
        0
       ELSE
        round(hours_prior_year, 0)
       END AS hours_prior_year, -- TURN THE ZERO CREDIT HOUR COURSES BACK TO 0 AND ROUND DOWN THE TOTALS
       CASE
       WHEN hours_two_years_back < .1 THEN
        0
       ELSE
        round(hours_two_years_back, 0)
       END AS hours_two_years_back, -- TURN THE ZERO CREDIT HOUR COURSES BACK TO 0 AND ROUND DOWN THE TOTALS
       CASE
       WHEN hours_three_years_back < .1 THEN
        0
       ELSE
        round(hours_three_years_back, 0)
       END AS hours_three_years_back, -- TURN THE ZERO CREDIT HOUR COURSES BACK TO 0 AND ROUND DOWN THE TOTALS
       CASE
       WHEN hours_lastyear_pacing < .1 THEN
        0
       ELSE
        round(hours_lastyear_pacing, 0)
       END AS hours_lastyear_pacing, -- TURN THE ZERO CREDIT HOUR COURSES BACK TO 0 AND ROUND DOWN THE TOTALS
       CASE
       WHEN hours_twoback_pacing < .1 THEN
        0
       ELSE
        round(hours_twoback_pacing, 0)
       END AS hours_twoback_pacing, -- TURN THE ZERO CREDIT HOUR COURSES BACK TO 0 AND ROUND DOWN THE TOTALS
       CASE
       WHEN hours_threeback_pacing < .1 THEN
        0
       ELSE
        round(hours_threeback_pacing, 0)
       END AS hours_threeback_pacing, -- TURN THE ZERO CREDIT HOUR COURSES BACK TO 0 AND ROUND DOWN THE TOTALS
       seats_current_actual,
       seats_prior_year,
       seats_two_years_back,
       seats_three_years_back,
       seats_lastyear_pacing,
       seats_twoback_pacing,
       seats_threeback_pacing,
       sects_current_actual,
       sects_prior_year,
       sects_two_years_back,
       sects_three_years_back,
       sects_lastyear_pacing,
       sects_twoback_pacing,
       sects_threeback_pacing,
       round(abs(first_value(hours_lastyear_pacing ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) - last_value(hours_current_actual ignore NULLS)
                 over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following)), 0) AS hours_lastyear_delta,
       round(abs(first_value(hours_twoback_pacing ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) - last_value(hours_current_actual ignore NULLS)
                 over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following)), 0) AS hours_twoback_delta,
       round(abs(first_value(hours_threeback_pacing ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) - last_value(hours_current_actual ignore NULLS)
                 over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following)), 0) AS hours_threeback_delta,
       --
       abs(first_value(seats_lastyear_pacing ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) - last_value(seats_current_actual ignore NULLS)
           over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following)) AS seats_lastyear_delta,
       abs(first_value(seats_twoback_pacing ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) - last_value(seats_current_actual ignore NULLS)
           over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following)) AS seats_twoback_delta,
       abs(first_value(seats_threeback_pacing ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) - last_value(seats_current_actual ignore NULLS)
           over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following)) AS seats_threeback_delta,
       --
       abs(first_value(sects_lastyear_pacing ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) - last_value(sects_current_actual ignore NULLS)
           over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following)) AS sects_lastyear_delta,
       abs(first_value(sects_twoback_pacing ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) - last_value(sects_current_actual ignore NULLS)
           over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following)) AS sects_twoback_delta,
       abs(first_value(sects_threeback_pacing ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) - last_value(sects_current_actual ignore NULLS)
           over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following)) AS sects_threeback_delta,
       v_etl_date AS activity_date
  FROM (SELECT graph_date,
               graph_today,
               group1,
               group2,
               CASE
               WHEN hours_current_actual IS NOT NULL THEN
                'Y'
               ELSE
                'N'
               END AS is_historical,
               --
               hours_current_actual,
               hours_prior_year,
               hours_two_years_back,
               hours_three_years_back,
               --
               round(CASE
                     WHEN hours_current_actual IS NULL THEN
                      (last_value(hours_current_actual ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) /
                       first_value(CASE
                                                                                 WHEN graph_date = graph_today THEN
                                                                                  hours_prior_year_mult
                                                                                 END ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following)) * hours_prior_year_mult
                     END, 0) hours_lastyear_pacing,
               round(CASE
                     WHEN hours_current_actual IS NULL THEN
                      (last_value(hours_current_actual ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) /
                       first_value(CASE
                                                                                 WHEN graph_date = graph_today THEN
                                                                                  hours_two_years_back_mult
                                                                                 END ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following)) * hours_two_years_back_mult
                     END, 0) hours_twoback_pacing,
               round(CASE
                     WHEN hours_current_actual IS NULL THEN
                      (last_value(hours_current_actual ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) /
                       first_value(CASE
                                                                                 WHEN graph_date = graph_today THEN
                                                                                  hours_three_years_back_mult
                                                                                 END ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following)) * hours_three_years_back_mult
                     END, 0) hours_threeback_pacing,
               --
               seats_current_actual,
               seats_prior_year,
               seats_two_years_back,
               seats_three_years_back,
               round(CASE
                     WHEN seats_current_actual IS NULL THEN
                      (last_value(seats_current_actual ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) /
                       first_value(CASE
                                                                                 WHEN graph_date = graph_today THEN
                                                                                  seats_prior_year_mult
                                                                                 END ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following)) * seats_prior_year_mult
                     END, 0) seats_lastyear_pacing,
               round(CASE
                     WHEN seats_current_actual IS NULL THEN
                      (last_value(seats_current_actual ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) /
                       first_value(CASE
                                                                                 WHEN graph_date = graph_today THEN
                                                                                  seats_two_years_back_mult
                                                                                 END ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following)) * seats_two_years_back_mult
                     END, 0) seats_twoback_pacing,
               round(CASE
                     WHEN seats_current_actual IS NULL THEN
                      (last_value(seats_current_actual ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) /
                       first_value(CASE
                                                                                 WHEN graph_date = graph_today THEN
                                                                                  seats_three_years_back_mult
                                                                                 END ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following)) * seats_three_years_back_mult
                     END, 0) seats_threeback_pacing,
               --
               sects_current_actual,
               sects_prior_year,
               sects_two_years_back,
               sects_three_years_back,
               round(CASE
                     WHEN sects_current_actual IS NULL THEN
                      (last_value(sects_current_actual ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) /
                       first_value(CASE
                                                                                 WHEN graph_date = graph_today THEN
                                                                                  sects_prior_year_mult
                                                                                 END ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following)) * sects_prior_year_mult
                     END, 0) sects_lastyear_pacing,
               round(CASE
                     WHEN sects_current_actual IS NULL THEN
                      (last_value(sects_current_actual ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) /
                       first_value(CASE
                                                                                 WHEN graph_date = graph_today THEN
                                                                                  sects_two_years_back_mult
                                                                                 END ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following)) * sects_two_years_back_mult
                     END, 0) sects_twoback_pacing,
               round(CASE
                     WHEN sects_current_actual IS NULL THEN
                      (last_value(sects_current_actual ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) /
                       first_value(CASE
                                                                                 WHEN graph_date = graph_today THEN
                                                                                  sects_three_years_back_mult
                                                                                 END ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following)) * sects_three_years_back_mult
                     END, 0) sects_threeback_pacing
          FROM (SELECT graph_date,
                       graph_today,
                       group1,
                       group2,
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code000 THEN
                            hours
                           END) hours_current_actual,
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code000 THEN
                            hours_final_ct
                           END) hours_current_final,
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code101 THEN
                            hours
                           END) hours_prior_year,
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code101 THEN
                            hours_final_ct
                           END) hours_prior_final,
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code202 THEN
                            hours
                           END) hours_two_years_back,
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code202 THEN
                            hours / hours_final_ct
                           END) hours_two_years_back_per,
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code303 THEN
                            hours
                           END) hours_three_years_back,
                       --
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code000 THEN
                            seats
                           END) seats_current_actual,
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code000 THEN
                            seats_final_ct
                           END) seats_current_final,
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code101 THEN
                            seats
                           END) seats_prior_year,
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code101 THEN
                            seats_final_ct
                           END) seats_prior_final,
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code202 THEN
                            seats
                           END) seats_two_years_back,
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code303 THEN
                            seats
                           END) seats_three_years_back,
                       --
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code000 THEN
                            sects
                           END) sects_current_actual,
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code000 THEN
                            sects_final_ct
                           END) sects_current_final,
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code101 THEN
                            sects
                           END) sects_prior_year,
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code101 THEN
                            sects_final_ct
                           END) sects_prior_final,
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code202 THEN
                            sects
                           END) sects_two_years_back,
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code303 THEN
                            sects
                           END) sects_three_years_back,
                       MAX(hours_prior_year_mult) AS hours_prior_year_mult,
                       MAX(hours_two_years_back_mult) AS hours_two_years_back_mult,
                       MAX(hours_three_years_back_mult) AS hours_three_years_back_mult,
                       MAX(seats_prior_year_mult) AS seats_prior_year_mult,
                       MAX(seats_two_years_back_mult) AS seats_two_years_back_mult,
                       MAX(seats_three_years_back_mult) AS seats_three_years_back_mult,
                       MAX(sects_prior_year_mult) AS sects_prior_year_mult,
                       MAX(sects_two_years_back_mult) AS sects_two_years_back_mult,
                       MAX(sects_three_years_back_mult) AS sects_three_years_back_mult
                  FROM (SELECT graph_date,
                               graph_today,
                               report_date,
                               aidy_code,
                               group1,
                               group2,
                               hours,
                               last_value(hours ignore NULLS) over(PARTITION BY aidy_code, group1, group2 ORDER BY report_date RANGE BETWEEN unbounded preceding AND unbounded following) hours_final_ct,
                               seats,
                               last_value(seats ignore NULLS) over(PARTITION BY aidy_code, group1, group2 ORDER BY report_date RANGE BETWEEN unbounded preceding AND unbounded following) seats_final_ct,
                               sects,
                               last_value(sects ignore NULLS) over(PARTITION BY aidy_code, group1, group2 ORDER BY report_date RANGE BETWEEN unbounded preceding AND unbounded following) sects_final_ct,
                               hours_prior_year_mult,
                               hours_two_years_back_mult,
                               hours_three_years_back_mult,
                               seats_prior_year_mult,
                               seats_two_years_back_mult,
                               seats_three_years_back_mult,
                               sects_prior_year_mult,
                               sects_two_years_back_mult,
                               sects_three_years_back_mult
                          FROM utl_d_aa.crspaceaidy_luoa_gtt) sub0
                  JOIN (SELECT DISTINCT aidy_code,
                                       start404_yyyy,
                                       end404_yyyy,
                                       aidy_code303,
                                       aidy_code202,
                                       aidy_code101,
                                       aidy_code000
                         FROM utl_d_aa.crshist_luoa_stg stg) stg
                    ON stg.aidy_code = sub0.aidy_code
                 GROUP BY graph_date,
                          graph_today,
                          group1,
                          group2) tbl0) tbl1
 WHERE 1 = 1
   AND ((nvl(seats_current_actual, 0) > 0 AND graph_date <= graph_today) OR (nvl(seats_lastyear_pacing, 0) + nvl(seats_twoback_pacing, 0) + nvl(seats_threeback_pacing, 0) > 0 AND graph_date > graph_today));
v_count := SQL%ROWCOUNT;
COMMIT;
-- only outout every [n] loops
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || rec.group1 || rec.group2 || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
utl_d_aa.truncate_table(v_table_name => 'crspaceaidy_luoa_gtt');
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
--------------------------------------------CHANGE LOG----------------------------------------
-- VERSION DATE        USERNAME    UPDATES
---     04-10-2024  WGRIFFITH2  --Initial release;
------------------------------------------------------------------------------------------------*/
END etl_aa_crspaceaidy_luoa; --

procedure etl_aa_crsmultaidygen_luoa (jobnumber number, processid varchar2, processname varchar2) is
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
v_proc        VARCHAR2(100) := 'etl_aa_crsmultaidygen_luoa';
CURSOR c_terms IS
SELECT DISTINCT substr(ll.crse_numb, 1, 2) AS group1,
                ll.camp_code AS group2
  FROM utl_d_lms.lms_link ll
 WHERE ll.instance = 'ACCAN'
   AND SYSDATE BETWEEN ll.start_date AND ll.end_date
UNION ALL
SELECT DISTINCT 'ALL' AS group1,
                ll.camp_code AS group2
  FROM utl_d_lms.lms_link ll
 WHERE ll.instance = 'ACCAN'
   AND SYSDATE BETWEEN ll.start_date AND ll.end_date;
BEGIN
-- dbms_output.enable(buffer_size => NULL);
--
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
dbms_output.put_line('Started at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ';');
utl_d_aa.truncate_table(v_table_name => 'crsmultaidygen_luoa');
FOR rec IN c_terms
LOOP
v_count   := 0; -- reset count
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || rec.group1 || rec.group2 || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
INSERT INTO utl_d_aa.crsmultaidygen_luoa
(graph_date,
 group1,
 group2,
 hours_prior_year_mult,
 hours_prior_year,
 hours_prior_year_final,
 hours_two_years_back_mult,
 hours_two_years_back,
 hours_two_years_back_final,
 hours_three_years_back_mult,
 hours_three_years_back,
 hours_three_years_back_final,
 seats_prior_year_mult,
 seats_prior_year,
 seats_prior_year_final,
 seats_two_years_back_mult,
 seats_two_years_back,
 seats_two_years_back_final,
 seats_three_years_back_mult,
 seats_three_years_back,
 seats_three_years_back_final,
 sects_prior_year_mult,
 sects_prior_year,
 sects_prior_year_final,
 sects_two_years_back_mult,
 sects_two_years_back,
 sects_two_years_back_final,
 sects_three_years_back_mult,
 sects_three_years_back,
 sects_three_years_back_final,
 activity_date)
SELECT graph_date,
       group1,
       group2,
       --
       MAX(CASE
           WHEN report_year = aidy_code101 THEN
            hours / hours_final_ct
           END) hours_prior_year_mult,
       MAX(CASE
           WHEN report_year = aidy_code101 THEN
            hours
           END) hours_prior_year,
       MAX(CASE
           WHEN report_year = aidy_code101 THEN
            hours_final_ct
           END) hours_prior_year_final,
       --
       MAX(CASE
           WHEN report_year = aidy_code202 THEN
            hours / hours_final_ct
           END) hours_two_years_back_mult,
       MAX(CASE
           WHEN report_year = aidy_code202 THEN
            hours
           END) hours_two_years_back,
       MAX(CASE
           WHEN report_year = aidy_code202 THEN
            hours_final_ct
           END) hours_two_years_back_final,
       --
       MAX(CASE
           WHEN report_year = aidy_code303 THEN
            hours / hours_final_ct
           END) hours_three_years_back_mult,
       MAX(CASE
           WHEN report_year = aidy_code303 THEN
            hours
           END) hours_three_years_back,
       MAX(CASE
           WHEN report_year = aidy_code303 THEN
            hours_final_ct
           END) hours_three_years_back_final,
       --
       MAX(CASE
           WHEN report_year = aidy_code101 THEN
            seats / seats_final_ct
           END) seats_prior_year_mult,
       MAX(CASE
           WHEN report_year = aidy_code101 THEN
            seats
           END) seats_prior_year,
       MAX(CASE
           WHEN report_year = aidy_code101 THEN
            seats_final_ct
           END) seats_prior_year_final,
       --
       MAX(CASE
           WHEN report_year = aidy_code202 THEN
            seats / seats_final_ct
           END) seats_two_years_back_mult,
       MAX(CASE
           WHEN report_year = aidy_code202 THEN
            seats
           END) seats_two_years_back,
       MAX(CASE
           WHEN report_year = aidy_code202 THEN
            seats_final_ct
           END) seats_two_years_back_final,
       --
       MAX(CASE
           WHEN report_year = aidy_code303 THEN
            seats / seats_final_ct
           END) seats_three_years_back_mult,
       MAX(CASE
           WHEN report_year = aidy_code303 THEN
            seats
           END) seats_three_years_back,
       MAX(CASE
           WHEN report_year = aidy_code303 THEN
            seats_final_ct
           END) seats_three_years_back_final,
       --
       MAX(CASE
           WHEN report_year = aidy_code101 THEN
            sects / sects_final_ct
           END) sects_prior_year_mult,
       MAX(CASE
           WHEN report_year = aidy_code101 THEN
            sects
           END) sects_prior_year,
       MAX(CASE
           WHEN report_year = aidy_code101 THEN
            sects_final_ct
           END) sects_prior_year_final,
       --
       MAX(CASE
           WHEN report_year = aidy_code202 THEN
            sects / sects_final_ct
           END) sects_two_years_back_mult,
       MAX(CASE
           WHEN report_year = aidy_code202 THEN
            sects
           END) sects_two_years_back,
       MAX(CASE
           WHEN report_year = aidy_code202 THEN
            sects_final_ct
           END) sects_two_years_back_final,
       --
       MAX(CASE
           WHEN report_year = aidy_code303 THEN
            sects / sects_final_ct
           END) sects_three_years_back_mult,
       MAX(CASE
           WHEN report_year = aidy_code303 THEN
            sects
           END) sects_three_years_back,
       MAX(CASE
           WHEN report_year = aidy_code303 THEN
            sects_final_ct
           END) sects_three_years_back_final,
       --
       v_etl_date AS activity_date
  FROM (SELECT graph_date,
               report_date,
               report_year,
               group1,
               group2,
               hours,
               last_value(hours) over(PARTITION BY report_year, group1, group2 ORDER BY report_date RANGE BETWEEN unbounded preceding AND unbounded following) hours_final_ct,
               seats,
               last_value(seats) over(PARTITION BY report_year, group1, group2 ORDER BY report_date RANGE BETWEEN unbounded preceding AND unbounded following) seats_final_ct,
               sects,
               last_value(sects) over(PARTITION BY report_year, group1, group2 ORDER BY report_date RANGE BETWEEN unbounded preceding AND unbounded following) sects_final_ct
          FROM (SELECT to_date(to_char(hist.report_date, 'mm/dd') || CASE
                               WHEN to_char(hist.report_date, 'yy') = substr(hist.aidy_code, 1, 2) THEN
                                start404_yyyy
                               ELSE
                                end404_yyyy
                               END, 'mm/dd/yyyy') graph_date,
                       hist.report_date report_date,
                       hist.aidy_code report_year,
                       SUM(hist.hours) hours,
                       SUM(hist.seats) seats,
                       SUM(hist.sections) sects,
                       rec.group1 AS group1,
                       rec.group2 AS group2
                  FROM utl_d_aa.crshist_luoa hist
                  JOIN utl_d_aa.crshist_luoa_stg stg
                    ON stg.term_code = hist.term_code
                   AND stg.week_number = hist.week_number
                   AND stg.current_year <> 'Y'
                 WHERE 1 = 1
                      --AND hist.subj_code IN ('BUSI', 'ACCT', 'COUC', 'UNIV')
                   AND to_char(hist.report_date, 'mm/dd') <> '02/29'
                   AND hist.report_date >= to_date('07/01/20' || substr(hist.aidy_code, 1, 2), 'mm/dd/yyyy')
                   AND hist.report_date <= to_date('06/30/20' || substr(hist.aidy_code, 3, 2), 'mm/dd/yyyy')
                   AND substr(hist.crse_numb, 1, 2) = CASE
                       WHEN rec.group1 = 'ALL' THEN
                        substr(hist.crse_numb, 1, 2)
                       ELSE
                        rec.group1
                       END
                   AND hist.camp_code = CASE
                       WHEN rec.group2 = 'ALL' THEN
                        hist.camp_code
                       ELSE
                        rec.group2
                       END
                 GROUP BY hist.report_date,
                          hist.aidy_code,
                          to_date(to_char(hist.report_date, 'mm/dd') || CASE
                                  WHEN to_char(hist.report_date, 'yy') = substr(hist.aidy_code, 1, 2) THEN
                                   start404_yyyy
                                  ELSE
                                   end404_yyyy
                                  END, 'mm/dd/yyyy')
                HAVING SUM(hist.hours) > .1 -- DO NOT WANT ZERO CREDIT HOUR COURSES HERE
                )
        -- this line of code needs to be here to match up the joins between the ptrm tables in the subqquery above
        -- in all but last week of the year, one record per week to reduce record counts
        -- last week of the ADY runs daily numbers to continue to produce forecasts through 06/30 for the current ADY
         WHERE ((to_char(v_etl_date, 'mm/dd') NOT IN ('06/22', '06/23', '06/24', '06/25', '06/26', '06/27', '06/28', '06/29', '06/30') /*AND to_char(v_etl_date - (365.25 * 4), 'D') = to_char(graph_date, 'D')*/) OR
               (to_char(v_etl_date, 'mm/dd') IN ('06/22', '06/23', '06/24', '06/25', '06/26', '06/27', '06/28', '06/29', '06/30')))) sub0
  JOIN (SELECT DISTINCT aidy_code,
                        start404_yyyy,
                        end404_yyyy,
                        aidy_code303,
                        aidy_code202,
                        aidy_code101,
                        aidy_code000
          FROM utl_d_aa.crshist_luoa_stg stg) stg
    ON stg.aidy_code = sub0.report_year
 GROUP BY graph_date,
          group1,
          group2;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || rec.group1 || rec.group2 || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
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
--------------------------------------------CHANGE LOG----------------------------------------
-- VERSION DATE        USERNAME    UPDATES
---     04-09-2024  WGRIFFITH2  --Initial release;
------------------------------------------------------------------------------------------------*/
END etl_aa_crsmultaidygen_luoa; --

procedure etl_aa_crshistaidydim_luoa (jobnumber number, processid varchar2, processname varchar2) is
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
v_proc        VARCHAR2(100) := 'etl_aa_crshistaidydim_luoa';
CURSOR c_terms IS
SELECT 'ALL' AS group1,
       'Campus' AS group2
  FROM dual
 WHERE 1 = 1
UNION
SELECT 'Course' AS group1,
       'Campus' AS group2
  FROM dual
 WHERE 1 = 1;
BEGIN
-- dbms_output.enable(buffer_size => NULL);
--
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
utl_d_aa.truncate_table(v_table_name => 'crshistaidydim_luoa');
FOR rec IN c_terms
LOOP
v_count   := 0; -- reset count
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || rec.group1 || rec.group2 || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
INSERT INTO utl_d_aa.crshistaidydim_luoa_gtt
(group1,
 group2,
 gen_group1,
 gen_group2)
SELECT DISTINCT CASE
                WHEN rec.group1 = 'ALL' THEN
                 'ALL'
                WHEN rec.group1 = 'College' THEN
                 a.coll_desc
                WHEN rec.group1 = 'Course' THEN
                 coalesce(a.base_course, a.subj_code || '_' || a.crse_numb)
                END group1,
                CASE
                WHEN rec.group2 = 'ALL' THEN
                 'ALL'
                WHEN rec.group2 = 'Campus' THEN
                 a.camp_code
                END group2,
                CASE
                WHEN rec.group1 = 'ALL' THEN
                 'ALL'
                WHEN rec.group1 = 'College' THEN
                 'ALL'
                WHEN rec.group1 = 'Course' THEN
                 substr(a.crse_numb, 1, 2)
                END AS gen_group1,
                CASE
                WHEN rec.group2 = 'ALL' THEN
                 'ALL'
                WHEN rec.group2 = 'Campus' THEN
                 a.camp_code
                END AS gen_group2
  FROM utl_d_aa.crshist_luoa a
  JOIN utl_d_aa.crshist_luoa_stg stg
    ON stg.aidy_code = a.aidy_code
   AND stg.term_code = a.term_code
   AND stg.week_number = a.week_number
   AND (stg.current_year = 'Y' OR stg.previous_year = 'Y');
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || rec.group1 || rec.group2 || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
INSERT INTO utl_d_aa.crshistaidydim_luoa
(report_date,
 graph_date,
 graph_today,
 aidy_code,
 group1,
 group2,
 gen_group1,
 gen_group2,
 activity_date)
SELECT DISTINCT date_value report_date,
                to_date(to_char(date_value, 'mm/dd') || CASE
                        WHEN to_char(date_value, 'yy') = substr(date_b_u_acyr, 1, 2) THEN
                         start404_yyyy
                        ELSE
                         end404_yyyy
                        END, 'mm/dd/yyyy') graph_date,
                to_date(to_char(v_etl_date, 'mm/dd') || CASE
                        WHEN to_char(v_etl_date, 'yy') = substr(stg.aidy_code000, 1, 2) THEN
                         start404_yyyy
                        ELSE
                         end404_yyyy
                        END, 'mm/dd/yyyy') graph_today,
                date_b_u_acyr AS aidy_code,
                crss.group1,
                crss.group2,
                gen_group1,
                gen_group2,
                v_etl_date AS activity_date
  FROM dm_common.date_d__01
  JOIN (SELECT DISTINCT stg.aidy_code,
                        start404_yyyy,
                        end404_yyyy,
                        aidy_code000
          FROM utl_d_aa.crshist_stg stg) stg
    ON stg.aidy_code = date_b_u_acyr
-- this will only pull dims that appear in the current ADY
 CROSS JOIN utl_d_aa.crshistaidydim_luoa_gtt crss
 WHERE 1 = 1
   AND to_char(date_value, 'mm/dd') <> '02/29'
   AND date_value >= to_date('07/01/20' || to_char(v_etl_date - (365 * 4), 'YY'), 'mm/dd/yyyy')
   AND date_value <= to_date('06/30/20' || to_char(v_etl_date + (365 * 1), 'YY'), 'mm/dd/yyyy');
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || rec.group1 || rec.group2 || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
utl_d_aa.truncate_table(v_table_name => 'crshistaidydim_luoa_gtt');
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
---     04-09-2024  WGRIFFITH2  --Initial release;
------------------------------------------------------------------------------------------------*/
END etl_aa_crshistaidydim_luoa; --

procedure etl_aa_crshist_luoa (jobnumber number, processid varchar2, processname varchar2) is
--DECLARE
--- PARAMS
v_etl_date DATE := SYSDATE;
v_msg      VARCHAR2(2000);
v_instance VARCHAR2(50) := upper('ALL'); -- inst from the jams job; used for determining instance
v_partition NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
-- v_mod         NUMBER := 5; -- number of partitions to be created
v_cpu         NUMBER := 4; -- number of CPUs used for parallelization - do not exceed 20 CPUs [v_mod x --v_cpu] if running simultaneously
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_aa_crshist_luoa';
CURSOR c_terms IS
SELECT t.fa_proc_year AS stage_year,
       t.term_code AS stage_term,
       t.semester,
       to_date('07/01/20' || substr(t.fa_proc_year, 1, 2), 'mm/dd/yyyy') AS stage_start,
       to_date('06/30/20' || substr(t.fa_proc_year, 3, 2), 'mm/dd/yyyy') AS stage_end,
       t.start_date + dates.numb date_in
  FROM zbtm.terms_by_group_v t
-- START TRACKING DATA 90 DAYS PRIOR TO TERM START DATE
  JOIN (SELECT LEVEL - 180 numb FROM dual CONNECT BY LEVEL <= 410) dates
    ON t.start_date + dates.numb <= to_date('06/30/20' || substr(t.fa_proc_year, 3, 2), 'mm/dd/yyyy') -- cut off for the end of ADY
   AND t.start_date + dates.numb <= SYSDATE
   AND t.term_code BETWEEN '201938' AND '203038'
   AND t.group_code = 'ACD'
  LEFT JOIN (SELECT DISTINCT report_date,
                             term_code,
                             aidy_code
               FROM utl_d_aa.crshist_luoa hist) hist
    ON hist.aidy_code = t.fa_proc_year
   AND hist.term_code = t.term_code
   AND t.start_date + dates.numb = hist.report_date
 WHERE hist.report_date IS NULL
   AND t.start_date + dates.numb >= to_date('07/01/20' || substr(t.fa_proc_year, 1, 2), 'mm/dd/yyyy')
   AND t.start_date + dates.numb <= to_date('06/30/20' || substr(t.fa_proc_year, 3, 2), 'mm/dd/yyyy')
 ORDER BY 6 ASC;
BEGIN
-- dbms_output.enable(buffer_size => NULL);
-- 
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
utl_d_aa.truncate_table(v_table_name => 'crshist_luoa_stg');
INSERT /*+*/
INTO utl_d_aa.crshist_luoa_stg
(aidy_code,
 term_code,
 term_start_date,
 term_end_date,
 semester,
 semester_desc,
 week_number,
 ptrm_start_date,
 ptrm_end_date,
 current_year,
 previous_year,
 start404_yyyy,
 end404_yyyy,
 aidy_code303,
 aidy_code202,
 aidy_code101,
 aidy_code000)
SELECT DISTINCT t.fa_proc_year aidy_code,
                t.term_code,
                t.start_date AS term_start_date,
                t.end_date AS term_end_date,
                t.semester,
                t.semester_desc,
                (CASE
                WHEN starts.start_date <= t.start_date THEN
                 1
                ELSE
                 floor((to_date(starts.start_date) - to_date(t.start_date)) / 7) + 1
                END) AS week_number,
                t.start_date AS ptrm_start_date, -- placeholder
                t.end_date AS ptrm_end_date, -- placeholder
                CASE
                WHEN t.fa_proc_year = (SELECT MIN(t1.fa_proc_year - 0) start_yyyy
                                         FROM zbtm.terms_by_group_v t1
                                        WHERE (v_etl_date BETWEEN to_date('07/01/20' || substr(t1.fa_proc_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(t1.fa_proc_year, 3, 2), 'mm/dd/yyyy') OR
                                              v_etl_date + 14 BETWEEN to_date('07/01/20' || substr(t1.fa_proc_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(t1.fa_proc_year, 3, 2), 'mm/dd/yyyy'))) THEN
                 'Y'
                ELSE
                 'N'
                END AS current_year,
                CASE
                WHEN t.fa_proc_year = (SELECT MIN(t1.fa_proc_year - 101) start_yyyy
                                         FROM zbtm.terms_by_group_v t1
                                        WHERE (v_etl_date BETWEEN to_date('07/01/20' || substr(t1.fa_proc_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(t1.fa_proc_year, 3, 2), 'mm/dd/yyyy') OR
                                              v_etl_date + 14 BETWEEN to_date('07/01/20' || substr(t1.fa_proc_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(t1.fa_proc_year, 3, 2), 'mm/dd/yyyy'))) THEN
                 'Y'
                ELSE
                 'N'
                END AS previous_year,
                (SELECT MIN('20' || substr(t1.fa_proc_year - 404, 1, 2)) start_yyyy
                   FROM zbtm.terms_by_group_v t1
                  WHERE (v_etl_date BETWEEN to_date('07/01/20' || substr(t1.fa_proc_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(t1.fa_proc_year, 3, 2), 'mm/dd/yyyy') OR
                        v_etl_date + 14 BETWEEN to_date('07/01/20' || substr(t1.fa_proc_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(t1.fa_proc_year, 3, 2), 'mm/dd/yyyy'))) start404_yyyy,
                (SELECT MIN('20' || substr(t1.fa_proc_year - 404, 3, 2)) end_yyyy
                   FROM zbtm.terms_by_group_v t1
                  WHERE (v_etl_date BETWEEN to_date('07/01/20' || substr(t1.fa_proc_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(t1.fa_proc_year, 3, 2), 'mm/dd/yyyy') OR
                        v_etl_date + 14 BETWEEN to_date('07/01/20' || substr(t1.fa_proc_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(t1.fa_proc_year, 3, 2), 'mm/dd/yyyy'))) end404_yyyy,
                (SELECT MIN(t1.fa_proc_year - 303) start_yyyy
                   FROM zbtm.terms_by_group_v t1
                  WHERE (v_etl_date BETWEEN to_date('07/01/20' || substr(t1.fa_proc_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(t1.fa_proc_year, 3, 2), 'mm/dd/yyyy') OR
                        v_etl_date + 14 BETWEEN to_date('07/01/20' || substr(t1.fa_proc_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(t1.fa_proc_year, 3, 2), 'mm/dd/yyyy'))) aidy_code303,
                (SELECT MIN(t1.fa_proc_year - 202) start_yyyy
                   FROM zbtm.terms_by_group_v t1
                  WHERE (v_etl_date BETWEEN to_date('07/01/20' || substr(t1.fa_proc_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(t1.fa_proc_year, 3, 2), 'mm/dd/yyyy') OR
                        v_etl_date + 14 BETWEEN to_date('07/01/20' || substr(t1.fa_proc_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(t1.fa_proc_year, 3, 2), 'mm/dd/yyyy'))) aidy_code202,
                (SELECT MIN(t1.fa_proc_year - 101) start_yyyy
                   FROM zbtm.terms_by_group_v t1
                  WHERE (v_etl_date BETWEEN to_date('07/01/20' || substr(t1.fa_proc_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(t1.fa_proc_year, 3, 2), 'mm/dd/yyyy') OR
                        v_etl_date + 14 BETWEEN to_date('07/01/20' || substr(t1.fa_proc_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(t1.fa_proc_year, 3, 2), 'mm/dd/yyyy'))) aidy_code101,
                (SELECT MIN(t1.fa_proc_year - 0) start_yyyy
                   FROM zbtm.terms_by_group_v t1
                  WHERE (v_etl_date BETWEEN to_date('07/01/20' || substr(t1.fa_proc_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(t1.fa_proc_year, 3, 2), 'mm/dd/yyyy') OR
                        v_etl_date + 14 BETWEEN to_date('07/01/20' || substr(t1.fa_proc_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(t1.fa_proc_year, 3, 2), 'mm/dd/yyyy'))) aidy_code000
  FROM zbtm.terms_by_group_v t
  JOIN (SELECT DISTINCT ll.term_code,
                        ll.start_date
          FROM utl_d_lms.lms_link ll
         WHERE 1 = 1) starts
    ON starts.term_code = t.term_code
 WHERE t.fa_proc_year IN (SELECT DISTINCT t.fa_proc_year aidy_code
                            FROM zbtm.terms_by_group_v t
                           WHERE to_date('06/30/20' || substr(t.fa_proc_year, 3, 2), 'mm/dd/yyyy') > v_etl_date - (365 * 5)
                             AND to_date('07/01/20' || substr(t.fa_proc_year, 1, 2), 'mm/dd/yyyy') < v_etl_date + 90
                             AND t.semester NOT IN ('WIN')
                             AND t.group_code IN ('ACD'))
   AND t.semester NOT IN ('WIN')
   AND t.group_code IN ('ACD')
 ORDER BY week_number,
          aidy_code;
COMMIT;
FOR rec IN c_terms
LOOP
v_count   := 0; -- reset count
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || rec.stage_term || rec.date_in || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
INSERT /*+*/
INTO utl_d_aa.crshist_luoa
(subj_code,
 crse_numb,
 term_code,
 aidy_code,
 semester,
 week_number,
 camp_code,
 coll_code,
 coll_desc,
 sections,
 seats,
 hours,
 report_date,
 activity_date,
 base_course)
SELECT subj_code,
       crse_numb,
       sfrstca_term_code AS term_code,
       rec.stage_year AS aidy_code,
       rec.semester,
       week_number,
       camp_code,
       coll_code,
       coll_desc,
       COUNT(DISTINCT sfrstca_crn) sections,
       COUNT(*) seats,
       SUM(CASE
           WHEN sfrstca_credit_hr < .1 THEN
            .0000001 -- this is to allow zero credit hour courses and not cause divisor oracle error
           ELSE
            sfrstca_credit_hr
           END) AS hours,
       rec.date_in AS report_date,
       v_etl_date AS activity_date,
       base_course
  FROM (SELECT sfrstca_pidm,
               sfrstca_term_code,
               sfrstca_crn,
               sfrstca_credit_hr,
               sfrstca_rsts_code,
               sfrstca_rsts_date,
               sfrstca_activity_date,
               sfrstca_message,
               rank() over(PARTITION BY sfrstca_pidm, sfrstca_term_code, sfrstca_crn ORDER BY sfrstca_seq_number DESC) sfrstca_ranker,
               (CASE
               WHEN starts.start_date <= t.start_date THEN
                1
               ELSE
                floor((to_date(starts.start_date) - to_date(t.start_date)) / 7) + 1
               END) AS week_number,
               'AC' AS coll_code,
               'Liberty Online Academy' AS coll_desc,
               starts.subj_code,
               starts.crse_numb,
               'D' AS camp_code,
               base_course
          FROM sfrstca a
          JOIN (SELECT ll.term_code,
                      ll.crn,
                      ll.subj_code,
                      ll.crse_numb,
                      ll.base_course,
                      MIN(ll.start_date) AS start_date
                 FROM utl_d_lms.lms_link ll
                 JOIN zsaturn.szrlevl l
                   ON l.szrlevl_levl_code = ll.levl_code
                  AND l.szrlevl_has_awardable_cred = 'Y' -- remove EM
                WHERE 1 = 1
                  AND ll.term_code = rec.stage_term
                GROUP BY ll.term_code,
                         ll.crn,
                         ll.subj_code,
                         ll.crse_numb,
                         ll.base_course) starts
            ON starts.term_code = a.sfrstca_term_code
           AND starts.crn = a.sfrstca_crn
          JOIN zbtm.terms_by_group_v t
            ON t.term_code = a.sfrstca_term_code
         WHERE sfrstca_term_code = rec.stage_term
           AND sfrstca_source_cde = 'BASE'
           AND sfrstca_levl_code <> 'PD'
           AND nvl(sfrstca_error_flag, 'NULL') <> 'F'
           AND trunc(sfrstca_activity_date) < rec.date_in) a
  JOIN stvrsts
    ON a.sfrstca_rsts_code = stvrsts_code
   AND stvrsts_incl_assess = 'Y'
   AND sfrstca_ranker = 1
   AND nvl(sfrstca_message, 'NULL') NOT LIKE 'Record deleted%'
  JOIN saturn.spriden
    ON a.sfrstca_pidm = spriden_pidm
   AND spriden_change_ind IS NULL
 GROUP BY subj_code,
          crse_numb,
          base_course,
          sfrstca_term_code,
          rec.stage_year,
          rec.semester,
          week_number,
          camp_code,
          coll_code,
          coll_desc,
          rec.date_in;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || rec.stage_term || rec.date_in || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
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
--------------------------------------------CHANGE LOG----------------------------------------
-- VERSION DATE        USERNAME    UPDATES
---     04-04-2024  WGRIFFITH2  --Initial release
------------------------------------------------------------------------------------------------*/
END etl_aa_crshist_luoa; --

procedure etl_aa_stupaceaidyep_log (jobnumber number, processid varchar2, processname varchar2) is
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
v_proc        VARCHAR2(100) := 'etl_aa_stupaceaidyep_log';
BEGIN
-- dbms_output.enable(buffer_size => NULL);
--
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
MERGE INTO utl_d_aa.stupaceaidyep_log t1
USING (SELECT ep.aidy_code,
              ep.group1,
              ep.grouping1,
              ep.group2,
              ep.grouping2,
              ep.dim,
              ep.pace_model,
              ep.hours_final_pace,
              ep.seats_final_pace,
              ep.enrl_final_pace,
              ep.activity_date
         FROM utl_d_aa.stupaceaidyep ep
         JOIN utl_d_aa.stuhist_stg stg
           ON stg.aidy_code = ep.aidy_code
          AND stg.current_year = 'Y'
        WHERE to_char(SYSDATE, 'D') = '2' -- log once a week on Monday
       ) t2
ON (t1.aidy_code = t2.aidy_code AND t1.group1 = t2.group1 AND t1.group2 = t2.group2 AND trunc(t1.activity_date) = trunc(t2.activity_date))
WHEN MATCHED THEN
UPDATE
   SET t1.grouping1        = t2.grouping1,
       t1.grouping2        = t2.grouping2,
       t1.dim              = t2.dim,
       t1.pace_model       = t2.pace_model,
       t1.hours_final_pace = t2.hours_final_pace,
       t1.seats_final_pace = t2.seats_final_pace,
       t1.enrl_final_pace  = t2.enrl_final_pace
WHEN NOT MATCHED THEN
INSERT
VALUES
(t2.aidy_code,
 t2.group1,
 t2.grouping1,
 t2.group2,
 t2.grouping2,
 t2.dim,
 t2.pace_model,
 t2.hours_final_pace,
 t2.seats_final_pace,
 t2.enrl_final_pace,
 t2.activity_date);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
-- END LOOP; -- c_terms
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
-- log any errors
EXCEPTION WHEN OTHERS THEN v_elapsed := round((SYSDATE - v_etl_date) * 86400); v_msg := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200); dbms_output.put_line(v_msg); ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
/*--------------------------------------------CHANGE LOG----------------------------------------
VERSION DATE        USERNAME    UPDATES
---     07-27-2020  WGRIFFITH2  --Initial release
---     06-28-2023  WGRIFFITH2  --Updates related to performance issues; adding logging
------------------------------------------------------------------------------------------------*/
END etl_aa_stupaceaidyep_log;

procedure etl_aa_stupaceaidyep_refresh(jobnumber number, processid varchar2, processname varchar2) is
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
v_proc        VARCHAR2(100) := 'etl_aa_stupaceaidyep_refresh';
CURSOR c_terms IS
-- Using start_date - 80 corresponds with term logic in stuhist_refresh
-- **This code cannot pull historically because it is using the stupace table
-- **so reloading historical data must be done ad-hoc with stuhist table
SELECT DISTINCT aidy_code FROM utl_d_aa.stuhist_stg stg WHERE stg.current_year = 'Y'  ;
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
MERGE INTO utl_d_aa.stupaceaidyep t1
USING (SELECT DISTINCT rec.aidy_code AS aidy_code,
                       group1,
                       group2,
                       grouping1,
                       grouping2,
                       dim,
                       pace_model,
                       last_value(hours_current_actual ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) hours_final_ct,
                       last_value(seats_current_actual ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) seats_final_ct,
                       last_value(enrl_current_actual ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) enrl_final_ct,
                       last_value(hours_pacing ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) hours_final_pace,
                       last_value(seats_pacing ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) seats_final_pace,
                       last_value(enrl_pacing ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) enrl_final_pace,
                       SYSDATE AS activity_date
         FROM (SELECT cp.graph_date,
                      cp.group1,
                      cp.group2,
                      cp.grouping1,
                      cp.grouping2,
                      REPLACE(cp.group1 || '_' || cp.group2, ' ', '') AS dim,
                      CASE
                      WHEN cp.hours_lastyear_delta = least(cp.hours_lastyear_delta, cp.hours_twoback_delta, cp.hours_threeback_delta) THEN
                       'Last Year'
                      WHEN cp.hours_twoback_delta = least(cp.hours_lastyear_delta, cp.hours_twoback_delta, cp.hours_threeback_delta) THEN
                       'Two Years Back'
                      WHEN cp.hours_threeback_delta = least(cp.hours_lastyear_delta, cp.hours_twoback_delta, cp.hours_threeback_delta) THEN
                       'Three Years Back'
                      ELSE
                       'UNKNOWN'
                      END AS pace_model,
                      cp.hours_current_actual,
                      CASE
                      WHEN cp.hours_lastyear_delta = least(cp.hours_lastyear_delta, cp.hours_twoback_delta, cp.hours_threeback_delta) THEN
                       cp.hours_lastyear_pacing
                      WHEN cp.hours_twoback_delta = least(cp.hours_lastyear_delta, cp.hours_twoback_delta, cp.hours_threeback_delta) THEN
                       cp.hours_twoback_pacing
                      WHEN cp.hours_threeback_delta = least(cp.hours_lastyear_delta, cp.hours_twoback_delta, cp.hours_threeback_delta) THEN
                       cp.hours_threeback_pacing
                      END AS hours_pacing,
                      cp.seats_current_actual,
                      CASE
                      WHEN cp.seats_lastyear_delta = least(cp.seats_lastyear_delta, cp.seats_twoback_delta, cp.seats_threeback_delta) THEN
                       cp.seats_lastyear_pacing
                      WHEN cp.seats_twoback_delta = least(cp.seats_lastyear_delta, cp.seats_twoback_delta, cp.seats_threeback_delta) THEN
                       cp.seats_twoback_pacing
                      WHEN cp.seats_threeback_delta = least(cp.seats_lastyear_delta, cp.seats_twoback_delta, cp.seats_threeback_delta) THEN
                       cp.seats_threeback_pacing
                      END AS seats_pacing,
                      cp.enrl_current_actual,
                      CASE
                      WHEN cp.enrl_lastyear_delta = least(cp.enrl_lastyear_delta, cp.enrl_twoback_delta, cp.enrl_threeback_delta) THEN
                       cp.enrl_lastyear_pacing
                      WHEN cp.enrl_twoback_delta = least(cp.enrl_lastyear_delta, cp.enrl_twoback_delta, cp.enrl_threeback_delta) THEN
                       cp.enrl_twoback_pacing
                      WHEN cp.enrl_threeback_delta = least(cp.enrl_lastyear_delta, cp.enrl_twoback_delta, cp.enrl_threeback_delta) THEN
                       cp.enrl_threeback_pacing
                      END AS enrl_pacing
                 FROM utl_d_aa.stupaceaidy cp)) t2
ON (t1.aidy_code = t2.aidy_code AND t1.group1 = t2.group1 AND t1.group2 = t2.group2)
WHEN MATCHED THEN
UPDATE
   SET t1.grouping1        = t2.grouping1,
       t1.grouping2        = t2.grouping2,
       t1.dim              = t2.dim,
       t1.pace_model       = t2.pace_model,
       t1.hours_final_ct   = t2.hours_final_ct,
       t1.seats_final_ct   = t2.seats_final_ct,
       t1.enrl_final_ct    = t2.enrl_final_ct,
       t1.hours_final_pace = t2.hours_final_pace,
       t1.seats_final_pace = t2.seats_final_pace,
       t1.enrl_final_pace  = t2.enrl_final_pace,
       t1.activity_date    = t2.activity_date
WHEN NOT MATCHED THEN
INSERT
VALUES
(t2.aidy_code,
 t2.group1,
 t2.grouping1,
 t2.group2,
 t2.grouping2,
 t2.dim,
 t2.pace_model,
 t2.hours_final_ct,
 t2.seats_final_ct,
 t2.enrl_final_ct,
 t2.hours_final_pace,
 t2.seats_final_pace,
 t2.enrl_final_pace,
 t2.activity_date);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || rec.aidy_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
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
VERSION DATE        USERNAME    UPDATES
---     12-09-2019  WGRIFFITH2  --Initial release
---     08-25-2021  WGRIFFITH2  --Accommodating zero credit hour courses
---     06-28-2023  WGRIFFITH2  --Updates related to performance issues; adding logging
------------------------------------------------------------------------------------------------*/
END etl_aa_stupaceaidyep_refresh;

procedure etl_aa_stupaceaidy_refresh (jobnumber number, processid varchar2, processname varchar2) is
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
v_proc        VARCHAR2(100) := 'etl_aa_stupaceaidy_refresh';
CURSOR c_terms IS
SELECT * FROM (
SELECT 'Program' AS group1,
       'Campus' AS group2
  FROM dual
UNION
SELECT 'College' AS group1,
       'Campus' AS group2
  FROM dual
UNION
SELECT 'ALL' AS group1,
       'Campus' AS group2
  FROM dual
UNION
SELECT 'Level' AS group1,
       'Campus' AS group2
  FROM dual)
  WHERE 1=1;
BEGIN
-- dbms_output.enable(buffer_size => NULL);
--
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
utl_d_aa.truncate_table(v_table_name => 'stupaceaidy');
FOR rec IN c_terms
LOOP
v_count   := 0; -- reset count
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || rec.group1 || rec.group2 || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
INSERT INTO utl_d_aa.stupaceaidy
(graph_date,
 graph_today,
 grouping1,
 group1,
 grouping2,
 group2,
 is_historical,
 hours_current_actual,
 hours_prior_year,
 hours_two_years_back,
 hours_three_years_back,
 hours_lastyear_pacing,
 hours_twoback_pacing,
 hours_threeback_pacing,
 seats_current_actual,
 seats_prior_year,
 seats_two_years_back,
 seats_three_years_back,
 seats_lastyear_pacing,
 seats_twoback_pacing,
 seats_threeback_pacing,
 enrl_current_actual,
 enrl_prior_year,
 enrl_two_years_back,
 enrl_three_years_back,
 enrl_lastyear_pacing,
 enrl_twoback_pacing,
 enrl_threeback_pacing,
 hours_lastyear_delta,
 hours_twoback_delta,
 hours_threeback_delta,
 seats_lastyear_delta,
 seats_twoback_delta,
 seats_threeback_delta,
 enrl_lastyear_delta,
 enrl_twoback_delta,
 enrl_threeback_delta,
 activity_date)
SELECT graph_date,
       graph_today,
       rec.group1 AS grouping1,
       group1,
       rec.group2 AS grouping2,
       group2,
       is_historical,
       CASE
       WHEN hours_current_actual < .1 THEN
        0
       ELSE
        round(hours_current_actual, 0)
       END AS hours_current_actual, -- TURN THE ZERO CREDIT HOUR COURSES BACK TO 0 AND ROUND DOWN THE TOTALS
       CASE
       WHEN hours_prior_year < .1 THEN
        0
       ELSE
        round(hours_prior_year, 0)
       END AS hours_prior_year, -- TURN THE ZERO CREDIT HOUR COURSES BACK TO 0 AND ROUND DOWN THE TOTALS
       CASE
       WHEN hours_two_years_back < .1 THEN
        0
       ELSE
        round(hours_two_years_back, 0)
       END AS hours_two_years_back, -- TURN THE ZERO CREDIT HOUR COURSES BACK TO 0 AND ROUND DOWN THE TOTALS
       CASE
       WHEN hours_three_years_back < .1 THEN
        0
       ELSE
        round(hours_three_years_back, 0)
       END AS hours_three_years_back, -- TURN THE ZERO CREDIT HOUR COURSES BACK TO 0 AND ROUND DOWN THE TOTALS
       CASE
       WHEN hours_lastyear_pacing < .1 THEN
        0
       ELSE
        round(hours_lastyear_pacing, 0)
       END AS hours_lastyear_pacing, -- TURN THE ZERO CREDIT HOUR COURSES BACK TO 0 AND ROUND DOWN THE TOTALS
       CASE
       WHEN hours_twoback_pacing < .1 THEN
        0
       ELSE
        round(hours_twoback_pacing, 0)
       END AS hours_twoback_pacing, -- TURN THE ZERO CREDIT HOUR COURSES BACK TO 0 AND ROUND DOWN THE TOTALS
       CASE
       WHEN hours_threeback_pacing < .1 THEN
        0
       ELSE
        round(hours_threeback_pacing, 0)
       END AS hours_threeback_pacing, -- TURN THE ZERO CREDIT HOUR COURSES BACK TO 0 AND ROUND DOWN THE TOTALS
       seats_current_actual,
       seats_prior_year,
       seats_two_years_back,
       seats_three_years_back,
       seats_lastyear_pacing,
       seats_twoback_pacing,
       seats_threeback_pacing,
       enrl_current_actual,
       enrl_prior_year,
       enrl_two_years_back,
       enrl_three_years_back,
       enrl_lastyear_pacing,
       enrl_twoback_pacing,
       enrl_threeback_pacing,
       round(abs(first_value(hours_lastyear_pacing ignore NULLS)
                 over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) - last_value(hours_current_actual ignore NULLS)
                 over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following)), 0) AS hours_lastyear_delta,
       round(abs(first_value(hours_twoback_pacing ignore NULLS)
                 over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) - last_value(hours_current_actual ignore NULLS)
                 over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following)), 0) AS hours_twoback_delta,
       round(abs(first_value(hours_threeback_pacing ignore NULLS)
                 over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) - last_value(hours_current_actual ignore NULLS)
                 over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following)), 0) AS hours_threeback_delta,
       --
       abs(first_value(seats_lastyear_pacing ignore NULLS)
           over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) - last_value(seats_current_actual ignore NULLS)
           over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following)) AS seats_lastyear_delta,
       abs(first_value(seats_twoback_pacing ignore NULLS)
           over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) - last_value(seats_current_actual ignore NULLS)
           over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following)) AS seats_twoback_delta,
       abs(first_value(seats_threeback_pacing ignore NULLS)
           over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) - last_value(seats_current_actual ignore NULLS)
           over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following)) AS seats_threeback_delta,
       --
       abs(first_value(enrl_lastyear_pacing ignore NULLS)
           over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) - last_value(enrl_current_actual ignore NULLS)
           over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following)) AS enrl_lastyear_delta,
       abs(first_value(enrl_twoback_pacing ignore NULLS)
           over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) - last_value(enrl_current_actual ignore NULLS)
           over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following)) AS enrl_twoback_delta,
       abs(first_value(enrl_threeback_pacing ignore NULLS)
           over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) - last_value(enrl_current_actual ignore NULLS)
           over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following)) AS enrl_threeback_delta,
       v_etl_date AS activity_date
  FROM (SELECT graph_date,
               graph_today,
               group1,
               group2,
               CASE
               WHEN hours_current_actual IS NOT NULL THEN
                'Y'
               ELSE
                'N'
               END AS is_historical,
               --
               hours_current_actual,
               hours_prior_year,
               hours_two_years_back,
               hours_three_years_back,
               --
               round(CASE
                     WHEN hours_current_actual IS NULL THEN
                      (last_value(hours_current_actual ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) /
                       first_value(CASE
                                                                                 WHEN graph_date = graph_today THEN
                                                                                  hours_prior_year_mult
                                                                                 END ignore NULLS)
                       over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following)) * hours_prior_year_mult
                     END, 0) hours_lastyear_pacing,
               round(CASE
                     WHEN hours_current_actual IS NULL THEN
                      (last_value(hours_current_actual ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) /
                       first_value(CASE
                                                                                 WHEN graph_date = graph_today THEN
                                                                                  hours_two_years_back_mult
                                                                                 END ignore NULLS)
                       over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following)) * hours_two_years_back_mult
                     END, 0) hours_twoback_pacing,
               round(CASE
                     WHEN hours_current_actual IS NULL THEN
                      (last_value(hours_current_actual ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) /
                       first_value(CASE
                                                                                 WHEN graph_date = graph_today THEN
                                                                                  hours_three_years_back_mult
                                                                                 END ignore NULLS)
                       over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following)) * hours_three_years_back_mult
                     END, 0) hours_threeback_pacing,
               --
               seats_current_actual,
               seats_prior_year,
               seats_two_years_back,
               seats_three_years_back,
               round(CASE
                     WHEN seats_current_actual IS NULL THEN
                      (last_value(seats_current_actual ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) /
                       first_value(CASE
                                                                                 WHEN graph_date = graph_today THEN
                                                                                  seats_prior_year_mult
                                                                                 END ignore NULLS)
                       over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following)) * seats_prior_year_mult
                     END, 0) seats_lastyear_pacing,
               round(CASE
                     WHEN seats_current_actual IS NULL THEN
                      (last_value(seats_current_actual ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) /
                       first_value(CASE
                                                                                 WHEN graph_date = graph_today THEN
                                                                                  seats_two_years_back_mult
                                                                                 END ignore NULLS)
                       over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following)) * seats_two_years_back_mult
                     END, 0) seats_twoback_pacing,
               round(CASE
                     WHEN seats_current_actual IS NULL THEN
                      (last_value(seats_current_actual ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) /
                       first_value(CASE
                                                                                 WHEN graph_date = graph_today THEN
                                                                                  seats_three_years_back_mult
                                                                                 END ignore NULLS)
                       over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following)) * seats_three_years_back_mult
                     END, 0) seats_threeback_pacing,
               --
               enrl_current_actual,
               enrl_prior_year,
               enrl_two_years_back,
               enrl_three_years_back,
               round(CASE
                     WHEN enrl_current_actual IS NULL THEN
                      (last_value(enrl_current_actual ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) /
                       first_value(CASE
                                                                                 WHEN graph_date = graph_today THEN
                                                                                  enrl_prior_year_mult
                                                                                 END ignore NULLS)
                       over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following)) * enrl_prior_year_mult
                     END, 0) enrl_lastyear_pacing,
               round(CASE
                     WHEN enrl_current_actual IS NULL THEN
                      (last_value(enrl_current_actual ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) /
                       first_value(CASE
                                                                                 WHEN graph_date = graph_today THEN
                                                                                  enrl_two_years_back_mult
                                                                                 END ignore NULLS)
                       over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following)) * enrl_two_years_back_mult
                     END, 0) enrl_twoback_pacing,
               round(CASE
                     WHEN enrl_current_actual IS NULL THEN
                      (last_value(enrl_current_actual ignore NULLS) over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following) /
                       first_value(CASE
                                                                                 WHEN graph_date = graph_today THEN
                                                                                  enrl_three_years_back_mult
                                                                                 END ignore NULLS)
                       over(PARTITION BY group1, group2 ORDER BY graph_date RANGE BETWEEN unbounded preceding AND unbounded following)) * enrl_three_years_back_mult
                     END, 0) enrl_threeback_pacing
          FROM (SELECT graph_date,
                       graph_today,
                       group1,
                       group2,
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code000 THEN
                            hours
                           END) hours_current_actual,
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code000 THEN
                            hours_final_ct
                           END) hours_current_final,
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code101 THEN
                            hours
                           END) hours_prior_year,
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code101 THEN
                            hours_final_ct
                           END) hours_prior_final,
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code202 THEN
                            hours
                           END) hours_two_years_back,
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code202 THEN
                            hours / hours_final_ct
                           END) hours_two_years_back_per,
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code303 THEN
                            hours
                           END) hours_three_years_back,
                       --
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code000 THEN
                            seats
                           END) seats_current_actual,
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code000 THEN
                            seats_final_ct
                           END) seats_current_final,
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code101 THEN
                            seats
                           END) seats_prior_year,
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code101 THEN
                            seats_final_ct
                           END) seats_prior_final,
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code202 THEN
                            seats
                           END) seats_two_years_back,
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code303 THEN
                            seats
                           END) seats_three_years_back,
                       --
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code000 THEN
                            enrl
                           END) enrl_current_actual,
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code000 THEN
                            enrl_final_ct
                           END) enrl_current_final,
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code101 THEN
                            enrl
                           END) enrl_prior_year,
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code101 THEN
                            enrl_final_ct
                           END) enrl_prior_final,
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code202 THEN
                            enrl
                           END) enrl_two_years_back,
                       MAX(CASE
                           WHEN sub0.aidy_code = aidy_code303 THEN
                            enrl
                           END) enrl_three_years_back,
                       MAX(hours_prior_year_mult) AS hours_prior_year_mult,
                       MAX(hours_two_years_back_mult) AS hours_two_years_back_mult,
                       MAX(hours_three_years_back_mult) AS hours_three_years_back_mult,
                       MAX(seats_prior_year_mult) AS seats_prior_year_mult,
                       MAX(seats_two_years_back_mult) AS seats_two_years_back_mult,
                       MAX(seats_three_years_back_mult) AS seats_three_years_back_mult,
                       MAX(enrl_prior_year_mult) AS enrl_prior_year_mult,
                       MAX(enrl_two_years_back_mult) AS enrl_two_years_back_mult,
                       MAX(enrl_three_years_back_mult) AS enrl_three_years_back_mult
                  FROM (SELECT graph_date,
                               graph_today,
                               report_date,
                               aidy_code,
                               group1,
                               group2,
                               hours,
                               last_value(hours ignore NULLS) over(PARTITION BY aidy_code, group1, group2 ORDER BY report_date RANGE BETWEEN unbounded preceding AND unbounded following) hours_final_ct,
                               seats,
                               last_value(seats ignore NULLS) over(PARTITION BY aidy_code, group1, group2 ORDER BY report_date RANGE BETWEEN unbounded preceding AND unbounded following) seats_final_ct,
                               enrl,
                               last_value(enrl ignore NULLS) over(PARTITION BY aidy_code, group1, group2 ORDER BY report_date RANGE BETWEEN unbounded preceding AND unbounded following) enrl_final_ct,
                               hours_prior_year_mult,
                               hours_two_years_back_mult,
                               hours_three_years_back_mult,
                               seats_prior_year_mult,
                               seats_two_years_back_mult,
                               seats_three_years_back_mult,
                               enrl_prior_year_mult,
                               enrl_two_years_back_mult,
                               enrl_three_years_back_mult
                          FROM (SELECT studt.graph_date AS graph_date,
                                       studt.graph_today AS graph_today,
                                       studt.report_date report_date,
                                       studt.aidy_code aidy_code,
                                       studt.group1,
                                       studt.group2,
                                       MAX(genmult.hours_prior_year_mult) AS hours_prior_year_mult,
                                       MAX(genmult.hours_two_years_back_mult) AS hours_two_years_back_mult,
                                       MAX(genmult.hours_three_years_back_mult) AS hours_three_years_back_mult,
                                       MAX(genmult.seats_prior_year_mult) AS seats_prior_year_mult,
                                       MAX(genmult.seats_two_years_back_mult) AS seats_two_years_back_mult,
                                       MAX(genmult.seats_three_years_back_mult) AS seats_three_years_back_mult,
                                       MAX(genmult.enrl_prior_year_mult) AS enrl_prior_year_mult,
                                       MAX(genmult.enrl_two_years_back_mult) AS enrl_two_years_back_mult,
                                       MAX(genmult.enrl_three_years_back_mult) AS enrl_three_years_back_mult,
                                       SUM(CASE
                                           WHEN studt.report_date <= trunc(v_etl_date) THEN
                                            hist.hours
                                           ELSE
                                            NULL
                                           END) hours,
                                       SUM(CASE
                                           WHEN studt.report_date <= trunc(v_etl_date) THEN
                                            hist.seats
                                           ELSE
                                            NULL
                                           END) seats,
                                       SUM(CASE
                                           WHEN studt.report_date <= trunc(v_etl_date) THEN
                                            hist.enrl
                                           ELSE
                                            NULL
                                           END) enrl
                                  FROM utl_d_aa.stuhistaidydim studt
                                  LEFT JOIN utl_d_aa.stuhist hist
                                    ON hist.report_date = studt.report_date
                                   AND hist.aidy_code = studt.aidy_code
                                   AND CASE
                                       WHEN rec.group1 = 'ALL' THEN
                                        'ALL'
                                       WHEN rec.group1 = 'Program' THEN
                                        hist.prog_code
                                       WHEN rec.group1 = 'College' THEN
                                        hist.coll_desc
                                        WHEN rec.group1 = 'Level' THEN
                                        hist.levl_code
                                       END = studt.group1
                                   AND CASE
                                       WHEN rec.group2 = 'ALL' THEN
                                        'ALL'
                                       WHEN rec.group2 = 'Campus' THEN
                                        hist.camp_code
                                       END = studt.group2
                                -- USING GENERALIZED PACE IF WE DONT HAVE ANY HISTORICAL DATA
                                  LEFT JOIN utl_d_aa.stumultaidygen genmult
                                    ON genmult.graph_date = studt.graph_date
                                   AND genmult.group1 = studt.gen_group1
                                   AND genmult.group2 = studt.gen_group2
                                 WHERE 1 = 1
                                      -- one record per week to reduce record counts
                                   AND to_char(v_etl_date - (365.25 * 4), 'D') = to_char(studt.graph_date, 'D')
                                 GROUP BY studt.graph_date,
                                          studt.graph_today,
                                          studt.report_date,
                                          studt.aidy_code,
                                          studt.group1,
                                          studt.group2)) sub0
                  JOIN (SELECT DISTINCT aidy_code,
                                       start404_yyyy,
                                       end404_yyyy,
                                       aidy_code303,
                                       aidy_code202,
                                       aidy_code101,
                                       aidy_code000
                         FROM utl_d_aa.stuhist_stg stg) stg
                    ON stg.aidy_code = sub0.aidy_code
                 GROUP BY graph_date,
                          graph_today,
                          group1,
                          group2) tbl0) tbl1
 WHERE 1 = 1
   AND ((coalesce(seats_current_actual, 0) > 0 AND graph_date <= graph_today) OR
       (coalesce(seats_lastyear_pacing, 0) + coalesce(seats_twoback_pacing, 0) + coalesce(seats_threeback_pacing, 0) > 0 AND graph_date > graph_today));
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || rec.group1 || rec.group2 || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
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
VERSION DATE        USERNAME    UPDATES
---     12-03-2019  WGRIFFITH2  --Initial release;
---     08-25-2021  WGRIFFITH2  --Accommodating zero credit hour courses
---     06-28-2023  WGRIFFITH2  --Updates related to performance issues; adding logging
------------------------------------------------------------------------------------------------*/
END etl_aa_stupaceaidy_refresh; --

procedure etl_aa_stumultaidygen_refresh (jobnumber number, processid varchar2, processname varchar2) is
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
v_proc        VARCHAR2(100) := 'etl_aa_stumultaidygen_refresh';
CURSOR c_terms IS
SELECT * FROM (
SELECT 'ALL' AS group1,
       'R' AS group2
  FROM dual
UNION
SELECT 'ALL' AS group1,
       'D' AS group2
  FROM dual)
  WHERE 1=1;
BEGIN
-- dbms_output.enable(buffer_size => NULL);
--
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
utl_d_aa.truncate_table(v_table_name => 'stumultaidygen');
FOR rec IN c_terms
LOOP
v_count   := 0; -- reset count
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || rec.group1 || rec.group2 || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
INSERT INTO utl_d_aa.stumultaidygen
(graph_date,
 group1,
 group2,
 hours_prior_year_mult,
 hours_prior_year,
 hours_prior_year_final,
 hours_two_years_back_mult,
 hours_two_years_back,
 hours_two_years_back_final,
 hours_three_years_back_mult,
 hours_three_years_back,
 hours_three_years_back_final,
 seats_prior_year_mult,
 seats_prior_year,
 seats_prior_year_final,
 seats_two_years_back_mult,
 seats_two_years_back,
 seats_two_years_back_final,
 seats_three_years_back_mult,
 seats_three_years_back,
 seats_three_years_back_final,
 enrl_prior_year_mult,
 enrl_prior_year,
 enrl_prior_year_final,
 enrl_two_years_back_mult,
 enrl_two_years_back,
 enrl_two_years_back_final,
 enrl_three_years_back_mult,
 enrl_three_years_back,
 enrl_three_years_back_final,
 activity_date)
SELECT graph_date,
       group1,
       group2,
       --
       MAX(CASE
           WHEN report_year = aidy_code101 THEN
            hours / hours_final_ct
           END) hours_prior_year_mult,
       MAX(CASE
           WHEN report_year = aidy_code101 THEN
            hours
           END) hours_prior_year,
       MAX(CASE
           WHEN report_year = aidy_code101 THEN
            hours_final_ct
           END) hours_prior_year_final,
       --
       MAX(CASE
           WHEN report_year = aidy_code202 THEN
            hours / hours_final_ct
           END) hours_two_years_back_mult,
       MAX(CASE
           WHEN report_year = aidy_code202 THEN
            hours
           END) hours_two_years_back,
       MAX(CASE
           WHEN report_year = aidy_code202 THEN
            hours_final_ct
           END) hours_two_years_back_final,
       --
       MAX(CASE
           WHEN report_year = aidy_code303 THEN
            hours / hours_final_ct
           END) hours_three_years_back_mult,
       MAX(CASE
           WHEN report_year = aidy_code303 THEN
            hours
           END) hours_three_years_back,
       MAX(CASE
           WHEN report_year = aidy_code303 THEN
            hours_final_ct
           END) hours_three_years_back_final,
       --
       MAX(CASE
           WHEN report_year = aidy_code101 THEN
            seats / seats_final_ct
           END) seats_prior_year_mult,
       MAX(CASE
           WHEN report_year = aidy_code101 THEN
            seats
           END) seats_prior_year,
       MAX(CASE
           WHEN report_year = aidy_code101 THEN
            seats_final_ct
           END) seats_prior_year_final,
       --
       MAX(CASE
           WHEN report_year = aidy_code202 THEN
            seats / seats_final_ct
           END) seats_two_years_back_mult,
       MAX(CASE
           WHEN report_year = aidy_code202 THEN
            seats
           END) seats_two_years_back,
       MAX(CASE
           WHEN report_year = aidy_code202 THEN
            seats_final_ct
           END) seats_two_years_back_final,
       --
       MAX(CASE
           WHEN report_year = aidy_code303 THEN
            seats / seats_final_ct
           END) seats_three_years_back_mult,
       MAX(CASE
           WHEN report_year = aidy_code303 THEN
            seats
           END) seats_three_years_back,
       MAX(CASE
           WHEN report_year = aidy_code303 THEN
            seats_final_ct
           END) seats_three_years_back_final,
       MAX(CASE
           WHEN report_year = aidy_code101 THEN
            enrl / enrl_final_ct
           END) enrl_prior_year_mult,
       MAX(CASE
           WHEN report_year = aidy_code101 THEN
            enrl
           END) enrl_prior_year,
       MAX(CASE
           WHEN report_year = aidy_code101 THEN
            enrl_final_ct
           END) enrl_prior_year_final,
       --
       MAX(CASE
           WHEN report_year = aidy_code202 THEN
            enrl / enrl_final_ct
           END) enrl_two_years_back_mult,
       MAX(CASE
           WHEN report_year = aidy_code202 THEN
            enrl
           END) enrl_two_years_back,
       MAX(CASE
           WHEN report_year = aidy_code202 THEN
            enrl_final_ct
           END) enrl_two_years_back_final,
       --
       MAX(CASE
           WHEN report_year = aidy_code303 THEN
            enrl / enrl_final_ct
           END) enrl_three_years_back_mult,
       MAX(CASE
           WHEN report_year = aidy_code303 THEN
            enrl
           END) enrl_three_years_back,
       MAX(CASE
           WHEN report_year = aidy_code303 THEN
            enrl_final_ct
           END) enrl_three_years_back_final,
       --
       v_etl_date AS activity_date
  FROM (SELECT graph_date,
               report_date,
               report_year,
               group1,
               group2,
               hours,
               last_value(hours) over(PARTITION BY report_year, group1, group2 ORDER BY report_date RANGE BETWEEN unbounded preceding AND unbounded following) hours_final_ct,
               seats,
               last_value(seats) over(PARTITION BY report_year, group1, group2 ORDER BY report_date RANGE BETWEEN unbounded preceding AND unbounded following) seats_final_ct,
               enrl,
               last_value(enrl) over(PARTITION BY report_year, group1, group2 ORDER BY report_date RANGE BETWEEN unbounded preceding AND unbounded following) enrl_final_ct
          FROM (SELECT to_date(to_char(hist.report_date, 'mm/dd') || CASE
                               WHEN to_char(hist.report_date, 'yy') = substr(hist.aidy_code, 1, 2) THEN
                                start404_yyyy
                               ELSE
                                end404_yyyy
                               END, 'mm/dd/yyyy') graph_date,
                       hist.report_date report_date,
                       hist.aidy_code report_year,
                       SUM(hours) hours,
                       SUM(seats) seats,
                       SUM(enrl) enrl,
                       rec.group1 AS group1,
                       rec.group2 AS group2
                  FROM utl_d_aa.stuhist hist
                  JOIN utl_d_aa.stuhist_stg stg
                    ON stg.aidy_code = hist.aidy_code
                   AND stg.current_year <> 'Y'
                 WHERE 1 = 1
                   AND to_char(hist.report_date, 'mm/dd') <> '02/29'
                   AND hist.report_date >= to_date('07/01/20' || substr(hist.aidy_code, 1, 2), 'mm/dd/yyyy')
                   AND hist.report_date <= to_date('06/30/20' || substr(hist.aidy_code, 3, 2), 'mm/dd/yyyy')
                   AND hist.prog_code = CASE
                       WHEN rec.group1 = 'ALL' THEN
                        hist.prog_code
                       ELSE
                        rec.group1
                       END
                   AND hist.camp_code = CASE
                       WHEN rec.group2 = 'ALL' THEN
                        hist.camp_code
                       ELSE
                        rec.group2
                       END
                 GROUP BY hist.report_date,
                          hist.aidy_code,
                          to_date(to_char(hist.report_date, 'mm/dd') || CASE
                                  WHEN to_char(hist.report_date, 'yy') = substr(hist.aidy_code, 1, 2) THEN
                                   start404_yyyy
                                  ELSE
                                   end404_yyyy
                                  END, 'mm/dd/yyyy')
        HAVING SUM(hist.hours) > .1 -- DO NOT WANT ZERO CREDIT HOURS HERE
                  )
        -- one record per week to reduce record counts
         WHERE to_char(v_etl_date - (365.25 * 4), 'D') = to_char(graph_date, 'D')
     ) sub0
  JOIN (SELECT DISTINCT aidy_code,
                        start404_yyyy,
                        end404_yyyy,
                        aidy_code303,
                        aidy_code202,
                        aidy_code101,
                        aidy_code000
          FROM utl_d_aa.stuhist_stg stg) stg
    ON stg.aidy_code = sub0.report_year
 GROUP BY graph_date,
          group1,
          group2;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || rec.group1 || rec.group2 || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
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
VERSION DATE        USERNAME    UPDATES
---     12-19-2019  WGRIFFITH2  --Initial release;
---     08-25-2021  WGRIFFITH2  --Accommodating zero credit hour courses
---     06-28-2023  WGRIFFITH2  --Updates related to performance issues; adding logging
------------------------------------------------------------------------------------------------*/
END etl_aa_stumultaidygen_refresh; --

procedure etl_aa_stuhistaidydim_refresh (jobnumber number, processid varchar2, processname varchar2) is
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
v_proc        VARCHAR2(100) := 'etl_aa_stuhistaidydim_refresh';
CURSOR c_terms IS
SELECT * FROM (
SELECT 'Program' AS group1,
       'Campus' AS group2
  FROM dual
UNION
SELECT 'College' AS group1,
       'Campus' AS group2
  FROM dual
UNION
SELECT 'ALL' AS group1,
       'Campus' AS group2
  FROM dual
UNION
SELECT 'Level' AS group1,
       'Campus' AS group2
  FROM dual)
  WHERE 1=1;
BEGIN
-- dbms_output.enable(buffer_size => NULL);
--
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
utl_d_aa.truncate_table(v_table_name => 'stuhistaidydim');
FOR rec IN c_terms
LOOP
v_count   := 0; -- reset count
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || rec.group1 || rec.group2 || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
INSERT INTO utl_d_aa.stuhistaidydim
(report_date,
 graph_date,
 graph_today,
 aidy_code,
 group1,
 group2,
 gen_group1,
 gen_group2,
 activity_date)
SELECT DISTINCT dim.report_date,
                dim.graph_date,
                dim.graph_today,
                dim.aidy_code,
                stus.group1,
                stus.group2,
                gen_group1,
                gen_group2,
                v_etl_date AS activity_date
  FROM (SELECT DISTINCT date_value report_date,
                        to_date(to_char(date_value, 'mm/dd') || CASE
                                WHEN to_char(date_value, 'yy') = substr(date_b_u_acyr, 1, 2) THEN
                                 start404_yyyy
                                ELSE
                                 end404_yyyy
                                END, 'mm/dd/yyyy') graph_date,
                        to_date(to_char(SYSDATE, 'mm/dd') || CASE
                                WHEN to_char(SYSDATE, 'yy') = substr(stg.aidy_code000, 1, 2) THEN
                                 start404_yyyy
                                ELSE
                                 end404_yyyy
                                END, 'mm/dd/yyyy') graph_today,
                        date_b_u_acyr AS aidy_code,
                        SYSDATE AS activity_date
          FROM dm_common.date_d__01
          JOIN (SELECT DISTINCT stg.aidy_code,
                               start404_yyyy,
                               end404_yyyy,
                               aidy_code000
                 FROM utl_d_aa.stuhist_stg stg) stg
            ON stg.aidy_code = date_b_u_acyr
         WHERE 1 = 1
           AND to_char(date_value, 'mm/dd') <> '02/29'
           AND date_value >= to_date('07/01/20' || to_char(SYSDATE - (365 * 4), 'YY'), 'mm/dd/yyyy')
           AND date_value <= to_date('06/30/20' || to_char(SYSDATE + (365 * 1), 'YY'), 'mm/dd/yyyy')) dim
-- this will only pull dims that appear in the current ADY
 CROSS JOIN (SELECT DISTINCT CASE
                             WHEN rec.group1 = 'ALL' THEN
                              'ALL'
                             WHEN rec.group1 = 'College' THEN
                              hist.coll_desc
                             WHEN rec.group1 = 'Program' THEN
                              hist.prog_code
                             WHEN rec.group1 = 'Level' THEN
                              hist.levl_code
                             END group1,
                             CASE
                             WHEN rec.group2 = 'ALL' THEN
                              'ALL'
                             WHEN rec.group2 = 'Campus' THEN
                              hist.camp_code
                             END group2,
                             CASE
                             WHEN rec.group1 = 'ALL' THEN
                              'ALL'
                             WHEN rec.group1 = 'College' THEN
                              'ALL'
                             WHEN rec.group1 = 'Program' THEN
                              'ALL'
                             WHEN rec.group1 = 'Level' THEN
                              'ALL'
                             END AS gen_group1,
                             CASE
                             WHEN rec.group2 = 'ALL' THEN
                              'ALL'
                             WHEN rec.group2 = 'Campus' THEN
                              hist.camp_code
                             END AS gen_group2
               FROM utl_d_aa.stuhist hist
               JOIN utl_d_aa.stuhist_stg stg
                 ON stg.aidy_code = hist.aidy_code
                AND stg.current_year = 'Y') stus;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || rec.group1 || rec.group2 || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
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
VERSION DATE        USERNAME    UPDATES
---     12-19-2019  WGRIFFITH2  --Initial release;
---     06-28-2023  WGRIFFITH2  --Updates related to performance issues; adding logging
------------------------------------------------------------------------------------------------*/
END etl_aa_stuhistaidydim_refresh; --

procedure etl_aa_stuhist_refresh (jobnumber number, processid varchar2, processname varchar2) is
-- DECLARE
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
v_proc        VARCHAR2(100) := 'etl_aa_stuhist_refresh';
CURSOR c_terms IS
SELECT DISTINCT terms.fa_proc_year aidy_code,
                to_date('07/01/20' || substr(terms.fa_proc_year, 1, 2), 'mm/dd/yyyy') stage_start,
                to_date('06/30/20' || substr(terms.fa_proc_year, 3, 2), 'mm/dd/yyyy') stage_end,
                to_date(to_char(trunc(terms.start_date + dates.numb) + (4 / 24), 'MM/DD/YYYY hh24:mi:ss'), 'MM/DD/YYYY hh24:mi:ss') AS ytd_timestamp
  FROM zbtm.terms_by_group_v terms
-- START TRACKING DATA 90 DAYS PRIOR TO TERM START DATE
  JOIN (SELECT LEVEL - 90 numb FROM dual CONNECT BY LEVEL <= 410) dates
    ON terms.start_date + dates.numb <= to_date('06/30/20' || substr(terms.fa_proc_year, 3, 2), 'mm/dd/yyyy') -- cut off for the end of ADY
   AND terms.start_date + dates.numb <= SYSDATE
   AND terms.term_code BETWEEN '202040' AND '203040'
   AND terms.group_code = 'STD'
   AND terms.semester IN ('FAL', 'SPR', 'SUM')
  LEFT JOIN (SELECT DISTINCT report_date,
                             aidy_code
               FROM utl_d_aa.stuhist hist) hist
    ON hist.aidy_code = terms.fa_proc_year
   AND terms.start_date + dates.numb = hist.report_date
 WHERE hist.report_date IS NULL
   AND terms.start_date + dates.numb >= to_date('07/01/20' || substr(terms.fa_proc_year, 1, 2), 'mm/dd/yyyy')
   AND terms.start_date + dates.numb <= to_date('06/30/20' || substr(terms.fa_proc_year, 3, 2), 'mm/dd/yyyy')
 ORDER BY 1 ASC,
          2 ASC,
          4 ASC;
BEGIN
-- dbms_output.enable(buffer_size => NULL);
--
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
utl_d_aa.truncate_table(v_table_name => 'stuhist_stg');
INSERT INTO utl_d_aa.stuhist_stg
(aidy_code,
 aidy_start_date,
 aidy_end_date,
 current_year,
 previous_year,
 start404_yyyy,
 end404_yyyy,
 aidy_code303,
 aidy_code202,
 aidy_code101,
 aidy_code000)
SELECT DISTINCT t.fa_proc_year aidy_code,
                to_date('07/01/20' || substr(t.fa_proc_year, 1, 2), 'mm/dd/yyyy') AS aidy_start_date,
                to_date('06/30/20' || substr(t.fa_proc_year, 3, 2), 'mm/dd/yyyy') AS aidy_end_date,
                CASE
                WHEN t.fa_proc_year = (SELECT MIN(t1.fa_proc_year - 0) start_yyyy
                                         FROM zbtm.terms_by_group_v t1
                                        WHERE (v_etl_date BETWEEN to_date('07/01/20' || substr(t1.fa_proc_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(t1.fa_proc_year, 3, 2), 'mm/dd/yyyy') OR
                                              v_etl_date + 14 BETWEEN to_date('07/01/20' || substr(t1.fa_proc_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(t1.fa_proc_year, 3, 2), 'mm/dd/yyyy'))) THEN
                 'Y'
                ELSE
                 'N'
                END AS current_year,
                CASE
                WHEN t.fa_proc_year = (SELECT MIN(t1.fa_proc_year - 101) start_yyyy
                                         FROM zbtm.terms_by_group_v t1
                                        WHERE (v_etl_date BETWEEN to_date('07/01/20' || substr(t1.fa_proc_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(t1.fa_proc_year, 3, 2), 'mm/dd/yyyy') OR
                                              v_etl_date + 14 BETWEEN to_date('07/01/20' || substr(t1.fa_proc_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(t1.fa_proc_year, 3, 2), 'mm/dd/yyyy'))) THEN
                 'Y'
                ELSE
                 'N'
                END AS previous_year,
                (SELECT MIN('20' || substr(t1.fa_proc_year - 404, 1, 2)) start_yyyy
                   FROM zbtm.terms_by_group_v t1
                  WHERE (v_etl_date BETWEEN to_date('07/01/20' || substr(t1.fa_proc_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(t1.fa_proc_year, 3, 2), 'mm/dd/yyyy') OR
                        v_etl_date + 14 BETWEEN to_date('07/01/20' || substr(t1.fa_proc_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(t1.fa_proc_year, 3, 2), 'mm/dd/yyyy'))) start404_yyyy,
                (SELECT MIN('20' || substr(t1.fa_proc_year - 404, 3, 2)) end_yyyy
                   FROM zbtm.terms_by_group_v t1
                  WHERE (v_etl_date BETWEEN to_date('07/01/20' || substr(t1.fa_proc_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(t1.fa_proc_year, 3, 2), 'mm/dd/yyyy') OR
                        v_etl_date + 14 BETWEEN to_date('07/01/20' || substr(t1.fa_proc_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(t1.fa_proc_year, 3, 2), 'mm/dd/yyyy'))) end404_yyyy,
                (SELECT MIN(t1.fa_proc_year - 303) start_yyyy
                   FROM zbtm.terms_by_group_v t1
                  WHERE (v_etl_date BETWEEN to_date('07/01/20' || substr(t1.fa_proc_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(t1.fa_proc_year, 3, 2), 'mm/dd/yyyy') OR
                        v_etl_date + 14 BETWEEN to_date('07/01/20' || substr(t1.fa_proc_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(t1.fa_proc_year, 3, 2), 'mm/dd/yyyy'))) aidy_code303,
                (SELECT MIN(t1.fa_proc_year - 202) start_yyyy
                   FROM zbtm.terms_by_group_v t1
                  WHERE (v_etl_date BETWEEN to_date('07/01/20' || substr(t1.fa_proc_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(t1.fa_proc_year, 3, 2), 'mm/dd/yyyy') OR
                        v_etl_date + 14 BETWEEN to_date('07/01/20' || substr(t1.fa_proc_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(t1.fa_proc_year, 3, 2), 'mm/dd/yyyy'))) aidy_code202,
                (SELECT MIN(t1.fa_proc_year - 101) start_yyyy
                   FROM zbtm.terms_by_group_v t1
                  WHERE (v_etl_date BETWEEN to_date('07/01/20' || substr(t1.fa_proc_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(t1.fa_proc_year, 3, 2), 'mm/dd/yyyy') OR
                        v_etl_date + 14 BETWEEN to_date('07/01/20' || substr(t1.fa_proc_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(t1.fa_proc_year, 3, 2), 'mm/dd/yyyy'))) aidy_code101,
                (SELECT MIN(t1.fa_proc_year - 0) start_yyyy
                   FROM zbtm.terms_by_group_v t1
                  WHERE (v_etl_date BETWEEN to_date('07/01/20' || substr(t1.fa_proc_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(t1.fa_proc_year, 3, 2), 'mm/dd/yyyy') OR
                        v_etl_date + 14 BETWEEN to_date('07/01/20' || substr(t1.fa_proc_year, 1, 2), 'mm/dd/yyyy') AND to_date('06/30/20' || substr(t1.fa_proc_year, 3, 2), 'mm/dd/yyyy'))) aidy_code000
  FROM zbtm.terms_by_group_v t
  JOIN saturn.sobptrm
    ON sobptrm_term_code = t.term_code
   AND sobptrm_ptrm_code IN ('R', '1A', '1B', '1C', '1D', '1J', 'L')
 WHERE t.fa_proc_year IN (SELECT DISTINCT t.fa_proc_year aidy_code
                            FROM zbtm.terms_by_group_v t
                           WHERE t.end_date > v_etl_date - (365 * 5)
                             AND t.start_date < v_etl_date + 180
                             AND t.semester NOT IN ('WIN')
                             AND t.group_code IN ('STD', 'MED'))
   AND t.semester NOT IN ('WIN')
   AND t.group_code IN ('STD', 'MED');
COMMIT;
FOR rec IN c_terms
LOOP
v_count   := 0; -- reset count
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || rec.aidy_code || ' - ' || rec.ytd_timestamp || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
INSERT INTO utl_d_aa.stuhist
(report_date,
 aidy_code,
 prog_code,
 levl_code,
 camp_code,
 coll_code,
 coll_desc,
 hours,
 seats,
 enrl,
 activity_date)
SELECT trunc(rec.ytd_timestamp) AS report_date,
       rec.aidy_code AS aidy_code,
       coalesce(lcur.prog_code_1, lcur.majr_code_1 || '-' || lcur.degc_code_1 || '-' || lcur.camp_code, 'XXXX-XX-X') AS prog_code,
       lcur.levl_code AS levl_code,
       lcur.camp_code AS camp_code,
       lcur.prog_coll_1 AS coll_code,
       stvcoll.stvcoll_desc AS coll_desc,
       -- this will get should rounded at the end of the progress
       SUM(CASE
           WHEN sfrstca_credit_hr < .1 THEN
            .0000001 -- this is to allow zero credit hour courses and not cause divisor oracle error
           ELSE
            sfrstca_credit_hr
           END) AS hours,
       COUNT(DISTINCT sfrstca_crn) seats,
       COUNT(DISTINCT sfrstca_pidm) enrollment,
       v_etl_date AS activity_date
  FROM saturn.sfrstca
  JOIN zbtm.terms_by_group_v terms -- do not remove this join because we need to make sure we exclude any terms we do not want to pull into the totals
    ON terms.term_code = sfrstca_term_code
   AND terms.group_code IN ('STD', 'MED') -- only get standard terms and med 
   AND terms.fa_proc_year = rec.aidy_code
  JOIN saturn.stvrsts
    ON stvrsts_code = sfrstca_rsts_code
   AND stvrsts_incl_sect_enrl = 'Y' -- aligns with AA tables
      --      AND stvrsts_incl_assess = 'Y' -- aligns with EM MR;
      -- we are looking for ALL enrollments - including zero (0) credit hours
   AND sfrstca_rsts_date <= rec.ytd_timestamp
   AND sfrstca_source_cde = 'BASE'
   AND sfrstca_levl_code <> 'PD' -- must explicitly exclude PD courses
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
   AND szrlevl_is_univ = 'Y' -- student must be university level and in a program that has awardable credit
   AND szrlevl_has_awardable_cred = 'Y'
  LEFT JOIN stvcoll
    ON stvcoll_code = lcur.prog_coll_1
 GROUP BY rec.ytd_timestamp,
          rec.aidy_code,
          coalesce(lcur.prog_code_1, lcur.majr_code_1 || '-' || lcur.degc_code_1 || '-' || lcur.camp_code, 'XXXX-XX-X'),
          lcur.levl_code,
          lcur.camp_code,
          lcur.prog_coll_1,
          stvcoll.stvcoll_desc,
          rec.ytd_timestamp;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || rec.aidy_code || ' - ' || rec.ytd_timestamp || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
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
VERSION DATE        USERNAME    UPDATES
---     12-19-2019  WGRIFFITH2  --Initial release
---     05-06-2019  WGRIFFITH2  --Updating logic for timeframes to use the ADY start and end dates of 7/1-6/30
---     08-25-2021  WGRIFFITH2  --Accommodating zero credit hour courses
---     05-17-2023  WGRIFFITH2  --Dealing with EM courses and updating code to use job_log
---     09-25-2025  WGRIFFITH2  --Matching code to what shows in the PDB enrollments
---     10-24-2025  wgriffith2  --utl_d_aim.szrregs deprecation; removing all szrcurr joins from etl procedures live code
------------------------------------------------------------------------------------------------*/
END etl_aa_stuhist_refresh; --

END load_aa_etl_pacing;
-- GRANT EXECUTE ON load_aa_etl_pacing TO utl_d_aim;
-- GRANT EXECUTE ON load_aa_etl_pacing TO utl_d_aa;
-- GRANT EXECUTE ON load_aa_etl_pacing TO utl_d_lms;
-- GRANT EXECUTE ON load_aa_etl_pacing TO wgriffith2;
-- GRANT EXECUTE ON load_aa_etl_pacing TO ZETL_JAMS_SVC;