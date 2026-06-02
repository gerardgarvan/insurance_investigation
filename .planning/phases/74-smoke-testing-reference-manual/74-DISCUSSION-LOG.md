# Phase 74: Smoke Testing & Reference Manual - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md -- this log preserves the alternatives considered.

**Date:** 2026-06-02
**Phase:** 74-smoke-testing-reference-manual
**Areas discussed:** Testing framework, Reference manual scope, Smoke test coverage, Cross-platform strategy

---

## Testing Framework

| Option | Description | Selected |
|--------|-------------|----------|
| testthat (lightweight) | Create tests/testthat/ with test-*.R files. Add minimal DESCRIPTION for testthat::test_dir(). Industry standard for R testing, but requires minor package scaffolding. | |
| Enhanced standalone (Recommended) | Expand existing R/87 pattern into a comprehensive standalone test script. No package scaffolding needed. Works directly with Rscript on both platforms. Aligns with existing codebase conventions. | ✓ |
| You decide | Claude picks the most appropriate approach given the codebase constraints. | |

**User's choice:** Enhanced standalone (Recommended)
**Notes:** No testthat framework -- project isn't an R package. Existing check() pattern from R/86/R/87 is the established convention.

### Test File Organization

| Option | Description | Selected |
|--------|-------------|----------|
| Replace into one script | Merge R/86 + R/87 checks into a single comprehensive smoke test. Reduces duplication. | |
| Supplement -- add R/88 | Keep R/86 and R/87 as-is, add a new R/88 script. More files but no risk of breaking existing tests. | |
| You decide | Claude picks based on code overlap and maintenance cost. | ✓ |

**User's choice:** You decide
**Notes:** Claude has discretion on consolidation vs supplementation approach.

### Backend Test Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Leave R/80 separate | R/80 tests DuckDB vs RDS parity with live data -- fundamentally different from structural smoke tests. Keep it independent. | ✓ |
| Include in scope | Fold R/80 checks into the comprehensive test so there's one test script that covers everything. | |

**User's choice:** Leave R/80 separate
**Notes:** R/80 is data-dependent; structural smoke tests should not require data access.

---

## Reference Manual Scope

### Format and Location

| Option | Description | Selected |
|--------|-------------|----------|
| docs/REFERENCE_MANUAL.md (Recommended) | Single markdown file in docs/ folder. Keeps it with other documentation. Easy to find for onboarding. | ✓ |
| R/REFERENCE_MANUAL.md | Next to R/SCRIPT_INDEX.md in the R/ directory. Co-located with the scripts it documents. | |
| You decide | Claude picks based on existing docs layout. | |

**User's choice:** docs/REFERENCE_MANUAL.md (Recommended)

### Dependency Matrix Depth

| Option | Description | Selected |
|--------|-------------|----------|
| Full matrix (Recommended) | Every script gets a row: Script, Purpose, source() Dependencies, RDS Inputs, RDS/CSV Outputs, Config Constants Used. Covers all 67 + 10 utils. | ✓ |
| Grouped by decade | Dependency table per decade with cross-decade links. More readable but less granular. | |
| You decide | Claude picks based on maintainability and script count. | |

**User's choice:** Full matrix (Recommended)

### Onboarding Instructions

| Option | Description | Selected |
|--------|-------------|----------|
| Yes -- full onboarding section | Include: HiPerGator setup, renv restore, module loading, run-order walkthrough, output file locations. | ✓ |
| Minimal -- just reference | Skip onboarding prose. Just the dependency matrix, run order, and config documentation. | |

**User's choice:** Yes -- full onboarding section
**Notes:** Useful for new team members or Amy Crisp.

### Generation Method

| Option | Description | Selected |
|--------|-------------|----------|
| Auto-generated (Recommended) | Parse the 5-field header blocks from all 67 scripts + 10 utils to build the dependency matrix automatically. | ✓ |
| Manually authored | Write the reference manual by hand based on script inventory. | |
| You decide | Claude picks based on header format consistency and maintenance cost. | |

**User's choice:** Auto-generated (Recommended)
**Notes:** Phase 69 added structured headers to all scripts -- these are parseable for auto-generation.

---

## Smoke Test Coverage

### Execution Depth

| Option | Description | Selected |
|--------|-------------|----------|
| Structure-only (Recommended) | Verify file existence, sequential numbering, source() resolution, RDS dependency chains, config constants -- but don't execute scripts that need data. | ✓ |
| Structure + config execution | Also source() R/00_config.R and verify all constants load, utils auto-source, key functions exist. Still no data loading. | |
| Full execution | Actually run critical scripts end-to-end. Requires data access -- only works on HiPerGator. | |

**User's choice:** Structure-only (Recommended)

### Additional Structural Checks

| Option | Description | Selected |
|--------|-------------|----------|
| DRY + defensive validation | Verify no duplicate constants outside R/00_config.R. Verify utils_assertions.R and utils_cancer.R present. Verify checkmate in library() chain. | |
| Full inventory validation | DRY checks PLUS: verify all 10 utils/ modules, verify R/archive/ has README, verify no orphan files, verify SCRIPT_INDEX.md matches filesystem. | |
| You decide | Claude determines the most valuable additional checks based on what prior phases changed. | ✓ |

**User's choice:** You decide
**Notes:** Claude has discretion on which additional checks add the most value.

---

## Cross-Platform Strategy

### Platform Handling

| Option | Description | Selected |
|--------|-------------|----------|
| Skip data checks on Windows (Recommended) | Structural checks run everywhere. Data-dependent checks gated behind DATA_AVAILABLE flag. Tests pass on Windows with fewer checks. | ✓ |
| Separate test scripts per platform | One script for Windows, one for HiPerGator. Cleaner separation but more files. | |
| You decide | Claude picks the cleanest cross-platform approach. | |

**User's choice:** Skip data checks on Windows (Recommended)

### Detection Method

| Option | Description | Selected |
|--------|-------------|----------|
| Auto-detect (Recommended) | Use .Platform$OS.type or Sys.info() to detect Windows vs Linux. Check if CONFIG$data_dir exists for data availability. No flags needed. | ✓ |
| Explicit flag | Use environment variable (SMOKE_TEST_DATA=true) to enable data-dependent checks. More explicit but requires user to set it. | |

**User's choice:** Auto-detect (Recommended)

---

## Claude's Discretion

- Test file organization (consolidate R/86+R/87 vs add R/88)
- Additional structural checks beyond existing R/86/R/87 coverage
- Reference manual generator implementation approach
- Smoke test internal structure (check grouping, output format)

## Deferred Ideas

None -- discussion stayed within phase scope
