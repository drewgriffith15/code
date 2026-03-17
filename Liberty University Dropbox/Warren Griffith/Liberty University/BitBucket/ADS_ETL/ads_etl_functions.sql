-- =============================================================================
-- PURPOSE: Generates a daily reporting spine for academic cohorts and return terms, calculating elapsed day offsets from term start dates and broadcasting current-day metadata across all historical rows within the reporting window.
--
-- TARGET(S): ads_etl.get_term_dates (SQL macro function returning inline view)
--
-- UNIQUE KEY / INDEX: cohort_term, return_term, camp_code, group_code, report_number (spine date identifier)
--
-- BUSINESS LOGIC & CONDITIONS:
-- - Identifies cohort terms (enrollment entry points) and their corresponding next-term return terms, filtered to active academic years (v_acad_year parameter) and campus groups (STD for Distance, STD+MED for Regional).
-- - Establishes a 90-day pre-return-term reporting window (timeframe_start_date) extending backward from the return term start date, enabling capture of pre-enrollment activity.
-- - Constructs a daily spine for each cohort-return term pair, generating one row per calendar day from the 90-day pre-window through the return term end date (optionally extended by v_extend_end_date for audit-trail reporting).
-- - Excludes cohort terms coded as '000000' or with semester type 'WIN' (Winter; non-standard academic periods).
-- - Excludes cohort start dates before August 15, 2008 (historical data cutoff).
-- - Includes only cohort terms where the 90-day pre-window start date is within 7 years of today (default v_days_back = 2,555 days), or a custom lookback period specified by the caller.
-- - Excludes cohort terms and return terms that have not yet started as of today (all spine rows must be historical; BOUNDARY 3).
-- - Suppresses February 29 spine rows entirely to prevent leap-year positional drift in day-number calculations.
-- - Calculates term_day_number as signed elapsed days from return_start_date (day 0 = first return term day; negative values = pre-term dates within the 90-day window).
-- - Calculates current_term_day_number by capturing yesterday's (SYSDATE-1) elapsed day offset from return_start_date, broadcast across all rows within the same semester partition (e.g., all FAL cohorts grouped separately from SPR, SUM).
-- - Range-clamps current_term_day_number to ensure the broadcast value falls within the valid day-number range of the spine for that term (lower bound ≈ -90 at timeframe_start_date; upper bound = day of final return-term day).
-- - When SYSDATE-1 is absent from the spine (e.g., a historical single-term pull), applies fallback logic to resolve yesterday's elapsed-day offset directly from the row-level return_start_date.
-- - Broadcasts SYSDATE-1 day-of-week (ISO standard: 1=Sunday, 7=Saturday) across all rows via current_day_of_week, with fallback to TO_CHAR(SYSDATE-1,'D') when yesterday is absent from the spine.
-- - Formats report_number as an 8-digit YYYYMMDD timestamp derived from the spine date, enabling date-based sorting and joins.
-- - Sets expiration_date to 23:58:59 on the spine date (one minute and one second before midnight) for audit-trail record retention policies.
-- - Sets report_timestamp to 23:59:00 on the spine date for consistency with standard end-of-business reporting conventions.
-- - Campus code filtering: v_camp_code='D' includes only STD group; v_camp_code='R' includes STD and MED groups.
-- - Returns rows in chronological order from timeframe_start_date through return_end_date (plus optional extension).
--
-- DEPENDENCIES: zbtm.terms_by_group_v (source of term metadata), ads_etl.get_next_term_code() (function to retrieve the next-term code given a cohort term and campus code)
--
-- CONSTRAINTS & RISKS:
-- - Current_term_day_number range-clamping ensures the broadcast value is always representable as an actual spine row for that term; out-of-range values (before timeframe_start_date or after return_end_date) are clamped to spine boundaries.
-- - Assumes return_start_date and return_end_date are non-NULL for all matching return terms; NULL values in these fields suppress output rows and result in NULL term_day_number and current_term_day_number.
-- - The 90-day pre-window (timeframe_start_date) is a fixed offset; no business-day or holiday calendar adjustments are applied.
-- - Large v_days_back values (deep historical lookback) combined with multiple cohort-return term pairs may generate extremely large result sets; consumer applications must implement pagination or filtering.
-- - CONNECT BY LEVEL <= 1000 limits the maximum spine length to 1,000 days per cohort-return term pair; terms with longer durations will be truncated.
-- =============================================================================
CREATE OR REPLACE FUNCTION ads_etl.get_term_dates(
    v_acad_year       VARCHAR2 DEFAULT NULL,
    v_days_back       NUMBER   DEFAULT NULL,
    v_camp_code       VARCHAR2 DEFAULT NULL,
    v_extend_end_date NUMBER   DEFAULT 0
) RETURN VARCHAR2 SQL_MACRO IS
BEGIN
    RETURN q'[
SELECT terms.cohort_term,
       terms.return_term,
       terms.camp_code,
       terms.group_code,
       -- Semester identifier derived from the return term; enables cross-year
       -- positional matching of the same semester type (e.g. FAL vs FAL).
       terms.semester,
       -- Cohort term hard boundaries (no buffers applied)
       terms.cohort_start_date,
       to_date(to_char(trunc(terms.cohort_end_date), 'MM/DD/YYYY') || ' 23:59:00', 'MM/DD/YYYY HH24:MI:SS') AS cohort_end_date,
       -- Return term hard boundaries (no buffers applied)
       terms.return_start_date,
       to_date(to_char(trunc(terms.return_end_date), 'MM/DD/YYYY') || ' 23:59:00', 'MM/DD/YYYY HH24:MI:SS') AS return_end_date,
       -- =========================================================================
       -- TERM DAY NUMBER
       -- Whole-number days elapsed since the return-term START date, computed
       -- entirely in TRUNC-date space.  Anchoring to the start date (not the end
       -- date) ensures day 0 falls on the first day of the return term, matching
       -- the acad_day_number convention in get_acad_dates.
       --
       -- PREVIOUS (broken): GREATEST(0, TRUNC(return_end_date) - TRUNC(spine_date))
       --   -> counted DOWN (days remaining); day 0 on final day; negative post-term
       --     values clamped, masking audit-tail position entirely.
       --
       -- FIXED: TRUNC(spine_date) - TRUNC(return_start_date)
       --   -> day  0 = return term start date
       --   -> day -1 = one day before term opens (90-day pre-window values are negative)
       --   -> day  N = Nth day into the return term
       --
       -- Signed offset is intentional and semantically correct; no GREATEST(0,...)
       -- floor is applied, mirroring get_acad_dates acad_day_number exactly.
       -- NULL-safe: if return_start_date is NULL (missing term data), field is NULL.
       -- =========================================================================
       CASE
       WHEN terms.return_start_date IS NOT NULL THEN
        (trunc(terms.timeframe_start_date + dates.numb) - trunc(terms.return_start_date))
       END AS term_day_number,
       -- =========================================================================
       -- CURRENT TERM DAY NUMBER (broadcast, range-clamped)
       -- Window MAX captures yesterday's term_day_number for all rows sharing the
       -- same semester partition (FAL partitioned separately from SPR, SUM, etc.),
       -- enabling cross-cohort semester-level comparisons.
       --
       -- PREVIOUS (broken):
       --   Window inner CASE anchored to return_end_date (days remaining); fallback
       --   also subtracted from return_end_date -- both inverted relative to the
       --   start-date convention required.
       --
       -- FIXED: inner CASE and fallback both anchor to return_start_date so the
       -- broadcast value is the signed elapsed-day offset from the return term
       -- start date, consistent with term_day_number above.
       --
       -- RANGE CLAMP (new):
       --   The raw broadcast or fallback value may lie outside the valid day range
       --   for this term's spine when SYSDATE-1 falls before timeframe_start_date
       --   (too-negative) or after return_end_date (too-positive).  Both extremes
       --   are clamped via GREATEST/LEAST so the result is always expressible as
       --   an actual row in this term's spine:
       --     lower bound = trunc(timeframe_start_date) - trunc(return_start_date)
       --                   (≈ -90; the day_number of the first spine row)
       --     upper bound = trunc(return_end_date)      - trunc(return_start_date)
       --                   (day_number of the final return-term day)
       --
       -- COALESCE fallback fires when SYSDATE-1 is absent from the spine (e.g. a
       -- historical single-term pull).  The fallback resolves yesterday's position
       -- directly from the row-level return_start_date -- semantically correct
       -- because "days elapsed" is always anchored to that term's own start
       -- boundary.  This mirrors the get_acad_dates pattern for
       -- current_acad_day_number, without a scalar subquery, since return_start_date
       -- is already in scope.
       --
       -- No GREATEST(0,...) floor applied to the signed offset itself; clamping is
       -- applied only at the spine boundary level described above.
       -- =========================================================================
       CASE
        WHEN terms.return_start_date IS NOT NULL THEN
         greatest(
                  -- Lower bound: day_number of the first spine row (≈ -90)
                  trunc(terms.timeframe_start_date) - trunc(terms.return_start_date), least(
                         -- Upper bound: day_number of the final return-term day
                         trunc(terms.return_end_date) - trunc(terms.return_start_date), coalesce(MAX(CASE
                                       WHEN trunc(terms.timeframe_start_date + dates.numb) = trunc(SYSDATE - 1)
                                            AND terms.return_start_date IS NOT NULL THEN
                                        (trunc(terms.timeframe_start_date + dates.numb) - trunc(terms.return_start_date))
                                       END) over(PARTITION BY terms.semester),
                                   -- Fallback: resolve yesterday's elapsed offset from the row-level
                                  -- return_start_date when SYSDATE-1 is absent from the spine.
                                  (trunc(SYSDATE - 1) - trunc(terms.return_start_date)))))
       END AS current_term_day_number,
       -- =========================================================================
       -- CALENDAR DAY-OF-WEEK FIELDS
       -- day_of_week: ISO day-of-week for the spine date (1=Sunday, 7=Saturday),
       -- consistent with get_acad_dates convention.
       -- current_day_of_week: broadcasts SYSDATE-1 day-of-week across all rows;
       -- COALESCE fallback applies TO_CHAR(SYSDATE-1,'D') directly when SYSDATE-1
       -- is absent from the spine, mirroring get_acad_dates behaviour exactly.
       -- =========================================================================
       to_number(to_char(trunc(terms.timeframe_start_date + dates.numb), 'D')) AS day_of_week,
       coalesce(MAX(CASE
                    WHEN trunc(terms.timeframe_start_date + dates.numb) = trunc(SYSDATE - 1) THEN
                     to_number(to_char(trunc(terms.timeframe_start_date + dates.numb), 'D'))
                    END) over(),
                -- Fallback: SYSDATE-1 day-of-week when absent from the spine
                to_number(to_char(trunc(SYSDATE - 1), 'D'))) AS current_day_of_week,
       to_number(to_char(terms.timeframe_start_date + dates.numb + 1, 'YYYYMMDD')) AS report_number,
       to_date(to_char(trunc(terms.timeframe_start_date + dates.numb), 'MM/DD/YYYY') || ' 23:59:00', 'MM/DD/YYYY HH24:MI:SS') AS report_timestamp,
       to_date(to_char(trunc(terms.timeframe_start_date + dates.numb), 'MM/DD/YYYY') || ' 23:58:59', 'MM/DD/YYYY HH24:MI:SS') AS expiration_date
  FROM (
        -- Inner subquery: one row per (cohort_term, return_term, group_code,
        -- semester) with all hard term boundaries and the 90-day pre-start
        -- reporting timeframe anchor.
        SELECT ct.cohort_term,
                ads_etl.get_next_term_code(ct.cohort_term, v_camp_code) AS return_term,
                v_camp_code AS camp_code,
                rt.group_code,
                -- Semester type from the return term (e.g. FAL, SPR, SUM).
                rt.semester,
                -- Cohort term hard boundaries
                MIN(ct.cohort_start_date) AS cohort_start_date,
                MAX(ct.cohort_end_date) AS cohort_end_date,
                -- Return term hard boundaries
                MIN(rt.start_date) AS return_start_date,
                MAX(rt.end_date) AS return_end_date,
                -- TIMEFRAME_START_DATE: 90-day pre-return-term window anchor.
                MIN(rt.start_date - 90) AS timeframe_start_date,
                -- TIMEFRAME_END_DATE: hard upper boundary at MAX return term end date.
                MAX(rt.end_date) AS timeframe_end_date
          FROM (SELECT t.term_code AS cohort_term,
                        MIN(t.start_date) AS cohort_start_date,
                        MAX(t.end_date) AS cohort_end_date
                   FROM zbtm.terms_by_group_v t
                  WHERE t.term_code NOT IN ('000000')
                    AND t.semester NOT IN ('WIN')
                    AND t.start_date - 90 < SYSDATE
                    AND t.start_date >= DATE '2008-08-15'
                    AND (v_acad_year IS NULL OR t.fa_proc_year = v_acad_year)
                    AND ((v_camp_code = 'D' AND t.group_code IN ('STD')) OR (v_camp_code = 'R' AND t.group_code IN ('STD', 'MED')))
                  GROUP BY t.term_code) ct
          JOIN zbtm.terms_by_group_v rt
            ON rt.term_code = ads_etl.get_next_term_code(ct.cohort_term, v_camp_code)
           AND rt.term_code != ct.cohort_term
           AND rt.semester NOT IN ('WIN')
           AND rt.start_date IS NOT NULL
           AND rt.end_date IS NOT NULL
           AND ((v_camp_code = 'D' AND rt.group_code IN ('STD')) OR (v_camp_code = 'R' AND rt.group_code IN ('STD', 'MED')))
         GROUP BY ct.cohort_term,
                   rt.group_code,
                   rt.semester) terms
  JOIN (SELECT LEVEL - 1 AS numb FROM dual CONNECT BY LEVEL <= 1000) dates
