# Architecture Integration: v1.7 Cancer Summary Refinement & Gantt Enhancements

**Project:** PCORnet Payer Variable Investigation (R Pipeline)
**Researched:** 2026-05-22
**Milestone:** v1.7 Cancer Summary Refinement & Gantt Enhancements

## Executive Summary

The v1.7 features integrate cleanly into the existing numbered-script architecture with minimal cross-cutting changes. Key integration points:

- **Benign D-code removal**: Filter in existing R/53 + R/54 cancer summary scripts (PREFIX_MAP edit)
- **HL cohort confirmation**: New script R/56 applies 7-day filter, writes confirmed cohort RDS, then re-runs R/53 + R/54 with cohort join
- **Post-HL cancer filtering**: R/53 variant reads first_hl_dx_date from cohort, filters DIAGNOSIS dates
- **Gantt cancer category labels**: R/49 enhancement reads cancer_summary.csv, joins on code → category, adds is_hodgkin flag
- **Death date integration**: R/00_config.R gets DEATH table path, R/49 joins death_date, exports as pseudo-treatment-type

**Critical architectural insight:** The numbered-script pattern supports variants (R/53a, R/54a for post-HL filtering) and composable enhancement (R/49 extends without touching R/44a episode generation).

## Current Architecture Overview

### Component Structure

```
R/00_config.R              Centralized configuration (TREATMENT_CODES, PREFIX_MAP, AMC_PAYER_LOOKUP, DuckDB paths)
R/01_load_pcornet.R        DuckDB backend dispatcher (get_pcornet_table, USE_DUCKDB flag)
R/utils_*.R                Shared helpers (treatment, payer, pptx)

R/04_build_cohort.R        HL cohort with HL_SOURCE flag (DIAGNOSIS + TR detection)
R/53_cancer_summary.R      Patient-code cancer summary (DIAGNOSIS → cancer_summary.csv)
R/54_cancer_summary_table.R Category/code aggregation (cancer_summary.csv → summary table)
R/50_cancer_site_confirmation.R 2-date confirmation (separate from R/53/54 pipeline)
R/51_cancer_site_confirmation_7day.R 7-day separation confirmation

R/44a_treatment_episodes.R Episode start/stop/length with triggering_codes
R/48b_build_code_descriptions.R Code → human-readable description lookup (4 sources)
R/49_gantt_data_export.R   Gantt CSV export (episodes + detail with descriptions)

DuckDB:                    13 tables (ENROLLMENT, DIAGNOSIS, PROCEDURES, DEMOGRAPHIC, TR1/2/3, etc.)
Outputs:
  output/tables/           xlsx/csv outputs
  output/rds/              Intermediate RDS artifacts
  /blue/.../rds/cohort/    Cohort snapshots (step-by-step)
```

### Data Flow (Current)

```
DIAGNOSIS (DuckDB)
  → R/53_cancer_summary.R → cancer_summary.csv (patient-code level, all patients)
  → R/54_cancer_summary_table.R → cancer_summary_table.xlsx (category/code aggregates)

DIAGNOSIS + TR
  → R/04_build_cohort.R → hl_cohort (HL_SOURCE flag, with_enrollment_period)

PROCEDURES + PRESCRIBING + DIAGNOSIS + ENCOUNTER + TR
  → R/44a_treatment_episodes.R → treatment_episodes.rds (episode start/stop + triggering_codes)
  → R/49_gantt_data_export.R → gantt_episodes.csv + gantt_detail.csv
```

## Integration Points for v1.7 Features

### 1. Benign D-Code Removal (Filter in R/53 + R/54)

**Integration:** Modify PREFIX_MAP in R/53 + R/54 to exclude D10-D36 benign prefixes.

**Components affected:**
- **MODIFY:** R/53_cancer_summary.R, lines 59-319 (PREFIX_MAP definition)
- **MODIFY:** R/54_cancer_summary_table.R, lines 51-311 (PREFIX_MAP definition, duplicated from R/53)

**Data flow:**
```
DIAGNOSIS (ICD-10, DX_TYPE == "10")
  → filter(str_detect(DX_norm, "^[CD]"))  # Unchanged
  → classify_codes(DX_norm)                # Uses PREFIX_MAP
  → [NEW] filter(!category %in% c("Benign Neoplasms", "In Situ Neoplasms"))  # Add after line 360 in R/53
  → cancer_summary.csv
```

