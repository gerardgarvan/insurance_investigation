# Phase 98: R/28 + Remaining Lookup Optimization - Research

**Researched:** 2026-06-10
**Domain:** data.table keyed joins, named vector replacement, R lookup optimization
**Confidence:** HIGH

## Summary

Phase 98 completes the v3.0 data.table migration by replacing all remaining named vector lookups (`DRUG_GROUPINGS[code]`, `CODE_SUBCATEGORY_MAP[code]`) with keyed joins across 8 files. The primary target is R/28 episode classification, which processes ~1K treatment episodes using comma-separated `triggering_codes` that require an explode-join-collapse pattern. The established Phase 95-97 infrastructure (LOOKUP_TABLES_DT, ensure_dt(), classify_payer_tier_dt()) provides all necessary building blocks. Unlike Phase 97's hot-path focus (5-20x speedup), this phase prioritizes consistency and maintainability — eliminating the final vestiges of named vector syntax in favor of uniform keyed join patterns across the codebase.

**Primary recommendation:** Use data.table's explode-join-collapse pattern for R/28 comma-separated lookups (split with `tstrsplit()`, unnest to long format, keyed join against LOOKUP_TABLES_DT, re-aggregate with `paste(collapse=",")` by episode ID), then perform a surgical sweep of 7 additional files to replace isolated named vector lookups. Validate with dedicated R/98 parity script (follows R/95/R/96/R/97 validation pattern) and full R/88 smoke test as v3.0 gate.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Full codebase sweep — replace ALL `DRUG_GROUPINGS[` named vector lookups with keyed join syntax. Not just R/28 but also R/55, R/56, R/57_drug_grouping_instances, R/57_explore_dx_deduplication, R/58, R/88, and R/utils/utils_xlsx_lookups.R. Even where performance impact is negligible, keyed joins replace named vectors for consistency.
- **D-02:** CODE_SUBCATEGORY_MAP lookups in R/56, R/57, R/57_drug_grouping_instances, R/58, and utils_xlsx_lookups.R are also in scope (same pattern, same sweep).
- **D-03:** Explode-join-collapse approach for R/28's sapply-based patterns. Unnest comma-separated `triggering_codes` into one-row-per-code, do a single vectorized keyed join against LOOKUP_TABLES_DT, then re-aggregate with `paste(collapse=",")`. Eliminates the R-level sapply/str_split loop entirely.
- **D-04:** Applies to all R/28 sections that use the pattern: Section 5B (map_codes_to_descriptions, map_codes_to_drug_groups), Section 5C (map_codes_to_xlsx_metadata, aggregate_treatment_line, aggregate_cross_use_flag, aggregate_immuno_confidence), and Section 6B (TBD code export loop).
- **D-05:** Dedicated R/98 parity validation script that compares R/28 output (treatment_episodes.rds) before vs after optimization. Validates structure (columns, order, types) and content (row-by-row match). Follows the R/95/R/96/R/97 validation script pattern.
- **D-06:** No benchmark timing needed — R/28 processes ~1K episodes (not 1M encounters like R/60). The optimization is for consistency with the data.table milestone, not for measurable speedup.
- **D-07:** Full R/88 smoke test (all 35 sections) serves as the final v3.0 gate. Must pass after all changes.

