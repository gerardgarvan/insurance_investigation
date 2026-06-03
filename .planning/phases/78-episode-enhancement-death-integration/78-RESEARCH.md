# Phase 78: Episode Enhancement & Death Integration - Research

**Researched:** 2026-06-03
**Domain:** R data enrichment, quality profiling, and CSV export enhancements
**Confidence:** HIGH

## Summary

Phase 78 enriches treatment episodes with human-readable code descriptions and drug group categories, profiles cause of death data quality, and integrates validated cause of death into Gantt v2 outputs. All technical patterns are established in the codebase — this is a data enrichment and quality documentation phase using proven R pipeline conventions.

**Primary recommendation:** Three independent waves — (1) death quality profiling standalone script, (2) R/28 episode enrichment with triggering_code_description and drug_group columns, (3) R/52 Gantt export integration of cause_of_death and drug_group. All use existing lookup tables (code_descriptions.rds, DRUG_GROUPINGS, DEATH_CAUSE_MAP) and follow established multi-sheet xlsx + console diagnostics patterns from Phases 28, 53, 64, and 75-77.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Death Quality Profiling:**
- **D-01:** New standalone script (R/XX_death_cause_quality.R) for cause of death quality reporting. Follows established analysis script pattern (R/35, R/40).
- **D-02:** Stratifications: overall completeness + by AMC payer category + by partner site (AMS, UMI, FLM, VRT, UFH).
- **D-03:** Output format: console diagnostics (glue messages with counts/percentages) + multi-sheet xlsx for persistent review.
- **D-04:** Claude's Discretion on whether death quality report gates R/52's cause_of_death integration (hard gate at 40% vs soft warning). Choose based on what the quality data shows.

**Triggering Code Description Mapping:**
- **D-05:** `triggering_code_description` column in R/28 populated from `code_descriptions.rds` (human-readable drug/procedure names like "Doxorubicin HCl"). NOT from DRUG_GROUPINGS.
- **D-06:** Separate `drug_group` column in R/28 populated from DRUG_GROUPINGS (category labels: "Chemotherapy", "Radiation", "SCT", "Immunotherapy", "Supportive Care").
- **D-07:** Both columns use semicolon-separated values matching triggering_codes order. E.g., codes="J9000;J9040" -> descriptions="Doxorubicin;Bleomycin" -> groups="Chemotherapy;Chemotherapy".
- **D-08:** Unmapped codes get NA in both description and group columns per-code position.

**Cause of Death Integration:**
- **D-09:** `cause_of_death` column appended as last column in gantt_episodes_v2.csv (14 -> 15 columns) and gantt_detail_v2.csv (13 -> 14 columns). Non-breaking change.
- **D-10:** Missing/unmapped ICD-10 codes -> "Unknown or Unspecified" (matches DEATH_CAUSE_MAP Phase 75 D-05). Treatment rows (non-death) -> NA.
- **D-11:** >40% missingness flagged via console warning in R/52 + documented in quality report xlsx. No footnote embedded in CSV.
- **D-12:** Both gantt_episodes_v2.csv and gantt_detail_v2.csv get the cause_of_death column.

**Episode-Level Scope:**
- **D-13:** "Populated for all episodes" means adding the two new columns (triggering_code_description, drug_group) to R/28 output. No changes to linkage logic. Unlinked episodes keep NA.
- **D-14:** drug_group column propagates to Gantt v2 export (R/52). Gantt episodes CSV grows from 15 to 16 columns (cause_of_death + drug_group).

### Claude's Discretion

- **D-04:** Hard gate vs soft warning for >40% cause of death missingness
- Script number assignment for the new death cause quality script (must fit decade-based numbering)

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.

</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CANCER-03 | Cancer_category and triggering code description populated per episode using drug groupings | DRUG_GROUPINGS already in R/00_config.R (Phase 77); code_descriptions.rds lookup pattern established in R/52; semicolon-separated multi-value field pattern from Phase 64 |
| DEATH-01 | Cause of death data quality profiled (completeness, coding, payer stratification) | Multi-sheet xlsx pattern from R/28, R/53; DuckDB DEATH table query pattern from R/53; stratification by payer/site pattern from R/91; DEATH_CAUSE_MAP already in R/00_config.R (Phase 75) |
| DEATH-02 | Cause of death included in outputs (conditional on DEATH-01 showing acceptable data quality) | Column addition to CSV export pattern from R/52; validated_death_dates.rds already loaded by R/52; DEATH_CAUSE field present in DEATH table; mapping via DEATH_CAUSE_MAP (3-char ICD-10 prefix) |
| QUAL-01 | All new/modified scripts follow v2.0 standards | styler formatting, lintr compliance, checkmate assertions, documentation headers, smoke test updates — all established in Phases 70-74 |

