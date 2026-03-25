---
phase: 03-cohort-building
plan: 02
subsystem: cohort-assembly
tags: [cohort, filter-chain, attrition-logging, treatment-flags, age-calculation]
dependencies:
  requires: [03_cohort_predicates.R, 02_harmonize_payer.R, 01_load_pcornet.R, utils_attrition.R]
  provides: [hl_cohort, attrition_log, cohort_csv]
  affects: [Phase 4 visualizations]
tech_stack:
  added: []
  patterns: [filter-chain-composition, attrition-logging, lubridate-age-calculation, primary-site-strategy, left-join-treatment-flags]
key_files:
  created:
    - R/04_build_cohort.R (250 lines: filter chain, enrollment aggregation, treatment flags, cohort assembly, CSV output)
  modified: []
decisions:
  - Primary site strategy for multi-site deduplication (D-13 via inner_join on ID+SOURCE with DEMOGRAPHIC)
  - Age calculation via lubridate interval() + time_length() for leap-year accuracy (D-10)
  - Treatment flags via left_join + replace_na(0L) for 0/1 integer flags (D-02, D-06)
  - Attrition logging uses n_distinct(cohort$ID) for patient counts (not nrow)
metrics:
  duration_seconds: 81
  tasks_completed: 2
  files_created: 1
  files_modified: 0
  commits: 1
completed: 2026-03-25T04:26:24Z
---

# Phase 03 Plan 02: Cohort Build Pipeline

**One-liner:** Complete cohort build pipeline composing filter predicates with attrition logging, enrollment aggregation with primary-site deduplication, age calculation via lubridate, treatment flag joins, and CSV output with 18 D-09 columns

## What Was Built

Created R/04_build_cohort.R (250 lines) as the main cohort assembly script that:

1. **Filter chain with attrition logging** — 4 sequential steps with log_attrition() after each: Initial population (DEMOGRAPHIC) → has_hodgkin_diagnosis() → with_enrollment_period() → exclude_missing_payer() → produces filtered cohort tibble
2. **Enrollment aggregation** — Primary site strategy (inner_join ENROLLMENT with DEMOGRAPHIC on ID+SOURCE) → group_by(ID) → min(ENR_START_DATE), max(ENR_END_DATE) → enrollment_duration_days
3. **Age calculation** — lubridate pattern: time_length(interval(BIRTH_DATE, enr_start_date), "years") → age_at_enr_start, age_at_enr_end (integer ages, leap-year accurate)
4. **First DX join** — left_join with first_dx tibble from 02_harmonize_payer.R → adds first_hl_dx_date
5. **Payer summary join** — left_join with payer_summary → adds PAYER_CATEGORY_PRIMARY, PAYER_CATEGORY_AT_FIRST_DX, DUAL_ELIGIBLE, PAYER_TRANSITION, N_ENCOUNTERS, N_ENCOUNTERS_WITH_PAYER
6. **Treatment flags** — left_join with has_chemo(), has_radiation(), has_sct() → replace_na(0L) → HAD_CHEMO, HAD_RADIATION, HAD_SCT (integer 0/1 flags)
7. **Final assembly** — select() 18 columns in D-09 order → hl_cohort tibble
8. **Console output** — Comprehensive summary: total patients, payer distribution, treatment flag percentages, demographics (age range, enrollment duration), site distribution, attrition log table
9. **CSV output** — write_csv to output/cohort/hl_cohort.csv (D-11)

All filter steps use n_distinct(cohort$ID) for patient counts (not nrow). hl_cohort and attrition_log remain in global R environment for Phase 4 consumption.

## Requirements Satisfied

| Requirement | Status | Evidence |
|-------------|--------|----------|
| CHRT-01 (named predicates) | ✓ Complete | Filter chain composes has_hodgkin_diagnosis, with_enrollment_period, exclude_missing_payer from 03_cohort_predicates.R |
| CHRT-02 (attrition logging) | ✓ Complete | init_attrition_log() + 4 log_attrition() calls tracking patient counts at each step; attrition_log printed to console |
| CHRT-03 (ICD format matching) | ✓ Complete | has_hodgkin_diagnosis() calls is_hl_diagnosis() which normalizes ICD codes |

## Key Decisions

