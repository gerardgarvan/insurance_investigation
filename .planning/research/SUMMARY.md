# Project Research Summary

**Project:** PCORnet Payer Variable Investigation (R Pipeline) — v2.0 Codebase Cleanup & Documentation
**Domain:** R analysis pipeline reorganization, documentation, and quality tooling
**Researched:** 2026-06-01
**Confidence:** HIGH

## Executive Summary

The v2.0 milestone addresses technical debt from 63 organic development phases, transforming an ad-hoc collection of ~80 R scripts into a maintainable, documented, and testable codebase. Research confirms this requires **five mature CRAN packages** (lintr, styler, checkmate, testthat, fs) plus **lightweight structural changes** (renumbering, section headers, centralized constants) — NOT a full package conversion or architectural overhaul.

**Recommended approach:** Sequential reorganization in 9 phases grouped as REORG → DOC → SAFE → DRY. Start with decade-based renumbering (00-09 foundation, 10-19 cohort, 20-39 treatment, 40-59 cancer, 60-69 payer/QA, 70-79 outputs, 80-89 tests, 90-99 ad-hoc), add documentation via section headers and roxygen2-style comments, apply auto-formatting and lint checking, insert defensive assertions and smoke tests, then consolidate duplicate lookups. Each phase builds on the previous, with smoke tests validating integrity before proceeding.

**Key risks and mitigation:** Six critical pitfalls identified: (1) Broken source() cross-references after renumbering — comprehensive grep BEFORE file moves, update references BEFORE renaming, smoke test immediately after; (2) lintr false positives on PCORnet ALLCAPS columns — configure .lintr to disable object_name_linter, fix violations incrementally; (3) checkmate performance overhead in hot loops — validate at function entry only, NOT inside iterations; (4) styler corrupting data files — style ONLY R/ directory explicitly; (5) hardcoded paths in tests — use here() for project-relative paths, test on both Windows and HiPerGator; (6) duplicate constants diverging after partial consolidation — grep exhaustively, delete ALL copies in same commit, validate with smoke test. All pitfalls are preventable with documented strategies.

The recommended stack has **zero bleeding-edge dependencies** — all packages are 5-14 years mature, CRAN-stable, and widely adopted in tidyverse ecosystem. Integration risk is minimal because all are standard R development tools that enhance workflow without changing pipeline logic.

## Key Findings

### Recommended Stack

**Five required packages, one optional.** All additions are infrastructure-focused (linting, formatting, testing, file operations) — they enhance code quality WITHOUT changing pipeline logic or data processing. Integration risk is minimal because all are standard R development tools with clear documentation and tidyverse alignment.

**Core technologies:**
- **lintr 3.3.0-1** (Nov 2025): Static style checking — detects violations without modifying code. Must disable object_name_linter for PCORnet ALLCAPS columns. Provides 100+ default checks (line length, spacing, commented code, T/F usage). Industry standard for tidyverse projects.
- **styler 1.11.0** (Oct 2025): Auto-formatting — fixes spacing, indentation, line breaks after bulk renumbering. Can preview changes with `dry = "on"` before applying. Integrates with RStudio Addins (Ctrl+Shift+A). Saves manual formatting time.
- **checkmate 2.3.4** (Feb 2026): Input validation — provides 100+ assertion functions for defensive coding. C-optimized (2-5x faster than base R stopifnot). Peer-reviewed (R Journal 2017). Critical for file existence checks, data structure validation, and payer mapping verification.
- **testthat 3.3.2** (Jan 2026): Smoke testing — verifies pipeline integrity after renumbering (sequential numbering, valid source() calls, expected RDS artifacts). Industry standard (10,000+ CRAN packages). Focus on integration tests, NOT exhaustive unit tests (research pipeline, not production software).
- **fs 2.1.0** (Apr 2026): Cross-platform file operations — atomic file renaming safer than base R file.rename(). Fails loudly if destination exists (prevents overwrites). Essential for renumbering ~80 scripts without data loss. Works identically on Windows and Linux.
- **logger 0.4.2** (May 2026, OPTIONAL): Structured logging — severity levels, namespaces, JSON output. Current glue + cat + tidylog is sufficient for v2.0. Defer to future milestone unless team grows or CI/CD integration requires machine-readable logs.

