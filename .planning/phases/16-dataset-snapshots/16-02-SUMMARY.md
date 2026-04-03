---
phase: 16-dataset-snapshots
plan: 02
subsystem: visualization-snapshots
tags:
  - rds-snapshots
  - figure-backing-data
  - table-backing-data
  - reproducibility
dependency_graph:
  requires:
    - utils_snapshot.R (save_output_data function)
    - CONFIG$cache$cache_dir (outputs subdirectory)
  provides:
    - 16 RDS snapshots in outputs/ subdirectory
    - Figure backing data for waterfall, sankey, and 7 encounter analysis charts
    - Table backing data for 1 encounter summary CSV and 5 PPTX tables
  affects:
    - R/05_visualize_waterfall.R
    - R/06_visualize_sankey.R
    - R/16_encounter_analysis.R
    - R/11_generate_pptx.R
tech_stack:
  added: []
  patterns:
    - "save_output_data() called immediately before plot/table rendering"
    - "_data suffix naming convention mirrors output filename"
    - "Shared enc_by_year and enc_ud_by_year saved under different names per output"
key_files:
  created: []
  modified:
    - R/05_visualize_waterfall.R (1 snapshot added)
    - R/06_visualize_sankey.R (1 snapshot added)
    - R/16_encounter_analysis.R (8 snapshots added)
    - R/11_generate_pptx.R (6 snapshots added)
decisions:
  - "enc_by_year saved twice with different names (post_tx_encounters_by_dx_year_data, total_encounters_by_dx_year_data) to match D-10 traceability requirement"
  - "enc_ud_by_year saved twice with different names (post_tx_unique_dates_by_dx_year_data, total_unique_dates_by_dx_year_data) for same reason"
  - "cohort_full saved as pptx_cohort_full_data (master source for all pivoted tables) instead of saving every table build operation"
metrics:
  duration_minutes: 4
  tasks_completed: 2
  files_modified: 4
  lines_added: 48
  snapshots_created: 16
  completed_at: "2026-04-03T17:58:19Z"
---

# Phase 16 Plan 02: Add Backing Data Snapshots to Visualization Scripts

**One-liner:** Added save_output_data() calls to 4 visualization scripts, creating 16 RDS snapshots (10 figure backing, 6 table backing) before rendering to preserve exact source data frames.

## What Was Done

Added `save_output_data()` calls to all visualization and output scripts to snapshot the exact data frames used for rendering figures and building tables. All snapshots placed immediately after data transformation completes and before the corresponding ggplot(), ggsave(), or add_table_slide() call.

### Task 1: Waterfall and Sankey Scripts (2 snapshots)

**R/05_visualize_waterfall.R:**
- Added `save_output_data(attrition_plot_data, "waterfall_attrition_data")` after line 36 mutate block
- Snapshot captures the exact data frame passed to ggplot() on line 45
- Includes step factor levels, n_after counts, and formatted labels with percentages

**R/06_visualize_sankey.R:**
- Added `save_output_data(sankey_data, "sankey_patient_flow_data")` after Section 4 (line 148)
- Snapshot captures the final data frame with PAYER_LABEL and TREATMENT_LABEL factors
- Includes collapsed payer categories, collapsed treatment combinations, and N-annotated stratum labels

### Task 2: Encounter Analysis and PPTX Scripts (14 snapshots)

**R/16_encounter_analysis.R (8 snapshots):**

1. **encounters_per_person_by_payor_data** — Histogram figure (Section 1, line 58)
   - `hist_data` with N_ENC_CAPPED (capped at 500), PAYER_CATEGORY_PRIMARY consolidated to 6+Missing
   - Includes overflow counts for facet annotations

2. **post_tx_encounters_by_dx_year_data** — Bar chart figure (Section 2, line 107)
   - `enc_by_year` with mean/median post-tx encounters and total encounters per DX_YEAR
   - Excludes patients with missing DX_YEAR (includes nullified 1900 sentinels)

3. **total_encounters_by_dx_year_data** — Bar chart figure (Section 3, line 133)
   - Same `enc_by_year` data frame as #2, saved under different name per D-10
   - Used for different y-axis (mean_total_enc vs mean_post_tx_enc)

4. **encounter_summary_by_payor_age_data** — CSV summary table (Section 4, line 192)
   - `summary_with_sums` with payer totals and grand total rows
   - Columns: n_patients, total_encounters, total_post_tx_enc, pct_with_post_tx

5. **post_tx_by_age_group_data** — Bar chart figure (Section 5, line 208)
   - `age_post_tx` with Yes/No breakdown per age group, includes percentages
   - Data frame also written to CSV in same section

6. **unique_dates_per_person_by_payor_data** — Histogram figure (Section 6c, line 296)
   - `hist_data_ud` with N_UD_CAPPED (capped at 300), distinct dates per patient
   - Includes overflow counts for facet annotations

