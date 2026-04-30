# Phase 36: All-Encounter Payer Frequency & Same-Day Categorization (AMC 8-Category) - Research

**Researched:** 2026-04-30
**Domain:** R code refactoring, AMC payer mapping migration, centralized configuration
**Confidence:** HIGH

## Summary

Phase 36 refactors R/36_tiered_same_day_payer.R to eliminate PayerVariable.xlsx dependency and use the centralized AMC 8-category payer mapping from R/00_config.R. This is a code modernization task that removes duplication and consolidates all payer mapping logic to a single source of truth.

The technical challenge is straightforward: replace `left_join(payer_lookup, by = "code")` operations (which use a 3-column xlsx dataframe) with direct `AMC_PAYER_LOOKUP` vector lookups (which use a named character vector). The frequency table output structure changes from `code | description | category | n | pct` to `code | amc_category | n | pct` because AMC_PAYER_LOOKUP contains no descriptions. The same-day resolution logic already uses AMC categories internally (via `CODE_TO_TIER()`) and requires minimal changes.

**Primary recommendation:** Remove Section 1 (PayerVariable.xlsx loading) entirely, remove the three local payer mapping functions (already duplicates of R/02 logic), replace `left_join` with `AMC_PAYER_LOOKUP[code]` lookups in frequency table generation, and update output column names. The 12 CSV outputs remain the same (filenames unchanged), but content is updated with AMC categories.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Script Strategy**
- **D-01:** Update R/36_tiered_same_day_payer.R in-place. No new script file. R/36 already has dual-scope coverage (all encounters + AV+TH) with frequency tables and same-day resolution.
- **D-02:** R/35_payer_code_frequency_av_th.R (Phase 34) remains as a historical baseline using PayerVariable.xlsx. It is NOT modified by this phase.

**AMC Category Mapping**
- **D-03:** Use AMC_PAYER_LOOKUP from R/00_config.R as the sole category mapping source. Remove PayerVariable.xlsx loading (readxl dependency no longer needed in R/36).
- **D-04:** Keep prefix-based fallback from PAYER_MAPPING$prefix_fallback in config.R for codes not found in AMC_PAYER_LOOKUP. Every code gets a category.
- **D-05:** Frequency table output columns: code, amc_category, n, pct. No description column (AMC_PAYER_LOOKUP has no descriptions). Category summary aggregates by the 8 AMC categories: Medicaid, Medicare, Private, Other govt, Other, Self-pay, Uninsured, Missing.

**Refactoring**
- **D-06:** Remove local function copies (map_payer_category_local, compute_effective_payer_local, detect_dual_eligible_local). Use centralized logic from config.R — AMC_PAYER_LOOKUP is already loaded via source("R/00_config.R").
- **D-07:** Remove Section 1 (Load PayerVariable.xlsx) entirely. Remove PAYER_XLSX_PATH constant. Remove readxl from library() calls.
- **D-08:** The CODE_TO_TIER function mapping AMC categories to resolution tiers stays — it's specific to the same-day resolution logic and maps from AMC 8 categories to the 7 resolution tiers (Other govt collapses to Other).

**Output Deliverables**
- **D-09:** Same 12 CSV filenames, same structure, content updated with AMC categories instead of PayerVariable.xlsx categories. Existing output files get overwritten on next HiPerGator run.
- **D-10:** Resolution CSVs already use AMC categories (via CODE_TO_TIER) — those need minimal or no changes. Frequency table CSVs are the primary update target.

### Claude's Discretion

- How to handle the left_join-based frequency table logic when switching from PayerVariable.xlsx lookup to AMC_PAYER_LOOKUP vector
- Whether to use map_payer_category() from R/02_harmonize_payer.R or inline AMC_PAYER_LOOKUP lookups
- Console summary format adjustments (if any) for the new column layout
- Whether compute_effective_payer and detect_dual_eligible should be sourced from R/02_harmonize_payer.R or remain inline (simplified)

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.

</user_constraints>

## Project Constraints (from CLAUDE.md)

