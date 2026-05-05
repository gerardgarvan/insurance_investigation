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
- [x] **Phase 39: Investigate Unmatched Codes** — Investigate CPT/HCPCS codes in HL patient data not in curated TREATMENT_CODES lists (completed 2026-05-04)
  - **Goal:** Widen heuristic detection ranges, auto-classify unmatched codes via NLM API lookup and keyword heuristics, produce xlsx report, and update TREATMENT_CODES with confirmed treatment codes
  - **Depends on:** Phase 38
  - **Plans:** 2 plans
  - Plans:
    - [x] 39-01-PLAN.md — Investigation script: extraction, NLM API lookup, classification, xlsx report
    - [x] 39-02-PLAN.md — Config updates: TREATMENT_CODES expansion and widened heuristic ranges
- [x] **Phase 40: Investigate Unmatched NDC Codes** — Investigate NDC codes and RXNORM CUIs in HL patient drug data not in curated TREATMENT_CODES lists (completed 2026-05-04)
  - **Goal:** Extract unmatched NDC and RXNORM codes from DISPENSING/PRESCRIBING/MED_ADMIN, look up drug names via RxNorm API, auto-classify into treatment categories, produce xlsx report, and update TREATMENT_CODES with new NDC vectors and expanded RXNORM CUIs
  - **Depends on:** Phase 39
  - **Plans:** 2 plans
  - Plans:
    - [x] 40-01-PLAN.md — Investigation script: drug code extraction, RxNorm API lookup, classification, xlsx report + RDS artifact
    - [x] 40-02-PLAN.md — Config update: new NDC vectors and expanded RXNORM CUIs in TREATMENT_CODES
- [x] **Phase 41: Combine NDC and HCPCS Reports** — Combine Phase 39 (HCPCS/CPT) and Phase 40 (NDC/RXNORM) unmatched code investigation reports into a single consolidated xlsx report (completed 2026-05-05)
  - **Goal:** Merge the two separate investigation xlsx reports into one unified report with consistent formatting, combined summary statistics, and cross-code-type views
  - **Depends on:** Phase 39, Phase 40
  - **Plans:** 1 plan
  - Plans:
    - [x] 41-01-PLAN.md — Load RDS artifacts, harmonize schemas, produce combined styled xlsx report
- [ ] **Phase 42: Treatment Codes Resolved XLSX (All Types)** — Create resolved xlsx reports for other treatment types (radiation, SCT, immunotherapy) from combined_unmatched_report.xlsx, and verify chemotherapy_codes_resolved.xlsx accuracy
  - **Goal:** Extend the chemotherapy_codes_resolved.xlsx pattern to all treatment categories, producing per-type resolved xlsx files, and audit chemotherapy_codes_resolved.xlsx for correctness
  - **Depends on:** Phase 41
  - **Plans:** 1 plan
  - Plans:
    - [ ] 42-01-PLAN.md — Per-type resolved xlsx generation (radiation, SCT, immunotherapy, supportive care) + chemotherapy verification

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
*Last updated: 2026-05-05*
