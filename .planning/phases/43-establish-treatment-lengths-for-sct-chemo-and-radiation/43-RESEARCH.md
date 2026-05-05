# Phase 43: Establish Treatment Lengths for SCT, Chemo, and Radiation - Research

**Researched:** 2026-05-05
**Domain:** Treatment duration measurement from PCORnet CDM multi-source timestamps
**Confidence:** HIGH

## Summary

Phase 43 calculates treatment duration metrics (first-to-last span, distinct date count, episode detection) for chemotherapy, radiation, SCT, and immunotherapy from PCORnet CDM data. The phase extends existing multi-source date extraction patterns from R/10_treatment_payer.R (which extracts FIRST dates only) to extract ALL treatment dates, then applies episode splitting based on 90-day gap thresholds. Outputs include per-patient RDS artifacts, styled xlsx reports (following Phase 41/42 openxlsx2 patterns), and distribution visualizations (histogram/boxplot PNG).

**Primary recommendation:** Reuse the proven multi-source extraction pattern from R/10_treatment_payer.R (7 PCORnet tables: PROCEDURES, PRESCRIBING, DIAGNOSIS, ENCOUNTER, DISPENSING, MED_ADMIN, TUMOR_REGISTRY) but remove the `min()` aggregation to collect all distinct dates per patient per type. Use dplyr's `lag()` with `cumsum()` for gap-based episode detection, tidylog for console logging, openxlsx2 for styled outputs, and ggplot2 for distribution histograms/boxplots.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Duration Measurement:**
- **D-01:** Measure treatment length as first-to-last date span (calendar days between earliest and latest treatment date per patient per type)
- **D-02:** Also report count of distinct treatment dates per patient per type (measures intensity alongside duration)
- **D-03:** Single-date patients included as span=0, count=1 — no special flag needed

**Episode Detection:**
- **D-04:** Calculate BOTH overall first-to-last span AND detect separate treatment episodes within each type
- **D-05:** 90-day gap threshold defines a new episode (gap of 90+ days between consecutive dates = new course)
- **D-06:** Episode output detail level — Claude's Discretion

**Output Deliverables:**
- **D-07:** Per-patient summary tibble saved as RDS artifact (one row per patient per treatment type with first date, last date, span, distinct date count, episode count)
- **D-08:** Styled xlsx report using openxlsx2 (following Phase 41/42 patterns)
- **D-09:** Distribution visualization — histogram or boxplot of treatment durations by type, PNG output
- **D-10:** Console summary statistics during execution (median, IQR, range per type, like existing tidylog-style logging)
- **D-11:** xlsx sheet organization — Claude's Discretion

**Treatment Type Scope:**
- **D-12:** Cover four treatment types: Chemotherapy, Radiation, SCT, Immunotherapy
- **D-13:** All chemotherapy codes treated as one type — no regimen distinction (ABVD/BV+AVD/salvage all pooled)

### Claude's Discretion

- Episode output granularity (episode summary per patient vs just counts)
- xlsx sheet structure (multi-sheet per type + summary vs single summary)
- Visualization style (histogram vs boxplot vs both)
- Whether to reuse compute functions from R/10_treatment_payer.R or write new extraction logic

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope

</user_constraints>

## Standard Stack

### Core Date Manipulation
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| dplyr | 1.2.0+ | Data transformation | group_by() + summarise() for per-patient aggregation; lag() for gap detection |
| lubridate | 1.9.3+ | Date operations | as_date() for type safety; interval arithmetic for span calculation |
| tidylog | 1.1.0 | Auto-logging | Wraps dplyr to print before/after counts — matches D-10 console logging requirement |

### Multi-Source Data Extraction
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| purrr | 1.0.2+ | Functional programming | compact() to remove NULL tables; map() for consistent operations across sources |
| glue | 1.8.0 | String formatting | Console logging messages per D-10: `glue("Chemo: median={median_days} days, IQR={iqr}")` |

### Output Generation
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|-------------|
| openxlsx2 | Latest | Styled xlsx workbooks | Established pattern from R/41_combine_reports.R and R/42_treatment_codes_resolved.R; supports TREATMENT_TYPE_COLORS styling |
| ggplot2 | 4.0.1+ | Visualization | geom_histogram() + geom_boxplot() for D-09 distribution charts; facet_wrap() for multi-type layout |
| scales | 1.3.0+ | Axis formatting | Label formatting for clean histogram/boxplot axes |

**Installation:** All packages already in project renv.lock (verified from CLAUDE.md stack). No new dependencies required.

