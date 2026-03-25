# Phase 3: Cohort Building - Context

**Gathered:** 2026-03-24
**Status:** Ready for planning

<domain>
## Phase Boundary

Build HL cohort using named filter predicates with automatic attrition logging. Apply inclusion/exclusion criteria, extract treatment flags from TUMOR_REGISTRY + PROCEDURES/PRESCRIBING, and produce a final patient-level cohort dataset with demographics, payer, and treatment information. Visualization is a separate phase.

</domain>

<decisions>
## Implementation Decisions

### Filter chain steps & order
- **D-01:** Filter chain runs in this order: 1) `has_hodgkin_diagnosis()` -> 2) `with_enrollment_period()` -> 3) `exclude_missing_payer()` -> then tag treatment flags. Diagnosis-first is clinical standard
- **D-02:** Treatment predicates (`has_chemo()`, `has_radiation()`, `has_sct()`) are **identification flags** only, not exclusion filters. All HL patients with enrollment and valid payer remain in cohort regardless of treatment status
- **D-03:** `with_enrollment_period()` requires at least one enrollment record (any duration). The CONFIG$analysis$min_enrollment_days = 30 threshold stays in config for optional future use but is NOT enforced in v1
- **D-04:** `exclude_missing_payer()` removes patients where PAYER_CATEGORY_PRIMARY is NA, "Unknown", or "Unavailable" -- only patients with a concrete payer category (Medicare, Medicaid, Dual eligible, Private, Other government, No payment / Self-pay, Other) are retained

### Treatment flag extraction
- **D-05:** Treatment evidence comes from BOTH sources: TUMOR_REGISTRY date columns (DT_CHEMO, DT_RAD, DT_OTHER) as primary, supplemented by PROCEDURES/PRESCRIBING CPT/HCPCS/NDC codes for patients missing registry data
- **D-06:** Three treatment flags: HAD_CHEMO, HAD_RADIATION, HAD_SCT (integer 0/1)
- **D-07:** SCT flag covers both autologous and allogeneic stem cell transplant -- a single HAD_SCT flag, no type distinction
- **D-08:** Treatment CPT/NDC code lists defined in 00_config.R (TREATMENT_CODES list with chemo_cpt, radiation_cpt, sct_cpt, chemo_ndc vectors) -- consistent with existing ICD_CODES pattern

### Cohort output structure
- **D-09:** Final cohort is a "full clinical profile" per patient: ID, SOURCE, demographics (SEX, RACE, HISPANIC as PCORnet codes -- no recoding), age_at_enr_start, age_at_enr_end, first_hl_dx_date, payer fields (from payer_summary: PAYER_CATEGORY_PRIMARY, PAYER_CATEGORY_AT_FIRST_DX, DUAL_ELIGIBLE, PAYER_TRANSITION, N_ENCOUNTERS, N_ENCOUNTERS_WITH_PAYER), treatment flags (HAD_CHEMO, HAD_RADIATION, HAD_SCT), enrollment duration
- **D-10:** Age calculated as age at enrollment start and age at enrollment end (two columns: age_at_enr_start, age_at_enr_end), not raw BIRTH_DATE
- **D-11:** Cohort saved to CSV at output/cohort/hl_cohort.csv AND kept in R environment as `hl_cohort` tibble. Matches Phase 2 pattern (payer_summary.csv)

### Edge case handling
- **D-12:** Patients with HL diagnosis but NO enrollment record are excluded by `with_enrollment_period()`. Exclusion count logged in attrition waterfall
- **D-13:** Multi-site patients (appearing in multiple partner sites): Claude's discretion on handling approach based on data exploration and site characteristics
- **D-14:** Attrition logging uses existing init_attrition_log() + log_attrition() from utils_attrition.R. Tracks unique patient counts (ID), not row counts

### Claude's Discretion
- Multi-site patient deduplication strategy (D-13)
- Internal structure of predicate functions (tibble-in/tibble-out vs logical vector)
- Exact CPT/HCPCS/NDC code lists for treatment detection (populate TREATMENT_CODES in config)
- How to handle patients with treatment evidence but no diagnosis date
- Console output formatting for cohort summary

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Data schema
- `csv_columns.txt` -- Column listing for PCORnet CDM CSV files. Key tables for this phase: DIAGNOSIS (DX, DX_DATE, DX_TYPE), ENROLLMENT (ENR_START_DATE, ENR_END_DATE), DEMOGRAPHIC (BIRTH_DATE, SEX, RACE, HISPANIC), PROCEDURES (PX, PX_TYPE, PX_DATE), PRESCRIBING (RXNORM_CUI, RX_ORDER_DATE), TUMOR_REGISTRY1/2/3 (DATE_OF_DIAGNOSIS, DT_CHEMO, DT_RAD, DT_OTHER)

