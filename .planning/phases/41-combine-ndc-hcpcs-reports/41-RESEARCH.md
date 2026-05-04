# Phase 41: Combine NDC and HCPCS Reports - Research

**Researched:** 2026-05-04
**Domain:** R data report consolidation (openxlsx2 styled workbook merging)
**Confidence:** HIGH

## Summary

Phase 41 combines two existing investigation reports into a single consolidated xlsx workbook. Phase 39 produced `output/unmatched_codes_report.xlsx` (CPT/HCPCS unmatched codes from PROCEDURES table) and Phase 40 produced `output/unmatched_ndc_report.xlsx` (NDC/RXNORM unmatched codes from DISPENSING, PRESCRIBING, MED_ADMIN tables). Both use the same openxlsx2 styling pattern established in Phase 38: dark gray header rows, treatment-type colored "pill" cells for codes, frozen panes, and comma-formatted numerics.

The combined report should read both RDS artifacts (`unmatched_codes_classified.rds` and `unmatched_ndc_classified.rds`), unify the classification scheme (resolving the "SCT" vs "SCT-related" naming difference), produce a cross-source summary sheet, per-category detail sheets with a unified column set, and a source breakdown view. This is a pure data-merging and report-generation task with no external API calls or data extraction needed.

**Primary recommendation:** Create a standalone `R/41_combine_reports.R` script that reads the two existing RDS artifacts, harmonizes column schemas, and produces a single `output/combined_unmatched_report.xlsx` workbook using the bulk-write openxlsx2 pattern from Phase 40 (not Phase 39's cell-by-cell loop).

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| openxlsx2 | 1.10+ | xlsx workbook generation | Already used in Phases 38-40; provides wb_workbook API for styled output |
| dplyr | 1.2.0+ | Data transformation | bind_rows, mutate, group_by/summarise for merging datasets |
| glue | 1.8.0 | String interpolation | Consistent messaging and dynamic cell references |
| stringr | 1.5.1+ | String operations | str_detect for category matching if needed |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| tidyr | 1.3.0+ | Data reshaping | pivot_wider for cross-tabulation views if needed |

**Installation:** All packages already installed in project environment (used by Phases 38-40).

## Architecture Patterns

### Recommended Script Structure
```
R/41_combine_reports.R
  SECTION 1: Setup and Configuration (source config, load libs)
  SECTION 2: Load and Harmonize RDS Artifacts
  SECTION 3: Write Combined xlsx Report
  SECTION 4: Main Execution
```

### Pattern 1: RDS Artifact Loading and Schema Harmonization

**What:** Load both classified RDS files and unify column schemas into a single tibble.

**When to use:** When merging datasets with overlapping but non-identical columns.

**Key insight:** The two RDS artifacts have different column schemas:

Phase 39 (`unmatched_codes_classified.rds`):
| Column | Type | Description |
|--------|------|-------------|
| code | character | CPT/HCPCS code |
| n_records | integer | Record count |
| n_patients | integer | Patient count |
| heuristic_type | character | Which heuristic matched |
| description | character | From NLM HCPCS API |
| lookup_status | character | API result status |
| classification | character | Auto-assigned category |

Phase 40 (`unmatched_ndc_classified.rds`):
| Column | Type | Description |
|--------|------|-------------|
| code | character | NDC or RXNORM code |
| code_type | character | "NDC" or "RXNORM" |
| source_table | character | DISPENSING/PRESCRIBING/MED_ADMIN |
| n_records | integer | Record count |
| n_patients | integer | Patient count |
| raw_drug_name | character | From PCORnet table |
| drug_name | character | From RxNorm API (or raw fallback) |
| lookup_status | character | API result status |
| classification | character | Auto-assigned category |

**Unified schema for combined report:**
| Column | Source | Notes |
|--------|--------|-------|
| code | Both | The code value |
| code_type | Phase 40 has it; Phase 39 = "CPT/HCPCS" | Add to Phase 39 data |
| description | Phase 39 = description; Phase 40 = drug_name | Unify as "description" |
| source_table | Phase 40 has it; Phase 39 = "PROCEDURES" | Add to Phase 39 data |
| n_records | Both | Same meaning |
| n_patients | Both | Same meaning |
| classification | Both | Harmonize "SCT" vs "SCT-related" |
| heuristic_type | Phase 39 only | Keep as optional column (NA for Phase 40) |
| lookup_status | Both | Same meaning |

### Pattern 2: Classification Harmonization

**What:** Phase 39 uses "SCT" while Phase 40 uses "SCT-related". The combined report must use one consistent label.

**Recommendation:** Use "SCT" as the canonical label (shorter, matches the config vector naming `sct_cpt`, `sct_icd9`, etc.). Remap Phase 40's "SCT-related" to "SCT" during harmonization.

**Category order for combined report:**
1. Chemotherapy
2. Radiation
3. SCT (unified from "SCT" + "SCT-related")
4. Immunotherapy
5. Supportive Care
6. Unrelated

### Pattern 3: Bulk Write xlsx (Phase 40 Optimized Pattern)

**What:** Phase 40 introduced a bulk-write pattern using `wb$add_data(x = write_df, col_names = FALSE)` and range-based styling instead of Phase 39's cell-by-cell loop.

**Why:** Phase 39's cell-by-cell loop is O(n*cols) write calls. Phase 40's bulk write is O(1) data write + O(categories) style calls. For a combined report with potentially hundreds of codes, this matters.

**Use Phase 40's pattern exclusively.**

### Anti-Patterns to Avoid
- **Cell-by-cell writing:** Do not replicate Phase 39's for-loop data writing. Use Phase 40's bulk write pattern.
- **Re-running API lookups:** All data already exists in the RDS artifacts. Do not call NLM or RxNorm APIs.
- **Modifying existing reports:** The combined report is an ADDITIONAL output, not a replacement. Individual reports remain useful for focused review.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| xlsx styling | Custom CSS/HTML export | openxlsx2 wb_workbook API | Already established pattern in Phases 38-40 |
| Data merge | Manual column matching | dplyr::bind_rows with mutate harmonization | Handles NA fill for missing columns automatically |
| Color palette | New color definitions | Existing TREATMENT_TYPE_COLORS | Already defined and used consistently |

## Common Pitfalls

### Pitfall 1: SCT vs SCT-related Naming Mismatch
**What goes wrong:** If left unharmonized, the combined report has both "SCT" (from Phase 39) and "SCT-related" (from Phase 40) as separate categories, splitting what should be one group.
**Why it happens:** Phase 40 chose "SCT-related" to indicate drugs associated with transplant (conditioning regimens) vs actual transplant procedure codes.
**How to avoid:** Remap "SCT-related" to "SCT" before any grouping/summarization.
**Warning signs:** 7 categories appearing in summary instead of 6.

### Pitfall 2: TREATMENT_TYPE_COLORS Key Mismatch
**What goes wrong:** `TREATMENT_TYPE_COLORS[["SCT"]]` works in Phase 39 but Phase 40 uses `TREATMENT_TYPE_COLORS[["SCT-related"]]`. The combined script must use the correct key.
**Why it happens:** Color palette keys differ between Phase 39 and Phase 40 scripts.
**How to avoid:** Define a fresh TREATMENT_TYPE_COLORS in the combined script with "SCT" as the key (matching the unified classification). Copy the yellow/dark olive colors.
**Warning signs:** NULL fill/font color causing white-on-white text.

### Pitfall 3: Duplicate Codes Across Sources
**What goes wrong:** The same RXNORM CUI might appear in both DISPENSING and PRESCRIBING in Phase 40's output. When computing summary statistics, codes could be double-counted.
**Why it happens:** Phase 40 groups by (code, source_table), not by code alone.
**How to avoid:** For the unified summary, count distinct codes (not rows). For per-source views, show all rows. Document both perspectives clearly.
**Warning signs:** "Total unique codes" != sum of per-source code counts.

### Pitfall 4: RDS File Not Found on Fresh Clone
**What goes wrong:** Script fails because RDS artifacts don't exist (they're generated by running scripts on HiPerGator).
**Why it happens:** RDS files are in output/ which may be gitignored or not yet generated.
**How to avoid:** Add clear error messages if RDS files don't exist, with instructions to run Phase 39 and 40 scripts first.
**Warning signs:** "Error: file not found" on first run.

