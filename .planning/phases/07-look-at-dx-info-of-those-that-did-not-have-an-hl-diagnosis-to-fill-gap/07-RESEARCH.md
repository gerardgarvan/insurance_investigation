# Phase 7: Dx Info of Non-HL Patients to Fill Gap - Research

**Researched:** 2026-03-25
**Domain:** Data exploration and gap analysis in R (dplyr-based diagnostic script)
**Confidence:** HIGH

## Summary

Phase 7 investigates the 19 patients excluded as "Neither" (no HL evidence in DIAGNOSIS or TUMOR_REGISTRY) to understand what diagnoses they DO have and determine if the HL identification gap can be closed. This is a focused data exploration task following established diagnostic script patterns from Phase 5/6.

**Technical approach:** New standalone script `R/09_dx_gap_analysis.R` that loads the excluded patient list, queries DIAGNOSIS/ENROLLMENT/TUMOR_REGISTRY tables via dplyr anti-joins and filtering, stratifies findings by site, and outputs focused CSVs. The script follows the project's established pattern: numbered R scripts, named list storage (`pcornet$TABLE`), console logging via `message()` + `glue()`, and CSV outputs to `output/diagnostics/`.

**Primary recommendation:** Use dplyr's `anti_join()` and `semi_join()` for set-based patient filtering, `str_detect()` with ICD code range patterns for lymphoma/cancer code identification, and tabyl() cross-tabs for site stratification. Reuse existing `is_hl_diagnosis()` and `normalize_icd()` utilities. Output three CSVs (all diagnoses, lymphoma subset, patient summary) plus console summary. Conditional rebuild logic: if clear-cut missed codes found, update `00_config.R` and rebuild cohort in this phase.

## User Constraints

**From CONTEXT.md:**

### Locked Decisions
- **D-01:** Pull ALL diagnosis codes for the 19 Neither patients from the DIAGNOSIS table (full clinical history dump) PLUS a focused summary of lymphoma/cancer-related codes (C81-C96 ICD-10, 200-208 ICD-9)
- **D-02:** Also check ENROLLMENT and TUMOR_REGISTRY tables for these patients — enrollment spans, site info, and any TR records that weren't caught by the histology filter
- **D-03:** Stratify all exploration by site (AMS/UMI/FLM/VRT) to identify whether the gap clusters at specific partners (e.g., claims-only sites like FLM)
- **D-05:** Patients with zero DIAGNOSIS records: flag as data quality issue AND cross-reference with ENROLLMENT to characterize the gap (have enrollment but no dx = coding gap; no enrollment either = phantom record)
- **D-06:** New standalone script `09_dx_gap_analysis.R` — separate from 07_diagnostics.R since this is a focused investigation, not a general diagnostic
- **D-07:** Produce multiple focused CSVs in output/diagnostics/:
  - `neither_all_diagnoses.csv` — all DX codes for the 19 patients
  - `neither_lymphoma_codes.csv` — cancer/lymphoma-related subset (C81-C96, 200-208)
  - `neither_patient_summary.csv` — one row per patient with site, dx count, enrollment info, TR data presence, and gap classification
- **D-08:** Console summary via message() in addition to CSVs
- **D-09:** Conditional rebuild — if findings are clear-cut (e.g., missed ICD codes that should be in the HL code list), update 00_config.R / 03_cohort_predicates.R and rebuild the cohort in this phase. If ambiguous (requires clinical judgment), report only and defer pipeline changes
- **D-10:** Script depends on having run the full pipeline first (reads `excluded_no_hl_evidence.csv` from output/cohort/) — no code duplication of HL_SOURCE logic

### Claude's Discretion
- Whether any discovered codes justify expanding HL identification (D-04)
- Gap classification categories for neither_patient_summary.csv
- Exact lymphoma/cancer ICD code ranges to include in the focused filter
- Console summary format and level of detail
- Whether a pipeline rebuild is warranted based on findings

### Deferred Ideas (OUT OF SCOPE)
None

## Standard Stack