-- BOUNDARY 1: Hard lower bound -- spine begins at the 90-day pre-term anchor
    ON terms.timeframe_start_date + dates.numb >= terms.timeframe_start_date
      -- BOUNDARY 2: Hard upper bound extended by v_extend_end_date for audit-tail
      -- consumers; term_day_number calculations remain anchored to return_start_date.
   AND terms.timeframe_start_date + dates.numb <= terms.timeframe_end_date + nvl(v_extend_end_date, 0)
      -- BOUNDARY 3: Do not surface dates that have not yet occurred
   AND terms.timeframe_start_date + dates.numb < trunc(SYSDATE)
      -- BOUNDARY 4: Optional look-back cap (default 7 years = 2,555 days)
   AND terms.timeframe_start_date + dates.numb >= trunc(SYSDATE - nvl(v_days_back, 2555))
      -- BOUNDARY 5: Suppress Feb 29 to prevent leap-year positional drift
   AND to_char(trunc(terms.timeframe_start_date + dates.numb), 'MM/DD') <> '02/29'
      -- BOUNDARY 6: Stop the spine on the final day of the return term when not
      -- in audit-tail mode.  When v_extend_end_date > 0, this boundary is
      -- intentionally relaxed; spine extends past return_end_date for audit-tail
      -- consumers as documented in the purpose header.
   AND (v_extend_end_date > 0 OR trunc(terms.timeframe_start_date + dates.numb) <= trunc(terms.return_end_date))
    ]';
END;
/

-- =============================================================================
-- PURPOSE: Generates a comprehensive academic and fiscal calendar snapshot with corrected day/week numbering (capped at calendar boundaries), term resolution, and current-day broadcasts for cohort analytics and institutional reporting.
--
-- TARGET(S): zbtm.terms_by_group_v (source), output result set
--
-- TARGET(S): ads_etl.get_acad_dates (SQL Macro Function), zbtm.terms_by_group_v (source view)
--
-- BUSINESS LOGIC & CONDITIONS:
-- - FISCAL YEAR AXIS (July 1 - June 30):
--   * Fiscal day number counts upward from 0 on July 1 (timeframe_start_date); capped at maximum 365 days per fiscal year.
--   * Fiscal week number counts upward from 0 on July 1 (week 0 = July 1-7); increments every 7 days; capped at maximum 52 weeks per fiscal year.
--   * Current fiscal day/week numbers are broadcast across all rows via window function, defaulting to yesterday's calculation if SYSDATE-1 falls outside the date spine.
--   * Current fiscal day is anchored to the dynamically derived live fiscal year's July 1 boundary (month >= 7 uses current-year July 1; otherwise prior-year July 1).
--
-- - ACADEMIC YEAR AXIS (First term start date - Last non-Winter term end date):
--   * Academic day number counts upward from 0 on acad_start_date; capped at maximum 365 days per academic year.
--   * Academic week number counts upward from 0 on acad_start_date; increments every 7 days; capped at maximum 52 weeks per academic year.
--   * Current academic day/week numbers are broadcast across all rows via window function; defaults to live academic year's acad_start_date if SYSDATE-1 is absent from spine.
--   * Current academic day is resolved from the live academic year (derived from SYSDATE-1 month and year) via scalar subquery against zbtm.terms_by_group_v.
--
-- - DATE SPINE & FILTERING:
--   * Generates one row per calendar day within the fiscal year (July 1 - June 30) that falls within acad_start_date to acad_end_date + optional extension.
--   * Excludes February 29 (leap day) to maintain calendar consistency.
--   * Restricts spine to rows older than SYSDATE (excludes today and future dates).
--   * Restricts spine to rows within the lookback window (defaults to 2555 days [7 years] prior to SYSDATE).
--
-- - TERM RESOLUTION:
--   * timeframe_current_term resolves the term code for each spine date by locating the first term whose start_date minus 90 days through end_date plus 7 days brackets the spine date.
--   * Includes only non-Winter semesters and standard group codes (STD).
--   * Defaults to timeframe_end_term if no qualifying term is found.
--
-- - REPORT TIMESTAMP FIELDS:
--   * report_number is the spine date + 1 day, formatted as YYYYMMDD integer.
--   * report_timestamp is the spine date at 23:59:00 (end-of-day snapshot marker).
--   * expiration_date is the spine date at 23:58:59 (one second before expiration).
--
-- - DAY-OF-WEEK FIELDS:
--   * day_of_week is the ISO day-of-week (1=Sunday, 7=Saturday) for the spine date.
--   * current_day_of_week broadcasts the day-of-week for SYSDATE-1; defaults to SYSDATE-1's day-of-week if spine does not contain SYSDATE-1.
--
-- DEPENDENCIES: zbtm.terms_by_group_v, SQL macro variables v_acad_year, v_extend_end_date, v_days_back
--
-- CONSTRAINTS & RISKS:
-- - Assumes acad_year is a numeric or character string formatted as four-digit concatenation (e.g., '2324' for 2023-24).
-- - Inline views (date spine via CONNECT BY, term aggregation subqueries) may cause performance degradation on very large date ranges or complex term structures.
-- - Scalar subquery lookups against zbtm.terms_by_group_v on every row introduce potential for repeated table scans; consider materialization if volume is excessive.
-- - Missing or NULL acad_start_date values will result in NULL academic day/week/current values for affected rows.
-- - Window function MAX() OVER() returns NULL if no row in the full result set matches SYSDATE-1; fallback logic depends on successful fa_proc_year derivation from SYSDATE-1.
-- =============================================================================
CREATE OR REPLACE FUNCTION ads_etl.get_acad_dates(
    v_acad_year       VARCHAR2 DEFAULT NULL,   -- expected 4-char academic year (e.g. '2425')
    v_days_back       NUMBER   DEFAULT NULL,   -- limit look-back window; defaults to 7 years (2555 days)
    v_extend_end_date NUMBER   DEFAULT 0       -- extend past June 30 fiscal boundary for audit-tail consumers
) RETURN VARCHAR2 SQL_MACRO IS
BEGIN
    RETURN q'[
