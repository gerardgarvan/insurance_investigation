# Quick 261114-r5e — Apply 203 schema probe; share TR treatment logic with R/202

## Changed
- `R/203_no_treatment_characterization.R`: rewritten against `.planning/schemas/203_schema_inputs_20261114.md`. All PENDING/placeholder columns removed; every variable derived per schema §5; sheets unchanged (KEY, A_profile, B_reasons_waterfall, C_by_source, D_candidate_rules, QC), so R/88 SECTION 15bf needs no edit.
- `R/utils/utils_cancer.R`: `TR_MAP`, `CODE_UNKNOWN`, `SCT_GIVEN`, `TR_HIST_COLS`, `tr_row_evidence()`, `collapse_evidence()` moved verbatim from R/202; new `build_tr_treatment_flags(ids, sources, by_source, tr_hl)`; `ENC_DATE_SENTINEL_BEFORE`.
- `R/202_tr_sensitivity.R`: block removed; Section 3b calls `build_tr_treatment_flags()` for `tr_pt_src` (all sources, by_source) and `tr_pt_all` (UFH+ORL). Output unchanged (same collapse code; `tr_unknown_any` renamed `tr_unknown`, only used inside the collapse). E_coverage_window first encounter now filters ADMIT_DATE < 1990-01-01; KEY note says E counts can shift slightly.
- `R/utils/utils_notx.R` (new): `add_notx_flags()`, `assign_notx_reason()`, `NOTX_REASON_LEVELS`.
- `tests/testthat/test-203-notx.R` (new): synthetic tests for TR flags + waterfall.
- `203-HUMAN-UAT.md` item 1 marked passed (schema probe).

## Verification (local)
- `tools/rcheck.sh parse` R/202, R/203, utils_cancer.R, utils_notx.R, test file: 5/5 OK.
- `tools/rcheck.sh test 203`: pass; `test 202`: pass.

## Assumptions (headless run)
- Payer: `load_payer_summary()` returns only `ID` + `PAYER_CATEGORY_PRIMARY` (already patient-level). `classify_payer_tier()` is encounter-level (needs `PAYER_TYPE_PRIMARY/SECONDARY/SOURCE`), so it is not applied; category reported as stored. Note `load_payer_summary()` picks its file by mtime internally (existing util); path recorded in KEY/QC.
- "Newest" input files chosen by sorted file name (dates in names), not mtime.
- "TR says treated" = any given among chemo/radiation/immuno/sct from UFH+ORL HL rows. TMH, hormone, systemic excluded.
- Coverage reason: no usable encounter (NA first encounter) counts as "dx before EHR coverage".
- Waterfall NLPHL reason uses `nlphl_any`; both `nlphl_any` and `nlphl_only` shown in A_profile.
- NOTX-05 rule redefined as: dx date present AND first usable encounter <= dx+90d AND follow-up >= 180d. Not applied to cohort or Gantt.
- SQL for NLPHL: `DX LIKE 'C81%' OR DX LIKE '201%'`, then `classify_codes()`; DX_TYPE not used.

## PENDING HIPERGATOR
```r
module load R/4.5; R --no-save
source("R/203_no_treatment_characterization.R", local = new.env(parent = globalenv()))
```
Paste back: any error + ~20 lines; the `[R203] no_tx ...; treated ...`, `not in cohort: ...` and `KEY FINDING` lines; QC sheet rows.
Also re-run R/202 and paste the `E_coverage_window` rows (counts may shift slightly from the sentinel guard); A_sensitivity should be identical to the prior run.
UAT item 2 (full run + workbook QC) stays pending.
