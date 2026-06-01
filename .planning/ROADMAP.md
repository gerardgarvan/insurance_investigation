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
- **v2.0 Codebase Cleanup & Documentation** — Phases 65-74 (active) — see below

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

## v2.0 Codebase Cleanup & Documentation (Active Milestone)

**Milestone Goal:** Reorganize, harden, and document the entire R pipeline for maintainability and onboarding.

**Granularity:** Coarse
**Requirements Coverage:** 17/17 mapped (100%)

### Phases

- [x] **Phase 65: Foundation Reorganization** - Renumber foundation scripts (00-09) and create utils/ folder (completed 2026-06-01)
- [ ] **Phase 66: Cohort & Treatment Reorganization** - Renumber cohort (10-19) and treatment (20-39) scripts
- [ ] **Phase 67: Cancer & Payer/QA Reorganization** - Renumber cancer (40-59) and payer/QA (60-69) scripts
- [ ] **Phase 68: Output & Test Reorganization** - Renumber output (70-79), test (80-89), and ad-hoc (90-99) scripts
- [ ] **Phase 69: Script Documentation** - Add header blocks, section headers, and inline comments
- [ ] **Phase 70: Automated Formatting** - Apply styler and configure lintr
- [ ] **Phase 71: Linting Cleanup** - Fix lintr violations incrementally
- [ ] **Phase 72: Defensive Coding** - Add checkmate assertions and input validation
- [ ] **Phase 73: DRY Consolidation** - Consolidate duplicate lookups and extract utility functions
- [ ] **Phase 74: Smoke Testing & Reference Manual** - Create comprehensive smoke tests and dependency documentation

### Phase Details

#### Phase 65: Foundation Reorganization
**Goal**: Foundation scripts (config, data loading, payer harmonization) are renumbered to 00-09 with utils/ folder structure established
**Depends on**: Phase 64
**Requirements**: REORG-01, REORG-03, REORG-04
**Success Criteria** (what must be TRUE):
  1. All 7 utils_*.R modules moved to R/utils/ subfolder
  2. R/00_config.R auto-sources all utils/ files on load
  3. Foundation scripts (DuckDB ingest, data loading, payer harmonization) renumbered to 01-03
  4. All source() calls referencing foundation scripts updated to new numbers
  5. Smoke test validates no broken cross-references for foundation scripts
**Plans:** 2/2 plans complete
Plans:
- [x] 65-01-PLAN.md -- Move utils to R/utils/, renumber 25->03, update all source() references
- [x] 65-02-PLAN.md -- Create smoke test, update documentation (SCRIPT_INDEX, existing smoke test)

#### Phase 66: Cohort & Treatment Reorganization
**Goal**: Cohort building (10-19) and treatment analysis (20-39) scripts are renumbered sequentially with updated cross-references
**Depends on**: Phase 65
**Requirements**: REORG-01, REORG-02
**Success Criteria** (what must be TRUE):
  1. Cohort scripts renumbered to 10-19 decade in execution order
  2. Treatment scripts (currently 38-44, 60-62) consolidated to 20-27 in 20-39 decade
  3. All source() cross-references updated (95+ total across codebase)
  4. RDS artifacts (hl_cohort.rds, treatment_episodes.rds) structure unchanged (parity test passes)
  5. Smoke test validates all cohort and treatment source() calls resolve
**Plans**: TBD

#### Phase 67: Cancer & Payer/QA Reorganization
**Goal**: Cancer diagnosis (40-59) and payer/QA (60-69) scripts are renumbered with validated dependencies
**Depends on**: Phase 66
**Requirements**: REORG-01, REORG-02
**Success Criteria** (what must be TRUE):
  1. Cancer site scripts (47-58) renumbered to 40-44 in 40-59 decade
  2. Payer/QA scripts consolidated to 60-67 in 60-69 decade
  3. cancer_summary.rds and confirmed_hl_cohort.rds row counts unchanged
  4. All source() references to cancer and payer scripts updated
  5. Smoke test validates cancer and payer script dependencies
**Plans**: TBD

#### Phase 68: Output & Test Reorganization
**Goal**: Output, test, and ad-hoc scripts are renumbered to final positions with deprecated scripts archived
**Depends on**: Phase 67
**Requirements**: REORG-01, REORG-02, REORG-04, REORG-05
**Success Criteria** (what must be TRUE):
  1. Visualization/report scripts renumbered to 70-77 in 70-79 decade
  2. Test/diagnostic scripts renumbered to 80-85 in 80-89 decade
  3. Ad-hoc exploratory scripts renumbered to 90-98 in 90-99 decade
  4. R/archive/ folder created with 6 deprecated scripts and explanatory README
  5. Comprehensive smoke test validates all 80 scripts have sequential numbering and resolvable source() calls
**Plans**: TBD

