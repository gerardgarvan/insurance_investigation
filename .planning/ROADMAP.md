# Roadmap: v3.1 Meeting Gap Closure — Clinical Data Coverage

**Milestone:** v3.1 Meeting Gap Closure — Clinical Data Coverage
**Goal:** Close analytical gaps identified in team meetings by quantifying unlinked treatments, analyzing single-agent co-administration patterns, producing death date cross-tabs, and improving cancer linkage rates via the CONDITION table.
**Created:** 2026-06-12
**Status:** Not started

**Previous milestone context:** v3.0 (Phases 95-99) delivered data.table infrastructure, classify_payer_tier_dt() optimization, R/60 and R/28 migrations, and consolidated Gantt export with dynamic schema verification.

## Phases

- [x] **Phase 100: CONDITION Table Cancer Linkage** - Supplement DIAGNOSIS-based linkage with CONDITION table to reduce unlinked episode rate (completed 2026-06-12)
- [ ] **Phase 101: Broadened Drug Grouping Output** - Expand drug grouping to all treatment encounters regardless of cancer linkage
- [ ] **Phase 102: Single-Agent Co-Administration Analysis** - Detect fragmented regimen patterns via 30-day co-administration windows
- [ ] **Phase 103: Death Date Cross-Tab Summary** - Produce death date presence and post-death encounter cross-tabs

## Phase Details

### Phase 100: CONDITION Table Cancer Linkage
**Goal**: Investigate CONDITION table as 3rd-tier cancer linkage supplement (read-only investigation producing improvement report)
**Depends on**: Nothing (first phase in v3.1)
**Requirements**: COND-01, COND-02, COND-03
**Plans:** 1/1 plans complete
Plans:
- [x] 100-01-PLAN.md — CONDITION linkage investigation script + smoke test validation
**Success Criteria** (what must be TRUE):
  1. User can run R/30_condition_linkage_investigation.R and see CONDITION table queried as 3rd-tier supplement showing what COULD be linked
  2. User can open episode_classification_audit.xlsx "Linkage Improvement" sheet and see before/after unlinked episode rates with treatment type breakdown
  3. User can run smoke test R/88 and see R/30 structural validation passing
  4. No existing RDS files, xlsx sheets, or outputs are modified by R/30 (investigation only)

### Phase 101: Broadened Drug Grouping Output
**Goal**: Drug grouping instances output includes ALL treatment encounters with cancer_linked flag, preserving existing cancer-linked-only output
**Depends on**: Phase 100 (improved linkage means better cancer_linked flag accuracy)
**Requirements**: DRUG-01, DRUG-02, DRUG-03
**Success Criteria** (what must be TRUE):
  1. User can open drug_grouping_instances.xlsx and see ALL treatment encounters (not just cancer-linked) with new cancer_linked TRUE/FALSE flag column
  2. User can verify existing cancer-linked-only output preserved as separate file with _linked_only suffix
  3. User can run cross-tab summary and see unlinked vs linked treatment counts by type (Chemo, RT, SCT, Immuno, Proton)
  4. User can inspect broadened output and see identical row structure to existing output plus cancer_linked column
**Plans**: TBD

### Phase 102: Single-Agent Co-Administration Analysis
**Goal**: Fragmented regimen patterns surfaced via 30-day co-administration window for single-agent chemotherapy encounters
**Depends on**: Phase 101 (broadened drug grouping provides full single-agent encounter base)
**Requirements**: COADMIN-01, COADMIN-02
**Success Criteria** (what must be TRUE):
  1. User can open co_administration_detail.xlsx and see each single-agent chemo encounter with all chemotherapies found within ±30 days
  2. User can review pattern summary table and see most common pairings ranked by frequency (e.g., "Drug A + Drug B: 45 instances")
  3. User can filter detail table to specific drug and trace all co-administered drugs across patient encounters
  4. User can identify fragmented ABVD/BV+AVD patterns via co-administration temporal clustering
**Plans**: TBD

### Phase 103: Death Date Cross-Tab Summary
**Goal**: Clean presentable death date cross-tab table answering team questions about death date coverage and post-death activity
**Depends on**: Nothing (independent analysis)
**Requirements**: DEATH-01
**Success Criteria** (what must be TRUE):
  1. User can open death_date_summary.xlsx and see unstratified cross-tab with three counts: (i) patients with death date, (ii) of those, how many have death as last encounter, (iii) how many have encounters after death
  2. User can verify counts match existing death date data quality analysis from Phase 62
  3. User can present table in team meeting without additional formatting (clean, labeled, HIPAA-compliant with <11 suppression)
  4. User can trace logic back to DEATH table and verify death date presence vs ENCOUNTER timing alignment
**Plans**: TBD

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 100. CONDITION Table Cancer Linkage | 1/1 | Complete   | 2026-06-12 |
| 101. Broadened Drug Grouping Output | 0/? | Not started | - |
| 102. Single-Agent Co-Administration Analysis | 0/? | Not started | - |
| 103. Death Date Cross-Tab Summary | 0/? | Not started | - |

## Next Steps

1. Execute Phase 100: `/gsd:execute-phase 100`
2. Plan Phase 101 after Phase 100 completes
3. Plan Phase 102 after Phase 101 completes
4. Plan Phase 103 (independent, can execute anytime)

## Coverage

**v3.1 Requirements:** 9 total
- DRUG: 3 requirements -> Phase 101
- COADMIN: 2 requirements -> Phase 102
- DEATH: 1 requirement -> Phase 103
- COND: 3 requirements -> Phase 100

**Coverage:** 9/9 requirements mapped (100%)
