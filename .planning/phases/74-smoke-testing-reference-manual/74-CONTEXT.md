# Phase 74: Smoke Testing & Reference Manual - Context

**Gathered:** 2026-06-02
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 74 delivers two artifacts: (1) a comprehensive standalone smoke test script that validates pipeline structural integrity (sequential numbering, source() resolution, RDS dependency chains, config constants, utility modules, DRY consolidation), and (2) an auto-generated reference manual with full dependency matrix and onboarding instructions. This phase does NOT add new pipeline functionality, modify existing scripts' behavior, or require data access for testing. Data-dependent validation is gated behind auto-detection and only runs on HiPerGator.

</domain>

<decisions>
## Implementation Decisions

### Testing Framework
- **D-01:** Enhanced standalone test scripts using the existing manual `check()` pattern from R/86 and R/87. No testthat framework, no DESCRIPTION file, no package scaffolding. Works directly with `Rscript` on both platforms.
- **D-02:** R/80 (backend parity test) is left as a separate data-dependent test, outside the scope of the structural smoke test suite.

### Test File Organization
- **D-03:** Claude's Discretion on whether to merge R/86 + R/87 into a single comprehensive script or add a new R/88 alongside them. Decision based on code overlap and maintenance cost.

### Smoke Test Coverage
- **D-04:** Structure-only testing — verify file existence, sequential numbering, source() resolution, RDS dependency chains, config constants. No script execution that requires data.
- **D-05:** Claude's Discretion on additional structural checks beyond R/86/R/87 coverage. Should include at minimum: DRY consolidation validation (no duplicate PREFIX_MAP/TIER_MAPPING outside R/00_config.R), utils module completeness (all 10 modules present), defensive coding infrastructure (checkmate in library chain, utils_assertions.R present).

### Cross-Platform Strategy
- **D-06:** Auto-detect platform using `.Platform$OS.type` or `Sys.info()`. Check if `CONFIG$data_dir` exists to determine data availability. No explicit flags needed.
- **D-07:** Data-dependent checks gated behind `DATA_AVAILABLE` flag set by auto-detection. Structural checks run on both Windows and HiPerGator. Tests pass on Windows with fewer checks (structural only).

### Reference Manual
- **D-08:** Reference manual lives at `docs/REFERENCE_MANUAL.md`, alongside existing docs (DUCKDB_MIGRATION_GUIDE.md, DUCKDB_TRANSLATION_NOTES.md).
- **D-09:** Full dependency matrix — every script gets a row: Script | Purpose | source() Dependencies | RDS Inputs | RDS/CSV Outputs | Config Constants Used. Covers all 67 numbered scripts + 10 utils.
- **D-10:** Includes full onboarding section: HiPerGator setup, renv restore, module loading, run-order walkthrough, output file locations. Targeted at new team members.
- **D-11:** Auto-generated from script headers. Phase 69 added structured 5-field header blocks (Purpose, Inputs, Outputs, Dependencies, Requirements) to all scripts. A utility script or inline R code parses these headers to build the dependency matrix automatically.

### Claude's Discretion
- Internal structure of the comprehensive smoke test (check grouping, output format, exit codes)
- Which R/86/R/87 checks to consolidate vs keep separate
- Exact set of additional structural checks beyond existing coverage
- Reference manual generator implementation (standalone script vs inline in smoke test vs separate utility)
- Prose sections of reference manual (architecture overview, config documentation, error message patterns)
- Wave/plan decomposition strategy

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements
- `.planning/REQUIREMENTS.md` -- REORG-05 (smoke test validation), SAFE-06 (comprehensive smoke test suite), DOC-04 (full reference manual with dependency matrix)

### Existing Smoke Tests
- `R/80_smoke_test_backends.R` -- DuckDB vs RDS parity test (out of scope but context for test decade)
- `R/86_smoke_test_foundation.R` -- Phase 65 foundation validation (6 checks: utils/ structure, auto-sourcing, foundation chain)
- `R/87_smoke_test_full_pipeline.R` -- Phase 66-67 reorganization validation (12 checks: decade counts, old numbers, a/b suffixes, source() refs, dependency chains)

### Script Inventory & Documentation
- `R/SCRIPT_INDEX.md` -- Canonical listing of all 67 numbered scripts + 10 utils + 8 archived
- `docs/DUCKDB_MIGRATION_GUIDE.md` -- Backend abstraction pattern documentation
- `docs/DUCKDB_TRANSLATION_NOTES.md` -- DuckDB translation gaps and workarounds

### Configuration
- `R/00_config.R` -- Foundation config with auto-sourcing mechanism, all centralized constants (ICD_CODES, PAYER_MAPPING, AMC_PAYER_LOOKUP, TREATMENT_CODES, ANALYSIS_PARAMS, CANCER_SITE_MAP, TIER_MAPPING)
- `R/utils/` -- 10 utility modules auto-sourced by 00_config.R

### Predecessor Phases
- `.planning/phases/73-dry-consolidation/73-CONTEXT.md` -- DRY consolidation: CANCER_SITE_MAP, TIER_MAPPING centralized, classify_codes/classify_payer_tier/build_output_path extracted
- `.planning/phases/72-defensive-coding/72-CONTEXT.md` -- checkmate assertions, utils_assertions.R, error message format [R/XX ACTION]
- `.planning/phases/69-script-documentation/69-CONTEXT.md` -- Script header format (Purpose/Inputs/Outputs/Dependencies/Requirements), section headers with 4+ dashes
- `.planning/phases/68-output-test-reorganization/68-CONTEXT.md` -- HiPerGator verification deferred to Phase 74, structural checks run locally

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `R/86_smoke_test_foundation.R` -- 6-check pattern with manual `check()` function, PASS/FAIL output, exit status 1 on failure
- `R/87_smoke_test_full_pipeline.R` -- 12-check comprehensive pattern, decade-by-decade validation, source() reference extraction
- All 67 scripts have structured header blocks (Phase 69) with Purpose, Inputs, Outputs, Dependencies fields -- parseable for auto-generating reference manual
- `R/utils/` with 10 modules -- established auto-sourcing pattern via `list.files("R/utils", pattern = "\\.R$")`

### Established Patterns
- Standalone smoke tests use `check(condition, message)` function returning PASS/FAIL per check
- Tests exit with `quit(status = 1)` on failure for SLURM job compatibility
- Decade-based organization: 00-09 foundation, 10-19 cohort, 20-29 treatment, 40-59 cancer, 60-69 payer/QA, 70-79 outputs, 80-89 tests, 90-99 ad-hoc
- Script headers follow `# Purpose:`, `# Inputs:`, `# Outputs:`, `# Dependencies:`, `# Requirements:` format

### Integration Points
- Test decade (80-89) -- new or consolidated smoke test fits in this decade
- `docs/` directory -- reference manual alongside existing DuckDB docs
- `R/SCRIPT_INDEX.md` -- should remain consistent with reference manual (reference manual is superset)
- `R/00_config.R` -- smoke test validates config constants and auto-sourcing mechanism

</code_context>

<specifics>
## Specific Ideas

No specific requirements -- standard smoke testing and documentation with decisions captured above.

</specifics>

<deferred>
## Deferred Ideas

None -- discussion stayed within phase scope

</deferred>

---

*Phase: 74-smoke-testing-reference-manual*
*Context gathered: 2026-06-02*
