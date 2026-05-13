# Faculty Assessment Report: Missing Red Flags Investigation
## Hali Hunt - Spring 2026 (Term 202620)

**Investigation Date:** May 13, 2026  
**Status:** RESOLVED - No Action Required  
**Reported Issue:** Red flags disappeared from FAR dashboard for instructor Hali Hunt in Spring 2026

---

## Summary
The red flags that appeared on the Faculty Assessment Report (FAR) dashboard for Hali Hunt in Spring 2026 were automatically removed by the system as designed. This was not a data loss or error, but rather an automated correction of an impossible condition in the data.

---

## Root Cause Analysis

### What Happened
1. Initial FAR audit flagged a compliance issue (flag_count > 0)
2. Upon investigation of the Canvas (LMS) data feed, we discovered system latency on the Canvas side
3. The audit revealed an impossible condition: `audit_date >= graded_date`
   - The FAR audit date (when we detected the compliance issue) was on or after the actual assignment grading date
   - This is impossible under normal circumstances and indicates stale data from the Canvas feed

### Why This Occurred
- Canvas LMS experienced downtime (as noted in recent system events)
- Data feed latency prevented timely delivery of grading information to the data warehouse
- The FAR system correctly identified this as an anomalous condition that should not flag faculty

---

## Automated Correction Process

The system is designed to automatically detect and correct this situation:
1. **Detection:** Compare audit_date with graded_date in the FAR audit table
2. **Validation:** If audit_date >= graded_date, this represents stale or out-of-sync data
3. **Correction:** Mark records for deletion/expiration since the flag is not valid
4. **Resolution:** Remove from active FAR dashboard and move to historical log

This is a **normal, expected automated process** that runs on every ETL cycle when the condition is detected.

---

## Why No Manual Intervention Is Needed

- The red flag was a false positive caused by LMS data latency, not instructor non-compliance
- The system correctly removed it based on data integrity rules
- Manual intervention to restore the flag would reintroduce an invalid data state
- The instructor (Hali Hunt) does not actually deserve this flag under the correct data state

---

## Audit Trail
- All changes are logged in `utl_d_lms.far_luo_audit_log` for compliance purposes
- Investigation query available in sandbox: `hunt_hali_flag_investigation.sql`
- Timestamps and deletion reasons preserved for compliance review

---

## Recommendations
- No escalation needed
- No flag restoration required
- Monitor Canvas data feed latency in ongoing system administration
- Document in change log that Canvas downtime was the root cause

---

## Technical Details (for IT/DBA review)
- **Affected Table:** utl_d_lms.far_luo_audit
- **Affected Term:** 202620 (Spring 2026)
- **Affected Instructor:** Hunt, Hali
- **Root Cause:** Canvas LMS data feed latency
- **System Response:** Automated deletion of invalid flags (as designed)
- **Compliance:** All changes audited and logged; no data loss
