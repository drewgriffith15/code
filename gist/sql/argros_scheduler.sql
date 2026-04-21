--Argos Schedules Sending to Non-Employees
SELECT m.argos_server,
       m.full_path,
       m.schedule_name,
       m.schedule_lastrundate,
       m.next_run_date,
       e.email_address
  FROM zargos_data.evebargsmeta m
  JOIN zargos_data.evebargsemal e
    ON e.argos_server = m.argos_server
   AND e.email_id = m.email_id
   AND e.email_address_line <> 'From'
  JOIN general.goremal em
    ON TRIM(upper(em.goremal_email_address)) = TRIM(upper(e.email_address))
   AND em.goremal_emal_code = 'LU'
 WHERE m.argos_server = 'argosreports03'
   AND m.full_path NOT LIKE '@TRASHBIN%'
   AND m.next_run_date IS NOT NULL
   AND m.schedule_active = 'Y'
   AND e.email_address like trim(lower(&email)) -- 'jbblunk@liberty.edu'
/*and (m.full_path like 'Banner.Housing%' or 
m.full_path like 'Banner.Center for ME%' or
m.full_path like 'Banner.CSER%' or 
m.full_path like 'Banner.Housing%' or
m.full_path like 'Banner.Liberty%' or 
m.full_path like 'Banner.LU Serve%' or
m.full_path like 'Banner.LU Sheph%' or 
m.full_path like 'Banner.LU Stage%' or
m.full_path like 'Banner.LUSend%' or
m.full_path like 'Banner.ODAS%' or
m.full_path like 'Banner.Office of Equity%' or 
m.full_path like 'Banner.SGA%' or
m.full_path like 'Banner.Student Health Records%' or
m.full_path like 'Banner.Student Leadership%' or 
m.full_path like 'Banner.Student Life%' or
m.full_path like 'Conduct.%' or
m.full_path like 'Banner.BIO_Academics.ADS Student Affairs%' or
m.full_path like 'Banner.BIO_Academics.ADS Academics Dev%' or
m.full_path like 'Banner.BIO_Academics.ADS Academics Application Support%')*/
 ORDER BY email_address,
          full_path;