#### Phase 69: Script Documentation
**Goal**: Every script has header blocks, section headers, and explanatory comments for maintainability
**Depends on**: Phase 68
**Requirements**: DOC-01, DOC-02, DOC-03
**Success Criteria** (what must be TRUE):
  1. All 80 production scripts have header blocks (purpose, inputs, outputs, dependencies)
  2. All scripts have section headers with 4+ dashes (RStudio Ctrl+Shift+O outline works)
  3. Non-obvious logic has inline comments explaining WHY (clinical rules, payer hierarchy, complex joins)
  4. Comments use roxygen2-style #' syntax for complex utility functions
  5. Documentation validation confirms no missing headers or sections
**Plans**: TBD

#### Phase 70: Automated Formatting
**Goal**: Codebase is consistently formatted via styler with lintr configured for project
**Depends on**: Phase 69
**Requirements**: SAFE-04, SAFE-05
**Success Criteria** (what must be TRUE):
  1. styler applied to R/ directory only (output/, cache/, renv/ excluded via .stylerignore)
  2. All R scripts follow tidyverse style (spacing, indentation, line breaks)
  3. .lintr configuration file disables object_name_linter (ALLCAPS PCORnet columns)
  4. .lintr line_length_linter set to 120 characters
  5. lintr baseline run identifies violations for next phase (count recorded)
**Plans**: TBD

#### Phase 71: Linting Cleanup
**Goal**: lintr violations are reduced to manageable baseline with high-severity issues fixed
**Depends on**: Phase 70
**Requirements**: SAFE-05
**Success Criteria** (what must be TRUE):
  1. HIGH-severity lintr violations fixed (commented code, T/F vs TRUE/FALSE)
  2. MEDIUM-severity violations fixed where feasible (long lines, complex expressions)
  3. LOW-severity violations documented and deferred (trailing whitespace)
  4. lintr violation count reduced to <50 manageable items
  5. All fixes validated via smoke test (pipeline still runs)
**Plans**: TBD

#### Phase 72: Defensive Coding
**Goal**: Critical functions have input validation and error handling with informative messages
**Depends on**: Phase 71
**Requirements**: SAFE-01, SAFE-02, SAFE-03
**Success Criteria** (what must be TRUE):
  1. File existence checks (checkmate assert_file_exists) at start of all data-loading scripts
  2. Data structure validation after critical loads/joins (assert_data_frame, assert_names, assert_subset)
  3. Error messages use glue() with context (file paths, expected vs actual, script name)
  4. Assertions validate at function entry (NOT inside hot loops)
  5. Smoke test confirms assertions catch invalid inputs without false positives
**Plans**: TBD

#### Phase 73: DRY Consolidation
**Goal**: Duplicate lookups consolidated to R/00_config.R and repeated patterns extracted to utilities
**Depends on**: Phase 72
**Requirements**: DRY-01, DRY-02
**Success Criteria** (what must be TRUE):
  1. All PREFIX_MAP and code mapping duplicates consolidated to R/00_config.R
  2. grep confirms no duplicate constant definitions remain in codebase
  3. Repeated code patterns (3+ occurrences) extracted to shared utility functions in R/utils/
  4. Old lookup copies deleted in same commit as consolidation
  5. Smoke test validates constants defined only once and utilities work correctly
**Plans**: TBD

#### Phase 74: Smoke Testing & Reference Manual
**Goal**: Comprehensive smoke test suite and reference manual document pipeline for maintainability
**Depends on**: Phase 73
**Requirements**: REORG-05, SAFE-06, DOC-04
**Success Criteria** (what must be TRUE):
  1. Comprehensive testthat smoke test suite validates sequential numbering, source() resolution, RDS dependencies
  2. Smoke tests verify config constants exist and critical scripts run without error
  3. Reference manual created with dependency matrix (Script -> Inputs/Outputs/Dependencies for all 80 scripts)
  4. Reference manual includes run-order guide and onboarding instructions
  5. All tests pass on both Windows (local) and HiPerGator (Linux)
**Plans**: TBD

### v2.0 Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 65. Foundation Reorganization | 2/2 | Complete    | 2026-06-01 |
| 66. Cohort & Treatment Reorganization | 0/0 | Not started | - |
| 67. Cancer & Payer/QA Reorganization | 0/0 | Not started | - |
| 68. Output & Test Reorganization | 0/0 | Not started | - |
| 69. Script Documentation | 0/0 | Not started | - |
| 70. Automated Formatting | 0/0 | Not started | - |
| 71. Linting Cleanup | 0/0 | Not started | - |
| 72. Defensive Coding | 0/0 | Not started | - |
| 73. DRY Consolidation | 0/0 | Not started | - |
| 74. Smoke Testing & Reference Manual | 0/0 | Not started | - |

---
*Last updated: 2026-06-01 -- Phase 65 planned (2 plans)*
