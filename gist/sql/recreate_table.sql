-- this is a template for recreating a table (with partitioning)
BEGIN
enable_parallel_dml('Y');
END;
/
CREATE TABLE utl_d_lms.student_enrollments_tmp 
/*+ PARALLEL(8) NOLOGGING */
AS 
SELECT /*+ PARALLEL(8) */
 src.course_code,
 src.term_code,
 src.crn,
 src.pidm,
 src.luid,
 src.course_sis_id,
 src.section_sis_id,
 src.course_id,
 src.course_section_id,
 src.user_id,
 src.enrollment_id,
 src.role_id,
 src.course_name,
 src.subj_code,
 src.crse_numb,
 src.seq_numb,
 src.ptrm_code,
 src.camp_code,
 src.insm_code,
 src.levl_code,
 src.coll_code,
 src.created_date,
 src.updated_date,
 src.last_request,
 src.workflow_state,
 src.type,
 src.instance,
 src.start_date,
 src.end_date,
 src.partition,
 src.base_course,
 src.faculty_pidm,
 src.microsection,
 src.cross_listed,
 src.data_source,
 src.activity_date,
 standard_hash(nvl(to_char(src.course_code), '<NULL>') || '#' || nvl(to_char(src.term_code), '<NULL>') || '#' || nvl(to_char(src.crn), '<NULL>') || '#' || nvl(to_char(src.pidm), '<NULL>') || '#' || nvl(to_char(src.luid), '<NULL>') || '#' ||
               nvl(to_char(src.course_sis_id), '<NULL>') || '#' || nvl(to_char(src.section_sis_id), '<NULL>') || '#' || nvl(to_char(src.course_id), '<NULL>') || '#' || nvl(to_char(src.course_section_id), '<NULL>') || '#' ||
               nvl(to_char(src.user_id), '<NULL>') || '#' || nvl(to_char(src.enrollment_id), '<NULL>') || '#' || nvl(to_char(src.role_id), '<NULL>') || '#' || nvl(to_char(src.course_name), '<NULL>') || '#' ||
               nvl(to_char(src.subj_code), '<NULL>') || '#' || nvl(to_char(src.crse_numb), '<NULL>') || '#' || nvl(to_char(src.seq_numb), '<NULL>') || '#' || nvl(to_char(src.ptrm_code), '<NULL>') || '#' ||
               nvl(to_char(src.camp_code), '<NULL>') || '#' || nvl(to_char(src.insm_code), '<NULL>') || '#' || nvl(to_char(src.levl_code), '<NULL>') || '#' || nvl(to_char(src.coll_code), '<NULL>') || '#' ||
               nvl(to_char(src.created_date, 'YYYYMMDDHH24MISS'), '<NULL>') || '#' || nvl(to_char(src.updated_date, 'YYYYMMDDHH24MISS'), '<NULL>') || '#' || nvl(to_char(src.last_request), '<NULL>') || '#' ||
               nvl(to_char(src.workflow_state), '<NULL>') || '#' || nvl(to_char(src.type), '<NULL>') || '#' || nvl(to_char(src.instance), '<NULL>') || '#' || nvl(to_char(src.start_date, 'YYYYMMDD'), '<NULL>') || '#' ||
               nvl(to_char(src.end_date, 'YYYYMMDD'), '<NULL>') || '#' || nvl(to_char(src.partition), '<NULL>') || '#' || nvl(to_char(src.base_course), '<NULL>') || '#' || nvl(to_char(src.faculty_pidm), '<NULL>') || '#' ||
               nvl(to_char(src.microsection), '<NULL>') || '#' || nvl(to_char(src.cross_listed), '<NULL>') || '#' || nvl(to_char(src.data_source), '<NULL>'), 'MD5') AS row_hash
  FROM utl_d_lms.student_enrollments src
