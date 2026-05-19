# Phase 02: Add Descriptions of Codes to the Gantt CSVs - Research

**Researched:** 2026-05-19
**Domain:** R data enrichment with static lookup tables
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Static lookup table built from existing data sources — no NLM API calls at runtime. Sources: (1) Phase 39-41 RDS artifacts (`unmatched_codes_classified.rds` + `unmatched_ndc_classified.rds`) with NLM API lookup results, (2) R/00_config.R inline comments for curated codes, (3) R/45 `hardcoded_descriptions` for retired radiation CPT codes.
- **D-02:** Lookup stored as a standalone `code_descriptions.rds` file (named character vector: code -> description). Built once via a helper script, loaded by R/49 at runtime. Reusable by other scripts if needed.
- **D-03:** Detail table (`gantt_detail.csv`): add a `triggering_code_description` column alongside `triggering_code`. One description per row.
- **D-04:** Episodes table (`gantt_episodes.csv`): add a `triggering_code_descriptions` column (note: plural) with descriptions in the same comma-separated order as the `triggering_codes` column. E.g., codes=`J9000,J9040` -> descriptions=`Doxorubicin HCl,Bleomycin sulfate`.
- **D-05:** When a code has no description in the lookup, use an empty string. The code is still present in the `triggering_code`/`triggering_codes` column for reference.
- **D-06:** Add description columns to both Gantt CSVs only. Do not modify R/44's per-type xlsx workbooks — those are a separate output with their own format.

### Claude's Discretion
- Helper script naming and numbering (following R/NN_*.R pattern)
- Whether to extract config inline comments programmatically or transcribe manually into the lookup builder
- Column ordering for the new description columns (likely placed immediately after the code column)

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope
</user_constraints>

## Summary

Phase 02 enriches the Gantt chart CSV exports with human-readable code descriptions so downstream consumers can understand treatment codes without external lookups. The phase involves building a static code description lookup table from three existing sources (Phase 39-41 RDS artifacts with NLM API results, R/00_config.R inline comments, and R/45 hardcoded descriptions for retired codes) and modifying R/49_gantt_data_export.R to add description columns to both CSV outputs.

The technical approach is straightforward: create a helper script to build a named character vector (code -> description) saved as `code_descriptions.rds`, then load this lookup in R/49 and use it to add description columns via dplyr's `mutate()` with vectorized lookups. The detail table gets one description per row; the episode table gets comma-separated descriptions matching the order of comma-separated codes.

**Primary recommendation:** Use `setNames()` or `purrr::set_names()` to create the named vector from tibbles, combine sources with `c()`, use dplyr's join or vectorized bracket lookup for enrichment, and use `paste(collapse=",")` for comma-separated episode descriptions.

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| dplyr | 1.1.4+ | Data manipulation | Already in use throughout project; `mutate()`, `select()`, `left_join()` for adding columns |
| purrr | 1.0.2+ | Functional programming | `set_names()` for creating named vectors; `map_chr()` for vectorized lookups |
| glue | 1.8.0+ | String formatting | Already in use; readable logging messages |
| stringr | 1.5.1+ | String operations | Already in use; `str_split()` for comma-separated codes if needed |

**Version verification:** All versions are already in use in the existing codebase (R/00_config.R sources tidyverse, R/49 uses dplyr and glue). No new package installations required.

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| readr | 2.1.5+ | CSV reading (via tidyverse) | Already available; not needed (using base R `write.csv()` pattern from R/49) |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Named vector (`c()`) | Tibble lookup with left_join | Named vector is O(1) hash lookup; join is more verbose for simple 1:1 mapping |
| `paste(collapse=",")` | `str_c()` from stringr | Both work identically; paste is base R, str_c is tidyverse style |
| Vectorized bracket `[]` | `map_chr()` with lambda | Bracket lookup is more concise for simple named vector access |

## Architecture Patterns

