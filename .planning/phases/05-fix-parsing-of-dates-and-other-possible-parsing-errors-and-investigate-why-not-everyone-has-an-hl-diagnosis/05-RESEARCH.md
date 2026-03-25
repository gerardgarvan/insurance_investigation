# Phase 5: Fix Parsing & Investigate HL Diagnosis Gaps - Research

**Researched:** 2026-03-25
**Domain:** Data quality auditing, date parsing, ICD-O-3 histology coding, PCORnet CDM validation
**Confidence:** HIGH

## Summary

Phase 5 addresses two critical data quality concerns: date parsing failures across 9 PCORnet CDM tables and incomplete HL diagnosis identification. The current pipeline identifies HL patients solely via DIAGNOSIS table ICD-9/10 codes, missing patients with HL evidence only in TUMOR_REGISTRY histology fields (ICD-O-3 codes 9650-9667). This phase produces both a reusable diagnostic script (07_diagnostics.R) and fixes to existing pipeline components.

The research confirms that TUMOR_REGISTRY tables use different column naming conventions: TR1 uses verbose NAACCR-derived names (HISTOLOGICAL_TYPE, DATE_OF_DIAGNOSIS), while TR2/TR3 use compact names (MORPH, DXDATE). The date column detection regex `(?i)(DATE|^DT_|^BDATE$|^DOD$|^DT_FU$|DXDATE)` already catches these patterns, but systematic auditing will reveal any missed columns. The dlookr package provides production-ready data quality diagnostics that can be integrated into a permanent diagnostic script.

**Primary recommendation:** Build 07_diagnostics.R around dlookr::diagnose() for systematic data quality checks, augmented with domain-specific audits (HL identification source comparison, date parsing validation, payer mapping cross-check). Expand has_hodgkin_diagnosis() to check TUMOR_REGISTRY HISTOLOGICAL_TYPE (TR1) and MORPH (TR2/TR3) fields for ICD-O-3 codes 9650-9667. Produce detailed Venn breakdown showing DIAGNOSIS-only, TR-only, both, and neither categories stratified by site.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Date parsing diagnosis:**
- D-01: Audit ALL 9 loaded tables for date parsing issues (ENROLLMENT, DIAGNOSIS, PROCEDURES, PRESCRIBING, ENCOUNTER, DEMOGRAPHIC, TUMOR_REGISTRY1/2/3)
- D-02: Unparseable dates: keep as NA in pipeline AND write diagnostic CSV (table, column, raw_value, row_count) to output/diagnostics/ for manual inspection
- D-03: Audit ALL regex patterns used for column detection — verify the date column detector regex catches all actual date columns by comparing against csv_columns.txt

**HL diagnosis gap investigation:**
- D-04: Expand HL identification to include TUMOR_REGISTRY histology codes (ICD-O-3 9650-9667)
- D-05: Add ICD_CODES$hl_histology vector to 00_config.R with ICD-O-3 histology codes for HL (9650-9667)
- D-06: Update has_hodgkin_diagnosis() predicate to check BOTH DIAGNOSIS (ICD-9/10 codes) AND TUMOR_REGISTRY (histology codes)
- D-07: Check all 3 TUMOR_REGISTRY tables for histology/morphology fields — TR1, TR2, TR3 may have different column names
- D-08: Produce full Venn-style breakdown: DIAGNOSIS-only, TR-only, both sources, neither. Break down by site (AMS/UMI/FLM/VRT) and by identification method (ICD-9 vs ICD-10 vs histology)
- D-09: Verify extract scope — check if ALL patients in DEMOGRAPHIC are supposed to have HL

**Fix vs report strategy:**
- D-10: Produce BOTH a reusable diagnostic script (07_diagnostics.R) AND fixes to existing scripts
- D-11: 07_diagnostics.R is a permanent reusable tool — kept in R/ alongside other scripts, re-runnable whenever data is reloaded or pipeline changes
- D-12: Diagnostic output goes to BOTH console (summary via message()) AND detailed CSVs in output/diagnostics/
- D-13: Fixes applied directly to existing pipeline scripts — no intermediate "patch later" step
- D-14: After fixes, rebuild cohort by re-running the full pipeline (load → harmonize → build) to produce updated hl_cohort.csv

**Other parsing errors scope:**
- D-15: Check column type mismatches — verify readr col_types specs match actual CSV data
- D-16: Check missing/extra columns — compare expected columns vs actual columns in each CSV
- D-17: Check encoding issues — non-UTF8 characters, BOM markers, embedded newlines in fields
- D-18: Numeric range checks — flag obviously wrong values (negative ages, dates before 1900, tumor sizes > 999mm)
- D-19: Audit TUMOR_REGISTRY column types — check all 314+ TR1 columns and 140+ TR2/TR3 columns, flag columns that look numeric or date-like but are loaded as character

**Payer audit:**
- D-20: Full audit of payer mapping — check if prefix rules are matching correctly, validate dual-eligible detection counts, compare against Python pipeline reference counts