-- create table from current term
 WHERE src.term_code IN (SELECT terms.term_code
                           FROM zbtm.terms_by_group_v terms
                          WHERE 1 = 1
                            AND terms.group_code IN ('STD', 'MED', 'ACD')
                            AND terms.semester <> 'WIN'
                            AND SYSDATE >= terms.start_date - 7
                            AND SYSDATE <= terms.end_date + 7);
-- insert the rest of the terms into the tmp table
DECLARE
CURSOR c1 IS
SELECT DISTINCT t.term_code AS term_code
  FROM utl_d_lms.student_enrollments t
 WHERE NOT EXISTS (SELECT /*+ HASH_EXISTS */
         1
          FROM utl_d_lms.student_enrollments_tmp tmp
         WHERE tmp.term_code = t.term_code)
 ORDER BY 1 DESC;
c1fmt c1%ROWTYPE;
BEGIN
enable_parallel_dml('Y');
OPEN c1;
FETCH c1
INTO c1fmt;
WHILE c1%FOUND
LOOP
INSERT /*+ APPEND PARALLEL(8) NOLOGGING */
INTO utl_d_lms.student_enrollments_tmp (course_code,
                                        term_code,
                                        crn,
                                        pidm,
                                        luid,
                                        course_sis_id,
                                        section_sis_id,
                                        course_id,
                                        course_section_id,
                                        user_id,
                                        enrollment_id,
                                        role_id,
                                        course_name,
                                        subj_code,
                                        crse_numb,
                                        seq_numb,
                                        ptrm_code,
                                        camp_code,
                                        insm_code,
                                        levl_code,
                                        coll_code,
                                        created_date,
                                        updated_date,
                                        last_request,
                                        workflow_state,
                                        type,
                                        instance,
                                        start_date,
                                        end_date,
                                        partition,
                                        base_course,
                                        faculty_pidm,
                                        microsection,
                                        cross_listed,
                                        data_source, 
                                        activity_date,
                                        row_hash)
SELECT /*+ PARALLEL(8) */
src.course_code,
src.term_code,
src.crn,
src.pidm,
src.luid,
src.course_sis_id,
src.section_sis_id,
src.course_id,
src.course_section_id,
src.user_id,
src.enrollment_id,
src.role_id,
src.course_name,
src.subj_code,
src.crse_numb,
src.seq_numb,
src.ptrm_code,
src.camp_code,
src.insm_code,
src.levl_code,
src.coll_code,
src.created_date,
src.updated_date,
src.last_request,
src.workflow_state,
src.type,
src.instance,
src.start_date,
src.end_date,
src.partition,
src.base_course,
src.faculty_pidm,
src.microsection,
src.cross_listed,
src.data_source,
src.activity_date,
standard_hash(nvl(to_char(src.course_code), '<NULL>') || '#' || nvl(to_char(src.term_code), '<NULL>') || '#' || nvl(to_char(src.crn), '<NULL>') || '#' || nvl(to_char(src.pidm), '<NULL>') || '#' || nvl(to_char(src.luid), '<NULL>') || '#' ||
               nvl(to_char(src.course_sis_id), '<NULL>') || '#' || nvl(to_char(src.section_sis_id), '<NULL>') || '#' || nvl(to_char(src.course_id), '<NULL>') || '#' || nvl(to_char(src.course_section_id), '<NULL>') || '#' ||
               nvl(to_char(src.user_id), '<NULL>') || '#' || nvl(to_char(src.enrollment_id), '<NULL>') || '#' || nvl(to_char(src.role_id), '<NULL>') || '#' || nvl(to_char(src.course_name), '<NULL>') || '#' ||
               nvl(to_char(src.subj_code), '<NULL>') || '#' || nvl(to_char(src.crse_numb), '<NULL>') || '#' || nvl(to_char(src.seq_numb), '<NULL>') || '#' || nvl(to_char(src.ptrm_code), '<NULL>') || '#' ||
               nvl(to_char(src.camp_code), '<NULL>') || '#' || nvl(to_char(src.insm_code), '<NULL>') || '#' || nvl(to_char(src.levl_code), '<NULL>') || '#' || nvl(to_char(src.coll_code), '<NULL>') || '#' ||
               nvl(to_char(src.created_date, 'YYYYMMDDHH24MISS'), '<NULL>') || '#' || nvl(to_char(src.updated_date, 'YYYYMMDDHH24MISS'), '<NULL>') || '#' || nvl(to_char(src.last_request), '<NULL>') || '#' ||
               nvl(to_char(src.workflow_state), '<NULL>') || '#' || nvl(to_char(src.type), '<NULL>') || '#' || nvl(to_char(src.instance), '<NULL>') || '#' || nvl(to_char(src.start_date, 'YYYYMMDD'), '<NULL>') || '#' ||
               nvl(to_char(src.end_date, 'YYYYMMDD'), '<NULL>') || '#' || nvl(to_char(src.partition), '<NULL>') || '#' || nvl(to_char(src.base_course), '<NULL>') || '#' || nvl(to_char(src.faculty_pidm), '<NULL>') || '#' ||
               nvl(to_char(src.microsection), '<NULL>') || '#' || nvl(to_char(src.cross_listed), '<NULL>') || '#' || nvl(to_char(src.data_source), '<NULL>'), 'MD5') AS row_hash
  FROM utl_d_lms.student_enrollments src
 WHERE src.term_code = c1fmt.term_code;
