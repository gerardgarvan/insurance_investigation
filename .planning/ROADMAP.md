# Roadmap: v3.0 Performance Optimization with data.table

**Milestone:** v3.0 Performance Optimization with data.table
**Goal:** Replace named vector lookups and slow dplyr patterns with data.table joins and optimized operations across the full pipeline for significant speed gains on large PCORnet datasets.
**Created:** 2026-06-10
**Status:** Not started

## Phases

- [x] **Phase 95: Infrastructure Setup** - Add data.table infrastructure without changing behavior (completed 2026-06-10)
- [x] **Phase 96: classify_payer_tier_dt() Implementation** - Create data.table variant of most-called utility function (completed 2026-06-10)
- [x] **Phase 97: R/60 Hot-Path Migration** - Migrate same-day payer resolution to data.table (completed 2026-06-11)
- [ ] **Phase 98: R/28 + Remaining Lookup Optimization** - Replace named vector lookups with keyed joins

## Phase Details

### Phase 95: Infrastructure Setup
**Goal**: Data.table infrastructure added with zero behavior changes to existing pipeline
**Depends on**: Nothing (first phase)
**Requirements**: INFRA-01, INFRA-02, INFRA-03, INFRA-04
**Success Criteria** (what must be TRUE):
  1. User can run `renv::status()` and see data.table 1.18.4+ installed
  2. User can source R/utils/utils_dt.R and call ensure_dt(), to_tibble_safe(), get_lookup_dt() without errors
  3. User can run existing R/60_tiered_same_day_payer.R unchanged and outputs match pre-Phase-95 baseline
  4. User can access LOOKUP_TABLES_DT$AMC_PAYER_LOOKUP in R console and see keyed data.table with 234 rows
**Plans:** 2/2 plans complete
Plans:
- [x] 95-01-PLAN.md -- Create utils_dt.R conversion helpers and LOOKUP_TABLES_DT keyed data.tables in R/00_config.R
- [x] 95-02-PLAN.md -- Validation script and human verification of zero behavior change

### Phase 96: classify_payer_tier_dt() Implementation
**Goal**: Data.table variant of classify_payer_tier() function validated with output parity
**Depends on**: Phase 95 (LOOKUP_TABLES_DT infrastructure)
**Requirements**: PAYER-01, PAYER-02
**Success Criteria** (what must be TRUE):
  1. User can call classify_payer_tier_dt() on 1000-row fixture data and receive tibble with payer_category column matching classify_payer_tier() output
  2. User can run smoke test Section 15 and see parity assertion pass between classify_payer_tier() and classify_payer_tier_dt()
  3. User can inspect function header and see reference semantics documented with copy() usage at entry point
  4. User can call classify_payer_tier_dt() on factor-column input and see explicit as.character() coercion without NA matches
**Plans:** 1/1 plans complete
Plans:
- [x] 96-01-PLAN.md -- Implement classify_payer_tier_dt() function and parity validation script

### Phase 97: R/60 Hot-Path Migration
**Goal**: Same-day payer resolution script migrated to data.table with 5-20x speedup and output parity
**Depends on**: Phase 96 (classify_payer_tier_dt function)
**Requirements**: PERF-01, PERF-02, VALID-02
**Success Criteria** (what must be TRUE):
  1. User can run R/60_tiered_same_day_payer.R on production HiPerGator data and see CSV outputs identical to pre-optimization (diff shows no changes)
  2. User can inspect script header and see runtime benchmark log showing before/after execution times
  3. User can run smoke test R/88 Section 15f and see same-day payer resolution validation pass
  4. User can trace group_by PATID+ADMIT_DATE operations and see data.table [, by=] syntax with setkey() before aggregation
**Plans:** 1/1 plans complete
Plans:
- [x] 97-01-PLAN.md -- Migrate R/60 to data.table (all 3 sections) and create R/97 benchmark + parity validation script

### Phase 98: R/28 + Remaining Lookup Optimization
**Goal**: Episode classification and remaining lookup-heavy scripts migrated to keyed joins with correctness validation
**Depends on**: Phase 97 (hot-path migration pattern validated)
**Requirements**: PERF-03, PERF-04, VALID-01
**Success Criteria** (what must be TRUE):
  1. User can run R/28_episode_classification.R and see treatment_episodes.rds structure unchanged (25 columns, same order, same row count)
  2. User can grep for "DRUG_GROUPINGS\[" and see zero matches (all named vector lookups replaced with keyed joins)
  3. User can run full smoke test R/88 and see all 35 sections pass
  4. User can inspect R/28 and see DRUG_GROUPINGS keyed join syntax with on= parameter instead of named vector indexing
**Plans:** 1/2 plans executed
Plans:
- [x] 98-01-PLAN.md -- Migrate R/28 to explode-join-collapse and sweep 7 files for named vector elimination
- [ ] 98-02-PLAN.md -- Create R/98 parity validation script and human verification (v3.0 gate)

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 95. Infrastructure Setup | 2/2 | Complete   | 2026-06-10 |
| 96. classify_payer_tier_dt() Implementation | 1/1 | Complete    | 2026-06-10 |
| 97. R/60 Hot-Path Migration | 1/1 | Complete    | 2026-06-11 |
| 98. R/28 + Remaining Lookup Optimization | 1/2 | In Progress|  |

## Next Steps

1. Run `/gsd:execute-phase 98` to replace all named vector lookups with keyed joins
2. Wave 1: Plan 98-01 (R/28 migration + 7-file sweep)
3. Wave 2: Plan 98-02 (R/98 validation script + R/88 smoke test v3.0 gate)

### Phase 99: Fix Gantt v2 vs v1 Disagreements and Schema Consolidation

**Goal:** Consolidate R/51 (v1) and R/52 (v2) into single canonical Gantt export: delete v1, clean v2 schema (add is_hodgkin, remove immunotherapy columns, fix pseudo-treatment metadata), replace hardcoded column counts with dynamic schema verification, rename output files to drop _v2 suffix, update all downstream references.
**Requirements**: D-01, D-02, D-03, D-04, D-05, D-06, D-07, D-08, D-09, D-10, D-11, D-12, D-13, D-14, D-15
**Depends on:** Phase 98
**Plans:** 2 plans

Plans:
- [ ] 99-01-PLAN.md -- Modify R/52 schema (add is_hodgkin, remove extraneous columns, fix pseudo-treatment metadata, dynamic schema verification) and delete R/51
- [ ] 99-02-PLAN.md -- Update R/88 smoke tests for Phase 99 changes and create R/99 validation script
