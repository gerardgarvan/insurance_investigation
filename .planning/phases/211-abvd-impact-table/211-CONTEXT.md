# Phase 211: ABVD Impact Table - Context

**Gathered:** 2026-11-17 (headless, non-interactive)
**Source:** Gerard's run message, ROADMAP v3.15 Phase 211, REQUIREMENTS ABVD-04, 210-04-SUMMARY.md

## Phase boundary
- One workbook: how Phase 210 drug-composition flags differ from the old abvd_class-derived flags, plus reconciliation with Gerard's one-off R/209.
- Out of scope: cohort membership, 7-day confirmation, D-201-04, any change to R/142 / R/206 flag logic.

## Inputs (pinned, env var + dated default; stop if missing)
- OLD: `R211_OLD180_CSV` default `output/internal/gantt_episodes_180_pre210_20261117_120409.csv` (32 cols; old `abvd_episode` = abvd_class in ABVD/AVD/JCODE_ABVD; old `ever_abvd` = any of it per patient; `ever_abvd_plus` = any ABVD_PLUS).
- NEW: `R211_NEW180_CSV` default `output/gantt_episodes_180.csv` (34 cols, run 2026-11-17).
- R/209 workbook: `R211_R209_XLSX`; path, sheet and labels UNKNOWN. R/209 is not in the repo (skipped; not invented). Plan 03 probes its output on HiPerGator before any code reads it.
- Old/new episode alignment: both files share cols 1-32; script asserts equal row count and row-wise agreement of `patient_id`, `treatment_type`, `drug_names`, and stops on mismatch.

## Reference facts from the 210-04 run (SUMMARY expected-value checks only; never typed into code)
- abvd_episode TRUE 1,254 (ABVD 1,125 + ABVD_PLUS 129); avd_episode 570 (AVD 236, BV+AVD 255, Nivo+AVD 42, ABVD_PLUS 37).
- Base->new abvd_episode: FALSE->TRUE 145; TRUE->FALSE 236.
- ever_abvd 1,169 (old 1,230); ever_avd 520; both 51; ever_abvd_plus 163.
- R/209: pipeline ever_abvd 1,244 (delivered 2026-11-14); ABVD-class-derived 1,052; ever_brentuximab pipeline 954 vs Gantt-text 776 (raw-only 178 from R/142 D-02b).

## Required report content
1. Episode flags old vs new, crosstabbed by `abvd_class`.
2. Patient flags old vs new (ever_abvd, ever_avd, ever_abvd_plus).
3. The 37 ABVD_PLUS episodes with avd_episode TRUE (no bleomycin): count and drug_names pattern table.
4. ABVD-plus-BEACOPP-component episodes now abvd_episode TRUE: drug_names patterns (BEACOPP components from `BEACOPP` list in R/00_config.R ~L4552), <11 suppressed.
5. Reconciliation rows: R/209 1,244 / 1,052 / 163 and ever_brentuximab 954 vs 776 (raw-only 178, R/142 D-02b), read by exact label from the pinned R/209 output.
6. Patient ever_abvd x ever_avd crosstab.

## Assumptions (headless run)
- A1: "old" episode flag = Phase 201 definition, taken from the pre210 CSV's own `abvd_episode` column, not recomputed.
- A2: BEACOPP component list read from config at run time; the four ABVD drugs do not count as "extra".
- A3: drug_names pattern tables show the sorted drug-set string; counts 1-10 -> `<11`; no patient IDs, dates or ZIPs in the workbook.
- A4: R/209 absent from the repo, so not saved. Reconciliation is PENDING HIPERGATOR (probe first, per CLAUDE.md "names from probes"); the other sheets do not depend on it.
- A5: Arial font, UF blue #0021A5 headers, orange #FA4616 accent, KEY leftmost; output `output/211_abvd_impact_<RUN_DATE>.xlsx`, copied unchanged into the phase folder at close-out.
- A6: Script R/211_abvd_impact_table.R; helpers R/utils/utils_abvd_impact.R (pure functions, fixture-tested).
