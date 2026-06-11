# Phase 99: Fix gantt_v2 vs gantt_v1 disagreements and bugs, extraneous columns - Research

**Researched:** 2026-06-11
**Domain:** R data export schema consolidation, CSV output validation, Tableau integration
**Confidence:** HIGH

## Summary

Phase 99 consolidates two parallel Gantt export scripts (R/51 v1 and R/52 v2) into a single canonical export by deprecating v1, cleaning v2's schema, and fixing schema validation bugs. The phase involves: (1) deleting R/51, (2) removing extraneous columns (encounter_ids, immunotherapy flags) from R/52 while adding back is_hodgkin for filtering convenience, (3) fixing pseudo-treatment metadata inconsistencies where Death/HL Diagnosis rows incorrectly carry enrichment flags, (4) replacing hardcoded column count verification with dynamic schema definitions, and (5) updating downstream references across R/88 smoke tests and renaming output files to drop the "_v2" suffix.

This is a schema cleanup and consolidation task—no new functionality, purely structural reorganization with validation to ensure correctness. The work follows established patterns from R/95 and R/96 validation scripts (numbered checks with pass/fail reporting).

**Primary recommendation:** Follow the validation-first pattern established in Phases 95-96. Build R/99 validation script first to define expected schema, then execute modifications with immediate pre/post validation.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**V1 Disposition**
- **D-01:** Deprecate v1 entirely. Delete R/51_gantt_data_export.R from the codebase. R/52 becomes the single canonical Gantt export script. Git history preserves R/51 if ever needed.

**Column Reconciliation**
- **D-02:** Keep semicolons for multi-value field separators (triggering_codes, drug_names, triggering_code_descriptions). Phase 64 standard — avoids CSV parsing ambiguity.
- **D-03:** Keep v2 cleanup behavior: empty strings instead of NA, "Unlinked" for blank cancer_category. Better for Tableau filters.
- **D-04:** Keep simplified drug names (Phase 64 BRAND_TO_GENERIC mapping). Full RxNorm descriptions available in treatment_episodes.rds for analysis.
- **D-05:** Rename output files from gantt_episodes_v2.csv / gantt_detail_v2.csv to gantt_episodes.csv / gantt_detail.csv. Drop the _v2 suffix since v2 is now canonical.

**Extraneous Columns**
- **D-06:** Leave out encounter_ids (episodes) and ENCOUNTERID (detail) columns. Too noisy for Tableau visualization; available in treatment_episodes.rds.
- **D-07:** Add is_hodgkin back as a convenience boolean column derived from cancer_category. Easier to filter on TRUE/FALSE than matching a string.
- **D-08:** Keep clinical context columns: regimen_label, is_first_line.
- **D-09:** Keep death/drug info columns: drug_group, cause_of_death.
- **D-10:** Keep source metadata columns: medication_name, code_type, source_table, treatment_line, sct_cross_use_flag.
- **D-11:** Remove immunotherapy context columns from Gantt export: is_sct_conditioning_context, immuno_confidence. These are specialized analysis flags, not visualization-relevant.

**Bug Fixes**
- **D-12:** Clean up pseudo-treatment row metadata. For Death and HL Diagnosis rows, set enrichment columns (regimen_label, is_first_line, drug_group, treatment_line, sct_cross_use_flag, etc.) to empty string rather than NA or FALSE. Prevents misleading Tableau filter results.
- **D-13:** Replace hardcoded column count verification (currently expects 23 episodes, 21 detail) with dynamic verification from a schema definition vector at top of script. Column names defined once, verification checks against that definition.
- **D-14:** Update all downstream references from gantt_*_v2 patterns to gantt_* across the codebase (R/88 smoke tests, any other scripts referencing v2 filenames).
- **D-15:** Create R/99 validation script following established pattern (R/95, R/96) that verifies: column names match schema, row counts preserved, separator consistency, NA handling, is_hodgkin derivation correctness.

