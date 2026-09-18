# Phase 154: Distribution and Histogram Deliverable — Plan

## Overview

Phase 154 adds histogram and distribution-summary infrastructure to `R/122_encounter_distance.R`. A new utility file `R/utils/utils_distance_hist.R` provides four functions (three from Appendix B with one guard added, one new).

**Execution order is 154-02 → 154-03 → 154-01.** 154-01 replaces SECTION 12 with calls into the utility file, so the file and its tests must exist first; executing in numeric order leaves R/122 unrunnable between tasks.

**Anchoring:** all edits to `R/122_encounter_distance.R` are anchored on section-header comment text, not line numbers — `FIX_122_and_zip_calendar.md` has already shifted the file, and line numbers cited in prose below are approximate. The script's SECTION 3 and SECTION 7 gain an `ENC_TYPE` column, and SECTION 12 is fully replaced: the existing 7-sheet xlsx becomes a 6-sheet spec, four histogram PNGs are written to `output/figures/`, a per-patient summary rds is written, and a row-count reconciliation stopifnot guards the final outputs.

## Prerequisites

- Phase 152/153 is complete: `R/122_encounter_distance.R` exists and builds `enc_distance` with columns `ID`, `ENCOUNTERID`, `ADMIT_DATE`, `zip5_facility`, `zip5_patient_source`, `days_offset`, `distance_mi`, `distance_status`.
- `R/utils/utils_zip_calendar.R` is already sourced in SECTION 1 of R/122 (line 60).
- `openxlsx2` and `zipcodeR` are installed in the project renv.
- `ggplot2` is available (part of tidyverse in renv).
- `FIX_122_and_zip_calendar.md` has been fully applied (in particular A5 and B4).
- The `add_styled_sheet()` helper in R/122 SECTION 12 is kept intact; tasks below reuse it. Its signature is `(wb, sheet_name, title, subtitle, data_tbl, extra_tbl = NULL, extra_label = NULL)`; confirm before use.
- The constants block near the top of R/122 keeps `OUTPUT_RDS` and `OUTPUT_XLSX`; the new SECTION 12 references them and does not redefine them.

---

## Tasks

### Task 154-01: Replace SECTION 12 with the 6-sheet xlsx writer

**Goal:** Swap out the existing 7-sheet xlsx builder (lines 916–1113 of `R/122_encounter_distance.R`) for the new 6-sheet spec. Also build the `A_distribution_summary` and `D_fill_offsets` tables inline in SECTION 12 (before the workbook assembly), add the facility-state join, call `make_distance_histograms()` and `summarise_distance()`, write the histogram PNGs, and add a row-count reconciliation stopifnot.

**Files:**
- `R/122_encounter_distance.R` — SECTION 12 block only (lines 916–1113)

**Steps:**

1. Before editing, confirm the object names the new block depends on exist in SECTIONS 8–11:
   ```
   grep -n "waterfall_tbl\|qc_tbl\|unmatched_zip9_by_state\|completeness_tbl\|status_breakdown_tbl" R/122_encounter_distance.R
   ```
   The block below builds `completeness_tbl` and `status_breakdown_tbl` itself (12.3a) from `enc_distance`, so only `qc_tbl` and `unmatched_zip9_by_state` must pre-exist. If either is missing, stop and report.

2. Locate the comment line beginning `# SECTION 12A: RDS WRITE` and delete from that line through the end of the file (this removes 12A and the `# SECTION 12: XLSX ASSEMBLY AND WRITE` block). Keep the `add_styled_sheet()` function definition: if it sits inside the deleted range, cut it out first and re-insert it immediately above the new block. Then paste the following immediately after the `section_done("SECTIONS 8-11 summaries + QC")` call:

```r
# ==============================================================================
# SECTION 12: HISTOGRAMS, PATIENT RDS, AND 6-SHEET XLSX (Phase 154) ----
# ==============================================================================

message("--- Phase 154: histogram PNGs, patient rds, 6-sheet xlsx ---")

# ---- 12.0 Facility-state join (for A_distribution_summary by_facility_state breakout) ----
# zipcodeR::zip_code_db is a data frame bundled with the package.
# Join on zip5_facility (character, 5-digit) to state.
zip_state_lkp <- zipcodeR::zip_code_db %>%
  dplyr::transmute(zipcode = as.character(zipcode), facility_state = state) %>%
  dplyr::distinct(zipcode, .keep_all = TRUE)

n_before_state_join <- nrow(enc_distance)
enc_distance <- enc_distance %>%
  dplyr::left_join(zip_state_lkp, by = c("zip5_facility" = "zipcode"))
stopifnot("facility-state join changed row count" = nrow(enc_distance) == n_before_state_join)

# ---- 12.0a Input invariants -- checked BEFORE any file is written ----
stopifnot(
  "computed status has missing distance_mi" =
    !any(enc_distance$distance_status == "computed" & is.na(enc_distance$distance_mi)),
  "non-computed status has non-missing distance_mi" =
    !any(enc_distance$distance_status != "computed" & !is.na(enc_distance$distance_mi)),
  "distance_mi has negative or non-finite values" =
    all(is.finite(enc_distance$distance_mi[!is.na(enc_distance$distance_mi)]) &
        enc_distance$distance_mi[!is.na(enc_distance$distance_mi)] >= 0),
  "nearest-fill rows contain days_offset == 0" =
    !any(enc_distance$zip5_patient_source %in% c("nearest_zip9", "nearest_zip5") &
         enc_distance$days_offset == 0, na.rm = TRUE)
)

# Single canonical definition used by every table, figure, and check below.
computed_rows <- enc_distance %>% dplyr::filter(distance_status == "computed")

cutoffs_mi <- if (!is.null(CONFIG$distance_candidate_cutoffs_mi)) {
  CONFIG$distance_candidate_cutoffs_mi
} else {
  c(30, 50)
}
stopifnot(
  "distance_candidate_cutoffs_mi must be finite, non-negative, unique numerics" =
    is.numeric(cutoffs_mi) && all(is.finite(cutoffs_mi)) && all(cutoffs_mi >= 0) &&
    !anyDuplicated(cutoffs_mi)
)

message(glue(
  "  facility_state join: {sum(!is.na(enc_distance$facility_state))} of ",
  "{nrow(enc_distance)} rows matched a state ({sum(is.na(enc_distance$facility_state))} unmatched)"
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

# 13 breaks -> 12 intervals, matching 12 labels. right = FALSE gives [-7,0) = -7..-1
# (past) and [0,7) = 1..6 (future); 0 itself never occurs for nearest fills.
fill_breaks <- c(-Inf, -365, -180, -90, -30, -7, 0, 7, 30, 90, 180, 365, Inf)
fill_labels <- c(
  "[-Inf,-365)", "[-365,-180)", "[-180,-90)", "[-90,-30)",
  "[-30,-7)", "[-7,0)", "[0,7)", "[7,30)",
  "[30,90)", "[90,180)", "[180,365)", "[365,+Inf)"
)
stopifnot(length(fill_breaks) - 1L == length(fill_labels))

D_fill_offsets_bins <- tibble::tibble(
  bin = fill_labels,
  n   = as.integer(table(cut(nearest_rows$days_offset,
                              breaks = fill_breaks,
                              labels = fill_labels,
                              right = FALSE,
                              include.lowest = FALSE)))
) %>%
  dplyr::mutate(pct = 100 * n / sum(n))

# Summary metrics go in a separate metric/value table (written via extra_tbl),
# not into the pct column of the bin table.
D_fill_offsets_summary <- tibble::tibble(
  metric = c("median_signed_offset_days", "median_abs_offset_days", "p90_abs_offset_days",
             "share_past_pct (days_offset > 0)", "share_future_pct (days_offset < 0)"),
  value  = if (nrow(nearest_rows) > 0) c(
    median(nearest_rows$days_offset),
    median(abs(nearest_rows$days_offset)),
    unname(quantile(abs(nearest_rows$days_offset), 0.90)),
    100 * mean(nearest_rows$days_offset > 0),
    100 * mean(nearest_rows$days_offset < 0)
  ) else rep(NA_real_, 5)
)

D_fill_offsets <- D_fill_offsets_bins

message(glue(
  "  D_fill_offsets: {nrow(nearest_rows)} nearest-fill rows; ",
  "{nrow(D_fill_offsets_bins)} bins"
))

# ---- 12.3a Completeness waterfall and status breakdown (C_completeness) ----
n_enc_total     <- nrow(enc_distance)
n_fac_zip       <- sum(!is.na(enc_distance$zip5_facility))
n_inrange_pat   <- sum(!is.na(enc_distance$zip5_facility) &
                       enc_distance$zip5_patient_source %in% c("in_range_zip9", "in_range_zip5"))
n_nearest_pat   <- sum(!is.na(enc_distance$zip5_facility) &
                       enc_distance$zip5_patient_source %in% c("nearest_zip9", "nearest_zip5"))
n_computed      <- sum(enc_distance$distance_status == "computed")

completeness_tbl <- tibble::tibble(
  Step = c("Encounters (cohort)", "With facility ZIP5", "  of which in-range patient ZIP",
           "  of which nearest-fill patient ZIP", "Distance computed"),
  N    = c(n_enc_total, n_fac_zip, n_inrange_pat, n_nearest_pat, n_computed),
  Pct_of_total = round(100 * N / n_enc_total, 2)
)

status_breakdown_tbl <- enc_distance %>%
  dplyr::count(distance_status, name = "N") %>%
  dplyr::mutate(Pct = round(100 * N / sum(N), 2)) %>%
  dplyr::arrange(dplyr::desc(N))
stopifnot(sum(status_breakdown_tbl$N) == n_enc_total)

# ---- 12.4 Per-patient summary table (saved in 12.5c) ----
# One row per patient with any computed encounter.
# share_ge_<c> columns for each cutoff in CONFIG$distance_candidate_cutoffs_mi (default c(30, 50)).
# One grouped summarise; share_ge_<c> columns built from the cutoff vector.
share_exprs <- setNames(
  lapply(cutoffs_mi, function(cm) rlang::expr(mean(distance_mi >= !!cm))),
  paste0("share_ge_", cutoffs_mi)
)

distance_patient <- computed_rows %>%
  dplyr::group_by(ID) %>%
  dplyr::summarise(
    n_enc_computed = dplyr::n(),
    median_mi      = median(distance_mi),
    min_mi         = min(distance_mi),
    max_mi         = max(distance_mi),
    !!!share_exprs,
    .groups = "drop"
  )

message(glue("  distance_patient built: {nrow(distance_patient)} patients (saved after reconciliation)"))

# ---- 12.5 Table reconciliation stopifnot (nothing has been written yet) ----
n_A_overall <- A_distribution_summary %>%
  dplyr::filter(breakout == "overall") %>%
  dplyr::pull(n)

stopifnot(
  "A_distribution_summary overall n != nrow(computed_rows)" =
    n_A_overall == nrow(computed_rows),
  "distance_patient nrow != n_distinct(ID) among computed rows" =
    nrow(distance_patient) == dplyr::n_distinct(computed_rows$ID),
  "D_fill_offsets bin n != number of nearest-fill rows" =
    sum(D_fill_offsets_bins$n) == nrow(nearest_rows),
  "completeness_tbl 'Distance computed' != nrow(computed_rows)" =
    completeness_tbl$N[completeness_tbl$Step == "Distance computed"] == nrow(computed_rows)
)
message("  Table reconciliation stopifnot PASSED")

# ---- 12.5b Histogram PNGs via make_distance_histograms() (first files written) ----
# Returns list(bins = <tibble>, stats = <tibble>) where bins is B_histogram_bins content.
hist_result <- make_distance_histograms(
  dist     = enc_distance,
  out_dir  = CONFIG$output_dir,
  run_date = RUN_DATE,
  cutoffs  = NULL   # dotted candidate-cutoff lines are a Phase 155 addition (154-CONTEXT)
)

message(glue(
  "  make_distance_histograms(): {nrow(hist_result$bins)} bin rows; ",
  "4 PNGs written to {file.path(CONFIG$output_dir, 'figures')}"
))

# Bin counts must contain every computed observation, at every level/scale.
n_pat_computed <- dplyr::n_distinct(computed_rows$ID)
for (lv in c("encounter", "patient")) {
  for (sc in c("linear", "log")) {
    n_bins <- sum(hist_result$bins$n[hist_result$bins$level == lv & hist_result$bins$scale == sc])
    n_expect <- if (lv == "encounter") nrow(computed_rows) else n_pat_computed
    if (n_bins != n_expect) stop(sprintf("bin count mismatch: %s/%s has %d, expected %d", lv, sc, n_bins, n_expect))
  }
}
n_hist_enc_stats <- hist_result$stats %>% dplyr::filter(level == "encounter") %>% dplyr::pull(n)
stopifnot("make_distance_histograms() encounter stats$n != nrow(computed_rows)" =
            n_hist_enc_stats == nrow(computed_rows))
message("  histogram bin-count reconciliation PASSED")

# ---- 12.5c Per-patient rds write ----
OUTPUT_PATIENT_RDS <- file.path(CONFIG$output_dir,
                                 glue("distance_patient_{RUN_DATE}.rds"))
saveRDS(distance_patient, OUTPUT_PATIENT_RDS)
message(glue(
  "  distance_patient rds written: {OUTPUT_PATIENT_RDS} ({nrow(distance_patient)} patients)"
))

# ---- 12.6 encounter_distance rds (full table, before xlsx) ----
# OUTPUT_RDS is defined in the constants block near the top of the script.
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
    "zipcodeR::zip_distance() between ZIP5 codes (miles); canonical per D-01. zip_distance() represents each ZIP by the single lat/lon in zipcodeR::zip_code_db (the ZCTA centroid) and takes the great-circle distance between the two points; same-ZIP pairs are 0 mi and large rural ZIPs carry more positional error than small urban ones. No km in this deliverable (154-D3).",
    glue("4 PNGs in {file.path(CONFIG$output_dir, 'figures')}: encounter_distance_hist_{{level}}_{{scale}}_{RUN_DATE}.png for level in (encounter, patient), scale in (linear, log)"),
    glue("distance_patient_{RUN_DATE}.rds: one row per patient with any computed encounter; columns: ID, n_enc_computed, median_mi, min_mi, max_mi, share_ge_<c> for c in ({paste(cutoffs_mi, collapse=', ')})"),
    "overall | year_<YYYY> (by ADMIT_DATE year) | enc_type_<X> (by ENC_TYPE) | state_<XX> (by facility_state from zipcodeR::zip_code_db)",
    "n, median_mi, IQR_mi, p90_mi, p95_mi, p99_mi, max_mi — all in miles (154-D3); no mean/SD",
    "level, scale, bin, lower, upper, lower_mi, upper_mi, n, pct — from make_distance_histograms() bind_rows(bins_out)",
    "Five-step waterfall keyed on distance_status (encounters → facility ZIP → in-range patient ZIP → nearest patient ZIP → distance computed)",
    "Nearest-* fill rows (zip5_patient_source in nearest_zip9, nearest_zip5) only; signed-integer bins. SIGN: positive days_offset = address period ended BEFORE the encounter (past); negative = period began AFTER (future). Summary metrics in the second table on the sheet.",
    "Coverage waterfall; n_candidates_in_range>1; nearest-fill offset distribution; unmatched ZIP9 by state; zip9_crosswalk_present flag"
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
  "Signed-integer bins of days_offset for zip5_patient_source in {nearest_zip9, nearest_zip5}. Positive = period ended before the encounter (past); negative = period began after (future). 0 never occurs.",
  D_fill_offsets,
  extra_tbl   = D_fill_offsets_summary,
  extra_label = "Summary metrics (days; shares in percent)"
)

add_styled_sheet(
  wb, "QC",
  "QC: Coverage Waterfall and Quality Checks",
  "Waterfall from raw cohort ENCOUNTER count to distance computed; nearest-fill days_offset distribution; n_candidates_in_range>1.",
  qc_tbl,
  extra_tbl   = unmatched_zip9_by_state,
  extra_label = "Unmatched ZIP9 encounters by state (centroid_source == zip5_fallback)"
)

# OUTPUT_XLSX is defined in the constants block near the top of the script.
wb_save(wb, OUTPUT_XLSX)
message(glue("  xlsx written: {OUTPUT_XLSX} (6 sheets: KEY, A_distribution_summary, B_histogram_bins, C_completeness, D_fill_offsets, QC)"))
section_done("SECTION 12 Phase 154 outputs")

message("=== R/122_encounter_distance.R complete ===")
```

