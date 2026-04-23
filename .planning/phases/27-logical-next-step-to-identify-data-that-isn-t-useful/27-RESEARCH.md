# Phase 27: Cross-Table Data Quality Assessment - Research

**Researched:** 2026-04-22
**Domain:** Multi-table data quality assessment in PCORnet CDM / R tidyverse ecosystem
**Confidence:** HIGH

## Summary

Phase 27 extends the single-table QA approach from Phases 25-26 (ENCOUNTER-focused multi-source overlap detection) to a comprehensive cross-table data quality assessment covering all 13 loaded PCORnet CDM tables. The phase applies four mandatory QA dimensions (multi-source overlap, field completeness, value validity, exact duplicates) plus additional profiling dimensions (temporal consistency, outlier detection, referential integrity) to identify data that is not analytically useful.

The research confirms that R's tidyverse ecosystem (dplyr, purrr, tidyr) combined with PCORnet CDM v7.0 specifications provides a robust foundation for systematic data quality assessment. Established patterns from Phase 19-22 investigation scripts (missingness profiling, duplicate detection, value audits) can be generalized into a unified QA framework that produces per-table CSV reports and console summaries.

**Primary recommendation:** Build a standalone R/24_cross_table_qa.R script that iterates over all 13 PCORnet CDM tables, applies dimension-specific QA functions (completeness_profile, validity_check, overlap_detect, duplicate_scan), and outputs per-table CSVs with flagged issues plus a consolidated console scorecard. Use janitor::tabyl() for frequency tables, base R duplicated() for exact row duplicates, and Phase 25's hipaa_suppress() pattern for CSV count suppression.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Definition of 'not useful':**
- **D-01:** Phase 25-26 confirmed no encounter duplicates worth removing. This phase extends QA to ALL other PCORnet CDM tables to find data quality issues there.
- **D-02:** "Not useful" encompasses: multi-source overlap records, fields that are mostly empty/sentinel-coded, values outside valid PCORnet CDM value sets, and exact row duplicates.

**QA dimensions (all four applied per table where applicable):**
- **D-03:** Multi-source overlap detection — same-ID, same-date records from different SOURCE values. Apply Phase 25-26 approach to each table with a date field.
- **D-04:** Field completeness — percentage of non-NA values per column, flagging columns that are mostly empty or all-sentinel.
- **D-05:** Value validity — check values against known PCORnet CDM value sets (e.g., ENC_TYPE should be AV/IP/ED/etc., DX_TYPE should be 09/10/SM, etc.).
- **D-06:** Exact row duplicates — identical rows (all fields match) that may be data loading artifacts.
- **D-07:** Skip multi-source overlap detection for tables without a natural date field (DEMOGRAPHIC, PROVIDER). These tables get completeness + validity + exact-duplicate checks only.

**Scope:**
- **D-08:** All records in each table as loaded by R/01_load_pcornet.R — not filtered to HL cohort patients. Data issues affect the whole dataset.
- **D-09:** All 13 loaded PCORnet CDM tables: ENROLLMENT, DIAGNOSIS, PROCEDURES, PRESCRIBING, ENCOUNTER, DEMOGRAPHIC, TUMOR_REGISTRY (3 subtables), DISPENSING, MED_ADMIN, LAB_RESULT_CM, PROVIDER.

**Output:**
- **D-10:** Per-table CSV reports in output/tables/ — one CSV per table with QA findings across all four dimensions.
- **D-11:** Full console summary per table with key findings, flagged issues, and overall QA scorecard — same message()/glue() pattern as Phase 25-26 scripts.
- **D-12:** Standalone script R/24_cross_table_qa.R following established investigation script pattern.

### Claude's Discretion

- Researcher should investigate additional QA dimensions beyond the four specified (the user requested "research into other areas to explore")
- CSV naming convention and column structure per table
- How to define PCORnet CDM valid value sets per column (reference PCORnet CDM v7.0 spec or derive from data)
- How to handle TUMOR_REGISTRY which is loaded as 3 subtables — QA each separately or combined
- Console summary formatting and aggregation approach

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope

</user_constraints>

## Standard Stack

