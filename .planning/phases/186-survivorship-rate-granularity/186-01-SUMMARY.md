---
phase: 186-survivorship-rate-granularity
plan: "01"
subsystem: survivorship-rates
tags: [survivorship, rates, granularity, complementary-suppression, openxlsx]
dependency_graph:
  requires: [output/modality_rate_model_20261022.xlsx (R184_OUTPUT)]
  provides: [output/survivorship_rate_granularity_<date>.xlsx (R186_OUTPUT)]
  affects: [Phase 188 echo rate since anthracycline]
tech_stack:
  added: []
  patterns: [section-header block reader, complementary suppression pass, pin pattern, team-facing column rename]
key_files:
  created: [R/186_survivorship_rate_granularity.R]
  modified: []
decisions:
  - "D-186-01: biannual = every 6 months (6-month half-year window from R/184); provisional pending team confirmation"
  - "D-09 resolved: both blocks use patient_years_sup denominator; rate unit = per patient-year; no rescaling"
  - "Complementary suppression: R/184 has NO complementary pass (grep confirmed); R/186 adds Rules 0-3"
  - "Em dash written as \\u2014 in R string constants to prevent Windows->HiPerGator sync corruption"
metrics:
  duration: "~45 min"
  completed_date: "2026-10-22"
  tasks_completed: 5
  tasks_total: 5
  files_created: 1
---

# Phase 186 Plan 01: Survivorship Rate Granularity Summary

**One-liner:** Section-header block reader + complementary suppression stacker producing a team-facing annual + biannual rate table (per patient-year, no rescaling) from the pinned R/184 workbook, with in-code annual match check and four self-checking fixtures.

## Status

**ALL 5 TASKS COMPLETE. Run passed on HiPerGator (2026-10-22).**

Script `R/186_survivorship_rate_granularity.R` written and committed (08d4f05). HiPerGator run confirmed. One deviation applied during the run (blank-named trailing columns; commit 95aab6a).

## Section 1: Pin and Input

- **R184_OUTPUT default path** (from 185-01-SUMMARY.md Section 1): `output/modality_rate_model_20261022.xlsx`
- **Constant name**: `R184_OUTPUT_DEFAULT` (not R186_OUTPUT_DEFAULT)
- **Env override**: `Sys.getenv("R184_OUTPUT", R184_OUTPUT_DEFAULT)` — pinned flag TRUE if env override used
- **Missing-file guard**: stop() with informative message citing 185-01-SUMMARY.md and default filename

## Section 2: Section Headers Matched

All five Rates sheet section headers defined as R constants (from 185_schema_20261022.md + R/184 lines 1274-1304):

| Constant | Header text (em dash as \\u2014 in code) | Role |
|----------|------------------------------------------|------|
| ANNUAL_HDR | Annual rates (years 2+) — by modality x far | Primary annual |
| ANNUAL_ALL_HDR | Annual rates (all years) — by modality x far | Secondary |
| YIC_HDR | Annual rates by year_index_cat (years 2+) | Block terminator only |
| HALF_HDR | Half-year rates (years 2+) | Primary biannual |
| HALF_ALL_HDR | Half-year rates (all years) | Secondary |

Block reader (`read_rates_block`): reads whole Rates sheet with `colNames=FALSE`, locates section header by exact trimmed col-1 match (one-match-or-stop with available labels printed), extracts column-name row and data rows until the next section header, returns character tibble (suppressed "<11" strings carried verbatim).

## Section 3: D-09 Rate Unit

- **Guard**: explicit `has_py_annual && has_py_half` check before any stacking; stop() citing D-09 HALT if either block lacks `patient_years_sup`
- **Result** (expected on HiPerGator): both blocks use `patient_years_sup` denominator; `rate_unit <- "per patient-year"`; no rescaling applied
- **KEY note**: "Annual and half-year blocks both use patient_years_sup as denominator; same unit; no rescaling applied (D-09)."

## Section 4: Complementary Suppression

**R/184 grep finding**: R/184 applies only the primary `sup()` helper (line 99); grep for "complementary", "comp_sup", "residual" returns no matches. R/186 must add the pass.

**Helper**: `apply_complementary_suppression(df, nested, dash)` implementing:
- Rule 0 (only add): never un-suppress; only turns visible cells into "<11" or DASH
- Rule 1 (rate leak): if events or patient_years is "<11" in any row, set rate to DASH (`"—"`)
- Rule 2 (cross-window, only if nested): for events and patient_years, within modality x far, suppress the smallest visible half when one group cell would be recoverable by arithmetic
- Rule 3 (patients): not additive across halves; no complementary rule applies
- Iteration: repeats until no changes (Rule 2 can trigger Rule 1)