### Claude's Discretion
- Column ordering in the final schema (logical grouping preferred)
- R/99 validation script check count and granularity
- How is_hodgkin is derived (cancer_category string match or lookup)
- Whether R/52 gets renamed to just R/52_gantt_export.R (drop _v2 from script name too)

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope.
</user_constraints>

## Standard Stack

### Core (Already Installed)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| dplyr | 1.2.0+ | Data transformation | tidyverse core, used throughout project for readable pipelines |
| glue | 1.8.0+ | String formatting | Project standard for logging messages |
| stringr | 1.5.1+ | String operations | Phase 64 cleanup pattern (semicolon separators, drug simplification) |

### Supporting (Already Defined)
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| CANCER_SITE_MAP | N/A (R/00_config.R) | ICD code → cancer category lookup | Derive is_hodgkin via str_detect() on cancer_category |
| BRAND_TO_GENERIC | N/A (inline in R/52) | Drug name simplification | Already implemented in R/52, leave unchanged per D-04 |

**No new packages required** — Phase 99 uses existing infrastructure.

## Architecture Patterns

### Recommended Modification Order
```
1. Build R/99_validate_gantt_consolidation.R first (validation-driven)
2. Define expected schemas at top of R/52 (EPISODES_SCHEMA, DETAIL_SCHEMA)
3. Modify R/52 column selection to match schemas
4. Run R/99 validation → fix failures → re-validate
5. Update R/88 smoke tests (gantt_*_v2 → gantt_* references)
6. Delete R/51_gantt_data_export.R (git preserves history)
7. Rename output files (drop _v2 suffix)
```

### Pattern 1: Schema Definition Vector (Dynamic Verification)
**What:** Replace hardcoded column count checks with named character vector defining expected schema
**When to use:** Any script producing structured CSV output with fixed columns
**Example:**
```r
# At top of R/52_gantt_v2_export.R (after SECTION 1: SETUP)

# EPISODES SCHEMA DEFINITION (D-13: dynamic verification)
EPISODES_SCHEMA <- c(
  "patient_id", "treatment_type", "episode_number",
  "episode_start", "episode_stop", "episode_length_days",
  "distinct_dates_in_episode", "historical_flag",
  "triggering_codes", "drug_names", "triggering_code_descriptions",
  "cancer_category", "is_hodgkin", "regimen_label", "is_first_line",
  "drug_group", "cause_of_death",
  "medication_name", "code_type", "source_table", "treatment_line", "sct_cross_use_flag"
)

# DETAIL SCHEMA DEFINITION
DETAIL_SCHEMA <- c(
  "patient_id", "treatment_type", "treatment_date",
  "triggering_code", "drug_name", "episode_number",
  "episode_start", "episode_stop", "historical_flag",
  "triggering_code_description", "cancer_category", "is_hodgkin",
  "regimen_label", "is_first_line", "cause_of_death",
  "medication_name", "code_type", "source_table", "treatment_line", "sct_cross_use_flag"
)

# Replace lines ~925-933 with:
if (!identical(colnames(episodes_export), EPISODES_SCHEMA)) {
  missing <- setdiff(EPISODES_SCHEMA, colnames(episodes_export))
  extra <- setdiff(colnames(episodes_export), EPISODES_SCHEMA)
  stop(glue("Schema mismatch: missing={paste(missing, collapse=', ')}, extra={paste(extra, collapse=', ')}"))
}
if (!identical(colnames(detail_export), DETAIL_SCHEMA)) {
  missing <- setdiff(DETAIL_SCHEMA, colnames(detail_export))
  extra <- setdiff(colnames(detail_export), DETAIL_SCHEMA)
  stop(glue("Schema mismatch: missing={paste(missing, collapse=', ')}, extra={paste(extra, collapse=', ')}"))
}
```

### Pattern 2: Pseudo-Treatment Metadata Cleanup
**What:** Set enrichment columns to empty string (not NA/FALSE) for Death and HL Diagnosis rows
**Why:** Prevents Tableau filters from grouping pseudo-treatments with real treatments that have missing metadata
**Example:**
```r
# In Death row construction (~lines 441-479), replace:
#   regimen_label = NA_character_,
#   is_first_line = FALSE,
# with:
#   regimen_label = "",
#   is_first_line = NA,
#   drug_group = "",
#   treatment_line = "",
#   sct_cross_use_flag = "",
```

