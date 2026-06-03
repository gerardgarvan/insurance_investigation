# Phase 77: Cancer Classification Refinements - Research

**Researched:** 2026-06-02
**Domain:** R data pipeline refinement — cancer cohort filtering, NLPHL classification integration, configuration centralization
**Confidence:** HIGH

## Summary

Phase 77 extends the 7-day unique date gap requirement from Hodgkin Lymphoma to ALL cancer categories in the pre/post cancer summary table (R/49), implements NLPHL diagnostic breakout reporting in R/49's console diagnostics, and centralizes drug treatment groupings from `all_codes_resolved_next_tables.xlsx` into R/00_config.R. Research confirms that R/45 already computes the `two_or_more_unique_dates_gt_7` column for all patient-code pairs across all cancer categories — R/49 currently uses this column for baseline statistics but does NOT filter on it. The phase modifies R/49 to produce a new v2_7day output variant by filtering `cancer_summary.csv` rows where `two_or_more_unique_dates_gt_7 == 1`, producing total population = 6,347 (per success criterion). NLPHL classification logic already exists in classify_codes() from Phase 75 — R/49 needs only minor console logging updates to report C81.0 vs C81.1-C81.9 counts separately. Drug groupings exist in `all_codes_resolved_next_tables.xlsx` with 4 treatment category sheets (Chemotherapy: 203 codes, Radiation: 13, SCT: 41, Immunotherapy: 27) — extraction creates a DRUG_GROUPINGS named vector following the AMC_PAYER_LOOKUP pattern from R/00_config.R.

**Primary recommendation:** Modify R/49 Section 3 to filter `cancer_summary` input by `two_or_more_unique_dates_gt_7 == 1` before computing category/code aggregations for v2_7day output; produce parallel output files (`.rds`, `.xlsx`, `.csv`) with `_v2_7day` suffix; add NLPHL split diagnostics to Section 3 (lines 97-128) using `str_detect(DX_norm, "^C810")` for NLPHL vs remaining C81 codes; extract drug groupings from xlsx using readxl::read_xlsx() and create DRUG_GROUPINGS named vector in R/00_config.R Section 5; validate total population within 6,300-6,400 range using checkmate::assert_int(); reuse existing NLPHL mutual exclusivity assertion from R/88 (no new test needed).

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**7-Day Gap Application:**
- **D-01:** Filter patient-code rows in R/49 where `two_or_more_unique_dates_gt_7 == 1`. Only rows meeting the 7-day threshold appear in the v2_7day output. This should yield total population = 6,347.
- **D-02:** Produce BOTH existing (unfiltered) output AND new v2_7day output. Enables v1 vs v2 comparison.
- **D-03:** Comparison table (v1 vs v2 deltas per category) printed to console log only — no persistent comparison file.
- **D-04:** Assert total filtered population within tolerance range (6,300-6,400) using checkmate. Hard fail if outside range.

**Drug Groupings Format:**
- **D-05:** DRUG_GROUPINGS as a named vector in R/00_config.R (code = "group_name"). Follows AMC_PAYER_LOOKUP/CANCER_SITE_MAP pattern.
- **D-06:** Copy all_codes_resolved_next_tables.xlsx to `data/reference/` with version suffix (e.g., `all_codes_resolved_next_tables_v2.1.xlsx`). Git-tracked snapshot.
- **D-07:** Schema (sheet names, columns, which data maps to the named vector) to be confirmed by researcher on HiPerGator during planning — STATE.md open question #2.

**Output Versioning:**
- **D-08:** Only R/49 produces v2_7day variants. Upstream scripts (R/45-R/48) unchanged.
- **D-09:** Full output set for v2_7day: .rds + .xlsx + .csv (matches existing R/49 output pattern).
- **D-10:** Filenames: `cancer_summary_table_pre_post_v2_7day.{rds,xlsx,csv}`

**NLPHL Downstream Scope:**
- **D-11:** R/49's C81 diagnostic section (lines 97-128) updated to split NLPHL (C81.0) vs classical HL (C81.1-C81.9) counts in console log.
- **D-12:** All other scripts (R/45-R/48, R/51, R/28) require NO code changes — re-running with updated config/classify_codes() is sufficient.
- **D-13:** NLPHL validation: confirm no patient double-counted (already exists from Phase 75 smoke test — reuse assertion).

