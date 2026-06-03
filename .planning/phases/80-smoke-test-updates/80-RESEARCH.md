# Phase 80: Smoke Test Updates - Research

**Researched:** 2026-06-03
**Domain:** R testing infrastructure (manual check() pattern, static analysis)
**Confidence:** HIGH

## Summary

Phase 80 adds smoke test validation for Phase 79 scripts (R/54-56), expands decade validation lists to include new scripts (R/35, R/54-56, R/76), fixes inconsistent section numbering throughout R/88, and updates the validated requirements summary. The smoke test uses an established manual `check()` function pattern (no testthat framework), performing static analysis via `readLines()` + `grepl()` without executing data-dependent code.

Research confirms: (1) testing infrastructure is standalone script-based (R/86, R/87, R/88) using custom check() helpers, (2) static analysis patterns are established for validating script structure, dependencies, and output patterns, (3) Phase 79 scripts follow v2.0 standards with structured headers and section markers, (4) section numbering inconsistency exists ([18/22]-[21/22] then [14/16]-[15/16]), and (5) decade lists require expansion for 17 cancer scripts, 7 output scripts, and R/35 in a quality/investigations group.

**Primary recommendation:** Add three new check sections (13E, 13F, 13G) for R/54-56 validation following existing patterns from Section 13B (R/26), fix all [N/M] progress labels to sequential numbering, expand decade lists in Sections 6 and 8, add R/35 to a new or existing decade group, and update the summary requirements list.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**D-01:** Static analysis for R/54 (SCT 0362 investigation), R/55 (replaced-by verification), and R/56 (new drug grouping tables) — ~5-8 checks per script matching the existing depth used for R/26, R/35, R/49, R/52 sections.

**D-02:** Check patterns include: source() dependencies, key column references, output file patterns (xlsx), script-specific logic (e.g., igraph usage in R/55, sheet structure in R/56), and documentation headers.

**D-03:** Renumber ALL section progress labels [N/M] to reflect actual total section count. Current labels are inconsistent — sections 13-13D use [18/22]-[21/22], then sections 14-16 use [14/16]-[15/16]. After adding Phase 79 sections, all labels must be sequential and accurate.

**D-04:** Clean sequential numbering from Section 1 through the final section. The summary line "ALL N CHECKS PASSED" will reflect the true total.

**D-05:** Expand cancer decade validation from 14 scripts (40-53) to include R/54, R/55, R/56 — 17 scripts total (40-56). Update the section label and expected count.

**D-06:** Expand output decade validation from 6 scripts (70-75) to include R/76 — 7 scripts total (70-76). Update the section label and expected count.

**D-07:** Add decade coverage for R/35 in the 30s range. Either widen an existing decade or add a new "Quality/Investigations (30-39)" decade with R/35. Claude's discretion on the cleanest boundary.

**D-08:** Add CODE-01, CODE-02, TREAT-03 to the "Validated requirements" list at end of R/88.

**D-09:** Update the version banner text if needed to reflect v2.1 completeness.

### Claude's Discretion

- Internal organization of new check sections (group by script vs group by requirement)
- Exact set of static analysis patterns to check per Phase 79 script (within the ~5-8 checks guideline)
- Whether R/35 gets its own decade group or merges into an adjacent one
- Specific check descriptions and glue() message formatting

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope

</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| QUAL-01 | v2.0 standards for all modified scripts | Smoke test patterns from Phase 74, R/88 existing structure validates all v2.1 changes with static analysis |

</phase_requirements>

## Standard Stack

### Core Testing Framework

| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| Manual check() pattern | N/A | Test assertion framework | Established in R/86/R/87/R/88; no external dependencies; SLURM-compatible exit codes |
| glue | 1.8.0 (from renv.lock) | String interpolation for check messages | Already loaded in R/88; clean dynamic message formatting |
| base R readLines() | N/A | Static script analysis | Zero dependencies; reads script content without execution |
| base R grepl() | N/A | Pattern matching | Zero dependencies; validates code patterns, column names, source() calls |

