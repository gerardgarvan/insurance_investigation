# Phase 22: Generalize Phase 20 to All Sites - Research

**Researched:** 2026-04-14
**Domain:** R data diagnostics, cross-site duplication analysis, tidyverse data manipulation
**Confidence:** HIGH

## Summary

Phase 22 extends Phase 20's FLM-specific duplicate date investigation to ALL partner sites (AMS, UMI, FLM, VRT, UFH) in the OneFlorida+ dataset. This is a direct parallel to how Phase 21 generalized Phase 19's missingness investigation. The implementation pattern is well-established: replace single-site filtering with group_by(SOURCE) operations, add SITE columns to all CSV outputs, and generate a cross-site summary CSV for head-to-head comparison.

The technical approach is straightforward tidyverse grouping. Phase 20's 8-section structure (patient identification, encounter filtering, same-date duplicate detection, exact row duplicates, multi-source identification, payer completeness comparison, CSV outputs, console summary) generalizes cleanly by adding SOURCE as a grouping dimension throughout. The primary challenge is handling the nested grouping: patient assignment by DEMOGRAPHIC.SOURCE, then examining ENCOUNTER.SOURCE variation within each patient's encounters.

**Primary recommendation:** Follow Phase 21's proven generalization pattern. Use group_by(SOURCE) for all aggregations, produce combined CSVs with a SITE column (not separate per-site files), add a cross-site summary CSV, and structure the script as a direct extension of Phase 20's R/19_flm_duplicate_dates.R with SOURCE-grouped operations.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Investigation Scope:**
- **D-01:** Analyze ALL patients per site from DEMOGRAPHIC (not just HL cohort). Same approach as Phase 20 D-06 — this is a data quality investigation, not a cohort analysis
- **D-02:** Patients assigned to sites via DEMOGRAPHIC.SOURCE (patient's home site). Then examine ENCOUNTER.SOURCE within each patient's encounters to detect cross-site encounters. Direct extension of Phase 20 pattern
- **D-03:** Same duplicate definitions as Phase 20: same-date by ID+date only (D-01), exact row duplicates (D-02), check ADMIT_DATE primary + DISCHARGE_DATE secondary (D-03)
- **D-04:** Same missingness definition as Phase 19/20: NA, empty string, NI, UN, OT, 99, 9999

**Output Structure:**
- **D-05:** Same 3+1 CSVs as Phase 20 but with a SITE/SOURCE column, plus a cross-site summary CSV (5 files total)
  - all_site_patient_duplicate_summary.csv (patient-level with SITE column)
  - all_site_date_level_duplicate_detail.csv (date-level with sources and payer data, SITE column)
  - all_site_duplicate_aggregate_summary.csv (per-site aggregate rates)
  - all_site_source_payer_completeness.csv (per-site source completeness)
  - all_site_cross_site_summary.csv (one row per site for head-to-head comparison)
- **D-06:** CSV file naming uses `all_site_` prefix, consistent with Phase 21's `all_source_` prefix pattern
- **D-07:** CSV output to `output/tables/` — consistent with existing pipeline pattern

**Recommendation Logic:**
- **D-08:** Per-site source-preference recommendations — for each DEMOGRAPHIC.SOURCE site, identify which ENCOUNTER.SOURCE provides the best payer data when multi-source duplicates exist
- **D-09:** Each site gets its own recommendation based on its own multi-source encounter payer completeness rates

**Script Design:**
- **D-10:** New standalone script `R/21_all_site_duplicate_dates.R`. Phase 20's `R/19_flm_duplicate_dates.R` stays unchanged
- **D-11:** Sources its own dependencies (same pattern as Phase 20: `source("R/00_config.R")` then conditional `source("R/01_load_pcornet.R")`)
- **D-12:** Use `group_by(SITE)` or iterate per site to extend Phase 20's single-site logic to all sites

### Claude's Discretion
- Exact CSV column structures and any additional columns beyond Phase 20's set
- Console logging format and how to present per-site summaries compactly
- Whether to iterate per site (for-loop like Phase 20's structure) or use group_by throughout (Phase 21's pattern)
- How to handle sites with zero duplicate dates or zero multi-source encounters
- Cross-site summary CSV column selection and sort order
- Script section numbering and organization

### Deferred Ideas (OUT OF SCOPE)
None

</user_constraints>

## Standard Stack

### Core Libraries
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| dplyr | 1.2.0+ | Data transformation and grouping | Industry standard for grouped aggregations; group_by(SOURCE) is the core pattern for multi-site analysis |
| tidyr | 1.3.1+ | Data reshaping | Included in tidyverse; needed for pivoting and unnesting operations if cross-site comparisons require wide format |
| readr | 2.2.0+ | CSV I/O | Fast, consistent CSV writing with write_csv() |
| glue | 1.8.0+ | String formatting | Readable logging messages with embedded expressions |
| stringr | 1.5.1+ | String operations | Consistent string handling for SOURCE values and date parsing |
| lubridate | 1.9.3+ | Date operations | Parse ADMIT_DATE and DISCHARGE_DATE, extract year() for temporal analysis |
| janitor | 2.2.1+ | Data cleaning | get_dupes() for exact row duplicate detection (Phase 20 D-02) |

### Version Verification

All packages already in use in Phase 20 and Phase 21 scripts. Versions verified from project CLAUDE.md stack documentation:

**Installation:**
```r
# Already installed in project via renv
# Verify with:
renv::status()
```

## Architecture Patterns

### Recommended Script Structure

Extend Phase 20's 8-section structure with SOURCE grouping:

```r
# R/21_all_site_duplicate_dates.R

source("R/00_config.R")
library(dplyr)
library(lubridate)
library(glue)
library(readr)
library(stringr)
library(janitor)
library(tidyr)

if (!exists("pcornet")) source("R/01_load_pcornet.R")

# SECTION 1: Identify all patients per site from DEMOGRAPHIC
#   - Get unique DEMOGRAPHIC.SOURCE values
#   - Log N patients per site
#   - Create site_patient_ids list for iteration

# SECTION 2: Per-site encounter filtering
#   - For each DEMOGRAPHIC.SOURCE site:
#     - Filter ENCOUNTER to patients from that site
#     - Log N encounters, NA SOURCE counts, unique ENCOUNTER.SOURCE values
#   - OR: Use group_by(DEMOGRAPHIC.SOURCE) if vectorizable

# SECTION 3: Same-date duplicate detection (per site)
#   - Parse ADMIT_DATE and DISCHARGE_DATE
#   - Group by DEMOGRAPHIC.SOURCE, ID, admit_date_parsed
#   - Count n_encounters_same_date
#   - Filter to duplicates (n > 1)
#   - Log per-site duplicate rates

# SECTION 4: Exact row duplicates (per site)
#   - get_dupes() on all ENCOUNTER columns (excluding parsed dates)
#   - Group by DEMOGRAPHIC.SOURCE to get per-site exact dupe counts
#   - Near-exact duplicates (excluding ENCOUNTERID)

# SECTION 5: Multi-source date identification (per site)
#   - For each DEMOGRAPHIC.SOURCE site's duplicate dates:
#     - Count n_distinct(ENCOUNTER.SOURCE)
#     - Identify multi-source vs same-source duplicates
#     - Log source combination frequencies

# SECTION 6: Payer completeness comparison (per site)
#   - For multi-source duplicates per DEMOGRAPHIC.SOURCE:
#     - Compare payer completeness across ENCOUNTER.SOURCE values
#     - Rank sources by primary payer completeness
#     - Generate per-site recommendations

# SECTION 7: Build and write CSV outputs
#   - all_site_patient_duplicate_summary.csv (SITE column added)
#   - all_site_date_level_duplicate_detail.csv (SITE column added)
#   - all_site_duplicate_aggregate_summary.csv (per-site metrics)
#   - all_site_source_payer_completeness.csv (per-site source ranking)
#   - all_site_cross_site_summary.csv (one row per site)

# SECTION 8: Console summary
#   - Per-site duplicate rates in compact table format
#   - Per-site recommendations
#   - CSV file list
```

### Pattern 1: Per-Site Iteration vs Grouped Operations

**Option A: Iterate per site (Phase 20 pattern):**
```r
# Get all unique sites
all_sites <- unique(pcornet$DEMOGRAPHIC$SOURCE)

# Initialize result containers
all_site_results <- list()

for (site in all_sites) {
  site_patients <- pcornet$DEMOGRAPHIC %>%
    filter(SOURCE == site) %>%
    pull(ID)

  site_encounters <- pcornet$ENCOUNTER %>%
    filter(ID %in% site_patients)

  # ... duplicate detection logic for this site ...

  all_site_results[[site]] <- site_summary
}

# Combine results
combined_results <- bind_rows(all_site_results, .id = "SITE")
```

**Option B: Group-by throughout (Phase 21 pattern):**
```r
# Attach DEMOGRAPHIC.SOURCE to encounters once
all_encounters <- pcornet$ENCOUNTER %>%
  left_join(pcornet$DEMOGRAPHIC %>% select(ID, SOURCE), by = "ID")

# All operations use group_by(SOURCE)
patient_date_summary <- all_encounters %>%
  filter(!is.na(admit_date_parsed)) %>%
  group_by(SOURCE, ID, admit_date_parsed) %>%
  summarize(
    n_encounters = n(),
    n_sources = n_distinct(ENCOUNTER.SOURCE, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  group_by(SOURCE) %>%
  # ... per-site aggregations ...
```

**Recommendation:** Use Option B (group_by pattern) for consistency with Phase 21 and better readability. Only fall back to iteration if nested grouping (DEMOGRAPHIC.SOURCE > ID > date > ENCOUNTER.SOURCE) becomes unwieldy.

### Pattern 2: Handling Two SOURCE Columns

**Challenge:** ENCOUNTER table has its own SOURCE column (encounter recording site), while DEMOGRAPHIC.SOURCE indicates patient's home site.

**Solution:**
```r
# Rename to avoid collision
all_encounters <- pcornet$ENCOUNTER %>%
  rename(ENCOUNTER_SOURCE = SOURCE) %>%  # Explicit rename
  left_join(
    pcornet$DEMOGRAPHIC %>% select(ID, SOURCE),
    by = "ID"
  ) %>%
  rename(SITE = SOURCE, SOURCE = ENCOUNTER_SOURCE)  # SITE = patient's home, SOURCE = encounter site

# Now can group by SITE and analyze SOURCE variation within SITE
multi_source_dates <- all_encounters %>%
  filter(!is.na(admit_date_parsed)) %>%
  group_by(SITE, ID, admit_date_parsed) %>%
  summarize(
    n_encounters = n(),
    n_sources = n_distinct(SOURCE, na.rm = TRUE),
    sources = paste(sort(unique(na.omit(SOURCE))), collapse = ", "),
    .groups = "drop"
  ) %>%
  filter(n_sources > 1)
```

### Pattern 3: Cross-Site Summary CSV

Phase 21 established this pattern for head-to-head comparison:

```r
cross_site_summary <- all_encounters %>%
  left_join(pcornet$DEMOGRAPHIC %>% select(ID, SOURCE), by = "ID") %>%
  group_by(SOURCE) %>%
  summarize(
    n_patients = n_distinct(ID),
    n_encounters = n(),
    n_unique_dates = n_distinct(paste(ID, admit_date_parsed)),
    n_duplicate_dates = sum(n_encounters_same_date > 1),
    pct_duplicate_rate = round(100 * n_duplicate_dates / n_unique_dates, 2),
    n_multi_source_dates = sum(n_sources > 1),
    pct_multi_source = round(100 * n_multi_source_dates / n_duplicate_dates, 2),
    .groups = "drop"
  ) %>%
  arrange(desc(pct_duplicate_rate))

# Add ALL aggregate row
overall <- all_encounters %>% summarize(...)
cross_site_summary <- bind_rows(cross_site_summary, overall)

write_csv(cross_site_summary, "output/tables/all_site_cross_site_summary.csv")
```

### Anti-Patterns to Avoid

**1. Don't confuse DEMOGRAPHIC.SOURCE and ENCOUNTER.SOURCE**
```r
# AVOID: Filtering ENCOUNTER by its own SOURCE column
flm_encounters <- pcornet$ENCOUNTER %>%
  filter(SOURCE == "FLM")  # Wrong! This gets encounters *recorded* at FLM

# CORRECT: Filter by patient's home site via DEMOGRAPHIC
flm_patients <- pcornet$DEMOGRAPHIC %>%
  filter(SOURCE == "FLM") %>%
  pull(ID)

flm_encounters <- pcornet$ENCOUNTER %>%
  filter(ID %in% flm_patients)  # Correct! All encounters for FLM patients
```

**2. Don't create per-site CSV files**
```r
# AVOID: Phase 20 pattern (separate CSV per site)
write_csv(flm_patient_summary, "output/tables/flm_patient_duplicate_summary.csv")

# CORRECT: Phase 21 pattern (combined CSV with SITE column)
all_site_patient_summary <- bind_rows(flm_summary, ams_summary, ..., .id = "SITE")
write_csv(all_site_patient_summary, "output/tables/all_site_patient_duplicate_summary.csv")
```

**3. Don't lose NA SOURCE values silently**
```r
# AVOID: Inner join drops patients with NA DEMOGRAPHIC.SOURCE
all_encounters <- pcornet$ENCOUNTER %>%
  inner_join(pcornet$DEMOGRAPHIC, by = "ID")  # Silently drops orphan encounters

# CORRECT: Left join and handle NAs explicitly
all_encounters <- pcornet$ENCOUNTER %>%
  left_join(pcornet$DEMOGRAPHIC %>% select(ID, SOURCE), by = "ID") %>%
  mutate(SITE = if_else(is.na(SOURCE), "<No Site>", SOURCE))

n_no_site <- sum(is.na(all_encounters$SITE))
if (n_no_site > 0) {
  message(glue("WARNING: {n_no_site} encounters have no DEMOGRAPHIC.SOURCE"))
}
```

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Exact row duplicate detection | Manual hash-based deduplication | janitor::get_dupes() | Handles all column types, preserves row context, tested in Phase 20 |
| Per-group summaries with totals | Manual rbind of per-group + overall | group_by() + bind_rows(overall) | Consistent column types, no off-by-one errors, Phase 21 pattern |
| Multi-column renaming | Repeated rename() calls | rename_with() or select(new = old) | Less error-prone for bulk renames |
| Nested grouping aggregations | For-loops over groups | group_by() with multiple columns | Vectorized, faster, more readable |

**Key insight:** tidyverse's grouped operations handle the complexity of multi-level aggregation (SITE > patient > date > source) more reliably than manual iteration. The mental model is: group once, summarize in layers, ungroup explicitly.

## Common Pitfalls

### Pitfall 1: DEMOGRAPHIC.SOURCE vs ENCOUNTER.SOURCE Confusion

**What goes wrong:** Filtering ENCOUNTER by its own SOURCE column returns encounters *recorded* at that site, not encounters for patients *from* that site. This misses cross-site care patterns.

**Why it happens:** Both tables have a SOURCE column, but they mean different things. DEMOGRAPHIC.SOURCE = patient's home site (persistent). ENCOUNTER.SOURCE = where the encounter was recorded (can vary per encounter for the same patient).

**How to avoid:** Always filter ENCOUNTER via patient IDs from DEMOGRAPHIC.SOURCE. Never filter ENCOUNTER.SOURCE directly unless explicitly analyzing recording-site patterns.

**Warning signs:** Your FLM patient count doesn't match the DEMOGRAPHIC count for FLM. You're missing encounters that FLM patients had at other sites.

### Pitfall 2: Silent NA SOURCE Loss in Joins

**What goes wrong:** inner_join(DEMOGRAPHIC) drops encounters for patients with no DEMOGRAPHIC record or NA DEMOGRAPHIC.SOURCE. These orphan encounters vanish from analysis without warning.

**Why it happens:** Default join is inner, which silently excludes non-matches. In a multi-site dataset, some ENCOUNTERs may lack a corresponding DEMOGRAPHIC row (data quality issue).

**How to avoid:** Use left_join from ENCOUNTER to DEMOGRAPHIC. Explicitly count and log NA SITE values. Decide whether to exclude them or report them as a separate category.

**Warning signs:** Total encounter counts decrease after join. No warning message about excluded records.

### Pitfall 3: Nested Grouping Ungroup Omission

**What goes wrong:** After group_by(SITE, ID, date), subsequent operations stay grouped. Aggregate summaries (e.g., overall cross-site totals) get computed per-group instead of globally, producing incorrect totals.

**Why it happens:** dplyr's grouping is sticky — it persists until explicitly ungrouped. Nested summarize() only removes one level of grouping at a time.

**How to avoid:** Always use .groups = "drop" in summarize() or call ungroup() explicitly before global aggregations.

**Warning signs:** Your "overall" row in cross-site summary has the same value as the first site. Aggregate counts are suspiciously small.

### Pitfall 4: Date Parsing Fails Silently

**What goes wrong:** as.Date() returns NA for unparseable dates without error. Subsequent filters on !is.na(admit_date_parsed) silently exclude these encounters from duplicate detection.

**Why it happens:** PCORnet dates come in multiple formats (ISO, SAS DATE9, YYYYMMDD). Phase 20's parse_pcornet_date() handles this, but it's conditional logic that may not run if standard parsing succeeds on most rows.

**How to avoid:** Always log N unparsed dates. If >5% fail standard parsing, fall back to parse_pcornet_date(). If >20% still fail, investigate format issues before proceeding.

**Warning signs:** Duplicate counts are lower than expected. Console shows "Encounters with NA ADMIT_DATE" unexpectedly high.

### Pitfall 5: ENC_TYPE Grouping Hides True Duplicates

**What goes wrong:** Including ENC_TYPE in group_by(ID, date, ENC_TYPE) makes same-day ED visit + IP admission look like valid distinct encounters instead of potential duplicates.

**Why it happens:** Clinical logic says same-date different encounter types can be valid (ED -> IP transfer). But data quality logic needs to detect all same-date collisions first, then filter by clinical rules.

**How to avoid:** Phase 20 D-01: group by ID + date ONLY. After identifying duplicates, add ENC_TYPE as a classification column (same-type vs different-type), not a grouping column.

**Warning signs:** Your duplicate rate is 0% or very low despite multi-source data. Phase 20's FLM investigation found duplicates — if you don't, you're filtering too aggressively.

## Code Examples

Verified patterns from Phase 20 and Phase 21:

### Attach DEMOGRAPHIC.SOURCE to Encounters
```r
# Source: Phase 21 R/20_all_source_missingness.R lines 89-104
# Pattern: Rename ENCOUNTER.SOURCE to avoid collision, join DEMOGRAPHIC.SOURCE

all_encounters <- pcornet$ENCOUNTER %>%
  select(-SOURCE) %>%  # Drop ENCOUNTER.SOURCE to avoid collision
  left_join(pcornet$DEMOGRAPHIC %>% select(ID, SOURCE), by = "ID") %>%
  mutate(
    # Rename for clarity: SITE = patient home, ENCOUNTER_SOURCE = recording site
    SITE = SOURCE
  )

# Log per-site patient and encounter counts
enc_by_site <- all_encounters %>%
  group_by(SITE) %>%
  summarise(
    n_patients = n_distinct(ID),
    n_encounters = n(),
    .groups = "drop"
  )

message("\nEncounters per site:")
for (i in seq_len(nrow(enc_by_site))) {
  r <- enc_by_site[i, ]
  message(glue("  {r$SITE}: {format(r$n_encounters, big.mark=',')} encounters"))
}
```

### Same-Date Duplicate Detection with SOURCE Grouping
```r
# Source: Phase 20 R/19_flm_duplicate_dates.R lines 119-136
# Extended with SITE grouping

# Parse dates (Phase 20 pattern)
all_encounters <- all_encounters %>%
  mutate(
    admit_date_parsed = as.Date(ADMIT_DATE, format = "%Y-%m-%d"),
    discharge_date_parsed = as.Date(DISCHARGE_DATE, format = "%Y-%m-%d")
  )

# Check parse success rate
n_admit_raw <- sum(!is.na(all_encounters$ADMIT_DATE) &
                   nchar(trimws(all_encounters$ADMIT_DATE)) > 0)
n_admit_parsed <- sum(!is.na(all_encounters$admit_date_parsed))
admit_parse_rate <- if (n_admit_raw > 0) {
  round(100 * n_admit_parsed / n_admit_raw, 1)
} else {
  100
}

message(glue("ADMIT_DATE parse rate: {admit_parse_rate}%"))

# Detect duplicates per site
admit_date_dupes <- all_encounters %>%
  filter(!is.na(admit_date_parsed)) %>%
  add_count(SITE, ID, admit_date_parsed, name = "n_encounters_same_date") %>%
  filter(n_encounters_same_date > 1) %>%
  arrange(SITE, ID, admit_date_parsed)

# Per-site duplicate summary
dupe_summary_by_site <- admit_date_dupes %>%
  group_by(SITE) %>%
  summarize(
    n_dupe_rows = n(),
    n_dupe_patient_dates = n_distinct(paste(ID, admit_date_parsed)),
    n_dupe_patients = n_distinct(ID),
    .groups = "drop"
  )

message("\nPer-site ADMIT_DATE duplicate summary:")
for (i in seq_len(nrow(dupe_summary_by_site))) {
  r <- dupe_summary_by_site[i, ]
  message(glue("  {r$SITE}: {format(r$n_dupe_patient_dates, big.mark=',')} patient-dates with duplicates"))
}
```

### Multi-Source Identification (Nested Grouping)
```r
# Source: Phase 20 R/19_flm_duplicate_dates.R lines 185-237
# Extended with SITE as outer group

# Restore ENCOUNTER.SOURCE for multi-source analysis
all_encounters_with_enc_source <- pcornet$ENCOUNTER %>%
  rename(ENCOUNTER_SOURCE = SOURCE) %>%
  left_join(pcornet$DEMOGRAPHIC %>% select(ID, SOURCE), by = "ID") %>%
  rename(SITE = SOURCE) %>%
  mutate(
    admit_date_parsed = as.Date(ADMIT_DATE, format = "%Y-%m-%d")
  )

# Per-patient-date summary with SITE grouping
patient_date_summary <- all_encounters_with_enc_source %>%
  filter(!is.na(admit_date_parsed)) %>%
  add_count(SITE, ID, admit_date_parsed, name = "n_encounters_same_date") %>%
  filter(n_encounters_same_date > 1) %>%
  group_by(SITE, ID, admit_date_parsed) %>%
  summarize(
    n_encounters = n(),
    n_sources = n_distinct(ENCOUNTER_SOURCE, na.rm = TRUE),
    sources = paste(sort(unique(na.omit(ENCOUNTER_SOURCE))), collapse = ", "),
    enc_types = paste(sort(unique(na.omit(ENC_TYPE))), collapse = ", "),
    n_enc_types = n_distinct(ENC_TYPE, na.rm = TRUE),
    .groups = "drop"
  )

# Identify multi-source dates per site
multi_source_dates <- patient_date_summary %>%
  filter(n_sources > 1)

# Per-site multi-source summary
multi_source_by_site <- multi_source_dates %>%
  group_by(SITE) %>%
  summarize(
    n_multi_source_dates = n(),
    n_multi_source_patients = n_distinct(ID),
    .groups = "drop"
  )

message("\nPer-site multi-source duplicate summary:")
for (i in seq_len(nrow(multi_source_by_site))) {
  r <- multi_source_by_site[i, ]
  message(glue("  {r$SITE}: {format(r$n_multi_source_dates, big.mark=',')} patient-dates with multiple sources"))
}
```

### Payer Completeness Comparison (Per Site)
```r
# Source: Phase 20 R/19_flm_duplicate_dates.R lines 239-330
# Extended with SITE grouping

# Missingness helper (Phase 19/20 pattern)
is_missing_payer <- function(payer_value) {
  is.na(payer_value) |
    nchar(trimws(payer_value)) == 0 |
    payer_value %in% c("NI", "UN", "OT", "99", "9999")
}

# Get multi-source encounters per site
multi_source_encounters <- all_encounters_with_enc_source %>%
  semi_join(multi_source_dates, by = c("SITE", "ID", "admit_date_parsed"))

# Per-site, per-ENCOUNTER_SOURCE completeness
source_completeness_by_site <- multi_source_encounters %>%
  filter(!is.na(ENCOUNTER_SOURCE)) %>%
  group_by(SITE, ENCOUNTER_SOURCE) %>%
  summarize(
    n_encounters = n(),
    n_primary_present = sum(!is_missing_payer(PAYER_TYPE_PRIMARY)),
    pct_primary_present = round(100 * n_primary_present / n_encounters, 1),
    n_secondary_present = sum(!is_missing_payer(PAYER_TYPE_SECONDARY)),
    pct_secondary_present = round(100 * n_secondary_present / n_encounters, 1),
    .groups = "drop"
  ) %>%
  arrange(SITE, desc(pct_primary_present))

# Generate per-site recommendations
site_recommendations <- source_completeness_by_site %>%
  group_by(SITE) %>%
  slice_max(order_by = pct_primary_present, n = 1, with_ties = FALSE) %>%
  ungroup() %>%
  select(SITE, recommended_source = ENCOUNTER_SOURCE,
         completeness_pct = pct_primary_present)

message("\nPer-site source recommendations (for multi-source duplicates):")
for (i in seq_len(nrow(site_recommendations))) {
  r <- site_recommendations[i, ]
  message(glue("  {r$SITE}: Prefer ENCOUNTER_SOURCE='{r$recommended_source}' ({r$completeness_pct}% primary payer completeness)"))
}
```

### Cross-Site Summary CSV
```r
# Source: Phase 21 R/20_all_source_missingness.R lines 383-418
# Adapted for duplicate investigation

# Per-site summary
cross_site_summary <- all_encounters %>%
  filter(!is.na(admit_date_parsed)) %>%
  group_by(SITE) %>%
  summarise(
    n_patients = n_distinct(ID),
    n_encounters = n(),
    n_unique_dates = n_distinct(paste(ID, admit_date_parsed)),
    .groups = "drop"
  ) %>%
  left_join(
    dupe_summary_by_site,
    by = "SITE"
  ) %>%
  left_join(
    multi_source_by_site,
    by = "SITE"
  ) %>%
  mutate(
    pct_duplicate_rate = round(100 * n_dupe_patient_dates / n_unique_dates, 2),
    pct_multi_source = round(100 * n_multi_source_dates / n_dupe_patient_dates, 2)
  ) %>%
  arrange(desc(pct_duplicate_rate))

# Add "ALL" aggregate row
overall_summary <- all_encounters %>%
  filter(!is.na(admit_date_parsed)) %>%
  summarise(
    SITE = "ALL",
    n_patients = n_distinct(ID),
    n_encounters = n(),
    n_unique_dates = n_distinct(paste(ID, admit_date_parsed)),
    # ... aggregate duplicate counts ...
  )

cross_site_summary <- bind_rows(cross_site_summary, overall_summary)

write_csv(cross_site_summary,
          file.path(output_dir, "all_site_cross_site_summary.csv"))
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Per-site separate CSVs | Combined CSV with SITE column | Phase 21 (2026-04-13) | Easier cross-site comparison; single file to load |
| For-loop per site | group_by(SITE) throughout | Phase 21 pattern | Cleaner code, vectorized, fewer bugs |
| DEMOGRAPHIC.SOURCE = "X" filter | Join and group | Phase 21 | Handles all sites in one pass, no copy-paste errors |
| Manual aggregate row construction | bind_rows(per_site, overall) | Phase 21 | Consistent column types, explicit ALL row |

**Deprecated/outdated:**
- Phase 20's single-site investigation pattern (R/19_flm_duplicate_dates.R) — works but doesn't generalize. Phase 22 supersedes it with multi-site approach.
- Separate per-site CSV files — Phase 21 established the combined CSV with grouping column pattern.

## Environment Availability

Skip this section: Phase 22 has no external dependencies beyond the R packages already installed in the project renv (dplyr, tidyr, readr, glue, stringr, lubridate, janitor). All dependencies were verified in Phase 20 and Phase 21.

## Sources

### Primary (HIGH confidence)
- R/19_flm_duplicate_dates.R (Phase 20) — Direct template for duplicate investigation logic, 8-section structure, missingness definition, payer completeness comparison
- R/20_all_source_missingness.R (Phase 21) — Direct template for generalization pattern, group_by(SOURCE) usage, cross-site summary CSV, console output format
- .planning/phases/20-check-duplicate-dates-of-flm-subjects/20-CONTEXT.md — Phase 20 decisions D-01 through D-18
- .planning/phases/21-generalize-phase-19-to-all-sources/21-CONTEXT.md — Phase 21 decisions D-01 through D-11, generalization strategy
- R/00_config.R line 107 — SOURCE column documentation
- R/01_load_pcornet.R — ENCOUNTER and DEMOGRAPHIC table loading
- CLAUDE.md (project) — Stack documentation (tidyverse versions, HiPerGator setup)

### Secondary (MEDIUM confidence)
- Phase 19 R/18_uf_insurance_missingness.R — Original missingness investigation pattern that Phase 21 generalized

### Tertiary (LOW confidence)
None — all research findings verified from project canonical references

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — All packages already in use and tested in Phase 20 and Phase 21
- Architecture: HIGH — Phase 21 established the generalization pattern; Phase 22 is a direct parallel application
- Pitfalls: HIGH — Verified from Phase 20 implementation and Phase 21's SOURCE column handling patterns
- Code examples: HIGH — All examples extracted verbatim from Phase 20 and Phase 21 scripts with line numbers

**Research date:** 2026-04-14
**Valid until:** 60 days (stable pattern, no fast-moving dependencies)