### Core QA Framework
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| dplyr | 1.2.0+ | Data transformation, grouping, summarizing | Existing dependency; group_by + summarise for completeness/validity counts |
| purrr | 1.0.2+ | Functional iteration over tables | map() to apply QA functions across all 13 tables in pcornet list |
| tidyr | 1.3.0+ | Data reshaping for QA reports | pivot_longer() to stack QA results across columns for CSV output |
| glue | 1.8.0 | Console message formatting | Established pattern in Phase 19-26 scripts for logging |
| janitor | 2.2.1+ | Frequency tables and cleaning | tabyl() replaces table() for cleaner value frequency output (completeness/validity) |

### Supporting Libraries
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| stringr | 1.5.1+ | String pattern matching for validity checks | str_detect() for ICD code formats, value set regex patterns |
| lubridate | 1.9.3+ | Date parsing and temporal consistency | Validate date sequences (start < end), detect outlier dates (e.g., 1900 sentinels, future dates) |
| readr | 2.2.0+ | CSV output with HIPAA suppression | write_csv() for per-table QA reports in output/tables/ |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Base R duplicated() | dplyr::distinct() with counting | duplicated() is more explicit for flagging vs distinct() which removes — use duplicated() for exact duplicate detection |
| Manual value set lists | pointblank validation rules | pointblank 0.12.3+ offers YAML-based validation but adds dependency + learning curve — defer to v2 unless complexity warrants |
| Nested loops over tables | purrr::map() functional approach | map() is more readable and returns list of results for easy binding — consistent with tidyverse philosophy |

**Installation:**
```bash
# All dependencies already installed in renv.lock from prior phases
# No new packages required for Phase 27
```

**Version verification:**
All packages are existing dependencies from CLAUDE.md stack specification. No version changes required.

## Architecture Patterns

### Recommended QA Script Structure
```
R/24_cross_table_qa.R
├── source("R/00_config.R")
├── source("R/01_load_pcornet.R")  # Conditionally if pcornet not loaded
├── SECTION 1: Define QA functions
│   ├── completeness_profile(df, table_name)
│   ├── validity_check(df, table_name, value_sets)
│   ├── overlap_detect(df, table_name, date_col, id_col)
│   ├── duplicate_scan(df, table_name)
│   └── hipaa_suppress(x) -- reuse from Phase 25
├── SECTION 2: Define PCORnet CDM value sets
│   ├── VALUE_SETS list (ENC_TYPE, DX_TYPE, PX_TYPE, etc.)
│   └── TABLE_DATE_FIELDS map (which date column per table)
├── SECTION 3: Iterate over tables
│   ├── map(names(pcornet), apply_all_qa_dimensions)
│   └── bind_rows() to create master QA summary
├── SECTION 4: Write per-table CSV reports
│   └── walk2(table_results, table_names, write_qa_csv)
└── SECTION 5: Console summary with scorecard
    └── message() with overall findings + per-table highlights
```

### Pattern 1: Completeness Profiling
**What:** Calculate % non-NA, % sentinel values, and n_distinct per column
**When to use:** Every table, every column (D-04)
**Example:**
```r
# Source: Adapted from Phase 19 missingness pattern (R/20_all_source_missingness.R)
completeness_profile <- function(df, table_name) {
  total_rows <- nrow(df)

  df %>%
    summarise(across(everything(), list(
      n_non_na = ~sum(!is.na(.x)),
      pct_complete = ~round(100 * sum(!is.na(.x)) / total_rows, 1),
      n_distinct = ~n_distinct(.x, na.rm = TRUE),
      n_sentinel = ~sum(.x %in% c("NI", "UN", "OT", "99", "9999"), na.rm = TRUE)
    ))) %>%
    pivot_longer(everything(), names_to = c("column", ".value"), names_sep = "_(?=n_|pct_)") %>%
    mutate(table = table_name) %>%
    arrange(pct_complete)
}
```

