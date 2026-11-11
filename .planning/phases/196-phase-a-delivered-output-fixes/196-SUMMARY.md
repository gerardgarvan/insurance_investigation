# Phase 196-A: Delivered-Output Fixes + Rerun — SUMMARY

**Status:** Complete  
**Completed:** 2026-11-11  
**Rerun log:** output/logs/phase196_rerun_20261111_0907.log

---

## Fixes Delivered (all committed before rerun)

| Task | Commit | Description |
|------|--------|-------------|
| suppress_small NA fix; phase folder move; cancer_summary reader comments; RERUN-AND-REISSUE updates; check_cohort_fingerprint tool | 435e067 | Phase A follow-up bundle |
| Fix suppress_small applied before arithmetic in R/109 / R/110 | 6637ec4 | Defer suppression to display only; raw integer tables for delta/sort; stopifnot guards; complementary suppression |
| Fix R/109 before/after name collision ($ operator on atomic vector in Section 6 D-03) | eb9dfc3 | Rename source frames to chemo_before/chemo_after; pre-compute scalars before tibble() |
| Fix R/47 overwriting R/46 cancer_summary_table.xlsx | 1afc456 | Rename R/47 output to cancer_summary_refined_table.xlsx; rewire R/48 BASELINE_TABLE_XLSX; update R/39 comment |
| Fix payer_path / n_payer_matched orphaned after load_payer_summary refactor | 61c355a | Attach source_path/source_mtime/n_cohort_matched attrs to return value; fix R/165 KEY rows |
| fix(183): recode payer 'Missing'/'Unknown'/'': to NA before MICE | 4b2579e | 183 sentinel values recoded to NA; replace full loggedEvents print with table(dep,out); D-196 decision in KEY |

---

## Rerun Checkpoints — All PASS

### Core pipeline (R/02, R/14, R/107, R/109, R/110)

- R/02 and R/14: `payer_at_chemo.csv` 4,796 rows — PASS
- R/107: PASS
- R/109: regimen section now populated (before/after name collision fixed); `<11` suppression applied at display only — PASS
- R/110: payer section now populated; `<11` suppression applied at display only — PASS

### Cancer summary (R/45, R/46, R/47)

- R/45: PASS
- R/46: 54 categories / 1,810 codes restored; md5 bee2685cc54d842a7ddc8f5c0e24e79f — PASS
- R/47: 7,696 confirmed HL patients; 52,068 rows; refined table 49 categories / 1,396 codes; R/46 table md5 unchanged after R/47 run — PASS

### Regression (R/165)

- Cell-by-cell regression vs Phase 195 baseline (12.4 min) — PASS

### MICE sensitivity (R/183)

Final run after D-196 payer recode (commit 4b2579e), 90.1 min:

- 183 `'Missing'` values recoded to NA before mice()
- Payer NA: 1,704 (19.7%); imputed with polyreg
- Pooled ORs:
  - D-01 years 2+: 0.846 (0.727–0.986)
  - D-01 all years: 0.913 (0.794–1.051)
  - D-02 years 2+: 0.823 (0.705–0.962)
  - D-02 all years: 0.877 (0.747–1.031)
- Complete-case OR: 0.834 (0.719–0.967) — unchanged
- Max change vs 10/15 baseline (no payer imputation): ≤ 0.02
- **Recommendation:** D-01 as reference MICE result. D-02 far proportion unstable across m (mean 0.150, range 0.054–0.353).

**Outputs ready for re-issue to Amy/Erin.**

---

## R/48 Rerun (2026-11-11, 17:03, 0.7 min) — commit 1deeca2

**Label swap CONFIRMED** for 2026-10-06 delivered version. NHL post-HL count (4,068) sat under "Baseline Patients" with R/46's 5,279 under "Post-HL Patients", giving a spurious 77.1% retained. Corrected file: NHL baseline 4,494 (R/47 refined) / post 4,068 / 90.5% retained.

Join diagnostic:
- 49 categories — 47 joined, 2 baseline-only (post=0), 0 post-only
- Baseline-only rows are the two HL anchor categories (expected; anchor codes excluded from post-HL universe):
  - Hodgkin Lymphoma (non-NLPHL): baseline 7,471 / post 0
  - NLPHL: baseline 1,782 / post 0
- post ≤ baseline guard: PASS

Run facts: confirmed cohort 7,696; post-HL 4,839 patients, 19,388 patient-code rows, 1,154 codes, 47 categories.

Spot checks: Secondary-Other Sites 653/566 (86.7%); Breast 270/245 (90.7%).

No downstream data consumers (R/39, R/87, R/88 reference R/48 by name only). Included in 2026-11-11 re-issue to Amy/Erin.

---

## Phase B Backlog (not implemented)

- Collapse `main_source` UCI level in R/183 (400 loggedEvents per model; also present in 10/15 baseline)
- Review `output/mice_trace_20261111.png`; consider `maxit < 20` (R/183 currently ~90 min)
- Fix `R/tools/check_cohort_fingerprint.R` path: cohort/ dir is under `dirname(CONFIG$cache$outputs_dir)`, not `output/`
- R/02: sort output by ID so reruns are byte-identical
- Drop R/02 from rerun lists when R/14 runs (R/14 calls R/02 internally)

## Phase C Backlog (not implemented)

- R/48 Comparison sheet has no TOTAL row