**Mandatory directives:**
- **Runtime environment**: RStudio on UF HiPerGator — scripts must work in that environment
- **R packages**: tidyverse ecosystem (dplyr, ggplot2, stringr, lubridate), readr for CSV I/O
- **Code style**: Filtering logic uses named predicate functions (`has_*`, `with_*`, `exclude_*`) — no opaque one-liners
- **Payer fidelity**: Must match the AMC 8-category payer mapping exactly (Medicaid, Medicare, Private, Other govt, Other, Self-pay, Uninsured, Missing)
- **Data access**: Raw CSVs on HiPerGator filesystem via DuckDB backend (USE_DUCKDB = TRUE per Phase 32)

**Package removals:**
- Remove `readxl` from library() calls in R/36 (no longer loading xlsx)

**AMC 8-category enforcement:**
- All payer categorization must use AMC_PAYER_LOOKUP from R/00_config.R
- Codes not in AMC_PAYER_LOOKUP fall back to PAYER_MAPPING$prefix_fallback (first-digit prefix mapping)
- No custom mapping logic — centralized configuration only

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| dplyr | 1.2.0+ | Data transformation | Tidyverse core; required for mutate, case_when, left_join replacement with vectorized lookups |
| glue | 1.8.0 | String formatting | Already used for console logging in R/36 |
| readr | 2.2.0+ | CSV I/O | write_csv() for all 12 output files |
| stringr | 1.5.1+ | String operations | str_starts() for prefix fallback logic (already in R/36) |
| lubridate | 1.9.3+ | Date operations | Date parsing for ADMIT_DATE (already in R/36) |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| utils_duckdb.R | N/A | Backend abstraction | get_pcornet_table(), materialize() — already used in R/36 |
| R/02_harmonize_payer.R | N/A | Centralized payer logic (optional sourcing) | If using map_payer_category(), compute_effective_payer(), detect_dual_eligible() — see Claude's discretion |

### Removed Dependencies
| Library | Why Removed |
|---------|-------------|
| readxl | No longer loading PayerVariable.xlsx (D-07) |

**Installation:**
No new packages needed. All dependencies already present in R/36.

**Version verification:**
R/36 uses existing package ecosystem. No version changes needed.

## Architecture Patterns

### Recommended Code Structure (R/36 refactored)

**Section 0: Setup and Tier Configuration**
- Source R/00_config.R (brings in AMC_PAYER_LOOKUP, PAYER_MAPPING)
- Load required libraries (dplyr, glue, readr, stringr, lubridate)
- Remove: readxl, PAYER_XLSX_PATH constant
- Keep: TIER_MAPPING (7 resolution tiers), CODE_TO_TIER function

**Section 1: DELETED**
- Remove entire PayerVariable.xlsx loading section (lines 167-189 in current R/36)

**Section 2: Load ENCOUNTER table and prepare both scopes**
- Keep DuckDB loading logic (get_pcornet_table, materialize)
- Remove local function definitions (compute_effective_payer_local, detect_dual_eligible_local, map_payer_category_local)
- Replace with: Either source R/02_harmonize_payer.R OR use inline AMC_PAYER_LOOKUP lookups

**Section 3: Frequency Tables**
- Replace build_frequency_tables() logic:
  - OLD: `left_join(payer_lookup, by = "code")` where payer_lookup is xlsx dataframe
  - NEW: `mutate(amc_category = AMC_PAYER_LOOKUP[code])` using named vector lookup
- Update column selection: `code, description, category, n, pct` → `code, amc_category, n, pct`
- Remove "NOT IN XLSX" fallback logic
- Add prefix fallback for unmapped codes: if AMC_PAYER_LOOKUP[code] is NA, use first-digit prefix rule

**Section 4: Same-Day Resolution**
- Minimal changes — already uses tier-based logic via CODE_TO_TIER()
- Verify that payer_category field (computed in Section 2) flows through correctly

### Pattern 1: Named Vector Lookup (Recommended for Claude's Discretion)