### Claude's Discretion
- Exact implementation of the Venn-style HL breakdown (console table format, CSV structure)
- Which specific TUMOR_REGISTRY columns to scan for histology (explore actual column names in data)
- Plausible numeric ranges for range checks (standard clinical ranges)
- Order and structure of diagnostic script sections
- How to handle the cohort rebuild (single re-source vs separate step)

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope

</user_constraints>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| dlookr | 0.8.0+ | Automated data quality diagnosis | Production-ready diagnose() function returns missing counts, unique values, type info across all columns; generates HTML/PDF reports |
| readr | 2.2.0+ | CSV loading and parse problem tracking | problems() function returns tibble of parse failures with row/col/expected/actual; already used in pipeline |
| dplyr | 1.2.0+ | Data manipulation | Already in stack; case_when() for conditional logic, group_by() for site-stratified breakdowns |
| stringr | 1.5.1+ | String pattern matching | Already in stack; str_detect() for histology code matching (9650-9667 range) |
| lubridate | 1.9.3+ | Date parsing | Already in stack; provides parse_date_time() with orders parameter for flexible date format detection |
| janitor | 2.2.1+ | Cross-tabulation and data cleaning | Already in stack; tabyl() for Venn breakdown (DIAGNOSIS vs TR source by site) |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| glue | 1.8.0 | String formatting for diagnostics | Already in stack; use for diagnostic messages and CSV filenames |
| here | 1.0.2 | Path management | Already in stack; use for output/diagnostics/ paths |
| forcats | 1.0.0+ | Factor reordering | Already in stack; use to order Venn breakdown categories (both → DIAGNOSIS-only → TR-only → neither) |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| dlookr | Manual dplyr summaries | dlookr automates missing counts, unique values, type checks in one call; manual approach requires 20+ lines per check |
| readr::problems() | Log unparsed values manually | problems() returns structured tibble with row/col/expected/actual; manual logging loses this structure |
| janitor::tabyl() | Base R table() | tabyl() returns data.frame (pipeable), handles 2-way and 3-way counts, supports adorn_* formatting; table() returns less flexible object |
| lubridate::parse_date_time() | Custom regex parser | lubridate handles 20+ date formats via orders parameter; custom regex requires case-by-case logic |

**Installation:**
```bash
# In R console (interactive session, run once)
install.packages(c("dlookr", "readr", "dplyr", "stringr", "lubridate", "janitor", "glue", "here", "forcats"))
renv::snapshot()
```

**Version verification:**
All core packages verified against CRAN as of 2026-03-25. dlookr 0.8.0 released 2024-10-15 (latest stable). readr 2.2.0 part of tidyverse 2.0.0 (July 2025). No breaking changes expected.

## Architecture Patterns

### Recommended Project Structure
```
R/
├── 00_config.R              # Add ICD_CODES$hl_histology vector
├── 01_load_pcornet.R        # Fix: audit date regex, update col_types if needed
├── 02_harmonize_payer.R     # Reference for payer audit
├── 03_cohort_predicates.R   # Fix: expand has_hodgkin_diagnosis() to check TR tables
├── 04_build_cohort.R        # Unchanged (re-run to rebuild cohort)
├── 05_visualize_waterfall.R # Unchanged
├── 06_visualize_sankey.R    # Unchanged
├── 07_diagnostics.R         # NEW: reusable diagnostic script
├── utils_dates.R            # Fix: add additional date formats if needed
├── utils_icd.R              # NEW: is_hl_histology() function for ICD-O-3 codes
└── utils_attrition.R        # Unchanged

output/
└── diagnostics/
    ├── date_parsing_failures.csv      # Table, column, raw_value, n_failures
    ├── column_type_mismatches.csv     # Table, column, expected_type, actual_sample
    ├── numeric_range_issues.csv       # Table, column, issue_type, n_affected, sample_values
    ├── hl_identification_venn.csv     # Site, source, n_patients (DIAGNOSIS/TR/both/neither)
    └── payer_mapping_audit.csv        # Category, n_patients_R, n_patients_Python, delta
```

### Pattern 1: Diagnostic Script with dlookr Integration
**What:** Reusable script that runs data quality checks on all loaded tables and writes detailed CSVs to output/diagnostics/
**When to use:** After every data load, before cohort building, when investigating data issues
**Example:**
```r
# Source: Adapted from dlookr vignette (https://cran.r-project.org/web/packages/dlookr/vignettes/diagonosis.html)
library(dlookr)
library(dplyr)
library(readr)
library(glue)

message("=== Data Quality Diagnostics ===")

# 1. Automated diagnosis across all tables
for (table_name in names(pcornet)) {
  if (!is.null(pcornet[[table_name]])) {
    message(glue("\n--- {table_name} ---"))

    # dlookr::diagnose() returns: variables, types, missing_count, missing_percent, unique_count, unique_rate
    diag <- diagnose(pcornet[[table_name]])

    # Flag high missing rates (>10%)
    high_missing <- diag %>% filter(missing_percent > 10)
    if (nrow(high_missing) > 0) {
      message(glue("  WARNING: {nrow(high_missing)} columns with >10% missing"))
      print(high_missing %>% select(variables, missing_percent))
    }
  }
}

# 2. Date parsing failures audit
date_failures <- data.frame()
for (table_name in names(pcornet)) {
  df <- pcornet[[table_name]]
  if (!is.null(df)) {
    date_cols <- names(df)[str_detect(names(df), "(?i)(DATE|^DT_|^BDATE$|^DOD$|^DT_FU$|DXDATE)")]
    for (col in date_cols) {
      if (is.character(df[[col]])) {
        # Column should have been parsed as date but is still character
        unparsed <- df %>%
          filter(!is.na(.data[[col]]) & nchar(trimws(.data[[col]])) > 0) %>%
          count(.data[[col]], name = "n_failures") %>%
          mutate(table = table_name, column = col) %>%
          select(table, column, raw_value = 1, n_failures)

        date_failures <- bind_rows(date_failures, unparsed)
      }
    }
  }
}

# Write to CSV
if (nrow(date_failures) > 0) {
  write_csv(date_failures, here("output", "diagnostics", "date_parsing_failures.csv"))
  message(glue("\nDate parsing failures: {nrow(date_failures)} unique patterns found"))
}
```