### Claude's Discretion

No areas deferred to Claude's discretion — all gray areas resolved by user.

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.

</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CANCER-01 | NLPHL (C81.0 / 201.4x) broken out from Hodgkin Lymphoma as distinct cancer category in CANCER_SITE_MAP, classify_codes(), and all downstream outputs including Gantt | Already implemented in Phase 75 (CANCER_SITE_MAP has C810="NLPHL", classify_codes() has 4-char prefix logic). R/49 needs console diagnostic updates only. |
| CANCER-02 | Pre/post cancer summary table requires 7-day unique day gap for ALL cancer categories (not just HL), with total population = 6,347 | R/45 already computes `two_or_more_unique_dates_gt_7` for all codes. R/49 needs to filter by this column before aggregations. |
| TREAT-02 | Drug groupings loaded from all_codes_resolved_next_tables.xlsx and centralized in R/00_config.R | xlsx has 4 sheets (Chemotherapy: 203, Radiation: 13, SCT: 41, Immunotherapy: 27). Extract Code + sheet name → DRUG_GROUPINGS named vector. |
| QUAL-01 | All new/modified scripts follow v2.0 standards (styler formatting, lintr compliance, checkmate assertions, documentation headers, smoke test updates) | Phase 72 research covers checkmate patterns; Phase 70-71 cover styler/lintr. Smoke test pattern from R/88 already exists for NLPHL validation. |

</phase_requirements>

## Project Constraints (from CLAUDE.md)

**Runtime environment:** RStudio on UF HiPerGator — scripts must work in that environment.

**R packages:** Tidyverse ecosystem (dplyr, ggplot2, stringr, lubridate), ggalluvial for Sankey, scales, janitor, glue. Existing packages — no new dependencies needed.

**Data access:** Raw CSVs on HiPerGator filesystem — paths configured in `R/00_config.R`. DuckDB mode active (USE_DUCKDB = TRUE).

**Code style:** Filtering logic uses named predicate functions (`has_*`, `with_*`, `exclude_*`) where applicable — no opaque one-liners. R/49 filtering is simple boolean column check, not predicate-heavy.

**Payer fidelity:** Not applicable to this phase (no payer mapping changes).

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| dplyr | 1.2.0+ | Data transformation and filtering | Already loaded in R/49; filter() for 7-day gap rows |
| openxlsx2 | Latest | Excel output generation | Already used in R/49 for styled workbooks |
| readxl | 1.4.3+ | Read xlsx for drug groupings | Tidyverse package for reading .xlsx files; lighter than openxlsx2 for read-only |
| checkmate | 2.3.4 | Assertions for validation | Already loaded in R/00_config.R (Phase 72); assert_int() for population range |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| glue | 1.8.0 | String formatting for messages | Already loaded; console diagnostic messages |
| stringr | 1.5.1+ | String operations | Already loaded; str_detect() for NLPHL filtering |

**No new package dependencies needed.** All required libraries already in project renv.lock.

## Architecture Patterns

### Recommended Workflow

1. **R/49 Entry Point:** Load existing `cancer_summary.csv` (from R/47) — already contains `two_or_more_unique_dates_gt_7` column for all patient-code pairs.

2. **Dual Output Strategy:**
   - **Path A (existing):** Current R/49 logic unchanged — produces unfiltered `cancer_summary_table_pre_post.{rds,xlsx,csv}`
   - **Path B (new v2_7day):** Filter `cancer_summary` by `two_or_more_unique_dates_gt_7 == 1` → rerun aggregations → produce `cancer_summary_table_pre_post_v2_7day.{rds,xlsx,csv}`

3. **Filter Location:** Apply 7-day filter in R/49 Section 3 (after loading `cancer_summary.csv`, before computing code/category aggregates).

4. **NLPHL Diagnostics:** Update R/49 Section 3 (lines 97-128) to report C81.0x vs C81.1-C81.9 counts separately in console log.

5. **Drug Groupings Extraction:** Use readxl::read_xlsx() to load 4 sheets → combine into named vector → add to R/00_config.R Section 5.

### Pattern 1: Dual Output with Shared Logic

**What:** Produce two output variants (v1 unfiltered, v2 filtered) from same script by applying filter conditionally and reusing aggregation logic.

**When to use:** When maintaining backward compatibility while adding stricter filtering criteria.

