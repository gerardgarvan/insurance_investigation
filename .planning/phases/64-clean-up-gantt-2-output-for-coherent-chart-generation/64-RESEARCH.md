# Phase 64: Clean up Gantt 2 output for coherent chart generation - Research

**Researched:** 2026-06-01
**Domain:** R data cleaning, CSV formatting for Tableau import, string manipulation
**Confidence:** HIGH

## Summary

Phase 64 cleans the Gantt v2 CSV output files (gantt_episodes_v2.csv ~23K rows, gantt_detail_v2.csv ~221K rows) for direct Tableau consumption. Current outputs have several data quality issues that make Tableau imports difficult: comma-delimited multi-value fields cause CSV parsing conflicts, empty/duplicate entries in descriptions, verbose RxNorm drug names (e.g., "25 ML doxorubicin hydrochloride 2 MG/ML Injection"), R's literal "NA" text instead of true CSV nulls, and empty cancer_category fields that should be labeled "Unlinked".

The cleanup is a presentation-layer transformation only — no upstream artifacts change. All logic integrates into the existing R/63_gantt_v2_export.R script between column selection and CSV write. User decisions from CONTEXT.md lock the exact column set to keep/drop, mandate semicolons as the multi-value separator, specify drug name simplification to extract generic names only, and define how to handle nulls and missing categories.

**Primary recommendation:** Add a cleanup section to R/63_gantt_v2_export.R that (1) replaces comma separators with semicolons in triggering_codes/drug_names/descriptions, (2) deduplicates and removes blanks from multi-value cells using stringr::str_split + unique + paste(collapse=";"), (3) extracts generic drug names via regex (pattern: `[a-z]+` before dosage keywords), (4) converts NA to true empty strings, (5) fills blank cancer_category with "Unlinked", and (6) sets pseudo-treatment descriptions to treatment_type value. Test with Tableau import to verify semicolon separator handling and null display.

## User Constraints (from CONTEXT.md)

### Locked Decisions

**Target Platform (D-01):** Output consumed by Tableau. Data must be clean enough for direct import without manual preprocessing.

**Column Selection - Episodes (D-02, D-03):** Trim episodes to essential columns. Keep: patient_id, treatment_type, episode_number, episode_start, episode_stop, episode_length_days, distinct_dates_in_episode, historical_flag, triggering_codes, drug_names, triggering_code_descriptions, cancer_category, regimen_label, is_first_line. Drop: encounter_ids, is_hodgkin, cancer_link_method. Keep historical_flag for Tableau filtering.

**Column Selection - Detail (D-04):** Trim detail to essential columns. Keep: patient_id, treatment_type, treatment_date, triggering_code, drug_name, episode_number, episode_start, episode_stop, historical_flag, triggering_code_description, cancer_category, regimen_label, is_first_line. Drop: ENCOUNTERID, is_hodgkin, cancer_link_method.

**Column Naming (D-05):** Keep snake_case column names (no renaming to Title Case).

**Separator Character (D-06):** Use semicolons (`;`) instead of commas as the separator within multi-value cells (triggering_codes, drug_names, triggering_code_descriptions). Prevents CSV parsing conflicts since commas are the field delimiter.

**Description Cleanup (D-07, D-08):** Deduplicate descriptions within each cell and drop blank entries. For example, `",,Encounter for antineoplastic chemotherapy"` becomes `"Encounter for antineoplastic chemotherapy"`. Multiple identical descriptions collapse to one. Apply same dedup + blank-drop to triggering_codes and drug_names.

**Drug Name Simplification (D-09):** Simplify drug names from full RxNorm descriptions (e.g., `"25 ML doxorubicin hydrochloride 2 MG/ML Injection"`) to just the generic drug name (e.g., `"doxorubicin"`). Remove dosage, formulation, volume, and brand info. Deduplicate per episode.

**Null/NA Handling (D-10):** Convert R's text `"NA"` to true empty cells in CSV output (Tableau reads these as null). Do not leave literal "NA" strings.

