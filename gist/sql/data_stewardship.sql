-- ============================================================
-- SCHEMA : UTL_D_AA | UTL_D_AIM | UTL_D_LMS
-- ACCESS : MUST LOGIN AS WGRIFFITH2 -- PROXY NOT SUPPORTED
-- REVISED SECTION MAP:
--   SECTION 1  : SCHEMA-LEVEL FOOTPRINT SUMMARY      (fka S9)
--   SECTION 2  : TABLE INVENTORY + RECOMMENDATIONS   (fka S2, enhanced)
--   SECTION 3  : KEYWORD SEARCH IN QUERY TEXT        (fka S5)
--   SECTION 4  : INDEX ANALYSIS + ACTION CANDIDATES  (fka S7, enhanced)
--   SECTION 5  : TEMP/TEST TABLE ID + DROP DDL       (fka S10, enhanced)
-- ============================================================
-- ============================================================
-- SECTION 1: SCHEMA-LEVEL FOOTPRINT SUMMARY
--            Full segment-type rollup per owner.
--            Replaces the coarse quota view from prior Section 1.
--            ROLLUP row (segment_type = SCHEMA) = owner grand total.
-- ============================================================
SELECT nvl(roll.owner, 'ALL') AS owner,
       nvl(roll.segment_type, 'SCHEMA -- TOTAL') AS segment_type,
       roll.object_count,
       roll.total_mb,
       roll.total_gb
  FROM (SELECT s.owner,
               s.segment_type,
               COUNT(DISTINCT s.segment_name) AS object_count,
               round(SUM(s.bytes) / (1024 * 1024), 2) AS total_mb,
               round(SUM(s.bytes) / (1024 * 1024 * 1024), 3) AS total_gb
          FROM dba_segments s
         WHERE s.owner IN ('UTL_D_LMS', 'UTL_D_AA', 'UTL_D_AIM')
           AND substr(s.segment_name, 1, 4) <> 'BIN$'
         GROUP BY ROLLUP(s.owner, s.segment_type)) roll
 ORDER BY roll.owner    NULLS LAST,
          roll.total_mb DESC;
-- ============================================================
-- SECTION 2: EXHAUSTIVE TABLE + LOB SEGMENT INVENTORY
--            WITH STORAGE RECOMMENDATIONS
--
--            RECOMMENDATION LOGIC:
--            (a) HEAP > 10 GB, no compression   -> PARTITION + COMPRESS (HIGH PRIORITY)
--            (b) HEAP > 5  GB, no compression   -> EVALUATE PARTITIONING + BASIC COMPRESSION
--            (c) HEAP > 1  GB, no compression   -> EVALUATE BASIC COMPRESSION
--            (d) PARTITIONED, > 500 MB, DISABLED -> EVALUATE PARTITION-LEVEL COMPRESSION
--            (e) Large table, last_query_at NULL -> VALIDATE USAGE BEFORE ACTION
--
--            SUGGESTED DDL is surfaced inline for qualifying rows.
-- ============================================================
WITH segment_rollup AS
 (SELECT /*+ materialize */
   s.owner,
   CASE
   WHEN s.segment_type IN ('LOB', 'LOBINDEX') THEN
    (SELECT l.table_name
       FROM dba_lobs l
      WHERE l.owner = s.owner
        AND l.segment_name = s.segment_name
        AND rownum = 1)
   WHEN s.segment_type IN ('TABLE PARTITION', 'TABLE SUBPARTITION') THEN
    (SELECT tp.table_name
       FROM dba_tab_partitions tp
      WHERE tp.table_owner = s.owner
        AND tp.partition_name = s.partition_name
        AND rownum = 1)
   ELSE
    s.segment_name
   END AS table_name,
   s.segment_name,
   s.partition_name,
   s.segment_type,
   s.bytes / (1024 * 1024) AS segment_mb,
   s.blocks,
   s.extents
    FROM dba_segments s
   WHERE s.owner IN ('UTL_D_LMS', 'UTL_D_AA', 'UTL_D_AIM')
     AND s.segment_type IN ('TABLE', 'TABLE PARTITION', 'TABLE SUBPARTITION', 'LOB', 'LOBINDEX')
     AND substr(s.segment_name, 1, 4) <> 'BIN$'),