## Code Examples

### Loading and Harmonizing RDS Artifacts
```r
# Load Phase 39 classified codes (CPT/HCPCS)
hcpcs_classified <- readRDS(file.path(CONFIG$output_dir, "unmatched_codes_classified.rds"))

# Load Phase 40 classified codes (NDC/RXNORM)
ndc_classified <- readRDS(file.path(CONFIG$output_dir, "unmatched_ndc_classified.rds"))

# Harmonize Phase 39 schema to unified format
hcpcs_harmonized <- hcpcs_classified %>%
  mutate(
    code_type = "CPT/HCPCS",
    source_table = "PROCEDURES",
    description = description  # already named correctly
  ) %>%
  select(code, code_type, source_table, description, n_records, n_patients,
         classification, heuristic_type, lookup_status)

# Harmonize Phase 40 schema
ndc_harmonized <- ndc_classified %>%
  mutate(
    description = drug_name,  # rename for consistency
    heuristic_type = NA_character_,  # not applicable to drug codes
    classification = if_else(classification == "SCT-related", "SCT", classification)
  ) %>%
  select(code, code_type, source_table, description, n_records, n_patients,
         classification, heuristic_type, lookup_status)

# Combine
all_codes <- bind_rows(hcpcs_harmonized, ndc_harmonized)
```

### Summary Sheet Structure
```r
# Combined summary by classification
summary_by_class <- all_codes %>%
  group_by(classification) %>%
  summarise(
    n_codes = n_distinct(code),
    n_records = sum(n_records),
    n_patients = sum(n_patients),
    .groups = "drop"
  ) %>%
  arrange(match(classification, category_order))

# Summary by code type
summary_by_type <- all_codes %>%
  group_by(code_type) %>%
  summarise(
    n_codes = n_distinct(code),
    n_records = sum(n_records),
    .groups = "drop"
  )

# Summary by source table
summary_by_source <- all_codes %>%
  group_by(source_table) %>%
  summarise(
    n_codes = n_distinct(code),
    n_records = sum(n_records),
    .groups = "drop"
  )
```