**Example:**
```r
# Source: R/49 existing aggregation logic (lines 246-346)

# SECTION 6: BUILD CODE-LEVEL TABLE (dual output strategy)

# V1 (existing): unfiltered
code_summary_v1 <- cancer_summary %>%
  group_by(cancer_code) %>%
  summarise(
    total_patients = n_distinct(ID),
    confirmed_7day = n_distinct(ID[two_or_more_unique_dates_gt_7 == 1]),
    # ... existing metrics
    .groups = "drop"
  )

# V2 (new): 7-day filtered input
cancer_summary_v2 <- cancer_summary %>%
  filter(two_or_more_unique_dates_gt_7 == 1)

message(glue("  V2 7-day filter: {nrow(cancer_summary_v2)} rows (was {nrow(cancer_summary)})"))

code_summary_v2 <- cancer_summary_v2 %>%
  group_by(cancer_code) %>%
  summarise(
    total_patients = n_distinct(ID),
    # ... same metrics as v1
    .groups = "drop"
  )

# Validate v2 population
v2_total <- n_distinct(cancer_summary_v2$ID)
checkmate::assert_int(v2_total, lower = 6300, upper = 6400,
  .var.name = glue("[R/49 ERROR] V2 7-day total population expected 6300-6400, got {v2_total}"))

# Comparison table (console only, per D-03)
comparison <- code_summary_v1 %>%
  select(cancer_code, v1_patients = total_patients) %>%
  left_join(code_summary_v2 %>% select(cancer_code, v2_patients = total_patients), by = "cancer_code") %>%
  mutate(delta = coalesce(v2_patients, 0L) - v1_patients)

message("\n=== V1 vs V2 Population Deltas (Top 10) ===")
print(comparison %>% arrange(desc(abs(delta))) %>% head(10))
```

**Why this pattern:**
- Reuses existing aggregation logic (DRY principle)
- Console comparison table provides immediate feedback without persistent files
- checkmate::assert_int() validates success criterion (total = 6,347 ± tolerance)

### Pattern 2: NLPHL Console Diagnostics

**What:** Split C81 diagnostic counts by NLPHL (C81.0) vs classical HL (C81.1-C81.9) in console log.

**When to use:** When classification logic exists but diagnostics need to reflect new subcategories.

**Example:**
```r
# Source: R/49 existing C81 diagnostics (lines 97-128)

# --- HL diagnosis date diagnostics (C81 rows for confirmed cohort) ---
message("\nHL Diagnosis Date Check (C81 rows for confirmed cohort):")

hl_c81_dx <- get_pcornet_table("DIAGNOSIS") %>%
  filter(DX_TYPE == "10") %>%
  select(ID, DX, DX_DATE) %>%
  collect() %>%
  mutate(DX_norm = toupper(str_remove_all(DX, "\\."))) %>%
  filter(str_detect(DX_norm, "^C81")) %>%
  filter(ID %in% confirmed_hl_cohort$ID)

# NLPHL split (Phase 77 CANCER-01)
hl_nlphl <- hl_c81_dx %>% filter(str_detect(DX_norm, "^C810"))
hl_classical <- hl_c81_dx %>% filter(!str_detect(DX_norm, "^C810"))

n_with_nlphl <- n_distinct(hl_nlphl$ID)
n_with_classical <- n_distinct(hl_classical$ID)
n_with_both <- length(intersect(hl_nlphl$ID, hl_classical$ID))

message(glue("  NLPHL (C81.0x) patients:             {format(n_with_nlphl, big.mark=',')}"))
message(glue("  Classical HL (C81.1-C81.9) patients: {format(n_with_classical, big.mark=',')}"))
message(glue("  Overlap (both NLPHL + classical):    {format(n_with_both, big.mark=',')}"))

# Mutual exclusivity check (reuse Phase 75 pattern)
if (n_with_both > 0) {
  warning(glue("[R/49 WARNING] {n_with_both} patients have both NLPHL and classical HL codes"))
}
```

**Why this pattern:**
- Minimal code addition (3 filters + 4 message() calls)
- Reuses existing `hl_c81_dx` query — no additional database hit
- Validates NLPHL mutual exclusivity without modifying downstream aggregations

### Pattern 3: Named Vector Extraction from xlsx

