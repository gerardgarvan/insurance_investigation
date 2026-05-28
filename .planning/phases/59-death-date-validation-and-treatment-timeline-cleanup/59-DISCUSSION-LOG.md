# Phase 59: Death Date Validation & Treatment Timeline Cleanup - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-28
**Phase:** 59-death-date-validation-and-treatment-timeline-cleanup
**Areas discussed:** Death date validation rules, Death-only patients, Treatment category date, Output and scope

---

## Death Date Validation Rules

| Option | Description | Selected |
|--------|-------------|----------|
| Before any treatment date | Exclude death dates before patient's EARLIEST treatment date across all types | ✓ |
| Before last treatment date | Exclude death dates before patient's LATEST treatment date. More lenient. | |
| Before any known activity | Exclude death dates earlier than ANY clinical activity. Strictest. | |

**User's choice:** Before any treatment date (Recommended)
**Notes:** Patient can't die before starting treatment and still have treatment records.

---

| Option | Description | Selected |
|--------|-------------|----------|
| Flag post-death activity | Check ENCOUNTER, DIAGNOSIS, treatment tables for records after death. Flag for review. | ✓ |
| Exclude death dates with post-death activity | Treat death date as invalid if any clinical activity occurs after. | |
| No, just check against treatments | Only validate against treatment dates. | |

**User's choice:** Yes, flag post-death activity (Recommended)
**Notes:** Surfaces patients with post-death records for review without auto-excluding.

---

| Option | Description | Selected |
|--------|-------------|----------|
| Remove from Gantt CSVs | Drop impossible death pseudo-treatment rows entirely. | ✓ |
| Keep but flag as invalid | Keep death row with death_date_valid = FALSE column. | |

**User's choice:** Remove from Gantt CSVs (Recommended)
**Notes:** Patient retains treatment rows but loses death endpoint.

---

## Death-Only Patients

| Option | Description | Selected |
|--------|-------------|----------|
| Demographics + diagnosis + death info | Patient ID, death date, death source, HL dates, cancer categories, enrollment, site. | |
| Just counts and summary stats | Counts by partner site, death source, time period. | |
| Full clinical timeline | All available data: demographics, diagnoses, encounters, enrollment. | ✓ |

**User's choice:** Full clinical timeline
**Notes:** Most comprehensive characterization of death-only patients.

---

| Option | Description | Selected |
|--------|-------------|----------|
| Why no treatments? | Understanding gaps in care — diagnosed but never treated? Death-only sources? | |
| Are they real HL patients? | Validate HL confirmation status (2+ codes, 7-day). | |
| Both — validity and care gaps | Check HL validity AND understand why no treatments. | ✓ |

**User's choice:** Both — validity and care gaps
**Notes:** Dual investigation: confirm HL status and characterize care gaps.

---

## Treatment Category Date

| Option | Description | Selected |
|--------|-------------|----------|
| First treatment date (any type) | Add earliest treatment date across all types as a column. | |
| First date per treatment type | Add first_chemo_date, first_radiation_date, etc. | |
| A new treatment category to detect | New treatment type not currently captured. | |

**User's choice:** Other — "it's the first HL diagnosis date but added under the treatment column"
**Notes:** Add first_hl_dx_date as pseudo-treatment row with treatment_type = "HL Diagnosis" in Gantt CSVs.

---

| Option | Description | Selected |
|--------|-------------|----------|
| HL Diagnosis | treatment_type = "HL Diagnosis". Clear, consistent with Death naming. | ✓ |
| Diagnosis | treatment_type = "Diagnosis". More generic. | |
| First HL Dx | treatment_type = "First HL Dx". Shorter. | |

**User's choice:** HL Diagnosis (Recommended)

---

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, confirmed only | Only patients in confirmed_hl_cohort.rds. | |
| All patients with any HL code | Any patient with at least one HL diagnosis code. More inclusive. | ✓ |

**User's choice:** All patients with any HL code
**Notes:** More inclusive — uses earliest HL date from DIAGNOSIS/TUMOR_REGISTRY regardless of 7-day confirmation.

---

## Output and Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Styled xlsx report | Multi-sheet xlsx with validation summary, patient detail, death-only investigation. | |
| CSV only | Simple CSVs, minimal formatting. | |
| Both xlsx and CSV | Styled xlsx for review + CSV for downstream R use. | ✓ |

**User's choice:** Both xlsx and CSV

---

| Option | Description | Selected |
|--------|-------------|----------|
| All patients with death dates | Validate for ALL patients in DEATH table regardless of HL status. | ✓ |
| Confirmed HL cohort only | Only patients in confirmed_hl_cohort.rds. | |
| Both as separate views | All patients AND separately for confirmed HL cohort. | |

**User's choice:** All patients with death dates (Recommended)

---

| Option | Description | Selected |
|--------|-------------|----------|
| Save validated_death_dates.rds | Cleaned death dates as RDS artifact for downstream scripts. | ✓ |
| Standalone investigation only | Report only, no artifact. | |

**User's choice:** Save validated_death_dates.rds (Recommended)

---

## Claude's Discretion

- Script numbering and naming
- Column ordering in xlsx
- Whether to modify R/49 in place or create separate validation script
- Summary statistics in validation overview sheet
- Exact schema of validated_death_dates.rds

## Deferred Ideas

None — discussion stayed within phase scope
