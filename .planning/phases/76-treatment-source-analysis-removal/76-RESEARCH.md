# Phase 76: Treatment Source Analysis & Removal - Research

**Researched:** 2026-06-02
**Domain:** Treatment data source audit, tumor registry data quality, pipeline refactoring
**Confidence:** HIGH

## Summary

Phase 76 quantifies tumor registry (TR) treatment data coverage before removing it from the treatment episode pipeline (R/26-29). The goal is to prevent silent data loss by documenting how many episodes are TR-only vs. captured by claims-based sources (PROCEDURES, DISPENSING, MED_ADMIN, ENCOUNTER). Research confirms that TR data has known quality issues (8-32% accuracy per SEER literature vs. 95-100% for EHR claims), justifying its removal. The current pipeline includes TR as source #7 in 3 treatment types: chemotherapy (7 sources: PX, RX, DX, DRG, DISP, MA, TR), radiation (4 sources: PX, DX, DRG, TR), and SCT (3 sources: PX, DRG, TR). Immunotherapy has no TR source (2 sources: PX, DRG only).

**Primary recommendation:** Create a standalone coverage analysis script (R/91_treatment_source_coverage.R) that runs before pipeline modification, produces CSV output showing episode counts by source combination (TR-only, claims-only, both), then remove TR blocks from R/26 extraction functions. Add checkmate assertion to halt pipeline if episode count drops >20% (guards against silent data loss). Follow diagnostic script numbering convention (90s series) and openxlsx2 audit pattern from R/26/R/28.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| TREAT-01 | All treatment data sourced from tumor registry dropped from treatment episode pipeline | TR appears in 3 of 4 treatment types (chemo/radiation/SCT); removal requires modifying extraction functions in R/26_treatment_episodes.R lines 195-223 (chemo), 277-305 (radiation), 341-372 (SCT) |
| QUAL-01 | All new/modified scripts follow v2.0 standards (styler formatting, lintr compliance, checkmate assertions, documentation headers, smoke test updates) | Smoke test patterns established in R/88_smoke_test_comprehensive.R; diagnostic script numbering (90s) follows R/92, R/93 convention from Phase 79 roadmap |

</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| dplyr | 1.2.0+ | Data transformation | Existing codebase dependency; used for all data manipulation |
| glue | 1.8.0+ | String interpolation | Logging and message formatting throughout codebase |
| openxlsx2 | 1.14+ | Excel output | Audit report pattern from R/26 (phase_60_audit.xlsx), R/28 (episode_classification_audit.xlsx) |
| checkmate | 1.0.0+ | Assertion validation | v2.0 standard for all new scripts; runtime validation |

**Installation:**
None required — all dependencies already in project renv.lock.

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| purrr | 1.0.2+ | Functional programming | compact() for filtering NULL sources in stack_and_dedup_with_codes() |
| tidyr | 1.3.1+ | Data reshaping | pivot_longer() if coverage table needs reshaping for visualization |

**No new package dependencies required.**

## Architecture Patterns

### Recommended Project Structure
Coverage analysis script follows diagnostic numbering convention (90s series):
```
R/
├── 26_treatment_episodes.R        # Modified: remove TR source blocks
├── 91_treatment_source_coverage.R # NEW: pre-removal coverage analysis
├── 88_smoke_test_comprehensive.R  # Modified: validate TR removal
└── utils/
    └── utils_assertions.R         # Existing: checkmate assertion helpers
```

### Pattern 1: Treatment Source Extraction (Existing Pattern)
**What:** Each treatment type has extraction function returning (ID, treatment_date, triggering_code, ENCOUNTERID) from multiple sources, then stacks via `stack_and_dedup_with_codes(sources = list(...))`.