COMMIT;
FETCH c1
INTO c1fmt;
END LOOP;
CLOSE c1;
END;
/
-- ENSURE WE HAVE ALL THE DATA
SELECT t.term_code,
       COUNT(*) total
  FROM utl_d_lms.student_enrollments_tmp t
 GROUP BY t.term_code
 ORDER BY 1 DESC; -- pull all terms from source table
--- 
-- ***STOP HERE - IMPORTANT***
-- ***NOW, GO COPY/PASTE THE EXISTING TABLE CREATE***
-- ***THEN, GO UPDATE THE LOADING PROCEDURE AT THE BOTTOM *BEFORE* DROPPING TABLE***
---
-- DROP TABLE student_enrollments purge;
-- Create table
create table STUDENT_ENROLLMENTS
(
  course_code       VARCHAR2(255 CHAR),
  term_code         VARCHAR2(6 CHAR) not null,
  crn               VARCHAR2(9) not null,
  pidm              NUMBER(8) not null,
  luid              VARCHAR2(9 CHAR),
  course_sis_id     VARCHAR2(50),
  section_sis_id    VARCHAR2(50),
  course_id         NUMBER,
  course_section_id NUMBER,
  user_id           NUMBER,
  enrollment_id     NUMBER,
  role_id           NUMBER,
  course_name       VARCHAR2(255 CHAR),
  subj_code         VARCHAR2(4 CHAR),
  crse_numb         VARCHAR2(5 CHAR),
  seq_numb          VARCHAR2(3 CHAR),
  ptrm_code         VARCHAR2(3 CHAR),
  camp_code         VARCHAR2(3 CHAR),
  insm_code         VARCHAR2(5 CHAR),
  levl_code         CHAR(2),
  coll_code         VARCHAR2(2 CHAR),
  created_date      TIMESTAMP(6),
  updated_date      TIMESTAMP(6),
  last_request      TIMESTAMP(6),
  workflow_state    VARCHAR2(1020),
  type              VARCHAR2(1020),
  instance          VARCHAR2(128),
  start_date        DATE,
  end_date          DATE,
  partition         NUMBER,
  base_course       VARCHAR2(255),
  faculty_pidm      NUMBER,
  microsection      VARCHAR2(50),
  cross_listed      VARCHAR2(1) default 'N',
  data_source       VARCHAR2(50) default 'CDE',
  surrogate_id      NUMBER generated by default as identity,
  activity_date     DATE default SYSDATE,
  row_hash          RAW(16)
)
PARTITION BY LIST (TERM_CODE) automatic
 (
 PARTITION P000000 VALUES ('000000')
 )
