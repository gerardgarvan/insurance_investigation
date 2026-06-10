# Phase 96: classify_payer_tier_dt() Implementation - Research

**Researched:** 2026-06-10
**Domain:** data.table payer classification with keyed joins and reference semantics
**Confidence:** HIGH

## Summary

Phase 96 creates a data.table variant of the most-called payer utility function (`classify_payer_tier()`) using keyed joins against `LOOKUP_TABLES_DT` and `fcase()` conditional logic. The function must produce byte-for-byte identical output to the existing dplyr version while operating on data.table objects internally. This is a pure implementation phase — no callers are modified, no existing behavior changes. Success hinges on correct reference semantics handling (defensive `copy()` at entry to prevent input mutation) and robust validation proving output parity on production data.

The existing dplyr function has a well-defined 177-line implementation with clear logic flow: effective_payer resolution (primary→secondary→NA cascade), AMC 8-category mapping (direct lookup + prefix fallback), tier assignment, special code overrides (93/14, FLM source), dual-eligible flag computation, and tier_rank assignment. The data.table variant replicates this chain using `fcase()` (fast vectorized CASE WHEN), keyed joins on `LOOKUP_TABLES_DT$AMC_PAYER_LOOKUP` and `LOOKUP_TABLES_DT$TIER_MAPPING`, and explicit `as.character()` coercion for factor inputs to prevent NA matches.

**Primary recommendation:** Use `fcase()` for all conditional logic (faster and cleaner than nested `fifelse()` for 3+ branches), perform keyed joins with `X[Y, on=.(key=i.key), nomatch=NA]` syntax, wrap input in `copy()` at function entry to prevent reference-based mutation, return tibble via `to_tibble_safe()` for downstream dplyr pipeline compatibility, and validate with standalone script comparing all output columns row-by-row on ENCOUNTER fixture data.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Place `classify_payer_tier_dt()` in `R/utils/utils_payer.R` alongside the existing `classify_payer_tier()`. Both versions of the same function in one file for easy side-by-side comparison. Callers already source this file via R/00_config.R auto-sourcing.
- **D-02:** Defer caller migration to their own phases. Phase 96 only creates and validates the function. R/60 switches in Phase 97, R/61/R/62 switch in Phase 98. No existing script behavior changes in Phase 96.
- **D-03:** Create a standalone validation script `R/96_validate_payer_dt.R` (following the Phase 95 pattern of R/95_validate_dt_infrastructure.R). Runs both classify_payer_tier() and classify_payer_tier_dt() on ENCOUNTER data, compares all output columns row-by-row, logs pass/fail. Can run on HiPerGator production data.

### Claude's Discretion
- **D-04:** Return type decision: tibble vs data.table based on actual caller patterns
- Internal implementation details: fcase() vs fifelse(), join syntax, copy() placement
- API signature: whether to match classify_payer_tier(df, include_dual, flm_override) exactly or adjust parameter names
- Validation script structure and specific checks within R/96

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| PAYER-01 | classify_payer_tier_dt() function using keyed joins and fcase() logic alongside existing dplyr version | data.table 1.18.4 keyed join syntax (X[Y] with on= argument), fcase() for multi-branch conditionals, LOOKUP_TABLES_DT infrastructure from Phase 95 |
| PAYER-02 | Output parity between classify_payer_tier() and classify_payer_tier_dt() validated on fixture data | Validation pattern from R/95_validate_dt_infrastructure.R (numbered checks with pass/fail messaging), all_equal() for tibble comparison, row-by-row column comparison |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| data.table | 1.18.4+ | Fast keyed joins and conditional logic | 10-50x faster than dplyr for large datasets; in-memory modification via reference semantics; keyed joins are O(log n) |
| dplyr | 1.2.0+ | Baseline comparison and tibble operations | Already in project stack; classify_payer_tier() uses case_when(), mutate() |
| tibble | 3.2.1+ | Modern data frame for return values | Downstream callers (R/60, R/61, R/62) expect tibble inputs; already in tidyverse |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| glue | 1.8.0 | Error message formatting | Already used in utils_dt.R for defensive error messages |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| fcase() | Nested fifelse() | fcase() is cleaner for 3+ branches; fifelse() only for binary decisions |
| fcase() | case_when() (dplyr) | case_when() is slower, incompatible with data.table's in-place syntax |
| Keyed joins | Named vector lookup | Named vectors (AMC_PAYER_LOOKUP[code]) are simpler but don't scale; keyed joins are O(log n) vs O(1) but handle missing values better |
| Return tibble | Return data.table | Tibble maintains compatibility with R/60, R/61, R/62 which use dplyr pipelines |

