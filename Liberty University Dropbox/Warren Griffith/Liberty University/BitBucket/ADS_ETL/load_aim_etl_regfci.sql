create or replace package load_aim_etl_regfci is
procedure etl_aim_regfcisum_main_reg_old(jobnumber number, processid varchar2, processname varchar2); -- RUN FIRST
procedure etl_aim_regfcisum_main_reg_luo(jobnumber number, processid varchar2, processname varchar2); -- RUN AFTER etl_aim_regfcisum_main_reg_old
-- 
procedure etl_aim_regfcisum_intl_reg_old(jobnumber number, processid varchar2, processname varchar2); -- RUN FIRST
procedure etl_aim_regfcisum_intl_reg(jobnumber number, processid varchar2, processname varchar2); -- RUN AFTER etl_aim_regfcisum_intl_reg_old
--
procedure etl_aim_regfcisum_new_res_old(jobnumber number, processid varchar2, processname varchar2); -- RUN FIRST; runs simultaneously
procedure etl_aim_regfcisum_main_reg_res_new(jobnumber number, processid varchar2, processname varchar2); -- RUN FIRST; runs simultaneously
procedure etl_aim_regfcisum_main_reg_res_return(jobnumber number, processid varchar2, processname varchar2); -- RUN FIRST; runs simultaneously
procedure etl_aim_regfcisum_new_res(jobnumber number, processid varchar2, processname varchar2); -- RUN FIRST; runs simultaneously
---
procedure etl_aim_regfcisum_total_reg(jobnumber number, processid varchar2, processname varchar2); -- RUN LAST; runs simultaneously
procedure etl_aim_regfcisum_ytd_reg(jobnumber number, processid varchar2, processname varchar2); -- RUN LAST; runs simultaneously WITH etl_aim_regfcisum_total_reg
end load_aim_etl_regfci;
/

CREATE OR REPLACE PACKAGE BODY load_aim_etl_regfci IS

PROCEDURE etl_aim_regfcisum_ytd_reg(jobnumber   NUMBER,
                                    processid   VARCHAR2,
                                    processname VARCHAR2) IS
/*
Table: utl_d_aim.rsbbregfci

Primary Keys: RSBBREGFCI_REPORT_DATE, RSBBREGFCI_REPORT, RSBBREGFCI_ACYR_CODE, RSBBREGFCI_TERM_CODE, RSBBREGFCI_CAMP_CODE, RSBBREGFCI_STYP_CODE, RSBBREGFCI_LEVL_CODE

Unique index: RSBBREGFCI_REPORT_DATE, RSBBREGFCI_REPORT, RSBBREGFCI_ACYR_CODE, RSBBREGFCI_TERM_CODE, RSBBREGFCI_CAMP_CODE, RSBBREGFCI_STYP_CODE, RSBBREGFCI_LEVL_CODE

Purpose:
- Tracking reg and fci for all students

Conditions:
- Student has to be registered

*/
--DECLARE
--- PARAMS
v_etl_date    DATE := SYSDATE;
v_msg         VARCHAR2(2000);
v_instance    VARCHAR2(50) := upper('ALL'); -- inst from the jams job; used for determining instance
v_partition    NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_cpu         NUMBER := 4; -- number of CPUs used for parallelization - do not exceed 20 CPUs [v_mod x --v_cpu] if running simultaneously
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_report_type VARCHAR2(32) := 'ytd_reg';
v_proc        VARCHAR2(100) := 'etl_aim_regfcisum_ytd_reg';
CURSOR c_terms IS
SELECT DISTINCT t.fa_proc_year AS acyr_code,
                trunc(t.start_date + dates.numb) AS report_date,
                to_date(to_char(trunc(t.start_date + dates.numb) + (4 / 24), 'MM/DD/YYYY hh24:mi:ss'), 'MM/DD/YYYY hh24:mi:ss') report_timestamp -- runs at 4am everyday
  FROM zbtm.terms_by_group_v t
  JOIN (SELECT LEVEL - 180 numb FROM dual CONNECT BY LEVEL <= 360) dates
    ON t.start_date + dates.numb <= trunc(SYSDATE)
   AND t.term_code NOT IN ('000000')
   AND t.group_code IN ('STD', 'MED')
 WHERE 1 = 1
   AND (trunc(t.start_date + dates.numb) >= trunc(SYSDATE - 3) -- running the last 3 days to catch anything we might have missed; to_date('2025-04-07','YYYY-MM-DD')
       OR trunc(t.start_date + dates.numb) = trunc(SYSDATE - 365.25))
   AND trunc(t.start_date + dates.numb) >= t.start_date - 180 -- begin tracking 90 days prior to start
   AND trunc(t.start_date + dates.numb) <= t.end_date -- end tracking on last day of term
 ORDER BY report_date DESC,
          acyr_code   ASC;
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
v_msg     := 'START - ' || rec.acyr_code || ' - ' || rec.report_date || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
MERGE /*+*/
INTO utl_d_aim.rsbbregfci tgt
USING (SELECT v_etl_date AS rsbbregfci_activity_date,
              rec.report_date AS rsbbregfci_report_date,
              v_report_type AS rsbbregfci_report,
              tbg.fa_proc_year AS rsbbregfci_acyr_code,
              '000000' AS rsbbregfci_term_code,
              lcur.camp_code AS rsbbregfci_camp_code,
              '*' AS rsbbregfci_styp_code,
              lcur.levl_code AS rsbbregfci_levl_code,
              COUNT(DISTINCT sfrstca_pidm) AS rsbbregfci_reg,
              COUNT(DISTINCT fci.pidm) rsbbregfci_fci,
              NULL AS rsbbregfci_reg_fci,
              NULL AS rsbbregfci_reg_not_fci,
              NULL AS rsbbregfci_fci_not_reg,
              coalesce(SUM(sfrstca_credit_hr), 0) AS rsbbregfci_hours,
              coalesce(SUM(CASE
                           WHEN fci.pidm IS NOT NULL THEN
                            sfrstca_credit_hr
                           END), 0) AS rsbbregfci_fci_hours
         FROM saturn.sfrstca
         JOIN saturn.stvrsts
           ON stvrsts_code = sfrstca_rsts_code
          AND stvrsts_incl_sect_enrl = 'Y'
          AND sfrstca.sfrstca_seq_number = (SELECT MAX(d.sfrstca_seq_number)
                                              FROM sfrstca d
                                             WHERE d.sfrstca_pidm = sfrstca.sfrstca_pidm
                                               AND d.sfrstca_term_code = sfrstca.sfrstca_term_code
                                               AND d.sfrstca_crn = sfrstca.sfrstca_crn
                                               AND d.sfrstca_source_cde = 'BASE'
                                               AND d.sfrstca_rsts_date <= rec.report_timestamp -- runs at 4am everyday
                                            )
          AND sfrstca_rsts_date <= rec.report_timestamp -- runs at 4am everyday
          AND sfrstca_source_cde = 'BASE'
         JOIN (SELECT DISTINCT tbg.term_code,
                              tbg.fa_proc_year
                FROM zbtm.terms_by_group_v tbg
               WHERE tbg.group_code IN ('STD', 'MED')
                 AND tbg.fa_proc_year = rec.acyr_code) tbg
           ON tbg.term_code = sfrstca_term_code
         JOIN zsaturn.szrlevl l
           ON l.szrlevl_levl_code = sfrstca_levl_code
          AND l.szrlevl_is_stu_levl = 'Y'
          AND l.szrlevl_has_awardable_cred = 'Y'
         JOIN saturn.ssbsect
           ON ssbsect_term_code = sfrstca_term_code
          AND ssbsect_crn = sfrstca_crn
          AND ssbsect_subj_code NOT IN ('CSER', 'FRSM', 'GRST', 'NEWS', 'NSSR')
          AND trunc(ssbsect.ssbsect_ptrm_start_date) <= rec.report_timestamp -- THIS IS THE ONLY DIFFERENCE BETWEEN YTD AND TOTAL
         JOIN saturn.spriden
           ON spriden_pidm = sfrstca_pidm
          AND spriden_change_ind IS NULL
         JOIN zexec.zsavlcur lcur
           ON lcur.pidm = sfrstca_pidm
          AND sfrstca_term_code BETWEEN lcur.from_term AND lcur.end_term
         LEFT JOIN (SELECT DISTINCT fci.zfrfcis_pidm AS pidm,
                                   zfrfcis_term     AS term_code
                     FROM zfincheckin.zfrfcis fci
                    WHERE fci.zfrfcis_term IN (SELECT DISTINCT tbg.term_code
                                                 FROM zbtm.terms_by_group_v tbg
                                                WHERE tbg.group_code IN ('STD', 'MED')
                                                  AND tbg.fa_proc_year = rec.acyr_code)
                      AND fci.zfrfcis_withdrawn IS NULL) fci
           ON fci.pidm = sfrstca_pidm
          AND fci.term_code = sfrstca_term_code
        WHERE 1 = 1
        GROUP BY tbg.fa_proc_year,
                 lcur.camp_code,
                 lcur.levl_code) src
ON (tgt.rsbbregfci_report_date = src.rsbbregfci_report_date AND tgt.rsbbregfci_report = src.rsbbregfci_report AND tgt.rsbbregfci_acyr_code = src.rsbbregfci_acyr_code AND tgt.rsbbregfci_term_code = src.rsbbregfci_term_code AND tgt.rsbbregfci_camp_code = src.rsbbregfci_camp_code AND tgt.rsbbregfci_styp_code = src.rsbbregfci_styp_code AND tgt.rsbbregfci_levl_code = src.rsbbregfci_levl_code)
WHEN MATCHED THEN
UPDATE
   SET tgt.rsbbregfci_activity_date = src.rsbbregfci_activity_date,
       tgt.rsbbregfci_reg           = src.rsbbregfci_reg,
       tgt.rsbbregfci_fci           = src.rsbbregfci_fci,
       tgt.rsbbregfci_reg_fci       = src.rsbbregfci_reg_fci,
       tgt.rsbbregfci_reg_not_fci   = src.rsbbregfci_reg_not_fci,
       tgt.rsbbregfci_fci_not_reg   = src.rsbbregfci_fci_not_reg,
       tgt.rsbbregfci_hours         = src.rsbbregfci_hours,
       tgt.rsbbregfci_fci_hours     = src.rsbbregfci_fci_hours
WHEN NOT MATCHED THEN
INSERT
(rsbbregfci_report_date,
 rsbbregfci_report,
 rsbbregfci_acyr_code,
 rsbbregfci_term_code,
 rsbbregfci_camp_code,
 rsbbregfci_levl_code,
 rsbbregfci_styp_code,
 rsbbregfci_reg,
 rsbbregfci_fci,
 rsbbregfci_reg_fci,
 rsbbregfci_reg_not_fci,
 rsbbregfci_fci_not_reg,
 rsbbregfci_hours,
 rsbbregfci_activity_date,
 rsbbregfci_fci_hours)
VALUES
(src.rsbbregfci_report_date,
 src.rsbbregfci_report,
 src.rsbbregfci_acyr_code,
 src.rsbbregfci_term_code,
 src.rsbbregfci_camp_code,
 src.rsbbregfci_levl_code,
 src.rsbbregfci_styp_code,
 src.rsbbregfci_reg,
 src.rsbbregfci_fci,
 src.rsbbregfci_reg_fci,
 src.rsbbregfci_reg_not_fci,
 src.rsbbregfci_fci_not_reg,
 src.rsbbregfci_hours,
 src.rsbbregfci_activity_date,
 src.rsbbregfci_fci_hours);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || '000000' || ' - ' || rec.report_date || ' - ' || v_report_type || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
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
VERSION    DATE        USERNAME       UPDATES
1.0        05-26-2016  odavenport2    --Initial release
2.0        06-23-2016  odavenport2    --changed to pidm-based model; changed to dimensional dates model
3.0         10-04-2016  odavenport2    --changed to aggregate model; removed dimensional dates model; created new table
4.0        11-16-2018  odavenport2     --added FCI hours column
5.0        12-23-2020  lxhatfield      --changed new res logic
5.1        09-17-2021  lxhatfield      --fixed error where res new hours was using count distinct instead of sum
---     05-17-2023  WGRIFFITH2  --Dealing with EM courses and updating code to use job_log
---     07-24-2023  WGRIFFITH2  --TKT2753928-Optimization
---     10-13-2023  WGRIFFITH2  --Fixing issues from code updates on 7/24/23
---     10-23-2023  WGRIFFITH2  --sfrstca instead of sfrstcr - TKT2798583
---     10-26-2023  WGRIFFITH2  --split into different procs due to performance issues
---     04-25-2025  WGRIFFITH2  --group code was in the cursor and should not have been; extra loop of MED was overwriting the STD term data
---     10-24-2025  wgriffith2  --utl_d_aim.szrregs deprecation; removing all szrcurr joins from etl procedures live code
------------------------------------------------------------------------------------------------*/
END etl_aim_regfcisum_ytd_reg;

PROCEDURE etl_aim_regfcisum_total_reg(jobnumber   NUMBER,
                                      processid   VARCHAR2,
                                      processname VARCHAR2) IS
/*
Table: utl_d_aim.rsbbregfci

Primary Keys: RSBBREGFCI_REPORT_DATE, RSBBREGFCI_REPORT, RSBBREGFCI_ACYR_CODE, RSBBREGFCI_TERM_CODE, RSBBREGFCI_CAMP_CODE, RSBBREGFCI_STYP_CODE, RSBBREGFCI_LEVL_CODE

Unique index: RSBBREGFCI_REPORT_DATE, RSBBREGFCI_REPORT, RSBBREGFCI_ACYR_CODE, RSBBREGFCI_TERM_CODE, RSBBREGFCI_CAMP_CODE, RSBBREGFCI_STYP_CODE, RSBBREGFCI_LEVL_CODE

Purpose:
- Tracking reg and fci for all students

Conditions:
- Student has to be registered

*/
--DECLARE
--- PARAMS
v_etl_date    DATE := SYSDATE;
v_msg         VARCHAR2(2000);
v_instance    VARCHAR2(50) := upper('ALL'); -- inst from the jams job; used for determining instance
v_partition    NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_cpu         NUMBER := 4; -- number of CPUs used for parallelization - do not exceed 20 CPUs [v_mod x --v_cpu] if running simultaneously
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_report_type VARCHAR2(32) := 'total_reg';
v_proc        VARCHAR2(100) := 'etl_aim_regfcisum_total_reg';
CURSOR c_terms IS
SELECT DISTINCT t.fa_proc_year AS acyr_code,
                trunc(t.start_date + dates.numb) AS report_date,
                to_date(to_char(trunc(t.start_date + dates.numb) + (4 / 24), 'MM/DD/YYYY hh24:mi:ss'), 'MM/DD/YYYY hh24:mi:ss') report_timestamp -- runs at 4am everyday
  FROM zbtm.terms_by_group_v t
  JOIN (SELECT LEVEL - 180 numb FROM dual CONNECT BY LEVEL <= 360) dates
    ON t.start_date + dates.numb <= trunc(SYSDATE)
   AND t.term_code NOT IN ('000000')
   AND t.group_code IN ('STD', 'MED')
 WHERE 1 = 1
   AND (trunc(t.start_date + dates.numb) >= trunc(SYSDATE - 3) -- running the last 3 days to catch anything we might have missed; to_date('2025-04-07','YYYY-MM-DD')
       OR trunc(t.start_date + dates.numb) = trunc(SYSDATE - 365.25))
   AND trunc(t.start_date + dates.numb) >= t.start_date - 180 -- begin tracking 90 days prior to start
   AND trunc(t.start_date + dates.numb) <= t.end_date -- end tracking on last day of term
 ORDER BY report_date DESC,
          acyr_code   ASC;
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
v_msg     := 'START - ' || rec.acyr_code || ' - ' || rec.report_date || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
MERGE /*+*/
INTO utl_d_aim.rsbbregfci tgt
USING (SELECT v_etl_date AS rsbbregfci_activity_date,
              rec.report_date AS rsbbregfci_report_date,
              'total_reg' AS rsbbregfci_report,
              tbg.fa_proc_year AS rsbbregfci_acyr_code,
              '000000' AS rsbbregfci_term_code,
              lcur.camp_code AS rsbbregfci_camp_code,
              '*' AS rsbbregfci_styp_code,
              lcur.levl_code AS rsbbregfci_levl_code,
              COUNT(DISTINCT sfrstca_pidm) AS rsbbregfci_reg,
              COUNT(DISTINCT fci.pidm) rsbbregfci_fci,
              NULL AS rsbbregfci_reg_fci,
              NULL AS rsbbregfci_reg_not_fci,
              NULL AS rsbbregfci_fci_not_reg,
              coalesce(SUM(sfrstca_credit_hr), 0) AS rsbbregfci_hours,
              coalesce(SUM(CASE
                           WHEN fci.pidm IS NOT NULL THEN
                            sfrstca_credit_hr
                           END), 0) AS rsbbregfci_fci_hours
         FROM saturn.sfrstca
         JOIN saturn.stvrsts
           ON stvrsts_code = sfrstca_rsts_code
          AND stvrsts_incl_sect_enrl = 'Y'
          AND sfrstca.sfrstca_seq_number = (SELECT MAX(d.sfrstca_seq_number)
                                              FROM sfrstca d
                                             WHERE d.sfrstca_pidm = sfrstca.sfrstca_pidm
                                               AND d.sfrstca_term_code = sfrstca.sfrstca_term_code
                                               AND d.sfrstca_crn = sfrstca.sfrstca_crn
                                               AND d.sfrstca_source_cde = 'BASE'
                                               AND d.sfrstca_rsts_date <= rec.report_timestamp -- runs at 4am everyday
                                            )
          AND sfrstca_rsts_date <= rec.report_timestamp -- runs at 4am everyday
          AND sfrstca_source_cde = 'BASE'
         JOIN (SELECT DISTINCT tbg.term_code,
                              tbg.fa_proc_year
                FROM zbtm.terms_by_group_v tbg
               WHERE tbg.group_code IN ('STD', 'MED')
                 AND tbg.fa_proc_year = rec.acyr_code) tbg
           ON tbg.term_code = sfrstca_term_code
         JOIN zsaturn.szrlevl l
           ON l.szrlevl_levl_code = sfrstca_levl_code
          AND l.szrlevl_is_stu_levl = 'Y'
          AND l.szrlevl_has_awardable_cred = 'Y'
         JOIN saturn.ssbsect
           ON ssbsect_term_code = sfrstca_term_code
          AND ssbsect_crn = sfrstca_crn
          AND ssbsect_subj_code NOT IN ('CSER', 'FRSM', 'GRST', 'NEWS', 'NSSR')
       --  AND trunc(ll.start_date) <= rec.report_timestamp -- THIS IS THE ONLY DIFFERENCE BETWEEN YTD AND TOTAL
         JOIN saturn.spriden
           ON spriden_pidm = sfrstca_pidm
          AND spriden_change_ind IS NULL
         JOIN zexec.zsavlcur lcur
           ON lcur.pidm = sfrstca_pidm
          AND sfrstca_term_code BETWEEN lcur.from_term AND lcur.end_term
         LEFT JOIN (SELECT DISTINCT fci.zfrfcis_pidm AS pidm,
                                   zfrfcis_term     AS term_code
                     FROM zfincheckin.zfrfcis fci
                    WHERE fci.zfrfcis_term IN (SELECT DISTINCT tbg.term_code
                                                 FROM zbtm.terms_by_group_v tbg
                                                WHERE tbg.group_code IN ('STD', 'MED')
                                                  AND tbg.fa_proc_year = rec.acyr_code)
                      AND fci.zfrfcis_withdrawn IS NULL) fci
           ON fci.pidm = sfrstca_pidm
          AND fci.term_code = sfrstca_term_code
        WHERE 1 = 1
        GROUP BY tbg.fa_proc_year,
                 lcur.camp_code,
                 lcur.levl_code) src
