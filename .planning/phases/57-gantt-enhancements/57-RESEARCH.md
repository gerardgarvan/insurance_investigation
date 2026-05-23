# Phase 57: Gantt Enhancements - Research

**Researched:** 2026-05-23
**Domain:** R data enrichment, CSV manipulation, DuckDB table integration
**Confidence:** HIGH

## Summary

Phase 57 enriches existing Gantt chart CSV exports with cancer category labels, a Hodgkin Lymphoma binary flag, and death dates as pseudo-treatment rows. This requires: (1) joining patient-level cancer categories from `cancer_summary.csv` to treatment episode rows, (2) detecting Hodgkin Lymphoma presence, and (3) adding full DuckDB pipeline integration for a new DEATH table, then creating single-point pseudo-treatment rows for visualization.

The implementation is straightforward R data manipulation using established project patterns: group-by aggregation of cancer categories per patient, comma-separated list concatenation (matching existing `triggering_codes` format), dplyr join operations, and sentinel date nullification for 1900-year death dates. The DEATH table integration follows the exact pattern used for DEMOGRAPHIC, CONDITION, and other PCORnet tables (config registration → load spec → DuckDB ingest → query via `get_pcornet_table()`).

**Primary recommendation:** Modify R/49_gantt_data_export.R to load cancer_summary.csv, aggregate cancer categories per patient, join to episodes/detail dataframes, and query DEATH table via DuckDB to append pseudo-treatment rows. Add DEATH to R/00_config.R PCORNET_TABLES, define DEATH_SPEC in R/01_load_pcornet.R, and re-run R/25_duckdb_ingest.R before executing the modified R/49 script.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Cancer Category Assignment:**
- **D-01:** Cancer categories assigned at patient level from `cancer_summary.csv` (R/55 output). Group by patient ID to get all distinct cancer categories per patient, then join onto treatment episode rows. No re-querying of DIAGNOSIS/DuckDB needed.
- **D-02:** Comma-separated list format for `cancer_category` column when patient has multiple cancer types (e.g., "Hodgkin Lymphoma,Breast"). Matches existing `triggering_codes` pattern in Gantt data.
- **D-03:** `is_hodgkin` column is TRUE when "Hodgkin Lymphoma" appears anywhere in comma-separated `cancer_category` value.

**Death Date Integration:**
- **D-04:** Death dates come from separate `DEATH_Mailhot_V1.csv` table with columns: ID, DEATH_DATE, DEATH_DATE_IMPUTE, DEATH_SOURCE, DEATH_MATCH_CONFIDENCE, SOURCE.
- **D-05:** Full pipeline integration for DEATH table: add to `PCORNET_TABLES` in R/00_config.R, define `DEATH_SPEC` in R/01_load_pcornet.R, ingest into DuckDB via R/25_duckdb_ingest.R, query via `get_pcornet_table("DEATH")`.
- **D-06:** Death rows are single-point pseudo-treatment rows: `treatment_type = "Death"`, `episode_start = death_date`, `episode_stop = death_date`, `episode_length_days = 0`, `episode_number = 1`. Other fields (triggering_codes, triggering_code_descriptions) are empty strings.
- **D-07:** Death rows appear in BOTH `gantt_episodes.csv` and `gantt_detail.csv` with same structure.
- **D-08:** Death dates undergo 1900 sentinel date nullification (same pattern as diagnosis dates). Patients with NULL death dates after sentinel filtering are excluded (no Death row).

### Claude's Discretion

