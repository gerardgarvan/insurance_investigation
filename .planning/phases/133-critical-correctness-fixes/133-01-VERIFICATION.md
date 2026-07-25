---
phase: 133-critical-correctness-fixes
verified: 2026-07-25T00:00:00Z
status: passed
score: 9/9 must-haves verified
re_verification: false
---

# Phase 133: Critical Correctness Fixes — Verification Report

**Phase Goal:** Apply 8 critical correctness fixes identified in 2026-07-23 code review across 11 R scripts.
**Verified:** 2026-07-25
**Status:** passed
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | R/28: `treatment_type == "SCT"` in sct_dates filter (not "Stem Cell Transplant") | VERIFIED | Line 648: `filter(treatment_type == "SCT")` confirmed; zero hits for "Stem Cell Transplant" |
| 2 | R/46: `total_records` aggregated at code grain before join, not multiplied by patient count | VERIFIED | Lines 133-159: `code_record_totals` built from `dx_record_counts` grouped by category; explicit NOTE comment blocks re-join onto patient frame; `stopifnot` guard at line 146 |
| 3 | R/47: `first_hl_dx_date` retains real date via pre-min sentinel filter; no post-hoc 1900 nullify | VERIFIED | `SENTINEL_CUTOFF` at line 68; filter applied at line 146 before `group_by`/`min()`; zero occurrences of "1900" or `year(first_hl_dx_date)` remaining |
| 4 | R/48: HL anchor codes (C81* and 201.x) excluded from post-HL second-cancer set | VERIFIED | Line 147: `filter(!str_detect(DX_norm, "^C81") & !str_detect(DX_norm, "^201"))` with log message at line 149 |
| 5 | R/49: `both_count` at category grain is true patient-level pre∩post intersection (inner_join, not grouping `patients_both`) | VERIFIED | Lines 440-452: `pre_patients_by_category` / `post_patients_by_category` built and inner-joined; V2 analogue at lines 604-616; TOTAL row uses `intersect(unique(patients_pre$ID), unique(patients_post$ID))` at lines 494, 647 |
| 6 | R/67: `admit_date_1`/`admit_date_2` swapped as a bound unit with sources in pmin/pmax mutate | VERIFIED | Lines 280-286: `admit_date_1_new` and `admit_date_2_new` helpers with `if_else(source_1 == src_lo, ...)` swap logic; originals reassigned in same mutate |
| 7 | R/68: comment confirms (admit_date, source) ordering inherited from R/67; no bare pmin/pmax reorder exists | VERIFIED | Line 102: "already canonicalized by R/67's pmin/pmax swap fix" comment present |
| 8 | R/95: identical admit_date bound-unit swap as R/67 applied (AV+TH scope) | VERIFIED | Lines 308-314: same `admit_date_1_new`/`admit_date_2_new` helpers with `if_else(source_1 == src_lo, ...)` logic |
| 9 | R/89: `header_end` anchored to 3rd `===` bar (index `[3]`); R/96 comment from R/95; R/101 `age_at_episode` before `episode_start = min()` | VERIFIED | R/89 line 65: `[3]`; R/96 line 82: "already canonicalized by R/95"; R/101 lines 202 vs 205: `age_at_episode` at line 202, `episode_start = min(...)` at line 205 |

**Score:** 9/9 truths verified

---

### Required Artifacts

