# Phase 111: Collapse chemo agents by date per patient in TABLE-2 - Research

**Researched:** 2026-06-18
**Domain:** R data aggregation with dplyr — collapsing multiple rows per group with string concatenation
**Confidence:** HIGH

## Summary

Phase 111 modifies R/36's TABLE-2 output from per-encounter+medication grain to per-patient+date grain by collapsing multiple agent names into comma-separated strings. This is a standard dplyr `group_by()` + `summarise()` aggregation pattern using `paste(sort(unique(x)), collapse = ",")` — identical to the pattern already used in R/36 Section 3 for cancer code aggregation. The transformation drops encounter-level columns (ENCOUNTERID, drug_class, treatment_type) since they become meaningless at date grain, and merges+deduplicates cancer codes across all encounters sharing the same patient+date.

**Primary recommendation:** Use dplyr's `group_by(PATID, treatment_date) %>% summarise()` with `paste(sort(unique(x)), collapse = ",")` for each string column (medication_name, cancer_codes, cancer_category_names). This is a proven pattern already working in R/36 Section 3 line 156 and Phase 109's date-grain transformation. Handle NA values explicitly via `na.omit()` within paste() to avoid "NA" strings in collapsed output.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions (MUST implement exactly as specified)

**Output Columns (D-01 through D-05):**
- Drop ENCOUNTERID column entirely — date grain makes encounter IDs meaningless
- Drop drug_class column — always "Chemotherapy" after chemo-only filter, no information content
- Drop treatment_type column — always "Chemotherapy" after chemo-only filter, no information content
- Merge and deduplicate cancer_codes across all encounters on same patient+date — union all cancer codes into comma-separated string
- Merge and deduplicate cancer_category_names across all encounters on same patient+date — matching cancer_codes merge
- Final columns: PATID, treatment_date, agents (collapsed medication names), cancer_codes (merged+deduped), cancer_category_names (merged+deduped)

**Agent String Format (D-06, D-07):**
- Combined agent string uses medication names only (e.g., "Doxorubicin, Vincristine, Bleomycin"), no triggering codes in the string
- Comma-separated, sorted alphabetically
- Deduplicate agents within each date — each unique medication name appears once per patient+date, even if it appeared in multiple encounters

**Scope of Change (D-08 through D-10):**
- Modify R/36 Section 5 in-place — change TABLE-2 build logic to collapse by (PATID, treatment_date) instead of keeping per-encounter+medication rows
- Replace existing output file — same filename (`tableau_table2_chemo_drugs_by_class.xlsx`), date-collapsed version supersedes per-encounter version
- TABLE-1 (encounter cancer codes) is completely untouched

### Claude's Discretion

- Column name for collapsed agents string (e.g., "agents", "medication_names", "chemo_agents")
- Whether to update R/88 smoke test assertions for new column structure
- Exact sort order for cancer_codes and cancer_category_names within merged strings (alphabetical vs original)
- Log message updates to reflect new grain and row counts

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.

</user_constraints>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| dplyr | 1.2.0+ | Data transformation | Mature, optimized for readability; `group_by()` + `summarise()` is canonical aggregation pattern |
| stringr | 1.5.1+ | String operations | Consistent API for string manipulation; used for cleaning/normalization if needed |
| glue | 1.8.0+ | String formatting | Readable logging messages with embedded expressions |
| openxlsx2 | latest | Excel output | Already in use in R/36 for xlsx writing; no change needed |

**Installation:** Already installed per R/36 existing dependencies. No new packages required.

**Version verification:** Project already uses tidyverse 2.0.0+ which includes dplyr 1.2.0+ and stringr 1.5.1+. Verified via CLAUDE.md STACK.md section.

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| tidyr | 1.3.0+ | Data reshaping (if needed) | NOT required for this phase — pure aggregation, no pivoting |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| dplyr `group_by()` + `summarise()` | data.table aggregation | 10-50x faster but opaque syntax (`DT[, .(agents = paste(unique(medication_name), collapse = ",")), by = .(PATID, treatment_date)]`) conflicts with project's "named predicate" requirement |
| `paste()` with `collapse` | `str_c()` from stringr | Identical functionality, but `paste()` is base R standard and already used in R/36 Section 3 line 156 |
| Inline aggregation | Separate helper function | Overkill for one-time transformation; inline is clearer |