### Pattern 2: HL Identification Source Comparison (Venn Breakdown)
**What:** Compare HL identification via DIAGNOSIS (ICD-9/10) vs TUMOR_REGISTRY (ICD-O-3 histology) across sites
**When to use:** After expanding has_hodgkin_diagnosis() to check both sources
**Example:**
```r
# Source: Adapted from janitor tabyl vignette (https://cran.r-project.org/web/packages/janitor/vignettes/tabyls.html)
library(janitor)
library(dplyr)

# Get IDs from each source
dx_patients <- pcornet$DIAGNOSIS %>%
  filter(is_hl_diagnosis(DX, DX_TYPE)) %>%
  distinct(ID) %>%
  mutate(has_dx_code = 1)

tr_patients <- bind_rows(
  pcornet$TUMOR_REGISTRY1 %>%
    filter(is_hl_histology(HISTOLOGICAL_TYPE)) %>%
    select(ID),
  pcornet$TUMOR_REGISTRY2 %>%
    filter(is_hl_histology(MORPH)) %>%
    select(ID),
  pcornet$TUMOR_REGISTRY3 %>%
    filter(is_hl_histology(MORPH)) %>%
    select(ID)
) %>%
  distinct(ID) %>%
  mutate(has_tr_code = 1)

# Full join and categorize
all_patients <- pcornet$DEMOGRAPHIC %>%
  select(ID, SOURCE) %>%
  left_join(dx_patients, by = "ID") %>%
  left_join(tr_patients, by = "ID") %>%
  mutate(
    has_dx_code = coalesce(has_dx_code, 0L),
    has_tr_code = coalesce(has_tr_code, 0L),
    hl_source = case_when(
      has_dx_code == 1 & has_tr_code == 1 ~ "Both DIAGNOSIS and TR",
      has_dx_code == 1 & has_tr_code == 0 ~ "DIAGNOSIS only",
      has_dx_code == 0 & has_tr_code == 1 ~ "TR only",
      TRUE ~ "Neither (data quality issue)"
    )
  )

# Site-stratified breakdown using janitor::tabyl()
venn_breakdown <- all_patients %>%
  tabyl(SOURCE, hl_source) %>%
  adorn_totals(c("row", "col"))

print(venn_breakdown)

# Write to CSV
write_csv(all_patients %>% count(SOURCE, hl_source),
          here("output", "diagnostics", "hl_identification_venn.csv"))
```

### Pattern 3: ICD-O-3 Histology Matching Utility
**What:** Dedicated function to check if histology/morphology code is in HL range (9650-9667)
**When to use:** In expanded has_hodgkin_diagnosis() predicate and diagnostic Venn breakdown
**Example:**
```r
# Source: New utility function (pattern adapted from utils_icd.R normalize_icd())
# Add to utils_icd.R

#' Check if ICD-O-3 histology code is Hodgkin Lymphoma
#'
#' Matches against ICD-O-3 histology codes 9650-9667 defined in 00_config.R.
#' Handles both numeric (9650) and string ("9650") inputs.
#'
#' @param histology_code Character or numeric vector of histology codes
#' @return Logical vector indicating HL histology matches
#'
#' @examples
#' is_hl_histology(c("9650", "9663", "8000", NA))
#' # Returns: c(TRUE, TRUE, FALSE, FALSE)
#'
is_hl_histology <- function(histology_code) {
  if (length(histology_code) == 0) {
    return(logical(0))
  }

  # Initialize result as all FALSE
  result <- rep(FALSE, length(histology_code))

  # Handle NA: if histology_code is NA, result is FALSE
  valid <- !is.na(histology_code)

  if (!any(valid)) {
    return(result)
  }

  # Convert to character for consistent matching
  hist_char <- as.character(histology_code)

  # ICD_CODES$hl_histology is character vector from 00_config.R
  # Example: c("9650", "9651", ..., "9667")
  result[valid] <- hist_char[valid] %in% ICD_CODES$hl_histology

  return(result)
}
```

