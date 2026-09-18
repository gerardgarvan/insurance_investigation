# Phase 154: Distribution and Histogram Deliverable — Plan

## Overview

Phase 154 adds histogram and distribution-summary infrastructure to `R/122_encounter_distance.R`. A new utility file `R/utils/utils_distance_hist.R` provides four functions (three from Appendix B verbatim, one new). The script's SECTION 3 and SECTION 7 gain an `ENC_TYPE` column, and SECTION 12 is fully replaced: the existing 7-sheet xlsx becomes a 6-sheet spec, four histogram PNGs are written to `output/figures/`, a per-patient summary rds is written, and a row-count reconciliation stopifnot guards the final outputs.

## Prerequisites

- Phase 152/153 is complete: `R/122_encounter_distance.R` exists and builds `enc_distance` with columns `ID`, `ENCOUNTERID`, `ADMIT_DATE`, `zip5_facility`, `zip5_patient_source`, `days_offset`, `distance_mi`, `distance_status`.
- `R/utils/utils_zip_calendar.R` is already sourced in SECTION 1 of R/122 (line 60).
- `openxlsx2` and `zipcodeR` are installed in the project renv.
- `ggplot2` is available (part of tidyverse in renv).
- The `add_styled_sheet()` helper at R/122 lines 931–980 is kept intact; tasks below reuse it.

---

## Tasks

### Task 154-01: Replace SECTION 12 with the 6-sheet xlsx writer

**Goal:** Swap out the existing 7-sheet xlsx builder (lines 916–1113 of `R/122_encounter_distance.R`) for the new 6-sheet spec. Also build the `A_distribution_summary` and `D_fill_offsets` tables inline in SECTION 12 (before the workbook assembly), add the facility-state join, call `make_distance_histograms()` and `summarise_distance()`, write the histogram PNGs, and add a row-count reconciliation stopifnot.

**Files:**
- `R/122_encounter_distance.R` — SECTION 12 block only (lines 916–1113)

**Steps:**

1. Delete lines 916–1113 of `R/122_encounter_distance.R` (the `# SECTION 12: XLSX ASSEMBLY AND WRITE` block and the `# SECTION 12A: RDS WRITE` block above it at lines 910–913). Replace them entirely with the code block below.

2. Paste the following as the new SECTION 12 block starting at line 910 (immediately after the `section_done("SECTIONS 8-11 summaries + QC")` call at line 907):