### Supporting Libraries

None required. All smoke test functionality uses base R + glue (already in use).

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Manual check() | testthat | testthat not in renv.lock; would require new dependency; over-engineering for structural validation |
| readLines() + grepl() | stringr::str_detect | stringr already loaded, but grepl() is base R and sufficient for simple patterns |
| Exit code 1 on failure | testthat::test_that | Test framework would complicate SLURM job integration; existing pattern works |

**Installation:**

No new packages required. Existing R/88 dependencies are sufficient (glue already loaded in Section 1).

**Version verification:** N/A (using base R + existing dependencies)

## Architecture Patterns

### Recommended Test Structure

```
R/88_smoke_test_comprehensive.R
├── SECTION 1: SETUP                     # check() function, glue library
├── SECTIONS 2-12: Foundation checks     # Existing coverage (utils, config, decades)
├── SECTION 13: NLPHL classification     # Phase 75 validation
├── SECTION 13B: TR removal              # Phase 76 validation
├── SECTION 13C: Drug groupings          # Phase 77 validation
├── SECTION 13D: 7-day gap extension     # Phase 77 validation
├── SECTION 14: Death quality profiling  # Phase 75 validation (R/35)
├── SECTION 15: Episode enrichment       # Phase 78 validation
├── NEW: SECTION 13E: SCT 0362           # Phase 79: R/54 validation
├── NEW: SECTION 13F: Replaced-by codes  # Phase 79: R/55 validation
├── NEW: SECTION 13G: Drug grouping tables # Phase 79: R/56 validation
└── SECTION 16: SUMMARY                  # Pass/fail totals, requirements list
```

**Note:** Section numbering will be renumbered sequentially in Phase 80 (D-03, D-04).

### Pattern 1: Static Script Analysis (Per-Script Validation)

**What:** Validate script structure without execution by reading file content with `readLines()` and checking patterns with `grepl()`.

**When to use:** Validating source() dependencies, key column references, output file patterns, section headers, documentation completeness.

**Example:**
```r
# Check source() dependencies
r54_lines <- readLines("R/54_investigate_sct_0362.R")
check(
  "R/54 sources R/00_config.R",
  any(grepl('source\\("R/00_config.R"\\)', r54_lines))
)

# Check xlsx output pattern
check(
  "R/54 outputs sct_0362_investigation.xlsx",
  any(grepl("sct_0362_investigation\\.xlsx", r54_lines))
)

# Check TREATMENT_CODES reference
check(
  "R/54 references TREATMENT_CODES for SCT codes",
  any(grepl("TREATMENT_CODES", r54_lines))
)
```

### Pattern 2: Multi-Check Script Section

**What:** Group 5-8 checks per script in a named section with progress label.

**When to use:** Validating each Phase 79 script (R/54, R/55, R/56).

**Example:**
```r
message("\n[N/M] Phase 79: SCT 0362 investigation (CODE-02)...")

r54_lines <- readLines("R/54_investigate_sct_0362.R", warn = FALSE)

check("R/54 exists", file.exists("R/54_investigate_sct_0362.R"))
check("R/54 sources R/00_config.R", any(grepl('source\\("R/00_config.R"\\)', r54_lines)))
check("R/54 references TREATMENT_CODES", any(grepl("TREATMENT_CODES", r54_lines)))
check("R/54 outputs sct_0362_investigation.xlsx", any(grepl("sct_0362_investigation\\.xlsx", r54_lines)))
check("R/54 uses openxlsx2 for multi-sheet output", any(grepl("library\\(openxlsx2\\)|openxlsx2::", r54_lines)))
check("R/54 has >= 6 section headers", sum(grepl("^# ---.*SECTION.*----", r54_lines)) >= 6)
```

### Pattern 3: Decade List Expansion

**What:** Expand existing decade validation lists with new script numbers.

**When to use:** Adding new scripts to established decades (40-59 cancer, 70-79 output).

