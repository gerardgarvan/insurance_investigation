# Phase 21: Generalize Phase 19 to All Sources - Research

**Researched:** 2026-04-13
**Domain:** R tidyverse grouped data operations, cross-site diagnostic patterns
**Confidence:** HIGH

## Summary

Phase 21 extends the Phase 19 UF-specific payer missingness investigation to all five partner sites (AMS, UMI, FLM, VRT, UFH) in the OneFlorida+ HL cohort. The technical approach is straightforward: replace Phase 19's `filter(SOURCE == "UFH")` with `group_by(SOURCE)` across all five missingness breakdowns, producing combined CSVs with a SOURCE column for cross-site comparison.

The research confirms that:
1. **Pattern exists**: Phase 19's `R/18_uf_insurance_missingness.R` (379 lines, 8 sections) provides a complete reference implementation
2. **Generalization is mechanical**: Adding `group_by(SOURCE)` to each of the 5 breakdown sections (raw value distribution, by year, by encounter type, year×type crosstab, raw vs harmonized) produces the required multi-site output
3. **Infrastructure is ready**: `pcornet$DEMOGRAPHIC` contains SOURCE column with all 5 partner identifiers; missingness definition and logging patterns are established
4. **Script number is known**: Next available is `R/20_all_source_missingness.R` (script 19 exists for Phase 20 FLM duplicates)

**Primary recommendation:** Create `R/20_all_source_missingness.R` by adapting Phase 19's script structure with `group_by(SOURCE)` replacing the UFH filter, producing 5 combined CSVs plus a cross-site summary CSV with one row per site.

## User Constraints (from 21-CONTEXT.md)

### Locked Decisions

**Cross-site Comparison**
- **D-01:** Single combined CSVs with a SOURCE column — all sites in the same file per breakdown type (not separate per-site CSVs)
- **D-02:** Include an additional cross-site summary CSV with one row per site showing overall missingness rates, enabling head-to-head comparison at a glance
- **D-03:** Numbers only in the summary — no severity flags or interpretation columns. Let the user interpret the rates

**Analysis Scope**
- **D-04:** Same 5 breakdowns as Phase 19: raw value distribution, by year, by encounter type, year×type crosstab, raw vs harmonized — just add SOURCE as a grouping dimension
- **D-05:** HL cohort patients only (same population as Phase 19). Do not analyze all patients per site

**Script Design**
- **D-06:** New standalone script (next available number, e.g., `R/20_all_source_missingness.R`). Phase 19's `R/18_uf_insurance_missingness.R` stays unchanged
- **D-07:** Single grouped pass using `dplyr::group_by(SOURCE)` for all breakdowns — no site-by-site loop. Natural tidyverse pattern
- **D-08:** Reuse Phase 19 missingness definition: NA, empty string, NI, UN, OT, 99, 9999 (from PAYER_MAPPING$sentinel_values + PAYER_MAPPING$unavailable_codes)

**Output Structure**
- **D-09:** CSV file naming uses `all_source_` prefix, mirroring Phase 19's `uf_` prefix: `all_source_payer_raw_value_distribution.csv`, `all_source_payer_missingness_by_year.csv`, etc.
- **D-10:** Console output: per-site summary of overall missingness rates plus a final cross-site comparison. Enough to review in HiPerGator terminal without opening CSVs
- **D-11:** CSV output to `output/tables/` — consistent with existing pipeline pattern

### Claude's Discretion

- Exact script number (next available after existing scripts) — **RESOLVED: R/20_all_source_missingness.R**
- Cross-site summary CSV column structure and exact columns
- Console output formatting and which per-site stats to highlight
- How to handle sites with very few encounters (if any)
- Whether to include an "ALL" aggregate row in each breakdown CSV

## Standard Stack

All libraries already in use — no new dependencies.

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| dplyr | 1.2.0+ | Data grouping and summarization | `group_by(SOURCE)` is the natural pattern for multi-site analysis; `summarise()` handles per-group aggregation |
| glue | 1.8.0 | String formatting | Already used in Phase 19 for console logging messages |
| readr | 2.2.0+ | CSV I/O | `write_csv()` for all output files |
| lubridate | 1.9.3+ | Date operations | Extract year from ADMIT_DATE for temporal breakdowns |
| stringr | 1.5.1+ | String operations | Trimming whitespace in missingness detection logic |
| tidyr | 1.3.0+ | Data reshaping | `bind_rows()` for combining PRIMARY/SECONDARY distributions |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| janitor | 2.2.1+ | Optional crosstab formatting | If using `tabyl()` for quick verification during development |

