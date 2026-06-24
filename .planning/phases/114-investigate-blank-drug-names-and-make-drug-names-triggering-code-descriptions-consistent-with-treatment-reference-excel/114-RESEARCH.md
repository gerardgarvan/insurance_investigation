# Phase 114: Investigate blank drug names and make drug_names/triggering_code_descriptions consistent with treatment reference excel - Research

**Researched:** 2026-06-24
**Domain:** Data quality remediation, reference data alignment, lookup table filling
**Confidence:** HIGH

## Summary

Phase 114 addresses two related data quality issues: (1) blank drug_names in treatment episodes despite the presence of triggering_codes (J-codes, billing codes) that map to known medications, and (2) inconsistencies between pipeline-generated drug_names/triggering_code_descriptions and the canonical treatment reference Excel file. The solution involves modifying upstream pipeline scripts (R/27, R/42, R/26, R/28) to use the reference Excel as the authoritative source for medication names and code descriptions, and producing a separate audit Excel documenting all changes.

**Primary recommendation:** Build a reference-based lookup table from the Medication column (column 3) of all_codes_resolved_next_tables_v2.1.xlsx during pipeline initialization, then use dplyr left_join + coalesce to fill blank drug_names and override inconsistent triggering_code_descriptions. Produce a standalone investigation script (R/6X pattern) that audits before/after states with two-sheet styled Excel output.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Blank Drug Names:**
- **D-01:** Investigate AND fill blank drug_names where possible — not report-only. Episodes with blank drug_names that have triggering_codes should be resolved.
- **D-02:** Use the **Medication** column from `all_codes_resolved_next_tables_v2.1.xlsx` as the fill source. Do NOT include route, dosage, or full description — just the medication name.
- **D-03:** Map triggering_codes to the reference excel to fill blanks. This is the primary fill mechanism (most blanks likely have J-codes or billing codes).

**Consistency Target:**
- **D-04:** Treatment reference excel (`all_codes_resolved_next_tables_v2.1.xlsx`) is the authoritative source for drug names and code descriptions. Pipeline values that disagree are bugs to fix.
- **D-05:** triggering_code_descriptions should match the treatment reference excel. Discrepancies = pipeline fixes, not reference corrections.

**Normalization:**
- **D-06:** Claude's discretion on normalization level (exact character match vs cleaned/title-cased form). Choose what makes sense given the data.

**Output Structure:**
- **D-07:** Before/after audit xlsx with two sheets: Sheet 1 = summary of blanks filled and discrepancies fixed with counts. Sheet 2 = per-code detail showing old vs new drug_name/description values.
- **D-08:** Audit xlsx produced by a **separate standalone investigation script** (not built into modified pipeline scripts). Follows the R/59, R/51 standalone pattern.

**Pipeline Modification:**
- **D-09:** Modify upstream pipeline scripts (R/27, R/42, R/26, R/28 as needed) so drug_names and triggering_code_descriptions use the treatment reference excel as source of truth. Changes propagate through all downstream outputs.

### Claude's Discretion

- Which specific pipeline scripts need modification (R/27 drug name resolution, R/42 code descriptions, R/26 episode builder, R/28 episode classification — determine based on where inconsistencies originate)
- Styled xlsx headers following existing meeting-presentable pattern (dark gray FF374151, white bold text, freeze panes)
- New script number assignment for the audit script
- Whether to add the audit script to pipeline runner (R/39 or equivalent)

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope
</user_constraints>

## Standard Stack

### Core Libraries
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| openxlsx2 | 1.16+ | Read reference Excel | Already used in R/36, R/56, R/57, R/58; modern rewrite with pipes support |
| dplyr | 1.2.0+ | Lookup table joins, value filling | Project standard; left_join + coalesce pattern for filling blanks |
| stringr | 1.5.1+ | String normalization | Project standard; str_to_title, str_trim for consistent medication names |
| glue | 1.8.0 | Logging messages | Project standard; readable audit logging |

### Supporting Libraries
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| data.table | 1.16.2+ | Keyed joins (optional) | If dplyr performance is insufficient for 454-code lookup |
| checkmate | 2.3.0+ | Input validation | Already used in utils; validate reference Excel structure |

**Installation:**
```bash
# All libraries already installed in project renv
# No additional installation required
```

**Version verification:** All packages verified as already present in project renv.lock.

## Architecture Patterns

### Reference Excel Structure (Verified Pattern)