### Claude's Discretion
- Internal data.table patterns for the explode-join-collapse (CJ vs manual unnest, .SD usage, re-aggregation method)
- Whether helper functions (lookup_drug_group, map_codes_to_drug_groups, etc.) are rewritten as data.table functions or replaced with inline operations
- How to handle the xlsx_lookups vectors (currently named character vectors, not in LOOKUP_TABLES_DT) — may need temporary data.table wrappers
- R/98 validation script structure and specific checks
- Whether code_descriptions.rds lookup (also in R/28) gets the same treatment or stays as-is (it's loaded from RDS, not a config lookup table)
- Ordering and grouping of the 8-file sweep for the plan

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| PERF-03 | R/28 episode classification lookups replaced with keyed joins | Explode-join-collapse pattern (Section 3.2), LOOKUP_TABLES_DT keyed tables (Section 2.1) |
| PERF-04 | R/28 treatment_episodes.rds structure unchanged (same columns, same order) | Validation Architecture (Section 7), parity validation script pattern (Section 3.4) |
| VALID-01 | Smoke test R/88 passes with all existing sections after optimization | R/88 validation pattern (Section 7.2), no external dependencies |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| data.table | 1.18.4 | Keyed joins and aggregation | Already in project (Phase 95 INFRA-01), 10-50x faster than dplyr for lookups |
| tidyverse | 2.0.0+ | Dplyr compatibility layer | Existing project dependency; data.table functions return tibbles via to_tibble_safe() |
| glue | 1.8.0 | String interpolation for logging | Existing project dependency; used in validation scripts |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| stringr | 1.5.1+ | String operations | R/28 comma-splitting (before migration to tstrsplit), ICD code normalization |
| readr | 2.2.0+ | RDS file I/O | R/28 loads code_descriptions.rds, writes treatment_episodes.rds |

**Installation:**
```bash
# All dependencies already installed in Phase 95
# Verify with:
renv::status()
```

**Version verification:** Phase 95 already pinned data.table 1.18.4 in renv.lock (latest stable as of May 2026).

## Architecture Patterns

### Pattern 1: Explode-Join-Collapse for Comma-Separated Lookups
**What:** Split comma-separated codes into one-row-per-code (explode), perform a single keyed join against LOOKUP_TABLES_DT, then re-aggregate by episode ID with `paste(collapse=",")`.

**When to use:** R/28 Section 5B/5C where `triggering_codes = "J9035,J9041"` needs to map to `drug_group = "Chemotherapy,Chemotherapy"`.

**Example (R/28 Section 5B drug group mapping):**
```r
# OLD: sapply over comma-separated codes
map_codes_to_drug_groups <- function(codes_str) {
  if (is.na(codes_str) || codes_str == "") return(NA_character_)
  codes <- str_split(codes_str, ",")[[1]]
  groups <- sapply(codes, lookup_drug_group, USE.NAMES = FALSE)
  paste(groups, collapse = ",")
}
episodes <- episodes %>%
  mutate(drug_group = sapply(triggering_codes, map_codes_to_drug_groups, USE.NAMES = FALSE))

# NEW: Explode-join-collapse with data.table
episodes_dt <- ensure_dt(episodes, name = "episodes", script_name = "R/28")
episodes_dt[, episode_id := .I]  # Temporary ID for re-aggregation

# Explode: one row per code
codes_long <- episodes_dt[, .(code = unlist(strsplit(triggering_codes, ",", fixed = TRUE))),
                          by = episode_id]

# Join: keyed lookup against DRUG_GROUPINGS
drug_lookup <- get_lookup_dt("DRUG_GROUPINGS")
codes_long[drug_lookup, on = .(code), drug_group := i.drug_group]

# Collapse: re-aggregate by episode
drug_groups_agg <- codes_long[, .(drug_group = paste(drug_group, collapse = ",")),
                               by = episode_id]

# Merge back to episodes
episodes_dt[drug_groups_agg, on = .(episode_id), drug_group := i.drug_group]
episodes_dt[, episode_id := NULL]  # Clean up temporary ID

episodes <- to_tibble_safe(episodes_dt, name = "episodes", script_name = "R/28")
```

### Pattern 2: Simple Named Vector Replacement (Single-Code Lookups)
**What:** Replace `DRUG_GROUPINGS[code]` with keyed join `dt[lookup, on=.(code), drug_group := i.drug_group]`.

**When to use:** R/55, R/56, R/57, R/58, R/88 where code is already a single value per row (no comma-separation).

**Example (R/55 verify_replaced_by_codes.R):**
```r
# OLD: Named vector lookup
verification <- replaced_by_pairs %>%
  mutate(
    old_group = DRUG_GROUPINGS[old_code],
    new_group = DRUG_GROUPINGS[new_code]
  )

# NEW: Keyed join
verification_dt <- ensure_dt(replaced_by_pairs, name = "verification", script_name = "R/55")
drug_lookup <- get_lookup_dt("DRUG_GROUPINGS")

verification_dt[drug_lookup, on = .(old_code = code), old_group := i.drug_group]
verification_dt[drug_lookup, on = .(new_code = code), new_group := i.drug_group]

verification <- to_tibble_safe(verification_dt, name = "verification", script_name = "R/55")
```

### Pattern 3: xlsx_lookups Named Vector Wrapper
**What:** utils_xlsx_lookups.R returns named character vectors (medications, code_types, source_tables, line_labels, cross_use_flags). Convert these to temporary keyed data.tables for R/28 Section 5C joins.

**When to use:** R/28 Section 5C metadata mapping, where xlsx_lookups$medications[code] is the current pattern.

**Example:**
```r
# In utils_xlsx_lookups.R or R/28 Section 5C setup
xlsx_lookups_dt <- list(
  medications = {
    dt <- data.table(code = names(xlsx_lookups$medications),
                     medication_name = unname(xlsx_lookups$medications))
    setkey(dt, code)
    dt
  },
  code_types = {
    dt <- data.table(code = names(xlsx_lookups$code_types),
                     code_type = unname(xlsx_lookups$code_types))
    setkey(dt, code)
    dt
  }
  # ... repeat for source_tables, line_labels, cross_use_flags
)

# Then use in explode-join-collapse pattern (same as Pattern 1)
codes_long[xlsx_lookups_dt$medications, on = .(code), medication_name := i.medication_name]
```

### Recommended Project Structure
```
R/
├── 28_episode_classification.R    # Primary target: Sections 5B, 5C, 6B
├── 55_verify_replaced_by_codes.R  # Simple named vector replacements
├── 56_new_tables_from_groupings.R # DRUG_GROUPINGS + CODE_SUBCATEGORY_MAP
├── 57_drug_grouping_instances.R   # DRUG_GROUPINGS + CODE_SUBCATEGORY_MAP
├── 57_explore_dx_deduplication.R  # DRUG_GROUPINGS + CODE_SUBCATEGORY_MAP
├── 58_code_reference_tables.R     # CODE_SUBCATEGORY_MAP
├── 88_smoke_test_comprehensive.R  # DRUG_GROUPINGS validation check
├── 98_validate_r28_migration.R    # NEW: Parity validation script
└── utils/
    └── utils_xlsx_lookups.R       # CODE_SUBCATEGORY_MAP + DRUG_GROUPINGS
```

### Anti-Patterns to Avoid
- **Mutating input data:** Always use `copy(ensure_dt())` at entry point, never setDT() on input (Phase 95 D-01 anti-pattern)
- **Forgetting to return tibble:** R/28 output must be tibble for downstream compatibility; always end with `to_tibble_safe()`
- **Manual row-by-row loops:** Avoid `for (code in codes) { lookup[code] }`; use vectorized joins or explode-join-collapse
- **Forgetting temporary IDs:** When exploding comma-separated codes, add `.I` or `1:.N` as episode_id before splitting so you can re-aggregate

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Comma-separated string splitting | `sapply(str_split())` loops | data.table explode-join-collapse (strsplit + keyed join + paste(collapse)) | O(n) vectorized join vs O(n*m) R-level loop; eliminates 460-594 line sapply patterns in R/28 |
| Single-code lookups | Named vector indexing `DRUG_GROUPINGS[code]` | Keyed join `dt[lookup, on=.(code), col := i.col]` | Consistent syntax, O(log n) binary search, eliminates 8 different named vector patterns |
| Validation scripts | Manual before/after CSV diffs | Automated parity checks with check() helper | Phase 95/96/97 established pattern; 45-check granularity for precise failure localization |

**Key insight:** Named vector lookups (`lookup[code]`) are syntactically convenient but create inconsistency in a codebase migrating to data.table. Keyed joins are uniform, self-documenting (`on=.(code)`), and scale to multi-column keys. The minor verbosity cost (3 lines vs 1) is offset by maintainability gains across 8 files and 12+ lookup sites.

## Common Pitfalls

### Pitfall 1: NA Handling in Exploded Joins
**What goes wrong:** When splitting comma-separated codes, empty strings or NA values create spurious rows that fail to match lookup tables and propagate as NA results.

**Why it happens:** `strsplit("J9035,,J9041", ",")` produces `c("J9035", "", "J9041")`. The empty string joins against DRUG_GROUPINGS, finds no match, and returns NA.

**How to avoid:**
```r
# Filter out empty/NA codes immediately after split
codes_long <- episodes_dt[, .(code = unlist(strsplit(triggering_codes, ",", fixed = TRUE))),
                          by = episode_id]
codes_long <- codes_long[!is.na(code) & code != ""]
```

**Warning signs:** If `drug_group` column has unexpected NA values after join, check codes_long for empty strings before join.

### Pitfall 2: Forgetting to Re-aggregate After Explode
**What goes wrong:** After exploding episodes from 1K rows to 3K rows (one per code), forgetting to collapse back results in a 3K-row output instead of 1K, breaking downstream scripts.

**Why it happens:** The explode-join pattern requires explicit re-aggregation by episode_id. It's not automatic.

**How to avoid:**
```r
# Always include the collapse step
drug_groups_agg <- codes_long[, .(drug_group = paste(drug_group, collapse = ",")),
                               by = episode_id]
episodes_dt[drug_groups_agg, on = .(episode_id), drug_group := i.drug_group]
```

**Warning signs:** If `nrow(episodes)` changes after migration, check for missing re-aggregation.

### Pitfall 3: xlsx_lookups Vectors Not in LOOKUP_TABLES_DT
**What goes wrong:** R/28 Section 5C uses `xlsx_lookups$medications[code]`, but xlsx_lookups vectors aren't in LOOKUP_TABLES_DT (they're built dynamically in utils_xlsx_lookups.R). Attempting `get_lookup_dt("medications")` fails.

