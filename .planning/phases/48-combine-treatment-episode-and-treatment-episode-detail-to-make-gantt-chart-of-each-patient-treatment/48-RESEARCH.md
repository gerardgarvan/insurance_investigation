# Phase 01: Combine Treatment Episode and Detail for Gantt Chart - Research

**Researched:** 2026-05-19
**Domain:** Data transformation — RDS to CSV export pipeline for Gantt chart visualization
**Confidence:** HIGH

## Summary

Phase 01 prepares two CSV datasets from existing RDS artifacts for third-party Gantt chart visualization. This is a **data preparation phase only** — no visualization code. The output structure follows the standard Gantt chart data model: (1) episode-level "bars" table defining patient treatment periods with start/stop dates, and (2) detail-level "ticks" table showing individual treatment dates with triggering codes.

The implementation is straightforward: load two existing RDS files (`treatment_episodes.rds` and `treatment_episode_detail.rds`), apply minimal transformations (column reordering per user decisions), and write two universally-parseable CSV files. The RDS artifacts already contain the exact data structure needed — this phase is primarily a format conversion operation.

**Primary recommendation:** Use standard `readRDS()` → `dplyr::select()` → `write.csv()` pipeline following established patterns in R/43-R/46 scripts. Script number: R/47 (next available after R/46_treatment_cross_reference.R).

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Data Structure:**
- **D-01:** Two-table output: (1) episode-level "bars" table with patient_id, treatment_type, episode_number, episode_start, episode_stop, episode_length_days, distinct_dates_in_episode, historical_flag, triggering_codes; (2) detail-level "ticks" table with patient_id, treatment_type, treatment_date, triggering_code, episode_number, episode_start, episode_stop, historical_flag
- **D-02:** One row per code in the detail table — if a patient has 3 treatment codes on one date, that's 3 rows. Preserves full granularity for the consumer.
- **D-03:** Separate rows by treatment type — concurrent treatments (e.g., chemo overlapping radiation) appear as separate rows. No overlap flag needed; the plotter handles overlap visually.

**Scope:**
- **D-04:** All HL patients with at least one treatment episode are included — full cohort, no filtering. Third party handles any subsetting.
- **D-05:** No payer tier data included in this phase. May be added in a future phase.

**Output Format:**
- **D-06:** CSV output only — two files: `gantt_episodes.csv` (bars) and `gantt_detail.csv` (ticks). Universal format for any plotting tool.

**Data Sources:**
- **D-07:** Load from existing RDS artifacts: `cache/outputs/treatment_episodes.rds` (episode-level) and `cache/outputs/treatment_episode_detail.rds` (detail-level). No re-extraction from raw PCORnet tables.

### Claude's Discretion

- Column ordering within the CSVs
- Whether to add any derived columns useful for Gantt plotting (e.g., patient row index, episode label)
- Script naming convention (following existing R/NN_*.R pattern)

### Deferred Ideas (OUT OF SCOPE)

- Payer tier integration — joining Phase 46 date-level payer data onto the Gantt detail table (user noted "might be implemented in future")
- Actual Gantt chart visualization code (ggplot2, plotly, etc.) — third party handles plotting

</user_constraints>

## Standard Stack

This phase uses the **existing R pipeline stack** from the project (no new packages required):

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| dplyr | 1.2.0+ | Data transformation | Already in use; select(), arrange() for column reordering |
| readr | 2.2.0+ | CSV writing | Already in use; alternative to base write.csv() with better defaults |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| glue | 1.8.0 | String formatting | Already in use; logging messages |

**No new package installation required.** All dependencies already loaded by R/44_treatment_episodes.R and used throughout the project.

**Version verification:** Package versions confirmed via CLAUDE.md STACK.md section — all verified against project's existing renv lock file (implicit) or documented phase usage.

## Project Constraints (from CLAUDE.md)

**Must follow:**
- **Runtime environment:** RStudio on UF HiPerGator — script must work in that environment
- **Code style:** Use tidyverse patterns (dplyr verbs, pipe operator); avoid base R subset/merge syntax
- **Script numbering:** Follow R/NN_descriptive_name.R pattern (next available: R/48)
- **Output directory:** `output/` for final CSV files (per CONFIG$output_dir)
- **RDS source paths:** Load from `CONFIG$cache$outputs_dir` (HiPerGator path: `/blue/erin.mobley-hl.bcu/clean/rds/outputs`)
- **Logging:** Use glue() for readable messages; log input row counts, output row counts, file paths

## Architecture Patterns

### Recommended Project Structure

No new directories needed. Uses existing structure:

