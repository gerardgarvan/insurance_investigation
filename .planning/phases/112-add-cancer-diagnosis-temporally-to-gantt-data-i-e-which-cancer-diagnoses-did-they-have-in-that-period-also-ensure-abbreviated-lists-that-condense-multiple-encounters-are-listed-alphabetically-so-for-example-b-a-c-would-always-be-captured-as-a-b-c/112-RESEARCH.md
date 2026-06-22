# Phase 112: Add Cancer Diagnosis Temporally to Gantt Data + Alphabetical List Ordering - Research

**Researched:** 2026-06-22
**Domain:** R data manipulation (dplyr), temporal joins, multi-value field sorting
**Confidence:** HIGH

## Summary

Phase 112 enriches Gantt episode data with temporal cancer diagnosis context and enforces universal alphabetical ordering across all multi-value fields in the export pipeline. The phase combines two distinct but related problems: (1) capturing all cancer diagnoses occurring within a buffered date range around each treatment episode (new temporal query feature), and (2) auditing and fixing sort direction across the entire Gantt/TABLE-2 pipeline to ensure ascending alphabetical order everywhere.

The existing codebase provides strong precedents for both operations. Temporal joins with date buffers are already implemented in R/28's cancer linkage cascade (30-day backward window). Multi-value field aggregation with `paste(sort(unique(...)), collapse=",")` appears throughout R/26, R/36, and R/57. The user explicitly identified R/36 line 202 where TABLE-2's `cancer_category_names` field uses `sort(..., decreasing = TRUE)` — the ONE exception that violates the universal ascending rule.

**Primary recommendation:** Add two new diagnosis columns to Gantt export via R/28 enrichment (temporal DuckDB query with ±30-day buffer from episode boundaries), then audit all `sort()` calls in R/26/R/52/R/36 and remove `decreasing = TRUE` flags.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Capture all cancer diagnoses where DX_DATE falls within a 30-day buffer on both sides of the episode span: `(episode_start - 30 days)` through `(episode_stop + 30 days)`
- **D-02:** This extends beyond the existing R/28 linkage (which uses 30-day backward only for single-category matching) to provide a full temporal picture of what was being diagnosed around each treatment episode
- **D-03:** Add TWO new columns to Gantt export: one for comma-separated ICD codes (e.g., "C81.00,C81.10,C85.90") and one for comma-separated category names (e.g., "Hodgkin Lymphoma,Non-Hodgkin Lymphoma")
- **D-04:** Deduplicate values within each column (unique codes, unique categories per episode)
- **D-05:** Keep existing single-value `cancer_category` column alongside new temporal columns — do not replace it. Downstream consumers of the existing field are not disrupted.
- **D-06:** Audit ALL multi-value fields across the entire Gantt export pipeline (triggering_codes, drug_names, encounter_ids, and any other comma/semicolon-separated fields) and enforce alphabetical ascending sort
- **D-07:** This includes both the new temporal diagnosis columns and all pre-existing multi-value fields in R/26, R/52, and related scripts
- **D-08:** All multi-value fields sort ascending (A-Z) everywhere — no exceptions. The user's example ("b,a,c" becomes "a,b,c") is the universal rule.
- **D-09:** Fix TABLE-2 (R/36) `cancer_category_names` field which currently uses `sort(..., decreasing = TRUE)` — change to ascending to match the universal rule

### Claude's Discretion
- Column naming for the two new temporal diagnosis fields (suggested: `episode_dx_codes` and `episode_dx_categories` or similar descriptive names)
- Where in the pipeline the temporal diagnosis query is best placed (R/28 enrichment vs R/52 export-time query)
- Whether to add the new columns to both `gantt_episodes.csv` and `gantt_detail.csv` or episodes only

</user_constraints>

## Standard Stack

### Core Libraries
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| dplyr | 1.2.0+ | Data transformation | Already used throughout pipeline; group_by/summarise pattern for multi-value aggregation |
| lubridate | 1.9.3+ | Date arithmetic | Episode date range + buffer calculations: `episode_start - days(30)` |
| stringr | 1.5.1+ | String operations | `str_split()`, `str_remove()` for code normalization and list parsing |
| DuckDB | via utils_duckdb.R | Database queries | Existing DIAGNOSIS table access pattern from R/28 Section 4 |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| glue | 1.8.0 | Logging | Standard logging pattern in R/26, R/28, R/52 |
| checkmate | Latest | Assertions | Existing validation pattern in R/26 (row count preservation) |

