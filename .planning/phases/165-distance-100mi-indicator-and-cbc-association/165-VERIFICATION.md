---
phase: 165-distance-100mi-indicator-and-cbc-association
verified: 2026-10-08T00:00:00Z
status: passed
score: 10/10 must-haves verified
re_verification: false
---

# Phase 165: Distance >100 mi Indicator and CBC Association — Verification Report

**Phase Goal:** An encounter-level binary `far_from_care_100mi` exists; the appropriate
statistical test for its relationship with CBC is researched and documented in a methods
memo, then the team-selected test is implemented and reported.

**Verified:** 2026-10-08
**Status:** PASSED
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `far_from_care_100mi` computed on every encounter with `distance_status == "computed"` | VERIFIED | `build_enc_analysis()` line 200: `far_from_care_100mi = as.integer(distance_mi > cutoff)` applied after filtering `distance_status == "computed"` (line 189) |
| 2 | `post_anchor` computed per R/147 rule (anchor day = pre) | VERIFIED | `utils_distance_cbc.R` line 222: `post_anchor = as.integer(ADMIT_DATE > hl_anchor_date)` — strict greater-than matches D-25 |
| 3 | Single source of cutoff (`CONFIG$far_from_care_cutoff_mi = 100`); no literal `100` in analysis scripts | VERIFIED | `R/00_config.R` line 228 defines it; R/163 only reference to `100` is in the header comment; R/165 references are `cbc_match_rate * 100` (percentage arithmetic) and `rowSums * 100` (percentage) — not a distance cutoff |
| 4 | CBC events cover whole record (pre- and post-anchor), distinct ID x date grain | VERIFIED | `build_cbc_events()` re-derives from DuckDB `LAB_RESULT_CM` with no date filter; returns `DISTINCT ID, cbc_date` via three-LOINC co-occurrence check |
| 5 | All four candidates ran for both windows and printed numeric results (C3 GEE skipped with SKIP_GEE flag — acceptable) | VERIFIED | 165-METHODS.md numeric results table shows C1, C2, C4 with numeric OR/SE/p; C3 documented as "Skipped: computationally infeasible at 1.7M encounters within SLURM time limit"; SKIP_GEE flag documented in 165-01-SUMMARY.md deviations |
| 6 | `165-METHODS.md` contains four-row candidate table, both-window results, and one stated recommendation | VERIFIED | Candidates section has four-row table; Results section shows both-window 2x2 tables and numeric results; Recommendation section names C4 patient Fisher as primary with C2 Rao-Scott as sensitivity check |
| 7 | D-165-01 recorded in `165-CONTEXT.md` and `CONFIG` | VERIFIED | CONTEXT.md line 30: `D-165-01 (DECIDED 2026-10-08): Primary analysis method = rao_scott`; `R/00_config.R` line 232: `CONFIG$distance_assoc_method <- "rao_scott"` |
| 8 | `CONFIG$distance_assoc_method` is `"rao_scott"` and R/165 dispatches on it | VERIFIED | `R/00_config.R` line 232 sets `"rao_scott"`; `R/165` line 57 reads it into `METHOD`; line 435 passes `method = "rao_scott"` to the Rao-Scott dispatch block |
| 9 | Analysis sets come from `R/utils/utils_distance_cbc.R` (both R/163 and R/165) | VERIFIED | `utils_distance_cbc.R` contains `build_cbc_events()`, `build_enc_analysis()`, `build_pat_analysis()`; R/165 calls all three via the auto-sourced path from `00_config.R` |
| 10 | `distance_cbc_association_<YYYYMMDD>.xlsx` exists with five sheets | VERIFIED | `output/distance_cbc_association_20261008.xlsx` present on disk; 165-02-SUMMARY.md confirms sheets KEY, A_crosstab, B_test, C_sensitivity, QC |

**Score:** 10/10 truths verified

---

## Required Artifacts

| Artifact | Status | Notes |
|----------|--------|-------|
| `R/utils/utils_distance_cbc.R` | VERIFIED | Exists; 313 lines; complete implementations of all five helper functions; no stubs |
| `R/163_distance_cbc_methods_prototype.R` | VERIFIED | Exists; referenced in 165-01-SUMMARY.md commits; ran on HiPerGator producing `enc_far_from_care.rds` |
| `R/165_distance_cbc_association.R` | VERIFIED | Exists; reads `CONFIG$distance_assoc_method`; builds analysis sets via utils helpers; dispatches Rao-Scott primary and patient Fisher sensitivity; writes five-sheet xlsx |
| `.planning/phases/165-.../165-METHODS.md` | VERIFIED | Exists; 204 lines; four-row candidate table; both-window numeric results; D-165-01 section at end |
| `output/distance_cbc_association_20261008.xlsx` | VERIFIED | Exists in `output/` directory |
| `R/00_config.R` — Phase 165 keys | VERIFIED | `CONFIG$far_from_care_cutoff_mi = 100` (line 228); `CONFIG$distance_assoc_method = "rao_scott"` (line 232); `CONFIG$distance_gee_corstr = "exchangeable"` (line 237) |

