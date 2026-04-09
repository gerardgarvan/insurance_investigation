# Phase 19: Investigate Insurance Missingness Source UF Specifically - Research

**Researched:** 2026-04-09
**Domain:** Missing data diagnostics in healthcare insurance / payer variables
**Confidence:** HIGH

## Summary

Phase 19 investigates why insurance/payer data is missing for UFH (University of Florida) patients in the OneFlorida+ Hodgkin Lymphoma cohort. The primary hypothesis is a data submission gap from UF — certain encounter types or time periods may systematically lack payer information.

This phase produces a **standalone diagnostic R script** (likely `R/18_uf_insurance_missingness.R`) that examines both raw ENCOUNTER table fields (PAYER_TYPE_PRIMARY, PAYER_TYPE_SECONDARY) and derived harmonized values (PAYER_CATEGORY_PRIMARY) for UFH patients. The script breaks down missingness by year, encounter type, and other discovered dimensions, writing CSV outputs to `output/tables/`.

The investigation is **exploratory** — designed to surface patterns rather than test a single hypothesis. Standard R data manipulation tools (dplyr group_by + summarise + count) provide sufficient power for this analysis. Advanced missing data packages like `smdi` are **out of scope for v1** but documented for future work.

**Primary recommendation:** Use dplyr crosstabs (group_by + summarise) to profile missingness across year × encounter type × raw vs harmonized payer fields. The existing `02_harmonize_payer.R` Section 5 (enrollment completeness by partner) provides a strong starting pattern.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Missingness Definition (D-01 to D-04):**
- "Missing" insurance = PAYER_TYPE_PRIMARY or PAYER_TYPE_SECONDARY is any of: NA, empty string, NI, UN, OT, 99, or 9999
- Track missingness on BOTH PRIMARY and SECONDARY fields (not just PRIMARY)
- Sentinel codes (NI, UN, OT) count as missing — they provide no usable insurance information
- 99/9999 ("Unavailable") counts as missing — consistent with Phase 11 collapsing it into "Missing" for display

**Investigation Scope (D-05 to D-08):**
- UF-only deep dive — do not compare to other sites. Focus exclusively on characterizing UFH patients' payer data patterns
- Examine all UF patients in the HL cohort (not just those with missing payer). Compare missing vs valid payer patients to find patterns
- Break down missingness by year, encounter type, and any other dimensions the researcher discovers as worthwhile
- Investigate at both levels: raw ENCOUNTER PAYER_TYPE fields AND derived PAYER_CATEGORY_PRIMARY after harmonization — shows where the gap originates

**Output & Deliverables (D-09 to D-11):**
- Produce a standalone diagnostic R script (e.g., `R/18_uf_insurance_missingness.R` or next available number). Sources its own dependencies. Not part of the main pipeline sequence
- CSV output files go to `output/tables/` — consistent with existing pipeline outputs
- Script produces CSV files with missingness breakdowns, run on HiPerGator

**Root Cause Hypotheses (D-12 to D-14):**
- Primary hypothesis: data submission gap from UF — the site may not submit payer data in certain encounter types or time periods
- No specific observation driving this investigation yet — this is the first UF-specific look at payer missingness
- Script should be exploratory — test the data submission gap hypothesis but surface whatever patterns exist

### Claude's Discretion

- Exact CSV file names and column structures
- Which additional breakdown dimensions to include beyond year and encounter type
- Console logging format and verbosity
- Script number (next available after existing scripts)
- How to identify UFH patients (SOURCE == "UFH" from DEMOGRAPHIC table, matching existing pattern)

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope

</user_constraints>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| dplyr | 1.2.0+ | Data manipulation | Established in existing pipeline; group_by + summarise for crosstabs |
| readr | 2.2.0+ | CSV I/O | write_csv() used throughout pipeline for table outputs |
| lubridate | 1.9.3+ | Date operations | Extract year from ADMIT_DATE for temporal breakdown |
| glue | 1.8.0+ | String interpolation | Console logging with embedded expressions (message + glue pattern) |
| stringr | 1.5.1+ | String operations | Trimming whitespace, detecting sentinel values |

