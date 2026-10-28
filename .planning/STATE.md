---
gsd_state_version: 1.0
milestone: v3.3
milestone_name: Rituximab/Methotrexate-Associated Diagnoses of Interest
status: executing
stopped_at: Completed 191-02-PLAN.md
last_updated: "2026-10-28T03:04:40.887Z"
last_activity: 2026-10-28
progress:
  total_phases: 176
  completed_phases: 154
  total_plans: 335
  completed_plans: 339
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-10-27, v3.13 started)

**Core value:** A working cohort filter chain that reads like a clinical protocol — with logged attrition at every step and clear payer-stratified visualizations showing how patients flow from enrollment through diagnosis to treatment.

**Current focus:** Phase 191 — verify-existing-entries

## Current Position

Phase: 191 (verify-existing-entries) — EXECUTING
Plan: 3 of 3
Status: Ready to execute
Last activity: 2026-10-28

## Phase Map (v3.13)

| Phase | Name | Depends on | Status |
|-------|------|------------|--------|
| 190 | Evidence Map | — | Complete |
| 191 | Verify Existing Entries | Phase 190 | Not started |
| 192 | Draft New Content | Phase 191 | Not started |
| 193 | Produce Updated Manual | Phase 192 | Not started |
| 194 | Team Review Package and Close-out | Phase 193 | Not started |

## Accumulated Context

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
| D-193-01 | Tracked changes in the original file vs a new versioned copy | New versioned copy (recommended) |

### Carried from v3.12

- R/88 ALL CHECKS PASSED 2026-10-23 (Sections 15av–15az, Phase 185–189 scripts)
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

**Stopped at:** Completed 191-02-PLAN.md
