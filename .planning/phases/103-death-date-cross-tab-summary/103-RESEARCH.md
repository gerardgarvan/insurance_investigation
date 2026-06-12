# Phase 103: Death Date Cross-Tab Summary - Research

**Researched:** 2026-06-12
**Domain:** R data summarization, cross-tabulation, Excel output formatting
**Confidence:** HIGH

## Summary

Phase 103 produces a clean, meeting-presentable death date cross-tab summary answering three team questions: (i) how many patients have a death date, (ii) of those, how many have death as their last encounter, (iii) how many have encounters after death. The phase creates a standalone investigation script (R/59_death_date_summary.R) that reads existing artifacts from Phase 59 (R/53 validated_death_dates.rds) and Phase 55/20 (confirmed_hl_cohort.rds), performs verification against Phase 62 (R/29) metrics, and outputs a styled xlsx file ready for team presentation without additional formatting.

This is a pure data summarization task with no new analysis logic — all death date validation and post-death activity detection already exists in R/53. The challenge is presentation: cascading summary structure (cohort → death date → last encounter → post-death), clean xlsx formatting, HIPAA awareness, and count verification against existing R/29 analysis.

**Primary recommendation:** Follow established investigation script pattern (R/30, R/58) — standalone R/59, reads existing RDS artifacts, produces styled xlsx output, adds R/88 validation section for structural checks. Use existing openxlsx2 workbook patterns from R/29/R/53/R/57/R/58 for consistent formatting. Verification against R/29 Section 4 counts is mandatory for success criteria #2.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** New standalone script: R/59_death_date_summary.R. Self-contained investigation pattern (like R/30, R/58). Reads existing artifacts, produces its own output. Clean separation from first-line therapy logic in R/29.
- **D-02:** Reads validated_death_dates.rds (from R/53 Phase 59) and queries DuckDB ENCOUNTER table for last-encounter and post-death timing. Also reads confirmed_hl_cohort.rds for cohort denominator.
- **D-03:** Cascading summary structure: rows flow top-to-bottom from total cohort → patients with death date → death is last encounter → encounters after death. Each row shows count and percentage of cohort.
- **D-04:** First row = total confirmed HL cohort patients (from confirmed_hl_cohort.rds) as denominator. Makes percentages meaningful (e.g., "42 of 500 (8.4%) have a death date").
- **D-05:** Success criteria #2 requires counts match existing Phase 62 data (R/29 death analysis). Script should log comparison against R/29 metrics for verification.
- **D-06:** Raw counts in xlsx output — NO automatic <11 suppression applied. HIPAA suppression applied manually before sharing/presenting. This allows internal review with exact numbers.
- **D-07:** Single xlsx file: death_date_summary.xlsx in output/ directory. Meeting-presentable formatting (styled headers, labeled rows, clear percentages).
- **D-08:** Success criteria #3 requires no additional formatting needed for team meeting presentation — styled xlsx with clear labels, readable column widths.

### Claude's Discretion
- Column ordering and exact row labels in the summary table
- Whether to include additional context rows (e.g., "patients with death date but no treatment records" from R/53)
- Console logging structure and verification messages
- R/88 smoke test validation section structure and check count
- Whether to add a second sheet with post-death encounter detail by ENC_TYPE (already computed in R/29)

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| DEATH-01 | Unstratified cross-tab table answering: (i) how many patients have a death date, (ii) of those how many have death as their last encounter, (iii) how many have encounters after their death date | All three metrics already computed in R/29 Section 4 (lines 222-256); R/53 provides validated_death_dates.rds with post_death_activity flag; DuckDB ENCOUNTER table provides last encounter date comparison |

</phase_requirements>

## Standard Stack

### Core Libraries
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| dplyr | 1.2.0+ | Data manipulation | Standard tidyverse filter/join/mutate for combining RDS artifacts |
| glue | 1.8.0 | String interpolation | Console logging with embedded expressions — project standard |
| openxlsx2 | 1.9+ | Excel workbook creation | Modern replacement for openxlsx; used in R/29, R/53, R/57, R/58 for styled xlsx output |
| lubridate | 1.9.3+ | Date operations | Already in use project-wide for date parsing and arithmetic |

### Supporting Libraries
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| stringr | 1.5.1+ | String operations | May be needed for formatting labels, percentage display |
| checkmate | 2.3.2+ | Assertions | Used in R/58 for argument validation — optional but consistent with recent phases |

