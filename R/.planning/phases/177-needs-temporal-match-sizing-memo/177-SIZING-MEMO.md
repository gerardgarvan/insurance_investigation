# Phase 177: NEEDS_TEMPORAL_MATCH Sizing Memo

**Run date:** 20261012
**Script:** R/177_temporal_match_sizing.R
**Workbook:** output/temporal_match_sizing_20261012.xlsx
**R/121 input:** zip_problem_inventory_2026-10-09.rds (not pinned — most recent by mtime)
**R/122 input:** encounter_distance_20261006.rds (not pinned — most recent by mtime)

---

## Decision Framework (locked before counting)

The recommendation tier is determined mechanically from two measures:

| Share of Phase 165 analysis encounters filled | Effect on >100 mi result | Recommendation |
|---|---|---|
| Under 1% | Can't plausibly move it | Document only |
| 1–5% | — | Inline fix in an existing script |
| Over 5% | *Or* could change the >100 mi result | New phase |

**"Could change the >100 mi result" (locked):** projected newly-far encounters are more than **5%** of the current far-encounter count in the Phase 165 set. Evaluated whole-record and post-anchor; either exceeding 5% triggers it.

**Mechanical decision rule (applied in order):**
1. If D-04 is not explained → recommendation withheld.
2. Else if share filled > 5% OR far_ratio > 5% (either window) → New phase.
3. Else if share filled ≥ 1% → Inline fix.
4. Else → Document only.

Share filled = filled encounters / current Phase 165 analysis-set encounters.

---

## D-04 Reconciliation

### Cross-tab: R/122 `patient_zip_missing` patients × R/121 triage group

| R/121 triage group | N patients in R/122 patient_zip_missing | Definitional reason |
|---|---|---|
| not in R/121 | 117 | R/121 was run on a specific cohort intersection; patients present in the ENCOUNTER/address universe but absent from R/121's patient tibble (e.g., enrolled but outside the triage filter window) are unclassified. No contradiction — R/121 triage is not exhaustive across all 1.98M enc_distance rows. |
| NO_MISSING_ZIP5 | 88 | R/121 checks ENCOUNTER row ZIP9/ZIP5 fields. R/122 uses LDS_ADDRESS_HISTORY for ZIP calendar lookup. A patient can have non-missing ZIP5 on all encounter rows (R/121: NO_MISSING_ZIP5) yet have address history gaps that leave some encounter dates uncovered (R/122: patient_zip_missing). Different data sources; both findings are correct. |
| UNREACHABLE_NO_ZIP9 | 42 | R/121 found no usable ZIP9 anywhere in the encounter rows; R/122 also found no address history coverage. Definitionally consistent: both sources agree these patients have no recoverable ZIP. |
| NEEDS_TEMPORAL_MATCH | 0 | See below. |

**NEEDS_TEMPORAL_MATCH patients with no `patient_zip_missing` encounter: 410**

All 410 NEEDS_TEMPORAL_MATCH patients have zero `patient_zip_missing` encounters in R/122. Definitional reason: R/121 identifies NEEDS_TEMPORAL_MATCH from **encounter row ZIP9 fields** (ZIP9 present on other rows but not on the missing-ZIP5 row). R/122 resolves patient ZIPs from **LDS_ADDRESS_HISTORY** — a separate data source. By the time R/122 runs, these patients' encounter dates are already covered by address history periods, so R/122's ZIP calendar lookup succeeds and does not classify their encounters as `patient_zip_missing`. R/122 has effectively already resolved the ZIP gap that R/121 flagged as needing temporal matching. The discrepancy is wholly explained by the difference in data sources (encounter rows vs. address history CSV).

**D-04 verdict: Explained.** Every non-zero cell in the cross-tab has a reason grounded in the R/121 and R/122 code definitions. No unexplained cells.

---

## Counts

### A. Phase 165 analysis set and candidate encounters

