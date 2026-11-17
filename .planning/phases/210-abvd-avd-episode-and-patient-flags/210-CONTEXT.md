# Phase 210: ABVD/AVD Episode and Patient Flags - Context

**Gathered:** 2026-11-17
**Status:** Ready for planning
**Source:** /gsd:plan-phase 210 args + ROADMAP v3.15 + REQUIREMENTS ABVD-01..03

## Phase boundary
- Episodes carry `abvd_episode` / `avd_episode` computed from episode drugs; patients carry `ever_abvd` / `ever_avd`; `ever_abvd_plus` deprecated.
- Out of scope: cohort membership, 7-day confirmation logic, D-201-04.

## Locked decisions
- Drug-level evidence: flags computed from each episode's drug set (`drug_names`), never from `abvd_class`. `abvd_class` stays descriptive.
- `abvd_episode` = Doxorubicin + Bleomycin + Vinblastine + Dacarbazine all present, any other compounds (ABVD_PLUS now TRUE).
- `avd_episode` = Dox + Vin + Dac present, no Bleomycin, any other compounds.
- Config flag `AVD_INCLUDES_BV_NIVO` (default TRUE): TRUE = BV+AVD and Nivo+AVD are `avd_episode` TRUE; FALSE = episodes containing Brentuximab or Nivolumab are `avd_episode` FALSE.
- `abvd_episode` and `avd_episode` mutually exclusive; `stopifnot` in every script that computes them. Flags only TRUE on Chemotherapy rows.
- `ever_abvd = any(abvd_episode)`, `ever_avd = any(avd_episode)` over the patient's full episode history (both may be TRUE).
- `ever_abvd_plus` kept, documented deprecated (old definition: any abvd_class == "ABVD_PLUS").
- KEY sheet / data dictionary list all four flags.
- Blank-drug J-code episodes (old JCODE_ABVD): no drug evidence, so flags FALSE. Open: recorded as an assumption below.

## Assumptions (headless run)
- A1: JCODE_ABVD episodes (blank drug_names, R/28 label ABVD) get abvd_episode FALSE under the drug-evidence rule; the impact table (Phase 211) quantifies the change.
- A2: Drug tokens matched with `split_drug_names()` (utils_regimen.R:35, accepts , and ;) and SUPPORTIVE_AGENTS removed before matching (same as classify_abvd_set).
- A3: Gantt CSV column count grows 32 -> 33 (`avd_episode` and `ever_avd` -> 34). Appended at the end so cols 1-32 are unchanged. R/88 checks that assert 32 columns must be updated in Phase 213 (CHAIN-02); this phase flags the list of those lines.
- A4: R/28, R/29, R/52 do not write/read these flags (grep verified); no code change, only confirm by grep in the plan.
- A5: No new schema probe needed for new logic: it reads `drug_names` and `treatment_type` already present in gantt_episodes_180.csv; Task 0 cites the latest probe/CSV header evidence via the SCHEMA_32 list in R/206 and R/142 and asks for a header probe on HiPerGator.

## Code locations (grep-verified)
- Write: R/142_gantt_180_export.R (~L90-96 schema, L896-920 compute+asserts, L923-1010 QC, L1132-1151 export select)
- Recompute: R/206_apply_decisions_gantt180.R (L50 schema, L95-101, L114-134 QC)
- Read: R/204_gantt_before_after.R (L29 FLAG_COLS), R/205_lot_output.R (L270-421)
- Helper: R/utils/utils_cancer.R classify_abvd_episode (L160); R/utils/utils_regimen.R split_drug_names (L35), classify_abvd_set (L469)
- Config: R/00_config.R L887-902 (ABVD_COMPONENTS etc.)
- Tests: tests/testthat/test-201-abvd-tr-flags.R, test-205-regimen-*.R; R/88 ABVD-TR-201 checks (L7910+), 32-column checks (L7528, L7678)