SELECT terms.acad_year,
       terms.acad_start_date,
       terms.acad_end_date,
       terms.timeframe_start_date,
       terms.timeframe_end_date + nvl(v_extend_end_date, 0) AS timeframe_end_date,
       terms.timeframe_start_term,
       nvl((SELECT MIN(CASE
                      WHEN to_date(to_char(trunc(terms.timeframe_start_date + dates.numb), 'MM/DD/YYYY') || ' 23:59:00', 'MM/DD/YYYY HH24:MI:SS') BETWEEN t2.start_date - 90 AND t2.end_date + 7 THEN
                       t2.term_code
                      END)
             FROM zbtm.terms_by_group_v t2
            WHERE t2.fa_proc_year = to_char(terms.acad_year)
              AND t2.group_code IN ('STD')
              AND t2.semester NOT IN ('WIN')), terms.timeframe_end_term) AS timeframe_current_term,
       terms.timeframe_end_term,
       -- =========================================================================
       -- FISCAL DAY NUMBER
       -- =========================================================================
       (trunc(terms.timeframe_start_date + dates.numb) - trunc(terms.timeframe_start_date)) AS fiscal_day_number,
       -- =========================================================================
       -- CURRENT FISCAL DAY NUMBER (broadcast)
       -- Window MAX captures the value from whichever row in the full result set
       -- has a spine date matching SYSDATE-1.  When that match is absent (e.g. a
       -- single-AY historical pull), the COALESCE fallback anchors to the CURRENT
       -- fiscal year's July 1 — computed inline from SYSDATE-1 — so the result
       -- always reflects today's position within the live fiscal year rather than
       -- an offset relative to a stale timeframe_start_date.
       -- =========================================================================
       coalesce(MAX(CASE
                     WHEN trunc(terms.timeframe_start_date + dates.numb) = trunc(SYSDATE - 1) THEN
                      (trunc(terms.timeframe_start_date + dates.numb) - trunc(terms.timeframe_start_date))
                     END) over(),
                 -- Fallback: offset from the live fiscal year's July 1 boundary
                (trunc(SYSDATE - 1) - CASE
                 WHEN to_number(to_char(trunc(SYSDATE - 1), 'MM')) >= 7 THEN
                  to_date('07/01/' || to_char(trunc(SYSDATE - 1), 'YYYY'), 'MM/DD/YYYY')
                 ELSE
                  to_date('07/01/' || to_char(add_months(trunc(SYSDATE - 1), -6), 'YYYY'), 'MM/DD/YYYY')
                 END)) AS current_fiscal_day_number,
       -- =========================================================================
       -- FISCAL WEEK NUMBER
       -- =========================================================================
       floor((trunc(terms.timeframe_start_date + dates.numb) - trunc(terms.timeframe_start_date)) / 7) AS fiscal_week_number,
       -- =========================================================================
       -- CURRENT FISCAL WEEK NUMBER (broadcast)
       -- Same anchor correction as current_fiscal_day_number; FLOOR preserves
       -- consistent week-boundary alignment with the day-0 origin.
       -- =========================================================================
       coalesce(MAX(CASE
                     WHEN trunc(terms.timeframe_start_date + dates.numb) = trunc(SYSDATE - 1) THEN
                      floor((trunc(terms.timeframe_start_date + dates.numb) - trunc(terms.timeframe_start_date)) / 7)
                     END) over(),
                 -- Fallback: week offset from the live fiscal year's July 1 boundary
                floor((trunc(SYSDATE - 1) - CASE
                       WHEN to_number(to_char(trunc(SYSDATE - 1), 'MM')) >= 7 THEN
                        to_date('07/01/' || to_char(trunc(SYSDATE - 1), 'YYYY'), 'MM/DD/YYYY')
                       ELSE
                        to_date('07/01/' || to_char(add_months(trunc(SYSDATE - 1), -6), 'YYYY'), 'MM/DD/YYYY')
                       END) / 7)) AS current_fiscal_week_number,
       -- =========================================================================
       -- ACADEMIC DAY NUMBER
       -- =========================================================================
       CASE
       WHEN terms.acad_start_date IS NOT NULL THEN
        (trunc(terms.timeframe_start_date + dates.numb) - trunc(terms.acad_start_date))
       END AS acad_day_number,
       -- =========================================================================
       -- CURRENT ACADEMIC DAY NUMBER (broadcast)
       -- Window MAX captures the signed day offset for the row whose spine date
       -- equals SYSDATE-1.  When SYSDATE-1 is absent from the spine (historical
       -- single-AY pull), the COALESCE fallback resolves the live AY's acad_start_date
       -- via an inline scalar subquery keyed to the dynamically derived current
       -- fa_proc_year string — preventing the large positive offset that would result
       -- from subtracting a stale row-level acad_start_date from a modern SYSDATE-1.
       -- =========================================================================
       CASE
        WHEN terms.acad_start_date IS NOT NULL THEN
         coalesce(MAX(CASE
                      WHEN trunc(terms.timeframe_start_date + dates.numb) = trunc(SYSDATE - 1)
                           AND terms.acad_start_date IS NOT NULL THEN
                       (trunc(terms.timeframe_start_date + dates.numb) - trunc(terms.acad_start_date))
                      END) over(),
                  -- Fallback: offset from the live AY's acad_start_date resolved via scalar subquery
                 (trunc(SYSDATE - 1) - (SELECT MIN(t_curr.start_date)
                                           FROM zbtm.terms_by_group_v t_curr
                                          WHERE t_curr.fa_proc_year = CASE
                                                WHEN to_number(to_char(trunc(SYSDATE - 1), 'MM')) >= 7 THEN
                                                 to_char(to_number(to_char(trunc(SYSDATE - 1), 'YY'))) || to_char(to_number(to_char(trunc(SYSDATE - 1), 'YY')) + 1)
                                                ELSE
                                                 to_char(to_number(to_char(trunc(SYSDATE - 1), 'YY')) - 1) || to_char(to_number(to_char(trunc(SYSDATE - 1), 'YY')))
                                                END
                                            AND t_curr.group_code = 'STD'
                                            AND t_curr.semester != 'WIN')))
       END AS current_acad_day_number,
       -- =========================================================================
       -- ACADEMIC WEEK NUMBER
       -- =========================================================================
       CASE
       WHEN terms.acad_start_date IS NOT NULL THEN
        floor((trunc(terms.timeframe_start_date + dates.numb) - trunc(terms.acad_start_date)) / 7)
       END AS acad_week_number,
       -- =========================================================================
       -- CURRENT ACADEMIC WEEK NUMBER (broadcast)
       -- Identical fallback strategy as current_acad_day_number; FLOOR applied
       -- after the live acad_start_date subtraction for correct negative-week
       -- rounding on pre-term dates.
       -- =========================================================================
       CASE
        WHEN terms.acad_start_date IS NOT NULL THEN
         coalesce(MAX(CASE
                      WHEN trunc(terms.timeframe_start_date + dates.numb) = trunc(SYSDATE - 1)
                           AND terms.acad_start_date IS NOT NULL THEN
                       floor((trunc(terms.timeframe_start_date + dates.numb) - trunc(terms.acad_start_date)) / 7)
                      END) over(),
                  -- Fallback: week offset from the live AY's acad_start_date resolved via scalar subquery
                 floor((trunc(SYSDATE - 1) - (SELECT MIN(t_curr.start_date)
                                                 FROM zbtm.terms_by_group_v t_curr
                                                WHERE t_curr.fa_proc_year = CASE
                                                      WHEN to_number(to_char(trunc(SYSDATE - 1), 'MM')) >= 7 THEN
                                                       to_char(to_number(to_char(trunc(SYSDATE - 1), 'YY'))) || to_char(to_number(to_char(trunc(SYSDATE - 1), 'YY')) + 1)
                                                      ELSE
                                                       to_char(to_number(to_char(trunc(SYSDATE - 1), 'YY')) - 1) || to_char(to_number(to_char(trunc(SYSDATE - 1), 'YY')))
                                                      END
                                                  AND t_curr.group_code = 'STD'
                                                  AND t_curr.semester != 'WIN')) / 7))
       END AS current_acad_week_number,
       -- =========================================================================
       -- CALENDAR DAY-OF-WEEK FIELDS
       -- =========================================================================
       to_number(to_char(trunc(terms.timeframe_start_date + dates.numb), 'D')) AS day_of_week,
       coalesce(MAX(CASE
                    WHEN trunc(terms.timeframe_start_date + dates.numb) = trunc(SYSDATE - 1) THEN
                     to_number(to_char(trunc(terms.timeframe_start_date + dates.numb), 'D'))
                    END) over(), to_number(to_char(trunc(SYSDATE - 1), 'D'))) AS current_day_of_week,
       -- =========================================================================
       -- REPORT TIMESTAMP FIELDS
       -- =========================================================================
       to_number(to_char(terms.timeframe_start_date + dates.numb + 1, 'YYYYMMDD')) AS report_number,
       to_date(to_char(trunc(terms.timeframe_start_date + dates.numb), 'MM/DD/YYYY') || ' 23:59:00', 'MM/DD/YYYY HH24:MI:SS') AS report_timestamp,
       to_date(to_char(trunc(terms.timeframe_start_date + dates.numb), 'MM/DD/YYYY') || ' 23:58:59', 'MM/DD/YYYY HH24:MI:SS') AS expiration_date
  FROM (SELECT t.fa_proc_year AS acad_year,
               to_date('07/01/20' || substr(t.fa_proc_year, 1, 2), 'MM/DD/YYYY') AS timeframe_start_date,
               to_date('06/30/20' || substr(t.fa_proc_year, 3, 2), 'MM/DD/YYYY') AS timeframe_end_date,
               MIN(t.start_date) AS acad_start_date,
               MAX((SELECT MAX(t2.end_date)
                     FROM zbtm.terms_by_group_v t2
                    WHERE t2.fa_proc_year = to_char(t.fa_proc_year)
                      AND t2.group_code IN ('STD')
                      AND t2.semester NOT IN ('WIN'))) AS acad_end_date,
               MIN((SELECT MIN(t2.term_code)
                     FROM zbtm.terms_by_group_v t2
                    WHERE t2.fa_proc_year = to_char(t.fa_proc_year)
                      AND t2.group_code IN ('STD')
                      AND t2.semester NOT IN ('WIN'))) AS timeframe_start_term,
               MAX((SELECT MAX(t2.term_code)
                     FROM zbtm.terms_by_group_v t2
                    WHERE t2.fa_proc_year = to_char(t.fa_proc_year)
                      AND t2.group_code IN ('STD')
                      AND t2.semester NOT IN ('WIN'))) AS timeframe_end_term
          FROM zbtm.terms_by_group_v t
         WHERE t.term_code NOT IN ('000000')
           AND t.semester NOT IN ('WIN')
           AND t.group_code IN ('STD')
           AND t.start_date >= DATE '2008-08-15'
           AND to_date('07/01/20' || substr(t.fa_proc_year, 1, 2), 'MM/DD/YYYY') < SYSDATE
           AND (v_acad_year IS NULL OR t.fa_proc_year = v_acad_year)
         GROUP BY t.fa_proc_year) terms
  JOIN (SELECT LEVEL - 1 AS numb FROM dual CONNECT BY LEVEL <= 366) dates
    ON terms.timeframe_start_date + dates.numb >= to_date('07/01/20' || substr(terms.acad_year, 1, 2), 'MM/DD/YYYY')
   AND terms.timeframe_start_date + dates.numb <= to_date('06/30/20' || substr(terms.acad_year, 3, 2), 'MM/DD/YYYY') + nvl(v_extend_end_date, 0)
   AND terms.timeframe_start_date + dates.numb < trunc(SYSDATE)
   AND terms.timeframe_start_date + dates.numb >= trunc(SYSDATE - nvl(v_days_back, 2555))
   AND to_char(trunc(terms.timeframe_start_date + dates.numb), 'MM/DD') <> '02/29'
    ]';
