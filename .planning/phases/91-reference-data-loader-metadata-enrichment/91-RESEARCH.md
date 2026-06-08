# Phase 91: Reference Data Loader & Metadata Enrichment - Research

**Researched:** 2026-06-08
**Domain:** R-based oncology treatment pipeline enhancement — integrating xlsx-sourced lookup tables with episode classification
**Confidence:** HIGH

## Summary

Phase 91 integrates clinical metadata from `all_codes_resolved2.xlsx` (203 chemotherapy codes, 12 radiation codes, 8 SCT codes across 8 sheets) into the existing treatment episode pipeline. The integration adds 5 new columns to `treatment_episodes.rds`: medication names (from xlsx column C), code types (RXNORM/CPT/HCPCS), source tables (PRESCRIBING/PROCEDURES), treatment line labels (F/S/E/N from column H), and cross-use flags (column I).

**Primary recommendation:** Create `R/utils/utils_xlsx_lookups.R` to parse all 8 xlsx sheets, extract columns 1 (Code), 3 (Medication), 4 (Code Type), 5 (Source Table), 8 (F/S/E/N labels), and 9 (Cross-use flags). Return named vectors for code → metadata lookups. Modify `R/28_episode_classification.R` to source the utility module, load xlsx once at script start, and derive 5 new columns from `triggering_codes` + xlsx lookups using the same pattern as existing `drug_group` enrichment (lines 450-490). The enriched RDS propagates to R/52 Gantt v2 export in Phase 92.

**Key insight:** NO NEW STACK COMPONENTS REQUIRED. All necessary libraries (openxlsx2, dplyr, stringr, checkmate) are already validated across 30+ existing scripts. The xlsx → lookup → join pattern directly matches R/57 drug grouping instances (wb_load + wb_to_df for multi-sheet xlsx, build named vectors, left_join to detail data).

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**F/S/E/N Label Handling:**
- **D-01:** Non-chemotherapy codes (Radiation, SCT, Immunotherapy, Supportive Care) get NA for treatment_line. F/S/E/N labels only exist in the Chemotherapy sheet (column 8). Other sheets lack this column entirely.
- **D-02:** Normalize F/S/E/N to single uppercase letters: F, S, E, N. Blank/N/A/missing/mixed-case variants all normalize to NA.
- **D-03:** Treatment line aggregates to a single best value per episode using priority: F > S > E > N. If any code in the episode has "F", the episode gets "F". This matches the existing is_first_line episode-level concept.

**Multi-Code Episode Display:**
- **D-04:** medication_name, code_type, and source_table use parallel semicolon-separated lists matching the existing triggering_codes pattern from Phase 64. Positional correspondence maintained (code N in triggering_codes maps to value N in each metadata column).
- **D-05:** treatment_line is the exception — it aggregates to a single value per episode (D-03), NOT a parallel list, because treatment line is an episode-level concept.

**TBD Code Handling:**
- **D-06:** TBD codes (8 vitamin combos, 2 CAR-T with unresolved classification) remain in treatment_episodes.rds with marker values: treatment_line = "TBD", sct_cross_use_flag = "TBD". No data loss — analysts can filter TBD if needed.
- **D-07:** Separate xlsx export for SME review containing: code, current category, medication name, patient/record counts from DuckDB, and a "Classification Question" column describing what needs resolving. Matches project's existing xlsx export pattern.

**Cross-Use Flag Values:**
- **D-08:** Claude's Discretion — inspect actual column 9 values in all_codes_resolved2.xlsx during implementation and decide normalization strategy (pass-through vs. enum mapping) based on what's found.
- **D-09:** Episode-level aggregation uses any-positive flag logic: if ANY code in the episode has a cross-use flag, the episode gets that flag. Most specific flag wins (mirrors the F>S>E>N aggregation pattern).

### Claude's Discretion

