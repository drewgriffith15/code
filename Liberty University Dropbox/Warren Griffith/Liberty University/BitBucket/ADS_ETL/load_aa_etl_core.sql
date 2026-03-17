create or replace package load_aa_etl_core is
procedure etl_aa_core_faculty_rosters(jobnumber number, processid varchar2, processname varchar2);
procedure etl_aa_core_soe_elms (jobnumber number, processid varchar2, processname varchar2);
procedure etl_aa_core_sowk_elms (jobnumber number, processid varchar2, processname varchar2);
procedure etl_aa_core_couc_elms (jobnumber number, processid varchar2, processname varchar2);
procedure etl_aa_core_psyd_elms (jobnumber number, processid varchar2, processname varchar2);
procedure etl_aa_core_lucom_elms (jobnumber number, processid varchar2, processname varchar2);
procedure etl_aa_alma(jobnumber number, processid varchar2, processname varchar2); -- ALMA - this is separate email send process, but similar enough to put here
END load_aa_etl_core;
/

CREATE OR REPLACE PACKAGE BODY load_aa_etl_core IS

procedure etl_aa_alma(jobnumber number, processid varchar2, processname varchar2) is
--
-- PURPOSE: Produces a type-2 history feed of active Liberty users and credentials for the Ex Libris Alma send list to support library access, identification, and provisioning.
--
-- TABLE: utl_d_aa.alma_sendlist
--
-- UNIQUE INDEX: UNIQUE_ID
--
-- CONDITIONS:
-- Loads people from SPRIDEN with stable IDs (SPRIDENT_CHANGE_IND is null) and an associated portal account (GOBTPAC by PIDM).
-- Builds a mobile/physical card profile from Envision: requires either a physical card (card_type <> 2, not lost, active, printed) or a mobile card (card_type = 2, not lost); ties to SPRIDEN by L-number ('L'||substr(custnum,15,9)) and keeps the highest (most recent) physical barcode.
-- Derives phone and watch mobile credentials separately and retains them only when distinct from each other and from the physical barcode.
-- Identifies alumni as the most recent graduates (from SHRDGMR) whose graduation date is on or before today and who have no current or future registration in any term that is current or in the future.
-- Identifies “expired” former employees as terminated employees who were never enrolled, are not currently active employees, and do not have a graduation record linked to their ID.
-- Flags active employees (faculty/staff) from ZGENERAL.ACTIVEEMPLOYEES while excluding those holding a Graduate Student Assistant assignment in any current/future term.
-- Selects a single best employee/org record per employee using a rank over organization_code and class type to resolve multiple org associations.
-- Derives student context from UTL_D_AIM.SZRENRL as the latest standard (non-winter) academic term on or before today and restricts to levels UG, GR, DR, JD, MD; adds indicators for Graduate Student Assistant (SIRASGN.ASTY_CODE = 'GSA') and Law Review coursework (LAW 881–886).
-- Pulls current academic standing context from ZFINCHECKIN.ZFRFCIS joined to SGBSTDN effective as of the check-in term (levels not in 'AC','00'); keeps the latest record per PIDM by term and create date.
-- Maps campus code from FINCHECK to 'RES' (R) or 'LUO' (D).
-- Computes academic class for undergraduates from SHRLGPA hours earned (FR <24, SO 24–47.999, JR 48–71.999, SR ≥72; defaults to FR when hours are null); for non-UG, the class equals academic level.
-- Sets gender from SPBPERS.SEX ('MALE'/'FEMALE'/‘NONE’) only when confidentiality is not flagged (SPBPERS_CONFID_IND = 'N').
-- Assigns user groups in priority order:
--   • LAWF / LAWST for Faculty/Staff linked to departments whose title contains 'LAW'; LUCOMF / LUCOMS for Faculty/Staff in departments with 'LUCOM'.
--   • FCLTY for remaining Faculty; STAF for remaining Staff (non-GSA).
--   • LAWREV for JD students with Law Review indicator.
--   • ALUM for qualified alumni.
--   • LAWS for remaining JD; LUCOM for MD.
--   • GRD for GR/DR residential or any GSA; GRDO for GR/DR online (non-GSA).
--   • UGD for UG residential; UGDO for UG online.
--   • EXP when a person is a former employee or has mobile/physical card info but does not fit any group.
--   • EXCLUDE for all others; excluded records are not output.
-- Keeps only the first-ranked employee/org association record per person; requires USER_GROUP <> 'EXCLUDE'.
-- Uses the person’s L-number numeric portion (trim leading 'L' and zeros) as PRIMARYIDENTIFIER and UNIQUE_ID; suppresses BARCODE only when equal to PRIMARYIDENTIFIER.
-- Populates USERPRINCIPALNAME/USERNAME from GOBTPAC.EXTERNAL_USER and EMAIL_ADDRESS as that value suffixed with '@liberty.edu'.
-- Sets a standardized mailing address (1971 University Blvd, Lynchburg, VA 24501) and includes best phone from ZEXEC.ZSAVTELE (rank = 1) with extension.
-- Emits NULL for middle name, title, expiration date, school, employee status, and enrollment status (these fields are intentionally unused).
-- Produces one current active row per UNIQUE_ID, enforcing type-2 history using FROM_DATE/TO_DATE (open-ended = 12/31/2099) and ACTIVITY_DATE.
-- Change detection compares all significant attributes (name, fullname, title, expirationdate, gender, usergroup, photo, address, phone, UPN, barcode, email, username, school, campuscode, employeestatus, levl, enrl_status, class, department, mobile credentials) between the new record and the currently active target row.
-- If no active target row exists for UNIQUE_ID, inserts a new active record (FROM_DATE = run timestamp; TO_DATE = 12/31/2099).
-- If any attribute differs, end-dates the current active row (TO_DATE = one second before run timestamp) and inserts a new active row with updated values.
-- If no attributes differ, refreshes only ACTIVITY_DATE on the active row.
-- After processing, end-dates any remaining active rows not seen in the current run (TO_DATE set to one second before run timestamp), ensuring the target reflects the current population.
-- Processes data in bulk via a cursor with up to 1,000,000 rows per batch.
--
-- URL: N/A
--
--DECLARE
v_etl_date    DATE := SYSDATE;
v_end_date    DATE := SYSDATE - 1 / (24 * 60 * 60); -- ONE SEC BEHIND
v_msg         VARCHAR2(255);
v_row_max     NUMBER := 1000000; -- max number of rows to be processed at one time
v_job_id      VARCHAR2(32);
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_cpu         NUMBER := 4; -- number of CPUs used for parallelization - do not exceed 20 CPUs [v_mod x v_cpu] if running simultaneously
v_proc        VARCHAR2(100) := 'etl_aa_alma';
v_instance    VARCHAR2(100) := 'ALL'; -- placeholder
v_partition    NUMBER := 0; -- placeholder
-- cursors
CURSOR curs IS
SELECT new_rec.*,
       CASE
       WHEN existing_rec.unique_id IS NULL THEN
        'INSERT' -- new record to source, add it
       WHEN -- using nvls to find any changes for student record
        (coalesce(existing_rec.firstname, 'XXXXXX') != coalesce(new_rec.firstname, 'XXXXXX') OR coalesce(existing_rec.middlename, 'XXXXXX') != coalesce(new_rec.middlename, 'XXXXXX') OR
        coalesce(existing_rec.lastname, 'XXXXXX') != coalesce(new_rec.lastname, 'XXXXXX') OR coalesce(existing_rec.fullname, 'XXXXXX') != coalesce(new_rec.fullname, 'XXXXXX') OR
        coalesce(existing_rec.title, 'XXXXXX') != coalesce(new_rec.title, 'XXXXXX') OR coalesce(existing_rec.expirationdate, SYSDATE) != coalesce(new_rec.expirationdate, SYSDATE) OR
        coalesce(existing_rec.gender, 'XXXXXX') != coalesce(new_rec.gender, 'XXXXXX') OR coalesce(existing_rec.usergroup, 'XXXXXX') != coalesce(new_rec.usergroup, 'XXXXXX') OR
        coalesce(existing_rec.photo, 'XXXXXX') != coalesce(new_rec.photo, 'XXXXXX') OR coalesce(existing_rec.addressline1, 'XXXXXX') != coalesce(new_rec.addressline1, 'XXXXXX') OR
        coalesce(existing_rec.addresscity, 'XXXXXX') != coalesce(new_rec.addresscity, 'XXXXXX') OR coalesce(existing_rec.addressstate, 'XXXXXX') != coalesce(new_rec.addressstate, 'XXXXXX') OR
        coalesce(existing_rec.addresszip, 999999) != coalesce(new_rec.addresszip, 999999) OR coalesce(existing_rec.phone, 'XXXXXX') != coalesce(new_rec.phone, 'XXXXXX') OR
        coalesce(existing_rec.userprinciplename, 'XXXXXX') != coalesce(new_rec.userprinciplename, 'XXXXXX') OR coalesce(existing_rec.barcode, 'XXXXXX') != coalesce(new_rec.barcode, 'XXXXXX') OR
        coalesce(existing_rec.email_address, 'XXXXXX') != coalesce(new_rec.email_address, 'XXXXXX') OR coalesce(existing_rec.username, 'XXXXXX') != coalesce(new_rec.username, 'XXXXXX') OR
        coalesce(existing_rec.school, 'XXXXXX') != coalesce(new_rec.school, 'XXXXXX') OR coalesce(existing_rec.campuscode, 'XXXXXX') != coalesce(new_rec.campuscode, 'XXXXXX') OR
        coalesce(existing_rec.employeestatus, 'XXXXXX') != coalesce(new_rec.employeestatus, 'XXXXXX') OR coalesce(existing_rec.levl, 'XXXXXX') != coalesce(new_rec.levl, 'XXXXXX') OR
        coalesce(existing_rec.enrl_status, 'XXXXXX') != coalesce(new_rec.enrl_status, 'XXXXXX') OR coalesce(existing_rec.class, 'XXXXXX') != coalesce(new_rec.class, 'XXXXXX') OR
        coalesce(existing_rec.department, 'XXXXXX') != coalesce(new_rec.department, 'XXXXXX') OR coalesce(existing_rec.mobile_credential_one, 'XXXXXX') != coalesce(new_rec.mobile_credential_one, 'XXXXXX') OR
        coalesce(existing_rec.mobile_credential_two, 'XXXXXX') != coalesce(new_rec.mobile_credential_two, 'XXXXXX')) THEN
        'EXPIRE' -- record no longer exists, expire it
       ELSE
        'UPDATE' -- existing record, no change
       END AS control_state, -- we are NOT deleting - EVER!
       COUNT(*) over() total_rows
  FROM (WITH terms AS -- bringing in current employee term so that all terms after it can be brought in (brings in last term, current term, all future terms)
        (SELECT stvterm.stvterm_code term
           FROM stvterm
          WHERE trunc(SYSDATE) BETWEEN trunc(stvterm.stvterm_start_date) AND trunc(stvterm.stvterm_end_date)
         UNION
         SELECT stvterm.stvterm_code -- accounting for future terms
           FROM stvterm
          WHERE trunc(SYSDATE) < trunc(stvterm.stvterm_start_date)), --
       mobc AS (SELECT /*+ materialize*/
                 luid, -- mobile credential info
                 MAX(fp_card) fp_card, -- had to add a max here on 9/4 to pull highest barcode (most recent) since we are no longer limiting barcode in the subquery
                 pidm,
                 firstname,
                 lastname,
                 middlename,
                 MAX(CASE
                     WHEN cred_type = 'phone' THEN
                      mobile_card
                     END) phone_cred,
                 MAX(CASE
                     WHEN cred_type = 'watch' THEN
                      mobile_card
                     END) watch_cred
                  FROM (SELECT 'L' || substr(cust.custnum, 15, 9) AS luid,
                               iden.spriden_first_name firstname,
                               iden.spriden_last_name lastname,
                               iden.spriden_mi middlename,
                               cust.defaultcardnum fp_card,
                               mc.cardnum mobile_card,
                               regexp_substr(mc.cardname, '[^:]+', 1, 2) cred_type,
                               mc.card_type card_type,
                               iden.spriden_pidm pidm
                          FROM envision.customer cust
                          JOIN spriden iden
                            ON iden.spriden_id = 'L' || substr(cust.custnum, 15, 9)
                           AND iden.spriden_change_ind IS NULL
                           AND iden.spriden_id LIKE 'L%'
                        --AND iden.spriden_first_name = cust.firstname -- removed these name joins 8/13 to not remove users due to name changes
                        --AND iden.spriden_last_name = cust.lastname
                        --Mobile Credential
                          LEFT JOIN envision.card mc
                            ON mc.cust_id = cust.cust_id
                           AND mc.card_type = 2 --mobile credential type
                              --  AND mc.card_status = 0 --active mobile credential status -- took this out 7/31, customer wants all mobile info to come in
                           AND mc.lost_flag = 'F' --not lost
                        --Physical Card
                          LEFT JOIN envision.card pc -- changed to left join 7/31, customer wants all phsyical or mobile cred info in
                            ON pc.cust_id = cust.cust_id
                           AND pc.card_type <> 2 --mobile credential type
                           AND pc.lost_flag = 'F' --not lost
                           AND pc.card_status = 0 --active PHYSICAL card status
                           AND pc.card_idm IS NOT NULL --printed card
                         WHERE (pc.cardnum IS NOT NULL OR mc.cardnum IS NOT NULL) -- has a physical or mobile card #
                        )
                 GROUP BY luid,
                          --fp_card,
                          pidm,
                          firstname,
                          lastname,
                          middlename), --
       alumni AS (SELECT /*+ materialize*/
                  DISTINCT al.pidm -- finding alumni
                    FROM (SELECT gmr.shrdgmr_pidm pidm,
                                 MAX(gmr.shrdgmr_grad_date) recent_grad_date -- max grad record
                            FROM shrdgmr gmr
                           WHERE 1 = 1
                                -- AND gmr.shrdgmr_degs_code = 'AW' -- took out per request from customer to avoid any lag between a student havinga degs code of AW and their graduation date
                             AND NOT EXISTS (SELECT 'X'
                                    FROM utl_d_aim.szrenrl b -- excluding students with a current or future reg
                                   WHERE b.pidm = gmr.shrdgmr_pidm
                                     AND b.term_code IN (SELECT term FROM terms))
                           GROUP BY gmr.shrdgmr_pidm) al
                   WHERE trunc(SYSDATE) >= trunc(recent_grad_date)), --
       stu AS (SELECT /*+ materialize*/
                ranker.pidm,
                ranker.term_code,
                ranker.levl_code,
                ranker.camp_code,
                ranker.gsa_ind,
                ranker.lr_ind,
                ranker.ranky
                 FROM (SELECT /*+ materialize*/
                        s.pidm,
                        s.term_code,
                        s.levl_code,
                        s.camp_code,
                        st.gsa_ind,
                        st.lr_ind,
                        rank() over(PARTITION BY s.pidm ORDER BY s.term_code DESC, rownum) ranky
                         FROM utl_d_aim.szrenrl s
                         LEFT JOIN (SELECT crse.pidm,
                                          crse.term_code,
                                          MAX(nvl2(gsa.sirasgn_pidm, 'Y', 'N')) gsa_ind,
                                          MAX(nvl2(c.pidm, 'Y', 'N')) lr_ind
                                     FROM utl_d_aim.szrcrse crse
                                     LEFT JOIN sirasgn gsa
                                       ON gsa.sirasgn_pidm = crse.pidm
                                      AND gsa.sirasgn_term_code = crse.term_code -- for find gsa students (need to be included in graduate pops)
                                      AND gsa.sirasgn_crn = crse.crn
                                      AND gsa.sirasgn_asty_code = 'GSA'
                                     LEFT JOIN utl_d_aim.szrcrse c
                                       ON c.pidm = crse.pidm
                                      AND c.term_code = crse.term_code
                                      AND c.crn = crse.crn
                                      AND c.subj = 'LAW'
                                      AND c.numb BETWEEN '881' AND '886'
                                    WHERE crse.term_code >= (SELECT MAX(term_code) AS current_term -- using this to pull in last std enroll term
                                                               FROM zbtm.terms_by_group_v
                                                              WHERE group_code = 'STD'
                                                                AND semester != 'WIN'
                                                                AND end_date <= SYSDATE)
                                    GROUP BY crse.pidm,
                                             crse.term_code) st
                           ON st.pidm = s.pidm
                          AND st.term_code = s.term_code
                        WHERE 1 = 1
                          AND s.levl_code IN ('UG', 'GR', 'DR', 'JD', 'MD')
                          AND s.term_code >= (SELECT MAX(term_code) AS current_term -- using this to pull in last std enroll term
                                                FROM zbtm.terms_by_group_v
                                               WHERE group_code = 'STD'
                                                 AND semester != 'WIN'
                                                 AND end_date <= SYSDATE)) ranker
                WHERE ranky = 1), empdata AS (SELECT /*+ materialize*/
                                              DISTINCT empid,
                                                       empstatus,
                                                       empstartdate,
                                                       empclassid,
                                                       empclasstype,
                                                       CASE
                                                       WHEN empterminationdate < empstartdate THEN
                                                        NULL
                                                       ELSE
                                                        empterminationdate
                                                       END emptermdate,
                                                       adpdept.descr department
                                                FROM (SELECT /*+ materialize*/
                                                       activeemployees.*,
                                                       rank() over(PARTITION BY empid ORDER BY empsnapshot DESC,CASE
                                                       WHEN (empclassid = 'J' OR empclassid = 'L') THEN
                                                        'Z'
                                                       ELSE
                                                        empclassid
                                                       END, empstatus, empstartdate DESC, empdeptindex DESC, rownum) ranker
                                                        FROM zgeneral.activeemployees) sub1
                                                JOIN zgeneral.adpdept
                                                  ON adpdept.deptid = sub1.empdeptid
                                               WHERE ranker = 1), --
       expired AS (SELECT /*+ materialize*/
                   DISTINCT ees.empid -- finding ex employees who are not alumni
                     FROM zgeneral.terminatedemployees ees
                    WHERE 1 = 1
                      AND NOT EXISTS (SELECT 'X'
                             FROM utl_d_aim.szrenrl e -- excluding anyone who has enrolled in past
                            WHERE e.luid = ees.empid)
                      AND NOT EXISTS (SELECT 'X'
                             FROM zgeneral.activeemployees oye -- excluding current employees who are in terminated employees as well
                            WHERE oye.empid = ees.empid)
                      AND NOT EXISTS (SELECT 'X'
                             FROM shrdgmr exg -- excluding users with a grad record on file but no reg (small pop of 12 users)
                             JOIN spriden exi
                               ON exi.spriden_pidm = exg.shrdgmr_pidm
                              AND exi.spriden_change_ind IS NULL
                            WHERE exi.spriden_id = ees.empid)), --
       fac AS (SELECT /*+ materialize*/
               DISTINCT activeemployees.empid,
                        activeemployees.empdeptid,
                        activeemployees.empclasstype
                 FROM zgeneral.activeemployees
                 LEFT JOIN sirasgn ngsa
                   ON ngsa.sirasgn_pidm = activeemployees.emppidm
                  AND ngsa.sirasgn_term_code IN (SELECT term FROM terms)
                  AND ngsa.sirasgn_asty_code = 'GSA'
                WHERE 1 = 1
                  AND ngsa.sirasgn_pidm IS NULL), --
       fincheck AS (SELECT /*+ materialize*/
                     zfrfcis_pidm,
                     zfrfcis_term,
                     zfrfcis_activity_date,
                     zfrfcis_create_date,
                     zfrfcis_withdrawn wd,
                     rank() over(PARTITION BY zfrfcis_pidm ORDER BY zfrfcis_term DESC, zfrfcis_create_date DESC, rownum) fci_rank,
                     sgbstdn_camp_code campus,
                     sgbstdn_levl_code levl,
                     sgbstdn_activity_date,
                     sgbstdn_exp_grad_date graduation_date
                      FROM zfincheckin.zfrfcis
                      JOIN saturn.sgbstdn a
                        ON a.sgbstdn_pidm = zfrfcis_pidm
                       AND a.sgbstdn_levl_code NOT IN ('AC', '00')
                       AND a.sgbstdn_term_code_eff = (SELECT MAX(z.sgbstdn_term_code_eff)
                                                        FROM saturn.sgbstdn z
                                                       WHERE a.sgbstdn_pidm = z.sgbstdn_pidm
                                                         AND z.sgbstdn_term_code_eff <= zfrfcis_term)
                     WHERE zfrfcis_term >= (SELECT MIN(stvterm_code) FROM stvterm WHERE stvterm_end_date >= trunc(SYSDATE))), --
       base AS (SELECT /*+ materialize*/
                 iden.spriden_pidm pidm,
                 iden.spriden_first_name firstname,
                 iden.spriden_last_name lastname,
                 iden.spriden_first_name || ' ' || iden.spriden_last_name fullname,
                 iden.spriden_id,
                 TRIM(leading 0 FROM(TRIM(leading 'L' FROM iden.spriden_id))) primaryidentifier,
                 CASE
                 WHEN spbpers.spbpers_sex = 'M' THEN
                  'MALE'
                 WHEN spbpers.spbpers_sex = 'F' THEN
                  'FEMALE'
                 ELSE
                  'NONE'
                 END gender,
                 zsavtele.phone_combo || zsavtele.phone_ext phone,
                 CASE
                 WHEN fincheck.campus = 'D' THEN
                  'LUO'
                 WHEN fincheck.campus = 'R' THEN
                  'RES'
                 END campuscode,
                 fincheck.levl,
                 CASE
                 WHEN fincheck.levl = 'UG' THEN
                  CASE
                  WHEN shrlgpa.shrlgpa_hours_earned >= 72 THEN
                   'SR'
                  WHEN shrlgpa.shrlgpa_hours_earned BETWEEN 48 AND 71.999 THEN
                   'JR'
                  WHEN shrlgpa.shrlgpa_hours_earned BETWEEN 24 AND 47.999 THEN
                   'SO'
                  WHEN shrlgpa.shrlgpa_hours_earned < 24 THEN
                   'FR'
                  WHEN shrlgpa.shrlgpa_hours_earned IS NULL THEN
                   'FR'
                  END
                 ELSE
                  fincheck.levl
                 END CLASS,
                 empdata.department,
                 fac.empclasstype,
                 dept.organization_code, --updated for Workday changeover
                 dept.organization_title, --updated for Workday changeover
                 upper(dept.organization_title), --updated for Workday changeover
                 CASE
                 WHEN fac.empid IS NOT NULL
                      AND fac.empclasstype = 'Faculty'
                      AND (dept.organization_code IS NOT NULL AND upper(dept.organization_title) LIKE '%LAW%') --updated for Workday changeover
                  THEN
                  'LAWF'
                 WHEN fac.empid IS NOT NULL
                      AND fac.empclasstype = 'Staff'
                      AND (dept.organization_code IS NOT NULL AND upper(dept.organization_title) LIKE '%LAW%') --updated for Workday changeover
                  THEN
                  'LAWST'
                 WHEN fac.empid IS NOT NULL
                      AND fac.empclasstype = 'Faculty'
                      AND (dept.organization_code IS NOT NULL AND upper(dept.organization_title) LIKE '%LUCOM%') --updated for Workday changeover
                  THEN
                  'LUCOMF'
                 WHEN fac.empid IS NOT NULL
                      AND fac.empclasstype = 'Staff'
                      AND (dept.organization_code IS NOT NULL AND upper(dept.organization_title) LIKE '%LUCOM%') --updated for Workday changeover
                  THEN
                  'LUCOMS'
                 WHEN fac.empid IS NOT NULL
                      AND fac.empclasstype = 'Faculty' THEN
                  'FCLTY'
                 WHEN stu.levl_code = 'JD'
                      AND lr_ind = 'Y' THEN
                  'LAWREV'
                 WHEN fac.empid IS NOT NULL
                      AND fac.empclasstype = 'Staff' THEN
                  'STAF'
                 WHEN alumni.pidm IS NOT NULL THEN
                  'ALUM'
                 WHEN stu.levl_code = 'JD' THEN
                  'LAWS'
                 WHEN stu.levl_code = 'MD' THEN
                  'LUCOM'
                 WHEN (stu.levl_code IN ('DR', 'GR') AND stu.camp_code = 'R' OR gsa_ind = 'Y') THEN
                  'GRD'
                 WHEN (stu.levl_code IN ('DR', 'GR') AND stu.camp_code = 'D' OR gsa_ind = 'Y') THEN
                  'GRDO'
                 WHEN stu.levl_code = 'UG'
                      AND stu.camp_code = 'R' THEN
                  'UGD'
                 WHEN stu.levl_code = 'UG'
                      AND stu.camp_code = 'D' THEN
                  'UGDO'
                 WHEN expired.empid IS NOT NULL
                      OR mobc.pidm IS NOT NULL THEN -- expirecd or students who dont fit in group but have mobc info
                  'EXP'
                 ELSE
                  'EXCLUDE' -- users who dont fit into any group and do not have mobc info, am excluding
                 END user_group,
                 gobtpac.gobtpac_external_user userprinciplename,
                 gobtpac.gobtpac_external_user || '@liberty.edu' AS email_address,
                 gobtpac.gobtpac_external_user username,
                 CASE
                 WHEN TRIM(leading '0' FROM mobc.fp_card) = TRIM(leading 0 FROM(TRIM(leading 'L' FROM iden.spriden_id))) THEN
                  NULL
                 ELSE
                  TRIM(leading '0' FROM mobc.fp_card)
                 END barcode, -- if barcode is the primary identifier dont show
                 CASE
                 WHEN TRIM(leading '0' FROM mobc.phone_cred) = TRIM(leading '0' FROM mobc.fp_card) THEN
                  NULL
                 ELSE
                  TRIM(leading '0' FROM mobc.phone_cred)
                 END mobile_credential_one, -- if mob one or two are the same as barcode null out
                 CASE
                 WHEN (TRIM(leading '0' FROM mobc.watch_cred) = TRIM(leading '0' FROM mobc.fp_card) OR TRIM(leading '0' FROM mobc.watch_cred) = TRIM(leading '0' FROM mobc.phone_cred)) THEN
                  NULL -- if it equals the mobile cred one or barcode make null
                 ELSE
                  TRIM(leading '0' FROM mobc.watch_cred)
                 END mobile_credential_two,
                 '1971 University Blvd' addressline1,
                 'Lynchburg' addresscity,
                 'VA' addressstate,
                 24501 addresszip,
                 rank() over(PARTITION BY fac.empid ORDER BY nvl(dept.organization_code, 'z'), nvl(fac.empclasstype, 'z') ASC) ranker --Updated for Workday changeover
                  FROM spriden iden
                  JOIN gobtpac
                    ON gobtpac.gobtpac_pidm = iden.spriden_pidm
                -- mobile credential info --
                  LEFT JOIN mobc
                    ON mobc.pidm = iden.spriden_pidm
                -- alumni --
                  LEFT JOIN alumni
                    ON alumni.pidm = iden.spriden_pidm
                -- expired (former employees who never enrolled) --
                  LEFT JOIN expired
                    ON expired.empid = iden.spriden_id
                -- fac / staff --
                  LEFT JOIN fac
                    ON fac.empid = iden.spriden_id
                  LEFT JOIN utl_d_fin.organization_vw dept
                    ON dept.organization_code = fac.empdeptid
                   AND (upper(dept.organization_title) LIKE '%LAW%' OR upper(dept.organization_title) LIKE '%LUCOM%') --Clarifies Law Staff / LUCOM Staff User Groups
                -- student groups --
                  LEFT JOIN stu
                    ON stu.pidm = iden.spriden_pidm
                -- additional columns --
                  LEFT JOIN spbpers
                    ON spbpers.spbpers_pidm = iden.spriden_pidm
                   AND spbpers.spbpers_confid_ind = 'N'
                  LEFT JOIN fincheck
                    ON fincheck.zfrfcis_pidm = iden.spriden_pidm
                   AND fincheck.fci_rank = 1
                  LEFT JOIN shrlgpa
                    ON shrlgpa_pidm = fincheck.zfrfcis_pidm
                   AND shrlgpa_levl_code = fincheck.levl
                   AND shrlgpa_gpa_type_ind = 'O'
                  LEFT JOIN zexec.zsavtele
                    ON zsavtele.pidm = iden.spriden_pidm
                   AND zsavtele.tele_rank = 1
                  LEFT JOIN empdata
                    ON empdata.empid = iden.spriden_id
                 WHERE 1 = 1
                   AND iden.spriden_change_ind IS NULL)
       SELECT DISTINCT base.firstname,
                       NULL                       middlename,
                       base.lastname,
                       base.fullname,
                       NULL                       title,
                       base.primaryidentifier     AS primaryidentifier,
                       NULL                       expirationdate,
                       base.gender,
                       base.user_group            usergroup,
                       NULL                       photo,
                       base.addressline1,
                       base.addresscity,
                       base.addressstate,
                       base.addresszip,
                       base.phone,
                       base.userprinciplename,
                       base.barcode,
                       base.email_address,
                       base.username,
                       NULL                       school,
                       base.campuscode,
                       NULL                       employeestatus,
                       base.levl,
                       NULL                       enrl_status,
                       base.class,
                       base.department,
                       base.mobile_credential_one,
                       base.mobile_credential_two,
                       base.primaryidentifier     AS unique_id
         FROM base
        WHERE 1 = 1
          AND base.ranker = 1
          AND base.user_group <> 'EXCLUDE' -- excluding the students not in a group and who dont have mobc info
        ) new_rec
         LEFT JOIN utl_d_aa.alma_sendlist existing_rec
           ON existing_rec.unique_id = new_rec.unique_id
          AND existing_rec.to_date = to_date('12/31/2099', 'MM/DD/YYYY'); -- only return active records from the target (ignore all previous);  WHERE CLAUSE WAS MOVED UP TO THE SELECT CONTROL_STATE ON 6/16/2025 CHANGE