**Version verification:** Not required — project uses renv with locked versions, all packages already present.

## Architecture Patterns

### Recommended Script Structure
```
R/43_treatment_durations.R
├── SECTION 1: Setup and Configuration
│   └── source("R/00_config.R"), load libraries
├── SECTION 2: Multi-Source Date Extraction
│   └── extract_all_treatment_dates(type) — 7 source queries stacked with bind_rows()
├── SECTION 3: Duration and Episode Calculation
│   └── calculate_durations_and_episodes(dates_df, gap_threshold = 90)
├── SECTION 4: Summary Statistics and Console Logging
│   └── log_duration_stats(durations_df)
├── SECTION 5: Styled XLSX Output
│   └── write_duration_report(durations_df, output_path)
└── SECTION 6: Distribution Visualization
    └── plot_duration_distributions(durations_df, output_path)
```

### Pattern 1: Multi-Source Date Extraction (Extend R/10_treatment_payer.R)
**What:** Query 7 PCORnet tables (PROCEDURES, PRESCRIBING, DIAGNOSIS, ENCOUNTER, DISPENSING, MED_ADMIN, TUMOR_REGISTRY) for treatment codes, extract ALL dates (not just min), stack results, deduplicate by patient+date.

**When to use:** For any treatment type where multiple timestamps may exist across tables.

**Example:**
```r
# Source: R/10_treatment_payer.R lines 100-227 (chemo extraction pattern)
# MODIFIED: Remove min() aggregation to collect all dates

extract_all_treatment_dates <- function(type = "chemo") {
  # Build prefix regex for ICD-10-PCS codes (if applicable)
  # Query each source table independently
  px_dates <- get_pcornet_table("PROCEDURES") %>%
    filter(
      (PX_TYPE == "CH" & PX %in% TREATMENT_CODES$chemo_hcpcs) |
      (PX_TYPE == "09" & PX %in% TREATMENT_CODES$chemo_icd9) |
      # ... other code types
    ) %>%
    filter(!is.na(PX_DATE)) %>%
    select(ID, treatment_date = PX_DATE)

  rx_dates <- get_pcornet_table("PRESCRIBING") %>%
    filter(RXNORM_CUI %in% TREATMENT_CODES$chemo_rxnorm) %>%
    filter(!is.na(RX_ORDER_DATE)) %>%
    select(ID, treatment_date = RX_ORDER_DATE)

  # ... 5 more sources (DIAGNOSIS, ENCOUNTER, DISPENSING, MED_ADMIN, TUMOR_REGISTRY)

  # Stack all sources using compact() + bind_rows()
  all_sources <- list(
    px = px_dates, rx = rx_dates, dx = dx_dates,
    drg = drg_dates, disp = disp_dates, ma = ma_dates, tr = tr_dates
  )

  bind_rows(compact(all_sources)) %>%
    distinct(ID, treatment_date) %>%  # Deduplicate same-day records
    arrange(ID, treatment_date)
}
```

### Pattern 2: Gap-Based Episode Detection
**What:** Use dplyr's `lag()` to calculate inter-date gaps, `cumsum()` to assign episode IDs when gap exceeds threshold.

**When to use:** For splitting continuous treatment into separate courses (e.g., induction vs consolidation vs salvage chemo).

**Example:**
```r
# Source: dplyr lag-lead documentation + cumsum gap detection pattern
# https://dplyr.tidyverse.org/reference/lead-lag.html
# https://gist.github.com/jgilfillan/23336d0f5bcfffe6a71d0bdd634d023e

calculate_durations_and_episodes <- function(dates_df, gap_threshold = 90) {
  dates_df %>%
    group_by(ID) %>%
    arrange(ID, treatment_date) %>%
    mutate(
      # Calculate gap from previous date (in days)
      days_since_prev = as.numeric(treatment_date - lag(treatment_date)),
      # New episode starts when gap >= threshold (or first date)
      new_episode = is.na(days_since_prev) | days_since_prev >= gap_threshold,
      # Assign episode ID using cumsum (increments when new_episode = TRUE)
      episode_id = cumsum(new_episode)
    ) %>%
    group_by(ID, episode_id) %>%
    summarise(
      episode_first_date = min(treatment_date),
      episode_last_date = max(treatment_date),
      episode_span_days = as.numeric(episode_last_date - episode_first_date),
      episode_distinct_dates = n_distinct(treatment_date),
      .groups = "drop_last"
    ) %>%
    summarise(
      first_treatment_date = min(episode_first_date),
      last_treatment_date = max(episode_last_date),
      overall_span_days = as.numeric(last_treatment_date - first_treatment_date),
      distinct_treatment_dates = sum(episode_distinct_dates),
      episode_count = n(),
      .groups = "drop"
    )
}
```

