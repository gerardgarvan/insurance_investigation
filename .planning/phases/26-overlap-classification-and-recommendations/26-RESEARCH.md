# Phase 26: Overlap Classification and Recommendations - Research

**Researched:** 2026-04-22
**Domain:** Multi-source encounter field comparison, data quality classification, deduplication strategy
**Confidence:** HIGH

## Summary

Phase 26 builds directly on Phase 25's multi-source overlap detection output to classify each overlapping encounter group as **Identical**, **Partial**, or **Distinct** via field-by-field comparison. The phase consumes 2 Phase 25 CSVs (same-date detail, same-week detail), joins back to raw ENCOUNTER to extract 5 comparison fields (ENC_TYPE, PAYER_TYPE_PRIMARY, PAYER_TYPE_SECONDARY, PROVIDERID, DISCHARGE_DATE), applies user-defined classification thresholds, and produces per-site recommendations on whether to deduplicate or retain multi-source encounters.

This is a diagnostic phase — output is investigative CSVs and console summaries, not an automated deduplication pipeline. The goal is to characterize overlap quality across sites so the user can make informed decisions about multi-source encounter handling in future analysis.

**Primary recommendation:** Follow Phase 21/22/25 standalone script pattern — one R script (R/23_overlap_classification.R), reads Phase 25 CSVs as input, joins to ENCOUNTER for field extraction, computes match counts and labels, outputs 4 CSVs + console summary with per-site recommendations.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Both NA = match. If both encounters in a pair have NA/missing for the same field, treat as agreement (shared absence = consistency).
- **D-02:** One NA, one present = mismatch. If one encounter has a value and the other has NA, treat as disagreement.
- **D-03:** Normalize payer sentinels before comparison. Convert all payer missing sentinels (NI, UN, OT, 99, 9999, empty string) to NA before comparing PAYER_TYPE_PRIMARY and PAYER_TYPE_SECONDARY. Consistent with Phase 19 `is_missing_payer()` definition.
- **D-04:** 5 fields compared for same-date pairs: ENC_TYPE, PAYER_TYPE_PRIMARY, PAYER_TYPE_SECONDARY, PROVIDERID, DISCHARGE_DATE.
- **D-05:** Identical = all compared fields match (5/5 for same-date, 4/4 for same-week). Partial = 1 to N-1 fields match. Distinct = 0 fields match.
- **D-06:** Include raw match count alongside label: e.g., "Partial (3/5)" so analyst can drill into granularity of partial matches.
- **D-07:** Per-site recommendation thresholds based on % Identical among same-date multi-source groups:
  - >=70% Identical: "Safe to deduplicate by keeping preferred source"
  - 30-69% Identical: "Mixed overlap — review partial matches before deduplication"
  - <30% Identical: "Encounters are largely distinct — retain all"
- **D-08:** Include preferred source suggestion for deduplication. For sites where deduplication is recommended, suggest which ENCOUNTER.SOURCE to keep based on payer completeness comparison (derived from the field comparison data within this phase).
- **D-09:** Exclude DISCHARGE_DATE from same-week field comparison. Compare only 4 fields: ENC_TYPE, PAYER_TYPE_PRIMARY, PAYER_TYPE_SECONDARY, PROVIDERID. Different admit dates likely mean different discharge dates — including it adds noise.
- **D-10:** Use same Identical/Partial/Distinct labels for same-week, with a `basis` column noting "same_date (5 fields)" vs "same_week (4 fields)" so the denominator difference is transparent.

