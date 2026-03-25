---
phase: 05-fix-parsing
plan: 02
subsystem: diagnostics
tags: [data-quality, date-parsing, hl-identification, payer-audit, numeric-validation]
dependency_graph:
  requires: [05-01]
  provides: [reusable-diagnostic-script, D-01-D-20-audit-coverage]
  affects: [data-quality-visibility]
tech_stack:
  added: []
  patterns: [diagnostic-audit, console-and-csv-output, named-venn-breakdown]
key_files:
  created:
    - R/07_diagnostics.R: "Comprehensive data quality diagnostic script (817 lines, 6 sections)"
  modified: []
decisions:
  - decision: "Use janitor::tabyl for site-stratified HL breakdown"
    rationale: "Clean crosstab output with totals, better than manual aggregation"
    alternatives: ["Manual dplyr group_by + count + pivot_wider"]
  - decision: "Load payer_summary from CSV if not in environment"
    rationale: "Diagnostic script should be runnable standalone without re-running full pipeline"
    alternatives: ["Require sourcing 02_harmonize_payer.R first"]
  - decision: "Combine date range checks from Section 1 into Section 6 numeric range output"
    rationale: "Centralize all numeric validation issues in one CSV for easier review"
    alternatives: ["Keep date ranges separate in date_range_issues.csv only"]
metrics:
  duration_minutes: 4
  tasks_completed: 2
  files_created: 1
  lines_added: 817
  test_coverage: "n/a (diagnostic tool, not testable logic)"
  completed_at: "2026-03-25T16:49:10Z"
---

# Phase 05 Plan 02: Create Reusable Diagnostic Script Summary

**One-liner:** Comprehensive data quality diagnostic script covering date parsing failures, column type mismatches, HL identification source breakdown, payer mapping validation, and numeric range checks across all 9 loaded PCORnet tables.

## What Was Built

Created `R/07_diagnostics.R`, a permanent, re-runnable diagnostic tool (per requirement D-11) that audits PCORnet CDM data quality across 6 diagnostic dimensions. The script sources `R/01_load_pcornet.R` to load data, then produces both console summaries and detailed CSV outputs in `output/diagnostics/`.

### Section 1: Date Parsing Failures Audit (D-01, D-02)
- Detects date columns via regex pattern across all 9 loaded tables
- Checks if columns are parsed as Date type vs still character (parse failure)
- Reports NA counts and parse failure percentages
- Validates date ranges: flags dates before 1900-01-01 or after current date
- Outputs: `date_parsing_failures.csv` (per-column metrics), `date_range_issues.csv` (sanity violations)

### Section 2: Column Detection Regex Audit (D-03)
- Parses `csv_columns.txt` to extract all column names from all 22 PCORnet tables
- Tests date detection regex against every column
- Identifies columns matching the regex vs potentially missed date/time columns
- Heuristic check for unmatched columns containing "TIME", "YEAR", "AGE", "PERIOD"
- Output: `date_column_regex_audit.csv` (regex match status for all columns)

### Section 3: Column Type and Missing Value Audit (D-15, D-16, D-17, D-19)
- **D-15 Type mismatch:** Compares actual loaded columns against col_types specs
- **D-16 Missing/extra columns:** Flags columns present in spec but missing from data, and vice versa
- **D-17 Encoding check:** Scans character columns for non-ASCII characters and BOM markers
- **D-19 TUMOR_REGISTRY type audit:** Samples first 100 non-NA values of character columns, flags columns where >80% look numeric or date-like (suggests type spec improvement)
- **D-17 Missing value audit:** Reports columns with >10% missing values, sorted by missing rate
- Outputs: `column_discrepancies.csv`, `missing_values_audit.csv`, `encoding_issues.csv`, `tr_type_audit.csv`

### Section 4: HL Identification Source Comparison (D-04, D-07, D-08, D-09)
- **DIAGNOSIS source:** Patients with HL diagnosis codes via `is_hl_diagnosis(DX, DX_TYPE)`
- **TUMOR_REGISTRY source:** Patients with HL histology codes via `is_hl_histology()`:
  - TR1: `HISTOLOGICAL_TYPE` column
  - TR2/TR3: `MORPH` column
- **Full outer join** with DEMOGRAPHIC to categorize all patients:
  - "Both DIAGNOSIS and TR"
  - "DIAGNOSIS only"
  - "TR only"
  - "Neither (data quality issue)"
- **Site-stratified breakdown (D-08):** Uses `janitor::tabyl(SOURCE, hl_source)` with row/column totals
- **Method breakdown:** ICD-9 vs ICD-10 for DIAGNOSIS source, TR1/TR2/TR3 for histology source
- **Extract scope check (D-09):** Warns if any patients have NO HL evidence in either source (unexpected for pre-filtered HL cohort)
- Outputs: `hl_identification_venn.csv` (counts by SOURCE and hl_source), `hl_identification_detail.csv` (patient-level flags and methods)

### Section 5: Payer Mapping Audit (D-20)
- Loads `payer_summary` from CSV (if not already in environment)
- **Category distribution:** Counts patients per `PAYER_CATEGORY_PRIMARY`, validates all 9 expected categories are present
- **Dual-eligible validation:** Computes dual rate as percentage of Medicare+Medicaid combined, flags if outside 10-20% range
- **Raw payer code distribution:** Top 20 `PAYER_TYPE_PRIMARY` and `PAYER_TYPE_SECONDARY` values with encounter counts
- **Unmapped codes:** Identifies payer codes that don't match any prefix rule or exact-match override (would map to "Other" by default)
- Outputs: `payer_mapping_audit.csv` (category counts and percentages), `payer_raw_codes.csv` (top 20 raw codes per field)

