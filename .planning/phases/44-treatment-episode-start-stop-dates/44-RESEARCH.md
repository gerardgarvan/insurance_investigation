# Phase 44: Treatment Episode Start/Stop Dates - Research

**Researched:** 2026-05-07
**Domain:** R data transformation, episode splitting with gap-based thresholds, temporal analysis
**Confidence:** HIGH

## Summary

Phase 44 produces per-patient, per-episode treatment timelines by disaggregating Phase 43's per-patient summary into episode-level rows. The core technical challenge is trivial: Phase 43 already computes per-episode dates internally (R/43_treatment_durations.R lines 486-492) before collapsing to patient-level summaries — Phase 44 simply stops at that intermediate result instead of aggregating further.

The research domain centers on: (1) historical date handling (flagging tumor registry dates from 1970s-2000s that fall outside the modern PCORnet data window), (2) episode numbering within patients, and (3) output formatting aligned with Phase 43's established patterns (RDS artifact, styled xlsx via openxlsx2, per-type CSV).

**Primary recommendation:** Source or refactor Phase 43's `extract_all_dates()` and `calculate_durations_and_episodes()` functions, stop aggregation at the per-episode `summarise()` step (line 492), add `episode_number` and `historical_flag` columns, then output following Phase 43's deliverable pattern.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Include historical episodes in the same output but flag them with a boolean `historical_flag` column
- **D-02:** Historical cutoff = before 2012 (matches OneFlorida+ data extraction period start)
- **D-03:** An episode is flagged historical when ALL its dates fall before 2012-01-01
- **D-04:** Historical episodes get start=stop=that date, length=0 for single-date records (consistent with Phase 43 D-03)
- **D-05:** New per-episode output alongside Phase 43's per-patient summary — Phase 43 stays unchanged
- **D-06:** New R script `R/44_treatment_episodes.R` (separate from R/43)
- **D-07:** Output deliverables: RDS artifact + styled xlsx + per-type CSVs (following Phase 43 patterns)
- **D-08:** Per-episode row columns: `patient_id`, `treatment_type`, `episode_number`, `episode_start`, `episode_stop`, `episode_length_days`, `distinct_dates_in_episode`, `historical_flag`
- **D-09:** One row per patient per treatment type per episode
- **D-10:** 90-day gap threshold for episode splitting (Phase 43 D-05)
- **D-11:** All chemo codes pooled, no regimen distinction (Phase 43 D-13)
- **D-12:** Four treatment types: Chemotherapy, Radiation, SCT, Immunotherapy (Phase 43 D-12)
- **D-13:** Pre-2000 dates are real tumor registry data, not sentinels (STATE.md key decision)

### Claude's Discretion
- How to share date extraction logic with R/43 (source R/43 functions, refactor to shared helper, or duplicate)
- xlsx sheet organization (summary + per-type, or flat)
- Whether to include a summary statistics console output like Phase 43's D-10
</user_constraints>

## Standard Stack

### Core Libraries (Already in Use)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| dplyr | 1.2.0+ | Data transformation | Tidyverse core; group_by/summarise pipeline for episode aggregation |
| lubridate | 1.9.3+ | Date arithmetic | Already used in Phase 43; needed for historical date cutoff comparisons |
| glue | 1.8.0 | String formatting | Already used for console logging throughout project |
| openxlsx2 | Latest | Excel workbook generation | Established in Phase 41/42/43 for styled xlsx output |
| purrr | 1.0.2+ | Functional programming | compact() + bind_rows() pattern for multi-source stacking |

**No new packages required** — Phase 44 uses the exact same tidyverse + openxlsx2 stack as Phase 43.

### Installation
Already installed via project renv. No additional setup needed.

## Architecture Patterns

### Recommended Project Structure
```
R/
├── 00_config.R              # CONFIG paths, TREATMENT_CODES, GAP_THRESHOLD
├── 01_load_pcornet.R        # get_pcornet_table() dispatcher
├── 43_treatment_durations.R # Per-patient summary (existing, unchanged)
└── 44_treatment_episodes.R  # Per-episode detail (NEW)
```

### Pattern 1: Reuse Phase 43 Date Extraction
**What:** Phase 43's `extract_all_dates(type)` function (lines 79-102) already queries all 7 PCORnet sources and returns ALL treatment dates per patient. This is exactly what Phase 44 needs — no modification required.

**When to use:** Always. Don't duplicate 400+ lines of multi-source date extraction logic.