**Example:**
```r
# BEFORE (Section 6):
cancer_expected <- c(
  "40_cancer_site_frequency.R", ..., "53_death_date_validation.R"
)
check(glue("Cancer decade: 14/14 scripts (found {cancer_found})"), cancer_found == 14)

# AFTER (Section 6):
cancer_expected <- c(
  "40_cancer_site_frequency.R", ..., "53_death_date_validation.R",
  "54_investigate_sct_0362.R", "55_verify_replaced_by_codes.R",
  "56_new_tables_from_groupings.R"
)
check(glue("Cancer decade: 17/17 scripts (found {cancer_found})"), cancer_found == 17)
```

### Anti-Patterns to Avoid

- **Don't execute data-dependent code in smoke tests:** Use `readLines()` to check patterns, not `source()` which would execute the script and require data availability.
- **Don't use absolute line numbers:** Patterns like `grepl("pattern", r54_lines[100])` are fragile. Use `any(grepl("pattern", r54_lines))` to check entire file.
- **Don't skip section renumbering:** Adding sections without renumbering creates inconsistent progress labels that confuse users reading test output.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Testing framework | Custom assertion library | Manual check() pattern from R/86 | Already established; zero dependencies; SLURM-compatible |
| Pattern matching | Custom regex parser | Base R grepl() | Sufficient for static analysis; widely documented |
| String interpolation | paste0() everywhere | glue() | Already loaded; cleaner syntax for check messages |
| Multi-sheet xlsx validation | Custom xlsx parser | Pattern matching on openxlsx2 calls | Don't need to open xlsx files; validate code references them |

**Key insight:** Smoke tests validate code structure, not data outputs. Static analysis via `readLines()` + `grepl()` is faster and more portable than executing scripts or parsing data files.

## Runtime State Inventory

> Skipped — Phase 80 is structural smoke test additions only (code/config-only changes). No runtime dependencies on databases, services, OS-registered state, or build artifacts.

## Common Pitfalls

### Pitfall 1: Inconsistent Section Numbering

**What goes wrong:** Adding new sections (13E, 13F, 13G) without renumbering ALL progress labels creates confusing output where Section 14 shows `[14/16]` but there are actually 19 sections.

**Why it happens:** Sections 13-13D use `[18/22]-[21/22]` labels (from earlier phase work), then sections 14-16 use `[14/16]-[15/16]` (inconsistent scheme). Adding more sections compounds the confusion.

**How to avoid:** Renumber ALL `[N/M]` labels sequentially from Section 1 through final section. Count actual sections, update M to match. Use consistent scheme throughout.

**Warning signs:** Progress labels where N > M, labels that skip numbers, or sections with different M values.

**Example fix:**
```r
# BEFORE (inconsistent):
message("\n[18/22] NLPHL classification...")  # Section 13
message("\n[19/22] TR removal...")            # Section 13B
message("\n[14/16] Death quality...")         # Section 14 (wrong!)

# AFTER (sequential, with 3 new sections = 19 total):
message("\n[13/19] NLPHL classification...")  # Section 13
message("\n[14/19] TR removal...")            # Section 13B
message("\n[15/19] Drug groupings...")        # Section 13C
message("\n[16/19] 7-day gap extension...")   # Section 13D
message("\n[17/19] SCT 0362 investigation...") # Section 13E (new)
message("\n[18/19] Death quality...")         # Section 14
message("\n[19/19] Summary...")               # Section 16
```

### Pitfall 2: Overly Specific Pattern Matching

**What goes wrong:** Checks that look for exact strings fail when implementation details change (e.g., checking for exact column order, specific variable names, exact file paths).

**Why it happens:** Copy-pasting exact code snippets from scripts into grepl() patterns creates brittle tests.

**How to avoid:** Match essential patterns, not implementation details. Check for key column names, source() file references, output filename patterns — not exact syntax.

**Warning signs:** Smoke test failures when scripts are refactored but remain functionally correct.