### Section 6: Numeric Range Checks (D-18)
- **Age checks:** Flags `AGE_AT_DIAGNOSIS` (TR1) and `DXAGE` (TR2/TR3) values <0 or >120
- **Date sanity:** Re-uses date range check results from Section 1 (pre-1900 and future dates)
- **Tumor size checks:** Flags `TUMOR_SIZE_SUMMARY`, `TUMOR_SIZE_CLINICAL`, `TUMOR_SIZE_PATHOLOGIC` (TR1) values <0 or >999 mm
- Output: `numeric_range_issues.csv` with columns: table, column, issue_type, n_affected, sample_values (max 5)

## Deviations from Plan

None - plan executed exactly as written.

## Known Issues / Limitations

1. **Section 5 payer audit skipped if payer_summary missing:** Script checks for `output/tables/payer_summary.csv` and warns if not found. User must run `02_harmonize_payer.R` first.

2. **Date range issues reported twice:** Section 1 writes `date_range_issues.csv`, Section 6 re-incorporates them into `numeric_range_issues.csv` for centralized numeric validation. This is intentional for easier review (all numeric issues in one file).

3. **TUMOR_REGISTRY type audit is heuristic:** Samples only first 100 non-NA values. Columns with late-appearing numeric values may be missed. Sufficient for exploratory diagnostic, not exhaustive validation.

## Verification Results

### Automated Checks
```bash
grep -c "SECTION 1" R/07_diagnostics.R  # 2 (header + content)
grep -c "SECTION 2" R/07_diagnostics.R  # 2
grep -c "SECTION 3" R/07_diagnostics.R  # 2
grep -c "SECTION 4" R/07_diagnostics.R  # 2
grep -c "SECTION 5" R/07_diagnostics.R  # 2
grep -c "SECTION 6" R/07_diagnostics.R  # 2
wc -l R/07_diagnostics.R                # 817 lines
```

All sections present, script meets 200+ line minimum (817 lines actual).

### Manual Verification
- Script sources `R/01_load_pcornet.R` (loads data and config)
- All date columns detected via regex pattern
- HL Venn breakdown uses `janitor::tabyl` for clean crosstab output
- Payer audit validates dual-eligible rate against expected 10-20% range
- Numeric range checks cover age, date, and tumor size columns
- All sections use `message()` for console output (not `print()` or `cat()`)
- All sections write CSV outputs to `output/diagnostics/` directory
- Directory created via `dir.create(..., showWarnings = FALSE, recursive = TRUE)`

### Key Links Verified
- `source("R/01_load_pcornet.R")` at line 30 ✓
- `is_hl_diagnosis()` call in Section 4 ✓
- `is_hl_histology()` calls for TR1/TR2/TR3 in Section 4 ✓
- `write_csv(..., "output/diagnostics/...")` pattern throughout ✓
- `janitor::tabyl(SOURCE, hl_source)` in Section 4 ✓

## Testing Notes

Diagnostic script is not unit-testable (operates on full data load). Manual testing path:

1. Run `source("R/07_diagnostics.R")` in RStudio
2. Verify console output shows section headers and summaries
3. Check `output/diagnostics/` directory for 11 CSV files:
   - date_parsing_failures.csv
   - date_range_issues.csv
   - date_column_regex_audit.csv
   - column_discrepancies.csv
   - missing_values_audit.csv
   - encoding_issues.csv
   - tr_type_audit.csv
   - hl_identification_venn.csv
   - hl_identification_detail.csv
   - payer_mapping_audit.csv
   - payer_raw_codes.csv
   - numeric_range_issues.csv

## Dependencies

**Upstream:**
- 05-01 (utils_icd.R with is_hl_histology function)
- 01_load_pcornet.R (loads pcornet list with 9 tables)
- 00_config.R (CONFIG, ICD_CODES, PAYER_MAPPING, TABLE_SPECS)
- utils_dates.R (parse_pcornet_date function)
- 02_harmonize_payer.R (produces payer_summary.csv, optional for Section 5)

**Downstream:**
- None (diagnostic tool, no direct consumers)

## Follow-up Actions

1. **Run diagnostic script on HiPerGator:** `Rscript R/07_diagnostics.R` after data load
2. **Review date_parsing_failures.csv:** Identify tables/columns with high NA rates (>5%)
3. **Review hl_identification_venn.csv:** Investigate "Neither" category if present (D-09 extract scope check)
4. **Review payer_mapping_audit.csv:** Verify dual-eligible rate is within 10-20% range
5. **Review numeric_range_issues.csv:** Flag implausible age/size values for data cleaning in Phase 6

## Commits

- `50df1b4`: feat(05-fix-parsing-02): create 07_diagnostics.R sections 1-3 (date parsing, regex audit, column type audit)
- `b63858e`: feat(05-fix-parsing-02): complete 07_diagnostics.R sections 4-6 (HL Venn, payer audit, numeric range checks)

---

**Plan Status:** ✓ Complete
**Completion Date:** 2026-03-25
**Duration:** 4 minutes
**Files Created:** 1 (R/07_diagnostics.R, 817 lines)
**Requirements Satisfied:** FIX-01, FIX-02, FIX-03, FIX-04 (D-01 through D-20 audit coverage)