### Installation
Already installed as part of project dependencies. No new package installation required.

## Architecture Patterns

### Recommended Script Structure
```
R/59_death_date_summary.R
├── SECTION 1: SETUP AND CONFIGURATION
│   ├── Library loading (dplyr, glue, openxlsx2)
│   ├── Source R/00_config.R, R/utils/utils_assertions.R, R/utils/utils_duckdb.R
│   ├── Define output paths (OUTPUT_XLSX)
│   └── Log file setup (optional — R/58 pattern)
├── SECTION 2: INPUT VALIDATION
│   ├── assert_rds_exists() for validated_death_dates.rds
│   ├── assert_rds_exists() for confirmed_hl_cohort.rds
│   └── Check DuckDB ENCOUNTER table availability
├── SECTION 3: LOAD DATA
│   ├── Load validated_death_dates.rds (ID, DEATH_DATE, death_valid, post_death_activity)
│   ├── Load confirmed_hl_cohort.rds (ID, first_hl_dx_date, first_hl_dx_source)
│   ├── Open DuckDB connection and query ENCOUNTER for last encounter dates
│   └── Log row counts at each step
├── SECTION 4: COMPUTE SUMMARY METRICS (per D-03, D-04, D-05)
│   ├── Metric 1: Total confirmed HL cohort (nrow(confirmed_hl_cohort))
│   ├── Metric 2: Patients with validated death dates (filter death_valid == TRUE)
│   ├── Metric 3: Death is last encounter (compare DEATH_DATE >= max(ADMIT_DATE) by ID)
│   ├── Metric 4: Post-death clinical activity (sum post_death_activity flag)
│   └── Log counts AND compare to R/29 Section 4 values for verification
├── SECTION 5: BUILD SUMMARY TABLE
│   ├── Create cascading tibble with Metric + Count + Percent columns
│   ├── Percentages relative to total cohort (D-04)
│   └── Clear row labels (per D-08 — meeting-presentable)
├── SECTION 6: CREATE STYLED XLSX (per D-07, D-08)
│   ├── wb_workbook() + add_worksheet("Death Date Summary")
│   ├── Header row styling (dark gray background, white bold text)
│   ├── Number formatting (#,##0 for counts, 0.0% for percentages)
│   ├── Column width auto-fitting
│   ├── Freeze pane on header row
│   └── wb_save() to output/death_date_summary.xlsx
└── SECTION 7: FINAL SUMMARY
    ├── Log output file path
    ├── Log key metrics (3 DEATH-01 answers)
    └── Log verification status vs R/29 counts
```

### Pattern 1: Investigation Script (R/30, R/58)
**What:** Standalone R script that reads existing artifacts, performs analysis, produces xlsx/csv output, does NOT save RDS or modify upstream files.

**When to use:** Phase 103 (per D-01, D-10) — self-contained death date summary, no upstream modification.

**Example structure:**
```r
# From R/58_co_administration_analysis.R (Phase 102)
# SECTION 1: SETUP
suppressPackageStartupMessages({
  library(dplyr)
  library(glue)
  library(openxlsx2)
})

source("R/00_config.R")
source("R/utils/utils_assertions.R")

# Define paths
DETAIL_RDS <- file.path(CONFIG$cache$outputs_dir, "treatment_episode_detail.rds")
OUTPUT_XLSX <- file.path(CONFIG$output_dir, "co_administration_analysis.xlsx")

# SECTION 2: INPUT VALIDATION
assert_rds_exists(DETAIL_RDS, script_name = "R/58")

# SECTION 3: LOAD DATA
detail <- readRDS(DETAIL_RDS)
message(glue("Loaded detail: {nrow(detail)} rows"))

# SECTION 4: ANALYSIS
# ... (analysis logic here)

# SECTION 5: CREATE XLSX
wb <- wb_workbook()
wb$add_worksheet("Summary")
wb$add_data(sheet = "Summary", x = summary_table, start_row = 1, start_col = 1)
# ... (styling)
wb_save(wb, OUTPUT_XLSX, overwrite = TRUE)
message(glue("Saved: {OUTPUT_XLSX}"))
```

### Pattern 2: Styled XLSX Workbook (R/29, R/53, R/57, R/58)
**What:** openxlsx2 workbook with consistent header styling, number formatting, freeze panes.