**Example:**
```r
# TOO SPECIFIC (brittle):
check("R/55 has exact igraph call",
      any(grepl("g <- graph_from_data_frame\\(edge_list, directed = TRUE\\)", r55_lines)))

# BETTER (essential pattern):
check("R/55 uses igraph for graph construction",
      any(grepl("graph_from_data_frame|igraph", r55_lines)))
```

### Pitfall 3: Missing Script-Specific Logic Validation

**What goes wrong:** Generic checks (file exists, has source() calls) pass, but script-specific functionality isn't validated. E.g., R/55 uses igraph for cycle detection — smoke test should confirm igraph usage.

**Why it happens:** Copy-pasting check templates without customizing for script's unique features.

**How to avoid:** Review Phase 79 CONTEXT.md decisions (D-05 through D-16) to identify script-specific patterns: R/54 uses TREATMENT_CODES, R/55 uses igraph, R/56 uses 2-sheet output structure.

**Warning signs:** All three scripts have identical check patterns despite different purposes.

**Example (R/55 specific checks):**
```r
check("R/55 uses igraph for DAG checking", any(grepl("library\\(igraph\\)|igraph::", r55_lines)))
check("R/55 has is_dag() call for cycle detection", any(grepl("is_dag", r55_lines)))
check("R/55 outputs 3-sheet workbook", any(grepl("Sheet.*Pairwise.*Chain.*Summary", r55_text)))
```

### Pitfall 4: Decade List Count Mismatches

**What goes wrong:** Adding R/54-56 to cancer decade list but forgetting to update expected count from 14 to 17, causing permanent test failure.

**Why it happens:** Two-step process (add to list, update count) — easy to forget second step.

**How to avoid:** Always update both: (1) append to expected script list, (2) update expected count in check() call.

**Warning signs:** Check message shows "Cancer decade: 17/14 scripts (found 17)" — count in check() doesn't match reality.

**Example:**
```r
# BEFORE:
cancer_expected <- c("40_cancer_site_frequency.R", ..., "53_death_date_validation.R")
check(glue("Cancer decade: 14/14 scripts (found {cancer_found})"), cancer_found == 14)

# AFTER (both changes):
cancer_expected <- c(
  "40_cancer_site_frequency.R", ..., "53_death_date_validation.R",
  "54_investigate_sct_0362.R", "55_verify_replaced_by_codes.R", "56_new_tables_from_groupings.R"
)
check(glue("Cancer decade: 17/17 scripts (found {cancer_found})"), cancer_found == 17)
```

### Pitfall 5: R/35 Decade Assignment Ambiguity

**What goes wrong:** R/35_death_cause_quality.R doesn't naturally fit existing decade boundaries (10-19 cohort, 20-29 treatment, 40-59 cancer). Creating a new "30-39 Quality/Investigations" decade for a single script feels over-engineered, but ignoring it leaves decade coverage incomplete.

**Why it happens:** Decade scheme was designed before quality profiling scripts existed. R/35 is legitimately in the 30s but doesn't have neighbors.

**How to avoid:** Either (1) create minimal "Quality/Investigations (30-39)" decade group with R/35 as the only member (leaves room for future quality scripts), or (2) extend cohort decade to "Cohort & Quality (10-39)" encompassing 10-14 cohort + R/35 quality.

**Warning signs:** R/35 validated in dedicated section (Section 14) but missing from any decade list validation.

**Recommended approach:** Create "Quality/Investigations (30-39)" decade with R/35 as sole member. Mirrors the structure of Section 14 (dedicated validation) and leaves clean extensibility if Phase 81+ adds R/36, R/37 quality scripts.

**Example:**
```r
# NEW Section (insert after Section 5):
message("\n[N/M] Quality/Investigations decade (30-39)...")

quality_scripts <- c("35_death_cause_quality.R")
quality_found <- 0L
for (s in quality_scripts) {
  if (file.exists(file.path("R", s))) quality_found <- quality_found + 1L
}
check(glue("Quality/Investigations decade: 1/1 scripts (found {quality_found})"), quality_found == 1)
```