TYPE rec_input_t IS TABLE OF curs%ROWTYPE;
rec_input rec_input_t;
TYPE index_pointer_t IS TABLE OF PLS_INTEGER;
ttab_dml index_pointer_t := index_pointer_t();
CURSOR cur_idx_dat(schema_ VARCHAR2,
                   table_  VARCHAR2) IS(
SELECT lower(a_idx.owner || '.' || a_idx.index_name) idx
  FROM all_indexes a_idx
 WHERE a_idx.owner = upper(schema_)
   AND a_idx.table_name = upper(table_));
rec_idx_dat cur_idx_dat%ROWTYPE;
TYPE index_pointer_e IS TABLE OF PLS_INTEGER;
expire_dml index_pointer_e := index_pointer_e();
TYPE index_pointer_u IS TABLE OF PLS_INTEGER;
update_dml index_pointer_u := index_pointer_u();
TYPE index_pointer_i IS TABLE OF PLS_INTEGER;
insert_dml   index_pointer_i := index_pointer_i();
start_time   TIMESTAMP;
end_time     TIMESTAMP;
select_count NUMBER := 0;
expire_count NUMBER := 0;
update_count NUMBER := 0;
insert_count NUMBER := 0;
start_t      DATE := SYSDATE;
elapsed      NUMBER := 0;
BEGIN
-- dbms_output.enable(buffer_size => NULL);
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
--
OPEN curs;
LOOP
v_count   := 0; -- reset count
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ALL' || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
FETCH curs BULK COLLECT
INTO rec_input LIMIT v_row_max;
IF rec_input.count = 0 THEN
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'SELECT - ALL' || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
RETURN;
ELSIF rec_input.count > 0 THEN
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'SELECT - ' || v_instance || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
expire_dml := index_pointer_e();
update_dml := index_pointer_u();
insert_dml := index_pointer_i();
-- collect records to DML
FOR idx IN rec_input.first .. rec_input.last
LOOP
v_count := rec_input(idx).total_rows;
IF rec_input(idx).control_state IN ('EXPIRE') THEN
-- record no longer exists, expire it
expire_dml.extend;
expire_dml(expire_dml.last) := idx;
END IF;
IF rec_input(idx).control_state IN ('UPDATE') THEN
-- existing record, no change
update_dml.extend;
update_dml(update_dml.last) := idx;
END IF;
IF rec_input(idx).control_state IN ('INSERT', 'EXPIRE') THEN
-- new record to source, add it or record no longer exists, expire it
insert_dml.extend;
insert_dml(insert_dml.last) := idx;
END IF;
END LOOP;
expire_count := expire_count + expire_dml.count;
update_count := update_count + update_dml.count;
insert_count := insert_count + insert_dml.count;
-- record no longer exists, expire it
FORALL i IN VALUES OF update_dml
UPDATE utl_d_aa.alma_sendlist tab
   SET (activity_date) =
       (SELECT v_etl_date FROM dual)
 WHERE tab.unique_id = rec_input(i).unique_id
   AND tab.to_date = to_date('12/31/2099', 'MM/DD/YYYY');
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'UPDATE - ACTIVE - ALL' || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- existing record, no change
FORALL i IN VALUES OF expire_dml
UPDATE utl_d_aa.alma_sendlist tab
   SET (activity_date, to_date) =
       (SELECT v_etl_date,
               v_end_date
          FROM dual)
 WHERE tab.unique_id = rec_input(i).unique_id
   AND tab.to_date = to_date('12/31/2099', 'MM/DD/YYYY');
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'UPDATE - EXISTS - ' || v_instance || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- new record to source, add it or record no longer exists, expire it
FORALL i IN VALUES OF insert_dml
INSERT INTO utl_d_aa.alma_sendlist tab
(tab.firstname,
 tab.middlename,
 tab.lastname,
 tab.fullname,
 tab.title,
 tab.primaryidentifier,
 tab.expirationdate,
 tab.gender,
 tab.usergroup,
 tab.photo,
 tab.addressline1,
 tab.addresscity,
 tab.addressstate,
 tab.addresszip,
 tab.phone,
 tab.userprinciplename,
 tab.barcode,
 tab.email_address,
 tab.username,
 tab.school,
 tab.campuscode,
 tab.employeestatus,
 tab.levl,
 tab.enrl_status,
 tab.class,
 tab.department,
 tab.mobile_credential_one,
 tab.mobile_credential_two,
 tab.unique_id,
 tab.activity_date,
 tab.from_date,
 tab.to_date)
VALUES
(rec_input(i).firstname,
 rec_input(i).middlename,
 rec_input(i).lastname,
 rec_input(i).fullname,
 rec_input(i).title,
 rec_input(i).primaryidentifier,
 rec_input(i).expirationdate,
 rec_input(i).gender,
 rec_input(i).usergroup,
 rec_input(i).photo,
 rec_input(i).addressline1,
 rec_input(i).addresscity,
 rec_input(i).addressstate,
 rec_input(i).addresszip,
 rec_input(i).phone,
 rec_input(i).userprinciplename,
 rec_input(i).barcode,
 rec_input(i).email_address,
 rec_input(i).username,
 rec_input(i).school,
 rec_input(i).campuscode,
 rec_input(i).employeestatus,
 rec_input(i).levl,
 rec_input(i).enrl_status,
 rec_input(i).class,
 rec_input(i).department,
 rec_input(i).mobile_credential_one,
 rec_input(i).mobile_credential_two,
 rec_input(i).unique_id,
 v_etl_date,
 v_etl_date,
 to_date('12/31/2099', 'MM/DD/YYYY'));
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - NEW - ' || v_instance || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
END IF;
SELECT ((CAST(SYSDATE AS DATE) - CAST(start_t AS DATE)) * 86400) INTO elapsed FROM dual;
select_count := select_count + rec_input.count;
EXIT WHEN(rec_input.count < v_row_max);
END LOOP;
CLOSE curs;
dbms_output.put_line(' --------- ');
-- keep outside of looping; end records that don't exist in current cursor
UPDATE utl_d_aa.alma_sendlist tgt
   SET tgt.to_date = v_end_date
 WHERE tgt.to_date = to_date('12/31/2099', 'MM/DD/YYYY')
   AND tgt.activity_date < v_etl_date; -- record wasn't looped over on last run, so it no longer exists, end it.
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'UPDATE - NOT EXISTS - ' || v_instance || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
-- log any errors
EXCEPTION
WHEN OTHERS THEN
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
/*--------------------------------------------CHANGE LOG----------------------------------------
VERSION  DATE        USERNAME    UPDATES
---      10/10/2024    JWTUCKER1     Initial Release
---      11/21/2024    JWTUCKER1     updated base CTE to fix duplication and added unique_id as table constraint
---      03/17/2025    JWTUCKER1     updated mobc to not exclude luo, created new group to exclude students who dont belong
---      06/13/2025    JWTUCKER1     update to user groups per customer request; 06/16/2025 wgriffith2 -- fixing the constraint error problem that is from having multiple rows per student =to_date('2099-12-31','YYYY-MM-DD');
---      07/31/2025    JWTUCKER1     updated mobile credential CTE, customer wants all credential info to come in so i changed the query to have left joins for physical and mobile creds
---      08/13/2025    JWTUCKER1     updated mobc cte to not join spriden on name, was removing barcode / mobile cred info for students who have a different name in envision tables
---      09/04/2025    JWTUCKER1     last update removed barcode limitations which started to cause unique contraint issues for multiple barcodes, added a max on fp_card to pull most recent (active) barcode
---      10/23/2025    JWTUCKER1     Changed barcode logic to show barcode no matter what, as long as the trimmed value does not equal the students primary identifier
---      11/13/2025    JWTUCKER1     Updated mobile one and two columns to be null if they are equal to the barcode, and if mobile two is the same as mobile one it is null as well
------------------------------------------------------------------------------------------------*/
END etl_aa_alma;