The treatment reference Excel has 5 sheets (Chemotherapy, Radiation, SCT, Immunotherapy, Supportive Care) with consistent structure across all scripts reading it:

```r
# Pattern from R/57, R/36, R/56, R/58
ref_wb <- wb_load("data/reference/all_codes_resolved_next_tables_v2.1.xlsx")
chemo_sheet <- wb_to_df(ref_wb, sheet = "Chemotherapy", start_row = 2)

# Column [[1]] = HCPCS.CPT.Code (the treatment code)
# Column [[3]] = Medication (the canonical drug name)
# Column [[7]] = Type of Treatment (for radiation/SCT sub-categorization)

# Build code -> medication lookup (existing pattern)
chemo_map <- setNames(as.character(chemo_sheet[[3]]), as.character(chemo_sheet[[1]]))
chemo_map <- chemo_map[!is.na(names(chemo_map)) & !is.na(chemo_map)]
```

### Pattern 1: Reference-Based Lookup Table Building

**What:** Extract medication names from all 5 sheets of reference Excel at pipeline startup, combine into single named character vector.

**When to use:** R/27 drug name resolution (replace/augment RxNorm API), R/42 code description building (add medication names to descriptions).

**Example:**
```r
# Source: Derived from R/57 lines 140-159
REFERENCE_XLSX <- "data/reference/all_codes_resolved_next_tables_v2.1.xlsx"

build_medication_lookup <- function(reference_xlsx_path) {
  ref_wb <- wb_load(reference_xlsx_path)

  # Extract from all 5 sheets
  chemo_sheet <- wb_to_df(ref_wb, sheet = "Chemotherapy", start_row = 2)
  rad_sheet <- wb_to_df(ref_wb, sheet = "Radiation", start_row = 2)
  sct_sheet <- wb_to_df(ref_wb, sheet = "SCT", start_row = 2)
  immuno_sheet <- wb_to_df(ref_wb, sheet = "Immunotherapy", start_row = 2)
  support_sheet <- wb_to_df(ref_wb, sheet = "Supportive Care", start_row = 2)

  # Build code -> medication mappings (column 1 = code, column 3 = medication)
  chemo_map <- setNames(as.character(chemo_sheet[[3]]), as.character(chemo_sheet[[1]]))
  rad_map <- setNames(as.character(rad_sheet[[3]]), as.character(rad_sheet[[1]]))
  sct_map <- setNames(as.character(sct_sheet[[3]]), as.character(sct_sheet[[1]]))
  immuno_map <- setNames(as.character(immuno_sheet[[3]]), as.character(immuno_sheet[[1]]))
  support_map <- setNames(as.character(support_sheet[[3]]), as.character(support_sheet[[1]]))

  # Combine and deduplicate
  all_medications <- c(chemo_map, rad_map, sct_map, immuno_map, support_map)
  all_medications <- all_medications[!is.na(names(all_medications)) & !is.na(all_medications)]

  # Normalize medication names (D-06 discretion: title case + trim)
  all_medications <- str_to_title(str_trim(all_medications))

  return(all_medications)
}

# Usage in R/27 or R/42
MEDICATION_LOOKUP <- build_medication_lookup(REFERENCE_XLSX)
message(glue("  Loaded {length(MEDICATION_LOOKUP)} medication names from reference Excel"))
```

### Pattern 2: Fill Blank Drug Names via Left Join + Coalesce

**What:** For treatment_episode_detail rows with blank drug_name but non-blank triggering_code, look up medication name from reference and fill.

**When to use:** R/26 treatment_episodes.R after drug_name_lookup.rds join, before episode aggregation.

**Example:**
```r
# Source: Adapted from dplyr coalesce join pattern
# https://www.asterhu.com/post/2023-05-11-coalesce-join-in-r/

# Load reference-based medication lookup (from R/00_config.R or built at runtime)
medication_ref <- tibble(
  triggering_code = names(MEDICATION_LOOKUP),
  ref_medication = MEDICATION_LOOKUP
)

# Identify rows with blank drug_name
detail_with_blanks <- all_detail %>%
  mutate(
    drug_name_was_blank = is.na(drug_name) | drug_name == ""
  )

# Left join reference medications
detail_filled <- detail_with_blanks %>%
  left_join(medication_ref, by = "triggering_code") %>%
  mutate(
    drug_name = coalesce(drug_name, ref_medication),  # Fill blank with reference
    .keep = "unused"  # Remove temporary ref_medication column
  )

# Log fill statistics
n_filled <- sum(detail_filled$drug_name_was_blank & !is.na(detail_filled$drug_name), na.rm = TRUE)
n_still_blank <- sum(is.na(detail_filled$drug_name) | detail_filled$drug_name == "")
message(glue("  Filled {n_filled} blank drug names from reference Excel"))
message(glue("  Still blank: {n_still_blank} (no matching triggering_code in reference)"))
```