**Rationale:** These libraries are already loaded and used in `02_harmonize_payer.R` Section 5 (enrollment completeness by partner) — the natural template for this UF-specific analysis.

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| janitor | 2.2.1+ | Tabulation | tabyl() for quick frequency tables during exploration |
| tidyr | 1.9.3+ | Data reshaping | pivot_wider() if converting long-form crosstabs to matrix view for CSV |

**Version verification (from pipeline):** All versions confirmed from existing `renv.lock` or canonical CRAN as of 2026-04-09.

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| dplyr crosstabs | smdi 0.3.2 | smdi provides sophisticated missing data diagnostics (ASMD, Hotelling's test, random forest predictability, outcome associations) but is **overkill for v1**. Phase 19 needs descriptive breakdowns, not inferential diagnostics. Reserve smdi for v2 if missing data mechanisms require formal testing. |
| Manual group_by | naniar package | naniar (part of tidyverse ecosystem) provides miss_var_summary(), gg_miss_var() for visualization. Useful for **exploratory plots** but not required for CSV output. Consider if visual diagnostics are requested in future iterations. |
| Console logging | tidylog | tidylog already used in cohort building. Not needed here — diagnostic script logs summary stats explicitly, not pipeline operations. |

**Installation:**
```bash
# Already available in project renv
# No new package installation needed
```

## Architecture Patterns

### Recommended Script Structure
```
R/18_uf_insurance_missingness.R
├── HEADER COMMENTS           # Purpose, decisions, usage
├── DEPENDENCIES              # source("R/01_load_pcornet.R")
├── SECTION 1: UFH patients   # Filter DEMOGRAPHIC to SOURCE == "UFH"
├── SECTION 2: Encounter-level missingness
│   ├── 2a. Raw field profiling (PAYER_TYPE_PRIMARY/SECONDARY)
│   ├── 2b. Missingness by year (extract from ADMIT_DATE)
│   ├── 2c. Missingness by encounter type (ENC_TYPE)
│   └── 2d. Year × ENC_TYPE crosstab
├── SECTION 3: Harmonized payer missingness
│   ├── 3a. Join to payer_summary for PAYER_CATEGORY_PRIMARY
│   └── 3b. Compare raw vs harmonized missingness rates
├── SECTION 4: Console summary
│   └── Log key stats (total UFH patients, N missing, top patterns)
├── SECTION 5: CSV outputs
│   ├── uf_payer_missingness_by_year.csv
│   ├── uf_payer_missingness_by_enc_type.csv
│   └── uf_payer_missingness_year_x_enc_type.csv
└── END
```

### Pattern 1: Filtering to UFH Patients
**What:** Identify UF partner site patients using DEMOGRAPHIC SOURCE column
**When to use:** At script start to scope all downstream analysis
**Example:**
```r
# Source: Existing pattern from 02_harmonize_payer.R Section 5f (patient_source)
# Context: DEMOGRAPHIC table has one row per patient with SOURCE column

library(dplyr)
source("R/01_load_pcornet.R")  # Loads pcornet$DEMOGRAPHIC, pcornet$ENCOUNTER

# Filter to UFH patients
ufh_patients <- pcornet$DEMOGRAPHIC %>%
  filter(SOURCE == "UFH") %>%
  select(ID, SOURCE) %>%
  distinct()

message(glue::glue("UFH patients in cohort: {nrow(ufh_patients)}"))
```

### Pattern 2: Defining Missingness (D-01 to D-04)
**What:** Classify PAYER_TYPE fields as missing based on sentinel values
**When to use:** Before counting missingness rates
**Example:**
```r
# Source: PAYER_MAPPING from 00_config.R + compute_effective_payer logic from 02_harmonize_payer.R
# Context: Missingness = NA, empty string, or sentinel (NI/UN/OT/99/9999)

sentinel_values <- PAYER_MAPPING$sentinel_values     # c("NI", "UN", "OT")
unavailable_codes <- PAYER_MAPPING$unavailable_codes # c("99", "9999")

# Binary missing indicators
ufh_encounters <- pcornet$ENCOUNTER %>%
  inner_join(ufh_patients, by = "ID") %>%
  mutate(
    primary_missing = is.na(PAYER_TYPE_PRIMARY) |
                      nchar(trimws(PAYER_TYPE_PRIMARY)) == 0 |
                      PAYER_TYPE_PRIMARY %in% c(sentinel_values, unavailable_codes),
    secondary_missing = is.na(PAYER_TYPE_SECONDARY) |
                        nchar(trimws(PAYER_TYPE_SECONDARY)) == 0 |
                        PAYER_TYPE_SECONDARY %in% c(sentinel_values, unavailable_codes),
    both_missing = primary_missing & secondary_missing
  )
```

### Pattern 3: Temporal Breakdown by Year
**What:** Extract year from ADMIT_DATE and count missingness per year
**When to use:** Testing hypothesis that missingness varies by submission period
**Example:**
```r
# Source: lubridate::year() pattern used throughout pipeline
# Context: ADMIT_DATE may have 1900 sentinel dates (filtered in 02_harmonize_payer.R)

library(lubridate)

# Filter out 1900 sentinel dates first (per 02_harmonize_payer.R pattern)
ufh_encounters_valid <- ufh_encounters %>%
  filter(!is.na(ADMIT_DATE) & year(ADMIT_DATE) != 1900L) %>%
  mutate(admit_year = year(ADMIT_DATE))

# Missingness by year
missingness_by_year <- ufh_encounters_valid %>%
  group_by(admit_year) %>%
  summarise(
    n_encounters = n(),
    n_primary_missing = sum(primary_missing),
    n_secondary_missing = sum(secondary_missing),
    n_both_missing = sum(both_missing),
    pct_primary_missing = round(100 * n_primary_missing / n_encounters, 1),
    .groups = "drop"
  ) %>%
  arrange(admit_year)
```

### Pattern 4: Encounter Type Breakdown
**What:** Crosstab missingness by ENC_TYPE (IP, AV, ED, etc.)
**When to use:** Testing hypothesis that certain encounter types lack payer data
**Example:**
```r
# Source: PCORnet CDM v7.0 ENC_TYPE codes
# Context: ENC_TYPE column exists in ENCOUNTER (confirmed in 01_load_pcornet.R)

# Missingness by encounter type
missingness_by_enc_type <- ufh_encounters_valid %>%
  group_by(ENC_TYPE) %>%
  summarise(
    n_encounters = n(),
    n_primary_missing = sum(primary_missing),
    pct_primary_missing = round(100 * n_primary_missing / n_encounters, 1),
    .groups = "drop"
  ) %>%
  arrange(desc(n_encounters))

# Year × ENC_TYPE crosstab
missingness_year_x_enc <- ufh_encounters_valid %>%
  group_by(admit_year, ENC_TYPE) %>%
  summarise(
    n_encounters = n(),
    n_primary_missing = sum(primary_missing),
    pct_primary_missing = round(100 * n_primary_missing / n_encounters, 1),
    .groups = "drop"
  ) %>%
  arrange(admit_year, ENC_TYPE)
```

### Pattern 5: Raw vs Harmonized Comparison
**What:** Compare raw PAYER_TYPE missingness to derived PAYER_CATEGORY_PRIMARY
**When to use:** Identifying where the gap originates (submission vs harmonization)
**Example:**
```r
# Source: payer_summary from 02_harmonize_payer.R
# Context: PAYER_CATEGORY_PRIMARY is patient-level mode; need encounter-level for fair comparison

# Recompute encounter-level payer_category (from 02_harmonize_payer.R Section 2)
source("R/02_harmonize_payer.R")  # Loads payer_summary and encounters with payer_category

ufh_encounters_with_category <- encounters %>%
  inner_join(ufh_patients, by = "ID") %>%
  filter(!is.na(ADMIT_DATE) & year(ADMIT_DATE) != 1900L) %>%
  mutate(
    admit_year = year(ADMIT_DATE),
    harmonized_missing = is.na(payer_category) |
                         payer_category %in% c("Unknown", "Unavailable")
  )

# Compare raw vs harmonized missingness
comparison <- ufh_encounters_with_category %>%
  summarise(
    n_encounters = n(),
    n_raw_missing = sum(primary_missing),
    n_harmonized_missing = sum(harmonized_missing),
    pct_raw = round(100 * n_raw_missing / n_encounters, 1),
    pct_harmonized = round(100 * n_harmonized_missing / n_encounters, 1)
  )

message(glue::glue("Raw PRIMARY missing: {comparison$pct_raw}%"))
message(glue::glue("Harmonized category missing: {comparison$pct_harmonized}%"))
```

### Pattern 6: CSV Output
**What:** Write crosstab results to `output/tables/` for external review
**When to use:** Final step after all breakdowns computed
**Example:**
```r
# Source: write_csv() pattern from 02_harmonize_payer.R, 09_dx_gap_analysis.R
# Context: output/tables/ directory already exists

library(readr)

output_dir <- file.path(CONFIG$output_dir, "tables")
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

write_csv(missingness_by_year,
          file.path(output_dir, "uf_payer_missingness_by_year.csv"))
write_csv(missingness_by_enc_type,
          file.path(output_dir, "uf_payer_missingness_by_enc_type.csv"))
write_csv(missingness_year_x_enc,
          file.path(output_dir, "uf_payer_missingness_year_x_enc_type.csv"))

message(glue::glue("\nCSV outputs written to {output_dir}"))
```

### Anti-Patterns to Avoid

- **Don't use smdi package for v1:** The smdi toolkit (v0.3.2) provides sophisticated diagnostics (ASMD, Hotelling's test, random forest predictability), but Phase 19 needs descriptive breakdowns, not inferential tests. Overkill for exploratory analysis.