END;
/

CREATE OR REPLACE FUNCTION ads_etl.get_next_acad_year(v_aidy_code IN VARCHAR2, -- Aid year code, e.g., '1415'
v_camp_code IN VARCHAR2 -- Campus code: 'D' or 'R'
) RETURN VARCHAR2 IS
v_output VARCHAR2(6); -- Output variable for the next aid year code
CURSOR c1 IS
SELECT ret_aidy_code FROM(
-- Get next year for both campuses
SELECT 'D' AS
campus, t.fa_proc_year, lpad(to_char(t.fa_proc_year + 101), 4, '0') AS
ret_aidy_code FROM zbtm.terms_by_group_v t WHERE t.group_code = 'STD' AND t.semester = 'FAL' UNION ALL SELECT 'R' AS
campus, t.fa_proc_year, lpad(to_char(t.fa_proc_year + 101), 4, '0') AS
ret_aidy_code FROM zbtm.terms_by_group_v t WHERE t.group_code IN ('STD', 'MED') AND t.semester = 'FAL') tbl WHERE campus = v_camp_code AND fa_proc_year = v_aidy_code;
BEGIN
-- Initialize output
v_output := NULL;
-- Open and fetch from cursor
OPEN c1; FETCH c1 INTO v_output; IF c1%NOTFOUND OR v_output IS
NULL THEN v_output := '9999'; -- Default value if not found
END IF; CLOSE c1; RETURN v_output;
EXCEPTION
WHEN OTHERS THEN
-- Ensure cursor is closed in case of error
IF c1%ISOPEN THEN CLOSE c1;
END IF;
-- Raise application error with detailed message
raise_application_error(-20001, 'An error occurred in get_next_acad_year: ' || SQLCODE || ' - ' || SQLERRM);
END get_next_acad_year;
/

CREATE OR REPLACE FUNCTION ads_etl.get_next_term_code(v_term_code IN VARCHAR2, v_camp_code IN VARCHAR2) RETURN VARCHAR2 IS
v_output VARCHAR2(6); -- Variable to hold the return term code
v_notfound BOOLEAN := FALSE; -- Flag to check if cursor returned any row
-- Cursor to fetch the next retention term code based on input parameters
CURSOR c1 IS
SELECT ret_term_code FROM(
-- For campus 'D'
SELECT 'D' AS
campus, term_code, CASE WHEN semester = 'FAL' THEN term_code + 80 WHEN semester = 'SPR' THEN term_code + 10 WHEN semester = 'SUM' THEN term_code + 10
END AS
ret_term_code FROM zbtm.terms_by_group_v t WHERE t.group_code = 'STD' AND t.semester NOT IN ('WIN') UNION ALL
-- For campus 'R'
SELECT 'R' AS
campus, term_code, CASE WHEN semester = 'FAL' THEN term_code + 80 WHEN semester = 'SPR' THEN term_code + 20 -- skipping summer; did they return next fall?
WHEN semester = 'SUM' THEN term_code + 10
END AS
ret_term_code FROM zbtm.terms_by_group_v t WHERE t.group_code IN ('STD', 'MED') AND t.semester NOT IN ('WIN')) tbl WHERE campus = v_camp_code AND term_code = v_term_code;
BEGIN
-- Initialize v_output to a default value
v_output := '999999';
-- Use a cursor FOR loop for clarity and automatic open/fetch/close
FOR rec IN c1 LOOP v_output := rec.ret_term_code; v_notfound := TRUE; EXIT; -- Only need the first match
END LOOP;
-- If no row was found, v_output remains '999999'
RETURN v_output;
EXCEPTION
WHEN OTHERS THEN
-- Log the error and raise a meaningful application error
raise_application_error(-20001, 'An error was encountered in get_retention - ' || SQLCODE || ' -ERROR- ' || SQLERRM);
END;
/ --

-- =============================================================================
-- PURPOSE: Records ETL/job execution metadata and messages as an append-only log entry for auditing and monitoring.
--
-- TARGET(S): utl_d_lms.job_log
--
-- UNIQUE KEY / INDEX: N/A - Append-only log; this procedure performs unconditional inserts and does not enforce uniqueness.
--
-- BUSINESS LOGIC & CONDITIONS:
-- - Inserts a single log row per procedure invocation into utl_d_lms.job_log with direct mappings from input parameters and session context.
-- - job_location is populated from the current DB session user; if SESSION_USER is null, falls back to PROXY_USER via sys_context('USERENV', ...).
-- - job_name is normalized to lowercase and stored in a 50-character field (v_job_name VARCHAR2(50)).
-- - activity_date is captured as the database current timestamp (SYSDATE).
-- - message_type and message_text are stored as provided into 4000-character fields (v_message_type/v_message_text VARCHAR2(4000)).
-- - instance is recorded from p_instance (v_instance VARCHAR2(20)).
-- - PARTITION column records the numeric p_partition value.
-- - job_id is recorded into a 32-character field (v_job_id VARCHAR2(32)).
-- - secs and recs capture numeric elapsed seconds and record counts respectively.
-- - No conditional filtering, joins, aggregations, or iterative/batching logic: each call results in one unconditional insert row.
--
-- DEPENDENCIES: utl_d_lms.job_log table; Oracle built-in functions sys_context('USERENV', ...) and SYSDATE; calling session must have INSERT privileges on the target table.
--
-- CONSTRAINTS & RISKS:
-- - Input size limits: exceeding declared VARCHAR2 sizes (job_name 50, instance 20, user 30, job_id 32, message_type/message_text 4000) can cause ORA-12899 (value too large for column) or other insert failures.
-- - High-frequency or bulk invocations will grow the job_log table rapidly, increasing storage use and potentially impacting query/maintenance performance.
-- - The procedure relies on USERENV session context values; unexpected or missing SESSION_USER/PROXY_USER values can change the recorded job_location.
-- - If the target table has additional constraints, triggers, or partitioning rules not represented here, inserts may fail or be subject to additional business rules.
-- =============================================================================
CREATE OR REPLACE EDITIONABLE PROCEDURE ads_etl.insert_job_log(p_job_name     IN VARCHAR2,
                                                               p_message_type IN VARCHAR2,
                                                               p_message_text IN VARCHAR2,
                                                               p_instance     IN VARCHAR2,
                                                               p_partition    IN NUMBER,
                                                               p_job_id       IN VARCHAR2,
                                                               p_secs         IN NUMBER,
                                                               p_recs         IN NUMBER) IS