### Claude's Discretion
- Exact join strategy for reading Phase 25 CSVs and joining back to ENCOUNTER table for field extraction
- Console summary formatting and verbosity
- CSV column naming and ordering
- How to compute preferred source from field comparison data (e.g., which source has more non-NA payer values across overlapping encounters)
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| OVRLP-01 | User can see field-by-field comparison for each same-date multi-source group: ENC_TYPE, PAYER_TYPE_PRIMARY, PAYER_TYPE_SECONDARY, PROVIDERID, and DISCHARGE_DATE match/mismatch flags | R 1:1 join from Phase 25 detail CSV to ENCOUNTER on (ID, ADMIT_DATE, SOURCE); compute `_match` boolean per field using D-01/D-02 NA handling |
| OVRLP-02 | User can see each multi-source group classified as Identical (all compared fields match), Partial (some fields match), or Distinct (most fields differ) | Count matches, apply D-05 thresholds (5/5=Identical, 1-4/5=Partial, 0/5=Distinct); store match_count and label columns |
| OVRLP-03 | User can see per-site overlap profile showing what percentage of multi-source same-date encounters are Identical vs Partial vs Distinct | Group by SITE (from DEMOGRAPHIC join), count label frequencies, compute percentages |
| OVRLP-04 | User can see the same field comparison and classification applied to same-week near-duplicates | Apply same logic to same-week detail CSV with 4-field comparison (D-09: exclude DISCHARGE_DATE); use `basis` column to distinguish 4-field vs 5-field denominator |
| OUTPT-01 | User can see CSV files in output/tables/ with patient-level same-date detail, same-week detail, and per-site aggregate summaries | Write 4 CSVs: classified_same_date_detail.csv, classified_same_week_detail.csv, per_site_overlap_profile.csv, source_payer_completeness.csv (HIPAA suppress count columns only) |
| OUTPT-02 | User can see console summary on HiPerGator with per-site multi-source rates, overlap classification breakdown, and key findings | Console output via `message()` + `glue()` following Phase 22/25 pattern; section-based structure with `strrep('=', 70)` headers |
| OUTPT-03 | User can see actionable per-site recommendations based on overlap patterns (e.g., "Site X: 85% identical -- safe to deduplicate by keeping preferred source") | D-07 threshold logic: compute per-site % Identical, apply 70%/30% cutoffs, generate recommendation text with preferred source from D-08 |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| dplyr | 1.2.0+ | Data transformation and joins | Project standard; 1:many join from detail CSV to ENCOUNTER, group_by for per-site aggregation |
| readr | 2.2.0+ | CSV I/O | Project standard; read Phase 25 CSVs, write Phase 26 classified CSVs |
| tidyr | 1.3.1+ | Data reshaping | spread/pivot if needed for field comparison matrices; part of tidyverse |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| glue | 1.8.0 | String formatting | Console output messages with embedded expressions (e.g., "Site X: {pct}% Identical") |
| stringr | 1.5.1+ | String operations | Payer sentinel normalization (`str_trim`, `%in%`), field value comparison |
| lubridate | 1.9.3+ | Date operations | Parse ADMIT_DATE for join keys, DISCHARGE_DATE field comparison |
| janitor | 2.2.1+ | Data cleaning | Optional: `clean_names()` for Phase 25 CSV columns if column name consistency issues arise |

**Installation:**
Already installed in project environment. No additional packages needed beyond existing Phase 19/20/21/22/25 dependencies.

**Version verification:**
```bash
# All versions inherited from project renv.lock (Phase 15)
# No new package installations required for Phase 26
```

## Architecture Patterns

### Recommended Project Structure
Phase 26 produces one new R script in existing structure:
```
R/
├── 00_config.R                         # CONFIG, output_dir, PAYER_MAPPING
├── 01_load_pcornet.R                   # pcornet$ENCOUNTER, pcornet$DEMOGRAPHIC
├── 22_multi_source_overlap_detection.R # Phase 25 (input producer)
└── 23_overlap_classification.R         # Phase 26 (NEW — this phase)

output/tables/
├── multi_source_same_date_detail.csv      # Phase 25 input
├── multi_source_same_week_detail.csv      # Phase 25 input
├── classified_same_date_detail.csv        # Phase 26 output
├── classified_same_week_detail.csv        # Phase 26 output
├── per_site_overlap_profile.csv           # Phase 26 output
└── source_payer_completeness.csv          # Phase 26 output
```

### Pattern 1: Field-by-Field Comparison with NA Handling (D-01, D-02, D-03)
**What:** Compare 5 fields (ENC_TYPE, PAYER_TYPE_PRIMARY, PAYER_TYPE_SECONDARY, PROVIDERID, DISCHARGE_DATE) between each pair of encounters in a same-date multi-source group, respecting NA=NA match rule.

**When to use:** Every same-date pair; same-week uses 4 fields (exclude DISCHARGE_DATE per D-09).