| Row | Enc (whole) | Patients (whole) | Enc (post-anchor) | Patients (post-anchor) | % enc whole | % enc post |
|---|---|---|---|---|---|---|
| Current Phase 165 set (denominator) | 1,585,337 | 7,108 | 1,246,333 | 7,078 | — | — |
| Context: all Phase 165 encounters of NEEDS_TEMPORAL_MATCH patients | 206,343 | 378 | 169,070 | 376 | 13.02% | 13.57% |
| Current far (>100 mi) | 262,431 | — | 211,509 | — | — | — |
| Candidates (patient_zip_missing, all other R/165 filters met) | 3,731 | 84 | 3,205 | 84 | 0.24% | 0.26% |
| Coverable (interval match + non-missing ZIP5) | 0 | — | 0 | — | — | — |
| Coverable but zip_not_in_db | 0 | — | 0 | — | — | — |
| Filled (coverable with a projected distance) | 0 | — | 0 | — | — | — |
| Projected >100 mi among filled | 0 | — | 0 | — | — | — |

**Share filled:** 0% (whole); 0% (post-anchor)
**Far ratio:** 0% (whole); 0% (post-anchor)

**NEEDS_TEMPORAL_MATCH patients in R/121 (context):** 410 patients; none appear in R/122's `patient_zip_missing`.

### B. Candidates by R/121 triage group

| R/121 triage | Encounters (whole) | Patients (whole) | Coverable (whole) | Filled (whole) | Proj >100 mi (whole) | Encounters (post) | Patients (post) | Coverable (post) | Filled (post) | Proj >100 mi (post) |
|---|---|---|---|---|---|---|---|---|---|---|
| UNREACHABLE_NO_ZIP9 | 2,602 | 36 | 0 | 0 | 0 | — | — | 0 | 0 | 0 |
| not in R/121 | 1,101 | 46 | 0 | 0 | 0 | — | — | 0 | 0 | 0 |
| NO_MISSING_ZIP5 | 28 | <11 | 0 | 0 | 0 | — | — | 0 | 0 | 0 |

Note: 938 encounters had an interval address-history match but no ZIP5 in the centroid database (`zip_not_in_db`). These are in the UNREACHABLE_NO_ZIP9 and "not in R/121" groups; the matched ZIP9 codes are not in zipcodeR's reference.

---

## Recommendation

**Tier: Document only.**

D-04 is explained (see above). The mechanical rule applies:

- share_whole = 0%, share_post = 0% → below the 1% inline-fix threshold
- far_ratio_whole = 0%, far_ratio_post = 0% → no far-encounter impact

**Why the counts are zero:** The 3,731 candidate encounters (R/122 `patient_zip_missing`) belong entirely to UNREACHABLE_NO_ZIP9 and "not in R/121" patients — groups where, by definition, no temporal ZIP9 match is available. When `get_zip9_at_date()` is run on these 84 patients, 938 encounters hit interval matches in address history but none yield a usable ZIP5 (`zip_not_in_db`), and the remaining get no match at all. There are 0 coverable encounters, so 0 filled and 0 projected far.

The NEEDS_TEMPORAL_MATCH group (410 patients, 206,343 context encounters in the Phase 165 set) generates **zero** `patient_zip_missing` encounters in R/122 — R/122's address-history calendar already resolves their ZIP at every encounter date. There is nothing for a temporal imputation tier to fill.

**No follow-up phase is warranted.** No inline fix is warranted. The finding should be recorded in planning state for audit purposes.

---

## Caveats

1. Projected distances use matched historical ZIP5 centroids (zipcodeR). No coverable encounters were found, so no projections were computed.
2. Encounters remaining unfillable: 938 interval-matched but `zip_not_in_db`; remaining candidates had no address-history coverage at encounter date. These are UNREACHABLE_NO_ZIP9 and "not in R/121" patients and are not addressable by a temporal ZIP tier.
3. Anchors were loaded from `output/confirmed_hl_cohort.rds` (R/47 output, `first_hl_dx_date`) because the DIAGNOSIS table is absent from the current DuckDB. This is equivalent to `get_hl_any_dx_ids()` for anchor-date purposes; the Phase 165 analysis set built here should match R/165's set modulo any DuckDB-version differences at R/165's run time.
4. R/121 and R/122 inputs are unpinned (most recent by mtime). Repin using `R177_R121_RDS` / `R177_R122_RDS` env vars if a specific validated run is required.