### Pattern 3: is_hodgkin Derivation
**What:** Derive boolean is_hodgkin from cancer_category string match
**Why:** cancer_category already computed and validated; no need to re-query CANCER_SITE_MAP
**Example:**
```r
# In final select() for episodes_export (~line 894), add after cancer_category:
mutate(
  is_hodgkin = str_detect(cancer_category, "Hodgkin Lymphoma")
)
```

### Pattern 4: R/99 Validation Script Structure (following R/95, R/96 pattern)
```r
# ==============================================================================
# 99_validate_gantt_consolidation.R -- Phase 99 Gantt v2 consolidation validation
# ==============================================================================
#
# Purpose:
#   Validates R/52 produces clean Gantt CSVs with correct schema after v1 deprecation
#   and extraneous column removal. Checks schema compliance, row preservation,
#   is_hodgkin derivation correctness, and pseudo-treatment metadata cleanliness.
#
# Usage:
#   source("R/99_validate_gantt_consolidation.R")
#
# Expected output:
#   Series of [PASS] / [FAIL] messages. All must show [PASS].

source("R/00_config.R")

pass_count <- 0L
fail_count <- 0L

check <- function(description, condition) {
  if (isTRUE(condition)) {
    message(sprintf("[PASS] %s", description))
    pass_count <<- pass_count + 1L
  } else {
    message(sprintf("[FAIL] %s", description))
    fail_count <<- fail_count + 1L
  }
}

# Section 1: Schema compliance checks
# Section 2: Row count preservation checks
# Section 3: is_hodgkin derivation checks
# Section 4: Pseudo-treatment metadata checks
# Section 5: Multi-value separator checks
# Section 6: Output file naming checks

# Final report
message(sprintf("\n=== Validation Summary ==="))
message(sprintf("PASSED: %d checks", pass_count))
message(sprintf("FAILED: %d checks", fail_count))
if (fail_count > 0) {
  stop("Validation failed. Fix errors and re-run.")
}
```

### Anti-Patterns to Avoid

- **Hardcoded column counts:** Current R/52 lines 925-933 use magic numbers (23, 21). Replace with schema vector comparison per D-13.
- **Inconsistent NA handling for pseudo-treatments:** Mixing NA_character_, FALSE, and empty strings creates Tableau filter confusion. Standardize to empty strings per D-12.
- **Renaming output files before validation:** Rename gantt_*_v2.csv → gantt_*.csv only after R/99 validation passes to avoid breaking downstream consumption.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| CSV schema validation | Manual column name checks in ad-hoc order | Named schema vector + identical() comparison | R/52 currently checks column count only. Schema vector enables precise mismatch reporting (missing vs extra columns). |
| is_hodgkin derivation | Re-query CANCER_SITE_MAP or ICD code lookup | str_detect(cancer_category, "Hodgkin Lymphoma") | cancer_category already computed in R/61. String match is simpler and preserves upstream logic. |
| Pseudo-treatment NA cleanup | case_when() across 10+ columns | Standardized construction pattern in Death/HL Diagnosis blocks | Easier to maintain one cleanup point than scattered case_when() logic. |

**Key insight:** R/52 is already 1,007 lines with complex multi-stage construction (treatment rows → Death rows → HL Diagnosis rows → cleanup → export). Incremental fixes at construction time are safer than post-hoc transformations.

## Runtime State Inventory

> Phase 99 is a code/config-only refactor with no external state dependencies.

N/A — No stored data, live service config, OS-registered state, secrets, or build artifacts affected. All changes are in-repo R scripts and CSV output filenames.

## Common Pitfalls