procedure etl_aa_core_soe_elms(jobnumber number, processid varchar2, processname varchar2) is
/***************************************************
Table: utl_d_aa.core_soe_elms
Primary Keys: NONE
Unique index: unique_key, TO_DATE, FROM_DATE
Purpose:
- Student program and demographic information for students who are currently enrolled in CORE programs
Conditions:
- this will leave historical data on the table, but use the to and from dates to return the latest record
Dependencies: zformdata.zfblist; zformdata.zfrlist; utl_d_aim.szrenrl; zdegree_audit
****************************************************/
--DECLARE
--- PARAMS
v_etl_date    DATE := SYSDATE;
v_end_date    DATE := SYSDATE - 1 / (24 * 60 * 60); -- ONE SEC BEHIND
v_msg         VARCHAR2(255);
v_row_max     NUMBER := 1000000; -- max number of rows to be processed at one time
v_job_id      VARCHAR2(32);
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_cpu         NUMBER := 4; -- number of CPUs used for parallelization - do not exceed 20 CPUs [v_mod x v_cpu] if running simultaneously
v_proc        VARCHAR2(100) := 'etl_aa_core_soe_elms';
v_instance    VARCHAR2(100) := 'ALL'; -- placeholder
v_partition    NUMBER := 0; -- placeholder
-- cursors
CURSOR curs IS
SELECT new_rec.*,
       CASE
       WHEN existing_rec.unique_key IS NULL THEN
        'NEW'
       WHEN existing_rec.unique_key IS NOT NULL THEN
        'CHANGE'
       END AS control_state, -- we are NOT deleting - EVER!
       COUNT(*) over() total_rows
  FROM (WITH termcode AS (SELECT MAX(term_code) AS term -- current term
                            FROM zbtm.terms_by_group_v
                           WHERE group_code = 'STD'
                             AND semester != 'WIN'
                             AND start_date <= SYSDATE), --
        course_list AS (SELECT /*+ materialize */
                         l.zfrlist_char_01,
                         l.zfrlist_char_02,
                         l.zfrlist_char_03 courselist
                          FROM zformdata.zfblist b
                          JOIN zformdata.zfrlist l
                            ON l.zfrlist_list_code = b.zfblist_code
                           AND l.zfrlist_active_yn = 'Y'
                         WHERE b.zfblist_code = 'CORE_ELMS_COURSELIST'
                           AND l.zfrlist_char_01 IN ('SOEIP', 'SOE')), --
        program_list AS (SELECT /*+ materialize */
                          l2.zfrlist_char_01 progschool, -- list of programs for core elms feeds
                          l2.zfrlist_char_02 progterm,
                          l2.zfrlist_char_03 proglist
                           FROM zformdata.zfblist b2
                           JOIN zformdata.zfrlist l2
                             ON l2.zfrlist_list_code = b2.zfblist_code
                            AND l2.zfrlist_active_yn = 'Y'
                            AND l2.zfrlist_char_01 = 'SOE'
                          WHERE b2.zfblist_code = 'CORE_ELMS_PROGRAMS'), --
        courses AS (SELECT /*+ materialize*/
                     t.zfrlist_char_01 school,
                     t.zfrlist_char_02 term,
                     TRIM(regexp_substr(REPLACE(t.courselist, '&', ','), '[^,]+', 1, LEVEL)) course -- breaking out courses from general list
                      FROM course_list t -- bringing in normal and internship/practicum courses
                    CONNECT BY PRIOR dbms_random.value IS NOT NULL
                           AND PRIOR t.zfrlist_char_01 = t.zfrlist_char_01
                           AND PRIOR t.zfrlist_char_02 = t.zfrlist_char_02
                           AND LEVEL <= regexp_count(REPLACE(t.courselist, '&', ','), ',') + 1), --
        programs AS (SELECT /*+ materialize*/
                      t2.progschool pgschool,
                      t2.progterm pgterm,
                      TRIM(regexp_substr(REPLACE(t2.proglist, '&', ','), '[^,]+', 1, LEVEL)) pglist -- breaking out programs similar to courses
                       FROM program_list t2
                     CONNECT BY PRIOR dbms_random.value IS NOT NULL
                            AND PRIOR t2.progschool = t2.progschool
                            AND PRIOR t2.progterm = t2.progterm
                            AND LEVEL <= regexp_count(REPLACE(t2.proglist, '&', ','), ',') + 1), --
        base AS (SELECT /*+ materialize */
                  enrl.pidm,
                  enrl.first_name fname,
                  enrl.last_name lname,
                  enrl.luid,
                  enrl.lu_email lu_email,
                  enrl.alt_email,
                  nvl(enrl.phone_text, enrl.phone) phone,
                  enrl.camp_code campus,
                  enrl.ipeds_ethn,
                  enrl.gender gender,
                  enrl.term_code,
                  enrl.prog_code_1 program,
                  enrl.levl_code level_code,
                  enrl.cum_gpa overall_gpa,
                  enrl.hrs_remaining,
                  enrl.classification,
                  enrl.ctlg_term_1
                   FROM utl_d_aim.szrenrl enrl
                   JOIN zsaturn.szrlevl levl
                     ON levl.szrlevl_levl_code = enrl.levl_code -- instead of hardcoded values, limiting in base pop
                    AND levl.szrlevl_is_univ = 'Y'
                    AND levl.szrlevl_has_awardable_cred = 'Y'
                  WHERE 1 = 1
                    AND enrl.term_code >= (SELECT term FROM termcode)
                    AND (enrl.prog_code_1 IN (SELECT pglist FROM programs) -- students who are either in an soe program or in an soe course (regardless of program)
                        OR EXISTS (SELECT 1
                                     FROM utl_d_aim.szrcrse bc
                                    WHERE bc.pidm = enrl.pidm
                                      AND bc.term_code = enrl.term_code
                                      AND bc.course IN (SELECT course FROM courses WHERE courses.school IN ('SOE', 'SOEIP'))))), --
                    mgpa AS (SELECT /*+ materialize */
        v.pidm pidm, b.blck_code blck_code, v.audit_term term_code, trunc(SUM(shrgrde.shrgrde_quality_points * cc.credit_hr) / nullif(SUM(cc.credit_hr), 0), 4) major_gpa FROM base b JOIN zdegree_audit.davaudit v ON
        v.pidm = b.pidm AND v.whatif_prog_ind = 'N' AND v.current_ind = 'Y' AND v.audit_term >= (SELECT term FROM termcode) JOIN zdegree_audit.daaudit a ON
        a.davaudit_id = v.davaudit_id AND a.req_met_rule_use_ind = 'Y' AND a.blck_code = b.program JOIN zdegree_audit.davblocks b ON b.blck_code = a.blck_code AND b.majr_blck_ind = 'Y' JOIN zdegree_audit.dacrsehist c ON
        c.davaudit_id = v.davaudit_id AND c.pseudo_eqiv_course_ind = 'N' AND c.test_code_ind = 'N' AND c.transfer_ind = 'N' AND c.inprogress_ind = 'N' JOIN zdegree_audit.dacrsehistused u ON
        u.dacrsehist_id = c.id AND u.davaudit_id = v.davaudit_id AND u.used_daaudit_id = a.dacrserules_id JOIN utl_d_aim.szrcrse cc ON cc.pidm = v.pidm AND cc.term_code = v.audit_term JOIN saturn.shrgrde shrgrde ON
        shrgrde.shrgrde_code = cc.final_grade AND shrgrde.shrgrde_levl_code = cc.levl_code AND shrgrde.shrgrde_gpa_ind = 'Y' AND
        shrgrde.shrgrde_term_code_effective = (SELECT MAX(shrgrde2.shrgrde_term_code_effective)
                                                 FROM saturn.shrgrde shrgrde2
                                                WHERE shrgrde.shrgrde_code = shrgrde2.shrgrde_code
                                                  AND shrgrde.shrgrde_levl_code = shrgrde2.shrgrde_levl_code) GROUP BY v.pidm, v.audit_term, b.blck_code),
       mainquery AS (
                      -- using this query for left joins for query speed (to bring in data that could be null)
                      SELECT /*+ materialize */
                       base.pidm,
                        base.luid luid,
                        base.fname firstname,
                        base.lname lastname,
                        base.lu_email email,
                        base.alt_email,
                        base.term_code enrl_term,
                        base.phone phone,
                        CASE
                        WHEN base.ipeds_ethn = 'American_Indian_Alaska_Native' THEN
                         'American Indian Alaska Native'
                        WHEN base.ipeds_ethn = 'Asian' THEN
                         'Asian'
                        WHEN base.ipeds_ethn = 'Black_or_African_American' THEN
                         'Black or African American'
                        WHEN base.ipeds_ethn = 'Hispanic_Latino' THEN
                         'Hispanic Latino'
                        WHEN base.ipeds_ethn = 'Native_Hawaiian_Pacific_Islander' THEN
                         'Native Hawaiian Pacific Islander'
                        WHEN base.ipeds_ethn = 'Nonresident_Alien' THEN
                         'Nonresident Alien'
                        WHEN base.ipeds_ethn = 'Two_or_more_races' THEN
                         'Two or more races'
                        WHEN base.ipeds_ethn = 'Unreported' THEN
                         'Unreported'
                        WHEN base.ipeds_ethn = 'White' THEN
                         'White'
                        END ethnicity,
                        base.gender,
                        base.program,
                        prle.smrprle_program_desc progname,
                        base.campus, -- program campus code
                        CASE
                        WHEN t.stvterm_code <= '199930' THEN
                         '19' || substr(t.stvterm_fa_proc_yr, 1, 2) || '-' || '19' || substr(t.stvterm_fa_proc_yr, 3, 4)
                        WHEN t.stvterm_code IN ('199940', '200020') THEN
                         '19' || substr(t.stvterm_fa_proc_yr, 1, 2) || '-' || '20' || substr(t.stvterm_fa_proc_yr, 3, 4)
                        WHEN t.stvterm_code >= '200020' THEN
                         '20' || substr(t.stvterm_fa_proc_yr, 1, 2) || '-' || '20' || substr(t.stvterm_fa_proc_yr, 3, 4)
                        END dcp_year, -- dcp_year
                        CASE
                        WHEN base.classification = '1_Freshman' THEN
                         'Freshman'
                        WHEN base.classification = '2_Sophomore' THEN
                         'Sophomore'
                        WHEN base.classification = '3_Junior' THEN
                         'Junior'
                        WHEN base.classification = '4_Senior' THEN
                         'Senior'
                        ELSE
                         base.classification
                        END classification,
                        base.overall_gpa, -- overall gpa
                        mgpa.major_gpa majorgpa, -- major gpa
                        base.hrs_remaining credit_hrs_remaining, -- credit hours remaining
                        coalesce(to_number(MAX(gmr.shrdgmr_acyr_code)), (SELECT to_number(substr(term, 0, 4)) + 2 FROM termcode)) grad_year, -- sgbstdn exp grad date was tanking runtime and innacurate, creating a default + 2 years exp grad year
                        'L' location_code,
                        nvl(addr.street_line1, resi.street_line1) address1,
                        nvl(addr.street_line2, resi.street_line2) address2,
                        nvl(addr.city, resi.city) city,
                        nvl(addr.stat_code, resi.stat_code) state,
                        nvl(addr.zip5, resi.zip5) zip,
                        nvl(addr.natn_code, resi.natn_code) country,
                        resi.stat_code,
                        CASE
                        WHEN (lower(emer.spremrg_first_name) = 'unknown' OR lower(emer.spremrg_last_name) = 'unknown') THEN
                         NULL
                        ELSE
                         emer.spremrg_first_name || ' ' || emer.spremrg_last_name
                        END e_contact,
                        CASE
                        WHEN length(regexp_replace(emer.spremrg_phone_number, '[^0-9]')) = 7
                             AND length(emer.spremrg_phone_area) = 3 THEN
                         emer.spremrg_phone_area || regexp_replace(emer.spremrg_phone_number, '[^0-9]')
                        WHEN length(regexp_replace(emer.spremrg_phone_number, '[^0-9]')) = 10 THEN
                         regexp_replace(emer.spremrg_phone_number, '[^0-9]')
                        WHEN length(emer.spremrg_phone_area) = 3
                             AND length(regexp_replace(emer.spremrg_phone_number, '[^0-9]')) = 3
                             AND length(emer.spremrg_phone_ext) = 4 THEN
                         emer.spremrg_phone_area || regexp_replace(emer.spremrg_phone_number, '[^0-9]') || emer.spremrg_phone_ext
                        ELSE
                         NULL
                        END e_contact_num, -- emergency contact number
                        CASE
                        WHEN crse.final_grade IS NULL THEN
                         listagg(DISTINCT regexp_replace(crse.course, '([A-Z]+)([0-9]+)', '\1 \2'), ' | ') within GROUP(ORDER BY crse.course)
                        END ec, -- enrolled courses
                        CASE
                        WHEN crse.final_grade IS NOT NULL THEN
                         listagg(DISTINCT regexp_replace(crse.course, '([A-Z]+)([0-9]+)', '\1 \2'), ' | ') within GROUP(ORDER BY crse.course)
                        END cc, -- completed courses
                        CASE
                        WHEN crse.final_grade IS NOT NULL THEN
                         listagg(DISTINCT regexp_replace(crse.course, '([A-Z]+)([0-9]+)', '\1 \2') || ' (' || crse.final_grade || ')', ' | ') within GROUP(ORDER BY crse.course)
                        END ccg, -- completed course grades
                        listagg(DISTINCT regexp_replace(crse2.course, '([A-Z]+)([0-9]+)', '\1 \2'), ' | ') within GROUP(ORDER BY crse2.course) ips -- intership / practicum courses
                        FROM base
                        JOIN smrprle prle
                          ON prle.smrprle_program = base.program
                        LEFT JOIN mgpa
                          ON mgpa.pidm = base.pidm
                         AND mgpa.blck_code = base.program
                         AND mgpa.term_code = base.term_code
                        LEFT JOIN utl_d_aim.szrcrse crse
                          ON crse.pidm = base.pidm
                         AND crse.term_code <= base.term_code
                         AND crse.levl_code = base.level_code
                         AND crse.course IN (SELECT course FROM courses WHERE courses.school = 'SOE')
                        LEFT JOIN utl_d_aim.szrcrse crse2
                          ON crse2.pidm = base.pidm
                         AND crse2.term_code <= base.term_code
                         AND crse2.levl_code = base.level_code
                         AND crse2.course IN (SELECT course FROM courses WHERE courses.school = 'SOEIP')
                        LEFT JOIN zexec.zsavaddr addr
                          ON addr.pidm = base.pidm
                         AND addr.atyp_code = 'MA'
                         AND addr.addr_type_rank = 1
                        LEFT JOIN zexec.zsavaddr resi
                          ON resi.pidm = base.pidm
                         AND resi.atyp_code = 'LP'
                         AND resi.addr_type_rank = 1
                        LEFT JOIN spremrg emer
                          ON emer.spremrg_pidm = base.pidm -- emergency contact info
                         AND emer.spremrg_priority = 1
                        LEFT JOIN stvterm t
                          ON t.stvterm_code = base.ctlg_term_1
                        LEFT JOIN shrdgmr gmr
                          ON gmr.shrdgmr_pidm = base.pidm
                         AND gmr.shrdgmr_program = base.program
                         AND gmr.shrdgmr_levl_code = base.level_code -- grad year, if no grad year use exp grad date default
                         AND gmr.shrdgmr_degs_code <> 'IN' -- students were duplicating due to having an IN record for the same prog
                         AND gmr.shrdgmr_term_code_grad >= (SELECT term FROM termcode) -- graduating this sem or in future
                       GROUP BY base.pidm,
                                 base.luid,
                                 base.fname,
                                 base.lname,
                                 base.lu_email,
                                 base.alt_email,
                                 base.term_code,
                                 base.phone,
                                 CASE
                                 WHEN base.ipeds_ethn = 'American_Indian_Alaska_Native' THEN
                                  'American Indian Alaska Native'
                                 WHEN base.ipeds_ethn = 'Asian' THEN
                                  'Asian'
                                 WHEN base.ipeds_ethn = 'Black_or_African_American' THEN
                                  'Black or African American'
                                 WHEN base.ipeds_ethn = 'Hispanic_Latino' THEN
                                  'Hispanic Latino'
                                 WHEN base.ipeds_ethn = 'Native_Hawaiian_Pacific_Islander' THEN
                                  'Native Hawaiian Pacific Islander'
                                 WHEN base.ipeds_ethn = 'Nonresident_Alien' THEN
                                  'Nonresident Alien'
                                 WHEN base.ipeds_ethn = 'Two_or_more_races' THEN
                                  'Two or more races'
                                 WHEN base.ipeds_ethn = 'Unreported' THEN
                                  'Unreported'
                                 WHEN base.ipeds_ethn = 'White' THEN
                                  'White'
                                 END,
                                 base.gender,
                                 base.program,
                                 prle.smrprle_program_desc,
                                 base.campus,
                                 CASE
                                 WHEN t.stvterm_code <= '199930' THEN
                                  '19' || substr(t.stvterm_fa_proc_yr, 1, 2) || '-' || '19' || substr(t.stvterm_fa_proc_yr, 3, 4)
                                 WHEN t.stvterm_code IN ('199940', '200020') THEN
                                  '19' || substr(t.stvterm_fa_proc_yr, 1, 2) || '-' || '20' || substr(t.stvterm_fa_proc_yr, 3, 4)
                                 WHEN t.stvterm_code >= '200020' THEN
                                  '20' || substr(t.stvterm_fa_proc_yr, 1, 2) || '-' || '20' || substr(t.stvterm_fa_proc_yr, 3, 4)
                                 END,
                                 CASE
                                 WHEN base.classification = '1_Freshman' THEN
                                  'Freshman'
                                 WHEN base.classification = '2_Sophomore' THEN
                                  'Sophomore'
                                 WHEN base.classification = '3_Junior' THEN
                                  'Junior'
                                 WHEN base.classification = '4_Senior' THEN
                                  'Senior'
                                 ELSE
                                  base.classification
                                 END,
                                 base.overall_gpa,
                                 mgpa.major_gpa,
                                 base.hrs_remaining,
                                 gmr.shrdgmr_acyr_code,
                                 'L',
                                 nvl(addr.street_line1, resi.street_line1),
                                 nvl(addr.street_line2, resi.street_line2),
                                 nvl(addr.city, resi.city),
                                 nvl(addr.stat_code, resi.stat_code),
                                 nvl(addr.zip5, resi.zip5),
                                 nvl(addr.natn_code, resi.natn_code),
                                 resi.stat_code,
                                 CASE
                                 WHEN (lower(emer.spremrg_first_name) = 'unknown' OR lower(emer.spremrg_last_name) = 'unknown') THEN
                                  NULL
                                 ELSE
                                  emer.spremrg_first_name || ' ' || emer.spremrg_last_name
                                 END,
                                 CASE
                                 WHEN length(regexp_replace(emer.spremrg_phone_number, '[^0-9]')) = 7
                                      AND length(emer.spremrg_phone_area) = 3 THEN
                                  emer.spremrg_phone_area || regexp_replace(emer.spremrg_phone_number, '[^0-9]')
                                 WHEN length(regexp_replace(emer.spremrg_phone_number, '[^0-9]')) = 10 THEN
                                  regexp_replace(emer.spremrg_phone_number, '[^0-9]')
                                 WHEN length(emer.spremrg_phone_area) = 3
                                      AND length(regexp_replace(emer.spremrg_phone_number, '[^0-9]')) = 3
                                      AND length(emer.spremrg_phone_ext) = 4 THEN
                                  emer.spremrg_phone_area || regexp_replace(emer.spremrg_phone_number, '[^0-9]') || emer.spremrg_phone_ext
                                 ELSE
                                  NULL
                                 END,
                                 crse.final_grade)
       SELECT mainquery.pidm || mainquery.enrl_term unique_key,
              mainquery.pidm,
              mainquery.luid,
              mainquery.firstname,
              mainquery.lastname,
              mainquery.enrl_term, -- the tables can have multiple terms for a student (to account for future reg for the upcoming sem)
              mainquery.email,
              mainquery.alt_email,
              mainquery.phone,
              mainquery.ethnicity,
              mainquery.gender,
              mainquery.program,
              mainquery.progname,
              mainquery.campus, -- program campus code
              mainquery.dcp_year, -- dcp_year
              mainquery.classification,
              mainquery.overall_gpa, -- overall gpa
              mainquery.majorgpa, -- major gpa
              mainquery.credit_hrs_remaining, -- credit hours remaining
              mainquery.grad_year,
              mainquery.location_code,
              mainquery.address1,
              mainquery.address2,
              mainquery.city,
              mainquery.state,
              mainquery.zip,
              mainquery.country,
              mainquery.stat_code state_code,
              mainquery.e_contact emergency_contact,
              mainquery.e_contact_num emergency_contact_number, -- emergency contact number
              MAX(mainquery.ec) enrolled_courses, -- enrolled courses
              MAX(mainquery.cc) completed_courses, -- completed courses
              MAX(mainquery.ccg) completed_course_grades, -- completed course grades
              MAX(mainquery.ips) internship_practicum_sections -- enrolled internship/practicum sections
         FROM mainquery
        GROUP BY mainquery.pidm || mainquery.enrl_term,
                 mainquery.pidm,
                 mainquery.luid,
                 mainquery.firstname,
                 mainquery.lastname,
                 mainquery.enrl_term,
                 mainquery.email,
                 mainquery.alt_email,
                 mainquery.phone,
                 mainquery.ethnicity,
                 mainquery.gender,
                 mainquery.program,
                 mainquery.progname,
                 mainquery.campus,
                 mainquery.dcp_year,
                 mainquery.classification,
                 mainquery.overall_gpa,
                 mainquery.majorgpa,
                 mainquery.credit_hrs_remaining,
                 mainquery.grad_year,
                 mainquery.location_code,
                 mainquery.address1,
                 mainquery.address2,
                 mainquery.city,
                 mainquery.state,
                 mainquery.zip,
                 mainquery.country,
                 mainquery.stat_code,
                 mainquery.e_contact,
                 mainquery.e_contact_num) new_rec
         LEFT JOIN utl_d_aa.core_soe_elms existing_rec
           ON existing_rec.unique_key = new_rec.unique_key
          AND existing_rec.to_date = to_date('12/31/2099', 'MM/DD/YYYY')
        WHERE existing_rec.unique_key IS NULL -- new record
             -- using nvls to find any changes for student record
           OR (coalesce(existing_rec.luid, 'XXXXXX') != coalesce(new_rec.luid, 'XXXXXX') OR coalesce(existing_rec.firstname, 'XXXXXX') != coalesce(new_rec.firstname, 'XXXXXX') OR
              coalesce(existing_rec.lastname, 'XXXXXX') != coalesce(new_rec.lastname, 'XXXXXX') OR coalesce(existing_rec.email, 'XXXXXX') != coalesce(new_rec.email, 'XXXXXX') OR
              coalesce(existing_rec.alt_email, 'XXXXXX') != coalesce(new_rec.alt_email, 'XXXXXX') OR coalesce(existing_rec.phone, 'XXXXXX') != coalesce(new_rec.phone, 'XXXXXX') OR
              coalesce(existing_rec.ethnicity, 'XXXXXX') != coalesce(new_rec.ethnicity, 'XXXXXX') OR coalesce(existing_rec.gender, 'XXXXXX') != coalesce(new_rec.gender, 'XXXXXX') OR
              coalesce(existing_rec.program, 'XXXXXX') != coalesce(new_rec.program, 'XXXXXX') OR coalesce(existing_rec.progname, 'XXXXXX') != coalesce(new_rec.progname, 'XXXXXX') OR
              coalesce(existing_rec.campus, 'XXXXXX') != coalesce(new_rec.campus, 'XXXXXX') OR coalesce(existing_rec.dcp_year, 'XXXXXX') != coalesce(new_rec.dcp_year, 'XXXXXX') OR
              coalesce(existing_rec.classification, 'XXXXXX') != coalesce(new_rec.classification, 'XXXXXX') OR coalesce(existing_rec.overall_gpa, 999999) != coalesce(new_rec.overall_gpa, 999999) OR
              coalesce(existing_rec.majorgpa, 999999) != coalesce(new_rec.majorgpa, 999999) OR coalesce(existing_rec.credit_hrs_remaining, 999999) != coalesce(new_rec.credit_hrs_remaining, 999999) OR
              coalesce(existing_rec.grad_year, 999999) != coalesce(new_rec.grad_year, 999999) OR coalesce(existing_rec.location_code, 'XXXXXX') != coalesce(new_rec.location_code, 'XXXXXX') OR
              coalesce(existing_rec.address1, 'XXXXXX') != coalesce(new_rec.address1, 'XXXXXX') OR coalesce(existing_rec.address2, 'XXXXXX') != coalesce(new_rec.address2, 'XXXXXX') OR
              coalesce(existing_rec.city, 'XXXXXX') != coalesce(new_rec.city, 'XXXXXX') OR coalesce(existing_rec.state, 'XXXXXX') != coalesce(new_rec.state, 'XXXXXX') OR
              coalesce(existing_rec.zip, 'XXXXXX') != coalesce(new_rec.zip, 'XXXXXX') OR coalesce(existing_rec.country, 'XXXXXX') != coalesce(new_rec.country, 'XXXXXX') OR
              coalesce(existing_rec.state_code, 'XXXXXX') != coalesce(new_rec.state_code, 'XXXXXX') OR coalesce(existing_rec.emergency_contact, 'XXXXXX') != coalesce(new_rec.emergency_contact, 'XXXXXX') OR
              coalesce(existing_rec.emergency_contact_number, 'XXXXXX') != coalesce(new_rec.emergency_contact_number, 'XXXXXX') OR coalesce(existing_rec.enrolled_courses, 'XXXXXX') != coalesce(new_rec.enrolled_courses, 'XXXXXX') OR
              coalesce(existing_rec.completed_courses, 'XXXXXX') != coalesce(new_rec.completed_courses, 'XXXXXX') OR coalesce(existing_rec.completed_course_grades, 'XXXXXX') != coalesce(new_rec.completed_course_grades, 'XXXXXX') OR
              coalesce(existing_rec.internship_practicum_sections, 'XXXXXX') != coalesce(new_rec.internship_practicum_sections, 'XXXXXX'));

TYPE rec_input_t IS TABLE OF curs%ROWTYPE;
rec_input rec_input_t;
TYPE index_pointer_t IS TABLE OF PLS_INTEGER;
ttab_dml index_pointer_t := index_pointer_t();
CURSOR cur_idx_dat(schema_ VARCHAR2,
                   table_  VARCHAR2) IS(
SELECT lower(a_idx.owner || '.' || a_idx.index_name) idx
  FROM all_indexes a_idx
 WHERE a_idx.owner = upper(schema_)
   AND a_idx.table_name = upper(table_));
rec_idx_dat cur_idx_dat%ROWTYPE;
TYPE index_pointer_i IS TABLE OF PLS_INTEGER;
insert_dml index_pointer_i := index_pointer_i();
TYPE index_pointer_u IS TABLE OF PLS_INTEGER;
update_dml index_pointer_u := index_pointer_u();
TYPE index_pointer_d IS TABLE OF PLS_INTEGER;
delete_dml   index_pointer_d := index_pointer_d();
start_time   TIMESTAMP;
end_time     TIMESTAMP;
select_count NUMBER := 0;
insert_count NUMBER := 0;
update_count NUMBER := 0;
delete_count NUMBER := 0;
start_t      DATE := SYSDATE;
elapsed      NUMBER := 0;
BEGIN
-- dbms_output.enable(buffer_size => NULL);
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
--
OPEN curs;
LOOP
v_count   := 0; -- reset count
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ALL' || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
FETCH curs BULK COLLECT
INTO rec_input LIMIT v_row_max;
IF rec_input.count = 0 THEN
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'SELECT - ALL' || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
RETURN;
ELSIF rec_input.count > 0 THEN
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'SELECT - ALL' || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
insert_dml := index_pointer_i();
update_dml := index_pointer_u();
FOR idx IN rec_input.first .. rec_input.last
LOOP
v_count := rec_input(idx).total_rows;
IF rec_input(idx).control_state = 'CHANGE' THEN
-- UPDATE HAS TO HAPPEN FIRST TO EXPIRE RECORDS THAT ALREADY EXIST
update_dml.extend;
update_dml(update_dml.last) := idx;
END IF;
IF rec_input(idx).control_state IN ('NEW', 'CHANGE') THEN
-- ALL NEW RECS OR CHANGES GET INSERTED
insert_dml.extend;
insert_dml(insert_dml.last) := idx;
END IF;
END LOOP;
update_count := update_count + update_dml.count;
insert_count := insert_count + insert_dml.count;
-- DML UPDATES
FORALL i IN VALUES OF update_dml
UPDATE utl_d_aa.core_soe_elms tab
   SET tab.to_date  = v_end_date,
     tab.activity_date = v_etl_date
 WHERE tab.unique_key = rec_input(i).unique_key
   AND tab.to_date = to_date('12/31/2099', 'MM/DD/YYYY');
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'UPDATE - ALL' || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- DML Inserts
FORALL i IN VALUES OF insert_dml
INSERT INTO utl_d_aa.core_soe_elms tab
(unique_key,from_date,to_date,activity_date,
 pidm,
 luid,
 firstname,
 lastname,
 enrl_term,
 email,
 alt_email,
 phone,
 ethnicity,
 gender,
 program,
 progname,
 campus,
 dcp_year,
 classification,
 overall_gpa,
 majorgpa,
 credit_hrs_remaining,
 grad_year,
 location_code,
 address1,
 address2,
 city,
 state,
 zip,
 country,
 state_code,
 emergency_contact,
 emergency_contact_number,
 enrolled_courses,
 completed_courses,
 completed_course_grades,
 internship_practicum_sections)
VALUES
(rec_input(i).unique_key,v_etl_date,to_date('12/31/2099', 'MM/DD/YYYY'),v_etl_date,
 rec_input(i).pidm,
 rec_input(i).luid,
 rec_input(i).firstname,
 rec_input(i).lastname,
 rec_input(i).enrl_term,
 rec_input(i).email,
 rec_input(i).alt_email,
 rec_input(i).phone,
 rec_input(i).ethnicity,
 rec_input(i).gender,
 rec_input(i).program,
 rec_input(i).progname,
 rec_input(i).campus,
 rec_input(i).dcp_year,
 rec_input(i).classification,
 rec_input(i).overall_gpa,
 rec_input(i).majorgpa,
 rec_input(i).credit_hrs_remaining,
 rec_input(i).grad_year,
 rec_input(i).location_code,
 rec_input(i).address1,
 rec_input(i).address2,
 rec_input(i).city,
 rec_input(i).state,
 rec_input(i).zip,
 rec_input(i).country,
 rec_input(i).state_code,
 rec_input(i).emergency_contact,
 rec_input(i).emergency_contact_number,
 rec_input(i).enrolled_courses,
 rec_input(i).completed_courses,
 rec_input(i).completed_course_grades,
 rec_input(i).internship_practicum_sections);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ALL' || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
END IF;
SELECT ((CAST(SYSDATE AS DATE) - CAST(start_t AS DATE)) * 86400) INTO elapsed FROM dual;
select_count := select_count + rec_input.count;
EXIT WHEN(rec_input.count < v_row_max);
END LOOP;
CLOSE curs;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
-- log any errors
EXCEPTION
WHEN OTHERS THEN
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
/*--------------------------------------------CHANGE LOG----------------------------------------
VERSION  DATE        USERNAME    UPDATES
---      12/11/2024    JWTUCKER1     Initial Release - broke up original ELMS procedure into separate procedures per school for runtime and troubleshooting
---      08/01/2025    JWTUCKER1     Students starting erroring due to multiple SHRDGMR records, with one being inactive and the other being active for their current program. Added a <> IN
---      09/19/2025    JWTUCKER1     Updated base CTE to include students who are in SOE courses but not in an SOE program, and changed update statement to join on pidm and not unique key, which has fixed students having multiple active records split up by term
------------------------------------------------------------------------------------------------*/
END etl_aa_core_soe_elms;

