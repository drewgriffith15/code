create or replace package load_aa_etl is
-- course calendar
procedure etl_aa_crscalendar_refresh (jobnumber number, processid varchar2, processname varchar2);
-- course final grades
procedure etl_aa_crsgrade_refresh (jobnumber number, processid varchar2, processname varchar2);
procedure etl_aa_crsgradestats_refresh (jobnumber number, processid varchar2, processname varchar2);
-- sgbi codes
procedure etl_aa_embbsbgiiatt_merge (jobnumber number, processid varchar2, processname varchar2);
procedure etl_aa_embbsbgiiext_merge (jobnumber number, processid varchar2, processname varchar2);
procedure etl_aa_inbbsbgiinst_refresh (jobnumber number, processid varchar2, processname varchar2);
-- luoa canvas
procedure etl_aa_luoa_emails (jobnumber number, processid varchar2, processname varchar2);
-- frozen file enrollment
procedure etl_aa_rsbbzsrcefa_refresh (jobnumber number, processid varchar2, processname varchar2, inst varchar2, nmbr number);
-- row level security (rls)
procedure etl_aa_faculty_hierarchy (jobnumber number, processid varchar2, processname varchar2);
procedure etl_aa_secfht_refresh (jobnumber number, processid varchar2, processname varchar2);
procedure etl_aa_secfhtcoll_refresh (jobnumber number, processid varchar2, processname varchar2);
-- student fn grade log
procedure etl_aa_stufngrade_log_refresh (jobnumber number, processid varchar2, processname varchar2);
-- student historical academic performance
procedure etl_aa_stuacadperform_refresh(jobnumber number,processid varchar2, processname varchar2);
procedure etl_aa_stucrseperform_refresh(jobnumber number,processid varchar2, processname varchar2);
procedure etl_aa_stuprofperform_refresh(jobnumber number,processid varchar2, processname varchar2);
procedure etl_aa_stusubjperform_refresh(jobnumber number,processid varchar2, processname varchar2);
procedure etl_aa_stucollperform_refresh(jobnumber number,processid varchar2, processname varchar2);
-- student HS_GPA and test scores
procedure etl_aa_stuhsgpa(jobnumber number,processid varchar2, processname varchar2);
procedure etl_aa_stutestscores(jobnumber number,processid varchar2, processname varchar2);
-- tableau staging
procedure etl_aa_fn_grade_projections_tableau(jobnumber number, processid varchar2, processname varchar2);
end load_aa_etl;
/

create or replace package body load_aa_etl_main is

procedure etl_aa_faculty_hierarchy (jobnumber number, processid varchar2, processname varchar2) is
/*
Table: utl_d_aa.faculty_hierarchy

Unique index: unique_id, from_date, to_date

Purpose:
- log table of all the faculty hierarchy associations linking faculty to all their superiors

Conditions:
- Must be in the FHT and an active faculty in the HR table

*/
--DECLARE
v_etl_date    DATE := SYSDATE;
v_end_date    DATE := SYSDATE - 1 / (24 * 60 * 60); -- ONE SEC BEHIND
v_msg         VARCHAR2(255);
v_row_max     NUMBER := 1000000; -- max number of rows to be processed at one time
v_job_id      VARCHAR2(32);
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_cpu         NUMBER := 4; -- number of CPUs used for parallelization - do not exceed 20 CPUs [v_mod x v_cpu] if running simultaneously
v_proc        VARCHAR2(100) := 'etl_aa_faculty_hierarchy';
v_instance    VARCHAR2(100) := 'ALL'; -- placeholder
v_partition    NUMBER := 0; -- placeholder
CURSOR curs IS
SELECT src.pidm,
       src.superior_pidm,
       src.superior_username,
       src.superior,
       src.superior_position,
       src.hierarchy_title_id,
       src.camp_code,
       src.coll_code,
       src.url,
       src.unique_id,
       CASE
       WHEN tgt.pidm IS NULL THEN
        'INSERT' -- new record to source, add it
       WHEN src.superior_username || src.superior || src.superior_position || src.url <> tgt.superior_username || tgt.superior || tgt.superior_position || tgt.url THEN
        'EXPIRE' -- record no longer exists, expire it
       ELSE
        'UPDATE' -- existing record, no change; gets latest activity_date (needed to find expirations at the end)
       END AS control_state, -- NEVER DELETE - EVER!
       COUNT(*) over() total_rows
  FROM (SELECT pidm,
               superior_pidm,
               superior_username,
               superior,
               superior_position,
               hierarchy_title_id,
               camp_code,
               coll_code,
               url,
               standard_hash(pidm || superior_pidm || hierarchy_title_id || camp_code || coll_code, 'MD5') AS unique_id,
               rank() over(PARTITION BY pidm || superior_pidm || hierarchy_title_id || camp_code || coll_code ORDER BY rownum) ranking -- this is resolve bad FHT data 
          FROM (WITH lvl1 AS (SELECT DISTINCT position.pidm AS pidm, -- must be hard-coded pidm showing instructor; must be distinct bc we don't need the department.dept_code
                                               spriden_pidm AS superior_pidm, -- shows the person above the previous lower level
                                               gobtpac_external_user AS superior_username,
                                               spriden_last_name || ', ' || spriden_first_name AS superior,
                                               hierarchy_title.id AS hierarchy_title_id,
                                               title.description AS superior_position,
                                               department.campus AS camp_code,
                                               department.college_code AS coll_code,
                                               position.approval_position_id,
                                               department.id AS department_id
                                 FROM zhierarchy.position
                                 JOIN saturn.spriden
                                   ON spriden_pidm = position.pidm
                                  AND spriden_change_ind IS NULL
                                  AND position.hierarchy_title_id IN (13, 6) -- faculty rows only
                                 JOIN gobtpac
                                   ON gobtpac_pidm = spriden_pidm
                                 JOIN zhierarchy.hierarchy_title
                                   ON position.hierarchy_title_id = hierarchy_title.id
                                 JOIN zhierarchy.title
                                   ON hierarchy_title.title_id = title.id
                                 JOIN zhierarchy.department
                                   ON position.department_id = department.id
                                  AND department.college_code IS NOT NULL -- returns academics positions (exlcuding all else)
                                 JOIN zgeneral.activefacultystaff -- a join to this view gets active faculty and staff without any filtering
                                   ON lower(activefacultystaff.empuserusername) = lower(gobtpac_external_user)
                                  
                               ), --
                lvl2 AS (SELECT DISTINCT lvl1.pidm, -- pass through the faculty pidm; must be distinct bc we don't need the department.dept_code
                                        spriden_pidm AS superior_pidm, -- shows the person above the previous lower level
                                        gobtpac_external_user AS superior_username,
                                        spriden_last_name || ', ' || spriden_first_name AS superior,
                                        hierarchy_title.id AS hierarchy_title_id,
                                        title.description AS superior_position,
                                        department.campus AS camp_code,
                                        department.college_code AS coll_code,
                                        position.approval_position_id
                          FROM lvl1
                          JOIN zhierarchy.position position
                            ON position.id = lvl1.approval_position_id
                          JOIN saturn.spriden
                            ON spriden_pidm = position.pidm
                           AND spriden_change_ind IS NULL
                          JOIN gobtpac
                            ON gobtpac_pidm = spriden_pidm
                          JOIN zhierarchy.hierarchy_title hierarchy_title
                            ON position.hierarchy_title_id = hierarchy_title.id
                          JOIN zhierarchy.title title
                            ON title.id = hierarchy_title.title_id
                          JOIN zhierarchy.department department
                            ON position.department_id = department.id
                           AND department.college_code IS NOT NULL -- returns academics positions (exlcuding all else)
                          JOIN zgeneral.activefacultystaff -- a join to this view gets active faculty and staff without any filtering
                            ON lower(activefacultystaff.empuserusername) = lower(gobtpac_external_user)
                           
                        ), --
               lvl3 AS (SELECT DISTINCT lvl2.pidm, -- pass through the faculty pidm; must be distinct bc we don't need the department.dept_code
                                         spriden_pidm AS superior_pidm, -- shows the person above the previous lower level
                                         gobtpac_external_user AS superior_username,
                                         spriden_last_name || ', ' || spriden_first_name AS superior,
                                         hierarchy_title.id AS hierarchy_title_id,
                                         title.description AS superior_position,
                                         department.campus AS camp_code,
                                         department.college_code AS coll_code,
                                         position.approval_position_id
                           FROM lvl2
                           JOIN zhierarchy.position position
                             ON position.id = lvl2.approval_position_id
                           JOIN saturn.spriden
                             ON spriden_pidm = position.pidm
                            AND spriden_change_ind IS NULL
                           JOIN gobtpac
                             ON gobtpac_pidm = spriden_pidm
                           JOIN zhierarchy.hierarchy_title hierarchy_title
                             ON position.hierarchy_title_id = hierarchy_title.id
                           JOIN zhierarchy.title title
                             ON title.id = hierarchy_title.title_id
                           JOIN zhierarchy.department department
                             ON position.department_id = department.id
                            AND department.college_code IS NOT NULL -- returns academics positions (exlcuding all else)
                           JOIN zgeneral.activefacultystaff -- a join to this view gets active faculty and staff without any filtering
                             ON lower(activefacultystaff.empuserusername) = lower(gobtpac_external_user)
                            
                         ), --
                lvl4 AS (SELECT DISTINCT lvl3.pidm, -- pass through the faculty pidm; must be distinct bc we don't need the department.dept_code
                                        spriden_pidm AS superior_pidm, -- shows the person above the previous lower level
                                        gobtpac_external_user AS superior_username,
                                        spriden_last_name || ', ' || spriden_first_name AS superior,
                                        hierarchy_title.id AS hierarchy_title_id,
                                        title.description AS superior_position,
                                        department.campus AS camp_code,
                                        department.college_code AS coll_code,
                                        position.approval_position_id
                          FROM lvl3
                          JOIN zhierarchy.position position
                            ON position.id = lvl3.approval_position_id
                          JOIN saturn.spriden
                            ON spriden_pidm = position.pidm
                           AND spriden_change_ind IS NULL
                          JOIN gobtpac
                            ON gobtpac_pidm = spriden_pidm
                          JOIN zhierarchy.hierarchy_title hierarchy_title
                            ON position.hierarchy_title_id = hierarchy_title.id
                          JOIN zhierarchy.title title
                            ON title.id = hierarchy_title.title_id
                          JOIN zhierarchy.department department
                            ON position.department_id = department.id
                           AND department.college_code IS NOT NULL -- returns academics positions (exlcuding all else)
                          JOIN zgeneral.activefacultystaff -- a join to this view gets active faculty and staff without any filtering
                            ON lower(activefacultystaff.empuserusername) = lower(gobtpac_external_user)
                           
                        ), --
               lvl5 AS (SELECT DISTINCT lvl4.pidm, -- pass through the faculty pidm; must be distinct bc we don't need the department.dept_code
                                         spriden_pidm AS superior_pidm, -- shows the person above the previous lower level
                                         gobtpac_external_user AS superior_username,
                                         spriden_last_name || ', ' || spriden_first_name AS superior,
                                         hierarchy_title.id AS hierarchy_title_id,
                                         title.description AS superior_position,
                                         department.campus AS camp_code,
                                         department.college_code AS coll_code,
                                         position.approval_position_id
                           FROM lvl4
                           JOIN zhierarchy.position position
                             ON position.id = lvl4.approval_position_id
                           JOIN saturn.spriden
                             ON spriden_pidm = position.pidm
                            AND spriden_change_ind IS NULL
                           JOIN gobtpac
                             ON gobtpac_pidm = spriden_pidm
                           JOIN zhierarchy.hierarchy_title hierarchy_title
                             ON position.hierarchy_title_id = hierarchy_title.id
                           JOIN zhierarchy.title title
                             ON title.id = hierarchy_title.title_id
                           JOIN zhierarchy.department department
                             ON position.department_id = department.id
                            AND department.college_code IS NOT NULL -- returns academics positions (exlcuding all else)
                           JOIN zgeneral.activefacultystaff -- a join to this view gets active faculty and staff without any filtering
                             ON lower(activefacultystaff.empuserusername) = lower(gobtpac_external_user)
                            
                         ), --
                fsc AS (SELECT DISTINCT lvl1.pidm, -- pass through the faculty pidm; must be distinct bc we don't need the department.dept_code
                                       spriden_pidm AS superior_pidm, -- shows the person above the previous lower level
                                       gobtpac_external_user AS superior_username,
                                       spriden_last_name || ', ' || spriden_first_name AS superior,
                                       0 AS hierarchy_title_id, -- we do not have IDs for FSCs
                                       'Faculty Support Coordinator' AS superior_position,
                                       department.campus AS camp_code,
                                       department.college_code AS coll_code
                         FROM lvl1
                         JOIN zhierarchy.department_fsc fsc
                           ON fsc.department_id = lvl1.department_id
                         JOIN saturn.spriden
                           ON spriden_pidm = fsc.pidm
                          AND spriden_change_ind IS NULL
                         JOIN gobtpac
                           ON gobtpac_pidm = spriden_pidm
                         JOIN zhierarchy.department department
                           ON fsc.department_id = department.id
                          AND department.college_code IS NOT NULL -- returns academics positions (exlcuding all else)
                         JOIN zgeneral.activefacultystaff -- a join to this view gets active faculty and staff without any filtering
                           ON lower(activefacultystaff.empuserusername) = lower(gobtpac_external_user)
                          
                       )
               -- pull it all together 
               SELECT DISTINCT pidm, -- must be distinct bc we don't need the department.dept_code
                                superior_pidm,
                                superior_username,
                                superior,
                                superior_position,
                                hierarchy_title_id,
                                camp_code,
                                coll_code,
                                'https://faculty-hierarchy.liberty.edu/#/people/' || superior_pidm AS url
                  FROM lvl1
                UNION ALL
                SELECT DISTINCT pidm, -- must be distinct bc we don't need the department.dept_code
                               superior_pidm,
                               superior_username,
                               superior,
                               superior_position,
                               hierarchy_title_id,
                               camp_code,
                               coll_code,
                               'https://faculty-hierarchy.liberty.edu/#/people/' || superior_pidm AS url
                 FROM lvl2
               UNION ALL
               SELECT DISTINCT pidm, -- must be distinct bc we don't need the department.dept_code
                                superior_pidm,
                                superior_username,
                                superior,
                                superior_position,
                                hierarchy_title_id,
                                camp_code,
                                coll_code,
                                'https://faculty-hierarchy.liberty.edu/#/people/' || superior_pidm AS url
                  FROM lvl3
                UNION ALL
                SELECT DISTINCT pidm, -- must be distinct bc we don't need the department.dept_code
                               superior_pidm,
                               superior_username,
                               superior,
                               superior_position,
                               hierarchy_title_id,
                               camp_code,
                               coll_code,
                               'https://faculty-hierarchy.liberty.edu/#/people/' || superior_pidm AS url
                 FROM lvl4
               UNION ALL
               SELECT DISTINCT pidm, -- must be distinct bc we don't need the department.dept_code
                                superior_pidm,
                                superior_username,
                                superior,
                                superior_position,
                                hierarchy_title_id,
                                camp_code,
                                coll_code,
                                'https://faculty-hierarchy.liberty.edu/#/people/' || superior_pidm AS url
                  FROM lvl5
                UNION ALL
                SELECT DISTINCT pidm, -- must be distinct bc we don't need the department.dept_code
                               superior_pidm,
                               superior_username,
                               superior,
                               superior_position,
                               hierarchy_title_id,
                               camp_code,
                               coll_code,
                               'https://faculty-hierarchy.liberty.edu/#/people/' || superior_pidm AS url
                 FROM fsc)
        ) src
  LEFT JOIN utl_d_aa.faculty_hierarchy tgt
    ON tgt.unique_id = src.unique_id
   AND tgt.to_date = to_date('12/31/2099', 'MM/DD/YYYY') -- only return active records from the target (ignore all previous)
 WHERE src.ranking = 1;
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
TYPE index_pointer_e IS TABLE OF PLS_INTEGER;
expire_dml index_pointer_e := index_pointer_e();
TYPE index_pointer_u IS TABLE OF PLS_INTEGER;
update_dml index_pointer_u := index_pointer_u();
TYPE index_pointer_i IS TABLE OF PLS_INTEGER;
insert_dml   index_pointer_i := index_pointer_i();
start_time   TIMESTAMP;
end_time     TIMESTAMP;
select_count NUMBER := 0;
expire_count NUMBER := 0;
update_count NUMBER := 0;
insert_count NUMBER := 0;
start_t      DATE := SYSDATE;
elapsed      NUMBER := 0;
BEGIN
-- dbms_output.enable(buffer_size => NULL);
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
OPEN curs;
LOOP
v_count   := 0; -- reset count
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ALL' || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
FETCH curs BULK COLLECT
INTO rec_input LIMIT v_row_max;
IF rec_input.count = 0 THEN
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'SELECT - ALL' || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
RETURN;
ELSIF rec_input.count > 0 THEN
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'SELECT - ' || v_instance || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
expire_dml := index_pointer_e();
update_dml := index_pointer_u();
insert_dml := index_pointer_i();
-- collect records to DML
FOR idx IN rec_input.first .. rec_input.last
LOOP
v_count := rec_input(idx).total_rows;
IF rec_input(idx).control_state IN ('EXPIRE') THEN
-- record no longer exists, expire it
expire_dml.extend;
expire_dml(expire_dml.last) := idx;
END IF;
IF rec_input(idx).control_state IN ('UPDATE') THEN
-- existing record, no change; gets latest activity_date (needed to find expirations at the end)
update_dml.extend;
update_dml(update_dml.last) := idx;
END IF;
IF rec_input(idx).control_state IN ('INSERT', 'EXPIRE') THEN
-- new record to source, add it OR record had changes, so we insert latest change
insert_dml.extend;
insert_dml(insert_dml.last) := idx;
END IF;
END LOOP;
expire_count := expire_count + expire_dml.count;
update_count := update_count + update_dml.count;
insert_count := insert_count + insert_dml.count;
-- existing record, no change; gets latest activity_date (needed to find expirations at the end)
FORALL i IN VALUES OF update_dml
UPDATE utl_d_aa.faculty_hierarchy tab
   SET (activity_date) =
       (SELECT v_etl_date FROM dual)
 WHERE tab.unique_id = rec_input(i).unique_id
   AND tab.to_date = to_date('12/31/2099', 'MM/DD/YYYY');
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'UPDATE - NO CHANGES - ALL' || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- record no longer exists, expire it
FORALL i IN VALUES OF expire_dml
UPDATE utl_d_aa.faculty_hierarchy tab
   SET (activity_date, to_date) =
       (SELECT v_etl_date,
               v_end_date
          FROM dual)
 WHERE tab.unique_id = rec_input(i).unique_id
   AND tab.to_date = to_date('12/31/2099', 'MM/DD/YYYY');
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'UPDATE - EXPIRED - ' || v_instance || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- new record to source, add it OR record had changes, so we insert latest change
FORALL i IN VALUES OF insert_dml
INSERT INTO utl_d_aa.faculty_hierarchy
(pidm,
 superior_pidm,
 superior_username,
 superior,
 superior_position,
 hierarchy_title_id,
 camp_code,
 coll_code,
 url,
 unique_id,
 activity_date,
 from_date,
 to_date)
VALUES
(rec_input(i).pidm,
 rec_input(i).superior_pidm,
 rec_input(i).superior_username,
 rec_input(i).superior,
 rec_input(i).superior_position,
 rec_input(i).hierarchy_title_id,
 rec_input(i).camp_code,
 rec_input(i).coll_code,
 rec_input(i).url,
 rec_input(i).unique_id,
 v_etl_date,
 v_etl_date,
 to_date('12/31/2099', 'MM/DD/YYYY'));
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - NEW OR CHANGE - ' || v_instance || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
END IF;
SELECT ((CAST(SYSDATE AS DATE) - CAST(start_t AS DATE)) * 86400) INTO elapsed FROM dual;
select_count := select_count + rec_input.count;
EXIT WHEN(rec_input.count < v_row_max);
end loop;
CLOSE curs;
dbms_output.put_line(' --------- ');
-- ** keep outside of looping ** expire records that don't exist in current cursor; this is delayed until next run, but that is okay for records that no longer exist!
UPDATE utl_d_aa.faculty_hierarchy tgt
      SET (activity_date, to_date) =
       (SELECT v_etl_date,
               v_end_date
          FROM dual)
 WHERE tgt.to_date = to_date('12/31/2099', 'MM/DD/YYYY')
   AND tgt.activity_date < v_etl_date; -- record wasn't looped over on last run, so it no longer exists, end it.
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'UPDATE - NO LONGER EXISTS - ' || v_instance || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
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
---     05-16-2025  WGRIFFITH2  -- Initial release
---     10-23-2025  WGRIFFITH2   -- missing some people in the FHT due to empstatus set to only 'A"; changed to: JOIN zgeneral.activefacultystaff -- a join to this view gets active faculty and staff without any filtering
------------------------------------------------------------------------------------------------*/
END etl_aa_faculty_hierarchy;

PROCEDURE etl_aa_fn_grade_projections_tableau(jobnumber   NUMBER, processid   VARCHAR2, processname VARCHAR2) IS
/*
Table: fn_grade_projections_tableau

Unique index: NONE

Purpose:
- new table structure for dashboard compatibility. pulls 3 years prior to the current term

Conditions:
- Data must be accurate and up-to-date.

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
v_proc        VARCHAR2(100) := 'etl_aa_fn_grade_projections_tableau';
CURSOR c_terms IS
SELECT DISTINCT t.term_code
  FROM zbtm.terms_by_group_v t
 WHERE 1 = 1
   AND (t.group_code IN ('STD') AND t.term_code >= '201538' AND SYSDATE >= t.start_date - 180 AND SYSDATE <= t.end_date + (365 * 5)) -- prevent overlap of CD1 and CD2
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
IF to_char(SYSDATE, 'HH24') IN ('01') THEN -- run once a day only
utl_d_aa.truncate_table(v_table_name => 'fn_grade_projections_tableau');
FOR rec IN c_terms
LOOP
v_count   := 0; -- reset count
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
INSERT INTO utl_d_aa.fn_grade_projections_tableau
(term_code,
 ptrm_code,
 semester,
 unique_headcount,
 f,
 f_percent,
 proj_f,
 diff_f,
 fn,
 fn_percent,
 proj_fn,
 diff_fn,
 w,
 w_percent,
 proj_w,
 diff_w)
SELECT s.term_code,
       s.ptrm_code,
       s.semester,
       COUNT(DISTINCT s.pidm) unique_headcount,
       COUNT(DISTINCT CASE
             WHEN s.final_grade = 'F' THEN
              pidm
             END) f,
       COUNT(DISTINCT CASE
             WHEN s.final_grade = 'F' THEN
              pidm
             END) / COUNT(DISTINCT s.pidm) f_percent,
       round(AVG(arc.f_percent) * COUNT(DISTINCT s.pidm)) proj_f,
       round(AVG(arc.f_percent) * COUNT(DISTINCT s.pidm)) - COUNT(DISTINCT CASE
                                                                  WHEN s.final_grade = 'F' THEN
                                                                   pidm
                                                                  END) diff_f,
       COUNT(DISTINCT CASE
             WHEN s.final_grade IN ('FN','NF') /*added NF on 20250607*/ THEN
              pidm
             END) fn,
       COUNT(DISTINCT CASE
             WHEN s.final_grade IN ('FN','NF') /*added NF on 20250607*/ THEN
              pidm
             END) / COUNT(DISTINCT s.pidm) fn_percent,
       round(AVG(arc.fn_percent) * COUNT(DISTINCT s.pidm)) proj_fn,
       round(AVG(arc.fn_percent) * COUNT(DISTINCT s.pidm)) - COUNT(DISTINCT CASE
                                                                   WHEN s.final_grade IN ('FN','NF') /*added NF on 20250607*/ THEN
                                                                    pidm
                                                                   END) diff_fn,
       COUNT(DISTINCT CASE
             WHEN s.final_grade = 'W' THEN
              pidm
             END) w,
       COUNT(DISTINCT CASE
             WHEN s.final_grade = 'W' THEN
              pidm
             END) / COUNT(DISTINCT s.pidm) w_percent,
       round(AVG(arc.w_percent) * COUNT(DISTINCT s.pidm)) proj_w,
       round(AVG(arc.w_percent) * COUNT(DISTINCT s.pidm)) - COUNT(DISTINCT CASE
                                                                  WHEN s.final_grade = 'W' THEN
                                                                   pidm
                                                                  END) diff_w
  FROM utl_d_aim.szrcrse s
  JOIN (SELECT term_code,
               ptrm_code,
               semester,
               COUNT(DISTINCT pidm) unique_headcount,
               COUNT(DISTINCT CASE
                     WHEN final_grade = 'F' THEN
                      pidm
                     END) f,
               COUNT(DISTINCT CASE
                     WHEN final_grade = 'F' THEN
                      pidm
                     END) / COUNT(DISTINCT pidm) f_percent,
               COUNT(DISTINCT CASE
                     WHEN final_grade IN ('FN','NF') /*added NF on 20250607*/ THEN
                      pidm
                     END) fn,
               COUNT(DISTINCT CASE
                     WHEN final_grade IN ('FN','NF') /*added NF on 20250607*/ THEN
                      pidm
                     END) / COUNT(DISTINCT pidm) fn_percent,
               COUNT(DISTINCT CASE
                     WHEN final_grade = 'W' THEN
                      pidm
                     END) w,
               COUNT(DISTINCT CASE
                     WHEN final_grade = 'W' THEN
                      pidm
                     END) / COUNT(DISTINCT pidm) w_percent
          FROM utl_d_aim.szrcrse
         WHERE group_code = 'STD'
           AND semester IN ('SPR', 'FAL', 'SUM')
           AND term_code < rec.term_code
           AND term_code >= rec.term_code - 300
           AND ptrm_code IN ('1A', '1B', '1C', '1D', '1J', 'R')
         GROUP BY term_code,
                  ptrm_code,
                  semester) arc
    ON arc.semester = s.semester
   AND arc.ptrm_code = s.ptrm_code
 WHERE s.group_code = 'STD'
   AND s.semester IN ('SPR', 'FAL', 'SUM')
   AND s.ptrm_code IN ('1A', '1B', '1C', '1D', '1J', 'R')
   AND s.term_code = rec.term_code
 GROUP BY s.term_code,
          s.ptrm_code,
          s.semester;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
end loop; -- c_terms
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
---     05-31-2024  WGRIFFITH2  --Initial release
------------------------------------------------------------------------------------------------*/
END etl_aa_fn_grade_projections_tableau;

procedure etl_aa_luoa_emails (jobnumber number, processid varchar2, processname varchar2) IS
--
-- PURPOSE: Consolidates all email addresses associated with LUOA students, including parents, guardians, affiliates, and the student, for communication and outreach purposes.
--
-- TABLE: utl_d_aa.luoa_emails
--
-- UNIQUE INDEX: STUDENT_PIDM, PROXY_PIDM, PROXY_EMAIL_ADDRESS
--
-- CONDITIONS:
-- Runs only during midnight hour (00) to minimize system load.
-- Includes emails for proxies (parents, guardians, affiliates) based on active Banner proxy relationships within start and stop dates.
-- Proxy type is derived from relationship code (RET P_CODE); affiliates are prioritized as POC individuals.
-- Includes student emails marked as SELF when no shared email exists with other proxies.
-- Pulls email addresses from zsavemal table and ranks them by email code group priority (LU, LUAD, PER, PG) and group rank to select the best email per student-proxy combination.
-- Ensures only active proxies (PIN not disabled) and valid Banner IDs (no change indicator) are included.
-- Filters affiliate proxies using specific ADID codes (LCIA, LCOA).
-- Deduplicates emails using RANK() to guarantee one unique email per student-proxy pair.
-- Excludes any email already associated with another student when processing SELF type.
-- Updates existing records or inserts new ones based on student-proxy-email combination.
-- Deletes previous proxy-type records before inserting updated data for proxies and SELF type to maintain accuracy.
-- No duplicate emails will exist in the final table.
--
-- URL: N/A
--
--DECLARE
--- PARAMS
v_etl_date    DATE := SYSDATE;
v_msg         VARCHAR2(2000);
v_instance    VARCHAR2(50) := upper('ALL'); -- inst from the jams job; used for determining instance
v_partition    NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_count       NUMBER := 0;
v_total_count NUMBER := 0;
v_elapsed     NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_aa_luoa_emails';
BEGIN
-- dbms_output.enable(buffer_size => NULL);
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
IF to_char(SYSDATE, 'HH24') IN ('00') THEN
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || 'ALL' || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
DELETE FROM utl_d_aa.luoa_emails le WHERE le.proxy_type NOT IN ('SELF'); -- check for family member, guardian, or affiliate poc
-- DO NOT COMMIT HERE; COMMIT AFTER SUCCESSFUL TRANSACTION
MERGE INTO utl_d_aa.luoa_emails destination_table
USING (SELECT student_pidm,
              student_luid,
              student_first_name,
              student_last_name,
              proxy_email_address,
              proxy_type,
              proxy_pidm,
              proxy_luid,
              proxy_first_name,
              proxy_last_name,
              proxy_emal_code_group,
              proxy_emal_code_group_rank,
              activity_date
         FROM (SELECT x.gprxref_person_pidm AS student_pidm,
                      stu.spriden_id AS student_luid,
                      stu.spriden_first_name AS student_first_name,
                      stu.spriden_last_name AS student_last_name,
                      lower(zsavemal.email_address) AS proxy_email_address,
                      CASE
                      WHEN x.gprxref_retp_code = 'ADVISOR' THEN
                       'AFFILIATE'
                      ELSE
                       x.gprxref_retp_code
                      END AS proxy_type,
                      g.gpbprxy_proxy_pidm AS proxy_pidm,
                      poc.spriden_id AS proxy_luid,
                      poc.spriden_first_name AS proxy_first_name,
                      poc.spriden_last_name proxy_last_name,
                      zsavemal.emal_code_group AS proxy_emal_code_group,
                      zsavemal.emal_code_group_rank AS proxy_emal_code_group_rank,
                      -- unique email per student & POC
                      rank() over(PARTITION BY x.gprxref_person_pidm, g.gpbprxy_proxy_pidm, lower(zsavemal.email_address) ORDER BY decode(zsavemal.emal_code_group, 'LU', 0, 'LUAD', 1, 'PER', 2, 'PG', 3, 9), emal_code_group_rank, rownum) ranking, -- pulls best unique list of emails for each pidm
                      SYSDATE AS activity_date
                 FROM gprxref x
                 JOIN gpbprxy g
                   ON g.gpbprxy_proxy_idm = x.gprxref_proxy_idm
                  AND g.gpbprxy_pin_disabled_ind = 'N'
                 JOIN saturn.spriden poc
                   ON spriden_pidm = g.gpbprxy_proxy_pidm
                  AND poc.spriden_change_ind IS NULL
                 JOIN saturn.spriden stu
                   ON stu.spriden_pidm = x.gprxref_person_pidm
                  AND stu.spriden_change_ind IS NULL
                 LEFT JOIN goradid p
                   ON p.goradid_pidm = g.gpbprxy_proxy_pidm
                  AND p.goradid_adid_code IN ('LCIA', 'LCOA') -- affiliate poc/observer codes
                 LEFT JOIN zexec.zsavemal
                   ON zsavemal.pidm = g.gpbprxy_proxy_pidm
                WHERE SYSDATE BETWEEN x.gprxref_start_date AND x.gprxref_stop_date) base
        WHERE ranking = 1) new_records
ON (destination_table.student_pidm = new_records.student_pidm AND destination_table.proxy_pidm = new_records.proxy_pidm AND destination_table.proxy_email_address = new_records.proxy_email_address)
WHEN MATCHED THEN
UPDATE
   SET destination_table.student_first_name = new_records.student_first_name,
       destination_table.student_last_name  = new_records.student_last_name,
       destination_table.student_luid       = new_records.student_luid,
       destination_table.proxy_first_name   = new_records.proxy_first_name,
       destination_table.proxy_luid         = new_records.proxy_luid,
       destination_table.proxy_type         = new_records.proxy_type,
       destination_table.proxy_last_name    = new_records.proxy_last_name,
       destination_table.activity_date      = new_records.activity_date
WHEN NOT MATCHED THEN
INSERT
(student_pidm,
 student_first_name,
 student_last_name,
 student_luid,
 proxy_pidm,
 proxy_luid,
 proxy_email_address,
 proxy_first_name,
 proxy_last_name,
 proxy_type,
 proxy_emal_code_group,
 proxy_emal_code_group_rank)
VALUES
(new_records.student_pidm,
 new_records.student_first_name,
 new_records.student_last_name,
 new_records.student_luid,
 new_records.proxy_pidm,
 new_records.proxy_luid,
 new_records.proxy_email_address,
 new_records.proxy_first_name,
 new_records.proxy_last_name,
 new_records.proxy_type,
 new_records.proxy_emal_code_group,
 new_records.proxy_emal_code_group_rank);
v_count := SQL%ROWCOUNT;
IF v_count > 0 THEN
v_total_count := v_total_count + v_count;
v_msg         := ' rows processed for PROXY: ' || v_count || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss');
dbms_output.put_line(v_msg);
COMMIT;
ELSE
v_msg := ' No rows processed!! Rolling back last DELETE at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss');
dbms_output.put_line(v_msg);
ROLLBACK;
END IF;
DELETE FROM utl_d_aa.luoa_emails le WHERE le.proxy_type = 'SELF'; -- next pass - find all emails associated to student
-- DO NOT COMMIT HERE; COMMIT AFTER SUCCESSFUL TRANSACTION
MERGE INTO utl_d_aa.luoa_emails destination_table
USING (SELECT student_pidm,
              student_luid,
              student_first_name,
              student_last_name,
              proxy_email_address,
              proxy_type,
              proxy_pidm,
              proxy_luid,
              proxy_first_name,
              proxy_last_name,
              proxy_emal_code_group,
              proxy_emal_code_group_rank,
              activity_date
         FROM (SELECT su.pidm AS student_pidm,
                      su.luid AS student_luid,
                      su.first_name AS student_first_name,
                      su.last_name AS student_last_name,
                      lower(zsavemal.email_address) AS proxy_email_address,
                      'SELF' AS proxy_type,
                      su.pidm AS proxy_pidm,
                      su.luid AS proxy_luid,
                      su.first_name AS proxy_first_name,
                      su.last_name AS proxy_last_name,
                      zsavemal.emal_code_group AS proxy_emal_code_group,
                      zsavemal.emal_code_group_rank AS proxy_emal_code_group_rank,
                      -- unique email per student
                      rank() over(PARTITION BY su.pidm, lower(zsavemal.email_address) ORDER BY decode(zsavemal.emal_code_group, 'LU', 0, 'LUAD', 1, 'PER', 2, 'PG', 3, 9), emal_code_group_rank, rownum) ranking, -- pulls best unique list of emails for each pidm
                      SYSDATE AS activity_date
                 FROM zexec.zsavemal
                 JOIN utl_d_lms.student_users su
                   ON su.pidm = zsavemal.pidm
                  AND su.instance = 'ACCAN'
                 LEFT JOIN utl_d_aa.luoa_emails le -- only emails that are not shared by anyone else
                   ON le.proxy_email_address = lower(zsavemal.email_address)
                WHERE le.student_pidm IS NULL) base --ADD union for apps and inqu??
        WHERE ranking = 1) new_records