**Installation:** Already installed in project environment (no new dependencies required)

## Architecture Patterns

### Recommended Integration Point
Add temporal diagnosis enrichment to R/28 Section 5D (after Phase 93 immunotherapy enrichment, before Section 6 RDS save). This follows the established pattern of enriching `treatment_episodes.rds` with cancer context before Gantt export.

**Why R/28 not R/52:**
- R/28 already queries DIAGNOSIS table for cancer linkage (Section 4, lines 179-186)
- Temporal diagnosis query reuses the same `dx_data` pattern (ID + ENCOUNTERID + DX + DX_DATE)
- Enrichment happens once at episode-level, not repeated for detail export
- R/52 is export-only (no DuckDB queries) — adding query logic there breaks separation of concerns

### Pattern 1: Temporal Join with Date Buffer

**What:** Join episodes to DIAGNOSIS table where DX_DATE falls within buffered episode date range
**When to use:** Capturing all diagnoses associated with a treatment episode, not just the "linked" diagnosis
**Precedent:** R/28 Section 4d (lines 220-235) — temporal fallback with 30-day backward window

**Example (adapted from R/28 pattern):**
```r
# From R/28 Section 4d (existing temporal fallback pattern)
temporal_linked <- unlinked_episodes %>%
  left_join(dx_for_unlinked, by = c("patient_id" = "ID"), relationship = "many-to-many") %>%
  filter(!is.na(DX_DATE)) %>%
  filter(DX_DATE <= episode_start) %>%          # Backward-only (existing)
  mutate(days_before = as.numeric(episode_start - DX_DATE)) %>%
  filter(days_before <= 30)

# Phase 112 adaptation: bidirectional buffer (±30 days from episode span)
temporal_dx <- episodes %>%
  left_join(dx_data, by = c("patient_id" = "ID"), relationship = "many-to-many") %>%
  filter(!is.na(DX_DATE)) %>%
  filter(
    DX_DATE >= (episode_start - days(30)) &
    DX_DATE <= (episode_stop + days(30))
  ) %>%
  filter(is_cancer_code(DX))  # Reuse existing utility from utils_cancer.R
```

### Pattern 2: Multi-Value Field Aggregation with Sort

**What:** Collapse multiple values per group into comma-separated string, alphabetically sorted, deduplicated
**When to use:** Aggregating codes, names, or IDs at episode level
**Precedent:** R/26 lines 485-487, R/36 lines 156-202, R/57 lines 209-250

**Example (from R/26 line 485, established pattern):**
```r
# Source: R/26_treatment_episodes.R lines 485-487
episodes %>%
  group_by(patient_id, episode_number) %>%
  summarise(
    triggering_codes = paste(sort(unique(na.omit(triggering_code))), collapse = ","),
    encounter_ids = paste(sort(unique(na.omit(ENCOUNTERID))), collapse = ","),
    .groups = "drop"
  )
```

**Phase 112 application:**
```r
# Temporal diagnosis aggregation (new pattern for Phase 112)
temporal_dx_agg <- temporal_dx %>%
  group_by(patient_id, episode_number, treatment_type) %>%
  summarise(
    episode_dx_codes = paste(sort(unique(DX)), collapse = ","),
    episode_dx_categories = {
      categories <- classify_codes(DX)  # Reuse R/utils/utils_cancer.R
      paste(sort(unique(categories[!is.na(categories)])), collapse = ",")
    },
    .groups = "drop"
  )
```

### Pattern 3: Sort Direction Audit

**What:** Grep all `sort()` calls in multi-value aggregation pipeline, verify ascending order
**When to use:** Before modifying sort behavior project-wide
**Precedent:** None — this is a new audit requirement

**Example audit workflow:**
```bash
# Find all sort calls in Gantt/TABLE pipeline
grep -n "sort(" R/26_treatment_episodes.R R/52_gantt_v2_export.R R/36_tableau_ready_tables.R

# Expected findings:
# R/26:485 - triggering_codes: sort(unique(...))  ✓ ascending (default)
# R/26:487 - encounter_ids: sort(unique(...))      ✓ ascending (default)
# R/26:712 - drug_names: sort(unique(...))          ✓ ascending (default)
# R/36:156 - cancer_codes: sort(unique(...))        ✓ ascending (default)
# R/36:202 - cancer_category_names: sort(..., decreasing = TRUE)  ✗ DESCENDING — needs fix
# R/36:302 - agents: sort(unique(...))              ✓ ascending (default)
```

