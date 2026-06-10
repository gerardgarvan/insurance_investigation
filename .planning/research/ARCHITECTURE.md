# Architecture Patterns: data.table Integration

**Domain:** PCORnet payer variable investigation R pipeline
**Researched:** 2026-06-10
**Confidence:** HIGH

## Integration Context

This is a SUBSEQUENT MILESTONE adding data.table performance optimization to an existing 77-script R pipeline with decade-based organization, DuckDB backend, and centralized configuration architecture.

**Existing architecture:**
- 77 numbered R scripts (R/00_config.R, R/01-R/14 cohort pipeline, R/20-R/29 treatment episodes, R/33-R/60 payer analysis, R/51-R/59 Gantt/cancer, R/88 smoke test)
- 11 utility modules in R/utils/ (utils_payer.R, utils_cancer.R, utils_duckdb.R, utils_dates.R, utils_xlsx_lookups.R, etc.)
- Centralized configuration in R/00_config.R holding 6 major lookup tables as named character vectors (AMC_PAYER_LOOKUP ~65 entries, DRUG_GROUPINGS ~454 entries, CODE_SUBCATEGORY_MAP ~347 entries, CANCER_SITE_MAP ~324 entries, ICD9_CANCER_SITE_MAP, DEATH_CAUSE_MAP)
- DuckDB backend with materialize() pattern: `get_pcornet_table("ENCOUNTER") %>% materialize()` collects lazy DuckDB queries into in-memory tibbles for dplyr processing
- Payer classification via classify_payer_tier() in utils_payer.R using named vector lookups (AMC_PAYER_LOOKUP[effective_payer])
- Heavy group_by/summarise operations in R/60 (same-day payer resolution), R/28 (episode classification)

**Performance bottleneck:** Named vector lookups scale linearly with ENCOUNTER table size (millions of rows). AMC_PAYER_LOOKUP[code] in vectorized mutate() requires per-row R-level indexing. Heavy group_by operations on large tables hit dplyr's single-threaded aggregation limits.

**Goal:** Replace named vector lookups with data.table keyed joins (10-50x faster) and migrate hot-path group_by/summarise to data.table syntax (radix sorting + parallel aggregation).

## Recommended Architecture

### Integration Pattern: Convert at Boundaries, Preserve Internals

**DO NOT** rewrite the entire pipeline in data.table syntax. The "named predicate" requirement (has_*, with_*, exclude_* functions for cohort filtering) and readability mandate conflict with data.table's DT[i, j, by] syntax.