- **Don't filter to only missing-payer patients:** Per D-06, examine ALL UFH patients and compare missing vs valid payer. Filtering to missing-only loses the comparison group needed to identify patterns.

- **Don't ignore 1900 sentinel dates:** ADMIT_DATE with year 1900 are SAS/Excel epoch sentinels (confirmed in `02_harmonize_payer.R` lines 154-159). Filter these out before year-based analysis or they'll dominate the "1900" bin.

- **Don't assume ENC_TYPE is always populated:** While ENC_TYPE is specified in ENCOUNTER_SPEC (01_load_pcornet.R line 51), it may have NA values. Count NA as a separate category rather than filtering it out.

- **Don't compare across sites without user permission:** D-05 explicitly restricts scope to UF-only. Comparing to other sites is deferred — focus on characterizing UFH patterns first.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Missing data visualization | Custom ggplot2 missingness heatmaps | naniar::gg_miss_var() | naniar provides publication-ready missing data plots with minimal code. If visual diagnostics are needed in v2, use naniar rather than custom plotting. |
| Missing data mechanism tests | Custom MCAR/MAR tests | smdi::smdi_diagnose() | smdi implements Hotelling's test, Little's test, and random forest predictability for formal missing data diagnostics. Don't reimplement statistical tests. |
| Frequency tables with percentages | Manual mutate(pct = 100 * n / sum(n)) | janitor::tabyl() + adorn_percentages() | janitor's tabyl provides crosstabs with built-in percentage formatting and totals. Cleaner than manual percentage calculation. |
| Date range validation | Custom year bounds checking | Already implemented in 02_harmonize_payer.R | 1900 sentinel filtering pattern established at lines 154-159. Reuse rather than rewrite. |

