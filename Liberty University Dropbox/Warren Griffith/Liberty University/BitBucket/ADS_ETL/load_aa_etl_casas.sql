create or replace package load_aa_etl_casas is
procedure etl_aa_casas_advising_cohort(jobnumber number, processid varchar2, processname varchar2);  --- 20250709  WGRIFFITH2 initial release
procedure etl_aa_casas_advising_schedule(jobnumber number, processid varchar2, processname varchar2); --- 20250709  WGRIFFITH2 initial release
procedure etl_aa_casas_advising_audit_reg(jobnumber number, processid varchar2, processname varchar2); --- 20250709  WGRIFFITH2 initial release
procedure etl_aa_casas_advising_audit_fci(jobnumber number, processid varchar2, processname varchar2); --- 20250709  WGRIFFITH2 initial release
procedure etl_aa_casas_advising_audit_tsi(jobnumber number, processid varchar2, processname varchar2); --- 20250801  WGRIFFITH2 initial release
procedure etl_aa_casas_advising_audit_fns(jobnumber number, processid varchar2, processname varchar2); --- 20251003  WGRIFFITH2 initial release
procedure etl_aa_casas_advising_audit_prq(jobnumber number, processid varchar2, processname varchar2); --- 20251013  WGRIFFITH2 initial release
procedure etl_aa_casas_advising_audit_cps(jobnumber number, processid varchar2, processname varchar2); --- 20251015  WGRIFFITH2 initial release
procedure etl_aa_casas_advising_audit_lxl(jobnumber number, processid varchar2, processname varchar2); --- 20260113  WGRIFFITH2 initial release
procedure etl_aa_casas_advising_tableau(jobnumber number, processid varchar2, processname varchar2); --- 20250709  WGRIFFITH2 initial release
end load_aa_etl_casas;
/

create or replace package body load_aa_etl_casas is

procedure etl_aa_casas_advising_audit_lxl(jobnumber number, processid varchar2, processname varchar2) IS
-- =============================================================================
-- PURPOSE: Identifies and flags STEM lecture-lab enrollment mismatches for resident campus students during active advising windows, marking critical advising alerts for intervention.
--
-- TARGET(S): utl_d_aa.casas_advising_audit
--
-- UNIQUE KEY / INDEX: TERM_CODE, PIDM, CATEGORY_CODE
--
-- BUSINESS LOGIC & CONDITIONS:
-- - Processes only schedule rows in utl_d_aa.casas_advising_schedule where category_code is 'LXL' and the current date falls between FROM_DATE and TO_DATE; executes one loop iteration per matching term.
-- - Restricts analysis to students who appear in utl_d_aa.casas_advising_cohort for the target term.
-- - Considers only section enrollments whose registration status code has the flag stvrsts_incl_sect_enrl set to 'Y' (enrollment counted in section).
-- - Uses only current identity records (spriden_change_ind is null) and filters out deceased students (spbpers_dead_ind is null).
-- - Applies resident campus filter exclusively (ssbsect_camp_code = 'R'), excluding all online and non-resident delivery modes.
-- - Limits analysis to an explicit whitelist of STEM courses: PHYS 201, 202, 231, 232; CHEM 107, 121, 122, 301, 302; BIOL 203, 224, 225, 301, 415.
-- - Classifies course sections as lecture (course number does not end in 'L') or lab (course number ends in 'L').
-- - Identifies missing-lab mismatches: students enrolled in a resident lecture section with no corresponding enrolled resident lab section in the same course.
-- - Identifies missing-lecture mismatches: students enrolled in a resident lab section with no corresponding enrolled resident lecture section in the same course.
-- - Flags waitlist activity: if a student is waitlisted for a missing counterpart section, appends '(WL)' to the alert description.
-- - Marks detected mismatches with red status (critical) at the time of detection (v_etl_date).
-- - Performs gray-window resolution: converts previously red alerts to gray status when no current resident campus mismatch exists for that student and term, extending the monitoring window by 7 days.
--
-- DEPENDENCIES: saturn.sfrstcr, saturn.stvrsts, saturn.ssbsect, saturn.spriden, saturn.spbpers, utl_d_aa.casas_advising_schedule, utl_d_aa.casas_advising_cohort, utl_d_aa.casas_advising_audit, ads_etl.insert_job_log package
--
-- CONSTRAINTS & RISKS:
-- - Complex correlated NOT EXISTS subqueries in the gray-window update phase may exhibit resource contention on large student populations; resident campus filtering does not mitigate this risk.
-- - Deadlock and resource-busy exceptions are handled via automatic retry logic (up to 3 retries with 120-second waits); persistent failures will exit the current term loop and log the error.
-- - Resident campus enforcement is applied across all section joins (both MERGE and gray-window UPDATE), ensuring online and remote delivery modes are never included in mismatch detection.
-- =============================================================================
-- DECLARE
v_etl_date    DATE := SYSDATE;
v_msg         VARCHAR2(2000);
v_instance    VARCHAR2(50) := upper('ALL');
v_partition   NUMBER := 0;
v_cpu         NUMBER := 4;
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_aa_casas_advising_audit_lxl';
v_loop_count  NUMBER := 0;
v_total_loops NUMBER := 0;
v_retry_count NUMBER := 0;
v_max_retries NUMBER := 3;
v_wait_time   NUMBER := 120; -- seconds
c_category_code      CONSTANT VARCHAR2(3)    := 'LXL';
c_status_red_color   CONSTANT VARCHAR2(10)   := 'red';
c_status_red_icon    CONSTANT VARCHAR2(16)   := 'cross';  -- critical
c_status_gray_color  CONSTANT VARCHAR2(10)   := 'gray';
c_status_gray_icon   CONSTANT VARCHAR2(16)   := 'clock';  -- neutral/settled
c_gray_days          CONSTANT PLS_INTEGER    := 7;
c_desc_max_len       CONSTANT PLS_INTEGER    := 1000;
c_status_date_offset CONSTANT NUMBER         := 0;
c_camp_code          CONSTANT VARCHAR2(1)    := 'R';       -- resident campus only; excludes online
e_deadlock EXCEPTION;
PRAGMA EXCEPTION_INIT(e_deadlock, -60);  -- ORA-00060
e_busy EXCEPTION;
PRAGMA EXCEPTION_INIT(e_busy, -54);      -- ORA-00054
/* SCHEDULE CURSOR TYPES */
TYPE r_rec IS RECORD(
term_code      VARCHAR2(6),
next_term_code VARCHAR2(6),
from_date      DATE,
to_date        DATE,
category_code  VARCHAR2(3));
TYPE t_rec IS TABLE OF r_rec INDEX BY PLS_INTEGER;
v_rec t_rec;
BEGIN
SELECT cas.term_code,
       cas.next_term_code,
       cas.from_date,
       cas.to_date,
       cas.category_code
  BULK COLLECT
  INTO v_rec
  FROM utl_d_aa.casas_advising_schedule cas
 WHERE SYSDATE BETWEEN cas.from_date AND cas.to_date
   AND cas.category_code = c_category_code
 ORDER BY 1;
v_total_loops := v_rec.count;
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5')
  INTO v_job_id
  FROM dual;