**Implementation options:**
1. **Source R/43 functions** — Add `source("R/43_treatment_durations.R")` at top of R/44, then call `extract_all_dates()` directly
2. **Refactor to shared helper** — Move `extract_all_dates()` and `stack_and_dedup()` to `R/utils_treatment_dates.R`, source from both R/43 and R/44
3. **Duplicate logic** — Copy-paste extraction functions into R/44 (NOT RECOMMENDED — violates DRY)

**Recommended:** Source R/43 functions directly (option 1). Simpler than refactoring, clearer dependency chain.

**Example:**
```r
# R/44_treatment_episodes.R
source("R/00_config.R")
source("R/01_load_pcornet.R")
source("R/43_treatment_durations.R")  # Reuse extract_all_dates()

# Extract dates (identical to Phase 43)
dates_df <- extract_all_dates("Chemotherapy")

# Stop at per-episode level instead of per-patient summary
episodes <- calculate_episodes_only(dates_df)
```

### Pattern 2: Episode-Level Aggregation (Modified from Phase 43)
**What:** Phase 43's `calculate_durations_and_episodes()` function (lines 464-503) computes per-episode intermediate results at lines 486-492, then collapses to per-patient summaries at lines 495-502. Phase 44 needs the intermediate result, not the final collapse.

**When to use:** Core episode detection logic.

**Implementation strategy:**
Create a modified version `calculate_episodes_detailed()` that stops at line 492 and adds `episode_number` + `historical_flag`:

```r
calculate_episodes_detailed <- function(dates_df, gap_threshold = GAP_THRESHOLD) {
  # Lines 476-492 from Phase 43 (unchanged)
  episodes <- dates_df %>%
    group_by(ID) %>%
    arrange(treatment_date, .by_group = TRUE) %>%
    mutate(
      days_since_prev = as.numeric(treatment_date - lag(treatment_date)),
      new_episode = is.na(days_since_prev) | days_since_prev >= gap_threshold,
      episode_id = cumsum(new_episode)
    ) %>%
    group_by(ID, episode_id) %>%
    summarise(
      episode_first_date = min(treatment_date),
      episode_last_date = max(treatment_date),
      episode_span_days = as.numeric(max(treatment_date) - min(treatment_date)),
      episode_distinct_dates = n(),
      .groups = "drop"
    )

  # NEW: Add episode_number per patient (sequential within patient)
  episodes <- episodes %>%
    group_by(ID) %>%
    mutate(episode_number = row_number()) %>%
    ungroup()

  # NEW: Add historical_flag (D-02/D-03: ALL dates in episode before 2012-01-01)
  episodes <- episodes %>%
    mutate(historical_flag = episode_last_date < as.Date("2012-01-01"))

  # Rename columns to match D-08 output schema
  episodes %>%
    select(
      patient_id = ID,
      episode_number,
      episode_start = episode_first_date,
      episode_stop = episode_last_date,
      episode_length_days = episode_span_days,
      distinct_dates_in_episode = episode_distinct_dates,
      historical_flag
    )
}
```

### Pattern 3: Historical Date Flagging
**What:** Tumor registry records from 1970s-2000s represent historical treatments outside the modern PCORnet data window (2012-2025). Phase 43's verification test (R/43_test_durations.R lines 131-216) already detects pre-2000 dates and documents the "bridge patient" pattern (first date pre-2000, last date post-2012, creating artificially inflated spans).

**When to use:** After computing episode-level dates, before output.

**Decision rule (per D-02/D-03):**
```r
# Historical cutoff: 2012-01-01 (matches OneFlorida+ extraction start)
HISTORICAL_CUTOFF <- as.Date("2012-01-01")

# An episode is historical when ALL its dates fall before cutoff
# (episode_last_date is the latest date in the episode, so if it's
# pre-2012, then ALL dates in the episode are pre-2012)
historical_flag = episode_last_date < HISTORICAL_CUTOFF
```

**Why episode_last_date, not episode_first_date?**
A patient could have a historical treatment in 1995 (one episode) and a modern treatment in 2015 (separate episode due to 90-day gap). Using `episode_last_date < 2012` ensures we flag the 1995 episode as historical but NOT the 2015 episode.

**Single-date historical episodes (D-04):**
Already handled naturally — when `distinct_dates_in_episode = 1`, `episode_start == episode_stop` and `episode_length_days = 0` (from Phase 43 D-03 logic).