**Alternatives rejected:**
- Full package structure (roxygen2 build, pkgdown): Over-engineering for analysis pipeline. Use roxygen2 syntax for readability only, NOT build process.
- CI/CD (GitHub Actions): Data dependency on HiPerGator CSVs makes CI impractical. Manual smoke tests sufficient for solo project.
- Pipeline orchestration (targets/drake): Major architecture change out of scope for v2.0. Existing sequential scripts work.
- Code coverage metrics (covr): Meaningful for unit tests, not smoke tests. Research pipeline, not production software.

**Integration with existing stack:**
- lintr + tidylog: Independent (tidylog runs during execution, lintr runs during development)
- styler + RStudio: IDE Addin integration for quick formatting
- checkmate + testthat: Built-in integration (checkmate provides expect_*() functions extending testthat)
- fs + here: Complementary (here() for path construction, fs for file operations)

### Expected Features

Research identified 9 table stakes features (industry standard for R pipelines), 4 differentiators (set apart from typical projects), and 8 anti-features (explicitly avoid over-engineering).

**Table stakes (must-have):**
- **Sequential script numbering (01-N)**: Industry standard. Answers "what runs when?" Low complexity (mechanical renaming with fs package).
- **Header blocks in every script**: Documents purpose, inputs, outputs, dependencies. Standard for reproducible research.
- **Section headers with 4+ dashes**: Enables RStudio Ctrl+Shift+R outline navigation. Critical for 500+ line scripts.
- **Descriptive variable/function names**: R style guide baseline (snake_case). Already in codebase via tidyverse.
- **Input file existence checks**: Fail-fast pattern. Prevents cryptic errors 30 minutes into execution. Use checkmate assert_file_exists().
- **README with run order**: Onboarding requirement. Linear list of scripts with 1-sentence purpose each.
- **Comments explaining non-obvious logic**: Future maintainer needs context. Comment WHY, not WHAT.
- **Centralized constants/lookups**: DRY principle. Multiple PREFIX_MAP copies = maintenance nightmare, divergence risk.
- **Error messages with context**: Use glue() for `stop(glue("Missing {file} at {path}"))` instead of generic "assertion failed".

**Differentiators (should-have):**
- **Automated dependency checks**: Verify required RDS artifacts exist before each script. Prevents "file not found" 20 min into run. Use checkmate assertions.
- **Smoke test script**: Catches cross-reference bugs immediately after renumbering. Run subset (1-5 min) to verify outputs exist + row counts match. Use testthat framework.
- **Assertion-rich pipeline (checkmate)**: Data quality gates. Catches upstream changes (e.g., new ENC_TYPE value). Assertions double as executable documentation.
- **Reference manual with dependency matrix**: Table format documenting Script → Inputs/Outputs/Dependencies for all 80 scripts. Enables quick understanding of pipeline flow.

**Anti-features (explicitly avoid):**
- Full package conversion (NAMESPACE, DESCRIPTION): Delays v2.0 by weeks. Analysis scripts, not distributable package.
- Automated style enforcement on commits: Adds friction. Run styler manually before milestone completion.
- Unit tests for every function: High maintenance cost vs value. Reserve for critical utility functions only.
- Interactive pkgdown site: Overkill for 1-2 person project. Static markdown reference manual sufficient.
- Pipeline orchestration (targets): Major re-learning curve. Defer to v3+ if pipeline grows >100 scripts.
- Git hooks for pre-commit validation: Adds friction. Manual smoke test before milestone tagging.
- Comprehensive input validation (pointblank): Already deferred in v1.0. Python pipeline handles data cleaning.
- Refactoring to object-oriented (R6 classes): Analysis pipeline = procedural workflow. OOP adds complexity without benefits.

### Architecture Approach

Current state: 63 numbered scripts with gaps (missing 30-32, 37, 57), 12 sub-lettered duplicates (22a/b, 43a/b, 44a/b, 45a/b, 46a/b, 48a/b), 7 unnumbered utilities, 6 ad-hoc exploratory scripts. Total 81 R files. Integration points: 95+ source() calls, 25+ RDS artifacts (semantic naming), 50+ output files (semantic naming).

**Recommended: Decade-based numbering** groups scripts by logical execution flow, NOT alphabetical order. Provides 10-20 slot capacity per functional area, allows inserting new scripts without mass renumbering.

