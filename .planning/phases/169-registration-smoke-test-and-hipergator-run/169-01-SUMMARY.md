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
  - "CONFIG$distance_assoc_method = 'rao_scott' (D-165-01); pending confirmation from Amy and Erin"
  - "R/88 exits non-zero (quit(status=1)) when any check FAILs — 88_smoke_test.sbatch propagates FAILED to SLURM via set -e"
  - "Test 4: patient with only anchor-day encounter has E002 (next day) also in fixture, so IS in post-window denominator with any_cbc=0"
metrics:
  duration_minutes: ~25
  completed_date: 2026-10-08
  tasks_completed: 5
  tasks_total: 6
  files_modified: 8
---

# Phase 169 Plan 01: Registration, Smoke Test, and HiPerGator Run — Summary

Tasks 1-5 complete. Task 6 (HiPerGator run) is a `checkpoint:human-action` — awaiting human execution.

**CONFIG$distance_assoc_method current value:** `"rao_scott"` (set in R/00_config.R line 232, D-165-01, 2026-10-08)

**R/88 exits non-zero on FAIL:** YES — `quit(status = 1)` called when `failed > 0` (and `TESTTHAT != "true"`). The `set -e` in `slurm/88_smoke_test.sbatch` propagates this as a SLURM FAILED job state.

---

## Tasks Completed

### Task 1: Register R/165 in R/39; SCRIPT_INDEX rows for R/163 and R/165

- R/165 inserted immediately before R/166 in `R/39_run_all_investigations.R` investigation_scripts vector (line 228, R/166 at line 229).
- R/163 documented in SCRIPT_INDEX as one-off, not in pipeline.
- R/165 SCRIPT_INDEX row references `CONFIG$distance_assoc_method` — no hardcoded method name.
- Script count updated: 25 → 27 post-renumber investigations; total 113 → 115.
- Commit: `e017032`

### Task 2: Memo fixes in code and memo; KEY note from CONFIG

- `naive_or_se()`: `matrix(as.numeric(ct), nrow = 2)` converts to double before arithmetic (integer overflow fix for large-count tables).
- R/165 DEFF comment: `# DEFF = (SE_rao_scott / SE_naive)^2 on the log-OR scale`.
- R/165 svyglm vs GEE note added near Rao-Scott branch: "svyglm with patient clusters gives the same point estimate as a GEE with independence working correlation, with robust (sandwich) standard errors."
- R/165 KEY method row: `paste0("Method (D-165-01): ", CONFIG$distance_assoc_method, " - pending confirmation from Amy and Erin")`.
- R/165 KEY CBC lab caveat: "CBC is captured only for labs recorded at OneFlorida+ partner sites; labs drawn at outside facilities are missing..."
- 165-METHODS.md: svyglm=GEE equivalence note added; outside-lab caveat added.
- Commit: `f274127`

### Task 3: tests/testthat/test-165-distance-cbc-association.R (TDD)

4 test_that blocks, all unconditional assertions:

1. **Overflow regression** — integer storage ct (120000L, 85000L, 95000L, 65000L): `is.finite(log_or)`, `is.finite(se)`, `se > 0`, `!haldane`, `exp(log_or)` == expected double OR (tolerance 1e-9).
2. **suppress_display** — 1 → "<11", 5 → "<11", 10 → "<11", 0 → "0", 11 → "11".
3. **CBC within encounter** — two-day inpatient stay with CBC on both days → 1 row, `cbc_in_encounter = 1`.
4. **Anchor-day exclusion** — fixture with E001 (anchor day, post=0) and E002 (next day, post=1); CBC only on anchor date → P001 in denominator (E002 is post-window) with `any_cbc = 0`; second fixture with CBC on day after anchor → `any_cbc = 1`.

- Commit: `856cfeb`

### Task 4: R/88 Section 15ar — SMOKE-165-01 (15 checks)

15 numbered checks inserted between SECTION 15aq (Phase 168) and SECTION 16 (SUMMARY):

- Always-on [1-10]: R/165 exists, utils_distance_cbc.R exists, CONFIG cutoff==100, method in known set, no bare `\b100\b` on cutoff/distance lines, no quit(), no R/4.4.2, 5 helpers defined, R/39 registration, test-165 exists.
- Output-gated [11-15]: sheet order KEY/A_crosstab/B_test/C_sensitivity/QC, B_test has both windows, far_from_care_100mi in {0,1}, no fan-out (nrow==n_distinct ENCOUNTERID), A_crosstab no numeric cell 1-10.
- Offline: NOTE + PASS for each output-gated check when workbook/RDS absent.
- Stale-output WARNING when `!IS_LOCAL` and date stamp != today (informational, counter unchanged).
- Summary message added to Section 16.
- Commit: `08d58a8`

### Task 5: SLURM wrappers

- `slurm/165_distance_cbc_association.sbatch`: added `set -e`; fixed log name (was `164`, now `165`); added testthat::test_file step before Rscript R/165.
- `slurm/88_smoke_test.sbatch`: created (was absent); `set -e`; `module load R/4.5`; 2 CPUs, 16gb, 02:00:00.
- Both files confirmed to contain `module load R/4.5`.
- Commit: `619c341`

---

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] slurm/165 log name typo**
- Found during: Task 5
- Issue: `logs/164_association_$(date +%Y%m%d).log` — wrong script number in log name
- Fix: Corrected to `165_association_$(date +%Y%m%d).log`
- Files modified: slurm/165_distance_cbc_association.sbatch
- Commit: 619c341

### Test 4 Fixture Design Note

The plan spec for Test 4 says "a patient whose encounter is on the anchor-day may be absent from the post-window set OR have any_cbc = 0". I chose a fixture with both an anchor-day encounter (E001) and a next-day encounter (E002), so the patient IS in the post-window denominator (E002 is post-anchor) but has any_cbc = 0 from anchor-day CBC only. This produces a single unconditional assertion (`any_cbc == 0`), fully satisfying the spec's requirement for no conditional branches.

---

## Task 6: Awaiting HiPerGator Run

**Status:** PENDING — checkpoint:human-action

See plan's `<how-to-verify>` section for exact sbatch commands.

Sacct table, SMOKE footers, workbook paths, and test-165 result from the 165 log to be pasted back after run.

---

## Self-Check: PASSED

All created files confirmed to exist. All 5 task commits confirmed in git log:
- e017032 feat(169-01): register R/165 in R/39; SCRIPT_INDEX rows for R/163 and R/165
- f274127 fix(169-01): memo fixes — overflow, DEFF, svyglm-GEE note, lab caveat, KEY from CONFIG
- 856cfeb test(169-01): add 4 real unit tests for utils_distance_cbc.R helpers
- 08d58a8 feat(169-01): R/88 Section 15ar SMOKE-165-01 with 15 checks
- 619c341 chore(169-01): SLURM wrappers — fix 165 sbatch; create 88 smoke test sbatch