PROCEDURE etl_aa_core_sowk_elms(jobnumber NUMBER, processid VARCHAR2, processname VARCHAR2) IS
/***************************************************
Table: utl_d_aa.core_sowk_elms
Primary Keys: NONE
Unique index: unique_key, TO_DATE, FROM_DATE
Purpose:
- Student program and demographic information for students who are currently enrolled in CORE programs
Conditions:
- this will leave historical data on the table, but use the to and from dates to return the latest record
Dependencies: zformdata.zfblist; zformdata.zfrlist; utl_d_aim.szrenrl; zdegree_audit
****************************************************/
--DECLARE
--- PARAMS
v_etl_date    DATE := SYSDATE;
v_end_date    DATE := SYSDATE - 1 / (24 * 60 * 60); -- ONE SEC BEHIND
v_msg         VARCHAR2(255);
v_row_max     NUMBER := 1000000; -- max number of rows to be processed at one time
v_job_id      VARCHAR2(32);
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_cpu         NUMBER := 4; -- number of CPUs used for parallelization - do not exceed 20 CPUs [v_mod x v_cpu] if running simultaneously
v_proc        VARCHAR2(100) := 'etl_aa_core_sowk_elms';
v_instance    VARCHAR2(100) := 'ALL'; -- placeholder
v_partition    NUMBER := 0; -- placeholder
-- cursors
CURSOR curs IS
SELECT new_rec.*,
       CASE
       WHEN existing_rec.unique_key IS NULL THEN
        'NEW'
       WHEN existing_rec.unique_key IS NOT NULL THEN
        'CHANGE'
       END AS control_state, -- we are NOT deleting - EVER!
       COUNT(*) over() total_rows
  FROM (WITH termcode AS (SELECT MAX(term_code) AS term -- current term
                            FROM zbtm.terms_by_group_v
                           WHERE group_code = 'STD'
                             AND semester != 'WIN'
                             AND start_date <= SYSDATE), --
        course_list AS (SELECT /*+ materialize */
                         l.zfrlist_char_01,
                         l.zfrlist_char_02,
                         l.zfrlist_char_03 courselist
                          FROM zformdata.zfblist b
                          JOIN zformdata.zfrlist l
                            ON l.zfrlist_list_code = b.zfblist_code
                           AND l.zfrlist_active_yn = 'Y'
                         WHERE b.zfblist_code = 'CORE_ELMS_COURSELIST'
                           AND l.zfrlist_char_01 IN ('SOWK')), --
               program_list AS (SELECT /*+ materialize */
        l2.zfrlist_char_01 progschool, -- list of programs for core elms feeds
        l2.zfrlist_char_02 progterm, l2.zfrlist_char_03 proglist FROM zformdata.zfblist b2 JOIN zformdata.zfrlist l2 ON l2.zfrlist_list_code = b2.zfblist_code AND l2.zfrlist_active_yn = 'Y' AND l2.zfrlist_char_01 = 'SOWK' WHERE
        b2.zfblist_code = 'CORE_ELMS_PROGRAMS'), --
    courses AS (SELECT /*+ materialize*/
       t.zfrlist_char_01 school,
       t.zfrlist_char_02 term,
       TRIM(regexp_substr(REPLACE(t.courselist, '&', ','), '[^,]+', 1, LEVEL)) course -- breaking out courses from general list
  FROM course_list t -- bringing in normal and internship/practicum courses
CONNECT BY PRIOR dbms_random.value IS NOT NULL
       AND PRIOR t.zfrlist_char_01 = t.zfrlist_char_01
       AND PRIOR t.zfrlist_char_02 = t.zfrlist_char_02
       AND LEVEL <= regexp_count(REPLACE(t.courselist, '&', ','), ',') + 1), --
 programs AS (SELECT /*+ materialize*/
               t2.progschool pgschool,
               t2.progterm pgterm,
               TRIM(regexp_substr(REPLACE(t2.proglist, '&', ','), '[^,]+', 1, LEVEL)) pglist -- breaking out programs similar to courses
                FROM program_list t2
              CONNECT BY PRIOR dbms_random.value IS NOT NULL
                     AND PRIOR t2.progschool = t2.progschool
                     AND PRIOR t2.progterm = t2.progterm
                     AND LEVEL <= regexp_count(REPLACE(t2.proglist, '&', ','), ',') + 1), --
 base AS (SELECT /*+ materialize */
           enrl.pidm,
           enrl.first_name fname,
           enrl.last_name lname,
           enrl.luid,
           enrl.lu_email lu_email,
           enrl.alt_email,
           nvl(enrl.phone_text, enrl.phone) phone,
           enrl.camp_code campus,
           enrl.term_code,
           enrl.prog_code_1 program,
           enrl.levl_code level_code,
           enrl.cum_gpa overall_gpa,
           enrl.hrs_remaining,
           enrl.classification,
           enrl.ctlg_term_1
            FROM utl_d_aim.szrenrl enrl
            JOIN zsaturn.szrlevl levl
              ON levl.szrlevl_levl_code = enrl.levl_code -- instead of hardcoded values, limiting in base pop
             AND levl.szrlevl_is_univ = 'Y'
             AND levl.szrlevl_has_awardable_cred = 'Y'
           WHERE 1 = 1
             AND enrl.term_code >= (SELECT term FROM termcode)
             AND enrl.prog_code_1 IN (SELECT pglist FROM programs) -- in case of program use (will change to genlist when the custom tables are made)
          ), --
 mgpa AS (SELECT /*+ materialize */
           v.pidm pidm,
           b.blck_code blck_code,
           v.audit_term term_code,
           trunc(SUM(shrgrde.shrgrde_quality_points * cc.credit_hr) / nullif(SUM(cc.credit_hr), 0), 4) major_gpa
            FROM base b
            JOIN zdegree_audit.davaudit v
              ON v.pidm = b.pidm
             AND v.whatif_prog_ind = 'N'
             AND v.current_ind = 'Y'
             AND v.audit_term >= (SELECT term FROM termcode)
            JOIN zdegree_audit.daaudit a
              ON a.davaudit_id = v.davaudit_id
             AND a.req_met_rule_use_ind = 'Y'
             AND a.blck_code = b.program
            JOIN zdegree_audit.davblocks b
              ON b.blck_code = a.blck_code
             AND b.majr_blck_ind = 'Y'
            JOIN zdegree_audit.dacrsehist c
              ON c.davaudit_id = v.davaudit_id
             AND c.pseudo_eqiv_course_ind = 'N'
             AND c.test_code_ind = 'N'
             AND c.transfer_ind = 'N'
             AND c.inprogress_ind = 'N'
            JOIN zdegree_audit.dacrsehistused u
              ON u.dacrsehist_id = c.id
             AND u.davaudit_id = v.davaudit_id
             AND u.used_daaudit_id = a.dacrserules_id
            JOIN utl_d_aim.szrcrse cc
              ON cc.pidm = v.pidm
             AND cc.term_code = v.audit_term
            JOIN saturn.shrgrde shrgrde
              ON shrgrde.shrgrde_code = cc.final_grade
             AND shrgrde.shrgrde_levl_code = cc.levl_code
             AND shrgrde.shrgrde_gpa_ind = 'Y'
             AND shrgrde.shrgrde_term_code_effective = (SELECT MAX(shrgrde2.shrgrde_term_code_effective)
                                                          FROM saturn.shrgrde shrgrde2
                                                         WHERE shrgrde.shrgrde_code = shrgrde2.shrgrde_code
                                                           AND shrgrde.shrgrde_levl_code = shrgrde2.shrgrde_levl_code)
           GROUP BY v.pidm,
                    v.audit_term,
                    b.blck_code), --
 mainquery AS (
               -- using this query for left joins for query speed (to bring in data that could be null)
               SELECT /*+ materialize */
                base.pidm,
                 base.luid luid,
                 base.fname firstname,
                 base.lname lastname,
                 base.lu_email email,
                 base.alt_email,
                 base.term_code enrl_term,
                 base.phone phone,
                 base.program,
                 base.campus, -- program campus code
                 CASE
                 WHEN t.stvterm_code <= '199930' THEN
                  '19' || substr(t.stvterm_fa_proc_yr, 1, 2) || '-' || '19' || substr(t.stvterm_fa_proc_yr, 3, 4)
                 WHEN t.stvterm_code IN ('199940', '200020') THEN
                  '19' || substr(t.stvterm_fa_proc_yr, 1, 2) || '-' || '20' || substr(t.stvterm_fa_proc_yr, 3, 4)
                 WHEN t.stvterm_code >= '200020' THEN
                  '20' || substr(t.stvterm_fa_proc_yr, 1, 2) || '-' || '20' || substr(t.stvterm_fa_proc_yr, 3, 4)
                 END dcp_year, -- dcp_year
                 CASE
                 WHEN base.classification = '1_Freshman' THEN
                  'Freshman'
                 WHEN base.classification = '2_Sophomore' THEN
                  'Sophomore'
                 WHEN base.classification = '3_Junior' THEN
                  'Junior'
                 WHEN base.classification = '4_Senior' THEN
                  'Senior'
                 ELSE
                  base.classification
                 END classification,
                 base.overall_gpa, -- overall gpa
                 mgpa.major_gpa majorgpa, -- major gpa
                 base.hrs_remaining credit_hrs_remaining, -- credit hours remaining
                 coalesce(to_number(MAX(gmr.shrdgmr_acyr_code)), (SELECT to_number(substr(term, 0, 4)) + 2 FROM termcode)) grad_year, -- sgbstdn exp grad date was tanking runtime and innacurate, creating a default + 2 years exp grad year
                 CASE
                 WHEN base.campus = 'R' THEN
                  'CVA'
                 ELSE
                  'OCVA'
                 END location_code,
                 nvl(addr.street_line1, resi.street_line1) address1,
                 nvl(addr.street_line2, resi.street_line2) address2,
                 nvl(addr.city, resi.city) city,
                 nvl(addr.stat_code, resi.stat_code) state,
                 nvl(addr.zip5, resi.zip5) zip,
                 nvl(addr.natn_code, resi.natn_code) country,
                 resi.stat_code,
                 CASE
                 WHEN (lower(emer.spremrg_first_name) = 'unknown' OR lower(emer.spremrg_last_name) = 'unknown') THEN
                  NULL
                 ELSE
                  emer.spremrg_first_name || ' ' || emer.spremrg_last_name
                 END e_contact,
                 CASE
                 WHEN length(regexp_replace(emer.spremrg_phone_number, '[^0-9]')) = 7
                      AND length(emer.spremrg_phone_area) = 3 THEN
                  emer.spremrg_phone_area || regexp_replace(emer.spremrg_phone_number, '[^0-9]')
                 WHEN length(regexp_replace(emer.spremrg_phone_number, '[^0-9]')) = 10 THEN
                  regexp_replace(emer.spremrg_phone_number, '[^0-9]')
                 WHEN length(emer.spremrg_phone_area) = 3
                      AND length(regexp_replace(emer.spremrg_phone_number, '[^0-9]')) = 3
                      AND length(emer.spremrg_phone_ext) = 4 THEN
                  emer.spremrg_phone_area || regexp_replace(emer.spremrg_phone_number, '[^0-9]') || emer.spremrg_phone_ext
                 ELSE
                  NULL
                 END e_contact_num, -- emergency contact number
                 CASE
                 WHEN crse.final_grade IS NULL THEN
                  listagg(DISTINCT regexp_replace(crse.course, '([A-Z]+)([0-9]+)', '\1 \2'), ' | ') within GROUP(ORDER BY crse.course)
                 END ec, -- enrolled courses
                 CASE
                 WHEN crse.final_grade IS NOT NULL THEN
                  listagg(DISTINCT regexp_replace(crse.course, '([A-Z]+)([0-9]+)', '\1 \2'), ' | ') within GROUP(ORDER BY crse.course)
                 END cc, -- completed courses
                 CASE
                 WHEN crse.final_grade IS NOT NULL THEN
                  listagg(DISTINCT regexp_replace(crse.course, '([A-Z]+)([0-9]+)', '\1 \2') || ' (' || crse.final_grade || ')', ' | ') within GROUP(ORDER BY crse.course)
                 END ccg -- completed course grades
                 FROM base
                 JOIN smrprle prle
                   ON prle.smrprle_program = base.program
                 LEFT JOIN mgpa
                   ON mgpa.pidm = base.pidm
                  AND mgpa.blck_code = base.program
                  AND mgpa.term_code = base.term_code
                 LEFT JOIN utl_d_aim.szrcrse crse
                   ON crse.pidm = base.pidm
                  AND crse.term_code <= base.term_code
                     --  and crse.credit_hr > .01
                  AND crse.levl_code = base.level_code
                  AND crse.course IN (SELECT course FROM courses WHERE courses.school = 'SOWK') -- lucom isnt limiting on courses
                 LEFT JOIN zexec.zsavaddr addr
                   ON addr.pidm = base.pidm
                  AND addr.atyp_code = 'MA'
                  AND addr.addr_type_rank = 1
                 LEFT JOIN zexec.zsavaddr resi
                   ON resi.pidm = base.pidm
                  AND resi.atyp_code = 'LP'
                  AND resi.addr_type_rank = 1
                 LEFT JOIN spremrg emer
                   ON emer.spremrg_pidm = base.pidm -- emergency contact info
                  AND emer.spremrg_priority = 1
                 LEFT JOIN stvterm t
                   ON t.stvterm_code = base.ctlg_term_1
                 LEFT JOIN shrdgmr gmr
                   ON gmr.shrdgmr_pidm = base.pidm
                  AND gmr.shrdgmr_program = base.program
                  AND gmr.shrdgmr_levl_code = base.level_code -- grad year, if no grad year use exp grad date default
                  AND gmr.shrdgmr_term_code_grad >= (SELECT term FROM termcode) -- graduating this sem or in the future
                GROUP BY base.pidm,
                          base.luid,
                          base.fname,
                          base.lname,
                          base.lu_email,
                          base.alt_email,
                          base.term_code,
                          base.phone,
                          base.program,
                          base.campus,
                          CASE
                          WHEN t.stvterm_code <= '199930' THEN
                           '19' || substr(t.stvterm_fa_proc_yr, 1, 2) || '-' || '19' || substr(t.stvterm_fa_proc_yr, 3, 4)
                          WHEN t.stvterm_code IN ('199940', '200020') THEN
                           '19' || substr(t.stvterm_fa_proc_yr, 1, 2) || '-' || '20' || substr(t.stvterm_fa_proc_yr, 3, 4)
                          WHEN t.stvterm_code >= '200020' THEN
                           '20' || substr(t.stvterm_fa_proc_yr, 1, 2) || '-' || '20' || substr(t.stvterm_fa_proc_yr, 3, 4)
                          END,
                          CASE
                          WHEN base.classification = '1_Freshman' THEN
                           'Freshman'
                          WHEN base.classification = '2_Sophomore' THEN
                           'Sophomore'
                          WHEN base.classification = '3_Junior' THEN
                           'Junior'
                          WHEN base.classification = '4_Senior' THEN
                           'Senior'
                          ELSE
                           base.classification
                          END,
                          base.overall_gpa,
                          mgpa.major_gpa,
                          base.hrs_remaining,
                          gmr.shrdgmr_acyr_code,
                          CASE
                          WHEN base.campus = 'R' THEN
                           'CVA'
                          ELSE
                           'OCVA'
                          END,
                          nvl(addr.street_line1, resi.street_line1),
                          nvl(addr.street_line2, resi.street_line2),
                          nvl(addr.city, resi.city),
                          nvl(addr.stat_code, resi.stat_code),
                          nvl(addr.zip5, resi.zip5),
                          nvl(addr.natn_code, resi.natn_code),
                          resi.stat_code,
                          CASE
                          WHEN (lower(emer.spremrg_first_name) = 'unknown' OR lower(emer.spremrg_last_name) = 'unknown') THEN
                           NULL
                          ELSE
                           emer.spremrg_first_name || ' ' || emer.spremrg_last_name
                          END,
                          CASE
                          WHEN length(regexp_replace(emer.spremrg_phone_number, '[^0-9]')) = 7
                               AND length(emer.spremrg_phone_area) = 3 THEN
                           emer.spremrg_phone_area || regexp_replace(emer.spremrg_phone_number, '[^0-9]')
                          WHEN length(regexp_replace(emer.spremrg_phone_number, '[^0-9]')) = 10 THEN
                           regexp_replace(emer.spremrg_phone_number, '[^0-9]')
                          WHEN length(emer.spremrg_phone_area) = 3
                               AND length(regexp_replace(emer.spremrg_phone_number, '[^0-9]')) = 3
                               AND length(emer.spremrg_phone_ext) = 4 THEN
                           emer.spremrg_phone_area || regexp_replace(emer.spremrg_phone_number, '[^0-9]') || emer.spremrg_phone_ext
                          ELSE
                           NULL
                          END,
                          crse.final_grade)
SELECT mainquery.pidm || mainquery.enrl_term unique_key,
       mainquery.pidm,
       mainquery.luid,
       mainquery.firstname,
       mainquery.lastname,
       mainquery.enrl_term,
       mainquery.email,
       mainquery.alt_email,
       mainquery.phone,
       mainquery.program,
       mainquery.campus, -- program campus code
       mainquery.dcp_year, -- dcp_year
       mainquery.classification,
       mainquery.overall_gpa, -- overall gpa
       mainquery.majorgpa, -- major gpa
       mainquery.credit_hrs_remaining, -- credit hours remaining
       mainquery.grad_year,
       mainquery.location_code,
       mainquery.address1,
       mainquery.address2,
       mainquery.city,
       mainquery.state,
       mainquery.zip,
       mainquery.country,
       mainquery.stat_code state_code,
       mainquery.e_contact emergency_contact,
       mainquery.e_contact_num emergency_contact_number, -- emergency contact number
       MAX(mainquery.ec) enrolled_courses, -- enrolled courses
       MAX(mainquery.cc) completed_courses, -- completed courses
       MAX(mainquery.ccg) completed_course_grades -- completed course grades
  FROM mainquery
 GROUP BY mainquery.pidm || mainquery.enrl_term,
mainquery.pidm,
mainquery.luid,
mainquery.firstname,
mainquery.lastname,
mainquery.enrl_term,
mainquery.email,
mainquery.alt_email,
mainquery.phone,
mainquery.program,
mainquery.campus,
mainquery.dcp_year,
mainquery.classification,
mainquery.overall_gpa,
mainquery.majorgpa,
mainquery.credit_hrs_remaining,
mainquery.grad_year,
mainquery.location_code,
mainquery.address1,
mainquery.address2,
mainquery.city,
mainquery.state,
mainquery.zip,
mainquery.country,
mainquery.stat_code,
mainquery.e_contact,
mainquery.e_contact_num) new_rec
  LEFT JOIN utl_d_aa.core_sowk_elms existing_rec
    ON existing_rec.unique_key = new_rec.unique_key
   AND existing_rec.to_date = to_date('12/31/2099', 'MM/DD/YYYY')
 WHERE existing_rec.unique_key IS NULL -- new record
      -- using nvls to find any changes for student record
    OR (coalesce(existing_rec.luid, 'XXXXXX') != coalesce(new_rec.luid, 'XXXXXX') OR coalesce(existing_rec.firstname, 'XXXXXX') != coalesce(new_rec.firstname, 'XXXXXX') OR
       coalesce(existing_rec.lastname, 'XXXXXX') != coalesce(new_rec.lastname, 'XXXXXX') OR coalesce(existing_rec.email, 'XXXXXX') != coalesce(new_rec.email, 'XXXXXX') OR
       coalesce(existing_rec.alt_email, 'XXXXXX') != coalesce(new_rec.alt_email, 'XXXXXX') OR coalesce(existing_rec.phone, 'XXXXXX') != coalesce(new_rec.phone, 'XXXXXX') OR
       coalesce(existing_rec.program, 'XXXXXX') != coalesce(new_rec.program, 'XXXXXX') OR coalesce(existing_rec.campus, 'XXXXXX') != coalesce(new_rec.campus, 'XXXXXX') OR
       coalesce(existing_rec.dcp_year, 'XXXXXX') != coalesce(new_rec.dcp_year, 'XXXXXX') OR coalesce(existing_rec.classification, 'XXXXXX') != coalesce(new_rec.classification, 'XXXXXX') OR
       coalesce(existing_rec.overall_gpa, 999999) != coalesce(new_rec.overall_gpa, 999999) OR coalesce(existing_rec.majorgpa, 999999) != coalesce(new_rec.majorgpa, 999999) OR
       coalesce(existing_rec.credit_hrs_remaining, 999999) != coalesce(new_rec.credit_hrs_remaining, 999999) OR coalesce(existing_rec.grad_year, 999999) != coalesce(new_rec.grad_year, 999999) OR
       coalesce(existing_rec.location_code, 'XXXXXX') != coalesce(new_rec.location_code, 'XXXXXX') OR coalesce(existing_rec.address1, 'XXXXXX') != coalesce(new_rec.address1, 'XXXXXX') OR
       coalesce(existing_rec.address2, 'XXXXXX') != coalesce(new_rec.address2, 'XXXXXX') OR coalesce(existing_rec.city, 'XXXXXX') != coalesce(new_rec.city, 'XXXXXX') OR
       coalesce(existing_rec.state, 'XXXXXX') != coalesce(new_rec.state, 'XXXXXX') OR coalesce(existing_rec.zip, 'XXXXXX') != coalesce(new_rec.zip, 'XXXXXX') OR
       coalesce(existing_rec.country, 'XXXXXX') != coalesce(new_rec.country, 'XXXXXX') OR coalesce(existing_rec.state_code, 'XXXXXX') != coalesce(new_rec.state_code, 'XXXXXX') OR
       coalesce(existing_rec.emergency_contact, 'XXXXXX') != coalesce(new_rec.emergency_contact, 'XXXXXX') OR coalesce(existing_rec.emergency_contact_number, 'XXXXXX') != coalesce(new_rec.emergency_contact_number, 'XXXXXX') OR
       coalesce(existing_rec.enrolled_courses, 'XXXXXX') != coalesce(new_rec.enrolled_courses, 'XXXXXX') OR coalesce(existing_rec.completed_courses, 'XXXXXX') != coalesce(new_rec.completed_courses, 'XXXXXX') OR
       coalesce(existing_rec.completed_course_grades, 'XXXXXX') != coalesce(new_rec.completed_course_grades, 'XXXXXX'));

TYPE rec_input_t IS TABLE OF curs%ROWTYPE;
rec_input rec_input_t;
TYPE index_pointer_t IS TABLE OF PLS_INTEGER;
ttab_dml index_pointer_t := index_pointer_t();
CURSOR cur_idx_dat(schema_ VARCHAR2,
                   table_  VARCHAR2) IS(
SELECT lower(a_idx.owner || '.' || a_idx.index_name) idx
  FROM all_indexes a_idx
 WHERE a_idx.owner = upper(schema_)
   AND a_idx.table_name = upper(table_));
rec_idx_dat cur_idx_dat%ROWTYPE;
TYPE index_pointer_i IS TABLE OF PLS_INTEGER;
insert_dml index_pointer_i := index_pointer_i();
TYPE index_pointer_u IS TABLE OF PLS_INTEGER;
update_dml index_pointer_u := index_pointer_u();
TYPE index_pointer_d IS TABLE OF PLS_INTEGER;
delete_dml   index_pointer_d := index_pointer_d();
start_time   TIMESTAMP;
end_time     TIMESTAMP;
select_count NUMBER := 0;
insert_count NUMBER := 0;
update_count NUMBER := 0;
delete_count NUMBER := 0;
start_t      DATE := SYSDATE;
elapsed      NUMBER := 0;
BEGIN
-- dbms_output.enable(buffer_size => NULL);
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
--
OPEN curs;
LOOP
v_count   := 0; -- reset count
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ALL' || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
FETCH curs BULK COLLECT
INTO rec_input LIMIT v_row_max;
IF rec_input.count = 0 THEN
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'SELECT - ALL' || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
RETURN;
ELSIF rec_input.count > 0 THEN
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'SELECT - ALL' || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
insert_dml := index_pointer_i();
update_dml := index_pointer_u();
FOR idx IN rec_input.first .. rec_input.last
LOOP
v_count := rec_input(idx).total_rows;
IF rec_input(idx).control_state = 'CHANGE' THEN
-- UPDATE HAS TO HAPPEN FIRST TO EXPIRE RECORDS THAT ALREADY EXIST
update_dml.extend;
update_dml(update_dml.last) := idx;
END IF;
IF rec_input(idx).control_state IN ('NEW', 'CHANGE') THEN
-- ALL NEW RECS OR CHANGES GET INSERTED
insert_dml.extend;
insert_dml(insert_dml.last) := idx;
END IF;
END LOOP;
update_count := update_count + update_dml.count;
insert_count := insert_count + insert_dml.count;
-- DML UPDATES
FORALL i IN VALUES OF update_dml
UPDATE utl_d_aa.core_sowk_elms tab
   SET tab.to_date  = v_end_date,
     tab.activity_date = v_etl_date
 WHERE tab.unique_key = rec_input(i).unique_key
   AND tab.to_date = to_date('12/31/2099', 'MM/DD/YYYY');
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'UPDATE - ALL' || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- DML Inserts
FORALL i IN VALUES OF insert_dml
INSERT INTO utl_d_aa.core_sowk_elms tab
(unique_key,from_date,to_date,activity_date,
 pidm,
 luid,
 firstname,
 lastname,
 enrl_term,
 email,
 alt_email,
 phone,
 program,
 campus,
 dcp_year,
 classification,
 overall_gpa,
 majorgpa,
 credit_hrs_remaining,
 grad_year,
 location_code,
 address1,
 address2,
 city,
 state,
 zip,
 country,
 state_code,
 emergency_contact,
 emergency_contact_number,
 enrolled_courses,
 completed_courses,
 completed_course_grades)
VALUES
(rec_input(i).unique_key,v_etl_date,to_date('12/31/2099', 'MM/DD/YYYY'),v_etl_date,
 rec_input(i).pidm,
 rec_input(i).luid,
 rec_input(i).firstname,
 rec_input(i).lastname,
 rec_input(i).enrl_term,
 rec_input(i).email,
 rec_input(i).alt_email,
 rec_input(i).phone,
 rec_input(i).program,
 rec_input(i).campus,
 rec_input(i).dcp_year,
 rec_input(i).classification,
 rec_input(i).overall_gpa,
 rec_input(i).majorgpa,
 rec_input(i).credit_hrs_remaining,
 rec_input(i).grad_year,
 rec_input(i).location_code,
 rec_input(i).address1,
 rec_input(i).address2,
 rec_input(i).city,
 rec_input(i).state,
 rec_input(i).zip,
 rec_input(i).country,
 rec_input(i).state_code,
 rec_input(i).emergency_contact,
 rec_input(i).emergency_contact_number,
 rec_input(i).enrolled_courses,
 rec_input(i).completed_courses,
 rec_input(i).completed_course_grades);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ALL' || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
END IF;
SELECT ((CAST(SYSDATE AS DATE) - CAST(start_t AS DATE)) * 86400) INTO elapsed FROM dual;
select_count := select_count + rec_input.count;
EXIT WHEN(rec_input.count < v_row_max);
END LOOP;
CLOSE curs;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
-- log any errors
EXCEPTION
WHEN OTHERS THEN
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
/*--------------------------------------------CHANGE LOG----------------------------------------
VERSION  DATE        USERNAME    UPDATES
---      12/11/2024    JWTUCKER1     Initial Release - broke up original ELMS procedure into separate procedures per school for runtime and troubleshooting
---      09/19/2025    JWTUCKER1      Fixed update statement to join on pidm and not unique key, so that past terms do not keep an active record
------------------------------------------------------------------------------------------------*/
END etl_aa_core_sowk_elms;