**Example:**
```r
# Phase 19 pattern: is_missing_payer() helper
is_missing_payer <- function(payer_value) {
  is.na(payer_value) |
    nchar(trimws(payer_value)) == 0 |
    payer_value %in% c("NI", "UN", "OT", "99", "9999")
}

# Normalize payer values before comparison (D-03)
enc_normalized <- enc %>%
  mutate(
    payer_primary_norm   = if_else(is_missing_payer(PAYER_TYPE_PRIMARY), NA_character_, PAYER_TYPE_PRIMARY),
    payer_secondary_norm = if_else(is_missing_payer(PAYER_TYPE_SECONDARY), NA_character_, PAYER_TYPE_SECONDARY)
  )

# D-01: Both NA = match
# D-02: One NA, one present = mismatch
field_match <- function(val1, val2) {
  # Both NA → TRUE (match)
  if (is.na(val1) & is.na(val2)) return(TRUE)
  # One NA, one present → FALSE (mismatch)
  if (is.na(val1) | is.na(val2)) return(FALSE)
  # Both present → compare
  return(val1 == val2)
}

# Apply to encounter pairs (after self-join)
pairs <- pairs %>%
  mutate(
    enc_type_match = field_match(ENC_TYPE_1, ENC_TYPE_2),
    payer_pri_match = field_match(payer_primary_norm_1, payer_primary_norm_2),
    payer_sec_match = field_match(payer_secondary_norm_1, payer_secondary_norm_2),
    providerid_match = field_match(PROVIDERID_1, PROVIDERID_2),
    discharge_match = field_match(DISCHARGE_DATE_1, DISCHARGE_DATE_2)
  )
```

### Pattern 2: Classification via Match Count Thresholds (D-05, D-06)
**What:** Count how many of the N compared fields match, then apply thresholds to assign Identical/Partial/Distinct label. Include both label and raw count.

**When to use:** After field comparison, before aggregation.

**Example:**
```r
# D-05: Identical = all match, Partial = some match, Distinct = none match
# D-06: Include match count (e.g., "Partial (3/5)")
classified <- pairs %>%
  rowwise() %>%
  mutate(
    match_count = sum(c_across(ends_with("_match")), na.rm = TRUE),
    n_fields = 5,  # same-date: 5 fields; same-week: 4 fields (set dynamically)
    classification = case_when(
      match_count == n_fields ~ "Identical",
      match_count == 0        ~ "Distinct",
      TRUE                    ~ "Partial"
    ),
    classification_detail = glue("{classification} ({match_count}/{n_fields})")
  ) %>%
  ungroup()
```

### Pattern 3: Per-Site Overlap Profile (D-07, OVRLP-03)
**What:** Group classified encounters by SITE (from DEMOGRAPHIC join), compute % Identical/Partial/Distinct, apply recommendation thresholds.

**When to use:** Aggregation step after classification.

**Example:**
```r
# Join to DEMOGRAPHIC for SITE assignment (Phase 22 pattern: rename ENCOUNTER.SOURCE, join DEMOGRAPHIC.SOURCE)
classified_with_site <- classified %>%
  rename(ENCOUNTER_SOURCE = SOURCE) %>%
  left_join(pcornet$DEMOGRAPHIC %>% select(ID, SOURCE), by = "ID") %>%
  rename(SITE = SOURCE)

per_site_profile <- classified_with_site %>%
  group_by(SITE) %>%
  summarise(
    n_multi_source_pairs = n(),
    n_identical = sum(classification == "Identical"),
    n_partial   = sum(classification == "Partial"),
    n_distinct  = sum(classification == "Distinct"),
    pct_identical = round(100 * n_identical / n_multi_source_pairs, 1),
    pct_partial   = round(100 * n_partial / n_multi_source_pairs, 1),
    pct_distinct  = round(100 * n_distinct / n_multi_source_pairs, 1),
    .groups = "drop"
  ) %>%
  # D-07: Apply recommendation thresholds
  mutate(
    recommendation = case_when(
      pct_identical >= 70 ~ "Safe to deduplicate by keeping preferred source",
      pct_identical >= 30 ~ "Mixed overlap — review partial matches before deduplication",
      TRUE                ~ "Encounters are largely distinct — retain all"
    )
  )
```

### Pattern 4: Preferred Source from Payer Completeness (D-08)
**What:** For sites where deduplication is recommended (>=70% Identical), compute which ENCOUNTER.SOURCE has higher payer completeness (% non-NA PAYER_TYPE_PRIMARY) across overlapping encounters.

**When to use:** After per-site profile, before recommendation output.

