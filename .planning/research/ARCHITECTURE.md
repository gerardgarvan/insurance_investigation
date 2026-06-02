# Architecture Integration: v2.1 Clinical Data Refinements & NLPHL Breakout

**Project:** PCORnet Payer Variable Investigation (R Pipeline)
**Milestone:** v2.1 Clinical Data Refinements & NLPHL Breakout
**Researched:** 2026-06-02

## Executive Summary

v2.1 adds **8 clinical data refinement features** to the existing v2.0 R pipeline. The architecture is mature (69 numbered scripts, DuckDB backend, encounter-level cancer linkage, first-line regimen detection) with well-defined integration points. All v2.1 features integrate cleanly without breaking changes.

**Integration strategy:** Modify existing scripts where logical (cancer summary, episode classification), add new scripts for investigations (SCT 0362, replaced-by codes), extend configuration for NLPHL breakout.

**Build order:** 3 waves — (1) config extensions (NLPHL, cause of death), (2) core modifications (cancer summary, episode classification, treatment filtering), (3) investigations and new tables.

**Critical integration points:** R/00_config.R (CANCER_SITE_MAP), R/utils/utils_cancer.R (classify_codes), R/49_cancer_summary_pre_post.R (7-day gap logic), R/28_episode_classification.R (cancer_category per episode), treatment episode pipeline (tumor registry removal).

**Risk assessment:** LOW. Most features are additive (new columns, new outputs). Only breaking change is tumor registry treatment removal (affects 7 scripts, well-isolated via source filtering).

---

## v2.1 Feature Mapping to Architecture

| Feature | Type | Integration Point | New vs Modified | Complexity |
|---------|------|-------------------|-----------------|------------|
| **1. NLPHL breakout** | Category addition | R/00_config.R CANCER_SITE_MAP, utils_cancer.R | MODIFY existing | Medium |
| **2. 7-day gap for ALL cancers** | Logic change | R/49 cancer_summary_pre_post.R | MODIFY existing | Low |
| **3. Drop tumor registry treatment** | Source filtering | R/26-29 treatment episode pipeline | MODIFY existing (7 scripts) | Medium |
| **4. SCT 0362 investigation** | Diagnostic | NEW R/9x_investigate_sct_0362.R | NEW script | Low |
| **5. Replaced-by codes verification** | Validation | NEW R/9x_verify_replaced_by_codes.R | NEW script | Low |
| **6. New tables from xlsx** | Output generation | NEW R/7x_new_tables_from_groupings.R | NEW script | Medium |
| **7. Cause of death in outputs** | Column addition | R/52_gantt_v2_export.R, death integration | MODIFY existing | Low |
| **8. Per-episode cancer_category** | Column addition | R/28_episode_classification.R, Gantt outputs | MODIFY existing | Low |

**Summary:** 3 new scripts, 9+ modified scripts, 2 configuration extensions.

---

## Data Flow Changes

### Current v2.0 Data Flow

```
R/00_config.R (CANCER_SITE_MAP: 324 prefixes → 15 categories including "Hodgkin Lymphoma")
    ↓
R/01_load_pcornet.R (DuckDB connection, get_pcornet_table dispatcher)
    ↓
R/26_treatment_episodes.R (7 sources: PROCEDURES, PRESCRIBING, DISPENSING, MED_ADMIN, ENCOUNTER DRG, DIAGNOSIS, TUMOR_REGISTRY)
    ↓
R/28_episode_classification.R (encounter-level cancer linkage → cancer_category per episode)
    ↓
R/49_cancer_summary_pre_post.R (7-day gap for HL only, total = 6,347)
    ↓
R/52_gantt_v2_export.R (14 columns including cancer_category, regimen_label, is_first_line)
```

### v2.1 Data Flow Changes