**Current structure (R/26, lines 118-232):**
```r
extract_chemo_dates_with_codes <- function() {
  # 1. PROCEDURES (PX)
  px_dates <- get_pcornet_table("PROCEDURES") %>% ...

  # 2. PRESCRIBING (RX)
  rx_dates <- get_pcornet_table("PRESCRIBING") %>% ...

  # ... 5 more sources ...

  # 7. TUMOR_REGISTRY_ALL (TR) — THIS IS REMOVED IN PHASE 76
  tr_dates <- NULL
  if (!is.null(get_pcornet_table("TUMOR_REGISTRY_ALL"))) {
    tr_chemo_cols <- intersect(
      c("CHEMO_START_DATE_SUMMARY", "DT_CHEMO"),
      colnames(get_pcornet_table("TUMOR_REGISTRY_ALL"))
    )
    if (length(tr_chemo_cols) > 0) {
      tr_data <- get_pcornet_table("TUMOR_REGISTRY_ALL") %>% ...
      # ... pivot_longer, filter, mutate ...
    }
  }

  stack_and_dedup_with_codes(
    sources = list(
      PX = px_dates, RX = rx_dates, DX = dx_dates,
      DRG = drg_dates, DISP = disp_dates, MA = ma_dates, TR = tr_dates  # TR removed
    ),
    type_name = "Chemotherapy"
  )
}
```

**Removal pattern:** Delete `tr_dates` block entirely, remove `TR = tr_dates` from sources list. Repeat for radiation (lines 277-305) and SCT (lines 341-372).

### Pattern 2: Coverage Analysis (New Script)
**What:** Pre-removal audit that quantifies overlap between TR and claims-based sources.

**When to use:** Before any source removal to prevent silent data loss.

**Example structure (R/91_treatment_source_coverage.R):**
```r
# ==============================================================================
# 91_treatment_source_coverage.R -- Treatment Source Coverage Analysis
# ==============================================================================
# Purpose: Quantify tumor registry treatment coverage before removal (Phase 76)
#
# Inputs:  PCORnet tables (TUMOR_REGISTRY_ALL + claims tables)
# Outputs: output/source_coverage_analysis.csv, output/source_coverage_analysis.xlsx
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(glue)
  library(openxlsx2)
})

source("R/00_config.R")
source("R/utils/utils_duckdb.R")

# Extract dates from TR and non-TR sources separately
for (type in c("Chemotherapy", "Radiation", "SCT")) {
  # Extract TR-only dates
  tr_dates <- extract_tr_dates_for_type(type)

  # Extract non-TR dates (all claims-based sources)
  claims_dates <- extract_claims_dates_for_type(type)

  # Categorize episodes:
  # - TR-only: dates in TR but not in claims
  # - Claims-only: dates in claims but not in TR
  # - Both: dates in both TR and claims

  # Build summary table per type
}

# Output multi-sheet xlsx: Summary + per-type detail
```

### Pattern 3: Episode Count Assertion (Defensive Validation)
**What:** Runtime assertion that halts pipeline if episode count drops unexpectedly after TR removal.

**When to use:** After modifying data extraction logic to prevent silent data loss.

**Example (R/26, after calculate_episodes_detailed()):**
```r
# SECTION 5: MAIN EXECUTION LOOP (modified for Phase 76)

# Pre-removal baseline (from coverage analysis output)
EXPECTED_EPISODE_COUNT_POST_TR_REMOVAL <- list(
  Chemotherapy = 1234,  # Update with actual values from R/91 output
  Radiation = 567,
  SCT = 89,
  Immunotherapy = 45  # No TR source, should be unchanged
)

for (type in TREATMENT_TYPES) {
  dates_df <- extract_dates_with_codes(type)
  episodes_df <- calculate_episodes_detailed(dates_df)

  # Phase 76: Validate episode count against expected post-TR-removal baseline
  if (!is.null(EXPECTED_EPISODE_COUNT_POST_TR_REMOVAL[[type]])) {
    expected <- EXPECTED_EPISODE_COUNT_POST_TR_REMOVAL[[type]]
    actual <- nrow(episodes_df)
    pct_delta <- abs(actual - expected) / expected * 100

    checkmate::assert_true(
      pct_delta <= 20,
      .var.name = glue("[R/26 ERROR] {type} episode count delta >20%"),
      add = glue("Expected ~{expected} episodes post-TR-removal, got {actual} ({round(pct_delta, 1)}% change)")
    )
  }

  # ... rest of loop
}
```

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Excel output with formatting | Manual XML/CSV assembly | openxlsx2 package | Multi-sheet workbooks with styling; established pattern in R/26, R/28, R/52; handles date formatting automatically |
| Source overlap calculation | Nested loops over patients/dates | dplyr joins + anti_join | Set operations (semi_join, anti_join) are optimized and readable; standard tidyverse pattern |
| Episode count validation | Manual if-statements with warnings | checkmate::assert_true() | Consistent error format; integrates with existing assertion framework (R/utils/utils_assertions.R) |

