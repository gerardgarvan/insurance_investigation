# 213-03 SUMMARY (COMPLETE)

## HiPerGator results (2026-11-17, pasted by Gerard)
- R/53: loaded confirmed HL cohort 9,179; valid deaths 1,297; impossible 47 (before treatment 29, before HL dx 18); post-death activity 255; death-only 571. chk_cohort: rows 9,179 OK, distinct 9,179 OK.
- R/29: 19,324 rows, 5,018 patients; first-line 1,959 (ABVD 956, BV+AVD 194, AVD 169, ABVD/AVD partial 118, R-CHOP 115, CHOP 108, ABVD_PLUS 95).
- R/52 (pre-filter run): gantt_episodes.csv 29,585 rows, 23 cols, 9,307 distinct patients; HL Diagnosis rows 9,179 OK; Death rows 1,082; detail 275,518 rows.
- 9,307 vs 9,179: 128 patients in the file are not in the cohort. This triggered the cohort-only decision below.

## Follow-up code change (local, 2026-11-17)
- `filter_gantt_to_cohort()` and `tr_nhl_only_among()` in `R/utils/utils_cohort_rule.R`; called in R/52 and R/142 (Section 4Z) before the CSV writes. Filters episodes and detail (including Death rows); prints rows/patients removed split TR-NHL-only (COHORT-03) vs other non-cohort; stopifnot: all patients in cohort, distinct episode patients == HL Diagnosis patients.
- `chk_gantt_cohort_only(path)` in `R/tools/213_chain_checks.R`; R/88 static checks added; tests in `tests/testthat/test-213-chain-checks.R`.
- Label fixes: R/53 care_gap_category text; R/52 header comment for `episode_dx_7day_confirmed`.
- R/52 must be rerun on HiPerGator to produce the cohort-only files (commands in the chat reply / plan 04).

## Assumptions (headless run)
- TR-NHL-only split uses `build_tr_lymphoma_flags()` on the removed IDs (tr_nhl_dx TRUE and tr_hl_dx not TRUE). If TUMOR_REGISTRY_ALL is unavailable the split prints "NA" and the filter still runs.
- Existing 29,585-row gantt_episodes.csv is superseded by the cohort-only rerun; R/59 optional step not run.
