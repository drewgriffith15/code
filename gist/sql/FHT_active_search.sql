-- Query handles missing approver roles and provide clear labeling for both Resident and Online faculty searches.
-- This version ensures that all expected approver roles are shown, even if no user is assigned, and provides clear messaging for missing connections.
-- **Search for faculty position** allows for searching the faculty name, LUID, or username to return FHT connections
WITH
-- Define expected approver roles for each campus type
expected_roles AS
 (SELECT 'Resident' AS campus,
         2 AS role_order,
         '2 - Chair' AS approver_position
    FROM dual
  UNION ALL
  SELECT 'Resident',
         3,
         '3 - Assistant/Associate Dean'
    FROM dual
  UNION ALL
  SELECT 'Resident',
         4,
         '4 - Dean'
    FROM dual
  UNION ALL
  SELECT 'Online',
         2,
         '2 - Instructional Mentor'
    FROM dual
  UNION ALL
  SELECT 'Online',
         3,
         '3 - Chair'
    FROM dual
  UNION ALL
  SELECT 'Online',
         4,
         '4 - Dean'
    FROM dual),
-- Find the searched faculty and their campus type
searched_faculty AS
 (SELECT DISTINCT fht.pidm,
                  CASE
                  WHEN fht.camp_code = 'D' THEN
                   'Online'
                  ELSE
                   'Resident'
                  END AS campus
    FROM utl_d_aa.faculty_hierarchy fht
   WHERE (fht.pidm IN (SELECT gobtpac_pidm FROM gobtpac WHERE lower(gobtpac.gobtpac_external_user) LIKE TRIM(lower('%&SEARCH_NAME_LUID_USERNAME%'))) OR
         fht.pidm IN (SELECT spriden_pidm
                         FROM spriden
                        WHERE spriden_change_ind IS NULL
                          AND lower(spriden_id) LIKE TRIM(lower('%&SEARCH_NAME_LUID_USERNAME%'))) OR lower(fht.superior) LIKE TRIM(lower('%&SEARCH_NAME_LUID_USERNAME%')))
     AND SYSDATE BETWEEN fht.from_date AND fht.to_date
     AND fht.hierarchy_title_id <> 0
     AND fht.coll_code <> 'PO'),
-- Get all actual approver connections for the searched faculty
actual_approvers AS
 (SELECT CASE
         WHEN fht.superior_position = 'Faculty' THEN
          '1 - Faculty'
         WHEN fht.superior_position = 'Instructional Mentor' THEN
          '2 - Instructional Mentor'
         WHEN fht.superior_position = 'Chair' THEN
          '3 - Chair'
         WHEN fht.superior_position = 'Assistant/Associate Dean' THEN
          '4 - Assistant/Associate Dean'
         WHEN fht.superior_position = 'Dean' THEN
          '5 - Dean'
         WHEN fht.superior_position = 'Faculty Support Coordinator' THEN
          '6 - FSC'
         END AS approver_position,
         fht.superior_username AS username,
         fht.superior AS full_name,
         nvl(stvcoll_desc, fht.coll_code) AS college,
         CASE
         WHEN fht.camp_code = 'D' THEN
          'Online'
         ELSE
          'Resident'
         END AS campus,
         fht.url,
         fht.from_date,
         fht.pidm
    FROM utl_d_aa.faculty_hierarchy fht
    LEFT JOIN saturn.stvcoll
      ON stvcoll_code = fht.coll_code
   WHERE (fht.pidm IN (SELECT gobtpac_pidm FROM gobtpac WHERE lower(gobtpac.gobtpac_external_user) LIKE TRIM(lower('%&SEARCH_NAME_LUID_USERNAME%'))) --
         OR fht.pidm IN (SELECT spriden_pidm
                            FROM spriden
                           WHERE spriden_change_ind IS NULL
                             AND lower(spriden_id) LIKE TRIM(lower('%&SEARCH_NAME_LUID_USERNAME%'))) --
         OR lower(fht.superior) LIKE TRIM(lower('%&SEARCH_NAME_LUID_USERNAME%')))
     AND SYSDATE BETWEEN fht.from_date AND fht.to_date
     AND fht.hierarchy_title_id <> 0
     AND fht.coll_code <> 'PO')
-- Main SELECT: For each expected role, show the actual approver if present, or a message if missing
SELECT (SELECT spriden_last_name || ', ' || spriden_first_name
          FROM spriden
         WHERE spriden_change_ind IS NULL
           AND sf.pidm = spriden_pidm) AS faculty_search,
       er.approver_position,
       nvl(aa.username, 'No approver listed for this role in FHT') AS username,
       nvl(aa.full_name, 'No approver listed for this role in FHT') AS full_name,
       sf.campus,
       aa.college,
       aa.url AS url,
       aa.from_date as effective_date
  FROM searched_faculty sf
  JOIN expected_roles er
    ON er.campus = sf.campus
  LEFT JOIN actual_approvers aa
    ON aa.approver_position = er.approver_position
   AND aa.campus = sf.campus
   AND aa.pidm = sf.pidm
 ORDER BY sf.campus,
          aa.college,
          er.role_order;
