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
- [x] **Phase 34: Payer Code Frequency Summary (AV+TH)** — Raw payer code frequency with PayerVariable.xlsx cross-reference (completed 2026-04-27)
- [x] **Phase 35: Tiered Same-Day Payer Categorization** — Dual-scope frequency tables + hierarchical same-day payer resolution per Amy Crisp framework (completed 2026-04-27)
- [ ] **Phase 36: All-Encounter Payer Frequency & Same-Day Categorization (AMC 8-Category)** — Refactor R/36 to use AMC_PAYER_LOOKUP from R/00_config.R, remove PayerVariable.xlsx dependency
  - **Goal:** R/36 uses centralized AMC 8-category mapping exclusively, producing same 12 CSVs with updated categories
  - **Plans:** 1 plan
  - Plans:
    - [ ] 36-01-PLAN.md — Refactor R/36 to AMC_PAYER_LOOKUP + human verification on HiPerGator

## Progress

| Phase | Milestone | Status | Completed |
|-------|-----------|--------|-----------|
| 1-14 | v1.0 | Complete | 2026-04-01 |
| 15-17 | v1.1 | Complete | 2026-04-03 |
| 18-23, 25 | v1.2 | Complete | 2026-04-21 |
| 24, 26-28 | v1.2 (deferred) | On hold | - |
| 29-32 | v1.3 | Complete | 2026-04-23 |
| 33 | v1.4 | Complete | 2026-04-24 |
| 34 | 1/1 | Complete    | 2026-04-27 |
| 35 | Unassigned | Complete | 2026-04-27 |

### Phase 37: Add an Other Govt tier to the tiered payer variable

**Goal:** Promote "Other govt" to its own distinct tier in the same-day payer resolution hierarchy, expanding from 7 tiers to 8 (Medicaid > Medicare > Private > Other Govt > Other > Self-pay > Uninsured > Missing)
**Requirements**: TIER-01
**Depends on:** Phase 36
**Plans:** 1 plan

Plans:
- [ ] 37-01-PLAN.md — Expand tier hierarchy to 8 tiers with Other Govt at position 4

---
*Last updated: 2026-05-01*