v_job_name     VARCHAR2(50) := lower(p_job_name);
v_message_type VARCHAR2(4000) := p_message_type;
v_message_text VARCHAR2(4000) := p_message_text;
v_instance     VARCHAR2(20) := p_instance;
v_user         VARCHAR2(30) := nvl(sys_context('USERENV', 'SESSION_USER'), sys_context('USERENV', 'PROXY_USER'));
v_etl_date     DATE := SYSDATE;
v_partition    NUMBER := p_partition;
v_job_id       VARCHAR2(32) := p_job_id;
v_secs         NUMBER := p_secs;
v_recs         NUMBER := p_recs;
--
BEGIN
INSERT INTO utl_d_lms.job_log
(job_location,
 job_name,
 activity_date,
 message_type,
 message_text,
 instance,
 PARTITION,
 job_id,
 secs,
 recs)
VALUES
(v_user,
 v_job_name,
 v_etl_date,
 v_message_type,
 v_message_text,
 v_instance,
 v_partition,
 v_job_id,
 v_secs,
 v_recs);
COMMIT;
EXCEPTION
WHEN OTHERS THEN
RAISE;
dbms_output.put_line(SQLERRM);
ROLLBACK;
END;
/ --

-- =============================================================================
-- PURPOSE: Rebuilds unusable or invalid indexes in the ads_etl schema (optionally filtered by table name) using an online, parallel rebuild strategy to restore index usability and performance.
--
-- TARGET(S): ads_etl - indexes (USER_INDEXES view)
--
-- UNIQUE KEY / INDEX: index_name (USER_INDEXES.index_name)
--
-- BUSINESS LOGIC & CONDITIONS:
-- - Selects indexes from USER_INDEXES where STATUS is either 'UNUSABLE' or 'INVALID'.
-- - If p_table_name is provided (non-NULL), restricts to indexes whose TABLE_NAME matches UPPER(p_table_name); if p_table_name IS NULL, selects all unusable/invalid indexes in the schema.
-- - Processes each matching index one-by-one in a PL/SQL loop.
-- - For each index, constructs and executes dynamic DDL to run: ALTER INDEX <index_name> REBUILD ONLINE PARALLEL 4.
-- - Uses ONLINE rebuild to minimize exclusive table locking where Oracle supports it (reduces blocking of concurrent DML).
-- - Uses a fixed PARALLEL degree of 4 to speed the rebuild operation.
-- - Immediately after rebuilding an index, executes ALTER INDEX <index_name> NOPARALLEL to clear the parallel attribute (forces NOPARALLEL regardless of prior setting).
-- - All DDL is derived from the dictionary-provided index_name values returned by USER_INDEXES.
-- - The procedure is defined with AUTHID DEFINER and therefore runs with the definer's privileges/scope (acts on the definer's schema indexes).
--
-- DEPENDENCIES: USER_INDEXES view, DBMS_OUTPUT (for informational messages), ALTER INDEX privileges on target indexes (procedure owner: ads_etl), Oracle functionality that supports ALTER INDEX ... REBUILD ONLINE and PARALLEL.
--
-- CONSTRAINTS & RISKS:
-- - Hard-coded PARALLEL 4 may consume significant CPU/IO and should be tuned for the environment; consider parameterizing parallel degree.
-- - The NOPARALLEL statement clears any previous parallel degree; the original parallel configuration is not restored by this procedure.
-- - Online rebuilds require additional temporary/index segment space and generate redo/undo; large or many index rebuilds can exhaust space or impact database performance.
-- - Certain index types or configurations (bitmap, some domain/function-based indexes, and some partitioned scenarios) have restrictions or version-dependent behavior for ONLINE rebuild; such indexes may fail or require special handling.
-- - If an ALTER INDEX statement fails, the procedure will abort mid-run (no exception handling or retry logic), leaving remaining indexes unprocessed.
-- - v_sql is declared VARCHAR2(2000); extremely long index names or unexpected concatenations could theoretically exceed this size (unlikely under normal Oracle object name lengths).
-- - The procedure only targets indexes visible in USER_INDEXES for the definer's schema; rebuilding indexes in other schemas requires DBA/ALL/DBA_INDEXES access and appropriate privileges.
-- - DBMS_OUTPUT messages are only visible if SERVEROUTPUT is enabled in the client session.
-- =============================================================================
CREATE OR REPLACE PROCEDURE ads_etl.rebuild_indexes(p_table_name IN VARCHAR2 DEFAULT NULL) AUTHID DEFINER AS
v_sql VARCHAR2(2000);
BEGIN
FOR r IN (SELECT index_name
            FROM user_indexes
           WHERE status IN ('UNUSABLE', 'INVALID')
             AND (table_name = upper(p_table_name) OR p_table_name IS NULL))
LOOP
-- Best Practice: Use ONLINE to prevent locking the table
-- Use PARALLEL 4 to speed up the rebuild
v_sql := 'ALTER INDEX ' || r.index_name || ' REBUILD ONLINE PARALLEL 4';
EXECUTE IMMEDIATE v_sql;
-- Reset to NOPARALLEL after rebuild
EXECUTE IMMEDIATE 'ALTER INDEX ' || r.index_name || ' NOPARALLEL';
dbms_output.put_line('Rebuilt Index: ' || r.index_name);
END LOOP;
END;
/ --

-- =============================================================================
-- PURPOSE: Refreshes Oracle table statistics selectively for tables in ETL-related schemas to ensure query planner accuracy without needlessly re-gathering stats on recently analyzed objects.
--
-- TARGET(S): Current schema table (dynamic, passed as parameter)
--
-- UNIQUE KEY / INDEX: owner + table_name (table identity used to select and invoke schema-specific gather routines)
--
-- BUSINESS LOGIC & CONDITIONS:
-- - Operates only on tables for which the ADS_ETL user has explicit TABLE privileges (checked via ALL_TAB_PRIVS).
-- - Limits candidate tables to owners: 'UTL_D_LMS', 'UTL_D_AA', 'UTL_D_AIM'.
-- - Excludes tables whose names match the regex '(_gtt|_tmp|_temp|_test)$' (case-insensitive), and excludes recycle bin names like '%BIN$%' and names containing '%#T%'.
-- - Requires a minimum approximate row count: COALESCE(tab.num_rows, 0) > 10000 (skips very small tables).
-- - Selects tables when any of these conditions are true:
--   - Oracle marks the table's existing statistics as stale (ast.stale_stats = 'YES').
--   - There is no statistics row yet for the table (ast.last_analyzed IS NULL).
--   - ALL_TABLES reports last_analyzed IS NULL (brand-new table as seen by ALL_TABLES).
--   - For very large tables (num_rows > 1,000,000): stats older than ~23 hours (tab.last_analyzed < SYSDATE - 23/24) are selected as a fallback if stale flag didn't trigger.
--   - For smaller tables (num_rows <= 1,000,000): stats older than 7 days (tab.last_analyzed < SYSDATE - 7) are selected as a weekly safety net.
-- - Orders candidate tables by descending num_rows so the largest tables are processed first.
-- - For each selected table, delegates the actual statistic gathering to a schema-specific package:
--   - UTL_D_LMS.gather_stats(table_name) when owner = 'UTL_D_LMS'
--   - UTL_D_AA.gather_stats(table_name) when owner = 'UTL_D_AA'
--   - UTL_D_AIM.gather_stats(table_name) when owner = 'UTL_D_AIM'
-- - Records job start, per-table info and completion info via ads_etl.insert_job_log, including a generated v_job_id based on a hash of proc/instance/partition/timestamp.
-- - Tracks and reports elapsed seconds and a running total of processed rows (v_total_count) reported back to the job log.
-- - Uses DBMS_OUTPUT to emit progress messages (primarily for interactive/operational visibility).
--
-- DEPENDENCIES:
-- - Dictionary views: SYS.ALL_TABLES, SYS.ALL_TAB_PRIVS, SYS.ALL_TAB_STATISTICS
-- - PL/SQL packages/procedures: UTL_D_LMS.gather_stats, UTL_D_AA.gather_stats, UTL_D_AIM.gather_stats
-- - Job logging utility: ADS_ETL.insert_job_log
-- - DBMS_OUTPUT for console messages
--
-- CONSTRAINTS & RISKS:
-- - Requires ADS_ETL to have explicit table privileges on candidate tables; missing privileges will exclude tables.
-- - Large-table processing can consume significant IO and CPU; the script avoids re-running on tables analyzed within ~23 hours (for very large tables) but will still potentially run long for many large tables in one batch.
-- - Running this too frequently wastes resources; intended to run as a "safety net" when auto-stats is disabled or in response to known large ETL changes.
-- - For very large systems, ordering by num_rows DESC may concentrate resource usage at start of run; consider windowing or parallelization if needed.
-- - Assumes schema-specific gather_stats procedures exist and behave idempotently and efficiently.
-- - If ADS_ETL lacks visibility into some objects due to grants or cross-schema issues, stats won't be gathered for those objects.
-- - SO... **this must be deployed for each schema that it runs on**
-- =============================================================================
CREATE OR REPLACE PROCEDURE gather_stats (p_table_name IN VARCHAR2) 
AUTHID DEFINER -- This ensures it runs with the OWNER'S permissions
AS
BEGIN
    DBMS_STATS.GATHER_TABLE_STATS(
    -- Using Oracle 19c Best Practice parameters:
    -- estimate_percent => DBMS_STATS.AUTO_SAMPLE_SIZE (Optimized speed/accuracy)
    -- granularity      => 'AUTO' (Handles partitioned vs non-partitioned automatically)
        ownname => SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA'), 
        tabname          => p_table_name,
        estimate_percent => DBMS_STATS.AUTO_SAMPLE_SIZE,
        method_opt       => 'FOR ALL COLUMNS SIZE AUTO',
        degree           => DBMS_STATS.AUTO_DEGREE, -- Let Oracle decide parallelism
        cascade          => TRUE,                  -- Gather stats on indexes too
        no_invalidate    => DBMS_STATS.AUTO_INVALIDATE -- Prevent global cursor storms
    );