```
R/00_config.R (CANCER_SITE_MAP: C81.0 → "NLPHL", C81.1-C81.9 → "Hodgkin Lymphoma (non-NLPHL)")
    ↓
    NEW: DEATH_CAUSE_MAP (ICD-10 cause of death categories)
    ↓
R/01_load_pcornet.R (unchanged, DuckDB still primary backend)
    ↓
R/26_treatment_episodes.R (6 sources: TUMOR_REGISTRY REMOVED, only PROCEDURES, PRESCRIBING, DISPENSING, MED_ADMIN, ENCOUNTER DRG, DIAGNOSIS)
    ↓
    MODIFIED: extract_*_dates_with_codes() functions — filter out TUMOR_REGISTRY sources
    ↓
R/28_episode_classification.R (unchanged linkage logic, NEW: triggering_code_description via drug groupings xlsx)
    ↓
    NEW OUTPUT COLUMNS: triggering_code_description (human-readable)
    ↓
R/49_cancer_summary_pre_post.R (7-day gap for ALL cancer categories, total = 6,347)
    ↓
    MODIFIED: Remove HL-only filter, apply 7-day separation to C81, C82, C50, etc.
    ↓
R/52_gantt_v2_export.R (15 columns: +cause_of_death)
    ↓
    NEW: Left join DEATH table for DEATH_CAUSE, map via DEATH_CAUSE_MAP
    ↓
NEW R/9x_investigate_sct_0362.R (diagnostic: 90 patients with code 0362 → do they have other SCT codes?)
NEW R/9x_verify_replaced_by_codes.R (validation: check all_codes_resolved_next_tables.xlsx "replaced by" mappings)
NEW R/7x_new_tables_from_groupings.R (generate 2 new tables using drug groupings from xlsx)
```

**Key changes:**
1. CANCER_SITE_MAP gains NLPHL as 16th category
2. Treatment episode sources reduced from 7 to 6
3. Cancer summary 7-day logic generalized from HL-only to all cancers
4. Gantt v2 gains cause_of_death column (17 total)
5. Episode classification gains triggering_code_description

---

## Integration Points by Component

### 1. Configuration Layer (R/00_config.R)

**Current state:**
```r
CANCER_SITE_MAP <- c(
  "C81" = "Hodgkin Lymphoma",  # 324 prefixes total
  "C82" = "Non-Hodgkin Lymphoma",
  # ... 322 more entries
)

ICD_CODES <- list(
  hl_icd10 = c("C81.00", "C81.01", ..., "C81.9A"),  # 77 codes
  hl_icd9 = c("201", "201.0", ..., "201.98")        # 81 codes
)
```

**v2.1 modifications:**
```r
# NLPHL BREAKOUT (Feature 1)
CANCER_SITE_MAP <- c(
  "C810" = "NLPHL",                         # NEW: Nodular lymphocyte predominant HL
  "C81" = "Hodgkin Lymphoma (non-NLPHL)",   # MODIFIED: Renamed, still catches C81.1-C81.9
  # ... rest unchanged
)

# ICD-9 NLPHL mapping (201.4x series)
ICD9_NLPHL_CODES <- c("201.4", "201.40", "201.41", ..., "201.48")  # NEW constant

# CAUSE OF DEATH (Feature 7)
DEATH_CAUSE_MAP <- c(
  "C81" = "Hodgkin Lymphoma",
  "C82" = "Non-Hodgkin Lymphoma",
  "C50" = "Breast cancer",
  "I21" = "Acute myocardial infarction",
  "J44" = "Chronic obstructive pulmonary disease",
  # ... comprehensive ICD-10 cause mapping from all_codes_resolved_next_tables.xlsx
)
```

**Impact:**
- `classify_codes()` automatically returns "NLPHL" for C81.0x codes
- Downstream scripts (R/28, R/40-R/53) inherit new category via CANCER_SITE_MAP
- DEATH_CAUSE_MAP enables human-readable cause of death in Gantt outputs

**Files modified:** R/00_config.R (add NLPHL mapping, add DEATH_CAUSE_MAP, add ICD9_NLPHL_CODES)

**Dependencies:** R/utils/utils_cancer.R (no code change needed — classify_codes uses CANCER_SITE_MAP dynamically)

---

### 2. Cancer Classification (R/utils/utils_cancer.R)