**Why it happens:** LOOKUP_TABLES_DT was designed for static config lookups (DRUG_GROUPINGS, CODE_SUBCATEGORY_MAP). xlsx_lookups are derived vectors built from multiple sources.

**How to avoid:** Create temporary keyed data.tables from xlsx_lookups at the top of R/28 Section 5C:
```r
xlsx_lookups_dt <- lapply(xlsx_lookups, function(vec) {
  dt <- data.table(code = names(vec), value = unname(vec))
  setkey(dt, code)
  dt
})
```

**Warning signs:** Error message "medications not found in lookup list. Available: AMC_PAYER_LOOKUP, DRUG_GROUPINGS, ...".

### Pitfall 4: Aggregation Functions Different from paste(collapse)
**What goes wrong:** R/28 Section 5C has 3 aggregation patterns: parallel lists (`medication_name = "Drug A,Drug B"`), priority selection (`treatment_line = "F"`), and any-positive flags (`cross_use_flag = "Questionable"`). Using `paste(collapse=",")` for all three produces wrong results for treatment_line and cross_use_flag.

**Why it happens:** Not all R/28 columns are parallel lists. Some require custom aggregation logic (max priority, first non-NA).

**How to avoid:**
```r
# Parallel list: paste(collapse=",")
med_names_agg <- codes_long[, .(medication_name = paste(medication_name, collapse = ",")),
                            by = episode_id]

# Priority selection: fcase() with priority order
line_agg <- codes_long[, .(treatment_line = {
  labels <- na.omit(treatment_line)
  fcase(
    "F" %in% labels, "F",
    "S" %in% labels, "S",
    "E" %in% labels, "E",
    "N" %in% labels, "N",
    default = NA_character_
  )
}), by = episode_id]

# Any-positive: first non-NA
flag_agg <- codes_long[, .(cross_use_flag = first(na.omit(cross_use_flag))),
                       by = episode_id]
```