### Pattern 4: readr Parse Problems Diagnostic
**What:** Extract and log readr parse problems from CSV loading
**When to use:** After load_pcornet_table() calls to capture type coercion failures
**Example:**
```r
# Source: readr problems() documentation (https://readr.tidyverse.org/reference/problems.html)

# After loading a table with load_pcornet_table()
df <- load_pcornet_table("DIAGNOSIS", PCORNET_PATHS$DIAGNOSIS, DIAGNOSIS_SPEC)

# Extract parse problems
probs <- problems(df)

if (nrow(probs) > 0) {
  message(glue("DIAGNOSIS table: {nrow(probs)} parse problems"))

  # Summarize by column
  prob_summary <- probs %>%
    count(col, expected, name = "n_failures") %>%
    arrange(desc(n_failures))

  print(prob_summary)

  # Write detailed problems to CSV
  write_csv(probs %>% mutate(table = "DIAGNOSIS"),
            here("output", "diagnostics", "parse_problems_DIAGNOSIS.csv"))
}
```

### Anti-Patterns to Avoid
- **Don't ignore parse problems:** readr silently converts failed parses to NA. Always call problems() after loading and log results.
- **Don't assume histology codes are numeric:** TUMOR_REGISTRY tables store histology as character. Use character matching, not numeric comparison.
- **Don't rebuild cohort manually:** After fixes, re-source the full pipeline (01_load → 02_harmonize → 03_predicates → 04_build). Avoids version skew.
- **Don't hard-code diagnostic paths:** Use here("output", "diagnostics", filename) for portability across HiPerGator and local RStudio.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Data quality summary (missing counts, unique values, types) | Manual dplyr summaries per column | dlookr::diagnose(df) | dlookr returns all diagnostic stats in one call; handles numeric vs character columns automatically; extensible with diagnose_numeric(), diagnose_outlier() |
| Parse failure tracking | Custom error logging | readr::problems(df) | problems() returns structured tibble with row, col, expected, actual; integrates with readr's type inference system |
| Date format detection | Regex-based format guesser | lubridate::parse_date_time(x, orders = c("ymd", "dmy", "mdy")) | lubridate handles 20+ format combinations; orders parameter tries formats in sequence; locale support for non-English months |
| Cross-tabulation for Venn breakdown | Nested group_by() + summarize() | janitor::tabyl(df, var1, var2) | tabyl() returns data.frame (pipeable), supports adorn_totals() for row/col sums, handles 3-way counts for site × source × method |
| ICD-O-3 code range validation | if-else chains for 9650-9667 | hist_code %in% ICD_CODES$hl_histology | Centralized config avoids magic numbers; extensible to other histology ranges; single source of truth |

**Key insight:** Data quality auditing is a solved problem in R. dlookr provides production-ready diagnostics without reinventing missing value counters or type checkers. readr::problems() captures parse failures that would otherwise be silent NAs. Invest time in interpreting diagnostics, not building diagnostic infrastructure.

## Common Pitfalls

### Pitfall 1: Silent Date Parsing Failures
**What goes wrong:** parse_pcornet_date() returns NA for unparseable dates but doesn't log which values failed. Diagnostic script finds 200 NAs in ENR_START_DATE but doesn't know if they're legitimate nulls or parse failures.
**Why it happens:** lubridate functions (ymd(), parse_date_time()) convert parse failures to NA silently with only a warning count, not the actual failed values.
**How to avoid:** Before passing to parse_pcornet_date(), separate NA (legitimate null) from non-NA (attempted parse). Track unparsed values in a separate tibble: `unparsed <- df %>% filter(!is.na(raw_date) & is.na(parsed_date)) %>% count(raw_date)`. Write unparsed to CSV for manual inspection.
**Warning signs:** High NA counts in date columns (>10%) combined with zero entries in date_parsing_failures.csv diagnostic output.

### Pitfall 2: TUMOR_REGISTRY Column Name Inconsistency
**What goes wrong:** Code checks TUMOR_REGISTRY2$HISTOLOGICAL_TYPE (TR1 column name) but TR2 uses MORPH. Missing 100% of TR2 HL histology matches.
**Why it happens:** TR1 uses verbose NAACCR-derived names (314 columns with full descriptions), while TR2/TR3 use compact field codes (140 columns with abbreviated names). csv_columns.txt shows TR1 has HISTOLOGICAL_TYPE (column 3) and DATE_OF_DIAGNOSIS (column 7), but TR2/TR3 have MORPH (column 17) and DXDATE (column 3).
**How to avoid:** Check column existence before filtering: `if ("HISTOLOGICAL_TYPE" %in% names(pcornet$TUMOR_REGISTRY1))`. Use different column names for TR1 vs TR2/TR3. Document column mappings in 07_diagnostics.R comments.
**Warning signs:** Venn breakdown shows 0 patients identified via TUMOR_REGISTRY despite known HL cohort extract.