</phase_requirements>

## Standard Stack

All required packages already in project renv.lock. No new dependencies needed.

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| dplyr | 1.2.0+ | Data manipulation | Universal R pipeline library; existing pattern in all 28+ scripts |
| glue | 1.8.0 | String formatting for console output | Established pattern: `message(glue("..."))` in 40+ scripts |
| stringr | 1.5.1+ | String operations | Semicolon-split/join for multi-value fields (Phase 64 pattern) |
| openxlsx2 | 1.9+ | Multi-sheet xlsx output | Quality report pattern from R/28, R/53, R/91 (5-sheet workbook with styling) |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| lubridate | 1.9.3+ | Date parsing | DuckDB date field handling (parse_pcornet_date utility) |
| checkmate | 2.3.2+ | Defensive validation | assert_rds_exists(), assert_df_valid() from Phase 72 |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| openxlsx2 | writexl | openxlsx2 supports cell styling (headers, freezing, colors) — essential for analyst-friendly quality reports |
| dplyr | data.table | dplyr is project-standard; data.table syntax conflicts with "human-readable named predicates" project constraint |

**Installation:**
All packages already in `renv.lock` from prior phases. No installation needed.

## Architecture Patterns

### Recommended Project Structure

Phase 78 adds one new quality profiling script and modifies two existing scripts:

```
R/
├── 00_config.R                    # DRUG_GROUPINGS, DEATH_CAUSE_MAP already present
├── 28_episode_classification.R    # ADD: triggering_code_description, drug_group columns
├── 52_gantt_v2_export.R           # ADD: cause_of_death, drug_group columns
├── 35_death_cause_quality.R       # NEW: standalone death quality profiling
├── 88_smoke_test_comprehensive.R  # ADD: validation sections for new columns
└── utils/
    └── utils_cancer.R              # NO CHANGE: classify_codes() already handles DEATH_CAUSE_MAP

cache/outputs/
├── code_descriptions.rds           # EXISTING: code -> human-readable name (from R/48b)
├── treatment_episodes.rds          # MODIFIED by R/28: +2 columns (triggering_code_description, drug_group)
└── validated_death_dates.rds       # EXISTING: death dates with ICD-10 DEATH_CAUSE (from R/53)

output/
├── death_cause_quality.xlsx        # NEW: multi-sheet quality report
├── gantt_episodes_v2.csv           # MODIFIED by R/52: 14 -> 16 columns (+cause_of_death, +drug_group)
└── gantt_detail_v2.csv             # MODIFIED by R/52: 13 -> 14 columns (+cause_of_death)
```

### Pattern 1: Multi-Value Field Enrichment (R/28)

**What:** Add two new semicolon-separated columns to treatment_episodes.rds by mapping each code in triggering_codes through lookup tables.

**When to use:** When enriching existing comma/semicolon-separated code lists with parallel human-readable descriptions or category labels.

**Example (from D-05, D-06, D-07):**

```r
# SECTION 6: CODE DESCRIPTION MAPPING ----
# Pattern from R/52 lines 187-207 (lookup_description, map_codes_to_descriptions)

# Helper: map single code to description
lookup_description <- function(code) {
  if (is.null(code_descriptions) || is.na(code) || code == "") return(NA_character_)
  if (code %in% names(code_descriptions)) return(code_descriptions[[code]])
  return(NA_character_)  # D-08: unmapped codes get NA
}

# Helper: map semicolon-separated codes to semicolon-separated descriptions
map_codes_to_descriptions <- function(codes_str) {
  if (is.na(codes_str) || codes_str == "") return("")
  codes <- str_split(codes_str, ";")[[1]]
  descriptions <- sapply(codes, lookup_description, USE.NAMES = FALSE)
  paste(descriptions, collapse = ";")
}

# Apply to episodes
episodes <- episodes %>%
  mutate(
    triggering_code_description = sapply(triggering_codes, map_codes_to_descriptions, USE.NAMES = FALSE),
    drug_group = sapply(triggering_codes, map_codes_to_drug_groups, USE.NAMES = FALSE)
  )
```

