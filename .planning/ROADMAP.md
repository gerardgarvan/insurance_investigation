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
- **v2.0 Codebase Cleanup & Documentation** — Phases 65-74 (shipped 2026-06-02) — [archive](milestones/v2.0-ROADMAP.md)
- **v2.1 Clinical Data Refinements & NLPHL Breakout** — Phases 75-82 (shipped 2026-06-03) — [archive](milestones/v2.1-ROADMAP.md)
- **v2.2 Local Testing Infrastructure & Clinical Refinements** — Phases 83-89 (shipped 2026-06-05) — [archive](milestones/v2.2-ROADMAP.md)
- **v2.3 Gantt Data Enrichment** — Phases 90-93 (active)

## v2.3 Gantt Data Enrichment

### Phases

- [x] **Phase 90: False-Positive SCT Code Removal** - Remove status/complication codes from treatment detection and validate impact (completed 2026-06-08)
- [x] **Phase 91: Reference Data Loader & Metadata Enrichment** - Build xlsx lookup utility and enrich treatment episodes with per-code metadata (completed 2026-06-08)
- [ ] **Phase 92: Gantt v2 Schema Extension** - Extend Gantt exports with 5 new columns while preserving backward compatibility
- [ ] **Phase 93: Cross-Use Flag Implementation** - Add temporal context logic for SCT conditioning and immunotherapy dual-purpose flags

### Phase Details

#### Phase 90: False-Positive SCT Code Removal
**Goal**: Remove 5 false-positive SCT codes (status/complication codes) from treatment detection
**Depends on**: Nothing (prerequisite for enrichment)
**Requirements**: CLEAN-01, CLEAN-02
**Success Criteria** (what must be TRUE):
  1. Five codes (Z94.84, T86.5, T86.09, Z48.290, HEMATOLOGIC_TRANSPLANT_AND_ENDOC) removed from R/00_config.R with documented rationale
  2. Impact analysis documented showing affected episode counts before removal
  3. Smoke test Section 15 validates deprecated codes absent from new treatment_episodes output
  4. No SCT episodes triggered solely by status/complication codes in cohort pipeline
**Plans:** 1/1 plans complete

Plans:
- [x] 90-01-PLAN.md — Remove 5 codes from DRUG_GROUPINGS and add smoke test Section 15c

#### Phase 91: Reference Data Loader & Metadata Enrichment
**Goal**: Integrate all_codes_resolved2.xlsx metadata into treatment episode pipeline
**Depends on**: Phase 90 (clean code list before enrichment)
**Requirements**: GANTT-01, GANTT-02, GANTT-03, GANTT-04, GANTT-05
**Success Criteria** (what must be TRUE):
  1. R/utils/utils_xlsx_lookups.R extracts medication names, code types, source tables, F/S/E/N labels, and cross-use flags from 8 xlsx sheets
  2. Pre-join validation prevents many-to-many row explosion (deduplication enforced)
  3. R/28 episode classification enriched with 5 new columns via left_join with relationship assertion
  4. Unresolved classifications (TBD codes) exported separately for clinical SME review rather than propagating NA values
  5. treatment_episodes.rds contains medication_name, code_type, source_table, treatment_line, and sct_cross_use_flag columns
**Plans:** 1/1 plans complete

Plans:
- [x] 91-01-PLAN.md — Create xlsx lookup utility, enrich R/28 with 5 metadata columns, add smoke test Section 15d

#### Phase 92: Gantt v2 Schema Extension
**Goal**: Extend Gantt CSV exports with enriched metadata columns while maintaining v1 compatibility
**Depends on**: Phase 91 (enriched episode data available)
**Requirements**: GANTT-06, GANTT-07
**Success Criteria** (what must be TRUE):
  1. gantt_episodes_v2.csv extends from 16 to 21 columns (5 new columns appended at end)
  2. gantt_detail_v2.csv extends from 14 to 19 columns (5 new columns appended at end)
  3. Existing v1 Gantt exports (R/51 output) unchanged and functional (backward compatible)
  4. Smoke test Section 52 validates 21-column schema with correct column order and non-null distributions
  5. Death/HL Diagnosis pseudo-rows populate new columns with NA appropriately
**Plans**: TBD

#### Phase 93: Cross-Use Flag Implementation
**Goal**: Add temporal context logic for drugs with dual treatment intent (SCT conditioning vs standalone chemotherapy/immunotherapy)
**Depends on**: Phase 92 (basic enrichment working)
**Requirements**: IMMU-01, IMMU-02
**Success Criteria** (what must be TRUE):
  1. Temporal context flags identify codes used within 30 days before SCT episode start (is_sct_conditioning_context)
  2. Questionable immunotherapy codes flagged with confidence column distinguishing vitamin combos from CAR-T classification ambiguity
  3. Category aggregation rules documented to prevent cross-use flags from causing treatment sums exceeding 100%
  4. Smoke test validates primary category sum equals total episode count (mutual exclusivity)
**Plans**: TBD

### Progress Table

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 90. False-Positive SCT Code Removal | 1/1 | Complete    | 2026-06-08 |
| 91. Reference Data Loader & Metadata Enrichment | 1/1 | Complete   | 2026-06-08 |
| 92. Gantt v2 Schema Extension | 0/0 | Not started | - |
| 93. Cross-Use Flag Implementation | 0/0 | Not started | - |

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
| 64 | v1.8 | Complete | 2026-06-01 |
| 65-74 | v2.0 | Complete | 2026-06-02 |
| 75-82 | v2.1 | Complete | 2026-06-03 |
| 83-89 | v2.2 | Complete | 2026-06-05 |
| 90-93 | v2.3 | Active | - |

---
*Last updated: 2026-06-08 -- Phase 91 planned (1 plan)*
