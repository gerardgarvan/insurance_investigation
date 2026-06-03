# Phase 81: Filter Unknown from cancer_codes, add category column, map unmapped sub-categories - Research

**Researched:** 2026-06-03
**Domain:** R data manipulation (dplyr), named vector configuration, code resolution
**Confidence:** HIGH

## Summary

Phase 81 refines the drug grouping summary table outputs from R/56 through three independent modifications: (1) filtering out rows with NA cancer_codes, (2) adding a category column derived from treatment_type to Table 1, and (3) resolving all unmapped sub-category labels via a new centralized CODE_SUBCATEGORY_MAP config vector.

All three modifications use standard dplyr operations and follow established project patterns (centralized named vectors in R/00_config.R, three-tier lookup hierarchies). No new package dependencies required — existing tidyverse stack (dplyr 1.2.0+, stringr 1.5.1+) provides all needed functionality.

**Primary recommendation:** Use `filter(!is.na(cancer_codes))` before aggregation for both tables, add `category = treatment_type` in early pipeline stages and use `relocate(category, .before = 1)` for column ordering, and create CODE_SUBCATEGORY_MAP as a named vector in R/00_config.R following the AMC_PAYER_LOOKUP pattern with entries like `"J9035" = "Bevacizumab"`.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Filter out rows with no cancer diagnosis codes (`cancer_codes` is NA) from both Table 1 (Sub-Category Summary) and Table 2 (Encounter Treatment Summary) entirely. Do not replace NA with "Unknown" — exclude these rows from the output.
- **D-02:** Filter silently — no additional log message for the filtering. The existing Section 4 NOTE about episodes without cancer codes already reports the count.
- **D-03:** Add a `category` column as the **first column** in Table 1. Final column order: `category | sub_category | cancer_codes | encounter_count`.
- **D-04:** Derive `category` value from the episode's `treatment_type` field directly (Chemotherapy, Radiation, SCT, Immunotherapy). No parsing from sub_category labels.
- **D-05:** Sort Table 1 by `category` first (alphabetical or custom order), then by descending `encounter_count` within each category. This groups related sub-categories together.
- **D-06:** Resolve ALL non-xlsx sub-categories — both code-type fallbacks (Tier 2: "Chemo HCPCS (no xlsx mapping)", "Chemo RxNorm", etc.) and truly unmapped codes (Tier 3: "Chemotherapy (unmapped)", "Radiation (unmapped)", "SCT (unmapped)").
- **D-07:** Create a new `CODE_SUBCATEGORY_MAP` named vector in `R/00_config.R` that maps treatment codes to sub-category names. Follows the centralized config pattern established by `DRUG_GROUPINGS`, `CANCER_SITE_MAP`, and `AMC_PAYER_LOOKUP`.
- **D-08:** Map to readable medication/procedure names where possible (e.g., HCPCS J9035 -> "Bevacizumab"). Fall back to code-type group labels only for codes where a specific name cannot be determined.
- **D-09:** R/56 lookup order: (1) reference xlsx sub-category mappings, (2) `CODE_SUBCATEGORY_MAP` from config, (3) final fallback label only if code is in neither.

### Claude's Discretion
- Category sort order within Table 1 (alphabetical vs custom logical ordering like Chemo > Radiation > SCT > Immunotherapy)
- How to investigate and identify readable names for currently unmapped codes (DRUG_GROUPINGS cross-reference, HCPCS/CPT code descriptions, etc.)
- Whether to add a summary count of resolved vs remaining unmapped codes to the console log

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope.
</user_constraints>

## Standard Stack

All required functionality already present in project dependencies (CLAUDE.md § Technology Stack).

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| dplyr | 1.2.0+ | Data frame filtering, column manipulation, sorting | Tidyverse ecosystem standard; `filter()`, `mutate()`, `relocate()`, `arrange()` are idiomatic R |
| stringr | 1.5.1+ | String pattern detection for code resolution | Already used in R/56 for ICD normalization; `str_detect()` for code matching |
| checkmate | (current) | Input validation | Project standard (utils_assertions.R); no new assertions needed but follows project pattern |

