# Phase 62: First-Line Therapy & Death Analysis - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-30
**Phase:** 62-first-line-therapy-and-death-analysis
**Areas discussed:** First-line eligibility, Death analysis tables, Output format & structure, Relationship to Phase 59

---

## First-Line Eligibility

### Q1: Which chemotherapy episodes should be eligible for the first-line flag?

| Option | Description | Selected |
|--------|-------------|----------|
| Only regimen-labeled (Recommended) | First-line flag only on episodes that Phase 61 labeled as ABVD, BV+AVD, or Nivo+AVD. Unlabeled chemo episodes get no first-line flag. | ✓ |
| All chemotherapy | Any chemo episode with 60-day clean period gets is_first_line=TRUE, regardless of whether Phase 61 identified a specific regimen. | |
| Both with distinction | All chemo gets is_first_line flag, but a separate is_first_line_regimen flag only for the 3 labeled regimens. | |

**User's choice:** Only regimen-labeled
**Notes:** None

### Q2: How should age 21+ be determined?

| Option | Description | Selected |
|--------|-------------|----------|
| Age at episode start (Recommended) | Calculate age at the first chemotherapy episode start date. DEMOGRAPHIC.BIRTH_DATE is available via DuckDB. | ✓ |
| Age at HL diagnosis | Calculate age at first_hl_dx_date from confirmed_hl_cohort.rds. Anchors to clinical milestone rather than treatment timing. | |
| You decide | Claude picks the most clinically appropriate approach during planning. | |

**User's choice:** Age at episode start
**Notes:** None

### Q3: What defines the 60-day clean period?

| Option | Description | Selected |
|--------|-------------|----------|
| No chemo of any kind in 60 days before episode start (Recommended) | Look back 60 days from episode_start. If any chemotherapy date exists in that window, the episode is NOT first-line. | ✓ |
| No treatment of any kind in 60 days | Broader: no chemo, radiation, SCT, or immunotherapy in the 60-day lookback window. | |
| No prior chemo episodes ever | Strictest: first chemo episode for the patient, period. No time window — any prior chemo disqualifies. | |

**User's choice:** No chemo of any kind in 60 days before episode start
**Notes:** None

### Q4: How should the first-line flag work across multiple episodes per patient?

| Option | Description | Selected |
|--------|-------------|----------|
| First qualifying episode only (Recommended) | Only the earliest chemo episode meeting the 60-day clean period gets is_first_line=TRUE. All subsequent episodes are FALSE. | ✓ |
| Any qualifying episode | Every chemo episode with a 60-day clean lookback gets flagged. A patient could have multiple first-line episodes if they have long gaps between treatments. | |

**User's choice:** First qualifying episode only
**Notes:** None

---

## Death Analysis Tables

### Q5: Which death date population should the analysis tables use?

| Option | Description | Selected |
|--------|-------------|----------|
| All recorded deaths (Recommended) | Use every patient with a DEATH_DATE in the DEATH table (after 1900 sentinel filtering). Shows full data quality picture. Phase 59's validation flags are available as context but don't exclude. | |
| Validated deaths only | Use only patients where death_valid=TRUE from validated_death_dates.rds. Excludes impossible deaths (before earliest treatment). | ✓ |
| Both views | Primary table uses all recorded deaths, with a footnote/column showing validated-only counts for comparison. | |

**User's choice:** Validated deaths only
**Notes:** User chose validated deaths over the recommended all-deaths approach. Phase 59's impossible death exclusion applies.

### Q6: What counts as 'death is the last encounter' for DEATH-02?

| Option | Description | Selected |
|--------|-------------|----------|
| Last ENCOUNTER table record (Recommended) | Compare DEATH_DATE to max(ADMIT_DATE) from ENCOUNTER table. Death is 'last' if no encounter occurs after it. | ✓ |
| Last clinical activity of any kind | Compare DEATH_DATE to max of: ENCOUNTER.ADMIT_DATE, DIAGNOSIS.DX_DATE, any treatment date. More thorough but more complex. | |
| You decide | Claude picks the clinically appropriate comparison during planning. | |