## Architecture Patterns

### Recommended Function Structure
```r
classify_payer_tier_dt <- function(df, include_dual = TRUE, flm_override = FALSE) {
  # 1. Defensive copy (prevent reference mutation of input)
  dt <- copy(ensure_dt(df, name = "input", script_name = "classify_payer_tier_dt"))

  # 2. Explicit character coercion (factors cause NA matches in keyed joins)
  dt[, `:=`(
    PAYER_TYPE_PRIMARY = as.character(PAYER_TYPE_PRIMARY),
    PAYER_TYPE_SECONDARY = as.character(PAYER_TYPE_SECONDARY),
    SOURCE = as.character(SOURCE)
  )]

  # 3. Effective payer resolution (fcase for 3+ branches)
  dt[, effective_payer := fcase(
    !is.na(PAYER_TYPE_PRIMARY) & nchar(trimws(PAYER_TYPE_PRIMARY)) > 0 &
      !PAYER_TYPE_PRIMARY %in% PAYER_MAPPING$sentinel_values,
      PAYER_TYPE_PRIMARY,
    !is.na(PAYER_TYPE_SECONDARY) & nchar(trimws(PAYER_TYPE_SECONDARY)) > 0 &
      !PAYER_TYPE_SECONDARY %in% PAYER_MAPPING$sentinel_values,
      PAYER_TYPE_SECONDARY,
    default = NA_character_
  )]

  # 4. Keyed join for AMC 8-category mapping
  amc_lookup <- get_lookup_dt("AMC_PAYER_LOOKUP")
  dt[amc_lookup, on = .(effective_payer = code), payer_category := i.payer_category]

  # 5. Prefix fallback for unmapped codes
  dt[is.na(payer_category) & !is.na(effective_payer), payer_category := fcase(
    startsWith(effective_payer, "1"), "Medicare",
    startsWith(effective_payer, "2"), "Medicaid",
    # ... (all 9 prefix branches)
    default = "Other"
  )]

  # 6. Missing fallback
  dt[is.na(effective_payer), payer_category := "Missing"]

  # 7. Tier assignment, special code overrides, tier_rank join
  # 8. Conditional FLM override (if flm_override == TRUE)
  # 9. Conditional dual_eligible flag (if include_dual == TRUE)

  # 10. Return tibble for dplyr pipeline compatibility
  to_tibble_safe(dt, name = "result", script_name = "classify_payer_tier_dt")
}
```

### Pattern 1: Reference Semantics Defense
**What:** Wrap input in `copy()` to create a deep copy before any reference-based modifications

**When to use:** All functions accepting data.table inputs that will be modified via `:=` operator

**Why:** data.table's reference semantics mean `dt[, x := y]` modifies the original object in place. If a caller passes `ENCOUNTER` to `classify_payer_tier_dt()`, and the function modifies it by reference, the caller's `ENCOUNTER` object is mutated. This violates R's typical copy-on-write semantics and causes unexpected side effects.

**Example:**
```r
# Source: Official data.table reference semantics vignette
# https://cran.r-project.org/web/packages/data.table/vignettes/datatable-reference-semantics.html

# BAD: Mutates input
classify_payer_tier_dt <- function(df) {
  dt <- ensure_dt(df)  # Converts to data.table but doesn't copy
  dt[, tier := "Medicaid"]  # MUTATES df in caller's environment!
  dt
}

# GOOD: Defensive copy
classify_payer_tier_dt <- function(df) {
  dt <- copy(ensure_dt(df))  # Deep copy before modification
  dt[, tier := "Medicaid"]  # Only mutates local dt, not caller's df
  dt
}
```