ON (tgt.rsbbregfci_report_date = src.rsbbregfci_report_date AND tgt.rsbbregfci_report = src.rsbbregfci_report AND tgt.rsbbregfci_acyr_code = src.rsbbregfci_acyr_code AND tgt.rsbbregfci_term_code = src.rsbbregfci_term_code AND tgt.rsbbregfci_camp_code = src.rsbbregfci_camp_code AND tgt.rsbbregfci_styp_code = src.rsbbregfci_styp_code AND tgt.rsbbregfci_levl_code = src.rsbbregfci_levl_code)
WHEN MATCHED THEN
UPDATE
   SET tgt.rsbbregfci_activity_date = src.rsbbregfci_activity_date,
       tgt.rsbbregfci_reg           = src.rsbbregfci_reg,
       tgt.rsbbregfci_fci           = src.rsbbregfci_fci,
       tgt.rsbbregfci_reg_fci       = src.rsbbregfci_reg_fci,
       tgt.rsbbregfci_reg_not_fci   = src.rsbbregfci_reg_not_fci,
       tgt.rsbbregfci_fci_not_reg   = src.rsbbregfci_fci_not_reg,
       tgt.rsbbregfci_hours         = src.rsbbregfci_hours,
       tgt.rsbbregfci_fci_hours     = src.rsbbregfci_fci_hours
WHEN NOT MATCHED THEN
INSERT
(rsbbregfci_report_date,
 rsbbregfci_report,
 rsbbregfci_acyr_code,
 rsbbregfci_term_code,
 rsbbregfci_camp_code,
 rsbbregfci_levl_code,
 rsbbregfci_styp_code,
 rsbbregfci_reg,
 rsbbregfci_fci,
 rsbbregfci_reg_fci,
 rsbbregfci_reg_not_fci,
 rsbbregfci_fci_not_reg,
 rsbbregfci_hours,
 rsbbregfci_activity_date,
 rsbbregfci_fci_hours)
VALUES
(src.rsbbregfci_report_date,
 src.rsbbregfci_report,
 src.rsbbregfci_acyr_code,
 src.rsbbregfci_term_code,
 src.rsbbregfci_camp_code,
 src.rsbbregfci_levl_code,
 src.rsbbregfci_styp_code,
 src.rsbbregfci_reg,
 src.rsbbregfci_fci,
 src.rsbbregfci_reg_fci,
 src.rsbbregfci_reg_not_fci,
 src.rsbbregfci_fci_not_reg,
 src.rsbbregfci_hours,
 src.rsbbregfci_activity_date,
 src.rsbbregfci_fci_hours);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || '000000' || ' - ' || rec.report_date || ' - ' || 'total_reg' || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
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
VERSION    DATE        USERNAME       UPDATES
1.0        05-26-2016  odavenport2    --Initial release
2.0        06-23-2016  odavenport2    --changed to pidm-based model; changed to dimensional dates model
3.0         10-04-2016  odavenport2    --changed to aggregate model; removed dimensional dates model; created new table
4.0        11-16-2018  odavenport2     --added FCI hours column
5.0        12-23-2020  lxhatfield      --changed new res logic
5.1        09-17-2021  lxhatfield      --fixed error where res new hours was using count distinct instead of sum
---     05-17-2023  WGRIFFITH2  --Dealing with EM courses and updating code to use job_log
---     07-24-2023  WGRIFFITH2  --TKT2753928-Optimization
---     10-13-2023  WGRIFFITH2  --Fixing issues from code updates on 7/24/23
---     10-23-2023  WGRIFFITH2  --sfrstca instead of sfrstcr - TKT2798583
---     10-26-2023  WGRIFFITH2  --split into different procs due to performance issues
---     04-25-2025  WGRIFFITH2  --group code was in the cursor and should not have been; extra loop of MED was overwriting the STD term data
---     10-24-2025  wgriffith2  --utl_d_aim.szrregs deprecation; removing all szrcurr joins from etl procedures live code
------------------------------------------------------------------------------------------------*/
END etl_aim_regfcisum_total_reg;


PROCEDURE etl_aim_regfcisum_intl_reg(jobnumber   NUMBER,
                                     processid   VARCHAR2,
                                     processname VARCHAR2) IS
/*
Table: utl_d_aim.rsbbregfci

Primary Keys: RSBBREGFCI_REPORT_DATE, RSBBREGFCI_REPORT, RSBBREGFCI_ACYR_CODE, RSBBREGFCI_TERM_CODE, RSBBREGFCI_CAMP_CODE, RSBBREGFCI_STYP_CODE, RSBBREGFCI_LEVL_CODE

Unique index: RSBBREGFCI_REPORT_DATE, RSBBREGFCI_REPORT, RSBBREGFCI_ACYR_CODE, RSBBREGFCI_TERM_CODE, RSBBREGFCI_CAMP_CODE, RSBBREGFCI_STYP_CODE, RSBBREGFCI_LEVL_CODE

Purpose:
- Tracking reg and fci for all students

Conditions:
- Student has to be registered

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
v_report_type VARCHAR2(32) := 'intl_reg';
v_proc        VARCHAR2(100) := 'etl_aim_regfcisum_intl_reg';
CURSOR c_terms IS
SELECT DISTINCT t.fa_proc_year AS acyr_code,
                t.term_code,
                t.semester,
                t.group_code,
                trunc(t.start_date + dates.numb) AS report_date,
                to_date(to_char(trunc(t.start_date + dates.numb) + (4 / 24), 'MM/DD/YYYY hh24:mi:ss'), 'MM/DD/YYYY hh24:mi:ss') report_timestamp -- runs at 4am everyday
  FROM zbtm.terms_by_group_v t
  JOIN (SELECT LEVEL - 180 numb FROM dual CONNECT BY LEVEL <= 360) dates
    ON t.start_date + dates.numb <= trunc(SYSDATE)
   AND t.term_code NOT IN ('000000')
   AND t.group_code IN ('STD', 'MED')
 WHERE 1 = 1
   AND (trunc(t.start_date + dates.numb) >= trunc(SYSDATE - 3) -- running the last 3 days to catch anything we might have missed; to_date('2025-04-07','YYYY-MM-DD')
       OR trunc(t.start_date + dates.numb) = trunc(SYSDATE - 365.25))
   AND trunc(t.start_date + dates.numb) >= t.start_date - 180 -- begin tracking 90 days prior to start
   AND trunc(t.start_date + dates.numb) <= t.end_date -- end tracking on last day of term
 ORDER BY report_date DESC,
          acyr_code   ASC;
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
v_msg     := 'START - ' || rec.term_code || ' - ' || rec.report_date || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
MERGE INTO utl_d_aim.rsbbregfci tgt
USING (SELECT v_etl_date AS rsbbregfci_activity_date,
              f.rsbbregfci_report_date,
              v_report_type AS rsbbregfci_report,
              f.rsbbregfci_acyr_code,
              f.rsbbregfci_term_code,
              f.rsbbregfci_camp_code,
              f.rsbbregfci_styp_code,
              f.rsbbregfci_levl_code,
              f.rsbbregfci_reg,
              f.rsbbregfci_fci,
              f.rsbbregfci_reg_fci,
              f.rsbbregfci_reg_not_fci,
              f.rsbbregfci_fci_not_reg,
              f.rsbbregfci_hours,
              f.rsbbregfci_fci_hours
         FROM utl_d_aim.rsbbregfci f
         JOIN zsaturn.szrlevl l
           ON l.szrlevl_levl_code = rsbbregfci_levl_code
          AND l.szrlevl_is_stu_levl = 'Y'
          AND l.szrlevl_has_awardable_cred = 'Y'
        CROSS JOIN (SELECT term_code,
                          semester,
                          fa_proc_year
                     FROM zbtm.terms_by_group_v
                    WHERE start_date <= rec.report_date + 240
                      AND end_date >= rec.report_date
                      AND group_code = rec.group_code) tbg
        WHERE f.rsbbregfci_report IN (v_report_type||'_old') -- we need to pull the data that is already staged from the old proc
          AND f.rsbbregfci_camp_code != 'R'
          AND f.rsbbregfci_term_code = tbg.term_code
          AND f.rsbbregfci_report_date = rec.report_date) src
ON (tgt.rsbbregfci_report_date = src.rsbbregfci_report_date AND tgt.rsbbregfci_report = src.rsbbregfci_report AND tgt.rsbbregfci_acyr_code = src.rsbbregfci_acyr_code AND tgt.rsbbregfci_term_code = src.rsbbregfci_term_code AND tgt.rsbbregfci_camp_code = src.rsbbregfci_camp_code AND tgt.rsbbregfci_styp_code = src.rsbbregfci_styp_code AND tgt.rsbbregfci_levl_code = src.rsbbregfci_levl_code)
WHEN MATCHED THEN
UPDATE
   SET tgt.rsbbregfci_activity_date = src.rsbbregfci_activity_date,
       tgt.rsbbregfci_reg           = src.rsbbregfci_reg,
       tgt.rsbbregfci_fci           = src.rsbbregfci_fci,
       tgt.rsbbregfci_reg_fci       = src.rsbbregfci_reg_fci,
       tgt.rsbbregfci_reg_not_fci   = src.rsbbregfci_reg_not_fci,
       tgt.rsbbregfci_fci_not_reg   = src.rsbbregfci_fci_not_reg,
       tgt.rsbbregfci_hours         = src.rsbbregfci_hours,
       tgt.rsbbregfci_fci_hours     = src.rsbbregfci_fci_hours
WHEN NOT MATCHED THEN
INSERT
(rsbbregfci_report_date,
 rsbbregfci_report,
 rsbbregfci_acyr_code,
 rsbbregfci_term_code,
 rsbbregfci_camp_code,
 rsbbregfci_levl_code,
 rsbbregfci_styp_code,
 rsbbregfci_reg,
 rsbbregfci_fci,
 rsbbregfci_reg_fci,
 rsbbregfci_reg_not_fci,
 rsbbregfci_fci_not_reg,
 rsbbregfci_hours,
 rsbbregfci_activity_date,
 rsbbregfci_fci_hours)
VALUES
(src.rsbbregfci_report_date,
 src.rsbbregfci_report,
 src.rsbbregfci_acyr_code,
 src.rsbbregfci_term_code,
 src.rsbbregfci_camp_code,
 src.rsbbregfci_levl_code,
 src.rsbbregfci_styp_code,
 src.rsbbregfci_reg,
 src.rsbbregfci_fci,
 src.rsbbregfci_reg_fci,
 src.rsbbregfci_reg_not_fci,
 src.rsbbregfci_fci_not_reg,
 src.rsbbregfci_hours,
 src.rsbbregfci_activity_date,
 src.rsbbregfci_fci_hours);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || '000000' || ' - ' || rec.report_date || ' - ' || v_report_type || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
--intl_reg_res
MERGE INTO utl_d_aim.rsbbregfci tgt
USING (SELECT v_etl_date AS rsbbregfci_activity_date,
              rec.report_date AS rsbbregfci_report_date,
              v_report_type AS rsbbregfci_report,
              term.fa_proc_year AS rsbbregfci_acyr_code,
              term.term_code AS rsbbregfci_term_code,
              'R' AS rsbbregfci_camp_code,
              'R' AS rsbbregfci_styp_code,
              dd.levl_code AS rsbbregfci_levl_code,
              COUNT(DISTINCT CASE
                    WHEN dd.registration_ind = 1 THEN
                     dd.pidm
                    END) AS rsbbregfci_reg,
              COUNT(DISTINCT CASE
                    WHEN dd.fci_ind = 1 THEN
                     dd.pidm
                    END) AS rsbbregfci_fci,
              COUNT(DISTINCT CASE
                    WHEN dd.registration_ind = 1
                         AND dd.fci_ind = 1 THEN
                     dd.pidm
                    END) AS rsbbregfci_reg_fci,
              COUNT(DISTINCT CASE
                    WHEN dd.registration_ind = 1
                         AND dd.fci_ind = 0 THEN
                     dd.pidm
                    END) AS rsbbregfci_reg_not_fci,
              COUNT(DISTINCT CASE
                    WHEN dd.registration_ind = 0
                         AND dd.fci_ind = 1 THEN
                     dd.pidm
                    END) AS rsbbregfci_fci_not_reg,
              coalesce(SUM(dd.total_reg_hours), 0) AS rsbbregfci_hours,
              coalesce(SUM(CASE
                           WHEN dd.fci_ind = 1 THEN
                            dd.total_reg_hours
                           END), 0) AS rsbbregfci_fci_hours
         FROM utl_d_res.mrbbmrappsdd dd
         JOIN zsaturn.szrlevl l
           ON l.szrlevl_levl_code = dd.levl_code
          AND l.szrlevl_is_stu_levl = 'Y'
          AND l.szrlevl_has_awardable_cred = 'Y'
         JOIN (SELECT term_code,
                     semester,
                     fa_proc_year
                FROM zbtm.terms_by_group_v
               WHERE start_date <= rec.report_date + 240
                 AND end_date >= rec.report_date
                 AND group_code = rec.group_code) term
           ON term.term_code = dd.term_code
        WHERE dd.report_date = (SELECT MAX(dd2.report_date)
                                  FROM utl_d_res.mrbbmrappsdd dd2
                                 WHERE dd2.term_code = dd.term_code
                                   AND dd2.report_date <= rec.report_date)
          AND dd.population = 'Return'
          AND dd.citz_ind = 'N'
        GROUP BY term.fa_proc_year,
                 term.term_code,
                 dd.levl_code) src
ON (tgt.rsbbregfci_report_date = src.rsbbregfci_report_date AND tgt.rsbbregfci_report = src.rsbbregfci_report AND tgt.rsbbregfci_acyr_code = src.rsbbregfci_acyr_code AND tgt.rsbbregfci_term_code = src.rsbbregfci_term_code AND tgt.rsbbregfci_camp_code = src.rsbbregfci_camp_code AND tgt.rsbbregfci_styp_code = src.rsbbregfci_styp_code AND tgt.rsbbregfci_levl_code = src.rsbbregfci_levl_code)
WHEN MATCHED THEN
UPDATE
   SET tgt.rsbbregfci_activity_date = src.rsbbregfci_activity_date,
       tgt.rsbbregfci_reg           = src.rsbbregfci_reg,
       tgt.rsbbregfci_fci           = src.rsbbregfci_fci,
       tgt.rsbbregfci_reg_fci       = src.rsbbregfci_reg_fci,
       tgt.rsbbregfci_reg_not_fci   = src.rsbbregfci_reg_not_fci,
       tgt.rsbbregfci_fci_not_reg   = src.rsbbregfci_fci_not_reg,
       tgt.rsbbregfci_hours         = src.rsbbregfci_hours,
       tgt.rsbbregfci_fci_hours     = src.rsbbregfci_fci_hours
WHEN NOT MATCHED THEN
INSERT
(rsbbregfci_report_date,
 rsbbregfci_report,
 rsbbregfci_acyr_code,
 rsbbregfci_term_code,
 rsbbregfci_camp_code,
 rsbbregfci_levl_code,
 rsbbregfci_styp_code,
 rsbbregfci_reg,
 rsbbregfci_fci,
 rsbbregfci_reg_fci,
 rsbbregfci_reg_not_fci,
 rsbbregfci_fci_not_reg,
 rsbbregfci_hours,
 rsbbregfci_activity_date,
 rsbbregfci_fci_hours)
VALUES
(src.rsbbregfci_report_date,
 src.rsbbregfci_report,
 src.rsbbregfci_acyr_code,
 src.rsbbregfci_term_code,
 src.rsbbregfci_camp_code,
 src.rsbbregfci_levl_code,
 src.rsbbregfci_styp_code,
 src.rsbbregfci_reg,
 src.rsbbregfci_fci,
 src.rsbbregfci_reg_fci,
 src.rsbbregfci_reg_not_fci,
 src.rsbbregfci_fci_not_reg,
 src.rsbbregfci_hours,
 src.rsbbregfci_activity_date,
 src.rsbbregfci_fci_hours);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || '000000' || ' - ' || rec.report_date || ' - ' || v_report_type || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
--intl_new
MERGE INTO utl_d_aim.rsbbregfci tgt
USING (SELECT v_etl_date AS rsbbregfci_activity_date,
              rec.report_date AS rsbbregfci_report_date,
              v_report_type AS rsbbregfci_report,
              term.fa_proc_year AS rsbbregfci_acyr_code,
              term.term_code AS rsbbregfci_term_code,
              'R' AS rsbbregfci_camp_code,
              'N' AS rsbbregfci_styp_code,
              dd.levl_code AS rsbbregfci_levl_code,
              COUNT(DISTINCT CASE
                    WHEN dd.apst_code <> 'W'
                         AND zsavappl_camplevl_rank = 1
                        --and dd.apdc_code like 'A%'
                         AND dd.registration_ind = 1 THEN
                     dd.pidm
                    END) AS rsbbregfci_reg,
              COUNT(DISTINCT CASE
                    WHEN dd.apst_code <> 'W'
                         AND dd.zsavappl_camplevl_rank = 1
                         AND dd.fci_ind = 1
                    --and dd.apdc_code like 'A%'
                     THEN
                     dd.pidm
                    END) AS rsbbregfci_fci,
              COUNT(DISTINCT CASE
                    WHEN dd.apst_code <> 'W'
                         AND zsavappl_camplevl_rank = 1
                         AND dd.registration_ind = 1
                         AND dd.fci_ind = 1
                    --and dd.apdc_code like 'A%'
                     THEN
                     dd.pidm
                    END) AS rsbbregfci_reg_fci,
              COUNT(DISTINCT CASE
                    WHEN dd.apst_code <> 'W'
                         AND zsavappl_camplevl_rank = 1
                         AND dd.registration_ind = 1
                         AND dd.fci_ind = 0
                    --and dd.apdc_code like 'A%'
                     THEN
                     dd.pidm
                    END) AS rsbbregfci_reg_not_fci,
              COUNT(DISTINCT CASE
                    WHEN dd.apst_code <> 'W'
                         AND zsavappl_camplevl_rank = 1
                         AND dd.registration_ind = 0
                         AND dd.fci_ind = 1
                    --and dd.apdc_code like 'A%'
                     THEN
                     dd.pidm
                    END) AS rsbbregfci_fci_not_reg,
              SUM(CASE
                  WHEN dd.apst_code <> 'W'
                       AND zsavappl_camplevl_rank = 1
                      --and dd.apdc_code like 'A%'
                       AND dd.registration_ind = 1 THEN
                   dd.total_reg_hours
                  END) AS rsbbregfci_hours,
              SUM(CASE
                  WHEN dd.apst_code <> 'W'
                       AND dd.zsavappl_camplevl_rank = 1
                       AND dd.fci_ind = 1
                  --and dd.apdc_code like 'A%'
                   THEN
                   dd.total_reg_hours
                  END) AS rsbbregfci_fci_hours
         FROM utl_d_res.mrbbmrappsdd dd
         JOIN zsaturn.szrlevl l
           ON l.szrlevl_levl_code = dd.levl_code
          AND l.szrlevl_is_stu_levl = 'Y'
          AND l.szrlevl_has_awardable_cred = 'Y'
         JOIN (SELECT term_code,
                     semester,
                     fa_proc_year
                FROM zbtm.terms_by_group_v
               WHERE start_date <= rec.report_date + 240
                 AND end_date >= rec.report_date
                 AND group_code = rec.group_code) term
           ON term.term_code = dd.term_code
        WHERE dd.citz_ind = 'N'
          AND dd.population = 'New'
          AND dd.report_date = (SELECT MAX(dd2.report_date)
                                  FROM utl_d_res.mrbbmrappsdd dd2
                                 WHERE dd2.term_code = dd.term_code
                                   AND dd2.report_date <= rec.report_date)
        GROUP BY dd.camp_code,
                 dd.levl_code,
                 term.fa_proc_year,
                 term.term_code) src
ON (tgt.rsbbregfci_report_date = src.rsbbregfci_report_date AND tgt.rsbbregfci_report = src.rsbbregfci_report AND tgt.rsbbregfci_acyr_code = src.rsbbregfci_acyr_code AND tgt.rsbbregfci_term_code = src.rsbbregfci_term_code AND tgt.rsbbregfci_camp_code = src.rsbbregfci_camp_code AND tgt.rsbbregfci_styp_code = src.rsbbregfci_styp_code AND tgt.rsbbregfci_levl_code = src.rsbbregfci_levl_code)
WHEN MATCHED THEN
UPDATE
   SET tgt.rsbbregfci_activity_date = src.rsbbregfci_activity_date,
       tgt.rsbbregfci_reg           = src.rsbbregfci_reg,
       tgt.rsbbregfci_fci           = src.rsbbregfci_fci,
       tgt.rsbbregfci_reg_fci       = src.rsbbregfci_reg_fci,
       tgt.rsbbregfci_reg_not_fci   = src.rsbbregfci_reg_not_fci,
       tgt.rsbbregfci_fci_not_reg   = src.rsbbregfci_fci_not_reg,
       tgt.rsbbregfci_hours         = src.rsbbregfci_hours,
       tgt.rsbbregfci_fci_hours     = src.rsbbregfci_fci_hours
WHEN NOT MATCHED THEN
INSERT
(rsbbregfci_report_date,
 rsbbregfci_report,
 rsbbregfci_acyr_code,
 rsbbregfci_term_code,
 rsbbregfci_camp_code,
 rsbbregfci_levl_code,
 rsbbregfci_styp_code,
 rsbbregfci_reg,
 rsbbregfci_fci,
 rsbbregfci_reg_fci,
 rsbbregfci_reg_not_fci,
 rsbbregfci_fci_not_reg,
 rsbbregfci_hours,
 rsbbregfci_activity_date,
 rsbbregfci_fci_hours)
VALUES
(src.rsbbregfci_report_date,
 src.rsbbregfci_report,
 src.rsbbregfci_acyr_code,
 src.rsbbregfci_term_code,
 src.rsbbregfci_camp_code,
 src.rsbbregfci_levl_code,
 src.rsbbregfci_styp_code,
 src.rsbbregfci_reg,
 src.rsbbregfci_fci,
 src.rsbbregfci_reg_fci,
 src.rsbbregfci_reg_not_fci,
 src.rsbbregfci_fci_not_reg,
 src.rsbbregfci_hours,
 src.rsbbregfci_activity_date,
 src.rsbbregfci_fci_hours);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || '000000' || ' - ' || rec.report_date || ' - ' || v_report_type || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
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
VERSION    DATE        USERNAME       UPDATES
1.0        05-26-2016  odavenport2    --Initial release
2.0        06-23-2016  odavenport2    --changed to pidm-based model; changed to dimensional dates model
3.0         10-04-2016  odavenport2    --changed to aggregate model; removed dimensional dates model; created new table
4.0        11-16-2018  odavenport2     --added FCI hours column
5.0        12-23-2020  lxhatfield      --changed new res logic
5.1        09-17-2021  lxhatfield      --fixed error where res new hours was using count distinct instead of sum
---     05-17-2023  WGRIFFITH2  --Dealing with EM courses and updating code to use job_log
---     07-24-2023  WGRIFFITH2  --TKT2753928-Optimization
---     10-13-2023  WGRIFFITH2  --Fixing issues from code updates on 7/24/23
---     10-23-2023  WGRIFFITH2  --sfrstca instead of sfrstcr - TKT2798583
---     10-26-2023  WGRIFFITH2  --split into different procs due to performance issues
------------------------------------------------------------------------------------------------*/
END etl_aim_regfcisum_intl_reg;