**Major components:**
1. **00-09 Foundation** — config (auto-sources utils/), DuckDB ingest, data loading, payer harmonization (4 scripts)
2. **10-19 Cohort Building** — predicates, assembly, treatment payer windows, surveillance detection (5 scripts)
3. **20-39 Treatment Analysis** — code inventory/resolution, durations, episodes, drug names, first-line therapy, cross-reference (8 scripts, 20 slots for expansion)
4. **40-59 Cancer Diagnosis** — site frequency, confirmation, refined summaries, temporal filters, code catalogs (5 scripts, 20 slots)
5. **60-69 Payer & Data Quality** — code frequency, tiered resolution, overlap detection/classification, death date validation, QA summaries, dx gap analysis, encounter missingness (8 scripts)
6. **70-79 Visualization & Reports** — encounter analysis, waterfall/Sankey, PPTX (main + overlap), documentation, Gantt v1/v2 (8 scripts)
7. **80-89 Testing & Diagnostics** — backend smoke tests, parity tests, benchmarks, duration/episode tests (6 scripts)
8. **90-99 Ad-Hoc & Deprecated** — value audits, radiation CPT checks, duplicate date detection, exploratory searches, diagnostics (9 scripts)
9. **utils/ folder (NEW)** — Extract 7 utils_*.R modules from main R/ directory (attrition, dates, duckdb, icd, payer, pptx, snapshot, treatment)
10. **archive/ folder (NEW)** — Preserve 6 deprecated scripts for reference (payer_frequency_from_resolved, tiered_payer_summary, sct_code_inventory, run_phase12_outputs, tiered_encounter_level, tiered_date_level)

**Integration point updates:** 95+ source() calls must update (e.g., `source("R/01_load_pcornet.R")` → `source("R/02_data_load_pcornet.R")`). RDS artifacts use semantic naming (hl_cohort.rds, treatment_episodes.rds) — NO changes required. Output files use semantic naming (gantt_episodes.csv) — NO changes required. Only source() paths and inline "Phase NN" comments need updates.

**Data flow through reorganized pipeline:**
```
00_config.R → auto-source utils/
    ↓
01_data_ingest_duckdb.R (CSV → DuckDB)
    ↓
02_data_load_pcornet.R (get_pcornet_table())
    ↓
03_data_harmonize_payer.R (8 AMC categories)
    ↓
10-14: Cohort Building → hl_cohort.rds
    ↓
20-27: Treatment Analysis → treatment_episodes.rds, regimen_labeled_episodes.rds
    ↓
40-44: Cancer Diagnosis → cancer_summary.rds, confirmed_hl_cohort.rds
    ↓
60-67: Payer & Data Quality → resolved encounters, quality metrics
    ↓
70-77: Visualization & Reports → PNG/CSV/PPTX outputs
```

**Migration strategy:** Build order in 9 phases (Foundation → Cohort → Treatment → Cancer → Payer/QA → Outputs → Tests → Ad-Hoc → Documentation). Smoke tests after each decade renumbered. Sequential execution required — each phase depends on previous stability.

### Critical Pitfalls

Six critical pitfalls with HIGH impact and documented prevention strategies. All are recoverable (LOW-MEDIUM cost) but avoidable with discipline.

1. **Broken source() references after renumbering** — Search-and-replace misses edge cases (comments, glue strings, conditional source() calls). Pipeline fails 20 min into execution with cryptic error. **Prevention:** Comprehensive grep BEFORE renaming (`grep -rn "source\(" R/`), update references BEFORE moving files, create renaming manifest to validate no duplicates, smoke test immediately after with testthat checking all source() calls resolve. **Warning signs:** Renaming took 20 min but no test errors, only tested first 3 scripts, git diff shows file renames but no source() updates.

2. **Over-aggressive lintr violations** — Default tidyverse rules flag PCORnet ALLCAPS columns (PATID, ENROLL_DATE). Developer batch-renames without understanding column names ≠ R variables. 50+ scripts break with "object 'PATID' not found". **Prevention:** Configure .lintr to disable object_name_linter and set line_length_linter(120) BEFORE running, fix violations incrementally (HIGH severity first, LOW severity deferred), use styler BEFORE lintr to auto-fix mechanical issues, test after each fix. **Warning signs:** lintr reports 500+ violations (too many to fix at once), batch find-replace on variable names, no incremental testing.

