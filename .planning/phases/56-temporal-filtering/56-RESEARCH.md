# Phase 56: Temporal Filtering - Research

**Researched:** 2026-05-22
**Domain:** Temporal date filtering, immortal time bias awareness, side-by-side dataset comparison
**Confidence:** HIGH

## Summary

Phase 56 creates a post-HL variant of the cancer summary outputs by filtering cancer diagnoses to those occurring AFTER each patient's first HL diagnosis date. The implementation is straightforward: join cancer_summary.csv with confirmed_hl_cohort.rds on ID, apply temporal filter DX_DATE > first_hl_dx_date, regenerate aggregations, and produce _post_hl suffixed outputs. The challenge is not technical complexity but bias awareness and clear communication — post-diagnosis filtering creates immortal time bias (patients who died before cancer diagnosis are automatically excluded). The phase addresses this through EXPLORATORY labeling and a side-by-side comparison sheet showing baseline vs post-HL denominators.

**Primary recommendation:** Use strict > (greater than) operator for temporal filtering to exclude same-day diagnoses, following standard clinical temporal precedence logic. Reuse R/55's styled xlsx pattern for consistency. Produce comparison sheet as third sheet in post-HL table workbook to keep all artifacts in one file.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

#### Script Architecture
- **D-01:** Create a new standalone R/56_cancer_summary_post_hl.R script. R/55 baseline outputs are not modified. R/56 reads confirmed_hl_cohort.rds (from Phase 55) and cancer_summary.csv to produce _post_hl suffixed outputs.
- **D-02:** R/56 follows the same single-script consolidation pattern as R/55 — produces both patient-code level outputs (csv, xlsx) and summary table (xlsx) internally.

#### Comparison Output
- **D-03:** The side-by-side comparison is presented as a third sheet ("Comparison") in cancer_summary_table_post_hl.xlsx. Shows baseline vs post-HL counts per cancer category: total patients, total codes, and delta. Keeps everything in one workbook.

#### EXPLORATORY Labeling
- **D-04:** Each sheet name in the post-HL xlsx outputs includes an "[EXPLORATORY]" prefix (e.g., "EXPLORATORY - Category Summary").
- **D-05:** A footnote row at the bottom of each data sheet reads: "Note: Post-HL filter introduces potential immortal time bias. Use for exploratory comparison only."

#### Edge Case Handling
- **D-06:** Patients with NA first_hl_dx_date are excluded from the post-HL variant entirely. They remain in baseline only. The comparison sheet reports the exclusion count.

### Claude's Discretion

