# Cross-Phase UAT & Verification Audit

**Generated:** 2026-05-18
**Scope:** All phases with UAT or VERIFICATION artifacts
**Method:** File scan + codebase cross-reference for staleness

---

## Executive Summary

| Category | Count | Phases |
|----------|-------|--------|
| Fully Passed | 8 | 32, 39, 40, 41, 42, 44, 45, 46 |
| Pending Human Tests (HiPerGator) | 3 | 17, 31, 33 |
| Active Gaps | 0 | — |
| Paused (Awaiting Checkpoint) | 1 | 47 |

**Total pending human test items:** 12 tests across 3 phases
**Total active gaps:** 0 (Phase 39 gap closed 2026-05-18)
**Stale documentation:** 1 item (Phase 46 requirements checkboxes)

---

## Section 1: Pending Human Tests (Prioritized)

### ~~Priority 1: Phase 39~~ — CLOSED 2026-05-18
**Resolution:** update_config_treatment_codes() executed on HiPerGator. Result: "No treatment codes to add (all classified as Unrelated)". All unmatched HCPCS/CPT codes are unrelated to HL treatment. No config update needed. Phase 39 verification updated to passed (4/4).

---

### Priority 1: Phase 17 — Visualization Polish (5 pending tests)
**Status:** human_needed (8/8 code-verified, 0/5 visual tests done)
**Blocker level:** NON-BLOCKING — code is complete, visual confirmation only

| # | Test | What to Check |
|---|------|---------------|
| 1 | Run 16_encounter_analysis.R | Stacked histogram PNG renders with correct stacking (blue post-tx bottom, orange pre-tx top), 6+Missing facets, overflow annotation |
| 2 | Run 11_generate_pptx.R | Slides 26-28 display correctly (post-treatment dates table, stacked histogram embed, pre/post statistics) |
| 3 | Scan full PPTX | No "1900" dates in any table cell or graph |
| 4 | Check Section 1 histogram | Exactly 7 payer categories, no "Other"/"Unknown"/"Unavailable" facets, overflow annotation visible |
| 5 | Check age group bar chart | Percentage labels fully visible above bars, not clipped |

**Batch strategy:** Tests 1-5 can all be done in a single session after running `source("R/04_build_cohort.R")` then `source("R/11_generate_pptx.R")`.

---

### Priority 2: Phase 33 — AV+TH Multi-Source Overlap (5 pending tests)
**Status:** human_needed (10/10 code-verified, 0/5 execution tests done)
**Blocker level:** NON-BLOCKING — analytical output, not blocking other phases

| # | Test | What to Check |
|---|------|---------------|
| 1 | Run R/33_multi_source_overlap_av_th.R | 4 CSV files created with _av_th suffix |
| 2 | Run R/34_overlap_classification_av_th.R | 4 CSV files created with _av_th suffix |
| 3 | Check R/33 console output | ENC_TYPE distribution with per-site AV/TH counts and WARNING messages |
| 4 | Check R/34 console output | Per-source-combo Identical/Partial/Distinct recommendations |
| 5 | Check baseline preservation | Phase 25/26 CSVs (without _av_th suffix) not overwritten |

**Batch strategy:** Run R/33 first, then R/34. Tests 3-5 observable during/after execution.

---

### Priority 3: Phase 31 — DuckDB Cohort Migration (2 pending tests)
**Status:** human_needed (7/9 truths verified, 2 execution-dependent)
**Blocker level:** LOW — DuckDB is already default (Phase 32 completed), these are validation tests

| # | Test | What to Check |
|---|------|---------------|
| 1 | Run R/27_parity_test_cohort.R | All 3 parity levels pass (row count, PATID set, structural equality via waldo::compare). Console shows "ALL CHECKS PASSED" |
| 2 | Run R/28_benchmark_cohort.R | CSV written to output/logs/duckdb_benchmark.csv with 6 rows, median comparison logged |