**Installation:** Already installed via project renv.lock. No new packages required.

**Version verification:** Project uses renv with pinned versions. No version changes needed.

## Architecture Patterns

### Pattern 1: NA Filtering in Aggregation Pipeline
**What:** Filter out NA values from a column before aggregation to exclude incomplete rows from output.

**When to use:** When summarizing data where missing values in a key field should exclude the entire row (not be aggregated separately).

**Example:**
```r
# CURRENT (R/56 lines 341-346): Replaces NA with "Unknown"
table1 <- episode_codes %>%
  mutate(cancer_codes = if_else(is.na(cancer_codes), "Unknown", cancer_codes)) %>%
  group_by(sub_category, cancer_codes) %>%
  summarise(encounter_count = n(), .groups = "drop")

# UPDATED: Filter out NA before aggregation
table1 <- episode_codes %>%
  filter(!is.na(cancer_codes)) %>%  # Add before aggregation
  group_by(sub_category, cancer_codes) %>%
  summarise(encounter_count = n(), .groups = "drop")
```

**Why this works:** `filter()` removes rows where the condition is FALSE or NA. `!is.na(cancer_codes)` evaluates to TRUE only for non-NA values, excluding NA rows from downstream operations.

### Pattern 2: Adding Derived Columns Early in Pipeline
**What:** Add derived columns (like `category` from `treatment_type`) before expansion/aggregation so the value is available in all downstream operations.

**When to use:** When a column value is needed for sorting, grouping, or display but derives from an existing column that might be lost during aggregation.

**Example:**
```r
# Add category early (before unnest/expansion)
episode_codes <- episode_dx %>%
  mutate(category = treatment_type) %>%  # Add before unnest
  mutate(code_list = str_split(triggering_codes, ",\\s*")) %>%
  unnest(code_list) %>%
  filter(!is.na(code_list), code_list != "") %>%
  rename(treatment_code = code_list)
```

**Why this works:** Adding `category` before `unnest()` copies the value to all expanded rows, making it available for aggregation. This is cleaner than re-joining treatment_type after aggregation.

### Pattern 3: Column Reordering with relocate()
**What:** Use `dplyr::relocate()` to move columns to specific positions without manually listing all columns.

**When to use:** When you need to reorder a subset of columns (especially moving one to the front) without disrupting the rest.

**Example:**
```r
# Reorder: category first, then existing columns
table1 <- episode_codes %>%
  filter(!is.na(cancer_codes)) %>%
  group_by(category, sub_category, cancer_codes) %>%  # Add category to grouping
  summarise(encounter_count = n(), .groups = "drop") %>%
  relocate(category, .before = 1)  # Move category to first position

# Result: category | sub_category | cancer_codes | encounter_count
```

**Why this works:** `relocate(category, .before = 1)` moves `category` to the first position. Alternative syntax: `relocate(category, .before = everything())` is more explicit but equivalent.

### Pattern 4: Multi-Level Sorting with arrange()
**What:** Sort by multiple columns to group related rows and order within groups.

**When to use:** When output needs hierarchical ordering (primary sort key, then secondary within groups).

**Example:**
```r
# Sort by category, then by descending encounter_count within category
table1 <- table1 %>%
  arrange(category, desc(encounter_count))

# For custom category order (not alphabetical):
category_order <- c("Chemotherapy", "Radiation", "SCT", "Immunotherapy")
table1 <- table1 %>%
  mutate(category = factor(category, levels = category_order)) %>%
  arrange(category, desc(encounter_count))
```

**Why this works:** `arrange()` accepts multiple columns; sorts by first column, then breaks ties with subsequent columns. `desc()` reverses sort order for numeric columns. Using `factor()` with explicit levels allows custom (non-alphabetical) ordering.

### Pattern 5: Named Vector Lookups in R/00_config.R
**What:** Define code-to-label mappings as named character vectors in centralized config, then use vector indexing for fast lookups.

**When to use:** When you have a fixed mapping of codes to labels that multiple scripts need to reference.

