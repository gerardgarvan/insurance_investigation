# Phase 58: Cancer Summary Pre/Post HL Counts - Research

**Researched:** 2026-05-26
**Domain:** R data manipulation with temporal date filtering and Excel generation
**Confidence:** HIGH

## Summary

Phase 58 creates a new cancer summary table showing pre/post HL diagnosis counts for each cancer code. The phase builds on established patterns from R/55 (cancer summary with D-code removal + HL cohort confirmation) and R/56 (temporal filtering using first_hl_dx_date). The implementation follows a standalone script pattern producing new outputs without modifying existing files.

The technical challenge is temporal partitioning: for each cancer code, count how many patients had that code before their first HL diagnosis date, after it, or both. This requires joining DIAGNOSIS table rows with confirmed_hl_cohort.rds (which contains first_hl_dx_date per patient), applying temporal filters (DX_DATE <= first_hl_dx_date for pre, DX_DATE > for post), and aggregating counts at both category and code levels.

**Primary recommendation:** Follow R/56's DuckDB query pattern (raw DIAGNOSIS rows joined with confirmed_hl_cohort), apply three temporal filters (pre/post/both) to produce separate patient sets, aggregate counts, and use R/55's xlsx styling pattern with openxlsx2. Exclude C81 rows from output tables since pre/post split is self-referential for the anchor diagnosis.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Implementation Decisions

**Column Structure:**
- D-01: Keep existing count columns from R/55: Total Patients, Confirmed (2+ Dates), Confirmed (7-Day Gap), Total Records
- D-02: Drop all percentage and date-stat columns: Rate (2+ Dates), Rate (7-Day Gap), Mean/Median Unique Dates, Mean/Median Dates (7-Day Sep)
- D-03: Add three new count columns: Pre-HL Count, Post-HL Count, Both Count
- D-04: "Both" = intersection — patient had that cancer code at least once before AND at least once after first_hl_dx_date. Pre and Post are non-exclusive (Pre + Post - Both = unique patients with temporal data)
- D-05: Counts only — no percentages anywhere in the table

**Column Ordering:**
- D-06: Category Summary: Cancer Site Category | Total Patients | Confirmed (2+ Dates) | Confirmed (7-Day Gap) | Pre-HL | Post-HL | Both | Total Records
- D-07: Code Summary: ICD-10 Code | Cancer Site Category | Total Patients | Confirmed (2+ Dates) | Confirmed (7-Day Gap) | Pre-HL | Post-HL | Both | Total Records

**Same-Day Handling:**
- D-08: Same-day = pre-HL. Pre uses DX_DATE <= first_hl_dx_date, Post uses DX_DATE > first_hl_dx_date. Consistent with R/56's strict > convention.

**HL Row Handling:**
- D-09: Exclude C81 (Hodgkin Lymphoma) rows entirely from the pre/post table. C81 is the anchor diagnosis — pre/post split is self-referential for this code. Table focuses on OTHER cancers relative to HL diagnosis.

**Patients with No Dates:**
- D-10: Patients with a cancer code but all NA DX_DATEs are excluded from Pre/Post/Both columns but still appear in Total Patients (carried forward from baseline patient-code summary).

**Sentinel Dates:**
- D-11: DX_DATEs before 1910-01-01 are excluded from pre/post counting, consistent with R/56's sentinel handling.

**Data Sources:**
- D-12: Load confirmed_hl_cohort.rds from R/55 for first_hl_dx_date — do not recompute. The pmin(DIAGNOSIS, TUMOR_REGISTRY) approach is established.
- D-13: Pre/post counting uses DIAGNOSIS table only (via DuckDB). TUMOR_REGISTRY is not queried for cancer codes — consistent with R/55 and R/56 pattern.

**Output Strategy:**
- D-14: New standalone script (R/58_cancer_summary_pre_post.R) producing a new file (cancer_summary_table_pre_post.xlsx). Does not modify R/55 or R/56 outputs.
- D-15: Two-sheet xlsx: Category Summary and Code Summary, matching R/55's two-sheet pattern.