### Recommended Project Structure
```
R/
├── 48_build_code_descriptions.R   # Helper script (NEW)
├── 49_gantt_data_export.R         # Modified to load lookup and add columns
└── 00_config.R                    # Existing inline comments source

cache/outputs/
└── code_descriptions.rds          # Static lookup (NEW artifact)

output/
├── gantt_episodes.csv             # Modified: adds triggering_code_descriptions column
└── gantt_detail.csv               # Modified: adds triggering_code_description column
```

**Rationale for script numbering:** Number 48 fits between Phase 45-47 radiation/cross-reference work (45-46 already exist, 47 likely next) and the Gantt export (49). The helper script logically precedes the Gantt export that consumes it.

### Pattern 1: Building Named Character Vector from Multiple Sources

**What:** Combine three description sources into a single named vector

**When to use:** When you have multiple tibbles/vectors with code->description mappings

**Example:**
```r
# Source 1: Phase 39 RDS (CPT/HCPCS codes with API lookup results)
hcpcs_rds <- readRDS(file.path(CONFIG$output_dir, "unmatched_codes_classified.rds"))
hcpcs_lookup <- setNames(hcpcs_rds$description, hcpcs_rds$code)

# Source 2: Phase 40 RDS (NDC/RXNORM codes with drug names)
ndc_rds <- readRDS(file.path(CONFIG$output_dir, "unmatched_ndc_classified.rds"))
ndc_lookup <- setNames(ndc_rds$drug_name, ndc_rds$code)

# Source 3: R/45 hardcoded descriptions (retired radiation CPT codes)
# Already exists as named vector in R/45_radiation_cpt_audit.R lines 87-124
source("R/45_radiation_cpt_audit.R")  # Loads hardcoded_descriptions

# Source 4: R/00_config.R inline comments (extract manually or programmatically)
config_lookup <- c(
  "J9000" = "Doxorubicin HCl (Adriamycin)",
  "J9040" = "Bleomycin sulfate",
  "J9360" = "Vinblastine sulfate"
  # ... transcribe from R/00_config.R lines 414-520
)

# Combine all sources (later sources overwrite earlier for duplicates)
all_descriptions <- c(hcpcs_lookup, ndc_lookup, hardcoded_descriptions, config_lookup)

# Save as RDS
saveRDS(all_descriptions, file.path(CONFIG$cache$outputs_dir, "code_descriptions.rds"))
```

**Source:** Existing patterns in R/41_combine_reports.R (lines 58-76) for harmonizing Phase 39/40 RDS; R/45_radiation_cpt_audit.R (lines 87-124) for named vector pattern.

### Pattern 2: Enriching Detail Table (One Description Per Row)

**What:** Add single description column to detail table

**When to use:** When each row has one code that needs one description

**Example:**
```r
# Load lookup
code_descriptions <- readRDS(file.path(CONFIG$cache$outputs_dir, "code_descriptions.rds"))

# Load detail data
detail <- readRDS(DETAIL_RDS)

# Add description column using vectorized lookup (per D-05: empty string if missing)
detail_export <- detail %>%
  select(
    patient_id, treatment_type, treatment_date, triggering_code,
    episode_number, episode_start, episode_stop, historical_flag
  ) %>%
  mutate(
    triggering_code_description = ifelse(
      is.na(triggering_code) | triggering_code == "",
      "",
      ifelse(triggering_code %in% names(code_descriptions),
             code_descriptions[triggering_code],
             "")
    )
  )
```

**Source:** Existing column selection pattern in R/49_gantt_data_export.R lines 106-110; vectorized named vector lookup is standard R idiom.

### Pattern 3: Enriching Episode Table (Comma-Separated Descriptions)

**What:** Split comma-separated codes, look up each, rejoin descriptions in same order

**When to use:** When a column contains comma-separated codes that need comma-separated descriptions