## Architecture Patterns

### Recommended Transformation Structure

**Current R/36 Section 5 flow (per-encounter+medication grain):**
```
1. Filter detail_dx to Chemotherapy encounters only
2. Resolve medication_name via 3-tier cascade (xlsx -> CODE_SUBCATEGORY_MAP -> fallback)
3. Add drug_class = "Chemotherapy"
4. Select columns + distinct() + arrange()
5. Write to xlsx
```

**Modified R/36 Section 5 flow (per-patient+date grain):**
```
1. Filter detail_dx to Chemotherapy encounters only
2. Resolve medication_name via 3-tier cascade (xlsx -> CODE_SUBCATEGORY_MAP -> fallback) — UNCHANGED
3. Drop drug_class and treatment_type columns (always "Chemotherapy", no information)
4. Group by (PATID, treatment_date)
5. Summarise:
   - agents = paste(sort(unique(medication_name)), collapse = ",")
   - cancer_codes = paste(sort(unique(unlist(strsplit(cancer_codes, ",")))), collapse = ",")
   - cancer_category_names = paste(sort(unique(unlist(strsplit(cancer_category_names, ",")))), collapse = ",")
6. Arrange by PATID, treatment_date
7. Write to xlsx
```

### Pattern 1: String Collapse with Deduplication

**What:** Group by multiple columns and collapse string values into comma-separated lists with deduplication and sorting.

**When to use:** Any time you need to aggregate multiple rows per group where the target columns are text values that should be combined.

**Example:**
```r
# Source: R/36 Section 3 line 156 (existing cancer code aggregation)
encounter_dx <- dx_cancer %>%
  group_by(ENCOUNTERID) %>%
  summarise(
    cancer_codes = paste(sort(unique(DX)), collapse = ","),
    .groups = "drop"
  )

# Adapted for Phase 111 (medication names by patient-date)
table2 <- chemo_detail %>%
  group_by(PATID, treatment_date) %>%
  summarise(
    agents = paste(sort(unique(medication_name)), collapse = ","),
    cancer_codes = paste(sort(unique(cancer_codes)), collapse = ","),
    cancer_category_names = paste(sort(unique(cancer_category_names)), collapse = ","),
    .groups = "drop"
  ) %>%
  arrange(PATID, treatment_date)
```

**Key elements:**
- `unique()` deduplicates values within each group
- `sort()` ensures consistent alphabetical ordering
- `collapse = ","` joins with comma separator (consistent with Phase 106 D-02)
- `.groups = "drop"` removes grouping after summarise (best practice)

### Pattern 2: Merging Already-Collapsed Strings

**What:** When input rows already have comma-separated strings (like cancer_codes from multiple encounters), split them, deduplicate globally across all rows in the group, then re-collapse.

**When to use:** Aggregating rows where the column already contains comma-separated values that need union+dedup.

**Example:**
```r
# Source: Adapted from R/36 Section 3 pattern + Phase 109 date-grain philosophy
# cancer_codes column already contains comma-separated strings per encounter
# Need to union codes across all encounters on the same patient+date

# OPTION 1: Simple unique() if cancer_codes already deduplicated per encounter
table2 <- chemo_detail %>%
  group_by(PATID, treatment_date) %>%
  summarise(
    agents = paste(sort(unique(medication_name)), collapse = ","),
    cancer_codes = paste(sort(unique(cancer_codes)), collapse = ","),
    .groups = "drop"
  )

# OPTION 2: Split-union-collapse if cancer_codes may have duplicates across encounters
table2 <- chemo_detail %>%
  group_by(PATID, treatment_date) %>%
  summarise(
    agents = paste(sort(unique(medication_name)), collapse = ","),
    cancer_codes = paste(sort(unique(unlist(strsplit(cancer_codes, ",")))), collapse = ","),
    .groups = "drop"
  )
```

