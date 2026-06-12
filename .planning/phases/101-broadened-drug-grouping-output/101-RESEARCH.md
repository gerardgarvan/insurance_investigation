# Phase 101: Broadened Drug Grouping Output - Research

**Researched:** 2026-06-12
**Domain:** R output expansion, data filtering logic modification, multi-file output strategy
**Confidence:** HIGH

## Summary

Phase 101 expands R/57 drug grouping instances output to include ALL treatment encounters (not just cancer-linked) with a new `cancer_linked` TRUE/FALSE flag column, preserving the existing cancer-linked-only output as a separate file. The phase adds a linked-vs-unlinked cross-tab summary sheet showing treatment type distributions. R/56 episode-level summaries remain unchanged (cancer-linked-only).

The technical challenge is minimal: R/57 already joins DIAGNOSIS per encounter in Section 4 (lines 148-260) and derives `cancer_codes` and `cancer_category_names` per encounter. The broadened output removes the `filter(!is.na(cancer_category_names))` filter from Table 1 (line 375) and Table 2 (line 399), adds a `cancer_linked` column derived from `!is.na(cancer_codes)`, and creates a cross-tab summary by treatment_type. The existing reference code filter (lines 280-284: valid_reference_codes OR Immunotherapy) stays in place for both outputs.

Phase 100's completion (CONDITION table cancer linkage improvement) means the `cancer_linked` flag benefits from improved linkage accuracy—fewer false-negatives where treatment encounters lacked cancer diagnosis codes due to DIAGNOSIS-only linkage.

**Primary recommendation:** Modify R/57 in-place to generate both outputs (broadened primary, linked-only preserved) in Section 7 after Table 1 and Table 2 creation. Use openxlsx2 multi-sheet pattern (already present) to create 3-sheet broadened file and 2-sheet linked-only file. Add cross-tab summary via `group_by(treatment_type) %>% summarise()` aggregation.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Scope of Broadening**
- **D-01:** R/57 only. R/56 episode-level summaries stay unchanged (cancer-linked-only).
- **D-02:** Only the `filter(!is.na(cancer_category_names))` filter is removed for the broadened output. The existing reference code filter (valid_reference_codes OR Immunotherapy) stays in place.

**cancer_linked Flag**
- **D-03:** cancer_linked derived from encounter-level DX presence — the existing R/57 logic that joins DuckDB DIAGNOSIS data per encounter and checks for cancer codes. TRUE when encounter has cancer diagnosis codes, FALSE otherwise.
- **D-04:** Self-contained within R/57, no dependency change on R/28's cancer_category column.

**Cross-Tab Summary**
- **D-05:** Simple 3-column table: treatment_type | linked_count | unlinked_count. One row per treatment type (Chemo, RT, SCT, Immuno, Proton).
- **D-06:** Cross-tab lives as 3rd sheet in the broadened xlsx (named "Linked vs Unlinked Summary" or similar within 31-char Excel limit).

**Output File Strategy**
- **D-07:** Broadened output becomes the primary file: `drug_grouping_instances.xlsx` (backward compat) and `encounter_level_drug_grouping_instances.xlsx` (grain-labeled).
- **D-08:** Cancer-linked-only output preserved with `_linked_only` suffix: `drug_grouping_instances_linked_only.xlsx` (backward compat) and `encounter_level_drug_grouping_instances_linked_only.xlsx` (grain-labeled).
- **D-09:** Broadened file has 3 sheets (Sub-Category Detail, Treatment Detail, Linked vs Unlinked Summary). Linked-only file keeps exact current 2-sheet structure.

### Claude's Discretion
- Sheet naming within 31-char Excel limit
- Column ordering for cancer_linked flag (last column or positioned contextually)
- Smoke test (R/88) validation section additions for broadened output

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope.