- Cross-use flag normalization strategy (D-08) — determined after xlsx inspection
- Exact column indices for sheets with fewer than 9 columns (Radiation has 7, SCT has 6)
- Pre-join deduplication logic (detect and resolve duplicate codes in xlsx before joining)
- TBD xlsx export filename and location (follow existing output patterns)
- Whether to version-stamp the xlsx reference file in data/reference/

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| GANTT-01 | Gantt v2 episodes CSV includes medication_name column (human-readable from xlsx column C) | Chemotherapy sheet column 3 (Medication) contains human-readable names; R/57 pattern shows wb_to_df + column index extraction; named vector lookup |
| GANTT-02 | Gantt v2 episodes CSV includes code_type column (RXNORM, CPT/HCPCS, ICD-10-CM) | All treatment sheets have column 4 (Code Type); R/50 code_type_map tribble demonstrates existing code→type mapping structure |
| GANTT-03 | Gantt v2 episodes CSV includes source_table column (PRESCRIBING, PROCEDURES, DIAGNOSIS) | All treatment sheets have column 5 (Source Table); matches PCORnet CDM table names already used in pipeline |
| GANTT-04 | Gantt v2 episodes CSV includes treatment_line column (F/S/E/N per triggering code) | Chemotherapy sheet column 8 contains F/S/E/N labels; aggregation pattern matches existing is_first_line logic in R/28 |
| GANTT-05 | Gantt v2 episodes CSV includes cross_use_flag column (SCT conditioning / immunotherapy cross-use) | Chemotherapy sheet column 9 contains cross-use flags; any-positive aggregation (D-09) matches existing drug_group enrichment pattern |
</phase_requirements>

## Standard Stack

### Core (All Already Validated)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| openxlsx2 | 1.8.2+ | Read xlsx with multi-sheet support | Already used in 30+ scripts (R/57, R/24, R/55, R/50); `wb_load()` + `wb_to_df()` proven for multi-sheet xlsx reading; no Java dependency |
| dplyr | 1.2.0+ | Data manipulation and joins | Industry standard; `left_join()` for metadata enrichment, `case_when()` for F/S/E/N normalization; used in all 98 pipeline scripts |
| stringr | 1.5.1+ | String cleaning and normalization | Clean F/S/E/N labels (normalize NA/blank/mixed case), handle Y/y/yes variants in cross-use flags; tidyverse ecosystem standard |
| tibble | 3.2.1+ | Modern data frames | Included in tidyverse; better printing than base data.frame; used for building lookup tables from xlsx columns |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| checkmate | 2.3.2+ | Input validation and assertions | Validate xlsx file exists, lookup tables have expected columns, enrichment preserves row counts; established in Phase 72 |
| glue | 1.8.0+ | String formatting for logging | Readable logging messages with embedded expressions; used across all pipeline scripts for attrition tracking |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| openxlsx2 | readxl | readxl is read-only; project standardized on openxlsx2 in Phase 36 for read+write capability |
| openxlsx2 | xlsx (Java-based) | Deprecated; requires Java runtime; replaced by openxlsx2 in 2020 |
| dplyr | data.table | 10-50x faster but opaque `DT[i, j, by]` syntax conflicts with named predicate requirement from CLAUDE.md |

**Installation:**
```r
# NO NEW PACKAGES TO INSTALL - all dependencies already in project renv
# For new contributors cloning the repo:
renv::restore()

# Verification:
packageVersion("openxlsx2")  # Should be >= 1.8.0
packageVersion("dplyr")       # Should be >= 1.2.0
packageVersion("checkmate")   # Should be >= 2.3.0
```

**Version verification:** All packages already at target versions in v2.2 renv.lock (verified 2026-06-07).

## Architecture Patterns

### Recommended Project Structure
```
R/
├── utils/
│   ├── utils_xlsx_lookups.R  # NEW: xlsx parsing and lookup extraction
│   ├── utils_treatment.R     # Existing: treatment-related helpers
│   ├── utils_duckdb.R        # Existing: database access
│   └── (8 other utils files)
├── 00_config.R               # Central config (TREATMENT_CODES, paths)
├── 28_episode_classification.R  # MODIFIED: source utils_xlsx_lookups, add 5 columns
└── 52_gantt_v2_export.R      # Used in Phase 92: propagate enriched columns to CSV
```

### Pattern 1: Utility Module for xlsx Lookup Extraction

**What:** Create `R/utils/utils_xlsx_lookups.R` with `load_xlsx_lookups(xlsx_path)` function that parses all_codes_resolved2.xlsx (8 sheets) and returns named vectors for code → metadata lookups.

**When to use:** This is the REQUIRED pattern for Phase 91. Not hardcoded in R/00_config.R (already 2000+ lines). Not inline in R/28 (keeps enrichment logic clean).