### Pattern 3: Override Inconsistent Code Descriptions

**What:** For triggering_code_description values that disagree with reference Excel, replace with canonical value.

**When to use:** R/42 build_code_descriptions.R when building code_descriptions.rds.

**Example:**
```r
# R/42 currently builds from 4 sources (Phase 39 HCPCS, Phase 40 NDC, hardcoded radiation, config)
# Add reference Excel as highest-priority source (last in precedence chain)

# After existing 4 sources combined:
all_descriptions <- c(hcpcs_lookup, ndc_lookup, radiation_hardcoded, config_descriptions)

# Add reference Excel medication names (highest priority)
reference_descriptions <- MEDICATION_LOOKUP  # Built from reference Excel
all_descriptions <- c(all_descriptions, reference_descriptions)

# Deduplicate by keeping last occurrence (reference Excel wins)
all_descriptions <- all_descriptions[!duplicated(names(all_descriptions), fromLast = TRUE)]

message(glue("  Reference Excel overrode {sum(names(reference_descriptions) %in% names(hcpcs_lookup))} existing descriptions"))
```

### Pattern 4: Standalone Investigation Script with Before/After Audit

**What:** Separate R script that compares current drug_names/triggering_code_descriptions against reference Excel and produces two-sheet styled xlsx.

**When to use:** Phase 114 deliverable; runs once to document remediation impact.

**Example:**
```r
# R/6X_drug_name_consistency_audit.R (new script, following R/51, R/59 pattern)

# SECTION 1: Load current state
episodes <- readRDS(file.path(CONFIG$cache$outputs_dir, "treatment_episodes.rds"))
detail <- readRDS(file.path(CONFIG$cache$outputs_dir, "treatment_episode_detail.rds"))
code_descriptions <- readRDS(file.path(CONFIG$cache$outputs_dir, "code_descriptions.rds"))

# SECTION 2: Load reference Excel
MEDICATION_LOOKUP <- build_medication_lookup(REFERENCE_XLSX)

# SECTION 3: Identify blanks and inconsistencies
blank_analysis <- detail %>%
  filter(is.na(drug_name) | drug_name == "") %>%
  filter(!is.na(triggering_code) & triggering_code != "") %>%
  mutate(
    ref_medication = MEDICATION_LOOKUP[triggering_code],
    fillable = !is.na(ref_medication)
  )

inconsistent_analysis <- tibble(
  code = names(code_descriptions),
  current_description = code_descriptions
) %>%
  mutate(
    ref_medication = MEDICATION_LOOKUP[code],
    has_reference = !is.na(ref_medication),
    is_inconsistent = has_reference & current_description != ref_medication
  ) %>%
  filter(is_inconsistent)

# SECTION 4: Summary statistics
summary_stats <- tibble(
  metric = c(
    "Episodes with blank drug_names",
    "  - With triggering_codes in reference (fillable)",
    "  - Without triggering_codes in reference (unfillable)",
    "Code descriptions inconsistent with reference",
    "Total codes in reference Excel"
  ),
  count = c(
    sum(is.na(detail$drug_name) | detail$drug_name == ""),
    sum(blank_analysis$fillable),
    sum(!blank_analysis$fillable),
    nrow(inconsistent_analysis),
    length(MEDICATION_LOOKUP)
  )
)

# SECTION 5: Create styled xlsx (following R/51 pattern)
wb <- wb_workbook()

# Sheet 1: Summary
wb$add_worksheet("Summary")
wb$add_data(sheet = "Summary", x = "Drug Name Consistency Audit", start_row = 1, start_col = 1)
wb$add_font(sheet = "Summary", dims = "A1", name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937"))
wb$merge_cells(sheet = "Summary", dims = "A1:C1")

# Header row for summary table
wb$add_data(sheet = "Summary", x = summary_stats, start_row = 3, start_col = 1, with_filter = FALSE)
wb$add_fill(sheet = "Summary", dims = "A3:B3", color = wb_color("FF374151"))
wb$add_font(sheet = "Summary", dims = "A3:B3", name = "Calibri", size = 11, bold = TRUE, color = wb_color("white"))
wb$set_col_widths(sheet = "Summary", cols = 1:2, widths = c(50, 15))
wb$freeze_panes(sheet = "Summary", first_active_row = 4)

# Sheet 2: Detail
wb$add_worksheet("Detail")
detail_table <- bind_rows(
  blank_analysis %>%
    select(triggering_code, current_drug_name = drug_name, ref_medication, fillable) %>%
    mutate(issue_type = "blank_drug_name"),
  inconsistent_analysis %>%
    select(triggering_code = code, current_drug_name = current_description, ref_medication, has_reference) %>%
    mutate(issue_type = "inconsistent_description", fillable = has_reference)
)

wb$add_data(sheet = "Detail", x = detail_table, start_row = 1, start_col = 1, with_filter = TRUE)
wb$add_fill(sheet = "Detail", dims = "A1:E1", color = wb_color("FF374151"))
wb$add_font(sheet = "Detail", dims = "A1:E1", name = "Calibri", size = 11, bold = TRUE, color = wb_color("white"))
wb$set_col_widths(sheet = "Detail", cols = 1:5, widths = c(15, 30, 30, 12, 18))
wb$freeze_panes(sheet = "Detail", first_active_row = 2)

# Save
OUTPUT_XLSX <- file.path(CONFIG$output_dir, "drug_name_consistency_audit.xlsx")
wb$save(OUTPUT_XLSX)
message(glue("Audit xlsx saved: {OUTPUT_XLSX}"))
```

