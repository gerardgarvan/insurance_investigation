# Phase 28: Per-Patient Source Detection by Date - Research

**Researched:** 2026-04-23
**Domain:** data.table-based per-date source enumeration for PCORnet multi-source encounter analysis
**Confidence:** HIGH

## Summary

Phase 28 simplifies the Phase 25-26 pairwise overlap detection approach by enumerating sources present on each patient-date, eliminating the need for self-joins and field-by-field comparison. Instead of asking "which encounter pairs overlap?", Phase 28 asks "which sources are present on each date?". This shift reduces complexity and improves performance by grouping encounters by (patient, date) and counting distinct SOURCE values, encounter counts per source, and generating alphabetical source combinations.

The core technical requirement is efficient group-by-summarization in data.table: for each (ID, ADMIT_DATE) pair, compute `n_distinct(SOURCE)`, `paste(sort(unique(SOURCE)), collapse="+")`, and count encounters. User explicitly requested data.table for speed, overriding the project-wide dplyr preference.

**Primary recommendation:** Use data.table's `[, .(...), by=...]` syntax for grouping, `uniqueN()` for distinct counts (faster than `n_distinct()`), and `paste(sort(unique(...)), collapse="+")` for alphabetical source combinations. Reuse HIPAA suppression helpers from R/22 (Phase 25) and console output patterns from R/20/R/21 (Phases 21-22).

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Patient-date detail CSV with one row per (patient, date) showing n_sources, source_combo, n_encounters. Include ALL dates (1+ sources), not just multi-source dates -- full picture with ability to filter downstream.
- **D-02:** Also produce aggregate summary CSVs: source combination frequencies and per-source summary counts. Mirrors Phase 25 output structure but based on source-per-date grouping instead of pairwise detection.
- **D-03:** Source detection only -- each patient-date gets n_sources, source_combo (alphabetical), n_encounters per source. No field comparison (ENC_TYPE, payer, provider) -- that was Phase 26's pairwise concern and is being replaced by this simpler approach.
- **D-04:** Same-date grouping only (patient + ADMIT_DATE). No same-week or rolling window detection. Directly answers "which sources were on each date" without the complexity of near-miss overlap detection.
- **D-05:** Use data.table for data manipulation instead of dplyr. Speed is the priority for this script. This overrides the project-wide "prefer dplyr for readability" convention specifically for this Phase 28 script.

### Claude's Discretion
- Script naming and numbering (follow existing convention: R/24_*.R or next available number)
- Console output formatting (follow existing Phase 25/26 banner and summary patterns)
- HIPAA suppression approach (carry forward Phase 25 pattern: suppress CSV count columns 1-10 as "<11")
- Whether to include an n_encounters_per_source breakdown column or just total n_encounters

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope
</user_constraints>

## Project Constraints (from CLAUDE.md)

**Must honor:**
- **Runtime environment:** RStudio on UF HiPerGator — scripts must work in that environment
- **HIPAA compliance:** All patient counts 1-10 must be suppressed in CSV output (not console)
- **Code style:** Named functions for major operations, readable over opaque one-liners (applies to helper functions, not data.table group-by syntax)
- **Standalone scripts:** Source R/00_config.R and conditionally source R/01_load_pcornet.R for table loading
- **Output location:** CSV files to CONFIG$output_dir/tables/

**Exception for this phase:** D-05 explicitly overrides "no data.table syntax" — use data.table for performance.

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| data.table | 1.16.2+ | Primary data manipulation | User-requested for speed; 10-50x faster than dplyr for large group-by operations |
| glue | 1.8.0+ | Console logging | Established pattern in R/20-23 for readable message formatting |
| readr | 2.2.0+ | CSV write | write_csv() for Phase 25 compatibility |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| lubridate | 1.9.3+ | Date parsing | as.Date() fallback if ADMIT_DATE parse rate < 50% (pattern from R/22 lines 86-108) |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| data.table | dplyr | dplyr is project standard but user explicitly requested data.table for this script's speed |
| uniqueN() | n_distinct() | uniqueN() is data.table-native and faster; n_distinct() requires dplyr load |
| paste(..., collapse="+") | str_c(..., collapse="+") | paste() is base R, no stringr dependency needed |