**Fix pattern (R/36 line 202):**
```r
# BEFORE (R/36 line 202, identified by user):
paste(sort(unique(categories), decreasing = TRUE), collapse = ",")

# AFTER (Phase 112 fix):
paste(sort(unique(categories)), collapse = ",")
# Default decreasing = FALSE → ascending A-Z order
```

### Anti-Patterns to Avoid

- **Pattern:** Querying DIAGNOSIS table inside R/52 export script
  **Why it's bad:** Breaks separation of concerns; export scripts should not perform database queries
  **What to do instead:** Enrich `treatment_episodes.rds` in R/28, export pre-enriched data in R/52

- **Pattern:** Joining temporal diagnosis at detail level (one row per date+code)
  **Why it's bad:** N×M explosion — each detail row would get all episode diagnoses, multiplying row count
  **What to do instead:** Aggregate at episode level first, then join to detail via episode_number key

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Cancer code classification | Custom ICD prefix parsing | `classify_codes()` (R/utils/utils_cancer.R) | Already handles ICD-10/ICD-9 4-tier cascade with CANCER_SITE_MAP lookup |
| Cancer code detection | Regex patterns for C-codes | `is_cancer_code()` (R/utils/utils_cancer.R) | Map-based detection (not range-based) ensures gap-free coverage |
| Date arithmetic | Manual day counting | `lubridate::days()`, `interval()` | Handles leap years, DST, edge cases automatically |
| DuckDB connection | Manual dbConnect/dbDisconnect | `open_pcornet_con()`, `get_pcornet_table()` (R/utils/utils_duckdb.R) | Existing PCORnet-aware utilities with USE_DUCKDB flag |

**Key insight:** The existing R/28 cancer linkage infrastructure (DIAGNOSIS table query, cancer classification utilities, temporal join patterns) provides 90% of what Phase 112 needs — don't reimplement database access or cancer code mapping.

## Common Pitfalls

### Pitfall 1: Date Buffer Direction Confusion

