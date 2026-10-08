---
phase: 165-distance-100mi-indicator-and-cbc-association
plan: "01"
subsystem: analysis
tags: [distance, cbc, statistical-methods, gee, survey, prototype]
dependency_graph:
  requires:
    - R/122 output (enc_distance RDS)
    - R/147 pattern (CBC LOINCs, anchor date logic)
    - DuckDB (LAB_RESULT_CM, ENCOUNTER)
    - utils_treatment.R (get_hl_any_dx_ids)
  provides:
    - R/utils/utils_distance_cbc.R (shared helpers for R/163 and R/165)
    - R/163_distance_cbc_methods_prototype.R
    - CONFIG$far_from_care_cutoff_mi (single cutoff source)
    - enc_far_from_care.rds (ACC-01 -- produced when R/163 runs on HiPerGator)
    - 165-METHODS.md (after Task 6, pending prototype log)
  affects:
    - Plan 02 (R/165 production script; blocked on D-165-01)
tech_stack:
  added:
    - survey (cluster-adjusted chi-square; Rao-Scott F; svyglm)
    - geepack (GEE logistic; marginal OR; robust SE)
  patterns:
    - Non-equi join for CBC-in-encounter (dplyr left_join + filter on date range)
    - CONFIG key as single numeric source (CONFIG$far_from_care_cutoff_mi)
    - tryCatch GEE fallback (exchangeable -> independence)
key_files:
  created:
    - .planning/phases/165-distance-100mi-indicator-and-cbc-association/165-DISCOVERY.md
    - R/utils/utils_distance_cbc.R
    - R/163_distance_cbc_methods_prototype.R
    - slurm/163_distance_cbc_methods_prototype.sbatch
  modified:
    - R/00_config.R (Phase 165 keys section added after line 218)
decisions:
  - "R/163 is prototype (free); R/164 taken by dox baseline; Plan 02 production = R/165"
  - "build_cbc_events() re-derives from DuckDB (R/147 saves post-only wide table; D-06a)"
  - "Date priority for CBC: RESULT_DATE > SPECIMEN_DATE > LAB_ORDER_DATE (matches R/147)"
  - "suppress_small_vec() returns NA_integer_; suppress_display() returns '<11' string (both needed)"
  - "GEE corstr defaults to exchangeable via CONFIG$distance_gee_corstr; falls back to independence with log"
metrics:
  completed_date: "2026-10-08"
  tasks_completed: 3
  tasks_total: 7
  tasks_blocked_at: "Task 2 (checkpoint:human-action — install survey/geepack on HiPerGator)"
---

# Phase 165 Plan 01: Distance >100 mi Indicator and CBC Association Methods Prototype — Summary

**One-liner:** Added `CONFIG$far_from_care_cutoff_mi` (single cutoff source), shared helpers `utils_distance_cbc.R`, and prototype R/163 running all four candidate tests (naive Pearson, Rao-Scott, GEE, patient-level) x two windows against real HiPerGator data.

## Completed Tasks

| Task | Name | Commit | Key Files |
|------|------|--------|-----------|
| 1 | Read-only discovery → 165-DISCOVERY.md | 9c99239 | .planning/phases/165-.../165-DISCOVERY.md |
| 3 | CONFIG key + utils_distance_cbc.R | 9c8b601 | R/00_config.R, R/utils/utils_distance_cbc.R |
| 4 | R/163 prototype + sbatch wrapper | 1aabefe | R/163_distance_cbc_methods_prototype.R, slurm/163_distance_cbc_methods_prototype.sbatch |

## Pending Tasks

| Task | Type | Blocked by |
|------|------|-----------|
| 2 | checkpoint:human-action | Install survey/geepack on HiPerGator interactively |
| 5 | checkpoint:human-action | Run prototype on HiPerGator; paste log |
| 6 | auto | Task 5 log (fill 165-METHODS.md with real numbers) |
| 7 | checkpoint:human-verify | Review memo, forward to Amy/Erin, record D-165-01 |

## Key Discoveries (Task 1)