**Example:**
```r
# Phase 22 pattern: per-source payer completeness
source_completeness <- classified_with_site %>%
  filter(!is.na(ENCOUNTER_SOURCE)) %>%
  group_by(SITE, ENCOUNTER_SOURCE) %>%
  summarise(
    n_encounters = n(),
    n_primary_present = sum(!is_missing_payer(PAYER_TYPE_PRIMARY)),
    pct_primary_present = round(100 * n_primary_present / n_encounters, 1),
    .groups = "drop"
  ) %>%
  arrange(SITE, desc(pct_primary_present))

# D-08: Preferred source = highest pct_primary_present per site
preferred_source_per_site <- source_completeness %>%
  group_by(SITE) %>%
  slice_max(pct_primary_present, n = 1, with_ties = FALSE) %>%
  select(SITE, preferred_source = ENCOUNTER_SOURCE, preferred_source_pct = pct_primary_present) %>%
  ungroup()

# Join back to per_site_profile
per_site_profile <- per_site_profile %>%
  left_join(preferred_source_per_site, by = "SITE") %>%
  mutate(
    recommendation = case_when(
      pct_identical >= 70 ~ glue("Safe to deduplicate — prefer {preferred_source} ({preferred_source_pct}% payer completeness)"),
      pct_identical >= 30 ~ "Mixed overlap — review partial matches before deduplication",
      TRUE                ~ "Encounters are largely distinct — retain all"
    )
  )
```

### Anti-Patterns to Avoid
- **Don't self-join on patient-date within R**: Phase 25 CSVs already identify multi-source groups. Load the CSV, join to ENCOUNTER to get fields, compare within-group — no Cartesian self-join needed.
- **Don't compare payer fields without normalization**: D-03 requires sentinel value normalization before comparison. If you skip this, "NI" vs NA will be treated as mismatch when they should both be NA.
- **Don't ignore basis column for same-week**: Same-week uses 4 fields, same-date uses 5. D-10 requires `basis` column to distinguish denominators — otherwise "Partial (2/4)" vs "Partial (2/5)" are ambiguous.
- **Don't output detailed row-level CSV for 262K-row datasets**: Phase 25 same-week detail has 262K rows. Writing a classified detail CSV with all match flags would be unwieldy. Consider aggregating to per-site or per-combo summaries for large outputs (per Phase 23 PPTX3-06 pattern).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Field comparison helper | Manual if/else ladder for NA handling | `field_match()` helper function (Pattern 1) | NA handling has 3 branches (both NA, one NA, both present); reusable function is clearer than inline conditionals repeated 5x |
| Payer sentinel normalization | Inline mutate per field | `is_missing_payer()` helper (already exists in R/21_all_site_duplicate_dates.R) | Phase 19 definition is canonical; reuse to maintain consistency across phases |
| Per-site aggregation | Manual loops | dplyr `group_by()` + `summarise()` | Standard tidyverse pattern; handles zero-row sites gracefully with `.groups = "drop"` |
| Recommendation text generation | Nested if/else | `case_when()` with glue strings (Pattern 3) | Cleaner than nested conditionals; `glue()` handles preferred source interpolation |

**Key insight:** Phase 26 is a diagnostic/reporting phase, not a statistical modeling phase. The field comparison logic is domain-specific (NA=NA match, payer normalization), but the aggregation and output patterns are standard dplyr/readr. Don't reinvent join or summarization logic — follow established Phase 21/22/25 patterns.

## Runtime State Inventory

> Not applicable — Phase 26 is a data transformation and reporting phase with no runtime state, external service dependencies, or OS-level registrations. All state is ephemeral (in-memory R session).

## Common Pitfalls

### Pitfall 1: Self-Join Cartesian Explosion on Large Datasets
**What goes wrong:** If you naively self-join ENCOUNTER on (ID, ADMIT_DATE) to create pairs, you get O(n²) rows per patient-date for n encounters. For a patient-date with 10 encounters from 5 sources, that's 100 rows (many duplicates).

**Why it happens:** Misunderstanding Phase 25 output format. Phase 25 CSVs already identify multi-source patient-dates (same_date_detail.csv has `source_combo` column). You don't need to rediscover pairs — just join to ENCOUNTER to fetch fields for comparison.

**How to avoid:** Load Phase 25 CSV, reshape to long format (one row per encounter per group), join to ENCOUNTER, then reshape/pivot to compare within-group. Or: for each multi-source group, fetch all encounters for that (ID, ADMIT_DATE), then compare pairwise within the group.

**Warning signs:** Join output has >100K rows when Phase 25 same-date CSV has ~10K rows; runtime >5 minutes for field extraction step.

