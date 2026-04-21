-- the following query looks for active running jobs...
WITH job_last_start AS
 (SELECT job.job_location,
         job.job_name,
         job.activity_date,
         job.message_type,
         job.message_text,
         coalesce(job.instance, 'NONE') AS instance,
         job.partition,
         job.job_id,
         job.secs,
         job.recs,
         rank() over(PARTITION BY job.job_name, coalesce(job.instance, 'NONE'), job.partition ORDER BY job.activity_date DESC, rownum) ranking
    FROM utl_d_lms.job_log_view job
   WHERE substr(TRIM(upper(job.message_text)), 1, 5) = 'BEGIN'
     AND TRIM(upper(job.job_name)) NOT LIKE '%TEST%'
     AND job.activity_date >= SYSDATE - 1 / 24),
active_jobs AS
 (SELECT job.job_location,
         job.job_name,
         job.instance,
         job.partition,
         job.job_id,
         CASE
         WHEN jl.message_type IS NULL THEN
          'INFO'
         ELSE
          jl.message_type
         END AS message_type,
         CASE
         WHEN jl.message_text IS NULL THEN
          'Job is currently running...'
         ELSE
          jl.message_text
         END AS message_text,
         (coalesce(jl.activity_date, SYSDATE) - job.activity_date) * 86400 AS secs,
         coalesce(jl.recs, 0) AS recs
    FROM job_last_start job
    LEFT JOIN utl_d_lms.job_log_view jl
      ON jl.job_id = job.job_id
     AND TRIM(upper(jl.job_name)) NOT LIKE '%TEST%'
     AND substr(TRIM(upper(jl.message_text)), 1, 3) = 'END'
   WHERE 1 = 1
     AND ranking = 1
     AND jl.job_id IS NULL
  --            AND job.job_name = 'etl_lms_student_assignments'
  --              AND job.job_id = 'FFF452F7AB825AC2862A6233663E96B3'
  )
SELECT job.job_name,
       job.message_text msg_text,
       job.message_type AS msg_type,
       job.instance || ' - ' || job.partition AS part,
       job.secs AS secs,
       CASE
       WHEN lag(job.activity_date) over(PARTITION BY job.job_id ORDER BY job.activity_date) IS NULL THEN
        0 -- First row for this job_id
       ELSE
        (job.activity_date - lag(job.activity_date) over(PARTITION BY job.job_id ORDER BY job.activity_date)) * 86400
       END AS gap,
       aj.secs AS runtime,
       job.recs AS recs,
       job.job_id,
       job.job_location AS job_location,
       job.activity_date
  FROM utl_d_lms.job_log_view job
  JOIN active_jobs aj
    ON aj.job_id = job.job_id
 ORDER BY job_location,
          job_name,
          part,
          job_id,
          activity_date,
          surrogate_id;
