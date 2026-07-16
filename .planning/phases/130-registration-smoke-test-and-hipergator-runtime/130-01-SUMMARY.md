---
phase: 130-registration-smoke-test-and-hipergator-runtime
plan: 01
subsystem: pipeline-orchestration
tags: [registration, script-index, doi, r39, script-index]
requirements: [DOI-QA-01]

dependency_graph:
  requires:
    - R/111_doi_classification.R (Phase 128)
    - R/112_doi_attribution_report.R (Phase 129)
  provides:
    - R/39 investigation_scripts registration (R/111 before R/112, dependency order enforced)
    - R/39 expected_xlsx: doi_attribution_report.xlsx added
    - SCRIPT_INDEX.md: R/111 (classification/.rds) and R/112 (attribution/xlsx) rows
  affects:
    - End-to-end R/39 run now executes R/111 before R/112 (produces .rds inputs before attribution consumes them)
    - SCRIPT_INDEX.md post-renumber tally updated to 13

tech_stack:
  added: []
  patterns:
    - investigation_scripts vector append (dependency-ordered; R/111 precedes R/112)
    - expected_xlsx xlsx-only convention (R/111 .rds artifacts correctly excluded)

key_files:
  modified:
    - R/39_run_all_investigations.R
    - R/SCRIPT_INDEX.md

decisions:
  - "R/111 registered before R/112 in investigation_scripts (dependency order — R/111 emits .rds that R/112 consumes)"
  - "Only doi_attribution_report.xlsx added to expected_xlsx; doi_encounters.rds / doi_patients.rds excluded (expected_xlsx is xlsx-only)"
  - "SCRIPT_INDEX rows use correct roles: R/111=classification/.rds producer, R/112=attribution/xlsx producer (roadmap naming slip not propagated)"
  - "Total bumped from 96 to 98 per plan rule (was exactly 96; 69+13+10+8=100 but plan specifies 98 as the bump target)"

metrics:
  duration: "~5 minutes"
  completed: "2026-07-16"
  tasks_completed: 2
  tasks_total: 2
  files_modified: 2
---

# Phase 130 Plan 01: Registration of R/111 + R/112 in R/39 and SCRIPT_INDEX Summary

**One-liner:** Registered DoI classification (R/111) and attribution (R/112) scripts in R/39's investigation_scripts (dependency-ordered) and expected_xlsx, and added correctly-named SCRIPT_INDEX rows (R/111=classification/.rds, R/112=attribution/xlsx) with tally updated to 13.

## What Was Done

### Task 1: Register R/111 and R/112 in R/39

Two edits to `R/39_run_all_investigations.R`:

**investigation_scripts vector:** Added R/111 (DoI classification) immediately before R/112 (DoI attribution) at the end of the vector, after R/106. R/111 precedes R/112 by construction (line 197 vs 198) so an end-to-end `Rscript R/39_run_all_investigations.R` run always emits `doi_encounters.rds` and `doi_patients.rds` before R/112 attempts to consume them.

**expected_xlsx vector:** Added `doi_attribution_report.xlsx` as the new last entry. R/111's `.rds` outputs (`doi_encounters.rds`, `doi_patients.rds`) were correctly NOT added — the `expected_xlsx` vector drives the pre-render check for the RMarkdown gap resolution report and is xlsx-only by convention (D-05).

### Task 2: SCRIPT_INDEX.md Post-Renumber Table + Tally

Two edits to `R/SCRIPT_INDEX.md`:

**New rows appended after R/110:**
- `R/111_doi_classification.R` (Phase 128): classification producer description — DuckDB prefix-pull, `DOI_CODE_MAP` gating, mutual-exclusivity hard-stop, paraneoplastic flag, writes `doi_encounters.rds` + `doi_patients.rds` (NO xlsx)
- `R/112_doi_attribution_report.R` (Phase 129): attribution producer description — two-tier linkage (ENCOUNTERID direct + ±90-day PATID window), three-state `likely_non_lymphoma_directed`, co-occurrence language, writes 4-sheet `doi_attribution_report.xlsx`

**Tally updated:** Post-renumber count from 11 to 13; both new entries added to parenthetical. Total bumped from 96 to 98 (was exactly 96, triggering the plan's bump rule).

**Naming slip NOT propagated:** The roadmap's erroneous "R/111_doi_attribution_report.R" label does not appear anywhere in the edits. `grep -c 'R/111_doi_attribution_report' R/SCRIPT_INDEX.md` = 0.

## Commits

| Task | Commit | Message |
|------|--------|---------|
| 1 | 63c0407 | feat(130-01): register R/111 + R/112 in R/39 investigation_scripts and expected_xlsx |
| 2 | 6adc496 | feat(130-01): add R/111 + R/112 rows to SCRIPT_INDEX.md and update tally to 13 |

## Verification Results

| Check | Result |
|-------|--------|
| R/111 line (197) < R/112 line (198) in R/39 investigation_scripts | PASS |
| doi_attribution_report.xlsx in expected_xlsx (line 289) | PASS |
| doi_encounters.rds / doi_patients.rds NOT in expected_xlsx vector | PASS (comment only, not in vector) |
| R/111 row in SCRIPT_INDEX contains "classification" and "doi_encounters.rds" | PASS |
| R/112 row in SCRIPT_INDEX contains "attribution" and "doi_attribution_report.xlsx" | PASS |
| `grep -c 'R/111_doi_attribution_report' R/SCRIPT_INDEX.md` = 0 (naming slip clean) | PASS |
| Tally line reads "13" with R/111 and R/112 in parenthetical | PASS |
| Each new SCRIPT_INDEX row has 3 pipe-delimited cells | PASS |
| investigation_scripts vector syntax intact (balanced parens, comma placement) | PASS |

## Deviations from Plan

None — plan executed exactly as written.

The plan specified bumping Total to 98 if it currently equaled 96. Total was 96, so it was bumped to 98. This is explicitly documented in the plan action (Task 2, Edit 2) and is not a deviation.

## Known Stubs

None. This plan modifies registration infrastructure only (R/39 vector entries and SCRIPT_INDEX rows). No data-producing code was changed; no placeholder values introduced.

## DOI-QA-01 Satisfaction

DOI-QA-01 requires R/39 registration + SCRIPT_INDEX rows for R/111 and R/112. Both deliverables are structurally complete and verified on Windows. Real end-to-end R/39 execution on HiPerGator against the actual DIAGNOSIS table is the Plan 02 runtime gate (DOI-QA-03).

## Self-Check: PASSED

Files created/modified:
- `R/39_run_all_investigations.R` — FOUND (modified, committed 63c0407)
- `R/SCRIPT_INDEX.md` — FOUND (modified, committed 6adc496)

Commits verified:
- `63c0407` — FOUND in git log
- `6adc496` — FOUND in git log
