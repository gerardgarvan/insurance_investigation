# Requirements: PCORnet Payer Variable Investigation — v2.0 Codebase Cleanup & Documentation

**Defined:** 2026-06-01
**Core Value:** A working cohort filter chain that reads like a clinical protocol — with logged attrition at every step and clear payer-stratified visualizations showing how patients flow from enrollment through diagnosis to treatment.

## v2.0 Requirements

Requirements for codebase reorganization, documentation, hardening, and redundancy removal.

### Reorganization

- [x] **REORG-01**: All R scripts renumbered sequentially using decade-based scheme (00-09 foundation, 10-19 cohort, 20-39 treatment, 40-59 cancer, 60-69 payer/QA, 70-79 outputs, 80-89 tests, 90-99 ad-hoc) with no gaps, duplicates, or sub-letter suffixes
- [x] **REORG-02**: All source() cross-references (95+) updated to match new script numbers and paths
- [x] **REORG-03**: Utility modules (utils_*.R) moved to R/utils/ subfolder with 00_config.R auto-sourcing them
- [x] **REORG-04**: Deprecated/superseded scripts moved to R/archive/ folder with README explaining their status
- [x] **REORG-05**: Smoke test validates no broken cross-references after each renumbering phase (RDS artifacts unchanged, source() calls resolve)

### Documentation

- [ ] **DOC-01**: Every script has a header block documenting purpose, inputs, outputs, and dependencies
- [ ] **DOC-02**: Every script has section headers with 4+ dashes for RStudio outline navigation (Ctrl+Shift+O)
- [ ] **DOC-03**: Non-obvious logic has inline comments explaining WHY (clinical rules, complex joins, business mappings, payer hierarchy decisions)
- [ ] **DOC-04**: Full reference manual created with dependency matrix (Script -> Inputs/Outputs/Dependencies table for all scripts) and run-order guide

### Safety

- [ ] **SAFE-01**: Input file existence validation (checkmate assert_file_exists) at the start of every script that loads data
- [ ] **SAFE-02**: Data structure validation after critical loads and joins (checkmate assertions for expected columns, types, and row-count sanity checks)
- [ ] **SAFE-03**: Error messages include context using glue() — file paths, expected vs actual values, script name
- [ ] **SAFE-04**: All scripts auto-formatted with styler (tidyverse style), with .stylerignore protecting non-R directories
- [ ] **SAFE-05**: lintr configured with project .lintr file (object_name_linter disabled for PCORnet ALLCAPS columns, line_length_linter(120))
- [ ] **SAFE-06**: Comprehensive smoke test suite (testthat) verifying pipeline integrity — sequential numbering, source() resolution, RDS dependency checks, critical script execution without error

### DRY (Redundancy Removal)

- [ ] **DRY-01**: All duplicated lookup tables (PREFIX_MAP, code mappings, category constants) consolidated to R/00_config.R with old copies deleted
- [ ] **DRY-02**: Repeated code patterns (3+ occurrences) extracted into shared utility functions in R/utils/ files

## Future Requirements

### Carried from v1.0 (deferred, not in v2.0 scope)

- **VIZ-01**: Produce attrition waterfall chart from filter log
- **VIZ-02**: Produce Sankey/alluvial stratified by payer
- **VIZ-03**: Apply HIPAA small-cell suppression in outputs

### v3.0+ Considerations

- **ORCH-01**: Pipeline orchestration via targets/drake (if pipeline grows >100 scripts)
- **CI-01**: CI/CD integration with automated lintr on PRs (if team grows >3 developers)
- **LOG-01**: Structured logging via logger package (if machine-readable logs needed)
- **PKG-01**: Full R package conversion with NAMESPACE/DESCRIPTION (if distributing pipeline)

## Out of Scope

| Feature | Reason |
|---------|--------|
| Full R package conversion (NAMESPACE, DESCRIPTION) | Over-engineering for analysis pipeline; package overhead not justified |
| Automated style enforcement on every commit (git hooks) | Adds friction; HiPerGator workflow doesn't use git heavily |
| Unit tests for every function | Analysis scripts, not production software; high maintenance cost vs value |
| Interactive documentation (pkgdown site) | Overkill for 1-2 person project; static markdown sufficient |
| Pipeline orchestration (targets/drake) | Major architecture change; existing sequential scripts work; defer to v3+ |
| Comprehensive input validation (pointblank) | Python pipeline handles data cleaning; R pipeline validates cohort logic only |
| Refactoring to object-oriented (R6 classes) | Analysis pipeline = procedural workflow; OOP adds complexity without benefits |
| Statistical modeling / regression | Exploration only; not in scope for any current milestone |
| Publication-ready figure formatting | Exploratory quality sufficient |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| REORG-01 | Phase 65, 66, 67, 68 | Complete |
| REORG-02 | Phase 66, 67, 68 | Complete |
| REORG-03 | Phase 65 | Complete |
| REORG-04 | Phase 68 | Complete |
| REORG-05 | Phase 68, 74 | Complete |
| DOC-01 | Phase 69 | Pending |
| DOC-02 | Phase 69 | Pending |
| DOC-03 | Phase 69 | Pending |
| DOC-04 | Phase 74 | Pending |
| SAFE-01 | Phase 72 | Pending |
| SAFE-02 | Phase 72 | Pending |
| SAFE-03 | Phase 72 | Pending |
| SAFE-04 | Phase 70 | Pending |
| SAFE-05 | Phase 70, 71 | Pending |
| SAFE-06 | Phase 74 | Pending |
| DRY-01 | Phase 73 | Pending |
| DRY-02 | Phase 73 | Pending |

**Coverage:**
- v2.0 requirements: 17 total
- Mapped to phases: 17 (100%)
- Unmapped: 0

---
*Requirements defined: 2026-06-01*
*Last updated: 2026-06-01 after roadmap creation*