tablespace UTILITY
  pctfree 10
  initrans 1
  maxtrans 255
  storage
  (
    initial 64K
    next 1M
    minextents 1
    maxextents unlimited
  );

-- Add comments to the table 
comment on table STUDENT_ENROLLMENTS
  is 'WGRIFFITH2 - Table used to link to Banner to Canvas on student and course (https://subversion.liberty.edu/svn/bio/academics/sql/ADS_ETL)';
-- Add comments to the columns 
comment on column STUDENT_ENROLLMENTS.course_code
  is 'Course code in Canvas';
comment on column STUDENT_ENROLLMENTS.term_code
  is 'Banner course term_code, and primary join field; do NOT use this field for non-term courses';
comment on column STUDENT_ENROLLMENTS.crn
  is 'Banner course crn, and primary join field; do NOT use this field for non-term courses';
comment on column STUDENT_ENROLLMENTS.pidm
  is 'Unique student identification number, and primary join field; do NOT use this field for non-term courses';
comment on column STUDENT_ENROLLMENTS.luid
  is 'Liberty University ID';
comment on column STUDENT_ENROLLMENTS.course_sis_id
  is 'Course import id between Banner and Canvas';
comment on column STUDENT_ENROLLMENTS.section_sis_id
  is 'Course import id between Banner and Canvas';
comment on column STUDENT_ENROLLMENTS.course_id
  is 'Canvas course_id';
comment on column STUDENT_ENROLLMENTS.course_section_id
  is 'Canvas course_section_id';
comment on column STUDENT_ENROLLMENTS.user_id
  is 'User ID in Canvas';
comment on column STUDENT_ENROLLMENTS.enrollment_id
  is 'Enrollment ID in Canvas';
comment on column STUDENT_ENROLLMENTS.role_id
  is 'Role ID in Canvas';
comment on column STUDENT_ENROLLMENTS.course_name
  is 'Canvas and/or Banner course name';
comment on column STUDENT_ENROLLMENTS.subj_code
  is 'Banner course subject';
comment on column STUDENT_ENROLLMENTS.crse_numb
  is 'Banner course number';
comment on column STUDENT_ENROLLMENTS.seq_numb
  is 'Banner course sequence';
comment on column STUDENT_ENROLLMENTS.ptrm_code
  is 'Banner course ptrm_code';
comment on column STUDENT_ENROLLMENTS.camp_code
  is 'Banner course campus';
comment on column STUDENT_ENROLLMENTS.insm_code
  is 'Banner course instructional method';
comment on column STUDENT_ENROLLMENTS.levl_code
  is 'Banner course level';
comment on column STUDENT_ENROLLMENTS.coll_code
  is 'Banner course college';
comment on column STUDENT_ENROLLMENTS.created_date
  is 'Date when the record was created';
comment on column STUDENT_ENROLLMENTS.updated_date
  is 'Timestamp of when the record was last updated in the Canvas database';
comment on column STUDENT_ENROLLMENTS.last_request
  is 'Last request timestamp';
comment on column STUDENT_ENROLLMENTS.workflow_state
  is 'Lifecycle for the record';
comment on column STUDENT_ENROLLMENTS.type
  is 'Type of enrollment';
comment on column STUDENT_ENROLLMENTS.instance
  is 'Canvas instance';
comment on column STUDENT_ENROLLMENTS.start_date
  is 'Course start date';
comment on column STUDENT_ENROLLMENTS.end_date
  is 'Course end date';
comment on column STUDENT_ENROLLMENTS.partition
  is 'SHOULD NOT BE USED FOR REPORTING. This is only used for batch/parallel processing for jobs';
comment on column STUDENT_ENROLLMENTS.base_course
  is 'Specific to LUOA that determines the course grouping based on scbsupp_subj_code and scbsupp_crse_numb in Banner';
comment on column STUDENT_ENROLLMENTS.faculty_pidm
  is 'Primary instructor for the course; only populates if there is a banner connection for the course';
comment on column STUDENT_ENROLLMENTS.microsection
  is 'Course is a microsection if the section ID shows up; otherwise it is NULL';
