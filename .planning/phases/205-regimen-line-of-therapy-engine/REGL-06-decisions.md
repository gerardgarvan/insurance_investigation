# Phase 205 Open Decisions (REGL-06)

These decisions require SME confirmation before Phase 205 results are interpreted.
Current pipeline defaults are shown; they remain in force until a decision is logged
and the config is updated. Open decisions do not block pipeline execution; they affect interpretation only.

Written 2026-11-14 (headless fix: R/88 SMOKE-205-01 [g] expects this exact path; Plan 205-03 Task 2 had not been executed).

| ID | Decision | Current Pipeline Default | Status |
|----|----------|--------------------------|--------|
| REGL-06-A | SME confirmation of the regimen family list (10 families in REGIMEN_DICT) | REGIMEN_DICT in R/00_config.R: ABVD, AVD, BV+AVD, Nivo+AVD, BEACOPP, escBEACOPP, Pediatric, R-CHOP, R-CVP, Salvage, Rituximab_mono, BV_consolidation (NLPHL removed 2026-11-14: a diagnosis, not a regimen) | OPEN |
| REGL-06-B | LOT gap length: treatment-free interval (non-maintenance drugs) that starts a new line | LOT_GAP_DAYS = 90L in R/00_config.R | OPEN |
| REGL-06-C | BV consolidation: maintenance (no new LOT) vs active treatment (new LOT) | Maintenance; BV_consolidation is assigned only when BV-only therapy starts on/after an SCT episode start and within BV_CONSOLIDATION_SCT_WINDOW_DAYS (90, assumed = LOT_GAP_DAYS) after SCT stop; MAINTENANCE_DRUG_CLASSES = c("BV_consolidation", "Rituximab_mono") in R/00_config.R | OPEN |
| REGL-06-D | NLPHL handling: R-CHOP / R-CVP / rituximab mono distinguished or grouped | Interim 2026-11-14: "NLPHL" label removed; R-CHOP, R-CVP and Rituximab_mono are separate families. Histology not used | OPEN |
| REGL-06-E | escBEACOPP vs BEACOPP: dose-level distinction | Same drug set in REGIMEN_DICT; dose not available from administration data alone | OPEN |
| REGL-06-F | Salvage list completeness (ICE/GVD/IGEV, BV-bendamustine, BV-nivolumab, pembrolizumab or nivolumab mono) | Salvage entry holds ifosfamide, carboplatin, etoposide only; others get "Unrecognized systemic" (Chemotherapy) or NA (Immunotherapy) | OPEN |
| REGL-06-G | Concurrency window: days around episode start in which drugs count toward the same regimen | CONCURRENCY_WINDOW_DAYS = 7L in R/00_config.R | OPEN |
| REGL-06-H | ABVD_PLUS vs BV+AVD reconciliation: how Phase 201 `abvd_class` values (ABVD with an added agent; BV+AVD / Nivo+AVD excluded from ABVD) map to Phase 205 `regimen_label` | Phase 205 labels by REGIMEN_DICT (exclusive match); R/205_reconciliation.R cross-tabulates `abvd_class` x `regimen_label` (REGL-05) | OPEN |
| REGL-06-I | D-201-01 (carried from Phase 201): count ABVD + low-dose oral methotrexate (RxNorm 105585) as ABVD? 4 episodes, <11 patients, mostly RA `immune_flag` | No (ABVD_EXCLUDING_DRUGS in R/00_config.R; `abvd_episode` unchanged). Phase 205 ABVD is `exclusive = TRUE`, consistent | OPEN |

## Impact on Phase 205 Results