**Example:**
```r
# In R/00_config.R
CODE_SUBCATEGORY_MAP <- c(
  # Chemotherapy HCPCS codes -> medication names
  "J9035" = "Bevacizumab",
  "J9310" = "Rituximab",
  "J9303" = "Paclitaxel",

  # Radiation CPT codes -> procedure types
  "77385" = "IMRT - Planning",
  "77386" = "IMRT - Delivery",

  # SCT CPT codes -> procedure types
  "38241" = "Allogeneic Bone Marrow Transplant",
  "38204" = "Autologous Stem Cell Transplant"
)

# In R/56_new_tables_from_groupings.R
episode_codes <- episode_codes %>%
  mutate(
    sub_category = case_when(
      # Tier 1: xlsx-mapped sub-categories
      treatment_code %in% names(code_to_subcategory) ~ code_to_subcategory[treatment_code],

      # Tier 2: CODE_SUBCATEGORY_MAP from config
      treatment_code %in% names(CODE_SUBCATEGORY_MAP) ~ CODE_SUBCATEGORY_MAP[treatment_code],

      # Tier 3: code-type fallback labels
      treatment_type == "Chemotherapy" & treatment_code %in% chemo_hcpcs_codes ~ "Chemo HCPCS (no mapping)",
      # ... rest of fallbacks

      TRUE ~ paste0(treatment_type, " (unmapped)")
    )
  )
```

**Why this works:** Named vector indexing (`vector[key]`) is O(1) lookup. `treatment_code %in% names(CODE_SUBCATEGORY_MAP)` checks existence before indexing to avoid NAs. Pattern matches AMC_PAYER_LOOKUP and CANCER_SITE_MAP from existing codebase.

### Pattern 6: Three-Tier Lookup Hierarchy with case_when()
**What:** Use `case_when()` with ordered conditions to implement fallback logic: try most specific lookup first, then broader fallbacks, ending with a default label.

**When to use:** When mapping codes to labels with multiple sources of truth (authoritative reference, supplemental mapping, code-type inference, default).

**Example:**
```r
# Current R/56 two-tier hierarchy (lines 279-319)
sub_category = case_when(
  # Tier 1: xlsx reference lookup (most authoritative)
  treatment_code %in% names(code_to_subcategory) ~ code_to_subcategory[treatment_code],

  # Tier 2: Code-type fallback labels
  treatment_type == "Chemotherapy" & treatment_code %in% chemo_hcpcs_codes ~ "Chemo HCPCS (no xlsx mapping)",
  treatment_type == "Chemotherapy" ~ "Chemotherapy (unmapped)",

  TRUE ~ treatment_type
)

# Updated three-tier hierarchy (insert CODE_SUBCATEGORY_MAP between Tier 1 and 2)
sub_category = case_when(
  # Tier 1: xlsx reference lookup (most authoritative)
  treatment_code %in% names(code_to_subcategory) ~ code_to_subcategory[treatment_code],

  # Tier 2: CODE_SUBCATEGORY_MAP supplement (new)
  treatment_code %in% names(CODE_SUBCATEGORY_MAP) ~ CODE_SUBCATEGORY_MAP[treatment_code],

  # Tier 3: Code-type fallback labels (only for codes in neither lookup)
  treatment_type == "Chemotherapy" & treatment_code %in% chemo_hcpcs_codes ~ "Chemo HCPCS (no mapping)",
  treatment_type == "Chemotherapy" ~ "Chemotherapy (unmapped)",

  TRUE ~ treatment_type
)
```

**Why this works:** `case_when()` evaluates conditions top-to-bottom and returns the first match. Inserting the CODE_SUBCATEGORY_MAP check after xlsx lookup but before code-type fallbacks ensures: (1) xlsx mappings take precedence (most authoritative), (2) supplemental mappings fill gaps, (3) code-type labels only apply to truly unmapped codes.

