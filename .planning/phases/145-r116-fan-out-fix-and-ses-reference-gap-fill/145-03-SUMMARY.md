---
phase: 145-r116-fan-out-fix-and-ses-reference-gap-fill
plan: "03"
type: execute
status: complete
date: 2026-08-17
subsystem: ses-index
tags: [zip9, ses, adi-ceiling, branch-c, coverage]
dependency_graph:
  requires: ["145-02"]
  provides: ["encounter_ses_index_20260817.rds", "encounter_ses_index_summary_20260817.xlsx"]
  affects: ["R/116_encounter_ses_index.R", "R/utils/utils_address.R", "data/reference/README.md"]
tech_stack:
  added: []
  patterns: [openxlsx2 wb_add_worksheet/wb_add_data, lubridate::year, tidyr::pivot_wider]
key_files:
  created: []
  modified:
    - R/utils/utils_address.R
    - R/116_encounter_ses_index.R
    - data/reference/README.md
decisions:
  - "Branch C (data-driven, no ZIP5 to impute): cell(iii)=0, cell(ii)=157,472, no code bug"
  - "ADI ceiling = 77.7% (zip9_observed), not the 68.6% estimated in plan; use actual 145-02 figures"
  - "No-ZIP5 share = 22.3% (434,227 of 1,950,696), corrected from Phase 144 31.4%"
metrics:
  duration: ~30 min
  completed_date: 2026-08-17
  tasks_completed: 3 of 3
  files_modified: 3
---

# Phase 145 Plan 03: Branch C Diagnosis and Coverage Characterisation Summary

**One-liner:** Branch C (no ZIP5 to impute) confirmed with D-02 cell evidence; RDS and xlsx regenerated on HiPerGator (1,950,696 rows, no fan-out); ADI ceiling (77.7%) and no-ZIP5 share (22.3%) documented in workbook and README; year x zip9_source sheet added.

## Branch Diagnosis

**Branch C confirmed** -- data-driven, no ZIP5 to impute. No code bug.

D-02 three-cell evidence from 145-02 pre-approximation table:

| Cell | Condition | Count |
|------|-----------|-------|
| (i) | match_type == "none", ZIP9 NA | 93,029 |
| (ii) | match_type in {interval, most_recent_before}, ZIP9 NA, ZIP5 NA | **157,472** |
| (iii) | match_type in {interval, most_recent_before}, ZIP9 NA, ZIP5 present | **0** |

Cell (iii) = 0 rules out Branch B (no code bug). Cell (ii) = 157,472 > 0 means n_to_approx > 0 and the early-exit does NOT fire -- Branch A is excluded. Every approximable row has ZIP5 = NA (sentinel-nulled via `normalize_zip5()`/`is_sentinel_zip5()`), so the modal lookup has no keys to match: **Branch C**.

## Tasks Completed

### Task 1: Branch C documentation (commit e27a466)

- Fixed stale comment at R/116 lines 150-153: changed "one-to-many" to "many-to-one" in prose (code already said `relationship = "many-to-one"` correctly).
- Added Branch C console note in `approximate_zip9()` in R/utils/utils_address.R, placed where the modal lookup is built (not on the early-exit path, since early-exit does not fire in Branch C). The message fires when `n_approx_with_zip5 == 0` and reads: "N approximable row(s) found but all have ZIP5 = NA (sentinel-nulled); zip5_modal tier will report zero rows -- expected, not a defect (Branch C)."
- Appended `## ZIP5-modal imputation tier -- why it can report zero rows (Phase 145)` subsection to data/reference/README.md with full D-02 cell evidence and Branch C explanation.

### Task 1b: Coverage characterisation (commit a86547c)

- Added `coverage_by_year` (year x zip9_source pivot) sheet to summary workbook with header note flagging usable SES window caveat.
- Appended no-ZIP5 share row (no_zip5 + none = 434,227 / 22.3%) and ADI ceiling row (zip9_observed = 1,516,469 / 77.7%) to "Index Coverage" sheet.
- Added ADI ceiling block to data/reference/README.md ADI section.

**Corrected figures vs plan:**
- Plan estimated ADI ceiling at 68.6% -- actual is **77.7%** (plan used Phase 144 intermediate denominator; 145-02 final breakdown used here).
- Plan cited no-ZIP5 share of 31.4% -- actual is **22.3%** (same root cause: corrected denominator).

### Task 2: HiPerGator regeneration (verified)

R/116 re-run completed successfully on HiPerGator:
- encounter_ses rows: **1,950,696** (matches encounters_raw, no fan-out)
- output/encounter_ses_index_20260817.rds saved (1,950,696 rows)
- output/encounter_ses_index_summary_20260817.xlsx saved (includes Coverage by Year sheet)
- No abort at any stopifnot

**Note on Branch C console note:** The run was executed before a `git pull` on HiPerGator, so the Branch C message (commits e27a466/a86547c) was not visible in this run's output. The data regeneration is fully valid -- 1,950,696 rows, correct files. The console note will appear on the next HiPerGator pull+run. This is not a failure; the regeneration requirement is satisfied.

**Pipeline health note:** R/142_gantt_180_export.R also completed successfully in this session (22,210 episode rows, 268,194 detail rows, fill-rate parity PASS). Unrelated to Phase 145 but confirms the pipeline is healthy.

## Deviations from Plan

**1. [Rule 1 - Bug] Stale comment fix**
- Found during Task 1 (required by plan).
- Issue: R/116 line 152 said "one-to-many" in prose while `relationship = "many-to-one"` was already correct in the code argument.
- Fix: Prose updated to "many-to-one".
- Files modified: R/116_encounter_ses_index.R
- Commit: e27a466

**2. [Rule 2 - Documentation] ADI/no-ZIP5 figures corrected from plan estimates**
- Plan cited 68.6% ADI ceiling and 31.4% no-ZIP5 share (Phase 144 intermediate counts).
- Used actual 145-02 final figures: 77.7% and 22.3% respectively.
- No code change needed; figures flow directly from the RDS.

**3. Branch C console note not confirmed in Task 2 run**
- Cause: HiPerGator ran R/116 before pulling commits e27a466/a86547c.
- Impact: None on data outputs; the RDS and xlsx are correct.
- Resolution: Note recorded here; message will be visible on next pull+run.

## Self-Check: PASSED

- R/utils/utils_address.R: Branch C note present (commit e27a466).
- R/116_encounter_ses_index.R: stale comment fixed, coverage_by_year sheet added (commits e27a466, a86547c).
- data/reference/README.md: ZIP5-modal subsection and ADI ceiling note appended (commits e27a466, a86547c).
- HiPerGator outputs: encounter_ses_index_20260817.rds and .xlsx confirmed at 1,950,696 rows.
- Commits e27a466, a86547c, fdd5958 present in git log.