### Pattern 2: Keyed Join Syntax
**What:** Use `X[Y, on=.(key=i.key), j, nomatch=NA]` for explicit column matching with `i.` prefix for right-hand table columns

**When to use:** Lookup table joins where key columns have different names (e.g., `effective_payer` in left table joins to `code` in right table)

**Why:** Keyed joins require matching key column order. The `on=` argument allows explicit column name mapping. The `i.` prefix disambiguates columns from the right-hand table (Y). Modern best practice prefers explicit `on=` over implicit key matching.

**Example:**
```r
# Source: Official data.table joins vignette
# https://cran.r-project.org/web/packages/data.table/vignettes/datatable-joins.html

# Keyed join with column name mismatch
dt[get_lookup_dt("AMC_PAYER_LOOKUP"),
   on = .(effective_payer = code),   # Left key = right key
   payer_category := i.payer_category,  # i. prefix for right table column
   nomatch = NA]  # Unmatched rows get NA (default = 0 drops them)
```

### Pattern 3: fcase() for Multi-Branch Conditionals
**What:** Use `fcase()` for 3+ conditional branches instead of nested `fifelse()` calls

**When to use:** Effective_payer resolution (3 branches: primary valid → secondary valid → NA), prefix fallback (9 branches for digits 1-9), tier assignment via CODE_TO_TIER equivalent

**Why:** `fcase()` is a fast vectorized CASE WHEN implementation. Conceptually a nested version of `fifelse()` but with smarter evaluation and cleaner syntax for multiple conditions.

**Example:**
```r
# Source: Official data.table fcase documentation
# https://rdatatable.gitlab.io/data.table/reference/fcase.html

# Nested fifelse (AVOID for 3+ branches)
dt[, category := fifelse(
  condition1, value1,
  fifelse(condition2, value2,
          fifelse(condition3, value3, default))
)]

# fcase (PREFER for 3+ branches)
dt[, category := fcase(
  condition1, value1,
  condition2, value2,
  condition3, value3,
  default = default_value
)]
```

### Pattern 4: Explicit as.character() for Factor Inputs
**What:** Coerce all payer code columns to character at function entry with `as.character()`

**When to use:** Before any keyed joins or string operations (startsWith, %in%, etc.)

**Why:** PCORnet data may load payer codes as factors (especially if read with default vroom type guessing). Factor-to-character joins fail silently: keyed lookup returns NA because factor levels don't match character keys. Explicit coercion at entry prevents this pitfall.

**Example:**
```r
# Source: General R factor/character conversion best practices
# https://www.geeksforgeeks.org/r-language/how-to-convert-factor-to-character-in-r/

# BEFORE join: coerce factors to character
dt[, `:=`(
  PAYER_TYPE_PRIMARY = as.character(PAYER_TYPE_PRIMARY),
  PAYER_TYPE_SECONDARY = as.character(PAYER_TYPE_SECONDARY),
  SOURCE = as.character(SOURCE)
)]

# THEN: joins and string operations work correctly
dt[, effective_payer := fcase(
  !is.na(PAYER_TYPE_PRIMARY) & !PAYER_TYPE_PRIMARY %in% sentinels,
    PAYER_TYPE_PRIMARY,
  # ... (won't fail on factor input)
)]
```

### Anti-Patterns to Avoid