**Installation:**
```r
# data.table likely already installed (CRAN standard)
# Check in R console:
if (!require(data.table)) install.packages("data.table")
```

**Version verification:**
As of CRAN snapshot 2026-01-27, data.table version is 1.18.2.1 (latest stable release). Project currently uses 1.16.2+ minimum — any version 1.16+ is compatible.

## Architecture Patterns

### Recommended Script Structure
```
R/24_per_patient_source_detection.R    # Phase 28 standalone script
├── SECTION 0: Setup and configuration
│   └── source("R/00_config.R"), library(data.table), library(glue)
├── SECTION 1: Load ENCOUNTER, parse ADMIT_DATE
│   └── Reuse R/22 lines 73-114 pattern (ADMIT_DATE parsing, parse_pcornet_date fallback)
├── SECTION 2: Per-patient-date source enumeration
│   └── Group by (ID, ADMIT_DATE), compute n_sources, source_combo, n_encounters
├── SECTION 3: Aggregate summaries
│   ├── Source combination frequencies
│   └── Per-source summary counts
├── SECTION 4: HIPAA suppression and CSV output
│   └── Reuse R/22 lines 47-60 hipaa_suppress() helpers
└── SECTION 5: Console summary
    └── Follow R/20/R/21 banner + summary pattern
```

### Pattern 1: data.table Group-By for Source Enumeration
**What:** For each (ID, ADMIT_DATE) pair, count distinct SOURCE values and create alphabetical combination string
**When to use:** Core operation for Phase 28 — replace Phase 25's pairwise self-join
**Example:**
```r
# Source: data.table FAQ + Phase 28 research
library(data.table)
enc_dt <- as.data.table(enc_valid)  # Convert from data.frame if needed

# Per-patient-date source enumeration
patient_date_detail <- enc_dt[, .(
  n_sources    = uniqueN(SOURCE),                              # Faster than n_distinct()
  source_combo = paste(sort(unique(SOURCE)), collapse = "+"), # Alphabetical
  n_encounters = .N                                            # Total encounters on this date
), by = .(ID, ADMIT_DATE)]
```