**When to use:** All xlsx outputs in project — meeting-presentable tables.

**Example:**
```r
# From R/29_first_line_and_death_analysis.R Section 5
wb <- wb_workbook()
wb$add_worksheet("Death Analysis Summary")

summary_stats <- tibble(
  Metric = c(
    "Total patients with validated death dates (DEATH-01)",
    "Death is last encounter (DEATH-02)",
    "Patients with post-death clinical activity (DEATH-03)"
  ),
  Count = c(n_with_death, n_death_is_last, n_post_death)
)

wb$add_data(sheet = "Death Analysis Summary", x = summary_stats, start_row = 1, start_col = 1)

# Style header row (dark gray background, white bold text)
wb$add_fill(sheet = "Death Analysis Summary", dims = "A1:B1", color = wb_color("FF374151"))
wb$add_font(
  sheet = "Death Analysis Summary", dims = "A1:B1",
  name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF")
)
wb$set_col_widths(sheet = "Death Analysis Summary", cols = 1:2, widths = c(60, 15))
wb$freeze_pane(sheet = "Death Analysis Summary", firstActiveRow = 2)

wb_save(wb, OUTPUT_XLSX, overwrite = TRUE)
```

### Pattern 3: Metric Verification Logging
**What:** Console messages comparing computed metrics to expected values from upstream scripts.

**When to use:** Phase 103 D-05 — verify R/59 counts match R/29 Section 4 for data integrity.

**Example:**
```r
# Compute metrics
n_with_death <- nrow(valid_deaths)
n_death_is_last <- sum(death_vs_encounter$death_is_last, na.rm = TRUE)
n_post_death <- sum(valid_deaths$post_death_activity, na.rm = TRUE)

# Log and compare to R/29 expected values (read from R/29 output or hardcode expected)
message(glue("  DEATH-01 (patients with death date): {n_with_death}"))
message(glue("  DEATH-02 (death is last encounter): {n_death_is_last}"))
message(glue("  DEATH-03 (post-death activity): {n_post_death}"))

# Verification (optional: read R/29 output and compare programmatically)
message("\n--- Verification vs R/29 Section 4 ---")
message("  Expected counts from R/29 death_analysis.xlsx:")
message("    DEATH-01: [read from R/29 output or log manually]")
message("    DEATH-02: [read from R/29 output or log manually]")
message("    DEATH-03: [read from R/29 output or log manually]")
message("  Status: [MATCH/MISMATCH — manual check or programmatic comparison]")
```

### Anti-Patterns to Avoid
- **Don't modify R/29 or R/53:** Phase 103 is standalone investigation (D-01, D-10) — no upstream file modification.
- **Don't save RDS artifacts:** Investigation scripts produce xlsx/csv only (D-07).
- **Don't apply automatic HIPAA suppression:** D-06 requires raw counts in xlsx; suppression is manual before sharing.
- **Don't skip verification:** D-05 requires count comparison to R/29 — this is a data integrity check, not optional.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Excel workbook styling | Manual cell formatting loops, hardcoded cell references | openxlsx2 wb_* functions with dims parameters | Project-standard pattern (R/29, R/53, R/57, R/58); wb_color(), wb_add_fill(), wb_set_col_widths() handle styling declaratively |
| Count verification | Manual count comparison, eyeball checking | Structured logging with glue + programmatic comparison (optional) | Success criteria #2 requires verification — structured logging makes this auditable; could read R/29 output xlsx and compare programmatically |
| DuckDB connection management | Manual DBI connection setup/teardown | R/utils/utils_duckdb.R: open_pcornet_con(), close_pcornet_con(), get_pcornet_table() | Already abstracted in project utilities (used in R/29, R/53) — consistent error handling and connection pooling |
| Date parsing | lubridate ad-hoc parsing | R/utils/utils_dates.R: parse_pcornet_date() | Project utility handles PCORnet date formats and 1900 sentinel values consistently |

**Key insight:** Phase 103 assembles existing components (R/53 validation, R/29 metrics, confirmed_hl_cohort) into a presentation-ready summary. The work is data wrangling and xlsx styling — not new analysis logic.

## Common Pitfalls

### Pitfall 1: Denominator Mismatch
**What goes wrong:** Using death date count as denominator instead of total cohort makes percentages misleading. "100 of 42 (238%) have post-death activity" is nonsensical.