**What:** Replace dataframe left_join with direct named vector access for category mapping
**When to use:** Frequency table generation (Section 3)
**Example:**
```r
# OLD (PayerVariable.xlsx approach):
primary_freq <- enc_scope %>%
  count(code = PAYER_TYPE_PRIMARY) %>%
  left_join(payer_lookup, by = "code") %>%  # payer_lookup is xlsx dataframe
  mutate(pct = round(100 * n / total_enc, 2)) %>%
  select(code, description, category, n, pct)

# NEW (AMC_PAYER_LOOKUP approach):
primary_freq <- enc_scope %>%
  mutate(
    code = case_when(
      is.na(PAYER_TYPE_PRIMARY) ~ "<NA>",
      PAYER_TYPE_PRIMARY == "" ~ "<EMPTY>",
      TRUE ~ PAYER_TYPE_PRIMARY
    )
  ) %>%
  count(code, name = "n") %>%
  mutate(
    # Direct vector lookup
    amc_category_looked_up = AMC_PAYER_LOOKUP[code],
    # Prefix fallback for unmapped codes
    prefix_first_digit = substr(code, 1, 1),
    prefix_category = case_when(
      prefix_first_digit == "1" ~ "Medicare",
      prefix_first_digit == "2" ~ "Medicaid",
      prefix_first_digit == "5" | prefix_first_digit == "6" ~ "Private",
      prefix_first_digit == "3" | prefix_first_digit == "4" ~ "Other govt",
      prefix_first_digit == "7" ~ "Private",
      prefix_first_digit == "8" ~ "Uninsured",
      prefix_first_digit == "9" ~ "Other",
      TRUE ~ "Other"
    ),
    # Use lookup if found, else prefix fallback, else Missing for <NA>/<EMPTY>
    amc_category = case_when(
      code %in% c("<NA>", "<EMPTY>") ~ "Missing",
      !is.na(amc_category_looked_up) ~ amc_category_looked_up,
      TRUE ~ prefix_category
    ),
    pct = round(100 * n / total_enc, 2)
  ) %>%
  select(code, amc_category, n, pct) %>%
  arrange(desc(n))
```

**Rationale:** Matches the centralized logic in R/02_harmonize_payer.R map_payer_category() (lines 109-129) which uses the same AMC_PAYER_LOOKUP + prefix fallback pattern. Ensures consistency across all scripts.

### Pattern 2: Source R/02 vs Inline Logic (Claude's Discretion)

**Option A: Source R/02_harmonize_payer.R**
```r
# After source("R/00_config.R"):
source("R/02_harmonize_payer.R")  # Brings in map_payer_category(), compute_effective_payer(), detect_dual_eligible()

# Then in Section 2:
enc <- enc_raw %>%
  mutate(
    effective_payer = compute_effective_payer(PAYER_TYPE_PRIMARY, PAYER_TYPE_SECONDARY),
    dual_eligible = detect_dual_eligible(PAYER_TYPE_PRIMARY, PAYER_TYPE_SECONDARY),
    payer_category = map_payer_category(effective_payer),
    tier = CODE_TO_TIER(payer_category),
    # ... rest of tier logic
  )
```

**Option B: Inline AMC_PAYER_LOOKUP (simpler, no function dependency)**
```r
# No source of R/02
# In Section 2:
enc <- enc_raw %>%
  mutate(
    # Inline effective payer logic (6 lines)
    effective_payer = case_when(
      !is.na(PAYER_TYPE_PRIMARY) & nchar(trimws(PAYER_TYPE_PRIMARY)) > 0 &
        !PAYER_TYPE_PRIMARY %in% c("NI", "UN", "OT") ~ PAYER_TYPE_PRIMARY,
      !is.na(PAYER_TYPE_SECONDARY) & nchar(trimws(PAYER_TYPE_SECONDARY)) > 0 &
        !PAYER_TYPE_SECONDARY %in% c("NI", "UN", "OT") ~ PAYER_TYPE_SECONDARY,
      TRUE ~ NA_character_
    ),
    # Direct AMC category lookup + prefix fallback (from Pattern 1)
    amc_category_looked_up = AMC_PAYER_LOOKUP[effective_payer],
    # ... same prefix logic as Pattern 1
  )
```