**Recommendation:** Use OPTION 1 (simple unique on cancer_codes string) UNLESS testing reveals duplicate codes across encounters. R/36 Section 3 already deduplicates cancer codes per encounter, so merging at date grain likely only needs unique() on the already-collapsed strings, not full split-union.

### Pattern 3: NA Handling in String Collapse

**What:** Prevent NA values from appearing as literal "NA" strings in collapsed output.

**When to use:** Any string aggregation where source data may have NA values.

**Example:**
```r
# BAD: NA becomes "NA" string in output
agents = paste(unique(medication_name), collapse = ",")
# Result: "Doxorubicin,NA,Vincristine"

# GOOD: Filter out NA before collapse
agents = paste(unique(na.omit(medication_name)), collapse = ",")
# Result: "Doxorubicin,Vincristine"

# BETTER: Handle edge case where ALL values are NA
agents = if(all(is.na(medication_name))) NA_character_ else paste(sort(unique(na.omit(medication_name))), collapse = ",")
```

**Why critical for Phase 111:** medication_name is resolved via 3-tier cascade with fallback, so NAs are unlikely. But cancer_codes may be NA for encounters with no cancer diagnosis. Must handle explicitly to avoid "NA" strings in output.

### Anti-Patterns to Avoid

- **Don't use `toString()`**: Returns "value1, value2" format (with space after comma) inconsistent with Phase 106 D-02 comma-only separator.
- **Don't forget `.groups = "drop"`**: Leaving grouped data can cause confusing downstream errors.
- **Don't use `distinct()` after `summarise()`**: `summarise()` already collapses to one row per group; distinct() is redundant.
- **Don't sort after collapse**: `sort()` must be INSIDE paste(), not after. `sort(paste(x, collapse = ","))` sorts a single string alphabetically by character, not by the original values.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| String aggregation by group | Manual loop with `for (id in unique(PATID))` + nested `for (date in unique(dates))` + string concatenation | dplyr `group_by()` + `summarise()` with `paste(collapse = ",")` | Built-in vectorization, readable syntax, handles edge cases (empty groups, NAs) automatically |
| Deduplication before collapse | Filter to `unique()` rows before grouping, then collapse | `paste(unique(x), collapse = ",")` inline | Combining unique() and collapse in one summarise() call is more efficient and clearer |
| Splitting and re-collapsing comma-separated strings | Manual `strsplit()` + loop + `unique()` + paste | `paste(sort(unique(unlist(strsplit(x, ",")))), collapse = ",")` one-liner | Standard R idiom, already proven in R/36 Section 3 |

**Key insight:** dplyr's `group_by()` + `summarise()` pattern is specifically designed for this use case. The R ecosystem has decades of optimization around this pattern — custom aggregation loops are slower, buggier, and less readable.

## Common Pitfalls

### Pitfall 1: Forgetting to Drop Meaningless Columns

**What goes wrong:** Including ENCOUNTERID, drug_class, or treatment_type in the date-grain output. These columns are encounter-level artifacts that become meaningless (or misleading) when multiple encounters collapse to one row per patient+date.

**Why it happens:** The existing R/36 Section 5 code includes these columns, and it's easy to carry them forward without realizing they're now ambiguous. Which ENCOUNTERID do you show when 3 encounters collapse to one row?

**How to avoid:** Explicitly drop these columns BEFORE `group_by()` or exclude them from the `select()` list in `summarise()`. Phase 111 D-01, D-02 specify exactly which columns to drop.

**Warning signs:** R/88 smoke test shows column count mismatch, or Tableau visualizations show duplicate/confusing encounter IDs.

### Pitfall 2: NA Becoming Literal "NA" String

**What goes wrong:** `paste()` converts NA to the string "NA", so collapsed output contains "Doxorubicin,NA,Vincristine" instead of "Doxorubicin,Vincristine".

**Why it happens:** R's `paste()` coerces all inputs to character, and `as.character(NA)` produces "NA" string, not an empty value.