PROCEDURE etl_aim_regfcisum_new_res(jobnumber   NUMBER,
                                    processid   VARCHAR2,
                                    processname VARCHAR2) IS
/*
Table: utl_d_aim.rsbbregfci

Primary Keys: RSBBREGFCI_REPORT_DATE, RSBBREGFCI_REPORT, RSBBREGFCI_ACYR_CODE, RSBBREGFCI_TERM_CODE, RSBBREGFCI_CAMP_CODE, RSBBREGFCI_STYP_CODE, RSBBREGFCI_LEVL_CODE

Unique index: RSBBREGFCI_REPORT_DATE, RSBBREGFCI_REPORT, RSBBREGFCI_ACYR_CODE, RSBBREGFCI_TERM_CODE, RSBBREGFCI_CAMP_CODE, RSBBREGFCI_STYP_CODE, RSBBREGFCI_LEVL_CODE

Purpose:
- Tracking reg and fci for all students

Conditions:
- Student has to be registered

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
v_report_type VARCHAR2(32) := 'new_res';
v_proc        VARCHAR2(100) := 'etl_aim_regfcisum_new_res';
CURSOR c_terms IS
SELECT DISTINCT t.fa_proc_year AS acyr_code,
                t.term_code,
                t.semester,
                t.group_code,
                trunc(t.start_date + dates.numb) AS report_date,
                to_date(to_char(trunc(t.start_date + dates.numb) + (4 / 24), 'MM/DD/YYYY hh24:mi:ss'), 'MM/DD/YYYY hh24:mi:ss') report_timestamp -- runs at 4am everyday
  FROM zbtm.terms_by_group_v t
  JOIN (SELECT LEVEL - 180 numb FROM dual CONNECT BY LEVEL <= 360) dates
    ON t.start_date + dates.numb <= trunc(SYSDATE)
   AND t.term_code NOT IN ('000000')
   AND t.group_code IN ('STD', 'MED')
 WHERE 1 = 1
   AND (trunc(t.start_date + dates.numb) >= trunc(SYSDATE - 3) -- running the last 3 days to catch anything we might have missed; to_date('2025-04-07','YYYY-MM-DD')
       OR trunc(t.start_date + dates.numb) = trunc(SYSDATE - 365.25))
   AND trunc(t.start_date + dates.numb) >= t.start_date - 180 -- begin tracking 90 days prior to start
   AND trunc(t.start_date + dates.numb) <= t.end_date -- end tracking on last day of term
 ORDER BY report_date DESC,
          acyr_code   ASC;
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
v_msg     := 'START - ' || rec.term_code || ' - ' || rec.report_date || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- truncate table  utl_d_aim.rsbbregfci_gtt;
INSERT INTO utl_d_aim.rsbbregfci_gtt
(rsbbregfci_pidm,
 rsbbregfci_acyr_code,
 rsbbregfci_term_code,
 rsbbregfci_camp_code,
 rsbbregfci_levl_code,
 rsbbregfci_styp_code,
 rsbbregfci_reg,
 rsbbregfci_fci,
 rsbbregfci_hours,
 rsbbregfci_fci_hours,
 rsbbregfci_report_date)
SELECT spriden_pidm,
       rec.acyr_code,
       rec.term_code,
       sgbstdn_camp_code,
       sgbstdn_levl_code,
       CASE
       WHEN sgbstdn_camp_code = 'R'
            AND appl.zsavappl_pidm IS NOT NULL THEN
        'N' -- RES student with App
       WHEN sgbstdn_camp_code = 'D'
            AND enrl_last_yr.pidm IS NULL THEN
        'N' -- LUO student not reg last year
       ELSE
        'R'
       END styp_code,
       CASE
       WHEN reg.pidm IS NOT NULL THEN
        1
       END AS reg_ind,
       CASE
       WHEN fci.pidm IS NOT NULL THEN
        1
       END fci_ind,
       reg.hours,
       CASE
       WHEN fci.pidm IS NOT NULL THEN
        reg.hours
       END fci_hours,
       rec.report_date
  FROM spriden
  JOIN sgbstdn
    ON sgbstdn_pidm = spriden_pidm
   AND sgbstdn_camp_code IS NOT NULL
   AND sgbstdn_program_1 IS NOT NULL
   AND spriden_change_ind IS NULL
   AND sgbstdn_term_code_eff = (SELECT MAX(d.sgbstdn_term_code_eff)
                                  FROM sgbstdn d
                                 WHERE d.sgbstdn_pidm = sgbstdn.sgbstdn_pidm
                                   AND d.sgbstdn_term_code_eff <= rec.term_code)
  JOIN zsaturn.szrlevl l
    ON l.szrlevl_levl_code = sgbstdn_levl_code
   AND l.szrlevl_is_stu_levl = 'Y'
   AND l.szrlevl_has_awardable_cred = 'Y'
  LEFT JOIN zexec.zsavappl appl
    ON appl.zsavappl_pidm = spriden_pidm
   AND appl.zsavappl_levl_code = sgbstdn_levl_code
   AND appl.zsavappl_camp_code = sgbstdn_camp_code
   AND appl.zsavappl_camp_code = 'R'
   AND appl.zsavappl_apdc_code IN (SELECT stvapdc_code FROM stvapdc WHERE stvapdc_inst_acc_ind = 'Y')
   AND appl.zsavappl_apst_code <> 'W'
   AND appl.zsavappl_term_code IN (rec.term_code, CASE WHEN rec.semester = 'FAL' THEN rec.term_code - 10 END)
  LEFT JOIN (SELECT DISTINCT enrl.pidm FROM utl_d_aim.szrenrl enrl WHERE enrl.acad_year = rec.acyr_code - 101) enrl_last_yr
    ON enrl_last_yr.pidm = spriden_pidm
  LEFT JOIN (SELECT sfrstca_pidm AS pidm,
                    SUM(sfrstca_credit_hr) AS hours
               FROM saturn.sfrstca
               JOIN saturn.stvrsts
                 ON stvrsts_code = sfrstca_rsts_code
                AND stvrsts_incl_sect_enrl = 'Y'
                AND sfrstca.sfrstca_seq_number = (SELECT MAX(d.sfrstca_seq_number)
                                                    FROM sfrstca d
                                                   WHERE d.sfrstca_pidm = sfrstca.sfrstca_pidm
                                                     AND d.sfrstca_term_code = sfrstca.sfrstca_term_code
                                                     AND d.sfrstca_crn = sfrstca.sfrstca_crn
                                                     AND d.sfrstca_source_cde = 'BASE'
                                                     AND d.sfrstca_rsts_date <= rec.report_timestamp -- runs at 4am everyday
                                                  )
               JOIN zsaturn.szrlevl l
                 ON l.szrlevl_levl_code = sfrstca_levl_code
                AND l.szrlevl_is_stu_levl = 'Y'
                AND l.szrlevl_has_awardable_cred = 'Y'
               JOIN ssbsect
                 ON ssbsect_term_code = sfrstca_term_code
                AND ssbsect_crn = sfrstca_crn
                AND ssbsect_subj_code NOT IN ('CSER', 'FRSM', 'GRST', 'NEWS', 'NSSR')
              WHERE 1 = 1
                AND sfrstca_term_code = rec.term_code
                AND sfrstca_rsts_date <= rec.report_timestamp -- runs at 4am everyday
                AND sfrstca_source_cde = 'BASE'
              GROUP BY sfrstca_pidm) reg
    ON reg.pidm = spriden_pidm
  LEFT JOIN (SELECT DISTINCT fci.zfrfcis_pidm AS pidm
               FROM zfincheckin.zfrfcis fci
              WHERE fci.zfrfcis_term = rec.term_code
                AND fci.zfrfcis_withdrawn IS NULL) fci
    ON fci.pidm = spriden_pidm
 WHERE 1 = 1
   AND (reg.pidm IS NOT NULL OR fci.pidm IS NOT NULL)
   AND NOT EXISTS (SELECT 'X'
          FROM utl_d_aim.rsbbregfci_gtt gtt
         WHERE gtt.rsbbregfci_term_code = rec.term_code
           AND gtt.rsbbregfci_pidm = reg.pidm
           AND gtt.rsbbregfci_report_date = rec.report_date);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || rec.term_code || ' - ' || rec.report_date || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
MERGE INTO utl_d_aim.rsbbregfci tgt
USING (SELECT v_etl_date AS rsbbregfci_activity_date,
              rec.report_date AS rsbbregfci_report_date,
              v_report_type AS rsbbregfci_report,
              term.fa_proc_year AS rsbbregfci_acyr_code,
              term.term_code AS rsbbregfci_term_code,
              dd.camp_code AS rsbbregfci_camp_code,
              dd.student_type AS rsbbregfci_styp_code,
              CASE
              WHEN dd.levl_code IN ('GR', 'DR') THEN
               'GR'
              ELSE
               'UG'
              END AS rsbbregfci_levl_code,
              COUNT(DISTINCT CASE
                    WHEN dd.apst_code <> 'W'
                         AND zsavappl_camplevl_rank = 1
                        --and dd.apdc_code like 'A%'
                         AND dd.registration_ind = 1 THEN
                     dd.pidm
                    END) AS rsbbregfci_reg,
              COUNT(DISTINCT CASE
                    WHEN dd.apst_code <> 'W'
                         AND dd.zsavappl_camplevl_rank = 1
                         AND dd.fci_ind = 1
                    --and dd.apdc_code like 'A%'
                     THEN
                     dd.pidm
                    END) AS rsbbregfci_fci,
              COUNT(DISTINCT CASE
                    WHEN dd.apst_code <> 'W'
                         AND zsavappl_camplevl_rank = 1
                         AND dd.registration_ind = 1
                         AND dd.fci_ind = 1
                    --and dd.apdc_code like 'A%'
                     THEN
                     dd.pidm
                    END) AS rsbbregfci_reg_fci,
              COUNT(DISTINCT CASE
                    WHEN dd.apst_code <> 'W'
                         AND zsavappl_camplevl_rank = 1
                         AND dd.registration_ind = 1
                         AND dd.fci_ind = 0
                    --and dd.apdc_code like 'A%'
                     THEN
                     dd.pidm
                    END) AS rsbbregfci_reg_not_fci,
              COUNT(DISTINCT CASE
                    WHEN dd.apst_code <> 'W'
                         AND zsavappl_camplevl_rank = 1
                         AND dd.registration_ind = 0
                         AND dd.fci_ind = 1
                    --and dd.apdc_code like 'A%'
                     THEN
                     dd.pidm
                    END) AS rsbbregfci_fci_not_reg,
              SUM(CASE
                  WHEN dd.apst_code <> 'W'
                       AND zsavappl_camplevl_rank = 1
                      --and dd.apdc_code like 'A%'
                       AND dd.registration_ind = 1 THEN
                   dd.total_reg_hours
                  END) AS rsbbregfci_hours,
              SUM(CASE
                  WHEN dd.apst_code <> 'W'
                       AND dd.zsavappl_camplevl_rank = 1
                       AND dd.fci_ind = 1
                  --and dd.apdc_code like 'A%'
                   THEN
                   dd.total_reg_hours
                  END) AS rsbbregfci_fci_hours
         FROM utl_d_res.mrbbmrappsdd dd
         JOIN zsaturn.szrlevl l
           ON l.szrlevl_levl_code = dd.levl_code
          AND l.szrlevl_is_stu_levl = 'Y'
          AND l.szrlevl_has_awardable_cred = 'Y'
         JOIN (SELECT term_code,
                     CASE
                     WHEN semester = 'FAL'
                          AND group_code = 'STD' THEN
                      to_char(term_code - 10)
                     ELSE
                      term_code
                     END prev_term,
                     semester,
                     fa_proc_year
                FROM zbtm.terms_by_group_v
               WHERE start_date <= rec.report_date + 240
                 AND end_date >= rec.report_date
                 AND group_code = rec.group_code) term
           ON term.term_code = dd.term_code
        WHERE dd.report_date = (SELECT MAX(dd2.report_date)
                                  FROM utl_d_res.mrbbmrappsdd dd2
                                 WHERE dd2.term_code = dd.term_code
                                   AND dd2.report_date <= rec.report_date)
          AND dd.population = 'New'
          AND dd.levl_code NOT IN ('JD', 'MD')
        GROUP BY term.fa_proc_year,
                 term.term_code,
                 dd.camp_code,
                 dd.student_type,
                 CASE
                 WHEN dd.levl_code IN ('GR', 'DR') THEN
                  'GR'
                 ELSE
                  'UG'
                 END) src
ON (tgt.rsbbregfci_report_date = src.rsbbregfci_report_date AND tgt.rsbbregfci_report = src.rsbbregfci_report AND tgt.rsbbregfci_acyr_code = src.rsbbregfci_acyr_code AND tgt.rsbbregfci_term_code = src.rsbbregfci_term_code AND tgt.rsbbregfci_camp_code = src.rsbbregfci_camp_code AND tgt.rsbbregfci_styp_code = src.rsbbregfci_styp_code AND tgt.rsbbregfci_levl_code = src.rsbbregfci_levl_code)
WHEN MATCHED THEN
UPDATE
   SET tgt.rsbbregfci_activity_date = src.rsbbregfci_activity_date,
       tgt.rsbbregfci_reg           = src.rsbbregfci_reg,
       tgt.rsbbregfci_fci           = src.rsbbregfci_fci,
       tgt.rsbbregfci_reg_fci       = src.rsbbregfci_reg_fci,
       tgt.rsbbregfci_reg_not_fci   = src.rsbbregfci_reg_not_fci,
       tgt.rsbbregfci_fci_not_reg   = src.rsbbregfci_fci_not_reg,
       tgt.rsbbregfci_hours         = src.rsbbregfci_hours,
       tgt.rsbbregfci_fci_hours     = src.rsbbregfci_fci_hours
WHEN NOT MATCHED THEN
INSERT
(rsbbregfci_report_date,
 rsbbregfci_report,
 rsbbregfci_acyr_code,
 rsbbregfci_term_code,
 rsbbregfci_camp_code,
 rsbbregfci_levl_code,
 rsbbregfci_styp_code,
 rsbbregfci_reg,
 rsbbregfci_fci,
 rsbbregfci_reg_fci,
 rsbbregfci_reg_not_fci,
 rsbbregfci_fci_not_reg,
 rsbbregfci_hours,
 rsbbregfci_activity_date,
 rsbbregfci_fci_hours)
VALUES
(src.rsbbregfci_report_date,
 src.rsbbregfci_report,
 src.rsbbregfci_acyr_code,
 src.rsbbregfci_term_code,
 src.rsbbregfci_camp_code,
 src.rsbbregfci_levl_code,
 src.rsbbregfci_styp_code,
 src.rsbbregfci_reg,
 src.rsbbregfci_fci,
 src.rsbbregfci_reg_fci,
 src.rsbbregfci_reg_not_fci,
 src.rsbbregfci_fci_not_reg,
 src.rsbbregfci_hours,
 src.rsbbregfci_activity_date,
 src.rsbbregfci_fci_hours);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || rec.term_code || ' - ' || rec.report_date || ' - ' || v_report_type || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
utl_d_aim.truncate_table(v_table_name => 'rsbbregfci_gtt'); -- REMOVE RECORDS AFTER EVERY LOOP
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
VERSION    DATE        USERNAME       UPDATES
1.0        05-26-2016  odavenport2    --Initial release
2.0        06-23-2016  odavenport2    --changed to pidm-based model; changed to dimensional dates model
3.0         10-04-2016  odavenport2    --changed to aggregate model; removed dimensional dates model; created new table
4.0        11-16-2018  odavenport2     --added FCI hours column
5.0        12-23-2020  lxhatfield      --changed new res logic
5.1        09-17-2021  lxhatfield      --fixed error where res new hours was using count distinct instead of sum
---     05-17-2023  WGRIFFITH2  --Dealing with EM courses and updating code to use job_log
---     07-24-2023  WGRIFFITH2  --TKT2753928-Optimization
---     10-13-2023  WGRIFFITH2  --Fixing issues from code updates on 7/24/23
---     10-23-2023  WGRIFFITH2  --sfrstca instead of sfrstcr - TKT2798583
---     10-26-2023  WGRIFFITH2  --split into different procs due to performance issues
------------------------------------------------------------------------------------------------*/
END etl_aim_regfcisum_new_res;