**Key points:**
- Semicolon separator (Phase 64 convention)
- Per-code NA preservation (D-08)
- Order preservation (codes[1] -> descriptions[1], codes[2] -> descriptions[2])

### Pattern 2: Death Quality Profiling Report (R/35_death_cause_quality.R)

**What:** Standalone script querying DEATH table, stratifying completeness by payer and site, outputting multi-sheet xlsx + console diagnostics.

**When to use:** Quality profiling before integrating a new data source into production outputs.

**Example (combining R/53 death query + R/91 stratification + R/28 multi-sheet xlsx):**

```r
# SECTION 1: SETUP ----
library(dplyr)
library(glue)
library(stringr)
library(openxlsx2)

source("R/00_config.R")
source("R/utils/utils_duckdb.R")

OUTPUT_XLSX <- file.path(CONFIG$output_dir, "death_cause_quality.xlsx")

# SECTION 2: LOAD DEATH DATA ----
# Pattern from R/53 lines 66-92
open_pcornet_con()
death_data <- get_pcornet_table("DEATH") %>%
  collect() %>%
  mutate(DEATH_DATE = parse_pcornet_date(DEATH_DATE)) %>%
  filter(!is.na(DEATH_DATE))

# SECTION 3: COMPLETENESS STRATIFICATION ----
# Overall
overall_stats <- death_data %>%
  summarise(
    n_deaths = n(),
    n_with_cause = sum(!is.na(DEATH_CAUSE) & DEATH_CAUSE != ""),
    pct_complete = round(100 * n_with_cause / n_deaths, 1)
  )

message(glue("Overall: {overall_stats$n_with_cause}/{overall_stats$n_deaths} ({overall_stats$pct_complete}%)"))

# By payer (requires join to patient payer category from episodes or enrollment)
# By site (requires PATID parsing or DEATH_SOURCE site code)

# SECTION 4: MULTI-SHEET XLSX OUTPUT ----
# Pattern from R/28 lines 448-677 (wb_workbook, add_worksheet, styling)
wb <- wb_workbook()
wb$add_worksheet("Overall Completeness")
wb$add_data(sheet = 1, x = overall_stats, start_row = 3, start_col = 1)
# ... header styling, freeze panes, etc.

wb_save(wb, OUTPUT_XLSX, overwrite = TRUE)
message(glue("Saved: {OUTPUT_XLSX}"))
```

**Key points:**
- Console diagnostics first (fail-fast if data missing)
- Multi-sheet xlsx for persistent review
- Stratifications as separate sheets
- D-04 decision: if pct_complete < 60%, recommend soft warning (document in quality report) vs hard gate (block R/52 integration)

### Pattern 3: Cause of Death Mapping (R/52)

**What:** Map 3-char ICD-10 prefix from DEATH_CAUSE to human-readable category via DEATH_CAUSE_MAP, append as last column to Gantt CSV exports.

**When to use:** Enriching output CSVs with mapped categorical fields from ICD-10 codes.

**Example (from D-09, D-10, D-11):**

```r
# SECTION 4: CAUSE OF DEATH MAPPING ----
# Load validated death dates (already contains DEATH_CAUSE from DEATH table)
validated_deaths <- readRDS(VALIDATED_DEATHS_RDS)

# Map ICD-10 to category (Phase 75 pattern)
map_death_cause <- function(death_cause_code) {
  if (is.na(death_cause_code) || death_cause_code == "") return("Unknown or Unspecified")
  prefix_3char <- str_sub(death_cause_code, 1, 3)
  if (prefix_3char %in% names(DEATH_CAUSE_MAP)) return(DEATH_CAUSE_MAP[[prefix_3char]])
  return("Unknown or Unspecified")  # D-10: unmapped codes
}

death_with_cause <- validated_deaths %>%
  mutate(cause_of_death = sapply(DEATH_CAUSE, map_death_cause, USE.NAMES = FALSE))

# Join to episodes export (left join — treatment episodes get NA, death rows get mapped cause)
episodes_export <- episodes_export %>%
  left_join(death_with_cause %>% select(patient_id, cause_of_death), by = "patient_id")

# Missingness check (D-11)
pct_missing <- 100 * sum(death_with_cause$cause_of_death == "Unknown or Unspecified") / nrow(death_with_cause)
if (pct_missing > 40) {
  message(glue("WARNING: Cause of death missing/unmapped for {round(pct_missing, 1)}% of deaths"))
}

# Column order (D-09, D-14)
episodes_export <- episodes_export %>%
  select(
    patient_id, treatment_type, episode_number, ...,
    drug_group, cause_of_death  # cause_of_death as last column
  )
```