**Why this works:** PREFIX_MAP is a static lookup table duplicated in R/53 and R/54 for script independence. Removing D-code entries (lines 260-296 in both scripts) prevents those codes from being classified, and an additional filter removes rows classified into those categories.

**Build order:**
1. Edit PREFIX_MAP in both scripts (remove D10-D36 entries)
2. Add explicit category filter after line 360 (R/53) and after line 344 (R/54)
3. Re-run R/53 → R/54 to regenerate outputs

**Pitfall to avoid:** PREFIX_MAP is duplicated in 3 scripts (R/47, R/53, R/54). Must edit all 3 to maintain consistency, OR extract to shared utility module.

---

### 2. HL Cohort Confirmation (2+ HL codes 7 days apart)

**Integration:** New script R/56 filters cohort to confirmed HL patients, writes confirmed_cohort.rds, then re-runs R/53 + R/54 with inner join.

**New component:**
- **CREATE:** R/56_hl_cohort_confirmation.R (builds on R/51 7-day logic)

**Data flow:**
```
DIAGNOSIS (HL codes only)
  → group_by(ID, DX_norm)
  → filter(n_distinct(DX_DATE[!is.na(DX_DATE)]) >= 2)
  → filter(max(DX_DATE) - min(DX_DATE) >= 7)
  → distinct(ID)
  → confirmed_hl_cohort.rds

DIAGNOSIS (all neoplasm codes)
  → R/53 with inner_join(confirmed_hl_cohort, by = "ID")  # Filter to confirmed patients only
  → cancer_summary.csv
```

**Why this works:** R/04_build_cohort.R already has HL detection logic (lines 66-138) that builds `HL_SOURCE` flag. R/56 reuses this pattern but adds 7-day separation requirement (from R/51 pattern), then writes a simple ID list.

**Build order:**
1. Create R/56_hl_cohort_confirmation.R (reads DIAGNOSIS, writes confirmed_hl_cohort.rds)
2. Modify R/53 to accept optional cohort_filter_rds parameter (default NULL = all patients)
3. Modify R/54 input validation to check if cancer_summary.csv is cohort-filtered
4. Run R/56 → R/53 → R/54

**Integration with R/53:** Add parameter to script:
```r
# In R/53, after line 42:
COHORT_FILTER_RDS <- Sys.getenv("COHORT_FILTER_RDS", unset = "")
confirmed_cohort <- if (COHORT_FILTER_RDS != "" && file.exists(COHORT_FILTER_RDS)) {
  readRDS(COHORT_FILTER_RDS)
} else {
  NULL
}

# Before line 344 (after collecting dx_cancer):
if (!is.null(confirmed_cohort)) {
  dx_cancer <- dx_cancer %>% inner_join(confirmed_cohort %>% select(ID), by = "ID")
  message(glue("  Filtered to confirmed cohort: {n_distinct(dx_cancer$ID)} patients"))
}
```

**Alternative:** Simpler approach — create R/53b + R/54b variants that hardcode the cohort filter. Avoids environment variable complexity.

---

### 3. Post-HL Cancer Filtering (Cancers after first HL diagnosis)

**Integration:** R/53 variant reads first_hl_dx_date from cohort/confirmed_hl_cohort.rds (extended with date column), filters DX_DATE > first_hl_dx_date.

**New components:**
- **CREATE:** R/53a_cancer_summary_post_hl.R (variant of R/53)
- **CREATE:** R/54a_cancer_summary_table_post_hl.R (variant of R/54)
- **MODIFY:** R/56_hl_cohort_confirmation.R to export first_hl_dx_date column

**Data flow:**
```
DIAGNOSIS (HL codes)
  → R/56 → confirmed_hl_cohort.rds with columns: ID, first_hl_dx_date

DIAGNOSIS (all neoplasm codes)
  → R/53a loads confirmed_hl_cohort.rds
  → inner_join(confirmed_hl_cohort, by = "ID")
  → filter(DX_DATE > first_hl_dx_date)  # Temporal filter
  → cancer_summary_post_hl.csv
  → R/54a → cancer_summary_table_post_hl.xlsx
```