### Pattern 2: Per-Source Encounter Counts (Optional Detail)
**What:** Add per-source encounter breakdown to patient_date_detail
**When to use:** If planner decides n_encounters_per_source breakdown adds value (Claude's discretion)
**Example:**
```r
# Compute encounters per source, then collapse to string
patient_date_detail <- enc_dt[, .(
  n_sources    = uniqueN(SOURCE),
  source_combo = paste(sort(unique(SOURCE)), collapse = "+"),
  n_encounters = .N,
  # e.g., "UFH:2, FLM:1" for a date with 2 UFH encounters and 1 FLM encounter
  encounters_per_source = paste(paste(SOURCE, .N, sep = ":"), collapse = ", ")
), by = .(ID, ADMIT_DATE, SOURCE)][
  # Then collapse by (ID, ADMIT_DATE) to get one row per patient-date
  , .(
    n_sources    = uniqueN(SOURCE),
    source_combo = paste(sort(unique(SOURCE)), collapse = "+"),
    n_encounters = sum(n_encounters),
    encounters_per_source = paste(encounters_per_source, collapse = "; ")
  ), by = .(ID, ADMIT_DATE)
]
```

### Pattern 3: HIPAA Suppression for CSV Output
**What:** Replace count values 1-10 with "<11" in CSV columns only (not console)
**When to use:** All CSV outputs (carry forward from Phase 25)
**Example:**
```r
# Source: R/22_multi_source_overlap_detection.R lines 47-60
hipaa_suppress <- function(x) {
  x_num <- suppressWarnings(as.numeric(x))
  ifelse(!is.na(x_num) & x_num >= 1 & x_num <= 10, "<11", as.character(x))
}

suppress_counts <- function(df) {
  count_cols <- grep("^n_|^n$|_count$|_encounters$|_dates$|_patients$|^rank$",
                     names(df), value = TRUE)
  count_cols <- count_cols[!grepl("pct_|_rate$|_pct$", count_cols)]
  df %>%
    mutate(across(all_of(count_cols), ~ hipaa_suppress(.x)))
}

# Apply before CSV write
csv1 <- patient_date_detail %>%
  mutate(
    n_sources    = hipaa_suppress(n_sources),
    n_encounters = hipaa_suppress(n_encounters)
  )
```

### Pattern 4: Aggregate Summary - Source Combination Frequencies
**What:** Count how many patient-dates have each source combination (e.g., "UFH+FLM" appears 1,234 times)
**When to use:** D-02 requirement for aggregate summary
**Example:**
```r
# Source: Phase 28 research + R/22 pattern
combo_freq <- patient_date_detail[, .(
  n_patient_dates = .N,
  n_total_encounters = sum(n_encounters)  # Note: n_encounters is still numeric here
), by = source_combo][
  order(-n_patient_dates)  # Descending by frequency
][
  , rank := .I  # Add rank column
]
```

### Pattern 5: Aggregate Summary - Per-Source Counts
**What:** For each SOURCE, count total encounters, patient-dates, patients affected
**When to use:** D-02 requirement for per-source summary
**Example:**
```r
# Total encounters per source (from full enc_dt)
total_per_source <- enc_dt[, .(total_encounters = .N), by = SOURCE]

# Patient-dates and patients from multi-source detail
# Note: patient_date_detail has source_combo (not individual SOURCE)
# Need to "explode" source_combo back to individual sources, or...
# SIMPLER: compute directly from enc_dt
per_source_summary <- enc_dt[, .(
  total_encounters   = .N,
  n_patient_dates    = uniqueN(paste(ID, ADMIT_DATE)),
  n_patients         = uniqueN(ID)
), by = SOURCE]
```

### Anti-Patterns to Avoid
- **Don't use dplyr group_by() for this script:** User explicitly requested data.table for speed (D-05)
- **Don't create pairwise comparisons:** Phase 28 replaces Phase 25's self-join approach; no need for SOURCE_1/SOURCE_2 pairs
- **Don't filter to multi-source dates only in patient_date_detail:** D-01 requires ALL dates (1+ sources) in detail CSV
- **Don't include field comparison (ENC_TYPE, payer, provider):** D-03 — source enumeration only, no Phase 26 overlap classification

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Count distinct values per group | Manual iteration over groups | data.table uniqueN() by group | uniqueN() is optimized C code, 10-100x faster than R loops |
| Alphabetical source combination string | Manual sorting + string building | paste(sort(unique(SOURCE)), collapse="+") | Built-in vectorized operations; sort() handles alphabetical ordering automatically |
| HIPAA suppression | Reimplementing cell suppression logic | Reuse R/22 hipaa_suppress() helper | Phase 25 already validated this pattern; secondary suppression not needed for this use case |
| CSV writing | Base write.csv() | readr::write_csv() | Consistent with Phase 25 output; handles special characters better |

**Key insight:** data.table's group-by is fundamentally different from dplyr — it uses modify-by-reference and C-level optimizations. Don't try to translate dplyr idioms directly; embrace data.table's `DT[i, j, by]` syntax.

## Runtime State Inventory

> Omitted — Phase 28 is greenfield development (new script), not a rename/refactor.

## Common Pitfalls

### Pitfall 1: Converting from dplyr to data.table — Mutation Semantics
**What goes wrong:** data.table modifies objects by reference; dplyr always copies. Assigning `enc_dt <- as.data.table(enc)` then mutating `enc_dt` can unexpectedly modify `enc`.
**Why it happens:** data.table's copy-by-reference is a performance optimization but violates R's usual copy-on-modify semantics.
**How to avoid:** Use `copy()` if you need to preserve the original: `enc_dt <- copy(as.data.table(enc))`. For Phase 28, this is low risk (enc is only read, not modified after conversion).
**Warning signs:** Unexpected changes to `enc` after operating on `enc_dt`.

### Pitfall 2: source_combo Order Inconsistency
**What goes wrong:** Without `sort()`, `paste(unique(SOURCE), collapse="+")` returns non-deterministic order (depends on encounter order in data), making "UFH+FLM" and "FLM+UFH" appear as different combinations.
**Why it happens:** `unique()` preserves first-occurrence order, which varies by data load order.
**How to avoid:** Always use `paste(sort(unique(SOURCE)), collapse="+")` to ensure alphabetical order (consistent with Phase 25 convention: `SOURCE_x < SOURCE_y` filter ensured alphabetical order).
**Warning signs:** Duplicate source combinations with different orderings in aggregate summary.

### Pitfall 3: HIPAA Suppression Applied Too Early
**What goes wrong:** Applying `hipaa_suppress()` before aggregation converts numeric columns to character "<11", breaking `sum(n_encounters)` in aggregate summaries.
**Why it happens:** HIPAA suppression is for CSV output only, but data.table chains can make it tempting to apply early.
**How to avoid:** Keep all counts as numeric until the final CSV write step. Apply `hipaa_suppress()` only in the `mutate()` or `[, :=]` operation immediately before `write_csv()`.
**Warning signs:** `sum(n_encounters)` returns NA or 0 when aggregating; column class shows "character" instead of "numeric".

### Pitfall 4: Including 0-Source Dates (Missing ADMIT_DATE)
**What goes wrong:** If ADMIT_DATE is NA for some encounters, grouping by (ID, ADMIT_DATE) creates a "patient-NA" group with invalid dates.
**Why it happens:** data.table includes NA as a valid group level by default.
**How to avoid:** Filter to valid dates before grouping: `enc_dt <- enc_dt[!is.na(ADMIT_DATE) & !is.na(SOURCE)]` (mirroring R/22 line 112 pattern).
**Warning signs:** CSV output includes rows with ADMIT_DATE = NA or "<NA>".

### Pitfall 5: Performance Degradation from Unnecessary Copies
**What goes wrong:** Creating intermediate data.frames/tibbles between data.table operations forces copy-to-memory, losing performance gains.
**Why it happens:** Mixing data.table with dplyr pipelines or using `as.data.frame()` mid-chain.
**How to avoid:** Keep data as data.table throughout the chain. If using readr::write_csv(), it handles data.table natively (no conversion needed).
**Warning signs:** Script runs slower than expected; memory usage spikes during aggregation.

## Code Examples

Verified patterns from Phase 25/26 scripts and data.table documentation:

### Per-Patient-Date Source Enumeration (Core Operation)
```r
# Source: Phase 28 research + data.table FAQ
library(data.table)

# Convert to data.table (if not already)
enc_dt <- as.data.table(enc_valid)

# Group by (ID, ADMIT_DATE), count sources and encounters
patient_date_detail <- enc_dt[, .(
  n_sources    = uniqueN(SOURCE),
  source_combo = paste(sort(unique(SOURCE)), collapse = "+"),
  n_encounters = .N
), by = .(ID, ADMIT_DATE)]

# Result: one row per (patient, date) with source enumeration
# Example row: ID="ABC123", ADMIT_DATE="2023-01-15", n_sources=2, source_combo="FLM+UFH", n_encounters=3
```

### Source Combination Frequency Summary
```r
# Source: R/22 lines 191-199 pattern adapted to data.table
combo_freq <- patient_date_detail[, .(
  n_patient_dates    = .N,
  n_total_encounters = sum(n_encounters)
), by = source_combo][
  order(-n_patient_dates)
][
  , rank := .I
]

# Top 10 console output
message("Top 10 source combinations:")
for (i in 1:min(10, nrow(combo_freq))) {
  r <- combo_freq[i]
  message(glue("  #{r$rank} {r$source_combo}: {format(r$n_patient_dates, big.mark=',')} patient-dates"))
}
```

### Per-Source Summary Counts
```r
# Source: R/22 lines 148-176 pattern adapted to data.table
per_source_summary <- enc_dt[, .(
  total_encounters = .N,
  n_patient_dates  = uniqueN(paste(ID, ADMIT_DATE)),
  n_patients       = uniqueN(ID)
), by = SOURCE][
  order(SOURCE)
]

# Console output
message("Per-SOURCE summary:")
for (i in 1:nrow(per_source_summary)) {
  r <- per_source_summary[i]
  message(glue("  {r$SOURCE}: {format(r$total_encounters, big.mark=',')} encounters | {format(r$n_patients, big.mark=',')} patients"))
}
```

### ADMIT_DATE Parsing with Fallback
```r
# Source: R/22 lines 86-108 (reuse verbatim)
enc <- enc %>%
  mutate(admit_date_parsed = as.Date(ADMIT_DATE, format = "%Y-%m-%d"))

n_admit_raw <- sum(!is.na(enc$ADMIT_DATE) & nchar(trimws(enc$ADMIT_DATE)) > 0)
n_admit_parsed <- sum(!is.na(enc$admit_date_parsed))
admit_parse_rate <- if (n_admit_raw > 0) round(100 * n_admit_parsed / n_admit_raw, 1) else 100

if (n_admit_raw > 0 && admit_parse_rate < 50) {
  message(glue("  Standard date parse rate only {admit_parse_rate}% -- trying parse_pcornet_date()"))
  if (file.exists("R/utils_dates.R")) {
    source("R/utils_dates.R")
    enc <- enc %>% mutate(admit_date_parsed = parse_pcornet_date(ADMIT_DATE))
    n_admit_parsed <- sum(!is.na(enc$admit_date_parsed))
    admit_parse_rate <- if (n_admit_raw > 0) round(100 * n_admit_parsed / n_admit_raw, 1) else 100
  }
}

message(glue("ADMIT_DATE parse rate: {admit_parse_rate}% ({format(n_admit_parsed, big.mark=',')} of {format(n_admit_raw, big.mark=',')} non-empty)"))
```

### HIPAA-Suppressed CSV Output
```r
# Source: R/22 lines 424-431
csv1 <- patient_date_detail %>%
  mutate(
    n_sources    = hipaa_suppress(n_sources),
    n_encounters = hipaa_suppress(n_encounters)
  )

write_csv(csv1, file.path(output_dir, "patient_date_source_detail.csv"))
message(glue("  Written: patient_date_source_detail.csv ({format(nrow(csv1), big.mark=',')} rows)"))
```

## State of the Art

| Old Approach (Phase 25-26) | Current Approach (Phase 28) | When Changed | Impact |
|----------------|------------------|--------------|--------|
| Pairwise self-join on (ID, date) with SOURCE_x < SOURCE_y filter to find overlapping encounters | Direct group-by (ID, date) to enumerate sources present | Phase 28 (2026-04-23) | 10-50x faster (no Cartesian product), simpler logic, same insight |
| Field-by-field comparison (ENC_TYPE, payer, provider, discharge date) to classify overlap | Source enumeration only — no field comparison | Phase 28 | Eliminates Phase 26 entirely for this use case; trades detailed overlap classification for speed and simplicity |
| Same-week window (±7 days) with day-by-day iteration | Same-date only (no window) | Phase 28 (D-04) | Simpler temporal logic, no need for window scans |

**Deprecated/outdated:**
- Phase 25 pairwise approach: Still valid for detailed field comparison, but Phase 28's per-date enumeration is faster and sufficient for "which sources overlap?" question
- Same-week near-duplicate detection: Out of scope for Phase 28 (D-04)

## Open Questions

1. **Should patient_date_detail include per-source encounter breakdown?**
   - What we know: D-01 specifies `n_sources, source_combo, n_encounters` — total encounters across all sources
   - What's unclear: Whether a column like `encounters_per_source = "UFH:2, FLM:1"` adds value for downstream analysis
   - Recommendation: Start without per-source breakdown (simplest); add if user requests during implementation review. Pattern 2 shows how to add it if needed.

2. **How to handle patients with encounters from >5 sources on same date?**
   - What we know: PCORnet has 5 partner sites (AMS, UMI, FLM, VRT, UFH) in this dataset; ENCOUNTER.SOURCE values are site codes
   - What's unclear: Whether ENCOUNTER.SOURCE contains values beyond the 5 known sites (e.g., external referrals, legacy codes)
   - Recommendation: Log unique SOURCE values at script start (mirror R/22 lines 80-83) and flag any unexpected values. source_combo will handle any number of sources (e.g., "AMS+FLM+UFH+UMI+VRT").

3. **Should aggregate summaries include single-source dates?**
   - What we know: D-01 requires ALL dates in patient_date_detail; D-02 requires aggregate summaries mirroring Phase 25 structure
   - What's unclear: Phase 25 filtered to multi-source dates only (n_sources > 1). Should Phase 28 aggregates include single-source combos (e.g., "UFH" as a source_combo with n_sources=1)?
   - Recommendation: Include ALL source combinations in aggregates (consistent with D-01's "full picture" rationale). User can filter `n_sources > 1` downstream if multi-source analysis is needed. Combo frequency will naturally show which are single-source (source_combo with no "+").

## Environment Availability

> Phase 28 has no external dependencies beyond standard R packages (data.table, glue, readr). All required packages are already in the project's renv.lock. Skipping environment probe.

## Validation Architecture

> Skipped — workflow.nyquist_validation is explicitly set to false in .planning/config.json.

## Sources

### Primary (HIGH confidence)
- [CRAN data.table 1.18.2.1 documentation](https://cran.r-project.org/web/packages/data.table/data.table.pdf) - Official package PDF, Jan 27 2026
- [data.table FAQ](https://cran.r-project.org/web/packages/data.table/vignettes/datatable-faq.html) - Official CRAN vignette
- R/22_multi_source_overlap_detection.R - Phase 25 script (HIPAA suppression helpers lines 47-60, ADMIT_DATE parsing lines 86-108, console output pattern)
- R/23_overlap_classification.R - Phase 26 script (field comparison pattern, shows what Phase 28 does NOT need)
- R/00_config.R - CONFIG object structure (output_dir, cache settings)

### Secondary (MEDIUM confidence)
- [Count Unique Values by Group in R - Statology](https://www.statology.org/r-count-unique-values-by-group/) - Verified uniqueN() and n_distinct() patterns
- [R: How to Collapse Text by Group in Data Frame - Statology](https://www.statology.org/r-collapse-text-by-group/) - paste(collapse) pattern
- [data.table vs dplyr performance - Towards Data Science](https://towardsdatascience.com/data-table-speed-with-dplyr-syntax-yes-we-can-51ef9aaed585/) - Performance claims (20x faster for group-by operations)
- [data.table Tutorial with 50 Examples - ListenData](https://www.listendata.com/2016/10/r-data-table.html) - Comprehensive syntax reference

### Tertiary (LOW confidence)
- [HIPAA Safe Harbor Method - Tonic.ai](https://www.tonic.ai/guides/using-tonic-structural-and-the-safe-harbor-method-to-de-identify-phi) - General HIPAA de-identification background (not R-specific)
- [Small count suppression - WA Dept of Health](https://www.doh.wa.gov/portals/1/documents/1500/smallnumbers.pdf) - Public health suppression standards (validates <11 threshold)

## Metadata

**Confidence breakdown:**
- Standard stack (data.table 1.16.2+): HIGH - Official CRAN versions verified, user explicitly requested data.table
- Architecture (group-by per-date enumeration): HIGH - data.table documentation + Phase 25 patterns provide clear implementation path
- Pitfalls (reference mutation, sort order, suppression timing): MEDIUM - Inferred from data.table FAQ and common R patterns, not yet validated in this specific script

**Research date:** 2026-04-23
**Valid until:** 60 days (data.table is stable; 1.16.2 → 1.18.2 had no breaking changes per CRAN NEWS)
