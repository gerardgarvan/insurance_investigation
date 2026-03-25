---
phase: 03-cohort-building
plan: 01
subsystem: cohort-predicates
tags: [cohort, filter-predicates, treatment-flags, named-functions]
dependencies:
  requires: [utils_icd.R, utils_attrition.R, 00_config.R, 02_harmonize_payer.R]
  provides: [cohort_predicates, treatment_flag_functions]
  affects: [04_build_cohort.R]
tech_stack:
  added: []
  patterns: [named-predicates, tibble-in-tibble-out, semi_join-filtering, conditional-schema-checks]
key_files:
  created:
    - R/03_cohort_predicates.R (6 named functions: 3 filters + 3 treatment flags)
  modified:
    - R/00_config.R (added TREATMENT_CODES list with 4 code vectors)
decisions:
  - Filter predicates use tibble-in/tibble-out pattern with semi_join for composability
  - Treatment flag functions return tibble of IDs with evidence (not filters)
  - TUMOR_REGISTRY1 schema handled separately (CHEMO_START_DATE_SUMMARY vs DT_CHEMO)
  - All functions log via message() + glue() for attrition visibility
metrics:
  duration_seconds: 142
  tasks_completed: 2
  files_created: 1
  files_modified: 1
  commits: 2
completed: 2026-03-25T04:35:44Z
---

# Phase 03 Plan 01: Cohort Predicates and Treatment Codes

**One-liner:** Filter predicates (has_hodgkin_diagnosis, with_enrollment_period, exclude_missing_payer) and treatment flag functions (has_chemo, has_radiation, has_sct) with TUMOR_REGISTRY schema-aware code detection

## What Was Built

Created the foundational building blocks for cohort filtering and treatment identification:

1. **TREATMENT_CODES configuration** — 4 code vectors (chemo_hcpcs, chemo_rxnorm, radiation_cpt, sct_cpt) defining CPT/HCPCS/RXNORM codes for treatment detection
2. **Filter predicates** — 3 tibble-in/tibble-out functions composable via pipe: has_hodgkin_diagnosis() (uses is_hl_diagnosis for ICD matching), with_enrollment_period() (any enrollment record), exclude_missing_payer() (removes NA/"Unknown"/"Unavailable")
3. **Treatment flag functions** — 3 lookup functions returning tibbles of patient IDs with treatment evidence: has_chemo() (TUMOR_REGISTRY dates + PROCEDURES HCPCS + PRESCRIBING RXNORM), has_radiation() (TR2/3 DT_RAD + PROCEDURES CPT), has_sct() (TR1 HEMATOLOGIC_TRANSPLANT + TR2/3 DT_HTE + PROCEDURES CPT)

All predicates log patient counts via message() + glue() for attrition visibility (CHRT-02). Filter predicates use semi_join (not inner_join) to preserve input tibble structure. Treatment functions handle TUMOR_REGISTRY1/2/3 schema differences with conditional column checks (TR1 has CHEMO_START_DATE_SUMMARY, TR2/3 have DT_CHEMO).

## Requirements Satisfied

| Requirement | Status | Evidence |
|-------------|--------|----------|
| CHRT-01 (named filter predicates) | ✓ Complete | 3 functions following has_*/with_*/exclude_* convention in 03_cohort_predicates.R |
| CHRT-02 (attrition visibility) | ✓ Complete | All 6 functions log patient counts via message() + glue() |
| CHRT-03 (ICD format matching) | ✓ Complete | has_hodgkin_diagnosis calls is_hl_diagnosis(DX, DX_TYPE) which normalizes ICD codes |

## Key Decisions

| Decision | Rationale | Impact |
|----------|-----------|--------|
| Tibble-in/tibble-out pattern for filters | Enables clean composition via %>% pipe, allows passing additional args (payer_summary) | Filter chain reads like clinical protocol: `df %>% has_hodgkin_diagnosis() %>% with_enrollment_period()` |
| Treatment flags return ID tibbles, not filter | Per D-02: treatment predicates identify, not exclude | Build script joins these to cohort; all HL patients retained regardless of treatment status |
| Conditional column checks for TUMOR_REGISTRY | TR1 schema differs from TR2/TR3 (CHEMO_START_DATE_SUMMARY vs DT_CHEMO) | Prevents runtime errors; handles multi-registry evidence gracefully |
| HCPCS for chemo supplemental evidence (not NDC) | PROCEDURES table has PX_TYPE="CH" for HCPCS; PRESCRIBING has RXNORM_CUI | Aligns with PCORnet CDM table structure; NDC in DISPENSING (not loaded in v1) |

## Files Modified

### Created
- **R/03_cohort_predicates.R** (278 lines)
  - `has_hodgkin_diagnosis()` — Filter to patients with HL diagnosis (149 codes via is_hl_diagnosis)
  - `with_enrollment_period()` — Filter to patients with enrollment records
  - `exclude_missing_payer()` — Filter to patients with valid payer category
  - `has_chemo()` — Returns tibble of IDs with chemo evidence (TR dates + PROCEDURES HCPCS + PRESCRIBING RXNORM)
  - `has_radiation()` — Returns tibble of IDs with radiation evidence (TR2/3 DT_RAD + PROCEDURES CPT)
  - `has_sct()` — Returns tibble of IDs with SCT evidence (TR1 HEMATOLOGIC + TR2/3 DT_HTE + PROCEDURES CPT)