### Anti-Patterns to Avoid
- **Don't use base R subset `df[condition, ]` in pipe chains:** Breaks %>% flow; use `filter()` instead.
- **Don't manually reorder columns with `select(col1, col2, col3, ...)`:** Fragile if columns change; use `relocate()` for targeted reordering.
- **Don't use `ifelse()` for vectorized lookups:** `case_when()` is more readable for multi-condition logic; named vector indexing is faster than nested `ifelse()`.
- **Don't hard-code lookup maps in script logic:** Violates DRY; centralize in R/00_config.R following AMC_PAYER_LOOKUP pattern.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Code-to-name lookups | Custom functions with if/else cascades | Named vectors with vector indexing | O(1) lookup vs O(n); standard R pattern; maintainable in config |
| Multi-column sorting | Manual ordering then rbind | `arrange(col1, desc(col2))` | dplyr handles tie-breaking correctly; more readable |
| Column reordering | `select()` with all columns listed | `relocate(col, .before = position)` | Robust to schema changes; explicit about intent |
| NA filtering | `subset(df, !is.na(col))` | `filter(!is.na(col))` | Tidyverse standard; integrates with pipe chains |

**Key insight:** dplyr verbs (`filter`, `mutate`, `relocate`, `arrange`) are optimized, well-tested, and compose cleanly in pipe chains. Custom logic for these operations adds complexity without benefit.

## Code Mapping Strategy

### Sources for CODE_SUBCATEGORY_MAP

Based on the context and existing code patterns, here are the sources to identify readable names for currently unmapped codes:

#### 1. Cross-Reference with DRUG_GROUPINGS
**Current state:** DRUG_GROUPINGS in R/00_config.R (lines 1153+) maps 454 treatment codes to categories (Chemotherapy, Radiation, SCT, Immunotherapy, Supportive Care).

**Issue:** Maps codes to broad category, not to medication/procedure name. Example: "J9035" = "Chemotherapy" (not "Bevacizumab").

**Opportunity:** DRUG_GROUPINGS confirms which codes are treatment-related and which category. Use this as a filter — if a code is in DRUG_GROUPINGS, it needs a sub-category mapping.

#### 2. Reference XLSX Column C (Chemotherapy Medications)
**Current state:** `all_codes_resolved_next_tables_v2.1.xlsx` Chemotherapy sheet has medication names in column C (read at R/56 line 118).

**Coverage:** 205 chemotherapy codes mapped to medication names (per DRUG_GROUPINGS comment line 1149).

**Gap:** HCPCS and RxNorm codes not in xlsx but appearing in data (identified by R/56 lines 290-291, 322-330 console logs).

**Action:** Codes in DRUG_GROUPINGS but NOT in xlsx column C need CODE_SUBCATEGORY_MAP entries.

#### 3. HCPCS Code Descriptions
**Source:** CMS HCPCS Code Files (public domain, updated quarterly).

**Example:** J9035 = "Injection, bevacizumab, 10 mg" → extract "Bevacizumab".

**Pattern:** HCPCS J-codes (drugs administered by injection) have standardized descriptions: "Injection, [drug name], [dosage]".

**Implementation:**
- For HCPCS codes in `chemo_hcpcs_codes` (R/00_config.R TREATMENT_CODES$chemo_hcpcs), look up official HCPCS description
- Extract drug name (second field after "Injection, ")
- Add to CODE_SUBCATEGORY_MAP as `"J9035" = "Bevacizumab"`

**Data source:** CMS HCPCS files available at https://www.cms.gov/medicare/coding-billing/healthcare-common-procedure-system or via medical coding references.

