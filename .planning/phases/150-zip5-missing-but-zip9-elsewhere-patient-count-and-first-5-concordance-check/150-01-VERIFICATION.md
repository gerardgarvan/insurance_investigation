---
phase: 150-zip5-missing-but-zip9-elsewhere-patient-count-and-first-5-concordance-check
plan: 150-01
verified: 2026-09-03T00:00:00Z
status: passed
score: 11/11 must-haves verified
re_verification: false
---

# Phase 150: ZIP5 Backfill Concordance Verification Report

**Phase Goal:** Write and run a read-only diagnostic (R/120_zip5_backfill_concordance.R) that quantifies how reliably ZIP9 can backfill missing ZIP5 values for patients in LDS_ADDRESS_HISTORY. Report 5 patient-level counts, concordance rate, and supplementary record-level agreement figure.
**Verified:** 2026-09-03
**Status:** PASSED
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | R/120 loads LDS_ADDRESS_HISTORY and produces 5 patient-level counts + concordance rate via dplyr, printed to console | VERIFIED | HiPerGator output in SUMMARY shows all counts (1)(2)(2a)(2b)(3a)(3b)(3c)(4) and rate 77.7% |
| 2 | Patient identifier column is ID (not PATID); script errors clearly if ID is absent | VERIFIED | `grep -c "PATID" R/120` = 0; `required_cols <- c("ID", ...)` with explicit stop on mismatch at line 186-189 |
| 3 | Modal ZIP per patient computed with explicit group_by(pid) so one row returned per patient | VERIFIED | `grep -c "group_by(pid)"` = 2 occurrences in modal_by_patient(); stopifnot at lines 164-166 asserts no duplicated pids |
| 4 | Runtime invariant asserts n_concordant + n_discordant + n_no_zip5_elsewhere == n_zip9_available | VERIFIED | stopifnot at line 194; no stopifnot fired on HiPerGator run |
| 5 | Runtime invariant asserts modal ZIP9 table has exactly one row per group-2 patient | VERIFIED | stopifnot at lines 164-165 (nrow == n_zip9_available and !any(duplicated(pid))) |
| 6 | Concordance rate reported with measured interpretation stating modal-comparison caveat | VERIFIED | SUMMARY output (4): "This compares patient-level modal values across all records, so a change of address within the study period registers as discordance" |
| 7 | Supplementary record-level same-record agreement figure printed as output (5) | VERIFIED | SUMMARY output (5): 19,727 of 19,739 records agree (99.9%) across 6,472 patients |
| 8 | Script registered in R/39_run_all_investigations.R investigation_scripts vector | VERIFIED | Line 222: `"R/120_zip5_backfill_concordance.R"` present in vector |
| 9 | Script has smoke-test entry in R/88_smoke_test_comprehensive.R Section 15af | VERIFIED | Lines 5126-5185: Section 15af block with 9 checks confirmed |
| 10 | Script appears in R/SCRIPT_INDEX.md | VERIFIED | Line 164 of SCRIPT_INDEX.md has row for script 120 with Phase 150 |
| 11 | HiPerGator run produces all counts and both rates with no stopifnot errors | VERIFIED | Full console output pasted in SUMMARY; "=== 120 done ===" reached; both stopifnot assertions passed |

**Score:** 11/11 truths verified

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `R/120_zip5_backfill_concordance.R` | Patient-level ZIP5-missing / ZIP9-available concordance diagnostic plus record-level check; min 120 lines | VERIFIED | 239 lines; dplyr + vroom; CONFIG$data_dir; normalize_zip5_raw resolved at runtime; no PATID; no setwd/data.table/read.csv |
| `R/39_run_all_investigations.R` | Registration of script 120 in investigation_scripts vector | VERIFIED | `"R/120_zip5_backfill_concordance.R"` appended at line 222 with comment |
| `R/88_smoke_test_comprehensive.R` | Smoke-test entry for script 120 in Section 15af | VERIFIED | Section 15af present at line 5126; 4 grep matches for the filename |
| `R/SCRIPT_INDEX.md` | Index entry for script 120 | VERIFIED | Full row at line 164 with description and phase reference |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| R/120_zip5_backfill_concordance.R | R/utils/utils_address.R | source via R/00_config.R auto-load; uses normalize_zip5_raw(), normalize_zip9(), is_sentinel_zip5() | VERIFIED | `grep -c "normalize_zip5\|normalize_zip9\|is_sentinel_zip5"` = 11 hits; runtime confirmed `normalize_zip5_raw` resolved and used |
| R/120_zip5_backfill_concordance.R | LDS_ADDRESS_HISTORY_Mailhot_V1.csv | vroom::vroom(file.path(CONFIG$data_dir, ...)) | VERIFIED | `CONFIG$data_dir` present (1 hit); runtime loaded 40,005 rows |

---

### Data-Flow Trace (Level 4)

This is a read-only diagnostic with console output only — no output files, no rendering of dynamic UI. The data-flow is: CSV -> vroom -> dplyr pipeline -> cat() to console. HiPerGator run confirms real data flowed (40,005 rows, 8,953 patients) and all counts were printed. Level 4 is satisfied by the runtime execution evidence in the SUMMARY.

---

### Behavioral Spot-Checks

| Behavior | Evidence | Status |
|----------|----------|--------|
| All 5 patient-level counts printed without error | HiPerGator output shows (1) 1128, (2) 701, (3a) 530, (3b) 152, (3c) 19 | PASS |
| Both runtime invariants passed (no stopifnot fired) | SUMMARY: "Both runtime invariants passed: no stopifnot fired" | PASS |
| Concordance rate printed with interpretation | (4) 77.7% (530/682) with full interpretation paragraph | PASS |
| Record-level check printed as output (5) | 19,727/19,739 records (99.9%) across 6,472 patients | PASS |
| (4) vs (5) divergence noted and interpreted | SUMMARY interpretation section: 22-point gap explained as residential mobility, not data quality failure | PASS |

Note: Cannot re-run HiPerGator commands from this environment. All spot-checks verified from SUMMARY output.

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| ZIP5-BACKFILL-01 | 150-01-PLAN.md | Read-only diagnostic quantifying ZIP9 backfill reliability for missing ZIP5 | SATISFIED | R/120 written, run on HiPerGator, all counts and rates reported; no output files written |

---

### Anti-Patterns Found

| File | Pattern | Severity | Impact |
|------|---------|----------|--------|
| None | — | — | — |

Static checks confirmed:
- No `PATID` in R/120 (count = 0)
- No `setwd`, `data.table`, or `read.csv` in R/120
- No hardcoded paths — uses `CONFIG$data_dir` and `file.path()`
- No opaque one-liners — named predicate pattern followed

---

### Human Verification Required

None. This is a purely computational diagnostic with console output. The HiPerGator run serves as the runtime verification. Both invariants passed at runtime, confirming correctness of the grouping logic and bucket exhaustion.

---

### Gaps Summary

No gaps. All 11 truths verified. All 4 artifacts exist and are substantive (239 lines, well above the 120-line minimum). Both key links confirmed via grep and runtime evidence. Registration in all three required files confirmed. HiPerGator run completed successfully with all counts and no errors.

The 22-point divergence between output (4) at 77.7% and output (5) at 99.9% is correctly interpreted in the SUMMARY as expected residential mobility signal, not a data quality problem, and flags the deferred temporal-matching phase as the next step if cross-record imputation is needed.

---

_Verified: 2026-09-03_
_Verifier: Claude (gsd-verifier)_