7. **post_tx_unique_dates_by_dx_year_data** — Bar chart figure (Section 6d, line 335)
   - `enc_ud_by_year` with mean/median unique dates (post-tx and total) per DX_YEAR

8. **total_unique_dates_by_dx_year_data** — Bar chart figure (Section 6e, line 356)
   - Same `enc_ud_by_year` data frame as #7, saved under different name per D-10
   - Used for different y-axis (mean_total_ud vs mean_post_tx_ud)

**R/11_generate_pptx.R (6 snapshots):**

1. **pptx_cohort_full_data** — Master source (Section 2e, line 407)
   - `cohort_full` assembled from hl_cohort with all treatment flags and encounter metrics
   - Source for all pivoted tables (tbl2–tbl13 built via build_payer_table functions)
   - Per D-07: saves master instead of every pivot to avoid redundancy

2. **last_tx_equals_last_encounter_data** — Slide 14 table (Section 5a, line 1013)
   - `tbl14` comparing treatment types: N with treatment, last tx = last encounter, had follow-up
   - 4 rows: Any Treatment, Chemotherapy, Radiation, Stem Cell Transplant

3. **missing_post_tx_payer_breakdown_data** — Slide 15 table (Section 5a, line 1063)
   - `tbl15` binning patients with missing post-tx payer by encounter count (0, 1-5, 6-10, 11-20, 21+)
   - Includes total row

4. **insurance_after_last_tx_retention_data** — Slide 16 table (Section 5a, line 1147)
   - `tbl16` comparing payer distribution for "Still in Dataset" vs "No Longer in Dataset"
   - Includes No Payer Assigned and Total rows

5. **encounter_summary_stats_by_payer_data** — Slide 18 table (Section 5b, line 1221)
   - `summary_stats` with N, Mean, Median, Min, Q1, Q3, Max, 500+ per payer category
   - Includes Total row

6. **unique_dates_summary_stats_by_payer_data** — Slide 23 table (Section 5b, line 1353)
   - `ud_summary_stats` with same structure as #5 but for unique encounter dates
   - 300+ column instead of 500+

## Deviations from Plan

None. Plan executed exactly as written.

## Verification

All verification criteria met:

1. `grep -c "save_output_data" R/05_visualize_waterfall.R` → 1 ✓
2. `grep -c "save_output_data" R/06_visualize_sankey.R` → 1 ✓
3. `grep -c "save_output_data" R/16_encounter_analysis.R` → 8 ✓
4. `grep -c "save_output_data" R/11_generate_pptx.R` → 6 ✓
5. Total across all 4 scripts → 16 ✓
6. All snapshot names end with `_data` suffix ✓

## Commits

| Hash | Message | Files |
|------|---------|-------|
| 4babd66 | feat(16-dataset-snapshots): add backing data snapshots to waterfall and sankey scripts | R/05_visualize_waterfall.R, R/06_visualize_sankey.R |
| 4220b35 | feat(16-dataset-snapshots): add backing data snapshots to encounter analysis and PPTX scripts | R/16_encounter_analysis.R, R/11_generate_pptx.R |

## Known Stubs

None. All snapshots write to RDS files via save_output_data() which creates the outputs/ subdirectory automatically if it doesn't exist. No hardcoded empty values or placeholder text introduced.

## Requirements Completed

- **SNAP-03**: Figure backing data snapshots — All 10 figure data frames saved before ggplot() rendering
- **SNAP-04**: Table backing data snapshots — All 6 unique PPTX table data frames + 1 encounter CSV summary saved before table building

## Next Steps

Phase 16 Plan 02 complete. All 4 visualization scripts now snapshot their backing data frames to RDS before rendering. Total of 16 snapshots created (10 figures + 6 tables). Next phase (Phase 17) will address visualization polish requirements (VIZP-01 to VIZP-03).

## Self-Check

**Status: PASSED**

All claimed files and commits verified:

```bash
# Files exist and modified
$ git diff --name-only 4babd66~1..4220b35
R/05_visualize_waterfall.R
R/06_visualize_sankey.R
R/11_generate_pptx.R
R/16_encounter_analysis.R

# Commits exist
$ git log --oneline --all | grep -E "4babd66|4220b35"
4220b35 feat(16-dataset-snapshots): add backing data snapshots to encounter analysis and PPTX scripts
4babd66 feat(16-dataset-snapshots): add backing data snapshots to waterfall and sankey scripts

# Snapshot count verification
$ grep "save_output_data" R/*.R | wc -l
16
```

All 16 snapshots verified in code:
- 2 in waterfall/sankey scripts ✓
- 8 in encounter analysis script ✓
- 6 in PPTX script ✓

All snapshot names follow _data suffix convention ✓