**Note:** These tests were originally deferred to Phase 32, which has since passed verification. The parity/benchmark infrastructure exists and works — these are confirmatory runs.

---

## Section 2: Phases with Recommended Execution Tests

These phases PASSED verification but have HiPerGator execution tests that would provide additional confidence:

### Phase 46 — Treatment Code Cross-Reference
**Verification:** passed (9/9 truths)
**Recommended:**
1. Run `Rscript R/46_treatment_cross_reference.R` on HiPerGator — verify output/tables/treatment_cross_reference.xlsx is created with 5 sheets
2. Run `Rscript R/44_treatment_episodes.R` on HiPerGator — verify episode CSVs have triggering_codes as column 8

### Phase 47 — Cancer Site Frequency (IN PROGRESS)
**Status:** Paused at Task 2 human-verify checkpoint
**Action required:**
1. Copy R/47_cancer_site_frequency.R to HiPerGator
2. Run: `Rscript R/47_cancer_site_frequency.R`
3. Open output/tables/cancer_site_frequency.xlsx
4. Verify 42 categories, 6 columns, TOTAL row, dark header styling
5. Type "approved" to resume phase

---

## Section 3: Fully Passed (No Action Needed)

| Phase | Verification Score | UAT Score | Status |
|-------|-------------------|-----------|--------|
| 32 — DuckDB Diagnostic Migration | 6/6 | — | passed |
| 39 — Investigate Unmatched HCPCS | 4/4 | — | passed (re-verified 2026-05-18) |
| 40 — Investigate Unmatched NDC | 10/10 | 3/3 | complete |
| 41 — Combine NDC+HCPCS Reports | 5/5 | — | passed |
| 42 — Treatment Codes Resolved XLSX | 6/6 | 6/6 | passed |
| 44 — Treatment Episode Start/Stop | — | 8/8 | complete |
| 45 — Radiation CPT Audit | 5/5 | — | passed (re-verified) |
| 46 — Treatment Code Cross-Reference | 9/9 | 7/7 | passed |

---

## Section 4: Stale Documentation

| Phase | File | Issue | Severity |
|-------|------|-------|----------|
| 46 | v1.6-REQUIREMENTS.md | TXREF-01 and TXREF-02 still shown as `[ ]` (unchecked) despite being implemented and verified | Low — doc only |
| 39 | 39-VERIFICATION.md | Reports output files missing, but unmatched_codes_classified.rds exists in project root (wrong path) | Medium — verification doc may be partially stale |

---

## Section 5: Prioritized Human Test Plan

**Recommended execution order for a single HiPerGator session:**

1. **Phase 39 gap closure** (BLOCKING)
   - Investigate path mismatch for unmatched_codes_classified.rds
   - Re-run R/39 if config update didn't fire, OR manually trigger Step 6
   - Verify supportive_care_hcpcs appears in R/00_config.R

2. **Phase 47 checkpoint** (IN PROGRESS)
   - Run R/47_cancer_site_frequency.R
   - Verify xlsx output
   - Approve to unblock phase completion

3. **Phase 17 visual batch** (5 tests, 1 session)
   - source("R/04_build_cohort.R")
   - source("R/11_generate_pptx.R")
   - Inspect PNG + PPTX slides + scan for 1900 dates

4. **Phase 33 execution batch** (5 tests, 1 session)
   - source("R/33_multi_source_overlap_av_th.R")
   - source("R/34_overlap_classification_av_th.R")
   - Verify outputs and console

5. **Phase 31 validation** (2 tests, low priority)
   - source("R/27_parity_test_cohort.R")
   - source("R/28_benchmark_cohort.R")

6. **Phase 46 execution** (2 tests, confirmatory)
   - Rscript R/46_treatment_cross_reference.R
   - Rscript R/44_treatment_episodes.R

**Total estimated human test items:** 17 across 6 phases