comment on column STUDENT_ENROLLMENTS.cross_listed
  is 'Course is a cross_listed Y/N';
comment on column STUDENT_ENROLLMENTS.data_source
  is 'What data source last updated the record';
comment on column STUDENT_ENROLLMENTS.surrogate_id
  is 'DEFAULT AS IDENTITY, -- Incremental ID';
comment on column STUDENT_ENROLLMENTS.activity_date
  is 'SYSDATE -- The last time the record was insert/updated on the table';
comment on column STUDENT_ENROLLMENTS.row_hash
  is 'MD5 hash representing a unique combination of key fields for change tracking';

-- Unique index on TERM_CODE, CRN, PIDM
CREATE UNIQUE INDEX IDX_STU_ENROLL_UK_TERM_CRN_PIDM
ON STUDENT_ENROLLMENTS (TERM_CODE, CRN, PIDM)
TABLESPACE UTILITY
PCTFREE 10 INITRANS 2 MAXTRANS 255
STORAGE (
    INITIAL 64K
    NEXT 1M
    MINEXTENTS 1
    MAXEXTENTS UNLIMITED
);

-- Index on INSTANCE, TERM_CODE, PARTITION
CREATE INDEX IDX_STU_ENROLL_INST_TERM_PART
ON STUDENT_ENROLLMENTS (INSTANCE, TERM_CODE, PARTITION)
TABLESPACE UTILITY
PCTFREE 10 INITRANS 2 MAXTRANS 255
STORAGE (
    INITIAL 64K
    NEXT 1M
    MINEXTENTS 1
    MAXEXTENTS UNLIMITED
);

-- Index on ROW_HASH
CREATE INDEX IDX_STU_ENROLL_ROW_HASH
ON STUDENT_ENROLLMENTS (ROW_HASH)
TABLESPACE UTILITY
PCTFREE 10 INITRANS 2 MAXTRANS 255
STORAGE (
    INITIAL 64K
    NEXT 1M
    MINEXTENTS 1
    MAXEXTENTS UNLIMITED
);

-- Unique index on INSTANCE, COURSE_SECTION_ID, USER_ID
CREATE UNIQUE INDEX IDX_STU_ENROLL_UK_INST_CSID_UID
ON STUDENT_ENROLLMENTS (INSTANCE, COURSE_SECTION_ID, USER_ID)
TABLESPACE UTILITY
PCTFREE 10 INITRANS 2 MAXTRANS 255
STORAGE (
    INITIAL 64K
    NEXT 1M
    MINEXTENTS 1
    MAXEXTENTS UNLIMITED
);

-- Grant/Revoke object privileges 
grant select, insert, update, delete, references, alter, index, debug, read on STUDENT_ENROLLMENTS to ADS_ETL with grant option;
grant select on STUDENT_ENROLLMENTS to CANVAS_READER_ROLE;
grant select, insert, update, delete on STUDENT_ENROLLMENTS to DWILLIAMS4 with grant option;
grant select, insert, update, delete on STUDENT_ENROLLMENTS to KCULPEPPER5 with grant option;
grant select, insert, update, delete on STUDENT_ENROLLMENTS to LAGALLAGHER;
grant select, insert, update, delete on STUDENT_ENROLLMENTS to MAPEELE with grant option;
grant select, insert, update, delete on STUDENT_ENROLLMENTS to R_STATS_SVC with grant option;
grant select on STUDENT_ENROLLMENTS to STUDENTINFORMATIONAPI_SVC;
grant select on STUDENT_ENROLLMENTS to TWILCOXEN;
grant select, insert, update, delete on STUDENT_ENROLLMENTS to UTL_D_AA with grant option;
grant select, insert, update, delete on STUDENT_ENROLLMENTS to UTL_D_AIM with grant option;
grant select on STUDENT_ENROLLMENTS to UTL_D_BIO;
grant select on STUDENT_ENROLLMENTS to UTL_D_LUO;
grant select, insert, update, delete, references, alter, index, debug, read on STUDENT_ENROLLMENTS to WGRIFFITH2 with grant option;
grant select, insert, update, delete on STUDENT_ENROLLMENTS to WRUMINN with grant option;
grant select on STUDENT_ENROLLMENTS to ZARGOS_Q_ROLE;
grant select on STUDENT_ENROLLMENTS to ZATHLETE_SVC with grant option;
grant select on STUDENT_ENROLLMENTS to ZATOZ_SVC;
grant select, insert, update, delete on STUDENT_ENROLLMENTS to ZETL_JAMS_SVC with grant option;
grant select on STUDENT_ENROLLMENTS to ZIS_ZEXEC with grant option;
grant select on STUDENT_ENROLLMENTS to ZIXL_SVC;
grant read on STUDENT_ENROLLMENTS to ZOBSERVATIONDECK with grant option;
grant read on STUDENT_ENROLLMENTS to ZOBSERVATIONDECK_SVC with grant option;
grant select on STUDENT_ENROLLMENTS to ZSOC_APP;
grant select on STUDENT_ENROLLMENTS to ZTABLEAU_SVC;
grant select on STUDENT_ENROLLMENTS to Z_BANPROD_DBLINK_ROLE;