**Why this works:** The variant pattern (a/b suffix) is established in the codebase (R/44a, R/44b for episode tests). R/53a is a fork of R/53 with:
- Input: confirmed_hl_cohort.rds (with first_hl_dx_date)
- Filter: DX_DATE > first_hl_dx_date before aggregation
- Output: cancer_summary_post_hl.csv

**Build order:**
1. Modify R/56 to compute first_hl_dx_date (min DX_DATE per patient among HL codes)
2. Copy R/53 → R/53a, add temporal filter at line 345 (after dx_cancer created)
3. Copy R/54 → R/54a, update input path to cancer_summary_post_hl.csv
4. Run R/56 → R/53a → R/54a

**Code change in R/53a (after line 344):**
```r
# Load confirmed HL cohort with first diagnosis dates
confirmed_hl_cohort <- readRDS(file.path(CONFIG$cache$cohort_dir, "confirmed_hl_cohort.rds"))

# Filter to confirmed patients AND post-HL diagnosis dates
dx_cancer <- dx_cancer %>%
  inner_join(confirmed_hl_cohort %>% select(ID, first_hl_dx_date), by = "ID") %>%
  filter(DX_DATE > first_hl_dx_date)

message(glue("  Post-HL filter: {n_distinct(dx_cancer$ID)} patients, {nrow(dx_cancer)} rows"))
```

**Comparison output:** Run both R/53 + R/54 (all cancers) and R/53a + R/54a (post-HL only) to produce side-by-side comparison tables.

---

### 4. Gantt Cancer Category Labels (Treatment episodes → cancer category)

**Integration:** R/49_gantt_data_export.R reads cancer_summary.csv, joins on triggering_code → cancer_code, adds category + is_hodgkin columns.

**Components affected:**
- **MODIFY:** R/49_gantt_data_export.R (add cancer category join logic)

**Data flow:**
```
treatment_episode_detail.rds (patient_id, treatment_date, triggering_code)
  → R/49 loads cancer_summary.csv
  → join on (patient_id, triggering_code) = (ID, cancer_code)
  → add columns: cancer_category, is_hodgkin
  → gantt_detail.csv (with cancer_category, is_hodgkin)

treatment_episodes.rds (patient_id, triggering_codes comma-separated)
  → R/49 splits triggering_codes → one category per episode (most frequent)
  → add columns: cancer_category, is_hodgkin
  → gantt_episodes.csv (with cancer_category, is_hodgkin)
```

**Why this works:** cancer_summary.csv (from R/53) contains (ID, cancer_code, category). R/49 already loads code_descriptions.rds for human-readable labels. Same pattern applies for cancer categories.

**Build order:**
1. Modify R/49 to read cancer_summary.csv after line 71 (after loading detail RDS)
2. Join detail_export with cancer_summary on (patient_id, triggering_code) = (ID, cancer_code)
3. Add is_hodgkin flag: `is_hodgkin = (cancer_category == "Hodgkin Lymphoma")`
4. For episodes: aggregate triggering_codes → most frequent category per episode
5. Re-run R/49 to regenerate Gantt CSVs

**Code change in R/49 (after line 111):**
```r
# Load cancer summary for category mapping
CANCER_SUMMARY_CSV <- file.path(CONFIG$output_dir, "tables", "cancer_summary.csv")
if (file.exists(CANCER_SUMMARY_CSV)) {
  cancer_summary <- read.csv(CANCER_SUMMARY_CSV, stringsAsFactors = FALSE) %>%
    select(ID, cancer_code, description) %>%
    mutate(
      # Extract category from "Category | Code description" format
      cancer_category = str_extract(description, "^[^|]+") %>% str_trim(),
      is_hodgkin = as.integer(cancer_category == "Hodgkin Lymphoma")
    ) %>%
    select(ID, cancer_code, cancer_category, is_hodgkin)

  message(glue("  Loaded cancer categories: {nrow(cancer_summary)} patient-code mappings"))
} else {
  warning(glue("Cancer summary not found: {CANCER_SUMMARY_CSV}. Skipping category mapping."))
  cancer_summary <- NULL
}

# Join to detail export
if (!is.null(cancer_summary)) {
  detail_export <- detail_export %>%
    left_join(cancer_summary, by = c("patient_id" = "ID", "triggering_code" = "cancer_code")) %>%
    mutate(
      cancer_category = ifelse(is.na(cancer_category), "", cancer_category),
      is_hodgkin = coalesce(is_hodgkin, 0L)
    )
}
```