**Current state:**
```r
classify_codes <- function(codes) {
  prefix3 <- substr(codes, 1, 3)  # "C810" → "C81"
  categories <- unname(CANCER_SITE_MAP[prefix3])
  categories
}
```

**v2.1 modification:**
```r
classify_codes <- function(codes) {
  # NLPHL requires 4-char match (C810), others use 3-char prefix
  prefix4 <- substr(codes, 1, 4)
  prefix3 <- substr(codes, 1, 3)

  # Try 4-char first (NLPHL: C810), fallback to 3-char
  categories <- unname(CANCER_SITE_MAP[prefix4])
  idx_na <- is.na(categories)
  if (any(idx_na)) {
    categories[idx_na] <- unname(CANCER_SITE_MAP[prefix3[idx_na]])
  }
  categories
}
```

**Files modified:** R/utils/utils_cancer.R (modify classify_codes for 4-char prefix support)

**Testing:** Verify C81.00 → "NLPHL", C81.10 → "Hodgkin Lymphoma (non-NLPHL)"

---

### 3. Cancer Summary 7-Day Logic (R/49_cancer_summary_pre_post.R)

**Current state (HL-only 7-day filter):**
```r
# Lines 116-127 (excerpt)
n_c81_7day <- hl_c81_with_date %>%
  distinct(ID, DX_DATE) %>%
  group_by(ID) %>%
  filter(n() >= 2, as.numeric(max(DX_DATE) - min(DX_DATE)) >= 7) %>%
  ungroup() %>%
  pull(ID) %>%
  n_distinct()

message(glue("  With 2+ unique dates, 7-day span:      {format(n_c81_7day, big.mark=',')}"))
```

**v2.1 modification (ALL cancers 7-day filter):**
```r
# Generalize to all cancer categories (C81, C82, C50, etc.)
cancer_7day_per_category <- dx_raw %>%
  filter(!is.na(DX_DATE)) %>%
  mutate(category = classify_codes(DX_norm)) %>%
  filter(!is.na(category)) %>%
  distinct(ID, category, DX_DATE) %>%
  group_by(ID, category) %>%
  filter(n() >= 2, as.numeric(max(DX_DATE) - min(DX_DATE)) >= 7) %>%
  ungroup()

n_patients_any_7day <- cancer_7day_per_category %>%
  distinct(ID) %>%
  nrow()

message(glue("  Patients with 7-day separation (any cancer): {format(n_patients_any_7day, big.mark=',')}"))
message(glue("  Expected total: 6,347 (per requirement)"))

# Per-category breakdown
cancer_7day_summary <- cancer_7day_per_category %>%
  group_by(category) %>%
  summarize(
    n_patients = n_distinct(ID),
    n_date_pairs = n()
  ) %>%
  arrange(desc(n_patients))

message("\n7-day separation by category:")
print(cancer_7day_summary, n = Inf)
```

**Impact:**
- Total population changes from HL-only subset to all confirmed cohort
- Expected total = 6,347 (requirement states this explicitly)
- Output table gains per-category 7-day confirmation metrics

**Files modified:** R/49_cancer_summary_pre_post.R (generalize 7-day logic, update total population filter)

**Testing:** Verify total = 6,347, verify NLPHL appears as separate category in output

---

### 4. Treatment Episode Pipeline — Tumor Registry Removal (R/26-R/29)

**Current state (7 sources):**
```r
# R/26_treatment_episodes.R lines 118-149
extract_chemo_dates_with_codes <- function() {
  # 1. PROCEDURES
  # 2. PRESCRIBING
  # 3. DIAGNOSIS (Z51.11/Z51.12)
  # 4. DISPENSING
  # 5. MED_ADMIN
  # 6. ENCOUNTER (DRG codes)
  # 7. TUMOR_REGISTRY (DT_CHEMO, DT_RAD, etc.)  <-- REMOVE THIS

  stack_and_dedup_with_codes(sources, "Chemotherapy")
}
```