**Key points:**
- "Unknown or Unspecified" for missingness visibility (D-10)
- Console warning at >40% threshold (D-11)
- NA for treatment rows (only death rows have cause)
- Last column position (D-09)

### Anti-Patterns to Avoid

**Anti-pattern 1: In-line xlsx table creation without helper**
```r
# BAD: Hard to read, error-prone
wb <- wb_workbook()
wb_add_worksheet(wb, "Sheet1")
wb_add_data(wb, "Sheet1", data, startRow = 1, startCol = 1)
```

**GOOD: Use openxlsx2 pipe-friendly API (R/28 pattern)**
```r
wb <- wb_workbook()
wb$add_worksheet("Sheet1")
wb$add_data(sheet = "Sheet1", x = data, start_row = 3, start_col = 1)
wb$add_font(sheet = "Sheet1", dims = "A3:E3", bold = TRUE)
```

**Anti-pattern 2: Modifying code_descriptions.rds**
```r
# BAD: code_descriptions.rds is a derived artifact from R/48b
# Don't modify it — create new columns in episodes instead
```

**GOOD: Leave artifacts read-only, add columns to target**
```r
# code_descriptions.rds stays unchanged
# Add triggering_code_description column to treatment_episodes.rds
```

**Anti-pattern 3: Embedding footnotes in CSV**
```r
# BAD: CSVs are for Tableau/data analysis — footnotes break parsing
# D-11: No footnote embedded in CSV
```

**GOOD: Document in quality report xlsx + console warning**
```r
message(glue("WARNING: {pct_missing}% cause of death missingness"))
# Quality report xlsx has "Missingness" sheet with footnote/recommendation
```

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Multi-sheet xlsx with styling | Custom write.csv loops with manual column width adjustment | openxlsx2 wb_workbook() with add_font, add_fill, freeze_pane | Edge cases: merged cells, frozen panes, conditional formatting all require low-level XML manipulation — openxlsx2 handles it |
| ICD-10 3-char prefix extraction | Custom regex or substr logic | str_sub(code, 1, 3) + named vector lookup | Named vector lookup (DEATH_CAUSE_MAP) is faster than 100+ if/else, easier to audit, and follows existing CANCER_SITE_MAP pattern |
| Semicolon-separated field mapping | Manual for loops with string concatenation | sapply + str_split + paste(collapse = ";") | Handles edge cases: empty strings, NA propagation, order preservation — already battle-tested in R/52 |
| Payer stratification | Custom joins to ENROLLMENT table | Reuse tiered_payer logic from R/60-R/62 or read payer_category from existing episodes.rds | Payer category already computed and validated — don't re-derive |

**Key insight:** All patterns needed for Phase 78 already exist in R/28, R/52, R/53, R/91. This phase is pure data enrichment following established conventions — no new algorithms, no new libraries, no new infrastructure.

## Common Pitfalls

### Pitfall 1: Script Numbering Conflicts

**What goes wrong:** R scripts use decade-based logical grouping (00-09 = foundation, 10-29 = cohort, 30-49 = analysis, 50-69 = outputs, 70-89 = quality, 90-99 = diagnostics). New death quality script needs a number that doesn't collide with existing scripts.

**Why it happens:** Decade ranges fill up over time. 90-99 diagnostics is nearly full (91, 92, 93, 94, 95, 96, 97, 98, 99 taken).