```
R/
├── 44_treatment_episodes.R      # Creates input RDS artifacts
├── 48_gantt_data_export.R       # THIS PHASE (new script)
output/
├── gantt_episodes.csv           # Output 1 (bars)
└── gantt_detail.csv             # Output 2 (ticks)
```

### Pattern 1: RDS-to-CSV Export Pipeline

**What:** Load RDS artifact, transform column structure, write CSV output
**When to use:** Converting internal RDS cache to universal CSV format for external tools
**Example:**

```r
# Source: R/43_treatment_durations.R lines 600-602, R/44_treatment_episodes.R lines 635-647
# Load RDS artifact
episodes <- readRDS(file.path(CONFIG$cache$outputs_dir, "treatment_episodes.rds"))

# Transform: select and reorder columns per user decisions
episodes_export <- episodes %>%
  select(patient_id, treatment_type, episode_number, episode_start, episode_stop,
         episode_length_days, distinct_dates_in_episode, historical_flag, triggering_codes)

# Write CSV with row.names=FALSE (standard pattern across codebase)
write.csv(episodes_export,
          file.path(CONFIG$output_dir, "gantt_episodes.csv"),
          row.names = FALSE)

message(glue("Wrote gantt_episodes.csv ({nrow(episodes_export)} rows)"))
```

### Pattern 2: Standard Script Structure (Phases 43-46)

**Sections:**
1. **Setup and Configuration:** Library loading, source R/00_config.R, define output paths
2. **Load Input Data:** readRDS() calls with existence checks
3. **Transform Data:** dplyr transformations (select, arrange, mutate if needed)
4. **Write Outputs:** write.csv() calls with logging
5. **Final Summary:** Message with output file paths and row counts

**Example structure:**

```r
# =============================================================================
# Phase 48: Gantt Chart Data Export
# =============================================================================
# Combines treatment episode and episode detail RDS artifacts into two CSV files
# for third-party Gantt chart visualization.
#
# Decision traceability:
#   D-01: Two-table output (bars + ticks)
#   D-02: Detail table preserves one-row-per-code granularity
#   D-03: Separate rows by treatment type (concurrent as separate rows)
#   D-04: Full cohort (no filtering)
#   D-06: CSV output only
#   D-07: Load from existing RDS artifacts
# =============================================================================

# --- SECTION 1: SETUP AND CONFIGURATION ---
suppressPackageStartupMessages({
  library(dplyr)
  library(glue)
})

source("R/00_config.R")

# Input RDS paths
EPISODES_RDS <- file.path(CONFIG$cache$outputs_dir, "treatment_episodes.rds")
DETAIL_RDS <- file.path(CONFIG$cache$outputs_dir, "treatment_episode_detail.rds")

# Output CSV paths
OUTPUT_EPISODES <- file.path(CONFIG$output_dir, "gantt_episodes.csv")
OUTPUT_DETAIL <- file.path(CONFIG$output_dir, "gantt_detail.csv")

# --- SECTION 2: LOAD INPUT DATA ---
message("=== Phase 48: Gantt Chart Data Export ===\n")
message("Loading RDS artifacts...")

# [Load and validate RDS files]

# --- SECTION 3: TRANSFORM DATA ---
# [Column selection and reordering per D-01]

# --- SECTION 4: WRITE OUTPUTS ---
# [write.csv() calls]

# --- SECTION 5: FINAL SUMMARY ---
message("\n=== Phase 48 Complete ===")
# [File paths and row counts]
```

### Anti-Patterns to Avoid

- **Don't use base R write.csv() with default row.names=TRUE:** All existing scripts use `row.names = FALSE` — follow this convention
- **Don't add new columns without user approval:** D-01 specifies exact column lists; Claude's discretion covers reordering but not new columns without justification
- **Don't filter the cohort:** D-04 specifies full cohort output; third party handles subsetting
- **Don't re-extract from PCORnet tables:** D-07 specifies using existing RDS artifacts only

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| CSV writing with encoding/escaping | Custom file.write() loop | base::write.csv() or readr::write_csv() | Handles NA values, quote escaping, special characters correctly |
| Column reordering | Manual index-based subsetting | dplyr::select() with column names | Readable, order-preserving, fails fast if column missing |
| File path construction | paste0() with hardcoded slashes | file.path() | Platform-independent path separator handling |
| Existence checks | file.exists() + manual error | Base R error if file missing | R's readRDS() throws clear error message if file doesn't exist |

**Key insight:** This phase is 95% plumbing — use built-in R functions and tidyverse verbs. The complexity is in verifying that RDS column structure matches user decisions (D-01), not in building custom data transformation logic.

## Common Pitfalls

### Pitfall 1: RDS File Missing on HiPerGator