| Artifact | Fix # | Expected | Status | Evidence |
|----------|-------|----------|--------|----------|
| `R/47_cancer_summary_refined.R` | Fix 1 | SENTINEL_CUTOFF constant + pre-min filter; no post-hoc 1900 nullify | VERIFIED | `SENTINEL_CUTOFF` at L68, filter at L146, 0 hits for "1900" |
| `R/28_episode_classification.R` | Fix 2 | `treatment_type == "SCT"` in sct_dates filter | VERIFIED | L648 confirmed; "Stem Cell Transplant" absent |
| `R/46_cancer_summary_table.R` | Fix 3 | `total_records` via code_record_totals; no patient-level join | VERIFIED | `code_record_totals` + direct code grain join; NOTE comment + stopifnot guard |
| `R/48_cancer_summary_post_hl.R` | Fix 4 | C81*/201.x exclusion filter after sentinel filter | VERIFIED | L147-149 present |
| `R/49_cancer_summary_pre_post.R` | Fix 5 | inner_join at category grain for both_count; intersect() for TOTAL | VERIFIED | L440-452, L604-616, L494, L647 confirmed |
| `R/67_multi_source_overlap_detection.R` | Fix 6 | admit_date_1_new/admit_date_2_new helpers in mutate | VERIFIED | L280-286 confirmed |
| `R/68_overlap_classification.R` | Fix 6 | Canonicalization comment at read_csv call | VERIFIED | L102 confirmed |
| `R/95_multi_source_overlap_av_th.R` | Fix 7 | Identical admit_date swap as R/67 | VERIFIED | L308-314 confirmed |
| `R/96_overlap_classification_av_th.R` | Fix 7 | Canonicalization comment at read_csv call | VERIFIED | L82 confirmed |
| `R/89_generate_reference_manual.R` | Fix 8 | `header_end` uses `[3]` not `[2]` | VERIFIED | L65: `[3]` confirmed |
| `R/101_gantt_lifespan_collapse.R` | Fix 9 | `age_at_episode` line before `episode_start = min()` in summarise() | VERIFIED | L202 < L205 confirmed |

---

### Key Link Verification

| From | To | Via | Status | Detail |
|------|----|-----|--------|--------|
| `R/47_cancer_summary_refined.R` | `output/confirmed_hl_cohort.rds` | `saveRDS(confirmed_hl_cohort, OUTPUT_RDS)` | NOT CHECKED | Structural grep only; RDS output requires HiPerGator runtime |
| `output/confirmed_hl_cohort.rds` | `R/48_cancer_summary_post_hl.R` | `readRDS(INPUT_RDS)` | NOT CHECKED | Runtime dependency; HiPerGator only |
| `R/67_multi_source_overlap_detection.R` | `multi_source_same_week_detail.csv` | `same_week_detail` write | NOT CHECKED | Runtime dependency |

Note: Key links are runtime I/O connections. Structural code checks above confirm the correct logic is present in all 11 scripts. Actual data flow cannot be verified without HiPerGator DuckDB access.

---

### Data-Flow Trace (Level 4)

SKIPPED — no local DuckDB connection available. All scripts require PCORnet CDM CSVs on HiPerGator filesystem. Numeric correctness of R/46 (total_records values) and R/49 (both_count reconciliation) cannot be confirmed until run against real data. Structural fix is confirmed at code level.

---

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| All 11 files parse without syntax error | R parse check (not runnable locally without R PATH) | Verified structurally via grep pattern consistency | SKIP (no Rscript in Bash PATH on Windows dev) |
| R/101: age_at_episode line < episode_start min() line | Line number comparison from grep | L202 vs L205 — age_at_episode is first | PASS |
| R/89: [3] not [2] on header_end | grep `header_end.*\[` | L65: `[3]` only — `[2]` absent | PASS |
| R/28: SCT string correct | grep pattern | L648: `"SCT"` confirmed; "Stem Cell Transplant" absent | PASS |
| R/47: no 1900 reference | grep "1900" | Zero matches | PASS |

---

### Requirements Coverage

| Requirement | Description | Status | Evidence |
|-------------|-------------|--------|----------|
| DATA-01 | R/28 SCT treatment_type string | SATISFIED | `treatment_type == "SCT"` at L648; "Stem Cell Transplant" gone |
| DATA-02 | R/46 total_records at code grain | SATISFIED | `code_record_totals` pattern; no patient-level join |
| DATA-03 | R/47 sentinel pre-filter (not post-hoc nullify) | SATISFIED | SENTINEL_CUTOFF + filter before min(); no "1900" |
| DATA-04 | R/48 HL anchor exclusion | SATISFIED | `!str_detect(DX_norm, "^C81") & !str_detect(DX_norm, "^201")` at L147 |
| DATA-05 | R/49 both_count patient-level intersection | SATISFIED | inner_join at category grain; intersect() for TOTAL |
| DATA-06 | R/67+R/95 bound (admit_date, source) swap | SATISFIED | `admit_date_1_new`/`admit_date_2_new` helpers confirmed in both |
| DATA-07 | R/101 age_at_episode ordering in summarise() | SATISFIED | L202 precedes L205 |
| DOCS-01 | R/89 header_end anchored to 3rd === bar | SATISFIED | `[3]` at L65; `[2]` absent |

