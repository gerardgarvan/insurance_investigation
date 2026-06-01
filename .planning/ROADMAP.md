# Roadmap: PCORnet Payer Variable Investigation (R Pipeline)

**Project:** PCORnet CDM Payer Analysis Pipeline (R)
**Created:** 2026-03-24

## Milestones

- **v1.0 MVP** — Phases 1-14 (shipped 2026-04-01)
- **v1.1 RDS Cache & Viz Polish** — Phases 15-17 (shipped 2026-04-03)
- **v1.2 Multi-Source Overlap** — Phases 18-23, 25 (shipped 2026-04-21; Phases 24/26/27/28 dropped)
- **v1.3 DuckDB Backend Migration** — Phases 29-32 (shipped 2026-04-23)
- **v1.4 AV+TH Subset Analysis** — Phase 33 (shipped 2026-04-27) — [archive](milestones/v1.4-ROADMAP.md)
- **v1.5 Payer Analysis Expansion** — Phases 34-37 (shipped 2026-05-01) — [archive](milestones/v1.5-ROADMAP.md)
- **v1.6 Treatment Code Validation & Cancer Site Analysis** — Phases 45-54 (shipped 2026-05-22) — [archive](milestones/v1.6-ROADMAP.md)
- **v1.7 Cancer Summary Refinement & Gantt Enhancements** — Phases 55-59 (shipped 2026-05-28) — [archive](milestones/v1.7-ROADMAP.md)
- **v1.8 Episode-Level Cancer Linkage & First-Line Therapy Identification** — Phases 60-63 (shipped 2026-06-01) — [archive](milestones/v1.8-ROADMAP.md)

## Remaining Phases (Unassigned)

- [x] **Phase 38: Chemo Treatment Inventory by Source Table** (completed 2026-05-05)
- [x] **Phase 39: Investigate Unmatched Codes** (completed 2026-05-04)
- [x] **Phase 40: Investigate Unmatched NDC Codes** (completed 2026-05-05)
- [x] **Phase 41: Combine NDC and HCPCS Reports** (completed 2026-05-05)
- [x] **Phase 42: Treatment Codes Resolved XLSX (All Types)** (completed 2026-05-05)
- [x] **Phase 43: Establish Treatment Lengths for SCT, Chemo, and Radiation** (completed 2026-05-05)
- [x] **Phase 44: Treatment Episode Start/Stop Dates** (completed 2026-05-11)
- [x] **Phase 45: Tiered Encounter-Level Payer Assignment** (completed 2026-05-12)
- [x] **Phase 46: Tiered Date-Level Payer Assignment** (completed 2026-05-12)

## Progress

| Phase | Milestone | Status | Completed |
|-------|-----------|--------|-----------|
| 1-14 | v1.0 | Complete | 2026-04-01 |
| 15-17 | v1.1 | Complete | 2026-04-03 |
| 18-23, 25 | v1.2 | Complete | 2026-04-21 |
| 24, 26-28 | v1.2 (deferred) | Dropped | 2026-05-05 |
| 29-32 | v1.3 | Complete | 2026-04-23 |
| 33 | v1.4 | Complete | 2026-04-24 |
| 34-37 | v1.5 | Complete | 2026-05-01 |
| 38-44 | Unassigned | Complete | 2026-05-12 |
| 45-54 | v1.6 | Complete | 2026-05-22 |
| 55-59 | v1.7 | Complete | 2026-05-28 |
| 60-63 | v1.8 | Complete | 2026-06-01 |

### Phase 64: Clean up Gantt 2 output for coherent chart generation

**Goal:** Clean the Gantt v2 CSV outputs (gantt_episodes_v2.csv, gantt_detail_v2.csv) for direct Tableau import by fixing multi-value separators, simplifying drug names, removing literal NA text, filling blank descriptions and cancer categories, and trimming to essential columns.
**Requirements**: GANTT-CLEAN-01 through GANTT-CLEAN-07
**Depends on:** Phase 63
**Plans:** 1 plan

Plans:
- [ ] 64-01-PLAN.md — Add Section 4D cleanup logic to R/63_gantt_v2_export.R and verify output quality

---
*Last updated: 2026-06-01 -- Phase 64 planned*