PROCEDURE etl_aim_regfcisum_main_reg_res_new(jobnumber   NUMBER,
                                             processid   VARCHAR2,
                                             processname VARCHAR2) IS
/*
Table: utl_d_aim.rsbbregfci

Primary Keys: RSBBREGFCI_REPORT_DATE, RSBBREGFCI_REPORT, RSBBREGFCI_ACYR_CODE, RSBBREGFCI_TERM_CODE, RSBBREGFCI_CAMP_CODE, RSBBREGFCI_STYP_CODE, RSBBREGFCI_LEVL_CODE

Unique index: RSBBREGFCI_REPORT_DATE, RSBBREGFCI_REPORT, RSBBREGFCI_ACYR_CODE, RSBBREGFCI_TERM_CODE, RSBBREGFCI_CAMP_CODE, RSBBREGFCI_STYP_CODE, RSBBREGFCI_LEVL_CODE

Purpose:
- Tracking reg and fci for all students

Conditions:
- Student has to be registered

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
v_report_type VARCHAR2(32) := 'main_reg';
v_proc        VARCHAR2(100) := 'etl_aim_regfcisum_main_reg_res_new';
CURSOR c_terms IS
SELECT DISTINCT t.fa_proc_year AS acyr_code,
                t.term_code,
                t.semester,
                t.group_code,
                trunc(t.start_date + dates.numb) AS report_date,
                to_date(to_char(trunc(t.start_date + dates.numb) + (4 / 24), 'MM/DD/YYYY hh24:mi:ss'), 'MM/DD/YYYY hh24:mi:ss') report_timestamp -- runs at 4am everyday
  FROM zbtm.terms_by_group_v t
  JOIN (SELECT LEVEL - 180 numb FROM dual CONNECT BY LEVEL <= 360) dates
    ON t.start_date + dates.numb <= trunc(SYSDATE)
   AND t.term_code NOT IN ('000000')
   AND t.group_code IN ('STD', 'MED')
 WHERE 1 = 1
   AND (trunc(t.start_date + dates.numb) >= trunc(SYSDATE - 3) -- running the last 3 days to catch anything we might have missed; to_date('2025-04-07','YYYY-MM-DD')
       OR trunc(t.start_date + dates.numb) = trunc(SYSDATE - 365.25))
   AND trunc(t.start_date + dates.numb) >= t.start_date - 180 -- begin tracking 90 days prior to start
   AND trunc(t.start_date + dates.numb) <= t.end_date -- end tracking on last day of term
 ORDER BY report_date DESC,
          acyr_code   ASC;
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
v_msg     := 'START - ' || rec.term_code || ' - ' || rec.report_date || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
--res new
MERGE INTO utl_d_aim.rsbbregfci tgt
USING (SELECT v_etl_date AS rsbbregfci_activity_date,
              rec.report_date AS rsbbregfci_report_date,
              v_report_type AS rsbbregfci_report,
              term.fa_proc_year AS rsbbregfci_acyr_code,
              term.term_code AS rsbbregfci_term_code,
              'R' AS rsbbregfci_camp_code,
              'N' AS rsbbregfci_styp_code,
              dd.levl_code AS rsbbregfci_levl_code,
              COUNT(DISTINCT CASE
                    WHEN dd.apst_code <> 'W'
                         AND zsavappl_camplevl_rank = 1
                        --and dd.apdc_code like 'A%'
                         AND dd.registration_ind = 1 THEN
                     dd.pidm
                    END) AS rsbbregfci_reg,
              COUNT(DISTINCT CASE
                    WHEN dd.apst_code <> 'W'
                         AND dd.zsavappl_camplevl_rank = 1
                         AND dd.fci_ind = 1
                    --and dd.apdc_code like 'A%'
                     THEN
                     dd.pidm
                    END) AS rsbbregfci_fci,
              COUNT(DISTINCT CASE
                    WHEN dd.apst_code <> 'W'
                         AND zsavappl_camplevl_rank = 1
                         AND dd.registration_ind = 1
                         AND dd.fci_ind = 1
                    --and dd.apdc_code like 'A%'
                     THEN
                     dd.pidm
                    END) AS rsbbregfci_reg_fci,
              COUNT(DISTINCT CASE
                    WHEN dd.apst_code <> 'W'
                         AND zsavappl_camplevl_rank = 1
                         AND dd.registration_ind = 1
                         AND dd.fci_ind = 0
                    --and dd.apdc_code like 'A%'
                     THEN
                     dd.pidm
                    END) AS rsbbregfci_reg_not_fci,
              COUNT(DISTINCT CASE
                    WHEN dd.apst_code <> 'W'
                         AND zsavappl_camplevl_rank = 1
                         AND dd.registration_ind = 0
                         AND dd.fci_ind = 1
                    --and dd.apdc_code like 'A%'
                     THEN
                     dd.pidm
                    END) AS rsbbregfci_fci_not_reg,
              SUM(CASE
                  WHEN dd.apst_code <> 'W'
                       AND zsavappl_camplevl_rank = 1
                      --and dd.apdc_code like 'A%'
                       AND dd.registration_ind = 1 THEN
                   dd.total_reg_hours
                  END) AS rsbbregfci_hours,
              SUM(CASE
                  WHEN dd.apst_code <> 'W'
                       AND dd.zsavappl_camplevl_rank = 1
                       AND dd.fci_ind = 1
                  --and dd.apdc_code like 'A%'
                   THEN
                   dd.total_reg_hours
                  END) AS rsbbregfci_fci_hours
         FROM utl_d_res.mrbbmrappsdd dd
         JOIN zsaturn.szrlevl l
           ON l.szrlevl_levl_code = dd.levl_code
          AND l.szrlevl_is_stu_levl = 'Y'
          AND l.szrlevl_has_awardable_cred = 'Y'
         JOIN (SELECT term_code,
                     semester,
                     fa_proc_year
                FROM zbtm.terms_by_group_v
               WHERE start_date <= rec.report_date + 240
                 AND end_date >= rec.report_date
                 AND group_code = rec.group_code) term
           ON term.term_code = dd.term_code
        WHERE dd.report_date = (SELECT MAX(dd2.report_date)
                                  FROM utl_d_res.mrbbmrappsdd dd2
                                 WHERE dd2.term_code = dd.term_code
                                   AND dd2.report_date <= rec.report_date)
          AND dd.population = 'New'
        GROUP BY dd.camp_code,
                 dd.levl_code,
                 term.fa_proc_year,
                 term.term_code) src
ON (tgt.rsbbregfci_report_date = src.rsbbregfci_report_date AND tgt.rsbbregfci_report = src.rsbbregfci_report AND tgt.rsbbregfci_acyr_code = src.rsbbregfci_acyr_code AND tgt.rsbbregfci_term_code = src.rsbbregfci_term_code AND tgt.rsbbregfci_camp_code = src.rsbbregfci_camp_code AND tgt.rsbbregfci_styp_code = src.rsbbregfci_styp_code AND tgt.rsbbregfci_levl_code = src.rsbbregfci_levl_code)
WHEN MATCHED THEN
UPDATE
   SET tgt.rsbbregfci_activity_date = src.rsbbregfci_activity_date,
       tgt.rsbbregfci_reg           = src.rsbbregfci_reg,
       tgt.rsbbregfci_fci           = src.rsbbregfci_fci,
       tgt.rsbbregfci_reg_fci       = src.rsbbregfci_reg_fci,
       tgt.rsbbregfci_reg_not_fci   = src.rsbbregfci_reg_not_fci,
       tgt.rsbbregfci_fci_not_reg   = src.rsbbregfci_fci_not_reg,
       tgt.rsbbregfci_hours         = src.rsbbregfci_hours,
       tgt.rsbbregfci_fci_hours     = src.rsbbregfci_fci_hours
WHEN NOT MATCHED THEN
INSERT
(rsbbregfci_report_date,
 rsbbregfci_report,
 rsbbregfci_acyr_code,
 rsbbregfci_term_code,
 rsbbregfci_camp_code,
 rsbbregfci_levl_code,
 rsbbregfci_styp_code,
 rsbbregfci_reg,
 rsbbregfci_fci,
 rsbbregfci_reg_fci,
 rsbbregfci_reg_not_fci,
 rsbbregfci_fci_not_reg,
 rsbbregfci_hours,
 rsbbregfci_activity_date,
 rsbbregfci_fci_hours)
VALUES
(src.rsbbregfci_report_date,
 src.rsbbregfci_report,
 src.rsbbregfci_acyr_code,
 src.rsbbregfci_term_code,
 src.rsbbregfci_camp_code,
 src.rsbbregfci_levl_code,
 src.rsbbregfci_styp_code,
 src.rsbbregfci_reg,
 src.rsbbregfci_fci,
 src.rsbbregfci_reg_fci,
 src.rsbbregfci_reg_not_fci,
 src.rsbbregfci_fci_not_reg,
 src.rsbbregfci_hours,
 src.rsbbregfci_activity_date,
 src.rsbbregfci_fci_hours);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || rec.term_code || ' - ' || rec.report_date || ' - ' || v_report_type || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
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
VERSION    DATE        USERNAME       UPDATES
1.0        05-26-2016  odavenport2    --Initial release
2.0        06-23-2016  odavenport2    --changed to pidm-based model; changed to dimensional dates model
3.0         10-04-2016  odavenport2    --changed to aggregate model; removed dimensional dates model; created new table
4.0        11-16-2018  odavenport2     --added FCI hours column
5.0        12-23-2020  lxhatfield      --changed new res logic
5.1        09-17-2021  lxhatfield      --fixed error where res new hours was using count distinct instead of sum
---     05-17-2023  WGRIFFITH2  --Dealing with EM courses and updating code to use job_log
---     07-24-2023  WGRIFFITH2  --TKT2753928-Optimization
---     10-13-2023  WGRIFFITH2  --Fixing issues from code updates on 7/24/23
---     10-23-2023  WGRIFFITH2  --sfrstca instead of sfrstcr - TKT2798583
---     10-26-2023  WGRIFFITH2  --split into different procs due to performance issues
------------------------------------------------------------------------------------------------*/
END etl_aim_regfcisum_main_reg_res_new;