table_totals AS
 (SELECT /*+ materialize */
   owner,
   table_name,
   round(SUM(segment_mb), 2) AS total_size_mb,
   SUM(blocks) AS total_blocks,
   SUM(extents) AS total_extents,
   MAX(CASE
       WHEN segment_type = 'TABLE' THEN
        'HEAP'
       WHEN segment_type = 'TABLE PARTITION' THEN
        'PARTITIONED'
       WHEN segment_type = 'TABLE SUBPARTITION' THEN
        'SUBPARTITIONED'
       WHEN segment_type = 'LOB' THEN
        'LOB'
       ELSE
        segment_type
       END) AS dominant_type
    FROM segment_rollup
   GROUP BY owner,
            table_name),
tut AS
 (SELECT /*+ materialize */
   t.object_owner,
   t.object_name,
   l.username,
   l.sql_exec_start AS query_date,
   t.sql_id,
   MAX(CASE
       WHEN substr(l.username, -3) = 'SVC' THEN
        'Y'
       WHEN l.username IN ('ZARGOS', 'ZSSRS') THEN
        'Y'
       ELSE
        'N'
       END) over(PARTITION BY t.object_owner, t.object_name) AS svc_usage,
   rank() over(PARTITION BY t.object_owner, t.object_name ORDER BY decode(l.username, 'ZETL_JAMS_SVC', 0, 1) DESC, l.sql_exec_start DESC, rownum) AS ranking,
   COUNT(*) over(PARTITION BY t.object_owner, t.object_name) AS count_it
    FROM luetl.lu_tut_query_tables t
    JOIN luetl.lu_tut_query_log l
      ON t.sql_id = l.sql_id
   WHERE l.sql_exec_start > SYSDATE - 7
     AND t.object_owner IN ('UTL_D_LMS', 'UTL_D_AA', 'UTL_D_AIM'))
SELECT tot.owner,
       tot.table_name,
       -- -------------------------------------------------------
       -- RECOMMENDATION: action guidance for the DBA
       -- -------------------------------------------------------
       CASE
       WHEN tot.total_size_mb > 10240
            AND tot.dominant_type = 'HEAP'
            AND atb.compression = 'DISABLED' THEN
        'HIGH PRIORITY -- EVALUATE RANGE PARTITIONING + COMPRESS FOR QUERY HIGH'
       WHEN tot.total_size_mb > 5120
            AND tot.dominant_type = 'HEAP'
            AND atb.compression = 'DISABLED' THEN
        'EVALUATE PARTITIONING + BASIC COMPRESSION'
       WHEN tot.total_size_mb > 1024
            AND tot.dominant_type = 'HEAP'
            AND atb.compression = 'DISABLED' THEN
        'EVALUATE BASIC COMPRESSION'
       WHEN tot.dominant_type IN ('PARTITIONED', 'SUBPARTITIONED')
            AND atb.compression = 'DISABLED'
            AND tot.total_size_mb > 500 THEN
        'EVALUATE PARTITION-LEVEL COMPRESSION'
       WHEN tut.query_date IS NULL
            AND tot.total_size_mb > 100 THEN
        'NO RECENT USAGE -- VALIDATE BEFORE DROPPING OR ARCHIVING'
       ELSE
        'NO ACTION REQUIRED'
       END AS recommendation,
       -- -------------------------------------------------------
       -- SUGGESTED DDL: only emitted for actionable conditions
       -- -------------------------------------------------------
       CASE
       WHEN tot.total_size_mb > 10240
            AND tot.dominant_type = 'HEAP'
            AND atb.compression = 'DISABLED' THEN
        '/* VALIDATE PARTITION KEY FIRST */ ALTER TABLE ' || tot.owner || '.' || tot.table_name || ' MOVE COMPRESS FOR QUERY HIGH; -- then rebuild indexes'
       WHEN tot.total_size_mb > 1024
            AND tot.dominant_type = 'HEAP'
            AND atb.compression = 'DISABLED' THEN
        'ALTER TABLE ' || tot.owner || '.' || tot.table_name || ' MOVE COMPRESS BASIC; -- then rebuild indexes'
       WHEN tot.dominant_type IN ('PARTITIONED', 'SUBPARTITIONED')
            AND atb.compression = 'DISABLED'
            AND tot.total_size_mb > 500 THEN
        '/* APPLY PER-PARTITION */ ALTER TABLE ' || tot.owner || '.' || tot.table_name || ' COMPRESS FOR QUERY HIGH; -- affects future loads only without MOVE'
       ELSE
        NULL
       END AS suggested_ddl,
       tot.dominant_type AS storage_type,
       tot.total_size_mb,
       round(tot.total_size_mb / 1024, 3) AS total_size_gb,
       tot.total_blocks,
       tot.total_extents,
       atb.compression,
       atb.compress_for,
       atb.num_rows,
       atb.last_analyzed,
       tut.username AS last_used_by,
       tut.sql_id,
       tut.svc_usage,
       tut.count_it AS total_executions,
       tut.query_date AS last_query_at,
       comm.comments AS table_comments
  FROM table_totals tot
  JOIN all_tables atb
    ON atb.owner = tot.owner
   AND atb.table_name = tot.table_name
  LEFT JOIN tut
    ON tut.object_owner = tot.owner
   AND tut.object_name = tot.table_name
   AND tut.ranking = 1
  LEFT JOIN all_tab_comments comm
    ON comm.owner = tot.owner
   AND comm.table_name = tot.table_name
 WHERE substr(tot.table_name, 1, 4) <> 'BIN$'
   AND substr(tot.table_name, 1, 2) <> '#T'
   AND substr(tot.table_name, -3) <> 'GTT'
 ORDER BY tot.total_size_mb DESC,
          tut.query_date    ASC NULLS FIRST,
          tot.owner,
          tot.table_name;