#### 4. RxNorm Concept Names
**Source:** RxNorm API or RxNav browser (https://rxnav.nlm.nih.gov/).

**Example:** RxCUI 1147324 = "Doxorubicin" → use "Doxorubicin".

**Pattern:** RxNorm Concept Unique Identifiers (RxCUIs) map to standardized drug names.

**Implementation:**
- For RxNorm codes in `chemo_rxnorm_codes` (TREATMENT_CODES$chemo_rxnorm), query RxNorm API or use cached mappings
- Use the preferred term (TTY = IN or SCD) as sub-category name
- Add to CODE_SUBCATEGORY_MAP as `"1147324" = "Doxorubicin"`

**Note:** RxNorm codes are numeric strings (6-8 digits). Distinguish from HCPCS by pattern: RxNorm = all digits, HCPCS = letter + digits.

#### 5. CPT Code Descriptions
**Source:** AMA CPT code files (proprietary but available via medical coding references).

**Example:** CPT 77385 = "Intensity modulated radiation therapy (IMRT); planning" → use "IMRT - Planning".

**Pattern:** CPT codes for procedures have descriptive names.

**Implementation:**
- For Radiation CPT codes in `rad_cpt_codes` (TREATMENT_CODES$radiation_cpt), look up CPT description
- Shorten to essential procedure type (e.g., "IMRT - Planning" not full 80-char description)
- Add to CODE_SUBCATEGORY_MAP as `"77385" = "IMRT - Planning"`

#### 6. SCT CPT/HCPCS Codes
**Source:** AMA CPT for stem cell transplant procedure codes (38204-38241 range per R/56 comment line 93).

**Example:** CPT 38241 = "Hematopoietic progenitor cell (HPC); allogeneic transplantation" → use "Allogeneic Transplant".

**Pattern:** SCT codes describe transplant type (Allogeneic vs Autologous) and source (bone marrow, peripheral blood, cord blood).

**Implementation:**
- For SCT codes in `sct_cpt_hcpcs_codes` (TREATMENT_CODES$sct_cpt + sct_hcpcs), look up CPT/HCPCS description
- Extract transplant type and source
- Add to CODE_SUBCATEGORY_MAP as `"38241" = "Allogeneic Bone Marrow Transplant"`

### Code Resolution Workflow

```r
# Pseudocode for building CODE_SUBCATEGORY_MAP

# Step 1: Identify codes needing resolution
unmapped_codes <- episode_codes %>%
  filter(str_detect(sub_category, "no xlsx mapping|unmapped")) %>%
  distinct(treatment_type, treatment_code)

# Step 2: For each code, look up description
# - If HCPCS J-code: CMS HCPCS file → extract drug name
# - If RxNorm (all digits): RxNorm API → get preferred term
# - If CPT (radiation): CPT file → extract procedure type
# - If CPT (SCT): CPT file → extract transplant type

# Step 3: Build CODE_SUBCATEGORY_MAP entries
CODE_SUBCATEGORY_MAP <- c(
  "J9035" = "Bevacizumab",  # HCPCS lookup
  "1147324" = "Doxorubicin",  # RxNorm lookup
  "77385" = "IMRT - Planning",  # CPT lookup
  "38241" = "Allogeneic Bone Marrow Transplant"  # CPT lookup
)

# Step 4: Document sources in R/00_config.R comments
# Comment above CODE_SUBCATEGORY_MAP:
# Source: HCPCS codes from CMS HCPCS 2025 Q4 file, RxNorm from RxNav API 2026-06,
#         CPT codes from reference sources (procedural descriptions abbreviated)
```

### Fallback Strategy

For codes where no readable name can be found:
- **Keep code-type group label:** "Chemo HCPCS (no mapping)" is acceptable for rare codes
- **Log for human review:** Add to console summary: "X codes remain unmapped after CODE_SUBCATEGORY_MAP resolution"
- **Don't invent names:** If source is unavailable, leave as code-type label rather than guessing

## Common Pitfalls

### Pitfall 1: Filtering After Aggregation
**What goes wrong:** Filtering out NA rows after `group_by() %>% summarise()` leaves "Unknown" or empty groups in aggregated output.

**Why it happens:** If NA rows are included in aggregation, they create separate groups (NA becomes a grouping level).

**How to avoid:** Filter NA values **before** `group_by()`. This excludes them from aggregation entirely.

**Warning signs:** Output has rows with `cancer_codes = "Unknown"` or blank values; row counts don't match filtered expectations.

**Example:**
```r
# WRONG: Filter after aggregation
table1 <- df %>%
  group_by(category, cancer_codes) %>%
  summarise(count = n()) %>%
  filter(!is.na(cancer_codes))  # Too late; NA group already created

# RIGHT: Filter before aggregation
table1 <- df %>%
  filter(!is.na(cancer_codes)) %>%  # Exclude NA rows first
  group_by(category, cancer_codes) %>%
  summarise(count = n())
```

### Pitfall 2: Losing Derived Columns in Aggregation
**What goes wrong:** Adding `category = treatment_type` after aggregation requires a re-join, or the column is lost.

**Why it happens:** `group_by() %>% summarise()` only retains grouping columns and summarized columns. Other columns from the input data frame are dropped.

**How to avoid:** Add derived columns **before** aggregation operations (before `group_by()`).

**Warning signs:** `mutate(category = treatment_type)` fails because `treatment_type` is no longer in the aggregated data frame.

**Example:**
```r
# WRONG: Add category after aggregation
table1 <- df %>%
  group_by(sub_category, cancer_codes) %>%
  summarise(count = n()) %>%
  mutate(category = treatment_type)  # ERROR: treatment_type doesn't exist

# RIGHT: Add category before aggregation
table1 <- df %>%
  mutate(category = treatment_type) %>%  # Add early
  group_by(category, sub_category, cancer_codes) %>%  # Include in grouping
  summarise(count = n())
```

### Pitfall 3: Vector Indexing Returns NA for Missing Keys
**What goes wrong:** Indexing a named vector with a key that doesn't exist returns NA (not an error), leading to silent failures.

**Why it happens:** R's vector indexing returns NA for out-of-bounds or missing names by default.

**How to avoid:** Check existence with `%in% names(vector)` before indexing in `case_when()`.

**Warning signs:** Sub-category values are NA when they should have fallback labels; "unmapped" labels don't appear.

**Example:**
```r
# WRONG: Direct indexing without existence check
sub_category = CODE_SUBCATEGORY_MAP[treatment_code]  # Returns NA if code not in map

# RIGHT: Check existence first in case_when()
sub_category = case_when(
  treatment_code %in% names(CODE_SUBCATEGORY_MAP) ~ CODE_SUBCATEGORY_MAP[treatment_code],
  TRUE ~ "Unmapped"  # Fallback for missing keys
)
```

### Pitfall 4: Case-Sensitive Code Matching
**What goes wrong:** HCPCS codes in data are lowercase ("j9035") but lookup map uses uppercase ("J9035"), causing mismatches.

**Why it happens:** Code standardization varies by data source (PCORnet may store codes in different cases).

**How to avoid:** Normalize codes to uppercase (or lowercase consistently) before lookups.

**Warning signs:** Codes appear unmapped despite being in CODE_SUBCATEGORY_MAP; manual inspection shows case mismatch.

**Example:**
```r
# Add normalization step before lookup
episode_codes <- episode_codes %>%
  mutate(treatment_code = toupper(treatment_code)) %>%  # Normalize to uppercase
  mutate(sub_category = case_when(
    treatment_code %in% names(CODE_SUBCATEGORY_MAP) ~ CODE_SUBCATEGORY_MAP[treatment_code],
    # ... rest of lookups
  ))
```

**Note:** Check existing R/56 code (lines 244-247) to see if normalization is already applied. If `treatment_code` is extracted from `triggering_codes` without normalization, add `toupper()` or `tolower()` before lookup.

### Pitfall 5: Factor Levels for Custom Sort Order
**What goes wrong:** Using `factor()` without explicit levels defaults to alphabetical order, not the intended custom order.

**Why it happens:** R's `factor()` function sorts levels alphabetically by default if `levels` argument is not provided.

**How to avoid:** Explicitly specify `levels` argument in `factor()` with desired order.

**Warning signs:** Table 1 sorted alphabetically (Chemotherapy, Immunotherapy, Radiation, SCT) instead of logical treatment order.

**Example:**
```r
# WRONG: Factor without explicit levels (alphabetical)
table1 <- table1 %>%
  mutate(category = factor(category)) %>%
  arrange(category)
# Result: Alphabetical order

# RIGHT: Factor with explicit levels
category_order <- c("Chemotherapy", "Radiation", "SCT", "Immunotherapy")
table1 <- table1 %>%
  mutate(category = factor(category, levels = category_order)) %>%
  arrange(category)
# Result: Custom order
```

**Recommendation:** Since user left sort order to Claude's discretion (CONTEXT.md § Claude's Discretion), document the chosen order in code comments. Logical treatment order (Chemo → Radiation → SCT → Immunotherapy) reflects typical treatment sequencing.

