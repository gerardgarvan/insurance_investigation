# Phase 205 Open Decisions (REGL-06)

These decisions require SME confirmation before Phase 205 results are interpreted.
Current pipeline defaults are shown; they remain in force until a decision is logged
and the config is updated. Open decisions do not block pipeline execution; they affect interpretation only.

Written 2026-11-14 (headless fix: R/88 SMOKE-205-01 [g] expects this exact path; Plan 205-03 Task 2 had not been executed).

| ID | Decision | Current Pipeline Default | Status |
|----|----------|--------------------------|--------|
| REGL-06-A | SME confirmation of the regimen family list (10 families in REGIMEN_DICT) | REGIMEN_DICT in R/00_config.R: ABVD, AVD, BV+AVD, Nivo+AVD, BEACOPP, escBEACOPP, Pediatric, NLPHL, Salvage, BV_consolidation | OPEN |
| REGL-06-B | LOT gap length: treatment-free interval (non-maintenance drugs) that starts a new line | LOT_GAP_DAYS = 90L in R/00_config.R | OPEN |
| REGL-06-C | BV consolidation: maintenance (no new LOT) vs active treatment (new LOT) | Maintenance; MAINTENANCE_DRUG_CLASSES = c("BV_consolidation", "Rituximab_mono") in R/00_config.R | OPEN |
| REGL-06-D | NLPHL handling: R-CHOP / R-CVP / rituximab mono distinguished or grouped | Single "NLPHL" family; rituximab-only episodes match it | OPEN |
| REGL-06-E | escBEACOPP vs BEACOPP: dose-level distinction | Same drug set in REGIMEN_DICT; dose not available from administration data alone | OPEN |
| REGL-06-F | Salvage list completeness (ICE/GVD/IGEV, BV-bendamustine, BV-nivolumab, pembrolizumab or nivolumab mono) | Salvage entry holds ifosfamide, carboplatin, etoposide only; others may fall to "Other" | OPEN |
| REGL-06-G | Concurrency window: days around episode start in which drugs count toward the same regimen | CONCURRENCY_WINDOW_DAYS = 7L in R/00_config.R | OPEN |
| REGL-06-H | ABVD_PLUS vs BV+AVD reconciliation: how Phase 201 `abvd_class` values (ABVD with an added agent; BV+AVD / Nivo+AVD excluded from ABVD) map to Phase 205 `regimen_label` | Phase 205 labels by REGIMEN_DICT (exclusive match); R/205_reconciliation.R cross-tabulates `abvd_class` x `regimen_label` (REGL-05) | OPEN |
| REGL-06-I | D-201-01 (carried from Phase 201): count ABVD + low-dose oral methotrexate (RxNorm 105585) as ABVD? 4 episodes, <11 patients, mostly RA `immune_flag` | No (ABVD_EXCLUDING_DRUGS in R/00_config.R; `abvd_episode` unchanged). Phase 205 ABVD is `exclusive = TRUE`, consistent | OPEN |

## Impact on Phase 205 Results

- **A**: Unlisted regimens fall through to "Other". Added families require re-running R/28 and R/205.
- **B**: Shorter gap gives more LOT splits; longer gap gives fewer. 90 days is a common convention; confirm with the analysis team.
- **C**: Reclassifying BV consolidation as active treatment adds a LOT for post-ASCT patients and changes `n_lines`.
- **D**: Separating NLPHL sub-types needs REGIMEN_DICT expansion and histology data.
- **E**: escBEACOPP needs dose data; feasibility depends on the MED_ADMIN/DISPENSING extract.
- **F**: Expanding Salvage needs SME input on qualifying combinations.
- **G**: Wider window merges more near-simultaneous drugs into one regimen; narrower window can split a cycle into partial regimens.
- **H**: Episodes that Phase 201 labelled ABVD-with-added-agent may be labelled "Other" or Salvage in Phase 205; the reconciliation table quantifies this.
- **I**: Counting methotrexate-added episodes as ABVD would move <11 patients; no effect on cohort membership.

## Notes

- Update Status to RESOLVED with date when the SME confirms a decision, and update config accordingly.
- SCT-triggered LOT boundaries (REGL-06-B TODO in R/205_lot_output.R, R/28) remain pending an SCT schema probe.
