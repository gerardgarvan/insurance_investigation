---
phase: 169-registration-smoke-test-and-hipergator-run
plan: 01
subsystem: distance-cbc-association
tags: [registration, smoke-test, testing, slurm, r165, r88]
dependency_graph:
  requires: [R/122 enc_distance RDS, R/116 SES RDS, R/147 cbc anchor dates, DuckDB LAB_RESULT_CM]
  provides: [R/165 registered in pipeline, SMOKE-165-01 checks, test-165 unit tests, 88_smoke_test.sbatch]
  affects: [R/39_run_all_investigations.R, R/SCRIPT_INDEX.md, R/88_smoke_test_comprehensive.R]
tech_stack:
  added: [testthat test for utils_distance_cbc.R, 88_smoke_test.sbatch]
  patterns: [SMOKE section pattern from 15aq, TDD test structure]
key_files:
  created:
    - tests/testthat/test-165-distance-cbc-association.R
    - slurm/88_smoke_test.sbatch
  modified:
    - R/39_run_all_investigations.R
    - R/SCRIPT_INDEX.md
    - R/utils/utils_distance_cbc.R
    - R/165_distance_cbc_association.R
    - .planning/phases/165-distance-100mi-indicator-and-cbc-association/165-METHODS.md
    - R/88_smoke_test_comprehensive.R
    - slurm/165_distance_cbc_association.sbatch
decisions:
  - "CONFIG$distance_assoc_method = 'rao_scott' (D-165-01; confirmed in HiPerGator run); pending team confirmation from Amy and Erin"
  - "R/88 exits non-zero on FAIL: quit(status=1) at source line 6772 when failed > 0; verified from code"
  - "Test 4 fixture: patient has E002 (next-day encounter) making them post-window denominator member; anchor-day CBC gives any_cbc=0 — single unconditional assertion"
metrics:
  duration_minutes: ~30
  completed_date: 2026-10-08
  tasks_completed: 6
  tasks_total: 6
  files_modified: 8
---

# Phase 169 Plan 01: Registration, Smoke Test, and HiPerGator Run — Summary

Registration gaps for Phase 165 closed; SMOKE-165-01 added (15 checks, all PASS on HiPerGator); real unit tests for utils_distance_cbc.R helpers written and passing; four phase workbooks re-issued with 2026-10-08 date stamp.

**CONFIG$distance_assoc_method:** `"rao_scott"` (R/00_config.R line 232; D-165-01; pending confirmation from Amy and Erin)

**R/88 exits non-zero on FAIL:** YES — `quit(status = 1)` at source line 6772 when `failed > 0` and `TESTTHAT != "true"`. Verified from code. The `set -e` in `slurm/88_smoke_test.sbatch` propagates this as a SLURM FAILED state.

---

## HiPerGator Run Results (Task 6)

### Job Outcomes

| Script | Status | Output |
|--------|--------|--------|
| R/165 distance_cbc_association | COMPLETE | output/distance_cbc_association_20261008.xlsx |
| R/166 survivorship modality rates | COMPLETE | survivorship_modality_rates_parts_20261008.rds |
| R/167 anthracycline echo | COMPLETE | survivorship_echo_parts_20261008.rds |
| R/168 survivorship workbook | COMPLETE | survivorship_modality_rates_20261008.xlsx |
| R/169 single source care | COMPLETE | output/single_source_care_20261008.xlsx |
| R/88 smoke test | 912/914 PASS | 2 pre-existing failures (unrelated to Phase 169) |

### SMOKE-165-01: 15 PASS / 0 FAIL

All 15 Phase 165 structural checks passed in Section 15ar.

### R/88 Pre-existing Failures (not Phase 169)

1. DRUG_NAME_ALIASES missing adriamycin + liposomal dox keys — Phase 164 backlog
2. episode_classification_audit.xlsx missing 'Linkage Improvement' sheet — R/30 output not regenerated

### Workbook Paths (all dated 20261008)

- `output/distance_cbc_association_20261008.xlsx`
- `/blue/erin.mobley-hl.bcu/clean/rds/outputs/survivorship_modality_rates_20261008.xlsx`
- `output/single_source_care_20261008.xlsx`

### R/165 Observations

- Integer overflow warnings RESOLVED — no longer present after the `as.numeric()` fix.
- "no weights" from `svydesign()` is expected (equal-probability design).
- Payer RDS not found: expected; sensitivity model ran without payer covariate.
- Elapsed: 1.6 min.

### R/167 Notes