### Anti-Patterns to Avoid

- **Don't modify reference Excel during pipeline execution:** Reference Excel is read-only source of truth (D-04). Pipeline fixes align TO it, not the reverse.
- **Don't use RxNorm API as primary source:** RxNorm API is fallback for codes not in reference (R/27 pattern); reference Excel should be checked first for 454 known codes.
- **Don't aggregate before filling:** Fill blank drug_names at detail grain (R/26 treatment_episode_detail.rds) BEFORE aggregating to episodes. Aggregation loses the per-code mapping needed for reference lookup.
- **Don't hardcode medication names in R/00_config.R:** CODE_SUBCATEGORY_MAP in R/00_config.R is for sub-category labels (e.g., "IMRT", "Allogeneic"); medication names come from reference Excel column 3.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Excel lookup table reading | Custom XML parsing | openxlsx2 wb_load + wb_to_df | Already project standard; handles Excel formats, merged cells, formula evaluation |
| Filling missing values from lookup | Manual ifelse chains | dplyr left_join + coalesce | Standard pattern; handles multiple columns, preserves non-missing values |
| Before/after audit comparison | Text file diffs | Styled xlsx with summary + detail sheets | Project pattern (R/51, R/59); meeting-presentable format |
| String normalization | Custom regex | stringr str_to_title, str_trim | Handles edge cases (apostrophes, hyphens, Unicode) |

**Key insight:** This is a data alignment problem, not a data discovery problem. The reference Excel already contains the canonical medication names for all 454 treatment codes. Pipeline scripts should read it once at startup and use it as the primary lookup, with RxNorm API as fallback only for codes not in the reference.

## Common Pitfalls

### Pitfall 1: Column Index Brittleness

**What goes wrong:** Hardcoding `chemo_sheet[[3]]` for Medication column breaks if reference Excel columns are reordered.

**Why it happens:** wb_to_df returns unnamed list-like structure; column access by position is fragile.

**How to avoid:** Add column name verification after wb_to_df:
```r
chemo_sheet <- wb_to_df(ref_wb, sheet = "Chemotherapy", start_row = 2)
required_cols <- c("HCPCS.CPT.Code", "Medication")
if (!all(required_cols %in% names(chemo_sheet))) {
  stop(glue("[ERROR] Missing columns in Chemotherapy sheet: {paste(setdiff(required_cols, names(chemo_sheet)), collapse=', ')}"))
}
medication_col <- which(names(chemo_sheet) == "Medication")
code_col <- which(names(chemo_sheet) == "HCPCS.CPT.Code")
chemo_map <- setNames(as.character(chemo_sheet[[medication_col]]), as.character(chemo_sheet[[code_col]]))
```

**Warning signs:** Script fails with "subscript out of bounds" error after reference Excel is updated.

