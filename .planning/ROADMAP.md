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

- [x] **Phase 65: Foundation Reorganization** - Renumber foundation scripts (00-09) and create utils/ folder (completed 2026-06-01)
- [x] **Phase 66: Cohort & Treatment Reorganization** - Comprehensive renumbering of ALL scripts into final decade positions (scope expanded from original cohort+treatment to include all decades) (completed 2026-06-01)
- [x] **Phase 67: Post-Renumbering Inventory Cleanup** - Resolve 66-prefix collision, archive unnumbered scripts, regenerate SCRIPT_INDEX.md (repurposed from original cancer/payer scope) (gap closure in progress) (completed 2026-06-01)
- [x] **Phase 68: Output & Test Reorganization (Verification Gate)** - Verify reorganization requirements, fix documentation drift, create HiPerGator validation checklist (completed 2026-06-02)
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
**Goal**: All pipeline scripts (03-63+) renumbered into final decade positions in one comprehensive pass with all source() cross-references updated
**Depends on**: Phase 65
**Requirements**: REORG-01, REORG-02
**Success Criteria** (what must be TRUE):
  1. Cohort scripts renumbered to 10-14 (helpers before build_cohort)
  2. Treatment scripts renumbered to 20-29 (no a/b suffixes)
  3. Cancer scripts renumbered to 40-53 (gantt exports in cancer decade)
  4. Payer/QA scripts renumbered to 60-69
  5. Output scripts renumbered to 70-75
  6. Test scripts renumbered to 80-86
  7. Ad-hoc scripts renumbered to 90-99
  8. All source() cross-references updated (95+ total across codebase)
  9. Comprehensive smoke test validates all decades and source() resolution
  10. SCRIPT_INDEX.md regenerated with complete new numbering
**Plans:** 3/3 plans complete
Plans:
- [x] 66-01-PLAN.md -- Renumber cohort (10-14) and treatment (20-29) scripts with source() updates
- [x] 66-02-PLAN.md -- Renumber cancer (40-53) and payer/QA (60-69) scripts with source() updates
- [x] 66-03-PLAN.md -- Renumber outputs (70-75), tests (80-86), ad-hoc (90-99), create smoke test, regenerate SCRIPT_INDEX

#### Phase 67: Post-Renumbering Inventory Cleanup
**Goal**: Resolve 66-prefix smoke test collision, archive 8 unnumbered scripts to R/archive/, and regenerate SCRIPT_INDEX.md from filesystem
**Depends on**: Phase 66
**Requirements**: REORG-01, REORG-02
**Success Criteria** (what must be TRUE):
  1. 66_smoke_test_full_pipeline.R moved to 87_smoke_test_full_pipeline.R (test decade)
  2. Payer/QA decade has 10 scripts (60-69) with no collision
  3. Test decade has 8 scripts (80-87) including full-pipeline smoke test
  4. All 8 unnumbered scripts archived to R/archive/ with README.md
  5. SCRIPT_INDEX.md regenerated from filesystem (guaranteed accurate)
**Plans:** 2/2 plans complete
Plans:
- [x] 67-01-PLAN.md -- Move smoke test to 87, archive unnumbered scripts, regenerate SCRIPT_INDEX
- [x] 67-02-PLAN.md -- Fix payer decade counts in SCRIPT_INDEX, smoke test, and ROADMAP (gap closure)

#### Phase 68: Output & Test Reorganization (Repurposed: Verification Gate)
**Goal**: Verify reorganization requirements (REORG-01 through REORG-05) are satisfied, fix documentation drift (SCRIPT_INDEX cancer decade), create HiPerGator validation checklist, and formally close the reorganization work stream
**Depends on**: Phase 67
**Requirements**: REORG-01, REORG-02, REORG-04, REORG-05
**Success Criteria** (what must be TRUE):
  1. Structural scan confirms 67 numbered scripts across 8 decades with correct counts per decade
  2. SCRIPT_INDEX.md fully aligned with filesystem (zero filename discrepancies)
  3. R/87 smoke test expected arrays match actual filenames (cancer decade corrected)
  4. R/archive/ contains 8 deprecated scripts with README.md (REORG-04 confirmed)
  5. HiPerGator validation checklist created for deferred REORG-05 data-dependent checks
  6. REQUIREMENTS.md traceability updated (REORG-04 complete, REORG-05 structural done)
**Plans:** 2/2 plans complete
Plans:
- [x] 68-01-PLAN.md -- Structural verification scan + fix SCRIPT_INDEX and smoke test discrepancies
- [x] 68-02-PLAN.md -- HiPerGator checklist creation + documentation updates (ROADMAP, REQUIREMENTS, STATE)

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
**Plans:** 7/8 plans executed
Plans:
- [x] 69-01-PLAN.md -- Foundation (00-03) + Utils (8 files) header/section/WHY documentation
- [x] 69-02-PLAN.md -- Cohort (10-14) header/section/WHY documentation
- [x] 69-03-PLAN.md -- Treatment (20-29) header/section/WHY documentation
- [x] 69-04-PLAN.md -- Cancer (40-53) header/section/WHY documentation
- [x] 69-05-PLAN.md -- Payer/QA (60-69) header/section/WHY documentation
- [x] 69-06-PLAN.md -- Outputs (70-75) + Tests (80-87) header/section/WHY documentation
- [x] 69-07-PLAN.md -- Ad-hoc (90-99) header/section/WHY documentation
- [ ] 69-08-PLAN.md -- Cross-codebase validation scan + gap fixes

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
| 66. Cohort & Treatment Reorganization | 3/3 | Complete    | 2026-06-01 |
| 67. Post-Renumbering Inventory Cleanup | 2/2 | Complete    | 2026-06-01 |
| 68. Output & Test Reorganization (Verification Gate) | 2/2 | Complete    | 2026-06-02 |
| 69. Script Documentation | 7/8 | In Progress|  |
| 70. Automated Formatting | 0/0 | Not started | - |
| 71. Linting Cleanup | 0/0 | Not started | - |
| 72. Defensive Coding | 0/0 | Not started | - |
| 73. DRY Consolidation | 0/0 | Not started | - |
| 74. Smoke Testing & Reference Manual | 0/0 | Not started | - |

---
*Last updated: 2026-06-02 -- Phase 69 plans created (8 plans in 2 waves)*
