---
plan: 148-03
phase: 148-centroid-zip9-crosswalk-tier3
status: complete
tasks-completed: 3/3
self-check: PASSED
---

## What Was Built

- `R/utils/utils_address.R`: `zip5_representative` branch added to `.classify_zip9_source()`
  in both the centroid-lookup and no-centroid-lookup arms.
- `R/116_encounter_ses_index.R`: `ADI_SUMMARY_PATH` constant, `has_adi_summary` probe,
  `has_adi_zip5` join block, and `adi_natrank_zip5_median` column added.

## Bug Found and Fixed (commit 5b65d56)

The initial code (commit b7a5e52) used `isTRUE(has_adi_zip5)` inside `case_when`.
`isTRUE()` is not vectorized — it evaluates the entire column as a single scalar and
always returns FALSE, so the `zip5_representative` branch never fired. Fixed by replacing
with bare `has_adi_zip5` (already a logical column coalesced to FALSE in R/116).

First run (pre-fix): `zip5_representative: 0`.
Post-fix run (2026-08-19): `zip5_representative: 30,725` (unique patient-date) → **47,036 encounters**.

## D-04 Figures

- **(b) Records resolved of 36,953 needing Tier 3: 30,725 (83.2%)** — lead figure
- **(c) Encounters with zip5_representative: 47,036**

## zip9_source breakdown (approximate_zip9 level, unique patient-date pairs)

| zip9_source | count |
|---|---|
| zip9_observed | 744,230 |
| zip5_modal | 111,599 |
| zip5_centroid | 0 |
| zip5_representative | **30,725** |
| zip5_no_zip9 | 6,228 |
| no_zip5 | 8,920 |
| none | 93,029 |

## zip9_source breakdown (encounter level, final output)

| zip9_source | encounters |
|---|---|
| zip9_observed | 1,516,469 |
| zip5_modal | 198,768 |
| zip5_representative | **47,036** |
| zip5_no_zip9 | 12,782 |
| no_zip5 | 16,942 |
| none | 158,699 |

## SES Coverage (post-fix)

| Index | Coverage |
|---|---|
| SDI | 90.2% |
| ADI (ZIP9-level, adi_natrank) | 84.1% |
| SVI | 90.2% |
| RUCA | 91.0% |

## R/88

Not re-run this wave (parse-only verified on Windows). Pre-existing 3 failures unchanged;
no new failures expected from the `isTRUE` → bare logical change.

## Tasks

1. **Task 1:** utils_address.R and R/116 updated (commit b7a5e52, then fixed in 5b65d56).
2. **Task 2:** Parse checks passed; R/116 re-run on HiPerGator confirmed correct output.
3. **Task 3 (human-verify checkpoint):** User ran `Rscript R/116_encounter_ses_index.R`;
   `zip5_representative: 47,036` confirmed in `logs/148_r116_rerun.log` (2026-08-19).