### Pitfall 3: ICD-O-3 Histology Code Format Confusion
**What goes wrong:** Histology codes stored as "9650/3" (includes behavior code /3 for malignant) but config lists "9650". String match fails.
**Why it happens:** ICD-O-3 morphology codes combine histology (9650) and behavior (/3 for malignant, /1 for benign). NAACCR stores these separately (histology in one field, behavior in another) but some systems concatenate them.
**How to avoid:** Check actual data format in TUMOR_REGISTRY tables first. If concatenated, use str_extract(MORPH, "^\\d{4}") to extract first 4 digits before matching. If separate, match histology field only (ignore behavior).
**Warning signs:** TUMOR_REGISTRY tables have records but is_hl_histology() returns all FALSE.

### Pitfall 4: dlookr::diagnose() Memory Usage on Large Tables
**What goes wrong:** diagnose(pcornet$ENCOUNTER) with 500K rows × 19 columns consumes 2GB RAM and times out on HiPerGator interactive sessions.
**Why it happens:** dlookr calculates unique values and missing patterns for every column. For high-cardinality columns (ENCOUNTERID with 500K unique values), this is expensive.
**How to avoid:** Run diagnose() on a sample for exploratory checks: `diagnose(pcornet$ENCOUNTER %>% slice_sample(n = 10000))`. For production diagnostic script, diagnose() only ID and SOURCE columns (low cardinality), use manual summarize() for high-cardinality columns.
**Warning signs:** R session hangs or shows "exceeded memory limit" when running 07_diagnostics.R.

### Pitfall 5: Venn Breakdown Doesn't Account for Multiple Tumors Per Patient
**What goes wrong:** Patient has 2 records in TUMOR_REGISTRY (primary HL + secondary cancer). Counted twice in "TR only" category, inflating totals.
**Why it happens:** TUMOR_REGISTRY tables have one row per tumor, not per patient. Patients with multiple primaries appear multiple times. distinct(ID) after filtering handles this, but if forgotten, counts are wrong.
**How to avoid:** Always use distinct(ID) after TUMOR_REGISTRY filtering: `pcornet$TUMOR_REGISTRY1 %>% filter(is_hl_histology(HISTOLOGICAL_TYPE)) %>% distinct(ID)`. Verify in diagnostic output: sum of Venn categories should equal nrow(pcornet$DEMOGRAPHIC).
**Warning signs:** Venn breakdown totals exceed total patients in DEMOGRAPHIC table.

## Code Examples

Verified patterns from tidyverse and dlookr official documentation:

### Example 1: Complete 07_diagnostics.R Script Structure
```r
# Source: Composite pattern from dlookr, readr, janitor documentation
# 07_diagnostics.R -- Reusable data quality diagnostic script

source("R/01_load_pcornet.R")  # Loads data and config

library(dlookr)
library(dplyr)
library(readr)
library(janitor)
library(glue)
library(here)

message(strrep("=", 60))
message("PCORnet Data Quality Diagnostics")
message(strrep("=", 60))

# Create diagnostics output directory
dir.create(here("output", "diagnostics"), showWarnings = FALSE, recursive = TRUE)

# ==============================================================================
# SECTION 1: Date Parsing Failures Audit
# ==============================================================================

message("\n=== Date Parsing Failures ===")

date_failures <- data.frame()
date_col_regex <- "(?i)(DATE|^DT_|^BDATE$|^DOD$|^DT_FU$|DXDATE)"

for (table_name in names(pcornet)) {
  df <- pcornet[[table_name]]
  if (!is.null(df)) {
    date_cols <- names(df)[str_detect(names(df), date_col_regex)]

    # Check if date columns were parsed as Date type
    for (col in date_cols) {
      if (!inherits(df[[col]], "Date")) {
        message(glue("  WARNING: {table_name}.{col} not parsed as Date (type: {class(df[[col]])[1]})"))

        # Get sample of unparsed values
        unparsed <- df %>%
          filter(!is.na(.data[[col]]) & nchar(trimws(as.character(.data[[col]]))) > 0) %>%
          count(.data[[col]], name = "n_failures", sort = TRUE) %>%
          slice_head(n = 10) %>%
          mutate(table = table_name, column = col) %>%
          rename(raw_value = 1) %>%
          select(table, column, raw_value, n_failures)

        date_failures <- bind_rows(date_failures, unparsed)
      }
    }
  }
}

if (nrow(date_failures) > 0) {
  write_csv(date_failures, here("output", "diagnostics", "date_parsing_failures.csv"))
  message(glue("\nWrote date_parsing_failures.csv: {nrow(date_failures)} unique patterns"))
} else {
  message("No date parsing failures detected")
}

# ==============================================================================
# SECTION 2: Column Type Audit (dlookr integration)
# ==============================================================================

message("\n=== Column Type and Missing Value Audit ===")

type_audit <- data.frame()

for (table_name in names(pcornet)) {
  df <- pcornet[[table_name]]
  if (!is.null(df)) {
    diag <- diagnose(df)

    # Flag high missing rates
    high_missing <- diag %>%
      filter(missing_percent > 20) %>%
      mutate(table = table_name) %>%
      select(table, column = variables, type = types, missing_percent)

    if (nrow(high_missing) > 0) {
      message(glue("{table_name}: {nrow(high_missing)} columns with >20% missing"))
      type_audit <- bind_rows(type_audit, high_missing)
    }
  }
}

if (nrow(type_audit) > 0) {
  write_csv(type_audit, here("output", "diagnostics", "high_missing_columns.csv"))
}

# ==============================================================================
# SECTION 3: HL Identification Source Comparison (Venn Breakdown)
# ==============================================================================

message("\n=== HL Identification Source Comparison ===")

# Get IDs from DIAGNOSIS table
dx_patients <- pcornet$DIAGNOSIS %>%
  filter(is_hl_diagnosis(DX, DX_TYPE)) %>%
  distinct(ID) %>%
  mutate(has_dx_code = 1)

# Get IDs from TUMOR_REGISTRY tables
tr1_patients <- if ("HISTOLOGICAL_TYPE" %in% names(pcornet$TUMOR_REGISTRY1)) {
  pcornet$TUMOR_REGISTRY1 %>%
    filter(is_hl_histology(HISTOLOGICAL_TYPE)) %>%
    distinct(ID)
} else {
  data.frame(ID = character())
}

tr2_patients <- if ("MORPH" %in% names(pcornet$TUMOR_REGISTRY2)) {
  pcornet$TUMOR_REGISTRY2 %>%
    filter(is_hl_histology(MORPH)) %>%
    distinct(ID)
} else {
  data.frame(ID = character())
}

tr3_patients <- if ("MORPH" %in% names(pcornet$TUMOR_REGISTRY3)) {
  pcornet$TUMOR_REGISTRY3 %>%
    filter(is_hl_histology(MORPH)) %>%
    distinct(ID)
} else {
  data.frame(ID = character())
}

tr_patients <- bind_rows(tr1_patients, tr2_patients, tr3_patients) %>%
  distinct(ID) %>%
  mutate(has_tr_code = 1)

# Full join and categorize
all_patients <- pcornet$DEMOGRAPHIC %>%
  select(ID, SOURCE) %>%
  left_join(dx_patients, by = "ID") %>%
  left_join(tr_patients, by = "ID") %>%
  mutate(
    has_dx_code = coalesce(has_dx_code, 0L),
    has_tr_code = coalesce(has_tr_code, 0L),
    hl_source = case_when(
      has_dx_code == 1 & has_tr_code == 1 ~ "Both DIAGNOSIS and TR",
      has_dx_code == 1 & has_tr_code == 0 ~ "DIAGNOSIS only",
      has_dx_code == 0 & has_tr_code == 1 ~ "TR only",
      TRUE ~ "Neither (data quality issue)"
    )
  )

# Site-stratified breakdown
venn_breakdown <- all_patients %>%
  tabyl(SOURCE, hl_source) %>%
  adorn_totals(c("row", "col"))

message("\nHL Identification Venn Breakdown by Site:")
print(venn_breakdown)

# Write detailed breakdown
write_csv(all_patients %>% count(SOURCE, hl_source),
          here("output", "diagnostics", "hl_identification_venn.csv"))

# Flag data quality issues
neither_count <- sum(all_patients$hl_source == "Neither (data quality issue)")
if (neither_count > 0) {
  message(glue("\n  WARNING: {neither_count} patients with NO HL evidence in DIAGNOSIS or TUMOR_REGISTRY"))
  message("  This is unexpected for a pre-filtered HL cohort extract")
}

message("\n", strrep("=", 60))
message("Diagnostics complete. Results in output/diagnostics/")
message(strrep("=", 60))
```

### Example 2: Expanding has_hodgkin_diagnosis() to Check TUMOR_REGISTRY
```r
# Source: Pattern adapted from existing has_hodgkin_diagnosis() in 03_cohort_predicates.R
# Updated version checking both DIAGNOSIS and TUMOR_REGISTRY

#' Filter to patients with Hodgkin Lymphoma diagnosis (DIAGNOSIS or TUMOR_REGISTRY)
#'
#' Returns only patients who have at least one HL diagnosis code in DIAGNOSIS
#' (ICD-9 201.xx or ICD-10 C81.xx) OR at least one HL histology code in
#' TUMOR_REGISTRY tables (ICD-O-3 9650-9667).
#'
#' @param patient_df Tibble with at least an ID column
#' @return Filtered tibble containing only patients with HL diagnosis
#'
has_hodgkin_diagnosis <- function(patient_df) {

  # Source 1: DIAGNOSIS table (ICD-9/10)
  dx_hl_patients <- pcornet$DIAGNOSIS %>%
    filter(is_hl_diagnosis(DX, DX_TYPE)) %>%
    distinct(ID)

  # Source 2: TUMOR_REGISTRY1 (verbose column names)
  tr1_hl_patients <- if ("HISTOLOGICAL_TYPE" %in% names(pcornet$TUMOR_REGISTRY1)) {
    pcornet$TUMOR_REGISTRY1 %>%
      filter(is_hl_histology(HISTOLOGICAL_TYPE)) %>%
      distinct(ID)
  } else {
    data.frame(ID = character())
  }

  # Source 3: TUMOR_REGISTRY2 (compact column names)
  tr2_hl_patients <- if ("MORPH" %in% names(pcornet$TUMOR_REGISTRY2)) {
    pcornet$TUMOR_REGISTRY2 %>%
      filter(is_hl_histology(MORPH)) %>%
      distinct(ID)
  } else {
    data.frame(ID = character())
  }

  # Source 4: TUMOR_REGISTRY3 (compact column names)
  tr3_hl_patients <- if ("MORPH" %in% names(pcornet$TUMOR_REGISTRY3)) {
    pcornet$TUMOR_REGISTRY3 %>%
      filter(is_hl_histology(MORPH)) %>%
      distinct(ID)
  } else {
    data.frame(ID = character())
  }

  # Union of all sources
  hl_patients <- bind_rows(dx_hl_patients, tr1_hl_patients, tr2_hl_patients, tr3_hl_patients) %>%
    distinct(ID)

  message(glue("[Predicate] has_hodgkin_diagnosis: {nrow(hl_patients)} patients with HL evidence"))
  message(glue("  DIAGNOSIS table: {nrow(dx_hl_patients)} patients"))
  message(glue("  TUMOR_REGISTRY: {nrow(bind_rows(tr1_hl_patients, tr2_hl_patients, tr3_hl_patients) %>% distinct(ID))} patients"))

  patient_df %>%
    semi_join(hl_patients, by = "ID")
}
```