**How to avoid:** Wrap values in `na.omit()` before unique/sort/paste, OR use `na.rm = TRUE` pattern, OR filter `!is.na(x)` before collapse.

```r
# WRONG
agents = paste(unique(medication_name), collapse = ",")

# RIGHT
agents = paste(unique(na.omit(medication_name)), collapse = ",")

# ALTERNATIVE
agents = paste(unique(medication_name[!is.na(medication_name)]), collapse = ",")
```

**Warning signs:** Smoke test shows literal "NA" in collapsed strings; Tableau filters show "NA" as a medication name.

### Pitfall 3: Row Count Assumptions Breaking

**What goes wrong:** Downstream code (R/88 smoke test, R/37 gap resolution report) assumes TABLE-2 row count is >= TABLE-1 row count because TABLE-2 was per-encounter+medication (multiple meds per encounter = more rows). After Phase 111, TABLE-2 is per-patient+date, likely FEWER rows than TABLE-1.

**Why it happens:** Phase 106 D-06 specified "one row per encounter+medication" grain. Collapsing to date grain means one row per patient+date regardless of how many medications or encounters.

**How to avoid:** Update R/88 validation section to remove or reverse the row count assertion. Update log messages to reflect new grain. Document the expected relationship: TABLE-2 rows ≈ unique patient+date combinations in chemo encounters.

**Warning signs:** R/88 smoke test fails with "TABLE-2 should have more rows than TABLE-1" assertion error.

### Pitfall 4: Sorting After Collapse Instead of Before

**What goes wrong:** `sort(paste(x, collapse = ","))` sorts the collapsed STRING alphabetically character-by-character, not the individual values.

```r
# WRONG: Sorts "Doxorubicin,Vincristine,Bleomycin" as a single string → ",,,,Bbcccdeiiilmnnnooorrsuxy..."
agents = sort(paste(unique(medication_name), collapse = ","))

# RIGHT: Sorts individual medications, THEN collapses → "Bleomycin,Doxorubicin,Vincristine"
agents = paste(sort(unique(medication_name)), collapse = ",")
```

**Why it happens:** Misunderstanding of R's evaluation order — sort() sees the single collapsed string, not the vector of medications.

**How to avoid:** Always structure as `paste(sort(unique(x)), collapse = ",")` — unique first, sort second, paste last.

**Warning signs:** Collapsed strings appear scrambled or character-sorted instead of word-sorted.

### Pitfall 5: Merging cancer_codes Without Proper Split

**What goes wrong:** `cancer_codes` column in chemo_detail is already comma-separated (from R/36 Section 3 line 156). Naive `paste(unique(cancer_codes), collapse = ",")` deduplicates the ENTIRE STRING, not individual codes.

```r
# Input rows:
# Row 1: cancer_codes = "C81.00,C81.10"
# Row 2: cancer_codes = "C81.10,C81.20"

# WRONG: Treats each string as atomic
paste(unique(cancer_codes), collapse = ",")
# Result: "C81.00,C81.10,C81.10,C81.20" (duplicate C81.10)

# RIGHT: Split, union, deduplicate, re-collapse
paste(sort(unique(unlist(strsplit(cancer_codes, ",")))), collapse = ",")
# Result: "C81.00,C81.10,C81.20"
```

**Why it happens:** Input data is already partially aggregated (per encounter), and Phase 111 needs to aggregate AGAIN (per date). String-of-strings requires split before union.

**How to avoid:** For cancer_codes and cancer_category_names columns, use `unlist(strsplit(x, ","))` to flatten before unique(). Test with sample data where multiple encounters share a date but have overlapping cancer codes.

**Warning signs:** Duplicate cancer codes in final output; smoke test shows more codes than expected.

## Code Examples

Verified patterns adapted from R/36 existing code:

### Date-Grain Agent Collapse (Primary Transformation)

