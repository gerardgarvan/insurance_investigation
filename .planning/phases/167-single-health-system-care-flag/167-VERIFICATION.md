---
phase: 167-single-health-system-care-flag
verified: 2026-10-08T00:00:00Z
status: passed
score: 5/5 must-haves verified
re_verification: false
---

# Phase 167: Single-Health-System Care Flag Verification Report

**Phase Goal:** A patient-level binary `single_source_care` identifies patients whose care occurred entirely within one health system (SOURCE). Deliver Excel workbook, joinable CSV, and internal RDS.
**Verified:** 2026-10-08
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `single_source_care` binary flag (0/1/NA) computed in DuckDB from ENCOUNTER.SOURCE | VERIFIED | R/169 lines 131-146: SQL with NULLIF/UPPER/TRIM normalisation; `COUNT(DISTINCT src)` in DuckDB; case_when at lines 65-69 produces 0L/1L/NA_integer_ |
| 2 | Two windows delivered as separate columns (whole-record + post-HL-anchor) | VERIFIED | build_single_source_result() returns both `single_source_care` and `single_source_care_post`; post flag from separate sql_post query (lines 160-182); case_when at lines 71-76 |
| 3 | Joinable CSV and internal RDS written | VERIFIED | Lines 257-280: readr::write_csv to output/internal/single_source_care_{run_date}.csv; saveRDS for .rds and _parts.rds; all under output/internal/ |
| 4 | Excel workbook delivered (KEY, A_summary, B_post_anchor, QC sheets) | VERIFIED | SECTIONS 4-5 (lines 282-902): openxlsx workbook; four sheets in correct order; saved to output/single_source_care_{run_date}.xlsx; HiPerGator run confirmed output on 2026-10-08 |
| 5 | Blank/NA SOURCE patients flagged and counted in QC, not coerced | VERIFIED | any_blank_source via MAX(CASE WHEN src IS NULL) in SQL (line 143); QC sheet block 2 (lines 747-773) reports n_any_blank and n_all_blank_w; sensitivity block (lines 812-854) shows alternate counting |

