---
gsd_state_version: 1.0
milestone: v3.3
milestone_name: Rituximab/Methotrexate-Associated Diagnoses of Interest
status: Executing Phase 199
last_updated: "2026-11-12T20:13:13.760Z"
last_activity: 2026-11-12 -- Phase 199 execution started
progress:
  total_phases: 190
  completed_phases: 162
  total_plans: 370
  completed_plans: 371
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-10-27, v3.13 started)

**Core value:** A working cohort filter chain that reads like a clinical protocol — with logged attrition at every step and clear payer-stratified visualizations showing how patients flow from enrollment through diagnosis to treatment.

**Current focus:** Phase 199 — immune-brentuximab-flags-gantt-episodes-180

## Current Position

Phase: 199 (immune-brentuximab-flags-gantt-episodes-180) — EXECUTING
Plan: 1 of 2
Phase: 192 (draft-new-content) — COMPLETE 2026-10-28: all 3 plans done; AM-DRAFT.md with sourced sections for all MISMATCH/PARTIAL leads; verification 16/16 passed.
Phase 192.3 COMPLETE 2026-11-04: all 3 plans done; R/181 produces 9-sheet workbook with SOURCE stratification; regression check passed on HiPerGator.
Phase 193 (produce-updated-manual) — AUTOMATED-QA-PASSED 2026-11-05 (Plans 01–04 complete):

  - Output DOCX: docs/analytic_manual/AnalyticManual_2026.10.28.docx
    SHA-256: 74ebe4e05ec5d805cd850bf5fc3f4cc922adca12ae36810e5158fe4761f663e1

  - Evidence workbook: output/am_evidence_20261028.xlsx (KEY, Operations, Open Items, Reconciliation)
  - Reply outcomes: c0=THREADED-REPLY, c1=THREADED-REPLY
  - D-15 QA: package checks=PASS, reconciliation=PASS, pandoc=PASS, LibreOffice=SKIP(not installed), export regression=PASS
  - 324 revisions issued, 12 comments added
  - D-193-01 resolved: new versioned copy used (default)
  - NEXT GATE: WORD-REVIEW-APPROVED (Plan 05) — Phase 193 is NOT complete until human Word review passes.
    Required checks: file opens without repair; tracked changes visible attributed to Gerard Garvan;
    accept/reject works on a sample; c0/c1 replies show under Amy's comments; no layout damage.
Phase 194 (reference-manual-regeneration) — COMPLETE 2026-11-06: all 4 plans done; R/89 rewrote with dynamic discovery, header parser, three-digit stage grouping, coverage gate; 8 scripts backfilled with five-field banners; docs/REFERENCE_MANUAL.md regeneration ready for HiPerGator.
Last activity: 2026-11-13 - Completed quick task 261112-tfm: Fix R/88 [f2] check to use IMMUNE_FLAG_DX_CODES set instead of has_autoimmune_dx proxy

## Phase Map (v3.13)

| Phase | Name | Depends on | Status |
|-------|------|------------|--------|
| 190 | Evidence Map | — | Complete |
| 191 | Verify Existing Entries | Phase 190 | Complete |
| 192 | Draft New Content | Phase 191 | Complete |
| 193 | Produce Updated Manual | Phase 192 | AUTOMATED-QA-PASSED (awaiting WORD-REVIEW-APPROVED) |
| 194 | Reference Manual Regeneration | Phase 193 | Complete |

## Accumulated Context

### Phase 200 Team Decision (D-200-01)

- **D-200-01 (2026-11-12, team):** Gantt treatment episodes capture ALL rituximab / methotrexate / immunotherapy administrations regardless of indication. Patients whose rituximab/MTX use may be for an autoimmune condition are identified by the Phase 199 `immune_flag` (with `immune_flag_dx` for the qualifying diagnosis), not removed from the timelines. No indication-based filtering is applied in R/26 or any downstream script.

### Phase 192.3 Decisions (Plan 01)

- **D-192.3-01:** All 15 ENCOUNTER SOURCE values are data partner institution codes (FLM, UMI, UFH, UAB, AVH, AMS, UCI, EMY, ORL, USF, TMA, CHP, NCH, TMC, BND). No Medicare, CMS, or payer-type SOURCE exists. `CONFIG$medicare_source_codes = character(0)`.
- **D-192.3-02:** LDS_ADDRESS_HISTORY has 14 institution SOURCE codes (same set minus UCI). Missing/blank SOURCE = 0. 4,810 patients have overlapping address periods (12,224 rows).
- **Reframing:** `assign_analytic_source()` will use in-effect address SOURCE for `interval_match` and `recency_fallback` encounters; encounter SOURCE for `no_match` encounters. No Medicare-reassignment branch needed.