-- ============================================================
-- SECTION 3: KEYWORD SEARCH IN CAPTURED QUERY TEXT
--            Replace the literal 'SQLTEXT' with the object
--            name, column, or keyword under investigation.
--            Use this to confirm whether an object is actively
--            referenced before decommissioning it.
-- ============================================================
SELECT MIN(l.capture_date) AS min_capture_date,
       MAX(l.capture_date) AS max_capture_date,
       COUNT(*) AS execution_count,
       l.username,
       dbms_lob.substr(t.sql_fulltext, 3950) AS full_text,
       t.sql_id
  FROM luetl.lu_tut_query_text t
  JOIN luetl.lu_tut_query_log l
    ON t.sql_id = l.sql_id
   AND dbms_lob.instr(lower(t.sql_fulltext), lower('&SQLTEXT'), 1, 1) > 0
 WHERE l.username NOT IN ('ADS_ETL', 'ZETL_JAMS_SVC', 'CANVAS_CTL', 'ZCANVAS_DATA_CTL')
   AND l.sql_exec_start > SYSDATE - 7
 GROUP BY l.username,
          dbms_lob.substr(t.sql_fulltext, 3950),
          t.sql_id
 ORDER BY l.username,
          t.sql_id;
-- ============================================================
-- SECTION 4: EXHAUSTIVE INDEX ANALYSIS
--            COMPRESSION CANDIDATES + REMOVAL CANDIDATES
--
--            COMPRESSION CANDIDATE CRITERIA (compress_candidate):
--              (a) index_mb > 100, DISABLED, NORMAL B-Tree, blevel >= 2
--              (b) index_mb > 500, DISABLED, NORMAL B-Tree (HIGH PRIORITY)
--
--            REMOVAL CANDIDATE CRITERIA (removal_candidate):
--              (a) total_access_count = 0 AND last_used IS NULL
--                  -- never accessed since monitoring began
--              (b) last_used < SYSDATE - 180
--                  -- cold for six months
--              (c) Combined with index_mb > 50
--                  -- worth reclaiming; small indexes flagged but deprioritized
--
--            Both compress_candidate and removal_candidate
--            surface inline DDL for immediate DBA use.
-- ============================================================
WITH index_segments AS
 (SELECT /*+ materialize */
   s.owner,
   s.segment_name AS index_name,
   round(SUM(s.bytes) / (1024 * 1024), 2) AS index_mb,
   SUM(s.blocks) AS total_blocks,
   SUM(s.extents) AS total_extents
    FROM dba_segments s
   WHERE s.owner IN ('UTL_D_LMS', 'UTL_D_AA', 'UTL_D_AIM')
     AND s.segment_type IN ('INDEX', 'INDEX PARTITION', 'INDEX SUBPARTITION')
     AND substr(s.segment_name, 1, 4) <> 'BIN$'
   GROUP BY s.owner,
            s.segment_name)
