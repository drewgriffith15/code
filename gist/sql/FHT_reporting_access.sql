-- Checking Row level security in FHT -> FAR / FPT dashboards
-- search a user to see what they can see
-- **CURRENT TERM [unless changed]**
SELECT COUNT(*) over() total_rows,
       ll.instance,
       fht.term_code AS "Term Code",
       fht.crn AS crn,
       ll.course_code AS "Course Code",
       fht.instructor AS "Instructor",
       fht.instructor_username AS "Username",
       fht.pidm AS "PIDM",
       fht.college AS "College",
       ll.insm_code AS "Instr Method",
       CASE
       WHEN instructor_username LIKE TRIM(lower('%&ENTER_USERNAME%')) THEN
        'Y'
       ELSE
        NULL
       END AS "Instructor",
       CASE
       WHEN dean_usernames LIKE TRIM(lower('%&ENTER_USERNAME%')) THEN
        'Y'
       ELSE
        NULL
       END AS "Dean",
       CASE
       WHEN chair_usernames LIKE TRIM(lower('%&ENTER_USERNAME%')) THEN
        'Y'
       ELSE
        NULL
       END AS "Chair",
       CASE
       WHEN im_usernames LIKE TRIM(lower('%&ENTER_USERNAME%')) THEN
        'Y'
       ELSE
        NULL
       END AS "IM",
       CASE
       WHEN sme_usernames LIKE TRIM(lower('%&ENTER_USERNAME%')) THEN
        'Y'
       ELSE
        NULL
       END AS "SME",
       CASE
       WHEN fsc_usernames LIKE TRIM(lower('%&ENTER_USERNAME%')) THEN
        'Y'
       ELSE
        NULL
       END AS "FSC",
       CASE
       WHEN fht.admin_usernames LIKE TRIM(lower('%&ENTER_USERNAME%')) THEN
        'Y'
       ELSE
        NULL
       END AS "Admin",
       ll.enrollment AS "Enrollment",
       'https://faculty-hierarchy.liberty.edu/#/people/' || fht.pidm AS url -- must be an exact match to work
  FROM utl_d_aa.secfht fht
  JOIN utl_d_lms.lms_link ll
    ON ll.term_code = fht.term_code
   AND ll.crn = fht.crn
   AND SYSDATE BETWEEN ll.start_date - 7 AND ll.end_date + 30 -- only what shows on current term reports
 WHERE (fht.chair_usernames LIKE TRIM(lower('%&ENTER_USERNAME%')) OR fht.im_usernames LIKE TRIM(lower('%&ENTER_USERNAME%')) OR fht.sme_usernames LIKE TRIM(lower('%&ENTER_USERNAME%')) OR
       fht.dean_usernames LIKE TRIM(lower('%&ENTER_USERNAME%')) OR fht.fsc_usernames LIKE TRIM(lower('%&ENTER_USERNAME%')) OR fht.instructor_username LIKE TRIM(lower('%&ENTER_USERNAME%')) OR
       fht.admin_usernames LIKE lower('%&ENTER_USERNAME%'))
 ORDER BY fht.term_code  DESC,
          fht.instructor ASC;