PROCEDURE etl_aim_regfcisum_main_reg_res_return(jobnumber   NUMBER,
                                                processid   VARCHAR2,
                                                processname VARCHAR2) IS
/*
Table: utl_d_aim.rsbbregfci

Primary Keys: RSBBREGFCI_REPORT_DATE, RSBBREGFCI_REPORT, RSBBREGFCI_ACYR_CODE, RSBBREGFCI_TERM_CODE, RSBBREGFCI_CAMP_CODE, RSBBREGFCI_STYP_CODE, RSBBREGFCI_LEVL_CODE

Unique index: RSBBREGFCI_REPORT_DATE, RSBBREGFCI_REPORT, RSBBREGFCI_ACYR_CODE, RSBBREGFCI_TERM_CODE, RSBBREGFCI_CAMP_CODE, RSBBREGFCI_STYP_CODE, RSBBREGFCI_LEVL_CODE

Purpose:
- Tracking reg and fci for all students

Conditions:
- Student has to be registered


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
v_report_type VARCHAR2(32) := 'main_reg';
v_proc        VARCHAR2(100) := 'etl_aim_regfcisum_main_reg_res_return';
CURSOR c_terms IS
SELECT DISTINCT t.fa_proc_year AS acyr_code,
                t.term_code,
                t.semester,
                t.group_code,
                trunc(t.start_date + dates.numb) AS report_date,
                to_date(to_char(trunc(t.start_date + dates.numb) + (4 / 24), 'MM/DD/YYYY hh24:mi:ss'), 'MM/DD/YYYY hh24:mi:ss') report_timestamp -- runs at 4am everyday
  FROM zbtm.terms_by_group_v t
  JOIN (SELECT LEVEL - 180 numb FROM dual CONNECT BY LEVEL <= 360) dates
    ON t.start_date + dates.numb <= trunc(SYSDATE)
   AND t.term_code NOT IN ('000000')
   AND t.group_code IN ('STD', 'MED')
 WHERE 1 = 1
   AND (trunc(t.start_date + dates.numb) >= trunc(SYSDATE - 3) -- running the last 3 days to catch anything we might have missed; to_date('2025-04-07','YYYY-MM-DD')
       OR trunc(t.start_date + dates.numb) = trunc(SYSDATE - 365.25))
   AND trunc(t.start_date + dates.numb) >= t.start_date - 180 -- begin tracking 90 days prior to start
   AND trunc(t.start_date + dates.numb) <= t.end_date -- end tracking on last day of term
 ORDER BY report_date DESC,
          acyr_code   ASC;
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
v_msg     := 'START - ' || rec.term_code || ' - ' || rec.report_date || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
--res return
MERGE INTO utl_d_aim.rsbbregfci tgt
USING (SELECT v_etl_date AS rsbbregfci_activity_date,
              rec.report_date AS rsbbregfci_report_date,
              v_report_type AS rsbbregfci_report,
              term.fa_proc_year AS rsbbregfci_acyr_code,
              term.term_code AS rsbbregfci_term_code,
              'R' AS rsbbregfci_camp_code,
              'R' AS rsbbregfci_styp_code,
              dd.levl_code AS rsbbregfci_levl_code,
              COUNT(DISTINCT CASE
                    WHEN dd.registration_ind = 1 THEN
                     dd.pidm
                    END) AS rsbbregfci_reg,
              COUNT(DISTINCT CASE
                    WHEN dd.fci_ind = 1 THEN
                     dd.pidm
                    END) AS rsbbregfci_fci,
              COUNT(DISTINCT CASE
                    WHEN dd.registration_ind = 1
                         AND dd.fci_ind = 1 THEN
                     dd.pidm
                    END) AS rsbbregfci_reg_fci,
              COUNT(DISTINCT CASE
                    WHEN dd.registration_ind = 1
                         AND dd.fci_ind = 0 THEN
                     dd.pidm
                    END) AS rsbbregfci_reg_not_fci,
              COUNT(DISTINCT CASE
                    WHEN dd.registration_ind = 0
                         AND dd.fci_ind = 1 THEN
                     dd.pidm
                    END) AS rsbbregfci_fci_not_reg,
              coalesce(SUM(dd.total_reg_hours), 0) AS rsbbregfci_hours,
              coalesce(SUM(CASE
                           WHEN dd.fci_ind = 1 THEN
                            dd.total_reg_hours
                           END), 0) AS rsbbregfci_fci_hours
         FROM utl_d_res.mrbbmrappsdd dd
         JOIN zsaturn.szrlevl l
           ON l.szrlevl_levl_code = dd.levl_code
          AND l.szrlevl_is_stu_levl = 'Y'
          AND l.szrlevl_has_awardable_cred = 'Y'
         JOIN (SELECT term_code,
                     semester,
                     fa_proc_year
                FROM zbtm.terms_by_group_v
               WHERE start_date <= rec.report_date + 240
                 AND end_date >= rec.report_date
                 AND group_code = rec.group_code) term
           ON term.term_code = dd.term_code
        WHERE dd.report_date = (SELECT MAX(dd2.report_date)
                                  FROM utl_d_res.mrbbmrappsdd dd2
                                 WHERE dd2.term_code = dd.term_code
                                   AND dd2.report_date <= rec.report_date)
          AND dd.population = 'Return'
        GROUP BY term.fa_proc_year,
                 term.term_code,
                 dd.levl_code) src
ON (tgt.rsbbregfci_report_date = src.rsbbregfci_report_date AND tgt.rsbbregfci_report = src.rsbbregfci_report AND tgt.rsbbregfci_acyr_code = src.rsbbregfci_acyr_code AND tgt.rsbbregfci_term_code = src.rsbbregfci_term_code AND tgt.rsbbregfci_camp_code = src.rsbbregfci_camp_code AND tgt.rsbbregfci_styp_code = src.rsbbregfci_styp_code AND tgt.rsbbregfci_levl_code = src.rsbbregfci_levl_code)
WHEN MATCHED THEN
UPDATE
   SET tgt.rsbbregfci_activity_date = src.rsbbregfci_activity_date,
       tgt.rsbbregfci_reg           = src.rsbbregfci_reg,
       tgt.rsbbregfci_fci           = src.rsbbregfci_fci,
       tgt.rsbbregfci_reg_fci       = src.rsbbregfci_reg_fci,
       tgt.rsbbregfci_reg_not_fci   = src.rsbbregfci_reg_not_fci,
       tgt.rsbbregfci_fci_not_reg   = src.rsbbregfci_fci_not_reg,
       tgt.rsbbregfci_hours         = src.rsbbregfci_hours,
       tgt.rsbbregfci_fci_hours     = src.rsbbregfci_fci_hours
WHEN NOT MATCHED THEN
INSERT
(rsbbregfci_report_date,
 rsbbregfci_report,
 rsbbregfci_acyr_code,
 rsbbregfci_term_code,
 rsbbregfci_camp_code,
 rsbbregfci_levl_code,
 rsbbregfci_styp_code,
 rsbbregfci_reg,
 rsbbregfci_fci,
 rsbbregfci_reg_fci,
 rsbbregfci_reg_not_fci,
 rsbbregfci_fci_not_reg,
 rsbbregfci_hours,
 rsbbregfci_activity_date,
 rsbbregfci_fci_hours)
VALUES
(src.rsbbregfci_report_date,
 src.rsbbregfci_report,
 src.rsbbregfci_acyr_code,
 src.rsbbregfci_term_code,
 src.rsbbregfci_camp_code,
 src.rsbbregfci_levl_code,
 src.rsbbregfci_styp_code,
 src.rsbbregfci_reg,
 src.rsbbregfci_fci,
 src.rsbbregfci_reg_fci,
 src.rsbbregfci_reg_not_fci,
 src.rsbbregfci_fci_not_reg,
 src.rsbbregfci_hours,
 src.rsbbregfci_activity_date,
 src.rsbbregfci_fci_hours);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || '000000' || ' - ' || rec.report_date || ' - ' || 'res return' || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
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
VERSION    DATE        USERNAME       UPDATES
1.0        05-26-2016  odavenport2    --Initial release
2.0        06-23-2016  odavenport2    --changed to pidm-based model; changed to dimensional dates model
3.0         10-04-2016  odavenport2    --changed to aggregate model; removed dimensional dates model; created new table
4.0        11-16-2018  odavenport2     --added FCI hours column
5.0        12-23-2020  lxhatfield      --changed new res logic
5.1        09-17-2021  lxhatfield      --fixed error where res new hours was using count distinct instead of sum
---     05-17-2023  WGRIFFITH2  --Dealing with EM courses and updating code to use job_log
---     07-24-2023  WGRIFFITH2  --TKT2753928-Optimization
---     10-13-2023  WGRIFFITH2  --Fixing issues from code updates on 7/24/23
---     10-23-2023  WGRIFFITH2  --sfrstca instead of sfrstcr - TKT2798583
---     10-26-2023  WGRIFFITH2  --split into different procs due to performance issues
------------------------------------------------------------------------------------------------*/
END etl_aim_regfcisum_main_reg_res_return;

PROCEDURE etl_aim_regfcisum_main_reg_luo(jobnumber   NUMBER,
                                         processid   VARCHAR2,
                                         processname VARCHAR2) IS
/*
Table: utl_d_aim.rsbbregfci

Primary Keys: RSBBREGFCI_REPORT_DATE, RSBBREGFCI_REPORT, RSBBREGFCI_ACYR_CODE, RSBBREGFCI_TERM_CODE, RSBBREGFCI_CAMP_CODE, RSBBREGFCI_STYP_CODE, RSBBREGFCI_LEVL_CODE

Unique index: RSBBREGFCI_REPORT_DATE, RSBBREGFCI_REPORT, RSBBREGFCI_ACYR_CODE, RSBBREGFCI_TERM_CODE, RSBBREGFCI_CAMP_CODE, RSBBREGFCI_STYP_CODE, RSBBREGFCI_LEVL_CODE

Purpose:
- Tracking reg and fci for all students

Conditions:
- Student has to be registered


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
v_report_type VARCHAR2(32) := 'main_reg';
v_proc        VARCHAR2(100) := 'etl_aim_regfcisum_main_reg_luo';
CURSOR c_terms IS
SELECT DISTINCT t.fa_proc_year AS acyr_code,
                t.term_code,
                t.semester,
                t.group_code,
                trunc(t.start_date + dates.numb) AS report_date,
                to_date(to_char(trunc(t.start_date + dates.numb) + (4 / 24), 'MM/DD/YYYY hh24:mi:ss'), 'MM/DD/YYYY hh24:mi:ss') report_timestamp -- runs at 4am everyday
  FROM zbtm.terms_by_group_v t
  JOIN (SELECT LEVEL - 180 numb FROM dual CONNECT BY LEVEL <= 360) dates
    ON t.start_date + dates.numb <= trunc(SYSDATE)
   AND t.term_code NOT IN ('000000')
   AND t.group_code IN ('STD', 'MED')
 WHERE 1 = 1
   AND (trunc(t.start_date + dates.numb) >= trunc(SYSDATE - 3) -- running the last 3 days to catch anything we might have missed; to_date('2025-04-07','YYYY-MM-DD')
       OR trunc(t.start_date + dates.numb) = trunc(SYSDATE - 365.25))
   AND trunc(t.start_date + dates.numb) >= t.start_date - 180 -- begin tracking 90 days prior to start
   AND trunc(t.start_date + dates.numb) <= t.end_date -- end tracking on last day of term
 ORDER BY report_date DESC,
          acyr_code   ASC;
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
v_msg     := 'START - ' || rec.term_code || ' - ' || rec.report_date || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- totals from morning report table....
--luo(same as main_reg_old)
MERGE INTO utl_d_aim.rsbbregfci tgt
USING (SELECT v_etl_date activity_date,
              f.rsbbregfci_report_date,
              v_report_type AS rsbbregfci_report,
              f.rsbbregfci_acyr_code,
              f.rsbbregfci_term_code,
              f.rsbbregfci_camp_code,
              f.rsbbregfci_styp_code,
              f.rsbbregfci_levl_code,
              f.rsbbregfci_reg,
              f.rsbbregfci_fci,
              f.rsbbregfci_reg_fci,
              f.rsbbregfci_reg_not_fci,
              f.rsbbregfci_fci_not_reg,
              f.rsbbregfci_hours,
              f.rsbbregfci_fci_hours,
              f.rsbbregfci_activity_date
         FROM utl_d_aim.rsbbregfci f
         JOIN zsaturn.szrlevl l
           ON l.szrlevl_levl_code = rsbbregfci_levl_code
          AND l.szrlevl_is_stu_levl = 'Y'
          AND l.szrlevl_has_awardable_cred = 'Y'
        CROSS JOIN (SELECT term_code,
                          semester,
                          fa_proc_year
                     FROM zbtm.terms_by_group_v
                    WHERE start_date <= rec.report_date + 240
                      AND end_date >= rec.report_date
                      AND group_code = rec.group_code) tbg
        WHERE f.rsbbregfci_report IN (v_report_type||'_old')
          AND f.rsbbregfci_camp_code != 'R'
          AND f.rsbbregfci_term_code = tbg.term_code
          AND f.rsbbregfci_report_date = rec.report_date) src
ON (tgt.rsbbregfci_report_date = src.rsbbregfci_report_date AND tgt.rsbbregfci_report = src.rsbbregfci_report AND tgt.rsbbregfci_acyr_code = src.rsbbregfci_acyr_code AND tgt.rsbbregfci_term_code = src.rsbbregfci_term_code AND tgt.rsbbregfci_camp_code = src.rsbbregfci_camp_code AND tgt.rsbbregfci_styp_code = src.rsbbregfci_styp_code AND tgt.rsbbregfci_levl_code = src.rsbbregfci_levl_code)
WHEN MATCHED THEN
UPDATE
   SET tgt.rsbbregfci_activity_date = src.rsbbregfci_activity_date,
       tgt.rsbbregfci_reg           = src.rsbbregfci_reg,
       tgt.rsbbregfci_fci           = src.rsbbregfci_fci,
       tgt.rsbbregfci_reg_fci       = src.rsbbregfci_reg_fci,
       tgt.rsbbregfci_reg_not_fci   = src.rsbbregfci_reg_not_fci,
       tgt.rsbbregfci_fci_not_reg   = src.rsbbregfci_fci_not_reg,
       tgt.rsbbregfci_hours         = src.rsbbregfci_hours,
       tgt.rsbbregfci_fci_hours     = src.rsbbregfci_fci_hours
WHEN NOT MATCHED THEN
INSERT
(rsbbregfci_report_date,
 rsbbregfci_report,
 rsbbregfci_acyr_code,
 rsbbregfci_term_code,
 rsbbregfci_camp_code,
 rsbbregfci_levl_code,
 rsbbregfci_styp_code,
 rsbbregfci_reg,
 rsbbregfci_fci,
 rsbbregfci_reg_fci,
 rsbbregfci_reg_not_fci,
 rsbbregfci_fci_not_reg,
 rsbbregfci_hours,
 rsbbregfci_activity_date,
 rsbbregfci_fci_hours)
VALUES
(src.rsbbregfci_report_date,
 src.rsbbregfci_report,
 src.rsbbregfci_acyr_code,
 src.rsbbregfci_term_code,
 src.rsbbregfci_camp_code,
 src.rsbbregfci_levl_code,
 src.rsbbregfci_styp_code,
 src.rsbbregfci_reg,
 src.rsbbregfci_fci,
 src.rsbbregfci_reg_fci,
 src.rsbbregfci_reg_not_fci,
 src.rsbbregfci_fci_not_reg,
 src.rsbbregfci_hours,
 src.rsbbregfci_activity_date,
 src.rsbbregfci_fci_hours);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || rec.term_code || ' - ' || rec.report_date || ' - ' || v_report_type || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
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
VERSION    DATE        USERNAME       UPDATES
1.0        05-26-2016  odavenport2    --Initial release
2.0        06-23-2016  odavenport2    --changed to pidm-based model; changed to dimensional dates model
3.0         10-04-2016  odavenport2    --changed to aggregate model; removed dimensional dates model; created new table
4.0        11-16-2018  odavenport2     --added FCI hours column
5.0        12-23-2020  lxhatfield      --changed new res logic
5.1        09-17-2021  lxhatfield      --fixed error where res new hours was using count distinct instead of sum
---     05-17-2023  WGRIFFITH2  --Dealing with EM courses and updating code to use job_log
---     07-24-2023  WGRIFFITH2  --TKT2753928-Optimization
---     10-13-2023  WGRIFFITH2  --Fixing issues from code updates on 7/24/23
---     10-23-2023  WGRIFFITH2  --sfrstca instead of sfrstcr - TKT2798583
---     10-26-2023  WGRIFFITH2  --split into different procs due to performance issues
------------------------------------------------------------------------------------------------*/
END etl_aim_regfcisum_main_reg_luo;