### Pattern 4: Output Deliverables (Phase 43 Pattern)
**What:** Phase 43 establishes three output artifacts (D-07 through D-09):
1. **RDS artifact** — `treatment_episodes.rds` saved to `CONFIG$cache$outputs_dir`
2. **Styled xlsx** — `treatment_episodes.xlsx` using openxlsx2 with color-coded headers per type
3. **Per-type CSV** — One CSV per treatment type with snake_case column names

**When to use:** Follow Phase 43's exact output structure for consistency.

**Example (RDS):**
```r
OUTPUT_RDS <- file.path(CONFIG$cache$outputs_dir, "treatment_episodes.rds")
saveRDS(all_episodes, OUTPUT_RDS)
```

**Example (per-type CSV):**
```r
# Phase 43 pattern (lines 574-591)
for (type in TREATMENT_TYPES) {
  type_data <- episodes_list[[type]]
  csv_name <- paste0(tolower(gsub(" ", "_", type)), "_episodes.csv")
  csv_path <- file.path(CONFIG$output_dir, csv_name)

  # D-08 schema: patient_id, episode_number, episode_start, episode_stop,
  #              episode_length_days, distinct_dates_in_episode, historical_flag
  write.csv(type_data, csv_path, row.names = FALSE)
  message(glue("  Wrote {csv_path} ({nrow(type_data)} episodes)"))
}
```

**Example (styled xlsx with openxlsx2):**
Follow Phase 43's pattern (lines 599-742):
- Sheet 1: Summary (episode count per type, historical vs modern breakdown)
- Sheets 2-5: Per-type detail with color-coded headers using `TREATMENT_TYPE_COLORS`
- Number formatting on episode_length_days and distinct_dates_in_episode
- Date formatting on episode_start and episode_stop

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Multi-source date extraction | Custom query logic per source | `extract_all_dates()` from R/43 | 400+ lines of DuckDB-aware queries across 7 PCORnet tables; handles NULL sources, type-specific code matching, tumor registry pivot logic |
| Episode gap detection | Custom loop with date diffs | dplyr `lag()` + `cumsum()` pattern from R/43 | Vectorized, readable, already validated in Phase 43 verification |
| Excel workbook styling | Manual cell formatting loops | openxlsx2 bulk write + style patterns from R/43 | Phase 43 lines 599-742 already implement header styling, number formatting, column widths |
| Historical date detection | Complex date range checks | Single boolean: `episode_last_date < HISTORICAL_CUTOFF` | Tumor registry dates are ALWAYS pre-2012 (per STATE.md), modern PCORnet data is 2012+; no overlap edge cases |

**Key insight:** Phase 44 is a VIEW of Phase 43's intermediate data. The hard work (multi-source extraction, episode detection, output styling) is already done. Don't reimplement — reuse or refactor.

## Common Pitfalls

### Pitfall 1: Episode Numbering Across Treatment Types
**What goes wrong:** Numbering episodes globally (episode 1, 2, 3...) instead of per-patient per-type creates confusion when a patient has chemo episode 1 and radiation episode 1 simultaneously.

**Why it happens:** The `episode_id` column from Phase 43's intermediate result is per-patient-per-type, not globally unique.

**How to avoid:** Compute `episode_number` using `group_by(ID) %>% mutate(episode_number = row_number())` AFTER filtering to a single treatment type. Each type's episode numbering resets at 1 for each patient.

**Warning signs:**
- Output has episode numbers > 10 (unlikely for HL — most patients have 1-2 episodes per type)
- Excel sheet shows gaps in episode numbers (e.g., patient has episodes 1, 5, 9 with no 2-4)

**Validation check:**
```r
# Episode numbers should be contiguous within each patient-type
check <- episodes %>%
  group_by(patient_id, treatment_type) %>%
  summarise(
    n_episodes = n(),
    max_episode = max(episode_number),
    .groups = "drop"
  ) %>%
  filter(n_episodes != max_episode)  # Should be empty

if (nrow(check) > 0) {
  stop("Episode numbering is non-contiguous")
}
```

### Pitfall 2: Historical Flag Logic (First vs Last Date)
**What goes wrong:** Using `episode_start < HISTORICAL_CUTOFF` instead of `episode_stop < HISTORICAL_CUTOFF` causes "bridge episodes" to be incorrectly flagged as historical.

**Example:** A patient with treatment dates [1995-03-15, 2015-06-20]. If these fall in the same episode (unlikely due to 90-day gap, but possible if data has no intermediate records), the episode spans 1995-2015. Using `episode_start < 2012` flags it as historical, even though it contains modern data.