**Key insight:** Don't write custom source overlap logic — use dplyr set operations (semi_join for "both", anti_join for "only in X"). Don't write custom Excel styling — copy openxlsx2 patterns from R/26 lines 780-1113 (multi-sheet workbook with headers, fills, fonts).

## Common Pitfalls

### Pitfall 1: Silent Data Loss from Source Removal
**What goes wrong:** Removing TR source without pre-analysis leads to unknown episode count delta. If TR captured unique dates not in claims (e.g., older treatments before EHR era), those episodes disappear silently.

**Why it happens:** Developer assumes TR data is fully redundant with claims data without verification.

**How to avoid:** Always run coverage analysis first. Document TR-only episode counts. Add runtime assertion (>20% drop halts pipeline).

**Warning signs:** Episode counts drop unexpectedly after script modification; historical episode percentage increases (indicating loss of recent TR data).

### Pitfall 2: Incomplete TR Block Removal
**What goes wrong:** Removing TR source from `sources = list(...)` but forgetting to remove the `tr_dates <- ...` extraction block. Code runs but leaves dead code in place. Or vice versa: removing extraction block but forgetting to remove from sources list, causing NULL reference.

**Why it happens:** TR extraction blocks are 10-30 lines each. Easy to miss one of three (chemo/radiation/SCT) or leave partial block.

**How to avoid:** Use global search for "TUMOR_REGISTRY" and "TR = tr_dates" to find all occurrences. Delete entire block from `tr_dates <- NULL` through closing brace. Verify sources list no longer references TR.

**Warning signs:** lintr reports unused variables; runtime error about undefined TR object; git diff shows partial deletion.

### Pitfall 3: Broken Assertion Baseline After Future Pipeline Changes
**What goes wrong:** Hard-coded episode count baseline (e.g., `EXPECTED_EPISODE_COUNT_POST_TR_REMOVAL <- list(Chemotherapy = 1234)`) becomes stale if upstream cohort changes (new data extract, diagnosis code changes, enrollment filters).

**Why it happens:** Baseline comes from one-time coverage analysis but pipeline evolves independently.

**How to avoid:** Document assertion baseline in comments with date and cohort size. Use percentage-based thresholds (>20% drop) rather than exact counts. Consider making baseline updatable via external file (though adds complexity).

**Warning signs:** Assertion fires on every run after upstream change; manual override becomes routine.

### Pitfall 4: Coverage Analysis Uses Different Episode Logic Than Pipeline
**What goes wrong:** R/91 coverage analysis implements its own episode windowing (e.g., different gap threshold) instead of reusing `assign_episode_ids()` from R/25. Results don't match actual pipeline behavior.

**Why it happens:** Developer writes standalone analysis without checking existing episode logic.

**How to avoid:** Source R/25_treatment_durations.R for `assign_episode_ids()` and `stack_and_dedup()`. Use same 90-day window (`GAP_THRESHOLD` from R/00_config.R). Reuse existing extraction functions where possible.

**Warning signs:** Coverage analysis shows 1500 episodes but pipeline produces 1200; different median episode lengths; different patient counts.

## Code Examples

### Example 1: Coverage Analysis — Source Overlap Detection
Verified pattern from dplyr documentation + existing codebase patterns:

```r
# Source: dplyr anti_join/semi_join documentation + R/26 existing extraction pattern

# Extract dates from TR source for chemotherapy
tr_dates <- get_pcornet_table("TUMOR_REGISTRY_ALL") %>%
  select(ID, all_of(tr_chemo_cols)) %>%
  collect() %>%
  tidyr::pivot_longer(cols = all_of(tr_chemo_cols), values_to = "treatment_date") %>%
  filter(!is.na(treatment_date)) %>%
  distinct(ID, treatment_date)

# Extract dates from all non-TR sources (claims)
claims_dates <- bind_rows(
  px_dates, rx_dates, dx_dates, drg_dates, disp_dates, ma_dates
) %>%
  distinct(ID, treatment_date)

# Categorize overlap
coverage_summary <- tibble(
  treatment_type = "Chemotherapy",
  tr_only_dates = nrow(anti_join(tr_dates, claims_dates, by = c("ID", "treatment_date"))),
  claims_only_dates = nrow(anti_join(claims_dates, tr_dates, by = c("ID", "treatment_date"))),
  both_sources_dates = nrow(semi_join(tr_dates, claims_dates, by = c("ID", "treatment_date"))),
  tr_total_dates = nrow(tr_dates),
  claims_total_dates = nrow(claims_dates)
) %>%
  mutate(
    pct_tr_only = round(100 * tr_only_dates / tr_total_dates, 1),
    pct_redundant = round(100 * both_sources_dates / tr_total_dates, 1)
  )

message(glue("Chemotherapy: {coverage_summary$tr_only_dates} TR-only dates ({coverage_summary$pct_tr_only}%)"))
message(glue("             {coverage_summary$both_sources_dates} dates in both sources ({coverage_summary$pct_redundant}%)"))
```