</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| DRUG-01 | drug_grouping_instances output includes ALL treatment encounters regardless of cancer diagnosis linkage (broadened from cancer-linked-only) | Remove `filter(!is.na(cancer_category_names))` from Table 1 (line 375) and Table 2 (line 399); reference code filter remains |
| DRUG-02 | Flag column indicating whether each encounter has a linked cancer diagnosis (cancer_linked = TRUE/FALSE) | Derive from existing `cancer_codes` column: `mutate(cancer_linked = !is.na(cancer_codes))` |
| DRUG-03 | Existing cancer-linked-only output preserved alongside broadened version (no breaking change) | Dual-output pattern: create both broadened and linked-only variants using filtered/unfiltered Table 1 and Table 2 |

</phase_requirements>

## Standard Stack

### Core (Already Installed)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| dplyr | 1.2.0+ | Data transformation | Project standard; already used throughout R/57 |
| tidyr | 1.3.1+ | Data reshaping | Already loaded in R/57 Section 1 |
| glue | 1.8.0+ | String formatting | Console logging messages |
| stringr | 1.5.1+ | String operations | Already used for code normalization |
| openxlsx2 | 1.10+ | Multi-sheet xlsx output | Already used in R/57 Section 7; supports multi-sheet workbooks |

**No new packages required** — Phase 101 uses existing R/57 infrastructure.

## Architecture Patterns

### Recommended Script Structure (R/57 Modifications)
```
R/57_drug_grouping_instances.R

SECTION 5: TABLE 1 -- SUB-CATEGORY ENCOUNTER DETAIL
  - NO CHANGE to filtering logic
  - Remove filter(!is.na(cancer_category_names)) — create table1_all
  - Add cancer_linked column: mutate(cancer_linked = !is.na(cancer_codes))
  - Create table1_linked (filtered version for backward compat)

SECTION 6: TABLE 2 -- ENCOUNTER TREATMENT CODE DETAIL
  - NO CHANGE to filtering logic
  - Remove filter(!is.na(cancer_category_names)) — create table2_all
  - Add cancer_linked column: mutate(cancer_linked = !is.na(cancer_codes))
  - Create table2_linked (filtered version for backward compat)

SECTION 6B: CROSS-TAB SUMMARY (NEW)
  - Aggregate table1_all by treatment_category
  - Group by treatment_category, cancer_linked
  - Count rows per group
  - Pivot to wide format (treatment_type | linked_count | unlinked_count)

SECTION 7: WRITE XLSX OUTPUT
  - Create broadened workbook (3 sheets):
    * Sheet 1: "Enc: Sub-Category Detail" (table1_all)
    * Sheet 2: "Enc: Treatment Detail" (table2_all)
    * Sheet 3: "Linked vs Unlinked" (cross-tab summary)
  - Save to NEW_OUTPUT_XLSX and OLD_OUTPUT_XLSX

  - Create linked-only workbook (2 sheets):
    * Sheet 1: "Enc: Sub-Category Detail" (table1_linked)
    * Sheet 2: "Enc: Treatment Detail" (table2_linked)
  - Save to NEW_OUTPUT_LINKED_XLSX and OLD_OUTPUT_LINKED_XLSX

SECTION 8: CONSOLE SUMMARY
  - Update to report both outputs
  - Log broadened vs linked-only row counts
  - Log cross-tab summary for verification
```

### Pattern 1: Dual-Output Generation (Broadened + Linked-Only)
**What:** Create both filtered and unfiltered versions of Table 1 and Table 2
**When to use:** When preserving backward-compatible output alongside expanded output
**Example:**
```r
# Source: R/57 Section 5 pattern (lines 373-383), modified for dual-output

# Table 1: Sub-Category Detail (ALL encounters)
table1_all <- detail_codes %>%
  # Reference filter still applies (D-02)
  group_by(patient_id, ENCOUNTERID, treatment_date, treatment_type,
           cancer_codes, cancer_category_names) %>%
  summarise(
    sub_category_names = paste(sort(unique(sub_category)), collapse = ";"),
    .groups = "drop"
  ) %>%
  mutate(cancer_linked = !is.na(cancer_codes)) %>%  # D-03: derive from cancer_codes
  select(patient_id, ENCOUNTERID, treatment_date, treatment_category = treatment_type,
         sub_category_names, cancer_category_names, cancer_linked) %>%
  arrange(patient_id, treatment_date, treatment_category)

# Table 1: Linked-only (backward compatibility)
table1_linked <- table1_all %>%
  filter(!is.na(cancer_category_names))  # Original filter logic

message(glue("  Table 1 (all): {nrow(table1_all)} rows"))
message(glue("  Table 1 (linked-only): {nrow(table1_linked)} rows"))
```