- **Don't skip copy() at function entry:** Reference semantics will mutate caller's input — violates R conventions and breaks test isolation
- **Don't use setDT() instead of as.data.table():** setDT() modifies in place (same mutation problem as missing copy())
- **Don't use implicit key matching without on= argument:** Hard to read, breaks when key column names differ, deprecated in modern data.table style
- **Don't nest fifelse() for 3+ branches:** Use fcase() instead — cleaner syntax, same performance
- **Don't assume character input:** PCORnet CSVs may load as factors; always coerce with as.character() before joins

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Multi-branch conditional logic | Nested ifelse() or case_when() in data.table context | fcase() | fcase() is vectorized, type-safe, and optimized for data.table's column references |
| Lookup table joins | Named vector subsetting (AMC_PAYER_LOOKUP[code]) | Keyed joins (X[Y, on=]) | Keyed joins handle missing values explicitly (nomatch=NA), scale to large lookups (O(log n)), and integrate with data.table's column assignment syntax |
| Tibble/data.table conversion | Manual as_tibble(as.data.frame(dt)) chains | to_tibble_safe() and ensure_dt() | Phase 95 utilities handle NULL/empty guards, type checks, and informative error messages |
| Deep copy for reference safety | Manual column-by-column duplication | copy() | Built-in data.table function handles all reference pointers correctly, including attributes and nested structures |

**Key insight:** data.table's reference semantics are powerful for performance but dangerous for R's typical functional programming style. Always use `copy()` at function boundaries to maintain caller expectations. Named vector lookups are simpler for small datasets but break down with missing values and don't compose with data.table's `:=` syntax.

## Common Pitfalls

### Pitfall 1: Forgetting copy() Causes Silent Input Mutation
**What goes wrong:** Function modifies caller's input object via reference semantics, breaking test isolation and causing spooky action-at-a-distance bugs

**Why it happens:** data.table's `:=` operator modifies objects in place for performance. If `classify_payer_tier_dt(enc)` skips `copy()`, then `enc[, tier := ...]` inside the function mutates the caller's `enc` object.

**How to avoid:** Always `copy()` at function entry before any `:=` operations:
```r
dt <- copy(ensure_dt(df))  # First line of function
```

**Warning signs:**
- Tests fail when run in sequence but pass individually
- Caller's data.frame has unexpected columns after function call
- Validation shows row count changes in original object

### Pitfall 2: Factor Inputs Cause Silent NA Matches in Keyed Joins
**What goes wrong:** Keyed join returns NA for all rows because factor levels don't match character keys in lookup table

**Why it happens:** vroom may load PAYER_TYPE_PRIMARY as factor if first 1000 rows look categorical. data.table keyed joins match by type AND value. Factor("219") ≠ character("219") → no match → NA.

**How to avoid:** Explicit `as.character()` coercion at function entry before any joins:
```r
dt[, `:=`(
  PAYER_TYPE_PRIMARY = as.character(PAYER_TYPE_PRIMARY),
  PAYER_TYPE_SECONDARY = as.character(PAYER_TYPE_SECONDARY),
  SOURCE = as.character(SOURCE)
)]
```

**Warning signs:**
- All `payer_category` values are NA or "Other" (prefix fallback)
- Validation shows 0% match rate on known-good codes like "219"
- `class(dt$PAYER_TYPE_PRIMARY)` returns "factor" not "character"

### Pitfall 3: Missing nomatch=NA in Keyed Joins Drops Unmatched Rows
**What goes wrong:** Rows with effective_payer values not found in AMC_PAYER_LOOKUP disappear from result

**Why it happens:** Default keyed join behavior is inner join (nomatch=0). Only matched rows survive. Unmatched rows are silently dropped.

**How to avoid:** Always specify `nomatch=NA` for left-join semantics:
```r
dt[amc_lookup, on = .(effective_payer = code),
   payer_category := i.payer_category,
   nomatch = NA]  # Unmatched rows get NA, not dropped
```

**Warning signs:**
- Row count decreases after join (nrow(dt_before) > nrow(dt_after))
- Validation fails with "row count mismatch" error
- Prefix fallback never triggers (because those rows were already dropped)

### Pitfall 4: Returning data.table Breaks Downstream dplyr Pipelines
**What goes wrong:** R/60, R/61, R/62 expect tibble input but receive data.table, causing dplyr verb failures or unexpected behavior

**Why it happens:** data.table objects have class `c("data.table", "data.frame")`. Some dplyr verbs work, some don't. Mixing paradigms causes subtle bugs.