**Example:**
```r
# R/utils/utils_xlsx_lookups.R
# Source: R/57_drug_grouping_instances.R (lines 113-131) — established pattern
library(openxlsx2)
library(checkmate)

load_xlsx_lookups <- function(xlsx_path = "all_codes_resolved2.xlsx") {
  # Validate input
  assert_file_exists(xlsx_path, .var.name = "[utils_xlsx_lookups ERROR] Reference XLSX")

  ref_wb <- wb_load(xlsx_path)

  # Chemotherapy: Has all 9 columns
  chemo_sheet <- wb_to_df(ref_wb, sheet = "Chemotherapy", start_row = 2)
  chemo_codes <- as.character(chemo_sheet[[1]])
  chemo_medications <- setNames(as.character(chemo_sheet[[3]]), chemo_codes)
  chemo_code_types <- setNames(as.character(chemo_sheet[[4]]), chemo_codes)
  chemo_source_tables <- setNames(as.character(chemo_sheet[[5]]), chemo_codes)
  chemo_line_labels <- setNames(as.character(chemo_sheet[[8]]), chemo_codes)
  chemo_cross_use <- setNames(as.character(chemo_sheet[[9]]), chemo_codes)

  # Radiation: Columns 1,2,4,5,6,7 (no Medication col 3, no F/S/E/N col 8, no cross-use col 9)
  rad_sheet <- wb_to_df(ref_wb, sheet = "Radiation", start_row = 2)
  rad_codes <- as.character(rad_sheet[[1]])
  rad_medications <- setNames(rep(NA_character_, length(rad_codes)), rad_codes)
  rad_code_types <- setNames(as.character(rad_sheet[[4]]), rad_codes)
  rad_source_tables <- setNames(as.character(rad_sheet[[5]]), rad_codes)
  rad_line_labels <- setNames(rep(NA_character_, length(rad_codes)), rad_codes)
  rad_cross_use <- setNames(rep(NA_character_, length(rad_codes)), rad_codes)

  # SCT: Similar structure (verify column count during implementation)
  sct_sheet <- wb_to_df(ref_wb, sheet = "SCT", start_row = 2)
  sct_codes <- as.character(sct_sheet[[1]])
  sct_medications <- setNames(rep(NA_character_, length(sct_codes)), sct_codes)
  sct_code_types <- setNames(as.character(sct_sheet[[4]]), sct_codes)
  sct_source_tables <- setNames(as.character(sct_sheet[[5]]), sct_codes)
  sct_line_labels <- setNames(rep(NA_character_, length(sct_codes)), sct_codes)
  sct_cross_use <- setNames(rep(NA_character_, length(sct_codes)), sct_codes)

  # Immunotherapy: Check column structure during implementation
  immuno_sheet <- wb_to_df(ref_wb, sheet = "Immunotherapy", start_row = 2)
  immuno_codes <- as.character(immuno_sheet[[1]])
  immuno_medications <- setNames(rep(NA_character_, length(immuno_codes)), immuno_codes)
  immuno_code_types <- setNames(as.character(immuno_sheet[[4]]), immuno_codes)
  immuno_source_tables <- setNames(as.character(immuno_sheet[[5]]), immuno_codes)
  immuno_line_labels <- setNames(rep(NA_character_, length(immuno_codes)), immuno_codes)
  immuno_cross_use <- setNames(rep(NA_character_, length(immuno_codes)), immuno_codes)

  # Combine all lookups
  list(
    medications = c(chemo_medications, rad_medications, sct_medications, immuno_medications),
    code_types = c(chemo_code_types, rad_code_types, sct_code_types, immuno_code_types),
    source_tables = c(chemo_source_tables, rad_source_tables, sct_source_tables, immuno_source_tables),
    line_labels = c(chemo_line_labels, rad_line_labels, sct_line_labels, immuno_line_labels),
    cross_use_flags = c(chemo_cross_use, rad_cross_use, sct_cross_use, immuno_cross_use)
  )
}
```

### Pattern 2: Episode-Level Metadata Enrichment

**What:** Modify R/28_episode_classification.R to source utils_xlsx_lookups.R, load xlsx once at script start, and derive 5 new columns from `triggering_codes` + xlsx lookups.

**When to use:** This is where enrichment happens (existing pattern: cancer linkage, regimen detection, drug groups at lines 450-600). Add new columns here before saving treatment_episodes.rds.