**User's choice:** Last ENCOUNTER table record
**Notes:** None

### Q7: How should 'encounters after death' be stratified for DEATH-03?

| Option | Description | Selected |
|--------|-------------|----------|
| By ENC_TYPE (Recommended) | Stratify by PCORnet encounter type (AV, TH, ED, IP, IS, OA, etc.). Shows which encounter settings have post-death records. | ✓ |
| By activity type | Stratify by encounters vs. diagnoses vs. treatments. Shows what kind of clinical activity occurs after death. | |
| Both dimensions | Two stratification tables: one by ENC_TYPE, one by activity type (encounter/diagnosis/treatment). | |

**User's choice:** By ENC_TYPE
**Notes:** None

---

## Output Format & Structure

### Q8: Where should the first-line therapy flag go?

| Option | Description | Selected |
|--------|-------------|----------|
| New column in treatment_episodes.rds (Recommended) | Add is_first_line boolean to the existing RDS artifact. Phase 63 picks it up automatically when building Gantt v2. Follows the Phase 60 pattern of enriching existing artifacts. | ✓ |
| Standalone analysis RDS | New first_line_therapy.rds with patient-level first-line analysis. treatment_episodes.rds stays unchanged. | |
| Both | Column in treatment_episodes.rds for downstream use AND a standalone first-line summary for analysis. | |

**User's choice:** New column in treatment_episodes.rds
**Notes:** None

### Q9: What output format for the death analysis tables?

| Option | Description | Selected |
|--------|-------------|----------|
| Styled xlsx + CSV (Recommended) | Multi-sheet xlsx following Phase 59 pattern (openxlsx2). Plus flat CSV. Sheet 1 = summary counts, Sheet 2 = ENC_TYPE stratification. | ✓ |
| xlsx only | Styled xlsx workbook only, no CSV. | |
| Console summary only | Print summary counts to console log. No file output. | |

**User's choice:** Styled xlsx + CSV
**Notes:** None

### Q10: Single script or separate scripts for the two components?

| Option | Description | Selected |
|--------|-------------|----------|
| Single combined script (Recommended) | One R/62_first_line_and_death_analysis.R script. Shared data dependencies justify combining. | ✓ |
| Separate scripts | R/62a_first_line_therapy.R and R/62b_death_analysis.R. Cleaner separation but more files. | |
| You decide | Claude picks the approach during planning. | |

**User's choice:** Single combined script
**Notes:** None

---

## Relationship to Phase 59

### Q11: How should Phase 62 death analysis relate to Phase 59's existing work?

| Option | Description | Selected |
|--------|-------------|----------|
| Build on validated_death_dates.rds (Recommended) | Load Phase 59's artifact as input. Don't re-validate or re-query DEATH table. Just produce summary counts and ENC_TYPE stratification from the validated set. | ✓ |
| Independent analysis | Query DEATH table fresh, do own sentinel filtering. More self-contained but duplicates work. | |
| Extend Phase 59 xlsx | Add new sheets to existing death_date_validation.xlsx rather than creating a new workbook. | |

**User's choice:** Build on validated_death_dates.rds
**Notes:** None

### Q12: Should Phase 62 re-run Phase 59's post-death activity detection?

| Option | Description | Selected |
|--------|-------------|----------|
| Reference Phase 59 flags (Recommended) | Use post_death_activity flag from validated_death_dates.rds for DEATH-03 count. Only query ENCOUNTER for NEW ENC_TYPE stratification. | ✓ |
| Re-detect independently | Phase 62 independently checks ENCOUNTER, DIAGNOSIS, and treatment tables. Fully self-contained. | |

**User's choice:** Reference Phase 59 flags
**Notes:** None

---

## Claude's Discretion

- Column ordering for is_first_line in treatment_episodes.rds
- xlsx sheet styling (colors, column widths, freeze panes)
- Console logging detail level during analysis
- Whether to also produce a first-line summary table in the xlsx
- How to handle edge case where a patient has no ENCOUNTER records at all

## Deferred Ideas

None — discussion stayed within phase scope