**Dependency:** Requires R/53 to run before R/49. Already enforced by RDS artifact dependencies (R/44a → R/48b → R/49).

---

### 5. Death Date Integration (DEATH table → Gantt pseudo-treatment-type)

**Integration:** Add DEATH table to R/00_config.R PCORNET_TABLES, R/49 joins death_date to episodes + detail, exports as treatment_type = "Death".

**Components affected:**
- **MODIFY:** R/00_config.R (add DEATH to PCORNET_TABLES, line 108-123)
- **MODIFY:** R/25_duckdb_ingest.R (add DEATH to ingest list)
- **MODIFY:** R/49_gantt_data_export.R (join death_date, add death pseudo-episodes)

**Data flow:**
```
DEATH (DuckDB)
  → select(ID, DEATH_DATE)

treatment_episodes.rds
  → R/49 left_join(death, by = c("patient_id" = "ID"))
  → add death_date column
  → append death pseudo-episode rows (patient_id, treatment_type = "Death", episode_start = death_date, episode_stop = death_date)
  → gantt_episodes.csv (with death rows)

treatment_episode_detail.rds
  → R/49 left_join(death, by = c("patient_id" = "ID"))
  → add death_date column
  → gantt_detail.csv (with death_date column)
```

**Why this works:** DEATH table follows PCORnet CDM standard (ID, DEATH_DATE columns). R/49 already stacks multiple treatment types into episodes CSV. Death becomes another treatment_type with episode_length_days = 0.

**Build order:**
1. Verify DEATH table exists in Mailhot_V1 extract (check /orange/.../DEATH_Mailhot_V1.csv)
2. Add to R/00_config.R PCORNET_TABLES (line 123)
3. Re-run R/25_duckdb_ingest.R to add DEATH to DuckDB
4. Modify R/49 to load DEATH, join to episodes, append death pseudo-episodes
5. Re-run R/49 to regenerate Gantt CSVs

**Code change in R/00_config.R (after line 123):**
```r
PCORNET_TABLES <- c(
  # ... existing tables ...
  "PROVIDER",
  "DEATH"          # Phase v1.7: death date for Gantt chart
)
```

**Code change in R/49 (after line 71):**
```r
# Load death dates
death <- get_pcornet_table("DEATH") %>%
  select(ID, DEATH_DATE) %>%
  filter(!is.na(DEATH_DATE)) %>%
  collect()

message(glue("  Loaded {nrow(death)} death dates"))

# Join death dates to episodes
episodes_export <- episodes_export %>%
  left_join(death, by = c("patient_id" = "ID"))

# Append death pseudo-episodes (one per patient with death_date)
death_episodes <- death %>%
  transmute(
    patient_id = ID,
    treatment_type = "Death",
    episode_number = 1L,
    episode_start = DEATH_DATE,
    episode_stop = DEATH_DATE,
    episode_length_days = 0L,
    distinct_dates_in_episode = 1L,
    historical_flag = as.integer(DEATH_DATE < HISTORICAL_CUTOFF),
    triggering_codes = "",
    triggering_code_descriptions = "",
    cancer_category = "",
    is_hodgkin = 0L
  )

# Append to episodes
episodes_export <- bind_rows(episodes_export, death_episodes) %>%
  arrange(patient_id, treatment_type, episode_number)

message(glue("  Added {nrow(death_episodes)} death pseudo-episodes"))
```

**Visualization impact:** Death rows appear as vertical bars at death_date on Gantt chart. Third-party visualization tool must support treatment_type filtering to toggle death visibility.

---

## New vs. Modified Components

### New Components

| Component | Purpose | Dependencies |
|-----------|---------|--------------|
| R/56_hl_cohort_confirmation.R | Filter to confirmed HL patients (2+ codes, 7 days apart) | DIAGNOSIS (DuckDB), R/00_config.R |
| R/53a_cancer_summary_post_hl.R | Cancer summary filtered to post-HL diagnosis dates | R/56 output, DIAGNOSIS (DuckDB) |
| R/54a_cancer_summary_table_post_hl.R | Aggregate post-HL cancer summary | R/53a output |

