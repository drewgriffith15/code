-- =============================================================================
-- Goal:
--   - Produce a task/resultset listing tasks assigned to a user with truncated
--     text fields and aggregated work_notes (emulating LISTAGG(DISTINCT ...))
--     while avoiding ORA-01489 (string concatenation too long).
--
-- Scope:
--   - In Scope: Select tasks from utl_p_sn.* schema, join related metadata,
--     aggregate distinct work_notes per task into a CLOB and truncate to 3900 bytes.
--   - Out of Scope: DDL changes, data mutation, permanent objects creation.
--
-- Key Requirements:
--   - Inputs:
--       lower('&username')   VARCHAR2  -- required, user_name to filter on (e.g. 'wgriffith2')
--       :p_days_back   NUMBER    -- optional, number of days to look back from SYSDATE (default 365)
--   - Outputs:
--       Resultset with task_number, sys_id, due_date, closed_at, user_name,
--       actual_effort_hours, truncated short_description, truncated description,
--       and truncated aggregated work_notes (listed_comments).
--   - Volume:
--       Designed for moderate resultsets; XMLAGG on high-cardinality distinct values
--       can still be expensive. Truncation avoids ORA-01489 for very long aggregations.
--
-- Dependencies:
--   - Tables/Views:
--       utl_p_sn.task, utl_p_sn.sys_user, utl_p_sn.sys_choice,
--       utl_p_sn.sc_req_item, utl_p_sn.sc_cat_item,
--       utl_p_sn.cmdb_ci, utl_p_sn.cmdb, utl_p_sn.sys_documentation,
--       utl_d_it.sn_group_hierarchy, utl_d_it.sn_default_group_history,
--       utl_d_it.sn_sys_audit
--   - Built-in packages/functions:
--       XMLAGG, XMLELEMENT, XMLSERIALIZE, DBMS_LOB.SUBSTR, REGEXP_LIKE, TO_DATE
--
-- Constraints & Risks:
--   - If DB is under heavy load, XMLAGG and DISTINCT in the subquery may be costly.
--   - work_effort is stored as text; malformed values are skipped (treated as zero effort).
--   - DBMS_LOB.SUBSTR returns VARCHAR2 limited by client settings; truncation to 3900 bytes
--     is applied to avoid ORA-01489 and to keep payloads manageable.
--   - sdoc join (sdoc.element IS NULL) may match multiple rows causing row-multiplication
--     if not unique; consider adding additional predicates if needed.
--   - Date-range join on dgh: ensure dgh.from_date/dgh.to_date are populated; missing ranges
--     can cause unexpected NULL joins.
--
-- Runbook Notes:
--   - Bind variables:
--       lower('&username') (required) -- set to the username to filter.
--       :p_days_back (optional) -- default 365 if NULL or <= 0.
--   - Example execution:
--       VARIABLE p_user_name VARCHAR2(100);
--       VARIABLE p_days_back NUMBER;
--       EXEC lower('&username') := 'wgriffith2';
--       EXEC :p_days_back := 365;
--       <run the SELECT statement below>
--   - Monitor execution plan for XMLAGG subquery and add indexes on utl_d_it.sn_sys_audit(task_sys_id, field_name, change_created_by)
--     if queries are slow.
-- =============================================================================
SELECT t.number_ AS task_number,
       t.sys_id,
       t.due_date,
       t.closed_at,
       su.user_name,
       -- Compute actual effort in hours from a textual timestamp (guarded by regex)
       MAX(nvl(round((CASE
                     WHEN regexp_like(t.work_effort, '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$') THEN
                      (to_date(t.work_effort, 'yyyy-mm-dd hh24:mi:ss') - to_date('1970-01-01 00:00:00', 'yyyy-mm-dd hh24:mi:ss')) * 24
                     ELSE
                      NULL
                     END), 2), 0)) AS actual_effort_hours,
       dbms_lob.substr(t.short_description, 3900) AS short_description,
       dbms_lob.substr(t.description, 3900) AS description,
       comms.listed_comments AS work_notes
  FROM utl_p_sn.task t
  JOIN utl_p_sn.sys_user su
    ON t.assigned_to = su.sys_id
  LEFT JOIN utl_p_sn.sys_user requested_for
    ON requested_for.sys_id = coalesce(t.requested_for, t.opened_by)
  LEFT JOIN utl_p_sn.sys_choice sc
    ON sc.value = to_char(t.state)
   AND sc.element = 'state'
   AND sc.name = t.sys_class_name
   AND sc.inactive = 0
   AND sc.sys_id <> '676bd0e8e0835000364971011e6341fb'
  LEFT JOIN utl_p_sn.sc_req_item sri
    ON sri.sys_id = t.sys_id
  LEFT JOIN utl_p_sn.sc_cat_item sci
    ON sri.cat_item = sci.sys_id
  LEFT JOIN utl_p_sn.cmdb_ci cmdb_ci
    ON cmdb_ci.sys_id = t.cmdb_ci
  LEFT JOIN utl_p_sn.cmdb cmdb
    ON cmdb.sys_id = t.cmdb_ci
  LEFT JOIN utl_p_sn.sys_documentation sdoc
    ON sdoc.element IS NULL
   AND sdoc.name = t.sys_class_name
  LEFT JOIN utl_d_it.sn_group_hierarchy ag
    ON ag.group_sys_id = t.assignment_group
  LEFT JOIN utl_d_it.sn_default_group_history dgh
    ON dgh.user_sys_id = su.sys_id
   AND t.closed_at BETWEEN dgh.from_date AND dgh.to_date
  LEFT JOIN utl_d_it.sn_group_hierarchy ai
    ON ai.group_sys_id = coalesce(dgh.default_group_sys_id, su.u_default_group)
  JOIN (
        -- Build distinct values per task (emulate LISTAGG(DISTINCT ...))
        -- then aggregate with XMLAGG ordered by sequence_number into a CLOB,
        -- finally truncate to 3900 bytes to avoid ORA-01489 and excessive payload.
        SELECT inner_sn.task_sys_id AS sn_task_sysid_p,
                dbms_lob.substr(xmlserialize(content xmlagg(xmlelement(e, inner_sn.value_ || '; ') ORDER BY inner_sn.sequence_number) AS CLOB), 3900) AS listed_comments
          FROM (SELECT DISTINCT task_sys_id,
                                 value_,
                                 sequence_number
                   FROM utl_d_it.sn_sys_audit
                  WHERE field_name IN ('comments', 'work_notes')
                    AND change_created_by = lower('&username')
                    AND value_ IS NOT NULL
                    AND TRIM(value_) <> 'JOURNAL FIELD ADDITION') inner_sn
         GROUP BY inner_sn.task_sys_id) comms
    ON comms.sn_task_sysid_p = t.sys_id
 WHERE su.user_name = lower('&username')
   AND t.due_date > (SYSDATE - nvl(nullif(&days_back, 0), 365))
   AND nvl(sc.label, '-') = 'Closed'
   AND t.sys_class_name NOT IN ('sc_request', 'sysapproval_group')
   AND lower(nvl(ai.division_name, '')) LIKE '%ads%'
 GROUP BY t.number_,
          t.sys_id,
          su.user_name,
          t.due_date,
          t.closed_at,
          dbms_lob.substr(t.short_description, 3900),
          dbms_lob.substr(t.description, 3900),
          comms.listed_comments
 ORDER BY t.closed_at DESC;