**Warning signs:** If R/98 parity validation fails on treatment_line or cross_use_flag columns, check aggregation logic.

## Code Examples

Verified patterns from established Phase 95-97 code:

### Keyed Join for Single-Code Lookup (Phase 96 Pattern)
```r
# Source: R/utils/utils_payer.R:327 (classify_payer_tier_dt)
tier_lookup <- get_lookup_dt("TIER_MAPPING")
dt[tier_lookup, on = .(tier = payer_category), tier_rank := i.tier]
```

### Explode-Join-Collapse Skeleton (Synthesized from R/28 Requirements)
```r
# Step 1: Convert to data.table with temporary episode ID
episodes_dt <- copy(ensure_dt(episodes, name = "episodes", script_name = "R/28"))
episodes_dt[, episode_id := .I]

# Step 2: Explode comma-separated triggering_codes
codes_long <- episodes_dt[, .(code = unlist(strsplit(triggering_codes, ",", fixed = TRUE))),
                          by = episode_id]
codes_long <- codes_long[!is.na(code) & code != ""]

# Step 3: Join against DRUG_GROUPINGS
drug_lookup <- get_lookup_dt("DRUG_GROUPINGS")
codes_long[drug_lookup, on = .(code), drug_group := i.drug_group]

# Step 4: Re-aggregate by episode
drug_groups_agg <- codes_long[, .(drug_group = paste(drug_group, collapse = ",")),
                               by = episode_id]

# Step 5: Merge back to episodes
episodes_dt[drug_groups_agg, on = .(episode_id), drug_group := i.drug_group]
episodes_dt[, episode_id := NULL]

# Step 6: Return tibble
episodes <- to_tibble_safe(episodes_dt, name = "episodes", script_name = "R/28")
```