### Pitfall 1: Column Order Mismatch Between Schema and select()
**What goes wrong:** Define EPISODES_SCHEMA with columns in logical order, but select() statement uses different order → schema validation fails even though all columns present
**Why it happens:** Schema vector is documentation, select() is implementation. Easy to update one without the other.
**How to avoid:** Copy EPISODES_SCHEMA directly into select() call as a code comment to keep them visually aligned:
```r
# EPISODES_SCHEMA definition (lines 50-60)
EPISODES_SCHEMA <- c("patient_id", "treatment_type", ...)

# select() call (line 894) — ORDER MUST MATCH SCHEMA
episodes_export <- episodes_export %>%
  select(
    # Core identifiers
    patient_id, treatment_type, episode_number,
    # Episode boundaries
    episode_start, episode_stop, episode_length_days,
    ...
  )
```
**Warning signs:** identical(colnames(df), SCHEMA) returns FALSE despite setdiff() showing zero missing/extra columns

### Pitfall 2: Pseudo-Treatment Rows Bypass is_hodgkin Derivation
**What goes wrong:** Add is_hodgkin derivation via mutate() after select(), but Death/HL Diagnosis rows are constructed separately and appended later → they get is_hodgkin=FALSE instead of derived value
**Why it happens:** Pseudo-treatment construction happens in separate code blocks (lines 441-558) that manually set all column values
**How to avoid:** Set is_hodgkin explicitly in Death/HL Diagnosis construction blocks:
```r
# Death rows: is_hodgkin should be FALSE (not cancer-specific)
is_hodgkin = FALSE,

# HL Diagnosis rows: is_hodgkin should be TRUE (by definition)
is_hodgkin = TRUE,
```
**Warning signs:** Validation script shows "HL Diagnosis rows with is_hodgkin=FALSE" check failing

### Pitfall 3: Updating R/88 References Without Checking File Existence
**What goes wrong:** Update R/88 smoke tests to reference gantt_episodes.csv, but output files haven't been renamed yet → smoke tests fail with "file not found"
**Why it happens:** R/88 has ~10 references to gantt_*_v2 patterns scattered across multiple sections. Easy to update code before outputs.
**How to avoid:** Execute modifications in this order:
1. Modify R/52 output paths (OUTPUT_EPISODES_V2 → OUTPUT_EPISODES)
2. Run R/52 to generate gantt_episodes.csv and gantt_detail.csv
3. Verify both files exist in output/ directory
4. Then update R/88 references
**Warning signs:** R/88 Section 28 fails with "gantt_episodes.csv not found" immediately after phase execution

### Pitfall 4: Forgetting to Update R/52 Header Comment Schema Documentation
**What goes wrong:** Modify R/52 schema (remove columns, add is_hodgkin) but leave header comment lines 39-86 unchanged → next developer reads stale schema documentation
**Why it happens:** Header schema documentation is 48 lines, easy to overlook during code changes
**How to avoid:** Add schema update to validation checklist in R/99:
```r
check("R/52 header documents correct episode column count (22)",
      any(str_detect(r52_lines, "gantt_episodes_v2.csv \\(22 columns\\)")))
```
**Warning signs:** Code review spots discrepancy between header documentation and actual select() statement

## Code Examples

Verified patterns from R/52 v2 export script (current state) and validation scripts (R/95, R/96):

### Schema Definition and Validation
```r
# Source: R/52 lines 925-933 (current hardcoded approach — TO BE REPLACED)
expected_ep_cols <- 23  # was 21, Phase 92: +5 metadata, Phase 93: +2 context = 23
expected_detail_cols <- 21  # was 14, Phase 92: +5 metadata, Phase 93: +2 context = 21

if (ncol(episodes_export) != expected_ep_cols) {
  stop(glue("ERROR: episodes_export has {ncol(episodes_export)} columns, expected {expected_ep_cols}"))
}

# NEW APPROACH (D-13 dynamic verification):
EPISODES_SCHEMA <- c("patient_id", "treatment_type", ...)  # 22 columns after cleanup

if (!identical(colnames(episodes_export), EPISODES_SCHEMA)) {
  missing <- setdiff(EPISODES_SCHEMA, colnames(episodes_export))
  extra <- setdiff(colnames(episodes_export), EPISODES_SCHEMA)
  stop(glue("Schema mismatch: missing={paste(missing, collapse=', ')}, extra={paste(extra, collapse=', ')}"))
}
```