ON (destination_table.student_pidm = new_records.student_pidm AND destination_table.proxy_pidm = new_records.proxy_pidm AND destination_table.proxy_email_address = new_records.proxy_email_address)
WHEN MATCHED THEN
UPDATE
   SET destination_table.student_first_name = new_records.student_first_name,
       destination_table.student_last_name  = new_records.student_last_name,
       destination_table.student_luid       = new_records.student_luid,
       destination_table.proxy_first_name   = new_records.proxy_first_name,
       destination_table.proxy_luid         = new_records.proxy_luid,
       destination_table.proxy_type         = new_records.proxy_type,
       destination_table.proxy_last_name    = new_records.proxy_last_name,
       destination_table.activity_date      = new_records.activity_date
WHEN NOT MATCHED THEN
INSERT
(student_pidm,
 student_first_name,
 student_last_name,
 student_luid,
 proxy_pidm,
 proxy_luid,
 proxy_email_address,
 proxy_first_name,
 proxy_last_name,
 proxy_type,
 proxy_emal_code_group,
 proxy_emal_code_group_rank)
VALUES
(new_records.student_pidm,
 new_records.student_first_name,
 new_records.student_last_name,
 new_records.student_luid,
 new_records.proxy_pidm,
 new_records.proxy_luid,
 new_records.proxy_email_address,
 new_records.proxy_first_name,
 new_records.proxy_last_name,
 new_records.proxy_type,
 new_records.proxy_emal_code_group,
 new_records.proxy_emal_code_group_rank);