| Decision | Rationale | Impact |
|----------|-----------|--------|
| Primary site deduplication strategy (D-13) | DEMOGRAPHIC has one row per patient with canonical SOURCE; filter ENROLLMENT to primary site via inner_join on (ID, SOURCE) | Prevents multi-site patients from appearing as duplicates; enrollment dates aggregated per primary site only |
| Age calculation via lubridate interval() + time_length() | Handles leap years correctly; standard R pattern; no external dependencies | age_at_enr_start and age_at_enr_end are integer floor(years), accurate across leap years |
| Treatment flags via left_join + replace_na(0L) | has_chemo/has_radiation/has_sct return tibbles of IDs with evidence; left_join preserves all cohort patients; replace_na sets 0 for no evidence | All HL patients retained regardless of treatment status (D-02); flags are 0/1 integers (D-06) |
| n_distinct(cohort$ID) for attrition counts | Patient-level counts required (D-17 from Phase 1); prevents row-count inflation from multi-enrollment patients | Attrition log tracks unique patients, not rows |

## Files Modified

### Created
- **R/04_build_cohort.R** (250 lines)
  - Sources: 02_harmonize_payer.R (loads everything upstream), 03_cohort_predicates.R
  - Libraries: dplyr, lubridate, glue, readr
  - Sections:
    1. Header and dependencies
    2. Filter chain with attrition logging (4 steps)
    3. Enrollment aggregation (primary site strategy, min/max dates, duration calculation)
    4. First HL diagnosis join
    5. Payer summary join (6 payer fields from payer_summary)
    6. Treatment flags (3 left_joins + replace_na)
    7. Final cohort assembly (select 18 D-09 columns)
    8. Cohort summary (console output: payer distribution, treatment flags, demographics, sites)
    9. Attrition summary (print attrition_log table)
    10. CSV output (output/cohort/hl_cohort.csv)

## Deviations from Plan

None — plan executed exactly as written. Both tasks completed in single file creation.

## Technical Notes

### Multi-Site Deduplication (D-13)

**Strategy chosen:** Primary site only (DEMOGRAPHIC SOURCE as canonical)

**Implementation:**
```r
enrollment_primary <- pcornet$ENROLLMENT %>%
  inner_join(
    pcornet$DEMOGRAPHIC %>% select(ID, SOURCE),
    by = c("ID", "SOURCE")
  )
```

This filters ENROLLMENT to keep only periods at the patient's primary site. DEMOGRAPHIC has one row per patient with SOURCE = canonical site assignment. Multi-site patients appearing at secondary sites have those enrollments excluded.

**Alternative considered:** Union all sites (keep multiple SOURCE per patient). Rejected because downstream payer analysis assumes one SOURCE per patient.

### Age Calculation (D-10)

**Pattern:**
```r
age_at_enr_start = as.integer(
  time_length(interval(BIRTH_DATE, enr_start_date), "years")
)
```

**Why this works:**
- `interval(start, end)` creates precise time span accounting for leap years
- `time_length(..., "years")` converts to decimal years
- `as.integer()` floors to whole years (standard age calculation)

**Alternative rejected:** `as.numeric(enr_start_date - BIRTH_DATE) / 365.25` breaks on leap years and timezone edge cases.

### Treatment Flag Join Pattern

**Pattern:**
```r
cohort <- cohort %>%
  left_join(chemo_flags, by = "ID") %>%
  left_join(rad_flags, by = "ID") %>%
  left_join(sct_flags, by = "ID") %>%
  mutate(
    HAD_CHEMO = replace_na(HAD_CHEMO, 0L),
    HAD_RADIATION = replace_na(HAD_RADIATION, 0L),
    HAD_SCT = replace_na(HAD_SCT, 0L)
  )
```

**Why left_join:** Preserves all cohort patients. Patients without evidence get NA, then replaced with 0L.

**Why replace_na(0L) not coalesce:** replace_na is vectorized and works with mutate across multiple columns. coalesce requires explicit column reference per flag.

### Final Cohort Structure (D-09)

18 columns in specified order:
1. ID (character)
2. SOURCE (character, primary site)
3. SEX (PCORnet code)
4. RACE (PCORnet code)
5. HISPANIC (PCORnet code)
6. age_at_enr_start (integer)
7. age_at_enr_end (integer)
8. first_hl_dx_date (Date)
9. PAYER_CATEGORY_PRIMARY (9-category system)
10. PAYER_CATEGORY_AT_FIRST_DX (9-category system)
11. DUAL_ELIGIBLE (integer 0/1)
12. PAYER_TRANSITION (integer 0/1)
13. N_ENCOUNTERS (integer)
14. N_ENCOUNTERS_WITH_PAYER (integer)
15. HAD_CHEMO (integer 0/1)
16. HAD_RADIATION (integer 0/1)
17. HAD_SCT (integer 0/1)
18. enrollment_duration_days (numeric)