```r
# ==============================================================================
# SECTION 12: HISTOGRAMS, PATIENT RDS, AND 6-SHEET XLSX (Phase 154) ----
# ==============================================================================

message("--- Phase 154: histogram PNGs, patient rds, 6-sheet xlsx ---")

# ---- 12.0 Facility-state join (for A_distribution_summary by_facility_state breakout) ----
# zipcodeR::zip_code_db is a data frame bundled with the package.
# Join on zip5_facility (character, 5-digit) to state.
zip_state_lkp <- zipcodeR::zip_code_db[, c("zipcode", "state")]

enc_distance <- enc_distance %>%
  dplyr::left_join(zip_state_lkp, by = c("zip5_facility" = "zipcode")) %>%
  dplyr::rename(facility_state = state)

message(glue(
  "  facility_state join: {sum(!is.na(enc_distance$facility_state))} of ",
  "{nrow(enc_distance)} rows matched a state ({sum(is.na(enc_distance$facility_state))} unmatched)"
))

# ---- 12.1 Histogram PNGs via make_distance_histograms() ----
# Returns list(bins = <tibble>, stats = <tibble>) where bins is B_histogram_bins content.
hist_result <- make_distance_histograms(
  dist    = enc_distance,
  out_dir = CONFIG$output_dir,
  run_date = RUN_DATE,
  cutoffs  = CONFIG$distance_candidate_cutoffs_mi  # NULL is fine if not set
)

message(glue(
  "  make_distance_histograms(): {nrow(hist_result$bins)} bin rows; ",
  "4 PNGs written to {file.path(CONFIG$output_dir, 'figures')}"
))

# ---- 12.2 A_distribution_summary via summarise_distance() ----
# breakout column identifies which slice: "overall", "year_<YYYY>", "enc_type_<X>", "state_<XX>"
A_distribution_summary <- dplyr::bind_rows(
  summarise_distance(enc_distance, by = "overall"),
  summarise_distance(enc_distance, by = "year"),
  summarise_distance(enc_distance, by = "ENC_TYPE"),
  summarise_distance(enc_distance, by = "facility_state")
)

message(glue("  A_distribution_summary: {nrow(A_distribution_summary)} rows"))

# ---- 12.3 D_fill_offsets ----
# Signed-integer bin distribution of days_offset for nearest-* fill rows.
# No [0] bin — nearest-fill rows are always nonzero by construction.
nearest_rows <- enc_distance %>%
  dplyr::filter(zip5_patient_source %in% c("nearest_zip9", "nearest_zip5"),
                !is.na(days_offset))

fill_breaks <- c(-Inf, -365, -180, -90, -30, -7, -1, 1, 7, 30, 90, 180, 365, Inf)
fill_labels <- c(
  "[-Inf,-365)", "[-365,-180)", "[-180,-90)", "[-90,-30)",
  "[-30,-7)", "[-7,-1)", "[1,7)", "[7,30)",
  "[30,90)", "[90,180)", "[180,365)", "[365,+Inf)"
)

D_fill_offsets_bins <- tibble::tibble(
  bin = fill_labels,
  n   = as.integer(table(cut(nearest_rows$days_offset,
                              breaks = fill_breaks,
                              labels = fill_labels,
                              right = FALSE,
                              include.lowest = FALSE)))
) %>%
  dplyr::mutate(pct = 100 * n / sum(n))

# Summary rows appended below the bin table.
D_fill_offsets_summary <- if (nrow(nearest_rows) > 0) {
  tibble::tibble(
    bin = c(
      "SUMMARY: median_signed_offset",
      "SUMMARY: median_abs_offset",
      "SUMMARY: p90_abs_offset",
      "SUMMARY: share_past (days_offset > 0)",
      "SUMMARY: share_future (days_offset < 0)"
    ),
    n   = NA_integer_,
    pct = c(
      median(nearest_rows$days_offset,       na.rm = TRUE),
      median(abs(nearest_rows$days_offset),  na.rm = TRUE),
      quantile(abs(nearest_rows$days_offset), 0.90, na.rm = TRUE),
      mean(nearest_rows$days_offset > 0, na.rm = TRUE) * 100,
      mean(nearest_rows$days_offset < 0, na.rm = TRUE) * 100
    )
  )
} else {
  tibble::tibble(bin = character(0), n = integer(0), pct = numeric(0))
}

D_fill_offsets <- dplyr::bind_rows(D_fill_offsets_bins, D_fill_offsets_summary)

message(glue(
  "  D_fill_offsets: {nrow(nearest_rows)} nearest-fill rows; ",
  "{nrow(D_fill_offsets_bins)} bins"
))

# ---- 12.4 Per-patient summary rds ----
# One row per patient with any computed encounter.
# share_ge_<c> columns for each cutoff in CONFIG$distance_candidate_cutoffs_mi (default c(30, 50)).
cutoffs_mi <- if (!is.null(CONFIG$distance_candidate_cutoffs_mi)) {
  CONFIG$distance_candidate_cutoffs_mi
} else {
  c(30, 50)
}

computed_rows <- enc_distance %>% dplyr::filter(distance_status == "computed")

distance_patient <- computed_rows %>%
  dplyr::group_by(ID) %>%
  dplyr::summarise(
    n_enc_computed = dplyr::n(),
    median_mi      = median(distance_mi, na.rm = TRUE),
    min_mi         = min(distance_mi,    na.rm = TRUE),
    max_mi         = max(distance_mi,    na.rm = TRUE),
    .groups = "drop"
  )

for (cut_mi in cutoffs_mi) {
  col_name <- paste0("share_ge_", cut_mi)
  distance_patient <- distance_patient %>%
    dplyr::left_join(
      computed_rows %>%
        dplyr::group_by(ID) %>%
        dplyr::summarise(!!col_name := mean(distance_mi >= cut_mi, na.rm = TRUE),
                         .groups = "drop"),
      by = "ID"
    )
}

OUTPUT_PATIENT_RDS <- file.path(CONFIG$output_dir,
                                 glue("distance_patient_{RUN_DATE}.rds"))
saveRDS(distance_patient, OUTPUT_PATIENT_RDS)
message(glue(
  "  distance_patient rds written: {OUTPUT_PATIENT_RDS} ({nrow(distance_patient)} patients)"
))

# ---- 12.5 Row-count reconciliation stopifnot ----
n_A_overall <- A_distribution_summary %>%
  dplyr::filter(breakout == "overall") %>%
  dplyr::pull(n)

n_hist_enc_stats <- hist_result$stats %>%
  dplyr::filter(level == "encounter") %>%
  dplyr::pull(n)

stopifnot(
  "A_distribution_summary overall n != nrow(filter(enc_distance, distance_status == 'computed'))" =
    n_A_overall == nrow(computed_rows),
  "make_distance_histograms() encounter stats$n != nrow(computed rows)" =
    n_hist_enc_stats == nrow(computed_rows),
  "distance_patient nrow != n_distinct(ID) among computed rows" =
    nrow(distance_patient) == dplyr::n_distinct(computed_rows$ID)
)
message("  Row-count reconciliation stopifnot PASSED")

# ---- 12.6 encounter_distance rds (full table, before xlsx) ----
OUTPUT_RDS <- file.path(CONFIG$output_dir, glue("encounter_distance_{RUN_DATE}.rds"))
saveRDS(enc_distance, OUTPUT_RDS)
message(glue("  rds written: {OUTPUT_RDS} ({nrow(enc_distance)} rows, full encounter-level table)"))

# ---- 12.7 Updated KEY sheet data (6-sheet spec) ----
key_tbl <- tibble::tibble(
  Field = c(
    "Script",
    "Phase",
    "Run date",
    "Cohort",
    "Encounter ZIP source",
    "Residence ZIP source",
    "Distance method",
    "Histogram PNGs",
    "Patient rds",
    "A_distribution_summary breakouts",
    "A_distribution_summary statistics",
    "B_histogram_bins columns",
    "C_completeness waterfall",
    "D_fill_offsets scope",
    "QC sheet contents"
  ),
  Description = c(
    "R/122_encounter_distance.R",
    "Phase 154 — distribution and histogram deliverable",
    RUN_DATE,
    glue("HL cohort (N = {length(COHORT_IDS)}), IDs from DuckDB via CONFIG"),
    "FACILITY_LOCATION column in PCORnet CDM ENCOUNTER table",
    "LDS_ADDRESS_HISTORY via build_patient_zip_calendar() + compute_encounter_distance() (Phase 153 bidirectional nearest-in-time ZIP5)",
    "zipcodeR::zip_distance() (miles); canonical per D-01 from Phase 152 milestone. No km in this deliverable (154-D3).",
    glue("4 PNGs in {file.path(CONFIG$output_dir, 'figures')}: encounter_distance_hist_{{level}}_{{scale}}_{RUN_DATE}.png for level in (encounter, patient), scale in (linear, log)"),
    glue("distance_patient_{RUN_DATE}.rds: one row per patient with any computed encounter; columns: ID, n_enc_computed, median_mi, min_mi, max_mi, share_ge_<c> for c in ({paste(cutoffs_mi, collapse=', ')})"),
    "overall | year_<YYYY> (by ADMIT_DATE year) | enc_type_<X> (by ENC_TYPE) | state_<XX> (by facility_state from zipcodeR::zip_code_db)",
    "n, median_mi, IQR_mi, p90_mi, p95_mi, p99_mi, max_mi — all in miles (154-D3); no mean/SD",
    "level, scale, bin, lower, upper, lower_mi, upper_mi, n, pct — from make_distance_histograms() bind_rows(bins_out)",
    "Five-step waterfall keyed on distance_status (encounters → facility ZIP → in-range patient ZIP → nearest patient ZIP → distance computed)",
    "Nearest-* fill rows (zip5_patient_source in nearest_zip9, nearest_zip5) only; signed-integer bins; no [0] bin; summary rows for median/p90 abs offset and past/future share",
    "Coverage waterfall; completeness waterfall; n_candidates_in_range>1; nearest-fill offset distribution; unmatched ZIP9 by state; zip9_crosswalk_present flag"
  )
)

# ---- 12.8 Build 6-sheet workbook ----
message("--- Writing 6-sheet xlsx (Phase 154 spec) ---")

wb <- wb_workbook()

add_styled_sheet(
  wb, "KEY",
  "Phase 154: Encounter Distance — Workbook KEY",
  glue("Run date: {RUN_DATE} | Cohort: HL (N={length(COHORT_IDS)}) | Script: R/122_encounter_distance.R"),
  key_tbl
)

add_styled_sheet(
  wb, "A_distribution_summary",
  "A: Distance Distribution Summary",
  "Rows stacked by breakout: overall, by year (ADMIT_DATE), by ENC_TYPE, by facility state. Miles only (154-D3).",
  A_distribution_summary
)

add_styled_sheet(
  wb, "B_histogram_bins",
  "B: Histogram Bin Counts",
  "Output of make_distance_histograms(): level (encounter/patient), scale (linear/log), bin edges in raw and mile units, n, pct.",
  hist_result$bins
)

add_styled_sheet(
  wb, "C_completeness",
  "C: Completeness Waterfall",
  "Five-step waterfall keyed on distance_status from compute_encounter_distance() (Phase 153).",
  completeness_tbl,
  extra_tbl   = status_breakdown_tbl,
  extra_label = "distance_status breakdown (row-for-row reconciles to nrow(enc_distance))"
)

add_styled_sheet(
  wb, "D_fill_offsets",
  "D: Nearest-Fill Days-Offset Distribution",
  "Signed-integer bins of days_offset for zip5_patient_source in {nearest_zip9, nearest_zip5}. No [0] bin (nearest fills are always nonzero).",
  D_fill_offsets
)

add_styled_sheet(
  wb, "QC",
  "QC: Coverage Waterfall and Quality Checks",
  "Waterfall from raw cohort ENCOUNTER count to distance computed; nearest-fill days_offset distribution; n_candidates_in_range>1; WV gap noted.",
  qc_tbl,
  extra_tbl   = unmatched_zip9_by_state,
  extra_label = "Unmatched ZIP9 encounters by state (centroid_source == zip5_fallback)"
)

OUTPUT_XLSX <- file.path(CONFIG$output_dir, glue("encounter_distance_{RUN_DATE}.xlsx"))
wb_save(wb, OUTPUT_XLSX)
message(glue("  xlsx written: {OUTPUT_XLSX} (6 sheets: KEY, A_distribution_summary, B_histogram_bins, C_completeness, D_fill_offsets, QC)"))
section_done("SECTION 12 Phase 154 outputs")

message("=== R/122_encounter_distance.R complete ===")
```