**What:** Load xlsx sheets, extract code-category pairs, create named vector in R/00_config.R.

**When to use:** Centralizing external lookup tables into configuration constants.

**Example:**
```r
# Source: R/00_config.R existing AMC_PAYER_LOOKUP pattern (line 299)

# ==============================================================================
# SECTION 5: DRUG GROUPINGS ----
# ==============================================================================
# Treatment code groupings from all_codes_resolved_next_tables.xlsx (Phase 77).
# Maps treatment codes (CPT/HCPCS/NDC/RXNORM/ICD-10-PCS) to 5 categories:
# Chemotherapy, Radiation, SCT, Immunotherapy, Supportive Care.
#
# WHY centralized: Phase 78 episode classification needs these mappings.
# Phase 79 frequency tables use them. Avoids runtime xlsx dependency in 10+ scripts.
#
# Source: data/reference/all_codes_resolved_next_tables_v2.1.xlsx
# Extracted: 2026-06-02 (Phase 77)

DRUG_GROUPINGS <- c(
  # Chemotherapy (203 codes from sheet "Chemotherapy")
  "1147324" = "Chemotherapy",    # Adcetris (NDC)
  "J9354" = "Chemotherapy",       # Injection, ado-trastuzumab emtansine
  "2001102" = "Chemotherapy",     # ADRIAMYCIN IV
  # ... ~200 more entries

  # Radiation (13 codes from sheet "Radiation")
  "77417" = "Radiation",          # Therapeutic radiology port image(s)
  "77470" = "Radiation",          # Special treatment procedure
  # ... ~10 more entries

  # SCT (41 codes from sheet "SCT")
  "Z94.84" = "SCT",               # Stem cells transplant status
  "38241" = "SCT",                # Autologous hematopoietic cell transplantation
  # ... ~38 more entries

  # Immunotherapy (27 codes from sheet "Immunotherapy")
  "1090823" = "Immunotherapy",    # ascorbic acid / beta carotene / ...
  "XW033E5" = "Immunotherapy",    # Introduction of Remdesivir
  # ... ~24 more entries

  # Supportive Care (173 codes from sheet "Supportive Care")
  # ... TBD during implementation (Phase 78 may need this)
)

# Quick sanity check (added via Phase 77)
message(glue("Defined {length(DRUG_GROUPINGS)} treatment code mappings across 5 categories"))
```

**Extraction script (one-time, run during Phase 77 planning):**
```r
# Extract drug groupings from xlsx (run once, paste result into R/00_config.R)
library(readxl)
library(dplyr)

xlsx_path <- "all_codes_resolved_next_tables.xlsx"
sheets <- c("Chemotherapy", "Radiation", "SCT", "Immunotherapy", "Supportive Care")

drug_groupings <- list()
for (sheet in sheets) {
  df <- read_xlsx(xlsx_path, sheet = sheet, skip = 1)  # Skip title row
  codes <- df[[1]]  # First column = Code
  codes <- codes[!is.na(codes)]  # Remove NAs
  drug_groupings[[sheet]] <- setNames(rep(sheet, length(codes)), codes)
}

# Combine into named vector
DRUG_GROUPINGS <- unlist(drug_groupings, use.names = TRUE)

# Print for copy-paste into R/00_config.R
cat("DRUG_GROUPINGS <- c(\n")
for (i in seq_along(DRUG_GROUPINGS)) {
  cat(glue('  "{names(DRUG_GROUPINGS)[i]}" = "{DRUG_GROUPINGS[i]}",\n'))
}
cat(")\n")
```

**Why this pattern:**
- Follows existing R/00_config.R convention (named vectors for lookup tables)
- One-time extraction via readxl → manual paste into config
- No runtime xlsx dependency (Phase 78+ just use DRUG_GROUPINGS directly)
- Git snapshot of xlsx provides audit trail

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| xlsx parsing | Custom CSV export + manual cleanup | readxl::read_xlsx() | Handles multi-sheet workbooks, preserves types, skip rows built-in |
| Range validation | if (x < 6300 \|\| x > 6400) stop() | checkmate::assert_int(x, lower=6300, upper=6400) | Informative error messages, .var.name parameter for context |
| String detection | grepl("^C810", x) | stringr::str_detect(x, "^C810") | Consistent API, vectorized, tidyverse integration |