### Pitfall 2: Forgetting Payer Sentinel Normalization (D-03)
**What goes wrong:** Comparing raw PAYER_TYPE_PRIMARY values treats "NI" as a distinct value from NA. Two encounters with (NI, NI) would match, but (NI, NA) would mismatch — violating D-03's requirement to normalize all sentinels to NA first.

**Why it happens:** Payer sentinel logic is spread across 6 values (NI, UN, OT, 99, 9999, empty). Easy to forget that "99" is a sentinel, not a valid payer code.

**How to avoid:** Apply `is_missing_payer()` helper (from Phase 19/21 pattern) to PAYER_TYPE_PRIMARY and PAYER_TYPE_SECONDARY before any field comparison. Mutate to `_norm` columns, then compare `_norm` columns, not raw.

**Warning signs:** Per-site overlap profiles show 0% Identical when you expect >50%; manual inspection of pairs shows "NI" vs NA treated as mismatch.

### Pitfall 3: Mixing Same-Date (5-field) and Same-Week (4-field) Denominators
**What goes wrong:** Computing "Partial (2/N)" without tracking whether N=5 (same-date) or N=4 (same-week). Classification labels are ambiguous across match types.

**Why it happens:** D-09 excludes DISCHARGE_DATE from same-week comparison, but it's easy to forget when reusing the same comparison function.

**How to avoid:** Add a `basis` column before field comparison (e.g., `basis = "same_date (5 fields)"`) and carry it through to classification output. Use it in the `classification_detail` column to make denominators explicit.

**Warning signs:** CSV output shows "Partial (2/4)" and "Partial (2/5)" without a way to distinguish which is which; aggregation treats them as the same class.

### Pitfall 4: Not Handling Zero-Row Sites in Aggregation
**What goes wrong:** Per-site aggregation via `group_by(SITE)` fails if a site has zero multi-source encounters. The site won't appear in output, breaking cross-site summary comparisons.

**Why it happens:** Phase 25 might find zero multi-source dates for a site (e.g., if all encounters are from a single SOURCE). `group_by()` + `summarise()` drops empty groups.

**How to avoid:** Use `.groups = "drop"` in summarise to avoid lingering groups, and consider `complete(SITE, fill = list(n_multi_source_pairs = 0))` to backfill missing sites if needed for cross-site comparison CSV.

**Warning signs:** Per-site summary CSV has 4 rows when there are 5 sites in the dataset; missing site has all single-source encounters.

## Code Examples

Verified patterns from canonical references:

### HIPAA Suppression (Phase 25 pattern, reused for Phase 26 count columns)
```r
# Source: R/22_multi_source_overlap_detection.R lines 47-60
hipaa_suppress <- function(x) {
  x_num <- suppressWarnings(as.numeric(x))
  ifelse(!is.na(x_num) & x_num >= 1 & x_num <= 10, "<11", as.character(x))
}

suppress_counts <- function(df) {
  count_cols <- grep("^n_|^n$|_count$|_pairs$|_affected$|_dates$|_encounters$|_patients$|^rank$",
                     names(df), value = TRUE)
  # Exclude columns that are not counts (rates, pcts)
  count_cols <- count_cols[!grepl("pct_|_rate$|_pct$", count_cols)]
  df %>%
    mutate(across(all_of(count_cols), ~ hipaa_suppress(.x)))
}
```

### Payer Missingness Helper (Phase 19/21 pattern, reused for D-03)
```r
# Source: R/21_all_site_duplicate_dates.R lines 48-52
is_missing_payer <- function(payer_value) {
  is.na(payer_value) |
    nchar(trimws(payer_value)) == 0 |
    payer_value %in% c("NI", "UN", "OT", "99", "9999")
}
```

### Console Output with Section Headers (Phase 22/25 pattern)
```r
# Source: R/22_multi_source_overlap_detection.R lines 66-69
message(glue("\n{strrep('=', 70)}"))
message("MULTI-SOURCE OVERLAP CLASSIFICATION")
message("Phase 26: Field-by-field comparison and deduplication recommendations")
message(glue("{strrep('=', 70)}\n"))
```

