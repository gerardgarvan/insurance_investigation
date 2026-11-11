---
quick: 261111-ce7
title: "Phase A follow-ups: suppress_small NA fix, folder move, reader comments, RERUN-AND-REISSUE, fingerprint tool"
status: complete
completed: 2026-11-11
duration_min: ~15
tasks_completed: 5
files_modified:
  - R/107_med_admin_dispensing_gap_diagnostic.R
  - R/109_med_admin_dispensing_fix_impact_audit.R
  - R/110_output_level_before_after_report.R
  - R/48_cancer_summary_post_hl.R
  - R/49_cancer_summary_pre_post.R
  - R/52_gantt_v2_export.R
  - R/142_gantt_180_export.R
  - R/tools/check_cohort_fingerprint.R (new)
  - .planning/phases/196-phase-a-delivered-output-fixes/196-01-PLAN.md (new)
  - .planning/phases/196-phase-a-delivered-output-fixes/RERUN-AND-REISSUE.md (new)
commits:
  - 7452d07: fix(suppress_small): NA input -> NA_character_ via case_when; add stopifnot in R/107, R/109, R/110
  - c3c77a5: chore: move Phase A plan artifacts from phase 195 to new phase 196 folder
  - fc0cfd3: docs(cancer_summary): resolve NEEDS DECISION comments in R/48, R/49, R/52, R/142
  - b882752: docs(phase-a): update RERUN-AND-REISSUE with before-rerun steps; add R/tools/check_cohort_fingerprint.R
---

## Summary

NA-safe `suppress_small` via `case_when` with `stopifnot` smoke tests in R/107, R/109, R/110; Phase 195 plan artifacts moved to Phase 196 folder; four NEEDS DECISION comments resolved to R/45 raw; RERUN-AND-REISSUE updated with before-rerun snapshot checks and fingerprint tool created.

## Tasks

1. **suppress_small NA fix** — R/107, R/109, R/110: replaced `ifelse` with `dplyr::case_when` returning `NA_character_` on NA input; `stopifnot` smoke test appended after each function.

2. **Phase 195 → 196 folder move** — Created `.planning/phases/196-phase-a-delivered-output-fixes/`; copied `195-01-PLAN.md` → `196-01-PLAN.md` with `phase:` and `name:` frontmatter updated; copied `RERUN-AND-REISSUE.md`; deleted originals from 195 folder; updated STATE.md `last_activity` to 2026-11-11.

3. **cancer_summary reader comments** — Replaced `NEEDS DECISION` blocks in `R/48_cancer_summary_post_hl.R`, `R/49_cancer_summary_pre_post.R`, `R/52_gantt_v2_export.R`, `R/142_gantt_180_export.R` with single-line decided comment: reads R/45 raw `cancer_summary.csv`.

4. **RERUN-AND-REISSUE.md updates** — Added "Before rerun" section (snapshot verification, fingerprint check, regression check steps); replaced Run order table with final 10-row version; removed resolved NEEDS DECISION section.

5. **check_cohort_fingerprint.R** — Created `R/tools/check_cohort_fingerprint.R` using `here()` for all paths, `dplyr::n_distinct`, `digest::digest` for sorted-ID md5; stops with message on mismatch.

## Deviations

- Plan listed `R/48_cancer_summary_payer.R`, `R/49_cancer_summary_payer_refined.R`, `R/52_cancer_summary_stage.R`, `R/142_cancer_stage_payer_summary.R` in `files_modified` frontmatter. Actual filenames are `R/48_cancer_summary_post_hl.R`, `R/49_cancer_summary_pre_post.R`, `R/52_gantt_v2_export.R`, `R/142_gantt_180_export.R`. NEEDS DECISION grep confirmed the correct targets. Task executed on actual files; frontmatter in this SUMMARY uses the real names.

- R/110 `suppress_small` comment appeared above the function (not inside it as shown in the plan diff). Replaced the two-line comment + function block as a unit. Result is identical.

- `R/tools/check_cohort_fingerprint.R` created with `library(digest)` added to `suppressPackageStartupMessages` block (constraints version), overriding the PLAN.md version which omitted it despite using `digest::digest`.

## Self-Check: PASSED

- `R/tools/check_cohort_fingerprint.R` exists
- `.planning/phases/196-phase-a-delivered-output-fixes/196-01-PLAN.md` exists
- `.planning/phases/196-phase-a-delivered-output-fixes/RERUN-AND-REISSUE.md` exists
- All 4 commits present in git log
- No NEEDS DECISION remains in R/48, R/49, R/52, R/142
