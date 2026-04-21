SELECT sites.name AS site_name,
       sites.id AS site_id,
       projects.name AS project_name,
       workbook.name AS workbook_name,
       views.name AS view_name,
       workbook_owner_name.name AS ads_owner,
       sys_user_arc.email AS viewer,
       http.completed_at AS usage_date,
       COUNT(*) over(PARTITION BY views.name) || ' views and ' || COUNT(DISTINCT sys_user_arc.id) over(PARTITION BY views.name) || ' users as of ' || to_char(&days_ago) || ' days ago' AS usage_stats,
       'https://reports.liberty.edu/#/site/' || REPLACE(sites.name, ' ', '') || '/workbooks/' || workbook.id || '/views' AS url,
       MIN(workbook.first_published_at) over() AS create_date,
       MAX(workbook.last_published_at) over() AS last_modified
  FROM tableau.workbooks workbook
  JOIN tableau.sites sites
    ON sites.id = workbook.site_id
   AND sites.id IN (14, 2, 17, 10, 72) --('academics', 'registrar', 'luoa', 'soaisc', 'jfl')
  LEFT JOIN tableau.projects projects
    ON workbook.project_id = projects.id
  LEFT JOIN arc_tableau.http_requests http
    ON workbook.site_id = http.site_id
   AND CAST(workbook.repository_url AS NVARCHAR2(255)) = substr(http.currentsheet, 0, instr(http.currentsheet, '/') - 1)
  LEFT JOIN tableau.views views
    ON views.site_id = http.site_id
   AND views.workbook_id = workbook.id
   AND substr(http.currentsheet, instr(http.currentsheet, '/') + 1) = views.sheet_id
  LEFT JOIN utl_d_or.tableau_users_arc arc_users
    ON arc_users.site_id = http.site_id
   AND arc_users.id = http.user_id
   AND arc_users.to_date > trunc(SYSDATE) --ADDED
  LEFT JOIN utl_d_or.tableau_system_users_arc sys_user_arc
    ON sys_user_arc.id = arc_users.system_user_id
  LEFT JOIN tableau.users workbook_owner
    ON workbook_owner.id = workbook.owner_id
   AND workbook_owner.site_id = sites.id
  LEFT JOIN tableau.system_users workbook_owner_name
    ON workbook_owner.system_user_id = workbook_owner_name.id
 WHERE http.action = 'show'
   AND lower(views.name) LIKE lower('%&view_name%')
   AND http.completed_at > SYSDATE - &days_ago
 ORDER BY workbook.name,
          http.completed_at DESC;