### Modified
- **R/00_config.R** (60 lines added)
  - Added section 5.5: TREATMENT_CODES list
  - `chemo_hcpcs`: J-codes for ABVD regimen (J9000, J9040, J9360, J9130) + targeted agents (J9042, J9299)
  - `chemo_rxnorm`: CUIs for ABVD ingredients (3639, 11213, 67228, 3946)
  - `radiation_cpt`: 2026 complexity-based codes (77427, 77407, 77412, 77402)
  - `sct_cpt`: Autologous + allogeneic codes (38240, 38241, 38242, 38243)

## Deviations from Plan

None — plan executed exactly as written. All acceptance criteria met.

## Technical Notes

### TUMOR_REGISTRY Schema Differences

**TUMOR_REGISTRY1** (NAACCR format):
- Chemo: `CHEMO_START_DATE_SUMMARY` (column 288)
- Radiation: No DT_RAD column (has REASON_NO_RADIATION but no date)
- SCT: `HEMATOLOGIC_TRANSPLANT_AND_ENDOC` (column 307, code field not date)

**TUMOR_REGISTRY2/3** (cancer registry format):
- Chemo: `DT_CHEMO` (column 63)
- Radiation: `DT_RAD` (column 65)
- SCT: `DT_HTE` (column 69, hematologic transplant/endocrine date)

All treatment functions check `"COLUMN_NAME" %in% names(pcornet$TUMOR_REGISTRY*)` before filtering to avoid "column not found" errors.

### Treatment Code Sources

- **Radiation CPT**: CMS 2026 complexity-based codes (77385/77386 deleted 2026-01-01)
- **SCT CPT**: ASBMT coding guidelines (autologous 38241, allogeneic 38240)
- **Chemo HCPCS**: ABVD regimen (standard first-line HL treatment)
- **Chemo RXNORM**: Base ingredient CUIs for ABVD components

### Pattern: Tibble-in/Tibble-out vs ID Lookup

**Filter predicates** (has_*, with_*, exclude_*):
```r
has_hodgkin_diagnosis <- function(patient_df) {
  hl_patients <- pcornet$DIAGNOSIS %>% filter(...) %>% distinct(ID)
  patient_df %>% semi_join(hl_patients, by = "ID")
}
```
- Accept patient tibble, return filtered patient tibble
- Use `semi_join` to preserve input structure (no column addition)
- Composable via pipe

**Treatment flag functions** (has_chemo, has_radiation, has_sct):
```r
has_chemo <- function() {
  # Collect IDs from multiple sources
  chemo_ids <- c(tr1_chemo, tr2_chemo, px_chemo, rx_chemo)
  tibble(ID = unique(chemo_ids), HAD_CHEMO = 1L)
}
```
- No patient input, return tibble of IDs with evidence
- Build script joins to cohort: `left_join(cohort, has_chemo(), by = "ID") %>% replace_na(list(HAD_CHEMO = 0L))`
- Enables `left_join` pattern for 0/1 flags

## Known Stubs

None — all functions are fully implemented with conditional schema checks.

## Testing Notes

Filter predicates require upstream data from 01_load_pcornet.R and 02_harmonize_payer.R:
- `has_hodgkin_diagnosis()` needs pcornet$DIAGNOSIS and is_hl_diagnosis() from utils_icd.R
- `with_enrollment_period()` needs pcornet$ENROLLMENT
- `exclude_missing_payer()` needs payer_summary from 02_harmonize_payer.R

Treatment flag functions need pcornet$TUMOR_REGISTRY1/2/3, pcornet$PROCEDURES, pcornet$PRESCRIBING, and TREATMENT_CODES from 00_config.R.

No unit tests created (out of scope for v1). Manual validation in 04_build_cohort.R will verify counts.

## Integration Points

### Upstream Dependencies
- `R/00_config.R` — ICD_CODES, TREATMENT_CODES, auto-sources utilities
- `R/utils_icd.R` — is_hl_diagnosis(), normalize_icd()
- `R/01_load_pcornet.R` — pcornet$DIAGNOSIS, pcornet$ENROLLMENT, pcornet$TUMOR_REGISTRY*, pcornet$PROCEDURES, pcornet$PRESCRIBING
- `R/02_harmonize_payer.R` — payer_summary tibble

### Downstream Consumers
- `R/04_build_cohort.R` — Will compose filter chain and join treatment flags to build final cohort

### Usage Example
```r
source("R/02_harmonize_payer.R")  # Loads everything upstream
source("R/03_cohort_predicates.R")

# Compose filter chain
cohort <- pcornet$DEMOGRAPHIC %>%
  select(ID, SOURCE) %>%
  has_hodgkin_diagnosis() %>%
  with_enrollment_period() %>%
  exclude_missing_payer(payer_summary)

# Add treatment flags via left_join
cohort <- cohort %>%
  left_join(has_chemo(), by = "ID") %>%
  left_join(has_radiation(), by = "ID") %>%
  left_join(has_sct(), by = "ID") %>%
  replace_na(list(HAD_CHEMO = 0L, HAD_RADIATION = 0L, HAD_SCT = 0L))
```

## Self-Check: PASSED

### Files Created
- R/03_cohort_predicates.R: ✓ EXISTS (278 lines, 6 functions)

### Files Modified
- R/00_config.R: ✓ EXISTS (TREATMENT_CODES section added)

### Commits
- e019df6: ✓ EXISTS (feat(03-01): add TREATMENT_CODES to config)
- 4716af0: ✓ EXISTS (feat(03-01): create cohort predicates with filter and treatment flag functions)

### Function Verification
```bash
grep -c "has_hodgkin_diagnosis\|with_enrollment_period\|exclude_missing_payer\|has_chemo\|has_radiation\|has_sct" R/03_cohort_predicates.R
# Output: 17 (6 function definitions + doc comments)
```

All claims verified. Plan complete.
