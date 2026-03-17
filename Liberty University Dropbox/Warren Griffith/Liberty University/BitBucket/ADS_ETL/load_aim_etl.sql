create or replace package load_aim_etl is
procedure etl_aim_nadrops(jobnumber number, processid varchar2, processname varchar2);
procedure etl_aim_szrcurr_refresh(jobnumber number, processid varchar2, processname varchar2);
procedure etl_aim_szrdgmr_refresh(jobnumber number, processid varchar2, processname varchar2);
procedure etl_aim_szriden_refresh(jobnumber number, processid varchar2, processname varchar2, mod_number number);
procedure etl_aim_szrcrse_refresh(jobnumber number, processid varchar2, processname varchar2, mod_number number);
procedure etl_aim_szrenrl_refresh(jobnumber number, processid varchar2, processname varchar2, mod_number number);
procedure etl_aim_robrregaudit_refresh(jobnumber number, processid varchar2, processname varchar2);
procedure etl_aim_rolllevl_refresh(jobnumber number, processid varchar2, processname varchar2);
procedure etl_aim_waitlist_refresh(jobnumber number, processid varchar2, processname varchar2);
procedure etl_aim_szrroom_refresh(jobnumber number, processid varchar2, processname varchar2);
procedure etl_aim_szrmros_refresh (jobnumber number, processid varchar2, processname varchar2); 
procedure etl_aim_szrctlg_refresh(jobnumber number, processid varchar2, processname varchar2);
procedure etl_aim_szrasgn_refresh(jobnumber number, processid varchar2, processname varchar2);
procedure etl_aim_progcolldept_refresh(jobnumber number, processid varchar2, processname varchar2);
procedure etl_aim_acad_cohorts_refresh (jobnumber number, processid varchar2, processname varchar2);
procedure etl_aim_traneval_sd_mod(jobnumber number, processid varchar2, processname varchar2, mod_number number); ---        06-11-2020  odavenport2   initial release
procedure etl_aim_zsraacc_refresh (jobnumber number, processid varchar2, processname varchar2);
procedure etl_aim_ffd_faculty (jobnumber number, processid varchar2, processname varchar2);
procedure etl_aim_ute_emails_refresh(jobnumber number, processid varchar2, processname varchar2);
procedure etl_aim_faculty_work_hours_refresh(jobnumber number, processid varchar2, processname varchar2);
procedure etl_aim_disclosure_refresh (jobnumber number, processid varchar2, processname varchar2);
procedure etl_aim_inplace_student_program(jobnumber number, processid varchar2, processname varchar2);
procedure etl_aim_inplace_student_course(jobnumber number, processid varchar2, processname varchar2);
procedure etl_aim_inplace_student_program_pch(jobnumber number, processid varchar2, processname varchar2);
procedure etl_aim_inplace_student_course_pch(jobnumber number, processid varchar2, processname varchar2);
procedure etl_aim_banner_log_checks (jobnumber number, processid varchar2, processname varchar2);
procedure etl_aim_prerequisites_refresh(jobnumber number, processid varchar2, processname varchar2);
procedure etl_aim_szrstfr_refresh(jobnumber number, processid varchar2, processname varchar2, mod_number number);
procedure etl_aim_luoa_course_weights(jobnumber   number, processid   varchar2, processname varchar2);
end load_aim_etl;
/

create or replace package body load_aim_etl IS

PROCEDURE etl_aim_luoa_course_weights(jobnumber   NUMBER, processid   VARCHAR2, processname VARCHAR2) IS
/*
Table: utl_d_aim.luoa_course_weights

Primary Keys: NONE

Unique index: subj_code, crse_numb

Purpose:
- used for paying LUOA faculty storing the LUOA course weights to calculate the amounts

Conditions:
-

*/
-- DECLARE
v_etl_date DATE := SYSDATE;
v_msg      VARCHAR2(2000);
v_instance VARCHAR2(50) := upper('ALL'); -- inst from the jams job; used for determining instance
v_partition NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
-- v_mod         NUMBER := 5; -- number of partitions to be created
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_aim_luoa_course_weights';
-- CURSOR
CURSOR c_terms IS
SELECT terms.term_code,
       terms.start_date,
       terms.end_date,
       terms.group_code
  FROM zbtm.terms_by_group_v terms
 WHERE (terms.group_code = 'ACD' AND SYSDATE >= terms.start_date - 7 AND SYSDATE <= terms.end_date + 21);
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
v_msg     := 'START - ' || rec.term_code || ' - ' || rec.start_date || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- truncate and reload
utl_d_aim.truncate_table(v_table_name => 'luoa_course_weights');
INSERT INTO utl_d_aim.luoa_course_weights
(subj_code,
 crse_numb,
 course_level_weight)
SELECT DISTINCT ssbsect.ssbsect_subj_code AS subj_code,
                ssbsect.ssbsect_crse_numb AS crse_numb,
                CASE
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'APP0K00' THEN
                 150
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'APP0K01' THEN
                 300
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'APP0K02' THEN
                 300
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'APP0K04' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'APP0K06' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'APP0K07' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'APP2804' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'APP0750' THEN
                 300
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'APP1202' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'APP2400' THEN
                 300
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'APP2000' THEN
                 300
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'APP2050' THEN
                 300
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'APP2107' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'APP2200' THEN
                 300
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'APP2203' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'APP2204' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'APP2800' THEN
                 300
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'APP2806' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'APP2807' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'APP1200' THEN
                 100
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'APP2404' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'APP2504' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'APP1201' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'APP1300' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'APP2900' THEN
                 300
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'APP2904' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'APP2104' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'APP2106' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'APP2500' THEN
                 300
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'BIB0104' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'BIB0106' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'BIB0107' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'BIB0204' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'BIB0206' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'BIB0207' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'BIB0304' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'BIB0306' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'BIB0307' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'BIB0404' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'BIB0406' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'BIB0407' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'BIB0504' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'BIB0506' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'BIB0507' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'BIB0604' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'BIB0606' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'BIB0607' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'BIB0700' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'BIB0701' THEN
                 400
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'BIB0702' THEN
                 400
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'BIB0704' THEN
                 800
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'BIB0706' THEN
                 800
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'BIB0707' THEN
                 266.67
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'BIB0800' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'BIB0801' THEN
                 400
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'BIB0802' THEN
                 400
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'BIB0804' THEN
                 800
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'BIB0806' THEN
                 800
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'BIB0807' THEN
                 266.67
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'BIB0900' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'BIB0901' THEN
                 400
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'BIB0902' THEN
                 400
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'BIB0904' THEN
                 800
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'BIB0906' THEN
                 800
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'BIB0907' THEN
                 266.67
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'BIB0K04' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'BIB0K06' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'BIB0K07' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'BIB1000' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'BIB1001' THEN
                 400
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'BIB1002' THEN
                 400
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'BIB1004' THEN
                 800
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'BIB1006' THEN
                 800
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'BIB1007' THEN
                 266.67
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'BIB2150' THEN
                 400
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'BIB2250' THEN
                 400
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'BIB2300' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'BIB2301' THEN
                 400
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'BIB2302' THEN
                 400
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'BIBB150' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'BIBB151' THEN
                 400
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'BIBB152' THEN
                 400
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'BIBG150' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'BIBG151' THEN
                 400
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'BIBG152' THEN
                 400
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'HIS0100' THEN
                 150
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'HIS0102' THEN
                 300
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'HIS0106' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'HIS0107' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'HIS0100' THEN
                 150
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'HIS0104' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'HIS0204' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'HIS0206' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'HIS0207' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'HIS0304' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'HIS0306' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'HIS0307' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'HIS0404' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'HIS0406' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'HIS0407' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'HIS0504' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'HIS0506' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'HIS0507' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'HIS0604' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'HIS0606' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'HIS0607' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'HIS0704' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'HIS0706' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'HIS0707' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'HIS0904' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'HIS0906' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'HIS0907' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'HIS0954' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'HIS0956' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'HIS0957' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'HIS1004' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'HIS1006' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'HIS1007' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'HIS1104' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'HIS1106' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'HIS1107' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'HIS1146' THEN
                 300
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'HIS1148' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'HIS1204' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'HIS1206' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'HIS2000' THEN
                 300
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'HIS2150' THEN
                 300
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'HIS2300' THEN
                 300
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'CSB2003' THEN
                 300
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'HPEB100' THEN
                 300
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'HPEB104' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'HPEB106' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'HPEB150' THEN
                 300
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'HPEB154' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'HPEB200' THEN
                 300
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'HPEB204' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'HPEB206' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'HPEB250' THEN
                 300
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'HPEB254' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'HPEG100' THEN
                 300
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'HPEG104' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'HPEG106' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'HPEG150' THEN
                 300
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'HPEG154' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'HPEG200' THEN
                 300
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'HPEG204' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'HPEG206' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'HPEG250' THEN
                 300
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'HPEG254' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN0104' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN0106' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN0107' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN0204' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN0206' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN0207' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN0304' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN0306' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN0307' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN0404' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN0406' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN0407' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN0504' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN0506' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN0507' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN0604' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN0606' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN0607' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN0651' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN0700' THEN
                 100
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN0701' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN0702' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN0800' THEN
                 100
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN0801' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN0802' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN0900' THEN
                 100
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN0901' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN0902' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN0K04' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN0K06' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN0K07' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN1000' THEN
                 100
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN1001' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN1002' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN1100' THEN
                 100
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN1101' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN1102' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN1200' THEN
                 100
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN1201' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN1202' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN1600' THEN
                 100
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN1601' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN1602' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN1700' THEN
                 100
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN1701' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN1702' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN1900' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN2000' THEN
                 300
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN2100' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN2150' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN2170' THEN
                 100
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN2171' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN2172' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN2180' THEN
                 100
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN2181' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN2182' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN2200' THEN
                 100
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN2201' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN2202' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN2300' THEN
                 100
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN2301' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN2302' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN2400' THEN
                 100
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN2401' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN2402' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN2600' THEN
                 100
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN2601' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN2602' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN2700' THEN
                 100
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN2701' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN2702' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN2800' THEN
                 100
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN2801' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN2802' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'LAN2950' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT0104' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT0106' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT0107' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT0204' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT0206' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT0207' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT0304' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT0306' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT0307' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT0404' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT0406' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT0407' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT0504' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT0506' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT0507' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT0604' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT0606' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT0607' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT0700' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT0701' THEN
                 400
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT0702' THEN
                 400
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT0704' THEN
                 800
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT0706' THEN
                 800
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT0707' THEN
                 266.67
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT0800' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT0801' THEN
                 400
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT0802' THEN
                 400
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT0804' THEN
                 800
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT0806' THEN
                 800
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT0807' THEN
                 266.67
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT0900' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT0901' THEN
                 400
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT0902' THEN
                 400
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT0904' THEN
                 800
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT0906' THEN
                 800
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT0907' THEN
                 266.67
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT0K04' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT0K06' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT0K07' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT1000' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT1001' THEN
                 400
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT1002' THEN
                 400
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT1004' THEN
                 800
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT1006' THEN
                 800
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT1007' THEN
                 266.67
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT1100' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT1101' THEN
                 400
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT1102' THEN
                 400
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT1104' THEN
                 800
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT1106' THEN
                 800
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT1107' THEN
                 266.67
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT1200' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT1201' THEN
                 400
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT1202' THEN
                 400
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT1204' THEN
                 800
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT1206' THEN
                 800
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT1207' THEN
                 266.67
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT1300' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT1301' THEN
                 400
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT1302' THEN
                 400
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT1304' THEN
                 800
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT1306' THEN
                 800
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT1307' THEN
                 266.67
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT1400' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT1401' THEN
                 400
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT1402' THEN
                 400
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT1404' THEN
                 800
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT1406' THEN
                 800
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT1407' THEN
                 266.67
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT2000' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT2001' THEN
                 400
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT2002' THEN
                 400
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT2100' THEN
                 400
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'MAT2104' THEN
                 800
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'SCI0100' THEN
                 150
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'SCI0102' THEN
                 300
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'SCI0106' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'SCI0107' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'SCI0104' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'SCI0204' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'SCI0206' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'SCI0207' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'SCI0304' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'SCI0306' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'SCI0307' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'SCI0404' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'SCI0406' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'SCI0407' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'SCI0504' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'SCI0506' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'SCI0507' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'SCI0604' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'SCI0606' THEN
                 600
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'SCI0607' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'SCI0700' THEN
                 100
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'SCI0701' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'SCI0702' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'SCI0800' THEN
                 100
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'SCI0801' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'SCI0802' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'SCI0900' THEN
                 100
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'SCI0901' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'SCI0902' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'SCI1000' THEN
                 100
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'SCI1001' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'SCI1002' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'SCI1100' THEN
                 100
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'SCI1101' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'SCI1102' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'SCI1200' THEN
                 100
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'SCI1201' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'SCI1202' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'SCI2100' THEN
                 100
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'SCI2101' THEN
                 200
                WHEN ssbsect_subj_code || ssbsect_crse_numb = 'SCI2102' THEN
                 200
                WHEN ssbsect.ssbsect_crse_numb LIKE '%0' THEN
                 150
                WHEN ssbsect.ssbsect_crse_numb LIKE '%1' THEN
                 300
                WHEN ssbsect.ssbsect_crse_numb LIKE '%2' THEN
                 300
                WHEN ssbsect.ssbsect_crse_numb LIKE '%50' THEN
                 350
                WHEN ssbsect.ssbsect_crse_numb LIKE '%3' THEN
                 400
                WHEN ssbsect.ssbsect_crse_numb LIKE '%4' THEN
                 400
                WHEN ssbsect.ssbsect_crse_numb LIKE '%6' THEN
                 400
                WHEN ssbsect.ssbsect_crse_numb LIKE '%7' THEN
                 133.3
                ELSE
                 NULL
                END course_level_weight
  FROM ssbsect
 WHERE 1 = 1
   AND ssbsect_subj_code IN ('APP', 'BIB', 'CSB', 'HIS', 'HPE', 'LAN', 'MAT', 'SCI')
   AND ssbsect_term_code = rec.term_code
   AND ssbsect_subj_code || ssbsect_crse_numb NOT IN
       ('APP1303', 'APP2903', 'HIS0009', 'HIS0103', 'HIS1103', 'LAN0000', 'LAN0001', 'LAN0006', 'LAN0009', 'LAN0070', 'LAN0080', 'LAN00S0', 'MAT0006', 'MAT0007', 'MAT0008', 'MAT0009', 'MAT0010', 'MAT0011', 'MAT0012', 'MAT0710', 'SCI0009', 'SCI0010', 'SCI0103', 'MAT0810', 'MAT0910',
        /*as of 7/3/2025*/ 'APP0700', 'APP0701', 'APP0702', 'APP2801', 'APP2802', 'APP2806', 'APP2807', 'HIS2150', 'LAN2000', 'LAN2180', 'LAN2181', 'LAN2182', 'APP1304')
   AND ssbsect_crse_numb NOT LIKE '3%';
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || rec.term_code || ' - ' || rec.start_date || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- utl_d_aim.truncate_table(v_table_name => 'znadrop_gtt'); -- truncate after a successful loop completes
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
VERSION    DATE        USERNAME       UPDATES
---        06-30-2025  NRTHOMASON     --Initial release
---        07-07-2025  NRTHOMASON     --Adding more courses to table
---        10-14-2025  NRTHOMASON     --Adding "WHEN ssbsect_subj_code || ssbsect_crse_numb = 'HIS0100' THEN 150"
------------------------------------------------------------------------------------------------*/
END etl_aim_luoa_course_weights;

PROCEDURE etl_aim_szrstfr_refresh(jobnumber number, processid varchar2, processname varchar2, mod_number number) is
/*
Table: utl_d_aim.szrstfr

Primary Keys:

Unique index:

Purpose:
- Calculate the student faculty ratio. For more information, contact mapeele

Conditions:
-

-
*/
--DECLARE
v_etl_date    DATE := SYSDATE;
v_instance VARCHAR2(50) := upper('ALL'); -- inst from the jams job; used for determining instance
v_partition NUMBER := 0 ; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_mod         NUMBER := 5; -- number of partitions to be created
v_msg         VARCHAR2(2000 CHAR);
v_job_id      VARCHAR2(32);
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_cpu         NUMBER := 4; -- number of CPUs used for parallelization - do not exceed 20 CPUs [v_mod x v_cpu] if running simultaneously
v_proc        VARCHAR2(100) := 'etl_aim_szrstfr_refresh';
CURSOR c_terms IS
SELECT t.term_code
  FROM zbtm.terms_by_group_v t
 WHERE 1 = 1
   AND SYSDATE < t.end_date + 21 -- Current AND future enrollment starting within the next 90 days
   AND t.start_date - 180 <= SYSDATE -- Current AND future enrollment starting within the next 90 days
   AND t.group_code IN ('STD')
   AND t.term_code IN (SELECT DISTINCT ssbsect_term_code FROM ssbsect WHERE ssbsect_enrl > 0)
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
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- !!! GLOBAL TEMP TABLE - PRESERVES ROWS ON COMMIT !!!
-- multiple runs per session with cause unique constraint (constraint_name) violated
-- truncate table szrstfr_prog_gtt;
INSERT INTO utl_d_aim.szrstfr_prog_gtt
(pidm,
 term_code,
 priority,
 program)
SELECT *
  FROM (SELECT enrl.pidm,
               enrl.term_code,
               lcur.prog_code_1,
               lcur.prog_code_2,
               lcur.prog_code_3,
               lcur.prog_code_4,
               lcur.prog_code_5
          FROM zexec.zsavlcur lcur
          JOIN utl_d_aim.szrenrl enrl
            ON substr(enrl.term_code, 1, 5) || '0' = rec.term_code
           AND enrl.pidm = lcur.pidm
           and mod(enrl.pidm,v_mod) = v_partition
           AND enrl.term_hours > 0
           AND enrl.term_code BETWEEN lcur.from_term AND lcur.end_term) unpivot(program FOR priority IN(prog_code_1 AS 1, prog_code_2 AS 2, prog_code_3 AS 3, prog_code_4 AS 4, prog_code_5 AS 5));
v_count       := SQL%ROWCOUNT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- !!! GLOBAL TEMP TABLE - PRESERVES ROWS ON COMMIT !!!
-- multiple runs per session with cause unique constraint (constraint_name) violated
-- truncate table szrstfr_audit_gtt;
INSERT /*+*/
INTO utl_d_aim.szrstfr_audit_gtt
(pidm,
 audit_term,
 prog_code,
 prog_ctlg_term,
 blck_code,
 blck_code_2,
 blck_desc,
 crse,
 term_code,
 crn,
 grde,
 course_type)
SELECT base.pidm,
       base.audit_term,
       base.prog_code,
       base.prog_ctlg_term,
       base.blck_code,
       base.blck_code_2,
       base.blck_desc,
       base.crse,
       base.term_code,
       base.crn,
       base.grde,
       CASE
       WHEN MAX(CASE
                WHEN b.majr_blck_ind = 'Y'
                     OR b.blck_code IN ('MJTEACHLIC') THEN
                 rc.crse
                END) IS NOT NULL
            OR base.majr_blck_ind = 'Y'
            OR base.blck_code = 'MJTEACHLIC' THEN
        'Major'
       WHEN MAX(CASE
                WHEN b.blck_code IN ('MJFOUNDCOUR', 'MJDIRECTCOUR') THEN
                 rc.crse
                END) IS NOT NULL
            OR base.blck_code IN ('MJFOUNDCOUR', 'MJDIRECTCOUR') THEN
        'Major Foundational/Directed'
       WHEN base.minr_blck_ind = 'Y'
            OR MAX(CASE
                   WHEN b.minr_blck_ind = 'Y' THEN
                    rc.crse
                   END) IS NOT NULL THEN
        'Minor'
       WHEN MAX(CASE
                WHEN b.blck_code NOT IN ('FALLTHRU') THEN
                 rc.crse
                END) IS NOT NULL THEN
        'General Education'
       WHEN base.blck_code = 'FRELECTIVE' THEN
        'Free Elective'
       WHEN base.blck_code = 'FALLTHRU' THEN
        'Fall Through'
       ELSE
        'General Education'
       END AS course_type
  FROM (SELECT v.davaudit_id,
               v.pidm,
               v.audit_term,
               v.prog_code,
               v.prog_ctlg_term,
               a.blck_code,
               a.blck_code_2,
               b.blck_desc,
               b.majr_blck_ind,
               b.minr_blck_ind,
               b.inds_aos_ind,
               c.crse,
               c.term_code,
               c.crn,
               c.grde
          FROM zdegree_audit.davaudit v
          JOIN zdegree_audit.daaudit a
            ON a.davaudit_id = v.davaudit_id
           AND a.req_met_rule_use_ind = 'Y' -- this will remove OR options that are not the fastest path
           AND mod(v.pidm,v_mod) = v_partition
           JOIN utl_d_aim.szrstfr_prog_gtt prog -- narrow down the population
           ON prog.pidm=v.pidm
           AND prog.term_code = v.audit_term
          JOIN zdegree_audit.davblocks b
            ON b.blck_code = a.blck_code
           AND b.meta_blck_ind = 'N' -- remove the addtional details "meta" blocks, these are normally MINRES type blocks
           AND b.gradreqs_show_ind = 'N'
          JOIN zdegree_audit.davblocks b2
            ON b2.blck_code = a.blck_code_2
          JOIN zdegree_audit.dacrsehistused u
            ON u.davaudit_id = v.davaudit_id
           AND u.used_daaudit_id = a.dacrserules_id
          JOIN zdegree_audit.dacrsehist c
            ON c.davaudit_id = v.davaudit_id
           AND c.id = u.dacrsehist_id
           AND c.pseudo_eqiv_course_ind = 'N'
           AND c.transfer_ind = 'N'
           AND substr(c.term_code, 1, 5) || '0' = rec.term_code
         WHERE v.current_ind = 'Y'
           AND v.whatif_prog_ind = 'N'
           AND v.audit_term = rec.term_code) base
  LEFT JOIN zdegree_audit.davaudit v
    ON v.pidm = base.pidm
   AND v.davaudit_id = base.davaudit_id
   AND base.blck_code = 'FALLTHRU'
   AND v.current_ind = 'Y'
   AND v.whatif_prog_ind = 'N'
   AND v.audit_term = rec.term_code
  LEFT JOIN zdegree_audit.daaudit a
    ON a.davaudit_id = v.davaudit_id
   AND a.req_met_rule_use_ind = 'Y'
  LEFT JOIN zdegree_audit.davblocks b
    ON b.blck_code = a.blck_code
   AND b.meta_blck_ind = 'N' -- remove the addtional details "meta" blocks, these are normally MINRES type blocks
   AND b.gradreqs_show_ind = 'N'
  LEFT JOIN zdegree_audit.dacrserec rc
    ON rc.dacrserules_id = a.dacrserules_id
   AND rc.crse = base.crse
 GROUP BY base.pidm,
          base.audit_term,
          base.prog_code,
          base.prog_ctlg_term,
          base.blck_code,
          base.blck_code_2,
          base.blck_desc,
          base.majr_blck_ind,
          base.minr_blck_ind,
          base.inds_aos_ind,
          base.crse,
          base.term_code,
          base.crn,
          base.grde;
v_count       := SQL%ROWCOUNT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
DELETE FROM utl_d_aim.szrstfr_hierarchy sh WHERE sh.term_code = rec.term_code AND mod(sh.pidm,v_mod) = v_partition;
v_count       := SQL%ROWCOUNT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'DELETE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
INSERT INTO utl_d_aim.szrstfr_hierarchy
(term_code,
 pidm,
 luid,
 last_name,
 first_name,
 hierarchy_title,
 hierarchy_coll_code,
 hierarchy_college,
 hierarchy_dept_code,
 hierarchy_dept_description,
 hierarchy_department,
 hierarchy_campus,
 hierarchy_level,
 hierarchy_primary_position,
 hierarchy_primary_faculty,
 faculty_contract_type,
 faculty_contract_campus,
 faculty_contract,
 faculty_contract_hours,
 hierarchy_position_rank,
 hierarchy_faculty_rank)
SELECT rec.term_code         AS term_code,
       i.spriden_pidm        AS pidm,
       i.spriden_id          AS luid,
       i.spriden_last_name   AS last_name,
       i.spriden_first_name  AS first_name,
       t.description         AS hierarchy_title,
       d.college_code        AS hierarchy_coll_code,
       coll.stvcoll_desc     AS hierarchy_college,
       d.dept_code           AS hierarchy_dept_code,
       d.description         AS hierarchy_dept_description,
       dept.stvdept_desc     AS hierarchy_department,
       camp.stvcamp_desc     AS hierarchy_campus,
       levl.stvlevl_desc     AS hierarchy_level,
       p.primary_position    AS hierarchy_primary_position,
       p.primary_faculty     AS hierarchy_primary_faculty,
       ct.contract_type      AS faculty_contract_type,
       ct.contract_camp_code AS faculty_contract_campus,
       ct.contract           AS faculty_contract,
       ct.contract_hours     AS faculty_contract_hours
     , dense_rank() over (partition by i.spriden_pidm
                          order by case when p.primary_position = 'Y' then 0 else 1 end
                                 , t.id
                                 , case when d.level_code = 'GR' then 0 else 1 end
                                 , rownum) as hierarchy_position_rank
     , dense_rank() over (partition by i.spriden_pidm
                          order by case when p.primary_faculty = 'Y' then 0 else 1 end
                                 , t.id desc
                                 , case when d.level_code = 'GR' then 0 else 1 end
                                 , rownum) as hierarchy_faculty_rank
  FROM saturn.spriden i
  JOIN zhierarchy.position p
    ON p.pidm = i.spriden_pidm
   AND i.spriden_change_ind IS NULL
   AND mod(i.spriden_pidm,v_mod) = v_partition
  JOIN zhierarchy.hierarchy_title h
    ON h.id = p.hierarchy_title_id
   AND h.hierarchy_type_id IN (1, 2, 3, 4, 5, 142, 143)
  JOIN zhierarchy.title t
    ON t.id = h.title_id
  JOIN zhierarchy.department d
    ON d.id = p.department_id
   AND nvl(d.college_code, 'handling nulls') != 'AC'
  LEFT JOIN saturn.stvcoll coll
    ON coll.stvcoll_code = d.college_code
  LEFT JOIN saturn.stvdept dept
    ON dept.stvdept_code = d.dept_code
  LEFT JOIN saturn.stvcamp camp
    ON camp.stvcamp_code = d.campus
  LEFT JOIN saturn.stvlevl levl
    ON levl.stvlevl_code = d.level_code
  LEFT JOIN (SELECT fcrf.szrfcrf_contractee_pidm AS pidm,
                    fcrf.szrfcrf_acyr AS acad_year,
                    fcrf.szrfcrf_contract_type AS contract_type,
                    fcrf.szrfcrf_req_hours AS contract_hours,
                    fcrf.szrfcrf_num_of_months AS contract_months,
                    fcrf.szrfcrf_from_date AS from_date,
                    fcrf.szrfcrf_effective_date AS contract_effective_date,
                    fcrf.szrfcrf_effective_to_date AS contract_effective_to_date,
                    fcrf.szrfcrf_to_date AS to_date,
                    fcrf.szrfcrf_id AS contract_id,
                    CASE
                    WHEN fcrf.szrfcrf_campus = 'DR' THEN
                     'D'
                    ELSE
                     fcrf.szrfcrf_campus
                    END AS contract_camp_code,
                    fcrf.szrfcrf_school AS contract_coll_code,
                    fcrf.szrfcrf_department AS contract_department,
                    r.zfrlist_char_04 AS contract,
                    dense_rank() over (partition by fcrf.szrfcrf_contractee_pidm, fcrf.szrfcrf_acyr
                                        order by fcrf.szrfcrf_effective_to_date desc, fcrf.szrfcrf_id desc, rownum desc) as ranking --shouldn't really be needed (just in case)
               FROM zprovost.szrfcrf fcrf
               JOIN saturn.stvterm tm
                 ON tm.stvterm_acyr_code = fcrf.szrfcrf_acyr
                AND tm.stvterm_code = rec.term_code
               LEFT JOIN zformdata.zfrlist r
                 ON r.zfrlist_list_code = 'FCRF_APEX_103_CONTRACT_RULE_MAP'
                AND r.zfrlist_active_yn = 'Y'
                AND fcrf.szrfcrf_contract_type = r.zfrlist_char_01
                AND fcrf.szrfcrf_contract_rule = r.zfrlist_char_03
              WHERE fcrf.szrfcrf_to_date = to_date('12/31/2099', 'mm/dd/yyyy')
                AND fcrf.szrfcrf_contract_type NOT IN ('GA', 'CN') --not grad assistant or contact expert contracts (LUCOM)/LUOA contracts
                AND fcrf.szrfcrf_contractee_pidm != '3248979' --tba
                AND (fcrf.szrfcrf_effective_to_date IS NULL --contract did not end
                    OR fcrf.szrfcrf_effective_to_date >= tm.stvterm_start_date AND fcrf.szrfcrf_effective_date < tm.stvterm_end_date)) ct
    ON ct.pidm = i.spriden_pidm
 WHERE EXISTS (SELECT 1
          FROM utl_d_aim.szrstfr z
         WHERE z.faculty_pidm = i.spriden_pidm
           AND substr(z.term_code, 1, 5) || '0' = rec.term_code);
v_count       := SQL%ROWCOUNT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
DELETE FROM utl_d_aim.szrstfr sh WHERE sh.term_code = rec.term_code AND mod(sh.student_pidm,v_mod) = v_partition;
v_count       := SQL%ROWCOUNT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'DELETE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
INSERT INTO utl_d_aim.szrstfr
(term_code,
 crn,
 ptrm_code,
 subj,
 numb,
 course,
 sect,
 instructional_method,
 registered_credit_hr,
 average_registered_credit_hr,
 catalog_credit_hr_low,
 catalog_credit_hr_high,
 has_general_studies_attribute,
 student_pidm,
 student_luid,
 student_last_name,
 student_first_name,
 student_fulltime_threshold,
 program,
 program_banner_description,
 program_web_display,
 is_teachout_program,
 program_major_group,
 program_group,
 program_degree_major_group,
 program_level,
 program_campus,
 program_degree_code,
 program_degree_level,
 program_coll_code,
 program_college,
 program_dept_code,
 program_department,
 dcpa_requirement_category,
 adjusted_program,
 adjusted_program_group,
 adjusted_program_coll_code,
 adjusted_program_college,
 adjusted_program_dept_code,
 adjusted_program_department,
 faculty_pidm,
 faculty_luid,
 faculty_last_name,
 faculty_first_name,
 faculty_contract_type,
 faculty_contract_campus,
 faculty_contract,
 faculty_contract_hours,
 faculty_level_taught,
 faculty_fulltime_threshold,
 has_gsa)
SELECT term_code,
       crn,
       ptrm_code,
       subj,
       numb,
       course,
       sect,
       instructional_method,
       registered_credit_hr,
       average_registered_credit_hr,
       catalog_credit_hr_low,
       catalog_credit_hr_high,
       has_general_studies_attribute,
       student_pidm,
       student_luid,
       student_last_name,
       student_first_name,
       student_fulltime_threshold,
       program,
       program_banner_description,
       program_web_display,
       is_teachout_program,
       program_major_group,
       program_group,
       program_degree_major_group,
       program_level,
       program_campus,
       program_degree_code,
       program_degree_level,
       program_coll_code,
       program_college,
       program_dept_code,
       program_department,
       dcpa_requirement_category
       /*******adjusted program ***************/,
       CASE
       WHEN acol.stvcoll_code = 'GS' THEN
        'General Education'
       WHEN dcpa_requirement_category = 'Minor' THEN
        'Minor'
       WHEN dcpa_requirement_category IN ('Fall Through', 'Free Elective', 'Free Elective/Fall Through') THEN
        'Free Elective/Fall Through'
       ELSE
        program
       END AS adjusted_program,
       CASE
       WHEN acol.stvcoll_code = 'GS' THEN
        'General Education'
       WHEN dcpa_requirement_category = 'Minor' THEN
        'Minor'
       WHEN dcpa_requirement_category IN ('Fall Through', 'Free Elective', 'Free Elective/Fall Through') THEN
        'Free Elective/Fall Through'
       ELSE
        program_degree_major_group
       END AS adjusted_program_group,
       CASE
       WHEN dcpa_requirement_category = 'Minor' THEN
        'Minor'
       WHEN dcpa_requirement_category IN ('Fall Through', 'Free Elective', 'Free Elective/Fall Through') THEN
        'Free Elective/Fall Through'
       ELSE
        acol.stvcoll_code
       END AS adjusted_program_coll_code,
       CASE
       WHEN dcpa_requirement_category = 'Minor' THEN
        'Minor'
       WHEN dcpa_requirement_category IN ('Fall Through', 'Free Elective', 'Free Elective/Fall Through') THEN
        'Free Elective/Fall Through'
       ELSE
        acol.stvcoll_desc
       END AS adjusted_program_college,
       CASE
       WHEN dcpa_requirement_category = 'Minor' THEN
        'Minor'
       WHEN dcpa_requirement_category IN ('Fall Through', 'Free Elective', 'Free Elective/Fall Through') THEN
        'Free Elective/Fall Through'
       ELSE
        adep.stvdept_code
       END AS adjusted_program_dept_code,
       CASE
       WHEN dcpa_requirement_category = 'Minor' THEN
        'Minor'
       WHEN dcpa_requirement_category IN ('Fall Through', 'Free Elective', 'Free Elective/Fall Through') THEN
        'Free Elective/Fall Through'
       ELSE
        adep.stvdept_desc
       END AS adjusted_program_department
       /*******faculty****************/,
       faculty_pidm,
       faculty_luid,
       faculty_last_name,
       faculty_first_name,
       faculty_contract_type,
       faculty_contract_campus,
       faculty_contract,
       faculty_contract_hours,
       faculty_level_taught,
       CASE
       WHEN faculty_level_taught = 'UG' THEN
        12
       ELSE
        9
       END faculty_fulltime_threshold,
       has_gsa
  FROM (SELECT /*****course data******/
          crse.term_code,
          crse.crn,
          crse.ptrm_code,
          crse.subj,
          crse.numb,
          crse.course,
          crse.sect,
          crse.insm_desc AS instructional_method,
          crse.credit_hr AS registered_credit_hr,
          ctlg.credit_hr_low AS catalog_credit_hr_low,
          ctlg.credit_hr_high AS catalog_credit_hr_high,
          nvl2(attr.crn, 'Yes', 'No') AS has_general_studies_attribute,
          avghr.avg_hr AS average_registered_credit_hr
          /*****student data******/,
          iden.szriden_pidm AS student_pidm,
          iden.szriden_id AS student_luid,
          iden.szriden_last_name AS student_last_name,
          iden.szriden_first_name AS student_first_name,
          crhr.rorcrhr_full_time_cr_hrs AS student_fulltime_threshold,
          prle.smrprle_program AS program,
          prle.smrprle_program_desc AS program_banner_description,
          zple.szrprle_web_display AS program_web_display,
          decode(mcrl.sormcrl_adm_ind, 'Y', 'No', 'Yes') AS is_teachout_program,
          pcd.majr_group AS program_major_group,
          pcd.majr_degc_group AS program_degree_major_group,
          dlev.stvdlev_desc || ': ' || pcd.majr_group AS program_group,
          plvl.stvlevl_desc AS program_level,
          pcmp.stvcamp_desc AS program_campus,
          prle.smrprle_degc_code AS program_degree_code,
          dlev.stvdlev_desc AS program_degree_level,
          prle.smrprle_coll_code AS program_coll_code,
          pcol.stvcoll_desc AS program_college,
          pdep.stvdept_code AS program_dept_code,
          pdep.stvdept_desc AS program_department,
          aud.course_type AS dcpa_requirement_category
                         , dense_rank() over (partition by crse.pidm
                                                         , prle.smrprle_program
                                                         , crse.term_code
                                                         , crse.crn
                                              order by case when aud.course_type = 'Major'
                                                            then 1
                                                            when aud.course_type = 'Major Foundational/Directed'
                                                            then 2
                                                            when aud.course_type = 'General Education'
                                                            then 3
                                                            when aud.course_type = 'Free Elective'
                                                            then 4
                                                            when aud.course_type = 'Fall Through'
                                                            then 5
                                                            else 9 --general ed
                                                       end
                                                     , rownum)                    as dcpa_ranking_within_programs
                         , dense_rank() over (partition by crse.pidm
                                                         , crse.term_code
                                                         , crse.crn
                                              order by case when aud.course_type = 'Major'
                                                            then 1
                                                            when aud.course_type = 'Major Foundational/Directed'
                                                            then 2
                                                            when aud.course_type = 'General Education'
                                                            then 3
                                                            when aud.course_type = 'Free Elective'
                                                            then 4
                                                            when aud.course_type = 'Fall Through'
                                                            then 5
                                                            else 9 --general ed
                                                       end)                       as dcpa_ranking_across_programs
          /*****faculty start********/,
          crse.faculty_id AS faculty_luid,
          crse.faculty_pidm,
          crse.faculty_last_name,
          crse.faculty_first_name,
          cntrct.faculty_contract_type,
          cntrct.faculty_contract_campus,
          cntrct.faculty_contract,
          cntrct.faculty_contract_hours,
          CASE
          WHEN MAX(levl.course_level) over(PARTITION BY crse.faculty_pidm) = MIN(levl.course_level) over(PARTITION BY crse.faculty_pidm) THEN
           levl.course_level
          ELSE
           'GR' --mixed level set as GR
          END AS faculty_level_taught,
          nvl2(gsa.crn, 'Yes', 'No') AS has_gsa
           FROM utl_d_aim.szrcrse crse
           JOIN saturn.stvterm term
             ON term.stvterm_code = crse.term_code
           JOIN utl_d_aim.szriden iden
             ON iden.szriden_pidm = crse.pidm
            AND SYSDATE BETWEEN iden.szriden_from_date AND iden.szriden_to_date
            AND mod(crse.pidm,v_mod) = v_partition
           JOIN utl_d_aim.szrstfr_prog_gtt prog
             ON prog.pidm = crse.pidm
            AND prog.term_code =crse.term_code
           JOIN saturn.smrprle prle
             ON prle.smrprle_program = prog.program
            AND prle.smrprle_levl_code != 'AC'
           JOIN saturn.stvdegc degc
             ON degc.stvdegc_code = prle.smrprle_degc_code
           JOIN saturn.stvdlev dlev
             ON dlev.stvdlev_code = degc.stvdegc_dlev_code
           JOIN saturn.sobcurr bcur
             ON bcur.sobcurr_program = prle.smrprle_program
           JOIN saturn.sorcmjr cmjr
             ON cmjr.sorcmjr_curr_rule = bcur.sobcurr_curr_rule
            AND cmjr.sorcmjr_term_code_eff = (SELECT MAX(cmjr2.sorcmjr_term_code_eff)
                                                FROM saturn.sorcmjr cmjr2
                                               WHERE cmjr2.sorcmjr_curr_rule = cmjr.sorcmjr_curr_rule
                                                 AND cmjr2.sorcmjr_term_code_eff <= substr(rec.term_code, 1, 5) || '5')
           JOIN saturn.sormcrl mcrl
             ON mcrl.sormcrl_curr_rule = bcur.sobcurr_curr_rule
            AND mcrl.sormcrl_term_code_eff = (SELECT MAX(mcrl2.sormcrl_term_code_eff)
                                                FROM saturn.sormcrl mcrl2
                                               WHERE mcrl2.sormcrl_curr_rule = mcrl.sormcrl_curr_rule
                                                 AND mcrl2.sormcrl_term_code_eff <= substr(rec.term_code, 1, 5) || '5')
           JOIN (SELECT szrcrse.term_code,
                       szrcrse.crn,
                       round(AVG(szrcrse.credit_hr)) AS avg_hr
                  FROM utl_d_aim.szrcrse
                 WHERE substr(szrcrse.term_code, 1, 5) = substr(rec.term_code, 1, 5)
                 GROUP BY szrcrse.term_code,
                          szrcrse.crn) avghr
             ON avghr.term_code = crse.term_code
            AND avghr.crn = crse.crn
           LEFT JOIN saturn.stvcoll pcol
             ON pcol.stvcoll_code = prle.smrprle_coll_code
           LEFT JOIN saturn.stvdept pdep
             ON pdep.stvdept_code = cmjr.sorcmjr_dept_code
           LEFT JOIN saturn.stvcamp pcmp
             ON pcmp.stvcamp_code = prle.smrprle_camp_code
           LEFT JOIN saturn.stvlevl plvl
             ON plvl.stvlevl_code = prle.smrprle_levl_code
           LEFT JOIN utl_d_aim.progcolldept pcd
             ON pcd.prog_code = prle.smrprle_program
           LEFT JOIN zsaturn.szrprle zple
             ON zple.szrprle_program = prle.smrprle_program
           LEFT JOIN utl_d_aim.szrctlg ctlg
             ON ctlg.subj = crse.subj
            AND ctlg.numb = crse.numb
            AND ctlg.camp_code = crse.camp_code
            AND crse.term_code BETWEEN ctlg.from_term AND ctlg.to_term
            AND SYSDATE BETWEEN ctlg.from_date AND ctlg.to_date
           LEFT JOIN (SELECT DISTINCT ssrattr_term_code AS term_code,
                                     ssrattr_crn       AS crn
                       FROM saturn.ssrattr
                      WHERE ssrattr_attr_code IN ('GS', 'GSD')) attr
             ON attr.term_code = crse.term_code
            AND attr.crn = crse.crn
           LEFT JOIN (SELECT DISTINCT sirasgn_term_code AS term_code,
                                     sirasgn_crn       AS crn
                       FROM saturn.sirasgn
                      WHERE sirasgn_asty_code = 'GSA') gsa
             ON gsa.term_code = crse.term_code
            AND gsa.crn = crse.crn
           LEFT JOIN (SELECT l.scrlevl_subj_code,
                            l.scrlevl_crse_numb,
                            l.scrlevl_eff_term,
                            CASE
                            WHEN COUNT(1) = 1
                                 AND MAX(l.scrlevl_levl_code) != 'CT' THEN
                             CASE
                             WHEN MAX(l.scrlevl_levl_code) IN ('UG', 'IN') THEN
                              'UG'
                             ELSE
                              'GR'
                             END
                            WHEN MAX(CASE
                                     WHEN l.scrlevl_levl_code IN ('JD', 'MD') THEN
                                      1
                                     END) IS NOT NULL THEN
                             'GR'
                            WHEN substr(l.scrlevl_crse_numb, 1, 1) < 5 THEN
                             'UG'
                            ELSE
                             'GR'
                            END AS course_level
                       FROM saturn.scrlevl l
                      WHERE l.scrlevl_levl_code NOT IN ('HS', 'K8', 'AC', 'PD')
                        AND l.scrlevl_eff_term = (SELECT MAX(l2.scrlevl_eff_term)
                                                    FROM saturn.scrlevl l2
                                                   WHERE l2.scrlevl_subj_code = l.scrlevl_subj_code
                                                     AND l2.scrlevl_crse_numb = l.scrlevl_crse_numb
                                                     AND l2.scrlevl_eff_term <= substr(rec.term_code, 1, 5) || '5')
                      GROUP BY l.scrlevl_subj_code,
                               l.scrlevl_crse_numb,
                               l.scrlevl_eff_term) levl
             ON levl.scrlevl_subj_code = ctlg.subj
            AND levl.scrlevl_crse_numb = ctlg.numb || ctlg.b_course
           LEFT JOIN (SELECT fcrf.szrfcrf_contractee_pidm AS faculty_pidm,
                            fcrf.szrfcrf_acyr AS acad_year,
                            fcrf.szrfcrf_contract_type AS faculty_contract_type,
                            fcrf.szrfcrf_req_hours AS faculty_contract_hours,
                            fcrf.szrfcrf_num_of_months AS contract_months,
                            fcrf.szrfcrf_from_date AS from_date,
                            fcrf.szrfcrf_effective_date AS contract_effective_date,
                            fcrf.szrfcrf_effective_to_date AS contract_effective_to_date,
                            fcrf.szrfcrf_to_date AS to_date,
                            fcrf.szrfcrf_id AS contract_id,
                            CASE
                            WHEN fcrf.szrfcrf_campus = 'DR' THEN
                             'D'
                            ELSE
                             fcrf.szrfcrf_campus
                            END AS faculty_contract_campus,
                            fcrf.szrfcrf_school AS contract_coll_code,
                            fcrf.szrfcrf_department AS contract_department,
                            r.zfrlist_char_04 AS faculty_contract
                                     , dense_rank() over (partition by fcrf.szrfcrf_contractee_pidm, fcrf.szrfcrf_acyr
                                                          order by fcrf.szrfcrf_effective_to_date desc, fcrf.szrfcrf_id desc, rownum desc) as ranking --shouldn't really be needed (just in case)
                      FROM zprovost.szrfcrf fcrf
                      JOIN saturn.stvterm tm
                        ON tm.stvterm_acyr_code = fcrf.szrfcrf_acyr
                       AND tm.stvterm_code = rec.term_code
                      LEFT JOIN zformdata.zfrlist r
                        ON r.zfrlist_list_code = 'FCRF_APEX_103_CONTRACT_RULE_MAP'
                       AND r.zfrlist_active_yn = 'Y'
                       AND fcrf.szrfcrf_contract_type = r.zfrlist_char_01
                       AND fcrf.szrfcrf_contract_rule = r.zfrlist_char_03
                     WHERE fcrf.szrfcrf_to_date = to_date('12/31/2099', 'mm/dd/yyyy')
                       AND fcrf.szrfcrf_contract_type NOT IN ('GA', 'CN') --not grad assistant or contact expert contracts (LUCOM)/LUOA contracts
                       AND fcrf.szrfcrf_contractee_pidm != '3248979' --tba
                       AND (fcrf.szrfcrf_effective_to_date IS NULL --contract did not end
                           OR fcrf.szrfcrf_effective_to_date >= tm.stvterm_start_date AND fcrf.szrfcrf_effective_date < tm.stvterm_end_date)) cntrct
            ON cntrct.faculty_pidm = crse.faculty_pidm
          LEFT JOIN faismgr.rorcrhr crhr
            ON crhr.rorcrhr_period = crse.term_code
           AND crhr.rorcrhr_levl_code = prle.smrprle_levl_code
          LEFT JOIN utl_d_aim.szrstfr_audit_gtt aud
            ON aud.pidm = crse.pidm
           AND aud.term_code = crse.term_code
           AND aud.crn = crse.crn
           AND aud.prog_code = prle.smrprle_program
         WHERE substr(crse.term_code, 1, 5) || '0' = rec.term_code
           AND crse.credit_hr > 0)
  LEFT JOIN saturn.stvcoll acol
    ON acol.stvcoll_code = CASE
       WHEN dcpa_requirement_category IN ('General Education', 'Major Foundational/Directed') THEN
        'GS'
       ELSE
        program_coll_code
       END
  LEFT JOIN saturn.stvdept adep
    ON adep.stvdept_code = CASE
       WHEN dcpa_requirement_category IN ('General Education', 'Major Foundational/Directed') THEN
        'GENS'
       ELSE
        program_dept_code
       END
 WHERE dcpa_ranking_within_programs = 1
   AND dcpa_ranking_across_programs = 1;
v_count       := SQL%ROWCOUNT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
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
v_msg     := substr(SQLERRM, 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
/*--------------------------------------------CHANGE LOG----------------------------------------
VERSION    DATE        USERNAME       UPDATES
---     10-11-2023  wgriffith2  -- Initial release; restored from previous deprecation
---     08-15-2025  CLREID2     -- Updated adjusted program group to pull program_degree_major_group
------------------------------------------------------------------------------------------------*/
END etl_aim_szrstfr_refresh;
procedure etl_aim_prerequisites_refresh (jobnumber number, processid varchar2, processname varchar2) IS
/*
Table: utl_d_aim.preq

Primary Keys: NONE!

Unique index: NONE!

Purpose:
- Tracking prereqs for all students that have been met

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
 v_cpu         NUMBER := 4; -- number of CPUs used for parallelization - do not exceed 20 CPUs [v_mod x --v_cpu] if running simultaneously
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_aim_prerequisites_refresh';
TYPE rt_preq IS RECORD(
pidm                     utl_d_aim.preq.pidm%TYPE,
term                     utl_d_aim.preq.term%TYPE,
crn                      utl_d_aim.preq.crn%TYPE,
course_preq_met          utl_d_aim.preq.course_preq_met%TYPE,
course_preq_met_w_enroll utl_d_aim.preq.course_preq_met_w_enroll%TYPE);
TYPE t_preq IS TABLE OF rt_preq;
l_preqs_met t_preq := t_preq();
CURSOR c_crses IS
SELECT /*+*/ pidm,
       term,
       crn,
       batch_id,
       batch_seq_num,
       batch_selection,
       batch_user,
       batch_reg_crn,
       batch_activity_date,
       --added logic to handle blank lines in the preq table that only return wrapping parenthesis
       listagg( case when lparen = '(' and rparen is null and preq_subj is null and preq_numb is null and preq_course is null then connector || lparen
                     when rparen = ')' and lparen is null and preq_subj is null and preq_numb is null and preq_course is null then rparen
                     else ' ' || connector || nvl(lparen, ' ') || '1=' || req_met || rparen
                 end ) within GROUP(ORDER BY seqno) AS cond,
       listagg(case when lparen = '(' and rparen is null and preq_subj is null and preq_numb is null and preq_course is null then connector || lparen
                    when rparen = ')' and lparen is null and preq_subj is null and preq_numb is null and preq_course is null then rparen
                    else ' ' || connector || nvl(lparen, ' ') || '1=' || req_met_w_enroll || rparen
               end ) within GROUP(ORDER BY seqno) AS cond_w_enroll
  FROM utl_d_aim.preq
 WHERE processed = 'N'
 GROUP BY pidm,
          term,
          crn,
          batch_id,
          batch_seq_num,
          batch_selection,
          batch_user,
          batch_reg_crn,
          batch_activity_date;
--  FETCH FIRST 10 rows ONLY;
CURSOR c_terms IS
SELECT DISTINCT crse.term_code
  FROM utl_d_aim.szrcrse crse
  JOIN (SELECT DISTINCT term_code,
                        dense_rank() over(ORDER BY term_code) rnk
          FROM zbtm.terms_by_group_v
          JOIN saturn.sobptrm ptrm
            ON ptrm.sobptrm_term_code = term_code
           AND ptrm.sobptrm_start_date + 14 >= SYSDATE
         WHERE group_code = 'STD'
           AND semester != 'WIN'
           AND SYSDATE <= end_date) term
    ON term.rnk <= 2 --return last [n] terms
   AND term.term_code = crse.term_code
   JOIN zsaturn.szrlevl l
  ON l.szrlevl_levl_code = crse.levl_code
   AND l.szrlevl_is_univ = 'Y'
   AND l.szrlevl_has_awardable_cred = 'Y'
 ORDER BY 1;
v_preq_met          NUMBER;
v_preq_met_w_enroll NUMBER;
v_log               NUMBER;
v_email_body        CLOB;
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
DELETE /*+*/ FROM utl_d_aim.preq
 WHERE preq.term = rec.term_code
   AND preq.batch_id IS NULL
   AND preq.batch_selection IS NULL;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'DELETE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
INSERT /*+*/ INTO utl_d_aim.preq
(pidm,
 luid,
 student,
 term,
 stu_campus,
 subj,
 numb,
 course,
 sect,
 crn,
 crse_campus,
 ptrm,
 ptrm_start,
 ptrm_end,
 reg_type,
 preq_type,
 seqno,
 preq_order,
 connector,
 lparen,
 preq_subj,
 preq_numb,
 preq_course,
 grde,
 min_points,
 rparen,
 concur_ind,
 ovr_subj,
 ovr_crse,
 ovr_activity,
 req_met,
 course_preq_met,
 req_met_w_enroll,
 course_preq_met_w_enroll,
 req_met_type,
 req_met_dtl,
 refresh_date,
 batch_id,
 batch_seq_num,
 batch_reg_crn,
 batch_user,
 batch_creator_id,
 batch_selection,
 batch_crn_matches,
 batch_error_message,
 batch_data_origin,
 batch_activity_date)
SELECT DISTINCT iden.spriden_pidm AS pidm,
                iden.spriden_id AS luid,
                iden.spriden_last_name || ', ' || iden.spriden_first_name AS student,
                sect.ssbsect_term_code AS term,
                stdn.sgbstdn_camp_code AS stu_campus,
                sect.ssbsect_subj_code AS subj,
                sect.ssbsect_crse_numb AS numb,
                sect.ssbsect_subj_code || sect.ssbsect_crse_numb AS course,
                sect.ssbsect_seq_numb AS sect,
                sect.ssbsect_crn AS crn,
                sect.ssbsect_camp_code AS crse_campus,
                sect.ssbsect_ptrm_code AS ptrm,
                sect.ssbsect_ptrm_start_date AS ptrm_start,
                sect.ssbsect_ptrm_end_date AS ptrm_end,
                stcr.sfrstcr_rsts_code AS reg_type,
                nvl2(ssrrtst_tesc_code, 'TEST', 'CRSE') AS preq_type,
                rtst.ssrrtst_seqno AS seqno,
                dense_rank() over(PARTITION BY iden.spriden_pidm, sect.ssbsect_term_code, sect.ssbsect_crn ORDER BY rtst.ssrrtst_seqno) AS preq_order,
                decode(rtst.ssrrtst_connector, 'A', 'And', 'O', 'Or', NULL) AS connector,
                rtst.ssrrtst_lparen AS lparen,
                rtst.ssrrtst_subj_code_preq AS preq_subj,
                rtst.ssrrtst_crse_numb_preq AS preq_numb,
                coalesce(rtst.ssrrtst_subj_code_preq || rtst.ssrrtst_crse_numb_preq, rtst.ssrrtst_tesc_code) AS preq_course,
                nvl(g.grde, rtst.ssrrtst_test_score) AS grde,
                coalesce(g.points, CASE
                          WHEN regexp_like(rtst.ssrrtst_test_score, '^\d+\.?\d?') THEN
                           to_number(rtst.ssrrtst_test_score)
                          END, 0) AS min_points,
                rtst.ssrrtst_rparen AS rparen,
                nvl(rtst.ssrrtst_concurrency_ind, '(None)') AS concur_ind,
                sfrsrpo_subj_code AS ovr_subj,
                sfrsrpo_crse_numb AS ovr_crse,
                MAX(sfrsrpo_activity_date) over(PARTITION BY sfrstcr_pidm, ssbsect_term_code, ssbsect_subj_code || ssbsect_crse_numb) AS ovr_activity,
                CASE
                WHEN sfrsrpo_subj_code IS NOT NULL THEN
                 1
                ELSE
                 0
                END AS req_met,
                1 AS course_preq_met,
                CASE
                WHEN sfrsrpo_subj_code IS NOT NULL THEN
                 1
                ELSE
                 0
                END AS req_met_w_enroll,
                1 AS course_preq_met_w_enroll,
                CASE
                WHEN sfrsrpo_subj_code IS NOT NULL THEN
                 'SFASRPO Override'
                END AS req_met_type,
                NULL AS req_met_dtl,
                SYSDATE AS refresh_date,
                NULL AS batch_id,
                NULL AS batch_seq_num,
                '' AS batch_reg_crn,
                '' AS batch_user,
                '' AS batch_creator_id,
                '' AS batch_selection,
                '' AS batch_crn_matches,
                '' AS batch_error_message,
                '' AS batch_data_origin,
                NULL AS batch_activity_date
  FROM saturn.spriden iden
  JOIN saturn.sfrstcr stcr
    ON stcr.sfrstcr_pidm = iden.spriden_pidm
   AND stcr.sfrstcr_term_code = rec.term_code
  JOIN saturn.stvrsts rsts
    ON rsts.stvrsts_code = stcr.sfrstcr_rsts_code
   AND rsts.stvrsts_incl_sect_enrl = 'Y'
   AND rsts.stvrsts_withdraw_ind = 'N'
  JOIN saturn.sgbstdn stdn
    ON stdn.sgbstdn_pidm = iden.spriden_pidm
   AND stdn.sgbstdn_term_code_eff = (SELECT MAX(stdn2.sgbstdn_term_code_eff)
                                       FROM saturn.sgbstdn stdn2
                                      WHERE stdn2.sgbstdn_pidm = stdn.sgbstdn_pidm
                                        AND stdn2.sgbstdn_term_code_eff <= rec.term_code)
  JOIN saturn.ssbsect sect
    ON sect.ssbsect_term_code = stcr.sfrstcr_term_code
   AND sect.ssbsect_crn = stcr.sfrstcr_crn
   AND sect.ssbsect_ptrm_start_date + 14 >= SYSDATE
  JOIN saturn.ssrrtst rtst
    ON rtst.ssrrtst_term_code = sect.ssbsect_term_code
   AND rtst.ssrrtst_crn = sect.ssbsect_crn
  LEFT JOIN (SELECT grde.shrgrde_levl_code AS levl,
                    grde.shrgrde_code AS grde,
                    nvl(decode(grde.shrgrde_code, 'P', 0.001, grde.shrgrde_quality_points), 0) AS points
               FROM saturn.shrgrde grde
              WHERE grde.shrgrde_term_code_effective = (SELECT MAX(grde2.shrgrde_term_code_effective)
                                                          FROM saturn.shrgrde grde2
                                                         WHERE grde2.shrgrde_levl_code = grde.shrgrde_levl_code
                                                           AND grde2.shrgrde_code = grde.shrgrde_code
                                                           AND grde2.shrgrde_term_code_effective <= rec.term_code)) g
    ON g.levl = rtst.ssrrtst_levl_code
   AND g.grde = rtst.ssrrtst_min_grde
  LEFT JOIN saturn.sfrsrpo srpo
    ON srpo.sfrsrpo_pidm = iden.spriden_pidm
   AND srpo.sfrsrpo_term_code = stcr.sfrstcr_term_code
   AND srpo.sfrsrpo_rovr_code = 'PRE-REQ'
   AND (srpo.sfrsrpo_crn = stcr.sfrstcr_crn OR srpo.sfrsrpo_crn IS NULL AND srpo.sfrsrpo_subj_code = sect.ssbsect_subj_code AND srpo.sfrsrpo_crse_numb = sect.ssbsect_crse_numb)
 WHERE iden.spriden_change_ind IS NULL;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
INSERT /*+*/ INTO utl_d_aim.preq
(pidm,
 luid,
 student,
 term,
 stu_campus,
 subj,
 numb,
 course,
 sect,
 crn,
 crse_campus,
 ptrm,
 ptrm_start,
 ptrm_end,
 reg_type,
 preq_type,
 seqno,
 preq_order,
 connector,
 lparen,
 preq_subj,
 preq_numb,
 preq_course,
 grde,
 min_points,
 rparen,
 concur_ind,
 ovr_subj,
 ovr_crse,
 ovr_activity,
 req_met,
 course_preq_met,
 req_met_w_enroll,
 course_preq_met_w_enroll,
 req_met_type,
 req_met_dtl,
 refresh_date,
 batch_id,
 batch_seq_num,
 batch_reg_crn,
 batch_user,
 batch_creator_id,
 batch_selection,
 batch_crn_matches,
 batch_error_message,
 batch_data_origin,
 batch_activity_date)
SELECT DISTINCT iden.spriden_pidm AS pidm,
                iden.spriden_id AS luid,
                iden.spriden_last_name || ', ' || iden.spriden_first_name AS student,
                sect.ssbsect_term_code AS term,
                stdn.sgbstdn_camp_code AS stu_campus,
                sect.ssbsect_subj_code AS subj,
                sect.ssbsect_crse_numb AS numb,
                sect.ssbsect_subj_code || sect.ssbsect_crse_numb AS course,
                sect.ssbsect_seq_numb AS sect,
                sect.ssbsect_crn AS crn,
                sect.ssbsect_camp_code AS crse_campus,
                sect.ssbsect_ptrm_code AS ptrm,
                sect.ssbsect_ptrm_start_date AS ptrm_start,
                sect.ssbsect_ptrm_end_date AS ptrm_end,
                '' AS reg_type,
                nvl2(ssrrtst_tesc_code, 'TEST', 'CRSE') AS preq_type,
                rtst.ssrrtst_seqno AS seqno,
                dense_rank() over(PARTITION BY iden.spriden_pidm, sect.ssbsect_term_code, sect.ssbsect_crn ORDER BY rtst.ssrrtst_seqno) AS preq_order,
                decode(rtst.ssrrtst_connector, 'A', 'And', 'O', 'Or', NULL) AS connector,
                rtst.ssrrtst_lparen AS lparen,
                rtst.ssrrtst_subj_code_preq AS preq_subj,
                rtst.ssrrtst_crse_numb_preq AS preq_numb,
                coalesce(rtst.ssrrtst_subj_code_preq || rtst.ssrrtst_crse_numb_preq, rtst.ssrrtst_tesc_code) AS preq_course,
                nvl(g.grde, rtst.ssrrtst_test_score) AS grde,
                coalesce(g.points, CASE
                          WHEN regexp_like(rtst.ssrrtst_test_score, '^\d+\.?\d?') THEN
                           to_number(rtst.ssrrtst_test_score)
                          END, 0) AS min_points,
                rtst.ssrrtst_rparen AS rparen,
                nvl(rtst.ssrrtst_concurrency_ind, '(None)') AS concur_ind,
                sfrsrpo_subj_code AS ovr_subj,
                sfrsrpo_crse_numb AS ovr_crse,
                MAX(sfrsrpo_activity_date) over(PARTITION BY bat.batch_id, bat.seq_numb) AS ovr_activity,
                CASE
                WHEN sfrsrpo_subj_code IS NOT NULL THEN
                 1
                ELSE
                 0
                END AS req_met,
                1 AS course_preq_met,
                CASE
                WHEN sfrsrpo_subj_code IS NOT NULL THEN
                 1
                ELSE
                 0
                END AS req_met_w_enroll,
                1 AS course_preq_met_w_enroll,
                CASE
                WHEN sfrsrpo_subj_code IS NOT NULL THEN
                 'SFASRPO Override'
                END AS req_met_type,
                NULL AS req_met_dtl,
                SYSDATE AS refresh_date,
                bat.batch_id AS batch_id,
                bat.seq_numb AS batch_seq_num,
                to_char(bat.crn) AS batch_reg_crn,
                bat.username AS batch_user,
                bat.creator AS batch_creator_id,
                bat.selection AS batch_selection,
                bat.error_crn_matches AS batch_crn_matches,
                bat.error_segment AS batch_error_message,
                bat.data_origin AS batch_data_origin,
                bat.activity_date AS batch_activity_date
  FROM saturn.spriden iden
  JOIN (SELECT REPLACE(regexp_substr(s.szrrstu_error_msg, 'CRN [0-9]+', 1, LEVEL), 'CRN ') AS error_crn,
               TRIM(regexp_substr(s.szrrstu_error_msg, '.*?\.', 1, LEVEL)) AS error_segment,
               LEVEL AS error_nbr,
               s.szrrstu_batch_id AS batch_id,
               s.szrrstu_seq_numb AS seq_numb,
               s.szrrstu_pidm AS pidm,
               s.szrrstu_term_code AS term_code,
               s.szrrstu_crn AS crn,
               s.szrrstu_user AS username,
               s.szrrstu_creator_id AS creator,
               s.szrrstu_selection AS selection,
               s.szrrstu_data_origin AS data_origin,
               s.szrrstu_activity_date AS activity_date,
               CASE
               WHEN s.szrrstu_crn = REPLACE(regexp_substr(s.szrrstu_error_msg, 'CRN [0-9]+', 1, LEVEL), 'CRN ') THEN
                'Y'
               ELSE
                'N'
               END AS error_crn_matches
          FROM (SELECT /*+ materialized*/
                 szrrstu.szrrstu_batch_id,
                 szrrstu.szrrstu_seq_numb,
                 szrrstu.szrrstu_pidm,
                 szrrstu.szrrstu_term_code,
                 szrrstu.szrrstu_crn,
                 szrrstu.szrrstu_user,
                 szrrstu.szrrstu_creator_id,
                 szrrstu.szrrstu_selection,
                 szrrstu.szrrstu_data_origin,
                 szrrstu.szrrstu_activity_date,
                 szrrstu.szrrstu_error_msg
                  FROM zsaturn.szrrstu
                 WHERE szrrstu.szrrstu_success_ind = 'N'
                   AND lower(szrrstu.szrrstu_error_msg) LIKE '%prerequisite%'
                   AND NOT EXISTS (SELECT 1
                          FROM utl_d_aim.preq
                         WHERE preq.batch_id = szrrstu.szrrstu_batch_id
                           AND preq.batch_seq_num = szrrstu.szrrstu_seq_numb)) s
         WHERE lower(regexp_substr(s.szrrstu_error_msg, '.*?\.', 1, LEVEL)) LIKE '%prerequisite%'
        CONNECT BY PRIOR s.szrrstu_pidm = s.szrrstu_pidm
               AND PRIOR s.szrrstu_term_code = s.szrrstu_term_code
               AND PRIOR s.szrrstu_crn = s.szrrstu_crn
               AND PRIOR dbms_random.value IS NOT NULL
               AND regexp_substr(s.szrrstu_error_msg, 'CRN', 1, LEVEL) IS NOT NULL) bat
    ON bat.pidm = iden.spriden_pidm
  JOIN saturn.sgbstdn stdn
    ON stdn.sgbstdn_pidm = iden.spriden_pidm
   AND stdn.sgbstdn_term_code_eff = (SELECT MAX(stdn2.sgbstdn_term_code_eff)
                                       FROM saturn.sgbstdn stdn2
                                      WHERE stdn2.sgbstdn_pidm = stdn.sgbstdn_pidm
                                        AND stdn2.sgbstdn_term_code_eff <= bat.term_code)
  JOIN saturn.ssbsect sect
    ON sect.ssbsect_term_code = bat.term_code
   AND sect.ssbsect_crn = bat.error_crn
  JOIN saturn.ssrrtst rtst
    ON rtst.ssrrtst_term_code = bat.term_code
   AND rtst.ssrrtst_crn = bat.error_crn
  LEFT JOIN (SELECT grde.shrgrde_levl_code AS levl,
                    grde.shrgrde_code AS grde,
                    nvl(decode(grde.shrgrde_code, 'P', 0.001, grde.shrgrde_quality_points), 0) AS points
               FROM saturn.shrgrde grde
              WHERE grde.shrgrde_term_code_effective = (SELECT MAX(grde2.shrgrde_term_code_effective)
                                                          FROM saturn.shrgrde grde2
                                                         WHERE grde2.shrgrde_levl_code = grde.shrgrde_levl_code
                                                           AND grde2.shrgrde_code = grde.shrgrde_code
                                                           AND grde2.shrgrde_term_code_effective <= rec.term_code)) g
    ON g.levl = rtst.ssrrtst_levl_code
   AND g.grde = rtst.ssrrtst_min_grde
  LEFT JOIN saturn.sfrsrpo srpo
    ON srpo.sfrsrpo_pidm = iden.spriden_pidm
   AND srpo.sfrsrpo_term_code = bat.term_code
   AND srpo.sfrsrpo_rovr_code = 'PRE-REQ'
   AND (srpo.sfrsrpo_crn = bat.crn OR srpo.sfrsrpo_crn IS NULL AND srpo.sfrsrpo_subj_code = sect.ssbsect_subj_code AND srpo.sfrsrpo_crse_numb = sect.ssbsect_crse_numb)
 WHERE iden.spriden_change_ind IS NULL;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
INSERT /*+*/ INTO utl_d_aim.preq
(pidm,
 luid,
 student,
 term,
 stu_campus,
 subj,
 numb,
 course,
 sect,
 crn,
 crse_campus,
 ptrm,
 ptrm_start,
 ptrm_end,
 reg_type,
 preq_type,
 seqno,
 preq_order,
 connector,
 lparen,
 preq_subj,
 preq_numb,
 preq_course,
 grde,
 min_points,
 rparen,
 concur_ind,
 ovr_subj,
 ovr_crse,
 ovr_activity,
 req_met,
 course_preq_met,
 req_met_w_enroll,
 course_preq_met_w_enroll,
 req_met_type,
 req_met_dtl,
 refresh_date,
 batch_id,
 batch_seq_num,
 batch_reg_crn,
 batch_user,
 batch_creator_id,
 batch_selection,
 batch_crn_matches,
 batch_error_message,
 batch_data_origin,
 batch_activity_date)
SELECT DISTINCT iden.spriden_pidm AS pidm,
                iden.spriden_id AS luid,
                iden.spriden_last_name || ', ' || iden.spriden_first_name AS student,
                sect.ssbsect_term_code AS term,
                stdn.sgbstdn_camp_code AS stu_campus,
                sect.ssbsect_subj_code AS subj,
                sect.ssbsect_crse_numb AS numb,
                sect.ssbsect_subj_code || sect.ssbsect_crse_numb AS course,
                sect.ssbsect_seq_numb AS sect,
                sect.ssbsect_crn AS crn,
                sect.ssbsect_camp_code AS crse_campus,
                sect.ssbsect_ptrm_code AS ptrm,
                sect.ssbsect_ptrm_start_date AS ptrm_start,
                sect.ssbsect_ptrm_end_date AS ptrm_end,
                '' AS reg_type,
                nvl2(ssrrtst_tesc_code, 'TEST', 'CRSE') AS preq_type,
                rtst.ssrrtst_seqno AS seqno,
                dense_rank() over(PARTITION BY iden.spriden_pidm, sect.ssbsect_term_code, sect.ssbsect_crn ORDER BY rtst.ssrrtst_seqno) AS preq_order,
                decode(rtst.ssrrtst_connector, 'A', 'And', 'O', 'Or', NULL) AS connector,
                rtst.ssrrtst_lparen AS lparen,
                rtst.ssrrtst_subj_code_preq AS preq_subj,
                rtst.ssrrtst_crse_numb_preq AS preq_numb,
                coalesce(rtst.ssrrtst_subj_code_preq || rtst.ssrrtst_crse_numb_preq, rtst.ssrrtst_tesc_code) AS preq_course,
                nvl(g.grde, rtst.ssrrtst_test_score) AS grde,
                coalesce(g.points, CASE
                          WHEN regexp_like(rtst.ssrrtst_test_score, '^\d+\.?\d?') THEN
                           to_number(rtst.ssrrtst_test_score)
                          END, 0) AS min_points,
                rtst.ssrrtst_rparen AS rparen,
                nvl(rtst.ssrrtst_concurrency_ind, '(None)') AS concur_ind,
                sfrsrpo_subj_code AS ovr_subj,
                sfrsrpo_crse_numb AS ovr_crse,
                MAX(sfrsrpo_activity_date) over(PARTITION BY bat.term_code, bat.error_crn, bat.input_crn, bat.selection, bat.username, bat.activity_date, bat.pidm) AS ovr_activity,
                CASE
                WHEN sfrsrpo_subj_code IS NOT NULL THEN
                 1
                ELSE
                 0
                END AS req_met,
                1 AS course_preq_met,
                CASE
                WHEN sfrsrpo_subj_code IS NOT NULL THEN
                 1
                ELSE
                 0
                END AS req_met_w_enroll,
                1 AS course_preq_met_w_enroll,
                CASE
                WHEN sfrsrpo_subj_code IS NOT NULL THEN
                 'SFASRPO Override'
                END AS req_met_type,
                NULL AS req_met_dtl,
                SYSDATE AS refresh_date,
                NULL AS batch_id,
                NULL AS batch_seq_num,
                bat.input_crn AS batch_reg_crn,
                bat.username AS batch_user,
                NULL AS batch_creator_id,
                bat.selection AS batch_selection,
                CASE
                WHEN bat.error_crn != input_crn THEN
                 'N'
                ELSE
                 'Y'
                END AS batch_crn_matches,
                NULL AS batch_error_message,
                'PPRD' AS batch_data_origin,
                to_date(bat.activity_date, 'YYYYMMDDHH24MI') AS batch_activity_date
  FROM saturn.spriden iden
  JOIN (SELECT zgeneral.get_token(glbextr_key, 1) AS selection,
               zgeneral.get_token(glbextr_key, 2) AS username,
               zgeneral.get_token(glbextr_key, 3) AS activity_date,
               zgeneral.get_token(glbextr_key, 4) AS pidm,
               zgeneral.get_token(glbextr_key, 5) AS term_code,
               zgeneral.get_token(glbextr_key, 6) AS input_crn,
               zgeneral.get_token(glbextr_key, 7) AS error_crn
          FROM general.glbextr extr
         WHERE extr.glbextr_application = 'STUDENT'
           AND extr.glbextr_selection = 'PPRD_PREREQ_CHECK'
           AND NOT EXISTS (SELECT 1
                  FROM utl_d_aim.preq
                 WHERE preq.batch_selection = zgeneral.get_token(glbextr_key, 1)
                   AND preq.batch_user = zgeneral.get_token(glbextr_key, 2)
                   AND to_char(preq.batch_activity_date, 'YYYYMMDDHH24MI') = zgeneral.get_token(glbextr_key, 3)
                   AND preq.pidm = zgeneral.get_token(glbextr_key, 4)
                   AND preq.term = zgeneral.get_token(glbextr_key, 5)
                   AND preq.batch_reg_crn = zgeneral.get_token(glbextr_key, 6)
                   AND preq.crn = zgeneral.get_token(glbextr_key, 7)
                   AND preq.batch_data_origin = 'PPRD')) bat
    ON bat.pidm = iden.spriden_pidm
  JOIN saturn.sgbstdn stdn
    ON stdn.sgbstdn_pidm = iden.spriden_pidm
   AND stdn.sgbstdn_term_code_eff = (SELECT MAX(stdn2.sgbstdn_term_code_eff)
                                       FROM saturn.sgbstdn stdn2
                                      WHERE stdn2.sgbstdn_pidm = stdn.sgbstdn_pidm
                                        AND stdn2.sgbstdn_term_code_eff <= bat.term_code)
  JOIN saturn.ssbsect sect
    ON sect.ssbsect_term_code = bat.term_code
   AND sect.ssbsect_crn = bat.error_crn
  JOIN saturn.ssrrtst rtst
    ON rtst.ssrrtst_term_code = bat.term_code
   AND rtst.ssrrtst_crn = bat.error_crn
  LEFT JOIN (SELECT grde.shrgrde_levl_code AS levl,
                    grde.shrgrde_code AS grde,
                    nvl(decode(grde.shrgrde_code, 'P', 0.001, grde.shrgrde_quality_points), 0) AS points
               FROM saturn.shrgrde grde
              WHERE grde.shrgrde_term_code_effective = (SELECT MAX(grde2.shrgrde_term_code_effective)
                                                          FROM saturn.shrgrde grde2
                                                         WHERE grde2.shrgrde_levl_code = grde.shrgrde_levl_code
                                                           AND grde2.shrgrde_code = grde.shrgrde_code
                                                           AND grde2.shrgrde_term_code_effective <= rec.term_code)) g
    ON g.levl = rtst.ssrrtst_levl_code
   AND g.grde = rtst.ssrrtst_min_grde
  LEFT JOIN saturn.sfrsrpo srpo
    ON srpo.sfrsrpo_pidm = iden.spriden_pidm
   AND srpo.sfrsrpo_term_code = bat.term_code
   AND srpo.sfrsrpo_rovr_code = 'PRE-REQ'
   AND (srpo.sfrsrpo_crn = bat.error_crn OR srpo.sfrsrpo_crn IS NULL AND srpo.sfrsrpo_subj_code = sect.ssbsect_subj_code AND srpo.sfrsrpo_crse_numb = sect.ssbsect_crse_numb)
 WHERE iden.spriden_change_ind IS NULL;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
utl_d_aim.truncate_table(v_table_name => 'preq_crse_hist');
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'TRUNCATE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
INSERT /*+*/ INTO utl_d_aim.preq_crse_hist
(pidm,
 term,
 ptrm,
 ptrm_start,
 ptrm_end,
 subj,
 numb,
 course,
 test_code,
 grde,
 points,
 req_met_type,
 req_met_dtl)
WITH base AS
 (SELECT DISTINCT pidm,
                  term
    FROM utl_d_aim.preq
   WHERE term = rec.term_code),
csub AS
 (SELECT /*+ materialize*/
   raft.*,
   LEVEL,
   wfac.zgrwfac_activity_id,
   wfqu.zgrwfqu_que_type,
   wfqu.zgrwfqu_name,
   wfqu.zgrwfqu_display_name,
   wfqu.zgrwfqu_assignment_dcmt_code,
   wfds.zgrwfds_desc,
   wfds.zgrwfds_accept_reject
                               , rank() over (partition by raft.submission_id
                                              order by case when wfqu.zgrwfqu_que_type = 'A' then 0 else 1 end
                                                     , case when wfqu.zgrwfqu_assignment_dcmt_code != 'INITIATOR' then 0 else 1 end --specific to this wf data
                                                     , level desc) rnk
    FROM (SELECT subm.szbsubm_id AS submission_id,
                 subm.szbsubm_pidm AS pidm,
                 subm.szbsubm_wf_proc_id AS wf_proc_id,
                 MAX(CASE
                     WHEN qest.szrqest_orig_qest_id = 9781
                          OR qest.szrqest_text LIKE '<!--REQ_CRSE_1-->%' THEN
                      regexp_substr(esan.szresan_short_ans, '^[A-Za-z]{4}_[0-9Xx]{3}')
                     END) AS req_crse_1,
                 MAX(CASE
                     WHEN qest.szrqest_orig_qest_id = 14245
                          OR qest.szrqest_text LIKE '<!--REQ_CRSE_2-->%' THEN
                      regexp_substr(esan.szresan_short_ans, '^[A-Za-z]{4}_[0-9Xx]{3}')
                     END) AS req_crse_2,
                 MAX(CASE
                     WHEN qest.szrqest_orig_qest_id = 9881
                          OR qest.szrqest_text LIKE '<!--#CSC1:#-->%' THEN
                      nvl(esan.szresan_short_ans, dbms_lob.substr(esan.szresan_essay, 100, 1))
                     END) AS rep_crse_1,
                 MAX(CASE
                     WHEN qest.szrqest_orig_qest_id = 14242
                          OR qest.szrqest_text LIKE '<!--#FCRC1:#-->%' THEN
                      nvl(esan.szresan_short_ans, dbms_lob.substr(esan.szresan_essay, 100, 1))
                     END) AS rep_crse_2
            FROM zraft.szbsubm subm
            JOIN zraft.szresan esan
              ON esan.szresan_szbsubm_id = subm.szbsubm_id
             AND esan.szresan_to_date IS NULL
            JOIN base
              ON base.pidm = szbsubm_pidm
            JOIN zraft.szrqest qest
              ON qest.szrqest_id = esan.szresan_question_id
            JOIN zgeneral.zgrwfac wfac
              ON wfac.zgrwfac_proc_id = subm.szbsubm_wf_proc_id
            JOIN zgeneral.zgrwfqu wfqu
              ON wfqu.zgrwfqu_que_id = wfac.zgrwfac_que_id
             AND wfqu.zgrwfqu_que_type = 'X'
           WHERE subm.szbsubm_szrfrms_id = 1081
             AND (qest.szrqest_orig_qest_id IN (9781, 14245, 9881, 14242) OR qest.szrqest_text LIKE '<!--REQ_CRSE_1-->%' OR qest.szrqest_text LIKE '<!--REQ_CRSE_2-->%' OR qest.szrqest_text LIKE '<!--#CSC1:#-->%' OR
                 qest.szrqest_text LIKE '<!--#FCRC1:#-->%')
             AND esan.szresan_to_date IS NULL
           GROUP BY subm.szbsubm_id,
                    subm.szbsubm_pidm,
                    subm.szbsubm_wf_proc_id
          HAVING MAX(CASE
          WHEN qest.szrqest_orig_qest_id = 9781
               OR qest.szrqest_text LIKE '<!--REQ_CRSE_1-->%' THEN
           regexp_substr(esan.szresan_short_ans, '^[A-Za-z]{4}_[0-9Xx]{3}')
          END) IS NOT NULL) raft
    JOIN zgeneral.zgrwfac wfac
      ON wfac.zgrwfac_proc_id = raft.wf_proc_id
    JOIN zgeneral.zgrwfqu wfqu
      ON wfqu.zgrwfqu_que_id = wfac.zgrwfac_que_id
    JOIN zgeneral.zgrwfds wfds
      ON wfds.zgrwfds_que_id = wfac.zgrwfac_que_id
     AND wfds.zgrwfds_disposition = wfac.zgrwfac_disposition
   START WITH wfac.zgrwfac_prev_activity_id IS NULL
  CONNECT BY PRIOR wfac.zgrwfac_activity_id = wfac.zgrwfac_prev_activity_id)
--graded
SELECT base.pidm,
       tckn.shrtckn_term_code AS term,
       NULL AS ptrm,
       NULL AS ptrm_start,
       NULL AS ptrm_end,
       tckn.shrtckn_subj_code AS subj,
       tckn.shrtckn_crse_numb AS numb,
       tckn.shrtckn_subj_code || tckn.shrtckn_crse_numb AS course,
       NULL AS test_code,
       grde.shrgrde_code AS grde,
       decode(grde.shrgrde_code, 'P', 4, 'I', NULL, nvl(grde.shrgrde_quality_points, 0)) AS points,
       decode(grde.shrgrde_code, 'P', 'Enrolled - no grade', 'Graded') AS req_met_type,
--        decode(grde.shrgrde_code, 'P', 'Enrolled - Prior P', 'Graded') AS req_met_type, -- added 20240126 wgriffith2
       'Course: ' || tckn.shrtckn_subj_code || tckn.shrtckn_crse_numb || ' Term: ' || tckn.shrtckn_term_code || ' Grade: ' || grde.shrgrde_code AS req_met_dtl
  FROM base
  JOIN saturn.shrtckn tckn
    ON tckn.shrtckn_pidm = base.pidm
  JOIN saturn.shrtckg tckg
    ON tckg.shrtckg_pidm = tckn.shrtckn_pidm
   AND tckg.shrtckg_term_code = tckn.shrtckn_term_code
   AND tckg.shrtckg_tckn_seq_no = tckn.shrtckn_seq_no
   AND tckg.shrtckg_seq_no = (SELECT MAX(tckg2.shrtckg_seq_no)
                                FROM saturn.shrtckg tckg2
                               WHERE tckg2.shrtckg_pidm = tckg.shrtckg_pidm
                                 AND tckg2.shrtckg_term_code = tckg.shrtckg_term_code
                                 AND tckg2.shrtckg_tckn_seq_no = tckg.shrtckg_tckn_seq_no)
  JOIN saturn.shrtckl tckl
    ON tckl.shrtckl_pidm = tckn.shrtckn_pidm
   AND tckl.shrtckl_term_code = tckn.shrtckn_term_code
   AND tckl.shrtckl_tckn_seq_no = tckn.shrtckn_seq_no
   AND tckl.shrtckl_primary_levl_ind = 'Y'
  JOIN saturn.shrgrde grde
    ON grde.shrgrde_code = tckg.shrtckg_grde_code_final
   AND grde.shrgrde_levl_code = tckl.shrtckl_levl_code
   AND grde.shrgrde_term_code_effective = (SELECT MAX(grde2.shrgrde_term_code_effective)
                                             FROM saturn.shrgrde grde2
                                            WHERE grde2.shrgrde_levl_code = grde.shrgrde_levl_code
                                              AND grde2.shrgrde_code = grde.shrgrde_code
                                              AND grde2.shrgrde_term_code_effective <= rec.term_code)
UNION ALL
--transfer
SELECT base.pidm,
       trce.shrtrce_term_code_eff AS term,
       NULL AS ptrm,
       NULL AS ptrm_start,
       NULL AS ptrm_end,
       trce.shrtrce_subj_code AS subj,
       trce.shrtrce_crse_numb AS numb,
       trce.shrtrce_subj_code || trce.shrtrce_crse_numb AS course,
       NULL AS test_code,
       grde.shrgrde_code AS grde,
       grde.shrgrde_numeric_value AS points,
       'Transfer' AS req_met_type,
       'Course: ' || trce.shrtrce_subj_code || trce.shrtrce_crse_numb || ' Term: ' || trce.shrtrce_term_code_eff || ' SBGI: ' || trit.shrtrit_sbgi_code AS req_met_dtl
  FROM base
  JOIN saturn.shrtrce trce
    ON trce.shrtrce_pidm = base.pidm
  JOIN saturn.shrtrcr trcr
    ON trcr.shrtrcr_pidm = trce.shrtrce_pidm
   AND trcr.shrtrcr_seq_no = trce.shrtrce_trcr_seq_no
   AND trcr.shrtrcr_tram_seq_no = trce.shrtrce_tram_seq_no
   AND trcr.shrtrcr_trit_seq_no = trce.shrtrce_trit_seq_no
  JOIN saturn.shrtram tram
    ON tram.shrtram_pidm = trce.shrtrce_pidm
   AND tram.shrtram_seq_no = trce.shrtrce_tram_seq_no
   AND tram.shrtram_trit_seq_no = trce.shrtrce_trit_seq_no
  JOIN saturn.shrtrit trit
    ON trit.shrtrit_pidm = trce.shrtrce_pidm
   AND trit.shrtrit_seq_no = trce.shrtrce_trit_seq_no
  JOIN saturn.shrgrde grde
    ON grde.shrgrde_code = trce.shrtrce_grde_code
   AND grde.shrgrde_levl_code = trce.shrtrce_levl_code
   AND grde.shrgrde_term_code_effective = (SELECT MAX(grde2.shrgrde_term_code_effective)
                                             FROM saturn.shrgrde grde2
                                            WHERE grde2.shrgrde_levl_code = grde.shrgrde_levl_code
                                              AND grde2.shrgrde_code = grde.shrgrde_code
                                              AND grde2.shrgrde_term_code_effective <= rec.term_code)
UNION ALL
--test
SELECT base.pidm,
       NULL AS term,
       NULL AS ptrm,
       NULL AS ptrm_start,
       NULL AS ptrm_end,
       NULL AS subj,
       NULL AS numb,
       NULL AS crse,
       tst.sortest_tesc_code AS test_code,
       tst.sortest_test_score AS grde, --stores score here if there are non-numeric scores
       CASE
       WHEN regexp_like(tst.sortest_test_score, '^\d+(\.\d+)?$') THEN
        to_number(tst.sortest_test_score)
       ELSE
        NULL -- or 0, or any default numeric value you prefer
       END AS points,
       'Test' AS req_met_type,
       'Test: ' || tst.sortest_tesc_code || ' Score: ' || tst.sortest_test_score AS req_met_dtl
  FROM base
  JOIN saturn.sortest tst
    ON tst.sortest_pidm = base.pidm
UNION ALL
--enrolled, no grade
SELECT base.pidm,
       stcr.sfrstcr_term_code AS term,
       sect.ssbsect_ptrm_code AS ptrm,
       sect.ssbsect_ptrm_start_date AS ptrm_start,
       sect.ssbsect_ptrm_end_date AS ptrm_end,
       sect.ssbsect_subj_code AS subj,
       sect.ssbsect_crse_numb AS numb,
       sect.ssbsect_subj_code || sect.ssbsect_crse_numb AS course,
       NULL AS test_code,
       'IP' AS grde,
       NULL AS points,
       'Enrolled - no grade' AS req_met_type,
       'Course: ' || sect.ssbsect_subj_code || sect.ssbsect_crse_numb || ' Term: ' || stcr.sfrstcr_term_code || '_' || substr(stcr.sfrstcr_ptrm_code, -1) AS req_met_dtl
  FROM base
  JOIN saturn.sfrstcr stcr
    ON stcr.sfrstcr_pidm = base.pidm
   AND stcr.sfrstcr_term_code <= base.term
   AND stcr.sfrstcr_grde_code IS NULL --grade was not posted
  JOIN saturn.stvrsts rsts
    ON rsts.stvrsts_code = stcr.sfrstcr_rsts_code
   AND rsts.stvrsts_incl_assess = 'Y'
   AND rsts.stvrsts_withdraw_ind = 'N'
  JOIN saturn.ssbsect sect
    ON sect.ssbsect_term_code = stcr.sfrstcr_term_code
   AND sect.ssbsect_crn = stcr.sfrstcr_crn
--course sub
UNION ALL
SELECT DISTINCT pidm,
                term,
                ptrm,
                ptrm_start,
                ptrm_end,
                subj,
                numb,
                course,
                test_code,
                grde,
                points,
                req_met_type,
                req_met_dtl
  FROM (SELECT csub.pidm,
               '000000' AS term,
               NULL AS ptrm,
               NULL AS ptrm_start,
               NULL AS ptrm_end,
               substr(csub.req_crse_1, 1, instr(csub.req_crse_1, '_') - 1) AS subj,
               substr(csub.req_crse_1, instr(csub.req_crse_1, '_') + 1) AS numb,
               REPLACE(csub.req_crse_1, '_') AS course,
               NULL AS test_code,
               g.grde,
               g.points,
               'Course Sub' AS req_met_type,
               '(Submission ' || csub.submission_id || ') ' || regexp_replace(csub.rep_crse_1 || '; ' || csub.rep_crse_2, '(^; )|(; $)') AS req_met_dtl,
               rank() over(PARTITION BY csub.pidm, csub.req_crse_1 ORDER BY g.points DESC, rownum) AS rnk
          FROM base
          JOIN csub
            ON base.pidm = csub.pidm
           AND csub.req_crse_1 IS NOT NULL
          LEFT JOIN (SELECT grde.shrgrde_levl_code AS levl,
                           grde.shrgrde_code AS grde,
                           nvl(decode(grde.shrgrde_code, 'P', 4, grde.shrgrde_quality_points), 0) AS points
                      FROM saturn.shrgrde grde
                     CROSS JOIN (SELECT DISTINCT term FROM base)
                     WHERE grde.shrgrde_term_code_effective = (SELECT MAX(grde2.shrgrde_term_code_effective)
                                                                 FROM saturn.shrgrde grde2
                                                                WHERE grde2.shrgrde_levl_code = grde.shrgrde_levl_code
                                                                  AND grde2.shrgrde_code = grde.shrgrde_code
                                                                  AND grde2.shrgrde_term_code_effective <= rec.term_code)) g
            ON g.levl = CASE
               WHEN substr(csub.req_crse_1, instr(csub.req_crse_1, '_') + 1, 1) < 4 THEN
                'UG'
               WHEN substr(csub.req_crse_1, instr(csub.req_crse_1, '_') + 1, 1) < 7 THEN
                'GR'
               WHEN substr(csub.req_crse_1, instr(csub.req_crse_1, '_') + 1, 1) >= 7 THEN
                'DR'
               END
           AND g.grde IN (regexp_replace(regexp_substr(csub.rep_crse_1, 'Received: \([A-Za-z+-]+\)'), '(Received: \()|\)'), regexp_replace(regexp_substr(rep_crse_2, 'Received: \([A-Za-z+-]+\)'), '(Received: \()|\)'))
         WHERE rnk = 1
           AND zgrwfds_accept_reject = 'A')
 WHERE rnk = 1
UNION
SELECT DISTINCT pidm,
                term,
                ptrm,
                ptrm_start,
                ptrm_end,
                subj,
                numb,
                course,
                test_code,
                grde,
                points,
                req_met_type,
                req_met_dtl
  FROM (SELECT csub.pidm,
               '000000' AS term,
               NULL AS ptrm,
               NULL AS ptrm_start,
               NULL AS ptrm_end,
               substr(csub.req_crse_2, 1, instr(csub.req_crse_2, '_') - 1) AS subj,
               substr(csub.req_crse_2, instr(csub.req_crse_2, '_') + 1) AS numb,
               REPLACE(csub.req_crse_2, '_') AS course,
               NULL AS test_code,
               g.grde,
               g.points,
               'Course Sub' AS req_met_type,
               '(Submission ' || csub.submission_id || ') ' || regexp_replace(csub.rep_crse_1 || '; ' || csub.rep_crse_2, '(^; )|(; $)') AS req_met_dtl,
               rank() over(PARTITION BY csub.pidm, csub.req_crse_2 ORDER BY g.points DESC, rownum) AS rnk
          FROM base
          JOIN csub
            ON base.pidm = csub.pidm
           AND csub.req_crse_2 IS NOT NULL
          LEFT JOIN (SELECT grde.shrgrde_levl_code AS levl,
                           grde.shrgrde_code AS grde,
                           nvl(decode(grde.shrgrde_code, 'P', 4, grde.shrgrde_quality_points), 0) AS points
                      FROM saturn.shrgrde grde
                     CROSS JOIN (SELECT DISTINCT term FROM base)
                     WHERE grde.shrgrde_term_code_effective = (SELECT MAX(grde2.shrgrde_term_code_effective)
                                                                 FROM saturn.shrgrde grde2
                                                                WHERE grde2.shrgrde_levl_code = grde.shrgrde_levl_code
                                                                  AND grde2.shrgrde_code = grde.shrgrde_code
                                                                  AND grde2.shrgrde_term_code_effective <= rec.term_code)) g
            ON g.levl = CASE
               WHEN substr(csub.req_crse_2, instr(csub.req_crse_2, '_') + 1, 1) < 4 THEN
                'UG'
               WHEN substr(csub.req_crse_2, instr(csub.req_crse_2, '_') + 1, 1) < 7 THEN
                'GR'
               WHEN substr(csub.req_crse_2, instr(csub.req_crse_2, '_') + 1, 1) >= 7 THEN
                'DR'
               END
           AND g.grde IN (regexp_replace(regexp_substr(csub.rep_crse_1, 'Received: \([A-Za-z+-]+\)'), '(Received: \()|\)'), regexp_replace(regexp_substr(rep_crse_2, 'Received: \([A-Za-z+-]+\)'), '(Received: \()|\)'))
         WHERE rnk = 1
           AND zgrwfds_accept_reject = 'A')
 WHERE rnk = 1;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
--equivalencies
INSERT /*+*/ INTO utl_d_aim.preq_crse_hist
(pidm,
 term,
 ptrm,
 ptrm_start,
 ptrm_end,
 subj,
 numb,
 course,
 test_code,
 grde,
 points,
 req_met_type,
 req_met_dtl)
SELECT DISTINCT hist.pidm,
                hist.term,
                hist.ptrm,
                hist.ptrm_start,
                hist.ptrm_end,
                eqiv.screqiv_subj_code AS subj,
                eqiv.screqiv_crse_numb AS numb,
                eqiv.screqiv_subj_code || eqiv.screqiv_crse_numb AS course,
                hist.test_code,
                hist.grde,
                hist.points,
                hist.req_met_type AS req_met_type,
                'Course (Equivalent): ' || hist.course || ' Term: ' || hist.term || ' Grade: ' || hist.grde AS req_met_dtl
  FROM utl_d_aim.preq_crse_hist hist
  JOIN saturn.screqiv eqiv
    ON eqiv.screqiv_subj_code_eqiv || eqiv.screqiv_crse_numb_eqiv = hist.course
   AND hist.term BETWEEN eqiv.screqiv_start_term AND eqiv.screqiv_end_term
   AND eqiv.screqiv_eff_term = (SELECT MAX(eqiv2.screqiv_eff_term)
                                  FROM saturn.screqiv eqiv2
                                 WHERE eqiv2.screqiv_subj_code = eqiv.screqiv_subj_code
                                   AND eqiv2.screqiv_crse_numb = eqiv.screqiv_crse_numb
                                   AND eqiv2.screqiv_eff_term <= rec.term_code)
 WHERE hist.req_met_type IN ('Graded', 'Enrolled - no grade', 'Transfer');
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
--crosslist
INSERT /*+*/ INTO utl_d_aim.preq_crse_hist
SELECT DISTINCT hist.pidm,
                hist.term,
                hist.ptrm,
                hist.ptrm_start,
                hist.ptrm_end,
                CASE
                WHEN subj_eqiv_ind = 'Y' THEN
                 CASE
                 WHEN xlst.cross_subj_1 = hist.subj THEN
                  xlst.cross_subj_2
                 ELSE
                  xlst.cross_subj_2
                 END
                WHEN xlst.cross_crse_1 = hist.course THEN
                 xlst.cross_subj_2
                ELSE
                 xlst.cross_subj_1
                END AS subj,
                CASE
                WHEN subj_eqiv_ind = 'Y' THEN
                 hist.numb
                WHEN xlst.cross_crse_1 = hist.course THEN
                 xlst.cross_numb_1
                ELSE
                 xlst.cross_numb_2
                END AS numb,
                CASE
                WHEN subj_eqiv_ind = 'Y' THEN
                 CASE
                 WHEN xlst.cross_subj_1 = hist.subj THEN
                  xlst.cross_subj_2
                 ELSE
                  xlst.cross_subj_2
                 END || hist.numb
                WHEN xlst.cross_crse_1 = hist.course THEN
                 xlst.cross_crse_2
                ELSE
                 xlst.cross_crse_1
                END AS course,
                hist.test_code,
                hist.grde,
                hist.points,
                'Crosslisted' AS req_met_type,
                'Course: ' || hist.course || ' Term: ' || hist.term || ' Grade: ' || hist.grde AS req_met_dtl
  FROM utl_d_aim.preq_crse_hist hist
  JOIN zdegree_audit.dacrosslist xlst
    ON (one_way_ind = 'N' --is not one way
       OR (hist.course = xlst.cross_crse_1 AND subj_eqiv_ind = 'N') --is one way; course matches cross_crse_2
       OR (hist.subj = xlst.cross_subj_1 AND subj_eqiv_ind = 'Y')) --is one way; subject matches cross_subj_2
   AND ((hist.course IN (xlst.cross_crse_1, xlst.cross_crse_2) AND subj_eqiv_ind = 'N') --course matches cross_crse_1 or cross_crse_2 (if one way we know cross crse 1 already matches; if two way then this fullfills condition)
       OR (hist.subj IN (xlst.cross_subj_1, xlst.cross_subj_2) AND subj_eqiv_ind = 'Y') --subject matches cross_subj_1 or cross_subj_1 (if one way we know cross subj 1 already matches; if two way then this fullfills condition)
       )
 WHERE hist.req_met_type IN ('Graded', 'Enrolled - no grade', 'Transfer');
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
MERGE /*+*/ INTO  utl_d_aim.preq o
USING (SELECT pidm,
              term,
              crn,
              seqno,
              MAX(CASE
                  WHEN hist_req_met_type = 'Enrolled - no grade' THEN
                   CASE
                   WHEN hist_term < term THEN
                    1 --previous term
                   WHEN hist_term = term
                        AND concur_ind = 'Y' THEN
                    1 --concurrency allowed
                   ELSE
                    0 --flag
                   END
                  WHEN hist_req_met_type NOT IN ('Crosslisted', 'Course Sub') THEN
                   1
                  ELSE
                   0
                  END) AS req_met,
              CASE
              WHEN hist_req_met_type = 'Enrolled - no grade' THEN
               CASE
               WHEN hist_term < term THEN
                'Enrolled previous term - no grade'
               WHEN hist_term = term
                    AND concur_ind = 'Y' THEN
                'Enrolled current term - concurrency allowed'
               WHEN hist_term = term
                    AND hist_ptrm_end < ptrm_start THEN
                'Enrolled current term - no grade'
               ELSE
                'Enrolled current term - overlapping subterms'
               END
              ELSE
               hist_req_met_type
              END AS req_met_type,
              coalesce(listagg(CASE
                               WHEN hist_req_met_type IN ('Equivalent', 'Course Sub', 'Crosslisted') THEN
                                hist_req_met_dtl
                               END, ', ') within GROUP(ORDER BY hist_req_met_dtl), MAX(CASE
                            WHEN hist_req_met_type IN ('Graded', 'Enrolled - no grade', 'Test', 'Equivalent', 'Transfer') THEN
                             hist_req_met_dtl
                            END)) AS req_met_dtl,
              MAX(CASE
                  WHEN hist_req_met_type = 'Enrolled - no grade'
                       AND hist_term = term
                       AND hist_ptrm_end >= ptrm_start
                       AND concur_ind != 'Y' THEN
                   0
                  WHEN hist_req_met_type NOT IN ('Crosslisted', 'Course Sub') THEN
                   1
                  ELSE
                   0
                  END) AS req_met_w_enroll
         FROM (SELECT preq.*,
                      hist.pidm         AS hist_pidm,
                      hist.term         AS hist_term,
                      hist.ptrm         AS hist_ptrm,
                      hist.ptrm_end     AS hist_ptrm_end,
                      hist.course       AS hist_course,
                      hist.test_code    AS hist_test,
                      hist.grde         AS hist_grde,
                      hist.points       AS hist_points,
                      hist.req_met_type AS hist_req_met_type,
                      hist.req_met_dtl  AS hist_req_met_dtl
                                                 , dense_rank() over (partition by preq.pidm
                                                                                 , preq.term
                                                                                 , preq.crn
                                                                                 , preq.seqno
                                                                      order by case when hist.req_met_type = 'Enrolled - no grade' then 2
                                                                                    when hist.req_met_type in ('Graded','Test','Transfer') then 1
                                                                                    when hist.req_met_type = 'Equivalent' then 3
                                                                                    when hist.req_met_type = 'Course - Sub' then 4
                                                                                    else 4
                                                                               end
                                                                             , hist.points desc
                                                                             , hist.grde
                                                                             , rownum) as ranking
                 FROM utl_d_aim.preq preq
                 JOIN utl_d_aim.preq_crse_hist hist
                   ON hist.pidm = preq.pidm
                  AND nvl(hist.course, hist.test_code) = preq.preq_course
                  AND (
                      --preq met
                       hist.points >= preq.min_points
                      --preq not graded
                       OR hist.points IS NULL AND (hist.term < preq.term --past term
                       OR hist.term = preq.term --same term but preq starts before reg course starts
                       /*and hist.ptrm_end < preq.ptrm_start*/ --moving this logic
                       --concurrency
                       OR preq.concur_ind = 'Y' AND hist.term = preq.term) --same term
                      )
                WHERE preq.req_met = 0)
        GROUP BY pidm,
                 term,
                 crn,
                 seqno,
                 hist_req_met_type,
                 hist_term,
                 concur_ind,
                 hist_ptrm_end,
                 ptrm_start
       HAVING MAX(CASE WHEN ranking = 1 AND hist_req_met_type IN('Graded', 'Test', 'Transfer', 'Enrolled - no grade') THEN 1 END) IS NOT NULL OR MAX(CASE WHEN ranking = 1 AND hist_req_met_type IN('Equivalent', 'Crosslisted', 'Course Sub') THEN 1 END) IS NOT NULL --these needed for listaggs
       AND hist_req_met_type IN('Equivalent', 'Crosslisted', 'Course Sub')) n
ON (n.pidm = o.pidm AND n.term = o.term AND n.crn = o.crn AND n.seqno = o.seqno)
WHEN MATCHED THEN
UPDATE
   SET o.req_met          = n.req_met,
       o.req_met_type     = n.req_met_type,
       o.req_met_dtl      = n.req_met_dtl,
       o.req_met_w_enroll = n.req_met_w_enroll;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
FOR v_crse IN c_crses
LOOP
BEGIN
EXECUTE IMMEDIATE 'select case when ' || v_crse.cond || ' then 1 else 0 end from dual'
INTO v_preq_met;
EXECUTE IMMEDIATE 'select case when ' || v_crse.cond_w_enroll || ' then 1 else 0 end from dual'
INTO v_preq_met_w_enroll;
IF v_preq_met = 0
   OR v_preq_met_w_enroll = 0 THEN
l_preqs_met.extend;
l_preqs_met(l_preqs_met.last).pidm := v_crse.pidm;
l_preqs_met(l_preqs_met.last).term := v_crse.term;
l_preqs_met(l_preqs_met.last).crn := v_crse.crn;
l_preqs_met(l_preqs_met.last).course_preq_met := v_preq_met;
l_preqs_met(l_preqs_met.last).course_preq_met_w_enroll := v_preq_met_w_enroll;
END IF;
EXCEPTION
WHEN OTHERS THEN
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := v_crse.term || ' ' || v_crse.crn || ': ' || SQLERRM || chr(10);
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(0));
ads_etl.insert_job_log(v_proc, 'WARNING', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
dbms_output.put_line(' --------- ');
END;
END LOOP; --c_crse
FORALL i IN 1 .. l_preqs_met.count
UPDATE utl_d_aim.preq
   SET course_preq_met          = l_preqs_met(i).course_preq_met,
       course_preq_met_w_enroll = l_preqs_met(i).course_preq_met_w_enroll
 WHERE pidm = l_preqs_met(i).pidm
   AND term = l_preqs_met(i).term
   AND crn = l_preqs_met(i).crn;
COMMIT;
DELETE /*+*/ FROM  utl_d_aim.szrpreq preq WHERE preq.term = rec.term_code;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'DELETE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
INSERT /*+*/ INTO utl_d_aim.szrpreq
(pidm,
 term,
 stu_campus,
 subj,
 numb,
 course,
 crn,
 reg_type,
 crse_campus,
 course_preq_met,
 course_preq_met_w_enroll,
 prerequisites,
 sfrsrpo_override,
 refresh_date)
SELECT preq.pidm,
       preq.term,
       preq.stu_campus,
       preq.subj,
       preq.numb,
       preq.course,
       preq.crn,
       preq.reg_type,
       preq.crse_campus,
       preq.course_preq_met,
       preq.course_preq_met_w_enroll,
       -- Enhanced prerequisites formatting
       TRIM(
         REGEXP_REPLACE(
           REGEXP_REPLACE(
             REGEXP_REPLACE(
               REGEXP_REPLACE(
                 REGEXP_REPLACE(
                   REGEXP_REPLACE(
                     REGEXP_REPLACE(
                       REGEXP_REPLACE(
                         -- Build the prerequisites string
                         LISTAGG(
                           TRIM(
                             -- Remove extra spaces from each component
                             REGEXP_REPLACE(
                               preq.connector ||
                               NVL(preq.lparen, ' ') ||
                               preq.preq_course || ' ' ||
                               preq.grde ||
                               NVL2(preq.concur_ind, ' Concur ', NULL) ||
                               CASE WHEN preq.req_met = 1 THEN 'Met ' END ||
                               preq.rparen,
                               '\s+', ' ' -- collapse multiple spaces to one
                             )
                           ),
                           '' -- No separator, as connectors are included in the string
                         ) WITHIN GROUP (ORDER BY preq.seqno),
                         '^\s+|\s+$', '', 1, 0
                       ),
                       '\)\s*And\s*\(', ') And (', 1, 0
                     ),
                     '\)\s*Or\s*\(', ') Or (', 1, 0
                   ),
                   '\(\s+', '(', 1, 0
                 ),
                 '\s+\)', ')', 1, 0
               ),
               '\s+(And|Or)\s+', ' \1 ', 1, 0
             ),
             -- Fix: ensure "Met" and "Concur" are not concatenated with parenthesis (e.g., "Met(" -> "Met (", "Concur(" -> "Concur (")
             '(Met|Concur)\(', '\1 (', 1, 0
           ),
           -- Fix: ensure "Met" and "Concur" are not concatenated with "And"/"Or" (e.g., "MetAnd" -> "Met And")
           '(Met|Concur)\s*(And|Or)', '\1 \2', 1, 0
         )
       ) AS prerequisites,
       nvl2(preq.ovr_subj, 'Y', '') AS sfrsrpo_override,
       preq.refresh_date
  FROM utl_d_aim.preq preq
 WHERE preq.course_preq_met = 0
   AND preq.batch_id IS NULL
   AND preq.term = rec.term_code
 GROUP BY preq.pidm,
          preq.term,
          preq.stu_campus,
          preq.subj,
          preq.numb,
          preq.course,
          preq.crn,
          preq.reg_type,
          preq.crse_campus,
          preq.course_preq_met,
          preq.course_preq_met_w_enroll,
          nvl2(preq.ovr_subj, 'Y', ''),
          refresh_date;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- THIS IS HERE TO FIX PROBLEMS WE DO NOT KNOW HOW TO FIX IN THE MAIN PART OF THE PROCEDURE
UPDATE utl_d_aim.szrpreq src
   SET course_preq_met_prior_p = 1
 WHERE EXISTS (SELECT spriden_id AS luid,
               hist2.term,
               hist2.course,
               hist2.grde,
               szrpreq.*
          FROM utl_d_aim.szrpreq
          JOIN utl_d_aim.preq
            ON preq.pidm = szrpreq.pidm
           AND preq.course = szrpreq.course
          JOIN utl_d_aim.preq_crse_hist hist1
            ON hist1.pidm = szrpreq.pidm
           AND hist1.course = preq.preq_course
           AND hist1.term = szrpreq.term
          JOIN utl_d_aim.preq_crse_hist hist2
            ON hist2.pidm = szrpreq.pidm
           AND hist2.course = preq.preq_course
           AND hist2.term < szrpreq.term
          JOIN spriden
            ON spriden_pidm = szrpreq.pidm
           AND spriden_change_ind IS NULL
         WHERE 1 = 1
           AND szrpreq.term = rec.term_code
           AND hist2.grde = 'P'
           AND szrpreq.course_preq_met_w_enroll = 0
           AND preq.req_met = 0
           AND src.pidm = szrpreq.pidm
           AND src.term = szrpreq.term
           AND src.crn = szrpreq.crn);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'UPDATE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
END LOOP; --c_term loop
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
1.0        08-30-2018  kcaldwell      Initial release
1.1        04-30-2019  lxhatfield     update term logic
2.0        11-21-2019  lxhatfield     adjusted logic TKT2089874
2.1        11-21-2019  lxhatfield     adjusted listagg to accomodate BUSI 885
2.2        05-14-2020  lxhatfield     added batch results to preq
3.0        07-08-2020  lxhatfield     add prereq batch processing (PPRD_PREREQ_CHECK)
3.1        12-07-2020  lxhatfield     added exception handling to catch sql errors in the preq logic & email errors to me
3.2        30-08-2021  lxhatfield     TKT2257761 - changed Incomplete grade(I) to show Enrolled - No Grade instead of Graded
3.3        12-15-2021  cwalsh1        Added 'distinct' to listagg in final szrpreq insert to reduce 'string concat too long' errors
---     05-24-2023  wgriffith2  --updating code to use job_log
---     06-21-2023  wgriffith2  --restored. report location -> https://argosreports02.university.liberty.edu/Argos/awv/#explorer/Banner%00DLP%00Reports%00Processing/At-risk%20Prerequisite%20Students/Dashboard
---     07-21-2023  wruminn    --This handles the issue of the course prerequisites in banner having a blank row with only a parenthesis.
---     01-26-2024  wgriffith2  --TKT2837558-created a hacky way to fix where student meets the prerequisites with a P grade.
---     06-28-2024  wgriffith2   --CASE WHEN regexp_like(tst.sortest_test_score, '^\d+(\.\d+)?$') THEN to_number(tst.sortest_test_score) ELSE NULL -- or 0, or any default numeric value you prefer END AS points,
-- 20251013      wgriffith2      --Added REGEXP_REPLACE to ensure "Met (" and "Concur (" are not concatenated, fixing the "Met(" and "Concur(" spacing issue.
------------------------------------------------------------------------------------------------*/
END etl_aim_prerequisites_refresh;

PROCEDURE etl_aim_nadrops (jobnumber number, processid varchar2, processname varchar2) is
/*
Table: utl_d_aim.znadrop

Primary Keys: ZNADROP_SEQ_NO

Unique index: ZNADROP_TERM, ZNADROP_PTRM, ZNADROP_LEVL

Purpose:
The enrollment drop detection generates reports showing the number of student enrollment drops that occurred on a specific date.
This addresses the challenge of distinguishing between newly occurred drops and historical drop events that may be processed or reviewed on the current day.

Conditions:
Captures a complete enrollment snapshot from the previous day
Compares it against the current enrollment data
Identifies missing enrollments to determine drops
Aggregates the results into a drop count report
Student was registered and did not complete CRC
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
v_proc        VARCHAR2(100) := 'etl_aim_nadrops';
-- CURSOR
CURSOR c_terms IS
SELECT DISTINCT ll.term_code,
                t.fa_proc_year AS aidy_code,
                ll.start_date, -- same as ssbsect_ptrm_start_date
                to_date(to_char(trunc((ll.start_date + 8)) + (4 / 24), 'MM/DD/YYYY hh24:mi:ss'), 'MM/DD/YYYY hh24:mi:ss') AS start_date_8d -- simulates 4am of that date which is a few hours BEFORE drops would have happened (later in the day manually)
  FROM zbtm.terms_by_group_v t
  JOIN utl_d_lms.lms_link ll
    ON ll.term_code = t.term_code
 WHERE 1 = 1
   AND ll.enrollment > 0 -- must have enrollment in the course
   AND ll.instance = 'L2CAN' --
   AND t.group_code = 'STD' -- only standard terms
   AND t.semester <> 'WIN' -- exclude winter
   AND ll.ptrm_code IN ('1A', '1B', '1C', '1D') -- only main online ptrm
   AND SYSDATE BETWEEN t.start_date AND t.end_date -- current term_code only
   AND to_date(to_char(trunc((ll.start_date + 8)) + (4 / 24), 'MM/DD/YYYY hh24:mi:ss'), 'MM/DD/YYYY hh24:mi:ss') < SYSDATE -- cannot run this until after the 9th day
   AND t.term_code >= '202020' -- report does not work prior to this term (zoctopus.latest_course_activity)
 ORDER BY ll.start_date DESC;
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
v_msg     := 'START - ' || rec.term_code || ' - ' || rec.start_date || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- we have to pull a snapshot of ALL the 8th days enrollment
-- In the tableau report, we will comparing the total number vs the drops and show this as a percentage of the total
INSERT INTO utl_d_aim.znadrop_gtt
(term_code,
 crn,
 pidm,
 ptrm_code,
 levl_code,
 credit_hr,
 first_enrl_term_year, -- 1/0 first enrollment of the year
 first_enrl_term, -- 1/0 first time ever at LU
 fci, -- 1/0 completed FCI
 dropped -- 1/0 enrollment was NAD
 )
SELECT sfrstca_term_code AS term_code,
       sfrstca_crn AS crn,
       sfrstca_pidm AS pidm,
       ssbsect_ptrm_code AS ptrm_code,
       lcur.levl_code AS levl_code,
       sfrstca_credit_hr AS credit_hr,
       CASE
       WHEN EXISTS (SELECT 'X'
               FROM utl_d_aim.szrenrl
              WHERE szrenrl.pidm = sfrstca_pidm
                AND szrenrl.acad_year = rec.aidy_code
                AND szrenrl.term_code < rec.term_code) THEN
        0
       ELSE
        1
       END new_to_year,
       CASE
       WHEN EXISTS (SELECT 'X'
               FROM utl_d_aim.szrenrl
              WHERE szrenrl.pidm = sfrstca_pidm
                AND szrenrl.term_code < rec.term_code) THEN
        0
       ELSE
        1
       END new_to_lu,
       (SELECT 1
          FROM zfincheckin.zfrfcis
         WHERE zfrfcis_term = rec.term_code
           AND zfrfcis_pidm = sfrstca_pidm
           AND zfrfcis_withdrawn IS NULL -- make sure FCI was not withdrawn
         HAVING MAX(zfrfcis_create_date) <= rec.start_date_8d -- must have FCI before the runtime
        ) AS fci_date,
       CASE
       WHEN la.last_activity IS NULL -- no activity found in the LMS
            AND reg.pidm IS NULL -- no longer actively enrolled in that course
        THEN
        1
       ELSE
        0
       END dropped
  FROM saturn.sfrstca
  JOIN saturn.stvrsts
    ON stvrsts.stvrsts_code = sfrstca_rsts_code
   AND stvrsts_incl_sect_enrl = 'Y' -- aligns with AA tables
   AND sfrstca_term_code = rec.term_code
   AND sfrstca_source_cde = 'BASE'
   AND sfrstca_seq_number = (SELECT MAX(d.sfrstca_seq_number)
                               FROM saturn.sfrstca d
                              WHERE d.sfrstca_pidm = sfrstca.sfrstca_pidm
                                AND d.sfrstca_term_code = sfrstca.sfrstca_term_code
                                AND d.sfrstca_crn = sfrstca.sfrstca_crn
                                AND d.sfrstca_source_cde = sfrstca.sfrstca_source_cde
                                AND d.sfrstca_activity_date <= rec.start_date_8d)
  JOIN saturn.ssbsect
    ON ssbsect_term_code = sfrstca_term_code
   AND ssbsect_crn = sfrstca_crn
   AND ssbsect_ptrm_start_date = rec.start_date
   AND ssbsect_ptrm_code IN ('1A', '1B', '1C', '1D')
   AND ssbsect_subj_code NOT IN ('CSER', 'CAFE', 'SFME', 'FRSM', 'NEWS') -- remove these courses that shouldn't be considered
   AND (ssbsect_camp_code = 'D' OR (ssbsect_camp_code = 'R' AND ssbsect_insm_code = 'ON' AND ssbsect_subj_code || ssbsect_crse_numb IN ('INQR101', 'RSCH201', 'UNIV101'))) -- get course taught online
  JOIN saturn.spriden iden
    ON iden.spriden_pidm = sfrstca_pidm
   AND iden.spriden_change_ind IS NULL
   AND iden.spriden_id LIKE 'L%' -- avoid any duplicate pidm situations
-- check the activity table to confirm the drop was for non-attendence and NOT just a random one
  LEFT JOIN (SELECT term_code,
                    crn,
                    pidm,
                    MAX(last_activity) AS last_activity --
               FROM (
                     -- CANVAS COURSES INTERNAL ACTIVITY
                     SELECT spriden_pidm AS pidm,
                             ssbsect_term_code AS crn,
                             ssbsect_term_code AS term_code,
                             MAX(oct.activity_date) AS last_activity
                       FROM zoctopus.latest_course_activity oct -- min term_code = 202020
                       JOIN saturn.ssbsect
                         ON ssbsect_term_code || ssbsect_crn = oct.course_sis_id
                        AND ssbsect_term_code = rec.term_code
                       JOIN saturn.spriden
                         ON spriden_id = oct.user_sis_id
                        AND spriden_change_ind IS NULL
                      WHERE oct.activity_source = 'CANVAS'
                        AND oct.activity_date <= rec.start_date_8d
                      GROUP BY spriden_pidm,
                                ssbsect_term_code,
                                ssbsect_term_code
                     UNION
                     -- CANVAS COURSES EXTERNAL ACTIVITY
                     SELECT spriden_pidm AS pidm,
                             ssbsect_term_code AS crn,
                             ssbsect_term_code AS term_code,
                             MAX(ea.activity_date) AS last_activity
                       FROM zlighthouse.external_activity ea -- min term_code = 201620
                       JOIN saturn.ssbsect
                         ON ssbsect_term_code || ssbsect_crn = substr(ea.enrollment_id, 1, instr(ea.enrollment_id, '_') - 1)
                        AND ssbsect_term_code = rec.term_code
                       JOIN saturn.spriden
                         ON spriden_id = substr(ea.enrollment_id, instr(ea.enrollment_id, '_') + 1)
                        AND spriden_change_ind IS NULL
                      WHERE ea.deleted = 'N'
                        AND ea.activity_date <= rec.start_date_8d
                      GROUP BY spriden_pidm,
                                ssbsect_term_code,
                                ssbsect_term_code)
              GROUP BY term_code,
                       crn,
                       pidm) la
    ON la.term_code = sfrstca_term_code
   AND la.crn = sfrstca_crn
   AND la.pidm = sfrstca_pidm
  LEFT JOIN (SELECT sfrstcr_term_code AS term_code,
                    sfrstcr_crn       AS crn,
                    sfrstcr_pidm      AS pidm
               FROM saturn.sfrstcr
               JOIN saturn.stvrsts
                 ON sfrstcr_rsts_code = stvrsts.stvrsts_code
                AND stvrsts_incl_sect_enrl = 'Y'
               JOIN saturn.ssbsect
                 ON ssbsect_term_code = sfrstcr_term_code
                AND ssbsect_crn = sfrstcr_crn
                AND ssbsect_subj_code NOT IN ('CSER', 'FRSM', 'GRST', 'NEWS', 'NSSR')) reg
    ON reg.term_code = sfrstca_term_code
   AND reg.crn = sfrstca_crn
   AND reg.pidm = sfrstca_pidm
  LEFT JOIN zexec.zsavlcur lcur
  ON lcur.pidm = sfrstca_pidm
   AND sfrstca_term_code BETWEEN lcur.from_term AND lcur.end_term;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || rec.term_code || ' - ' || rec.start_date || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
MERGE INTO utl_d_aim.znadrop tgt
USING (SELECT src.znadrop_term,
              src.znadrop_ptrm,
              src.znadrop_credit_hrs,
              src.znadrop_distinct_students,
              src.znadrop_unique_students,
              src.znadrop_new,
              src.znadrop_returning,
              src.znadrop_checkin,
              src.znadrop_registrations,
              src.znadrop_total_seats,
              src.znadrop_activity_date,
              src.znadrop_levl
         FROM (SELECT gtt.term_code AS znadrop_term,
                       CASE
                       WHEN gtt.ptrm_code IN ('1A', '1B') THEN
                        'AB'
                       WHEN gtt.ptrm_code = '1C' THEN
                        'C'
                       WHEN gtt.ptrm_code = '1D' THEN
                        'D'
                       END AS znadrop_ptrm,
                       gtt.levl_code AS znadrop_levl,
                       SUM(CASE
                           WHEN gtt.dropped = 1 THEN
                            gtt.credit_hr
                           ELSE
                            0
                           END) AS znadrop_credit_hrs,
                       COUNT(DISTINCT CASE
                             WHEN gtt.dropped = 1 THEN
                              gtt.pidm
                             END) AS znadrop_distinct_students,
                       COUNT(DISTINCT CASE
                             WHEN gtt.dropped = 1
                                  AND gtt.first_enrl_term_year = 1 THEN
                              gtt.pidm
                             END) AS znadrop_unique_students, -- this is a horribly named field btw; it's distinct students dropped taking their first term this academic year
                      COUNT(DISTINCT CASE
                            WHEN gtt.dropped = 1
                                 AND gtt.first_enrl_term = 1 THEN
                             gtt.pidm
                            END) AS znadrop_new,
                      COUNT(DISTINCT CASE
                            WHEN gtt.dropped = 1
                                 AND gtt.first_enrl_term = 0 THEN
                             gtt.pidm
                            END) AS znadrop_returning,
                      COUNT(DISTINCT CASE
                            WHEN gtt.fci = 1 THEN
                             gtt.pidm
                            END) AS znadrop_checkin,
                      COUNT(DISTINCT CASE
                            WHEN gtt.dropped = 1 THEN
                             gtt.term_code || gtt.crn || gtt.pidm
                            END) AS znadrop_registrations,
                      (SELECT COUNT(DISTINCT gtt2.term_code || gtt2.crn || gtt2.pidm) FROM utl_d_aim.znadrop_gtt gtt2) AS znadrop_total_seats,
                      v_etl_date AS znadrop_activity_date
                 FROM utl_d_aim.znadrop_gtt gtt
                GROUP BY gtt.term_code,
                         CASE
                         WHEN gtt.ptrm_code IN ('1A', '1B') THEN
                          'AB'
                         WHEN gtt.ptrm_code = '1C' THEN
                          'C'
                         WHEN gtt.ptrm_code = '1D' THEN
                          'D'
                         END,
                         gtt.levl_code
               HAVING SUM(CASE WHEN gtt.dropped = 1 THEN gtt.credit_hr ELSE 0 END) > 0) src
         LEFT JOIN utl_d_aim.znadrop tgt
           ON tgt.znadrop_term = src.znadrop_term
          AND tgt.znadrop_ptrm = src.znadrop_ptrm
          AND tgt.znadrop_levl = src.znadrop_levl
        WHERE tgt.znadrop_term IS NULL -- only insert the data once and never again!
       ) src
ON (tgt.znadrop_term = src.znadrop_term AND tgt.znadrop_ptrm = src.znadrop_ptrm AND tgt.znadrop_levl = src.znadrop_levl)
WHEN MATCHED THEN
UPDATE
   SET tgt.znadrop_credit_hrs        = src.znadrop_credit_hrs,
       tgt.znadrop_distinct_students = src.znadrop_distinct_students,
       tgt.znadrop_unique_students   = src.znadrop_unique_students,
       tgt.znadrop_new               = src.znadrop_new,
       tgt.znadrop_returning         = src.znadrop_returning,
       tgt.znadrop_checkin           = src.znadrop_checkin,
       tgt.znadrop_registrations     = src.znadrop_registrations,
       tgt.znadrop_total_seats       = src.znadrop_total_seats,
       tgt.znadrop_activity_date     = src.znadrop_activity_date
WHEN NOT MATCHED THEN
INSERT
(znadrop_term,
 znadrop_ptrm,
 znadrop_credit_hrs,
 znadrop_distinct_students,
 znadrop_unique_students,
 znadrop_new,
 znadrop_returning,
 znadrop_checkin,
 znadrop_registrations,
 znadrop_total_seats,
 znadrop_activity_date,
 znadrop_levl)
VALUES
(src.znadrop_term,
 src.znadrop_ptrm,
 src.znadrop_credit_hrs,
 src.znadrop_distinct_students,
 src.znadrop_unique_students,
 src.znadrop_new,
 src.znadrop_returning,
 src.znadrop_checkin,
 src.znadrop_registrations,
 src.znadrop_total_seats,
 src.znadrop_activity_date,
 src.znadrop_levl);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || rec.term_code || ' - ' || rec.start_date || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- utl_d_aim.truncate_table(v_table_name => 'znadrop_gtt'); -- truncate after a successful loop completes
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
VERSION    DATE        USERNAME       UPDATES
1.0        03-28-2017  odavenport2    --Initial release
2.0        08-28-2019  kcaldwell      --rewrote with temp tables
3.0        11-04-2020  lxhatfield     --rewrote temp3 insert as query was running into temp space issues
3.1        07-15-2021  lxhatfield     --reworte temp1 insert as query was running into temp space issues
---     05-17-2023  wgriffith2  --Dealing with EM courses and updating code to use job_log
---     06-25-2025  wgriffith2  --complete overhaul of the code (TKT3104237); Automated ETL process identifies and logs non-attendance drops for online courses, updating summary tables for reporting and analysis.
---     07-02-2025  wgriffith2  --Adding znadrop_unique_students back in since we now know the definition for what it is
------------------------------------------------------------------------------------------------*/
END etl_aim_nadrops;

procedure etl_aim_szrcurr_refresh (jobnumber number, processid varchar2, processname varchar2) is
/*
Table: utl_d_aim.szrcurr

Unique index: pidm, szrcurr_from_term, szrcurr_to_term

Purpose:
- there really is none. this table is useless but only in place because too many reports use this to migrate
- it is best to use zexec.zsavlcur instead

*/
--DECLARE
v_etl_date    DATE := SYSDATE;
v_msg         VARCHAR2(2000);
v_instance    VARCHAR2(50) := upper('ALL'); -- inst from the jams job; used for determining instance
v_partition    NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_aim_szrcurr_refresh';
BEGIN
-- dbms_output.enable(buffer_size => NULL);
--
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
dbms_lock.sleep(1.0); -- pause
MERGE INTO utl_d_aim.szrcurr tgt
USING (SELECT lcur.pidm          AS szrcurr_pidm,
              lcur.from_term     AS szrcurr_from_term,
              lcur.end_term      AS szrcurr_to_term,
              lcur.camp_code     AS szrcurr_camp_code_1,
              lcur.levl_code     AS szrcurr_levl_code_1,
              lcur.prog_code_1   AS szrcurr_prog_code_1,
              lcur.majr_code_1   AS szrcurr_majr_code_1,
              majr1.stvmajr_desc AS szrcurr_majr_desc_1,
              lcur.degc_code_1   AS szrcurr_degc_code_1,
              lcur.camp_code     AS szrcurr_camp_code_2,
              lcur.levl_code_2   AS szrcurr_levl_code_2,
              lcur.prog_code_2   AS szrcurr_prog_code_2,
              lcur.majr_code_2   AS szrcurr_majr_code_2,
              majr2.stvmajr_desc AS szrcurr_majr_desc_2,
              lcur.degc_code_2   AS szrcurr_degc_code_2,
              lcur.minr_code_1   AS szrcurr_minr_code_1,
              lcur.minr_code_2   AS szrcurr_minr_code_2,
              lcur.prog_coll_1   AS szrcurr_coll_code_1,
              lcur.prog_coll_2   AS szrcurr_coll_code_2
         FROM zexec.zsavlcur lcur
         LEFT JOIN stvmajr majr1
           ON majr1.stvmajr_code = lcur.majr_code_1
         LEFT JOIN stvmajr majr2
           ON majr2.stvmajr_code = lcur.majr_code_2
        WHERE lcur.current_ind = 'Y') src
ON (tgt.szrcurr_pidm = src.szrcurr_pidm AND tgt.szrcurr_from_term = src.szrcurr_from_term AND tgt.szrcurr_to_term = src.szrcurr_to_term)
WHEN MATCHED THEN
UPDATE
   SET tgt.szrcurr_camp_code_1 = src.szrcurr_camp_code_1,
       tgt.szrcurr_levl_code_1 = src.szrcurr_levl_code_1,
       tgt.szrcurr_prog_code_1 = src.szrcurr_prog_code_1,
       tgt.szrcurr_majr_code_1 = src.szrcurr_majr_code_1,
       tgt.szrcurr_majr_desc_1 = src.szrcurr_majr_desc_1,
       tgt.szrcurr_degc_code_1 = src.szrcurr_degc_code_1,
       tgt.szrcurr_camp_code_2 = src.szrcurr_camp_code_2,
       tgt.szrcurr_levl_code_2 = src.szrcurr_levl_code_2,
       tgt.szrcurr_prog_code_2 = src.szrcurr_prog_code_2,
       tgt.szrcurr_majr_code_2 = src.szrcurr_majr_code_2,
       tgt.szrcurr_majr_desc_2 = src.szrcurr_majr_desc_2,
       tgt.szrcurr_degc_code_2 = src.szrcurr_degc_code_2,
       tgt.szrcurr_minr_code_1 = src.szrcurr_minr_code_1,
       tgt.szrcurr_minr_code_2 = src.szrcurr_minr_code_2,
       tgt.szrcurr_coll_code_1 = src.szrcurr_coll_code_1,
       tgt.szrcurr_coll_code_2 = src.szrcurr_coll_code_2
 WHERE
-- Only update if any value is different
 (nvl(tgt.szrcurr_camp_code_1, 'x') != nvl(src.szrcurr_camp_code_1, 'x') OR --
 nvl(tgt.szrcurr_levl_code_1, 'x') != nvl(src.szrcurr_levl_code_1, 'x') OR --
 nvl(tgt.szrcurr_prog_code_1, 'x') != nvl(src.szrcurr_prog_code_1, 'x') OR --
 nvl(tgt.szrcurr_majr_code_1, 'x') != nvl(src.szrcurr_majr_code_1, 'x') OR --
 nvl(tgt.szrcurr_majr_desc_1, 'x') != nvl(src.szrcurr_majr_desc_1, 'x') OR --
 nvl(tgt.szrcurr_degc_code_1, 'x') != nvl(src.szrcurr_degc_code_1, 'x') OR --
 nvl(tgt.szrcurr_camp_code_2, 'x') != nvl(src.szrcurr_camp_code_2, 'x') OR --
 nvl(tgt.szrcurr_levl_code_2, 'x') != nvl(src.szrcurr_levl_code_2, 'x') OR --
 nvl(tgt.szrcurr_prog_code_2, 'x') != nvl(src.szrcurr_prog_code_2, 'x') OR --
 nvl(tgt.szrcurr_majr_code_2, 'x') != nvl(src.szrcurr_majr_code_2, 'x') OR --
 nvl(tgt.szrcurr_majr_desc_2, 'x') != nvl(src.szrcurr_majr_desc_2, 'x') OR --
 nvl(tgt.szrcurr_degc_code_2, 'x') != nvl(src.szrcurr_degc_code_2, 'x') OR --
 nvl(tgt.szrcurr_minr_code_1, 'x') != nvl(src.szrcurr_minr_code_1, 'x') OR --
 nvl(tgt.szrcurr_minr_code_2, 'x') != nvl(src.szrcurr_minr_code_2, 'x') OR --
 nvl(tgt.szrcurr_coll_code_1, 'x') != nvl(src.szrcurr_coll_code_1, 'x') OR --
 nvl(tgt.szrcurr_coll_code_2, 'x') != nvl(src.szrcurr_coll_code_2, 'x'))
WHEN NOT MATCHED THEN
INSERT
(szrcurr_pidm,
 szrcurr_from_term,
 szrcurr_to_term,
 szrcurr_camp_code_1,
 szrcurr_levl_code_1,
 szrcurr_prog_code_1,
 szrcurr_majr_code_1,
 szrcurr_majr_desc_1,
 szrcurr_degc_code_1,
 szrcurr_camp_code_2,
 szrcurr_levl_code_2,
 szrcurr_prog_code_2,
 szrcurr_majr_code_2,
 szrcurr_majr_desc_2,
 szrcurr_degc_code_2,
 szrcurr_minr_code_1,
 szrcurr_minr_code_2,
 szrcurr_coll_code_1,
 szrcurr_coll_code_2,
 szrcurr_etl_date,
 szrcurr_from_date,
 szrcurr_to_date)
VALUES
(src.szrcurr_pidm,
 src.szrcurr_from_term,
 src.szrcurr_to_term,
 src.szrcurr_camp_code_1,
 src.szrcurr_levl_code_1,
 src.szrcurr_prog_code_1,
 src.szrcurr_majr_code_1,
 src.szrcurr_majr_desc_1,
 src.szrcurr_degc_code_1,
 src.szrcurr_camp_code_2,
 src.szrcurr_levl_code_2,
 src.szrcurr_prog_code_2,
 src.szrcurr_majr_code_2,
 src.szrcurr_majr_desc_2,
 src.szrcurr_degc_code_2,
 src.szrcurr_minr_code_1,
 src.szrcurr_minr_code_2,
 src.szrcurr_coll_code_1,
 src.szrcurr_coll_code_2,
 v_etl_date,
 -- the only reason the szrcurr_from_date and szrcurr_to_date exist still is to not break queries; hard-coded values set on 20251023 update due to flawed logic in initial release of code
 to_date('01/01/1971', 'MM/DD/YYYY'),
 to_date('12/31/2099', 'MM/DD/YYYY'));
v_count := SQL%ROWCOUNT;
COMMIT;
dbms_lock.sleep(1.0); -- pause
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
dbms_lock.sleep(1.0); -- pause
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
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
/*--------------------------------------------CHANGE LOG----------------------------------------
VERSION  DATE        USERNAME    UPDATES
---      09-28-2017  odavenport2    --Initial release
---     10-23-2025  wgriffith2   -- backfilling historical data prior to 2017; quality of life improvements to the code for efficiency
------------------------------------------------------------------------------------------------*/
END etl_aim_szrcurr_refresh;

procedure etl_aim_szrdgmr_refresh (jobnumber number, processid varchar2, processname varchar2) is
--declare
/* *********************************************************************** */
/* ********* LIBERTY UNIVERSITY - Analytics and Decision Support ********* */
/* ********* OJBECT NAME: UTL_D_AIM.szrdgmr                      ********* */
/* ********* DESCRIPTION: Refresh for Graduation Table           ********* */
/* ********* CREATED BY: Owen Davenport                          ********* */
/* ********* (See CHANGE LOG at bottom of file)                  ********* */
/* *********************************************************************** */

  PRAGMA AUTONOMOUS_TRANSACTION;

  v_cnt number := 0;
  v_etl_date   date   := sysdate;
  v_end_date   date   := v_etl_date - 1 / (24 * 60 * 60);

  cursor c_changes is
     select nvl(nw.szrdgmr_pidm,ol.szrdgmr_pidm) as szrdgmr_pidm
          , nw.szrdgmr_levl_code
          , nw.szrdgmr_camp_code
          , nw.szrdgmr_prog_code
          , nw.szrdgmr_degc_code
          , nw.szrdgmr_majr_code_1
          , nw.szrdgmr_term_ctlg_1
          , nw.szrdgmr_coll_code_1
          , nw.szrdgmr_majr_code_2
          , nw.szrdgmr_coll_code_2
          , nw.szrdgmr_term_ctlg_2
          , nw.szrdgmr_degs_code
          , nw.szrdgmr_grst_code
          , nw.szrdgmr_appl_date
          , nw.szrdgmr_grad_date
          , nw.szrdgmr_grad_term
          , nw.szrdgmr_fiscal_year
          , nw.szrdgmr_acad_year
          , nw.szrdgmr_minr_1
          , nw.szrdgmr_minr_2
          , nw.szrdgmr_minr_1_2
          , nw.szrdgmr_minr_2_2
          , nvl(nw.szrdgmr_seq_no,ol.szrdgmr_seq_no) as szrdgmr_seq_no
          , nw.szrdgmr_authorized
          , nw.szrdgmr_user_id
          , nw.row_hash
          , case when nw.szrdgmr_pidm is null then 'END CURRENT ROW'
                 when nw.row_hash != ol.row_hash then 'REPLACE CURRENT ROW'
                 when ol.szrdgmr_pidm is null then 'ADD NEW ROW'
            end as action
     from (select shrdgmr_pidm                                           szrdgmr_pidm
                , shrdgmr_levl_code                                      szrdgmr_levl_code
                , shrdgmr_camp_code                                      szrdgmr_camp_code
                , shrdgmr_program                                        szrdgmr_prog_code
                , shrdgmr_degc_code                                      szrdgmr_degc_code
                , shrdgmr_majr_code_1                                    szrdgmr_majr_code_1
                , shrdgmr_term_code_ctlg_1                               szrdgmr_term_ctlg_1
                , shrdgmr_coll_code_1                                    szrdgmr_coll_code_1
                , shrdgmr_majr_code_2                                    szrdgmr_majr_code_2
                , shrdgmr_coll_code_2                                    szrdgmr_coll_code_2
                , shrdgmr_term_code_ctlg_2                               szrdgmr_term_ctlg_2
                , shrdgmr_degs_code                                      szrdgmr_degs_code
                , shrdgmr_grst_code                                      szrdgmr_grst_code
                , shrdgmr_appl_date                                      szrdgmr_appl_date
                , shrdgmr_grad_date                                      szrdgmr_grad_date
                , shrdgmr_term_code_grad                                 szrdgmr_grad_term
                , lpad(to_char(ftvfsyr_fsyr_code-1)||ftvfsyr_fsyr_code,4,'0') szrdgmr_fiscal_year
                , stvterm_fa_proc_yr                                     szrdgmr_acad_year
                , shrdgmr_majr_code_minr_1                               szrdgmr_minr_1
                , shrdgmr_majr_code_minr_2                               szrdgmr_minr_2
                , shrdgmr_majr_code_minr_1_2                             szrdgmr_minr_1_2
                , shrdgmr_majr_code_minr_2_2                             szrdgmr_minr_2_2
                , shrdgmr_seq_no                                         szrdgmr_seq_no
                , shrdgmr_authorized                                     szrdgmr_authorized
                , shrdgmr_user_id                                        szrdgmr_user_id
                , standard_hash(shrdgmr_levl_code
                               ||'~'||shrdgmr_camp_code
                               ||'~'||shrdgmr_program
                               ||'~'||shrdgmr_degc_code
                               ||'~'||shrdgmr_majr_code_1
                               ||'~'||shrdgmr_term_code_ctlg_1
                               ||'~'||shrdgmr_coll_code_1
                               ||'~'||shrdgmr_majr_code_2
                               ||'~'||shrdgmr_coll_code_2
                               ||'~'||shrdgmr_term_code_ctlg_2
                               ||'~'||shrdgmr_degs_code
                               ||'~'||shrdgmr_grst_code
                               ||'~'||shrdgmr_appl_date
                               ||'~'||shrdgmr_grad_date
                               ||'~'||shrdgmr_term_code_grad
                               ||'~'||lpad(to_char(ftvfsyr_fsyr_code-1)||ftvfsyr_fsyr_code,4,'0')
                               ||'~'||stvterm_fa_proc_yr
                               ||'~'||shrdgmr_majr_code_minr_1
                               ||'~'||shrdgmr_majr_code_minr_2
                               ||'~'||shrdgmr_majr_code_minr_1_2
                               ||'~'||shrdgmr_majr_code_minr_2_2
                               ||'~'||shrdgmr_authorized
                               ||'~'||shrdgmr_user_id, 'MD5')            row_hash
           from shrdgmr
           left join ftvfsyr on shrdgmr_grad_date between ftvfsyr_start_date and ftvfsyr_end_date
                            and ftvfsyr_coas_code = 'U'
           left join stvterm on stvterm_code = shrdgmr_term_code_grad
           ) nw

           full join(select *
                     from utl_d_aim.szrdgmr
                     where szrdgmr_to_date = to_date('12/31/2099','MM/DD/YYYY') -- still active
                     ) ol on ol.szrdgmr_pidm = nw.szrdgmr_pidm
                         and ol.szrdgmr_seq_no = nw.szrdgmr_seq_no -- pidm and seq_no are the PK
           where nw.szrdgmr_pidm is null
              or ol.szrdgmr_pidm is null
              or nw.row_hash != ol.row_hash;

begin
  dbms_output.enable(NULL);

  dbms_output.put_line('SZRASGN Proc Started');

  for v_change in c_changes loop

    if(v_change.action in ('END CURRENT ROW','REPLACE CURRENT ROW')) then
           update utl_d_aim.szrdgmr dgmr
           set dgmr.szrdgmr_to_date = v_end_date
             , dgmr.szrdgmr_etl_date = v_etl_date
           where dgmr.szrdgmr_pidm = v_change.szrdgmr_pidm
             and dgmr.szrdgmr_seq_no = v_change.szrdgmr_seq_no
             and dgmr.szrdgmr_to_date = to_date('12/31/2099','MM/DD/YYYY');

           dbms_output.put_line('Ended: '||v_change.szrdgmr_pidm||' '||v_change.szrdgmr_seq_no);
       end if;

       if(v_change.action in ('REPLACE CURRENT ROW','ADD NEW ROW')) then
           insert into utl_d_aim.szrdgmr(szrdgmr_pidm,
                                         szrdgmr_levl_code,
                                         szrdgmr_camp_code,
                                         szrdgmr_prog_code,
                                         szrdgmr_degc_code,
                                         szrdgmr_majr_code_1,
                                         szrdgmr_term_ctlg_1,
                                         szrdgmr_coll_code_1,
                                         szrdgmr_majr_code_2,
                                         szrdgmr_coll_code_2,
                                         szrdgmr_term_ctlg_2,
                                         szrdgmr_degs_code,
                                         szrdgmr_grst_code,
                                         szrdgmr_appl_date,
                                         szrdgmr_grad_date,
                                         szrdgmr_grad_term,
                                         szrdgmr_fiscal_year,
                                         szrdgmr_acad_year,
                                         szrdgmr_minr_1,
                                         szrdgmr_minr_2,
                                         szrdgmr_minr_1_2,
                                         szrdgmr_minr_2_2,
                                         szrdgmr_seq_no,
                                         szrdgmr_authorized,
                                         szrdgmr_user_id,
                                         szrdgmr_etl_date,
                                         szrdgmr_from_date,
                                         szrdgmr_to_date,
                                         row_hash)
           values(v_change.szrdgmr_pidm,
                  v_change.szrdgmr_levl_code,
                  v_change.szrdgmr_camp_code,
                  v_change.szrdgmr_prog_code,
                  v_change.szrdgmr_degc_code,
                  v_change.szrdgmr_majr_code_1,
                  v_change.szrdgmr_term_ctlg_1,
                  v_change.szrdgmr_coll_code_1,
                  v_change.szrdgmr_majr_code_2,
                  v_change.szrdgmr_coll_code_2,
                  v_change.szrdgmr_term_ctlg_2,
                  v_change.szrdgmr_degs_code,
                  v_change.szrdgmr_grst_code,
                  v_change.szrdgmr_appl_date,
                  v_change.szrdgmr_grad_date,
                  v_change.szrdgmr_grad_term,
                  v_change.szrdgmr_fiscal_year,
                  v_change.szrdgmr_acad_year,
                  v_change.szrdgmr_minr_1,
                  v_change.szrdgmr_minr_2,
                  v_change.szrdgmr_minr_1_2,
                  v_change.szrdgmr_minr_2_2,
                  v_change.szrdgmr_seq_no,
                  v_change.szrdgmr_authorized,
                  v_change.szrdgmr_user_id,
                  v_etl_date,
                  v_etl_date,
                  to_date('12/31/2099','MM/DD/YYYY'),
                  v_change.row_hash
                  );
           dbms_output.put_line('Added: '||v_change.szrdgmr_pidm||' '||v_change.szrdgmr_seq_no);
       end if;

  end loop; --c_changes

  commit;

  dbms_output.put_line('SZRASGN Proc Ended');

exception
  when others then
   rollback;
   raise;

/*--------------------------------------------CHANGE LOG----------------------------------------
VERSION    DATE        USERNAME       UPDATES
1.0        09-28-2017  odavenport2    Initial release
1.1        09-18-2020  lxhatfield     added delim in the row check and changed to using hash
------------------------------------------------------------------------------------------------*/

end etl_aim_szrdgmr_refresh;

procedure etl_aim_szriden_refresh(jobnumber number, processid varchar2, processname varchar2, mod_number number) is
--
-- PURPOSE: Maintains a slowly changing person identity, demographic, and contact dimension—incl. IPEDS ethnicity/visa—for analytics and operational communications.
--
-- TABLE: utl_d_aim.szriden
--
-- UNIQUE INDEX: SZRIDEN_PIDM, SZRIDEN_TO_DATE
--
-- CONDITIONS:
-- Processes data in partitions: only PIDMs where MOD(PIDM, v_mod) = v_partition (default v_mod = 5); designed to run parallel DML with v_cpu workers.
-- Includes only the current identity rows from SPRIDEN (SPRiden_CHANGE_IND is NULL).
-- A row is (re)versioned when any tracked attribute differs from the current SZRIDEN row (the row with SZRIDEN_TO_DATE = 12/31/2099); otherwise no change is recorded.
-- When a change is detected, the existing current SZRIDEN row is end-dated to the ETL end timestamp (v_end_date) and a new current version is inserted with FROM_DATE = ETL run time and TO_DATE = 12/31/2099.
-- If no current SZRIDEN row exists for a PIDM, a new current row is inserted.
-- Current SZRIDEN rows (TO_DATE = 12/31/2099) are end-dated when the corresponding SPRIDEN PIDM no longer exists as a current record (SPRiden_CHANGE_IND is NULL).
-- Username (SZRIDEN_USERNAME) is sourced from GOBTPAC.EXTERNAL_USER when available.
-- Demographic attributes (SSN, birth date, marital, religion, sex, citizenship, confidentiality, deceased indicators/dates) come from SPBPERS for the same PIDM.
-- Email selection (from ZEXEC.ZSAVEMAL by PIDM):
--   - LU email: the address where EMAL_CODE IN ('LU','LUAD') AND EMAL_RANK = 1.
--   - Alternate (personal) email: highest available by EMAL_CODE_GROUP = 'PER' (group rank 1 then 2) excluding addresses ending in '@liberty.edu'.
--   - Parent emails: EMAL_CODE_GROUP = 'PG' (group ranks 1 and 2).
-- Email change protection: LU, alternate, and parent email fields do not trigger a version change if the new value is NULL (i.e., NULL cannot overwrite an existing non-NULL value).
-- Address selection (from ZEXEC.ZSAVADDR) uses the top ranked address (ADDR_RANK = '1') to populate street lines, city, state, ZIP, nation, and address type code.
-- Nation derivation (for SZRIDEN_NATION):
--   - If STATE is in a US state list (incl. DC), set to 'US';
--   - Else prefer GOBINTL.NATN_CODE_LEGAL when present;
--   - Else use ZSAVADDR.NATN_CODE; final display via TRIM(STVNATN.NATION).
-- Race detail (SZRIDEN_RACE_CODES) is built from GORPRAC by PIDM as a comma-separated LISTAGG of distinct race codes; RACE_CNT counts distinct races.
-- RCRAPP1 join uses only current records with INFC_CODE = 'EDE' and the most recent AIDY per PIDM.
-- Visa status join (GORVISA) considers only active visas as of the run date (SYSDATE BETWEEN VISA_START_DATE and VISA_EXPIRE_DATE) with non-resident types (STVVTYP.NON_RES_IND = 'Y').
-- IPEDS ethnicity classification (SZRIDEN_IPEDS_ETHN) is derived as:
--   - 'Nonresident_Alien' if RCRAPP1_CITZ_IND = '3', or if SPBPERS_CITZ_CODE <> 'NE' and an active qualifying visa exists.
--   - 'Hispanic_Latino' if SPBPERS_ETHN_CODE IN ('HL','MA','PR') OR SPBPERS_ETHN_CDE = '2' OR any GORPRAC code contains 'HO'.
--   - 'Two_or_more_races' if the distinct race count (RACE_CNT) = 2.
--   - Otherwise mapped by (first non-NULL of SPBPERS_ETHN_CODE or GORPRAC.RACES) to:
--       'AF' ? 'Black_or_African_American';
--       'AI' ? 'American_Indian_Alaska_Native';
--       'AS' ? 'Asian';
--       'HI' or 'PI' ? 'Native_Hawaiian_Pacific_Islander';
--       'WT' ? 'White';
--       else 'Unreported'.
-- IPEDS visa classification (SZRIDEN_IPEDS_VISA) is derived as:
--   - RCRAPP1_CITZ_IND = '1' ? 'US_National';
--   - RCRAPP1_CITZ_IND = '2' ? 'Permanent_Resident_Card';
--   - RCRAPP1_CITZ_IND = '3' ? 'Nonresident_Alien';
--   - Else if SPBPERS_CITZ_CODE = 'NE' ? 'Permanent_Resident_Card';
--   - Else if SPBPERS_CITZ_CODE = 'IL' ? 'Nonresident_Alien';
--   - Else if an active qualifying visa exists ? 'Nonresident_Alien';
--   - Otherwise ? 'US_National'.
-- Phone selection:
--   - Text-capable phone (SZRIDEN_PHONE_TEXT) from UTL_D_BIO.ZSAVTELT where TELE_US_VALID_RANK = 1, PHONE_COMBO is 10 digits, US_VALID_AREA = 'Y', STP_DATE is NULL, and not suppressed by an active APREXCL exclusion with codes in ('A01','A02','T01','T02').
--   - Primary phone (SZRIDEN_PHONE) from ZEXEC.ZSAVTELE where TELE_US_VALID_RANK = 1, PHONE_COMBO is 10 digits, US_VALID_AREA = 'Y', STP_DATE is NULL, and not suppressed by an active APREXCL exclusion with codes in ('A01','A02','V01','P01','P02').
-- All joins to optional sources (emails, phones, races, visas, international, address) are left joins; missing source data results in NULLs for those attributes without preventing the person row from being created.
-- The cursor selects DISTINCT PIDM-level rows to avoid duplicate processing within a partition.
--
-- URL: N/A

-- DECLARE
v_etl_date    DATE := SYSDATE;
v_partition    NUMBER := mod_number; -- mod_number; Jams parameter; defaulted to 0 if no partitioning is needed; **must be less than v_mod**
v_mod         NUMBER := 5; -- number of partitions; defaulted to 1 if no partitioning is needed; **must be greater than v_partition**
v_msg         VARCHAR2(2000 CHAR);
v_job_id      VARCHAR2(32);
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_cpu         NUMBER := 4; -- number of CPUs used for parallelization - do not exceed 20 CPUs [v_mod x v_cpu] if running simultaneously
v_proc        VARCHAR2(100) := 'etl_aim_szriden_refresh';
v_instance    VARCHAR2(100) := 'ALL';
v_end_date    DATE := v_etl_date - 1 / (24 * 60 * 60);
CURSOR c_terms IS
SELECT nw.*,
       CASE
       WHEN ol.szriden_pidm IS NULL THEN
        'INSERT_NEW_ROW'
       WHEN ((coalesce(nw.szriden_pidm, -1) <> coalesce(ol.szriden_pidm, -1)) OR (coalesce(nw.szriden_id, 'X') <> coalesce(ol.szriden_id, 'X')) OR (coalesce(nw.szriden_last_name, 'X') <> coalesce(ol.szriden_last_name, 'X')) OR
            (coalesce(nw.szriden_first_name, 'X') <> coalesce(ol.szriden_first_name, 'X')) OR (coalesce(nw.szriden_mi, 'X') <> coalesce(ol.szriden_mi, 'X')) OR (coalesce(nw.szriden_ssn, 'X') <> coalesce(ol.szriden_ssn, 'X')) OR
            (coalesce(nw.szriden_birth_date, v_etl_date) <> coalesce(ol.szriden_birth_date, v_etl_date)) OR (coalesce(nw.szriden_ethn_code, 'X') <> coalesce(ol.szriden_ethn_code, 'X')) OR
            (coalesce(nw.szriden_ethn_cde, 'X') <> coalesce(ol.szriden_ethn_cde, 'X')) OR (coalesce(nw.szriden_race_codes, 'X') <> coalesce(ol.szriden_race_codes, 'X')) OR
            (coalesce(nw.szriden_ipeds_ethn, 'X') <> coalesce(ol.szriden_ipeds_ethn, 'X')) OR (coalesce(nw.szriden_ipeds_visa, 'X') <> coalesce(ol.szriden_ipeds_visa, 'X')) OR
            (coalesce(nw.szriden_mrtl_code, 'X') <> coalesce(ol.szriden_mrtl_code, 'X')) OR (coalesce(nw.szriden_relg_code, 'X') <> coalesce(ol.szriden_relg_code, 'X')) OR (coalesce(nw.szriden_sex, 'X') <> coalesce(ol.szriden_sex, 'X')) OR
            (coalesce(nw.szriden_citz_code, 'X') <> coalesce(ol.szriden_citz_code, 'X')) OR (coalesce(nw.szriden_confid_ind, 'X') <> coalesce(ol.szriden_confid_ind, 'X')) OR
            (coalesce(nw.szriden_dead_ind, 'X') <> coalesce(ol.szriden_dead_ind, 'X')) OR (coalesce(nw.szriden_dead_date, v_etl_date) <> coalesce(ol.szriden_dead_date, v_etl_date)) OR
            (coalesce(nw.szriden_street_line1, 'X') <> coalesce(ol.szriden_street_line1, 'X')) OR (coalesce(nw.szriden_street_line2, 'X') <> coalesce(ol.szriden_street_line2, 'X')) OR
            (coalesce(nw.szriden_city, 'X') <> coalesce(ol.szriden_city, 'X')) OR (coalesce(nw.szriden_stat_code, 'X') <> coalesce(ol.szriden_stat_code, 'X')) OR (coalesce(nw.szriden_zip5, 'X') <> coalesce(ol.szriden_zip5, 'X')) OR
            (coalesce(nw.szriden_nation, 'X') <> coalesce(ol.szriden_nation, 'X')) OR (coalesce(nw.szriden_atyp_code, 'X') <> coalesce(ol.szriden_atyp_code, 'X')) OR
            (coalesce(nw.szriden_lu_email, 'X') <> coalesce(ol.szriden_lu_email, 'X')) OR (coalesce(nw.szriden_alt_email, 'X') <> coalesce(ol.szriden_alt_email, 'X')) OR
            (coalesce(nw.szriden_parent_email_1, 'X') <> coalesce(ol.szriden_parent_email_1, 'X')) OR (coalesce(nw.szriden_parent_email_2, 'X') <> coalesce(ol.szriden_parent_email_2, 'X')) OR
            (coalesce(nw.szriden_phone, 'X') <> coalesce(ol.szriden_phone, 'X')) OR (coalesce(nw.szriden_phone_text, 'X') <> coalesce(ol.szriden_phone_text, 'X')) OR
            (coalesce(nw.szriden_username, 'X') <> coalesce(ol.szriden_username, 'X'))) THEN
        'END_EXISTING_ROW'
       END action
  FROM (SELECT DISTINCT spriden_pidm szriden_pidm,
                        spriden_id szriden_id,
                        spriden_last_name szriden_last_name,
                        spriden_first_name szriden_first_name,
                        spriden_mi szriden_mi,
                        spbpers_ssn szriden_ssn,
                        spbpers_birth_date szriden_birth_date,
                        gobtpac_external_user szriden_username,
                        spbpers_ethn_code szriden_ethn_code,
                        spbpers_ethn_cde szriden_ethn_cde,
                        gorprac.races szriden_race_codes,
                        CASE
                        WHEN nvl(rcrapp1_citz_ind, 'X') = '3' THEN
                         'Nonresident_Alien'
                        WHEN nvl(spbpers_citz_code, 'X') <> 'NE'
                             AND visa.gorvisa_pidm IS NOT NULL THEN
                         'Nonresident_Alien'
                        WHEN spbpers_ethn_code IN ('HL', 'MA', 'PR')
                             OR spbpers_ethn_cde = '2'
                             OR gorprac.races LIKE '%HO%' THEN
                         'Hispanic_Latino'
                        WHEN race_cnt >= 2 THEN
                         'Two_or_more_races'
                        WHEN nvl(spbpers_ethn_code, gorprac.races) = 'AF' THEN
                         'Black_or_African_American'
                        WHEN nvl(spbpers_ethn_code, gorprac.races) = 'AI' THEN
                         'American_Indian_Alaska_Native'
                        WHEN nvl(spbpers_ethn_code, gorprac.races) = 'AS' THEN
                         'Asian'
                        WHEN nvl(spbpers_ethn_code, gorprac.races) IN ('HI', 'PI') THEN
                         'Native_Hawaiian_Pacific_Islander'
                        WHEN nvl(spbpers_ethn_code, gorprac.races) = 'WT' THEN
                         'White'
                        WHEN nvl(spbpers_ethn_code, gorprac.races) = 'AF' THEN
                         'Black_or_African_American'
                        WHEN nvl(spbpers_ethn_code, gorprac.races) = 'AI' THEN
                         'American_Indian_Alaska_Native'
                        WHEN nvl(spbpers_ethn_code, gorprac.races) = 'AS' THEN
                         'Asian'
                        WHEN nvl(spbpers_ethn_code, gorprac.races) IN ('HI', 'PI') THEN
                         'Native_Hawaiian_Pacific_Islander'
                        WHEN nvl(spbpers_ethn_code, gorprac.races) = 'WT' THEN
                         'White'
                        ELSE
                         'Unreported'
                        END szriden_ipeds_ethn,
                        CASE
                        WHEN nvl(rcrapp1_citz_ind, 'X') = '1' THEN
                         'US_National'
                        WHEN nvl(rcrapp1_citz_ind, 'X') = '2' THEN
                         'Permanent_Resident_Card'
                        WHEN nvl(rcrapp1_citz_ind, 'X') = '3' THEN
                         'Nonresident_Alien'
                        WHEN spbpers_citz_code = 'NE' THEN
                         'Permanent_Resident_Card'
                        WHEN spbpers_citz_code = 'IL' THEN
                         'Nonresident_Alien'
                        WHEN visa.gorvisa_pidm IS NOT NULL THEN
                         'Nonresident_Alien'
                        ELSE
                         'US_National'
                        END szriden_ipeds_visa,
                        spbpers_mrtl_code szriden_mrtl_code,
                        spbpers_relg_code szriden_relg_code,
                        spbpers_sex szriden_sex,
                        spbpers_citz_code szriden_citz_code,
                        spbpers_confid_ind szriden_confid_ind,
                        spbpers_dead_ind szriden_dead_ind,
                        spbpers_dead_date szriden_dead_date,
                        zsavaddr.street_line1 szriden_street_line1,
                        zsavaddr.street_line2 szriden_street_line2,
                        zsavaddr.city szriden_city,
                        zsavaddr.stat_code szriden_stat_code,
                        zsavaddr.zip5 szriden_zip5,
                        TRIM(stvnatn_nation) szriden_nation,
                        zsavaddr.atyp_code szriden_atyp_code,
                        zsavemal.lu_email szriden_lu_email,
                        zsavemal.alt_email szriden_alt_email,
                        zsavemal.parent_email_1 szriden_parent_email_1,
                        zsavemal.parent_email_2 szriden_parent_email_2,
                        phne.phone_combo szriden_phone,
                        txt.phone_combo szriden_phone_text
          FROM spriden
          JOIN spbpers
            ON spbpers_pidm = spriden_pidm
           AND MOD(spriden_pidm, v_mod) = v_partition
          LEFT JOIN (SELECT z.pidm,
                           MAX(CASE
                 WHEN z.emal_code = 'LU'
                  AND z.emal_rank = 1 THEN
                z.email_address
                 WHEN z.emal_code = 'LUAD'
                  AND z.emal_rank = 1 THEN
                z.email_address
                 END) lu_email,
                           MAX(CASE
                               WHEN z.emal_code_group = 'PER'
                                    AND z.emal_code_group_rank = 1
                                    AND lower(z.email_address) NOT LIKE '%@liberty.edu' THEN
                                z.email_address
                               WHEN z.emal_code_group = 'PER'
                                    AND z.emal_code_group_rank = 2
                                    AND lower(z.email_address) NOT LIKE '%@liberty.edu' THEN
                                z.email_address
                               END) alt_email,
                           MAX(CASE
                               WHEN z.emal_code_group = 'PG'
                                    AND z.emal_code_group_rank = 1 THEN
                                z.email_address
                               END) parent_email_1,
                           MAX(CASE
                               WHEN z.emal_code_group = 'PG'
                                    AND z.emal_code_group_rank = 2 THEN
                                z.email_address
                               END) parent_email_2
                      FROM zexec.zsavemal z
                     WHERE MOD(z.pidm, v_mod) = v_partition
                     GROUP BY z.pidm) zsavemal
            ON zsavemal.pidm = spriden_pidm
          LEFT JOIN (SELECT gorprac_pidm,
                           COUNT(DISTINCT gorprac_race_cde) race_cnt,
                           listagg(gorprac_race_cde, ',') within GROUP(ORDER BY gorprac_race_cde) races
                      FROM gorprac
                     WHERE 1 = 1
                       AND MOD(gorprac_pidm, v_mod) = v_partition
                     GROUP BY gorprac_pidm) gorprac
            ON gorprac_pidm = spriden_pidm
          LEFT JOIN (SELECT rcrapp1_pidm,
                           rcrapp1_citz_ind
                      FROM rcrapp1
                     WHERE rcrapp1_curr_rec_ind = 'Y'
                       AND MOD(rcrapp1_pidm, v_mod) = v_partition
                       AND rcrapp1_infc_code = 'EDE'
                       AND rcrapp1_aidy_code = (SELECT MAX(d.rcrapp1_aidy_code)
                                                  FROM rcrapp1 d
                                                 WHERE d.rcrapp1_pidm = rcrapp1.rcrapp1_pidm
                                                   AND d.rcrapp1_curr_rec_ind = 'Y'
                                                   AND d.rcrapp1_infc_code = 'EDE')) rcrapp
            ON rcrapp.rcrapp1_pidm = spriden_pidm
          LEFT JOIN (SELECT DISTINCT gorvisa_pidm
                      FROM gorvisa
                      JOIN stvvtyp
                        ON stvvtyp_code = gorvisa_vtyp_code
                       AND nvl(stvvtyp_non_res_ind, 'N') = 'Y'
                     WHERE 1 = 1
                       AND MOD(gorvisa_pidm, v_mod) = v_partition
                       AND SYSDATE BETWEEN nvl(gorvisa_visa_start_date, to_date('01-JAN-1900', 'DD-MON-YYYY')) AND nvl(gorvisa_visa_expire_date, to_date('31-DEC-2099', 'DD-MON-YYYY'))) visa
            ON visa.gorvisa_pidm = spriden_pidm
          LEFT JOIN general.gobintl
            ON gobintl_pidm = spriden_pidm
           AND TRIM(gobintl_natn_code_legal) IS NOT NULL
          LEFT JOIN general.gobtpac
            ON gobtpac_pidm = spriden_pidm
          LEFT JOIN zexec.zsavaddr
            ON zsavaddr.pidm = spriden_pidm
           AND zsavaddr.addr_rank = '1'
          LEFT JOIN stvnatn
            ON stvnatn_code = coalesce(CASE
                                        WHEN zsavaddr.stat_code IN
                                             ('AL', 'AK', 'AZ', 'AR', 'CA', 'CO', 'CT', 'DC', 'DE', 'FL', 'GA', 'HI', 'ID', 'IL', 'IN', 'IA', 'KS', 'KY', 'LA', 'ME', 'MD', 'MA', 'MI', 'MN', 'MS', 'MO', 'MT', 'NE', 'NV', 'NJ', 'NM', 'NY', 'NC', 'ND', 'OH', 'OK', 'OR', 'PA', 'RI', 'NH', 'SC', 'SD', 'TN', 'TX', 'UT', 'VT', 'VA', 'WA', 'WV', 'WI', 'WY') THEN
                                         'US'
                                        END, gobintl_natn_code_legal, zsavaddr.natn_code)
          LEFT JOIN (SELECT text.pidm,
                           text.phone_combo
                      FROM utl_d_bio.zsavtelt text
                     WHERE text.tele_us_valid_rank = 1
                       AND MOD(text.pidm, v_mod) = v_partition
                       AND text.phone_combo IS NOT NULL
                       AND text.stp_date IS NULL
                       AND length(text.phone_combo) = 10
                       AND text.us_valid_area = 'Y'
                       AND NOT EXISTS (SELECT 'X'
                              FROM aprexcl
                             WHERE aprexcl_pidm = text.pidm
                               AND aprexcl_excl_code IN ('A01', 'A02', 'T01', 'T02')
                               AND aprexcl_date < SYSDATE
                               AND (aprexcl_end_date >= trunc(SYSDATE) OR aprexcl_end_date IS NULL))) txt
            ON txt.pidm = spriden_pidm
          LEFT JOIN (SELECT tele.pidm,
                           tele.phone_combo
                      FROM zexec.zsavtele tele
                     WHERE tele.tele_us_valid_rank = 1
                       AND MOD(tele.pidm, v_mod) = v_partition
                       AND tele.phone_combo IS NOT NULL
                       AND tele.stp_date IS NULL
                       AND length(tele.phone_combo) = 10
                       AND tele.us_valid_area = 'Y'
                       AND NOT EXISTS (SELECT 'X'
                              FROM aprexcl
                             WHERE aprexcl_pidm = tele.pidm
                               AND aprexcl_excl_code IN ('A01', 'A02', 'V01', 'P01', 'P02')
                               AND aprexcl_date < SYSDATE
                               AND (aprexcl_end_date >= trunc(SYSDATE) OR aprexcl_end_date IS NULL))) phne
            ON phne.pidm = spriden_pidm
         WHERE spriden_change_ind IS NULL) nw
  LEFT JOIN utl_d_aim.szriden ol
    ON ol.szriden_pidm = nw.szriden_pidm
   AND ol.szriden_to_date = to_date('12/31/2099', 'MM/DD/YYYY')
   AND MOD(ol.szriden_pidm, v_mod) = v_partition
 WHERE ol.szriden_pidm IS NULL
    OR (coalesce(nw.szriden_pidm, -1) <> coalesce(ol.szriden_pidm, -1))
    OR (coalesce(nw.szriden_id, 'X') <> coalesce(ol.szriden_id, 'X'))
    OR (coalesce(nw.szriden_last_name, 'X') <> coalesce(ol.szriden_last_name, 'X'))
    OR (coalesce(nw.szriden_first_name, 'X') <> coalesce(ol.szriden_first_name, 'X'))
    OR (coalesce(nw.szriden_mi, 'X') <> coalesce(ol.szriden_mi, 'X'))
    OR (coalesce(nw.szriden_ssn, 'X') <> coalesce(ol.szriden_ssn, 'X'))
    OR (coalesce(nw.szriden_birth_date, v_etl_date) <> coalesce(ol.szriden_birth_date, v_etl_date))
    OR (coalesce(nw.szriden_ethn_code, 'X') <> coalesce(ol.szriden_ethn_code, 'X'))
    OR (coalesce(nw.szriden_ethn_cde, 'X') <> coalesce(ol.szriden_ethn_cde, 'X'))
    OR (coalesce(nw.szriden_race_codes, 'X') <> coalesce(ol.szriden_race_codes, 'X'))
    OR (coalesce(nw.szriden_ipeds_ethn, 'X') <> coalesce(ol.szriden_ipeds_ethn, 'X'))
    OR (coalesce(nw.szriden_ipeds_visa, 'X') <> coalesce(ol.szriden_ipeds_visa, 'X'))
    OR (coalesce(nw.szriden_mrtl_code, 'X') <> coalesce(ol.szriden_mrtl_code, 'X'))
    OR (coalesce(nw.szriden_relg_code, 'X') <> coalesce(ol.szriden_relg_code, 'X'))
    OR (coalesce(nw.szriden_sex, 'X') <> coalesce(ol.szriden_sex, 'X'))
    OR (coalesce(nw.szriden_citz_code, 'X') <> coalesce(ol.szriden_citz_code, 'X'))
    OR (coalesce(nw.szriden_confid_ind, 'X') <> coalesce(ol.szriden_confid_ind, 'X'))
    OR (coalesce(nw.szriden_dead_ind, 'X') <> coalesce(ol.szriden_dead_ind, 'X'))
    OR (coalesce(nw.szriden_dead_date, v_etl_date) <> coalesce(ol.szriden_dead_date, v_etl_date))
    OR (coalesce(nw.szriden_street_line1, 'X') <> coalesce(ol.szriden_street_line1, 'X'))
    OR (coalesce(nw.szriden_street_line2, 'X') <> coalesce(ol.szriden_street_line2, 'X'))
    OR (coalesce(nw.szriden_city, 'X') <> coalesce(ol.szriden_city, 'X'))
    OR (coalesce(nw.szriden_stat_code, 'X') <> coalesce(ol.szriden_stat_code, 'X'))
    OR (coalesce(nw.szriden_zip5, 'X') <> coalesce(ol.szriden_zip5, 'X'))
    OR (coalesce(nw.szriden_nation, 'X') <> coalesce(ol.szriden_nation, 'X'))
    OR (coalesce(nw.szriden_atyp_code, 'X') <> coalesce(ol.szriden_atyp_code, 'X'))
    OR (coalesce(nw.szriden_lu_email, 'X') <> coalesce(ol.szriden_lu_email, 'X') AND (nw.szriden_lu_email IS NOT NULL)) -- THIS IS DIFFERENT; DO NOT ALLOW UPDATES TO BE NULL
    OR (coalesce(nw.szriden_alt_email, 'X') <> coalesce(ol.szriden_alt_email, 'X') AND (nw.szriden_alt_email IS NOT NULL)) -- THIS IS DIFFERENT; DO NOT ALLOW UPDATES TO BE NULL
    OR (coalesce(nw.szriden_parent_email_1, 'X') <> coalesce(ol.szriden_parent_email_1, 'X') AND (nw.szriden_parent_email_1 IS NOT NULL)) -- THIS IS DIFFERENT; DO NOT ALLOW UPDATES TO BE NULL
    OR (coalesce(nw.szriden_parent_email_2, 'X') <> coalesce(ol.szriden_parent_email_2, 'X') AND (nw.szriden_parent_email_2 IS NOT NULL)) -- THIS IS DIFFERENT; DO NOT ALLOW UPDATES TO BE NULL
    OR (coalesce(nw.szriden_phone, 'X') <> coalesce(ol.szriden_phone, 'X'))
    OR (coalesce(nw.szriden_phone_text, 'X') <> coalesce(ol.szriden_phone_text, 'X'))
    OR (coalesce(nw.szriden_username, 'X') <> coalesce(ol.szriden_username, 'X'));
BEGIN
dbms_output.enable(10000000);
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
v_msg     := 'START - ' || rec.szriden_pidm || ' - ' || rec.action || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
-- KEEP COUNT BUT DO NOT OUTPUT
-- dbms_output.put_line(v_msg);
-- ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- end records where the data has changed
IF rec.action = 'END_EXISTING_ROW' THEN
UPDATE /*+*/ utl_d_aim.szriden t
   SET t.szriden_to_date  = v_end_date,
       t.szriden_etl_date = v_etl_date
 WHERE t.szriden_pidm = rec.szriden_pidm
   AND t.szriden_to_date = to_date('12/31/2099', 'MM/DD/YYYY');
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'UPDATE - ' || rec.szriden_pidm || ' - ' || rec.action || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
-- KEEP COUNT BUT DO NOT OUTPUT
-- dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
-- ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- dbms_output.put_line(' --------- ');
END IF;
-- insert new record or new version of record ended above
INSERT /*+*/
INTO utl_d_aim.szriden
(szriden_pidm,
 szriden_id,
 szriden_last_name,
 szriden_first_name,
 szriden_mi,
 szriden_ssn,
 szriden_birth_date,
 szriden_ethn_code,
 szriden_ethn_cde,
 szriden_race_codes,
 szriden_ipeds_ethn,
 szriden_ipeds_visa,
 szriden_mrtl_code,
 szriden_relg_code,
 szriden_sex,
 szriden_citz_code,
 szriden_confid_ind,
 szriden_dead_ind,
 szriden_dead_date,
 szriden_street_line1,
 szriden_street_line2,
 szriden_city,
 szriden_stat_code,
 szriden_zip5,
 szriden_nation,
 szriden_atyp_code,
 szriden_lu_email,
 szriden_alt_email,
 szriden_parent_email_1,
 szriden_parent_email_2,
 szriden_phone,
 szriden_phone_text,
 szriden_username,
 szriden_etl_date,
 szriden_from_date,
 szriden_to_date)
VALUES
(rec.szriden_pidm,
 rec.szriden_id,
 rec.szriden_last_name,
 rec.szriden_first_name,
 rec.szriden_mi,
 rec.szriden_ssn,
 rec.szriden_birth_date,
 rec.szriden_ethn_code,
 rec.szriden_ethn_cde,
 rec.szriden_race_codes,
 rec.szriden_ipeds_ethn,
 rec.szriden_ipeds_visa,
 rec.szriden_mrtl_code,
 rec.szriden_relg_code,
 rec.szriden_sex,
 rec.szriden_citz_code,
 rec.szriden_confid_ind,
 rec.szriden_dead_ind,
 rec.szriden_dead_date,
 rec.szriden_street_line1,
 rec.szriden_street_line2,
 rec.szriden_city,
 rec.szriden_stat_code,
 rec.szriden_zip5,
 rec.szriden_nation,
 rec.szriden_atyp_code,
 rec.szriden_lu_email,
 rec.szriden_alt_email,
 rec.szriden_parent_email_1,
 rec.szriden_parent_email_2,
 rec.szriden_phone,
 rec.szriden_phone_text,
 rec.szriden_username,
 v_etl_date,
 v_etl_date,
 to_date('12/31/2099', 'MM/DD/YYYY'));
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || rec.szriden_pidm || ' - ' || rec.action || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
-- KEEP COUNT BUT DO NOT OUTPUT
-- dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
-- ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- dbms_output.put_line(' --------- ');
END LOOP; -- inserts loop
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ALL - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
-- End records that don't exist in spriden anymore
UPDATE /*+*/ utl_d_aim.szriden
   SET szriden_to_date  = v_end_date,
       szriden_etl_date = v_etl_date
 WHERE szriden_to_date = to_date('12/31/2099', 'MM/DD/YYYY')
   AND MOD(szriden_pidm, v_mod) = v_partition
   AND NOT EXISTS (SELECT 'X'
          FROM spriden
         WHERE spriden_change_ind IS NULL
           AND spriden_pidm = szriden_pidm);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'UPDATE - ALL - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
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
VERSION    DATE        USERNAME       UPDATES
1.0        09-28-2017  odavenport2    --Initial release
2.0        10-30-2017  wruminn          --fixed two or more races logic in SZRIDEN
3.0        7-23-2019   kcaldwell        --added username, additional contact info
---       01-05-2024  mapeele      --update to szriden_ipeds_ethn
---       07-15-2024  wgriffith2      --adding partitions to reduce temp space errors
---       10-06-2025  wgriffith2      --not allowing a NULL LU email to overwrite an existing one; related to zsavemal truncate/reload on the DW;
---       10-09-2025  wgriffith2      --added all email fields on 10/9 bc we were still catching the null changes in the non-lu emails
---       10-10-2025  clreid2      -- update the "LEFT JOIN stvnatn" to get state code first then its a toss up between gobintl_natn_code_legal or w/e the student has in zsavaddr
---       10-23-2025  wgriffith2      -- no code changes, but running hotfix to update the first record found for each pidm to push the from date to beginning of time
---       11-12-2025  wgriffith2      --changing the email code to get the LU email using z.emal_rank = 1
------------------------------------------------------------------------------------------------*/
END etl_aim_szriden_refresh;

procedure etl_aim_szrcrse_refresh(jobnumber number, processid varchar2, processname varchar2, mod_number number) is
--
-- PURPOSE: Maintains a transactional student course history with enrollment, section, instructor, and final grade details for active and recent terms, and immediately reflects Banner grade changes into LMS progress.
--
-- TABLE: utl_d_aim.szrcrse
--
-- UNIQUE INDEX: PIDM, TERM_CODE, CRN
--
-- CONDITIONS:
-- Processes terms by group: STD and MED terms from 180 days before the term start through 180 days after the term end; ACD terms from 180 days before the term start through 365 days after the term end.
-- Once daily after midnight, additionally processes any non-active terms (outside the windows above) where a final grade change was recorded in the last 24 hours, limited to Banner terms from 200740 forward and to the current parallel partition.
-- Includes only section enrollments where the registration status is flagged as “include section enrollment” (STVRSTS_INCL_SECT_ENRL = 'Y').
-- Excludes sections with subject code 'NEWS'.
-- For STD and MED terms, includes only student levels that award credit (SZRLEVL_HAS_AWARDABLE_CRED = 'Y'); for ACD terms, PD-level enrollments (e.g., clubs) and EM sections are allowed.
-- Limits processing to the parallel partition specified by MOD(PIDM, v_mod) = v_partition; the same partitioning is applied when detecting grade changes and when comparing to existing SZRCRSE rows.
-- Associates each enrollment to a term group (STD, MED, or ACD) and derives the financial aid processing year and semester from zbtm.terms_by_group_v.
-- Derives course title from the section title when present; otherwise uses the catalog title (SCBCRSE).
-- Populates college and department from the latest SCBCRSE catalog record effective on or before the section term; this join is required for STD/MED and optional for ACD.
-- Derives instruction method code and description from GTVINSM when available.
-- Captures student identity and faculty identity only when the identity record (SZRIDEN) is active at the ETL timestamp.
-- Includes only the primary instructor assignment for each section (SIRASGN_PRIMARY_IND = 'Y').
-- Calculates course display code (CRSDISP/TOPS) from SCBSUPP using the most recent effective term not after the section term and pads to 4 digits.
-- Sets part-of-term dates for STD/MED directly from SSBSECT; for ACD, uses SFRAREG start/completion dates when present, otherwise SSBSECT; end dates are set to 23:59:59 of the computed day.
-- For ACD terms, overrides the end date based on subject/number or credit hours:
--   LAN 2170 or 2180: 41 weeks after start
--   LAN 2171, 2172, or 2182: 22 weeks after start
--   0.500 credit hours: 22 weeks after start
--   1.000 credit hour: 41 weeks after start
--   0.25 credit hour: 12 weeks after start
--   0 credit hours: 41 weeks after start
-- Populates final grade from SHRTCKG (latest grade change record per enrollment) when available; otherwise uses SFRSTCR grade code.
-- Sets grade date to the SHRTCKG final grade change date when present; otherwise uses the SFRSTCR grade date.
-- Looks up grade quality points and numeric values from SHRGRDE by student level using the latest effective grading rule on or before the section term.
-- Sets adjusted quality points to NULL when the grade does not count toward GPA and the grade code is not one of W, FN, WP, WF, or PR; otherwise equals the standard quality points.
-- Includes schedule code, campus code, integration code, add date, and billing hours (SFRSTCR_BILL_HR) for each enrollment.
-- Compares source rows to existing SZRCRSE rows and performs inserts, updates, or deletes only when the record is new, removed from the source, or any field has changed for the same PIDM, TERM_CODE, and CRN.
-- After refreshing SZRCRSE, immediately updates LMS student_progress (final_grade and final_grade_date) for matching enrollments where SZRCRSE’s final grade differs, limited to the same parallel partition.
-- Excludes pre-Banner terms; all processing is restricted to terms from 200740 onward.
-- Processes data term-by-term and in bulk (up to 1,000,000 rows per fetch) to support incremental refresh.
--
--DECLARE
v_etl_date    DATE := SYSDATE;
v_partition    NUMBER := mod_number; -- mod_number; Jams parameter; defaulted to 0 if no partitioning is needed; **must be less than v_mod**
v_mod         NUMBER := 5; -- number of partitions; defaulted to 1 if no partitioning is needed; **must be greater than v_partition**
v_msg         VARCHAR2(2000 CHAR);
v_job_id      VARCHAR2(32);
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_row_max     NUMBER := 1000000; -- max number of rows to be processed at one time
--v_cpu         NUMBER := 4; -- number of CPUs used for parallelization - do not exceed 20 CPUs [v_mod x v_cpu] if running simultaneously
v_proc        VARCHAR2(100) := 'etl_aim_szrcrse_refresh';
v_instance    VARCHAR2(100) := 'ALL';
v_retry_count NUMBER := 0;
v_max_retries NUMBER := 3; -- number of retries for WAIT
v_wait_time   NUMBER := 60; -- seconds for WAIT
CURSOR c_terms IS
SELECT t.term_code,
       t.group_code
  FROM zbtm.terms_by_group_v t
 WHERE 1 = 1
   AND ((t.group_code IN ('STD') AND SYSDATE >= t.start_date - 180 AND SYSDATE <= t.end_date + 180) --
       OR (t.group_code IN ('MED') AND SYSDATE >= t.start_date - 180 AND SYSDATE <= t.end_date + 180) -- run once a day only
       OR (t.group_code IN ('ACD') AND SYSDATE >= t.start_date - 180 AND SYSDATE <= t.end_date + 365))
UNION
-- ONCE A DAY AFTER MIDNIGHT, CHECK FOR ANY GRADE CHANGES ON NON-ACTIVE TERMS
SELECT DISTINCT shrtckg_term_code AS term_code,
                gc.group_code     AS group_code
  FROM saturn.shrtckg
  JOIN (SELECT group_code,
               term_code
          FROM zbtm.terms_by_group_v t
         WHERE 1 = 1
           AND t.group_code IN ('STD', 'ACD', 'MED')) gc
    ON gc.term_code = shrtckg_term_code
 WHERE 1 = 1
   AND to_char(SYSDATE, 'HH24') IN ('00') -- run once a day only
   AND shrtckg_final_grde_chg_date > SYSDATE - 1 -- check for any grade changes
   AND MOD(shrtckg_pidm, v_mod) = v_partition
   AND shrtckg_term_code >= '200740'
   AND NOT EXISTS (SELECT t.term_code,
               t.group_code
          FROM zbtm.terms_by_group_v t
         WHERE 1 = 1
           AND t.term_code = shrtckg_term_code
           AND ((t.group_code IN ('STD') AND SYSDATE >= t.start_date - 180 AND SYSDATE <= t.end_date + 180) --
               OR (t.group_code IN ('MED') AND SYSDATE >= t.start_date - 180 AND SYSDATE <= t.end_date + 180) -- run once a day only
               OR (t.group_code IN ('ACD') AND SYSDATE >= t.start_date - 180 AND SYSDATE <= t.end_date + 365)))
 ORDER BY group_code DESC,
          1          DESC;
CURSOR c1(v_term_code  VARCHAR,
          v_group_code VARCHAR) IS
SELECT COUNT(*) over() total_rows,
       CASE
       WHEN tblnew.pidm IS NOT NULL
            AND tblold.pidm IS NULL THEN
        'INSERT' -- new record to source, add to table
       WHEN tblnew.pidm IS NOT NULL
            AND tblold.pidm IS NOT NULL THEN
        'UPDATE' -- record exists in both places
       WHEN tblnew.pidm IS NULL
            AND tblold.pidm IS NOT NULL THEN
        'DELETE' -- no record longer exists on the source data, remove it
       END AS control_state,
       coalesce(tblnew.pidm, tblold.pidm) AS pidm,
       tblnew.acad_year,
       coalesce(tblnew.term_code, tblold.term_code) AS term_code,
       tblnew.ptrm_code,
       tblnew.group_code,
       tblnew.semester,
       tblnew.ptrm_start,
       tblnew.ptrm_end,
       tblnew.subj,
       tblnew.numb,
       tblnew.course,
       tblnew.sect,
       coalesce(tblnew.crn, tblold.crn) AS crn,
       tblnew.rsts_code,
       tblnew.title,
       tblnew.camp_code,
       tblnew.insm_code,
       tblnew.insm_desc,
       tblnew.credit_hr,
       tblnew.levl_code,
       tblnew.college,
       tblnew.coll_code,
       tblnew.crsdisp,
       tblnew.department,
       tblnew.dept_code,
       tblnew.final_grade,
       tblnew.grade_date,
       tblnew.grade_quality_points,
       tblnew.grade_adj_quality_points,
       tblnew.grade_numeric_value,
       tblnew.faculty_id,
       tblnew.faculty_pidm,
       tblnew.faculty_last_name,
       tblnew.faculty_first_name,
       tblnew.activity_date,
       tblnew.schd_code,
       tblnew.add_date,
       tblnew.intg_code,
       tblnew.faculty_email,
       tblnew.billing_hr
  FROM (
        -- STD and MED terms
        SELECT DISTINCT sfrstcr_pidm pidm, -- distinct because of szriden_pidm = 13804536
                         tbg.fa_proc_year acad_year,
                         sfrstcr_term_code term_code,
                         ssbsect_ptrm_code ptrm_code,
                         tbg.group_code group_code,
                         tbg.semester semester,
                         ssbsect_ptrm_start_date ptrm_start,
                         ssbsect_ptrm_end_date ptrm_end,
                         ssbsect_subj_code subj,
                         ssbsect_crse_numb numb,
                         ssbsect_subj_code || ssbsect_crse_numb course,
                         ssbsect_seq_numb sect,
                         ssbsect_crn crn,
                         sfrstcr_rsts_code rsts_code,
                         coalesce(ssbsect_crse_title, scbcrse_title) title,
                         ssbsect_camp_code camp_code,
                         ssbsect_insm_code insm_code,
                         gtvinsm_desc insm_desc,
                         sfrstcr_credit_hr credit_hr,
                         sfrstcr_levl_code levl_code,
                         stvcoll_desc college,
                         stvcoll_code coll_code,
                         lpad(a.crsdisp, 4, 0) crsdisp,
                         stvdept_desc department,
                         stvdept_code dept_code,
                         coalesce(grde.final_grade, sfrstcr_grde_code) AS final_grade,
                         coalesce(grde.grade_change_date, sfrstcr_grde_date) AS grade_date,
                         grde.grade_quality_points,
                         grde.grade_adj_quality_points,
                         grde.grade_numeric_value,
                         faculty.szriden_id faculty_id,
                         faculty.szriden_pidm faculty_pidm,
                         faculty.szriden_last_name faculty_last_name,
                         faculty.szriden_first_name faculty_first_name,
                         v_etl_date activity_date,
                         ssbsect_schd_code schd_code,
                         sfrstcr_add_date add_date,
                         ssbsect_intg_cde intg_code,
                         faculty.szriden_lu_email faculty_email,
                         sfrstcr.sfrstcr_bill_hr billing_hr
          FROM sfrstcr
          JOIN stvrsts
            ON stvrsts_code = sfrstcr_rsts_code
           AND stvrsts_incl_sect_enrl = 'Y'
           AND sfrstcr_term_code = v_term_code
           AND MOD(sfrstcr_pidm, v_mod) = v_partition
          JOIN zsaturn.szrlevl l
            ON l.szrlevl_levl_code = sfrstcr_levl_code
           AND l.szrlevl_has_awardable_cred = 'Y'
          JOIN ssbsect
            ON ssbsect_term_code = sfrstcr_term_code
           AND ssbsect_crn = sfrstcr_crn
           AND ssbsect_subj_code <> 'NEWS'
          JOIN utl_d_aim.szriden
            ON szriden_pidm = sfrstcr_pidm
           AND v_etl_date BETWEEN szriden_from_date AND szriden_to_date
          JOIN zbtm.terms_by_group_v tbg
            ON tbg.term_code = sfrstcr_term_code
           AND tbg.group_code = v_group_code
           AND v_group_code <> 'ACD' -- DO NOT REMOVE HARD CODED VALUE
          LEFT JOIN saturn.scbcrse
            ON scbcrse_subj_code = ssbsect_subj_code
           AND scbcrse_crse_numb = ssbsect_crse_numb
           AND scbcrse_eff_term = (SELECT MAX(scbcrse2.scbcrse_eff_term)
                                     FROM saturn.scbcrse scbcrse2
                                    WHERE scbcrse2.scbcrse_subj_code = scbcrse.scbcrse_subj_code
                                      AND scbcrse2.scbcrse_crse_numb = scbcrse.scbcrse_crse_numb
                                      AND scbcrse2.scbcrse_eff_term <= v_term_code)
          LEFT JOIN stvcoll
            ON stvcoll_code = scbcrse_coll_code
          LEFT JOIN stvdept
            ON stvdept_code = scbcrse_dept_code
          LEFT JOIN gtvinsm
            ON gtvinsm_code = ssbsect_insm_code
          LEFT JOIN sirasgn
            ON sirasgn_crn = sfrstcr_crn
           AND sirasgn_term_code = sfrstcr_term_code
           AND sirasgn_primary_ind = 'Y'
          LEFT JOIN utl_d_aim.szriden faculty
            ON faculty.szriden_pidm = sirasgn_pidm
           AND v_etl_date BETWEEN faculty.szriden_from_date AND faculty.szriden_to_date
          LEFT JOIN (SELECT shrtckn_pidm AS pidm,
                            shrtckn_crn AS crn,
                            shrtckg_grde_code_final AS final_grade,
                            shrtckg_gmod_code AS gmod_code,
                            shrtckn_term_code AS term_code,
                            shrgrde_quality_points AS grade_quality_points,
                            CASE
                            WHEN shrgrde_gpa_ind = 'N'
                                 AND shrgrde_code NOT IN ('W', 'FN', 'WP', 'WF', 'PR') THEN
                             NULL
                            ELSE
                             shrgrde_quality_points
                            END AS grade_adj_quality_points,
                            shrgrde_numeric_value AS grade_numeric_value,
                            coalesce(shrtckg_final_grde_chg_date, v_etl_date) AS grade_change_date
                       FROM shrtckn
                       JOIN shrtckg
                         ON shrtckg_pidm = shrtckn_pidm
                        AND shrtckg_term_code = shrtckn_term_code
                        AND shrtckg_tckn_seq_no = shrtckn_seq_no
                        AND shrtckg_seq_no = (SELECT MAX(d.shrtckg_seq_no)
                                                FROM shrtckg d
                                               WHERE d.shrtckg_pidm = shrtckg.shrtckg_pidm
                                                 AND d.shrtckg_tckn_seq_no = shrtckg.shrtckg_tckn_seq_no
                                                 AND d.shrtckg_term_code = shrtckg.shrtckg_term_code)
                       JOIN shrtckl
                         ON shrtckn_term_code = v_term_code
                        AND shrtckl.shrtckl_pidm = shrtckn_pidm
                        AND shrtckl.shrtckl_term_code = shrtckn_term_code
                        AND shrtckl.shrtckl_tckn_seq_no = shrtckn_seq_no
                       JOIN shrgrde shrgrde
                         ON shrgrde.shrgrde_code = shrtckg.shrtckg_grde_code_final
                        AND shrgrde.shrgrde_levl_code = shrtckl_levl_code
                        AND shrgrde.shrgrde_term_code_effective = (SELECT MAX(shrgrde2.shrgrde_term_code_effective)
                                                                     FROM shrgrde shrgrde2
                                                                    WHERE shrgrde2.shrgrde_code = shrgrde.shrgrde_code
                                                                      AND shrgrde2.shrgrde_levl_code = shrtckl_levl_code
                                                                      AND shrgrde2.shrgrde_term_code_effective <= v_term_code)
                      WHERE shrtckn_term_code = v_term_code
                        AND MOD(shrtckn_pidm, v_mod) = v_partition) grde
            ON grde.term_code = sfrstcr_term_code
           AND grde.crn = sfrstcr_crn
           AND grde.pidm = sfrstcr_pidm
          LEFT JOIN (SELECT scbsupp_subj_code || scbsupp_crse_numb course,
                            a.scbsupp_tops_code crsdisp,
                            rank() over(PARTITION BY a.scbsupp_subj_code, a.scbsupp_crse_numb ORDER BY a.scbsupp_eff_term DESC, rownum) ranking
                       FROM scbsupp a
                      WHERE a.scbsupp_eff_term <= v_term_code) a
            ON a.course = ssbsect_subj_code || ssbsect_crse_numb
           AND a.ranking = 1
        UNION ALL
        -- ACD terms
        SELECT DISTINCT sfrstcr_pidm pidm, -- distinct because of szriden_pidm = 13804536
                         tbg.fa_proc_year acad_year,
                         sfrstcr_term_code term_code,
                         ssbsect_ptrm_code ptrm_code,
                         tbg.group_code group_code,
                         tbg.semester semester,
                         CASE
                         WHEN areg.crn IS NOT NULL THEN
                          areg.start_date
                         ELSE
                          ssbsect_ptrm_start_date
                         END ptrm_start,
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
                         END AS ptrm_end,
                         ssbsect_subj_code subj,
                         ssbsect_crse_numb numb,
                         ssbsect_subj_code || ssbsect_crse_numb course,
                         ssbsect_seq_numb sect,
                         ssbsect_crn crn,
                         sfrstcr_rsts_code rsts_code,
                         coalesce(ssbsect_crse_title, scbcrse_title) title,
                         ssbsect_camp_code camp_code,
                         ssbsect_insm_code insm_code,
                         gtvinsm_desc insm_desc,
                         sfrstcr_credit_hr credit_hr,
                         sfrstcr_levl_code levl_code,
                         stvcoll_desc college,
                         stvcoll_code coll_code,
                         lpad(a.crsdisp, 4, 0) crsdisp,
                         stvdept_desc department,
                         stvdept_code dept_code,
                         coalesce(grde.final_grade, sfrstcr_grde_code) AS final_grade,
                         coalesce(grde.grade_change_date, sfrstcr_grde_date) AS grade_date,
                         grde.grade_quality_points,
                         grde.grade_adj_quality_points,
                         grde.grade_numeric_value,
                         faculty.szriden_id faculty_id,
                         faculty.szriden_pidm faculty_pidm,
                         faculty.szriden_last_name faculty_last_name,
                         faculty.szriden_first_name faculty_first_name,
                         v_etl_date activity_date,
                         ssbsect_schd_code schd_code,
                         sfrstcr_add_date add_date,
                         ssbsect_intg_cde intg_code,
                         faculty.szriden_lu_email faculty_email,
                         sfrstcr.sfrstcr_bill_hr billing_hr
          FROM sfrstcr
          JOIN stvrsts
            ON stvrsts_code = sfrstcr_rsts_code
           AND stvrsts_incl_sect_enrl = 'Y'
           AND sfrstcr_term_code = v_term_code
           AND MOD(sfrstcr_pidm, v_mod) = v_partition
        -- we are including PD level for clubs; and allowing EM now (20230904), but must be restricted in anywhere necessary
          JOIN ssbsect
            ON ssbsect_term_code = sfrstcr_term_code
           AND ssbsect_crn = sfrstcr_crn
           AND ssbsect_subj_code <> 'NEWS'
          JOIN utl_d_aim.szriden
            ON szriden_pidm = sfrstcr_pidm
           AND v_etl_date BETWEEN szriden_from_date AND szriden_to_date
          JOIN zbtm.terms_by_group_v tbg
            ON tbg.term_code = sfrstcr_term_code
           AND tbg.group_code = v_group_code
           AND v_group_code = 'ACD' -- DO NOT REMOVE HARD CODED VALUE
          LEFT JOIN saturn.scbcrse
            ON scbcrse_subj_code = ssbsect_subj_code
           AND scbcrse_crse_numb = ssbsect_crse_numb
           AND scbcrse_eff_term = (SELECT MAX(scbcrse2.scbcrse_eff_term)
                                     FROM saturn.scbcrse scbcrse2
                                    WHERE scbcrse2.scbcrse_subj_code = scbcrse.scbcrse_subj_code
                                      AND scbcrse2.scbcrse_crse_numb = scbcrse.scbcrse_crse_numb
                                      AND scbcrse2.scbcrse_eff_term <= v_term_code)
          LEFT JOIN stvcoll
            ON stvcoll_code = scbcrse_coll_code
          LEFT JOIN stvdept
            ON stvdept_code = scbcrse_dept_code
          LEFT JOIN gtvinsm
            ON gtvinsm_code = ssbsect_insm_code
          LEFT JOIN (SELECT areg.sfrareg_term_code AS term_code,
                            areg.sfrareg_crn AS crn,
                            areg.sfrareg_pidm AS pidm,
                            MAX(areg.sfrareg_start_date) keep(dense_rank FIRST ORDER BY areg.sfrareg_extension_number) AS start_date, -- yes MAX, we want the MAX
                            MAX(areg.sfrareg_completion_date) keep(dense_rank FIRST ORDER BY areg.sfrareg_extension_number DESC) AS end_date
                       FROM saturn.sfrareg areg
                      WHERE (areg.sfrareg_term_code IN ('201440') OR areg.sfrareg_term_code >= '202338') -- DO NOT REMOVE HARD CODED VALUE
                        AND areg.sfrareg_term_code = v_term_code
                      GROUP BY areg.sfrareg_term_code,
                               areg.sfrareg_crn,
                               areg.sfrareg_pidm) areg
            ON areg.term_code = sfrstcr_term_code
           AND areg.crn = sfrstcr_crn
           AND areg.pidm = sfrstcr_pidm
          LEFT JOIN sirasgn
            ON sirasgn_crn = sfrstcr_crn
           AND sirasgn_term_code = sfrstcr_term_code
           AND sirasgn_primary_ind = 'Y'
          LEFT JOIN utl_d_aim.szriden faculty
            ON faculty.szriden_pidm = sirasgn_pidm
           AND v_etl_date BETWEEN faculty.szriden_from_date AND faculty.szriden_to_date
          LEFT JOIN (SELECT shrtckn_pidm AS pidm,
                            shrtckn_crn AS crn,
                            shrtckg_grde_code_final AS final_grade,
                            shrtckg_gmod_code AS gmod_code,
                            shrtckn_term_code AS term_code,
                            shrgrde_quality_points AS grade_quality_points,
                            CASE
                            WHEN shrgrde_gpa_ind = 'N'
                                 AND shrgrde_code NOT IN ('W', 'FN', 'WP', 'WF', 'PR') THEN
                             NULL
                            ELSE
                             shrgrde_quality_points
                            END AS grade_adj_quality_points,
                            shrgrde_numeric_value AS grade_numeric_value,
                            coalesce(shrtckg_final_grde_chg_date, v_etl_date) AS grade_change_date
                       FROM shrtckn
                       JOIN shrtckg
                         ON shrtckg_pidm = shrtckn_pidm
                        AND shrtckg_term_code = shrtckn_term_code
                        AND shrtckg_tckn_seq_no = shrtckn_seq_no
                        AND shrtckg_seq_no = (SELECT MAX(d.shrtckg_seq_no)
                                                FROM shrtckg d
                                               WHERE d.shrtckg_pidm = shrtckg.shrtckg_pidm
                                                 AND d.shrtckg_tckn_seq_no = shrtckg.shrtckg_tckn_seq_no
                                                 AND d.shrtckg_term_code = shrtckg.shrtckg_term_code)
                       JOIN shrtckl
                         ON shrtckn_term_code = v_term_code
                        AND shrtckl.shrtckl_pidm = shrtckn_pidm
                        AND shrtckl.shrtckl_term_code = shrtckn_term_code
                        AND shrtckl.shrtckl_tckn_seq_no = shrtckn_seq_no
                       JOIN shrgrde shrgrde
                         ON shrgrde.shrgrde_code = shrtckg.shrtckg_grde_code_final
                        AND shrgrde.shrgrde_levl_code = shrtckl_levl_code
                        AND shrgrde.shrgrde_term_code_effective = (SELECT MAX(shrgrde2.shrgrde_term_code_effective)
                                                                     FROM shrgrde shrgrde2
                                                                    WHERE shrgrde2.shrgrde_code = shrgrde.shrgrde_code
                                                                      AND shrgrde2.shrgrde_levl_code = shrtckl_levl_code
                                                                      AND shrgrde2.shrgrde_term_code_effective <= v_term_code)
                      WHERE shrtckn_term_code = v_term_code
                        AND MOD(shrtckn_pidm, v_mod) = v_partition) grde
            ON grde.term_code = sfrstcr_term_code
           AND grde.crn = sfrstcr_crn
           AND grde.pidm = sfrstcr_pidm
          LEFT JOIN (SELECT scbsupp_subj_code || scbsupp_crse_numb course,
                            a.scbsupp_tops_code crsdisp,
                            rank() over(PARTITION BY a.scbsupp_subj_code, a.scbsupp_crse_numb ORDER BY a.scbsupp_eff_term DESC, rownum) ranking
                       FROM scbsupp a
                      WHERE a.scbsupp_eff_term <= v_term_code) a
            ON a.course = ssbsect_subj_code || ssbsect_crse_numb
           AND a.ranking = 1) tblnew
-- for the control state
  FULL JOIN (SELECT *
               FROM utl_d_aim.szrcrse
              WHERE term_code = v_term_code
                AND group_code = v_group_code
                AND MOD(szrcrse.pidm, v_mod) = v_partition) tblold
    ON tblold.pidm = tblnew.pidm
   AND tblold.term_code = tblnew.term_code
   AND tblold.crn = tblnew.crn
 WHERE 1 = 1
      -- for inserts or deletes...
   AND (((tblnew.pidm IS NULL AND tblold.pidm IS NOT NULL) OR (tblnew.pidm IS NOT NULL AND tblold.pidm IS NULL))
       -- for updates if any data has changed...
       OR ((coalesce(tblnew.acad_year, 'X') <> coalesce(tblold.acad_year, 'X')) OR --
       (coalesce(tblnew.ptrm_code, 'X') <> coalesce(tblold.ptrm_code, 'X')) OR --
       (coalesce(tblnew.group_code, 'X') <> coalesce(tblold.group_code, 'X')) OR --
       (coalesce(tblnew.semester, 'X') <> coalesce(tblold.semester, 'X')) OR --
       (coalesce(tblnew.ptrm_start, v_etl_date) <> coalesce(tblold.ptrm_start, v_etl_date)) OR --
       (coalesce(tblnew.ptrm_end, v_etl_date) <> coalesce(tblold.ptrm_end, v_etl_date)) OR --
       (coalesce(tblnew.subj, 'X') <> coalesce(tblold.subj, 'X')) OR --
       (coalesce(tblnew.numb, 'X') <> coalesce(tblold.numb, 'X')) OR --
       (coalesce(tblnew.course, 'X') <> coalesce(tblold.course, 'X')) OR --
       (coalesce(tblnew.sect, 'X') <> coalesce(tblold.sect, 'X')) OR --
       (coalesce(tblnew.rsts_code, 'X') <> coalesce(tblold.rsts_code, 'X')) OR --
       (coalesce(tblnew.title, 'X') <> coalesce(tblold.title, 'X')) OR --
       (coalesce(tblnew.camp_code, 'X') <> coalesce(tblold.camp_code, 'X')) OR --
       (coalesce(tblnew.insm_code, 'X') <> coalesce(tblold.insm_code, 'X')) OR --
       (coalesce(tblnew.insm_desc, 'X') <> coalesce(tblold.insm_desc, 'X')) OR --
       (coalesce(tblnew.credit_hr, -1) <> coalesce(tblold.credit_hr, -1)) OR --
       (coalesce(tblnew.levl_code, 'X') <> coalesce(tblold.levl_code, 'X')) OR --
       (coalesce(tblnew.college, 'X') <> coalesce(tblold.college, 'X')) OR --
       (coalesce(tblnew.coll_code, 'X') <> coalesce(tblold.coll_code, 'X')) OR --
       (coalesce(tblnew.crsdisp, 'X') <> coalesce(tblold.crsdisp, 'X')) OR --
       (coalesce(tblnew.department, 'X') <> coalesce(tblold.department, 'X')) OR --
       (coalesce(tblnew.dept_code, 'X') <> coalesce(tblold.dept_code, 'X')) OR --
       (coalesce(tblnew.final_grade, 'X') <> coalesce(tblold.final_grade, 'X')) OR --
       (coalesce(tblnew.grade_date, v_etl_date) <> coalesce(tblold.grade_date, v_etl_date)) OR --
       (coalesce(tblnew.grade_quality_points, -1) <> coalesce(tblold.grade_quality_points, -1)) OR --
       (coalesce(tblnew.grade_adj_quality_points, -1) <> coalesce(tblold.grade_adj_quality_points, -1)) OR --
       (coalesce(tblnew.grade_numeric_value, -1) <> coalesce(tblold.grade_numeric_value, -1)) OR --
       (coalesce(tblnew.faculty_id, 'X') <> coalesce(tblold.faculty_id, 'X')) OR --
       (coalesce(tblnew.faculty_pidm, -1) <> coalesce(tblold.faculty_pidm, -1)) OR --
       (coalesce(tblnew.faculty_last_name, 'X') <> coalesce(tblold.faculty_last_name, 'X')) OR --
       (coalesce(tblnew.faculty_first_name, 'X') <> coalesce(tblold.faculty_first_name, 'X')) OR --
       (coalesce(tblnew.schd_code, 'X') <> coalesce(tblold.schd_code, 'X')) OR --
       (coalesce(tblnew.add_date, v_etl_date) <> coalesce(tblold.add_date, v_etl_date)) OR --
       (coalesce(tblnew.intg_code, 'X') <> coalesce(tblold.intg_code, 'X')) OR --
       (coalesce(tblnew.faculty_email, 'X') <> coalesce(tblold.faculty_email, 'X')) OR --
       (coalesce(tblnew.billing_hr, -1) <> coalesce(tblold.billing_hr, -1))));
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
start_time   TIMESTAMP;
end_time     TIMESTAMP;
select_count NUMBER := 0;
insert_count NUMBER := 0;
update_count NUMBER := 0;
delete_count NUMBER := 0;
start_t      DATE := SYSDATE;
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
OPEN c1(rec.term_code, rec.group_code);
LOOP
v_count   := 0; -- reset count
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || rec.term_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
FETCH c1 BULK COLLECT
INTO rec_input LIMIT v_row_max;
v_count := rec_input.count;
IF v_count = 0 THEN
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'SELECT - ' || rec.term_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
ELSIF v_count > 0 THEN
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'SELECT - ' || rec.term_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
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
v_msg     := SQLERRM || ' exception raised for ' || rec.term_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || round(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
CONTINUE;
END;
END LOOP;
insert_count := insert_dml.count;
update_count := update_dml.count;
delete_count := delete_dml.count;
--- deadlock detections HEADER ---
LOOP
BEGIN -- Retry mechanism for handling deadlocks
  --- deadlock detections HEADER ---
FORALL i IN VALUES OF insert_dml -- DML INSERTS
INSERT INTO utl_d_aim.szrcrse tab
(pidm,
 acad_year,
 term_code,
 ptrm_code,
 group_code,
 semester,
 ptrm_start,
 ptrm_end,
 subj,
 numb,
 course,
 sect,
 crn,
 rsts_code,
 title,
 camp_code,
 insm_code,
 insm_desc,
 credit_hr,
 levl_code,
 college,
 coll_code,
 crsdisp,
 department,
 dept_code,
 final_grade,
 grade_date,
 grade_quality_points,
 grade_adj_quality_points,
 grade_numeric_value,
 faculty_id,
 faculty_pidm,
 faculty_last_name,
 faculty_first_name,
 activity_date,
 schd_code,
 add_date,
 intg_code,
 faculty_email,
 billing_hr)
VALUES
(rec_input(i).pidm,
 rec_input(i).acad_year,
 rec_input(i).term_code,
 rec_input(i).ptrm_code,
 rec_input(i).group_code,
 rec_input(i).semester,
 rec_input(i).ptrm_start,
 rec_input(i).ptrm_end,
 rec_input(i).subj,
 rec_input(i).numb,
 rec_input(i).course,
 rec_input(i).sect,
 rec_input(i).crn,
 rec_input(i).rsts_code,
 rec_input(i).title,
 rec_input(i).camp_code,
 rec_input(i).insm_code,
 rec_input(i).insm_desc,
 rec_input(i).credit_hr,
 rec_input(i).levl_code,
 rec_input(i).college,
 rec_input(i).coll_code,
 rec_input(i).crsdisp,
 rec_input(i).department,
 rec_input(i).dept_code,
 rec_input(i).final_grade,
 rec_input(i).grade_date,
 rec_input(i).grade_quality_points,
 rec_input(i).grade_adj_quality_points,
 rec_input(i).grade_numeric_value,
 rec_input(i).faculty_id,
 rec_input(i).faculty_pidm,
 rec_input(i).faculty_last_name,
 rec_input(i).faculty_first_name,
 rec_input(i).activity_date,
 rec_input(i).schd_code,
 rec_input(i).add_date,
 rec_input(i).intg_code,
 rec_input(i).faculty_email,
 rec_input(i).billing_hr);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'INSERT - ' || rec.term_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
--- deadlock detections FOOTER ---
EXIT; -- If successful, exit the retry loop for deadlock detection
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
--- deadlock detections FOOTER ---
--- deadlock detections HEADER ---
LOOP
BEGIN -- Retry mechanism for handling deadlocks
  --- deadlock detections HEADER ---
FORALL i IN VALUES OF update_dml -- DML UPDATES
UPDATE utl_d_aim.szrcrse tab
   SET (pidm, acad_year, term_code, ptrm_code, group_code, semester, ptrm_start, ptrm_end, subj, numb, course, sect, crn, rsts_code, title, camp_code, insm_code, insm_desc, credit_hr, levl_code, college, coll_code, crsdisp, department, dept_code, final_grade, grade_date, grade_quality_points, grade_adj_quality_points, grade_numeric_value, faculty_id, faculty_pidm, faculty_last_name, faculty_first_name, activity_date, schd_code, add_date, intg_code, faculty_email, billing_hr) =
       (SELECT rec_input(i).pidm,
               rec_input(i).acad_year,
               rec_input(i).term_code,
               rec_input(i).ptrm_code,
               rec_input(i).group_code,
               rec_input(i).semester,
               rec_input(i).ptrm_start,
               rec_input(i).ptrm_end,
               rec_input(i).subj,
               rec_input(i).numb,
               rec_input(i).course,
               rec_input(i).sect,
               rec_input(i).crn,
               rec_input(i).rsts_code,
               rec_input(i).title,
               rec_input(i).camp_code,
               rec_input(i).insm_code,
               rec_input(i).insm_desc,
               rec_input(i).credit_hr,
               rec_input(i).levl_code,
               rec_input(i).college,
               rec_input(i).coll_code,
               rec_input(i).crsdisp,
               rec_input(i).department,
               rec_input(i).dept_code,
               rec_input(i).final_grade,
               rec_input(i).grade_date,
               rec_input(i).grade_quality_points,
               rec_input(i).grade_adj_quality_points,
               rec_input(i).grade_numeric_value,
               rec_input(i).faculty_id,
               rec_input(i).faculty_pidm,
               rec_input(i).faculty_last_name,
               rec_input(i).faculty_first_name,
               rec_input(i).activity_date,
               rec_input(i).schd_code,
               rec_input(i).add_date,
               rec_input(i).intg_code,
               rec_input(i).faculty_email,
               rec_input(i).billing_hr
          FROM dual)
 WHERE tab.term_code = rec_input(i).term_code
   AND tab.crn = rec_input(i).crn
   AND tab.pidm = rec_input(i).pidm;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'UPDATE - ' || rec.term_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
--- deadlock detections FOOTER ---
EXIT; -- If successful, exit the retry loop for deadlock detection
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
--- deadlock detections FOOTER ---
--- deadlock detections HEADER ---
LOOP
BEGIN -- Retry mechanism for handling deadlocks
  --- deadlock detections HEADER ---
FORALL i IN VALUES OF delete_dml -- DML DELETES
DELETE FROM utl_d_aim.szrcrse tab
 WHERE tab.term_code = rec_input(i).term_code
   AND tab.crn = rec_input(i).crn
   AND tab.pidm = rec_input(i).pidm;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'DELETE - ' || rec.term_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
--- deadlock detections FOOTER ---
EXIT; -- If successful, exit the retry loop for deadlock detection
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
--- deadlock detections FOOTER ---
END IF;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_total_count := v_total_count + rec_input.count;
EXIT WHEN(rec_input.count < v_row_max);
END LOOP;
CLOSE c1;
dbms_output.put_line(' --------- ');
END LOOP; -- c_terms
--- deadlock detections HEADER ---
LOOP
BEGIN -- Retry mechanism for handling deadlocks
  --- deadlock detections HEADER ---
-- update any final grades on the student_progress table immediately
UPDATE utl_d_lms.student_progress tgt
   SET (tgt.final_grade, tgt.final_grade_date) =
       (SELECT crse.final_grade,
               crse.grade_date
          FROM utl_d_lms.student_enrollments se
          JOIN utl_d_lms.student_progress sp
            ON se.instance = sp.instance
           AND se.course_section_id = sp.course_section_id
           AND se.user_id = sp.user_id
           AND se.partition = v_partition
          JOIN utl_d_aim.szrcrse crse
            ON crse.term_code = se.term_code
           AND crse.crn = se.crn
           AND crse.pidm = se.pidm
           AND coalesce(crse.final_grade, 'M') <> coalesce(tgt.final_grade, 'M')
         WHERE tgt.instance = sp.instance
           AND tgt.course_section_id = sp.course_section_id
           AND tgt.user_id = sp.user_id)
 WHERE EXISTS (SELECT 1
          FROM utl_d_lms.student_enrollments se
          JOIN utl_d_lms.student_progress sp
            ON se.instance = sp.instance
           AND se.course_section_id = sp.course_section_id
           AND se.user_id = sp.user_id
           AND se.partition = v_partition
          JOIN utl_d_aim.szrcrse crse
            ON crse.term_code = se.term_code
           AND crse.crn = se.crn
           AND crse.pidm = se.pidm
           AND coalesce(crse.final_grade, 'M') <> coalesce(tgt.final_grade, 'M')
         WHERE tgt.instance = sp.instance
           AND tgt.course_section_id = sp.course_section_id
           AND tgt.user_id = sp.user_id);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'UPDATE - ' || 'ALL' || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
--- deadlock detections FOOTER ---
EXIT; -- If successful, exit the retry loop for deadlock detection
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
--- deadlock detections FOOTER ---
v_total_count := v_total_count + v_count; -- calculate total
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
-- log any errors
EXCEPTION
WHEN OTHERS THEN
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(SQLERRM, 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
/*--------------------------------------------CHANGE LOG----------------------------------------
VERSION    DATE        USERNAME       UPDATES
1.0        06-13-2018  kcaldwell      Initial release
2.0        03-27-2019  kcaldwell      added coll code and prof pidm
3.0        05-06-2019  kcaldwell      added crs disp
3.1        03-09-2020  lxhatfield     added grade quality points and numeric value
3.2        08-21-2020  lxhatfield     added schd_code, add_date, intg_code, course_sis_id, section_sis_id
3.3        01-22-2021  lxhatfield     add faculty_email
3.4        02-02-2021  lxhatfield     updated lms course and section SIS ID to match UTL_D_LMS.LMS_LINK as per Drew's recommendation. Main change is for MED and ACD courses.
3.5        02-14-2021  cwalsh1        Add max statements on source ID to merge statements, circumventing issues with duplicate source IDs per TERM_CODE/CRN on canvas_ETL
4.0        07-08-2022  cwalsh1        Converted ETL to a transactional refresh. No full reloads. Worked with Wayne Yates on body of the changes. Refresh down from 50 mins to 13.
4.0        10-06-2022  wgriffith2     Adding billing_hr field
4.0        10-14-2022  wgriffith2     Updates to null start and end dates; adding activity_date timestamps on merges
4.1        10-27-2022  wgriffith2     Now using bulk collect
4.2        01-23-2023  wgriffith2     Adding open learning for LUOA terms
---     05-17-2023  wgriffith2  --Dealing with EM courses and updating code to use job_log
---     09-04-2023  wgriffith2  --allowing EM now, but must be restricted in anywhere this table is being used
---     02-08-2024  wgriffith2  --always run active terms hourly including any future terms within 180 days. then, only run terms that we found a grade change happen once daily after midnight
---     02-15-2024  wgriffith2  --adding update to student_progress table for immediate change to final grades
---     10-10-2025  wgriffith2  -- added deadlock detections AND avoidance
------------------------------------------------------------------------------------------------*/
END etl_aim_szrcrse_refresh;

procedure etl_aim_robrregaudit_refresh (jobnumber number, processid varchar2, processname varchar2) is
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
v_proc        VARCHAR2(100) := 'etl_aim_robrregaudit_refresh';
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
v_msg     := 'START - ' || v_instance || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
utl_d_aim.truncate_table(v_table_name => 'ROBRREGAUDIT');
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'TRUNCATE - ' || v_instance || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
--Insert latest data
INSERT INTO utl_d_aim.robrregaudit
(id,
 action_type,
 action,
 action_search,
 staff_last_name,
 staff_first_name,
 job_title,
 department,
 activity_date,
 staff_email,
 term,
 subj_code,
 crse_numb,
 seq_numb,
 crn,
 crse_levl,
 stu_id,
 stu_pidm,
 stu_levl,
 stu_program,
 stu_last_name,
 stu_first_name,
 last_refresh)
SELECT rownum id,
       dog.action_type,
       dog.action,
       dog.action_search,
       nvl(u.spriden_last_name, dog.user_id) staff_last_name,
       u.spriden_first_name staff_first_name,
       nvl(emp.empjobtitle, 'UNKNOWN OR NO LONGER EMPLOYED') job_title,
       nvl(emp.ftvorgn_title, 'UNKNOWN OR NO LONGER EMPLOYED') department,
       dog.activity_date,
       email_address staff_email,
       dog.term,
       dog.subj_code,
       dog.crse_numb,
       dog.seq_numb,
       dog.crn,
       dog.crse_levl,
       s.spriden_id stu_id,
       s.spriden_pidm stu_pidm,
       sgbstdn_levl_code stu_levl,
       CASE
       WHEN smrprle_program IS NULL THEN
        stvmajr_code || ' (' || stvmajr_desc || ')'
       ELSE
        smrprle_program || ' (' || smrprle_program_desc || ')'
       END stu_term,
       s.spriden_last_name stu_last_name,
       s.spriden_first_name stu_first_name,
       SYSDATE
  FROM saturn.spriden s
  JOIN ( --Registration error overrides
        SELECT 'REG ERROR OVERRIDE' action_type,
                listagg(sfrstca_message, ':') within GROUP(ORDER BY sfrstca_rmsg_cde) action,
                listagg(sfrstca_rmsg_cde, ':') within GROUP(ORDER BY sfrstca_rmsg_cde) action_search,
                sfrstcr_pidm pidm,
                sfrstca_rsts_date activity_date,
                sfrstca_user user_id,
                sfrstcr_term_code term,
                ssbsect_subj_code subj_code,
                ssbsect_crse_numb crse_numb,
                ssbsect_seq_numb seq_numb,
                sfrstcr_crn crn,
                crse_levl
          FROM (SELECT sfrstcr_pidm,
                        sfrstca_rsts_date,
                        sfrstca_user,
                        sfrstcr_term_code,
                        sfrstcr_crn,
                        ssbsect_subj_code,
                        ssbsect_crse_numb,
                        ssbsect_seq_numb,
                        sfrstca_message,
                        sfrstca_rmsg_cde,
                        listagg(scrlevl_levl_code, ':') within GROUP(ORDER BY scrlevl_levl_code) crse_levl
                   FROM (SELECT DISTINCT sfrstcr_pidm,
                                         sfrstca.sfrstca_rsts_date,
                                         sfrstca.sfrstca_user,
                                         sfrstcr_term_code,
                                         sfrstcr_crn,
                                         ssbsect_subj_code,
                                         ssbsect_crse_numb,
                                         ssbsect_seq_numb,
                                         scrlevl_levl_code,
                                         er.sfrstca_message,
                                         er.sfrstca_rmsg_cde
                           FROM saturn.sfrstcr
                           JOIN saturn.stvrsts
                             ON stvrsts_code = sfrstcr_rsts_code
                            AND stvrsts_incl_sect_enrl = 'Y'
                            AND stvrsts_withdraw_ind = 'N'
                           JOIN saturn.sfrstca
                             ON sfrstca.sfrstca_term_code = sfrstcr_term_code
                            AND sfrstca.sfrstca_pidm = sfrstcr_pidm
                            AND sfrstca.sfrstca_crn = sfrstcr_crn
                            AND sfrstca.sfrstca_seq_number = (SELECT MAX(stca2.sfrstca_seq_number)
                                                                FROM saturn.sfrstca stca2
                                                               WHERE stca2.sfrstca_term_code = sfrstca.sfrstca_term_code
                                                                 AND stca2.sfrstca_pidm = sfrstca.sfrstca_pidm
                                                                 AND stca2.sfrstca_crn = sfrstca.sfrstca_crn
                                                                 AND stca2.sfrstca_rsts_code = sfrstcr_rsts_code
                                                                 AND stca2.sfrstca_error_flag = sfrstcr_error_flag
                                                                 AND stca2.sfrstca_source_cde = 'BASE')
                           JOIN saturn.sfrstca er
                             ON er.sfrstca_term_code = sfrstcr_term_code
                            AND er.sfrstca_pidm = sfrstcr_pidm
                            AND er.sfrstca_crn = sfrstcr_crn
                            AND er.sfrstca_seq_number < sfrstca.sfrstca_seq_number
                            AND er.sfrstca_rsts_code = sfrstca.sfrstca_rsts_code
                            AND er.sfrstca_user = sfrstca.sfrstca_user
                            AND er.sfrstca_source_cde = 'TEMP'
                            AND er.sfrstca_error_flag = 'F'
                            AND er.sfrstca_message NOT LIKE '%SYSDEL'
                           JOIN (SELECT ssbsect_term_code,
                                       ssbsect_crn,
                                       ssbsect_subj_code,
                                       ssbsect_crse_numb,
                                       ssbsect_seq_numb,
                                       scrlevl_levl_code,
                                       rank() over(PARTITION BY ssbsect_term_code, ssbsect_subj_code, ssbsect_crse_numb ORDER BY scrlevl_eff_term DESC) levl_rank
                                  FROM saturn.ssbsect
                                  JOIN saturn.scrlevl
                                    ON scrlevl_subj_code = ssbsect_subj_code
                                   AND scrlevl_crse_numb = ssbsect_crse_numb
                                   AND scrlevl_eff_term <= ssbsect_term_code)
                             ON ssbsect_term_code = sfrstcr_term_code
                            AND ssbsect_crn = sfrstcr_crn
                            AND levl_rank = 1
                          WHERE sfrstcr_error_flag = 'O'
                            AND trunc(sfrstcr_rsts_date) > add_months(SYSDATE, -12))
                  GROUP BY sfrstcr_pidm,
                           sfrstca_rsts_date,
                           sfrstca_user,
                           sfrstcr_term_code,
                           sfrstcr_crn,
                           ssbsect_subj_code,
                           ssbsect_crse_numb,
                           ssbsect_seq_numb,
                           sfrstca_message,
                           sfrstca_rmsg_cde)
          LEFT JOIN (SELECT sgbstdn_pidm,
                            sgbstdn_program_1,
                            sgbstdn_levl_code,
                            sgbstdn_majr_code_1,
                            stvterm_code program_term
                       FROM saturn.sgbstdn
                      CROSS JOIN saturn.stvterm
                      WHERE sgbstdn_term_code_eff = (SELECT MAX(stdn2.sgbstdn_term_code_eff)
                                                       FROM saturn.sgbstdn stdn2
                                                      WHERE stdn2.sgbstdn_pidm = sgbstdn.sgbstdn_pidm
                                                        AND stdn2.sgbstdn_term_code_eff <= stvterm_code))
            ON sgbstdn_pidm = sfrstcr_pidm
           AND program_term = sfrstcr_term_code
          LEFT JOIN saturn.smrprle
            ON smrprle_program = sgbstdn_program_1
          LEFT JOIN saturn.stvmajr
            ON stvmajr_code = sgbstdn_majr_code_1
         GROUP BY sfrstcr_pidm,
                   sfrstca_rsts_date,
                   sfrstca_user,
                   sfrstcr_term_code,
                   sfrstcr_crn,
                   ssbsect_subj_code,
                   ssbsect_crse_numb,
                   ssbsect_seq_numb,
                   crse_levl
        UNION ALL
        --Grade changes (SFRSTCA)
        SELECT action_type,
                action,
                action_search,
                sfrstca_pidm,
                sfrstca_activity_date,
                sfrstca_user,
                sfrstca_term_code,
                ssbsect_subj_code,
                ssbsect_crse_numb,
                ssbsect_seq_numb,
                sfrstca_crn,
                listagg(scrlevl_levl_code, ':') within GROUP(ORDER BY scrlevl_levl_code)
          FROM (SELECT 'SFAALST GRADE CHANGE' action_type,
                        '"' || CASE
                        WHEN prv.sfrstca_message LIKE '%NULL' THEN
                         '*REMOVED*'
                        ELSE
                         regexp_substr(prv.sfrstca_message, '[A-Z]{1,2}[+-]?$')
                        END || '" TO "' || CASE
                        WHEN sfrstca.sfrstca_message LIKE '%NULL' THEN
                         '*REMOVED*'
                        ELSE
                         regexp_substr(sfrstca.sfrstca_message, '[A-Z]{1,2}[+-]?$')
                        END || '"' action,
                        '"' || CASE
                        WHEN prv.sfrstca_message LIKE '%NULL' THEN
                         '*REMOVED*'
                        ELSE
                         regexp_substr(prv.sfrstca_message, '[A-Z]{1,2}[+-]?$')
                        END || '" TO "' || CASE
                        WHEN sfrstca.sfrstca_message LIKE '%NULL' THEN
                         '*REMOVED*'
                        ELSE
                         regexp_substr(sfrstca.sfrstca_message, '[A-Z]{1,2}[+-]?$')
                        END || '"' action_search --same as action
                       ,
                        sfrstca.sfrstca_pidm,
                        sfrstca.sfrstca_activity_date,
                        sfrstca.sfrstca_user,
                        sfrstca.sfrstca_term_code,
                        ssbsect_subj_code,
                        ssbsect_crse_numb,
                        ssbsect_seq_numb,
                        sfrstca.sfrstca_crn,
                        scrlevl_levl_code,
                        rank() over(PARTITION BY ssbsect_term_code, ssbsect_subj_code, ssbsect_crse_numb ORDER BY scrlevl_eff_term DESC) levl_rank
                   FROM saturn.sfrstcr
                   JOIN saturn.sfrstca
                     ON sfrstca.sfrstca_term_code = sfrstcr_term_code
                    AND sfrstca.sfrstca_pidm = sfrstcr_pidm
                    AND sfrstca.sfrstca_crn = sfrstcr_crn
                    AND sfrstca.sfrstca_source_cde = 'BASE'
                    AND sfrstca.sfrstca_rmsg_cde = 'FING'
                    AND sfrstca.sfrstca_seq_number != (SELECT MIN(stca3.sfrstca_seq_number) --We want the grade posting records that are not the first grade posting
                                                         FROM saturn.sfrstca stca3
                                                        WHERE stca3.sfrstca_term_code = sfrstca.sfrstca_term_code
                                                          AND stca3.sfrstca_pidm = sfrstca.sfrstca_pidm
                                                          AND stca3.sfrstca_crn = sfrstca.sfrstca_crn
                                                          AND stca3.sfrstca_source_cde = 'BASE'
                                                          AND stca3.sfrstca_rmsg_cde = 'FING')
                   JOIN saturn.sfrstca prv
                     ON prv.sfrstca_term_code = sfrstca.sfrstca_term_code --The previous grade (grade change from)
                    AND prv.sfrstca_pidm = sfrstca.sfrstca_pidm
                    AND prv.sfrstca_crn = sfrstca.sfrstca_crn
                    AND prv.sfrstca_seq_number = (SELECT MAX(stca4.sfrstca_seq_number)
                                                    FROM saturn.sfrstca stca4
                                                   WHERE stca4.sfrstca_term_code = prv.sfrstca_term_code
                                                     AND stca4.sfrstca_pidm = prv.sfrstca_pidm
                                                     AND stca4.sfrstca_crn = prv.sfrstca_crn
                                                     AND stca4.sfrstca_source_cde = 'BASE'
                                                     AND stca4.sfrstca_rmsg_cde = 'FING'
                                                     AND stca4.sfrstca_seq_number < sfrstca.sfrstca_seq_number)
                   JOIN saturn.ssbsect
                     ON ssbsect_term_code = sfrstcr_term_code
                    AND ssbsect_crn = sfrstcr_crn
                   JOIN saturn.scrlevl
                     ON scrlevl_subj_code = ssbsect_subj_code
                    AND scrlevl_crse_numb = ssbsect_crse_numb
                    AND scrlevl_eff_term <= ssbsect_term_code
                  WHERE trunc(sfrstca.sfrstca_activity_date) > add_months(SYSDATE, -12))
         WHERE levl_rank = 1
         GROUP BY action_type,
                   action,
                   action_search,
                   sfrstca_pidm,
                   sfrstca_activity_date,
                   sfrstca_user,
                   sfrstca_term_code,
                   ssbsect_subj_code,
                   ssbsect_crse_numb,
                   ssbsect_seq_numb,
                   sfrstca_crn
        UNION ALL
        --Grade changes (SHRTCKG)
        SELECT DISTINCT 'SHATCKN GRADE CHANGE' action_type,
                         '"' || prev.shrtckg_grde_code_final || '" TO "' || shrtckg.shrtckg_grde_code_final || '"' action,
                         '"' || prev.shrtckg_grde_code_final || '" TO "' || shrtckg.shrtckg_grde_code_final || '"' action_search,
                         shrtckn_pidm,
                         shrtckg.shrtckg_final_grde_chg_date,
                         shrtckg.shrtckg_final_grde_chg_user,
                         shrtckn_term_code,
                         shrtckn_subj_code,
                         shrtckn_crse_numb,
                         shrtckn_seq_numb,
                         shrtckn_crn,
                         listagg(shrtckl_levl_code, ':') within GROUP(ORDER BY shrtckl_primary_levl_ind DESC) over(PARTITION BY shrtckn_term_code, shrtckn_pidm, shrtckn_seq_no, shrtckg.shrtckg_seq_no) levl
          FROM saturn.shrtckn
          JOIN saturn.shrtckg
            ON shrtckg.shrtckg_pidm = shrtckn_pidm
           AND shrtckg.shrtckg_term_code = shrtckn_term_code
           AND shrtckg.shrtckg_tckn_seq_no = shrtckn_seq_no
           AND shrtckg.shrtckg_seq_no != 1 --Don't get the initial grade posting
          JOIN saturn.shrtckg prev
            ON prev.shrtckg_pidm = shrtckn_pidm
           AND prev.shrtckg_term_code = shrtckn_term_code
           AND prev.shrtckg_tckn_seq_no = shrtckn_seq_no
           AND prev.shrtckg_seq_no = shrtckg.shrtckg_seq_no - 1 --Get the previous grade
          JOIN saturn.shrtckl
            ON shrtckl_pidm = shrtckn_pidm
           AND shrtckl_term_code = shrtckn_term_code
           AND shrtckl_tckn_seq_no = shrtckn_seq_no
         WHERE trunc(shrtckg.shrtckg_final_grde_chg_date) > add_months(SYSDATE, -12)
        UNION ALL
        --Degrees conferred
        SELECT 'DEGREES CONFERRED' action_type,
                'Degree Conferred' action,
                'Degree Conferred' action_search,
                shrdgmr_pidm,
                shrdgmr_grad_date,
                shrdgmr_user_id,
                shrdgmr_term_code_grad,
                shrdgmr_program || ' (' || g.smrprle_program_desc || ')',
                NULL,
                NULL,
                NULL,
                shrdgmr_levl_code
          FROM saturn.shrdgmr
          LEFT JOIN saturn.smrprle g
            ON g.smrprle_program = shrdgmr_program
         WHERE shrdgmr_degs_code = 'AW'
           AND trunc(shrdgmr_grad_date) > add_months(SYSDATE, -12)) dog
    ON dog.pidm = s.spriden_pidm
  JOIN saturn.sgbstdn
    ON sgbstdn_pidm = dog.pidm
   AND sgbstdn_levl_code IS NOT NULL
   AND sgbstdn_term_code_eff = (SELECT MAX(stdn2.sgbstdn_term_code_eff)
                                  FROM saturn.sgbstdn stdn2
                                 WHERE stdn2.sgbstdn_pidm = sgbstdn.sgbstdn_pidm
                                   AND stdn2.sgbstdn_term_code_eff <= dog.term)
  LEFT JOIN saturn.smrprle
    ON smrprle_program = sgbstdn_program_1
  LEFT JOIN saturn.stvmajr
    ON stvmajr_code = sgbstdn_majr_code_1
--staff(user_id) info
  LEFT JOIN general.gobtpac
    ON gobtpac_ldap_user = REPLACE(dog.user_id, 'W:')
  LEFT JOIN saturn.spriden u
    ON u.spriden_pidm = gobtpac_pidm
   AND u.spriden_change_ind IS NULL
  LEFT JOIN (SELECT s2.empid,
                    listagg(nvl(s2.empjobtitle, 'UNKNOWN'), ':') within GROUP(ORDER BY s3.ftvorgn_title) empjobtitle,
                    s3.ftvorgn_title
               FROM (SELECT DISTINCT s5.empid,
                                     s5.empjobtitle
                       FROM zgeneral.activefacultystaff s5) s2
               JOIN (SELECT s.empid,
                           listagg(nvl(f.ftvorgn_title, 'UNKNOWN'), ':') within GROUP(ORDER BY f.ftvorgn_title) ftvorgn_title
                      FROM (SELECT DISTINCT s4.empid,
                                            s4.empdeptid,
                                            s4.empjobtitle
                              FROM zgeneral.activefacultystaff s4) s
                      LEFT JOIN ftvorgn f
                        ON s.empdeptid = f.ftvorgn_orgn_code
                       AND f.ftvorgn_status_ind = 'A'
                       AND trunc(SYSDATE) BETWEEN f.ftvorgn_eff_date AND f.ftvorgn_nchg_date
                       AND nvl(f.ftvorgn_term_date, SYSDATE) >= SYSDATE
                       AND f.ftvorgn_coas_code = 'U'
                     GROUP BY s.empid) s3
                 ON s2.empid = s3.empid
              WHERE 1 = 1
             --and S2.EMPID = 'L00033404'
             --and length(regexp_replace(':'||S2.EMPJOBTITLE,'[^:]')) > 1
              GROUP BY s2.empid,
                       s3.ftvorgn_title) emp
    ON emp.empid = u.spriden_id
  LEFT JOIN zexec.zsavemal emal
    ON emal.pidm = u.spriden_pidm
   AND emal.emal_code = 'LU'
   AND emal.emal_rank = 1
 WHERE s.spriden_change_ind IS NULL;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || v_instance || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
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
VERSION  DATE    USERNAME  UPDATES
1.0    07-10-2014  nvancil    --Initial release
2.0    06-11-2018 lxhatfield  --rewrote parts to run more efficiently
---     05-24-2023  wgriffith2  --updating code to use job_log
------------------------------------------------------------------------------------------------*/
END etl_aim_robrregaudit_refresh;

procedure etl_aim_rolllevl_refresh (jobnumber number, processid varchar2, processname varchar2) is
/*
Table: utl_d_aim.rolllevl

Primary Keys: CRN, TERM_CODE

Unique index: CRN, TERM_CODE

Purpose:
-

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
v_cpu         NUMBER := 4; -- number of CPUs used for parallelization - do not exceed 20 CPUs [v_mod x --v_cpu] if running simultaneously
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_loop_count  NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_aim_rolllevl_refresh';
v_term        VARCHAR(6);
v_ptrm        VARCHAR(2);
CURSOR c_terms IS
SELECT sobptrm_term_code term,
       sobptrm_ptrm_code ptrm
  FROM sobptrm
  JOIN zbtm.terms_by_group_v tbg
    ON tbg.term_code = sobptrm_term_code
   AND tbg.group_code = 'STD'
   AND tbg.semester IN ('FAL', 'SPR', 'SUM')
   AND sobptrm.sobptrm_ptrm_code IN ('1A', '1B', '1C', '1D')
   AND SYSDATE >= tbg.start_date
   AND tbg.start_date > SYSDATE - 365 * 5
 ORDER BY 1 DESC,
          2 DESC;
CURSOR c_reg IS
WITH cohort AS
 (SELECT ssbsect_term_code term,
         ssbsect_ptrm_code ptrm,
         ssbsect_crn crn,
         ssbsect_subj_code subj,
         ssbsect_crse_numb crse,
         ssbsect_seq_numb sect,
         ssbsect_enrl enrl,
         ssbsect_max_enrl max_enrl,
         CASE
         WHEN ssbsect_crse_numb BETWEEN '100' AND '999'
              AND ssbsect_crse_numb NOT LIKE '%99'
              AND ssbsect_crse_numb NOT LIKE CASE
              WHEN ssbsect_crse_numb > '500' THEN
               '%98'
              ELSE
               'X'
              END
              AND ssbsect_crse_numb NOT LIKE CASE
              WHEN ssbsect_crse_numb > '500' THEN
               '%90'
              ELSE
               'X'
              END
              AND ssbsect_crse_numb NOT LIKE CASE
              WHEN ssbsect_crse_numb > '500' THEN
               '%89'
              ELSE
               'X'
              END
              AND ssbsect_crse_numb NOT LIKE CASE
              WHEN ssbsect_crse_numb > '700' THEN
               '%80'
              ELSE
               'X'
              END
              AND ssbsect_insm_code NOT IN ('IS', 'IP', 'TH')
              AND ssbsect_camp_code = 'D'
              AND ssbsect_seq_numb LIKE '%' || substr(ssbsect_ptrm_code, 2, 1) || '%'
              AND ssbsect_seq_numb NOT LIKE '%E%'
              AND NOT EXISTS (SELECT 'X'
                 FROM ssrattr
                WHERE ssrattr_crn = ssbsect_crn
                  AND ssrattr_term_code = ssbsect_term_code
                  AND ssrattr_attr_code IN ('COEX', 'EDGE', 'SPAN', 'RESD', 'NORT')) THEN
          'Y'
         ELSE
          'N'
         END flag
    FROM ssbsect
   WHERE ssbsect_subj_code NOT IN ('CSER', 'FRSM', 'GRST', 'NEWS', 'NSSR')
     AND ssbsect_term_code = v_term
     AND ssbsect_ptrm_code = v_ptrm
     AND CASE
         WHEN ssbsect_max_enrl = 0
              AND ssbsect_enrl = 0 THEN
          (SELECT DISTINCT 'X'
             FROM sfrstca
            WHERE sfrstca_term_code = ssbsect_term_code
              AND sfrstca_crn = ssbsect_crn
              AND sfrstca_source_cde = 'BASE')
         ELSE
          'X'
         END = 'X')
SELECT cohort.term,
       cohort.ptrm,
       cohort.crn,
       cohort.subj,
       cohort.crse,
       cohort.sect,
       cohort.subj || cohort.crse course,
       days.dte,
       day_desc,
       COUNT(DISTINCT sfrstca_pidm) reg,
       cohort.flag
  FROM sfrstca
  JOIN cohort
    ON cohort.term = sfrstca_term_code
   AND cohort.crn = sfrstca_crn
  JOIN (SELECT sobptrm_term_code trm,
               sobptrm_ptrm_code ptrm,
               day_desc,
               sobptrm_start_date - days_before dte
          FROM sobptrm
         CROSS JOIN (SELECT 0 days_before,
                           'After FCI Drops' day_desc
                      FROM dual
                    UNION
                    SELECT 2 days_before,
                           'Before FCI Drops'
                      FROM dual
                    UNION
                    SELECT 7 days_before,
                           'Week 0'
                      FROM dual
                    UNION
                    SELECT 14 days_before,
                           'Week -1'
                      FROM dual
                    UNION
                    SELECT 21 days_before,
                           'Week -2'
                      FROM dual
                    UNION
                    SELECT 28 days_before,
                           'Week -3'
                      FROM dual
                    UNION
                    SELECT 35 days_before,
                           'Week -4'
                      FROM dual)
         WHERE sobptrm_ptrm_code = v_ptrm
           AND sobptrm_term_code = v_term) days
    ON days.trm = cohort.term
   AND days.ptrm = cohort.ptrm
  JOIN stvrsts
    ON stvrsts_code = sfrstca_rsts_code
   AND stvrsts_incl_sect_enrl = 'Y'
 WHERE sfrstca_source_cde = 'BASE'
   AND sfrstca_seq_number = (SELECT MAX(d.sfrstca_seq_number)
                               FROM sfrstca d
                              WHERE d.sfrstca_pidm = sfrstca.sfrstca_pidm
                                AND d.sfrstca_term_code = sfrstca.sfrstca_term_code
                                AND d.sfrstca_crn = sfrstca.sfrstca_crn
                                AND d.sfrstca_source_cde = 'BASE'
                                AND d.sfrstca_rsts_date <= days.dte)
 GROUP BY cohort.term,
          cohort.ptrm,
          cohort.crn,
          cohort.subj,
          cohort.crse,
          cohort.sect,
          cohort.subj || cohort.crse,
          days.dte,
          day_desc,
          cohort.flag;
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
v_loop_count := 0; -- reset count
v_elapsed    := round((SYSDATE - v_etl_date) * 86400);
v_msg        := 'START - ' || rec.term || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
v_term := rec.term;
v_ptrm := rec.ptrm;
FOR rec IN c_reg
LOOP
v_count := 0; -- reset count
INSERT /*+*/
INTO utl_d_aim.rolllevl
(rolllevl_term,
 rolllevl_ptrm,
 rolllevl_crn,
 rolllevl_subj,
 rolllevl_crse,
 rolllevl_sect,
 rolllevl_course,
 rolllevl_dte,
 rolllevl_day_desc,
 rolllevl_reg,
 rolllevl_flag)
SELECT rec.term,
       rec.ptrm,
       rec.crn,
       rec.subj,
       rec.crse,
       rec.sect,
       rec.course,
       rec.dte,
       rec.day_desc,
       rec.reg,
       rec.flag
  FROM dual
 WHERE NOT EXISTS (SELECT 'X'
          FROM utl_d_aim.rolllevl
         WHERE rolllevl_term = rec.term
           AND rolllevl_ptrm = rec.ptrm
           AND rolllevl_crn = rec.crn
           AND rolllevl_dte = rec.dte
           AND rolllevl_day_desc = rec.day_desc
           AND rolllevl_flag = rec.flag);
v_count := SQL%ROWCOUNT;
COMMIT;
v_loop_count  := v_loop_count + v_count; -- keep running total of rows processed
v_total_count := v_total_count + v_count; -- keep running total of rows processed
END LOOP; --c_reg
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'INSERT - ' || rec.term || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_loop_count));
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
VERSION DATE    USERNAME       UPDATES
1.0   05-11-2018  kcaldwell     --Initial release
---     05-17-2023  wgriffith2  --Dealing with EM courses and updating code to use job_log
---     08-22-2023  wgriffith2  --TKT2758094 - Performance updates
------------------------------------------------------------------------------------------------*/
END etl_aim_rolllevl_refresh;

procedure etl_aim_szrenrl_refresh (jobnumber number, processid varchar2, processname varchar2, mod_number number) is
--
-- PURPOSE: Stages term-level student enrollment and academic metrics since 200740 for analytics and operational reporting.
--
-- TABLE: utl_d_aim.szrenrl
--
-- UNIQUE INDEX: PIDM, TERM_CODE
--
-- CONDITIONS:
-- Processes data one aid year at a time for term groups STD (standard), MED (medical), and ACD (academic).
-- For the LIVE timeframe, includes the current aid year when the run date falls within each group’s window: STD and MED if run date is from 180 days before the group start to 180 days after the group end; ACD if run date is from 180 days before the group start to 365 days after the group end.
-- For the DONE (historical) timeframe, runs only at 00:00 on day 7 (Saturday), includes terms with TERM_CODE >= 200740 that have ended by the run date, and excludes any terms currently in the LIVE window.
-- Performs an incremental refresh by comparing computed source rows to existing szrenrl rows for the same PIDM and TERM_CODE within the selected aid year and group; inserts new rows, updates changed rows, and deletes rows only for LIVE terms when the student no longer has qualifying enrollment.
-- Includes only students who have course enrollment records in utl_d_aim.szrcrse for the selected aid year and group.
-- Includes only academic levels that have awardable credit (szrlevl_has_awardable_cred = 'Y').
-- Uses the student’s curriculum snapshot (zexec.zsavlcur) effective for the term to set camp_code, levl_code, program, and major/minor context (term_code between from_term and end_term).
-- Determines enrollment status (FT/PT) by comparing total term credit hours to the full-time credit-hour threshold (RORCRHR) for the student’s level in the term; FT if hours = threshold, otherwise PT.
-- Derives academic classification:
-- For level AC, uses the most recent LUOA attribute description effective on or before the term from SGRSATT and STVATTS.
-- For other levels, maps SGRCLSR class codes by earned hours prior to the term to labeled values (1_Freshman, 2_Sophomore, 3_Junior, 4_Senior).
-- Counts distinct course sections taken in the term as term seats (distinct CRNs).
-- Calculates term hours as total credit hours attempted; audit hours where STVRSTS_INCL_SECT_ENRL = 'N'; withdraw hours where STVRSTS_WITHDRAW_IND = 'Y'.
-- Splits hours by campus and sub-term: Resident hours when camp_code = 'R'; LUO/online hours when camp_code = 'D'; sub-term hours by PTRM_CODE (1A, 1B, 1C, 1D, 1J) and regular resident term 'R'.
-- Sets housing as:
-- On-Campus when camp_code = 'R' and an active residence booking exists for the term (zresidence.bookings_all_view).
-- Off-Campus when camp_code = 'R' without a residence booking.
-- Online for all other camp codes.
-- Populates last_term_completed as the most recent SHRTCKN term code prior to the current term within institutional groups (STD, ACD, MED).
-- Flags first/last enrollment across multiple scopes using existence checks in szrenrl:
-- last_enrl_term = Y when no later term exists for the student; otherwise N.
-- last_enrl_term_year = Y when no later term exists in the same aid year; otherwise N.
-- last_enrl_term_levl = Y when no later term exists at the same academic level; otherwise N.
-- last_enrl_term_levl_year = Y when no later term exists at the same level within the same aid year; otherwise N.
-- first_enrl_term and its variants mirror the above logic for earlier terms.
-- Determines “last completed” flags using the latest non-null last_term_completed:
-- last_completed_term = Y when the latest completed term equals the current term; otherwise N.
-- last_completed_term_year = Y when the latest completed term is in the same aid year as the current term; otherwise N.
-- last_completed_term_levl = Y when the latest completed term equals the current term at the same level; otherwise N.
-- last_completed_term_levl_year = Y when the latest completed term is in the same aid year at the same level; otherwise N.
-- Selects person demographics and contacts from utl_d_aim.szriden valid for the term (term end date between SZRIDEN_FROM_DATE and SZRIDEN_TO_DATE): age at term start date, gender, state, ZIP5, nation, phones, emails, parent emails, IPEDS ethnicity, and IPEDS visa.
-- Aggregates administrative holds from SPRHOLD as a comma-separated list for codes BR, EA, and DC that are active on the term end date.
-- Maps military status from SGRSATT as-of the term to one of: Active Duty, Reserves/National Guard, Veteran, Spouse, Dependent Child, or Military Ties; sets a military attribute flag (Y) when code MILT is present as-of the term.
-- Computes GPA and hours at the student’s level:
-- Cumulative GPA and cumulative hours include all institutional GPA records up to and including the term (SHRTGPA, gpa_type_ind = 'I', hours > 0).
-- Institutional hours are those with gpa_type_ind = 'I'; transfer hours use gpa_type_ind = 'T'.
-- GPA as of prior term uses institutional records strictly before the term; cumulative hours as-of prior term include only records before the term with positive GPA hours.
-- Term GPA comes from SHRTGPA for the exact term and level.
-- Sets student type (STYP) from the most recent admitted application (ZEXEC.ZSAVAPPL) for the student’s level and campus, excluding withdrawn applications and requiring accepted decisions (STVAPDC_INST_ACC_IND = 'Y' or APDC_CODE = 'EI'); defaults to 'C' when none; for resident fall STD terms also checks the prior term (TERM_CODE - 10).
-- Derives academic standing:
-- astd_asof_term and astd_code_asof_term from the most recent prior term’s end-of-term standing within the student’s curriculum and level (SHRTTRM/STVASTD).
-- term_astd and term_astd_code from the current term’s end-of-term standing.
-- Populates LUCOM fields from SGRCHRT as-of the term: lucom_cohort (codes matching CO####) and lucom_classification (codes beginning ‘OMS-’).
-- Pulls degree audit metrics (hours required/applied/remaining, in-progress applied hours, completion percentages) from ZDEGREE_AUDIT.DAVAUDIT for current, non-what-if audits at the term.
-- Assigns yr_rank as the position of the term within the aid year (descending term_code) to support first/last-of-year logic.
-- Limits the comparison set (existing rows) to the same aid year and group as the computed set.
-- Uses parallel processing by partitioning work on PIDM with MOD(PIDM, v_mod) = v_partition.
--
-- URL: N/A
--
--DECLARE
v_etl_date    DATE := SYSDATE;
v_partition    NUMBER := mod_number; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_mod         NUMBER := 5; -- number of partitions; defaulted to 1 if no partitioning is needed; **must be greater than v_partition**
v_msg         VARCHAR2(2000 CHAR);
v_job_id      VARCHAR2(32);
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_row_max     NUMBER := 1000000; -- max number of rows to be processed at one time
v_proc     VARCHAR2(100) := 'etl_aim_szrenrl_refresh';
v_instance VARCHAR2(100) := 'ALL';
CURSOR c_terms IS
SELECT -- WE HAVE TO LOOP THROUGH BY ACADEMIC YEAR; BUT OF THE TERM RANKING STUFF WE HAVE TO DO
DISTINCT t.fa_proc_year AS aidy_code,
         t.group_code,
         'LIVE' AS timeframe,
         to_char(v_etl_date, 'HH24') AS hr24,
         to_char(v_etl_date, 'D') AS day_of_week
  FROM zbtm.terms_by_group_v t
 WHERE ((t.group_code IN ('STD') AND v_etl_date >= t.start_date - 180 AND v_etl_date <= t.end_date + 180) -- must always get current aidy to ensure first and last term enrl is accurate
       OR (t.group_code IN ('MED') AND v_etl_date >= t.start_date - 180 AND v_etl_date <= t.end_date + 180) -- must always get current aidy to ensure first and last term enrl is accurate
       OR (t.group_code IN ('ACD') AND v_etl_date >= t.start_date - 180 AND v_etl_date <= t.end_date + 365)) -- must always get current aidy to ensure first and last term enrl is accurate
UNION ALL
-- SPECIAL RUNS TO CHECK FOR ANY GRADES OR ENROLLMENT CHANGES ON NON-ACTIVE TERMS
SELECT -- WE HAVE TO LOOP THROUGH BY ACADEMIC YEAR; BUT OF THE TERM RANKING STUFF WE HAVE TO DO
DISTINCT terms.fa_proc_year AS aidy_code,
         terms.group_code,
         'DONE' AS timeframe,
         to_char(v_etl_date, 'HH24') AS hr24,
         to_char(v_etl_date, 'D') AS day_of_week
  FROM zbtm.terms_by_group_v terms
 WHERE group_code IN ('STD', 'MED', 'ACD')
   AND terms.term_code >= '200740'
   AND terms.end_date <= v_etl_date -- only get terms that have ended; no future
   AND to_char(v_etl_date, 'HH24') IN ('00') -- special timeframe for this to run; this must be v_etl_date **NOT** SYSDATE bc of the possibilty of long runtime
   AND to_char(v_etl_date, 'D') IN ('7') -- special timeframe for this to run; this must be v_etl_date **NOT** SYSDATE bc of the possibilty of long runtime
   AND NOT EXISTS (SELECT t.term_code,
               t.group_code
          FROM zbtm.terms_by_group_v t
         WHERE 1 = 1
           AND t.term_code = terms.term_code
           AND ((t.group_code IN ('STD') AND SYSDATE >= t.start_date - 180 AND SYSDATE <= t.end_date + 180) --
               OR (t.group_code IN ('MED') AND SYSDATE >= t.start_date - 180 AND SYSDATE <= t.end_date + 180) -- run once a day only
               OR (t.group_code IN ('ACD') AND SYSDATE >= t.start_date - 180 AND SYSDATE <= t.end_date + 365)))
 ORDER BY timeframe  ASC,
          group_code DESC,
          aidy_code  DESC;
CURSOR c1(v_aidy_code  VARCHAR,
          v_group_code VARCHAR,
          v_timeframe  VARCHAR) IS
SELECT *
  FROM (SELECT COUNT(*) over() total_rows,
               CASE
               WHEN tgt.pidm IS NOT NULL
                    AND src.pidm IS NULL THEN
                'INSERT' -- new record to source, add to table
               WHEN tgt.pidm IS NOT NULL
                    AND src.pidm IS NOT NULL THEN
                'UPDATE' -- record exists in both places
               WHEN v_timeframe = 'LIVE' -- **ONLY REMOVE IF IT IS A LIVE TERM**
                    AND tgt.pidm IS NULL
                    AND src.pidm IS NOT NULL THEN
                'DELETE' -- no record longer exists on the source data, remove it
               END AS control_state,
               coalesce(tgt.pidm, src.pidm) AS pidm,
               coalesce(tgt.term_code, src.term_code) AS term_code,
               tgt.group_code,
               tgt.semester,
               tgt.acad_year,
               tgt.status,
               tgt.classification,
               tgt.term_seats,
               tgt.term_hours,
               tgt.res_hours,
               tgt.luo_hours,
               tgt.au_hours,
               tgt.a_hours,
               tgt.b_hours,
               tgt.c_hours,
               tgt.d_hours,
               tgt.j_hours,
               tgt.r_hours,
               tgt.fci_date,
               tgt.yr_rank,
               tgt.housing,
               tgt.last_term_completed,
               tgt.last_enrl_term,
               tgt.last_enrl_term_year,
               tgt.last_enrl_term_levl,
               tgt.last_enrl_term_levl_year,
               tgt.first_enrl_term,
               tgt.first_enrl_term_year,
               tgt.first_enrl_term_levl,
               tgt.first_enrl_term_levl_year,
               tgt.camp_code,
               tgt.levl_code,
               tgt.prog_code_1,
               tgt.prog_code_2,
               tgt.prog_code_3,
               tgt.prog_code_4,
               tgt.majr_code_1,
               tgt.majr_code_2,
               tgt.majr_desc_1,
               tgt.majr_desc_2,
               tgt.degc_code_1,
               tgt.degc_code_2,
               tgt.degc_levl_1,
               tgt.degc_levl_2,
               tgt.ctlg_term_1,
               tgt.ctlg_term_2,
               tgt.ctlg_term_3,
               tgt.ctlg_term_4,
               tgt.coll_desc_1,
               tgt.coll_desc_2,
               tgt.dept_desc_1,
               tgt.dept_desc_2,
               tgt.minr_1,
               tgt.minr_2,
               tgt.minr_3,
               tgt.minr_4,
               tgt.ctlg_minr_1,
               tgt.ctlg_minr_2,
               tgt.ctlg_minr_3,
               tgt.ctlg_minr_4,
               tgt.luid,
               tgt.last_name,
               tgt.first_name,
               tgt.age,
               tgt.ipeds_ethn,
               tgt.ipeds_visa,
               tgt.state,
               tgt.zip5,
               tgt.phone,
               tgt.phone_text,
               tgt.nation,
               tgt.gender,
               tgt.lu_email,
               tgt.alt_email,
               tgt.parent_email_1,
               tgt.parent_email_2,
               tgt.milt_status,
               tgt.milt_attr,
               tgt.admn_holds,
               tgt.cum_gpa,
               tgt.cum_hours,
               tgt.inst_hours,
               tgt.tran_hours,
               tgt.gpa_asof_term,
               tgt.cum_hours_asof_term,
               tgt.term_gpa,
               tgt.styp_code,
               tgt.activity_date,
               tgt.astd_asof_term,
               tgt.term_astd,
               tgt.hrs_required,
               tgt.hrs_applied,
               tgt.hrs_remaining,
               tgt.hrs_applied_ip,
               tgt.hrs_pct_done,
               tgt.req_pct_done,
               tgt.astd_code_asof_term,
               tgt.term_astd_code,
               tgt.lucom_cohort,
               tgt.lucom_classification,
               tgt.prog_2_hrs_required,
               tgt.prog_2_hrs_applied,
               tgt.prog_2_hrs_remaining,
               tgt.prog_2_applied_ip,
               tgt.prog_2_hrs_pct_done,
               tgt.prog_2_req_pct_done,
               tgt.last_completed_term,
               tgt.last_completed_term_year,
               tgt.last_completed_term_levl,
               tgt.last_completed_term_levl_year,
               tgt.wd_hours,
               src.pidm AS src_pidm,
               src.term_code AS src_term_code,
               src.group_code AS src_group_code,
               src.semester AS src_semester,
               src.acad_year AS src_acad_year,
               src.status AS src_status,
               src.classification AS src_classification,
               src.term_seats AS src_term_seats,
               src.term_hours AS src_term_hours,
               src.res_hours AS src_res_hours,
               src.luo_hours AS src_luo_hours,
               src.au_hours AS src_au_hours,
               src.a_hours AS src_a_hours,
               src.b_hours AS src_b_hours,
               src.c_hours AS src_c_hours,
               src.d_hours AS src_d_hours,
               src.j_hours AS src_j_hours,
               src.r_hours AS src_r_hours,
               src.fci_date AS src_fci_date,
               src.yr_rank AS src_yr_rank,
               src.housing AS src_housing,
               src.last_term_completed AS src_last_term_completed,
               src.last_enrl_term AS src_last_enrl_term,
               src.last_enrl_term_year AS src_last_enrl_term_year,
               src.last_enrl_term_levl AS src_last_enrl_term_levl,
               src.last_enrl_term_levl_year AS src_last_enrl_term_levl_year,
               src.first_enrl_term AS src_first_enrl_term,
               src.first_enrl_term_year AS src_first_enrl_term_year,
               src.first_enrl_term_levl AS src_first_enrl_term_levl,
               src.first_enrl_term_levl_year AS src_first_enrl_term_levl_year,
               src.camp_code AS src_camp_code,
               src.levl_code AS src_levl_code,
               src.prog_code_1 AS src_prog_code_1,
               src.prog_code_2 AS src_prog_code_2,
               src.prog_code_3 AS src_prog_code_3,
               src.prog_code_4 AS src_prog_code_4,
               src.majr_code_1 AS src_majr_code_1,
               src.majr_code_2 AS src_majr_code_2,
               src.majr_desc_1 AS src_majr_desc_1,
               src.majr_desc_2 AS src_majr_desc_2,
               src.degc_code_1 AS src_degc_code_1,
               src.degc_code_2 AS src_degc_code_2,
               src.degc_levl_1 AS src_degc_levl_1,
               src.degc_levl_2 AS src_degc_levl_2,
               src.ctlg_term_1 AS src_ctlg_term_1,
               src.ctlg_term_2 AS src_ctlg_term_2,
               src.ctlg_term_3 AS src_ctlg_term_3,
               src.ctlg_term_4 AS src_ctlg_term_4,
               src.coll_desc_1 AS src_coll_desc_1,
               src.coll_desc_2 AS src_coll_desc_2,
               src.dept_desc_1 AS src_dept_desc_1,
               src.dept_desc_2 AS src_dept_desc_2,
               src.minr_1 AS src_minr_1,
               src.minr_2 AS src_minr_2,
               src.minr_3 AS src_minr_3,
               src.minr_4 AS src_minr_4,
               src.ctlg_minr_1 AS src_ctlg_minr_1,
               src.ctlg_minr_2 AS src_ctlg_minr_2,
               src.ctlg_minr_3 AS src_ctlg_minr_3,
               src.ctlg_minr_4 AS src_ctlg_minr_4,
               src.luid AS src_luid,
               src.last_name AS src_last_name,
               src.first_name AS src_first_name,
               src.age AS src_age,
               src.ipeds_ethn AS src_ipeds_ethn,
               src.ipeds_visa AS src_ipeds_visa,
               src.state AS src_state,
               src.zip5 AS src_zip5,
               src.phone AS src_phone,
               src.phone_text AS src_phone_text,
               src.nation AS src_nation,
               src.gender AS src_gender,
               src.lu_email AS src_lu_email,
               src.alt_email AS src_alt_email,
               src.parent_email_1 AS src_parent_email_1,
               src.parent_email_2 AS src_parent_email_2,
               src.milt_status AS src_milt_status,
               src.milt_attr AS src_milt_attr,
               src.admn_holds AS src_admn_holds,
               src.cum_gpa AS src_cum_gpa,
               src.cum_hours AS src_cum_hours,
               src.inst_hours AS src_inst_hours,
               src.tran_hours AS src_tran_hours,
               src.gpa_asof_term AS src_gpa_asof_term,
               src.cum_hours_asof_term AS src_cum_hours_asof_term,
               src.term_gpa AS src_term_gpa,
               src.styp_code AS src_styp_code,
               src.activity_date AS src_activity_date,
               src.astd_asof_term AS src_astd_asof_term,
               src.term_astd AS src_term_astd,
               src.hrs_required AS src_hrs_required,
               src.hrs_applied AS src_hrs_applied,
               src.hrs_remaining AS src_hrs_remaining,
               src.hrs_applied_ip AS src_hrs_applied_ip,
               src.hrs_pct_done AS src_hrs_pct_done,
               src.req_pct_done AS src_req_pct_done,
               src.astd_code_asof_term AS src_astd_code_asof_term,
               src.term_astd_code AS src_term_astd_code,
               src.lucom_cohort AS src_lucom_cohort,
               src.lucom_classification AS src_lucom_classification,
               src.prog_2_hrs_required AS src_prog_2_hrs_required,
               src.prog_2_hrs_applied AS src_prog_2_hrs_applied,
               src.prog_2_hrs_remaining AS src_prog_2_hrs_remaining,
               src.prog_2_applied_ip AS src_prog_2_applied_ip,
               src.prog_2_hrs_pct_done AS src_prog_2_hrs_pct_done,
               src.prog_2_req_pct_done AS src_prog_2_req_pct_done,
               src.last_completed_term AS src_last_completed_term,
               src.last_completed_term_year AS src_last_completed_term_year,
               src.last_completed_term_levl AS src_last_completed_term_levl,
               src.last_completed_term_levl_year AS src_last_completed_term_levl_year,
               src.wd_hours AS src_wd_hours
          FROM (SELECT regs_pidm pidm,
                       regs_term_code term_code,
                       regs_group_code group_code,
                       regs_semester semester,
                       regs_acad_year acad_year,
                       regs_status status,
                       CASE
                       WHEN regs_class = 'AC' THEN
                        (SELECT MAX(stvatts_desc) -- sgrsatt_atts_code
                           FROM sgrsatt
                           JOIN stvatts
                             ON stvatts_code = sgrsatt_atts_code
                          WHERE sgrsatt_pidm = regs_pidm
                            AND sgrsatt.sgrsatt_atts_code IN (SELECT zfrlist_key1_code luoa_attr
                                                                FROM zformdata.zfrlist d
                                                               WHERE zfrlist_list_code = 'LUOA_ATTRIBUTE_EXT'
                                                                 AND zfrlist_active_yn = 'Y')
                            AND sgrsatt.sgrsatt_term_code_eff = (SELECT MAX(sgrsatt_term_code_eff)
                                                                   FROM saturn.sgrsatt sgrsatt1
                                                                  WHERE sgrsatt1.sgrsatt_pidm = sgrsatt.sgrsatt_pidm
                                                                    AND sgrsatt1.sgrsatt_term_code_eff <= regs_term_code))
                       ELSE
                        decode(stvclas_code, 'FR', '1_', 'SO', '2_', 'JR', '3_', 'SR', '4_') || stvclas_desc
                       END classification,
                       regs_term_seats term_seats,
                       regs_term_hours term_hours,
                       regs_res_hours res_hours,
                       regs_luo_hours luo_hours,
                       regs_au_hours au_hours,
                       regs_a_hours a_hours,
                       regs_b_hours b_hours,
                       regs_c_hours c_hours,
                       regs_d_hours d_hours,
                       regs_j_hours j_hours,
                       regs_r_hours r_hours,
                       regs_wd_hours wd_hours,
                       regs_fci_date fci_date,
                       rank() over(PARTITION BY regs_pidm, regs_acad_year ORDER BY regs_term_code DESC, rownum) AS yr_rank,
                       CASE
                       WHEN lcur.camp_code = 'R'
                            AND bav.pidm IS NOT NULL THEN
                        'On-Campus'
                       WHEN lcur.camp_code = 'R'
                            AND bav.pidm IS NULL THEN
                        'Off-Campus'
                       ELSE
                        'Online'
                       END housing,
                       regs_last_term_completed last_term_completed,
                       CASE
                       WHEN EXISTS (SELECT 'X'
                               FROM utl_d_aim.szrenrl b
                              WHERE b.pidm = regs_pidm
                                AND b.term_code > regs_term_code) THEN
                        'N'
                       ELSE
                        'Y'
                       END last_enrl_term,
                       CASE
                       WHEN EXISTS (SELECT 'X'
                               FROM utl_d_aim.szrenrl b
                              WHERE b.pidm = regs_pidm
                                AND b.term_code > regs_term_code
                                AND b.acad_year = regs_acad_year) THEN
                        'N'
                       ELSE
                        'Y'
                       END last_enrl_term_year,
                       CASE
                       WHEN EXISTS (SELECT 'X'
                               FROM utl_d_aim.szrenrl b
                              WHERE b.pidm = regs_pidm
                                AND b.levl_code = lcur.levl_code
                                AND b.term_code > regs_term_code) THEN
                        'N'
                       ELSE
                        'Y'
                       END last_enrl_term_levl,
                       CASE
                       WHEN EXISTS (SELECT 'X'
                               FROM utl_d_aim.szrenrl b
                              WHERE b.pidm = regs_pidm
                                AND b.levl_code = lcur.levl_code
                                AND b.acad_year = regs_acad_year
                                AND b.term_code > regs_term_code) THEN
                        'N'
                       ELSE
                        'Y'
                       END last_enrl_term_levl_year,
                       CASE
                       WHEN EXISTS (SELECT 'X'
                               FROM utl_d_aim.szrenrl b
                              WHERE b.pidm = regs_pidm
                                AND b.term_code < regs_term_code) THEN
                        'N'
                       ELSE
                        'Y'
                       END first_enrl_term,
                       CASE
                       WHEN EXISTS (SELECT 'X'
                               FROM utl_d_aim.szrenrl b
                              WHERE b.pidm = regs_pidm
                                AND b.acad_year = regs_acad_year
                                AND b.term_code < regs_term_code) THEN
                        'N'
                       ELSE
                        'Y'
                       END first_enrl_term_year,
                       CASE
                       WHEN EXISTS (SELECT 'X'
                               FROM utl_d_aim.szrenrl b
                              WHERE b.pidm = regs_pidm
                                AND b.levl_code = lcur.levl_code
                                AND b.term_code < regs_term_code) THEN
                        'N'
                       ELSE
                        'Y'
                       END first_enrl_term_levl,
                       CASE
                       WHEN EXISTS (SELECT 'X'
                               FROM utl_d_aim.szrenrl b
                              WHERE b.pidm = regs_pidm
                                AND b.levl_code = lcur.levl_code
                                AND b.acad_year = regs_acad_year
                                AND b.term_code < regs_term_code) THEN
                        'N'
                       ELSE
                        'Y'
                       END first_enrl_term_levl_year,
                       lcur.camp_code camp_code,
                       lcur.levl_code levl_code,
                       lcur.prog_code_1 prog_code_1,
                       lcur.prog_code_2 prog_code_2,
                       lcur.prog_code_3 prog_code_3,
                       lcur.prog_code_4 prog_code_4,
                       mj1.stvmajr_code majr_code_1,
                       mj2.stvmajr_code majr_code_2,
                       mj1.stvmajr_desc majr_desc_1,
                       mj2.stvmajr_desc majr_desc_2,
                       lcur.degc_code_1 degc_code_1,
                       lcur.degc_code_2 degc_code_2,
                       dlev1.stvdlev_desc degc_levl_1,
                       dlev2.stvdlev_desc degc_levl_2,
                       lcur.prog_ctlg_1 ctlg_term_1,
                       lcur.prog_ctlg_2 ctlg_term_2,
                       lcur.prog_ctlg_3 ctlg_term_3,
                       lcur.prog_ctlg_4 ctlg_term_4,
                       c1.stvcoll_desc coll_desc_1,
                       c2.stvcoll_desc coll_desc_2,
                       dep1.stvdept_desc dept_desc_1,
                       dep2.stvdept_desc dept_desc_2,
                       m1.stvmajr_desc minr_1,
                       m2.stvmajr_desc minr_2,
                       m3.stvmajr_desc minr_3,
                       m4.stvmajr_desc minr_4,
                       lcur.minr_ctlg_1 ctlg_minr_1,
                       lcur.minr_ctlg_2 ctlg_minr_2,
                       lcur.minr_ctlg_3 ctlg_minr_3,
                       NULL ctlg_minr_4,
                       szriden_id luid,
                       szriden_last_name last_name,
                       szriden_first_name first_name,
                       floor((trunc(stvterm_start_date) - szriden_birth_date) / 365.25) age,
                       szriden_ipeds_ethn ipeds_ethn,
                       szriden_ipeds_visa ipeds_visa,
                       szriden_stat_code state,
                       szriden_zip5 zip5,
                       szriden_phone phone,
                       szriden_phone_text phone_text,
                       szriden_nation nation,
                       szriden_sex gender,
                       szriden_lu_email lu_email,
                       szriden_alt_email alt_email,
                       szriden_parent_email_1 parent_email_1,
                       szriden_parent_email_2 parent_email_2,
                       (SELECT MIN(CASE
                                   WHEN sgrsatt_atts_code = 'MLAD' THEN
                                    '1_Active_Duty'
                                   WHEN sgrsatt_atts_code IN ('MLRS', 'MLNG') THEN
                                    '2_Reserves/National_Guard'
                                   WHEN sgrsatt_atts_code IN ('MLRT', 'MLDC') THEN
                                    '3_Veteran'
                                   WHEN sgrsatt_atts_code = 'MLSP' THEN
                                    '4_Spouse'
                                   WHEN sgrsatt_atts_code = 'MLCD' THEN
                                    '5_Dependent_Child'
                                   WHEN sgrsatt_atts_code = 'MILT' THEN
                                    '6_Milt_Ties'
                                   END)
                          FROM sgrsatt
                         WHERE sgrsatt_pidm = regs_pidm
                           AND sgrsatt_atts_code IN ('MLAD', 'MLRS', 'MLNG', 'MLRT', 'MLDC', 'MLCD', 'MLSP', 'MILT')
                           AND sgrsatt_term_code_eff = (SELECT MAX(d.sgrsatt_term_code_eff)
                                                          FROM sgrsatt d
                                                         WHERE d.sgrsatt_pidm = sgrsatt.sgrsatt_pidm
                                                           AND d.sgrsatt_term_code_eff <= regs_term_code)) milt_status,
                       (SELECT MAX(CAST('Y' AS VARCHAR2(1)))
                          FROM sgrsatt
                         WHERE sgrsatt_pidm = regs_pidm
                           AND sgrsatt_atts_code = 'MILT'
                           AND sgrsatt_term_code_eff = (SELECT MAX(d.sgrsatt_term_code_eff)
                                                          FROM sgrsatt d
                                                         WHERE d.sgrsatt_pidm = sgrsatt.sgrsatt_pidm
                                                           AND d.sgrsatt_term_code_eff <= regs_term_code)) milt_attr,
                       (SELECT listagg(sprhold_hldd_code, ',') within GROUP(ORDER BY sprhold_hldd_code)
                          FROM sprhold
                         WHERE sprhold_pidm = regs_pidm
                           AND sprhold_hldd_code IN ('BR', 'EA', 'DC')
                           AND regs_end_date BETWEEN sprhold_from_date AND sprhold_to_date) admn_holds,
                       (SELECT round(SUM(shrtgpa_quality_points) / SUM(shrtgpa_gpa_hours), 4)
                          FROM shrtgpa
                         WHERE shrtgpa_pidm = regs_pidm
                           AND shrtgpa_levl_code = lcur.levl_code
                           AND shrtgpa_term_code <= regs_term_code -- snapshotting end of term numbers
                           AND shrtgpa_gpa_type_ind = 'I'
                           AND shrtgpa_gpa_hours > 0) AS cum_gpa,
                       (SELECT SUM(shrtgpa_hours_earned)
                          FROM shrtgpa
                         WHERE shrtgpa_pidm = regs_pidm
                           AND shrtgpa_levl_code = lcur.levl_code
                           AND shrtgpa_term_code <= regs_term_code -- snapshotting end of term numbers
                        ) AS cum_hours,
                       (SELECT SUM(shrtgpa_hours_earned)
                          FROM shrtgpa
                         WHERE shrtgpa_pidm = regs_pidm
                           AND shrtgpa_levl_code = lcur.levl_code
                           AND shrtgpa_term_code <= regs_term_code -- snapshotting end of term numbers
                           AND shrtgpa_gpa_type_ind = 'I') AS inst_hours,
                       (SELECT SUM(shrtgpa_hours_earned)
                          FROM shrtgpa
                         WHERE shrtgpa_pidm = regs_pidm
                           AND shrtgpa_levl_code = lcur.levl_code
                           AND shrtgpa_term_code <= regs_term_code -- snapshotting end of term numbers
                           AND shrtgpa_gpa_type_ind = 'T') AS tran_hours,
                       (SELECT round(SUM(shrtgpa_quality_points) / SUM(shrtgpa_gpa_hours), 4)
                          FROM shrtgpa
                         WHERE shrtgpa_pidm = regs_pidm
                           AND shrtgpa_levl_code = lcur.levl_code
                           AND shrtgpa_term_code < regs_term_code
                           AND shrtgpa_gpa_type_ind = 'I'
                           AND shrtgpa_gpa_hours > 0) gpa_asof_term,
                       (SELECT SUM(shrtgpa_hours_earned)
                          FROM shrtgpa
                         WHERE shrtgpa_pidm = regs_pidm
                           AND shrtgpa_levl_code = lcur.levl_code
                           AND shrtgpa_term_code < regs_term_code
                           AND shrtgpa_gpa_hours > 0) cum_hours_asof_term,
                       round(shrtgpa_gpa, 4) term_gpa,
                       nvl((SELECT MAX(zsavappl_styp_code) keep(dense_rank FIRST ORDER BY zsavappl_term_code DESC, zsavappl_appl_no DESC, rownum)
                             FROM zexec.zsavappl
                            WHERE zsavappl_pidm = regs_pidm
                              AND zsavappl_levl_code = lcur.levl_code
                              AND zsavappl_camp_code = lcur.camp_code
                              AND zsavappl_apst_code <> 'W'
                              AND zsavappl_apdc_code IN (SELECT stvapdc_code
                                                           FROM stvapdc
                                                          WHERE stvapdc_inst_acc_ind = 'Y'
                                                             OR stvapdc_code = 'EI')
                              AND zsavappl_term_code IN (regs_term_code, CASE WHEN lcur.camp_code = 'R' AND regs_semester = 'FAL' AND regs_group_code = 'STD' THEN regs_term_code - 10 END)), 'C') styp_code,
                       v_etl_date AS activity_date,
                       (SELECT MAX(stvastd_desc) keep(dense_rank FIRST ORDER BY shrttrm_term_code DESC)
                          FROM shrttrm
                          JOIN stvastd
                            ON stvastd_code = shrttrm_astd_code_end_of_term
                          JOIN zexec.zsavlcur lcura
                            ON lcura.pidm = shrttrm_pidm
                           AND shrttrm_term_code BETWEEN lcura.from_term AND lcura.end_term
                           AND lcura.levl_code = lcur.levl_code
                         WHERE shrttrm_pidm = regs_pidm
                           AND shrttrm_term_code < regs_term_code) astd_asof_term,
                       (SELECT MAX(stvastd_desc)
                          FROM shrttrm
                          JOIN stvastd
                            ON stvastd_code = shrttrm_astd_code_end_of_term
                         WHERE shrttrm_pidm = regs_pidm
                           AND shrttrm_term_code = regs_term_code) term_astd,
                       v1.hrs_required,
                       v1.hrs_applied,
                       v1.hrs_remaining,
                       v1.hrs_applied_ip,
                       v1.hrs_pct_done,
                       v1.req_pct_done,
                       (SELECT MAX(stvastd_code) keep(dense_rank FIRST ORDER BY shrttrm_term_code DESC)
                          FROM shrttrm
                          JOIN stvastd
                            ON stvastd_code = shrttrm_astd_code_end_of_term
                          JOIN zexec.zsavlcur lcura
                            ON lcura.pidm = shrttrm_pidm
                           AND shrttrm_term_code BETWEEN lcura.from_term AND lcura.end_term
                           AND lcura.levl_code = lcur.levl_code
                         WHERE shrttrm_pidm = regs_pidm
                           AND shrttrm_term_code < regs_term_code) astd_code_asof_term,
                       (SELECT MAX(stvastd_code)
                          FROM shrttrm
                          JOIN stvastd
                            ON stvastd_code = shrttrm_astd_code_end_of_term
                         WHERE shrttrm_pidm = regs_pidm
                           AND shrttrm_term_code = regs_term_code) term_astd_code,
                       (SELECT chrt.sgrchrt_chrt_code
                          FROM saturn.sgrchrt chrt
                         WHERE chrt.sgrchrt_pidm = regs_pidm
                           AND regexp_like(chrt.sgrchrt_chrt_code, 'CO[0-9]{4}')
                           AND chrt.sgrchrt_term_code_eff = (SELECT MAX(chrt2.sgrchrt_term_code_eff)
                                                               FROM saturn.sgrchrt chrt2
                                                              WHERE chrt2.sgrchrt_pidm = chrt.sgrchrt_pidm
                                                                AND chrt2.sgrchrt_term_code_eff <= regs_term_code)) lucom_cohort,
                       (SELECT chrt.sgrchrt_chrt_code
                          FROM saturn.sgrchrt chrt
                         WHERE chrt.sgrchrt_pidm = regs_pidm
                           AND chrt.sgrchrt_chrt_code LIKE 'OMS-%'
                           AND chrt.sgrchrt_term_code_eff = (SELECT MAX(chrt2.sgrchrt_term_code_eff)
                                                               FROM saturn.sgrchrt chrt2
                                                              WHERE chrt2.sgrchrt_pidm = chrt.sgrchrt_pidm
                                                                AND chrt2.sgrchrt_term_code_eff <= regs_term_code)) lucom_classification,
                       v2.hrs_required AS prog_2_hrs_required,
                       v2.hrs_applied AS prog_2_hrs_applied,
                       v2.hrs_remaining AS prog_2_hrs_remaining,
                       v2.hrs_applied_ip AS prog_2_applied_ip,
                       v2.hrs_pct_done AS prog_2_hrs_pct_done,
                       v2.req_pct_done AS prog_2_req_pct_done,
                       CASE
                       WHEN EXISTS (SELECT 'x'
                               FROM (SELECT b.last_term_completed,
                                            rank() over(PARTITION BY b.pidm ORDER BY b.last_term_completed DESC NULLS LAST, rownum) ranking
                                       FROM utl_d_aim.szrenrl b
                                      WHERE 1 = 1
                                        AND b.pidm = regs.regs_pidm)
                              WHERE ranking = 1
                                AND last_term_completed = regs_term_code) THEN
                        'Y'
                       ELSE
                        'N'
                       END AS last_completed_term,
                       CASE
                       WHEN EXISTS (SELECT 'x'
                               FROM (SELECT b.last_term_completed,
                                            rank() over(PARTITION BY b.pidm ORDER BY b.last_term_completed DESC NULLS LAST, rownum) ranking
                                       FROM utl_d_aim.szrenrl b
                                      WHERE 1 = 1
                                        AND b.pidm = regs.regs_pidm)
                               JOIN stvterm
                                 ON stvterm_code = last_term_completed
                              WHERE ranking = 1
                                AND stvterm.stvterm_fa_proc_yr = regs.regs_acad_year) THEN
                        'Y'
                       ELSE
                        'N'
                       END AS last_completed_term_year,
                       CASE
                       WHEN EXISTS (SELECT 'x'
                               FROM (SELECT b.last_term_completed,
                                            rank() over(PARTITION BY b.pidm ORDER BY b.last_term_completed DESC NULLS LAST, rownum) ranking
                                       FROM utl_d_aim.szrenrl b
                                      WHERE 1 = 1
                                        AND b.pidm = regs.regs_pidm
                                        AND b.levl_code = lcur.levl_code)
                              WHERE ranking = 1
                                AND last_term_completed = regs_term_code) THEN
                        'Y'
                       ELSE
                        'N'
                       END AS last_completed_term_levl,
                       CASE
                       WHEN EXISTS (SELECT 'x'
                               FROM (SELECT b.last_term_completed,
                                            rank() over(PARTITION BY b.pidm ORDER BY b.last_term_completed DESC NULLS LAST, rownum) ranking
                                       FROM utl_d_aim.szrenrl b
                                      WHERE 1 = 1
                                        AND b.pidm = regs.regs_pidm
                                        AND b.levl_code = lcur.levl_code)
                               JOIN stvterm
                                 ON stvterm_code = last_term_completed
                              WHERE ranking = 1
                                AND stvterm.stvterm_fa_proc_yr = regs.regs_acad_year) THEN
                        'Y'
                       ELSE
                        'N'
                       END AS last_completed_term_levl_year
                  FROM (SELECT s.pidm regs_pidm,
                               s.term_code regs_term_code,
                               s.group_code regs_group_code,
                               s.semester regs_semester,
                               s.acad_year regs_acad_year,
                               MAX(s.ptrm_end) AS regs_end_date,
                               CASE
                               WHEN SUM(s.credit_hr) >= MAX(rorcrhr_full_time_cr_hrs) THEN
                                'FT'
                               ELSE
                                'PT'
                               END regs_status,
                               MAX((SELECT MAX(CASE
                                              WHEN lcur.levl_code = 'AC' THEN
                                               'AC'
                                              ELSE
                                               sgrclsr_clas_code
                                              END)
                                     FROM sgrclsr
                                    WHERE sgrclsr_levl_code = lcur.levl_code
                                      AND nvl((SELECT SUM(shrtgpa_hours_earned)
                                                FROM shrtgpa
                                               WHERE shrtgpa_pidm = s.pidm
                                                 AND shrtgpa_levl_code = lcur.levl_code
                                                 AND shrtgpa_term_code < s.term_code
                                               GROUP BY shrtgpa_pidm), 0) BETWEEN sgrclsr_from_hours AND sgrclsr_to_hours)) regs_class,
                               MAX((SELECT MAX(shrtckn_term_code)
                                     FROM shrtckn
                                     JOIN (SELECT t.term_code,
                                                 t.start_date,
                                                 t.end_date,
                                                 t.group_code
                                            FROM zbtm.terms_by_group_v t
                                           WHERE 1 = 1
                                             AND t.group_code IN ('STD', 'ACD', 'MED')) terms
                                       ON terms.term_code = shrtckn_term_code
                                    WHERE shrtckn_pidm = s.pidm
                                      AND shrtckn_term_code < s.term_code)) regs_last_term_completed,
                               SUM(s.credit_hr) regs_term_hours,
                               SUM(CASE
                                   WHEN stvrsts_withdraw_ind = 'Y' THEN
                                    s.credit_hr
                                   END) regs_wd_hours,
                               SUM(CASE
                                   WHEN stvrsts_incl_sect_enrl = 'N' THEN
                                    s.credit_hr
                                   END) regs_au_hours,
                               COUNT(DISTINCT s.crn) regs_term_seats,
                               SUM(CASE
                                   WHEN s.camp_code = 'R' THEN
                                    s.credit_hr
                                   END) regs_res_hours,
                               SUM(CASE
                                   WHEN s.camp_code = 'D' THEN
                                    s.credit_hr
                                   END) regs_luo_hours,
                               SUM(CASE
                                   WHEN s.ptrm_code = '1A' THEN
                                    s.credit_hr
                                   END) regs_a_hours,
                               SUM(CASE
                                   WHEN s.ptrm_code = '1B' THEN
                                    s.credit_hr
                                   END) regs_b_hours,
                               SUM(CASE
                                   WHEN s.ptrm_code = '1C' THEN
                                    s.credit_hr
                                   END) regs_c_hours,
                               SUM(CASE
                                   WHEN s.ptrm_code = '1D' THEN
                                    s.credit_hr
                                   END) regs_d_hours,
                               SUM(CASE
                                   WHEN s.ptrm_code = '1J' THEN
                                    s.credit_hr
                                   END) regs_j_hours,
                               SUM(CASE
                                   WHEN s.ptrm_code = 'R' THEN
                                    s.credit_hr
                                   END) regs_r_hours,
                               MAX((SELECT MAX(zfrfcis_create_date)
                                     FROM zfincheckin.zfrfcis
                                    WHERE zfrfcis_pidm = s.pidm
                                      AND zfrfcis_term = s.term_code
                                      AND zfrfcis_withdrawn IS NULL)) regs_fci_date
                          FROM utl_d_aim.szrcrse s
                          JOIN stvrsts
                            ON stvrsts_code = s.rsts_code
                           AND s.acad_year = v_aidy_code -- we must pull the whole year to get the first and last ranks accurate
                           AND s.group_code = v_group_code
                           AND MOD(s.pidm, v_mod) = v_partition
                          JOIN zexec.zsavlcur lcur
                            ON lcur.pidm = s.pidm
                           AND s.term_code BETWEEN lcur.from_term AND lcur.end_term
                          JOIN zsaturn.szrlevl l
                            ON l.szrlevl_levl_code = s.levl_code
                           AND l.szrlevl_has_awardable_cred = 'Y'
                          LEFT JOIN rorcrhr
                            ON rorcrhr_term_code = s.term_code
                           AND rorcrhr_levl_code = lcur.levl_code
                         GROUP BY s.pidm,
                                  s.term_code,
                                  s.group_code,
                                  s.semester,
                                  s.acad_year,
                                  lcur.levl_code) regs
                  JOIN utl_d_aim.szriden
                    ON szriden_pidm = regs_pidm
                   AND regs_end_date BETWEEN szriden_from_date AND szriden_to_date
                  JOIN stvterm
                    ON stvterm_code = regs_term_code
                  JOIN zexec.zsavlcur lcur
                    ON lcur.pidm = regs_pidm
                   AND regs_term_code BETWEEN lcur.from_term AND lcur.end_term
                  LEFT JOIN shrlgpa o
                    ON o.shrlgpa_pidm = regs_pidm
                   AND o.shrlgpa_gpa_type_ind = 'O'
                   AND o.shrlgpa_levl_code = lcur.levl_code
                  LEFT JOIN shrlgpa i
                    ON i.shrlgpa_pidm = regs_pidm
                   AND i.shrlgpa_gpa_type_ind = 'I'
                   AND i.shrlgpa_levl_code = lcur.levl_code
                  LEFT JOIN shrlgpa t
                    ON t.shrlgpa_pidm = regs_pidm
                   AND t.shrlgpa_gpa_type_ind = 'T'
                   AND t.shrlgpa_levl_code = lcur.levl_code
                  LEFT JOIN shrtgpa
                    ON shrtgpa_pidm = regs_pidm
                   AND shrtgpa_gpa_type_ind = 'I'
                   AND shrtgpa_term_code = regs_term_code
                   AND shrtgpa_levl_code = lcur.levl_code
                  LEFT JOIN zresidence.bookings_all_view bav
                    ON bav.pidm = regs_pidm
                   AND bav.term = regs_term_code
                  LEFT JOIN stvcoll c1
                    ON c1.stvcoll_code = lcur.prog_coll_1
                  LEFT JOIN stvcoll c2
                    ON c2.stvcoll_code = lcur.prog_coll_2
                  LEFT JOIN stvdept dep1
                    ON dep1.stvdept_code = lcur.majr_dept_1
                  LEFT JOIN stvdept dep2
                    ON dep2.stvdept_code = lcur.majr_dept_2
                  LEFT JOIN stvmajr mj1
                    ON mj1.stvmajr_code = lcur.majr_code_1
                  LEFT JOIN stvmajr mj2
                    ON mj2.stvmajr_code = lcur.majr_code_2
                  LEFT JOIN stvmajr m1
                    ON m1.stvmajr_code = lcur.minr_code_1
                  LEFT JOIN stvmajr m2
                    ON m2.stvmajr_code = lcur.minr_code_2
                  LEFT JOIN stvmajr m3
                    ON m3.stvmajr_code = lcur.minr_code_3
                  LEFT JOIN stvmajr m4
                    ON m4.stvmajr_code = lcur.minr_code_4
                  LEFT JOIN stvclas
                    ON stvclas_code = regs_class
                  LEFT JOIN stvdegc degc1
                    ON degc1.stvdegc_code = lcur.degc_code_1
                  LEFT JOIN stvdegc degc2
                    ON degc2.stvdegc_code = lcur.degc_code_2
                  LEFT JOIN stvdlev dlev1
                    ON dlev1.stvdlev_code = degc1.stvdegc_dlev_code
                  LEFT JOIN stvdlev dlev2
                    ON dlev2.stvdlev_code = degc2.stvdegc_dlev_code
                  LEFT JOIN zdegree_audit.davaudit v1
                    ON v1.pidm = regs_pidm
                   AND v1.prog_code = lcur.prog_code_1
                   AND v1.audit_term = regs_term_code
                   AND v1.current_ind = 'Y'
                   AND v1.whatif_prog_ind = 'N'
                  LEFT JOIN zdegree_audit.davaudit v2
                    ON v2.pidm = regs_pidm
                   AND v2.prog_code = lcur.prog_code_1
                   AND v2.audit_term = regs_term_code
                   AND v2.current_ind = 'Y'
                   AND v2.whatif_prog_ind = 'N') tgt
          FULL JOIN (SELECT *
                      FROM utl_d_aim.szrenrl e
                     WHERE e.acad_year = v_aidy_code
                       AND e.group_code = v_group_code
                       AND MOD(pidm, v_mod) = v_partition) src
            ON src.pidm = tgt.pidm
           AND src.term_code = tgt.term_code
           AND MOD(src.pidm, v_mod) = v_partition)
 WHERE (pidm IS NULL AND src_pidm IS NOT NULL)
    OR (pidm IS NOT NULL AND src_pidm IS NULL)
    OR ((group_code <> src_group_code OR (group_code IS NULL AND src_group_code IS NOT NULL) OR (group_code IS NOT NULL AND src_group_code IS NULL)) OR
       (semester <> src_semester OR (semester IS NULL AND src_semester IS NOT NULL) OR (semester IS NOT NULL AND src_semester IS NULL)) OR
       (acad_year <> src_acad_year OR (acad_year IS NULL AND src_acad_year IS NOT NULL) OR (acad_year IS NOT NULL AND src_acad_year IS NULL)) OR
       (status <> src_status OR (status IS NULL AND src_status IS NOT NULL) OR (status IS NOT NULL AND src_status IS NULL)) OR
       (classification <> src_classification OR (classification IS NULL AND src_classification IS NOT NULL) OR (classification IS NOT NULL AND src_classification IS NULL)) OR
       (term_seats <> src_term_seats OR (term_seats IS NULL AND src_term_seats IS NOT NULL) OR (term_seats IS NOT NULL AND src_term_seats IS NULL)) OR
       (term_hours <> src_term_hours OR (term_hours IS NULL AND src_term_hours IS NOT NULL) OR (term_hours IS NOT NULL AND src_term_hours IS NULL)) OR
       (res_hours <> src_res_hours OR (res_hours IS NULL AND src_res_hours IS NOT NULL) OR (res_hours IS NOT NULL AND src_res_hours IS NULL)) OR
       (luo_hours <> src_luo_hours OR (luo_hours IS NULL AND src_luo_hours IS NOT NULL) OR (luo_hours IS NOT NULL AND src_luo_hours IS NULL)) OR
       (au_hours <> src_au_hours OR (au_hours IS NULL AND src_au_hours IS NOT NULL) OR (au_hours IS NOT NULL AND src_au_hours IS NULL)) OR
       (a_hours <> src_a_hours OR (a_hours IS NULL AND src_a_hours IS NOT NULL) OR (a_hours IS NOT NULL AND src_a_hours IS NULL)) OR
       (b_hours <> src_b_hours OR (b_hours IS NULL AND src_b_hours IS NOT NULL) OR (b_hours IS NOT NULL AND src_b_hours IS NULL)) OR
       (c_hours <> src_c_hours OR (c_hours IS NULL AND src_c_hours IS NOT NULL) OR (c_hours IS NOT NULL AND src_c_hours IS NULL)) OR
       (d_hours <> src_d_hours OR (d_hours IS NULL AND src_d_hours IS NOT NULL) OR (d_hours IS NOT NULL AND src_d_hours IS NULL)) OR
       (j_hours <> src_j_hours OR (j_hours IS NULL AND src_j_hours IS NOT NULL) OR (j_hours IS NOT NULL AND src_j_hours IS NULL)) OR
       (r_hours <> src_r_hours OR (r_hours IS NULL AND src_r_hours IS NOT NULL) OR (r_hours IS NOT NULL AND src_r_hours IS NULL)) OR
       (wd_hours <> src_wd_hours OR (wd_hours IS NULL AND src_wd_hours IS NOT NULL) OR (wd_hours IS NOT NULL AND src_wd_hours IS NULL)) OR
       (fci_date <> src_fci_date OR (fci_date IS NULL AND src_fci_date IS NOT NULL) OR (fci_date IS NOT NULL AND src_fci_date IS NULL)) OR
       (yr_rank <> src_yr_rank OR (yr_rank IS NULL AND src_yr_rank IS NOT NULL) OR (yr_rank IS NOT NULL AND src_yr_rank IS NULL)) OR
       (housing <> src_housing OR (housing IS NULL AND src_housing IS NOT NULL) OR (housing IS NOT NULL AND src_housing IS NULL)) OR
       (last_term_completed <> src_last_term_completed OR (last_term_completed IS NULL AND src_last_term_completed IS NOT NULL) OR (last_term_completed IS NOT NULL AND src_last_term_completed IS NULL)) OR
       (last_enrl_term <> src_last_enrl_term OR (last_enrl_term IS NULL AND src_last_enrl_term IS NOT NULL) OR (last_enrl_term IS NOT NULL AND src_last_enrl_term IS NULL)) OR
       (last_enrl_term_year <> src_last_enrl_term_year OR (last_enrl_term_year IS NULL AND src_last_enrl_term_year IS NOT NULL) OR (last_enrl_term_year IS NOT NULL AND src_last_enrl_term_year IS NULL)) OR
       (last_enrl_term_levl <> src_last_enrl_term_levl OR (last_enrl_term_levl IS NULL AND src_last_enrl_term_levl IS NOT NULL) OR (last_enrl_term_levl IS NOT NULL AND src_last_enrl_term_levl IS NULL)) OR
       (last_enrl_term_levl_year <> src_last_enrl_term_levl_year OR (last_enrl_term_levl_year IS NULL AND src_last_enrl_term_levl_year IS NOT NULL) OR (last_enrl_term_levl_year IS NOT NULL AND src_last_enrl_term_levl_year IS NULL)) OR
       (first_enrl_term <> src_first_enrl_term OR (first_enrl_term IS NULL AND src_first_enrl_term IS NOT NULL) OR (first_enrl_term IS NOT NULL AND src_first_enrl_term IS NULL)) OR
       (first_enrl_term_year <> src_first_enrl_term_year OR (first_enrl_term_year IS NULL AND src_first_enrl_term_year IS NOT NULL) OR (first_enrl_term_year IS NOT NULL AND src_first_enrl_term_year IS NULL)) OR
       (first_enrl_term_levl <> src_first_enrl_term_levl OR (first_enrl_term_levl IS NULL AND src_first_enrl_term_levl IS NOT NULL) OR (first_enrl_term_levl IS NOT NULL AND src_first_enrl_term_levl IS NULL)) OR
       (first_enrl_term_levl_year <> src_first_enrl_term_levl_year OR (first_enrl_term_levl_year IS NULL AND src_first_enrl_term_levl_year IS NOT NULL) OR (first_enrl_term_levl_year IS NOT NULL AND src_first_enrl_term_levl_year IS NULL)) OR
       (camp_code <> src_camp_code OR (camp_code IS NULL AND src_camp_code IS NOT NULL) OR (camp_code IS NOT NULL AND src_camp_code IS NULL)) OR
       (levl_code <> src_levl_code OR (levl_code IS NULL AND src_levl_code IS NOT NULL) OR (levl_code IS NOT NULL AND src_levl_code IS NULL)) OR
       (prog_code_1 <> src_prog_code_1 OR (prog_code_1 IS NULL AND src_prog_code_1 IS NOT NULL) OR (prog_code_1 IS NOT NULL AND src_prog_code_1 IS NULL)) OR
       (prog_code_2 <> src_prog_code_2 OR (prog_code_2 IS NULL AND src_prog_code_2 IS NOT NULL) OR (prog_code_2 IS NOT NULL AND src_prog_code_2 IS NULL)) OR
       (prog_code_3 <> src_prog_code_3 OR (prog_code_3 IS NULL AND src_prog_code_3 IS NOT NULL) OR (prog_code_3 IS NOT NULL AND src_prog_code_3 IS NULL)) OR
       (prog_code_4 <> src_prog_code_4 OR (prog_code_4 IS NULL AND src_prog_code_4 IS NOT NULL) OR (prog_code_4 IS NOT NULL AND src_prog_code_4 IS NULL)) OR
       (majr_code_1 <> src_majr_code_1 OR (majr_code_1 IS NULL AND src_majr_code_1 IS NOT NULL) OR (majr_code_1 IS NOT NULL AND src_majr_code_1 IS NULL)) OR
       (majr_code_2 <> src_majr_code_2 OR (majr_code_2 IS NULL AND src_majr_code_2 IS NOT NULL) OR (majr_code_2 IS NOT NULL AND src_majr_code_2 IS NULL)) OR
       (majr_desc_1 <> src_majr_desc_1 OR (majr_desc_1 IS NULL AND src_majr_desc_1 IS NOT NULL) OR (majr_desc_1 IS NOT NULL AND src_majr_desc_1 IS NULL)) OR
       (majr_desc_2 <> src_majr_desc_2 OR (majr_desc_2 IS NULL AND src_majr_desc_2 IS NOT NULL) OR (majr_desc_2 IS NOT NULL AND src_majr_desc_2 IS NULL)) OR
       (degc_code_1 <> src_degc_code_1 OR (degc_code_1 IS NULL AND src_degc_code_1 IS NOT NULL) OR (degc_code_1 IS NOT NULL AND src_degc_code_1 IS NULL)) OR
       (degc_code_2 <> src_degc_code_2 OR (degc_code_2 IS NULL AND src_degc_code_2 IS NOT NULL) OR (degc_code_2 IS NOT NULL AND src_degc_code_2 IS NULL)) OR
       (degc_levl_1 <> src_degc_levl_1 OR (degc_levl_1 IS NULL AND src_degc_levl_1 IS NOT NULL) OR (degc_levl_1 IS NOT NULL AND src_degc_levl_1 IS NULL)) OR
       (degc_levl_2 <> src_degc_levl_2 OR (degc_levl_2 IS NULL AND src_degc_levl_2 IS NOT NULL) OR (degc_levl_2 IS NOT NULL AND src_degc_levl_2 IS NULL)) OR
       (ctlg_term_1 <> src_ctlg_term_1 OR (ctlg_term_1 IS NULL AND src_ctlg_term_1 IS NOT NULL) OR (ctlg_term_1 IS NOT NULL AND src_ctlg_term_1 IS NULL)) OR
       (ctlg_term_2 <> src_ctlg_term_2 OR (ctlg_term_2 IS NULL AND src_ctlg_term_2 IS NOT NULL) OR (ctlg_term_2 IS NOT NULL AND src_ctlg_term_2 IS NULL)) OR
       (ctlg_term_3 <> src_ctlg_term_3 OR (ctlg_term_3 IS NULL AND src_ctlg_term_3 IS NOT NULL) OR (ctlg_term_3 IS NOT NULL AND src_ctlg_term_3 IS NULL)) OR
       (ctlg_term_4 <> src_ctlg_term_4 OR (ctlg_term_4 IS NULL AND src_ctlg_term_4 IS NOT NULL) OR (ctlg_term_4 IS NOT NULL AND src_ctlg_term_4 IS NULL)) OR
       (coll_desc_1 <> src_coll_desc_1 OR (coll_desc_1 IS NULL AND src_coll_desc_1 IS NOT NULL) OR (coll_desc_1 IS NOT NULL AND src_coll_desc_1 IS NULL)) OR
       (coll_desc_2 <> src_coll_desc_2 OR (coll_desc_2 IS NULL AND src_coll_desc_2 IS NOT NULL) OR (coll_desc_2 IS NOT NULL AND src_coll_desc_2 IS NULL)) OR
       (dept_desc_1 <> src_dept_desc_1 OR (dept_desc_1 IS NULL AND src_dept_desc_1 IS NOT NULL) OR (dept_desc_1 IS NOT NULL AND src_dept_desc_1 IS NULL)) OR
       (dept_desc_2 <> src_dept_desc_2 OR (dept_desc_2 IS NULL AND src_dept_desc_2 IS NOT NULL) OR (dept_desc_2 IS NOT NULL AND src_dept_desc_2 IS NULL)) OR
       (minr_1 <> src_minr_1 OR (minr_1 IS NULL AND src_minr_1 IS NOT NULL) OR (minr_1 IS NOT NULL AND src_minr_1 IS NULL)) OR
       (minr_2 <> src_minr_2 OR (minr_2 IS NULL AND src_minr_2 IS NOT NULL) OR (minr_2 IS NOT NULL AND src_minr_2 IS NULL)) OR
       (minr_3 <> src_minr_3 OR (minr_3 IS NULL AND src_minr_3 IS NOT NULL) OR (minr_3 IS NOT NULL AND src_minr_3 IS NULL)) OR
       (minr_4 <> src_minr_4 OR (minr_4 IS NULL AND src_minr_4 IS NOT NULL) OR (minr_4 IS NOT NULL AND src_minr_4 IS NULL)) OR
       (ctlg_minr_1 <> src_ctlg_minr_1 OR (ctlg_minr_1 IS NULL AND src_ctlg_minr_1 IS NOT NULL) OR (ctlg_minr_1 IS NOT NULL AND src_ctlg_minr_1 IS NULL)) OR
       (ctlg_minr_2 <> src_ctlg_minr_2 OR (ctlg_minr_2 IS NULL AND src_ctlg_minr_2 IS NOT NULL) OR (ctlg_minr_2 IS NOT NULL AND src_ctlg_minr_2 IS NULL)) OR
       (ctlg_minr_3 <> src_ctlg_minr_3 OR (ctlg_minr_3 IS NULL AND src_ctlg_minr_3 IS NOT NULL) OR (ctlg_minr_3 IS NOT NULL AND src_ctlg_minr_3 IS NULL)) OR
       (ctlg_minr_4 <> src_ctlg_minr_4 OR (ctlg_minr_4 IS NULL AND src_ctlg_minr_4 IS NOT NULL) OR (ctlg_minr_4 IS NOT NULL AND src_ctlg_minr_4 IS NULL)) OR
       (luid <> src_luid OR (luid IS NULL AND src_luid IS NOT NULL) OR (luid IS NOT NULL AND src_luid IS NULL)) OR
       (last_name <> src_last_name OR (last_name IS NULL AND src_last_name IS NOT NULL) OR (last_name IS NOT NULL AND src_last_name IS NULL)) OR
       (first_name <> src_first_name OR (first_name IS NULL AND src_first_name IS NOT NULL) OR (first_name IS NOT NULL AND src_first_name IS NULL)) OR
       (age <> src_age OR (age IS NULL AND src_age IS NOT NULL) OR (age IS NOT NULL AND src_age IS NULL)) OR
       (ipeds_ethn <> src_ipeds_ethn OR (ipeds_ethn IS NULL AND src_ipeds_ethn IS NOT NULL) OR (ipeds_ethn IS NOT NULL AND src_ipeds_ethn IS NULL)) OR
       (ipeds_visa <> src_ipeds_visa OR (ipeds_visa IS NULL AND src_ipeds_visa IS NOT NULL) OR (ipeds_visa IS NOT NULL AND src_ipeds_visa IS NULL)) OR
       (state <> src_state OR (state IS NULL AND src_state IS NOT NULL) OR (state IS NOT NULL AND src_state IS NULL)) OR (zip5 <> src_zip5 OR (zip5 IS NULL AND src_zip5 IS NOT NULL) OR (zip5 IS NOT NULL AND src_zip5 IS NULL)) OR
       (phone <> src_phone OR (phone IS NULL AND src_phone IS NOT NULL) OR (phone IS NOT NULL AND src_phone IS NULL)) OR
       (phone_text <> src_phone_text OR (phone_text IS NULL AND src_phone_text IS NOT NULL) OR (phone_text IS NOT NULL AND src_phone_text IS NULL)) OR
       (nation <> src_nation OR (nation IS NULL AND src_nation IS NOT NULL) OR (nation IS NOT NULL AND src_nation IS NULL)) OR
       (gender <> src_gender OR (gender IS NULL AND src_gender IS NOT NULL) OR (gender IS NOT NULL AND src_gender IS NULL)) OR
       (lu_email <> src_lu_email OR (lu_email IS NULL AND src_lu_email IS NOT NULL) OR (lu_email IS NOT NULL AND src_lu_email IS NULL)) OR
       (alt_email <> src_alt_email OR (alt_email IS NULL AND src_alt_email IS NOT NULL) OR (alt_email IS NOT NULL AND src_alt_email IS NULL)) OR
       (parent_email_1 <> src_parent_email_1 OR (parent_email_1 IS NULL AND src_parent_email_1 IS NOT NULL) OR (parent_email_1 IS NOT NULL AND src_parent_email_1 IS NULL)) OR
       (parent_email_2 <> src_parent_email_2 OR (parent_email_2 IS NULL AND src_parent_email_2 IS NOT NULL) OR (parent_email_2 IS NOT NULL AND src_parent_email_2 IS NULL)) OR
       (milt_status <> src_milt_status OR (milt_status IS NULL AND src_milt_status IS NOT NULL) OR (milt_status IS NOT NULL AND src_milt_status IS NULL)) OR
       (milt_attr <> src_milt_attr OR (milt_attr IS NULL AND src_milt_attr IS NOT NULL) OR (milt_attr IS NOT NULL AND src_milt_attr IS NULL)) OR
       (admn_holds <> src_admn_holds OR (admn_holds IS NULL AND src_admn_holds IS NOT NULL) OR (admn_holds IS NOT NULL AND src_admn_holds IS NULL)) OR
       (cum_gpa <> src_cum_gpa OR (cum_gpa IS NULL AND src_cum_gpa IS NOT NULL) OR (cum_gpa IS NOT NULL AND src_cum_gpa IS NULL)) OR
       (cum_hours <> src_cum_hours OR (cum_hours IS NULL AND src_cum_hours IS NOT NULL) OR (cum_hours IS NOT NULL AND src_cum_hours IS NULL)) OR
       (inst_hours <> src_inst_hours OR (inst_hours IS NULL AND src_inst_hours IS NOT NULL) OR (inst_hours IS NOT NULL AND src_inst_hours IS NULL)) OR
       (tran_hours <> src_tran_hours OR (tran_hours IS NULL AND src_tran_hours IS NOT NULL) OR (tran_hours IS NOT NULL AND src_tran_hours IS NULL)) OR
       (gpa_asof_term <> src_gpa_asof_term OR (gpa_asof_term IS NULL AND src_gpa_asof_term IS NOT NULL) OR (gpa_asof_term IS NOT NULL AND src_gpa_asof_term IS NULL)) OR
       (cum_hours_asof_term <> src_cum_hours_asof_term OR (cum_hours_asof_term IS NULL AND src_cum_hours_asof_term IS NOT NULL) OR (cum_hours_asof_term IS NOT NULL AND src_cum_hours_asof_term IS NULL)) OR
       (term_gpa <> src_term_gpa OR (term_gpa IS NULL AND src_term_gpa IS NOT NULL) OR (term_gpa IS NOT NULL AND src_term_gpa IS NULL)) OR
       (styp_code <> src_styp_code OR (styp_code IS NULL AND src_styp_code IS NOT NULL) OR (styp_code IS NOT NULL AND src_styp_code IS NULL)) OR
       (astd_asof_term <> src_astd_asof_term OR (astd_asof_term IS NULL AND src_astd_asof_term IS NOT NULL) OR (astd_asof_term IS NOT NULL AND src_astd_asof_term IS NULL)) OR
       (term_astd <> src_term_astd OR (term_astd IS NULL AND src_term_astd IS NOT NULL) OR (term_astd IS NOT NULL AND src_term_astd IS NULL)) OR
       (hrs_required <> src_hrs_required OR (hrs_required IS NULL AND src_hrs_required IS NOT NULL) OR (hrs_required IS NOT NULL AND src_hrs_required IS NULL)) OR
       (hrs_applied <> src_hrs_applied OR (hrs_applied IS NULL AND src_hrs_applied IS NOT NULL) OR (hrs_applied IS NOT NULL AND src_hrs_applied IS NULL)) OR
       (hrs_remaining <> src_hrs_remaining OR (hrs_remaining IS NULL AND src_hrs_remaining IS NOT NULL) OR (hrs_remaining IS NOT NULL AND src_hrs_remaining IS NULL)) OR
       (hrs_applied_ip <> src_hrs_applied_ip OR (hrs_applied_ip IS NULL AND src_hrs_applied_ip IS NOT NULL) OR (hrs_applied_ip IS NOT NULL AND src_hrs_applied_ip IS NULL)) OR
       (hrs_pct_done <> src_hrs_pct_done OR (hrs_pct_done IS NULL AND src_hrs_pct_done IS NOT NULL) OR (hrs_pct_done IS NOT NULL AND src_hrs_pct_done IS NULL)) OR
       (req_pct_done <> src_req_pct_done OR (req_pct_done IS NULL AND src_req_pct_done IS NOT NULL) OR (req_pct_done IS NOT NULL AND src_req_pct_done IS NULL)) OR
       (astd_code_asof_term <> src_astd_code_asof_term OR (astd_code_asof_term IS NULL AND src_astd_code_asof_term IS NOT NULL) OR (astd_code_asof_term IS NOT NULL AND src_astd_code_asof_term IS NULL)) OR
       (term_astd_code <> src_term_astd_code OR (term_astd_code IS NULL AND src_term_astd_code IS NOT NULL) OR (term_astd_code IS NOT NULL AND src_term_astd_code IS NULL)) OR
       (lucom_cohort <> src_lucom_cohort OR (lucom_cohort IS NULL AND src_lucom_cohort IS NOT NULL) OR (lucom_cohort IS NOT NULL AND src_lucom_cohort IS NULL)) OR
       (lucom_classification <> src_lucom_classification OR (lucom_classification IS NULL AND src_lucom_classification IS NOT NULL) OR (lucom_classification IS NOT NULL AND src_lucom_classification IS NULL)) OR
       (prog_2_hrs_required <> src_prog_2_hrs_required OR (prog_2_hrs_required IS NULL AND src_prog_2_hrs_required IS NOT NULL) OR (prog_2_hrs_required IS NOT NULL AND src_prog_2_hrs_required IS NULL)) OR
       (prog_2_hrs_applied <> src_prog_2_hrs_applied OR (prog_2_hrs_applied IS NULL AND src_prog_2_hrs_applied IS NOT NULL) OR (prog_2_hrs_applied IS NOT NULL AND src_prog_2_hrs_applied IS NULL)) OR
       (prog_2_hrs_remaining <> src_prog_2_hrs_remaining OR (prog_2_hrs_remaining IS NULL AND src_prog_2_hrs_remaining IS NOT NULL) OR (prog_2_hrs_remaining IS NOT NULL AND src_prog_2_hrs_remaining IS NULL)) OR
       (prog_2_applied_ip <> src_prog_2_applied_ip OR (prog_2_applied_ip IS NULL AND src_prog_2_applied_ip IS NOT NULL) OR (prog_2_applied_ip IS NOT NULL AND src_prog_2_applied_ip IS NULL)) OR
       (prog_2_hrs_pct_done <> src_prog_2_hrs_pct_done OR (prog_2_hrs_pct_done IS NULL AND src_prog_2_hrs_pct_done IS NOT NULL) OR (prog_2_hrs_pct_done IS NOT NULL AND src_prog_2_hrs_pct_done IS NULL)) OR
       (prog_2_req_pct_done <> src_prog_2_req_pct_done OR (prog_2_req_pct_done IS NULL AND src_prog_2_req_pct_done IS NOT NULL) OR (prog_2_req_pct_done IS NOT NULL AND src_prog_2_req_pct_done IS NULL)) OR
       (last_term_completed <> src_last_term_completed OR (last_term_completed IS NULL AND src_last_term_completed IS NOT NULL) OR (last_term_completed IS NOT NULL AND src_last_term_completed IS NULL)) OR
       (last_completed_term <> src_last_completed_term OR (last_completed_term IS NULL AND src_last_completed_term IS NOT NULL) OR (last_completed_term IS NOT NULL AND src_last_completed_term IS NULL)) OR
       (last_completed_term_year <> src_last_completed_term_year OR (last_completed_term_year IS NULL AND src_last_completed_term_year IS NOT NULL) OR (last_completed_term_year IS NOT NULL AND src_last_completed_term_year IS NULL)) OR
       (last_completed_term_levl <> src_last_completed_term_levl OR (last_completed_term_levl IS NULL AND src_last_completed_term_levl IS NOT NULL) OR (last_completed_term_levl IS NOT NULL AND src_last_completed_term_levl IS NULL)) OR
       (last_completed_term_levl_year <> src_last_completed_term_levl_year OR (last_completed_term_levl_year IS NULL AND src_last_completed_term_levl_year IS NOT NULL) OR
       (last_completed_term_levl_year IS NOT NULL AND src_last_completed_term_levl_year IS NULL)));
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
start_time   TIMESTAMP;
end_time     TIMESTAMP;
select_count NUMBER := 0;
insert_count NUMBER := 0;
update_count NUMBER := 0;
delete_count NUMBER := 0;
start_t      DATE := SYSDATE;
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
OPEN c1(rec.aidy_code, rec.group_code, rec.timeframe);
LOOP
v_count   := 0; -- reset count
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || rec.aidy_code || ' - ' || rec.group_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
FETCH c1 BULK COLLECT
INTO rec_input LIMIT v_row_max;
v_count := rec_input.count;
IF v_count = 0 THEN
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'SELECT - ' || rec.aidy_code || ' - ' || rec.group_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
ELSIF v_count > 0 THEN
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'SELECT - ' || rec.aidy_code || ' - ' || rec.group_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
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
v_msg     := SQLERRM || ' exception raised for ' || rec.aidy_code || ' - ' || rec.group_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || round(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
CONTINUE;
END;
END LOOP;
insert_count := insert_dml.count;
update_count := update_dml.count;
delete_count := delete_dml.count;
FORALL i IN VALUES OF insert_dml -- DML INSERTS
INSERT INTO utl_d_aim.szrenrl tab
(pidm,
 term_code,
 group_code,
 semester,
 acad_year,
 status,
 classification,
 term_seats,
 term_hours,
 res_hours,
 luo_hours,
 au_hours,
 a_hours,
 b_hours,
 c_hours,
 d_hours,
 j_hours,
 r_hours,
 wd_hours,
 fci_date,
 yr_rank,
 housing,
 last_term_completed,
 last_enrl_term,
 last_enrl_term_year,
 last_enrl_term_levl,
 last_enrl_term_levl_year,
 first_enrl_term,
 first_enrl_term_year,
 first_enrl_term_levl,
 first_enrl_term_levl_year,
 camp_code,
 levl_code,
 prog_code_1,
 prog_code_2,
 prog_code_3,
 prog_code_4,
 majr_code_1,
 majr_code_2,
 majr_desc_1,
 majr_desc_2,
 degc_code_1,
 degc_code_2,
 degc_levl_1,
 degc_levl_2,
 ctlg_term_1,
 ctlg_term_2,
 ctlg_term_3,
 ctlg_term_4,
 coll_desc_1,
 coll_desc_2,
 dept_desc_1,
 dept_desc_2,
 minr_1,
 minr_2,
 minr_3,
 minr_4,
 ctlg_minr_1,
 ctlg_minr_2,
 ctlg_minr_3,
 ctlg_minr_4,
 luid,
 last_name,
 first_name,
 age,
 ipeds_ethn,
 ipeds_visa,
 state,
 zip5,
 phone,
 phone_text,
 nation,
 gender,
 lu_email,
 alt_email,
 parent_email_1,
 parent_email_2,
 milt_status,
 milt_attr,
 admn_holds,
 cum_gpa,
 cum_hours,
 inst_hours,
 tran_hours,
 gpa_asof_term,
 cum_hours_asof_term,
 term_gpa,
 styp_code,
 activity_date,
 astd_asof_term,
 term_astd,
 hrs_required,
 hrs_applied,
 hrs_remaining,
 hrs_applied_ip,
 hrs_pct_done,
 req_pct_done,
 astd_code_asof_term,
 term_astd_code,
 lucom_cohort,
 lucom_classification,
 prog_2_hrs_required,
 prog_2_hrs_applied,
 prog_2_hrs_remaining,
 prog_2_applied_ip,
 prog_2_hrs_pct_done,
 prog_2_req_pct_done,
 last_completed_term,
 last_completed_term_year,
 last_completed_term_levl,
 last_completed_term_levl_year)
VALUES
(rec_input(i).pidm,
 rec_input(i).term_code,
 rec_input(i).group_code,
 rec_input(i).semester,
 rec_input(i).acad_year,
 rec_input(i).status,
 rec_input(i).classification,
 rec_input(i).term_seats,
 rec_input(i).term_hours,
 rec_input(i).res_hours,
 rec_input(i).luo_hours,
 rec_input(i).au_hours,
 rec_input(i).a_hours,
 rec_input(i).b_hours,
 rec_input(i).c_hours,
 rec_input(i).d_hours,
 rec_input(i).j_hours,
 rec_input(i).r_hours,
 rec_input(i).wd_hours,
 rec_input(i).fci_date,
 rec_input(i).yr_rank,
 rec_input(i).housing,
 rec_input(i).last_term_completed,
 rec_input(i).last_enrl_term,
 rec_input(i).last_enrl_term_year,
 rec_input(i).last_enrl_term_levl,
 rec_input(i).last_enrl_term_levl_year,
 rec_input(i).first_enrl_term,
 rec_input(i).first_enrl_term_year,
 rec_input(i).first_enrl_term_levl,
 rec_input(i).first_enrl_term_levl_year,
 rec_input(i).camp_code,
 rec_input(i).levl_code,
 rec_input(i).prog_code_1,
 rec_input(i).prog_code_2,
 rec_input(i).prog_code_3,
 rec_input(i).prog_code_4,
 rec_input(i).majr_code_1,
 rec_input(i).majr_code_2,
 rec_input(i).majr_desc_1,
 rec_input(i).majr_desc_2,
 rec_input(i).degc_code_1,
 rec_input(i).degc_code_2,
 rec_input(i).degc_levl_1,
 rec_input(i).degc_levl_2,
 rec_input(i).ctlg_term_1,
 rec_input(i).ctlg_term_2,
 rec_input(i).ctlg_term_3,
 rec_input(i).ctlg_term_4,
 rec_input(i).coll_desc_1,
 rec_input(i).coll_desc_2,
 rec_input(i).dept_desc_1,
 rec_input(i).dept_desc_2,
 rec_input(i).minr_1,
 rec_input(i).minr_2,
 rec_input(i).minr_3,
 rec_input(i).minr_4,
 rec_input(i).ctlg_minr_1,
 rec_input(i).ctlg_minr_2,
 rec_input(i).ctlg_minr_3,
 rec_input(i).ctlg_minr_4,
 rec_input(i).luid,
 rec_input(i).last_name,
 rec_input(i).first_name,
 rec_input(i).age,
 rec_input(i).ipeds_ethn,
 rec_input(i).ipeds_visa,
 rec_input(i).state,
 rec_input(i).zip5,
 rec_input(i).phone,
 rec_input(i).phone_text,
 rec_input(i).nation,
 rec_input(i).gender,
 rec_input(i).lu_email,
 rec_input(i).alt_email,
 rec_input(i).parent_email_1,
 rec_input(i).parent_email_2,
 rec_input(i).milt_status,
 rec_input(i).milt_attr,
 rec_input(i).admn_holds,
 rec_input(i).cum_gpa,
 rec_input(i).cum_hours,
 rec_input(i).inst_hours,
 rec_input(i).tran_hours,
 rec_input(i).gpa_asof_term,
 rec_input(i).cum_hours_asof_term,
 rec_input(i).term_gpa,
 rec_input(i).styp_code,
 rec_input(i).activity_date,
 rec_input(i).astd_asof_term,
 rec_input(i).term_astd,
 rec_input(i).hrs_required,
 rec_input(i).hrs_applied,
 rec_input(i).hrs_remaining,
 rec_input(i).hrs_applied_ip,
 rec_input(i).hrs_pct_done,
 rec_input(i).req_pct_done,
 rec_input(i).astd_code_asof_term,
 rec_input(i).term_astd_code,
 rec_input(i).lucom_cohort,
 rec_input(i).lucom_classification,
 rec_input(i).prog_2_hrs_required,
 rec_input(i).prog_2_hrs_applied,
 rec_input(i).prog_2_hrs_remaining,
 rec_input(i).prog_2_applied_ip,
 rec_input(i).prog_2_hrs_pct_done,
 rec_input(i).prog_2_req_pct_done,
 rec_input(i).last_completed_term,
 rec_input(i).last_completed_term_year,
 rec_input(i).last_completed_term_levl,
 rec_input(i).last_completed_term_levl_year);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'INSERT - ' || rec.aidy_code || ' - ' || rec.group_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
FORALL i IN VALUES OF update_dml -- DML UPDATES
UPDATE utl_d_aim.szrenrl tab
   SET (pidm, term_code, group_code, semester, acad_year, status, classification, term_seats, term_hours, res_hours, luo_hours, au_hours, a_hours, b_hours, c_hours, d_hours, j_hours, r_hours, wd_hours, fci_date, yr_rank, housing, last_term_completed, last_enrl_term, last_enrl_term_year, last_enrl_term_levl, last_enrl_term_levl_year, first_enrl_term, first_enrl_term_year, first_enrl_term_levl, first_enrl_term_levl_year, camp_code, levl_code, prog_code_1, prog_code_2, prog_code_3, prog_code_4, majr_code_1, majr_code_2, majr_desc_1, majr_desc_2, degc_code_1, degc_code_2, degc_levl_1, degc_levl_2, ctlg_term_1, ctlg_term_2, ctlg_term_3, ctlg_term_4, coll_desc_1, coll_desc_2, dept_desc_1, dept_desc_2, minr_1, minr_2, minr_3, minr_4, ctlg_minr_1, ctlg_minr_2, ctlg_minr_3, ctlg_minr_4, luid, last_name, first_name, age, ipeds_ethn, ipeds_visa, state, zip5, phone, phone_text, nation, gender, lu_email, alt_email, parent_email_1, parent_email_2, milt_status, milt_attr, admn_holds, cum_gpa, cum_hours, inst_hours, tran_hours, gpa_asof_term, cum_hours_asof_term, term_gpa, styp_code, activity_date, astd_asof_term, term_astd, hrs_required, hrs_applied, hrs_remaining, hrs_applied_ip, hrs_pct_done, req_pct_done, astd_code_asof_term, term_astd_code, lucom_cohort, lucom_classification, prog_2_hrs_required, prog_2_hrs_applied, prog_2_hrs_remaining, prog_2_applied_ip, prog_2_hrs_pct_done, prog_2_req_pct_done, last_completed_term, last_completed_term_year, last_completed_term_levl, last_completed_term_levl_year) =
       (SELECT rec_input(i).pidm,
               rec_input(i).term_code,
               rec_input(i).group_code,
               rec_input(i).semester,
               rec_input(i).acad_year,
               rec_input(i).status,
               rec_input(i).classification,
               rec_input(i).term_seats,
               rec_input(i).term_hours,
               rec_input(i).res_hours,
               rec_input(i).luo_hours,
               rec_input(i).au_hours,
               rec_input(i).a_hours,
               rec_input(i).b_hours,
               rec_input(i).c_hours,
               rec_input(i).d_hours,
               rec_input(i).j_hours,
               rec_input(i).r_hours,
               rec_input(i).wd_hours,
               rec_input(i).fci_date,
               rec_input(i).yr_rank,
               rec_input(i).housing,
               rec_input(i).last_term_completed,
               rec_input(i).last_enrl_term,
               rec_input(i).last_enrl_term_year,
               rec_input(i).last_enrl_term_levl,
               rec_input(i).last_enrl_term_levl_year,
               rec_input(i).first_enrl_term,
               rec_input(i).first_enrl_term_year,
               rec_input(i).first_enrl_term_levl,
               rec_input(i).first_enrl_term_levl_year,
               rec_input(i).camp_code,
               rec_input(i).levl_code,
               rec_input(i).prog_code_1,
               rec_input(i).prog_code_2,
               rec_input(i).prog_code_3,
               rec_input(i).prog_code_4,
               rec_input(i).majr_code_1,
               rec_input(i).majr_code_2,
               rec_input(i).majr_desc_1,
               rec_input(i).majr_desc_2,
               rec_input(i).degc_code_1,
               rec_input(i).degc_code_2,
               rec_input(i).degc_levl_1,
               rec_input(i).degc_levl_2,
               rec_input(i).ctlg_term_1,
               rec_input(i).ctlg_term_2,
               rec_input(i).ctlg_term_3,
               rec_input(i).ctlg_term_4,
               rec_input(i).coll_desc_1,
               rec_input(i).coll_desc_2,
               rec_input(i).dept_desc_1,
               rec_input(i).dept_desc_2,
               rec_input(i).minr_1,
               rec_input(i).minr_2,
               rec_input(i).minr_3,
               rec_input(i).minr_4,
               rec_input(i).ctlg_minr_1,
               rec_input(i).ctlg_minr_2,
               rec_input(i).ctlg_minr_3,
               rec_input(i).ctlg_minr_4,
               rec_input(i).luid,
               rec_input(i).last_name,
               rec_input(i).first_name,
               rec_input(i).age,
               rec_input(i).ipeds_ethn,
               rec_input(i).ipeds_visa,
               rec_input(i).state,
               rec_input(i).zip5,
               rec_input(i).phone,
               rec_input(i).phone_text,
               rec_input(i).nation,
               rec_input(i).gender,
               rec_input(i).lu_email,
               rec_input(i).alt_email,
               rec_input(i).parent_email_1,
               rec_input(i).parent_email_2,
               rec_input(i).milt_status,
               rec_input(i).milt_attr,
               rec_input(i).admn_holds,
               rec_input(i).cum_gpa,
               rec_input(i).cum_hours,
               rec_input(i).inst_hours,
               rec_input(i).tran_hours,
               rec_input(i).gpa_asof_term,
               rec_input(i).cum_hours_asof_term,
               rec_input(i).term_gpa,
               rec_input(i).styp_code,
               rec_input(i).activity_date,
               rec_input(i).astd_asof_term,
               rec_input(i).term_astd,
               rec_input(i).hrs_required,
               rec_input(i).hrs_applied,
               rec_input(i).hrs_remaining,
               rec_input(i).hrs_applied_ip,
               rec_input(i).hrs_pct_done,
               rec_input(i).req_pct_done,
               rec_input(i).astd_code_asof_term,
               rec_input(i).term_astd_code,
               rec_input(i).lucom_cohort,
               rec_input(i).lucom_classification,
               rec_input(i).prog_2_hrs_required,
               rec_input(i).prog_2_hrs_applied,
               rec_input(i).prog_2_hrs_remaining,
               rec_input(i).prog_2_applied_ip,
               rec_input(i).prog_2_hrs_pct_done,
               rec_input(i).prog_2_req_pct_done,
               rec_input(i).last_completed_term,
               rec_input(i).last_completed_term_year,
               rec_input(i).last_completed_term_levl,
               rec_input(i).last_completed_term_levl_year
          FROM dual)
 WHERE tab.term_code = rec_input(i).term_code
   AND tab.pidm = rec_input(i).pidm;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'UPDATE - ' || rec.aidy_code || ' - ' || rec.group_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
FORALL i IN VALUES OF delete_dml -- DML DELETES
DELETE FROM utl_d_aim.szrenrl tab
 WHERE tab.term_code = rec_input(i).term_code
   AND tab.pidm = rec_input(i).pidm;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'DELETE - ' || rec.aidy_code || ' - ' || rec.group_code || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
END IF;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_total_count := v_total_count + rec_input.count;
EXIT WHEN(rec_input.count < v_row_max);
END LOOP;
CLOSE c1;
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
v_msg     := substr(SQLERRM, 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
/*--------------------------------------------CHANGE LOG----------------------------------------
VERSION DATE    USERNAME       UPDATES
---     05-11-2018  wruminn      Initial release
---     09-28-2018  wruminn      Added addtional columns for major codes, degree code, last term columns
---     10-31-2018  wruminn      Added additional columns for department, first enrl, styp_code, renamed enrl_holds to admn_holds
---     12-18-2018  wruminn      Added two columns: astd_asof_term and term_astd
---     07-25-2019  kcaldwell    Added columns for contact info
---     05-17-2021  lxhatfield   Updated housing logic based on code from ADS Student Life
---     07-07-2022  cwalsh1      Updated cursor to be more spaced out instead of running all terms on Mondays. Was causing runtime errors in JAMS.
---     07-29-2022  cwalsh1      Converted ETL to transactional format to reduce runtime
---     09-21-2022  cwalsh1      Added mod group to procedure and cursor to allow parallell processing calls in JAMS
---     10/3/2022   cwalsh1      Coverted mod group to pidm to eliminate overlap on update statements. Cursor for terms is not limited.
---     05-17-2023  wgriffith2  --Dealing with EM courses and updating code to use job_log
---     02-08-2024  wgriffith2  --always run active terms hourly including any future terms within 180 days. then, only run terms that we found a grade change happen once daily after midnight
---     08-06-2024  wgriffith2/JWTUCKER1  --adding new last_completed_term columns
---     08-19-2025  wgriffith2  --Updated szrenrl select to calculate GPA and hours as of each term?s end_date
---     10-23-2025  wgriffith2  --Changed [szrenrl] cursor to run current aidy hourly, full history after midnight on Saturdays
---     10-24-2025  wgriffith2  --utl_d_aim.szrregs deprecation; removing all szrcurr joins from etl procedures live code
---     01-14-2026  wgriffith2  --repointed ctlg terms to the correct fields in the lcur table
------------------------------------------------------------------------------------------------*/
END etl_aim_szrenrl_refresh;

PROCEDURE etl_aim_waitlist_refresh (jobnumber number, processid varchar2, processname varchar2) IS
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
v_proc        VARCHAR2(100) := 'etl_aim_waitlist_refresh';
v_run_date    DATE := trunc(SYSDATE);
CURSOR c_terms IS
SELECT sfrrsts_term_code AS term_code
  FROM sfrrsts
 WHERE sfrrsts_ptrm_code = 'R'
   AND sfrrsts_rsts_code = 'LW'
   AND SYSDATE BETWEEN sfrrsts_start_date AND sfrrsts_end_date;
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
MERGE INTO utl_d_aim.waitlist destination_table
USING (SELECT v_run_date wl_dte,
              ssbsect_term_code term,
              ssbsect_crn crn,
              sgrclsr_clas_code clas,
              nvl(SUM(t.tot_enrl), 0) total_enrl,
              nvl(SUM(t.tot_wl + t.notified), 0) total_wl,
              nvl(SUM(t.run_tot_wl), 0) run_tot_wl,
              nvl(SUM(t.tot_wl), 0) current_wl,
              nvl(SUM(t.pending), 0) pending,
              nvl(SUM(t.notified), 0) notified,
              nvl(SUM(t.registered), 0) registered,
              nvl(SUM(t.dropped), 0) dropped
         FROM ssbsect
         JOIN sgrclsr
           ON sgrclsr_levl_code = 'UG'
          AND sgrclsr_clas_code IN ('FR', 'SO', 'JR', 'SR')
         LEFT JOIN (SELECT v_run_date dates,
                          ssbsect_term_code term,
                          ssbsect_crn crn,
                          sgrclsr_clas_code clas,
                          COUNT(DISTINCT CASE
                                WHEN s1.sfrstca_rsts_code <> 'LW' THEN
                                 CASE
                                 WHEN nvl((SELECT SUM(shrtgpa_hours_earned)
                                            FROM shrtgpa
                                           WHERE shrtgpa_pidm = s1.sfrstca_pidm
                                             AND shrtgpa_gpa_type_ind IN ('I', 'T')
                                             AND shrtgpa_term_code <= rec.term_code
                                             AND shrtgpa_levl_code = 'UG'
                                           GROUP BY shrtgpa_pidm), 0) BETWEEN sgrclsr_from_hours AND sgrclsr_to_hours THEN
                                  s1.sfrstca_pidm
                                 END
                                END) tot_enrl,
                          COUNT(DISTINCT CASE
                                WHEN s1.sfrstca_rsts_code = 'LW' THEN
                                 CASE
                                 WHEN nvl((SELECT SUM(shrtgpa_hours_earned)
                                            FROM shrtgpa
                                           WHERE shrtgpa_pidm = s1.sfrstca_pidm
                                             AND shrtgpa_gpa_type_ind IN ('I', 'T')
                                             AND shrtgpa_term_code <= rec.term_code
                                             AND shrtgpa_levl_code = 'UG'
                                           GROUP BY shrtgpa_pidm), 0) BETWEEN sgrclsr_from_hours AND sgrclsr_to_hours THEN
                                  s1.sfrstca_pidm
                                 END
                                END) tot_wl,
                          0 run_tot_wl,
                          0 pending,
                          0 notified,
                          0 registered,
                          0 dropped
                     FROM ssbsect
                     JOIN sgrclsr
                       ON sgrclsr_levl_code = 'UG'
                      AND sgrclsr_clas_code IN ('FR', 'SO', 'JR', 'SR')
                      AND ssbsect_wait_capacity > 0
                     JOIN sfrstca s1
                       ON s1.sfrstca_term_code = ssbsect_term_code
                      AND s1.sfrstca_crn = ssbsect_crn
                      AND s1.sfrstca_source_cde = 'BASE'
                      AND s1.sfrstca_rsts_code IN (SELECT stvrsts_code
                                                     FROM stvrsts
                                                    WHERE stvrsts_incl_sect_enrl = 'Y'
                                                       OR stvrsts_code = 'LW')
                      AND nvl(s1.sfrstca_rmsg_cde, 'X') <> 'DELT'
                      AND s1.sfrstca_seq_number = (SELECT MAX(d.sfrstca_seq_number)
                                                     FROM sfrstca d
                                                    WHERE d.sfrstca_pidm = s1.sfrstca_pidm
                                                      AND d.sfrstca_term_code = s1.sfrstca_term_code
                                                      AND d.sfrstca_crn = s1.sfrstca_crn
                                                      AND d.sfrstca_source_cde = 'BASE'
                                                      AND trunc(d.sfrstca_rsts_date) <= v_run_date)
                    WHERE ssbsect_term_code = rec.term_code
                      AND ssbsect_camp_code = 'R'
                      AND ssbsect_enrl > 0
                      AND ssbsect_wait_capacity > 0
                      AND ssbsect_subj_code NOT IN ('CSER', 'FRSM', 'GRST', 'NEWS', 'NSSR')
                    GROUP BY ssbsect_term_code,
                             ssbsect_crn,
                             sgrclsr_clas_code,
                             v_run_date
                   UNION
                   SELECT v_run_date dates,
                          ssbsect_term_code term,
                          ssbsect_crn crn,
                          sgrclsr_clas_code clas,
                          0 tot_enrl,
                          0 tot_wl,
                          COUNT(DISTINCT CASE
                                WHEN nvl((SELECT SUM(shrtgpa_hours_earned)
                                           FROM shrtgpa
                                          WHERE shrtgpa_pidm = s2.sfrstca_pidm
                                            AND shrtgpa_gpa_type_ind IN ('I', 'T')
                                            AND shrtgpa_term_code <= rec.term_code
                                            AND shrtgpa_levl_code = 'UG'
                                          GROUP BY shrtgpa_pidm), 0) BETWEEN sgrclsr_from_hours AND sgrclsr_to_hours THEN
                                 s2.sfrstca_pidm
                                END) run_tot_wl,
                          0 pending,
                          0 notified,
                          0 registered,
                          0 dropped
                     FROM ssbsect
                     JOIN sgrclsr
                       ON sgrclsr_levl_code = 'UG'
                      AND sgrclsr_clas_code IN ('FR', 'SO', 'JR', 'SR')
                      AND ssbsect_wait_capacity > 0
                     LEFT JOIN sfrstca s2
                       ON s2.sfrstca_term_code = ssbsect_term_code
                      AND s2.sfrstca_crn = ssbsect_crn
                      AND s2.sfrstca_source_cde = 'BASE'
                      AND s2.sfrstca_rsts_code = 'LW'
                      AND trunc(s2.sfrstca_rsts_date) <= v_run_date
                    WHERE ssbsect_term_code = rec.term_code
                      AND ssbsect_camp_code = 'R'
                      AND ssbsect_enrl > 0
                      AND ssbsect_wait_capacity > 0
                      AND ssbsect_subj_code NOT IN ('CSER', 'FRSM', 'GRST', 'NEWS', 'NSSR')
                    GROUP BY ssbsect_term_code,
                             ssbsect_crn,
                             sgrclsr_clas_code,
                             v_run_date
                   UNION
                   SELECT v_run_date dates,
                          ssbsect_term_code term,
                          ssbsect_crn crn,
                          sgrclsr_clas_code clas,
                          0 tot_enrl,
                          0 tot_wl,
                          0 run_tot_wl,
                          COUNT(DISTINCT CASE
                                WHEN nvl((SELECT SUM(shrtgpa_hours_earned)
                                           FROM shrtgpa
                                          WHERE shrtgpa_pidm = sfrwlnt_pidm
                                            AND shrtgpa_gpa_type_ind IN ('I', 'T')
                                            AND shrtgpa_term_code <= rec.term_code
                                            AND shrtgpa_levl_code = 'UG'
                                          GROUP BY shrtgpa_pidm), 0) BETWEEN sgrclsr_from_hours AND sgrclsr_to_hours THEN
                                 CASE
                                 WHEN v_run_date BETWEEN trunc(sfrwlnt_start_date) AND trunc(sfrwlnt_end_date) THEN
                                  sfrwlnt_pidm
                                 END
                                END) pending,
                          COUNT(DISTINCT CASE
                                WHEN nvl((SELECT SUM(shrtgpa_hours_earned)
                                           FROM shrtgpa
                                          WHERE shrtgpa_pidm = sfrwlnt_pidm
                                            AND shrtgpa_gpa_type_ind IN ('I', 'T')
                                            AND shrtgpa_term_code <= rec.term_code
                                            AND shrtgpa_levl_code = 'UG'
                                          GROUP BY shrtgpa_pidm), 0) BETWEEN sgrclsr_from_hours AND sgrclsr_to_hours THEN
                                 sfrwlnt_pidm
                                END) notified,
                          COUNT(DISTINCT CASE
                                WHEN nvl((SELECT SUM(shrtgpa_hours_earned)
                                           FROM shrtgpa
                                          WHERE shrtgpa_pidm = sfrwlnt_pidm
                                            AND shrtgpa_gpa_type_ind IN ('I', 'T')
                                            AND shrtgpa_term_code <= rec.term_code
                                            AND shrtgpa_levl_code = 'UG'
                                          GROUP BY shrtgpa_pidm), 0) BETWEEN sgrclsr_from_hours AND sgrclsr_to_hours THEN
                                 CASE
                                 WHEN sfrwlnt_reg_conf_stat = 'R' THEN
                                  sfrwlnt_pidm
                                 END
                                END) registered,
                          COUNT(DISTINCT CASE
                                WHEN nvl((SELECT SUM(shrtgpa_hours_earned)
                                           FROM shrtgpa
                                          WHERE shrtgpa_pidm = sfrwlnt_pidm
                                            AND shrtgpa_gpa_type_ind IN ('I', 'T')
                                            AND shrtgpa_term_code <= rec.term_code
                                            AND shrtgpa_levl_code = 'UG'
                                          GROUP BY shrtgpa_pidm), 0) BETWEEN sgrclsr_from_hours AND sgrclsr_to_hours THEN
                                 CASE
                                 WHEN sfrwlnt_reg_conf_stat IN ('Z', 'X') THEN
                                  sfrwlnt_pidm
                                 END
                                END) dropped
                     FROM ssbsect
                     JOIN sgrclsr
                       ON sgrclsr_levl_code = 'UG'
                      AND sgrclsr_clas_code IN ('FR', 'SO', 'JR', 'SR')
                     LEFT JOIN sfrwlnt
                       ON sfrwlnt_crn = ssbsect_crn
                      AND sfrwlnt_term_code = ssbsect_term_code
                      AND trunc(sfrwlnt_start_date) <= v_run_date
                    WHERE ssbsect_term_code = rec.term_code
                      AND ssbsect_camp_code = 'R'
                      AND ssbsect_enrl > 0
                      AND ssbsect_wait_capacity > 0
                      AND ssbsect_subj_code NOT IN ('CSER', 'FRSM', 'GRST', 'NEWS', 'NSSR')
                    GROUP BY ssbsect_term_code,
                             ssbsect_crn,
                             sgrclsr_clas_code,
                             v_run_date) t
           ON t.crn = ssbsect_crn
          AND t.term = ssbsect_term_code
          AND t.clas = sgrclsr_clas_code
        WHERE ssbsect_term_code = rec.term_code
          AND ssbsect_camp_code = 'R'
          AND ssbsect_subj_code NOT IN ('CSER', 'FRSM', 'GRST', 'NEWS', 'NSSR')
          AND ssbsect_wait_capacity > 0
          AND ssbsect_ssts_code = 'A'
        GROUP BY v_run_date,
                 ssbsect_term_code,
                 sgrclsr_clas_code,
                 ssbsect_crn) new_records
ON (destination_table.wl_dte = new_records.wl_dte AND destination_table.term = new_records.term AND destination_table.crn = new_records.crn AND destination_table.clas = new_records.clas)
WHEN MATCHED THEN
UPDATE
   SET destination_table.total_enrl = new_records.total_enrl,
       destination_table.total_wl   = new_records.total_wl,
       destination_table.run_tot_wl = new_records.run_tot_wl,
       destination_table.current_wl = new_records.current_wl,
       destination_table.pending    = new_records.pending,
       destination_table.notified   = new_records.notified,
       destination_table.registered = new_records.registered,
       destination_table.dropped    = new_records.dropped
WHEN NOT MATCHED THEN
INSERT
(wl_dte,
 term,
 crn,
 clas,
 total_enrl,
 total_wl,
 run_tot_wl,
 current_wl,
 pending,
 notified,
 registered,
 dropped)
VALUES
(new_records.wl_dte,
 new_records.term,
 new_records.crn,
 new_records.clas,
 new_records.total_enrl,
 new_records.total_wl,
 new_records.run_tot_wl,
 new_records.current_wl,
 new_records.pending,
 new_records.notified,
 new_records.registered,
 new_records.dropped);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || rec.term_code  || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
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
1.0        08-30-2018  kcaldwell    --Initial release
---     05-24-2023  wgriffith2  --updating code to use job_log
------------------------------------------------------------------------------------------------*/
END etl_aim_waitlist_refresh;

PROCEDURE etl_aim_szrroom_refresh (jobnumber number, processid varchar2, processname varchar2) IS
--DECLARE
--- PARAMS
v_etl_date DATE := SYSDATE;
v_msg      VARCHAR2(2000);
v_instance VARCHAR2(50) := upper('ALL'); -- inst from the jams job; used for determining instance
v_partition NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
-- v_mod         NUMBER := 5; -- number of partitions to be created

v_count           NUMBER := 0;
v_elapsed         NUMBER := 0;
v_total_count     NUMBER := 0;
v_job_id          VARCHAR2(32);
v_proc            VARCHAR2(100) := 'etl_aim_szrroom_refresh';
v_timeslot_exists NUMBER;
CURSOR c_terms IS
SELECT term_code
  FROM (SELECT term_code,
               rank() over(ORDER BY term_code) rnk
          FROM zbtm.terms_by_group_v
         WHERE group_code = 'STD'
           AND semester IN ('FAL', 'SPR', 'SUM')
           AND end_date > trunc(SYSDATE)) trm
 WHERE trm.rnk <= 3;
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
SELECT COUNT(1) INTO v_timeslot_exists FROM utl_d_aim.ztimeslot WHERE term_code = rec.term_code;
IF v_timeslot_exists = 0 THEN
INSERT INTO utl_d_aim.ztimeslot
(term_code,
 week_day,
 start_time,
 end_time,
 time_slot)
SELECT rec.term_code AS term_code,
       z.week_day,
       z.start_time,
       z.end_time,
       z.time_slot
  FROM utl_d_aim.ztimeslot z
 WHERE term_code = rec.term_code;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
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
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
/*--------------------------------------------CHANGE LOG----------------------------------------
VERSION    DATE        USERNAME       UPDATES
--      11-01-2018  kcaldwell      Initial release
--      11-13-2018  kcaldwell      updates the zroomutil
--      02-03-2020  lxhatfield     removed 0 capacity limit
--      03-03-2022  cwalsh1        Expanded columns and building logic for ZROOMUTIL_TEMP insert
--      05-17-2023  wgriffith2  --Dealing with EM courses and updating code to use job_log
--      08-14-2023  wgriffith2  --TKT2754619 - Fixing performance issues
--      05-14-2025  wgriffith2  --fixing runaway job; investigation revealed only table in still use is utl_d_aim.ztimeslot (ZTABLEAU_SVC); leaving that table in the proc and removing all the rest
------------------------------------------------------------------------------------------------*/
END etl_aim_szrroom_refresh;

PROCEDURE etl_aim_szrmros_refresh (jobnumber number, processid varchar2, processname varchar2) is
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
v_proc        VARCHAR2(100) := 'etl_aim_szrmros_refresh';
--
CURSOR c_terms IS
SELECT MAX(tbg.term_code) term_code
  FROM zbtm.terms_by_group_v tbg
 WHERE tbg.group_code = 'STD'
   AND tbg.semester <> 'WIN'
   AND trunc(SYSDATE) BETWEEN tbg.start_date AND tbg.end_date;
BEGIN
-- dbms_output.enable(buffer_size => NULL);
--
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
utl_d_aim.truncate_table(v_table_name => 'SZRMROS');
FOR rec IN c_terms
LOOP
v_count   := 0; -- reset count
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
INSERT INTO utl_d_aim.szrmros
(luid,
 student_last_name,
 student_first_name,
 audit_stu,
 student_email,
 attend_hr,
 date_registered,
 lateadd,
 stu_campus,
 stu_type,
 term,
 course,
 crn,
 subterm,
 credit_hrs,
 college,
 ptrm_crse_start,
 ptrm_crse_end,
 prework_crse_start,
 prework_crse_end,
 camp_start,
 camp_end,
 days,
 course_type,
 instr_luid,
 instr_name,
 instr_email,
 im,
 chair,
 assistant_dean,
 instructor_username,
 im_usernames,
 chair_usernames,
 dean_usernames,
 fsc_usernames,
 sme_usernames,
 admin_usernames,
 dept,
 course_id,
 cross_list_group,
 grade,
 activity_date,
 campus_datasource,
 etl_date)
SELECT iden.spriden_id AS luid,
       iden.spriden_last_name AS student_last_name,
       iden.spriden_first_name AS student_first_name,
       CASE
       WHEN rsts.stvrsts_code = 'AU' THEN
        'Y'
       ELSE
        'N'
       END AS audit_stu,
       emal.email_address AS student_email,
       nvl(to_char(stcr.sfrstcr_attend_hr), 'N/A') AS attend_hr,
       CASE
       WHEN camp.stvcamp_code = 'R' THEN
        stcr.sfrstcr_add_date
       WHEN camp.stvcamp_code = 'D' THEN
        stcr.sfrstcr_rsts_date
       END AS date_registered,
       CASE
       WHEN trunc(stcr.sfrstcr_rsts_date) >= trunc(sect.ssbsect_ptrm_start_date) THEN
        trunc(stcr.sfrstcr_rsts_date)
       END AS lateadd,
       stdn.sgbstdn_camp_code AS stu_campus,
       CASE
       WHEN EXISTS (SELECT 1
               FROM saturn.sfrstcr
               JOIN saturn.stvrsts
                 ON stvrsts.stvrsts_code = sfrstcr.sfrstcr_rsts_code
                AND stvrsts.stvrsts_incl_sect_enrl = 'Y'
                AND sfrstcr.sfrstcr_term_code < rec.term_code
                AND sfrstcr.sfrstcr_pidm = iden.spriden_pidm
               JOIN zsaturn.szrlevl l
                 ON l.szrlevl_levl_code = sfrstcr_levl_code
                AND l.szrlevl_is_univ = 'Y'
                AND l.szrlevl_has_awardable_cred = 'Y'
                AND szrlevl_is_profess = 'N' -- optional if you want to exclude JD/MD
               JOIN saturn.ssbsect
                 ON ssbsect.ssbsect_term_code = sfrstcr.sfrstcr_term_code
                AND ssbsect.ssbsect_crn = sfrstcr.sfrstcr_crn
                AND ssbsect.ssbsect_subj_code NOT IN ('SFME', 'FRSM', 'GRST', 'NSSR', 'CSER')) THEN
        'Returning'
       ELSE
        'New'
       END AS stu_type,
       sect.ssbsect_term_code AS term,
       sect.ssbsect_subj_code || sect.ssbsect_crse_numb || '_' || sect.ssbsect_seq_numb AS course,
       sect.ssbsect_crn AS crn,
       sect.ssbsect_ptrm_code AS subterm,
       stcr.sfrstcr_credit_hr AS credit_hrs,
       CASE
       WHEN coll.stvcoll_code IN ('IN', 'RL', 'SM', 'S2') THEN
        'School of Divinity'
       WHEN sect.ssbsect_subj_code || sect.ssbsect_crse_numb IN ('BIOL103', 'CLST103', 'HIUS542', 'INDS400', 'PHIL201') THEN
        'College of General Studies'
       WHEN sect.ssbsect_subj_code || sect.ssbsect_crse_numb = 'CSIS340' THEN
        'School of Business'
       ELSE
        coll.stvcoll_desc
       END AS college,
       sect.ssbsect_ptrm_start_date AS ptrm_crse_start,
       sect.ssbsect_ptrm_end_date AS ptrm_crse_end,
       MIN(meet.ssrmeet_start_date) AS prework_crse_start,
       MAX(meet.ssrmeet_end_date) AS prework_crse_end,
       MIN(CASE
           WHEN coalesce(meet.ssrmeet_mon_day, meet.ssrmeet_tue_day, meet.ssrmeet_wed_day, meet.ssrmeet_thu_day, meet.ssrmeet_fri_day, meet.ssrmeet_sat_day, meet.ssrmeet_sun_day) IS NOT NULL THEN
            meet.ssrmeet_start_date
           END) AS camp_start,
       MAX(CASE
           WHEN coalesce(meet.ssrmeet_mon_day, meet.ssrmeet_tue_day, meet.ssrmeet_wed_day, meet.ssrmeet_thu_day, meet.ssrmeet_fri_day, meet.ssrmeet_sat_day, meet.ssrmeet_sun_day) IS NOT NULL THEN
            meet.ssrmeet_end_date
           END) AS camp_end,
       (SELECT MAX(meet2.ssrmeet_mon_day) || MAX(meet2.ssrmeet_tue_day) || MAX(meet2.ssrmeet_wed_day) || MAX(meet2.ssrmeet_thu_day) || MAX(meet2.ssrmeet_fri_day) || MAX(meet2.ssrmeet_sat_day) || MAX(meet2.ssrmeet_sun_day)
          FROM saturn.ssrmeet meet2
         WHERE meet2.ssrmeet_term_code = sect.ssbsect_term_code
           AND meet2.ssrmeet_crn = sect.ssbsect_crn) AS days,
       CASE
       WHEN camp.stvcamp_code = 'D' THEN
        NULL
       WHEN sect.ssbsect_insm_code = 'IT'
            AND sect.ssbsect_camp_code = 'D' THEN
        'Online Intensive'
       WHEN sect.ssbsect_insm_code = 'IT'
            AND sect.ssbsect_camp_code = 'R' THEN
        'Residential Intensive'
       ELSE
        'Residential Course'
       END AS course_type,
       inst.spriden_id AS instr_luid,
       nullif(inst.spriden_last_name || ', ' || inst.spriden_first_name, ', ') AS instr_name,
       ieml.email_address AS instr_email,
       nvl(hier.im, 'N/A') AS im,
       nvl(hier.chair, 'N/A') AS chair,
       nvl(hier.adean, 'N/A') AS assistant_dean,
       rls.instructor_username AS instructor_username,
       rls.im_usernames AS im_usernames,
       rls.chair_usernames AS chair_usernames,
       rls.dean_usernames AS dean_usernames,
       rls.fsc_usernames AS fsc_usernames,
       rls.sme_usernames AS sme_usernames,
       rls.admin_usernames || '-skpayne-bebailey2-skpayne-bebailey2-credding3-jdtemple1-mebennett1-' AS admin_usernames,
       dept.stvdept_desc AS dept,
       bbcm.course_id AS course_id,
       CASE
       WHEN camp.stvcamp_code = 'D' THEN
        nvl(xlst.ssrxlst_xlst_group, 'N/A')
       END AS cross_list_group,
       stcr.sfrstcr_grde_code AS grde_code,
       stcr.sfrstcr_activity_date AS activity_date,
       camp.stvcamp_code AS campus_datasource,
       SYSDATE AS etl_date
  FROM saturn.sfrstcr stcr
  JOIN saturn.spriden iden
    ON iden.spriden_pidm = stcr.sfrstcr_pidm
   AND iden.spriden_change_ind IS NULL
   AND stcr.sfrstcr_attend_hr IS NULL
   AND stcr.sfrstcr_add_date < trunc(SYSDATE)
   AND stcr.sfrstcr_term_code = rec.term_code
  JOIN zsaturn.szrlevl l
    ON l.szrlevl_levl_code = sfrstcr_levl_code
   AND l.szrlevl_is_univ = 'Y'
   AND l.szrlevl_has_awardable_cred = 'Y'
   AND szrlevl_is_profess = 'N' -- optional if you want to exclude JD/MD
  JOIN general.gobtpac tpac
    ON tpac.gobtpac_pidm = iden.spriden_pidm
  JOIN saturn.sgbstdn stdn
    ON stdn.sgbstdn_pidm = iden.spriden_pidm
   AND stdn.sgbstdn_term_code_eff = (SELECT MAX(stdn2.sgbstdn_term_code_eff)
                                       FROM saturn.sgbstdn stdn2
                                      WHERE stdn2.sgbstdn_pidm = stdn.sgbstdn_pidm
                                        AND stdn2.sgbstdn_term_code_eff <= rec.term_code)
  JOIN saturn.ssbsect sect
    ON sect.ssbsect_term_code = stcr.sfrstcr_term_code
   AND sect.ssbsect_crn = stcr.sfrstcr_crn
   AND sect.ssbsect_subj_code NOT IN ('SFME', 'FRSM', 'GRST', 'NSSR', 'CSER', 'NEWS', 'LAW')
   AND sect.ssbsect_ptrm_start_date < trunc(SYSDATE) + 1
  JOIN saturn.stvcamp camp
    ON camp.stvcamp_code = 'R'
   AND (sect.ssbsect_insm_code = 'IT' OR sect.ssbsect_camp_code = 'R')
   AND sect.ssbsect_crse_numb NOT IN ('989', '990')
   AND sect.ssbsect_seq_numb NOT LIKE 'A6_%'
   AND sect.ssbsect_subj_code || sect.ssbsect_crse_numb NOT IN ('INQR101', 'RSCH201', 'UNIV101', 'GRST500', 'COUC969', 'THEO690', 'COUN670', 'COUN671', 'CMHC670', 'CMHC671')
   AND sect.ssbsect_subj_code || sect.ssbsect_crse_numb || sect.ssbsect_seq_numb NOT IN ('APOL120A01', 'BIBL160A01', 'BIBL165A01', 'COMN105A01', 'GBST103A01', 'GBST163A01', 'COUC700A60', 'GBST104A01', 'GBST164A01', 'THEO108A01')
    OR camp.stvcamp_code = 'D'
   AND sect.ssbsect_ptrm_code IN ('1A', '1B', '1C', '1D')
   AND (sect.ssbsect_camp_code = 'D' OR sect.ssbsect_subj_code || sect.ssbsect_crse_numb IN ('UNIV101', 'INQR101', 'RSCH201') AND sect.ssbsect_camp_code = 'R')
   AND sect.ssbsect_insm_code NOT IN ('IP', 'IS', 'TH')
   AND sect.ssbsect_schd_code NOT IN ('I', 'E', 'N')
   AND sect.ssbsect_subj_code || sect.ssbsect_crse_numb NOT IN ('GRST500', 'GRST501')
  JOIN saturn.stvrsts rsts
    ON rsts.stvrsts_code = stcr.sfrstcr_rsts_code
   AND rsts.stvrsts_incl_sect_enrl = 'Y'
   AND rsts.stvrsts_withdraw_ind = 'N'
   AND (camp.stvcamp_code = 'R' OR camp.stvcamp_code = 'D' AND rsts.stvrsts_incl_assess = 'Y')
  JOIN saturn.ssrmeet meet
    ON meet.ssrmeet_term_code = sect.ssbsect_term_code
   AND meet.ssrmeet_crn = sect.ssbsect_crn
  JOIN saturn.scbcrse rcrse
    ON rcrse.scbcrse_subj_code = sect.ssbsect_subj_code
   AND rcrse.scbcrse_crse_numb = sect.ssbsect_crse_numb
   AND rcrse.scbcrse_eff_term = (SELECT MAX(rcrse2.scbcrse_eff_term)
                                   FROM saturn.scbcrse rcrse2
                                  WHERE rcrse2.scbcrse_subj_code = rcrse.scbcrse_subj_code
                                    AND rcrse2.scbcrse_crse_numb = rcrse.scbcrse_crse_numb
                                    AND rcrse2.scbcrse_eff_term <= rec.term_code)
  JOIN zexec.zsavemal emal
    ON emal.pidm = iden.spriden_pidm
   AND emal.emal_code = 'LU'
   AND emal.emal_code_rank = 1
  LEFT JOIN (SELECT crse.scbcrse_subj_code,
                    regexp_replace(crse.scbcrse_crse_numb, 'B$') AS scbcrse_crse_numb,
                    crse.scbcrse_coll_code,
                    crse.scbcrse_dept_code
               FROM saturn.scbcrse crse
               JOIN saturn.scbcrky crky
                 ON crky.scbcrky_subj_code = crse.scbcrse_subj_code
                AND crky.scbcrky_crse_numb = crse.scbcrse_crse_numb
                AND rec.term_code BETWEEN crky.scbcrky_term_code_start AND crky.scbcrky_term_code_end
                AND crse.scbcrse_crse_numb LIKE '%B'
                AND crse.scbcrse_eff_term = (SELECT MAX(crse2.scbcrse_eff_term)
                                               FROM saturn.scbcrse crse2
                                              WHERE crse2.scbcrse_subj_code = crse.scbcrse_subj_code
                                                AND crse2.scbcrse_crse_numb = crse.scbcrse_crse_numb
                                                AND crse2.scbcrse_eff_term <= rec.term_code)) bcrse
    ON bcrse.scbcrse_subj_code = sect.ssbsect_subj_code
   AND bcrse.scbcrse_crse_numb = sect.ssbsect_crse_numb
   AND sect.ssbsect_camp_code = 'D'
  LEFT JOIN saturn.stvcoll coll
    ON coll.stvcoll_code = nvl(bcrse.scbcrse_coll_code, rcrse.scbcrse_coll_code)
  LEFT JOIN saturn.stvdept dept
    ON dept.stvdept_code = nvl(bcrse.scbcrse_dept_code, rcrse.scbcrse_dept_code)
  LEFT JOIN saturn.sirasgn asgn
    ON asgn.sirasgn_term_code = sect.ssbsect_term_code
   AND asgn.sirasgn_crn = sect.ssbsect_crn
   AND asgn.sirasgn_primary_ind = 'Y'
  LEFT JOIN saturn.spriden inst
    ON inst.spriden_pidm = asgn.sirasgn_pidm
   AND inst.spriden_change_ind IS NULL
  LEFT JOIN zexec.zsavemal ieml
    ON ieml.pidm = inst.spriden_pidm
   AND ieml.emal_code = 'LU'
   AND ieml.emal_code_rank = 1
  LEFT JOIN utl_d_aa.secfht rls
    ON rls.term_code = sect.ssbsect_term_code
   AND rls.crn = sect.ssbsect_crn
  LEFT JOIN saturn.ssrxlst xlst
    ON camp.stvcamp_code = 'D'
   AND xlst.ssrxlst_term_code = sect.ssbsect_term_code
   AND xlst.ssrxlst_crn = sect.ssbsect_crn
  LEFT JOIN bblearn.course_main bbcm
    ON camp.stvcamp_code = 'D'
   AND bbcm.batch_uid = nvl2(xlst.ssrxlst_crn, xlst.ssrxlst_term_code || 'XLST' || xlst.ssrxlst_xlst_group, sect.ssbsect_term_code || sect.ssbsect_crn)
  LEFT JOIN (SELECT MAX(CASE
                        WHEN position_id = root_id THEN
                         pidm
                        END) AS pidm,
                    MAX(CASE
                        WHEN position_id = root_id THEN
                         faculty
                        END) AS faculty,
                    MAX(CASE
                        WHEN title_id = 6 THEN
                         faculty
                        END) AS im,
                    MAX(CASE
                        WHEN title_id = 5 THEN
                         faculty
                        END) AS chair,
                    MAX(CASE
                        WHEN title_id = 4 THEN
                         faculty
                        END) AS adean
               FROM (SELECT p.id AS position_id,
                            p.pidm,
                            i.spriden_last_name || ', ' || i.spriden_first_name AS faculty,
                            t.id AS title_id,
                            sys_connect_by_path(p.pidm, '/') AS path,
                            connect_by_root p.id AS root_id,
                            connect_by_root t.id AS root_title_id,
                            connect_by_root p.primary_faculty AS root_primary_faculty,
                            connect_by_isleaf AS leaf
                       FROM zhierarchy.position p
                       JOIN saturn.spriden i
                         ON i.spriden_pidm = p.pidm
                        AND i.spriden_change_ind IS NULL
                       JOIN zhierarchy.department d
                         ON d.id = p.department_id
                       JOIN zhierarchy.hierarchy_title ht
                         ON ht.id = p.hierarchy_title_id
                       JOIN zhierarchy.title t
                         ON t.id = ht.title_id
                     CONNECT BY nocycle PRIOR p.approval_position_id = p.id)
              WHERE root_title_id = 7
                AND root_primary_faculty = 'Y'
              GROUP BY root_id) hier
    ON hier.pidm = inst.spriden_pidm
 GROUP BY iden.spriden_pidm,
          iden.spriden_id,
          iden.spriden_first_name,
          iden.spriden_last_name,
          CASE
          WHEN rsts.stvrsts_code = 'AU' THEN
           'Y'
          ELSE
           'N'
          END,
          emal.email_address,
          nvl(to_char(stcr.sfrstcr_attend_hr), 'N/A'),
          CASE
          WHEN camp.stvcamp_code = 'R' THEN
           stcr.sfrstcr_add_date
          WHEN camp.stvcamp_code = 'D' THEN
           stcr.sfrstcr_rsts_date
          END,
          CASE
          WHEN trunc(stcr.sfrstcr_rsts_date) >= trunc(sect.ssbsect_ptrm_start_date) THEN
           trunc(stcr.sfrstcr_rsts_date)
          END,
          stdn.sgbstdn_camp_code,
          sect.ssbsect_term_code,
          sect.ssbsect_subj_code || sect.ssbsect_crse_numb || '_' || sect.ssbsect_seq_numb,
          sect.ssbsect_crn,
          sect.ssbsect_ptrm_code,
          stcr.sfrstcr_credit_hr,
          CASE
          WHEN coll.stvcoll_code IN ('IN', 'RL', 'SM', 'S2') THEN
           'School of Divinity'
          WHEN sect.ssbsect_subj_code || sect.ssbsect_crse_numb IN ('BIOL103', 'CLST103', 'HIUS542', 'INDS400', 'PHIL201') THEN
           'College of General Studies'
          WHEN sect.ssbsect_subj_code || sect.ssbsect_crse_numb = 'CSIS340' THEN
           'School of Business'
          ELSE
           coll.stvcoll_desc
          END,
          sect.ssbsect_ptrm_start_date,
          sect.ssbsect_ptrm_end_date,
          CASE
          WHEN camp.stvcamp_code = 'D' THEN
           NULL
          WHEN sect.ssbsect_insm_code = 'IT'
               AND sect.ssbsect_camp_code = 'D' THEN
           'Online Intensive'
          WHEN sect.ssbsect_insm_code = 'IT'
               AND sect.ssbsect_camp_code = 'R' THEN
           'Residential Intensive'
          ELSE
           'Residential Course'
          END,
          inst.spriden_id,
          inst.spriden_last_name || ', ' || inst.spriden_first_name,
          ieml.email_address,
          nvl(hier.im, 'N/A'),
          nvl(hier.chair, 'N/A'),
          nvl(hier.adean, 'N/A'),
          rls.instructor_username,
          rls.im_usernames,
          rls.chair_usernames,
          rls.dean_usernames,
          rls.fsc_usernames,
          rls.sme_usernames,
          rls.admin_usernames,
          dept.stvdept_desc,
          stcr.sfrstcr_activity_date,
          stcr.sfrstcr_grde_code,
          bbcm.course_id,
          CASE
          WHEN camp.stvcamp_code = 'D' THEN
           nvl(xlst.ssrxlst_xlst_group, 'N/A')
          END,
          camp.stvcamp_code;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
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
1.0        3-7-2019    kcaldwell      Initial release
2.0        3-1-2020    lxhatfield     rewrote insert due to job hitting temp space errors
---     05-17-2023  wgriffith2  --Dealing with EM courses and updating code to use job_log
-----------------------------------------------------------------------------------------------*/
END etl_aim_szrmros_refresh;

procedure etl_aim_szrctlg_refresh(jobnumber number, processid varchar2, processname varchar2) is

/* *********************************************************************** */
/* ********* LIBERTY UNIVERSITY - Analytics and Decision Support ********* */
/* ********* OJBECT NAME: UTL_D_AA.szrctlg                       ********* */
/* ********* DESCRIPTION: Refresh for Course Catalog             ********* */
/* ********* CREATED BY: Lucy Hatfield                           ********* */
/* ********* (See CHANGE LOG at bottom of file)                  ********* */
/* *********************************************************************** */

--declare
  v_cnt        number := 0;
  v_etl_date   date   := sysdate;
  v_end_date   date   := v_etl_date - 1 / (24 * 60 * 60);

  cursor c_new_inserts is

    select nw.*
         , case when ol.subj is null then 'INSERT_NEW_ROW'
                when ol.b_course||'-'||ol.from_term||'-'||ol.to_term||'-'||ol.coll_code||'-'||ol.divs_code||'-'||ol.dept_code||'-'||ol.csta_code||'-'||ol.title||'-'||ol.cipc_code||'-'||ol.credit_hr_ind||'-'||ol.credit_hr_low||'-'||ol.credit_hr_high||'-'||ol.lec_hr_ind||'-'||ol.lec_hr_low||'-'||ol.lec_hr_high||'-'||ol.lab_hr_ind||'-'||ol.lab_hr_low||'-'||ol.lab_hr_high||'-'||ol.oth_hr_ind||'-'||ol.oth_hr_low||'-'||ol.oth_hr_high||'-'||ol.bill_hr_ind||'-'||ol.bill_hr_low||'-'||ol.bill_hr_high||'-'||ol.aprv_code||'-'||ol.repeat_limit||'-'||ol.pwav_code||'-'||ol.tuiw_ind||'-'||ol.add_fees_ind||'-'||ol.scbcrse_activity_date||'-'||ol.cont_hr_low||'-'||ol.cont_hr_ind||'-'||ol.cont_hr_high||'-'||ol.ceu_ind||'-'||ol.reps_code||'-'||ol.max_rpt_units||'-'||ol.capp_prereq_test_ind||'-'||ol.dunt_code||'-'||ol.number_of_units||'-'||ol.data_origin||'-'||ol.user_id||'-'||ol.prereq_chk_method_cde||'-'||ol.surrogate_id||'-'||ol.version||'-'||ol.vpdi_code||'-'||ol.max_record
                  <> nw.b_course||'-'||nw.from_term||'-'||nw.to_term||'-'||nw.coll_code||'-'||nw.divs_code||'-'||nw.dept_code||'-'||nw.csta_code||'-'||nw.title||'-'||nw.cipc_code||'-'||nw.credit_hr_ind||'-'||nw.credit_hr_low||'-'||nw.credit_hr_high||'-'||nw.lec_hr_ind||'-'||nw.lec_hr_low||'-'||nw.lec_hr_high||'-'||nw.lab_hr_ind||'-'||nw.lab_hr_low||'-'||nw.lab_hr_high||'-'||nw.oth_hr_ind||'-'||nw.oth_hr_low||'-'||nw.oth_hr_high||'-'||nw.bill_hr_ind||'-'||nw.bill_hr_low||'-'||nw.bill_hr_high||'-'||nw.aprv_code||'-'||nw.repeat_limit||'-'||nw.pwav_code||'-'||nw.tuiw_ind||'-'||nw.add_fees_ind||'-'||nw.scbcrse_activity_date||'-'||nw.cont_hr_low||'-'||nw.cont_hr_ind||'-'||nw.cont_hr_high||'-'||nw.ceu_ind||'-'||nw.reps_code||'-'||nw.max_rpt_units||'-'||nw.capp_prereq_test_ind||'-'||nw.dunt_code||'-'||nw.number_of_units||'-'||nw.data_origin||'-'||nw.user_id||'-'||nw.prereq_chk_method_cde||'-'||nw.surrogate_id||'-'||nw.version||'-'||nw.vpdi_code||'-'||nw.max_record
                then 'END_EXISTING_ROW'
           end action
    from ( select subj
                , nvl(new_numb,numb) as numb
                , case when numb like '%B' then 'B' end as b_course
                , camp_code
                , nvl(new_from_term, from_term) as from_term
                , nvl(new_to_term, to_term) as to_term
                , coll_code
                , divs_code
                , dept_code
                , csta_code
                , title
                , cipc_code
                , credit_hr_ind
                , credit_hr_low
                , credit_hr_high
                , lec_hr_ind
                , lec_hr_low
                , lec_hr_high
                , lab_hr_ind
                , lab_hr_low
                , lab_hr_high
                , oth_hr_ind
                , oth_hr_low
                , oth_hr_high
                , bill_hr_ind
                , bill_hr_low
                , bill_hr_high
                , aprv_code
                , repeat_limit
                , pwav_code
                , tuiw_ind
                , add_fees_ind
                , scbcrse_activity_date
                , cont_hr_low
                , cont_hr_ind
                , cont_hr_high
                , ceu_ind
                , reps_code
                , max_rpt_units
                , capp_prereq_test_ind
                , dunt_code
                , number_of_units
                , data_origin
                , user_id
                , prereq_chk_method_cde
                , surrogate_id
                , version
                , vpdi_code
                , case when rank() over (partition by subj
                                                    , nvl(new_numb,numb)
                                                    , camp_code
                                         order by case when to_date = to_date('12/31/2099','MM/DD/YYYY') then 0 else 1 end
                                                , nvl(new_to_term, to_term) desc
                                                , nvl(new_from_term, from_term) desc) = 1 then 'Y' else 'N' end as max_record
                , etl_date
                , from_date
                , to_date
           from (
           with base as (select /*+ materialize*/
                                crse.scbcrse_subj_code             as subj
                              , crse.scbcrse_crse_numb             as numb
                              , crse.scbcrse_eff_term              as from_term
                              ,(select min(term)
                                from (select to_char(min(crse2.scbcrse_eff_term) - 1) term
                                      from saturn.scbcrse crse2
                                      where crse2.scbcrse_subj_code = crse.scbcrse_subj_code
                                        and crse2.scbcrse_crse_numb = crse.scbcrse_crse_numb
                                        and crse2.scbcrse_eff_term > crse.scbcrse_eff_term
                                      union all
                                      select crky.scbcrky_term_code_end
                                      from saturn.scbcrky crky
                                      where crky.scbcrky_subj_code = crse.scbcrse_subj_code
                                        and crky.scbcrky_crse_numb = crse.scbcrse_crse_numb
                                      union all
                                      select '999999'
                                      from dual))                   as to_term
                               , crse.scbcrse_coll_code             as coll_code
                               , crse.scbcrse_divs_code             as divs_code
                               , crse.scbcrse_dept_code             as dept_code
                               , crse.scbcrse_csta_code             as csta_code
                               , crse.scbcrse_title                 as title
                               , crse.scbcrse_cipc_code             as cipc_code
                               , crse.scbcrse_credit_hr_ind         as credit_hr_ind
                               , crse.scbcrse_credit_hr_low         as credit_hr_low
                               , crse.scbcrse_credit_hr_high        as credit_hr_high
                               , crse.scbcrse_lec_hr_ind            as lec_hr_ind
                               , crse.scbcrse_lec_hr_low            as lec_hr_low
                               , crse.scbcrse_lec_hr_high           as lec_hr_high
                               , crse.scbcrse_lab_hr_ind            as lab_hr_ind
                               , crse.scbcrse_lab_hr_low            as lab_hr_low
                               , crse.scbcrse_lab_hr_high           as lab_hr_high
                               , crse.scbcrse_oth_hr_ind            as oth_hr_ind
                               , crse.scbcrse_oth_hr_low            as oth_hr_low
                               , crse.scbcrse_oth_hr_high           as oth_hr_high
                               , crse.scbcrse_bill_hr_ind           as bill_hr_ind
                               , crse.scbcrse_bill_hr_low           as bill_hr_low
                               , crse.scbcrse_bill_hr_high          as bill_hr_high
                               , crse.scbcrse_aprv_code             as aprv_code
                               , crse.scbcrse_repeat_limit          as repeat_limit
                               , crse.scbcrse_pwav_code             as pwav_code
                               , crse.scbcrse_tuiw_ind              as tuiw_ind
                               , crse.scbcrse_add_fees_ind          as add_fees_ind
                               , crse.scbcrse_activity_date         as scbcrse_activity_date
                               , crse.scbcrse_cont_hr_low           as cont_hr_low
                               , crse.scbcrse_cont_hr_ind           as cont_hr_ind
                               , crse.scbcrse_cont_hr_high          as cont_hr_high
                               , crse.scbcrse_ceu_ind               as ceu_ind
                               , crse.scbcrse_reps_code             as reps_code
                               , crse.scbcrse_max_rpt_units         as max_rpt_units
                               , crse.scbcrse_capp_prereq_test_ind  as capp_prereq_test_ind
                               , crse.scbcrse_dunt_code             as dunt_code
                               , crse.scbcrse_number_of_units       as number_of_units
                               , crse.scbcrse_data_origin           as data_origin
                               , crse.scbcrse_user_id               as user_id
                               , crse.scbcrse_prereq_chk_method_cde as prereq_chk_method_cde
                               , crse.scbcrse_surrogate_id          as surrogate_id
                               , crse.scbcrse_version               as version
                               , crse.scbcrse_vpdi_code             as vpdi_code
                               , to_date('1/1/1971','MM/DD/YYYY')   as from_date
                               , to_date('12/31/2099','MM/DD/YYYY') as to_date
                               , sysdate                            as etl_date
                         from saturn.scbcrse crse
                        where 1 = 1
                           --and crse.scbcrse_subj_code = 'APOL'
                           --and crse.scbcrse_crse_numb like '500%'
                           and(crse.scbcrse_crse_numb not like '%B'
                            or crse.scbcrse_crse_numb like '%B'
                           /*and crse.scbcrse_csta_code != 'I'*/)
                           and crse.scbcrse_eff_term <=(select crky.scbcrky_term_code_end
                                                        from saturn.scbcrky crky
                                                        where crky.scbcrky_subj_code = crse.scbcrse_subj_code
                                                          and crky.scbcrky_crse_numb = crse.scbcrse_crse_numb)
                         )
           /*Generate record for when a B course is ended*/
           select regexp_replace(base.numb,'B$') as new_numb
                , 'D' as camp_code
                , greatest(to_char(base.to_term + 1),r.from_term) as new_from_term
                , null as new_to_term
                , r.*
           from base
           join base r on r.subj = base.subj
                      and r.numb||'B' = base.numb
                      and base.to_term + 1 between r.from_term and r.to_term
           where base.numb like '%B'
             and base.to_term != '999999'
             and greatest(to_char(base.to_term + 1),r.from_term) != r.to_term
             and not exists (select 1
                             from base b2
                             where b2.subj = base.subj
                               and b2.numb = base.numb
                               and b2.from_term = base.to_term + 1)
           union all
           /*Generate record for when a B course is opened*/
           select regexp_replace(base.numb,'B$') as new_numb
                , 'D' as camp_code
                , null as new_from_term
                , to_char(base.from_term - 1) as new_to_term
                , r.*
           from base
           join base r on r.subj = base.subj
                      and r.numb||'B' = base.numb
                      and base.from_term - 1 between r.from_term and r.to_term
           where base.numb like '%B'
             and base.from_term - 1 != r.to_term
           and not exists (select 1
                           from base b2
                           where b2.subj = base.subj
                             and b2.numb = base.numb
                             and b2.to_term = base.from_term - 1)
           union all
           /*Normal records*/
           select regexp_replace(base.numb,'B$') as new_numb
                , camp.stvcamp_code as camp_code
                , null as new_from_term
                , null as new_to_term
                , base.*
           from base
           join saturn.stvcamp camp on camp.stvcamp_code in ('R','D')
           where(base.numb not like '%B'
             and(camp.stvcamp_code = 'R'
                 or not exists (select 1
                                from base b
                                where b.subj = base.subj
                                  and b.numb = base.numb||'B'
                                  and b.from_term <= base.to_term
                                  and b.to_term >= base.from_term
                 and camp.stvcamp_code = 'D'))
             or base.numb like '%B'
            and camp.stvcamp_code = 'D')
           )) nw

    left join utl_d_aim.szrctlg ol on ol.subj = nw.subj
                                  and ol.numb = nw.numb
                                  and ol.camp_code = nw.camp_code
                                  and nw.from_term between ol.from_term and ol.to_term
                                  and ol.to_date = to_date('12/31/2099','MM/DD/YYYY')
 ;
begin
  for r in c_new_inserts loop
    v_cnt := v_cnt + 1;
    -- update the ETL date to the static etl job run time, this denotes that the record still exists at the same grain with no changes
    if r.action is null then
      update utl_d_aim.szrctlg t
         set t.etl_date  = v_etl_date
       where t.subj      = r.subj
         and t.numb      = r.numb
         and t.camp_code = r.camp_code
         and t.from_term = r.from_term
         and t.to_date   = to_date('12/31/2099','MM/DD/YYYY');
    end if;

    -- end records where the data has changed
    if r.action = 'END_EXISTING_ROW' then
       update utl_d_aim.szrctlg t
          set t.to_date    = v_end_date
            , t.etl_date   = v_etl_date
            , t.max_record = 'N'
        where t.subj       = r.subj
          and t.numb       = r.numb
          and t.camp_code  = r.camp_code
          and t.from_term  = r.from_term
          and t.to_date    = to_date('12/31/2099','MM/DD/YYYY');
    end if;

--    dbms_output.put_line(r.subj||r.numb||' ('||r.camp_code||'): '||r.from_term||' - '||r.to_term);

    -- insert new record or new version of record ended above
    if r.action in ('INSERT_NEW_ROW','END_EXISTING_ROW') then
      insert into utl_d_aim.szrctlg(subj, numb, b_course, camp_code, from_term, to_term, coll_code, divs_code, dept_code, csta_code, title, cipc_code, credit_hr_ind, credit_hr_low, credit_hr_high, lec_hr_ind, lec_hr_low, lec_hr_high, lab_hr_ind, lab_hr_low, lab_hr_high, oth_hr_ind, oth_hr_low, oth_hr_high, bill_hr_ind, bill_hr_low, bill_hr_high, aprv_code, repeat_limit, pwav_code, tuiw_ind, add_fees_ind, scbcrse_activity_date, cont_hr_low, cont_hr_ind, cont_hr_high, ceu_ind, reps_code, max_rpt_units, capp_prereq_test_ind, dunt_code, number_of_units, data_origin, user_id, prereq_chk_method_cde, surrogate_id, version, vpdi_code, max_record, etl_date, from_date, to_date)
      values (r.subj, r.numb, r.b_course, r.camp_code, r.from_term, r.to_term, r.coll_code, r.divs_code, r.dept_code, r.csta_code, r.title, r.cipc_code, r.credit_hr_ind, r.credit_hr_low, r.credit_hr_high, r.lec_hr_ind, r.lec_hr_low, r.lec_hr_high, r.lab_hr_ind, r.lab_hr_low, r.lab_hr_high, r.oth_hr_ind, r.oth_hr_low, r.oth_hr_high, r.bill_hr_ind, r.bill_hr_low, r.bill_hr_high, r.aprv_code, r.repeat_limit, r.pwav_code, r.tuiw_ind, r.add_fees_ind, r.scbcrse_activity_date, r.cont_hr_low, r.cont_hr_ind, r.cont_hr_high, r.ceu_ind, r.reps_code, r.max_rpt_units, r.capp_prereq_test_ind, r.dunt_code, r.number_of_units, r.data_origin, r.user_id, r.prereq_chk_method_cde, r.surrogate_id, r.version, r.vpdi_code, r.max_record, v_etl_date, v_etl_date, to_date('12/31/2099','MM/DD/YYYY'));
    end if;
  end loop;

  -- End records that don't exist in current cursor
  update utl_d_aim.szrctlg
     set to_date   = v_end_date
   where to_date   = to_date('12/31/2099','MM/DD/YYYY')
     and etl_date  < v_etl_date; -- record wasn't looped over on last run, so it no longer exists, end it.

  commit;

  exception
    when others then
      rollback;
      raise;
      dbms_output.put_line(sqlerrm);

/*exception
  when others then
   rollback;
   raise;*/
--end;
/*--------------------------------------------CHANGE LOG----------------------------------------
VERSION    DATE        USERNAME       UPDATES
0.1        12-06-2019  lxhatfield     Initial release
------------------------------------------------------------------------------------------------*/
--END;

END etl_aim_szrctlg_refresh;

procedure etl_aim_szrasgn_refresh(jobnumber number, processid varchar2, processname varchar2) is
--DECLARE
--- PARAMS
v_etl_date DATE := SYSDATE;
v_msg      VARCHAR2(2000);
v_row_max  NUMBER := 1000000; -- max number of rows to be processed at one time
v_instance VARCHAR2(50) := upper('ALL'); -- inst from the jams job; used for determining instance
v_partition NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
-- v_mod         NUMBER := 5; -- number of partitions to be created

v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_aim_szrasgn_refresh';
v_end_date    DATE := v_etl_date - 1 / (24 * 60 * 60);
CURSOR c1 IS
SELECT nvl(nw.term_code, ol.term_code) AS term_code,
       nvl(nw.crn, ol.crn) AS crn,
       nvl(nw.pidm, ol.pidm) AS pidm,
       nvl(nw.category, ol.category) AS category,
       nw.percent_response,
       nw.workload_adjust,
       nw.percent_sess,
       nw.primary_ind,
       nw.over_ride,
       nw.fcnt_code,
       nw.asty_code,
       v_etl_date AS etl_date,
       v_etl_date AS from_date,
       CASE
       WHEN nw.term_code IS NULL THEN
        v_end_date
       WHEN nw.row_hash != ol.row_hash THEN
        v_end_date
       WHEN ol.term_code IS NULL THEN
        nw.to_date
       END AS to_date,
       nw.row_hash,
       CASE
       WHEN nw.term_code IS NULL THEN
        'UPDATE'
       WHEN nw.row_hash != ol.row_hash THEN
        'UPDATE'
       WHEN ol.term_code IS NULL THEN
        'INSERT'
       END AS control_state,
       nw.data_origin,
       nw.user_id,
       nw.user_pidm,
       nw.index_code,
       nw.budget_code,
       nw.budget_code_title AS budget_title
  FROM (SELECT asgn.sirasgn_term_code AS term_code,
               asgn.sirasgn_crn AS crn,
               asgn.sirasgn_pidm AS pidm,
               asgn.sirasgn_category AS category,
               asgn.sirasgn_percent_response AS percent_response,
               asgn.sirasgn_workload_adjust AS workload_adjust,
               asgn.sirasgn_percent_sess AS percent_sess,
               asgn.sirasgn_primary_ind AS primary_ind,
               asgn.sirasgn_over_ride AS over_ride,
               asgn.sirasgn_fcnt_code AS fcnt_code,
               asgn.sirasgn_asty_code AS asty_code,
               to_date('12/31/2099', 'MM/DD/YYYY') AS to_date,
               standard_hash(asgn.sirasgn_term_code || '-' || asgn.sirasgn_crn || '-' || asgn.sirasgn_pidm || '-' || asgn.sirasgn_category || '-' || asgn.sirasgn_percent_response || '-' || asgn.sirasgn_workload_adjust || '-' ||
                             asgn.sirasgn_percent_sess || '-' || asgn.sirasgn_primary_ind || '-' || asgn.sirasgn_over_ride || '-' || asgn.sirasgn_fcnt_code || '-' || asgn.sirasgn_asty_code, 'MD5') AS row_hash,
               asgn.sirasgn_data_origin AS data_origin,
               asgn.sirasgn_user_id AS user_id,
               iden.spriden_pidm AS user_pidm,
               ae.empdeptindex AS index_code,
               org.ftvorgn_orgn_code AS budget_code,
               org.ftvorgn_title AS budget_code_title
          FROM saturn.sirasgn asgn
          JOIN (SELECT MAX(term_code) AS current_term FROM zbtm.terms_by_group_v WHERE start_date <= v_etl_date)
            ON asgn.sirasgn_term_code BETWEEN current_term - 100 AND current_term + 100
          LEFT JOIN general.gobtpac tpac
            ON tpac.gobtpac_ldap_user = asgn.sirasgn_user_id
          LEFT JOIN saturn.spriden iden
            ON iden.spriden_pidm = tpac.gobtpac_pidm
           AND iden.spriden_change_ind IS NULL
          LEFT JOIN zgeneral.activeemployees ae
            ON ae.empid = iden.spriden_id
           AND ae.empclassrank = 1
           AND ae.empstatus IN ('A', 'L')
          LEFT JOIN fimsmgr.ftvacci ind
            ON ind.ftvacci_acci_code = ae.empdeptindex
           AND ind.ftvacci_coas_code = 'U'
           AND ind.ftvacci_status_ind = 'A'
           AND v_etl_date BETWEEN ind.ftvacci_eff_date AND ind.ftvacci_nchg_date
           AND ind.ftvacci_term_date IS NULL
          LEFT JOIN fimsmgr.ftvorgn org
            ON org.ftvorgn_orgn_code = ind.ftvacci_orgn_code
           AND org.ftvorgn_coas_code = 'U'
           AND org.ftvorgn_status_ind = 'A'
           AND v_etl_date BETWEEN ftvorgn_eff_date AND org.ftvorgn_nchg_date
           AND ftvorgn_term_date IS NULL) nw
  FULL OUTER JOIN (SELECT *
                     FROM utl_d_aim.szrasgn asgn
                    CROSS JOIN (SELECT MAX(term_code) AS current_term FROM zbtm.terms_by_group_v WHERE start_date <= v_etl_date)
                    WHERE asgn.term_code BETWEEN current_term - 100 AND current_term + 100
                      AND asgn.to_date = to_date('12/31/2099', 'MM/DD/YYYY')) ol
    ON ol.term_code = nw.term_code
   AND ol.crn = nw.crn
   AND ol.pidm = nw.pidm
   AND ol.category = nw.category
   AND ol.term_code BETWEEN current_term - 100 AND current_term + 100
 WHERE 1 = 1
   AND nw.term_code IS NULL
    OR ol.term_code IS NULL
    OR nw.row_hash != ol.row_hash;
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
insert_count NUMBER := 0;
update_count NUMBER := 0;
delete_count NUMBER := 0;
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
INSERT INTO utl_d_aim.szrasgn tab
(term_code,
 crn,
 pidm,
 category,
 percent_response,
 workload_adjust,
 percent_sess,
 primary_ind,
 over_ride,
 fcnt_code,
 asty_code,
 etl_date,
 from_date,
 to_date,
 row_hash,
 data_origin,
 user_id,
 user_pidm,
 index_code,
 budget_code,
 budget_title)
VALUES
(rec_input(i).term_code,
 rec_input(i).crn,
 rec_input(i).pidm,
 rec_input(i).category,
 rec_input(i).percent_response,
 rec_input(i).workload_adjust,
 rec_input(i).percent_sess,
 rec_input(i).primary_ind,
 rec_input(i).over_ride,
 rec_input(i).fcnt_code,
 rec_input(i).asty_code,
 rec_input(i).etl_date,
 rec_input(i).from_date,
 rec_input(i).to_date,
 rec_input(i).row_hash,
 rec_input(i).data_origin,
 rec_input(i).user_id,
 rec_input(i).user_pidm,
 rec_input(i).index_code,
 rec_input(i).budget_code,
 rec_input(i).budget_title);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'INSERT - ' || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
FORALL i IN VALUES OF update_dml -- DML UPDATES
UPDATE utl_d_aim.szrasgn tab
   SET (etl_date, to_date) =
       (SELECT rec_input(i).etl_date,
               rec_input(i).to_date
          FROM dual)
 WHERE tab.term_code = rec_input(i).term_code
   AND tab.crn = rec_input(i).crn
   AND tab.pidm = rec_input(i).pidm
   AND tab.category = rec_input(i).category;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'UPDATE - ' || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
FORALL i IN VALUES OF delete_dml -- DML DELETES
DELETE FROM utl_d_aim.szrasgn tab
 WHERE tab.term_code = rec_input(i).term_code
   AND tab.crn = rec_input(i).crn
   AND tab.pidm = rec_input(i).pidm
   AND tab.category = rec_input(i).category;
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
VERSION    DATE        USERNAME       UPDATES
1.0        04-01-2020  lxhatfield     Initial release (TKT2187409)
1.1        09-10-2020  lxhatfield     Added columns for TKT2243683
1.2        09-18-2020  lxhatfield     Adjusted code to remove non-essential columns that we don't want to be tracking changes for
---     05-24-2023  wgriffith2  --updating code to use job_log
---     08-14-2023  wgriffith2  --performance updates
------------------------------------------------------------------------------------------------*/
END etl_aim_szrasgn_refresh;

procedure etl_aim_progcolldept_refresh (jobnumber number, processid varchar2, processname varchar2) is
--DECLARE
v_etl_date DATE := SYSDATE;
v_msg      VARCHAR2(2000);
v_instance VARCHAR2(50) := upper('ALL'); -- inst from the jams job; used for determining instance
v_partition NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
-- v_mod         NUMBER := 5; -- number of partitions to be created

v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_aim_progcolldept_refresh';
BEGIN
-- dbms_output.enable(buffer_size => NULL);
--
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
DELETE FROM utl_d_aim.progcolldept pcd WHERE NOT EXISTS (SELECT cl.prog_code FROM zdegree_audit.clblocks cl WHERE cl.prog_code = pcd.prog_code);
v_count := SQL%ROWCOUNT;
dbms_lock.sleep(1.0); -- pause
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'DELETE - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
MERGE INTO utl_d_aim.progcolldept o
USING (SELECT prog_code,
              majr_degc_group,
              dual_level_prog_code
         FROM (SELECT cl.prog_code AS prog_code,
                      pc.programtitle AS majr_degc_group,
                      progval.assoc_dual_levl AS dual_level_prog_code,
                      rank() over(PARTITION BY cl.prog_code ORDER BY progval.ctlg_term_start DESC, rownum) ranking
                 FROM zdegree_audit.clblocks cl
                 LEFT JOIN courseleaf_etl.program pc
                   ON pc.key = cl.cl_key
                 LEFT JOIN zdegree_audit.daprogavail progval
                   ON progval.prog_code = cl.prog_code) src
        WHERE src.ranking = 1) n
ON (o.prog_code = n.prog_code)
WHEN MATCHED THEN
UPDATE
   SET o.majr_degc_group      = n.majr_degc_group,
       o.dual_level_prog_code = n.dual_level_prog_code
 WHERE
-- Only update if the points_submitted value is different and not null
 (nvl(o.majr_degc_group, 'x') != nvl(n.majr_degc_group, 'x'))
 OR (nvl(o.dual_level_prog_code, 'x') != nvl(n.dual_level_prog_code, 'x'))
WHEN NOT MATCHED THEN
INSERT
(prog_code,
 majr_degc_group,
 dual_level_prog_code)
VALUES
(n.prog_code,
 n.majr_degc_group,
 n.dual_level_prog_code);
v_count := SQL%ROWCOUNT;
COMMIT;
dbms_lock.sleep(1.0); -- pause
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
dbms_lock.sleep(1.0); -- pause
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
/*--------------------------------------------CHANGE LOG----------------------------------------
VERSION    DATE        USERNAME       UPDATES
---        04-22-2020  lxhatfield    --Initial release
---        08-14-2025  wgriffith2    --now using zdegree_audit.clblocks; courseleaf_etl.program; zdegree_audit.daprogavail
------------------------------------------------------------------------------------------------*/
END etl_aim_progcolldept_refresh;

procedure etl_aim_acad_cohorts_refresh (jobnumber number, processid varchar2, processname varchar2) is
--declare
/* *********************************************************************** */
/* ********* liberty university - analytics and decision support ********* */
/* ********* ojbect name: utl_d_aim.academic_cohorts             ********* */
/* ********* description: this table contains cohorts for the    ********* */
/* ********* cohort academic overiew dashboard on the academic   ********* */
/* ********* tableau site                                        ********* */
/* ********* created by: smmatulionis                            ********* */
/* ********* (see change log at bottom of file)                  ********* */
/* *********************************************************************** */
    v_current_term stvterm.stvterm_code%type;
    pragma autonomous_transaction;

begin
    dbms_output.enable(null);

    dbms_output.put_line('Academic cohorts refresh started');

    select max(term_code)
    into v_current_term
    from zbtm.terms_by_group_v
    where group_code = 'STD'
      and semester != 'WIN'
      and sysdate between start_date and end_date;

    dbms_output.put_line('Refreshing '||v_current_term);

    /*clear all current term records*/
    delete from utl_d_aim.academic_cohorts where term_code = v_current_term;

    dbms_output.put_line('Removed '||sql%rowcount||' rows');

    /*insert current debate team students*/
    insert into utl_d_aim.academic_cohorts(pidm,
                                           category,
                                           sub_category,
                                           term_code)
    select s.pidm,
           'Debate Team',
           '',
           v_current_term
    from zdebate.student s
    join spriden on spriden_pidm = s.pidm
     and spriden_change_ind is null
    where status = 'CURRENT';

    dbms_output.put_line('Added '||sql%rowcount||' rows for debate team');

    /*insert current inds students*/
    insert into utl_d_aim.academic_cohorts(pidm,
                                           category,
                                           sub_category,
                                           term_code)
     select enrl.pidm,
            'INDS Students',
            enrl.majr_code_1,
            v_current_term
     from utl_d_aim.szrenrl enrl
     where (enrl.majr_code_1 in ('INDS', 'INDI')
           or enrl.majr_code_2 in ('INDS', 'INDI'))
     and enrl.camp_code = 'R'
     and enrl.term_code = v_current_term;

    dbms_output.put_line('Added '||sql%rowcount||' rows for INDS');

    commit;

    dbms_output.put_line('Academic cohorts refresh completed');
exception
    when others then
      rollback;
      raise;
      dbms_output.put_line(sqlerrm);
/*--------------------------------------------change log----------------------------------------
version    date        username       updates
1.0        05-12-2020  smmatulionis   initial release
------------------------------------------------------------------------------------------------*/
--end;
end etl_aim_acad_cohorts_refresh;

procedure etl_aim_traneval_sd_mod(jobnumber number, processid varchar2, processname varchar2, mod_number number) is
--
-- PURPOSE: Builds Tableau-ready transfer evaluation workflow metrics (routing, assignment, and completion turnaround) to support Registrar/RO operational reporting.
--
-- TABLE: utl_d_aim.traneval_sd, utl_d_aim.traneval_tableau
--
-- UNIQUE INDEX: N/A - Full data refresh
--
-- CONDITIONS:
-- Fully refreshes the data by truncating and reloading both the staging table (TRANEVAL_SD) and the reporting table (TRANEVAL_TABLEAU).
-- Includes only documents whose document type name is present and does not start with "z" (excludes null and "z%" document types).
-- Includes only documents that have audit activity on or after the first day of the month one year ago (AUDITDATETIME >= TRUNC(ADD_MONTHS(SYSDATE, -12), 'MM')).
-- Includes only documents identified as transfer-evaluation related based on routing status (fieldid 35) being one of the configured transfer evaluation steps (including values such as End, RES Undergrad Transfer Evaluation, LUO UG Transfer Evaluation, GR Transfer Evaluation, Military Transcripts/Credit Granting Test Scores, Unofficial Transfer Evaluation, Content Competencies, Credit Granting Score, and Imported to TRIP).
-- Excludes documents marked as duplicate completions (removes any document with a WorkQueueLogs record of type "Duplicate Completion").
-- Excludes documents that have been deleted (removes any document found in the RecycleBin).
-- Includes only documents that exist in catalog 7 (restricts to NODE records where CATALOGID = 7).
-- Student identifier (LUID) and student name are derived from eTrieve field values linked through the party/version relationship for fieldid 15, using specific fieldids (first name=2, middle name=3, last name=4, DOB=56, LUID=11).
-- SBGI code is pulled when available from document field values where fieldid = 34; if not present, SBGI may be null.
-- Produces exactly one staging row per document by grouping on DOCUMENTID and taking the maximum available field values for each required student attribute and SBGI code.
-- Determines the "last routing status" as the most recent routing-status change (fieldid 35) among the configured routing values, per document (keeps the highest AUDITDATETIME using a ranking rule).
-- Determines the "first routing status" as the earliest routing-status change (fieldid 35) recorded for the document (keeps the lowest AUDITDATETIME using a ranking rule).
-- Determines the current evaluation status from the most recent evaluation-status change (fieldid 64) per document; if no evaluation status exists, it defaults to "New" (unless completed).
-- Marks a document as Complete only when the last routing status is "End"; otherwise the status is the current evaluation status (or "New" if missing).
-- Sets COMPLETE_DATE only when the last routing status is "End"; otherwise COMPLETE_DATE is null.
-- Captures ASSIGNED_TO for routing events from the audit USERNAME value (normalized to upper-case and with "@liberty.edu" removed when present).
-- Captures the assignment owner and assigned date from the most recent WorkQueueLogs entry of type "Assignment" or "Reassignment", parsing the log comment to extract the user and using the log timestamp as the assignment date.
-- Calculates routed-to-complete turnaround (ROUTED_TO_END) only for completed items (last routing status = "End"), expressed in hours and adjusted to remove weekend time using an ISO-week (Monday-based) weekday calculation; if completion occurs on a weekend, it adds back the portion of that final weekend from Friday to the completion timestamp.
-- Calculates assigned-to-complete turnaround (ASSIGNED_TO_END) only for completed items, expressed in hours and adjusted to remove weekend time using the same weekday-only logic but starting from the assigned date.
-- Derives day-of-week labels for routed, assigned, and complete events from their timestamps; complete day is populated only for completed items.
-- Calculates alternate turnaround measures that exclude weekends without adding any weekend portion (ROUTED_TO_END_NO_WKND and ASSIGNED_TO_END_NO_WKND) only when both the start day and end day are not Saturday or Sunday; otherwise these fields are null.
-- Stamps each staging row with the ETL run timestamp (ETL_DATE) and stamps WH_ETL_DATE using the maximum available ETL timestamp from the eTrieve document source, converted to America/New_York.
-- Builds the Tableau table by joining staging rows to the current person record in SPRIDEN (matches SPRIDEN_ID = LUID and requires SPRIDEN_CHANGE_IND is null).
-- Derives PROGRAM for Tableau using the most recent SGBSTDN record by effective term when available; otherwise uses the application program from ZSAVAPPL (PROGRAM = NVL(SGBSTDN_PROGRAM_1, ZSAVAPPL_PROGRAM)).
-- Uses only non-withdrawn applications from ZSAVAPPL (APST_CODE <> 'W') and selects the top-ranked application (RANK = 1) with the highest application number for that PIDM among non-withdrawn applications.
-- Excludes records from the Tableau output when LAST_ROUT is "Docs with no active app" or "Duplicate".
-- Excludes records from the Tableau output when DOC_TYPE is one of the explicitly excluded document types (State Teaching License, DD 214 Discharge Papers, Elementary School Record - Preliminary, Elementary School Record - Unofficial).
-- Populates the Tableau URL field using the document’s node identifiers (CATALOGID and NODEID) and DOCUMENTID via UTL_D_AIM.GET_ETRIEVE_URL; if node information is missing, URL may be null.
-- Sets ACTIVITY_DATE in the Tableau table to the ETL run timestamp for consistent refresh tracking.
--
-- URL: https://reports.liberty.edu/#/site/Registrar/workbooks/3854/views
--
--DECLARE
--- PARAMS
v_etl_date    DATE := SYSDATE;
v_msg         VARCHAR2(2000);
v_instance    VARCHAR2(50) := upper('ALL'); -- inst from the jams job; used for determining instance
v_partition   NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_mod         NUMBER := 5; -- number of partitions to be created
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_aim_traneval_sd_mod';
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
v_msg     := 'START - ' || v_instance || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
utl_d_aim.truncate_table(v_table_name => 'traneval_sd');
INSERT /*+*/
INTO utl_d_aim.traneval_sd
(luid,
 stu_name,
 documentid,
 sbgi_code,
 doc_type,
 assigned_to,
 routed_date,
 assigned_date,
 complete_date,
 first_rout,
 last_rout,
 status,
 routed_to_end,
 assigned_to_end,
 etl_date,
 routed_day,
 assigned_day,
 complete_day,
 routed_to_end_no_wknd,
 assigned_to_end_no_wknd,
 wh_etl_date)
WITH transfer_eval AS
 (SELECT doc.documentid,
         documenttype.documenttypeid,
         documenttype.name AS doc_type,
         MAX(CASE
             WHEN fv.fieldid = 2 THEN
              fv.text
             END) AS first_name,
         MAX(CASE
             WHEN fv.fieldid = 3 THEN
              fv.text
             END) AS middle_name,
         MAX(CASE
             WHEN fv.fieldid = 4 THEN
              fv.text
             END) AS last_name,
         MAX(CASE
             WHEN fv.fieldid = 56 THEN
              fv.text
             END) AS dob,
         MAX(CASE
             WHEN fv.fieldid = 11 THEN
              fv.text
             END) AS luid,
         MAX(sbgi.sbgi_code) AS sbgi_code
    FROM etrieve.documenttype documenttype
    JOIN etrieve.document doc
      ON documenttype.documenttypeid = doc.documenttypeid
     AND documenttype.name IS NOT NULL
     AND documenttype.name NOT LIKE 'z%'
    JOIN (SELECT DISTINCT d.documentid
           FROM etrieve.document d
           JOIN etrieve.workqueueassignment wqa
             ON wqa.documentid = d.documentid
           JOIN etrieve.auditdocument ad
             ON ad.auditdocumentid = d.documentid
           JOIN etrieve."AUDIT" a
             ON a.auditid = ad.auditid
            AND a.auditdatetime >= trunc(add_months(SYSDATE, -12), 'MM') --Feb 2026 → Feb 1, 2025
           JOIN etrieve.auditdocumentfield adf
             ON adf.auditid = ad.auditid
            AND adf.fieldid = 35 --  RO evaluations only
            AND adf.newvalue IN
                ('End', 'RES Undergrad Transfer Evaluation', 'Military Transcripts/ Credit Granting Test Scores', 'GR Transfer Evaluation', 'LUO UG Transfer Evaluation', 'Credit Granting Score', 'Unofficial Transfer Evaluation', 'Content Competencies', 'Imported to TRIP')
           LEFT JOIN etrieve.workqueuelogs wqld
             ON wqld.documentid = d.documentid
            AND wqld.type = 'Duplicate Completion'
           LEFT JOIN etrieve.recyclebin rb
             ON rb.documentid = d.documentid
          WHERE 1 = 1
            AND wqld.documentid IS NULL -- REMOVE DUPLICATES
            AND rb.documentid IS NULL -- REMOVE DELETES
         ) ro
      ON ro.documentid = doc.documentid
    JOIN etrieve.node
      ON doc.documentid = node.documentid
     AND node.catalogid = 7
    JOIN etrieve.documentfieldpartyversion documentfieldpartyversion
      ON doc.documentid = documentfieldpartyversion.documentid
     AND documentfieldpartyversion.fieldid = 15
  -- get the student info
    LEFT JOIN etrieve.partyversion partyversion
      ON documentfieldpartyversion.partyversionid = partyversion.partyversionid
    LEFT JOIN etrieve.partyversionfieldvalue ivpartystudentid
      ON documentfieldpartyversion.partyversionid = ivpartystudentid.partyversionid
    LEFT JOIN etrieve.fieldvalue fv
      ON fv.fieldvalueid = ivpartystudentid.fieldvalueid
  -- get the SBGI code
    LEFT JOIN (SELECT dfv.documentid,
                     fvsc.text AS sbgi_code
                FROM etrieve.documentfieldvalue dfv
                JOIN etrieve.fieldvalue fvsc
                  ON fvsc.fieldvalueid = dfv.fieldvalueid
                 AND fvsc.fieldid = 34 --SBGI field
              --                  AND MOD(dfv.documentid, v_mod) = v_partition
              ) sbgi
      ON sbgi.documentid = doc.documentid
   WHERE 1 = 1
   GROUP BY doc.documentid,
            documenttype.documenttypeid,
            documenttype.name)
SELECT luid,
       nullif(transfer_eval.last_name || ', ' || transfer_eval.first_name, ', ') AS stu_name,
       transfer_eval.documentid,
       transfer_eval.sbgi_code,
       transfer_eval.doc_type,
       assignment.assigned_to,
       last_route.auditdatetime AS routed_date,
       assignment.assigned_date,
       CASE
       WHEN last_route.routing_status = 'End' THEN
        last_route.auditdatetime
       END AS complete_date,
       first_route.routing_status AS first_rout,
       last_route.routing_status AS last_rout,
       CASE
       WHEN last_route.routing_status = 'End' THEN
        'Complete'
       ELSE
        nvl(eval_status.evaluation_status, 'New') -- sometimes, we do not find anything for this, it must exist elsewhere in the database than here?
       END AS status,
       CASE
       WHEN last_route.routing_status = 'End' THEN
        round(((trunc(last_route.auditdatetime, 'IW') - trunc(first_route.auditdatetime, 'IW')) * 5 / 7 --number of weeks * weekdays (removing all weekends)
              + least(last_route.auditdatetime - trunc(last_route.auditdatetime, 'IW'), 5) --if end date > friday then 5 otherwise use the decimal of days since last monday
              - least(first_route.auditdatetime - trunc(first_route.auditdatetime, 'IW'), 5) --if start date > friday then 5 otherwise use the decimal of days since last monday
              + CASE
              WHEN TRIM(to_char(last_route.auditdatetime, 'day')) IN ('sunday', 'saturday') --adding the latest weekend if completed on a weekend
               THEN
               last_route.auditdatetime - greatest((trunc(last_route.auditdatetime, 'IW') + 5), first_route.auditdatetime)
              ELSE
               0
              END) * 24, 1)
       ELSE
        NULL
       END AS routed_to_end,
       CASE
       WHEN last_route.routing_status = 'End' THEN
        round(((trunc(last_route.auditdatetime, 'IW') - trunc(assignment.assigned_date, 'IW')) * 5 / 7 --number of weeks * weekdays (removing all weekends)
              + least(last_route.auditdatetime - trunc(last_route.auditdatetime, 'IW'), 5) --if end date > friday then 5 otherwise use the decimal of days since last monday
              - least(assignment.assigned_date - trunc(assignment.assigned_date, 'IW'), 5) --if start date > friday then 5 otherwise use the decimal of days since last monday
              + CASE
              WHEN TRIM(to_char(last_route.auditdatetime, 'day')) IN ('sunday', 'saturday') --this is adding the latest weekend if completed on a weekend
               THEN
               last_route.auditdatetime - greatest((trunc(last_route.auditdatetime, 'IW') + 5), assignment.assigned_date)
              ELSE
               0
              END) * 24, 1)
       ELSE
        NULL
       END AS assigned_to_end,
       v_etl_date AS tl_date,
       TRIM(to_char(first_route.auditdatetime, 'Day')) AS routed_day,
       TRIM(to_char(assignment.assigned_date, 'Day')) AS assigned_day,
       CASE
       WHEN last_route.routing_status = 'End' THEN
        TRIM(to_char(last_route.auditdatetime, 'Day'))
       ELSE
        NULL
       END AS complete_day,
       CASE
       WHEN last_route.routing_status = 'End'
            AND TRIM(to_char(first_route.auditdatetime, 'Day')) NOT IN ('Saturday', 'Sunday')
            AND TRIM(to_char(last_route.auditdatetime, 'Day')) NOT IN ('Saturday', 'Sunday') THEN
        round(((trunc(last_route.auditdatetime, 'IW') - trunc(first_route.auditdatetime, 'IW')) * 5 / 7 --number of weeks * weekdays (removing all weekends)
              + least(last_route.auditdatetime - trunc(last_route.auditdatetime, 'IW'), 5) --if end date > friday then 5 otherwise use the decimal of days since last monday
              - least(first_route.auditdatetime - trunc(first_route.auditdatetime, 'IW'), 5) --if start date > friday then 5 otherwise use the decimal of days since last monday
              ) * 24, 1)
       END AS routed_to_end_no_wknd,
       CASE
       WHEN last_route.routing_status = 'End'
            AND TRIM(to_char(assignment.assigned_date, 'Day')) NOT IN ('Saturday', 'Sunday')
            AND TRIM(to_char(last_route.auditdatetime, 'Day')) NOT IN ('Saturday', 'Sunday') THEN
        round(((trunc(last_route.auditdatetime, 'IW') - trunc(assignment.assigned_date, 'IW')) * 5 / 7 --number of weeks * weekdays (removing all weekends)
              + least(last_route.auditdatetime - trunc(last_route.auditdatetime, 'IW'), 5) --if end date > friday then 5 otherwise use the decimal of days since last monday
              - least(assignment.assigned_date - trunc(assignment.assigned_date, 'IW'), 5) --if start date > friday then 5 otherwise use the decimal of days since last monday
              ) * 24, 1)
       END AS assigned_to_end_no_wknd,
       (SELECT CAST(from_tz(CAST(MAX(last_dttm) AS TIMESTAMP), 'America/New_York') at TIME ZONE 'America/New_York' AS DATE) AS est FROM etrieve.document) AS v_wh_etl_date
  FROM transfer_eval
-- CURRENT evaluation status; ranking returns current step in the process
  JOIN (SELECT ad2.auditdocumentid,
               adf.newvalue AS routing_status,
               adf.fieldid,
               CAST(a.auditdatetime AS DATE) AS auditdatetime,
               upper(REPLACE(lower(dbms_lob.substr(a.username, 4000, 1)), '@liberty.edu', '')) AS assigned_to,
               rank() over(PARTITION BY ad2.auditdocumentid ORDER BY a.auditdatetime DESC, rownum) ranking
          FROM etrieve.auditdocument ad2
          JOIN transfer_eval
            ON transfer_eval.documentid = ad2.auditdocumentid
          JOIN etrieve."AUDIT" a
            ON a.auditid = ad2.auditid
          JOIN etrieve.auditdocumentfield adf
            ON adf.auditid = ad2.auditid
           AND adf.fieldid IN (35) -- routing status; limit to the following values...
           AND adf.newvalue IN ('End', 'GR Transfer Evaluation', 'LUO UG Transfer Evaluation', 'Military Transcripts/ Credit Granting Test Scores', 'RES Undergrad Transfer Evaluation', 'Unofficial Transfer Evaluation', 'Imported to TRIP')) last_route
    ON transfer_eval.documentid = last_route.auditdocumentid
   AND last_route.ranking = 1
-- FIRST evaluation status; ranking returns 1st step in the process; any/all status
  LEFT JOIN (SELECT ad2.auditdocumentid,
                    adf.newvalue AS routing_status,
                    adf.fieldid,
                    CAST(a.auditdatetime AS DATE) AS auditdatetime,
                    upper(REPLACE(lower(dbms_lob.substr(a.username, 4000, 1)), '@liberty.edu', '')) AS assigned_to,
                    rank() over(PARTITION BY ad2.auditdocumentid ORDER BY a.auditdatetime ASC, rownum) ranking
               FROM etrieve.auditdocument ad2
               JOIN transfer_eval
                 ON transfer_eval.documentid = ad2.auditdocumentid
               JOIN etrieve."AUDIT" a
                 ON a.auditid = ad2.auditid
               JOIN etrieve.auditdocumentfield adf
                 ON adf.auditid = ad2.auditid
                AND adf.fieldid IN (35) -- routing status
             ) first_route
    ON transfer_eval.documentid = first_route.auditdocumentid
   AND first_route.ranking = 1
-- get evaluation status
  LEFT JOIN (SELECT ad2.auditdocumentid AS documentid,
                    adf.fieldid,
                    adf.newvalue AS evaluation_status,
                    rank() over(PARTITION BY ad2.auditdocumentid ORDER BY a.auditdatetime DESC, rownum) ranking
               FROM etrieve.auditdocument ad2
               JOIN transfer_eval
                 ON transfer_eval.documentid = ad2.auditdocumentid
               JOIN etrieve."AUDIT" a
                 ON a.auditid = ad2.auditid
               JOIN etrieve.auditdocumentfield adf
                 ON adf.auditid = ad2.auditid
                AND adf.fieldid IN (64) --eval status
             ) eval_status
    ON transfer_eval.documentid = eval_status.documentid
   AND eval_status.ranking = 1
-- get assignment date - last time it was assigned; it must be assigned lest it gets igored on the reports
  LEFT JOIN (SELECT wqla.documentid,
                    regexp_substr(regexp_replace(to_char(regexp_substr(wqla."COMMENT", 'to( user)?( \d*)? \w*(@liberty.edu)?')), 'user|to|@liberty.edu'), '\w+$') AS assigned_to,
                    CAST(to_timestamp(wqla.timestamp, 'MM/DD/YYYY HH:MI:SS AM') AS DATE) AS assigned_date,
                    rank() over(PARTITION BY wqla.documentid ORDER BY nvl2(regexp_substr(regexp_replace(to_char(regexp_substr(wqla."COMMENT", 'to( user)?( \d*)? \w*(@liberty.edu)?')), 'user|to|@liberty.edu'), '\w+$'), 1, 2) ASC, CAST(to_timestamp(wqla.timestamp, 'MM/DD/YYYY HH:MI:SS AM') AS DATE) DESC /*asc*/, rownum) ranking --for the most recent update, took out DESC for ASC
               FROM etrieve.workqueuelogs wqla
               JOIN transfer_eval
                 ON transfer_eval.documentid = wqla.documentid
              WHERE 1 = 1
                AND wqla."TYPE" IN ('Assignment', 'Reassignment')) assignment
    ON transfer_eval.documentid = assignment.documentid
   AND assignment.ranking = 1;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
utl_d_aim.truncate_table(v_table_name => 'traneval_tableau');
INSERT /*+*/
INTO utl_d_aim.traneval_tableau
(routed_date,
 assigned_to,
 doc_type,
 last_rout,
 luid,
 stu_name,
 sbgi_code,
 program,
 status,
 documentid,
 url,
 assigned_date,
 complete_date,
 first_rout,
 routed_to_end,
 assigned_to_end,
 routed_day,
 assigned_day,
 complete_day,
 routed_to_end_no_wknd,
 assigned_to_end_no_wknd,
 activity_date)
SELECT tran.routed_date,
       tran.assigned_to,
       tran.doc_type,
       tran.last_rout,
       tran.luid,
       tran.stu_name,
       tran.sbgi_code,
       nvl(sgb.sgbstdn_program_1, a.zsavappl_program) program,
       tran.status,
       tran.documentid,
       utl_d_aim.get_etrieve_url(n.catalogid, n.nodeid, tran.documentid) AS url,
       tran.assigned_date, -- only in tableau
       tran.complete_date, -- only in tableau
       tran.first_rout, -- only in tableau
       tran.routed_to_end, -- only in tableau
       tran.assigned_to_end, -- only in tableau
       tran.routed_day, -- only in tableau
       tran.assigned_day, -- only in tableau
       tran.complete_day, -- only in tableau
       tran.routed_to_end_no_wknd, -- only in tableau
       tran.assigned_to_end_no_wknd, -- only in tableau
       v_etl_date AS activity_date
  FROM utl_d_aim.traneval_sd tran
  LEFT JOIN etrieve.node n
    ON n.documentid = tran.documentid
  JOIN spriden
    ON spriden_id = tran.luid
   AND spriden_change_ind IS NULL
  LEFT JOIN zexec.zsavappl a
    ON a.zsavappl_pidm = spriden_pidm
   AND a.zsavappl_apst_code <> 'W'
   AND a.zsavappl_rank = 1
   AND a.zsavappl_appl_no = (SELECT MAX(a2.zsavappl_appl_no)
                               FROM zexec.zsavappl a2
                              WHERE a2.zsavappl_pidm = a.zsavappl_pidm
                                AND a2.zsavappl_apst_code <> 'W')
  LEFT JOIN sgbstdn sgb
    ON sgb.sgbstdn_pidm = spriden_pidm
   AND sgb.sgbstdn_term_code_eff = (SELECT MAX(sgb2.sgbstdn_term_code_eff) FROM sgbstdn sgb2 WHERE sgb.sgbstdn_pidm = sgb2.sgbstdn_pidm)
 WHERE 1 = 1
   AND tran.last_rout NOT IN ('Docs with no active app', 'Duplicate') -- exlcuded in BOTH argos and the tableau dashboard
   AND tran.doc_type NOT IN ('State Teaching License', 'DD 214 Discharge Papers', --  -- exlcuded in BOTH argos and the tableau dashboard
                             'Elementary School Record - Preliminary', 'Elementary School Record - Unofficial' -- exlcuded in BOTH argos and the tableau dashboard
                             );
v_count := SQL%ROWCOUNT;
COMMIT;
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count); -- leave this here to log the delete from above (it will cause a commit)
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
utl_d_aim.truncate_table(v_table_name => 'traneval_sd'); -- we need to truncate this table because it is only a staging
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
-- log any errors
EXCEPTION
WHEN OTHERS THEN
utl_d_aim.truncate_table(v_table_name => 'traneval_sd');
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
END etl_aim_traneval_sd_mod;

procedure etl_aim_zsraacc_refresh (jobnumber number, processid varchar2, processname varchar2) is
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
v_proc        VARCHAR2(100) := 'etl_aim_zsraacc_refresh';
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
v_msg     := 'START at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
INSERT INTO utl_d_aim.zsracdc
SELECT spriden.spriden_pidm pidm,
       qu.ans,
       SYSDATE              activity_date
  FROM spriden
  JOIN (SELECT DISTINCT esan.szresan_short_ans   ans,
                        sub.szbsubm_id           base_id,
                        sub.szbsubm_created_date st_date,
                        sub.szbsubm_pidm         pidm
          FROM zraft.szrfgin f
          JOIN zraft.szrgrps grp
            ON grp.szrgrps_form_id = f.szrfgin_form_id
          JOIN zraft.szrqest qest
            ON ((grp.szrgrps_id = qest.szrqest_group_id) OR (grp.szrgrps_group_type = 'GO'))
          JOIN zraft.szbsubm sub
            ON sub.szbsubm_szrfrms_id = f.szrfgin_form_id
           AND sub.szbsubm_locked = 1
           AND ((sub.szbsubm_szrgrps_id = qest.szrqest_group_id) OR (grp.szrgrps_group_type = 'GO'))
          JOIN zraft.szresan esan
            ON esan.szresan_question_id = qest.szrqest_id
           AND esan.szresan_szbsubm_id = sub.szbsubm_id
           AND esan.szresan_to_date IS NULL
         WHERE qest.szrqest_to_date IS NULL
           AND esan.szresan_short_ans = 'Y'
           AND f.szrfgin_form_id = 1121
           AND (qest.szrqest_q_type = 'YN' AND esan.szresan_to_date IS NULL)) qu
    ON qu.pidm = spriden_pidm
  LEFT JOIN (SELECT DISTINCT zsracdc.pidm,
                             zsracdc.response
               FROM utl_d_aim.zsracdc
              WHERE zsracdc.activity_date = (SELECT MAX(d.activity_date) FROM utl_d_aim.zsracdc d WHERE d.pidm = zsracdc.pidm)) prev
    ON prev.pidm = spriden_pidm
   AND prev.response = qu.ans
 WHERE prev.pidm IS NULL
   AND spriden_change_ind IS NULL;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
INSERT INTO utl_d_aim.zsraacc
SELECT DISTINCT spriden.spriden_pidm pidm,
                spriden.spriden_id luid,
                spriden.spriden_last_name last_name,
                spriden.spriden_first_name first_name,
                zsavaddr.street_line1 address1,
                zsavaddr.street_line2 address2,
                zsavaddr.city city,
                zsavaddr.stat_code stat,
                zsavaddr.zip5 zip_code,
                stvnatn_nation country,
                nvl2(aprexcl.aprexcl_pidm, 'DNC', zsavtele.phone_combo) phone_number,
                se.lu_email email_address,
                s.course || '-' || s.sect course,
                s.term_code || CASE
                WHEN s.camp_code = 'D' THEN
                 substr(s.ptrm_code, 2, 2)
                ELSE
                 s.ptrm_code
                END term,
                s.ptrm_end completion_date,
                CASE
                WHEN s.course = 'CCOU201' THEN
                 'Intro to Christian Counseling'
                WHEN s.course = 'CCOU202' THEN
                 'Issues of Christian Counseling'
                WHEN s.course = 'CCOU301' THEN
                 'Chr Coun for Marriage & Family'
                WHEN s.course = 'CCOU302' THEN
                 'Christian Coun for Children'
                WHEN s.course = 'CCOU304' THEN
                 'Christian Coun for Women'
                WHEN s.course = 'CCOU305' THEN
                 'Issues in Human Sexuality'
                WHEN s.course = 'CRIS302' THEN
                 'Found Prin of Crisis Response'
                WHEN s.course = 'CRIS303' THEN
                 'Acute Stress, Grief, & Trauma'
                WHEN s.course = 'CRIS304' THEN
                 'PTSD & Combat Related Trauma'
                WHEN s.course = 'CRIS305' THEN
                 'Trauma Assessment & Intervent'
                WHEN s.course = 'CRIS306' THEN
                 'Complex Trauma & Disasters'
                WHEN s.course = 'CRIS605' THEN
                 'Crisis & 1st Responder Skills'
                WHEN s.course = 'CRIS606' THEN
                 'Acute Stress, Grief & Trauma'
                WHEN s.course = 'CRIS607' THEN
                 'PTSD & Combat Related Trauma'
                WHEN s.course = 'CRIS608' THEN
                 'Trauma Assessment & Interventn'
                WHEN s.course = 'CRIS609' THEN
                 'Complex Trauma & Disasters'
                WHEN s.course = 'LIFC201' THEN
                 'Introduction to Life Coaching'
                WHEN s.course = 'LIFC202' THEN
                 'Advanced Skills Life Coaching'
                WHEN s.course = 'LIFC301' THEN
                 'Health & Wellness Coaching'
                WHEN s.course = 'LIFC302' THEN
                 'Marriage Coaching'
                WHEN s.course = 'LIFC303' THEN
                 'Financial Life Coaching'
                WHEN s.course = 'LIFC304' THEN
                 'Leadership Prof Life Coaching'
                WHEN s.course = 'LIFC501' THEN
                 'Introduction to Life Coaching'
                WHEN s.course = 'LIFC502' THEN
                 'Advanced Life Coaching Skills'
                WHEN s.course = 'LIFC601' THEN
                 'Health and Wellness Coaching'
                WHEN s.course = 'LIFC602' THEN
                 'Marriage Coaching'
                WHEN s.course = 'LIFC603' THEN
                 'Financial Life Coaching'
                WHEN s.course = 'LIFC604' THEN
                 'Leadership Prof Life Coaching'
                WHEN s.course = 'PSYC307' THEN
                 'Treatment and Recovery'
                WHEN s.course = 'PSYC308' THEN
                 'Diag & Treatment Sex Addiction'
                WHEN s.course = 'PSYC309' THEN
                 'Healthy Sexuality'
                WHEN s.course = 'SUBS606' THEN
                 'Biol Aspects Addiction/Recovry'
                WHEN s.course = 'SUBS607' THEN
                 'Treatment and Recovery Process'
                WHEN s.course = 'SUBS608' THEN
                 'Diag & Treatment Sexual Addctn'
                WHEN s.course = 'SUBS609' THEN
                 'Healthy Sexuality'
                END scbcrse_title,
                s.subj || s.numb ccheck,
                SYSDATE senddate
  FROM saturn.spriden spriden
 INNER JOIN utl_d_aim.szrcrse s
    ON s.pidm = spriden.spriden_pidm
   AND spriden.spriden_change_ind IS NULL
   AND s.term_code >= '201240'
   AND s.course IN
       ('CCOU201', 'CCOU202', 'CCOU301', 'CCOU302', 'CCOU304', 'CCOU305', 'CRIS302', 'CRIS303', 'CRIS304', 'CRIS305', 'CRIS306', 'CRIS605', 'CRIS606', 'CRIS607', 'CRIS608', 'CRIS609', 'LIFC201', 'LIFC202', 'LIFC301', 'LIFC302', 'LIFC303', 'LIFC304', 'LIFC501', 'LIFC502', 'LIFC601', 'LIFC602', 'LIFC603', 'LIFC604', 'PSYC307', 'PSYC308', 'PSYC309', 'SUBS606', 'SUBS607', 'SUBS608', 'SUBS609')
   AND s.final_grade IN ('A', 'A-', 'B+', 'B', 'B-', 'C+', 'C', 'C-', 'D+', 'D', 'D-', 'P')
 INNER JOIN utl_d_aim.szrenrl se
    ON se.pidm = s.pidm
   AND se.term_code = s.term_code
  JOIN zsaturn.szrlevl l
    ON l.szrlevl_levl_code = se.levl_code
   AND l.szrlevl_is_univ = 'Y'
   AND l.szrlevl_has_awardable_cred = 'Y'
 INNER JOIN spbpers spbpers
    ON spbpers.spbpers_pidm = spriden.spriden_pidm
   AND spbpers.spbpers_dead_ind IS NULL
 INNER JOIN utl_d_aim.zsracdc
    ON spriden.spriden_pidm = zsracdc.pidm
   AND zsracdc.response = 'Y'
   AND zsracdc.activity_date = (SELECT MAX(x.activity_date) -- most recent opt in response is yes
                                  FROM utl_d_aim.zsracdc x
                                 WHERE x.pidm = zsracdc.pidm)
  LEFT JOIN zexec.zsavaddr zsavaddr
    ON zsavaddr.pidm = spriden.spriden_pidm
   AND zsavaddr.addr_rank = '1'
  LEFT JOIN zexec.zsavtele zsavtele
    ON spriden.spriden_pidm = zsavtele.pidm
   AND zsavtele.tele_us_valid_rank = 1
   AND zsavtele.tele_rank = 1
   AND zsavtele.stp_date IS NULL
   AND zsavtele.phone_combo IS NOT NULL
   AND length(zsavtele.phone_combo) = 10
  LEFT JOIN alumni.aprexcl aprexcl
    ON spriden.spriden_pidm = aprexcl.aprexcl_pidm
   AND aprexcl_excl_code IN ('A01', 'A02', 'P01')
   AND (aprexcl_end_date IS NULL OR aprexcl_end_date > SYSDATE)
  LEFT JOIN stvmajr stvmajr
    ON stvmajr.stvmajr_code = se.majr_code_1
  LEFT JOIN stvnatn
    ON stvnatn_code = nvl(zsavaddr.natn_code, CASE
                           WHEN zsavaddr.stat_code IN
                                ('AL', 'AK', 'AZ', 'AR', 'CA', 'CO', 'CT', 'DC', 'DE', 'FL', 'GA', 'HI', 'ID', 'IL', 'IN', 'IA', 'KS', 'KY', 'LA', 'ME', 'MD', 'MA', 'MI', 'MN', 'MS', 'MO', 'MT', 'NE', 'NV', 'NJ', 'NM', 'NY', 'NC', 'ND', 'OH', 'OK', 'OR', 'PA', 'RI', 'NH', 'SC', 'SD', 'TN', 'TX', 'UT', 'VT', 'VA', 'WA', 'WV', 'WI', 'WY') THEN
                            'US'
                           END)
  LEFT JOIN utl_d_aim.zsraacc
    ON zsraacc.pidm = spriden.spriden_pidm
   AND zsraacc.ccheck = s.course
 WHERE 1 = 1
   AND zsraacc.pidm IS NULL; -- exclude records that have already been inserted/sent to AACC
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- setting seed record to keep table up-to-date
MERGE INTO utl_d_aim.zsracdc tgt
USING (SELECT -999 AS pidm FROM dual) src
ON (tgt.pidm = src.pidm)
WHEN MATCHED THEN
UPDATE
   SET tgt.response      = 'N',
       tgt.activity_date = SYSDATE
WHEN NOT MATCHED THEN
INSERT
(pidm,
 response,
 activity_date)
VALUES
(src.pidm,
 'N',
 SYSDATE);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
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
/*--------------------------------------------change log----------------------------------------
version    date        username       updates
-- 06-23-2020     smmatulionis   --initial release
-- 05-17-2023     wgriffith2  --Dealing with EM courses and updating code to use job_log
-- 20250918         wgriffith2      --MERGE statement added setting seed record to keep table up-to-date
------------------------------------------------------------------------------------------------*/
END etl_aim_zsraacc_refresh;

procedure etl_aim_ffd_faculty (jobnumber number, processid varchar2, processname varchar2) is
--
-- PURPOSE: Builds a term-specific roster of instructional faculty with campus, college/department, teaching level, credit/load hours, contract status, and terminal-degree flags to support staffing, budgeting, accreditation, and executive reporting.
--
-- TABLE: utl_d_aim.ffd_faculty
--
-- UNIQUE INDEX: TERM, PIDM
--
-- CONDITIONS:
-- Processes data one qualifying academic term at a time, iterating over LMS terms that are ACTIVE, have enrollment > 0, belong to groups STD or MED, and are in instance L2CAN.
-- Refreshes the target term by deleting existing rows for that TERM and inserting the newly computed faculty records for that same TERM.
-- Includes only individuals present in the active faculty/staff population and EXCLUDES graduate assistants (empclassid = 'G').
-- Includes a person only if they either have enrollment-bearing teaching activity OR have instructional load/pay records for the TERM.
-- Course-based measures consider ONLY sections with student enrollment that counts toward section enrollment (i.e., only enrollment statuses that include section enrollment).
-- Course-based measures EXCLUDE sections with subject code 'NEWS'.
-- Course-based measures include ONLY university-level coursework that carries awardable institutional credit.
-- Course-based measures use the PRIMARY instructor assignment on sections.
-- Course-based hours and department selection focus on FALL semester offerings tied to the processed TERM.
-- Credit hours per section use the section’s credit hours; if missing, use the catalog’s range and treat 1–6 variable-credit courses as 3 credits.
-- For online-designated (“B”) catalog variants, use the online catalog record when applicable to determine credits and attributes.
-- Determines course-based level (UG vs. GR) per section as GR if the college is designated graduate-only (e.g., OM or LW) or course numbering/metadata indicates GR; UG if numbering indicates UG; if an instructor teaches both UG and GR, the instructor’s course-based level for the TERM is GR.
-- Computes total credit hours taught for the TERM (fall_hours) and splits by campus: Residential (R) as fall_res_hours
--
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
v_proc        VARCHAR2(100) := 'etl_aim_ffd_faculty';
TYPE t_fac IS TABLE OF utl_d_aim.ffd_faculty%ROWTYPE;
l_fac t_fac;
CURSOR c_terms IS
SELECT DISTINCT ll.term_code
  FROM zbtm.terms_by_group_v t
  JOIN utl_d_lms.lms_link ll
    ON ll.term_code = t.term_code
 WHERE 1 = 1
   AND ll.status = 'active'
   AND ll.enrollment > 0
   AND ll.instance = 'L2CAN'
   AND t.group_code IN ('STD', 'MED')
 GROUP BY ll.term_code,
          ll.ptrm_code
 ORDER BY term_code DESC;
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
DELETE FROM utl_d_aim.ffd_faculty WHERE term = rec.term_code;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'DELETE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
SELECT DISTINCT rec.term_code AS term_code,
                spriden_pidm AS pidm,
                spriden_id AS luid,
                spriden_last_name AS last_name,
                spriden_first_name AS first_name,
                contracts.szrfcrf_contract_type AS status,
                coalesce(contracts.szrfcrf_contract_rule, 'ADJNCT') AS status_rule,
                coalesce(contracts.szrfcrf_req_hours, 0) AS contract_hours,
                CASE
                WHEN contracts.szrfcrf_campus IN ('D', 'R') THEN
                 contracts.szrfcrf_campus
                WHEN coalesce(fpay.r_credit_hours, fall_res_hrs, 0) >= coalesce(fpay.d_credit_hours, fall_luo_hrs, 0) THEN
                 'R'
                WHEN coalesce(fpay.d_credit_hours, fall_luo_hrs, 0) >= coalesce(fpay.r_credit_hours, fall_res_hrs, 0) THEN
                 'D'
                WHEN fpay.r_load_hours >= nvl(fpay.d_load_hours, 0) THEN
                 'R'
                WHEN fpay.d_load_hours >= nvl(fpay.r_load_hours, 0) THEN
                 'D'
                END AS hr_campus,
                contracts.szrfcrf_school AS hr_college,
                hier.hierarchy_campus,
                hier.hierarchy_college,
                hier.hierarchy_department,
                hier.hierarchy_level,
                crse.crse_campus,
                crse.crse_college,
                crse.crse_department,
                crse.crse_level,
                coalesce(fpay.tot_load_hours, 0) AS fall_load_hours,
                coalesce(fpay.tot_credit_hours, hours.fall_hours, 0) AS fall_hours,
                coalesce(fpay.d_credit_hours, fall_luo_hrs, 0) AS fall_luo_hours,
                coalesce(fpay.r_credit_hours, fall_res_hrs, 0) AS fall_res_hours,
                CASE
                WHEN TRIM(upper(coalesce(contracts.szrfcrf_contract_rule, 'AJ'))) != 'AJ' THEN
                 'F'
                ELSE
                 'P'
                END faculty_type,
                CASE
                WHEN TRIM(upper(coalesce(contracts.szrfcrf_contract_rule, 'AJ'))) != 'AJ' THEN
                 'F'
                WHEN coalesce(crse.crse_level, hier.hierarchy_level, 'UG') = 'UG'
                     AND coalesce(fpay.tot_credit_hours, hours.fall_hours, 0) >= 12 THEN
                 'F'
                WHEN nvl(crse.crse_level, hier.hierarchy_level) = 'GR'
                     AND coalesce(fpay.tot_credit_hours, hours.fall_hours, 0) >= 9 THEN
                 'F'
                ELSE
                 'P'
                END faculty_type_by_level,
                coalesce(faculty.term_degree, 'N') AS is_terminal,
                coalesce(faculty.prioiritize_terminal, 'N') AS prioiritize_terminal
  BULK COLLECT
  INTO l_fac
  FROM saturn.spriden spridey
  LEFT JOIN zgeneral.activefacultystaff afs
    ON afs.empid = spridey.spriden_id
--contract data
  LEFT JOIN (SELECT DISTINCT f.szrfcrf_acyr,
                             f.szrfcrf_contract_type,
                             r.zfrlist_char_02,
                             f.szrfcrf_contract_rule,
                             r.zfrlist_char_04,
                             f.szrfcrf_req_hours,
                             f.szrfcrf_campus,
                             f.szrfcrf_contractee_pidm,
                             f.szrfcrf_id,
                             f.szrfcrf_school,
                             f.szrfcrf_department
               FROM zprovost.szrfcrf f
               LEFT JOIN zformdata.zfrlist r
                 ON r.zfrlist_list_code = 'FCRF_APEX_103_CONTRACT_RULE_MAP'
                AND r.zfrlist_active_yn = 'Y'
                AND f.szrfcrf_contract_type = r.zfrlist_char_01
                AND f.szrfcrf_contract_rule = r.zfrlist_char_03
               JOIN saturn.stvacyr acyr
                 ON acyr.stvacyr_code = f.szrfcrf_acyr
               JOIN saturn.stvterm trm
                 ON trm.stvterm_code = rec.term_code
                AND trm.stvterm_acyr_code = acyr.stvacyr_code
              WHERE f.szrfcrf_contractee_pidm IS NOT NULL
                AND f.szrfcrf_to_date = to_date('2099-12-31', 'YYYY-MM-DD')) contracts
    ON contracts.szrfcrf_contractee_pidm = spridey.spriden_pidm
-- load hours
  LEFT JOIN (SELECT facpay.zd_facpay_pidm,
                    SUM(CASE
                        WHEN facpay.zd_facpay_pay_camp_code = 'D' THEN
                         facpay.zd_facpay_load_hr
                        END) d_load_hours,
                    SUM(CASE
                        WHEN facpay.zd_facpay_pay_camp_code = 'R' THEN
                         facpay.zd_facpay_load_hr
                        END) r_load_hours,
                    SUM(facpay.zd_facpay_load_hr) tot_load_hours,
                    SUM(CASE
                        WHEN facpay.zd_facpay_pay_camp_code = 'D' THEN
                         facpay.zd_facpay_credit_hr
                        END) d_credit_hours,
                    SUM(CASE
                        WHEN facpay.zd_facpay_pay_camp_code = 'R' THEN
                         facpay.zd_facpay_credit_hr
                        END) r_credit_hours,
                    SUM(facpay.zd_facpay_credit_hr) tot_credit_hours,
                    SUM(CASE
                        WHEN facpay.zd_facpay_pay_camp_code = 'D' THEN
                         facpay.zd_facpay_ovrld_hr
                        END) d_overload_hours,
                    SUM(CASE
                        WHEN facpay.zd_facpay_pay_camp_code = 'R' THEN
                         facpay.zd_facpay_ovrld_hr
                        END) r_overload_hours,
                    SUM(facpay.zd_facpay_ovrld_hr) tot_overload_hours
               FROM zprovost.zd_facpay facpay
              WHERE facpay.zd_facpay_term_code = rec.term_code
                AND facpay.zd_facpay_nbp_ind IS NULL
                AND facpay.zd_facpay_data_origin != 'SZPFRLP'
                AND facpay.zd_facpay_enrollment > 0
              GROUP BY facpay.zd_facpay_pidm) fpay
    ON fpay.zd_facpay_pidm = spridey.spriden_pidm
-- credit hours
  LEFT JOIN (SELECT fac_id,
                    SUM(hrs) fall_hours,
                    SUM(CASE
                        WHEN crse_campus = 'D' THEN
                         hrs
                        END) fall_luo_hrs,
                    SUM(CASE
                        WHEN crse_campus = 'R' THEN
                         hrs
                        END) fall_res_hrs
               FROM (SELECT DISTINCT spriden_id fac_id,
                                     sfrstcr_crn,
                                     ssbsect_camp_code crse_campus,
                                     nvl(ssbsect_credit_hrs, CASE
                                          WHEN nvl(b.scbcrse_credit_hr_low, r.scbcrse_credit_hr_low) = 1
                                               AND nvl(b.scbcrse_credit_hr_high, r.scbcrse_credit_hr_high) = 6 THEN
                                           3
                                          ELSE
                                           nvl(b.scbcrse_credit_hr_low, r.scbcrse_credit_hr_low)
                                          END) hrs
                       FROM sfrstcr
                       JOIN stvrsts
                         ON stvrsts.stvrsts_code = sfrstcr.sfrstcr_rsts_code
                        AND stvrsts.stvrsts_incl_sect_enrl = 'Y'
                        AND sfrstcr_term_code = rec.term_code
                       JOIN zsaturn.szrlevl l
                         ON l.szrlevl_levl_code = sfrstcr_levl_code
                        AND l.szrlevl_is_univ = 'Y'
                        AND l.szrlevl_has_awardable_cred = 'Y'
                       JOIN ssbsect
                         ON ssbsect_term_code = sfrstcr_term_code
                        AND ssbsect_crn = sfrstcr_crn
                        AND ssbsect_subj_code <> 'NEWS'
                       JOIN sirasgn
                         ON sirasgn_crn = sfrstcr_crn
                        AND sirasgn.sirasgn_term_code = sfrstcr.sfrstcr_term_code
                        AND sirasgn.sirasgn_primary_ind = 'Y'
                       JOIN spriden
                         ON spriden_pidm = sirasgn_pidm
                        AND spriden_change_ind IS NULL
                       LEFT JOIN scbcrse b
                         ON b.scbcrse_subj_code = ssbsect_subj_code
                        AND b.scbcrse_crse_numb = ssbsect_crse_numb || 'B'
                        AND b.scbcrse_crse_numb LIKE '%B'
                        AND ssbsect_camp_code = 'D'
                        AND b.scbcrse_eff_term = (SELECT MAX(d.scbcrse_eff_term)
                                                    FROM scbcrse d
                                                   WHERE d.scbcrse_subj_code = b.scbcrse_subj_code
                                                     AND d.scbcrse_crse_numb = b.scbcrse_crse_numb
                                                     AND d.scbcrse_eff_term <= ssbsect_term_code)
                       LEFT JOIN scbcrse r
                         ON r.scbcrse_subj_code = ssbsect_subj_code
                        AND r.scbcrse_crse_numb = ssbsect_crse_numb
                        AND b.scbcrse_subj_code IS NULL -- not already determined to be a b course
                        AND r.scbcrse_eff_term = (SELECT MAX(d.scbcrse_eff_term)
                                                    FROM scbcrse d
                                                   WHERE d.scbcrse_subj_code = r.scbcrse_subj_code
                                                     AND d.scbcrse_crse_numb = r.scbcrse_crse_numb
                                                     AND d.scbcrse_eff_term <= ssbsect_term_code))
              GROUP BY fac_id) hours
    ON hours.fac_id = spriden_id
--terminal degrees
  LEFT JOIN (SELECT pidm,
                    MAX(CASE
                        WHEN deg_rnk = 1 THEN
                         deg_code
                        END) AS deg_code,
                    MAX(CASE
                        WHEN deg_rnk = 1 THEN
                         fdegree
                        END) AS fdegree,
                    MAX(CASE
                        WHEN deg_rnk = 1 THEN
                         education_details
                        END) AS education_details,
                    MAX(CASE
                        WHEN deg_rnk = 1 THEN
                         term_degree
                        END) AS term_degree,
                    MAX(CASE
                        WHEN deg_rnk = 1 THEN
                         department
                        END) AS department,
                    MAX(CASE
                        WHEN deg_rnk_prioritize_terminal = 1 THEN
                         deg_code
                        END) AS prioiritize_terminal_deg_code,
                    MAX(CASE
                        WHEN deg_rnk_prioritize_terminal = 1 THEN
                         fdegree
                        END) AS prioiritize_terminal_fdegree,
                    MAX(CASE
                        WHEN deg_rnk_prioritize_terminal = 1 THEN
                         education_details
                        END) AS prioiritize_terminal_education_details,
                    MAX(CASE
                        WHEN deg_rnk_prioritize_terminal = 1 THEN
                         term_degree
                        END) prioiritize_terminal,
                    MAX(CASE
                        WHEN deg_rnk_prioritize_terminal = 1 THEN
                         department
                        END) AS prioiritize_terminal_department
               FROM (SELECT DISTINCT t.pidm,
                                     t.deg_code,
                                     t.fdegree,
                                     t.education_details,
                                     t.ztvdegc_terminal  term_degree,
                                     t.department
                                         , dense_rank() over(partition by  t.pidm
                                                            order by case when t.deg_code in ('PHD','DP','D','EDD','DMN','DMA','PSYD','G45','DBA','THD','DSM','DA','DN','DPM','DM','DC','DMGT','DDS','MD','DPT','G44','DVM','DEM','DPHM','DPH','DO') then 1 else 0 end desc
                                                                   , case when t.deg_code in ('JD','BL') then 1 else 0 end desc
                                                                   , case when t.deg_code = 'MFA' then 1 else 0 end desc
                                                                   , case when t.deg_code = 'EDS' then 1 else 0 end desc
                                                                   , case when t.deg_code in ('STM','THM') then 1 else 0 end desc
                                                                   , t.stvdlev_numeric_value desc
                                                                   , rownum )  deg_rnk
                                     , dense_rank() over (partition by t.pidm
                                                          order by case when t.ztvdegc_terminal = 'Y' then 0 else 1 end
                                                                 , case when t.deg_code in ('PHD','DP','D','EDD','DMN','DMA','PSYD','G45','DBA','THD','DSM','DA','DN','DPM','DM','DC','DMGT','DDS','MD','DPT','G44','DVM','DEM','DPHM','DPH','DO') then 1 else 0 end desc
                                                                 , case when t.deg_code in ('JD','BL') then 1 else 0 end desc
                                                                 , case when t.deg_code = 'MFA' then 1 else 0 end desc
                                                                 , case when t.deg_code = 'EDS' then 1 else 0 end desc
                                                                 , case when t.deg_code in ('STM','THM') then 1 else 0 end desc
                                                                 , t.stvdlev_numeric_value desc
                                                                 ,                 rownum) deg_rnk_prioritize_terminal
               FROM (SELECT DISTINCT spriden.spriden_pidm          pidm,
                                     stvdegc.stvdegc_code          deg_code,
                                     stvdlev.stvdlev_desc          fdegree,
                                     stvdegc.stvdegc_desc          education_details,
                                     ztvdegc_terminal,
                                     stvdegc.stvdegc_dlev_code     dlev,
                                     stvdlev.stvdlev_numeric_value,
                                     department.description        department
                       FROM saturn.spriden spriden
                       JOIN (SELECT DISTINCT spriden.spriden_pidm pidm
                              FROM sirasgn
                              JOIN spriden
                                ON spriden.spriden_pidm = sirasgn.sirasgn_pidm
                               AND spriden.spriden_change_ind IS NULL
                               AND sirasgn.sirasgn_term_code = rec.term_code
                               AND sirasgn.sirasgn_primary_ind = 'Y') sirasgn
                         ON sirasgn.pidm = spriden_pidm
                        AND nvl(spriden_first_name, 'x') <> 'To Be Announced'
                       LEFT JOIN zfacultyportfolio.portfolio p
                         ON p.pidm = spriden.spriden_pidm
                       LEFT JOIN zfacultyportfolio.cv cv
                         ON cv.portfolio = p.id
                       LEFT JOIN zfacultyportfolio.earned_degree ed
                         ON ed.cv = cv.id
                       LEFT JOIN saturn.stvdegc stvdegc
                         ON stvdegc.stvdegc_code = ed.degree_code
                       LEFT JOIN zsaturn.ztvdegc
                         ON ztvdegc_code = stvdegc_code
                       LEFT JOIN saturn.stvdlev stvdlev
                         ON stvdlev.stvdlev_code = stvdegc.stvdegc_dlev_code
                       LEFT JOIN zfacultyportfolio.discipline dis
                         ON dis.earned_degree = ed.id
                       LEFT JOIN zhierarchy.position position
                         ON position.pidm = spriden.spriden_pidm
                        AND position.primary_position = 'Y'
                       LEFT JOIN zhierarchy.department department
                         ON department.id = position.department_id) t) faculty
--where  faculty.deg_rnk = 1 -- return highest ranked degree only
 GROUP BY pidm) faculty
    ON faculty.pidm = spriden_pidm
--hierarchy
  LEFT JOIN (SELECT hp.pidm,
                    hd.campus AS hierarchy_campus,
                    hd.college_code AS hierarchy_college,
                    hd.dept_code AS hierarchy_department,
                    hd.level_code AS hierarchy_level,
                    dense_rank() over(PARTITION BY hp.pidm ORDER BY hht.title_id,CASE
                    WHEN hp.primary_position = 'Y' THEN
                     0
                    ELSE
                     1
                    END,CASE
                    WHEN hp.primary_faculty = 'Y' THEN
                     0
                    ELSE
                     1
                    END, hd.level_code,CASE
                    WHEN hd.campus = 'R' THEN
                     0
                    ELSE
                     1
                    END) AS rnk
               FROM zhierarchy.position hp
               JOIN zhierarchy.department hd
                 ON hd.id = hp.department_id
                AND hd.college_code NOT IN ('CS', 'AC', 'GD', 'IN', 'JL', 'PO')
               JOIN zhierarchy.hierarchy_title hht
                 ON hht.id = hp.hierarchy_title_id
                AND hht.title_id BETWEEN 3 AND 7) hier
    ON hier.pidm = spriden_pidm
   AND hier.rnk = 1
--course
  LEFT JOIN (SELECT pidm,
                    term,
                    MAX(CASE
                        WHEN dept_rnk = 1 THEN
                         crse_campus
                        END) AS crse_campus,
                    MAX(CASE
                        WHEN dept_rnk = 1 THEN
                         crse_college
                        END) AS crse_college,
                    MAX(CASE
                        WHEN dept_rnk = 1 THEN
                         crse_dept
                        END) AS crse_department,
                    CASE
                    WHEN MAX(crse_level) != MIN(crse_level) THEN
                     'GR'
                    ELSE
                     MAX(crse_level)
                    END AS crse_level
               FROM (SELECT pidm,
                            term,
                            crse_campus,
                            crse_college,
                            crse_dept,
                            crse_level,
                            hrs,
                            dense_rank() over(PARTITION BY pidm, term ORDER BY dept_hrs DESC,CASE
                            WHEN crse_campus = 'R' THEN
                             0
                            ELSE
                             1
                            END, crse_college, crse_dept) AS dept_rnk
                       FROM (SELECT pidm,
                                    term,
                                    crse_campus,
                                    crse_college,
                                    crse_dept,
                                    crse_level,
                                    SUM(hrs) over(PARTITION BY pidm, term, crse_campus, crse_college, crse_dept) AS dept_hrs,
                                    hrs
                               FROM (SELECT asgn.sirasgn_pidm AS pidm,
                                            substr(asgn.sirasgn_term_code, 1, 5) || '0' AS term,
                                            asgn.sirasgn_term_code AS term_raw,
                                            asgn.sirasgn_crn AS crn,
                                            sect.ssbsect_camp_code AS crse_campus,
                                            nvl(b.scbcrse_coll_code, r.scbcrse_coll_code) AS crse_college,
                                            nvl(b.scbcrse_dept_code, r.scbcrse_dept_code) AS crse_dept,
                                            CASE
                                            WHEN nvl(b.scbcrse_coll_code, r.scbcrse_coll_code) IN ('OM', 'LW') THEN
                                             'GR'
                                            WHEN substr(sect.ssbsect_crse_numb, 1, 1) <= '4' THEN
                                             'UG'
                                            ELSE
                                             'GR'
                                            END AS crse_level,
                                            nvl(sect.ssbsect_credit_hrs, CASE
                                                 WHEN nvl(b.scbcrse_credit_hr_low, r.scbcrse_credit_hr_low) = 1
                                                      AND nvl(b.scbcrse_credit_hr_high, r.scbcrse_credit_hr_high) = 6 THEN
                                                  3
                                                 ELSE
                                                  nvl(b.scbcrse_credit_hr_low, r.scbcrse_credit_hr_low)
                                                 END) AS hrs
                                       FROM saturn.ssbsect sect
                                       JOIN saturn.sirasgn asgn
                                         ON asgn.sirasgn_term_code = sect.ssbsect_term_code
                                        AND substr(asgn.sirasgn_term_code, 1, 5) || '0' = rec.term_code
                                        AND asgn.sirasgn_crn = sect.ssbsect_crn
                                        AND asgn.sirasgn_primary_ind = 'Y'
                                        AND sect.ssbsect_subj_code != 'NEWS'
                                        AND EXISTS (SELECT 1
                                               FROM saturn.sfrstcr stcr
                                               JOIN saturn.stvrsts rsts
                                                 ON rsts.stvrsts_code = stcr.sfrstcr_rsts_code
                                                AND rsts.stvrsts_incl_sect_enrl = 'Y'
                                                AND stcr.sfrstcr_term_code = sect.ssbsect_term_code
                                                AND stcr.sfrstcr_crn = sect.ssbsect_crn
                                               JOIN zsaturn.szrlevl l
                                                 ON l.szrlevl_levl_code = sfrstcr_levl_code
                                                AND l.szrlevl_is_univ = 'Y'
                                                AND l.szrlevl_has_awardable_cred = 'Y')
                                       JOIN zbtm.terms_by_group_v term
                                         ON term.term_code = sect.ssbsect_term_code
                                        AND term.semester = 'FAL'
                                        AND substr(term.term_code, 1, 5) || '0' = rec.term_code
                                       JOIN saturn.scbcrse r
                                         ON r.scbcrse_subj_code = sect.ssbsect_subj_code
                                        AND r.scbcrse_crse_numb = sect.ssbsect_crse_numb
                                        AND r.scbcrse_eff_term = (SELECT MAX(r2.scbcrse_eff_term)
                                                                    FROM saturn.scbcrse r2
                                                                   WHERE r2.scbcrse_subj_code = r.scbcrse_subj_code
                                                                     AND r2.scbcrse_crse_numb = r.scbcrse_crse_numb
                                                                     AND r2.scbcrse_eff_term <= sect.ssbsect_term_code)
                                       LEFT JOIN saturn.scbcrse b
                                         ON b.scbcrse_subj_code = sect.ssbsect_subj_code
                                        AND b.scbcrse_crse_numb = sect.ssbsect_crse_numb || 'B'
                                        AND sect.ssbsect_camp_code = 'D'
                                        AND EXISTS (SELECT 1
                                               FROM saturn.scbcrky k
                                              WHERE k.scbcrky_subj_code = b.scbcrse_subj_code
                                                AND k.scbcrky_crse_numb = b.scbcrse_crse_numb
                                                AND sect.ssbsect_term_code BETWEEN k.scbcrky_term_code_start AND k.scbcrky_term_code_end))))
              GROUP BY pidm,
                       term) crse
    ON crse.pidm = spriden_pidm
 WHERE spriden_change_ind IS NULL
   AND afs.empclassid != 'G' -- remove gsas
   AND (hours.fac_id IS NOT NULL OR fpay.zd_facpay_pidm IS NOT NULL);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
FORALL indx IN 1 .. l_fac.count
INSERT INTO utl_d_aim.ffd_faculty
(term,
 pidm,
 luid,
 last_name,
 first_name,
 status,
 status_rule,
 contract_hours,
 hr_campus,
 hr_college,
 hierarchy_campus,
 hierarchy_college,
 hierarchy_department,
 hierarchy_level,
 crse_campus,
 crse_college,
 crse_department,
 crse_level,
 fall_load_hours,
 fall_hours,
 fall_luo_hours,
 fall_res_hours,
 faculty_type,
 faculty_type_by_level,
 is_terminal,
 prioiritize_terminal)
VALUES
(l_fac(indx).term,
 l_fac(indx).pidm,
 l_fac(indx).luid,
 l_fac(indx).last_name,
 l_fac(indx).first_name,
 l_fac(indx).status,
 l_fac(indx).status_rule,
 l_fac(indx).contract_hours,
 l_fac(indx).hr_campus,
 l_fac(indx).hr_college,
 l_fac(indx).hierarchy_campus,
 l_fac(indx).hierarchy_college,
 l_fac(indx).hierarchy_department,
 l_fac(indx).hierarchy_level,
 l_fac(indx).crse_campus,
 l_fac(indx).crse_college,
 l_fac(indx).crse_department,
 l_fac(indx).crse_level,
 l_fac(indx).fall_load_hours,
 l_fac(indx).fall_hours,
 l_fac(indx).fall_luo_hours,
 l_fac(indx).fall_res_hours,
 l_fac(indx).faculty_type,
 l_fac(indx).faculty_type_by_level,
 l_fac(indx).is_terminal,
 l_fac(indx).prioiritize_terminal);
-- v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
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
/*--------------------------------------------change log----------------------------------------
version    date        username       updates
1.0        10-04-2020  lxhatfield     initial release
---     05-17-2023  wgriffith2  --Dealing with EM courses and updating code to use job_log
------------------------------------------------------------------------------------------------*/
END etl_aim_ffd_faculty;

procedure etl_aim_ute_emails_refresh(jobnumber number, processid varchar2, processname varchar2) is
--DECLARE --Refresh Unofficial Evaluation Emails
--- PARAMS
v_etl_date DATE := SYSDATE;
v_msg      VARCHAR2(2000);
v_instance VARCHAR2(50) := upper('ALL'); -- inst from the jams job; used for determining instance
v_partition NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
-- v_mod         NUMBER := 5; -- number of partitions to be created

v_count           NUMBER := 0;
v_elapsed         NUMBER := 0;
v_total_count     NUMBER := 0;
v_job_id          VARCHAR2(32);
v_proc            VARCHAR2(100) := 'etl_aim_ute_emails_refresh';
v_email_date      DATE := trunc(SYSDATE);
v_eval_date_start DATE;
v_eval_date_end   DATE := v_email_date - 1;
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
v_msg     := 'START - ' || v_instance || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
SELECT MAX(email_date) INTO v_eval_date_start FROM utl_d_aim.ute_emails_detail;
INSERT INTO utl_d_aim.ute_emails_detail
(email_date,
 pidm,
 sbgi_code,
 program,
 evaluation_date,
 transfer_subj,
 transfer_numb,
 transfer_title,
 transfer_cred_hrs,
 lu_subj,
 lu_numb,
 lu_title,
 lu_cred_hrs,
 etl_date)
SELECT DISTINCT v_email_date AS email_date,
                iden.spriden_pidm AS pidm,
                trtk.shrtrtk_sbgi_code AS sbgi_code,
                appl.zsavappl_program AS program,
                trtk.shrtrtk_activity_date AS evaluation_date,
                shrtrtk_tsubj_code AS transfer_subj,
                shrtrtk_tcrse_numb AS transfer_numb,
                shrtrtk_tcrse_title AS transfer_title,
                TRIM(shrtrtk_cred_hours) AS transfer_cred_hrs,
                shrtrtk_subj_code_inst AS lu_subj,
                shrtrtk_crse_numb_inst AS lu_numb,
                shrtrtk_crse_title AS lu_title,
                TRIM(shrtrtk_inst_credits_used) AS lu_cred_hrs,
                v_etl_date AS etl_date
  FROM saturn.shrtrtk trtk
  JOIN saturn.stvsbgi sbgi
    ON sbgi.stvsbgi_code = trtk.shrtrtk_sbgi_code
  JOIN saturn.spriden iden
    ON iden.spriden_pidm = trtk.shrtrtk_pidm
   AND iden.spriden_change_ind IS NULL
  LEFT JOIN zexec.zsavappl appl
    ON appl.zsavappl_pidm = shrtrtk_pidm
   AND appl.zsavappl_comm_rank = 1
 WHERE 1 = 1
   AND trunc(trtk.shrtrtk_activity_date) BETWEEN v_eval_date_start AND v_eval_date_end;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || v_instance || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
INSERT INTO utl_d_aim.ute_emails
(email_date,
 pidm,
 sbgi_code,
 program,
 clob1)
SELECT e.email_date,
       e.pidm,
       e.sbgi_code,
       e.program,
       xmlelement("table", xmlattributes('clob1' AS "id"), xmlforest(xmlelement("tr", xmlattributes('rowhead' AS "class"), xmlconcat( --COLUMN HEADERS
       xmlelement("td", xmlattributes('colHead' AS "class"), 'Course'), xmlelement("td", xmlattributes('colHead' AS "class"), '#'), xmlelement("td", xmlattributes('colHead' AS "class"), 'Title'), xmlelement("td", xmlattributes('colHead' AS "class"), 'Hrs'), xmlelement("td", xmlattributes('colHead' AS "class"), 'Course'), xmlelement("td", xmlattributes('colHead' AS "class"), '#'), xmlelement("td", xmlattributes('colHead' AS "class"), 'Title'), xmlelement("td", xmlattributes('colHead' AS "class"), 'Hrs'))) AS "thead", xmlagg(xmlforest(xmlconcat( --COLUMN DATA
       xmlelement("td", xmlattributes('colData' AS "class"), '<font face="Helvetica" size="1">' || e.transfer_subj || '</font>'), xmlelement("td", xmlattributes('colData' AS "class"), '<font face="Helvetica" size="1">' || e.transfer_numb || '</font>'), xmlelement("td", xmlattributes('colData' AS "class"), '<font face="Helvetica" size="1">' || e.transfer_title || '</font>'), xmlelement("td", xmlattributes('colData' AS "class"), '<font face="Helvetica" size="1">' || e.transfer_cred_hrs || '</font>'), xmlelement("td", xmlattributes('colData' AS "class"), '<font face="Helvetica" size="1">' || e.lu_subj || '</font>'), xmlelement("td", xmlattributes('colData' AS "class"), '<font face="Helvetica" size="1">' || e.lu_numb || '</font>'), xmlelement("td", xmlattributes('colData' AS "class"), '<font face="Helvetica" size="1">' || e.lu_title || '</font>'), xmlelement("td", xmlattributes('colData' AS "class"), '<font face="Helvetica" size="1">' || e.lu_cred_hrs || '</font>')) AS "tr") ORDER BY e.transfer_subj, e.transfer_numb) AS "tbody")).getclobval() AS clob1
  FROM utl_d_aim.ute_emails_detail e
 WHERE e.email_date = v_email_date
   AND e.lu_subj IS NOT NULL
   AND e.program IS NOT NULL
 GROUP BY e.email_date,
          e.pidm,
          e.sbgi_code,
          e.program;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || v_instance || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
/*--------------------------------------------CHANGE LOG----------------------------------------
VERSION    DATE        USERNAME       UPDATES
1.0        02-02-2021  lxhatfield     Initial release (SCTASK0479421)
1.1        02-11-2021  lxhatfield     added summary table
---     05-24-2023  wgriffith2  --updating code to use job_log
------------------------------------------------------------------------------------------------*/
END etl_aim_ute_emails_refresh;

procedure etl_aim_faculty_work_hours_refresh(jobnumber number, processid varchar2, processname varchar2) is
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
v_proc        VARCHAR2(100) := 'etl_aim_faculty_work_hours_refresh';
CURSOR c_terms IS
SELECT DISTINCT to_char(dte, 'yyyy') yr FROM utl_d_aim.calendar WHERE to_char(dte, 'yyyy') BETWEEN to_char((v_etl_date - (365 * 3)), 'YYYY') AND to_char(v_etl_date, 'yyyy') ORDER BY 1 DESC;
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
v_msg     := 'START - ' || rec.yr || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
DELETE FROM utl_d_aim.faculty_work_hours_detail wh WHERE wh.report_yr = rec.yr;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'DELETE - ' || rec.yr || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
INSERT INTO utl_d_aim.faculty_work_hours_detail
(pidm,
 benefits,
 report_yr,
 report_yr_desc,
 report_yr_start_date,
 report_yr_end_date,
 report_term,
 dte,
 hierarchy_campus,
 hierarchy_college,
 hierarchy_department,
 subj,
 numb,
 course,
 sect,
 crn,
 course_campus,
 course_college,
 course_department,
 course_start_date,
 course_end_date,
 course_term,
 course_ptrm,
 course_ptrm_incomplete,
 thesis_students,
 students,
 load,
 day_load,
 sme,
 im,
 sme_load,
 im_load,
 thesis_load,
 release_term,
 release_load,
 release_hours,
 release_stipend,
 etl_date)
WITH yr AS
 (SELECT /*+ materialize*/
  DISTINCT rec.yr yr,
           rec.yr || ' - ' || (rec.yr + 1) AS yr_desc,
           CASE
           WHEN rec.yr <= '2020' --Hard coded values requested by Kathy Bennett on 4/1/2022 as part of v1.1
            THEN
            to_date('7/1/' || rec.yr, 'MM/DD/YYYY')
           WHEN rec.yr = '2021' THEN
            to_date('6/25/' || rec.yr, 'MM/DD/YYYY')
           WHEN rec.yr = '2022' THEN
            to_date('6/27/' || rec.yr, 'MM/DD/YYYY')
           ELSE
            to_date('7/1/' || rec.yr, 'MM/DD/YYYY') - 6 --Default for future years. Added v1.1
           END AS from_dte,
           CASE
           WHEN rec.yr <= '2020' --Hard coded values requested by Kathy Bennett on 4/1/2022 as part of v1.1
            THEN
            to_date('5/31/' || (rec.yr + 1), 'MM/DD/YYYY')
           WHEN rec.yr = '2021' THEN
            to_date('5/27/' || (rec.yr + 1), 'MM/DD/YYYY')
           WHEN rec.yr = '2022' THEN
            to_date('5/26/' || (rec.yr + 1), 'MM/DD/YYYY')
           ELSE
            to_date('5/31/' || (rec.yr + 1), 'MM/DD/YYYY')
           END AS to_dte,
           v_etl_date AS etl_date
    FROM dual),
dtes AS
 (SELECT /*+ materialize*/
   yr,
   yr_desc,
   yr.from_dte,
   yr.to_dte,
   dte,
   tbgv.term_code,
   tbgv.semester,
   term.stvterm_acyr_code AS acyr_code
    FROM yr
    JOIN utl_d_aim.calendar cal
      ON cal.day_numb = 2
     AND cal.dte BETWEEN from_dte AND to_dte
    JOIN zbtm.terms_by_group_v tbgv
      ON tbgv.group_code = 'STD'
    JOIN saturn.stvterm term
      ON term.stvterm_code = tbgv.term_code
    JOIN saturn.sobptrm ptrm
      ON ptrm.sobptrm_term_code = term.stvterm_code
     AND (ptrm.sobptrm_ptrm_code = '1A' --using the term start date in stvterm includes an extra week for j term
         AND tbgv.semester != 'WIN' OR tbgv.semester = 'WIN' AND ptrm.sobptrm_ptrm_code = '1J')
     AND cal.dte BETWEEN ptrm.sobptrm_start_date AND ptrm.sobptrm_end_date),
disp AS
 (SELECT ptrm.sobptrm_term_code AS term_code,
         ptrm.sobptrm_ptrm_code AS ptrm_code,
         ptrm.sobptrm_start_date AS ptrm_start_date,
         CASE
         WHEN ptrm.sobptrm_ptrm_code IN ('1A', '1B', '1C', '1D', 'R') THEN
          next_day(ptrm.sobptrm_start_date + (2 * 6), 'Monday')
         WHEN tbgv.semester = 'WIN' THEN
          next_day(dtrm.sobptrm_start_date + (2 * 6), 'Monday')
         ELSE
          next_day(dtrm.sobptrm_start_date + (2 * 6), 'Monday')
         END AS display_from_date,
         CASE
         WHEN ptrm.sobptrm_ptrm_code IN ('1A', '1B', '1C', '1D', 'R') THEN
          next_day(ptrm.sobptrm_start_date + (5 * 6), 'Monday')
         WHEN tbgv.semester = 'WIN' THEN
          next_day(dtrm.sobptrm_start_date + (3 * 6), 'Monday')
         ELSE
          next_day(dtrm.sobptrm_start_date + (5 * 6), 'Monday')
         END AS final_date
    FROM saturn.sobptrm ptrm
    JOIN zbtm.terms_by_group_v tbgv
      ON tbgv.group_code = 'STD'
     AND tbgv.term_code = ptrm.sobptrm_term_code
    JOIN saturn.sobptrm dtrm
      ON dtrm.sobptrm_term_code = ptrm.sobptrm_term_code
     AND (dtrm.sobptrm_ptrm_code = '1D' AND tbgv.semester != 'WIN' OR tbgv.semester = 'WIN' AND dtrm.sobptrm_ptrm_code = '1J')
   WHERE v_etl_date >= CASE
         WHEN ptrm.sobptrm_ptrm_code IN ('1A', '1B', '1C', '1D', 'R') THEN
          ptrm.sobptrm_start_date + (2 * 6)
         ELSE
          dtrm.sobptrm_start_date + (2 * 6)
         END),
crse AS
 (SELECT /*+ materialize*/
   nvl(pay.yr, thesis.yr) AS yr,
   nvl(pay.yr_desc, thesis.yr_desc) AS yr_desc,
   nvl(pay.subject, thesis.subject) AS subject,
   nvl(pay.crse_numb, thesis.crse_numb) AS crse_numb,
   nvl(pay.course, thesis.course) AS course,
   nvl(pay.sect, thesis.sect) AS sect,
   nvl(pay.crn, thesis.crn) AS crn,
   nvl(pay.start_date, thesis.start_date) AS start_date,
   nvl(pay.end_date, thesis.end_date) AS end_date,
   nvl(pay.term, thesis.term) AS term,
   nvl(pay.ptrm, thesis.ptrm) AS ptrm,
   nvl(pay.ptrm_incomplete, thesis.ptrm_incomplete) AS ptrm_incomplete,
   nvl(pay.pidm, thesis.pidm) AS pidm,
   nvl(pay.im, thesis.im) AS im,
   nvl(pay.campus, thesis.campus) AS campus,
   coll.stvcoll_desc AS college,
   dept.stvdept_desc AS department,
   SUM(nvl(pay.th_students, thesis.th_students)) AS th_students,
   SUM(nvl(pay.students, thesis.students)) AS students,
   MAX(nvl(pay.load, thesis.load)) AS load,
   MAX(nvl(pay.sme, thesis.sme)) AS sme
    FROM (SELECT yr,
                 yr_desc,
                 sect.ssbsect_subj_code AS subject,
                 sect.ssbsect_crse_numb AS crse_numb,
                 sect.ssbsect_subj_code || sect.ssbsect_crse_numb AS course,
                 sect.ssbsect_seq_numb AS sect,
                 sect.ssbsect_crn AS crn,
                 sect.ssbsect_ptrm_start_date AS start_date,
                 sect.ssbsect_ptrm_end_date AS end_date,
                 sect.ssbsect_term_code AS term,
                 sect.ssbsect_ptrm_code AS ptrm,
                 CASE
                 WHEN disp.final_date > yr.etl_date THEN
                  'Y'
                 END AS ptrm_incomplete,
                 COUNT(DISTINCT stcr.sfrstcr_pidm) AS th_students,
                 0 AS students,
                 asgn.sirasgn_pidm AS pidm,
                 0 AS load,
                 NULL AS sme,
                 NULL AS im,
                 sect.ssbsect_camp_code AS campus
            FROM yr
            JOIN saturn.ssbsect sect
              ON sect.ssbsect_ptrm_start_date <= to_dte
             AND sect.ssbsect_ptrm_end_date >= from_dte
             AND sect.ssbsect_insm_code = 'TH'
             AND sect.ssbsect_subj_code || ' ' || sect.ssbsect_crse_numb IN
                 ('ARTS 789', 'ARTS 790', 'BIBL 987', 'BIBL 988', 'BIBL 989', 'BIOM 889', 'BIOM 890', 'BMAL 887', 'BMAL 888', 'BMAL 889', 'BUSI 887', 'BUSI 888', 'BUSI 889', 'BUSI 987', 'BUSI 988', 'BUSI 989', 'CJUS 689', 'CJUS 690', 'CJUS 887', 'CJUS 888', 'CJUS 889', 'CJUS 980', 'CJUS 987', 'CJUS 988', 'CJUS 989', 'CJUS 990', 'CLED 987', 'CLED 988', 'CLED 989', 'CLED 990', 'COMS 689', 'COMS 690', 'COMS 691', 'COMS 987', 'COMS 988', 'COMS 989', 'COUC 989', 'COUC 990', 'DISS 987', 'DISS 988', 'DISS 989', 'DISS 990', 'DMIN 841', 'DMIN 881', 'DMIN 885', 'DMIN 889', 'DMIN 890', 'EDCO 808', 'EDCO 825', 'EDCO 988', 'EDCO 989', 'EDCO 990', 'EDDR 987', 'EDDR 988', 'EDDR 989', 'EDUC 887', 'EDUC 888', 'EDUC 889', 'EDUC 987', 'EDUC 988', 'EDUC 989', 'EDUC 990', 'ENGL 689', 'ENGL 690', 'ENGR 687', 'ENGR 688', 'ENGR 689', 'ENGR 690', 'ENGR 987', 'ENGR 988', 'ENGR 989', 'ENGR 990', 'ETHM 689', 'ETHM 690', 'HIST 689', 'HIST 690', 'HIST 987', 'HIST 988', 'HIST 989', 'HSCI 887', 'HSCI 888', 'HSCI 889', 'HSCI 987', 'HSCI 988', 'HSCI 989', 'INTL 689', 'INTL 690', 'LPCY 887', 'LPCY 888', 'LPCY 889', 'MSPS 689', 'MSPS 691', 'MUSC 687', 'MUSC 689', 'MUSC 690', 'MUSC 691', 'MUSC 888', 'MUSC 889', 'MUSC 890', 'NESC 689', 'NSEC 690', 'NURS 987', 'NURS 988', 'NURS 989', 'PADM 689', 'PADM 690', 'PADM 887', 'PADM 888', 'PADM 889', 'PADM 987', 'PADM 988', 'PADM 989', 'PHIL 689', 'PHIL 690', 'PLCY 842', 'PLCY 852', 'PLCY 862', 'PLCY 872', 'PLCY 882', 'PLCY 980', 'PLCY 987', 'PLCY 988', 'PLCY 989', 'PLCY 990', 'PPOG 689', 'PPOG 690', 'PSCI 689', 'PSCI 690', 'PSYC 689', 'PSYC 690', 'PSYC 987', 'PSYC 988', 'PSYC 989', 'PSYD 889', 'PSYD 890', 'SMGT 689', 'SMGT 690', 'STCO 689', 'STCO 690', 'STCO 691', 'THES 689', 'THES 690', 'WMUS 687', 'WMUS 689', 'WMUS 690', 'WRIT 689', 'WRIT 690', 'WRSP 687', 'WRSP 689', 'WRSP 690', 'WRSP 888', 'WRSP 889', 'WRSP 890', 'WRSP 987', 'WRSP 988', 'WRSP 989', 'DMIN 885', 'HSCI 887', 'HSCI 888', 'HSCI 889', 'HSCI 890', 'HSCI 987', 'HSCI 988', 'HSCI 989', 'HSCI 990', 'LPCY 887', 'LPCY 888', 'LPCY 889', 'LPCY 890', 'NSEC 689', 'EXSC 689', 'EXSC 690', 'MUSC 987', 'MUSC 988', 'MUSC 989', 'AVIA 987', 'AVIA 988', 'AVIA 989', 'AVIA 990', 'CLED 885', 'CLED 886', 'CLED 887', 'CLED 888', 'CLED 889', 'CLED 890')
            JOIN disp
              ON disp.term_code = sect.ssbsect_term_code
             AND disp.ptrm_code = sect.ssbsect_ptrm_code
             AND disp.display_from_date <= yr.etl_date
            JOIN saturn.sirasgn asgn
              ON asgn.sirasgn_term_code = sect.ssbsect_term_code
             AND asgn.sirasgn_crn = sect.ssbsect_crn
             AND asgn.sirasgn_primary_ind = 'Y'
            JOIN saturn.sfrstcr stcr
              ON stcr.sfrstcr_term_code = sect.ssbsect_term_code
             AND stcr.sfrstcr_crn = sect.ssbsect_crn
            JOIN saturn.stvrsts rsts
              ON rsts.stvrsts_code = stcr.sfrstcr_rsts_code
             AND rsts.stvrsts_incl_sect_enrl = 'Y'
           GROUP BY yr,
                    yr_desc,
                    sect.ssbsect_subj_code,
                    sect.ssbsect_crse_numb,
                    sect.ssbsect_subj_code || sect.ssbsect_crse_numb,
                    sect.ssbsect_seq_numb,
                    sect.ssbsect_crn,
                    sect.ssbsect_ptrm_start_date,
                    sect.ssbsect_ptrm_end_date,
                    sect.ssbsect_term_code,
                    sect.ssbsect_ptrm_code,
                    CASE
                    WHEN disp.final_date > yr.etl_date THEN
                     'Y'
                    END,
                    asgn.sirasgn_pidm,
                    sect.ssbsect_camp_code) pay
    FULL OUTER JOIN (SELECT yr,
                           yr_desc,
                           sect.ssbsect_subj_code AS subject,
                           sect.ssbsect_crse_numb AS crse_numb,
                           sect.ssbsect_subj_code || sect.ssbsect_crse_numb AS course,
                           sect.ssbsect_seq_numb AS sect,
                           sect.ssbsect_crn AS crn,
                           sect.ssbsect_ptrm_start_date AS start_date,
                           sect.ssbsect_ptrm_end_date AS end_date,
                           sect.ssbsect_term_code AS term,
                           sect.ssbsect_ptrm_code AS ptrm,
                           CASE
                           WHEN disp.final_date > yr.etl_date THEN
                            'Y'
                           END AS ptrm_incomplete,
                           NULL AS th_students,
                           (SELECT COUNT(DISTINCT stcr.sfrstcr_pidm)
                              FROM saturn.sfrstcr stcr
                              JOIN saturn.stvrsts rsts
                                ON rsts.stvrsts_code = stcr.sfrstcr_rsts_code
                               AND rsts.stvrsts_incl_sect_enrl = 'Y'
                               AND stcr.sfrstcr_term_code = sect.ssbsect_term_code
                               AND stcr.sfrstcr_crn = sect.ssbsect_crn) AS students,
                           fpay.zd_facpay_pidm AS pidm,
                           SUM(nvl(fpay.zd_facpay_load_hr, 0)) AS load,
                           MAX(fpay.zd_facpay_sme_ind) AS sme,
                           MAX(fpay.zd_facpay_im_ind) AS im,
                           sect.ssbsect_camp_code AS campus
                      FROM yr
                      JOIN saturn.ssbsect sect
                        ON sect.ssbsect_ptrm_start_date <= to_dte
                       AND sect.ssbsect_ptrm_end_date >= from_dte
                      JOIN disp
                        ON disp.term_code = sect.ssbsect_term_code
                       AND disp.ptrm_code = sect.ssbsect_ptrm_code
                       AND disp.display_from_date <= yr.etl_date
                      JOIN zprovost.zd_facpay fpay
                        ON sect.ssbsect_term_code = fpay.zd_facpay_term_code
                       AND sect.ssbsect_crn = fpay.zd_facpay_crn
                       AND nvl(fpay.zd_facpay_load_hr, 0) != 0
                     GROUP BY yr,
                              yr_desc,
                              sect.ssbsect_subj_code,
                              sect.ssbsect_crse_numb,
                              sect.ssbsect_subj_code || sect.ssbsect_crse_numb,
                              sect.ssbsect_seq_numb,
                              sect.ssbsect_crn,
                              sect.ssbsect_ptrm_start_date,
                              sect.ssbsect_ptrm_end_date,
                              sect.ssbsect_term_code,
                              sect.ssbsect_ptrm_code,
                              sect.ssbsect_camp_code,
                              fpay.zd_facpay_pidm,
                              CASE
                              WHEN disp.final_date > yr.etl_date THEN
                               'Y'
                              END) thesis
      ON thesis.yr = pay.yr
     AND thesis.term = pay.term
     AND thesis.crn = pay.crn
     AND thesis.pidm = pay.pidm
    JOIN saturn.scbcrse ctlg
      ON ctlg.scbcrse_subj_code = nvl(pay.subject, thesis.subject) --sect.ssbsect_subj_code
     AND ctlg.scbcrse_crse_numb = nvl(pay.crse_numb, thesis.crse_numb) --sect.ssbsect_crse_numb
     AND ctlg.scbcrse_eff_term = (SELECT MAX(ctlg2.scbcrse_eff_term)
                                    FROM saturn.scbcrse ctlg2
                                   WHERE ctlg2.scbcrse_subj_code = ctlg.scbcrse_subj_code
                                     AND ctlg2.scbcrse_crse_numb = ctlg.scbcrse_crse_numb
                                     AND ctlg2.scbcrse_eff_term <= nvl(pay.term, thesis.term))
    LEFT JOIN saturn.stvcoll coll
      ON coll.stvcoll_code = ctlg.scbcrse_coll_code
    LEFT JOIN saturn.stvdept dept
      ON dept.stvdept_code = ctlg.scbcrse_dept_code
   GROUP BY nvl(pay.yr, thesis.yr),
            nvl(pay.yr_desc, thesis.yr_desc),
            nvl(pay.subject, thesis.subject),
            nvl(pay.crse_numb, thesis.crse_numb),
            nvl(pay.course, thesis.course),
            nvl(pay.sect, thesis.sect),
            nvl(pay.crn, thesis.crn),
            nvl(pay.start_date, thesis.start_date),
            nvl(pay.end_date, thesis.end_date),
            nvl(pay.term, thesis.term),
            nvl(pay.ptrm, thesis.ptrm),
            nvl(pay.ptrm_incomplete, thesis.ptrm_incomplete),
            nvl(pay.pidm, thesis.pidm),
            nvl(pay.im, thesis.im),
            nvl(pay.campus, thesis.campus),
            coll.stvcoll_desc,
            dept.stvdept_desc),
rel AS
 (SELECT r.pidm,
         r.acyr,
         dtes.yr,
         dtes.yr_desc,
         dtes.dte,
         dtes.term_code,
         dtes.semester,
         SUM(CASE dtes.semester
             WHEN 'SPR' THEN
              spring
             WHEN 'FAL' THEN
              fall
             WHEN 'SUM' THEN
              summer
             END) AS release_load,
         SUM(CASE dtes.semester
             WHEN 'SPR' THEN
              spring_hrs
             WHEN 'FAL' THEN
              fall_hrs
             WHEN 'SUM' THEN
              summer_hrs
             END) AS release_hours,
         SUM(CASE dtes.semester
             WHEN 'SPR' THEN
              spring_stipend
             WHEN 'FAL' THEN
              fall_stipend
             WHEN 'SUM' THEN
              summer_stipend
             END) AS release_stipend
    FROM (SELECT brls.szbrlse_id AS release_id,
                 brls.szbrlse_pidm AS pidm,
                 brls.szbrlse_acyr AS acyr,
                 nvl(brls.szbrlse_fall_hrs, 0) AS fall_hrs_raw,
                 nvl(brls.szbrlse_fall_stipend, 0) AS fall_stipend_raw,
                 nvl(brls.szbrlse_spring_hrs, 0) AS spring_hrs_raw,
                 nvl(brls.szbrlse_spring_stipend, 0) AS spring_stipend_raw,
                 nvl(brls.szbrlse_summer_hrs, 0) AS summer_hrs_raw,
                 nvl(brls.szbrlse_summer_stipend, 0) AS summer_stipend_raw,
                 CASE
                 WHEN lower(brls.szbrlse_rlse_desc) LIKE '%clb dissertation chair%'
                      AND brls.szbrlse_data_origin = 'Initial Import from App 710' THEN
                  (nvl(brls.szbrlse_fall_hrs, 0) + nvl(brls.szbrlse_spring_hrs, 0) + nvl(brls.szbrlse_summer_hrs, 0)) / 3
                 ELSE
                  nvl(brls.szbrlse_fall_hrs, 0)
                 END AS fall_hrs,
                 CASE
                 WHEN lower(brls.szbrlse_rlse_desc) LIKE '%clb dissertation chair%'
                      AND brls.szbrlse_data_origin = 'Initial Import from App 710' THEN
                  ((nvl(brls.szbrlse_fall_stipend, 0) + nvl(brls.szbrlse_spring_stipend, 0) + nvl(brls.szbrlse_summer_stipend, 0)) / 3) / CASE
                  WHEN brls.szbrlse_acyr < 2021 THEN
                   700
                  ELSE
                   800
                  END
                 ELSE
                  nvl(brls.szbrlse_fall_stipend, 0)
                 END AS fall_stipend,
                 CASE
                 WHEN lower(brls.szbrlse_rlse_desc) LIKE '%clb dissertation chair%'
                      AND brls.szbrlse_data_origin = 'Initial Import from App 710' THEN
                  (nvl(brls.szbrlse_fall_hrs, 0) + nvl(brls.szbrlse_spring_hrs, 0) + nvl(brls.szbrlse_summer_hrs, 0)) / 3
                 ELSE
                  nvl(brls.szbrlse_spring_hrs, 0)
                 END AS spring_hrs,
                 CASE
                 WHEN lower(brls.szbrlse_rlse_desc) LIKE '%clb dissertation chair%'
                      AND brls.szbrlse_data_origin = 'Initial Import from App 710' THEN
                  ((nvl(brls.szbrlse_fall_stipend, 0) + nvl(brls.szbrlse_spring_stipend, 0) + nvl(brls.szbrlse_summer_stipend, 0)) / 3) / CASE
                  WHEN brls.szbrlse_acyr < 2021 THEN
                   700
                  ELSE
                   800
                  END
                 ELSE
                  nvl(brls.szbrlse_spring_stipend, 0)
                 END AS spring_stipend,
                 CASE
                 WHEN lower(brls.szbrlse_rlse_desc) LIKE '%clb dissertation chair%'
                      AND brls.szbrlse_data_origin = 'Initial Import from App 710' THEN
                  (nvl(brls.szbrlse_fall_hrs, 0) + nvl(brls.szbrlse_spring_hrs, 0) + nvl(brls.szbrlse_summer_hrs, 0)) / 3
                 ELSE
                  nvl(brls.szbrlse_summer_hrs, 0)
                 END AS summer_hrs,
                 CASE
                 WHEN lower(brls.szbrlse_rlse_desc) LIKE '%clb dissertation chair%'
                      AND brls.szbrlse_data_origin = 'Initial Import from App 710' THEN
                  ((nvl(brls.szbrlse_fall_stipend, 0) + nvl(brls.szbrlse_spring_stipend, 0) + nvl(brls.szbrlse_summer_stipend, 0)) / 3) / CASE
                  WHEN brls.szbrlse_acyr < '2021' THEN
                   700
                  ELSE
                   800
                  END
                 ELSE
                  nvl(brls.szbrlse_summer_stipend, 0)
                 END AS summer_stipend,
                 CASE
                 WHEN lower(brls.szbrlse_rlse_desc) LIKE '%clb dissertation chair%'
                      AND brls.szbrlse_data_origin = 'Initial Import from App 710' THEN
                  (nvl(brls.szbrlse_fall_hrs, 0) + nvl(brls.szbrlse_spring_hrs, 0) + nvl(brls.szbrlse_summer_hrs, 0)) / 3 + ((nvl(brls.szbrlse_fall_stipend, 0) + nvl(brls.szbrlse_spring_stipend, 0) + nvl(brls.szbrlse_summer_stipend, 0)) / 3) / CASE
                  WHEN brls.szbrlse_acyr < '2021' THEN
                   700
                  ELSE
                   800
                  END
                 ELSE
                  nvl(brls.szbrlse_fall_hrs, 0) + nvl(brls.szbrlse_fall_stipend, 0) / CASE
                  WHEN brls.szbrlse_acyr < 2021 THEN
                   700
                  ELSE
                   800
                  END
                 END AS fall,
                 CASE
                 WHEN lower(brls.szbrlse_rlse_desc) LIKE '%clb dissertation chair%'
                      AND brls.szbrlse_data_origin = 'Initial Import from App 710' THEN
                  (nvl(brls.szbrlse_fall_hrs, 0) + nvl(brls.szbrlse_spring_hrs, 0) + nvl(brls.szbrlse_summer_hrs, 0)) / 3 + ((nvl(brls.szbrlse_fall_stipend, 0) + nvl(brls.szbrlse_spring_stipend, 0) + nvl(brls.szbrlse_summer_stipend, 0)) / 3) / CASE
                  WHEN brls.szbrlse_acyr < '2021' THEN
                   700
                  ELSE
                   800
                  END
                 ELSE
                  nvl(brls.szbrlse_spring_hrs, 0) + nvl(brls.szbrlse_spring_stipend, 0) / CASE
                  WHEN brls.szbrlse_acyr < 2021 THEN
                   700
                  ELSE
                   800
                  END
                 END AS spring,
                 CASE
                 WHEN lower(brls.szbrlse_rlse_desc) LIKE '%clb dissertation chair%'
                      AND brls.szbrlse_data_origin = 'Initial Import from App 710' THEN
                  (nvl(brls.szbrlse_fall_hrs, 0) + nvl(brls.szbrlse_spring_hrs, 0) + nvl(brls.szbrlse_summer_hrs, 0)) / 3 + ((nvl(brls.szbrlse_fall_stipend, 0) + nvl(brls.szbrlse_spring_stipend, 0) + nvl(brls.szbrlse_summer_stipend, 0)) / 3) / CASE
                  WHEN brls.szbrlse_acyr < '2021' THEN
                   700
                  ELSE
                   800
                  END
                 ELSE
                  nvl(brls.szbrlse_summer_hrs, 0) + nvl(brls.szbrlse_summer_stipend, 0) / CASE
                  WHEN brls.szbrlse_acyr < '2021' THEN
                   700
                  ELSE
                   800
                  END
                 END AS summer
            FROM zprovost.szbrlse brls
            LEFT JOIN saturn.spriden iden
              ON iden.spriden_pidm = brls.szbrlse_pidm
             AND iden.spriden_change_ind IS NULL
            LEFT JOIN zgeneral.zgbwfpr wfpr
              ON wfpr.zgbwfpr_proc_id = brls.szbrlse_proc_id
            LEFT JOIN zgeneral.zgrwfac wfac
              ON wfac.zgrwfac_proc_id = brls.szbrlse_proc_id
             AND wfac.zgrwfac_active_ind = 'Y'
            LEFT JOIN zgeneral.zgrwfqu wfqu
              ON wfqu.zgrwfqu_que_id = wfac.zgrwfac_que_id
             AND wfqu.zgrwfqu_flow_id = wfac.zgrwfac_flow_id
            LEFT JOIN zformdata.zfrlist rtyp
              ON rtyp.zfrlist_list_code = 'FCRF_APEX_103_RELEASE_REQ_TYPES'
             AND rtyp.zfrlist_active_yn = 'Y'
             AND rtyp.zfrlist_key1_code = brls.szbrlse_rlse_req_type
           WHERE brls.szbrlse_to_date = to_date('2099-12-31', 'YYYY-MM-DD')
             AND brls.szbrlse_rlse_req_type != 'Cancelled'
             AND brls.szbrlse_pidm IS NOT NULL) r
    JOIN dtes
      ON dtes.acyr_code = r.acyr
     AND dtes.semester IN ('SPR', 'FAL', 'SUM')
   WHERE EXISTS (SELECT 1 FROM disp WHERE disp.term_code = dtes.term_code)
   GROUP BY r.pidm,
            r.acyr,
            dtes.yr,
            dtes.yr_desc,
            dtes.dte,
            dtes.term_code,
            dtes.semester),
fac AS
 (SELECT /*+ materialize*/
  DISTINCT p.pidm               pidm,
           dept.campus          primary_campus,
           stvcoll.stvcoll_desc primary_college,
           stvdept.stvdept_desc primary_dept
    FROM zhierarchy.position p
   INNER JOIN zhierarchy.hierarchy_title ht
      ON ht.id = p.hierarchy_title_id
   INNER JOIN zhierarchy.title title
      ON title.id = ht.title_id
  --and title.id = 7 -- faculty records
   INNER JOIN zhierarchy.department dept
      ON dept.id = p.department_id
   INNER JOIN stvcoll
      ON stvcoll.stvcoll_code = dept.college_code
   INNER JOIN stvdept
      ON stvdept.stvdept_code = dept.dept_code
   WHERE p.primary_faculty = 'Y'),
base AS
 (SELECT DISTINCT b.*
    FROM (SELECT crse.yr year1,
                 crse.yr_desc,
                 crse.pidm,
                 dtes.term_code,
                 dtes.dte,
                 dtes.from_dte,
                 dtes.to_dte
            FROM crse
            LEFT JOIN dtes
              ON dtes.yr = crse.yr
          UNION ALL
          SELECT rel.yr,
                 rel.yr_desc,
                 rel.pidm,
                 dtes.term_code,
                 dtes.dte,
                 dtes.from_dte,
                 dtes.to_dte
            FROM rel
            LEFT JOIN dtes
              ON dtes.yr = rel.yr) b)
SELECT base.pidm,
       base.benefits,
       base.base_year AS report_yr,
       base.base_year_description AS report_yr_desc,
       base.base_year_start_date AS report_yr_start_date,
       base.base_year_end_date AS report_yr_end_date,
       base.term_code AS report_term,
       base.dte,
       base.primary_campus AS hierarchy_campus,
       base.primary_college AS hierarchy_college,
       base.primary_dept AS hierarchy_department,
       base.subj,
       base.numb,
       base.course,
       base.sect,
       base.crn,
       base.course_campus,
       base.course_college,
       base.course_department,
       base.start_date AS course_start_date,
       base.end_date AS course_end_date,
       base.course_term,
       base.ptrm AS course_ptrm,
       base.ptrm_incomplete AS course_ptrm_incomplete,
       CASE
       WHEN base.load > 0 THEN
        0
       ELSE
        base.th_students
       END AS thesis_students,
       base.students,
       base.load,
       base.day_load,
       base.sme,
       base.im,
       base.sme_load,
       base.im_load,
       base.th_load AS thesis_load,
       base.release_term,
       base.release_load,
       base.release_hours,
       base.release_stipend,
       v_etl_date AS etl_date
  FROM (SELECT spriden_id luid,
               spriden_last_name || ', ' || spriden_first_name fac_name,
               REPLACE(TRIM(f.szrfcrf_benefits), '-', ' ') AS benefits,
               base.year1 base_year,
               base.yr_desc base_year_description,
               base.from_dte base_year_start_date,
               base.to_dte base_year_end_date,
               base.term_code,
               base.dte,
               fac.primary_campus,
               fac.primary_college,
               fac.primary_dept,
               crse.subject AS subj,
               crse.crse_numb AS numb,
               crse.course,
               crse.sect,
               crse.crn,
               crse.start_date,
               crse.end_date,
               crse.term AS course_term,
               crse.ptrm,
               crse.ptrm_incomplete,
               crse.th_students,
               crse.students,
               base.pidm,
               crse.load,
               crse.sme,
               crse.im,
               crse.campus AS course_campus,
               crse.college AS course_college,
               crse.department AS course_department,
               CASE
               WHEN COUNT(DISTINCT CASE
                          WHEN crse.ptrm != '1C'
                               AND crse.sme = 'Y' THEN
                           crse.ptrm || '-' || crse.course
                          END) over(PARTITION BY base.pidm, base.dte, base.year1) > 2 THEN
                2
               ELSE
                COUNT(DISTINCT CASE
                      WHEN crse.ptrm != '1C'
                           AND crse.sme = 'Y' THEN
                       crse.ptrm || '-' || crse.course
                      END) over(PARTITION BY base.pidm, base.dte, base.year1)
               END AS sme_load,
               CASE
               WHEN MAX(crse.im) over(PARTITION BY base.pidm, base.dte, base.year1) = 'Y' THEN
                1
               ELSE
                0
               END AS im_load,
               SUM(crse.load) over(PARTITION BY base.pidm, base.dte, base.year1) AS day_load,
               SUM(CASE
                   WHEN crse.load = 0 THEN
                    crse.th_students
                   END) over(PARTITION BY base.pidm, base.dte, base.year1) * 0.5 AS th_load,
               rel.term_code AS release_term,
               rel.release_load,
               rel.release_hours,
               rel.release_stipend
          FROM base
          LEFT JOIN crse
            ON base.dte BETWEEN crse.start_date AND crse.end_date
           AND base.pidm = crse.pidm
           AND base.year1 = crse.yr
          LEFT JOIN rel
            ON base.dte = rel.dte
           AND base.pidm = rel.pidm
           AND base.year1 = rel.yr
          LEFT JOIN spriden
            ON spriden_pidm = base.pidm
           AND spriden_change_ind IS NULL
          LEFT JOIN fac
            ON fac.pidm = spriden_pidm
          LEFT JOIN zprovost.szrfcrf f
            ON f.szrfcrf_contractee_pidm = base.pidm
           AND f.szrfcrf_acyr = base.year1
           AND f.szrfcrf_to_date = to_date('2099-12-31', 'YYYY-MM-DD')
           AND trunc(f.szrfcrf_effective_date) <= base.dte
           AND f.szrfcrf_school != 'AC'
         WHERE base.year1 >= 2018) base;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || rec.yr || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
END LOOP; -- c_terms
DELETE FROM utl_d_aim.faculty_work_hours wh;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'DELETE at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
INSERT INTO utl_d_aim.faculty_work_hours
(pidm,
 report_year,
 group_type,
 group_code,
 average_weekly_workload,
 etl_date)
SELECT pidm,
       report_yr_desc AS report_year,
       'Year' AS group_type,
       report_yr_desc AS group_code,
       nvl((SUM(week_workload) * 2.25) / nullif(COUNT(DISTINCT CASE
                                                      WHEN week_workload > 0 THEN
                                                       week
                                                      END), 0), 0) AS average_weekly_workload,
       SYSDATE AS etl_date
  FROM (SELECT fwhd.pidm,
               fwhd.report_yr_desc,
               fwhd.dte AS week,
               nvl(MIN(day_load), 0) + nvl(MIN(thesis_load), 0) + nvl(MIN(im_load), 0) + nvl(MIN(sme_load), 0) + nvl(MIN(release_load), 0) AS week_workload
          FROM utl_d_aim.faculty_work_hours_detail fwhd
         GROUP BY fwhd.pidm,
                  fwhd.report_yr_desc,
                  fwhd.dte)
 GROUP BY pidm,
          report_yr_desc
HAVING nvl((SUM(week_workload) * 2.25) / nullif(COUNT(DISTINCT CASE WHEN week_workload > 0 THEN week END), 0), 0) > 0
UNION ALL
SELECT pidm,
       report_yr_desc AS report_year,
       'Semester' AS group_type,
       coalesce(course_term, release_term, report_term) AS group_code,
       nvl((SUM(week_workload) * 2.25) / nullif(COUNT(DISTINCT CASE
                                                      WHEN week_workload > 0 THEN
                                                       week
                                                      END), 0), 0) AS average_weekly_workload,
       SYSDATE AS etl_date
  FROM (SELECT fwhd.pidm,
               fwhd.report_term,
               fwhd.course_term,
               fwhd.release_term,
               fwhd.report_yr_desc,
               fwhd.dte AS week,
               nvl(MIN(day_load), 0) + nvl(MIN(thesis_load), 0) + nvl(MIN(im_load), 0) + nvl(MIN(sme_load), 0) + nvl(MIN(release_load), 0) AS week_workload
          FROM utl_d_aim.faculty_work_hours_detail fwhd
         GROUP BY fwhd.pidm,
                  fwhd.report_term,
                  fwhd.course_term,
                  fwhd.release_term,
                  fwhd.report_yr_desc,
                  fwhd.dte)
 GROUP BY pidm,
          coalesce(course_term, release_term, report_term),
          report_yr_desc
HAVING nvl((SUM(week_workload) * 2.25) / nullif(COUNT(DISTINCT CASE WHEN week_workload > 0 THEN week END), 0), 0) > 0;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
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
VERSION DATE        USERNAME       UPDATES
1.0     2020-10-22  lxhatfield     Initial release
1.1     2022-4-1    CWALSH1        Updated from and to date logic in YR WITH Statement per Kathy Bennett
---     05-17-2023  wgriffith2  --Dealing with EM courses and updating code to use job_log
------------------------------------------------------------------------------------------------*/
END etl_aim_faculty_work_hours_refresh;

procedure etl_aim_inplace_student_program(jobnumber number, processid varchar2, processname varchar2) is
--- PARAMS
v_etl_date     DATE := SYSDATE;
v_msg          VARCHAR2(255);
v_row_max      NUMBER := 1000000; -- max number of rows to be processed at one time
v_count        NUMBER := 0;
v_proc         VARCHAR2(100) := 'etl_aim_inplace_student_program';
-- cursors
CURSOR curs IS
select * from(
with progs as(
select prle.smrprle_program program                                               --Specify which programs to look for
from  zsaturn.ztvcoll coll
join smrprle prle on prle.smrprle_coll_code = coll.ext_coll_code
                 and prle.smrprle_program not in ('MNS2-MS-D','MNB2-MBA-D')
                 and prle.smrprle_degc_code not in ('PHD')
where coll.primary_coll_code = 'Y'
and coll.base_coll_code = 'NR'                 )

, students as (select * from                                                      --Return ALL student curriculum records in ZSAVLCUR for those programs
              (select lcur.pidm
                    , lcur.prog_code_1 prog_code
                    , lcur.prog_ctlg_1 prog_version
                    , lcur.current_ind current_ind
                    , lcur.from_term
                    , lcur.end_term
                    , rank() over (partition by lcur.pidm, lcur.prog_code_1, lcur.prog_ctlg_1 order by case when lcur.current_ind = 'Y' then 1 end, lcur.end_term desc) ranker
                 from progs

                join zexec.zsavlcur lcur on lcur.prog_code_1 = progs.program)
                where ranker = 1)                                                 --Rank by PIDM, PROG, and CTLG, looking only at program 1, to return most recent record with given program (avoid duplicates when student changes minors or something)
                                                                                  --From term is not used in INPlace, just end term, so most recent always works

select tbl.pidm
     , tbl.prog_code
     , tbl.prog_version
     , tbl.active_prog
     , tbl.graduated
     , tbl.discontinued
     , tbl.pidm||tbl.prog_code||tbl.prog_version insert_hash
     , tbl.active_prog||tbl.graduated||tbl.discontinued update_hash
     , sysdate activity_date
     , CASE
       WHEN stucomp.pidm IS NULL THEN
        'INSERT'
       when stucomp.pidm is not null then
        'UPDATE'
       ELSE
        'NONE'
       END AS control_state
     , COUNT(*) over() total_rows
  from
  (


select distinct
       students.pidm                                                       pidm
     , students.prog_code                                                  prog_code
     , students.prog_version                                               prog_version
     , students.current_ind                                                active_prog
     , nvl2(dgmr.shrdgmr_pidm, dgmr.shrdgmr_grad_date,null)                graduated
     , case when dgmr.shrdgmr_pidm is null --Show end term for ZSAVLCUR, or show their BR hold date
             and endterm.stvterm_code is not null then trunc(endterm.stvterm_end_date)
            when dgmr.shrdgmr_pidm is null
             and endterm.stvterm_code is null
             and hold.sprhold_pidm is not null then trunc(hold.sprhold_activity_date) else null end  discontinued --did student break enrollment without graduating

       from students
join(select max(term_code) as current_term
                                  from zbtm.terms_by_group_v
                                  where group_code = 'STD'
                                    and semester != 'WIN'
                                    and start_date <= sysdate) on 1=1


join stvterm term on term.stvterm_code = students.prog_version

join stvacyr acyr on acyr.stvacyr_code = term.stvterm_acyr_code

left join stvterm endterm on endterm.stvterm_code = students.end_term
                         and students.end_term < current_term

left join shrdgmr dgmr on dgmr.shrdgmr_pidm = students.pidm
                      and dgmr.shrdgmr_degs_code = 'AW'
                      and dgmr.shrdgmr_program = students.prog_code
                      and dgmr.shrdgmr_term_code_ctlg_1 = students.prog_version

left join sprhold hold on hold.sprhold_pidm = students.pidm
                      and hold.sprhold_hldd_code = 'BR'
                      and trunc(sysdate) between hold.sprhold_from_date and hold.sprhold_to_date

where 1=1
and (exists (select 'X' from zexec.zsavregs r --General request that we only look at students who have had registrations since 201940
             where r.reg_pidm = students.pidm
               and r.reg_term_code >= '201940')
 or exists (select 'X' from zexec.zsavlcur lcurchk
             where lcurchk.pidm = students.pidm
               and lcurchk.from_term >= '201940'
               and lcurchk.prog_code_1 = students.prog_code))

) tbl
left join utl_d_aim.inplace_student_program stucomp on stucomp.insert_hash = tbl.pidm||tbl.prog_code||tbl.prog_version);

TYPE rec_input_t IS TABLE OF curs%ROWTYPE;
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
start_time   TIMESTAMP;
end_time     TIMESTAMP;
select_count NUMBER := 0;
insert_count NUMBER := 0;
update_count NUMBER := 0;
delete_count NUMBER := 0;
start_t      DATE := SYSDATE;
elapsed      NUMBER := 0;
BEGIN
v_msg := 'Started at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss');
dbms_output.put_line(v_msg);
dbms_output.put_line(' --------- ');
--
OPEN curs;
LOOP
FETCH curs BULK COLLECT
INTO rec_input LIMIT v_row_max;
IF rec_input.count = 0 THEN
v_msg := 'No rows found in cursor... ';
dbms_output.put_line(v_msg);
v_msg := ' -- COMPLETED --';
dbms_output.put_line(v_msg);
RETURN;
ELSIF rec_input.count > 0 THEN
insert_dml := index_pointer_i();
update_dml := index_pointer_u();
delete_dml := index_pointer_d();
FOR idx IN rec_input.first .. rec_input.last
LOOP
v_count := rec_input(idx).total_rows;
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
END LOOP;
insert_count := insert_count + insert_dml.count;
update_count := update_count + update_dml.count;
delete_count := delete_count + delete_dml.count;
v_msg        := 'Query returned ' || v_count || ' rows';
dbms_output.put_line(v_msg);
-- DML INSERTS
v_msg := 'Inserts started at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss');
dbms_output.put_line(v_msg);
FORALL i IN VALUES OF insert_dml
INSERT INTO utl_d_aim.inplace_student_program tab
(pidm,
 prog_code,
 prog_version,
 active_prog,
 graduated,
 discontinued,
 insert_hash,
 update_hash,
 last_control_state)
VALUES
(rec_input(i).pidm,
 rec_input(i).prog_code,
 rec_input(i).prog_version,
 rec_input(i).active_prog,
 rec_input(i).graduated,
 rec_input(i).discontinued,
 rec_input(i).insert_hash,
 rec_input(i).update_hash,
 rec_input(i).control_state);
v_count := SQL%ROWCOUNT;
COMMIT;
v_msg := ' rows inserted: ' || v_count || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss');
dbms_output.put_line(v_msg);
-- DML UPDATES
v_msg := 'Updates started at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss');
dbms_output.put_line(v_msg);
FORALL i IN VALUES OF update_dml
UPDATE utl_d_aim.inplace_student_program tab
   SET (pidm,  prog_code, prog_version, active_prog, graduated, discontinued, insert_hash, update_hash, last_control_state, activity_date) =
       (SELECT rec_input(i).pidm,
               rec_input(i).prog_code,
               rec_input(i).prog_version,
               rec_input(i).active_prog,
               rec_input(i).graduated,
               rec_input(i).discontinued,
               rec_input(i).insert_hash,
               rec_input(i).update_hash,
               rec_input(i).control_state,
               rec_input(i).activity_date
          FROM dual)
 WHERE tab.insert_hash = rec_input(i).insert_hash
   and tab.update_hash != rec_input(i).update_hash;
v_count := SQL%ROWCOUNT;
COMMIT;
v_msg := ' rows updated: ' || v_count || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss');
dbms_output.put_line(v_msg);
-- DML DELETES
v_msg := 'Deletes started at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss');
dbms_output.put_line(v_msg);
FORALL i IN VALUES OF delete_dml
DELETE FROM utl_d_aim.inplace_student_program tab WHERE tab.insert_hash = rec_input(i).insert_hash;
v_count := SQL%ROWCOUNT;
COMMIT;
v_msg := ' rows processed: ' || v_count || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss');
dbms_output.put_line(v_msg);
dbms_output.put_line(' --------- ');
END IF;
SELECT ((CAST(SYSDATE AS DATE) - CAST(start_t AS DATE)) * 86400) INTO elapsed FROM dual;
select_count := select_count + rec_input.count;
EXIT WHEN(rec_input.count < v_row_max);
END LOOP;
CLOSE curs;
-- UPDATES ON THE ACTIVE RECORD HERE
/*update utl_d_aim.inplace_student_program stu
set active_prog = 'N'
where exists (SOLCUR)
-- */
-- log any errors
EXCEPTION
WHEN OTHERS THEN
v_msg := substr(SQLERRM, 1, 200);
dbms_output.put_line(v_msg);
/*--------------------------------------------CHANGE LOG----------------------------------------
VERSION  DATE        USERNAME    UPDATES
---    2/4/2022   CWALSH1   Initial Release
------------------------------------------------------------------------------------------------*/
END etl_aim_inplace_student_program;

procedure etl_aim_inplace_student_course(jobnumber number, processid varchar2, processname varchar2) is
--- PARAMS
v_etl_date     DATE := SYSDATE;
v_msg          VARCHAR2(255);
v_row_max      NUMBER := 1000000; -- max number of rows to be processed at one time
v_count        NUMBER := 0;
v_proc         VARCHAR2(100) := 'etl_aim_inplace_student_course';
v_update_line  VARCHAR2(255);
-- cursors
CURSOR curs IS
select base.pidm
     , base.prog_code
     , base.prog_version
     , base.subj
     , base.numb
     , base.crn
     , base.term_code
     , base.grade
     , base.active_crse
     , base.hash_check
     , sysdate activity_date
     , CASE
       WHEN stucomp.pidm IS NULL THEN
        'INSERT'
       when stucomp.pidm is not null then
        'UPDATE'
       ELSE
        'NONE'
       END AS control_state
     , COUNT(*) over() total_rows from
(select tbl.*
     , rank() over (partition by pidm||crn||term_code order by case when active_crse = 'Y' then 1 when active_crse = 'N' then 2 end) ranker --Ranks the unions records, giving a 1 to active records and ONLY giving 1 to inactive records if no active record comes back
  from (
select distinct stup.pidm
     , lcur.prog_code_1 prog_code
     , lcur.prog_ctlg_1 prog_version
     , c.subj
     , c.numb
     , c.crn
     , c.term_code
     , case when c.grde = 'IP' then null
            else decode(c.grde_passed,'Y','PASS','N','FAIL') end grade
     , 'Y' active_crse
     , stup.pidm||c.crn||c.term_code hash_check


  from utl_d_aim.inplace_student_program stup

  join (select min(t.term_code) reference_term --Pulls previous term up until 21 days after the end date
          FROM zbtm.terms_by_group_v t
         WHERE 1 = 1
           AND sysdate < t.end_date + 21
           AND group_code IN ('STD')
           and semester != 'WIN') on 1=1


  join zdegree_audit.davaudit v on v.pidm = stup.pidm
                             and v.prog_code = stup.prog_code
                             and v.prog_ctlg_term = stup.prog_version
                             and v.whatif_prog_ind = 'N'
                             and v.current_ind = 'Y'
                             and v.audit_term >= reference_term

join zdegree_audit.daaudit a on a.davaudit_id = v.davaudit_id
                            and a.req_met_rule_use_ind = 'Y'

join zdegree_audit.dacrsehistused u on u.davaudit_id = v.davaudit_id
                                   and u.used_daaudit_id = a.dacrserules_id

join zdegree_audit.dacrsehist c on c.davaudit_id = v.davaudit_id
                               and c.id = u.dacrsehist_id
                               and c.pseudo_eqiv_course_ind = 'N'
                               and c.test_code_ind = 'N'
                              and c.transfer_ind = 'N'
                              and c.term_code >= reference_term

join zexec.zsavlcur lcur on c.term_code between lcur.from_term and lcur.end_term --Connect the program they were in at the actual time of taking the course
                             and lcur.pidm = v.pidm
                             and lcur.prog_code_1 = v.prog_code
                             and lcur.prog_ctlg_1 = v.prog_ctlg_term

join zdegree_audit.davblocks b on b.blck_code = a.blck_code
                              and(b.majr_blck_ind = 'Y' --Major block, courses, or NURS courses
                               or b.blck_code in ('MJDIRECTCOUR','MJFOUNDCOUR')
                               or (c.subj = 'NURS'
                                 and b.meta_blck_ind = 'N'))

join saturn.ssbsect sect on sect.ssbsect_term_code = c.term_code --For 0 level courses, gets rid of any that are not tied to an associated lecture course
                        and sect.ssbsect_crn = c.crn
                        and sect.ssbsect_subj_code != 'NEWS'
                        and sect.ssbsect_ptrm_code != '1P'
                        and sect.ssbsect_subj_code||sect.ssbsect_crse_numb not in (
                      select distinct sect.ssbsect_subj_code||sect.ssbsect_crse_numb course
                      from saturn.ssbsect sect
                      where sect.ssbsect_crse_numb like '0%'
                        and not exists(select 1
                                       from saturn.scrrtst preq
                                       where preq.scrrtst_subj_code_preq = sect.ssbsect_subj_code
                                         and preq.scrrtst_crse_numb_preq = sect.ssbsect_crse_numb
                                         and preq.scrrtst_crse_numb not like '0%'
                                         and preq.scrrtst_term_code_eff = (select max(preq2.scrrtst_term_code_eff)
                                                                           from saturn.scrrtst preq2
                                                                           where preq2.scrrtst_subj_code = preq.scrrtst_subj_code
                                                                             and preq2.scrrtst_crse_numb = preq.scrrtst_crse_numb))
                        and sect.ssbsect_subj_code in ('NURS','MISC'))
  where (stup.active_prog = 'Y'
     or trunc(stup.activity_date) between trunc(sysdate - 21) and trunc(sysdate)
     or stup.prog_version >= reference_term) --Active students, or students who discontinued within 21 days, or students with future progs/courses --Active students, or students who discontinued within 21 days

union

 select distinct pidm
     , prog_code
     , prog_version
     , subj
     , numb
     , crn
     , term_code
     , grade
     , 'N' active_crse
     , pidm||crn||term_code hash_check
   from utl_d_aim.inplace_student_course stuc
    join (select min(t.term_code) reference_term
          FROM zbtm.terms_by_group_v t
         WHERE 1 = 1
           AND sysdate < t.end_date + 21
           AND group_code IN ('STD')
           and semester != 'WIN') on 1=1
  where stuc.term_code >= reference_term  ) tbl) base --Full pull of student courses from existing table. Ranked in wrapper to only pull N status if does not exist in audit record. Refrence terms are the same (21 days after)

left join utl_d_aim.inplace_student_course stucomp on stucomp.hash_check = base.hash_check
where ranker = 1;


TYPE rec_input_t IS TABLE OF curs%ROWTYPE;
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
start_time   TIMESTAMP;
end_time     TIMESTAMP;
select_count NUMBER := 0;
insert_count NUMBER := 0;
update_count NUMBER := 0;
delete_count NUMBER := 0;
start_t      DATE := SYSDATE;
elapsed      NUMBER := 0;
BEGIN
v_msg := 'Started at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss');
dbms_output.put_line(v_msg);
dbms_output.put_line(' --------- ');
OPEN curs;
LOOP
FETCH curs BULK COLLECT
INTO rec_input LIMIT v_row_max;
IF rec_input.count = 0 THEN
v_msg := 'No rows found in cursor... ';
dbms_output.put_line(v_msg);
v_msg := ' -- COMPLETED --';
dbms_output.put_line(v_msg);
RETURN;
ELSIF rec_input.count > 0 THEN
insert_dml := index_pointer_i();
update_dml := index_pointer_u();
delete_dml := index_pointer_d();
FOR idx IN rec_input.first .. rec_input.last
LOOP
v_count := rec_input(idx).total_rows;
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
END LOOP;
insert_count := insert_count + insert_dml.count;
update_count := update_count + update_dml.count;
delete_count := delete_count + delete_dml.count;
v_msg        := 'Query returned ' || v_count || ' rows';
dbms_output.put_line(v_msg);
-- DML INSERTS
v_msg := 'Inserts started at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss');
dbms_output.put_line(v_msg);
FORALL i IN VALUES OF insert_dml
INSERT INTO utl_d_aim.inplace_student_course tab
(pidm,
 prog_code,
 prog_version,
 subj,
 numb,
 crn,
 term_code,
 grade,
 active_crse,
 hash_check,
 last_control_state)
VALUES
(rec_input(i).pidm,
 rec_input(i).prog_code,
 rec_input(i).prog_version,
 rec_input(i).subj,
 rec_input(i).numb,
 rec_input(i).crn,
 rec_input(i).term_code,
 rec_input(i).grade,
 rec_input(i).active_crse,
 rec_input(i).hash_check,
 rec_input(i).control_state);
v_count := SQL%ROWCOUNT;
COMMIT;
v_msg := ' rows inserted: ' || v_count || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss');
dbms_output.put_line(v_msg);
-- DML UPDATES
v_msg := 'Updates started at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss');
dbms_output.put_line(v_msg);
FORALL i IN VALUES OF update_dml
UPDATE utl_d_aim.inplace_student_course tab
   SET (pidm, prog_code, prog_version, subj, numb, crn, term_code, grade, active_crse, hash_check, last_control_state, activity_date) =
       (SELECT rec_input(i).pidm,
               rec_input(i).prog_code,
               rec_input(i).prog_version,
               rec_input(i).subj,
               rec_input(i).numb,
               rec_input(i).crn,
               rec_input(i).term_code,
               rec_input(i).grade,
               rec_input(i).active_crse,
               rec_input(i).hash_check,
               rec_input(i).control_state,
               rec_input(i).activity_date
          FROM dual)
 WHERE tab.hash_check = rec_input(i).hash_check
   and (tab.grade != rec_input(i).grade
    or  tab.active_crse != rec_input(i).active_crse);
v_count := SQL%ROWCOUNT;
COMMIT;
v_msg := ' records updated: ' || v_count || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss');
dbms_output.put_line(v_msg);
-- DML DELETES
v_msg := 'Deletes started at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss');
dbms_output.put_line(v_msg);
FORALL i IN VALUES OF delete_dml
DELETE FROM utl_d_aim.inplace_student_course tab WHERE tab.hash_check = rec_input(i).hash_check;
v_count := SQL%ROWCOUNT;
COMMIT;
v_msg := ' rows deleted: ' || v_count || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss');
dbms_output.put_line(v_msg);
dbms_output.put_line(' --------- ');
END IF;
SELECT ((CAST(SYSDATE AS DATE) - CAST(start_t AS DATE)) * 86400) INTO elapsed FROM dual;
select_count := select_count + rec_input.count;
EXIT WHEN(rec_input.count < v_row_max);
END LOOP;
CLOSE curs;
-- UPDATES ON THE ACTIVE RECORD HERE
/*update utl_d_aim.inplace_student_program stu
set active_prog = 'N'
where exists (SOLCUR)
-- */
-- log any errors
EXCEPTION
WHEN OTHERS THEN
v_msg := substr(SQLERRM, 1, 200);
dbms_output.put_line(v_msg);
/*--------------------------------------------CHANGE LOG----------------------------------------
VERSION  DATE        USERNAME    UPDATES
---      2/4/2022    CWALSH1     Initial Release
1.1      4/29/2022   CWALSH1     Add >= logic for audit term = reference term line. Prevented future courses from pulling for students changing to different progs or ctlg years
------------------------------------------------------------------------------------------------*/
END etl_aim_inplace_student_course;


procedure etl_aim_disclosure_refresh (jobnumber number, processid varchar2, processname varchar2) is
/*
Table: utl_d_aim.state_licensure_meta; utl_d_aim.state_licensure_content; utl_d_aim.state_licensure_send_list

Primary Keys:
-
Unique index:
-
Purpose:
- Email table for sending state licensure agreements

Conditions:
-

*/
/*********************************************************
Author: Colin Walsh
Date: 05/10/2022
Associated Ticket:
Title: State Licensure Disclosures Email ETL
Description: Runs hourly to generate list of students who need to be notified of disclosures associated with their program
Notes:
-This replaced Lucy Hatfield's previous ETL under CEID 69236
- CEID 69236 is still used and date logic was used to separate 'old' logic sends from new sends
- Generic ID hash has changed, so does not line up with any 'old' send generic ID columns
- GOLIVE variable is the date used to mitigate above
- 3 main tables, meta, content, and send list
  -Meta is all combinations of programs and states we care about
  -Content is the actual content of each post, picking most 'relevant' post for a given combination (overcomes wordpress duplicate issue)
  -Send list will ONLY contain those who need to be sent to. No historical info
*********************************************************/
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
v_proc        VARCHAR2(100) := 'etl_aim_disclosure_refresh';
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
v_msg     := 'START - ' || v_instance || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
--BEGIN FULL REFRESH OF STATE LICENSURE META
utl_d_aim.truncate_table(v_table_name => 'state_licensure_meta');
INSERT INTO utl_d_aim.state_licensure_meta
(post_id,
 prog_meta_id,
 program,
 prog_pmd,
 state_meta_id,
 states,
 state_pmd,
 ranker) --all program/state combos we care about
WITH progs AS
 (SELECT progs.meta_id,
         progs.post_id,
         j2.program,
         progs.pmd prog_pmd
    FROM (SELECT /*+ materialize*/
           pmp.meta_id,
           pmp.post_id,
           pmp.meta_value,
           p.post_modified_z pmd
            FROM zwpress_online.wp_3_postmeta pmp
            JOIN zwpress_online.wp_3_posts p
              ON p.id = pmp.post_id
             AND p.post_parent = 0
             AND p.post_status = 'publish'
             AND p.post_type = 'licensure'
           WHERE pmp.meta_key = 'programs' --Programs for a given post ID
             AND dbms_lob.getlength(regexp_replace(pmp.meta_value, '\s|"|\[|\]')) != 0 --Actually has programs
          ) progs
   CROSS JOIN json_table(progs.meta_value, '$' columns(NESTED path '$[*]' columns(program VARCHAR2(12) path '$[*]'))) j2),
states AS
 (SELECT states.meta_id,
         states.post_id,
         j2.states,
         states.pmd state_pmd
    FROM (SELECT /*+ materialize*/
           pms.meta_id,
           pms.post_id,
           pms.meta_value,
           p.post_modified_z pmd
            FROM zwpress_online.wp_3_postmeta pms
            JOIN zwpress_online.wp_3_posts p
              ON p.id = pms.post_id
             AND p.post_parent = 0
             AND p.post_status = 'publish'
             AND p.post_type = 'licensure'
           WHERE pms.meta_key = 'states'
             AND dbms_lob.getlength(regexp_replace(pms.meta_value, '\s|"|\[|\]')) != 0 --Actually has States
          ) states
   CROSS JOIN json_table(states.meta_value, '$' columns(NESTED path '$[*]' columns(states VARCHAR2(12) path '$[*]'))) j2)
SELECT progs.post_id,
       progs.meta_id prog_meta_id,
       progs.program,
       progs.prog_pmd,
       states.meta_id state_meta_id,
       states.states,
       states.state_pmd,
       rank() over(PARTITION BY progs.program, states.states ORDER BY progs.prog_pmd DESC, states.state_pmd DESC, rownum) ranker
  FROM progs
  JOIN states
    ON states.post_id = progs.post_id
 WHERE progs.program IN (SELECT p.szvprle_program prog_code --Some programs use the wordpress site, but aren't licensure
                           FROM zexec.szvprle p
                          WHERE p.szvprle_licensure_ind = 'Y')
 ORDER BY progs.program,
          states.states;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || v_instance || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
------------------------------------------------------------------------------------------------------------------------------
--BEGIN FULL REFRESH OF STATE LICENSURE CONTENT
utl_d_aim.truncate_table(v_table_name => 'state_licensure_content');
INSERT INTO utl_d_aim.state_licensure_content
(post_id,
 post_status,
 post_modified,
 program,
 states,
 post_content,
 post_content_hash,
 full_hash,
 requirement_message_check,
 requirement_message,
 meta_ranker)
WITH base AS
 (SELECT p.id AS post_id,
         p.post_status AS post_status,
         trunc(CAST(to_timestamp(p.post_modified_z, 'YYYY-MM-DD HH24:MI:SS.FF') AS DATE)) AS post_modified, --2020-06-17 07:08:58.000000000
         slm.program,
         slm.states,
         to_clob(p.post_content) AS post_content,
         utl_d_aim.hash_clob(to_clob(p.post_content || pmr.meta_value)) AS post_content_hash,
         to_number(dbms_lob.substr(pmc.meta_value, 4000, 1)) AS requirement_message_check,
         to_char(dbms_lob.substr(pmr.meta_value, 4000, 1)) AS requirement_message,
         slm.ranker AS meta_ranker
    FROM zwpress_online.wp_3_posts p
    JOIN utl_d_aim.state_licensure_meta slm
      ON slm.post_id = p.id
    JOIN zwpress_online.wp_3_postmeta pmr
      ON pmr.post_id = p.id
     AND pmr.meta_key = 'requirement_message' --This is the dropdown option list from WP
    JOIN zwpress_online.wp_3_postmeta pmc
      ON pmc.post_id = p.id
     AND pmc.meta_key = 'requirement_message_check'
   WHERE p.post_parent = 0
     AND p.post_status = 'publish' --Indicates an 'active' post
     AND p.post_type = 'licensure')
SELECT base.post_id,
       base.post_status,
       base.post_modified,
       base.program,
       base.states,
       base.post_content,
       base.post_content_hash,
       utl_d_aim.hash_clob(to_clob(base.post_content_hash || program || states || base.post_id)) full_hash,
       base.requirement_message_check,
       base.requirement_message,
       base.meta_ranker
  FROM base;
--END FULL REFRESH OF STATE LICENSURE CONTENT
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || v_instance || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
---------------------------------------------------------------------
--BEGIN FULL REFRESH OF STATE LICENSURE SEND LIST
utl_d_aim.truncate_table(v_table_name => 'state_licensure_send_list');
INSERT INTO utl_d_aim.state_licensure_send_list
(post_id,
 pidm,
 program,
 stu_type,
 campus,
 requirement_message,
 coll_code,
 post_content,
 levl_code,
 major_group,
 major_degc_group,
 states,
 post_content_hash,
 full_hash,
 post_modified,
 requirement_message_check,
 meta_ranker)
WITH base_stu AS
 (SELECT /*+ materialize*/
   pidm,
   prog_code,
   ctlg_term
    FROM zexec.zsavlcur cur unpivot((prog_code, ctlg_term) FOR priority IN((prog_code_1, prog_ctlg_1) AS '1', (prog_code_2, prog_ctlg_2) AS '2', (prog_code_3, prog_ctlg_3) AS '3', (prog_code_4, prog_ctlg_4) AS '4', (prog_code_5, prog_ctlg_5) AS '5'))
   CROSS JOIN (SELECT MAX(term_code) AS current_term
                FROM zbtm.terms_by_group_v
               WHERE group_code = 'STD'
                 AND semester != 'WIN'
                 AND start_date <= SYSDATE)
   WHERE current_ind = 'Y' ),
stu AS
 (
  --Students who have matriculated within a program (attended courses under that prog)
  SELECT pidm,
          prog_code,
          ctlg_term,
          campus,
          levl_code,
          coll_code,
          stu_type
    FROM (SELECT pidm,
                   prog_code,
                   ctlg_term,
                   campus,
                   levl_code,
                   coll_code,
                   stu_type,
                   rank () over (partition by pidm, prog_code, ctlg_term order by case when stu_type = 'MATRIC' then 0 else 1 end) type_ranker
              FROM (SELECT DISTINCT /*+ materialize*/ base.pidm,
                                     base.prog_code,
                                     base.ctlg_term,
                                     prle.smrprle_camp_code campus,
                                     prle.smrprle_levl_code levl_code,
                                     prle.smrprle_coll_code coll_code,
                                     'MATRIC' stu_type
                       FROM base_stu base
                       JOIN smrprle prle
                         ON prle.smrprle_program = base.prog_code
                       JOIN zexec.szvprle p
                         ON p.szvprle_licensure_ind = 'Y'
                        AND p.szvprle_program = base.prog_code
                       JOIN utl_d_aim.szrcrse crse
                         ON crse.pidm = base.pidm
                        AND crse.ptrm_start <= SYSDATE
                        AND crse.ptrm_start >= (SELECT nvl(MAX(holdr.sprhold_from_date), crse.ptrm_start)
                                                  FROM saturn.sprhold holdr
                                                 WHERE holdr.sprhold_pidm = base.pidm
                                                   AND holdr.sprhold_hldd_code IN ('BD', 'BR', 'DC', 'EA')
                                                   AND holdr.sprhold_from_date <= SYSDATE)
                       JOIN utl_d_aim.szrenrl enrl
                         ON enrl.pidm = crse.pidm
                        AND enrl.term_code = crse.term_code
                        AND base.prog_code IN (enrl.prog_code_1, enrl.prog_code_2, enrl.prog_code_3, enrl.prog_code_4)
                       JOIN zsaturn.szrlevl l
                         ON l.szrlevl_levl_code = enrl.levl_code
                        AND l.szrlevl_is_univ = 'Y'
                        AND l.szrlevl_has_awardable_cred = 'Y'
                       LEFT JOIN saturn.sprhold hold
                         ON hold.sprhold_pidm = base.pidm
                        AND hold.sprhold_hldd_code IN ('BD', 'BR', 'DC', 'EA')
                        AND SYSDATE BETWEEN hold.sprhold_from_date AND hold.sprhold_to_date
                      WHERE hold.sprhold_pidm IS NULL
                     UNION ALL

                     -- Apps and Accepts who have not matriculated into their program
                     SELECT /*+ materialize*/
                      zsavappl_pidm pidm,
                      zsavappl_program prog_code,
                      zsavappl_term_code ctlg_term,
                      zsavappl_camp_code campus,
                      app.zsavappl_levl_code levl_code,
                      app.zsavappl_coll_code coll_code,
                      'APP' stu_type
                       FROM zexec.zsavappl app
                      CROSS JOIN (SELECT MAX(term_code) AS current_term
                                   FROM zbtm.terms_by_group_v
                                  WHERE group_code = 'STD'
                                    AND semester != 'WIN'
                                    AND start_date <= trunc(SYSDATE))
                       JOIN zexec.szvprle p
                         ON p.szvprle_licensure_ind = 'Y'
                        AND p.szvprle_program = zsavappl_program
                       JOIN zsaturn.szrlevl l
                         ON l.szrlevl_levl_code = app.zsavappl_levl_code
                        AND l.szrlevl_is_univ = 'Y'
                        AND l.szrlevl_has_awardable_cred = 'Y'
                      WHERE 1 = 1
                        --- WE DO NOT WANT TO RANK HERE. WE NEED ALL RELATED APPS
                        AND zsavappl_apst_code <> 'W'
                         AND coalesce(zsavappl_apdc_code, 'X') LIKE 'A%'--NOT IN ('RJ', 'IN', 'FA')
                        AND NOT EXISTS (SELECT 'X'
                               FROM utl_d_aim.szrcrse crse
                               JOIN utl_d_aim.szrenrl enrl
                                 ON enrl.pidm = crse.pidm
                                AND enrl.term_code = crse.term_code
                                AND app.zsavappl_program IN (enrl.prog_code_1, enrl.prog_code_2, enrl.prog_code_3, enrl.prog_code_4)
                              WHERE crse.pidm = app.zsavappl_pidm
                                AND crse.ptrm_start <= SYSDATE)
                      AND ((zsavappl_camp_code = 'D' AND zsavappl_appl_date >= trunc(SYSDATE) - 365) OR -- now only sends to luo accepted apps over the pass year and res accepted apps for a future term
                          (zsavappl_camp_code = 'R' AND zsavappl_term_code > current_term))))

   WHERE type_ranker = 1)
SELECT slc.post_id,
       stu.pidm,
       slc.program,
       stu.stu_type,
       stu.campus,
       slc.requirement_message,
       stu.coll_code,
       slc.post_content,
       stu.levl_code,
       pg.zfrlist_char_01            AS major_group,
       pg.zfrlist_char_02            AS major_degc_group,
       slc.states,
       slc.post_content_hash, --Not used in dedupe. Helpful for identifying matching content
       slc.full_hash, --combo of content hash (includes requirement message), program, state, and post ID
       slc.post_modified, --truncated day of last modified date
       slc.requirement_message_check,
       slc.meta_ranker
  FROM utl_d_aim.state_licensure_content slc
 CROSS JOIN (SELECT MAX(term_code) AS current_term
               FROM zbtm.terms_by_group_v
              WHERE group_code = 'STD'
                AND semester != 'WIN'
                AND start_date <= SYSDATE)
  JOIN stu
    ON stu.prog_code = slc.program
  JOIN zformdata.zfrlist pg
    ON pg.zfrlist_list_code = 'PROGRAM_GROUPS'
   AND pg.zfrlist_key1_code = stu.prog_code
  JOIN saturn.sgrchrt chrt
    ON chrt.sgrchrt_pidm = stu.pidm --State of student?
   AND nvl(chrt.sgrchrt_active_ind, 'N') != 'Y'
   AND (chrt.sgrchrt_term_code_eff = (SELECT MAX(chrt2.sgrchrt_term_code_eff)
                                        FROM saturn.sgrchrt chrt2
                                       WHERE chrt2.sgrchrt_pidm = chrt.sgrchrt_pidm
                                         AND chrt2.sgrchrt_term_code_eff <= greatest(current_term, stu.ctlg_term) --Lucy's old logic
                                       ) OR chrt.sgrchrt_term_code_eff > current_term)
   AND slc.states = substr(chrt.sgrchrt_chrt_code, -2)
  LEFT JOIN utl_d_pp.whsentmessagelog nsml
    ON nsml.pidm = stu.pidm
   AND nsml.campaignid IN (68592, 69236)
   AND nsml.generic_id = slc.full_hash
   AND nsml.activity_date >= to_date('5/10/2022', 'MM/DD/YYYY') --Leave hardcoded. Marks the switch from the old logic to new and helps with antijoin
  LEFT JOIN (select r.pidm
                   ,r.merge10
               from UTL_P_CLM.RECIPIENTS R
               JOIN UTL_P_CLM.TASKS TS ON TS.ID = R.TASK_ID -- changed not exists to left join for speed
                                      AND TS.ZCRMQUE_CAMPAIGN_NUMBER IN (68592,69236) --CEID
              WHERE 1=1
                AND R.UPLOADED = 'Z'
                AND R.INVD_CODE IS NULL) rddupe on rddupe.pidm = stu.pidm
                                               and rddupe.merge10 = slc.full_hash
  LEFT JOIN utl_d_luo.marketing_spam_blacklist spam on spam.spam_pidm = stu.pidm -- anyone in this table is getting cleaned out of centralist and should be excluded
 WHERE 1 = 1
   AND meta_ranker = 1
   AND ((post_modified >= to_date('5/10/2022', 'MM/DD/YYYY')  --Leave hardcoded. Marks the switch from the old logic to new and helps with antijoin
   AND nsml.pidm IS NULL) OR (stu_type = 'APP' AND nsml.pidm IS NULL))
   and rddupe.pidm is null
   and spam.spam_pidm is null
   /*AND NOT EXISTS (SELECT 'X' -- RECIPIENTS DEDUPE FOR PAST 10 DAYS -- old dedupe, leaving in case
                                FROM UTL_P_CLM.RECIPIENTS R
                                JOIN UTL_P_CLM.TASKS TS ON TS.ID = R.TASK_ID
                                                       AND TS.ZCRMQUE_CAMPAIGN_NUMBER IN (68592,69236) --CEID
                                WHERE R.PIDM = STU.PIDM
                                  AND R.MERGE10 = SLC.FULL_HASH
                                  AND R.UPLOADED = 'Z'
                                  AND R.INVD_CODE IS NULL) -- restrict date limit for applicants (Who have not reg or enrolled) within the last 18 months*/
 ORDER BY post_modified,
          post_id;
v_count := SQL%ROWCOUNT;

COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || v_instance || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
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
/*--------------------------------------------change log----------------------------------------
version    date        username       updates
1.0        05/10/2022  CWALSH1     initial release
---     05-17-2023  wgriffith2  --Dealing with EM courses and updating code to use job_log
---     05-03-2024  wgriffith2  --updated the wp_6_posts to wp_3_posts
---     06-10-2024  JWTUCKER1   --temp update to limit to apps over the last six months only.
---     06-24-2024  JWTUCKER1   --snip snap, snip snap...
---     09-26-2024  JWTUCKER1   --changed to accepted apps only and changed not exists left join for speed
------------------------------------------------------------------------------------------------*/
END etl_aim_disclosure_refresh;

procedure etl_aim_inplace_student_program_pch(jobnumber number, processid varchar2, processname varchar2) is
-- declare
--- PARAMS
v_etl_date     DATE := SYSDATE;
v_msg          VARCHAR2(255);
v_row_max      NUMBER := 1000000; -- max number of rows to be processed at one time
v_count        NUMBER := 0;
v_proc         VARCHAR2(100) := 'etl_aim_inplace_student_program_pch';
-- cursors
CURSOR curs IS
select * from(
with progs as(
select prle.smrprle_program program  , prle.smrprle_program_desc                                           --Specify which programs to look for
from  smrprle prle
where prle.smrprle_degc_code in ('MPH','MSPH','DRPH') -- added DRPH on 7/17/2025 per request
  --and substr(prle.smrprle_program,0,3) != 'MPC' --Removed per request of Linaya Graf on 2/17/2023
   )

, students as (select * from                                                      --Return ALL student curriculum records in ZSAVLCUR for those programs
              (select lcur.pidm
                    , lcur.prog_code_1 prog_code
                    , lcur.prog_ctlg_1 prog_version
                    , lcur.current_ind current_ind
                    , lcur.from_term
                    , lcur.end_term
                    , rank() over (partition by lcur.pidm, lcur.prog_code_1, lcur.prog_ctlg_1 order by case when lcur.current_ind = 'Y' then 1 end, lcur.end_term desc) ranker
                 from progs

                join zexec.zsavlcur lcur on lcur.prog_code_1 = progs.program)
                where ranker = 1)                                                 --Rank by PIDM, PROG, and CTLG, looking only at program 1, to return most recent record with given program (avoid duplicates when student changes minors or something)
                                                                                  --From term is not used in INPlace, just end term, so most recent always works

select tbl.pidm
     , tbl.prog_code
     , tbl.prog_version
     , case when tbl.graduated is not null then 'N'
            when tbl.discontinued is not null then 'N'
            else tbl.active_prog end active_prog
     , tbl.graduated
     , tbl.discontinued
     , tbl.pidm||tbl.prog_code||tbl.prog_version insert_hash
     , tbl.active_prog||tbl.graduated||tbl.discontinued update_hash
     , sysdate activity_date
     , CASE
       WHEN stucomp.pidm IS NULL THEN
        'INSERT'
       when stucomp.pidm is not null then
        'UPDATE'
       ELSE
        'NONE'
       END AS control_state
     , COUNT(*) over() total_rows
  from
  (


select distinct
       students.pidm                                                       pidm
     , students.prog_code                                                  prog_code
     , students.prog_version                                               prog_version
     , students.current_ind                                                active_prog
     , nvl2(dgmr.shrdgmr_pidm, dgmr.shrdgmr_grad_date,null)                graduated
     , case when dgmr.shrdgmr_pidm is null --Show end term for ZSAVLCUR, or show their BR hold date
             and endterm.stvterm_code is not null then trunc(endterm.stvterm_end_date)
            when dgmr.shrdgmr_pidm is null
             and endterm.stvterm_code is null
             and hold.sprhold_pidm is not null then trunc(hold.sprhold_activity_date) else null end  discontinued --did student break enrollment without graduating

       from students
join(select max(term_code) as current_term
                                  from zbtm.terms_by_group_v
                                  where group_code = 'STD'
                                    and semester != 'WIN'
                                    and start_date <= sysdate) on 1=1


join stvterm term on term.stvterm_code = students.prog_version

join stvacyr acyr on acyr.stvacyr_code = term.stvterm_acyr_code

left join stvterm endterm on endterm.stvterm_code = students.end_term
                         and students.end_term < current_term

left join shrdgmr dgmr on dgmr.shrdgmr_pidm = students.pidm
                      and dgmr.shrdgmr_degs_code = 'AW'
                      and dgmr.shrdgmr_program = students.prog_code
                      and dgmr.shrdgmr_term_code_ctlg_1 = students.prog_version

left join sprhold hold on hold.sprhold_pidm = students.pidm
                      and hold.sprhold_hldd_code = 'BR'
                      and trunc(sysdate) between hold.sprhold_from_date and hold.sprhold_to_date

where 1=1
and (exists (select 'X' from zexec.zsavregs r --General request that we only look at students who have had registrations since 201940
             where r.reg_pidm = students.pidm
               and r.reg_term_code >= '201940')
 or exists (select 'X' from zexec.zsavlcur lcurchk
             where lcurchk.pidm = students.pidm
               and lcurchk.from_term >= '201940' --Ctlg term better?
               and lcurchk.prog_code_1 = students.prog_code))

) tbl
left join utl_d_aim.inplace_student_program_pch stucomp on stucomp.insert_hash = tbl.pidm||tbl.prog_code||tbl.prog_version);

TYPE rec_input_t IS TABLE OF curs%ROWTYPE;
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
start_time   TIMESTAMP;
end_time     TIMESTAMP;
select_count NUMBER := 0;
insert_count NUMBER := 0;
update_count NUMBER := 0;
delete_count NUMBER := 0;
start_t      DATE := SYSDATE;
elapsed      NUMBER := 0;
BEGIN
v_msg := 'Started at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss');
dbms_output.put_line(v_msg);
dbms_output.put_line(' --------- ');
--
OPEN curs;
LOOP
FETCH curs BULK COLLECT
INTO rec_input LIMIT v_row_max;
IF rec_input.count = 0 THEN
v_msg := 'No rows found in cursor... ';
dbms_output.put_line(v_msg);
v_msg := ' -- COMPLETED --';
dbms_output.put_line(v_msg);
RETURN;
ELSIF rec_input.count > 0 THEN
insert_dml := index_pointer_i();
update_dml := index_pointer_u();
delete_dml := index_pointer_d();
FOR idx IN rec_input.first .. rec_input.last
LOOP
v_count := rec_input(idx).total_rows;
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
END LOOP;
insert_count := insert_count + insert_dml.count;
update_count := update_count + update_dml.count;
delete_count := delete_count + delete_dml.count;
v_msg        := 'Query returned ' || v_count || ' rows';
dbms_output.put_line(v_msg);
-- DML INSERTS
v_msg := 'Inserts started at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss');
dbms_output.put_line(v_msg);
FORALL i IN VALUES OF insert_dml
INSERT INTO utl_d_aim.inplace_student_program_pch tab
(pidm,
 prog_code,
 prog_version,
 active_prog,
 graduated,
 discontinued,
 insert_hash,
 update_hash,
 last_control_state)
VALUES
(rec_input(i).pidm,
 rec_input(i).prog_code,
 rec_input(i).prog_version,
 rec_input(i).active_prog,
 rec_input(i).graduated,
 rec_input(i).discontinued,
 rec_input(i).insert_hash,
 rec_input(i).update_hash,
 rec_input(i).control_state);
v_count := SQL%ROWCOUNT;
COMMIT;
v_msg := ' rows inserted: ' || v_count || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss');
dbms_output.put_line(v_msg);
-- DML UPDATES
v_msg := 'Updates started at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss');
dbms_output.put_line(v_msg);
FORALL i IN VALUES OF update_dml
UPDATE utl_d_aim.inplace_student_program_pch tab
   SET (pidm,  prog_code, prog_version, active_prog, graduated, discontinued, insert_hash, update_hash, last_control_state, activity_date) =
       (SELECT rec_input(i).pidm,
               rec_input(i).prog_code,
               rec_input(i).prog_version,
               rec_input(i).active_prog,
               rec_input(i).graduated,
               rec_input(i).discontinued,
               rec_input(i).insert_hash,
               rec_input(i).update_hash,
               rec_input(i).control_state,
               rec_input(i).activity_date
          FROM dual)
 WHERE tab.insert_hash = rec_input(i).insert_hash
   and tab.update_hash != rec_input(i).update_hash;
v_count := SQL%ROWCOUNT;
COMMIT;
v_msg := ' rows updated: ' || v_count || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss');
dbms_output.put_line(v_msg);
-- DML DELETES
v_msg := 'Deletes started at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss');
dbms_output.put_line(v_msg);
FORALL i IN VALUES OF delete_dml
DELETE FROM utl_d_aim.inplace_student_program_pch tab WHERE tab.insert_hash = rec_input(i).insert_hash;
v_count := SQL%ROWCOUNT;
COMMIT;
v_msg := ' rows processed: ' || v_count || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss');
dbms_output.put_line(v_msg);
dbms_output.put_line(' --------- ');
END IF;
SELECT ((CAST(SYSDATE AS DATE) - CAST(start_t AS DATE)) * 86400) INTO elapsed FROM dual;
select_count := select_count + rec_input.count;
EXIT WHEN(rec_input.count < v_row_max);
END LOOP;
CLOSE curs;
-- UPDATES ON THE ACTIVE RECORD HERE
/*update utl_d_aim.inplace_student_program_pch stu
set active_prog = 'N'
where exists (SOLCUR)
-- */
-- log any errors
EXCEPTION
WHEN OTHERS THEN
v_msg := substr(SQLERRM, 1, 200);
dbms_output.put_line(v_msg);
/*--------------------------------------------CHANGE LOG----------------------------------------
VERSION  DATE        USERNAME    UPDATES
---    7/14/2022   CWALSH1   Initial Release
1.1    2/17/2023   JWTUCKER1 Removed MPC Program Exclusion
------------------------------------------------------------------------------------------------*/
END etl_aim_inplace_student_program_pch;

--declare
procedure etl_aim_inplace_student_course_pch(jobnumber number, processid varchar2, processname varchar2) is
--- PARAMS
v_etl_date     DATE := SYSDATE;
v_msg          VARCHAR2(255);
v_row_max      NUMBER := 1000000; -- max number of rows to be processed at one time
v_count        NUMBER := 0;
v_proc         VARCHAR2(100) := 'etl_aim_inplace_student_course_pch';
v_update_line  VARCHAR2(255);
-- cursors
CURSOR curs IS
select base.pidm
     , base.prog_code
     , base.prog_version
     , base.subj
     , base.numb
     , base.crn
     , base.term_code
     , base.grade
     , base.active_crse
     , base.hash_check
     , sysdate activity_date
     , CASE
       WHEN stucomp.pidm IS NULL THEN
        'INSERT'
       when stucomp.pidm is not null then
        'UPDATE'
       ELSE
        'NONE'
       END AS control_state
     , COUNT(*) over() total_rows from
(select tbl.*
     , rank() over (partition by pidm||crn||term_code order by case when active_crse = 'Y' then 1 when active_crse = 'N' then 2 end) ranker --Ranks the unions records, giving a 1 to active records and ONLY giving 1 to inactive records if no active record comes back
  from (
  (
select distinct stup.pidm
     , lcur.prog_code_1 prog_code
     , lcur.prog_ctlg_1 prog_version
     , c.subj
     , c.numb
     , c.crn
     , c.term_code
     , case when c.grde = 'IP' then null
            else decode(c.grde_passed,'Y','PASS','N','FAIL') end grade
     , 'Y' active_crse
     , stup.pidm||c.crn||c.term_code hash_check


  from utl_d_aim.inplace_student_program_pch stup

  join (select min(t.term_code) reference_term --Pulls previous term up until 21 days after the end date
          FROM zbtm.terms_by_group_v t
         WHERE 1 = 1
           AND sysdate < t.end_date + 21
           AND group_code IN ('STD')
           and semester != 'WIN') on 1=1


  join zdegree_audit.davaudit v on v.pidm = stup.pidm
                             and v.prog_code = stup.prog_code
                             and v.prog_ctlg_term = stup.prog_version
                             and v.whatif_prog_ind = 'N'
                             and v.current_ind = 'Y'
                             and v.audit_term >= reference_term

join zdegree_audit.daaudit a on a.davaudit_id = v.davaudit_id
                            and a.req_met_rule_use_ind = 'Y'

join zdegree_audit.dacrsehistused u on u.davaudit_id = v.davaudit_id
                                   and u.used_daaudit_id = a.dacrserules_id

join zdegree_audit.dacrsehist c on c.davaudit_id = v.davaudit_id
                               and c.id = u.dacrsehist_id
                               and c.pseudo_eqiv_course_ind = 'N'
                               and c.test_code_ind = 'N'
                              and c.transfer_ind = 'N'
                              and c.term_code >= reference_term

join zexec.zsavlcur lcur on c.term_code between lcur.from_term and lcur.end_term --Connect the program they were in at the actual time of taking the course
                             and lcur.pidm = v.pidm
                             and lcur.prog_code_1 = v.prog_code
                             and lcur.prog_ctlg_1 = v.prog_ctlg_term

join zdegree_audit.davblocks b on b.blck_code = a.blck_code
                              and(b.majr_blck_ind = 'Y' --Major block, courses, or NURS courses
                               or b.blck_code in ('MJDIRECTCOUR','MJFOUNDCOUR'))
                           /*    or (c.subj = 'NURS'
                                 and b.meta_blck_ind = 'N'))*/

join saturn.ssbsect sect on sect.ssbsect_term_code = c.term_code --For 0 level courses, gets rid of any that are not tied to an associated lecture course
                        and sect.ssbsect_crn = c.crn
                        and sect.ssbsect_subj_code != 'NEWS'
                        and sect.ssbsect_ptrm_code != '1P'
                     /*   and sect.ssbsect_subj_code||sect.ssbsect_crse_numb not in (
                      select distinct sect.ssbsect_subj_code||sect.ssbsect_crse_numb course
                      from saturn.ssbsect sect
                      where sect.ssbsect_crse_numb like '0%'
                        and not exists(select 1
                                       from saturn.scrrtst preq
                                       where preq.scrrtst_subj_code_preq = sect.ssbsect_subj_code
                                         and preq.scrrtst_crse_numb_preq = sect.ssbsect_crse_numb
                                         and preq.scrrtst_crse_numb not like '0%'
                                         and preq.scrrtst_term_code_eff = (select max(preq2.scrrtst_term_code_eff)
                                                                           from saturn.scrrtst preq2
                                                                           where preq2.scrrtst_subj_code = preq.scrrtst_subj_code
                                                                             and preq2.scrrtst_crse_numb = preq.scrrtst_crse_numb))
                        and sect.ssbsect_subj_code in ('NURS','MISC'))*/
  where (stup.active_prog = 'Y'
     or trunc(stup.activity_date) between trunc(sysdate - 21) and trunc(sysdate)
     or stup.prog_version >= reference_term) --Active students, or students who discontinued within 21 days, or students with future progs/courses --Active students, or students who discontinued within 21 days


union
--Special union for pulling all course enrollments despite DCP requirements (still dependent on inplace_pch_program table)
select distinct stup.pidm
     , lcur.prog_code_1 prog_code
     , lcur.prog_ctlg_1 prog_version
     , crse.subj
     , crse.numb
     , crse.crn
     , crse.term_code
     , case when crse.final_grade = 'IP' then null
            else decode(g.shrgrde_passed_ind,'Y','PASS','N','FAIL') end grade
     , 'Y' active_crse
     , stup.pidm||crse.crn||crse.term_code hash_check


  from utl_d_aim.inplace_student_program_pch stup

   join (select min(t.term_code) reference_term --Pulls previous term up until 21 days after the end date
          FROM zbtm.terms_by_group_v t
         WHERE 1 = 1
           AND sysdate < t.end_date + 21
           AND group_code IN ('STD')
           and semester != 'WIN') on 1=1

   join utl_d_aim.szrenrl enrl on enrl.pidm = stup.pidm
                              and stup.prog_code = enrl.prog_code_1
                              and stup.prog_version = enrl.ctlg_term_1
                              and enrl.term_code >= reference_term

   join utl_d_aim.szrcrse crse on crse.pidm = enrl.pidm
                              and crse.term_code = enrl.term_code
                              and crse.term_code >= reference_term
                              and crse.course in (select zfrlist_key1_code from zformdata.zfrlist l --list of specific courses to include despite DCP requirements
                                                   where l.zfrlist_list_code = 'INPLACE_PCH_COURSES'
                                                     and l.zfrlist_active_yn = 'Y')
   JOIN zsaturn.szrlevl l ON l.szrlevl_levl_code = crse.levl_code
             AND l.szrlevl_is_univ = 'Y'
             AND l.szrlevl_has_awardable_cred = 'Y'

   join shrgrde g on g.shrgrde_code = crse.final_grade
                 and g.shrgrde_levl_code = crse.levl_code

join zexec.zsavlcur lcur on crse.term_code between lcur.from_term and lcur.end_term --Connect the program they were in at the actual time of taking the course
                             and lcur.pidm = enrl.pidm
                             and lcur.prog_code_1 = enrl.prog_code_1
                             and lcur.prog_ctlg_1 = enrl.ctlg_term_1

  where (stup.active_prog = 'Y'
     or trunc(stup.activity_date) between trunc(sysdate - 21) and trunc(sysdate)
     or stup.prog_version >= reference_term)

)

union

 select distinct pidm
     , prog_code
     , prog_version
     , subj
     , numb
     , crn
     , term_code
     , grade
     , 'N' active_crse
     , pidm||crn||term_code hash_check
   from utl_d_aim.inplace_student_course_pch stuc
    join (select min(t.term_code) reference_term
          FROM zbtm.terms_by_group_v t
         WHERE 1 = 1
           AND sysdate < t.end_date + 21
           AND group_code IN ('STD')
           and semester != 'WIN') on 1=1
  where stuc.term_code >= reference_term  ) tbl) base --Full pull of student courses from existing table. Ranked in wrapper to only pull N status if does not exist in audit record. Refrence terms are the same (21 days after)

left join utl_d_aim.inplace_student_course_pch stucomp on stucomp.hash_check = base.hash_check
where ranker = 1;


TYPE rec_input_t IS TABLE OF curs%ROWTYPE;
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
start_time   TIMESTAMP;
end_time     TIMESTAMP;
select_count NUMBER := 0;
insert_count NUMBER := 0;
update_count NUMBER := 0;
delete_count NUMBER := 0;
start_t      DATE := SYSDATE;
elapsed      NUMBER := 0;
BEGIN
v_msg := 'Started at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss');
dbms_output.put_line(v_msg);
dbms_output.put_line(' --------- ');
OPEN curs;
LOOP
FETCH curs BULK COLLECT
INTO rec_input LIMIT v_row_max;
IF rec_input.count = 0 THEN
v_msg := 'No rows found in cursor... ';
dbms_output.put_line(v_msg);
v_msg := ' -- COMPLETED --';
dbms_output.put_line(v_msg);
RETURN;
ELSIF rec_input.count > 0 THEN
insert_dml := index_pointer_i();
update_dml := index_pointer_u();
delete_dml := index_pointer_d();
FOR idx IN rec_input.first .. rec_input.last
LOOP
v_count := rec_input(idx).total_rows;
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
END LOOP;
insert_count := insert_count + insert_dml.count;
update_count := update_count + update_dml.count;
delete_count := delete_count + delete_dml.count;
v_msg        := 'Query returned ' || v_count || ' rows';
dbms_output.put_line(v_msg);
-- DML INSERTS
v_msg := 'Inserts started at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss');
dbms_output.put_line(v_msg);
FORALL i IN VALUES OF insert_dml
INSERT INTO utl_d_aim.inplace_student_course_pch tab
(pidm,
 prog_code,
 prog_version,
 subj,
 numb,
 crn,
 term_code,
 grade,
 active_crse,
 hash_check,
 last_control_state)
VALUES
(rec_input(i).pidm,
 rec_input(i).prog_code,
 rec_input(i).prog_version,
 rec_input(i).subj,
 rec_input(i).numb,
 rec_input(i).crn,
 rec_input(i).term_code,
 rec_input(i).grade,
 rec_input(i).active_crse,
 rec_input(i).hash_check,
 rec_input(i).control_state);
v_count := SQL%ROWCOUNT;
COMMIT;
v_msg := ' rows inserted: ' || v_count || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss');
dbms_output.put_line(v_msg);
-- DML UPDATES
v_msg := 'Updates started at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss');
dbms_output.put_line(v_msg);
FORALL i IN VALUES OF update_dml
UPDATE utl_d_aim.inplace_student_course_pch tab
   SET (pidm, prog_code, prog_version, subj, numb, crn, term_code, grade, active_crse, hash_check, last_control_state, activity_date) =
       (SELECT rec_input(i).pidm,
               rec_input(i).prog_code,
               rec_input(i).prog_version,
               rec_input(i).subj,
               rec_input(i).numb,
               rec_input(i).crn,
               rec_input(i).term_code,
               rec_input(i).grade,
               rec_input(i).active_crse,
               rec_input(i).hash_check,
               rec_input(i).control_state,
               rec_input(i).activity_date
          FROM dual)
 WHERE tab.hash_check = rec_input(i).hash_check
   and (tab.grade != rec_input(i).grade
    or  tab.active_crse != rec_input(i).active_crse);
v_count := SQL%ROWCOUNT;
COMMIT;
v_msg := ' records updated: ' || v_count || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss');
dbms_output.put_line(v_msg);
-- DML DELETES
v_msg := 'Deletes started at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss');
dbms_output.put_line(v_msg);
FORALL i IN VALUES OF delete_dml
DELETE FROM utl_d_aim.inplace_student_course_pch tab WHERE tab.hash_check = rec_input(i).hash_check;
v_count := SQL%ROWCOUNT;
COMMIT;
v_msg := ' rows deleted: ' || v_count || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss');
dbms_output.put_line(v_msg);
dbms_output.put_line(' --------- ');
END IF;
SELECT ((CAST(SYSDATE AS DATE) - CAST(start_t AS DATE)) * 86400) INTO elapsed FROM dual;
select_count := select_count + rec_input.count;
EXIT WHEN(rec_input.count < v_row_max);
END LOOP;
CLOSE curs;
-- UPDATES ON THE ACTIVE RECORD HERE
/*update utl_d_aim.inplace_student_program stu
set active_prog = 'N'
where exists (SOLCUR)
-- */
-- log any errors
EXCEPTION
WHEN OTHERS THEN
v_msg := substr(SQLERRM, 1, 200);
dbms_output.put_line(v_msg);
/*--------------------------------------------CHANGE LOG----------------------------------------
VERSION  DATE        USERNAME    UPDATES
---      2/4/2022    CWALSH1     Initial Release
1.1      4/29/2022   CWALSH1     Add >= logic for audit term = reference term line. Prevented future courses from pulling for students changing to different progs or ctlg years
1.2      2/17/2023   JWTUCKER1   Added union for including specific course enrollments despite DCP reqs
------------------------------------------------------------------------------------------------*/
END etl_aim_inplace_student_course_pch;

procedure etl_aim_banner_log_checks (jobnumber number, processid varchar2, processname varchar2) is
  /* *********************************************************************** */
/* ********* LIBERTY UNIVERSITY - Analytics and Decision Support ********* */
/* ********* OJBECT NAME: UTL_D_AIM....LOG_CHECK                 ********* */
/* ********* DESCRIPTION: Daily Refresh                          ********* */
/* ********* CREATED BY: Colin Walsh                             ********* */
/* ********* (See CHANGE LOG at bottom of file)                  ********* */
/* *********************************************************************** */
-- DECLARE
v_etl_date DATE := SYSDATE;
v_msg      VARCHAR2(2000);
v_instance VARCHAR2(50) := upper('ALL'); -- inst from the jams job; used for determining instance
v_partition NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
-- v_mod         NUMBER := 5; -- number of partitions to be created

v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_aim_banner_log_checks';
BEGIN
-- dbms_output.enable(buffer_size => NULL);
--
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
dbms_lock.sleep(1.0); -- pause second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
--SFBESTS
INSERT INTO utl_d_aim.sfbests_log_check
(sfbests_term_code,
 sfbests_ests_code,
 sfbests_start_date,
 sfbests_end_date,
 sfbests_activity_date,
 sfbests_surrogate_id,
 sfbests_version,
 sfbests_user_id,
 sfbests_data_origin,
 sfbests_vpdi_code,
 sfbests_log_type,
 etl_activity_date,
 hash_check)
SELECT coalesce(bantable.sfbests_term_code, custable.sfbests_term_code) sfbests_term_code,
       coalesce(bantable.sfbests_ests_code, custable.sfbests_ests_code) sfbests_ests_code,
       coalesce(bantable.sfbests_start_date, custable.sfbests_start_date) sfbests_start_date,
       coalesce(bantable.sfbests_end_date, custable.sfbests_end_date) sfbests_end_date,
       coalesce(bantable.sfbests_activity_date, custable.sfbests_activity_date) sfbests_activity_date,
       coalesce(bantable.sfbests_surrogate_id, custable.sfbests_surrogate_id) sfbests_surrogate_id,
       coalesce(bantable.sfbests_version, custable.sfbests_version) sfbests_version,
       coalesce(bantable.sfbests_user_id, custable.sfbests_user_id) sfbests_user_id,
       coalesce(bantable.sfbests_data_origin, custable.sfbests_data_origin) sfbests_data_origin,
       coalesce(bantable.sfbests_vpdi_code, custable.sfbests_vpdi_code) sfbests_vpdi_code,
       CASE
       WHEN custable.sfbests_surrogate_id IS NULL
            AND bantable.sfbests_surrogate_id IS NOT NULL THEN
        'INSERT'
       WHEN (custable.hash_check != bantable.hash_check AND NOT EXISTS (SELECT 'X'
                                                                          FROM utl_d_aim.sfbests_log_check lc
                                                                         WHERE lc.sfbests_surrogate_id = bantable.sfbests_surrogate_id
                                                                           AND lc.hash_check = bantable.hash_check)) THEN
        'UPDATE'
       WHEN (custable.sfbests_surrogate_id IS NOT NULL AND bantable.sfbests_surrogate_id IS NULL AND NOT EXISTS
             (SELECT 'X'
                FROM utl_d_aim.sfbests_log_check lc
               WHERE lc.sfbests_surrogate_id = custable.sfbests_surrogate_id
                 AND lc.sfbests_log_type = 'DELETE')) THEN
        'DELETE'
       END log_type,
       v_etl_date etl_activity_date,
       coalesce(bantable.hash_check, custable.hash_check) hash_check
  FROM (SELECT sfb.sfbests_term_code,
               sfb.sfbests_ests_code,
               sfb.sfbests_start_date,
               sfb.sfbests_end_date,
               sfb.sfbests_activity_date,
               sfb.sfbests_surrogate_id,
               sfb.sfbests_version,
               sfb.sfbests_user_id,
               sfb.sfbests_data_origin,
               sfb.sfbests_vpdi_code,
               ora_hash(sfb.sfbests_term_code || sfb.sfbests_ests_code || sfb.sfbests_start_date || sfb.sfbests_end_date || sfb.sfbests_activity_date || sfb.sfbests_version || sfb.sfbests_user_id || sfb.sfbests_data_origin ||
                        sfb.sfbests_vpdi_code) hash_check
          FROM sfbests sfb) bantable
  FULL JOIN utl_d_aim.sfbests_log_check custable
    ON custable.sfbests_surrogate_id = bantable.sfbests_surrogate_id
 WHERE (custable.sfbests_surrogate_id IS NULL AND bantable.sfbests_surrogate_id IS NOT NULL)
    OR (custable.sfbests_surrogate_id IS NOT NULL AND bantable.sfbests_surrogate_id IS NULL AND NOT EXISTS
        (SELECT 'X'
           FROM utl_d_aim.sfbests_log_check lc
          WHERE lc.sfbests_surrogate_id = custable.sfbests_surrogate_id
            AND lc.sfbests_log_type = 'DELETE')) --record DELETEd and not already logged
    OR (custable.hash_check != bantable.hash_check AND NOT EXISTS (SELECT 'X'
                                                                     FROM utl_d_aim.sfbests_log_check lc
                                                                    WHERE lc.sfbests_surrogate_id = bantable.sfbests_surrogate_id
                                                                      AND lc.hash_check = bantable.hash_check)); --record UPDATEd and hash not already logged
v_count := SQL%ROWCOUNT;
COMMIT;
dbms_lock.sleep(1.0); -- pause second
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - sfbests_log_check - at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
--SFBRFST
INSERT INTO utl_d_aim.sfbrfst_log_check
(sfbrfst_term_code,
 sfbrfst_ests_code,
 sfbrfst_from_date,
 sfbrfst_to_date,
 sfbrfst_tuit_refund,
 sfbrfst_fees_refund,
 sfbrfst_activity_date,
 sfbrfst_surrogate_id,
 sfbrfst_version,
 sfbrfst_user_id,
 sfbrfst_data_origin,
 sfbrfst_vpdi_code,
 sfbrfst_log_type,
 etl_activity_date,
 hash_check)
SELECT coalesce(custable.sfbrfst_term_code, bantable.sfbrfst_term_code) sfbrfst_term_code,
       coalesce(custable.sfbrfst_ests_code, bantable.sfbrfst_ests_code) sfbrfst_ests_code,
       coalesce(custable.sfbrfst_from_date, bantable.sfbrfst_from_date) sfbrfst_from_date,
       coalesce(custable.sfbrfst_to_date, bantable.sfbrfst_to_date) sfbrfst_to_date,
       coalesce(custable.sfbrfst_tuit_refund, bantable.sfbrfst_tuit_refund) sfbrfst_tuit_refund,
       coalesce(custable.sfbrfst_fees_refund, bantable.sfbrfst_fees_refund) sfbrfst_fees_refund,
       coalesce(custable.sfbrfst_activity_date, bantable.sfbrfst_activity_date) sfbrfst_activity_date,
       coalesce(custable.sfbrfst_surrogate_id, bantable.sfbrfst_surrogate_id) sfbrfst_surrogate_id,
       coalesce(custable.sfbrfst_version, bantable.sfbrfst_version) sfbrfst_version,
       coalesce(custable.sfbrfst_user_id, bantable.sfbrfst_user_id) sfbrfst_user_id,
       coalesce(custable.sfbrfst_data_origin, bantable.sfbrfst_data_origin) sfbrfst_data_origin,
       coalesce(custable.sfbrfst_vpdi_code, bantable.sfbrfst_vpdi_code) sfbrfst_vpdi_code,
       CASE
       WHEN custable.sfbrfst_surrogate_id IS NULL
            AND bantable.sfbrfst_surrogate_id IS NOT NULL THEN
        'INSERT'
       WHEN (custable.hash_check != bantable.hash_check AND NOT EXISTS (SELECT 'X'
                                                                          FROM utl_d_aim.sfbrfst_log_check lc
                                                                         WHERE lc.sfbrfst_surrogate_id = bantable.sfbrfst_surrogate_id
                                                                           AND lc.hash_check = bantable.hash_check)) THEN
        'UPDATE'
       WHEN (custable.sfbrfst_surrogate_id IS NOT NULL AND bantable.sfbrfst_surrogate_id IS NULL AND NOT EXISTS
             (SELECT 'X'
                FROM utl_d_aim.sfbrfst_log_check lc
               WHERE lc.sfbrfst_surrogate_id = custable.sfbrfst_surrogate_id
                 AND lc.sfbrfst_log_type = 'DELETE')) THEN
        'DELETE'
       END log_type,
       v_etl_date etl_activity_date,
       coalesce(bantable.hash_check, custable.hash_check) hash_check
  FROM (SELECT sfb.sfbrfst_term_code,
               sfb.sfbrfst_ests_code,
               sfb.sfbrfst_from_date,
               sfb.sfbrfst_to_date,
               sfb.sfbrfst_tuit_refund,
               sfb.sfbrfst_fees_refund,
               sfb.sfbrfst_activity_date,
               sfb.sfbrfst_surrogate_id,
               sfb.sfbrfst_version,
               sfb.sfbrfst_user_id,
               sfb.sfbrfst_data_origin,
               sfb.sfbrfst_vpdi_code,
               ora_hash(sfb.sfbrfst_term_code || sfb.sfbrfst_ests_code || sfb.sfbrfst_from_date || sfb.sfbrfst_to_date || sfb.sfbrfst_tuit_refund || sfb.sfbrfst_fees_refund || sfb.sfbrfst_activity_date ||
                        --  sfb.sfbrfst_surrogate_id||
                        sfb.sfbrfst_version || sfb.sfbrfst_user_id || sfb.sfbrfst_data_origin || sfb.sfbrfst_vpdi_code) hash_check
          FROM sfbrfst sfb) bantable
  FULL JOIN utl_d_aim.sfbrfst_log_check custable
    ON custable.sfbrfst_surrogate_id = bantable.sfbrfst_surrogate_id
 WHERE (custable.sfbrfst_surrogate_id IS NULL AND bantable.sfbrfst_surrogate_id IS NOT NULL)
    OR (custable.sfbrfst_surrogate_id IS NOT NULL AND bantable.sfbrfst_surrogate_id IS NULL AND NOT EXISTS
        (SELECT 'X'
           FROM utl_d_aim.sfbrfst_log_check lc
          WHERE lc.sfbrfst_surrogate_id = custable.sfbrfst_surrogate_id
            AND lc.sfbrfst_log_type = 'DELETE')) --record DELETEd and not already logged
    OR (custable.hash_check != bantable.hash_check AND NOT EXISTS (SELECT 'X'
                                                                     FROM utl_d_aim.sfbrfst_log_check lc
                                                                    WHERE lc.sfbrfst_surrogate_id = bantable.sfbrfst_surrogate_id
                                                                      AND lc.hash_check = bantable.hash_check)); --record UPDATEd and hash not already logged
v_count := SQL%ROWCOUNT;
COMMIT;
dbms_lock.sleep(1.0); -- pause second
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - sfbrfst_log_check - at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
--SFRCTRL
INSERT INTO utl_d_aim.sfrctrl_log_check
(sfrctrl_term_code_host,
 sfrctrl_seq_no,
 sfrctrl_begin_date,
 sfrctrl_end_date,
 sfrctrl_hour_begin,
 sfrctrl_hour_end,
 sfrctrl_pin_start,
 sfrctrl_pin_end,
 sfrctrl_last_nam_start,
 sfrctrl_last_nam_end,
 sfrctrl_stud_type_1,
 sfrctrl_stud_type_2,
 sfrctrl_stud_type_3,
 sfrctrl_stud_type_4,
 sfrctrl_stud_type_5,
 sfrctrl_levl_1,
 sfrctrl_levl_2,
 sfrctrl_levl_3,
 sfrctrl_levl_4,
 sfrctrl_levl_5,
 sfrctrl_coll_incl_excl,
 sfrctrl_coll_1,
 sfrctrl_coll_2,
 sfrctrl_coll_3,
 sfrctrl_coll_4,
 sfrctrl_coll_5,
 sfrctrl_degr_incl_excl,
 sfrctrl_degr_1,
 sfrctrl_degr_2,
 sfrctrl_degr_3,
 sfrctrl_degr_4,
 sfrctrl_degr_5,
 sfrctrl_dept_incl_excl,
 sfrctrl_dept_1,
 sfrctrl_dept_2,
 sfrctrl_dept_3,
 sfrctrl_dept_4,
 sfrctrl_dept_5,
 sfrctrl_cmps_incl_excl,
 sfrctrl_cmps_1,
 sfrctrl_cmps_2,
 sfrctrl_cmps_3,
 sfrctrl_cmps_4,
 sfrctrl_cmps_5,
 sfrctrl_cls_incl_excl,
 sfrctrl_cls_1,
 sfrctrl_cls_2,
 sfrctrl_cls_3,
 sfrctrl_cls_4,
 sfrctrl_cls_5,
 sfrctrl_majr_incl_excl,
 sfrctrl_majr_1,
 sfrctrl_majr_2,
 sfrctrl_majr_3,
 sfrctrl_majr_4,
 sfrctrl_majr_5,
 sfrctrl_earn_hrs_begin,
 sfrctrl_earn_hrs_end,
 sfrctrl_surrogate_id,
 sfrctrl_version,
 sfrctrl_user_id,
 sfrctrl_data_origin,
 sfrctrl_activity_date,
 sfrctrl_vpdi_code,
 sfrctrl_log_type,
 etl_activity_date,
 hash_check)
SELECT coalesce(bantable.sfrctrl_term_code_host, custable.sfrctrl_term_code_host),
       coalesce(bantable.sfrctrl_seq_no, custable.sfrctrl_seq_no),
       coalesce(bantable.sfrctrl_begin_date, custable.sfrctrl_begin_date),
       coalesce(bantable.sfrctrl_end_date, custable.sfrctrl_end_date),
       coalesce(bantable.sfrctrl_hour_begin, custable.sfrctrl_hour_begin),
       coalesce(bantable.sfrctrl_hour_end, custable.sfrctrl_hour_end),
       coalesce(bantable.sfrctrl_pin_start, custable.sfrctrl_pin_start),
       coalesce(bantable.sfrctrl_pin_end, custable.sfrctrl_pin_end),
       coalesce(bantable.sfrctrl_last_nam_start, custable.sfrctrl_last_nam_start),
       coalesce(bantable.sfrctrl_last_nam_end, custable.sfrctrl_last_nam_end),
       coalesce(bantable.sfrctrl_stud_type_1, custable.sfrctrl_stud_type_1),
       coalesce(bantable.sfrctrl_stud_type_2, custable.sfrctrl_stud_type_2),
       coalesce(bantable.sfrctrl_stud_type_3, custable.sfrctrl_stud_type_3),
       coalesce(bantable.sfrctrl_stud_type_4, custable.sfrctrl_stud_type_4),
       coalesce(bantable.sfrctrl_stud_type_5, custable.sfrctrl_stud_type_5),
       coalesce(bantable.sfrctrl_levl_1, custable.sfrctrl_levl_1),
       coalesce(bantable.sfrctrl_levl_2, custable.sfrctrl_levl_2),
       coalesce(bantable.sfrctrl_levl_3, custable.sfrctrl_levl_3),
       coalesce(bantable.sfrctrl_levl_4, custable.sfrctrl_levl_4),
       coalesce(bantable.sfrctrl_levl_5, custable.sfrctrl_levl_5),
       coalesce(bantable.sfrctrl_coll_incl_excl, custable.sfrctrl_coll_incl_excl),
       coalesce(bantable.sfrctrl_coll_1, custable.sfrctrl_coll_1),
       coalesce(bantable.sfrctrl_coll_2, custable.sfrctrl_coll_2),
       coalesce(bantable.sfrctrl_coll_3, custable.sfrctrl_coll_3),
       coalesce(bantable.sfrctrl_coll_4, custable.sfrctrl_coll_4),
       coalesce(bantable.sfrctrl_coll_5, custable.sfrctrl_coll_5),
       coalesce(bantable.sfrctrl_degr_incl_excl, custable.sfrctrl_degr_incl_excl),
       coalesce(bantable.sfrctrl_degr_1, custable.sfrctrl_degr_1),
       coalesce(bantable.sfrctrl_degr_2, custable.sfrctrl_degr_2),
       coalesce(bantable.sfrctrl_degr_3, custable.sfrctrl_degr_3),
       coalesce(bantable.sfrctrl_degr_4, custable.sfrctrl_degr_4),
       coalesce(bantable.sfrctrl_degr_5, custable.sfrctrl_degr_5),
       coalesce(bantable.sfrctrl_dept_incl_excl, custable.sfrctrl_dept_incl_excl),
       coalesce(bantable.sfrctrl_dept_1, custable.sfrctrl_dept_1),
       coalesce(bantable.sfrctrl_dept_2, custable.sfrctrl_dept_2),
       coalesce(bantable.sfrctrl_dept_3, custable.sfrctrl_dept_3),
       coalesce(bantable.sfrctrl_dept_4, custable.sfrctrl_dept_4),
       coalesce(bantable.sfrctrl_dept_5, custable.sfrctrl_dept_5),
       coalesce(bantable.sfrctrl_cmps_incl_excl, custable.sfrctrl_cmps_incl_excl),
       coalesce(bantable.sfrctrl_cmps_1, custable.sfrctrl_cmps_1),
       coalesce(bantable.sfrctrl_cmps_2, custable.sfrctrl_cmps_2),
       coalesce(bantable.sfrctrl_cmps_3, custable.sfrctrl_cmps_3),
       coalesce(bantable.sfrctrl_cmps_4, custable.sfrctrl_cmps_4),
       coalesce(bantable.sfrctrl_cmps_5, custable.sfrctrl_cmps_5),
       coalesce(bantable.sfrctrl_cls_incl_excl, custable.sfrctrl_cls_incl_excl),
       coalesce(bantable.sfrctrl_cls_1, custable.sfrctrl_cls_1),
       coalesce(bantable.sfrctrl_cls_2, custable.sfrctrl_cls_2),
       coalesce(bantable.sfrctrl_cls_3, custable.sfrctrl_cls_3),
       coalesce(bantable.sfrctrl_cls_4, custable.sfrctrl_cls_4),
       coalesce(bantable.sfrctrl_cls_5, custable.sfrctrl_cls_5),
       coalesce(bantable.sfrctrl_majr_incl_excl, custable.sfrctrl_majr_incl_excl),
       coalesce(bantable.sfrctrl_majr_1, custable.sfrctrl_majr_1),
       coalesce(bantable.sfrctrl_majr_2, custable.sfrctrl_majr_2),
       coalesce(bantable.sfrctrl_majr_3, custable.sfrctrl_majr_3),
       coalesce(bantable.sfrctrl_majr_4, custable.sfrctrl_majr_4),
       coalesce(bantable.sfrctrl_majr_5, custable.sfrctrl_majr_5),
       coalesce(bantable.sfrctrl_earn_hrs_begin, custable.sfrctrl_earn_hrs_begin),
       coalesce(bantable.sfrctrl_earn_hrs_end, custable.sfrctrl_earn_hrs_end),
       coalesce(bantable.sfrctrl_surrogate_id, custable.sfrctrl_surrogate_id),
       coalesce(bantable.sfrctrl_version, custable.sfrctrl_version),
       coalesce(bantable.sfrctrl_user_id, custable.sfrctrl_user_id),
       coalesce(bantable.sfrctrl_data_origin, custable.sfrctrl_data_origin),
       coalesce(bantable.sfrctrl_activity_date, custable.sfrctrl_activity_date),
       coalesce(bantable.sfrctrl_vpdi_code, custable.sfrctrl_vpdi_code),
       CASE
       WHEN custable.sfrctrl_surrogate_id IS NULL
            AND bantable.sfrctrl_surrogate_id IS NOT NULL THEN
        'INSERT'
       WHEN (custable.hash_check != bantable.hash_check AND NOT EXISTS (SELECT 'X'
                                                                          FROM utl_d_aim.sfrctrl_log_check lc
                                                                         WHERE lc.sfrctrl_surrogate_id = bantable.sfrctrl_surrogate_id
                                                                           AND lc.hash_check = bantable.hash_check)) THEN
        'UPDATE'
       WHEN (custable.sfrctrl_surrogate_id IS NOT NULL AND bantable.sfrctrl_surrogate_id IS NULL AND NOT EXISTS
             (SELECT 'X'
                FROM utl_d_aim.sfrctrl_log_check lc
               WHERE lc.sfrctrl_surrogate_id = custable.sfrctrl_surrogate_id
                 AND lc.sfrctrl_log_type = 'DELETE')) THEN
        'DELETE'
       END log_type,
       v_etl_date etl_activity_date,
       coalesce(bantable.hash_check, custable.hash_check) hash_check
  FROM (SELECT ct.sfrctrl_term_code_host,
               ct.sfrctrl_seq_no,
               ct.sfrctrl_begin_date,
               ct.sfrctrl_end_date,
               ct.sfrctrl_hour_begin,
               ct.sfrctrl_hour_end,
               ct.sfrctrl_pin_start,
               ct.sfrctrl_pin_end,
               ct.sfrctrl_last_nam_start,
               ct.sfrctrl_last_nam_end,
               ct.sfrctrl_stud_type_1,
               ct.sfrctrl_stud_type_2,
               ct.sfrctrl_stud_type_3,
               ct.sfrctrl_stud_type_4,
               ct.sfrctrl_stud_type_5,
               ct.sfrctrl_levl_1,
               ct.sfrctrl_levl_2,
               ct.sfrctrl_levl_3,
               ct.sfrctrl_levl_4,
               ct.sfrctrl_levl_5,
               ct.sfrctrl_coll_incl_excl,
               ct.sfrctrl_coll_1,
               ct.sfrctrl_coll_2,
               ct.sfrctrl_coll_3,
               ct.sfrctrl_coll_4,
               ct.sfrctrl_coll_5,
               ct.sfrctrl_degr_incl_excl,
               ct.sfrctrl_degr_1,
               ct.sfrctrl_degr_2,
               ct.sfrctrl_degr_3,
               ct.sfrctrl_degr_4,
               ct.sfrctrl_degr_5,
               ct.sfrctrl_dept_incl_excl,
               ct.sfrctrl_dept_1,
               ct.sfrctrl_dept_2,
               ct.sfrctrl_dept_3,
               ct.sfrctrl_dept_4,
               ct.sfrctrl_dept_5,
               ct.sfrctrl_cmps_incl_excl,
               ct.sfrctrl_cmps_1,
               ct.sfrctrl_cmps_2,
               ct.sfrctrl_cmps_3,
               ct.sfrctrl_cmps_4,
               ct.sfrctrl_cmps_5,
               ct.sfrctrl_cls_incl_excl,
               ct.sfrctrl_cls_1,
               ct.sfrctrl_cls_2,
               ct.sfrctrl_cls_3,
               ct.sfrctrl_cls_4,
               ct.sfrctrl_cls_5,
               ct.sfrctrl_majr_incl_excl,
               ct.sfrctrl_majr_1,
               ct.sfrctrl_majr_2,
               ct.sfrctrl_majr_3,
               ct.sfrctrl_majr_4,
               ct.sfrctrl_majr_5,
               ct.sfrctrl_earn_hrs_begin,
               ct.sfrctrl_earn_hrs_end,
               ct.sfrctrl_surrogate_id,
               ct.sfrctrl_version,
               ct.sfrctrl_user_id,
               ct.sfrctrl_data_origin,
               ct.sfrctrl_activity_date,
               ct.sfrctrl_vpdi_code,
               ora_hash(ct.sfrctrl_term_code_host || ct.sfrctrl_seq_no || ct.sfrctrl_begin_date || ct.sfrctrl_end_date || ct.sfrctrl_hour_begin || ct.sfrctrl_hour_end || ct.sfrctrl_pin_start || ct.sfrctrl_pin_end ||
                        ct.sfrctrl_last_nam_start || ct.sfrctrl_last_nam_end || ct.sfrctrl_stud_type_1 || ct.sfrctrl_stud_type_2 || ct.sfrctrl_stud_type_3 || ct.sfrctrl_stud_type_4 || ct.sfrctrl_stud_type_5 || ct.sfrctrl_levl_1 ||
                        ct.sfrctrl_levl_2 || ct.sfrctrl_levl_3 || ct.sfrctrl_levl_4 || ct.sfrctrl_levl_5 || ct.sfrctrl_coll_incl_excl || ct.sfrctrl_coll_1 || ct.sfrctrl_coll_2 || ct.sfrctrl_coll_3 || ct.sfrctrl_coll_4 || ct.sfrctrl_coll_5 ||
                        ct.sfrctrl_degr_incl_excl || ct.sfrctrl_degr_1 || ct.sfrctrl_degr_2 || ct.sfrctrl_degr_3 || ct.sfrctrl_degr_4 || ct.sfrctrl_degr_5 || ct.sfrctrl_dept_incl_excl || ct.sfrctrl_dept_1 || ct.sfrctrl_dept_2 ||
                        ct.sfrctrl_dept_3 || ct.sfrctrl_dept_4 || ct.sfrctrl_dept_5 || ct.sfrctrl_cmps_incl_excl || ct.sfrctrl_cmps_1 || ct.sfrctrl_cmps_2 || ct.sfrctrl_cmps_3 || ct.sfrctrl_cmps_4 || ct.sfrctrl_cmps_5 ||
                        ct.sfrctrl_cls_incl_excl || ct.sfrctrl_cls_1 || ct.sfrctrl_cls_2 || ct.sfrctrl_cls_3 || ct.sfrctrl_cls_4 || ct.sfrctrl_cls_5 || ct.sfrctrl_majr_incl_excl || ct.sfrctrl_majr_1 || ct.sfrctrl_majr_2 || ct.sfrctrl_majr_3 ||
                        ct.sfrctrl_majr_4 || ct.sfrctrl_majr_5 || ct.sfrctrl_earn_hrs_begin || ct.sfrctrl_earn_hrs_end ||
                        --    ct.sfrctrl_surrogate_id||
                        ct.sfrctrl_version || ct.sfrctrl_user_id || ct.sfrctrl_data_origin || ct.sfrctrl_activity_date || ct.sfrctrl_vpdi_code) hash_check
          FROM sfrctrl ct) bantable
  FULL JOIN utl_d_aim.sfrctrl_log_check custable
    ON custable.sfrctrl_surrogate_id = bantable.sfrctrl_surrogate_id
 WHERE (custable.sfrctrl_surrogate_id IS NULL AND bantable.sfrctrl_surrogate_id IS NOT NULL)
    OR (custable.sfrctrl_surrogate_id IS NOT NULL AND bantable.sfrctrl_surrogate_id IS NULL AND NOT EXISTS
        (SELECT 'X'
           FROM utl_d_aim.sfrctrl_log_check lc
          WHERE lc.sfrctrl_surrogate_id = custable.sfrctrl_surrogate_id
            AND lc.sfrctrl_log_type = 'DELETE')) --record DELETEd and not already logged
    OR (custable.hash_check != bantable.hash_check AND NOT EXISTS (SELECT 'X'
                                                                     FROM utl_d_aim.sfrctrl_log_check lc
                                                                    WHERE lc.sfrctrl_surrogate_id = bantable.sfrctrl_surrogate_id
                                                                      AND lc.hash_check = bantable.hash_check)); --record UPDATEd and hash not already logged
v_count := SQL%ROWCOUNT;
COMMIT;
dbms_lock.sleep(1.0); -- pause second
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - sfrctrl_log_check - at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
--SOBPTRM
INSERT INTO utl_d_aim.sobptrm_log_check
(sobptrm_term_code,
 sobptrm_ptrm_code,
 sobptrm_desc,
 sobptrm_start_date,
 sobptrm_end_date,
 sobptrm_reg_allowed,
 sobptrm_weeks,
 sobptrm_census_date,
 sobptrm_activity_date,
 sobptrm_sect_over_ind,
 sobptrm_census_2_date,
 sobptrm_mgrd_web_upd_ind,
 sobptrm_fgrd_web_upd_ind,
 sobptrm_waitlst_web_disp_ind,
 sobptrm_incomplete_ext_date,
 sobptrm_surrogate_id,
 sobptrm_version,
 sobptrm_user_id,
 sobptrm_data_origin,
 sobptrm_vpdi_code,
 sobptrm_final_grde_pub_date,
 sobptrm_det_grde_pub_date,
 sobptrm_reas_grde_pub_date,
 sobptrm_reas_det_grde_pub_date,
 sobptrm_score_open_date,
 sobptrm_score_cutoff_date,
 sobptrm_reas_score_open_date,
 sobptrm_reas_score_cutoff_date,
 sobptrm_enrl_cutoff_date,
 sobptrm_refund_cutoff_date,
 sobptrm_acad_cutoff_date,
 sobptrm_drop_cutoff_date,
 sobptrm_acad_cut_off_date,
 sobptrm_drop_cut_off_date,
 sobptrm_enrl_cut_off_date,
 sobptrm_refund_cut_off_date,
 sobptrm_log_type,
 etl_activity_date,
 hash_check)
SELECT coalesce(bantable.sobptrm_term_code, custable.sobptrm_term_code),
       coalesce(bantable.sobptrm_ptrm_code, custable.sobptrm_ptrm_code),
       coalesce(bantable.sobptrm_desc, custable.sobptrm_desc),
       coalesce(bantable.sobptrm_start_date, custable.sobptrm_start_date),
       coalesce(bantable.sobptrm_end_date, custable.sobptrm_end_date),
       coalesce(bantable.sobptrm_reg_allowed, custable.sobptrm_reg_allowed),
       coalesce(bantable.sobptrm_weeks, custable.sobptrm_weeks),
       coalesce(bantable.sobptrm_census_date, custable.sobptrm_census_date),
       coalesce(bantable.sobptrm_activity_date, custable.sobptrm_activity_date),
       coalesce(bantable.sobptrm_sect_over_ind, custable.sobptrm_sect_over_ind),
       coalesce(bantable.sobptrm_census_2_date, custable.sobptrm_census_2_date),
       coalesce(bantable.sobptrm_mgrd_web_upd_ind, custable.sobptrm_mgrd_web_upd_ind),
       coalesce(bantable.sobptrm_fgrd_web_upd_ind, custable.sobptrm_fgrd_web_upd_ind),
       coalesce(bantable.sobptrm_waitlst_web_disp_ind, custable.sobptrm_waitlst_web_disp_ind),
       coalesce(bantable.sobptrm_incomplete_ext_date, custable.sobptrm_incomplete_ext_date),
       coalesce(bantable.sobptrm_surrogate_id, custable.sobptrm_surrogate_id),
       coalesce(bantable.sobptrm_version, custable.sobptrm_version),
       coalesce(bantable.sobptrm_user_id, custable.sobptrm_user_id),
       coalesce(bantable.sobptrm_data_origin, custable.sobptrm_data_origin),
       coalesce(bantable.sobptrm_vpdi_code, custable.sobptrm_vpdi_code),
       coalesce(bantable.sobptrm_final_grde_pub_date, custable.sobptrm_final_grde_pub_date),
       coalesce(bantable.sobptrm_det_grde_pub_date, custable.sobptrm_det_grde_pub_date),
       coalesce(bantable.sobptrm_reas_grde_pub_date, custable.sobptrm_reas_grde_pub_date),
       coalesce(bantable.sobptrm_reas_det_grde_pub_date, custable.sobptrm_reas_det_grde_pub_date),
       coalesce(bantable.sobptrm_score_open_date, custable.sobptrm_score_open_date),
       coalesce(bantable.sobptrm_score_cutoff_date, custable.sobptrm_score_cutoff_date),
       coalesce(bantable.sobptrm_reas_score_open_date, custable.sobptrm_reas_score_open_date),
       coalesce(bantable.sobptrm_reas_score_cutoff_date, custable.sobptrm_reas_score_cutoff_date),
       coalesce(bantable.sobptrm_enrl_cutoff_date, custable.sobptrm_enrl_cutoff_date),
       coalesce(bantable.sobptrm_refund_cutoff_date, custable.sobptrm_refund_cutoff_date),
       coalesce(bantable.sobptrm_acad_cutoff_date, custable.sobptrm_acad_cutoff_date),
       coalesce(bantable.sobptrm_drop_cutoff_date, custable.sobptrm_drop_cutoff_date),
       coalesce(bantable.sobptrm_acad_cut_off_date, custable.sobptrm_acad_cut_off_date),
       coalesce(bantable.sobptrm_drop_cut_off_date, custable.sobptrm_drop_cut_off_date),
       coalesce(bantable.sobptrm_enrl_cut_off_date, custable.sobptrm_enrl_cut_off_date),
       coalesce(bantable.sobptrm_refund_cut_off_date, custable.sobptrm_refund_cut_off_date),
       CASE
       WHEN custable.sobptrm_surrogate_id IS NULL
            AND bantable.sobptrm_surrogate_id IS NOT NULL THEN
        'INSERT'
       WHEN (custable.hash_check != bantable.hash_check AND NOT EXISTS (SELECT 'X'
                                                                          FROM utl_d_aim.sobptrm_log_check lc
                                                                         WHERE lc.sobptrm_surrogate_id = bantable.sobptrm_surrogate_id
                                                                           AND lc.hash_check = bantable.hash_check)) THEN
        'UPDATE'
       WHEN (custable.sobptrm_surrogate_id IS NOT NULL AND bantable.sobptrm_surrogate_id IS NULL AND NOT EXISTS
             (SELECT 'X'
                FROM utl_d_aim.sobptrm_log_check lc
               WHERE lc.sobptrm_surrogate_id = custable.sobptrm_surrogate_id
                 AND lc.sobptrm_log_type = 'DELETE')) THEN
        'DELETE'
       END log_type,
       v_etl_date etl_activity_date,
       coalesce(bantable.hash_check, custable.hash_check) hash_check
  FROM (SELECT ptrm.sobptrm_term_code,
               ptrm.sobptrm_ptrm_code,
               ptrm.sobptrm_desc,
               ptrm.sobptrm_start_date,
               ptrm.sobptrm_end_date,
               ptrm.sobptrm_reg_allowed,
               ptrm.sobptrm_weeks,
               ptrm.sobptrm_census_date,
               ptrm.sobptrm_activity_date,
               ptrm.sobptrm_sect_over_ind,
               ptrm.sobptrm_census_2_date,
               ptrm.sobptrm_mgrd_web_upd_ind,
               ptrm.sobptrm_fgrd_web_upd_ind,
               ptrm.sobptrm_waitlst_web_disp_ind,
               ptrm.sobptrm_incomplete_ext_date,
               ptrm.sobptrm_surrogate_id,
               ptrm.sobptrm_version,
               ptrm.sobptrm_user_id,
               ptrm.sobptrm_data_origin,
               ptrm.sobptrm_vpdi_code,
               ptrm.sobptrm_final_grde_pub_date,
               ptrm.sobptrm_det_grde_pub_date,
               ptrm.sobptrm_reas_grde_pub_date,
               ptrm.sobptrm_reas_det_grde_pub_date,
               ptrm.sobptrm_score_open_date,
               ptrm.sobptrm_score_cutoff_date,
               ptrm.sobptrm_reas_score_open_date,
               ptrm.sobptrm_reas_score_cutoff_date,
               ptrm.sobptrm_enrl_cutoff_date,
               ptrm.sobptrm_refund_cutoff_date,
               ptrm.sobptrm_acad_cutoff_date,
               ptrm.sobptrm_drop_cutoff_date,
               ptrm.sobptrm_acad_cut_off_date,
               ptrm.sobptrm_drop_cut_off_date,
               ptrm.sobptrm_enrl_cut_off_date,
               ptrm.sobptrm_refund_cut_off_date,
               ora_hash(ptrm.sobptrm_term_code || ptrm.sobptrm_ptrm_code || ptrm.sobptrm_desc || ptrm.sobptrm_start_date || ptrm.sobptrm_end_date || ptrm.sobptrm_reg_allowed || ptrm.sobptrm_weeks || ptrm.sobptrm_census_date ||
                        ptrm.sobptrm_activity_date || ptrm.sobptrm_sect_over_ind || ptrm.sobptrm_census_2_date || ptrm.sobptrm_mgrd_web_upd_ind || ptrm.sobptrm_fgrd_web_upd_ind || ptrm.sobptrm_waitlst_web_disp_ind ||
                        ptrm.sobptrm_incomplete_ext_date ||
                        --ptrm.sobptrm_surrogate_id||
                        ptrm.sobptrm_version || ptrm.sobptrm_user_id || ptrm.sobptrm_data_origin || ptrm.sobptrm_vpdi_code || ptrm.sobptrm_final_grde_pub_date || ptrm.sobptrm_det_grde_pub_date || ptrm.sobptrm_reas_grde_pub_date ||
                        ptrm.sobptrm_reas_det_grde_pub_date || ptrm.sobptrm_score_open_date || ptrm.sobptrm_score_cutoff_date || ptrm.sobptrm_reas_score_open_date || ptrm.sobptrm_reas_score_cutoff_date || ptrm.sobptrm_enrl_cutoff_date ||
                        ptrm.sobptrm_refund_cutoff_date || ptrm.sobptrm_acad_cutoff_date || ptrm.sobptrm_drop_cutoff_date || ptrm.sobptrm_acad_cut_off_date || ptrm.sobptrm_drop_cut_off_date || ptrm.sobptrm_enrl_cut_off_date ||
                        ptrm.sobptrm_refund_cut_off_date) hash_check
          FROM sobptrm ptrm) bantable
  FULL JOIN utl_d_aim.sobptrm_log_check custable
    ON custable.sobptrm_surrogate_id = bantable.sobptrm_surrogate_id
 WHERE (custable.sobptrm_surrogate_id IS NULL AND bantable.sobptrm_surrogate_id IS NOT NULL)
    OR (custable.sobptrm_surrogate_id IS NOT NULL AND bantable.sobptrm_surrogate_id IS NULL AND NOT EXISTS
        (SELECT 'X'
           FROM utl_d_aim.sobptrm_log_check lc
          WHERE lc.sobptrm_surrogate_id = custable.sobptrm_surrogate_id
            AND lc.sobptrm_log_type = 'DELETE')) --record DELETEd and not already logged
    OR (custable.hash_check != bantable.hash_check AND NOT EXISTS (SELECT 'X'
                                                                     FROM utl_d_aim.sobptrm_log_check lc
                                                                    WHERE lc.sobptrm_surrogate_id = bantable.sobptrm_surrogate_id
                                                                      AND lc.hash_check = bantable.hash_check)); --record UPDATEd and hash not already logged
v_count := SQL%ROWCOUNT;
COMMIT;
dbms_lock.sleep(1.0); -- pause second
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - sobptrm_log_check - at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
/*
INSERT INTO utl_d_aim.ssrxlst_log_check
(ssrxlst_term_code,
 ssrxlst_xlst_group,
 ssrxlst_crn,
 ssrxlst_activity_date,
 ssrxlst_surrogate_id,
 ssrxlst_version,
 ssrxlst_user_id,
 ssrxlst_data_origin,
 ssrxlst_vpdi_code,
 ssrxlst_log_type,
 etl_activity_date,
 hash_check)
SELECT coalesce(bantable.ssrxlst_term_code, custable.ssrxlst_term_code),
       coalesce(bantable.ssrxlst_xlst_group, custable.ssrxlst_xlst_group),
       coalesce(bantable.ssrxlst_crn, custable.ssrxlst_crn),
       coalesce(bantable.ssrxlst_activity_date, custable.ssrxlst_activity_date),
       coalesce(bantable.ssrxlst_surrogate_id, custable.ssrxlst_surrogate_id),
       coalesce(bantable.ssrxlst_version, custable.ssrxlst_version),
       coalesce(bantable.ssrxlst_user_id, custable.ssrxlst_user_id),
       coalesce(bantable.ssrxlst_data_origin, custable.ssrxlst_data_origin),
       coalesce(bantable.ssrxlst_vpdi_code, custable.ssrxlst_vpdi_code),
       CASE
       WHEN custable.ssrxlst_surrogate_id IS NULL
            AND bantable.ssrxlst_surrogate_id IS NOT NULL THEN
        'INSERT'
       WHEN (custable.hash_check != bantable.hash_check AND NOT EXISTS (SELECT 'X'
                                                                          FROM utl_d_aim.ssrxlst_log_check lc
                                                                         WHERE lc.ssrxlst_surrogate_id = bantable.ssrxlst_surrogate_id
                                                                           AND lc.hash_check = bantable.hash_check)) THEN
        'UPDATE'
       WHEN (custable.ssrxlst_surrogate_id IS NOT NULL AND bantable.ssrxlst_surrogate_id IS NULL AND NOT EXISTS
             (SELECT 'X'
                FROM utl_d_aim.ssrxlst_log_check lc
               WHERE lc.ssrxlst_surrogate_id = custable.ssrxlst_surrogate_id
                 AND lc.ssrxlst_log_type = 'DELETE')) THEN
        'DELETE'
       END log_type,
       SYSDATE etl_activity_date,
       coalesce(bantable.hash_check, custable.hash_check) hash_check
  FROM (SELECT t.ssrxlst_term_code,
               t.ssrxlst_xlst_group,
               t.ssrxlst_crn,
               t.ssrxlst_activity_date,
               t.ssrxlst_surrogate_id,
               t.ssrxlst_version,
               t.ssrxlst_user_id,
               t.ssrxlst_data_origin,
               t.ssrxlst_vpdi_code,
               ora_hash(t.ssrxlst_term_code || t.ssrxlst_xlst_group || t.ssrxlst_crn || t.ssrxlst_activity_date || t.ssrxlst_surrogate_id || t.ssrxlst_version || t.ssrxlst_user_id || t.ssrxlst_data_origin || t.ssrxlst_vpdi_code) hash_check
          FROM ssrxlst t) bantable
  FULL JOIN utl_d_aim.ssrxlst_log_check custable
    ON custable.ssrxlst_surrogate_id = bantable.ssrxlst_surrogate_id
 WHERE (custable.ssrxlst_surrogate_id IS NULL AND bantable.ssrxlst_surrogate_id IS NOT NULL)
    OR (custable.ssrxlst_surrogate_id IS NOT NULL AND bantable.ssrxlst_surrogate_id IS NULL AND NOT EXISTS
        (SELECT 'X'
           FROM utl_d_aim.ssrxlst_log_check lc
          WHERE lc.ssrxlst_surrogate_id = custable.ssrxlst_surrogate_id
            AND lc.ssrxlst_log_type = 'DELETE')) --record DELETEd and not already logged
    OR (custable.hash_check != bantable.hash_check AND NOT EXISTS (SELECT 'X'
                                                                     FROM utl_d_aim.ssrxlst_log_check lc
                                                                    WHERE lc.ssrxlst_surrogate_id = bantable.ssrxlst_surrogate_id
                                                                      AND lc.hash_check = bantable.hash_check)); --record UPDATEd and hash not already logged
v_count := SQL%ROWCOUNT;
COMMIT;
dbms_lock.sleep(1.0); -- pause second
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ssrxlst_log_check - at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
INSERT INTO utl_d_aim.ssbsect_log_check
SELECT coalesce(bantable.ssbsect_term_code, custable.ssbsect_term_code) AS ssbsect_term_code,
       coalesce(bantable.ssbsect_crn, custable.ssbsect_crn) AS ssbsect_crn,
       coalesce(bantable.ssbsect_ptrm_code, custable.ssbsect_ptrm_code) AS ssbsect_ptrm_code,
       coalesce(bantable.ssbsect_subj_code, custable.ssbsect_subj_code) AS ssbsect_subj_code,
       coalesce(bantable.ssbsect_crse_numb, custable.ssbsect_crse_numb) AS ssbsect_crse_numb,
       coalesce(bantable.ssbsect_seq_numb, custable.ssbsect_seq_numb) AS ssbsect_seq_numb,
       coalesce(bantable.ssbsect_ssts_code, custable.ssbsect_ssts_code) AS ssbsect_ssts_code,
       coalesce(bantable.ssbsect_schd_code, custable.ssbsect_schd_code) AS ssbsect_schd_code,
       coalesce(bantable.ssbsect_camp_code, custable.ssbsect_camp_code) AS ssbsect_camp_code,
       coalesce(bantable.ssbsect_crse_title, custable.ssbsect_crse_title) AS ssbsect_crse_title,
       coalesce(bantable.ssbsect_credit_hrs, custable.ssbsect_credit_hrs) AS ssbsect_credit_hrs,
       coalesce(bantable.ssbsect_bill_hrs, custable.ssbsect_bill_hrs) AS ssbsect_bill_hrs,
       coalesce(bantable.ssbsect_gmod_code, custable.ssbsect_gmod_code) AS ssbsect_gmod_code,
       coalesce(bantable.ssbsect_sapr_code, custable.ssbsect_sapr_code) AS ssbsect_sapr_code,
       coalesce(bantable.ssbsect_sess_code, custable.ssbsect_sess_code) AS ssbsect_sess_code,
       coalesce(bantable.ssbsect_link_ident, custable.ssbsect_link_ident) AS ssbsect_link_ident,
       coalesce(bantable.ssbsect_prnt_ind, custable.ssbsect_prnt_ind) AS ssbsect_prnt_ind,
       coalesce(bantable.ssbsect_gradable_ind, custable.ssbsect_gradable_ind) AS ssbsect_gradable_ind,
       coalesce(bantable.ssbsect_tuiw_ind, custable.ssbsect_tuiw_ind) AS ssbsect_tuiw_ind,
       coalesce(bantable.ssbsect_prior_enrl, custable.ssbsect_prior_enrl) AS ssbsect_prior_enrl,
       coalesce(bantable.ssbsect_proj_enrl, custable.ssbsect_proj_enrl) AS ssbsect_proj_enrl,
       coalesce(bantable.ssbsect_max_enrl, custable.ssbsect_max_enrl) AS ssbsect_max_enrl,
       coalesce(bantable.ssbsect_census_enrl_date, custable.ssbsect_census_enrl_date) AS ssbsect_census_enrl_date,
       coalesce(bantable.ssbsect_ptrm_start_date, custable.ssbsect_ptrm_start_date) AS ssbsect_ptrm_start_date,
       coalesce(bantable.ssbsect_ptrm_end_date, custable.ssbsect_ptrm_end_date) AS ssbsect_ptrm_end_date,
       coalesce(bantable.ssbsect_ptrm_weeks, custable.ssbsect_ptrm_weeks) AS ssbsect_ptrm_weeks,
       coalesce(bantable.ssbsect_reserved_ind, custable.ssbsect_reserved_ind) AS ssbsect_reserved_ind,
       coalesce(bantable.ssbsect_lec_hr, custable.ssbsect_lec_hr) AS ssbsect_lec_hr,
       coalesce(bantable.ssbsect_lab_hr, custable.ssbsect_lab_hr) AS ssbsect_lab_hr,
       coalesce(bantable.ssbsect_oth_hr, custable.ssbsect_oth_hr) AS ssbsect_oth_hr,
       coalesce(bantable.ssbsect_cont_hr, custable.ssbsect_cont_hr) AS ssbsect_cont_hr,
       coalesce(bantable.ssbsect_acct_code, custable.ssbsect_acct_code) AS ssbsect_acct_code,
       coalesce(bantable.ssbsect_accl_code, custable.ssbsect_accl_code) AS ssbsect_accl_code,
       coalesce(bantable.ssbsect_census_2_date, custable.ssbsect_census_2_date) AS ssbsect_census_2_date,
       coalesce(bantable.ssbsect_enrl_cut_off_date, custable.ssbsect_enrl_cut_off_date) AS ssbsect_enrl_cut_off_date,
       coalesce(bantable.ssbsect_acad_cut_off_date, custable.ssbsect_acad_cut_off_date) AS ssbsect_acad_cut_off_date,
       coalesce(bantable.ssbsect_drop_cut_off_date, custable.ssbsect_drop_cut_off_date) AS ssbsect_drop_cut_off_date,
       coalesce(bantable.ssbsect_census_2_enrl, custable.ssbsect_census_2_enrl) AS ssbsect_census_2_enrl,
       coalesce(bantable.ssbsect_voice_avail, custable.ssbsect_voice_avail) AS ssbsect_voice_avail,
       coalesce(bantable.ssbsect_capp_prereq_test_ind, custable.ssbsect_capp_prereq_test_ind) AS ssbsect_capp_prereq_test_ind,
       coalesce(bantable.ssbsect_gsch_name, custable.ssbsect_gsch_name) AS ssbsect_gsch_name,
       coalesce(bantable.ssbsect_best_of_comp, custable.ssbsect_best_of_comp) AS ssbsect_best_of_comp,
       coalesce(bantable.ssbsect_subset_of_comp, custable.ssbsect_subset_of_comp) AS ssbsect_subset_of_comp,
       coalesce(bantable.ssbsect_insm_code, custable.ssbsect_insm_code) AS ssbsect_insm_code,
       coalesce(bantable.ssbsect_reg_from_date, custable.ssbsect_reg_from_date) AS ssbsect_reg_from_date,
       coalesce(bantable.ssbsect_reg_to_date, custable.ssbsect_reg_to_date) AS ssbsect_reg_to_date,
       coalesce(bantable.ssbsect_learner_regstart_fdate, custable.ssbsect_learner_regstart_fdate) AS ssbsect_learner_regstart_fdate,
       coalesce(bantable.ssbsect_learner_regstart_tdate, custable.ssbsect_learner_regstart_tdate) AS ssbsect_learner_regstart_tdate,
       coalesce(bantable.ssbsect_dunt_code, custable.ssbsect_dunt_code) AS ssbsect_dunt_code,
       coalesce(bantable.ssbsect_number_of_units, custable.ssbsect_number_of_units) AS ssbsect_number_of_units,
       coalesce(bantable.ssbsect_number_of_extensions, custable.ssbsect_number_of_extensions) AS ssbsect_number_of_extensions,
       coalesce(bantable.ssbsect_data_origin, custable.ssbsect_data_origin) AS ssbsect_data_origin,
       coalesce(bantable.ssbsect_user_id, custable.ssbsect_user_id) AS ssbsect_user_id,
       coalesce(bantable.ssbsect_intg_cde, custable.ssbsect_intg_cde) AS ssbsect_intg_cde,
       coalesce(bantable.ssbsect_prereq_chk_method_cde, custable.ssbsect_prereq_chk_method_cde) AS ssbsect_prereq_chk_method_cde,
       coalesce(bantable.ssbsect_surrogate_id, custable.ssbsect_surrogate_id) AS ssbsect_surrogate_id,
       coalesce(bantable.ssbsect_version, custable.ssbsect_version) AS ssbsect_version,
       coalesce(bantable.ssbsect_vpdi_code, custable.ssbsect_vpdi_code) AS ssbsect_vpdi_code,
       coalesce(bantable.ssbsect_keyword_index_id, custable.ssbsect_keyword_index_id) AS ssbsect_keyword_index_id,
       coalesce(bantable.ssbsect_score_open_date, custable.ssbsect_score_open_date) AS ssbsect_score_open_date,
       coalesce(bantable.ssbsect_score_cutoff_date, custable.ssbsect_score_cutoff_date) AS ssbsect_score_cutoff_date,
       coalesce(bantable.ssbsect_reas_score_open_date, custable.ssbsect_reas_score_open_date) AS ssbsect_reas_score_open_date,
       coalesce(bantable.ssbsect_reas_score_ctof_date, custable.ssbsect_reas_score_ctof_date) AS ssbsect_reas_score_ctof_date,
       coalesce(bantable.ssbsect_override_dur_ind, custable.ssbsect_override_dur_ind) AS ssbsect_override_dur_ind,
       coalesce(bantable.ssbsect_refund_cutoff_date, custable.ssbsect_refund_cutoff_date) AS ssbsect_refund_cutoff_date,
       coalesce(bantable.ssbsect_reg_auth_active_cde, custable.ssbsect_reg_auth_active_cde) AS ssbsect_reg_auth_active_cde,
       coalesce(bantable.ssbsect_acyr_code, custable.ssbsect_acyr_code) AS ssbsect_acyr_code,
       coalesce(bantable.ssbsect_refund_cut_off_date, custable.ssbsect_refund_cut_off_date) AS ssbsect_refund_cut_off_date,
       coalesce(bantable.ssbsect_reg_auth_active_ind, custable.ssbsect_reg_auth_active_ind) AS ssbsect_reg_auth_active_ind,
       coalesce(bantable.hash_check, custable.hash_check) hash_check,
       CASE
       WHEN custable.ssbsect_surrogate_id IS NULL
            AND bantable.ssbsect_surrogate_id IS NOT NULL THEN
        'INSERT'
       WHEN (custable.hash_check != bantable.hash_check AND NOT EXISTS (SELECT 'X'
                                                                          FROM utl_d_aim.ssbsect_log_check lc
                                                                         WHERE lc.ssbsect_surrogate_id = bantable.ssbsect_surrogate_id
                                                                           AND lc.hash_check = bantable.hash_check)) THEN
        'UPDATE'
       END log_type,
       v_etl_date AS etl_activity_date
  FROM (SELECT t.ssbsect_term_code,
               t.ssbsect_crn,
               t.ssbsect_ptrm_code,
               t.ssbsect_subj_code,
               t.ssbsect_crse_numb,
               t.ssbsect_seq_numb,
               t.ssbsect_ssts_code,
               t.ssbsect_schd_code,
               t.ssbsect_camp_code,
               t.ssbsect_crse_title,
               t.ssbsect_credit_hrs,
               t.ssbsect_bill_hrs,
               t.ssbsect_gmod_code,
               t.ssbsect_sapr_code,
               t.ssbsect_sess_code,
               t.ssbsect_link_ident,
               t.ssbsect_prnt_ind,
               t.ssbsect_gradable_ind,
               t.ssbsect_tuiw_ind,
               t.ssbsect_prior_enrl,
               t.ssbsect_proj_enrl,
               t.ssbsect_max_enrl,
               t.ssbsect_census_enrl_date,
               t.ssbsect_ptrm_start_date,
               t.ssbsect_ptrm_end_date,
               t.ssbsect_ptrm_weeks,
               t.ssbsect_reserved_ind,
               t.ssbsect_lec_hr,
               t.ssbsect_lab_hr,
               t.ssbsect_oth_hr,
               t.ssbsect_cont_hr,
               t.ssbsect_acct_code,
               t.ssbsect_accl_code,
               t.ssbsect_census_2_date,
               t.ssbsect_enrl_cut_off_date,
               t.ssbsect_acad_cut_off_date,
               t.ssbsect_drop_cut_off_date,
               t.ssbsect_census_2_enrl,
               t.ssbsect_voice_avail,
               t.ssbsect_capp_prereq_test_ind,
               t.ssbsect_gsch_name,
               t.ssbsect_best_of_comp,
               t.ssbsect_subset_of_comp,
               t.ssbsect_insm_code,
               t.ssbsect_reg_from_date,
               t.ssbsect_reg_to_date,
               t.ssbsect_learner_regstart_fdate,
               t.ssbsect_learner_regstart_tdate,
               t.ssbsect_dunt_code,
               t.ssbsect_number_of_units,
               t.ssbsect_number_of_extensions,
               t.ssbsect_data_origin,
               t.ssbsect_user_id,
               t.ssbsect_intg_cde,
               t.ssbsect_prereq_chk_method_cde,
               t.ssbsect_surrogate_id,
               t.ssbsect_version,
               t.ssbsect_vpdi_code,
               t.ssbsect_keyword_index_id,
               t.ssbsect_score_open_date,
               t.ssbsect_score_cutoff_date,
               t.ssbsect_reas_score_open_date,
               t.ssbsect_reas_score_ctof_date,
               t.ssbsect_override_dur_ind,
               t.ssbsect_refund_cutoff_date,
               t.ssbsect_reg_auth_active_cde,
               t.ssbsect_acyr_code,
               t.ssbsect_refund_cut_off_date,
               t.ssbsect_reg_auth_active_ind,
               ora_hash(t.ssbsect_term_code || t.ssbsect_crn || t.ssbsect_ptrm_code || t.ssbsect_subj_code || t.ssbsect_crse_numb || t.ssbsect_seq_numb || t.ssbsect_ssts_code || t.ssbsect_schd_code || t.ssbsect_camp_code ||
                        t.ssbsect_crse_title || t.ssbsect_credit_hrs || t.ssbsect_bill_hrs || t.ssbsect_gmod_code || t.ssbsect_sapr_code || t.ssbsect_sess_code || t.ssbsect_link_ident || t.ssbsect_prnt_ind || t.ssbsect_gradable_ind ||
                        t.ssbsect_tuiw_ind || t.ssbsect_prior_enrl || t.ssbsect_proj_enrl || t.ssbsect_max_enrl || t.ssbsect_ptrm_start_date || t.ssbsect_ptrm_end_date || t.ssbsect_ptrm_weeks || t.ssbsect_reserved_ind || t.ssbsect_lec_hr ||
                        t.ssbsect_lab_hr || t.ssbsect_oth_hr || t.ssbsect_cont_hr || t.ssbsect_acct_code || t.ssbsect_accl_code || t.ssbsect_census_2_date || t.ssbsect_enrl_cut_off_date || t.ssbsect_acad_cut_off_date ||
                        t.ssbsect_drop_cut_off_date || t.ssbsect_census_2_enrl || t.ssbsect_voice_avail || t.ssbsect_capp_prereq_test_ind || t.ssbsect_gsch_name || t.ssbsect_best_of_comp || t.ssbsect_subset_of_comp || t.ssbsect_insm_code ||
                        t.ssbsect_reg_from_date || t.ssbsect_reg_to_date || t.ssbsect_learner_regstart_fdate || t.ssbsect_learner_regstart_tdate || t.ssbsect_dunt_code || t.ssbsect_number_of_units || t.ssbsect_number_of_extensions ||
                        t.ssbsect_data_origin || t.ssbsect_user_id || t.ssbsect_intg_cde || t.ssbsect_prereq_chk_method_cde || t.ssbsect_surrogate_id || t.ssbsect_version || t.ssbsect_vpdi_code || t.ssbsect_keyword_index_id ||
                        t.ssbsect_score_open_date || t.ssbsect_score_cutoff_date || t.ssbsect_reas_score_open_date || t.ssbsect_reas_score_ctof_date || t.ssbsect_override_dur_ind || t.ssbsect_refund_cutoff_date ||
                        t.ssbsect_reg_auth_active_cde || t.ssbsect_acyr_code || t.ssbsect_refund_cut_off_date || t.ssbsect_reg_auth_active_ind) hash_check
          FROM ssbsect t) bantable
  LEFT JOIN utl_d_aim.ssbsect_log_check custable
    ON custable.ssbsect_surrogate_id = bantable.ssbsect_surrogate_id
 WHERE (custable.ssbsect_surrogate_id IS NULL AND bantable.ssbsect_surrogate_id IS NOT NULL)
    OR (custable.ssbsect_surrogate_id IS NOT NULL AND custable.hash_check != bantable.hash_check)
UNION ALL
SELECT coalesce(bantable.ssbsect_term_code, custable.ssbsect_term_code) AS ssbsect_term_code,
       coalesce(bantable.ssbsect_crn, custable.ssbsect_crn) AS ssbsect_crn,
       coalesce(bantable.ssbsect_ptrm_code, custable.ssbsect_ptrm_code) AS ssbsect_ptrm_code,
       coalesce(bantable.ssbsect_subj_code, custable.ssbsect_subj_code) AS ssbsect_subj_code,
       coalesce(bantable.ssbsect_crse_numb, custable.ssbsect_crse_numb) AS ssbsect_crse_numb,
       coalesce(bantable.ssbsect_seq_numb, custable.ssbsect_seq_numb) AS ssbsect_seq_numb,
       coalesce(bantable.ssbsect_ssts_code, custable.ssbsect_ssts_code) AS ssbsect_ssts_code,
       coalesce(bantable.ssbsect_schd_code, custable.ssbsect_schd_code) AS ssbsect_schd_code,
       coalesce(bantable.ssbsect_camp_code, custable.ssbsect_camp_code) AS ssbsect_camp_code,
       coalesce(bantable.ssbsect_crse_title, custable.ssbsect_crse_title) AS ssbsect_crse_title,
       coalesce(bantable.ssbsect_credit_hrs, custable.ssbsect_credit_hrs) AS ssbsect_credit_hrs,
       coalesce(bantable.ssbsect_bill_hrs, custable.ssbsect_bill_hrs) AS ssbsect_bill_hrs,
       coalesce(bantable.ssbsect_gmod_code, custable.ssbsect_gmod_code) AS ssbsect_gmod_code,
       coalesce(bantable.ssbsect_sapr_code, custable.ssbsect_sapr_code) AS ssbsect_sapr_code,
       coalesce(bantable.ssbsect_sess_code, custable.ssbsect_sess_code) AS ssbsect_sess_code,
       coalesce(bantable.ssbsect_link_ident, custable.ssbsect_link_ident) AS ssbsect_link_ident,
       coalesce(bantable.ssbsect_prnt_ind, custable.ssbsect_prnt_ind) AS ssbsect_prnt_ind,
       coalesce(bantable.ssbsect_gradable_ind, custable.ssbsect_gradable_ind) AS ssbsect_gradable_ind,
       coalesce(bantable.ssbsect_tuiw_ind, custable.ssbsect_tuiw_ind) AS ssbsect_tuiw_ind,
       coalesce(bantable.ssbsect_prior_enrl, custable.ssbsect_prior_enrl) AS ssbsect_prior_enrl,
       coalesce(bantable.ssbsect_proj_enrl, custable.ssbsect_proj_enrl) AS ssbsect_proj_enrl,
       coalesce(bantable.ssbsect_max_enrl, custable.ssbsect_max_enrl) AS ssbsect_max_enrl,
       coalesce(bantable.ssbsect_census_enrl_date, custable.ssbsect_census_enrl_date) AS ssbsect_census_enrl_date,
       coalesce(bantable.ssbsect_ptrm_start_date, custable.ssbsect_ptrm_start_date) AS ssbsect_ptrm_start_date,
       coalesce(bantable.ssbsect_ptrm_end_date, custable.ssbsect_ptrm_end_date) AS ssbsect_ptrm_end_date,
       coalesce(bantable.ssbsect_ptrm_weeks, custable.ssbsect_ptrm_weeks) AS ssbsect_ptrm_weeks,
       coalesce(bantable.ssbsect_reserved_ind, custable.ssbsect_reserved_ind) AS ssbsect_reserved_ind,
       coalesce(bantable.ssbsect_lec_hr, custable.ssbsect_lec_hr) AS ssbsect_lec_hr,
       coalesce(bantable.ssbsect_lab_hr, custable.ssbsect_lab_hr) AS ssbsect_lab_hr,
       coalesce(bantable.ssbsect_oth_hr, custable.ssbsect_oth_hr) AS ssbsect_oth_hr,
       coalesce(bantable.ssbsect_cont_hr, custable.ssbsect_cont_hr) AS ssbsect_cont_hr,
       coalesce(bantable.ssbsect_acct_code, custable.ssbsect_acct_code) AS ssbsect_acct_code,
       coalesce(bantable.ssbsect_accl_code, custable.ssbsect_accl_code) AS ssbsect_accl_code,
       coalesce(bantable.ssbsect_census_2_date, custable.ssbsect_census_2_date) AS ssbsect_census_2_date,
       coalesce(bantable.ssbsect_enrl_cut_off_date, custable.ssbsect_enrl_cut_off_date) AS ssbsect_enrl_cut_off_date,
       coalesce(bantable.ssbsect_acad_cut_off_date, custable.ssbsect_acad_cut_off_date) AS ssbsect_acad_cut_off_date,
       coalesce(bantable.ssbsect_drop_cut_off_date, custable.ssbsect_drop_cut_off_date) AS ssbsect_drop_cut_off_date,
       coalesce(bantable.ssbsect_census_2_enrl, custable.ssbsect_census_2_enrl) AS ssbsect_census_2_enrl,
       coalesce(bantable.ssbsect_voice_avail, custable.ssbsect_voice_avail) AS ssbsect_voice_avail,
       coalesce(bantable.ssbsect_capp_prereq_test_ind, custable.ssbsect_capp_prereq_test_ind) AS ssbsect_capp_prereq_test_ind,
       coalesce(bantable.ssbsect_gsch_name, custable.ssbsect_gsch_name) AS ssbsect_gsch_name,
       coalesce(bantable.ssbsect_best_of_comp, custable.ssbsect_best_of_comp) AS ssbsect_best_of_comp,
       coalesce(bantable.ssbsect_subset_of_comp, custable.ssbsect_subset_of_comp) AS ssbsect_subset_of_comp,
       coalesce(bantable.ssbsect_insm_code, custable.ssbsect_insm_code) AS ssbsect_insm_code,
       coalesce(bantable.ssbsect_reg_from_date, custable.ssbsect_reg_from_date) AS ssbsect_reg_from_date,
       coalesce(bantable.ssbsect_reg_to_date, custable.ssbsect_reg_to_date) AS ssbsect_reg_to_date,
       coalesce(bantable.ssbsect_learner_regstart_fdate, custable.ssbsect_learner_regstart_fdate) AS ssbsect_learner_regstart_fdate,
       coalesce(bantable.ssbsect_learner_regstart_tdate, custable.ssbsect_learner_regstart_tdate) AS ssbsect_learner_regstart_tdate,
       coalesce(bantable.ssbsect_dunt_code, custable.ssbsect_dunt_code) AS ssbsect_dunt_code,
       coalesce(bantable.ssbsect_number_of_units, custable.ssbsect_number_of_units) AS ssbsect_number_of_units,
       coalesce(bantable.ssbsect_number_of_extensions, custable.ssbsect_number_of_extensions) AS ssbsect_number_of_extensions,
       coalesce(bantable.ssbsect_data_origin, custable.ssbsect_data_origin) AS ssbsect_data_origin,
       coalesce(bantable.ssbsect_user_id, custable.ssbsect_user_id) AS ssbsect_user_id,
       coalesce(bantable.ssbsect_intg_cde, custable.ssbsect_intg_cde) AS ssbsect_intg_cde,
       coalesce(bantable.ssbsect_prereq_chk_method_cde, custable.ssbsect_prereq_chk_method_cde) AS ssbsect_prereq_chk_method_cde,
       coalesce(bantable.ssbsect_surrogate_id, custable.ssbsect_surrogate_id) AS ssbsect_surrogate_id,
       coalesce(bantable.ssbsect_version, custable.ssbsect_version) AS ssbsect_version,
       coalesce(bantable.ssbsect_vpdi_code, custable.ssbsect_vpdi_code) AS ssbsect_vpdi_code,
       coalesce(bantable.ssbsect_keyword_index_id, custable.ssbsect_keyword_index_id) AS ssbsect_keyword_index_id,
       coalesce(bantable.ssbsect_score_open_date, custable.ssbsect_score_open_date) AS ssbsect_score_open_date,
       coalesce(bantable.ssbsect_score_cutoff_date, custable.ssbsect_score_cutoff_date) AS ssbsect_score_cutoff_date,
       coalesce(bantable.ssbsect_reas_score_open_date, custable.ssbsect_reas_score_open_date) AS ssbsect_reas_score_open_date,
       coalesce(bantable.ssbsect_reas_score_ctof_date, custable.ssbsect_reas_score_ctof_date) AS ssbsect_reas_score_ctof_date,
       coalesce(bantable.ssbsect_override_dur_ind, custable.ssbsect_override_dur_ind) AS ssbsect_override_dur_ind,
       coalesce(bantable.ssbsect_refund_cutoff_date, custable.ssbsect_refund_cutoff_date) AS ssbsect_refund_cutoff_date,
       coalesce(bantable.ssbsect_reg_auth_active_cde, custable.ssbsect_reg_auth_active_cde) AS ssbsect_reg_auth_active_cde,
       coalesce(bantable.ssbsect_acyr_code, custable.ssbsect_acyr_code) AS ssbsect_acyr_code,
       coalesce(bantable.ssbsect_refund_cut_off_date, custable.ssbsect_refund_cut_off_date) AS ssbsect_refund_cut_off_date,
       coalesce(bantable.ssbsect_reg_auth_active_ind, custable.ssbsect_reg_auth_active_ind) AS ssbsect_reg_auth_active_ind,
       bantable.hash_check hash_check,
       'DELETE' log_type,
       v_etl_date AS etl_activity_date
  FROM (SELECT s.ssbsect_term_code,
               s.ssbsect_crn,
               s.ssbsect_ptrm_code,
               s.ssbsect_subj_code,
               s.ssbsect_crse_numb,
               s.ssbsect_seq_numb,
               s.ssbsect_ssts_code,
               s.ssbsect_schd_code,
               s.ssbsect_camp_code,
               s.ssbsect_crse_title,
               s.ssbsect_credit_hrs,
               s.ssbsect_bill_hrs,
               s.ssbsect_gmod_code,
               s.ssbsect_sapr_code,
               s.ssbsect_sess_code,
               s.ssbsect_link_ident,
               s.ssbsect_prnt_ind,
               s.ssbsect_gradable_ind,
               s.ssbsect_tuiw_ind,
               s.ssbsect_prior_enrl,
               s.ssbsect_proj_enrl,
               s.ssbsect_max_enrl,
               s.ssbsect_census_enrl_date,
               s.ssbsect_ptrm_start_date,
               s.ssbsect_ptrm_end_date,
               s.ssbsect_ptrm_weeks,
               s.ssbsect_reserved_ind,
               s.ssbsect_lec_hr,
               s.ssbsect_lab_hr,
               s.ssbsect_oth_hr,
               s.ssbsect_cont_hr,
               s.ssbsect_acct_code,
               s.ssbsect_accl_code,
               s.ssbsect_census_2_date,
               s.ssbsect_enrl_cut_off_date,
               s.ssbsect_acad_cut_off_date,
               s.ssbsect_drop_cut_off_date,
               s.ssbsect_census_2_enrl,
               s.ssbsect_voice_avail,
               s.ssbsect_capp_prereq_test_ind,
               s.ssbsect_gsch_name,
               s.ssbsect_best_of_comp,
               s.ssbsect_subset_of_comp,
               s.ssbsect_insm_code,
               s.ssbsect_reg_from_date,
               s.ssbsect_reg_to_date,
               s.ssbsect_learner_regstart_fdate,
               s.ssbsect_learner_regstart_tdate,
               s.ssbsect_dunt_code,
               s.ssbsect_number_of_units,
               s.ssbsect_number_of_extensions,
               s.ssbsect_data_origin,
               s.ssbsect_user_id,
               s.ssbsect_intg_cde,
               s.ssbsect_prereq_chk_method_cde,
               s.ssbsect_surrogate_id,
               s.ssbsect_version,
               s.ssbsect_vpdi_code,
               s.ssbsect_keyword_index_id,
               s.ssbsect_score_open_date,
               s.ssbsect_score_cutoff_date,
               s.ssbsect_reas_score_open_date,
               s.ssbsect_reas_score_ctof_date,
               s.ssbsect_override_dur_ind,
               s.ssbsect_refund_cutoff_date,
               s.ssbsect_reg_auth_active_cde,
               s.ssbsect_acyr_code,
               s.ssbsect_refund_cut_off_date,
               s.ssbsect_reg_auth_active_ind,
               s.hash_check
          FROM utl_d_aim.ssbsect_log_check s) bantable
  LEFT JOIN ssbsect custable
    ON custable.ssbsect_surrogate_id = bantable.ssbsect_surrogate_id
 WHERE custable.ssbsect_surrogate_id IS NULL
   AND bantable.ssbsect_surrogate_id IS NOT NULL;
v_count := SQL%ROWCOUNT;
COMMIT;
dbms_lock.sleep(1.0); -- pause second
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ssbsect_log_check - at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- '); */
dbms_lock.sleep(1.0); -- pause second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
-- log any errors
EXCEPTION
WHEN OTHERS THEN
dbms_lock.sleep(1.0); -- pause second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
/*--------------------------------------------CHANGE LOG----------------------------------------
VERSION  DATE         USERNAME    UPDATES
---      11/8/2022    CWALSH1     Initial Release
---      07/29/2025   cryan9      adding ssbsect_log_check
---      08/05/2025   cryan9      adding ssrxlst_log_check, adding logging to ads_etl.insert_job_log
---      08/07/2025    wgriffith2  re-ordering the inserts so that ssbsect runs last since it is running away every time now. Clee is going to be working on fixing the ssbsect insert
------------------------------------------------------------------------------------------------*/
END etl_aim_banner_log_checks;

end load_aim_etl;