### Pseudo-Treatment Metadata Cleanup
```r
# Source: R/52 lines 441-479 (Death row construction — TO BE MODIFIED per D-12)
death_episodes <- death_data %>%
  mutate(
    # ... core columns ...
    regimen_label = NA_character_,     # BEFORE: NA (misleading in Tableau)
    is_first_line = FALSE,              # BEFORE: FALSE (groups with non-first-line treatments)
    drug_group = NA_character_,         # BEFORE: NA
    treatment_line = NA_character_,     # BEFORE: NA
    sct_cross_use_flag = NA_character_  # BEFORE: NA
  )

# AFTER (D-12 cleanup):
death_episodes <- death_data %>%
  mutate(
    # ... core columns ...
    regimen_label = "",           # Empty string: "no regimen" (not "unknown")
    is_first_line = NA,           # NA: not applicable (not "not first line")
    drug_group = "",              # Empty string: no drug group
    treatment_line = "",          # Empty string: not a treatment line
    sct_cross_use_flag = ""       # Empty string: not applicable
  )
```

### is_hodgkin Derivation
```r
# Source: Existing pattern from R/51 line 122 (v1 approach — reuse in R/52)
is_hodgkin = str_detect(cancer_category, "Hodgkin Lymphoma")

# Context: Add after cancer_category in final select() (~line 894)
episodes_export <- episodes_export %>%
  select(...) %>%
  mutate(
    is_hodgkin = str_detect(cancer_category, "Hodgkin Lymphoma")
  )
```