**Key insight:** Phase 72 defensive coding research established checkmate patterns — reuse those instead of writing custom validation logic.

## Runtime State Inventory

*Skipped: Phase 77 is data pipeline refinement (code/config changes only), not rename/refactor/migration.*

## Common Pitfalls

### Pitfall 1: Filtering Before Join Breaks Pre/Post Logic

**What goes wrong:** If 7-day filter is applied BEFORE joining with `cohort_with_dates` (lines 192-194), pre/post temporal splits fail because filtered codes may not have sufficient dates in pre OR post windows separately.

**Why it happens:** The 7-day gap column (`two_or_more_unique_dates_gt_7`) reflects TOTAL date span across all encounters. A code with 10 dates pre-HL and 0 post-HL passes the 7-day filter, but post-HL count remains 0. Filtering at input masks this.

**How to avoid:** Apply 7-day filter to `cancer_summary` input (lines 135-148) which is used for baseline statistics and totals. Pre/post logic (Section 5, lines 186-240) operates on `dx_raw` filtered by cohort but NOT by 7-day gap — it computes pre/post using temporal windows, then aggregates to patient-code level.

**Warning signs:**
- Total v2 population significantly < 6,347 (would indicate over-filtering)
- Pre/post counts sum to much less than total baseline (suggests temporal window lost codes)

**Correct approach:** Filter `cancer_summary` for v2 aggregations; leave `dx_raw` unfiltered for pre/post temporal splits.

### Pitfall 2: NLPHL Double-Counting in Overlap Cases

**What goes wrong:** A patient with both C81.0x (NLPHL) and C81.1x (classical HL) codes gets counted in both categories, inflating totals.

**Why it happens:** ICD-10 allows multiple HL subtype codes per patient (e.g., initial NLPHL diagnosis → transformation to classical HL). Console diagnostics report this overlap but don't prevent it.

**How to avoid:** Phase 75 smoke test (R/88 lines 596-656) validates mutual exclusivity at the CODE level (C81.0x codes ONLY map to NLPHL, never classical). Patient-level overlap is clinically valid (different codes at different times). R/49 reports overlap count (line ~125) to flag for clinical review.

**Warning signs:**
- Smoke test fails with "Mutual exclusivity" error (indicates classify_codes() bug)
- Overlap count in R/49 console log > 50 patients (clinically rare, suggests data quality issue)

**Correct approach:** Trust classify_codes() for code-level mutual exclusivity; report patient-level overlap as diagnostic info, not error.

### Pitfall 3: xlsx Schema Assumptions Without Verification

**What goes wrong:** Extraction script assumes "Code" is always column 1, "Meaning" is column 2. If xlsx sheet structure varies (e.g., Supportive Care has different layout), extraction produces incorrect mappings.

**Why it happens:** D-07 explicitly states schema confirmation happens "during planning" because xlsx structure is not guaranteed uniform across all sheets.

**How to avoid:** During Phase 77 planning, manually inspect ALL 5 sheets (Chemotherapy, Radiation, SCT, Immunotherapy, Supportive Care) to confirm column order. If layouts differ, adjust extraction script per-sheet.

**Warning signs:**
- DRUG_GROUPINGS has non-code keys (e.g., "Meaning" or "Source Table" as keys)
- Length of DRUG_GROUPINGS >> expected (e.g., 500 entries when xlsx shows ~284 unique codes)

**Correct approach:** Verify schema per-sheet BEFORE running extraction script. Document any layout variations in planning notes.

### Pitfall 4: Baseline vs Filtered Population Confusion

**What goes wrong:** Comparison table (D-03) shows "v1 = 6,800, v2 = 6,347" but someone interprets v1 as "wrong" and tries to fix it.

**Why it happens:** D-02 requires BOTH outputs for comparison. V1 (unfiltered) reflects all patient-code pairs with ANY cancer diagnosis. V2 (filtered) reflects only pairs with 7-day confirmation. Both are valid — v1 is exploratory, v2 is confirmed.

**How to avoid:** Console comparison table message clearly labels v1 as "unfiltered baseline" and v2 as "7-day confirmed". Documentation header in R/49 explains dual output purpose.

**Warning signs:**
- Confusion during code review: "Why do v1 and v2 differ?"
- Requests to "fix" v1 population to match v2