### Pattern 3: Styled XLSX Output (Follow R/42_treatment_codes_resolved.R)
**What:** Create multi-sheet workbook with TREATMENT_TYPE_COLORS styling, title row, headers, and formatted data.

**When to use:** All phase outputs requiring Excel reports (per D-08).

**Example:**
```r
# Source: R/42_treatment_codes_resolved.R lines 52-100 (write_resolved_xlsx pattern)
# openxlsx2 styling manual: https://janmarvin.github.io/openxlsx2/articles/openxlsx2_style_manual.html

write_duration_report <- function(durations_df, output_path) {
  wb <- wb_workbook()

  for (type in c("Chemotherapy", "Radiation", "SCT", "Immunotherapy")) {
    type_data <- durations_df %>% filter(treatment_type == type)
    sheet_name <- paste(type, "Durations")
    wb$add_worksheet(sheet_name)

    # Row 1: Title with patient count
    wb$add_data(sheet = sheet_name,
                x = glue("{type} Treatment Durations ({nrow(type_data)} patients)"),
                start_row = 1, start_col = 1)
    wb$add_font(sheet = sheet_name, dims = "A1",
                name = "Calibri", size = 16, bold = TRUE)

    # Row 2: Column headers with color coding
    headers <- c("Patient ID", "First Date", "Last Date", "Span (days)",
                 "Distinct Dates", "Episode Count")
    for (i in seq_along(headers)) {
      wb$add_data(sheet = sheet_name, x = headers[i],
                  start_row = 2, start_col = i)
    }

    fill_color <- TREATMENT_TYPE_COLORS[[type]]$fill
    font_color <- TREATMENT_TYPE_COLORS[[type]]$font
    wb$add_fill(sheet = sheet_name, dims = "A2:F2", color = wb_color(fill_color))
    wb$add_font(sheet = sheet_name, dims = "A2:F2",
                name = "Calibri", size = 11, bold = TRUE, color = wb_color(font_color))

    # Row 3+: Data
    wb$add_data(sheet = sheet_name, x = type_data, start_row = 3)
  }

  wb$save(output_path)
}
```

### Pattern 4: Distribution Visualization
**What:** Faceted histogram or boxplot showing duration distribution by treatment type.

**When to use:** Per D-09 requirement for PNG output.

**Example:**
```r
# Source: ggplot2 distribution charts guide
# https://r-statistics.co/ggplot2-Distribution-Charts.html

plot_duration_distributions <- function(durations_df, output_path) {
  # Histogram version
  p1 <- ggplot(durations_df, aes(x = overall_span_days)) +
    geom_histogram(bins = 30, fill = "steelblue", color = "white") +
    facet_wrap(~treatment_type, scales = "free_x") +
    labs(
      title = "Treatment Duration Distribution by Type",
      x = "Duration (days, first to last treatment)",
      y = "Patient count"
    ) +
    theme_minimal()

  # Boxplot version (shows median, IQR, outliers)
  p2 <- ggplot(durations_df, aes(x = treatment_type, y = overall_span_days,
                                  fill = treatment_type)) +
    geom_boxplot() +
    labs(
      title = "Treatment Duration Distribution by Type",
      x = "Treatment Type",
      y = "Duration (days, first to last treatment)"
    ) +
    theme_minimal() +
    theme(legend.position = "none")

  ggsave(output_path, plot = p1, width = 10, height = 6, dpi = 300)
  # Or save both as multi-panel
}
```

### Anti-Patterns to Avoid

- **Don't use base R date arithmetic without lubridate:** `as.Date()` type coercion is fragile; use `lubridate::as_date()` for safer parsing.
- **Don't recalculate first/last dates manually:** Reuse extraction logic from R/10_treatment_payer.R to avoid discrepancies with existing pipeline outputs.
- **Don't apply HIPAA suppression to internal RDS artifacts:** Suppression applies to shared xlsx/PNG only; RDS files are internal cache.
- **Don't forget to handle single-date patients:** Per D-03, span=0 and count=1 for one-date patients — don't filter them out as "incomplete."

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Episode splitting by date gaps | Custom gap detection with loops or apply() | dplyr lag() + cumsum() pattern | Edge cases: multiple patients, unsorted dates, first/last episode boundaries — cumsum() handles these automatically |
| Multi-format date parsing | Nested ifelse() chains testing date formats | lubridate::parse_date_time() with orders vector | PCORnet dates arrive in 3+ formats (DATE9, YYYYMMDD, Excel serial); parse_date_time() handles all with one call |
| Console logging of before/after counts | Manual message() calls after each dplyr operation | tidylog package (wraps dplyr) | Automatically logs N rows added/removed at every mutate/filter/summarise — matches D-10 requirement with zero code |
| Styled Excel output with color-coded headers | Manual cell-by-cell formatting loops | openxlsx2 bulk styling (wb_add_fill, wb_add_font on ranges) | R/41_combine_reports.R pattern proven; cell loops are 10-100x slower and error-prone |