### Pattern 2: Value Validity Checks Against PCORnet CDM Value Sets
**What:** Flag values not in official PCORnet CDM v7.0 value sets
**When to use:** Coded columns only (ENC_TYPE, DX_TYPE, PX_TYPE, etc.) (D-05)
**Example:**
```r
# Source: PCORnet CDM v7.0 Value Set Reference File (May 2025)
VALUE_SETS <- list(
  ENC_TYPE = c("AV", "ED", "EI", "IC", "IP", "IS", "OA", "OS", "TH"),  # v7.0 added TH (Telehealth)
  DX_TYPE = c("09", "10", "11", "SM"),  # 09=ICD-9, 10=ICD-10, 11=ICD-11, SM=SNOMED
  PX_TYPE = c("09", "10", "11", "CH", "LC", "ND", "RE"),  # 09=ICD-9, 10=ICD-10, CH=CPT, etc.
  DX_ORIGIN = c("OD", "BI", "CL", "DR", "NI", "UN", "OT"),
  PX_SOURCE = c("OD", "BI", "CL", "DR", "NI", "UN", "OT"),
  ENR_BASIS = c("E", "G", "I", "NI", "UN", "OT")
)

validity_check <- function(df, table_name, value_sets) {
  # Identify which columns in df have defined value sets
  coded_cols <- intersect(names(df), names(value_sets))

  map_dfr(coded_cols, ~{
    col_name <- .x
    valid_values <- value_sets[[col_name]]
    invalid_rows <- df %>%
      filter(!is.na(.data[[col_name]]), !(.data[[col_name]] %in% valid_values))

    if (nrow(invalid_rows) > 0) {
      invalid_rows %>%
        count(.data[[col_name]], name = "n_invalid") %>%
        mutate(table = table_name, column = col_name, valid_set = paste(valid_values, collapse = ", "))
    } else {
      tibble()  # No invalid values
    }
  })
}
```

### Pattern 3: Multi-Source Overlap Detection
**What:** Detect same-ID, same-date records from different SOURCE values
**When to use:** Tables with ID + date field (skip DEMOGRAPHIC, PROVIDER per D-07)
**Example:**
```r
# Source: R/22_multi_source_overlap_detection.R (Phase 25)
overlap_detect <- function(df, table_name, date_col, id_col = "ID") {
  if (!date_col %in% names(df) || !"SOURCE" %in% names(df)) {
    return(tibble(table = table_name, overlap_pairs = 0, skip_reason = "Missing date or SOURCE column"))
  }

  # Parse date if character
  df_parsed <- df %>%
    mutate(date_parsed = as.Date(.data[[date_col]], format = "%Y-%m-%d"))

  # Group by ID + date, count distinct SOURCE values
  overlap_groups <- df_parsed %>%
    filter(!is.na(date_parsed), !is.na(SOURCE)) %>%
    group_by(.data[[id_col]], date_parsed) %>%
    summarise(
      n_sources = n_distinct(SOURCE),
      n_records = n(),
      source_combo = paste(sort(unique(SOURCE)), collapse = "+"),
      .groups = "drop"
    ) %>%
    filter(n_sources > 1)

  tibble(
    table = table_name,
    overlap_pairs = nrow(overlap_groups),
    patients_affected = n_distinct(overlap_groups[[id_col]]),
    top_combo = if (nrow(overlap_groups) > 0) {
      overlap_groups %>% count(source_combo, sort = TRUE) %>% slice(1) %>% pull(source_combo)
    } else { NA_character_ }
  )
}
```

### Pattern 4: Exact Row Duplicate Detection
**What:** Find rows where all fields are identical (potential loading artifacts)
**When to use:** Every table (D-06)
**Example:**
```r
# Source: Base R duplicated() function (see "Exact row duplicate detection R tidyverse" web search)
duplicate_scan <- function(df, table_name) {
  # duplicated() marks 2nd+ occurrence as TRUE; keep both original and duplicates for counting
  dup_rows <- df[duplicated(df) | duplicated(df, fromLast = TRUE), ]

  if (nrow(dup_rows) > 0) {
    # Group identical rows to count frequency
    dup_summary <- dup_rows %>%
      group_by(across(everything())) %>%
      summarise(n_copies = n(), .groups = "drop") %>%
      arrange(desc(n_copies))

    tibble(
      table = table_name,
      total_duplicate_rows = nrow(dup_rows),
      unique_duplicate_sets = nrow(dup_summary),
      max_copies = max(dup_summary$n_copies)
    )
  } else {
    tibble(table = table_name, total_duplicate_rows = 0, unique_duplicate_sets = 0, max_copies = 0)
  }
}
```