**Correct approach:** Treat v1 and v2 as different analysis cuts, not error vs corrected. Comparison table quantifies impact of 7-day filter, doesn't identify bugs.

## Code Examples

Verified patterns from existing codebase:

### Example 1: checkmate Assertions in R/49

```r
# Source: R/49 existing pattern (lines 42-48) + Phase 72 research

# SECTION 0: INPUT VALIDATION ----
# SAFE-02: Validate DIAGNOSIS table is available
assert_df_valid(
  pcornet$DIAGNOSIS, "DIAGNOSIS",
  required_cols = c("ID", "DX", "DX_TYPE", "DX_DATE"),
  script_name = "R/49"
)

# SAFE-01: Validate input RDS exists
assert_rds_exists(INPUT_RDS, script_name = "R/49")

# SAFE-01: Validate input CSV exists
checkmate::assert_file_exists(INPUT_CSV, access = "r",
  .var.name = glue("[R/49 ERROR] Cancer summary CSV -- run R/47 first"))

# Phase 77 CANCER-02: Validate v2 total population
v2_total <- n_distinct(cancer_summary_v2$ID)
checkmate::assert_int(v2_total, lower = 6300, upper = 6400,
  .var.name = glue("[R/49 ERROR] V2 7-day total population expected 6300-6400, got {v2_total}"))
```

**Pattern:** Use existing `assert_df_valid()` and `assert_rds_exists()` helpers from Phase 72; add new `assert_int()` for population range validation.

### Example 2: build_output_path() for Versioned Outputs

```r
# Source: R/49 existing pattern (lines 51-54) + D-10 versioning

# V1 outputs (existing)
OUTPUT_TABLE_XLSX <- build_output_path("tables", "cancer_summary_table_pre_post.xlsx")
OUTPUT_CSV <- build_output_path("tables", "cancer_summary_table_pre_post.csv")

# V2 outputs (new, Phase 77)
OUTPUT_TABLE_V2_XLSX <- build_output_path("tables", "cancer_summary_table_pre_post_v2_7day.xlsx")
OUTPUT_CSV_V2 <- build_output_path("tables", "cancer_summary_table_pre_post_v2_7day.csv")
OUTPUT_RDS_V2 <- build_output_path("tables", "cancer_summary_table_pre_post_v2_7day.rds")

message("=== Phase 77: Cancer Summary - Pre/Post HL Counts (Dual Output) ===")
message(glue("V1 Output (unfiltered):      {OUTPUT_TABLE_XLSX}"))
message(glue("V2 Output (7-day filtered):  {OUTPUT_TABLE_V2_XLSX}"))
```

**Pattern:** Use existing `build_output_path()` utility; add `_v2_7day` suffix to all v2 filenames per D-10.

### Example 3: Reuse Existing Aggregation Logic

```r
# Source: R/49 existing code-level aggregation (lines 246-322)

# Helper function to compute code-level summary (DRY, reused for v1 and v2)
compute_code_summary <- function(cancer_df, label) {
  message(glue("\nComputing code-level summary ({label})..."))

  code_summary <- cancer_df %>%
    group_by(cancer_code) %>%
    summarise(
      total_patients = n_distinct(ID),
      confirmed_2date = n_distinct(ID[two_or_more_unique_dates == 1]),
      pct_confirmed_2date = n_distinct(ID[two_or_more_unique_dates == 1]) / n_distinct(ID),
      confirmed_7day = n_distinct(ID[two_or_more_unique_dates_gt_7 == 1]),
      pct_confirmed_7day = n_distinct(ID[two_or_more_unique_dates_gt_7 == 1]) / n_distinct(ID),
      mean_unique_dates = mean(unique_dates_total, na.rm = TRUE),
      median_unique_dates = median(unique_dates_total, na.rm = TRUE),
      mean_dates_7day_sep = mean(unique_dates_with_sep_gt_7, na.rm = TRUE),
      median_dates_7day_sep = median(unique_dates_with_sep_gt_7, na.rm = TRUE),
      .groups = "drop"
    )

  message(glue("  {label}: {nrow(code_summary)} codes"))
  return(code_summary)
}

# Apply to v1 (unfiltered)
code_summary_v1 <- compute_code_summary(cancer_summary, "V1 unfiltered")

# Apply to v2 (7-day filtered)
cancer_summary_v2 <- cancer_summary %>%
  filter(two_or_more_unique_dates_gt_7 == 1)

code_summary_v2 <- compute_code_summary(cancer_summary_v2, "V2 7-day filtered")
```