### Example 2: TR Source Block Removal (Chemotherapy)
Before (R/26, lines 195-223):
```r
  # 7. TUMOR_REGISTRY_ALL: date evidence only — no individual code
  tr_dates <- NULL
  if (!is.null(get_pcornet_table("TUMOR_REGISTRY_ALL"))) {
    tr_chemo_cols <- intersect(
      c("CHEMO_START_DATE_SUMMARY", "DT_CHEMO"),
      colnames(get_pcornet_table("TUMOR_REGISTRY_ALL"))
    )
    if (length(tr_chemo_cols) > 0) {
      tr_data <- get_pcornet_table("TUMOR_REGISTRY_ALL") %>%
        select(ID, all_of(tr_chemo_cols)) %>%
        collect() %>%
        filter(if_any(all_of(tr_chemo_cols), ~ !is.na(.)))
      if (nrow(tr_data) > 0) {
        tr_dates <- tr_data %>%
          tidyr::pivot_longer(
            cols = all_of(tr_chemo_cols),
            names_to = "date_source",
            values_to = "treatment_date"
          ) %>%
          filter(!is.na(treatment_date)) %>%
          mutate(
            treatment_date = as.Date(treatment_date),
            triggering_code = NA_character_,
            ENCOUNTERID = NA_character_
          ) %>%
          select(ID, treatment_date, triggering_code, ENCOUNTERID)
      }
    }
  }

  stack_and_dedup_with_codes(
    sources = list(
      PX = px_dates, RX = rx_dates, DX = dx_dates,
      DRG = drg_dates, DISP = disp_dates, MA = ma_dates, TR = tr_dates
    ),
    type_name = "Chemotherapy"
  )
```

After (Phase 76):
```r
  # Phase 76: Tumor registry source removed — claims-based sources only
  # TR data accuracy 8-32% per SEER literature vs 95-100% for EHR claims
  # Pre-removal coverage analysis documented in output/source_coverage_analysis.xlsx

  stack_and_dedup_with_codes(
    sources = list(
      PX = px_dates, RX = rx_dates, DX = dx_dates,
      DRG = drg_dates, DISP = disp_dates, MA = ma_dates
    ),
    type_name = "Chemotherapy"
  )
```

**Changes:**
- Delete lines 195-223 (entire tr_dates block)
- Remove `TR = tr_dates` from sources list (line 228)
- Add comment documenting removal rationale and coverage analysis reference

**Repeat for:**
- `extract_radiation_dates_with_codes()` (R/26, lines 277-305)
- `extract_sct_dates_with_codes()` (R/26, lines 341-372)