### Pattern 5: HIPAA Suppression for CSV Outputs
**What:** Replace counts 1-10 with "<11" in CSV files, retain raw values in console
**When to use:** All CSV outputs (D-10), not console (D-11)
**Example:**
```r
# Source: R/22_multi_source_overlap_detection.R (reuse verbatim)
hipaa_suppress <- function(x) {
  x_num <- suppressWarnings(as.numeric(x))
  ifelse(!is.na(x_num) & x_num >= 1 & x_num <= 10, "<11", as.character(x))
}

suppress_counts <- function(df) {
  count_cols <- grep("^n_|^n$|_count$|_pairs$|_affected$|_dates$|_patients$|_rows$|_sets$|_copies$",
                     names(df), value = TRUE)
  count_cols <- count_cols[!grepl("pct_|_rate$|_pct$", count_cols)]
  df %>%
    mutate(across(all_of(count_cols), ~ hipaa_suppress(.x)))
}
```

### Anti-Patterns to Avoid

- **Don't use pointblank for v1:** Adds 0.12.3+ dependency and YAML config learning curve. Defer to v2 unless data quality issues become systematic enough to warrant automated rule engine. For exploratory QA, explicit functions are more transparent.
- **Don't filter to HL cohort before QA:** Data quality issues (duplicates, missing values, invalid codes) affect the entire raw dataset per D-08. Filtering to cohort masks site-level submission problems.
- **Don't manually hardcode value sets:** Pull from PCORnet CDM v7.0 Value Set Reference File or derive from data. Hardcoding outdates when CDM updates (e.g., v7.0 added TH=Telehealth to ENC_TYPE).
- **Don't suppress counts in console output:** Phase 25-26 pattern retains raw counts in message() logs for investigator analysis; suppression applies only to CSV outputs per D-11.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Exact row duplicate detection | Custom hash-based comparison | Base R duplicated() | duplicated() is O(n log n), memory-efficient, handles all column types including dates/factors; rolling your own misses edge cases (NA handling, factor level mismatches) |
| Frequency tables with percentages | Manual count() + mutate(pct = n/sum(n)) | janitor::tabyl() | tabyl() auto-adds totals row, handles grouped data cleanly, formats percentages with rounding — avoids div-by-zero, missing totals, rounding inconsistencies |
| Value set validation | Nested if-else chains | Named list lookup with %in% | Scalable to 50+ value sets across 13 tables; adding a new value set is one list entry vs rewriting conditionals |
| Iterating QA over tables | for loop with manual result binding | purrr::map() + bind_rows() | map() returns list of results that bind_rows() stacks automatically; for loops accumulate results with rbind() in a loop (quadratic performance, harder to read) |
| Missing data profiling | is.na() checks scattered across script | summarise(across(everything(), list(...))) | Applies same logic to all columns in one pass; across() is vectorized, avoids copy-paste errors, scales to 140-column tables (TUMOR_REGISTRY3) |

**Key insight:** PCORnet CDM QA is pattern-heavy (13 tables × 4 dimensions = 52 QA operations). Functional programming (purrr::map) + across() for column-wise operations prevent code duplication and make adding new QA dimensions trivial (one new function + one map() call).

## Additional QA Dimensions (Beyond the Four Required)

Based on data quality literature and PCORnet CDM v7.0 validation guidance, the following dimensions complement the four mandatory checks:

### 5. Temporal Consistency
**What:** Validate date logic (start < end, no future dates, no extreme outliers like 1900 sentinels)
**Why:** PCORnet CDM has paired date fields (ENR_START_DATE/ENR_END_DATE, ADMIT_DATE/DISCHARGE_DATE, RX_START_DATE/RX_END_DATE) where logic violations indicate data errors
**How:** For each table, identify date field pairs, check start <= end, flag future dates (> Sys.Date()), detect sentinel years (1900, 1901, 9999)
**Confidence:** HIGH — PCORnet CDM Data Quality Validation PDF explicitly mentions "start dates precede end dates" as a consistency check