**Key insight:** R's missing data ecosystem (naniar, smdi, mice) is mature and well-tested. For v1, dplyr crosstabs are sufficient. For v2, use specialized packages rather than building custom diagnostics.

## Common Pitfalls

### Pitfall 1: Confusing Patient-Level vs Encounter-Level Missingness
**What goes wrong:** `payer_summary$PAYER_CATEGORY_PRIMARY` is a patient-level mode computed across all encounters. Comparing it to raw encounter-level PAYER_TYPE fields conflates aggregation levels.

**Why it happens:** The harmonization pipeline (02_harmonize_payer.R) produces patient-level summaries by design. UFH missingness analysis needs encounter-level granularity to identify year/type patterns.

**How to avoid:** Recompute encounter-level payer_category from raw fields (Pattern 5) OR clearly label outputs as "patient-level" vs "encounter-level" to prevent misinterpretation.

**Warning signs:** Missingness percentages don't match between "raw" and "harmonized" breakdowns. Patient-level aggregation hides within-patient variation.

### Pitfall 2: Sentinel Codes vs Unavailable Codes
**What goes wrong:** Treating 99/9999 differently than NI/UN/OT creates inconsistent missingness definitions across script sections.

**Why it happens:** In `02_harmonize_payer.R`, sentinel_values (NI/UN/OT) trigger fallback to SECONDARY, while unavailable_codes (99/9999) map to "Unavailable" category. But per D-04, BOTH count as missing for Phase 19 purposes.