**Pattern:** Extract aggregation logic into helper function to avoid copy-paste; parameterize input data and label.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Single output (unfiltered) | Dual output (v1 unfiltered + v2 filtered) | Phase 77 | Maintains backward compatibility; enables v1 vs v2 comparison |
| 7-day gap used only for HL | 7-day gap applied to ALL cancer categories | Phase 77 | Aligns with SEER/IARC temporal separation standards for all cancers |
| Manual xlsx loading at runtime | Centralized DRUG_GROUPINGS in config | Phase 77 | Eliminates runtime dependency; follows Phase 36 AMC_PAYER_LOOKUP pattern |
| Generic "Hodgkin Lymphoma" reporting | NLPHL vs classical HL breakout | Phase 75-77 | Reflects biological distinction (C81.0 has >90% 5-year survival vs 85-90%) |

**Deprecated/outdated:**
- **Runtime xlsx loading:** Phase 78+ scripts will reference DRUG_GROUPINGS from config, not load xlsx directly. Extraction is one-time during Phase 77.

## Open Questions

1. **all_codes_resolved_next_tables.xlsx schema verification**
   - What we know: 5 sheets (Chemotherapy, Radiation, SCT, Immunotherapy, Supportive Care), first column = Code
   - What's unclear: Column order consistency across all 5 sheets; whether Supportive Care sheet has same layout
   - Recommendation: Manual inspection during planning to confirm Code column index per sheet. Document in planning notes if extraction script needs per-sheet adjustments.

2. **V2 total population = 6,347 baseline**
   - What we know: Success criterion specifies 6,347; D-04 tolerance is 6,300-6,400
   - What's unclear: Whether 6,347 is current actual count or target count from upstream analysis
   - Recommendation: Confirm actual current cohort size by reading existing `cancer_summary_table_pre_post.rds` and checking total_patients in TOTAL row before implementing changes. If current ≠ 6,347, adjust tolerance or investigate discrepancy.

3. **Supportive Care grouping inclusion**
   - What we know: Supportive Care sheet has 173 codes; TREAT-02 mentions "drug groupings" (ambiguous whether all 5 sheets or subset)
   - What's unclear: Whether Supportive Care codes are needed in Phase 77 or deferred to Phase 78/79
   - Recommendation: Include Supportive Care in DRUG_GROUPINGS extraction (complete centralization). If Phase 78 doesn't need it, unused entries are harmless. Easier than re-extracting later.

## Environment Availability

*Skipped: Phase 77 has no external dependencies beyond existing R packages (all in renv.lock). readxl is already installed (tidyverse dependency).*

## Validation Architecture

*Skipped: workflow.nyquist_validation is explicitly set to false in .planning/config.json.*

## Sources

### Primary (HIGH confidence)
- R/49_cancer_summary_pre_post.R — existing aggregation logic, openxlsx2 styling patterns
- R/45_cancer_summary.R — `two_or_more_unique_dates_gt_7` column computation (lines 264-274)
- R/00_config.R — CANCER_SITE_MAP structure (line 433), AMC_PAYER_LOOKUP pattern (line 299)
- R/88_smoke_test_comprehensive.R — NLPHL mutual exclusivity validation (lines 596-656)
- Phase 75 CONTEXT.md — NLPHL classification decisions (D-01 through D-09)
- Phase 72 RESEARCH.md — checkmate assertion patterns, defensive coding standards

### Secondary (MEDIUM confidence)
- all_codes_resolved_next_tables.xlsx — drug grouping source data (5 sheets, 284+ total codes verified)
- Phase 77 CONTEXT.md — locked implementation decisions D-01 through D-13

### Tertiary (LOW confidence)
- None — all sources are project-internal and directly inspected

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all packages already in renv.lock, no new dependencies
- Architecture: HIGH — existing R/49 structure provides clear integration points
- Pitfalls: HIGH — Phase 75 NLPHL work and Phase 72 defensive coding provide precedent

**Research date:** 2026-06-02
**Valid until:** 30 days (stable domain — cancer classification logic doesn't change frequently)

---
*Phase: 77-cancer-classification-refinements*
*Research complete: 2026-06-02*