**Installation:**

No installation needed — all packages already in `renv.lock` from prior phases.

**Version verification:**

Versions already verified in Phase 1 (LOAD-01 to LOAD-03) and confirmed in `renv.lock`.

## Architecture Patterns

### Recommended Project Structure

Phase 21 follows the standalone diagnostic script pattern established in Phase 19 and Phase 20:

```
R/
├── 00_config.R              # PAYER_MAPPING config with sentinel_values, unavailable_codes
├── 01_load_pcornet.R        # Loads pcornet$ENCOUNTER, pcornet$DEMOGRAPHIC (provides SOURCE)
├── 02_harmonize_payer.R     # Provides encounters tibble with payer_category
├── 18_uf_insurance_missingness.R   # Phase 19 reference implementation (UFH only)
├── 19_flm_duplicate_dates.R        # Phase 20 diagnostic script
└── 20_all_source_missingness.R     # Phase 21 NEW — generalized to all sources
```

Standalone scripts source their dependencies (`source("R/02_harmonize_payer.R")`) and produce CSV output to `output/tables/`.

### Pattern 1: Grouped Multi-Site Analysis

**What:** Replace single-site filter with multi-group summarization

**When to use:** When extending a site-specific analysis to all sites without changing logic

**Example:**

```r
# Phase 19 pattern (UFH only):
ufh_encounters <- pcornet$ENCOUNTER %>%
  inner_join(ufh_patients, by = "ID") %>%
  mutate(primary_missing = is.na(PAYER_TYPE_PRIMARY) | ...)

missingness_by_year <- ufh_encounters_valid %>%
  group_by(admit_year) %>%
  summarise(
    n_encounters = n(),
    n_primary_missing = sum(primary_missing),
    pct_primary_missing = round(100 * n_primary_missing / n_encounters, 1),
    .groups = "drop"
  )

# Phase 21 pattern (all sources):
# No need to filter to specific SOURCE — use all HL cohort patients
all_encounters <- pcornet$ENCOUNTER %>%
  inner_join(hl_patients, by = "ID") %>%  # HL cohort, not site-filtered
  left_join(pcornet$DEMOGRAPHIC %>% select(ID, SOURCE), by = "ID") %>%
  mutate(primary_missing = is.na(PAYER_TYPE_PRIMARY) | ...)

missingness_by_year_and_source <- all_encounters_valid %>%
  group_by(SOURCE, admit_year) %>%  # Add SOURCE to grouping
  summarise(
    n_encounters = n(),
    n_primary_missing = sum(primary_missing),
    pct_primary_missing = round(100 * n_primary_missing / n_encounters, 1),
    .groups = "drop"
  )
```