**What goes wrong:** Using backward-only window (like R/28's 30-day fallback) instead of bidirectional ±30 days from episode span
**Why it happens:** R/28 Section 4d uses `DX_DATE <= episode_start` (backward-only) for linkage — easy to copy this pattern
**How to avoid:** Buffer is from episode START minus 30 to episode STOP plus 30 — two distinct date calculations
**Warning signs:** Diagnoses dated after treatment start are missing from temporal columns

**Code example:**
```r
# WRONG (backward-only like R/28 linkage):
filter(DX_DATE <= episode_start & DX_DATE >= (episode_start - days(30)))

# CORRECT (bidirectional from episode span per D-01):
filter(
  DX_DATE >= (episode_start - days(30)) &
  DX_DATE <= (episode_stop + days(30))
)
```

### Pitfall 2: Descending Sort Discovery Blindness

**What goes wrong:** Grep finds R/36 line 202's `decreasing = TRUE`, but misses other instances in R/57, R/56, or custom scripts
**Why it happens:** Focused search on Gantt pipeline (R/26/R/52/R/36) skips broader codebase
**How to avoid:** Extend grep to all R/*.R files, check both `decreasing = TRUE` and `desc()` patterns
**Warning signs:** User reports "some fields still sort backward" after claimed fix

**Comprehensive audit command:**
```bash
# Search project-wide for descending sort patterns
grep -rn "decreasing = TRUE" R/
grep -rn "desc()" R/ | grep -v "# description"  # Exclude comments
```

### Pitfall 3: Row Count Explosion from Many-to-Many Join

**What goes wrong:** Joining episodes (8,000 rows) to DIAGNOSIS (2M rows) without proper filtering → 500K+ row intermediate table
**Why it happens:** Forgetting to filter to patient subset BEFORE joining (`dx_data` query should filter `ID %in% episode_patients`)
**How to avoid:** Follow R/28 Section 4d pattern (lines 215-217) — filter DIAGNOSIS table to episode patients first
**Warning signs:** Memory usage spike, 10x expected join output rows

**Code example:**
```r
# WRONG (join all episodes to all diagnoses — memory explosion):
episodes %>%
  left_join(get_pcornet_table("DIAGNOSIS") %>% collect(),
            by = c("patient_id" = "ID"))

# CORRECT (filter DIAGNOSIS to episode patients first):
episode_patients <- unique(episodes$patient_id)
dx_data <- get_pcornet_table("DIAGNOSIS") %>%
  filter(ID %in% !!episode_patients) %>%  # !! unquotes local vector
  select(ID, DX, DX_DATE) %>%
  collect()

episodes %>%
  left_join(dx_data, by = c("patient_id" = "ID"))
```

### Pitfall 4: Forgetting NA Removal in Multi-Value Collapse

**What goes wrong:** `paste(sort(unique(categories)), collapse = ",")` produces literal "NA" strings in output ("Hodgkin Lymphoma,NA,Breast")
**Why it happens:** `classify_codes()` returns NA for unmapped codes; `unique()` preserves NA; `paste()` converts NA to string "NA"
**How to avoid:** Wrap with `na.omit()` or filter `[!is.na(...)]` before `paste()`
**Warning signs:** Excel users report "NA" appearing as a cancer category name in comma-separated lists

**Code example:**
```r
# WRONG (NA becomes literal string "NA"):
paste(sort(unique(categories)), collapse = ",")

# CORRECT (filter NAs before collapse):
paste(sort(unique(categories[!is.na(categories)])), collapse = ",")
# OR:
paste(sort(unique(na.omit(categories))), collapse = ",")
```

## Code Examples

Verified patterns from official sources:

### Temporal Diagnosis Query (New for Phase 112, adapted from R/28)

```r
# Source: Adapted from R/28_episode_classification.R Section 4d (lines 215-235)
# Pattern: Temporal join with date filter, cancer code detection, aggregation

# Step 1: Get episode patient list and query DIAGNOSIS table (R/28 pattern)
episode_patients <- unique(episodes$patient_id)
dx_data <- get_pcornet_table("DIAGNOSIS") %>%
  filter(ID %in% !!episode_patients) %>%
  select(ID, DX, DX_DATE) %>%
  collect() %>%
  filter(is_cancer_code(DX))  # Reuse shared utility

# Step 2: Temporal join with ±30-day buffer from episode span (D-01, D-02)
temporal_dx <- episodes %>%
  select(patient_id, treatment_type, episode_number, episode_start, episode_stop) %>%
  left_join(dx_data, by = c("patient_id" = "ID"), relationship = "many-to-many") %>%
  filter(!is.na(DX_DATE)) %>%
  filter(
    DX_DATE >= (episode_start - days(30)) &
    DX_DATE <= (episode_stop + days(30))
  )

# Step 3: Aggregate to episode level (D-03, D-04)
temporal_dx_agg <- temporal_dx %>%
  group_by(patient_id, treatment_type, episode_number) %>%
  summarise(
    episode_dx_codes = paste(sort(unique(DX)), collapse = ","),
    episode_dx_categories = {
      cats <- classify_codes(DX)
      paste(sort(unique(cats[!is.na(cats)])), collapse = ",")
    },
    .groups = "drop"
  )

# Step 4: Join back to episodes (preserve row count, D-05)
pre_join_count <- nrow(episodes)
episodes <- episodes %>%
  left_join(temporal_dx_agg, by = c("patient_id", "treatment_type", "episode_number"))

# Validate row count preserved (R/28 pattern, lines 696-697)
stopifnot(nrow(episodes) == pre_join_count)
```

### Multi-Value Sort Fix (R/36 line 202)

```r
# Source: R/36_tableau_ready_tables.R line 202 (BEFORE)
# User explicitly identified this as the ONE place with descending sort

# BEFORE (D-09 violation):
map_cancer_codes_to_categories <- function(cancer_codes_str) {
  # ... classification logic ...
  paste(sort(unique(categories), decreasing = TRUE), collapse = ",")
  #                                ^^^^^^^^^^^^^^^^^^^^ REMOVE THIS
}

# AFTER (D-08 compliance):
map_cancer_codes_to_categories <- function(cancer_codes_str) {
  # ... classification logic ...
  paste(sort(unique(categories)), collapse = ",")  # Default ascending A-Z
}
```

### Existing Multi-Value Sort Pattern (Already Correct)

```r
# Source: R/26_treatment_episodes.R lines 485-487
# This pattern is ALREADY correct — no changes needed

group_by(patient_id, episode_number) %>%
summarise(
  triggering_codes = paste(sort(unique(na.omit(triggering_code))), collapse = ","),
  encounter_ids = paste(sort(unique(na.omit(ENCOUNTERID))), collapse = ","),
  .groups = "drop"
)
# ✓ sort() with no arguments → default decreasing = FALSE → ascending A-Z
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Descending category sort (R/36) | Universal ascending sort | Phase 112 (2026-06-22) | Consistent alphabetical order across all multi-value fields; easier Excel filtering |
| Single-diagnosis linkage (R/28) | Temporal diagnosis context (±30 buffer) | Phase 112 (2026-06-22) | Fuller clinical picture of co-occurring diagnoses during treatment episodes |

**Deprecated/outdated:**
- None identified — Phase 112 is additive (new columns) + corrective (sort direction fix)

## Open Questions

1. **Column names for temporal diagnosis fields**
   - What we know: Need two columns (DX codes + category names), comma-separated, deduplicated
   - What's unclear: Preferred naming convention (e.g., `episode_dx_codes` vs `temporal_dx_codes` vs `dx_codes_buffered`)
   - Recommendation: Use `episode_dx_codes` and `episode_dx_categories` — consistent with existing `episode_start`, `episode_stop` naming in R/26

2. **Detail-level temporal diagnosis columns**
   - What we know: User constraint D-05 says keep existing `cancer_category` column, add new ones alongside
   - What's unclear: Whether `gantt_detail.csv` (one row per date+code) should also get temporal diagnosis columns, or episodes-only
   - Recommendation: Episodes-only — temporal context is an episode-level property (date buffer spans the episode, not individual treatment dates)

3. **R/57 (drug_grouping_instances.R) sort direction**
   - What we know: R/57 is broader pipeline (not just Gantt), has own `sort(..., decreasing = TRUE)` at line 250
   - What's unclear: Does D-06 "entire Gantt export pipeline" include R/57, or only R/26/R/52/R/36?
   - Recommendation: Audit R/57 but treat as separate from Gantt pipeline — only fix if it feeds Gantt/TABLE outputs

## Environment Availability

**Step 2.6: SKIPPED** (no external dependencies identified — all operations use existing R packages already installed in project environment)

## Validation Architecture

**SKIPPED** (workflow.nyquist_validation is explicitly set to false in .planning/config.json)

## Sources

### Primary (HIGH confidence)
- R/28_episode_classification.R (Section 4: cancer linkage cascade with temporal fallback pattern, lines 179-282)
- R/26_treatment_episodes.R (multi-value aggregation pattern with `sort(unique(...))`, lines 485-487, 712)
- R/52_gantt_v2_export.R (Gantt export schema, Phase 99 consolidation decisions D-01 through D-15)
- R/36_tableau_ready_tables.R (TABLE-2 date-grain collapse, `sort(..., decreasing = TRUE)` at line 202)
- R/00_config.R (CANCER_SITE_MAP, ICD9_CANCER_SITE_MAP lookup tables)
- R/utils/utils_cancer.R (classify_codes(), is_cancer_code() shared utilities)
- 112-CONTEXT.md (Phase 112 user decisions D-01 through D-09, canonical file references)

### Secondary (MEDIUM confidence)
- R/57_drug_grouping_instances.R (broader multi-value sort patterns outside Gantt pipeline)
- R/56_new_tables_from_groupings.R (additional multi-value aggregation examples)

### Tertiary (LOW confidence)
- None — all research findings verified against project source code

## Metadata

**Confidence breakdown:**
- Temporal join pattern: HIGH (directly adapted from existing R/28 Section 4d, lines 220-235)
- Multi-value sort pattern: HIGH (established in R/26, R/36, R/57 with 15+ instances)
- Sort direction fix: HIGH (user explicitly identified R/36 line 202 as the exception)
- Integration point (R/28 vs R/52): HIGH (R/28 already queries DIAGNOSIS table, R/52 is export-only)

**Research date:** 2026-06-22
**Valid until:** 2026-08-22 (60 days — stable R codebase with infrequent API changes)