### Payer mapping reference
- `C:\cygwin64\home\Owner\Data loading and cleaing\docs\PAYER_VARIABLES_AND_CATEGORIES.md` -- Defines the 9-category payer system replicated in Phase 2. Needed to understand which categories D-04 excludes vs keeps

### Existing code (upstream dependencies)
- `R/00_config.R` -- ICD_CODES list, CONFIG$analysis params, PAYER_MAPPING, auto-sources utilities
- `R/01_load_pcornet.R` -- Loads pcornet$ENROLLMENT, pcornet$DIAGNOSIS, pcornet$DEMOGRAPHIC, pcornet$PROCEDURES, pcornet$PRESCRIBING, pcornet$TUMOR_REGISTRY1/2/3
- `R/02_harmonize_payer.R` -- Produces payer_summary tibble (patient-level payer assignments), encounters tibble, first_dx tibble
- `R/utils_icd.R` -- normalize_icd(), is_hl_diagnosis() for HL diagnosis matching (CHRT-03)
- `R/utils_attrition.R` -- init_attrition_log(), log_attrition() for cohort attrition tracking (CHRT-02)
- `R/utils_dates.R` -- parse_pcornet_date() for date parsing

### Architecture patterns
- `.planning/research/ARCHITECTURE.md` -- Named predicate pattern (has_*, with_*, exclude_*), numbered script pattern
- `.planning/phases/01-foundation-data-loading/01-CONTEXT.md` -- D-23: Script naming (03_cohort_predicates.R, 04_build_cohort.R), D-11: column names as-is, D-17: patient-level attrition
- `.planning/phases/02-payer-harmonization/02-CONTEXT.md` -- D-07: treatment flags deferred to Phase 3, D-10: first HL DX date from both DIAGNOSIS + TUMOR_REGISTRY, D-12: ICD normalization in utils_icd.R

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `R/utils_icd.R`: normalize_icd() and is_hl_diagnosis() -- ready for has_hodgkin_diagnosis() predicate, handles dotted/undotted ICD formats
- `R/utils_attrition.R`: init_attrition_log() and log_attrition() -- ready for CHRT-02 attrition logging
- `R/02_harmonize_payer.R`: payer_summary tibble (per-patient payer assignments), first_dx tibble (first HL diagnosis date per patient), encounters tibble (encounter-level payer data)
- `R/00_config.R`: ICD_CODES$hl_icd10 and ICD_CODES$hl_icd9 (149 HL codes), CONFIG$analysis params

### Established Patterns
- Named list storage: pcornet$TABLE_NAME for loaded data
- Patient ID column is `ID` across all tables
- SOURCE column = partner/site identifier (AMS, UMI, FLM, VRT)
- Scripts source their dependencies: 03 would source 02 which sources 01 which sources 00_config
- Console logging via message() + glue()
- CSV output via readr::write_csv()
- Named reusable functions (map_payer_category, compute_effective_payer, detect_dual_eligible) -- predicate functions should follow same pattern

### Integration Points
- Input: pcornet$DIAGNOSIS, pcornet$ENROLLMENT, pcornet$DEMOGRAPHIC, pcornet$PROCEDURES, pcornet$PRESCRIBING, pcornet$TUMOR_REGISTRY1/2/3
- Input: payer_summary tibble from 02_harmonize_payer.R
- Input: first_dx tibble from 02_harmonize_payer.R (first HL diagnosis dates)
- Output: hl_cohort tibble consumed by Phase 4 (visualization)
- Output: output/cohort/hl_cohort.csv for manual inspection
- Output: attrition_log data frame consumed by Phase 4 (waterfall chart)
- New config: TREATMENT_CODES list in 00_config.R

</code_context>

<specifics>
## Specific Ideas

- Treatment flags should combine TUMOR_REGISTRY dates (primary source) with PROCEDURES/PRESCRIBING codes (supplemental) for maximum coverage
- Age at enrollment start and enrollment end as two calculated columns, not raw BIRTH_DATE
- Filter chain order mirrors clinical protocol: identify disease -> validate enrollment -> confirm payer -> tag treatments
- Predicate naming follows project convention: has_* (inclusion), with_* (requires), exclude_* (exclusion)

</specifics>

<deferred>
## Deferred Ideas

None -- discussion stayed within phase scope

</deferred>

---

*Phase: 03-cohort-building*
*Context gathered: 2026-03-24*