- `deaths_resolved` not found; death as competing event not applied (expected).
- D-08a/D-166-02 fallback active: `first_line` absent, all episodes treated as first-line.

---

## Tasks Completed

### Task 1: Register R/165 in R/39; SCRIPT_INDEX rows for R/163 and R/165 — Commit e017032

- R/165 at line 228, R/166 at line 229 in investigation_scripts vector.
- R/163 documented in SCRIPT_INDEX as one-off, not in pipeline.
- R/165 SCRIPT_INDEX row: references `CONFIG$distance_assoc_method`, no hardcoded method name.
- Script count: 25 → 27 post-renumber investigations; total 113 → 115.

### Task 2: Memo fixes in code and memo; KEY note from CONFIG — Commit f274127

- `naive_or_se()`: `matrix(as.numeric(ct), nrow = 2)` — overflow fix confirmed resolved on HiPerGator.
- DEFF comment: `# DEFF = (SE_rao_scott / SE_naive)^2 on the log-OR scale`.
- svyglm vs GEE equivalence note near Rao-Scott branch.
- KEY method row: `paste0("Method (D-165-01): ", CONFIG$distance_assoc_method, " - pending confirmation from Amy and Erin")`.
- KEY CBC lab caveat: outside-facility labs missing note.
- 165-METHODS.md: svyglm=GEE note and outside-lab caveat added.

### Task 3: tests/testthat/test-165-distance-cbc-association.R — Commit 856cfeb

4 unconditional test_that blocks; run as first step of slurm/165 job on HiPerGator.

1. Overflow regression: large integer-storage ct → finite OR, finite SE, correct double OR.
2. suppress_display: 0 → "0"; 1,5,10 → "<11"; 11 → "11".
3. Two-day inpatient CBC → 1 row, `cbc_in_encounter = 1`.
4. Post-window: anchor-day CBC → `any_cbc = 0`; next-day CBC → `any_cbc = 1`.

### Task 4: R/88 Section 15ar — SMOKE-165-01 (15 checks) — Commit 08d58a8

Inserted between SECTION 15aq and SECTION 16. Result: **15 PASS / 0 FAIL**.

### Task 5: SLURM wrappers — Commit 619c341

- `slurm/165_distance_cbc_association.sbatch`: `set -e`; log name fixed (164→165); testthat step added before R/165.
- `slurm/88_smoke_test.sbatch`: created; `set -e`; `module load R/4.5`; 2 CPUs, 16gb, 02:00:00.

### Task 6: HiPerGator run

All phase scripts and R/88 completed. SMOKE-165-01: 15 PASS / 0 FAIL. Two pre-existing R/88 failures deferred.

---

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] slurm/165 log name typo**
- Found during: Task 5
- Issue: Log name was `164_association_...` — wrong script number
- Fix: Corrected to `165_association_...`
- Files modified: slurm/165_distance_cbc_association.sbatch
- Commit: 619c341

### Design Decisions

**Test 4 fixture:** Plan said patient may be "absent OR have any_cbc=0". The function's denominator is patients with ≥1 post-anchor encounter (post_anchor==1). Fixture includes E002 (next-day, post=1), so patient IS in denominator; anchor-day CBC is not > anchor_date → any_cbc=0. One unconditional assertion, no conditional branch.

---

## Deferred Items

- DRUG_NAME_ALIASES adriamycin/liposomal keys (Phase 164 backlog) — pre-existing R/88 failure
- episode_classification_audit.xlsx Linkage Improvement sheet — R/30 needs regeneration, pre-existing
- 165-CONTEXT.md D-165-01 pending-confirmation status update — per 169-CONTEXT.md "Deferred Ideas"
- utils_distance_hist.R SCRIPT_INDEX utility entry — per 169-CONTEXT.md "Deferred Ideas"

---

## Self-Check: PASSED

All created files exist. All task commits present in git log:
- e017032 feat(169-01): register R/165 in R/39; SCRIPT_INDEX rows for R/163 and R/165
- f274127 fix(169-01): memo fixes — overflow, DEFF, svyglm-GEE note, lab caveat, KEY from CONFIG
- 856cfeb test(169-01): add 4 real unit tests for utils_distance_cbc.R helpers
- 08d58a8 feat(169-01): R/88 Section 15ar SMOKE-165-01 with 15 checks
- 619c341 chore(169-01): SLURM wrappers — fix 165 sbatch; create 88 smoke test sbatch
- 2cb0b1b docs(169-01): complete Tasks 1-5; SUMMARY and STATE updated