**v2.1 modification (6 sources):**
```r
extract_chemo_dates_with_codes <- function() {
  # 1-6 unchanged

  # 7. TUMOR_REGISTRY — REMOVED per v2.1 requirement
  # Tumor registry dates are unreliable for treatment episode detection
  # (documented in v2.1 milestone requirements)

  # tr_dates <- NULL  # Commented out or deleted

  sources <- list(
    procedures = px_dates,
    prescribing = rx_dates,
    diagnosis = dx_dates,
    dispensing = disp_dates,
    med_admin = ma_dates,
    encounter_drg = enc_dates
    # tumor_registry = tr_dates  # REMOVED
  )

  stack_and_dedup_with_codes(sources, "Chemotherapy")
}
```

**Affected scripts:**
1. **R/26_treatment_episodes.R** — extract_chemo_dates_with_codes, extract_radiation_dates_with_codes, extract_sct_dates_with_codes (3 functions)
2. **R/27_drug_name_resolution.R** — May reference treatment_episodes.rds (no change needed if episodes.rds format unchanged)
3. **R/28_episode_classification.R** — Uses treatment_episodes.rds (no change needed)
4. **R/29_first_line_and_death_analysis.R** — Uses treatment_episodes.rds (no change needed)

**Impact:**
- Episode counts will decrease (tumor registry was supplemental source)
- No schema change to treatment_episodes.rds
- Backward compatible (existing outputs still valid, just fewer episodes)

**Files modified:** R/26_treatment_episodes.R (remove tumor registry extraction for chemo, radiation, SCT)

**Testing:**
- Count episodes before/after tumor registry removal
- Verify no episodes with `source_table = "TUMOR_REGISTRY"` in triggering_codes
- Verify episode start/stop dates still valid (no NA episodes)

---

### 5. Episode-Level Cancer Category & Triggering Code Description (R/28_episode_classification.R)

**Current state:**
```r
# Output columns (14 total)
episodes_enriched <- episodes %>%
  # ... cancer linkage logic ...
  select(
    patient_id, treatment_type, episode_number, episode_start, episode_stop,
    episode_length_days, distinct_dates_in_episode, historical_flag,
    triggering_codes, ENCOUNTERID, cancer_category, cancer_link_method,
    is_hodgkin, regimen_label
  )
```

**v2.1 modification (add triggering_code_description):**
```r
# NEW: Load drug groupings from all_codes_resolved_next_tables.xlsx
drug_groupings <- readxl::read_excel(
  file.path(CONFIG$data_dir, "all_codes_resolved_next_tables.xlsx"),
  sheet = "Drug Groupings"
) %>%
  select(code, description = drug_grouping)

# Join triggering codes with descriptions
episodes_enriched <- episodes %>%
  # ... existing cancer linkage ...
  mutate(
    # Extract first code from comma-separated triggering_codes
    primary_triggering_code = str_extract(triggering_codes, "^[^,]+")
  ) %>%
  left_join(drug_groupings, by = c("primary_triggering_code" = "code")) %>%
  rename(triggering_code_description = description) %>%
  select(
    patient_id, treatment_type, episode_number, episode_start, episode_stop,
    episode_length_days, distinct_dates_in_episode, historical_flag,
    triggering_codes, triggering_code_description,  # NEW COLUMN
    ENCOUNTERID, cancer_category, cancer_link_method,
    is_hodgkin, regimen_label
  )
```

**Files modified:** R/28_episode_classification.R (add drug groupings join, new column)

**New dependency:** `all_codes_resolved_next_tables.xlsx` must exist in data directory

**Testing:**
- Verify triggering_code_description not NA for common chemo codes (J9000, J9360, etc.)
- Verify NLPHL episodes have correct cancer_category

---

### 6. Cause of Death in Gantt Outputs (R/52_gantt_v2_export.R)

**Current state (14 columns):**
```r
gantt_v2 <- treatment_episodes %>%
  select(
    patient_id, treatment_type, episode_number, episode_start, episode_stop,
    episode_length_days, distinct_dates_in_episode, historical_flag,
    triggering_codes, ENCOUNTERID, cancer_category, regimen_label,
    is_first_line, death_date
  )
```