**Example:**
```r
# Load lookup
code_descriptions <- readRDS(file.path(CONFIG$cache$outputs_dir, "code_descriptions.rds"))

# Helper function to map comma-separated codes to comma-separated descriptions
map_codes_to_descriptions <- function(codes_str) {
  if (is.na(codes_str) || codes_str == "") {
    return("")
  }

  codes <- str_split(codes_str, ",")[[1]]

  descriptions <- sapply(codes, function(code) {
    if (code %in% names(code_descriptions)) {
      code_descriptions[[code]]
    } else {
      ""
    }
  }, USE.NAMES = FALSE)

  paste(descriptions, collapse = ",")
}

# Load episode data
episodes <- readRDS(EPISODES_RDS)

# Add descriptions column
episodes_export <- episodes %>%
  select(
    patient_id, treatment_type, episode_number,
    episode_start, episode_stop, episode_length_days,
    distinct_dates_in_episode, historical_flag, triggering_codes
  ) %>%
  mutate(
    triggering_code_descriptions = sapply(triggering_codes, map_codes_to_descriptions, USE.NAMES = FALSE)
  )
```

**Source:** Adapted from R/44_treatment_episodes.R pattern for handling comma-separated triggering_codes (lines 84-86 use `paste(sort(unique(...)), collapse=",")`); stringr split/rejoin is standard tidyverse idiom documented in [R-bloggers: Collapse Text by Group](https://www.r-bloggers.com/2024/05/how-to-collapse-text-by-group-in-a-data-frame-using-r/).

### Anti-Patterns to Avoid

- **Don't use left_join for simple 1:1 vectorized lookup:** Named vector bracket access is more efficient and concise than creating a temporary tibble for joining when you just need a simple code->description map.
- **Don't load source scripts multiple times:** If you `source("R/45_radiation_cpt_audit.R")` to get `hardcoded_descriptions`, don't re-source R/00_config.R unnecessarily — it's already sourced by the calling script.
- **Don't modify R/49 to duplicate description extraction logic:** Keep all description source handling in the helper script. R/49 should only load the pre-built lookup and use it.
- **Don't forget to handle NA triggering_codes:** TUMOR_REGISTRY sources produce `NA_character_` triggering_codes per Phase 46 decisions (R/44 lines 68). These must get empty string descriptions, not errors.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Extracting inline comments from R source | Regex parsing R comments to extract descriptions | Manual transcription or simple `readLines()` + `grep()` | R comments aren't structured data; parsing is fragile. 30 curated codes from R/00_config.R lines 414-520 are manageable to transcribe. If programmatic, use `readLines()` + `grep("#")` to extract, then manually validate. |
| Comma-separated string operations | Custom split/map/join loop | `stringr::str_split()` + `sapply()` + `paste(collapse=",")` | Standard R idiom; readable and debugged. Reinventing string splitting adds bugs. |
| Named vector creation from tibble | Manual loop building named vector | `setNames(values, names)` or `purrr::set_names()` | Base R `setNames()` is optimized and error-checked. Manual loops risk mismatched lengths. |

**Key insight:** Named character vectors are a core R data structure with excellent built-in support. Use them directly rather than building wrapper abstractions.

## Runtime State Inventory

> Omitted — Phase 02 is not a rename/refactor/migration phase. This is greenfield data enrichment work.

## Common Pitfalls

### Pitfall 1: Mismatched Comma-Separated Order
**What goes wrong:** Splitting codes, sorting descriptions alphabetically, and rejoining produces descriptions in a different order than the original codes.
**Why it happens:** Natural instinct to sort for consistency, but requirement D-04 explicitly states "same comma-separated order."
**How to avoid:** Do NOT sort descriptions. Use `sapply()` to preserve input order when mapping codes to descriptions.
**Warning signs:** Test case with codes="J9040,J9000" (alphabetically reversed) should produce descriptions in that same order, not alphabetically sorted.

### Pitfall 2: NA Handling in Vectorized Lookup
**What goes wrong:** `code_descriptions[NA_character_]` returns `NA`, which then gets coerced to string "NA" instead of empty string.
**Why it happens:** R's vectorized bracket operator doesn't treat NA specially.
**How to avoid:** Wrap lookup in `ifelse(is.na(triggering_code) | triggering_code == "", "", ...)` to explicitly handle NA before lookup.
**Warning signs:** CSV contains literal "NA" string in description column instead of empty cells.

### Pitfall 3: Description Source Precedence
**What goes wrong:** Phase 39 RDS overwrites R/00_config.R curated descriptions with generic API results, losing human-annotated detail.
**Why it happens:** Order of combining sources matters. `c(source1, source2)` means source2 overwrites source1 for duplicate keys.
**How to avoid:** Combine sources in precedence order: API results FIRST (lowest precedence), config comments LAST (highest precedence). Final combine order: `c(hcpcs_lookup, ndc_lookup, hardcoded_descriptions, config_lookup)`.
**Warning signs:** J9000 shows generic "Injection, doxorubicin hydrochloride" from API instead of curated "Doxorubicin HCl (Adriamycin)" from config.

### Pitfall 4: Script Numbering Collision
**What goes wrong:** Numbering helper script as R/50 creates confusion when Phase 47 work needs to be numbered in sequence with 45-46.
**Why it happens:** Choosing next available number without considering the logical dependency flow.
**How to avoid:** Number 48 (between existing radiation work and Gantt export). The helper builds an artifact consumed by R/49, so it must be numbered before 49.
**Warning signs:** Developer confusion about execution order; temptation to renumber later.

## Code Examples

Verified patterns from existing codebase:

### Extracting Named Vector from RDS Tibble
```r
# Source: R/41_combine_reports.R lines 58-64 (harmonization pattern)
# Load Phase 39 RDS artifact
hcpcs_classified <- readRDS(file.path(CONFIG$output_dir, "unmatched_codes_classified.rds"))

# Schema: columns are code, description, n_records, n_patients, classification, heuristic_type, lookup_status
# Create named vector: code -> description
hcpcs_lookup <- setNames(hcpcs_classified$description, hcpcs_classified$code)

# Example result:
# hcpcs_lookup["J9025"] returns "Injection, azacitidine, 1 mg"
```

### Existing Hardcoded Descriptions Pattern
```r
# Source: R/45_radiation_cpt_audit.R lines 87-124
# Already defined as named character vector
hardcoded_descriptions <- c(
  "77404" = "Radiation treatment delivery; single area, 6-10 MeV (DELETED 2015)",
  "77408" = "Radiation treatment delivery; 2 separate areas, 3+ ports, 6-10 MeV (DELETED 2015)",
  # ... 24 total codes
)

# This vector can be reused directly via source() or copy-paste
```

### Current R/49 Column Selection Pattern
```r
# Source: R/49_gantt_data_export.R lines 98-110
# Episode-level bars table: 9 columns in specified order
episodes_export <- episodes %>%
  select(
    patient_id, treatment_type, episode_number,
    episode_start, episode_stop, episode_length_days,
    distinct_dates_in_episode, historical_flag, triggering_codes
  )

# Modify to add 10th column:
episodes_export <- episodes %>%
  select(
    patient_id, treatment_type, episode_number,
    episode_start, episode_stop, episode_length_days,
    distinct_dates_in_episode, historical_flag, triggering_codes
  ) %>%
  mutate(triggering_code_descriptions = map_codes_to_descriptions(triggering_codes))
```

### Handling Comma-Separated Codes
```r
# Pattern from R/44_treatment_episodes.R lines 84-86 (building comma-separated codes)
# Reverse pattern: split, map, rejoin

# Split comma-separated string
codes_vector <- str_split("J9000,J9040,J9360", ",")[[1]]
# Result: c("J9000", "J9040", "J9360")

# Map each to description
descriptions_vector <- sapply(codes_vector, function(code) {
  if (code %in% names(code_descriptions)) {
    code_descriptions[[code]]
  } else {
    ""
  }
}, USE.NAMES = FALSE)

# Rejoin with comma
descriptions_string <- paste(descriptions_vector, collapse = ",")
# Result: "Doxorubicin HCl (Adriamycin),Bleomycin sulfate,Vinblastine sulfate"
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| N/A | Static RDS lookup with named vector | Phase 02 (new feature) | First time descriptions are exposed in Gantt CSVs |

**Deprecated/outdated:**
None — this is greenfield work adding new functionality.

## Open Questions

1. **Should config inline comments be extracted programmatically or transcribed manually?**
   - What we know: R/00_config.R lines 414-520 have ~30 curated codes with inline comments like `"J9000", # Doxorubicin HCl (Adriamycin)`
   - What's unclear: Is programmatic extraction worth the fragility risk for 30 codes?
   - Recommendation: Transcribe manually for initial version. Comments are unstructured and span multiple lines (e.g., "ABVD regimen:" header line). Programmatic extraction with `readLines()` + `grep()` is possible but requires careful validation. Manual transcription is safer and takes ~15 minutes. If future phases add hundreds more codes, revisit programmatic extraction.

2. **What about ICD-10-PCS codes that have no descriptions?**
   - What we know: Phase 39 verification notes "Some ICD-10-PCS codes (XW033A3, XW033B3, etc.) were noted as 'no description' even after API lookup"
   - What's unclear: Should we provide generic fallback descriptions like "ICD-10-PCS code" or leave empty per D-05?
   - Recommendation: Leave empty per D-05. Empty string signals "lookup attempted but not found" which is accurate. Generic fallbacks would be misleading (third-party consumer might think it's an actual description).

3. **Should the lookup builder be idempotent (re-runnable)?**
   - What we know: Lookup sources are stable (RDS artifacts from Phase 39-40, hardcoded vector from R/45, config comments)
   - What's unclear: Do we need to regenerate if config changes?
   - Recommendation: Yes, make it re-runnable. Use a simple pattern: always read all sources, combine, overwrite RDS. If someone adds a code to R/00_config.R later, they can re-run the builder. Add a message logging how many descriptions were loaded from each source for transparency.

## Environment Availability

> Skipped — Phase 02 has no external dependencies beyond existing R packages (dplyr, purrr, glue, stringr) which are already installed and in use in the project. All work runs in RStudio on HiPerGator with existing environment.

## Sources

### Primary (HIGH confidence)
- **Existing codebase:** R/49_gantt_data_export.R (current CSV export pattern), R/44_treatment_episodes.R (triggering_codes column), R/41_combine_reports.R (RDS harmonization pattern), R/45_radiation_cpt_audit.R (hardcoded_descriptions named vector), R/00_config.R (inline comments source)
- **CONTEXT.md:** User decisions D-01 through D-06 provide exact requirements
- **STATE.md:** Lines 62-75 document Phase 39-41 decisions about RDS schema and API lookup patterns

### Secondary (MEDIUM confidence)
- [R-bloggers: Collapse Text by Group](https://www.r-bloggers.com/2024/05/how-to-collapse-text-by-group-in-a-data-frame-using-r/) - paste collapse pattern
- [rlang::set_names documentation](https://rlang.r-lib.org/reference/set_names.html) - named vector creation
- [sqlpad.io: Concatenate Strings with paste and collapse](https://sqlpad.io/tutorial/concatenate-strings-paste-collapse/) - paste vs collapse semantics

### Tertiary (LOW confidence)
None — all research grounded in existing codebase or official R package documentation

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All packages already in use in the project
- Architecture: HIGH - Patterns extracted directly from existing R/41, R/44, R/45, R/49 scripts
- Pitfalls: HIGH - Based on R's documented NA handling, string vectorization semantics, and named vector precedence rules
- Code examples: HIGH - All examples sourced from existing project code with line numbers

**Research date:** 2026-05-19
**Valid until:** 60 days (stable domain — R base data structures and tidyverse patterns don't change rapidly)