END;
/

-- =============================================================================
-- PURPOSE: Safely truncates a specified table in the current schema by validating the table name and schema against Oracle's SQL identifier rules before executing the DDL, preventing SQL injection and ensuring data is removed with storage reclamation.
--
-- TARGET(S): Current schema table (dynamic, passed as parameter)
--
-- UNIQUE KEY / INDEX: schema + table_name (validated identifiers used to construct and execute the TRUNCATE statement)
--
-- BUSINESS LOGIC & CONDITIONS:
-- - Retrieves the current schema context from the Oracle session environment.
-- - Validates the input table name using DBMS_ASSERT.SIMPLE_SQL_NAME to ensure it is a legal, unquoted SQL identifier.
-- - Validates the current schema using DBMS_ASSERT.SCHEMA_NAME to ensure the schema name is legal and safe.
-- - Constructs a TRUNCATE TABLE DDL statement that includes the DROP STORAGE clause to reclaim allocated space.
-- - Executes the DDL statement dynamically against the validated schema and table combination.
-- - Logs initialization and completion messages to DBMS_OUTPUT for audit and debugging purposes.
--
-- DEPENDENCIES: DBMS_ASSERT package, DBMS_OUTPUT package, Oracle data dictionary context functions (SYS_CONTEXT)
--
-- CONSTRAINTS & RISKS:
-- - TRUNCATE is a DDL operation that immediately commits; any active transaction will be committed before truncation occurs.
-- - Truncation cannot be rolled back; all data in the table is permanently removed.
-- - Calling procedure must possess ALTER privilege on the target table; execution runs with the procedure owner's privileges (AUTHID DEFINER).
-- - Invalid table or schema names will raise a VALUE_ERROR exception and prevent execution.
-- - The procedure logs errors but re-raises exceptions, delegating failure handling to the calling ETL framework.
-- =============================================================================
CREATE OR REPLACE PROCEDURE truncate_table(p_table_name IN VARCHAR2) AUTHID DEFINER -- Runs with OWNER's privileges; mirrors gather_stats auth model
 AS
v_schema     VARCHAR2(128) := sys_context('USERENV', 'CURRENT_SCHEMA');
v_safe_table VARCHAR2(128);
v_ddl        VARCHAR2(512);
BEGIN
-- Security Requirement: Validate identifier before embedding in dynamic DDL.
-- DBMS_ASSERT.SIMPLE_SQL_NAME raises VALUE_ERROR if input is not a legal
-- unquoted SQL identifier, preventing injection via EXECUTE IMMEDIATE.
v_safe_table := dbms_assert.simple_sql_name(p_table_name);
v_ddl := 'TRUNCATE TABLE ' || dbms_assert.schema_name(v_schema) -- Also assert schema is valid
         || '.' || v_safe_table || ' DROP STORAGE';
dbms_output.put_line('[truncate_table] Initiating: ' || v_schema || '.' || v_safe_table);
EXECUTE IMMEDIATE v_ddl;
dbms_output.put_line('[truncate_table] Completed:  ' || v_schema || '.' || v_safe_table);
EXCEPTION
-- Catch assertion failures from DBMS_ASSERT (invalid identifier or schema)
WHEN value_error THEN
dbms_output.put_line('[truncate_table] ASSERTION FAILED — invalid table or schema name: ' || p_table_name);
RAISE;
-- Catch object-not-found (ORA-00942: table or view does not exist)
WHEN OTHERS THEN
dbms_output.put_line('[truncate_table] ERROR on ' || v_schema || '.' || p_table_name || ' — ' || SQLCODE || ': ' || SQLERRM);
RAISE; -- Re-raise so the calling ETL framework captures the failure
END truncate_table;
/

-- =============================================================================
-- =============================================================================
CREATE OR REPLACE EDITIONABLE FUNCTION ADS_ETL.GET_SECTION_SIS_ID(p_term_code IN saturn.ssbsect.ssbsect_term_code%TYPE,
                                                                        p_crn       IN saturn.ssbsect.ssbsect_crn%TYPE,
                                                                        p_instance  IN utl_d_lms.lms_link.instance%TYPE) RETURN VARCHAR2 IS
PRAGMA AUTONOMOUS_TRANSACTION;
v_output    VARCHAR2(50);
v_term_code VARCHAR2(6) := p_term_code;
v_crn       VARCHAR2(5) := p_crn;
v_instance  VARCHAR2(50) := p_instance;
BEGIN
IF v_instance = 'ACCAN'
   AND v_term_code < '202338' THEN
SELECT section_sis_id
  INTO v_output
  FROM (SELECT ssbsect_subj_code || ssbsect_crse_numb || '_' || ssbsect_term_code || '_' || s1.ssrsprt_pars_code || '_' || s2.ssrsprt_pars_code || '_' || ssbsect_crn AS section_sis_id,
               rank() over(PARTITION BY ssbsect_term_code, ssbsect_crn ORDER BY s1.ssrsprt_activity_date DESC, s1.ssrsprt_pars_code, s2.ssrsprt_pars_code) AS ranking -- there should only be one teacher group per crn, but Banner data is messed up
          FROM saturn.ssbsect
          LEFT JOIN saturn.ssrsprt s1
            ON s1.ssrsprt_term_code = ssbsect.ssbsect_term_code
           AND s1.ssrsprt_crn = ssbsect.ssbsect_crn
           AND substr(s1.ssrsprt_pars_code, 1, 2) = 'AP'
          LEFT JOIN saturn.ssrsprt s2
            ON s2.ssrsprt_crn = ssbsect_crn
           AND s2.ssrsprt_term_code = ssbsect_term_code
           AND substr(s2.ssrsprt_pars_code, 1, 4) = 'ACTG'
         WHERE 1 = 1
           AND ssbsect.ssbsect_term_code = v_term_code
           AND ssbsect.ssbsect_crn = v_crn)
 WHERE ranking = 1;
ELSE
-- L2CAN or open learning >= '202338'
SELECT ssbsect_term_code || ssbsect_crn AS section_sis_id
  INTO v_output
  FROM saturn.ssbsect
 WHERE 1 = 1
   AND ssbsect.ssbsect_term_code = v_term_code
   AND ssbsect.ssbsect_crn = v_crn;
END IF;
COMMIT;
RETURN v_output;
EXCEPTION
WHEN OTHERS THEN
ROLLBACK;
RAISE;
dbms_output.put_line(SQLERRM);
END;
/
-- =============================================================================
-- =============================================================================
CREATE OR REPLACE EDITIONABLE FUNCTION ADS_ETL.GET_COURSE_SIS_ID(p_term_code IN saturn.ssbsect.ssbsect_term_code%TYPE,
                                                                       p_crn       IN saturn.ssbsect.ssbsect_crn%TYPE,
                                                                       p_instance  IN utl_d_lms.lms_link.instance%TYPE) RETURN VARCHAR2 IS
PRAGMA AUTONOMOUS_TRANSACTION;
v_output    VARCHAR2(50);
v_term_code VARCHAR2(6) := p_term_code;
v_crn       VARCHAR2(5) := p_crn;
v_instance  VARCHAR2(50) := p_instance;
-- v_etl_date  DATE := SYSDATE;
BEGIN
-- only runs for ACCAN
IF v_instance <> 'ACCAN' THEN
v_output := NULL;
ELSE
SELECT course_sis_id
  INTO v_output
  FROM (SELECT ssbsect_subj_code || ssbsect_crse_numb || '_' || ssbsect_term_code || '_' || s1.ssrsprt_pars_code || '_' || s2.ssrsprt_pars_code AS course_sis_id,
               rank() over(PARTITION BY ssbsect_term_code, ssbsect_crn ORDER BY s1.ssrsprt_activity_date DESC, s1.ssrsprt_pars_code, s2.ssrsprt_pars_code) AS ranking -- there should only be one teacher group per crn, but Banner data is messed up
          FROM saturn.ssbsect
          JOIN saturn.ssrsprt s1
            ON s1.ssrsprt_term_code = ssbsect.ssbsect_term_code
           AND s1.ssrsprt_crn = ssbsect.ssbsect_crn
          JOIN saturn.ssrsprt s2
            ON s2.ssrsprt_crn = s1.ssrsprt_crn
           AND s2.ssrsprt_term_code = s1.ssrsprt_term_code
           AND substr(s2.ssrsprt_pars_code, 1, 4) = 'ACTG'
         WHERE substr(s1.ssrsprt_pars_code, 1, 2) = 'AP'
           AND ssbsect.ssbsect_term_code = v_term_code
           AND ssbsect.ssbsect_crn = v_crn)
 WHERE ranking = 1;
END IF;
COMMIT;
RETURN v_output;
EXCEPTION
WHEN OTHERS THEN
ROLLBACK;
RAISE;
dbms_output.put_line(SQLERRM);
END;
/
-- =============================================================================
-- =============================================================================
CREATE OR REPLACE EDITIONABLE FUNCTION ADS_ETL.FAR_LUOA_CLEAR(p_course_code              IN far_luoa_audit.course_code%TYPE,
                                                                    p_compliance_category_code IN far_luoa_audit.compliance_category_code%TYPE,
                                                                    p_unique_id                IN far_luoa_audit.unique_id%TYPE,
                                                                    p_delete_reason            IN far_luoa_audit.deleted_reason%TYPE) RETURN VARCHAR2 IS