- **Script numbers:** R/163 free (prototype); R/164 taken (`164_dox_baseline_counts.R`); Plan 02 production = R/165
- **CBC re-derivation:** R/147 saves a post-anchor-only wide table; `build_cbc_events()` re-derives from DuckDB LAB_RESULT_CM with LOINCs 6690-2 / 718-7 / 777-3, date priority RESULT_DATE > SPECIMEN_DATE > LAB_ORDER_DATE
- **Anchor source:** `get_hl_any_dx_ids()` in utils_treatment.R (earliest DX_DATE / ADMIT_DATE fallback)
- **DuckDB helpers:** `open_pcornet_con()` / `close_pcornet_con()` (utils_duckdb.R)
- **DISCHARGE_DATE:** present in ENCOUNTER (70.87% missing; `coalesce(DISCHARGE_DATE, ADMIT_DATE)` for single-day encounters)
- **Rurality:** `encounter_ses_index_YYYYMMDD.rds` from R/116; columns `ruca_code`, `ruca_category`; join key PATID (not ID)
- **Payer:** `payer_summary` from R/02; column `PAYER_CATEGORY_PRIMARY`
- **suppress_small_vec():** no vectorized NA-integer version in shared utils; defined both in utils_distance_cbc.R

## CONFIG Keys Added

```r
CONFIG$far_from_care_cutoff_mi <- 100       # single source; no literal 100 in R/163 or utils
CONFIG$distance_assoc_method   <- NA_character_  # D-165-01; R/165 stops if NA
CONFIG$distance_gee_corstr     <- "exchangeable" # fallback to "independence" logged in R/163
```

## Utils Contract (utils_distance_cbc.R)

| Function | Returns | Notes |
|----------|---------|-------|
| `suppress_small_vec(n)` | integer (NA for 1-10) | For arithmetic suppression |
| `suppress_display(n)` | character ("<11" for 1-10) | For table output, matches pipeline |
| `naive_or_se(ct)` | list(log_or, se, haldane) | Woolf; Haldane 0.5 if any cell = 0 |
| `build_cbc_events(con, ids)` | tibble(ID, cbc_date) distinct | Re-derives from DuckDB; whole record |
| `build_enc_analysis(...)` | tibble, one row per ENCOUNTERID | far_from_care_100mi, post_anchor, cbc_in_encounter |
| `build_pat_analysis(...)` | tibble, one row per patient | any_far, any_cbc, n_encounters |

## Deviations from Plan

**1. [Rule 1 - Discovery] R/163 join implementation — removed erroneous dplyr::join_by reference**

The plan's pseudo-code for `build_enc_analysis()` showed a `dplyr::join_by(between(...))` syntax using a column self-reference that is ambiguous in dplyr. The implemented version uses a cleaner pattern: `left_join` on ID then `filter(cbc_date >= ADMIT_DATE & cbc_date <= enc_end)` followed by `group_by(ENCOUNTERID)` summarise. This achieves the same non-equi join semantics without the ambiguous column reference, and the stopifnot guard for no duplicate ENCOUNTERIDs is retained.

None — plan executed with one implementation-level clarification above.

## Known Stubs

None — utils_distance_cbc.R functions are complete implementations. R/163 is complete but cannot run until survey/geepack are installed (Task 2) and HiPerGator execution is available (Task 5). 165-METHODS.md will be written from the Task 5 log (Task 6).

## Self-Check: PASSED

Files created:
- `.planning/phases/165-distance-100mi-indicator-and-cbc-association/165-DISCOVERY.md` — exists
- `R/utils/utils_distance_cbc.R` — exists
- `R/163_distance_cbc_methods_prototype.R` — exists
- `slurm/163_distance_cbc_methods_prototype.sbatch` — exists

Commits:
- 9c99239 — feat(165-01): Task 1 — discovery answers in 165-DISCOVERY.md
- 9c8b601 — feat(165-01): Task 3 — CONFIG keys + utils_distance_cbc.R
- 1aabefe — feat(165-01): Task 4 — R/163 prototype + slurm/163 sbatch wrapper

R/122_encounter_distance.R: unchanged (git diff empty, confirmed).
Literal `100` cutoff: absent from R/163 and utils_distance_cbc.R (confirmed by grep).
`module load R/4.4.2`: absent from R/163 and sbatch (confirmed by grep).
`statistic = "F"`: present in R/163 line 276 (confirmed).