- Column ordering for new columns (cancer_category, is_hodgkin) in CSVs
- Whether cancer_category list is alphabetically sorted or ordered by code frequency
- Script numbering for new R/57 script
- Whether DEATH table re-ingest requires separate step or is part of R/57's setup instructions
- Cancer category for Death pseudo-treatment row (patient's cancer categories, or NA/empty)

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.

</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| GANTT-01 | Each treatment episode row includes cancer category label from CancerSiteCategories mapping (D-codes excluded) | Cancer categories pre-computed in R/55 output (cancer_summary.csv); group-by aggregation provides per-patient categories |
| GANTT-02 | Each treatment episode row includes `is_hodgkin` binary column (TRUE when cancer category is Hodgkin Lymphoma) | String detection on comma-separated cancer_category value using `str_detect(cancer_category, "Hodgkin Lymphoma")` |
| GANTT-03 | Death date from DEMOGRAPHIC table added to Gantt chart data as treatment type for visualization | DEATH table integration via config → load spec → DuckDB ingest → query; pseudo-treatment row construction with single-point structure |

</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| dplyr | 1.2.0+ | Data manipulation | Project standard; group_by for cancer category aggregation, left_join for enrichment, bind_rows for death row concatenation |
| stringr | 1.5.1+ | String operations | Comma-separated list construction (str_c with collapse), Hodgkin detection (str_detect), matches existing triggering_codes pattern |
| lubridate | 1.9.3+ | Date operations | Year extraction for 1900 sentinel nullification: `year(DEATH_DATE) == 1900L` |
| glue | 1.8.0 | String formatting | Logging messages; established project pattern |
| vroom | 1.7.0+ | CSV reading | Load cancer_summary.csv (fast, matches project's readr/vroom preference) |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| readr | 2.2.0+ | CSV writing | write.csv() for output (project uses base write.csv, but readr is available fallback) |
| DBI/duckdb | (project versions) | Database queries | get_pcornet_table("DEATH") after DuckDB ingest |

**Installation:**
All packages already installed in project renv. No new dependencies needed.

**Version verification:**
```r
# Verify current project versions match research assumptions
packageVersion("dplyr")    # Should be >= 1.2.0
packageVersion("stringr")  # Should be >= 1.5.1
packageVersion("lubridate") # Should be >= 1.9.3
```

## Architecture Patterns

### Recommended Modification Structure
R/49_gantt_data_export.R sections:
```
SECTION 1: SETUP AND CONFIGURATION
  - Add cancer_summary.csv input path
  - Add DEATH table query setup

SECTION 2: LOAD INPUT DATA
  - Load cancer_summary.csv
  - Query DEATH table via get_pcornet_table("DEATH")

SECTION 3: AGGREGATE CANCER CATEGORIES
  - Group cancer_summary by ID, collapse categories to comma-separated string
  - Create is_hodgkin flag

SECTION 4: ENRICH EPISODES AND DETAIL
  - Left join cancer categories to episodes
  - Left join cancer categories to detail

SECTION 5: BUILD DEATH PSEUDO-TREATMENT ROWS
  - Apply 1900 sentinel date nullification
  - Construct death rows for episodes table
  - Construct death rows for detail table

SECTION 6: CONCATENATE DEATH ROWS
  - bind_rows(episodes, death_episodes)
  - bind_rows(detail, death_detail)

SECTION 7: SELECT AND ORDER COLUMNS
  - (Existing section, modified to include cancer_category, is_hodgkin)

SECTION 8: WRITE CSV OUTPUTS
  - (Existing section, unchanged)
```

### Pattern 1: Patient-Level Cancer Category Aggregation
**What:** Group patient-code level data (cancer_summary.csv) to patient-level with comma-separated category list
**When to use:** Converting multi-row per patient to single row with aggregated values
**Example:**
```r
# Source: Established project pattern from R/49 triggering_codes construction
# Input: cancer_summary.csv with columns ID, cancer_code, category
# Output: per-patient dataframe with ID, cancer_category (comma-separated)

cancer_categories_per_patient <- cancer_summary %>%
  group_by(ID) %>%
  summarise(
    cancer_category = paste(unique(category), collapse = ","),
    .groups = "drop"
  ) %>%
  mutate(
    is_hodgkin = str_detect(cancer_category, "Hodgkin Lymphoma")
  )
```

### Pattern 2: 1900 Sentinel Date Nullification
**What:** Replace year-1900 dates with NA to filter PCORnet sentinel values
**When to use:** All date columns from PCORnet tables before downstream logic
**Example:**
```r
# Source: R/04_build_cohort.R lines 171-172, R/11_generate_pptx.R line 511
# Project established pattern for enrollment dates, diagnosis dates

death_data <- get_pcornet_table("DEATH") %>%
  collect() %>%
  mutate(
    DEATH_DATE = if_else(year(DEATH_DATE) == 1900L, as.Date(NA), DEATH_DATE)
  ) %>%
  filter(!is.na(DEATH_DATE))  # Exclude patients with no valid death date
```

### Pattern 3: Pseudo-Treatment Row Construction
**What:** Create synthetic treatment episode rows for non-treatment events (death) to enable timeline visualization
**When to use:** Single-point events that need to appear on Gantt chart
**Example:**
```r
# Source: Phase 57 specification (D-06)
# Structure matches existing treatment_episodes columns

death_episodes <- death_data %>%
  mutate(
    treatment_type = "Death",
    episode_number = 1L,
    episode_start = DEATH_DATE,
    episode_stop = DEATH_DATE,
    episode_length_days = 0L,
    distinct_dates_in_episode = 1L,
    historical_flag = FALSE,
    triggering_codes = "",
    triggering_code_descriptions = "",
    cancer_category = NA_character_,  # Or join from cancer_categories_per_patient
    is_hodgkin = FALSE  # Or join from cancer_categories_per_patient
  ) %>%
  select(patient_id = ID, treatment_type, episode_number,
         episode_start, episode_stop, episode_length_days,
         distinct_dates_in_episode, historical_flag,
         triggering_codes, triggering_code_descriptions,
         cancer_category, is_hodgkin)

death_detail <- death_data %>%
  mutate(
    treatment_type = "Death",
    treatment_date = DEATH_DATE,
    triggering_code = "",
    episode_number = 1L,
    episode_start = DEATH_DATE,
    episode_stop = DEATH_DATE,
    historical_flag = FALSE,
    triggering_code_description = "",
    cancer_category = NA_character_,
    is_hodgkin = FALSE
  ) %>%
  select(patient_id = ID, treatment_type, treatment_date,
         triggering_code, episode_number, episode_start,
         episode_stop, historical_flag, triggering_code_description,
         cancer_category, is_hodgkin)
```

### Pattern 4: DuckDB Table Integration (DEATH Table)
**What:** Add new PCORnet table to full pipeline infrastructure
**When to use:** When new data table becomes available and needs query access
**Example:**
```r
# Step 1: R/00_config.R — Add to PCORNET_TABLES vector (line 108-123)
PCORNET_TABLES <- c(
  "ENROLLMENT",
  "DIAGNOSIS",
  # ... existing tables ...
  "PROVIDER",
  "DEATH"  # NEW: Phase 57
)

# Step 2: R/01_load_pcornet.R — Define load spec (after DEMOGRAPHIC_SPEC, line 186)
# ------------------------------------------------------------------------------
# X. DEATH (6 columns)
# ------------------------------------------------------------------------------
DEATH_SPEC <- cols(
  ID = col_character(),
  DEATH_DATE = col_character(),  # Parse as character, convert in R
  DEATH_DATE_IMPUTE = col_character(),
  DEATH_SOURCE = col_character(),
  DEATH_MATCH_CONFIDENCE = col_character(),
  SOURCE = col_character()
)

# Step 3: Re-run R/25_duckdb_ingest.R to ingest DEATH table
# (Rebuilds entire DuckDB from scratch per D-02 in that script)

# Step 4: Query in R/49 via established pattern
source("R/utils_duckdb.R")
open_pcornet_con()
death_raw <- get_pcornet_table("DEATH") %>% collect()
close_pcornet_con()
```

### Anti-Patterns to Avoid

- **Don't parse DEATH_DATE as Date in load spec:** PCORnet CSVs have inconsistent date formats; load as character then parse with lubridate (matches DEMOGRAPHIC BIRTH_DATE pattern)
- **Don't skip 1900 sentinel nullification on death dates:** Missing data is coded as 1900-01-01 in PCORnet; must filter before creating death rows
- **Don't create death rows for patients without valid death dates:** Empty/NA death dates after sentinel filtering should be excluded, not defaulted to NA rows (per D-08)
- **Don't alphabetically sort cancer_category lists:** Maintain insertion order or frequency order from cancer_summary.csv; arbitrary sorting obscures clinical importance
- **Don't re-query DIAGNOSIS for cancer categories:** Phase 55 already computed and classified all cancer codes; reuse cancer_summary.csv output (per D-01)

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Patient-level category aggregation | Manual loop over unique patient IDs | dplyr group_by + summarise | group_by handles missing data, maintains type safety, readable code |
| Comma-separated list construction | paste0 with manual collapse loops | stringr::str_c or base paste with collapse="," | Handles empty groups, NA values consistently |
| DuckDB query backend switching | if/else checks for RDS vs DuckDB | get_pcornet_table() from utils_duckdb.R | Abstracts backend, supports USE_DUCKDB flag, matches project pattern |
| CSV reading with type inference | read.csv with default types | vroom with col_types spec | Project standard; prevents type mismatch errors on reload |

**Key insight:** The project already has established patterns for every operation needed in Phase 57. Reuse existing code patterns rather than inventing new approaches — this maintains consistency and leverages tested logic.

## Common Pitfalls

### Pitfall 1: Cancer Category List Ordering Ambiguity
**What goes wrong:** Different scripts produce different category orderings for same patient (e.g., "Hodgkin Lymphoma,Breast" vs "Breast,Hodgkin Lymphoma"), breaking reproducibility and downstream string matching.
**Why it happens:** `unique()` in R preserves first-occurrence order, but cancer_summary.csv row order is arbitrary (depends on DIAGNOSIS query order from DuckDB).
**How to avoid:** Explicitly sort categories within each patient group OR document that order is arbitrary and only presence/absence matters (don't rely on position).
**Warning signs:** Test runs produce different cancer_category values for same patient; `is_hodgkin` flag unexpectedly FALSE despite Hodgkin diagnosis.

**Prevention strategy:**
```r
# Option 1: Alphabetical sort for reproducibility
cancer_category = paste(sort(unique(category)), collapse = ",")

# Option 2: Frequency order (most common cancer type first)
# Requires pre-computing category frequencies across cohort

# Option 3: Document arbitrary order, use str_detect for all matching
# is_hodgkin = str_detect(cancer_category, "Hodgkin Lymphoma")
# (Robust to order; recommended per D-03)
```

### Pitfall 2: Missing DEATH Table RDS Cache After Config Addition
**What goes wrong:** R/49 script fails with "DEATH.rds not found" or "DEATH table not in DuckDB" error after adding DEATH to PCORNET_TABLES.
**Why it happens:** Adding a table to config doesn't automatically load it; requires re-running the load pipeline (R/02 for RDS cache, R/25 for DuckDB ingest).
**How to avoid:** After modifying R/00_config.R and R/01_load_pcornet.R, run `source("R/02_load_pcornet_cache.R")` (if it exists) or re-run the full load pipeline before executing R/49.
**Warning signs:** Error message mentions "table DEATH does not exist", "DEATH.rds not found", or PCORNET_TABLES length mismatch.

**Prevention strategy:**
```bash
# After config changes, re-ingest DEATH table
Rscript R/25_duckdb_ingest.R  # Rebuilds entire DuckDB (includes new DEATH table)

# Then verify table exists before running R/49
R -e "source('R/utils_duckdb.R'); open_pcornet_con(); print(DBI::dbListTables(pcornet_con)); close_pcornet_con()"
# Should include "DEATH" in output
```

### Pitfall 3: 1900 Sentinel Date Detection After Type Conversion
**What goes wrong:** Sentinel date check `year(DEATH_DATE) == 1900L` fails because DEATH_DATE is still character type (not parsed as Date).
**Why it happens:** vroom loads DEATH_DATE as character per DEATH_SPEC; must parse with lubridate before year extraction.
**How to avoid:** Parse date column immediately after loading, before applying sentinel logic.
**Warning signs:** Error "non-numeric argument to mathematical function" when calling `year()`, or all death dates pass through filter unexpectedly.

**Prevention strategy:**
```r
# WRONG: year() called on character column
death_data <- get_pcornet_table("DEATH") %>%
  collect() %>%
  mutate(DEATH_DATE = if_else(year(DEATH_DATE) == 1900L, as.Date(NA), DEATH_DATE))
# Error: year() doesn't work on character

# CORRECT: Parse first, then apply sentinel logic
death_data <- get_pcornet_table("DEATH") %>%
  collect() %>%
  mutate(
    DEATH_DATE = ymd(DEATH_DATE),  # Parse character to Date
    DEATH_DATE = if_else(year(DEATH_DATE) == 1900L, as.Date(NA), DEATH_DATE)
  ) %>%
  filter(!is.na(DEATH_DATE))
```

### Pitfall 4: Column Mismatch After bind_rows() for Death Rows
**What goes wrong:** bind_rows() fails with "incompatible types" or silently creates NA columns because death row dataframe columns don't match treatment episode columns (order, names, types).
**Why it happens:** Forgetting to include new cancer_category/is_hodgkin columns in death row construction, or using wrong column names.
**How to avoid:** Explicitly specify all columns in death row construction with same names, types, and order as treatment episodes/detail dataframes. Verify column names with `setdiff()` before binding.
**Warning signs:** bind_rows() warning "Column X not found in all inputs", or output CSV has unexpected NA columns.

**Prevention strategy:**
```r
# Verify column alignment before bind_rows
expected_cols <- colnames(episodes_export)
death_cols <- colnames(death_episodes)
missing_in_death <- setdiff(expected_cols, death_cols)
extra_in_death <- setdiff(death_cols, expected_cols)

if (length(missing_in_death) > 0) {
  stop(glue("Death episodes missing columns: {paste(missing_in_death, collapse=', ')}"))
}
if (length(extra_in_death) > 0) {
  warning(glue("Death episodes has extra columns: {paste(extra_in_death, collapse=', ')}"))
}

episodes_with_death <- bind_rows(episodes_export, death_episodes)
```

## Code Examples

Verified patterns from project codebase:

### Example 1: Group-By Aggregation with Comma-Separated Collapse
```r
# Source: R/49_gantt_data_export.R lines 123-128 (triggering_codes pattern)
# Adapted for cancer category aggregation

cancer_summary <- vroom::vroom("output/tables/cancer_summary.csv", show_col_types = FALSE)

cancer_categories_per_patient <- cancer_summary %>%
  group_by(ID) %>%
  summarise(
    cancer_category = paste(sort(unique(category)), collapse = ","),
    .groups = "drop"
  ) %>%
  mutate(
    is_hodgkin = str_detect(cancer_category, "Hodgkin Lymphoma")
  )

# Example output:
# ID        cancer_category                    is_hodgkin
# 12345     "Hodgkin Lymphoma"                 TRUE
# 67890     "Breast,Hodgkin Lymphoma,Thyroid"  TRUE
# 11111     "Prostate"                         FALSE
```

### Example 2: Left Join Enrichment (Add Cancer Categories to Episodes)
```r
# Source: R/49 pattern (join code_descriptions), R/55 pattern (join dx_record_counts)
# Left join preserves all treatment episodes; adds cancer_category/is_hodgkin

episodes_export <- episodes %>%
  select(
    patient_id, treatment_type, episode_number,
    episode_start, episode_stop, episode_length_days,
    distinct_dates_in_episode, historical_flag, triggering_codes
  ) %>%
  mutate(
    triggering_code_descriptions = sapply(triggering_codes, map_codes_to_descriptions, USE.NAMES = FALSE)
  ) %>%
  left_join(cancer_categories_per_patient, by = c("patient_id" = "ID")) %>%
  mutate(
    cancer_category = ifelse(is.na(cancer_category), "", cancer_category),
    is_hodgkin = ifelse(is.na(is_hodgkin), FALSE, is_hodgkin)
  )

# Columns: patient_id, treatment_type, episode_number, episode_start, episode_stop,
#          episode_length_days, distinct_dates_in_episode, historical_flag,
#          triggering_codes, triggering_code_descriptions, cancer_category, is_hodgkin
```

### Example 3: 1900 Sentinel Date Nullification for DEATH Table
```r
# Source: R/04_build_cohort.R lines 171-172, R/11_generate_pptx.R line 511
# Query DEATH table, parse dates, nullify 1900 sentinels

source("R/utils_duckdb.R")
open_pcornet_con()

death_data <- get_pcornet_table("DEATH") %>%
  collect() %>%
  mutate(
    DEATH_DATE = ymd(DEATH_DATE),  # Parse character to Date
    DEATH_DATE = if_else(year(DEATH_DATE) == 1900L, as.Date(NA), DEATH_DATE)
  ) %>%
  filter(!is.na(DEATH_DATE)) %>%  # Exclude patients with no valid death date (per D-08)
  select(ID, DEATH_DATE)

close_pcornet_con()

message(glue("  Loaded {nrow(death_data)} patients with valid death dates"))
```

### Example 4: Death Pseudo-Treatment Row Construction
```r
# Source: Phase 57 specification (D-06, D-07)
# Construct death rows matching episodes/detail structure

# For gantt_episodes.csv (bars)
death_episodes <- death_data %>%
  left_join(cancer_categories_per_patient, by = "ID") %>%
  mutate(
    patient_id = ID,
    treatment_type = "Death",
    episode_number = 1L,
    episode_start = DEATH_DATE,
    episode_stop = DEATH_DATE,
    episode_length_days = 0L,
    distinct_dates_in_episode = 1L,
    historical_flag = FALSE,
    triggering_codes = "",
    triggering_code_descriptions = "",
    cancer_category = ifelse(is.na(cancer_category), "", cancer_category),
    is_hodgkin = ifelse(is.na(is_hodgkin), FALSE, is_hodgkin)
  ) %>%
  select(patient_id, treatment_type, episode_number,
         episode_start, episode_stop, episode_length_days,
         distinct_dates_in_episode, historical_flag,
         triggering_codes, triggering_code_descriptions,
         cancer_category, is_hodgkin)

# For gantt_detail.csv (ticks)
death_detail <- death_data %>%
  left_join(cancer_categories_per_patient, by = "ID") %>%
  mutate(
    patient_id = ID,
    treatment_type = "Death",
    treatment_date = DEATH_DATE,
    triggering_code = "",
    episode_number = 1L,
    episode_start = DEATH_DATE,
    episode_stop = DEATH_DATE,
    historical_flag = FALSE,
    triggering_code_description = "",
    cancer_category = ifelse(is.na(cancer_category), "", cancer_category),
    is_hodgkin = ifelse(is.na(is_hodgkin), FALSE, is_hodgkin)
  ) %>%
  select(patient_id, treatment_type, treatment_date,
         triggering_code, episode_number, episode_start,
         episode_stop, historical_flag, triggering_code_description,
         cancer_category, is_hodgkin)
```

### Example 5: Concatenate Death Rows with Treatment Episodes
```r
# Source: Project pattern from multi-table binding (TUMOR_REGISTRY_ALL)
# Bind death rows to existing episodes/detail

episodes_with_death <- bind_rows(episodes_export, death_episodes) %>%
  arrange(patient_id, episode_start, treatment_type)  # Sort for readability

detail_with_death <- bind_rows(detail_export, death_detail) %>%
  arrange(patient_id, treatment_date, treatment_type)

message(glue("  Episodes with death: {nrow(episodes_with_death)} rows ({nrow(death_episodes)} death rows added)"))
message(glue("  Detail with death: {nrow(detail_with_death)} rows ({nrow(death_detail)} death rows added)"))
```

## Environment Availability

> All dependencies are in-project libraries already installed in renv; no external tools required.

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| R | Base runtime | ✓ | 4.4.2+ (HiPerGator standard) | — |
| dplyr | Cancer category aggregation, joins | ✓ | 1.2.0+ (in renv) | — |
| stringr | Comma-separated lists, Hodgkin detection | ✓ | 1.5.1+ (in renv) | — |
| lubridate | Date parsing, sentinel detection | ✓ | 1.9.3+ (in renv) | — |
| vroom | CSV reading (cancer_summary.csv) | ✓ | 1.7.0+ (in renv) | readr (fallback) |
| DBI/duckdb | DEATH table queries | ✓ | (project versions in renv) | — |

**Missing dependencies with no fallback:**
- None — all required packages are already installed in project renv.

**Missing dependencies with fallback:**
- None

## Validation Architecture

> Skipped: workflow.nyquist_validation is explicitly set to false in .planning/config.json.

## Sources

### Primary (HIGH confidence)
- R/49_gantt_data_export.R — Current Gantt export script structure, triggering_codes pattern
- R/55_cancer_summary_refined.R — Cancer category classification (PREFIX_MAP), confirmed_hl_cohort.rds output
- R/00_config.R — PCORNET_TABLES vector pattern
- R/01_load_pcornet.R — DEMOGRAPHIC_SPEC, load spec pattern for new tables
- R/25_duckdb_ingest.R — DuckDB ingest pattern, rebuilds entire database from scratch
- R/utils_duckdb.R — get_pcornet_table() abstraction, open/close connection pattern
- R/04_build_cohort.R lines 171-172 — 1900 sentinel date nullification for enrollment dates
- R/11_generate_pptx.R line 511 — 1900 sentinel date nullification for treatment dates
- .planning/phases/57-gantt-enhancements/57-CONTEXT.md — User decisions, locked specifications

### Secondary (MEDIUM confidence)
- CLAUDE.md — Project constraints (R package stack, HiPerGator runtime, named predicate style)
- .planning/REQUIREMENTS.md — GANTT-01, GANTT-02, GANTT-03 requirement definitions

### Tertiary (LOW confidence)
- None — all research derived from project codebase and phase context

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All packages already in project renv, verified from CLAUDE.md STACK.md section
- Architecture: HIGH - All patterns extracted from existing project code (R/49, R/55, R/04, R/25, utils_duckdb.R)
- Pitfalls: HIGH - Based on actual project patterns and common R data manipulation errors
- DEATH table integration: HIGH - Exact pattern match to DEMOGRAPHIC table integration (config → load spec → ingest → query)
- Cancer category aggregation: HIGH - Direct reuse of triggering_codes pattern from R/49

**Research date:** 2026-05-23
**Valid until:** 2026-06-22 (30 days — stable domain, project-internal patterns unlikely to change)

---

*Phase: 57-gantt-enhancements*
*Research complete — ready for planning*