/*************
COUC
*************/
PROCEDURE etl_aa_core_couc_elms(jobnumber NUMBER, processid VARCHAR2, processname VARCHAR2) IS
/***************************************************
Table: utl_d_aa.core_couc_elms
Primary Keys: NONE
Unique index: unique_key, TO_DATE, FROM_DATE
Purpose:
- Student program and demographic information for students who are currently enrolled in CORE programs
Conditions:
- this will leave historical data on the table, but use the to and from dates to return the latest record
Dependencies: zformdata.zfblist; zformdata.zfrlist; utl_d_aim.szrenrl; zdegree_audit
****************************************************/
--DECLARE
--- PARAMS
v_etl_date    DATE := SYSDATE;
v_end_date    DATE := SYSDATE - 1 / (24 * 60 * 60); -- ONE SEC BEHIND
v_msg         VARCHAR2(255);
v_row_max     NUMBER := 1000000; -- max number of rows to be processed at one time
v_job_id      VARCHAR2(32);
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_cpu         NUMBER := 4; -- number of CPUs used for parallelization - do not exceed 20 CPUs [v_mod x v_cpu] if running simultaneously
v_proc        VARCHAR2(100) := 'etl_aa_core_couc_elms';
v_instance    VARCHAR2(100) := 'ALL'; -- placeholder
v_partition    NUMBER := 0; -- placeholder
-- cursors
CURSOR curs IS
SELECT new_rec.*,
       CASE
       WHEN existing_rec.unique_key IS NULL THEN
        'NEW'
       WHEN existing_rec.unique_key IS NOT NULL THEN
        'CHANGE'
       END AS control_state, -- we are NOT deleting - EVER!
       COUNT(*) over() total_rows
  FROM (WITH termcode AS (SELECT MAX(term_code) AS term -- current term
                            FROM zbtm.terms_by_group_v
                           WHERE group_code = 'STD'
                             AND semester != 'WIN'
                             AND start_date <= SYSDATE), --
       course_list AS (SELECT /*+ materialize */
                        l.zfrlist_char_01,
                        l.zfrlist_char_02,
                        l.zfrlist_char_03 courselist
                         FROM zformdata.zfblist b
                         JOIN zformdata.zfrlist l
                           ON l.zfrlist_list_code = b.zfblist_code
                          AND l.zfrlist_active_yn = 'Y'
                        WHERE b.zfblist_code = 'CORE_ELMS_COURSELIST'
                          AND l.zfrlist_char_01 IN ('COUC')), --
       program_list AS (SELECT /*+ materialize */
                         l2.zfrlist_char_01 progschool, -- list of programs for core elms feeds
                         l2.zfrlist_char_02 progterm,
                         l2.zfrlist_char_03 proglist
                          FROM zformdata.zfblist b2
                          JOIN zformdata.zfrlist l2
                            ON l2.zfrlist_list_code = b2.zfblist_code
                           AND l2.zfrlist_active_yn = 'Y'
                           AND l2.zfrlist_char_01 = 'COUC'
                         WHERE b2.zfblist_code = 'CORE_ELMS_PROGRAMS'), --
       courses AS (SELECT /*+ materialize*/
                    t.zfrlist_char_01 school,
                    t.zfrlist_char_02 term,
                    TRIM(regexp_substr(REPLACE(t.courselist, '&', ','), '[^,]+', 1, LEVEL)) course -- breaking out courses from general list
                     FROM course_list t -- bringing in normal and internship/practicum courses
                   CONNECT BY PRIOR dbms_random.value IS NOT NULL
                          AND PRIOR t.zfrlist_char_01 = t.zfrlist_char_01
                          AND PRIOR t.zfrlist_char_02 = t.zfrlist_char_02
                          AND LEVEL <= regexp_count(REPLACE(t.courselist, '&', ','), ',') + 1),
       programs AS (SELECT /*+ materialize*/
                     t2.progschool pgschool,
                     t2.progterm pgterm,
                     TRIM(regexp_substr(REPLACE(t2.proglist, '&', ','), '[^,]+', 1, LEVEL)) pglist -- breaking out programs similar to courses
                      FROM program_list t2
                    CONNECT BY PRIOR dbms_random.value IS NOT NULL
                           AND PRIOR t2.progschool = t2.progschool
                           AND PRIOR t2.progterm = t2.progterm
                           AND LEVEL <= regexp_count(REPLACE(t2.proglist, '&', ','), ',') + 1), --
       base AS (SELECT /*+ materialize */
                 enrl.pidm,
                 enrl.first_name fname,
                 enrl.last_name lname,
                 enrl.luid,
                 enrl.lu_email lu_email,
                 enrl.alt_email,
                 nvl(enrl.phone_text, enrl.phone) phone,
                 enrl.camp_code campus,
                 enrl.ipeds_ethn,
                 enrl.gender gender,
                 enrl.term_code,
                 enrl.prog_code_1 program,
                 enrl.levl_code level_code,
                 enrl.cum_gpa overall_gpa,
                 enrl.hrs_remaining,
                 enrl.classification,
                 enrl.ctlg_term_1
                  FROM utl_d_aim.szrenrl enrl
                  JOIN zsaturn.szrlevl levl
                    ON levl.szrlevl_levl_code = enrl.levl_code -- instead of hardcoded values, limiting in base pop
                   AND levl.szrlevl_is_univ = 'Y'
                   AND levl.szrlevl_has_awardable_cred = 'Y'
                 WHERE 1 = 1
                   AND enrl.term_code >= (SELECT term FROM termcode)
                   AND enrl.prog_code_1 IN (SELECT pglist FROM programs) -- in case of program use (will change to genlist when the custom tables are made)
                ), --
       mgpa AS (SELECT /*+ materialize */
                 v.pidm pidm,
                 b.blck_code blck_code,
                 v.audit_term term_code,
                 trunc(SUM(shrgrde.shrgrde_quality_points * cc.credit_hr) / nullif(SUM(cc.credit_hr), 0), 4) major_gpa
                  FROM base b
                  JOIN zdegree_audit.davaudit v
                    ON v.pidm = b.pidm
                   AND v.whatif_prog_ind = 'N'
                   AND v.current_ind = 'Y'
                   AND v.audit_term >= (SELECT term FROM termcode)
                  JOIN zdegree_audit.daaudit a
                    ON a.davaudit_id = v.davaudit_id
                   AND a.req_met_rule_use_ind = 'Y'
                   AND a.blck_code = b.program
                  JOIN zdegree_audit.davblocks b
                    ON b.blck_code = a.blck_code
                   AND b.majr_blck_ind = 'Y'
                  JOIN zdegree_audit.dacrsehist c
                    ON c.davaudit_id = v.davaudit_id
                   AND c.pseudo_eqiv_course_ind = 'N'
                   AND c.test_code_ind = 'N'
                   AND c.transfer_ind = 'N'
                   AND c.inprogress_ind = 'N'
                  JOIN zdegree_audit.dacrsehistused u
                    ON u.dacrsehist_id = c.id
                   AND u.davaudit_id = v.davaudit_id
                   AND u.used_daaudit_id = a.dacrserules_id
                  JOIN utl_d_aim.szrcrse cc
                    ON cc.pidm = v.pidm
                   AND cc.term_code = v.audit_term
                  JOIN saturn.shrgrde shrgrde
                    ON shrgrde.shrgrde_code = cc.final_grade
                   AND shrgrde.shrgrde_levl_code = cc.levl_code
                   AND shrgrde.shrgrde_gpa_ind = 'Y'
                   AND shrgrde.shrgrde_term_code_effective = (SELECT MAX(shrgrde2.shrgrde_term_code_effective)
                                                                FROM saturn.shrgrde shrgrde2
                                                               WHERE shrgrde.shrgrde_code = shrgrde2.shrgrde_code
                                                                 AND shrgrde.shrgrde_levl_code = shrgrde2.shrgrde_levl_code)
                 GROUP BY v.pidm,
                          v.audit_term,
                          b.blck_code), --
       mainquery AS (
                     -- using this query for left joins for query speed (to bring in data that could be null)
                     SELECT /*+ materialize */
                       case when base.program = 'ADCN-MA-D' then 'ADCN'
                            when base.program = 'MFTP-MMFT-D' then 'MMFT'
                            when base.program in ('MESC-MED-D','MECU-MED-D','MSCL-MED-D','SHCO-MED-D') then 'SC'
                            when base.program = 'DCED-PHD-D' then 'PhD'
                            when base.program in ('CMHC-MA-D','CMHC-MA-R') then 'CMHC' end program_group,
                       base.pidm,
                       base.luid luid,
                       base.fname firstname,
                       base.lname lastname,
                       base.lu_email email,
                       base.alt_email,
                       base.term_code enrl_term,
                       base.phone phone,
                       CASE
                       WHEN base.ipeds_ethn = 'American_Indian_Alaska_Native' THEN
                        'American Indian Alaska Native'
                       WHEN base.ipeds_ethn = 'Asian' THEN
                        'Asian'
                       WHEN base.ipeds_ethn = 'Black_or_African_American' THEN
                        'Black or African American'
                       WHEN base.ipeds_ethn = 'Hispanic_Latino' THEN
                        'Hispanic Latino'
                       WHEN base.ipeds_ethn = 'Native_Hawaiian_Pacific_Islander' THEN
                        'Native Hawaiian Pacific Islander'
                       WHEN base.ipeds_ethn = 'Nonresident_Alien' THEN
                        'Nonresident Alien'
                       WHEN base.ipeds_ethn = 'Two_or_more_races' THEN
                        'Two or more races'
                       WHEN base.ipeds_ethn = 'Unreported' THEN
                        'Unreported'
                       WHEN base.ipeds_ethn = 'White' THEN
                        'White'
                       END ethnicity,
                       base.gender,
                       base.program,
                       base.campus, -- program campus code
                       CASE
                       WHEN t.stvterm_code <= '199930' THEN
                        '19' || substr(t.stvterm_fa_proc_yr, 1, 2) || '-' || '19' || substr(t.stvterm_fa_proc_yr, 3, 4)
                       WHEN t.stvterm_code IN ('199940', '200020') THEN
                        '19' || substr(t.stvterm_fa_proc_yr, 1, 2) || '-' || '20' || substr(t.stvterm_fa_proc_yr, 3, 4)
                       WHEN t.stvterm_code >= '200020' THEN
                        '20' || substr(t.stvterm_fa_proc_yr, 1, 2) || '-' || '20' || substr(t.stvterm_fa_proc_yr, 3, 4)
                       END dcp_year, -- dcp_year
                       CASE
                       WHEN base.classification = '1_Freshman' THEN
                        'Freshman'
                       WHEN base.classification = '2_Sophomore' THEN
                        'Sophomore'
                       WHEN base.classification = '3_Junior' THEN
                        'Junior'
                       WHEN base.classification = '4_Senior' THEN
                        'Senior'
                       ELSE
                        base.classification
                       END classification,
                       base.overall_gpa, -- overall gpa
                       mgpa.major_gpa majorgpa, -- major gpa
                       base.hrs_remaining credit_hrs_remaining, -- credit hours remaining
                       coalesce(to_number(MAX(gmr.shrdgmr_acyr_code)), (SELECT to_number(substr(term, 0, 4)) + 2 FROM termcode)) grad_year, -- sgbstdn exp grad date was tanking runtime and innacurate, creating a default + 2 years exp grad year
                       'L' location_code,
                       nvl(addr.street_line1, resi.street_line1) address1,
                       nvl(addr.street_line2, resi.street_line2) address2,
                       nvl(addr.city, resi.city) city,
                       nvl(addr.stat_code, resi.stat_code) state,
                       nvl(addr.zip5, resi.zip5) zip,
                       nvl(addr.natn_code, resi.natn_code) country,
                       resi.stat_code,
                       CASE
                       WHEN (lower(emer.spremrg_first_name) = 'unknown' OR lower(emer.spremrg_last_name) = 'unknown') THEN
                        NULL
                       ELSE
                        emer.spremrg_first_name || ' ' || emer.spremrg_last_name
                       END e_contact,
                       CASE
                       WHEN length(regexp_replace(emer.spremrg_phone_number, '[^0-9]')) = 7
                            AND length(emer.spremrg_phone_area) = 3 THEN
                        emer.spremrg_phone_area || regexp_replace(emer.spremrg_phone_number, '[^0-9]')
                       WHEN length(regexp_replace(emer.spremrg_phone_number, '[^0-9]')) = 10 THEN
                        regexp_replace(emer.spremrg_phone_number, '[^0-9]')
                       WHEN length(emer.spremrg_phone_area) = 3
                            AND length(regexp_replace(emer.spremrg_phone_number, '[^0-9]')) = 3
                            AND length(emer.spremrg_phone_ext) = 4 THEN
                        emer.spremrg_phone_area || regexp_replace(emer.spremrg_phone_number, '[^0-9]') || emer.spremrg_phone_ext
                       ELSE
                        NULL
                       END e_contact_num, -- emergency contact number
                       CASE
                       WHEN crse.final_grade IS NULL THEN
                        listagg(DISTINCT regexp_replace(crse.course, '([A-Z]+)([0-9]+)', '\1 \2'), ' | ') within GROUP(ORDER BY crse.course)
                       END ec, -- enrolled courses
                       CASE
                       WHEN crse.final_grade IS NOT NULL THEN
                        listagg(DISTINCT regexp_replace(crse.course, '([A-Z]+)([0-9]+)', '\1 \2'), ' | ') within GROUP(ORDER BY crse.course)
                       END cc, -- completed courses
                       CASE
                       WHEN crse.final_grade IS NOT NULL THEN
                        listagg(DISTINCT regexp_replace(crse.course, '([A-Z]+)([0-9]+)', '\1 \2') || ' (' || crse.final_grade || ')', ' | ') within GROUP(ORDER BY crse.course)
                       END ccg -- completed course grades
                       FROM base
                       LEFT JOIN mgpa
                         ON mgpa.pidm = base.pidm
                        AND mgpa.blck_code = base.program
                        AND mgpa.term_code = base.term_code
                       LEFT JOIN utl_d_aim.szrcrse crse
                         ON crse.pidm = base.pidm
                        AND crse.term_code <= base.term_code
                           --  and crse.credit_hr > .01
                        AND crse.levl_code = base.level_code
                        AND crse.course IN (SELECT course FROM courses WHERE courses.school = 'COUC') -- lucom isnt limiting on courses
                       LEFT JOIN zexec.zsavaddr addr
                         ON addr.pidm = base.pidm
                        AND addr.atyp_code = 'MA'
                        AND addr.addr_type_rank = 1
                       LEFT JOIN zexec.zsavaddr resi
                         ON resi.pidm = base.pidm
                        AND resi.atyp_code = 'LP'
                        AND resi.addr_type_rank = 1
                       LEFT JOIN spremrg emer
                         ON emer.spremrg_pidm = base.pidm -- emergency contact info
                        AND emer.spremrg_priority = 1
                       LEFT JOIN stvterm t
                         ON t.stvterm_code = base.ctlg_term_1
                       LEFT JOIN shrdgmr gmr
                         ON gmr.shrdgmr_pidm = base.pidm
                        AND gmr.shrdgmr_program = base.program
                        AND gmr.shrdgmr_levl_code = base.level_code -- grad year, if no grad year use exp grad date
                        AND gmr.shrdgmr_term_code_grad >= (SELECT term FROM termcode) --------------------------
                      GROUP BY  case when base.program = 'ADCN-MA-D' then 'ADCN'
                                     when base.program = 'MFTP-MMFT-D' then 'MMFT'
                                     when base.program in ('MESC-MED-D','MECU-MED-D','MSCL-MED-D','SCHO-MED-D','SHCO-MED-D') then 'SC'
                                     when base.program = 'DCED-PHD-D' then 'PhD'
                                     when base.program in ('CMHC-MA-D','CMHC-MA-R') then 'CMHC' end,
                                base.pidm,
                                base.luid,
                                base.fname,
                                base.lname,
                                base.lu_email,
                                base.alt_email,
                                base.term_code,
                                base.phone,
                                CASE
                                WHEN base.ipeds_ethn = 'American_Indian_Alaska_Native' THEN
                                 'American Indian Alaska Native'
                                WHEN base.ipeds_ethn = 'Asian' THEN
                                 'Asian'
                                WHEN base.ipeds_ethn = 'Black_or_African_American' THEN
                                 'Black or African American'
                                WHEN base.ipeds_ethn = 'Hispanic_Latino' THEN
                                 'Hispanic Latino'
                                WHEN base.ipeds_ethn = 'Native_Hawaiian_Pacific_Islander' THEN
                                 'Native Hawaiian Pacific Islander'
                                WHEN base.ipeds_ethn = 'Nonresident_Alien' THEN
                                 'Nonresident Alien'
                                WHEN base.ipeds_ethn = 'Two_or_more_races' THEN
                                 'Two or more races'
                                WHEN base.ipeds_ethn = 'Unreported' THEN
                                 'Unreported'
                                WHEN base.ipeds_ethn = 'White' THEN
                                 'White'
                                END,
                                base.gender,
                                base.program,
                                base.campus,
                                CASE
                                WHEN t.stvterm_code <= '199930' THEN
                                 '19' || substr(t.stvterm_fa_proc_yr, 1, 2) || '-' || '19' || substr(t.stvterm_fa_proc_yr, 3, 4)
                                WHEN t.stvterm_code IN ('199940', '200020') THEN
                                 '19' || substr(t.stvterm_fa_proc_yr, 1, 2) || '-' || '20' || substr(t.stvterm_fa_proc_yr, 3, 4)
                                WHEN t.stvterm_code >= '200020' THEN
                                 '20' || substr(t.stvterm_fa_proc_yr, 1, 2) || '-' || '20' || substr(t.stvterm_fa_proc_yr, 3, 4)
                                END,
                                CASE
                                WHEN base.classification = '1_Freshman' THEN
                                 'Freshman'
                                WHEN base.classification = '2_Sophomore' THEN
                                 'Sophomore'
                                WHEN base.classification = '3_Junior' THEN
                                 'Junior'
                                WHEN base.classification = '4_Senior' THEN
                                 'Senior'
                                ELSE
                                 base.classification
                                END,
                                base.overall_gpa,
                                mgpa.major_gpa,
                                base.hrs_remaining,
                                gmr.shrdgmr_acyr_code,
                                'L',
                                nvl(addr.street_line1, resi.street_line1),
                                nvl(addr.street_line2, resi.street_line2),
                                nvl(addr.city, resi.city),
                                nvl(addr.stat_code, resi.stat_code),
                                nvl(addr.zip5, resi.zip5),
                                nvl(addr.natn_code, resi.natn_code),
                                resi.stat_code,
                                CASE
                                WHEN (lower(emer.spremrg_first_name) = 'unknown' OR lower(emer.spremrg_last_name) = 'unknown') THEN
                                 NULL
                                ELSE
                                 emer.spremrg_first_name || ' ' || emer.spremrg_last_name
                                END,
                                CASE
                                WHEN length(regexp_replace(emer.spremrg_phone_number, '[^0-9]')) = 7
                                     AND length(emer.spremrg_phone_area) = 3 THEN
                                 emer.spremrg_phone_area || regexp_replace(emer.spremrg_phone_number, '[^0-9]')
                                WHEN length(regexp_replace(emer.spremrg_phone_number, '[^0-9]')) = 10 THEN
                                 regexp_replace(emer.spremrg_phone_number, '[^0-9]')
                                WHEN length(emer.spremrg_phone_area) = 3
                                     AND length(regexp_replace(emer.spremrg_phone_number, '[^0-9]')) = 3
                                     AND length(emer.spremrg_phone_ext) = 4 THEN
                                 emer.spremrg_phone_area || regexp_replace(emer.spremrg_phone_number, '[^0-9]') || emer.spremrg_phone_ext
                                ELSE
                                 NULL
                                END,
                                crse.final_grade)
    SELECT mainquery.pidm || mainquery.enrl_term unique_key,
              mainquery.program_group,
              mainquery.pidm,
              mainquery.luid,
              mainquery.firstname,
              mainquery.lastname,
              mainquery.enrl_term,
              mainquery.email,
              mainquery.alt_email,
              mainquery.phone,
              mainquery.ethnicity,
              mainquery.gender,
              mainquery.program,
              mainquery.campus, -- program campus code
              mainquery.dcp_year, -- dcp_year
              mainquery.classification,
              mainquery.overall_gpa, -- overall gpa
              mainquery.majorgpa, -- major gpa
              mainquery.credit_hrs_remaining, -- credit hours remaining
              mainquery.grad_year,
              mainquery.location_code,
              mainquery.address1,
              mainquery.address2,
              mainquery.city,
              mainquery.state,
              mainquery.zip,
              mainquery.country,
              mainquery.stat_code state_code,
              mainquery.e_contact emergency_contact,
              mainquery.e_contact_num emergency_contact_number, -- emergency contact number
              MAX(mainquery.ec) enrolled_courses, -- enrolled courses
              MAX(mainquery.cc) completed_courses, -- completed courses
              MAX(mainquery.ccg) completed_course_grades -- completed course grades
         FROM mainquery
        GROUP BY mainquery.pidm || mainquery.enrl_term,
                 mainquery.program_group,
                 mainquery.pidm,
                 mainquery.luid,
                 mainquery.firstname,
                 mainquery.lastname,
                 mainquery.enrl_term,
                 mainquery.email,
                 mainquery.alt_email,
                 mainquery.phone,
                 mainquery.ethnicity,
                 mainquery.gender,
                 mainquery.program,
                 mainquery.campus,
                 mainquery.dcp_year,
                 mainquery.classification,
                 mainquery.overall_gpa,
                 mainquery.majorgpa,
                 mainquery.credit_hrs_remaining,
                 mainquery.grad_year,
                 mainquery.location_code,
                 mainquery.address1,
                 mainquery.address2,
                 mainquery.city,
                 mainquery.state,
                 mainquery.zip,
                 mainquery.country,
                 mainquery.stat_code,
                 mainquery.e_contact,
                 mainquery.e_contact_num) new_rec
         LEFT JOIN utl_d_aa.core_couc_elms existing_rec
           ON existing_rec.unique_key = new_rec.unique_key
          AND existing_rec.to_date = to_date('12/31/2099', 'MM/DD/YYYY')
        WHERE existing_rec.unique_key IS NULL -- new record
             -- using nvls to find any changes for student record
           OR (coalesce(existing_rec.luid, 'XXXXXX') != coalesce(new_rec.luid, 'XXXXXX') OR coalesce(existing_rec.firstname, 'XXXXXX') != coalesce(new_rec.firstname, 'XXXXXX') OR
              coalesce(existing_rec.lastname, 'XXXXXX') != coalesce(new_rec.lastname, 'XXXXXX') OR coalesce(existing_rec.email, 'XXXXXX') != coalesce(new_rec.email, 'XXXXXX') OR
              coalesce(existing_rec.alt_email, 'XXXXXX') != coalesce(new_rec.alt_email, 'XXXXXX') OR coalesce(existing_rec.phone, 'XXXXXX') != coalesce(new_rec.phone, 'XXXXXX') OR
              coalesce(existing_rec.ethnicity, 'XXXXXX') != coalesce(new_rec.ethnicity, 'XXXXXX') OR coalesce(existing_rec.gender, 'XXXXXX') != coalesce(new_rec.gender, 'XXXXXX') OR
              coalesce(existing_rec.program, 'XXXXXX') != coalesce(new_rec.program, 'XXXXXX') OR coalesce(existing_rec.campus, 'XXXXXX') != coalesce(new_rec.campus, 'XXXXXX') OR
              coalesce(existing_rec.dcp_year, 'XXXXXX') != coalesce(new_rec.dcp_year, 'XXXXXX') OR coalesce(existing_rec.classification, 'XXXXXX') != coalesce(new_rec.classification, 'XXXXXX') OR
              coalesce(existing_rec.overall_gpa, 999999) != coalesce(new_rec.overall_gpa, 999999) OR coalesce(existing_rec.majorgpa, 999999) != coalesce(new_rec.majorgpa, 999999) OR
              coalesce(existing_rec.credit_hrs_remaining, 999999) != coalesce(new_rec.credit_hrs_remaining, 999999) OR coalesce(existing_rec.grad_year, 999999) != coalesce(new_rec.grad_year, 999999) OR
              coalesce(existing_rec.location_code, 'XXXXXX') != coalesce(new_rec.location_code, 'XXXXXX') OR coalesce(existing_rec.address1, 'XXXXXX') != coalesce(new_rec.address1, 'XXXXXX') OR
              coalesce(existing_rec.address2, 'XXXXXX') != coalesce(new_rec.address2, 'XXXXXX') OR coalesce(existing_rec.city, 'XXXXXX') != coalesce(new_rec.city, 'XXXXXX') OR
              coalesce(existing_rec.state, 'XXXXXX') != coalesce(new_rec.state, 'XXXXXX') OR coalesce(existing_rec.zip, 'XXXXXX') != coalesce(new_rec.zip, 'XXXXXX') OR
              coalesce(existing_rec.country, 'XXXXXX') != coalesce(new_rec.country, 'XXXXXX') OR coalesce(existing_rec.state_code, 'XXXXXX') != coalesce(new_rec.state_code, 'XXXXXX') OR
              coalesce(existing_rec.emergency_contact, 'XXXXXX') != coalesce(new_rec.emergency_contact, 'XXXXXX') OR coalesce(existing_rec.emergency_contact_number, 'XXXXXX') != coalesce(new_rec.emergency_contact_number, 'XXXXXX') OR
              coalesce(existing_rec.enrolled_courses, 'XXXXXX') != coalesce(new_rec.enrolled_courses, 'XXXXXX') OR coalesce(existing_rec.completed_courses, 'XXXXXX') != coalesce(new_rec.completed_courses, 'XXXXXX') OR
              coalesce(existing_rec.completed_course_grades, 'XXXXXX') != coalesce(new_rec.completed_course_grades, 'XXXXXX'));

TYPE rec_input_t IS TABLE OF curs%ROWTYPE;
rec_input rec_input_t;
TYPE index_pointer_t IS TABLE OF PLS_INTEGER;
ttab_dml index_pointer_t := index_pointer_t();
CURSOR cur_idx_dat(schema_ VARCHAR2,
                   table_  VARCHAR2) IS(
SELECT lower(a_idx.owner || '.' || a_idx.index_name) idx
  FROM all_indexes a_idx
 WHERE a_idx.owner = upper(schema_)
   AND a_idx.table_name = upper(table_));