## Code Examples

Verified patterns from R/88_smoke_test_comprehensive.R (current state):

### Existing check() Function Pattern
```r
# Source: R/88_smoke_test_comprehensive.R:47-55
check <- function(description, condition) {
  if (condition) {
    message(glue("  PASS: {description}"))
    passed <<- passed + 1L
  } else {
    message(glue("  FAIL: {description}"))
    failed <<- failed + 1L
  }
}
```

### Existing Static Analysis Pattern (Section 13B: TR Removal)
```r
# Source: R/88_smoke_test_comprehensive.R:706-732
r26_lines <- readLines("R/26_treatment_episodes.R")
r26_text <- paste(r26_lines, collapse = "\n")

# Check 1: No live tr_dates assignments
tr_dates_assignments <- sum(grepl("tr_dates <- NULL", r26_lines, fixed = TRUE))
check(
  glue("R/26 has no tr_dates <- NULL assignments (found {tr_dates_assignments})"),
  tr_dates_assignments == 0
)

# Check 2: No TR in any sources list
tr_source_refs <- sum(grepl("TR = tr_dates", r26_lines, fixed = TRUE))
check(
  glue("R/26 has no TR = tr_dates in sources lists (found {tr_source_refs})"),
  tr_source_refs == 0
)

# Check 6: Chemo sources list has 6 entries (no TR)
chemo_has_6 <- grepl(
  "PX = px_dates.*RX = rx_dates.*DX = dx_dates.*DRG = drg_dates.*DISP = disp_dates.*MA = ma_dates",
  r26_text
) && !grepl("TR = tr_dates.*type_name = .Chemotherapy", r26_text)
check("Chemotherapy uses 6 sources (PX, RX, DX, DRG, DISP, MA)", chemo_has_6)
```

### Existing Multi-Sheet XLSX Output Validation (Section 14: R/35)
```r
# Source: R/88_smoke_test_comprehensive.R:882-928
if (file.exists("R/35_death_cause_quality.R")) {
  r35_lines <- readLines("R/35_death_cause_quality.R", warn = FALSE)

  check("R/35 sources R/00_config.R",
        any(grepl('source\\("R/00_config.R"\\)', r35_lines)))

  check("R/35 references DEATH_CAUSE_MAP for cause mapping",
        any(grepl("DEATH_CAUSE_MAP", r35_lines)))

  check("R/35 has DEATH_CAUSE field availability guard",
        any(grepl("death_cause_available|DEATH_CAUSE.*names", r35_lines)))

  check("R/35 outputs death_cause_quality.xlsx",
        any(grepl("death_cause_quality\\.xlsx", r35_lines)))

  check("R/35 saves quality decision artifact",
        any(grepl("death_cause_quality_result\\.rds", r35_lines)))

  check(glue("R/35 has >= 6 section headers (found: {n_sections_r35})"),
        n_sections_r35 >= 6)
}
```

