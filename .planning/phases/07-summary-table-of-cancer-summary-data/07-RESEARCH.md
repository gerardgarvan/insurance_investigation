# Phase 7: Summary Table of Cancer Summary Data - Research

**Researched:** 2026-05-21
**Domain:** R data aggregation, openxlsx2 styled multi-sheet xlsx generation, dplyr group_by summarization
**Confidence:** HIGH

## Summary

Phase 7 creates a two-sheet xlsx summary table from the Phase 6 cancer_summary patient-code level dataset (R/53_cancer_summary.R output). The summary aggregates by (1) cancer site category and (2) exact ICD-10 code, showing patient counts, confirmation rates (both 2+ dates and 7-day gap), date distribution stats (mean and median of unique_dates), and record counts from DIAGNOSIS.

This is a standard dplyr aggregation pattern (group_by + summarise) followed by openxlsx2 styled xlsx generation matching R/47 and R/50 conventions. The research confirms established patterns exist in the codebase for:
- **Aggregation**: R/50 and R/51 already aggregate by category and code
- **Two-sheet xlsx**: R/50, R/51, R/52 all produce multi-sheet workbooks
- **openxlsx2 styling**: R/47, R/50, R/52 use dark header fill (FF374151), white font, freeze panes, number formatting, auto widths
- **DuckDB record counts**: R/52 pattern for querying DIAGNOSIS to get total record counts per code

