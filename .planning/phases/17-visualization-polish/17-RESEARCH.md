# Phase 17: Visualization Polish - Research

**Researched:** 2026-04-03
**Domain:** R data visualization (ggplot2), PPTX generation (officer/flextable), date filtering, encounter data analysis
**Confidence:** HIGH

## Summary

Phase 17 completes the PPTX visualization suite by filtering 1900 sentinel dates from all display content, adding a new post-treatment encounter summary table (unique dates per person by payer after last treatment), and creating stacked encounter histograms showing pre/post-treatment breakdown. The phase also closes two gaps from Phase 12: verifying PPTX2-04 (overflow bin annotation) and PPTX2-07 (label clipping fix).

**Primary recommendation:** Filter 1900 dates at the PPTX display layer in `11_generate_pptx.R` and `16_encounter_analysis.R` using `year() != 1900L` predicates before data reaches `flextable()` or `ggplot()`. For stacked histograms, use `geom_histogram(position = "stack")` with a categorical `fill` aesthetic mapping to pre/post status, leveraging existing faceting and overflow bin patterns from Section 1 of `16_encounter_analysis.R`.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**1900 Sentinel Date Filtering (VIZP-01):**
- **D-01:** Filter 1900 dates at the PPTX display layer only — in `11_generate_pptx.R` and `16_encounter_analysis.R`. Do NOT modify raw cohort data in `04_build_cohort.R` (except the existing `first_hl_dx_date` nullification which stays). This keeps raw data intact for audit purposes.
- **D-02:** Apply 1900 filtering to any date column that appears in PPTX tables or is used to derive values shown in PPTX graphs (treatment dates, enrollment dates, encounter dates).

**Post-Treatment Encounter Summary (VIZP-02):**
- **D-03:** New PPTX slide with summary table: unique encounter dates per person by payer category, counted only after `max(LAST_CHEMO_DATE, LAST_RADIATION_DATE, LAST_SCT_DATE)` — the last treatment date across all treatment types.
- **D-04:** Patients with no treatment (all three LAST_*_DATE are NA) are excluded from this slide — they have no "post-treatment" period.
- **D-05:** This is a distinct metric from the existing `N_UNIQUE_DATES_POST_TX` in Section 6 of `16_encounter_analysis.R`, which uses post-diagnosis as anchor. The new metric uses post-last-treatment as anchor.

**Stacked Encounter Histogram (VIZP-03):**
- **D-06:** Add a NEW stacked histogram — do not replace the existing encounter histogram (Section 1 of `16_encounter_analysis.R`).
- **D-07:** Each bar shows a patient's total encounters split into pre-treatment (top) and post-treatment (bottom, colored distinctly). "Post-treatment" = encounters after `max(LAST_CHEMO_DATE, LAST_RADIATION_DATE, LAST_SCT_DATE)`.
- **D-08:** Faceted by payer category (6 + Missing, matching existing consolidation pattern).
- **D-09:** Use raw encounter counts (N_ENCOUNTERS), not unique dates, to match the existing histogram metric.
- **D-10:** Patients with no treatment are excluded from the stacked histogram (no way to split pre/post).

**Gap Closure (PPTX2-04, PPTX2-07):**
- **D-11:** PPTX2-04 (encounter histogram with 6+Missing payer and >500 overflow bin with per-facet annotation) — code already exists in `16_encounter_analysis.R` lines 39-83. Verify correctness, do not rewrite.
- **D-12:** PPTX2-07 (age group bar chart labels not clipped) — code already exists with `coord_cartesian(clip = "off", ylim = c(0, max_y_p4 * 1.2))` at line 231. Verify correctness, do not rewrite.

### Claude's Discretion

- Exact color palette for pre/post-treatment stacking (should be visually distinct and consistent with existing viridis/manual palettes)
- Binwidth and x-axis cap for the new stacked histogram
- Whether to add a summary statistics companion slide for the stacked histogram (like Slide 18 for the existing histogram)
- Exact wording of footnotes and subtitles for new slides
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| VIZP-01 | Filter 1900 sentinel dates from all PPTX content (tables and graphs) | Date filtering patterns in existing code, lubridate `year()` function for extraction |
| VIZP-02 | New PPTX slide with unique encounter dates per person by payer, counted after `max(LAST_CHEMO_DATE, LAST_RADIATION_DATE, LAST_SCT_DATE)` | Existing `all_last_dates` tibble computes `LAST_ANY_TREATMENT_DATE`; existing table builder helpers (`add_table_slide()`, `rename_payer()`) for PPTX integration |
| VIZP-03 | Stacked encounter histograms by payer with post-treatment on bottom and pre-treatment on top | `geom_histogram(position = "stack")` with categorical `fill` aesthetic; existing faceting and overflow patterns from Section 1 |
| PPTX2-04 | Encounter histogram with 6+Missing payer and >500 overflow bin with per-facet annotation | Already implemented in `16_encounter_analysis.R` lines 39-83; verification only |
| PPTX2-07 | Age group bar chart labels not clipped at plot top | Already implemented with `coord_cartesian(clip = "off")` at line 231; verification only |
</phase_requirements>