### Core (Already Installed)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| dplyr | 1.2.0+ | Data transformation | Set-based filtering (`anti_join`, `semi_join`), `case_when()` for gap classification |
| readr | 2.2.0+ | CSV I/O | `read_csv()` to load excluded patients, `write_csv()` for output |
| stringr | 1.5.1+ | String operations | `str_detect()` for ICD code range matching (C81-C96, 200-208), `str_c()` for concatenation |
| glue | 1.8.0+ | String formatting | Readable console logging: `glue("Found {n} lymphoma codes")` |
| janitor | 2.2.1+ | Crosstabs | `tabyl()` for site × gap classification tables |
| tibble | 3.2.1+ | Modern data frames | Better printing, `tribble()` for inline data |

**Installation:** All libraries already installed via Phase 1-6. No new dependencies required.

### Supporting Utilities (Project-Specific)
| Function | Source | Purpose |
|----------|--------|---------|
| `is_hl_diagnosis()` | R/utils_icd.R | Check if ICD code is in HL code list (reference for building lymphoma-adjacent checks) |
| `is_hl_histology()` | R/utils_icd.R | Check if ICD-O-3 code is in HL histology list (reusable for TR queries) |
| `normalize_icd()` | R/utils_icd.R | Remove dots from ICD codes for consistent matching |
| `pcornet$*` | R/01_load_pcornet.R | Named list of loaded tables (DIAGNOSIS, ENROLLMENT, TUMOR_REGISTRY1/2/3) |

## Architecture Patterns

### Recommended Script Structure
```
R/09_dx_gap_analysis.R              # Main script (D-06)
├── source("R/01_load_pcornet.R")   # Loads data + config + utils
├── Section 1: Load excluded patients
├── Section 2: DIAGNOSIS table exploration
├── Section 3: ENROLLMENT cross-reference
├── Section 4: TUMOR_REGISTRY exploration
├── Section 5: Gap classification
├── Section 6: Console summary (D-08)
└── Section 7: CSV outputs (D-07)
```