dbms_lock.sleep(0.5);
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
FOR i IN 1 .. v_rec.count
LOOP
    v_loop_count := v_loop_count + 1;
    v_count      := 0;
    dbms_lock.sleep(0.5);
    v_elapsed := round((SYSDATE - v_etl_date) * 86400);
    v_msg     := 'START - Loop ' || v_loop_count || ' of ' || v_total_loops || ' - ' || v_rec(i).term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
    dbms_output.put_line(v_msg);
    ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
    v_retry_count := 0;
    <<retry_loop>>
    LOOP
        BEGIN
            v_count := 0;
            /* ------------------------------------------------------------------ */
            /* MERGE CURRENT RED/CRITICAL LXL MISMATCHES                          */
            /* Scope: resident campus sections only (ssbsect_camp_code = 'R')     */
            /* ------------------------------------------------------------------ */
            MERGE INTO utl_d_aa.casas_advising_audit tgt
            USING (
            WITH lecture_whitelist AS
             (
              SELECT 'PHYS' AS subj, '201' AS num FROM dual UNION ALL
              SELECT 'PHYS' AS subj, '202' AS num FROM dual UNION ALL
              SELECT 'PHYS' AS subj, '231' AS num FROM dual UNION ALL
              SELECT 'PHYS' AS subj, '232' AS num FROM dual UNION ALL
              SELECT 'CHEM' AS subj, '107' AS num FROM dual UNION ALL
              SELECT 'CHEM' AS subj, '121' AS num FROM dual UNION ALL
              SELECT 'CHEM' AS subj, '122' AS num FROM dual UNION ALL
              SELECT 'CHEM' AS subj, '301' AS num FROM dual UNION ALL
              SELECT 'CHEM' AS subj, '302' AS num FROM dual UNION ALL
              SELECT 'BIOL' AS subj, '203' AS num FROM dual UNION ALL
              SELECT 'BIOL' AS subj, '224' AS num FROM dual UNION ALL
              SELECT 'BIOL' AS subj, '225' AS num FROM dual UNION ALL
              SELECT 'BIOL' AS subj, '301' AS num FROM dual UNION ALL
              SELECT 'BIOL' AS subj, '415' AS num FROM dual),
            cohort_students AS
             (SELECT pidm,
                     term_code
                FROM utl_d_aa.casas_advising_cohort
               WHERE term_code = v_rec(i).term_code),
            enroll AS
             (SELECT /*+ materialize */
              DISTINCT r.sfrstcr_pidm                     AS pidm,
                       r.sfrstcr_term_code                AS term_code,
                       s.ssbsect_crn                      AS crn,
                       s.ssbsect_subj_code                AS subj,
                       s.ssbsect_crse_numb                AS crse_numb,
                       substr(s.ssbsect_crse_numb, 1, 3)  AS base_num,
                       CASE
                           WHEN s.ssbsect_crse_numb LIKE '%L' THEN 1
                           ELSE 0
                       END                                AS is_lab,
                       s.ssbsect_seq_numb                 AS seq,
                       s.ssbsect_term_code                AS sect_term_code
                FROM saturn.sfrstcr r
                JOIN saturn.stvrsts v
                  ON v.stvrsts_code = r.sfrstcr_rsts_code
                 AND v.stvrsts_incl_sect_enrl = 'Y'
                /* Resident campus filter: excludes online (camp_code != 'R') sections */
                JOIN saturn.ssbsect s
                  ON s.ssbsect_term_code = r.sfrstcr_term_code
                 AND s.ssbsect_crn       = r.sfrstcr_crn
                 AND s.ssbsect_camp_code = c_camp_code
                JOIN saturn.spriden p
                  ON p.spriden_pidm       = r.sfrstcr_pidm
                 AND p.spriden_change_ind IS NULL
                JOIN saturn.spbpers pe
                  ON pe.spbpers_pidm     = p.spriden_pidm
                 AND pe.spbpers_dead_ind IS NULL
                JOIN lecture_whitelist lw
                  ON lw.subj = s.ssbsect_subj_code
                 AND lw.num  = substr(s.ssbsect_crse_numb, 1, 3)
               WHERE r.sfrstcr_term_code = v_rec(i).term_code
                 AND EXISTS (SELECT 1
                               FROM cohort_students cs
                              WHERE cs.pidm      = r.sfrstcr_pidm
                                AND cs.term_code = r.sfrstcr_term_code)),
            lecture_enroll AS
             (SELECT e.* FROM enroll e WHERE e.is_lab = 0),
            lab_enroll AS
             (SELECT e.* FROM enroll e WHERE e.is_lab = 1),
            wl_labs AS
             (SELECT /*+ materialize */
              DISTINCT r.sfrstcr_pidm                    AS pidm,
                       s.ssbsect_subj_code               AS subj,
                       substr(s.ssbsect_crse_numb, 1, 3) AS base_num
                FROM saturn.sfrstcr r
                JOIN saturn.stvrsts v
                  ON v.stvrsts_code         = r.sfrstcr_rsts_code
                 AND r.sfrstcr_term_code    = v_rec(i).term_code
                 AND r.sfrstcr_wl_priority IS NOT NULL
                /* Resident campus filter applied to waitlist lab sections */
                JOIN saturn.ssbsect s
                  ON s.ssbsect_term_code  = r.sfrstcr_term_code
                 AND s.ssbsect_crn        = r.sfrstcr_crn
                 AND s.ssbsect_camp_code  = c_camp_code
                JOIN lecture_whitelist lw
                  ON lw.subj = s.ssbsect_subj_code
                 AND lw.num  = substr(s.ssbsect_crse_numb, 1, 3)
               WHERE s.ssbsect_crse_numb LIKE '%L'),
            wl_lectures AS
             (SELECT /*+ materialize */
              DISTINCT r.sfrstcr_pidm                    AS pidm,
                       s.ssbsect_subj_code               AS subj,
                       substr(s.ssbsect_crse_numb, 1, 3) AS base_num
                FROM saturn.sfrstcr r
                JOIN saturn.stvrsts v
                  ON v.stvrsts_code         = r.sfrstcr_rsts_code
                 AND r.sfrstcr_term_code    = v_rec(i).term_code
                 AND r.sfrstcr_wl_priority IS NOT NULL
                /* Resident campus filter applied to waitlist lecture sections */
                JOIN saturn.ssbsect s
                  ON s.ssbsect_term_code  = r.sfrstcr_term_code
                 AND s.ssbsect_crn        = r.sfrstcr_crn
                 AND s.ssbsect_camp_code  = c_camp_code
                JOIN lecture_whitelist lw
                  ON lw.subj = s.ssbsect_subj_code
                 AND lw.num  = substr(s.ssbsect_crse_numb, 1, 3)
               WHERE s.ssbsect_crse_numb NOT LIKE '%L'),
            final_rows AS
             (
              /* Missing lab: student enrolled in a resident lecture with no resident lab counterpart */
              SELECT lml.term_code AS term_code,
                     lml.pidm     AS pidm,
                     'Missing lab for ' || lml.subj || lml.base_num || '_' || lml.seq || '_' || lml.sect_term_code ||
                     CASE
                         WHEN EXISTS (SELECT 1
                                        FROM wl_labs w
                                       WHERE w.pidm     = lml.pidm
                                         AND w.subj     = lml.subj
                                         AND w.base_num = lml.base_num) THEN ' (WL)'
                         ELSE ''
                     END          AS situation,
                     lml.seq,
                     lml.subj,
                     lml.base_num
                FROM lecture_enroll lml_src
                JOIN (SELECT le.*
                        FROM lecture_enroll le
                       WHERE NOT EXISTS (SELECT 1
                                           FROM lab_enroll lb
                                          WHERE lb.pidm     = le.pidm
                                            AND lb.subj     = le.subj
                                            AND lb.base_num = le.base_num)) lml
                  ON lml.pidm     = lml_src.pidm
                 AND lml.subj     = lml_src.subj
                 AND lml.base_num = lml_src.base_num
              UNION ALL
              /* Missing lecture: student enrolled in a resident lab with no resident lecture counterpart */
              SELECT lml2.term_code AS term_code,
                     lml2.pidm     AS pidm,
                     'Missing lecture for ' || lml2.subj || lml2.base_num || '_' || lml2.seq || '_' || lml2.sect_term_code ||
                     CASE
                         WHEN EXISTS (SELECT 1
                                        FROM wl_lectures w
                                       WHERE w.pidm     = lml2.pidm
                                         AND w.subj     = lml2.subj
                                         AND w.base_num = lml2.base_num) THEN ' (WL)'
                         ELSE ''
                     END           AS situation,
                     lml2.seq,
                     lml2.subj,
                     lml2.base_num
                FROM lab_enroll lml2_src
                JOIN (SELECT lb.*
                        FROM lab_enroll lb
                       WHERE NOT EXISTS (SELECT 1
                                           FROM lecture_enroll le
                                          WHERE le.pidm     = lb.pidm
                                            AND le.subj     = lb.subj
                                            AND le.base_num = lb.base_num)) lml2
                  ON lml2.pidm     = lml2_src.pidm
                 AND lml2.subj     = lml2_src.subj
                 AND lml2.base_num = lml2_src.base_num),
            student_status AS
             (SELECT fr.term_code                                                                             AS term_code,
                     fr.pidm                                                                                  AS pidm,
                     c_category_code                                                                          AS category_code,
                     (v_etl_date + c_status_date_offset)                                                      AS status_date,
                     c_status_red_color                                                                       AS status_color,
                     c_status_red_icon                                                                        AS status_icon,
                     listagg(fr.situation, '; ') WITHIN GROUP (ORDER BY fr.term_code, fr.subj, fr.base_num, fr.seq) AS situation
                FROM final_rows fr
               GROUP BY fr.term_code,
                        fr.pidm)
            SELECT ss.term_code,
                   ss.pidm,
                   ss.category_code,
                   ss.status_color,
                   ss.status_icon,
                   substr(ss.situation, 1, c_desc_max_len) AS status_desc,
                   v_etl_date                              AS from_date,   -- first detection timestamp
                   cas.to_date                             AS to_date,
                   v_etl_date                              AS activity_date
              FROM student_status ss
              JOIN utl_d_aa.casas_advising_schedule cas
                ON cas.term_code      = ss.term_code
               AND cas.category_code  = ss.category_code
               AND v_etl_date BETWEEN cas.from_date AND cas.to_date) src
            ON (tgt.term_code     = src.term_code
            AND tgt.pidm          = src.pidm
            AND tgt.category_code = src.category_code)
            WHEN MATCHED THEN
                UPDATE
                   SET tgt.status_color  = src.status_color,
                       tgt.status_icon   = src.status_icon,
                       tgt.status_desc   = src.status_desc,
                       tgt.to_date       = src.to_date,       -- preserve FROM_DATE; update TO_DATE only
                       tgt.activity_date = src.activity_date
            WHEN NOT MATCHED THEN
                INSERT (term_code,
                        pidm,
                        category_code,
                        status_color,
                        status_icon,
                        status_desc,
                        from_date,
                        to_date,
                        activity_date)
                VALUES (src.term_code,
                        src.pidm,
                        src.category_code,
                        src.status_color,
                        src.status_icon,
                        src.status_desc,
                        src.from_date,
                        src.to_date,
                        src.activity_date);
            v_count := SQL%ROWCOUNT;
            COMMIT;
            dbms_lock.sleep(0.5);
            v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
            v_msg         := 'MERGE - ' || v_rec(i).term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
            v_total_count := v_total_count + v_count;
            dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
            ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
            /* ------------------------------------------------------------------ */
            /* GRAY-WINDOW UPDATE                                                  */
            /* Converts previously red LXL rows to gray when no current resident  */
            /* campus mismatch exists for that student and term.                  */
            /* Resident campus filter (camp_code = 'R') applied to all ssbsect    */
            /* joins inside the correlated NOT EXISTS subqueries.                 */
            /* ------------------------------------------------------------------ */
            UPDATE utl_d_aa.casas_advising_audit
               SET status_color  = c_status_gray_color,
                   status_icon   = c_status_gray_icon,
                   status_desc   = 'Lab/Lecture found recently; continued monitoring',
                   to_date       = v_etl_date + c_gray_days,  -- extend monitoring window
                   activity_date = v_etl_date
             WHERE category_code = c_category_code
               AND term_code     = v_rec(i).term_code
               AND status_color  = c_status_red_color
               AND NOT EXISTS (
                       SELECT 1
                         FROM dual
                        WHERE EXISTS (
                                  /* Resident lecture without matching resident lab */
                                  SELECT 1
                                    FROM saturn.sfrstcr r_lec
                                    JOIN saturn.stvrsts v_lec
                                      ON v_lec.stvrsts_code        = r_lec.sfrstcr_rsts_code
                                     AND v_lec.stvrsts_incl_sect_enrl = 'Y'
                                    /* Resident campus filter */
                                    JOIN saturn.ssbsect s_lec
                                      ON s_lec.ssbsect_term_code  = r_lec.sfrstcr_term_code
                                     AND s_lec.ssbsect_crn        = r_lec.sfrstcr_crn
                                     AND s_lec.ssbsect_camp_code  = c_camp_code
                                   WHERE r_lec.sfrstcr_term_code = term_code  -- correlate to target row
                                     AND r_lec.sfrstcr_pidm      = pidm       -- correlate to target row
                                     AND (s_lec.ssbsect_subj_code, substr(s_lec.ssbsect_crse_numb, 1, 3))
                                             IN (SELECT 'PHYS', '201' FROM dual UNION ALL
                                                 SELECT 'PHYS', '202' FROM dual UNION ALL
                                                 SELECT 'PHYS', '231' FROM dual UNION ALL
                                                 SELECT 'PHYS', '232' FROM dual UNION ALL
                                                 SELECT 'CHEM', '107' FROM dual UNION ALL
                                                 SELECT 'CHEM', '121' FROM dual UNION ALL
                                                 SELECT 'CHEM', '122' FROM dual UNION ALL
                                                 SELECT 'CHEM', '301' FROM dual UNION ALL
                                                 SELECT 'CHEM', '302' FROM dual UNION ALL
                                                 SELECT 'BIOL', '203' FROM dual UNION ALL
                                                 SELECT 'BIOL', '224' FROM dual UNION ALL
                                                 SELECT 'BIOL', '225' FROM dual UNION ALL
                                                 SELECT 'BIOL', '301' FROM dual UNION ALL
                                                 SELECT 'BIOL', '415' FROM dual)
                                     AND s_lec.ssbsect_crse_numb NOT LIKE '%L'
                                     AND NOT EXISTS (
                                             SELECT 1
                                               FROM saturn.sfrstcr r_lab
                                               JOIN saturn.stvrsts v_lab
                                                 ON v_lab.stvrsts_code           = r_lab.sfrstcr_rsts_code
                                                AND v_lab.stvrsts_incl_sect_enrl = 'Y'
                                               /* Resident campus filter on inner lab join */
                                               JOIN saturn.ssbsect s_lab
                                                 ON s_lab.ssbsect_term_code  = r_lab.sfrstcr_term_code
                                                AND s_lab.ssbsect_crn        = r_lab.sfrstcr_crn
                                                AND s_lab.ssbsect_camp_code  = c_camp_code
                                              WHERE r_lab.sfrstcr_term_code              = r_lec.sfrstcr_term_code
                                                AND r_lab.sfrstcr_pidm                   = r_lec.sfrstcr_pidm
                                                AND s_lab.ssbsect_subj_code              = s_lec.ssbsect_subj_code
                                                AND substr(s_lab.ssbsect_crse_numb, 1, 3) = substr(s_lec.ssbsect_crse_numb, 1, 3)
                                                AND s_lab.ssbsect_crse_numb LIKE '%L'))
                           OR EXISTS (
                                  /* Resident lab without matching resident lecture */
                                  SELECT 1
                                    FROM saturn.sfrstcr r_lab
                                    JOIN saturn.stvrsts v_lab
                                      ON v_lab.stvrsts_code           = r_lab.sfrstcr_rsts_code
                                     AND v_lab.stvrsts_incl_sect_enrl = 'Y'
                                    /* Resident campus filter */
                                    JOIN saturn.ssbsect s_lab
                                      ON s_lab.ssbsect_term_code  = r_lab.sfrstcr_term_code
                                     AND s_lab.ssbsect_crn        = r_lab.sfrstcr_crn
                                     AND s_lab.ssbsect_camp_code  = c_camp_code
                                   WHERE r_lab.sfrstcr_term_code = term_code  -- correlate to target row
                                     AND r_lab.sfrstcr_pidm      = pidm       -- correlate to target row
                                     AND (s_lab.ssbsect_subj_code, substr(s_lab.ssbsect_crse_numb, 1, 3))
                                             IN (SELECT 'PHYS', '201' FROM dual UNION ALL
                                                 SELECT 'PHYS', '202' FROM dual UNION ALL
                                                 SELECT 'PHYS', '231' FROM dual UNION ALL
                                                 SELECT 'PHYS', '232' FROM dual UNION ALL
                                                 SELECT 'CHEM', '107' FROM dual UNION ALL
                                                 SELECT 'CHEM', '121' FROM dual UNION ALL
                                                 SELECT 'CHEM', '122' FROM dual UNION ALL
                                                 SELECT 'CHEM', '301' FROM dual UNION ALL
                                                 SELECT 'CHEM', '302' FROM dual UNION ALL
                                                 SELECT 'BIOL', '203' FROM dual UNION ALL
                                                 SELECT 'BIOL', '224' FROM dual UNION ALL
                                                 SELECT 'BIOL', '225' FROM dual UNION ALL
                                                 SELECT 'BIOL', '301' FROM dual UNION ALL
                                                 SELECT 'BIOL', '415' FROM dual)
                                     AND s_lab.ssbsect_crse_numb LIKE '%L'
                                     AND NOT EXISTS (
                                             SELECT 1
                                               FROM saturn.sfrstcr r_lec
                                               JOIN saturn.stvrsts v_lec
                                                 ON v_lec.stvrsts_code           = r_lec.sfrstcr_rsts_code
                                                AND v_lec.stvrsts_incl_sect_enrl = 'Y'
                                               /* Resident campus filter on inner lecture join */
                                               JOIN saturn.ssbsect s_lec
                                                 ON s_lec.ssbsect_term_code  = r_lec.sfrstcr_term_code
                                                AND s_lec.ssbsect_crn        = r_lec.sfrstcr_crn
                                                AND s_lec.ssbsect_camp_code  = c_camp_code
                                              WHERE r_lec.sfrstcr_term_code               = r_lab.sfrstcr_term_code
                                                AND r_lec.sfrstcr_pidm                    = r_lab.sfrstcr_pidm
                                                AND s_lec.ssbsect_subj_code               = s_lab.ssbsect_subj_code
                                                AND substr(s_lec.ssbsect_crse_numb, 1, 3) = substr(s_lab.ssbsect_crse_numb, 1, 3)
                                                AND s_lec.ssbsect_crse_numb NOT LIKE '%L')));
            v_count := SQL%ROWCOUNT;
            COMMIT;
            dbms_lock.sleep(0.5);
            v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
            v_msg         := 'GRAY-WINDOW UPDATE - ' || v_rec(i).term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
            v_total_count := v_total_count + v_count;
            dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
            ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
            EXIT;
        EXCEPTION
            WHEN e_deadlock THEN
                v_retry_count := v_retry_count + 1;
                IF v_retry_count > v_max_retries THEN
                    dbms_lock.sleep(0.5);
                    v_elapsed := round((SYSDATE - v_etl_date) * 86400);
                    v_msg     := '!!!-00060: deadlock detected while waiting for resource. Max retries exceeded after ' || (v_max_retries * v_wait_time) || ' seconds';
                    dbms_output.put_line(v_msg);
                    ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
                    EXIT;
                ELSE
                    dbms_lock.sleep(0.5);
                    v_elapsed := round((SYSDATE - v_etl_date) * 86400);
                    v_msg     := 'Deadlock detected while waiting for resource - waiting ' || v_wait_time || ' seconds for retry attempt number ' || v_retry_count;
                    dbms_output.put_line(v_msg);
                    ads_etl.insert_job_log(v_proc, 'WARNING', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
                    dbms_lock.sleep(v_wait_time);
                    CONTINUE retry_loop;
                END IF;
            WHEN e_busy THEN
                v_retry_count := v_retry_count + 1;
                IF v_retry_count > v_max_retries THEN
                    dbms_lock.sleep(0.5);
                    v_elapsed := round((SYSDATE - v_etl_date) * 86400);
                    v_msg     := '!!!-00054: resource busy. Max retries exceeded after ' || (v_max_retries * v_wait_time) || ' seconds';
                    dbms_output.put_line(v_msg);
                    ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
                    EXIT;
                ELSE
                    dbms_lock.sleep(0.5);
                    v_elapsed := round((SYSDATE - v_etl_date) * 86400);
                    v_msg     := 'Resource busy - waiting ' || v_wait_time || ' seconds for retry attempt number ' || v_retry_count;
                    dbms_output.put_line(v_msg);
                    ads_etl.insert_job_log(v_proc, 'WARNING', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
                    dbms_lock.sleep(v_wait_time);
                    CONTINUE retry_loop;
                END IF;
            WHEN OTHERS THEN
                dbms_lock.sleep(0.5);
                v_elapsed := round((SYSDATE - v_etl_date) * 86400);
                v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
                dbms_output.put_line(v_msg);
                ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
                EXIT;
        END;
    END LOOP retry_loop;
    dbms_output.put_line(' --------- ');
END LOOP;
dbms_lock.sleep(0.5);
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
EXCEPTION
    WHEN OTHERS THEN
        dbms_lock.sleep(0.5);
        v_elapsed := round((SYSDATE - v_etl_date) * 86400);
        v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
        dbms_output.put_line(v_msg);
        ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
END etl_aa_casas_advising_audit_lxl;

procedure etl_aa_casas_advising_audit_cps(jobnumber number, processid varchar2, processname varchar2) IS
-- =============================================================================
-- PURPOSE: Identify and track undergraduate full-time students with fewer than 12 CPOS-eligible credit hours, assigning dashboard status indicators (RED, YELLOW, GRAY) based on part-of-term proximity, with automatic conversion to GRAY status and a 7-day grace period after issues resolve.
--
-- TARGET(S): utl_d_aa.casas_advising_audit
--
-- UNIQUE KEY / INDEX: TERM_CODE, PIDM, CATEGORY_CODE
--
-- BUSINESS LOGIC & CONDITIONS:
-- - Processes only active terms and categories where SYSDATE falls between FROM_DATE and TO_DATE in the advising schedule.
-- - Identifies and tracks undergraduate full-time (levl_code='UG', status='FT') students enrolled in non-CPOS-eligible courses.
-- - Restricts scope to students who are active members of the CASAS advising cohort for the processing term.
-- - Restricts scope to students with current and active FAFSA eligibility (rcrapp1_infc_code='EDE', rcrapp1_curr_rec_ind='Y') whose aid year matches the term's financial aid processing year.
-- - Excludes students who have obtained approved scholarship appeals (zcvists_code IN (112, 1) on conduct case type 19).
-- - Identifies students whose total CPOS-ineligible credit hours fall below 12 hours when subtracted from their overall term enrollment hours.
-- - Assigns severity levels and UI status indicators based on proximity to part-of-term start date:
--   * RED (cross icon): Student is within plus-or-minus 14 days of the part-of-term start date (most urgent).
--   * YELLOW (exclamation icon): Student is before the part-of-term start date minus 14 days (caution phase).
--   * GRAY (clock icon): Student is after the part-of-term start date plus 14 days (informational/resolved phase).
-- - Determines "worst-case-wins" status across all non-CPOS courses for a single student using numeric severity scoring (3=RED, 2=YELLOW, 1=GRAY) to ensure deterministic aggregation.
-- - Merges identified students into the audit table: inserts new records for students not previously tracked; updates existing records only if they are not already in GRAY status (protecting 7-day grace window from being overwritten).
-- - When a student's CPOS shortfall condition no longer exists in the active enrollment data, converts both RED and YELLOW records to GRAY status and extends the TO_DATE by 7 days to allow dashboard visibility of the resolved issue.
-- - Prevents re-activation of records whose TO_DATE window has already expired by checking that SYSDATE is less than or equal to the current TO_DATE before extending.
-- - Re-evaluates all eligibility guards (cohort membership, FAFSA status, scholarship appeals, course-level CPOS flags) during gray-window conversion to ensure the student genuinely no longer qualifies.
-- - Processes one term and category combination per loop iteration to manage transaction scope and enable per-term logging.
--
-- DEPENDENCIES:
-- - utl_d_aa.casas_advising_schedule: defines active term/category time windows.
-- - utl_d_aa.casas_advising_cohort: identifies students active in the cohort for a given term.
-- - utl_d_aa.casas_advising_audit: target table for insert/update operations.
-- - utl_d_aim.szrcrse: course enrollment records with part-of-term, subject, number, section, and credit hour details.
-- - utl_d_aim.szrenrl: enrollment status and term hours by student.
-- - rcrapp1: financial aid eligibility and aid year application data.
-- - saturn.sfrscre: course-level CPOS (Financial Aid eligibility) flags (sfrscre_for_aid_cde='N' = ineligible).
-- - zbtm.terms_by_group_v: maps term codes to financial aid processing years.
-- - spriden: student identity and change indicators.
-- - zconduct.zcbirep, zconduct.zcbcase, zconduct.zcvists: scholarship appeal case and status data.
-- - ads_etl.insert_job_log: external logging procedure for ETL status and metrics.
-- - dbms_output: console output for runtime diagnostics.
--
-- CONSTRAINTS & RISKS:
-- - Student identification relies on exact PIDM and term code matching across disconnected systems; any mismatch breaks cohort/FAFSA eligibility checks.
-- - CPOS flag determination requires the maximum runseq_no from sfrscre; if runseq_no is missing or incorrectly sequenced, the CPOS determination may be stale.
-- - FAFSA eligibility is point-in-time (rcrapp1_curr_rec_ind='Y'); students whose aid eligibility is revoked mid-cycle may not transition to GRAY even after the shortfall resolves.
-- - Scholarship appeal exclusion relies on conduct case office_type=19 and zcvists_code IN (112,1); missing or incorrectly coded records may allow excluded students to appear on the dashboard.
-- - Complex multi-join query (10+ tables) with subqueries increases CPU consumption and risk of execution plan degradation; recommend index on szrcrse(term_code, pidm), szrenrl(term_code, pidm), sfrscre(term_code, pidm, crn).
-- - Deadlock (-60) and resource busy (-54) errors are retried up to 3 times with 120-second wait intervals; persistent contention may block downstream ETL processes.
-- - The 7-day gray grace period (c_gray_days=7) is hardcoded; extending the grace period requires code modification.
-- - Processes all active terms in a single batch loop; if any term takes excessively long, subsequent terms are delayed.
-- =============================================================================
--DECLARE
-- Timestamps and telemetry
v_etl_date    DATE := SYSDATE;
v_msg         VARCHAR2(2000);
v_instance    VARCHAR2(50) := upper('ALL');
v_partition   NUMBER := 0;
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_aa_casas_advising_audit_cps';
-- Loop control
v_loop_count  NUMBER := 0;
v_total_loops NUMBER := 0;
-- Retry control
v_retry_count NUMBER := 0;
v_max_retries NUMBER := 3;
v_wait_time   NUMBER := 120; -- seconds
-- ---------------------------------------------------------------------------
-- STATUS/UI CONSTANTS
-- Severity integers are used inside SQL MAX() to ensure deterministic
-- "worst-case wins" aggregation across courses for a single student.
--   3 = RED   (most severe — within ±14 days of ptrm_start)
--   2 = YELLOW (caution  — before ptrm_start - 14)
--   1 = GRAY   (neutral  — after  ptrm_start + 14)
-- The integer is resolved back to color/icon strings in the outer SELECT.
-- ---------------------------------------------------------------------------
c_status_red_color    CONSTANT VARCHAR2(10) := 'red';
c_status_red_icon     CONSTANT VARCHAR2(16) := 'cross';
c_status_yellow_color CONSTANT VARCHAR2(10) := 'yellow';
c_status_yellow_icon  CONSTANT VARCHAR2(16) := 'exclamation';
c_status_gray_color   CONSTANT VARCHAR2(10) := 'gray';
c_status_gray_icon    CONSTANT VARCHAR2(16) := 'clock';
c_gray_days           CONSTANT PLS_INTEGER := 7;
c_desc_max_len        CONSTANT PLS_INTEGER := 1000;
-- Named exception mapping
e_deadlock EXCEPTION;
PRAGMA EXCEPTION_INIT(e_deadlock, -60);
e_busy EXCEPTION;
PRAGMA EXCEPTION_INIT(e_busy, -54);
-- Cursor/record types
TYPE r_rec IS RECORD(
term_code      VARCHAR2(6),
next_term_code VARCHAR2(6),
from_date      DATE,
to_date        DATE,
category_code  VARCHAR2(3));
TYPE t_rec IS TABLE OF r_rec INDEX BY PLS_INTEGER;
v_rec t_rec;
BEGIN
SELECT cas.term_code,
       cas.next_term_code,
       cas.from_date,
       cas.to_date,
       cas.category_code
  BULK COLLECT
  INTO v_rec
  FROM utl_d_aa.casas_advising_schedule cas
 WHERE SYSDATE BETWEEN cas.from_date AND cas.to_date
   AND cas.category_code = 'CPS'
 ORDER BY 1;
v_total_loops := v_rec.count;
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
dbms_lock.sleep(0.5);
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
FOR i IN 1 .. v_rec.count
LOOP
v_loop_count := v_loop_count + 1;
v_count      := 0;
dbms_lock.sleep(0.5);
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - Loop ' || v_loop_count || ' of ' || v_total_loops || ' - ' || v_rec(i).term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
v_retry_count := 0;
<<retry_loop>>
LOOP
BEGIN
v_count := 0;
-- ================================================================
-- STEP 1: MERGE — Insert or update active CPOS-shortfall students
-- ================================================================
-- FIX (CAUSE 5): Severity-integer pattern replaces MAX(color_string).
--   Inner aggregation computes MAX(severity_int) per student so that
--   "worst course wins" is deterministic. Outer SELECT maps the int
--   back to the appropriate color and icon constants.
--
-- FIX (CAUSE 3): WHEN MATCHED UPDATE adds WHERE clause:
--   WHERE tgt.status_color != c_status_gray_color
--   This prevents the MERGE from overwriting a record that is
--   currently in its 7-day gray grace period back to RED/YELLOW,
--   which would be the wrong transition on a subsequent ETL run
--   where the student happens to still appear as "active" due to
--   the extended TO_DATE not yet expiring.
-- ================================================================
MERGE INTO utl_d_aa.casas_advising_audit tgt
USING (
WITH cohort_students AS
 (
  -- Active cohort for this term only
  SELECT pidm,
          term_code
    FROM utl_d_aa.casas_advising_cohort
   WHERE term_code = v_rec(i).term_code),
raw_cpos AS
 (
  -- Resolve non-CPOS courses per student with severity scoring
  SELECT crse.term_code,
          crse.pidm,
          v_rec(i).category_code AS category_code,
          -- FIX (CAUSE 5): Assign a numeric severity so MAX() is
          -- deterministic and correctly "worst-case-wins" across
          -- all non-CPOS courses for one student in one term.
          -- String MAX on colors is non-deterministic by intent.
          MAX(CASE
              WHEN SYSDATE BETWEEN (crse.ptrm_start - 14) AND (crse.ptrm_start + 14) THEN
               3 -- RED severity
              WHEN SYSDATE < (crse.ptrm_start - 14) THEN
               2 -- YELLOW severity
              WHEN SYSDATE > (crse.ptrm_start + 14) THEN
               1 -- GRAY severity
              ELSE
               1 -- fallback to GRAY
              END) AS status_severity,
          MAX(enrl.term_hours) AS term_hours,
          SUM(crse.credit_hr) AS not_cpos_hours,
          'Non-financial aid eligible credit < 12; Not CPOS: ' || listagg(crse.subj || crse.numb || '_' || crse.sect || '_' || crse.term_code || ' (' || crse.credit_hr || ')', '; ') within GROUP(ORDER BY crse.subj, crse.numb, crse.sect) AS situation
    FROM utl_d_aim.szrcrse crse
    JOIN utl_d_aim.szrenrl enrl
      ON enrl.term_code = crse.term_code
     AND enrl.pidm = crse.pidm
     AND enrl.levl_code = 'UG'
     AND enrl.status = 'FT'
    JOIN cohort_students cs
      ON cs.term_code = crse.term_code
     AND cs.pidm = crse.pidm
    JOIN rcrapp1
      ON rcrapp1_pidm = crse.pidm
     AND rcrapp1_infc_code = 'EDE'
     AND rcrapp1_curr_rec_ind = 'Y'
     AND rcrapp1_aidy_code IN (SELECT DISTINCT terms.fa_proc_year FROM zbtm.terms_by_group_v terms WHERE terms.term_code = v_rec(i).term_code)
    LEFT JOIN (
               -- Approved scholarship appeal exclusion
               SELECT i.zcbirep_pidm AS pidm
                 FROM zconduct.zcbirep i
                 JOIN zconduct.zcbcase c
                   ON c.zcbcase_id = i.zcbirep_case_id
                  AND c.office_type = 19
                 JOIN spriden
                   ON spriden_pidm = i.zcbirep_pidm
                  AND spriden_change_ind IS NULL
                 JOIN zconduct.zcvists s
                   ON s.zcvists_code = i.zcbirep_ists_code
                WHERE field_1 = v_rec(i).term_code
                  AND zcvists_code IN (112, 1)) sch_app
      ON sch_app.pidm = crse.pidm
    JOIN saturn.sfrscre cpos
      ON cpos.sfrscre_term_code = crse.term_code
     AND cpos.sfrscre_pidm = crse.pidm
     AND cpos.sfrscre_crn = crse.crn
     AND cpos.sfrscre_runseq_no = (SELECT MAX(cpos2.sfrscre_runseq_no)
                                     FROM saturn.sfrscre cpos2
                                    WHERE cpos2.sfrscre_pidm = cpos.sfrscre_pidm
                                      AND cpos2.sfrscre_term_code = cpos.sfrscre_term_code)
   WHERE crse.term_code = v_rec(i).term_code
     AND cpos.sfrscre_for_aid_cde = 'N'
     AND sch_app.pidm IS NULL
   GROUP BY crse.term_code,
             crse.pidm
  HAVING MAX(enrl.term_hours) - SUM(crse.credit_hr) < 12),
student_status AS
 (
  -- FIX (CAUSE 5): Map numeric severity back to color/icon strings
  SELECT rc.term_code,
          rc.pidm,
          rc.category_code,
          CASE rc.status_severity
          WHEN 3 THEN
           c_status_red_color
          WHEN 2 THEN
           c_status_yellow_color
          ELSE
           c_status_gray_color -- severity 1 or any fallback
          END AS status_color,
          CASE rc.status_severity
          WHEN 3 THEN
           c_status_red_icon
          WHEN 2 THEN
           c_status_yellow_icon
          ELSE
           c_status_gray_icon
          END AS status_icon,
          rc.term_hours,
          rc.not_cpos_hours,
          rc.situation
    FROM raw_cpos rc)
SELECT ss.term_code,
       ss.pidm,
       ss.category_code,
       ss.status_color,
       ss.status_icon,
       substr(ss.situation, 1, c_desc_max_len) AS status_desc,
       v_etl_date AS from_date,
       cas.to_date AS to_date,
       v_etl_date AS activity_date
  FROM student_status ss
  JOIN utl_d_aa.casas_advising_schedule cas
    ON cas.term_code = ss.term_code
   AND cas.category_code = ss.category_code
   AND v_etl_date BETWEEN cas.from_date AND cas.to_date) src ON (tgt.term_code = src.term_code AND tgt.pidm = src.pidm AND tgt.category_code = src.category_code) WHEN MATCHED THEN
UPDATE
   SET tgt.status_color  = src.status_color,
       tgt.status_icon   = src.status_icon,
       tgt.status_desc   = src.status_desc,
       tgt.to_date       = src.to_date,
       tgt.activity_date = src.activity_date
-- FIX (CAUSE 3): Do NOT overwrite a record that is currently in
-- its 7-day gray grace window. The student's CPOS issue has already
-- been resolved and the gray-window step extended TO_DATE. Allowing
-- the MERGE to flip it back to RED/YELLOW would undo the gray
-- transition. The gray step below correctly re-evaluates each run;
-- if the issue genuinely recurs, the student will not match the
-- gray guard and this MERGE will be free to update them normally
-- on the next ETL cycle once gray clears.
 WHERE tgt.status_color != c_status_gray_color
WHEN NOT MATCHED THEN
INSERT
(term_code,
 pidm,
 category_code,
 status_color,
 status_icon,
 status_desc,
 from_date,
 to_date,
 activity_date)
VALUES
(src.term_code,
 src.pidm,
 src.category_code,
 src.status_color,
 src.status_icon,
 src.status_desc,
 src.from_date,
 src.to_date,
 src.activity_date);
v_count := SQL%ROWCOUNT;
COMMIT;
dbms_lock.sleep(0.5);
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || v_rec(i).term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count;
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- ================================================================
-- STEP 2: GRAY-WINDOW EXPIRATION (7-DAY GRACE PERIOD)
-- ================================================================
-- Converts RED *and* YELLOW records to GRAY when the student no
-- longer meets the CPOS-shortfall condition. Extends TO_DATE by
-- c_gray_days so the record remains visible as a neutral indicator.
--
-- FIX (CAUSE 1): The original UPDATE only targeted status_color =
--   c_status_red_color. YELLOW records that resolved were never
--   converted, causing them to stay on the dashboard indefinitely.
--   Fixed by adding: OR tgt.status_color = c_status_yellow_color
--
-- FIX (CAUSE 2): The original NOT EXISTS subquery was missing the
--   cohort and FAFSA guards present in the MERGE source. Without
--   them, students who left the cohort or lost FAFSA eligibility
--   would still match the NOT EXISTS check (finding no rows) and
--   therefore still be blocked from transitioning to GRAY. The
--   recheck subquery now faithfully mirrors all join conditions
--   from the MERGE source query.
--
-- FIX (CAUSE 4): Added AND v_etl_date <= tgt.to_date to prevent
--   accidentally re-activating a record whose window already closed.
--   Without this, a record with a past TO_DATE could receive a new
--   extended TO_DATE of v_etl_date + 7, resurrecting it incorrectly.
-- ================================================================
UPDATE utl_d_aa.casas_advising_audit tgt
   SET tgt.status_color  = c_status_gray_color,
       tgt.status_icon   = c_status_gray_icon,
       tgt.status_desc   = 'CPOS issue found recently; continued monitoring',
       tgt.to_date       = v_etl_date + c_gray_days,
       tgt.activity_date = v_etl_date
 WHERE tgt.category_code = v_rec(i).category_code
   AND tgt.term_code = v_rec(i).term_code
      -- FIX (CAUSE 1): Target both RED and YELLOW for gray conversion.
      -- Original code only converted RED → GRAY, leaving YELLOW records
      -- permanently stuck on the dashboard after the condition resolved.
   AND tgt.status_color IN (c_status_red_color, c_status_yellow_color)
      -- FIX (CAUSE 4): Only act on records whose window has not yet closed.
      -- Prevents accidentally extending a naturally expired record.
   AND v_etl_date <= tgt.to_date
      -- Student must NOT still have an active CPOS shortfall.
      -- FIX (CAUSE 2): Subquery now mirrors all guards from the MERGE source
      -- (cohort, FAFSA, scholarship appeal exclusion) so the recheck is a
      -- faithful, symmetric evaluation. Previously missing cohort + FAFSA
      -- joins meant students who lost eligibility were still found here,
      -- blocking their gray transition incorrectly.
   AND NOT EXISTS (SELECT 1
          FROM (SELECT crse.pidm
                  FROM utl_d_aim.szrcrse crse
                  JOIN utl_d_aim.szrenrl enrl
                    ON enrl.term_code = crse.term_code
                   AND enrl.pidm = crse.pidm
                   AND enrl.levl_code = 'UG'
                   AND enrl.status = 'FT'
                -- FIX (CAUSE 2): Cohort guard was absent in original.
                  JOIN utl_d_aa.casas_advising_cohort cs
                    ON cs.term_code = crse.term_code
                   AND cs.pidm = crse.pidm
                -- FIX (CAUSE 2): FAFSA guard was absent in original.
                  JOIN rcrapp1
                    ON rcrapp1_pidm = crse.pidm
                   AND rcrapp1_infc_code = 'EDE'
                   AND rcrapp1_curr_rec_ind = 'Y'
                   AND rcrapp1_aidy_code IN (SELECT DISTINCT terms.fa_proc_year FROM zbtm.terms_by_group_v terms WHERE terms.term_code = v_rec(i).term_code)
                -- FIX (CAUSE 2): Scholarship appeal exclusion was absent.
                  LEFT JOIN (SELECT i.zcbirep_pidm AS pidm
                              FROM zconduct.zcbirep i
                              JOIN zconduct.zcbcase c
                                ON c.zcbcase_id = i.zcbirep_case_id
                               AND c.office_type = 19
                              JOIN spriden
                                ON spriden_pidm = i.zcbirep_pidm
                               AND spriden_change_ind IS NULL
                              JOIN zconduct.zcvists s
                                ON s.zcvists_code = i.zcbirep_ists_code
                             WHERE field_1 = v_rec(i).term_code
                               AND zcvists_code IN (112, 1)) sch_app
                    ON sch_app.pidm = crse.pidm
                  JOIN saturn.sfrscre cpos
                    ON cpos.sfrscre_term_code = crse.term_code
                   AND cpos.sfrscre_pidm = crse.pidm
                   AND cpos.sfrscre_crn = crse.crn
                   AND cpos.sfrscre_runseq_no = (SELECT MAX(cpos2.sfrscre_runseq_no)
                                                   FROM saturn.sfrscre cpos2
                                                  WHERE cpos2.sfrscre_pidm = cpos.sfrscre_pidm
                                                    AND cpos2.sfrscre_term_code = cpos.sfrscre_term_code)
                 WHERE crse.term_code = tgt.term_code
                   AND crse.pidm = tgt.pidm
                   AND cpos.sfrscre_for_aid_cde = 'N'
                   AND sch_app.pidm IS NULL
                 GROUP BY crse.pidm,
                          enrl.term_hours
                HAVING enrl.term_hours - SUM(crse.credit_hr) < 12) still_in_violation);
v_count := SQL%ROWCOUNT;
COMMIT;
dbms_lock.sleep(0.5);
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'GRAY-WINDOW UPDATE (CPS) - ' || v_rec(i).term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count;
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
EXIT; -- Success — exit retry loop
EXCEPTION
WHEN e_deadlock THEN
v_retry_count := v_retry_count + 1;
IF v_retry_count > v_max_retries THEN
dbms_lock.sleep(0.5);
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := '!!!-00060: deadlock detected while waiting for resource. ' || 'Max retries exceeded after ' || (v_max_retries * v_wait_time) || ' seconds';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
EXIT;
ELSE
dbms_lock.sleep(0.5);
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'Deadlock detected while waiting for resource - waiting ' || v_wait_time || ' seconds for retry attempt number ' || v_retry_count;
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'WARNING', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
dbms_lock.sleep(v_wait_time);
CONTINUE retry_loop;
END IF;
WHEN e_busy THEN
v_retry_count := v_retry_count + 1;
IF v_retry_count > v_max_retries THEN
dbms_lock.sleep(0.5);
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := '!!!-00054: resource busy. Max retries exceeded after ' || (v_max_retries * v_wait_time) || ' seconds';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
EXIT;
ELSE
dbms_lock.sleep(0.5);
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'Resource busy - waiting ' || v_wait_time || ' seconds for retry attempt number ' || v_retry_count;
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'WARNING', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
dbms_lock.sleep(v_wait_time);
CONTINUE retry_loop;
END IF;
WHEN OTHERS THEN
dbms_lock.sleep(0.5);
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
EXIT;
END;
END LOOP retry_loop;
dbms_output.put_line(' --------- ');
END LOOP; -- v_rec
dbms_lock.sleep(0.5);
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
EXCEPTION
WHEN OTHERS THEN
dbms_lock.sleep(0.5);
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
END etl_aa_casas_advising_audit_cps;

procedure etl_aa_casas_advising_audit_prq(jobnumber number, processid varchar2, processname varchar2) IS
--
-- PURPOSE: Flags and tracks prerequisite issues for cohort students by term to support CASAS advising alerts and follow-up monitoring.
--
-- TABLE: utl_d_aa.casas_advising_audit
--
-- UNIQUE INDEX: TERM_CODE, PIDM, CATEGORY_CODE
--
-- CONDITIONS:
-- Processes one term at a time for every row in utl_d_aa.casas_advising_schedule where SYSDATE is between FROM_DATE and TO_DATE and CATEGORY_CODE = 'PRQ'.
-- Includes only students listed in utl_d_aa.casas_advising_cohort for the current TERM_CODE.
-- Identifies prerequisite problems from utl_d_aim.szrpreq for the same TERM_CODE and student (PIDM).
-- Excludes any SZRPREQ rows where an override exists (SFRSRPO_OVERRIDE is NULL must be true).
-- Excludes prerequisites satisfied by concurrent enrollment (COURSE_PREQ_MET_W_ENROLL <> 1 must be true).
-- Requires the enrolled section to exist in SATURN.SSBSECT (join on TERM and CRN); courses without a matching section are excluded.
-- Builds a human-readable course identifier as SUBJECT+COURSE_NUMBER_SECTION_TERM (e.g., ACCT211_01_202440).
-- For each student-term, aggregates all unmet prerequisite situations into one row and orders the list by the underlying status date and course, separated by semicolons.
-- Truncates the prerequisite narrative to 100 characters with an ellipsis when longer; the final aggregated status description is capped to 1000 characters.
-- Sets CATEGORY_CODE to 'PRQ' and marks active prerequisite problems with a red status (color 'red', icon 'cross').
-- Sets FROM_DATE to the earliest SZRPREQ.REFRESH_DATE when the issue was first detected and TO_DATE to the schedule’s TO_DATE for the current window.
-- Loads or updates only rows where the current ETL timestamp falls within the same schedule window (v_etl_date BETWEEN CAS.FROM_DATE AND CAS.TO_DATE).
-- Merges by TERM_CODE, PIDM, and CATEGORY_CODE; on updates, FROM_DATE is preserved while STATUS_COLOR, STATUS_ICON, STATUS_DESC, TO_DATE, and ACTIVITY_DATE are refreshed.
-- After loading, converts prior red issues to a gray status (color 'gray', icon 'clock') when no SZRPREQ row exists for that student and term with a NULL override, indicating the issue has cleared.
-- When converted to gray, replaces the description with 'PRE-REQ resolved; continued monitoring' and extends TO_DATE to 7 days after the ETL date to keep the item visible for follow-up.
-- Only red rows are eligible for conversion to gray; if a new prerequisite problem reappears later, a subsequent MERGE will flip the status back to red.
-- 
-- URL: https://reports.liberty.edu/#/site/Academics/views/AdvisingDashboard/ResidentStudents
--
--DECLARE
v_etl_date    DATE := SYSDATE;
v_msg         VARCHAR2(2000);
v_instance    VARCHAR2(50) := upper('ALL');
v_partition   NUMBER := 0;
v_cpu         NUMBER := 4;
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_aa_casas_advising_audit_prq';
v_loop_count  NUMBER := 0;
v_total_loops NUMBER := 0;
v_retry_count NUMBER := 0;
v_max_retries NUMBER := 3;
v_wait_time   NUMBER := 120; -- seconds
-- Status/UI constants (avoid hard-coded literals in multiple places)
c_status_red_color  CONSTANT VARCHAR2(10) := 'red';
c_status_red_icon   CONSTANT VARCHAR2(16) := 'cross'; -- critical
c_status_gray_color CONSTANT VARCHAR2(10) := 'gray';
c_status_gray_icon  CONSTANT VARCHAR2(16) := 'clock'; -- neutral/settled
c_gray_days         CONSTANT PLS_INTEGER := 7;
c_desc_max_len      CONSTANT PLS_INTEGER := 1000; -- conservative cap for status_desc
-- Map Oracle errors to named exceptions for clarity
e_deadlock EXCEPTION;
PRAGMA EXCEPTION_INIT(e_deadlock, -60); -- ORA-00060
e_busy EXCEPTION;
PRAGMA EXCEPTION_INIT(e_busy, -54); -- ORA-00054
-- Cursor and record types for terms
TYPE r_rec IS RECORD(
term_code      VARCHAR2(6),
next_term_code VARCHAR2(6),
from_date      DATE,
to_date        DATE,
category_code  VARCHAR2(3));
TYPE t_rec IS TABLE OF r_rec INDEX BY PLS_INTEGER;
v_rec t_rec;
BEGIN
-- Calculate total number of loops
SELECT cas.term_code,
       cas.next_term_code,
       cas.from_date,
       cas.to_date,
       cas.category_code
  BULK COLLECT
  INTO v_rec
  FROM utl_d_aa.casas_advising_schedule cas
 WHERE SYSDATE BETWEEN from_date AND to_date
   AND category_code = 'PRQ'
 ORDER BY 1;
v_total_loops := v_rec.count;
-- Generate job ID for logging
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
-- Optional: enable parallel DML for large batches; requires proper table settings
-- EXECUTE IMMEDIATE 'ALTER SESSION ENABLE PARALLEL DML';
-- Main loop over each term
FOR i IN 1 .. v_rec.count
LOOP
v_loop_count := v_loop_count + 1;
v_count      := 0;
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - Loop ' || v_loop_count || ' of ' || v_total_loops || ' - ' || v_rec(i).term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
v_retry_count := 0;
<<retry_loop>>
LOOP
BEGIN
v_count := 0;
-- Single MERGE statement that handles all logic
MERGE INTO utl_d_aa.casas_advising_audit tgt
USING (
WITH cohort_students AS
 (SELECT pidm,
         term_code
    FROM utl_d_aa.casas_advising_cohort
   WHERE term_code = v_rec(i).term_code),
student_status AS
 (SELECT term_code,
         pidm,
         category_code,
         status_color,
         status_icon,
         MIN(status_date) AS status_date,
         -- Deterministic ordering of situations (by date then course)
         listagg(situation, '; ') within GROUP(ORDER BY status_date, course_code) AS situation
    FROM (SELECT cs.term_code,
                 cs.pidm,
                 v_rec(i).category_code AS category_code,
                 prq.status_date,
                 c_status_red_color AS status_color,
                 c_status_red_icon AS status_icon, -- critical
                 'ENROLLED: ' || prq.course_code || ' || PRE-REQ: ' || prq.prerequisites AS situation,
                 v_etl_date AS activity_date,
                 prq.course_code
            FROM cohort_students cs
            JOIN (SELECT preq.pidm,
                        preq.crn,
                        preq.term AS term_code,
                        ssbsect_subj_code || ssbsect_crse_numb || '_' || ssbsect_seq_numb || '_' || ssbsect_term_code AS course_code,
                        CASE
                        WHEN length(preq.prerequisites) > 100 THEN
                         substr(preq.prerequisites, 1, 100) || '...'
                        ELSE
                         preq.prerequisites
                        END AS prerequisites,
                        preq.refresh_date AS status_date -- this is going overwrite every day szrpreq runs
                   FROM utl_d_aim.szrpreq preq
                   JOIN saturn.ssbsect
                     ON ssbsect_term_code = preq.term
                    AND ssbsect_crn = preq.crn
                  WHERE preq.term = v_rec(i).term_code
                    AND preq.sfrsrpo_override IS NULL -- not showing any overrides
                    AND preq.course_preq_met_w_enroll <> 1 -- not showing any pre-req that has concur enrollment (meeting criteria)
                 ) prq
              ON prq.pidm = cs.pidm)
   GROUP BY term_code,
            pidm,
            category_code,
            status_color,
            status_icon)
SELECT student_status.term_code,
       student_status.pidm,
       student_status.category_code,
       student_status.status_color,
       student_status.status_icon,
       -- Truncate aggregated status_desc to avoid overflow into tgt column
       substr(student_status.situation, 1, c_desc_max_len) AS status_desc,
       status_date AS from_date, -- GET THE TIMESTAMP WHEN WE FIRST FOUND IT
       cas.to_date,
       v_etl_date AS activity_date
  FROM student_status
  JOIN utl_d_aa.casas_advising_schedule cas
    ON cas.term_code = student_status.term_code
   AND cas.category_code = student_status.category_code
   AND v_etl_date BETWEEN cas.from_date AND cas.to_date) src ON (tgt.term_code = src.term_code AND tgt.pidm = src.pidm AND tgt.category_code = src.category_code) WHEN MATCHED THEN
UPDATE
   SET tgt.status_color  = src.status_color,
       tgt.status_icon   = src.status_icon,
       tgt.status_desc   = src.status_desc,
       tgt.to_date       = src.to_date, -- DO NOT UPDATE THE FROM DATE
       tgt.activity_date = src.activity_date
WHEN NOT MATCHED THEN
INSERT
(term_code,
 pidm,
 category_code,
 status_color,
 status_icon,
 status_desc,
 from_date,
 to_date,
 activity_date)
VALUES
(src.term_code,
 src.pidm,
 src.category_code,
 src.status_color,
 src.status_icon,
 src.status_desc,
 src.from_date,
 src.to_date,
 src.activity_date);
v_count := SQL%ROWCOUNT;
COMMIT;
dbms_lock.sleep(0.5); -- pause half second
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || v_rec(i).term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count;
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- SECONDARY STEP: Convert rows from RED to GRAY for 7 days after pre-req mismatch
--                is no longer present in SZRPREQ for the same term/pidm.
--                - If a new mismatch emerges, the MERGE above flips back to red.
UPDATE utl_d_aa.casas_advising_audit tgt
   SET tgt.status_color  = c_status_gray_color,
       tgt.status_icon   = c_status_gray_icon,
       tgt.status_desc   = 'PRE-REQ resolved; continued monitoring', -- concise, user-facing
       tgt.to_date       = v_etl_date + c_gray_days, -- UPDATE THE TO_DATE TO CONTINUE MONITORING
       tgt.activity_date = v_etl_date
 WHERE tgt.category_code = v_rec(i).category_code
   AND tgt.term_code = v_rec(i).term_code
   AND tgt.status_color = c_status_red_color -- only convert red -> gray
   AND NOT EXISTS (SELECT 1
          FROM utl_d_aim.szrpreq preq
         WHERE preq.term = tgt.term_code
           AND preq.pidm = tgt.pidm
		   AND preq.course_preq_met_w_enroll <> 1 -- not showing any pre-req that has concur enrollment (meeting criteria)
           AND preq.sfrsrpo_override IS NULL);
v_count := SQL%ROWCOUNT;
COMMIT;
dbms_lock.sleep(0.5); -- pause half second
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'GRAY-WINDOW UPDATE - ' || v_rec(i).term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count;
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
EXIT; -- Success, exit retry loop
EXCEPTION
WHEN e_deadlock THEN
-- Deadlock detected
v_retry_count := v_retry_count + 1;
IF v_retry_count > v_max_retries THEN
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := '!!!-00060: deadlock detected while waiting for resource. ' || 'Max retries exceeded after ' || (v_max_retries * v_wait_time) || ' seconds';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
EXIT; -- Give up after max retries
ELSE
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'Deadlock detected while waiting for resource - waiting ' || v_wait_time || ' seconds for retry attempt number ' || v_retry_count;
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'WARNING', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
dbms_lock.sleep(v_wait_time);
CONTINUE retry_loop; -- Retry
END IF;
WHEN e_busy THEN
-- Resource busy (e.g., NOWAIT elsewhere); treat similar to deadlock retry
v_retry_count := v_retry_count + 1;
IF v_retry_count > v_max_retries THEN
dbms_lock.sleep(0.5);
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := '!!!-00054: resource busy. Max retries exceeded after ' || (v_max_retries * v_wait_time) || ' seconds';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
EXIT;
ELSE
dbms_lock.sleep(0.5);
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'Resource busy - waiting ' || v_wait_time || ' seconds for retry attempt number ' || v_retry_count;
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'WARNING', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
dbms_lock.sleep(v_wait_time);
CONTINUE retry_loop; -- Retry
END IF;
WHEN OTHERS THEN
-- Other errors
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
EXIT; -- Exit on other errors
END;
END LOOP retry_loop;
dbms_output.put_line(' --------- ');
END LOOP; -- v_rec
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
EXCEPTION
WHEN OTHERS THEN
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
END etl_aa_casas_advising_audit_prq;

procedure etl_aa_casas_advising_audit_fns(jobnumber number, processid varchar2, processname varchar2) IS

--
-- PURPOSE: Generates final‑grade intervention records for advising by identifying recent grade activity for cohort students and assigning a color‑coded status for follow‑up.
--
-- TABLE: utl_d_aa.casas_advising_audit
--
-- UNIQUE INDEX: TERM_CODE, PIDM, CATEGORY_CODE
--
-- CONDITIONS:
-- Processes only schedule entries where the current date falls between START_DATE and END_DATE for category FNS.
-- Iterates one term at a time based on matching rows from CASAS_ADVISING_SCHEDULE.
-- Includes only students listed in CASAS_ADVISING_COHORT for the active term.
-- Uses STUFNGRADE_LOG to locate all grade or activity events for each student and CRN within the term.
-- Selects the most recent grade_date or activity_date for each student‑CRN pair.
-- Joins only identity records where SPRIDEN_CHANGE_IND is null, ensuring only the current identity row is used.
-- Joins SSBSECT to attach subject, course number, sequence, and term for descriptive output.
-- Aggregates all course events per student into a semicolon‑separated status description, ordered by most recent grade activity.
-- Determines student status based on recency of their most recent grade activity:
--   Red if the most recent grade_date is within the past 7 days.
--   Yellow if the date is between 8 and 14 days old.
--   Gray if the date is older than 14 days.
-- Assigns status icons that correspond to red (cross), yellow (exclamation), and gray (clock).
-- Truncates the concatenated status description to a maximum of 1000 characters.
-- Sets FROM_DATE equal to the student's most recent grade activity.
-- Sets TO_DATE to 30 days after the FROM_DATE to define the intervention window.
-- Performs an upsert by matching on TERM_CODE, PIDM, and CATEGORY_CODE so that existing records are updated and new ones inserted.
--
-- URL: https://reports.liberty.edu/#/site/Academics/views/AdvisingDashboard/ResidentStudents
--

--DECLARE
-- Parameters and control variables
v_etl_date    DATE := SYSDATE;
v_msg         VARCHAR2(2000);
v_instance    VARCHAR2(50) := upper('ALL');
v_partition   NUMBER := 0;
v_cpu         NUMBER := 4;
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_aa_casas_advising_audit_fns';
v_loop_count  NUMBER := 0;
v_total_loops NUMBER := 0;
v_retry_count NUMBER := 0;
v_max_retries NUMBER := 3;
v_wait_time   NUMBER := 120; -- seconds
-- Status/UI constants (avoid hard-coded literals in multiple places)
c_status_red_color        CONSTANT VARCHAR2(10) := 'red';
c_status_red_icon         CONSTANT VARCHAR2(16) := 'cross'; -- critical
c_status_yellow_color     CONSTANT VARCHAR2(10) := 'yellow';
c_status_yellow_icon      CONSTANT VARCHAR2(16) := 'exclamation'; -- caution
c_status_gray_color       CONSTANT VARCHAR2(10) := 'gray';
c_status_gray_icon        CONSTANT VARCHAR2(16) := 'clock'; -- neutral
c_red_days_threshold      CONSTANT PLS_INTEGER := 7; -- <=7 days => red
c_yellow_days_upper_bound CONSTANT PLS_INTEGER := 14; -- 8-14 days => yellow
c_desc_max_len            CONSTANT PLS_INTEGER := 1000; -- conservative cap
-- Map Oracle errors to named exceptions for clarity
e_deadlock EXCEPTION;
PRAGMA EXCEPTION_INIT(e_deadlock, -60); -- ORA-00060
e_busy EXCEPTION;
PRAGMA EXCEPTION_INIT(e_busy, -54); -- ORA-00054
-- Cursor and record types for terms
TYPE r_rec IS RECORD(
term_code      VARCHAR2(6),
next_term_code VARCHAR2(6),
from_date      DATE,
to_date        DATE,
category_code  VARCHAR2(3));
TYPE t_rec IS TABLE OF r_rec INDEX BY PLS_INTEGER;
v_rec t_rec;
BEGIN
-- Calculate total number of loops
SELECT cas.term_code,
       cas.next_term_code,
       cas.from_date,
       cas.to_date,
       cas.category_code
  BULK COLLECT
  INTO v_rec
  FROM utl_d_aa.casas_advising_schedule cas
 WHERE v_etl_date BETWEEN from_date AND to_date
   AND category_code = 'FNS'
 ORDER BY 1;
v_total_loops := v_rec.count;
-- Generate job ID for logging
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
-- Optional: enable parallel DML for large batches; requires proper table settings
-- EXECUTE IMMEDIATE 'ALTER SESSION ENABLE PARALLEL DML';
-- Main loop over each term
FOR i IN 1 .. v_rec.count
LOOP
v_loop_count := v_loop_count + 1;
v_count      := 0;
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - Loop ' || v_loop_count || ' of ' || v_total_loops || ' - ' || v_rec(i).term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
v_retry_count := 0;
<<retry_loop>>
LOOP
BEGIN
v_count := 0;
-- Single MERGE statement that handles all logic
MERGE INTO utl_d_aa.casas_advising_audit tgt
USING (
WITH cohort_students AS
 (SELECT pidm,
         term_code
    FROM utl_d_aa.casas_advising_cohort
   WHERE term_code = v_rec(i).term_code),
-- Collect latest grade event per (term, crn, pidm)
latest_fnl AS
 (SELECT fnl.term_code,
         fnl.crn,
         fnl.pidm,
         MAX(coalesce(fnl.grade_date, fnl.activity_date)) AS grade_date
    FROM utl_d_aa.stufngrade_log fnl
   WHERE fnl.term_code = v_rec(i).term_code
   GROUP BY fnl.term_code,
            fnl.crn,
            fnl.pidm),
-- Aggregate student-level status across CRNs with deterministic ordering
student_status AS
 (SELECT lf.pidm,
         lf.term_code,
         v_rec(i).category_code AS category_code,
         MAX(lf.grade_date) AS status_date,
         listagg(ssbsect_subj_code || ssbsect_crse_numb || '_' || ssbsect_seq_numb || '_' || ssbsect_term_code || ' (' || to_char(lf.grade_date, 'YYYY-MM-DD') || ')', '; ') within GROUP(ORDER BY lf.grade_date DESC, ssbsect_subj_code, ssbsect_crse_numb, ssbsect_seq_numb) AS situation
    FROM cohort_students cs
    JOIN latest_fnl lf
      ON cs.term_code = lf.term_code
     AND cs.pidm = lf.pidm
    JOIN saturn.spriden
      ON spriden_pidm = lf.pidm
     AND spriden_change_ind IS NULL
    JOIN saturn.ssbsect
      ON ssbsect_term_code = lf.term_code
     AND ssbsect_crn = lf.crn
   WHERE lf.term_code = v_rec(i).term_code
   GROUP BY lf.pidm,
            lf.term_code)
SELECT term_code,
       pidm,
       category_code,
       -- Status determination using CASE statement
       CASE
       WHEN status_date > SYSDATE - c_red_days_threshold THEN
        c_status_red_color
       WHEN status_date BETWEEN SYSDATE - c_yellow_days_upper_bound AND SYSDATE - c_red_days_threshold THEN
        c_status_yellow_color
       ELSE
        c_status_gray_color
       END AS status_color,
       CASE
       WHEN status_date > SYSDATE - c_red_days_threshold THEN
        c_status_red_icon -- critical
       WHEN status_date BETWEEN SYSDATE - c_yellow_days_upper_bound AND SYSDATE - c_red_days_threshold THEN
        c_status_yellow_icon
       ELSE
        c_status_gray_icon
       END AS status_icon,
       substr(situation, 1, c_desc_max_len) AS status_desc, -- Truncate aggregated desc
       status_date AS from_date, -- START INTERVENTIONS - specific to student
       status_date + 30 AS to_date, -- END INTERVENTIONS - specific to student
       v_etl_date AS activity_date
  FROM student_status) src
    ON (tgt.term_code = src.term_code AND tgt.pidm = src.pidm AND tgt.category_code = src.category_code) WHEN MATCHED THEN
UPDATE
   SET tgt.status_color  = src.status_color,
       tgt.status_icon   = src.status_icon,
       tgt.status_desc   = src.status_desc,
       tgt.from_date     = src.from_date, -- keep per-event start bound
       tgt.to_date       = src.to_date, -- keep per-event end bound
       tgt.activity_date = src.activity_date
WHEN NOT MATCHED THEN
INSERT
(term_code,
 pidm,
 category_code,
 status_color,
 status_icon,
 status_desc,
 from_date,
 to_date,
 activity_date)
VALUES
(src.term_code,
 src.pidm,
 src.category_code,
 src.status_color,
 src.status_icon,
 src.status_desc,
 src.from_date,
 src.to_date,
 src.activity_date);
v_count := SQL%ROWCOUNT;
COMMIT;
dbms_lock.sleep(0.5); -- pause half second
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || v_rec(i).term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count;
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
EXIT; -- Success, exit retry loop
EXCEPTION
WHEN e_deadlock THEN
-- Deadlock detected
v_retry_count := v_retry_count + 1;
IF v_retry_count > v_max_retries THEN
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := '!!!-00060: deadlock detected while waiting for resource. ' || 'Max retries exceeded after ' || (v_max_retries * v_wait_time) || ' seconds';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
EXIT; -- Give up after max retries
ELSE
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'Deadlock detected while waiting for resource - waiting ' || v_wait_time || ' seconds for retry attempt number ' || v_retry_count;
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'WARNING', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
dbms_lock.sleep(v_wait_time);
CONTINUE retry_loop; -- Retry
END IF;
WHEN e_busy THEN
-- Resource busy (e.g., NOWAIT elsewhere); treat similar to deadlock retry
v_retry_count := v_retry_count + 1;
IF v_retry_count > v_max_retries THEN
dbms_lock.sleep(0.5);
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := '!!!-00054: resource busy. Max retries exceeded after ' || (v_max_retries * v_wait_time) || ' seconds';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
EXIT;
ELSE
dbms_lock.sleep(0.5);
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'Resource busy - waiting ' || v_wait_time || ' seconds for retry attempt number ' || v_retry_count;
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'WARNING', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
dbms_lock.sleep(v_wait_time);
CONTINUE retry_loop; -- Retry
END IF;
WHEN OTHERS THEN
-- Other errors
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
EXIT; -- Exit on other errors
END;
END LOOP retry_loop;
dbms_output.put_line(' --------- ');
END LOOP; -- v_rec
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
EXCEPTION
WHEN OTHERS THEN
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
END etl_aa_casas_advising_audit_fns;

procedure etl_aa_casas_advising_audit_tsi(jobnumber number, processid varchar2, processname varchar2) IS

--
-- PURPOSE: Produces TSI intervention alerts by identifying recent test scores and transcript receipts for cohort students so advisors can take timely action.
--
-- TABLE: utl_d_aa.casas_advising_audit
--
-- UNIQUE INDEX: TERM_CODE, PIDM, CATEGORY_CODE
--
-- CONDITIONS:
-- Processes only TSI schedule rows where the current date falls between the schedule FROM_DATE and TO_DATE.
-- Runs once per active term_code defined in the CASAS_ADVISING_SCHEDULE table for category TSI.
-- Includes only students listed in CASAS_ADVISING_COHORT for the specific term being processed.
-- Includes only test score records where the testing date occurred within the last 30 days.
-- Includes only tests whose test codes fall within a defined list of approved TSI‑related codes.
-- Includes only transcript receipt records where the received date occurred within the last 30 days.
-- Includes only transcripts whose ADMR codes fall within a defined list of approved incoming transcript types.
-- Aggregates all qualifying test and transcript events for each student into a single record per term_code and PIDM.
-- Selects the earliest (minimum) status_date from all qualifying events for each student.
-- Determines status color based on recency of status_date: red if within 7 days, yellow if 7–14 days, gray if older than 14 days.
-- Determines status icon based on the same recency buckets: cross for red, exclamation for yellow, clock for gray.
-- Creates a status description by concatenating all event descriptions and appending the associated status_date.
-- Assigns the student-specific intervention window by setting FROM_DATE to the status_date and TO_DATE to status_date plus 30 days.
-- Populates or updates CASAS_ADVISING_AUDIT using MERGE keyed by TERM_CODE, PIDM, and CATEGORY_CODE.
--
-- URL: https://reports.liberty.edu/#/site/Academics/views/AdvisingDashboard/ResidentStudents
--

-- DECLARE
-- Timestamps and telemetry
v_etl_date    DATE := SYSDATE;
v_msg         VARCHAR2(2000);
v_instance    VARCHAR2(50) := upper('ALL');
v_partition   NUMBER := 0;
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_aa_casas_advising_audit_tsi'; -- Transcript Status (Incoming)
-- Loop control
v_loop_count  NUMBER := 0;
v_total_loops NUMBER := 0;
-- Retry control
v_retry_count NUMBER := 0;
v_max_retries NUMBER := 3;
v_wait_time   NUMBER := 120; -- seconds
-- Status/UI constants (avoid hard-coded literals in multiple places)
c_status_red_color    CONSTANT VARCHAR2(10) := 'red';
c_status_red_icon     CONSTANT VARCHAR2(16) := 'cross'; -- critical
c_status_yellow_color CONSTANT VARCHAR2(10) := 'yellow';
c_status_yellow_icon  CONSTANT VARCHAR2(16) := 'exclamation'; -- caution
c_status_gray_color   CONSTANT VARCHAR2(10) := 'gray';
c_status_gray_icon    CONSTANT VARCHAR2(16) := 'clock'; -- neutral/settled
c_desc_max_len        CONSTANT PLS_INTEGER := 1000; -- conservative cap for status_desc
-- Map Oracle errors to named exceptions for clarity
e_deadlock EXCEPTION;
PRAGMA EXCEPTION_INIT(e_deadlock, -60); -- ORA-00060
e_busy EXCEPTION;
PRAGMA EXCEPTION_INIT(e_busy, -54); -- ORA-00054
-- Cursor and record types for terms (align structure with CPS example)
TYPE r_rec IS RECORD(
term_code      VARCHAR2(6),
next_term_code VARCHAR2(6),
from_date      DATE,
to_date        DATE,
category_code  VARCHAR2(3));
TYPE t_rec IS TABLE OF r_rec INDEX BY PLS_INTEGER;
v_rec t_rec;
BEGIN
-- Calculate total number of loops
SELECT cas.term_code,
       cas.next_term_code,
       cas.from_date,
       cas.to_date,
       cas.category_code
  BULK COLLECT
  INTO v_rec
  FROM utl_d_aa.casas_advising_schedule cas
 WHERE SYSDATE BETWEEN cas.from_date AND cas.to_date -- active processing window
   AND cas.category_code = 'TSI'
 ORDER BY 1;
v_total_loops := v_rec.count;
-- Generate job ID for logging
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
-- Optional: enable parallel DML for large batches; requires proper table settings
-- EXECUTE IMMEDIATE 'ALTER SESSION ENABLE PARALLEL DML';
-- Main loop over each term
FOR i IN 1 .. v_rec.count
LOOP
v_loop_count := v_loop_count + 1;
v_count      := 0;
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - Loop ' || v_loop_count || ' of ' || v_total_loops || ' - ' || v_rec(i).term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
v_retry_count := 0;
<<retry_loop>>
LOOP
BEGIN
v_count := 0;
-- Single MERGE statement that handles all logic
MERGE INTO utl_d_aa.casas_advising_audit tgt
USING (
WITH cohort_students AS
 (SELECT pidm,
         term_code
    FROM utl_d_aa.casas_advising_cohort
   WHERE term_code = v_rec(i).term_code),
student_status AS
 (SELECT term_code,
         pidm,
         category_code,
         MIN(status_date) AS status_date,
         listagg(situation, '; ') within GROUP(ORDER BY 1) AS situation
    FROM (SELECT cs.term_code,
                 cs.pidm,
                 v_rec(i).category_code AS category_code,
                 status_date,
                 stvtesc_desc || ' - ' || sortest_test_score AS situation,
                 v_etl_date AS activity_date
            FROM cohort_students cs
            JOIN (SELECT DISTINCT stvtesc.stvtesc_desc,
                                 sortest.sortest_test_date  AS status_date,
                                 sortest.sortest_test_score,
                                 sortest.sortest_pidm       AS pidm
                   FROM saturn.sortest sortest
                   JOIN cohort_students
                     ON cohort_students.pidm = sortest.sortest_pidm
                   LEFT JOIN stvtesc
                     ON stvtesc_code = sortest_tesc_code
                  WHERE sortest.sortest_test_date BETWEEN SYSDATE - 30 AND SYSDATE -- ONLY SHOW RECORDS FOR THE LAST 30 DAYS
                    AND sortest.sortest_tesc_code IN
                        ('ASMA', 'ASM2', 'ASEN', 'AP07', 'AP13', 'AP14', 'AP15', 'AP16', 'AP20', 'AP22', 'AP25', 'AP28', 'AP31', 'AP32', 'AP33', 'AP34', 'AP35', 'AP43', 'AP48', 'AP51', 'AP53', 'AP55', 'AP57', 'AP58', 'AP60', 'AP61', 'AP62', 'AP64', 'AP66', 'AP68', 'AP69', 'AP75', 'AP76', 'AP77', 'AP78', 'AP80', 'AP82', 'AP83', 'AP84', 'AP85', 'AP87', 'AP89', 'AP90', 'AP93', 'CP02', 'CP04', 'CP05', 'CP07', 'CP08', 'CP09', 'CP11', 'CP14', 'CP17', 'CP18', 'CP20', 'CP26', 'CP30', 'CP31', 'CP37', 'CP56', 'CP62', 'CP65', 'CP66', 'CP67', 'CP68', 'CP69', 'CP70', 'CP71', 'CP72', 'CP73', 'CP74', 'CP75', 'CP76', 'CP77', 'CP78', 'CP79', 'CP80', 'CP81', 'CP87', 'CP89', 'CP91', 'CP92', 'AP36', 'AP37', 'AP40')) tests
              ON tests.pidm = cs.pidm
          UNION ALL
          SELECT cs.term_code,
                 cs.pidm,
                 v_rec(i).category_code AS category_code,
                 status_date,
                 transcript_type || ' - ' || college AS situation,
                 v_etl_date AS activity_date
            FROM cohort_students cs
            JOIN (SELECT DISTINCT sar.sarchkl_pidm         AS pidm,
                                 sar.sarchkl_receive_date AS status_date,
                                 sar.sarchkl_comment      AS college,
                                 stvadmr.stvadmr_desc     AS transcript_type
                   FROM sarchkl sar
                   JOIN cohort_students
                     ON cohort_students.pidm = sar.sarchkl_pidm
                   LEFT JOIN stvadmr
                     ON stvadmr_code = sar.sarchkl_admr_code
                  WHERE sar.sarchkl_receive_date BETWEEN SYSDATE - 30 AND SYSDATE -- ONLY SHOW RECORDS FOR THE LAST 30 DAYS
                    AND sar.sarchkl_admr_code IN
                        ('AART', 'CCAF', 'CGI', 'CT1', 'CT10', 'CT11', 'CT12', 'CT13', 'CT14', 'CT15', 'CT16', 'CT17', 'CT18', 'CT19', 'CT2', 'CT20', 'CT3', 'CT4', 'CT5', 'CT6', 'CT7', 'CT8', 'CT9', 'CTF1', 'CTF2', 'CTF3', 'CTF4', 'CTF5', 'CTF6', 'CTF7', 'CTF8', 'CTF9', 'CTP1', 'CTP2', 'CTP3', 'CTP4', 'CTP5', 'CTP6', 'CTP7', 'CTP8', 'CTP9', 'CTPR', 'CTU1', 'CTU2', 'CTU3', 'CTU4', 'CTU5', 'CTU6', 'CTU7', 'CTU8', 'CTU9', 'HSF1', 'HST1', 'HST2', 'HST3', 'HST4', 'HST5', 'LWTR')) transcripts
              ON transcripts.pidm = cs.pidm)
   GROUP BY term_code,
            pidm,
            category_code)
SELECT term_code,
       pidm,
       category_code,
       -- Status determination using CASE statement
       CASE
       WHEN status_date > SYSDATE - 7 THEN
        c_status_red_color
       WHEN status_date BETWEEN SYSDATE - 14 AND SYSDATE - 7 THEN
        c_status_yellow_color
       ELSE
        c_status_gray_color
       END AS status_color,
       CASE
       WHEN status_date > SYSDATE - 7 THEN
        c_status_red_icon -- critical
       WHEN status_date BETWEEN SYSDATE - 14 AND SYSDATE - 7 THEN
        c_status_yellow_icon
       ELSE
        c_status_gray_icon -- neutral/settled
       END AS status_icon,
       substr(situation || ' (' || to_char(status_date, 'YYYY-MM-DD') || ')', 1, c_desc_max_len) AS status_desc, -- cap to avoid overflow
       status_date AS from_date, -- START INTERVENTIONS - specific to student, so we are not using the schedule table
       status_date + 30 AS to_date, -- END INTERVENTIONS - specific to student, so we are not using the schedule table
       v_etl_date AS activity_date
  FROM student_status) src
    ON (tgt.term_code = src.term_code AND tgt.pidm = src.pidm AND tgt.category_code = src.category_code) WHEN MATCHED THEN
UPDATE
   SET tgt.status_color  = src.status_color,
       tgt.status_icon   = src.status_icon,
       tgt.status_desc   = src.status_desc,
       tgt.from_date     = src.from_date,
       tgt.to_date       = src.to_date,
       tgt.activity_date = src.activity_date
WHEN NOT MATCHED THEN
INSERT
(term_code,
 pidm,
 category_code,
 status_color,
 status_icon,
 status_desc,
 from_date,
 to_date,
 activity_date)
VALUES
(src.term_code,
 src.pidm,
 src.category_code,
 src.status_color,
 src.status_icon,
 src.status_desc,
 src.from_date,
 src.to_date,
 src.activity_date);
v_count := SQL%ROWCOUNT;
COMMIT;
dbms_lock.sleep(0.5); -- pause half second
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || v_rec(i).term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count;
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
EXIT; -- Success, exit retry loop
EXCEPTION
WHEN e_deadlock THEN
-- Deadlock detected
v_retry_count := v_retry_count + 1;
IF v_retry_count > v_max_retries THEN
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := '!!!-00060: deadlock detected while waiting for resource. Max retries exceeded after ' || (v_max_retries * v_wait_time) || ' seconds';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
EXIT; -- Give up after max retries
ELSE
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'Deadlock detected while waiting for resource - waiting ' || v_wait_time || ' seconds for retry attempt number ' || v_retry_count;
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'WARNING', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
dbms_lock.sleep(v_wait_time);
CONTINUE retry_loop; -- Retry
END IF;
WHEN e_busy THEN
-- Resource busy (e.g., NOWAIT elsewhere); treat similar to deadlock retry
v_retry_count := v_retry_count + 1;
IF v_retry_count > v_max_retries THEN
dbms_lock.sleep(0.5);
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := '!!!-00054: resource busy. Max retries exceeded after ' || (v_max_retries * v_wait_time) || ' seconds';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
EXIT;
ELSE
dbms_lock.sleep(0.5);
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'Resource busy - waiting ' || v_wait_time || ' seconds for retry attempt number ' || v_retry_count;
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'WARNING', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
dbms_lock.sleep(v_wait_time);
CONTINUE retry_loop; -- Retry
END IF;
WHEN OTHERS THEN
-- Other errors
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
EXIT; -- Exit on other errors
END;
END LOOP retry_loop;
dbms_output.put_line(' --------- ');
END LOOP; -- v_rec
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
EXCEPTION
WHEN OTHERS THEN
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
END etl_aa_casas_advising_audit_tsi;


procedure etl_aa_casas_advising_tableau(jobnumber number, processid varchar2, processname varchar2) IS
-- =============================================================================
-- PURPOSE: Conditionally refreshes the CASAS advising Tableau dashboard table only when new advising activity (appointments, calls, tasks) is detected or a new calendar day begins, avoiding unnecessary resource consumption.
--
-- TARGET(S): utl_d_aa.casas_advising_tableau
--
-- UNIQUE KEY / INDEX: term_code, pidm, category_code
--
-- BUSINESS LOGIC & CONDITIONS:
-- - Gate Check 1 (Empty Table): Queries the maximum activity_date from the target table. If NULL (table empty), triggers unconditional full refresh.
-- - Gate Check 2 (New Day): Determines if today's date has already been loaded. If the last refresh was from a previous day, triggers a mandatory refresh regardless of disposition deltas.
-- - Gate Check 3 (Intra-Day Delta): Retrieves the single most recent createdon_est timestamp across all three disposition types (Appointment, Phone Call, Task) for the CASAS business unit in one pass.
-- - Refresh Decision: Sets refresh flag if table is empty, if a new calendar day has begun, OR if any disposition record is more recent than the last tableau activity timestamp. Otherwise, exits gracefully without touching the table.
-- - Term Filtering: Fetches all active term/group combinations from the academic calendar view, excluding winter semesters and limiting to terms within 180 days before/after today, ordered by term code.
-- - Sentinel Row: Inserts a placeholder row (term_code='000000') during refresh to signal "Data refresh in progress" to downstream consumers.
-- - Student Roster: Retrieves all students enrolled in the CASAS advising cohort for each term.
-- - Athletic Status Flagging: Appends "(AT)" to student names for NCAA athletes and "(CA)" for club athletes; all others show standard naming.
-- - Schedule Alignment: Joins to advising schedule to ensure all records fall within the term's active advising window (from_date to to_date).
-- - Intervention Status Determination: Joins to advising audit table to retrieve current status codes (color, icon, description) and applies a conditional status filter mapping (check_mark=Completed, exclamation=Needs Intervention, spot=Prevented Intervention, cross=Critical Intervention, else=Monitoring).
-- - Priority Ranking Calculation: Combines three factors: (1) presence of critical intervention flag (cross icon), (2) term-level priority weight, and (3) machine learning persistence probability, rounded to 6 decimals.
-- - Active Holds Aggregation: Scans active registration holds (where current date is between from_date and to_date) and aggregates only specific hold codes (AV, AW, AP, AS, AD, AC, NA, H1, TR, FT, SA), eliminating exact duplicates via REGEXP_REPLACE pattern matching.
-- - Disposition History (Most Recent): Uses three separate LEFT JOINs with RANK() window function (partitioned by external_pidm, ordered by createdon_est DESC) to isolate the single most recent record for each disposition type (Appointment, Phone Call, Task) within the term period.
-- - Last Intervention Composite: Calculates the maximum timestamp across all three disposition types (appointment_time, call_time, task_time); if all are NULL, defaults to term start_date.
-- - Disposition Display Logic: For each disposition type, formats a human-readable string (e.g., "Phone Call at 2024-01-15 14:30:00") if a record exists, otherwise displays "No [type] since [term start date]".
-- - Retention Model Integration: Joins to machine learning persistence table to retrieve the most recent prediction probability (ranked by dte DESC, with one record per student/term); if unavailable, renders as NULL in the output.
-- - MERGE Strategy: Matches target records on (term_code, pidm, category_code); updates all 26 columns when matched; inserts new records when unmatched.
-- - Deadlock Resilience: If ORA-00060 (deadlock) is detected during MERGE, retries up to 3 times with 120-second wait intervals between attempts; if max retries exceeded, logs the error and continues to the next term without failing the entire procedure.
-- - Non-Deadlock Errors: Logs fatal errors and skips the current term iteration, allowing the procedure to continue processing remaining terms.
-- - Sentinel Cleanup: Removes the placeholder row (term_code='000000') once all term iterations complete successfully.
-- - Job Logging: Generates a unique MD5 hash (job_id) for traceability; logs the refresh reason (TABLE EMPTY, NEW DAY, or INTRA-DAY DELTA with specific timestamp deltas); logs each term's merge completion with row counts and elapsed seconds.
--
-- DEPENDENCIES: 
-- - zbtm.terms_by_group_v (academic term calendar view)
-- - utl_d_aa.casas_advising_cohort (student roster)
-- - utl_d_aa.casas_advising_schedule (advising schedule periods)
-- - utl_d_aa.casas_advising_audit (intervention status records)
-- - saturn.sprhold (student registration holds)
-- - utl_r_ads.rscbcrmactdis (CRM disposition records: appointments, calls, tasks)
-- - utl_d_aa.ml_persistence (machine learning persistence predictions)
-- - ads_etl.insert_job_log (custom logging procedure)
-- - ads_etl.clear_table (custom truncate procedure)
-- - dbms_lock.sleep, standard_hash, RANK(), DECODE, CASE, LISTAGG, REGEXP_REPLACE, TRUNC
--
-- CONSTRAINTS & RISKS:
-- - Deadlock Potential: Heavy reliance on MERGE operations across multiple joins; concurrent execution of this procedure from multiple instances may cause lock contention and ORA-00060 errors.
-- - Disposition JOIN Multiplicity: Although the gate-check uses a single MAX(createdon_est) across all three disposition types, the MERGE unpacks three separate LEFT JOINs; if the CRM disposition table is being actively written to during execution, rankings may become inconsistent mid-query.
-- - External PIDM Matching Risk: Assumes external_pidm from the CRM system (utl_r_ads.rscbcrmactdis) exactly matches pidm in the academic database; mismatches will silently fail to join, resulting in missing disposition records for affected students.
-- - Sentinel Row Visibility: Client queries of casas_advising_tableau must explicitly filter out term_code='000000' to avoid displaying "Please wait..." placeholder rows to end users.
-- - Silent Term Failure: If a single term fails MERGE after exhausting max deadlock retries, the failure is logged but the procedure continues; that term's data may remain stale or incomplete without explicit alerting to operators.
-- - Holds Aggregation Fragility: REGEXP_REPLACE deduplication logic assumes specific hold code formatting; malformed or unexpected hold codes may produce unexpected results.
-- - ML Model Dependency: If utl_d_aa.ml_persistence lacks recent predictions for a student/term combination, persistence_probability renders as NULL; downstream dashboards must handle NULL values gracefully.
-- =============================================================================
-- DECLARE
v_etl_date    DATE := SYSDATE;
v_msg         VARCHAR2(2000);
v_instance    VARCHAR2(50) := upper('ALL');
v_partition   NUMBER := 0;
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_aa_casas_advising_tableau';
v_loop_count  NUMBER := 0;
v_total_loops NUMBER := 0;
v_retry_count NUMBER := 0;
v_max_retries NUMBER := 3;
v_wait_time   NUMBER := 120;
-- ---------------------------------------------------------------------------
-- Gate-check variables
-- ---------------------------------------------------------------------------
v_last_tableau_refresh DATE; -- MAX(activity_date) currently in tableau table
v_last_disp_activity   DATE; -- MAX(createdon_est) across all CASAS dispositions
v_tableau_load_today   NUMBER; -- 1 = already loaded today; 0 = not yet
v_needs_refresh        NUMBER := 0; -- 1 = proceed with full ETL; 0 = skip
-- ---------------------------------------------------------------------------
-- Cursor / collection types
-- ---------------------------------------------------------------------------
TYPE r_rec IS RECORD(
term_code  VARCHAR2(6),
group_code VARCHAR2(3),
start_date DATE);
TYPE t_rec IS TABLE OF r_rec;
v_rec t_rec;
CURSOR c_rec IS
SELECT terms.term_code,
       terms.group_code,
       terms.start_date
  FROM zbtm.terms_by_group_v terms
 WHERE terms.semester NOT IN ('WIN')
   AND terms.group_code IN ('STD')
   AND SYSDATE >= terms.start_date - 180
   AND SYSDATE <= terms.end_date + 180
 ORDER BY 1;
BEGIN
-- -----------------------------------------------------------------------
-- GATE CHECK 1 of 2: Determine the most recent activity_date in the
--                     tableau target table.  A NULL means the table is
--                     empty, which always forces a full refresh.
-- -----------------------------------------------------------------------
SELECT MAX(tgt.activity_date) INTO v_last_tableau_refresh FROM utl_d_aa.casas_advising_tableau tgt WHERE tgt.term_code <> '000000'; -- exclude the in-progress sentinel row
-- -----------------------------------------------------------------------
-- GATE CHECK 2 of 2: Has today already been loaded?
--   0 = today is a new day  → force refresh
--   1 = already loaded today → check disposition delta below
-- -----------------------------------------------------------------------
SELECT CASE
       WHEN v_last_tableau_refresh IS NULL THEN
        0
       WHEN trunc(v_last_tableau_refresh) < trunc(SYSDATE) THEN
        0
       ELSE
        1
       END
  INTO v_tableau_load_today
  FROM dual;
-- -----------------------------------------------------------------------
-- GATE CHECK 3 of 3: Pull the single most recent createdon_est across ALL
--                     three disposition types for CASAS in one pass.
--                     Replaces the three separate LEFT JOINs used solely
--                     for the change-detection decision.
-- -----------------------------------------------------------------------
SELECT MAX(disp.createdon_est)
  INTO v_last_disp_activity
  FROM utl_r_ads.rscbcrmactdis disp
 WHERE disp.business_unit = 'CASAS'
   AND disp.dispo_type IN ('Appointment', 'Phone Call', 'Task');
-- -----------------------------------------------------------------------
-- DECISION: refresh if the table is empty, today is new, or there is a
--           disposition record newer than the last tableau activity stamp.
-- -----------------------------------------------------------------------
IF v_last_tableau_refresh IS NULL THEN
-- Table is empty; unconditional full load
v_needs_refresh := 1;
ELSIF v_tableau_load_today = 0 THEN
-- New calendar day; one mandatory daily refresh regardless of deltas
v_needs_refresh := 1;
ELSIF v_last_disp_activity > v_last_tableau_refresh THEN
-- Intra-day change detected in dispositions; refresh to pick it up
v_needs_refresh := 1;
ELSE
v_needs_refresh := 0;
END IF;
-- -----------------------------------------------------------------------
-- SHORT-CIRCUIT EXIT: nothing new + not a new day → log and bail out
-- -----------------------------------------------------------------------
IF v_needs_refresh = 0 THEN
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
dbms_lock.sleep(0.5);
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'SKIP - No new disposition activity detected and table already loaded today. ' || 'Last tableau refresh: ' || to_char(v_last_tableau_refresh, 'MM/DD/YYYY hh24:mi:ss') || ' | Last disposition activity: ' ||
             nvl(to_char(v_last_disp_activity, 'MM/DD/YYYY hh24:mi:ss'), 'NONE') || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
RETURN; -- graceful early exit; no table touched, no resources wasted
END IF;
-- -----------------------------------------------------------------------
-- FULL ETL PATH: refresh is warranted; proceed with standard pipeline
-- -----------------------------------------------------------------------
OPEN c_rec;
FETCH c_rec BULK COLLECT
INTO v_rec;
v_total_loops := v_rec.count;
CLOSE c_rec;
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
dbms_lock.sleep(0.5);
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' | Refresh reason: ' || CASE
         WHEN v_last_tableau_refresh IS NULL THEN
          'TABLE EMPTY'
         WHEN v_tableau_load_today = 0 THEN
          'NEW DAY - first load for ' || to_char(SYSDATE, 'MM/DD/YYYY')
         WHEN v_last_disp_activity > v_last_tableau_refresh THEN
          'INTRA-DAY DELTA (disp: ' || to_char(v_last_disp_activity, 'MM/DD/YYYY hh24:mi:ss') || ' > tbl: ' || to_char(v_last_tableau_refresh, 'MM/DD/YYYY hh24:mi:ss') || ')'
         END || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
-- Truncate and place in-progress sentinel row
utl_d_aa.truncate_table(v_table_name => 'casas_advising_tableau');
INSERT INTO utl_d_aa.casas_advising_tableau tgt
(term_code,
 pidm,
 luid,
 category_code,
 status_desc,
 full_name)
VALUES
('000000',
 99999,
 'L00000000',
 'X',
 'Data refresh in progress',
 'Please wait...');
COMMIT;
-- -----------------------------------------------------------------------
-- MAIN LOOP over active term/group combinations
-- -----------------------------------------------------------------------
FOR rec IN c_rec
LOOP
v_loop_count  := v_loop_count + 1;
v_count       := 0;
v_retry_count := 0; -- reset deadlock counter per term iteration
dbms_lock.sleep(0.5);
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - Loop ' || v_loop_count || ' of ' || v_total_loops || ' - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- -------------------------------------------------------------------
-- INNER RETRY LOOP: deadlock-safe MERGE with back-off
-- -------------------------------------------------------------------
LOOP
BEGIN
MERGE INTO utl_d_aa.casas_advising_tableau tgt
USING (SELECT CASE
              WHEN cac.ncaa_athlete = 'Y' THEN
               cac.full_name || ' - ' || cac.luid || ' (AT)'
              WHEN cac.club_athlete = 'Y' THEN
               cac.full_name || ' - ' || cac.luid || ' (CA)'
              ELSE
               cac.full_name || ' - ' || cac.luid
              END AS student,
              cac.full_name,
              cac.pidm,
              cac.luid,
              cac.url,
              cas.term_code,
              cas.next_term_code,
              cas.semester_desc,
              cas.category_code,
              cas.category_desc,
              caa.status_color,
              caa.status_icon,
              caa.status_desc,
              CASE
              WHEN caa.status_icon = 'check_mark' THEN
               'Completed'
              WHEN caa.status_icon = 'exclamation' THEN
               'Needs Intervention'
              WHEN caa.status_icon = 'spot' THEN
               'Prevented Intervention'
              WHEN caa.status_icon = 'cross' THEN
               'Critical Intervention'
              ELSE
               'Monitoring'
              END AS status_filtering,
              round(MAX(decode(caa.status_icon, 'cross', 1, 0)) over(PARTITION BY cas.term_code, cac.pidm) + MAX(cas.priority) over(PARTITION BY cas.term_code, cac.pidm) + mp.prediction_probability, 6) AS priority_ranking,
              round(mp.prediction_probability, 6) AS persistence_probability,
              cac.last_initial,
              cac.levl_code,
              cac.coll_desc,
              cac.majr_desc,
              cac.ncaa_athlete,
              cac.club_athlete,
              -- Consolidate all three disposition types into a single subquery
              -- to derive last_intervention, last_appointment, last_call, last_task
              CASE
              WHEN greatest(nvl(appt.appointment_time, rec.start_date), nvl(calls.call_time, rec.start_date), nvl(tasks.task_time, rec.start_date)) > rec.start_date THEN
               greatest(nvl(appt.appointment_time, rec.start_date), nvl(calls.call_time, rec.start_date), nvl(tasks.task_time, rec.start_date))
              ELSE
               rec.start_date
              END AS last_intervention,
              CASE
              WHEN appt.pidm IS NOT NULL THEN
               appt.appointment_type || ' at ' || to_char(appt.appointment_time, 'YYYY-MM-DD HH24:MI:SS')
              ELSE
               'No appointments since ' || to_char(rec.start_date, 'YYYY-MM-DD HH24:MI:SS')
              END AS last_appointment,
              CASE
              WHEN calls.pidm IS NOT NULL THEN
               calls.call_type || ' at ' || to_char(calls.call_time, 'YYYY-MM-DD HH24:MI:SS')
              ELSE
               'No calls since ' || to_char(rec.start_date, 'YYYY-MM-DD HH24:MI:SS')
              END AS last_call,
              CASE
              WHEN tasks.pidm IS NOT NULL THEN
               tasks.task_type || ' at ' || to_char(tasks.task_time, 'YYYY-MM-DD HH24:MI:SS')
              ELSE
               'No tasks since ' || to_char(rec.start_date, 'YYYY-MM-DD HH24:MI:SS')
              END AS last_task,
              nvl(hld.holds, 'none') AS holds,
              v_etl_date AS activity_date
         FROM utl_d_aa.casas_advising_cohort cac
         JOIN utl_d_aa.casas_advising_schedule cas
           ON cas.term_code = cac.term_code
          AND cac.term_code = rec.term_code
          AND v_etl_date BETWEEN cas.from_date AND cas.to_date
         JOIN utl_d_aa.casas_advising_audit caa
           ON caa.term_code = cac.term_code
          AND caa.pidm = cac.pidm
          AND caa.category_code = cas.category_code
          AND v_etl_date BETWEEN caa.from_date AND caa.to_date
       -- Selective active holds
         LEFT JOIN (SELECT sprhold_pidm AS pidm,
                          regexp_replace(listagg(DISTINCT upper(sprhold_hldd_code), ', ') within GROUP(ORDER BY sprhold_hldd_code), '([^-]*)(-\1)+($|-)', '\1\3') AS holds
                     FROM saturn.sprhold
                    WHERE v_etl_date BETWEEN sprhold_from_date AND sprhold_to_date
                      AND sprhold_hldd_code IN ('AV', 'AW', 'AP', 'AS', 'AD', 'AC', 'NA', 'H1', 'TR', 'FT', 'SA')
                    GROUP BY sprhold_pidm) hld
           ON hld.pidm = cac.pidm
       -- Appointments (rank 1 = most recent)
         LEFT JOIN (SELECT disp.external_pidm AS pidm,
                          disp.dispo_desc AS appointment_type,
                          disp.createdon_est AS appointment_time,
                          rank() over(PARTITION BY disp.external_pidm ORDER BY disp.createdon_est DESC, rownum) AS ranking
                     FROM utl_r_ads.rscbcrmactdis disp
                    WHERE disp.business_unit = 'CASAS'
                      AND trunc(disp.createdon_est) >= rec.start_date
                      AND disp.dispo_type = 'Appointment') appt
           ON appt.pidm = cac.pidm
          AND appt.ranking = 1
       -- Phone Calls (rank 1 = most recent)
         LEFT JOIN (SELECT disp.external_pidm AS pidm,
                          disp.dispo_desc AS call_type,
                          disp.createdon_est AS call_time,
                          rank() over(PARTITION BY disp.external_pidm ORDER BY disp.createdon_est DESC, rownum) AS ranking
                     FROM utl_r_ads.rscbcrmactdis disp
                    WHERE disp.business_unit = 'CASAS'
                      AND trunc(disp.createdon_est) >= rec.start_date
                      AND disp.dispo_type = 'Phone Call') calls
           ON calls.pidm = cac.pidm
          AND calls.ranking = 1
       -- Tasks (rank 1 = most recent)
         LEFT JOIN (SELECT disp.external_pidm AS pidm,
                          disp.dispo_desc AS task_type,
                          disp.createdon_est AS task_time,
                          rank() over(PARTITION BY disp.external_pidm ORDER BY disp.createdon_est DESC, rownum) AS ranking
                     FROM utl_r_ads.rscbcrmactdis disp
                    WHERE disp.business_unit = 'CASAS'
                      AND trunc(disp.createdon_est) >= rec.start_date
                      AND disp.dispo_type = 'Task') tasks
           ON tasks.pidm = cac.pidm
          AND tasks.ranking = 1
       -- Retention model predictions (rank 1 = most recent run)
         LEFT JOIN (SELECT mp.term_code,
                          mp.pidm,
                          mp.prediction_probability,
                          rank() over(PARTITION BY mp.term_code, mp.pidm ORDER BY mp.dte DESC) AS ranking
                     FROM utl_d_aa.ml_persistence mp
                    WHERE mp.term_code = rec.term_code
                      AND mp.camp_code = 'R'
                      AND mp.prediction_probability IS NOT NULL) mp
           ON mp.term_code = cac.term_code
          AND mp.pidm = cac.pidm
          AND mp.ranking = 1) src
ON (tgt.term_code = src.term_code AND tgt.pidm = src.pidm AND tgt.category_code = src.category_code)
WHEN MATCHED THEN
UPDATE
   SET tgt.student                 = src.student,
       tgt.full_name               = src.full_name,
       tgt.luid                    = src.luid,
       tgt.url                     = src.url,
       tgt.next_term_code          = src.next_term_code,
       tgt.semester_desc           = src.semester_desc,
       tgt.category_desc           = src.category_desc,
       tgt.status_color            = src.status_color,
       tgt.status_icon             = src.status_icon,
       tgt.status_desc             = src.status_desc,
       tgt.status_filtering        = src.status_filtering,
       tgt.priority_ranking        = src.priority_ranking,
       tgt.persistence_probability = src.persistence_probability,
       tgt.last_initial            = src.last_initial,
       tgt.levl_code               = src.levl_code,
       tgt.coll_desc               = src.coll_desc,
       tgt.majr_desc               = src.majr_desc,
       tgt.ncaa_athlete            = src.ncaa_athlete,
       tgt.club_athlete            = src.club_athlete,
       tgt.last_intervention       = src.last_intervention,
       tgt.last_appointment        = src.last_appointment,
       tgt.last_call               = src.last_call,
       tgt.last_task               = src.last_task,
       tgt.activity_date           = src.activity_date
WHEN NOT MATCHED THEN
INSERT
(student,
 full_name,
 pidm,
 luid,
 url,
 term_code,
 next_term_code,
 semester_desc,
 category_code,
 category_desc,
 status_color,
 status_icon,
 status_desc,
 status_filtering,
 priority_ranking,
 persistence_probability,
 last_initial,
 levl_code,
 coll_desc,
 majr_desc,
 ncaa_athlete,
 club_athlete,
 last_intervention,
 last_appointment,
 last_call,
 last_task,
 holds,
 activity_date)
VALUES
(src.student,
 src.full_name,
 src.pidm,
 src.luid,
 src.url,
 src.term_code,
 src.next_term_code,
 src.semester_desc,
 src.category_code,
 src.category_desc,
 src.status_color,
 src.status_icon,
 src.status_desc,
 src.status_filtering,
 src.priority_ranking,
 src.persistence_probability,
 src.last_initial,
 src.levl_code,
 src.coll_desc,
 src.majr_desc,
 src.ncaa_athlete,
 src.club_athlete,
 src.last_intervention,
 src.last_appointment,
 src.last_call,
 src.last_task,
 src.holds,
 src.activity_date);
v_count := SQL%ROWCOUNT;
COMMIT;
dbms_lock.sleep(0.5);
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count;
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
EXIT; -- Successful MERGE; exit the deadlock-retry loop
EXCEPTION
WHEN OTHERS THEN
IF SQLCODE = -60 THEN
-- ORA-00060: Deadlock detected
v_retry_count := v_retry_count + 1;
dbms_lock.sleep(0.5);
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
IF v_retry_count > v_max_retries THEN
v_msg := '!!!-00060: deadlock detected while waiting for resource. ' || 'Max retries exceeded after ' || to_char(v_max_retries * v_wait_time) || ' seconds';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
EXIT; -- Max retries hit; move on to next term in c_rec
ELSE
v_msg := 'Deadlock detected while waiting for resource - waiting ' || to_char(v_wait_time) || ' seconds for retry attempt ' || to_char(v_retry_count);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'WARNING', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
dbms_lock.sleep(v_wait_time);
CONTINUE; -- Back to top of retry loop
END IF;
ELSE
-- Non-deadlock error; log and abandon this term iteration
dbms_lock.sleep(0.5);
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
EXIT; -- Exit retry loop; continue to next term in c_rec
END IF;
END;
END LOOP; -- end deadlock-retry loop
dbms_output.put_line(' --------- ');
END LOOP; -- end c_rec term loop
-- Remove in-progress sentinel row now that all terms are loaded
DELETE FROM utl_d_aa.casas_advising_tableau tgt WHERE tgt.term_code = '000000';
COMMIT;
dbms_lock.sleep(0.5);
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
EXCEPTION
WHEN OTHERS THEN
dbms_lock.sleep(0.5);
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
END etl_aa_casas_advising_tableau;

procedure etl_aa_casas_advising_audit_fci(jobnumber number, processid varchar2, processname varchar2) IS

--
-- PURPOSE: Generates financial check-in (FCI) audit status for resident cohort students during the active FCI advising window for use on the Advising Dashboard.
--
-- TABLE: utl_d_aa.casas_advising_audit
--
-- UNIQUE INDEX: TERM_CODE, PIDM, CATEGORY_CODE
--
-- CONDITIONS:
-- Processes only academic terms whose semester is not WIN.
-- Includes only terms assigned to the STD group code.
-- Restricts processing to terms within 120 days before and 90 days after the current date.
-- Iterates one term at a time using a cursor-driven loop.
-- Includes only students present in utl_d_aa.casas_advising_cohort for the current term.
-- Determines each student's next registration term using ADS_ETL.GET_NEXT_TERM_CODE.
-- Uses the financial check-in (FCI) advising schedule window only when the current timestamp falls between the schedule's from_date and to_date values for category FCI.
-- Builds the gray, yellow, and red timing windows for FCI status by subtracting 28 days and 14 days from schedule.to_date.
-- Includes only students who are registered for the next term, because financial check‑in is only tracked for students already enrolled.
-- Identifies financial check‑in completion by checking szrenrl.fci_date for the student in the next term.
-- Assigns status colors:
--   - Green when FCI has been completed.
--   - Red when current date is within the red window.
--   - Yellow when current date is within the yellow window.
--   - Gray when current date is within the gray window.
--   - Blue for all other times within the display window.
-- Assigns status icons (check mark, cross, exclamation, or clock) based on the student’s FCI status and timing window.
-- Generates descriptive status text indicating whether the student is financially checked in, late, nearing deadline, or awaiting required action.
-- Merges results into the audit table, inserting new rows or updating existing ones based on TERM_CODE, PIDM, and CATEGORY_CODE.
--
-- URL: https://reports.liberty.edu/#/site/Academics/views/AdvisingDashboard/ResidentStudents
--

--DECLARE
-- Parameters and control variables
v_etl_date    DATE := SYSDATE;
v_msg         VARCHAR2(2000);
v_instance    VARCHAR2(50) := upper('ALL');
v_partition   NUMBER := 0;
v_cpu         NUMBER := 4;
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_aa_casas_advising_audit_fci';
v_loop_count  NUMBER := 0;
v_total_loops NUMBER := 0;
v_retry_count NUMBER := 0;
v_max_retries NUMBER := 3;
v_wait_time   NUMBER := 120; -- seconds
-- Cursor and record types for terms
TYPE r_rec IS RECORD(
term_code  VARCHAR2(6),
group_code VARCHAR2(3),
end_date   DATE);
TYPE t_rec IS TABLE OF r_rec INDEX BY PLS_INTEGER;
v_rec t_rec;
BEGIN
-- Calculate total number of loops
SELECT term_code,
       group_code,
       end_date
  BULK COLLECT
  INTO v_rec
  FROM zbtm.terms_by_group_v
 WHERE semester NOT IN ('WIN')
   AND group_code IN ('STD')
   AND SYSDATE >= start_date - 120
   AND SYSDATE <= end_date + 90
 ORDER BY 1;
v_total_loops := v_rec.count;
-- Generate job ID for logging
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
-- Main loop over each term
FOR i IN 1 .. v_rec.count
LOOP
v_loop_count := v_loop_count + 1;
v_count      := 0;
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - Loop ' || v_loop_count || ' of ' || v_total_loops || ' - ' || v_rec(i).term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
v_retry_count := 0;
<<retry_loop>>
LOOP
BEGIN
v_count := 0;
-- Single MERGE statement that handles all logic
MERGE INTO utl_d_aa.casas_advising_audit tgt
USING (
WITH cohort_students AS
 (SELECT pidm,
         term_code,
         ADS_ETL.GET_NEXT_TERM_CODE(v_rec(i).term_code, 'R') AS next_term_code
    FROM utl_d_aa.casas_advising_cohort
   WHERE term_code = v_rec(i).term_code),
-- Category display window now comes from schedule.start_date .. schedule.end_date
schedule_window AS
 (SELECT from_date AS show_start, -- start window 
         to_date AS show_end, -- end window
         from_date AS gray_start,
         to_date - 28 AS gray_end,
         to_date - 28 AS yellow_start,
         to_date - 14 AS yellow_end,
         to_date - 14 AS red_start,
         to_date AS red_end,
         category_code
    FROM utl_d_aa.casas_advising_schedule
   WHERE term_code = v_rec(i).term_code
     AND v_etl_date BETWEEN from_date AND to_date -- gate by display window
     AND category_code = 'FCI'
     AND rownum = 1),
student_status AS
 (SELECT cs.term_code,
         cs.next_term_code,
         cs.pidm,
         sw.category_code,
         sw.show_start,
         sw.show_end,
         sw.gray_start,
         sw.gray_end,
         sw.yellow_start,
         sw.yellow_end,
         sw.red_start,
         sw.red_end,
         v_etl_date AS activity_date,
         -- Financial check-in 
         CASE
         WHEN EXISTS (SELECT 1
                 FROM utl_d_aim.szrenrl
                WHERE term_code = cs.next_term_code
                  AND pidm = cs.pidm
                  AND szrenrl.fci_date IS NOT NULL) THEN
          1
         ELSE
          0
         END AS is_fci
    FROM cohort_students cs
   CROSS JOIN schedule_window sw
  -- only start showing records when reg for next term happens
   WHERE EXISTS (SELECT 1
            FROM utl_d_aim.szrenrl
           WHERE term_code = cs.next_term_code
             AND pidm = cs.pidm))
SELECT term_code,
       pidm,
       category_code,
       -- Status determination using CASE statement
       CASE
       WHEN is_fci = 1 THEN
        'green'
       WHEN v_etl_date BETWEEN red_start AND red_end THEN
        'red'
       WHEN v_etl_date BETWEEN yellow_start AND yellow_end THEN
        'yellow'
       WHEN v_etl_date BETWEEN gray_start AND gray_end THEN
        'gray'
       ELSE
        'blue'
       END AS status_color,
       CASE
       WHEN is_fci = 1 THEN
        'check_mark'
       WHEN v_etl_date BETWEEN red_start AND red_end THEN
        'cross' -- critical "red cross"
       WHEN v_etl_date BETWEEN yellow_start AND yellow_end THEN
        'exclamation' -- warning sign       
       ELSE
        'clock'
       END AS status_icon,
       CASE
       WHEN is_fci = 1 THEN
        'Registered & financially checked-in for ' || student_status.next_term_code
       WHEN v_etl_date BETWEEN red_start AND red_end THEN
        'Registered/NOT FCI for ' || student_status.next_term_code || ' after critical deadline'
       WHEN v_etl_date BETWEEN yellow_start AND yellow_end THEN
        'Registered/NOT FCI for ' || student_status.next_term_code
       WHEN v_etl_date BETWEEN gray_start AND gray_end THEN
        'Awaiting action for ' || student_status.next_term_code
       END AS status_desc,
       show_start AS from_date,
       show_end AS to_date,
       activity_date
  FROM student_status) src
    ON (tgt.term_code = src.term_code AND tgt.pidm = src.pidm AND tgt.category_code = src.category_code) WHEN MATCHED THEN
UPDATE
   SET tgt.status_color  = src.status_color,
       tgt.status_icon   = src.status_icon,
       tgt.status_desc   = src.status_desc,
       tgt.from_date     = src.from_date,
       tgt.to_date       = src.to_date,
       tgt.activity_date = src.activity_date
WHEN NOT MATCHED THEN
INSERT
(term_code,
 pidm,
 category_code,
 status_color,
 status_icon,
 status_desc,
 from_date,
 to_date,
 activity_date)
VALUES
(src.term_code,
 src.pidm,
 src.category_code,
 src.status_color,
 src.status_icon,
 src.status_desc,
 src.from_date,
 src.to_date,
 src.activity_date);
v_count := SQL%ROWCOUNT;
COMMIT;
dbms_lock.sleep(0.5); -- pause half second
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || v_rec(i).term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count;
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
EXIT; -- Success, exit retry loop
EXCEPTION
WHEN OTHERS THEN
IF SQLCODE = -60 THEN
-- Deadlock detected
v_retry_count := v_retry_count + 1;
IF v_retry_count > v_max_retries THEN
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := '!!!-00060: deadlock detected while waiting for resource. Max retries exceeded after ' || (v_max_retries * v_wait_time) || ' seconds';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
EXIT; -- Give up after max retries
ELSE
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'Deadlock detected while waiting for resource - waiting ' || v_wait_time || ' seconds for retry attempt number ' || v_retry_count;
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'WARNING', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
dbms_lock.sleep(v_wait_time);
CONTINUE retry_loop; -- Retry
END IF;
ELSE
-- Other errors
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
EXIT; -- Exit on other errors
END IF;
END;
END LOOP retry_loop;
dbms_output.put_line(' --------- ');
END LOOP; -- v_rec
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
EXCEPTION
WHEN OTHERS THEN
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
END etl_aa_casas_advising_audit_fci;

procedure etl_aa_casas_advising_audit_reg(jobnumber number, processid varchar2, processname varchar2) IS

--
-- PURPOSE: Produces registration audit status (color, icon, and description) for each resident cohort student during the active REG advising window.
--
-- TABLE: utl_d_aa.casas_advising_audit
--
-- UNIQUE INDEX: TERM_CODE, PIDM, CATEGORY_CODE
--
-- CONDITIONS:
-- Processes only academic terms whose semester is not WIN.
-- Includes only terms assigned to the STD group code.
-- Limits processing to terms within 120 days before and 90 days after the current date.
-- Iterates term by term, processing one term's advising audit data at a time.
-- Includes only cohort students stored in utl_d_aa.casas_advising_cohort for the selected term.
-- Determines each student’s next-term registration target using ADS_ETL.GET_NEXT_TERM_CODE.
-- Uses advising schedule records only where the current timestamp falls between the schedule’s from_date and to_date for the REG category.
-- Derives advisory color windows (gray, yellow, red) using offsets from schedule.to_date for the REG category.
-- Classifies each student as registered if they appear in next-term enrollment (szrenrl) for the next term code.
-- Classifies each student as graduated if they have been awarded a degree between the current term and the next term, applying MDV degree-in-passing rules.
-- Identifies hard administrative holds using sprhold codes BR, AS, AD, and DC when active at the term’s end date.
-- Identifies financial-aid fraud holds using rorhold codes FC, FD, FO, EH, FI, FY, and FF when active at the term’s end date.
-- Applies color logic:
--   - Green when registered or graduated.
--   - Black when any hard or fraud hold is active.
--   - Red when current date falls within the red window.
--   - Yellow when current date falls within the yellow window.
--   - Gray when current date falls within the gray window.
--   - Blue when within the display window but before all defined thresholds.
-- Builds status icons based on registration, graduation, hold status, and color window.
-- Builds status descriptions explaining the student's specific registration or hold situation.
-- Inserts or updates the audit table using a MERGE keyed on term, student, and category.
--
-- URL: https://reports.liberty.edu/#/site/Academics/views/AdvisingDashboard/ResidentStudents

--DECLARE
-- Parameters and control variables
v_etl_date    DATE := SYSDATE;
v_msg         VARCHAR2(2000);
v_instance    VARCHAR2(50) := upper('ALL');
v_partition   NUMBER := 0;
v_cpu         NUMBER := 4;
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_aa_casas_advising_audit_reg';
v_loop_count  NUMBER := 0;
v_total_loops NUMBER := 0;
v_retry_count NUMBER := 0;
v_max_retries NUMBER := 3;
v_wait_time   NUMBER := 120; -- seconds
-- Cursor and record types for terms
TYPE r_rec IS RECORD(
term_code  VARCHAR2(6),
group_code VARCHAR2(3),
end_date   DATE);
TYPE t_rec IS TABLE OF r_rec INDEX BY PLS_INTEGER;
v_rec t_rec;
BEGIN
-- Calculate total number of loops
SELECT term_code,
       group_code,
       end_date
  BULK COLLECT
  INTO v_rec
  FROM zbtm.terms_by_group_v
 WHERE semester NOT IN ('WIN')
   AND group_code IN ('STD')
   AND SYSDATE >= start_date - 120
   AND SYSDATE <= end_date + 90
 ORDER BY 1;
v_total_loops := v_rec.count;
-- Generate job ID for logging
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
-- Main loop over each term
FOR i IN 1 .. v_rec.count
LOOP
v_loop_count := v_loop_count + 1;
v_count      := 0;
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - Loop ' || v_loop_count || ' of ' || v_total_loops || ' - ' || v_rec(i).term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
v_retry_count := 0;
<<retry_loop>>
LOOP
BEGIN
v_count := 0;
-- Single MERGE statement that handles all logic
MERGE INTO utl_d_aa.casas_advising_audit tgt
USING (
WITH cohort_students AS
 (SELECT pidm,
         term_code,
         ADS_ETL.GET_NEXT_TERM_CODE(v_rec(i).term_code, 'R') AS next_term_code
    FROM utl_d_aa.casas_advising_cohort
   WHERE term_code = v_rec(i).term_code),
-- Category display window now comes from schedule.start_date .. schedule.end_date
schedule_window AS
 (SELECT from_date AS show_start, -- start window 
         to_date AS show_end, -- end window
         from_date AS gray_start,
         to_date - 28 AS gray_end,
         to_date - 28 AS yellow_start,
         to_date - 14 AS yellow_end,
         to_date - 14 AS red_start,
         to_date AS red_end,
         category_code
    FROM utl_d_aa.casas_advising_schedule
   WHERE term_code = v_rec(i).term_code
     AND v_etl_date BETWEEN from_date AND to_date -- gate by display window
     AND category_code = 'REG'
     AND rownum = 1),
student_status AS
 (SELECT cs.term_code,
         cs.next_term_code,
         cs.pidm,
         sw.category_code,
         sw.show_start,
         sw.show_end,
         sw.gray_start,
         sw.gray_end,
         sw.yellow_start,
         sw.yellow_end,
         sw.red_start,
         sw.red_end,
         v_etl_date AS activity_date,
         -- Registration check (registered for NEXT term)
         CASE
         WHEN EXISTS (SELECT 1
                 FROM utl_d_aim.szrenrl r
                WHERE r.term_code = cs.next_term_code
                  AND r.pidm = cs.pidm) THEN
          1
         ELSE
          0
         END AS is_registered,
         -- Graduation check (awarded degree between current term and next term)
         CASE
         WHEN EXISTS (SELECT 1
                 FROM utl_d_aim.szrenrl sr
                 JOIN saturn.stvdegc std
                   ON sr.degc_code_1 = std.stvdegc_code
                 JOIN (SELECT shrdgmr_pidm,
                             shrdgmr_term_code_grad,
                             shrdgmr_levl_code,
                             shrdgmr_degc_code,
                             stvdegc_acat_code
                        FROM saturn.shrdgmr
                        JOIN saturn.stvdegc
                          ON shrdgmr_degc_code = stvdegc_code
                       WHERE shrdgmr_term_code_grad >= cs.term_code
                         AND shrdgmr_degs_code = 'AW') grads
                   ON grads.shrdgmr_pidm = sr.pidm
                WHERE sr.pidm = cs.pidm
                  AND ((grads.stvdegc_acat_code >= std.stvdegc_acat_code AND grads.shrdgmr_degc_code <> 'MDV') OR (grads.shrdgmr_degc_code = 'MDV' AND grads.shrdgmr_degc_code = sr.degc_code_1))
                  AND grads.shrdgmr_term_code_grad <= cs.next_term_code) THEN
          1
         ELSE
          0
         END AS is_graduated,
         -- Hard holds (preventing future enrollment) evaluated at current term end date
         CASE
         WHEN EXISTS (SELECT 1
                 FROM saturn.sprhold h
                WHERE h.sprhold_pidm = cs.pidm
                  AND h.sprhold_hldd_code IN ('BR', 'AS', 'AD', 'DC')
                  AND v_rec(i).end_date BETWEEN h.sprhold_from_date AND h.sprhold_to_date) THEN
          1
         ELSE
          0
         END AS is_hard_holds,
         -- Fraud holds (financial aid) evaluated at current term end date
         CASE
         WHEN EXISTS (SELECT 1
                 FROM rorhold fin_fraud
                WHERE fin_fraud.rorhold_pidm = cs.pidm
                  AND fin_fraud.rorhold_hold_code IN ('FC', 'FD', 'FO', 'EH', 'FI', 'FY', 'FF')
                  AND v_rec(i).end_date BETWEEN fin_fraud.rorhold_from_date AND fin_fraud.rorhold_to_date) THEN
          1
         ELSE
          0
         END AS is_fraud_holds
    FROM cohort_students cs
   CROSS JOIN schedule_window sw)
SELECT term_code,
       pidm,
       category_code,
       -- Status determination using CASE statement
       CASE
       WHEN is_registered = 1 THEN
        'green'
       WHEN is_graduated = 1 THEN
        'green'
       WHEN is_hard_holds = 1 THEN
        'black'
       WHEN is_fraud_holds = 1 THEN
        'black'
       WHEN v_etl_date BETWEEN red_start AND red_end THEN
        'red'
       WHEN v_etl_date BETWEEN yellow_start AND yellow_end THEN
        'yellow'
       WHEN v_etl_date BETWEEN gray_start AND gray_end THEN
        'gray'
       ELSE
        'blue'
       END AS status_color,
       CASE
       WHEN is_registered = 1 THEN
        'check_mark'
       WHEN is_graduated = 1 THEN
        'check_mark'
       WHEN is_hard_holds = 1 THEN
        'spot' -- black spot (Pirates of the Caribbean)
       WHEN is_fraud_holds = 1 THEN
        'spot' -- black spot (Pirates of the Caribbean)        
       WHEN v_etl_date BETWEEN red_start AND red_end THEN
        'cross' -- critical "red cross"
       WHEN v_etl_date BETWEEN yellow_start AND yellow_end THEN
        'exclamation' -- warning sign
       ELSE
        'clock'
       END AS status_icon,
       CASE
       WHEN is_registered = 1 THEN
        'Registered for ' || student_status.next_term_code
       WHEN is_graduated = 1 THEN
        'Graduated after ' || student_status.term_code
       WHEN is_hard_holds = 1 THEN
        'Hard hold is preventing registration for ' || student_status.term_code
       WHEN is_fraud_holds = 1 THEN
        'Fraud hold is preventing registration for ' || student_status.term_code
       WHEN v_etl_date BETWEEN red_start AND red_end THEN
        'NOT registered for ' || student_status.next_term_code || ' after critical deadline'
       WHEN v_etl_date BETWEEN yellow_start AND yellow_end THEN
        'NOT registered for ' || student_status.next_term_code || ' semester begins soon'
       WHEN v_etl_date BETWEEN gray_start AND gray_end THEN
        'Registration window approaching for ' || student_status.next_term_code
       END AS status_desc,
       show_start AS from_date,
       show_end AS to_date,
       activity_date
  FROM student_status) src
    ON (tgt.term_code = src.term_code AND tgt.pidm = src.pidm AND tgt.category_code = src.category_code) WHEN MATCHED THEN
UPDATE
   SET tgt.status_color  = src.status_color,
       tgt.status_icon   = src.status_icon,
       tgt.status_desc   = src.status_desc,
       tgt.from_date     = src.from_date,
       tgt.to_date       = src.to_date,
       tgt.activity_date = src.activity_date
WHEN NOT MATCHED THEN
INSERT
(term_code,
 pidm,
 category_code,
 status_color,
 status_icon,
 status_desc,
 from_date,
 to_date,
 activity_date)
VALUES
(src.term_code,
 src.pidm,
 src.category_code,
 src.status_color,
 src.status_icon,
 src.status_desc,
 src.from_date,
 src.to_date,
 src.activity_date);
v_count := SQL%ROWCOUNT;
COMMIT;
dbms_lock.sleep(0.5); -- pause half second
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || v_rec(i).term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count;
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
EXIT; -- Success, exit retry loop
EXCEPTION
WHEN OTHERS THEN
IF SQLCODE = -60 THEN
-- Deadlock detected
v_retry_count := v_retry_count + 1;
IF v_retry_count > v_max_retries THEN
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := '!!!-00060: deadlock detected while waiting for resource. Max retries exceeded after ' || (v_max_retries * v_wait_time) || ' seconds';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
EXIT; -- Give up after max retries
ELSE
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'Deadlock detected while waiting for resource - waiting ' || v_wait_time || ' seconds for retry attempt number ' || v_retry_count;
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'WARNING', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
dbms_lock.sleep(v_wait_time);
CONTINUE retry_loop; -- Retry
END IF;
ELSE
-- Other errors
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
EXIT; -- Exit on other errors
END IF;
END;
END LOOP retry_loop;
dbms_output.put_line(' --------- ');
END LOOP; -- v_rec
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
EXCEPTION
WHEN OTHERS THEN
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
END etl_aa_casas_advising_audit_reg;

procedure etl_aa_casas_advising_cohort(jobnumber number, processid varchar2, processname varchar2) is
--
-- PURPOSE: Builds the resident-student advising cohort for each academic term to support category-level interventions in the Advising Dashboard.
--
-- TABLE: utl_d_aa.casas_advising_cohort
--
-- UNIQUE INDEX: TERM_CODE, PIDM
--
-- CONDITIONS:
-- Processes only academic terms whose semester is not WIN.
-- Includes only terms assigned to the STD group code.
-- Processes terms whose dates fall within 180 days before or after the current date.
-- Iterates term by term using a cursor, processing one cohort population per term.
-- For each term, identifies the corresponding next registration term using ADS_ETL.GET_NEXT_TERM_CODE.
-- Selects only resident students based on cohort-level program data (camp_code = 'R').
-- Excludes all law students (levl_code = 'JD') from both current enrollment and future program data.
-- Excludes deceased students based on active szriden records containing a death indicator.
-- Includes only students whose identity record (szriden) is active at the ETL timestamp.
-- Retrieves future-program attributes (camp_code, levl_code, college, major) from zsavlcur when the student has a valid program spanning the next term.
-- Applies cohort-level defaults (campus, level, college, major) when no future-term program exists.
-- Includes NCAA and club sports participation when the student has an engage record in the cohort term or next term.
-- Recomputes values such as full name, last initial, and student identifiers for every run.
-- Uses MERGE to insert or update only when differences exist between source and existing records.
-- Deletes any students who are no longer enrolled in the cohort term.
-- Removes students whose future-term program indicates either online campus (camp_code = 'D') or law enrollment (levl_code = 'JD').
-- Removes any student marked deceased in active szriden records.
--
-- URL: https://reports.liberty.edu/#/site/Academics/views/AdvisingDashboard/ResidentStudents
--
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
v_proc        VARCHAR2(100) := 'etl_aa_casas_advising_cohort';
v_loop_count  NUMBER := 0; -- Variable to track the current loop iteration
v_total_loops NUMBER := 0; -- Variable to track the total number of loops
v_retry_count NUMBER := 0;
v_max_retries NUMBER := 3; -- number of retries for WAIT
v_wait_time   NUMBER := 120; -- seconds for WAIT
TYPE r_rec IS RECORD(
term_code  VARCHAR2(6),
group_code VARCHAR2(3),
next_term  VARCHAR2(6));
TYPE t_rec IS TABLE OF r_rec;
v_rec t_rec;
CURSOR c_rec IS
SELECT terms.term_code,
       terms.group_code,
       ADS_ETL.GET_NEXT_TERM_CODE(terms.term_code, 'R') AS next_term
  FROM zbtm.terms_by_group_v terms
 WHERE 1 = 1
   AND terms.semester NOT IN ('WIN')
   AND terms.group_code IN ('STD')
   AND SYSDATE >= terms.start_date - 180
   AND SYSDATE <= terms.end_date + 180
 ORDER BY 1;
BEGIN
-- dbms_output.enable(buffer_size => NULL);
--
-- Calculate total number of loops
OPEN c_rec;
FETCH c_rec BULK COLLECT
INTO v_rec;
v_total_loops := v_rec.count;
CLOSE c_rec;
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
FOR rec IN c_rec
LOOP
v_loop_count := v_loop_count + 1; -- Increment loop count
v_count      := 0; -- reset count
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - Loop ' || v_loop_count || ' of ' || v_total_loops || ' - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- Retry mechanism for handling deadlocks
LOOP
BEGIN
v_count := 0; --reset count
MERGE INTO utl_d_aa.casas_advising_cohort tgt
USING (SELECT src.term_code,
              src.pidm,
              src.luid,
              src.full_name,
              src.last_initial,
              src.camp_code,
              src.levl_code,
              src.coll_desc,
              src.majr_desc,
              src.ncaa_athlete,
              src.club_athlete,
              src.url,
              src.activity_date
         FROM (SELECT enrl.term_code,
                      enrl.pidm,
                      szriden_id AS luid,
                      TRIM(initcap(szriden_last_name) || ', ' || initcap(szriden_first_name)) AS full_name,
                      upper(substr(TRIM(szriden_last_name), 1, 1)) AS last_initial,
                      nvl(lcur.camp_code, enrl.camp_code) AS camp_code, -- if no future term, get cohort
                      nvl(lcur.levl_code, enrl.levl_code) AS levl_code, -- if no future term, get cohort
                      nvl(stvcoll_desc, enrl.coll_desc_1) AS coll_desc, -- if no future term, get cohort
                      nvl(stvmajr_desc, enrl.majr_desc_1) AS majr_desc, -- if no future term, get cohort
                      nvl(ath.ncaa_athlete, 'N') AS ncaa_athlete,
                      nvl(ath.club_athlete, 'N') AS club_athlete,
                      '' AS url, -- to be added later
                      v_etl_date AS activity_date
                 FROM utl_d_aim.szrenrl enrl
                 JOIN utl_d_aim.szriden
                   ON szriden_pidm = enrl.pidm
                  AND v_etl_date BETWEEN szriden_from_date AND szriden_to_date
                  AND enrl.term_code = rec.term_code
                  AND enrl.camp_code = 'R' -- only resident student; based on program of study (not course)
                  AND enrl.levl_code <> 'JD' -- removing law from population
                  AND szriden_dead_ind IS NULL -- remove from population completely if deceased
                 JOIN zexec.zsavlcur lcur
                   ON lcur.pidm = enrl.pidm
                  AND rec.next_term BETWEEN lcur.from_term AND lcur.end_term -- get FUTURE program data                      
                  AND lcur.levl_code <> 'JD' -- removing law from population
                  AND lcur.camp_code <> 'D' -- removing students that have switched to online
                 LEFT JOIN stvcoll
                   ON stvcoll_code = lcur.prog_coll_1
                   LEFT JOIN stvmajr
           ON stvmajr_code = lcur.majr_code_1
                 LEFT JOIN (SELECT -- bc there can be multiple sports 
                            ath.engage_pidm AS pidm,
                            MAX(CASE
                                WHEN ath.engage_type = 'NCAA Athlete' THEN
                                 'Y'
                                ELSE
                                 'N'
                                END) AS ncaa_athlete,
                            MAX(CASE
                                WHEN ath.engage_type = 'Club Sports' THEN
                                 'Y'
                                ELSE
                                 'N'
                                END) AS club_athlete
                             FROM utl_d_or.cohort_membership ath
                            WHERE ath.engage_term IN (rec.term_code, rec.next_term) -- get cohort AND next term
                              AND ath.engage_type IN ('Club Sports', 'NCAA Athlete')
                            GROUP BY ath.engage_pidm) ath
                   ON ath.pidm = enrl.pidm) src
       -- check for diffs  
         LEFT JOIN utl_d_aa.casas_advising_cohort tgt
           ON tgt.term_code = src.term_code
          AND tgt.pidm = src.pidm
        WHERE (tgt.pidm IS NULL --
              OR nvl(tgt.last_initial, 'X') <> nvl(src.last_initial, 'X') --
              OR nvl(tgt.camp_code, 'X') <> nvl(src.camp_code, 'X') --
              OR nvl(tgt.levl_code, 'X') <> nvl(src.levl_code, 'X') --
              OR nvl(tgt.coll_desc, 'X') <> nvl(src.coll_desc, 'X') --
              OR nvl(tgt.majr_desc, 'X') <> nvl(src.majr_desc, 'X') --
              OR nvl(tgt.ncaa_athlete, 'X') <> nvl(src.ncaa_athlete, 'X') --
              OR nvl(tgt.club_athlete, 'X') <> nvl(src.club_athlete, 'X') --
              OR nvl(tgt.full_name, 'X') <> nvl(src.full_name, 'X') --
              OR nvl(tgt.luid, 'X') <> nvl(src.luid, 'X') --
              OR nvl(tgt.url, 'X') <> nvl(src.url, 'X'))) src
ON (tgt.term_code = src.term_code AND tgt.pidm = src.pidm)
WHEN MATCHED THEN
UPDATE
   SET tgt.luid          = src.luid,
       tgt.full_name     = src.full_name,
       tgt.last_initial  = src.last_initial,
       tgt.camp_code     = src.camp_code,
       tgt.levl_code     = src.levl_code,
       tgt.coll_desc     = src.coll_desc,
       tgt.majr_desc     = src.majr_desc,
       tgt.ncaa_athlete  = src.ncaa_athlete,
       tgt.club_athlete  = src.club_athlete,
       tgt.url           = src.url,
       tgt.activity_date = src.activity_date
WHEN NOT MATCHED THEN
INSERT
(term_code,
 pidm,
 luid,
 full_name,
 last_initial,
 camp_code,
 levl_code,
 coll_desc,
 majr_desc,
 ncaa_athlete,
 club_athlete,
 url,
 activity_date)
VALUES
(src.term_code,
 src.pidm,
 src.luid,
 src.full_name,
 src.last_initial,
 src.camp_code,
 src.levl_code,
 src.coll_desc,
 src.majr_desc,
 src.ncaa_athlete,
 src.club_athlete,
 src.url,
 src.activity_date);
v_count := SQL%ROWCOUNT;
COMMIT;
dbms_lock.sleep(0.5); -- pause half second
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- remove any students NOT enrolled in cohort anymore
DELETE FROM utl_d_aa.casas_advising_cohort tgt
 WHERE tgt.term_code = rec.term_code
   AND NOT EXISTS (SELECT 1
          FROM utl_d_aim.szrenrl src
         WHERE src.term_code = tgt.term_code
           AND src.pidm = tgt.pidm);
v_count := SQL%ROWCOUNT;
COMMIT;
-- remove any students that switched to online OR is JD in the upcoming term  
DELETE FROM utl_d_aa.casas_advising_cohort tgt
 WHERE tgt.term_code = rec.term_code
   AND EXISTS (SELECT 1
          FROM zexec.zsavlcur lcur
         WHERE lcur.pidm = tgt.pidm
           AND rec.next_term BETWEEN lcur.from_term AND lcur.end_term
           AND (lcur.levl_code = 'JD' -- removing law from population
               OR lcur.camp_code = 'D') -- removing students that have switched to online
        );
v_count := v_count + SQL%ROWCOUNT;
COMMIT;
-- remove any students that have deceased
DELETE FROM utl_d_aa.casas_advising_cohort tgt
 WHERE tgt.term_code = rec.term_code
   AND EXISTS (SELECT 1
          FROM utl_d_aim.szriden
         WHERE szriden_pidm = tgt.pidm
           AND v_etl_date BETWEEN szriden_from_date AND szriden_to_date
           AND szriden_dead_ind IS NOT NULL);
v_count := v_count + SQL%ROWCOUNT;
COMMIT;
dbms_lock.sleep(0.5); -- pause half second
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'DELETE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
EXIT; -- If successful, exit the retry loop
EXCEPTION
WHEN OTHERS THEN
IF SQLCODE = -60 THEN
-- Deadlock detected
v_retry_count := v_retry_count + 1;
IF v_retry_count > v_max_retries THEN
-- Log error for max retries
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := '!!!-00060: deadlock detected while waiting for resource. Max retries exceeded after ' || (v_max_retries * v_wait_time) || ' seconds';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
EXIT; -- Add EXIT here to break out of the loop when max retries exceeded
ELSE
-- Log retry attempt
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'Deadlock detected while waiting for resource - waiting ' || v_wait_time || ' seconds for retry attempt number ' || v_retry_count;
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'WARNING', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
dbms_lock.sleep(v_wait_time); -- Wait between retries; short wait because it will need to cycle through all the GTTs again
CONTINUE; -- Add CONTINUE to explicitly indicate loop continuation
END IF;
ELSE
-- Other errors
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
EXIT; -- Add EXIT here to break out of the loop for non-deadlock errors
END IF;
END;
END LOOP; -- end deadlock detection
dbms_output.put_line(' --------- ');
END LOOP; -- c_rec
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
-- log any errors
EXCEPTION
WHEN OTHERS THEN
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
END etl_aa_casas_advising_cohort;

procedure etl_aa_casas_advising_schedule(jobnumber number, processid varchar2, processname varchar2) is

--
-- PURPOSE: Defines when each advising dashboard category should appear for a given academic term to support resident-student interventions in the Advising Dashboard.
--
-- TABLE: utl_d_aa.casas_advising_schedule
--
-- UNIQUE INDEX: TERM_CODE, CATEGORY_CODE
--
-- CONDITIONS:
-- Processes only academic terms whose semester is not WIN.
-- Includes only terms assigned to the STD group code.
-- Processes only terms whose start and end dates fall within 180 days before or after the current date.
-- Iterates through each eligible term individually using a cursor, evaluating one term at a time.
-- For each term, derives the next registration term using ADS_ETL.GET_NEXT_TERM_CODE when building REG and FCI records.
-- For Registration records, includes only Fall and Spring semester terms.
-- Registration and Financial Check-in records begin showing 21 days before the current term's end date.
-- Registration and Financial Check-in records stop showing 7 & 14 days after the next term's start date.
-- FN Grades records show beginning seven days after the term's start date and stop at the end of the current term.
-- Course Program of Study, Pre-Req Not Met, and Lab/Lecture Mismatch records begin showing 90 days before the term begins and stop 30 days before the term ends.
-- Transcript Status records begin showing 90 days before the term begins and stop at the end of the term.
-- Joins to stvterm ensure that each advising category inherits the official term description for the associated term.
-- MERGE logic ensures that each term/category combination is updated if already present or inserted if missing.
--
-- URL: https://reports.liberty.edu/#/site/Academics/views/AdvisingDashboard/ResidentStudents
--

--DECLARE
-- Parameters and control variables
v_etl_date    DATE := SYSDATE;
v_msg         VARCHAR2(2000);
v_instance    VARCHAR2(50) := upper('ALL'); -- Instance from job control
v_partition   NUMBER := 0; -- Parallelization control
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_aa_casas_advising_schedule';
v_loop_count  NUMBER := 0;
v_total_loops NUMBER := 0;
v_retry_count NUMBER := 0;
v_max_retries NUMBER := 3;
v_wait_time   NUMBER := 120; -- seconds
-- Cursor and record types
TYPE r_rec IS RECORD(
term_code  VARCHAR2(6),
group_code VARCHAR2(3),
active     NUMBER);
TYPE t_rec IS TABLE OF r_rec;
v_rec t_rec;
CURSOR c_rec IS
SELECT terms.term_code,
       terms.group_code,
       CASE
       WHEN SYSDATE <= terms.end_date + 7 THEN
        1
       ELSE
        0
       END AS active
  FROM zbtm.terms_by_group_v terms
 WHERE terms.semester NOT IN ('WIN')
   AND terms.group_code IN ('STD')
   AND SYSDATE >= terms.start_date - 180
   AND SYSDATE <= terms.end_date + 180
 ORDER BY 1;
BEGIN
-- dbms_output.enable(buffer_size => NULL);
--
-- Calculate total number of loops
OPEN c_rec;
FETCH c_rec BULK COLLECT
INTO v_rec;
v_total_loops := v_rec.count;
CLOSE c_rec;
-- Generate job ID for logging
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
-- Main loop over each term
FOR rec IN c_rec
LOOP
v_loop_count := v_loop_count + 1;
v_count      := 0;
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - Loop ' || v_loop_count || ' of ' || v_total_loops || ' - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
v_retry_count := 0; -- Reset retry count for each term
-- Retry mechanism for deadlocks
LOOP
BEGIN
v_count := 0;
-- MERGE statement to upsert REG and FCI plus other categories for the term
MERGE INTO utl_d_aa.casas_advising_schedule tgt
USING (
       /* ========================== CATEGORY WINDOWS ==========================
                                         NOTE: This schedule ONLY determines WHEN a category can appear on the
                                               dashboard for a cohort term. Per-student intervention windows
                                               (previously from_date/to_date) are no longer part of this table.
                                         ===================================================================== */
       -- Registration
       SELECT t.term_code,
               ADS_ETL.GET_NEXT_TERM_CODE(t.term_code, 'R') AS next_term_code,
               t.end_date - 21 AS from_date, -- START SHOWING RECORDS FOR TERM (cohort term)
               trunc(t2.start_date + 7) - (1 / (24 * 60 * 60)) AS to_date, -- STOP SHOWING (format as 11:59:59pm)
               t.semester AS semester,
               stvterm_desc AS semester_desc,
               'REG' AS category_code,
               'Registration' AS category_desc,
               0.99 AS priority,
               SYSDATE AS activity_date
         FROM zbtm.terms_by_group_v t
         JOIN zbtm.terms_by_group_v t2
           ON t2.term_code = ADS_ETL.GET_NEXT_TERM_CODE(t.term_code, 'R') -- GET NEXT TERM
          AND t2.group_code = 'STD'
         JOIN stvterm
           ON stvterm_code = t2.term_code
        WHERE t.term_code = rec.term_code
          AND t.group_code = 'STD'
          AND t.semester IN ('FAL', 'SPR') -- only spring and summer (NOTE: filter is actually Fall/Spring)
       UNION ALL
       -- Financial Check-in
       SELECT t.term_code,
               ADS_ETL.GET_NEXT_TERM_CODE(t.term_code, 'R') AS next_term_code,
               t.end_date - 21 AS from_date, -- START SHOWING RECORDS FOR TERM (cohort term)
               trunc(t2.start_date + 14) - (1 / (24 * 60 * 60)) AS to_date, -- STOP SHOWING (format as 11:59:59pm)
               t.semester AS semester,
               stvterm_desc AS semester_desc,
               'FCI' AS category_code,
               'Financial Check-in' AS category_desc,
               0.98 AS priority,
               SYSDATE AS activity_date
         FROM zbtm.terms_by_group_v t
         JOIN zbtm.terms_by_group_v t2
           ON t2.term_code = ADS_ETL.GET_NEXT_TERM_CODE(t.term_code, 'R') -- GET NEXT TERM
          AND t2.group_code = 'STD'
         JOIN stvterm
           ON stvterm_code = t2.term_code
        WHERE t.term_code = rec.term_code
          AND t.group_code = 'STD'
          AND t.semester IN ('FAL', 'SPR') -- only spring and summer (NOTE: filter is actually Fall/Spring)
       UNION ALL
       -- FN Grades
       SELECT t.term_code,
               NULL AS next_term_code, -- NOT IMPORTANT FOR THIS TASK
               t.start_date + 7 AS from_date, -- START SHOWING RECORDS
               trunc(t.end_date) - (1 / (24 * 60 * 60)) AS to_date, -- STOP SHOWING (format as 11:59:59pm)
               t.semester AS semester,
               stvterm_desc AS semester_desc,
               'FNS' AS category_code,
               'FN Grades' AS category_desc,
               0.49 AS priority,
               SYSDATE AS activity_date
         FROM zbtm.terms_by_group_v t
         JOIN stvterm
           ON stvterm_code = t.term_code
        WHERE t.term_code = rec.term_code
          AND t.group_code = 'STD'
          AND t.semester IN ('FAL', 'SPR', 'SUM') -- all terms
       UNION ALL
       -- Course Program of Study
       SELECT t.term_code,
               NULL AS next_term_code, -- NOT IMPORTANT FOR THIS TASK
               t.start_date - 90 AS from_date, -- START SHOWING RECORDS
               trunc(t.end_date - 30) - (1 / (24 * 60 * 60)) AS to_date, -- STOP SHOWING (format as 11:59:59pm)
               t.semester AS semester,
               stvterm_desc AS semester_desc,
               'CPS' AS category_code,
               'Course Program of Study' AS category_desc,
               0.48 AS priority,
               SYSDATE AS activity_date
         FROM zbtm.terms_by_group_v t
         JOIN stvterm
           ON stvterm_code = t.term_code
        WHERE t.term_code = rec.term_code
          AND t.group_code = 'STD'
          AND t.semester IN ('FAL', 'SPR', 'SUM') -- all terms
       UNION ALL
       -- Pre-Req Not Met
       SELECT t.term_code,
               NULL AS next_term_code, -- NOT IMPORTANT FOR THIS TASK
               t.start_date - 90 AS from_date, -- START SHOWING RECORDS
               trunc(t.end_date - 30) - (1 / (24 * 60 * 60)) AS to_date, -- STOP SHOWING (format as 11:59:59pm)
               t.semester AS semester,
               stvterm_desc AS semester_desc,
               'PRQ' AS category_code,
               'Pre-Req Not Met' AS category_desc,
               0.47 AS priority,
               SYSDATE AS activity_date
         FROM zbtm.terms_by_group_v t
         JOIN stvterm
           ON stvterm_code = t.term_code
        WHERE t.term_code = rec.term_code
          AND t.group_code = 'STD'
          AND t.semester IN ('FAL', 'SPR', 'SUM') -- all terms
       UNION ALL
       -- Lab/Lecture Mismatch
       SELECT t.term_code,
               NULL AS next_term_code, -- NOT IMPORTANT FOR THIS TASK
               t.start_date - 90 AS from_date, -- START SHOWING RECORDS
               trunc(t.end_date - 30) - (1 / (24 * 60 * 60)) AS to_date, -- STOP SHOWING (format as 11:59:59pm)
               t.semester AS semester,
               stvterm_desc AS semester_desc,
               'LXL' AS category_code,
               'Lab/Lecture Mismatch' AS category_desc,
               0.46 AS priority,
               SYSDATE AS activity_date
         FROM zbtm.terms_by_group_v t
         JOIN stvterm
           ON stvterm_code = t.term_code
        WHERE t.term_code = rec.term_code
          AND t.group_code = 'STD'
          AND t.semester IN ('FAL', 'SPR', 'SUM') -- all terms
       UNION ALL
       -- Transcript Status (Incoming)
       SELECT t.term_code,
               NULL AS next_term_code, -- NOT IMPORTANT FOR THIS TASK
               t.start_date - 90 AS from_date, -- START SHOWING RECORDS
               trunc(t.end_date) - (1 / (24 * 60 * 60)) AS to_date, -- STOP SHOWING (format as 11:59:59pm)
               t.semester AS semester,
               stvterm_desc AS semester_desc,
               'TSI' AS category_code,
               'Transcript Status' AS category_desc,
               0.45 AS priority,
               SYSDATE AS activity_date
         FROM zbtm.terms_by_group_v t
         JOIN stvterm
           ON stvterm_code = t.term_code
        WHERE t.term_code = rec.term_code
          AND t.group_code = 'STD'
          AND t.semester IN ('FAL', 'SPR', 'SUM') -- all terms
       ) src
ON (tgt.term_code = src.term_code AND tgt.category_code = src.category_code)
WHEN MATCHED THEN
UPDATE
   SET tgt.next_term_code = src.next_term_code,
       tgt.from_date      = src.from_date,
       tgt.to_date        = src.to_date,
       tgt.semester       = src.semester,
       tgt.semester_desc  = src.semester_desc,
       tgt.category_desc  = src.category_desc,
       tgt.priority       = src.priority,
       tgt.activity_date  = SYSDATE
WHEN NOT MATCHED THEN
INSERT
(term_code,
 next_term_code,
 from_date,
 to_date,
 semester,
 semester_desc,
 category_code,
 category_desc,
 priority,
 activity_date)
VALUES
(src.term_code,
 src.next_term_code,
 src.from_date,
 src.to_date,
 src.semester,
 src.semester_desc,
 src.category_code,
 src.category_desc,
 src.priority,
 src.activity_date);
v_count := SQL%ROWCOUNT;
COMMIT;
dbms_lock.sleep(0.5); -- pause half second
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count;
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
EXIT; -- Success, exit retry loop
EXCEPTION
WHEN OTHERS THEN
IF SQLCODE = -60 THEN
-- Deadlock detected
v_retry_count := v_retry_count + 1;
IF v_retry_count > v_max_retries THEN
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := '!!!-00060: deadlock detected while waiting for resource. Max retries exceeded after ' || (v_max_retries * v_wait_time) || ' seconds';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
EXIT; -- Give up after max retries
ELSE
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'Deadlock detected while waiting for resource - waiting ' || v_wait_time || ' seconds for retry attempt number ' || v_retry_count;
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'WARNING', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
dbms_lock.sleep(v_wait_time);
CONTINUE; -- Retry
END IF;
ELSE
-- Other errors
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
EXIT; -- Exit on other errors
END IF;
END;
END LOOP; -- end deadlock detection
dbms_output.put_line(' --------- ');
END LOOP; -- c_rec
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
EXCEPTION
WHEN OTHERS THEN
dbms_lock.sleep(0.5); -- pause half second
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
END etl_aa_casas_advising_schedule;

END load_aa_etl_casas;
-- GRANT EXECUTE ON load_aa_etl_casas TO utl_d_aim;
-- GRANT EXECUTE ON load_aa_etl_casas TO utl_d_aa;
-- GRANT EXECUTE ON load_aa_etl_casas TO utl_d_lms;
-- GRANT EXECUTE ON load_aa_etl_casas TO utl_d_luo;
-- GRANT EXECUTE ON load_aa_etl_casas TO wgriffith2;
-- GRANT EXECUTE ON load_aa_etl_casas TO ZETL_JAMS_SVC;