**How to avoid:** Always return tibble via `to_tibble_safe()`:
```r
to_tibble_safe(dt, name = "result", script_name = "classify_payer_tier_dt")
```

**Warning signs:**
- Downstream script errors with "object not a tibble" or unexpected print behavior
- dplyr group_by() or summarize() produce different results than expected
- Validation passes but R/97 migration fails with mysterious errors

### Pitfall 5: Prefix Fallback Logic Has Off-by-One Substring Errors
**What goes wrong:** startsWith() check uses wrong column or wrong substring, assigning incorrect payer category

**Why it happens:** Copy-paste error from dplyr version; effective_payer may be NA, causing startsWith() to fail silently; substring index off by one

**How to avoid:**
- Only apply prefix fallback when `is.na(payer_category) & !is.na(effective_payer)`
- Use `startsWith(effective_payer, "1")` not `substr(effective_payer, 1, 1) == "1"` (clearer intent)
- Validate against dplyr version output row-by-row

**Warning signs:**
- Validation shows payer_category mismatch for codes like "93" (should override to Medicaid but doesn't)
- Category distribution differs from dplyr version (too many "Other", too few "Medicaid")

## Code Examples

Verified patterns from existing codebase and official data.table documentation:

### Defensive Copy at Function Entry
```r
# Source: R/utils/utils_dt.R (Phase 95) + data.table reference semantics vignette
# https://cran.r-project.org/web/packages/data.table/vignettes/datatable-reference-semantics.html

classify_payer_tier_dt <- function(df, include_dual = TRUE, flm_override = FALSE) {
  # Step 1: Convert to data.table with NULL/empty guards
  dt_raw <- ensure_dt(df, name = "input", script_name = "classify_payer_tier_dt")

  # Step 2: Deep copy to prevent reference mutation of caller's input
  dt <- copy(dt_raw)

  # Now safe to modify dt via := without affecting df
  dt[, new_column := compute_value()]
  # ...
}
```

### Keyed Join with Column Name Mismatch
```r
# Source: Phase 95 LOOKUP_TABLES_DT infrastructure + data.table joins vignette
# https://cran.r-project.org/web/packages/data.table/vignettes/datatable-joins.html

# Retrieve keyed lookup table (already setkey() on 'code' column)
amc_lookup <- get_lookup_dt("AMC_PAYER_LOOKUP")

# Left join: match dt$effective_payer to amc_lookup$code, add payer_category
dt[amc_lookup,
   on = .(effective_payer = code),    # Left key = right key (different names)
   payer_category := i.payer_category,  # i. prefix = right table column
   nomatch = NA]                       # Unmatched rows get NA (not dropped)
```

### fcase() for Effective Payer Resolution
```r
# Source: Existing classify_payer_tier() case_when() logic translated to fcase()
# https://rdatatable.gitlab.io/data.table/reference/fcase.html

dt[, effective_payer := fcase(
  # Branch 1: Primary valid (not NA, not empty, not sentinel)
  !is.na(PAYER_TYPE_PRIMARY) &
    nchar(trimws(PAYER_TYPE_PRIMARY)) > 0 &
    !PAYER_TYPE_PRIMARY %in% PAYER_MAPPING$sentinel_values,
  PAYER_TYPE_PRIMARY,

  # Branch 2: Secondary valid (primary was invalid)
  !is.na(PAYER_TYPE_SECONDARY) &
    nchar(trimws(PAYER_TYPE_SECONDARY)) > 0 &
    !PAYER_TYPE_SECONDARY %in% PAYER_MAPPING$sentinel_values,
  PAYER_TYPE_SECONDARY,

  # Default: Both invalid
  default = NA_character_
)]
```

### Prefix Fallback with fcase()
```r
# Source: Existing classify_payer_tier() prefix_cat logic (lines 113-124)

# Only apply fallback when direct lookup failed (payer_category is NA)
dt[is.na(payer_category) & !is.na(effective_payer), payer_category := fcase(
  startsWith(effective_payer, "1"), "Medicare",
  startsWith(effective_payer, "2"), "Medicaid",
  startsWith(effective_payer, "5") | startsWith(effective_payer, "6"), "Private",
  startsWith(effective_payer, "3") | startsWith(effective_payer, "4"), "Other govt",
  startsWith(effective_payer, "7"), "Private",
  startsWith(effective_payer, "8"), "Uninsured",
  startsWith(effective_payer, "9"), "Other",
  default = "Other"
)]

# Missing fallback (effective_payer is NA)
dt[is.na(effective_payer), payer_category := "Missing"]
```

### Special Code Override with Coalesce Pattern
```r
# Source: Existing classify_payer_tier() tier override logic (lines 131-138)

# First assign tier via CODE_TO_TIER (fcase version)
dt[, tier := fcase(
  payer_category == "Medicaid", "Medicaid",
  payer_category == "Medicare", "Medicare",
  payer_category == "Private", "Private",
  payer_category == "Other govt", "Other govt",
  payer_category == "Other", "Other",
  payer_category == "Self-pay", "Self-pay",
  payer_category == "Uninsured", "Uninsured",
  payer_category == "Missing", "Missing",
  default = "Missing"
)]

# Then override with special codes 93/14 (Medicaid regardless of category)
dt[, tier := fcase(
  PAYER_TYPE_PRIMARY %in% c("93", "14"), "Medicaid",
  PAYER_TYPE_SECONDARY %in% c("93", "14"), "Medicaid",
  default = tier  # Keep existing tier if no override
)]
```

### Conditional Column Addition (include_dual Parameter)
```r
# Source: Existing classify_payer_tier() dual_eligible logic (lines 156-174)

if (include_dual) {
  dual_codes <- PAYER_MAPPING$dual_eligible_codes

  dt[, dual_eligible := {
    sec_missing <- is.na(PAYER_TYPE_SECONDARY) |
                   nchar(trimws(PAYER_TYPE_SECONDARY)) == 0
    has_dual <- PAYER_TYPE_PRIMARY %in% dual_codes |
                PAYER_TYPE_SECONDARY %in% dual_codes
    cross_payer <- (startsWith(PAYER_TYPE_PRIMARY, "1") &
                    startsWith(PAYER_TYPE_SECONDARY, "2")) |
                   (startsWith(PAYER_TYPE_PRIMARY, "2") &
                    startsWith(PAYER_TYPE_SECONDARY, "1"))

    fcase(
      sec_missing, 0L,
      has_dual, 1L,
      cross_payer, 1L,
      default = 0L
    )
  }]
}
```

### Tier Rank Assignment via Keyed Join
```r
# Source: LOOKUP_TABLES_DT$TIER_MAPPING (Phase 95) + existing tier_rank logic

# Retrieve tier→rank mapping (keyed on payer_category)
tier_lookup <- get_lookup_dt("TIER_MAPPING")

# Join to add tier_rank column
dt[tier_lookup,
   on = .(tier = payer_category),  # Match dt$tier to tier_lookup$payer_category
   tier_rank := i.tier,             # i.tier is the integer rank
   nomatch = NA]

# Safety net: missing tier_rank defaults to 8 (lowest priority)
dt[is.na(tier_rank), tier_rank := 8L]
```

### Return Tibble for dplyr Compatibility
```r
# Source: Phase 95 utils_dt.R to_tibble_safe() pattern

# Final step: convert data.table result to tibble
to_tibble_safe(dt, name = "result", script_name = "classify_payer_tier_dt")
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| dplyr case_when() for conditionals | data.table fcase() for hot paths | Phase 96 (June 2026) | 5-10x faster for vectorized conditions; cleaner syntax for 3+ branches |
| Named vector lookup (AMC_PAYER_LOOKUP[code]) | Keyed joins (X[Y, on=]) | Phase 95 (June 2026) | Explicit NA handling (nomatch=NA), scales to large lookups, integrates with := syntax |
| Implicit copy-on-write (R default) | Explicit copy() for reference safety | Phase 96 (June 2026) | Prevents silent input mutation, documents intent, required for data.table's reference semantics |
| on= argument optional | on= argument required for clarity | data.table 1.12+ (2019) | Modern best practice: explicit column mapping over implicit key matching |

**Deprecated/outdated:**
- Implicit key matching without `on=` argument — modern data.table style requires explicit `on=.(left=right)` for readability
- setDT() in function bodies — use as.data.table() to avoid mutating input (unless mutation is explicitly intended)
- Nested fifelse() for 3+ branches — fcase() is cleaner and performs identically

## Open Questions

1. **Should tier_rank use integer join or character join?**
   - What we know: Existing dplyr version uses `unlist(TIER_MAPPING[tier])` which accesses named list by character key, returns integer
   - What's unclear: LOOKUP_TABLES_DT$TIER_MAPPING has `payer_category` (char) keyed to `tier` (int). Should join match on payer_category or tier column name?
   - Recommendation: Join on `tier = payer_category` (tier values like "Medicaid" match payer_category keys) and retrieve `i.tier` (the integer rank). This matches existing logic flow.

2. **Should validation script test on fixture data only or also production ENCOUNTER.csv?**
   - What we know: Phase 95 validation used fixture data for infrastructure checks. R/60 processes full ENCOUNTER (~1M+ rows). CONTEXT.md says validation "Can run on HiPerGator production data."
   - What's unclear: Does "can run" mean "optional" or "required"?
   - Recommendation: Validation script should support both via IS_LOCAL flag (fixture for quick checks, production for comprehensive parity). Make production run optional (controlled by script argument) to avoid long CI times.

3. **How to handle coalesce pattern for tier override in data.table syntax?**
   - What we know: dplyr version uses `coalesce(case_when(special_code_check), tier)` to override tier conditionally
   - What's unclear: data.table doesn't have built-in coalesce; fcase with `default=tier` may be cleaner
   - Recommendation: Use `fcase(special_code_condition, "Medicaid", default = tier)` — simpler than fifelse(special_code, "Medicaid", tier) and clearer intent

## Validation Architecture

> SKIPPED: workflow.nyquist_validation is explicitly set to false in .planning/config.json

## Sources

### Primary (HIGH confidence)
- [CRAN data.table 1.18.4 PDF manual](https://cran.r-project.org/web/packages/data.table/data.table.pdf) - Official package documentation (May 8, 2026)
- [data.table reference semantics vignette](https://cran.r-project.org/web/packages/data.table/vignettes/datatable-reference-semantics.html) - When to use copy()
- [data.table joins vignette](https://cran.r-project.org/web/packages/data.table/vignettes/datatable-joins.html) - Keyed join syntax with on= argument
- [fcase documentation](https://rdatatable.gitlab.io/data.table/reference/fcase.html) - Multi-branch conditional logic
- Existing codebase: R/utils/utils_payer.R (classify_payer_tier baseline), R/utils/utils_dt.R (Phase 95 helpers), R/00_config.R (LOOKUP_TABLES_DT and PAYER_MAPPING)

### Secondary (MEDIUM confidence)
- [data.table NEWS.md](https://github.com/Rdatatable/data.table/blob/master/NEWS.md) - Version 1.18.4 release notes (May 2026)
- [data.table fcase documentation](https://rdrr.io/cran/data.table/man/fcase.html) - fcase vs fifelse usage
- [R factor to character conversion](https://www.geeksforgeeks.org/r-language/how-to-convert-factor-to-character-in-r/) - Why as.character() is needed before joins

### Tertiary (LOW confidence)
- [data.table vs dplyr performance comparison](https://metricgate.com/blogs/data-table-vs-dplyr-r-performance/) - General performance claims (not specific benchmarks for this use case)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - data.table 1.18.4 verified from CRAN, existing Phase 95 infrastructure in place
- Architecture: HIGH - Existing classify_payer_tier() provides complete specification, official data.table vignettes document all required patterns
- Pitfalls: HIGH - Common data.table gotchas well-documented in official vignettes and existing project anti-patterns (Phase 95)

**Research date:** 2026-06-10
**Valid until:** 2026-09-10 (90 days for stable R package; data.table updates infrequently)