-- insert records back into the table
DECLARE
CURSOR c1 IS
SELECT /*+ PARALLEL(4) */
DISTINCT t.term_code AS term_code
  FROM utl_d_lms.student_enrollments_tmp t
 ORDER BY 1 DESC;
c1fmt c1%ROWTYPE;
BEGIN
enable_parallel_dml('Y');
OPEN c1;
FETCH c1
INTO c1fmt;
WHILE c1%FOUND
LOOP
INSERT /*+ APPEND PARALLEL(8) NOLOGGING */
INTO utl_d_lms.student_enrollments (course_code,
                                    term_code,
                                    crn,
                                    pidm,
                                    luid,
                                    course_sis_id,
                                    section_sis_id,
                                    course_id,
                                    course_section_id,
                                    user_id,
                                    enrollment_id,
                                    role_id,
                                    course_name,
                                    subj_code,
                                    crse_numb,
                                    seq_numb,
                                    ptrm_code,
                                    camp_code,
                                    insm_code,
                                    levl_code,
                                    coll_code,
                                    created_date,
                                    updated_date,
                                    last_request,
                                    workflow_state,
                                    type,
                                    instance,
                                    start_date,
                                    end_date,
                                    partition,
                                    base_course,
                                    faculty_pidm,
                                    microsection,
                                    cross_listed,
                                    data_source, 
                                    activity_date,
                                    row_hash)
SELECT /*+ PARALLEL(8) */
src.course_code,
src.term_code,
src.crn,
src.pidm,
src.luid,
src.course_sis_id,
src.section_sis_id,
src.course_id,
src.course_section_id,
src.user_id,
src.enrollment_id,
src.role_id,
src.course_name,
src.subj_code,
src.crse_numb,
src.seq_numb,
src.ptrm_code,
src.camp_code,
src.insm_code,
src.levl_code,
src.coll_code,
src.created_date,
src.updated_date,
src.last_request,
src.workflow_state,
src.type,
src.instance,
src.start_date,
src.end_date,
src.partition,
src.base_course,
src.faculty_pidm,
src.microsection,
src.cross_listed,
src.data_source,
src.activity_date,
src.row_hash
  FROM utl_d_lms.student_enrollments_tmp src
 WHERE src.term_code = c1fmt.term_code;
COMMIT;
FETCH c1
INTO c1fmt;
END LOOP;
CLOSE c1;
END;
/
BEGIN
gather_stats('student_enrollments');
END;
/
-- ENSURE ALL DATA EXISTS 
SELECT term_code,
       COUNT(*) c
  FROM utl_d_lms.student_enrollments
 GROUP BY term_code
 ORDER BY term_code; 
 -- 
-- DROP TABLE student_enrollments_tmp PURGE ;
 
