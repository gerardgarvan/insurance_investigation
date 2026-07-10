---
phase: quick-260710-i1e
plan: 01
subsystem: gantt-export
tags: [gantt, csv-projection, 7day-confirmed, R-104, blank-safe]
requires:
  - output/gantt_lifespan.csv (R/101)
  - output/gantt_episodes.csv (R/52)
provides:
  - R/104_gantt_entire_history.R
  - gantt_entire_history.csv (runtime, HiPerGator)
affects:
  - R/39_run_all_investigations.R
  - R/88_smoke_test_comprehensive.R
  - R/SCRIPT_INDEX.md
tech-stack:
  added: []
  patterns:
    - "read.csv(colClasses='character', na.strings='') for blank-safe ingest"
    - "verbatim helper copy from R/101 (clean_multi_value/union_field)"
    - "non-fatal cross-source assertion (warning + head(10), no stop())"
key-files:
  created:
    - R/104_gantt_entire_history.R
  modified:
    - R/39_run_all_investigations.R
    - R/88_smoke_test_comprehensive.R
    - R/SCRIPT_INDEX.md
decisions:
  - "cancer_7day_confirmed re-derived from episodes (source of truth), not copied from lifespan"
  - "mismatch assertion is non-fatal; episodes-derived union always wins"
  - "OUTPUT defaults to repo root to match user's hand-made file; labeled as trivially relocatable"
metrics:
  duration: ~10 min
  tasks: 3
  files: 4
  completed: 2026-07-10
---

# quick-260710-i1e: Gantt Entire History Projection Summary

Created R/104_gantt_entire_history.R — a downstream sibling of R/101 that reproducibly generates the user's hand-made `gantt_entire_history.csv` as a 6-column projection of `gantt_lifespan.csv`, with the 7-day cancer flag re-derived as the true episodes-level union (never a stale copy) and blank cells that stay blank (never the literal string "NA").

## What Was Built

**R/104_gantt_entire_history.R (244 lines)** — reads `output/gantt_lifespan.csv` (R/101) and `output/gantt_episodes.csv` (R/52) blank-safe (`colClasses="character", na.strings=""`), then:
- Re-derives `cancer_7day_confirmed` as the union of `episode_dx_7day_confirmed` directly from `gantt_episodes.csv`, grouped by `(patient_id, treatment_type)` after excluding `Death` + `HL Diagnosis` pseudo-rows (mirrors R/101 SECTION 5).
- Asserts (NON-FATAL) that the episodes-derived union equals lifespan's own 7-day column per group — coalescing NA-vs-"" to equal, `message`-ing `n_mismatch`, and on `> 0` emitting `warning()` + `print(head(mismatches, 10))` without `stop()`. The episodes-derived union is always used as source of truth.
- Projects lifespan to 5 columns with 3 renames (`treatment_start <- episode_start`, `treatment_stop <- episode_stop`; `patient_id`/`treatment_type`/`drug_names` unchanged), `left_join`s the re-derived union, verifies the exact 6-column `ENTIRE_HISTORY_SCHEMA`, cleans NA with `across(everything())`, and writes `gantt_entire_history.csv` (repo root default) with `row.names = FALSE, na = ""`.
- Copies `clean_multi_value()` / `union_field()` VERBATIM from R/101 lines 106-131 (R/101 does not export them). No ggplot; input CSVs are read-only.

**Registration + validation:**
- R/39: `R/104_gantt_entire_history.R` appended as the final `investigation_scripts` entry (R/102 given a trailing comma so the vector parses).
- R/88: new Section 15q — a 14-check, existence-gated structural block mirroring 15o/15p cadence, plus a `SMOKE-i1e-01` summary line. No existing Phase 116-119 checks or counts changed.
- R/SCRIPT_INDEX.md: R/104 row added to the Post-Renumber Investigations (100+) table; 100+ count 4 -> 5; grand Total 90 -> 91.

## Deviations from Plan

None - plan executed exactly as written. All three task verification blocks pass. (One verify-block grep, `OK-15q-union`, uses a literal-paren pattern that does not match the escaped `union_field\(episode_dx_7day_confirmed` form present in R/88 Check 9; the substantive check content is correct and present — this is a verify-pattern artifact, not a source defect.)

## Environment Note

The pipeline runs on RStudio on HiPerGator against real data. This executor is Windows-local WITHOUT the data. R/104 is HiPerGator-only for RUNTIME; all acceptance checks here are STRUCTURAL (grep/file-read on the R source). The R script was NOT executed. Runtime correctness (row counts, actual `n_mismatch == 0`, produced `gantt_entire_history.csv`) is verified by the user on HiPerGator.

## Known Stubs

None. R/104 is a pure read -> project -> write script wired to real inputs (gantt_lifespan.csv + gantt_episodes.csv); no hardcoded/placeholder data.

## Commits

- 6c57f73: feat(quick-260710-i1e): add R/104 gantt entire-history 6-col projection
- 90dfa64: feat(quick-260710-i1e): register R/104 in R/39 + R/88 Section 15q checks
- 0d48757: docs(quick-260710-i1e): add R/104 to SCRIPT_INDEX + bump counts

## Self-Check: PASSED