PROCEDURE etl_aim_regfcisum_new_res_old(jobnumber   NUMBER,
                                        processid   VARCHAR2,
                                        processname VARCHAR2) IS
/*
Table: utl_d_aim.rsbbregfci

Primary Keys: RSBBREGFCI_REPORT_DATE, RSBBREGFCI_REPORT, RSBBREGFCI_ACYR_CODE, RSBBREGFCI_TERM_CODE, RSBBREGFCI_CAMP_CODE, RSBBREGFCI_STYP_CODE, RSBBREGFCI_LEVL_CODE

Unique index: RSBBREGFCI_REPORT_DATE, RSBBREGFCI_REPORT, RSBBREGFCI_ACYR_CODE, RSBBREGFCI_TERM_CODE, RSBBREGFCI_CAMP_CODE, RSBBREGFCI_STYP_CODE, RSBBREGFCI_LEVL_CODE

Purpose:
- Tracking reg and fci for all students

Conditions:
- Student has to be registered


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
v_report_type VARCHAR2(32) := 'new_res_old';
v_proc        VARCHAR2(100) := 'etl_aim_regfcisum_new_res_old';
CURSOR c_terms IS
SELECT DISTINCT t.fa_proc_year AS acyr_code,
                t.term_code,
                t.semester,
                t.group_code,
                trunc(t.start_date + dates.numb) AS report_date,
                to_date(to_char(trunc(t.start_date + dates.numb) + (4 / 24), 'MM/DD/YYYY hh24:mi:ss'), 'MM/DD/YYYY hh24:mi:ss') report_timestamp -- runs at 4am everyday
  FROM zbtm.terms_by_group_v t
  JOIN (SELECT LEVEL - 180 numb FROM dual CONNECT BY LEVEL <= 360) dates
    ON t.start_date + dates.numb <= trunc(SYSDATE)
   AND t.term_code NOT IN ('000000')
   AND t.group_code IN ('STD', 'MED')
 WHERE 1 = 1
   AND (trunc(t.start_date + dates.numb) >= trunc(SYSDATE - 3) -- running the last 3 days to catch anything we might have missed; to_date('2025-04-07','YYYY-MM-DD')
       OR trunc(t.start_date + dates.numb) = trunc(SYSDATE - 365.25))
   AND trunc(t.start_date + dates.numb) >= t.start_date - 180 -- begin tracking 90 days prior to start
   AND trunc(t.start_date + dates.numb) <= t.end_date -- end tracking on last day of term
 ORDER BY report_date DESC,
          acyr_code   ASC;
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
v_msg     := 'START - ' || rec.term_code || ' - ' || rec.report_date || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- truncate table  utl_d_aim.rsbbregfci_gtt;
INSERT INTO utl_d_aim.rsbbregfci_gtt
(rsbbregfci_pidm,
 rsbbregfci_acyr_code,
 rsbbregfci_term_code,
 rsbbregfci_camp_code,
 rsbbregfci_levl_code,
 rsbbregfci_styp_code,
 rsbbregfci_reg,
 rsbbregfci_fci,
 rsbbregfci_hours,
 rsbbregfci_fci_hours,
 rsbbregfci_report_date)
SELECT spriden_pidm,
       rec.acyr_code,
       rec.term_code,
       sgbstdn_camp_code,
       sgbstdn_levl_code,
       CASE
       WHEN sgbstdn_camp_code = 'R'
            AND appl.zsavappl_pidm IS NOT NULL THEN
        'N' -- RES student with App
       WHEN sgbstdn_camp_code = 'D'
            AND enrl_last_yr.pidm IS NULL THEN
        'N' -- LUO student not reg last year
       ELSE
        'R'
       END styp_code,
       CASE
       WHEN reg.pidm IS NOT NULL THEN
        1
       END AS reg_ind,
       CASE
       WHEN fci.pidm IS NOT NULL THEN
        1
       END fci_ind,
       reg.hours,
       CASE
       WHEN fci.pidm IS NOT NULL THEN
        reg.hours
       END fci_hours,
       rec.report_date
  FROM spriden
  JOIN sgbstdn
    ON sgbstdn_pidm = spriden_pidm
   AND sgbstdn_camp_code IS NOT NULL
   AND sgbstdn_program_1 IS NOT NULL
   AND spriden_change_ind IS NULL
   AND sgbstdn_term_code_eff = (SELECT MAX(d.sgbstdn_term_code_eff)
                                  FROM sgbstdn d
                                 WHERE d.sgbstdn_pidm = sgbstdn.sgbstdn_pidm
                                   AND d.sgbstdn_term_code_eff <= rec.term_code)
  JOIN zsaturn.szrlevl l
    ON l.szrlevl_levl_code = sgbstdn_levl_code
   AND l.szrlevl_is_stu_levl = 'Y'
   AND l.szrlevl_has_awardable_cred = 'Y'
  LEFT JOIN zexec.zsavappl appl
    ON appl.zsavappl_pidm = spriden_pidm
   AND appl.zsavappl_levl_code = sgbstdn_levl_code
   AND appl.zsavappl_camp_code = sgbstdn_camp_code
   AND appl.zsavappl_camp_code = 'R'
   AND appl.zsavappl_apdc_code IN (SELECT stvapdc_code FROM stvapdc WHERE stvapdc_inst_acc_ind = 'Y')
   AND appl.zsavappl_apst_code <> 'W'
   AND appl.zsavappl_term_code IN (rec.term_code, CASE WHEN rec.semester = 'FAL' THEN rec.term_code - 10 END)
  LEFT JOIN (SELECT DISTINCT enrl.pidm FROM utl_d_aim.szrenrl enrl WHERE enrl.acad_year = rec.acyr_code - 101) enrl_last_yr
    ON enrl_last_yr.pidm = spriden_pidm
  LEFT JOIN (SELECT sfrstca_pidm AS pidm,
                    SUM(sfrstca_credit_hr) AS hours
               FROM saturn.sfrstca
               JOIN saturn.stvrsts
                 ON stvrsts_code = sfrstca_rsts_code
                AND stvrsts_incl_sect_enrl = 'Y'
                AND sfrstca.sfrstca_seq_number = (SELECT MAX(d.sfrstca_seq_number)
                                                    FROM sfrstca d
                                                   WHERE d.sfrstca_pidm = sfrstca.sfrstca_pidm
                                                     AND d.sfrstca_term_code = sfrstca.sfrstca_term_code
                                                     AND d.sfrstca_crn = sfrstca.sfrstca_crn
                                                     AND d.sfrstca_source_cde = 'BASE'
                                                     AND d.sfrstca_rsts_date <= rec.report_timestamp -- runs at 4am everyday
                                                  )
               JOIN zsaturn.szrlevl l
                 ON l.szrlevl_levl_code = sfrstca_levl_code
                AND l.szrlevl_is_stu_levl = 'Y'
                AND l.szrlevl_has_awardable_cred = 'Y'
               JOIN ssbsect
                 ON ssbsect_term_code = sfrstca_term_code
                AND ssbsect_crn = sfrstca_crn
                AND ssbsect_subj_code NOT IN ('CSER', 'FRSM', 'GRST', 'NEWS', 'NSSR')
              WHERE 1 = 1
                AND sfrstca_term_code = rec.term_code
                AND sfrstca_rsts_date <= rec.report_timestamp -- runs at 4am everyday
                AND sfrstca_source_cde = 'BASE'
              GROUP BY sfrstca_pidm) reg
    ON reg.pidm = spriden_pidm
  LEFT JOIN (SELECT DISTINCT fci.zfrfcis_pidm AS pidm
               FROM zfincheckin.zfrfcis fci
              WHERE fci.zfrfcis_term = rec.term_code
                AND fci.zfrfcis_withdrawn IS NULL) fci
    ON fci.pidm = spriden_pidm
 WHERE 1 = 1
   AND (reg.pidm IS NOT NULL OR fci.pidm IS NOT NULL)
   AND NOT EXISTS (SELECT 'X'
          FROM utl_d_aim.rsbbregfci_gtt gtt
         WHERE gtt.rsbbregfci_term_code = rec.term_code
           AND gtt.rsbbregfci_pidm = reg.pidm
           AND gtt.rsbbregfci_report_date = rec.report_date);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || rec.term_code || ' - ' || rec.report_date || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
MERGE INTO utl_d_aim.rsbbregfci tgt
USING (SELECT v_etl_date AS rsbbregfci_activity_date,
              rec.report_date AS rsbbregfci_report_date,
              v_report_type AS rsbbregfci_report,
              rec.acyr_code AS rsbbregfci_acyr_code,
              rec.term_code AS rsbbregfci_term_code,
              sgbstdn_camp_code AS rsbbregfci_camp_code,
              zsavappl_styp_code AS rsbbregfci_styp_code,
              CASE
              WHEN sgbstdn_levl_code IN ('JD', 'GR', 'DR', 'MD') THEN
               'GR'
              ELSE
               'UG'
              END AS rsbbregfci_levl_code,
              COUNT(DISTINCT gtt.rsbbregfci_pidm) AS rsbbregfci_reg,
              NULL AS rsbbregfci_fci,
              NULL AS rsbbregfci_reg_fci,
              NULL AS rsbbregfci_reg_not_fci,
              NULL AS rsbbregfci_fci_not_reg,
              NULL AS rsbbregfci_hours,
              NULL AS rsbbregfci_fci_hours
         FROM utl_d_aim.rsbbregfci_gtt gtt
         JOIN zsaturn.szrlevl l
           ON l.szrlevl_levl_code = rsbbregfci_levl_code
          AND l.szrlevl_is_stu_levl = 'Y'
          AND l.szrlevl_has_awardable_cred = 'Y'
          AND gtt.rsbbregfci_term_code = rec.term_code
          AND coalesce(gtt.rsbbregfci_reg, 0) > 0 -- has reg
         JOIN sgbstdn
           ON sgbstdn_pidm = rsbbregfci_pidm
          AND sgbstdn_camp_code IS NOT NULL
          AND sgbstdn_program_1 IS NOT NULL
          AND sgbstdn_camp_code = 'R'
          AND sgbstdn_term_code_eff = (SELECT MAX(d.sgbstdn_term_code_eff)
                                         FROM sgbstdn d
                                        WHERE d.sgbstdn_pidm = sgbstdn.sgbstdn_pidm
                                          AND d.sgbstdn_term_code_eff <= rec.term_code)
         JOIN zexec.zsavappl
           ON zsavappl_pidm = rsbbregfci_pidm
          AND zsavappl_camp_code = sgbstdn_camp_code
          AND zsavappl_levl_code = sgbstdn_levl_code
          AND zsavappl_term_code IN (rec.term_code, to_char(rec.term_code - 10))
          AND zsavappl_apst_code <> 'W'
          AND zsavappl_apdc_code IN (SELECT stvapdc_code
                                       FROM stvapdc
                                      WHERE stvapdc_inst_acc_ind = 'Y'
                                         OR stvapdc_code = 'EI')
        GROUP BY v_etl_date,
                 rec.report_date,
                 rec.acyr_code,
                 rec.term_code,
                 sgbstdn_camp_code,
                 zsavappl_styp_code,
                 CASE
                 WHEN sgbstdn_levl_code IN ('JD', 'GR', 'DR', 'MD') THEN
                  'GR'
                 ELSE
                  'UG'
                 END) src
ON (tgt.rsbbregfci_report_date = src.rsbbregfci_report_date AND tgt.rsbbregfci_report = src.rsbbregfci_report AND tgt.rsbbregfci_acyr_code = src.rsbbregfci_acyr_code AND tgt.rsbbregfci_term_code = src.rsbbregfci_term_code AND tgt.rsbbregfci_camp_code = src.rsbbregfci_camp_code AND tgt.rsbbregfci_styp_code = src.rsbbregfci_styp_code AND tgt.rsbbregfci_levl_code = src.rsbbregfci_levl_code)
WHEN MATCHED THEN
UPDATE
   SET tgt.rsbbregfci_activity_date = src.rsbbregfci_activity_date,
       tgt.rsbbregfci_reg           = src.rsbbregfci_reg,
       tgt.rsbbregfci_fci           = src.rsbbregfci_fci,
       tgt.rsbbregfci_reg_fci       = src.rsbbregfci_reg_fci,
       tgt.rsbbregfci_reg_not_fci   = src.rsbbregfci_reg_not_fci,
       tgt.rsbbregfci_fci_not_reg   = src.rsbbregfci_fci_not_reg,
       tgt.rsbbregfci_hours         = src.rsbbregfci_hours,
       tgt.rsbbregfci_fci_hours     = src.rsbbregfci_fci_hours
WHEN NOT MATCHED THEN
INSERT
(rsbbregfci_report_date,
 rsbbregfci_report,
 rsbbregfci_acyr_code,
 rsbbregfci_term_code,
 rsbbregfci_camp_code,
 rsbbregfci_levl_code,
 rsbbregfci_styp_code,
 rsbbregfci_reg,
 rsbbregfci_fci,
 rsbbregfci_reg_fci,
 rsbbregfci_reg_not_fci,
 rsbbregfci_fci_not_reg,
 rsbbregfci_hours,
 rsbbregfci_activity_date,
 rsbbregfci_fci_hours)
VALUES
(src.rsbbregfci_report_date,
 src.rsbbregfci_report,
 src.rsbbregfci_acyr_code,
 src.rsbbregfci_term_code,
 src.rsbbregfci_camp_code,
 src.rsbbregfci_levl_code,
 src.rsbbregfci_styp_code,
 src.rsbbregfci_reg,
 src.rsbbregfci_fci,
 src.rsbbregfci_reg_fci,
 src.rsbbregfci_reg_not_fci,
 src.rsbbregfci_fci_not_reg,
 src.rsbbregfci_hours,
 src.rsbbregfci_activity_date,
 src.rsbbregfci_fci_hours);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || rec.term_code || ' - ' || rec.report_date || ' - ' || v_report_type || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
utl_d_aim.truncate_table(v_table_name => 'rsbbregfci_gtt'); -- REMOVE RECORDS AFTER EVERY LOOP
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
VERSION    DATE        USERNAME       UPDATES
1.0        05-26-2016  odavenport2    --Initial release
2.0        06-23-2016  odavenport2    --changed to pidm-based model; changed to dimensional dates model
3.0         10-04-2016  odavenport2    --changed to aggregate model; removed dimensional dates model; created new table
4.0        11-16-2018  odavenport2     --added FCI hours column
5.0        12-23-2020  lxhatfield      --changed new res logic
5.1        09-17-2021  lxhatfield      --fixed error where res new hours was using count distinct instead of sum
---     05-17-2023  WGRIFFITH2  --Dealing with EM courses and updating code to use job_log
---     07-24-2023  WGRIFFITH2  --TKT2753928-Optimization
---     10-13-2023  WGRIFFITH2  --Fixing issues from code updates on 7/24/23
---     10-23-2023  WGRIFFITH2  --sfrstca instead of sfrstcr - TKT2798583
---     10-26-2023  WGRIFFITH2  --split into different procs due to performance issues
------------------------------------------------------------------------------------------------*/
END etl_aim_regfcisum_new_res_old;

PROCEDURE etl_aim_regfcisum_intl_reg_old(jobnumber   NUMBER,
                                         processid   VARCHAR2,
                                         processname VARCHAR2) IS