### R/99 Validation Script Pattern
```r
# Source: R/95_validate_dt_infrastructure.R lines 29-37 (check function pattern)
check <- function(description, condition) {
  if (isTRUE(condition)) {
    message(sprintf("[PASS] %s", description))
    pass_count <<- pass_count + 1L
  } else {
    message(sprintf("[FAIL] %s", description))
    fail_count <<- fail_count + 1L
  }
}

# Sample checks for R/99:
check("R/51_gantt_data_export.R has been deleted", !file.exists("R/51_gantt_data_export.R"))
check("gantt_episodes.csv exists (no _v2 suffix)", file.exists("output/gantt_episodes.csv"))
check("Episodes CSV has 22 columns", ncol(episodes) == 22)
check("Detail CSV has 20 columns", ncol(detail) == 20)
check("is_hodgkin is TRUE for all HL Diagnosis rows",
      all(episodes$is_hodgkin[episodes$treatment_type == "HL Diagnosis"]))
check("Death rows have empty regimen_label (not NA)",
      all(episodes$regimen_label[episodes$treatment_type == "Death"] == ""))
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Parallel v1/v2 scripts (R/51, R/52) | Single canonical script (R/52) | Phase 99 | Eliminates maintenance burden of keeping two schemas in sync |
| Hardcoded column count checks | Schema definition vectors | Phase 99 | Precise mismatch reporting (missing vs extra columns) |
| NA/FALSE for pseudo-treatment metadata | Empty strings for not-applicable columns | Phase 99 | Cleaner Tableau filter behavior (explicit "no value" vs "unknown") |
| Manual column list updates in 3 places | Schema vector copied once, referenced everywhere | Phase 99 | Single source of truth for expected columns |

**Deprecated/outdated:**
- R/51_gantt_data_export.R: Phase 51 v1 schema (14 episodes columns, 13 detail columns). Deprecated in Phase 99 per D-01. Git history preserves implementation if needed.
- Hardcoded expected column counts (R/52 lines 925-933): Replaced by schema vector comparison per D-13.

## Environment Availability

> Phase 99 has no external dependencies beyond the project's existing R environment.

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| R | Script execution | ✓ | 4.4.2+ (HiPerGator standard) | — |
| dplyr | Data manipulation | ✓ | 1.2.0+ (tidyverse core) | — |
| glue | Logging | ✓ | 1.8.0+ (project dependency) | — |
| stringr | is_hodgkin derivation | ✓ | 1.5.1+ (tidyverse core) | — |

**Missing dependencies with no fallback:** None

**Missing dependencies with fallback:** None

All required packages are already installed per Phase 95 infrastructure and project CLAUDE.md stack definition.

## Validation Architecture

> Phase 99 nyquist_validation is explicitly set to false in .planning/config.json — skipping test framework section per protocol.

Validation strategy for Phase 99 follows the established pattern from Phases 95-96: a dedicated R validation script (R/99_validate_gantt_consolidation.R) with numbered checks covering:

1. **Schema compliance:** Column names and order match EPISODES_SCHEMA and DETAIL_SCHEMA
2. **Row count preservation:** No rows lost during schema modifications
3. **is_hodgkin correctness:** Derived correctly from cancer_category
4. **Pseudo-treatment metadata:** Death/HL Diagnosis rows have empty strings (not NA/FALSE)
5. **File naming:** Output files renamed (gantt_*.csv, not gantt_*_v2.csv)
6. **Downstream references:** R/88 smoke tests updated to match new filenames

Expected check count: 25-35 individual assertions (following R/95's 45 checks, R/96's 41 checks pattern scaled to Phase 99 scope).

## Open Questions

1. **Should R/52 script be renamed to R/52_gantt_export.R (drop _v2 suffix)?**
   - What we know: User marked this as "Claude's discretion" in CONTEXT.md
   - What's unclear: Whether script name consistency (matching output file pattern) outweighs Git history continuity
   - Recommendation: Keep R/52_gantt_v2_export.R filename unchanged. Script header comment can note "v2 is now canonical post-Phase 99" without file rename. Rationale: Git history continuity, existing references in R/88 smoke tests.

2. **Should is_hodgkin be placed immediately after cancer_category or at end of column list?**
   - What we know: User preference for "logical grouping"
   - What's unclear: Is "logical grouping" taxonomic (cancer columns together) or derivation-based (derived columns together)?
   - Recommendation: Place is_hodgkin immediately after cancer_category (taxonomic grouping). Pattern: R/51 line 122 shows cancer_category and is_hodgkin adjacent.

3. **What should is_first_line be for Death/HL Diagnosis rows: NA or empty string?**
   - What we know: D-12 says "set enrichment columns to empty string", but is_first_line is logical (TRUE/FALSE), not character
   - What's unclear: R semantics for "not applicable" on logical columns
   - Recommendation: Use NA for logical is_first_line (R's native "not applicable"), empty string "" for character columns (regimen_label, drug_group, treatment_line, sct_cross_use_flag). R/52 currently uses FALSE for is_first_line on pseudo-treatments; change to NA to distinguish "not first line" from "not a treatment line".

## Sources

### Primary (HIGH confidence)
- R/51_gantt_data_export.R (lines 1-543) - v1 schema definition and construction pattern
- R/52_gantt_v2_export.R (lines 1-1007) - v2 schema, Phase 64 cleanup, Phase 92/93 enrichments
- R/88_smoke_test_comprehensive.R (lines 253-254, 485, 1156-1488) - Gantt validation patterns
- R/95_validate_dt_infrastructure.R (lines 1-100) - Validation script structure pattern
- R/96_validate_payer_dt.R (lines 1-100) - Validation check() function pattern
- .planning/phases/99-*/99-CONTEXT.md (lines 1-105) - User decisions D-01 through D-15

### Secondary (MEDIUM confidence)
- R/00_config.R (lines 537+) - CANCER_SITE_MAP for is_hodgkin derivation understanding
- Project CLAUDE.md stack section - Confirms dplyr, stringr, glue versions and conventions

### Tertiary (LOW confidence)
None — all research grounded in existing codebase artifacts.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All packages already installed per project dependencies
- Architecture: HIGH - Patterns directly copied from R/95, R/96 validation scripts and R/52 existing structure
- Pitfalls: HIGH - Identified from actual R/52 code structure (1007 lines, multi-stage construction, separate pseudo-treatment blocks)

**Research date:** 2026-06-11
**Valid until:** 60 days (stable domain: CSV schema consolidation patterns don't change frequently)