- Same-day cancer diagnoses (DX_DATE == first_hl_dx_date): Claude decides whether to use strict > or >= based on clinical standard for temporal comparisons
- Console logging verbosity and attrition step messaging
- Styling of post-HL xlsx outputs (reuse R/55's dark header pattern for consistency)
- PREFIX_MAP handling (copy from R/55 for script independence, or load from cancer_summary.csv which already has categories)

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope

</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CREF-04 | Cancer summary table is produced in two versions — all cancers and cancers occurring after first HL diagnosis date — for side-by-side comparison | Temporal filtering pattern (date comparison), openxlsx2 multi-sheet workbook creation, immortal time bias awareness, comparison table generation |

</phase_requirements>

## Standard Stack

### Core (Already Established in Project)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| dplyr | 1.2.0+ | Data joining and filtering | Standard project pattern; `left_join()` for cohort + cancer_summary merge, `filter()` for temporal condition |
| lubridate | 1.9.3+ | Date comparison operations | Already in use; no special functions needed (base R `>` operator sufficient for Date class) |
| openxlsx2 | Latest | Excel workbook creation | Project standard (R/55); `wb_workbook()`, `wb_add_worksheet()`, styling functions |
| glue | 1.8.0 | Console logging | Project standard; readable attrition messages |
| readr/vroom | 2.2.0+/1.7.0+ | CSV I/O | Project standard for reading baseline cancer_summary.csv |

### Supporting
No additional libraries needed beyond existing project stack.

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| dplyr filter() | base R subset() | Less readable; project uses tidyverse |
| > (strict greater than) | >= (greater or equal) | >= includes same-day diagnoses; unclear temporal precedence |
| openxlsx2 | openxlsx (original) | openxlsx deprecated in favor of openxlsx2; project already uses openxlsx2 |
| Comparison as separate file | Comparison as sheet in workbook | Separate file creates artifact sprawl; single workbook easier to distribute |

**Installation:**
No new installations needed — all libraries already in project renv.lock.

## Architecture Patterns

### Recommended Project Structure
```
R/
├── 55_cancer_summary_refined.R    # Baseline (all cancers) - EXISTING
├── 56_cancer_summary_post_hl.R    # Post-HL temporal variant - NEW
└── 00_config.R                     # CONFIG object - EXISTING

output/
├── confirmed_hl_cohort.rds         # Bridge artifact from R/55 - INPUT
└── tables/
    ├── cancer_summary.csv                    # Baseline - INPUT (from R/55)
    ├── cancer_summary_table.xlsx             # Baseline - INPUT (from R/55)
    ├── cancer_summary_post_hl.csv            # Post-HL - NEW OUTPUT
    ├── cancer_summary_post_hl.xlsx           # Post-HL single sheet - NEW OUTPUT
    └── cancer_summary_table_post_hl.xlsx     # Post-HL 3-sheet workbook - NEW OUTPUT
```

### Pattern 1: Temporal Filtering with Left Join
**What:** Join cancer_summary with confirmed_hl_cohort to get first_hl_dx_date, then filter DX_DATE > first_hl_dx_date
**When to use:** Any post-diagnosis event filtering
**Example:**
```r
# Source: Project pattern based on dplyr standard practices
cancer_summary_post_hl <- cancer_summary %>%
  left_join(confirmed_hl_cohort, by = "ID") %>%
  filter(!is.na(first_hl_dx_date)) %>%              # Exclude patients with no HL date (D-06)
  filter(DX_DATE > first_hl_dx_date)                # Strict > for temporal precedence
```

**Why strict > not >=:**
- Clinical temporal precedence: "post-HL" implies AFTER first diagnosis, not simultaneous
- Same-day cancer diagnoses are ambiguous (was HL diagnosed first in the encounter, or other cancer?)
- Excluding same-day diagnoses is conservative and clinically defensible
- Standard practice in survival analysis and time-to-event studies

### Pattern 2: Reuse Aggregation Logic from Upstream Script
**What:** Copy category-level and code-level aggregation sections from R/55 with no modifications
**When to use:** When producing parallel outputs with different denominators
**Example:**
```r
# Source: R/55_cancer_summary_refined.R lines 525-567
# Category-level aggregation (IDENTICAL to R/55 Section 9)
category_summary_post_hl <- cancer_summary_post_hl %>%
  group_by(category) %>%
  summarise(
    total_patients        = n_distinct(ID),
    confirmed_2date       = n_distinct(ID[two_or_more_unique_dates == 1]),
    pct_confirmed_2date   = n_distinct(ID[two_or_more_unique_dates == 1]) / n_distinct(ID),
    # ... (all other columns from R/55)
    .groups = "drop"
  ) %>%
  arrange(desc(total_patients))
```

### Pattern 3: Multi-Sheet Workbook with Comparison Sheet
**What:** Three-sheet workbook structure: Category Summary, Code Summary, Comparison
**When to use:** Presenting filtered variant alongside baseline comparison
**Example:**
```r
# Source: openxlsx2 standard pattern + R/55 styling
wb <- wb_workbook()

# Sheet 1: EXPLORATORY - Category Summary (styled like R/55)
wb$add_worksheet("EXPLORATORY - Category Summary")
# ... add data, headers, styling, footnote

# Sheet 2: EXPLORATORY - Code Summary (styled like R/55)
wb$add_worksheet("EXPLORATORY - Code Summary")
# ... add data, headers, styling, footnote

# Sheet 3: Comparison
wb$add_worksheet("Comparison")
# Build comparison_df: category, baseline_patients, post_hl_patients, delta, baseline_codes, post_hl_codes, delta
# ... add data, headers, simple styling

wb$save(OUTPUT_TABLE_XLSX)
```

### Pattern 4: Comparison Table Generation
**What:** Read baseline cancer_summary_table.xlsx to extract baseline counts, compare with post-HL counts
**When to use:** Side-by-side before/after comparison
**Example:**
```r
# Source: Project pattern based on dplyr standard practices
# Read baseline Category Summary from R/55 output
baseline_category <- openxlsx2::read_xlsx(
  file.path(CONFIG$output_dir, "tables", "cancer_summary_table.xlsx"),
  sheet = "Category Summary",
  skip_empty_rows = FALSE
) %>%
  filter(row_number() > 2, category != "TOTAL") %>%  # Skip title/header rows, exclude totals
  select(category, baseline_patients = total_patients)

# Compare with post-HL counts
comparison_df <- category_summary_post_hl %>%
  select(category, post_hl_patients = total_patients) %>%
  full_join(baseline_category, by = "category") %>%
  mutate(
    baseline_patients = if_else(is.na(baseline_patients), 0L, baseline_patients),
    post_hl_patients = if_else(is.na(post_hl_patients), 0L, post_hl_patients),
    delta_patients = post_hl_patients - baseline_patients,
    pct_change = delta_patients / baseline_patients
  )
```

### Anti-Patterns to Avoid

- **Don't use >= for post-diagnosis filtering:** Same-day diagnoses are ambiguous temporal precedence. Use strict >.
- **Don't modify baseline outputs:** R/55 outputs (cancer_summary.csv, cancer_summary_table.xlsx) remain untouched for reproducibility.
- **Don't create separate comparison CSV:** Comparison belongs in the post-HL table workbook as Sheet 3.
- **Don't forget EXPLORATORY labeling:** Both sheet names (D-04) and footnote rows (D-05) are required to flag bias risk.
- **Don't include patients with NA first_hl_dx_date in post-HL variant:** Per D-06, these are excluded entirely (not filtered to zero rows, but removed from denominator).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Excel multi-sheet workbooks | Manual XML generation, writexl | openxlsx2 | Mature API for styling, sheet management, freeze panes; project already uses it |
| Date comparison logic | Custom date parsing and comparison | Base R > operator on Date class | Dates already parsed by lubridate in upstream; comparison is trivial |
| Aggregation logic | Custom summary functions | Copy R/55 Sections 9-10 | Already tested and verified; identical logic ensures consistency |
| Before/after comparison | Manual subtraction and formatting | dplyr joins + mutate | Standard pattern; full_join handles categories appearing in one dataset only |

**Key insight:** R/55 already solved all hard problems (aggregation, styling, PREFIX_MAP). R/56 is a thin wrapper: add temporal filter, reuse everything else.

## Common Pitfalls

### Pitfall 1: Including Same-Day Diagnoses Creates Ambiguity
**What goes wrong:** Using DX_DATE >= first_hl_dx_date includes cancer diagnoses on the exact same day as first HL diagnosis. Clinical temporal precedence is unclear (which was diagnosed first in the encounter?).
**Why it happens:** >= feels inclusive and maximizes sample size; analyst assumes "post-HL" means "HL diagnosis date onward."
**How to avoid:** Use strict > operator. "Post-HL" means AFTER first diagnosis, not simultaneous.
**Warning signs:** Comparison sheet shows minimal patient exclusion between baseline and post-HL (suggests same-day diagnoses are being retained).

### Pitfall 2: Forgetting to Handle NA first_hl_dx_date
**What goes wrong:** Patients in confirmed_hl_cohort.rds with NA first_hl_dx_date appear in post-HL outputs with all their cancers (temporal filter NA > date evaluates to NA, which filter() drops, but join retains the patient).
**Why it happens:** Developer assumes confirmed_hl_cohort.rds contains only patients with valid dates; forgets sentinel date nullification in R/55 Section 5.
**How to avoid:** Explicit `filter(!is.na(first_hl_dx_date))` BEFORE temporal filter (per D-06).
**Warning signs:** Post-HL patient count is higher than expected; comparison sheet shows minimal exclusions.

### Pitfall 3: Modifying Baseline Outputs Instead of Creating New Files
**What goes wrong:** Overwriting cancer_summary.csv or cancer_summary_table.xlsx with post-HL data breaks reproducibility and destroys baseline for comparison.
**Why it happens:** Developer follows R/55's overwrite pattern (R/55 overwrites R/53 outputs); misapplies to R/56.
**How to avoid:** R/56 creates NEW files with _post_hl suffix. Baseline files remain untouched.
**Warning signs:** Git diff shows modifications to cancer_summary.csv instead of creation of cancer_summary_post_hl.csv.

### Pitfall 4: Comparison Sheet Uses Wrong Baseline Source
**What goes wrong:** Comparing post-HL counts to pre-D-code-removal baseline (R/53 output) instead of current baseline (R/55 output with D-codes already removed).
**Why it happens:** Developer reads old cancer_summary.csv instead of cancer_summary_table.xlsx.
**How to avoid:** Read baseline counts from cancer_summary_table.xlsx (R/55 output), not raw cancer_summary.csv.
**Warning signs:** Comparison shows larger-than-expected baseline counts (includes D-codes); categories like "Benign Neoplasms" appear in comparison.

### Pitfall 5: Forgetting EXPLORATORY Labeling
**What goes wrong:** Post-HL outputs lack warnings about immortal time bias; downstream analysts treat them as equivalent to baseline.
**Why it happens:** Developer focuses on technical implementation; forgets D-04 and D-05 labeling requirements.
**How to avoid:** Sheet names MUST include "[EXPLORATORY]" prefix. Data sheets MUST include footnote row with bias warning.
**Warning signs:** Sheet names are "Category Summary" instead of "EXPLORATORY - Category Summary"; no footnote rows in data sheets.

## Code Examples

Verified patterns from project and official sources:

### Temporal Filter with Edge Case Handling
```r
# Source: Project pattern based on R/55 and dplyr standard practices
# Join cancer_summary with confirmed_hl_cohort, filter to post-HL diagnoses

cancer_summary_post_hl <- cancer_summary %>%
  left_join(confirmed_hl_cohort, by = "ID") %>%
  filter(!is.na(first_hl_dx_date)) %>%              # D-06: Exclude patients with no HL date
  filter(DX_DATE > first_hl_dx_date)                # Strict > for temporal precedence

n_excluded_na_date <- n_distinct(cancer_summary$ID) -
                      n_distinct(cancer_summary %>%
                                 left_join(confirmed_hl_cohort, by = "ID") %>%
                                 filter(!is.na(first_hl_dx_date)) %>%
                                 pull(ID))

message(glue("Excluded {n_excluded_na_date} patients with NA first_hl_dx_date"))
message(glue("Post-HL cohort: {n_distinct(cancer_summary_post_hl$ID)} patients, {nrow(cancer_summary_post_hl)} cancer diagnosis rows"))
```

### EXPLORATORY Sheet with Footnote
```r
# Source: R/55 styling pattern + D-04/D-05 requirements
SHEET1 <- "EXPLORATORY - Category Summary"  # D-04: EXPLORATORY prefix
wb$add_worksheet(SHEET1)

# Title row
wb$add_data(sheet = SHEET1, x = "Cancer Summary Table - By Category (POST-HL DIAGNOSES ONLY)",
            start_row = 1, start_col = 1)
# ... styling

# Headers row
# ... (same as R/55)

# Data rows
data_start <- 3
n_data <- nrow(category_summary_post_hl)
data_end <- data_start + n_data - 1
wb$add_data(sheet = SHEET1, x = as.data.frame(category_summary_post_hl),
            start_row = data_start, col_names = FALSE)
# ... number formatting

# Totals row
totals_row <- data_end + 1
# ... (same as R/55)

# D-05: Footnote row with bias warning
footnote_row <- totals_row + 2
wb$add_data(sheet = SHEET1,
            x = "Note: Post-HL filter introduces potential immortal time bias. Use for exploratory comparison only.",
            start_row = footnote_row, start_col = 1)
wb$add_font(sheet = SHEET1, dims = glue("A{footnote_row}"),
            name = "Calibri", size = 10, italic = TRUE,
            color = wb_color("FF6B7280"))  # Gray italic
wb$merge_cells(sheet = SHEET1, dims = glue("A{footnote_row}:K{footnote_row}"))
```

### Comparison Sheet Generation
```r
# Source: Project pattern based on dplyr and openxlsx2 standard practices
# Read baseline Category Summary from R/55 output (skip title row, extract data)

baseline_path <- file.path(CONFIG$output_dir, "tables", "cancer_summary_table.xlsx")
baseline_category <- openxlsx2::read_xlsx(baseline_path, sheet = "Category Summary") %>%
  slice(-1) %>%  # Remove title row
  filter(row_number() > 1, category != "TOTAL") %>%  # Skip header row, exclude totals
  select(category, baseline_patients = `Total Patients`)

# Build comparison
comparison_df <- category_summary_post_hl %>%
  select(category, post_hl_patients = total_patients) %>%
  full_join(baseline_category, by = "category") %>%
  replace_na(list(baseline_patients = 0, post_hl_patients = 0)) %>%
  mutate(
    delta = post_hl_patients - baseline_patients,
    pct_retained = if_else(baseline_patients > 0,
                           post_hl_patients / baseline_patients,
                           NA_real_)
  ) %>%
  arrange(desc(baseline_patients))

# Add to workbook as Sheet 3
SHEET3 <- "Comparison"
wb$add_worksheet(SHEET3)

# Title
wb$add_data(sheet = SHEET3, x = "Baseline vs Post-HL Comparison - By Category",
            start_row = 1, start_col = 1)
# ... styling

# Headers
headers3 <- c("Cancer Site Category", "Baseline Patients", "Post-HL Patients", "Delta", "% Retained")
# ... add headers with styling

# Data
wb$add_data(sheet = SHEET3, x = as.data.frame(comparison_df),
            start_row = 3, col_names = FALSE)
# ... number formatting
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Separate scripts for patient-code and table outputs (R/53 + R/54) | Single consolidated script (R/55) | Phase 55 (May 2026) | R/56 follows R/55 pattern: single script for all outputs |
| TUMOR_REGISTRY-preferred first diagnosis date (R/02) | True minimum via pmin() across DIAGNOSIS + TUMOR_REGISTRY (R/55) | Phase 55 (May 2026) | R/56 consumes confirmed_hl_cohort.rds with true minimum dates |
| Manual before/after logging | tidylog automatic attrition logging | Project inception | R/56 should use tidylog if available for automatic logging |
| openxlsx (original) | openxlsx2 | Feb 2026 (openxlsx2 1.0 release) | R/56 uses openxlsx2 like R/55 |

**Deprecated/outdated:**
- openxlsx (original package): Replaced by openxlsx2 with better API and performance
- >= for post-diagnosis filtering: Ambiguous temporal precedence; strict > is clearer

## Open Questions

1. **DX_DATE missing values in cancer_summary.csv**
   - What we know: R/55 uses DX_DATE from cancer_summary.csv (originally from R/53)
   - What's unclear: How many cancer diagnosis rows have NA DX_DATE? Does temporal filter need additional NA handling?
   - Recommendation: Add `filter(!is.na(DX_DATE))` before temporal comparison to avoid NA > date producing NA rows

2. **Baseline count extraction method**
   - What we know: Comparison sheet needs baseline counts per category
   - What's unclear: Read from cancer_summary_table.xlsx (formatted, has title row) or regenerate from cancer_summary.csv (raw data)?
   - Recommendation: Read from cancer_summary_table.xlsx for consistency with user-visible baseline; skip title/header rows carefully

3. **Category column in cancer_summary.csv**
   - What we know: R/55 adds category column via classify_codes() before writing outputs
   - What's unclear: Is category column present in cancer_summary.csv, or only in internal R/55 dataframes?
   - Recommendation: If category is not in CSV, either (a) read cancer_summary.csv and call classify_codes() again (requires copying PREFIX_MAP), or (b) read cancer_summary.xlsx which may have category. Verify during implementation.

## Immortal Time Bias Awareness

### What Is Immortal Time Bias?

Immortal time bias occurs in observational studies when a period exists during which the outcome event (e.g., death, second cancer) cannot occur by design. In this phase:

- **The bias:** Patients who died BEFORE their first HL diagnosis are excluded from the post-HL cohort entirely (they have no post-HL cancer diagnoses). This artificially inflates survival and reduces observed cancer burden in the post-HL group.
- **Why it happens:** Temporal filtering creates a "must survive to first HL diagnosis" requirement. Patients who died earlier are not in the cohort.
- **Mitigation:** Clear EXPLORATORY labeling (D-04, D-05) warns analysts not to treat post-HL counts as equivalent to baseline. Comparison sheet shows excluded counts.

### Clinical Implications

Post-HL cancer summary answers: "Of cancers that occurred AFTER HL diagnosis, what is the distribution?" It does NOT answer: "What is the cancer burden in HL patients?" (that's the baseline). Use cases:

- **Valid:** Exploring second malignancies after HL treatment
- **Valid:** Comparing cancer site distributions pre-HL vs post-HL
- **Invalid:** Estimating overall cancer prevalence in HL cohort (use baseline)
- **Invalid:** Survival or time-to-event analysis without landmark adjustment

### Labeling Strategy (per D-04, D-05)

- **Sheet names:** "EXPLORATORY - Category Summary" and "EXPLORATORY - Code Summary" flag outputs as exploratory-only
- **Footnote:** "Note: Post-HL filter introduces potential immortal time bias. Use for exploratory comparison only." on every data sheet
- **Comparison sheet:** Shows excluded patients/codes to quantify bias impact

## Environment Availability

Skip this section — Phase 56 has no external dependencies beyond existing R packages already in project renv.lock.

## Validation Architecture

Skip this section — workflow.nyquist_validation is explicitly set to false in .planning/config.json.

## Sources

### Primary (HIGH confidence)
- [dplyr filter() official documentation](https://dplyr.tidyverse.org/reference/filter.html) - Date filtering with > operator
- [openxlsx2 CRAN documentation](https://cran.r-project.org/web/packages/openxlsx2/openxlsx2.pdf) - Multi-sheet workbook API (April 2026 update)
- [openxlsx2 basic manual](https://cloud.r-project.org/web/packages/openxlsx2/vignettes/openxlsx2.html) - Workbook creation and styling
- R/55_cancer_summary_refined.R (lines 525-673) - Aggregation and styled xlsx pattern (project source)
- .planning/phases/55-cancer-summary-refinement-foundation/55-01-SUMMARY.md - confirmed_hl_cohort.rds schema

### Secondary (MEDIUM confidence)
- [Learning To Filter Data By Date Using Dplyr In R](https://statistics.arabpsychology.com/filter-by-date-using-dplyr/) - Date comparison examples
- [How to Filter by Date Using dplyr - Statology](https://www.statology.org/dplyr-filter-date/) - Date filtering best practices
- [Identifying, handling and impact of immortal time bias (BMC Medical Research Methodology, 2026)](https://link.springer.com/article/10.1186/s12874-025-02739-3) - Systematic review of immortal time bias in observational studies
- [Immortal time bias in older vs younger age groups (British Journal of Cancer, 2023)](https://www.nature.com/articles/s41416-023-02187-0) - Simulation study with cancer cohort application

### Tertiary (LOW confidence)
- [data.table vs dplyr: A Side-by-Side Comparison (R-bloggers, 2025)](https://www.r-bloggers.com/2025/07/data-table-vs-dplyr-a-side-by-side-comparison/) - General dplyr usage patterns
- [Temporal relationship of computed and structured diagnoses in EHR data (PMC, 2021)](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC7890604/) - Background on same-day diagnosis challenges

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All libraries already in project renv.lock; no new installations
- Architecture: HIGH - R/55 provides complete pattern to replicate; temporal filter is trivial dplyr operation
- Pitfalls: HIGH - Edge cases (NA dates, same-day diagnoses) well-documented in clinical literature and project history
- Immortal time bias: HIGH - Recent 2026 systematic review provides authoritative guidance; labeling strategy directly addresses bias

**Research date:** 2026-05-22
**Valid until:** 2026-06-22 (30 days for stable domain)
