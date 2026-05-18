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
- **v1.6 Treatment Code Validation & Cancer Site Analysis** — Phases 45-47 — [roadmap](milestones/v1.6-ROADMAP.md)

## Remaining Phases (Unassigned)

- [x] **Phase 38: Chemo Treatment Inventory by Source Table** — List all chemo treatments and categorize by PCORnet table (procedures, dispensing, prescribing, etc.) (completed 2026-05-05)
  - **Goal:** Aggregate inventory of all treatment codes (chemo, radiation, SCT, immunotherapy) across 7 PCORnet tables with styled xlsx output
  - **Plans:** 1 plan
  - Plans:
    - [x] 38-01-PLAN.md — Data extraction, aggregation, unknown code detection, styled xlsx output
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
- [x] **Phase 42: Treatment Codes Resolved XLSX (All Types)** — Create resolved xlsx reports for other treatment types (radiation, SCT, immunotherapy) from combined_unmatched_report.xlsx, and verify chemotherapy_codes_resolved.xlsx accuracy (completed 2026-05-05)
  - **Goal:** Extend the chemotherapy_codes_resolved.xlsx pattern to all treatment categories, producing per-type resolved xlsx files, and audit chemotherapy_codes_resolved.xlsx for correctness
  - **Depends on:** Phase 41
  - **Plans:** 1 plan
  - Plans:
    - [x] 42-01-PLAN.md — Per-type resolved xlsx generation (radiation, SCT, immunotherapy, supportive care) + chemotherapy verification
- [x] **Phase 43: Establish Treatment Lengths for SCT, Chemo, and Radiation** — Determine treatment duration windows for stem cell transplant, chemotherapy, and radiation therapy from PCORnet data (completed 2026-05-05)
  - **Goal:** Establish treatment length estimates for SCT, chemo, radiation, and immunotherapy using procedure/dispensing/prescribing timestamps with 90-day episode gap detection
  - **Depends on:** Phase 42
  - **Plans:** 1 plan
  - Plans:
    - [x] 43-01-PLAN.md — Multi-source date extraction, duration/episode computation, styled xlsx + boxplot PNG + RDS output
- [x] **Phase 44: Treatment Episode Start/Stop Dates** — Produce per-patient per-episode start and stop dates for each 90-day treatment period with episode length; single-date episodes for historical treatments outside the 2012-2025 data window (completed 2026-05-11)
  - **Goal:** Expand treatment duration output to include per-episode start/stop dates and episode length, with special handling for isolated historical treatment dates (e.g., tumor registry dates from 1970s-2000s)
  - **Depends on:** Phase 43
  - **Plans:** 1 plan
  - Plans:
    - [x] 44-01-PLAN.md — Per-episode date extraction, historical flagging, styled xlsx + per-type CSVs + RDS output
- [x] **Phase 45: Tiered Encounter-Level Payer Assignment** — Assign AMC 8-category payer tiers to every individual encounter without same-day collapsing (completed 2026-05-12)
  - **Goal:** Per-encounter payer tier assignment with dual-scope (all encounters + AV+TH) detail and summary CSV output
  - **Depends on:** Phase 37
  - **Plans:** 1 plan
  - Plans:
    - [x] 45-01-PLAN.md — Encounter-level tier assignment, dual-scope CSV output (executed outside GSD workflow)
- [x] **Phase 46: Tiered Date-Level Payer Assignment** — Expand treatment episodes to per-calendar-date rows and assign payer tiers with forward/backward fill and enrollment fallback (completed 2026-05-12)
  - **Goal:** Per-calendar-date payer tier assignment within treatment episodes using encounter tiers, forward/backward fill, and FLM enrollment fallback
  - **Depends on:** Phase 44, Phase 45
  - **Plans:** 1 plan
  - Plans:
    - [x] 46-01-PLAN.md — Episode-to-daily expansion, tier cascade (encounter > fill > enrollment), summary CSVs (executed outside GSD workflow)

## v1.6 Phases

- [x] **Phase 45: Radiation CPT Audit** — Classify CPT 70010-79999 sub-ranges with citations, identify which codes appear in HL patient data, and add proton therapy codes to config (completed 2026-05-15)
  - **Goal:** The radiation CPT range 70010-79999 is documented, every code in HL patient data is classified as imaging or treatment, and proton therapy codes are captured in config
  - **Depends on:** Phase 44
  - **Requirements:** RADCPT-01, RADCPT-02, RADCPT-03
  - **Plans:** 2 plans
  - Plans:
    - [x] 45-01-PLAN.md — Config update (proton codes, fixed descriptions, comment block) + audit script (classification table, PROCEDURES query, styled xlsx)
    - [x] 45-02-PLAN.md — Gap closure: execute audit script on HiPerGator to generate xlsx output
- [x] **Phase 46: Treatment Code Cross-Reference & Triggering Codes** — Two-way gap report comparing TreatmentVariables docx against config, plus triggering_codes column in episode CSV output (completed 2026-05-15)
  - **Goal:** Users can see which codes are in the reference doc but not in config (and vice versa), and each episode row shows which code(s) triggered it
  - **Depends on:** Phase 45
  - **Requirements:** TXREF-01, TXREF-02
  - **Plans:** 2 plans
  - Plans:
    - [ ] 46-01-PLAN.md — Gap report: hardcoded reference data from docx/xlsx files, two-way comparison, DuckDB counts, styled 5-sheet xlsx
    - [ ] 46-02-PLAN.md — Triggering codes: extract_dates_with_codes() function, triggering_codes column in episode CSV and xlsx
- [x] **Phase 47: Cancer Site Frequency** — Frequency table of all 42 cancer site categories from CancerSiteCategories.xlsx with styled xlsx output ready to email (completed 2026-05-15)
  - **Goal:** Users can see patient counts and encounter counts per cancer site category across the full PCORnet extract
  - **Depends on:** Nothing (independent)
  - **Requirements:** CSITE-01, CSITE-02
  - **Plans:** 1 plan
  - Plans:
    - [ ] 47-01-PLAN.md — Cancer site frequency script: range expansion, DIAGNOSIS + TUMOR_REGISTRY queries, styled xlsx output

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
| 38-46 | Unassigned | Complete | 2026-05-12 |
| 45 | v1.6 | Complete | 2026-05-15 |
| 46-47 | v1.6 | Not started | — |

---
*Last updated: 2026-05-18*
