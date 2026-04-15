---
phase: 24-make-presentation-of-just-phases-19-and-20
plan: 01
subsystem: visualization
tags: [pptx, officer, flextable, ggplot2, phase19, phase20, focused-deck]

requires:
  - phase: 19-investigate-insurance-missingness-source-uf-specifically
    provides: "UF CSV outputs (uf_*.csv) in output/tables/"
  - phase: 20-check-duplicate-dates-of-flm-subjects
    provides: "FLM CSV outputs (flm_*.csv) in output/tables/"
provides:
  - "Standalone focused PPTX generator script for phases 19 and 20"
  - "Split-table handling for large UF year x encounter-type and FLM detail summaries"
  - "Phase 24 chart PNG generation in output/figures/phase24_*"

tech-stack:
  added: [officer, flextable, ggplot2, readr, dplyr, tidyr, scales, glue]
  patterns: [standalone-focused-deck-script, chunked-table-slides, chart-first-then-embed]

key-files:
  created:
    - R/22_generate_phase19_20_pptx.R

requirements-completed: [PPTX4-01, PPTX4-02, PPTX4-03, PPTX4-04]
status: awaiting-human-verification
completed: 2026-04-15
---

# Phase 24 Plan 01 Summary

Implemented `R/22_generate_phase19_20_pptx.R`, a standalone PPTX generator that builds a focused deck from only Phase 19 UF missingness outputs and Phase 20 FLM duplicate-date outputs.

## What Was Built
- Added standalone script `R/22_generate_phase19_20_pptx.R` with project-consistent slide helpers and styling.
- Script reads only `uf_*` and `flm_*` CSV inputs; no `all_source_*`/`all_site_*` dependencies.
- Added chart generation to `output/figures/phase24_*` and embedded chart slides in the deck.
- Added multi-slide splitting for large tables:
  - UF year x encounter-type table
  - FLM patient duplicate summary
  - FLM date-level detail summary (aggregated for readability)
- Added source-preference recommendation slide from FLM source completeness evidence.
- Added deterministic output naming: `insurance_tables_phase19_20_YYYY-MM-DD.pptx`.

## Verification Notes
- Static lint check: no diagnostics in `R/22_generate_phase19_20_pptx.R`.
- Constraint check: no `all_source_` or `all_site_` references found in the new script.
- Runtime parse check could not be executed in this shell because R is not available in the current local environment.

## Human Verification Required (Blocking)
Run:

```r
source("R/22_generate_phase19_20_pptx.R")
```

Then confirm:
- Deck file `insurance_tables_phase19_20_YYYY-MM-DD.pptx` is created.
- Deck contains only Phase 19 and 20 content.
- Tables and charts are both present.
- Split tables are readable and recommendation slide content is acceptable.

---
*Phase: 24-make-presentation-of-just-phases-19-and-20*  
*Completed: 2026-04-15 (awaiting user approval after runtime verification)*