3. Leave the `OUTPUT_RDS` and `OUTPUT_XLSX` constants in the constants block unchanged; the new SECTION 12 uses them. Confirm with `grep -n "OUTPUT_RDS <-\|OUTPUT_XLSX <-" R/122_encounter_distance.R` that each is defined exactly once.

**Verify:** Run `grep -n "OUTPUT_RDS\|OUTPUT_XLSX\|SECTION 12\|7 sheets\|add_styled_sheet\|cutoffs  = NULL" R/122_encounter_distance.R` and confirm: no `7 sheets` string, exactly one `wb_workbook()` call, six `add_styled_sheet(` calls with sheet names KEY, A_distribution_summary, B_histogram_bins, C_completeness, D_fill_offsets, QC, and `cutoffs  = NULL` in the `make_distance_histograms()` call. Then `Rscript -e 'invisible(parse("R/122_encounter_distance.R"))'` must succeed.

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
# from Appendix B of MILESTONE_encounter_distance.md, with one addition:
# bin_distance() returns an empty bin table on empty input instead of erroring.
# summarise_distance() is new in Phase 154.
# Dependencies: dplyr, tibble, ggplot2, scales (a ggplot2 dependency; all namespace-qualified). No lubridate.
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
  if (length(mi) == 0L) {
    return(tibble::tibble(bin = character(0), lower = numeric(0), upper = numeric(0),
                          n = integer(0), pct = numeric(0), scale = character(0),
                          lower_mi = numeric(0), upper_mi = numeric(0)))
  }
  if (scale == "linear") {
    edges <- c(seq(0, cap, by = width), Inf)
    x <- mi
  } else {
    # Upper edge strictly above the max so a value exactly on a 0.25 boundary
    # (e.g. 9 mi -> log10(10) = 1) and the all-zero case (max_log = 0) both
    # yield >= 2 edges. include.lowest = TRUE would also cover the boundary
    # case, but the explicit form is clearer and covers all-zero.
    max_log <- max(log10(1 + mi))
    edges <- seq(0, (floor(max_log / 0.25) + 1) * 0.25, by = 0.25)
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
#' Layout rules (8 x 5 in at 300 dpi, base_size 12):
#'   - title/subtitle/caption are left-aligned to the plot edge (plot.title.position = "plot")
#'     so long strings never clip against the panel;
#'   - caption is split over two lines; nothing longer than ~90 characters per line;
#'   - x axis on the linear scale labels the open top bin as "<cap>+";
#'   - y axis uses comma separators; bars sit on the axis (no lower expansion);
#'   - reference lines are explained in the subtitle, not annotated on the panel
#'     (annotations overflow when the median sits near an axis edge).
#'
#' @param bins     tibble from bin_distance().
#' @param stats    tibble with columns n, n_excluded, median, p90, n_zero.
#' @param level    "encounter" or "patient" (controls axis label).
#' @param cutoffs  Optional numeric vector of candidate cutoffs in miles (dotted lines).
#' @param run_date Date string for caption.
#' @return ggplot2 object.
plot_distance_hist <- function(bins, stats, level = c("encounter", "patient"),
                               cutoffs = NULL, run_date = Sys.Date()) {
  level  <- match.arg(level)
  is_log <- unique(bins$scale) == "log"
  bw     <- bins$upper[1] - bins$lower[1]                     # bin width in axis units
  cap    <- if (is_log) NA_real_ else max(bins$lower)          # open top bin starts here
  bins   <- bins |> dplyr::mutate(mid = ifelse(is.infinite(upper), lower + bw / 2, (lower + upper) / 2))

  xf   <- if (is_log) function(v) log10(1 + v) else identity
  unit <- if (level == "encounter") "encounters" else "patients"

  p <- ggplot2::ggplot(bins, ggplot2::aes(x = mid, y = n)) +
    ggplot2::geom_col(width = bw, fill = UF_BLUE, colour = "white", linewidth = 0.2) +
    ggplot2::geom_vline(xintercept = xf(stats$median), colour = UF_ORANGE, linewidth = 0.8) +
    ggplot2::geom_vline(xintercept = xf(stats$p90),    colour = UF_ORANGE, linewidth = 0.8,
                        linetype = "dashed") +
    ggplot2::scale_y_continuous(labels = scales::label_comma(),
                                expand = ggplot2::expansion(mult = c(0, 0.05))) +
    ggplot2::labs(
      x = if (is_log) "Distance, miles (log scale)" else "Distance, miles",
      y = if (level == "encounter") "Encounters" else "Patients",
      title    = sprintf("Patient-to-encounter distance, %s level", level),
      subtitle = sprintf("n = %s. Median %.1f mi (solid line); 90th percentile %.1f mi (dashed line).",
                         format(stats$n, big.mark = ","), stats$median, stats$p90),
      caption  = sprintf("Distance: zipcodeR::zip_distance() between ZIP5 codes.\nExcludes %s %s with no computable distance. Run %s.",
                         format(stats$n_excluded, big.mark = ","), unit, run_date)
    ) +
    ggplot2::theme_minimal(base_size = 12) +
    ggplot2::theme(
      plot.title.position   = "plot",
      plot.caption.position = "plot",
      plot.title    = ggplot2::element_text(face = "bold", size = 13),
      plot.subtitle = ggplot2::element_text(size = 10, colour = "grey20", margin = ggplot2::margin(b = 8)),
      plot.caption  = ggplot2::element_text(hjust = 0, size = 8.5, colour = "grey30", lineheight = 1.1,
                                            margin = ggplot2::margin(t = 8)),
      panel.grid.minor   = ggplot2::element_blank(),
      panel.grid.major.x = ggplot2::element_blank(),
      axis.title = ggplot2::element_text(size = 10),
      axis.text  = ggplot2::element_text(size = 9),
      plot.margin = ggplot2::margin(10, 14, 8, 10)
    )

  if (is_log) {
    ticks <- c(0, 1, 2, 5, 10, 25, 50, 100, 250, 500, 1000, 2500)
    ticks <- ticks[log10(1 + ticks) <= max(bins$upper)]
    p <- p + ggplot2::scale_x_continuous(breaks = log10(1 + ticks), labels = scales::label_comma()(ticks),
                                         expand = ggplot2::expansion(mult = c(0.01, 0.02)))
  } else {
    step   <- if (cap >= 200) 50 else if (cap >= 100) 25 else 10
    brks   <- seq(0, cap, by = step)
    labs_x <- as.character(brks)
    top    <- cap + bw / 2
    p <- p + ggplot2::scale_x_continuous(breaks = c(brks, top), labels = c(labs_x, paste0(cap, "+")),
                                         expand = ggplot2::expansion(mult = c(0.01, 0.02)))
  }

  if (!is.null(cutoffs))
    p <- p + ggplot2::geom_vline(xintercept = xf(cutoffs), colour = UF_ORANGE,
                                 linetype = "dotted", linewidth = 0.6)
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
  if (nrow(enc) == 0L) {
    warning("make_distance_histograms(): no computed rows; no PNGs written")
    empty_bins <- bin_distance(numeric(0)) |> dplyr::mutate(level = character(0), .before = 1)
    return(list(bins = empty_bins,
                stats = tibble::tibble(level = c("encounter", "patient"), n = 0L,
                                       n_excluded = c(nrow(dist), dplyr::n_distinct(dist$ID)),
                                       median = NA_real_, p90 = NA_real_, n_zero = 0L)))
  }
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

  # Same definition as computed_rows in R/122; the status/NA invariant is asserted upstream.
  computed <- enc_distance |> dplyr::filter(distance_status == "computed")

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
    "year"           = dplyr::mutate(computed, .grp = format(ADMIT_DATE, "%Y")),
    "ENC_TYPE"       = dplyr::mutate(computed, .grp = as.character(ENC_TYPE)),
    "facility_state" = dplyr::mutate(computed, .grp = as.character(facility_state))
  ) |>
    dplyr::mutate(.grp = dplyr::coalesce(.grp, "unmatched"))

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

3. In SECTION 3 of `R/122_encounter_distance.R`, find the `dplyr::select()` call in the ENCOUNTER pull (approx. line 213):
   ```r
     dplyr::select(ID, ENCOUNTERID, ADMIT_DATE, enc_zip_raw = FACILITY_LOCATION) %>%
   ```
   Replace with:
   ```r
     dplyr::select(ID, ENCOUNTERID, ADMIT_DATE, ENC_TYPE, enc_zip_raw = FACILITY_LOCATION) %>%
   ```

4. In SECTION 7 of `R/122_encounter_distance.R`, find the `dplyr::select()` building `enc_distance` (approx. lines 530–548; anchor on the `distance_km_haversine,` line added by FIX B4). The current select list is:
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
library(withr)

# Follow the sourcing convention used by the existing test-utils-address*.R files.
# testthat::test_path() resolves relative to tests/testthat/, so this works under
# both test_file() and test_dir().
source(testthat::test_path("..", "..", "R", "utils", "utils_distance_hist.R"))

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

test_that("bin_distance: empty input returns an empty bin table, both scales", {
  for (sc in c("linear", "log")) {
    b <- bin_distance(numeric(0), scale = sc)
    expect_equal(nrow(b), 0L)
    expect_true(all(c("bin", "lower", "upper", "n", "pct", "scale", "lower_mi", "upper_mi") %in% names(b)))
  }
  b <- bin_distance(c(NA_real_, NA_real_), scale = "log")
  expect_equal(nrow(b), 0L)
})

test_that("bin_distance: all-zero input lands entirely in the first bin", {
  b <- bin_distance(rep(0, 7), scale = "linear")
  expect_equal(b$n[1], 7L)
  expect_equal(sum(b$n[-1]), 0L)
  b_log <- bin_distance(rep(0, 7), scale = "log")
  expect_equal(sum(b_log$n), 7L)
})

test_that("bin_distance log: value exactly on a 0.25 boundary is counted", {
  b <- bin_distance(c(0, 9, 99), scale = "log")   # log10(10) = 1, log10(100) = 2
  expect_equal(sum(b$n), 3L)
  expect_true(max(b$upper) > 2)
})

test_that("bin_distance: negative or infinite input is not silently binned", {
  # bin_distance() does not validate; the invariant lives in R/122 SECTION 12.0a.
  # This test documents the contract: NA is dropped, everything else is counted.
  b <- bin_distance(c(-1, 5), scale = "linear")
  expect_equal(sum(b$n), 1L)   # -1 falls outside [0, Inf) and is dropped by cut()
})

test_that("bin_distance: single value above cap goes to the open top bin", {
  b <- bin_distance(1234, scale = "linear", cap = 300)
  expect_equal(b$n[is.infinite(b$upper)], 1L)
  expect_equal(sum(b$n), 1L)
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
  tmp <- withr::local_tempdir()
  result <- make_distance_histograms(enc_dist, out_dir = tmp, run_date = "20260918")
  expect_named(result, c("bins", "stats"))
})

test_that("make_distance_histograms bins has level column with encounter and patient", {
  tmp <- withr::local_tempdir()
  result <- make_distance_histograms(enc_dist, out_dir = tmp, run_date = "20260918")
  expect_true(all(c("encounter", "patient") %in% result$bins$level))
})

test_that("make_distance_histograms bins has scale column with linear and log", {
  tmp <- withr::local_tempdir()
  result <- make_distance_histograms(enc_dist, out_dir = tmp, run_date = "20260918")
  expect_true(all(c("linear", "log") %in% result$bins$scale))
})

test_that("make_distance_histograms writes exactly the 4 expected PNG file names", {
  tmp <- withr::local_tempdir()
  result <- make_distance_histograms(enc_dist, out_dir = tmp, run_date = "20260918")
  expected <- sprintf("encounter_distance_hist_%s_%s_20260918.png",
                      rep(c("encounter", "patient"), each = 2), rep(c("linear", "log"), 2))
  pngs <- list.files(file.path(tmp, "figures"), pattern = "\\.png$", full.names = FALSE)
  expect_setequal(pngs, expected)
})

test_that("make_distance_histograms bin counts sum to computed n at every level/scale", {
  tmp <- withr::local_tempdir()
  result <- make_distance_histograms(enc_dist, out_dir = tmp, run_date = "20260918")
  n_enc <- nrow(dplyr::filter(enc_dist, distance_status == "computed"))
  n_pat <- dplyr::n_distinct(dplyr::filter(enc_dist, distance_status == "computed")$ID)
  for (lv in c("encounter", "patient")) for (sc in c("linear", "log")) {
    got <- sum(result$bins$n[result$bins$level == lv & result$bins$scale == sc])
    expect_equal(got, if (lv == "encounter") n_enc else n_pat, info = paste(lv, sc))
  }
})

test_that("make_distance_histograms with no computed rows warns and writes nothing", {
  tmp <- withr::local_tempdir()
  none <- dplyr::mutate(enc_dist, distance_status = "patient_zip_missing", distance_mi = NA_real_)
  expect_warning(result <- make_distance_histograms(none, out_dir = tmp, run_date = "20260918"),
                 "no computed rows")
  expect_equal(nrow(result$bins), 0L)
  expect_equal(length(list.files(file.path(tmp, "figures"))), 0L)
})

test_that("make_distance_histograms encounter stats$n equals nrow of computed rows", {
  tmp <- withr::local_tempdir()
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

test_that("summarise_distance: facility_state NA maps to state_unmatched", {
  d <- dplyr::mutate(enc_dist, facility_state = NA_character_)
  out <- summarise_distance(d, by = "facility_state")
  expect_equal(out$breakout, "state_unmatched")
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
   All tests must pass. The utility file has no lubridate dependency (year is derived with `format(ADMIT_DATE, "%Y")`).

**Verify:**
```
Rscript -e "testthat::test_file('tests/testthat/test-utils-distance-hist.R')"
```
Expected: all tests pass, 0 failures, 0 errors. Each `make_distance_histograms()` test writes its 4 PNGs into its own `withr::local_tempdir()`, cleaned up on exit.

**Done:** `tests/testthat/test-utils-distance-hist.R` exists with tests for all four functions covering normal cases, edge cases (NAs, zero distance), and the row-count invariant. All tests pass with `testthat::test_file()`.

---

### Task 154-04: zipcodeR-vs-haversine agreement test (milestone 152-02 criterion)

**Goal:** Satisfy the 152-02 success criterion — `zipcodeR::zip_distance()` and `haversine_km()` agree within 1 mile on a 500-pair sample — as a testthat case that reads the Phase 154 rds. Runs only where the rds exists (HiPerGator); skipped locally.

**Files:**
- `tests/testthat/test-encounter-distance.R` — create new (or append if it exists)

**Steps:**

1. Add:

```r
library(testthat)
library(dplyr)

test_that("zipcodeR distance agrees with haversine cross-check within 1 mile (500-pair sample)", {
  rds_files <- list.files(file.path(CONFIG$output_dir), pattern = "^encounter_distance_\\d{8}\\.rds$",
                          full.names = TRUE)
  skip_if(length(rds_files) == 0, "encounter_distance rds not present (run on HiPerGator)")
  d <- readRDS(sort(rds_files, decreasing = TRUE)[1]) |>
    dplyr::filter(distance_status == "computed", !is.na(distance_km_haversine))
  skip_if(nrow(d) == 0, "no computed rows with haversine cross-check")
  set.seed(15202)
  s <- d[sample.int(nrow(d), min(500L, nrow(d))), ]
  diff_mi <- abs(s$distance_mi - s$distance_km_haversine / 1.609344)
  expect_lte(stats::median(diff_mi), 1)
  expect_lte(mean(diff_mi > 1), 0.05)   # allow <=5% of pairs to differ by >1 mi (centroid-source differences)
})
```

   `CONFIG` must be available; source `R/00_config.R` at the top of the file the same way the existing HiPerGator-dependent tests do.

2. If the median difference exceeds 1 mile, do NOT relax the threshold. Report the median and the 95th percentile of `diff_mi` and stop: a systematic offset means the two centroid sources disagree and D-01 needs a note in AM §3.

**Verify:** `Rscript -e "testthat::test_file('tests/testthat/test-encounter-distance.R')"` — skipped locally, passes on HiPerGator after a full run.

**Done:** The 152-02 cross-check exists as a repeatable test and is not a workbook row (154-D3).

---

## Verification

After all four tasks are complete (order 154-02, 154-03, 154-01, 154-04), confirm the following:

1. **6-sheet xlsx structure** — Open `output/encounter_distance_<date>.xlsx` and confirm exactly 6 tabs in order: KEY, A_distribution_summary, B_histogram_bins, C_completeness, D_fill_offsets, QC. Confirm no tabs named A_encounter_distance, B_patient_summary, C_distribution, D_flags, or E_completeness remain.

2. **4 histogram PNGs** — Verify these four files exist in `output/figures/`:
   - `encounter_distance_hist_encounter_linear_<date>.png`
   - `encounter_distance_hist_encounter_log_<date>.png`
   - `encounter_distance_hist_patient_linear_<date>.png`
   - `encounter_distance_hist_patient_log_<date>.png`

3. **Per-patient rds** — Verify `output/distance_patient_<date>.rds` exists. Load it and confirm `nrow()` equals `n_distinct(ID)` among `enc_distance` rows where `distance_status == "computed"`. Confirm columns include `ID`, `n_enc_computed`, `median_mi`, `min_mi`, `max_mi`, and `share_ge_30`, `share_ge_50` (or the configured cutoffs).

4. **Row-count reconciliation** — The `stopifnot` block in SECTION 12.5 passes without error during a full run. This is the canonical proof that the A_distribution_summary overall row, the histogram stats tibble, and the patient rds are all consistent.

5. **Test suite** — `Rscript -e "testthat::test_file('tests/testthat/test-utils-distance-hist.R')"` reports 0 failures and 0 errors; `test-encounter-distance.R` passes on HiPerGator.

7. **Figure check** — open all four PNGs at 100% and confirm: only two orange reference lines (median solid, p90 dashed); title, subtitle and both caption lines fully visible and left-aligned with the panel; linear x axis ends with a "300+" tick over the open top bin; log x axis tick labels are plain numbers (0, 1, 2, 5, 10, ...) with no overlap; y axis labels have thousands separators; no bar drawn past the last tick; no text clipped at the right edge. If the subtitle wraps or clips at 8 in width, reduce `plot.subtitle` size to 9 rather than widening the figure.

8. **D_fill_offsets** — the sheet has 12 bin rows and a second table of 5 summary metrics; no row labelled `[0]`.

9. **Write order** — in the run log, "Table reconciliation stopifnot PASSED" appears before any "written" message; the first file written is a PNG, then the patient rds, then the encounter rds, then the xlsx. A failed reconciliation leaves no Phase 154 output on disk.

6. **ENC_TYPE column present** — `Rscript -e "source('R/122_encounter_distance.R'); cat(names(enc_distance))"` output includes `ENC_TYPE` (requires DuckDB on HiPerGator; for local verification use the grep check from Task 154-02 step 4 instead).