**How to avoid:** Define missingness classification once at script start (Pattern 2) and reuse consistently. Combine sentinel_values + unavailable_codes into a single missing_indicators set.

**Warning signs:** Different missingness counts when using compute_effective_payer() vs manual classification. Phase 19's definition is broader than harmonization's.

### Pitfall 3: ENC_TYPE Missing/Unknown Values
**What goes wrong:** Filtering out encounters where `is.na(ENC_TYPE)` or `ENC_TYPE == "OT"` (Other) silently drops encounters that might have payer missingness patterns.

**Why it happens:** Assuming ENC_TYPE is always populated and valid. PCORnet CDM allows NULL/missing ENC_TYPE, and "OT" is a catch-all category.

**How to avoid:** Count NA and "OT" as explicit categories in the ENC_TYPE breakdown. Use `group_by(ENC_TYPE) %>% replace_na(list(ENC_TYPE = "Unknown"))` to make missingness visible.

**Warning signs:** ENC_TYPE crosstab total encounters < total UFH encounters. Missing categories indicate filtered rows.

### Pitfall 4: ADMIT_DATE Nulls Excluded Without Logging
**What goes wrong:** Filtering `filter(!is.na(ADMIT_DATE))` without logging how many encounters were excluded loses transparency about temporal coverage.

**Why it happens:** Standard data cleaning reflex. But for missing data diagnostics, the absence of dates is itself a signal.

**How to avoid:** Log excluded counts explicitly: `n_no_admit_date <- sum(is.na(ADMIT_DATE)); message(glue("Excluded {n_no_admit_date} encounters without ADMIT_DATE"))`. Consider adding a separate breakdown for encounters with NULL dates.

**Warning signs:** Year-based crosstabs have suspiciously low totals compared to overall UFH encounter counts.

### Pitfall 5: 1900 Sentinel Year Dominating Temporal Analysis
**What goes wrong:** If 1900 sentinel dates aren't filtered, they create a massive spike in the "1900" year bin, obscuring real temporal patterns.

**Why it happens:** SAS and Excel use 1900-01-01 as a missing date sentinel. PCORnet exports preserve these as literal dates.

**How to avoid:** Filter 1900 dates before year extraction (Pattern 3), following the established pattern from `02_harmonize_payer.R` lines 154-159. Log how many were filtered for transparency.

**Warning signs:** Year breakdown shows thousands of encounters in 1900. Real diagnosis years should be 2000s-2020s for this cohort.