SELECT iseg.owner,
       iseg.index_name,
       di.table_name,
       -- -------------------------------------------------------
       -- COMPRESSION CANDIDATE FLAG
       -- -------------------------------------------------------
       CASE
       WHEN iseg.index_mb > 500
            AND di.compression = 'DISABLED'
            AND di.index_type = 'NORMAL' THEN
        'Y -- HIGH PRIORITY'
       WHEN iseg.index_mb > 100
            AND di.compression = 'DISABLED'
            AND di.index_type = 'NORMAL'
            AND dis.blevel >= 2
            AND di.uniqueness = 'NONUNIQUE' THEN
        'Y -- EVALUATE FOR COMPRESSION'
       ELSE
        'N'
       END AS compress_candidate,
       -- -------------------------------------------------------
       -- COMPRESSION DDL
       -- -------------------------------------------------------
       CASE
       WHEN iseg.index_mb > 100
            AND di.compression = 'DISABLED'
            AND di.index_type = 'NORMAL'
            AND dis.blevel >= 2
            AND di.uniqueness = 'NONUNIQUE' THEN
        'ALTER INDEX ' || iseg.owner || '.' || iseg.index_name || ' REBUILD COMPRESS ONLINE;'
       ELSE
        NULL
       END AS compress_ddl,
       -- -------------------------------------------------------
       -- REMOVAL CANDIDATE FLAG
       -- -------------------------------------------------------
       CASE
       WHEN (ciu.total_access_count = 0 OR ciu.total_access_count IS NULL)
            AND ciu.last_used IS NULL THEN
        'Y -- NEVER ACCESSED SINCE MONITORING BEGAN'
       WHEN ciu.last_used < SYSDATE - 180
            AND iseg.index_mb > 50 THEN
        'Y -- COLD 180+ DAYS, SIZE > 50 MB -- VALIDATE THEN DROP'
       WHEN ciu.last_used < SYSDATE - 90
            AND iseg.index_mb > 50 THEN
        'REVIEW -- COLD 90+ DAYS, SIZE > 50 MB'
       ELSE
        'N'
       END AS removal_candidate,
       -- -------------------------------------------------------
       -- REMOVAL DDL -- do not execute without Section 3 review
       -- -------------------------------------------------------
       CASE
       WHEN (ciu.total_access_count = 0 OR ciu.total_access_count IS NULL)
            AND ciu.last_used IS NULL THEN
        '/* VERIFY WITH SECTION 3 BEFORE EXECUTING */ DROP INDEX ' || iseg.owner || '.' || iseg.index_name || ';'
       WHEN ciu.last_used < SYSDATE - 180
            AND iseg.index_mb > 50 THEN
        '/* VERIFY WITH SECTION 3 BEFORE EXECUTING */ DROP INDEX ' || iseg.owner || '.' || iseg.index_name || ';'
       ELSE
        NULL
       END AS removal_ddl,
       di.index_type,
       di.partitioned,
       di.status,
       di.uniqueness,
       di.compression,
       iseg.index_mb,
       round(iseg.index_mb / 1024, 3) AS index_gb,
       iseg.total_blocks,
       iseg.total_extents,
       dis.blevel,
       dis.leaf_blocks,
       dis.distinct_keys,
       dis.clustering_factor,
       dis.num_rows AS index_num_rows,
       dis.last_analyzed,
       ciu.total_access_count,
       ciu.last_used,
       round(SYSDATE - ciu.last_used, 0) AS days_since_last_use
  FROM index_segments iseg
  JOIN dba_indexes di
    ON di.owner = iseg.owner
   AND di.index_name = iseg.index_name
  LEFT JOIN dba_ind_statistics dis
    ON dis.owner = iseg.owner
   AND dis.index_name = iseg.index_name
   AND dis.partition_name IS NULL -- headline stats row only
  LEFT JOIN sys.cdb_index_usage ciu
    ON ciu.owner = iseg.owner
   AND ciu.name = iseg.index_name
 WHERE substr(iseg.index_name, 1, 4) <> 'BIN$'
   AND substr(di.index_name, -2) <> 'PK'
   AND substr(di.index_name, 1, 2) <> 'PK'
   AND instr(di.index_name, 'UNIQUE_INDX') = 0
 ORDER BY iseg.index_mb   DESC,
          ciu.last_used   ASC NULLS FIRST,
          iseg.owner,
          iseg.index_name;