```r
# Source: R/36 Section 5 (modified from per-encounter to per-date grain)
# Adapts existing R/36 Section 3 line 156 pattern for medication names

# INPUT: chemo_detail (per-encounter+medication grain)
# Columns: patient_id, ENCOUNTERID, treatment_date, medication_name, cancer_codes, cancer_category_names

# OUTPUT: table2 (per-patient+date grain)
# Columns: PATID, treatment_date, agents, cancer_codes, cancer_category_names

table2 <- chemo_detail %>%
  group_by(patient_id, treatment_date) %>%
  summarise(
    # Collapse medication names into comma-separated string
    agents = paste(sort(unique(na.omit(medication_name))), collapse = ","),

    # Merge cancer codes across encounters — split existing strings, union, collapse
    cancer_codes = {
      all_codes <- unlist(strsplit(cancer_codes[!is.na(cancer_codes)], ","))
      if(length(all_codes) == 0) NA_character_ else paste(sort(unique(all_codes)), collapse = ",")
    },

    # Merge cancer category names — same pattern
    cancer_category_names = {
      all_cats <- unlist(strsplit(cancer_category_names[!is.na(cancer_category_names)], ","))
      if(length(all_cats) == 0) NA_character_ else paste(sort(unique(all_cats)), collapse = ",")
    },

    .groups = "drop"
  ) %>%
  rename(PATID = patient_id) %>%
  arrange(PATID, treatment_date)
```

**Alternative simpler approach (if cancer_codes already deduplicated per encounter):**

```r
table2 <- chemo_detail %>%
  group_by(patient_id, treatment_date) %>%
  summarise(
    agents = paste(sort(unique(na.omit(medication_name))), collapse = ","),
    cancer_codes = paste(sort(unique(cancer_codes[!is.na(cancer_codes)])), collapse = ","),
    cancer_category_names = paste(sort(unique(cancer_category_names[!is.na(cancer_category_names)])), collapse = ","),
    .groups = "drop"
  ) %>%
  rename(PATID = patient_id) %>%
  arrange(PATID, treatment_date)
```

**Testing note:** Try simpler approach first. If smoke test or manual inspection shows duplicate codes, fall back to split-union pattern.

### Logging the Grain Transformation

