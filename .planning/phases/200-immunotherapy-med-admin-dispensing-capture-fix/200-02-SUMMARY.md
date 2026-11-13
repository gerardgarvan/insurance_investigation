# Phase 200-02: Immunotherapy Episode Enrichment — Summary

**Completed:** 2026-11-12  
**Status:** Complete

## What Changed

R/142 and R/88 updated to handle `raw_history=TRUE` in `build_immune_flags()` (introduced Phase 199 D-02b). Key fix: check [f] in R/88 was stale — it only checked Gantt `drug_names` tokens, missing patients flagged via raw MED_ADMIN/PRESCRIBING history.

## Gantt Episode Counts (before → after Phase 200 rerun)

**180-day Gantt:**

| Row type | Episodes (before) | Patients (before) | Episodes (after) | Patients (after) |
|---|---|---|---|---|
| Chemo | 8,155 | 4,498 | 8,194 | 4,502 |
| Immunotherapy | 2,723 | 1,645 | 3,211 | 1,888 |
| Death | unchanged | — | unchanged | — |
| HL Dx | unchanged | — | unchanged | — |
| Proton | unchanged | — | unchanged | — |
| Radiation | unchanged | — | unchanged | — |
| SCT | unchanged | — | unchanged | — |

**90-day Gantt:**

| Row type | Episodes (before) | Patients (before) | Episodes (after) | Patients (after) |
|---|---|---|---|---|
| Chemo | 12,205 | 4,498 | 12,256 | 4,502 |
| Immunotherapy | 3,797 | 1,645 | 4,583 | 1,888 |

## R/142 QC (Phase 200 rerun)

- `immune_flag = TRUE`: 98 patients (Case 1 only 46, Case 2 only 38, both 14)
- `ever_brentuximab = TRUE`: 954
- `immune_flag_dx` label counts: RA 96, GPA <11, PV <11, MPA 0
- `immune_flag` is a subset of `has_autoimmune_dx` (confirmed)

**Drug exposure union (Gantt + raw history):**

| Drug | Gantt | Raw-only | Total union |
|---|---|---|---|
| Rituximab | 462 | 310 | 772 |
| Methotrexate | 245 | 26 | 271 |
| Brentuximab | 775 | 179 | 954 |

## check_199 Raw-Only Findings

- Brentuximab raw-only via MED_ADMIN code 184 → 0 (no code-based captures remain)
- Remaining raw-only captures are name-based: Rituximab 298, MTX 24, Brentuximab 175 (via MED_ADMIN name)

## Stale Input Finding

`treatment_episodes_180_enriched.rds` was stale since 2026-10-06. After D-197, the step-5 command in 200-02-PLAN.md lacked `p143_out_rds`, so R/28 was overwriting `treatment_episodes_stage2.rds` instead of writing the enriched file. The Phase 199 R/142 run used this stale input. Regenerated 2026-11-12 with the corrected command. Plan patched (Task 3).

## R/88 Results

- 1,085 checks total: 10 FAIL = 9 baseline + IMMUNE-FLAG-199 [f] (stale test, now fixed)
- IMMUNE-FLAG-199 [f] scope: <11 of 98 `immune_flag=TRUE` patients are flagged via raw history only (no Gantt `drug_names` token)
- Fix applied: check [f] updated to union check (Gantt OR `immune_flag_exposure_ids.rds`); check [f2] added for one-direction completeness

## Backlog (Phase 201 candidates)

- (a) R/26 name-based MED_ADMIN capture or missing codes — Phase 201 candidate
- (b) MTX 24 and BV 19 patients in Gantt-only (raw search lacks NDC crosswalk)
- (c) Spot-check RAW_MEDADMIN_MED_NAME rituximab matches (431 patients via name)
- (d) Multivitamins via PRESCRIBING (261 vitamin confidence flags)
- (e) R/25 old immuno logic review
- (f) Chemo_combos "Rituximab/Hyaluronidase" classification
- (g) Stray `.planning/phases/01-immune-brentuximab-*` directory cleanup