### Pattern 2: Cross-Tab Summary Generation
**What:** Aggregate treatment encounters by treatment_type and cancer_linked flag
**When to use:** Producing linked-vs-unlinked count summaries (D-05, D-06)
**Example:**
```r
# Source: dplyr group_by + summarise pattern, pivot_wider for cross-tab

# Compute cross-tab: treatment_type x cancer_linked counts
crosstab_summary <- table1_all %>%
  group_by(treatment_category, cancer_linked) %>%
  summarise(n = n(), .groups = "drop") %>%
  tidyr::pivot_wider(
    names_from = cancer_linked,
    values_from = n,
    values_fill = 0
  ) %>%
  rename(
    treatment_type = treatment_category,
    unlinked_count = `FALSE`,
    linked_count = `TRUE`
  ) %>%
  select(treatment_type, linked_count, unlinked_count) %>%
  arrange(desc(linked_count))

message(glue("  Cross-tab summary: {nrow(crosstab_summary)} treatment types"))
```

### Pattern 3: Multi-Sheet Workbook with Suffix Variants
**What:** Create two separate workbooks (broadened 3-sheet, linked-only 2-sheet) with dual naming
**When to use:** Implementing D-07, D-08, D-09 output file strategy
**Example:**
```r
# Source: R/57 Section 7 (lines 416-437), extended for dual-workbook pattern

# --- Broadened output (3 sheets) ---
wb_broad <- wb_workbook()

# Sheet 1: Sub-Category Detail (all encounters)
wb_broad$add_worksheet("Enc: Sub-Category Detail")
wb_broad$add_data("Enc: Sub-Category Detail", table1_all, start_row = 1, col_names = TRUE)

# Sheet 2: Treatment Detail (all encounters)
wb_broad$add_worksheet("Enc: Treatment Detail")
wb_broad$add_data("Enc: Treatment Detail", table2_all, start_row = 1, col_names = TRUE)

# Sheet 3: Linked vs Unlinked Summary (NEW per D-06)
wb_broad$add_worksheet("Linked vs Unlinked")  # 18 chars, fits 31-char limit
wb_broad$add_data("Linked vs Unlinked", crosstab_summary, start_row = 1, col_names = TRUE)

# Save broadened output (grain-labeled + backward compat)
NEW_OUTPUT_XLSX <- file.path(CONFIG$output_dir, "encounter_level_drug_grouping_instances.xlsx")
OLD_OUTPUT_XLSX <- file.path(CONFIG$output_dir, "drug_grouping_instances.xlsx")
wb_broad$save(NEW_OUTPUT_XLSX)
wb_broad$save(OLD_OUTPUT_XLSX)
message(glue("Saved broadened (3 sheets): {NEW_OUTPUT_XLSX}, {OLD_OUTPUT_XLSX}"))

# --- Linked-only output (2 sheets) ---
wb_linked <- wb_workbook()

# Sheet 1: Sub-Category Detail (cancer-linked only, NO cancer_linked column)
table1_linked_export <- table1_linked %>% select(-cancer_linked)
wb_linked$add_worksheet("Enc: Sub-Category Detail")
wb_linked$add_data("Enc: Sub-Category Detail", table1_linked_export, start_row = 1, col_names = TRUE)

# Sheet 2: Treatment Detail (cancer-linked only, NO cancer_linked column)
table2_linked_export <- table2_linked %>% select(-cancer_linked)
wb_linked$add_worksheet("Enc: Treatment Detail")
wb_linked$add_data("Enc: Treatment Detail", table2_linked_export, start_row = 1, col_names = TRUE)

# Save linked-only output with _linked_only suffix (per D-08)
NEW_OUTPUT_LINKED_XLSX <- file.path(CONFIG$output_dir, "encounter_level_drug_grouping_instances_linked_only.xlsx")
OLD_OUTPUT_LINKED_XLSX <- file.path(CONFIG$output_dir, "drug_grouping_instances_linked_only.xlsx")
wb_linked$save(NEW_OUTPUT_LINKED_XLSX)
wb_linked$save(OLD_OUTPUT_LINKED_XLSX)
message(glue("Saved linked-only (2 sheets): {NEW_OUTPUT_LINKED_XLSX}, {OLD_OUTPUT_LINKED_XLSX}"))
```

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Excel sheet name truncation | Manual string truncation logic | Direct assignment (Excel auto-truncates at 31) | openxlsx2 handles 31-char limit internally; no need for substr() |
| Cross-tab aggregation | Nested loops per treatment_type | dplyr `group_by() %>% summarise()` + `pivot_wider()` | Declarative, readable, handles edge cases (missing groups) |
| Dual-output differentiation | Single workbook with version flags | Separate workbooks with suffix naming | Clear file distinction; no risk of users opening wrong sheet |