### Bulk Data Write Pattern (from Phase 40)
```r
# Prepare data frame for bulk write
write_df <- data.frame(
  Code = df_cat$code,
  Description = ifelse(is.na(df_cat$description), "", df_cat$description),
  Code_Type = df_cat$code_type,
  Source_Table = df_cat$source_table,
  Records = df_cat$n_records,
  Patients = df_cat$n_patients,
  Lookup_Status = df_cat$lookup_status,
  stringsAsFactors = FALSE
)
wb$add_data(sheet = sheet_name, x = write_df, start_row = 5, col_names = FALSE)

# Apply styles to entire ranges at once
last_row <- 4 + nrow(df_cat)
code_dims <- glue("A5:A{last_row}")
wb$add_fill(sheet = sheet_name, dims = code_dims, color = wb_color(fill_color))
wb$add_font(sheet = sheet_name, dims = code_dims,
            name = "Calibri", size = 10, bold = TRUE, color = wb_color(font_color))
```

## Report Structure Recommendation

### Sheet Layout for Combined Report

1. **Summary** - Overall statistics with three sections:
   - By Classification (6 rows): codes, records, patients per category
   - By Code Type (3 rows): CPT/HCPCS, NDC, RXNORM
   - By Source Table (4 rows): PROCEDURES, DISPENSING, PRESCRIBING, MED_ADMIN

2. **Chemotherapy** - All chemo codes across all code types/sources
3. **Radiation** - All radiation codes
4. **SCT** - All SCT/transplant-related codes
5. **Immunotherapy** - All immunotherapy codes
6. **Supportive Care** - All supportive care codes
7. **Unrelated** - All unrelated codes

### Per-Category Sheet Columns

| Column | Width | Description |
|--------|-------|-------------|
| Code | 15 | The code value |
| Description | 45 | Drug name or procedure description |
| Code Type | 12 | CPT/HCPCS, NDC, or RXNORM |
| Source Table | 15 | Which PCORnet table |
| Records | 10 | Number of records |
| Patients | 10 | Distinct patient count |
| Lookup Status | 15 | API lookup result |

### Naming Convention

- Script: `R/41_combine_reports.R`
- Output: `output/combined_unmatched_report.xlsx`
- The individual reports remain: `output/unmatched_codes_report.xlsx` and `output/unmatched_ndc_report.xlsx`

## State of the Art

| Old Approach (Phase 39) | Current Approach (Phase 40) | Impact |
|--------------------------|------------------------------|--------|
| Cell-by-cell writing | Bulk data.frame write + range styling | 10-100x fewer openxlsx2 API calls |
| httr (legacy) | httr2 (modern) | Not relevant here (no API calls) |

## Open Questions

1. **Should "Unrelated" codes be included in the combined report?**
   - What we know: Both reports include Unrelated codes. They constitute the majority of codes (especially NDC where most drugs are unrelated to HL treatment).
   - What's unclear: Whether the combined report should include them (useful for completeness) or omit them (cleaner focus on treatment-relevant codes).
   - Recommendation: Include them but on the last sheet. The summary will show their proportion.

2. **Should patient counts be deduplicated across sources?**
   - What we know: The same patient could appear in both PROCEDURES and DISPENSING. Simple sum of n_patients across code types will overcount.
   - What's unclear: Whether the RDS artifacts contain patient IDs (they don't -- only n_patients aggregates).
   - Recommendation: Sum n_patients within each source/category but note in the summary that cross-source patient totals may include duplicates. This is an inherent limitation of working from aggregated RDS artifacts.

## Project Constraints (from CLAUDE.md)

- **Runtime environment:** RStudio on UF HiPerGator
- **R packages:** tidyverse ecosystem; openxlsx2 for xlsx output
- **Code style:** Named predicates not required here (this is report generation, not cohort filtering)
- **Data access:** RDS artifacts from previous phase outputs
- **Payer fidelity:** Not applicable to this phase (no payer analysis)

## Sources

### Primary (HIGH confidence)
- `R/39_investigate_unmatched.R` - Phase 39 script with HCPCS report generation (789 lines)
- `R/40_investigate_unmatched_ndc.R` - Phase 40 script with NDC report generation (1064 lines)
- `R/00_config.R` - Config with TREATMENT_CODES structure (952 lines)
- Phase 39 and 40 SUMMARY.md files - Confirmed outputs, decisions, patterns

### Secondary (MEDIUM confidence)
- openxlsx2 package documentation - bulk write patterns

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All packages already used in project
- Architecture: HIGH - Direct extension of established Phase 38-40 patterns
- Pitfalls: HIGH - Derived from actual code review of both scripts

**Research date:** 2026-05-04
**Valid until:** 2026-06-04 (stable -- no external dependencies changing)