3. **checkmate assertions inside hot loops** — Defensive enthusiasm puts `assert_character(ID)` inside map(). 5-minute pipeline becomes 45 minutes (9x slowdown). No actual bugs caught (data already validated at load). **Prevention:** Validate ONCE at function entry, NOT per iteration. Use conditional validation (`VALIDATE_INPUTS` env var) for debugging. Profile if runtime increases 5x. **Warning signs:** Pipeline runtime increased 5x after adding assertions, profiling shows checkmate at top (not data operations), assertions inside group_by/summarize/map.

4. **styler reformats data files** — Running `styler::style_dir(".")` recurses into output/ and corrupts CSVs. Gantt chart tool can't parse corrupted CSV. Git diff shows 10,000+ lines changed in output/. **Prevention:** Style ONLY R/ directory explicitly (`styler::style_dir("R/")`), use .stylerignore (output/, cache/, renv/, .planning/), preview with `dry = "on"` before applying. **Warning signs:** styler processing 1000+ files (should be ~80 R scripts), git diff shows changes in output/ or cache/, CSV files show spacing changes.

5. **Smoke tests with hardcoded paths** — Write test with `"C:/Users/Owner/insurance_investigation/cache/cohort.rds"`. Works on local Windows. Fails on HiPerGator Linux: "No such file or directory." **Prevention:** Use here() for project-relative paths (`here("cache", "cohort.rds")`), use fs::file_exists() (not base R), test on both platforms before committing. **Warning signs:** Paths with C:/ or D:/ (Windows-specific), backslashes in paths, tests pass in RStudio but fail in SLURM jobs.