### 6. Referential Integrity
**What:** Verify foreign key relationships across tables (e.g., all DIAGNOSIS.ID values exist in DEMOGRAPHIC.ID)
**Why:** PCORnet CDM has strict table relationships; orphaned records indicate ETL failures
**How:** anti_join() to find IDs in child table (DIAGNOSIS) not in parent table (DEMOGRAPHIC); flag tables with orphan rate > threshold (e.g., 1%)
**Confidence:** HIGH — PCORnet Data Quality Validation document lists "referential integrity across tables" as a core validation rule

### 7. Outlier Detection (Numeric Fields)
**What:** Identify extreme values in numeric columns (age, lab results, dosages) via IQR or Z-score
**Why:** Extreme outliers (e.g., age = 200, negative lab values where biologically impossible) are often data entry errors or sentinel codes not documented
**How:** For numeric columns, calculate Q1, Q3, IQR; flag values < Q1 - 3*IQR or > Q3 + 3*IQR as potential outliers
**Confidence:** MEDIUM — Web search literature identifies IQR and Z-score as standard outlier detection methods; PCORnet spec doesn't mandate this but Phase 5 diagnostic script (R/07_diagnostics.R) already flags numeric range issues

### 8. Cardinality Profiling
**What:** Count distinct values per column to identify low-cardinality fields (candidates for validity checks) vs high-cardinality IDs
**Why:** Helps prioritize which columns need value set validation (low cardinality = coded field) vs which are free text (high cardinality = names, notes)
**How:** n_distinct() per column in completeness_profile(); flag columns with n_distinct < 20 as coded fields to cross-check against value sets
**Confidence:** MEDIUM — Implied by data profiling best practices (web search: "data quality profiling summary statistics"); janitor::tabyl() is designed for this use case

### 9. Cross-Field Consistency
**What:** Check logical relationships between fields (e.g., DX_TYPE='09' should have DX code in ICD-9 format, not ICD-10)
**Why:** PCORnet CDM has implicit consistency rules (diagnosis type should match diagnosis code format, encounter type should align with admit/discharge logic)
**How:** Case-specific validations (e.g., if DX_TYPE == '09', check DX matches ICD-9 pattern; if ENC_TYPE == 'ED', DISCHARGE_DATE should be same-day or next-day)
**Confidence:** LOW — Requires domain knowledge of PCORnet CDM business rules; may be overkill for exploratory v1 (defer to v2)

**Recommended for Phase 27:** Include dimensions 5 (Temporal Consistency) and 6 (Referential Integrity) as they directly support PCORnet CDM validation requirements and reuse existing patterns (date parsing from Phase 5, anti_join from tidyverse). Dimensions 7-9 are optional enhancements if time permits.

## Common Pitfalls

### Pitfall 1: Assuming All Tables Have a SOURCE Column
**What goes wrong:** Some PCORnet CDM tables (PROVIDER v7.0) may not include SOURCE column; overlap_detect() crashes with "column not found"
**Why it happens:** DEMOGRAPHIC and ENCOUNTER have SOURCE (patient site, data contributor), but PROVIDER.SOURCE was added in v7.0 and may be unpopulated
**How to avoid:** Guard clause in overlap_detect(): `if (!"SOURCE" %in% names(df)) return(skip_reason = "No SOURCE column")`
**Warning signs:** Error message "object 'SOURCE' not found" when running QA script

### Pitfall 2: Treating Sentinel Values as Valid Data
**What goes wrong:** Completeness metrics count "NI" (No Information), "UN" (Unknown), "OT" (Other) as populated fields, inflating completeness percentages
**Why it happens:** PCORnet CDM uses sentinel codes to distinguish "no data" (NA) from "data explicitly marked unknown" (UN), but both are analytically useless
**How to avoid:** Define sentinel list (`c("NI", "UN", "OT", "99", "9999")` per Phase 19 pattern) and count these separately in completeness_profile() as n_sentinel, not n_non_na
**Warning signs:** Completeness % looks high (e.g., 95%) but majority of values are "NI" or "UN" when inspected