rec_idx_dat cur_idx_dat%ROWTYPE;
TYPE index_pointer_i IS TABLE OF PLS_INTEGER;
insert_dml index_pointer_i := index_pointer_i();
TYPE index_pointer_u IS TABLE OF PLS_INTEGER;
update_dml index_pointer_u := index_pointer_u();
TYPE index_pointer_d IS TABLE OF PLS_INTEGER;
delete_dml   index_pointer_d := index_pointer_d();
start_time   TIMESTAMP;
end_time     TIMESTAMP;
select_count NUMBER := 0;
insert_count NUMBER := 0;
update_count NUMBER := 0;
delete_count NUMBER := 0;
start_t      DATE := SYSDATE;
elapsed      NUMBER := 0;
BEGIN
-- dbms_output.enable(buffer_size => NULL);
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
--
OPEN curs;
LOOP
v_count   := 0; -- reset count
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ALL' || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
FETCH curs BULK COLLECT
INTO rec_input LIMIT v_row_max;
IF rec_input.count = 0 THEN
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'SELECT - ALL' || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
RETURN;
ELSIF rec_input.count > 0 THEN
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'SELECT - ALL' || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
insert_dml := index_pointer_i();
update_dml := index_pointer_u();
FOR idx IN rec_input.first .. rec_input.last
LOOP
v_count := rec_input(idx).total_rows;
IF rec_input(idx).control_state = 'CHANGE' THEN
-- UPDATE HAS TO HAPPEN FIRST TO EXPIRE RECORDS THAT ALREADY EXIST
update_dml.extend;
update_dml(update_dml.last) := idx;
END IF;
IF rec_input(idx).control_state IN ('NEW', 'CHANGE') THEN
-- ALL NEW RECS OR CHANGES GET INSERTED
insert_dml.extend;
insert_dml(insert_dml.last) := idx;
END IF;
END LOOP;
update_count := update_count + update_dml.count;
insert_count := insert_count + insert_dml.count;
-- DML UPDATES
FORALL i IN VALUES OF update_dml
UPDATE utl_d_aa.core_couc_elms tab
   SET tab.to_date  = v_end_date,
     tab.activity_date = v_etl_date
 WHERE tab.unique_key = rec_input(i).unique_key
   AND tab.to_date = to_date('12/31/2099', 'MM/DD/YYYY');
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'UPDATE - ALL' || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- DML Inserts
FORALL i IN VALUES OF insert_dml
INSERT INTO utl_d_aa.core_couc_elms tab
(unique_key,from_date,to_date,activity_date,
 program_group,
 pidm,
 luid,
 firstname,
 lastname,
 enrl_term,
 email,
 alt_email,
 phone,
 ethnicity,
 gender,
 program,
 campus,
 dcp_year,
 classification,
 overall_gpa,
 majorgpa,
 credit_hrs_remaining,
 grad_year,
 location_code,
 address1,
 address2,
 city,
 state,
 zip,
 country,
 state_code,
 emergency_contact,
 emergency_contact_number,
 enrolled_courses,
 completed_courses,
 completed_course_grades)
VALUES
(rec_input(i).unique_key,v_etl_date,to_date('12/31/2099', 'MM/DD/YYYY'),v_etl_date,
 rec_input(i).program_group,
 rec_input(i).pidm,
 rec_input(i).luid,
 rec_input(i).firstname,
 rec_input(i).lastname,
 rec_input(i).enrl_term,
 rec_input(i).email,
 rec_input(i).alt_email,
 rec_input(i).phone,
 rec_input(i).ethnicity,
 rec_input(i).gender,
 rec_input(i).program,
 rec_input(i).campus,
 rec_input(i).dcp_year,
 rec_input(i).classification,
 rec_input(i).overall_gpa,
 rec_input(i).majorgpa,
 rec_input(i).credit_hrs_remaining,
 rec_input(i).grad_year,
 rec_input(i).location_code,
 rec_input(i).address1,
 rec_input(i).address2,
 rec_input(i).city,
 rec_input(i).state,
 rec_input(i).zip,
 rec_input(i).country,
 rec_input(i).state_code,
 rec_input(i).emergency_contact,
 rec_input(i).emergency_contact_number,
 rec_input(i).enrolled_courses,
 rec_input(i).completed_courses,
 rec_input(i).completed_course_grades);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ALL' || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
END IF;
SELECT ((CAST(SYSDATE AS DATE) - CAST(start_t AS DATE)) * 86400) INTO elapsed FROM dual;
select_count := select_count + rec_input.count;
EXIT WHEN(rec_input.count < v_row_max);
END LOOP;
CLOSE curs;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
-- log any errors
EXCEPTION
WHEN OTHERS THEN
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
/*--------------------------------------------CHANGE LOG----------------------------------------
VERSION  DATE        USERNAME    UPDATES
---      12/11/2024    JWTUCKER1     Initial Release - broke up original ELMS procedure into separate procedures per school for runtime and troubleshooting
---      09/19/2025    JWTUCKER1     Fixed update statement to join on pidm and not unique key, so that past terms do not keep an active record
---      02/26/2026    JWTUCKER1     Added program_group column to help partition file by program for CORE
------------------------------------------------------------------------------------------------*/
END etl_aa_core_couc_elms;

/*************
PSYD
*************/
PROCEDURE etl_aa_core_psyd_elms(jobnumber NUMBER, processid VARCHAR2, processname VARCHAR2) IS
/***************************************************
Table: utl_d_aa.core_psyd_elms
Primary Keys: NONE
Unique index: unique_key, TO_DATE, FROM_DATE
Purpose:
- Student program and demographic information for students who are currently enrolled in CORE programs
Conditions:
- this will leave historical data on the table, but use the to and from dates to return the latest record
Dependencies: zformdata.zfblist; zformdata.zfrlist; utl_d_aim.szrenrl; zdegree_audit
****************************************************/
--DECLARE
--- PARAMS
v_etl_date    DATE := SYSDATE;
v_end_date    DATE := SYSDATE - 1 / (24 * 60 * 60); -- ONE SEC BEHIND
v_msg         VARCHAR2(255);
v_row_max     NUMBER := 1000000; -- max number of rows to be processed at one time
v_job_id      VARCHAR2(32);
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_cpu         NUMBER := 4; -- number of CPUs used for parallelization - do not exceed 20 CPUs [v_mod x v_cpu] if running simultaneously
v_proc        VARCHAR2(100) := 'etl_aa_core_psyd_elms';
v_instance    VARCHAR2(100) := 'ALL'; -- placeholder
v_partition    NUMBER := 0; -- placeholder
-- cursors
CURSOR curs IS
SELECT new_rec.*,
       CASE
       WHEN existing_rec.unique_key IS NULL THEN
        'NEW'
       WHEN existing_rec.unique_key IS NOT NULL THEN
        'CHANGE'
       END AS control_state, -- we are NOT deleting - EVER!
       COUNT(*) over() total_rows
  FROM (WITH termcode AS (SELECT MAX(term_code) AS term -- current term
                            FROM zbtm.terms_by_group_v
                           WHERE group_code = 'STD'
                             AND semester != 'WIN'
                             AND start_date <= SYSDATE) --
      , program_list AS (SELECT /*+ materialize */
                           l2.zfrlist_char_01 progschool, -- list of programs for core elms feeds
                           l2.zfrlist_char_02 progterm,
                           l2.zfrlist_char_03 proglist
                            FROM zformdata.zfblist b2
                            JOIN zformdata.zfrlist l2
                              ON l2.zfrlist_list_code = b2.zfblist_code
                             AND l2.zfrlist_active_yn = 'Y'
                             AND l2.zfrlist_char_01 = 'PSYD'
                           WHERE b2.zfblist_code = 'CORE_ELMS_PROGRAMS'), --
       programs AS (SELECT /*+ materialize*/
                     t2.progschool pgschool,
                     t2.progterm pgterm,
                     TRIM(regexp_substr(REPLACE(t2.proglist, '&', ','), '[^,]+', 1, LEVEL)) pglist -- breaking out programs similar to courses
                      FROM program_list t2
                    CONNECT BY PRIOR dbms_random.value IS NOT NULL
                           AND PRIOR t2.progschool = t2.progschool
                           AND PRIOR t2.progterm = t2.progterm
                           AND LEVEL <= regexp_count(REPLACE(t2.proglist, '&', ','), ',') + 1), --
       base AS (SELECT /*+ materialize */
                 enrl.pidm,
                 enrl.first_name fname,
                 enrl.last_name lname,
                 enrl.luid,
                 enrl.lu_email lu_email,
                 enrl.alt_email,
                 nvl(enrl.phone_text, enrl.phone) phone,
                 enrl.camp_code campus,
                 enrl.term_code,
                 enrl.prog_code_1 program,
                 enrl.levl_code level_code,
                 enrl.cum_gpa overall_gpa,
                 enrl.hrs_remaining,
                 enrl.classification,
                 enrl.ctlg_term_1,
                 enrl.hrs_applied
                  FROM utl_d_aim.szrenrl enrl
                  JOIN zsaturn.szrlevl levl
                    ON levl.szrlevl_levl_code = enrl.levl_code -- instead of hardcoded values, limiting in base pop
                   AND levl.szrlevl_is_univ = 'Y'
                   AND levl.szrlevl_has_awardable_cred = 'Y'
                 WHERE 1 = 1
                   AND enrl.term_code >= (SELECT term FROM termcode)
                   AND enrl.prog_code_1 IN (SELECT pglist FROM programs) -- in case of program use (will change to genlist when the custom tables are made)
                ), --
       mgpa AS (SELECT /*+ materialize */
                 v.pidm pidm,
                 b.blck_code blck_code,
                 v.audit_term term_code,
                 trunc(SUM(shrgrde.shrgrde_quality_points * cc.credit_hr) / nullif(SUM(cc.credit_hr), 0), 4) major_gpa
                  FROM base b
                  JOIN zdegree_audit.davaudit v
                    ON v.pidm = b.pidm
                   AND v.whatif_prog_ind = 'N'
                   AND v.current_ind = 'Y'
                   AND v.audit_term >= (SELECT term FROM termcode)
                  JOIN zdegree_audit.daaudit a
                    ON a.davaudit_id = v.davaudit_id
                   AND a.req_met_rule_use_ind = 'Y'
                   AND a.blck_code = b.program
                  JOIN zdegree_audit.davblocks b
                    ON b.blck_code = a.blck_code
                   AND b.majr_blck_ind = 'Y'
                  JOIN zdegree_audit.dacrsehist c
                    ON c.davaudit_id = v.davaudit_id
                   AND c.pseudo_eqiv_course_ind = 'N'
                   AND c.test_code_ind = 'N'
                   AND c.transfer_ind = 'N'
                   AND c.inprogress_ind = 'N'
                  JOIN zdegree_audit.dacrsehistused u
                    ON u.dacrsehist_id = c.id
                   AND u.davaudit_id = v.davaudit_id
                   AND u.used_daaudit_id = a.dacrserules_id
                  JOIN utl_d_aim.szrcrse cc
                    ON cc.pidm = v.pidm
                   AND cc.term_code = v.audit_term
                  JOIN saturn.shrgrde shrgrde
                    ON shrgrde.shrgrde_code = cc.final_grade
                   AND shrgrde.shrgrde_levl_code = cc.levl_code
                   AND shrgrde.shrgrde_gpa_ind = 'Y'
                   AND shrgrde.shrgrde_term_code_effective = (SELECT MAX(shrgrde2.shrgrde_term_code_effective)
                                                                FROM saturn.shrgrde shrgrde2
                                                               WHERE shrgrde.shrgrde_code = shrgrde2.shrgrde_code
                                                                 AND shrgrde.shrgrde_levl_code = shrgrde2.shrgrde_levl_code)
                 GROUP BY v.pidm,
                          v.audit_term,
                          b.blck_code), --
       mainquery AS (
                     -- using this query for left joins for query speed (to bring in data that could be null)
                     SELECT /*+ materialize */
                      base.pidm,
                       base.luid luid,
                       base.fname firstname,
                       base.lname lastname,
                       base.lu_email email,
                       base.alt_email,
                       base.term_code enrl_term,
                       base.phone phone,
                       base.program,
                       base.campus, -- program campus code
                       CASE
                       WHEN t.stvterm_code <= '199930' THEN
                        '19' || substr(t.stvterm_fa_proc_yr, 1, 2) || '-' || '19' || substr(t.stvterm_fa_proc_yr, 3, 4)
                       WHEN t.stvterm_code IN ('199940', '200020') THEN
                        '19' || substr(t.stvterm_fa_proc_yr, 1, 2) || '-' || '20' || substr(t.stvterm_fa_proc_yr, 3, 4)
                       WHEN t.stvterm_code >= '200020' THEN
                        '20' || substr(t.stvterm_fa_proc_yr, 1, 2) || '-' || '20' || substr(t.stvterm_fa_proc_yr, 3, 4)
                       END dcp_year, -- dcp_year
                       CASE
                       WHEN base.classification = '1_Freshman' THEN
                        'Freshman'
                       WHEN base.classification = '2_Sophomore' THEN
                        'Sophomore'
                       WHEN base.classification = '3_Junior' THEN
                        'Junior'
                       WHEN base.classification = '4_Senior' THEN
                        'Senior'
                       ELSE
                        base.classification
                       END classification,
                       stdn.sgbstdn_term_code_ctlg_1 prog_enrl_term, -- program enroll term
                       CASE
                       WHEN stdn.sgbstdn_term_code_ctlg_1 LIKE '____20' THEN
                        'Spring' || ' ' || substr(stdn.sgbstdn_term_code_ctlg_1, 1, 4)
                       WHEN stdn.sgbstdn_term_code_ctlg_1 LIKE '____30' THEN
                        'Summer' || ' ' || substr(stdn.sgbstdn_term_code_ctlg_1, 1, 4)
                       WHEN stdn.sgbstdn_term_code_ctlg_1 LIKE '____40' THEN
                        'Fall' || ' ' || substr(stdn.sgbstdn_term_code_ctlg_1, 1, 4)
                       END prog_enrl_term_desc,
                       base.overall_gpa, -- overall gpa
                       mgpa.major_gpa majorgpa, -- major gpa
                       base.hrs_remaining credit_hrs_remaining, -- credit hours remaining
                       base.hrs_applied credit_hrs_applied,
                       'L' location_code,
                       nvl(addr.street_line1, resi.street_line1) address1,
                       nvl(addr.street_line2, resi.street_line2) address2,
                       nvl(addr.city, resi.city) city,
                       nvl(addr.stat_code, resi.stat_code) state,
                       nvl(addr.zip5, resi.zip5) zip,
                       nvl(addr.natn_code, resi.natn_code) country,
                       CASE
                       WHEN (lower(emer.spremrg_first_name) = 'unknown' OR lower(emer.spremrg_last_name) = 'unknown') THEN
                        NULL
                       ELSE
                        emer.spremrg_first_name || ' ' || emer.spremrg_last_name
                       END e_contact,
                       CASE
                       WHEN length(regexp_replace(emer.spremrg_phone_number, '[^0-9]')) = 7
                            AND length(emer.spremrg_phone_area) = 3 THEN
                        emer.spremrg_phone_area || regexp_replace(emer.spremrg_phone_number, '[^0-9]')
                       WHEN length(regexp_replace(emer.spremrg_phone_number, '[^0-9]')) = 10 THEN
                        regexp_replace(emer.spremrg_phone_number, '[^0-9]')
                       WHEN length(emer.spremrg_phone_area) = 3
                            AND length(regexp_replace(emer.spremrg_phone_number, '[^0-9]')) = 3
                            AND length(emer.spremrg_phone_ext) = 4 THEN
                        emer.spremrg_phone_area || regexp_replace(emer.spremrg_phone_number, '[^0-9]') || emer.spremrg_phone_ext
                       ELSE
                        NULL
                       END e_contact_num, -- emergency contact number
                       (SELECT COUNT(DISTINCT ca.crn || ca.term_code)
                          FROM utl_d_aim.szrcrse ca
                          JOIN saturn.shrgrde g
                            ON g.shrgrde_code = ca.final_grade
                           AND g.shrgrde_levl_code = ca.levl_code
                           AND g.shrgrde_passed_ind = 'Y'
                           AND g.shrgrde_term_code_effective = (SELECT MAX(bb.shrgrde_term_code_effective)
                                                                  FROM saturn.shrgrde bb
                                                                 WHERE g.shrgrde_code = bb.shrgrde_code
                                                                   AND g.shrgrde_levl_code = bb.shrgrde_levl_code) -- formatting in feed and not etl
                         WHERE ca.pidm = base.pidm
                           AND ca.levl_code = base.level_code) completed_course_count
                       FROM base
                       JOIN sgbstdn stdn
                         ON stdn.sgbstdn_pidm = base.pidm -- for program enrl term and desc
                        AND stdn.sgbstdn_program_1 = base.program
                        AND stdn.sgbstdn_levl_code = base.level_code
                        AND stdn.sgbstdn_term_code_eff = (SELECT MAX(beta.sgbstdn_term_code_eff)
                                                            FROM sgbstdn beta
                                                           WHERE beta.sgbstdn_pidm = stdn.sgbstdn_pidm
                                                             AND beta.sgbstdn_term_code_eff <= base.term_code)
                       LEFT JOIN mgpa
                         ON mgpa.pidm = base.pidm
                        AND mgpa.blck_code = base.program
                        AND mgpa.term_code = base.term_code
                       LEFT JOIN zexec.zsavaddr addr
                         ON addr.pidm = base.pidm
                        AND addr.atyp_code = 'MA'
                        AND addr.addr_type_rank = 1
                       LEFT JOIN zexec.zsavaddr resi
                         ON resi.pidm = base.pidm
                        AND resi.atyp_code = 'LP'
                        AND resi.addr_type_rank = 1
                       LEFT JOIN spremrg emer
                         ON emer.spremrg_pidm = base.pidm -- emergency contact info
                        AND emer.spremrg_priority = 1
                       LEFT JOIN stvterm t
                         ON t.stvterm_code = base.ctlg_term_1
                      GROUP BY base.pidm,
                                base.luid,
                                base.fname,
                                base.lname,
                                base.lu_email,
                                base.alt_email,
                                base.term_code,
                                base.phone,
                                base.program,
                                base.campus,
                                CASE
                                WHEN t.stvterm_code <= '199930' THEN
                                 '19' || substr(t.stvterm_fa_proc_yr, 1, 2) || '-' || '19' || substr(t.stvterm_fa_proc_yr, 3, 4)
                                WHEN t.stvterm_code IN ('199940', '200020') THEN
                                 '19' || substr(t.stvterm_fa_proc_yr, 1, 2) || '-' || '20' || substr(t.stvterm_fa_proc_yr, 3, 4)
                                WHEN t.stvterm_code >= '200020' THEN
                                 '20' || substr(t.stvterm_fa_proc_yr, 1, 2) || '-' || '20' || substr(t.stvterm_fa_proc_yr, 3, 4)
                                END,
                                CASE
                                WHEN base.classification = '1_Freshman' THEN
                                 'Freshman'
                                WHEN base.classification = '2_Sophomore' THEN
                                 'Sophomore'
                                WHEN base.classification = '3_Junior' THEN
                                 'Junior'
                                WHEN base.classification = '4_Senior' THEN
                                 'Senior'
                                ELSE
                                 base.classification
                                END,
                                stdn.sgbstdn_term_code_ctlg_1,
                                CASE
                                WHEN stdn.sgbstdn_term_code_ctlg_1 LIKE '____20' THEN
                                 'Spring' || ' ' || substr(stdn.sgbstdn_term_code_ctlg_1, 1, 4)
                                WHEN stdn.sgbstdn_term_code_ctlg_1 LIKE '____30' THEN
                                 'Summer' || ' ' || substr(stdn.sgbstdn_term_code_ctlg_1, 1, 4)
                                WHEN stdn.sgbstdn_term_code_ctlg_1 LIKE '____40' THEN
                                 'Fall' || ' ' || substr(stdn.sgbstdn_term_code_ctlg_1, 1, 4)
                                END,
                                base.overall_gpa,
                                mgpa.major_gpa,
                                base.hrs_remaining,
                                base.hrs_applied,
                                'L',
                                nvl(addr.street_line1, resi.street_line1),
                                nvl(addr.street_line2, resi.street_line2),
                                nvl(addr.city, resi.city),
                                nvl(addr.stat_code, resi.stat_code),
                                nvl(addr.zip5, resi.zip5),
                                nvl(addr.natn_code, resi.natn_code),
                                resi.stat_code,
                                CASE
                                WHEN (lower(emer.spremrg_first_name) = 'unknown' OR lower(emer.spremrg_last_name) = 'unknown') THEN
                                 NULL
                                ELSE
                                 emer.spremrg_first_name || ' ' || emer.spremrg_last_name
                                END,
                                CASE
                                WHEN length(regexp_replace(emer.spremrg_phone_number, '[^0-9]')) = 7
                                     AND length(emer.spremrg_phone_area) = 3 THEN
                                 emer.spremrg_phone_area || regexp_replace(emer.spremrg_phone_number, '[^0-9]')
                                WHEN length(regexp_replace(emer.spremrg_phone_number, '[^0-9]')) = 10 THEN
                                 regexp_replace(emer.spremrg_phone_number, '[^0-9]')
                                WHEN length(emer.spremrg_phone_area) = 3
                                     AND length(regexp_replace(emer.spremrg_phone_number, '[^0-9]')) = 3
                                     AND length(emer.spremrg_phone_ext) = 4 THEN
                                 emer.spremrg_phone_area || regexp_replace(emer.spremrg_phone_number, '[^0-9]') || emer.spremrg_phone_ext
                                ELSE
                                 NULL
                                END,
                                base.level_code)
       SELECT mainquery.pidm || mainquery.enrl_term unique_key,
              mainquery.pidm,
              mainquery.luid,
              mainquery.firstname,
              mainquery.lastname,
              mainquery.enrl_term,
              mainquery.email,
              mainquery.alt_email,
              mainquery.phone,
              mainquery.program,
              mainquery.campus, -- program campus code
              mainquery.dcp_year, -- dcp_year
              mainquery.prog_enrl_term,
              mainquery.prog_enrl_term_desc,
              mainquery.classification,
              mainquery.overall_gpa, -- overall gpa
              mainquery.majorgpa, -- major gpa
              NULL grad_year, -- psyd sends a null grad year, leaving in in case they want to send eventually (used in the other feeds)
              mainquery.location_code,
              mainquery.address1,
              mainquery.address2,
              mainquery.city,
              mainquery.state,
              mainquery.zip,
              mainquery.country,
              mainquery.e_contact emergency_contact,
              mainquery.e_contact_num emergency_contact_number, -- emergency contact number
              mainquery.completed_course_count, -- rather than enrolled course / completed course columns, psyd does a course count
              mainquery.credit_hrs_applied,
              mainquery.credit_hrs_remaining -- credit hours remaining
         FROM mainquery) new_rec
         LEFT JOIN utl_d_aa.core_psyd_elms existing_rec
           ON existing_rec.unique_key = new_rec.unique_key
          AND existing_rec.to_date = to_date('12/31/2099', 'MM/DD/YYYY')
        WHERE existing_rec.unique_key IS NULL -- new record
             -- using nvls to find any changes for student record
           OR (coalesce(existing_rec.luid, 'XXXXXX') != coalesce(new_rec.luid, 'XXXXXX') OR coalesce(existing_rec.firstname, 'XXXXXX') != coalesce(new_rec.firstname, 'XXXXXX') OR
              coalesce(existing_rec.lastname, 'XXXXXX') != coalesce(new_rec.lastname, 'XXXXXX') OR coalesce(existing_rec.email, 'XXXXXX') != coalesce(new_rec.email, 'XXXXXX') OR
              coalesce(existing_rec.alt_email, 'XXXXXX') != coalesce(new_rec.alt_email, 'XXXXXX') OR coalesce(existing_rec.phone, 'XXXXXX') != coalesce(new_rec.phone, 'XXXXXX') OR
              coalesce(existing_rec.program, 'XXXXXX') != coalesce(new_rec.program, 'XXXXXX') OR coalesce(existing_rec.prog_enrl_term, 'XXXXXX') != coalesce(new_rec.prog_enrl_term, 'XXXXXX') OR
              coalesce(existing_rec.prog_enrl_term_desc, 'XXXXXX') != coalesce(new_rec.prog_enrl_term_desc, 'XXXXXX') OR coalesce(existing_rec.campus, 'XXXXXX') != coalesce(new_rec.campus, 'XXXXXX') OR
              coalesce(existing_rec.dcp_year, 'XXXXXX') != coalesce(new_rec.dcp_year, 'XXXXXX') OR coalesce(existing_rec.classification, 'XXXXXX') != coalesce(new_rec.classification, 'XXXXXX') OR
              coalesce(existing_rec.overall_gpa, 999999) != coalesce(new_rec.overall_gpa, 999999) OR coalesce(existing_rec.majorgpa, 999999) != coalesce(new_rec.majorgpa, 999999) OR
              coalesce(existing_rec.credit_hrs_remaining, 999999) != coalesce(new_rec.credit_hrs_remaining, 999999) OR coalesce(existing_rec.credit_hrs_applied, 999999) != coalesce(new_rec.credit_hrs_applied, 999999) OR
              coalesce(existing_rec.grad_year, 999999) != coalesce(new_rec.grad_year, 999999) OR coalesce(existing_rec.location_code, 'XXXXXX') != coalesce(new_rec.location_code, 'XXXXXX') OR
              coalesce(existing_rec.address1, 'XXXXXX') != coalesce(new_rec.address1, 'XXXXXX') OR coalesce(existing_rec.address2, 'XXXXXX') != coalesce(new_rec.address2, 'XXXXXX') OR
              coalesce(existing_rec.city, 'XXXXXX') != coalesce(new_rec.city, 'XXXXXX') OR coalesce(existing_rec.state, 'XXXXXX') != coalesce(new_rec.state, 'XXXXXX') OR
              coalesce(existing_rec.zip, 'XXXXXX') != coalesce(new_rec.zip, 'XXXXXX') OR coalesce(existing_rec.country, 'XXXXXX') != coalesce(new_rec.country, 'XXXXXX') OR
              coalesce(existing_rec.emergency_contact, 'XXXXXX') != coalesce(new_rec.emergency_contact, 'XXXXXX') OR coalesce(existing_rec.emergency_contact_number, 'XXXXXX') != coalesce(new_rec.emergency_contact_number, 'XXXXXX') OR
              coalesce(to_number(existing_rec.completed_course_count), 999999) != coalesce(to_number(new_rec.completed_course_count), 999999));