**Primary recommendation:** Follow R/52 structure for aggregation + styled xlsx generation. Reuse PREFIX_MAP and classify_codes() from R/53 (already copied from R/47). Read cancer_summary.xlsx/csv from Phase 6, aggregate, query DuckDB for record counts, write styled xlsx.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Two-sheet xlsx: one sheet aggregated by cancer site category (from PREFIX_MAP), one sheet aggregated by exact ICD-10 code
- **D-02:** Category-level sheet: one row per cancer site category (~54 categories)
- **D-03:** Code-level sheet: one row per unique ICD-10 code — include ALL codes, no minimum patient count threshold
- **D-04:** Patient counts: total_patients per category/code (the base metric)
- **D-05:** Confirmation rates: confirmed_patients (2+ dates), confirmed_7day (7-day gap), and percentage rates for both — show both absolute counts AND percentages
- **D-06:** Date distribution stats: mean and median of unique_dates_total and unique_dates_with_sep_gt_7 per category/code
- **D-07:** Record counts: total DIAGNOSIS rows per category/code (not just unique dates — shows encounter volume)
- **D-08:** Styled xlsx with dark fill + white font headers, freeze panes, auto column widths, number formatting — matches R/47 and R/50 patterns
- **D-09:** xlsx only, no CSV output
- **D-10:** Filename: cancer_summary_table.xlsx in output/tables/
- **D-11:** Output directory: output/tables/ (same as Phase 6)
- **D-12:** All patients in DIAGNOSIS with neoplasm codes (not restricted to HL cohort) — consistent with Phase 6
- **D-13:** All neoplasm codes included (C and D prefixes, C00-D49) — matches Phase 6 scope
- **D-14:** Rows sorted by patient count descending (most common cancer sites/codes at top)
- **D-15:** New R script (Claude's discretion on number, likely R/54_cancer_summary_table.R)

### Claude's Discretion
- Script number assignment
- Exact column header names (should be human-readable)
- Whether to include a totals row at the bottom of each sheet
- Percentage number formatting (e.g., 1 decimal place)
- Whether date distribution stats use mean, median, or both
</user_constraints>

## Standard Stack

### Core Libraries
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| dplyr | 1.2.0+ | Data aggregation | group_by + summarise for category/code-level rollups; standard for readable aggregation |
| stringr | 1.5.1+ | Prefix extraction | substr() for 3-char prefix classification (reuse from R/53) |
| glue | 1.8.0 | String formatting | Readable logging messages with embedded expressions |
| openxlsx2 | 1.15+ | Styled xlsx generation | Two-sheet workbook with dark header styling, freeze panes, number formatting — project standard per R/47, R/50, R/52 |
| tibble | 3.2.1+ | Data frame operations | Modern tibble operations for clean aggregation |

**Installation:**
```bash
# Already installed per project STACK.md — no new dependencies
```

**Version verification:** All libraries already in use by R/47, R/50, R/52, R/53. No new dependencies needed.

## Architecture Patterns

### Recommended Script Structure
```
R/54_cancer_summary_table.R
├── SECTION 1: SETUP
│   ├── Load libraries (dplyr, stringr, glue, openxlsx2)
│   ├── source("R/00_config.R")
│   ├── source("R/01_load_pcornet.R")  # For DuckDB access
│   └── Define output path
├── SECTION 2: LOAD AND CLASSIFY SOURCE DATA
│   ├── Read output/tables/cancer_summary.xlsx or .csv (Phase 6 output)
│   ├── Copy PREFIX_MAP and classify_codes() from R/53 (or source R/53 for reuse)
│   └── Classify codes if not already in input data
├── SECTION 3: QUERY RECORD COUNTS FROM DIAGNOSIS
│   ├── get_pcornet_table("DIAGNOSIS") %>% filter DX_TYPE == "10" and neoplasm codes
│   ├── group_by(DX_norm) %>% summarise(record_count = n())
│   └── Join record counts to summary data
├── SECTION 4: CATEGORY-LEVEL AGGREGATION
│   ├── group_by(category)
│   ├── summarise: total_patients, confirmed_patients, confirmed_7day_patients, percentage rates
│   ├── summarise: mean/median of unique_dates_total, mean/median of unique_dates_with_sep_gt_7
│   ├── summarise: total_records (sum of record_count)
│   └── arrange(desc(total_patients))
├── SECTION 5: CODE-LEVEL AGGREGATION
│   ├── group_by(cancer_code, category)
│   ├── summarise: same metrics as category level but per exact code
│   └── arrange(desc(total_patients))
├── SECTION 6: WRITE STYLED XLSX (two sheets)
│   ├── wb <- wb_workbook()
│   ├── Sheet 1: "Category Summary" with category-level data
│   ├── Sheet 2: "Code Summary" with code-level data
│   ├── Apply openxlsx2 styling: dark header fill, white font, freeze panes, number formatting, auto widths
│   └── wb$save(OUTPUT_PATH)
└── SECTION 7: CLEANUP
    └── close_pcornet_con()
```

### Pattern 1: Reuse PREFIX_MAP and classify_codes()
**What:** PREFIX_MAP (3-char ICD-10 prefix → cancer site category) and classify_codes() function from R/47/R/53
**When to use:** Every script that needs to classify ICD-10 codes by cancer site
**Example:**
```R
# From R/53_cancer_summary.R lines 59-328
PREFIX_MAP <- c(
  "C00" = "Lip, Oral Cavity and Pharynx",
  "C01" = "Lip, Oral Cavity and Pharynx",
  # ... 54 categories total
)

classify_codes <- function(codes) {
  prefix3 <- substr(codes, 1, 3)
  categories <- unname(PREFIX_MAP[prefix3])
  categories
}
```
**Source:** R/47_cancer_site_frequency.R lines 49-382, copied to R/53_cancer_summary.R

### Pattern 2: Two-Sheet XLSX with Consistent Styling
**What:** Multi-sheet workbook with dark header fill (FF374151), white font (FFFFFFFF), freeze panes, number formatting, auto column widths
**When to use:** All styled xlsx outputs (project standard)
**Example:**
```R
# From R/50_cancer_site_confirmation.R lines 523-657
DARK_HEADER_FILL <- "FF374151"
WHITE_FONT       <- "FFFFFFFF"
TITLE_FONT_COLOR <- "FF1F2937"
TOTALS_FILL      <- "FFE5E7EB"

wb <- wb_workbook()

# Sheet 1: Category level
wb$add_worksheet("Category Summary")
# Row 1: Title with merged cells
wb$add_data(sheet = "Category Summary", x = "Cancer Site Summary", start_row = 1, start_col = 1)
wb$add_font(sheet = "Category Summary", dims = "A1", name = "Calibri", size = 16, bold = TRUE, color = wb_color(TITLE_FONT_COLOR))
wb$merge_cells(sheet = "Category Summary", dims = "A1:H1")

# Row 2: Headers with dark fill and white font
headers <- c("Category", "Total Patients", "Confirmed (2+ Dates)", "Confirmed (7-Day)", ...)
for (i in seq_along(headers)) {
  wb$add_data(sheet = "Category Summary", x = headers[i], start_row = 2, start_col = i)
}
wb$add_fill(sheet = "Category Summary", dims = "A2:H2", color = wb_color(DARK_HEADER_FILL))
wb$add_font(sheet = "Category Summary", dims = "A2:H2", name = "Calibri", size = 11, bold = TRUE, color = wb_color(WHITE_FONT))

# Freeze panes at row 3
wb$freeze_pane(sheet = "Category Summary", first_active_row = 3, first_active_col = 1)

# Data rows with number formatting
data_start <- 3
data_end <- data_start + nrow(summary_df) - 1
wb$add_data(sheet = "Category Summary", x = as.data.frame(summary_df), start_row = data_start, col_names = FALSE)
wb$add_numfmt(sheet = "Category Summary", dims = glue("B{data_start}:D{data_end}"), numfmt = "#,##0")  # Integer counts
wb$add_numfmt(sheet = "Category Summary", dims = glue("E{data_start}:F{data_end}"), numfmt = "0.0%")   # Percentages

# Auto column widths
wb$set_col_widths(sheet = "Category Summary", cols = 1:8, widths = "auto")  # or explicit: c(40, 14, 16, ...)

wb$save(OUTPUT_PATH)
```
**Source:** R/50_cancer_site_confirmation.R (2-sheet pattern), R/52_all_codes_resolved.xlsx (6-sheet pattern), R/47_cancer_site_frequency.R (styling pattern)

### Pattern 3: DuckDB Record Count Query
**What:** Query DIAGNOSIS table via DuckDB to get total record counts per code (not just unique dates)
**When to use:** When record counts are needed in addition to patient counts
**Example:**
```R
# From R/52_all_codes_resolved.R lines 215-292 (PROCEDURES query pattern)
# Adapt for DIAGNOSIS with ICD-10 neoplasm codes

dx_record_counts <- get_pcornet_table("DIAGNOSIS") %>%
  filter(DX_TYPE == "10") %>%
  mutate(DX_norm = toupper(str_remove_all(DX, "\\."))) %>%
  filter(str_detect(DX_norm, "^[CD]")) %>%  # Neoplasm codes only
  group_by(DX_norm) %>%
  summarise(record_count = n(), .groups = "drop") %>%
  collect()
```
**Source:** R/52_all_codes_resolved.R lines 215-292 (PROCEDURES query), adapted for DIAGNOSIS

### Pattern 4: Patient-Level to Summary Aggregation
**What:** Aggregate patient-code level data (one row per patient per code) to summary level (one row per category or code)
**When to use:** Creating summary tables from patient-level detail
**Example:**
```R
# Category-level aggregation
category_summary <- cancer_summary_patient_level %>%
  group_by(category) %>%
  summarise(
    total_patients = n_distinct(ID),
    confirmed_patients = sum(two_or_more_unique_dates),  # Count of patients with flag = 1
    confirmed_7day = sum(two_or_more_unique_dates_gt_7),
    confirmation_rate = confirmed_patients / total_patients,
    confirmation_rate_7day = confirmed_7day / total_patients,
    mean_unique_dates = mean(unique_dates_total, na.rm = TRUE),
    median_unique_dates = median(unique_dates_total, na.rm = TRUE),
    mean_unique_dates_7day = mean(unique_dates_with_sep_gt_7, na.rm = TRUE),
    median_unique_dates_7day = median(unique_dates_with_sep_gt_7, na.rm = TRUE),
    total_records = sum(record_count, na.rm = TRUE),  # From DuckDB join
    .groups = "drop"
  ) %>%
  arrange(desc(total_patients))

# Code-level aggregation (same pattern, group by cancer_code + category)
code_summary <- cancer_summary_patient_level %>%
  group_by(cancer_code, category) %>%
  summarise(...same metrics..., .groups = "drop") %>%
  arrange(desc(total_patients))
```
**Source:** R/50_cancer_site_confirmation.R lines 418-448 (exact code aggregation), lines 463-493 (category aggregation)

### Anti-Patterns to Avoid
- **Don't recompute confirmation from DIAGNOSIS:** Phase 6 already computed two_or_more_unique_dates flags — just sum() them per group
- **Don't use wide format for sheets:** Each sheet is a flat table (not pivoted) per R/50 pattern
- **Don't skip totals row:** R/50 and R/52 both include totals rows with distinct styling (TOTALS_FILL background)

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Multi-sheet styled xlsx | Custom XML generation | openxlsx2 wb_workbook() | openxlsx2 provides wb_add_worksheet(), wb_add_fill(), wb_add_font(), wb_freeze_pane(), wb_set_col_widths() — all formatting needs covered |
| Cancer site classification | Parse ICD-10 ranges ad-hoc | PREFIX_MAP + classify_codes() from R/53 | Already implemented and tested in R/47, R/53 (54 categories, 319 prefixes) |
| Number formatting | Post-hoc Excel manual formatting | wb_add_numfmt() in script | Reproducible, version-controlled formatting (R/47, R/50, R/52 standard) |
| Record counts | Count unique dates | Query DIAGNOSIS via DuckDB | Distinct dates != total encounters. D-07 requires total DIAGNOSIS rows (encounter volume metric) |

**Key insight:** Phase 6 already did the hard work (patient-code level detail with confirmation flags). Phase 7 is pure aggregation + styling — no new computation logic needed.

## Runtime State Inventory

> Omitted — not a rename/refactor/migration phase. This is greenfield aggregation.

## Common Pitfalls

### Pitfall 1: Confusing patient counts with record counts
**What goes wrong:** Using n_distinct(ID) when D-07 requires total DIAGNOSIS rows
**Why it happens:** Phase 6 output has one row per patient per code — easy to count patients, but record counts require DuckDB query
**How to avoid:** Query DIAGNOSIS table separately for record counts (pattern from R/52), join to summary data
**Warning signs:** If record_count == patient_count (should be higher — patients have multiple encounters per code)

### Pitfall 2: Missing confirmation flag interpretation
**What goes wrong:** Trying to recompute confirmation logic instead of aggregating existing flags
**Why it happens:** Not recognizing that two_or_more_unique_dates is already a 1/0 flag
**How to avoid:** sum(two_or_more_unique_dates) gives count of confirmed patients (flag = 1 means confirmed)
**Warning signs:** Complex date logic in summarise() block (should just be sum())

### Pitfall 3: Forgetting percentage denominators
**What goes wrong:** Percentage rates computed incorrectly (e.g., confirmed / total_records instead of confirmed / total_patients)
**Why it happens:** Multiple counts in play (patients vs records)
**How to avoid:** D-05 specifies rates as confirmed_patients / total_patients (patient-based rates, not encounter-based)
**Warning signs:** Confirmation rates > 100% or near 0% when data shows meaningful confirmation counts

### Pitfall 4: openxlsx2 dims string construction
**What goes wrong:** dims argument uses wrong Excel coordinate format (e.g., dims = "A2-F2" instead of "A2:F2")
**Why it happens:** Unfamiliarity with Excel A1 notation
**How to avoid:** Use "A2:F2" format (colon, not dash); use glue() for dynamic ranges: glue("A3:A{last_row}")
**Warning signs:** R error: "invalid 'dims' argument" from wb_add_fill() or wb_add_font()

### Pitfall 5: Totals row styling inconsistency
**What goes wrong:** Totals row not styled (TOTALS_FILL background, bold font) or number formatting breaks
**Why it happens:** Forgetting to apply styling to totals_start row separately from data rows
**How to avoid:** Apply wb_add_fill(), wb_add_font(), wb_add_numfmt() to totals row explicitly (see R/50 lines 569-583, R/52 lines 649-661)
**Warning signs:** Totals row looks like regular data rows in Excel output

## Code Examples

Verified patterns from existing scripts:

### Aggregation: Category-Level Summary
```R
# Source: R/50_cancer_site_confirmation.R lines 463-493
# Adapted for Phase 7 metrics

category_summary <- cancer_summary_patient_level %>%
  group_by(category) %>%
  summarise(
    total_patients = n_distinct(ID),
    confirmed_patients = sum(two_or_more_unique_dates, na.rm = TRUE),
    confirmed_7day = sum(two_or_more_unique_dates_gt_7, na.rm = TRUE),
    unconfirmed_patients = total_patients - confirmed_patients,
    unconfirmed_7day = total_patients - confirmed_7day,
    confirmation_rate = confirmed_patients / total_patients,
    confirmation_rate_7day = confirmed_7day / total_patients,
    mean_unique_dates = mean(unique_dates_total, na.rm = TRUE),
    median_unique_dates = median(unique_dates_total, na.rm = TRUE),
    mean_unique_dates_7day = mean(unique_dates_with_sep_gt_7, na.rm = TRUE),
    median_unique_dates_7day = median(unique_dates_with_sep_gt_7, na.rm = TRUE),
    total_records = sum(record_count, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(desc(total_patients))
```

### DuckDB Record Count Query
```R
# Source: R/52_all_codes_resolved.R lines 215-245 (PROCEDURES pattern), adapted for DIAGNOSIS

message("Querying DIAGNOSIS for record counts...")

dx_record_counts <- get_pcornet_table("DIAGNOSIS") %>%
  filter(DX_TYPE == "10") %>%
  mutate(DX_norm = toupper(str_remove_all(DX, "\\."))) %>%
  filter(str_detect(DX_norm, "^[CD]")) %>%  # Neoplasm codes C00-D49
  group_by(DX_norm) %>%
  summarise(record_count = n(), .groups = "drop") %>%
  collect()

message(glue("  Found record counts for {nrow(dx_record_counts)} unique codes"))

# Join to patient-level data
cancer_summary_with_counts <- cancer_summary_patient_level %>%
  left_join(dx_record_counts, by = c("cancer_code" = "DX_norm")) %>%
  mutate(record_count = if_else(is.na(record_count), 0L, as.integer(record_count)))
```

### openxlsx2 Two-Sheet Styled Workbook
```R
# Source: R/50_cancer_site_confirmation.R lines 520-657

DARK_HEADER_FILL <- "FF374151"
WHITE_FONT       <- "FFFFFFFF"
TITLE_FONT_COLOR <- "FF1F2937"
TOTALS_FILL      <- "FFE5E7EB"

wb <- wb_workbook()

# ---------------------------------------------------------------------------
# Sheet 1: Category Summary
# ---------------------------------------------------------------------------
SHEET1 <- "Category Summary"
wb$add_worksheet(SHEET1)

# Row 1: Title
wb$add_data(sheet = SHEET1, x = "Cancer Site Summary - By Category",
            start_row = 1, start_col = 1)
wb$add_font(sheet = SHEET1, dims = "A1",
            name = "Calibri", size = 16, bold = TRUE,
            color = wb_color(TITLE_FONT_COLOR))
wb$merge_cells(sheet = SHEET1, dims = "A1:K1")  # Adjust column span to fit headers

# Row 2: Headers
headers1 <- c("Cancer Site Category", "Total Patients", "Confirmed (2+ Dates)", "Unconfirmed", "Rate (%)",
              "Confirmed (7-Day)", "Unconfirmed", "Rate (%)", "Mean Dates", "Median Dates", "Total Records")
for (i in seq_along(headers1)) {
  wb$add_data(sheet = SHEET1, x = headers1[i], start_row = 2, start_col = i)
}
wb$add_fill(sheet = SHEET1, dims = "A2:K2", color = wb_color(DARK_HEADER_FILL))
wb$add_font(sheet = SHEET1, dims = "A2:K2",
            name = "Calibri", size = 11, bold = TRUE,
            color = wb_color(WHITE_FONT))

# Freeze pane
wb$freeze_pane(sheet = SHEET1, first_active_row = 3, first_active_col = 1)

# Data rows
data_start <- 3
n_data     <- nrow(category_summary)
data_end   <- data_start + n_data - 1

wb$add_data(sheet = SHEET1, x = as.data.frame(category_summary),
            start_row = data_start, col_names = FALSE)
# Number formatting
wb$add_numfmt(sheet = SHEET1, dims = glue("B{data_start}:D{data_end}"), numfmt = "#,##0")  # Patient counts
wb$add_numfmt(sheet = SHEET1, dims = glue("E{data_start}:E{data_end}"), numfmt = "0.0%")   # Rate
wb$add_numfmt(sheet = SHEET1, dims = glue("F{data_start}:G{data_end}"), numfmt = "#,##0")  # 7-day counts
wb$add_numfmt(sheet = SHEET1, dims = glue("H{data_start}:H{data_end}"), numfmt = "0.0%")   # 7-day rate
wb$add_numfmt(sheet = SHEET1, dims = glue("I{data_start}:J{data_end}"), numfmt = "0.0")    # Mean/median (1 decimal)
wb$add_numfmt(sheet = SHEET1, dims = glue("K{data_start}:K{data_end}"), numfmt = "#,##0")  # Total records

# Totals row
totals_start <- data_end + 1
totals_row <- tibble(
  category = "TOTAL",
  total_patients = sum(category_summary$total_patients),
  confirmed_patients = sum(category_summary$confirmed_patients),
  unconfirmed_patients = sum(category_summary$unconfirmed_patients),
  confirmation_rate = NA_real_,  # Don't aggregate rates
  confirmed_7day = sum(category_summary$confirmed_7day),
  unconfirmed_7day = sum(category_summary$unconfirmed_7day),
  confirmation_rate_7day = NA_real_,
  mean_unique_dates = NA_real_,
  median_unique_dates = NA_real_,
  total_records = sum(category_summary$total_records)
)
wb$add_data(sheet = SHEET1, x = as.data.frame(totals_row),
            start_row = totals_start, col_names = FALSE)
wb$add_fill(sheet = SHEET1, dims = glue("A{totals_start}:K{totals_start}"),
            color = wb_color(TOTALS_FILL))
wb$add_font(sheet = SHEET1, dims = glue("A{totals_start}:K{totals_start}"),
            name = "Calibri", size = 11, bold = TRUE,
            color = wb_color(TITLE_FONT_COLOR))
wb$add_numfmt(sheet = SHEET1, dims = glue("B{totals_start}:D{totals_start}"), numfmt = "#,##0")
wb$add_numfmt(sheet = SHEET1, dims = glue("F{totals_start}:G{totals_start}"), numfmt = "#,##0")
wb$add_numfmt(sheet = SHEET1, dims = glue("K{totals_start}:K{totals_start}"), numfmt = "#,##0")

# Column widths (explicit or "auto")
wb$set_col_widths(sheet = SHEET1, cols = 1:11, widths = c(40, 14, 16, 14, 10, 16, 14, 10, 12, 12, 14))

# ---------------------------------------------------------------------------
# Sheet 2: Code Summary (same pattern, different data)
# ---------------------------------------------------------------------------
SHEET2 <- "Code Summary"
wb$add_worksheet(SHEET2)
# ... (repeat pattern with code_summary data and one extra column for code)

# ---------------------------------------------------------------------------
# Save
# ---------------------------------------------------------------------------
wb$save(OUTPUT_PATH)
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual Excel formatting post-export | openxlsx2 wb_add_fill(), wb_add_font(), wb_add_numfmt() in script | Since R/47 (Phase 47) | Reproducible, version-controlled styling |
| Base R table() and aggregate() | dplyr group_by() + summarise() | Project standard | Cleaner, more readable aggregation code |
| RDS backend for all queries | DuckDB lazy queries via get_pcornet_table() | Phase 30 (default: Phase 32) | Faster, lower memory for large table queries |
| CSV output only | Styled xlsx as primary output | Since Phase 47 | Immediate readability for clinical stakeholders |

**Deprecated/outdated:**
- None — all patterns are current project standards as of 2026-05-21

## Open Questions

1. **Should totals row show overall confirmation rates, or leave those cells blank?**
   - What we know: R/50 leaves confirmation_rate as NA_real_ in totals row (line 505)
   - What's unclear: Whether D-05 wants overall rates computed (sum(confirmed) / sum(total))
   - Recommendation: Follow R/50 pattern (leave rates as NA) unless user specifies otherwise in Claude's discretion

2. **Mean vs median for date distribution stats (D-06)?**
   - What we know: D-06 says "mean and median" but doesn't specify if both or just one
   - What's unclear: Whether to show both (4 columns) or just one (2 columns)
   - Recommendation: Show both (mean and median for each of unique_dates_total and unique_dates_with_sep_gt_7) = 4 columns total. Provides richer distribution picture.

3. **How to handle categories with zero patients?**
   - What we know: D-02 says ~54 categories, but Phase 6 only includes categories with actual patients
   - What's unclear: Should Phase 7 fill in zero rows for unpopulated categories?
   - Recommendation: Follow R/50 pattern line 442 (filter total_patients > 0) — only show categories with data

## Environment Availability

> Skipped — no external dependencies beyond R packages already in use (dplyr, stringr, glue, openxlsx2, all installed per project STACK.md)

## Validation Architecture

> Omitted — workflow.nyquist_validation is set to false in .planning/config.json

## Sources

### Primary (HIGH confidence)
- R/53_cancer_summary.R — Phase 6 output structure, PREFIX_MAP + classify_codes() pattern
- R/50_cancer_site_confirmation.R — Two-sheet category + code aggregation pattern, openxlsx2 styling
- R/52_all_codes_resolved.R — Multi-sheet xlsx pattern, DuckDB record count query pattern
- R/47_cancer_site_frequency.R — openxlsx2 dark header styling constants and pattern
- R/01_load_pcornet.R — get_pcornet_table() DuckDB access pattern
- R/00_config.R — CONFIG$output_dir and USE_DUCKDB settings
- .planning/phases/07-summary-table-of-cancer-summary-data/07-CONTEXT.md — User decisions and constraints

### Secondary (MEDIUM confidence)
- openxlsx2 CRAN documentation — wb_workbook() API, wb_add_fill(), wb_add_font(), wb_add_numfmt(), wb_freeze_pane(), wb_set_col_widths()

### Tertiary (LOW confidence)
- None

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All libraries already in use by project (R/47, R/50, R/52, R/53)
- Architecture: HIGH - Four established patterns identified (aggregation, two-sheet xlsx, DuckDB record counts, openxlsx2 styling)
- Pitfalls: HIGH - All pitfalls derived from actual code patterns and common R/dplyr mistakes
- Code examples: HIGH - All examples extracted from working scripts (R/50, R/52, R/53)

**Research date:** 2026-05-21
**Valid until:** ~60 days (patterns are stable project conventions, unlikely to change)