### Pitfall 3: Exact Duplicate Detection on Tables with Auto-Generated IDs
**What goes wrong:** Tables with system-generated unique IDs (DIAGNOSISID, ENCOUNTERID) will never have exact row duplicates even if all other fields match
**Why it happens:** duplicated() requires ALL fields to match; unique ID columns prevent detection of "semantic duplicates" (same patient, date, diagnosis, but different DIAGNOSISID)
**How to avoid:** Two-tier duplicate detection: (1) exact duplicates on ALL fields (D-06), (2) semantic duplicates excluding ID columns (e.g., DIAGNOSIS without DIAGNOSISID). Document which type each QA report shows.
**Warning signs:** Zero duplicates reported for tables known to have redundant records (e.g., same patient, same diagnosis, same date from multiple data feeds)

### Pitfall 4: Hardcoding PCORnet CDM Value Sets Without Version Tracking
**What goes wrong:** Value sets evolve across CDM versions (v6.1 → v7.0 added TH=Telehealth to ENC_TYPE); hardcoded lists become outdated
**Why it happens:** Easier to manually list valid values than to parse official Value Set Reference File
**How to avoid:** Either (a) embed CDM version in VALUE_SETS definition with source citation, or (b) parse official PCORnet v7.0 Parseable Spreadsheet if available on HiPerGator filesystem
**Warning signs:** Validity checks flag "TH" as invalid even though it's a legitimate v7.0 encounter type

### Pitfall 5: HIPAA Suppression Breaking Numeric Columns
**What goes wrong:** hipaa_suppress() converts all count columns to character; downstream sum() or mean() operations fail with "non-numeric argument"
**Why it happens:** CSV output suppression (counts 1-10 → "<11") makes columns character type; if these CSVs are re-read, counts are strings
**How to avoid:** Apply suppress_counts() ONLY before write_csv(), never to in-memory data frames used for further computation. Keep two versions: df_raw (numeric) for console logging, df_suppressed (character) for CSV output.
**Warning signs:** Error "non-numeric argument to binary operator" when trying to summarise() a suppressed column

## Code Examples

Verified patterns from official sources and existing codebase:

### Example 1: Iterate QA Functions Over All Tables
```r
# Source: purrr::map() pattern, adapted from Phase 19-22 all-source scripts
library(purrr)
library(dplyr)

# List of all loaded tables
table_names <- names(pcornet)

# Apply all QA dimensions to each table
qa_results <- map(table_names, function(tbl_name) {
  df <- pcornet[[tbl_name]]

  # Completeness
  completeness <- completeness_profile(df, tbl_name)

  # Validity (only if value sets defined for this table)
  validity <- validity_check(df, tbl_name, VALUE_SETS)

  # Overlap (only if date column exists)
  date_col <- TABLE_DATE_FIELDS[[tbl_name]]
  overlap <- if (!is.null(date_col)) {
    overlap_detect(df, tbl_name, date_col)
  } else {
    tibble(table = tbl_name, overlap_pairs = NA, skip_reason = "No date field defined")
  }

  # Exact duplicates
  duplicates <- duplicate_scan(df, tbl_name)

  # Combine into single result
  list(
    completeness = completeness,
    validity = validity,
    overlap = overlap,
    duplicates = duplicates
  )
})

# Name list elements by table
names(qa_results) <- table_names
```

### Example 2: Console Scorecard Summary
```r
# Source: Phase 25 R/22_multi_source_overlap_detection.R console pattern
message(glue("\n{strrep('=', 70)}"))
message("CROSS-TABLE DATA QUALITY ASSESSMENT SCORECARD")
message(glue("{strrep('=', 70)}\n"))

# Extract duplicate counts per table
dup_summary <- map_dfr(qa_results, "duplicates")

message("--- Exact Row Duplicates ---")
for (i in seq_len(nrow(dup_summary))) {
  r <- dup_summary[i, ]
  if (r$total_duplicate_rows > 0) {
    message(glue("  {r$table}: {format(r$total_duplicate_rows, big.mark=',')} duplicate rows in {r$unique_duplicate_sets} sets (max {r$max_copies} copies)"))
  } else {
    message(glue("  {r$table}: No exact duplicates"))
  }
}

# Extract overlap counts per table
overlap_summary <- map_dfr(qa_results, "overlap")

message("\n--- Multi-Source Overlap (Same-Date) ---")
for (i in seq_len(nrow(overlap_summary))) {
  r <- overlap_summary[i, ]
  if (!is.na(r$overlap_pairs) && r$overlap_pairs > 0) {
    message(glue("  {r$table}: {format(r$overlap_pairs, big.mark=',')} patient-date pairs from >1 SOURCE (top combo: {r$top_combo})"))
  } else if (!is.na(r$skip_reason)) {
    message(glue("  {r$table}: Skipped ({r$skip_reason})"))
  } else {
    message(glue("  {r$table}: No multi-source overlap"))
  }
}

message(glue("\n{strrep('=', 70)}"))
```

