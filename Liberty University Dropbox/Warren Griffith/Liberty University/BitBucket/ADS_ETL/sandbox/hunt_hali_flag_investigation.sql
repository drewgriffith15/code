-- Investigation: Missing Red Flags for Hali Hunt, Spring 2026 (term 202620)
-- Purpose: Identify what red flags disappeared and trace audit history
-- Author: Claude Code
-- Date: 2026-05-13

-- PART 1: Current state - what records exist now for Hali Hunt in the active table
SELECT 'PART 1: CURRENT STATE (far_luo_audit)' AS section FROM dual;
SELECT
    fla.term_code,
    fla.crn,
    fla.compliance_category_code,
    fla.faculty_name,
    fla.flag_count,
    fla.status,
    fla.deleted_ind,
    fla.deleted_reason,
    fla.audit_date,
    fla.last_modified
FROM utl_d_lms.far_luo_audit fla
WHERE fla.term_code = '202620'
  AND UPPER(fla.faculty_name) LIKE '%HUNT%HALI%' OR UPPER(fla.faculty_name) LIKE '%HALI%HUNT%'
ORDER BY fla.crn, fla.compliance_category_code;

-- PART 2: Historical/deleted records in the log table
SELECT 'PART 2: HISTORICAL RECORDS (far_luo_audit_log)' AS section FROM dual;
SELECT
    flal.term_code,
    flal.crn,
    flal.compliance_category_code,
    flal.faculty_name,
    flal.flag_count,
    flal.status,
    flal.deleted_ind,
    flal.deleted_reason,
    flal.audit_date,
    flal.last_modified
FROM utl_d_lms.far_luo_audit_log flal
WHERE flal.term_code = '202620'
  AND (UPPER(flal.faculty_name) LIKE '%HUNT%HALI%' OR UPPER(flal.faculty_name) LIKE '%HALI%HUNT%')
ORDER BY flal.crn, flal.compliance_category_code, flal.last_modified DESC;

-- PART 3: Red flags that were deleted (flag_count > 0 in log but now deleted)
SELECT 'PART 3: RED FLAGS THAT DISAPPEARED' AS section FROM dual;
SELECT
    flal.term_code,
    flal.crn,
    flal.compliance_category_code,
    flal.faculty_name,
    flal.flag_count AS historical_flag_count,
    flal.status AS historical_status,
    flal.deleted_ind AS historical_deleted_ind,
    flal.deleted_reason,
    flal.audit_date,
    flal.last_modified AS log_last_modified,
    CASE
        WHEN flal.deleted_ind = 'Y' THEN 'MANUALLY DELETED'
        WHEN flal.flag_count > 0 AND flal.status = 'EXPIRED' THEN 'EXPIRED'
        WHEN flal.flag_count > 0 AND NOT EXISTS (
            SELECT 1 FROM utl_d_lms.far_luo_audit fla
            WHERE fla.term_code = flal.term_code
              AND fla.crn = flal.crn
              AND fla.compliance_category_code = flal.compliance_category_code
              AND fla.faculty_name = flal.faculty_name
        ) THEN 'REMOVED FROM ACTIVE TABLE'
        ELSE 'OTHER'
    END AS disappearance_reason
FROM utl_d_lms.far_luo_audit_log flal
WHERE flal.term_code = '202620'
  AND (UPPER(flal.faculty_name) LIKE '%HUNT%HALI%' OR UPPER(flal.faculty_name) LIKE '%HALI%HUNT%')
  AND flal.flag_count > 0
ORDER BY flal.crn, flal.compliance_category_code, flal.last_modified DESC;

-- PART 4: Timeline - all changes for this instructor, ordered by date
SELECT 'PART 4: COMPLETE AUDIT TRAIL' AS section FROM dual;
SELECT
    flal.last_modified,
    flal.term_code,
    flal.crn,
    flal.compliance_category_code,
    flal.flag_count,
    flal.status,
    flal.deleted_ind,
    flal.deleted_reason,
    flal.faculty_name
FROM utl_d_lms.far_luo_audit_log flal
WHERE flal.term_code = '202620'
  AND (UPPER(flal.faculty_name) LIKE '%HUNT%HALI%' OR UPPER(flal.faculty_name) LIKE '%HALI%HUNT%')
ORDER BY flal.last_modified DESC, flal.crn, flal.compliance_category_code;