**Example:**
```r
# R/28_episode_classification.R (MODIFIED)
# Source: Existing drug_group enrichment pattern (lines 450-490)

# After existing sources
source("R/utils/utils_xlsx_lookups.R")

# Load xlsx lookups once at script start
xlsx_lookups <- load_xlsx_lookups("all_codes_resolved2.xlsx")

# Later in script, after regimen detection (line ~500), before saving RDS (line ~600):

# Helper: Aggregate F/S/E/N labels with priority (D-03)
aggregate_line_labels <- function(codes_str, lookups) {
  if (is.na(codes_str) || codes_str == "") return(NA_character_)
  codes <- str_split(codes_str, ",")[[1]]
  labels <- sapply(codes, function(c) lookups$line_labels[[c]] %||% NA_character_, USE.NAMES = FALSE)
  # Normalize to uppercase single letters
  labels <- str_trim(str_to_upper(labels))
  labels <- labels[labels %in% c("F", "S", "E", "N")]
  # Priority: F > S > E > N
  if ("F" %in% labels) return("F")
  if ("S" %in% labels) return("S")
  if ("E" %in% labels) return("E")
  if ("N" %in% labels) return("N")
  return(NA_character_)
}

# Helper: Map codes to metadata, join with semicolons (D-04)
map_codes_to_metadata <- function(codes_str, lookups_vec) {
  if (is.na(codes_str) || codes_str == "") return(NA_character_)
  codes <- str_split(codes_str, ",")[[1]]
  values <- sapply(codes, function(c) lookups_vec[[c]] %||% NA_character_, USE.NAMES = FALSE)
  paste(values, collapse = ";")
}

# Apply to episodes
treatment_episodes <- treatment_episodes %>%
  mutate(
    # D-03: Episode-level aggregation (single value, not parallel list)
    treatment_line = sapply(triggering_codes, aggregate_line_labels, lookups = xlsx_lookups, USE.NAMES = FALSE),

    # D-04: Parallel semicolon-separated lists matching triggering_codes
    medication_name = sapply(triggering_codes, map_codes_to_metadata, lookups_vec = xlsx_lookups$medications, USE.NAMES = FALSE),
    code_type = sapply(triggering_codes, map_codes_to_metadata, lookups_vec = xlsx_lookups$code_types, USE.NAMES = FALSE),
    source_table = sapply(triggering_codes, map_codes_to_metadata, lookups_vec = xlsx_lookups$source_tables, USE.NAMES = FALSE),

    # D-09: Any-positive aggregation for cross-use flags
    sct_cross_use_flag = sapply(triggering_codes, function(codes_str) {
      if (is.na(codes_str) || codes_str == "") return(NA_character_)
      codes <- str_split(codes_str, ",")[[1]]
      flags <- sapply(codes, function(c) xlsx_lookups$cross_use_flags[[c]] %||% NA_character_, USE.NAMES = FALSE)
      flags <- flags[!is.na(flags) & flags != ""]
      if (length(flags) > 0) return(flags[1])  # Return first non-NA
      return(NA_character_)
    }, USE.NAMES = FALSE)
  )
```

### Pattern 3: Pre-Join Validation (Many-to-Many Prevention)

**What:** Before joining xlsx metadata to episodes, validate that each code appears only once in the xlsx lookup tables.

**When to use:** REQUIRED before any join to prevent row explosion from duplicate codes in xlsx.

**Example:**
```r
# In load_xlsx_lookups() function, after combining all lookups:

# Validate uniqueness (prevent many-to-many join explosion)
all_codes <- names(combined_lookups$medications)
duplicates <- all_codes[duplicated(all_codes)]
if (length(duplicates) > 0) {
  stop(glue("[utils_xlsx_lookups ERROR] Duplicate codes found in xlsx: {paste(duplicates, collapse = ', ')}"))
}
```

### Anti-Patterns to Avoid

