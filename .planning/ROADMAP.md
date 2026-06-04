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
- **v2.2 Local Testing Infrastructure** — Phases 83-86 (active) — see below

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

## v2.2 Local Testing Infrastructure (Active Milestone)

**Milestone Goal:** Add environment auto-detection to R/00_config.R and create targeted test fixtures with clinical edge cases so key pipeline logic can be verified locally on Windows before deploying to HiPerGator.

**Granularity:** Coarse
**Requirements Coverage:** 21/21 mapped (100%)

### Phases

- [x] **Phase 83: Environment Detection & Infrastructure** - Auto-detect local vs HiPerGator, configure conditional paths, set up testing infrastructure (completed 2026-06-04)
- [ ] **Phase 84: Test Fixture Design & Creation** - Design and create hand-crafted CSVs covering clinical edge cases
- [ ] **Phase 85: Testing Integration & Validation** - Integrate fixtures with DuckDB ingest and smoke test, validate end-to-end
- [ ] **Phase 86: Documentation & Cleanup** - Document workflow, update PROJECT.md, finalize .gitignore and quality standards

### Phase Details

#### Phase 83: Environment Detection & Infrastructure
**Goal**: Pipeline auto-detects local Windows vs HiPerGator Linux and configures appropriate paths for data, cache, and database files
**Depends on**: Nothing (first phase of v2.2)
**Requirements**: ENV-01, ENV-02, ENV-03, ENV-04, ENV-05, ENV-06, INFRA-01, INFRA-02, INFRA-03, INFRA-04
**Success Criteria** (what must be TRUE):
  1. Developer sources R/00_config.R on Windows and IS_LOCAL flag auto-sets to TRUE with data_dir pointing to tests/fixtures/
  2. Developer sources R/00_config.R on HiPerGator Linux and IS_LOCAL flag defaults to FALSE with data_dir pointing to /orange/ production path
  3. Developer sets R_TESTING_ENV=local environment variable and pipeline switches to local mode regardless of OS
  4. Pipeline logs which environment mode is active at startup (Local Testing Mode or Production HiPerGator Mode)
  5. All path construction throughout pipeline uses file.path() with no hardcoded backslashes or forward slashes
**Plans:** 2/2 plans complete
Plans:
- [x] 83-01-PLAN.md — Environment detection block and conditional CONFIG paths in R/00_config.R
- [x] 83-02-PLAN.md — Infrastructure files (.gitignore, .Renviron.example) and smoke test validation

#### Phase 84: Test Fixture Design & Creation
**Goal**: Hand-crafted test fixture CSVs exist covering 18+ clinical edge cases (dual-eligible, NLPHL, orphan dx, SCT, death dates, multiple cancers) in a documented, reproducible, git-tracked format
**Depends on**: Phase 83 (environment detection must work before fixtures can be placed in correct directory)
**Requirements**: FIX-01, FIX-02, FIX-03, FIX-04, FIX-05
**Success Criteria** (what must be TRUE):
  1. Developer opens tests/fixtures/FIXTURE_DESIGN.md and sees a table mapping 20 synthetic patients to specific clinical edge cases with rationale
  2. Developer runs dir("tests/fixtures/") and sees 15 CSV files matching PCORnet CDM table names (ENROLLMENT, DIAGNOSIS, ENCOUNTER, etc.)
  3. Developer reads any fixture CSV and sees obviously synthetic data (unrealistic dates 2010-2015, generic site codes, fake patient IDs) preventing HIPAA re-identification
  4. Developer queries fixture CSVs for known edge cases and finds patients PT001-PT002 with dual-eligible records, PT003 with NLPHL diagnosis, PT008 with orphan dx codes
  5. Developer runs git diff after fixture creation and sees all CSVs tracked in version control with total size under 1MB
**Plans**: TBD
**UI hint**: yes

#### Phase 85: Testing Integration & Validation
**Goal**: Existing DuckDB ingest (R/03) and smoke test (R/88) run successfully against local test fixtures, validating environment detection and fixture schema with end-to-end pipeline completing in under 2 minutes
**Depends on**: Phase 84 (fixtures must exist before ingest/testing can proceed)
**Requirements**: TEST-01, TEST-02, TEST-03, TEST-04, TEST-05
**Success Criteria** (what must be TRUE):
  1. Developer sources R/00_config.R, R/01, R/03 on Windows and DuckDB file appears in tempdir() containing 15 tables with 20-25 patient records from fixtures
  2. Developer sources R/88 smoke test locally and all sections pass including new environment detection validation (Section 3B) and fixture schema validation (Section 3C)
  3. Developer runs R/88 on HiPerGator production and smoke test passes Section 3B (environment check) but skips Section 3C (fixture schema check only runs in local mode)
  4. Developer times full local pipeline (R/00 through R/88) and execution completes in under 2 minutes with no path errors or DuckDB locking issues
  5. Developer queries DuckDB for edge case patients and confirms PT001 shows dual-eligible payer records, PT003 shows NLPHL diagnosis code, PT008 shows orphan dx without cancer linkage
**Plans**: TBD

#### Phase 86: Documentation & Cleanup
**Goal**: Local testing workflow is documented, PROJECT.md updated to reflect v2.2 completion, .gitignore prevents accidental commits of environment files, and all new scripts meet v2.0 quality standards
**Depends on**: Phase 85 (workflow must work before documenting it)
**Requirements**: QUAL-01
**Success Criteria** (what must be TRUE):
  1. Developer opens .planning/PROJECT.md and sees v2.2 milestone moved to "Shipped" section with key decisions about environment detection strategy and fixture design documented
  2. Developer attempts to git add .Renviron and git blocks the commit due to .gitignore rules
  3. Developer opens .Renviron.example and sees commented example showing R_TESTING_ENV override pattern without exposing real credentials or paths
  4. Developer runs styler on all modified scripts and sees no formatting changes (already compliant with tidyverse style)
  5. Developer runs lintr on all modified scripts and sees no violations, all scripts have documentation headers and inline comments explaining WHY
**Plans**: TBD

### v2.2 Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 83. Environment Detection & Infrastructure | 2/2 | Complete    | 2026-06-04 |
| 84. Test Fixture Design & Creation | 0/? | Not started | - |
| 85. Testing Integration & Validation | 0/? | Not started | - |
| 86. Documentation & Cleanup | 0/? | Not started | - |

### Phase 87: Unify ICD-9/ICD-10 Cancer Code Usage

**Goal:** Unify cancer diagnosis code handling across the cancer summary pipeline (R/45-R/49) and drug grouping tables (R/56) so all scripts use both ICD-9 and ICD-10 cancer codes via shared centralized maps, expand HL cohort confirmation to include ICD-9 201.x, and ensure consistent cross-system aggregation rules.
**Requirements**: ICD-01, ICD-02, ICD-03, ICD-04, ICD-05, ICD-06, ICD-07, ICD-08, ICD-09, ICD-10, ICD-11, ICD-12
**Depends on:** Phase 82 (v2.1 cancer classification work)
**Plans:** 3 plans

Plans:
- [ ] 87-01-PLAN.md — ICD9_CANCER_SITE_MAP config, shared is_cancer_code(), classify_codes() extension
- [ ] 87-02-PLAN.md — Cancer summary pipeline (R/45, R/47, R/48, R/49) DX_TYPE removal and cohort expansion
- [ ] 87-03-PLAN.md — R/56 shared utility linkage, R/50 verification, R/88 smoke test validation

---
*Last updated: 2026-06-04 -- Phase 87 planned (3 plans, 2 waves)*