3. Remove the old `OUTPUT_RDS` and `OUTPUT_XLSX` constant assignments at lines 103–104 of the original (those two lines define `OUTPUT_RDS` and `OUTPUT_XLSX` using `glue()`). The new SECTION 12 defines them inline at steps 12.6 and 12.8 respectively. Verify no other section between lines 103 and 907 references `OUTPUT_RDS` or `OUTPUT_XLSX` other than the constants block — if any do, update those references to the inline values or guard them with a check that the variable exists.

**Verify:** Run `grep -n "OUTPUT_RDS\|OUTPUT_XLSX\|SECTION 12\|7 sheets\|add_styled_sheet" R/122_encounter_distance.R` and confirm: no `7 sheets` string, exactly one `wb_workbook()` call, and six `add_styled_sheet(` calls with sheet names KEY, A_distribution_summary, B_histogram_bins, C_completeness, D_fill_offsets, QC.

**Done:** SECTION 12 of `R/122_encounter_distance.R` writes exactly 6 sheets, calls `make_distance_histograms()` and `summarise_distance()`, saves `distance_patient_<date>.rds`, and passes the three-part `stopifnot` row-count reconciliation.

---

### Task 154-02: Create `R/utils/utils_distance_hist.R` and wire ENC_TYPE into R/122