**Why it happens:** Natural to use "patients with death dates" as the population, but team question is "what % of our cohort died, and of those who died, what % have data issues?"

**How to avoid:** D-04 decision locks total cohort as denominator. First row of summary table = nrow(confirmed_hl_cohort). All percentages are "X of total cohort (Y%)".

**Warning signs:** Percentages > 100%, or denominator changing between rows.

### Pitfall 2: R/29 Count Mismatch Due to Filtering Differences
**What goes wrong:** R/59 computes n_with_death = 50, but R/29 shows 48. Verification fails, trust in data erodes.

**Why it happens:** R/29 filters to death_valid == TRUE (validated deaths only), but if R/59 uses all deaths from validated_death_dates.rds without filtering, counts differ.

**How to avoid:** Both scripts MUST filter death_valid == TRUE before counting. R/29 Section 4 line 220: `valid_deaths <- validated_deaths %>% filter(death_valid == TRUE)`. R/59 must replicate this filter exactly.

**Warning signs:** Count discrepancies of 1-5 patients; check filter conditions in both scripts.

### Pitfall 3: HIPAA Suppression Applied Too Early
**What goes wrong:** Script applies <11 suppression to xlsx output, but internal reviewers can't verify exact counts.

**Why it happens:** Reflexive HIPAA compliance — assumption that all outputs need suppression.

**How to avoid:** D-06 decision explicitly states raw counts in xlsx output, manual suppression before sharing. Internal review needs exact numbers for validation.

**Warning signs:** Counts showing "<11" in xlsx when team needs to verify against R/29.

### Pitfall 4: "Death is Last Encounter" Logic Error
**What goes wrong:** Patient with death_date = 2023-05-15 and last_encounter_date = 2023-05-16 incorrectly flagged as "death is last encounter."

**Why it happens:** Using >= instead of > for comparison, or not handling NA encounter dates properly.

**How to avoid:** Follow R/29 Section 4 logic exactly (lines 238-247):
```r
death_is_last = case_when(
  is.na(last_encounter_date) ~ TRUE,  # No encounters → death is "last" by default
  DEATH_DATE >= last_encounter_date ~ TRUE,
  TRUE ~ FALSE
)
```

**Warning signs:** Patients with encounters dated AFTER death showing as "death is last encounter."

### Pitfall 5: Missing Input File Crashes Script Mid-Execution
**What goes wrong:** Script runs for 30 seconds loading data, then crashes on missing confirmed_hl_cohort.rds — wasted time and confusing error.

**Why it happens:** Input validation happens after data loading instead of upfront.

**How to avoid:** SECTION 2 (before any data loading) uses assert_rds_exists() for all RDS inputs. Fail fast with clear error message.

**Warning signs:** Error messages deep in script execution instead of immediate validation failure.

## Code Examples

Verified patterns from existing project code:

### Core Metric Computation (from R/29 Section 4)
```r
# Source: R/29_first_line_and_death_analysis.R lines 218-256
# DEATH-01: Patients with validated death dates
valid_deaths <- validated_deaths %>%
  filter(death_valid == TRUE)

n_with_death <- nrow(valid_deaths)
message(glue("  DEATH-01: Patients with validated death dates: {n_with_death}"))

# DEATH-02: Death as last encounter
last_encounters <- get_pcornet_table("ENCOUNTER") %>%
  select(ID, ADMIT_DATE) %>%
  collect() %>%
  mutate(ADMIT_DATE = parse_pcornet_date(ADMIT_DATE)) %>%
  filter(!is.na(ADMIT_DATE)) %>%
  group_by(ID) %>%
  summarise(last_encounter_date = max(ADMIT_DATE), .groups = "drop")

death_vs_encounter <- valid_deaths %>%
  left_join(last_encounters, by = "ID") %>%
  mutate(
    death_is_last = case_when(
      is.na(last_encounter_date) ~ TRUE,
      DEATH_DATE >= last_encounter_date ~ TRUE,
      TRUE ~ FALSE
    )
  )

n_death_is_last <- sum(death_vs_encounter$death_is_last, na.rm = TRUE)
message(glue("  DEATH-02: Death is last encounter: {n_death_is_last}"))

# DEATH-03: Post-death activity (from Phase 59 flag)
n_post_death <- sum(valid_deaths$post_death_activity, na.rm = TRUE)
message(glue("  DEATH-03: Patients with post-death activity: {n_post_death}"))
```