## Standard Stack

All required libraries are already present in the project's `renv.lock` and actively used:

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| ggplot2 | 4.0.1+ | Visualization | Core tidyverse plotting; `geom_histogram()` with `position="stack"` for stacked histograms |
| dplyr | 1.2.0+ | Data transformation | Filter, mutate, group_by for date filtering and pre/post categorization |
| lubridate | 1.9.3+ | Date operations | `year()` function for 1900 sentinel detection; date arithmetic for pre/post splits |
| officer | 0.6.9+ | PPTX generation | `read_pptx()`, `add_slide()`, `ph_with()` for PowerPoint output |
| flextable | 0.9.9+ | Table formatting | `flextable()`, `theme_vanilla()` for PPTX table rendering |
| scales | 1.3.0+ | Formatting | `label_number()` for axis labels, HIPAA suppression helpers |

**No new packages needed.** All functionality exists in the current stack.

**Installation:** N/A — all dependencies already installed via `renv::restore()`.

## Architecture Patterns

### Existing Code Structure (Reuse Assets)

```
R/
├── 11_generate_pptx.R     # PPTX generation + helper functions
│   ├── rename_payer()        # Consolidates Other/Unavailable/Unknown → Missing
│   ├── PAYER_ORDER           # 7-level factor ordering (6 + Missing)
│   ├── add_table_slide()     # PPTX slide builder for flextable objects
│   ├── add_image_slide()     # PPTX slide builder for PNG files
│   ├── add_footnote()        # Add italic footnote text to slide bottom
│   ├── compute_last_dates()  # Extract LAST_CHEMO/RADIATION/SCT_DATE
│   └── all_last_dates        # Tibble with LAST_ANY_TREATMENT_DATE per patient
├── 16_encounter_analysis.R # Encounter visualizations + table generation
│   ├── Section 1: Histogram (encounters per person by payor, with overflow)
│   ├── Section 2: Post-treatment encounters by DX year
│   ├── Section 3: Total encounters by DX year
│   ├── Section 4: Summary table with column sums
│   ├── Section 5: Post-treatment by age group
│   └── Section 6: Unique dates histograms and summaries
├── 04_build_cohort.R       # Cohort building (existing 1900 nullification)
│   └── Lines 176-183: first_hl_dx_date 1900 sentinel nullification
└── utils_snapshot.R        # save_output_data() for RDS snapshots
```

### Pattern 1: 1900 Sentinel Date Filtering (VIZP-01)

**What:** Use `year(date_column) != 1900L` predicates immediately before data enters display functions (`flextable()` or `ggplot()`).

**When to use:** Any PPTX table or graph that displays date values or uses dates to compute derived metrics (counts, means, summaries).

**Existing example (04_build_cohort.R lines 179-183):**
```r
# Nullify 1900 sentinel dates (SAS epoch)
n_sentinel_dx <- sum(year(cohort$first_hl_dx_date) == 1900L, na.rm = TRUE)
if (n_sentinel_dx > 0) {
  message(glue("  Nullifying {n_sentinel_dx} sentinel diagnosis dates (year 1900)"))
  cohort <- cohort %>%
    mutate(first_hl_dx_date = if_else(year(first_hl_dx_date) == 1900L, as.Date(NA), first_hl_dx_date))
}
```

**For PPTX display filtering (new pattern for Phase 17):**
```r
# Example: Filter treatment dates before PPTX table display
treatment_summary <- hl_cohort %>%
  filter(
    is.na(FIRST_CHEMO_DATE) | year(FIRST_CHEMO_DATE) != 1900L,
    is.na(LAST_CHEMO_DATE) | year(LAST_CHEMO_DATE) != 1900L
  ) %>%
  # ... continue with table building
```