-- the following query looks for failures / runaways over selected timeframe
SELECT to_char((&lookback_in_days)) || ' day(s)' AS timeframe,
       job.job_name,
       job.instance || ' - ' || to_char(MAX(job.partition) + 1) AS parts,
       MAX(CASE
           WHEN sta_end = 'END' THEN
            job.activity_date
           ELSE
            NULL
           END) AS last_complete,
       COUNT(DISTINCT job.job_id) AS starts, -- includes all partitions
       SUM(CASE
           WHEN sta_end = 'END' THEN
            1
           ELSE
            0
           END) AS ends, -- includes all partitions 
       COUNT(DISTINCT job.job_id) - SUM(CASE
                                        WHEN sta_end = 'END' THEN
                                         1
                                        ELSE
                                         0
                                        END) AS fails, -- includes all partitions      
       nvl(round(MAX(CASE
                     WHEN job.recs > 0 THEN
                      job.recs
                     END)), 0) AS max_recs,
       nvl(round(AVG(CASE
                     WHEN job.recs > 0 THEN
                      job.recs
                     END)), 0) AS avg_recs,
       round(MAX(job.secs)) AS max_secs,
       round(AVG(job.secs)) AS avg_secs,
       MAX(max_gap.gap) AS max_gap,
       listagg(DISTINCT job.job_location, '; ') within GROUP(ORDER BY 1) AS job_location
  FROM (SELECT job.job_location,
               job.job_name,
               job.activity_date,
               job.message_type,
               job.message_text,
               job.instance,
               job.partition,
               job.job_id,
               job.secs,
               job.recs,
               substr(TRIM(upper(job.message_text)), 1, 3) AS sta_end,
               rank() over(PARTITION BY job.job_id ORDER BY job.activity_date DESC, job.surrogate_id DESC) ranking -- last output for each job run
          FROM utl_d_lms.job_log_view job
          JOIN (SELECT DISTINCT job_id
                 FROM utl_d_lms.job_log_view
                WHERE (substr(TRIM(upper(job_log_view.message_text)), 1, 5) = 'BEGIN' -- look for jobs started
                      AND job_log_view.activity_date >= SYSDATE - (&lookback_in_days) -- within the last day
                      AND job_log_view.activity_date < SYSDATE - 1 / 24) -- before the last hour so we do not get currently running jobs
               ) starts
            ON starts.job_id = job.job_id
         WHERE 1 = 1
           AND job.job_location IN ('ZETL_JAMS_SVC', '2WJXH63')
           AND job.activity_date >= SYSDATE - (&lookback_in_days)
           AND TRIM(upper(job.job_name)) NOT LIKE '%TEST%') job
  JOIN (SELECT job_id,
               surrogate_id,
               gap,
               rank() over(PARTITION BY job.job_id ORDER BY gap DESC, job.surrogate_id DESC) ranking -- largest, most recent gap for each job run
          FROM (SELECT job_id,
                       job.surrogate_id,
                       CASE
                       WHEN lag(job.activity_date) over(PARTITION BY job.job_id ORDER BY job.activity_date) IS NULL THEN
                        0 -- First row for this job_id
                       ELSE
                        (job.activity_date - lag(job.activity_date) over(PARTITION BY job.job_id ORDER BY job.activity_date)) * 86400
                       END AS gap
                  FROM utl_d_lms.job_log_view job
                 WHERE (job.activity_date >= SYSDATE - (&lookback_in_days) -- within the last day
                       AND job.activity_date < SYSDATE - 1 / 24) -- before the last hour so we do not get currently running jobs
                ) job) max_gap
    ON max_gap.job_id = job.job_id
   AND max_gap.ranking = 1
 WHERE 1 = 1
   AND job.ranking = 1
   AND job.job_name LIKE lower('%&job_name_search%')
 GROUP BY job.job_name,
          job.instance
 ORDER BY fails    DESC,
          avg_secs DESC NULLS LAST;
-- the following query looks for a particular job and provides hourly metrics on select job over selected timeframe
SELECT job.job_name,
       --        regexp_replace(listagg(DISTINCT upper(job.instance), ' & ') within GROUP(ORDER BY 1), '([^-]*)(-\1)+($|-)', '\1\3') AS instances,
       job.instance,
       to_char(activity_date, 'HH24') AS hr,
       COUNT(DISTINCT job.instance || ' - ' || job.partition) AS parts,
       SUM(CASE
           WHEN substr(job.message_text, 1, 5) = 'BEGIN' THEN
            1
           ELSE
            0
           END) AS starts,
       SUM(CASE
           WHEN substr(job.message_text, 1, 3) = 'END' THEN
            1
           ELSE
            0
           END) AS ends,
       round(AVG(CASE
                 WHEN substr(job.message_text, 1, 3) = 'END' THEN
                  job.secs
                 END)) AS secs,
       round(AVG(CASE
                 WHEN substr(job.message_text, 1, 3) = 'END' THEN
                  job.recs
                 END)) AS recs,
       round(SUM(CASE
                 WHEN substr(job.message_text, 1, 5) = 'START' THEN
                  1
                 ELSE
                  0
                 END)) AS loops
  FROM utl_d_lms.job_log_view job
 WHERE 1 = 1
   AND job.job_name LIKE lower('%&job_name_search%')
   AND job.activity_date >= SYSDATE - (&lookback_in_days) -- within the last day
 GROUP BY job.job_name,
          job.instance,
          to_char(activity_date, 'HH24')
 ORDER BY job.instance,
          job_name,
          hr