6. **Duplicate constants diverge after consolidation** — Grep finds 2 of 3 PREFIX_MAP copies, third remains in conditional logic. Same patient has different payer categories depending on which script runs first (non-deterministic). **Prevention:** Grep exhaustively (`grep -rn "PREFIX_MAP <-"`) BEFORE consolidation, remove ALL old copies in same commit as adding to 00_config.R, validate with smoke test that constant defined only in config (`expect_false(str_detect(content, "PREFIX_MAP <-"))`). **Warning signs:** Consolidation commit only modifies R/00_config.R (didn't delete old copies), grep shows multiple definitions after consolidation, results change when scripts run in different order.

**Moderate pitfalls (MEDIUM impact):** Renumbering without execution order analysis (breaks dependencies), section headers without 4+ dashes (RStudio outline doesn't work), roxygen2 package build for non-package (creates unnecessary man/ directory), over-commenting trivial code (noise obscures important comments).

**Recovery costs:** All critical pitfalls are LOW-MEDIUM cost to recover. Broken source() calls: grep + update + test. lintr ALLCAPS rename: revert + configure .lintr + re-run. checkmate hot loops: move assertions outside loop. styler CSVs: revert output/ changes. Hardcoded paths: replace with here(). Duplicate constants: grep + delete + smoke test.

## Implications for Roadmap

Based on research, v2.0 should follow a **9-phase sequential reorganization** with smoke tests after each major group. Phases build incrementally — each adds capability without breaking previous work. Total estimated 11 phases (9 primary + 2 iterative for lint/consolidate).

### Phase 1: Foundation Reorganization (REORG-01)
**Rationale:** Create new folder structure and renumber foundation scripts first. All downstream scripts depend on config/data loading, so this must be stable before proceeding. Addresses numbering chaos and unclear execution order.
**Delivers:** utils/ folder created, 7 utility modules moved, 00_config.R updated to source from utils/, DuckDB ingest renumbered 01, data loading 02, payer harmonization 03.
**Addresses:** Table stakes (sequential numbering, centralized constants in utils/).
**Avoids:** Pitfall #1 (broken source() references) — comprehensive grep for all 95+ source() calls, update references BEFORE file moves, smoke test validates. Pitfall #5 (hardcoded paths) — use here() for all path operations.
**Stack:** fs package for atomic file_move() operations, here() for project-relative paths.
**Research flag:** Standard pattern (file operations well-documented in fs package). No deeper research needed.

### Phase 2: Cohort Building Reorganization (REORG-02)
**Rationale:** Cohort scripts (03→10, 04→11, 10→12, 13, 14) form second dependency tier. Renumber after foundation is stable. Prevents breaking downstream treatment/cancer scripts that depend on cohort.
**Delivers:** Cohort building scripts (10-19 decade), source() calls updated in 7 downstream scripts, parity test confirms hl_cohort.rds row count unchanged.
**Addresses:** Table stakes (sequential numbering). Differentiator (automated dependency checks via parity tests).
**Avoids:** Pitfall #7 (renumbering without execution order analysis) — manual dependency mapping ensures 10→11→12→13→14 order.
**Stack:** testthat for parity tests (verify RDS row counts match before/after).
**Research flag:** Standard pattern. No research needed.

### Phase 3: Treatment Analysis Reorganization (REORG-03)
**Rationale:** Treatment scripts (38-44, 60-62) scattered across two regions. Consolidate to 20-39 decade with 20-slot capacity for future expansion. Prevents renumbering all scripts when adding new treatment analysis.
**Delivers:** 8 treatment scripts renumbered/merged (20-27), treatment_episodes.rds structure validated, source() cross-references updated.
**Implements:** Decade-based grouping architecture (20 slots allow inserting 28_new_analysis.R without renumbering 29-80).
**Avoids:** Pitfall #1 (broken source() calls) — comprehensive update of all references to 43a/44a (treatment durations/episodes).
**Stack:** checkmate assertions validate treatment episode counts after renumbering.
**Research flag:** Standard pattern. No research needed.

### Phase 4: Cancer Diagnosis Reorganization (REORG-04)
**Rationale:** Cancer site scripts (47-58) consolidated to 40-59 decade. Provides 20-slot expansion capacity for future cancer analyses.
**Delivers:** 5 cancer scripts renumbered/merged (40-44), cancer_summary.rds validated, confirmed_hl_cohort.rds row count matches.
**Addresses:** Architecture component (cancer diagnosis analysis isolated to dedicated decade).
**Stack:** testthat smoke tests validate cancer site frequency counts, checkmate assertions verify cancer_summary structure.
**Research flag:** Standard pattern. No research needed.

### Phase 5: Payer/QA and Output Reorganization (REORG-05)
**Rationale:** Complete renumbering (60-69 payer/QA, 70-79 outputs, 80-89 tests, 90-99 ad-hoc). Final push to decade-based system. Creates archive/ for deprecated scripts.
**Delivers:** All 80 scripts in final decade-based positions, archive/ folder created with 6 deprecated scripts, smoke test suite validates all source() calls resolve.
**Addresses:** Anti-feature (avoid mixing production and test code) — test scripts isolated to 80-89 decade, exploratory scripts to 90-99.
**Avoids:** Pitfall #1 (broken references) — final comprehensive smoke test with testthat checking ALL source() calls across entire codebase.
**Stack:** testthat comprehensive suite (sequential numbering, source() validation, RDS dependencies).
**Research flag:** Standard pattern. No research needed.

### Phase 6: Documentation and Section Headers (DOC-01, DOC-02)
**Rationale:** After renumbering stable, add human-readable structure. Header blocks + section headers enable reference manual generation and RStudio navigation.
**Delivers:** Header block in all 80 scripts (purpose, inputs, outputs, dependencies), section headers with 4+ dashes (RStudio Ctrl+Shift+R outline navigation), roxygen2-style #' comments for complex functions.
**Addresses:** Table stakes (header blocks, section headers, comments explaining non-obvious logic). Differentiator (reference manual foundation).
**Avoids:** Pitfall #8 (section headers without 4+ dashes) — enforce RStudio format. Pitfall #9 (roxygen2 package build) — use syntax only, NOT build process. Pitfall #10 (over-commenting) — comment WHY not WHAT.
**Stack:** Base R comments (no package overhead), RStudio built-in outline feature.
**Research flag:** Standard pattern (comment conventions documented in tidyverse/Google R style guides). No research needed.

### Phase 7: Automated Formatting and Linting (SAFE-01, SAFE-02)
**Rationale:** Bulk renumbering causes formatting inconsistencies. styler fixes mechanically, lintr detects remaining issues that can't be auto-fixed.
**Delivers:** Consistent tidyverse style across all R/ scripts, .lintr configuration file (disable object_name_linter for PCORnet ALLCAPS, line_length_linter(120)), lintr violations reduced to <50 manageable items (defer LOW severity like trailing whitespace).
**Addresses:** Table stakes (consistent style, descriptive variable names validated).
**Avoids:** Pitfall #2 (over-aggressive lintr) — configure BEFORE running, fix incrementally NOT batch, test after each fix. Pitfall #4 (styler data files) — style ONLY R/ directory, preview with `dry = "on"`.
**Stack:** styler 1.11.0 with dry run preview, lintr 3.3.0-1 with custom .lintr config.
**Research flag:** Standard pattern (styler/lintr have comprehensive documentation). No research needed. **Implementation note:** May need iteration if lintr finds 100+ violations — plan extra phase for cleanup.

### Phase 8: Defensive Coding and Validation (SAFE-03, DRY-01)
**Rationale:** Add input validation and consolidate duplicate constants while testing infrastructure is fresh. Hardens pipeline against data quality issues and prevents constant divergence.
**Delivers:** checkmate assertions in critical functions (file loading, payer mapping, data structure checks), PREFIX_MAP and code lookups consolidated to 00_config.R, smoke tests validate no duplicate constants remain.
**Addresses:** Table stakes (input file existence checks, error messages with context, centralized constants). Differentiator (assertion-rich pipeline, data quality gates).
**Avoids:** Pitfall #3 (assertions in hot loops) — validate at function entry only, NOT inside map()/group_by(). Pitfall #6 (duplicate constants diverge) — comprehensive grep, delete ALL copies in one commit, validate with smoke test.
**Stack:** checkmate 2.3.4 for assertions (assert_file_exists, assert_data_frame, assert_names, assert_subset), testthat for validation smoke tests.
**Research flag:** Standard pattern (checkmate has 100+ functions but excellent vignettes). No research needed.

### Phase 9: Smoke Testing and Documentation (SAFE-04, DOC-03)
**Rationale:** Final integration test + reference manual before milestone closure. Ensures pipeline integrity and provides onboarding documentation.
**Delivers:** Comprehensive smoke test suite (sequential numbering verified, source() calls validate, RDS dependencies checked, config constants exist, critical scripts run without error, output file counts match expected), reference manual with dependency matrix (Script → Inputs/Outputs/Dependencies table for all 80 scripts).
**Addresses:** Table stakes (README with run order expanded to reference manual). Differentiator (smoke test script, reference manual with dependency matrix).
**Avoids:** Pitfall #5 (hardcoded paths in tests) — use here() for all paths, test on HiPerGator. Pitfall #1 (final validation) — smoke test catches any remaining broken references.
**Stack:** testthat 3.3.2 with fs::file_exists() and here() for cross-platform compatibility.
**Research flag:** Standard pattern (testthat well-documented, reference manual format synthesized from targets/pipeflow examples). No research needed.

### Phase Ordering Rationale

**Sequential execution required** — each phase depends on previous stability:
- **REORG (Phases 1-5):** File renumbering must complete before documentation (comments reference final numbers) and testing (smoke tests verify final structure).
- **DOC (Phases 6, 9):** Section headers and comments enable readable reference manual, must come after renumbering stable.
- **SAFE (Phases 7-9):** Formatting, linting, assertions, and testing build on documented code. styler preserves comments (run after DOC), smoke tests validate assertions don't break pipeline.
- **DRY (Phase 8):** Consolidation easier after codebase clean and well-documented (easier to see duplication with good section headers).

**Smoke tests after each decade renumbered** (not after every phase) — balance safety vs overhead:
- After REORG-01 (Foundation 00-09)
- After REORG-02 (Cohort 10-19)
- After REORG-03 (Treatment 20-39)
- After REORG-04 (Cancer 40-59)
- After REORG-05 (Payer/QA/Outputs/Tests/Ad-Hoc 60-99)
- After SAFE-04 (Final comprehensive test)

**Parallelization opportunities:**
- DOC-01 and DOC-02 can overlap (different granularity: section headers vs function comments)
- SAFE-01 and SAFE-03 can overlap (styler and checkmate are independent)
- Implementation note: lintr (SAFE-02) should run AFTER styler (SAFE-01) to reduce violations

**Decade-based grouping enables future expansion** — 20-slot treatment decade (20-39) allows inserting 28_new_analysis.R without renumbering 29-80. Same for 20-slot cancer decade (40-59). Ad-hoc scripts (90-99) isolated — adding exploratory script doesn't pollute production decades.

### Research Flags

**Phases needing deeper research during planning:** NONE for v2.0. All capabilities have clear stack solutions with mature packages. Reorganization is mechanical (not algorithmic).

**Phases with standard patterns (skip research-phase):**
- **All REORG phases (1-5):** File renaming well-understood, fs package documentation complete, decade-based numbering pattern from tidyverse/Google R style guides.
- **All DOC phases (6, 9):** Comment conventions documented in tidyverse/Google R style guides, reference manual format synthesized from established patterns.
- **All SAFE phases (7-9):** lintr/styler/checkmate/testthat have comprehensive official documentation, active communities, extensive vignettes and examples.
- **All DRY phases (8):** Base R refactoring, no special tools needed, consolidation pattern is standard software engineering.

**Potential implementation challenges (not research gaps, just execution complexity):**
- **REORG-01:** Defining logical execution order requires manual pipeline understanding (can't be automated) — expect 4-8 hours manual mapping.
- **SAFE-02:** lintr may flag 100+ violations initially — prioritize HIGH severity (commented code, T/F vs TRUE/FALSE) first, defer LOW severity (trailing whitespace) to polishing pass. May need iteration phase.
- **SAFE-03:** Deciding WHERE to add assertions requires judgment (too many = slow, too few = insufficient validation) — prioritize file loading, payer mapping, cohort structure.
- **DRY-02 (future):** Balancing extraction vs over-abstraction (don't create 1-line wrapper functions) — extract only if pattern appears 3+ times.

**Future research needs (v3.0+, out of scope for v2.0):**
- If team grows >3 developers: Research CI/CD integration (GitHub Actions, automated lintr on PRs, remote smoke tests)
- If pipeline grows >100 scripts: Research targets/drake orchestration (dependency graph automation, parallel execution, automatic caching)
- If compute time >4 hours: Research profiling tools (profvis) for bottleneck detection, query optimization strategies
- If publishing pipeline as package: Research full roxygen2 build process, pkgdown website generation, CRAN submission

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | **HIGH** | All 5 required packages are CRAN-stable (5-14 years mature), widely adopted (10,000+ dependent packages for testthat), actively maintained (latest versions Nov 2025 - Apr 2026). No bleeding-edge or GitHub-only dependencies. Integration points documented (checkmate + testthat, fs + here, lintr + styler workflow). All versions verified 2026-06-01. |
| Features | **HIGH** | Core recommendations (sequential numbering, header blocks, section headers, input validation) are R community standards documented in multiple authoritative sources (Hadley Wickham's R4DS, Google R Style Guide, tidyverse style guide). checkmate peer-reviewed (R Journal 2017). testthat is official R testing framework. Anti-features validated by over-engineering pitfalls in community forums. |
| Architecture | **HIGH** | Decade-based numbering verified against existing codebase (81 files inventoried, 95+ source() calls mapped, 25+ RDS artifacts cataloged). Integration points explicit (RDS artifacts use semantic naming, no changes required). Data flow chain validated against Phase 0-63 history. Migration strategy builds on fs atomic operations (safer than base R). |
| Pitfalls | **HIGH** | All 6 critical pitfalls documented from common R refactoring mistakes (source() reference updates, lintr configuration, checkmate performance, styler scope, path portability, constant consolidation). Prevention strategies tested against package documentation (grep patterns, smoke test patterns, .lintr config format). Recovery costs estimated (LOW-MEDIUM, all recoverable with git revert + targeted fixes). Warning signs observable during execution. |

**Overall confidence:** **HIGH**

All research areas grounded in official documentation (CRAN package pages, tidyverse guides, R Journal peer review). No speculative recommendations — stack choices verified against HiPerGator environment constraints (renv + module system), existing tidyverse pipeline style (dplyr, ggplot2), and solo-researcher workflow (no CI/CD, manual testing). Phase sequencing validated against dependency chains extracted from codebase. Pitfall prevention strategies documented with concrete examples (grep commands, test patterns, config snippets).

**Source hierarchy followed:** CRAN official pages (versions, publication dates) → Official package documentation (API usage, configuration) → Peer-reviewed articles (checkmate R Journal) → Tidyverse/Google style guides (conventions) → Community resources (edge cases, troubleshooting). All version numbers verified against CRAN as of 2026-06-01.

### Gaps to Address

**Minor gaps (low risk, deferred to implementation):**
- **logger package adoption**: Deferred to v3.0 as OPTIONAL. Current glue + cat + tidylog provides sufficient logging for solo researcher. Re-evaluate if team grows (namespaces), CI/CD integration requires machine-readable logs (JSON output), or severity filtering becomes necessary (DEBUG vs INFO vs WARN).
- **Reference manual format**: No single authoritative standard for multi-script R pipelines. Synthesized from targets/pipeflow package documentation and general software engineering practices (dependency matrices). Will validate format during DOC-03 implementation based on what's most useful for onboarding.
- **lintr violation scope**: Unknown until first run. May find 50 violations (quick fix) or 500 violations (needs iteration phase). Plan buffer time in SAFE-02 for cleanup iterations.

**No blocking gaps.** All v2.0 capabilities (renumbering, documentation, linting, validation, testing, consolidation) have mature stack solutions with clear implementation paths. Execution complexity is predictable (file operations, comment additions, test writing) — no algorithmic or research challenges.

## Sources

### Primary (HIGH confidence)
- **CRAN official package pages**: lintr 3.3.0-1 (Nov 2025), styler 1.11.0 (Oct 2025), checkmate 2.3.4 (Feb 2026), testthat 3.3.2 (Jan 2026), fs 2.1.0 (Apr 2026), logger 0.4.2 (May 2026) — version numbers and publication dates verified 2026-06-01
- **Official package documentation**: lintr.r-lib.org, styler.r-lib.org, checkmate (mllg.github.io), testthat.r-lib.org, fs.r-lib.org, logger (daroczig.github.io) — API references, configuration guides, usage vignettes
- **R Journal peer review**: Lang, M. (2017). checkmate: Fast Argument Checks for Defensive R Programming. The R Journal, 9(1), 437-445. — Performance benchmarks, design rationale, validation of checkmate approach
- **Tidyverse Style Guide** (style.tidyverse.org) — Section headers (4+ dashes), comment conventions, file naming (sequential numbering)
- **R for Data Science (2e)** (r4ds.hadley.nz) — Workflow scripts chapter, sequential numbering patterns, project organization
- **Google's R Style Guide** (web.stanford.edu/class/cs109l) — Industry standard conventions, naming patterns

### Secondary (MEDIUM confidence)
- **R Packages (2e)** (r-pkgs.org) — Testing basics chapter (testthat usage), function documentation (roxygen2 syntax without build), code organization
- **CRAN Task View: Reproducible Research** — Pipeline organization patterns, reproducibility tools landscape
- **HiPerGator documentation** (Weecology Wiki, UF HiPerGator guides) — renv integration with module system, cross-platform considerations (Windows dev, Linux HPC)
- **Community resources**: RStudio Community forums, GitHub issue trackers (lintr, styler, checkmate, testthat) — Troubleshooting edge cases, configuration examples, performance discussions

### Tertiary (validated during research)
- **Existing codebase inventory**: 81 R files cataloged (63 numbered, 7 utilities, 6 ad-hoc, 1 runner, 4 special), 95+ source() calls mapped via grep, 25+ RDS artifacts identified (semantic naming verified), 50+ output files cataloged (semantic naming verified), integration points extracted from actual scripts
- **PCORnet CDM v7.0 specification**: ALLCAPS column naming convention (PATID, ENROLL_DATE, DX, PROCEDURES, ENC_TYPE) — requires lintr object_name_linter configuration
- **Phase 0-63 development history**: Organic growth patterns identified (numbering gaps, sub-lettered duplicates, scattered utilities), dependency chains validated against execution order

---
*Research completed: 2026-06-01*
*Ready for roadmap: yes*

**Next steps:** Use this summary + detailed research files (STACK.md, FEATURES.md, ARCHITECTURE.md, PITFALLS.md) to create v2.0 roadmap with 9 primary phases (REORG-01 through SAFE-04/DOC-03) plus potential iteration phases for lintr cleanup and DRY extraction.