### Example 3: Adding ICD-O-3 Histology Codes to 00_config.R
```r
# Source: ICD-O-3 SEER Code Lists (https://seer.cancer.gov/seertools/hemelymph/code_list/)
# Add to ICD_CODES list in 00_config.R after hl_icd9 definition

ICD_CODES <- list(
  # ... existing hl_icd10 and hl_icd9 ...

  # ICD-O-3 Histology codes for Hodgkin Lymphoma (morphology codes 9650-9667)
  # Used for TUMOR_REGISTRY table matching
  #
  # Code structure: 4-digit histology code (behavior code /3 stored separately in BEHAV column)
  # Reference: SEER ICD-O-3 Hematopoietic and Lymphoid code lists
  #
  # 9650: Hodgkin lymphoma, NOS
  # 9651: Hodgkin lymphoma, lymphocyte-rich
  # 9652: Hodgkin lymphoma, mixed cellularity, NOS
  # 9653: Hodgkin lymphoma, lymphocytic depletion, NOS
  # 9654: Hodgkin lymphoma, lymphocytic depletion, diffuse fibrosis
  # 9655: Hodgkin lymphoma, lymphocytic depletion, reticular
  # 9659: Nodular lymphocyte predominant Hodgkin lymphoma
  # 9661: Hodgkin granuloma (obsolete)
  # 9662: Hodgkin sarcoma (obsolete)
  # 9663: Hodgkin lymphoma, nodular sclerosis, NOS
  # 9664: Hodgkin lymphoma, nodular sclerosis, cellular phase
  # 9665: Hodgkin lymphoma, nodular sclerosis, grade 1
  # 9667: Hodgkin lymphoma, nodular sclerosis, grade 2
  hl_histology = c(
    "9650", "9651", "9652", "9653", "9654", "9655", "9659",
    "9661", "9662", "9663", "9664", "9665", "9667"
  )
)
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual missing value counts with is.na() | dlookr::diagnose() for automated data quality | dlookr 0.6.0 (2023) added diagnose_paged_report() | Single function call replaces 20+ lines of manual summarization |
| lubridate::dmy(), mdy(), ymd() with tryCatch() chains | lubridate::parse_date_time(orders = c("dmy", "mdy", "ymd")) | lubridate 1.7.0 (2017) stabilized orders parameter | Try multiple formats in one call instead of nested tryCatch() |
| Base R table() for cross-tabs | janitor::tabyl() with adorn_* functions | janitor 1.0.0 (2017) introduced tabyl ecosystem | Returns pipeable data.frame, supports totals and percentages, 3-way tables |
| Identify HL patients via DIAGNOSIS table only | Check BOTH DIAGNOSIS (ICD-9/10) and TUMOR_REGISTRY (ICD-O-3 histology) | PCORnet CDM v6.0 (2021) added tumor registry tables | Captures patients with registry-only HL evidence (estimated 5-10% missed previously) |

**Deprecated/outdated:**
- **readr::type_convert() for post-load type fixing:** Deprecated in readr 2.0 (2021). Use explicit col_types in read_csv() instead.
- **Manual date format detection with str_detect() + if-else chains:** Replaced by lubridate::parse_date_time() with orders parameter.
- **ICD-O-2 histology codes (9590-9596 for HL):** ICD-O-3 (2000) updated HL codes to 9650-9667. PCORnet uses ICD-O-3 exclusively.

## Open Questions

1. **What is the actual format of histology codes in TUMOR_REGISTRY MORPH column?**
   - What we know: csv_columns.txt shows MORPH exists in TR2/TR3 (column 17), HISTOLOGICAL_TYPE exists in TR1 (column 3)
   - What's unclear: Whether codes are stored as "9650", "9650/3" (with behavior suffix), or numeric 9650. Behavior code may be separate column (BEHAV in TR2/TR3).
   - Recommendation: 07_diagnostics.R should sample and print first 10 unique values from each histology column to determine format before implementing is_hl_histology(). If format is "9650/3", use str_extract(MORPH, "^\\\\d{4}") to extract histology before matching.

2. **Are there additional date columns missed by the current regex?**
   - What we know: Current regex `(?i)(DATE|^DT_|^BDATE$|^DOD$|^DT_FU$|DXDATE)` catches most columns
   - What's unclear: csv_columns.txt may have columns like ONSET_DATE, REPORT_DATE (from CONDITION table), RECUR_DT (from TUMOR_REGISTRY2/3) that may be missed
   - Recommendation: 07_diagnostics.R should compare regex-detected columns against csv_columns.txt to find gaps. Add to regex if patterns found.

3. **What is the expected dual-eligible rate in this cohort for payer audit validation?**
   - What we know: Python pipeline has reference counts, 02_harmonize_payer.R already compares against 10-20% expected range
   - What's unclear: Is 10-20% the correct range for an HL cohort specifically? Different from general oncology population?
   - Recommendation: 07_diagnostics.R should document actual dual-eligible rate and flag if outside range. Compare R pipeline output against Python pipeline PAYER_VARIABLES_AND_CATEGORIES.md reference.

4. **Should numeric range checks flag or correct outliers?**
   - What we know: D-18 calls for flagging "obviously wrong values" (negative ages, dates before 1900, tumor sizes >999mm)
   - What's unclear: Should 07_diagnostics.R just report these, or should fixes be applied (e.g., set AGE_AT_DIAGNOSIS < 0 to NA)?
   - Recommendation: Report only in v1. Correction requires clinical input on plausible ranges. Flag counts and sample values, let user decide.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Manual validation (no automated tests) |
| Config file | None — exploratory R pipeline, not production software |
| Quick run command | `Rscript R/07_diagnostics.R` |
| Full suite command | `Rscript R/04_build_cohort.R` (rebuilds cohort after fixes) |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| N/A | Date parsing fixes reduce NA rate | manual | Inspect date_parsing_failures.csv before/after | ❌ Wave 0 |
| N/A | HL identification expands to TR | manual | Compare Venn breakdown before/after | ❌ Wave 0 |
| N/A | Payer mapping audit matches Python counts | manual | Compare payer_mapping_audit.csv | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** Run `Rscript R/07_diagnostics.R` to verify diagnostic output structure
- **Per wave merge:** Re-run full pipeline (01_load → 04_build) to verify cohort rebuild
- **Phase gate:** Manual review of all CSV outputs in output/diagnostics/ before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] No automated tests — validation is manual inspection of diagnostic CSVs
- [ ] No test framework installation needed (exploration pipeline, not production software)

## Sources

### Primary (HIGH confidence)
- [SEER ICD-O-3 Code Lists](https://seer.cancer.gov/seertools/hemelymph/code_list/) - ICD-O-3 histology codes 9650-9667 for Hodgkin Lymphoma
- [PCORnet CDM v7.0 Specification](https://pcornet.org/wp-content/uploads/2025/01/PCORnet-Common-Data-Model-v70-2025_01_23.pdf) - Official PCORnet Common Data Model specification (2025-01-23)
- [dlookr CRAN vignette: Data quality diagnosis](https://cran.r-project.org/web/packages/dlookr/vignettes/diagonosis.html) - diagnose() function documentation
- [readr problems() documentation](https://readr.tidyverse.org/reference/problems.html) - Parse problem tracking
- [janitor tabyl vignette](https://cran.r-project.org/web/packages/janitor/vignettes/tabyls.html) - Cross-tabulation with adorn_* functions
- [lubridate parse_date_time() documentation](https://lubridate.tidyverse.org/reference/parse_date_time.html) - Multi-format date parsing with orders parameter

### Secondary (MEDIUM confidence)
- [NAACCR ICD-O-3 Guidelines](https://www.naaccr.org/wp-content/uploads/2016/11/ICDO3Final-Implementation-Guide.pdf) - ICD-O-3 implementation (verified against SEER)
- [GitHub: kumc-bmi/naaccr-tumor-data](https://github.com/kumc-bmi/naaccr-tumor-data/blob/master/pcornet_cdm/fields.csv) - NAACCR to PCORnet CDM field mappings (referenced for column name crosswalk)

### Tertiary (LOW confidence)
- None — all claims verified against official CRAN documentation or SEER/NAACCR standards

## Metadata

**Confidence breakdown:**
- ICD-O-3 histology codes: HIGH - Verified against SEER official code lists (2026-03-25)
- TUMOR_REGISTRY column names: HIGH - Extracted from csv_columns.txt (actual data)
- dlookr package usage: HIGH - Official CRAN vignette with examples
- Date parsing patterns: MEDIUM - lubridate documentation current, but actual date formats in data unknown until diagnostic audit
- Payer audit validation: MEDIUM - Python reference counts exist, but HL-specific dual-eligible rate unknown

**Research date:** 2026-03-25
**Valid until:** 2026-04-25 (30 days; R package ecosystem stable, ICD-O-3 codes unchanged since 2000)