/*
Table: utl_d_aim.rsbbregfci

Primary Keys: RSBBREGFCI_REPORT_DATE, RSBBREGFCI_REPORT, RSBBREGFCI_ACYR_CODE, RSBBREGFCI_TERM_CODE, RSBBREGFCI_CAMP_CODE, RSBBREGFCI_STYP_CODE, RSBBREGFCI_LEVL_CODE

Unique index: RSBBREGFCI_REPORT_DATE, RSBBREGFCI_REPORT, RSBBREGFCI_ACYR_CODE, RSBBREGFCI_TERM_CODE, RSBBREGFCI_CAMP_CODE, RSBBREGFCI_STYP_CODE, RSBBREGFCI_LEVL_CODE

Purpose:
- Tracking reg and fci for all students

Conditions:
- Student has to be registered


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
v_report_type VARCHAR2(32) := 'intl_reg_old';
v_proc        VARCHAR2(100) := 'etl_aim_regfcisum_intl_reg_old';
CURSOR c_terms IS
SELECT DISTINCT t.fa_proc_year AS acyr_code,
                t.term_code,
                t.semester,
                t.group_code,
                trunc(t.start_date + dates.numb) AS report_date,
                to_date(to_char(trunc(t.start_date + dates.numb) + (4 / 24), 'MM/DD/YYYY hh24:mi:ss'), 'MM/DD/YYYY hh24:mi:ss') report_timestamp -- runs at 4am everyday
  FROM zbtm.terms_by_group_v t
  JOIN (SELECT LEVEL - 180 numb FROM dual CONNECT BY LEVEL <= 360) dates
    ON t.start_date + dates.numb <= trunc(SYSDATE)
   AND t.term_code NOT IN ('000000')
   AND t.group_code IN ('STD', 'MED')
 WHERE 1 = 1
   AND (trunc(t.start_date + dates.numb) >= trunc(SYSDATE - 3) -- running the last 3 days to catch anything we might have missed; to_date('2025-04-07','YYYY-MM-DD')
       OR trunc(t.start_date + dates.numb) = trunc(SYSDATE - 365.25))
   AND trunc(t.start_date + dates.numb) >= t.start_date - 180 -- begin tracking 90 days prior to start
   AND trunc(t.start_date + dates.numb) <= t.end_date -- end tracking on last day of term
 ORDER BY report_date DESC,
          acyr_code   ASC;
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
v_msg     := 'START - ' || rec.term_code || ' - ' || rec.report_date || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- truncate table  utl_d_aim.rsbbregfci_gtt;
INSERT INTO utl_d_aim.rsbbregfci_gtt
(rsbbregfci_pidm,
 rsbbregfci_acyr_code,
 rsbbregfci_term_code,
 rsbbregfci_camp_code,
 rsbbregfci_levl_code,
 rsbbregfci_styp_code,
 rsbbregfci_reg,
 rsbbregfci_fci,
 rsbbregfci_hours,
 rsbbregfci_fci_hours,
 rsbbregfci_report_date)
SELECT spriden_pidm,
       rec.acyr_code,
       rec.term_code,
       sgbstdn_camp_code,
       sgbstdn_levl_code,
       CASE
       WHEN sgbstdn_camp_code = 'R'
            AND appl.zsavappl_pidm IS NOT NULL THEN
        'N' -- RES student with App
       WHEN sgbstdn_camp_code = 'D'
            AND enrl_last_yr.pidm IS NULL THEN
        'N' -- LUO student not reg last year
       ELSE
        'R'
       END styp_code,
       CASE
       WHEN reg.pidm IS NOT NULL THEN
        1
       END AS reg_ind,
       CASE
       WHEN fci.pidm IS NOT NULL THEN
        1
       END fci_ind,
       reg.hours,
       CASE
       WHEN fci.pidm IS NOT NULL THEN
        reg.hours
       END fci_hours,
       rec.report_date
  FROM spriden
  JOIN sgbstdn
    ON sgbstdn_pidm = spriden_pidm
   AND sgbstdn_camp_code IS NOT NULL
   AND sgbstdn_program_1 IS NOT NULL
   AND spriden_change_ind IS NULL
   AND sgbstdn_term_code_eff = (SELECT MAX(d.sgbstdn_term_code_eff)
                                  FROM sgbstdn d
                                 WHERE d.sgbstdn_pidm = sgbstdn.sgbstdn_pidm
                                   AND d.sgbstdn_term_code_eff <= rec.term_code)
  JOIN zsaturn.szrlevl l
    ON l.szrlevl_levl_code = sgbstdn_levl_code
   AND l.szrlevl_is_stu_levl = 'Y'
   AND l.szrlevl_has_awardable_cred = 'Y'
  LEFT JOIN zexec.zsavappl appl
    ON appl.zsavappl_pidm = spriden_pidm
   AND appl.zsavappl_levl_code = sgbstdn_levl_code
   AND appl.zsavappl_camp_code = sgbstdn_camp_code
   AND appl.zsavappl_camp_code = 'R'
   AND appl.zsavappl_apdc_code IN (SELECT stvapdc_code FROM stvapdc WHERE stvapdc_inst_acc_ind = 'Y')
   AND appl.zsavappl_apst_code <> 'W'
   AND appl.zsavappl_term_code IN (rec.term_code, CASE WHEN rec.semester = 'FAL' THEN rec.term_code - 10 END)
  LEFT JOIN (SELECT DISTINCT enrl.pidm FROM utl_d_aim.szrenrl enrl WHERE enrl.acad_year = rec.acyr_code - 101) enrl_last_yr
    ON enrl_last_yr.pidm = spriden_pidm
  LEFT JOIN (SELECT sfrstca_pidm AS pidm,
                    SUM(sfrstca_credit_hr) AS hours
               FROM saturn.sfrstca
               JOIN saturn.stvrsts
                 ON stvrsts_code = sfrstca_rsts_code
                AND stvrsts_incl_sect_enrl = 'Y'
                AND sfrstca.sfrstca_seq_number = (SELECT MAX(d.sfrstca_seq_number)
                                                    FROM sfrstca d
                                                   WHERE d.sfrstca_pidm = sfrstca.sfrstca_pidm
                                                     AND d.sfrstca_term_code = sfrstca.sfrstca_term_code
                                                     AND d.sfrstca_crn = sfrstca.sfrstca_crn
                                                     AND d.sfrstca_source_cde = 'BASE'
                                                     AND d.sfrstca_rsts_date <= rec.report_timestamp -- runs at 4am everyday
                                                  )
               JOIN zsaturn.szrlevl l
                 ON l.szrlevl_levl_code = sfrstca_levl_code
                AND l.szrlevl_is_stu_levl = 'Y'
                AND l.szrlevl_has_awardable_cred = 'Y'
               JOIN ssbsect
                 ON ssbsect_term_code = sfrstca_term_code
                AND ssbsect_crn = sfrstca_crn
                AND ssbsect_subj_code NOT IN ('CSER', 'FRSM', 'GRST', 'NEWS', 'NSSR')
              WHERE 1 = 1
                AND sfrstca_term_code = rec.term_code
                AND sfrstca_rsts_date <= rec.report_timestamp -- runs at 4am everyday
                AND sfrstca_source_cde = 'BASE'
              GROUP BY sfrstca_pidm) reg
    ON reg.pidm = spriden_pidm
  LEFT JOIN (SELECT DISTINCT fci.zfrfcis_pidm AS pidm
               FROM zfincheckin.zfrfcis fci
              WHERE fci.zfrfcis_term = rec.term_code
                AND fci.zfrfcis_withdrawn IS NULL) fci
    ON fci.pidm = spriden_pidm
 WHERE 1 = 1
   AND (reg.pidm IS NOT NULL OR fci.pidm IS NOT NULL)
   AND NOT EXISTS (SELECT 'X'
          FROM utl_d_aim.rsbbregfci_gtt gtt
         WHERE gtt.rsbbregfci_term_code = rec.term_code
           AND gtt.rsbbregfci_pidm = reg.pidm
           AND gtt.rsbbregfci_report_date = rec.report_date);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || rec.term_code || ' - ' || rec.report_date || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
MERGE INTO utl_d_aim.rsbbregfci tgt
USING (SELECT v_etl_date rsbbregfci_activity_date,
              rec.report_date rsbbregfci_report_date,
              v_report_type AS rsbbregfci_report,
              rsbbregfci_acyr_code,
              rsbbregfci_term_code,
              rsbbregfci_camp_code,
              rsbbregfci_levl_code,
              rsbbregfci_styp_code,
              COUNT(DISTINCT CASE
                    WHEN rsbbregfci_reg IS NOT NULL THEN
                     rsbbregfci_pidm
                    END) rsbbregfci_reg,
              COUNT(DISTINCT CASE
                    WHEN rsbbregfci_fci IS NOT NULL THEN
                     rsbbregfci_pidm
                    END) rsbbregfci_fci,
              COUNT(DISTINCT CASE
                    WHEN rsbbregfci_reg IS NOT NULL
                         AND rsbbregfci_fci IS NOT NULL THEN
                     rsbbregfci_pidm
                    END) rsbbregfci_reg_fci,
              COUNT(DISTINCT CASE
                    WHEN rsbbregfci_reg IS NOT NULL
                         AND wd_ind IS NULL
                         AND rsbbregfci_fci IS NULL THEN
                     rsbbregfci_pidm
                    END) rsbbregfci_reg_not_fci,
              COUNT(DISTINCT CASE
                    WHEN rsbbregfci_reg IS NULL
                         AND rsbbregfci_fci IS NOT NULL
                         AND winter_ind IS NOT NULL THEN
                     NULL
                    WHEN rsbbregfci_reg IS NULL
                         AND rsbbregfci_fci IS NOT NULL THEN
                     rsbbregfci_pidm
                    END) rsbbregfci_fci_not_reg,
              coalesce(SUM(rsbbregfci_hours), 0) rsbbregfci_hours,
              coalesce(SUM(CASE
                           WHEN rsbbregfci_fci IS NOT NULL THEN
                            rsbbregfci_hours
                           END), 0) rsbbregfci_fci_hours
         FROM (SELECT rsbbregfci_pidm,
                      rsbbregfci_acyr_code,
                      rsbbregfci_term_code,
                      rsbbregfci_camp_code,
                      rsbbregfci_levl_code,
                      rsbbregfci_styp_code,
                      rsbbregfci_reg,
                      rsbbregfci_fci,
                      rsbbregfci_hours,
                      rsbbregfci_fci_hours,
                      CASE
                      WHEN EXISTS (SELECT 'X'
                              FROM sfrstcr
                              JOIN utl_d_aim.rsbbregfci_gtt gtt
                                ON gtt.rsbbregfci_pidm = sfrstcr_pidm
                               AND gtt.rsbbregfci_term_code = rec.term_code
                              JOIN stvrsts
                                ON stvrsts_code = sfrstcr_rsts_code
                               AND stvrsts_incl_sect_enrl = 'Y'
                               AND sfrstcr_term_code = CASE
                                   WHEN rec.semester = 'SPR' THEN
                                    rec.term_code - 10
                                   END
                              JOIN zsaturn.szrlevl l
                                ON l.szrlevl_levl_code = sfrstcr_levl_code
                               AND l.szrlevl_is_stu_levl = 'Y'
                               AND l.szrlevl_has_awardable_cred = 'Y'
                              JOIN ssbsect
                                ON ssbsect_term_code = sfrstcr_term_code
                               AND ssbsect_crn = sfrstcr.sfrstcr_crn
                               AND ssbsect_subj_code NOT IN ('CSER', 'FRSM', 'GRST', 'NEWS', 'NSSR')
                             WHERE sfrstcr_pidm = gtt.rsbbregfci_pidm) THEN
                       1
                      END winter_ind,
                      CASE
                      WHEN EXISTS (SELECT 'X'
                              FROM sfbetrm
                              JOIN utl_d_aim.rsbbregfci_gtt gtt
                                ON gtt.rsbbregfci_pidm = sfbetrm_pidm
                               AND gtt.rsbbregfci_term_code = rec.term_code
                             WHERE sfbetrm_term_code = rec.term_code
                               AND sfbetrm_ests_code LIKE 'W%'
                               AND sfbetrm_pidm = gtt.rsbbregfci_pidm) THEN
                       1
                      END wd_ind
                 FROM utl_d_aim.rsbbregfci_gtt gtt
                WHERE 1 = 1
                  AND gtt.rsbbregfci_term_code = rec.term_code
                  AND EXISTS (SELECT 'X'
                         FROM spbpers
                        WHERE spbpers_citz_code = 'NI'
                          AND spbpers_pidm = gtt.rsbbregfci_pidm))
        GROUP BY rsbbregfci_acyr_code,
                 rsbbregfci_term_code,
                 rsbbregfci_camp_code,
                 rsbbregfci_styp_code,
                 rsbbregfci_levl_code) src
ON (tgt.rsbbregfci_report_date = src.rsbbregfci_report_date AND tgt.rsbbregfci_report = src.rsbbregfci_report AND tgt.rsbbregfci_acyr_code = src.rsbbregfci_acyr_code AND tgt.rsbbregfci_term_code = src.rsbbregfci_term_code AND tgt.rsbbregfci_camp_code = src.rsbbregfci_camp_code AND tgt.rsbbregfci_styp_code = src.rsbbregfci_styp_code AND tgt.rsbbregfci_levl_code = src.rsbbregfci_levl_code)
WHEN MATCHED THEN
UPDATE
   SET tgt.rsbbregfci_activity_date = src.rsbbregfci_activity_date,
       tgt.rsbbregfci_reg           = src.rsbbregfci_reg,
       tgt.rsbbregfci_fci           = src.rsbbregfci_fci,
       tgt.rsbbregfci_reg_fci       = src.rsbbregfci_reg_fci,
       tgt.rsbbregfci_reg_not_fci   = src.rsbbregfci_reg_not_fci,
       tgt.rsbbregfci_fci_not_reg   = src.rsbbregfci_fci_not_reg,
       tgt.rsbbregfci_hours         = src.rsbbregfci_hours,
       tgt.rsbbregfci_fci_hours     = src.rsbbregfci_fci_hours
WHEN NOT MATCHED THEN
INSERT
(rsbbregfci_report_date,
 rsbbregfci_report,
 rsbbregfci_acyr_code,
 rsbbregfci_term_code,
 rsbbregfci_camp_code,
 rsbbregfci_levl_code,
 rsbbregfci_styp_code,
 rsbbregfci_reg,
 rsbbregfci_fci,
 rsbbregfci_reg_fci,
 rsbbregfci_reg_not_fci,
 rsbbregfci_fci_not_reg,
 rsbbregfci_hours,
 rsbbregfci_activity_date,
 rsbbregfci_fci_hours)
VALUES
(src.rsbbregfci_report_date,
 src.rsbbregfci_report,
 src.rsbbregfci_acyr_code,
 src.rsbbregfci_term_code,
 src.rsbbregfci_camp_code,
 src.rsbbregfci_levl_code,
 src.rsbbregfci_styp_code,
 src.rsbbregfci_reg,
 src.rsbbregfci_fci,
 src.rsbbregfci_reg_fci,
 src.rsbbregfci_reg_not_fci,
 src.rsbbregfci_fci_not_reg,
 src.rsbbregfci_hours,
 src.rsbbregfci_activity_date,
 src.rsbbregfci_fci_hours);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || rec.term_code || ' - ' || rec.report_date || ' - ' || v_report_type || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
utl_d_aim.truncate_table(v_table_name => 'rsbbregfci_gtt'); -- REMOVE RECORDS AFTER EVERY LOOP
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
VERSION    DATE        USERNAME       UPDATES
1.0        05-26-2016  odavenport2    --Initial release
2.0        06-23-2016  odavenport2    --changed to pidm-based model; changed to dimensional dates model
3.0         10-04-2016  odavenport2    --changed to aggregate model; removed dimensional dates model; created new table
4.0        11-16-2018  odavenport2     --added FCI hours column
5.0        12-23-2020  lxhatfield      --changed new res logic
5.1        09-17-2021  lxhatfield      --fixed error where res new hours was using count distinct instead of sum
---     05-17-2023  WGRIFFITH2  --Dealing with EM courses and updating code to use job_log
---     07-24-2023  WGRIFFITH2  --TKT2753928-Optimization
---     10-13-2023  WGRIFFITH2  --Fixing issues from code updates on 7/24/23
---     10-23-2023  WGRIFFITH2  --sfrstca instead of sfrstcr - TKT2798583
---     10-26-2023  WGRIFFITH2  --split into different procs due to performance issues
------------------------------------------------------------------------------------------------*/
END etl_aim_regfcisum_intl_reg_old;

PROCEDURE etl_aim_regfcisum_main_reg_old(jobnumber   NUMBER,
                                         processid   VARCHAR2,
                                         processname VARCHAR2) IS