## Code Examples

Verified patterns from existing pipeline:

### UFH Patient Identification
```r
# Source: 02_harmonize_payer.R Section 4f (patient_source)
# Canonical reference: R/00_config.R line 107 comment

library(dplyr)
source("R/01_load_pcornet.R")

# DEMOGRAPHIC has one row per patient with SOURCE column
ufh_patients <- pcornet$DEMOGRAPHIC %>%
  filter(SOURCE == "UFH") %>%
  select(ID, SOURCE) %>%
  distinct()

message(glue::glue("UFH patients: {format(nrow(ufh_patients), big.mark=',')}"))
```

### Missingness Classification (Per D-01 to D-04)
```r
# Source: PAYER_MAPPING from R/00_config.R lines 260-275
# Canonical reference: compute_effective_payer() logic in 02_harmonize_payer.R

sentinel_values <- PAYER_MAPPING$sentinel_values     # c("NI", "UN", "OT")
unavailable_codes <- PAYER_MAPPING$unavailable_codes # c("99", "9999")

# Combine for Phase 19's broader definition
missing_indicators <- c(sentinel_values, unavailable_codes)

# Classify PRIMARY field
ufh_encounters <- pcornet$ENCOUNTER %>%
  inner_join(ufh_patients, by = "ID") %>%
  mutate(
    primary_missing = is.na(PAYER_TYPE_PRIMARY) |
                      nchar(trimws(PAYER_TYPE_PRIMARY)) == 0 |
                      PAYER_TYPE_PRIMARY %in% missing_indicators
  )
```

### Year-Based Breakdown
```r
# Source: 02_harmonize_payer.R lines 154-159 (1900 sentinel filtering)
# Canonical reference: lubridate::year() used throughout pipeline

library(lubridate)

# Filter 1900 sentinels first
ufh_encounters_valid <- ufh_encounters %>%
  filter(!is.na(ADMIT_DATE) & year(ADMIT_DATE) != 1900L) %>%
  mutate(admit_year = year(ADMIT_DATE))

# Crosstab by year
missingness_by_year <- ufh_encounters_valid %>%
  group_by(admit_year) %>%
  summarise(
    n_encounters = n(),
    n_primary_missing = sum(primary_missing),
    pct_primary_missing = round(100 * n_primary_missing / n_encounters, 1),
    .groups = "drop"
  ) %>%
  arrange(admit_year)

# Console summary
for (i in seq_len(nrow(missingness_by_year))) {
  r <- missingness_by_year[i, ]
  message(glue::glue("{r$admit_year}: {r$n_primary_missing}/{r$n_encounters} ({r$pct_primary_missing}%) missing"))
}
```

### Encounter Type Breakdown
```r
# Source: PCORnet CDM v7.0 ENC_TYPE specification
# Context: ENC_TYPE column confirmed in ENCOUNTER_SPEC (01_load_pcornet.R line 51)

# Replace NA ENC_TYPE with "Unknown" to avoid filtering
ufh_encounters_valid <- ufh_encounters_valid %>%
  mutate(ENC_TYPE = if_else(is.na(ENC_TYPE), "Unknown", ENC_TYPE))

# Crosstab by encounter type
missingness_by_enc <- ufh_encounters_valid %>%
  group_by(ENC_TYPE) %>%
  summarise(
    n_encounters = n(),
    n_primary_missing = sum(primary_missing),
    pct_primary_missing = round(100 * n_primary_missing / n_encounters, 1),
    .groups = "drop"
  ) %>%
  arrange(desc(n_encounters))

# Log top 5 encounter types
message("\nTop encounter types by volume:")
for (i in seq_len(min(5, nrow(missingness_by_enc)))) {
  r <- missingness_by_enc[i, ]
  message(glue::glue("  {r$ENC_TYPE}: {r$n_encounters} encounters, {r$pct_primary_missing}% missing payer"))
}
```

