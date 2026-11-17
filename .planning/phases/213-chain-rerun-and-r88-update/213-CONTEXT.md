# Phase 213 CONTEXT: Chain Rerun and R/88 Update

Goal: rerun the delivered chain on the 9,179-patient cohort (Phase 212), with backup first and expected-vs-actual counts at every step. Requirements CHAIN-01, CHAIN-02.
Out of scope: cohort membership, the 212 rule, D-201-04, treatment capture.

## Inputs fixed by Phase 212
- `output/confirmed_hl_cohort.rds`: 9,179 patients, 3 columns, 0 NA first_hl_dx_date.
- Old-cohort backup: `output/internal/pre_v315_backup/confirmed_hl_cohort_pre212_20261117_133152.rds` (7,696). Never the `*_intermediate_NAdates_*` file.
- Expected lines at every step (helper `R/tools/213_chain_checks.R`): cohort rows 9,179; cohort distinct IDs 9,179; gantt HL Diagnosis rows 9,179 (R/142 Sec 4C builds one per cohort row with non-NA first_hl_dx_date).

## Chain facts found by code reading (no data opened)
- R/26 and R/28 have no cohort filter (no `confirmed_hl_cohort` reference; treatment codes are pulled table-wide). Expected: episode counts unchanged vs the backup. The rerun is a confirmation, not a count change. If counts do change, stop and report (a different input changed).
- Cohort is applied downstream: R/53 (COHORT_RDS, line 55), R/29, R/52, R/142 (Sec 4C HL Diagnosis rows, line 468+).
- R/28 second pass (p143) uses the options block from 200-02-PLAN.md lines 209-218; `p143_out_rds` is mandatory (D-197 note, 200-02-SUMMARY.md).
- R/142 at HEAD labels abvd_class through `assign_regimen()` (Phase 205 stage2 column) and already drops supportive GnRH agents (`classify_abvd_set`, utils_regimen.R:461) and derives abvd_episode/avd_episode from drug_names (Phase 210). So D-201-01=NO, 205-2=NO and the 210 flags are in the generating code. R/206 as written needs `pre205_run_backup` (Phase 204 labels) and `p205_candidate_v4`, both built on the old 7,696 cohort and 22,548 rows (`EXPECTED_ROWS`), so it cannot run on new patients.
- R/88 is mostly static (greps script text). No hardcoded 7,696 found. It checks R/52 `two_or_more_unique_dates_gt_7` (line ~1940) and 7-day wording (lines ~880-905, ~1903-1980) that describe the old rule.

## Decisions (headless defaults; flagged for review)
- DEC-213-01 (R/206 on new cohort): default = "direct" mode. Rerun R/142 at HEAD on the new cohort, then R/206 in `R206_MODE=direct` verifies the decision rules on that file instead of joining to old files. Rerunning the p205 candidate chain is NOT used (more runs, old-cohort-only reconciliation inputs). Consequence to review: R/142 at HEAD ships Phase 205 regimen labels for all rows, not only ABVD_PLUS rows. This is the open "ship 205 over delivered?" decision (deferred to 2026-12-07). Plan 04 adds a label-diff step (delivered backup vs new, old-cohort patients only) so the size of that change is known before sign-off. Delivered file stays rollback-able from the backup.
- DEC-213-02: R/26 and R/28 are run (user order) but expected unchanged; the plan gates on that.
- DEC-213-03: R/169 gets a new dated output. R/208 default pin is edited to that file name after the run; the old pin stays in the backup list.
- DEC-213-04: R/88 edits are limited to cohort-rule wording checks and new 213 checks. The 9 pre-v3.14 baseline failures must stay exactly 9 and the same 9.
- DEC-213-05: the `cohort/cohort_final.rds` consumer (`R/tools/check_cohort_fingerprint.R`) is a different object; not touched.

## Other cohort readers: rerun now vs later
Rerun now (feed delivered v3.15 outputs, chain-dependent):
- R/169 (plan 01), R/53 and R/52 and R/29 and R/142 (chain), R/206 (plan 04).
- R/208: pins R/169 + R/203 files; rerun after R/169 and R/203 (plan 05 tail, or Phase 214 if no slot).
- R/203: reads cohort; rerun before R/208. Rerun now (plan 05 step, HiPerGator).
Later (analysis tables not in the v3.15 deliverable chain; rerun at the next delivery that needs them):
- R/59 (death summary; run immediately after R/53 only if validated_death_dates deliverable is refreshed; default: with plan 03 as an optional step).
- R/31, R/32, R/34, R/48, R/49, R/77, R/177, R/39 (runner), R/202: not in the CHAIN-01 list. Marked LATER. R/48/R/49 depend on R/47 `cancer_summary` refilter, and R/77 on the cohort venn; all are stale for the new cohort until rerun. Record as a stale-output list in the plan 05 SUMMARY.
- R/115: wording only ("7-day confirmed"); the stability counts are a separate deliverable. LATER; text edit, no rerun.
- R/45 `cancer_summary.csv`: unchanged by the rule (R/47 refilters).

## Assumptions (headless run)
- Planner/checker agents not spawned; plans hand-checked against the three success criteria.
- Script scoping for R/26 (no cohort filter) is from grep only; plan 02 Task 0 confirms with the count comparison.
- Backup list and output names beyond those cited are discovered by globbing on HiPerGator, not assumed (plan 01 prints them).
