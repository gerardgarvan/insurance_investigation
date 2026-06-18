---
phase: 110-redo-cancer-summary-table-pre-post-v2-7day
plan: 01
subsystem: cancer-summary-tables
tags:
  - cancer-summary
  - 7-day-confirmation
  - hl-diagnosis
  - data-filtering
  - secondary-malignancies
dependency_graph:
  requires:
    - R/45_cancer_summary.R (two_or_more_unique_dates_gt_7 column)
    - R/47_cancer_summary_refined.R (confirmed_hl_cohort.rds)
  provides:
    - tighter-v2-cancer-summary-xlsx
    - hl-specific-7-day-population-filter
    - dual-7-day-confirmation-criteria
  affects:
    - output/tables/cancer_summary_table_pre_post_v2_7day.xlsx
    - output/tables/cancer_summary_table_pre_post_v2_7day.csv
    - output/tables/cancer_summary_table_pre_post_v2_7day.rds
tech_stack:
  added: []
  patterns:
    - ID vector extraction for population filtering
    - dual filter chaining (population + per-code)
    - semi-join pattern reuse for K-L-M columns
key_files:
  created: []
  modified:
    - R/49_cancer_summary_pre_post.R
    - R/88_smoke_test_comprehensive.R
decisions:
  - D-01: Overwrite existing V2 output with tighter-filtered data (V1 remains untouched)
  - D-04: Extract hl_7day_confirmed_ids vector for population filtering
  - D-05: V2 population = HL-specific 7-day confirmed + per-code 7-day confirmed
  - D-06/D-07: K-L-M columns inherit tighter population via existing v2_valid_pairs semi-join
  - D-08: Both sheets apply same filtering for internal consistency
metrics:
  duration_minutes: 4
  tasks_completed: 2
  tasks_total: 2
  files_modified: 2
  commits: 2
  lines_changed: 44
  completed_date: 2026-06-18
---

# Phase 110 Plan 01: Tighten V2 Cancer Summary to HL-Specific 7-Day Confirmed Patients - Summary

**One-liner:** Dual 7-day confirmation for V2 cancer summary table — HL diagnosis-specific population filter plus secondary malignancy 7-day gap requirement

## What Was Built

Modified R/49_cancer_summary_pre_post.R to apply dual 7-day confirmation criteria for the V2 cancer summary table:
1. **Population filter:** Restrict V2 table to patients whose **Hodgkin Lymphoma diagnosis specifically** (C81 + ICD-9 201.x codes) meets the 7-day gap criterion
2. **Secondary malignancy filter:** K-L-M columns (Pre-HL, Post-HL, Both) only count secondary malignancies that themselves meet the 7-day confirmation criterion

Updated R/88_smoke_test_comprehensive.R to validate the new filtering pattern and assertion bounds.

## Tasks Completed

| Task | Status | Commit | Files Modified |
|------|--------|--------|----------------|
| 1. Tighten R/49 V2 population filter, assertions, and xlsx metadata | ✅ Complete | be533fa | R/49_cancer_summary_pre_post.R |
| 2. Update R/88 smoke test for V2 population bounds | ✅ Complete | f142258 | R/88_smoke_test_comprehensive.R |

## Key Changes

### R/49 Modifications (5 targeted areas)

**Change 1 — Section 3 (HL 7-day computation):**
- Expanded `n_hl_7day` computation to produce `hl_7day_confirmed_ids` vector (ID extraction)
- Preserves existing count for console diagnostics
- Intermediate `hl_7day_confirmed` tibble added to rm() cleanup

**Change 2 — Section 8b (V2 population filter):**
- Added dual filter chain: `filter(ID %in% hl_7day_confirmed_ids) %>% filter(two_or_more_unique_dates_gt_7 == 1)`
- Step 1: restrict to HL-specific 7-day confirmed patients
- Step 2: require each patient-code pair to also meet 7-day gap
- Added diagnostic messages showing HL-confirmed population count

**Change 3 — Section 8b (V2 assertion bounds):**
- Updated from `[6300, 7500]` to `[4000, 7000]` to accommodate smaller HL-specific subset
- Updated error message to reference "HL-confirmed population"
- Wide bounds allow for first-run data observation

