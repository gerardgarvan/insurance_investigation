# Roadmap: PCORnet Payer Variable Investigation (R Pipeline)

**Project:** PCORnet CDM Payer Analysis Pipeline (R)
**Created:** 2026-03-24

## Milestones

- **v1.0 MVP** — Phases 1-14 (shipped 2026-04-01)
- **v1.1 RDS Cache & Viz Polish** — Phases 15-17 (shipped 2026-04-03)
- **v1.2 Multi-Source Overlap** — Phases 18-25 (on hold, Phases 24/26/27/28 deferred)
- **v1.3 DuckDB Backend Migration** — Phases 29-32 (shipped 2026-04-23)
- **v1.4 AV+TH Subset Analysis** — Phase 33 (shipped 2026-04-27) — [archive](milestones/v1.4-ROADMAP.md)
- **v1.5 Payer Analysis Expansion** — Phases 34-37 (shipped 2026-05-01) — [archive](milestones/v1.5-ROADMAP.md)

## Remaining Phases (Unassigned)

- [ ] **Phase 24: Focused Presentation of Phases 19/20** — Build PPTX with UF missingness + FLM duplicate-date outputs only
- [ ] **Phase 26: Overlap Classification and Recommendations** — Field-by-field comparison and Identical/Partial/Distinct classification for all encounter types
- [ ] **Phase 27: Cross-Table Data Quality Assessment** — 6-dimension QA pass across all 13 PCORnet CDM tables
- [ ] **Phase 28: Per-Patient Source Detection by Date** — Per-date source enumeration replacing pairwise overlap approach
- [ ] **Phase 38: Chemo Treatment Inventory by Source Table** — List all chemo treatments and categorize by PCORnet table (procedures, dispensing, prescribing, etc.)
  - **Goal:** Aggregate inventory of all treatment codes (chemo, radiation, SCT, immunotherapy) across 7 PCORnet tables with styled xlsx output
  - **Plans:** 1 plan
  - Plans:
    - [ ] 38-01-PLAN.md — Data extraction, aggregation, unknown code detection, styled xlsx output

## Progress

| Phase | Milestone | Status | Completed |
|-------|-----------|--------|-----------|
| 1-14 | v1.0 | Complete | 2026-04-01 |
| 15-17 | v1.1 | Complete | 2026-04-03 |
| 18-23, 25 | v1.2 | Complete | 2026-04-21 |
| 24, 26-28 | v1.2 (deferred) | On hold | - |
| 29-32 | v1.3 | Complete | 2026-04-23 |
| 33 | v1.4 | Complete | 2026-04-24 |
| 34-37 | v1.5 | Complete | 2026-05-01 |

---
*Last updated: 2026-05-01*