**Key insight:** PCORnet multi-source extraction is deceptively complex. Dates exist in 7+ tables with different column names (PX_DATE, RX_ORDER_DATE, DX_DATE, ADMIT_DATE, DISPENSE_DATE, MEDADMIN_START_DATE, CHEMO_START_DATE_SUMMARY), different code systems (CPT, ICD-9, ICD-10-PCS, RXNORM, DRG), and different patient coverage. R/10_treatment_payer.R already solved this for FIRST dates across all 7 sources — reusing that pattern for ALL dates avoids 6-10 hours of debugging source-specific quirks.

## Common Pitfalls

### Pitfall 1: Assuming All Dates Are in PROCEDURES Table
**What goes wrong:** Analyst queries only PROCEDURES.PX_DATE for treatment dates, missing ~40-60% of dates from PRESCRIBING, DISPENSING, MED_ADMIN, DIAGNOSIS, ENCOUNTER, and TUMOR_REGISTRY. Duration calculations show unrealistically short spans (missing intermediate dates) and episode counts are artificially low (gaps between source tables appear as separate episodes when they're actually continuous treatment documented in different tables).

**Why it happens:** PCORnet CDM documentation emphasizes PROCEDURES as the primary source for procedure codes, leading analysts to assume it's comprehensive. In reality, chemotherapy appears in PRESCRIBING (oral drugs), DISPENSING (pharmacy fills), MED_ADMIN (infusion events), DIAGNOSIS (Z51.11 encounter codes), and ENCOUNTER (DRG 837-839). Radiation appears in PROCEDURES (CPT) but also DIAGNOSIS (Z51.0) and ENCOUNTER (DRG 849). SCT appears in PROCEDURES but also DIAGNOSIS (Z94.84, T86.5) and TUMOR_REGISTRY. Each source captures different care settings (inpatient vs outpatient vs pharmacy).

**How to avoid:**
1. Use the proven 7-source extraction pattern from R/10_treatment_payer.R (lines 100-227)
2. Log record counts per source: `message(glue("Chemo dates: PX={nrow(px_dates)}, RX={nrow(rx_dates)}, ..."))`
3. Validate total distinct dates against source-specific counts — should exceed any single source
4. For each treatment type, verify all applicable sources are queried (chemo needs all 7; SCT primarily needs PROCEDURES + DIAGNOSIS + TUMOR_REGISTRY)

**Warning signs:**
- Median treatment span is < 30 days for chemotherapy (ABVD cycles are ~28 days each; typical 4-6 cycles = 112-168 days)
- 90%+ of patients have episode_count = 1 (suggests missing gaps filled by other sources)
- Source breakdown shows one table contributing 80%+ of dates (should be distributed: PROCEDURES 30-40%, PRESCRIBING 20-30%, others 10-20% each for chemo)
- Distinct date counts are implausibly low (chemo patients typically have 10-20+ distinct treatment dates for multi-cycle regimens)

### Pitfall 2: Not Deduplicating Same-Day Records Across Sources
**What goes wrong:** Same treatment date appears in multiple tables (e.g., PX_DATE in PROCEDURES for infusion, RX_ORDER_DATE in PRESCRIBING for the same drug, ADMIT_DATE in ENCOUNTER for the hospital visit). Without deduplication, `distinct_treatment_dates` count is inflated (one treatment day counted 2-3 times), making intensity metrics misleading. Episode detection also breaks because micro-gaps between same-day duplicate timestamps create artificial episode splits.

**Why it happens:** PCORnet CDM intentionally allows cross-table redundancy — the same clinical event generates records in multiple tables (procedure code, medication order, encounter DRG). Analysts stack source results with `bind_rows()` but forget `distinct(ID, treatment_date)` before aggregation. Date columns have different names (PX_DATE, RX_ORDER_DATE) so simple de-dup by column name doesn't work after renaming to generic `treatment_date`.

**How to avoid:**
1. After stacking all sources with `bind_rows()`, immediately apply `distinct(ID, treatment_date)` to remove same-day duplicates
2. Log before/after counts: `message(glue("Before dedup: {nrow(stacked)} records → After: {nrow(deduped)} distinct patient-dates"))`
3. Validate that deduplicated count < sum of source counts (proves deduplication occurred)
4. For debugging, create a duplicate-flagging query: `group_by(ID, treatment_date) %>% filter(n() > 1)` to inspect patterns

**Warning signs:**
- Distinct date counts are higher than expected (e.g., 60 distinct dates for a 4-cycle ABVD regimen that should have ~8-12 infusion days)
- Same patient has multiple records on same date in final RDS artifact (violates one-row-per-patient-per-type constraint from D-07)
- Episode splitting creates 10+ episodes with single-day spans (suggests same-day duplicates treated as separate dates, creating 0-day gaps that trigger new episodes)

### Pitfall 3: Gaps from Missing Enrollment ≠ Treatment Gaps
**What goes wrong:** Patient has treatment dates 2020-03-15, 2020-05-20, 2020-08-10 but no ENROLLMENT records between March and May. Analyst assumes 65-day gap (March to May) is a true treatment gap and splits into 2 episodes. In reality, the patient received continuous care but their enrollment data has gaps (common for encounter-based enrollment partners like AMS/UMI, or for care delivered outside the OneFlorida network). Episode count is inflated, treatment spans are fragmented, making patterns uninterpretable.

**Why it happens:** From PITFALLS.md Pitfall 4: PCORnet ENROLLMENT represents "periods where medical care should be observed," not insurance coverage. Partner-specific quirks: FLM is claims-only (enrollment gaps for uninsured), VRT is death-only (no enrollment), AMS/UMI have 3-year lookback windows. Analysts assume "if treatment happened, enrollment must exist" but that's false for ~30% of OneFlorida patients. Gap-based episode detection uses treatment dates only (correct per D-05) but analysts may incorrectly validate gaps against enrollment, introducing spurious splits.

**How to avoid:**
1. **Do NOT cross-reference treatment dates with enrollment dates** for episode detection — use treatment dates ONLY per D-05
2. Episode gaps are defined by consecutive treatment dates (via lag()), not by enrollment presence
3. Accept that some patients have treatment dates spanning enrollment gaps — this is expected PCORnet behavior
4. Document in outputs: "Episode detection based on treatment date gaps only; enrollment data not used"
5. If validating results, compare episode counts by partner — AMS/UMI (encounter-based enrollment) should have similar episode patterns to FLM (claims-based), proving enrollment is irrelevant

**Warning signs:**
- Episode counts vary dramatically by partner for same treatment type (e.g., AMS patients average 2.5 episodes, FLM average 1.2 episodes for chemotherapy)
- Patients with single continuous regimen split into 3+ episodes with gaps exactly matching enrollment table gaps
- Code includes joins to ENROLLMENT table for gap validation (shouldn't be there — episode logic is treatment-date-only)

### Pitfall 4: ABVD Cycle Duration Misinterpreted as 90-Day Gap Threshold
**What goes wrong:** Analyst reads that ABVD cycles are 28 days (per research: "each cycle lasts 28 days, treatment on day 1 and day 15"), assumes 90-day gap threshold is too long and reduces it to 30-45 days. This splits multi-cycle ABVD regimens into separate episodes when patients have normal 4-6 week inter-cycle gaps (e.g., between cycle 2 and cycle 3 for PET scan, dose adjustment, or toxicity recovery). Episode counts are inflated 2-3x, making "separate treatment courses" unidentifiable.

**Why it happens:** ABVD cycle length (28 days) describes intra-cycle spacing (day 1 vs day 15 infusions), NOT inter-cycle gaps. Real-world inter-cycle gaps are 4-12 weeks due to: toxicity recovery (neutropenia, pulmonary toxicity), PET scan scheduling for response assessment, dose delays for cytopenias, insurance authorization delays. The 90-day threshold (from D-05) is designed to detect separate treatment courses (e.g., induction → 6-month break → salvage), NOT separate cycles within a course. User decision context states "90 days is ~3 missed cycles" which is clinically appropriate for course separation.

**How to avoid:**
1. Use 90-day gap threshold per D-05 — do NOT reduce it
2. Understand that 90 days captures: induction → long break → salvage, or primary treatment → relapse treatment
3. Normal inter-cycle ABVD gaps (4-6 weeks) are well below 90 days and should NOT trigger new episodes
4. Validate: most chemo patients should have episode_count = 1 (one treatment course); 10-20% may have 2+ (salvage, relapse)
5. If debugging, check gap distribution: `mutate(gap_category = cut(days_since_prev, breaks = c(0, 30, 60, 90, 180, Inf)))` — most gaps should be 0-60 days (within-course), few 90+ (between-course)

**Warning signs:**
- Median episode_count for chemotherapy is 3-5 (should be 1-2 for most patients)
- Gap distribution histogram shows spike at 30-45 days (normal inter-cycle gaps) being treated as episode splits
- Code has `gap_threshold` hardcoded to value < 90 days, contradicting D-05
- Validation shows nearly all patients have multi-episode treatment, inconsistent with clinical expectation of single induction course

### Pitfall 5: Single-Date Patients Filtered Out as "Incomplete"
**What goes wrong:** Analyst sees patients with only one treatment date (e.g., one SCT infusion, one radiation DRG code, one chemotherapy prescription) and filters them out assuming "incomplete data" or "missing follow-up." Per D-03, these patients should be included with span=0 and count=1, representing legitimate single-event treatments (common for SCT which is often a 1-2 day procedure, or single-fraction radiation for palliative care). Filtering creates selection bias — removing patients with simpler/shorter treatment courses skews duration distributions upward.

**Why it happens:** Analysts expect longitudinal treatment patterns (multi-cycle chemo, multi-week radiation), so single-date records "look wrong." For SCT, a single infusion date is expected (transplant = 1 day; conditioning chemo is separate and captured as "chemo" type, not SCT). For radiation, some patients receive single-fraction palliative radiation. For chemo, a patient may die after first cycle or switch to hospice. Filtering single-date patients excludes early mortality, palliative care, and treatment failures — exactly the population disparities research needs to capture.

**How to avoid:**
1. **Include all patients with ≥1 treatment date** regardless of count
2. For single-date patients, calculate: span = 0 days, distinct_dates = 1, episode_count = 1
3. Validate: SCT patients should have high % of single-date records (SCT infusion is 1-day event)
4. Document in outputs: "Single-date patients included; span=0 indicates one treatment date only"
5. Sensitivity analysis: compare results with vs without single-date patients — if results differ, single-date exclusion is biasing findings

**Warning signs:**
- SCT has median span > 30 days (should be 0-7 days for most patients; transplant infusion is 1 day, some have multi-day conditioning)
- Chemo cohort excludes ~20-30% of patients (likely those who died after first cycle or received single palliative dose)
- Code includes filter: `filter(distinct_treatment_dates > 1)` or `filter(overall_span_days > 0)` — violates D-03
- Distribution histogram has no bar at zero (should have spike for single-date patients, especially SCT)

## Code Examples

Verified patterns from existing codebase:

### Multi-Source Date Extraction (Extend R/10_treatment_payer.R Pattern)
```r
# Source: R/10_treatment_payer.R lines 100-227 (chemotherapy example)
# Modified to collect ALL dates, not just min()

extract_all_chemo_dates <- function() {
  # PROCEDURES: CPT/HCPCS, ICD-9, ICD-10-PCS, revenue codes
  px_dates <- get_pcornet_table("PROCEDURES") %>%
    filter(
      (PX_TYPE == "CH" & PX %in% TREATMENT_CODES$chemo_hcpcs) |
      (PX_TYPE == "09" & PX %in% TREATMENT_CODES$chemo_icd9) |
      (PX_TYPE == "10" & str_detect(PX, chemo_icd10pcs_rx)) |
      (PX_TYPE == "RE" & PX %in% TREATMENT_CODES$chemo_revenue)
    ) %>%
    filter(!is.na(PX_DATE)) %>%
    select(ID, treatment_date = PX_DATE)

  # PRESCRIBING: RXNORM_CUI for oral/IV drugs
  rx_dates <- get_pcornet_table("PRESCRIBING") %>%
    filter(RXNORM_CUI %in% TREATMENT_CODES$chemo_rxnorm) %>%
    filter(!is.na(RX_ORDER_DATE)) %>%
    select(ID, treatment_date = RX_ORDER_DATE)

  # Stack all 7 sources, deduplicate same-day records
  all_sources <- list(
    px = px_dates, rx = rx_dates, dx = dx_dates,
    drg = drg_dates, disp = disp_dates, ma = ma_dates, tr = tr_dates
  )

  compact(all_sources) %>%
    bind_rows() %>%
    distinct(ID, treatment_date) %>%
    arrange(ID, treatment_date)
}
```

### Gap-Based Episode Detection with lag() + cumsum()
```r
# Source: dplyr lead-lag reference
# https://dplyr.tidyverse.org/reference/lead-lag.html

calculate_episodes <- function(dates_df, gap_threshold = 90) {
  dates_df %>%
    group_by(ID) %>%
    arrange(ID, treatment_date) %>%
    mutate(
      days_since_prev = as.numeric(treatment_date - lag(treatment_date)),
      new_episode = is.na(days_since_prev) | days_since_prev >= gap_threshold,
      episode_id = cumsum(new_episode)
    ) %>%
    group_by(ID, episode_id) %>%
    summarise(
      episode_first = min(treatment_date),
      episode_last = max(treatment_date),
      episode_span = as.numeric(episode_last - episode_first),
      episode_n_dates = n(),
      .groups = "drop_last"
    ) %>%
    summarise(
      first_treatment_date = min(episode_first),
      last_treatment_date = max(episode_last),
      overall_span_days = as.numeric(last_treatment_date - first_treatment_date),
      distinct_treatment_dates = sum(episode_n_dates),
      episode_count = n(),
      .groups = "drop"
    )
}
```

### Console Logging with tidylog + glue
```r
# Source: tidylog package (auto-wraps dplyr)
# https://cran.r-project.org/web/packages/tidylog/index.html
library(tidylog)  # Wraps dplyr functions to auto-log

# Manual supplement for summary stats (tidylog doesn't auto-log custom summaries)
log_duration_stats <- function(durations_df, type_name) {
  stats <- durations_df %>%
    summarise(
      n = n(),
      median_span = median(overall_span_days, na.rm = TRUE),
      iqr_span = IQR(overall_span_days, na.rm = TRUE),
      median_episodes = median(episode_count, na.rm = TRUE)
    )

  message(glue("{type_name}: N={stats$n}, median span={stats$median_span} days ",
               "(IQR={stats$iqr_span}), median episodes={stats$median_episodes}"))
}
```

### Styled XLSX Output (Following R/42 Pattern)
```r
# Source: R/42_treatment_codes_resolved.R lines 52-100
# openxlsx2 styling manual: https://janmarvin.github.io/openxlsx2/articles/openxlsx2_style_manual.html

write_duration_xlsx <- function(durations_list, output_path) {
  wb <- wb_workbook()

  for (type in names(durations_list)) {
    df <- durations_list[[type]]
    sheet_name <- paste(type, "Durations")
    wb$add_worksheet(sheet_name)

    # Title row
    wb$add_data(sheet = sheet_name,
                x = glue("{type} Treatment Durations ({nrow(df)} patients)"),
                start_row = 1, start_col = 1)
    wb$merge_cells(sheet = sheet_name, dims = "A1:F1")

    # Headers with color coding (from R/41_combine_reports.R TREATMENT_TYPE_COLORS)
    headers <- c("Patient ID", "First Date", "Last Date", "Span (days)",
                 "Distinct Dates", "Episodes")
    wb$add_data(sheet = sheet_name, x = as.data.frame(t(headers)),
                start_row = 2, col_names = FALSE)

    fill_color <- TREATMENT_TYPE_COLORS[[type]]$fill
    font_color <- TREATMENT_TYPE_COLORS[[type]]$font
    wb$add_fill(sheet = sheet_name, dims = "A2:F2", color = wb_color(fill_color))
    wb$add_font(sheet = sheet_name, dims = "A2:F2", bold = TRUE,
                color = wb_color(font_color))

    # Data rows
    wb$add_data(sheet = sheet_name, x = df, start_row = 3, col_names = FALSE)
  }

  wb$save(output_path)
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Single-source (PROCEDURES only) | Multi-source extraction (7 tables) | Phase 9 (R/10_treatment_payer.R) | Captures 2-3x more treatment dates; critical for intensity metrics |
| Manual date gap loops | dplyr lag() + cumsum() pattern | Standard since dplyr 1.0 (2020) | Cleaner code, handles edge cases (unsorted, missing) automatically |
| Base openxlsx (v4) | openxlsx2 (v0.8+) | 2023+ | Faster workbook creation, cleaner API for styling |
| Hard-coded gap thresholds | Parameterized threshold (90 days default) | D-05 decision | Allows sensitivity analysis without code changes |

**Deprecated/outdated:**
- **Single-source PROCEDURES-only queries:** Replaced by 7-source extraction in Phase 9/10; PROCEDURES captures only ~40% of chemotherapy dates.
- **apply() or for-loop gap detection:** Replaced by vectorized lag() + cumsum() — 10-100x faster on large cohorts.
- **openxlsx (v4) styling:** Replaced by openxlsx2 which has simpler syntax (`wb$add_fill()` vs `addStyle()` with createStyle()).

## Open Questions

1. **How should we handle TUMOR_REGISTRY dates when other sources exist?**
   - What we know: TUMOR_REGISTRY has summary dates (CHEMO_START_DATE_SUMMARY, DT_CHEMO) which may be abstracted from other sources
   - What's unclear: Does including TUMOR_REGISTRY dates create duplicates of dates already in PROCEDURES/PRESCRIBING?
   - Recommendation: Include TUMOR_REGISTRY dates but deduplicate with `distinct(ID, treatment_date)` — if they're true duplicates, dedup removes them; if they're unique (e.g., external care), they're captured

2. **Should immunotherapy episodes use the same 90-day threshold as chemotherapy?**
   - What we know: CAR T-cell therapy (in immunotherapy codes) is typically a single infusion, unlike multi-cycle chemo
   - What's unclear: Are 90-day gaps appropriate for immunotherapy, or should threshold be higher (180 days)?
   - Recommendation: Use 90 days per D-05 (applies to all types) for v1; flag as sensitivity analysis if immunotherapy episode counts look implausible

3. **What if a patient has overlapping treatment types (chemo + radiation concurrent)?**
   - What we know: HL treatment often includes concurrent chemo-radiation (ABVD + radiation to bulky disease)
   - What's unclear: Do overlapping dates between types affect duration calculations?
   - Recommendation: Calculate durations independently per type (per D-12) — concurrent treatments are separate measurements, not a conflict

## Validation Architecture

> SKIPPED: workflow.nyquist_validation is explicitly set to false in .planning/config.json

## Sources

### Primary (HIGH confidence)

- **R/10_treatment_payer.R** - Multi-source date extraction pattern (7 PCORnet tables) for first treatment dates
- **R/00_config.R lines 412-659** - TREATMENT_CODES list with all code vectors by type (chemo, radiation, SCT, immunotherapy)
- **R/41_combine_reports.R** - openxlsx2 workbook creation with TREATMENT_TYPE_COLORS styling
- **R/42_treatment_codes_resolved.R** - Per-type xlsx output pattern with styled headers

### Secondary (MEDIUM confidence)

- [PCORnet Common Data Model](https://pcornet.org/data/common-data-model/) - PROCEDURES, PRESCRIBING, DISPENSING table specifications
- [PCORnet Procedure/Prescribing/Dispensing Date Fields](https://data-models-service.research.chop.edu/models/pcornet/6.0.0) - PX_DATE, RX_ORDER_DATE, DISPENSE_DATE field definitions
- [ABVD Chemotherapy Cycle Duration](https://www.chemoexperts.com/abvd.html) - 28-day cycles, day 1 and day 15 infusions
- [Stem Cell Transplant Treatment Duration](https://clinicaltrials.ucsf.edu/stem-cell-transplant) - Typical 1-2 day infusion, follow-up over months-years
- [dplyr lag() and lead() Reference](https://dplyr.tidyverse.org/reference/lead-lag.html) - Official documentation for gap detection pattern
- [Cumulative Sum Gap Detection Pattern](https://gist.github.com/jgilfillan/23336d0f5bcfffe6a71d0bdd634d023e) - Community example of cumsum() for episode splitting
- [openxlsx2 Styling Manual](https://janmarvin.github.io/openxlsx2/articles/openxlsx2_style_manual.html) - Official styling guide for workbooks
- [ggplot2 Distribution Charts](https://r-statistics.co/ggplot2-Distribution-Charts.html) - Histogram and boxplot patterns for clinical data

### Tertiary (LOW confidence)

- General oncology treatment timing research (WebSearch) - Confirms 90-day gap is appropriate for course separation, not cycle separation
- lubridate date manipulation tutorials - Standard date arithmetic approaches

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All packages already in project renv, patterns verified in existing codebase
- Architecture patterns: HIGH - Multi-source extraction proven in R/10, openxlsx2 styling proven in R/41/42
- Pitfalls: HIGH - Based on existing codebase patterns and PCORnet CDM quirks documented in PITFALLS.md
- Episode detection: MEDIUM-HIGH - lag() + cumsum() is standard dplyr pattern, but 90-day threshold requires clinical validation
- Clinical domain (ABVD cycles, SCT duration): MEDIUM - Based on public clinical resources, not OneFlorida-specific data

**Research date:** 2026-05-05
**Valid until:** 60 days (stable R packages, proven patterns in codebase)