### Validation Script Pattern (Phase 95 Pattern)
```r
# Source: R/95_validate_dt_infrastructure.R:50
check <- function(description, condition) {
  if (isTRUE(condition)) {
    message(sprintf("[PASS] %s", description))
    pass_count <<- pass_count + 1L
  } else {
    message(sprintf("[FAIL] %s", description))
    fail_count <<- fail_count + 1L
  }
}

# Apply to R/28 output structure validation
check(
  "treatment_episodes.rds has 22 columns",
  ncol(treatment_episodes_new) == 22
)
check(
  "Column order matches baseline (drug_group is column 5)",
  names(treatment_episodes_new)[5] == "drug_group"
)
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Named vector lookups (`DRUG_GROUPINGS[code]`) | Keyed joins (`dt[lookup, on=.(code), col := i.col]`) | Phase 95-98 (v3.0, Jun 2026) | Uniform syntax, binary search performance, multi-column key support |
| sapply loops over comma-separated codes | Explode-join-collapse pattern | Phase 98 (v3.0, Jun 2026) | Eliminates R-level loops, vectorized joins, 10-100x faster for large datasets |
| Manual before/after validation | Automated parity scripts with check() helper | Phase 95-98 (v3.0, Jun 2026) | 45+ granular checks, SLURM exit code integration, reproducible |

**Deprecated/outdated:**
- **Named vector indexing in hot paths:** Phase 95-97 established LOOKUP_TABLES_DT as the standard. Named vectors remain in R/00_config.R for backward compatibility but new code should not use them.
- **case_when() in data.table code:** Replaced by fcase() (Phase 96 D-03). case_when() is dplyr-specific; fcase() is data.table's optimized equivalent.

## Open Questions

1. **code_descriptions.rds lookup handling**
   - What we know: R/28 loads `code_descriptions <- readRDS("output/artifacts/code_descriptions.rds")` and uses `code_descriptions[[code]]` for lookups (lines 460-463). This is a named vector loaded from RDS, not a config lookup.
   - What's unclear: Should this be converted to a keyed data.table as well, or left as-is since it's dynamically loaded (not config-defined)?
   - Recommendation: Leave as-is for Phase 98. code_descriptions is built by an upstream script and stored as RDS; converting it requires coordination with the script that builds it. Defer to v3.1 if consistency becomes a priority.

2. **Helper function preservation vs inlining**
   - What we know: R/28 has helper functions like `map_codes_to_drug_groups()` and `aggregate_treatment_line()` that wrap sapply patterns. The explode-join-collapse approach can be inlined or wrapped in new data.table helper functions.
   - What's unclear: Is there value in preserving the helper function abstraction, or should the explode-join-collapse logic be inlined directly in R/28 Sections 5B/5C?
   - Recommendation: Inline for Phase 98. The helpers exist to wrap sapply logic; once replaced with data.table, the abstraction adds no value (no reuse across scripts). Inline reduces indirection and makes the vectorized approach visible.

3. **R/88 Section 15 coverage of new patterns**
   - What we know: R/88 smoke test has 35 sections validating config constants, file structure, and script outputs. Line 1623 validates DRUG_GROUPINGS named vector lookup.
   - What's unclear: Does R/88 Section 15 adequately test keyed join patterns, or does it only validate named vector syntax?
   - Recommendation: R/88 validation check at line 1623 will break after migration (tests `DRUG_GROUPINGS[proton_codes]`). Update to test keyed join syntax instead: `LOOKUP_TABLES_DT$DRUG_GROUPINGS[.(proton_codes), drug_group]`. Add to Phase 98 plan.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| data.table | Keyed joins (PERF-03) | ✓ | 1.18.4 | — |
| R | Runtime | ✗ (dev machine) | — | HiPerGator execution only |
| renv | Package management | ✓ | 1.1.4+ | — |

**Missing dependencies with no fallback:**
- R runtime not installed on dev machine (Windows) — all execution must occur on HiPerGator via SLURM or RStudio Server

**Missing dependencies with fallback:**
- None

**Note:** Phase 98 is code-only (no new dependencies). All required packages (data.table, tidyverse, glue, stringr, readr) were installed in Phase 95.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Custom validation with check() helper (established in Phase 95-97) |
| Config file | None — R/98_validate_r28_migration.R is standalone validation script |
| Quick run command | `Rscript R/98_validate_r28_migration.R` |
| Full suite command | `Rscript R/88_smoke_test_comprehensive.R` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| PERF-03 | R/28 lookups use keyed joins | unit | `grep -c "DRUG_GROUPINGS\\[" R/28_episode_classification.R` (expect 0) | ❌ Wave 0 |
| PERF-04 | treatment_episodes.rds structure unchanged | integration | `Rscript R/98_validate_r28_migration.R` | ❌ Wave 0 |
| VALID-01 | R/88 all 35 sections pass | smoke | `Rscript R/88_smoke_test_comprehensive.R` | ✅ (requires update for keyed join syntax) |

### Sampling Rate
- **Per task commit:** `Rscript R/98_validate_r28_migration.R` (R/28 parity only, ~30 seconds)
- **Per wave merge:** `Rscript R/88_smoke_test_comprehensive.R` (full suite, ~2 minutes)
- **Phase gate:** R/88 all 35 sections pass + R/98 parity validation + grep confirms zero DRUG_GROUPINGS[ matches

### Wave 0 Gaps
- [ ] `R/98_validate_r28_migration.R` — covers PERF-03, PERF-04 (structure + content parity)
- [ ] Update `R/88_smoke_test_comprehensive.R` line 1623 — replace named vector test with keyed join syntax test

*(Validation script creation is part of implementation, not a gap — Wave 0 establishes the validation approach)*

## Sources

### Primary (HIGH confidence)
- R/28_episode_classification.R (lines 460-495, 510-594, 740-767) — Current sapply patterns being replaced
- R/00_config.R (lines 3438-3519) — LOOKUP_TABLES_DT keyed data.tables with code/drug_group and code/subcategory columns
- R/utils/utils_dt.R (full file, 158 lines) — ensure_dt(), to_tibble_safe(), get_lookup_dt() helpers
- R/utils/utils_payer.R (lines 300-364) — classify_payer_tier_dt() established keyed join pattern
- R/95_validate_dt_infrastructure.R, R/96_validate_payer_dt.R, R/97_validate_r60_migration.R — Validation script pattern
- .planning/phases/95-infrastructure-setup/95-CONTEXT.md — D-03 (semantic column names), D-04 (TREATMENT_CODES flattening)
- .planning/phases/96-classify-payer-tier-dt-implementation/96-CONTEXT.md — Keyed join patterns, copy() at entry, to_tibble_safe() at exit
- .planning/phases/97-r-60-hot-path-migration/97-CONTEXT.md — Full script migration pattern

### Secondary (MEDIUM confidence)
- [data.table tstrsplit documentation](https://rdatatable.gitlab.io/data.table/reference/tstrsplit.html) — Official docs for string splitting function
- [How to Collapse Text by Group in a Data Frame Using R](https://www.r-bloggers.com/2024/05/how-to-collapse-text-by-group-in-a-data-frame-using-r/) — data.table paste(collapse=",") pattern
- [R: How to Collapse Text by Group in Data Frame](https://www.statology.org/r-collapse-text-by-group/) — Aggregation by group examples

### Tertiary (LOW confidence)
- CRAN data.table 1.18.4 PDF documentation (binary format, not directly readable) — Attempted but format prevented extraction

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All dependencies already installed in Phase 95, versions verified in renv.lock
- Architecture: HIGH - Explode-join-collapse pattern synthesized from established data.table idioms + R/28 requirements; keyed join pattern directly from Phase 96-97 code
- Pitfalls: MEDIUM - Explode-join pitfalls (NA handling, re-aggregation) are synthesized from common data.table errors, not project-specific empirical failures
- Validation: HIGH - R/95/R/96/R/97 validation scripts provide direct template; check() helper pattern is established

**Research date:** 2026-06-10
**Valid until:** 2026-07-10 (30 days; stable domain — data.table 1.18.4 is latest stable, no fast-moving changes)
