# Feature Landscape

**Domain:** R Pipeline Cleanup, Documentation, and Defensive Coding
**Researched:** 2026-06-01

## Table Stakes

Features users expect. Missing = pipeline feels incomplete or unprofessional.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Sequential script numbering (01-N) | Industry standard for numbered pipelines. RStudio default ordering. Answers "what runs when?" | Low | Mechanical renaming. Dependency: cross-references must update. Example: `01-load-data.R`, `02-clean.R` |
| Header block in every script | Standard practice for reproducible research. Documents purpose, author, date, outputs | Low | Manual but formulaic. Template: purpose, inputs, outputs, dependencies |
| Section headers within scripts | RStudio outline/navigation feature. Makes 500+ line scripts navigable | Low | RStudio `Ctrl+Shift+R` generates automatically. Requires 4+ dashes: `# Section Name ----` |
| Descriptive variable/function names | R style guide baseline (Hadley Wickham, Google). snake_case for readability | Low | Already in codebase via tidyverse style |
| Input file existence checks | Defensive programming 101. "Fail fast" before 30 min processing | Low | `stopifnot(file.exists("data.csv"))` or assertr. Prevents cryptic downstream errors |
| README with run order | Onboarding requirement. Answers "how do I run this pipeline?" | Low | Linear list of scripts with 1-sentence purpose each |
| Comments explaining non-obvious logic | Code review standard. Future maintainer (or future you) needs context | Medium | Judgment call: what's "obvious"? Err on side of over-commenting for clinical logic |
| Centralized constants/lookups | DRY principle. Multiple copies = maintenance nightmare, divergence risk | Medium | Already started: `AMC_PAYER_LOOKUP` in `R/00_config.R`. Need to consolidate `PREFIX_MAP`, code mappings |
| Error messages with context | Debugging requirement. "Assertion failed" vs "ENROLLMENT.csv not found in /blue/..." | Low | Use `glue()` for messages: `stop(glue("Missing {file} at {path}"))` |

## Differentiators

Features that set pipeline apart. Not expected, but valued by reviewers/collaborators.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Automated dependency checks | Verifies required RDS artifacts exist before each script runs. Prevents "file not found" 20 min into execution | Low-Medium | Simple: `stopifnot(file.exists("cohort.rds"))`. Advanced: `targets` package auto-tracks |
| Smoke test script | CI/CD standard. Verifies pipeline integrity after changes. Catches cross-reference bugs immediately | Medium | Run subset of scripts (1-5 min), check outputs exist + row counts match expected ranges |
| Assertion-rich pipeline (checkmate/assertr) | Data quality gates. Catches upstream data changes early (e.g., new ENC_TYPE value) | Medium | `assertr::verify()` for data frames. Example: `verify(n_distinct(PATID) == expected_n)` |
| Reference manual with dependency matrix | Documents inputs/outputs/dependencies for every script in table format | Medium | Example: Script 05 → Inputs: {03.rds, 04.rds} → Outputs: {filtered_cohort.rds} → Dependencies: {00_config.R} |
| Self-documenting code via checkmate | Assertions double as executable documentation. `assert_numeric(age, lower = 0, upper = 120)` says "age in years 0-120" | Medium | Pipeline-friendly. More readable than comments |

## Anti-Features

Features to explicitly NOT build.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Full package conversion (NAMESPACE, DESCRIPTION) | Over-engineering for analysis pipeline. Package overhead not justified. Delays v2.0 by weeks | Keep scripts + utility functions. Use roxygen2 syntax for function docs only, not full package build |
| Automated code style enforcement on every commit | Adds friction to commits. HiPerGator workflow doesn't use git heavily | Run styler manually before milestone completion. Defer automated enforcement to v3 if team grows |
| Unit tests for every function (testthat) | Analysis scripts, not production software. High maintenance cost vs value | Reserve testing for smoke tests + critical utility functions only |
| Interactive documentation (pkgdown site) | Overkill for 1-2 person project. Maintenance burden | Markdown reference manual is sufficient. Static, versionable, readable |
| Automated pipeline orchestration (targets/drake) | Major architecture change. Re-learning curve. Existing sequential scripts work | Defer to v3+ if pipeline grows >100 scripts or compute time >4 hours |
| Git hooks for pre-commit validation | Adds friction to commits. HiPerGator workflow doesn't use git heavily | Manual smoke test before milestone tagging |
| Comprehensive input validation (pointblank) | Already deferred in STACK.md. Python pipeline handles data cleaning. R pipeline validates cohort logic only | Use stopifnot() + checkmate for critical checks. Full validation is out of scope |
| Refactoring to object-oriented (R6 classes) | Analysis pipeline = procedural workflow. OOP adds complexity without benefits | Keep functional style with named predicates. R6 for package development only |

