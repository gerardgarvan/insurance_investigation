# Requirements: PCORnet Payer Variable Investigation — v2.2 Local Testing Infrastructure

**Defined:** 2026-06-03
**Core Value:** A working cohort filter chain that reads like a clinical protocol — with logged attrition at every step and clear payer-stratified visualizations showing how patients flow from enrollment through diagnosis to treatment.

## v2.2 Requirements

Requirements for local testing infrastructure: environment detection, test fixtures, validation, and supporting infrastructure.

### Environment Detection

- [x] **ENV-01**: Pipeline auto-detects local Windows vs HiPerGator Linux using Sys.info()
- [x] **ENV-02**: Environment overridable via R_TESTING_ENV environment variable
- [x] **ENV-03**: Local mode configures tests/fixtures/ for data, tempdir() for DuckDB and RDS cache
- [x] **ENV-04**: HiPerGator production mode is the safe default — no behavior change when env var unset
- [x] **ENV-05**: Environment detection logs which mode is active at startup
- [x] **ENV-06**: Local mode uses 1 thread; HiPerGator uses SLURM-allocated cores

### Test Fixtures

- [x] **FIX-01**: Hand-crafted fixture CSVs (~20 patients) covering all 13 PCORnet CDM tables in tests/fixtures/
- [x] **FIX-02**: Fixtures include all clinical edge cases: dual-eligible, NLPHL, SCT, multiple cancers, death dates, orphan dx, same-day multi-payer, 1900 sentinel dates
- [x] **FIX-03**: Fixture design documented in FIXTURE_DESIGN.md with patient-to-edge-case mapping
- [x] **FIX-04**: Fixture generation R script creates CSVs reproducibly from documented design
- [x] **FIX-05**: Fixture CSVs git-tracked for version control and diff visibility

### Testing & Validation

- [x] **TEST-01**: DuckDB ingest (R/03) works with fixture CSVs without code changes
- [x] **TEST-02**: R/88 smoke test passes locally against fixtures
- [x] **TEST-03**: Smoke test validates environment detection flag and fixture schema
- [x] **TEST-04**: Full pipeline end-to-end runnable locally
- [x] **TEST-05**: Conditional assertions in smoke test (fixture counts vs production counts)

### Infrastructure

- [x] **INFRA-01**: All path construction uses file.path() — no paste0 with path separators
- [x] **INFRA-02**: .gitignore updated for .Renviron, .duckdb files, local output artifacts
- [x] **INFRA-03**: Local output directories created automatically when missing
- [x] **INFRA-04**: .Renviron.example documents the override pattern

### Quality Standards

- [ ] **QUAL-01**: All new/modified scripts follow v2.0 standards (styler formatting, lintr compliance, checkmate assertions, documentation headers, smoke test updates)

## Previous Milestone Requirements (v2.1 — Complete)

### Cancer Classification

- [x] **CANCER-01**: NLPHL (C81.0 / 201.4x) broken out from Hodgkin Lymphoma as distinct cancer category
- [x] **CANCER-02**: Pre/post cancer summary table requires 7-day unique day gap for ALL cancer categories
- [x] **CANCER-03**: Cancer_category and triggering code description populated per episode

### Treatment Pipeline

- [x] **TREAT-01**: All treatment data sourced from tumor registry dropped
- [x] **TREAT-02**: Drug groupings centralized in R/00_config.R
- [x] **TREAT-03**: Two new summary tables (treatment-type-level + drug-level)

### Death Data

- [x] **DEATH-01**: Cause of death data quality profiled before integration
- [x] **DEATH-02**: Cause of death included in outputs

### Code Verification

- [x] **CODE-01**: "Replaced by" codes verified
- [x] **CODE-02**: SCT code 0362 patients investigated

### Quality Standards

- [x] **QUAL-01**: All v2.1 scripts follow v2.0 standards

## Future Requirements

### Visualization (deferred)

- **VIZ-01**: Attrition waterfall chart produced from filter log
- **VIZ-02**: Sankey/alluvial diagram stratified by payer
- **VIZ-03**: HIPAA small-cell suppression applied in all outputs

### v3.0+ Considerations

- **ORCH-01**: Pipeline orchestration via targets/drake (if pipeline grows >100 scripts)
- **CI-01**: CI/CD integration with automated lintr on PRs (if team grows >3 developers)
- **LOG-01**: Structured logging via logger package (if machine-readable logs needed)
- **PKG-01**: Full R package conversion with NAMESPACE/DESCRIPTION (if distributing pipeline)
- **SYNTH-01**: Full synthetic data generator with realistic distributions (if targeted fixtures prove insufficient)

## Out of Scope

| Feature | Reason |
|---------|--------|
| Full synthetic data generator | Targeted fixtures catch logic errors; real data testing stays on HiPerGator |
| Making all 75 scripts pass locally | Many scripts tightly coupled to real data shape; diminishing ROI |
| Large-scale synthetic datasets (100-1000 patients) | 20 patients sufficient for edge case testing |
| Docker/containerization | R + DuckDB install easily on Windows; container adds complexity |
| Automatic fixture refresh from production | HIPAA risk, complexity outweighs benefit |
| Multi-environment CI/CD | Not shipping software; single research team |
| Stanford V / BEACOPP regimen identification | Only 3 regimens cover ~95% of adult first-line |
| Pediatric protocols (age <21) | Adult protocols only for v1.x-v2.x |
| Statistical modeling / regression | Exploration only |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| ENV-01 | Phase 83 | Complete |
| ENV-02 | Phase 83 | Complete |
| ENV-03 | Phase 83 | Complete |
| ENV-04 | Phase 83 | Complete |
| ENV-05 | Phase 83 | Complete |
| ENV-06 | Phase 83 | Complete |
| FIX-01 | Phase 84 | Complete |
| FIX-02 | Phase 84 | Complete |
| FIX-03 | Phase 84 | Complete |
| FIX-04 | Phase 84 | Complete |
| FIX-05 | Phase 84 | Complete |
| TEST-01 | Phase 85 | Complete |
| TEST-02 | Phase 85 | Complete |
| TEST-03 | Phase 85 | Complete |
| TEST-04 | Phase 85 | Complete |
| TEST-05 | Phase 85 | Complete |
| INFRA-01 | Phase 83 | Complete |
| INFRA-02 | Phase 83 | Complete |
| INFRA-03 | Phase 83 | Complete |
| INFRA-04 | Phase 83 | Complete |
| QUAL-01 | Phase 86 | Pending |

**Coverage:**
- v2.2 requirements: 21 total (20 specific + 1 cross-cutting)
- Mapped to phases: 21/21 (100%)
- Unmapped: 0

**Coverage verification:**
- Environment Detection (ENV-01 through ENV-06): 6 requirements → Phase 83
- Infrastructure (INFRA-01 through INFRA-04): 4 requirements → Phase 83
- Test Fixtures (FIX-01 through FIX-05): 5 requirements → Phase 84
- Testing & Validation (TEST-01 through TEST-05): 5 requirements → Phase 85
- Quality Standards (QUAL-01): 1 requirement → Phase 86

**Total mapped:** 21/21 requirements (100% coverage)

---
*Requirements defined: 2026-06-03*
*Last updated: 2026-06-03 after roadmap creation*