## Open Questions

1. **HCPCS/CPT code databases availability**
   - What we know: CMS HCPCS files are public domain; AMA CPT codes are proprietary but available via medical coding references
   - What's unclear: Whether planner has access to these databases or needs to use alternate sources (e.g., cached mappings, manual lookup)
   - Recommendation: Planner should identify which codes are currently unmapped (via console logs from existing R/56 runs), then look up a representative sample (5-10 codes) to build CODE_SUBCATEGORY_MAP. Full coverage is not required — map the most common codes first, leave rare codes with fallback labels.

2. **RxNorm API rate limits**
   - What we know: RxNorm API is free for research use (https://rxnav.nlm.nih.gov/api.html)
   - What's unclear: Whether bulk lookups are feasible or if manual lookup is needed
   - Recommendation: For <50 RxNorm codes, manual lookup via RxNav web interface is faster than API integration. For >50 codes, consider batch API calls or cached RxNorm concept name files.

3. **CODE_SUBCATEGORY_MAP completeness target**
   - What we know: User wants "ALL non-xlsx sub-categories" resolved (D-06)
   - What's unclear: Whether "all" means 100% coverage or "all commonly occurring" codes
   - Recommendation: Prioritize codes with high encounter counts (top 80% of volume) for CODE_SUBCATEGORY_MAP. Rare codes (bottom 20%) can remain with code-type fallback labels. Add console summary logging: "Resolved X/Y unmapped codes (Z% of encounters)".

## Environment Availability

All dependencies already installed via project renv.lock. No external tools required beyond R and existing packages.

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| dplyr | Data manipulation | ✓ | 1.2.0+ (renv) | — |
| stringr | String operations | ✓ | 1.5.1+ (renv) | — |
| checkmate | Assertions | ✓ | (renv) | — |

**Missing dependencies:** None.

## Sources

### Primary (HIGH confidence)
- Existing codebase: R/56_new_tables_from_groupings.R (lines 1-423) — current implementation patterns
- Existing codebase: R/00_config.R (AMC_PAYER_LOOKUP lines 319-383, CANCER_SITE_MAP lines 433+, DRUG_GROUPINGS lines 1153+) — named vector pattern
- dplyr documentation: https://dplyr.tidyverse.org/ (filter, mutate, relocate, arrange, case_when) — verified current as of 2026-06-03
- CLAUDE.md § Technology Stack — project package versions (dplyr 1.2.0+, stringr 1.5.1+)

### Secondary (MEDIUM confidence)
- CMS HCPCS Code Files: https://www.cms.gov/medicare/coding-billing/healthcare-common-procedure-system — public domain drug code descriptions
- RxNorm API: https://rxnav.nlm.nih.gov/ — NLM drug terminology service

### Tertiary (LOW confidence - flagged for validation)
- CPT code descriptions: Proprietary AMA resource; planner may need alternate sources (medical coding references, cached mappings)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All operations use existing project dependencies (dplyr, stringr); no new packages
- Architecture patterns: HIGH - dplyr verbs (filter, mutate, relocate, arrange) are stable R idioms; named vector pattern verified from existing codebase
- Code resolution strategy: MEDIUM - HCPCS/RxNorm sources are standard but availability for bulk lookup uncertain
- Pitfalls: HIGH - Based on common R/dplyr errors and existing code patterns in R/56

**Research date:** 2026-06-03
**Valid until:** 2026-09-03 (90 days; R/tidyverse stable, infrequent breaking changes)