**Source:** Adapted from Phase 19 script structure with official dplyr grouped data pattern ([dplyr grouped data documentation](https://dplyr.tidyverse.org/articles/grouping.html))

### Pattern 2: Cross-Site Summary Aggregation

**What:** Produce a summary CSV with one row per site for head-to-head comparison

**When to use:** When decision D-02 requires a cross-site comparison table

**Example:**

```r
# Compute overall missingness rate per site (across all years/encounter types)
cross_site_summary <- all_encounters %>%
  group_by(SOURCE) %>%
  summarise(
    n_patients = n_distinct(ID),
    n_encounters = n(),
    n_primary_missing = sum(primary_missing),
    pct_primary_missing = round(100 * n_primary_missing / n_encounters, 1),
    n_secondary_missing = sum(secondary_missing),
    pct_secondary_missing = round(100 * n_secondary_missing / n_encounters, 1),
    n_both_missing = sum(both_missing),
    pct_both_missing = round(100 * n_both_missing / n_encounters, 1),
    .groups = "drop"
  ) %>%
  arrange(SOURCE)

write_csv(cross_site_summary, file.path(output_dir, "all_source_cross_site_summary.csv"))
```

**Source:** Standard dplyr aggregation pattern

### Pattern 3: Missingness Flag Definition

**What:** Reuse Phase 19's missingness logic exactly (D-08)

**Example:**

```r
# From Phase 19 (R/18_uf_insurance_missingness.R Section 2)
missing_indicators <- c(PAYER_MAPPING$sentinel_values, PAYER_MAPPING$unavailable_codes)
# c("NI", "UN", "OT", "99", "9999")

all_encounters <- all_encounters %>%
  mutate(
    primary_missing = is.na(PAYER_TYPE_PRIMARY) |
                      nchar(trimws(PAYER_TYPE_PRIMARY)) == 0 |
                      PAYER_TYPE_PRIMARY %in% missing_indicators,
    secondary_missing = is.na(PAYER_TYPE_SECONDARY) |
                        nchar(trimws(PAYER_TYPE_SECONDARY)) == 0 |
                        PAYER_TYPE_SECONDARY %in% missing_indicators,
    both_missing = primary_missing & secondary_missing
  )
```

**Source:** `R/18_uf_insurance_missingness.R` Section 2

### Pattern 4: Console Logging for Per-Site Summary

**What:** Log each site's overall missingness rate to console for quick HiPerGator review (D-10)

**Example:**

```r
message("\n--- Per-Site Missingness Summary ---")
for (i in seq_len(nrow(cross_site_summary))) {
  r <- cross_site_summary[i, ]
  message(glue("{r$SOURCE}: {format(r$n_primary_missing, big.mark=',')}/{format(r$n_encounters, big.mark=',')} ({r$pct_primary_missing}%) PRIMARY missing"))
}
```

**Source:** Phase 19 logging pattern (Section 8)

### Anti-Patterns to Avoid

- **Site-by-site loop:** Don't loop over each SOURCE value and filter separately — use `group_by(SOURCE)` for all operations (violates D-07)
- **Separate CSVs per site:** Don't write 5 separate files per breakdown — use single combined CSV with SOURCE column (violates D-01)
- **Changing missingness definition:** Don't introduce new missing indicators — reuse Phase 19's exact logic (violates D-08)
- **Filtering to HL cohort inconsistently:** Phase 19 used UFH patients only because it was UF-specific. Phase 21 should use ALL HL cohort patients (from all sites) but group by SOURCE. Don't filter to a subset.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Multi-site aggregation | Manual loops over SOURCE values | `dplyr::group_by(SOURCE)` | Handles all combinations automatically, cleaner code, matches tidyverse style |
| Console summary formatting | String concatenation with paste0() | `glue::glue()` | Established pattern in Phase 19; more readable |
| Combined PRIMARY/SECONDARY distribution | Separate processing then manual merge | `bind_rows()` with `field` column | Pattern from Phase 19 Section 3 |

**Key insight:** Phase 19 already solved all the hard problems (missingness definition, console logging, CSV structure). Phase 21 is a mechanical generalization adding `group_by(SOURCE)`.

## Common Pitfalls

### Pitfall 1: Forgetting to Join SOURCE Column

**What goes wrong:** `pcornet$ENCOUNTER` does not contain SOURCE — must join from `pcornet$DEMOGRAPHIC`

**Why it happens:** Phase 19 joined UFH patients from DEMOGRAPHIC, but the pattern may be less obvious when not filtering by SOURCE

**How to avoid:** Always `left_join(pcornet$DEMOGRAPHIC %>% select(ID, SOURCE), by = "ID")` after joining encounters to cohort patients

**Warning signs:** Error: "object 'SOURCE' not found" or SOURCE column full of NAs

**Example:**

```r
# WRONG: SOURCE not in ENCOUNTER table
all_encounters <- pcornet$ENCOUNTER %>%
  inner_join(hl_patients, by = "ID") %>%
  group_by(SOURCE)  # ERROR: SOURCE doesn't exist

# RIGHT: Join SOURCE from DEMOGRAPHIC
all_encounters <- pcornet$ENCOUNTER %>%
  inner_join(hl_patients, by = "ID") %>%
  left_join(pcornet$DEMOGRAPHIC %>% select(ID, SOURCE), by = "ID") %>%
  group_by(SOURCE)
```

**Source:** Confirmed by examining Phase 19 Section 1 and `00_config.R` line 107 comment

### Pitfall 2: .groups Argument Confusion with Nested Grouping

**What goes wrong:** When grouping by `SOURCE, admit_year`, `summarise()` auto-ungroups only the last group (admit_year), leaving SOURCE grouped — can cause unexpected behavior in subsequent operations

**Why it happens:** dplyr default behavior since v1.0.0 is `.groups = "drop_last"`

**How to avoid:** Always specify `.groups = "drop"` explicitly in `summarise()` calls to fully ungroup

**Warning signs:** Subsequent operations produce one result per SOURCE instead of overall; group structure warnings

**Example:**

```r
# POTENTIAL ISSUE: Implicit grouping retained
missingness_by_year_and_source <- all_encounters_valid %>%
  group_by(SOURCE, admit_year) %>%
  summarise(n_encounters = n())  # Still grouped by SOURCE after this

# SAFE: Explicit ungrouping
missingness_by_year_and_source <- all_encounters_valid %>%
  group_by(SOURCE, admit_year) %>%
  summarise(
    n_encounters = n(),
    .groups = "drop"  # Fully ungrouped
  )
```

**Source:** [dplyr grouped data documentation](https://dplyr.tidyverse.org/articles/grouping.html), [group_by reference](https://dplyr.tidyverse.org/reference/group_by.html)

### Pitfall 3: NA ENC_TYPE Handling Inconsistency

**What goes wrong:** Filtering out `is.na(ENC_TYPE)` silently excludes encounters without type classification — missingness becomes invisible

**Why it happens:** Default `group_by()` drops NA groups unless explicitly preserved

**How to avoid:** Convert NA to explicit `"<NA>"` label before grouping (Phase 19 pattern from Section 5)

**Warning signs:** Encounter counts don't match expected totals; missingness percentages don't add up

**Example:**

```r
# From Phase 19 Section 5:
all_encounters_valid <- all_encounters_valid %>%
  mutate(ENC_TYPE_LABEL = if_else(is.na(ENC_TYPE), "<NA>", ENC_TYPE))

# Then group by ENC_TYPE_LABEL, not ENC_TYPE
```

**Source:** `R/18_uf_insurance_missingness.R` Section 5 lines 193-194

### Pitfall 4: HL Cohort Identification

**What goes wrong:** Incorrectly filtering to all patients in pcornet dataset instead of HL cohort only (violates D-05)

**Why it happens:** Phase 19 had `ufh_patients` from DEMOGRAPHIC filter — Phase 21 needs HL cohort patients

**How to avoid:** Source `R/04_build_cohort.R` to get `hl_cohort`, or define HL patients via DIAGNOSIS/TUMOR_REGISTRY joins

**Warning signs:** Patient counts much higher than Phase 19 total cohort (~2000-3000 HL patients)

**Example:**

```r
# Option 1: Source cohort script (heavy — loads full pipeline)
source("R/04_build_cohort.R")
hl_patients <- hl_cohort %>% select(ID) %>% distinct()

# Option 2: Lightweight HL identification from DEMOGRAPHIC + HL_SOURCE logic
# (Requires understanding Phase 6 HL_SOURCE logic — more complex)

# Then join to encounters:
all_encounters <- pcornet$ENCOUNTER %>%
  inner_join(hl_patients, by = "ID") %>%
  left_join(pcornet$DEMOGRAPHIC %>% select(ID, SOURCE), by = "ID")
```

**Source:** Inferred from D-05 requirement and Phase 19 context

## Code Examples

Verified patterns from Phase 19 reference implementation:

### Section 1: Identify All HL Patients (Multi-Site)

```r
# Source: Adapted from R/18_uf_insurance_missingness.R Section 1
# Phase 19 filtered to UFH only; Phase 21 uses all HL cohort patients

# Lightweight approach if hl_cohort already loaded:
hl_patients <- hl_cohort %>%
  select(ID) %>%
  distinct()

# If hl_cohort not loaded, source it:
if (!exists("hl_cohort")) source("R/04_build_cohort.R")

message(glue("HL patients in dataset: {format(nrow(hl_patients), big.mark=',')}"))
```

### Section 2: Build Multi-Site Encounter Dataset with Missingness Flags

```r
# Source: R/18_uf_insurance_missingness.R Section 2
# Changes: Join SOURCE from DEMOGRAPHIC, no site filter

missing_indicators <- c(PAYER_MAPPING$sentinel_values, PAYER_MAPPING$unavailable_codes)
message(glue("Missing indicators: {paste(missing_indicators, collapse=', ')}"))

all_encounters <- pcornet$ENCOUNTER %>%
  inner_join(hl_patients, by = "ID") %>%
  left_join(pcornet$DEMOGRAPHIC %>% select(ID, SOURCE), by = "ID") %>%
  mutate(
    primary_missing = is.na(PAYER_TYPE_PRIMARY) |
                      nchar(trimws(PAYER_TYPE_PRIMARY)) == 0 |
                      PAYER_TYPE_PRIMARY %in% missing_indicators,
    secondary_missing = is.na(PAYER_TYPE_SECONDARY) |
                        nchar(trimws(PAYER_TYPE_SECONDARY)) == 0 |
                        PAYER_TYPE_SECONDARY %in% missing_indicators,
    both_missing = primary_missing & secondary_missing
  )
```

### Section 3: Raw Value Distribution Grouped by SOURCE

```r
# Source: R/18_uf_insurance_missingness.R Section 3
# Changes: Add SOURCE to grouping

primary_dist <- all_encounters %>%
  group_by(SOURCE, PAYER_TYPE_PRIMARY) %>%
  summarise(n = n(), .groups = "drop") %>%
  group_by(SOURCE) %>%
  mutate(pct = round(100 * n / sum(n), 1)) %>%
  ungroup()

secondary_dist <- all_encounters %>%
  group_by(SOURCE, PAYER_TYPE_SECONDARY) %>%
  summarise(n = n(), .groups = "drop") %>%
  group_by(SOURCE) %>%
  mutate(pct = round(100 * n / sum(n), 1)) %>%
  ungroup()

raw_value_dist <- bind_rows(
  primary_dist %>%
    rename(value = PAYER_TYPE_PRIMARY) %>%
    mutate(field = "PRIMARY"),
  secondary_dist %>%
    rename(value = PAYER_TYPE_SECONDARY) %>%
    mutate(field = "SECONDARY")
) %>%
  mutate(value = if_else(is.na(value), "<NA>", value)) %>%
  select(SOURCE, field, value, n, pct) %>%
  arrange(SOURCE, field, desc(n))

write_csv(raw_value_dist, file.path(output_dir, "all_source_payer_raw_value_distribution.csv"))
```

### Section 4: Temporal Breakdown Grouped by SOURCE and Year

```r
# Source: R/18_uf_insurance_missingness.R Section 4
# Changes: Add SOURCE to grouping

all_encounters_valid <- all_encounters %>%
  filter(!is.na(ADMIT_DATE) & year(ADMIT_DATE) != 1900L) %>%
  mutate(admit_year = year(ADMIT_DATE))

missingness_by_year_and_source <- all_encounters_valid %>%
  group_by(SOURCE, admit_year) %>%
  summarise(
    n_encounters = n(),
    n_primary_missing = sum(primary_missing),
    n_secondary_missing = sum(secondary_missing),
    n_both_missing = sum(both_missing),
    pct_primary_missing = round(100 * n_primary_missing / n_encounters, 1),
    pct_secondary_missing = round(100 * n_secondary_missing / n_encounters, 1),
    pct_both_missing = round(100 * n_both_missing / n_encounters, 1),
    .groups = "drop"
  ) %>%
  arrange(SOURCE, admit_year)

write_csv(missingness_by_year_and_source, file.path(output_dir, "all_source_payer_missingness_by_year.csv"))
```

### Section 8 Addition: Cross-Site Summary CSV (D-02)

```r
# NEW for Phase 21 — not in Phase 19
# Per D-02: One row per site with overall missingness rates

cross_site_summary <- all_encounters %>%
  group_by(SOURCE) %>%
  summarise(
    n_patients = n_distinct(ID),
    n_encounters = n(),
    n_primary_missing = sum(primary_missing),
    pct_primary_missing = round(100 * n_primary_missing / n_encounters, 1),
    n_secondary_missing = sum(secondary_missing),
    pct_secondary_missing = round(100 * n_secondary_missing / n_encounters, 1),
    n_both_missing = sum(both_missing),
    pct_both_missing = round(100 * n_both_missing / n_encounters, 1),
    .groups = "drop"
  ) %>%
  arrange(SOURCE)

write_csv(cross_site_summary, file.path(output_dir, "all_source_cross_site_summary.csv"))

# Console output (D-10)
message("\n--- Cross-Site Missingness Summary ---")
for (i in seq_len(nrow(cross_site_summary))) {
  r <- cross_site_summary[i, ]
  message(glue("{r$SOURCE}: {format(r$n_primary_missing, big.mark=',')}/{format(r$n_encounters, big.mark=',')} ({r$pct_primary_missing}%) PRIMARY missing"))
}
```

## State of the Art

No breaking changes or deprecations — Phase 21 uses the same dplyr 1.2.0+ patterns as Phase 19.

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `.groups = "drop_last"` (default) | Explicit `.groups = "drop"` | dplyr 1.0.0 (May 2020) | Always specify to avoid grouped surprises |
| `group_by() %>% filter()` | No change | N/A | Still best practice for site-specific analysis |

**Deprecated/outdated:**

None — all Phase 19 patterns remain current.

## Open Questions

1. **Should the cross-site summary CSV include an "ALL" aggregate row?**
   - What we know: D-02 requires per-site summary. D-03 says numbers only, no interpretation.
   - What's unclear: Whether an overall aggregate row (SOURCE = "ALL") aids comparison or adds clutter.
   - Recommendation: Include it as the last row for convenience. Easy to ignore if not needed. Format: `bind_rows(cross_site_summary, overall_row %>% mutate(SOURCE = "ALL"))`

2. **How to handle sites with very few HL patients?**
   - What we know: Phase 19 had ~1,000s of UFH encounters. Some sites (AMS, UMI, FLM, VRT) may have <100 patients.
   - What's unclear: Should low-N sites be flagged in console output or treated identically?
   - Recommendation: Log N patients per site in console summary. Let user decide if small-N sites are interpretable. No suppression logic needed (D-03: user interprets).

3. **Do we need HIPAA suppression for per-site breakdowns?**
   - What we know: HIPAA small-cell suppression (counts 1-10) applied to PPTX outputs. Phase 19 diagnostic script had no suppression.
   - What's unclear: Whether cross-site summary with site-level counts requires suppression.
   - Recommendation: No suppression. This is an internal diagnostic script (like Phase 19), not publication output. If site has <11 patients, that's valuable diagnostic information.

## Environment Availability

Phase 21 has no external dependencies beyond R packages already installed in `renv.lock`. All work happens within the existing HiPerGator R environment.

**Skipped:** No external tools, databases, or services required.

## Sources

### Primary (HIGH confidence)
- `C:\Users\Owner\Documents\insurance_investigation\R\18_uf_insurance_missingness.R` - Phase 19 reference implementation (379 lines, 8 sections)
- `C:\Users\Owner\Documents\insurance_investigation\.planning\phases\19-investigate-insurance-missingness-source-uf-specifically\19-CONTEXT.md` - Phase 19 decisions D-01 to D-14
- `C:\Users\Owner\Documents\insurance_investigation\.planning\phases\21-generalize-phase-19-to-all-sources\21-CONTEXT.md` - Phase 21 decisions D-01 to D-11
- `C:\Users\Owner\Documents\insurance_investigation\R\00_config.R` - PAYER_MAPPING config, SOURCE column comment (line 107)
- `C:\Users\Owner\Documents\insurance_investigation\R\02_harmonize_payer.R` - Payer harmonization, encounters tibble
- [dplyr grouped data documentation](https://dplyr.tidyverse.org/articles/grouping.html) - Official reference for `group_by()` behavior
- [group_by reference](https://dplyr.tidyverse.org/reference/group_by.html) - Official API documentation
- [summarise reference](https://dplyr.tidyverse.org/reference/summarise.html) - Official API documentation for `.groups` argument

### Secondary (MEDIUM confidence)
- [Andrew Heiss dplyr animations](https://www.andrewheiss.com/blog/2024/04/04/group_by-summarize-ungroup-animations/) - Visualization of grouped operations
- [Statology group by multiple columns](https://www.statology.org/group-by-multiple-columns-in-r/) - Tutorial on multi-column grouping

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All packages already in use, versions verified in Phase 1
- Architecture: HIGH - Phase 19 provides complete reference implementation; generalization is mechanical
- Pitfalls: HIGH - Derived directly from Phase 19 code patterns and dplyr official documentation
- HL cohort identification: MEDIUM - Requires sourcing `R/04_build_cohort.R` or reimplementing HL logic; not fully specified in Phase 19

**Research date:** 2026-04-13
**Valid until:** 2026-05-13 (30 days, stable domain)