TYPE rec_input_t IS TABLE OF curs%ROWTYPE;
rec_input rec_input_t;
TYPE index_pointer_t IS TABLE OF PLS_INTEGER;
ttab_dml index_pointer_t := index_pointer_t();
CURSOR cur_idx_dat(schema_ VARCHAR2,
                   table_  VARCHAR2) IS(
SELECT lower(a_idx.owner || '.' || a_idx.index_name) idx
  FROM all_indexes a_idx
 WHERE a_idx.owner = upper(schema_)
   AND a_idx.table_name = upper(table_));
rec_idx_dat cur_idx_dat%ROWTYPE;
TYPE index_pointer_i IS TABLE OF PLS_INTEGER;
insert_dml index_pointer_i := index_pointer_i();
TYPE index_pointer_u IS TABLE OF PLS_INTEGER;
update_dml index_pointer_u := index_pointer_u();
TYPE index_pointer_d IS TABLE OF PLS_INTEGER;
delete_dml   index_pointer_d := index_pointer_d();
start_time   TIMESTAMP;
end_time     TIMESTAMP;
select_count NUMBER := 0;
insert_count NUMBER := 0;
update_count NUMBER := 0;
delete_count NUMBER := 0;
start_t      DATE := SYSDATE;
elapsed      NUMBER := 0;
BEGIN
-- dbms_output.enable(buffer_size => NULL);
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
--
OPEN curs;
LOOP
v_count   := 0; -- reset count
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ALL' || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
FETCH curs BULK COLLECT
INTO rec_input LIMIT v_row_max;
IF rec_input.count = 0 THEN
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'SELECT - ALL' || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
RETURN;
ELSIF rec_input.count > 0 THEN
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'SELECT - ALL' || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
insert_dml := index_pointer_i();
update_dml := index_pointer_u();
FOR idx IN rec_input.first .. rec_input.last
LOOP
v_count := rec_input(idx).total_rows;
IF rec_input(idx).control_state = 'CHANGE' THEN
-- UPDATE HAS TO HAPPEN FIRST TO EXPIRE RECORDS THAT ALREADY EXIST
update_dml.extend;
update_dml(update_dml.last) := idx;
END IF;
IF rec_input(idx).control_state IN ('NEW', 'CHANGE') THEN
-- ALL NEW RECS OR CHANGES GET INSERTED
insert_dml.extend;
insert_dml(insert_dml.last) := idx;
END IF;
END LOOP;
update_count := update_count + update_dml.count;
insert_count := insert_count + insert_dml.count;
-- DML UPDATES
FORALL i IN VALUES OF update_dml
UPDATE utl_d_aa.core_psyd_elms tab
   SET tab.to_date  = v_end_date,
     tab.activity_date = v_etl_date
 WHERE tab.unique_key = rec_input(i).unique_key
   AND tab.to_date = to_date('12/31/2099', 'MM/DD/YYYY');
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'UPDATE - ALL' || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- DML Inserts
FORALL i IN VALUES OF insert_dml
INSERT INTO utl_d_aa.core_psyd_elms tab
(unique_key,from_date,to_date,activity_date,
 pidm,
 luid,
 firstname,
 lastname,
 enrl_term,
 email,
 alt_email,
 phone,
 program,
 campus,
 dcp_year,
 prog_enrl_term,
 prog_enrl_term_desc,
 classification,
 overall_gpa,
 majorgpa,
 grad_year,
 location_code,
 address1,
 address2,
 city,
 state,
 zip,
 country,
 emergency_contact,
 emergency_contact_number,
 completed_course_count,
 credit_hrs_applied,
 credit_hrs_remaining)
VALUES
(rec_input(i).unique_key,v_etl_date,to_date('12/31/2099', 'MM/DD/YYYY'),v_etl_date,
 rec_input(i).pidm,
 rec_input(i).luid,
 rec_input(i).firstname,
 rec_input(i).lastname,
 rec_input(i).enrl_term,
 rec_input(i).email,
 rec_input(i).alt_email,
 rec_input(i).phone,
 rec_input(i).program,
 rec_input(i).campus,
 rec_input(i).dcp_year,
 rec_input(i).prog_enrl_term,
 rec_input(i).prog_enrl_term_desc,
 rec_input(i).classification,
 rec_input(i).overall_gpa,
 rec_input(i).majorgpa,
 rec_input(i).grad_year,
 rec_input(i).location_code,
 rec_input(i).address1,
 rec_input(i).address2,
 rec_input(i).city,
 rec_input(i).state,
 rec_input(i).zip,
 rec_input(i).country,
 rec_input(i).emergency_contact,
 rec_input(i).emergency_contact_number,
 rec_input(i).completed_course_count,
 rec_input(i).credit_hrs_applied,
 rec_input(i).credit_hrs_remaining);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ALL' || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
END IF;
SELECT ((CAST(SYSDATE AS DATE) - CAST(start_t AS DATE)) * 86400) INTO elapsed FROM dual;
select_count := select_count + rec_input.count;
EXIT WHEN(rec_input.count < v_row_max);
END LOOP;
CLOSE curs;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
-- log any errors
EXCEPTION
WHEN OTHERS THEN
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
/*--------------------------------------------CHANGE LOG----------------------------------------
VERSION  DATE        USERNAME    UPDATES
---      12/11/2024    JWTUCKER1     Initial Release - broke up original ELMS procedure into separate procedures per school for runtime and troubleshooting
---      09/19/2025    JWTUCKER1      Fixed update statement to join on pidm and not unique key, so that past terms do not keep an active record
------------------------------------------------------------------------------------------------*/
END etl_aa_core_psyd_elms;

/*************
LUCOM
*************/
PROCEDURE etl_aa_core_lucom_elms(jobnumber NUMBER, processid VARCHAR2, processname VARCHAR2) IS

/***************************************************
Table: utl_d_aa.core_lucom_elms
Primary Keys: NONE
Unique index: unique_key, TO_DATE, FROM_DATE
Purpose:
- Student program and demographic information for students who are currently enrolled in CORE programs
Conditions:
- this will leave historical data on the table, but use the to and from dates to return the latest record
Dependencies: zformdata.zfblist; zformdata.zfrlist; utl_d_aim.szrenrl; zdegree_audit
****************************************************/
--DECLARE
--- PARAMS
v_etl_date    DATE := SYSDATE;
v_end_date    DATE := SYSDATE - 1 / (24 * 60 * 60); -- ONE SEC BEHIND
v_msg         VARCHAR2(255);
v_row_max     NUMBER := 1000000; -- max number of rows to be processed at one time
v_job_id      VARCHAR2(32);
v_count       NUMBER := 0;
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_cpu         NUMBER := 4; -- number of CPUs used for parallelization - do not exceed 20 CPUs [v_mod x v_cpu] if running simultaneously
v_proc        VARCHAR2(100) := 'etl_aa_core_lucom_elms';
v_instance    VARCHAR2(100) := 'ALL'; -- placeholder
v_partition    NUMBER := 0; -- placeholder
-- cursors
CURSOR curs IS
SELECT new_rec.*,
       CASE
       WHEN existing_rec.unique_key IS NULL THEN
        'NEW'
       WHEN existing_rec.unique_key IS NOT NULL THEN
        'CHANGE'
       END AS control_state, -- we are NOT deleting - EVER!
       COUNT(*) over() total_rows
  FROM (WITH termcode AS (SELECT MAX(term_code) AS term -- current med term
                            FROM zbtm.terms_by_group_v
                           WHERE group_code = 'MED'
                             AND semester != 'WIN'
                             AND start_date <= SYSDATE), --
       base AS (SELECT /*+ materialize */
                 enrl.pidm,
                 enrl.first_name fname,
                 enrl.last_name lname,
                 enrl.luid,
                 enrl.lu_email lu_email,
                 enrl.alt_email,
                 nvl(enrl.phone_text, enrl.phone) phone,
                 enrl.camp_code campus,
                 enrl.ipeds_ethn,
                 enrl.gender gender,
                 enrl.term_code,
                 enrl.prog_code_1 program,
                 enrl.levl_code level_code,
                 enrl.cum_gpa overall_gpa,
                 enrl.hrs_remaining,
                 enrl.classification,
                 enrl.ctlg_term_1,
                 stdn.sgbstdn_exp_grad_date exp_grad_date
                  FROM utl_d_aim.szrenrl enrl
                  join sgbstdn stdn on stdn.sgbstdn_pidm = enrl.pidm
                     and stdn.sgbstdn_program_1 = enrl.prog_code_1
                     and stdn.sgbstdn_term_code_eff = (select max(beta.sgbstdn_term_code_eff)
                                                         from sgbstdn beta
                                                        where beta.sgbstdn_pidm = stdn.sgbstdn_pidm
                                                          and beta.sgbstdn_program_1 = stdn.sgbstdn_program_1
                                                          and beta.sgbstdn_term_code_eff <= enrl.term_code)
                 WHERE 1 = 1
                   AND enrl.term_code >= (SELECT term FROM termcode)
                   AND enrl.levl_code = 'MD' -- LUCOM is limiting based on level code
                ), --
       mgpa AS (SELECT /*+ materialize */
                 v.pidm pidm,
                 b.blck_code blck_code,
                 v.audit_term term_code,
                 trunc(SUM(shrgrde.shrgrde_quality_points * cc.credit_hr) / nullif(SUM(cc.credit_hr), 0), 4) major_gpa
                  FROM base b
                  JOIN zdegree_audit.davaudit v
                    ON v.pidm = b.pidm
                   AND v.whatif_prog_ind = 'N'
                   AND v.current_ind = 'Y'
                   AND v.audit_term >= (SELECT term FROM termcode) ----------------
                  JOIN zdegree_audit.daaudit a
                    ON a.davaudit_id = v.davaudit_id
                   AND a.req_met_rule_use_ind = 'Y'
                   AND a.blck_code = b.program
                  JOIN zdegree_audit.davblocks b
                    ON b.blck_code = a.blck_code
                   AND b.majr_blck_ind = 'Y'
                  JOIN zdegree_audit.dacrsehist c
                    ON c.davaudit_id = v.davaudit_id
                   AND c.pseudo_eqiv_course_ind = 'N'
                   AND c.test_code_ind = 'N'
                   AND c.transfer_ind = 'N'
                   AND c.inprogress_ind = 'N'
                  JOIN zdegree_audit.dacrsehistused u
                    ON u.dacrsehist_id = c.id
                   AND u.davaudit_id = v.davaudit_id
                   AND u.used_daaudit_id = a.dacrserules_id
                  JOIN utl_d_aim.szrcrse cc
                    ON cc.pidm = v.pidm
                   AND cc.term_code = v.audit_term
                  JOIN saturn.shrgrde shrgrde
                    ON shrgrde.shrgrde_code = cc.final_grade
                   AND shrgrde.shrgrde_levl_code = cc.levl_code
                   AND shrgrde.shrgrde_gpa_ind = 'Y'
                   AND shrgrde.shrgrde_term_code_effective = (SELECT MAX(shrgrde2.shrgrde_term_code_effective)
                                                                FROM saturn.shrgrde shrgrde2
                                                               WHERE shrgrde.shrgrde_code = shrgrde2.shrgrde_code
                                                                 AND shrgrde.shrgrde_levl_code = shrgrde2.shrgrde_levl_code)
                 GROUP BY v.pidm,
                          v.audit_term,
                          b.blck_code), --
       mainquery AS (
                     -- using this query for left joins for query speed (to bring in data that could be null)
                     SELECT /*+ materialize */
                      base.pidm,
                       base.luid luid,
                       base.fname firstname,
                       base.lname lastname,
                       base.lu_email email,
                       base.alt_email,
                       base.term_code enrl_term,
                       base.phone phone,
                       CASE
                       WHEN base.ipeds_ethn = 'American_Indian_Alaska_Native' THEN
                        'American Indian Alaska Native'
                       WHEN base.ipeds_ethn = 'Asian' THEN
                        'Asian'
                       WHEN base.ipeds_ethn = 'Black_or_African_American' THEN
                        'Black or African American'
                       WHEN base.ipeds_ethn = 'Hispanic_Latino' THEN
                        'Hispanic Latino'
                       WHEN base.ipeds_ethn = 'Native_Hawaiian_Pacific_Islander' THEN
                        'Native Hawaiian Pacific Islander'
                       WHEN base.ipeds_ethn = 'Nonresident_Alien' THEN
                        'Nonresident Alien'
                       WHEN base.ipeds_ethn = 'Two_or_more_races' THEN
                        'Two or more races'
                       WHEN base.ipeds_ethn = 'Unreported' THEN
                        'Unreported'
                       WHEN base.ipeds_ethn = 'White' THEN
                        'White'
                       END ethnicity,
                       base.gender,
                       base.program,
                       base.campus, -- program campus code
                       CASE
                       WHEN t.stvterm_code <= '199930' THEN
                        '19' || substr(t.stvterm_fa_proc_yr, 1, 2) || '-' || '19' || substr(t.stvterm_fa_proc_yr, 3, 4)
                       WHEN t.stvterm_code IN ('199940', '200020') THEN
                        '19' || substr(t.stvterm_fa_proc_yr, 1, 2) || '-' || '20' || substr(t.stvterm_fa_proc_yr, 3, 4)
                       WHEN t.stvterm_code >= '200020' THEN
                        '20' || substr(t.stvterm_fa_proc_yr, 1, 2) || '-' || '20' || substr(t.stvterm_fa_proc_yr, 3, 4)
                       END dcp_year, -- dcp_year
                       CASE
                       WHEN base.classification = '1_Freshman' THEN
                        'Freshman'
                       WHEN base.classification = '2_Sophomore' THEN
                        'Sophomore'
                       WHEN base.classification = '3_Junior' THEN
                        'Junior'
                       WHEN base.classification = '4_Senior' THEN
                        'Senior'
                       ELSE
                        base.classification
                       END classification,
                       base.overall_gpa, -- overall gpa
                       mgpa.major_gpa majorgpa, -- major gpa
                       base.hrs_remaining credit_hrs_remaining, -- credit hours remaining
                       coalesce(max(to_number(gmr.shrdgmr_acyr_code)),to_number(extract(year from base.exp_grad_date))) grad_year, -- LUCOM manages sgsbstdn grad date so its more accurate than a calculation. They want to use it (other schools didnt)
                       'L' location_code,
                       nvl(addr.street_line1, resi.street_line1) address1,
                       nvl(addr.street_line2, resi.street_line2) address2,
                       nvl(addr.city, resi.city) city,
                       nvl(addr.stat_code, resi.stat_code) state,
                       nvl(addr.zip5, resi.zip5) zip,
                       nvl(addr.natn_code, resi.natn_code) country,
                       resi.stat_code,
                       CASE
                       WHEN (lower(emer.spremrg_first_name) = 'unknown' OR lower(emer.spremrg_last_name) = 'unknown') THEN
                        NULL
                       ELSE
                        emer.spremrg_first_name || ' ' || emer.spremrg_last_name
                       END e_contact,
                       CASE
                       WHEN length(regexp_replace(emer.spremrg_phone_number, '[^0-9]')) = 7
                            AND length(emer.spremrg_phone_area) = 3 THEN
                        emer.spremrg_phone_area || regexp_replace(emer.spremrg_phone_number, '[^0-9]')
                       WHEN length(regexp_replace(emer.spremrg_phone_number, '[^0-9]')) = 10 THEN
                        regexp_replace(emer.spremrg_phone_number, '[^0-9]')
                       WHEN length(emer.spremrg_phone_area) = 3
                            AND length(regexp_replace(emer.spremrg_phone_number, '[^0-9]')) = 3
                            AND length(emer.spremrg_phone_ext) = 4 THEN
                        emer.spremrg_phone_area || regexp_replace(emer.spremrg_phone_number, '[^0-9]') || emer.spremrg_phone_ext
                       ELSE
                        NULL
                       END e_contact_num, -- emergency contact number
                       CASE
                       WHEN crse.final_grade IS NULL
                            AND crse.term_code = base.term_code THEN
                        listagg(DISTINCT regexp_replace(crse.course, '([A-Z]+)([0-9]+)', '\1 \2'), ' | ') within GROUP(ORDER BY crse.course)
                       END ec, -- enrolled courses for lucom
                       CASE
                       WHEN crse.final_grade IS NOT NULL
                            AND crse.term_code = base.term_code THEN
                        listagg(DISTINCT regexp_replace(crse.course, '([A-Z]+)([0-9]+)', '\1 \2'), ' | ') within GROUP(ORDER BY crse.course)
                       END cc, -- completed courses for lucom
                       CASE
                       WHEN crse.final_grade IS NOT NULL
                            AND crse.term_code = base.term_code THEN
                        listagg(DISTINCT regexp_replace(crse.course, '([A-Z]+)([0-9]+)', '\1 \2') || ' (' || crse.final_grade || ')', ' | ') within GROUP(ORDER BY crse.course)
                       END ccg, -- completed course grades for lucom
                       CASE
                       WHEN crse.term_code > base.term_code THEN
                        listagg(DISTINCT regexp_replace(crse.course, '([A-Z]+)([0-9]+)', '\1 \2'), ' | ') within GROUP(ORDER BY crse.course)
                       END rfc -- registered future term courses for lucom
                       FROM base
                       LEFT JOIN mgpa
                         ON mgpa.pidm = base.pidm
                        AND mgpa.blck_code = base.program
                        AND mgpa.term_code = base.term_code
                       LEFT JOIN utl_d_aim.szrcrse crse
                         ON crse.pidm = base.pidm
                        AND crse.levl_code = base.level_code
                        AND crse.term_code >= base.term_code
                     --   and crse.credit_hr > .01 -- lucom isnt limiting on courses, but just checking status of courses in select
                       LEFT JOIN zexec.zsavaddr addr
                         ON addr.pidm = base.pidm
                        AND addr.atyp_code = 'MA'
                        AND addr.addr_type_rank = 1
                       LEFT JOIN zexec.zsavaddr resi
                         ON resi.pidm = base.pidm
                        AND resi.atyp_code = 'LP'
                        AND resi.addr_type_rank = 1
                       LEFT JOIN spremrg emer
                         ON emer.spremrg_pidm = base.pidm -- emergency contact info
                        AND emer.spremrg_priority = 1
                       LEFT JOIN stvterm t
                         ON t.stvterm_code = base.ctlg_term_1
                       LEFT JOIN shrdgmr gmr
                         ON gmr.shrdgmr_pidm = base.pidm
                        AND gmr.shrdgmr_program = base.program
                        AND gmr.shrdgmr_levl_code = base.level_code -- grad year, if no grad year use exp grad date
                        AND gmr.shrdgmr_term_code_grad >= (SELECT term FROM termcode) ------------------------
                      GROUP BY base.pidm,
                                base.luid,
                                base.fname,
                                base.lname,
                                base.lu_email,
                                base.alt_email,
                                base.term_code,
                                base.phone,
                                CASE
                                WHEN base.ipeds_ethn = 'American_Indian_Alaska_Native' THEN
                                 'American Indian Alaska Native'
                                WHEN base.ipeds_ethn = 'Asian' THEN
                                 'Asian'
                                WHEN base.ipeds_ethn = 'Black_or_African_American' THEN
                                 'Black or African American'
                                WHEN base.ipeds_ethn = 'Hispanic_Latino' THEN
                                 'Hispanic Latino'
                                WHEN base.ipeds_ethn = 'Native_Hawaiian_Pacific_Islander' THEN
                                 'Native Hawaiian Pacific Islander'
                                WHEN base.ipeds_ethn = 'Nonresident_Alien' THEN
                                 'Nonresident Alien'
                                WHEN base.ipeds_ethn = 'Two_or_more_races' THEN
                                 'Two or more races'
                                WHEN base.ipeds_ethn = 'Unreported' THEN
                                 'Unreported'
                                WHEN base.ipeds_ethn = 'White' THEN
                                 'White'
                                END,
                                base.gender,
                                base.program,
                                base.campus,
                                CASE
                                WHEN t.stvterm_code <= '199930' THEN
                                 '19' || substr(t.stvterm_fa_proc_yr, 1, 2) || '-' || '19' || substr(t.stvterm_fa_proc_yr, 3, 4)
                                WHEN t.stvterm_code IN ('199940', '200020') THEN
                                 '19' || substr(t.stvterm_fa_proc_yr, 1, 2) || '-' || '20' || substr(t.stvterm_fa_proc_yr, 3, 4)
                                WHEN t.stvterm_code >= '200020' THEN
                                 '20' || substr(t.stvterm_fa_proc_yr, 1, 2) || '-' || '20' || substr(t.stvterm_fa_proc_yr, 3, 4)
                                END,
                                CASE
                                WHEN base.classification = '1_Freshman' THEN
                                 'Freshman'
                                WHEN base.classification = '2_Sophomore' THEN
                                 'Sophomore'
                                WHEN base.classification = '3_Junior' THEN
                                 'Junior'
                                WHEN base.classification = '4_Senior' THEN
                                 'Senior'
                                ELSE
                                 base.classification
                                END,
                                base.overall_gpa,
                                mgpa.major_gpa,
                                base.hrs_remaining,
                                gmr.shrdgmr_acyr_code,
                                base.exp_grad_date,
                                'L',
                                nvl(addr.street_line1, resi.street_line1),
                                nvl(addr.street_line2, resi.street_line2),
                                nvl(addr.city, resi.city),
                                nvl(addr.stat_code, resi.stat_code),
                                nvl(addr.zip5, resi.zip5),
                                nvl(addr.natn_code, resi.natn_code),
                                resi.stat_code,
                                CASE
                                WHEN (lower(emer.spremrg_first_name) = 'unknown' OR lower(emer.spremrg_last_name) = 'unknown') THEN
                                 NULL
                                ELSE
                                 emer.spremrg_first_name || ' ' || emer.spremrg_last_name
                                END,
                                CASE
                                WHEN length(regexp_replace(emer.spremrg_phone_number, '[^0-9]')) = 7
                                     AND length(emer.spremrg_phone_area) = 3 THEN
                                 emer.spremrg_phone_area || regexp_replace(emer.spremrg_phone_number, '[^0-9]')
                                WHEN length(regexp_replace(emer.spremrg_phone_number, '[^0-9]')) = 10 THEN
                                 regexp_replace(emer.spremrg_phone_number, '[^0-9]')
                                WHEN length(emer.spremrg_phone_area) = 3
                                     AND length(regexp_replace(emer.spremrg_phone_number, '[^0-9]')) = 3
                                     AND length(emer.spremrg_phone_ext) = 4 THEN
                                 emer.spremrg_phone_area || regexp_replace(emer.spremrg_phone_number, '[^0-9]') || emer.spremrg_phone_ext
                                ELSE
                                 NULL
                                END,
                                crse.final_grade,
                                crse.term_code)
       SELECT mainquery.pidm || mainquery.enrl_term unique_key,
              mainquery.pidm,
              mainquery.luid,
              mainquery.firstname,
              mainquery.lastname,
              mainquery.enrl_term,
              mainquery.email,
              mainquery.alt_email,
              mainquery.phone,
              mainquery.ethnicity,
              mainquery.gender,
              mainquery.program,
              mainquery.campus, -- program campus code
              mainquery.dcp_year, -- dcp_year
              mainquery.classification,
              mainquery.overall_gpa, -- overall gpa
              mainquery.majorgpa, -- major gpa
              mainquery.credit_hrs_remaining, -- credit hours remaining
              mainquery.grad_year,
              mainquery.location_code,
              mainquery.address1,
              mainquery.address2,
              mainquery.city,
              mainquery.state,
              mainquery.zip,
              mainquery.country,
              mainquery.stat_code state_code,
              mainquery.e_contact emergency_contact,
              mainquery.e_contact_num emergency_contact_number, -- emergency contact number
              MAX(mainquery.ec) enrolled_courses, -- enrolled courses
              MAX(mainquery.cc) completed_courses, -- completed courses
              MAX(mainquery.ccg) completed_course_grades, -- completed course grades
              MAX(mainquery.rfc) registered_future_courses -- enrolled internship/practicum sections
         FROM mainquery
        GROUP BY mainquery.pidm || mainquery.enrl_term,
                 mainquery.pidm,
                 mainquery.luid,
                 mainquery.firstname,
                 mainquery.lastname,
                 mainquery.enrl_term,
                 mainquery.email,
                 mainquery.alt_email,
                 mainquery.phone,
                 mainquery.ethnicity,
                 mainquery.gender,
                 mainquery.program,
                 mainquery.campus,
                 mainquery.dcp_year,
                 mainquery.classification,
                 mainquery.overall_gpa,
                 mainquery.majorgpa,
                 mainquery.credit_hrs_remaining,
                 mainquery.grad_year,
                 mainquery.location_code,
                 mainquery.address1,
                 mainquery.address2,
                 mainquery.city,
                 mainquery.state,
                 mainquery.zip,
                 mainquery.country,
                 mainquery.stat_code,
                 mainquery.e_contact,
                 mainquery.e_contact_num) new_rec
         LEFT JOIN utl_d_aa.core_lucom_elms existing_rec
           ON existing_rec.unique_key = new_rec.unique_key
          AND existing_rec.to_date = to_date('12/31/2099', 'MM/DD/YYYY')
        WHERE existing_rec.unique_key IS NULL -- new record
             -- using nvls to find any changes for student record
           OR (coalesce(existing_rec.luid, 'XXXXXX') != coalesce(new_rec.luid, 'XXXXXX') OR coalesce(existing_rec.firstname, 'XXXXXX') != coalesce(new_rec.firstname, 'XXXXXX') OR
              coalesce(existing_rec.lastname, 'XXXXXX') != coalesce(new_rec.lastname, 'XXXXXX') OR coalesce(existing_rec.email, 'XXXXXX') != coalesce(new_rec.email, 'XXXXXX') OR
              coalesce(existing_rec.alt_email, 'XXXXXX') != coalesce(new_rec.alt_email, 'XXXXXX') OR coalesce(existing_rec.phone, 'XXXXXX') != coalesce(new_rec.phone, 'XXXXXX') OR
              coalesce(existing_rec.ethnicity, 'XXXXXX') != coalesce(new_rec.ethnicity, 'XXXXXX') OR coalesce(existing_rec.gender, 'XXXXXX') != coalesce(new_rec.gender, 'XXXXXX') OR
              coalesce(existing_rec.program, 'XXXXXX') != coalesce(new_rec.program, 'XXXXXX') OR coalesce(existing_rec.campus, 'XXXXXX') != coalesce(new_rec.campus, 'XXXXXX') OR
              coalesce(existing_rec.dcp_year, 'XXXXXX') != coalesce(new_rec.dcp_year, 'XXXXXX') OR coalesce(existing_rec.classification, 'XXXXXX') != coalesce(new_rec.classification, 'XXXXXX') OR
              coalesce(existing_rec.overall_gpa, 999999) != coalesce(new_rec.overall_gpa, 999999) OR coalesce(existing_rec.majorgpa, 999999) != coalesce(new_rec.majorgpa, 999999) OR
              coalesce(existing_rec.credit_hrs_remaining, 999999) != coalesce(new_rec.credit_hrs_remaining, 999999) OR coalesce(existing_rec.grad_year, 999999) != coalesce(new_rec.grad_year, 999999) OR
              coalesce(existing_rec.location_code, 'XXXXXX') != coalesce(new_rec.location_code, 'XXXXXX') OR coalesce(existing_rec.address1, 'XXXXXX') != coalesce(new_rec.address1, 'XXXXXX') OR
              coalesce(existing_rec.address2, 'XXXXXX') != coalesce(new_rec.address2, 'XXXXXX') OR coalesce(existing_rec.city, 'XXXXXX') != coalesce(new_rec.city, 'XXXXXX') OR
              coalesce(existing_rec.state, 'XXXXXX') != coalesce(new_rec.state, 'XXXXXX') OR coalesce(existing_rec.zip, 'XXXXXX') != coalesce(new_rec.zip, 'XXXXXX') OR
              coalesce(existing_rec.country, 'XXXXXX') != coalesce(new_rec.country, 'XXXXXX') OR coalesce(existing_rec.state_code, 'XXXXXX') != coalesce(new_rec.state_code, 'XXXXXX') OR
              coalesce(existing_rec.emergency_contact, 'XXXXXX') != coalesce(new_rec.emergency_contact, 'XXXXXX') OR coalesce(existing_rec.emergency_contact_number, 'XXXXXX') != coalesce(new_rec.emergency_contact_number, 'XXXXXX') OR
              coalesce(existing_rec.enrolled_courses, 'XXXXXX') != coalesce(new_rec.enrolled_courses, 'XXXXXX') OR coalesce(existing_rec.completed_courses, 'XXXXXX') != coalesce(new_rec.completed_courses, 'XXXXXX') OR
              coalesce(existing_rec.completed_course_grades, 'XXXXXX') != coalesce(new_rec.completed_course_grades, 'XXXXXX') OR
              coalesce(existing_rec.registered_future_courses, 'XXXXXX') != coalesce(new_rec.registered_future_courses, 'XXXXXX'));