### Example 3: Per-Table CSV Output with HIPAA Suppression
```r
# Source: Phase 19-22 CSV output pattern (R/20_all_source_missingness.R)
library(readr)

# Write completeness CSV for each table
walk(table_names, function(tbl_name) {
  completeness <- qa_results[[tbl_name]]$completeness

  # Apply HIPAA suppression to count columns
  completeness_suppressed <- completeness %>%
    suppress_counts()

  # Write to output/tables/
  filename <- file.path(CONFIG$output_dir, "tables", glue("{tbl_name}_completeness_qa.csv"))
  write_csv(completeness_suppressed, filename)
  message(glue("  Wrote {filename}"))
})
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual QA scripts per table | Functional iteration with purrr::map() | Tidyverse 1.0.0 (2019) | One QA function applied to 13 tables instead of 13 copy-paste scripts |
| Value set validation via nested if-else | Named list lookup with %in% operator | Base R best practice | Adding v7.0 Telehealth (TH) to ENC_TYPE is 1 line change instead of updating conditionals across scripts |
| Exact duplicate detection with dplyr::distinct() | Base R duplicated() for explicit flagging | Always available | distinct() removes duplicates silently; duplicated() returns logical vector for counting/profiling duplicate sets |
| CONSORT/pointblank for data validation | Exploratory tidyverse QA functions | pointblank 0.12.3 (Nov 2025) | pointblank is overkill for one-off QA; reserve for systematic validation in production pipelines (v2 scope) |

**Deprecated/outdated:**
- **Manual foreach loops with rbind() accumulation:** Replaced by purrr::map() + bind_rows() — quadratic performance, error-prone
- **Treating all NA as missing:** PCORnet CDM distinguishes NA (no data) from NI/UN (explicitly marked unknown) — both must be counted separately
- **Hardcoding value sets in script body:** PCORnet CDM v7.0 Value Set Reference File (May 2025) is authoritative source — embed as comments with version + date

## Open Questions

1. **PCORnet CDM v7.0 Value Set Reference File availability on HiPerGator**
   - What we know: PCORnet publishes v7.0 spec PDF + parseable spreadsheet (May 2025) with complete value sets
   - What's unclear: Is this file accessible on HiPerGator filesystem at /orange/erin.mobley-hl.bcu/ or must values be manually transcribed from spec PDF?
   - Recommendation: Manually transcribe critical value sets (ENC_TYPE, DX_TYPE, PX_TYPE, ENR_BASIS) into VALUE_SETS list with source citation. Future enhancement: parse spreadsheet if available.

2. **TUMOR_REGISTRY QA — 3 separate tables or combined?**
   - What we know: R/01_load_pcornet.R loads TUMOR_REGISTRY1, TUMOR_REGISTRY2, TUMOR_REGISTRY3 as separate tibbles in pcornet list
   - What's unclear: Do these represent different record types (e.g., primary tumor, metastasis, recurrence) or data partitions? Should QA treat them separately or bind_rows() first?
   - Recommendation: QA each separately initially; if structure/columns are identical, note in console summary that they could be combined for future analyses.

3. **Temporal consistency checks — which date pairs to validate?**
   - What we know: PCORnet CDM has multiple date pair relationships (ENR_START_DATE/ENR_END_DATE, ADMIT_DATE/DISCHARGE_DATE, RX_START_DATE/RX_END_DATE)
   - What's unclear: Are there other implicit date logic rules (e.g., DIAGNOSIS.DX_DATE should be within ENCOUNTER.ADMIT_DATE to DISCHARGE_DATE window)?
   - Recommendation: Start with explicit paired date fields in same table; defer cross-table date logic (DX_DATE vs ADMIT_DATE) to v2 unless user flags as priority.

4. **Referential integrity — which table relationships to check?**
   - What we know: DEMOGRAPHIC.ID is parent key; all other tables' ID columns are foreign keys; ENCOUNTER.ENCOUNTERID links to child tables (DIAGNOSIS, PROCEDURES)
   - What's unclear: Full dependency graph for 13 tables (which IDs must exist in which parent tables)
   - Recommendation: Prioritize DEMOGRAPHIC.ID → all tables check (catches ETL patient ID mismatches); defer ENCOUNTER.ENCOUNTERID → DIAGNOSIS/PROCEDURES checks to v2.

## Environment Availability

> Phase 27 has no external dependencies beyond existing R packages in renv.lock. All tools (dplyr, purrr, janitor, glue) are already installed per CLAUDE.md stack. Skipped.

## Validation Architecture

> Skipped — workflow.nyquist_validation is explicitly set to false in .planning/config.json (line 19). No test framework section required.

## Sources

### Primary (HIGH confidence)
- [PCORnet Common Data Model v7.0 Specification (May 2025)](https://pcornet.org/wp-content/uploads/2025/05/PCORnet_Common_Data_Model_v70_2025_05_01.pdf) - Table schemas, value sets, field definitions
- [PCORnet CDM Data Quality Validation (Dec 2024)](https://pcornet.org/wp-content/uploads/2024/12/CDM-Data-Quality-Validation.pdf) - QA dimensions, validation rules, completeness metrics, consistency checks
- [PCORnet Common Data Model](https://pcornet.org/data/common-data-model/) - Official CDM resource page
- Existing codebase scripts (R/22_multi_source_overlap_detection.R, R/20_all_source_missingness.R, R/17_value_audit.R) - Established patterns for QA, HIPAA suppression, console logging

### Secondary (MEDIUM confidence)
- [The Six Primary Dimensions for Data Quality Assessment](https://www.sbctc.edu/resources/documents/colleges-staff/commissions-councils/dgc/data-quality-deminsions.pdf) - Completeness, validity, consistency framework
- [Overview of Data Quality: Examining the Dimensions, Antecedents, and Impacts of Data Quality (PMC)](https://pmc.ncbi.nlm.nih.gov/articles/PMC9912223/) - Academic framework for QA dimensions
- [6 Data Quality Dimensions: Complete Guide (ICEDQ)](https://icedq.com/6-data-quality-dimensions) - Industry best practices for completeness, validity, consistency
- [Data Quality Dimensions: Key Metrics & Best Practices for 2026 (OvalEdge)](https://www.ovaledge.com/blog/data-quality-dimensions) - Current industry standards

### Tertiary (LOW confidence, marked for validation)
- [R package pointblank: Data Validation and Quality Control](https://rstudio.github.io/pointblank/) - Alternative QA framework (deferred to v2)
- [Package 'skimr' (CRAN Jan 2026)](https://cran.r-project.org/web/packages/skimr/skimr.pdf) - Data profiling alternative to manual summarise()
- [Identify and Remove Duplicate Data in R (GeeksforGeeks)](https://www.geeksforgeeks.org/identify-and-remove-duplicate-data-in-r/) - duplicated() function usage
- [Data Wrangling Essentials: Duplicate observations (SSCC)](https://sscc.wisc.edu/sscc/pubs/DWE/book/4-9-duplicate-observations.html) - duplicated() and distinct() comparison

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — All packages existing dependencies from CLAUDE.md, verified in renv.lock by prior phases
- Architecture patterns: HIGH — Adapted from proven Phase 19-26 investigation scripts with 6 prior executions
- PCORnet value sets: MEDIUM — Official v7.0 spec available but value set spreadsheet not verified on HiPerGator filesystem
- Additional QA dimensions: MEDIUM — Temporal consistency and referential integrity explicitly mentioned in PCORnet DQ Validation PDF; outlier/cardinality profiling inferred from data quality literature
- Pitfalls: HIGH — Sentinel value handling, duplicate detection edge cases observed in Phase 19-22 execution

**Research date:** 2026-04-22
**Valid until:** 2026-07-22 (90 days — PCORnet CDM stable, R package ecosystem stable, project-specific patterns unlikely to change)