### Styled XLSX Workbook Creation (from R/53 Section 8)
```r
# Source: R/53_death_date_validation.R lines 406-486
wb <- wb_workbook()
wb$add_worksheet("Validation Summary")

# Title row (A1)
wb$add_data(
  sheet = "Validation Summary", x = "Death Date Validation Report",
  start_row = 1, start_col = 1
)
wb$add_font(
  sheet = "Validation Summary", dims = "A1",
  name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937")
)
wb$merge_cells(sheet = "Validation Summary", dims = "A1:D1")

# Subtitle row (A2)
subtitle <- glue("Generated: {Sys.Date()} | Population: All patients with death dates")
wb$add_data(sheet = "Validation Summary", x = subtitle, start_row = 2, start_col = 1)
wb$add_font(
  sheet = "Validation Summary", dims = "A2",
  name = "Calibri", size = 10, color = wb_color("FF6B7280")
)
wb$merge_cells(sheet = "Validation Summary", dims = "A2:D2")

# Summary statistics table starting row 4
summary_stats <- tibble(
  Metric = c(
    "Total patients with death dates",
    "Valid death dates retained",
    "Patients with post-death clinical activity"
  ),
  Count = c(nrow(death_data), sum(valid_deaths$death_valid), sum(valid_deaths$post_death_activity))
)

wb$add_data(sheet = "Validation Summary", x = summary_stats, start_row = 4, start_col = 1)

# Header row styling (row 4)
wb$add_fill(sheet = "Validation Summary", dims = "A4:B4", color = wb_color("FF374151"))
wb$add_font(
  sheet = "Validation Summary", dims = "A4:B4",
  name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF")
)

# Number formatting (count column)
data_rows <- glue("B5:B{4 + nrow(summary_stats)}")
wb$add_numfmt(sheet = "Validation Summary", dims = data_rows, numfmt = "#,##0")

# Column widths
wb$set_col_widths(sheet = "Validation Summary", cols = 1:2, widths = c(55, 15))

# Freeze pane below header row
wb$freeze_pane(sheet = "Validation Summary", firstActiveRow = 5)

# Save
wb_save(wb, OUTPUT_XLSX, overwrite = TRUE)
message(glue("Saved XLSX report: {OUTPUT_XLSX}"))
```

### Input Validation Pattern (from R/58)
```r
# Source: R/58_co_administration_analysis.R lines 70-80
# SECTION 2: INPUT VALIDATION
assert_rds_exists(DETAIL_RDS, script_name = "R/58")
assert_rds_exists(EPISODES_RDS, script_name = "R/58")

if (!file.exists(REFERENCE_XLSX)) {
  stop(glue("[R/58] REFERENCE_XLSX not found: {REFERENCE_XLSX}"))
}

# SECTION 3: LOAD DATA
detail <- readRDS(DETAIL_RDS)
message(glue("  Loaded treatment_episode_detail.rds: {nrow(detail)} rows"))

episodes <- readRDS(EPISODES_RDS)
message(glue("  Loaded treatment_episodes.rds: {nrow(episodes)} episodes"))
```

### Cascading Summary Table Structure
```r
# Recommendation for R/59 (not in existing code — new pattern)
# Per D-03: Top-to-bottom cascading structure with percentages of total cohort

# Load cohort for denominator
cohort <- readRDS(COHORT_RDS)
total_cohort <- nrow(cohort)

# Compute metrics
n_with_death <- nrow(valid_deaths)
n_death_is_last <- sum(death_vs_encounter$death_is_last, na.rm = TRUE)
n_post_death <- sum(valid_deaths$post_death_activity, na.rm = TRUE)

# Build cascading table
summary_table <- tibble(
  Metric = c(
    "Total confirmed HL cohort patients",
    "Patients with validated death date",
    "  - Death is last encounter",
    "  - Encounters after death date"
  ),
  Count = c(total_cohort, n_with_death, n_death_is_last, n_post_death),
  Percent = c(
    100.0,
    round(100 * n_with_death / total_cohort, 1),
    round(100 * n_death_is_last / total_cohort, 1),
    round(100 * n_post_death / total_cohort, 1)
  )
)

# Add percent column formatting in xlsx
wb$add_numfmt(sheet = "Summary", dims = "C2:C5", numfmt = "0.0\"%\"")
```

## Environment Availability

