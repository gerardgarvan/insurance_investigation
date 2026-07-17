# Roadmap: PCORnet Payer Variable Investigation (R Pipeline)

## Milestones

- ✅ **v1.0 MVP** - Phases 1-14 (shipped 2026-04-01)
- ✅ **v1.1 RDS Cache & Visualization Polish** - Phases 15-17 (shipped 2026-04-03)
- ✅ **v1.2 Multi-Source Overlap Investigation** - Phases 19-25 (on hold)
- ✅ **v1.3 DuckDB Backend Migration** - Phases 29-32 (shipped 2026-04-23)
- ✅ **v1.4 AV+TH Subset Analysis** - Phase 33 (shipped 2026-04-27)
- ✅ **v1.5 Payer Analysis Expansion** - Phases 34-37 (shipped 2026-05-01)
- ✅ **v1.6 Treatment Code Validation & Cancer Site Analysis** - Phases 45-54 (shipped 2026-05-22)
- ✅ **v1.7 Cancer Summary Refinement & Gantt Enhancements** - Phases 55-59 (shipped 2026-05-28)
- ✅ **v1.8 Episode-Level Cancer Linkage & First-Line Therapy Identification** - Phases 60-63 (shipped 2026-06-01)
- ✅ **v2.0 Codebase Cleanup & Documentation** - Phases 65-74 (shipped 2026-06-02)
- ✅ **v2.1 Clinical Data Refinements & NLPHL Breakout** - Phases 75-82 (shipped 2026-06-03)
- ✅ **v2.2 Local Testing Infrastructure & Clinical Refinements** - Phases 83-89 (shipped 2026-06-05)
- ✅ **v2.3 Gantt Data Enrichment** - Phases 90-94 (shipped 2026-06-08)
- ✅ **v3.0 data.table Infrastructure** - Phases 95-99 (shipped 2026-06-11)
- ✅ **v3.1 Meeting Gap Closure — Clinical Data Coverage** - Phases 100-103 (shipped 2026-06-12)
- ✅ **v3.2 Meeting Gap Resolution Report** - Phases 104-126 (shipped 2026-07-15)
- ✅ **v3.3 Rituximab/Methotrexate-Associated Diagnoses of Interest** - Phases 127-130 (shipped 2026-07-17)

## Phases

<details>
<summary>✅ v1.0 through v3.2 (Phases 1-126) - SHIPPED 2026-07-15</summary>

See MILESTONES.md for full details on all shipped milestones.

126 phases completed across 16 milestones. Key capabilities delivered:
- PCORnet CDM loading, payer harmonization, cohort filter chain
- DuckDB backend with dual-environment support (HiPerGator + Windows)
- data.table infrastructure with 6 keyed lookup tables
- Treatment episodes with encounter-level cancer linkage and regimen identification
- Unified ICD-9/ICD-10 cancer code handling via utils_cancer.R
- Instance-level drug grouping tables, consolidated Gantt export
- MED_ADMIN/DISPENSING chemo-detection fix (+1,328 patients / +13,762 chemo dates)
- Comprehensive smoke test (R/88) exits 0 on HiPerGator

</details>

<details>
<summary>✅ v3.3 Rituximab/Methotrexate-Associated Diagnoses of Interest (Phases 127-130) — SHIPPED 2026-07-17</summary>

- [x] **Phase 127: Code-Set and Infrastructure Centralization** (2 plans) — DOI_CODE_MAP + utils_doi.R + fixture augmentation (completed 2026-07-15)
- [x] **Phase 128: DoI Classification** (2 plans) — DuckDB DIAGNOSIS pull, classify, mutual-exclusivity hard-stop, cached artifacts (completed 2026-07-15)
- [x] **Phase 129: Attribution Linkage and Output** (2 plans) — Two-tier join, three-state flag, 4-sheet xlsx (completed 2026-07-16)
- [x] **Phase 130: Registration, Smoke Test, and HiPerGator Runtime** (2 plans) — R/39 + SCRIPT_INDEX + R/88 Section 15w + runtime gate (completed 2026-07-17)

See `.planning/milestones/v3.3-ROADMAP.md` for full phase details.

</details>

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 127. Code-Set and Infrastructure | v3.3 | 2/2 | Complete | 2026-07-15 |
| 128. DoI Classification | v3.3 | 2/2 | Complete | 2026-07-15 |
| 129. Attribution Linkage and Output | v3.3 | 2/2 | Complete | 2026-07-16 |
| 130. Registration, Smoke Test, HiPerGator | v3.3 | 2/2 | Complete | 2026-07-17 |

### Phase 131: update all_codes_resolved_next_tables_v2.1_new.xlsx to include med_admin codes and also every tab should have a normalized name column

**Goal:** Add MED_ADMIN-exclusive RxNorm CUI rows and a uniform normalized_name column to every code tab in the reference xlsx workbook; update R/105 and R/88 to use the new column name.
**Requirements**: 131-A (normalized_name column all tabs), 131-B (MED_ADMIN rows), 131-C (R/105 + R/88 rename)
**Depends on:** Phase 130
**Plans:** 2 plans

Plans:
- [ ] 131-01-PLAN.md — Build R/131 script: MED_ADMIN anti-join + normalized_name columns for all xlsx tabs
- [ ] 131-02-PLAN.md — Update R/105 header string + R/88 section 15r Check 12 assertion