/*
Table: utl_d_aim.rsbbregfci

Primary Keys: RSBBREGFCI_REPORT_DATE, RSBBREGFCI_REPORT, RSBBREGFCI_ACYR_CODE, RSBBREGFCI_TERM_CODE, RSBBREGFCI_CAMP_CODE, RSBBREGFCI_STYP_CODE, RSBBREGFCI_LEVL_CODE

Unique index: RSBBREGFCI_REPORT_DATE, RSBBREGFCI_REPORT, RSBBREGFCI_ACYR_CODE, RSBBREGFCI_TERM_CODE, RSBBREGFCI_CAMP_CODE, RSBBREGFCI_STYP_CODE, RSBBREGFCI_LEVL_CODE

Purpose:
- Tracking reg and fci for all students

Conditions:
- Student has to be registered


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
v_report_type VARCHAR2(32) := 'main_reg_old';
v_proc        VARCHAR2(100) := 'etl_aim_regfcisum_main_reg_old';
CURSOR c_terms IS
SELECT DISTINCT t.fa_proc_year AS acyr_code,
                t.term_code,
                t.semester,
                t.group_code,
                trunc(t.start_date + dates.numb) AS report_date,
                to_date(to_char(trunc(t.start_date + dates.numb) + (4 / 24), 'MM/DD/YYYY hh24:mi:ss'), 'MM/DD/YYYY hh24:mi:ss') report_timestamp -- runs at 4am everyday
  FROM zbtm.terms_by_group_v t
  JOIN (SELECT LEVEL - 180 numb FROM dual CONNECT BY LEVEL <= 360) dates
    ON t.start_date + dates.numb <= trunc(SYSDATE)
   AND t.term_code NOT IN ('000000')
   AND t.group_code IN ('STD', 'MED')
 WHERE 1 = 1
   AND (trunc(t.start_date + dates.numb) >= trunc(SYSDATE - 3) -- running the last 3 days to catch anything we might have missed; to_date('2025-04-07','YYYY-MM-DD')
       OR trunc(t.start_date + dates.numb) = trunc(SYSDATE - 365.25))
   AND trunc(t.start_date + dates.numb) >= t.start_date - 180 -- begin tracking 90 days prior to start
   AND trunc(t.start_date + dates.numb) <= t.end_date -- end tracking on last day of term
 ORDER BY report_date DESC,
          acyr_code   ASC;
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
v_msg     := 'START - ' || rec.term_code || ' - ' || rec.report_date || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- truncate table  utl_d_aim.rsbbregfci_gtt;
INSERT INTO utl_d_aim.rsbbregfci_gtt
(rsbbregfci_pidm,
 rsbbregfci_acyr_code,
 rsbbregfci_term_code,
 rsbbregfci_camp_code,
 rsbbregfci_levl_code,
 rsbbregfci_styp_code,
 rsbbregfci_reg,
 rsbbregfci_fci,
 rsbbregfci_hours,
 rsbbregfci_fci_hours,
 rsbbregfci_report_date)
SELECT spriden_pidm,
       rec.acyr_code,
       rec.term_code,
       sgbstdn_camp_code,
       sgbstdn_levl_code,
       CASE
       WHEN sgbstdn_camp_code = 'R'
            AND appl.zsavappl_pidm IS NOT NULL THEN
        'N' -- RES student with App
       WHEN sgbstdn_camp_code = 'D'
            AND enrl_last_yr.pidm IS NULL THEN
        'N' -- LUO student not reg last year
       ELSE
        'R'
       END styp_code,
       CASE
       WHEN reg.pidm IS NOT NULL THEN
        1
       END AS reg_ind,
       CASE
       WHEN fci.pidm IS NOT NULL THEN
        1
       END fci_ind,
       reg.hours,
       CASE
       WHEN fci.pidm IS NOT NULL THEN
        reg.hours
       END fci_hours,
       rec.report_date
  FROM spriden
  JOIN sgbstdn
    ON sgbstdn_pidm = spriden_pidm
   AND sgbstdn_camp_code IS NOT NULL
   AND sgbstdn_program_1 IS NOT NULL
   AND spriden_change_ind IS NULL
   AND sgbstdn_term_code_eff = (SELECT MAX(d.sgbstdn_term_code_eff)
                                  FROM sgbstdn d
                                 WHERE d.sgbstdn_pidm = sgbstdn.sgbstdn_pidm
                                   AND d.sgbstdn_term_code_eff <= rec.term_code)
  JOIN zsaturn.szrlevl l
    ON l.szrlevl_levl_code = sgbstdn_levl_code
   AND l.szrlevl_is_stu_levl = 'Y'
   AND l.szrlevl_has_awardable_cred = 'Y'
  LEFT JOIN zexec.zsavappl appl
    ON appl.zsavappl_pidm = spriden_pidm
   AND appl.zsavappl_levl_code = sgbstdn_levl_code
   AND appl.zsavappl_camp_code = sgbstdn_camp_code
   AND appl.zsavappl_camp_code = 'R'
   AND appl.zsavappl_apdc_code IN (SELECT stvapdc_code FROM stvapdc WHERE stvapdc_inst_acc_ind = 'Y')
   AND appl.zsavappl_apst_code <> 'W'
   AND appl.zsavappl_term_code IN (rec.term_code, CASE WHEN rec.semester = 'FAL' THEN rec.term_code - 10 END)
  LEFT JOIN (SELECT DISTINCT enrl.pidm FROM utl_d_aim.szrenrl enrl WHERE enrl.acad_year = rec.acyr_code - 101) enrl_last_yr
    ON enrl_last_yr.pidm = spriden_pidm
  LEFT JOIN (SELECT sfrstca_pidm AS pidm,
                    SUM(sfrstca_credit_hr) AS hours
               FROM saturn.sfrstca
               JOIN saturn.stvrsts
                 ON stvrsts_code = sfrstca_rsts_code
                AND stvrsts_incl_sect_enrl = 'Y'
                AND sfrstca.sfrstca_seq_number = (SELECT MAX(d.sfrstca_seq_number)
                                                    FROM sfrstca d
                                                   WHERE d.sfrstca_pidm = sfrstca.sfrstca_pidm
                                                     AND d.sfrstca_term_code = sfrstca.sfrstca_term_code
                                                     AND d.sfrstca_crn = sfrstca.sfrstca_crn
                                                     AND d.sfrstca_source_cde = 'BASE'
                                                     AND d.sfrstca_rsts_date <= rec.report_timestamp -- runs at 4am everyday
                                                  )
               JOIN zsaturn.szrlevl l
                 ON l.szrlevl_levl_code = sfrstca_levl_code
                AND l.szrlevl_is_stu_levl = 'Y'
                AND l.szrlevl_has_awardable_cred = 'Y'
               JOIN ssbsect
                 ON ssbsect_term_code = sfrstca_term_code
                AND ssbsect_crn = sfrstca_crn
                AND ssbsect_subj_code NOT IN ('CSER', 'FRSM', 'GRST', 'NEWS', 'NSSR')
              WHERE 1 = 1
                AND sfrstca_term_code = rec.term_code
                AND sfrstca_rsts_date <= rec.report_timestamp -- runs at 4am everyday
                AND sfrstca_source_cde = 'BASE'
              GROUP BY sfrstca_pidm) reg
    ON reg.pidm = spriden_pidm
  LEFT JOIN (SELECT DISTINCT fci.zfrfcis_pidm AS pidm
               FROM zfincheckin.zfrfcis fci
              WHERE fci.zfrfcis_term = rec.term_code
                AND fci.zfrfcis_create_date <= rec.report_timestamp -- runs at 4am everyday
                AND fci.zfrfcis_withdrawn IS NULL) fci
    ON fci.pidm = spriden_pidm
 WHERE 1 = 1
   AND (reg.pidm IS NOT NULL OR fci.pidm IS NOT NULL)
   AND NOT EXISTS (SELECT 'X'
          FROM utl_d_aim.rsbbregfci_gtt gtt
         WHERE gtt.rsbbregfci_term_code = rec.term_code
           AND gtt.rsbbregfci_pidm = reg.pidm
           AND gtt.rsbbregfci_report_date = rec.report_date);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || rec.term_code || ' - ' || rec.report_date || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
MERGE INTO utl_d_aim.rsbbregfci tgt
USING (SELECT v_etl_date rsbbregfci_activity_date,
              rec.report_date AS rsbbregfci_report_date,
              v_report_type  AS rsbbregfci_report,
              rsbbregfci_acyr_code,
              rsbbregfci_term_code,
              rsbbregfci_camp_code,
              rsbbregfci_levl_code,
              rsbbregfci_styp_code,
              COUNT(DISTINCT CASE
                    WHEN rsbbregfci_reg IS NOT NULL THEN
                     rsbbregfci_pidm
                    END) rsbbregfci_reg,
              COUNT(DISTINCT CASE
                    WHEN rsbbregfci_fci IS NOT NULL THEN
                     rsbbregfci_pidm
                    END) rsbbregfci_fci,
              COUNT(DISTINCT CASE
                    WHEN rsbbregfci_reg IS NOT NULL
                         AND rsbbregfci_fci IS NOT NULL THEN
                     rsbbregfci_pidm
                    END) rsbbregfci_reg_fci,
              COUNT(DISTINCT CASE
                    WHEN rsbbregfci_reg IS NOT NULL
                         AND wd_ind IS NULL
                         AND rsbbregfci_fci IS NULL THEN
                     rsbbregfci_pidm
                    END) rsbbregfci_reg_not_fci,
              COUNT(DISTINCT CASE
                    WHEN rsbbregfci_reg IS NULL
                         AND rsbbregfci_fci IS NOT NULL
                         AND winter_ind IS NOT NULL THEN
                     NULL
                    WHEN rsbbregfci_reg IS NULL
                         AND rsbbregfci_fci IS NOT NULL THEN
                     rsbbregfci_pidm
                    END) rsbbregfci_fci_not_reg,
              coalesce(SUM(rsbbregfci_hours), 0) rsbbregfci_hours,
              coalesce(SUM(CASE
                           WHEN rsbbregfci_fci IS NOT NULL THEN
                            rsbbregfci_hours
                           END), 0) rsbbregfci_fci_hours
         FROM (SELECT rsbbregfci_pidm,
                      rsbbregfci_acyr_code,
                      rsbbregfci_term_code,
                      rsbbregfci_camp_code,
                      rsbbregfci_levl_code,
                      rsbbregfci_styp_code,
                      rsbbregfci_reg,
                      rsbbregfci_fci,
                      rsbbregfci_hours,
                      rsbbregfci_fci_hours,
                      CASE
                      WHEN EXISTS (SELECT 'X'
                              FROM sfrstcr
                              JOIN utl_d_aim.rsbbregfci_gtt gtt
                                ON gtt.rsbbregfci_pidm = sfrstcr_pidm
                               AND gtt.rsbbregfci_term_code = rec.term_code
                              JOIN stvrsts
                                ON stvrsts_code = sfrstcr_rsts_code
                               AND stvrsts_incl_sect_enrl = 'Y'
                               AND sfrstcr_term_code = CASE
                                   WHEN rec.semester = 'SPR' THEN
                                    rec.term_code - 10
                                   END
                              JOIN zsaturn.szrlevl l
                                ON l.szrlevl_levl_code = sfrstcr_levl_code
                               AND l.szrlevl_is_stu_levl = 'Y'
                               AND l.szrlevl_has_awardable_cred = 'Y'
                              JOIN ssbsect
                                ON ssbsect_term_code = sfrstcr_term_code
                               AND ssbsect_crn = sfrstcr.sfrstcr_crn
                               AND ssbsect_subj_code NOT IN ('CSER', 'FRSM', 'GRST', 'NEWS', 'NSSR')
                             WHERE sfrstcr_pidm = gtt.rsbbregfci_pidm) THEN
                       1
                      END winter_ind,
                      CASE
                      WHEN EXISTS (SELECT 'X'
                              FROM sfbetrm
                              JOIN utl_d_aim.rsbbregfci_gtt gtt
                                ON gtt.rsbbregfci_pidm = sfbetrm_pidm
                               AND gtt.rsbbregfci_term_code = rec.term_code
                             WHERE sfbetrm_term_code = rec.term_code
                               AND sfbetrm_ests_code LIKE 'W%'
                               AND sfbetrm_pidm = gtt.rsbbregfci_pidm) THEN
                       1
                      END wd_ind
                 FROM utl_d_aim.rsbbregfci_gtt gtt
                WHERE 1 = 1
                  AND gtt.rsbbregfci_term_code = rec.term_code)
        GROUP BY rsbbregfci_acyr_code,
                 rsbbregfci_term_code,
                 rsbbregfci_camp_code,
                 rsbbregfci_styp_code,
                 rsbbregfci_levl_code) src
ON (tgt.rsbbregfci_report_date = src.rsbbregfci_report_date AND tgt.rsbbregfci_report = src.rsbbregfci_report AND tgt.rsbbregfci_acyr_code = src.rsbbregfci_acyr_code AND tgt.rsbbregfci_term_code = src.rsbbregfci_term_code AND tgt.rsbbregfci_camp_code = src.rsbbregfci_camp_code AND tgt.rsbbregfci_styp_code = src.rsbbregfci_styp_code AND tgt.rsbbregfci_levl_code = src.rsbbregfci_levl_code)
WHEN MATCHED THEN
UPDATE
   SET tgt.rsbbregfci_activity_date = src.rsbbregfci_activity_date,
       tgt.rsbbregfci_reg           = src.rsbbregfci_reg,
       tgt.rsbbregfci_fci           = src.rsbbregfci_fci,
       tgt.rsbbregfci_reg_fci       = src.rsbbregfci_reg_fci,
       tgt.rsbbregfci_reg_not_fci   = src.rsbbregfci_reg_not_fci,
       tgt.rsbbregfci_fci_not_reg   = src.rsbbregfci_fci_not_reg,
       tgt.rsbbregfci_hours         = src.rsbbregfci_hours,
       tgt.rsbbregfci_fci_hours     = src.rsbbregfci_fci_hours
WHEN NOT MATCHED THEN
INSERT
(rsbbregfci_report_date,
 rsbbregfci_report,
 rsbbregfci_acyr_code,
 rsbbregfci_term_code,
 rsbbregfci_camp_code,
 rsbbregfci_levl_code,
 rsbbregfci_styp_code,
 rsbbregfci_reg,
 rsbbregfci_fci,
 rsbbregfci_reg_fci,
 rsbbregfci_reg_not_fci,
 rsbbregfci_fci_not_reg,
 rsbbregfci_hours,
 rsbbregfci_activity_date,
 rsbbregfci_fci_hours)
VALUES
(src.rsbbregfci_report_date,
 src.rsbbregfci_report,
 src.rsbbregfci_acyr_code,
 src.rsbbregfci_term_code,
 src.rsbbregfci_camp_code,
 src.rsbbregfci_levl_code,
 src.rsbbregfci_styp_code,
 src.rsbbregfci_reg,
 src.rsbbregfci_fci,
 src.rsbbregfci_reg_fci,
 src.rsbbregfci_reg_not_fci,
 src.rsbbregfci_fci_not_reg,
 src.rsbbregfci_hours,
 src.rsbbregfci_activity_date,
 src.rsbbregfci_fci_hours);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || rec.term_code || ' - ' || rec.report_date || ' - ' || v_report_type || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
utl_d_aim.truncate_table(v_table_name => 'rsbbregfci_gtt'); -- REMOVE RECORDS AFTER EVERY LOOP
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
VERSION    DATE        USERNAME       UPDATES
1.0        05-26-2016  odavenport2    --Initial release
2.0        06-23-2016  odavenport2    --changed to pidm-based model; changed to dimensional dates model
3.0         10-04-2016  odavenport2    --changed to aggregate model; removed dimensional dates model; created new table
4.0        11-16-2018  odavenport2     --added FCI hours column
5.0        12-23-2020  lxhatfield      --changed new res logic
5.1        09-17-2021  lxhatfield      --fixed error where res new hours was using count distinct instead of sum
---     05-17-2023  WGRIFFITH2  --Dealing with EM courses and updating code to use job_log
---     07-24-2023  WGRIFFITH2  --TKT2753928-Optimization
---     10-13-2023  WGRIFFITH2  --Fixing issues from code updates on 7/24/23
---     10-23-2023  WGRIFFITH2  --sfrstca instead of sfrstcr - TKT2798583
---     10-26-2023  WGRIFFITH2  --split into different procs due to performance issues
------------------------------------------------------------------------------------------------*/
END etl_aim_regfcisum_main_reg_old;
END load_aim_etl_regfci;
-- GRANT EXECUTE ON load_aim_etl_regfci TO utl_d_aim;
-- GRANT EXECUTE ON load_aim_etl_regfci TO utl_d_aa;
-- GRANT EXECUTE ON load_aim_etl_regfci TO utl_d_lms;
-- GRANT EXECUTE ON load_aim_etl_regfci TO wgriffith2;
-- GRANT EXECUTE ON load_aim_etl_regfci TO mapeele;
-- GRANT EXECUTE ON load_aim_etl_regfci TO clreid2;