v_count := SQL%ROWCOUNT;
IF v_count > 0 THEN
v_total_count := v_total_count + v_count;
v_msg         := ' rows processed for SELF: ' || v_count || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss');
dbms_output.put_line(v_msg);
COMMIT;
ELSE
v_msg := ' No rows processed!! Rolling back last DELETE at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss');
dbms_output.put_line(v_msg);
ROLLBACK;
END IF;
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
v_msg     := substr(SQLERRM, 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
/*--------------------------------------------CHANGE LOG----------------------------------------
VERSION   DATE        USERNAME    UPDATES
---       10-12-2022  WGRIFFITH2   --Initial release
---       01-27-2023  WGRIFFITH2   --adding ads_etl.insert_job_log logging
------------------------------------------------------------------------------------------------*/
END etl_aa_luoa_emails; --

PROCEDURE etl_aa_stuhsgpa(jobnumber NUMBER,processid VARCHAR2, processname VARCHAR2) IS
--DECLARE
v_etl_date DATE := SYSDATE;
l_start    NUMBER;
CURSOR crsr_terms IS
SELECT z.term_code AS term_code
  FROM zbtm.terms_by_group_v z
 WHERE 1 = 1
   AND z.term_code IN (SELECT (z.term_code) t
                         FROM zbtm.terms_by_group_v z
                        WHERE SYSDATE >= z.start_date - 7
                          AND SYSDATE < z.end_date + 22
                          AND z.semester <> 'WIN'
                          AND z.group_code = 'STD')
              AND to_char(SYSDATE, 'HH24') IN ('00')
   AND z.group_code = 'STD'
   AND z.semester <> 'WIN';
BEGIN
l_start := dbms_utility.get_time; -- Time regular updates
dbms_output.put_line('Started at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ';');
FOR tbl_terms IN crsr_terms
LOOP
MERGE INTO utl_d_aa.stuhsgpa t1
USING (SELECT enrl.pidm,
              hs_gpa,
              SYSDATE AS activity_date
         FROM utl_d_aim.szrenrl enrl
         JOIN (SELECT sorhsch_pidm pidm,
                     sorhsch_sbgi_code sbgi,
                     round(sorhsch_gpa, 3) hs_gpa,
                     rank() over(PARTITION BY sorhsch_pidm ORDER BY sorhsch_gpa DESC, rownum) rnk
                FROM sorhsch
               WHERE sorhsch_sbgi_code NOT IN ('B99999', '010002')
                 AND (length(TRIM(translate(sorhsch_gpa, '.0123456789', ' '))) IS NULL AND substr(sorhsch_gpa, 1, 2) IN ('0.', '1.', '2.', '3.', '4.') AND
                     length(sorhsch_gpa) - length(REPLACE(sorhsch_gpa, '.')) < 2)) hs
           ON hs.pidm = enrl.pidm
        WHERE enrl.term_code = tbl_terms.term_code
          AND rnk = 1) t2
ON (t1.pidm = t2.pidm)
WHEN MATCHED THEN
UPDATE
   SET t1.hs_gpa        = t2.hs_gpa,
       t1.activity_date = t2.activity_date
WHEN NOT MATCHED THEN
INSERT
VALUES
(t2.pidm,
 t2.hs_gpa,
 t2.activity_date);
COMMIT;
END LOOP;
dbms_output.put_line('Ended at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'));
/*--------------------------------------------CHANGE LOG----------------------------------------
VERSION DATE        USERNAME    UPDATES
---     08-18-2020  WGRIFFITH2  --Initial release
------------------------------------------------------------------------------------------------*/
END etl_aa_stuhsgpa;

PROCEDURE etl_aa_stutestscores(jobnumber NUMBER,processid VARCHAR2, processname VARCHAR2) IS
--DECLARE
v_etl_date DATE := SYSDATE;
l_start    NUMBER;
CURSOR crsr_terms IS
SELECT z.term_code AS term_code
  FROM zbtm.terms_by_group_v z
 WHERE 1=1
   AND z.term_code in (SELECT (z.term_code) t
                         FROM zbtm.terms_by_group_v z
                        WHERE SYSDATE >= z.start_date - 7
                          AND SYSDATE < z.end_date + 22
                          AND z.semester <> 'WIN'
                          AND z.group_code = 'STD')
              AND to_char(SYSDATE, 'HH24') IN ('00')
   AND z.group_code = 'STD'
   AND z.semester <> 'WIN';
BEGIN
l_start := dbms_utility.get_time; -- Time regular updates
dbms_output.put_line('Started at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ';');
FOR tbl_terms IN crsr_terms
LOOP
MERGE INTO utl_d_aa.stutestscores t1
USING (SELECT DISTINCT spriden_pidm pidm,
                       'SAT Composite' AS test_desc,
                       1 AS version_number,
                       scores.score AS test_score,
                       v_etl_date AS activity_date
         FROM spriden
         JOIN utl_d_aim.szrenrl enrl
           ON enrl.pidm = spriden_pidm
          AND enrl.term_code = tbl_terms.term_code
          AND spriden_change_ind IS NULL
         JOIN (SELECT sortest.sortest_pidm pidm,
                     MAX(CASE
                         WHEN sortest_tesc_code = 'S01' THEN
                          to_number(sortest_test_score)
                         END) + MAX(CASE
                                    WHEN sortest_tesc_code = 'S02' THEN
                                     to_number(sortest_test_score)
                                    END) score
                FROM saturn.sortest sortest
               WHERE sortest.sortest_tesc_code IN ('S01', 'S02')
               GROUP BY sortest.sortest_pidm) scores
           ON scores.pidm = spriden_pidm) t2
ON (t1.pidm = t2.pidm AND t1.test_desc = t2.test_desc AND t1.version_number = t2.version_number)
WHEN MATCHED THEN
UPDATE
   SET t1.test_score    = t2.test_score,
       t1.activity_date = t2.activity_date
WHEN NOT MATCHED THEN
INSERT
VALUES
(t2.pidm,
 t2.test_desc,
 t2.version_number,
 t2.test_score,
 t2.activity_date);
COMMIT;
--
MERGE INTO utl_d_aa.stutestscores t1
USING (SELECT DISTINCT spriden_pidm pidm,
                       'SAT Composite' AS test_desc,
                       2 AS version_number,
                       scores.score AS test_score,
                       v_etl_date AS activity_date
         FROM spriden
         JOIN utl_d_aim.szrenrl enrl
           ON enrl.pidm = spriden_pidm
          AND enrl.term_code = tbl_terms.term_code
          AND spriden_change_ind IS NULL
         JOIN (SELECT sortest.sortest_pidm pidm,
                     MAX(CASE
                         WHEN sortest_tesc_code = 'SMMT' THEN
                          to_number(sortest_test_score)
                         END) + MAX(CASE
                                    WHEN sortest_tesc_code = 'SMRW' THEN
                                     to_number(sortest_test_score)
                                    END) score
                FROM saturn.sortest sortest
               WHERE sortest.sortest_tesc_code IN ('SMRW', 'SMMT')
               GROUP BY sortest.sortest_pidm) scores
           ON scores.pidm = spriden_pidm) t2
ON (t1.pidm = t2.pidm AND t1.test_desc = t2.test_desc AND t1.version_number = t2.version_number)
WHEN MATCHED THEN
UPDATE
   SET t1.test_score    = t2.test_score,
       t1.activity_date = t2.activity_date
WHEN NOT MATCHED THEN
INSERT
VALUES
(t2.pidm,
 t2.test_desc,
 t2.version_number,
 t2.test_score,
 t2.activity_date);
COMMIT;
--
MERGE INTO utl_d_aa.stutestscores t1
USING (SELECT DISTINCT spriden_pidm pidm,
                       'ACT Composite' AS test_desc,
                       1 AS version_number,
                       scores.score AS test_score,
                       v_etl_date AS activity_date
         FROM spriden
         JOIN utl_d_aim.szrenrl enrl
           ON enrl.pidm = spriden_pidm
          AND enrl.term_code = tbl_terms.term_code
          AND spriden_change_ind IS NULL
         JOIN (SELECT sortest.sortest_pidm pidm,
                     round((MAX(CASE
                                WHEN sortest_tesc_code = 'A01' THEN
                                 to_number(sortest_test_score)
                                END) + MAX(CASE
                                            WHEN sortest_tesc_code = 'A02' THEN
                                             to_number(sortest_test_score)
                                            END) + MAX(CASE
                                                        WHEN sortest_tesc_code = 'A03' THEN
                                                         to_number(sortest_test_score)
                                                        END) + MAX(CASE
                                                                    WHEN sortest_tesc_code = 'A04' THEN
                                                                     to_number(sortest_test_score)
                                                                    END)) / 4, 0) score
                FROM saturn.sortest sortest
               WHERE sortest.sortest_tesc_code IN ('A01', 'A02', 'A03', 'A04')
               GROUP BY sortest.sortest_pidm) scores
           ON scores.pidm = spriden_pidm) t2
ON (t1.pidm = t2.pidm AND t1.test_desc = t2.test_desc AND t1.version_number = t2.version_number)
WHEN MATCHED THEN
UPDATE
   SET t1.test_score    = t2.test_score,
       t1.activity_date = t2.activity_date
WHEN NOT MATCHED THEN
INSERT
VALUES
(t2.pidm,
 t2.test_desc,
 t2.version_number,
 t2.test_score,
 t2.activity_date);
COMMIT;
--
MERGE INTO utl_d_aa.stutestscores t1
USING (SELECT DISTINCT spriden_pidm pidm,
                       'LSAT' AS test_desc,
                       1 AS version_number,
                       scores.score AS test_score,
                       v_etl_date AS activity_date
         FROM spriden
         JOIN utl_d_aim.szrenrl enrl
           ON enrl.pidm = spriden_pidm
          AND enrl.term_code = tbl_terms.term_code
          AND spriden_change_ind IS NULL
         JOIN (SELECT sortest.sortest_pidm pidm,
                     MAX(CASE
                         WHEN sortest_tesc_code = 'LSAT' THEN
                          to_number(sortest_test_score)
                         END) score
                FROM saturn.sortest sortest
               WHERE sortest.sortest_tesc_code IN ('LSAT')
               GROUP BY sortest.sortest_pidm) scores
           ON scores.pidm = spriden_pidm) t2
ON (t1.pidm = t2.pidm AND t1.test_desc = t2.test_desc AND t1.version_number = t2.version_number)
WHEN MATCHED THEN
UPDATE
   SET t1.test_score    = t2.test_score,
       t1.activity_date = t2.activity_date
WHEN NOT MATCHED THEN
INSERT
VALUES
(t2.pidm,
 t2.test_desc,
 t2.version_number,
 t2.test_score,
 t2.activity_date);
COMMIT;
end loop;
dbms_output.put_line('Ended at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'));
/*--------------------------------------------CHANGE LOG----------------------------------------
VERSION DATE        USERNAME    UPDATES
---     08-18-2020  WGRIFFITH2  --Initial release
------------------------------------------------------------------------------------------------*/
END etl_aa_stutestscores;

PROCEDURE etl_aa_stuacadperform_refresh(jobnumber NUMBER,processid VARCHAR2, processname VARCHAR2) IS
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
v_proc        VARCHAR2(100) := 'etl_aa_stuacadperform_refresh';
CURSOR c_terms IS
SELECT terms.term_code AS term_code,
       to_char(terms.term_code - 300) AS from_term_code
  FROM zbtm.terms_by_group_v terms
 WHERE terms.term_code IN (SELECT term_code
                             FROM zbtm.terms_by_group_v terms
                            WHERE group_code IN ('STD')
                              AND semester <> 'WIN'
                              AND SYSDATE BETWEEN start_date - 7 AND end_date + 7)
   AND EXISTS (SELECT 1 FROM utl_d_aa.stuacadperform scp HAVING MAX(trunc(scp.activity_date)) <> trunc(SYSDATE)) -- Check if data has already been loaded today
UNION
SELECT DISTINCT shrtckg_term_code AS term_code,
                to_char(shrtckg_term_code - 300) AS from_term_code
  FROM saturn.shrtckg
  JOIN (SELECT group_code,
               term_code
          FROM zbtm.terms_by_group_v t
         WHERE 1 = 1
           AND t.group_code = 'STD') fg
    ON fg.term_code = shrtckg_term_code
 WHERE 1 = 1
   AND shrtckg_final_grde_chg_date > SYSDATE - 1 -- check for any grade changes
   AND shrtckg_term_code IN (SELECT terms.term_code
                               FROM zbtm.terms_by_group_v terms
                              WHERE terms.group_code = 'STD'
                                AND (SYSDATE BETWEEN terms.start_date - 21 AND terms.end_date + (365 * 1))
                                AND terms.semester <> 'WIN')
   AND EXISTS (SELECT 1 FROM utl_d_aa.stuacadperform scp HAVING MAX(trunc(scp.activity_date)) <> trunc(SYSDATE)) -- Check if data has already been loaded today
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
  -- Clear GTT tables before processing
utl_d_aa.truncate_table(v_table_name => 'stuacadperformpo_gtt');
utl_d_aa.truncate_table(v_table_name => 'stuacadperformso_gtt');
v_count   := 0; -- reset count
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
INSERT INTO utl_d_aa.stuacadperformpo_gtt
(term_code,
 avg_grade,
 p_pct,
 w_pct,
 fn_pct,
 avg_grade_asof_term,
 p_pct_asof_term,
 w_pct_asof_term,
 fn_pct_asof_term,
 seat_cnt)
SELECT rec.term_code AS term_code,
       sco.avg_grade AS avg_grade,
       sco.p_pct     AS p_pct,
       sco.w_pct     AS w_pct,
       sco.fn_pct    AS fn_pct,
       sao.avg_grade AS avg_grade_asof_term,
       sao.p_pct     AS p_pct_asof_term,
       sao.w_pct     AS w_pct_asof_term,
       sao.fn_pct    AS fn_pct_asof_term,
       sco.seat_cnt  AS seat_cnt
  FROM (SELECT AVG(CASE
                   WHEN crs.final_grade = 'P' THEN
                    4
                   ELSE
                    crs.grade_quality_points
                   END) AS avg_grade,
               CASE
               WHEN COUNT(CASE
                          WHEN crs.final_grade IS NOT NULL THEN
                           1
                          END) = 0 THEN
                NULL
               ELSE
                SUM(CASE
                    WHEN crs.final_grade IS NOT NULL
                         AND (crs.grade_quality_points >= 2 OR crs.final_grade = 'P') THEN
                     1
                    ELSE
                     0
                    END) / COUNT(CASE
                                 WHEN crs.final_grade IS NOT NULL THEN
                                  1
                                 END)
               END AS p_pct,
               CASE
               WHEN COUNT(CASE
                          WHEN crs.final_grade IS NOT NULL THEN
                           1
                          END) = 0 THEN
                NULL
               ELSE
                SUM(CASE
                    WHEN crs.final_grade IS NOT NULL
                         AND substr(crs.final_grade, 1, 1) = 'W' THEN
                     1
                    ELSE
                     0
                    END) / COUNT(CASE
                                 WHEN crs.final_grade IS NOT NULL THEN
                                  1
                                 END)
               END AS w_pct,
               CASE
               WHEN COUNT(CASE
                          WHEN crs.final_grade IS NOT NULL THEN
                           1
                          END) = 0 THEN
                NULL
               ELSE
                SUM(CASE
                    WHEN crs.final_grade IS NOT NULL
                         AND substr(crs.final_grade, 1, 2) IN ('FN', 'NF') THEN
                     1
                    ELSE
                     0
                    END) / COUNT(CASE
                                 WHEN crs.final_grade IS NOT NULL THEN
                                  1
                                 END)
               END AS fn_pct,
               COUNT(*) AS seat_cnt
          FROM utl_d_aim.szrcrse crs
          JOIN zsaturn.szrlevl l
            ON l.szrlevl_levl_code = crs.levl_code
           AND l.szrlevl_has_awardable_cred = 'Y'
         WHERE 1 = 1
           AND crs.group_code = 'STD'
           AND crs.term_code BETWEEN rec.from_term_code AND rec.term_code) sco -- student current overall
 CROSS JOIN (SELECT AVG(CASE
                        WHEN crs.final_grade = 'P' THEN
                         4
                        ELSE
                         crs.grade_quality_points
                        END) AS avg_grade,
                    CASE
                    WHEN COUNT(CASE
                               WHEN crs.final_grade IS NOT NULL THEN
                                1
                               END) = 0 THEN
                     NULL
                    ELSE
                     SUM(CASE
                         WHEN crs.final_grade IS NOT NULL
                              AND (crs.grade_quality_points >= 2 OR crs.final_grade = 'P') THEN
                          1
                         ELSE
                          0
                         END) / COUNT(CASE
                                      WHEN crs.final_grade IS NOT NULL THEN
                                       1
                                      END)
                    END AS p_pct,
                    CASE
                    WHEN COUNT(CASE
                               WHEN crs.final_grade IS NOT NULL THEN
                                1
                               END) = 0 THEN
                     NULL
                    ELSE
                     SUM(CASE
                         WHEN crs.final_grade IS NOT NULL
                              AND substr(crs.final_grade, 1, 1) = 'W' THEN
                          1
                         ELSE
                          0
                         END) / COUNT(CASE
                                      WHEN crs.final_grade IS NOT NULL THEN
                                       1
                                      END)
                    END AS w_pct,
                    CASE
                    WHEN COUNT(CASE
                               WHEN crs.final_grade IS NOT NULL THEN
                                1
                               END) = 0 THEN
                     NULL
                    ELSE
                     SUM(CASE
                         WHEN crs.final_grade IS NOT NULL
                              AND substr(crs.final_grade, 1, 2) IN ('FN', 'NF') THEN
                          1
                         ELSE
                          0
                         END) / COUNT(CASE
                                      WHEN crs.final_grade IS NOT NULL THEN
                                       1
                                      END)
                    END AS fn_pct
               FROM utl_d_aim.szrcrse crs
               JOIN zsaturn.szrlevl l
                 ON l.szrlevl_levl_code = crs.levl_code
                AND l.szrlevl_has_awardable_cred = 'Y'
              WHERE 1 = 1
                AND crs.group_code = 'STD'
                AND crs.term_code < rec.term_code) sao; -- student as of term overall
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
INSERT INTO utl_d_aa.stuacadperformso_gtt
(pidm,
 term_code,
 avg_grade,
 p_pct,
 w_pct,
 fn_pct,
 avg_grade_asof_term,
 p_pct_asof_term,
 w_pct_asof_term,
 fn_pct_asof_term,
 seat_cnt,
 quality_points,
 quality_points_asof_term)
SELECT sco.pidm                  AS pidm,
       rec.term_code             AS term_code,
       sco.avg_grade             AS avg_grade,
       sco.p_pct                 AS p_pct,
       sco.w_pct                 AS w_pct,
       sco.fn_pct                AS fn_pct,
       sao.avg_grade             AS avg_grade_asof_term,
       sao.p_pct                 AS p_pct_asof_term,
       sao.w_pct                 AS w_pct_asof_term,
       sao.fn_pct                AS fn_pct,
       sco.seat_cnt              AS seat_cnt,
       sco.quality_points_earned,
       sao.quality_points_earned -- _asof_term
  FROM (SELECT crs.pidm AS pidm,
               AVG(CASE
                   WHEN crs.final_grade = 'P' THEN
                    4
                   ELSE
                    crs.grade_quality_points
                   END) AS avg_grade,
               CASE
               WHEN COUNT(CASE
                          WHEN crs.final_grade IS NOT NULL THEN
                           1
                          END) = 0 THEN
                NULL
               ELSE
                SUM(CASE
                    WHEN crs.final_grade IS NOT NULL
                         AND (crs.grade_quality_points >= 2 OR crs.final_grade = 'P') THEN
                     1
                    ELSE
                     0
                    END) / COUNT(CASE
                                 WHEN crs.final_grade IS NOT NULL THEN
                                  1
                                 END)
               END AS p_pct,
               CASE
               WHEN COUNT(CASE
                          WHEN crs.final_grade IS NOT NULL THEN
                           1
                          END) = 0 THEN
                NULL
               ELSE
                SUM(CASE
                    WHEN crs.final_grade IS NOT NULL
                         AND substr(crs.final_grade, 1, 1) = 'W' THEN
                     1
                    ELSE
                     0
                    END) / COUNT(CASE
                                 WHEN crs.final_grade IS NOT NULL THEN
                                  1
                                 END)
               END AS w_pct,
               CASE
               WHEN COUNT(CASE
                          WHEN crs.final_grade IS NOT NULL THEN
                           1
                          END) = 0 THEN
                NULL
               ELSE
                SUM(CASE
                    WHEN crs.final_grade IS NOT NULL
                         AND substr(crs.final_grade, 1, 2) IN ('FN', 'NF') THEN
                     1
                    ELSE
                     0
                    END) / COUNT(CASE
                                 WHEN crs.final_grade IS NOT NULL THEN
                                  1
                                 END)
               END AS fn_pct,
               COUNT(*) AS seat_cnt,
               SUM(crs.grade_quality_points) AS quality_points_earned
          FROM utl_d_aim.szrcrse crs
          JOIN zsaturn.szrlevl l
            ON l.szrlevl_levl_code = crs.levl_code
           AND l.szrlevl_has_awardable_cred = 'Y'
         WHERE 1 = 1
           AND crs.group_code = 'STD'
           AND crs.term_code BETWEEN rec.from_term_code AND rec.term_code
           AND crs.pidm IN (SELECT DISTINCT pidm FROM utl_d_aim.szrenrl enrl WHERE term_code = rec.term_code) -- must be enrolled in term
         GROUP BY crs.pidm) sco -- student current overall
  LEFT JOIN (SELECT crs.pidm AS pidm,
                    AVG(CASE
                        WHEN crs.final_grade = 'P' THEN
                         4
                        ELSE
                         crs.grade_quality_points
                        END) AS avg_grade,
                    CASE
                    WHEN COUNT(CASE
                               WHEN crs.final_grade IS NOT NULL THEN
                                1
                               END) = 0 THEN
                     NULL
                    ELSE
                     SUM(CASE
                         WHEN crs.final_grade IS NOT NULL
                              AND (crs.grade_quality_points >= 2 OR crs.final_grade = 'P') THEN
                          1
                         ELSE
                          0
                         END) / COUNT(CASE
                                      WHEN crs.final_grade IS NOT NULL THEN
                                       1
                                      END)
                    END AS p_pct,
                    CASE
                    WHEN COUNT(CASE
                               WHEN crs.final_grade IS NOT NULL THEN
                                1
                               END) = 0 THEN
                     NULL
                    ELSE
                     SUM(CASE
                         WHEN crs.final_grade IS NOT NULL
                              AND substr(crs.final_grade, 1, 1) = 'W' THEN
                          1
                         ELSE
                          0
                         END) / COUNT(CASE
                                      WHEN crs.final_grade IS NOT NULL THEN
                                       1
                                      END)
                    END AS w_pct,
                    CASE
                    WHEN COUNT(CASE
                               WHEN crs.final_grade IS NOT NULL THEN
                                1
                               END) = 0 THEN
                     NULL
                    ELSE
                     SUM(CASE
                         WHEN crs.final_grade IS NOT NULL
                              AND substr(crs.final_grade, 1, 2) IN ('FN', 'NF') THEN
                          1
                         ELSE
                          0
                         END) / COUNT(CASE
                                      WHEN crs.final_grade IS NOT NULL THEN
                                       1
                                      END)
                    END AS fn_pct,
                    SUM(crs.grade_quality_points) AS quality_points_earned
               FROM utl_d_aim.szrcrse crs
               JOIN zsaturn.szrlevl l
                 ON l.szrlevl_levl_code = crs.levl_code
                AND l.szrlevl_has_awardable_cred = 'Y'
              WHERE 1 = 1
                AND crs.group_code = 'STD'
                AND crs.term_code < rec.term_code
                AND crs.pidm IN (SELECT DISTINCT pidm FROM utl_d_aim.szrenrl enrl WHERE term_code = rec.term_code) -- must be enrolled in term
              GROUP BY crs.pidm) sao -- student as of term overall
    ON sao.pidm = sco.pidm;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
MERGE INTO utl_d_aa.stuacadperform t1
USING (SELECT so.pidm,
              rec.term_code AS term_code,
              round(so.avg_grade, 4) AS avg_grade,
              round(so.p_pct, 4) AS p_pct,
              round(so.w_pct, 4) AS w_pct,
              round(so.fn_pct, 4) AS fn_pct,
              round(so.avg_grade_asof_term, 4) AS avg_grade_asof_term,
              round(so.p_pct_asof_term, 4) AS p_pct_asof_term,
              round(so.w_pct_asof_term, 4) AS w_pct_asof_term,
              round(so.fn_pct_asof_term, 4) AS fn_pct_asof_term,
              so.seat_cnt AS seat_cnt,
              round(po.avg_grade, 4) AS avg_grade_peer,
              round(po.p_pct, 4) AS p_pct_peer,
              round(po.w_pct, 4) AS w_pct_peer,
              round(po.fn_pct, 4) AS fn_pct_peer,
              round(po.avg_grade_asof_term, 4) AS avg_grade_asof_term_peer,
              round(po.p_pct_asof_term, 4) AS p_pct_asof_term_peer,
              round(po.w_pct_asof_term, 4) AS w_pct_asof_term_peer,
              round(po.fn_pct_asof_term, 4) AS fn_pct_asof_term_peer,
              po.seat_cnt AS seat_cnt_peer,
              v_etl_date AS activity_date,
              round(so.quality_points, 4) AS quality_points,
              round(so.quality_points_asof_term, 4) AS quality_points_asof_term
         FROM utl_d_aa.stuacadperformso_gtt so
         LEFT JOIN utl_d_aa.stuacadperformpo_gtt po
           ON po.term_code = so.term_code
        WHERE so.term_code = rec.term_code) t2
ON (t1.pidm = t2.pidm AND t1.term_code = t2.term_code)
WHEN MATCHED THEN
UPDATE
   SET t1.avg_grade                = t2.avg_grade,
       t1.p_pct                    = t2.p_pct,
       t1.w_pct                    = t2.w_pct,
       t1.fn_pct                   = t2.fn_pct,
       t1.avg_grade_asof_term      = t2.avg_grade_asof_term,
       t1.p_pct_asof_term          = t2.p_pct_asof_term,
       t1.w_pct_asof_term          = t2.w_pct_asof_term,
       t1.fn_pct_asof_term         = t2.fn_pct_asof_term,
       t1.seat_cnt                 = t2.seat_cnt,
       t1.avg_grade_peer           = t2.avg_grade_peer,
       t1.p_pct_peer               = t2.p_pct_peer,
       t1.w_pct_peer               = t2.w_pct_peer,
       t1.fn_pct_peer              = t2.fn_pct_peer,
       t1.avg_grade_asof_term_peer = t2.avg_grade_asof_term_peer,
       t1.p_pct_asof_term_peer     = t2.p_pct_asof_term_peer,
       t1.w_pct_asof_term_peer     = t2.w_pct_asof_term_peer,
       t1.fn_pct_asof_term_peer    = t2.fn_pct_asof_term_peer,
       t1.seat_cnt_peer            = t2.seat_cnt_peer,
       t1.quality_points           = t2.quality_points,
       t1.quality_points_asof_term = t2.quality_points_asof_term,
       t1.activity_date            = t2.activity_date
WHEN NOT MATCHED THEN
INSERT
VALUES
(t2.pidm,
 t2.term_code,
 t2.avg_grade,
 t2.p_pct,
 t2.w_pct,
 t2.fn_pct,
 t2.avg_grade_asof_term,
 t2.p_pct_asof_term,
 t2.w_pct_asof_term,
 t2.fn_pct_asof_term,
 t2.seat_cnt,
 t2.avg_grade_peer,
 t2.p_pct_peer,
 t2.w_pct_peer,
 t2.fn_pct_peer,
 t2.avg_grade_asof_term_peer,
 t2.p_pct_asof_term_peer,
 t2.w_pct_asof_term_peer,
 t2.fn_pct_asof_term_peer,
 t2.seat_cnt_peer,
 v_etl_date,
 t2.quality_points,
 t2.quality_points_asof_term);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- remove any students NOT currently enrolled [dropped NOT withdraw]
-- do not try to time restrict here because of the way the cursor works only running once a day
DELETE FROM utl_d_aa.stuacadperform sp
 WHERE sp.term_code = rec.term_code
   AND NOT EXISTS (SELECT 1
          FROM utl_d_aim.szrenrl enrl
         WHERE enrl.term_code = sp.term_code
           AND enrl.pidm = sp.pidm);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'DELETE - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
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
  -- Clear GTT tables on error
utl_d_aa.truncate_table(v_table_name => 'stuacadperformpo_gtt');
utl_d_aa.truncate_table(v_table_name => 'stuacadperformso_gtt');
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
/*--------------------------------------------CHANGE LOG----------------------------------------
VERSION    DATE        USERNAME       UPDATES
---        03-27-2020  wgriffith2     --Initial release
--         03-08-2021  wgriffith2     --Adding quality_points and quality_points_asof_term
---        06-30-2022  wgriffith2     --refreshes do not happen until the subterm is completed
---        08-24-2022  wgriffith2     --refreshes must happen once the subterm starts! I fixed the seat count field to not start counting until the term has completed
---        09-09-2022  wgriffith2     --reverting back to the version prior to 20220630 to fix issues report in TKT2555560; optimization - only returning rows when active enrollment on the particular dimension
---        01-23-2025  wgriffith2     --fixing issues with pass/fail courses producing 0s; quality points show 0 when course is passed.
---        07-01-2025  wgriffith2     --Enhanced by implementing batch processing to handle large data volumes efficiently;  Added logic to ensure p_pct, w_pct, fn_pct are NULL if no non-null final grades exist in the group.
------------------------------------------------------------------------------------------------*/
END etl_aa_stuacadperform_refresh; -- 

PROCEDURE etl_aa_stucollperform_refresh(jobnumber NUMBER,processid VARCHAR2, processname VARCHAR2) IS
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
v_proc        VARCHAR2(100) := 'etl_aa_stucollperform_refresh';
CURSOR c_terms IS
SELECT terms.term_code AS term_code,
       to_char(terms.term_code - 300) AS from_term_code
  FROM zbtm.terms_by_group_v terms
 WHERE terms.term_code IN (SELECT term_code
                             FROM zbtm.terms_by_group_v terms
                            WHERE group_code IN ('STD')
                              AND semester <> 'WIN'
                              AND SYSDATE BETWEEN start_date - 7 AND end_date + 7)
   AND EXISTS (SELECT 1 FROM utl_d_aa.stucollperform scp HAVING MAX(trunc(scp.activity_date)) <> trunc(SYSDATE)) -- Check if data has already been loaded today
UNION
SELECT DISTINCT shrtckg_term_code AS term_code,
                to_char(shrtckg_term_code - 300) AS from_term_code
  FROM saturn.shrtckg
  JOIN (SELECT group_code,
               term_code
          FROM zbtm.terms_by_group_v t
         WHERE 1 = 1
           AND t.group_code = 'STD') fg
    ON fg.term_code = shrtckg_term_code
 WHERE 1 = 1
   AND shrtckg_final_grde_chg_date > SYSDATE - 1 -- check for any grade changes
   AND shrtckg_term_code IN (SELECT terms.term_code
                               FROM zbtm.terms_by_group_v terms
                              WHERE terms.group_code = 'STD'
                                AND (SYSDATE BETWEEN terms.start_date - 21 AND terms.end_date + (365 * 1))
                                AND terms.semester <> 'WIN')
   AND EXISTS (SELECT 1 FROM utl_d_aa.stucollperform scp HAVING MAX(trunc(scp.activity_date)) <> trunc(SYSDATE)) -- Check if data has already been loaded today
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
utl_d_aa.truncate_table(v_table_name => 'stucollperformpo_gtt');
utl_d_aa.truncate_table(v_table_name => 'stucollperformso_gtt');
v_count   := 0; -- reset count
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
INSERT INTO utl_d_aa.stucollperformpo_gtt
(coll_code,
 term_code,
 avg_grade,
 p_pct,
 w_pct,
 fn_pct,
 avg_grade_asof_term,
 p_pct_asof_term,
 w_pct_asof_term,
 fn_pct_asof_term,
 seat_cnt)
SELECT sco.coll_code AS coll_code,
       rec.term_code AS term_code,
       sco.avg_grade AS avg_grade,
       sco.p_pct     AS p_pct,
       sco.w_pct     AS w_pct,
       sco.fn_pct    AS fn_pct,
       sao.avg_grade AS avg_grade_asof_term,
       sao.p_pct     AS p_pct_asof_term,
       sao.w_pct     AS w_pct_asof_term,
       sao.fn_pct    AS fn_pct_asof_term,
       sco.seat_cnt  AS seat_cnt
  FROM (SELECT crs.coll_code AS coll_code,
               AVG(CASE
                   WHEN crs.final_grade = 'P' THEN
                    4
                   ELSE
                    crs.grade_quality_points
                   END) AS avg_grade,
               CASE
               WHEN COUNT(CASE
                          WHEN crs.final_grade IS NOT NULL THEN
                           1
                          END) = 0 THEN
                NULL
               ELSE
                SUM(CASE
                    WHEN crs.final_grade IS NOT NULL
                         AND (crs.grade_quality_points >= 2 OR crs.final_grade = 'P') THEN
                     1
                    ELSE
                     0
                    END) / COUNT(CASE
                                 WHEN crs.final_grade IS NOT NULL THEN
                                  1
                                 END)
               END AS p_pct,
               CASE
               WHEN COUNT(CASE
                          WHEN crs.final_grade IS NOT NULL THEN
                           1
                          END) = 0 THEN
                NULL
               ELSE
                SUM(CASE
                    WHEN crs.final_grade IS NOT NULL
                         AND substr(crs.final_grade, 1, 1) = 'W' THEN
                     1
                    ELSE
                     0
                    END) / COUNT(CASE
                                 WHEN crs.final_grade IS NOT NULL THEN
                                  1
                                 END)
               END AS w_pct,
               CASE
               WHEN COUNT(CASE
                          WHEN crs.final_grade IS NOT NULL THEN
                           1
                          END) = 0 THEN
                NULL
               ELSE
                SUM(CASE
                    WHEN crs.final_grade IS NOT NULL
                         AND substr(crs.final_grade, 1, 2) IN ('FN', 'NF') THEN
                     1
                    ELSE
                     0
                    END) / COUNT(CASE
                                 WHEN crs.final_grade IS NOT NULL THEN
                                  1
                                 END)
               END AS fn_pct,
               COUNT(*) AS seat_cnt
          FROM utl_d_aim.szrcrse crs
          JOIN zsaturn.szrlevl l
            ON l.szrlevl_levl_code = crs.levl_code
           AND l.szrlevl_has_awardable_cred = 'Y'
         WHERE 1 = 1
           AND crs.group_code = 'STD'
           AND crs.term_code BETWEEN rec.from_term_code AND rec.term_code
         GROUP BY crs.coll_code) sco -- student current overall
  LEFT JOIN (SELECT crs.coll_code AS coll_code,
                    AVG(CASE
                        WHEN crs.final_grade = 'P' THEN
                         4
                        ELSE
                         crs.grade_quality_points
                        END) AS avg_grade,
                    CASE
                    WHEN COUNT(CASE
                               WHEN crs.final_grade IS NOT NULL THEN
                                1
                               END) = 0 THEN
                     NULL
                    ELSE
                     SUM(CASE
                         WHEN crs.final_grade IS NOT NULL
                              AND (crs.grade_quality_points >= 2 OR crs.final_grade = 'P') THEN
                          1
                         ELSE
                          0
                         END) / COUNT(CASE
                                      WHEN crs.final_grade IS NOT NULL THEN
                                       1
                                      END)
                    END AS p_pct,
                    CASE
                    WHEN COUNT(CASE
                               WHEN crs.final_grade IS NOT NULL THEN
                                1
                               END) = 0 THEN
                     NULL
                    ELSE
                     SUM(CASE
                         WHEN crs.final_grade IS NOT NULL
                              AND substr(crs.final_grade, 1, 1) = 'W' THEN
                          1
                         ELSE
                          0
                         END) / COUNT(CASE
                                      WHEN crs.final_grade IS NOT NULL THEN
                                       1
                                      END)
                    END AS w_pct,
                    CASE
                    WHEN COUNT(CASE
                               WHEN crs.final_grade IS NOT NULL THEN
                                1
                               END) = 0 THEN
                     NULL
                    ELSE
                     SUM(CASE
                         WHEN crs.final_grade IS NOT NULL
                              AND substr(crs.final_grade, 1, 2) IN ('FN', 'NF') THEN
                          1
                         ELSE
                          0
                         END) / COUNT(CASE
                                      WHEN crs.final_grade IS NOT NULL THEN
                                       1
                                      END)
                    END AS fn_pct
               FROM utl_d_aim.szrcrse crs
               JOIN zsaturn.szrlevl l
                 ON l.szrlevl_levl_code = crs.levl_code
                AND l.szrlevl_has_awardable_cred = 'Y'
              WHERE 1 = 1
                AND crs.group_code = 'STD'
                AND crs.term_code < rec.term_code
              GROUP BY crs.coll_code) sao -- student as of term overall
    ON sao.coll_code = sco.coll_code;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
INSERT INTO utl_d_aa.stucollperformso_gtt
(pidm,
 coll_code,
 term_code,
 avg_grade,
 p_pct,
 w_pct,
 fn_pct,
 avg_grade_asof_term,
 p_pct_asof_term,
 w_pct_asof_term,
 fn_pct_asof_term,
 seat_cnt,
 quality_points,
 quality_points_asof_term)
SELECT sco.pidm                  AS pidm,
       sco.coll_code             AS coll_code,
       rec.term_code             AS term_code,
       sco.avg_grade             AS avg_grade,
       sco.p_pct                 AS p_pct,
       sco.w_pct                 AS w_pct,
       sco.fn_pct                AS fn_pct,
       sao.avg_grade             AS avg_grade_asof_term,
       sao.p_pct                 AS p_pct_asof_term,
       sao.w_pct                 AS w_pct_asof_term,
       sao.fn_pct                AS fn_pct,
       sco.seat_cnt              AS seat_cnt,
       sco.quality_points_earned,
       sao.quality_points_earned AS quality_points_asof_term
  FROM (SELECT crs.pidm AS pidm,
               crs.coll_code AS coll_code,
               AVG(CASE
                   WHEN crs.final_grade = 'P' THEN
                    4
                   ELSE
                    crs.grade_quality_points
                   END) AS avg_grade,
               CASE
               WHEN COUNT(CASE
                          WHEN crs.final_grade IS NOT NULL THEN
                           1
                          END) = 0 THEN
                NULL
               ELSE
                SUM(CASE
                    WHEN crs.final_grade IS NOT NULL
                         AND (crs.grade_quality_points >= 2 OR crs.final_grade = 'P') THEN
                     1
                    ELSE
                     0
                    END) / COUNT(CASE
                                 WHEN crs.final_grade IS NOT NULL THEN
                                  1
                                 END)
               END AS p_pct,
               CASE
               WHEN COUNT(CASE
                          WHEN crs.final_grade IS NOT NULL THEN
                           1
                          END) = 0 THEN
                NULL
               ELSE
                SUM(CASE
                    WHEN crs.final_grade IS NOT NULL
                         AND substr(crs.final_grade, 1, 1) = 'W' THEN
                     1
                    ELSE
                     0
                    END) / COUNT(CASE
                                 WHEN crs.final_grade IS NOT NULL THEN
                                  1
                                 END)
               END AS w_pct,
               CASE
               WHEN COUNT(CASE
                          WHEN crs.final_grade IS NOT NULL THEN
                           1
                          END) = 0 THEN
                NULL
               ELSE
                SUM(CASE
                    WHEN crs.final_grade IS NOT NULL
                         AND substr(crs.final_grade, 1, 2) IN ('FN', 'NF') THEN
                     1
                    ELSE
                     0
                    END) / COUNT(CASE
                                 WHEN crs.final_grade IS NOT NULL THEN
                                  1
                                 END)
               END AS fn_pct,
               COUNT(*) AS seat_cnt,
               SUM(crs.grade_adj_quality_points) AS quality_points_earned
          FROM utl_d_aim.szrcrse crs
          JOIN zsaturn.szrlevl l
            ON l.szrlevl_levl_code = crs.levl_code
           AND l.szrlevl_has_awardable_cred = 'Y'
        -- student must be enrolled in dimension for current term
          JOIN (SELECT DISTINCT crse.pidm,
                               crse.coll_code
                 FROM utl_d_aim.szrcrse crse
                WHERE term_code = rec.term_code) req
            ON req.pidm = crs.pidm
           AND req.coll_code = crs.coll_code
         WHERE 1 = 1
           AND crs.group_code = 'STD'
           AND crs.term_code BETWEEN rec.from_term_code AND rec.term_code
         GROUP BY crs.coll_code,
                  crs.pidm) sco -- student current overall
  LEFT JOIN (SELECT crs.pidm AS pidm,
                    crs.coll_code AS coll_code,
                    AVG(CASE
                        WHEN crs.final_grade = 'P' THEN
                         4
                        ELSE
                         crs.grade_quality_points
                        END) AS avg_grade,
                    CASE
                    WHEN COUNT(CASE
                               WHEN crs.final_grade IS NOT NULL THEN
                                1
                               END) = 0 THEN
                     NULL
                    ELSE
                     SUM(CASE
                         WHEN crs.final_grade IS NOT NULL
                              AND (crs.grade_quality_points >= 2 OR crs.final_grade = 'P') THEN
                          1
                         ELSE
                          0
                         END) / COUNT(CASE
                                      WHEN crs.final_grade IS NOT NULL THEN
                                       1
                                      END)
                    END AS p_pct,
                    CASE
                    WHEN COUNT(CASE
                               WHEN crs.final_grade IS NOT NULL THEN
                                1
                               END) = 0 THEN
                     NULL
                    ELSE
                     SUM(CASE
                         WHEN crs.final_grade IS NOT NULL
                              AND substr(crs.final_grade, 1, 1) = 'W' THEN
                          1
                         ELSE
                          0
                         END) / COUNT(CASE
                                      WHEN crs.final_grade IS NOT NULL THEN
                                       1
                                      END)
                    END AS w_pct,
                    CASE
                    WHEN COUNT(CASE
                               WHEN crs.final_grade IS NOT NULL THEN
                                1
                               END) = 0 THEN
                     NULL
                    ELSE
                     SUM(CASE
                         WHEN crs.final_grade IS NOT NULL
                              AND substr(crs.final_grade, 1, 2) IN ('FN', 'NF') THEN
                          1
                         ELSE
                          0
                         END) / COUNT(CASE
                                      WHEN crs.final_grade IS NOT NULL THEN
                                       1
                                      END)
                    END AS fn_pct,
                    SUM(crs.grade_adj_quality_points) AS quality_points_earned
               FROM utl_d_aim.szrcrse crs
               JOIN zsaturn.szrlevl l
                 ON l.szrlevl_levl_code = crs.levl_code
                AND l.szrlevl_has_awardable_cred = 'Y'
             -- student must be enrolled in dimension for current term
               JOIN (SELECT DISTINCT crse.pidm,
                                    crse.coll_code
                      FROM utl_d_aim.szrcrse crse
                     WHERE term_code = rec.term_code) req
                 ON req.pidm = crs.pidm
                AND req.coll_code = crs.coll_code
              WHERE 1 = 1
                AND crs.group_code = 'STD'
                AND crs.term_code < rec.term_code
              GROUP BY crs.coll_code,
                       crs.pidm) sao -- student as of term overall
    ON sao.coll_code = sco.coll_code
   AND sao.pidm = sco.pidm;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
MERGE INTO utl_d_aa.stucollperform t1
USING (SELECT so.pidm,
              so.coll_code,
              rec.term_code AS term_code,
              round(so.avg_grade, 4) AS avg_grade,
              round(so.p_pct, 4) AS p_pct,
              round(so.w_pct, 4) AS w_pct,
              round(so.fn_pct, 4) AS fn_pct,
              round(so.avg_grade_asof_term, 4) AS avg_grade_asof_term,
              round(so.p_pct_asof_term, 4) AS p_pct_asof_term,
              round(so.w_pct_asof_term, 4) AS w_pct_asof_term,
              round(so.fn_pct_asof_term, 4) AS fn_pct_asof_term,
              so.seat_cnt AS seat_cnt,
              round(po.avg_grade, 4) AS avg_grade_peer,
              round(po.p_pct, 4) AS p_pct_peer,
              round(po.w_pct, 4) AS w_pct_peer,
              round(po.fn_pct, 4) AS fn_pct_peer,
              round(po.avg_grade_asof_term, 4) AS avg_grade_asof_term_peer,
              round(po.p_pct_asof_term, 4) AS p_pct_asof_term_peer,
              round(po.w_pct_asof_term, 4) AS w_pct_asof_term_peer,
              round(po.fn_pct_asof_term, 4) AS fn_pct_asof_term_peer,
              po.seat_cnt AS seat_cnt_peer,
              v_etl_date AS activity_date,
              round(so.quality_points, 4) AS quality_points,
              round(so.quality_points_asof_term, 4) AS quality_points_asof_term
         FROM utl_d_aa.stucollperformso_gtt so
         LEFT JOIN utl_d_aa.stucollperformpo_gtt po
           ON po.coll_code = so.coll_code
          AND po.term_code = so.term_code
        WHERE so.term_code = rec.term_code) t2
ON (t1.pidm = t2.pidm AND t1.term_code = t2.term_code AND t1.coll_code = t2.coll_code)
WHEN MATCHED THEN
UPDATE
   SET t1.avg_grade                = t2.avg_grade,
       t1.p_pct                    = t2.p_pct,
       t1.w_pct                    = t2.w_pct,
       t1.fn_pct                   = t2.fn_pct,
       t1.avg_grade_asof_term      = t2.avg_grade_asof_term,
       t1.p_pct_asof_term          = t2.p_pct_asof_term,
       t1.w_pct_asof_term          = t2.w_pct_asof_term,
       t1.fn_pct_asof_term         = t2.fn_pct_asof_term,
       t1.seat_cnt                 = t2.seat_cnt,
       t1.avg_grade_peer           = t2.avg_grade_peer,
       t1.p_pct_peer               = t2.p_pct_peer,
       t1.w_pct_peer               = t2.w_pct_peer,
       t1.fn_pct_peer              = t2.fn_pct_peer,
       t1.avg_grade_asof_term_peer = t2.avg_grade_asof_term_peer,
       t1.p_pct_asof_term_peer     = t2.p_pct_asof_term_peer,
       t1.w_pct_asof_term_peer     = t2.w_pct_asof_term_peer,
       t1.fn_pct_asof_term_peer    = t2.fn_pct_asof_term_peer,
       t1.seat_cnt_peer            = t2.seat_cnt_peer,
       t1.quality_points           = t2.quality_points,
       t1.quality_points_asof_term = t2.quality_points_asof_term,
       t1.activity_date            = v_etl_date
WHEN NOT MATCHED THEN
INSERT
(pidm,
 coll_code,
 term_code,
 avg_grade,
 p_pct,
 w_pct,
 fn_pct,
 avg_grade_asof_term,
 p_pct_asof_term,
 w_pct_asof_term,
 fn_pct_asof_term,
 seat_cnt,
 avg_grade_peer,
 p_pct_peer,
 w_pct_peer,
 fn_pct_peer,
 avg_grade_asof_term_peer,
 p_pct_asof_term_peer,
 w_pct_asof_term_peer,
 fn_pct_asof_term_peer,
 seat_cnt_peer,
 activity_date,
 quality_points,
 quality_points_asof_term)
VALUES
(t2.pidm,
 t2.coll_code,
 t2.term_code,
 t2.avg_grade,
 t2.p_pct,
 t2.w_pct,
 t2.fn_pct,
 t2.avg_grade_asof_term,
 t2.p_pct_asof_term,
 t2.w_pct_asof_term,
 t2.fn_pct_asof_term,
 t2.seat_cnt,
 t2.avg_grade_peer,
 t2.p_pct_peer,
 t2.w_pct_peer,
 t2.fn_pct_peer,
 t2.avg_grade_asof_term_peer,
 t2.p_pct_asof_term_peer,
 t2.w_pct_asof_term_peer,
 t2.fn_pct_asof_term_peer,
 t2.seat_cnt_peer,
 v_etl_date,
 t2.quality_points,
 t2.quality_points_asof_term);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- remove any students NOT currently enrolled [dropped NOT withdraw]
-- do not try to time restrict here because of the way the cursor works only running once a day
DELETE FROM utl_d_aa.stucollperform sp
 WHERE sp.term_code = rec.term_code
   AND NOT EXISTS (SELECT 1
          FROM utl_d_aim.szrcrse crse
         WHERE crse.term_code = sp.term_code
           AND crse.pidm = sp.pidm
           AND crse.coll_code = sp.coll_code);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'DELETE - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
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
-- Clear GTT tables on error
utl_d_aa.truncate_table(v_table_name => 'stucollperformpo_gtt');
utl_d_aa.truncate_table(v_table_name => 'stucollperformso_gtt');
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
/*--------------------------------------------CHANGE LOG----------------------------------------
VERSION    DATE        USERNAME       UPDATES
---        03-27-2020  wgriffith2     --Initial release
--         03-08-2021  wgriffith2     --Adding quality_points and quality_points_asof_term
---        06-30-2022  wgriffith2     --refreshes do not happen until the subterm is completed
---        08-24-2022  wgriffith2     --refreshes must happen once the subterm starts! I fixed the seat count field to not start counting until the term has completed
---        09-09-2022  wgriffith2     --reverting back to the version prior to 20220630 to fix issues report in TKT2555560; optimization - only returning rows when active enrollment on the particular dimension
---        01-23-2025  wgriffith2     --fixing issues with pass/fail courses producing 0s; quality points show 0 when course is passed.
---        04-04-2025  wgriffith2     --STUCOLLPERFORMSO_GTT was set to "on commit delete rows;" and should have been "on commit preserve rows;"
---        07-01-2025  wgriffith2     --Enhanced by implementing batch processing to handle large data volumes efficiently;  Added logic to ensure p_pct, w_pct, fn_pct are NULL if no non-null final grades exist in the group.
------------------------------------------------------------------------------------------------*/
END etl_aa_stucollperform_refresh;

PROCEDURE etl_aa_stucrseperform_refresh(jobnumber NUMBER,processid VARCHAR2, processname VARCHAR2) IS
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
v_proc        VARCHAR2(100) := 'etl_aa_stucrseperform_refresh';
CURSOR c_terms IS
SELECT terms.term_code AS term_code,
       to_char(terms.term_code - 300) AS from_term_code
  FROM zbtm.terms_by_group_v terms
 WHERE terms.term_code IN (SELECT term_code
                             FROM zbtm.terms_by_group_v terms
                            WHERE group_code IN ('STD')
                              AND semester <> 'WIN'
                              AND SYSDATE BETWEEN start_date - 7 AND end_date + 7)
   AND EXISTS (SELECT 1 FROM utl_d_aa.stucrseperform scp HAVING MAX(trunc(scp.activity_date)) <> trunc(SYSDATE)) -- Check if data has already been loaded today
UNION
SELECT DISTINCT shrtckg_term_code AS term_code,
                to_char(shrtckg_term_code - 300) AS from_term_code
  FROM saturn.shrtckg
  JOIN (SELECT group_code,
               term_code
          FROM zbtm.terms_by_group_v t
         WHERE 1 = 1
           AND t.group_code = 'STD') fg
    ON fg.term_code = shrtckg_term_code
 WHERE 1 = 1
   AND shrtckg_final_grde_chg_date > SYSDATE - 1 -- check for any grade changes
   AND shrtckg_term_code IN (SELECT terms.term_code
                               FROM zbtm.terms_by_group_v terms
                              WHERE terms.group_code = 'STD'
                                AND (SYSDATE BETWEEN terms.start_date - 21 AND terms.end_date + (365 * 1))
                                AND terms.semester <> 'WIN')
   AND EXISTS (SELECT 1 FROM utl_d_aa.stucrseperform scp HAVING MAX(trunc(scp.activity_date)) <> trunc(SYSDATE)) -- Check if data has already been loaded today
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
utl_d_aa.truncate_table(v_table_name => 'stucrseperformpo_gtt');
v_count   := 0; -- reset count
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
INSERT /*+ APPEND */
INTO utl_d_aa.stucrseperformpo_gtt
(course,
 term_code,
 avg_grade,
 p_pct,
 w_pct,
 fn_pct,
 avg_grade_asof_term,
 p_pct_asof_term,
 w_pct_asof_term,
 fn_pct_asof_term,
 seat_cnt)
SELECT sco.course    AS course,
       rec.term_code AS term_code,
       sco.avg_grade AS avg_grade,
       sco.p_pct     AS p_pct,
       sco.w_pct     AS w_pct,
       sco.fn_pct    AS fn_pct,
       sao.avg_grade AS avg_grade_asof_term,
       sao.p_pct     AS p_pct_asof_term,
       sao.w_pct     AS w_pct_asof_term,
       sao.fn_pct    AS fn_pct_asof_term,
       sco.seat_cnt  AS seat_cnt
  FROM (SELECT crs.subj || crs.numb AS course,
               AVG(CASE
                   WHEN crs.final_grade = 'P' THEN
                    4
                   ELSE
                    crs.grade_quality_points
                   END) AS avg_grade,
               CASE
               WHEN COUNT(CASE
                          WHEN crs.final_grade IS NOT NULL THEN
                           1
                          END) = 0 THEN
                NULL
               ELSE
                SUM(CASE
                    WHEN crs.final_grade IS NOT NULL
                         AND (crs.grade_quality_points >= 2 OR crs.final_grade = 'P') THEN
                     1
                    ELSE
                     0
                    END) / COUNT(CASE
                                 WHEN crs.final_grade IS NOT NULL THEN
                                  1
                                 END)
               END AS p_pct,
               CASE
               WHEN COUNT(CASE
                          WHEN crs.final_grade IS NOT NULL THEN
                           1
                          END) = 0 THEN
                NULL
               ELSE
                SUM(CASE
                    WHEN crs.final_grade IS NOT NULL
                         AND substr(crs.final_grade, 1, 1) = 'W' THEN
                     1
                    ELSE
                     0
                    END) / COUNT(CASE
                                 WHEN crs.final_grade IS NOT NULL THEN
                                  1
                                 END)
               END AS w_pct,
               CASE
               WHEN COUNT(CASE
                          WHEN crs.final_grade IS NOT NULL THEN
                           1
                          END) = 0 THEN
                NULL
               ELSE
                SUM(CASE
                    WHEN crs.final_grade IS NOT NULL
                         AND substr(crs.final_grade, 1, 2) IN ('FN', 'NF') THEN
                     1
                    ELSE
                     0
                    END) / COUNT(CASE
                                 WHEN crs.final_grade IS NOT NULL THEN
                                  1
                                 END)
               END AS fn_pct,
               COUNT(*) AS seat_cnt
          FROM utl_d_aim.szrcrse crs /*+ INDEX(crs SZRCRSE_INDX3) */
          JOIN zsaturn.szrlevl l
            ON l.szrlevl_levl_code = crs.levl_code
           AND l.szrlevl_has_awardable_cred = 'Y'
         WHERE 1 = 1
           AND crs.group_code = 'STD'
           AND crs.term_code BETWEEN rec.from_term_code AND rec.term_code
           AND EXISTS (SELECT 1
                  FROM utl_d_aim.szrcrse crse
                 WHERE crse.term_code = rec.term_code
                   AND crse.subj || crse.numb = crs.subj || crs.numb) -- must exist in term
         GROUP BY crs.subj || crs.numb) sco -- student current overall
  LEFT JOIN (SELECT crs.subj || crs.numb AS course,
                    AVG(CASE
                        WHEN crs.final_grade = 'P' THEN
                         4
                        ELSE
                         crs.grade_quality_points
                        END) AS avg_grade,
                    CASE
                    WHEN COUNT(CASE
                               WHEN crs.final_grade IS NOT NULL THEN
                                1
                               END) = 0 THEN
                     NULL
                    ELSE
                     SUM(CASE
                         WHEN crs.final_grade IS NOT NULL
                              AND (crs.grade_quality_points >= 2 OR crs.final_grade = 'P') THEN
                          1
                         ELSE
                          0
                         END) / COUNT(CASE
                                      WHEN crs.final_grade IS NOT NULL THEN
                                       1
                                      END)
                    END AS p_pct,
                    CASE
                    WHEN COUNT(CASE
                               WHEN crs.final_grade IS NOT NULL THEN
                                1
                               END) = 0 THEN
                     NULL
                    ELSE
                     SUM(CASE
                         WHEN crs.final_grade IS NOT NULL
                              AND substr(crs.final_grade, 1, 1) = 'W' THEN
                          1
                         ELSE
                          0
                         END) / COUNT(CASE
                                      WHEN crs.final_grade IS NOT NULL THEN
                                       1
                                      END)
                    END AS w_pct,
                    CASE
                    WHEN COUNT(CASE
                               WHEN crs.final_grade IS NOT NULL THEN
                                1
                               END) = 0 THEN
                     NULL
                    ELSE
                     SUM(CASE
                         WHEN crs.final_grade IS NOT NULL
                              AND substr(crs.final_grade, 1, 2) IN ('FN', 'NF') THEN
                          1
                         ELSE
                          0
                         END) / COUNT(CASE
                                      WHEN crs.final_grade IS NOT NULL THEN
                                       1
                                      END)
                    END AS fn_pct
               FROM utl_d_aim.szrcrse crs
               JOIN zsaturn.szrlevl l
                 ON l.szrlevl_levl_code = crs.levl_code
                AND l.szrlevl_has_awardable_cred = 'Y'
              WHERE 1 = 1
                AND crs.group_code = 'STD'
                AND crs.term_code < rec.term_code
              GROUP BY crs.subj || crs.numb) sao -- student as of term overall
    ON sao.course = sco.course;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
MERGE /*+ USE_NL(t2) INDEX(t2 stucrseperformpo_gtt_idx1) */
INTO utl_d_aa.stucrseperform t1
USING (SELECT po.course,
              rec.term_code AS term_code,
              round(po.avg_grade, 4) AS avg_grade_peer,
              round(po.p_pct, 4) AS p_pct_peer,
              round(po.w_pct, 4) AS w_pct_peer,
              round(po.fn_pct, 4) AS fn_pct_peer,
              round(po.avg_grade_asof_term, 4) AS avg_grade_asof_term_peer,
              round(po.p_pct_asof_term, 4) AS p_pct_asof_term_peer,
              round(po.w_pct_asof_term, 4) AS w_pct_asof_term_peer,
              round(po.fn_pct_asof_term, 4) AS fn_pct_asof_term_peer,
              po.seat_cnt AS seat_cnt_peer,
              v_etl_date AS activity_date
         FROM utl_d_aa.stucrseperformpo_gtt po
        WHERE po.term_code = rec.term_code) t2
ON (t1.term_code = t2.term_code AND t1.course = t2.course)
WHEN MATCHED THEN
UPDATE
   SET t1.avg_grade_peer           = t2.avg_grade_peer,
       t1.p_pct_peer               = t2.p_pct_peer,
       t1.w_pct_peer               = t2.w_pct_peer,
       t1.fn_pct_peer              = t2.fn_pct_peer,
       t1.avg_grade_asof_term_peer = t2.avg_grade_asof_term_peer,
       t1.p_pct_asof_term_peer     = t2.p_pct_asof_term_peer,
       t1.w_pct_asof_term_peer     = t2.w_pct_asof_term_peer,
       t1.fn_pct_asof_term_peer    = t2.fn_pct_asof_term_peer,
       t1.seat_cnt_peer            = t2.seat_cnt_peer,
       t1.activity_date            = t2.activity_date
WHEN NOT MATCHED THEN
INSERT
VALUES
(t2.course,
 t2.term_code,
 t2.avg_grade_peer,
 t2.p_pct_peer,
 t2.w_pct_peer,
 t2.fn_pct_peer,
 t2.avg_grade_asof_term_peer,
 t2.p_pct_asof_term_peer,
 t2.w_pct_asof_term_peer,
 t2.fn_pct_asof_term_peer,
 t2.seat_cnt_peer,
 v_etl_date);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- remove any students NOT currently enrolled [dropped NOT withdraw]
-- **do not try to time restrict here** because of the way the cursor works only running once a day
DELETE FROM utl_d_aa.stucrseperform tgt
 WHERE tgt.term_code = rec.term_code
   AND NOT EXISTS (SELECT 1
          FROM utl_d_aim.szrcrse crse
         WHERE crse.term_code = tgt.term_code
           AND crse.subj || crse.numb = tgt.course);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'DELETE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
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
-- Clear GTT tables on error
utl_d_aa.truncate_table(v_table_name => 'stucrseperformpo_gtt');
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
/*--------------------------------------------CHANGE LOG----------------------------------------
VERSION    DATE        USERNAME       UPDATES
---        03-27-2020  wgriffith2     --Initial release
--         03-08-2021  wgriffith2     --Adding quality_points and quality_points_asof_term
---        06-30-2022  wgriffith2     --refreshes do not happen until the subterm is completed
---        08-24-2022  wgriffith2     --refreshes must happen once the subterm starts! I fixed the seat count field to not start counting until the term has completed
---        09-09-2022  wgriffith2     --reverting back to the version prior to 20220630 to fix issues report in TKT2555560; optimization - only returning rows when active enrollment on the particular dimension
---        01-23-2025  wgriffith2     --fixing issues with pass/fail courses producing 0s; quality points show 0 when course is passed.
---        07-01-2025  wgriffith2     --Enhanced by implementing batch processing to handle large data volumes efficiently;  Added logic to ensure p_pct, w_pct, fn_pct are NULL if no non-null final grades exist in the group.
---        07-09-2025  wgriffith2     --Rebuilding to be only the course data and not directly student -> course. the unique student / course pairings were too rare to be useful in any ML models and it was causing problems with runaways
------------------------------------------------------------------------------------------------*/
END etl_aa_stucrseperform_refresh; --

PROCEDURE etl_aa_stuprofperform_refresh(jobnumber NUMBER,processid VARCHAR2, processname VARCHAR2) IS
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
v_proc        VARCHAR2(100) := 'etl_aa_stuprofperform_refresh';
CURSOR c_terms IS
SELECT terms.term_code AS term_code,
       to_char(terms.term_code - 300) AS from_term_code
  FROM zbtm.terms_by_group_v terms
 WHERE terms.term_code IN (SELECT term_code
                             FROM zbtm.terms_by_group_v terms
                            WHERE group_code IN ('STD')
                              AND semester <> 'WIN'
                              AND SYSDATE BETWEEN start_date - 7 AND end_date + 7)
   AND EXISTS (SELECT 1 FROM utl_d_aa.stuprofperform scp HAVING MAX(trunc(scp.activity_date)) <> trunc(SYSDATE)) -- Check if data has already been loaded today
UNION
SELECT DISTINCT shrtckg_term_code AS term_code,
                to_char(shrtckg_term_code - 300) AS from_term_code
  FROM saturn.shrtckg
  JOIN (SELECT group_code,
               term_code
          FROM zbtm.terms_by_group_v t
         WHERE 1 = 1
           AND t.group_code = 'STD') fg
    ON fg.term_code = shrtckg_term_code
 WHERE 1 = 1
   AND shrtckg_final_grde_chg_date > SYSDATE - 1 -- check for any grade changes
   AND shrtckg_term_code IN (SELECT terms.term_code
                               FROM zbtm.terms_by_group_v terms
                              WHERE terms.group_code = 'STD'
                                AND (SYSDATE BETWEEN terms.start_date - 21 AND terms.end_date + (365 * 1))
                                AND terms.semester <> 'WIN')
   AND EXISTS (SELECT 1 FROM utl_d_aa.stuprofperform scp HAVING MAX(trunc(scp.activity_date)) <> trunc(SYSDATE)) -- Check if data has already been loaded today
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
-- Clear GTT tables before processing
utl_d_aa.truncate_table(v_table_name => 'stuprofperformpo_gtt');
v_count   := 0; -- reset count
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
INSERT INTO utl_d_aa.stuprofperformpo_gtt
(prof_pidm,
 term_code,
 avg_grade,
 p_pct,
 w_pct,
 fn_pct,
 avg_grade_asof_term,
 p_pct_asof_term,
 w_pct_asof_term,
 fn_pct_asof_term,
 seat_cnt)
SELECT sco.prof_pidm,
       rec.term_code AS term_code,
       sco.avg_grade,
       sco.p_pct,
       sco.w_pct,
       sco.fn_pct,
       sao.avg_grade,
       sao.p_pct     AS p_pct_asof_term,
       sao.w_pct     AS w_pct_asof_term,
       sao.fn_pct    AS fn_pct_asof_term,
       sco.seat_cnt
  FROM (SELECT prof_pidm,
               avg_grade,
               p_pct,
               w_pct,
               fn_pct,
               seat_cnt
          FROM (SELECT crs.faculty_pidm AS prof_pidm,
                       AVG(CASE
                           WHEN crs.final_grade = 'P' THEN
                            4
                           ELSE
                            crs.grade_quality_points
                           END) AS avg_grade,
                       CASE
                       WHEN COUNT(CASE
                                  WHEN crs.final_grade IS NOT NULL THEN
                                   1
                                  END) = 0 THEN
                        NULL
                       ELSE
                        SUM(CASE
                            WHEN crs.final_grade IS NOT NULL
                                 AND (crs.grade_quality_points >= 2 OR crs.final_grade = 'P') THEN
                             1
                            ELSE
                             0
                            END) / COUNT(CASE
                                         WHEN crs.final_grade IS NOT NULL THEN
                                          1
                                         END)
                       END AS p_pct,
                       CASE
                       WHEN COUNT(CASE
                                  WHEN crs.final_grade IS NOT NULL THEN
                                   1
                                  END) = 0 THEN
                        NULL
                       ELSE
                        SUM(CASE
                            WHEN crs.final_grade IS NOT NULL
                                 AND substr(crs.final_grade, 1, 1) = 'W' THEN
                             1
                            ELSE
                             0
                            END) / COUNT(CASE
                                         WHEN crs.final_grade IS NOT NULL THEN
                                          1
                                         END)
                       END AS w_pct,
                       CASE
                       WHEN COUNT(CASE
                                  WHEN crs.final_grade IS NOT NULL THEN
                                   1
                                  END) = 0 THEN
                        NULL
                       ELSE
                        SUM(CASE
                            WHEN crs.final_grade IS NOT NULL
                                 AND substr(crs.final_grade, 1, 2) IN ('FN', 'NF') THEN
                             1
                            ELSE
                             0
                            END) / COUNT(CASE
                                         WHEN crs.final_grade IS NOT NULL THEN
                                          1
                                         END)
                       END AS fn_pct,
                       COUNT(DISTINCT crs.term_code || crs.crn || crs.pidm) AS seat_cnt
                  FROM utl_d_aim.szrcrse crs
                  JOIN zsaturn.szrlevl l
                    ON l.szrlevl_levl_code = crs.levl_code
                   AND l.szrlevl_has_awardable_cred = 'Y'
                 WHERE 1 = 1
                   AND crs.group_code = 'STD'
                   AND crs.term_code BETWEEN rec.from_term_code AND rec.term_code
                   AND crs.faculty_pidm IN (SELECT DISTINCT crse.faculty_pidm FROM utl_d_aim.szrcrse crse WHERE crse.term_code = rec.term_code) -- must be teaching in term
                 GROUP BY crs.faculty_pidm)) sco
  LEFT JOIN (SELECT crs.faculty_pidm AS prof_pidm,
                    AVG(CASE
                        WHEN crs.final_grade = 'P' THEN
                         4
                        ELSE
                         crs.grade_quality_points
                        END) AS avg_grade,
                    CASE
                    WHEN COUNT(CASE
                               WHEN crs.final_grade IS NOT NULL THEN
                                1
                               END) = 0 THEN
                     NULL
                    ELSE
                     SUM(CASE
                         WHEN crs.final_grade IS NOT NULL
                              AND (crs.grade_quality_points >= 2 OR crs.final_grade = 'P') THEN
                          1
                         ELSE
                          0
                         END) / COUNT(CASE
                                      WHEN crs.final_grade IS NOT NULL THEN
                                       1
                                      END)
                    END AS p_pct,
                    CASE
                    WHEN COUNT(CASE
                               WHEN crs.final_grade IS NOT NULL THEN
                                1
                               END) = 0 THEN
                     NULL
                    ELSE
                     SUM(CASE
                         WHEN crs.final_grade IS NOT NULL
                              AND substr(crs.final_grade, 1, 1) = 'W' THEN
                          1
                         ELSE
                          0
                         END) / COUNT(CASE
                                      WHEN crs.final_grade IS NOT NULL THEN
                                       1
                                      END)
                    END AS w_pct,
                    CASE
                    WHEN COUNT(CASE
                               WHEN crs.final_grade IS NOT NULL THEN
                                1
                               END) = 0 THEN
                     NULL
                    ELSE
                     SUM(CASE
                         WHEN crs.final_grade IS NOT NULL
                              AND substr(crs.final_grade, 1, 2) IN ('FN', 'NF') THEN
                          1
                         ELSE
                          0
                         END) / COUNT(CASE
                                      WHEN crs.final_grade IS NOT NULL THEN
                                       1
                                      END)
                    END AS fn_pct
               FROM utl_d_aim.szrcrse crs
               JOIN zsaturn.szrlevl l
                 ON l.szrlevl_levl_code = crs.levl_code
                AND l.szrlevl_has_awardable_cred = 'Y'
              WHERE crs.group_code = 'STD'
                AND crs.term_code < rec.term_code
                AND crs.faculty_pidm IS NOT NULL
              GROUP BY crs.faculty_pidm) sao -- as of term overall
    ON sao.prof_pidm = sco.prof_pidm;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
MERGE INTO utl_d_aa.stuprofperform t1
USING (SELECT po.prof_pidm,
              rec.term_code AS term_code,
              round(po.avg_grade, 4) AS avg_grade_peer,
              round(po.p_pct, 4) AS p_pct_peer,
              round(po.w_pct, 4) AS w_pct_peer,
              round(po.fn_pct, 4) AS fn_pct_peer,
              round(po.avg_grade_asof_term, 4) AS avg_grade_asof_term_peer,
              round(po.p_pct_asof_term, 4) AS p_pct_asof_term_peer,
              round(po.w_pct_asof_term, 4) AS w_pct_asof_term_peer,
              round(po.fn_pct_asof_term, 4) AS fn_pct_asof_term_peer,
              po.seat_cnt AS seat_cnt_peer,
              v_etl_date AS activity_date
         FROM utl_d_aa.stuprofperformpo_gtt po
        WHERE po.term_code = rec.term_code) t2
ON (t1.term_code = t2.term_code AND t1.prof_pidm = t2.prof_pidm)
WHEN MATCHED THEN
UPDATE
   SET t1.avg_grade_peer           = t2.avg_grade_peer,
       t1.p_pct_peer               = t2.p_pct_peer,
       t1.w_pct_peer               = t2.w_pct_peer,
       t1.fn_pct_peer              = t2.fn_pct_peer,
       t1.avg_grade_asof_term_peer = t2.avg_grade_asof_term_peer,
       t1.p_pct_asof_term_peer     = t2.p_pct_asof_term_peer,
       t1.w_pct_asof_term_peer     = t2.w_pct_asof_term_peer,
       t1.fn_pct_asof_term_peer    = t2.fn_pct_asof_term_peer,
       t1.seat_cnt_peer            = t2.seat_cnt_peer,
       t1.activity_date            = t2.activity_date
WHEN NOT MATCHED THEN
INSERT
VALUES
(t2.prof_pidm,
 t2.term_code,
 t2.avg_grade_peer,
 t2.p_pct_peer,
 t2.w_pct_peer,
 t2.fn_pct_peer,
 t2.avg_grade_asof_term_peer,
 t2.p_pct_asof_term_peer,
 t2.w_pct_asof_term_peer,
 t2.fn_pct_asof_term_peer,
 t2.seat_cnt_peer,
 v_etl_date);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- remove any students NOT currently enrolled [dropped NOT withdraw]
-- do not try to time restrict here because of the way the cursor works only running once a day
DELETE FROM utl_d_aa.stuprofperform sp
 WHERE sp.term_code = rec.term_code
   AND NOT EXISTS (SELECT 1
          FROM utl_d_aim.szrcrse crse
         WHERE crse.term_code = sp.term_code
           AND crse.faculty_pidm = sp.prof_pidm);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'DELETE - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
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
-- Clear GTT tables on error
utl_d_aa.truncate_table(v_table_name => 'stuprofperformpo_gtt');
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
/*--------------------------------------------CHANGE LOG----------------------------------------
VERSION    DATE        USERNAME       UPDATES
---        03-27-2020  wgriffith2     --Initial release
--         03-08-2021  wgriffith2     --Adding quality_points and quality_points_asof_term
---        06-30-2022  wgriffith2     --refreshes do not happen until the subterm is completed
---        08-24-2022  wgriffith2     --refreshes must happen once the subterm starts! I fixed the seat count field to not start counting until the term has completed
---        09-09-2022  wgriffith2     --reverting back to the version prior to 20220630 to fix issues report in TKT2555560; optimization - only returning rows when active enrollment on the particular dimension
---        01-23-2025  wgriffith2     --fixing issues with pass/fail courses producing 0s; quality points show 0 when course is passed.
---        07-01-2025  wgriffith2     --Enhanced by implementing batch processing to handle large data volumes efficiently;  Added logic to ensure p_pct, w_pct, fn_pct are NULL if no non-null final grades exist in the group.
---        07-03-2025  wgriffith2     --Rebuilding to be only the instructors data and not directly student -> instructor. the unique student / instructor pairings were too rare to be useful in any ML models
------------------------------------------------------------------------------------------------*/
END etl_aa_stuprofperform_refresh; --

PROCEDURE etl_aa_stusubjperform_refresh(jobnumber NUMBER,processid VARCHAR2, processname VARCHAR2) IS
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
v_proc        VARCHAR2(100) := 'etl_aa_stusubjperform_refresh';
CURSOR c_terms IS
SELECT terms.term_code AS term_code,
       to_char(terms.term_code - 300) AS from_term_code
  FROM zbtm.terms_by_group_v terms
 WHERE terms.term_code IN (SELECT term_code
                             FROM zbtm.terms_by_group_v terms
                            WHERE group_code IN ('STD')
                              AND semester <> 'WIN'
                              AND SYSDATE BETWEEN start_date - 7 AND end_date + 7)
   AND EXISTS (SELECT 1 FROM utl_d_aa.stusubjperform scp HAVING MAX(trunc(scp.activity_date)) <> trunc(SYSDATE)) -- Check if data has already been loaded today
UNION
SELECT DISTINCT shrtckg_term_code AS term_code,
                to_char(shrtckg_term_code - 300) AS from_term_code
  FROM saturn.shrtckg
  JOIN (SELECT group_code,
               term_code
          FROM zbtm.terms_by_group_v t
         WHERE 1 = 1
           AND t.group_code = 'STD') fg
    ON fg.term_code = shrtckg_term_code
 WHERE 1 = 1
   AND shrtckg_final_grde_chg_date > SYSDATE - 1 -- check for any grade changes
   AND shrtckg_term_code IN (SELECT terms.term_code
                               FROM zbtm.terms_by_group_v terms
                              WHERE terms.group_code = 'STD'
                                AND (SYSDATE BETWEEN terms.start_date - 21 AND terms.end_date + (365 * 1))
                                AND terms.semester <> 'WIN')
   AND EXISTS (SELECT 1 FROM utl_d_aa.stusubjperform scp HAVING MAX(trunc(scp.activity_date)) <> trunc(SYSDATE)) -- Check if data has already been loaded today
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
utl_d_aa.truncate_table(v_table_name => 'stusubjperformpo_gtt');
utl_d_aa.truncate_table(v_table_name => 'stusubjperformso_gtt');
v_count   := 0; -- reset count
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
INSERT INTO utl_d_aa.stusubjperformpo_gtt
(subj_code,
 term_code,
 avg_grade,
 p_pct,
 w_pct,
 fn_pct,
 avg_grade_asof_term,
 p_pct_asof_term,
 w_pct_asof_term,
 fn_pct_asof_term,
 seat_cnt)
SELECT sco.subj_code AS subj_code,
       rec.term_code AS term_code,
       sco.avg_grade AS avg_grade,
       sco.p_pct     AS p_pct,
       sco.w_pct     AS w_pct,
       sco.fn_pct    AS fn_pct,
       sao.avg_grade AS avg_grade_asof_term,
       sao.p_pct     AS p_pct_asof_term,
       sao.w_pct     AS w_pct_asof_term,
       sao.fn_pct    AS fn_pct_asof_term,
       sco.seat_cnt  AS seat_cnt
  FROM (SELECT crs.subj AS subj_code,
               AVG(CASE
                   WHEN crs.final_grade = 'P' THEN
                    4
                   ELSE
                    crs.grade_quality_points
                   END) AS avg_grade,
               CASE
               WHEN COUNT(CASE
                          WHEN crs.final_grade IS NOT NULL THEN
                           1
                          END) = 0 THEN
                NULL
               ELSE
                SUM(CASE
                    WHEN crs.final_grade IS NOT NULL
                         AND (crs.grade_quality_points >= 2 OR crs.final_grade = 'P') THEN
                     1
                    ELSE
                     0
                    END) / COUNT(CASE
                                 WHEN crs.final_grade IS NOT NULL THEN
                                  1
                                 END)
               END AS p_pct,
               CASE
               WHEN COUNT(CASE
                          WHEN crs.final_grade IS NOT NULL THEN
                           1
                          END) = 0 THEN
                NULL
               ELSE
                SUM(CASE
                    WHEN crs.final_grade IS NOT NULL
                         AND substr(crs.final_grade, 1, 1) = 'W' THEN
                     1
                    ELSE
                     0
                    END) / COUNT(CASE
                                 WHEN crs.final_grade IS NOT NULL THEN
                                  1
                                 END)
               END AS w_pct,
               CASE
               WHEN COUNT(CASE
                          WHEN crs.final_grade IS NOT NULL THEN
                           1
                          END) = 0 THEN
                NULL
               ELSE
                SUM(CASE
                    WHEN crs.final_grade IS NOT NULL
                         AND substr(crs.final_grade, 1, 2) IN ('FN', 'NF') THEN
                     1
                    ELSE
                     0
                    END) / COUNT(CASE
                                 WHEN crs.final_grade IS NOT NULL THEN
                                  1
                                 END)
               END AS fn_pct,
               COUNT(*) AS seat_cnt
          FROM utl_d_aim.szrcrse crs
          JOIN zsaturn.szrlevl l
            ON l.szrlevl_levl_code = crs.levl_code
           AND l.szrlevl_has_awardable_cred = 'Y'
         WHERE 1 = 1
           AND crs.group_code = 'STD'
           AND crs.term_code BETWEEN rec.from_term_code AND rec.term_code
         GROUP BY crs.subj) sco -- student current overall
  LEFT JOIN (SELECT crs.subj AS subj_code,
                    AVG(CASE
                        WHEN crs.final_grade = 'P' THEN
                         4
                        ELSE
                         crs.grade_quality_points
                        END) AS avg_grade,
                    CASE
                    WHEN COUNT(CASE
                               WHEN crs.final_grade IS NOT NULL THEN
                                1
                               END) = 0 THEN
                     NULL
                    ELSE
                     SUM(CASE
                         WHEN crs.final_grade IS NOT NULL
                              AND (crs.grade_quality_points >= 2 OR crs.final_grade = 'P') THEN
                          1
                         ELSE
                          0
                         END) / COUNT(CASE
                                      WHEN crs.final_grade IS NOT NULL THEN
                                       1
                                      END)
                    END AS p_pct,
                    CASE
                    WHEN COUNT(CASE
                               WHEN crs.final_grade IS NOT NULL THEN
                                1
                               END) = 0 THEN
                     NULL
                    ELSE
                     SUM(CASE
                         WHEN crs.final_grade IS NOT NULL
                              AND substr(crs.final_grade, 1, 1) = 'W' THEN
                          1
                         ELSE
                          0
                         END) / COUNT(CASE
                                      WHEN crs.final_grade IS NOT NULL THEN
                                       1
                                      END)
                    END AS w_pct,
                    CASE
                    WHEN COUNT(CASE
                               WHEN crs.final_grade IS NOT NULL THEN
                                1
                               END) = 0 THEN
                     NULL
                    ELSE
                     SUM(CASE
                         WHEN crs.final_grade IS NOT NULL
                              AND substr(crs.final_grade, 1, 2) IN ('FN', 'NF') THEN
                          1
                         ELSE
                          0
                         END) / COUNT(CASE
                                      WHEN crs.final_grade IS NOT NULL THEN
                                       1
                                      END)
                    END AS fn_pct
               FROM utl_d_aim.szrcrse crs
               JOIN zsaturn.szrlevl l
                 ON l.szrlevl_levl_code = crs.levl_code
                AND l.szrlevl_has_awardable_cred = 'Y'
              WHERE 1 = 1
                AND crs.group_code = 'STD'
                AND crs.term_code < rec.term_code
              GROUP BY crs.subj) sao -- student as of term overall
    ON sao.subj_code = sco.subj_code;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
INSERT INTO utl_d_aa.stusubjperformso_gtt
(pidm,
 subj_code,
 term_code,
 avg_grade,
 p_pct,
 w_pct,
 fn_pct,
 avg_grade_asof_term,
 p_pct_asof_term,
 w_pct_asof_term,
 fn_pct_asof_term,
 seat_cnt,
 quality_points,
 quality_points_asof_term)
SELECT sco.pidm                  AS pidm,
       sco.subj_code             AS subj_code,
       rec.term_code             AS term_code,
       sco.avg_grade             AS avg_grade,
       sco.p_pct                 AS p_pct,
       sco.w_pct                 AS w_pct,
       sco.fn_pct                AS fn_pct,
       sao.avg_grade             AS avg_grade_asof_term,
       sao.p_pct                 AS p_pct_asof_term,
       sao.w_pct                 AS w_pct_asof_term,
       sao.fn_pct                AS fn_pct,
       sco.seat_cnt              AS seat_cnt,
       sco.quality_points_earned,
       sao.quality_points_earned -- _asof_term
  FROM (SELECT crs.pidm AS pidm,
               crs.subj AS subj_code,
               AVG(CASE
                   WHEN crs.final_grade = 'P' THEN
                    4
                   ELSE
                    crs.grade_quality_points
                   END) AS avg_grade,
               CASE
               WHEN COUNT(CASE
                          WHEN crs.final_grade IS NOT NULL THEN
                           1
                          END) = 0 THEN
                NULL
               ELSE
                SUM(CASE
                    WHEN crs.final_grade IS NOT NULL
                         AND (crs.grade_quality_points >= 2 OR crs.final_grade = 'P') THEN
                     1
                    ELSE
                     0
                    END) / COUNT(CASE
                                 WHEN crs.final_grade IS NOT NULL THEN
                                  1
                                 END)
               END AS p_pct,
               CASE
               WHEN COUNT(CASE
                          WHEN crs.final_grade IS NOT NULL THEN
                           1
                          END) = 0 THEN
                NULL
               ELSE
                SUM(CASE
                    WHEN crs.final_grade IS NOT NULL
                         AND substr(crs.final_grade, 1, 1) = 'W' THEN
                     1
                    ELSE
                     0
                    END) / COUNT(CASE
                                 WHEN crs.final_grade IS NOT NULL THEN
                                  1
                                 END)
               END AS w_pct,
               CASE
               WHEN COUNT(CASE
                          WHEN crs.final_grade IS NOT NULL THEN
                           1
                          END) = 0 THEN
                NULL
               ELSE
                SUM(CASE
                    WHEN crs.final_grade IS NOT NULL
                         AND substr(crs.final_grade, 1, 2) IN ('FN', 'NF') THEN
                     1
                    ELSE
                     0
                    END) / COUNT(CASE
                                 WHEN crs.final_grade IS NOT NULL THEN
                                  1
                                 END)
               END AS fn_pct,
               COUNT(*) AS seat_cnt,
               SUM(crs.grade_adj_quality_points) AS quality_points_earned
          FROM utl_d_aim.szrcrse crs
          JOIN zsaturn.szrlevl l
            ON l.szrlevl_levl_code = crs.levl_code
           AND l.szrlevl_has_awardable_cred = 'Y'
        -- student must be enrolled in dimension for current term
          JOIN (SELECT DISTINCT crse.pidm,
                               crse.subj
                 FROM utl_d_aim.szrcrse crse
                WHERE term_code = rec.term_code) req
            ON req.pidm = crs.pidm
           AND req.subj = crs.subj
         WHERE 1 = 1
           AND crs.group_code = 'STD'
           AND crs.term_code BETWEEN rec.from_term_code AND rec.term_code
         GROUP BY crs.subj,
                  crs.pidm) sco -- student current overall
  LEFT JOIN (SELECT crs.pidm AS pidm,
                    crs.subj AS subj_code,
                    AVG(CASE
                        WHEN crs.final_grade = 'P' THEN
                         4
                        ELSE
                         crs.grade_quality_points
                        END) AS avg_grade,
                    CASE
                    WHEN COUNT(CASE
                               WHEN crs.final_grade IS NOT NULL THEN
                                1
                               END) = 0 THEN
                     NULL
                    ELSE
                     SUM(CASE
                         WHEN crs.final_grade IS NOT NULL
                              AND (crs.grade_quality_points >= 2 OR crs.final_grade = 'P') THEN
                          1
                         ELSE
                          0
                         END) / COUNT(CASE
                                      WHEN crs.final_grade IS NOT NULL THEN
                                       1
                                      END)
                    END AS p_pct,
                    CASE
                    WHEN COUNT(CASE
                               WHEN crs.final_grade IS NOT NULL THEN
                                1
                               END) = 0 THEN
                     NULL
                    ELSE
                     SUM(CASE
                         WHEN crs.final_grade IS NOT NULL
                              AND substr(crs.final_grade, 1, 1) = 'W' THEN
                          1
                         ELSE
                          0
                         END) / COUNT(CASE
                                      WHEN crs.final_grade IS NOT NULL THEN
                                       1
                                      END)
                    END AS w_pct,
                    CASE
                    WHEN COUNT(CASE
                               WHEN crs.final_grade IS NOT NULL THEN
                                1
                               END) = 0 THEN
                     NULL
                    ELSE
                     SUM(CASE
                         WHEN crs.final_grade IS NOT NULL
                              AND substr(crs.final_grade, 1, 2) IN ('FN', 'NF') THEN
                          1
                         ELSE
                          0
                         END) / COUNT(CASE
                                      WHEN crs.final_grade IS NOT NULL THEN
                                       1
                                      END)
                    END AS fn_pct,
                    SUM(crs.grade_adj_quality_points) AS quality_points_earned
               FROM utl_d_aim.szrcrse crs
               JOIN zsaturn.szrlevl l
                 ON l.szrlevl_levl_code = crs.levl_code
                AND l.szrlevl_has_awardable_cred = 'Y'
             -- student must be enrolled in dimension for current term
               JOIN (SELECT DISTINCT crse.pidm,
                                    crse.subj
                      FROM utl_d_aim.szrcrse crse
                     WHERE term_code = rec.term_code) req
                 ON req.pidm = crs.pidm
                AND req.subj = crs.subj
              WHERE 1 = 1
                AND crs.group_code = 'STD'
                AND crs.term_code < rec.term_code
              GROUP BY crs.subj,
                       crs.pidm) sao -- student as of term overall
    ON sao.subj_code = sco.subj_code
   AND sao.pidm = sco.pidm;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
MERGE INTO utl_d_aa.stusubjperform t1
USING (SELECT so.pidm,
              so.subj_code,
              rec.term_code AS term_code,
              round(so.avg_grade, 4) AS avg_grade,
              round(so.p_pct, 4) AS p_pct,
              round(so.w_pct, 4) AS w_pct,
              round(so.fn_pct, 4) AS fn_pct,
              round(so.avg_grade_asof_term, 4) AS avg_grade_asof_term,
              round(so.p_pct_asof_term, 4) AS p_pct_asof_term,
              round(so.w_pct_asof_term, 4) AS w_pct_asof_term,
              round(so.fn_pct_asof_term, 4) AS fn_pct_asof_term,
              so.seat_cnt AS seat_cnt,
              round(po.avg_grade, 4) AS avg_grade_peer,
              round(po.p_pct, 4) AS p_pct_peer,
              round(po.w_pct, 4) AS w_pct_peer,
              round(po.fn_pct, 4) AS fn_pct_peer,
              round(po.avg_grade_asof_term, 4) AS avg_grade_asof_term_peer,
              round(po.p_pct_asof_term, 4) AS p_pct_asof_term_peer,
              round(po.w_pct_asof_term, 4) AS w_pct_asof_term_peer,
              round(po.fn_pct_asof_term, 4) AS fn_pct_asof_term_peer,
              po.seat_cnt AS seat_cnt_peer,
              v_etl_date AS activity_date,
              round(so.quality_points, 4) AS quality_points,
              round(so.quality_points_asof_term, 4) AS quality_points_asof_term
         FROM utl_d_aa.stusubjperformso_gtt so
         LEFT JOIN utl_d_aa.stusubjperformpo_gtt po
           ON po.subj_code = so.subj_code
          AND po.term_code = so.term_code
        WHERE so.term_code = rec.term_code) t2
ON (t1.pidm = t2.pidm AND t1.term_code = t2.term_code AND t1.subj_code = t2.subj_code)
WHEN MATCHED THEN
UPDATE
   SET t1.avg_grade                = t2.avg_grade,
       t1.p_pct                    = t2.p_pct,
       t1.w_pct                    = t2.w_pct,
       t1.fn_pct                   = t2.fn_pct,
       t1.avg_grade_asof_term      = t2.avg_grade_asof_term,
       t1.p_pct_asof_term          = t2.p_pct_asof_term,
       t1.w_pct_asof_term          = t2.w_pct_asof_term,
       t1.fn_pct_asof_term         = t2.fn_pct_asof_term,
       t1.seat_cnt                 = t2.seat_cnt,
       t1.avg_grade_peer           = t2.avg_grade_peer,
       t1.p_pct_peer               = t2.p_pct_peer,
       t1.w_pct_peer               = t2.w_pct_peer,
       t1.fn_pct_peer              = t2.fn_pct_peer,
       t1.avg_grade_asof_term_peer = t2.avg_grade_asof_term_peer,
       t1.p_pct_asof_term_peer     = t2.p_pct_asof_term_peer,
       t1.w_pct_asof_term_peer     = t2.w_pct_asof_term_peer,
       t1.fn_pct_asof_term_peer    = t2.fn_pct_asof_term_peer,
       t1.seat_cnt_peer            = t2.seat_cnt_peer,
       t1.quality_points           = t2.quality_points,
       t1.quality_points_asof_term = t2.quality_points_asof_term,
       t1.activity_date            = t2.activity_date
WHEN NOT MATCHED THEN
INSERT
VALUES
(t2.pidm,
 t2.subj_code,
 t2.term_code,
 t2.avg_grade,
 t2.p_pct,
 t2.w_pct,
 t2.fn_pct,
 t2.avg_grade_asof_term,
 t2.p_pct_asof_term,
 t2.w_pct_asof_term,
 t2.fn_pct_asof_term,
 t2.seat_cnt,
 t2.avg_grade_peer,
 t2.p_pct_peer,
 t2.w_pct_peer,
 t2.fn_pct_peer,
 t2.avg_grade_asof_term_peer,
 t2.p_pct_asof_term_peer,
 t2.w_pct_asof_term_peer,
 t2.fn_pct_asof_term_peer,
 t2.seat_cnt_peer,
 v_etl_date,
 t2.quality_points,
 t2.quality_points_asof_term);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- remove any students NOT currently enrolled [dropped NOT withdraw]
-- do not try to time restrict here because of the way the cursor works only running once a day
DELETE FROM utl_d_aa.stusubjperform sp
 WHERE sp.term_code = rec.term_code
   AND NOT EXISTS (SELECT 1
          FROM utl_d_aim.szrcrse crse
         WHERE crse.term_code = sp.term_code
           AND crse.pidm = sp.pidm
           AND crse.subj = sp.subj_code);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'DELETE - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
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
utl_d_aa.truncate_table(v_table_name => 'stusubjperformpo_gtt');
utl_d_aa.truncate_table(v_table_name => 'stusubjperformso_gtt');
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
/*--------------------------------------------CHANGE LOG----------------------------------------
VERSION    DATE        USERNAME       UPDATES
---        03-27-2020  wgriffith2     --Initial release
--         03-08-2021  wgriffith2     --Adding quality_points and quality_points_asof_term
---        06-30-2022  wgriffith2     --refreshes do not happen until the subterm is completed
---        08-24-2022  wgriffith2     --refreshes must happen once the subterm starts! I fixed the seat count field to not start counting until the term has completed
---        09-09-2022  wgriffith2     --reverting back to the version prior to 20220630 to fix issues report in TKT2555560; optimization - only returning rows when active enrollment on the particular dimension
---        01-23-2025  wgriffith2     --fixing issues with pass/fail courses producing 0s; quality points show 0 when course is passed.
---        07-01-2025  wgriffith2     --Enhanced by implementing batch processing to handle large data volumes efficiently;  Added logic to ensure p_pct, w_pct, fn_pct are NULL if no non-null final grades exist in the group.
------------------------------------------------------------------------------------------------*/
END etl_aa_stusubjperform_refresh; --

procedure etl_aa_secfhtcoll_refresh (jobnumber number, processid varchar2, processname varchar2) is
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
v_proc        VARCHAR2(100) := 'etl_aa_secfhtcoll_refresh';
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
IF to_char(SYSDATE, 'HH24')  IN ('00', '20') THEN
dbms_lock.sleep(0.5); -- pause half second
MERGE INTO utl_d_aa.secfhtcoll target
USING (SELECT src.college_description,
              src.college_code,
              src.campus,
              src.ad_usernames,
              src.im_usernames,
              src.chair_usernames,
              src.dean_usernames,
              src.director_usernames,
              src.prov_usernames,
              src.fsc_usernames,
              src.sme_usernames,
              src.admin_usernames,
              src.activity_date
         FROM (SELECT stvcoll_desc AS college_description,
                      stvcoll_code AS college_code,
                      'ALL' AS campus,
                      ad_usernames,
                      im_usernames,
                      chair_usernames,
                      dean_usernames,
                      NULL AS director_usernames, -- deprecated **in the FHT, add them as an FSC to get them full college visability...**
                      NULL AS prov_usernames,
                      fsc_usernames,
                      sme_usernames,
                      admin_usernames,
                      v_etl_date AS activity_date
                 FROM saturn.stvcoll
               -- get admin access 
                 JOIN (SELECT regexp_replace(listagg(lower(username), '-') within GROUP(ORDER BY 1), '([^-]*)(-\1)+($|-)', '\1\3') AS admin_usernames FROM utl_d_aa.secadmin) aa_ron
                   ON 1 = 1
               -- get all FHT connections
               --  Dean 
               -- this join will give us all the active colleges in the FHT
                 JOIN (SELECT fht.coll_code,
                             regexp_replace(listagg(DISTINCT lower(fht.superior_username), '-') within GROUP(ORDER BY 1), '([^-]*)(-\1)+($|-)', '\1\3') AS dean_usernames
                        FROM utl_d_aa.faculty_hierarchy fht
                       WHERE fht.superior_position IN ('Dean')
                         AND v_etl_date BETWEEN fht.from_date AND fht.to_date -- only return active FHT connections
                       GROUP BY fht.coll_code) dean
                   ON dean.coll_code = stvcoll_code
               -- Instructional Mentor
                 LEFT JOIN (SELECT fht.coll_code,
                                  regexp_replace(listagg(DISTINCT lower(fht.superior_username), '-') within GROUP(ORDER BY 1), '([^-]*)(-\1)+($|-)', '\1\3') AS im_usernames
                             FROM utl_d_aa.faculty_hierarchy fht
                            WHERE fht.superior_position = 'Instructional Mentor'
                              AND SYSDATE BETWEEN fht.from_date AND fht.to_date -- only return active FHT connections
                            GROUP BY fht.coll_code) im
                   ON im.coll_code = stvcoll_code
               -- Chair
                 LEFT JOIN (SELECT fht.coll_code,
                                  regexp_replace(listagg(DISTINCT lower(fht.superior_username), '-') within GROUP(ORDER BY 1), '([^-]*)(-\1)+($|-)', '\1\3') AS chair_usernames
                             FROM utl_d_aa.faculty_hierarchy fht
                            WHERE fht.superior_position = 'Chair'
                              AND v_etl_date BETWEEN fht.from_date AND fht.to_date -- only return active FHT connections
                            GROUP BY fht.coll_code) ch
                   ON ch.coll_code = stvcoll_code
               --  Assistant/Associate Dean
                 LEFT JOIN (SELECT fht.coll_code,
                                  regexp_replace(listagg(DISTINCT lower(fht.superior_username), '-') within GROUP(ORDER BY 1), '([^-]*)(-\1)+($|-)', '\1\3') AS ad_usernames
                             FROM utl_d_aa.faculty_hierarchy fht
                            WHERE fht.superior_position IN ('Assistant/Associate Dean')
                              AND v_etl_date BETWEEN fht.from_date AND fht.to_date -- only return active FHT connections
                            GROUP BY fht.coll_code) ad
                   ON ad.coll_code = stvcoll_code
               -- Faculty Support Coordinator
                 LEFT JOIN (SELECT fht.coll_code,
                                  regexp_replace(listagg(DISTINCT lower(fht.superior_username), '-') within GROUP(ORDER BY 1), '([^-]*)(-\1)+($|-)', '\1\3') AS fsc_usernames
                             FROM utl_d_aa.faculty_hierarchy fht
                            WHERE fht.superior_position = 'Faculty Support Coordinator'
                              AND v_etl_date BETWEEN fht.from_date AND fht.to_date -- only return active FHT connections
                            GROUP BY fht.coll_code) ad
                   ON ad.coll_code = stvcoll_code
               -- get the subject matter experts (this is used selectively in dashboards)
                 LEFT JOIN (SELECT regexp_replace(listagg(lower(smebase.username), '-') within GROUP(ORDER BY 1), '([^-]*)(-\1)+($|-)', '\1\3') AS sme_usernames,
                                  smebase.coll_code
                             FROM (SELECT DISTINCT gob.gobtpac_external_user username,
                                                   cata.scbcrse_coll_code    coll_code
                                     FROM saturn.scbcrse cata
                                     JOIN zsaturn.zjrpsme c
                                       ON c.zjrpsme_crsesubj = cata.scbcrse_subj_code
                                      AND substr(c.zjrpsme_crsenum, 1, 3) = cata.scbcrse_crse_numb
                                      AND c.zjrpsme_effectivedate = (SELECT MAX(c2.zjrpsme_effectivedate)
                                                                       FROM zsaturn.zjrpsme c2
                                                                      WHERE c2.zjrpsme_crsesubj = c.zjrpsme_crsesubj
                                                                        AND substr(c2.zjrpsme_crsenum, 1, 3) = substr(c.zjrpsme_crsenum, 1, 3)
                                                                        AND c2.zjrpsme_crselgth = c.zjrpsme_crselgth
                                                                        AND c2.zjrpsme_crselang = c.zjrpsme_crselang
                                                                        AND c2.zjrpsme_effectivedate <= SYSDATE)
                                     JOIN gobtpac gob
                                       ON gob.gobtpac_pidm = c.zjrpsme_pidm
                                    WHERE cata.scbcrse_eff_term = (SELECT MAX(cc.scbcrse_eff_term)
                                                                     FROM saturn.scbcrse cc
                                                                    WHERE cc.scbcrse_subj_code = cata.scbcrse_subj_code
                                                                      AND cc.scbcrse_crse_numb = cata.scbcrse_crse_numb 
                                                                      AND cc.scbcrse_eff_term <= (SELECT MAX(z.term_code) term
                                                                                                    FROM zbtm.terms_by_group_v z
                                                                                                   WHERE z.start_date <= SYSDATE
                                                                                                     AND z.group_code = 'STD'))
                                      AND cata.scbcrse_csta_code = 'A') smebase
                            GROUP BY smebase.coll_code) sme
                   ON sme.coll_code = stvcoll_code) src
         LEFT JOIN utl_d_aa.secfhtcoll tgt
           ON tgt.college_code = src.college_code
          AND tgt.campus = src.campus
        WHERE 1 = 1
          AND (((src.college_code IS NULL AND tgt.college_code IS NOT NULL) OR --
              (src.college_code IS NOT NULL AND tgt.college_code IS NULL)) --
              OR nvl(src.im_usernames, 'X') <> nvl(tgt.im_usernames, 'X') --
              OR nvl(src.chair_usernames, 'X') <> nvl(tgt.chair_usernames, 'X') --
              OR nvl(src.dean_usernames, 'X') <> nvl(tgt.dean_usernames, 'X') --
              OR nvl(src.ad_usernames, 'X') <> nvl(tgt.ad_usernames, 'X') --
              OR nvl(src.fsc_usernames, 'X') <> nvl(tgt.fsc_usernames, 'X') --
              OR nvl(src.sme_usernames, 'X') <> nvl(tgt.sme_usernames, 'X') --
              OR nvl(src.admin_usernames, 'X') <> nvl(tgt.admin_usernames, 'X') --
              OR nvl(src.director_usernames, 'X') <> nvl(tgt.director_usernames, 'X') --
              )) src
ON (target.college_code = src.college_code AND target.campus = src.campus)
WHEN MATCHED THEN
UPDATE
   SET target.college_description = src.college_description,
       target.ad_usernames        = src.ad_usernames,
       target.im_usernames        = src.im_usernames,
       target.chair_usernames     = src.chair_usernames,
       target.dean_usernames      = src.dean_usernames,
       target.director_usernames  = src.director_usernames,
       target.admin_usernames     = src.admin_usernames,
       target.prov_usernames      = src.prov_usernames,
       target.fsc_usernames       = src.fsc_usernames,
       target.sme_usernames       = src.sme_usernames,
       target.activity_date       = src.activity_date
WHEN NOT MATCHED THEN
INSERT
(college_description,
 college_code,
 campus,
 ad_usernames,
 im_usernames,
 chair_usernames,
 dean_usernames,
 director_usernames,
 admin_usernames,
 prov_usernames,
 fsc_usernames,
 sme_usernames,
 activity_date)
VALUES
(src.college_description,
 src.college_code,
 src.campus,
 src.ad_usernames,
 src.im_usernames,
 src.chair_usernames,
 src.dean_usernames,
 src.director_usernames,
 src.admin_usernames,
 src.prov_usernames,
 src.fsc_usernames,
 src.sme_usernames,
 src.activity_date);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
END IF;
dbms_lock.sleep(0.5); -- pause half second
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
VERSION DATE    USERNAME  UPDATES
---   02-25-2020  WGRIFFITH2  --Initial release of secfhtcoll
---   03-03-2020  WGRIFFITH2  --nvl(d.campus,'X')
---   10-18-2024  WGRIFFITH2  --campus is no longer applicable; removed
---   10-23-2024  WGRIFFITH2  --changed to merge for constant uptime
--    06-19-2025  WGRIFFITH2  --MAJOR UPDATE: now using the utl_d_aa.faculty_hierarchy table for the active FHT connections
------------------------------------------------------------------------------------------------*/
END etl_aa_secfhtcoll_refresh;

procedure etl_aa_secfht_refresh (jobnumber number, processid varchar2, processname varchar2) is
/*
Table: utl_d_aa.secfht

Unique index: TERM_CODE, CRN

Purpose:
- Contains all courses that are in the academics tableau dashboards and controls access using row level security

Conditions:
- All course sections found in ssbsect
- Returns the primary instructor only; all associated roles to course section

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
v_proc        VARCHAR2(100) := 'etl_aa_secfht_refresh';
CURSOR c_terms IS
SELECT start_date,
       term_code,
       term_desc,
       group_code,
       rank() over(PARTITION BY 1 ORDER BY term_code ASC) ranking
  FROM (SELECT terms.start_date,
               terms.term_code AS term_code,
               terms.term_desc,
               terms.group_code
          FROM zbtm.terms_by_group_v terms
         WHERE terms.group_code IN ('STD', 'MED', 'ACD')
           AND (SYSDATE BETWEEN terms.start_date - 21 AND terms.end_date + (365 * 5))
           AND terms.semester <> 'WIN')
 ORDER BY ranking DESC;
BEGIN
-- dbms_output.enable(buffer_size => NULL);
--
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
utl_d_aa.truncate_table(v_table_name => 'secadmin');
INSERT INTO utl_d_aa.secadmin
(username,
 employee_role,
 employee_title)
SELECT a.empuserusername AS username,
       regexp_replace(listagg(DISTINCT(a.empclasstype), '/') within GROUP(ORDER BY 1), '([^-]*)(-\1)+($|-)', '\1\3') AS employee_role,
       regexp_replace(listagg(DISTINCT(a.empjobtitle), '; ') within GROUP(ORDER BY 1), '([^-]*)(-\1)+($|-)', '\1\3') AS employee_title
  FROM zgeneral.activefacultystaff a
 WHERE a.empstatus IN ('A') -- ensure employee is active
   AND a.empuserusername IN ('acwittcop', 'airish2', 'bebailey2', 'bsfrye', 'cgravatt', 'clreid2', 'cmleogrande', 'dlkeith', 'dmwoodru', 'dppaterson', 'dwilliams4', 'eaneff', 'djones42',--
                             'ehrabalcharlesworth', 'jbgregory2', 'jharper28', 'jmgauger', 'jpyoder', 'jpzealand', 'jswoosley', 'jwander', 'kdstruble', 'kjmayhew', 'kmichael9', --
                             'lcarroll15', 'lcpayton', 'mapeele', 'mcordes', 'mhfox2', 'mjzealan', 'mtshenkle', 'nrthomason', 'rdiddams', 'rkennedy', 'rjcardinale', 'cewilson2', --
                             'samuldrow', 'sbarker24', 'sdcraft', 'smhicks', 'spaik', 'taconner', 'wfspier', 'wgriffith2', 'kculpepper5','wruminn', 'lagallagher', 'cbrenning', --
							 'kpeterson10', 'jehimes', 'jtwalker', --
                             -- retention commitee
                             'dgdowell', 'mhyde', 'dkmelton', 'cjmisiano', 'joshrutledge', 'mtshenkle', 'kswiebe', 'bcyates', 'dbridge', 'jnbyrd', 'mcooper9', 'decostin')
 GROUP BY a.empuserusername
 ORDER BY 1;
COMMIT;
--
FOR rec IN c_terms
LOOP
v_count   := 0; -- reset count
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
MERGE INTO utl_d_aa.secfht tgt
USING (SELECT src.crn,
              src.term_code,
              src.coll_code,
              src.college,
              src.pidm,
              src.instructor,
              src.instructor_username,
              src.im_usernames,
              src.chair_usernames,
              src.dean_usernames,
              src.fsc_usernames,
              src.sme_usernames,
              src.admin_usernames,
              src.director_usernames,
              src.activity_date
         FROM (SELECT ll.crn AS crn,
                      ll.term_code AS term_code,
                      ll.coll_code AS coll_code,
                      stvcoll_desc AS college,
                      prof.spriden_pidm AS pidm,
                      prof.spriden_last_name || ', ' || prof.spriden_first_name AS instructor,
                      lower(gob.gobtpac_external_user) AS instructor_username,
                      im_usernames,
                      chair_usernames,
                      dean_usernames,
                      fsc_usernames,
                      sme_usernames,
                      admin_usernames,
                      NULL AS director_usernames, -- deprecated **in the FHT, add them as an FSC to get them full college visability...**
                      v_etl_date AS activity_date
                 FROM utl_d_lms.lms_link ll
                 JOIN saturn.spriden prof
                   ON prof.spriden_pidm = ll.faculty_pidm
                  AND prof.spriden_change_ind IS NULL
                  AND ll.term_code = rec.term_code
                  AND ll.faculty_pidm <> 3248979 --Staff, To Be Announced
                 JOIN general.gobtpac gob
                   ON gob.gobtpac_pidm = ll.faculty_pidm
                 LEFT JOIN saturn.stvcoll
                   ON stvcoll_code = ll.coll_code
               -- get admin access 
                 JOIN (SELECT regexp_replace(listagg(lower(username), '-') within GROUP(ORDER BY 1), '([^-]*)(-\1)+($|-)', '\1\3') AS admin_usernames FROM utl_d_aa.secadmin) aa_ron
                   ON 1 = 1
               -- get all FHT connections 
               -- Instructional Mentor
                 LEFT JOIN (SELECT fht.pidm,
                                  regexp_replace(listagg(DISTINCT lower(fht.superior_username), '-') within GROUP(ORDER BY 1), '([^-]*)(-\1)+($|-)', '\1\3') AS im_usernames
                             FROM utl_d_aa.faculty_hierarchy fht
                            WHERE fht.superior_position = 'Instructional Mentor'
                              AND v_etl_date BETWEEN fht.from_date AND fht.to_date -- only return active FHT connections
                            GROUP BY fht.pidm) im
                   ON im.pidm = ll.faculty_pidm
               -- Chair (join on COLLEGE)
                 LEFT JOIN (SELECT fht.coll_code,
                                  regexp_replace(listagg(DISTINCT lower(fht.superior_username), '-') within GROUP(ORDER BY 1), '([^-]*)(-\1)+($|-)', '\1\3') AS chair_usernames
                             FROM utl_d_aa.faculty_hierarchy fht
                            WHERE fht.superior_position = 'Chair'
                              AND v_etl_date BETWEEN fht.from_date AND fht.to_date -- only return active FHT connections
                            GROUP BY fht.coll_code) ch
                   ON ch.coll_code = ll.coll_code
               -- Dean', 'Assistant/Associate Dean (join on COLLEGE)
                 LEFT JOIN (SELECT fht.coll_code,
                                  regexp_replace(listagg(DISTINCT lower(fht.superior_username), '-') within GROUP(ORDER BY 1), '([^-]*)(-\1)+($|-)', '\1\3') AS dean_usernames
                             FROM utl_d_aa.faculty_hierarchy fht
                            WHERE fht.superior_position IN ('Dean', 'Assistant/Associate Dean')
                              AND v_etl_date BETWEEN fht.from_date AND fht.to_date -- only return active FHT connections
                            GROUP BY fht.coll_code) ad
                   ON ad.coll_code = ll.coll_code
               -- Faculty Support Coordinator
                 LEFT JOIN (SELECT fht.coll_code,
                                  regexp_replace(listagg(DISTINCT lower(fht.superior_username), '-') within GROUP(ORDER BY 1), '([^-]*)(-\1)+($|-)', '\1\3') AS fsc_usernames
                             FROM utl_d_aa.faculty_hierarchy fht
                            WHERE fht.superior_position = 'Faculty Support Coordinator'
                              AND v_etl_date BETWEEN fht.from_date AND fht.to_date -- only return active FHT connections
                            GROUP BY fht.coll_code) ad
                   ON ad.coll_code = ll.coll_code
               -- get the subject matter experts (this is used selectively in dashboards)
                 LEFT JOIN (SELECT zj.zjrpsme_crsesubj || ' ' || zj.zjrpsme_crsenum AS course,
                                  regexp_replace(listagg(DISTINCT lower(gob.gobtpac_external_user), '-') within GROUP(ORDER BY 1), '([^-]*)(-\1)+($|-)', '\1\3') AS sme_usernames
                             FROM zsaturn.zjrpsme zj
                             JOIN zsaturn.zjvcrlg crlg
                               ON crlg.zjvcrlg_id = zj.zjrpsme_crselang
                             JOIN zsaturn.zjvcrlh crlh
                               ON crlh.zjvcrlh_id = zj.zjrpsme_crselgth
                             JOIN general.gobtpac gob
                               ON gob.gobtpac_pidm = zj.zjrpsme_pidm
                            WHERE crlg.zjvcrlg_name = 'English'
                              AND crlh.zjvcrlh_number = 8
                            GROUP BY zj.zjrpsme_crsesubj || ' ' || zj.zjrpsme_crsenum) sme
                   ON sme.course = ll.subj_code || ' ' || ll.crse_numb) src
         LEFT JOIN utl_d_aa.secfht tgt
           ON tgt.term_code = src.term_code
          AND tgt.crn = src.crn
        WHERE 1 = 1
          AND (((src.instructor_username IS NULL AND tgt.instructor_username IS NOT NULL) OR --
              (src.instructor_username IS NOT NULL AND tgt.instructor_username IS NULL)) --
              OR (nvl(src.instructor_username, 'X') <> nvl(tgt.instructor_username, 'X') --
              OR nvl(src.im_usernames, 'X') <> nvl(tgt.im_usernames, 'X') --
              OR nvl(src.chair_usernames, 'X') <> nvl(tgt.chair_usernames, 'X') --
              OR nvl(src.dean_usernames, 'X') <> nvl(tgt.dean_usernames, 'X') --
              OR nvl(src.fsc_usernames, 'X') <> nvl(tgt.fsc_usernames, 'X') --
              OR nvl(src.sme_usernames, 'X') <> nvl(tgt.sme_usernames, 'X') --
              OR nvl(src.admin_usernames, 'X') <> nvl(tgt.admin_usernames, 'X') --
              OR nvl(src.director_usernames, 'X') <> nvl(tgt.director_usernames, 'X') --
              ))) src
ON (tgt.term_code = src.term_code AND tgt.crn = src.crn)
WHEN MATCHED THEN
UPDATE
   SET tgt.coll_code           = src.coll_code,
       tgt.college             = src.college,
       tgt.pidm                = src.pidm,
       tgt.instructor          = src.instructor,
       tgt.instructor_username = src.instructor_username,
       tgt.im_usernames        = src.im_usernames,
       tgt.chair_usernames     = src.chair_usernames,
       tgt.dean_usernames      = src.dean_usernames,
       tgt.fsc_usernames       = src.fsc_usernames,
       tgt.sme_usernames       = src.sme_usernames,
       tgt.admin_usernames     = src.admin_usernames,
       tgt.director_usernames  = src.director_usernames,
       tgt.activity_date       = src.activity_date
WHEN NOT MATCHED THEN
INSERT
(crn,
 term_code,
 coll_code,
 college,
 pidm,
 instructor,
 instructor_username,
 im_usernames,
 chair_usernames,
 dean_usernames,
 fsc_usernames,
 sme_usernames,
 admin_usernames,
 director_usernames,
 activity_date)
VALUES
(src.crn,
 src.term_code,
 src.coll_code,
 src.college,
 src.pidm,
 src.instructor,
 src.instructor_username,
 src.im_usernames,
 src.chair_usernames,
 src.dean_usernames,
 src.fsc_usernames,
 src.sme_usernames,
 src.admin_usernames,
 src.director_usernames,
 src.activity_date);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- remove any records that no longer EXISTS
DELETE FROM utl_d_aa.secfht tgt
 WHERE NOT EXISTS (SELECT 1
          FROM utl_d_lms.lms_link src
         WHERE src.term_code = tgt.term_code
           AND src.crn = tgt.crn)
   AND tgt.term_code = rec.term_code;
v_count := SQL%ROWCOUNT;
-- remove any records older than 5 years
DELETE FROM utl_d_aa.secfht tgt
 WHERE EXISTS (SELECT 1
          FROM utl_d_lms.lms_link src
         WHERE src.term_code = tgt.term_code
           AND src.crn = tgt.crn)
   AND rec.ranking = 1 -- RUN ONLY ONCE AT THE END 
   AND tgt.term_code < rec.term_code;
v_count := v_count + SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'DELETE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
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
VERSION DATE    USERNAME  UPDATES
---   09-20-2017  WGRIFFITH2  --Initial release
---   09-28-2017  WGRIFFITH2  --Fixed a ton of broken links between FHT and Banner courses
---   10-23-2017  WGRIFFITH2  --Associate Dean title has been changed to Assistant/Associate Dean
---   05-14-2018  WGRIFFITH2  --changed to run on a week prior to the term start date
---   05-15-2018  WGRIFFITH2  --optimization and adding error handling
---   05-22-2018  WGRIFFITH2  --reverting back to previous version; removing merge
---   02-20-2020  WGRIFFITH2  --Initial release of secfht
---   03-17-2022  WGRIFFITH2  --Adding LUOA courses
--    09-22-2022  WGRIFFITH2  --default to gobtpac username if FHT records do not exist
---   03-15-2023  WGRIFFITH2  --adding output to insert_job_log
---   11-28-2023  WGRIFFITH2  --updates to fix missing college data historically
---   12-05-2023  WGRIFFITH2  --fht has to join on pidm & college line 216-217
---   10-17-2024  WGRIFFITH2  --switching from delete/insert to merge with delete conditionally
---   10-21-2024  WGRIFFITH2  --adding partitioning
---   11-19-2024  WGRIFFITH2  --adding LUCOM
---   12-05-2024  WGRIFFITH2  --splitting chairs into their own subquery
---   12-10-2024  WGRIFFITH2  --adding secadmin proc; adding employee_role, employee_title fields to the secadmin table
--    06-19-2025  WGRIFFITH2  --MAJOR UPDATE: now using the utl_d_aa.faculty_hierarchy table for the active FHT connections
--    07-10-2025  WGRIFFITH2  --MAJOR UPDATE: (somewhat reverting back to how it used to work) Chair, ADs, Deans, FSCs all join on COLLEGE now instead of pidm because the FHT is too confusing for people to configure it correctly AND this change does not disrupt the FPT evaluations
------------------------------------------------------------------------------------------------*/
END etl_aa_secfht_refresh; --

procedure etl_aa_crsgradestats_refresh (jobnumber number, processid varchar2, processname varchar2) is

--
-- PURPOSE: Aggregates course-grade distributions and quality-point statistics by section to support academic performance reporting and monitoring.
--
-- TABLE: utl_d_aa.crsgradestats
--
-- UNIQUE INDEX: CRN, TERM_CODE, PTRM_CODE, BB_CRSE_ID
--
-- CONDITIONS:
-- Runs once daily at midnight and only processes terms with grade changes recorded in the prior day.
-- Processes terms from academic groups STD, ACD, and MED, limited to terms with code 200740 or later.
-- Refreshes data one term at a time by deleting existing rows for the term and reloading aggregated results.
-- Includes only enrollments with a non-null final grade.
-- Includes only enrollments in levels flagged as having awardable credit (zsaturn.szrlevl_has_awardable_cred = 'Y').
-- Excludes students with an active financial aid fraud/spam hold (codes FC, FD, FO, EH, FI, FY, FF) when the hold is effective on the run date.
-- Requires grade submission for a section: either at least 7 days after the LMS end_date, or at least 365 days after the LMS start_date.
-- Aggregates results per section identified by CRN, TERM_CODE, PTRM_CODE, and LMS course code (BB_CRSE_ID).
-- Computes median credit hours for the section.
-- Computes minimum, median, average (rounded to four decimals), and maximum adjusted quality points for the section.
-- Counts "success" when any of the following are true: lower-level courses (numbers starting 0–4) with adjusted quality points ≥ 2.00; upper/graduate-level courses (numbers starting 5–9) with adjusted quality points ≥ 2.67; final grade is P or PR; or the letter grade begins with A, B, or C.
-- Counts letter grades by thresholds or explicit letters: A when adjusted quality points > 3.33 or grade = 'A'; B when adjusted quality points between 2.67 and 3.33 or grade = 'B'; C when adjusted quality points between 1.67 and 2.33 or grade = 'C'; D when adjusted quality points between 0.67 and 1.33 or grade = 'D'.
-- Counts F when adjusted quality points = 0 or grade = 'F', excluding cases where the grade is FN, NF, W, or PR.
-- Counts withdrawals (WD) when the final grade code begins with 'W'.
-- Counts non-attendance failures (FN) when the final grade is 'FN' or 'NF'.
-- Counts pass (P) when the final grade is 'P' or 'PR'.
-- Counts not pass (NP) when the final grade is 'NP'.
-- Total count represents the number of enrollment records (students) contributing to the section’s statistics.
-- Sets activity_date to the ETL run timestamp.
--
-- URL: https://reports.liberty.edu/#/site/Academics/views/SuccessRates/CourseInstructorSuccessRates
--
-- DECLARE
--- PARAMS
v_etl_date  DATE := SYSDATE;
v_msg       VARCHAR2(2000);
v_instance  VARCHAR2(50) := upper('ALL'); -- inst from the jams job; used for determining instance
v_partition NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
-- v_mod      NUMBER := 1; -- number of partitions to be created

v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_aa_crsgradestats_refresh';
CURSOR c_terms IS
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
   AND shrtckg_term_code >= '200740'
 ORDER BY group_code DESC,
          1          DESC;
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
DELETE FROM utl_d_aa.crsgradestats ag WHERE ag.term_code = rec.term_code;
-- DO NOT COMMIT HERE
INSERT INTO utl_d_aa.crsgradestats
(crn,
 term_code,
 ptrm_code,
 bb_crse_id,
 credit_hr,
 min_quality_pts,
 med_quality_pts,
 mean_quality_pts,
 max_quality_pts,
 success_cnt,
 a_cnt,
 b_cnt,
 c_cnt,
 d_cnt,
 f_cnt,
 wd_cnt,
 fn_cnt,
 p_cnt,
 np_cnt,
 total_cnt,
 activity_date)
SELECT crn,
       term_code,
       ptrm_code,
       bb_crse_id,
       median(credit_hr) AS credit_hr,
       MIN(crs.grade_adj_quality_points) AS min_quality_pts,
       median(crs.grade_adj_quality_points) AS med_quality_pts,
       round(AVG(crs.grade_adj_quality_points), 4) AS mean_quality_pts,
       MAX(crs.grade_adj_quality_points) AS max_quality_pts,
       SUM(success) AS success_cnt,
       SUM(a) AS a_cnt,
       SUM(b) AS b_cnt,
       SUM(c) AS c_cnt,
       SUM(d) AS d_cnt,
       SUM(f) AS f_cnt,
       SUM(wd) AS wd_cnt,
       SUM(fn) AS fn_cnt,
       SUM(p) AS p_cnt,
       SUM(np) AS np_cnt,
       COUNT(pidm) AS total_cnt,
       v_etl_date activity_date
  FROM (SELECT crs.pidm,
                crs.crn,
                crs.term_code,
                crs.ptrm_code,
                ll.course_code AS bb_crse_id,
                crs.credit_hr AS credit_hr,
                crs.final_grade AS final_grade,
                crs.grade_adj_quality_points,
                CASE
                WHEN substr(crs.numb, 1, 1) IN ('0', '1', '2', '3', '4')
                     AND crs.grade_adj_quality_points >= 2 THEN
                 1
                WHEN substr(crs.numb, 1, 1) IN ('5', '6', '7', '8', '9')
                     AND crs.grade_adj_quality_points >= 2.67 THEN
                 1
                WHEN crs.final_grade = 'P' THEN
                 1
                WHEN crs.final_grade = 'PR' THEN -- per Mike Shenkle
                 1
                WHEN substr(crs.final_grade, 1, 1) IN ('A', 'B', 'C') THEN
                 1
                ELSE
                 0
                END AS success,
                CASE
                WHEN crs.grade_adj_quality_points > 3.33 THEN
                 1
                WHEN substr(crs.final_grade, 1, 1) IN ('A') THEN
                 1
                ELSE
                 0
                END AS a,
                CASE
                WHEN crs.grade_adj_quality_points BETWEEN 2.67 AND 3.33 THEN
                 1
                WHEN substr(crs.final_grade, 1, 1) IN ('B') THEN
                 1
                ELSE
                 0
                END AS b,
                CASE
                WHEN crs.grade_adj_quality_points BETWEEN 1.67 AND 2.33 THEN
                 1
                WHEN substr(crs.final_grade, 1, 1) IN ('C') THEN
                 1
                ELSE
                 0
                END AS c,
                CASE
                WHEN crs.grade_adj_quality_points BETWEEN .67 AND 1.33 THEN
                 1
                WHEN substr(crs.final_grade, 1, 1) IN ('D') THEN
                 1
                ELSE
                 0
                END AS d,
                CASE
                WHEN crs.grade_adj_quality_points = 0
                     AND crs.final_grade NOT IN ('FN', 'NF', 'W', 'PR') THEN
                 1
                WHEN crs.final_grade = 'F'
                     AND crs.final_grade NOT IN ('FN', 'NF', 'W', 'PR') THEN
                 1
                ELSE
                 0
                END AS f,
                CASE
                WHEN substr(crs.final_grade, 1, 1) = 'W' THEN
                 1
                ELSE
                 0
                END AS wd,
                CASE
                WHEN crs.final_grade IN ('FN', 'NF') THEN
                 1
                ELSE
                 0
                END AS fn,
                CASE
                WHEN crs.final_grade = 'P' THEN
                 1
                WHEN crs.final_grade = 'PR' THEN -- per Mike Shenkle
                 1
                ELSE
                 0
                END AS p,
                CASE
                WHEN crs.final_grade = 'NP' THEN
                 1
                ELSE
                 0
                END AS np
           FROM utl_d_aim.szrcrse crs
           JOIN zsaturn.szrlevl l
             ON l.szrlevl_levl_code = crs.levl_code
            AND l.szrlevl_has_awardable_cred = 'Y'
           JOIN utl_d_lms.lms_link ll
             ON ll.crn = crs.crn
            AND ll.term_code = crs.term_code
           LEFT JOIN rorhold fin_fraud
             ON fin_fraud.rorhold_pidm = crs.pidm
            AND fin_fraud.rorhold_hold_code IN ('FC', 'FD', 'FO', 'EH', 'FI', 'FY', 'FF') -- financial aid side fraud ID'ed
           AND SYSDATE BETWEEN fin_fraud.rorhold_from_date AND fin_fraud.rorhold_to_date
         WHERE crs.term_code = rec.term_code
           AND fin_fraud.rorhold_pidm IS NULL -- removing any financial aid fraudsters
           AND crs.final_grade IS NOT NULL
           AND (v_etl_date >= ll.end_date + 7 -- MUST HAVE GRADES SUBMITTED
               OR v_etl_date >= ll.start_date + 365)) crs
 GROUP BY crn,
          term_code,
          ptrm_code,
          bb_crse_id;
v_count := SQL%ROWCOUNT;
IF v_count > 0 THEN
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
ELSE
ROLLBACK;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
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
---     02-12-2020  WGRIFFITH2  --Initial release
---     02-18-2020  WGRIFFITH2  --AND SYSDATE >= crs.ptrm_end + 7 -- MUST HAVE GRADES SUBMITTED
---     03-12-2020  WGRIFFITH2  --Removing SZRGRDS table
---     04-02-2020  WGRIFFITH2  --Adding the letter grade counts
---     11-10-2021  WGRIFFITH2  --Adding LUOA
---     03-15-2023  WGRIFFITH2  --adding output to insert_job_log
---     03-27-2023  WGRIFFITH2  --marking crs.final_grade = 'PR' is successful
-- 20260105 - WGRIFFITH2 - Excluded fraud/spam-hold PIDMs via join to [rorhold]
------------------------------------------------------------------------------------------------*/
END etl_aa_crsgradestats_refresh;

procedure etl_aa_crsgrade_refresh (jobnumber number, processid varchar2, processname varchar2) is
/*
Table: utl_d_aa.crsgrade

Unique index: pidm, crn, term_code

Purpose:
- Keep track of final grades for students and determine final grade success rates

Conditions:
- If the student is undergrad (UG), the success is determined by having a C or better that is represented by the grade_adj_quality_points.
- If the student is graduate or doctorate, the success is determined by having a C+ or better that is represented by the grade_adj_quality_points.

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
v_proc        VARCHAR2(100) := 'etl_aa_crsgrade_refresh';
CURSOR c_terms IS
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
   AND shrtckg_term_code >= '200740'
 ORDER BY group_code DESC,
          1          DESC;
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
DELETE FROM utl_d_aa.crsgrade ag WHERE ag.term_code = rec.term_code;
-- DO NOT COMMIT HERE
INSERT INTO utl_d_aa.crsgrade
(pidm,
 crn,
 term_code,
 ptrm_code,
 bb_crse_id,
 credit_hr,
 final_grade,
 quality_pts,
 success,
 wd,
 fn,
 grade_date,
 activity_date)
SELECT crs.pidm,
       crs.crn,
       crs.term_code,
       crs.ptrm_code,
       ll.course_code AS bb_crse_id,
       crs.credit_hr AS credit_hr,
       crs.final_grade AS final_grade,
       crs.grade_adj_quality_points,
       CASE
       WHEN substr(crs.numb, 1, 1) IN ('0', '1', '2', '3', '4')
            AND crs.grade_adj_quality_points >= 2 THEN
        1
       WHEN substr(crs.numb, 1, 1) IN ('5', '6', '7', '8', '9')
            AND crs.grade_adj_quality_points >= 2.67 THEN
        1
       WHEN crs.final_grade = 'P' THEN
        1
       WHEN substr(crs.final_grade, 1, 1) IN ('A', 'B', 'C') THEN
        1
       ELSE
        0
       END AS success,
       CASE
       WHEN substr(crs.final_grade, 1, 1) = 'W' THEN
        1
       ELSE
        0
       END AS wd,
       CASE
       WHEN crs.final_grade IN ('FN', 'NF') THEN
        1
       ELSE
        0
       END AS fn,
       crs.grade_date AS grade_date,
       SYSDATE AS activity_date
  FROM utl_d_aim.szrcrse crs
  JOIN zsaturn.szrlevl l
    ON l.szrlevl_levl_code = crs.levl_code
   AND l.szrlevl_has_awardable_cred = 'Y'
  JOIN utl_d_lms.lms_link ll
    ON ll.crn = crs.crn
   AND ll.term_code = crs.term_code
 WHERE crs.term_code = rec.term_code
   AND crs.final_grade IS NOT NULL
   AND (SYSDATE >= ll.end_date + 7); -- MUST HAVE GRADES SUBMITTED
v_count := SQL%ROWCOUNT;
IF v_count > 0 THEN
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
ELSE
ROLLBACK;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
END IF;
end loop; -- c_terms
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
---     02-12-2020  WGRIFFITH2  --Initial release
---     03-12-2020  WGRIFFITH2  --Removing SZRGRDS table
---     04-16-2020  WGRIFFITH2  --pass/fail courses now calc into the success rate
---     11-10-2021  WGRIFFITH2  --Adding LUOA
---     03-15-2023  WGRIFFITH2  --adding output to insert_job_log
------------------------------------------------------------------------------------------------*/
END etl_aa_crsgrade_refresh;

procedure etl_aa_crscalendar_refresh (jobnumber number, processid varchar2, processname varchar2) is
/*
Table: utl_d_aa.crscalendar

Unique index: TERM_CODE, CRN, DTE

Purpose:
- Contains all courses and it a date table for every day the course is active (start_date-7 to end_date + 21).

Conditions:
- All course sections found in utl_d_lms.lms_link

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
v_proc        VARCHAR2(100) := 'etl_aa_crscalendar_refresh';
CURSOR c_terms IS
SELECT t.term_code,
       t.group_code
  FROM zbtm.terms_by_group_v t
 WHERE 1 = 1
   AND to_char(SYSDATE, 'HH24') IN ('00')  -- ONLY RUN AFTER MIDNIGHT
   AND ((t.group_code IN ('STD') AND SYSDATE >= t.start_date - 180 AND SYSDATE <= t.end_date + 90) --
       OR (t.group_code IN ('MED') AND to_char(SYSDATE, 'HH24') IN ('00') AND SYSDATE >= t.start_date - 180 AND SYSDATE <= t.end_date + 90) -- run once a day only
       OR (t.group_code IN ('ACD') AND t.term_code >= '202138' AND SYSDATE >= t.start_date - 180 AND SYSDATE <= t.end_date + 365) -- prevent overlap of CD1 and CD2
       )
 ORDER BY 2 DESC, 1 DESC;
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
MERGE INTO utl_d_aa.crscalendar tgt
USING (SELECT src.crn,
              src.term_code,
              src.ptrm_code,
              src.bb_crse_id,
              src.start_date,
              src.end_date,
              src.dte,
              src.day_number,
              src.day_of_week,
              src.week_number,
              src.week_start_date,
              src.week_end_date
         FROM (SELECT crn,
                      term_code,
                      ptrm_code,
                      bb_crse_id,
                      start_date,
                      end_date,
                      dte,
                      day_number,
                      day_of_week,
                      week_number,
                      first_value(dte ignore NULLS) over(PARTITION BY crn, term_code, week_number ORDER BY day_number, dte) AS week_start_date,
                      first_value(dte ignore NULLS) over(PARTITION BY crn, term_code, week_number ORDER BY day_number DESC, dte DESC) AS week_end_date
                 FROM (SELECT ll.crn,
                              ll.term_code,
                              ll.subj_code || ll.crse_numb || '_' || ll.seq_numb || '_' || ll.term_code AS bb_crse_id,
                              ll.ptrm_code,
                              ll.start_date,
                              ll.end_date,
                              ll.start_date + daysin.numb AS dte,
                              daysin.numb + 1 AS day_number,
                              TRIM(to_char(ll.start_date + daysin.numb, 'Day')) AS day_of_week,
                              CASE
                              -- week 0
                              WHEN daysin.numb + 1 <= 0 THEN
                               0
                              -- ALL resident: monday to Sunday
                              WHEN ll.ptrm_code IN ('R') THEN
                               decode(ceil((daysin.numb + 1) / 7), 0, 1, ceil((daysin.numb + 1) / 7))
                              -- ALL luoa: monday to Sunday
                              WHEN rec.group_code = 'ACD' THEN
                               decode(ceil((daysin.numb + 1) / 7), 0, 1, ceil((daysin.numb + 1) / 7))
                              -- ALL med school: monday to Sunday
                              WHEN rec.group_code = 'MED' THEN
                               decode(ceil((daysin.numb + 1) / 7), 0, 1, ceil((daysin.numb + 1) / 7))
                              --UG week 1: monday to monday (8 days)
                              --UG weeks 2-7: tuesday to monday
                              --UG week 8(or whatever the final week is for A term): tuesday to Friday
                              WHEN substr(ll.crse_numb, 1, 1) IN ('0', '1', '2', '3', '4') THEN
                               decode(ceil((daysin.numb) / 7), 0, 1, ceil((daysin.numb) / 7))
                              --GR/DR weeks 1-7: monday to Sunday
                              --GR/DR week 8 (or whatever the final week is for A term): monday to friday
                              WHEN substr(ll.crse_numb, 1, 1) NOT IN ('0', '1', '2', '3', '4') THEN
                               decode(ceil((daysin.numb + 1) / 7), 0, 1, ceil((daysin.numb + 1) / 7))
                              END AS week_number
                         FROM utl_d_lms.lms_link ll
             JOIN zsaturn.szrlevl l
               ON l.szrlevl_levl_code = ll.levl_code
              AND l.szrlevl_has_awardable_cred = 'Y' -- remove EM
                         JOIN (SELECT LEVEL - 8 numb FROM dual CONNECT BY LEVEL <= 800) daysin
                           ON ll.start_date + daysin.numb <= ll.end_date
                        WHERE 1 = 1
                          AND ll.term_code = rec.term_code)) src
         LEFT JOIN utl_d_aa.crscalendar tgt
           ON src.term_code = tgt.term_code
          AND src.crn = tgt.crn
          AND src.dte = tgt.dte
        WHERE 1 = 1 -- jic there overlap running different v_partition at the same time
             -- for inserts or updates...
          AND (((src.crn IS NULL AND tgt.crn IS NOT NULL) OR (src.crn IS NOT NULL AND tgt.crn IS NULL)) OR --
              -- for updates if any data has changed...
              (coalesce(src.bb_crse_id, 'X') <> coalesce(tgt.bb_crse_id, 'X')) OR --
              (coalesce(src.ptrm_code, 'X') <> coalesce(tgt.ptrm_code, 'X')) OR --
              (coalesce(src.day_number, -99) <> coalesce(tgt.day_number, -99)) OR --
              (coalesce(src.day_of_week, 'X') <> coalesce(tgt.day_of_week, 'X')) OR --
              (coalesce(src.start_date, SYSDATE) <> coalesce(tgt.start_date, SYSDATE)) OR --
              (coalesce(src.end_date, SYSDATE) <> coalesce(tgt.end_date, SYSDATE)) OR --
              (coalesce(src.week_number, -99) <> coalesce(tgt.week_number, -99)) OR --
              (coalesce(src.week_start_date, SYSDATE) <> coalesce(tgt.week_start_date, SYSDATE)) OR --
              (coalesce(src.week_end_date, SYSDATE) <> coalesce(tgt.week_end_date, SYSDATE)))) src
ON (tgt.term_code = src.term_code AND tgt.crn = src.crn AND tgt.dte = src.dte)
WHEN MATCHED THEN
UPDATE
   SET tgt.ptrm_code       = src.ptrm_code,
       tgt.bb_crse_id      = src.bb_crse_id,
       tgt.start_date      = src.start_date,
       tgt.end_date        = src.end_date,
       tgt.day_number      = src.day_number,
       tgt.day_of_week     = src.day_of_week,
       tgt.week_number     = src.week_number,
       tgt.week_start_date = src.week_start_date,
       tgt.week_end_date   = src.week_end_date
WHEN NOT MATCHED THEN
INSERT
(crn,
 term_code,
 ptrm_code,
 bb_crse_id,
 start_date,
 end_date,
 dte,
 day_number,
 day_of_week,
 week_number,
 week_start_date,
 week_end_date)
VALUES
(src.crn,
 src.term_code,
 src.ptrm_code,
 src.bb_crse_id,
 src.start_date,
 src.end_date,
 src.dte,
 src.day_number,
 src.day_of_week,
 src.week_number,
 src.week_start_date,
 src.week_end_date);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
end loop; -- c_terms
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
---     02-03-2020  WGRIFFITH2  --Initial release
---     02-19-2020  WGRIFFITH2  --Adding week_start_date and week_end_date
---     03-16-2020  WGRIFFITH2  --Update to resident courses
---     03-18-2020  WGRIFFITH2  --Removing the bb_link join
---     04-12-2020  WGRIFFITH2  --Adding J ptrm
---     09-01-2021  WGRIFFITH2  --Adding MED school
---     11-10-2021  WGRIFFITH2  --Adding LUOA
---     03-15-2023  WGRIFFITH2  --Switch to use LMS LINK; adding output to insert_job_log
------------------------------------------------------------------------------------------------*/
END etl_aa_crscalendar_refresh;

procedure etl_aa_stufngrade_log_refresh (jobnumber number, processid varchar2, processname varchar2) is
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
v_proc        VARCHAR2(100) := 'etl_aa_stufngrade_log_refresh';
CURSOR c_terms IS
SELECT t.term_code,
       t.group_code
  FROM zbtm.terms_by_group_v t
 WHERE 1 = 1
   AND ((t.group_code IN ('STD') AND SYSDATE >= t.start_date - 180 AND SYSDATE <= t.end_date + 90) --
       OR (t.group_code IN ('MED') AND to_char(SYSDATE, 'HH24') IN ('00') AND SYSDATE >= t.start_date - 180 AND SYSDATE <= t.end_date + 90) -- run once a day only
       OR (t.group_code IN ('ACD') AND t.term_code >= '202138' AND SYSDATE >= t.start_date - 180 AND SYSDATE <= t.end_date + 365) -- prevent overlap of CD1 and CD2
       )
ORDER BY 2 DESC, 1 DESC;
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
MERGE INTO utl_d_aa.stufngrade_log destination
USING (SELECT fn.crn,
              fn.term_code,
              fn.pidm,
              fn.grade,
              fn.grade_date,
              fn.activity_date,
              fn.sequence_number
         FROM (SELECT sfrstcr.sfrstcr_crn crn,
                      sfrstcr.sfrstcr_term_code term_code,
                      sfrstcr.sfrstcr_pidm AS pidm,
                      sfrstcr.sfrstcr_grde_code AS grade,
                      MAX(coalesce(sfrstcr.sfrstcr_grde_date, shrtckg_final_grde_chg_date, sysdate)) AS grade_date, -- in case the grade date is null [it is possible - 2/29]
                      SYSDATE AS activity_date,
                      MAX(coalesce(shrtckn_seq_no, 1)) AS sequence_number
                 FROM saturn.sfrstcr sfrstcr
                 JOIN saturn.stvrsts stvrsts
                   ON stvrsts.stvrsts_code = sfrstcr.sfrstcr_rsts_code
                  AND sfrstcr_term_code = rec.term_code
                  AND sfrstcr_rsts_code <> 'AU'
                  AND sfrstcr.sfrstcr_grde_code IN ('FN','NF') -- added NF on 20250514
                  AND stvrsts.stvrsts_incl_sect_enrl = 'Y'
                  AND stvrsts.stvrsts_withdraw_ind = 'N'
                  AND stvrsts.stvrsts_incl_assess = 'Y'
                 LEFT JOIN (SELECT shrtckg_grde_code_final             AS shrtckg_grde_code_final,
                                  shrtckn_pidm,
                                  shrtckn_term_code,
                                  shrtckn_crn,
                                  shrtckn_seq_no,
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
                GROUP BY sfrstcr.sfrstcr_crn,
                         sfrstcr.sfrstcr_term_code,
                         sfrstcr.sfrstcr_pidm,
                         sfrstcr.sfrstcr_grde_code) fn
         LEFT JOIN utl_d_aa.stufngrade_log fnl
           ON fnl.pidm = fn.pidm
          AND fnl.term_code = fn.term_code
          AND fnl.crn = fn.crn
          AND fnl.grade_date = fn.grade_date
        WHERE fnl.pidm IS NULL -- only log changes
       ) new_records
ON (destination.crn = new_records.crn AND destination.term_code = new_records.term_code AND destination.pidm = new_records.pidm)
WHEN MATCHED THEN
UPDATE
   SET destination.grade           = new_records.grade,
       destination.grade_date      = new_records.grade_date,
       destination.activity_date   = new_records.activity_date,
       destination.sequence_number = new_records.sequence_number
WHEN NOT MATCHED THEN
INSERT
VALUES
(new_records.crn,
 new_records.term_code,
 new_records.pidm,
 new_records.grade,
 new_records.grade_date,
 new_records.activity_date,
 new_records.sequence_number);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'MERGE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
end loop; -- c_terms
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
---     01-20-2020  WGRIFFITH2  --Initial release
---     02-29-2020  WGRIFFITH2  --nvl(sfrstcr.sfrstcr_grde_date, v_etl_date) AS grade_date,-- in case the grade date is null [it is possible - 2/29]
---     11-08-2021  WGRIFFITH2  --Adding ACD
---     03-15-2023  WGRIFFITH2  --adding output to insert_job_log
------------------------------------------------------------------------------------------------*/
END etl_aa_stufngrade_log_refresh; 

procedure etl_aa_rsbbzsrcefa_refresh (jobnumber number, processid varchar2, processname varchar2, inst varchar2, nmbr number) is
/* ************************************************************************** */
/* *********  LIBERTY UNIVERSITY - ANALYTICS AND DECISION SUPPORT ********* */
/* *********  OJBECT NAME: utl_d_aa.ETL_AA_RSBBZSRCEFA_refresh   ********* */
/* *********  DESCRIPTION: Table that pulls enrollment data by pidm and term. Historical terms locked  after completion ********* */
/* *********  CREATED BY: WGRIFFITH2                ********* */
/* *********  (See CHANGE LOG at bottom of file)          ********* */
/* ************************************************************************** */
--DECLARE
--- PARAMS
v_etl_date    DATE := SYSDATE;
v_msg         VARCHAR2(2000);
v_instance    VARCHAR2(50) := upper('ALL'); -- inst from the jams job; used for determining instance
v_partition    NUMBER := nmbr; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
v_mod         NUMBER := 5; -- number of partitions to be created

v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_aa_rsbbzsrcefa_refresh';
CURSOR c_terms IS
SELECT t.term_code,
       t.fa_proc_year,
       t.start_date,
       t.end_date,
       CASE
       WHEN substr(t.term_code, 5, 1) IN ('1', '2') THEN
        substr(t.term_code, 1, 4) || '20'
       WHEN substr(t.term_code, 5, 1) = '3' THEN
        substr(t.term_code, 1, 4) || '30'
       WHEN substr(t.term_code, 5, 1) = '4' THEN
        substr(t.term_code, 1, 4) || '40'
       ELSE
        t.term_code
       END AS period
  FROM zbtm.terms_by_group_v t
 WHERE 1 = 1
   AND SYSDATE < t.end_date + 21 -- Current AND future enrollment starting within the next 90 days
   AND t.start_date - 90 <= SYSDATE -- Current AND future enrollment starting within the next 90 days
   AND t.group_code IN ('STD', 'MED')
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
 v_msg         := 'DELETE (PENDING) - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
DELETE  FROM utl_d_aa.rsbbzsrcefa z
 WHERE z.rsbbzsrcefa_rectype = 'CEFA'
   AND z.rsbbzsrcefa_term_code = rec.term_code
   AND MOD(z.rsbbzsrcefa_pidm, v_mod) = v_partition;
v_count := SQL%ROWCOUNT;
-- DO NOT COMMIT HERE;
-- needs constant uptime
-- use dbms output after the delete - only for testing
 v_msg         := 'DELETE - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
INSERT INTO utl_d_aa.rsbbzsrcefa
(rsbbzsrcefa_rectype,
 rsbbzsrcefa_pidm,
 rsbbzsrcefa_id,
 rsbbzsrcefa_ssn,
 rsbbzsrcefa_socsec1,
 rsbbzsrcefa_aidy_code,
 rsbbzsrcefa_period,
 rsbbzsrcefa_term_code,
 rsbbzsrcefa_sfrstcr_ind,
 rsbbzsrcefa_rorstat_ind,
 rsbbzsrcefa_camp_code,
 rsbbzsrcefa_levl_code,
 rsbbzsrcefa_majr_code,
 rsbbzsrcefa_degc_code,
 rsbbzsrcefa_program,
 rsbbzsrcefa_styp_code,
 rsbbzsrcefa_progone,
 rsbbzsrcefa_plevone,
 rsbbzsrcefa_progtwo,
 rsbbzsrcefa_plevtwo,
 rsbbzsrcefa_gender,
 rsbbzsrcefa_ethn_code,
 rsbbzsrcefa_race_code,
 rsbbzsrcefa_oncred,
 rsbbzsrcefa_offcred,
 rsbbzsrcefa_totcred,
 rsbbzsrcefa_transhours,
 rsbbzsrcefa_insthours,
 rsbbzsrcefa_cumhours,
 rsbbzsrcefa_consorthours,
 rsbbzsrcefa_enrl_status,
 rsbbzsrcefa_level_,
 rsbbzsrcefa_stustat,
 rsbbzsrcefa_hsstat,
 rsbbzsrcefa_visa,
 rsbbzsrcefa_zip,
 rsbbzsrcefa_zip5,
 rsbbzsrcefa_stat_code,
 rsbbzsrcefa_cnty_code,
 rsbbzsrcefa_locdomi,
 rsbbzsrcefa_fips,
 rsbbzsrcefa_tuition,
 rsbbzsrcefa_birthye,
 rsbbzsrcefa_birthmo,
 rsbbzsrcefa_errsort,
 rsbbzsrcefa_activity_date,
 rsbbzsrcefa_ce_repper,
 rsbbzsrcefa_fa_repper,
 rsbbzsrcefa_user_id,
 rsbbzsrcefa_surrogate_id,
 rsbbzsrcefa_version,
 rsbbzsrcefa_data_origin,
 rsbbzsrcefa_vpdi_code)
SELECT DISTINCT 'CEFA' AS rsbbzsrcefa_rectype,
                spriden_pidm AS rsbbzsrcefa_pidm,
                spriden_id AS rsbbzsrcefa_id,
                substr(spbpers_ssn, 1, 9) AS rsbbzsrcefa_ssn,
                --substr(goradid_additional_id,1,9) AS RSBBZSRCEFA_socsec1,
                'XXXXXXXXX' AS rsbbzsrcefa_socsec1,
                rec.fa_proc_year AS rsbbzsrcefa_aidy_code,
                CASE
                WHEN substr(rec.term_code, 5, 1) IN ('1', '2') THEN
                 substr(rec.term_code, 1, 4) || '20'
                WHEN substr(rec.term_code, 5, 1) = '3' THEN
                 substr(rec.term_code, 1, 4) || '30'
                WHEN substr(rec.term_code, 5, 1) = '4' THEN
                 substr(rec.term_code, 1, 4) || '40'
                ELSE
                 NULL
                END AS rsbbzsrcefa_period,
                rec.term_code AS rsbbzsrcefa_term_code,
                nvl2(zsrregs.reg_pidm, 'Y', NULL) AS rsbbzsrcefa_sfrstcr_ind,
                nvl2(ror.rpratrm_pidm, 'Y', NULL) AS rsbbzsrcefa_rorstat_ind,
                sgbstdn_camp_code AS rsbbzsrcefa_camp_code,
                sgbstdn_levl_code AS rsbbzsrcefa_levl_code,
                sgbstdn_majr_code_1 AS rsbbzsrcefa_majr_code,
                sgbstdn_degc_code_1 AS rsbbzsrcefa_degc_code,
                nvl(sgbstdn_program_1, sgbstdn_majr_code_1 || '-' || sgbstdn_degc_code_1 || '-' || sgbstdn_camp_code) AS rsbbzsrcefa_program,
                zsrappl_styp_code AS rsbbzsrcefa_styp_code,
                nvl(stvmajr1.stvmajr_cipc_code, '000000') AS rsbbzsrcefa_progone,
                CASE
                WHEN (sgbstdn_majr_code_1 LIKE 'SPC%' OR sgbstdn_degc_code_1 = 'DPL')
                     AND roralgs_key_4 = 'UG' THEN
                 '00' --No Degree Sought (Undergraduate)
                WHEN (sgbstdn_majr_code_1 LIKE 'SPC%' OR sgbstdn_degc_code_1 = 'DPL')
                     AND sgbstdn_degc_code_1 IN ('MDV', 'JD', 'DO') THEN
                 '01' --No Degree Sought (First Professional)
                WHEN (sgbstdn_majr_code_1 LIKE 'SPC%' OR sgbstdn_degc_code_1 = 'DPL')
                     AND roralgs_key_4 = 'GR' THEN
                 '02' --No Degree Sought (Graduate)
                WHEN stvdegc1.stvdegc_acat_code = '21' THEN
                 '10' --Post Second. Cert/Dipl < 1 yr.
                WHEN stvdegc1.stvdegc_acat_code = '22' THEN
                 '15' --Post Second. Cert/Dipl >1 < 2
                WHEN stvdegc1.stvdegc_acat_code = '23' THEN
                 '20' --Associate Degree
                WHEN stvdegc1.stvdegc_acat_code IN ('24', '25') THEN
                 '40' --4 Year Baccalaureate Degree
                -- when stvdegc1.stvdegc_acat_code                          then '41' --5 Year Baccalaureate Degree
                -- when stvdegc1.stvdegc_acat_code                          then '42' --Bach's Lvl Student In Contin grad f/p pgm
                 WHEN stvdegc1.stvdegc_acat_code IN ('26', '27', '41') THEN
                  '55' --Postbaccalaureate Certificate
                 WHEN stvdegc1.stvdegc_acat_code = '31'
                      OR stvdegc1.stvdegc_code IN ('MDV', 'JD', 'DO') THEN
                  '60' --First-Professional Degree
                 WHEN stvdegc1.stvdegc_acat_code IN ('32', '42') THEN
                  '70' --Masters Degree
                 WHEN stvdegc1.stvdegc_acat_code = '43' THEN
                  '80' --Post Masters Certificate
                 WHEN stvdegc1.stvdegc_acat_code IN ('44', '45') THEN
                  '85' --Doctoral Degree/Post-Doctoral Award
                 WHEN stvdegc1.stvdegc_acat_code = '46' THEN
                  '80' --Post-Master's Degree
                ELSE
                 '00'
                END AS rsbbzsrcefa_plevone,
                CASE
                WHEN stvmajr1.stvmajr_cipc_code = stvmajr2.stvmajr_cipc_code THEN
                 '000000' --When same, update program 2 to '000000'
                ELSE
                 nvl(stvmajr2.stvmajr_cipc_code, '000000')
                END AS rsbbzsrcefa_progtwo,
                CASE
                WHEN stvmajr1.stvmajr_cipc_code = stvmajr2.stvmajr_cipc_code
                     AND substr(stvdegc1.stvdegc_acat_code, 1, 1) = '2' THEN
                 '00' --Same Major between Programs
                WHEN stvmajr1.stvmajr_cipc_code = stvmajr2.stvmajr_cipc_code
                     AND substr(stvdegc1.stvdegc_acat_code, 1, 1) = '3' THEN
                 '01' --Same Major between Programs
                WHEN stvmajr1.stvmajr_cipc_code = stvmajr2.stvmajr_cipc_code
                     AND substr(stvdegc1.stvdegc_acat_code, 1, 1) = '4' THEN
                 '02' --Same Major between Programs
                WHEN (sgbstdn_majr_code_2 LIKE 'SPC%' OR sgbstdn_degc_code_2 = 'DPL')
                     AND roralgs_key_4 = 'UG' THEN
                 '00' --No Degree Sought (Undergraduate)
                WHEN (sgbstdn_majr_code_2 LIKE 'SPC%' OR sgbstdn_degc_code_2 = 'DPL')
                     AND sgbstdn_degc_code_2 IN ('MDV', 'JD', 'DO') THEN
                 '01' --No Degree Sought (First Professional)
                WHEN (sgbstdn_majr_code_2 LIKE 'SPC%' OR sgbstdn_degc_code_2 = 'DPL')
                     AND roralgs_key_4 = 'GR' THEN
                 '02' --No Degree Sought (Graduate)
                WHEN stvdegc2.stvdegc_acat_code = '21' THEN
                 '10' --Post Second. Cert/Dipl < 1 yr.
                WHEN stvdegc2.stvdegc_acat_code = '22' THEN
                 '15' --Post Second. Cert/Dipl >1 < 2
                WHEN stvdegc2.stvdegc_acat_code = '23' THEN
                 '20' --Associate Degree
                WHEN stvdegc2.stvdegc_acat_code IN ('24', '25') THEN
                 '40' --4 Year Baccalaureate Degree
                -- when stvdegc2.stvdegc_acat_code                          then '41' --5 Year Baccalaureate Degree
                -- when stvdegc2.stvdegc_acat_code                          then '42' --Bach's Lvl Student In Contin grad f/p pgm
                 WHEN stvdegc2.stvdegc_acat_code IN ('26', '27', '41') THEN
                  '55' --Postbaccalaureate Certificate
                 WHEN stvdegc2.stvdegc_acat_code = '31'
                      OR stvdegc2.stvdegc_code IN ('MDV', 'JD', 'DO') THEN
                  '60' --First-Professional Degree
                 WHEN stvdegc2.stvdegc_acat_code IN ('32', '42') THEN
                  '70' --Masters Degree
                 WHEN stvdegc2.stvdegc_acat_code = '43' THEN
                  '80' --Post Masters Certificate
                 WHEN stvdegc2.stvdegc_acat_code IN ('44', '45') THEN
                  '85' --Doctoral Degree/Post-Doctoral Award
                 WHEN stvdegc2.stvdegc_acat_code = '46' THEN
                  '80' --Post-Master's Degree
                ELSE
                 '00'
                END AS rsbbzsrcefa_plevtwo,
                CASE
                WHEN spbpers_sex = 'M' THEN
                 '1'
                WHEN spbpers_sex = 'F' THEN
                 '2'
                ELSE
                 '4'
                END AS rsbbzsrcefa_gender,
                spbpers_ethn_code AS rsbbzsrcefa_ethn_code,
                substr(race.race_code, 1, 30) AS rsbbzsrcefa_race_code,
                nvl(zsrregs.res_hours, 0) AS rsbbzsrcefa_oncred /* Based on SFRSTCR */,
                nvl(zsrregs.dlp_hours, 0) AS rsbbzsrcefa_offcred /* Based on SFRSTCR */,
                nvl(zsrregs.term_credit_hr, 0) AS rsbbzsrcefa_totcred /* Based on SFRSTCR */,
                nvl(tgpa.transhours, 0) AS rsbbzsrcefa_transhours /* Based on SHRTGPA */,
                nvl(tgpa.insthours, 0) AS rsbbzsrcefa_insthours /* Based on SHRTGPA */,
                nvl(tgpa.cumhours, 0) AS rsbbzsrcefa_cumhours /* Based on SHRTGPA */,
                nvl(total_consort_hours, 0) AS rsbbzsrcefa_consorthours,
                CASE
                WHEN substr(rec.term_code, 5, 1) = '1' THEN
                 'PT' -- Not auto calculated for Winter
                WHEN zsrregs.term_credit_hr >= r1.rorcrhr_full_time_cr_hrs THEN
                 'FT'
                WHEN term_credit_hr < r1.rorcrhr_full_time_cr_hrs
                     AND term_credit_hr > 0 THEN
                 'PT'
                ELSE
                 'NA'
                END AS rsbbzsrcefa_enrl_status,
                CASE
                 WHEN (sgbstdn_majr_code_1 LIKE 'SPC%' OR sgbstdn_degc_code_1 = 'DPL')
                      AND roralgs_key_4 = 'UG' THEN
                  '90' --No Degree Sought (Undergraduate)
                 WHEN (sgbstdn_majr_code_1 LIKE 'SPC%' OR sgbstdn_degc_code_1 = 'DPL')
                      AND sorxref_edi_value IS NOT NULL THEN
                  '93' --No Degree Sought (First Professional)
                 WHEN (sgbstdn_majr_code_1 LIKE 'SPC%' OR sgbstdn_degc_code_1 = 'DPL')
                      AND roralgs_key_4 = 'GR' THEN
                  '95' --No Degree Sought (Graduate)
                 WHEN nvl(sorxref_banner_value, '.') = 'JD'
                      AND nvl(cumhours, 0) >= 90
                      OR nvl(sorxref_banner_value, '.') = 'DO'
                      AND nvl(cumhours, 0) >= 251.25
                      AND stvterm_ctlg_aidy.stvterm_fa_proc_yr <= '1415'
                      OR nvl(sorxref_banner_value, '.') = 'DO'
                      AND nvl(cumhours, 0) >= 251.25
                      AND stvterm_ctlg_aidy.stvterm_fa_proc_yr >= '1516' /* Update/Duplicate this line if standards change */
                      OR nvl(sorxref_banner_value, '.') = 'MDV'
                      AND nvl(cumhours, 0) >= 72 THEN
                  '64' --First Professional - 4th Year
                 WHEN nvl(sorxref_banner_value, '.') = 'JD'
                      AND nvl(cumhours, 0) >= 60
                      OR nvl(sorxref_banner_value, '.') = 'DO'
                      AND nvl(cumhours, 0) >= 127.25
                      AND stvterm_ctlg_aidy.stvterm_fa_proc_yr <= '1415'
                      OR nvl(sorxref_banner_value, '.') = 'DO'
                      AND nvl(cumhours, 0) >= 127.25
                      AND stvterm_ctlg_aidy.stvterm_fa_proc_yr >= '1516' /* Update/Duplicate this line if standards change */
                      OR nvl(sorxref_banner_value, '.') = 'MDV'
                      AND nvl(cumhours, 0) >= 48 THEN
                  '63' --First Professional - 3rd Year
                 WHEN nvl(sorxref_banner_value, '.') = 'JD'
                      AND nvl(cumhours, 0) >= 30
                      OR nvl(sorxref_banner_value, '.') = 'DO'
                      AND nvl(cumhours, 0) >= 60
                      AND stvterm_ctlg_aidy.stvterm_fa_proc_yr <= '1415'
                      OR nvl(sorxref_banner_value, '.') = 'DO'
                      AND nvl(cumhours, 0) >= 60
                      AND stvterm_ctlg_aidy.stvterm_fa_proc_yr >= '1516' /* Update/Duplicate this line if standards change */
                      OR nvl(sorxref_banner_value, '.') = 'MDV'
                      AND nvl(cumhours, 0) >= 24 THEN
                  '62' --First Professional - 2nd Year
                 WHEN nvl(sorxref_banner_value, '.') = 'JD'
                      AND nvl(cumhours, 0) < 30
                      OR nvl(sorxref_banner_value, '.') = 'DO'
                      AND nvl(cumhours, 0) < 60
                      AND stvterm_ctlg_aidy.stvterm_fa_proc_yr <= '1415'
                      OR nvl(sorxref_banner_value, '.') = 'DO'
                      AND nvl(cumhours, 0) < 60
                      AND stvterm_ctlg_aidy.stvterm_fa_proc_yr >= '1516' /* Update/Duplicate this line if standards change */
                      OR nvl(sorxref_banner_value, '.') = 'MDV'
                      AND nvl(cumhours, 0) < 24 THEN
                  '61' --First Professional - 1st Year
                 WHEN stvdegc1.stvdegc_acat_code = '44' THEN
                  '80' --Graduate Doctoral or Advanced
                 WHEN stvdegc1.stvdegc_acat_code IN ('41', '42') THEN
                  '70' --Graduate Master's
                WHEN stvdegc1.stvdegc_acat_code IN ('23', '24', '25')
                     AND nvl(cumhours, 0) >= 72 THEN
                 '42' --Senior
                WHEN stvdegc1.stvdegc_acat_code IN ('23', '24', '25')
                     AND nvl(cumhours, 0) BETWEEN 48 AND 71.999 THEN
                 '41' --Junior
                WHEN stvdegc1.stvdegc_acat_code IN ('23', '24', '25')
                     AND nvl(cumhours, 0) BETWEEN 24 AND 47.999 THEN
                 '22' --Sophomore
                WHEN stvdegc1.stvdegc_acat_code IN ('23', '24', '25')
                     AND (nvl(cumhours, 0) < 24 OR nvl(cumhours, 0) IS NULL) THEN
                 '21' --Freshman
                WHEN stvdegc1.stvdegc_acat_code = '22' THEN
                 '17' --Sophomore, Cert or Award Prog < 2 yrs
                WHEN stvdegc1.stvdegc_acat_code = '21' THEN
                 '16' --Freshman, Cert or Award Prog < 2 yrs
                ELSE
                 '00'
                END AS rsbbzsrcefa_level_
                /* ------------------------ */
                /* Big ol' party needed */,
                CASE
                WHEN zsrappl_sudb_code = 'N' THEN
                 '1' --New Student
                WHEN zsrappl_sudb_code = 'T' THEN
                 '2' --Transfer Student
                WHEN zsrappl_sudb_code = 'R' THEN
                 '4' --Readmit Student
                WHEN zsrappl_sudb_code = 'M' THEN
                 '5' --Student New to Program
                WHEN sgbstdn_degc_code_1 = 'DPL' THEN
                 '6' --Dual Enrolled (HS Taking College Courses)
                WHEN zsrappl_styp_code = 'N'
                     AND sgbstdn_levl_code IN ('IN', 'UG')
                     AND nvl(cumhours, 0) >= 72 /***REVIEW: transhours - nontranshours? ***/
                     AND nvl(transhours, 0) >= 24 THEN
                 '2' --Update: Students who are classified as new to transfer
                WHEN zsrappl_styp_code = 'N'
                     AND sgbstdn_levl_code IN ('IN', 'UG')
                     AND nvl(cumhours, 0) >= 72 /***REVIEW: nvl(cumhours,0) > nvl(transhours,0) (remove transhours?)***/
                     AND nvl(transhours, 0) < 24 THEN
                 '4' --Update: Students who are classified as new to readmit
                WHEN zsrappl_styp_code = 'N'
                     AND sgbstdn_levl_code NOT IN ('IN', 'UG', 'MD')
                     AND nvl(cumhours, 0) >= 24 THEN
                 '4' --Update: Students who are classified as new to readmit
                WHEN zsrappl_styp_code = 'N' THEN
                 '1' --New Student
                WHEN zsrappl_styp_code = 'T' THEN
                 '2' --Transfer Student
                WHEN zsrappl_styp_code = 'R' THEN
                 '4' --Readmit Student
                WHEN zsrappl_styp_code = 'M' THEN
                 '5' --Student New to Program
                ELSE
                 '3' --Continuing Student
                END AS rsbbzsrcefa_stustat,
                CASE
                WHEN sgbstdn_degc_code_1 = 'DPL'
                     OR hs_grad_date < trunc(stvterm_curr.stvterm_start_date - 365) THEN
                 '0'
                WHEN hs_grad_date >= trunc(stvterm_curr.stvterm_start_date - 120) THEN
                 '1'
                WHEN zsrappl_styp_code = 'N'
                     AND sgbstdn_levl_code IN ('IN', 'UG')
                     AND nvl(cumhours, 0) < 48
                     AND nvl(transhours, 0) < 30 THEN
                 '1'
                ELSE
                 '0'
                END AS rsbbzsrcefa_hsstat,
                CASE
                WHEN nvl(rcrapp1_citz_ind, 'X') = '1' THEN
                 '111' --US National
                WHEN nvl(rcrapp1_citz_ind, 'X') = '2' THEN
                 '222' --Permanent Resident Card
                WHEN nvl(rcrapp1_citz_ind, 'X') = '3' THEN
                 '333' --Nonresident alien
                /*   then '444' --Foreign student on non-US campus branch or off-site location */
                /*   then '555' --Foreign student taking online courses in their country */
                WHEN spbpers_citz_code = 'NE' /* Legal Perm Res */
                 THEN
                 '222'
                WHEN visa.gorvisa_pidm IS NOT NULL THEN
                 '333'
                WHEN spbpers_citz_code IN ('IL', 'NI') THEN
                 '333'
                ELSE
                 '111'
                END AS rsbbzsrcefa_visa,
                CASE
                WHEN nvl(rcrapp1_citz_ind, 'X') IN ('1', '2')
                     AND nvl(spraddr_zip5, '00000') <> '00000' THEN
                 rpad(REPLACE(spraddr_zip, '-', ''), 9, 0)
                WHEN nvl(rcrapp1_citz_ind, 'X') = '3' THEN
                 '000003333'
                WHEN spbpers_citz_code = 'NE' /* Perm Res */
                     AND nvl(spraddr_zip5, '00000') <> '00000' THEN
                 rpad(REPLACE(spraddr_zip, '-', ''), 9, 0)
                WHEN (gorvisa_pidm IS NOT NULL OR spbpers_citz_code IN ('IL', 'NI') -- wruminn added 8/21/15
                     OR ipeds_cde = '90') THEN
                 '000003333'
                WHEN nvl(spraddr_zip5, '00000') <> '00000' THEN
                 rpad(REPLACE(spraddr_zip, '-', ''), 9, 0)
                ELSE
                 '000002222'
                END AS rsbbzsrcefa_zip,
                spraddr_zip5 AS rsbbzsrcefa_zip5,
                stat_code AS rsbbzsrcefa_stat_code,
                cnty_code AS rsbbzsrcefa_cnty_code,
                CASE
                WHEN nvl(rcrapp1_citz_ind, 'X') IN ('1', '2')
                     AND ipeds_cde = '51'
                     AND substr(cnty_code, 1, 2) = '51' THEN
                 lpad(substr(cnty_code, 3, 3), 4, '0000')
                WHEN nvl(rcrapp1_citz_ind, 'X') IN ('1', '2')
                     AND ipeds_cde NOT IN ('51', '57', '90') THEN
                 '10' || ipeds_cde
                WHEN nvl(rcrapp1_citz_ind, 'X') = '3' THEN
                 '1090'
                WHEN spbpers_citz_code = 'NE'
                     AND ipeds_cde = '51'
                     AND substr(cnty_code, 1, 2) = '51' THEN
                 lpad(substr(cnty_code, 3, 3), 4, '0000')
                WHEN spbpers_citz_code = 'NE'
                     AND ipeds_cde NOT IN ('51', '57', '90') THEN
                 '10' || ipeds_cde
                WHEN (gorvisa_pidm IS NOT NULL OR spbpers_citz_code IN ('IL', 'NI') -- wruminn added 8/21/2015
                     OR ipeds_cde = '90') THEN
                 '1090'
                WHEN stat_code IN ('AA', 'AE', 'AP') THEN
                 '1100'
                WHEN ipeds_cde = '51'
                     AND substr(cnty_code, 1, 2) = '51' THEN
                 lpad(substr(cnty_code, 3, 3), 4, '0000')
                WHEN ipeds_cde NOT IN ('51', '57', '90') THEN
                 '10' || ipeds_cde
                WHEN ipeds_cde = '51' THEN
                 '0902' /* In Virginia, Unknown */
                ELSE
                 '1057' /* Outside Virgina, in US, Unknown */
                END AS rsbbzsrcefa_locdomi,
                CASE
                WHEN stat_code IS NULL
                     AND gorvisa_pidm IS NOT NULL THEN
                 '90'
                ELSE
                 nvl(ipeds_cde, '57')
                END AS rsbbzsrcefa_fips /* Not really a FIPS, an IPEDS State Code */,
                nvl2(robusdf_value_121, upper(substr(robusdf_value_121, 1, 1)), 'Z') AS rsbbzsrcefa_tuition,
                nvl(to_char(spbpers.spbpers_birth_date, 'YYYY'), '0000') AS rsbbzsrcefa_birthye,
                nvl(to_char(spbpers.spbpers_birth_date, 'MM'), '00') AS rsbbzsrcefa_birthmo,
                '12' AS rsbbzsrcefa_errsort --As of 29-MAY-2012, used to indicate Trailing Summer
               ,
                SYSDATE AS rsbbzsrcefa_activity_date,
                CASE
                WHEN substr(rec.term_code, 5, 1) = '4' THEN
                 '2'
                WHEN substr(rec.term_code, 5, 1) IN ('1', '2') THEN
                 '4'
                WHEN substr(rec.term_code, 5, 1) = '3' THEN
                 '1'
                ELSE
                 'X'
                END AS rsbbzsrcefa_ce_repper,
                CASE
                WHEN substr(rec.term_code, 5, 1) = '3' THEN
                 '1'
                ELSE
                 '5'
                END AS rsbbzsrcefa_fa_repper,
                upper(USER) AS rsbbzsrcefa_user_id,
                NULL,
                NULL,
                NULL,
                NULL
  FROM spriden
  LEFT JOIN spbpers
    ON spbpers_pidm = spriden_pidm
  LEFT JOIN (SELECT sfrstcr_pidm AS reg_pidm,
                    COUNT(CASE
                          WHEN sfrstcr_credit_hr > 0 THEN
                           1
                          ELSE
                           NULL
                          END) crdt_hr_classes,
                    COUNT(CASE
                          WHEN sfrstcr_credit_hr = 0 THEN
                           1
                          ELSE
                           NULL
                          END) non_crdt_hr_classes,
                    SUM(CASE
                        WHEN sfrstcr_camp_code = 'R' THEN
                         sfrstcr_credit_hr
                        ELSE
                         NULL
                        END) res_hours,
                    SUM(CASE
                        WHEN sfrstcr_camp_code = 'D' THEN
                         sfrstcr_credit_hr
                        ELSE
                         NULL
                        END) dlp_hours,
                    SUM(sfrstcr_credit_hr) AS term_credit_hr,
                    trunc(MIN(sfrstcr_add_date)) reg_add_date
               FROM sfrstcr
              JOIN ssbsect
                 ON ssbsect_term_code = sfrstcr_term_code
                AND ssbsect_crn = sfrstcr_crn
                AND ssbsect_subj_code <> 'NEWS'
              JOIN stvrsts
                 ON stvrsts_code = sfrstcr_rsts_code
                AND stvrsts_incl_sect_enrl = 'Y'
              JOIN roralgs
                 ON roralgs_aidy_code = greatest(rec.fa_proc_year, '1415')
                AND roralgs_key_1 = 'SCHEV'
                AND roralgs_key_2 = 'VALID_LEVL'
                AND roralgs_key_3 = sfrstcr_levl_code
                AND roralgs_amt = 1
              WHERE sfrstcr_term_code > '200720'
                AND sfrstcr_term_code = rec.term_code
                AND MOD(sfrstcr_pidm, v_mod) = v_partition
              GROUP BY sfrstcr_pidm
             HAVING SUM(sfrstcr_credit_hr) > 0 -- As of 18-APR-2012, must have Hours per Larry Shackleton
             UNION ALL
             SELECT shrtckn_pidm AS reg_pidm,
                    COUNT(CASE
                          WHEN shrtckg_credit_hours > 0 THEN
                           1
                          ELSE
                           NULL
                          END) crdt_hr_classes,
                    COUNT(CASE
                          WHEN shrtckg_credit_hours = 0 THEN
                           1
                          ELSE
                           NULL
                          END) non_crdt_hr_classes,
                    SUM(CASE
                        WHEN shrtckn_camp_code = 'R' THEN
                         shrtckg_credit_hours
                        ELSE
                         0
                        END) res_hours /* note: this is 0, above is null */,
                    SUM(CASE
                        WHEN shrtckn_camp_code = 'D' THEN
                         shrtckg_credit_hours
                        ELSE
                         0
                        END) dlp_hours /* note: this is 0, above is null */,
                    SUM(shrtckg_credit_hours) AS term_credit_hr,
                    trunc(MIN(shrtckn_reg_start_date)) AS reg_add_date
               FROM shrtckn
              JOIN shrtckg s1
                 ON s1.shrtckg_pidm = shrtckn_pidm
                AND s1.shrtckg_term_code = shrtckn_term_code
                AND s1.shrtckg_tckn_seq_no = shrtckn_seq_no
                AND s1.shrtckg_seq_no = (SELECT MAX(s2.shrtckg_seq_no)
                                           FROM shrtckg s2
                                          WHERE s2.shrtckg_pidm = s1.shrtckg_pidm
                                            AND s2.shrtckg_term_code = s1.shrtckg_term_code
                                            AND s2.shrtckg_tckn_seq_no = s1.shrtckg_tckn_seq_no)
              JOIN shrtckl
                 ON shrtckl_pidm = shrtckn_pidm
                AND shrtckl_term_code = shrtckn_term_code
                AND shrtckl_tckn_seq_no = shrtckn_seq_no
              JOIN roralgs
                 ON roralgs_aidy_code = greatest(rec.fa_proc_year, '1415')
                AND roralgs_key_1 = 'SCHEV'
                AND roralgs_key_2 = 'VALID_LEVL'
                AND roralgs_key_3 = shrtckl_levl_code
                AND roralgs_amt = 1
              WHERE shrtckn_term_code <= '200720'
                AND shrtckn_term_code = rec.term_code
                AND MOD(shrtckn_pidm, v_mod) = v_partition
              GROUP BY shrtckn_pidm
             HAVING SUM(shrtckg_credit_hours) > 0 -- As of 18-APR-2012, must have Hours per Larry Shackleton
             ) zsrregs
    ON zsrregs.reg_pidm = spriden_pidm
 JOIN sgbstdn
    ON sgbstdn_pidm = spriden_pidm
   AND sgbstdn_term_code_eff = (SELECT MAX(d.sgbstdn_term_code_eff)
                                  FROM sgbstdn d
                                 WHERE d.sgbstdn_pidm = sgbstdn.sgbstdn_pidm
                                   AND d.sgbstdn_term_code_eff <= rec.term_code)
  LEFT JOIN stvterm stvterm_ctlg_aidy
    ON stvterm_ctlg_aidy.stvterm_code = sgbstdn.sgbstdn_term_code_ctlg_1
 JOIN stvterm stvterm_curr
    ON stvterm_curr.stvterm_code = rec.term_code
  LEFT JOIN sorxref
    ON sorxref_banner_value = sgbstdn_degc_code_1
   AND sorxref_xlbl_code = 'STVDEGC'
   AND sorxref_edi_value LIKE 'SCHEV_FPROF%'
  JOIN roralgs
     ON roralgs_aidy_code = greatest(rec.fa_proc_year, '1415')
    AND roralgs_key_1 = 'SCHEV'
    AND roralgs_key_2 = 'VALID_LEVL'
    AND roralgs_key_3 = CASE
        WHEN sgbstdn_levl_code = 'AC' THEN
         'UG'
        ELSE
         sgbstdn_levl_code
        END
    AND roralgs_amt = 1
   JOIN rorcrhr r1
     ON r1.rorcrhr_levl_code = CASE
        WHEN sgbstdn_levl_code = 'AC' THEN
         'UG'
        ELSE
         sgbstdn_levl_code
        END
    AND r1.rorcrhr_period = greatest('200640',CASE
           WHEN substr(rec.term_code, 5, 1) = '1' THEN
            substr(rec.term_code, 1, 4) || '2' || substr(rec.term_code, 6, 1)
           ELSE
            rec.term_code
           END)
  LEFT JOIN stvmajr stvmajr1
    ON stvmajr1.stvmajr_code = sgbstdn_majr_code_1
  LEFT JOIN stvmajr stvmajr2
    ON stvmajr2.stvmajr_code = sgbstdn_majr_code_2
  LEFT JOIN stvdegc stvdegc1
    ON stvdegc1.stvdegc_code = sgbstdn_degc_code_1
  LEFT JOIN stvdegc stvdegc2
    ON stvdegc2.stvdegc_code = sgbstdn_degc_code_2
  LEFT JOIN (SELECT spraddr_pidm,
                    spraddr_atyp_code,
                    spraddr_seqno,
                    spraddr_zip,
                    substr(spraddr_zip, 1, 5) AS spraddr_zip5,
                    spraddr_natn_code AS natn_code,
                    nvl(spraddr_cnty_code, '00000') AS cnty_code,
                    spraddr_stat_code AS stat_code,
                    stvstat_ipeds_cde AS ipeds_cde,
                    rank() OVER ( PARTITION BY spraddr_pidm ORDER BY CASE WHEN ( substr(nvl(spraddr_zip, '00000'), 1, 5) = '00000' OR spraddr_stat_code IS NULL ) THEN '2' ELSE '1' END, decode(spraddr.spraddr_atyp_code, 'LP', 3, 'AP', 2, 'MA', 1, 0) DESC, spraddr_activity_date DESC, rownum ) AS addr_rank
               FROM spraddr
               LEFT JOIN stvstat
                 ON stvstat_code = spraddr_stat_code
              WHERE regexp_like(substr(spraddr_zip, 1, 5), '^[[:digit:]]{5}$')
                AND MOD(spraddr_pidm, v_mod) = v_partition
                AND spraddr_atyp_code IN ('LP', 'AP', 'MA')
                AND nvl(spraddr_from_date, to_date('01-JAN-1900', 'DD-MON-YYYY')) <= rec.end_date
                AND nvl(spraddr_to_date, to_date('01-JAN-2099', 'DD-MON-YYYY')) >= rec.start_date) zsraddr
    ON zsraddr.spraddr_pidm = spriden_pidm
   AND zsraddr.addr_rank = 1
  LEFT JOIN (SELECT DISTINCT rpratrm_pidm
               FROM rpratrm
              WHERE rpratrm_period = rec.period
                AND MOD(rpratrm_pidm, v_mod) = v_partition
                AND nvl(rpratrm_paid_amt, 0) > 0
              GROUP BY rpratrm_pidm) ror
    ON ror.rpratrm_pidm = spriden_pidm
  LEFT JOIN (SELECT gorprac_pidm,
                    listagg(gorprac_race_cde, ',') within GROUP(ORDER BY gorprac_race_cde) AS race_code
               FROM gorprac
              WHERE 1 = 1
                AND MOD(gorprac_pidm, v_mod) = v_partition
              GROUP BY gorprac_pidm) race
    ON race.gorprac_pidm = spriden_pidm
--LEFT JOIN goradid ON goradid_pidm = spriden_pidm AND goradid_adid_code = 'VCI1'
  LEFT JOIN (SELECT saradap_pidm AS zsrappl_pidm,
                    sgbuser_sudb_code AS zsrappl_sudb_code,
                    saradap_styp_code AS zsrappl_styp_code,
                    saradap_levl_code AS zsrappl_levl_code,
                    rank() over(PARTITION BY saradap_pidm ORDER BY trunc(saradap_appl_date) DESC, saradap_appl_no DESC) AS zsrappl_rank
               FROM saradap
               LEFT JOIN sgbuser
                 ON sgbuser_pidm = saradap_pidm
                AND sgbuser_term_code = saradap_term_code_entry
              WHERE substr(saradap_term_code_entry, 1, 5) IN (substr(rec.term_code, 1, 5), CASE WHEN saradap_camp_code = 'R' AND substr(rec.term_code, 5, 1) = '4' THEN substr(rec.term_code, 1, 4) || '3' ELSE NULL END)
                AND MOD(saradap_pidm, v_mod) = v_partition
                AND saradap_apst_code = 'D') zsrappl
    ON zsrappl.zsrappl_pidm = spriden_pidm
   AND zsrappl.zsrappl_levl_code = sgbstdn_levl_code
   AND zsrappl.zsrappl_rank = 1
  LEFT JOIN (SELECT DISTINCT gorvisa_pidm
               FROM gorvisa
              JOIN stvvtyp
                 ON stvvtyp_code = gorvisa_vtyp_code
                AND nvl(stvvtyp_non_res_ind, 'N') = 'Y'
              JOIN stvterm
                 ON stvterm_code = rec.term_code
              WHERE nvl(gorvisa_visa_start_date, to_date('01-JAN-1900', 'DD-MON-YYYY')) <= stvterm_end_date
                AND nvl(gorvisa_visa_expire_date, to_date('31-DEC-2099', 'DD-MON-YYYY')) >= stvterm_start_date
                AND MOD(gorvisa_pidm, v_mod) = v_partition) visa
    ON visa.gorvisa_pidm = spriden_pidm
  LEFT JOIN (SELECT shrtgpa_pidm,
                    shrtgpa_levl_code,
                    SUM(CASE
                        WHEN shrtgpa_gpa_type_ind = 'T' THEN
                         shrtgpa_hours_earned
                        ELSE
                         0
                        END) AS transhours,
                    SUM(CASE
                        WHEN shrtgpa_gpa_type_ind = 'I' THEN
                         shrtgpa_hours_earned
                        ELSE
                         0
                        END) AS insthours,
                    SUM(shrtgpa_hours_earned) AS cumhours
               FROM shrtgpa
              WHERE shrtgpa_term_code <= rec.term_code
                AND MOD(shrtgpa_pidm, v_mod) = v_partition
              GROUP BY shrtgpa_pidm,
                       shrtgpa_levl_code) tgpa
    ON tgpa.shrtgpa_pidm = spriden_pidm
   AND tgpa.shrtgpa_levl_code = sgbstdn_levl_code
  LEFT JOIN robusdf
    ON robusdf_pidm = spriden_pidm
   AND robusdf_aidy_code = rec.fa_proc_year
  LEFT JOIN (SELECT rorenrl_pidm,
                    rorenrl_term_code,
                    SUM(rorenrl_finaid_credit_hr) AS total_consort_hours
               FROM rorenrl
              WHERE rorenrl_term_code = rec.term_code
                AND MOD(rorenrl_pidm, v_mod) = v_partition
                AND rorenrl_finaid_credit_hr > 0
                AND rorenrl_enrr_code = 'REPEAT'
              GROUP BY rorenrl_pidm,
                       rorenrl_term_code) consortium
    ON consortium.rorenrl_pidm = spriden_pidm
   AND consortium.rorenrl_term_code = rec.term_code
  LEFT JOIN (SELECT hs.sorhsch_pidm,
                    hs.sorhsch_sbgi_code,
                    trunc(hs.hs_grad_date) AS hs_grad_date,
                    hs.sorhsch_rank
               FROM (SELECT DISTINCT sorhsch_pidm,
                                     sorhsch_sbgi_code,
                                     sorhsch_graduation_date AS hs_grad_date,
                                     rank() OVER ( PARTITION BY sorhsch_pidm ORDER BY CASE WHEN sorhsch_sbgi_code = '010002' THEN 0 ELSE 1 END DESC /* Self Certification Form */ , CASE WHEN sorhsch_sbgi_code = 'A01072' THEN 0 ELSE 1 END DESC /* High School (International) */ , nvl(sorhsch_graduation_date, to_date('01-JAN-1901','DD-MON-YYYY')) DESC, nvl(sorhsch_gpa, 0) DESC, rownum ) AS sorhsch_rank
                       FROM sorhsch
                      WHERE sorhsch_sbgi_code <> 'B99999' /* Final High School Transcript */
                        AND MOD(sorhsch_pidm, v_mod) = v_partition) hs) sorhsch
    ON sorhsch_pidm = spriden_pidm
   AND sorhsch_rank = 1
  LEFT JOIN (SELECT rcrapp1_pidm,
                    rcrapp1_aidy_code,
                    rcrapp1_citz_ind
               FROM rcrapp1
              WHERE rcrapp1_curr_rec_ind = 'Y'
                AND MOD(rcrapp1_pidm, v_mod) = v_partition
                AND rcrapp1_infc_code = 'EDE'
                AND rcrapp1_aidy_code = rec.fa_proc_year) rcrapp
    ON rcrapp.rcrapp1_pidm = spriden_pidm
 WHERE spriden_change_ind IS NULL
   AND spriden_entity_ind = 'P' /* Person */
   AND spriden_id LIKE 'L%'
   AND MOD(spriden_pidm, v_mod) = v_partition
   AND (zsrregs.reg_pidm IS NOT NULL /* Has courses */
       OR substr(rec.term_code, 5, 1) IN ('4', '2', '3') /* Fall, Spring, or Summer */
       AND ror.rpratrm_pidm IS NOT NULL /* Has financial aid, Winter does not have consortium hours */
       );
v_count := SQL%ROWCOUNT;
IF v_count > 0 THEN
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'DELETE/INSERT - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
ELSE
ROLLBACK;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'DELETE/INSERT - ' || rec.term_code || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
END IF;
end loop; -- c_terms
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
VERSION DATE    USERNAME  UPDATES
1.0   09-18-2015  WGRIFFITH2  --Initial release
1.1   09-25-2015  WGRIFFITH2  --Fixed casting for nvl(sorhsch_graduation_date, to_date('01-01-1901','mm-dd-yyyy'))
1.2   10-09-2015  WGRIFFITH2  --Filling in gaps for null program codes with major-degc-camp
1.3   01-13-2016  WGRIFFITH2  --substr(spbpers_ssn,1,9) AS RSBBZSRCEFA_SSN and substr(goradid_additional_id,1,9)
2.0   07-15-2016  WGRIFFITH2  --Adding look for future term enrollment for advising purposes
2.1   08-31-2016  WGRIFFITH2  --Including Academy level students in the table so course rosters in continuation probability model do not look incorrect
3.0   09-25-2017  WGRIFFITH2  --Adding global temp table to help with refresh
3.1   11-16-2017  WGRIFFITH2  --Only pulling open/future terms 90 days out
3.2   04-25-2017  WGRIFFITH2  --Adding exception for duplicate values
3.3   07-02-2019  WGRIFFITH2  --Removing the GTT
---     03-15-2023  WGRIFFITH2  --adding output to insert_job_log
---     08-09-2023  WGRIFFITH2  --adding in parallels to make things run faster and take smaller bites
---     09-25-2023  WGRIFFITH2  --switch out the join to rorcrhr & roralgs per Matt Peele
------------------------------------------------------------------------------------------------*/
END etl_aa_rsbbzsrcefa_refresh; --

procedure etl_aa_embbsbgiiatt_merge (jobnumber number, processid varchar2, processname varchar2) is
--DECLARE
/*--------------------------------------------CHANGE LOG----------------------------------------
VERSION DATE    USERNAME  UPDATES
1.0   02-06-2014  sawaddy     --Initial release
                --Purpose: This is an institute attribute table for STVSBGI for storing custom metadata for management purposes.  This process retrieves info from SORBCMT.
2.0   03-07-2014  wayates     --Integrated Reorganization tag
3.0   08-27-2020  wayates   --Converted to Full Join DELETE, INSERT, MODIFY Cursor Approach
                --The Merge Into solution wasn't handling deletes.
3.1   10-01-2020  wgriffith2  --DEFAULT NULL ON conversion error
3.2   05-13-2021  wayates   --Patch attribute_end_date due to final ";" entries
4.0   06-11-2021  wayates   --Removed ORA_HASH and changed to column comparison technique
5.0   06-24-2024  wayates   --Alternate Address type data has become formatted in JSON; new parsing rules added.
6.0   09-10-2024  wayates   --Reorganization type data has become formatted in JSON; new parsing rules added.
------------------------------------------------------------------------------------------------*/
job_start_time date := sysdate;
insct          int := 0;
updct          int := 0;
delct          int := 0;
newct          int := 0;
modct          int := 0;
error_key      varchar2(32000);
recs           int := 0;
cursor c1 is
select *
  from (select tblnew.stvsbgi_code,
               tblnew.seqno,
               tblnew.attribute_type,
               tblnew.attribute_name,
               tblnew.attribute_value,
               tblnew.attribute_start_date,
               tblnew.attribute_end_date,
               tblnew.active_ind,
               tblnew.create_date,
               tblnew.modified_date,
               tblnew.user_id,
               tblold.stvsbgi_code         as o_stvsbgi_code,
               tblold.seqno                as o_seqno,
               tblold.attribute_type       as o_attribute_type,
               tblold.attribute_name       as o_attribute_name,
               tblold.attribute_value      as o_attribute_value,
               tblold.attribute_start_date as o_attribute_start_date,
               tblold.attribute_end_date   as o_attribute_end_date,
               tblold.active_ind           as o_active_ind,
               tblold.create_date          as o_create_date,
               tblold.modified_date        as o_modified_date,
               tblold.user_id              as o_user_id
          from (select stvsbgi_code,
             sorbcmt_seqno seqno,
             case when substr(sorbcmt_comment, 1, instr(sorbcmt_comment, ':')) like '%Alternate Address:%'
                 and trim(substr(sorbcmt_comment, instr(sorbcmt_comment, ';') + 1, instr(sorbcmt_comment, ':', 1, 2) - instr(sorbcmt_comment, ';'))) = 'Address Type:'
              then trim(substr(sorbcmt_comment, instr(sorbcmt_comment, ':', 1, 2) + 1, length(sorbcmt_comment) - instr(sorbcmt_comment, ':', 1, 2)))
              when substr(sorbcmt_comment, 1, instr(sorbcmt_comment, ':')) = 'Alternate Address (JSON):'
              then json_value(trim(substr(sorbcmt_comment,26)),'$.address_type')
              when substr(sorbcmt_comment, 1, instr(sorbcmt_comment, ':')) like '%Reorganization:%'
              then substr(sorbcmt_comment, instr(sorbcmt_comment, ':') + 2, instr(sorbcmt_comment, ';') - instr(sorbcmt_comment, ':') - 2)
              when substr(sorbcmt_comment, 1, instr(sorbcmt_comment, ':')) like '%Reorganization (JSON):%'
              then json_value(trim(substr(sorbcmt_comment,23)),'$.reorganization_type')
              else null
             end attribute_type,
             replace(substr(sorbcmt_comment, 1, instr(sorbcmt_comment, ':') - 1),' (JSON)','') attribute_name,
             case when substr(sorbcmt_comment, 1, instr(sorbcmt_comment, ':')) like '%Reorganization:%'
                 and trim(substr(sorbcmt_comment, instr(sorbcmt_comment, ';') + 1, instr(sorbcmt_comment, ':', 1, 2) - instr(sorbcmt_comment, ';'))) = 'Details:'
              then trim(substr(sorbcmt_comment, instr(sorbcmt_comment, ':', 1, 2) + 1, length(sorbcmt_comment) - instr(sorbcmt_comment, ':', 1, 2)))
              when substr(sorbcmt_comment, 1, instr(sorbcmt_comment, ':')) like '%Reorganization (JSON):%'
              then r.reorg_comment
              when substr(sorbcmt_comment, 1, instr(sorbcmt_comment, ':')) = 'Alternate Address (JSON):'
              then json_value(trim(substr(sorbcmt_comment,26)),'$.address.street1')||
                 case when json_value(trim(substr(sorbcmt_comment,26)),'$.address.street2') is null then null else ', '||json_value(trim(substr(sorbcmt_comment,26)),'$.address.street2') end||
                 case when json_value(trim(substr(sorbcmt_comment,26)),'$.address.street3') is null then null else ', '||json_value(trim(substr(sorbcmt_comment,26)),'$.address.street3') end||
                 case when json_value(trim(substr(sorbcmt_comment,26)),'$.address.city') is null then null else ', '||json_value(trim(substr(sorbcmt_comment,26)),'$.address.city') end||
                 case when json_value(trim(substr(sorbcmt_comment,26)),'$.address.state_code') is null then null else ', '||json_value(trim(substr(sorbcmt_comment,26)),'$.address.state_code') end||
                 case when json_value(trim(substr(sorbcmt_comment,26)),'$.address.zip_code') is null then null else ' '||json_value(trim(substr(sorbcmt_comment,26)),'$.address.zip_code') end||
                 case when json_value(trim(substr(sorbcmt_comment,26)),'$.address.nation_code') is null then null else ', '||json_value(trim(substr(sorbcmt_comment,26)),'$.address.nation_code') end
              when instr(sorbcmt_comment, ';') = 0
              then substr(sorbcmt_comment, instr(sorbcmt_comment, ':') + 2)
              else substr(sorbcmt_comment, instr(sorbcmt_comment, ':') + 2, instr(sorbcmt_comment, ';') - instr(sorbcmt_comment, ':') - 2)
             end attribute_value,
             case when substr(sorbcmt_comment, 1, instr(sorbcmt_comment, ':')) = 'Formerly Named:'
                 and trim(substr(sorbcmt_comment, instr(sorbcmt_comment, ';') + 1, instr(sorbcmt_comment, ':', 1, 2) - instr(sorbcmt_comment, ';'))) = 'Begin Date:'
              then to_date(trim(substr(sorbcmt_comment, instr(sorbcmt_comment, ':', 1, 2) + 1, instr(sorbcmt_comment, ';', 1, 2) - instr(sorbcmt_comment, ':', 1, 2) - 1))
                     default null on conversion error, 'mm/dd/yyyy')
              else null
             end attribute_start_date,
             case when substr(sorbcmt_comment, 1, instr(sorbcmt_comment, ':')) = 'Formerly Named:'
                 and trim(substr(sorbcmt_comment, instr(sorbcmt_comment, ';', 1, 2) + 1, instr(sorbcmt_comment, ':', 1, 3) - instr(sorbcmt_comment, ';', 1, 2))) = 'End Date:'
              then to_date(trim(replace(substr(sorbcmt_comment, instr(sorbcmt_comment, ':', 1, 3) + 2, length(sorbcmt_comment) - instr(sorbcmt_comment, ':', 1, 3)),';',''))
                     default null on conversion error, 'mm/dd/yyyy')
              else null
             end attribute_end_date,
             'Y' active_ind,
             sorbcmt_activity_date create_date,
             sorbcmt_activity_date modified_date,
             'syncprocess' user_id
        from sorbcmt
        join stvsbgi
          on stvsbgi_code = sorbcmt_sbgi_code
        left join (select sorbcmt_sbgi_code reorg_sbgi_code, sorbcmt_seqno reorg_sorbcmt_seqno,
                  trim(listagg(case when n.code is not null then '(' else null end||n.code||case when n.code is not null then ') ' else null end||
                  n.name||
                  case when n.established is not null then ' (Est. ' else null end||n.established||case when n.established is not null then ')' else null end||
                  case when n.street1 is not null then ' ' else null end||n.street1||case when n.street1 is not null then ',' else null end||
                  case when n.street2 is not null then ' ' else null end||n.street2||case when n.street2 is not null then ',' else null end||
                  case when n.street3 is not null then ' ' else null end||n.street3||case when n.street3 is not null then ',' else null end||
                  case when n.city is not null then ' ' else null end||n.city||case when n.city is not null then ',' else null end||
                  case when n.state_code is not null then ' ' else null end||n.state_code||
                  case when n.zip_code is not null then ' ' else null end||n.zip_code||
                  case when n.nation_code is not null then ', ' else null end||n.nation_code||
                  case when coalesce(n.street1,n.street2,n.street3,n.city,n.state_code,n.zip_code,n.nation_code) is not null then ';' else null end||
                  case when n.phone is not null then ' (' else null end||n.phone||case when n.phone is not null then ');' else null end||
                  case when n.url is not null then ' ' else null end||n.url||case when n.url is not null then ';' else null end||
                  case when n.note is not null then ' (' else null end||n.note||case when n.note is not null then ');' else null end,'; ') within group (order by n.rec_num)||
                  case when n.reorg_date is not null then ' ' else null end||n.reorg_date||case when n.reorg_date is not null then ';' else null end) as reorg_comment
               from sorbcmt c,
               json_table(trim(substr(sorbcmt_comment,23)),
                    '$.details[*]'
                    columns(organizations varchar2 (4000) path '$.organizations',
                        reorg_date varchar2 (4000) path '$.reorg_date',
                        nested path '$.organizations[*]'
                        columns(rec_num varchar2(4000) path '$.rec_num',
                            code varchar2(4000) path '$.code',
                            name varchar2(4000) path '$.name',
                            established varchar2(4000) path '$.established',
                            street1 varchar2(4000) path '$.street1',
                            street2 varchar2(4000) path '$.street2',
                            street3 varchar2(4000) path '$.street3',
                            city varchar2(4000) path '$.city',
                            state_code varchar2(4000) path '$.state_code',
                            zip_code varchar2(4000) path '$.zip_code',
                            nation_code varchar2(4000) path '$.nation_code',
                            phone varchar2(4000) path '$.phone',
                            url varchar2(4000) path '$.url',
                            note varchar2(4000) path '$.note'))) n
               where sorbcmt_comment like '%Reorganization (JSON):%'
               group by sorbcmt_sbgi_code, sorbcmt_seqno, n.reorg_date) r
             on r.reorg_sbgi_code = sorbcmt_sbgi_code
            and r.reorg_sorbcmt_seqno = sorbcmt_seqno
        where instr(sorbcmt_comment, ':') > 0
          and (sorbcmt_comment like '%Address Type:%' or sorbcmt_comment like '%Alternate Address:%' or sorbcmt_comment like '%Alternate Address (JSON):%' or sorbcmt_comment like '%Alternatively Named:%' or
             --sorbcmt_comment like '%Begin Date:%' or
             sorbcmt_comment like '%Campus Includes:%' or sorbcmt_comment like '%Campus Includes (JSON):%' or sorbcmt_comment like '%Email:%' or
             --sorbcmt_comment like '%End Date:%' or
             sorbcmt_comment like '%Fax:%' or sorbcmt_comment like '%Formerly Named:%' or sorbcmt_comment like '%Full Name:%' or
             sorbcmt_comment like '%Reorganization:%' or sorbcmt_comment like '%Reorganization (JSON):%' or sorbcmt_comment like '%Sub-Titled:%')) tblnew
          full join utl_d_aa.embbsbgiiatt tblold
         on tblold.stvsbgi_code = tblnew.stvsbgi_code
        and tblold.seqno = tblnew.seqno)
 where (stvsbgi_code is null and o_stvsbgi_code is not null)
    or (stvsbgi_code is not null and o_stvsbgi_code is null)
    or ((attribute_type<>o_attribute_type or (attribute_type is null and o_attribute_type is not null) or (attribute_type is not null and o_attribute_type is null)) or
    (attribute_name<>o_attribute_name or (attribute_name is null and o_attribute_name is not null) or (attribute_name is not null and o_attribute_name is null)) or
    (attribute_value<>o_attribute_value or (attribute_value is null and o_attribute_value is not null) or (attribute_value is not null and o_attribute_value is null)) or
    (attribute_start_date<>o_attribute_start_date or (attribute_start_date is null and o_attribute_start_date is not null) or (attribute_start_date is not null and o_attribute_start_date is null)) or
    (attribute_end_date<>o_attribute_end_date or (attribute_end_date is null and o_attribute_end_date is not null) or (attribute_end_date is not null and o_attribute_end_date is null)) or
    (active_ind<>o_active_ind or (active_ind is null and o_active_ind is not null) or (active_ind is not null and o_active_ind is null)));
c1fmt c1%rowtype;
begin
  open c1;
  fetch c1 into c1fmt;
  while c1%found
    loop
    --Deleted Record
    if c1fmt.stvsbgi_code is null and c1fmt.o_stvsbgi_code is not null then
      delete from utl_d_aa.embbsbgiiatt
      where stvsbgi_code = c1fmt.o_stvsbgi_code
        and seqno = c1fmt.o_seqno;
      updct := updct + 1;
      delct := delct + 1;
    end if;
    --New Record
    if c1fmt.stvsbgi_code is not null and c1fmt.o_stvsbgi_code is null then
      begin insert into utl_d_aa.embbsbgiiatt (stvsbgi_code, seqno, attribute_type, attribute_name, attribute_value, attribute_start_date,
                           attribute_end_date, active_ind, create_date, modified_date, user_id)
            values (c1fmt.stvsbgi_code, c1fmt.seqno, c1fmt.attribute_type, c1fmt.attribute_name, c1fmt.attribute_value, c1fmt.attribute_start_date,
                c1fmt.attribute_end_date, c1fmt.active_ind, c1fmt.create_date, c1fmt.modified_date, c1fmt.user_id);
        exception when dup_val_on_index then
          --Log Key Error
          error_key := c1fmt.stvsbgi_code;
          dbms_output.put_line('Duplicate stvsbgi_code:' || error_key);
      end;
      insct := insct + 1;
      newct := newct + 1;
    end if;
    --Modified Record
    if c1fmt.stvsbgi_code is not null and c1fmt.o_stvsbgi_code is not null and
       ((c1fmt.attribute_type<>c1fmt.o_attribute_type or (c1fmt.attribute_type is null and c1fmt.o_attribute_type is not null) or (c1fmt.attribute_type is not null and c1fmt.o_attribute_type is null)) or
      (c1fmt.attribute_name<>c1fmt.o_attribute_name or (c1fmt.attribute_name is null and c1fmt.o_attribute_name is not null) or (c1fmt.attribute_name is not null and c1fmt.o_attribute_name is null)) or
      (c1fmt.attribute_value<>c1fmt.o_attribute_value or (c1fmt.attribute_value is null and c1fmt.o_attribute_value is not null) or (c1fmt.attribute_value is not null and c1fmt.o_attribute_value is null)) or
      (c1fmt.attribute_start_date<>c1fmt.o_attribute_start_date or (c1fmt.attribute_start_date is null and c1fmt.o_attribute_start_date is not null) or (c1fmt.attribute_start_date is not null and c1fmt.o_attribute_start_date is null)) or
      (c1fmt.attribute_end_date<>c1fmt.o_attribute_end_date or (c1fmt.attribute_end_date is null and c1fmt.o_attribute_end_date is not null) or (c1fmt.attribute_end_date is not null and c1fmt.o_attribute_end_date is null)) or
      (c1fmt.active_ind<>c1fmt.o_active_ind or (c1fmt.active_ind is null and c1fmt.o_active_ind is not null) or (c1fmt.active_ind is not null and c1fmt.o_active_ind is null))
       ) then
      begin
        update utl_d_aa.embbsbgiiatt
        set attribute_type = c1fmt.attribute_type,
          attribute_name = c1fmt.attribute_name,
          attribute_value = c1fmt.attribute_value,
          attribute_start_date = c1fmt.attribute_start_date,
          attribute_end_date = c1fmt.attribute_end_date,
          active_ind = c1fmt.active_ind,
          create_date = c1fmt.create_date,
          modified_date = c1fmt.modified_date,
          user_id = c1fmt.user_id
        where stvsbgi_code = c1fmt.o_stvsbgi_code
          and seqno = c1fmt.o_seqno;
        updct := updct + 1;
      end;
      insct := insct + 1;
      modct := modct + 1;
    end if;
    recs := recs + 1;
    fetch c1 into c1fmt;
  end loop;
  close c1;
  commit;
  --Log load complete time, total records, inserts, and updates and final status; utilize UTL_D_BIO.DWEBGENLOG for analysis using settings from below
  utl_d_bio.ads_common_tools.dwebgenlog_insert(p_process_id => 'etlj_bio_embbsbgiiatt_refresh_' || to_char(sysdate, 'yyyymmddhh24miss'),
                         p_process_name => 'ETLJ_BIO_EMBBSBGIIATT_REFRESH',
                         p_process_step => 'Completed',
                         p_process_developer => 'wayates',
                         p_log_persist => 365,
                         p_output_text => 'Added ' || insct || ', expired ' || updct || ' records at ' ||
                      to_char(sysdate, 'YYYY-MM-DD HH24:MI:SS') || '; Processed ' || recs || ' for UTL_D_BIO.EMBBSBGIIATT',
                         p_select_cnt => recs,
                         p_insert_cnt => newct,
                         p_update_cnt => modct,
                         p_delete_cnt => delct,
                         p_error_cnt => null,
                         p_error_severity => null,
                         p_start_time => job_start_time,
                         p_end_time => sysdate,
                         p_mech_number1 => round((sysdate - job_start_time) * 24 * 60 * 60, 0), p_mech_number2 => null, p_mech_text1 => 'EMBBSBGIIATT',
                         p_mech_text2 => null);
end etl_aa_embbsbgiiatt_merge;

procedure etl_aa_embbsbgiiext_merge (jobnumber number, processid varchar2, processname varchar2) is

/*--------------------------------------------CHANGE LOG----------------------------------------
VERSION DATE    USERNAME  UPDATES
1.0   02-06-2014  sawaddy   --Initial release
                --Purpose: This is an institute extension table for STVSBGI for storing custom metadata for management purposes.  This process retrieves info from SORBCMT.
2.0   07-18-2014  wayates   --Modified Homeschool definition to use new tag
3.0   08-27-2020  wayates --Converted to Full Join DELETE, INSERT, MODIFY Cursor Approach
              --The Merge Into solution wasn't handling deletes.
4.0   06-11-2021  wayates --Removed ORA_HASH and changed to column comparison technique; also stvsbgi_subtype is now sourced from SORBCMT
              --We ran into an issue where JAMS had a different NLS_DATE_FORMAT and was generating collision.
------------------------------------------------------------------------------------------------*/
  job_start_time date:= sysdate;
  insct int:=0;
  updct int:=0;
  delct int:=0;
  newct int:=0;
  modct int:=0;
  error_key varchar2(32000);
  recs int:=0;

  cursor c1 is
    select *
    from (select tblnew.stvsbgi_code, tblnew.stvsbgi_subtype, tblnew.status, tblnew.status_date, tblnew.status_contact, tblnew.website, tblnew.ceeb_redirect, tblnew.redirect_note,
           tblnew.duplicate_ind, tblnew.homeschool_ind, --tblnew.acsi_code, tblnew.nces_code, tblnew.act_code, tblnew.schev_lin_type, tblnew.schev_list_type,
           tblnew.create_date, tblnew.modified_date, tblnew.user_id,
           tblold.stvsbgi_code as o_stvsbgi_code, tblold.stvsbgi_subtype as o_stvsbgi_subtype, tblold.status as o_status, tblold.status_date as o_status_date, tblold.status_contact as o_status_contact,
           tblold.website as o_website, tblold.ceeb_redirect as o_ceeb_redirect, tblold.redirect_note as o_redirect_note, tblold.duplicate_ind as o_duplicate_ind, tblold.homeschool_ind as o_homeschool_ind,
           tblold.acsi_code as o_acsi_code, --tblold.nces_code as o_nces_code, tblold.act_code as o_act_code, tblold.schev_lin_type as o_schev_lin_type, tblold.schev_list_type as o_schev_list_type,
           tblold.create_date as o_create_date, tblold.modified_date as o_modified_date, tblold.user_id as o_user_id, tblold.block_comment as o_block_comment
        from (select stvsbgi_code,
               max(stvsbgi_subtype) stvsbgi_subtype,
               max(status) status,
               max(status_date) status_date,
               max(status_contact) status_contact,
               max(website) website,
               max(ceeb_redirect) ceeb_redirect,
               max(redirect_note) redirect_note,
               max(duplicate_ind) duplicate_ind,
               max(homeschool_ind) homeschool_ind,
               --max(acsi_code) acsi_code,  --hybrid custom entries
               --max(nces_code) nces_code,  --not used
               --max(act_code) act_code,  --not used
               --max(schev_lin_type) schev_lin_type,  --not used
               --max(schev_list_type) schev_list_type,  --not used
               max(create_date) create_date,
               max(modified_date) modified_date,
               max(user_id) user_id
          from (select stvsbgi.stvsbgi_code stvsbgi_code,
                 --zbgiext.zbgiext_sbgi_subtype
                 case when sorbcmt_comment like 'Sub-Type:%'
                    then case when sorbcmt_comment like '%;%'
                        then trim(substr(sorbcmt_comment, 10, instr(sorbcmt_comment, ';') - 10))
                        else trim(substr(sorbcmt_comment, 10))
                     end
                    else null
                 end stvsbgi_subtype,
                 case when sorbcmt_comment like 'Status:%'
                    then case when sorbcmt_comment like '%;%'
                        then trim(substr(sorbcmt_comment, 9, instr(sorbcmt_comment, ';') - 9))
                        else trim(substr(sorbcmt_comment, 9))
                     end
                    else null
                 end status,
                 case when sorbcmt_comment like 'Status:%'
                    then case when sorbcmt_comment like '%Date:%'
                        then to_date(substr(sorbcmt_comment, instr(lower(sorbcmt_comment), 'date:') + 6, 10), 'mm/dd/yyyy')
                        else null
                     end
                    else null
                 end status_date,
                 case when sorbcmt_comment like 'Status:%'
                    then case when sorbcmt_comment like '%Contact:%' or
                           sorbcmt_comment like '%Contact CEEB:%'
                        then case when sorbcmt_comment like '%Contact:%'
                              then trim(substr(sorbcmt_comment, instr(lower(sorbcmt_comment), 'contact:') + 8))
                              else 'Refer to CEEB: ' || trim(substr(sorbcmt_comment, instr(lower(sorbcmt_comment), 'contact ceeb:') + 13))
                           end
                        else null
                     end
                    else null
                 end status_contact,
                 case when sorbcmt_comment like 'Website:%'
                    then case when sorbcmt_comment like '%;%'
                        then trim(substr(sorbcmt_comment, 9, instr(sorbcmt_comment, ';') - 9))
                        else trim(substr(sorbcmt_comment, 9))
                     end
                    else null
                 end website,
                 case when sorbcmt_comment like 'USE CEEB:%'
                    then case when sorbcmt_comment like '%;%'
                        then trim(substr(sorbcmt_comment, 11, instr(sorbcmt_comment, ';') - 11))
                        else trim(substr(sorbcmt_comment, 11))
                     end
                    else null
                 end ceeb_redirect,
                 case when lower(sorbcmt_comment) like '%redirect note:%'
                    then trim(substr(sorbcmt_comment, instr(lower(sorbcmt_comment), 'redirect note:') + 14))
                    else null
                 end redirect_note,
                 case when lower(sorbcmt_comment) like '%duplicate:%' then 'Y' else null end duplicate_ind,
                 case when sorbcmt_comment = '#Homeschool' then 'Y' else null end homeschool_ind,
                 --null acsi_code,
                 --null nces_code,
                 --null act_code,
                 --zbgiext.zbgiext_schev_lintype
                 --zbgiext.zbgiext_schev_lstinst
                 nvl(sorbcmt_activity_date, stvsbgi_activity_date) --nvl(nvl(zbgiext_activity_date, sorbcmt_activity_date), stvsbgi_activity_date)
                 create_date,
                 nvl(sorbcmt_activity_date, stvsbgi_activity_date) --nvl(nvl(zbgiext_activity_date, sorbcmt_activity_date), stvsbgi_activity_date)
                 modified_date,
                 'syncprocess' user_id
            from stvsbgi
            --LEFT JOIN utl_d_bio.zbgiext zbgiext
                 --ON stvsbgi.stvsbgi_code= zbgiext.zbgiext_sbgi_code
            join sorbcmt
              on stvsbgi_code = sorbcmt_sbgi_code
             and (sorbcmt_comment like 'USE CEEB:%' or
                sorbcmt_comment like 'Website:%' or
                sorbcmt_comment like 'Status:%' or
                sorbcmt_comment like 'Contact:%' or
                sorbcmt_comment like 'Sub-Type:%' or
                sorbcmt_comment = '#Homeschool'))
          group by stvsbgi_code) tblnew
        full join utl_d_aa.embbsbgiiext tblold
           on tblold.stvsbgi_code = tblnew.stvsbgi_code)
    where (stvsbgi_code is null and o_stvsbgi_code is not null)
       or (stvsbgi_code is not null and o_stvsbgi_code is null)
       or ((stvsbgi_subtype<>o_stvsbgi_subtype or (stvsbgi_subtype is null and o_stvsbgi_subtype is not null) or (stvsbgi_subtype is not null and o_stvsbgi_subtype is null)) or
         (status<>o_status or (status is null and o_status is not null) or (status is not null and o_status is null)) or
         (status_date<>o_status_date or (status_date is null and o_status_date is not null) or (status_date is not null and o_status_date is null)) or
         (status_contact<>o_status_contact or (status_contact is null and o_status_contact is not null) or (status_contact is not null and o_status_contact is null)) or
         (website<>o_website or (website is null and o_website is not null) or (website is not null and o_website is null)) or
         (ceeb_redirect<>o_ceeb_redirect or (ceeb_redirect is null and o_ceeb_redirect is not null) or (ceeb_redirect is not null and o_ceeb_redirect is null)) or
         (redirect_note<>o_redirect_note or (redirect_note is null and o_redirect_note is not null) or (redirect_note is not null and o_redirect_note is null)) or
         (duplicate_ind<>o_duplicate_ind or (duplicate_ind is null and o_duplicate_ind is not null) or (duplicate_ind is not null and o_duplicate_ind is null)) or
         (homeschool_ind<>o_homeschool_ind or (homeschool_ind is null and o_homeschool_ind is not null) or (homeschool_ind is not null and o_homeschool_ind is null)));

c1fmt c1%rowtype;
begin
open c1;
fetch c1 into c1fmt;
while c1%found loop

--Deleted Record (Only if no custom data)
    if c1fmt.stvsbgi_code is null and c1fmt.o_stvsbgi_code is not null and
     --these conditions were added to prevent deleting the custom hybrid information; i.e. ensure no custom values
     c1fmt.o_acsi_code is null and c1fmt.o_block_comment is null
  then
      delete from utl_d_aa.embbsbgiiext where stvsbgi_code = c1fmt.o_stvsbgi_code;
    updct:=updct+1;
    delct:=delct+1;
    end if;
--Clear Record (remove non-custom data)
    if c1fmt.stvsbgi_code is null and c1fmt.o_stvsbgi_code is not null and
     --these conditions were added to prevent deleting the custom hybrid information; i.e. ensure no custom values
     (c1fmt.o_acsi_code is not null or c1fmt.o_block_comment is not null) and
     --no sense in updating this everytime it runs so ensure something has not been cleared.
     (c1fmt.o_stvsbgi_subtype is not null or c1fmt.o_status is not null or c1fmt.o_status_date is not null or
    c1fmt.o_status_contact is not null or c1fmt.o_website is not null or c1fmt.o_ceeb_redirect is not null or
    c1fmt.o_redirect_note is not null or c1fmt.o_duplicate_ind is not null or c1fmt.o_homeschool_ind is not null)
  then
      update utl_d_aa.embbsbgiiext
    set stvsbgi_subtype = null,
      status = null,
      status_date = null,
      status_contact = null,
      website = null,
      ceeb_redirect = null,
      redirect_note = null,
      duplicate_ind = null,
      homeschool_ind = null,
      modified_date = sysdate,
      user_id = 'syncprocess',
      embbsbgiiext_pk = embbsbgiiext_pk*-1  --This field is audited by: ARGOS05: Banner.ADS.System Auditing and Quality Control.STVSBGI.STVSBGI-IEXT Records Deleted
    where stvsbgi_code = c1fmt.o_stvsbgi_code;
    updct:=updct+1;
    delct:=delct+1;
    end if;

--New Record
  if c1fmt.stvsbgi_code is not null and c1fmt.o_stvsbgi_code is null then
  begin
    insert into utl_d_aa.embbsbgiiext (stvsbgi_code, stvsbgi_subtype, status, status_date, status_contact, website, ceeb_redirect, redirect_note, duplicate_ind, homeschool_ind,
                       create_date, modified_date, user_id)
      values (c1fmt.stvsbgi_code, c1fmt.stvsbgi_subtype, c1fmt.status, c1fmt.status_date, c1fmt.status_contact, c1fmt.website, c1fmt.ceeb_redirect, c1fmt.redirect_note, c1fmt.duplicate_ind, c1fmt.homeschool_ind,
          c1fmt.create_date, c1fmt.modified_date, c1fmt.user_id);
    exception when dup_val_on_index then
      --Log Key Error
      error_key:=  c1fmt.stvsbgi_code;
      dbms_output.put_line('Duplicate stvsbgi_code:' || error_key);
  end;
  insct:=insct+1;
  newct:=newct+1;
  end if;

--Modified Record
  if c1fmt.stvsbgi_code is not null and c1fmt.o_stvsbgi_code is not null and
   ((c1fmt.stvsbgi_subtype<>c1fmt.o_stvsbgi_subtype or (c1fmt.stvsbgi_subtype is null and c1fmt.o_stvsbgi_subtype is not null) or (c1fmt.stvsbgi_subtype is not null and c1fmt.o_stvsbgi_subtype is null)) or
   (c1fmt.status<>c1fmt.o_status or (c1fmt.status is null and c1fmt.o_status is not null) or (c1fmt.status is not null and c1fmt.o_status is null)) or
   (c1fmt.status_date<>c1fmt.o_status_date or (c1fmt.status_date is null and c1fmt.o_status_date is not null) or (c1fmt.status_date is not null and c1fmt.o_status_date is null)) or
   (c1fmt.status_contact<>c1fmt.o_status_contact or (c1fmt.status_contact is null and c1fmt.o_status_contact is not null) or (c1fmt.status_contact is not null and c1fmt.o_status_contact is null)) or
   (c1fmt.website<>c1fmt.o_website or (c1fmt.website is null and c1fmt.o_website is not null) or (c1fmt.website is not null and c1fmt.o_website is null)) or
   (c1fmt.ceeb_redirect<>c1fmt.o_ceeb_redirect or (c1fmt.ceeb_redirect is null and c1fmt.o_ceeb_redirect is not null) or (c1fmt.ceeb_redirect is not null and c1fmt.o_ceeb_redirect is null)) or
   (c1fmt.redirect_note<>c1fmt.o_redirect_note or (c1fmt.redirect_note is null and c1fmt.o_redirect_note is not null) or (c1fmt.redirect_note is not null and c1fmt.o_redirect_note is null)) or
   (c1fmt.duplicate_ind<>c1fmt.o_duplicate_ind or (c1fmt.duplicate_ind is null and c1fmt.o_duplicate_ind is not null) or (c1fmt.duplicate_ind is not null and c1fmt.o_duplicate_ind is null)) or
   (c1fmt.homeschool_ind<>c1fmt.o_homeschool_ind or (c1fmt.homeschool_ind is null and c1fmt.o_homeschool_ind is not null) or (c1fmt.homeschool_ind is not null and c1fmt.o_homeschool_ind is null))
   ) then
  begin
    update utl_d_aa.embbsbgiiext
      set stvsbgi_subtype = c1fmt.stvsbgi_subtype,
      status = c1fmt.status,
      status_date = c1fmt.status_date,
      status_contact = c1fmt.status_contact,
      website = c1fmt.website,
      ceeb_redirect = c1fmt.ceeb_redirect,
      redirect_note = c1fmt.redirect_note,
      duplicate_ind = c1fmt.duplicate_ind,
      homeschool_ind = c1fmt.homeschool_ind,
      create_date = c1fmt.create_date,
      modified_date = c1fmt.modified_date,
      user_id = c1fmt.user_id
    where stvsbgi_code = c1fmt.o_stvsbgi_code;
    updct:=updct+1;
    end;
    insct:=insct+1;
    modct:=modct+1;
  end if;
  recs:=recs+1;
  fetch c1 into c1fmt;
  end loop;
close c1;

commit;
  --Log load complete time, total records, inserts, and updates and final status; utilize UTL_D_BIO.DWEBGENLOG for analysis using settings from below
  utl_d_bio.ads_common_tools.dwebgenlog_insert (p_process_id    => 'etlj_bio_embbsbgiiext_refresh_'||to_char(sysdate,'yyyymmddhh24miss'),
                      p_process_name      => 'ETLJ_BIO_EMBBSBGIIEXT_REFRESH',
                      p_process_step      => 'Completed',
                      p_process_developer => 'wayates',
                      p_log_persist       => 365,
                      p_output_text       => 'Added ' || insct || ', expired ' || updct || ' records at ' || to_char(sysdate,'YYYY-MM-DD HH24:MI:SS')||'; Processed ' || recs || ' for UTL_D_BIO.EMBBSBGIIEXT',
                      p_select_cnt        => recs,
                      p_insert_cnt        => newct,
                      p_update_cnt        => modct,
                      p_delete_cnt        => delct,
                                          p_error_cnt         => null,
                                          p_error_severity    => null,
                      p_start_time        => job_start_time,
                      p_end_time          => sysdate,
                      p_mech_number1      => round((sysdate - job_start_time)*24*60*60,0),
                      p_mech_number2      => null,
                      p_mech_text1        => 'EMBBSBGIIEXT',
                      p_mech_text2        => null);

end etl_aa_embbsbgiiext_merge;

procedure etl_aa_inbbsbgiinst_refresh (jobnumber number, processid varchar2, processname varchar2) is
--DECLARE
/*--------------------------------------------CHANGE LOG----------------------------------------
VERSION DATE    USERNAME  UPDATES
1.0   03-10-2014  wayates   --Initial release
                --Purpose: This is a staging table for the Institution Auditing and Reporting SSRS Report.
2.0   10-15-2020  wayates --Updating to SCD style ETL
              --Changed institution name logic due to Full Name tag exhaustive implementation. (TKT2263858)
------------------------------------------------------------------------------------------------*/

  job_start_time date:= sysdate;
  job_check_time date;
  insct int:=0;
  updct int:=0;
  delct int:=0;
  newct int:=0;
  modct int:=0;
  error_key varchar2(32000);
  recs int:=0;

cursor c1 is
    select * from (
    select d.*,
       case when (stvsbgi_code is null and o_stvsbgi_code is not null) then 'Deleted'
          when (stvsbgi_code is not null and o_stvsbgi_code is null) then 'Inserted'
          when (stvsbgi_type_ind<>o_stvsbgi_type_ind or (stvsbgi_type_ind is null and o_stvsbgi_type_ind is not null) or (stvsbgi_type_ind is not null and o_stvsbgi_type_ind is null)) or
             (institution_group<>o_institution_group or (institution_group is null and o_institution_group is not null) or (institution_group is not null and o_institution_group is null)) or
             (affiliated_prefix<>o_affiliated_prefix or (affiliated_prefix is null and o_affiliated_prefix is not null) or (affiliated_prefix is not null and o_affiliated_prefix is null)) or
             (institution_name_and_aliases<>o_institution_name_and_aliases or (institution_name_and_aliases is null and o_institution_name_and_aliases is not null) or (institution_name_and_aliases is not null and o_institution_name_and_aliases is null)) or
             (sorbcmt_comment<>o_sorbcmt_comment or (sorbcmt_comment is null and o_sorbcmt_comment is not null) or (sorbcmt_comment is not null and o_sorbcmt_comment is null)) or
             (status<>o_status or (status is null and o_status is not null) or (status is not null and o_status is null)) or
             (status_date<>o_status_date or (status_date is null and o_status_date is not null) or (status_date is not null and o_status_date is null)) or
             (status_contact<>o_status_contact or (status_contact is null and o_status_contact is not null) or (status_contact is not null and o_status_contact is null)) or
             (reorganization<>o_reorganization or (reorganization is null and o_reorganization is not null) or (reorganization is not null and o_reorganization is null)) or
             (sobsbgi_address<>o_sobsbgi_address or (sobsbgi_address is null and o_sobsbgi_address is not null) or (sobsbgi_address is not null and o_sobsbgi_address is null)) or
             (sobsbgi_city<>o_sobsbgi_city or (sobsbgi_city is null and o_sobsbgi_city is not null) or (sobsbgi_city is not null and o_sobsbgi_city is null)) or
             (sobsbgi_stat_code<>o_sobsbgi_stat_code or (sobsbgi_stat_code is null and o_sobsbgi_stat_code is not null) or (sobsbgi_stat_code is not null and o_sobsbgi_stat_code is null)) or
             (sobsbgi_zip<>o_sobsbgi_zip or (sobsbgi_zip is null and o_sobsbgi_zip is not null) or (sobsbgi_zip is not null and o_sobsbgi_zip is null)) or
             (sobsbgi_natn_code<>o_sobsbgi_natn_code or (sobsbgi_natn_code is null and o_sobsbgi_natn_code is not null) or (sobsbgi_natn_code is not null and o_sobsbgi_natn_code is null)) or
             (alt_address<>o_alt_address or (alt_address is null and o_alt_address is not null) or (alt_address is not null and o_alt_address is null)) or
             (institution_phone<>o_institution_phone or (institution_phone is null and o_institution_phone is not null) or (institution_phone is not null and o_institution_phone is null)) or
             (website<>o_website or (website is null and o_website is not null) or (website is not null and o_website is null)) or
             (ceeb_redirect<>o_ceeb_redirect or (ceeb_redirect is null and o_ceeb_redirect is not null) or (ceeb_redirect is not null and o_ceeb_redirect is null)) or
             (redirect_note<>o_redirect_note or (redirect_note is null and o_redirect_note is not null) or (redirect_note is not null and o_redirect_note is null)) or
             (duplicate_ind<>o_duplicate_ind or (duplicate_ind is null and o_duplicate_ind is not null) or (duplicate_ind is not null and o_duplicate_ind is null)) or
             --(institution_note<>o_institution_note or (institution_note is null and o_institution_note is not null) or (institution_note is not null and o_institution_note is null)) or
             (courses_articulated<>o_courses_articulated or (courses_articulated is null and o_courses_articulated is not null) or (courses_articulated is not null and o_courses_articulated is null)) or
             (accreditationagency<>o_accreditationagency or (accreditationagency is null and o_accreditationagency is not null) or (accreditationagency is not null and o_accreditationagency is null)) or
             (calendarsystem<>o_calendarsystem or (calendarsystem is null and o_calendarsystem is not null) or (calendarsystem is not null and o_calendarsystem is null)) or
             (awarded<>o_awarded or (awarded is null and o_awarded is not null) or (awarded is not null and o_awarded is null)) then 'Modified'
       end action_type
    from (
    select tblnew.stvsbgi_code, tblnew.stvsbgi_type_ind, tblnew.institution_group, tblnew.affiliated_prefix, tblnew.institution_name_and_aliases, tblnew.sorbcmt_comment,
       tblnew.status, tblnew.status_date, tblnew.status_contact, tblnew.reorganization, tblnew.sobsbgi_address, tblnew.sobsbgi_city, tblnew.sobsbgi_stat_code, tblnew.sobsbgi_zip,
       tblnew.sobsbgi_natn_code, tblnew.alt_address, tblnew.institution_phone, tblnew.website, tblnew.ceeb_redirect, tblnew.redirect_note, tblnew.duplicate_ind,
       --tblnew.institution_note,
       tblnew.courses_articulated, tblnew.accreditationagency, tblnew.calendarsystem, tblnew.awarded,
       tblold.stvsbgi_code as o_stvsbgi_code, tblold.stvsbgi_type_ind as o_stvsbgi_type_ind, tblold.institution_group as o_institution_group,
       tblold.affiliated_prefix as o_affiliated_prefix, tblold.institution_name_and_aliases as o_institution_name_and_aliases, tblold.sorbcmt_comment as o_sorbcmt_comment,
       tblold.status as o_status, tblold.status_date as o_status_date, tblold.status_contact as o_status_contact, tblold.reorganization as o_reorganization,
       tblold.sobsbgi_address as o_sobsbgi_address, tblold.sobsbgi_city as o_sobsbgi_city, tblold.sobsbgi_stat_code as o_sobsbgi_stat_code, tblold.sobsbgi_zip as o_sobsbgi_zip,
       tblold.sobsbgi_natn_code as o_sobsbgi_natn_code, tblold.alt_address as o_alt_address, tblold.institution_phone as o_institution_phone, tblold.website as o_website,
       tblold.ceeb_redirect as o_ceeb_redirect, tblold.redirect_note as o_redirect_note, tblold.duplicate_ind as o_duplicate_ind,
       --tblold.institution_note as o_institution_note,
       tblold.courses_articulated as o_courses_articulated, tblold.accreditationagency as o_accreditationagency, tblold.calendarsystem as o_calendarsystem,
       tblold.awarded as o_awarded
    from (select q.stvsbgi_code,
           stvsbgi_type_ind,
           institution_group,
           affiliated_prefix,
           institution_name_and_aliases,
           sorbcmt_comment,
           ext.status,
           ext.status_date,
           ext.status_contact,
           reorganization,
           sobsbgi_address,
           sobsbgi_city,
           sobsbgi_stat_code,
           sobsbgi_zip,
           sobsbgi_natn_code,
           alt_address,
           institution_phone,
           ext.website,
           ext.ceeb_redirect,
           ext.redirect_note,
           ext.duplicate_ind,
           --ext.block_comment institution_note,
           courses_articulated,
           accreditationagency,
           calendarsystem,
           awarded
      from (select s.stvsbgi_code,
             stvsbgi_type_ind,
             institution_group,
             affiliated_prefix,
             substr(institution_name_and_aliases, 1, length(institution_name_and_aliases) - 1) institution_name_and_aliases,
             substr(sorbcmt_comment, 1, length(sorbcmt_comment) - 1) sorbcmt_comment,
             reorganization,
             sobsbgi_address,
             sobsbgi_city,
             sobsbgi_stat_code,
             sobsbgi_zip,
             sobsbgi_natn_code,
             alt_address,
             institution_phone,
             courses_articulated,
             acst_desc accreditationagency,
             cald_desc calendarsystem,
             nvl(awarded_count,0) awarded
          from stvsbgi s
        --GET NAME
          left join (select stvsbgi_code sbgi_code,
                  listagg(case when name_type = 'Full Name' then null else name_type||': ' end||institution_name||
                      case when attribute_start_date is not null
                         then ' ('||to_char(attribute_start_date,'mm/dd/yyyy')||'-'||to_char(attribute_end_date,'mm/dd/yyyy')||')' end||chr(10))
                      within group (order by decode(name_type,'Full Name',1,'Sub-Titled',2,'Banner Desc',3,'Alternatively Named',4,'Formerly Named',5,'Campus Includes',99,6),
                                   nvl(attribute_start_date,date '1900-01-01'),
                                   institution_name) as institution_name_and_aliases
               from (select i.stvsbgi_code,
                      'Banner Desc' name_type,
                      i.stvsbgi_desc institution_name,
                      null attribute_start_date,
                      null attribute_end_date
                   from stvsbgi i
                   left join utl_d_bio.embbsbgiiatt f
                      on f.stvsbgi_code = i.stvsbgi_code
                     and f.attribute_name = 'Full Name'
                     and f.attribute_value = i.stvsbgi_desc
                   where stvsbgi_type_ind in ('C','H')
                   and f.stvsbgi_code is null
                   union all
                   select iatt.stvsbgi_code,
                      iatt.attribute_name  name_type,
                      iatt.attribute_value institution_name,
                      attribute_start_date,
                      attribute_end_date
                   from utl_d_aa.embbsbgiiatt iatt
                   --Attribute Validation
                   join utl_d_aa.emebsbgiiatv iatv
                   on iatv.attribute_name = iatt.attribute_name
                  and iatv.attribute_alias_ind = 'Y'
                   where iatt.active_ind = 'Y')
               group by stvsbgi_code) att_n
             on s.stvsbgi_code = att_n.sbgi_code
        --GET GROUP
          left join (select institution_group,
                  affiliated_code,
                  case when h.stvsbgi_code = affiliated_code
                     then 'P'
                     else 'C'
                  end hier_ind,
                  h.affiliated_prefix
               from utl_r_ads.embbsbgihier h
               join (select stvsbgi_code,
                      rank() over(order by stvsbgi_code) institution_group
                   from utl_r_ads.embbsbgihier
                   group by stvsbgi_code) g
                 on g.stvsbgi_code = h.stvsbgi_code
               order by institution_group,
                    hier_ind desc) hier
             on s.stvsbgi_code = hier.affiliated_code
        --GET ADDRESS
          left join (select sobsbgi_sbgi_code,
                  listagg(sobsbgi_street_line1 || case when sobsbgi_street_line2 is not null
                                     then chr(10) || sobsbgi_street_line2
                                     else null
                                  end) within group(order by sobsbgi_sbgi_code) as sobsbgi_address,
                  sobsbgi_city,
                  sobsbgi_stat_code,
                  sobsbgi_zip,
                  sobsbgi_natn_code
               from sobsbgi
               group by sobsbgi_sbgi_code,
                    sobsbgi_city,
                    sobsbgi_stat_code,
                    sobsbgi_zip,
                    sobsbgi_natn_code)
             on s.stvsbgi_code = sobsbgi_sbgi_code
        --GET ALTERNATE ADDRESS
          left join (select stvsbgi_code stvsbgi_code_r,
                  listagg(attribute_type || ': ' || attribute_value || chr(10)) within group(order by seqno) as alt_address
               from (select stvsbgi_code,
                      attribute_type,
                      attribute_value,
                      seqno
                   from utl_d_aa.embbsbgiiatt
                   where attribute_name = 'Alternate Address')
               group by stvsbgi_code) att_a
             on s.stvsbgi_code = att_a.stvsbgi_code_r
        --GET REORGANIZATION
          left join (select stvsbgi_code stvsbgi_code_r,
                  listagg(attribute_type || ': ' || attribute_value || chr(10)) within group(order by seqno) as reorganization
               from (select stvsbgi_code,
                      attribute_type,
                      attribute_value,
                      seqno
                   from utl_d_aa.embbsbgiiatt
                   where attribute_name = 'Reorganization')
               group by stvsbgi_code) att_r
             on s.stvsbgi_code = att_r.stvsbgi_code_r
        --GET COMMENTS
          left join (select sorbcmt_sbgi_code,
                  listagg(sorbcmt_comment || chr(10)) within group(order by sorbcmt_seqno) as sorbcmt_comment
               from sorbcmt
               --remove tagged comments leaving normal comments
               where instr(sorbcmt_comment, ':') = 0
               --and substr(sorbcmt_comment, 1, 1) <> '#'
               group by sorbcmt_sbgi_code)
             on s.stvsbgi_code = sorbcmt_sbgi_code
        --GET PHONE
          left join (select sorbcnt_sbgi_code,
                  listagg(sorbcnt_name || ': ' || sorbcnt_phone || chr(10)) within group(order by sorbcnt_rank) as institution_phone
               from (select sorbcnt_sbgi_code,
                      sorbcnt_name,
                      sorbcnt_phone_area || '.' || case when length(replace(replace(sorbcnt_phone_number, '.'), '-')) = 7
                                      then substr(replace(replace(sorbcnt_phone_number, '.'), '-'), 1, 3) || '.' ||
                                         substr(replace(replace(sorbcnt_phone_number, '.'), '-'), 4, 4)
                                      else replace(replace(sorbcnt_phone_number, '.'), '-')
                                     end
                                  || case when sorbcnt_phone_ext is not null
                                      then ' (' || sorbcnt_phone_ext || ')'
                                      else null
                                     end as sorbcnt_phone,
                      rank() over(partition by sorbcnt_sbgi_code order by sorbcnt_activity_date, sorbcnt_name) sorbcnt_rank
                   from sorbcnt)
               group by sorbcnt_sbgi_code)
             on s.stvsbgi_code = sorbcnt_sbgi_code
            --and sorbcnt_rank = 1
        --GET AWARDED
          left join (select shrtrit_sbgi_code, count(distinct shrtrit_pidm) awarded_count
               from (select shrtrit_sbgi_code,
                      shrtrit_pidm
                   from shrtrit
                   join shrtrce
                   on shrtrce_pidm = shrtrit_pidm
                  and shrtrce_trit_seq_no = shrtrit_seq_no
                   union all
                   select sorhsch_sbgi_code,
                      sorhsch_pidm
                   from sorhsch
                   union all
                   select sorpcol_sbgi_code,
                      sorpcol_pidm
                   from sorpcol)
               group by shrtrit_sbgi_code)
             on shrtrit_sbgi_code = s.stvsbgi_code
        --GET CALENDAR
          left join (select distinct sorbtag.sorbtag_sbgi_code sbgi_code,
                       stvcald_desc cald_desc
               from sorbtag sorbtag
               left join stvcald
                  on sorbtag.sorbtag_cald_code = stvcald_code
               where sorbtag.sorbtag_term_code_eff = (select max(sorbtag2.sorbtag_term_code_eff)
                                  from sorbtag sorbtag2
                                  where sorbtag.sorbtag_sbgi_code = sorbtag2.sorbtag_sbgi_code
                                    and sorbtag2.sorbtag_term_code_eff <= (select min(stvterm_code)
                                                       from stvterm
                                                       where sysdate <= stvterm_end_date + 12
                                                         and mod(to_number(stvterm_code), 20) = 0))) calsys
             on calsys.sbgi_code = s.stvsbgi_code
        --GET ACCREDITATION
          left join (select sorbtai.sorbtai_sbgi_code sbgi_code,
                  listagg(stvacst_desc, ';' || chr(10)) within group(order by stvacst_desc) acst_desc
               from sorbtai sorbtai
               left join stvacst
                    on sorbtai.sorbtai_acst_code = stvacst_code
               where sorbtai.sorbtai_term_code_eff = (select max(sorbtai2.sorbtai_term_code_eff)
                                  from sorbtai sorbtai2
                                  where sorbtai.sorbtai_sbgi_code = sorbtai2.sorbtai_sbgi_code
                                    and sorbtai2.sorbtai_term_code_eff <= (select min(stvterm_code)
                                                       from stvterm
                                                       where sysdate <= stvterm_end_date + 12
                                                         and mod(to_number(stvterm_code), 20) = 0))
               group by sorbtai.sorbtai_sbgi_code) acred
             on acred.sbgi_code = s.stvsbgi_code
        --GET ARTICULATION
          left join (select shrtatc_sbgi_code,
                  count(distinct shrtatc_subj_code_trns || shrtatc_crse_numb_trns) courses_articulated
               from shrtatc
               group by shrtatc_sbgi_code) artic
             on artic.shrtatc_sbgi_code = s.stvsbgi_code
          where stvsbgi_type_ind in ('C', 'H')) q
            left join utl_d_aa.embbsbgiiext ext
             on q.stvsbgi_code = ext.stvsbgi_code) tblnew
    full join (select * from utl_d_aa.inbbsbgiinst) tblold
       on tblold.stvsbgi_code = tblnew.stvsbgi_code) d)
    where action_type is not null;

c1fmt c1%rowtype;


begin

open c1;
fetch c1 into c1fmt;
while c1%found loop

--Deleted Record
    if c1fmt.action_type = 'Deleted'
  then
      delete from utl_d_aa.inbbsbgiinst where stvsbgi_code = c1fmt.o_stvsbgi_code;
    updct:=updct+1;
    delct:=delct+1;
    end if;

--New Record
  if c1fmt.action_type = 'Inserted' then
  begin
    insert into utl_d_aa.inbbsbgiinst (stvsbgi_code, stvsbgi_type_ind, institution_group, affiliated_prefix, institution_name_and_aliases, sorbcmt_comment, status, status_date, status_contact,
                       reorganization, sobsbgi_address, sobsbgi_city, sobsbgi_stat_code, sobsbgi_zip, sobsbgi_natn_code, alt_address, institution_phone, website,
                       ceeb_redirect, redirect_note, duplicate_ind,
                       --institution_note,
                       courses_articulated, accreditationagency, calendarsystem, awarded)
      values (c1fmt.stvsbgi_code, c1fmt.stvsbgi_type_ind, c1fmt.institution_group, c1fmt.affiliated_prefix, c1fmt.institution_name_and_aliases, c1fmt.sorbcmt_comment,
          c1fmt.status, c1fmt.status_date, c1fmt.status_contact, c1fmt.reorganization, c1fmt.sobsbgi_address, c1fmt.sobsbgi_city, c1fmt.sobsbgi_stat_code,
          c1fmt.sobsbgi_zip, c1fmt.sobsbgi_natn_code, c1fmt.alt_address, c1fmt.institution_phone, c1fmt.website, c1fmt.ceeb_redirect, c1fmt.redirect_note, c1fmt.duplicate_ind,
          --c1fmt.institution_note,
          c1fmt.courses_articulated, c1fmt.accreditationagency, c1fmt.calendarsystem, c1fmt.awarded);
  --Catch Errors and Print
    exception when dup_val_on_index then
            error_key:= c1fmt.stvsbgi_code;
            dbms_output.put_line('Duplicate stvsbgi_code: ' || error_key);
          when others then
            error_key:= c1fmt.stvsbgi_code;
            dbms_output.put_line('Error inserting: ' || error_key||'; Error: '|| sqlcode || '/' || substr(sqlerrm, 1, 100));

  end;
  insct:=insct+1;
  newct:=newct+1;
  end if;

--Modified Record
  if c1fmt.action_type = 'Modified' then
  begin
    update utl_d_aa.inbbsbgiinst
      set stvsbgi_type_ind = c1fmt.stvsbgi_type_ind,
      institution_group = c1fmt.institution_group,
      affiliated_prefix = c1fmt.affiliated_prefix,
      institution_name_and_aliases = c1fmt.institution_name_and_aliases,
      sorbcmt_comment = c1fmt.sorbcmt_comment,
      status = c1fmt.status,
      status_date = c1fmt.status_date,
      status_contact = c1fmt.status_contact,
      reorganization = c1fmt.reorganization,
      sobsbgi_address = c1fmt.sobsbgi_address,
      sobsbgi_city = c1fmt.sobsbgi_city,
      sobsbgi_stat_code = c1fmt.sobsbgi_stat_code,
      sobsbgi_zip = c1fmt.sobsbgi_zip,
      sobsbgi_natn_code = c1fmt.sobsbgi_natn_code,
      alt_address = c1fmt.alt_address,
      institution_phone = c1fmt.institution_phone,
      website = c1fmt.website,
      ceeb_redirect = c1fmt.ceeb_redirect,
      redirect_note = c1fmt.redirect_note,
      duplicate_ind = c1fmt.duplicate_ind,
      --institution_note = c1fmt.institution_note,
      courses_articulated = c1fmt.courses_articulated,
      accreditationagency = c1fmt.accreditationagency,
      calendarsystem = c1fmt.calendarsystem,
      awarded = c1fmt.awarded
    where stvsbgi_code = c1fmt.o_stvsbgi_code;
    updct:=updct+1;
  --Catch Errors and Print
  exception when others then
    error_key:= c1fmt.stvsbgi_code;
    dbms_output.put_line('Error modifying: ' || error_key||'; Error: '|| sqlcode || '/' || substr(sqlerrm, 1, 100));
    end;
    insct:=insct+1;
    modct:=modct+1;
  end if;
  recs:=recs+1;
  fetch c1 into c1fmt;
  end loop;
close c1;

commit;

  --Log load complete time, total records, inserts, and updates and final status;
  --utilize UTL_D_BIO.DWEBGENLOG for analysis using settings from below
  utl_d_bio.ads_common_tools.dwebgenlog_insert (p_process_id    => 'etlj_aa_inbbsbgiinst_refresh_'||to_char(sysdate,'yyyymmddhh24miss'),
                      p_process_name      => 'ETLJ_AA_INBBSBGIINST_REFRESH',
                      p_process_step      => 'Completed',
                      p_process_developer => 'wayates',
                      p_log_persist       => 365,
                      p_output_text       => 'Added ' || insct || ' UTL_D_AA.INBBSBGIINST, expired ' || updct || ' records at ' || to_char(sysdate,'YYYY-MM-DD HH24:MI:SS')||'; Processed ' || recs || ' UTL_D_AA.INBBSBGIINST',
                      p_select_cnt        => recs,
                      p_insert_cnt        => newct,
                      p_update_cnt        => modct,
                      p_delete_cnt        => delct,
                      p_mech_number1      => null,
                      p_mech_number2      => null,
                      p_mech_text1        => 'INBBSBGIINST',
                      p_mech_text2        => null);

end etl_aa_inbbsbgiinst_refresh; --

end load_aa_etl_main;