**INSTEAD:** Use data.table for:
1. **Lookup table storage** — Convert R/00_config.R named vectors to keyed data.tables
2. **Hot-path joins** — Replace named vector [ indexing with data.table joins
3. **Heavy aggregations** — Migrate specific group_by/summarise blocks to data.table where profiling shows bottlenecks

**Preserve dplyr/tibble** for:
- Cohort filter chain (R/03, R/04, R/14) — readability is critical
- Low-frequency scripts (R/45-R/59 cancer summaries) — optimization not needed
- Utility functions without table operations (utils_dates.R, utils_icd.R) — no data.table benefit

### Component Boundaries

| Component | Current Implementation | data.table Integration | Rationale |
|-----------|------------------------|------------------------|-----------|
| **Lookup tables** | Named vectors in R/00_config.R | data.tables with setkey() | Direct keyed join replaces vectorized [ indexing |
| **classify_payer_tier()** | dplyr + named vector lookup | Hybrid: data.table join, return tibble | High-frequency function (called on full ENCOUNTER table) |
| **DuckDB → local** | materialize() → tibble | materialize() → setDT() conversion | Convert once at boundary, not per-operation |
| **Hot-path aggregations** | dplyr group_by/summarise | data.table [, .(col = expr), by = .(key)] | R/60 same-day resolution, R/28 episode grouping |
| **Cohort filter chain** | dplyr filter/mutate | NO CHANGE (keep dplyr) | Readability requirement overrides performance |
| **Utility outputs** | tibble return values | Return tibble (setDF if needed) | Downstream scripts expect tibble/data.frame |

## New Components

### 1. utils_dt.R — data.table Integration Utilities

**Location:** R/utils/utils_dt.R

**Purpose:** Centralize data.table conversion helpers and lookup table access.

**Functions:**
- ensure_dt(df): Lazy conversion (only setDT if not already data.table)
- to_tibble_safe(dt): Safe back-conversion (data.table → tibble)
- get_lookup_dt(lookup_name): Returns LOOKUP_TABLES_DT[[lookup_name]]

**Why separate from utils_payer.R:** utils_payer.R is sourced by 20+ scripts. New utils_dt.R is sourced only by scripts that need data.table operations.

### 2. Keyed Lookup Tables in R/00_config.R

**Add after named vector definitions:**

```r
# data.table versions for optimized joins (v3.0+)
if (requireNamespace("data.table", quietly = TRUE)) {
  library(data.table)

  LOOKUP_TABLES_DT <- list(
    AMC_PAYER_LOOKUP = data.table(
      code = names(AMC_PAYER_LOOKUP),
      category = unname(AMC_PAYER_LOOKUP),
      key = "code"
    ),

    DRUG_GROUPINGS = data.table(
      code = names(DRUG_GROUPINGS),
      treatment_type = unname(DRUG_GROUPINGS),
      key = "code"
    ),

    CODE_SUBCATEGORY_MAP = data.table(
      code = names(CODE_SUBCATEGORY_MAP),
      subcategory = unname(CODE_SUBCATEGORY_MAP),
      key = "code"
    ),

    CANCER_SITE_MAP = data.table(
      prefix = names(CANCER_SITE_MAP),
      cancer_category = unname(CANCER_SITE_MAP),
      key = "prefix"
    )
  )

  message(paste0("Created ", length(LOOKUP_TABLES_DT), " keyed lookup tables"))
} else {
  LOOKUP_TABLES_DT <- NULL
  message("data.table not installed; lookup tables remain named vectors")
}
```

**Why keep named vectors:** Backward compatibility for gradual migration.

**Why conditional creation:** data.table is a new dependency. If not installed, pipeline falls back to named vector mode.

### 3. classify_payer_tier_dt() — data.table Variant

**Location:** R/utils/utils_payer.R (add alongside existing classify_payer_tier)

**Signature:**
```r
classify_payer_tier_dt <- function(dt, include_dual = TRUE, flm_override = FALSE, return_tibble = FALSE)
```

**Implementation uses:**
- Keyed join with LOOKUP_TABLES_DT$AMC_PAYER_LOOKUP
- fcase() for conditional logic (faster than case_when)
- In-place mutation with := operator
- Optional tibble return for downstream compatibility

**Why both versions:** classify_payer_tier() is called from 10+ scripts. Phased migration allows testing data.table version before updating all call sites.

## Integration Points

### 1. R/00_config.R → Lookup Table Definitions

**Action:** Add LOOKUP_TABLES_DT list after existing named vector definitions.

**Dependencies:** data.table package installed.

**Backward compatibility:** Named vectors remain unchanged. Scripts not using data.table continue working.

**Risk:** If data.table not installed, LOOKUP_TABLES_DT is NULL. Mitigation: Add defensive checks in utils_dt.R.

### 2. R/utils/utils_payer.R → classify_payer_tier_dt()

**Action:** Add new function alongside existing classify_payer_tier().

**Call sites to update:**
- R/60_tiered_same_day_payer.R (Section 2)
- R/02_harmonize_payer.R (if profiling shows bottleneck)
- R/11_treatment_payer.R (if profiling shows bottleneck)

**Backward compatibility:** Existing classify_payer_tier() unchanged. Scripts can migrate individually.

### 3. R/60_tiered_same_day_payer.R → Hot-Path Migration

**Action:** Replace Section 4 group_by/summarise with data.table aggregation.

**Current bottleneck:** group_by(ID, admit_date_parsed) %>% summarise() on 2M+ encounter rows.

**Migration pattern:**
```r
# Replace this:
resolved_detail <- enc %>%
  group_by(ID, admit_date_parsed) %>%
  summarise(n_encounters = n(), ...)

# With this:
enc_dt <- setDT(enc)
resolved_detail_dt <- enc_dt[, .(n_encounters = .N, ...), by = .(ID, admit_date_parsed)]
resolved_detail <- as_tibble(setDF(resolved_detail_dt))
```

**Expected speedup:** 5-20x on same-day resolution.

**Output compatibility:** CSV outputs must match existing format exactly.

### 4. R/28_episode_classification.R → Lookup Optimization

**Action:** Replace DRUG_GROUPINGS[code] and CODE_SUBCATEGORY_MAP[code] lookups with keyed joins.

**Current pattern:**
```r
episodes <- episodes %>%
  mutate(drug_group = DRUG_GROUPINGS[triggering_code])
```

**Optimized pattern:**
```r
episodes_dt <- setDT(episodes)
episodes_dt[LOOKUP_TABLES_DT$DRUG_GROUPINGS, on = .(triggering_code = code), drug_group := i.treatment_type]
episodes <- setDF(episodes_dt)
```

**Expected speedup:** 2-5x on code lookups.

**Output compatibility:** treatment_episodes.rds structure must match existing schema (22 columns, same order).

## Data Flow Changes

### Before (All dplyr)

```
DuckDB → materialize() → tibble → classify_payer_tier() [AMC_PAYER_LOOKUP[code]]
  → tibble → group_by/summarise → tibble → write_csv()
```

### After (data.table Hot Path)

```
DuckDB → materialize() → tibble → setDT() → data.table
  → classify_payer_tier_dt() [keyed join] → data.table
  → [, .(col = expr), by = .(key)] → data.table
  → setDF() → tibble → write_csv()
```

**Key change:** Single conversion at start (tibble → data.table), single conversion at end (data.table → tibble). Minimizes boundary crossings.

## Suggested Build Order

### Phase 95: Infrastructure Setup

**Goal:** Add data.table infrastructure without changing behavior.

**Tasks:**
1. Add data.table to renv.lock
2. Create R/utils/utils_dt.R with conversion helpers
3. Add LOOKUP_TABLES_DT to R/00_config.R
4. Test: All existing scripts run unchanged

**Validation:** Smoke test Section 0, verify LOOKUP_TABLES_DT structure.

**Risk:** LOW (additive changes only)

### Phase 96: classify_payer_tier_dt() Implementation

**Goal:** Create data.table variant with correctness validation.

**Tasks:**
1. Implement classify_payer_tier_dt() in R/utils/utils_payer.R
2. Add unit test comparing both versions on synthetic data
3. Add smoke test section

**Validation:** Unit test passes on 1000-row synthetic table.

**Risk:** MEDIUM (complex logic, but existing function unchanged as fallback)

### Phase 97: R/60 Hot-Path Migration

**Goal:** Migrate R/60 to data.table, validate output parity.

**Tasks:**
1. Migrate group_by/summarise to data.table syntax
2. Run both versions, diff CSV outputs
3. Benchmark runtime before/after

**Validation:** CSV diff shows zero changes, speedup logged.

**Risk:** MEDIUM (complex aggregation logic)

### Phase 98: R/28 Lookup Optimization

**Goal:** Replace named vector lookups with keyed joins.

**Tasks:**
1. Migrate DRUG_GROUPINGS[code] → keyed join
2. Migrate CODE_SUBCATEGORY_MAP[code] → keyed join
3. Validate treatment_episodes.rds structure unchanged

**Validation:** Smoke test Section 15 passes.

**Risk:** LOW (isolated lookups)

## Modified vs New Components

### New Components

| Component | Path | Purpose |
|-----------|------|---------|
| utils_dt.R | R/utils/utils_dt.R | data.table conversion helpers |
| LOOKUP_TABLES_DT | R/00_config.R (new list) | Keyed lookup tables |
| classify_payer_tier_dt() | R/utils/utils_payer.R (new function) | data.table payer classification |

### Modified Components

| Component | Path | Modification | Backward Compatible? |
|-----------|------|--------------|----------------------|
| R/00_config.R | R/00_config.R | Add LOOKUP_TABLES_DT list | YES |
| R/60_tiered_same_day_payer.R | R/60_tiered_same_day_payer.R | Replace dplyr group_by | YES |
| R/28_episode_classification.R | R/28_episode_classification.R | Replace named vector lookups | YES |
| utils_payer.R | R/utils/utils_payer.R | Add classify_payer_tier_dt() | YES |

## Anti-Patterns to Avoid

### 1. Don't Rewrite the Cohort Filter Chain in data.table

**Bad:** Opaque data.table syntax in cohort filtering
**Good:** Keep named predicate dplyr syntax
**Why:** Readability requirement is non-negotiable for clinical logic

### 2. Don't Convert Between Tibble and data.table Repeatedly

**Bad:** Per-operation conversion
**Good:** Single conversion at start and end
**Why:** setDT() and setDF() are in-place, but as_tibble() copies data

### 3. Don't Use data.table := in Piped Code

**Bad:** Mixing := with %>%
**Good:** data.table chaining with [] or separate operations
**Why:** data.table := modifies by reference; piping creates copies

### 4. Don't Assume Keyed Join Handles NAs Like Named Vector Indexing

**Bad:** Assume identical NA behavior
**Good:** Validate NA behavior, add explicit NA handling
**Why:** Named vector [ indexing propagates NAs with warnings; keyed joins have different semantics

### 5. Don't Skip Output Parity Validation

**Bad:** Deploy without testing
**Good:** Run both versions, diff outputs
**Why:** Subtle differences in aggregation order or NA handling cause silent regressions

## Sources

- **data.table documentation:** https://rdatatable.gitlab.io/data.table/
- **data.table vs dplyr benchmarks:** https://h2oai.github.io/db-benchmark/
- **R/00_config.R:** Existing lookup table definitions (3443 lines)
- **R/60_tiered_same_day_payer.R:** Current hot-path implementation
- **R/utils/utils_payer.R:** classify_payer_tier() current implementation
- **R/utils/utils_duckdb.R:** materialize() pattern

**Confidence:** HIGH (data.table is mature, well-documented; integration pattern follows established boundary-conversion approach; existing architecture supports gradual migration)