**Why it happens:** Misunderstanding the decision rule D-03: "An episode is flagged historical when ALL its dates fall before 2012-01-01."

**How to avoid:** Use `episode_stop < HISTORICAL_CUTOFF`. If the LAST date in an episode is pre-2012, then ALL dates in that episode are pre-2012 (dates are sorted chronologically).

**Warning signs:**
- Historical episodes with `episode_length_days > 365` (tumor registry dates are typically isolated single dates)
- Test output shows "bridge patients" (R/43_test_durations.R line 178) being flagged as historical

### Pitfall 3: Output Schema Mismatch with Phase 43
**What goes wrong:** Using different column names or ordering than Phase 43's per-patient output makes downstream scripts brittle.

**Why it happens:** Phase 44's output is episode-level (more granular) but should align with Phase 43's column naming conventions for consistency.

**How to avoid:**
- Use `patient_id` (not `ID`) to match Phase 43's CSV output pattern (R/43 line 585)
- Keep date columns as `episode_start`/`episode_stop` (not `first_date`/`last_date`) to distinguish from Phase 43's patient-level dates
- Use `episode_length_days` (not `span_days` or `duration_days`) for clarity

**Schema comparison:**

| Phase 43 (per-patient) | Phase 44 (per-episode) | Notes |
|------------------------|------------------------|-------|
| patient_id | patient_id | ✓ Matches |
| treatment_type | treatment_type | ✓ Matches |
| first_treatment_date | — | Episode-level has no "first across all episodes" |
| last_treatment_date | — | Episode-level has no "last across all episodes" |
| overall_span_days | — | Episode-level has per-episode span instead |
| distinct_treatment_dates | — | Episode-level has distinct_dates_in_episode |
| episode_count | — | Episode-level is ONE episode per row |
| — | episode_number | NEW in Phase 44 |
| — | episode_start | NEW (replaces first_treatment_date at episode level) |
| — | episode_stop | NEW (replaces last_treatment_date at episode level) |
| — | episode_length_days | NEW (replaces overall_span_days at episode level) |
| — | distinct_dates_in_episode | NEW (replaces distinct_treatment_dates at episode level) |
| — | historical_flag | NEW in Phase 44 |

### Pitfall 4: Forgetting to Filter Historical Episodes for Analysis
**What goes wrong:** Downstream analysis scripts include 1970s-1990s tumor registry dates in modern treatment timelines, creating nonsensical summary statistics.

**Why it happens:** The `historical_flag` column is designed as a filter key, but scripts forget to apply it.

**How to avoid:** Document clearly in RESEARCH.md and R/44 comments that `historical_flag = TRUE` rows should be filtered out for modern treatment analysis.

**Example:**
```r
# Modern episodes only (exclude historical tumor registry dates)
modern_episodes <- all_episodes %>% filter(!historical_flag)

# Historical episodes (tumor registry dates from 1970s-2000s)
historical_episodes <- all_episodes %>% filter(historical_flag)
```

**Warning signs:**
- Summary statistics show episode spans > 20 years
- Median episode start dates in the 1980s-1990s

## Code Examples

Verified patterns from Phase 43:

### Multi-Source Date Extraction (Reuse from R/43)
```r
# Source: R/43_treatment_durations.R lines 87-102
# Reuse directly — no modification needed

source("R/43_treatment_durations.R")

# Extract ALL chemotherapy dates across 7 PCORnet sources
dates_df <- extract_all_dates("Chemotherapy")
# Returns tibble: ID (character), treatment_date (Date)
```

### Episode Detection with Historical Flagging
```r
# Source: Modified from R/43_treatment_durations.R lines 464-503
# Stops at per-episode level, adds episode_number + historical_flag

calculate_episodes_detailed <- function(dates_df, gap_threshold = 90) {
  if (nrow(dates_df) == 0) {
    return(tibble(
      patient_id = character(0),
      episode_number = integer(0),
      episode_start = as.Date(character(0)),
      episode_stop = as.Date(character(0)),
      episode_length_days = numeric(0),
      distinct_dates_in_episode = integer(0),
      historical_flag = logical(0)
    ))
  }

  HISTORICAL_CUTOFF <- as.Date("2012-01-01")

  dates_df %>%
    group_by(ID) %>%
    arrange(treatment_date, .by_group = TRUE) %>%
    mutate(
      days_since_prev = as.numeric(treatment_date - lag(treatment_date)),
      new_episode = is.na(days_since_prev) | days_since_prev >= gap_threshold,
      episode_id = cumsum(new_episode)
    ) %>%
    group_by(ID, episode_id) %>%
    summarise(
      episode_start = min(treatment_date),
      episode_stop = max(treatment_date),
      episode_length_days = as.numeric(max(treatment_date) - min(treatment_date)),
      distinct_dates_in_episode = n(),
      .groups = "drop"
    ) %>%
    group_by(ID) %>%
    mutate(episode_number = row_number()) %>%
    ungroup() %>%
    mutate(historical_flag = episode_stop < HISTORICAL_CUTOFF) %>%
    select(
      patient_id = ID,
      episode_number,
      episode_start,
      episode_stop,
      episode_length_days,
      distinct_dates_in_episode,
      historical_flag
    )
}
```