BIRTH_DATE, enr_start_date, enr_end_date dropped from final output (intermediate columns only).

## Known Stubs

None — all sections fully implemented.

## Testing Notes

**Manual verification steps:**
1. Run `source("R/04_build_cohort.R")` in RStudio
2. Verify console output shows:
   - 4 attrition steps with decreasing patient counts
   - Enrollment aggregation stats (median duration)
   - First DX stats (N with vs missing dates)
   - Payer join success (all patients have PAYER_CATEGORY_PRIMARY)
   - Treatment flag totals and percentages
   - Cohort summary (payer distribution, demographics, site distribution)
   - Attrition log table (4 rows)
3. Check hl_cohort object in R environment: `dim(hl_cohort)` should show 18 columns
4. Check attrition_log object: `print(attrition_log)` should show 4 rows with columns: step, n_before, n_after, n_excluded, pct_excluded
5. Verify CSV file created: `file.exists("output/cohort/hl_cohort.csv")`

**Expected edge cases:**
- Patients with first_hl_dx_date = NA (diagnosis outside network or in TUMOR_REGISTRY only) — acceptable per D-09
- Patients with HAD_CHEMO = 1 but no first_hl_dx_date — acceptable, documented as edge case in Phase 3 research
- Age calculations with BIRTH_DATE = NA → age_at_enr_start = NA — handled by time_length() returning NA

**No automated tests created** (out of scope for v1 exploratory pipeline).

## Integration Points

### Upstream Dependencies
- **R/00_config.R** — CONFIG$output_dir, auto-sources utilities
- **R/utils_attrition.R** — init_attrition_log(), log_attrition()
- **R/01_load_pcornet.R** — pcornet$DEMOGRAPHIC, pcornet$ENROLLMENT
- **R/02_harmonize_payer.R** — payer_summary, first_dx tibbles
- **R/03_cohort_predicates.R** — has_hodgkin_diagnosis(), with_enrollment_period(), exclude_missing_payer(), has_chemo(), has_radiation(), has_sct()

### Downstream Consumers
- **Phase 4 visualizations** — Will consume hl_cohort and attrition_log from R environment
- **Manual analysis** — output/cohort/hl_cohort.csv available for inspection, external analysis, validation against Python pipeline

### Usage Example
```r
# Load and build cohort
source("R/04_build_cohort.R")

# Cohort is now available as hl_cohort tibble
dim(hl_cohort)  # Should show N patients × 18 columns
head(hl_cohort)

# Attrition log is available as attrition_log data frame
print(attrition_log)  # Shows 4 filter steps

# CSV is saved at output/cohort/hl_cohort.csv
read_csv("output/cohort/hl_cohort.csv")  # Can reload for external use
```

## Self-Check: PASSED

### Files Created
- R/04_build_cohort.R: ✓ EXISTS (250 lines, 10 sections)

### File Content Verification
```bash
grep -c "log_attrition\|init_attrition_log\|has_hodgkin_diagnosis\|with_enrollment_period\|exclude_missing_payer\|enrollment_duration_days\|time_length" R/04_build_cohort.R
# Output: 47 (all required patterns present)
```

### Commits
- 90bbea4: ✓ EXISTS (feat(03-02): create complete cohort build pipeline)

### Required Patterns Verified
- ✓ source("R/02_harmonize_payer.R") and source("R/03_cohort_predicates.R")
- ✓ init_attrition_log() called
- ✓ 4 log_attrition() calls (initial population + 3 filter steps)
- ✓ Filter chain follows D-01 order: has_hodgkin_diagnosis → with_enrollment_period → exclude_missing_payer
- ✓ Primary site deduplication: inner_join(pcornet$ENROLLMENT, DEMOGRAPHIC, by = c("ID", "SOURCE"))
- ✓ Enrollment aggregation: group_by(ID) + min/max dates + enrollment_duration_days
- ✓ Age calculation: time_length(interval(BIRTH_DATE, enr_start_date), "years")
- ✓ First DX join: left_join(first_dx, by = "ID")
- ✓ Payer summary join: left_join(payer_summary, by = "ID") with 6 fields
- ✓ Treatment flags: left_join(has_chemo(), has_radiation(), has_sct()) + replace_na(0L)
- ✓ Final select() with 18 columns in D-09 order
- ✓ Cohort summary console output (payer distribution, treatment flags, demographics, sites)
- ✓ Attrition log printed to console
- ✓ CSV output: write_csv(hl_cohort, output_path)
- ✓ hl_cohort and attrition_log remain in global environment

All claims verified. Plan complete.
