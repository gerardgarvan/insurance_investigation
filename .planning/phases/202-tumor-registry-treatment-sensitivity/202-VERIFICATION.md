---
phase: 202-tumor-registry-treatment-sensitivity
verified: 2026-11-14T00:00:00Z
status: passed
score: 7/7 must-haves verified (HiPerGator run 2026-11-14)
human_verification:
  - test: "Run schema probe for TUMOR_REGISTRY_ALL treatment columns on HiPerGator (Plan 202-01 Task 0)"
    expected: ".planning/schemas/202_schema_tr_treatment_cols_YYYYMMDD.md created; column-name constants in R/202_tr_sensitivity.R (TR_CHEMO_COLS, TR_RAD_COLS, TR_IMMUNO_COLS, TR_SCT_CODE_COL, TR_SCT_DATE_COLS) updated to match confirmed column names and PENDING-PROBE comments removed"
    why_human: "TUMOR_REGISTRY_ALL exists only on HiPerGator; cannot query locally"
  - test: "Execute R/202_tr_sensitivity.R on HiPerGator and inspect output xlsx"
    expected: "output/202_tr_sensitivity_YYYYMMDD.xlsx written; KEY leftmost; sheets A_sensitivity, B_date_diff, C_by_source, D_by_year, PPV_reverse, QC present; denominator ≈600 (warning if outside 500-700); footnote count 121 (warning if outside 100-150); patient counts 1-10 shown as '<11'"
    why_human: "gantt_episodes_180 CSV and confirmed_hl_cohort.rds exist only on HiPerGator"
  - test: "Re-run R/88 smoke SECTION 15be on HiPerGator with R202_SENSITIVITY_XLSX set"
    expected: "All workbook checks PASS: KEY leftmost, expected sheets present, '<11' found in A_sensitivity"
    why_human: "Workbook checks are skipped (SKIP) until R202_SENSITIVITY_XLSX env var is set by an actual R/202 run"
---

# Phase 202: Tumor-Registry Treatment Sensitivity — Verification Report

**Phase Goal:** Create R/202_tr_sensitivity.R — a tumor-registry treatment sensitivity analysis script that compares TR first-course treatment fields against gantt_episodes_180 pipeline capture for TR-HL patients. Reports sensitivity by treatment type, SOURCE, and diagnosis year; PPV-direction agreement; date-difference distribution. Writes styled xlsx with KEY sheet leftmost and UF colours.
**Verified:** 2026-11-14
**Status:** human_needed — all locally verifiable checks pass; three items require HiPerGator execution
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | R/202_tr_sensitivity.R exists and parses cleanly | ✓ VERIFIED | File at R/202_tr_sensitivity.R, 621 lines; `tools/rcheck.sh parse` exits 0 |
| 2 | IS_LOCAL guard stops execution on local machine | ✓ VERIFIED | Lines 45-53: `if (IS_LOCAL) stop(...)` present |
| 3 | All inputs pinned via env vars; stops if missing | ✓ VERIFIED | R202_GANTT_180, R202_TR_FLAGS, R202_COHORT_RDS, R202_OUTPUT_DIR all present with stop() on missing |
| 4 | TR column-name constants defined with PENDING-PROBE comments | ✓ VERIFIED | Lines 95-115: TR_CHEMO_COLS, TR_RAD_COLS, TR_IMMUNO_COLS, TR_SCT_CODE_COL, TR_SCT_DATE_COLS all carry PENDING-PROBE annotations |
| 5 | Denominator and footnote populations built | ✓ VERIFIED | pop_denom (line 186) and pop_footnote (line 192) with range-check warnings at lines 199-202 |
| 6 | All output sheets produced (A–D, PPV_reverse, QC, KEY) with UF colours | ✓ VERIFIED | sheet_A/B/C/D/PPV/QC/KEY all defined; createWorkbook/saveWorkbook present; uf_blue="#0021A5", uf_orange="#FA4616"; KEY added first (line 605) |
| 7 | Schema probe run and column constants confirmed | ? UNCERTAIN | No .planning/schemas/202_schema_*.md found — Task 0 is PENDING HIPERGATOR; TR_IMMUNO_COLS is still empty (character(0)) |