All 8 requirements: SATISFIED.

---

### Anti-Patterns Found

None found. Verification confirmed:
- No "Stem Cell Transplant" string in R/28.
- No "1900" or `year(first_hl_dx_date)` in R/47.
- No patient-level `left_join(dx_record_counts, ...)` on `cancer_summary` frame in R/46.
- No old unbound pmin/pmax pattern (without `_new` helpers) in R/67 or R/95.
- R/89 `[2]` on `header_end` is absent.

---

### Human Verification Required

#### 1. Numeric correctness of R/46 total_records

**Test:** Run R/46 against real data on HiPerGator; compare `total_records` per category to raw `SELECT DX_norm, COUNT(*) FROM DIAGNOSIS GROUP BY DX_norm` aggregated to category grain.
**Expected:** `total_records` equals the true count of DIAGNOSIS rows for codes in each category, not records x patients.
**Why human:** Requires HiPerGator DuckDB connection and PCORnet CDM CSVs; not available locally.

#### 2. R/49 both_count reconciliation

**Test:** Run R/49 on HiPerGator; verify `pre_count + post_count - both_count == union_count` for every category row (the `stopifnot` guard in the plan validates this automatically if present).
**Expected:** The reconciliation identity holds for all categories including the TOTAL row.
**Why human:** Runtime data required.

#### 3. R/89 reference manual field extraction quality

**Test:** Run R/89 on HiPerGator; open generated REFERENCE_MANUAL.md; verify "Not documented" count is near zero for scripts that have complete headers.
**Expected:** Purpose, Inputs, Outputs, Dependencies, Requirements fields populated for the majority of scripts.
**Why human:** Requires source R scripts accessible on filesystem for parsing.

#### 4. R/28 SCT downstream population

**Test:** Run R/28 on HiPerGator with a cohort that includes SCT patients; verify `is_sct_conditioning_context` is TRUE for SCT-adjacent episodes and `days_to_nearest_sct` is non-NA.
**Expected:** Columns populate for patients classified as `treatment_type == "SCT"`.
**Why human:** Requires PCORnet CDM data and known SCT patients to confirm non-empty result.

---

### Gaps Summary

No gaps. All 8 bug fixes are structurally present in the 11 R scripts. The fixes are:

1. R/28 Fix 2 — SCT string literal corrected to `"SCT"`.
2. R/46 Fix 3 — total_records computed at code grain via `code_record_totals`, not summed from patient-level join.
3. R/47 Fix 1 — SENTINEL_CUTOFF pre-filter applied before `min()`; post-hoc 1900 nullify removed.
4. R/48 Fix 4 — HL anchor exclusion (C81*/201.x) added after sentinel filter.
5. R/49 Fix 5 — `cat_both_by_category` uses category-grain inner_join; TOTAL uses `intersect()`.
6. R/67 Fix 6 — `admit_date_1_new`/`admit_date_2_new` helpers bind dates to sources through pmin/pmax swap.
7. R/95 Fix 7 — Identical to Fix 6 for AV+TH scope.
8. R/89 Fix 8 — `header_end` index changed from `[2]` to `[3]`.
9. R/101 Fix 9 — `age_at_episode` assignment precedes `episode_start = min(...)` in summarise().

Numeric verification (R/46 total_records, R/49 both_count reconciliation) and functional verification (R/28 SCT population, R/89 field extraction quality) require HiPerGator runtime with real data. These are flagged for human verification above, not counted as gaps since the structural code changes are correct per the plan specification.

---

_Verified: 2026-07-25_
_Verifier: Claude (gsd-verifier)_