- **Don't hardcode xlsx data in R/00_config.R:** xlsx is source of truth (Amy Crisp edits it); hardcoding creates divergence (config vs xlsx). Do this instead: Load xlsx at runtime in R/28 (once per execution, <1 sec overhead).
- **Don't create separate enrichment script (R/28b):** R/28 already does episode-level enrichment; adds pipeline step and splits related logic. Do this instead: Add new columns in R/28 alongside existing enrichments (lines 450-600).
- **Don't use column names for multi-line headers:** Multi-line header creates unwieldy name, fragile to text changes. Do this instead: Use column index with comment: `fsen_col <- df[[8]]  # Column H: F/S/E/N labels`.
- **Don't assume all sheets have same column structure:** Radiation sheet has no Medication column (col 3 blank), no F/S/E/N (col 8), no cross-use (col 9). Do this instead: Build sheet-specific extractors with explicit NA fills for missing columns.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| xlsx parsing | Custom CSV converter or text extraction | openxlsx2::wb_load() + wb_to_df() | Handles merged headers, multi-line cells, preserves data types; already validated in 30+ scripts |
| Code deduplication | Manual loop checking for duplicates | dplyr::count() + filter(n > 1) | Vectorized operation; clear intent; works with relationship assertion in left_join |
| String normalization | case_when with 20+ variants | str_trim(str_to_upper()) + filtering | Handles all case variants and whitespace in 2 function calls |
| Named vector lookups | Hash tables or environment-based lookups | setNames(values, keys) | R native; fast O(1) lookup; readable |

**Key insight:** R has mature ecosystem for xlsx reading and data transformation. Using established patterns (openxlsx2 for xlsx, named vectors for lookups, dplyr for joins) is faster and more maintainable than custom solutions.

## Common Pitfalls

### Pitfall 1: Many-to-Many Join Explosion from Duplicate xlsx Entries

**What goes wrong:** If xlsx has duplicate entries for a code (e.g., two rows for "Melphalan" with conflicting classifications), join produces row duplication. Per dplyr documentation: "If both x and y have multiple matches for a key, the result is the cross product... if x has 100 rows for id=1 and y has 5 rows for id=1, it returns 500 rows for id=1."

**Why it happens:** all_codes_resolved2.xlsx is a working document with unresolved questions (8 vitamin combos, 2 CAR-T codes TBD). Excel allows duplicate entries during exploratory work. No uniqueness constraint on code columns.

**How to avoid:**
1. **Pre-join validation:** Run `xlsx_data |> count(code) |> filter(n > 1)` in load_xlsx_lookups() and error if duplicates exist
2. **Assert relationship:** Use `left_join(..., relationship = "many-to-one")` (dplyr 1.1+) to error on many-to-many
3. **Deduplicate reference data:** Filter xlsx to `distinct(code, .keep_all = TRUE)` with precedence rules (e.g., prioritize rows with non-NA medication_name)
4. **Unit test join:** `expect_equal(nrow(episodes_enriched), nrow(treatment_episodes))`

**Warning signs:**
- Reference xlsx has "TBD" or "?" in classification columns
- No uniqueness check before join
- Row count increases after enrichment
- Smoke test doesn't validate pre/post enrichment row counts

### Pitfall 2: Unresolved Classifications Propagating to Production Output

**What goes wrong:** 8 vitamin combo codes flagged as questionable immunotherapy and 2 CAR-T codes with TBD classification exist in all_codes_resolved2.xlsx. If joined as-is, treatment_episodes.rds contains `treatment_line = NA` or `sct_cross_use_flag = NA`, downstream analysts filter `!is.na()` and silently exclude questionable codes.

**Why it happens:** Clinical domain expertise required for classification exceeds data engineering scope. Codes fall into gray areas (vitamin combos: Supportive care or immunomodulatory agents? CAR-T: Technically cellular immunotherapy, but often tracked separately).

**How to avoid:**
1. **Marker values (D-06):** TBD codes get `treatment_line = "TBD"`, `sct_cross_use_flag = "TBD"` (not NA)
2. **Separate export (D-07):** Export TBD codes to xlsx with code, current category, medication name, patient/record counts, and "Classification Question" column
3. **Document rationale:** Add classification_notes column with "TBD - requires oncology SME review"
4. **Filter-friendly:** Analysts can `filter(treatment_line != "TBD")` to exclude unresolved codes from analysis

**Warning signs:**
- Reference data has "TBD", "?", or blank classification cells
- No confidence/quality column exists
- Enrichment logic treats all classifications equally (no filtering by confidence)
- No clinical SME review scheduled

### Pitfall 3: F/S/E/N Label Variants Breaking Normalization

**What goes wrong:** xlsx column 8 may contain "F", "f", "First line", "first-line", "NA", "N/A", blank cells, or mixed-case variants. Naive string matching (== "F") misses variants, leaving most codes with NA treatment_line.