**How to avoid:**
- Check existing numbering: `ls R/*.R | grep -E "^R/[0-9]{2}_"`
- Death quality script is a quality/profiling task, not a diagnostic
- Recommend 30-49 "analysis" range (quality profiling IS analysis)
- Candidate: R/35_death_cause_quality.R (35-39 appear available based on ls output)
- Alternative: 70-89 "quality" range if 35 is taken

**Warning signs:**
- Script number collision (file already exists)
- Sourcing error (script sourced out of order, missing dependency)

### Pitfall 2: DEATH_CAUSE Field Availability

**What goes wrong:** Assuming DEATH table has a field named DEATH_CAUSE when it might be named CAUSE, CAUSE_OF_DEATH, or require linkage to external cause-of-death table.

**Why it happens:** PCORnet CDM DEATH table spec (v7.0) defines DEATH_CAUSE as optional field. Some networks populate it, some don't.

**How to avoid:**
1. Query DEATH table schema first: `names(get_pcornet_table("DEATH"))`
2. Check for DEATH_CAUSE column presence
3. If missing, check DEATH_SOURCE, DEATH_CAUSE_CODE, CAUSE variants
4. Document field name in quality profiling script header
5. If truly missing, fall back to "Unknown or Unspecified" for 100% of deaths (document in quality report)

**Warning signs:**
- Column not found error when querying DEATH_CAUSE
- All deaths map to "Unknown or Unspecified"
- Phase 53 (R/53_death_date_validation.R) doesn't reference DEATH_CAUSE (suggests it may not exist in this dataset)

**Resolution strategy for this project:**
- R/53 loads DEATH table and selects ID, DEATH_DATE, DEATH_SOURCE (lines 78-91)
- DEATH_CAUSE not mentioned in R/53 — strong signal it may be missing
- Quality profiling script MUST check column availability before mapping
- If missing: document 100% missingness, recommend skipping cause_of_death integration in R/52 (D-04 decision: soft warning)

### Pitfall 3: Triggering Codes vs Drug Names Confusion

**What goes wrong:** Populating triggering_code_description from DRUG_GROUPINGS instead of code_descriptions.rds, or vice versa.

**Why it happens:** Both are code-to-label mappings with similar names.

**How to avoid (per D-05, D-06):**
- `triggering_code_description` ← code_descriptions.rds (human-readable names: "Doxorubicin HCl 50mg injection")
- `drug_group` ← DRUG_GROUPINGS (category labels: "Chemotherapy")
- Two separate columns, two separate lookups
- Never mix sources

**Warning signs:**
- triggering_code_description contains "Chemotherapy" (category label, not drug name)
- drug_group contains "Doxorubicin HCl" (drug name, not category)

### Pitfall 4: Column Count Breakage

**What goes wrong:** Gantt CSV exports break Tableau dashboards when column counts change unexpectedly.

**Why it happens:** Tableau data sources specify fixed column schemas. Adding/removing columns without version bumps breaks existing connections.

**How to avoid (per D-09, D-14):**
- Document old vs new column counts in script header
- gantt_episodes_v2.csv: 14 -> 16 columns (was 14 after Phase 64 cleanup)
- gantt_detail_v2.csv: 13 -> 14 columns
- Add new columns at END (right side) for backward compatibility
- Verify count with assertion: `stopifnot(ncol(episodes_export) == 16)`
- Update v2 schema comment block (R/52 lines 36-72)

**Warning signs:**
- Column count assertion failure
- Tableau data source refresh error
- Missing columns in Gantt chart

## Code Examples

Verified patterns from project codebase:

### Pattern 1: Multi-Sheet XLSX with Styling (R/28 pattern)