### Per-Type CSV Output (Phase 43 Pattern)
```r
# Source: R/43_treatment_durations.R lines 574-591
# Adapted for episode-level output

TREATMENT_TYPES <- c("Chemotherapy", "Radiation", "SCT", "Immunotherapy")

for (type in TREATMENT_TYPES) {
  type_data <- episodes_list[[type]]

  # Clean filename: lowercase, underscored
  csv_name <- paste0(tolower(gsub(" ", "_", type)), "_episodes.csv")
  csv_path <- file.path(CONFIG$output_dir, csv_name)

  # Write with snake_case column names (already in D-08 schema)
  write.csv(type_data, csv_path, row.names = FALSE)
  message(glue("  Wrote {csv_path} ({nrow(type_data)} episodes)"))
}

# Output files:
#   chemotherapy_episodes.csv
#   radiation_episodes.csv
#   sct_episodes.csv
#   immunotherapy_episodes.csv
```

### Console Summary Statistics (Optional, per Claude's Discretion)
```r
# Source: Adapted from R/43_treatment_durations.R lines 510-535

log_episode_stats <- function(episodes_df, type_name) {
  if (nrow(episodes_df) == 0) {
    message(glue("\n  {type_name} Episodes: 0 (no data)"))
    return(invisible(NULL))
  }

  stats <- episodes_df %>%
    summarise(
      n_patients = n_distinct(patient_id),
      n_episodes = n(),
      n_historical = sum(historical_flag),
      pct_historical = round(100 * mean(historical_flag), 1),
      median_length = median(episode_length_days, na.rm = TRUE),
      median_dates = median(distinct_dates_in_episode, na.rm = TRUE)
    )

  message(glue("\n  {type_name} Summary:"))
  message(glue("    Patients: {stats$n_patients}"))
  message(glue("    Episodes: {stats$n_episodes} ({stats$n_historical} historical, {stats$pct_historical}%)"))
  message(glue("    Episode length (days): median={stats$median_length}"))
  message(glue("    Dates per episode: median={stats$median_dates}"))

  invisible(stats)
}
```