- **A**: Unlisted regimens get "Unrecognized systemic" (Chemotherapy) or NA (Immunotherapy); "Other" no longer exists. Added families require re-running R/28 and R/205.
- **B**: Shorter gap gives more LOT splits; longer gap gives fewer. 90 days is a common convention; confirm with the analysis team.
- **C**: Reclassifying BV consolidation as active treatment adds a LOT for post-ASCT patients and changes `n_lines`.
- **D**: Separating NLPHL sub-types needs REGIMEN_DICT expansion and histology data.
- **E**: escBEACOPP needs dose data; feasibility depends on the MED_ADMIN/DISPENSING extract.
- **F**: Expanding Salvage needs SME input on qualifying combinations.
- **G**: Wider window merges more near-simultaneous drugs into one regimen; narrower window can split a cycle into partial regimens.
- **H**: Episodes that Phase 201 labelled ABVD-with-added-agent may be labelled "Unrecognized systemic" or Salvage in Phase 205; the reconciliation table quantifies this.
- **I**: Counting methotrexate-added episodes as ABVD would move <11 patients; no effect on cohort membership.

## Notes

- Update Status to RESOLVED with date when the SME confirms a decision, and update config accordingly.
- SCT-triggered LOT boundaries (REGL-06-B TODO in R/205_lot_output.R, R/28) remain pending an SCT schema probe.

## Fix 2026-11-14: labels leaked onto non-systemic episodes (headless fix)

Root cause: `episode_number` is unique only within (patient_id, treatment_type). `assign_regimen()` grouped on (ID, episode_number) and R/28 joined on (patient_id, episode_number), so Chemotherapy labels copied onto Radiation/SCT/Proton episodes with the same number. Changes:
- `assign_regimen()` keys on (ID, treatment_type, episode_number); only Chemotherapy/Immunotherapy rows are returned. Drugs are pooled across the patient's Chemotherapy + Immunotherapy rows within the window so BV+AVD / Nivo+AVD still match.
- No match: Chemotherapy with drug names = "Unrecognized systemic"; otherwise NA. Immunotherapy is labeled only when all its drugs belong to the matched family. "Other" removed.
- NLPHL family replaced by R-CHOP / R-CVP / Rituximab_mono.
- BV_consolidation needs a prior SCT episode (see REGL-06-C).
- R/205 section 1B prints regimen_label x treatment_type and stops if any non-systemic episode is labeled, any "Other" remains, or an Immunotherapy episode is "Unrecognized systemic".

### Reconciliation with R/142 abvd_class (REGL-06-H)

| Label | R/142 delivered 180-day file (old abvd_class) | stage2 label counts, pre-fix run (all 19324 episodes, inflated by leak) |
|---|---|---|
| ABVD | 1109 | 1561 |
| AVD | 236 | 730 |
| BV+AVD | 251 | 739 |
| Nivo+AVD | 42 | 144 |
| ABVD_PLUS | 186 | not a family; maps to "Unrecognized systemic" (ABVD + added agent fails the exclusive match) |

- The two columns are not comparable: the pre-fix counts include non-Chemotherapy episodes that inherited labels and cover all stage2 episodes, not the 180-day episode set.
- Expected after fix: ABVD/AVD/BV+AVD/Nivo+AVD counts fall toward the delivered values; Unrecognized systemic should absorb the 186 ABVD_PLUS episodes plus other unmatched chemotherapy. Differences remaining after the fix are explained by (a) the 7-day pooled window, (b) cross-type pooling, (c) 180-day episode merging in R/142 vs stage2 episodes.
- R/142 still tests `abvd_class == "ABVD_PLUS"` for `ever_abvd_plus`; with the new labels that flag will be all FALSE. Decision needed: derive `ever_abvd_plus` from "Unrecognized systemic" episodes containing all ABVD drugs, or retire the column. Not changed here.

PENDING HIPERGATOR: post-fix counts. After re-running R/28 then R/205, paste the R/205 `QC regimen_label x treatment_type` table (about 25 lines) to complete this table.

```r
module load R/4.5
R --no-save
source("R/28_episode_classification.R", local = new.env(parent = globalenv()))
source("R/205_lot_output.R", local = new.env(parent = globalenv()))
```