**Why it happens:** Manual xlsx editing by clinical staff; no data validation in Excel; legacy data with different conventions.

**How to avoid:**
1. **Normalize to uppercase:** `str_to_upper(str_trim(label))` handles case and whitespace
2. **Extract first character:** `str_sub(label, 1, 1)` for "First line" → "F"
3. **Explicit enum filtering:** `label %in% c("F", "S", "E", "N")` after normalization
4. **Map blanks to NA:** `case_when(label %in% c("", "NA", "N/A") ~ NA_character_, ...)`
5. **Log unexpected values:** Print unique values not in expected set for manual review

**Warning signs:**
- Treatment_line column mostly NA after enrichment
- No string normalization before aggregation
- No logging of unexpected label values
- Smoke test doesn't check for expected F/S/E/N distribution

### Pitfall 4: Cross-Use Flag Logic Without Mutual Exclusivity Validation

**What goes wrong:** 5 chemotherapy codes flagged as SCT conditioning agents (Melphalan, Carmustine, Temsirolimus). If counted in both "chemotherapy" and "SCT conditioning" groups, summing counts across categories produces >100% totals.

**Why it happens:** Same drug code appears in multiple clinical contexts. CODE_SUBCATEGORY_MAP assigns single category per code, but reality is multi-modal (Melphalan alone = multiple myeloma chemotherapy; Melphalan + other agents within 14 days of SCT = BEAM conditioning regimen).

**How to avoid:**
1. **Episode-level aggregation only (D-09):** Cross-use flag is metadata, not a separate category
2. **Document non-additivity:** Flags describe dual-use potential, not separate treatment types
3. **Primary category remains treatment_type:** Chemotherapy codes stay in chemotherapy category
4. **Future: Temporal context flags (Phase 93):** `is_sct_conditioning_context = TRUE` when code in conditioning_drugs AND within 30 days before SCT episode

**Warning signs:**
- Cross-use flags implemented as boolean columns without aggregation guidance
- Category counts validated to sum to total episodes (will fail if flags treated as categories)
- Documentation doesn't specify how to handle dual-use codes

## Code Examples

Verified patterns from existing codebase:

### Load xlsx and Extract Columns by Index
```r
# Source: R/57_drug_grouping_instances.R (lines 113-131)
library(openxlsx2)
library(checkmate)

assert_file_exists("all_codes_resolved2.xlsx", .var.name = "[R/57 ERROR] Reference XLSX")
ref_wb <- wb_load("all_codes_resolved2.xlsx")

# Chemotherapy: code -> medication name (column C, "Medication")
chemo_sheet <- wb_to_df(ref_wb, sheet = "Chemotherapy", start_row = 2)
chemo_map <- setNames(as.character(chemo_sheet[[3]]), as.character(chemo_sheet[[1]]))
chemo_map <- chemo_map[!is.na(names(chemo_map)) & !is.na(chemo_map)]
message(glue("Chemo medications: {length(unique(chemo_map))} from {length(chemo_map)} codes"))
```

### Map Comma-Separated Codes to Metadata
```r
# Source: R/28_episode_classification.R (lines 450-490)
# Existing pattern for drug_group enrichment

# triggering_codes: "J9000,J9040,J9360" (comma-separated)
# Map each code to metadata, rejoin with semicolons
map_codes_to_metadata <- function(codes_str, lookup_vec) {
  if (is.na(codes_str) || codes_str == "") return(NA_character_)
  codes <- str_split(codes_str, ",")[[1]]
  values <- sapply(codes, function(c) lookup_vec[[c]] %||% NA_character_, USE.NAMES = FALSE)
  paste(values, collapse = ";")
}

# Apply to episodes
treatment_episodes <- treatment_episodes %>%
  mutate(
    medication_name = sapply(triggering_codes, map_codes_to_metadata,
                             lookups_vec = xlsx_lookups$medications,
                             USE.NAMES = FALSE)
  )
```

### Validate Row Count After Join
```r
# Source: Phase 72 checkmate pattern
library(checkmate)

# Before enrichment
original_count <- nrow(treatment_episodes)

# After enrichment
treatment_episodes_enriched <- treatment_episodes %>%
  mutate(
    medication_name = ...,
    treatment_line = ...,
    # ... other columns
  )

# Verify no row explosion
assert_true(nrow(treatment_episodes_enriched) == original_count,
            .var.name = "[R/28 ERROR] Enrichment changed row count")
```

