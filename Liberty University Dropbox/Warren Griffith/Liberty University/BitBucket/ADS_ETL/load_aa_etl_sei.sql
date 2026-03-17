create or replace package load_aa_etl_sei is  
procedure etl_aa_sei_convocation_attendance(jobnumber   number, processid   varchar2, processname varchar2);
procedure etl_aa_sei_prayer_room_attendance(jobnumber number, processid varchar2, processname varchar2);
procedure etl_aa_sei_campus_community(jobnumber   number, processid   varchar2, processname varchar2);
procedure etl_aa_sei_community_group_attendance(jobnumber   number, processid   varchar2, processname varchar2);
procedure etl_aa_sei_cser(jobnumber   number, processid   varchar2, processname varchar2);
PROCEDURE etl_aa_sei_biblical_literacy(jobnumber   NUMBER, processid   VARCHAR2, processname VARCHAR2);
procedure etl_aa_sei_tableau(jobnumber   number, processid   varchar2, processname varchar2);
end load_aa_etl_sei;
/

create or replace package body load_aa_etl_sei is

PROCEDURE etl_aa_sei_biblical_literacy(jobnumber   NUMBER, processid   VARCHAR2, processname VARCHAR2) IS
--DECLARE
-- PARAMS
v_etl_date    DATE := SYSDATE;
v_msg         VARCHAR2(2000);
v_instance    VARCHAR2(50) := upper('ALL'); -- instance from the jams job; used for determining instance
v_partition    NUMBER := 0; -- number from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_aa_sei_biblical_literacy';
BEGIN
-- Generate unique job_id for this run
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
dbms_lock.sleep(0.5); -- pause half second 
MERGE INTO utl_d_aa.sei_audit a
USING (SELECT enr.pidm,
              enr.term_code,
              'biblical_literacy' AS TYPE,
              12.5 AS score,
              v_etl_date AS activity_date
         FROM utl_d_aim.szrenrl enr
         JOIN zbtm.terms_by_group_v terms
           ON terms.term_code = enr.term_code
          AND terms.semester NOT IN ('WIN', 'SUM')
          AND terms.group_code IN ('STD')
          AND SYSDATE >= terms.start_date - 180
          AND SYSDATE <= terms.end_date + 180
        WHERE enr.camp_code = 'R'
          AND enr.levl_code = 'UG'
          AND enr.term_hours > 0) u
ON (u.pidm = a.pidm AND u.term_code = a.term_code AND u.type = a.type)
WHEN MATCHED THEN
UPDATE
   SET a.score         = u.score,
       a.activity_date = u.activity_date
 WHERE a.score != u.score
   AND u.score IS NOT NULL
WHEN NOT MATCHED THEN
INSERT
(pidm,
 term_code,
 TYPE,
 score,
 activity_date)
VALUES
(u.pidm,
 u.term_code,
 u.type,
 u.score,
 u.activity_date);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