### Roadmap Evolution

- Phase 192.1 inserted after Phase 192: Rebase v3.13 to the revised Analytic Manual (URGENT)
- Phase 192.2 inserted after Phase 192.1: ICD-9 autoimmune codes in Gantt episodes (URGENT)
- Phase 192.3 inserted after Phase 192.2: Distance >100 mi vs CBC stratified by SOURCE (Medicare reassigned to address source) (URGENT)
- Phase 192.4 inserted after Phase 192.3: Distance x CBC telehealth payer source composition (URGENT)
- Phase 192.1 renamed from "rebase-v3-13-to-the-revised-analytic-manual" to "autoimmune-diagnosis-flags-in-gantt-episodes" (canonical name)
- Phase 192.1 COMPLETE 2026-10-29: has_autoimmune_dx + first_autoimmune_dx_date added to gantt_episodes.csv and gantt_episodes_180.csv
- Phase 199 added: Immune and Brentuximab Flags in gantt_episodes_180 (immune_flag, ever_brentuximab, immune_flag_dx cols 24–26 via R/142)
- Phase 200 added: Immunotherapy MED_ADMIN/DISPENSING capture fix — switch R/26 extract_immunotherapy_dates_with_codes() from RXNORM_CUI filter to get_chemo_hits()-style matching; add rituximab codes + biosimilar HCPCS; rerun R/26→R/28→R/29→R/52→R/142
- Phase 200 rescoped (2026-11-12): the R/26 fix and code additions were already implemented in Phase 199. Phase 200 records the team analytic decision: D-200-01.

### v3.13 Milestone Context

- Phase numbering continues from v3.12 (Phases 185–189); v3.13 starts at Phase 190
- Milestone supersedes Phase 156 (AM §4 write-back, dropped 2026-10-09 — manual was not available in the repo; it is now)
- Ground rules: no pipeline behavior changes; all drafted statements require source citations; mismatches become team decisions (D-191-NN)
- A standalone `R/190_cbc_encounter_distance.R` was drafted outside GSD on 2026-10-23 — check SCRIPT_INDEX before assigning script slots
- Inputs to copy to `docs/analytic_manual/` before Phase 190: AnalyticManual_2026.01.30.docx, TeamMtgNotes2026.docx, VariableDetails.xlsx; OneFLquestions document status unknown (D-190-01)

### Known Leads for Phase 191 Verification

| # | AM location | Likely verdict |
|---|-------------|----------------|
| L1 | §4 Source | Check — LNK in ENCOUNTER vs DEMOGRAPHIC |
| L2 | §4 Insurance | Check — 6-tier manual vs 8-tier/8-category code |
| L3 | §4 Cancer Diagnosis Date | Check — TR-first rule vs code |
| L4 | §4 Cancer Diagnosis | Check — HL-only vs all cancer types for 7-day rule |
| L5 | §4 ADI | Check — manual likely out of date |
| L6 | §4 Death | Check — 14-day rule and NHL flag usage |
| L7 | §4 Distance | Mismatch — method and cutoff differ |
| L8 | §4 Treatment window | Partial — parked pending Sharon |
| L9 | §4 Survivorship | Update — codeset now in repo |

### Open Team Decisions for v3.13

| ID | Question | Default if no answer |
|----|----------|----------------------|
| D-190-01 | Location of the OneFLquestions document | Proceed without it; list as a gap in §8 |
| D-190-02 | Data freeze label to use in Front Matter | Extract filename + DuckDB build date |
| D-191-01..08 | see AM-EVIDENCE-MAP.md AM-MAP-03 (6 open, 2 manual-update-only) | — |
| D-193-01 | Tracked changes in the original file vs a new versioned copy | New versioned copy (recommended) |

### Carried from v3.12