-- ============================================================
-- SECTION 5: TEST / TEMP / DEV TABLE IDENTIFICATION
--            WITH ACTIONABLE DROP DDL
--
--            INSTRUCTIONS:
--            (1) Run Section 3 (keyword search) against each
--                table_name returned here BEFORE executing DDL.
--            (2) Confirm zero usage in TUT query log.
--            (3) Execute the drop_ddl only after validation.
--
--            EXCLUSION LIST: tables confirmed as legitimate
--            despite matching the TEMP/TMP/TEST substring.
-- ============================================================
SELECT DISTINCT c.owner,
                c.table_name,
                seg.total_size_mb,
                atb.last_analyzed,
                atb.num_rows,
                -- Usage signal from rolling 30-day window
                (SELECT MAX(l.sql_exec_start)
                   FROM luetl.lu_tut_query_tables qt
                   JOIN luetl.lu_tut_query_log l
                     ON qt.sql_id = l.sql_id
                  WHERE qt.object_owner = c.owner
                    AND qt.object_name = c.table_name
                    AND l.sql_exec_start > SYSDATE - 30) AS last_query_30d,
                -- Actionable DDL -- validate with Section 3 first
                'DROP TABLE ' || c.owner || '.' || c.table_name || ' CASCADE CONSTRAINTS PURGE;' AS drop_ddl
  FROM all_tab_columns c
-- Join to confirm segment existence (avoids virtual/external refs)
  JOIN (SELECT owner,
               table_name,
               round(SUM(bytes) / (1024 * 1024), 2) AS total_size_mb
          FROM dba_segments
         WHERE segment_type IN ('TABLE', 'TABLE PARTITION', 'TABLE SUBPARTITION')
           AND owner IN ('UTL_D_LMS', 'UTL_D_AA', 'UTL_D_AIM')
           AND substr(segment_name, 1, 4) <> 'BIN$'
         GROUP BY owner,
                  table_name) seg
    ON seg.owner = c.owner
   AND seg.table_name = c.table_name
  JOIN all_tables atb
    ON atb.owner = c.owner
   AND atb.table_name = c.table_name
 WHERE c.owner IN ('UTL_D_LMS', 'UTL_D_AA', 'UTL_D_AIM')
   AND (instr(c.table_name, 'TEMP') > 0 OR instr(c.table_name, 'TMP') > 0 OR instr(c.table_name, 'TEST') > 0)
   AND c.table_name NOT IN
       ('STUTESTSCORES', 'ASGNATTEMPTS', 'ACSI_TEMP_IDBASE', 'EMBBSBGIACSI_TEMP_MATCH', 'EMBBSBGIACSI_TEMP_PK_U', 'STVSBGI_TEMP_MATCH', 'NADROPS_TEMP1', 'NADROPS_TEMP2', 'NADROPS_TEMP3', 'SZRDCPC_TEMP_AA', 'SZRDCPC_TEMP_BB', 'SZRDCPC_TEMP_CC', 'ZROOMUTIL_TEMP', 'ZCHATBDA_SZRTEMP')
 ORDER BY seg.total_size_mb DESC,
          c.owner,
          c.table_name;
-- ============================================================
-- ============================================================
-- SUPPLEMENTAL SCRIPT: UTL_D_LMS ORPHANED PARTITIONED INDEX
--                      DISCOVERY + CLEANUP DDL
--
--            PURPOSE:
--            Surfaces all INDEX PARTITION and INDEX SUBPARTITION
--            segments in UTL_D_LMS that belong to indexes with
--            no corresponding table constraint (non-PK, non-unique)
--            and have shown zero access activity.
--            Generates DROP INDEX DDL for DBA review.
--
--            EXECUTION PROTOCOL:
--            (1) Run the discovery block first (read-only).
--            (2) Cross-reference index_name in Section 3.
--            (3) Only execute DDL after confirming zero dependency.
--            (4) Run the generated drop_ddl statements individually.
-- ============================================================
-- ============================================================