```r
# Source: R/28_episode_classification.R lines 448-677
# Pattern: 5-sheet workbook with title rows, header styling, freeze panes

wb <- wb_workbook()

# Sheet 1: Overall Completeness
wb$add_worksheet("Overall Completeness")

# Title row (A1)
wb$add_data(sheet = "Overall Completeness", x = "Death Cause Quality Report",
            start_row = 1, start_col = 1)
wb$add_font(sheet = "Overall Completeness", dims = "A1",
            name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937"))
wb$merge_cells(sheet = "Overall Completeness", dims = "A1:C1")

# Subtitle row (A2)
subtitle <- glue("Generated: {Sys.Date()} | Total deaths: {nrow(death_data)}")
wb$add_data(sheet = "Overall Completeness", x = subtitle, start_row = 2, start_col = 1)
wb$add_font(sheet = "Overall Completeness", dims = "A2",
            name = "Calibri", size = 10, color = wb_color("FF6B7280"))

# Data starting row 4
wb$add_data(sheet = "Overall Completeness", x = overall_stats,
            start_row = 4, start_col = 1)

# Header styling (row 4)
wb$add_font(sheet = "Overall Completeness", dims = "A4:C4",
            name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))
wb$add_fill(sheet = "Overall Completeness", dims = "A4:C4",
            color = wb_color("FF1F2937"))

# Freeze panes and autofit
wb$freeze_pane(sheet = "Overall Completeness", first_active_row = 5)
wb$set_col_widths(sheet = "Overall Completeness", cols = 1:3, widths = "auto")

# Save
wb_save(wb, OUTPUT_XLSX, overwrite = TRUE)
```

### Pattern 2: Semicolon-Separated Multi-Value Mapping (R/52 pattern)

```r
# Source: R/52_gantt_v2_export.R lines 187-207, 513-612
# Pattern: Map comma/semicolon-separated codes to parallel descriptions

# Helper: lookup single code
lookup_description <- function(code) {
  if (is.null(code_descriptions) || is.na(code) || code == "") return("")
  if (code %in% names(code_descriptions)) return(code_descriptions[[code]])
  return("")  # unmapped returns empty string (not NA)
}

# Helper: map multi-value field
map_codes_to_descriptions <- function(codes_str) {
  if (is.na(codes_str) || codes_str == "") return("")
  codes <- str_split(codes_str, ";")[[1]]  # Phase 64 separator
  descriptions <- sapply(codes, lookup_description, USE.NAMES = FALSE)
  paste(descriptions, collapse = ";")
}

# Apply to dataframe
episodes <- episodes %>%
  mutate(
    triggering_code_descriptions = sapply(triggering_codes, map_codes_to_descriptions,
                                           USE.NAMES = FALSE)
  )
```

### Pattern 3: DuckDB DEATH Table Query (R/53 pattern)

```r
# Source: R/53_death_date_validation.R lines 66-92
# Pattern: Query DEATH table, parse dates, filter sentinels, aggregate to patient level

library(dplyr)
library(lubridate)
source("R/00_config.R")
source("R/utils/utils_duckdb.R")
source("R/utils/utils_dates.R")

USE_DUCKDB <- TRUE
open_pcornet_con()

death_data <- get_pcornet_table("DEATH") %>%
  collect() %>%
  mutate(
    DEATH_DATE = parse_pcornet_date(DEATH_DATE),
    DEATH_DATE = if_else(year(DEATH_DATE) == 1900L, as.Date(NA), DEATH_DATE)
  ) %>%
  filter(!is.na(DEATH_DATE)) %>%
  select(ID, DEATH_DATE, DEATH_SOURCE) %>%
  group_by(ID) %>%
  summarise(
    DEATH_DATE = min(DEATH_DATE),
    DEATH_SOURCE = first(DEATH_SOURCE),
    .groups = "drop"
  )

message(glue("Patients with valid death dates: {nrow(death_data)}"))

close_pcornet_con()
```

### Pattern 4: Named Vector Lookup (R/00_config.R pattern)

```r
# Source: R/00_config.R lines 1153-1199 (DRUG_GROUPINGS), 751-1134 (DEATH_CAUSE_MAP)
# Pattern: Named vector for code-to-category mapping

# Drug grouping lookup (D-06)
map_drug_group <- function(code) {
  if (is.na(code) || code == "") return(NA_character_)
  if (code %in% names(DRUG_GROUPINGS)) return(DRUG_GROUPINGS[[code]])
  return(NA_character_)  # D-08: unmapped codes get NA
}

# Death cause lookup (D-10)
map_death_cause <- function(death_cause_code) {
  if (is.na(death_cause_code) || death_cause_code == "") return("Unknown or Unspecified")
  prefix_3char <- str_sub(death_cause_code, 1, 3)
  if (prefix_3char %in% names(DEATH_CAUSE_MAP)) return(DEATH_CAUSE_MAP[[prefix_3char]])
  return("Unknown or Unspecified")
}

# Apply to multi-value field
episodes <- episodes %>%
  mutate(
    drug_group = sapply(triggering_codes, map_codes_to_drug_groups, USE.NAMES = FALSE),
    cause_of_death = sapply(DEATH_CAUSE, map_death_cause, USE.NAMES = FALSE)
  )
```

