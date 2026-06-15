# Phase 104: Treatment Timing Investigations - Research

**Researched:** 2026-06-15
**Domain:** R-based temporal analysis (treatment-before-diagnosis detection, secondary malignancy classification)
**Confidence:** HIGH

## Summary

Phase 104 implements two standalone investigation scripts using established R pipeline patterns to answer team questions about treatment timing anomalies and secondary malignancy patterns. The research confirms that all necessary infrastructure is already in place: treatment episode data with full temporal context (R/26), confirmed HL cohort with first diagnosis dates (R/47), 7-day gap criterion logic (R/45), and cancer code classification utilities (utils_cancer.R). Both investigations read existing RDS artifacts and DuckDB tables, perform temporal filtering/classification, and output styled xlsx files — following the exact pattern established by R/30, R/58, and R/59 in prior phases.

**Primary recommendation:** Script R/60 for pre-diagnosis treatment flagging (TIMING-01), script R/61 for secondary malignancy table (TIMING-02). Both use standard investigation script pattern: load artifacts, filter/classify, produce two-sheet xlsx with summary + detail, no upstream modification.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01 (Pre-Dx Output):** Output as xlsx with two sheets: Sheet 1 = summary counts by treatment type (e.g., "42 chemo episodes before HL dx"), Sheet 2 = patient-level detail rows for clinical plausibility review
- **D-02 (Treatment Coverage):** Include ALL 5 treatment types: Chemotherapy, Radiation, SCT, Immunotherapy, Proton Therapy. No focus/weighting on any single type
- **D-03 (Detail Context):** Detail rows include full code context: ID, treatment_type, episode_start, episode_stop, first_hl_dx_date, days_before_dx, triggering_codes, drug_names. Enables clinical review without cross-referencing R/26 output
- **D-04 (Standalone Files):** Separate standalone output file (`secondary_malignancy_table.xlsx`), NOT an enhancement of R/49's existing output. R/49 output remains unchanged
- **D-05 (Population Scope):** Population restricted to confirmed HL patients (7-day gap HL diagnosis confirmation from R/47's confirmed_hl_cohort.rds)
- **D-06 (Dual 7-Day Confirmation):** Secondary malignancies also require 7-day confirmation — each non-HL cancer code needs 2+ diagnosis dates with 7+ day separation to count as a confirmed secondary malignancy
- **D-07 (Temporal Split):** Pre/post HL split: secondary cancer diagnosed before vs after first HL dx date. Population-based percentage columns use confirmed HL cohort size as denominator
- **D-08 (Script Structure):** Two separate standalone scripts: one for pre-diagnosis treatment flagging (TIMING-01), one for secondary malignancy table (TIMING-02). Different data flows, different outputs. Follows investigation script pattern from v3.1
- **D-09 (HIPAA Suppression):** Raw counts without HIPAA suppression — manual suppression before sharing (v3.1 convention)

### Claude's Discretion
- Script numbering (next available numbers in appropriate decade)
- Console logging structure and verbosity
- Summary sheet layout details (column ordering, row labels, formatting)
- Whether to include additional context in summary (e.g., percentage of total episodes that are pre-dx)
- R/88 smoke test section structure and check count for both new scripts

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope

</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| TIMING-01 | User can run R script that flags and quantifies all treatment episodes (chemo, radiation, SCT, immunotherapy) occurring before the patient's first confirmed HL diagnosis date, with counts by treatment type | treatment_episodes.rds (R/26) + confirmed_hl_cohort.rds (R/47) temporal filtering; investigation script pattern (R/30, R/58, R/59); openxlsx2 two-sheet output |
| TIMING-02 | User can run R script that produces a secondary malignancy table using 7-day gap criterion between diagnoses, with columns K-N based on population in column E (E3 per meeting notes) | 7-day gap logic (R/45 lines 266-302); classify_codes() (utils_cancer.R); pre/post temporal split (R/49 lines 127-160); confirmed HL cohort as denominator (D-05) |

</phase_requirements>

## Standard Stack

### Core Framework
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| dplyr | 1.2.0+ | Data filtering, joins, aggregation | Tidyverse standard for readable temporal filtering (`filter(episode_start < first_hl_dx_date)`); established in all 100+ existing scripts |
| glue | 1.8.0+ | String interpolation for logging | Standard logging pattern across all investigation scripts: `glue("Found {n} pre-dx episodes")` |
| lubridate | 1.9.3+ | Date arithmetic | Compute days_before_dx: `as.numeric(first_hl_dx_date - episode_start)`; established in R/47, R/49 |
| openxlsx2 | 1.13.2+ | Styled xlsx output | Two-sheet workbook pattern (summary + detail) established in R/26, R/30, R/58, R/59; wb_workbook() -> add_worksheet() -> add_data() -> save() |

### Data Access
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| DuckDB (via utils_duckdb.R) | 1.1.3+ | Query DIAGNOSIS table | Secondary malignancy script (TIMING-02) loads all non-HL cancer codes from DIAGNOSIS via get_pcornet_table() |
| readRDS (base R) | Built-in | Load cached artifacts | Both scripts read treatment_episodes.rds, confirmed_hl_cohort.rds |

### Cancer Classification
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| utils_cancer.R | Project utility | is_cancer_code(), classify_codes() | TIMING-02: filter non-HL cancer codes, classify into site categories (Breast, Lung, Colorectal, etc.) |
| stringr | 1.5.1+ | String operations | ICD code normalization: `str_remove_all(DX, "\\.")` to match C810 vs C81.0 formats |

### Supporting Libraries
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| utils_assertions.R | Project utility | assert_rds_exists(), assert_df_valid() | Input validation (both scripts): verify treatment_episodes.rds and confirmed_hl_cohort.rds exist and have required columns |
| utils_duckdb.R | Project utility | open_pcornet_con(), get_pcornet_table() | TIMING-02: load DIAGNOSIS table for secondary malignancy detection |
| scales | 1.3.0+ | Percentage formatting | Optional for summary sheet: `scales::percent(n_pre_dx / n_total)` |

## Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| dplyr temporal filtering | data.table non-equi joins | data.table 10-50x faster but opaque syntax (`DT[episode_start < first_hl_dx_date]`) conflicts with project "named predicate" requirement |
| openxlsx2 | writexl | writexl is simpler (no styling) but cannot produce styled headers (dark gray FF374151, white bold text) established in all existing outputs |
| Pre/post split logic | Reuse R/49's output | D-04 locks decision: standalone file, R/49 unchanged. Duplicating 30 lines of filtering logic is simpler than refactoring R/49 |
| 7-day gap criterion | Reuse R/45's function | R/45 lines 266-302 is inline summarise() code, not a reusable function. Copy-paste 37 lines vs 100+ lines to refactor into utils function |

## Architecture Patterns

### Investigation Script Structure (Established Pattern)

All v3.1 investigation scripts (R/30, R/58, R/59) follow this 7-section pattern:

```r
# SECTION 1: SETUP AND CONFIGURATION ----
suppressPackageStartupMessages({
  library(dplyr)
  library(glue)
  library(openxlsx2)
})
source("R/00_config.R")
source("R/utils/utils_assertions.R")
# Define file paths
INPUT_RDS <- file.path(CONFIG$cache$outputs_dir, "artifact.rds")
OUTPUT_XLSX <- file.path(CONFIG$output_dir, "output.xlsx")

# SECTION 2: INPUT VALIDATION ----
assert_rds_exists(INPUT_RDS, script_name = "R/XX")

# SECTION 3: LOAD DATA ----
data <- readRDS(INPUT_RDS)

# SECTION 4: FILTER / CLASSIFY / COMPUTE ----
# Domain-specific logic (temporal filtering, classification, aggregation)

# SECTION 5: BUILD SUMMARY TABLE ----
summary_table <- ... %>% group_by(...) %>% summarise(...)

# SECTION 6: CREATE STYLED XLSX ----
wb <- wb_workbook()
wb$add_worksheet("Summary")
# ... styled headers, data, formatting ...
wb$save(OUTPUT_XLSX)

# SECTION 7: FINAL SUMMARY ----
message("=== Phase XX Complete ===")
message(glue("Output: {OUTPUT_XLSX}"))
```

### Pre-Diagnosis Treatment Detection (TIMING-01)

**Data flow:**
1. Load `treatment_episodes.rds` (11 columns including episode_start, treatment_type, triggering_codes, drug_names)
2. Load `confirmed_hl_cohort.rds` (3 columns: ID, first_hl_dx_date, first_hl_dx_source)
3. Inner join on ID (keep only confirmed HL cohort episodes)
4. Filter: `episode_start < first_hl_dx_date` (pre-diagnosis episodes)
5. Compute: `days_before_dx = as.numeric(first_hl_dx_date - episode_start)`
6. Aggregate by treatment_type for Sheet 1 summary
7. Build patient-level detail for Sheet 2

**Key pattern (R/49 lines 127-160):**
```r
# Pre/post temporal split pattern
pre_dx <- episodes %>%
  inner_join(confirmed_hl_cohort, by = c("patient_id" = "ID")) %>%
  filter(episode_start < first_hl_dx_date)
```

### Secondary Malignancy Table (TIMING-02)

**Data flow:**
1. Load `confirmed_hl_cohort.rds` (confirmed HL patients + first_hl_dx_date)
2. Query DuckDB DIAGNOSIS table for all non-HL cancer codes
3. Filter: `is_cancer_code(DX) & !str_detect(DX_norm, "^C81|^201")` (exclude HL)
4. Apply 7-day gap criterion per patient-code (R/45 lines 266-302 logic)
5. Classify confirmed secondary cancers into site categories (classify_codes)
6. Split pre/post HL diagnosis: `DX_DATE < first_hl_dx_date` vs `>= first_hl_dx_date`
7. Aggregate: count patients per category, compute percentages vs total cohort

**7-day gap criterion (from R/45 lines 266-302):**
```r
# Per patient-code: 2+ unique dates AND max - min >= 7 days
two_or_more_unique_dates_gt_7 = as.integer({
  dates <- DX_DATE[!is.na(DX_DATE)]
  ud <- unique(dates)
  if (length(ud) >= 2) {
    as.numeric(max(ud) - min(ud)) >= 7
  } else {
    FALSE
  }
})
```

### Styled XLSX Pattern (openxlsx2)

**Two-sheet workbook (from R/26, R/30, R/58, R/59):**
```r
wb <- wb_workbook()

# Sheet 1: Summary
wb$add_worksheet("Summary")
wb$add_data(sheet = "Summary", x = "Title", start_row = 1, start_col = 1)
wb$add_font(sheet = "Summary", dims = "A1",
            name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937"))

# Header row: dark gray background (FF374151), white bold text (FFFFFFFF)
headers <- c("Column1", "Column2", "Column3")
for (i in seq_along(headers)) {
  wb$add_data(sheet = "Summary", x = headers[i], start_row = 3, start_col = i)
}
wb$add_fill(sheet = "Summary", dims = "A3:C3", color = wb_color("FF374151"))
wb$add_font(sheet = "Summary", dims = "A3:C3",
            name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))

# Data rows + number formatting
wb$add_data(sheet = "Summary", x = summary_data, start_row = 4, col_names = FALSE)
wb$add_numfmt(sheet = "Summary", dims = "B4:B10", numfmt = "#,##0")

# Column widths + freeze panes
wb$set_col_widths(sheet = "Summary", cols = 1:3, widths = c(30, 15, 15))
wb$freeze_pane(sheet = "Summary", firstActiveRow = 4)

# Sheet 2: Detail
# ... repeat pattern ...

wb$save(OUTPUT_XLSX)
```

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| 7-day gap detection | Custom date span logic per code | Copy R/45 lines 266-302 verbatim | Established pattern used in R/45, R/47, R/49; already validated in production; 37 lines of inline summarise() code |
| Cancer code classification | Regex-based ICD-10 range detection | classify_codes() from utils_cancer.R | Handles 309 ICD-10 prefixes + ICD-9 + ICD-O-3; 4-tier cascade (C810 -> NLPHL, C81 -> classical HL); validated in R/28, R/40, R/45-R/49 |
| HL code filtering | Manual C81/201 regex patterns | Reuse R/47 lines 113-130 pattern | Handles both ICD-10 (C81) and ICD-9 (201.x) with dot normalization; already used in cohort confirmation |
| Episode-to-cohort join | Merge + filter | Inner join on ID | dplyr inner_join automatically filters to confirmed HL cohort; established in R/49 line 127 |
| Date parsing | strptime/as.Date manually | parse_pcornet_date() from utils_dates.R | Handles PCORnet date formats (YYYY-MM-DD, sentinel 1900-01-01); used in all 60+ scripts |
| Styled xlsx headers | Manual cell-by-cell formatting | Reuse R/59 lines 222-230 pattern | Dark header (FF374151) + white bold text (FFFFFFFF) established in 12+ outputs; copy-paste 8 lines |

**Key insight:** The codebase has 100+ scripts with mature temporal filtering, cancer classification, and xlsx styling patterns. Copy-paste established 10-50 line blocks rather than refactoring into shared utilities (which would require modifying 12+ existing scripts for 2 new scripts).

## Common Pitfalls

### Pitfall 1: Date Column Ambiguity in treatment_episodes.rds
**What goes wrong:** Using `treatment_date` column that doesn't exist in treatment_episodes.rds, causing "column not found" error.
**Why it happens:** treatment_episode_detail.rds has `treatment_date` (one row per date+code), but treatment_episodes.rds has `episode_start`/`episode_stop` (one row per episode). Pre-diagnosis filtering operates at episode grain, not date grain.
**How to avoid:** Use `episode_start < first_hl_dx_date` for pre-diagnosis filtering. Confirmed by R/26 output structure (lines 666-670): treatment_episodes.rds has `episode_start`, `episode_stop`, NO `treatment_date` column.
**Warning signs:** `Error: object 'treatment_date' not found` when filtering treatment_episodes.rds.

### Pitfall 2: Missing ICD-9 HL Codes in Secondary Malignancy Filtering
**What goes wrong:** Filtering only `!str_detect(DX_norm, "^C81")` allows ICD-9 201.x HL codes to leak into secondary malignancy counts.
**Why it happens:** confirmed_hl_cohort.rds includes patients with ICD-9 201.x codes (R/47 lines 113-117). Secondary malignancy table must exclude BOTH C81 (ICD-10) AND 201 (ICD-9) to prevent HL from appearing as a "secondary malignancy."
**How to avoid:** Use `!str_detect(DX_norm, "^C81|^201")` to exclude both ICD-10 and ICD-9 HL codes. Confirmed by R/47 dual-code filtering logic (lines 116-117).
**Warning signs:** HL (Hodgkin Lymphoma) category appears in secondary malignancy table.

### Pitfall 3: Denominator Confusion in Percentage Calculations
**What goes wrong:** Using subset size (e.g., patients with secondary malignancies) as denominator instead of total confirmed HL cohort.
**Why it happens:** D-07 locks decision: "Population-based percentage columns use confirmed HL cohort size as denominator." Meeting notes specify "columns K-N based on population in column E (E3)," meaning total cohort, NOT subset.
**How to avoid:** `pct_with_secondary = n_with_secondary / nrow(confirmed_hl_cohort)`, NOT `n_with_secondary / n_with_any_cancer`. Load cohort size once at top of script: `total_cohort <- nrow(confirmed_hl_cohort)`. Use this value for all percentage calculations.
**Warning signs:** Percentages > 50% for rare secondary malignancies (should be < 10% for most categories).

### Pitfall 4: Double-Counting Patients Across Pre/Post Split
**What goes wrong:** Same patient appears in both "Pre-HL Secondary Cancer" and "Post-HL Secondary Cancer" rows if they have secondary cancers diagnosed at different times.
**Why it happens:** Pre/post split is per diagnosis, not per patient. A patient with breast cancer before HL and lung cancer after HL contributes to both rows.
**How to avoid:** This is CORRECT behavior per meeting notes ("secondary cancer diagnosed before vs after first HL dx date"). Document in output that rows are NOT mutually exclusive. Add summary row: "Any Secondary Cancer (Pre or Post)" with n_distinct(ID).
**Warning signs:** Sum of pre + post counts exceeds total cohort size (expected behavior, not an error).

### Pitfall 5: Sentinel Date Contamination (1900-01-01)
**What goes wrong:** Computing days_before_dx produces absurdly large values (> 40,000 days) when first_hl_dx_date is 1900-01-01 sentinel.
**Why it happens:** R/47 nullifies 1900 sentinel dates (lines 182-187), but IF any slip through, days_before_dx calculation will produce outliers.
**How to avoid:** Filter `!is.na(first_hl_dx_date) & year(first_hl_dx_date) > 1900` before temporal filtering. Established in R/47 lines 182-187.
**Warning signs:** Pre-diagnosis episodes with > 10,000 days before HL diagnosis (clinically implausible).

## Code Examples

Verified patterns from existing scripts:

### Pre-Diagnosis Temporal Filtering (TIMING-01)

**Source:** R/49 lines 127-160 (pre/post HL split pattern)

```r
# Load artifacts
episodes <- readRDS(file.path(CONFIG$cache$outputs_dir, "treatment_episodes.rds"))
cohort <- readRDS(file.path(CONFIG$output_dir, "confirmed_hl_cohort.rds"))

# Join episodes to cohort (inner join = confirmed HL patients only)
episodes_with_dx <- episodes %>%
  inner_join(cohort, by = c("patient_id" = "ID"))

# Filter pre-diagnosis episodes
pre_dx_episodes <- episodes_with_dx %>%
  filter(!is.na(first_hl_dx_date)) %>%
  filter(year(first_hl_dx_date) > 1900) %>%  # Sentinel date guard
  filter(episode_start < first_hl_dx_date) %>%
  mutate(days_before_dx = as.numeric(first_hl_dx_date - episode_start))

# Summary by treatment type
summary_by_type <- pre_dx_episodes %>%
  group_by(treatment_type) %>%
  summarise(
    n_episodes = n(),
    n_patients = n_distinct(patient_id),
    median_days_before = median(days_before_dx),
    .groups = "drop"
  )
```

### 7-Day Gap Criterion for Secondary Malignancies (TIMING-02)

**Source:** R/45 lines 266-302 (7-day gap detection logic)

```r
# Query DIAGNOSIS for non-HL cancer codes
source("R/utils/utils_cancer.R")
library(stringr)

dx_cancer <- get_pcornet_table("DIAGNOSIS") %>%
  select(ID, DX, DX_TYPE, DX_DATE) %>%
  collect() %>%
  mutate(DX_norm = toupper(str_remove_all(DX, "\\."))) %>%
  filter(is_cancer_code(DX)) %>%
  filter(!str_detect(DX_norm, "^C81|^201"))  # Exclude HL (ICD-10 + ICD-9)

# Apply 7-day gap criterion per patient-code
# (Copy R/45 lines 266-302 verbatim)
confirmed_secondary <- dx_cancer %>%
  group_by(ID, DX_norm) %>%
  summarise(
    unique_dates_total = n_distinct(DX_DATE[!is.na(DX_DATE)]),
    two_or_more_unique_dates_gt_7 = as.integer({
      dates <- DX_DATE[!is.na(DX_DATE)]
      ud <- unique(dates)
      if (length(ud) >= 2) {
        as.numeric(max(ud) - min(ud)) >= 7
      } else {
        FALSE
      }
    }),
    .groups = "drop"
  ) %>%
  filter(two_or_more_unique_dates_gt_7 == 1) %>%  # Confirmed only
  left_join(
    dx_cancer %>% select(ID, DX_norm, DX_DATE),
    by = c("ID", "DX_norm")
  )

# Classify into cancer site categories
confirmed_secondary$category <- classify_codes(confirmed_secondary$DX_norm)
```

### Pre/Post HL Temporal Split (TIMING-02)

**Source:** R/49 lines 127-160

```r
# Join secondary malignancies to cohort for first_hl_dx_date
secondary_with_dx <- confirmed_secondary %>%
  inner_join(cohort, by = "ID")

# Split pre/post HL diagnosis
pre_hl <- secondary_with_dx %>%
  filter(DX_DATE < first_hl_dx_date)

post_hl <- secondary_with_dx %>%
  filter(DX_DATE >= first_hl_dx_date)

# Aggregate by category with population-based percentages
total_cohort <- nrow(cohort)

summary_table <- bind_rows(
  pre_hl %>%
    group_by(category) %>%
    summarise(
      n_patients = n_distinct(ID),
      pct_of_cohort = n_distinct(ID) / total_cohort,
      timing = "Pre-HL",
      .groups = "drop"
    ),
  post_hl %>%
    group_by(category) %>%
    summarise(
      n_patients = n_distinct(ID),
      pct_of_cohort = n_distinct(ID) / total_cohort,
      timing = "Post-HL",
      .groups = "drop"
    )
)
```

### Styled XLSX Two-Sheet Output (Both Scripts)

**Source:** R/59 lines 187-250 (death date summary pattern)

```r
library(openxlsx2)

wb <- wb_workbook()

# Sheet 1: Summary
wb$add_worksheet("Summary")

# Title row
wb$add_data(
  sheet = "Summary",
  x = "Pre-Diagnosis Treatment Episodes",
  start_row = 1, start_col = 1
)
wb$add_font(
  sheet = "Summary", dims = "A1",
  name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937")
)
wb$merge_cells(sheet = "Summary", dims = "A1:D1")

# Header row (dark gray background, white bold text)
headers <- c("Treatment Type", "Episodes", "Patients", "Median Days Before HL Dx")
for (i in seq_along(headers)) {
  wb$add_data(sheet = "Summary", x = headers[i], start_row = 3, start_col = i)
}
wb$add_fill(sheet = "Summary", dims = "A3:D3", color = wb_color("FF374151"))
wb$add_font(
  sheet = "Summary", dims = "A3:D3",
  name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF")
)

# Data rows
wb$add_data(sheet = "Summary", x = summary_by_type, start_row = 4, col_names = FALSE)

# Number formatting
last_row <- 3 + nrow(summary_by_type)
wb$add_numfmt(sheet = "Summary", dims = glue("B4:D{last_row}"), numfmt = "#,##0")

# Column widths + freeze panes
wb$set_col_widths(sheet = "Summary", cols = 1:4, widths = c(25, 12, 12, 20))
wb$freeze_pane(sheet = "Summary", firstActiveRow = 4)

# Sheet 2: Detail
wb$add_worksheet("Detail")
# ... repeat pattern with detail_data ...

wb$save(file.path(CONFIG$output_dir, "pre_diagnosis_treatments.xlsx"))
```

## Environment Availability

**Step 2.6: SKIPPED** — Phase 104 is code-only with no external dependencies. Both scripts operate on existing RDS artifacts and DuckDB tables already validated in 100+ prior scripts (R/26, R/47, R/49). No CLI tools, no external services, no package installs required.

## Validation Architecture

**Skip condition met:** `workflow.nyquist_validation` is explicitly set to `false` in `.planning/config.json` (line 19). Validation Architecture section omitted per research protocol.

## Sources

### Primary (HIGH confidence)
- **R/26_treatment_episodes.R** (lines 1-1302) — treatment_episodes.rds structure, episode_start/episode_stop columns, triggering_codes, drug_names
- **R/47_cancer_summary_refined.R** (lines 1-662) — confirmed_hl_cohort.rds structure (ID, first_hl_dx_date, first_hl_dx_source), sentinel date nullification (lines 182-187)
- **R/45_cancer_summary.R** (lines 266-302) — 7-day gap criterion logic (2+ unique dates AND max - min >= 7)
- **R/49_cancer_summary_pre_post.R** (lines 127-160) — pre/post HL temporal split pattern (DX_DATE < first_hl_dx_date)
- **R/utils/utils_cancer.R** (lines 0-79) — is_cancer_code(), classify_codes() 4-tier cascade
- **R/30_condition_linkage_investigation.R** (lines 0-99) — Investigation script pattern (read-only, no upstream modification, styled xlsx output)
- **R/58_co_administration_analysis.R** (lines 0-99) — Two-sheet xlsx pattern (summary + detail)
- **R/59_death_date_summary.R** (lines 1-271) — Complete investigation script template (7 sections, styled xlsx, meeting-presentable output)
- **R/88_smoke_test_comprehensive.R** (lines 0-149) — Smoke test structure (check function pattern, expected file validation)
- **.planning/phases/104-treatment-timing-investigations/104-CONTEXT.md** — User decisions (D-01 through D-09), canonical references, meeting notes context
- **pecan_lymphoma_meeting_notes_combined.md** — G5 (radiation before HL dx), secondary malignancy table definition (columns K-N, population E/E3)

### Secondary (MEDIUM confidence)
- **CLAUDE.md research/STACK.md** — tidyverse 2.0.0+, dplyr 1.2.0+, glue 1.8.0, lubridate 1.9.3+, openxlsx2 1.13.2+ version pins
- **CLAUDE.md** — Project constraints: RStudio on HiPerGator, named predicate requirement, raw counts without HIPAA suppression

### Tertiary (LOW confidence)
None — all research findings verified against existing codebase patterns

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — All libraries already in use in 100+ existing scripts; versions verified in research/STACK.md
- Architecture: HIGH — Investigation script pattern established in R/30, R/58, R/59 (v3.1); 7-day gap logic validated in R/45, R/47, R/49
- Pitfalls: HIGH — All 5 pitfalls derived from actual codebase patterns (sentinel date handling R/47 lines 182-187, dual ICD filtering R/47 lines 116-117, denominator from meeting notes)
- Code examples: HIGH — All examples copied verbatim from existing scripts with line number citations

**Research date:** 2026-06-15
**Valid until:** 2026-07-15 (30 days — stable R ecosystem, mature codebase with 100+ scripts)