**Alternative approach for count-based filtering (when dates drive counts but aren't displayed):**
```r
# Example: Exclude patients with 1900 treatment dates from encounter summaries
encounter_summary <- hl_cohort %>%
  filter(
    year(LAST_ANY_TREATMENT_DATE) != 1900L | is.na(LAST_ANY_TREATMENT_DATE)
  ) %>%
  count(PAYER_CATEGORY_PRIMARY, name = "n")
```

**Key principle:** Filter at display layer, not at raw cohort creation (per D-01). The existing `first_hl_dx_date` nullification in `04_build_cohort.R` is grandfathered and remains unchanged.

### Pattern 2: Stacked Histogram with Pre/Post Split (VIZP-03)

**What:** Create a new categorical variable (e.g., `ENCOUNTER_PERIOD` with levels "Pre-treatment", "Post-treatment") and map it to the `fill` aesthetic in `geom_histogram()` with `position = "stack"`.

**When to use:** Visualizing encounter distributions split by a binary or categorical temporal anchor (treatment, diagnosis, enrollment).

**Example (adapted from existing Section 1 pattern):**
```r
# Step 1: Compute per-patient pre/post encounter counts
stacked_data <- encounters %>%
  left_join(all_last_dates, by = "ID") %>%
  filter(!is.na(LAST_ANY_TREATMENT_DATE)) %>%  # Exclude patients with no treatment (D-10)
  mutate(
    ENCOUNTER_PERIOD = if_else(
      ADMIT_DATE <= LAST_ANY_TREATMENT_DATE,
      "Pre-treatment",
      "Post-treatment"
    )
  ) %>%
  count(ID, ENCOUNTER_PERIOD, name = "n_encounters") %>%
  complete(ID, ENCOUNTER_PERIOD, fill = list(n_encounters = 0))  # Ensure all patients have both periods

# Step 2: Join payer category (for faceting) and consolidate
stacked_data <- stacked_data %>%
  left_join(hl_cohort %>% select(ID, PAYER_CATEGORY_PRIMARY), by = "ID") %>%
  mutate(
    PAYER_CATEGORY_PRIMARY = case_when(
      PAYER_CATEGORY_PRIMARY %in% c("Other", "Unavailable", "Unknown") ~ "Missing",
      TRUE ~ PAYER_CATEGORY_PRIMARY
    ),
    PAYER_CATEGORY_PRIMARY = factor(PAYER_CATEGORY_PRIMARY,
      levels = c("Medicare", "Medicaid", "Dual eligible", "Private",
                 "Other government", "No payment / Self-pay", "Missing")),
    ENCOUNTER_PERIOD = factor(ENCOUNTER_PERIOD,
      levels = c("Post-treatment", "Pre-treatment"))  # Post on bottom, Pre on top
  )

# Step 3: Aggregate to total encounters per patient
patient_totals <- stacked_data %>%
  group_by(ID, PAYER_CATEGORY_PRIMARY) %>%
  summarise(N_TOTAL = sum(n_encounters), .groups = "drop")

# Step 4: Create stacked histogram with overflow bin
x_cap <- 500
patient_totals <- patient_totals %>%
  mutate(N_TOTAL_CAPPED = if_else(N_TOTAL > x_cap, as.numeric(x_cap + 1), as.numeric(N_TOTAL)))

overflow_counts <- patient_totals %>%
  filter(N_TOTAL > x_cap) %>%
  count(PAYER_CATEGORY_PRIMARY, name = "n_overflow", .drop = FALSE)

# Step 5: Join back encounter period splits for stacking
plot_data <- stacked_data %>%
  left_join(patient_totals %>% select(ID, N_TOTAL_CAPPED), by = "ID")

p_stacked <- ggplot(plot_data, aes(x = N_TOTAL_CAPPED, fill = ENCOUNTER_PERIOD)) +
  geom_histogram(position = "stack", binwidth = 20, color = "white", linewidth = 0.2) +
  geom_text(data = overflow_counts %>% filter(n_overflow > 0),
            aes(x = x_cap + 10, y = Inf, label = paste0(">", x_cap, ": ", n_overflow)),
            vjust = 1.5, hjust = 0, size = 2.8, inherit.aes = FALSE) +
  facet_wrap(~ PAYER_CATEGORY_PRIMARY, scales = "free_y") +
  coord_cartesian(xlim = c(0, x_cap + 40)) +
  scale_x_continuous(breaks = seq(0, x_cap, by = 100),
                     labels = c(seq(0, x_cap - 100, by = 100), paste0(x_cap, "+"))) +
  scale_fill_manual(values = c("Post-treatment" = "#1f77b4", "Pre-treatment" = "#ff7f0e")) +
  labs(
    title = "Encounters per Person by Payor (Pre/Post-Treatment)",
    x = "Number of Encounters",
    y = "Number of Patients",
    fill = "Period"
  ) +
  theme_minimal(base_size = 11) +
  theme(strip.text = element_text(face = "bold"))

ggsave("output/figures/encounters_stacked_pre_post_by_payor.png", p_stacked,
       width = 12, height = 8, dpi = 300)
```

**Key insight:** The `position = "stack"` argument to `geom_histogram()` is the default and handles stacking automatically. The `fill` aesthetic controls which category drives the stacking. Factor level ordering controls stacking order (first level = bottom, last level = top).

### Pattern 3: Post-Treatment Unique Encounter Dates Summary (VIZP-02)

**What:** Count unique `ADMIT_DATE` values per patient where `ADMIT_DATE > LAST_ANY_TREATMENT_DATE`, then summarize by payer category.

**When to use:** Measuring post-treatment engagement using distinct care dates (collapses multi-encounter same-day visits to single date).

**Example:**
```r
# Step 1: Compute per-patient unique post-treatment encounter dates
post_tx_unique_dates <- encounters %>%
  left_join(all_last_dates, by = "ID") %>%
  filter(
    !is.na(LAST_ANY_TREATMENT_DATE),              # Only patients with treatment (D-04)
    !is.na(ADMIT_DATE),
    ADMIT_DATE > LAST_ANY_TREATMENT_DATE,         # Post-treatment encounters only
    year(ADMIT_DATE) != 1900L                     # Filter 1900 sentinels (VIZP-01)
  ) %>%
  group_by(ID) %>%
  summarise(N_UNIQUE_DATES_POST_LAST_TX = n_distinct(ADMIT_DATE), .groups = "drop")

# Step 2: Join payer category and consolidate
post_tx_summary <- hl_cohort %>%
  select(ID, PAYER_CATEGORY_PRIMARY) %>%
  left_join(post_tx_unique_dates, by = "ID") %>%
  replace_na(list(N_UNIQUE_DATES_POST_LAST_TX = 0)) %>%
  mutate(
    PAYER_CATEGORY_PRIMARY = rename_payer(PAYER_CATEGORY_PRIMARY),
    PAYER_CATEGORY_PRIMARY = factor(PAYER_CATEGORY_PRIMARY, levels = PAYER_ORDER)
  ) %>%
  group_by(PAYER_CATEGORY_PRIMARY) %>%
  summarise(
    N = n(),
    Mean = mean(N_UNIQUE_DATES_POST_LAST_TX, na.rm = TRUE),
    Median = median(N_UNIQUE_DATES_POST_LAST_TX, na.rm = TRUE),
    Min = min(N_UNIQUE_DATES_POST_LAST_TX, na.rm = TRUE),
    Max = max(N_UNIQUE_DATES_POST_LAST_TX, na.rm = TRUE),
    .groups = "drop"
  )

# Step 3: Create PPTX table slide
ft <- flextable(post_tx_summary) %>%
  theme_vanilla() %>%
  align(align = "center", part = "all") %>%
  autofit()

pres <- pres %>%
  add_slide(layout = "Title and Content", master = "Office Theme") %>%
  ph_with(value = "Unique Encounter Dates per Person (Post-Last Treatment)",
          location = ph_location_type(type = "title")) %>%
  ph_with(value = ft, location = ph_location_type(type = "body"))

pres <- add_footnote(pres,
  "Post-Last Treatment: Encounters after max(LAST_CHEMO_DATE, LAST_RADIATION_DATE, LAST_SCT_DATE). Patients with no treatment excluded.")
```

**Key principle:** This is distinct from the existing `N_UNIQUE_DATES_POST_TX` in Section 6, which anchors on `first_hl_dx_date` (post-diagnosis). The new metric anchors on `LAST_ANY_TREATMENT_DATE` (post-treatment).

### Anti-Patterns to Avoid

- **Modifying raw cohort data:** Do NOT add 1900 filtering to `04_build_cohort.R` (except existing `first_hl_dx_date` nullification). Filter at display layer only (D-01).
- **Using `geom_bar()` instead of `geom_histogram()`:** For continuous encounter counts, use `geom_histogram()`. `geom_bar()` is for discrete categories or pre-aggregated data.
- **Wrong stacking order:** To put post-treatment on bottom (visually dominant), make it the **first** factor level. ggplot2 stacks from bottom to top in factor level order.
- **Forgetting overflow bins:** Stacked histograms inherit the same x-axis capping and overflow annotation pattern as the existing histogram (Section 1). Without this, high-encounter outliers distort the x-axis.
- **Mixing anchor dates:** Post-diagnosis (`first_hl_dx_date`) vs. post-treatment (`LAST_ANY_TREATMENT_DATE`) are different clinical windows. Document which anchor is used in every metric and slide title.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Stacked histogram layout | Manual `geom_rect()` or `geom_polygon()` to draw stacked bars | `geom_histogram(position = "stack", fill = category)` | ggplot2's position system handles binning, stacking, and scaling automatically; manual approaches break with faceting |
| Date filtering for display | Custom filter functions or complex `case_when()` chains | `year(date_col) != 1900L` inline in `filter()` | lubridate's `year()` is vectorized, readable, and fast; custom functions add unnecessary abstraction |
| PPTX table rendering | Manually constructing XML via `ph_with(value = block_list(...))` | `flextable()` + `ph_with(value = ft)` | flextable handles table styling, alignment, formatting, and officer integration; manual XML is brittle and verbose |
| Overflow bin annotation | Custom `geom_text()` with hardcoded positions per facet | `geom_text(data = overflow_counts, aes(...), inherit.aes = FALSE)` | Existing pattern in Section 1 dynamically computes per-facet counts; hardcoding breaks with payer category changes |

**Key insight:** The codebase already contains reference implementations for all patterns needed in Phase 17. Reuse, don't rewrite.

## Common Pitfalls

### Pitfall 1: Forgetting to Filter 1900 Dates in Derived Metrics

**What goes wrong:** PPTX slides show "N = 842 patients with mean 23.4 encounters" but that includes patients with `LAST_CHEMO_DATE = '1900-01-01'` (sentinel value), inflating the denominator.

**Why it happens:** 1900 filtering is applied to direct date displays (`first_hl_dx_date` → `DX_YEAR` in bar charts) but forgotten in computed metrics (counts, means, summaries) that use dates as filters.

**How to avoid:** Audit **every** dplyr chain in `11_generate_pptx.R` and `16_encounter_analysis.R` that uses a date column. Add `year(date_col) != 1900L` to the `filter()` step before aggregation.

**Warning signs:**
- Footnote says "X patients excluded for 1900 dates" but table total still includes them
- Mean/median values are unexpectedly high (1900 dates create long pre-treatment windows)

### Pitfall 2: Wrong Factor Level Ordering in Stacked Histograms

**What goes wrong:** Stacked histogram shows pre-treatment (orange) on bottom and post-treatment (blue) on top, opposite of the requirement (D-07: post on bottom).

**Why it happens:** ggplot2 stacks `fill` categories in factor level order: first level = bottom, last level = top. Default alphabetical ordering puts "Post" after "Pre".

**How to avoid:** Explicitly set factor levels with **desired bottom-to-top order**:
```r
mutate(
  ENCOUNTER_PERIOD = factor(ENCOUNTER_PERIOD,
    levels = c("Post-treatment", "Pre-treatment"))  # Post on bottom
)
```

**Warning signs:** Visual inspection of PNG output shows reversed stacking order.

### Pitfall 3: Excluding Patients with Zero Pre-Treatment or Post-Treatment Encounters

**What goes wrong:** Stacked histogram only shows patients who have BOTH pre-treatment AND post-treatment encounters. Patients with only pre-treatment or only post-treatment are silently dropped.

**Why it happens:** After splitting encounters into `ENCOUNTER_PERIOD` categories and counting, patients with zero encounters in one period are missing rows. Joining or summarizing by `ID` drops these patients.

**How to avoid:** Use `tidyr::complete()` to fill in missing combinations:
```r
stacked_data <- encounters %>%
  # ... split into periods and count ...
  complete(ID, ENCOUNTER_PERIOD, fill = list(n_encounters = 0))
```

**Warning signs:** Total patient count in stacked histogram is much lower than in the original (non-stacked) histogram from Section 1.

### Pitfall 4: Reusing Existing `N_UNIQUE_DATES_POST_TX` for VIZP-02

**What goes wrong:** New PPTX slide uses the existing `N_UNIQUE_DATES_POST_TX` column from `16_encounter_analysis.R` Section 6, but this uses `first_hl_dx_date` as anchor (post-diagnosis), not `LAST_ANY_TREATMENT_DATE` (post-last-treatment).

**Why it happens:** Similar-sounding metric names and the desire to reuse existing code.

**How to avoid:** Create a **new** variable with a distinct name (e.g., `N_UNIQUE_DATES_POST_LAST_TX`) and document the anchor date difference in slide footnotes (per D-05).

**Warning signs:** Footnote says "post-treatment" but values don't match expectations for patients with treatment dates far from diagnosis dates.

### Pitfall 5: Missing save_output_data() Snapshot Calls

**What goes wrong:** New stacked histogram PNG and new post-treatment summary table are added to PPTX, but their backing data is not saved as `.rds` snapshots (violates SNAP-03 and SNAP-04 from Phase 16).

**Why it happens:** Forgetting Phase 16's snapshot requirement when adding new outputs.

**How to avoid:** After every `write_csv()`, `ggsave()`, or flextable creation, call:
```r
save_output_data(plot_data, "encounters_stacked_pre_post_data")  # For figures
save_output_data(summary_table, "post_tx_unique_dates_summary_data")  # For tables
```

**Warning signs:** `.planning/phases/16-dataset-snapshots/16-PLAN-*.md` lists expected snapshots, but `outputs/` directory is missing new `.rds` files.

## Code Examples

Verified patterns from existing codebase:

### Example 1: Date Filtering for 1900 Sentinels (Existing Pattern)

```r
# Source: R/04_build_cohort.R lines 179-183
# Context: Nullify first_hl_dx_date when year is 1900

n_sentinel_dx <- sum(year(cohort$first_hl_dx_date) == 1900L, na.rm = TRUE)
if (n_sentinel_dx > 0) {
  message(glue("  Nullifying {n_sentinel_dx} sentinel diagnosis dates (year 1900)"))
  cohort <- cohort %>%
    mutate(first_hl_dx_date = if_else(year(first_hl_dx_date) == 1900L, as.Date(NA), first_hl_dx_date))
}
```

**For Phase 17:** Apply same pattern in display layer (filter, not mutate to NA):
```r
# New pattern for PPTX display filtering
treatment_table_data <- hl_cohort %>%
  filter(
    year(LAST_CHEMO_DATE) != 1900L | is.na(LAST_CHEMO_DATE)
  ) %>%
  # ... continue with table aggregation
```

### Example 2: Histogram with Overflow Bin (Existing Pattern)

```r
# Source: R/16_encounter_analysis.R lines 48-83
# Context: Encounters per person histogram with >500 overflow bin

x_cap <- 500

# Compute per-facet overflow counts
overflow_counts <- hist_data %>%
  filter(N_ENCOUNTERS > x_cap) %>%
  count(PAYER_CATEGORY_PRIMARY, name = "n_overflow", .drop = FALSE)

# Cap encounter values for binning
hist_data <- hist_data %>%
  mutate(N_ENC_CAPPED = if_else(N_ENCOUNTERS > x_cap, as.numeric(x_cap + 1), as.numeric(N_ENCOUNTERS)))

p1 <- ggplot(hist_data, aes(x = N_ENC_CAPPED, fill = PAYER_CATEGORY_PRIMARY)) +
  geom_histogram(binwidth = 20, color = "white", linewidth = 0.2) +
  geom_text(data = overflow_counts %>% filter(n_overflow > 0),
            aes(x = x_cap + 10, y = Inf, label = paste0(">", x_cap, ": ", n_overflow)),
            vjust = 1.5, hjust = 0, size = 2.8, inherit.aes = FALSE) +
  facet_wrap(~ PAYER_CATEGORY_PRIMARY, scales = "free_y") +
  coord_cartesian(xlim = c(0, x_cap + 40)) +
  scale_x_continuous(breaks = seq(0, x_cap, by = 100),
                     labels = c(seq(0, x_cap - 100, by = 100), paste0(x_cap, "+")))
```

**For Phase 17:** Reuse this entire pattern in stacked histogram, replacing `fill = PAYER_CATEGORY_PRIMARY` with `fill = ENCOUNTER_PERIOD` and adding `facet_wrap(~ PAYER_CATEGORY_PRIMARY)`.

### Example 3: Payer Consolidation and Factor Ordering (Existing Pattern)

```r
# Source: R/11_generate_pptx.R lines 73-78
# Context: Consolidate payer categories to 6 + Missing

rename_payer <- function(x) {
  case_when(
    x %in% c("Other", "Unavailable", "Unknown") ~ "Missing",
    is.na(x)                                      ~ "Missing",
    TRUE ~ x
  )
}

# Source: R/11_generate_pptx.R lines 66-69
PAYER_ORDER <- c(
  "Medicare", "Medicaid", "Dual eligible", "Private",
  "Other government", "No payment / Self-pay", "Missing"
)
```

**For Phase 17:** Apply to all new PPTX slides and stacked histogram data prep:
```r
post_tx_data <- post_tx_data %>%
  mutate(
    PAYER_CATEGORY_PRIMARY = rename_payer(PAYER_CATEGORY_PRIMARY),
    PAYER_CATEGORY_PRIMARY = factor(PAYER_CATEGORY_PRIMARY, levels = PAYER_ORDER)
  )
```

### Example 4: LAST_ANY_TREATMENT_DATE Computation (Existing Pattern)

```r
# Source: R/11_generate_pptx.R lines 271-285
# Context: Compute the latest treatment date across all types

all_last_dates <- hl_cohort %>%
  select(ID) %>%
  left_join(last_chemo_dates, by = "ID") %>%
  left_join(last_rad_dates, by = "ID") %>%
  left_join(last_sct_dates, by = "ID") %>%
  rowwise() %>%
  mutate(
    LAST_ANY_TREATMENT_DATE = {
      dates <- c(LAST_CHEMO_DATE, LAST_RADIATION_DATE, LAST_SCT_DATE)
      dates <- dates[!is.na(dates)]
      if (length(dates) == 0) NA_Date_ else max(dates)
    }
  ) %>%
  ungroup() %>%
  select(ID, LAST_ANY_TREATMENT_DATE)
```

**For Phase 17:** Reuse this tibble directly for VIZP-02 and VIZP-03. It's already computed in `11_generate_pptx.R` Section 2.

### Example 5: Label Clipping Fix (Existing Pattern — PPTX2-07)

```r
# Source: R/16_encounter_analysis.R lines 227-231
# Context: Age group bar chart with labels not clipped at top

max_y_p4 <- max(age_post_tx$n, na.rm = TRUE)

p4 <- ggplot(age_post_tx, aes(x = AGE_GROUP, y = n, fill = HAS_POST_TX_ENCOUNTERS)) +
  geom_col(position = "dodge") +
  geom_text(aes(label = paste0(n, "\n(", pct, "%)")),
            position = position_dodge(width = 0.9), vjust = -0.3, size = 3) +
  coord_cartesian(clip = "off", ylim = c(0, max_y_p4 * 1.2)) +  # Key line: clip="off" + expanded y-axis
  # ... rest of plot code
```

**For Phase 17:** Verify this code in `16_encounter_analysis.R` line 231. It already implements PPTX2-07. No changes needed (per D-12).

### Example 6: Snapshot Helper (Existing Pattern — Phase 16)

```r
# Source: R/utils_snapshot.R lines 24-55
# Context: Save output data snapshot for reproducibility

save_output_data(hist_data, "encounters_per_person_by_payor_data")
save_output_data(summary_with_sums, "encounter_summary_by_payor_age_data")
```

**For Phase 17:** Call after creating plot data or table data:
```r
# After creating stacked histogram data
save_output_data(stacked_plot_data, "encounters_stacked_pre_post_data")

# After creating post-treatment unique dates summary
save_output_data(post_tx_summary, "post_tx_unique_dates_summary_data")
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual XML construction for PPTX tables | `flextable()` + `officer::ph_with()` | Phase 11 (2026-03-31) | Declarative table styling; automatic officer integration |
| Hardcoded payer categories (9 levels) | Consolidated to 6 + Missing via `rename_payer()` | Phase 11 (2026-03-31) | Unambiguous "Missing" label; consistent across all slides |
| No overflow bin annotation | Per-facet `geom_text()` with dynamic counts | Phase 12 (2026-04-01) | High-encounter outliers visible and counted per payer |
| DX_YEAR=1900 included in bar charts | Filtered with `filter(DX_YEAR != 1900)` | Phase 12 (2026-04-01) | Sentinel dates excluded from visualizations |
| No backing data snapshots | `save_output_data()` for all figures/tables | Phase 16 (2026-04-02) | Reproducibility and post-hoc analysis |

**Deprecated/outdated:**
- **9-category payer system:** Replaced by 7-category (6 + Missing) in Phase 11. Do not use `Other`, `Unavailable`, `Unknown` as separate categories in new PPTX slides.
- **Manual attrition logging:** Replaced by `tidylog` in Phase 3. Do not write custom `message()` calls for dplyr operation logging.

## Open Questions

1. **Color palette for stacked histogram pre/post categories**
   - What we know: Existing code uses `scale_fill_viridis_d()` for categorical fills and `scale_fill_manual(values = c("Yes" = "#2c7fb8", "No" = "#d95f02"))` for binary comparisons.
   - What's unclear: User preference for pre/post-treatment colors — should they match viridis palette, use UF brand colors (blue/orange), or use distinct clinical palette?
   - Recommendation: Use `scale_fill_manual(values = c("Post-treatment" = "#2c7fb8", "Pre-treatment" = "#ff7f0e"))` — matches existing age group pattern (blue/orange) and provides high visual contrast. Document in commit message.

2. **Binwidth and x-axis cap for stacked histogram**
   - What we know: Existing histogram uses `binwidth = 20` and `x_cap = 500` (Section 1, line 66 and 49).
   - What's unclear: Whether stacked histogram should use same parameters (encounter distributions may differ for treated-only subset).
   - Recommendation: Start with same parameters (`binwidth = 20`, `x_cap = 500`) for consistency. Adjust if median/Q3 values for treated subset differ significantly from full cohort. Document in footnote if changed.

3. **Summary statistics companion slide for stacked histogram**
   - What we know: Existing histogram (Slide 17) has a companion summary statistics table (Slide 18) showing N, Mean, Median, Min, Q1, Q3, Max, N>500 per payer.
   - What's unclear: Whether stacked histogram should also have a summary slide, and if so, how to summarize pre/post splits (separate rows per period? combined stats?).
   - Recommendation: Add summary slide with **separate rows** for Pre-treatment and Post-treatment per payer (14 rows total for 7 payer categories × 2 periods). This parallels existing pattern and provides comparable statistics. Document in PPTX slide subtitle.

## Validation Architecture

> Validation skipped: `workflow.nyquist_validation` is explicitly set to `false` in `.planning/config.json`.

## Sources

### Primary (HIGH confidence)

- **Existing codebase (R/):** `04_build_cohort.R`, `11_generate_pptx.R`, `16_encounter_analysis.R`, `utils_snapshot.R` — all patterns verified by reading actual implementation
- **ggplot2 official documentation:** [Histograms and frequency polygons — geom_freqpoly](https://ggplot2.tidyverse.org/reference/geom_histogram.html) — confirms `position = "stack"` as default for `geom_histogram()`
- **ggplot2 position_stack documentation:** [Stack overlapping objects on top of each another — position_stack](https://ggplot2.tidyverse.org/reference/position_stack.html) — describes stacking order (first level = bottom)
- **lubridate/dplyr filtering:** [How to Filter by Date Using dplyr](https://www.statology.org/dplyr-filter-date/) — confirms `year()` function for date component extraction
- **officer and flextable integration:** [ph_with.flextable: Add a flextable into a PowerPoint slide](https://rdrr.io/cran/flextable/man/ph_with.flextable.html) — confirms `ph_with(value = ft)` pattern

### Secondary (MEDIUM confidence)

- **Stacked histogram examples:** [Histogram by group in ggplot2 | R CHARTS](https://r-charts.com/distribution/histogram-group-ggplot2/) — shows `fill` aesthetic mapping for categorical stacking
- **ggplot2 color scales:** [Viridis Color Scales for ggplot2](https://sjmgarnier.github.io/viridis/reference/scale_viridis.html) and [11 Colour scales and legends – ggplot2](https://ggplot2-book.org/scales-colour.html) — documents viridis and manual color palette usage
- **officer for PowerPoint:** [Chapter 6 officer for PowerPoint | officeverse](https://ardata-fr.github.io/officeverse/officer-for-powerpoint.html) — general PowerPoint generation workflow

### Tertiary (LOW confidence)

- None — all findings verified with existing code or official documentation.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all libraries already present in `renv.lock`, no new dependencies
- Architecture: HIGH — all patterns exist in current codebase (`04_build_cohort.R`, `11_generate_pptx.R`, `16_encounter_analysis.R`)
- Pitfalls: HIGH — derived from common R/ggplot2 gotchas and project-specific context (1900 sentinel dates, payer consolidation)
- Stacked histogram implementation: HIGH — `geom_histogram(position = "stack")` is well-documented and existing code provides reference patterns
- Date filtering: HIGH — existing 1900 nullification in `04_build_cohort.R` lines 179-183 demonstrates pattern; lubridate `year()` is standard
- PPTX integration: HIGH — existing `add_table_slide()`, `add_image_slide()`, `rename_payer()`, `PAYER_ORDER` helpers cover all needs

**Research date:** 2026-04-03
**Valid until:** 2026-05-03 (30 days for stable R ecosystem)

---

**Ready for Planning:** Research complete. Planner can create PLAN.md files for:
1. VIZP-01 implementation (1900 date filtering in PPTX layer)
2. VIZP-02 implementation (post-treatment unique encounter dates summary table)
3. VIZP-03 implementation (stacked histogram with pre/post split)
4. PPTX2-04 and PPTX2-07 verification (confirm existing code correctness)