**Recommendation:** Option A (source R/02) for maintainability. If the centralized logic changes, R/36 automatically inherits the update. Option B creates another copy to maintain (contradicts D-06). However, R/36 currently has local copies (lines 106-164), so removing them requires sourcing R/02 or inlining a simplified version. Planner should decide based on "remove duplication" vs "minimize cross-file dependencies" tradeoff.

### Anti-Patterns to Avoid

**1. Don't keep local function copies**
```r
# AVOID: Keeping compute_effective_payer_local, map_payer_category_local, detect_dual_eligible_local
# These are exact duplicates of R/02 logic (lines 106-164 in current R/36)
# Violates D-06 (remove local function copies)
```

**2. Don't load PayerVariable.xlsx**
```r
# AVOID:
library(readxl)
payer_lookup <- read_excel("PayerVariable.xlsx", sheet = "Sheet2")

# This entire pattern is out of scope per D-03, D-07
```

**3. Don't use left_join for category mapping**
```r
# AVOID:
primary_freq <- ... %>%
  count(code) %>%
  left_join(payer_lookup, by = "code")  # payer_lookup no longer exists

# Use AMC_PAYER_LOOKUP[code] vector lookup instead (Pattern 1)
```

**4. Don't create custom category logic**
```r
# AVOID:
custom_category <- case_when(
  code == "14" ~ "Dual eligible",  # Wrong — AMC maps this to Medicaid
  # ... custom rules
)

# Use AMC_PAYER_LOOKUP + prefix_fallback only (Pattern 1)
```

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Payer code → category mapping | Custom lookup tables, new xlsx files | AMC_PAYER_LOOKUP from R/00_config.R | Centralized source of truth; validated against payer_primary_codes_frequency_AMC.xlsx; maintains consistency with R/02 harmonization |
| Effective payer computation | Inline case_when logic | compute_effective_payer() from R/02_harmonize_payer.R (or inline if simplified) | Primary-if-valid-else-secondary logic with sentinel value handling already tested |
| Dual-eligible detection | String matching on codes | detect_dual_eligible() from R/02_harmonize_payer.R | Handles both explicit codes (14/141/142) and cross-payer Medicare+Medicaid patterns |
| Prefix-based fallback | Custom first-digit rules | PAYER_MAPPING$prefix_fallback from R/00_config.R | Already defined in config; ensures consistency with map_payer_category() |

**Key insight:** All payer mapping logic lives in R/00_config.R (data) and R/02_harmonize_payer.R (functions). R/36 should consume these, not reimplement them. The only script-specific logic in R/36 is CODE_TO_TIER() (AMC 8 categories → 7 resolution tiers for same-day hierarchy) and the resolution algorithm itself.

## Common Pitfalls

### Pitfall 1: Breaking Existing Output Consumers

**What goes wrong:** Changing frequency table column names from `category` to `amc_category` may break downstream consumers (Excel macros, other R scripts, manual workflows that expect specific column names).

**Why it happens:** User decisions specify `code, amc_category, n, pct` (D-05), but existing workflow may expect old column layout.

**How to avoid:** Verify with user that no downstream dependencies exist, OR add a backward-compatibility alias column in the CSV output:
```r
# If backward compatibility needed:
primary_freq <- primary_freq %>%
  mutate(category = amc_category) %>%  # Alias for old consumers
  select(code, amc_category, category, n, pct)  # Both columns present
```

**Warning signs:** User mentions "Excel reports", "automated ingestion", or "PowerBI dashboards" that consume these CSVs.

**Note:** User decisions do NOT mention backward compatibility, so planner should clarify or proceed with breaking change per D-05.

### Pitfall 2: NA Handling in Named Vector Lookups

**What goes wrong:** `AMC_PAYER_LOOKUP[code]` returns `NA` (with name) for unmapped codes, not `NA_character_`. This breaks `is.na()` checks if not handled correctly.

**Why it happens:** Named vector indexing with `[` preserves the name attribute even when the value is NA.

**How to avoid:** Use `unname()` or explicit NA handling:
```r
# SAFE:
amc_category_looked_up = unname(AMC_PAYER_LOOKUP[code])

# Or check with if_else:
amc_category = if_else(!is.na(AMC_PAYER_LOOKUP[code]), AMC_PAYER_LOOKUP[code], prefix_category)
```