### Decade List Validation Pattern (Section 6: Cancer Decade)
```r
# Source: R/88_smoke_test_comprehensive.R:226-244
message("\n[6/22] Cancer decade (40-53)...")

cancer_expected <- c(
  "40_cancer_site_frequency.R", "41_extract_all_codes.R",
  "42_build_code_descriptions.R", "43_cancer_site_confirmation.R",
  "44_cancer_site_confirmation_7day.R", "45_cancer_summary.R",
  "46_cancer_summary_table.R", "47_cancer_summary_refined.R",
  "48_cancer_summary_post_hl.R", "49_cancer_summary_pre_post.R",
  "50_all_codes_resolved.R", "51_gantt_data_export.R",
  "52_gantt_v2_export.R", "53_death_date_validation.R"
)
cancer_found <- 0L
for (s in cancer_expected) {
  if (file.exists(file.path("R", s))) cancer_found <- cancer_found + 1L
}
check(
  glue("Cancer decade: 14/14 scripts (found {cancer_found})"),
  cancer_found == 14
)
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| testthat framework | Manual check() pattern | Phase 74 (June 2026) | Zero external dependencies; SLURM-compatible; cross-platform portability |
| Data-dependent testing | Static analysis via readLines() | Phase 74 (June 2026) | Tests run on Windows dev environment without HiPerGator data access |
| Separate smoke tests (R/86, R/87) | Consolidated R/88 | Phase 74 (June 2026) | Single comprehensive test script; 1039 lines covering 15 validation domains |

**Deprecated/outdated:**
- R/86_smoke_test_foundation.R: Superseded by R/88 (R/88 includes all R/86 checks in Sections 2-4)
- R/87_smoke_test_full_pipeline.R: Superseded by R/88 (R/88 includes all R/87 checks in Sections 5-12)

## Open Questions

1. **R/35 decade assignment strategy:**
   - What we know: R/35 exists, validated in Section 14, but not in any decade list
   - What's unclear: Whether to create "Quality/Investigations (30-39)" decade for one script, or extend cohort decade to "Cohort & Quality (10-39)"
   - Recommendation: Create "Quality/Investigations (30-39)" decade with R/35 as sole member. Mirrors dedicated Section 14 validation and leaves clean extensibility for future R/36+ quality scripts. Insert as new section after Section 5 (treatment decade).

2. **Section renumbering approach:**
   - What we know: Current labels are inconsistent ([18/22] through [21/22], then [14/16] through [15/16])
   - What's unclear: Whether to renumber during Phase 80 wave 1 (structural fixes) or wave 2 (Phase 79 additions)
   - Recommendation: Renumber ALL sections in a single wave after adding new Phase 79 sections. Prevents multiple passes through 1039-line file. Count final sections (likely 19 or 20 depending on R/35 decade), update all `[N/M]` labels once.

## Environment Availability Audit

> SKIPPED (no external dependencies identified)

Phase 80 is structural smoke test updates with zero external dependencies beyond existing R/88 dependencies (glue, base R). No CLI tools, databases, services, or package manager operations required.

## Sources

### Primary (HIGH confidence)

- R/88_smoke_test_comprehensive.R (lines 1-1039) - Current smoke test structure, check() pattern, static analysis examples
- .planning/phases/74-smoke-testing-reference-manual/74-CONTEXT.md - Original smoke test decisions (D-01 through D-11)
- .planning/phases/79-code-investigations-new-tables/79-CONTEXT.md - Phase 79 script decisions (D-01 through D-17), script-specific patterns
- .planning/phases/80-smoke-test-updates/80-CONTEXT.md - Phase 80 constraints and decisions (D-01 through D-09)

### Secondary (MEDIUM confidence)

- R/54_investigate_sct_0362.R (lines 1-287) - Script structure, dependencies, output patterns for validation
- R/55_verify_replaced_by_codes.R (lines 1-376) - igraph usage, replaced-by verification patterns
- R/56_new_tables_from_groupings.R (lines 1-224) - 2-sheet xlsx structure, DRUG_GROUPINGS usage
- R/35_death_cause_quality.R (lines 1-50) - Existing quality profiling pattern reference
- R/76_treatment_source_coverage.R (lines 1-50) - Existing coverage analysis pattern reference

### Tertiary (LOW confidence)

None — all findings verified against existing code.

## Metadata

**Confidence breakdown:**
- Testing framework (manual check()): HIGH - pattern established in R/86/R/87/R/88, no alternatives needed
- Static analysis patterns: HIGH - extensively used in existing Sections 13-15 with proven reliability
- Phase 79 script structure: HIGH - scripts exist, follow v2.0 standards, patterns clearly documented
- Section numbering fix: HIGH - inconsistency confirmed by reading R/88 lines 65-1004
- Decade list expansion: HIGH - clear script additions (R/54-56, R/76), counts verified

**Research date:** 2026-06-03
**Valid until:** 2026-09-03 (90 days — testing infrastructure stable, no rapid ecosystem changes expected)
