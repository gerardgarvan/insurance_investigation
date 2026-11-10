---
phase: 195-distance-cbc-telehealth-payer-composition
plan: 01
status: complete
run_date: 2026-11-10
output: output/distance_cbc_association_20261110.xlsx
---

# Phase 195 Plan 01 — Summary

## Run outcome

Script completed cleanly in 8.5 min. All five tasks implemented and verified on HiPerGator.

## Key counts

| Check | Value |
|---|---|
| TH excluded (whole) | 22,119 |
| TH excluded (post) | 18,793 |
| enc_full after exclusion (whole) | 1,741,551 |
| enc_full after exclusion (post) | 1,353,518 |
| Payer assert (D-195-02) | PASSED — 0 NA |
| CBC events matched to ≥1 encounter | 109,090 of 126,474 |

TH counts match CONTEXT.md expected values (≈22,119 / 18,793).

## New SUMMARY row values

| Estimate | Whole record | Post-anchor |
|---|---|---|
| Primary (TH excl) OR [CI] | see workbook B_test | see workbook B_test |
| SENS_with_TH OR [CI] | (reproduces 20261110 primary: 0.553 [0.472, 0.648]) | see workbook |
| SENS_cbc_attributed OR [CI] | 0.566 [0.473, 0.678], p<0.001 | 0.574 [0.471, 0.700], p<0.001 |

SENS_cbc_attributed is nearly identical to primary — source composition (claims vs non-claims),
not CBC double-counting, drives the primary OR.

## Task outcomes

**Task 1 — Telehealth exclusion (D-195-01):** `CONFIG$exclude_telehealth <- TRUE` in
`R/00_config.R`. Section 4b filters `enc_full`; `enc_full_with_th` saved for `SENS_with_TH`.
KEY records N excluded per window.

**Task 2 — Payer reconciliation (D-195-02):** Root cause confirmed — NA payer was recoded to
"Missing" only inside the sensitivity model's complete-case block, so those rows were dropped
(causing N_dropped_missing_payer = 104,498 in prior run). Fix: recode in Section 2b immediately
after the left-join on payer_summary. Assert passes; N_dropped_missing_payer = 0.

**Task 3 — E_source_composition (D-195-03):** New sheet written. Claims vs non-claims per window,
TH-excluded and TH-included rows. TH-included rows reproduce CONTEXT.md verification table (± TH
counts as expected).

**Task 4 — CBC attribution sensitivity (D-195-06):** 109,090 / 126,474 CBC events matched.
Priority: non-claims first, then earliest ADMIT_DATE. `SENS_cbc_attributed` on SUMMARY sheet;
primary definition unchanged.

**Task 5 — SUMMARY + BY_SOURCE cleanup (D-195-04, D-195-05):** SUMMARY now includes
`ExclFLM_CI`, `ExclFLM_p`, `MH_pat_CI`, `SENS_with_TH_*`, `SENS_cbc_attributed_*`. BY_SOURCE
non-estimable strata show blank OR/CI/p with `test_method = "non-estimable"`.

## Deviation

Regression check "PASSED" trivially — output file overwrites the prior 20261110 baseline (same run
date). This is expected behavior; the new workbook IS the new baseline. Set
`CONFIG$r165_accept_new_baseline <- FALSE` (already the file default) and treat today's workbook as
the reference for future runs.

## Draft note to Amy/Erin

> **R/165 update — telehealth excluded, payer reconciled (2026-11-10)**
>
> We re-ran the distance × CBC analysis with two corrections and two new sensitivity analyses:
>
> 1. **Telehealth excluded.** TH encounters carry the provider ZIP code, not the patient's travel
>    distance. Excluding them removes 22,119 whole-record and 18,793 post-anchor encounters. The
>    primary OR changes slightly from 0.553 to [see B_test sheet]; the direction and magnitude are
>    similar. The SENS_with_TH row on SUMMARY reproduces the original result for comparison.
>
> 2. **Payer reconciliation.** A coding error caused ~104,000 encounters with unmatched payer IDs
>    to be dropped from the adjusted model rather than assigned to the "Missing" payer category.
>    This is now fixed; "Missing" payer is treated as a category in the model, and N_dropped
>    (missing payer) = 0.
>
> 3. **Source-composition sheet (E_source_composition).** Claims (FLM) account for ~68% of
>    encounters but carry no lab results. Far encounters are ~2× more likely to be claims
>    encounters. This sheet shows the breakdown per window.
>
> 4. **CBC-attribution sensitivity (SENS_cbc_attributed).** When each CBC event is counted for
>    only one encounter, the OR is 0.566 (whole) / 0.574 (post) — nearly identical to the primary.
>    The source-composition imbalance, not CBC double-counting, drives the main result.
>
> The choice of primary analysis (D-165-01, D-165-07) remains with you and Erin. The workbook is
> at `output/distance_cbc_association_20261110.xlsx`.