EXCEPTION
WHEN OTHERS THEN
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line('Error: ' || v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
ROLLBACK;
----------------------------------------CHANGE LOG----------------------------------------
-- VERSION DATE        USERNAME    UPDATES
--   08-04-2025        WGRIFFITH2  --Initial release with job_log integration
------------------------------------------------------------------------------------------
END etl_aa_sei_biblical_literacy;

PROCEDURE etl_aa_sei_tableau(jobnumber   NUMBER, processid   VARCHAR2, processname VARCHAR2) IS
--DECLARE
-- PARAMS
v_etl_date    DATE := SYSDATE;
v_msg         VARCHAR2(2000);
v_instance    VARCHAR2(50) := upper('ALL'); -- instance from the jams job; used for determining instance
v_partition    NUMBER := 0; -- number from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_aa_sei_tableau';
BEGIN
-- Generate unique job_id for this run
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
dbms_lock.sleep(0.5); -- pause half second
utl_d_aa.truncate_table(v_table_name => 'sei_tableau');
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'TRUNCATE - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count;
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_lock.sleep(0.5); -- pause half second
INSERT INTO utl_d_aa.sei_tableau
(pidm,
 luid,
 NAME,
 enr_term,
 term_desc,
 term_start,
 term_end,
 house,
 denomination,
 gender,
 rs,
 shepherd,
 shepherd_username,
 category_name,
 faith_category,
 cat_score,
 faith_score,
 final_score,
 activity_date)
WITH term AS
 (SELECT terms.term_desc,
         terms.term_code  AS term_code,
         terms.start_date AS term_start,
         terms.end_date   AS term_end
    FROM zbtm.terms_by_group_v terms
   WHERE terms.semester NOT IN ('WIN', 'SUM')
     AND terms.group_code IN ('STD')
     AND terms.term_code >= '202440' -- they will want the data indefinitely from here
     AND terms.start_date - 21 <= SYSDATE)
SELECT enr.pidm AS pidm,
       enr.luid AS luid,
       enr.first_name || ' ' || enr.last_name AS NAME,
       enr.term_code AS enr_term,
       term.term_desc,
       term.term_start,
       term.term_end,
       nvl2(bk.booking_id, 'On Campus', 'Off Campus') AS house,
       TRIM(nvl(rl.stvrelg_desc, 'Unreported')) AS denomination,
       decode(enr.gender, 'M', 'Male', 'F', 'Female', 'N', 'Not Specified', enr.gender) AS gender,
       nvl(listagg(rs.rs_name, ', ') within GROUP(ORDER BY 1), 'Off Campus') AS rs,
       CASE
       WHEN shep.spriden_pidm IS NULL THEN
        'Off Campus'
       ELSE
        shep.spriden_first_name || ' ' || shep.spriden_last_name
       END shepherd,
       g.gobtpac_external_user AS shepherd_username,
       sei_type_codes.type_code AS subcategory_name,
       sei_type_codes.faith_category,
       nvl(sei.score, 0) AS subcategory_score, -- raw score of what matches to sei_type_codes.type_code
       nvl(SUM(sei.score) over(PARTITION BY enr.pidm, enr.term_code, sei_type_codes.faith_category), 0) AS category_score, -- this is the score of each acronym of the "faith" score
       nvl(SUM(sei.score) over(PARTITION BY enr.pidm, enr.term_code), 0) AS final_score, -- this is the "total" score - summing all sei.score per pidm and term
       v_etl_date AS activity_date
  FROM utl_d_aim.szrenrl enr
  JOIN utl_d_aa.sei_type_codes -- needed to make everything show whether or not we have anything in the audit table.
    ON sei_type_codes.active = 'Y'
  JOIN term
    ON term.term_code = enr.term_code
   AND enr.camp_code = 'R'
   AND enr.levl_code = 'UG'
   AND enr.term_hours > 0
-- get audit data
  LEFT JOIN utl_d_aa.sei_audit sei
    ON sei.term_code = enr.term_code
   AND sei.pidm = enr.pidm
   AND sei.type = sei_type_codes.type_code
-- get bed location
  LEFT JOIN (SELECT bav.pidm       AS pidm,
                    b.bed_id       AS bed,
                    bav.term,
                    bav.booking_id
               FROM zresidence.bookings_all_view bav
               JOIN term
                 ON term.term_code = bav.term
               JOIN zresidence.bookings b
                 ON b.booking_id = bav.booking_id
              WHERE bav.status IN ('INRM', 'RESV', 'TENT', 'HIST')) bk
    ON bk.term = enr.term_code
   AND bk.pidm = enr.pidm -- student pidm
-- start making connections to resident shepards / shepard
  LEFT JOIN zexec.zsavhloc lx2
    ON lx2.sr_bed_id = bk.bed
   AND lx2.primary_ind = 'Y'
-- get list of resident shepards
  LEFT JOIN (SELECT l.ln_build_id bldg,
                    CASE
                    WHEN l.ln_area_id IN ('9', '10') THEN
                     l.ln_build_id
                    ELSE
                     l.ln_hall_id
                    END hall,
                    l.ln_area_id,
                    s.spriden_first_name || ' ' || s.spriden_last_name rs_name,
                    bav.term
               FROM zresidence.bookings_all_view bav
               JOIN zresidence.bookings b
                 ON b.booking_id = bav.booking_id
               JOIN term
                 ON term.term_code = bav.term
               JOIN zresidence.location l
                 ON l.ln_bed_id = b.bed_id
               JOIN zresidence.positions p
                 ON p.ps_entry_id = b.entry_id
                AND p.ps_position = 'Resident Shepherd'
                AND (p.ps_position_date_start BETWEEN term.term_start AND term.term_end OR p.ps_position_date_end BETWEEN term.term_start AND term.term_end OR term.term_start BETWEEN p.ps_position_date_start AND p.ps_position_date_end OR
                    term.term_end BETWEEN p.ps_position_date_start AND p.ps_position_date_end)
               JOIN saturn.spriden s
                 ON s.spriden_pidm = bav.pidm
                AND s.spriden_change_ind IS NULL
              WHERE bav.status IN ('INRM', 'RESV', 'TENT', 'HIST')) rs
    ON rs.bldg = lx2.sr_bldg_id
   AND rs.term = enr.term_code
   AND rs.hall = CASE
       WHEN rs.ln_area_id IN ('9', '10') THEN
        rs.bldg
       ELSE
        lx2.sr_hall_id
       END
  LEFT JOIN zshepherds.jurisdictions jur
    ON SYSDATE > jur.start_date
   AND jur.hall_id = lx2.sr_hall_id
  LEFT JOIN saturn.spriden shep
    ON shep.spriden_pidm = jur.lu_shepherd_pidm
   AND shep.spriden_change_ind IS NULL
  LEFT JOIN general.gobtpac g
    ON g.gobtpac_pidm = shep.spriden_pidm
  LEFT JOIN saturn.spbpers pers
    ON pers.spbpers_pidm = enr.pidm
  LEFT JOIN saturn.stvrelg rl
    ON rl.stvrelg_code = pers.spbpers_relg_code
 GROUP BY enr.pidm,
          enr.luid,
          enr.first_name,
          enr.last_name,
          enr.term_code,
          term.term_desc,
          term.term_start,
          term.term_end,
          bk.booking_id,
          rl.stvrelg_desc,
          enr.gender,
          shep.spriden_pidm,
          shep.spriden_first_name,
          shep.spriden_last_name,
          g.gobtpac_external_user,
          sei_type_codes.type_code,
          sei.score,
          sei_type_codes.faith_category;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count;
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
EXCEPTION
WHEN OTHERS THEN
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line('Error: ' || v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
ROLLBACK;
/*--------------------------------------------CHANGE LOG----------------------------------------
VERSION DATE        USERNAME    UPDATES
--   08-06-2025     WGRIFFITH2  --Initial release
------------------------------------------------------------------------------------------------*/
END etl_aa_sei_tableau;

PROCEDURE etl_aa_sei_convocation_attendance(jobnumber   NUMBER, processid   VARCHAR2, processname VARCHAR2) IS
--DECLARE
-- Parameters for logging and process control
v_etl_date    DATE := SYSDATE;
v_msg         VARCHAR2(2000);
v_instance    VARCHAR2(50) := upper('ALL'); -- instance from the job, can be parameterized
v_partition    NUMBER := 0; -- parallel partition, can be parameterized
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_aa_sei_convocation_attendance';
BEGIN
-- Generate a unique job_id for this run
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
dbms_lock.sleep(0.5); -- pause half second
----------------------------------------------------------------------------
-- (DML) MERGE STATEMENT
----------------------------------------------------------------------------
MERGE INTO utl_d_aa.sei_convocation_gtt a
USING (
WITH cdates AS
 (SELECT t.stvterm_code,
         c.szrcond_convo_date
    FROM saturn.stvterm t
   INNER JOIN zbtm.terms_by_group_v terms
      ON terms.term_code = t.stvterm_code
   INNER JOIN zconvocation.szrcond c
      ON c.szrcond_convo_date BETWEEN t.stvterm_start_date AND t.stvterm_end_date
     AND to_date(to_char(c.szrcond_convo_date, 'YYYYMMDD') || c.szrcond_convo_time, 'YYYYMMDDHH24MI') + 1.5 / 24 <= SYSDATE
     AND c.szrcond_to_date IS NULL
     AND c.szrcond_exempted = 'N'
     AND c.szrcond_cancelled = 'N'
   WHERE terms.semester NOT IN ('WIN', 'SUM')
     AND terms.group_code IN ('STD')
     AND SYSDATE >= terms.start_date - 180
     AND SYSDATE <= terms.end_date + 180
     AND t.stvterm_code >= '202440'), --
convo_total AS
 (SELECT t.stvterm_code convo_term,
         COUNT(*) tot_convo
    FROM saturn.stvterm t
   INNER JOIN zbtm.ztvterm zt
      ON zt.ztvterm_code = t.stvterm_code
     AND zt.ztvterm_is_major = 'Y'
   INNER JOIN zconvocation.szrcond c
      ON c.szrcond_convo_date BETWEEN t.stvterm_start_date AND t.stvterm_end_date
     AND to_date(to_char(c.szrcond_convo_date, 'YYYYMMDD') || c.szrcond_convo_time, 'YYYYMMDDHH24MI') + 1.5 / 24 <= SYSDATE
     AND c.szrcond_to_date IS NULL
     AND c.szrcond_exempted = 'N'
     AND c.szrcond_cancelled = 'N'
   WHERE substr(t.stvterm_code, 6, 1) = '0'
     AND t.stvterm_start_date <= SYSDATE
     AND t.stvterm_code >= '202440'
   GROUP BY t.stvterm_code), -- 
nq AS
 (SELECT a2.pidm pidm,
         a2.time_in
    FROM zquickpass_reporting.attendance a2
   WHERE a2.location_code = 'CONVO'
     AND trunc(a2.time_in) >= to_date('19-AUG-2024', 'DD-MON-YYYY')
     AND a2.time_in = (SELECT MIN(a3.time_in)
                         FROM zquickpass_reporting.attendance a3
                        WHERE a3.pidm = a2.pidm
                          AND trunc(a3.time_in) = trunc(a2.time_in)
                          AND a3.location_code = a2.location_code)
  UNION
  SELECT a.pidm,
         a.time_in
    FROM zswiper.attendance a
   WHERE a.location_id IN (11641026, 7608093)
     AND trunc(a.time_in) >= to_date('19-AUG-2024', 'DD-MON-YYYY')
     AND a.time_in = (SELECT MIN(att.time_in)
                        FROM zswiper.attendance att
                       WHERE att.pidm = a.pidm
                         AND trunc(att.time_in) = trunc(a.time_in)
                         AND att.location_id = a.location_id))
-- Part one of Union: All required students and attendance
SELECT h.szrahst_pidm pidm,
       cdates.stvterm_code term,
       SUM(CASE
           WHEN h.szrahst_attendance = 'P' THEN
            1
           ELSE
            0
           END) att_present,
       SUM(CASE
           WHEN h.szrahst_attendance <> 'P' THEN
            1
           ELSE
            0
           END) att_missed,
       'Required' convo_type,
       COUNT(cdates.szrcond_convo_date) student_convos_possible,
       ct.tot_convo total_convos_per_term
  FROM cdates
 INNER JOIN zconvocation.szrahst h
    ON h.szrahst_convo_date = cdates.szrcond_convo_date
   AND h.szrahst_to_date IS NULL
 INNER JOIN zconvocation.szvatnd atnd
    ON atnd.szvatnd_code = h.szrahst_attendance
 INNER JOIN saturn.spriden s
    ON s.spriden_pidm = h.szrahst_pidm
   AND s.spriden_change_ind IS NULL
 INNER JOIN convo_total ct
    ON ct.convo_term = cdates.stvterm_code
 GROUP BY h.szrahst_pidm,
          cdates.stvterm_code,
          ct.tot_convo
UNION
-- Second part of union: All students who have swiped in that are not required
SELECT nq.pidm pidm,
       cdates.stvterm_code term,
       COUNT(nq.time_in) AS att_present,
       NULL att_missed,
       'Present - Not Required' convo_type,
       COUNT(nq.time_in) AS student_convos_possible, -- for off-campus; not required, so the number they attended in their max
       ct.tot_convo total_convos_per_term
  FROM cdates
 INNER JOIN nq
    ON trunc(nq.time_in) = cdates.szrcond_convo_date
 INNER JOIN saturn.spriden s
    ON s.spriden_pidm = nq.pidm
   AND s.spriden_change_ind IS NULL
 INNER JOIN convo_total ct
    ON ct.convo_term = cdates.stvterm_code
 WHERE NOT EXISTS (SELECT 1
          FROM zconvocation.szrahst h
         WHERE h.szrahst_pidm = nq.pidm
           AND h.szrahst_convo_date = cdates.szrcond_convo_date)
 GROUP BY nq.pidm,
          cdates.stvterm_code,
          ct.tot_convo) u
    ON (u.pidm = a.pidm AND u.term = a.term_code) WHEN MATCHED THEN
UPDATE
   SET a.att_present           = u.att_present,
       a.att_missed            = u.att_missed,
       a.convo_type            = u.convo_type,
       a.convos_possible       = u.student_convos_possible,
       a.total_convos_per_term = u.total_convos_per_term
 WHERE a.att_present != u.att_present
   AND u.att_present IS NOT NULL
WHEN NOT MATCHED THEN
INSERT
(pidm,
 term_code,
 att_present,
 att_missed,
 convo_type,
 convos_possible,
 total_convos_per_term)
VALUES
(u.pidm,
 u.term,
 u.att_present,
 u.att_missed,
 u.convo_type,
 u.student_convos_possible,
 u.total_convos_per_term);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count;
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
----------------------------------------------------------------------------
-- Main MERGE statement for convocation attendance scoring
----------------------------------------------------------------------------
MERGE INTO utl_d_aa.sei_audit a
USING (
WITH scs AS
 (SELECT gtt.term_code,
         gtt.pidm,
         SUM(gtt.att_present) AS att_present,
         SUM(gtt.convos_possible) AS convos_possible,
         SUM(gtt.att_present) / SUM(gtt.convos_possible) att_pct
    FROM utl_d_aa.sei_convocation_gtt gtt
   GROUP BY gtt.term_code,
            gtt.pidm), --
norm AS
 ( -- Calculate min and max for att_present across the entire table
  SELECT MIN(att_pct) AS min_att_present,
          MAX(att_pct) AS max_att_present,
          term_code
    FROM scs
   GROUP BY term_code), --
base AS
 (SELECT scs.pidm,
         scs.term_code,
         -- Min-Max Normalization: (att_present - min_att_present) / (max_att_present - min_att_present)
         CASE
         WHEN norm.max_att_present = norm.min_att_present THEN
          0 -- Avoid division by zero if all values are the same
         ELSE
          (scs.att_pct - norm.min_att_present) / (norm.max_att_present - norm.min_att_present)
         END AS att_present_normalized
    FROM scs
    JOIN norm
      ON norm.term_code = scs.term_code)
SELECT pidm,
       term_code,
       'convocation_attendance' AS TYPE,
       CASE
       WHEN att_present_normalized > 1 THEN
        10
       ELSE
        round(att_present_normalized * 10)
       END AS score, -- take the normalized score and multiple by 10
       v_etl_date AS activity_date
  FROM base) u
    ON (u.pidm = a.pidm AND u.term_code = a.term_code AND u.type = a.type) WHEN MATCHED THEN
UPDATE
   SET a.score = u.score,
       a.activity_date = u.activity_date
 WHERE a.score != u.score
   AND u.score IS NOT NULL
WHEN NOT MATCHED THEN
INSERT
(pidm,
 term_code,
 TYPE,
 score,
 activity_date)
VALUES
(u.pidm,
 u.term_code,
 u.type,
 u.score,
 u.activity_date);
v_count := SQL%ROWCOUNT; -- Get the number of rows affected by the MERGE
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count;
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_lock.sleep(0.5); -- Pause for half a second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
EXCEPTION
WHEN OTHERS THEN
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line('Error: ' || v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
utl_d_aa.truncate_table(v_table_name => 'sei_convocation_gtt');
ROLLBACK;
/*--------------------------------------------CHANGE LOG----------------------------------------
VERSION DATE        USERNAME    UPDATES
--   07-17-2025     WGRIFFITH2  --Initial release with job_log integration
--   08-01-2025     WGRIFFITH2  --replaced the staging table and created it as a GTT; score, -- take the normalized score and multiple by 10
------------------------------------------------------------------------------------------------*/
END etl_aa_sei_convocation_attendance;

PROCEDURE etl_aa_sei_cser(jobnumber   NUMBER, processid   VARCHAR2, processname VARCHAR2) IS
--DECLARE
-- Parameters for logging and process tracking
v_etl_date    DATE := SYSDATE;
v_msg         VARCHAR2(2000);
v_instance    VARCHAR2(50) := 'ALL';
v_partition    NUMBER := 0;
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_aa_sei_cser';
BEGIN
-- Generate unique job_id for this run
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
dbms_lock.sleep(0.5); -- pause half second
----------------------------------------------------------------------------
-- (DML) MERGE STATEMENT
----------------------------------------------------------------------------
MERGE INTO utl_d_aa.sei_audit a
USING (
WITH cser AS
 (SELECT s.spriden_pidm pidm,
         s.spriden_first_name || ' ' || s.spriden_last_name NAME,
         COUNT(ckg.shrtckg_grde_code_final) credits,
         CASE
         WHEN substr(n.shrtckn_term_code, 5, 2) = '30' THEN
          to_char(n.shrtckn_term_code - 10)
         WHEN substr(n.shrtckn_term_code, 5, 2) = '10' THEN
          to_char(n.shrtckn_term_code - 70)
         ELSE
          n.shrtckn_term_code
         END term_code,
         t_all.fa_proc_year academic_year
    FROM saturn.shrtckn n
    JOIN saturn.shrtckg ckg
      ON ckg.shrtckg_pidm = n.shrtckn_pidm
     AND ckg.shrtckg_term_code = n.shrtckn_term_code
     AND ckg.shrtckg_tckn_seq_no = n.shrtckn_seq_no
     AND ckg.shrtckg_seq_no = (SELECT MAX(ckg2.shrtckg_seq_no)
                                 FROM saturn.shrtckg ckg2
                                WHERE ckg2.shrtckg_pidm = ckg.shrtckg_pidm
                                  AND ckg2.shrtckg_tckn_seq_no = ckg.shrtckg_tckn_seq_no
                                  AND ckg2.shrtckg_term_code = ckg.shrtckg_term_code)
    JOIN saturn.spriden s
      ON s.spriden_pidm = n.shrtckn_pidm
     AND s.spriden_change_ind IS NULL
    JOIN zbtm.terms_by_group_v t_all
      ON t_all.term_code = n.shrtckn_term_code
     AND t_all.term_code >= '202440'
     AND t_all.group_code = 'STD'
   WHERE ckg.shrtckg_grde_code_final IN ('A', 'B', 'P')
     AND (n.shrtckn_subj_code = 'CSER' OR (n.shrtckn_subj_code IN ('BWVW', 'GNED') AND n.shrtckn_crse_numb IN ('101', '102')))
   GROUP BY s.spriden_pidm,
            s.spriden_first_name || ' ' || s.spriden_last_name,
            CASE
            WHEN substr(n.shrtckn_term_code, 5, 2) = '30' THEN
             to_char(n.shrtckn_term_code - 10)
            WHEN substr(n.shrtckn_term_code, 5, 2) = '10' THEN
             to_char(n.shrtckn_term_code - 70)
            ELSE
             n.shrtckn_term_code
            END,
            t_all.fa_proc_year),
base AS
 (SELECT c.pidm,
         v.term_code,
         1 AS credit_flag
    FROM cser c
    JOIN zbtm.terms_by_group_v v
      ON v.fa_proc_year = c.academic_year
     AND v.group_code = 'STD'
     AND v.is_major = 'Y'
   WHERE credits >= 2
  UNION
  SELECT pidm,
         term_code,
         1 credit_flag
    FROM cser
   WHERE cser.credits = 1)
SELECT pidm,
       term_code,
       'cser_credit' AS TYPE,
       credit_flag * 25 AS score,
       v_etl_date AS activity_date
  FROM base) u
    ON (u.pidm = a.pidm AND u.term_code = a.term_code AND u.type = a.type) WHEN MATCHED THEN
UPDATE
   SET a.score         = u.score,
       a.activity_date = u.activity_date
 WHERE a.score != u.score
   AND u.score IS NOT NULL
WHEN NOT MATCHED THEN
INSERT
(pidm,
 term_code,
 TYPE,
 score,
 activity_date)
VALUES
(u.pidm,
 u.term_code,
 u.type,
 u.score,
 u.activity_date);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count;
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
EXCEPTION
WHEN OTHERS THEN
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line('Error: ' || v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
ROLLBACK;
/*--------------------------------------------CHANGE LOG----------------------------------------
VERSION DATE        USERNAME    UPDATES
--   07-17-2025     WGRIFFITH2  --Initial release with job_log integration
------------------------------------------------------------------------------------------------*/
END etl_aa_sei_cser;

PROCEDURE etl_aa_sei_community_group_attendance(jobnumber   NUMBER, processid   VARCHAR2, processname VARCHAR2) IS
--DECLARE
-- PARAMS
v_etl_date    DATE := SYSDATE;
v_msg         VARCHAR2(2000);
v_instance    VARCHAR2(50) := upper('ALL'); -- instance from the jams job; used for determining instance
v_partition    NUMBER := 0; -- number from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_aa_sei_community_group_attendance';
BEGIN
-- Generate unique job_id for this run
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
dbms_lock.sleep(0.5); -- pause half second
----------------------------------------------------------------------------
-- (DML) MERGE STATEMENT
----------------------------------------------------------------------------
MERGE INTO utl_d_aa.sei_audit a
USING (
WITH base AS
 (SELECT DISTINCT s.spriden_pidm "PIDM",
                  CASE
                  WHEN hous.hall LIKE 'Annex D%' THEN
                   'Annex D'
                  ELSE
                   hous.hall
                  END "Hall",
                  hous.building "Building",
                  hous.area "Area",
                  atnd.szvatnd_description "Status",
                  ahst.szrahst_cg_date "Community Group Date",
                  cdates.szrcond_cg_time "Community Group Start Time",
                  to_date(ahst.szrahst_cg_date || ' ' || cdates.szrcond_cg_time, 'DD-MON-YY hh24mi') "CG DTT",
                  to_date(ahst.szrahst_from_date, 'DD-MON-YY hh.mi.ss AM') "Checked In",
                  to_date(ahst.szrahst_from_date, 'DD-MON-YY hh.mi.ss AM') - to_date(ahst.szrahst_cg_date || ' ' || cdates.szrcond_cg_time, 'DD-MON-YY hh24mi') "Check-In Delay",
                  ahst.szrahst_to_date "Expiration Date",
                  s.spriden_id "LUID",
                  s.spriden_last_name || ', ' || s.spriden_first_name "Name",
                  pers.spbpers_sex "Gender",
                  lus.lus_name "Shepherd",
                  lus.lus_username "Shepherd Username",
                  gsch.gsch_name "Grad Scholar",
                  gsch.gsch_username "Grad Scholar Username",
                  to_char(to_date(ahst.szrahst_from_date, 'dd-MON-yy hh.mi.ss AM'), 'hh12:mi:ss AM') "Time In",
                  CASE
                  WHEN to_date(ahst.szrahst_from_date, 'DD-MON-YYYY hh.mi.ss AM') < to_date(ahst.szrahst_cg_date || ' ' || cdates.szrcond_cg_time, 'DD-MON-YYYY hh24mi')
                       AND ahst.szrahst_attendance = 'P' THEN
                   'Early'
                  WHEN to_date(ahst.szrahst_from_date, 'DD-MON-YYYY hh.mi.ss AM') BETWEEN to_date(ahst.szrahst_cg_date || ' ' || cdates.szrcond_cg_time, 'DD-MON-YYYY hh24mi') AND
                       to_date(ahst.szrahst_cg_date || ' ' || cdates.szrcond_cg_time, 'DD-MON-YYYY hh24mi') + 2 / 3
                       AND ahst.szrahst_attendance = 'P' THEN
                   'On Time'
                  WHEN to_date(ahst.szrahst_from_date, 'DD-MON-YYYY hh.mi.ss AM') > to_date(ahst.szrahst_cg_date || ' ' || cdates.szrcond_cg_time, 'DD-MON-YYYY hh24mi') + 2 / 3
                       AND ahst.szrahst_attendance = 'P' THEN
                   'Late'
                  ELSE
                   'Not Present'
                  END AS "Punctuality",
                  t.term_code term_code,
                  t.term_desc "Term"
    FROM zbtm.terms_by_group_v t
   INNER JOIN zcommunitygroups.szrcond cdates
      ON 1 = 1
   INNER JOIN zcommunitygroups.szrahst ahst
      ON ahst.szrahst_cg_date = cdates.szrcond_cg_date
     AND ahst.szrahst_to_date IS NULL
     AND ahst.szrahst_cg_date BETWEEN t.start_date AND t.end_date
   INNER JOIN saturn.spriden s
      ON s.spriden_pidm = ahst.szrahst_pidm
     AND s.spriden_change_ind IS NULL
   INNER JOIN saturn.spbpers pers
      ON pers.spbpers_pidm = ahst.szrahst_pidm
   INNER JOIN zcommunitygroups.szvatnd atnd
      ON atnd.szvatnd_code = ahst.szrahst_attendance
    LEFT JOIN (SELECT DISTINCT ahst2.szrahst_id,
                              lx.sr_hall_desc  hall,
                              lx.bldg_desc     building,
                              lx.area_desc     area,
                              lx.room_desc     room_desc,
                              lx.hall_floor    hall_floor,
                              c.zcvbldg_code   bld_code
                FROM zcommunitygroups.szrahst ahst2
                LEFT JOIN zhousing.zhr_housing_assignment ha
                  ON ha.id = ahst2.szrahst_hous
                 AND ahst2.szrahst_from_date < '03-Feb-20'
                LEFT JOIN zhousing.zhbroom room
                  ON room.zhbroom_id = ha.room_id
                LEFT JOIN zresidence.bookings b
                  ON b.booking_id = ahst2.szrahst_hous
                 AND ahst2.szrahst_from_date >= '03-Feb-20'
                LEFT JOIN zresidence.location l
                  ON l.ln_bed_id = b.bed_id
                LEFT JOIN zexec.zsavhloc lx
                  ON lx.sr_room_id = l.ln_room_id
                  OR lx.lu_room_id = room.zhbroom_id
               INNER JOIN zconduct.zcvbldg c
                  ON c.zcvbldg_desc = lx.bldg_desc) hous
      ON hous.szrahst_id = ahst.szrahst_id
    LEFT JOIN (SELECT DISTINCT spriden2.spriden_id lus_id,
                              spriden2.spriden_last_name || ', ' || spriden2.spriden_first_name lus_name,
                              gobby.gobtpac_external_user lus_username,
                              jurs.zcrjris_bldg_code lus_bldg_code,
                              jurs.zcrjris_floor lus_floor
                FROM saturn.spriden spriden2
               INNER JOIN zconduct.zcrjris jurs
                  ON jurs.zcrjris_pidm = spriden2.spriden_pidm
                 AND jurs.zcrjris_ottl_code = 'CP'
                LEFT JOIN general.gobtpac gobby
                  ON gobby.gobtpac_pidm = spriden2.spriden_pidm
               WHERE spriden2.spriden_change_ind IS NULL) lus
      ON lus.lus_bldg_code = hous.bld_code
     AND (lus.lus_floor = CASE
         WHEN nvl(hous.hall_floor, substr(hous.room_desc, 1, 1)) = 'T' THEN
          'G'
         ELSE
          nvl(hous.hall_floor, substr(hous.room_desc, 1, 1))
         END OR lus.lus_floor IS NULL)
    LEFT JOIN (SELECT DISTINCT spriden2.spriden_id gsch_id,
                              spriden2.spriden_last_name || ', ' || spriden2.spriden_first_name gsch_name,
                              gobby.gobtpac_external_user gsch_username,
                              jurs.zcrjris_bldg_code gsch_bldg_code,
                              jurs.zcrjris_floor gsch_floor
                FROM saturn.spriden spriden2
               INNER JOIN zconduct.zcrjris jurs
                  ON jurs.zcrjris_pidm = spriden2.spriden_pidm
                 AND jurs.zcrjris_ottl_code = 'GSCH'
                LEFT JOIN general.gobtpac gobby
                  ON gobby.gobtpac_pidm = spriden2.spriden_pidm
               WHERE spriden2.spriden_change_ind IS NULL) gsch
      ON gsch.gsch_bldg_code = hous.bld_code
     AND (gsch.gsch_floor = CASE
         WHEN nvl(hous.hall_floor, substr(hous.room_desc, 1, 1)) = 'T' THEN
          'G'
         ELSE
          nvl(hous.hall_floor, substr(hous.room_desc, 1, 1))
         END OR gsch.gsch_floor IS NULL)
   WHERE cdates.szrcond_cg_date <= trunc(SYSDATE)
     AND cdates.szrcond_cg_date >= '14-FEB-18'
     AND cdates.szrcond_cancelled = 'N'
     AND cdates.szrcond_to_date IS NULL
     AND t.is_major = 'Y'
     AND t.group_code = 'STD'
     AND t.term_code >= (SELECT MIN(t.stvterm_code) - 100 term_code
                           FROM saturn.stvterm t
                           JOIN zbtm.ztvterm zt
                             ON zt.ztvterm_code = t.stvterm_code
                            AND zt.ztvterm_is_major = 'Y'
                          WHERE t.stvterm_end_date >= SYSDATE
                            AND substr(t.stvterm_code, 6, 1) = 0)
   ORDER BY ahst.szrahst_cg_date,
            CASE
            WHEN hous.hall LIKE 'Annex D%' THEN
             'Annex D'
            ELSE
             hous.hall
            END,
            "Punctuality")
SELECT base."PIDM",
       base.term_code,
       'community_group_attendance' AS TYPE,
       (COUNT(base."Checked In") * 1) AS score,
       v_etl_date AS activity_date
  FROM base
 WHERE base."Status" = 'Present'
 GROUP BY base."PIDM",
          base.term_code
 ORDER BY 1,
          3) u
    ON (u.pidm = a.pidm AND u.term_code = a.term_code AND u.type = a.type) WHEN MATCHED THEN
UPDATE
   SET a.score         = u.score,
       a.activity_date = u.activity_date
 WHERE a.score != u.score
   AND u.score IS NOT NULL
WHEN NOT MATCHED THEN
INSERT
(pidm,
 term_code,
 TYPE,
 score,
 activity_date)
VALUES
(u.pidm,
 u.term_code,
 u.type,
 u.score,
 u.activity_date);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
EXCEPTION
WHEN OTHERS THEN
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line('Error: ' || v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
ROLLBACK;
/*--------------------------------------------CHANGE LOG----------------------------------------
VERSION DATE        USERNAME    UPDATES
--   07-17-2025        WGRIFFITH2  --Initial release with job_log integration
------------------------------------------------------------------------------------------------*/
END etl_aa_sei_community_group_attendance;

PROCEDURE etl_aa_sei_campus_community(jobnumber   NUMBER, processid   VARCHAR2, processname VARCHAR2) IS
--DECLARE
-- PARAMS
v_etl_date    DATE := SYSDATE;
v_msg         VARCHAR2(2000);
v_instance    VARCHAR2(50) := upper('ALL'); -- instance from the jams job; used for determining instance
v_partition    NUMBER := 0; -- number from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_aa_sei_campus_community';
BEGIN
-- Generate unique job_id for this run
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
dbms_lock.sleep(0.5); -- pause half second
----------------------------------------------------------------------------
-- (DML) MERGE STATEMENT
----------------------------------------------------------------------------
MERGE INTO utl_d_aa.sei_audit a
USING (
WITH att AS
 (SELECT trunc(a.time_in) AS time_in,
         a.pidm,
         t.term_code,
         rank() over(PARTITION BY a.pidm, trunc(a.time_in), a.location_code ORDER BY a.time_in) AS rnk
    FROM zquickpass_reporting.attendance a
    JOIN zbtm.terms_by_group_v t
      ON t.group_code = 'STD'
     AND t.is_major = 'Y'
     AND a.time_in BETWEEN t.start_date AND t.end_date
   WHERE a.location_code = 'CAMPUS_COMMUNITY'
   GROUP BY a.pidm,
            a.time_in,
            a.location_code,
            t.term_code)
SELECT att.pidm,
       att.term_code,
       'camp_comm' AS TYPE,
       (COUNT(att.time_in) * 1) AS score,
       v_etl_date AS activity_date
  FROM att
 WHERE att.rnk = 1
 GROUP BY att.pidm,
          att.term_code) u
    ON (u.pidm = a.pidm AND u.term_code = a.term_code AND u.type = a.type) WHEN MATCHED THEN
UPDATE
   SET a.score = u.score,
       a.activity_date = u.activity_date
 WHERE a.score != u.score
   AND u.score IS NOT NULL
WHEN NOT MATCHED THEN
INSERT
(pidm,
 term_code,
 TYPE,
 score,
 activity_date)
VALUES
(u.pidm,
 u.term_code,
 u.type,
 u.score,
 u.activity_date);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
EXCEPTION
WHEN OTHERS THEN
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line('Error: ' || v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
ROLLBACK;
/*--------------------------------------------CHANGE LOG----------------------------------------
VERSION DATE        USERNAME    UPDATES
--   07-17-2025        WGRIFFITH2  --Initial release with job_log integration
------------------------------------------------------------------------------------------------*/
END etl_aa_sei_campus_community;

PROCEDURE etl_aa_sei_prayer_room_attendance(jobnumber   NUMBER, processid   VARCHAR2, processname VARCHAR2) IS
--DECLARE
-- PARAMS
v_etl_date    DATE := SYSDATE;
v_msg         VARCHAR2(2000);
v_instance    VARCHAR2(50) := upper('ALL'); -- instance from the jams job; used for determining instance
v_partition    NUMBER := 0; -- number from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_aa_sei_prayer_room_attendance';
BEGIN
-- Generate unique job_id for this run
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
dbms_lock.sleep(0.5); -- pause half second 
MERGE INTO utl_d_aa.sei_audit a
USING (SELECT s.spriden_pidm pidm,
              t.term_code term_code,
              'prayer_room_attendance' AS TYPE,
              CASE
              WHEN COUNT(DISTINCT trunc(a.time_in, 'MM')) > 2 THEN
               12.5
              WHEN COUNT(DISTINCT trunc(a.time_in, 'MM')) > 0 THEN
               6.25
              ELSE
               0
              END AS score,
              v_etl_date AS activity_date
         FROM zswiper.attendance a
         JOIN zswiper.location l
           ON l.id = a.location_id
          AND l.active_indicator = 'Y'
         JOIN zswiper.location_tag lt
           ON lt.location_id = l.id
          AND lt.tag_code = 'SEI PRAYER'
         JOIN saturn.spriden s
           ON s.spriden_pidm = a.pidm
          AND s.spriden_change_ind IS NULL
         JOIN zbtm.terms_by_group_v t
           ON a.time_in BETWEEN t.start_date AND t.end_date
          AND t.group_code = 'STD'
          AND t.term_code >= '202440'
        GROUP BY s.spriden_pidm,
                 s.spriden_first_name || ', ' || s.spriden_last_name,
                 t.term_code,
                 t.end_date,
                 t.start_date) u
ON (u.pidm = a.pidm AND u.term_code = a.term_code AND u.type = a.type)
WHEN MATCHED THEN
UPDATE
   SET a.score         = u.score,
       a.activity_date = u.activity_date
 WHERE a.score != u.score
   AND u.score IS NOT NULL
WHEN NOT MATCHED THEN
INSERT
(pidm,
 term_code,
 TYPE,
 score,
 activity_date)
VALUES
(u.pidm,
 u.term_code,
 u.type,
 u.score,
 u.activity_date);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
EXCEPTION
WHEN OTHERS THEN
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line('Error: ' || v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
ROLLBACK;
----------------------------------------CHANGE LOG----------------------------------------
-- VERSION DATE        USERNAME    UPDATES
--   07-17-2025        WGRIFFITH2  --Initial release with job_log integration
------------------------------------------------------------------------------------------
END etl_aa_sei_prayer_room_attendance;

end load_aa_etl_sei;
-- GRANT EXECUTE ON load_aa_etl_sei TO utl_d_aim;
-- GRANT EXECUTE ON load_aa_etl_sei TO utl_d_aa;
-- GRANT EXECUTE ON load_aa_etl_sei TO utl_d_lms;
-- GRANT EXECUTE ON load_aa_etl_sei TO wgriffith2;
-- GRANT EXECUTE ON load_aa_etl_sei TO RAHEPLER;
-- GRANT EXECUTE ON load_aa_etl_sei TO ZETL_JAMS_SVC;