### Modified Components

| Component | Modification | Reason |
|-----------|--------------|--------|
| R/00_config.R | Add DEATH to PCORNET_TABLES | Enable death date loading |
| R/25_duckdb_ingest.R | Add DEATH to ingest list | Populate DuckDB with death dates |
| R/53_cancer_summary.R | Remove D10-D36 from PREFIX_MAP, add category filter | Exclude benign neoplasms |
| R/54_cancer_summary_table.R | Remove D10-D36 from PREFIX_MAP, add category filter | Exclude benign neoplasms |
| R/47_cancer_site_frequency.R | Remove D10-D36 from PREFIX_MAP (consistency) | Match cancer summary exclusion |
| R/49_gantt_data_export.R | Join cancer_summary, add death pseudo-episodes | Add category + death to Gantt |

### Unchanged Components

| Component | Why Unchanged |
|-----------|---------------|
| R/04_build_cohort.R | HL cohort detection already exists; R/56 applies stricter filter |
| R/44a_treatment_episodes.R | Episode generation independent of cancer categories |
| R/48b_build_code_descriptions.R | Code descriptions unrelated to cancer categories |
| R/50_cancer_site_confirmation.R | 2-date confirmation standalone; R/56 handles 7-day cohort filter |

---

## Build Order and Dependencies

### Dependency Graph

```
R/00_config.R (DEATH added)
  → R/25_duckdb_ingest.R (DEATH ingested)
  → R/56_hl_cohort_confirmation.R (reads DIAGNOSIS, writes confirmed_hl_cohort.rds)
    → R/53_cancer_summary.R (benign removed, no cohort filter)
    → R/53a_cancer_summary_post_hl.R (cohort filter + temporal filter)
      → R/54_cancer_summary_table.R (benign removed)
      → R/54a_cancer_summary_table_post_hl.R
  → R/44a_treatment_episodes.R (unchanged, writes treatment_episodes.rds)
    → R/48b_build_code_descriptions.R (unchanged)
      → R/49_gantt_data_export.R (cancer category + death joins)
```

### Recommended Build Sequence

**Phase 1: Benign Code Removal (Standalone)**
1. Edit PREFIX_MAP in R/47, R/53, R/54 (remove D10-D36 entries)
2. Add category filter in R/53 (line 360), R/54 (line 344)
3. Re-run R/53 → R/54
4. Validate: Column F (Hodgkin Lymphoma) should show 100% in cancer_summary_table.xlsx

**Phase 2: HL Cohort Confirmation (Builds on Phase 1)**
1. Create R/56_hl_cohort_confirmation.R (7-day HL filter)
2. Create R/53a, R/54a (post-HL variants)
3. Run R/56 → R/53a → R/54a
4. Validate: cancer_summary_table_post_hl.xlsx has lower patient counts than baseline

**Phase 3: Gantt Enhancements (Parallel with Phase 2)**
1. Add DEATH to R/00_config.R PCORNET_TABLES
2. Re-run R/25_duckdb_ingest.R (add DEATH table)
3. Modify R/49 (cancer category join + death pseudo-episodes)
4. Re-run R/49
5. Validate: gantt_detail.csv has cancer_category, is_hodgkin columns; gantt_episodes.csv has Death rows

**Critical path:** Phase 1 is prerequisite for Phase 2 (benign removal affects HL percentage). Phase 3 is independent.

---

## Sources

- R/00_config.R: Configuration patterns (PCORNET_TABLES, PREFIX_MAP centralization)
- R/53_cancer_summary.R: Patient-code cancer summary logic, PREFIX_MAP definition
- R/54_cancer_summary_table.R: Category/code aggregation, PREFIX_MAP duplication
- R/49_gantt_data_export.R: Gantt CSV export with code descriptions
- R/04_build_cohort.R: HL cohort detection with HL_SOURCE flag
- R/50_cancer_site_confirmation.R: 2-date confirmation pattern
- R/51_cancer_site_confirmation_7day.R: 7-day separation logic
- R/44a_treatment_episodes.R: Treatment episode generation with triggering_codes
- .planning/PROJECT.md: v1.7 milestone requirements

**Confidence:** HIGH (all integration points verified against existing codebase structure)