### CSV Output
```r
# Source: write_csv() pattern from 02_harmonize_payer.R line 412, 09_dx_gap_analysis.R lines 362-370
# Canonical reference: CONFIG$output_dir from 00_config.R

library(readr)

output_dir <- file.path(CONFIG$output_dir, "tables")
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

# Write year breakdown
write_csv(missingness_by_year,
          file.path(output_dir, "uf_payer_missingness_by_year.csv"))

# Write encounter type breakdown
write_csv(missingness_by_enc,
          file.path(output_dir, "uf_payer_missingness_by_enc_type.csv"))

message(glue::glue("\nCSV outputs saved to: {output_dir}"))
message("  - uf_payer_missingness_by_year.csv")
message("  - uf_payer_missingness_by_enc_type.csv")
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual frequency tables | janitor::tabyl() | janitor 2.2.1 (July 2025) | Clean crosstab syntax with built-in percentage formatting; replaces manual group_by + mutate patterns |
| Ad-hoc missing data checks | smdi package diagnostics | smdi 0.3.2 (Feb 2026) | Formalized missing data investigation framework for healthcare EHR studies; provides MCAR/MAR/NMAR tests |
| Base R table() for crosstabs | dplyr count() + janitor tabyl() | dplyr 1.2.0 (Feb 2026) | Tidyverse integration; count() is more composable with pipe workflows than base R table() |
| Custom missingness plots | naniar package | naniar 1.1.0+ | Purpose-built missing data visualization; gg_miss_var(), gg_miss_upset() for pattern exploration |

**Deprecated/outdated:**
- **Base R table():** Replaced by dplyr::count() and janitor::tabyl() in modern R workflows. Less pipeable, harder to format for output.
- **reshape2 for pivoting:** Superseded by tidyr::pivot_wider() / pivot_longer(). reshape2 no longer maintained as of 2023.

**Emerging (not for v1):**
- **smdi for EHR missing data:** Published Jan 2024, gaining traction in pharmacoepidemiology. Provides principled diagnostics for MCAR/MAR/NMAR assessment. Consider for v2 if formal mechanism testing is needed.
- **naniar for visualization:** Part of tidyverse ecosystem. If Phase 19 findings warrant visual exploration in v2, naniar provides gg_miss_var(), gg_miss_upset(), and missingness pattern plots.

## Open Questions

1. **What are the actual UF payer missingness rates?**
   - What we know: Enrollment completeness report (02_harmonize_payer.R Section 5) logs partner-level stats but doesn't break down by year or encounter type
   - What's unclear: Whether UF has systematically higher missingness than other sites, and if so, in which time periods / encounter types
   - Recommendation: Run the diagnostic script on HiPerGator to get actual numbers. CONTEXT.md notes "no specific observation driving this investigation yet" — this is exploratory.

2. **Are there ENC_TYPE codes with 100% missingness?**
   - What we know: ENC_TYPE specification exists (PCORnet CDM v7.0), column is loaded (01_load_pcornet.R line 51)
   - What's unclear: Whether certain encounter types (e.g., telehealth codes added in CDM v6.0+) systematically lack payer submission from UF
   - Recommendation: Crosstab will surface this. If found, it suggests UF's data submission process doesn't capture payer for specific care settings.

3. **Does raw vs harmonized comparison reveal a harmonization bug?**
   - What we know: Harmonization logic in 02_harmonize_payer.R is tested (Phase 2 completion verified in STATE.md)
   - What's unclear: Whether UF-specific payer code patterns cause unexpected fallback to "Unknown" during harmonization
   - Recommendation: If harmonized missingness rate is significantly higher than raw PRIMARY missingness, investigate PAYER_MAPPING prefix rules for UF-specific codes.

4. **Should SECONDARY missingness be analyzed separately?**
   - What we know: D-02 requires tracking BOTH PRIMARY and SECONDARY, compute_effective_payer() falls back to SECONDARY if PRIMARY is sentinel
   - What's unclear: Whether UF's SECONDARY field has a different missingness pattern (e.g., consistently NULL while PRIMARY is populated)
   - Recommendation: Add a section comparing PRIMARY vs SECONDARY vs both_missing rates. If SECONDARY is always missing, it explains why dual-eligible detection may fail for UF.

## Environment Availability

> Phase 19 has no external dependencies beyond the core R pipeline stack (dplyr, readr, lubridate, glue, stringr). All libraries are already installed in the project renv.

**Environment:** RStudio on UF HiPerGator (HPC SLURM scheduler)

**Availability check:** SKIPPED (no new external dependencies)

## Validation Architecture

> Skipped: workflow.nyquist_validation is explicitly set to false in .planning/config.json.

## Sources

### Primary (HIGH confidence)
- PCORnet Common Data Model v7.0 (Jan 2025): [https://pcornet.org/wp-content/uploads/2025/01/PCORnet-Common-Data-Model-v70-2025_01_23.pdf](https://pcornet.org/wp-content/uploads/2025/01/PCORnet-Common-Data-Model-v70-2025_01_23.pdf) - ENC_TYPE specification, ENCOUNTER table structure
- CRAN dplyr documentation: [https://dplyr.tidyverse.org/reference/count.html](https://dplyr.tidyverse.org/reference/count.html) - count() function for crosstabs
- CRAN janitor documentation: [https://cran.r-project.org/web/packages/janitor/vignettes/tabyls.html](https://cran.r-project.org/web/packages/janitor/vignettes/tabyls.html) - tabyl() for frequency tables
- R/02_harmonize_payer.R (project codebase): Lines 260-275 (PAYER_MAPPING), Section 5 (enrollment completeness pattern)
- R/00_config.R (project codebase): Line 107 (SOURCE column documentation), lines 95-108 (PCORNET_TABLES)

### Secondary (MEDIUM confidence)
- SMDI toolkit paper (PMC11490010): [https://pmc.ncbi.nlm.nih.gov/articles/PMC11490010/](https://pmc.ncbi.nlm.nih.gov/articles/PMC11490010/) - Missing data investigation framework for EHR studies (documented for v2 consideration)
- SMDI package CRAN page: [https://cran.r-project.org/web/packages/smdi/index.html](https://cran.r-project.org/web/packages/smdi/index.html) - Version 0.3.2 (Feb 2026) package documentation
- PCORnet partnerships with health plans (PubMed 41504749): [https://pubmed.ncbi.nlm.nih.gov/41504749/](https://pubmed.ncbi.nlm.nih.gov/41504749/) - Context on insurance data linkage in PCORnet
- R for Data Science (2e) Chapter 18: [https://r4ds.hadley.nz/missing-values.html](https://r4ds.hadley.nz/missing-values.html) - Handling missing values in tidyverse

### Tertiary (LOW confidence)
- PCORnet Data page: [https://pcornet.org/data/](https://pcornet.org/data/) - General information on data curation and partner capabilities (no specific UF missingness data found)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All libraries already in project renv, patterns verified from existing scripts (02_harmonize_payer.R, 09_dx_gap_analysis.R)
- Architecture: HIGH - Patterns directly lifted from 02_harmonize_payer.R Section 5 (enrollment completeness) and established pipeline conventions
- Pitfalls: HIGH - Sourced from actual pipeline code (1900 sentinel handling, sentinel_values vs unavailable_codes distinction, patient-level vs encounter-level aggregation)
- Missing data ecosystem (smdi, naniar): MEDIUM - Recent packages (smdi 0.3.2 Feb 2026) with strong documentation but not yet used in this project
- UF-specific payer patterns: LOW - No existing analysis of UFH missingness found in codebase or literature; this phase is the first investigation

**Research date:** 2026-04-09
**Valid until:** 60 days (stable domain — PCORnet CDM v7.0 released Jan 2025, no major updates expected until v8.0 in 2027)