### Date Parsing with Fallback (Phase 21/22/25 pattern)
```r
# Source: R/21_all_site_duplicate_dates.R lines 153-178
enc <- enc %>%
  mutate(admit_date_parsed = as.Date(ADMIT_DATE, format = "%Y-%m-%d"))

n_admit_raw <- sum(!is.na(enc$ADMIT_DATE) & nchar(trimws(enc$ADMIT_DATE)) > 0)
n_admit_parsed <- sum(!is.na(enc$admit_date_parsed))
admit_parse_rate <- if (n_admit_raw > 0) round(100 * n_admit_parsed / n_admit_raw, 1) else 100

if (n_admit_raw > 0 && admit_parse_rate < 50) {
  message(glue("  Standard date parse rate only {admit_parse_rate}% -- trying parse_pcornet_date()"))
  if (file.exists("R/utils_dates.R")) {
    source("R/utils_dates.R")
    enc <- enc %>%
      mutate(admit_date_parsed = parse_pcornet_date(ADMIT_DATE))
    n_admit_parsed <- sum(!is.na(enc$admit_date_parsed))
    message(glue("  After parse_pcornet_date: {format(n_admit_parsed, big.mark=',')} parsed"))
  }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual deduplication without data quality assessment | Diagnostic field comparison → informed deduplication | Phase 26 (current) | Prevents loss of genuinely distinct encounters; identifies sites where multi-source is true duplication vs data submission artifacts |
| Treat all multi-source dates as duplicates | Classify as Identical/Partial/Distinct | Phase 26 (current) | Site-specific strategies; UFH+FLM might have 80% Identical (dedupe), AMS might have 60% Distinct (retain all) |
| Global payer completeness metric | Source-specific payer completeness within multi-source encounters | Phase 26 (current) | Preferred source recommendations are context-aware; source with best payer data for overlapping encounters might differ from overall best source |

**Deprecated/outdated:**
- **Naive duplicate removal**: Older data quality scripts might remove all same-date encounters from secondary sources without assessing field concordance. Phase 26 approach is to classify first, recommend per-site, then (in future phases) implement source preference filters only where Identical % is high.

## Environment Availability

> Skipped — Phase 26 has no external dependencies beyond existing R packages already installed in project environment. No CLI tools, services, or runtimes beyond RStudio on HiPerGator.

All required packages (dplyr, readr, glue, stringr, lubridate) are already in `renv.lock` from Phases 1-25. No new installations needed.

## Validation Architecture

> Skipped — `workflow.nyquist_validation` is explicitly set to `false` in `.planning/config.json`.

No test framework integration for Phase 26. Validation occurs via human review of HiPerGator console output and CSV spot-checks after execution.

## Sources

### Primary (HIGH confidence)
- R/22_multi_source_overlap_detection.R (Phase 25) — Input CSV format, HIPAA suppression pattern, console output structure
- R/21_all_site_duplicate_dates.R (Phase 22) — `is_missing_payer()` helper, SOURCE rename pattern, per-site recommendation pattern, payer completeness comparison
- R/18_uf_insurance_missingness.R (Phase 19) — Payer sentinel definition (NI, UN, OT, 99, 9999), missingness flag computation
- R/00_config.R — CONFIG object, PAYER_MAPPING, output_dir path
- .planning/phases/26-overlap-classification-and-recommendations/26-CONTEXT.md — D-01 to D-10 user decisions, requirements OVRLP-01 to OUTPT-03
- .planning/REQUIREMENTS.md — OVRLP-01 to OVRLP-04, OUTPT-01 to OUTPT-03

### Secondary (MEDIUM confidence)
- R tidyverse documentation (dplyr 1.2.0, readr 2.2.0, tidyr 1.3.1) — Standard join and summarization patterns verified against official package docs

### Tertiary (LOW confidence)
- None — Phase 26 is a straightforward data transformation task with established patterns from prior phases. No external research sources required.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — All packages already installed, versions confirmed in project renv.lock
- Architecture: HIGH — Direct application of Phase 21/22/25 patterns; no novel architecture needed
- Pitfalls: HIGH — Pitfalls derived from known Phase 21/22/25 implementation challenges (self-join explosion, payer normalization, HIPAA suppression)
- Field comparison logic: HIGH — D-01 to D-10 are explicit and unambiguous; NA handling is well-defined
- Recommendation thresholds: MEDIUM — D-07 thresholds (70%/30%) are user-provided and fixed; no research needed, but thresholds are arbitrary (not literature-derived)

**Research date:** 2026-04-22
**Valid until:** 90 days (R package ecosystem is stable; dplyr/readr APIs unlikely to change before Phase 26 execution)