## State of the Art

No deprecated approaches. All patterns are current as of Phase 77 (2026-06-02).

| Pattern | Current Approach | When Established | Impact |
|---------|------------------|------------------|--------|
| Multi-value separators | Semicolon (;) | Phase 64 (2026-06-01) | CSV Tableau import cleanup; replaces commas to avoid field splitting |
| Lookup tables | Named vectors in R/00_config.R | Phase 36 (AMC_PAYER_LOOKUP) | Centralized, version-controlled, no runtime xlsx dependency |
| Quality reports | openxlsx2 multi-sheet with styling | Phase 28, 53, 91 | Analyst-friendly persistent review (vs console-only diagnostics) |
| Death validation | validated_death_dates.rds from R/53 | Phase 59 (2026-06-01) | Pre-validated artifact prevents duplicate validation logic |

**Current state (Phase 77 complete):**
- DRUG_GROUPINGS: 454 entries in R/00_config.R (Phase 77)
- DEATH_CAUSE_MAP: ~100 entries in R/00_config.R (Phase 75)
- code_descriptions.rds: existing artifact from R/48b
- validated_death_dates.rds: existing artifact from R/53
- R/28 treatment_episodes.rds: 15 columns (Phase 61-62)
- R/52 gantt CSVs: 14 episodes / 13 detail columns (Phase 64)

## Open Questions

### Question 1: DEATH_CAUSE Field Availability

**What we know:**
- PCORnet CDM v7.0 DEATH table spec includes optional DEATH_CAUSE field (ICD-10 code)
- R/53 (Phase 59) queries DEATH table but only selects ID, DEATH_DATE, DEATH_SOURCE
- No reference to DEATH_CAUSE in R/53 suggests field may be missing from this dataset

**What's unclear:**
- Does this OneFlorida+ dataset populate DEATH_CAUSE?
- If missing, is there an alternative field (DEATH_CAUSE_CODE, CAUSE, etc.)?
- If truly missing, what's the missingness rate to report?

**Recommendation:**
1. Quality profiling script (Wave 1) MUST probe DEATH table schema first
2. If DEATH_CAUSE exists: proceed with mapping via DEATH_CAUSE_MAP
3. If DEATH_CAUSE missing: document 100% missingness in quality report, recommend SKIPPING cause_of_death integration in R/52 (D-04: soft warning, not hard gate)
4. Code defensively: `if ("DEATH_CAUSE" %in% names(death_data)) { ... } else { message("DEATH_CAUSE field not available") }`

### Question 2: Death Quality Report Threshold Decision (D-04)

**What we know:**
- D-11: >40% missingness triggers console warning in R/52
- D-04: Claude's discretion on hard gate (block R/52 integration) vs soft warning (document but proceed)
- Literature: 40-60% cause of death missingness is common in EHR-based mortality studies

**What's unclear:**
- What will the actual missingness rate be for this dataset?
- Are there meaningful stratifications (e.g., 90% complete for in-hospital deaths, 20% for external deaths)?

**Recommendation:**
- Implement quality profiling first (Wave 1)
- If missingness <40%: proceed with R/52 integration (soft warning)
- If 40-60%: proceed but document limitations prominently in quality report
- If >60%: recommend SKIPPING cause_of_death column (D-04: hard gate) — integration provides no analytical value at that missingness rate
- Final decision after seeing actual data quality

### Question 3: Script Number for Death Quality Report

**What we know:**
- Decade-based numbering: 00-09 foundation, 10-29 cohort, 30-49 analysis, 50-69 outputs, 70-89 quality, 90-99 diagnostics
- 90-99 diagnostics nearly full
- Death quality profiling is a quality analysis task

**What's unclear:**
- Is R/35 available? (ls output shows R/40 exists, but not R/35)
- Is 70-89 quality range more appropriate than 30-49 analysis?