- R/88 ALL CHECKS PASSED 2026-10-23 (Sections 15av–15az, Phase 185–189 scripts)
- R/88 ALL AUTOIMMUNE-FLAG checks PASSED 2026-10-29 (Section 15ba, Phase 192.1, 29 checks)
- Phase 192.1 decisions: 4460/6944 broader ICD-9 codes included; 71432/71433/3571/3596 excluded per GEM; SENTINEL_CUTOFF promoted to config; detail CSVs excluded from column injection; D-09 branch determined at R/170 runtime
- Survivorship cohort: 9,331 patients (R/147 baseline 2026-09-25)
- Anthracycline exposure variables in output/internal/ (Phase 187)
- Echo rate since last anthracycline = 0.2501/py (Phase 188)
- D-165-01 / D-09 carry-forward: Amy/Erin method confirmation still pending

### R/165 Backlog (Phase 195 close-out, 2026-11-10)

- **Regression check fix (D-165-11):** Select prior workbook BEFORE writing, honoring `R1923_PRIOR_DIST_CBC_WB` first, else newest file with run date < current run date. Never overwrite an existing same-date output silently — version as _v2/_v3 or add HHMM. `stop()` if prior path == new path.
- **Unattributed CBC events by SOURCE:** Record 17,384 unattributed (of 126,474) as a KEY/QC row split by SOURCE.
- **Decision pending Amy/Erin:** D-165-01 (Rao-Scott primary) and D-165-07 (D_excl_FLM role).
- **SOURCE_REASSIGN_QC cleanup:** Remove stray "Label" row; add title row for the second table (Task 4.5 incomplete).
- **D_excl_FLM / E_source_composition row 1:** Remove "X" placeholder (same issue already fixed on A_crosstab).
- **C_sensitivity coefficient table:** Confirm SOURCE coefficients are now |log-OR| < 5; full-precision raw log-odds in display (3.3 incomplete).
- **MH_POOLED chi_stat:** Populate MH chi2 column (currently blank, only p shown).

### Parked Items (no phases this milestone)

- End-of-treatment date rules (pending Sharon)
- Data-completeness check vs Medicaid claims
- D-15 primary analysis and D-165-01 method confirmation (awaiting Amy/Erin)
- Anthracycline as a covariate in the R/184 interaction model
- New CBC models beyond Phase 181/183 year-1 analysis

### HiPerGator Run Pattern (standard)

```r
module load R/4.5
R --no-save
source("R/<NNN>_<script>.R", local = new.env(parent = globalenv()))
```

## Quick Tasks Completed