**v2.1 modification (15 columns with cause_of_death):**
```r
# Load DEATH table (has ID, DEATH_DATE, DEATH_CAUSE)
death_tbl <- get_pcornet_table("DEATH") %>%
  select(ID, DEATH_DATE, DEATH_CAUSE) %>%
  collect()

# Map DEATH_CAUSE (ICD-10) to human-readable category
death_with_category <- death_tbl %>%
  mutate(
    cause_prefix3 = substr(DEATH_CAUSE, 1, 3),
    cause_of_death = unname(DEATH_CAUSE_MAP[cause_prefix3])
  ) %>%
  select(ID, death_date = DEATH_DATE, cause_of_death)

# Join to Gantt data
gantt_v2 <- treatment_episodes %>%
  left_join(death_with_category, by = c("patient_id" = "ID")) %>%
  select(
    patient_id, treatment_type, episode_number, episode_start, episode_stop,
    episode_length_days, distinct_dates_in_episode, historical_flag,
    triggering_codes, ENCOUNTERID, cancer_category, regimen_label,
    is_first_line, death_date, cause_of_death  # NEW COLUMN
  )
```

**Files modified:** R/52_gantt_v2_export.R (join DEATH table, add cause_of_death column)

**New dependency:** R/00_config.R must define DEATH_CAUSE_MAP

**Testing:**
- Verify cause_of_death populated for known deaths
- Verify NA for patients without death records
- Verify "Hodgkin Lymphoma" appears for C81.x death causes

---

## Suggested Build Order

### Wave 1: Configuration & Utilities (Foundation)
**Goal:** Extend configuration for NLPHL and cause of death, update classification logic

1. **R/00_config.R**
   - Add NLPHL to CANCER_SITE_MAP (C810 = "NLPHL", C81 = "Hodgkin Lymphoma (non-NLPHL)")
   - Add ICD9_NLPHL_CODES (201.4x series)
   - Add DEATH_CAUSE_MAP (ICD-10 cause categories)

2. **R/utils/utils_cancer.R**
   - Modify `classify_codes()` for 4-char prefix support (C810 before C81)
   - Add unit tests (optional): verify C81.00 → "NLPHL", C81.10 → "Hodgkin Lymphoma (non-NLPHL)"

**Success criteria:**
- `classify_codes(c("C8100", "C8110"))` returns `c("NLPHL", "Hodgkin Lymphoma (non-NLPHL)")`
- DEATH_CAUSE_MAP has 50+ entries covering major ICD-10 categories

**Estimated effort:** 1-2 hours

---

### Wave 2: Core Modifications (Data Processing)
**Goal:** Modify existing scripts for 7-day gap generalization, tumor registry removal, episode enrichment

3. **R/49_cancer_summary_pre_post.R**
   - Generalize 7-day logic from HL-only to all cancer categories
   - Verify total population = 6,347
   - Add per-category 7-day breakdown to output

4. **R/26_treatment_episodes.R**
   - Remove tumor registry extraction from `extract_chemo_dates_with_codes()`
   - Remove tumor registry extraction from `extract_radiation_dates_with_codes()`
   - Remove tumor registry extraction from `extract_sct_dates_with_codes()`
   - Update source count in script header (7 → 6 sources)

5. **R/28_episode_classification.R**
   - Load `all_codes_resolved_next_tables.xlsx` (Drug Groupings sheet)
   - Join triggering_codes with drug_groupings for `triggering_code_description`
   - Add column to output schema (14 → 15 columns)

6. **R/52_gantt_v2_export.R**
   - Load DEATH table via get_pcornet_table("DEATH")
   - Join DEATH_CAUSE and map via DEATH_CAUSE_MAP
   - Add `cause_of_death` column to Gantt v2 CSV/xlsx (14 → 15 columns)

