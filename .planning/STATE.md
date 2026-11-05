---
gsd_state_version: 1.0
milestone: v3.13
milestone_name: Analytic Manual Fill-out and Verification
status: executing
stopped_at: Completed 194-02-PLAN.md
last_updated: "2026-11-05T18:52:39.203Z"
last_activity: 2026-11-05
progress:
  total_phases: 46
  completed_phases: 37
  total_plans: 126
  completed_plans: 136
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-10-27, v3.13 started)

**Core value:** A working cohort filter chain that reads like a clinical protocol — with logged attrition at every step and clear payer-stratified visualizations showing how patients flow from enrollment through diagnosis to treatment.

**Current focus:** Phase 193 — Produce Updated Manual

## Current Position

Phase: 191 (verify-existing-entries) — COMPLETE 2026-10-28: all 3 plans done; 24 verdicts, 8 D-191-NN decisions (6 OPEN, 2 CONFIRMED); am_verdicts_20261027.xlsx produced; validate passes.
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
Last activity: 2026-11-05

## Phase Map (v3.13)

| Phase | Name | Depends on | Status |
|-------|------|------------|--------|
| 190 | Evidence Map | — | Complete |
| 191 | Verify Existing Entries | Phase 190 | Complete |
| 192 | Draft New Content | Phase 191 | Complete |
| 193 | Produce Updated Manual | Phase 192 | AUTOMATED-QA-PASSED (awaiting WORD-REVIEW-APPROVED) |
| 194 | Team Review Package and Close-out | Phase 193 | Not started |

## Accumulated Context

### Phase 192.3 Decisions (Plan 01)

- **D-192.3-01:** All 15 ENCOUNTER SOURCE values are data partner institution codes (FLM, UMI, UFH, UAB, AVH, AMS, UCI, EMY, ORL, USF, TMA, CHP, NCH, TMC, BND). No Medicare, CMS, or payer-type SOURCE exists. `CONFIG$medicare_source_codes = character(0)`.
- **D-192.3-02:** LDS_ADDRESS_HISTORY has 14 institution SOURCE codes (same set minus UCI). Missing/blank SOURCE = 0. 4,810 patients have overlapping address periods (12,224 rows).
- **Reframing:** `assign_analytic_source()` will use in-effect address SOURCE for `interval_match` and `recency_fallback` encounters; encounter SOURCE for `no_match` encounters. No Medicare-reassignment branch needed.

### Roadmap Evolution

- Phase 192.1 inserted after Phase 192: Rebase v3.13 to the revised Analytic Manual (URGENT)
- Phase 192.2 inserted after Phase 192.1: ICD-9 autoimmune codes in Gantt episodes (URGENT)
- Phase 192.3 inserted after Phase 192.2: Distance >100 mi vs CBC stratified by SOURCE (Medicare reassigned to address source) (URGENT)
- Phase 192.1 renamed from "rebase-v3-13-to-the-revised-analytic-manual" to "autoimmune-diagnosis-flags-in-gantt-episodes" (canonical name)
- Phase 192.1 COMPLETE 2026-10-29: has_autoimmune_dx + first_autoimmune_dx_date added to gantt_episodes.csv and gantt_episodes_180.csv

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

## Session Continuity

**Stopped at:** Completed 194-02-PLAN.md