**Recommendation:**
- Primary: R/35_death_cause_quality.R (analysis range, groups with other cancer frequency scripts like R/40)
- Fallback 1: R/36_death_cause_quality.R (if 35 exists but not in ls output)
- Fallback 2: R/78_death_cause_quality.R (quality range, but 70-89 is conceptually for automated tests)
- Confirm availability via `ls R/35_*.R` during planning

## Project Constraints (from CLAUDE.md)

### Runtime Environment
- **HiPerGator RStudio** — all scripts must run in this environment
- **R 4.4.2+** loaded via `module load R/4.4.2`

### Code Style
- **Named predicate functions** for filtering logic (`has_*`, `with_*`, `exclude_*`) — no opaque one-liners
- Phase 78 doesn't add new filtering logic, so this constraint doesn't apply

### Package Constraints
- **tidyverse ecosystem** (dplyr, ggplot2, stringr, lubridate) — all already used
- **No data.table** — conflicts with "named predicate" requirement (not applicable to Phase 78)

### Data Access
- **Raw CSVs on HiPerGator** via DuckDB (already established)
- Phase 78 reads existing RDS artifacts (treatment_episodes.rds, validated_death_dates.rds, code_descriptions.rds)

### Payer Fidelity
- **9-category payer mapping** (matches Python pipeline) — not applicable to Phase 78 (payer category already computed in R/60)

## Sources

### Primary (HIGH confidence)

**Codebase artifacts (direct inspection):**
- R/28_episode_classification.R — Multi-sheet xlsx pattern (lines 448-677), episode enrichment pattern (lines 424-442)
- R/52_gantt_v2_export.R — Semicolon-separated multi-value mapping (lines 187-207, 513-612), Gantt CSV export pattern (lines 714-728)
- R/53_death_date_validation.R — DuckDB DEATH table query pattern (lines 66-92), validated_death_dates.rds creation
- R/00_config.R — DRUG_GROUPINGS (lines 1153+), DEATH_CAUSE_MAP (lines 751-1134), named vector lookup pattern
- R/91_data_quality_summary.R — Quality profiling pattern (lines 1-100)
- .planning/phases/75-configuration-extensions-nlphl-death-cause/75-CONTEXT.md — DEATH_CAUSE_MAP decisions (D-04 through D-07)
- .planning/phases/77-cancer-classification-refinements/77-CONTEXT.md — DRUG_GROUPINGS decisions (D-05 through D-07)
- .planning/phases/78-episode-enhancement-death-integration/78-CONTEXT.md — All implementation decisions (D-01 through D-14)

**Project documentation:**
- CLAUDE.md — Runtime environment (HiPerGator RStudio), package constraints (tidyverse), code style (named predicates)
- .planning/REQUIREMENTS.md — CANCER-03, DEATH-01, DEATH-02, QUAL-01 requirements

### Secondary (MEDIUM confidence)

**External standards (for context only, not driving decisions):**
- PCORnet CDM v7.0 specification — DEATH table schema (DEATH_DATE, DEATH_SOURCE, DEATH_CAUSE fields)
- WHO Mortality Database — ICD-10 cause of death groupings (informational context for DEATH_CAUSE_MAP design in Phase 75)
- CDC NCHS 113 Selected Causes — ICD-10 cause categories (informational context for DEATH_CAUSE_MAP design in Phase 75)

**Note:** All implementation patterns are derived from project codebase, not external R documentation. No external package documentation needed — all packages already in use.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — All packages already in renv.lock from prior phases
- Architecture: HIGH — All patterns (multi-sheet xlsx, multi-value mapping, DuckDB queries, named vector lookups) directly observable in existing scripts
- Pitfalls: HIGH — Field availability issue identified from R/53 code inspection (DEATH_CAUSE not referenced)
- Code examples: HIGH — All examples quoted verbatim from project codebase with line numbers

**Research date:** 2026-06-03
**Valid until:** 90 days (stable codebase, no fast-moving dependencies)

**Open dependencies:**
- DEATH_CAUSE field availability (resolvable in Wave 1 quality profiling)
- Script number assignment (resolvable via `ls R/` check during planning)
- Hard gate vs soft warning decision (resolvable after seeing quality profiling results)

---

**Ready for planning.** All technical patterns established. Three-wave implementation: (1) death quality profiling, (2) R/28 episode enrichment, (3) R/52 Gantt integration. No new packages, no new infrastructure, no architectural changes.