PRAGMA AUTONOMOUS_TRANSACTION;
v_output VARCHAR2(200);
--DECLARE
v_compliance_category_code VARCHAR2(2) := upper(p_compliance_category_code);
v_course_code              VARCHAR2(255) := p_course_code;
v_category_desc            VARCHAR2(100);
v_unique_id                VARCHAR2(100) := p_unique_id;
v_delete_reason            VARCHAR2(3950) := p_delete_reason;
v_user                     VARCHAR2(50) := nvl(sys_context('USERENV', 'PROXY_USER'), sys_context('USERENV', 'SESSION_USER'));
v_count                    NUMBER;
v_etl_date                 DATE := SYSDATE;
BEGIN
-- get the compliance_category_code
-- throw error if there is a new code that has not been coded before
SELECT flcc.category_desc
  INTO v_category_desc
  FROM utl_d_lms.far_luoa_cat_code flcc
 WHERE flcc.category_code = v_compliance_category_code
   AND flcc.category_code IN ('FN', 'FG', 'GC', 'MQ', 'MM', 'WA');
IF length(v_category_desc) > 0 THEN
v_output := 'Category code: ' || v_compliance_category_code || ' (' || v_category_desc || ')';
ELSE
v_output := 'Searching for compliance_category_code: ' || v_compliance_category_code || ' (NOT FOUND). Valid codes found in utl_d_lms.far_luoa_cat_code';
END IF;
-- Run updates on main table (if exists)
UPDATE utl_d_lms.far_luoa_audit fla
   SET (fla.status, fla.flag_count, fla.deleted_ind, fla.deleted_reason) =
       (SELECT 'EXPIRED',
               0,
               'Y',
               v_delete_reason
          FROM dual)
 WHERE EXISTS (SELECT 'X'
          FROM utl_d_lms.far_luoa_audit flax
         WHERE 1 = 1
           AND flax.unique_id = p_unique_id -- no formatting needed
           AND flax.unique_id = fla.unique_id);
v_count := SQL%ROWCOUNT;
COMMIT;
-- Run updates on log table
UPDATE utl_d_lms.far_luoa_audit_log fla
   SET (fla.status, fla.flag_count, fla.deleted_ind, fla.deleted_reason) =
       (SELECT 'EXPIRED',
               0,
               'Y',
               v_delete_reason
          FROM dual)
 WHERE EXISTS (SELECT 'X'
          FROM utl_d_lms.far_luoa_audit_log flax
         WHERE 1 = 1
           AND flax.unique_id = p_unique_id -- no formatting needed
           AND flax.unique_id = fla.unique_id);
v_count := SQL%ROWCOUNT;
COMMIT;
v_output := 'Cleared ' || v_count || ' ' || v_category_desc || ' ' || 'flag(s) in the FAR for ' || v_course_code || ' at ' || to_char(v_etl_date, 'MM/DD/YYYY hh24:mi:ss') || ';';
COMMIT;
RETURN v_output;
EXCEPTION
WHEN OTHERS THEN
ROLLBACK;
RAISE;
dbms_output.put_line(SQLERRM);
END;
/

-- =============================================================================
-- =============================================================================
CREATE OR REPLACE EDITIONABLE FUNCTION ADS_ETL.FAR_LUO_CLEAR (p_course_code              IN far_luo_audit.course_code%TYPE,
                                              p_compliance_category_code IN far_luo_audit.compliance_category_code%TYPE,
                                              p_unique_id                IN far_luo_audit.unique_id%TYPE,
                                              p_delete_reason            IN far_luo_audit.deleted_reason%TYPE) RETURN VARCHAR2 IS
PRAGMA AUTONOMOUS_TRANSACTION;
v_output VARCHAR2(200);
--DECLARE
v_compliance_category_code VARCHAR2(2) := upper(p_compliance_category_code);
v_course_code              VARCHAR2(255) := p_course_code;
v_category_desc            VARCHAR2(100);
v_unique_id                VARCHAR2(100) := p_unique_id;
v_delete_reason            VARCHAR2(3950) := p_delete_reason;
v_user                     VARCHAR2(50) := nvl(sys_context('USERENV', 'PROXY_USER'), sys_context('USERENV', 'SESSION_USER'));
v_count                    NUMBER;
v_etl_date                 DATE := SYSDATE;
BEGIN
-- get the compliance_category_code
-- throw error if there is a new code that has not been coded before
SELECT flcc.category_desc
  INTO v_category_desc
  FROM utl_d_lms.far_luo_cat_code flcc
 WHERE flcc.category_code = v_compliance_category_code
   AND flcc.category_code IN ('AN', 'FC', 'FG', 'FN', 'GC', 'LA', 'PC', 'VR');
IF length(v_category_desc) > 0 THEN
v_output := 'Category code: ' || v_compliance_category_code || ' (' || v_category_desc || ')';
ELSE
v_output := 'Searching for compliance_category_code: ' || v_compliance_category_code || ' (NOT FOUND). Valid codes found in utl_d_lms.far_luo_cat_code';
END IF;
-- Run updates on main table (if exists)
UPDATE utl_d_lms.far_luo_audit fla
   SET (fla.status, fla.flag_count, fla.deleted_ind, fla.deleted_reason) =
       (SELECT 'EXPIRED',
               0,
               'Y',
               v_delete_reason
          FROM dual)
 WHERE EXISTS (SELECT 'X'
          FROM utl_d_lms.far_luo_audit flax
         WHERE 1 = 1
           AND flax.unique_id = p_unique_id -- no formatting needed
           AND flax.unique_id = fla.unique_id);
v_count := SQL%ROWCOUNT;
COMMIT;
-- Run updates on log table
UPDATE utl_d_lms.far_luo_audit_log fla
   SET (fla.status, fla.flag_count, fla.deleted_ind, fla.deleted_reason) =
       (SELECT 'EXPIRED',
               0,
               'Y',
               v_delete_reason
          FROM dual)
 WHERE EXISTS (SELECT 'X'
          FROM utl_d_lms.far_luo_audit_log flax
         WHERE 1 = 1
           AND flax.unique_id = p_unique_id -- no formatting needed
           AND flax.unique_id = fla.unique_id);
v_count := SQL%ROWCOUNT;
COMMIT;
v_output := 'Cleared ' || v_count || ' ' || v_category_desc || ' ' || 'flag(s) in the FAR for ' || v_course_code || ' at ' || to_char(v_etl_date, 'MM/DD/YYYY hh24:mi:ss') || ';';
COMMIT;
RETURN v_output;
EXCEPTION WHEN OTHERS THEN ROLLBACK;
RAISE;
dbms_output.put_line(SQLERRM);
END;
/