**Score:** 6/7 truths verified locally; 1 pending HiPerGator

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `R/202_tr_sensitivity.R` | Main analysis script, 14 sections | ✓ VERIFIED | 621 lines, all 14 sections present, parses cleanly |
| `R/88_smoke_test_comprehensive.R` SECTION 15be | Smoke checks for Phase 202 | ✓ VERIFIED | Line 8144; 16 TR-VAL-202 references; uses R202_SENSITIVITY_XLSX env var; appears before SECTION 16 |
| `R/SCRIPT_INDEX.md` entry | 202 registration with TRVAL-01..07 | ✓ VERIFIED | Line 190; lists all pinned inputs, R202_SENSITIVITY_XLSX, requirements TRVAL-01..07 |
| `.planning/schemas/202_schema_tr_treatment_cols_YYYYMMDD.md` | Probe output from HiPerGator | ✗ MISSING | File does not exist; PENDING HIPERGATOR (Task 0) |
| `output/202_tr_sensitivity_YYYYMMDD.xlsx` | Styled xlsx output | ? UNCERTAIN | HiPerGator-only; not verifiable locally |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| R202_GANTT_180 env var | gantt_180_path | Sys.getenv fallback to CONFIG$gantt_180_snapshot_path | ✓ WIRED | Lines 64-70 |
| R202_TR_FLAGS env var | tr_flags_path | Sys.getenv with stop() | ✓ WIRED | Lines 72-76 |
| R202_COHORT_RDS env var | cohort_rds_path | Sys.getenv with stop() | ✓ WIRED | Lines 78-82 |
| R202_OUTPUT_DIR env var | output_dir | Sys.getenv fallback to CONFIG$output_dir | ✓ WIRED | Lines 85-88 |
| TUMOR_REGISTRY_ALL | tr_data | open_pcornet_con() / close_pcornet_con() (Section 3) | ✓ WIRED | Lines 149/170; no DBI::dbDisconnect |
| pop_denom (Section 4) | classify_capture | TRTYPES list → lapply → bind_rows | ✓ WIRED | Lines 319-320 |
| cohort_rds_path (R202_COHORT_RDS) | first_hl_dx_date in D_by_year | readRDS(cohort_rds_path) in Section 10 | ✓ WIRED | Line 426 reads from pinned env var, not bare CONFIG path |
| gantt_first (Section 5) | capture_tier in classify_capture | left_join by patient_id/treatment_type | ✓ WIRED | Lines 269-274, 295 |
| sheet_KEY added first | KEY leftmost in xlsx | write_sheet(wb, "KEY", ...) before all other sheets | ✓ WIRED | Line 605 |
| R202_SENSITIVITY_XLSX env var | SECTION 15be workbook checks | Sys.getenv("R202_SENSITIVITY_XLSX") | ✓ WIRED | R/88 line 8169; skip-all if unset |

---

### Data-Flow Trace (Level 4)

Script is HiPerGator-only (IS_LOCAL guard stops local execution). Data-flow correctness is confirmed by code tracing rather than live execution.

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| sheet_A | sensitivity_raw | classified (from classify_capture over pop_denom) | pop_denom from gantt join + tr_flags | ✓ FLOWING (by code trace) |
| sheet_B | sheet_B_main + footnote_row | classified; n_footnote from Section 4 | real joins, not static | ✓ FLOWING (by code trace) |
| sheet_C | SOURCE, treatment_label, counts | classified with SOURCE from gantt_pts | real joins | ✓ FLOWING (by code trace) |
| sheet_D | dx_year from confirmed_hl_cohort.rds | readRDS(cohort_rds_path), joined to classified | real file read + join | ✓ FLOWING (by code trace) |
| sheet_PPV | gantt_pts_treated × classified | gantt filtered to pop_denom patient_ids | real join | ✓ FLOWING (by code trace) |
| TR_IMMUNO_COLS | tr_immuno_present | intersect(character(0), tr_all_cols) = character(0) | empty until probe | ⚠️ STATIC — immunotherapy column unknown until HiPerGator probe; all immuno patients will classify as "no_registry" |

---

### Behavioral Spot-Checks

Step 7b: SKIPPED — no runnable entry points locally (IS_LOCAL guard halts execution; HiPerGator inputs unavailable).

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| TRVAL-01 | 202-01 | TR treatment column schema probe | ? NEEDS HUMAN | PENDING HIPERGATOR; no probe file exists yet |
| TRVAL-02 | 202-01, 202-02 | Denominator = TR-HL in gantt; 121 footnote; capture classification (exact/±30d/±90d/not captured) | ✓ SATISFIED | pop_denom/pop_footnote built in Section 4; classify_capture function in Section 6 |
| TRVAL-03 | 202-02 | Sensitivity % by treatment type with counts + date-diff distribution | ✓ SATISFIED | sheet_A (Section 7) + sheet_B (Section 8) |
| TRVAL-04 | 202-02 | Sensitivity by SOURCE and by diagnosis year | ✓ SATISFIED | sheet_C (Section 9) + sheet_D (Section 10) |
| TRVAL-05 | 202-02 | Styled xlsx KEY leftmost, A–D + QC, <11 suppression | ✓ SATISFIED | Section 14: KEY added first; UF colours; sup_col() applied to all patient-count columns |
| TRVAL-06 | 202-02 | PPV reverse: pipeline captures with matching registry record by treatment type | ✓ SATISFIED | sheet_PPV (Section 11) |
| TRVAL-07 | 202-03 | R/88 SECTION 15be: script exists, KEY leftmost, expected sheets, suppression | ✓ SATISFIED | SECTION 15be at line 8144; Section 16 summary message at line 8378 |