**Key insight:** R/57 already has all the data needed (cancer_codes, cancer_category_names) — the broadening is just removing a filter, not adding new data sources.

## Common Pitfalls

### Pitfall 1: Forgetting to Remove cancer_linked from Linked-Only Export
**What goes wrong:** Linked-only output includes cancer_linked column (always TRUE), breaking backward compatibility
**Why it happens:** table1_linked and table2_linked are filtered from table1_all/table2_all which have cancer_linked
**How to avoid:** Explicitly `select(-cancer_linked)` before writing linked-only sheets
**Warning signs:** Linked-only xlsx has 7 columns instead of 6 (Table 1) or 6 instead of 5 (Table 2)

### Pitfall 2: Inconsistent Filtering Between Table 1 and Table 2
**What goes wrong:** Table 1 shows all encounters but Table 2 still filters to cancer-linked-only
**Why it happens:** Forgetting to apply broadening to both tables (lines 375 AND 399)
**How to avoid:** Create table1_all/table2_all first, then derive table1_linked/table2_linked from them using same filter
**Warning signs:** Row count mismatch between Table 1 and Table 2 in broadened output

### Pitfall 3: Cross-Tab Summary Using Episode-Level Data
**What goes wrong:** Cross-tab shows episode counts instead of encounter counts
**Why it happens:** Aggregating from treatment_episodes.rds instead of R/57's detail_codes
**How to avoid:** Build cross-tab from table1_all (encounter-level grain) not from episodes
**Warning signs:** Cross-tab totals don't match sum(nrow(table1_all))

### Pitfall 4: Overwriting Existing Output Files
**What goes wrong:** Broadened output overwrites linked-only output (or vice versa)
**Why it happens:** Reusing OLD_OUTPUT_XLSX path for both workbooks
**How to avoid:** Define 4 separate paths (NEW/OLD for broadened, NEW_LINKED/OLD_LINKED for linked-only)
**Warning signs:** Only 2 output files exist after script runs (should be 4)

## Code Examples

Verified patterns from R/57 existing code:

### cancer_linked Column Derivation
```r
# Source: R/57 logic (cancer_codes already exists from Section 4)

# In Section 5 (Table 1) and Section 6 (Table 2):
# After creating aggregated tables, add cancer_linked column
table1_all <- detail_codes %>%
  # ... existing aggregation logic ...
  mutate(cancer_linked = !is.na(cancer_codes)) %>%  # TRUE if encounter has cancer DX
  select(patient_id, ENCOUNTERID, treatment_date, treatment_category,
         sub_category_names, cancer_category_names, cancer_linked)

# Explanation: cancer_codes is NA when encounter has no cancer diagnosis codes
# (set in Section 4 lines 188-190: left_join returns NA for non-matching rows)
# !is.na(cancer_codes) produces TRUE for linked, FALSE for unlinked
```