**Warning signs:** Console warnings about "NAs introduced by coercion" or unexpected `NA` counts in frequency tables.

### Pitfall 3: Removing readxl Without Checking Other Dependencies

**What goes wrong:** R/36 loads `library(readxl)` (line 56). Removing it is safe IF no other code in R/36 uses read_excel(). But if the script is later extended, the missing library causes a cryptic error.

**Why it happens:** D-07 says "remove readxl", but assumes entire Section 1 is deleted atomically. If a partial refactor happens, readxl removal may be forgotten.

**How to avoid:** Grep the entire R/36 file for `read_excel` or `readxl::` before removing the library() call. Ensure PAYER_XLSX_PATH is also removed (it's a dangling reference).

**Warning signs:** Error on HiPerGator: `could not find function "read_excel"` despite readxl being installed.

### Pitfall 4: Forgetting to Update Console Output Messages

**What goes wrong:** Console output in Section 3 build_frequency_tables() function logs "Distinct PRIMARY codes: X (Y NOT IN XLSX)". This message no longer makes sense when PayerVariable.xlsx is removed.

**Why it happens:** Message assumes xlsx cross-reference logic. After refactor, there's no "NOT IN XLSX" concept — unmapped codes use prefix fallback.

**How to avoid:** Update console messages to reflect new logic:
```r
# OLD:
message(glue("  Distinct PRIMARY codes: {nrow(primary_freq)} ({n_not_in_xlsx_primary} NOT IN XLSX)"))

# NEW:
n_fallback_primary <- sum(is.na(AMC_PAYER_LOOKUP[primary_freq$code]), na.rm = TRUE)
message(glue("  Distinct PRIMARY codes: {nrow(primary_freq)} ({n_fallback_primary} via prefix fallback)"))
```

**Warning signs:** User confusion when reading console output that mentions xlsx files that no longer exist.

## Code Examples

Verified patterns from official sources.

### Common Operation 1: Replace xlsx left_join with AMC_PAYER_LOOKUP

```r
# Source: Derived from R/02_harmonize_payer.R lines 109-129 (map_payer_category function)
# and R/00_config.R lines 265-362 (AMC_PAYER_LOOKUP definition)

# In build_frequency_tables() function (Section 3):

build_frequency_tables <- function(enc_scope, suffix, output_dir) {
  total_enc <- nrow(enc_scope)

  # PRIMARY frequency table
  primary_freq <- enc_scope %>%
    mutate(
      code = case_when(
        is.na(PAYER_TYPE_PRIMARY) ~ "<NA>",
        PAYER_TYPE_PRIMARY == "" ~ "<EMPTY>",
        TRUE ~ PAYER_TYPE_PRIMARY
      )
    ) %>%
    count(code, name = "n") %>%
    mutate(
      # Direct lookup from AMC_PAYER_LOOKUP
      amc_category_looked_up = AMC_PAYER_LOOKUP[code],

      # Prefix-based fallback for unmapped codes
      prefix_first_digit = substr(code, 1, 1),
      prefix_category = case_when(
        prefix_first_digit == "1" ~ "Medicare",
        prefix_first_digit == "2" ~ "Medicaid",
        prefix_first_digit == "5" | prefix_first_digit == "6" ~ "Private",
        prefix_first_digit == "3" | prefix_first_digit == "4" ~ "Other govt",
        prefix_first_digit == "7" ~ "Private",
        prefix_first_digit == "8" ~ "Uninsured",
        prefix_first_digit == "9" ~ "Other",
        TRUE ~ "Other"
      ),

      # Final category: lookup if found, else prefix fallback, else Missing
      amc_category = case_when(
        code %in% c("<NA>", "<EMPTY>") ~ "Missing",
        !is.na(amc_category_looked_up) ~ amc_category_looked_up,
        TRUE ~ prefix_category
      ),

      pct = round(100 * n / total_enc, 2)
    ) %>%
    select(code, amc_category, n, pct) %>%
    arrange(desc(n))

  # SECONDARY frequency table (same logic)
  secondary_freq <- enc_scope %>%
    mutate(
      code = case_when(
        is.na(PAYER_TYPE_SECONDARY) ~ "<NA>",
        PAYER_TYPE_SECONDARY == "" ~ "<EMPTY>",
        TRUE ~ PAYER_TYPE_SECONDARY
      )
    ) %>%
    count(code, name = "n") %>%
    mutate(
      amc_category_looked_up = AMC_PAYER_LOOKUP[code],
      prefix_first_digit = substr(code, 1, 1),
      prefix_category = case_when(
        prefix_first_digit == "1" ~ "Medicare",
        prefix_first_digit == "2" ~ "Medicaid",
        prefix_first_digit == "5" | prefix_first_digit == "6" ~ "Private",
        prefix_first_digit == "3" | prefix_first_digit == "4" ~ "Other govt",
        prefix_first_digit == "7" ~ "Private",
        prefix_first_digit == "8" ~ "Uninsured",
        prefix_first_digit == "9" ~ "Other",
        TRUE ~ "Other"
      ),
      amc_category = case_when(
        code %in% c("<NA>", "<EMPTY>") ~ "Missing",
        !is.na(amc_category_looked_up) ~ amc_category_looked_up,
        TRUE ~ prefix_category
      ),
      pct = round(100 * n / total_enc, 2)
    ) %>%
    select(code, amc_category, n, pct) %>%
    arrange(desc(n))

  # Category-level summary
  primary_cat <- primary_freq %>%
    group_by(amc_category) %>%
    summarise(n = sum(n), .groups = "drop") %>%
    mutate(
      field = "PRIMARY",
      pct   = round(100 * n / total_enc, 2)
    ) %>%
    select(field, amc_category, n, pct) %>%
    arrange(desc(n))

  secondary_cat <- secondary_freq %>%
    group_by(amc_category) %>%
    summarise(n = sum(n), .groups = "drop") %>%
    mutate(
      field = "SECONDARY",
      pct   = round(100 * n / total_enc, 2)
    ) %>%
    select(field, amc_category, n, pct) %>%
    arrange(desc(n))

  category_summary <- bind_rows(primary_cat, secondary_cat)

  # Write CSVs (filenames unchanged per D-09)
  write_csv(primary_freq, file.path(output_dir, paste0("payer_primary_code_freq", suffix, ".csv")))
  write_csv(secondary_freq, file.path(output_dir, paste0("payer_secondary_code_freq", suffix, ".csv")))
  write_csv(category_summary, file.path(output_dir, paste0("payer_category_summary", suffix, ".csv")))

  # Updated console messages
  message(glue("  Written: payer_primary_code_freq{suffix}.csv ({nrow(primary_freq)} rows)"))
  message(glue("  Written: payer_secondary_code_freq{suffix}.csv ({nrow(secondary_freq)} rows)"))
  message(glue("  Written: payer_category_summary{suffix}.csv ({nrow(category_summary)} rows)"))

  n_fallback_primary <- sum(is.na(AMC_PAYER_LOOKUP[primary_freq$code]) &
                            !primary_freq$code %in% c("<NA>", "<EMPTY>"), na.rm = TRUE)
  n_fallback_secondary <- sum(is.na(AMC_PAYER_LOOKUP[secondary_freq$code]) &
                              !secondary_freq$code %in% c("<NA>", "<EMPTY>"), na.rm = TRUE)

  message(glue("  Distinct PRIMARY codes: {nrow(primary_freq)} ({n_fallback_primary} via prefix fallback)"))
  message(glue("  Distinct SECONDARY codes: {nrow(secondary_freq)} ({n_fallback_secondary} via prefix fallback)"))
}
```

### Common Operation 2: Remove Local Function Copies (Section 0)

```r
# Source: R/36_tiered_same_day_payer.R current lines 106-164 (to be deleted)
# Replaced by: source("R/02_harmonize_payer.R") OR inline simplified logic

# DELETE THESE (lines 106-164 in current R/36):
# compute_effective_payer_local <- function(primary, secondary) { ... }
# detect_dual_eligible_local <- function(primary, secondary) { ... }
# map_payer_category_local <- function(effective_payer) { ... }

# OPTION A: Source centralized functions
source("R/02_harmonize_payer.R")  # After source("R/00_config.R")

# OPTION B: Inline simplified logic (if avoiding cross-file dependency)
# In Section 2, directly use:
enc <- enc_raw %>%
  mutate(
    # Inline effective payer (6 lines, clearer than function call for single-use)
    effective_payer = case_when(
      !is.na(PAYER_TYPE_PRIMARY) & nchar(trimws(PAYER_TYPE_PRIMARY)) > 0 &
        !PAYER_TYPE_PRIMARY %in% c("NI", "UN", "OT") ~ PAYER_TYPE_PRIMARY,
      !is.na(PAYER_TYPE_SECONDARY) & nchar(trimws(PAYER_TYPE_SECONDARY)) > 0 &
        !PAYER_TYPE_SECONDARY %in% c("NI", "UN", "OT") ~ PAYER_TYPE_SECONDARY,
      TRUE ~ NA_character_
    ),
    # Use map_payer_category() from R/02 OR inline AMC_PAYER_LOOKUP + prefix logic
    payer_category = map_payer_category(effective_payer),  # If sourced R/02
    # ... rest of tier logic
  )
```

### Common Operation 3: Update Section 1 to Section 0 (Delete xlsx loading)

```r
# Source: R/36_tiered_same_day_payer.R lines 167-189 (current Section 1)

# DELETE ENTIRE SECTION:
# ==============================================================================
# SECTION 1: Load PayerVariable.xlsx
# ==============================================================================
#
# message("--- SECTION 1: Load PayerVariable.xlsx ---")
#
# payer_lookup <- readxl::read_excel(PAYER_XLSX_PATH, sheet = "Sheet2")
#
# # Rename columns for R-friendliness
# names(payer_lookup) <- c("code", "description", "category")
#
# # Trim whitespace and convert all to character
# payer_lookup <- payer_lookup %>%
#   mutate(across(everything(), ~trimws(as.character(.))))
#
# message(glue("Loaded {nrow(payer_lookup)} rows from PayerVariable.xlsx (Sheet2)"))
# message(glue("Unique categories in xlsx: {paste(sort(unique(payer_lookup$category)), collapse = ', ')}"))
# message(glue("Number of unique categories: {n_distinct(payer_lookup$category)}"))
#
# message("\nFirst 5 rows:")
# for (i in seq_len(min(5, nrow(payer_lookup)))) {
#   r <- payer_lookup[i, ]
#   message(glue("  code={r$code} | desc={r$description} | cat={r$category}"))
# }

# ALSO DELETE from Section 0:
# PAYER_XLSX_PATH <- "PayerVariable.xlsx"  # Line 61
# library(readxl)  # Line 56
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| PayerVariable.xlsx as payer mapping source (Phase 34/35) | AMC_PAYER_LOOKUP from R/00_config.R (Phase 36+) | 2026-04-30 (commit 67243b2) | Centralized payer mapping; single source of truth; no xlsx dependency; consistent with R/02 harmonization pipeline |
| 9-category payer mapping (Dual eligible as separate category) | AMC 8-category payer mapping (code 14 → Medicaid) | 2026-04-30 (commit 67243b2) | Aligns with Amy Crisp framework; simplifies category set; removes dual-eligible as standalone category (becomes informational flag only) |
| Local function copies in diagnostic scripts | Centralized functions in R/02_harmonize_payer.R | Phase 32+ (DuckDB migration) | Reduced duplication; easier maintenance; single source of logic updates |
| left_join-based category lookup (dataframe) | Named vector lookup (AMC_PAYER_LOOKUP[code]) | Phase 36 | Faster lookup; simpler code; no xlsx parsing overhead |

**Deprecated/outdated:**
- **PayerVariable.xlsx dependency**: Replaced by AMC_PAYER_LOOKUP in R/00_config.R. R/35 (Phase 34 baseline) keeps xlsx for historical comparison, but all new code uses config-based lookup.
- **readxl package in R/36**: No longer needed after Section 1 deletion.
- **Local payer mapping functions**: compute_effective_payer_local, map_payer_category_local, detect_dual_eligible_local are duplicates of R/02 logic. Remove per D-06.

## Open Questions

1. **Should R/36 source R/02_harmonize_payer.R or use inline logic?**
   - What we know: D-06 says "remove local function copies", suggesting use of centralized functions from R/02.
   - What's unclear: Does sourcing R/02 introduce unwanted side effects (e.g., R/02 also loads ENCOUNTER table via get_pcornet_table)? R/02 has Section 2 (ENCOUNTER processing) that R/36 doesn't need.
   - Recommendation: Extract just the three functions (compute_effective_payer, detect_dual_eligible, map_payer_category) into a new R/utils_payer.R utility file, OR use inline simplified logic in R/36 (6 lines for effective_payer + Pattern 1 for category mapping). Planner should decide based on "minimize duplication" vs "avoid cross-file dependencies" tradeoff. **Safest:** Inline logic (no source dependency), using AMC_PAYER_LOOKUP directly as shown in Code Examples.

2. **Do any downstream workflows depend on old column names?**
   - What we know: D-05 specifies new column layout (`code, amc_category, n, pct` instead of `code, description, category, n, pct`).
   - What's unclear: Whether Excel reports, PowerBI dashboards, or other R scripts consume these CSVs with hardcoded column name expectations.
   - Recommendation: Verify with user that no downstream dependencies exist. If they do, add backward-compatibility alias column (`category = amc_category`). If not, proceed with breaking change per D-05.

3. **Should console output mention prefix fallback counts?**
   - What we know: Current console output logs "X codes NOT IN XLSX" to show cross-reference gaps.
   - What's unclear: Whether PIs want visibility into how many codes used prefix fallback vs direct AMC_PAYER_LOOKUP.
   - Recommendation: Include fallback counts in console output for transparency: `message(glue("Distinct PRIMARY codes: {nrow(primary_freq)} ({n_fallback_primary} via prefix fallback)"))`. This maintains the visibility pattern from the xlsx approach but adapts to the new logic.

## Sources

### Primary (HIGH confidence)
- R/00_config.R lines 239-362 — AMC_PAYER_LOOKUP definition, PAYER_MAPPING$prefix_fallback, 8 standard categories
- R/02_harmonize_payer.R lines 47-129 — compute_effective_payer(), detect_dual_eligible(), map_payer_category() function implementations
- R/36_tiered_same_day_payer.R (current) — 489 lines, dual-scope frequency + resolution logic with PayerVariable.xlsx
- R/35_payer_code_frequency_av_th.R — Phase 34 baseline, shows original xlsx-based pattern
- 36-CONTEXT.md — User decisions from /gsd:discuss-phase (D-01 through D-10)
- payer_framework.txt — Amy Crisp same-day resolution hierarchy (Medicaid > Medicare > Private > Other > Self-pay > Uninsured > Missing)
- Git commit 67243b2 — "refactor: replace 9-category payer mapping with AMC 8-category lookup table" (2026-04-30)

### Secondary (MEDIUM confidence)
- CLAUDE.md — Project constraints (HiPerGator runtime, tidyverse ecosystem, AMC 8-category fidelity)
- .planning/STATE.md — Phase 34 complete, Phase 35 complete, Phase 36 pending
- .planning/config.json — workflow.nyquist_validation = false (no Validation Architecture section needed)

### Tertiary (LOW confidence)
- None — all findings verified from codebase files.

## Metadata

**Confidence breakdown:**
- AMC mapping logic: HIGH - Direct inspection of R/00_config.R and R/02_harmonize_payer.R, plus recent commit 67243b2
- Refactoring pattern: HIGH - Current R/36 structure inspected, clear left_join → vector lookup transformation
- User decisions: HIGH - 36-CONTEXT.md provides explicit D-01 through D-10 constraints
- Downstream impact: MEDIUM - Unknown if other workflows consume the CSVs; marked as Open Question

**Research date:** 2026-04-30
**Valid until:** 2026-05-30 (30 days for stable refactoring task; R package ecosystem and payer mapping logic unlikely to change)