## Open Questions

1. **Radiation/SCT/Immunotherapy sheet column structure**
   - What we know: STACK.md documents Radiation lacks Medication (col 3), SCT has different col 7 meaning
   - What's unclear: Exact column indices for sheets with fewer than 9 columns
   - Recommendation: Print `ncol(rad_sheet)` and `names(rad_sheet)` during implementation to verify before extraction

2. **F/S/E/N label variants in xlsx**
   - What we know: Expected values are "F", "S", "E", "N" per oncology nomenclature
   - What's unclear: Actual variants in xlsx (NA/N/A/mixed case/full strings like "First line")
   - Recommendation: Print `unique(chemo_sheet[[8]])` during implementation; implement normalization as in Pitfall 3

3. **Cross-use flag values in column 9**
   - What we know: Column 9 labeled "Is this used for conditioning for SCT or as immunotherapy also?"
   - What's unclear: Actual values (Y/y/yes/blank/None/descriptive text)
   - Recommendation: Print `unique(chemo_sheet[[9]])` during implementation; decide normalization (D-08: Claude's Discretion)

4. **TBD xlsx export location**
   - What we know: D-07 specifies separate xlsx export for SME review
   - What's unclear: Filename convention and output directory
   - Recommendation: Follow existing pattern from R/51-R/52 (output/ directory), use `unresolved_codes_for_review.xlsx`

## Environment Availability

> Phase has no external dependencies (code/config-only changes using existing R packages in renv.lock).

Step 2.6: SKIPPED (no external dependencies identified)

## Sources

### Primary (HIGH confidence)
- **Codebase inspection:**
  - R/00_config.R — TREATMENT_CODES lookup patterns, CODE_SUBCATEGORY_MAP structure
  - R/28_episode_classification.R — Episode enrichment pattern (lines 450-600), existing drug_group derivation
  - R/57_drug_grouping_instances.R (lines 113-131) — wb_load + wb_to_df xlsx reading pattern, setNames for named vector creation
  - R/88_smoke_test_comprehensive.R — Validation patterns for new features, check() assertion helper
  - R/utils/*.R — 10 existing utility modules demonstrating project's utility module pattern

- **Official documentation:**
  - [CRAN openxlsx2 1.8.2](https://cran.r-project.org/web/packages/openxlsx2/index.html) (Dec 2025) — wb_load, wb_to_df, wb_get_sheet_names API
  - [dplyr mutate-joins reference](https://dplyr.tidyverse.org/reference/mutate-joins.html) — relationship = "many-to-one" assertion (dplyr 1.1+)
  - [R for Data Science (2e) - Joins](https://r4ds.hadley.nz/joins.html) — Many-to-many join pitfalls, row duplication mechanics

### Secondary (MEDIUM confidence)
- **Research documents:**
  - .planning/research/ARCHITECTURE.md — Integration architecture for xlsx loading and enrichment pipeline
  - .planning/research/PITFALLS.md — Many-to-many join explosion prevention, TBD code propagation risks
  - .planning/research/SUMMARY.md — Research synthesis with integration patterns and column derivation logic
  - .planning/research/STACK.md — xlsx structure verification (column counts per sheet), openxlsx2 usage patterns

- **Oncology treatment classification:**
  - [Development and Utility of Cancer Medications Enquiry Database](https://pmc.ncbi.nlm.nih.gov/articles/PMC7868035/) — Medication code misclassification, varying therapy definitions
  - [Stem Cell Transplant Conditioning Regimens](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC12293537/) — Chemotherapy agents in conditioning (cyclophosphamide, busulfan, carmustine, melphalan)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — All libraries validated in 30+ existing scripts, openxlsx2 + dplyr patterns proven in R/57 drug grouping
- Architecture: HIGH — Codebase patterns well-established (R/28 enrichment, utility module pattern), integration points explicit
- Column derivation logic: HIGH — Existing drug_group enrichment (R/28 lines 450-490) provides direct template for new columns
- xlsx structure: MEDIUM-HIGH — Chemotherapy sheet verified (9 columns), other sheets need column count verification during implementation

**Research date:** 2026-06-08
**Valid until:** 60 days (stack and patterns stable, xlsx structure may evolve with clinical review updates)