### Reference Code Filter (Preserved in Broadened Output)
```r
# Source: R/57 lines 280-284 (existing logic, unchanged in Phase 101)

# Reference filter: keep only codes in xlsx sheets OR Immunotherapy category
# This filter stays for BOTH broadened and linked-only outputs (per D-02)
detail_codes <- detail_codes %>%
  filter(triggering_code %in% valid_reference_codes | category == "Immunotherapy")

# Result: broadened output is "all treatment encounters that passed reference filter"
# not "literally every row in treatment_episode_detail.rds"
```

### Backward-Compatible Linked-Only Table Creation
```r
# Source: Current R/57 line 375 filter, preserved for linked-only variant

# Create linked-only version by filtering the broadened table
table1_linked <- table1_all %>%
  filter(!is.na(cancer_category_names)) %>%  # Original filter logic
  select(-cancer_linked)  # Remove flag column (not in original output)

# This ensures linked-only output matches current R/57 output exactly:
# - Same filtering logic
# - Same column structure (no cancer_linked column)
# - Same row ordering
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Single output (cancer-linked-only) | Dual output (broadened + linked-only) | Phase 101 (2026-06-12) | Users can analyze all treatment encounters (e.g., unlinked chemo for regimen detection) while preserving existing cancer-focused workflows |
| No visibility into unlinked encounters | cancer_linked flag + cross-tab summary | Phase 101 | Quantifies how many encounters lack cancer DX linkage per treatment type |
| Manual xlsx sheet naming | openxlsx2 auto-truncation | Already established (R/57 Phase 89) | No change needed |

**Deprecated/outdated:**
None — this is a new capability, not a replacement.

## Open Questions

1. **Column Ordering for cancer_linked**
   - What we know: Flag can go anywhere in table1_all/table2_all
   - What's unclear: Last column (minimal disruption) vs. positioned after cancer_category_names (contextual grouping)
   - Recommendation: Last column (easier for users to ignore if not needed; consistent with "new column" pattern)

2. **Smoke Test Coverage**
   - What we know: R/88 needs new validation section for broadened output
   - What's unclear: Depth of checks (file existence only vs. row count validations vs. schema checks)
   - Recommendation: File existence (4 files), row count comparison (broadened > linked-only), sheet count (3 vs 2), column presence (cancer_linked in broadened, absent in linked-only)

3. **Cross-Tab Sheet Naming**
   - What we know: Must fit 31-char Excel limit
   - What's unclear: "Linked vs Unlinked Summary" (26 chars) vs. "Linked vs Unlinked" (18 chars) vs. shorter variant
   - Recommendation: "Linked vs Unlinked" (18 chars, clear, plenty of margin)

## Validation Architecture

> Skipped: workflow.nyquist_validation is explicitly set to false in .planning/config.json.

## Environment Availability

> Skipped: Phase 101 has no external dependencies beyond R packages already installed in the pipeline (dplyr, tidyr, glue, stringr, openxlsx2). All dependencies are code/config-only changes using existing R/57 infrastructure.

## Sources

### Primary (HIGH confidence)
- R/57_drug_grouping_instances.R (existing script structure, Section 4 cancer_codes derivation, Section 7 openxlsx2 pattern)
- R/56_new_tables_from_groupings.R (reference for episode-level vs encounter-level distinction, confirms R/56 stays unchanged)
- R/28_episode_classification.R (cancer linkage context, confirms R/57 derivation is independent)
- R/00_config.R (CONFIG paths, confirms output_dir structure)
- openxlsx2 documentation (CRAN stable, multi-sheet workbook pattern verified)

### Secondary (MEDIUM confidence)
- CONTEXT.md decisions D-01 through D-10 (user-validated constraints)
- REQUIREMENTS.md DRUG-01, DRUG-02, DRUG-03 (project requirements)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - all packages already installed, no new dependencies
- Architecture: HIGH - existing R/57 patterns apply directly (dual-output, multi-sheet xlsx)
- Pitfalls: MEDIUM - common dplyr/openxlsx2 issues documented, but no Phase 101-specific gotchas yet observed
- Code examples: HIGH - sourced directly from R/57 existing code

**Research date:** 2026-06-12
**Valid until:** 90 days (stable R packages, established project patterns, no fast-moving dependencies)