**Success criteria:**
- R/49 output shows 7-day separation for NLPHL, HL (non-NLPHL), NHL, Breast, etc.
- R/26 output has no episodes with `source_table = "TUMOR_REGISTRY"`
- R/28 output has triggering_code_description populated for common codes
- R/52 output has cause_of_death for patients with death records

**Estimated effort:** 4-6 hours

---

### Wave 3: Investigations & New Tables (Additive)
**Goal:** Create new diagnostic and output scripts

7. **NEW R/92_investigate_sct_0362.R**
   - Query PROCEDURES for 90 patients with code 0362
   - Find all SCT codes on same encounters
   - Output CSV with encounter-level summary

8. **NEW R/93_verify_replaced_by_codes.R**
   - Load `all_codes_resolved_next_tables.xlsx` (Replaced By sheet)
   - Verify replaced_by_code in TREATMENT_CODES
   - Query PROCEDURES for actual usage
   - Output verification CSV

9. **NEW R/76_new_tables_from_groupings.R**
   - Load `all_codes_resolved_next_tables.xlsx` (Drug Groupings, Table Template sheets)
   - Generate 2 tables (structure TBD based on xlsx)
   - Output multi-sheet xlsx

**Success criteria:**
- R/92 output identifies other SCT codes for 0362 patients
- R/93 output confirms replaced-by codes are valid
- R/76 output has 2 tables matching template structure

**Estimated effort:** 3-4 hours

---

### Wave 4: Smoke Test & Documentation Updates
**Goal:** Verify integration, update documentation

10. **R/88_smoke_test_comprehensive.R**
    - Add tests for new scripts (R/76, R/92, R/93)
    - Verify NLPHL category appears in cancer outputs
    - Verify Gantt v2 has 15 columns (not 14)

11. **Documentation updates**
    - Update SCRIPT_INDEX.md with new scripts
    - Update PROJECT.md requirements (mark v2.1 features as Validated)
    - Update ROADMAP.md with v2.1 phase completion

**Success criteria:**
- Smoke test passes for all new/modified scripts
- Documentation reflects v2.1 architecture changes

**Estimated effort:** 1-2 hours

---

## Total Estimated Effort: 10-15 hours

---

## Risk Assessment & Mitigation

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| **NLPHL 4-char prefix breaks other classifications** | Low | High | Test classify_codes extensively; 4-char tries before 3-char fallback |
| **Tumor registry removal reduces episode counts to zero** | Low | Medium | Verify 6 sources (PROCEDURES, PRESCRIBING, etc.) still produce episodes |
| **7-day gap for all cancers excludes too many patients** | Medium | Medium | Validate total = 6,347 matches requirement exactly |
| **all_codes_resolved_next_tables.xlsx missing required sheets** | Medium | High | Check xlsx structure before coding; create fallback logic |
| **Cause of death ICD-10 mapping incomplete** | Medium | Low | Start with top 20 causes, expand iteratively |
| **Gantt v2 schema change breaks downstream tools** | Low | Medium | Version Gantt files (gantt_v2.csv → gantt_v2.1.csv) if schema change |

**Overall risk: LOW** — Most changes are additive. Only breaking change is tumor registry removal (well-isolated).

---

## Sources

### Internal Documentation
- PROJECT.md (v2.1 requirements)
- R/00_config.R (CANCER_SITE_MAP structure)
- R/utils/utils_cancer.R (classify_codes implementation)
- R/26_treatment_episodes.R (treatment source extraction)
- R/28_episode_classification.R (episode enrichment)
- R/49_cancer_summary_pre_post.R (7-day logic)
- R/52_gantt_v2_export.R (output schema)

### External References
- ICD-10-CM 2025: C81.0 = Nodular lymphocyte predominant Hodgkin lymphoma (NLPHL)
- ICD-9-CM: 201.4x = Lymphocytic-histiocytic predominance (NLPHL historical code)
- WHO ICD-O-3: Histology 9659 = Nodular lymphocyte predominant Hodgkin lymphoma

**Confidence:** **HIGH** — All integration points identified from existing codebase. NLPHL breakout verified against ICD-10-CM official classification. Build order considers dependencies (config before classification before outputs).