**Nesting check**: computed from data (annual == H1 + H2 for visible rows); drives Rule 2.

**Four fixtures** (stopifnot, run before real data):
- (a) Rule 2: H2 suppressed when back-calculable from annual - H1
- (b) Rule 1: rate set to DASH when events is "<11"
- (c) Rule 0: no-suppression table comes back identical
- (d) nested=FALSE: Rule 2 does not fire

**Applied**: to primary_tbl (years 2+) and secondary_tbl (all years) separately.

## Section 5: Annual Match Check

Re-reads the annual block from the pinned workbook after the complementary pass. Asserts cell by cell over patients/patient_years/events/rate: each output cell either equals the R/184 value exactly (character comparison) or was changed to "<11"/DASH by the pass. stop() on first mismatch. Messages count of identical cells and added-suppression cells.

## Section 6: Output Workbook Structure

Sheets in order (KEY leftmost):
1. **KEY**: Parameter/Value table with run metadata, pin path and pinned flag, biannual definition (D-186-01), rate unit, rate unit note (D-09), suppression note (D-06), period values, nesting check results and row counts, cells-changed counts per column per table, annual match check result, source note. UF_BLUE header row.
2. **Primary**: years 2+ — annual + biannual, one row per modality x far x window x half. UF_ORANGE section header, UF_BLUE column header.
3. **Secondary**: all-years — same grain. UF_ORANGE section header, UF_BLUE column header.

Team-facing column names in output: `patients`, `patient_years`, `events`, `rate`, `rate_unit` (no `_sup` suffix in output tables).

**Output path**: `output/survivorship_rate_granularity_<YYYYMMDD>.xlsx`
**R186_OUTPUT pin**: messaged at end of script for Phase 188.

## Task 5: HiPerGator Run Results (2026-10-22)

**(a) Fixtures:** All four PASSED.

**(b) Output:** `/blue/erin.mobley-hl.bcu/insurance_investigation/output/survivorship_rate_granularity_20261022.xlsx`

**(c) Row counts and nesting:**
- primary_tbl: 84 rows. Key unique: OK.
- Nesting check (primary): 27 testable rows; 27 matched (annual = H1+H2). nested=TRUE
- Primary suppression pass cells changed: events=0, patient_years=0, rate=0
- secondary_pre: 84 rows. nested_all=TRUE
- Secondary suppression pass cells changed: events=1, patient_years=0, rate=1

**(d) Annual match check:** `[R/186] annual cells match R/184: 112 identical, 0 added suppression`

**Schema probe:** `.planning/schemas/186_schema_20261022.md` written and copied to Windows repo.

**Visual check:** KEY is leftmost tab. No rate shown next to a suppressed cell (secondary had 1 event cell suppressed; corresponding rate also suppressed — Rule 1 fired correctly on second pass).

**RATE-02 satisfied:** biannual = every 6 months (D-186-01); 84 rows in Primary = 28 annual + 56 biannual (14 modalities x 2 far x 2 halves).
**RATE-03 satisfied:** single team table with team-facing columns, KEY sheet leftmost, UF colours, complementary suppression applied.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Bug] Trailing blank-named columns from xlsx caused dplyr error**
- **Found during:** Task 5 (HiPerGator run)
- **Issue:** `openxlsx::read.xlsx(..., colNames=FALSE)` on the Rates sheet produced trailing columns with blank names (e.g., `X9`, `X10`) when the column-name row had fewer non-blank entries than the raw sheet width. After `names(data_rows) <- col_names`, the blank entries became empty strings, causing a dplyr error on `dplyr::across(dplyr::everything(), as.character)` or downstream column selection.
- **Fix:** Added a drop of blank-named columns after name assignment in `read_rates_block`: `data_rows <- data_rows[, nzchar(trimws(names(data_rows))), drop=FALSE]`
- **Files modified:** R/186_survivorship_rate_granularity.R
- **Commit:** 95aab6a

## Known Stubs

None — no hardcoded empty values or placeholder data in the output path. All values read at run time from the pinned workbook.

## Self-Check: PASSED

- R/186_survivorship_rate_granularity.R created (722 lines, > 150 minimum)
- Commit 08d4f05: Tasks 0-4 script
- Commit 95aab6a: Rule 3 blank-column bug fix (applied on HiPerGator during Task 5 run)
- HiPerGator run: all fixtures PASSED, 0 mismatches in annual match check, output written
- Schema probe: .planning/schemas/186_schema_20261022.md present
- Visual check: KEY leftmost, no rate shown next to suppressed count
