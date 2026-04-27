# Roadmap: PCORnet Payer Variable Investigation (R Pipeline)

**Project:** PCORnet CDM Payer Analysis Pipeline (R)
**Created:** 2026-03-24

## Milestones

- **v1.0 MVP** — Phases 1-14 (shipped 2026-04-01)
- **v1.1 RDS Cache & Viz Polish** — Phases 15-17 (shipped 2026-04-03)
- **v1.2 Multi-Source Overlap** — Phases 19-25 (on hold, Phases 24/26/27/28 deferred)
- **v1.3 DuckDB Backend Migration** — Phases 29-32 (shipped 2026-04-23)
- **v1.4 AV+TH Subset Analysis** — Phase 33 (shipped 2026-04-27) — [archive](milestones/v1.4-ROADMAP.md)

## Remaining Phases (Unassigned)

- [ ] **Phase 24: Focused Presentation of Phases 19/20** — Build PPTX with UF missingness + FLM duplicate-date outputs only
- [ ] **Phase 26: Overlap Classification and Recommendations** — Field-by-field comparison and Identical/Partial/Distinct classification for all encounter types
- [ ] **Phase 27: Cross-Table Data Quality Assessment** — 6-dimension QA pass across all 13 PCORnet CDM tables
- [ ] **Phase 28: Per-Patient Source Detection by Date** — Per-date source enumeration replacing pairwise overlap approach
- [x] **Phase 34: Payer Code Frequency Summary (AV+TH)** — Raw payer code frequency with PayerVariable.xlsx cross-reference (completed 2026-04-27)
- [x] **Phase 35: Tiered Same-Day Payer Categorization** — Dual-scope frequency tables + hierarchical same-day payer resolution per Amy Crisp framework (completed 2026-04-27)

## Progress

| Phase | Milestone | Status | Completed |
|-------|-----------|--------|-----------|
| 1-14 | v1.0 | Complete | 2026-04-01 |
| 15-17 | v1.1 | Complete | 2026-04-03 |
| 18-23, 25 | v1.2 | Complete | 2026-04-21 |
| 24, 26-28 | v1.2 (deferred) | On hold | - |
| 29-32 | v1.3 | Complete | 2026-04-23 |
| 33 | v1.4 | Complete | 2026-04-24 |
| 34 | 1/1 | Complete   | 2026-04-27 |
| 35 | Unassigned | Complete | 2026-04-27 |

---
*Last updated: 2026-04-27 after v1.4 milestone completion*