---

## Key Link Verification

| From | To | Via | Status | Notes |
|------|----|-----|--------|-------|
| `R/165_distance_cbc_association.R` | `CONFIG$far_from_care_cutoff_mi` | `CUTOFF <- CONFIG$far_from_care_cutoff_mi` (line 58) | WIRED | Passed as `cutoff` arg to `build_enc_analysis()` |
| `R/165_distance_cbc_association.R` | `CONFIG$distance_assoc_method` | `METHOD <- CONFIG$distance_assoc_method` (line 57) | WIRED | Validated with `stopifnot`; dispatched to Rao-Scott block |
| `R/165_distance_cbc_association.R` | `utils_distance_cbc.R` | auto-sourced via `00_config.R` | WIRED | `build_cbc_events()`, `build_enc_analysis()`, `build_pat_analysis()` all called |
| `build_enc_analysis()` | `far_from_care_100mi` column | `as.integer(distance_mi > cutoff)` | WIRED | Column present in returned tibble; selected in final `dplyr::select()` |
| `D-165-01` decision | `CONFIG$distance_assoc_method` | Recorded in CONTEXT.md; `"rao_scott"` written to `R/00_config.R` | WIRED | Memo `D-165-01` section states `CONFIG$distance_assoc_method <- "rao_scott"` |

---

## Data-Flow Trace (Level 4)

`R/165_distance_cbc_association.R` reads real data from HiPerGator-executed RDS files. The
output xlsx is present on disk with specific numeric results (OR = 0.553, DEFF = 130) that
match the prototype output. This is strong evidence of a real data flow, not a stub or
hardcoded output. Data-flow status: FLOWING.

---

## Anti-Patterns Found

| File | Issue | Severity | Disposition |
|------|-------|----------|-------------|
| `R/165_distance_cbc_association.R` lines 374, 392 | Literal `100` appears — but only as `* 100` for percentage conversion, not as a distance cutoff | Info | Not a hardcoded distance cutoff; safe |
| `165-METHODS.md` Recommendation section | Author recommended C4 patient Fisher as primary; D-165-01 chose C2 Rao-Scott instead | Info | Not a bug — team override is explicit. Both the memo Recommendation section and the final D-165-01 block clearly document the change. No inconsistency in the codebase; CONFIG and R/165 both implement rao_scott |

No blockers. No STUB patterns. No `return NULL` / empty handler / placeholder patterns found
in the analysis files.

---

## R/122 Unchanged Confirmation

Git log for `R/122_encounter_distance.R` shows the most recent commit predates Phase 165
(`76c60bd` from Phase 154). No commits to R/122 during or after 2026-10-08 for Phase 165
work. R/122 unchanged: CONFIRMED.

---

## Behavioral Spot-Checks

Step 7b: SKIPPED — scripts require HiPerGator DuckDB access and cannot be run locally.
However, the presence of the output xlsx (`output/distance_cbc_association_20261008.xlsx`)
and the numeric results documented in 165-METHODS.md and 165-02-SUMMARY.md provide strong
post-hoc evidence of successful execution.

---

## Human Verification Required

None blocking goal achievement. One informational item:

### 1. xlsx sheet content review

**Test:** Open `output/distance_cbc_association_20261008.xlsx` and verify all five sheets
(KEY, A_crosstab, B_test, C_sensitivity, QC) contain the expected content — especially that
C_sensitivity notes the payer covariate was dropped due to missing RDS.

**Why human:** Sheet content cannot be verified without Excel/R on HiPerGator.

---

## Summary Verdict

**PASSED.** All 10 must-haves verified.

Phase 165 goal is achieved:

1. `far_from_care_100mi` is computed on all computed-distance encounters via
   `build_enc_analysis()` using `CONFIG$far_from_care_cutoff_mi` as the single source.
   No literal `100` appears as a distance cutoff in any analysis script.

2. `165-METHODS.md` is a complete methods memo with the four-candidate table, both-window
   numeric results (DEFF=130, OR=0.553/0.558 for Rao-Scott; OR=0.586/0.659 for patient
   Fisher), and a stated recommendation. D-165-01 is formally recorded in both CONTEXT.md
   and `R/00_config.R`.

3. `R/165_distance_cbc_association.R` implements the D-165-01 decision (rao_scott),
   reads all analysis-set parameters from CONFIG, delegates analysis-set construction to
   `utils_distance_cbc.R` helpers, and produced
   `output/distance_cbc_association_20261008.xlsx`.

4. R/122 was not modified.

The one notable (non-blocking) observation is that the memo author recommended C4 patient
Fisher as primary, but the team chose C2 Rao-Scott. This is correctly documented in the
memo's D-165-01 section and in CONTEXT.md. The production script implements rao_scott.
There is no inconsistency in the code.

---

_Verified: 2026-10-08_
_Verifier: Claude (gsd-verifier)_