### Example 3: Multi-Sheet Coverage Report (openxlsx2 Pattern)
```r
# Source: R/26 phase_60_audit.xlsx pattern (lines 1120-1258)

COVERAGE_XLSX <- file.path(CONFIG$output_dir, "source_coverage_analysis.xlsx")
wb <- wb_workbook()

# Sheet 1: Summary
wb$add_worksheet("Summary")
wb$add_data(sheet = "Summary", x = "Treatment Source Coverage Analysis", start_row = 1, start_col = 1)
wb$add_font(sheet = "Summary", dims = "A1", size = 16, bold = TRUE)

# Headers (row 3)
headers <- c("Treatment Type", "TR-Only Episodes", "Claims-Only Episodes", "Both Sources", "% TR-Only")
for (i in seq_along(headers)) {
  wb$add_data(sheet = "Summary", x = headers[i], start_row = 3, start_col = i)
}
wb$add_fill(sheet = "Summary", dims = "A3:E3", color = wb_color("FF374151"))
wb$add_font(sheet = "Summary", dims = "A3:E3", bold = TRUE, color = wb_color("FFFFFFFF"))

# Data rows (coverage_summary from analysis loop)
wb$add_data(sheet = "Summary", x = coverage_summary, start_row = 4, col_names = FALSE)

# Sheet 2: Chemotherapy Detail (repeat for Radiation, SCT)
wb$add_worksheet("Chemotherapy Detail")
# ... patient-level detail showing which episodes are TR-only vs both ...

wb$save(COVERAGE_XLSX)
message(glue("Coverage analysis saved: {COVERAGE_XLSX}"))
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Accept all TR treatment data | Remove TR data based on quality assessment | Phase 76 (2026-06) | Reduces data from 7→6 sources (chemo), 4→3 (radiation), 3→2 (SCT); improves accuracy at cost of potential historical coverage loss |
| Remove sources without pre-analysis | Mandatory coverage analysis before removal | Phase 76 (2026-06) | Prevents silent data loss; documents decision rationale |
| Manual episode count checks | Automated assertion with >20% threshold | Phase 76 (2026-06) | Runtime validation prevents unexpected data loss from future pipeline changes |

**Deprecated/outdated:**
- **Accepting TR data without quality assessment:** SEER/NAACCR literature documents 8-32% TR treatment accuracy vs 95-100% for claims. Modern pipelines prioritize EHR claims data.
- **Source removal without impact analysis:** Best practice now requires coverage quantification before removal (percentage TR-only, episode count delta).

## Environment Availability

> All dependencies are code/config-only (R package modifications). No external tools required.

**Skip condition met:** Phase 76 is purely R code changes with no external runtime dependencies (databases, APIs, CLI tools). All work performed within existing R environment.

## Validation Architecture

> Skipped: workflow.nyquist_validation is explicitly set to false in .planning/config.json.

## Open Questions

1. **What is the actual TR-only episode percentage?**
   - What we know: Literature suggests TR accuracy is 8-32% vs 95-100% for claims
   - What's unclear: Specific overlap in this OneFlorida+ cohort
   - Recommendation: R/91 coverage analysis will quantify; include in validation report

2. **Should historical episodes (pre-2012) trigger different assertion thresholds?**
   - What we know: TR may be primary source for pre-EHR-era treatments (before 2012)
   - What's unclear: Whether >20% threshold is appropriate for historical vs contemporary episodes
   - Recommendation: Coverage analysis should stratify by historical_flag; consider separate thresholds if historical data dominates TR-only category

3. **Should immunotherapy be included in coverage analysis?**
   - What we know: Immunotherapy extraction (R/26, lines 382-408) has no TR source — only PX and DRG
   - What's unclear: Whether to include in analysis as "zero TR coverage" baseline
   - Recommendation: Include in analysis with explicit note "No TR source (expected 0% coverage)" — provides completeness and documents design decision

## Sources

### Primary (HIGH confidence)
- R/26_treatment_episodes.R (lines 118-409) — Current treatment extraction logic with TR sources
- R/25_treatment_durations.R (episode windowing logic via assign_episode_ids())
- R/00_config.R (TREATMENT_TYPES, GAP_THRESHOLD, CONFIG paths)
- R/88_smoke_test_comprehensive.R (smoke test patterns, check() function)
- R/utils/utils_assertions.R (checkmate assertion helpers)
- openxlsx2 patterns from R/26 (lines 780-1113), R/28 (audit report structure)
- ROADMAP.md Phase 79 (diagnostic script numbering convention: R/92, R/93)

### Secondary (MEDIUM confidence)
- SEER/NAACCR documentation on tumor registry data quality (8-32% treatment accuracy cited in Phase 76 success criteria)
- dplyr documentation (anti_join, semi_join for set operations)

### Tertiary (LOW confidence)
- None — all research findings verified against codebase or official R package documentation

## Metadata

**Confidence breakdown:**
- Treatment extraction patterns: HIGH - verified from R/26 source code (lines 118-409)
- Coverage analysis approach: HIGH - dplyr set operations (anti_join/semi_join) are standard
- Assertion patterns: HIGH - checkmate is established v2.0 standard (R/utils/utils_assertions.R)
- TR data quality rationale: MEDIUM - SEER literature cited but not independently verified

**Research date:** 2026-06-02
**Valid until:** 90 days (2026-09-01) — codebase stable, no fast-moving dependencies