### Styled xlsx Summary Sheet (Phase 43 Pattern)
```r
# Source: R/43_treatment_durations.R lines 604-683
# Adapted for episode-level summary

wb <- wb_workbook()
wb$add_worksheet("Summary")

# Title
wb$add_data(sheet = "Summary", x = "Treatment Episodes by Type",
            start_row = 1, start_col = 1)
wb$add_font(sheet = "Summary", dims = "A1",
            name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937"))
wb$merge_cells(sheet = "Summary", dims = "A1:G1")

# Subtitle
wb$add_data(sheet = "Summary",
            x = glue("Generated: {Sys.Date()} | Gap threshold: {GAP_THRESHOLD} days | Historical cutoff: 2012-01-01"),
            start_row = 2, start_col = 1)
wb$add_font(sheet = "Summary", dims = "A2",
            name = "Calibri", size = 10, color = wb_color("FF6B7280"))
wb$merge_cells(sheet = "Summary", dims = "A2:G2")

# Headers
summary_headers <- c("Treatment Type", "Patients", "Episodes", "Historical Episodes",
                     "% Historical", "Median Length (days)", "Median Dates/Episode")
for (i in seq_along(summary_headers)) {
  wb$add_data(sheet = "Summary", x = summary_headers[i],
              start_row = 4, start_col = i)
}
wb$add_fill(sheet = "Summary", dims = "A4:G4", color = wb_color("FF374151"))
wb$add_font(sheet = "Summary", dims = "A4:G4",
            name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))

# Data rows (one per treatment type)
# ... (follow Phase 43 pattern lines 633-674)
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Patient-level aggregation only | Episode-level detail + patient-level summary | Phase 44 (2026-05-07) | Enables longitudinal analysis of treatment courses, relapse detection, treatment gap identification |
| No historical date flagging | `historical_flag` boolean | Phase 44 (2026-05-07) | Separates modern PCORnet data (2012-2025) from tumor registry historical records (1970s-2000s) for cleaner modern treatment analysis |
| Hardcoded 90-day gap | `GAP_THRESHOLD` constant in R/00_config.R | Phase 43 (2026-05-05) | Consistent across all scripts; easy to tune if clinical requirements change |

**Deprecated/outdated:**
- No deprecated patterns — Phase 43 is current (completed 2026-05-05)

## Open Questions

1. **Should episode-level output include patient-level rollup columns?**
   - What we know: Phase 43 outputs per-patient summaries (first/last date across all episodes, total episode count). Phase 44 outputs per-episode detail.
   - What's unclear: Would downstream analysis benefit from having BOTH per-episode AND per-patient columns in the same row? (e.g., `patient_first_treatment_date`, `patient_last_treatment_date` alongside `episode_start`, `episode_stop`)
   - Recommendation: Start with pure per-episode schema (D-08). If downstream scripts need patient-level context, they can left_join Phase 43's output by `patient_id` + `treatment_type`. Keeps Phase 44 focused and avoids column bloat.

2. **Historical episodes: include in xlsx detail sheets or separate sheet?**
   - What we know: Historical episodes will appear in the RDS artifact and per-type CSVs with `historical_flag = TRUE`
   - What's unclear: Should the xlsx detail sheets (Chemotherapy Episodes, Radiation Episodes, etc.) include historical rows, or should historical episodes get a separate "Historical Episodes" sheet?
   - Recommendation: Include historical episodes in per-type detail sheets with conditional row styling (gray fill for historical rows) to make them visually distinct. Analysts can filter `historical_flag = FALSE` in Excel if needed. A separate "Historical Episodes" summary sheet (counts per type, decade distribution) would be useful as sheet 6.

3. **Episode numbering: reset on type switch or global?**
   - What we know: D-09 specifies "one row per patient per treatment type per episode"
   - What's unclear: Is episode_number scoped to treatment type (Chemo episode 1, Rad episode 1 for same patient) or global (episodes 1-5 across all types)?
   - Recommendation: Per-type numbering (as shown in code examples). Matches the "per treatment type per episode" specification. Global numbering would require cross-type date sorting and create ambiguity when patient receives concurrent treatments.

## Environment Availability

No external dependencies beyond base R + tidyverse + openxlsx2 (already installed via project renv). All required packages are in use by Phase 43.

## Sources

### Primary (HIGH confidence)
- R/43_treatment_durations.R — Phase 43 implementation (lines 1-787) showing episode detection logic at lines 476-492
- R/43_test_durations.R — Phase 43 verification tests (lines 1-296) documenting pre-2000 date handling and "bridge patient" pattern
- .planning/phases/44-treatment-episode-start-stop-dates/44-CONTEXT.md — User decisions D-01 through D-13
- .planning/phases/43-establish-treatment-lengths-for-sct-chemo-and-radiation/43-CONTEXT.md — Prior phase decisions referenced in Phase 44 context
- .planning/STATE.md — Key project decision: "Pre-2000 dates retained as real tumor registry historical data, not sentinels"

### Secondary (MEDIUM confidence)
- R/42_treatment_codes_resolved.R — Per-type xlsx output pattern using `write_resolved_xlsx()` function (lines 52-134)
- R/00_config.R — CONFIG paths (lines 29-75), TREATMENT_CODES (lines 412+), backend selection (lines 78-92)
- R/10_treatment_payer.R — Multi-source date extraction pattern (lines 100-200) that Phase 43 extends
- CLAUDE.md — Project constraints (R ecosystem, named predicates, HiPerGator environment)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — Phase 43 already uses all required packages (dplyr, lubridate, glue, openxlsx2, purrr)
- Architecture: HIGH — Phase 44 is a subset of Phase 43's internal computation (lines 486-492), not a new pattern
- Historical date handling: HIGH — Phase 43 verification tests (R/43_test_durations.R lines 131-216) already document pre-2000 date patterns
- Episode numbering: HIGH — Standard dplyr `group_by() %>% mutate(row_number())` pattern
- Output formatting: HIGH — Follows Phase 43's established RDS + xlsx + CSV pattern (lines 568-787)

**Research date:** 2026-05-07
**Valid until:** 60 days (stable domain — R data transformation patterns don't change rapidly; Phase 43 implementation is current as of 2026-05-05)