### Pitfall 2: Normalization Inconsistency Across Sources

**What goes wrong:** Reference Excel has "Doxorubicin HCl", RxNorm API returns "doxorubicin hydrochloride", R/00_config.R has "Doxorubicin" — coalesce doesn't recognize them as the same drug.

**Why it happens:** Different sources use different capitalization, chemical name variants, abbreviations.

**How to avoid:** Apply consistent normalization to ALL sources before comparison:
```r
normalize_drug_name <- function(name) {
  if (is.na(name) || name == "") return(NA_character_)

  name %>%
    str_trim() %>%
    str_to_title() %>%
    str_replace_all("Hcl$", "HCl") %>%  # Preserve common abbreviations
    str_replace_all("\\s+", " ")  # Collapse multiple spaces
}

# Apply to all sources
MEDICATION_LOOKUP <- sapply(MEDICATION_LOOKUP, normalize_drug_name)
detail$drug_name <- sapply(detail$drug_name, normalize_drug_name)
```

**Warning signs:** Audit shows "inconsistencies" for drugs that are actually the same with different capitalization.

### Pitfall 3: Triggering Codes vs Individual Codes Mismatch

**What goes wrong:** Episodes have `triggering_codes = "J9000,J9040,J9360"` (comma-separated), lookup expects single code.

**Why it happens:** R/26 aggregates multiple codes per episode; reference Excel maps individual codes.

**How to avoid:** Fill at detail grain (one row per code) BEFORE aggregation to episode grain:
```r
# CORRECT ORDER (R/26 treatment_episodes.R):
# 1. Load treatment_episode_detail (one row per patient+date+code)
# 2. Join drug_name_lookup.rds (existing RxNorm)
# 3. Fill blanks from reference Excel (NEW — this phase)
# 4. Aggregate to episode grain with paste(sort(unique(drug_name)), collapse = ",")

# INCORRECT ORDER (don't do this):
# 1. Aggregate to episode grain first
# 2. Try to fill from reference Excel (fails because triggering_codes is multi-valued)
```

**Warning signs:** Fill count is unexpectedly low; manual inspection shows blank episodes with valid J-codes.

### Pitfall 4: Reference Excel as Runtime Dependency

**What goes wrong:** Every script that needs medication names reads the reference Excel independently, slowing pipeline startup.

**Why it happens:** Copying the R/57 pattern (load reference in each script) instead of centralizing.

**How to avoid:** Build MEDICATION_LOOKUP once in R/00_config.R and reuse:
```r
# R/00_config.R (add after DRUG_GROUPINGS definition)
MEDICATION_LOOKUP <- local({
  REFERENCE_XLSX <- "data/reference/all_codes_resolved_next_tables_v2.1.xlsx"

  if (!file.exists(REFERENCE_XLSX)) {
    warning(glue("Reference Excel not found: {REFERENCE_XLSX}. MEDICATION_LOOKUP will be empty."))
    return(setNames(character(0), character(0)))
  }

  ref_wb <- wb_load(REFERENCE_XLSX)

  # Extract from all 5 sheets (code in Architecture Pattern 1)
  chemo_sheet <- wb_to_df(ref_wb, sheet = "Chemotherapy", start_row = 2)
  chemo_map <- setNames(as.character(chemo_sheet[[3]]), as.character(chemo_sheet[[1]]))
  # ... (repeat for other 4 sheets)

  all_medications <- c(chemo_map, rad_map, sct_map, immuno_map, support_map)
  all_medications <- all_medications[!is.na(names(all_medications)) & !is.na(all_medications)]
  all_medications <- sapply(all_medications, normalize_drug_name)

  return(all_medications)
})

message(glue("  MEDICATION_LOOKUP initialized: {length(MEDICATION_LOOKUP)} medications from reference Excel"))
```

**Warning signs:** Pipeline startup takes 10+ seconds due to repeated Excel reading.

## Code Examples

Verified patterns from project codebase:

### Reading Reference Excel (Existing Pattern)
```r
# Source: R/57 lines 136-159, R/36 lines 269-271
REFERENCE_XLSX <- "data/reference/all_codes_resolved_next_tables_v2.1.xlsx"
ref_wb <- wb_load(REFERENCE_XLSX)

# Chemotherapy sheet
chemo_sheet <- wb_to_df(ref_wb, sheet = "Chemotherapy", start_row = 2)
chemo_map <- setNames(as.character(chemo_sheet[[3]]), as.character(chemo_sheet[[1]]))
chemo_map <- chemo_map[!is.na(names(chemo_map)) & !is.na(chemo_map)]

# Radiation sheet
rad_sheet <- wb_to_df(ref_wb, sheet = "Radiation", start_row = 2)
rad_map <- setNames(as.character(rad_sheet[[7]]), as.character(rad_sheet[[1]]))  # Column 7 for type, not medication
rad_map <- rad_map[!is.na(names(rad_map)) & !is.na(rad_map)]

# SCT sheet
sct_sheet <- wb_to_df(ref_wb, sheet = "SCT", start_row = 2)
sct_map <- setNames(as.character(sct_sheet[[7]]), as.character(sct_sheet[[1]]))  # Column 7 for type, not medication
sct_map <- sct_map[!is.na(names(sct_map)) & !is.na(sct_map)]
```

### Filling Blank Drug Names (New Pattern)
```r
# Source: Adapted from dplyr coalesce join best practices
# https://www.spsanderson.com/steveondata/posts/2025-02-17/
# https://www.asterhu.com/post/2023-05-11-coalesce-join-in-r/

fill_blank_drug_names <- function(detail_df, medication_lookup) {
  # Build lookup tibble
  medication_ref <- tibble(
    triggering_code = names(medication_lookup),
    ref_medication = medication_lookup
  )

  # Track which rows were blank before fill
  detail_filled <- detail_df %>%
    mutate(was_blank = is.na(drug_name) | drug_name == "") %>%
    left_join(medication_ref, by = "triggering_code") %>%
    mutate(
      drug_name = coalesce(drug_name, ref_medication)
    ) %>%
    select(-ref_medication)  # Remove temporary column

  # Log fill statistics
  n_filled <- sum(detail_filled$was_blank & !is.na(detail_filled$drug_name), na.rm = TRUE)
  n_still_blank <- sum(is.na(detail_filled$drug_name) | detail_filled$drug_name == "", na.rm = TRUE)

  message(glue("  Filled {n_filled} blank drug names from reference Excel"))
  message(glue("  Still blank: {n_still_blank}"))

  detail_filled %>% select(-was_blank)
}

# Usage in R/26
all_detail <- fill_blank_drug_names(all_detail, MEDICATION_LOOKUP)
```

