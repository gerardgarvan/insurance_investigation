# Quick 261114-sir Summary

Done locally: A-H. Parse OK on R/00_config.R, R/28, R/29, R/142, R/205, R/utils/utils_regimen.R and the three 205 test files. Full testthat suite: 0 failed, 5 skipped (HiPerGator-only data).

Changes: see `.planning/phases/205-regimen-line-of-therapy-engine/REGL-06-decisions.md` (section "Second HiPerGator run ... revision").

Test edits: two old LOT tests removed (post-SCT increment, SCT three-line) because SCT no longer starts a line. Four dict-test expectations changed from NA to "Unrecognized systemic" for Immunotherapy/BV-without-SCT.

## Assumptions (headless run)
- Immunotherapy episodes outside any regimen get "Unrecognized systemic" (request: never NA).
- BEAM "near SCT" = within 30 days before/after the SCT episode (`BEAM_SCT_WINDOW_DAYS`).
- Methotrexate-alone + autoimmune relabel applied in R/142 (R/28 has no autoimmune flag); R/205 LOT and R/29 are unaffected because Unrecognized is already excluded.
- LOT families and first-line label list as in REGL-06-decisions.md.
- Baseline reconciliation joins on (patient_id, treatment_type, episode_number, episode_start); stops if that key is not unique.

## PENDING HIPERGATOR
R/205 reconciliation and the R/28 root-cause diagnostic have not run (no data locally). Steps:

```r
module load R/4.5
R --no-save
source("R/28_episode_classification.R", local = new.env(parent = globalenv()))
source("R/142_gantt_180_export.R", local = new.env(parent = globalenv()))
source("R/205_lot_output.R", local = new.env(parent = globalenv()))
```
(R/28 with the same p143 options used for the 180-day pass.) Paste back:
- R/28: lines "Systemic episodes with drug_names..." and "regimen_basis:".
- R/205: QC regimen_label x treatment_type table, abvd_class 204 x 205 cross-tab, patient-level before/after, any `Warning` lines, ">4 lines" QC block.
- R/29 first-line patient count.
Plan status: incomplete until these are pasted.