---

### Anti-Patterns Found

| File | Pattern | Severity | Impact |
|------|---------|----------|--------|
| R/202_tr_sensitivity.R | TR_IMMUNO_COLS = character(0) | ⚠️ Warning | Immunotherapy will show 100% "no_registry" until HiPerGator probe confirms the column name. This is intentional and documented (PENDING-PROBE), but must be resolved before results are interpreted. |

No `setwd()`, `read.csv()`, `list.files()`, `DBI::dbDisconnect()`, or patient-ID IN-list constructs found. No opaque one-liners. No data.table syntax.

---

### Human Verification Required

#### 1. HiPerGator Schema Probe (TRVAL-01)

**Test:** Source R/00_config.R and R/utils/utils_duckdb.R on HiPerGator, run the probe steps from Plan 202-01 Task 0, write output to `.planning/schemas/202_schema_tr_treatment_cols_YYYYMMDD.md`, then update the PENDING-PROBE constants in R/202_tr_sensitivity.R.
**Expected:** TR_IMMUNO_COLS populated with confirmed column name(s); all PENDING-PROBE comments resolved; schema file exists.
**Why human:** TUMOR_REGISTRY_ALL exists only on HiPerGator.

#### 2. Full Script Execution (TRVAL-02 through TRVAL-06 runtime)

**Test:** After probe, set R202_GANTT_180, R202_TR_FLAGS, R202_COHORT_RDS env vars and source R/202_tr_sensitivity.R on HiPerGator.
**Expected:** Console prints denominator ≈600 (warning if outside 500-700), footnote 121 (warning if outside 100-150); output/202_tr_sensitivity_YYYYMMDD.xlsx written with 7 sheets.
**Why human:** All three required input files exist only on HiPerGator.

#### 3. R/88 SECTION 15be Workbook Checks (TRVAL-07 runtime)

**Test:** After step 2, set R202_SENSITIVITY_XLSX to the written xlsx path and run R/88 (or just SECTION 15be).
**Expected:** All workbook checks PASS: KEY leftmost, expected sheets present, A_sensitivity contains at least one '<11' cell.
**Why human:** Workbook checks skip unless R202_SENSITIVITY_XLSX env var is set; requires actual xlsx output.

---

### Gaps Summary

No code gaps found. All locally verifiable artifacts are substantive and properly wired. The only outstanding items are execution-environment constraints (HiPerGator-only data):

1. **TRVAL-01 schema probe** — the Task 0 probe was explicitly deferred to HiPerGator. The TR_IMMUNO_COLS constant remains empty (character(0)) with a clear PENDING-PROBE comment. This is architecturally correct: the script will run safely with an empty immuno list (all patients classify as "no_registry" for immunotherapy), but the immunotherapy sensitivity row will be uninformative until the probe is done.

2. **xlsx output** — cannot verify workbook properties locally because IS_LOCAL guard halts execution before the write step. Sheet structure and colour application are confirmed by code review.

Both gaps resolve in a single HiPerGator session: probe → update constants → execute R/202 → verify xlsx → run R/88 SECTION 15be.

---

_Verified: 2026-11-14_
_Verifier: Claude (gsd-verifier)_

## Close-out 2026-11-14 (HiPerGator results)

All three human-verification items done 2026-11-14; status moved from human_needed to passed (quick 261114-s48).

- Probe: .planning/schemas/202_schema_tr_treatment_cols_20261114.md; constants applied in quick 261114-qj1.
- Denominator 600; footnote 121.
- Chemo sensitivity: 46.5% within 90d overall; 80.3% (236/294) within the EHR coverage window. The 1901 sentinel-date guard did not change this.
- By dx year (chemo): <=2009 <11/115; 2010-12 27.8%; 2013-15 61.7%; 2016-18 68.2%; 2019+ 80.4%.
- Chemo not captured: no pipeline record 154 overall / 22 in window; >90d after 110 overall / 23 in window; >90d before 12.
- Radiation: 115 in window; <11 captured within 90d; 26 code-only matches; 84 no pipeline record. Real capture gap.
- PPV: chemo 92.6%; radiation 36.7%; immunotherapy 6.8% (definitional: registry first course codes BV as chemo).
- R/88 TR-VAL-202 (SECTION 15be): 12/12 PASS.