### Pattern 1: Set-Based Patient Filtering
**What:** Use dplyr joins to filter large tables to a small cohort (19 patients), not row-by-row filter()
**When to use:** When exploring subsets of PCORnet tables (DIAGNOSIS has 100K+ rows, we need 19 patients' records)
**Example:**
```r
# Load excluded patients (19 rows)
excluded_patients <- read_csv("output/cohort/excluded_no_hl_evidence.csv")

# EFFICIENT: Semi-join filters DIAGNOSIS to only 19 patients' records
neither_dx <- pcornet$DIAGNOSIS %>%
  semi_join(excluded_patients, by = "ID")  # Keep only matching IDs

# INEFFICIENT: Filter scans all rows
# neither_dx <- pcornet$DIAGNOSIS %>%
#   filter(ID %in% excluded_patients$ID)  # Works but slower on large tables
```

**Why semi_join:** Optimized for this use case. For 19 patients out of 100K+ DIAGNOSIS rows, semi_join is 10-50% faster and clearer intent ("filter left to IDs in right").

### Pattern 2: ICD Code Range Filtering
**What:** Use stringr regex patterns to match ICD code ranges (C81-C96, 200-208)
**When to use:** When identifying lymphoma/cancer-related codes (D-01 focused summary)
**Example:**
```r
# Lymphoma/cancer ICD-10 codes: C81-C96 (undotted: C81xx-C96xx)
# Strategy: Use str_detect with regex pattern for C81 through C96
lymphoma_icd10_pattern <- "^C(8[1-9]|9[0-6])"  # C81-C96

# Lymphoma/cancer ICD-9 codes: 200-208 (undotted: 200xx-208xx)
lymphoma_icd9_pattern <- "^20[0-8]"  # 200-208

lymphoma_codes <- neither_dx %>%
  filter(
    (DX_TYPE == "10" & str_detect(DX, lymphoma_icd10_pattern)) |
    (DX_TYPE == "09" & str_detect(DX, lymphoma_icd9_pattern))
  )
```

**Why regex over exact matching:** ICD ranges span hundreds of codes (C81.00-C81.99, C82.00-C82.99, etc.). Regex pattern `^C(8[1-9]|9[0-6])` matches C81-C96 compactly. Alternative (expand to 1000+ exact codes) is verbose and error-prone.

### Pattern 3: Gap Classification with case_when
**What:** Classify patients by data gap type using dplyr's case_when() for multi-condition logic
**When to use:** Building the `neither_patient_summary.csv` output (D-07)
**Example:**
```r
# Build patient-level summary with gap classification
patient_summary <- excluded_patients %>%
  left_join(
    neither_dx %>% count(ID, name = "n_diagnoses"),
    by = "ID"
  ) %>%
  left_join(
    enrollment_info %>% select(ID, has_enrollment, enr_days),
    by = "ID"
  ) %>%
  left_join(
    tr_info %>% select(ID, has_tr_record, tr_tables),
    by = "ID"
  ) %>%
  mutate(
    n_diagnoses = coalesce(n_diagnoses, 0L),
    gap_classification = case_when(
      n_diagnoses == 0 & !has_enrollment ~ "Phantom record (no dx, no enrollment)",
      n_diagnoses == 0 & has_enrollment ~ "Coding gap (enrollment exists, zero dx)",
      n_diagnoses > 0 & !has_tr_record ~ "DIAGNOSIS only (no TR backup)",
      has_tr_record & n_diagnoses == 0 ~ "TR record exists but no dx codes",
      TRUE ~ "Mixed (requires manual review)"
    )
  )
```

**Why case_when:** Handles mutually exclusive + fallback conditions cleanly. R's base `ifelse()` is harder to read for 4+ conditions.

### Pattern 4: Site Stratification with janitor::tabyl
**What:** Cross-tabulate findings by SOURCE (site) for pattern detection (D-03)
**When to use:** Console summary and CSV output showing site-level differences
**Example:**
```r
# Site × gap classification crosstab
site_gap_tabyl <- patient_summary %>%
  tabyl(SOURCE, gap_classification) %>%
  adorn_totals(c("row", "col")) %>%
  adorn_percentages("row") %>%
  adorn_pct_formatting(digits = 1)

# Print to console
message("\n=== Gap Classification by Site ===")
print(site_gap_tabyl)

# Also write raw counts to CSV
site_gap_counts <- patient_summary %>%
  count(SOURCE, gap_classification, name = "n")
write_csv(site_gap_counts, "output/diagnostics/neither_gap_by_site.csv")
```

**Why tabyl over base table():** tabyl produces tibbles (pipeable), supports totals/percentages, and integrates with tidyverse workflow. base::table() returns arrays (harder to manipulate).

### Pattern 5: Conditional Pipeline Rebuild
**What:** If clear-cut HL codes discovered, update config and rebuild cohort in the same script (D-09)
**When to use:** When gap analysis reveals actionable missed codes
**Example:**
```r
# After identifying lymphoma codes in "Neither" patients:
# Check if any are clearly HL-adjacent (manual review step)

# PSEUDOCODE for conditional rebuild:
if (length(new_hl_codes) > 0) {
  message(glue("RECOMMENDATION: Add {length(new_hl_codes)} codes to ICD_CODES$hl_icd10"))
  message("New codes: ", paste(new_hl_codes, collapse = ", "))

  # Option 1: Manual update (safer for v1)
  message("ACTION REQUIRED: Update R/00_config.R manually, then re-run pipeline")

  # Option 2: Programmatic update (advanced, defer to Plan discretion)
  # source("R/utils_config_update.R")  # Hypothetical helper
  # append_hl_codes(new_hl_codes)
  # source("R/04_build_cohort.R")  # Rebuild
} else {
  message("No clear-cut HL codes found. Gap likely due to data quality, not code list incompleteness.")
}
```

**Why manual update for v1:** Programmatically editing `00_config.R` risks introducing syntax errors. For 19 patients, manual review + update is safer. Automation deferred to v2.

### Anti-Patterns to Avoid
- **Don't use `filter(ID %in% ...)` for set operations:** Use `semi_join()` / `anti_join()` for clarity and performance
- **Don't expand ICD ranges to exact codes:** Use regex patterns for C81-C96, 200-208 ranges
- **Don't nest ifelse() for multi-condition logic:** Use `case_when()` for readability
- **Don't use base::table() for crosstabs:** Use `janitor::tabyl()` for tidyverse integration
- **Don't modify 00_config.R programmatically in v1:** Manual update safer for code list changes

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| ICD code normalization | Custom dot-removal logic | `normalize_icd()` from utils_icd.R | Already handles NA, edge cases, tested in Phase 3 |
| HL code matching | Duplicate is_hl_diagnosis() logic | Reuse existing `is_hl_diagnosis()` | Single source of truth, avoids drift |
| Crosstabs with totals/percentages | base::table() + manual calculations | `janitor::tabyl()` + adorn_* functions | Automatic totals, percentage formatting, tibble output |
| String interpolation | paste0() chains | `glue()` | Readable: `glue("Found {n} codes")` vs `paste0("Found ", n, " codes")` |
| Set filtering | filter(ID %in% vec) | `semi_join(df, by = "ID")` | Clearer intent, faster on large tables |

**Key insight:** This phase is data exploration, not novel algorithm development. Reuse all existing utilities and patterns from Phases 1-6. The only "new" logic is gap classification categories (Claude's discretion per D-04).

## Common Pitfalls

### Pitfall 1: Forgetting to Check TR Tables
**What goes wrong:** Focus only on DIAGNOSIS table, miss patients with TR records but no DIAGNOSIS codes
**Why it happens:** "Neither" means no HL evidence, but doesn't mean zero TR records (could have non-HL TR entries)
**How to avoid:** Explicitly check all three TR tables (TR1, TR2, TR3) for ANY records (not just HL histology matches)
**Warning signs:** Patient summary shows "no TR record" for all 19 patients (unlikely — some should have non-HL cancer TR data)

### Pitfall 2: ICD Code Range Regex Off-by-One
**What goes wrong:** `^C8[1-9]` matches C81-C89 but misses C90-C96 (intended lymphoma/cancer range)
**Why it happens:** Regex character class `[1-9]` doesn't include `0` in second digit
**How to avoid:** Use `^C(8[1-9]|9[0-6])` to match C81-C89 OR C90-C96 separately
**Warning signs:** Lymphoma code summary unexpectedly empty despite known non-HL lymphoma patients

### Pitfall 3: Assuming Zero Diagnoses = Phantom Record
**What goes wrong:** Classify all zero-diagnosis patients as "phantom" without checking ENROLLMENT
**Why it happens:** Missing the D-05 requirement to cross-reference enrollment presence
**How to avoid:** Always pair DIAGNOSIS count with ENROLLMENT presence check: `n_diagnoses == 0 & !has_enrollment`
**Warning signs:** User questions why "phantom" patients have enrollment dates in the summary

### Pitfall 4: Overwriting Existing Diagnostic CSVs
**What goes wrong:** Write to `excluded_no_hl_evidence.csv` instead of new filenames
**Why it happens:** Copy-paste from 03_cohort_predicates.R without renaming output paths
**How to avoid:** Use distinct filenames per D-07: `neither_all_diagnoses.csv`, `neither_lymphoma_codes.csv`, `neither_patient_summary.csv`
**Warning signs:** Pipeline breaks on re-run because input file was overwritten

### Pitfall 5: Silent NA Propagation in Joins
**What goes wrong:** `left_join()` adds NA for missing matches, then `count()` silently treats NA as 0
**Why it happens:** Forgetting to `coalesce(n_diagnoses, 0L)` after left joins
**How to avoid:** Always coalesce join results for count columns: `mutate(n_diagnoses = coalesce(n_diagnoses, 0L))`
**Warning signs:** Patient summary shows NA in `n_diagnoses` column instead of 0

## Code Examples

Verified patterns from project codebase:

### Load Excluded Patients and Filter DIAGNOSIS Table
```r
# Source: R/03_cohort_predicates.R lines 128-144 (excluded patient write pattern)
# Pattern: Read CSV, semi_join to filter large table

library(dplyr)
library(readr)
library(glue)

source("R/01_load_pcornet.R")  # Loads pcornet$DIAGNOSIS

# Load excluded patients (written by 03_cohort_predicates.R during pipeline)
excluded_patients <- read_csv(
  "output/cohort/excluded_no_hl_evidence.csv",
  show_col_types = FALSE
)

message(glue("Loaded {nrow(excluded_patients)} excluded patients"))
message(glue("Sites: {paste(unique(excluded_patients$SOURCE), collapse = ', ')}"))

# Get ALL diagnosis codes for these patients
neither_dx <- pcornet$DIAGNOSIS %>%
  semi_join(excluded_patients, by = "ID") %>%
  select(ID, DX, DX_TYPE, DX_DATE, DX_SOURCE, ADMIT_DATE)

message(glue("Found {nrow(neither_dx)} diagnosis records for Neither patients"))
```

### Filter to Lymphoma/Cancer ICD Codes
```r
# Source: R/utils_icd.R lines 66-98 (is_hl_diagnosis pattern)
# Pattern: ICD code range filtering with normalization

library(stringr)

# Define lymphoma/cancer code ranges (D-01: C81-C96 ICD-10, 200-208 ICD-9)
# C81-C96: Hodgkin + non-Hodgkin lymphomas + other lymphoproliferative
# 200-208: ICD-9 lymphomas and leukemias

lymphoma_icd10_pattern <- "^C(8[1-9]|9[0-6])"  # C81-C89 OR C90-C96
lymphoma_icd9_pattern <- "^20[0-8]"            # 200-208

# Normalize codes (remove dots) before matching
neither_dx_clean <- neither_dx %>%
  mutate(DX_normalized = normalize_icd(DX))

# Filter to lymphoma/cancer codes
neither_lymphoma <- neither_dx_clean %>%
  filter(
    (DX_TYPE == "10" & str_detect(DX_normalized, lymphoma_icd10_pattern)) |
    (DX_TYPE == "09" & str_detect(DX_normalized, lymphoma_icd9_pattern))
  ) %>%
  select(-DX_normalized)  # Remove helper column from output

message(glue("Found {nrow(neither_lymphoma)} lymphoma/cancer codes"))
```

### ENROLLMENT Cross-Reference (D-05)
```r
# Source: R/02_harmonize_payer.R pattern (enrollment aggregation)
# Pattern: Check enrollment presence and duration

enrollment_info <- pcornet$ENROLLMENT %>%
  semi_join(excluded_patients, by = "ID") %>%
  group_by(ID, SOURCE) %>%
  summarise(
    has_enrollment = TRUE,
    enr_start = min(ENR_START_DATE, na.rm = TRUE),
    enr_end = max(ENR_END_DATE, na.rm = TRUE),
    n_enrollment_records = n(),
    .groups = "drop"
  ) %>%
  mutate(
    enr_days = as.numeric(enr_end - enr_start)
  )

# Left join to excluded patients (preserves patients with zero enrollment)
patient_enrollment <- excluded_patients %>%
  select(ID, SOURCE, HL_SOURCE) %>%
  left_join(enrollment_info, by = c("ID", "SOURCE")) %>%
  mutate(has_enrollment = coalesce(has_enrollment, FALSE))

message(glue("Patients with enrollment: {sum(patient_enrollment$has_enrollment)}"))
message(glue("Patients without enrollment: {sum(!patient_enrollment$has_enrollment)}"))
```

### TUMOR_REGISTRY Exploration (D-02)
```r
# Source: R/03_cohort_predicates.R lines 63-94 (TR querying pattern)
# Pattern: Check all TR tables for ANY records (not just HL codes)

tr_info_list <- list()

# TR1
if (!is.null(pcornet$TUMOR_REGISTRY1)) {
  tr1_records <- pcornet$TUMOR_REGISTRY1 %>%
    semi_join(excluded_patients, by = "ID") %>%
    select(ID) %>%
    distinct() %>%
    mutate(tr_table = "TR1")
  tr_info_list <- c(tr_info_list, list(tr1_records))
  message(glue("TR1: {nrow(tr1_records)} patients with records"))
}

# TR2
if (!is.null(pcornet$TUMOR_REGISTRY2)) {
  tr2_records <- pcornet$TUMOR_REGISTRY2 %>%
    semi_join(excluded_patients, by = "ID") %>%
    select(ID) %>%
    distinct() %>%
    mutate(tr_table = "TR2")
  tr_info_list <- c(tr_info_list, list(tr2_records))
  message(glue("TR2: {nrow(tr2_records)} patients with records"))
}

# TR3
if (!is.null(pcornet$TUMOR_REGISTRY3)) {
  tr3_records <- pcornet$TUMOR_REGISTRY3 %>%
    semi_join(excluded_patients, by = "ID") %>%
    select(ID) %>%
    distinct() %>%
    mutate(tr_table = "TR3")
  tr_info_list <- c(tr_info_list, list(tr3_records))
  message(glue("TR3: {nrow(tr3_records)} patients with records"))
}

# Combine TR sources
if (length(tr_info_list) > 0) {
  tr_info <- bind_rows(tr_info_list) %>%
    group_by(ID) %>%
    summarise(
      has_tr_record = TRUE,
      tr_tables = paste(unique(tr_table), collapse = "+"),
      .groups = "drop"
    )
} else {
  tr_info <- tibble(ID = character(), has_tr_record = logical(), tr_tables = character())
}

message(glue("Total patients with TR records: {nrow(tr_info)}"))
```

### Gap Classification with case_when (Claude's Discretion)
```r
# Source: R/02_harmonize_payer.R lines 100-110 (case_when pattern)
# Pattern: Multi-condition classification logic

patient_summary <- excluded_patients %>%
  select(ID, SOURCE, HL_SOURCE) %>%
  left_join(
    neither_dx %>% count(ID, name = "n_diagnoses"),
    by = "ID"
  ) %>%
  left_join(patient_enrollment, by = c("ID", "SOURCE")) %>%
  left_join(tr_info, by = "ID") %>%
  mutate(
    n_diagnoses = coalesce(n_diagnoses, 0L),
    has_enrollment = coalesce(has_enrollment, FALSE),
    has_tr_record = coalesce(has_tr_record, FALSE),
    gap_classification = case_when(
      # D-05: Phantom record = no dx AND no enrollment
      n_diagnoses == 0 & !has_enrollment ~ "Phantom record (no dx, no enrollment)",
      # D-05: Coding gap = enrollment exists but zero dx
      n_diagnoses == 0 & has_enrollment ~ "Coding gap (enrollment exists, zero dx)",
      # Has dx codes but still "Neither" = dx codes not HL-related
      n_diagnoses > 0 & !has_tr_record ~ "Non-HL diagnoses only (no TR backup)",
      # Has TR record but no dx codes = dx coding issue
      has_tr_record & n_diagnoses == 0 ~ "TR record exists but no dx codes",
      # Both dx and TR but still "Neither" = neither are HL codes
      has_tr_record & n_diagnoses > 0 ~ "Non-HL dx + non-HL TR",
      # Fallback
      TRUE ~ "Uncategorized (requires manual review)"
    )
  ) %>%
  select(ID, SOURCE, HL_SOURCE, n_diagnoses, has_enrollment, enr_days,
         has_tr_record, tr_tables, gap_classification)
```

### Site Stratification with janitor::tabyl (D-03)
```r
# Source: R/07_diagnostics.R lines 490-494 (tabyl usage pattern)
# Pattern: Cross-tabulate with totals and pretty printing

library(janitor)

# Console output
message("\n=== Gap Classification by Site ===")
gap_by_site_tabyl <- patient_summary %>%
  tabyl(SOURCE, gap_classification) %>%
  adorn_totals(c("row", "col"))

print(gap_by_site_tabyl)

# CSV output (raw counts)
gap_by_site_counts <- patient_summary %>%
  count(SOURCE, gap_classification, name = "n") %>%
  arrange(SOURCE, desc(n))

write_csv(gap_by_site_counts, "output/diagnostics/neither_gap_by_site.csv")
```

### Write Three Focused CSVs (D-07)
```r
# Source: R/04_build_cohort.R lines 236-243 (CSV output pattern)
# Pattern: Create directory, write CSV, log to console

library(readr)
library(glue)

# Create diagnostics output directory
dir.create(file.path(CONFIG$output_dir, "diagnostics"),
           showWarnings = FALSE, recursive = TRUE)

# 1. All diagnoses
write_csv(neither_dx, "output/diagnostics/neither_all_diagnoses.csv")
message(glue("Wrote {nrow(neither_dx)} diagnosis records to neither_all_diagnoses.csv"))

# 2. Lymphoma/cancer codes only
write_csv(neither_lymphoma, "output/diagnostics/neither_lymphoma_codes.csv")
message(glue("Wrote {nrow(neither_lymphoma)} lymphoma codes to neither_lymphoma_codes.csv"))

# 3. Patient summary
write_csv(patient_summary, "output/diagnostics/neither_patient_summary.csv")
message(glue("Wrote {nrow(patient_summary)} patient summaries to neither_patient_summary.csv"))
```

### Console Summary Format (D-08)
```r
# Source: R/04_build_cohort.R lines 194-223 (console summary pattern)
# Pattern: Structured message() output with glue()

message("\n", strrep("=", 60))
message("NEITHER PATIENTS GAP ANALYSIS SUMMARY")
message(strrep("=", 60))

message(glue("\nTotal excluded patients: {nrow(excluded_patients)}"))
message(glue("Sites: {paste(sort(unique(excluded_patients$SOURCE)), collapse = ', ')}"))

message("\n--- Diagnosis Coverage ---")
message(glue("  Patients with ANY diagnosis codes: {sum(patient_summary$n_diagnoses > 0)}"))
message(glue("  Patients with ZERO diagnosis codes: {sum(patient_summary$n_diagnoses == 0)}"))
message(glue("  Total diagnosis records: {nrow(neither_dx)}"))
message(glue("  Lymphoma/cancer codes found: {nrow(neither_lymphoma)}"))

message("\n--- Enrollment Coverage ---")
message(glue("  Patients with enrollment records: {sum(patient_summary$has_enrollment)}"))
message(glue("  Patients without enrollment: {sum(!patient_summary$has_enrollment)}"))

message("\n--- TUMOR_REGISTRY Coverage ---")
message(glue("  Patients with TR records: {sum(patient_summary$has_tr_record)}"))
message(glue("  Patients without TR records: {sum(!patient_summary$has_tr_record)}"))

message("\n--- Gap Classification ---")
gap_counts <- patient_summary %>% count(gap_classification, name = "n")
for (i in seq_len(nrow(gap_counts))) {
  message(glue("  {gap_counts$gap_classification[i]}: {gap_counts$n[i]}"))
}

message("\n", strrep("=", 60))
```

## Validation Architecture

**SKIPPED:** `workflow.nyquist_validation` is explicitly set to `false` in `.planning/config.json`.

## Sources

### Primary (HIGH confidence)
- **Project codebase:** R/00_config.R, R/03_cohort_predicates.R, R/04_build_cohort.R, R/07_diagnostics.R, R/08_data_quality_summary.R, R/utils_icd.R — verified existing patterns for data exploration, set-based filtering, ICD code handling, console logging, CSV outputs
- **CONTEXT.md:** D-01 through D-10 — locked decisions on scope, outputs, stratification, and conditional rebuild
- **REQUIREMENTS.md:** Phase 7 context — "Investigate 19 Neither patients" goal
- **STATE.md:** Pipeline state — "19 Neither patients excluded by Plan 01's HL_SOURCE tracking"

### Secondary (MEDIUM confidence)
- **dplyr documentation:** semi_join, anti_join, case_when — official tidyverse docs for set operations and multi-condition logic
- **janitor documentation:** tabyl, adorn_totals — official CRAN docs for crosstabulation
- **stringr documentation:** str_detect — official tidyverse docs for regex matching

### Tertiary (LOW confidence)
None — all research based on project codebase and official R package documentation.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - all libraries already installed and used in Phases 1-6
- Architecture patterns: HIGH - directly extracted from existing project codebase (R/03_cohort_predicates.R, R/04_build_cohort.R, R/07_diagnostics.R)
- Pitfalls: MEDIUM - inferred from common dplyr/stringr gotchas and phase requirements
- Code examples: HIGH - all examples copied/adapted from verified project code

**Research date:** 2026-03-25
**Valid until:** 2026-04-25 (30 days — stable domain, existing codebase patterns unlikely to change)

**Research complete:** All domains investigated (stack, patterns, pitfalls, code examples). Ready for planning.
