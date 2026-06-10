# Requirements: PCORnet Payer Variable Investigation (R Pipeline)

**Defined:** 2026-06-09
**Core Value:** A working cohort filter chain that reads like a clinical protocol -- with logged attrition at every step and clear payer-stratified visualizations showing how patients flow from enrollment through diagnosis to treatment.

## v3.0 Requirements

Requirements for performance optimization milestone. Each maps to roadmap phases.

### Infrastructure

- [x] **INFRA-01**: data.table 1.18.4+ added as project dependency in renv.lock
- [x] **INFRA-02**: R/utils/utils_dt.R created with conversion helpers (ensure_dt, to_tibble_safe, get_lookup_dt)
- [x] **INFRA-03**: LOOKUP_TABLES_DT list in R/00_config.R with 6 keyed data.tables (AMC_PAYER_LOOKUP, DRUG_GROUPINGS, CODE_SUBCATEGORY_MAP, CANCER_SITE_MAP, TIER_MAPPING, TREATMENT_CODES)
- [x] **INFRA-04**: All existing scripts run unchanged after infrastructure addition (zero behavior change)

### Payer Classification

- [ ] **PAYER-01**: classify_payer_tier_dt() function using keyed joins and fcase() logic alongside existing dplyr version
- [ ] **PAYER-02**: Output parity between classify_payer_tier() and classify_payer_tier_dt() validated on fixture data

### Hot-Path Optimization

- [ ] **PERF-01**: R/60 same-day payer resolution migrated to data.table by= aggregation
- [ ] **PERF-02**: R/60 CSV outputs identical pre/post optimization (diff validation)
- [ ] **PERF-03**: R/28 episode classification lookups replaced with keyed joins
- [ ] **PERF-04**: R/28 treatment_episodes.rds structure unchanged (same columns, same order)

### Validation

- [ ] **VALID-01**: Smoke test R/88 passes with all existing sections after optimization
- [ ] **VALID-02**: Runtime benchmark logged (before/after timings for optimized scripts)

## Future Requirements

### Extended Optimization (v3.1+)

- **PERF-05**: R/02 payer harmonization case_when replacement with fcase()
- **PERF-06**: R/11 treatment payer lookup optimization
- **PERF-07**: dtplyr fallback path for scripts not worth full data.table migration
- **PERF-08**: Rolling joins for temporal payer lookups (treatment date +/-30 days)

## Out of Scope

| Feature | Reason |
|---------|--------|
| Complete dplyr removal | Conflicts with named predicate readability requirement (has_*, with_*, exclude_*) |
| collapse package adoption | Unnecessary third syntax paradigm; data.table covers all project use cases |
| DuckDB replacement | data.table is in-memory only; DuckDB provides disk-backed lazy queries for 1-5GB CSVs |
| Factor-level encoding for payer categories | 8-category system sees negligible memory savings, added join complexity |
| Native data.table in all 77 scripts | Over-optimization; 90% process <100K rows where dplyr is adequate |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| INFRA-01 | Phase 95 | Complete |
| INFRA-02 | Phase 95 | Complete |
| INFRA-03 | Phase 95 | Complete |
| INFRA-04 | Phase 95 | Complete |
| PAYER-01 | Phase 96 | Pending |
| PAYER-02 | Phase 96 | Pending |
| PERF-01 | Phase 97 | Pending |
| PERF-02 | Phase 97 | Pending |
| PERF-03 | Phase 98 | Pending |
| PERF-04 | Phase 98 | Pending |
| VALID-01 | Phase 98 | Pending |
| VALID-02 | Phase 97 | Pending |

**Coverage:**
- v3.0 requirements: 12 total
- Mapped to phases: 12
- Unmapped: 0

---
*Requirements defined: 2026-06-09*
*Last updated: 2026-06-10 after roadmap creation*