-- =============================================================================
-- PURPOSE: Toggles and optionally enforces Oracle session-level parallel execution settings (DML, QUERY, DDL) with a governance cap on parallel degree.
--
-- TARGET(S): Oracle Session - ALTER SESSION parallel settings (DML, QUERY, DDL)
--
-- UNIQUE KEY / INDEX: N/A - Session-level operation
--
-- BUSINESS LOGIC & CONDITIONS:
-- - Accepts p_enabled (default 'Y'); treated case-insensitively. Values 'Y', 'YES', 'ON', or 'ENABLE' enable parallelism; any other value disables it.
-- - When enabling, issues ALTER SESSION ENABLE PARALLEL DML, ENABLE PARALLEL QUERY, and ENABLE PARALLEL DDL to allow parallel operations in the current session.
-- - If p_degree is provided and strictly greater than 1, compute applied_degree = LEAST(p_degree, c_max_degree) where c_max_degree = 8; then force that degree via ALTER SESSION FORCE PARALLEL DML/QUERY/DDL PARALLEL <applied_degree>, overriding object-level hints and settings.
-- - If p_degree is NULL or <= 1, enable parallel operation but do not force a specific degree (Oracle's default degree remains in effect).
-- - When disabling, issues ALTER SESSION DISABLE PARALLEL DML, DISABLE PARALLEL QUERY, and DISABLE PARALLEL DDL to turn off parallelism for the current session.
-- - Session-scoped operation: changes apply only to the calling session and do not persist across sessions; intended to be invoked per-session before maintenance/ETL work.
-- - Governance: the static cap (c_max_degree = 8) prevents requested degrees above 8 from being applied to avoid excessive CPU consumption.
-- - Forced DDL handling is included so index rebuilds or compression operations can be executed at the forced parallel degree when applicable.
-- - Only values greater than 1 trigger forced degree behavior; a requested degree of 1 is treated as "no forced degree".
-- - Recommended usage pattern: call to enable/force at the start of a maintenance job; when run interactively, disable at the end to avoid unintended parallelism in shared SQL clients.
--
-- DEPENDENCIES: DBMS_OUTPUT (for optional informational messages), ALTER SESSION privilege for the executing user, Oracle database support for session-level PARALLEL (PARALLEL DML/QUERY/DDL).
--
-- CONSTRAINTS & RISKS:
-- - Forcing parallelism consumes CPU and parallel server resources; even with an 8-thread cap, many concurrent forced sessions can cause resource contention and CPU starvation.
-- - Effectiveness and limits depend on instance configuration (PARALLEL_MAX_SERVERS, CPU count, and related initialization parameters); requested degree may be further constrained by system settings.
-- - Requires appropriate privileges; lack of ALTER SESSION or parallel-related privileges will prevent the procedure from applying settings.
-- - FORCE PARALLEL overrides object-level parallel settings and hints and can degrade performance for small workloads or when misapplied.
-- - In interactive clients (e.g., SQL Developer), leaving parallel enabled may cause subsequent ad-hoc queries to run with parallelism unexpectedly; disable when finished.
-- - In RAC or multi-tenant environments, parallel settings may have broader impact across nodes and should be used with caution.
-- =============================================================================
CREATE OR REPLACE PROCEDURE ads_etl.set_parallel_session (
    p_enabled IN VARCHAR2 DEFAULT 'Y',
    p_degree  IN NUMBER   DEFAULT 4,
    p_mode    IN VARCHAR2 DEFAULT 'ALL' -- 'ALL' (DML+Query+DDL) or 'QUERY' (Query+DDL only)
) AS
    v_state          VARCHAR2(10) := UPPER(p_enabled);
    v_mode           VARCHAR2(10) := UPPER(p_mode);
    v_input_degree   NUMBER       := p_degree;
    v_applied_degree NUMBER;
    v_sql            VARCHAR2(200);
    
    -- Safety Governance: Hard cap to prevent over-consuming server resources
    c_max_degree CONSTANT NUMBER := 8;
BEGIN
    /* 
       1. Handle ENABLE logic 
    */
    IF v_state IN ('Y', 'YES', 'ON', 'ENABLE') THEN
        
        -- Enable Parallel Query & DDL (Safe, no commit restrictions)
        EXECUTE IMMEDIATE 'ALTER SESSION ENABLE PARALLEL QUERY';
        EXECUTE IMMEDIATE 'ALTER SESSION ENABLE PARALLEL DDL';

        -- Enable Parallel DML ONLY if mode is ALL. 
        -- If user passes 'QUERY', we skip DML to prevent ORA-12838 without commits.
        IF v_mode = 'ALL' THEN
            EXECUTE IMMEDIATE 'ALTER SESSION ENABLE PARALLEL DML';
        END IF;

        -- 2. Governance: Apply Degree Cap
        IF v_input_degree IS NOT NULL AND v_input_degree > 1 THEN
            -- LEAST picks the smaller of the two: Input or 8
            v_applied_degree := LEAST(v_input_degree, c_max_degree);
            
            -- FORCE ensures hints/table settings are overruled
            v_sql := 'ALTER SESSION FORCE PARALLEL QUERY PARALLEL ' || v_applied_degree;
            EXECUTE IMMEDIATE v_sql;
            
            v_sql := 'ALTER SESSION FORCE PARALLEL DDL PARALLEL ' || v_applied_degree;
            EXECUTE IMMEDIATE v_sql;

            IF v_mode = 'ALL' THEN
                v_sql := 'ALTER SESSION FORCE PARALLEL DML PARALLEL ' || v_applied_degree;
                EXECUTE IMMEDIATE v_sql;
            END IF;

            DBMS_OUTPUT.PUT_LINE('Parallel Session: ENABLED (Mode: ' || v_mode || ', Forced Degree: ' || v_applied_degree || ')');
        ELSE
            DBMS_OUTPUT.PUT_LINE('Parallel Session: ENABLED (Mode: ' || v_mode || ', Default Oracle Degree)');
        END IF;

    /* 
       3. Handle DISABLE logic 
    */
    ELSE
        -- Note: If you have uncommitted DML, disabling PDML will throw ORA-12841.
        -- Always COMMIT in your ETL before calling set_parallel_session('N').
        EXECUTE IMMEDIATE 'ALTER SESSION DISABLE PARALLEL DML';
        EXECUTE IMMEDIATE 'ALTER SESSION DISABLE PARALLEL QUERY';
        EXECUTE IMMEDIATE 'ALTER SESSION DISABLE PARALLEL DDL';
        DBMS_OUTPUT.PUT_LINE('Parallel Session: DISABLED');
    END IF;

EXCEPTION
    WHEN OTHERS THEN
        -- Best practice: Log it (if you have an autonomous logging framework), 
        -- but you MUST RAISE so the ETL framework knows the session state failed.
        DBMS_OUTPUT.PUT_LINE('CRITICAL ERROR setting parallel session: ' || SQLERRM);
        RAISE; 
END set_parallel_session;
/
-- =============================================================================
-- Safe to run as: proxy user authenticated as ADS_ETL (no DBA required)
-- Requirement:    ALTER USER ADS_ETL GRANT CONNECT THROUGH <proxy_account>;
-- =============================================================================
DECLARE
v_owner CONSTANT VARCHAR2(30) := 'ADS_ETL';
TYPE t_vlist IS TABLE OF VARCHAR2(128);
v_plain t_vlist := t_vlist('ZARGOS_Q_ROLE', 'ZTABLEAU_SVC', 'ZETL_JAMS_SVC', 'R_STATS_SVC', 'WGRIFFITH2', 'KCULPEPPER5', 'WRUMINN');
v_wgo t_vlist := t_vlist('UTL_D_AA', 'UTL_D_AIM', 'UTL_D_LMS');
TYPE t_err_rec IS RECORD(
obj_owner VARCHAR2(128),
obj_name  VARCHAR2(128),
grantee   VARCHAR2(128),
wgo_flag  VARCHAR2(3),
err_msg   VARCHAR2(4000));
TYPE t_err_list IS TABLE OF t_err_rec INDEX BY PLS_INTEGER;
v_errors    t_err_list;
v_err_count PLS_INTEGER := 0;
CURSOR c_objects IS
SELECT owner,
       object_name,
       object_type
  FROM all_objects
 WHERE owner = v_owner
   AND object_type IN ('FUNCTION', 'PROCEDURE', 'PACKAGE', 'TYPE')
 ORDER BY object_type,
          object_name;
-- =========================================================================
-- Returns TRUE when the principal is a DATABASE ROLE.
-- Roles exist in SESSION_ROLES / DBA_ROLES; without DBA we use ALL_USERS
-- as a negative lookup: if the name is NOT in ALL_USERS it is a role.
-- ORA-01931: cannot grant WITH GRANT OPTION to a role — prevented here.
-- =========================================================================
FUNCTION is_role(p_principal IN VARCHAR2) RETURN BOOLEAN IS
v_count PLS_INTEGER;
BEGIN
SELECT COUNT(*) INTO v_count FROM all_users WHERE username = upper(p_principal);
RETURN v_count = 0; -- not a user → treat as role
END is_role;

FUNCTION is_wgo_principal(p_grantee IN VARCHAR2) RETURN BOOLEAN IS
BEGIN
FOR i IN 1 .. v_wgo.count
LOOP
IF v_wgo(i) = p_grantee THEN
RETURN TRUE;
END IF;
END LOOP;
RETURN FALSE;
END is_wgo_principal;

PROCEDURE grant_exec(p_obj_owner         IN VARCHAR2,
                     p_obj_name          IN VARCHAR2,
                     p_grantee           IN VARCHAR2,
                     p_with_grant_option IN BOOLEAN := FALSE) IS
v_sql     VARCHAR2(4000);
v_wgo_lbl VARCHAR2(3) := CASE
                         WHEN p_with_grant_option THEN
                          'YES'
                         ELSE
                          'NO'
                         END;
BEGIN
-- Guard: Oracle prohibits WGO on roles — downgrade silently to plain
-- This prevents ORA-01931 without dropping the grantee entirely.
v_sql := 'GRANT EXECUTE ON "' || p_obj_owner || '"."' || p_obj_name || '" TO "' || p_grantee || '"';
IF p_with_grant_option
   AND NOT is_role(p_grantee) THEN
v_sql := v_sql || ' WITH GRANT OPTION';
END IF;
EXECUTE IMMEDIATE v_sql;
EXCEPTION
WHEN OTHERS THEN
v_err_count := v_err_count + 1;
v_errors(v_err_count).obj_owner := p_obj_owner;
v_errors(v_err_count).obj_name := p_obj_name;
v_errors(v_err_count).grantee := p_grantee;
v_errors(v_err_count).wgo_flag := v_wgo_lbl;
v_errors(v_err_count).err_msg := SQLERRM;
END grant_exec;

BEGIN
FOR r IN c_objects
LOOP
FOR i IN 1 .. v_wgo.count
LOOP
grant_exec(p_obj_owner => r.owner, p_obj_name => r.object_name, p_grantee => v_wgo(i), p_with_grant_option => TRUE);
END LOOP;
FOR i IN 1 .. v_plain.count
LOOP
IF NOT is_wgo_principal(v_plain(i)) THEN
grant_exec(p_obj_owner => r.owner, p_obj_name => r.object_name, p_grantee => v_plain(i), p_with_grant_option => FALSE);
END IF;
END LOOP;
END LOOP;
IF v_err_count = 0 THEN
dbms_output.put_line('SUCCESS: EXECUTE grants applied to all eligible objects in ' || v_owner || '.');
ELSE
dbms_output.put_line('COMPLETED WITH ' || v_err_count || ' FAILURE(S):');
FOR i IN 1 .. v_err_count
LOOP
dbms_output.put_line('  [' || i || '] ' || v_errors(i).obj_owner || '.' || v_errors(i).obj_name || ' -> ' || v_errors(i).grantee || ' (WGO=' || v_errors(i).wgo_flag || ') : ' || v_errors(i).err_msg);
END LOOP;
raise_application_error(-20001, v_err_count || ' GRANT(s) failed in schema ' || v_owner || '. Review DBMS_OUTPUT for detail.');
END IF;
END;
/