**Score:** 5/5 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `R/169_single_source_care.R` | Main script — flags, exports, workbook | VERIFIED | 913 lines; fully implemented SECTIONS 1B-5; no functional stubs |
| `tests/testthat/test-169-single-source-care.R` | 6 test_that blocks covering SRC-01/02/03 | VERIFIED | 172 lines; 6 test_that blocks; all three requirement IDs exercised |
| `R/39_run_all_investigations.R` | R/169 registered in dependency order | VERIFIED | Line 236: `"R/169_single_source_care.R"` inserted after R/168 with descriptive comment |
| `R/88_smoke_test_comprehensive.R` | SMOKE-167-01 section with 10 checks | VERIFIED | Lines 6121-6260: SECTION 15ap with all 10 checks; structural + output-gated checks present |
| `slurm/167_single_source_care.sbatch` | SLURM wrapper for HiPerGator | VERIFIED | Present; correct job name, account, 4 CPUs, 16gb, 02:00:00; runs tests then R/169 then R/88; `module load R/4.5`; `set -e` |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| R/169 | DuckDB ENCOUNTER | duckdb_register + SQL JOIN | WIRED | `duckdb_register(pcornet_con, "cohort_ids", ...)` then SQL JOIN cohort_ids; unregistered in cleanup |
| R/169 | get_hl_any_dx_ids() | Direct call | WIRED | Line 113: `anchors <- get_hl_any_dx_ids()` |
| R/169 | output/internal/\*.csv + \*.rds | readr::write_csv + saveRDS | WIRED | Lines 257-280; paths use CONFIG$output_dir + "internal" |
| R/169 | output/\*.xlsx | openxlsx::saveWorkbook | WIRED | Line 902: saves to CONFIG$output_dir root (not internal) |
| R/39 | R/169 | Script path string | WIRED | Line 236 confirmed by grep |
| R/88 | R/169 | SMOKE-167-01 checks | WIRED | 10-check section confirmed; checks reference R/169 by path |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| R/169 (flag columns) | whole_raw, post_raw | DuckDB SQL queries against ENCOUNTER table | Yes — two SQL queries with GROUP BY; result passed to build_single_source_result() | FLOWING |
| A_summary sheet | result (from build_single_source_result) | DuckDB + anchors from get_hl_any_dx_ids() | Yes — HiPerGator run reported 9,331 cohort patients, 5,640 single-source | FLOWING |
| QC sheet | n_na_admit, n_any_blank, n_all_blank_w | sql_na_admit DuckDB query + result columns | Yes — computed from live query results, not hardcoded | FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| R/169 file exists and is non-trivial | File read: 913 lines | 913 lines, complete SECTIONS 1B-5 | PASS |
| build_single_source_result defined | Grep pattern in file | Found at line 48 | PASS |
| openxlsx used (not openxlsx2) | Grep for openxlsx | `library(openxlsx)` at line 286; openxlsx2 absent | PASS |
| All four sheet literals present | Grep for "KEY", "A_summary", "B_post_anchor", "QC" | All four present in addWorksheet calls | PASS |
| HiPerGator run completed | 167-02-SUMMARY.md Task 3 | 9,331 patients; CSV, RDS, parts RDS, xlsx all written | PASS |
| All 4 commits verified | git log | b795e1f, 3d6ee3e, 085158f, 589244d all present | PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| SRC-01 | 167-01 | Patient-level binary `single_source_care` (1 = n_distinct SOURCE == 1) + `n_sources`; computed in DuckDB; ENCOUNTER only | SATISFIED | DuckDB SQL with COUNT(DISTINCT src); build_single_source_result() produces integer 0L/1L/NA_integer_; `n_sources` column present in output |
| SRC-02 | 167-01 | Two windows as separate columns: whole-record and post-HL-anchor; joinable on ID | SATISFIED | Both `single_source_care` and `single_source_care_post` columns in result; CSV output joinable on ID; anchors from get_hl_any_dx_ids() same as Phases 165/166 |
| SRC-03 | 167-01 | Patients with NA/blank SOURCE flagged and counted in QC; not coerced | SATISFIED | any_blank_source column computed; QC sheet blocks 2 and 4 report blank patient counts; SENSITIVITY block shows alternate treatment |

No orphaned requirements: REQUIREMENTS.md traceability table shows SRC-01, SRC-02, SRC-03 all mapped to Phase 167, all marked Complete.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| None | — | No TODOs, placeholders, hardcoded empty returns, or stub implementations detected | — | — |

Checks performed:
- No `TODO|FIXME|PLACEHOLDER` comments in R/169
- No `return null` / `return {}` / `return []` patterns
- No `quit()` call (SUMMARY confirms only appears in a comment documenting its absence)
- No `openxlsx2` (correct `openxlsx` used, matching project convention from R/168)
- `single_source_care_post` case_when precedes n_sources_post coalesce (Pitfall 2 correctly ordered)
- All output paths under output/internal/ for patient-level files; aggregate xlsx in output/ root

### Human Verification Required

No items require human verification. The HiPerGator run (Task 3 of Plan 02) was completed on 2026-10-08 with outputs approved by the user (Task 4). The following were confirmed by that run:

- 9,331 cohort patients processed
- 5,640 single-source (whole record, ~60%)
- 0 blank SOURCE patients
- 0 missing ADMIT_DATE encounters
- CSV, RDS, parts RDS written to output/internal/single_source_care_20261008.*
- Workbook written to output/single_source_care_20261008.xlsx

### Gaps Summary

No gaps. All five observable truths verified. All five required artifacts exist, are substantive, and are wired. All three requirement IDs (SRC-01, SRC-02, SRC-03) are satisfied. All four claimed commits exist in git history. No anti-patterns found.

---

_Verified: 2026-10-08_
_Verifier: Claude (gsd-verifier)_