**Styling:**
- D-16: Same styling as R/55: dark gray headers (#374151), white font, totals row with light gray fill (#E5E7EB), comma-formatted counts (#,##0), frozen header row, Calibri font.

### Claude's Discretion
- Whether to also produce a companion CSV file
- Whether to include population denominator note in the xlsx
- PREFIX_MAP handling (copy from R/55 or factor out)

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope

</user_constraints>

## Standard Stack

### Core Libraries
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| dplyr | 1.2.0+ | Data transformation | Established in R/55 and R/56 for filtering, grouping, aggregation; readable pipe syntax |
| stringr | 1.5.1+ | String operations | Used in R/55/R/56 for ICD code normalization (str_detect, str_remove_all) |
| glue | 1.8.0+ | String interpolation | Logging messages in R/55/R/56; readable alternative to paste0 |
| openxlsx2 | 1.9+ | Excel workbook generation | Used in R/55 and R/56 for styled xlsx outputs; modern successor to openxlsx |
| lubridate | 1.9.3+ | Date operations | Used in R/55 for year() function (sentinel date handling) and date arithmetic |

### Supporting Libraries
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| DBI | 1.1.3+ | Database interface | Required for DuckDB connections (via R/01_load_pcornet.R) |
| duckdb | 1.1.3+ | Analytical database engine | Backend for DIAGNOSIS table queries; established in R/56 for large-scale row retrieval |
| tibble | 3.2.1+ | Modern data frames | Tidyverse default; used for building totals rows in R/55 |

**Installation:**
All libraries already installed per project configuration. Sourcing R/00_config.R and R/01_load_pcornet.R provides DuckDB connection management.

**Version verification:** Versions listed match R/55 and R/56 script headers (verified via project codebase inspection). No new packages needed.

## Architecture Patterns

### Recommended Script Structure
```
R/58_cancer_summary_pre_post.R
├── SECTION 1: SETUP
│   ├── Library loading (dplyr, stringr, glue, openxlsx2, lubridate)
│   ├── Source R/00_config.R and R/01_load_pcornet.R
│   └── Define input/output paths
├── SECTION 2: PREFIX_MAP AND classify_codes()
│   └── Copy from R/55 lines 69-338 for script independence
├── SECTION 3: LOAD INPUTS
│   ├── Load confirmed_hl_cohort.rds (ID, first_hl_dx_date, first_hl_dx_source)
│   └── Load cancer_summary.csv (for description lookup)
├── SECTION 4: QUERY DIAGNOSIS FOR RAW DATE ROWS
│   ├── DuckDB query: C-codes for confirmed cohort IDs
│   └── Exclude sentinel dates (< 1910-01-01)
├── SECTION 5: COMPUTE PRE/POST/BOTH SETS
│   ├── Join with confirmed_hl_cohort to get first_hl_dx_date
│   ├── Filter for pre-HL: DX_DATE <= first_hl_dx_date
│   ├── Filter for post-HL: DX_DATE > first_hl_dx_date
│   └── Compute both: patients in pre AND post sets
├── SECTION 6: AGGREGATE BASELINE PATIENT-CODE METRICS
│   ├── Reuse R/55 aggregation logic for Total Patients, Confirmed (2+ Dates), Confirmed (7-Day Gap)
│   └── Query record counts from DIAGNOSIS
├── SECTION 7: MERGE PRE/POST/BOTH COUNTS
│   ├── Left join pre/post/both counts to baseline aggregation
│   └── Exclude C81 rows per D-09
├── SECTION 8: CATEGORY-LEVEL AGGREGATION
│   ├── Group by category, sum all count columns
│   └── Build category totals row
├── SECTION 9: CODE-LEVEL AGGREGATION
│   ├── Group by cancer_code + category, preserve all count columns
│   └── Build code totals row
├── SECTION 10: WRITE OUTPUTS
│   ├── Sheet 1: Category Summary (7 columns per D-06)
│   ├── Sheet 2: Code Summary (8 columns per D-07)
│   └── Apply R/55 styling: headers, totals row, number formats, frozen panes
└── SECTION 11: CLEANUP
    └── close_pcornet_con()
```

### Pattern 1: Temporal Partitioning
**What:** Split patient-code-date rows into pre-HL, post-HL, and both sets based on first_hl_dx_date.
**When to use:** When counting events relative to a per-patient anchor date (here: first HL diagnosis).
**Example:**
```r
# Source: Established pattern from R/56 lines 399-430
# Join with confirmed_hl_cohort to get first_hl_dx_date per row
dx_with_hl_date <- dx_raw %>%
  inner_join(confirmed_hl_cohort %>% select(ID, first_hl_dx_date), by = "ID") %>%
  filter(!is.na(DX_DATE))  # Remove rows with NA DX_DATE

# Pre-HL: same-day included (<=)
dx_pre_hl <- dx_with_hl_date %>%
  filter(DX_DATE <= first_hl_dx_date)

# Post-HL: strict > (same-day excluded)
dx_post_hl <- dx_with_hl_date %>%
  filter(DX_DATE > first_hl_dx_date)

# Both: patients with at least one code pre AND one code post
patients_pre <- dx_pre_hl %>% distinct(ID, DX_norm)
patients_post <- dx_post_hl %>% distinct(ID, DX_norm)

patients_both <- patients_pre %>%
  inner_join(patients_post, by = c("ID", "DX_norm"))
```

### Pattern 2: Baseline Metrics Reuse
**What:** Compute Total Patients, Confirmed (2+ Dates), Confirmed (7-Day Gap) using R/55's existing logic.
**When to use:** When you need the same patient-code aggregation metrics as the baseline cancer summary.
**Example:**
```r
# Source: R/55 lines 548-567 (code-level aggregation)
code_summary_baseline <- cancer_summary %>%
  group_by(cancer_code, category) %>%
  summarise(
    total_patients        = n_distinct(ID),
    confirmed_2date       = n_distinct(ID[two_or_more_unique_dates == 1]),
    confirmed_7day        = n_distinct(ID[two_or_more_unique_dates_gt_7 == 1]),
    total_records         = sum(record_count, na.rm = TRUE),
    .groups = "drop"
  )
```

### Pattern 3: C81 Exclusion
**What:** Remove Hodgkin Lymphoma (C81*) rows from the output table since pre/post split is self-referential.
**When to use:** After all aggregations are complete, before writing to xlsx.
**Example:**
```r
# Exclude C81 rows (anchor diagnosis) from category and code summaries
category_summary <- category_summary %>%
  filter(category != "Hodgkin Lymphoma")

code_summary <- code_summary %>%
  filter(!str_detect(cancer_code, "^C81"))
```

### Pattern 4: Both Count Computation
**What:** "Both" = intersection of patients with the same code pre AND post HL diagnosis.
**When to use:** When you need to identify patients with persistent/recurrent codes across the temporal boundary.
**Example:**
```r
# Count patients with code X both before and after first_hl_dx_date
both_counts <- patients_pre %>%
  inner_join(patients_post, by = c("ID", "DX_norm")) %>%
  group_by(DX_norm) %>%
  summarise(both_count = n_distinct(ID), .groups = "drop")
```

### Anti-Patterns to Avoid

**Don't recompute first_hl_dx_date:** R/55 already computed it using pmin(DIAGNOSIS, TUMOR_REGISTRY). Load confirmed_hl_cohort.rds and use the pre-computed value (D-12).

**Don't query TUMOR_REGISTRY for cancer codes:** R/55 and R/56 established DIAGNOSIS-only pattern for cancer code queries. TUMOR_REGISTRY is used only for first HL diagnosis date computation, which is already done.

**Don't include C81 rows in output:** The pre/post split is meaningless for the anchor diagnosis. Filter out after aggregation but before xlsx writing.

**Don't use percentages:** D-05 specifies counts only. All percentage columns from R/55 are dropped.

**Don't modify existing outputs:** D-14 specifies new standalone script and new file. R/55 and R/56 outputs remain untouched.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Excel styling | Manual XML generation or CSV+manual formatting | openxlsx2 wb_* functions | R/55 and R/56 established pattern with 11 styling operations (headers, fills, fonts, number formats, frozen panes, column widths, totals row). Replicating manually is error-prone and breaks visual consistency. |
| Temporal filtering | Loop over patients and dates in R | DuckDB collect() + dplyr filter() | R/56 established pattern: collect raw rows from DuckDB (vectorized), join with confirmed_hl_cohort, apply vectorized date filters. Looping in R is 100-1000x slower for 100K+ rows. |
| Date handling | String parsing with substr() | lubridate year() and date arithmetic | R/55 uses year(first_hl_dx_date) == 1900L for sentinel detection. lubridate handles date edge cases (leap years, missing dates) that string parsing misses. |
| ICD code normalization | Manual regex or substr() | str_remove_all(DX, "\\\\.") + toupper() | R/55 and R/56 established pattern. PCORnet ICD codes come in dotted (C81.0) and undotted (C810) formats. Consistent normalization required for joins. |
| Both count computation | Nested loops or merge() | dplyr inner_join() on ID + DX_norm | Intersection of patient-code pairs is a standard set operation. inner_join() is vectorized and optimized; merge() is slower; loops are 100x slower. |

**Key insight:** All five problems have established solutions in R/55 and R/56. Deviating from those patterns introduces inconsistency risk and performance regression.

## Common Pitfalls

### Pitfall 1: Misinterpreting "Both" as Exclusive Count
**What goes wrong:** Treating Pre, Post, Both as mutually exclusive categories (assuming Pre + Post + Both = Total Patients).
**Why it happens:** "Both" is an intersection, not a third category. Pre and Post are non-exclusive — a patient can be in both sets if they have the code both before and after first HL diagnosis.
**How to avoid:** Document clearly: `Pre + Post - Both = unique patients with temporal data`. The "Both" count is already included in Pre and Post counts.
**Warning signs:** If Pre + Post + Both sums to more than Total Patients, the calculation is wrong.

### Pitfall 2: Same-Day Ambiguity
**What goes wrong:** Inconsistent handling of DX_DATE == first_hl_dx_date across pre and post filters, leading to same-day diagnoses being double-counted or excluded entirely.
**Why it happens:** Temporal boundaries require explicit <= vs < decisions. R/56 used strict > for post-HL (excluding same-day), but that decision must propagate consistently.
**How to avoid:** D-08 resolves this: Pre uses DX_DATE <= first_hl_dx_date (same-day included), Post uses DX_DATE > first_hl_dx_date (same-day excluded). Filters are mutually exclusive and cover all rows with valid dates.
**Warning signs:** If Pre + Post row counts don't equal total rows with non-NA DX_DATE (excluding sentinel dates), same-day handling is inconsistent.

### Pitfall 3: Sentinel Date Contamination
**What goes wrong:** Pre-1910 sentinel dates (1900-01-01 from data entry errors) appear in pre-HL counts, inflating pre-HL patient numbers artificially.
**Why it happens:** R/55 nullifies sentinel dates in first_hl_dx_date computation (year == 1900L → NA), but raw DIAGNOSIS table still contains 1900-01-01 rows. If not filtered before aggregation, they contaminate pre-HL counts.
**How to avoid:** Apply sentinel exclusion filter (DX_DATE >= as.Date("1910-01-01")) immediately after collecting raw DIAGNOSIS rows, before any temporal filtering (D-11). Same pattern as R/56 lines 391-396.
**Warning signs:** If pre-HL counts are unexpectedly high for certain codes, check if 1900-01-01 dates are present in dx_pre_hl filtered set.

### Pitfall 4: C81 Rows in Output
**What goes wrong:** Hodgkin Lymphoma (C81*) rows appear in output table with meaningless pre/post counts (pre-HL HL diagnosis is tautological).
**Why it happens:** C81 rows are present in DIAGNOSIS table and pass all filters. Without explicit exclusion, they propagate to final output.
**How to avoid:** Filter out C81 rows after all aggregations are complete but before writing to xlsx (D-09). Apply at both category level (category != "Hodgkin Lymphoma") and code level (!str_detect(cancer_code, "^C81")).
**Warning signs:** If final xlsx contains a "Hodgkin Lymphoma" category row or any C81* code rows, exclusion filter was not applied.

### Pitfall 5: NA DX_DATE Handling Inconsistency
**What goes wrong:** Patients with cancer codes but all NA DX_DATEs disappear from Total Patients column, or appear with 0s in pre/post columns but inflate baseline counts.
**Why it happens:** Temporal filtering requires non-NA dates (cannot compare NA dates). If baseline Total Patients uses all patient-code pairs (including NA-only patients) but pre/post uses only dated rows, counts become inconsistent.
**How to avoid:** D-10 specifies: Total Patients comes from baseline cancer_summary.csv (includes NA-date patients), but pre/post/both columns require non-NA dates. Document this explicitly in xlsx footnote or methodology.
**Warning signs:** If Total Patients > Pre + Post (after removing "Both" duplicates), check if NA-date patients exist in baseline but are excluded from temporal counts.

## Code Examples

Verified patterns from R/55 and R/56:

### Temporal Filter Application
```r
# Source: R/56 lines 405-430 (post-HL filtering)
# Adapted for pre/post split with same-day handling per D-08

# Join with confirmed_hl_cohort to get first_hl_dx_date per row
dx_with_hl_date <- dx_raw %>%
  inner_join(confirmed_hl_cohort %>% select(ID, first_hl_dx_date), by = "ID")

# Filter out rows with NA DX_DATE (cannot compare NA dates)
dx_with_hl_date <- dx_with_hl_date %>%
  filter(!is.na(DX_DATE))

# Pre-HL: same-day included (<=)
dx_pre_hl <- dx_with_hl_date %>%
  filter(DX_DATE <= first_hl_dx_date)

# Post-HL: strict > (same-day excluded, consistent with R/56)
dx_post_hl <- dx_with_hl_date %>%
  filter(DX_DATE > first_hl_dx_date)

n_pre <- nrow(dx_pre_hl)
n_post <- nrow(dx_post_hl)
message(glue("Pre-HL rows: {format(n_pre, big.mark=',')}"))
message(glue("Post-HL rows: {format(n_post, big.mark=',')}"))
```

### Both Count Computation
```r
# Compute "Both" = patients with code X both before AND after first_hl_dx_date
# Source: Set intersection pattern, standard dplyr

# Patient-code pairs in pre-HL set
patients_pre <- dx_pre_hl %>%
  distinct(ID, DX_norm) %>%
  rename(cancer_code = DX_norm)

# Patient-code pairs in post-HL set
patients_post <- dx_post_hl %>%
  distinct(ID, DX_norm) %>%
  rename(cancer_code = DX_norm)

# Intersection: patients with same code pre AND post
patients_both <- patients_pre %>%
  inner_join(patients_post, by = c("ID", "cancer_code"))

# Aggregate counts by code
pre_counts <- patients_pre %>%
  group_by(cancer_code) %>%
  summarise(pre_hl_count = n_distinct(ID), .groups = "drop")

post_counts <- patients_post %>%
  group_by(cancer_code) %>%
  summarise(post_hl_count = n_distinct(ID), .groups = "drop")

both_counts <- patients_both %>%
  group_by(cancer_code) %>%
  summarise(both_count = n_distinct(ID), .groups = "drop")
```

### Baseline Metrics + Temporal Counts Merge
```r
# Source: R/55 lines 548-567 (code-level aggregation) + new temporal counts

# Baseline patient-code metrics (from cancer_summary.csv)
code_summary <- cancer_summary %>%
  filter(!str_detect(cancer_code, "^C81")) %>%  # D-09: Exclude C81 early
  group_by(cancer_code, category) %>%
  summarise(
    total_patients        = n_distinct(ID),
    confirmed_2date       = n_distinct(ID[two_or_more_unique_dates == 1]),
    confirmed_7day        = n_distinct(ID[two_or_more_unique_dates_gt_7 == 1]),
    total_records         = sum(record_count, na.rm = TRUE),
    .groups = "drop"
  )

# Merge temporal counts (left join to preserve all codes, even if 0 pre/post)
code_summary <- code_summary %>%
  left_join(pre_counts, by = "cancer_code") %>%
  left_join(post_counts, by = "cancer_code") %>%
  left_join(both_counts, by = "cancer_code") %>%
  mutate(
    pre_hl_count = ifelse(is.na(pre_hl_count), 0L, as.integer(pre_hl_count)),
    post_hl_count = ifelse(is.na(post_hl_count), 0L, as.integer(post_hl_count)),
    both_count = ifelse(is.na(both_count), 0L, as.integer(both_count))
  )

# Reorder columns per D-07
code_summary <- code_summary %>%
  select(cancer_code, category, total_patients, confirmed_2date, confirmed_7day,
         pre_hl_count, post_hl_count, both_count, total_records)
```

### Excel Sheet Writing with Styling
```r
# Source: R/55 lines 652-850 (cancer_summary_table.xlsx two-sheet pattern)
# Adapted for new column structure per D-06 and D-07

# Styling constants (same as R/55)
DARK_HEADER_FILL <- "FF374151"
WHITE_FONT       <- "FFFFFFFF"
TITLE_FONT_COLOR <- "FF1F2937"
TOTALS_FILL      <- "FFE5E7EB"

wb <- wb_workbook()

# Sheet 1: Category Summary
SHEET1 <- "Category Summary"
wb$add_worksheet(SHEET1)

# Row 1: Title
wb$add_data(sheet = SHEET1, x = "Cancer Summary Table - Pre/Post HL Diagnosis",
            start_row = 1, start_col = 1)
wb$add_font(sheet = SHEET1, dims = "A1",
            name = "Calibri", size = 16, bold = TRUE,
            color = wb_color(TITLE_FONT_COLOR))
wb$merge_cells(sheet = SHEET1, dims = "A1:H1")

# Row 2: Headers (8 columns per D-06)
headers1 <- c(
  "Cancer Site Category",
  "Total Patients",
  "Confirmed (2+ Dates)",
  "Confirmed (7-Day Gap)",
  "Pre-HL",
  "Post-HL",
  "Both",
  "Total Records"
)
for (i in seq_along(headers1)) {
  wb$add_data(sheet = SHEET1, x = headers1[i], start_row = 2, start_col = i)
}
wb$add_fill(sheet = SHEET1, dims = "A2:H2", color = wb_color(DARK_HEADER_FILL))
wb$add_font(sheet = SHEET1, dims = "A2:H2",
            name = "Calibri", size = 11, bold = TRUE,
            color = wb_color(WHITE_FONT))

# Freeze pane
wb$freeze_pane(sheet = SHEET1, first_active_row = 3, first_active_col = 1)

# Data rows starting at row 3
data_start1 <- 3
n_data1     <- nrow(category_summary)
data_end1   <- data_start1 + n_data1 - 1

wb$add_data(sheet = SHEET1, x = as.data.frame(category_summary),
            start_row = data_start1, col_names = FALSE)

# Number formatting: All count columns use "#,##0" (comma-separated integers)
# Columns B-H (all counts, no percentages per D-05)
wb$add_numfmt(sheet = SHEET1, dims = glue("B{data_start1}:H{data_end1}"), numfmt = "#,##0")

# Totals row
totals_row1 <- data_end1 + 1
wb$add_data(sheet = SHEET1, x = as.data.frame(totals_category),
            start_row = totals_row1, col_names = FALSE)
wb$add_fill(sheet = SHEET1,
            dims  = glue("A{totals_row1}:H{totals_row1}"),
            color = wb_color(TOTALS_FILL))
wb$add_font(sheet = SHEET1,
            dims  = glue("A{totals_row1}:H{totals_row1}"),
            name  = "Calibri", size = 11, bold = TRUE,
            color = wb_color(TITLE_FONT_COLOR))
wb$add_numfmt(sheet = SHEET1,
              dims  = glue("B{totals_row1}:H{totals_row1}"),
              numfmt = "#,##0")

# Column widths
wb$set_col_widths(sheet = SHEET1, cols = 1:8,
                  widths = c(40, 14, 18, 18, 10, 10, 10, 14))
```

## Open Questions

None — all critical questions resolved via CONTEXT.md decisions (D-01 through D-16) and canonical reference inspection (R/55, R/56).

## Environment Availability

Step 2.6: SKIPPED (no external dependencies beyond project's existing R environment)

## Validation Architecture

> Skipped — workflow.nyquist_validation is explicitly set to false in .planning/config.json.

## Sources

### Primary (HIGH confidence)
- R/55_cancer_summary_refined.R (lines 1-859) — Baseline cancer summary pattern: D-code removal, HL cohort confirmation, confirmed_hl_cohort.rds creation, PREFIX_MAP, classify_codes(), openxlsx2 two-sheet styling
- R/56_cancer_summary_post_hl.R (lines 1-1006) — Temporal filtering pattern: DuckDB raw row query, DX_DATE > first_hl_dx_date filter, sentinel exclusion, post-HL re-aggregation
- 58-CONTEXT.md (lines 1-117) — User decisions: column structure (D-01 through D-05), column ordering (D-06, D-07), same-day handling (D-08), C81 exclusion (D-09), NA date handling (D-10), sentinel dates (D-11), data sources (D-12, D-13), output strategy (D-14, D-15), styling (D-16)
- R/00_config.R (lines 1-100) — CONFIG paths, USE_DUCKDB flag, cache settings

### Secondary (MEDIUM confidence)
- R/01_load_pcornet.R (inferred from R/55 and R/56 source calls) — get_pcornet_table(), close_pcornet_con() functions for DuckDB access

### Tertiary (LOW confidence)
None

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All libraries established in R/55 and R/56 with explicit version verification
- Architecture: HIGH - Direct reuse of R/55 (baseline aggregation, xlsx styling) and R/56 (temporal filtering) patterns
- Pitfalls: HIGH - Five pitfalls identified with concrete examples from R/55 and R/56 code inspection and CONTEXT.md edge cases

**Research date:** 2026-05-26
**Valid until:** 2026-06-25 (30 days — stable R ecosystem, project-specific patterns unlikely to change)