> Phase 103 has no external dependencies beyond the R project stack (already installed). All required data sources are internal RDS artifacts or DuckDB tables created by prior phases.

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| R | Script execution | ✓ | 4.4.2+ (HiPerGator module) | — |
| dplyr | Data manipulation | ✓ | 1.2.0+ (tidyverse) | — |
| glue | String interpolation | ✓ | 1.8.0 | — |
| openxlsx2 | Excel output | ✓ | 1.9+ | — |
| lubridate | Date parsing | ✓ | 1.9.3+ (tidyverse) | — |
| validated_death_dates.rds | Death date data | ✓ | Created by R/53 Phase 59 | Fail if missing (assert_rds_exists) |
| confirmed_hl_cohort.rds | Cohort denominator | ✓ | Created by R/55 Phase 55 | Fail if missing (assert_rds_exists) |
| DuckDB ENCOUNTER table | Last encounter dates | ✓ | Created by R/25 Phase 29 | Fail if missing (get_pcornet_table check) |

**Missing dependencies with no fallback:**
- None — all dependencies are part of the established project infrastructure.

**Missing dependencies with fallback:**
- None identified.

## Validation Architecture (R/88 Smoke Test)

> Validation section required — workflow.nyquist_validation is NOT explicitly set to false in .planning/config.json.

### Test Framework
| Property | Value |
|----------|-------|
| Framework | R native (no external test framework) |
| Config file | None — R/88 is standalone smoke test script |
| Quick run command | `Rscript R/88_smoke_test_comprehensive.R` |
| Full suite command | `Rscript R/88_smoke_test_comprehensive.R` (same — single comprehensive test) |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| DEATH-01 | R/59 produces death_date_summary.xlsx with 3 metrics (patients with death date, death is last encounter, post-death activity) | Structural smoke test | `Rscript R/88_smoke_test_comprehensive.R` (new section) | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** `Rscript R/88_smoke_test_comprehensive.R` (runs in < 5 seconds, validates file structure)
- **Per wave merge:** Same (single comprehensive test)
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] R/88 Section 32: Phase 103 validation — checks R/59 script exists, sources R/00_config.R and utils, output xlsx file structure (sheet name, column names)
- [ ] R/88 check: death_date_summary.xlsx has "Death Date Summary" sheet with Metric, Count, Percent columns

*(Pattern: Follow R/88 Section 31B Phase 102 validation — check script exists, key patterns present in code, xlsx structure if file exists)*

## Sources

### Primary (HIGH confidence)
- R/29_first_line_and_death_analysis.R (Section 4, lines 213-285) — canonical death date analysis logic, verified production code
- R/53_death_date_validation.R (Sections 2-7) — validated_death_dates.rds structure and post_death_activity flag computation
- R/58_co_administration_analysis.R — investigation script pattern (standalone, xlsx output, no RDS save)
- R/88_smoke_test_comprehensive.R (Sections 31A, 31B) — validation section patterns for Phase 101-102
- .planning/phases/103-death-date-cross-tab-summary/103-CONTEXT.md — user decisions D-01 through D-08
- .planning/REQUIREMENTS.md — DEATH-01 requirement definition

### Secondary (MEDIUM confidence)
- R/00_config.R — CONFIG paths and utility auto-sourcing (lines 1-150)
- R/utils/utils_assertions.R — assert_rds_exists(), assert_df_valid() usage patterns
- R/utils/utils_duckdb.R — get_pcornet_table(), open/close_pcornet_con() usage patterns
- openxlsx2 package documentation (CRAN) — wb_* function reference for styling

### Tertiary (LOW confidence)
- None — all research findings verified against project codebase or official R package documentation.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all libraries already in use (R/29, R/53, R/57, R/58 precedent)
- Architecture patterns: HIGH — investigation script pattern (R/30, R/58), styled xlsx workbook (R/29, R/53), metric verification (R/29 Section 4)
- Common pitfalls: MEDIUM — inferred from D-04 (denominator decision), D-05 (verification requirement), D-06 (HIPAA suppression timing)
- Environment availability: HIGH — all dependencies verified as existing project infrastructure
- Validation architecture: MEDIUM — R/88 pattern extrapolated from Section 31B (Phase 102), new section needed for Phase 103

**Research date:** 2026-06-12
**Valid until:** 2026-07-12 (stable stack, no fast-moving dependencies)