## Feature Dependencies

```
Script Renumbering (01-N)
  → Cross-Reference Updates (source() calls, comments, README)
    → Smoke Test (verify cross-references work)

Centralized Constants (R/00_config.R consolidation)
  → No dependencies, but BLOCKS:
    → Cross-script validation (if constants diverged, reveals bugs)

Input Validation (file.exists checks)
  → No dependencies, ENHANCES:
    → Error messages with context (both low-hanging fruit)

Section Headers + Header Blocks
  → No dependencies, ENABLES:
    → Reference manual (scrape headers programmatically)
```

## MVP Recommendation

**Milestone: v2.0 Codebase Cleanup & Documentation**

### Prioritize (Phase 1-3):

1. **Script Renumbering** (REORG-01) — Mechanical, unblocks everything
2. **Cross-Reference Updates** (REORG-02) — Critical dependency, must follow renumbering
3. **Smoke Test** (SAFE-04) — Validates renumbering worked, prevents regressions
4. **Header Blocks** (DOC-01) — Quick wins, enables reference manual
5. **Section Headers** (DOC-01) — RStudio Ctrl+Shift+R, 5 min per script
6. **Input Validation** (SAFE-03) — `file.exists()` checks, fail-fast pattern
7. **Centralized Constants** (DRY-01) — Prevents divergence bugs, improves maintainability

### Defer (Phase 4+):

8. **Auto-formatting** (SAFE-01) — styler for consistent style after renumbering
9. **Defensive Checks** (SAFE-03) — Type/structure assertions, row-count checks (build incrementally)
10. **Reference Manual** (DOC-03) — Comprehensive table (can scrape from header blocks)
11. **Utility Function Extraction** (DRY-02) — Refactor repeated patterns (identify during cleanup)

### Out of Scope for v2.0:

- Dependency graph visualization (valuable but not blocking)
- roxygen2 package build (only syntax for function comments)
- Logging infrastructure (already have tidylog; file logging is nice-to-have)
- Automated cross-reference updating (too risky vs manual + verification)

## Sources

### Script Naming & Numbering
- [R for Data Science: Workflow Scripts](https://r4ds.hadley.nz/workflow-scripts.html) — Sequential numbering with meaningful names
- [Google's R Style Guide](https://web.stanford.edu/class/cs109l/unrestricted/resources/google-style.html) — Industry standard conventions

### Code Commenting & Documentation
- [R Packages: Function Documentation](https://r-pkgs.org/man.html) — roxygen2 best practices
- [Tidyverse Style Guide: Comments](https://style.tidyverse.org/syntax.html#comments) — Section headers and inline documentation

### Input Validation & Defensive Coding
- [checkmate: Fast Argument Checks for Defensive R Programming (R Journal 2017)](https://journal.r-project.org/archive/2017/RJ-2017-028/RJ-2017-028.pdf) — checkmate package methodology

### Testing
- [testthat Documentation](https://testthat.r-lib.org/) — R testing framework (v3.3.2, Jan 2026)

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Script numbering conventions | **HIGH** | Multiple authoritative sources (Hadley Wickham's R4DS, Google R Style Guide). Industry standard pattern. |
| Commenting standards | **HIGH** | roxygen2 is official R documentation framework. Multiple style guides converge on same recommendations. |
| Input validation | **HIGH** | checkmate published in R Journal (peer-reviewed). stopifnot() is base R. |
| Testing approaches | **MEDIUM** | testthat is official R testing framework (latest version verified from CRAN, Jan 2026). Smoke testing concepts from general software engineering (not R-specific). |
| Reference manual structure | **MEDIUM** | No single authoritative standard for multi-script R pipelines. Synthesized from targets/pipeflow package documentation and general software engineering practices. |

**Overall confidence:** **HIGH** — Core recommendations (numbering, headers, validation, testing) are well-established R community standards.