### Styled XLSX Output (Existing Pattern)
```r
# Source: R/51 lines 283-298 (post-death investigation pattern)
wb <- wb_workbook()
wb$add_worksheet("Summary")

# Title row
wb$add_data(sheet = "Summary", x = "Drug Name Consistency Audit", start_row = 1, start_col = 1)
wb$add_font(sheet = "Summary", dims = "A1", name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937"))
wb$merge_cells(sheet = "Summary", dims = "A1:C1")

# Data table with styled header
wb$add_data(sheet = "Summary", x = summary_table, start_row = 3, start_col = 1, with_filter = FALSE)
wb$add_fill(sheet = "Summary", dims = "A3:B3", color = wb_color("FF374151"))  # Dark gray
wb$add_font(sheet = "Summary", dims = "A3:B3", name = "Calibri", size = 11, bold = TRUE, color = wb_color("white"))
wb$set_col_widths(sheet = "Summary", cols = 1:2, widths = c(50, 15))
wb$freeze_panes(sheet = "Summary", first_active_row = 4)

# Save
wb$save(file.path(CONFIG$output_dir, "drug_name_consistency_audit.xlsx"))
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| RxNorm API only | Reference Excel + RxNorm fallback | Phase 114 (this phase) | Medication names for 454 known codes come from authoritative source; RxNorm used only for unlisted codes |
| Four-source code descriptions precedence | Five-source with reference Excel highest priority | Phase 114 (this phase) | Reference Excel medication names override API results, ensuring consistency |
| Manual ifelse for missing value fill | dplyr coalesce join | Best practice 2025+ | Standard pattern; cleaner, more maintainable |

**Deprecated/outdated:**
- Reading reference Excel in every script independently (R/57, R/36, R/56, R/58 pattern) → should centralize in R/00_config.R as MEDICATION_LOOKUP for performance
- Hardcoded medication names in R/00_config.R CODE_SUBCATEGORY_MAP for chemotherapy codes → should come from reference Excel Medication column instead

## Open Questions

1. **Which normalization level for medication names?**
   - What we know: Reference Excel has varied capitalization (e.g., "Doxorubicin HCl", "RITUXIMAB", "bleomycin sulfate")
   - What's unclear: Should we preserve exact capitalization or normalize to title case for consistency?
   - Recommendation: Apply str_to_title normalization to all sources (reference Excel, RxNorm API, R/00_config.R) for consistency, but preserve known abbreviations (HCl, IV, PO) via targeted str_replace_all. Document normalization choices in audit script output.

2. **Should CODE_SUBCATEGORY_MAP be updated or replaced?**
   - What we know: R/00_config.R CODE_SUBCATEGORY_MAP (extracted Phase 77) has medication names for some codes; reference Excel Medication column also has medication names
   - What's unclear: Do we keep CODE_SUBCATEGORY_MAP for backward compatibility or merge it into MEDICATION_LOOKUP?
   - Recommendation: Keep CODE_SUBCATEGORY_MAP for non-medication sub-categories (e.g., radiation "IMRT" vs "Proton Therapy", SCT "Allogeneic" vs "Autologous"). Create new MEDICATION_LOOKUP specifically for drug names from reference Excel column 3. These serve different purposes.

3. **How to handle codes in pipeline but not in reference Excel?**
   - What we know: DRUG_GROUPINGS has 454 codes; pipeline may encounter additional codes from patient data not in reference
   - What's unclear: Should these trigger warnings or silently fall back to RxNorm API?
   - Recommendation: Log at INFO level (not WARNING) when a code uses RxNorm API fallback. This is expected behavior for investigational drugs or newly approved codes not yet in reference Excel. Audit script should report counts of "filled from reference" vs "filled from RxNorm" vs "unfillable".

## Environment Availability

Phase 114 has no external dependencies beyond the project's existing R packages and reference data files. All required tools (openxlsx2, dplyr, stringr) are already installed in project renv.

**SKIPPED:** No external services, APIs, or CLI tools required. This is a pure R code/data modification phase using existing project infrastructure.

## Sources

### Primary (HIGH confidence)

- R/27_drug_name_resolution.R - Current RxNorm API-based drug name resolution implementation
- R/42_build_code_descriptions.R - Four-source code description precedence chain
- R/26_treatment_episodes.R lines 706-719 - Episode-level drug_name aggregation from detail grain
- R/28_episode_classification.R lines 294-306, 365-382 - Drug name usage in regimen detection and J-code fallback
- R/57_drug_grouping_instances.R lines 140-159 - Reference Excel reading pattern (Medication column extraction)
- R/36_tableau_ready_tables.R lines 269-271 - Reference Excel reading pattern (Medication column)
- R/51_post_death_encounter_investigation.R lines 283-298 - Styled XLSX output pattern
- R/00_config.R lines 1371-1901 - DRUG_GROUPINGS named vector (454 treatment codes)
- 114-CONTEXT.md - User decisions and phase constraints

### Secondary (MEDIUM confidence)

- [How to Replace Values in Data Frame Based on Lookup Table in R](https://www.spsanderson.com/steveondata/posts/2025-02-17/) - dplyr left_join best practices for value replacement
- [Replace missing value from other columns using coalesce join in dplyr](https://www.asterhu.com/post/2023-05-11-coalesce-join-in-r/) - Coalesce join pattern for filling missing values
- [R-bloggers: Replace missing value using coalesce join](https://www.r-bloggers.com/2023/05/replace-missing-value-from-other-columns-using-coalesce-join-in-dplyr/) - Additional coalesce join examples
- [openxlsx2 CRAN documentation](https://cran.r-project.org/web/packages/openxlsx2/openxlsx2.pdf) - Official package reference (May 2026)
- [openxlsx2 GitHub repository](https://github.com/JanMarvin/openxlsx2) - Modern rewrite with pipes support
- [pointblank: Data Validation and Quality Control for R](https://medium.com/r-evolution/pointblank-data-validation-and-quality-control-for-r-67ce1c73f4fc) - Data quality validation patterns (optional for deep validation)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All libraries already in project renv; openxlsx2 pattern verified in 6+ scripts
- Architecture: HIGH - Reference Excel structure verified in R/57, R/36, R/56, R/58; coalesce join pattern is dplyr best practice
- Pitfalls: HIGH - Based on common R data quality issues (column index brittleness, normalization inconsistency, grain mismatch)

**Research date:** 2026-06-24
**Valid until:** 2026-08-24 (60 days for stable stack; R package ecosystem changes slowly)