**Change 4 — Section 9b (V2 xlsx metadata):**
- Sheet 1 title: "Confirmed HL 7-Day Gap Patients Only"
- Sheet 2 title: "Confirmed HL 7-Day Gap Patients Only"
- Both footnotes: "V2 (Phase 110): Restricted to patients with 7-day confirmed HL diagnosis (C81 + 201.x codes with 2+ unique dates spanning 7+ days). Secondary malignancies in Pre/Post/Both columns also require two_or_more_unique_dates_gt_7 == 1."

**Change 5 — Section 10b (V2 RDS metadata):**
- Updated filter description: "HL-specific 7-day confirmed (ID %in% hl_7day_confirmed_ids) AND two_or_more_unique_dates_gt_7 == 1"
- Added `hl_7day_confirmed_count` field for traceability
- Updated phase reference to "110"

**What was NOT changed (per plan):**
- V1 Sections (1-8a, 9a, 10, 11) — completely untouched
- Lines 518-530 (v2_valid_pairs semi-join) — existing pattern automatically narrows K-L-M columns when `cancer_summary_v2` is tighter
- HL anchor code exclusion logic (lines 229-235) — defensive safeguard remains
- V1 vs V2 comparison table (lines 641-659) — generic logic works with tighter V2 automatically

### R/88 Smoke Test Updates

**New Check 2b:** Validates `hl_7day_confirmed_ids` filtering pattern exists in R/49
**Updated Check 3:** Validates new assertion bounds (4000-7000) instead of old bounds (6300-7500)
**Preserved Check 2:** Per-code `two_or_more_unique_dates_gt_7 == 1` filter still validated

## Deviations from Plan

None — plan executed exactly as written. All changes matched the interfaces specification.

## Known Stubs

None — this phase modifies existing filtering logic, no new stubs introduced.

## Technical Decisions

1. **Wide assertion bounds (4000-7000):** Set conservatively for first run with real data. Bounds can be tightened after observing actual V2 population size. The HL-specific subset is known to be smaller than the previous any-code subset (6300-7500), but exact count depends on data distribution.

2. **Dual filter order matters:** Population filter (`ID %in% hl_7day_confirmed_ids`) applied FIRST, then per-code filter (`two_or_more_unique_dates_gt_7 == 1`). This ensures only HL-confirmed patients appear, and only their 7-day confirmed secondary malignancies are counted.

3. **Reused existing semi-join pattern:** The v2_valid_pairs extraction from `cancer_summary_v2` automatically implements the K-L-M column tightening. No code change needed — the existing pattern correctly filters pre/post/both patient-code pairs to only those meeting the 7-day gap criterion.

## Testing Notes

Verification checks passed:
- ✅ 7 occurrences of `hl_7day_confirmed_ids` in R/49 (definition, filter, footnote x2, metadata x2, diagnostic message)
- ✅ 2 title updates ("Confirmed HL 7-Day Gap Patients Only")
- ✅ 3 assertion bounds references (4000-7000) in R/49
- ✅ 2 assertion bounds references (4000-7000) in R/88
- ✅ 3 semi-join pattern references (patients_pre_v2, patients_post_v2, patients_both_v2) — unchanged

**Next validation step:** Run R/49 with real data to observe actual V2 population count and verify it falls within [4000, 7000] range. If out of bounds, adjust assertion limits per observed data.

## Files Modified

### R/49_cancer_summary_pre_post.R
- Lines 125-135: Expanded HL 7-day computation to produce ID vector
- Line 154: Updated rm() to include hl_7day_confirmed intermediate tibble
- Lines 175-195: Tightened V2 population filter with dual criteria and updated assertion bounds
- Lines 950, 1053: Updated V2 xlsx sheet titles
- Lines 1026, 1129: Updated V2 footnote text to describe dual 7-day confirmation
- Lines 1181-1190: Updated V2 RDS metadata (filter description, hl_7day_confirmed_count, phase 110)

### R/88_smoke_test_comprehensive.R
- Lines 878-887: Added Check 2b (HL-specific filtering pattern) and updated Check 3 (new assertion bounds)

## Self-Check: PASSED

**Files created:** None (modifications only)

**Files modified:**
- ✅ R/49_cancer_summary_pre_post.R exists and contains all expected patterns
- ✅ R/88_smoke_test_comprehensive.R exists and contains updated checks

**Commits exist:**
- ✅ be533fa: feat(110-01): tighten V2 cancer summary to HL-specific 7-day confirmed patients
- ✅ f142258: test(110-01): update R/88 smoke test for V2 population bounds

All verification claims confirmed via git log and file inspection.