| # | Description | Date | Commit | Directory |
|---|-------------|------|--------|-----------|
| 261106-ize | Write phase 194 SUMMARY.md, update STATE.md to mark Phase 194 complete, and update ROADMAP.md to mark Phase 194 and v3.13 milestone as shipped | 2026-11-06 | 5bf4445 | [261106-ize-write-phase-194-summary-md-update-state-](./quick/261106-ize-write-phase-194-summary-md-update-state-/) |
| 261110-165-fix | Pin distance to 20261015, fix payer 1j to read CSV (fatal on missing), fatal has_payer branch; D-165-02 and D-165-03 decision entries | 2026-11-10 | 5d442e0 | R/165_distance_cbc_association.R |
| 261110-luq | Write R/tools/dep_map.R — static dependency mapper (AST-based, 10 sections, five outputs, R1–R9 risk report) | 2026-11-10 | 4c5a7e3 | [261110-luq-build-static-dependency-map-of-r-code](./quick/261110-luq-build-static-dependency-map-of-r-code/) |
| 261111-c91 | Update phase 192.4 frontmatter in CONTEXT, PLAN, SUMMARY | 2026-11-11 | 53faa42 | [261111-c91-update-phase-192-4-frontmatter-in-contex](./quick/261111-c91-update-phase-192-4-frontmatter-in-contex/) |
| 261111-ce7 | Phase A follow-ups: suppress_small NA fix, phase folder move, cancer_summary reader comments, RERUN-AND-REISSUE updates, check_cohort_fingerprint tool | 2026-11-11 | 435e067 | [261111-ce7-phase-a-follow-ups-suppress-small-na-fix](./quick/261111-ce7-phase-a-follow-ups-suppress-small-na-fix/) |
| 261111-cxn | Fix suppress_small applied before arithmetic in R/109/R/110: defer to display-only; raw integer tables for delta/sort; stopifnot guards; complementary suppression | 2026-11-11 | 6637ec4 | [261111-cxn-fix-suppress-small-applied-before-arithm](./quick/261111-cxn-fix-suppress-small-applied-before-arithm/) |
| 261111-e1j | Fix R/109 before/after name collision ($ operator on atomic vector in Section 6 D-03): rename source frames to chemo_before/chemo_after, pre-compute scalars before tibble() | 2026-11-11 | eb9dfc3 | [261111-e1j-fix-r-109-before-after-name-collision-ca](./quick/261111-e1j-fix-r-109-before-after-name-collision-ca/) |
| 261111-e84 | Fix R/47 overwriting R/46 cancer_summary_table.xlsx: rename R/47 OUTPUT_TABLE_XLSX to cancer_summary_refined_table.xlsx; rewire R/48 BASELINE_TABLE_XLSX; update R/39 comment; RERUN-AND-REISSUE updated | 2026-11-11 | 1afc456 | [261111-e84-fix-r-47-overwriting-r-46-cancer-summary](./quick/261111-e84-fix-r-47-overwriting-r-46-cancer-summary/) |
| 261111-eqg | Fix payer_path / n_payer_matched orphaned after load_payer_summary refactor: attach source_path/source_mtime/n_cohort_matched attrs to return value; fix R/165 KEY rows; R/183 confirmed clean | 2026-11-11 | 61c355a | [261111-eqg-fix-payer-path-leftovers-after-load-paye](./quick/261111-eqg-fix-payer-path-leftovers-after-load-paye/) |
| 261112-t3s | Phase 200 post-rerun fixes: R/88 [f] union check + [f2], R/142 staleness guard + exposure RDS, 200-02-PLAN.md p143_out_rds, 200-02-SUMMARY.md | 2026-11-13 | 957e3df | [261112-t3s-phase-200-post-rerun-fixes-update-r-88-r](./quick/261112-t3s-phase-200-post-rerun-fixes-update-r-88-r/) |
| 261112-tfm | Fix R/88 [f2] check to use IMMUNE_FLAG_DX_CODES set instead of has_autoimmune_dx proxy | 2026-11-13 | 11f3f09 | [261112-tfm-fix-r-88-f2-check-to-use-immune-flag-dx-](./quick/261112-tfm-fix-r-88-f2-check-to-use-immune-flag-dx-/) |

## Session Continuity

| 261111-hrc | fix(183): recode payer 'Missing'/'Unknown'/'' to NA before MICE; replace full loggedEvents print with table(dep,out); D-196 decision in KEY; RERUN-AND-REISSUE updated | 2026-11-11 | 4b2579e | inline |

## Phase 196-A Complete

Phase 196-A (Delivered-Output Fixes + Rerun) — **COMPLETE 2026-11-11**: all fixes committed (1afc456, 61c355a, 4b2579e and earlier); full pipeline rerun PASS (log: output/logs/phase196_rerun_20261111_0907.log); R/183 MICE final run complete (90.1 min, D-01 pooled OR 0.846 [0.727–0.986] years 2+); outputs re-issued to Amy/Erin. Phase B backlog recorded in 196-SUMMARY.md.

## Session Continuity

Phase 197 — **COMPLETE 2026-11-12** (commit 7d76eed). All HiPerGator verification steps PASS:

- Step 5 `check_cohort_fingerprint.R`: PASS — 8,770 rows, 8,770 IDs, md5 4cee245c…
- Step 6 `mice_convergence_diagnostic.R`: PASS — 11 imputed vars extracted; all continuous/binary vars converge within maxit=20; D-197-12 resolved: keep maxit=20, no rerun.
- Step 7 `dep_map.R` v6: PASS — gate 15/15; resolve_input() 100% resolved (n=14); zero critical run-order or duplicate-writer findings.

**Open items carried forward (not blocking closure):**

- D-197-10: UCI facility ZIP — 29,158 UCI encounters blank FACILITY_LOCATION; 211 patients; awaiting Amy/Erin.
- D-197-11: override CSV implementation in R/183 — gates on D-197-10.
- 48 patients NA main_source: data quality gap, unconfirmed cause.
- chemo_rxnorm SME scope (oral MTX 2.5 mg, gemcitabine, carboplatin, etoposide, bendamustine): awaiting SME.
- Phase C backlog: unchanged.

**Phase 198 scaffold:** `198-CONTEXT.md` created; gates on chemo_rxnorm SME confirmation.