**Goal:** Write the new utility file with all four functions (`bin_distance`, `plot_distance_hist`, `make_distance_histograms` verbatim from Appendix B, plus the new `summarise_distance`), then make two targeted edits to `R/122_encounter_distance.R`: add the `source()` call in SECTION 1, and add `ENC_TYPE` to the `dplyr::select()` in SECTION 3 and the final `enc_distance` `select()` in SECTION 7.

**Files:**
- `R/utils/utils_distance_hist.R` — create new
- `R/122_encounter_distance.R` — edit SECTION 1 (line 60 area), SECTION 3 (line 213 area), SECTION 7 (lines 530–548)

**Steps:**

1. Create `R/utils/utils_distance_hist.R` with the following content exactly:

```r
# ==============================================================================
# utils_distance_hist.R -- Distance histogram helpers (Phase 154)
# ==============================================================================
# Functions:
#   bin_distance()           -- cut distance_mi into histogram bins (linear or log)
#   plot_distance_hist()     -- ggplot2 bar chart with UF brand colors
#   make_distance_histograms() -- produce 4 PNGs + return bin tibble + stats
#   summarise_distance()     -- compute n/median/IQR/p90/p95/p99/max_mi by breakout
#
# Source: bin_distance / plot_distance_hist / make_distance_histograms are
# verbatim from Appendix B of MILESTONE_encounter_distance.md (lines 264-353).
# summarise_distance() is new in Phase 154.
#
# Called from: R/122_encounter_distance.R SECTION 1 (after utils_zip_calendar.R)
# ==============================================================================

# UF brand colors (locked for this deliverable; do not source utils_pptx.R)
UF_BLUE   <- "#0021A5"
UF_ORANGE <- "#FA4616"

# ------------------------------------------------------------------------------
#' Cut distance_mi values into histogram bins.
#'
#' @param mi     Numeric vector of distances in miles.
#' @param scale  "linear" (5-mile bins up to 300 mi then Inf) or
#'               "log"    (0.25-unit log10(1+mi) bins).
#' @param width  Bin width for linear scale (default 5 miles).
#' @param cap    Upper cap for linear bins before the Inf tail (default 300).
#' @return tibble with columns: bin, lower, upper, lower_mi, upper_mi, n, pct, scale.
bin_distance <- function(mi, scale = c("linear", "log"), width = 5, cap = 300) {
  scale <- match.arg(scale)
  mi <- mi[!is.na(mi)]
  if (scale == "linear") {
    edges <- c(seq(0, cap, by = width), Inf)
    x <- mi
  } else {
    edges <- seq(0, ceiling(log10(1 + max(mi)) * 4) / 4, by = 0.25)
    x <- log10(1 + mi)
  }
  cut_x <- cut(x, breaks = edges, right = FALSE, include.lowest = TRUE)
  tibble::tibble(bin = levels(cut_x),
                 lower = head(edges, -1),
                 upper = tail(edges, -1)) |>
    dplyr::left_join(tibble::as_tibble(table(bin = cut_x)), by = "bin") |>
    dplyr::mutate(n = dplyr::coalesce(as.integer(n), 0L),
                  pct = 100 * n / sum(n),
                  scale = scale,
                  lower_mi = if (scale == "log") 10^lower - 1 else lower,
                  upper_mi = if (scale == "log") 10^upper - 1 else upper)
}

# ------------------------------------------------------------------------------
#' Plot a distance histogram with UF brand colors.
#'
#' @param bins     tibble from bin_distance().
#' @param stats    tibble with columns n, n_excluded, median, p90, n_zero.
#' @param level    "encounter" or "patient" (controls axis label).
#' @param cutoffs  Optional numeric vector of candidate cutoffs in miles (dotted lines).
#' @param run_date Date string for caption.
#' @return ggplot2 object.
plot_distance_hist <- function(bins, stats, level = c("encounter", "patient"),
                               cutoffs = NULL, run_date = Sys.Date()) {
  level <- match.arg(level)
  is_log <- unique(bins$scale) == "log"
  bins <- bins |> dplyr::mutate(mid = (lower + pmin(upper, lower + (upper - lower))) / 2)
  if (!is_log) bins$mid[is.infinite(bins$upper)] <- max(bins$lower) + (bins$lower[2] - bins$lower[1]) / 2
  xf <- if (is_log) function(v) log10(1 + v) else identity
  p <- ggplot2::ggplot(bins, ggplot2::aes(x = mid, y = n)) +
    ggplot2::geom_col(width = diff(bins$lower)[1], fill = UF_BLUE, colour = "white", linewidth = 0.2) +
    ggplot2::geom_vline(xintercept = xf(stats$median), colour = UF_ORANGE, linewidth = 0.8) +
    ggplot2::geom_vline(xintercept = xf(stats$p90),    colour = UF_ORANGE, linewidth = 0.8, linetype = "dashed") +
    ggplot2::labs(
      x = if (is_log) "Distance, miles (log10(1 + mi) scale)" else "Distance, miles",
      y = if (level == "encounter") "Encounters" else "Patients",
      title = sprintf("Patient-to-encounter distance, %s level", level),
      subtitle = sprintf("n = %s; median %.1f mi (solid), 90th percentile %.1f mi (dashed)",
                         format(stats$n, big.mark = ","), stats$median, stats$p90),
      caption = sprintf("Distance: zipcodeR::zip_distance() on ZIP5 centroids. Excludes %s %ss with no computable distance. Run %s.",
                        format(stats$n_excluded, big.mark = ","), level, run_date)
    ) +
    ggplot2::theme_minimal(base_size = 12) +
    ggplot2::theme(plot.caption = ggplot2::element_text(hjust = 0, colour = "grey30"))
  if (!is.null(cutoffs))
    p <- p + ggplot2::geom_vline(xintercept = xf(cutoffs), colour = UF_ORANGE, linetype = "dotted", linewidth = 0.6)
  if (is_log) {
    ticks <- c(0, 1, 5, 10, 25, 50, 100, 250, 500, 1000)
    p <- p + ggplot2::scale_x_continuous(breaks = log10(1 + ticks), labels = ticks)
  }
  p
}

# ------------------------------------------------------------------------------
#' Produce 4 histogram PNGs and return bin tibble + stats tibble.
#'
#' @param dist     enc_distance tibble (must have columns distance_status, distance_mi, ID).
#' @param out_dir  Output directory; PNGs go to out_dir/figures/.
#' @param run_date Date string used in file names (default today YYYYMMDD).
#' @param cutoffs  Optional numeric vector of candidate cutoffs in miles.
#' @return list(bins = <tibble>, stats = <tibble with level column>).
make_distance_histograms <- function(dist, out_dir, run_date = format(Sys.Date(), "%Y%m%d"),
                                     cutoffs = NULL) {
  dir.create(file.path(out_dir, "figures"), showWarnings = FALSE, recursive = TRUE)
  enc <- dist |> dplyr::filter(distance_status == "computed")
  pat <- enc |> dplyr::group_by(ID) |> dplyr::summarise(distance_mi = median(distance_mi), .groups = "drop")
  summ <- function(d, n_total) tibble::tibble(
    n = nrow(d), n_excluded = n_total - nrow(d),
    median = median(d$distance_mi), p90 = quantile(d$distance_mi, .90),
    n_zero = sum(d$distance_mi == 0))
  levels <- list(
    encounter = list(d = enc, stats = summ(enc, nrow(dist))),
    patient   = list(d = pat, stats = summ(pat, dplyr::n_distinct(dist$ID))))
  bins_out <- list()
  for (lv in names(levels)) {
    for (sc in c("linear", "log")) {
      b <- bin_distance(levels[[lv]]$d$distance_mi, scale = sc)
      bins_out[[paste(lv, sc)]] <- dplyr::mutate(b, level = lv, .before = 1)
      g <- plot_distance_hist(b, levels[[lv]]$stats, level = lv, cutoffs = cutoffs, run_date = run_date)
      ggplot2::ggsave(file.path(out_dir, "figures", sprintf("encounter_distance_hist_%s_%s_%s.png", lv, sc, run_date)),
                      g, width = 8, height = 5, dpi = 300, bg = "white")
    }
  }
  list(bins = dplyr::bind_rows(bins_out),
       stats = dplyr::bind_rows(lapply(levels, `[[`, "stats"), .id = "level"))
}

# ------------------------------------------------------------------------------
#' Summarise distance_mi for computed encounters, with a breakout label column.
#'
#' @param enc_distance tibble with columns distance_status, distance_mi, ADMIT_DATE,
#'                     ENC_TYPE, facility_state.
#' @param by           One of "overall", "year", "ENC_TYPE", "facility_state".
#' @return tibble with columns breakout, n, median_mi, IQR_mi, p90_mi, p95_mi, p99_mi, max_mi.
summarise_distance <- function(enc_distance, by = c("overall", "year", "ENC_TYPE", "facility_state")) {
  by <- match.arg(by)

  computed <- enc_distance |> dplyr::filter(distance_status == "computed", !is.na(distance_mi))

  .summarise_one <- function(df, label) {
    tibble::tibble(
      breakout   = label,
      n          = nrow(df),
      median_mi  = median(df$distance_mi, na.rm = TRUE),
      IQR_mi     = IQR(df$distance_mi,    na.rm = TRUE),
      p90_mi     = quantile(df$distance_mi, 0.90, na.rm = TRUE),
      p95_mi     = quantile(df$distance_mi, 0.95, na.rm = TRUE),
      p99_mi     = quantile(df$distance_mi, 0.99, na.rm = TRUE),
      max_mi     = max(df$distance_mi,    na.rm = TRUE)
    )
  }

  if (by == "overall") {
    return(.summarise_one(computed, "overall"))
  }

  group_col <- switch(by,
    "year"          = dplyr::mutate(computed, .grp = as.character(lubridate::year(ADMIT_DATE))),
    "ENC_TYPE"      = dplyr::mutate(computed, .grp = as.character(ENC_TYPE)),
    "facility_state"= dplyr::mutate(computed, .grp = as.character(facility_state))
  )

  prefix <- switch(by,
    "year"           = "year_",
    "ENC_TYPE"       = "enc_type_",
    "facility_state" = "state_"
  )

  group_col |>
    dplyr::group_by(.grp) |>
    dplyr::group_modify(~ .summarise_one(.x, paste0(prefix, .y$.grp))) |>
    dplyr::ungroup() |>
    dplyr::select(-".grp")
}
```

2. In `R/122_encounter_distance.R` SECTION 1, add a `source()` call for the new utility. Find line 60:
   ```r
   source("R/utils/utils_zip_calendar.R")
   ```
   Insert immediately after it (as line 61):
   ```r
   source("R/utils/utils_distance_hist.R")
   ```

3. In SECTION 3 of `R/122_encounter_distance.R`, find the `dplyr::select()` call at line 213:
   ```r
     dplyr::select(ID, ENCOUNTERID, ADMIT_DATE, enc_zip_raw = FACILITY_LOCATION) %>%
   ```
   Replace with:
   ```r
     dplyr::select(ID, ENCOUNTERID, ADMIT_DATE, ENC_TYPE, enc_zip_raw = FACILITY_LOCATION) %>%
   ```

4. In SECTION 7 of `R/122_encounter_distance.R`, find the `dplyr::select()` building `enc_distance` (lines 530–548). The current select list is:
   ```
   ID, ENCOUNTERID, ADMIT_DATE, enc_zip_norm, zip5_facility, zip9_patient, zip5_patient,
   zip5_patient_source, days_offset, n_candidates_in_range, distance_mi, distance_km,
   distance_km_haversine, distance_status, distance_basis, enc_centroid_source, res_centroid_source
   ```
   Add `ENC_TYPE` after `ADMIT_DATE` so the list begins:
   ```r
   dplyr::select(
     ID,
     ENCOUNTERID,
     ADMIT_DATE,
     ENC_TYPE,
     enc_zip_norm,
     ...
   ```
   All other columns remain unchanged.

**Verify:**
```
grep -n "utils_distance_hist\|ENC_TYPE" R/122_encounter_distance.R
```
Expected output: line ~61 has `source("R/utils/utils_distance_hist.R")`, line ~213 has `ENC_TYPE` in the SECTION 3 select, and the SECTION 7 `enc_distance` select also contains `ENC_TYPE`.

```
grep -c "^bin_distance\|^plot_distance_hist\|^make_distance_histograms\|^summarise_distance" R/utils/utils_distance_hist.R
```
Expected: 4

**Done:** `R/utils/utils_distance_hist.R` exists with four exported functions; `R/122_encounter_distance.R` sources it in SECTION 1 and carries `ENC_TYPE` from SECTION 3 through SECTION 7 into `enc_distance`.

---

### Task 154-03: Write the test file for `utils_distance_hist.R`

**Goal:** Create `tests/testthat/test-utils-distance-hist.R` with unit tests covering all four functions. Tests must be runnable with `testthat::test_file()` without a live DuckDB connection or HiPerGator data — they use only synthetic vectors and small tibbles.

**Files:**
- `tests/testthat/test-utils-distance-hist.R` — create new

**Steps:**

1. Create `tests/testthat/test-utils-distance-hist.R` with the following content:

```r
# ==============================================================================
# test-utils-distance-hist.R -- Unit tests for R/utils/utils_distance_hist.R
# Phase 154
# ==============================================================================
# Run with: testthat::test_file("tests/testthat/test-utils-distance-hist.R")
# No DuckDB, HiPerGator, or live data required.

library(testthat)
library(dplyr)
library(tibble)

source("R/utils/utils_distance_hist.R")

# ---- Synthetic data ----
set.seed(154)
mi_vec <- c(0, 1.5, 5, 10, 25, 50, 75, 100, 200, 300, 500)

make_enc_distance <- function(n = 30) {
  tibble::tibble(
    ID              = rep(paste0("P", 1:10), each = 3)[seq_len(n)],
    ADMIT_DATE      = seq(as.Date("2020-01-01"), by = "month", length.out = n),
    ENC_TYPE        = rep(c("AV", "IP", "ED"), length.out = n),
    zip5_facility   = rep(c("32601", "32603", "33101"), length.out = n),
    facility_state  = rep(c("FL", "FL", "FL"), length.out = n),
    distance_mi     = c(runif(n - 3, 0, 200), NA, NA, NA),
    distance_status = c(rep("computed", n - 3), "patient_zip_missing", "facility_zip_missing", "zip_not_in_db"),
    zip5_patient_source = rep("in_range_zip5", n),
    days_offset     = rep(0L, n)
  )
}

enc_dist <- make_enc_distance()

# ==============================================================================
# bin_distance()
# ==============================================================================

test_that("bin_distance linear: n sums to length of input", {
  b <- bin_distance(mi_vec, scale = "linear")
  expect_equal(sum(b$n), length(mi_vec))
})

test_that("bin_distance linear: pct sums to 100", {
  b <- bin_distance(mi_vec, scale = "linear")
  expect_equal(round(sum(b$pct), 5), 100)
})

test_that("bin_distance log: n sums to length of input", {
  b <- bin_distance(mi_vec, scale = "log")
  expect_equal(sum(b$n), length(mi_vec))
})

test_that("bin_distance: NAs in input are silently dropped", {
  b <- bin_distance(c(10, NA, 50, NA), scale = "linear")
  expect_equal(sum(b$n), 2L)
})

test_that("bin_distance linear: scale column is 'linear'", {
  b <- bin_distance(mi_vec, scale = "linear")
  expect_true(all(b$scale == "linear"))
})

test_that("bin_distance log: scale column is 'log'", {
  b <- bin_distance(mi_vec, scale = "log")
  expect_true(all(b$scale == "log"))
})

test_that("bin_distance: zero distance falls in first bin", {
  b <- bin_distance(c(0, 10), scale = "linear")
  first_bin_n <- b$n[b$lower == 0]
  expect_true(first_bin_n >= 1L)
})

# ==============================================================================
# plot_distance_hist()
# ==============================================================================

test_that("plot_distance_hist returns a ggplot for linear bins", {
  b <- bin_distance(mi_vec, scale = "linear")
  stats <- tibble::tibble(n = length(mi_vec), n_excluded = 0L,
                           median = median(mi_vec), p90 = quantile(mi_vec, 0.9),
                           n_zero = sum(mi_vec == 0))
  p <- plot_distance_hist(b, stats, level = "encounter")
  expect_s3_class(p, "ggplot")
})

test_that("plot_distance_hist returns a ggplot for log bins", {
  b <- bin_distance(mi_vec, scale = "log")
  stats <- tibble::tibble(n = length(mi_vec), n_excluded = 0L,
                           median = median(mi_vec), p90 = quantile(mi_vec, 0.9),
                           n_zero = sum(mi_vec == 0))
  p <- plot_distance_hist(b, stats, level = "patient")
  expect_s3_class(p, "ggplot")
})

# ==============================================================================
# make_distance_histograms()
# ==============================================================================

test_that("make_distance_histograms returns list with bins and stats", {
  tmp <- tempdir()
  result <- make_distance_histograms(enc_dist, out_dir = tmp, run_date = "20260918")
  expect_named(result, c("bins", "stats"))
})

test_that("make_distance_histograms bins has level column with encounter and patient", {
  tmp <- tempdir()
  result <- make_distance_histograms(enc_dist, out_dir = tmp, run_date = "20260918")
  expect_true(all(c("encounter", "patient") %in% result$bins$level))
})

test_that("make_distance_histograms bins has scale column with linear and log", {
  tmp <- tempdir()
  result <- make_distance_histograms(enc_dist, out_dir = tmp, run_date = "20260918")
  expect_true(all(c("linear", "log") %in% result$bins$scale))
})

test_that("make_distance_histograms writes 4 PNG files", {
  tmp <- tempdir()
  result <- make_distance_histograms(enc_dist, out_dir = tmp, run_date = "20260918")
  pngs <- list.files(file.path(tmp, "figures"), pattern = "\\.png$", full.names = FALSE)
  expect_equal(length(pngs), 4L)
})

test_that("make_distance_histograms encounter stats$n equals nrow of computed rows", {
  tmp <- tempdir()
  result <- make_distance_histograms(enc_dist, out_dir = tmp, run_date = "20260918")
  n_computed <- nrow(dplyr::filter(enc_dist, distance_status == "computed"))
  enc_stat_n <- result$stats |> dplyr::filter(level == "encounter") |> dplyr::pull(n)
  expect_equal(enc_stat_n, n_computed)
})

# ==============================================================================
# summarise_distance()
# ==============================================================================

test_that("summarise_distance overall returns one row with breakout = 'overall'", {
  out <- summarise_distance(enc_dist, by = "overall")
  expect_equal(nrow(out), 1L)
  expect_equal(out$breakout, "overall")
})

test_that("summarise_distance overall n equals nrow of computed non-NA distance rows", {
  out <- summarise_distance(enc_dist, by = "overall")
  expected_n <- nrow(dplyr::filter(enc_dist, distance_status == "computed", !is.na(distance_mi)))
  expect_equal(out$n, expected_n)
})

test_that("summarise_distance by year has breakout values prefixed year_", {
  out <- summarise_distance(enc_dist, by = "year")
  expect_true(all(startsWith(out$breakout, "year_")))
})

test_that("summarise_distance by ENC_TYPE has breakout values prefixed enc_type_", {
  out <- summarise_distance(enc_dist, by = "ENC_TYPE")
  expect_true(all(startsWith(out$breakout, "enc_type_")))
})

test_that("summarise_distance by facility_state has breakout values prefixed state_", {
  out <- summarise_distance(enc_dist, by = "facility_state")
  expect_true(all(startsWith(out$breakout, "state_")))
})

test_that("summarise_distance returns required stat columns", {
  out <- summarise_distance(enc_dist, by = "overall")
  expect_named(out, c("breakout", "n", "median_mi", "IQR_mi", "p90_mi", "p95_mi", "p99_mi", "max_mi"))
})

test_that("summarise_distance: p90 >= median for overall", {
  out <- summarise_distance(enc_dist, by = "overall")
  expect_true(out$p90_mi >= out$median_mi)
})
```

2. Confirm the test file is runnable in a clean R session (no DuckDB, no HiPerGator paths):
   ```r
   testthat::test_file("tests/testthat/test-utils-distance-hist.R")
   ```
   All tests must pass. If `lubridate` is not explicitly loaded in `utils_distance_hist.R`, add `lubridate::year()` namespace-qualified calls (already done in the code above) — do not add a bare `library(lubridate)` to the util file; use `lubridate::year()` instead.

**Verify:**
```
Rscript -e "testthat::test_file('tests/testthat/test-utils-distance-hist.R')"
```
Expected: all tests pass, 0 failures, 0 errors. If `ggplot2::ggsave` writes to a temp directory, 4 PNG files will appear under `tempdir()/figures/`.

**Done:** `tests/testthat/test-utils-distance-hist.R` exists with tests for all four functions covering normal cases, edge cases (NAs, zero distance), and the row-count invariant. All tests pass with `testthat::test_file()`.

---

## Verification

After all three tasks are complete, confirm the following:

1. **6-sheet xlsx structure** — Open `output/encounter_distance_<date>.xlsx` and confirm exactly 6 tabs in order: KEY, A_distribution_summary, B_histogram_bins, C_completeness, D_fill_offsets, QC. Confirm no tabs named A_encounter_distance, B_patient_summary, C_distribution, D_flags, or E_completeness remain.

2. **4 histogram PNGs** — Verify these four files exist in `output/figures/`:
   - `encounter_distance_hist_encounter_linear_<date>.png`
   - `encounter_distance_hist_encounter_log_<date>.png`
   - `encounter_distance_hist_patient_linear_<date>.png`
   - `encounter_distance_hist_patient_log_<date>.png`

3. **Per-patient rds** — Verify `output/distance_patient_<date>.rds` exists. Load it and confirm `nrow()` equals `n_distinct(ID)` among `enc_distance` rows where `distance_status == "computed"`. Confirm columns include `ID`, `n_enc_computed`, `median_mi`, `min_mi`, `max_mi`, and `share_ge_30`, `share_ge_50` (or the configured cutoffs).

4. **Row-count reconciliation** — The `stopifnot` block in SECTION 12.5 passes without error during a full run. This is the canonical proof that the A_distribution_summary overall row, the histogram stats tibble, and the patient rds are all consistent.

5. **Test suite** — `Rscript -e "testthat::test_file('tests/testthat/test-utils-distance-hist.R')"` reports 0 failures and 0 errors.

6. **ENC_TYPE column present** — `Rscript -e "source('R/122_encounter_distance.R'); cat(names(enc_distance))"` output includes `ENC_TYPE` (requires DuckDB on HiPerGator; for local verification use the grep check from Task 154-02 step 4 instead).