TYPE rec_input_t IS TABLE OF curs%ROWTYPE;
rec_input rec_input_t;
TYPE index_pointer_t IS TABLE OF PLS_INTEGER;
ttab_dml index_pointer_t := index_pointer_t();
CURSOR cur_idx_dat(schema_ VARCHAR2,
                   table_  VARCHAR2) IS(
SELECT lower(a_idx.owner || '.' || a_idx.index_name) idx
  FROM all_indexes a_idx
 WHERE a_idx.owner = upper(schema_)
   AND a_idx.table_name = upper(table_));
rec_idx_dat cur_idx_dat%ROWTYPE;
TYPE index_pointer_i IS TABLE OF PLS_INTEGER;
insert_dml index_pointer_i := index_pointer_i();
TYPE index_pointer_u IS TABLE OF PLS_INTEGER;
update_dml index_pointer_u := index_pointer_u();
TYPE index_pointer_d IS TABLE OF PLS_INTEGER;
delete_dml   index_pointer_d := index_pointer_d();
start_time   TIMESTAMP;
end_time     TIMESTAMP;
select_count NUMBER := 0;
insert_count NUMBER := 0;
update_count NUMBER := 0;
delete_count NUMBER := 0;
start_t      DATE := SYSDATE;
elapsed      NUMBER := 0;
BEGIN
-- dbms_output.enable(buffer_size => NULL);
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
--
OPEN curs;
LOOP
v_count   := 0; -- reset count
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'START - ALL' || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
FETCH curs BULK COLLECT
INTO rec_input LIMIT v_row_max;
IF rec_input.count = 0 THEN
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'SELECT - ALL' || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
RETURN;
ELSIF rec_input.count > 0 THEN
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'SELECT - ALL' || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
insert_dml := index_pointer_i();
update_dml := index_pointer_u();
FOR idx IN rec_input.first .. rec_input.last
LOOP
v_count := rec_input(idx).total_rows;
IF rec_input(idx).control_state = 'CHANGE' THEN
-- UPDATE HAS TO HAPPEN FIRST TO EXPIRE RECORDS THAT ALREADY EXIST
update_dml.extend;
update_dml(update_dml.last) := idx;
END IF;
IF rec_input(idx).control_state IN ('NEW', 'CHANGE') THEN
-- ALL NEW RECS OR CHANGES GET INSERTED
insert_dml.extend;
insert_dml(insert_dml.last) := idx;
END IF;
END LOOP;
update_count := update_count + update_dml.count;
insert_count := insert_count + insert_dml.count;
-- DML UPDATES
FORALL i IN VALUES OF update_dml
UPDATE utl_d_aa.core_lucom_elms tab
   SET tab.to_date  = v_end_date,
     tab.activity_date = v_etl_date
 WHERE tab.unique_key = rec_input(i).unique_key
   AND tab.to_date = to_date('12/31/2099', 'MM/DD/YYYY');
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'UPDATE - ALL' || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- DML Inserts
FORALL i IN VALUES OF insert_dml
INSERT INTO utl_d_aa.core_lucom_elms tab
(unique_key,from_date,to_date,activity_date,
 pidm,
 luid,
 firstname,
 lastname,
 enrl_term,
 email,
 alt_email,
 phone,
 ethnicity,
 gender,
 program,
 campus,
 dcp_year,
 classification,
 overall_gpa,
 majorgpa,
 credit_hrs_remaining,
 grad_year,
 location_code,
 address1,
 address2,
 city,
 state,
 zip,
 country,
 state_code,
 emergency_contact,
 emergency_contact_number,
 enrolled_courses,
 completed_courses,
 completed_course_grades,
 registered_future_courses)
VALUES
(rec_input(i).unique_key,v_etl_date,to_date('12/31/2099', 'MM/DD/YYYY'),v_etl_date,
 rec_input(i).pidm,
 rec_input(i).luid,
 rec_input(i).firstname,
 rec_input(i).lastname,
 rec_input(i).enrl_term,
 rec_input(i).email,
 rec_input(i).alt_email,
 rec_input(i).phone,
 rec_input(i).ethnicity,
 rec_input(i).gender,
 rec_input(i).program,
 rec_input(i).campus,
 rec_input(i).dcp_year,
 rec_input(i).classification,
 rec_input(i).overall_gpa,
 rec_input(i).majorgpa,
 rec_input(i).credit_hrs_remaining,
 rec_input(i).grad_year,
 rec_input(i).location_code,
 rec_input(i).address1,
 rec_input(i).address2,
 rec_input(i).city,
 rec_input(i).state,
 rec_input(i).zip,
 rec_input(i).country,
 rec_input(i).state_code,
 rec_input(i).emergency_contact,
 rec_input(i).emergency_contact_number,
 rec_input(i).enrolled_courses,
 rec_input(i).completed_courses,
 rec_input(i).completed_course_grades,
 rec_input(i).registered_future_courses);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed     := round((SYSDATE - v_etl_date) * 86400);
v_msg         := 'INSERT - ALL' || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
v_total_count := v_total_count + v_count; -- keep running total of rows processed
dbms_output.put_line(v_msg || ' - rows processed: ' || to_char(v_count));
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
END IF;
SELECT ((CAST(SYSDATE AS DATE) - CAST(start_t AS DATE)) * 86400) INTO elapsed FROM dual;
select_count := select_count + rec_input.count;
EXIT WHEN(rec_input.count < v_row_max);
END LOOP;
CLOSE curs;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
-- log any errors
EXCEPTION
WHEN OTHERS THEN
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
/*--------------------------------------------CHANGE LOG----------------------------------------
VERSION  DATE        USERNAME    UPDATES
---      12/11/2024    JWTUCKER1     Initial Release - broke up original ELMS procedure into separate procedures per school for runtime and troubleshooting
---      09/19/2025    JWTUCKER1     Fixed update statement to join on pidm and not unique key, so that past terms do not keep an active record
---      10/21/2025    JWTUCKER1     Updated grad term to be based on sgbstdn, which LUCOM manages and is more accurate than a calculation. Most schools use calculation because they dont manage exp_grad_date in SGBSTDN
------------------------------------------------------------------------------------------------*/
END etl_aa_core_lucom_elms;

/*************
COURSE ROSTERS -- Not splitting into two feeds since its just SOE and COUC, may split up if other schools want a course roster feed
*************/
PROCEDURE etl_aa_core_faculty_rosters(jobnumber NUMBER, processid VARCHAR2, processname VARCHAR2) IS
/***************************************************
Table: utl_d_aa.core_course_rosters
Primary Keys: NONE
Unique index: TERM_CODE, CRN, LUID
Purpose:
- For faculty to view course rosters in CORE which is an outside vendor that replaced LiveText.
Conditions:
Dependencies: zformdata.zfblist; zformdata.zfrlist
****************************************************/
--DECLARE
--- PARAMS
v_etl_date DATE := SYSDATE;
v_msg      VARCHAR2(2000);
v_instance VARCHAR2(50) := upper('ALL'); -- inst from the jams job; used for determining instance
v_partition NUMBER := 0; -- nmbr from the jams job; used for partitioning IF NEEDED; DEFAULT 0
-- v_mod         NUMBER := 5; -- number of partitions to be created

v_count       NUMBER := 0;
v_row_max     NUMBER := 100000; -- max number of rows to be processed at one time
v_elapsed     NUMBER := 0;
v_total_count NUMBER := 0;
v_job_id      VARCHAR2(32);
v_proc        VARCHAR2(100) := 'etl_aa_core_faculty_rosters';
-- cursors
CURSOR curs IS
SELECT new_rec.*,
       CASE
       WHEN existing_rec.unique_key IS NULL THEN
        'NEW'
       WHEN existing_rec.unique_key IS NOT NULL
            AND (coalesce(existing_rec.status, 'X') <> coalesce(new_rec.status, 'X') OR coalesce(existing_rec.faculty_school_id, 'X') <> coalesce(new_rec.faculty_school_id, 'X')) THEN
        'CHANGE'
       END AS control_state, -- using none to not delete
       COUNT(*) over() total_rows
  FROM (WITH zlist AS (SELECT /*+ materialize */
                        l.zfrlist_char_01,
                        l.zfrlist_char_03 courselist
                         FROM zformdata.zfblist b
                         JOIN zformdata.zfrlist l
                           ON l.zfrlist_list_code = b.zfblist_code
                          AND l.zfrlist_active_yn = 'Y'
                        WHERE b.zfblist_code = 'CORE_FACULTY_ROSTER_COURSES'
                       --and l.zfrlist_char_02 >= 202420 -- limiting to all terms after 202420 (terms in genlist will be >= 202420)
                       ), --
       courses AS (SELECT /*+ materialize*/
                   DISTINCT t.zfrlist_char_01 school,
                            TRIM(regexp_substr(REPLACE(t.courselist, '&', ','), '[^,]+', 1, LEVEL)) course -- had to break out general list in a separate with statement for run time
                     FROM zlist t
                   CONNECT BY PRIOR dbms_random.value IS NOT NULL
                          AND PRIOR t.zfrlist_char_01 = t.zfrlist_char_01
                          AND LEVEL <= regexp_count(REPLACE(t.courselist, '&', ','), ',') + 1), --
       coursereg AS (SELECT /*+ materialize*/
                      stca.sfrstca_pidm,
                      courses.school,
                      stca.sfrstca_term_code term_code,
                      stca.sfrstca_crn crn,
                      sect.ssbsect_subj_code || sect.ssbsect_crse_numb course_code,
                      sect.ssbsect_seq_numb section_code,
                      stca.sfrstca_activity_date course_activity_date,
                      crse.faculty_id faculty_school_id, -- added faculty columns
                      crse.faculty_first_name faculty_firstname,
                      crse.faculty_last_name faculty_lastname,
                      crse.faculty_email faculty_email,
                      CASE
                      WHEN stca.sfrstca_rsts_code LIKE 'D%'
                           OR stca.sfrstca_rsts_code LIKE 'W%'
                           OR crse.final_grade LIKE 'F_'
                           OR crse.final_grade LIKE 'W%' THEN -- all drop and withdrawn rsts codes, all f grades like FN (excluding a normal F) and any W grades
                       'DROP'
                      ELSE
                       'ADD'
                      END status -- any kind of drop show drop else add
                       FROM courses
                       JOIN ssbsect sect
                         ON sect.ssbsect_subj_code || sect.ssbsect_crse_numb = courses.course
                        AND sect.ssbsect_term_code >= (SELECT MAX(term_code) AS current_term
                                                         FROM zbtm.terms_by_group_v
                                                        WHERE group_code = 'STD'
                                                          AND semester != 'WIN'
                                                          AND start_date <= SYSDATE)
                       JOIN sfrstca stca
                         ON stca.sfrstca_crn = sect.ssbsect_crn -- most recent course record per crn / term_code
                        AND stca.sfrstca_term_code = sect.ssbsect_term_code
                        AND stca.sfrstca_source_cde = 'BASE'
                        AND stca.sfrstca_seq_number = (SELECT MAX(sfrstca2.sfrstca_seq_number)
                                                         FROM saturn.sfrstca sfrstca2
                                                        WHERE sfrstca2.sfrstca_pidm = stca.sfrstca_pidm
                                                          AND sfrstca2.sfrstca_term_code = stca.sfrstca_term_code
                                                          AND sfrstca2.sfrstca_crn = stca.sfrstca_crn
                                                          AND sfrstca2.sfrstca_source_cde = 'BASE')
                       JOIN stvrsts rsts
                         ON rsts.stvrsts_code = stca.sfrstca_rsts_code
                       LEFT JOIN utl_d_aim.szrcrse crse
                         ON crse.pidm = stca.sfrstca_pidm
                        AND crse.term_code = stca.sfrstca_term_code
                        AND crse.crn = stca.sfrstca_crn)
       SELECT /*+ materialize*/
        iden.spriden_id luid,
        coursereg.school,
        coursereg.term_code,
        coursereg.crn,
        coursereg.course_code,
        coursereg.section_code,
        term_code.stvterm_desc AS semester_code,
        coursereg.status,
        coursereg.course_activity_date,
        CASE
        WHEN coursereg.status = 'DROP' THEN
         NULL
        ELSE
         coursereg.faculty_school_id
        END faculty_school_id -- added faculty columns
      ,
        CASE
        WHEN coursereg.status = 'DROP' THEN
         NULL
        ELSE
         coursereg.faculty_firstname
        END faculty_firstname,
        CASE
        WHEN coursereg.status = 'DROP' THEN
         NULL
        ELSE
         coursereg.faculty_lastname
        END faculty_lastname,
        CASE
        WHEN coursereg.status = 'DROP' THEN
         NULL
        ELSE
         coursereg.faculty_email
        END faculty_email,
        iden.spriden_id || coursereg.term_code || coursereg.crn unique_key, -- unique key based on luid, term_code, crn
        v_etl_date activity_date
         FROM coursereg
         JOIN spriden iden
           ON iden.spriden_pidm = coursereg.sfrstca_pidm -- bringing in student luid for core
          AND iden.spriden_change_ind IS NULL
         JOIN stvterm term_code
           ON term_code.stvterm_code = coursereg.term_code -- for term_code desc in core
        ) new_rec
         LEFT JOIN utl_d_aa.core_course_rosters existing_rec
           ON existing_rec.unique_key = new_rec.luid || new_rec.term_code || new_rec.crn; -- create index to speed up (tried luid, term_code, crn and went faster, would something else be better)
TYPE rec_input_t IS TABLE OF curs%ROWTYPE;
rec_input rec_input_t;
TYPE index_pointer_t IS TABLE OF PLS_INTEGER;
ttab_dml index_pointer_t := index_pointer_t();
CURSOR cur_idx_dat(schema_ VARCHAR2,
                   table_  VARCHAR2) IS(
SELECT lower(a_idx.owner || '.' || a_idx.index_name) idx
  FROM all_indexes a_idx
 WHERE a_idx.owner = upper(schema_)
   AND a_idx.table_name = upper(table_));
rec_idx_dat cur_idx_dat%ROWTYPE;
TYPE index_pointer_i IS TABLE OF PLS_INTEGER;
insert_dml index_pointer_i := index_pointer_i();
TYPE index_pointer_u IS TABLE OF PLS_INTEGER;
update_dml index_pointer_u := index_pointer_u();
TYPE index_pointer_d IS TABLE OF PLS_INTEGER;
delete_dml   index_pointer_d := index_pointer_d();
start_time   TIMESTAMP;
end_time     TIMESTAMP;
select_count NUMBER := 0;
insert_count NUMBER := 0;
update_count NUMBER := 0;
delete_count NUMBER := 0;
start_t      DATE := SYSDATE;
elapsed      NUMBER := 0;
BEGIN
-- dbms_output.enable(buffer_size => NULL);
--
SELECT standard_hash(v_proc || v_instance || v_partition || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss'), 'MD5') INTO v_job_id FROM dual;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'BEGIN - ' || v_instance || ' - ' || v_partition || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || v_job_id || ')';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
--
OPEN curs;
LOOP
FETCH curs BULK COLLECT
INTO rec_input LIMIT v_row_max;
v_total_count := v_total_count + rec_input.count;
IF rec_input.count = 0 THEN
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'No rows found in cursor... ';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
v_msg := ' -- COMPLETED --';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
RETURN;
ELSIF rec_input.count > 0 THEN
insert_dml := index_pointer_i();
update_dml := index_pointer_u();
delete_dml := index_pointer_d();
FOR idx IN rec_input.first .. rec_input.last
LOOP
v_count := rec_input(idx).total_rows;
IF rec_input(idx).control_state = 'NEW' THEN
insert_dml.extend;
insert_dml(insert_dml.last) := idx;
END IF;
IF rec_input(idx).control_state = 'CHANGE' THEN
update_dml.extend;
update_dml(update_dml.last) := idx;
END IF;
IF rec_input(idx).control_state = 'DELETE' THEN
-- not using delete
delete_dml.extend;
delete_dml(delete_dml.last) := idx;
END IF;
END LOOP;
insert_count := insert_count + insert_dml.count;
update_count := update_count + update_dml.count;
delete_count := delete_count + delete_dml.count;
v_elapsed    := round((SYSDATE - v_etl_date) * 86400);
v_msg        := 'Query returned ' || v_count || ' rows';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- DML Inserts
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'Inserts started at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss');
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
FORALL i IN VALUES OF insert_dml
INSERT INTO utl_d_aa.core_course_rosters tab
(luid,
 school,
 term_code,
 crn,
 course_code,
 section_code,
 semester_code,
 status,
 course_activity_date,
 faculty_school_id,
 faculty_firstname,
 faculty_lastname,
 faculty_email,
 unique_key,
 activity_date)
VALUES
(rec_input(i).luid,
 rec_input(i).school,
 rec_input(i).term_code,
 rec_input(i).crn,
 rec_input(i).course_code,
 rec_input(i).section_code,
 rec_input(i).semester_code,
 rec_input(i).status,
 rec_input(i).course_activity_date,
 rec_input(i).faculty_school_id,
 rec_input(i).faculty_firstname,
 rec_input(i).faculty_lastname,
 rec_input(i).faculty_email,
 rec_input(i).unique_key,
 rec_input(i).activity_date);
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := ' rows inserted: ' || v_count || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss');
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- DML UPDATES
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'Updates started at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss');
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
FORALL i IN VALUES OF update_dml
UPDATE utl_d_aa.core_course_rosters tab
   SET (luid, school, term_code, crn, course_code, section_code, semester_code, status, course_activity_date, faculty_school_id, faculty_firstname, faculty_lastname, faculty_email, unique_key, activity_date) =
       (SELECT rec_input(i).luid,
               rec_input(i).school,
               rec_input(i).term_code,
               rec_input(i).crn,
               rec_input(i).course_code,
               rec_input(i).section_code,
               rec_input(i).semester_code,
               rec_input(i).status,
               rec_input(i).course_activity_date,
               rec_input(i).faculty_school_id,
               rec_input(i).faculty_firstname,
               rec_input(i).faculty_lastname,
               rec_input(i).faculty_email,
               rec_input(i).unique_key,
               rec_input(i).activity_date
          FROM dual)
 WHERE tab.unique_key = rec_input(i).unique_key; -- comparing unqiue key to update records, status is being compared in top select
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := ' records updated: ' || v_count || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss');
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
-- DML DELETES -- not using delete (like in InPlace)
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'Deletes started at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss');
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
FORALL i IN VALUES OF delete_dml
DELETE FROM utl_d_aa.core_course_rosters tab WHERE tab.unique_key = rec_input(i).unique_key;
v_count := SQL%ROWCOUNT;
COMMIT;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := ' rows deleted: ' || v_count || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss');
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_count);
dbms_output.put_line(' --------- ');
END IF;
SELECT ((CAST(SYSDATE AS DATE) - CAST(start_t AS DATE)) * 86400) INTO elapsed FROM dual;
select_count := select_count + rec_input.count;
EXIT WHEN(rec_input.count < v_row_max);
END LOOP;
CLOSE curs;
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := 'END - rows processed: ' || to_char(v_total_count) || ' at ' || to_char(SYSDATE, 'MM/DD/YYYY hh24:mi:ss') || ' (' || to_char(v_elapsed) || ' secs)';
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'INFO', v_msg, v_instance, v_partition, v_job_id, v_elapsed, v_total_count);
-- log any errors
EXCEPTION
WHEN OTHERS THEN
v_elapsed := round((SYSDATE - v_etl_date) * 86400);
v_msg     := substr(REPLACE(SQLERRM, 'ORA', '!!!'), 1, 200);
dbms_output.put_line(v_msg);
ads_etl.insert_job_log(v_proc, 'ERROR', v_msg, v_instance, v_partition, v_job_id, v_elapsed, 0);
/*--------------------------------------------CHANGE LOG----------------------------------------
VERSION  DATE        USERNAME    UPDATES
---      5/6/2024    JWTUCKER1     Initial Release
---      8/26/2024   JWTUCKER1     Updated szrcrse join
---      12/13/2024  JWTUCKER1     Added to new CORE pkg, added WD and FN grades as DROPS
---      02/10/2025  JWTUCKER1     Updated faculty cols to NULL when student reg status is dropped
------------------------------------------------------------------------------------------------*/
END etl_aa_core_faculty_rosters;

END load_aa_etl_core;