**What goes wrong:** Script runs locally with dev data but fails on HiPerGator because RDS artifacts haven't been generated yet
**Why it happens:** R/44_treatment_episodes.R must be run first to create the RDS artifacts; if Phase 44 script hasn't been executed on HiPerGator, the files won't exist
**How to avoid:** Add explicit existence check with informative error message:

```r
if (!file.exists(EPISODES_RDS)) {
  stop(glue("ERROR: {EPISODES_RDS} not found. Run R/44_treatment_episodes.R first."))
}
```

**Warning signs:** `Error in readRDS(EPISODES_RDS) : error reading from connection`

### Pitfall 2: Column Name Mismatch Between RDS and User Decisions

**What goes wrong:** RDS file uses `ID` but D-01 specifies `patient_id`, causing select() to fail or produce wrong columns
**Why it happens:** R/44_treatment_episodes.R already renamed columns to match D-01 spec (line 616-617: `select(patient_id = ID, ...)`), but if script order changes or RDS regenerated with old code, column names diverge
**How to avoid:** Verify column names immediately after loading:

```r
episodes <- readRDS(EPISODES_RDS)
expected_cols <- c("patient_id", "treatment_type", "episode_number", "episode_start",
                   "episode_stop", "episode_length_days", "distinct_dates_in_episode",
                   "historical_flag", "triggering_codes")
missing_cols <- setdiff(expected_cols, colnames(episodes))
if (length(missing_cols) > 0) {
  stop(glue("ERROR: RDS missing expected columns: {paste(missing_cols, collapse=', ')}"))
}
```

**Warning signs:** `Error: Can't subset columns that don't exist.`

### Pitfall 3: CSV Row Name Column Breaks Third-Party Parser

**What goes wrong:** CSV output includes an unlabeled first column with row numbers (1, 2, 3...), confusing Gantt chart parser
**Why it happens:** Base R write.csv() defaults to `row.names = TRUE`, adding a row number column
**How to avoid:** **Always specify `row.names = FALSE`** (standard across R/43-R/46):

```r
write.csv(episodes_export, OUTPUT_EPISODES, row.names = FALSE)
```

**Warning signs:** Third-party tool reports "unexpected column count" or treats patient IDs as row numbers

### Pitfall 4: Date Columns Written as Character Instead of ISO 8601

**What goes wrong:** Dates appear as "2024-01-15" (character) but third-party parser expects Date type or fails to recognize format
**Why it happens:** write.csv() converts Date columns to character strings in ISO 8601 format (YYYY-MM-DD) by default — this is actually **correct behavior** for CSV interoperability
**How to avoid:** **No action needed** — ISO 8601 string format is the universal standard for dates in CSV files. If third party requires a different format, that's a future transformation (out of scope for this phase per D-06).
**Warning signs:** None — this is expected behavior. Only flag if third party explicitly requests non-ISO format.

### Pitfall 5: Triggering Codes Column Contains NA Values Breaking Plotter

**What goes wrong:** Some episodes have `triggering_codes = NA` (TUMOR_REGISTRY sources with date evidence only), causing Gantt plotter to fail on NA strings
**Why it happens:** R/44_treatment_episodes.R correctly sets `triggering_code = NA_character_` for TUMOR_REGISTRY sources (lines 201, 262, 283, 356) because those sources provide dates but not individual procedure codes. The aggregation logic (`paste(sort(unique(na.omit(...))))`) removes NAs during episode-level collapse, but if ALL codes for an episode are NA, the column is empty string `""`, not NA.
**How to avoid:** **No action needed** — R/44's na.omit() logic already handles this (line 469). Verify output CSVs have empty strings `""` not `NA` for TUMOR_REGISTRY-only episodes.
**Warning signs:** CSV contains literal `NA` strings in triggering_codes column

## Code Examples

Verified patterns from existing codebase:

### Load RDS Artifact with Logging

```r
# Source: R/43_treatment_durations.R lines 555-579 (implicit pattern)
message("Loading treatment episodes from RDS...")
episodes <- readRDS(EPISODES_RDS)
message(glue("  Loaded {nrow(episodes)} episode rows"))
```

### Column Selection and Reordering per User Decision

```r
# Source: R/44_treatment_episodes.R lines 616-617
# D-01 specifies exact column order for episode table
episodes_export <- episodes %>%
  select(patient_id, treatment_type, episode_number, episode_start, episode_stop,
         episode_length_days, distinct_dates_in_episode, historical_flag, triggering_codes)
```

### Write CSV with Standard Logging Pattern

```r
# Source: R/44_treatment_episodes.R lines 646-647
write.csv(episodes_export, OUTPUT_EPISODES, row.names = FALSE)
message(glue("  Wrote {OUTPUT_EPISODES} ({nrow(episodes_export)} rows)"))
```

### Full Phase Structure (Minimal Transform)