```r
# Source: R/36 Section 2 logging pattern + Phase 109 date-grain messaging

# BEFORE aggregation (per-encounter+medication grain)
message(glue("  Chemo detail rows (with triggering_code): {nrow(chemo_detail)}"))
message(glue("  Unique encounters: {n_distinct(chemo_detail$ENCOUNTERID)}"))
message(glue("  Unique patient-dates: {n_distinct(paste(chemo_detail$patient_id, chemo_detail$treatment_date))}"))

# AFTER aggregation (per-patient+date grain)
message(glue("  TABLE-2 rows (patient-date grain): {nrow(table2)}"))
message(glue("  TABLE-2 unique patients: {n_distinct(table2$PATID)}"))
message(glue("  TABLE-2 unique dates: {n_distinct(table2$treatment_date)}"))
message(glue("  TABLE-2 unique medications (deduplicated): {n_distinct(unlist(strsplit(table2$agents, ',')))}"))
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Encounter-grain analysis | Date-grain analysis | Phase 109 (2026-06-18) | Encounter IDs are billing artifacts; dates are clinically meaningful units. Phase 111 extends this philosophy to TABLE-2. |
| Per-medication rows in TABLE-2 | Collapsed agents per patient+date | Phase 111 (this phase) | Reduces row count, simplifies Tableau pivoting for date-level drug combination views |
| dplyr 1.0.x `summarise()` warnings | dplyr 1.1.0+ `.groups = "drop"` explicit | dplyr 1.1.0 (Feb 2023) | Must explicitly set `.groups` argument to avoid warnings about grouped output |

**Deprecated/outdated:**
- `summarise_all()` with `funs()`: Superseded by `across()` in dplyr 1.0.0 (May 2020). Not needed for Phase 111 (single-column aggregations).
- `group_by() %>% do()`: Deprecated in favor of `summarise()` with arbitrary expressions.

## Open Questions

1. **Should cancer_codes use simple unique() or split-union pattern?**
   - What we know: R/36 Section 3 line 156 already deduplicates cancer codes per encounter. Multiple encounters on the same date may have overlapping codes.
   - What's unclear: Whether the existing per-encounter deduplication is sufficient, or whether merging at date grain creates duplicates.
   - Recommendation: Start with simple `unique(cancer_codes)` approach. If testing shows duplicates (e.g., "C81.10,C81.10" in final output), switch to split-union pattern. Log both before/after unique counts to detect this.

2. **How should R/88 smoke test validate the new column structure?**
   - What we know: R/88 currently validates R/36 outputs (lines shown in earlier grep). Column structure changes (drops ENCOUNTERID, drug_class, treatment_type; adds agents).
   - What's unclear: Whether to keep lenient validation (file exists + has expected columns) or add strict checks (row count bounds, no duplicate agents within a row).
   - Recommendation: Update R/88 to check for new columns (PATID, treatment_date, agents, cancer_codes, cancer_category_names) and REMOVE checks for dropped columns. Add check that agents column contains no duplicate medication names within a single comma-separated string.

3. **What's the expected row count ratio between new TABLE-2 and TABLE-1?**
   - What we know: Old TABLE-2 (per-encounter+medication) had MORE rows than TABLE-1 (per-encounter) because multiple medications per encounter. New TABLE-2 (per-patient+date) likely has FEWER rows than TABLE-1.
   - What's unclear: Exact expected ratio. Depends on how many treatment encounters share the same patient+date.
   - Recommendation: Log both row counts and the ratio during R/36 execution. Update R/88 to validate TABLE-2 rows < TABLE-1 rows (or remove the row count comparison entirely).

## Environment Availability

Phase 111 is purely code/config changes with no external dependencies beyond existing R/36 environment. All required packages (dplyr, stringr, glue, openxlsx2) already installed and validated in Phase 106.

**SKIPPED:** No external tools, services, runtimes, or databases required beyond what's already in use.

## Validation Architecture

SKIPPED: `workflow.nyquist_validation` is explicitly set to `false` in `.planning/config.json`.

## Sources

### Primary (HIGH confidence)
- R/36 Section 3 lines 151-158 — Existing cancer code aggregation pattern using `group_by()` + `summarise()` + `paste(sort(unique()), collapse = ",")`
- R/36 Section 5 lines 274-320 — Current TABLE-2 build logic to be modified
- Phase 106 CONTEXT.md — Original TABLE-2 decisions (D-04, D-05, D-06) being modified by Phase 111
- Phase 109 CONTEXT.MD — Date-grain philosophy and precedent (D-03, D-04)
- dplyr official documentation — [summarise reference](https://dplyr.tidyverse.org/reference/summarise.html)
- CLAUDE.md STACK.md — Project's tidyverse version constraints and anti-patterns

### Secondary (MEDIUM confidence)
- [R: How to Collapse Text by Group in Data Frame](https://www.statology.org/r-collapse-text-by-group/)
- [How to Collapse Text by Group in a Data Frame Using R | R-bloggers](https://www.r-bloggers.com/2024/05/how-to-collapse-text-by-group-in-a-data-frame-using-r/)
- [dplyr distinct() Function: A Deep Practical Guide](https://thelinuxcode.com/r-dplyr-distinct-function-a-deep-practical-guide-to-reliable-deduplication/)
- [R dplyr group_by() + summarise() in R](https://r-statistics.co/dplyr-group-by-summarise.html)
- [Grouping data – The Epidemiologist R Handbook](https://epirhandbook.com/en/new_pages/grouping.html)

### Tertiary (LOW confidence)
- NA handling in paste() — GitHub issue [vctrs #39](https://github.com/r-lib/vctrs/issues/39) discusses NA behavior, but base R `na.omit()` is standard solution

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — All packages already in use, no new dependencies
- Architecture: HIGH — Exact pattern already exists in R/36 Section 3, directly reusable
- Pitfalls: HIGH — Verified via existing codebase patterns and dplyr official docs
- Code examples: HIGH — Adapted from working R/36 code (lines 151-158, 274-320)

**Research date:** 2026-06-18
**Valid until:** 90 days (2026-09-16) — dplyr aggregation patterns are stable; no fast-moving dependencies