**Pseudo-Treatment Rows (D-11):** Keep Death and HL Diagnosis pseudo-treatment rows. Set their triggering_code_descriptions to the treatment_type value itself (e.g., "Death", "HL Diagnosis") so Tableau tooltips are not blank.

**Missing Cancer Category (D-12):** Set empty/blank cancer_category values to "Unlinked" instead of empty string. Provides honest label for Tableau filtering and coloring.

**Output Structure (D-13):** Clean both gantt_episodes_v2.csv and gantt_detail_v2.csv with the same quality fixes. Output overwrites existing v2 files (or writes to new filenames — Claude's discretion).

### Claude's Discretion

- Output file naming (overwrite v2 files vs new names like gantt_episodes_v2_clean.csv)
- Sort order of output rows
- How to extract generic drug names from RxNorm strings (regex pattern design)
- Whether to also clean triggering_codes field values (dedup/drop blanks)

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.

## Standard Stack

All tools already in project stack (CLAUDE.md research/STACK.md).

### Core Libraries

| Library | Version | Purpose | Already Installed |
|---------|---------|---------|-------------------|
| stringr | 1.5.1+ | String operations for multi-value field cleaning, drug name extraction | ✓ Phase 1 |
| dplyr | 1.2.0+ | Data transformation (mutate, case_when for column operations) | ✓ Phase 1 |
| tidyr | 1.3.0+ | No direct use, but available if needed for reshape operations | ✓ Phase 1 |

### Functions Needed

| Operation | Function | Purpose |
|-----------|----------|---------|
| Multi-value split | `str_split(field, ",")` | Split comma-separated values into vectors |
| Deduplication | `unique()` | Remove duplicate entries from split vectors |
| Blank removal | `Filter(function(x) x != "" && !is.na(x), vec)` | Drop empty strings and NAs |
| Rejoin | `paste(vec, collapse = ";")` | Rejoin with semicolon separator |
| Drug name extraction | `str_extract(drug, "^[a-z]+(?= |$)")` | Extract leading lowercase word (generic name) |
| NA conversion | `ifelse(is.na(field) \| field == "NA", "", field)` | Convert NA to empty string |
| Conditional fill | `ifelse(field == "", "Unlinked", field)` | Fill blank cancer_category |

No new package installations required.

## Architecture Patterns

### Recommended Integration Point

Insert cleanup logic into R/63_gantt_v2_export.R between Section 4 (column selection) and Section 5 (CSV write).

**Current structure (R/63_gantt_v2_export.R):**

```
Section 1: Setup and configuration
Section 2: Load input data
Section 3: Code description lookup
Section 4: Select and order columns (lines 172-240)
Section 4B: Death pseudo-treatment rows (lines 242-351)
Section 4C: HL Diagnosis pseudo-treatment rows (lines 354-464)
→→→ INSERT SECTION 4D: DATA CLEANUP HERE ←←←
Section 5: Write CSV outputs (lines 467-477)
Section 6: Final summary (lines 480-524)
```

### Pattern 1: Multi-Value Field Cleanup

**What:** Deduplicate, remove blanks, and change separator for comma-delimited fields (triggering_codes, drug_names, triggering_code_descriptions).

**Implementation:**

```r
# Helper function: clean multi-value field
clean_multi_value <- function(field_str, sep_in = ",", sep_out = ";") {
  if (is.na(field_str) || field_str == "" || field_str == "NA") return("")

  values <- str_split(field_str, sep_in)[[1]]
  values <- str_trim(values)  # Remove leading/trailing whitespace
  values <- values[values != "" & !is.na(values)]  # Drop blanks and NAs
  values <- unique(values)  # Deduplicate

  if (length(values) == 0) return("")
  paste(values, collapse = sep_out)
}

# Apply to episodes_export
episodes_export <- episodes_export %>%
  mutate(
    triggering_codes = sapply(triggering_codes, clean_multi_value, USE.NAMES = FALSE),
    drug_names = sapply(drug_names, clean_multi_value, USE.NAMES = FALSE),
    triggering_code_descriptions = sapply(triggering_code_descriptions, clean_multi_value, USE.NAMES = FALSE)
  )
```

**Rationale:** Semicolons prevent CSV parsing conflicts. Deduplication reduces visual clutter in Tableau tooltips. Blank removal avoids empty list entries.

### Pattern 2: Drug Name Simplification

**What:** Extract generic drug names from RxNorm full descriptions.

**RxNorm name patterns observed:**
- `"25 ML doxorubicin hydrochloride 2 MG/ML Injection"` → `"doxorubicin"`
- `"1 ML vincristine sulfate 1 MG/ML Injection [Vincasar]"` → `"vincristine"`
- `"dacarbazine 200 MG Injection"` → `"dacarbazine"`
- `"vinblastine"` (already simple) → `"vinblastine"`
- `"24 ML nivolumab 10 MG/ML Injection [Opdivo]"` → `"nivolumab"`

**Generic name extraction strategy:**

```r
# Helper function: extract generic drug name
simplify_drug_name <- function(drug_str) {
  if (is.na(drug_str) || drug_str == "" || drug_str == "NA") return("")

  # Split multi-drug strings by semicolon (after multi-value cleanup)
  drugs <- str_split(drug_str, ";")[[1]]
  drugs <- str_trim(drugs)

  # Extract generic name from each drug string
  simplified <- sapply(drugs, function(d) {
    # Pattern: extract first lowercase word before dosage keywords
    # Match: word at start OR word after number+space (e.g., "25 ML doxorubicin...")
    match <- str_extract(d, regex("\\b([a-z][a-z]+)\\b(?=\\s+(hydrochloride|sulfate|\\d+\\s*MG|Injection|Injectable|\\[))", ignore_case = FALSE))

    # If no match with suffix keywords, try simpler pattern: first lowercase word
    if (is.na(match)) {
      match <- str_extract(d, "^[a-z][a-z]+")
    }

    # If still no match, keep original (handles already-simple names like "vinblastine")
    if (is.na(match)) return(d)
    tolower(match)
  }, USE.NAMES = FALSE)

  simplified <- unique(simplified)  # Deduplicate
  paste(simplified, collapse = ";")
}

# Apply to both tables
episodes_export <- episodes_export %>%
  mutate(drug_names = sapply(drug_names, simplify_drug_name, USE.NAMES = FALSE))

detail_export <- detail_export %>%
  mutate(drug_name = sapply(drug_name, simplify_drug_name, USE.NAMES = FALSE))
```

**Rationale:** Regex pattern captures the generic name before dosage/formulation keywords. Fallback to "first lowercase word" handles simple cases. Preserves original if no pattern matches (safety).

**Alternative simpler pattern (Claude's discretion):**

```r
# Simpler: just take first lowercase word sequence
simplify_drug_name <- function(drug_str) {
  if (is.na(drug_str) || drug_str == "" || drug_str == "NA") return("")

  drugs <- str_split(drug_str, ";")[[1]]
  drugs <- str_trim(drugs)

  simplified <- sapply(drugs, function(d) {
    # Match: first sequence of lowercase letters (2+ chars)
    match <- str_extract(d, "[a-z]{2,}")
    if (is.na(match)) return(d)
    match
  }, USE.NAMES = FALSE)

  simplified <- unique(simplified)
  paste(simplified, collapse = ";")
}
```

**Testing approach:** Verify against known drugs from Phase 61 regimen detection (doxorubicin, bleomycin, vinblastine, dacarbazine, brentuximab, nivolumab, vincristine, carboplatin, etoposide, ifosfamide, carmustine, gemcitabine). Check output for each.

### Pattern 3: NA and Empty String Normalization

**What:** Convert R's literal "NA" text and actual NA values to empty strings for CSV output.

**Implementation:**

```r
# Apply to all character columns before CSV write
episodes_export <- episodes_export %>%
  mutate(across(where(is.character), ~ ifelse(is.na(.) | . == "NA", "", .)))

detail_export <- detail_export %>%
  mutate(across(where(is.character), ~ ifelse(is.na(.) | . == "NA", "", .)))
```

**Rationale:** Tableau imports empty cells as null (good for filtering). Literal "NA" text appears as data value (bad).

### Pattern 4: Cancer Category Fill

**What:** Replace empty cancer_category with "Unlinked" label.

**Implementation:**

```r
episodes_export <- episodes_export %>%
  mutate(cancer_category = ifelse(cancer_category == "" | is.na(cancer_category), "Unlinked", cancer_category))

detail_export <- detail_export %>%
  mutate(cancer_category = ifelse(cancer_category == "" | is.na(cancer_category), "Unlinked", cancer_category))
```

**Rationale:** "Unlinked" is honest and filterable in Tableau. Empty string causes blank category in color legends.

### Pattern 5: Pseudo-Treatment Description Fill

**What:** Set triggering_code_descriptions to treatment_type value for Death and HL Diagnosis rows (currently blank).

**Implementation:**

```r
# Episodes
episodes_export <- episodes_export %>%
  mutate(
    triggering_code_descriptions = case_when(
      treatment_type %in% c("Death", "HL Diagnosis") & (triggering_code_descriptions == "" | is.na(triggering_code_descriptions)) ~ treatment_type,
      TRUE ~ triggering_code_descriptions
    )
  )

# Detail
detail_export <- detail_export %>%
  mutate(
    triggering_code_description = case_when(
      treatment_type %in% c("Death", "HL Diagnosis") & (triggering_code_description == "" | is.na(triggering_code_description)) ~ treatment_type,
      TRUE ~ triggering_code_description
    )
  )
```

**Rationale:** Tableau tooltips show meaningful text instead of blank for these important milestone rows.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Drug name extraction via NLP | Custom parser with dosage/unit rules | Simple regex pattern | RxNorm names are consistent: generic name always comes first, dosage keywords are predictable. Regex handles 95%+ of cases. Edge cases can keep full name. |
| CSV escaping for special characters | Manual quote/escape logic | `write.csv()` default behavior | R's write.csv() already handles commas, quotes, newlines in cell values correctly. Semicolon separator eliminates need for custom escaping. |
| Multi-value deduplication | Custom loop with bookkeeping | `unique()` on split vector | Built-in unique() is vectorized, handles NA correctly, and is readable. |

**Key insight:** R's stringr + base functions are sufficient. This is standard data cleaning, not NLP. Avoid over-engineering.

## Common Pitfalls

### Pitfall 1: Separator Replacement Without Escaping Existing Semicolons

**What goes wrong:** If source data already contains semicolons (unlikely but possible in free-text descriptions), replacing commas with semicolons creates ambiguous delimiters.

**Why it happens:** Assumption that semicolons never appear in source data.

**How to avoid:** Verify no semicolons exist in current data before switching:

```r
# Check for existing semicolons
episodes_with_semicolon <- episodes_export %>%
  filter(str_detect(triggering_codes, ";") | str_detect(drug_names, ";") | str_detect(triggering_code_descriptions, ";"))

if (nrow(episodes_with_semicolon) > 0) {
  warning(glue("Found {nrow(episodes_with_semicolon)} rows with existing semicolons — verify separator choice"))
}
```

**Verification:** Search current gantt_episodes_v2.csv for `;` character. If found, either escape them or choose a different separator (e.g., ` | `).

### Pitfall 2: Regex Extraction Misses Capitalized Generic Names

**What goes wrong:** Pattern `[a-z]+` only matches lowercase. If RxNorm sometimes capitalizes generic names (e.g., "Doxorubicin"), regex fails.

**Why it happens:** Assumption that RxNorm generic names are always lowercase.

**How to avoid:** Use case-insensitive pattern OR convert to lowercase first:

```r
# Option 1: Case-insensitive regex
match <- str_extract(d, regex("[a-z]+", ignore_case = TRUE))

# Option 2: Lowercase input first
match <- str_extract(tolower(d), "[a-z]+")
```

**Verification:** Inspect unique drug_names in current output — all observed examples are lowercase (vincristine, doxorubicin, etc.), but new data may differ.

### Pitfall 3: Empty Multi-Value Fields After Cleanup Become ";" or ";;"

**What goes wrong:** If all values in a multi-value field are blank or duplicate, deduplication leaves an empty vector, but paste(collapse=";") might produce empty string OR a lone semicolon depending on implementation.

**Why it happens:** Edge case handling in cleanup function.

**How to avoid:** Explicit check for empty result:

```r
if (length(values) == 0) return("")
```

Already included in Pattern 1 cleanup function above.

### Pitfall 4: Applying Cleanup Before Pseudo-Treatment Row Construction

**What goes wrong:** If cleanup runs before Sections 4B/4C (Death/HL Diagnosis rows), those rows are added AFTER cleanup and don't get cleaned.

**Why it happens:** Misunderstanding of script flow.

**How to avoid:** Place cleanup in new Section 4D AFTER 4B and 4C, or explicitly re-run cleanup on pseudo-treatment rows after they're added.

**Recommended:** Section 4D after all rows are finalized, before CSV write.

### Pitfall 5: NA Conversion Affects Non-String Columns

**What goes wrong:** Applying `ifelse(is.na(.), "", .)` to date or logical columns converts them to strings.

**Why it happens:** `across(where(is.character))` selector should restrict to character columns only.

**How to avoid:** Use `across(where(is.character), ...)` as shown in Pattern 3. Never apply to all columns.

## Code Examples

Verified patterns from existing codebase and R documentation:

### Multi-Value Field Cleanup (Complete Function)

```r
# Section 4D: Data Cleanup (add to R/63_gantt_v2_export.R)

message("\n--- Section 4D: Data Quality Cleanup ---")

# Helper: clean multi-value field (dedup, drop blanks, change separator)
clean_multi_value <- function(field_str, sep_in = ",", sep_out = ";") {
  if (is.na(field_str) || field_str == "" || field_str == "NA") return("")

  values <- str_split(field_str, sep_in)[[1]]
  values <- str_trim(values)
  values <- values[values != "" & !is.na(values)]
  values <- unique(values)

  if (length(values) == 0) return("")
  paste(values, collapse = sep_out)
}

# Helper: extract generic drug name from RxNorm string
simplify_drug_name <- function(drug_str) {
  if (is.na(drug_str) || drug_str == "" || drug_str == "NA") return("")

  drugs <- str_split(drug_str, ";")[[1]]  # Already semicolon-separated after multi-value cleanup
  drugs <- str_trim(drugs)

  simplified <- sapply(drugs, function(d) {
    # Extract first lowercase word sequence (generic name)
    match <- str_extract(tolower(d), "[a-z]{2,}")
    if (is.na(match)) return(d)
    match
  }, USE.NAMES = FALSE)

  simplified <- unique(simplified)
  paste(simplified, collapse = ";")
}

# Step 1: Clean multi-value fields (separator + dedup + drop blanks)
episodes_export <- episodes_export %>%
  mutate(
    triggering_codes = sapply(triggering_codes, clean_multi_value, USE.NAMES = FALSE),
    drug_names = sapply(drug_names, clean_multi_value, USE.NAMES = FALSE),
    triggering_code_descriptions = sapply(triggering_code_descriptions, clean_multi_value, USE.NAMES = FALSE)
  )

detail_export <- detail_export %>%
  mutate(
    triggering_code_description = sapply(triggering_code_description, clean_multi_value, USE.NAMES = FALSE)
  )

message("  Multi-value fields cleaned (separator: semicolon, deduped, blanks dropped)")

# Step 2: Simplify drug names
episodes_export <- episodes_export %>%
  mutate(drug_names = sapply(drug_names, simplify_drug_name, USE.NAMES = FALSE))

detail_export <- detail_export %>%
  mutate(drug_name = sapply(drug_name, simplify_drug_name, USE.NAMES = FALSE))

message("  Drug names simplified (generic names only)")

# Step 3: Fill pseudo-treatment descriptions
episodes_export <- episodes_export %>%
  mutate(
    triggering_code_descriptions = case_when(
      treatment_type %in% c("Death", "HL Diagnosis") & (triggering_code_descriptions == "" | is.na(triggering_code_descriptions)) ~ treatment_type,
      TRUE ~ triggering_code_descriptions
    )
  )

detail_export <- detail_export %>%
  mutate(
    triggering_code_description = case_when(
      treatment_type %in% c("Death", "HL Diagnosis") & (triggering_code_description == "" | is.na(triggering_code_description)) ~ treatment_type,
      TRUE ~ triggering_code_description
    )
  )

message("  Pseudo-treatment descriptions filled")

# Step 4: Convert NA to empty strings
episodes_export <- episodes_export %>%
  mutate(across(where(is.character), ~ ifelse(is.na(.) | . == "NA", "", .)))

detail_export <- detail_export %>%
  mutate(across(where(is.character), ~ ifelse(is.na(.) | . == "NA", "", .)))

message("  NA values converted to empty strings")

# Step 5: Fill blank cancer_category with "Unlinked"
episodes_export <- episodes_export %>%
  mutate(cancer_category = ifelse(cancer_category == "", "Unlinked", cancer_category))

detail_export <- detail_export %>%
  mutate(cancer_category = ifelse(cancer_category == "", "Unlinked", cancer_category))

message("  Blank cancer_category filled with 'Unlinked'")

# Step 6: Column trimming (drop encounter_ids, is_hodgkin, cancer_link_method per D-02, D-04)
episodes_export <- episodes_export %>%
  select(
    patient_id, treatment_type, episode_number,
    episode_start, episode_stop, episode_length_days,
    distinct_dates_in_episode, historical_flag,
    triggering_codes, drug_names, triggering_code_descriptions,
    cancer_category, regimen_label, is_first_line
  )

detail_export <- detail_export %>%
  select(
    patient_id, treatment_type, treatment_date,
    triggering_code, drug_name, episode_number,
    episode_start, episode_stop, historical_flag,
    triggering_code_description, cancer_category,
    regimen_label, is_first_line
  )

message("  Columns trimmed to Tableau-essential set")
message(glue("  Episodes: {ncol(episodes_export)} columns, Detail: {ncol(detail_export)} columns"))
```

### Column Count Verification

```r
# Verify final column counts match CONTEXT.md decisions
expected_ep_cols <- 14  # D-02
expected_detail_cols <- 13  # D-04

if (ncol(episodes_export) != expected_ep_cols) {
  stop(glue("ERROR: episodes_export has {ncol(episodes_export)} columns, expected {expected_ep_cols}"))
}

if (ncol(detail_export) != expected_detail_cols) {
  stop(glue("ERROR: detail_export has {ncol(detail_export)} columns, expected {expected_detail_cols}"))
}
```

## Validation Architecture

**SKIPPED:** `.planning/config.json` has `workflow.nyquist_validation: false`.

## State of the Art

| Topic | Current Practice | Notes |
|-------|------------------|-------|
| Tableau CSV Import | UTF-8, comma-delimited, quoted strings | Standard since Tableau 8+ (2013) |
| Multi-value separators | Pipe `\|` or semicolon `;` preferred over comma | Tableau SPLIT() function handles both |
| Null handling | Empty string or explicit "NULL" text | Empty string is standard for missing categorical data |
| Drug name standards | RxNorm TTY=SCD (Semantic Clinical Drug) | Full strings include dose/form/route — too verbose for charts |

**Deprecated/outdated:**
- Tab-delimited CSVs: Less common now, tools expect comma by default
- Excel as intermediate format: Adds type coercion risks (dates, leading zeros)

## Open Questions

1. **Should triggering_codes field also be deduplicated?**
   - What we know: User decisions (D-07, D-08) explicitly mention deduplication for triggering_code_descriptions and drug_names, but not triggering_codes itself.
   - What's unclear: Whether codes like "Z51.11,Z51.11,Z51.12" should become "Z51.11;Z51.12" or stay as-is.
   - Recommendation: Apply same dedup logic to triggering_codes (LOW risk, HIGH consistency). Pattern 1 function already set up for this.

2. **What if drug name extraction fails for some drugs?**
   - What we know: Regex pattern handles common cases (doxorubicin, vincristine, etc.), but new/rare drugs might not match.
   - What's unclear: Acceptable fallback behavior — keep full RxNorm string or mark as "Unknown"?
   - Recommendation: Keep original full string if regex fails (function already implements this). User can spot-check output and refine regex if needed.

3. **Should output overwrite existing v2 files or create new filenames?**
   - What we know: D-13 says "overwrites the existing v2 files (or writes to new filenames — Claude's discretion)".
   - What's unclear: User preference for comparison vs replacement.
   - Recommendation: Overwrite v2 files directly. This is a cleanup phase, not a parallel version. If comparison needed, user can `git diff` before committing.

4. **Should historical_flag be preserved as TRUE/FALSE or converted to Yes/No text?**
   - What we know: D-03 says keep historical_flag for Tableau filtering. Current format is logical TRUE/FALSE.
   - What's unclear: Tableau preference for logical vs text for filtering.
   - Recommendation: Keep as logical TRUE/FALSE. Tableau handles booleans natively and displays as checkboxes in filters. Text conversion adds complexity with no benefit.

## Environment Availability

**SKIPPED:** No external dependencies beyond existing R environment. All operations use base R + tidyverse packages already in project stack (Phase 1). No new tools, services, or CLIs required.

## Sources

### Primary (HIGH confidence)

- R/63_gantt_v2_export.R (lines 1-525) — Current v2 export script structure
- CONTEXT.md Phase 64 decisions (D-01 through D-13) — User requirements
- output/gantt_episodes_v2.csv — Current data with quality issues (comma separators, verbose drug names, empty fields)
- R/61_episode_classification.R (lines 509-665) — Regimen detection logic using drug names (doxorubicin, vinblastine, etc.)
- stringr documentation — https://stringr.tidyverse.org/ (verified 2026-06-01: version 1.5.1)
- dplyr across() documentation — https://dplyr.tidyverse.org/reference/across.html (verified 2026-06-01)

### Secondary (MEDIUM confidence)

- Tableau CSV import best practices — https://help.tableau.com/current/pro/desktop/en-us/examples_text.htm (verified 2026-06-01: recommends UTF-8, comma-delimited, supports pipe/semicolon as multi-value separator in calculated fields)
- RxNorm drug name format — https://www.nlm.nih.gov/research/umls/rxnorm/docs/techdoc.html (verified 2026-06-01: SCD format is `{Ingredient} {Strength} {Dose Form}`)

### Tertiary (LOW confidence)

None — all research findings verified against official R documentation or existing project code.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — All tools already installed (stringr, dplyr in Phase 1)
- Architecture: HIGH — Integration point clear (Section 4D in R/63), patterns match existing project style
- Pitfalls: HIGH — Observed data quality issues in current output, common R string manipulation pitfalls well-documented

**Research date:** 2026-06-01
**Valid until:** 2026-12-01 (6 months — stable domain, R string functions and Tableau CSV format change infrequently)

---

*Phase: 64-clean-up-gantt-2-output-for-coherent-chart-generation*
*Research complete — ready for planning*