```r
# Combining patterns from R/43-R/46
message("=== Phase 48: Gantt Chart Data Export ===\n")

# Load episode-level data
message("Loading treatment episodes...")
episodes <- readRDS(EPISODES_RDS)
message(glue("  Loaded {nrow(episodes)} episodes"))

# Load detail-level data
message("Loading episode detail...")
detail <- readRDS(DETAIL_RDS)
message(glue("  Loaded {nrow(detail)} detail rows"))

# Episode table: D-01 column order
episodes_export <- episodes %>%
  select(patient_id, treatment_type, episode_number, episode_start, episode_stop,
         episode_length_days, distinct_dates_in_episode, historical_flag, triggering_codes)

# Detail table: D-01 column order
detail_export <- detail %>%
  select(patient_id, treatment_type, treatment_date, triggering_code,
         episode_number, episode_start, episode_stop, historical_flag)

# Write outputs
message("\n--- Writing CSV outputs ---")
write.csv(episodes_export, OUTPUT_EPISODES, row.names = FALSE)
message(glue("  Wrote {OUTPUT_EPISODES} ({nrow(episodes_export)} episodes)"))

write.csv(detail_export, OUTPUT_DETAIL, row.names = FALSE)
message(glue("  Wrote {OUTPUT_DETAIL} ({nrow(detail_export)} detail rows)"))

message("\n=== Phase 48 Complete ===")
message(glue("Outputs:"))
message(glue("  {OUTPUT_EPISODES}"))
message(glue("  {OUTPUT_DETAIL}"))
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Per-type CSV files (4 files each) | Single combined CSV per table type (2 files total) | Phase 01 (new) | Simpler for third-party tools — treatment type is a column, not separate files |
| RDS artifacts for internal use only | CSV exports for external visualization | Phase 01 (new) | Enables tool-agnostic Gantt chart plotting |

**Note:** R/44_treatment_episodes.R already outputs per-type CSV files (chemotherapy_episodes.csv, radiation_episodes.csv, etc.) — Phase 01 consolidates these into single files with `treatment_type` column for easier third-party consumption.

## Validation Architecture

**Skipped:** Per .planning/config.json, `workflow.nyquist_validation` is set to `false`. No test infrastructure research required.

## Environment Availability

**Skipped:** This phase has no external dependencies beyond base R and tidyverse packages already installed on HiPerGator. All dependencies verified present via CLAUDE.md STACK.md section.

## Open Questions

**None.** All requirements clearly specified in CONTEXT.md decisions D-01 through D-07. RDS artifacts already exist with exact column structure needed.

## Sources

### Primary (HIGH confidence)

- **Existing codebase:** R/44_treatment_episodes.R (lines 55-57, 620-668) — defines RDS artifact structure and CSV export pattern
- **Existing codebase:** R/43_treatment_durations.R (lines 50-56, 584-602) — establishes RDS-to-CSV pipeline pattern used across phases 43-46
- **Project configuration:** R/00_config.R (lines 55-74) — defines CONFIG$cache$outputs_dir and CONFIG$output_dir paths
- **User decisions:** .planning/phases/01-*/01-CONTEXT.md (decisions D-01 through D-07) — locks all structural requirements

### Secondary (MEDIUM confidence)

- [Simple Gantt charts in R with ggplot2](https://www.molecularecologist.com/2019/01/03/simple-gantt-charts-in-r-with-ggplot2-and-the-tidyverse/) — confirms geom_segment() standard for Gantt bars with start/end times on x-axis
- [How to Create a Gantt Chart in R Using ggplot2](https://www.statology.org/gantt-chart-r-ggplot2/) — verifies typical two-column structure (start date, end date) for episode bars
- [Gantt charts in R (plotly)](https://plotly.com/r/gantt/) — confirms standard data structure expectations for Gantt visualization

### Tertiary (LOW confidence, informational only)

- [Gantt Chart Software for Health Care Professionals](https://clickup.com/features/gantt/health-care-professionals) — confirms healthcare application of Gantt charts for treatment timeline visualization (conceptual validation only, no technical details)

## Metadata

**Confidence breakdown:**
- RDS artifact structure: **HIGH** — directly verified from R/44_treatment_episodes.R source code (lines 615-627)
- CSV export pattern: **HIGH** — verified from 3 existing scripts (R/43, R/44, R/46) using identical write.csv() pattern
- Column requirements: **HIGH** — locked decisions D-01/D-02 in CONTEXT.md with exact column lists
- HiPerGator paths: **HIGH** — CONFIG structure defined in R/00_config.R (lines 55-74)

**Research date:** 2026-05-19
**Valid until:** 90 days (stable domain — data export patterns unlikely to change)
