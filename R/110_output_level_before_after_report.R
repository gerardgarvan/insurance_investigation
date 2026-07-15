# ==============================================================================
# 110_output_level_before_after_report.R -- Phase 124 Output-Level Before/After
#   Comparison Report + Unmapped Drug-Name Audit
# ==============================================================================
# Purpose:     READ-ONLY post-integration proof artifact for Phase 124. Proves
#              that the Phase 122 chemo-detection fix propagated to the FINAL
#              PRODUCTS (output-level), not just source counts. Mirrors the
#              R/109 / R/51 pattern.
#
#              Phase 123 quantified SOURCE-level impact (+1,328 patients /
#              +13,762 dates). This report proves the wired consumers actually
#              changed the FINAL PRODUCTS: treatment episode counts, patients
#              with any chemo episode, first-line regimen distribution, first-
#              chemo timing shifts, and payer-anchor windows (D-02).
#
#              Covers:
#                D-02: Output-level before/after diff across treatment episodes,
#                      chemo patients, regimen distribution, timing, payer.
#                D-03: Baseline = committed pre-Phase-122 gantt CSV +
#                      treatment_episodes_pre_p124.rds (HiPerGator Plan 04
#                      snapshot). After = regenerated runtime artifacts.
#                D-08: Unmapped Names audit — raw/cleaned drug names with no
#                      canonical mapping in MEDICATION_LOOKUP/DRUG_NAME_ALIASES.
#                D-09: Regimen-label distribution (silent aggregate).
#                D-15: All patient counts 1-10 HIPAA-suppressed via
#                      suppress_small().
#
# Inputs:      cache/outputs/treatment_episodes.rds            (AFTER)
#              cache/outputs/treatment_episodes_pre_p124.rds   (BEFORE, HiPerGator)
#              output/gantt_episodes.csv                       (AFTER regeneration)
#              output/gantt_episodes_pre_p124.csv              (BEFORE; Plan 04 copy)
#              R/00_config.R (MEDICATION_LOOKUP, DRUG_NAME_ALIASES,
#                canonicalize_drug_name, CONFIG$output_dir, IS_LOCAL)
#
# Outputs:     output/output_level_before_after_report.xlsx
#
# Dependencies: R/00_config.R (auto-sources utils_duckdb, utils_treatment)
#               tidyverse: dplyr, glue, stringr, lubridate
#               openxlsx2, here
#
# Requirements: D-02, D-03, D-08, D-09, D-15 (Phase 124 Plan 03)
#
# Usage:       Rscript R/110_output_level_before_after_report.R
#              source("R/110_output_level_before_after_report.R")
#
# Note:        READ-ONLY output-level report. Structural-only verification on
#              Windows (no Rscript; cache/outputs is empty locally). Full run
#              with counts is HiPerGator ONLY (Plan 04). This script must NOT
#              touch R/26, R/00_config, treatment_episodes.rds, or any cohort/
#              episode source file.
#
# REGISTRATION NOTE: This is a ONE-OFF output-level proof artifact — NOT wired
#              into R/39 and NOT a repeatable investigation. SCRIPT_INDEX-only
#              registration (mirrors R/107, R/108, R/109). R/88 Section 15v
#              confirms structure (SMOKE-124-01).
# ==============================================================================


# ==============================================================================
# SECTION 1: SETUP AND LIBRARIES ----
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(glue)
  library(stringr)
  library(lubridate)
  library(openxlsx2)
  library(here)
})

source("R/00_config.R")

message("=== Phase 124: Output-Level Before/After Report + Unmapped-Name Audit (D-02/D-08) ===\n")


# ==============================================================================
# SECTION 2: CONSTANTS AND HIPAA HELPER ----
# ==============================================================================

# Paths: BEFORE baselines (pre-Phase-122) and AFTER regenerated artifacts.
# Plan 04 on HiPerGator:
#   - copies treatment_episodes.rds -> treatment_episodes_pre_p124.rds BEFORE R/26 runs
#   - copies output/gantt_episodes.csv -> output/gantt_episodes_pre_p124.csv BEFORE R/52 runs
# Use CONFIG$cache$outputs_dir (matches R/26/R/28/R/52) — on HiPerGator this is an
# absolute path OUTSIDE the project tree (/blue/.../clean/rds/outputs), NOT here("cache").
EPISODES_AFTER  <- file.path(CONFIG$cache$outputs_dir, "treatment_episodes.rds")
EPISODES_BEFORE <- file.path(CONFIG$cache$outputs_dir, "treatment_episodes_pre_p124.rds")
GANTT_AFTER     <- here::here("output", "gantt_episodes.csv")
GANTT_BEFORE    <- here::here("output", "gantt_episodes_pre_p124.csv")
OUT_XLSX        <- here::here("output", "output_level_before_after_report.xlsx")

message(glue("Episodes AFTER:  {EPISODES_AFTER}"))
message(glue("Episodes BEFORE: {EPISODES_BEFORE}"))
message(glue("Gantt AFTER:     {GANTT_AFTER}"))
message(glue("Gantt BEFORE:    {GANTT_BEFORE}"))
message(glue("Output xlsx:     {OUT_XLSX}\n"))

# HIPAA helper: patient counts 1-10 are suppressed in any persisted/printed
# per-group breakdown to prevent re-identification. Applies to all n_patients
# fields in all output sheets and console lines.
# Copied VERBATIM from R/109 (line 111).
suppress_small <- function(n) {
  # Vectorized: works on both scalar counts (n_distinct(...)) and whole columns
  # (across(...)). Uses & / ifelse (vectorized) rather than && (scalar-only) so a
  # length > 1 input never triggers "'length = N' in coercion to 'logical(1)'".
  n <- as.integer(n)
  ifelse(!is.na(n) & n >= 1L & n <= 10L, NA_integer_, n)
}


# ==============================================================================
# SECTION 3: LOAD ARTIFACTS ----
# ==============================================================================

# ---------------------------------------------------------------------------
# 3a: Load AFTER episode RDS (regenerated by R/26+R/28+R/29 in Plan 04).
# Guard with file.exists() so script PARSES on Windows where cache/outputs
# is empty locally. (IS_LOCAL check pattern from R/109.)
# ---------------------------------------------------------------------------
message("--- Section 3a: Load AFTER treatment_episodes.rds ---")

episodes_after <- NULL
if (file.exists(EPISODES_AFTER)) {
  episodes_after <- readRDS(EPISODES_AFTER)
  message(glue("  AFTER episodes loaded: {format(nrow(episodes_after), big.mark = ',')} rows"))
} else {
  message(glue("  [SKIP] {EPISODES_AFTER} not found (HiPerGator runtime required)"))
}

# ---------------------------------------------------------------------------
# 3b: Load BEFORE episode RDS (snapshotted by Plan 04 BEFORE R/26 runs).
# This is the pre-Phase-122 baseline for episode-level metrics.
# ---------------------------------------------------------------------------
message("--- Section 3b: Load BEFORE treatment_episodes_pre_p124.rds ---")

episodes_before <- NULL
if (file.exists(EPISODES_BEFORE)) {
  episodes_before <- readRDS(EPISODES_BEFORE)
  message(glue("  BEFORE episodes loaded: {format(nrow(episodes_before), big.mark = ',')} rows"))
} else {
  message(glue("  [SKIP] {EPISODES_BEFORE} not found (HiPerGator Plan 04 snapshot required)"))
}

# ---------------------------------------------------------------------------
# 3c: Load BEFORE gantt CSV (pre-Phase-122; committed CSV predates fix).
# Read defensively: all columns as character, pick columns via any_of().
# ---------------------------------------------------------------------------
message("--- Section 3c: Load BEFORE gantt_episodes_pre_p124.csv ---")

gantt_before <- NULL
if (file.exists(GANTT_BEFORE)) {
  gantt_before <- read.csv(GANTT_BEFORE, colClasses = "character", stringsAsFactors = FALSE)
  message(glue("  BEFORE gantt loaded: {format(nrow(gantt_before), big.mark = ',')} rows"))
} else {
  message(glue("  [SKIP] {GANTT_BEFORE} not found (HiPerGator Plan 04 snapshot required)"))
}

# ---------------------------------------------------------------------------
# 3d: Load AFTER gantt CSV (regenerated by R/52 in Plan 04).
# ---------------------------------------------------------------------------
message("--- Section 3d: Load AFTER gantt_episodes.csv ---")

gantt_after <- NULL
if (file.exists(GANTT_AFTER)) {
  gantt_after <- read.csv(GANTT_AFTER, colClasses = "character", stringsAsFactors = FALSE)
  message(glue("  AFTER gantt loaded: {format(nrow(gantt_after), big.mark = ',')} rows"))
} else {
  message(glue("  [SKIP] {GANTT_AFTER} not found (HiPerGator runtime required)"))
}


# ==============================================================================
# SECTION 4: SHEET 1 — SUMMARY (D-02 headline before/after) ----
# ==============================================================================

message("\n--- Section 4: Sheet 1 — Summary (D-02 headline before/after) ---")

# ---------------------------------------------------------------------------
# Helper: compute episode-level summary metrics from an episodes data frame.
# Handles absent columns gracefully via any_of().
# ---------------------------------------------------------------------------
compute_episode_summary <- function(df, label) {
  if (is.null(df)) {
    return(tibble::tibble(
      metric = c(
        "Total treatment episodes",
        "Total chemo episodes",
        "Patients with any chemo episode",
        "Patients with DISPENSING-sourced chemo episode",
        "Patients with MED_ADMIN-sourced chemo episode"
      ),
      !!label := NA_integer_
    ))
  }

  # Determine episode-grain patient-id column (may be patient_id or PATID)
  pid_col <- if ("patient_id" %in% names(df)) "patient_id" else if ("PATID" %in% names(df)) "PATID" else NULL

  # treatment_type column for chemo filter
  tt_col  <- if ("treatment_type" %in% names(df)) "treatment_type" else NULL
  # source_table column for source-specific counts
  src_col <- if ("source_table" %in% names(df)) "source_table" else NULL

  total_episodes <- nrow(df)

  chemo_df <- if (!is.null(tt_col)) {
    df |> dplyr::filter(stringr::str_detect(.data[[tt_col]], regex("Chemo|chemo", ignore_case = TRUE)))
  } else {
    df
  }

  total_chemo_episodes <- nrow(chemo_df)

  pts_any_chemo <- if (!is.null(pid_col)) {
    suppress_small(dplyr::n_distinct(chemo_df[[pid_col]]))
  } else {
    NA_integer_
  }

  pts_dispensing <- if (!is.null(pid_col) && !is.null(src_col)) {
    d_chemo <- chemo_df |>
      dplyr::filter(stringr::str_detect(.data[[src_col]], "DISPENSING"))
    suppress_small(dplyr::n_distinct(d_chemo[[pid_col]]))
  } else {
    NA_integer_
  }

  pts_med_admin <- if (!is.null(pid_col) && !is.null(src_col)) {
    m_chemo <- chemo_df |>
      dplyr::filter(stringr::str_detect(.data[[src_col]], "MED_ADMIN"))
    suppress_small(dplyr::n_distinct(m_chemo[[pid_col]]))
  } else {
    NA_integer_
  }

  tibble::tibble(
    metric = c(
      "Total treatment episodes",
      "Total chemo episodes",
      "Patients with any chemo episode",
      "Patients with DISPENSING-sourced chemo episode",
      "Patients with MED_ADMIN-sourced chemo episode"
    ),
    !!label := c(
      total_episodes,
      total_chemo_episodes,
      pts_any_chemo,
      pts_dispensing,
      pts_med_admin
    )
  )
}

summary_before <- compute_episode_summary(episodes_before, "before")
summary_after  <- compute_episode_summary(episodes_after, "after")

df_summary <- dplyr::left_join(summary_before, summary_after, by = "metric") |>
  dplyr::mutate(
    delta = dplyr::case_when(
      !is.na(before) & !is.na(after) ~ after - before,
      TRUE ~ NA_integer_
    )
  )

message(glue("  Summary sheet: {nrow(df_summary)} rows"))


# ==============================================================================
# SECTION 5: SHEET 2 — REGIMEN DISTRIBUTION (D-02, D-09) ----
# ==============================================================================

message("\n--- Section 5: Sheet 2 — Regimen Distribution (D-02, D-09) ---")

# ---------------------------------------------------------------------------
# Helper: regimen distribution from episode RDS (first-line chemo or all chemo).
# Uses any_of() to handle absent columns gracefully.
# ---------------------------------------------------------------------------
compute_regimen_dist <- function(df, label) {
  if (is.null(df)) {
    return(tibble::tibble(regimen_label = character(0), !!label := integer(0)))
  }

  # Filter to chemo episodes
  tt_col     <- if ("treatment_type" %in% names(df)) "treatment_type" else NULL
  line_col   <- if ("is_first_line" %in% names(df)) "is_first_line" else NULL
  regimen_col <- if ("regimen_label" %in% names(df)) "regimen_label" else NULL

  if (is.null(regimen_col)) {
    return(tibble::tibble(regimen_label = "(column absent)", !!label := NA_integer_))
  }

  chemo_df <- if (!is.null(tt_col)) {
    df |> dplyr::filter(stringr::str_detect(.data[[tt_col]], regex("Chemo|chemo", ignore_case = TRUE)))
  } else {
    df
  }

  # Prefer first-line if available; fall back to all chemo
  if (!is.null(line_col)) {
    fl_df <- chemo_df |> dplyr::filter(.data[[line_col]] == TRUE)
    if (nrow(fl_df) > 0) chemo_df <- fl_df
  }

  chemo_df |>
    dplyr::group_by(regimen_label = .data[[regimen_col]]) |>
    dplyr::summarise(!!label := dplyr::n(), .groups = "drop") |>
    dplyr::arrange(dplyr::desc(.data[[label]]))
}

regimen_before <- compute_regimen_dist(episodes_before, "n_before")
regimen_after  <- compute_regimen_dist(episodes_after, "n_after")

df_regimen <- dplyr::full_join(regimen_before, regimen_after, by = "regimen_label") |>
  dplyr::mutate(
    delta = dplyr::case_when(
      !is.na(n_before) & !is.na(n_after) ~ n_after - n_before,
      TRUE ~ NA_integer_
    )
  ) |>
  dplyr::arrange(dplyr::desc(dplyr::coalesce(n_after, n_before)))

message(glue("  Regimen distribution sheet: {nrow(df_regimen)} rows"))


# ==============================================================================
# SECTION 6: SHEET 3 — FIRST-CHEMO TIMING SHIFT ----
# ==============================================================================

message("\n--- Section 6: Sheet 3 — First-Chemo Timing Shift ---")

# ---------------------------------------------------------------------------
# Per-patient earliest chemo episode_start before vs after.
# Positive delta_days_earlier = patient gained an earlier first-chemo date.
# ---------------------------------------------------------------------------
compute_first_chemo <- function(df, id_label) {
  if (is.null(df)) return(NULL)

  pid_col   <- if ("patient_id" %in% names(df)) "patient_id" else if ("PATID" %in% names(df)) "PATID" else NULL
  tt_col    <- if ("treatment_type" %in% names(df)) "treatment_type" else NULL
  start_col <- if ("episode_start" %in% names(df)) "episode_start" else NULL

  if (is.null(pid_col) || is.null(start_col)) return(NULL)

  chemo_df <- if (!is.null(tt_col)) {
    df |> dplyr::filter(stringr::str_detect(.data[[tt_col]], regex("Chemo|chemo", ignore_case = TRUE)))
  } else {
    df
  }

  chemo_df |>
    dplyr::mutate(
      episode_start_date = lubridate::ymd(.data[[start_col]])
    ) |>
    dplyr::group_by(patient_id_key = .data[[pid_col]]) |>
    dplyr::summarise(
      first_chemo := min(episode_start_date, na.rm = TRUE),
      .groups = "drop"
    ) |>
    dplyr::rename(!!id_label := patient_id_key)
}

fc_before <- compute_first_chemo(episodes_before, "patient_id")
fc_after  <- compute_first_chemo(episodes_after, "patient_id")

df_timing <- if (!is.null(fc_before) && !is.null(fc_after)) {
  dplyr::inner_join(fc_before, fc_after, by = "patient_id", suffix = c("_before", "_after")) |>
    dplyr::mutate(
      delta_days = as.integer(first_chemo_before - first_chemo_after),
      direction = dplyr::case_when(
        delta_days > 0  ~ "Earlier (gained earlier first-chemo date)",
        delta_days == 0 ~ "Same date",
        delta_days < 0  ~ "Later (lost earlier date — unexpected)",
        TRUE            ~ "Unknown"
      )
    )
} else {
  tibble::tibble(
    note = "Data not available on Windows executor — run on HiPerGator after Plan 04 regeneration."
  )
}

# Summarise shift distribution (suppress patient counts 1-10)
if ("direction" %in% names(df_timing)) {
  df_timing_summary <- df_timing |>
    dplyr::group_by(direction) |>
    dplyr::summarise(
      n_patients = suppress_small(dplyr::n()),
      median_days_earlier = median(delta_days[direction == "Earlier (gained earlier first-chemo date)"],
                                   na.rm = TRUE),
      .groups = "drop"
    )
} else {
  df_timing_summary <- df_timing
}

message(glue("  Timing shift sheet: {nrow(df_timing_summary)} rows"))


# ==============================================================================
# SECTION 7: SHEET 4 — PAYER-ANCHOR WINDOW ----
# ==============================================================================

message("\n--- Section 7: Sheet 4 — Payer-Anchor Window ---")

# ---------------------------------------------------------------------------
# Payer-at-chemo artifact from R/11/R/14 output (treatment-anchored payer mode).
# Guard with file.exists(); emit documented placeholder if absent at report time.
# The payer-anchor numbers can be filled from R/11 output on HiPerGator.
# ---------------------------------------------------------------------------
PAYER_CHEMO_CSV <- here::here("output", "payer_at_chemo.csv")

df_payer <- NULL
if (file.exists(PAYER_CHEMO_CSV)) {
  payer_raw <- read.csv(PAYER_CHEMO_CSV, colClasses = "character", stringsAsFactors = FALSE)
  message(glue("  Payer-at-chemo CSV loaded: {format(nrow(payer_raw), big.mark = ',')} rows"))

  # Summarise payer distribution from available columns (any_of guard)
  payer_col <- intersect(c("payer_category", "payer_mode", "payer_type"), names(payer_raw))
  if (length(payer_col) > 0) {
    df_payer <- payer_raw |>
      dplyr::group_by(payer = .data[[payer_col[1]]]) |>
      dplyr::summarise(
        n_patients = suppress_small(dplyr::n_distinct(.data[["patient_id"]] %||% .data[[names(payer_raw)[1]]])),
        .groups = "drop"
      ) |>
      dplyr::mutate(
        note = "After regeneration (treatment_episodes includes MED_ADMIN/DISPENSING sources)"
      )
  }
}

if (is.null(df_payer)) {
  df_payer <- tibble::tibble(
    payer = c("(placeholder)"),
    n_patients = NA_integer_,
    note = paste0(
      "Payer-anchor artifact (output/payer_at_chemo.csv) not available at report time. ",
      "Run R/11 on HiPerGator after Plan 04 regeneration to populate this sheet. ",
      "The treatment-anchored payer window changes are documented in Phase 124 D-02 context."
    )
  )
  message("  [PLACEHOLDER] payer_at_chemo.csv not found; placeholder row emitted.")
}

message(glue("  Payer-anchor sheet: {nrow(df_payer)} rows"))


# ==============================================================================
# SECTION 8: SHEET 5 — UNMAPPED NAMES AUDIT (D-08) ----
# ==============================================================================

message("\n--- Section 8: Sheet 5 — Unmapped Names Audit (D-08) ---")

# ---------------------------------------------------------------------------
# Collect drug-name strings from EPISODES_AFTER that are UNMAPPED:
#   cleaned = toupper(trimws(x))
#   unmapped if canonicalize_drug_name(x) returns x unchanged AND
#             cleaned is not among unname(MEDICATION_LOOKUP) canonical values.
# Uses treatment_episode_detail.rds if present (per-code grain); falls back
# to treatment_episodes.rds drug_names field (multi-value string, split on ";").
# Columns: code | raw_name | cleaned_name_in_output | source_table | n_episodes | n_patients
# Model layout on R/79. SME review list — do NOT resolve names here (D-08).
# ---------------------------------------------------------------------------

DETAIL_RDS <- file.path(CONFIG$cache$outputs_dir, "treatment_episode_detail.rds")

df_unmapped <- NULL

# Try detail RDS first (per-code grain preferred)
if (file.exists(DETAIL_RDS)) {
  detail_raw <- readRDS(DETAIL_RDS)
  message(glue("  Detail RDS loaded: {format(nrow(detail_raw), big.mark = ',')} rows"))

  # Identify available columns via any_of
  code_col     <- intersect(c("triggering_code", "code"), names(detail_raw))
  name_col     <- intersect(c("drug_name", "drug_names"), names(detail_raw))
  src_col      <- intersect(c("source_table"), names(detail_raw))
  pid_col      <- intersect(c("patient_id", "PATID"), names(detail_raw))
  ep_col       <- intersect(c("episode_number"), names(detail_raw))

  if (length(name_col) > 0) {
    canonical_values <- toupper(trimws(unname(MEDICATION_LOOKUP)))

    df_unmapped <- detail_raw |>
      dplyr::filter(!is.na(.data[[name_col[1]]]) & nchar(.data[[name_col[1]]]) > 0) |>
      dplyr::mutate(
        raw_name            = .data[[name_col[1]]],
        cleaned_name_in_output = canonicalize_drug_name(raw_name),
        is_canonical_hit    = toupper(trimws(cleaned_name_in_output)) %in% canonical_values,
        is_unchanged        = cleaned_name_in_output == raw_name,
        is_unmapped         = is_unchanged & !is_canonical_hit
      ) |>
      dplyr::filter(is_unmapped) |>
      dplyr::group_by(
        code               = if (length(code_col) > 0) .data[[code_col[1]]] else NA_character_,
        raw_name,
        cleaned_name_in_output,
        source_table       = if (length(src_col) > 0) .data[[src_col[1]]] else NA_character_
      ) |>
      dplyr::summarise(
        n_episodes = dplyr::n(),
        n_patients = suppress_small(if (length(pid_col) > 0) dplyr::n_distinct(.data[[pid_col[1]]]) else NA_integer_),
        .groups = "drop"
      ) |>
      dplyr::arrange(dplyr::desc(n_episodes))
  }
}

# Fallback: split drug_names from episodes_after
if (is.null(df_unmapped) && !is.null(episodes_after)) {
  name_col <- intersect(c("drug_names", "drug_name"), names(episodes_after))
  pid_col  <- intersect(c("patient_id", "PATID"), names(episodes_after))
  src_col  <- intersect(c("source_table"), names(episodes_after))

  if (length(name_col) > 0) {
    canonical_values <- toupper(trimws(unname(MEDICATION_LOOKUP)))

    split_df <- episodes_after |>
      dplyr::select(
        dplyr::any_of(c("patient_id", "PATID", "source_table", "episode_number")),
        drug_names_raw = dplyr::all_of(name_col[1])
      ) |>
      dplyr::filter(!is.na(drug_names_raw) & nchar(drug_names_raw) > 0) |>
      tidyr::separate_rows(drug_names_raw, sep = ";") |>
      dplyr::mutate(drug_names_raw = stringr::str_trim(drug_names_raw)) |>
      dplyr::filter(nchar(drug_names_raw) > 0)

    canonical_values_check <- toupper(trimws(unname(MEDICATION_LOOKUP)))

    df_unmapped <- split_df |>
      dplyr::mutate(
        raw_name               = drug_names_raw,
        cleaned_name_in_output = canonicalize_drug_name(raw_name),
        is_canonical_hit       = toupper(trimws(cleaned_name_in_output)) %in% canonical_values_check,
        is_unchanged           = cleaned_name_in_output == raw_name,
        is_unmapped            = is_unchanged & !is_canonical_hit
      ) |>
      dplyr::filter(is_unmapped) |>
      dplyr::group_by(
        code               = NA_character_,
        raw_name,
        cleaned_name_in_output,
        source_table       = if (length(src_col) > 0) .data[[src_col[1]]] else NA_character_
      ) |>
      dplyr::summarise(
        n_episodes = dplyr::n(),
        n_patients = suppress_small(
          if ("patient_id" %in% names(.)) dplyr::n_distinct(patient_id)
          else if ("PATID" %in% names(.)) dplyr::n_distinct(PATID)
          else NA_integer_
        ),
        .groups = "drop"
      ) |>
      dplyr::arrange(dplyr::desc(n_episodes))
  }
}

if (is.null(df_unmapped)) {
  df_unmapped <- tibble::tibble(
    code                   = character(0),
    raw_name               = character(0),
    cleaned_name_in_output = character(0),
    source_table           = character(0),
    n_episodes             = integer(0),
    n_patients             = integer(0)
  )
  message("  [SKIP] No episode detail available for unmapped-name audit (HiPerGator required).")
} else {
  message(glue("  Unmapped names found: {nrow(df_unmapped)} distinct name/source combos"))
}


# ==============================================================================
# SECTION 9: STYLED XLSX ASSEMBLY ----
# ==============================================================================

message("\n--- Section 9: Styled xlsx assembly ---")

# ---------------------------------------------------------------------------
# DRY helper: add a styled sheet.
# Copied VERBATIM from R/109 (lines 717-746):
#   Header fill FF374151, white font FFFFFFFF, Calibri 11 bold, data at row 4,
#   freeze at row 5. Title Calibri 16 bold FF1F2937, subtitle Calibri 10 gray.
# ---------------------------------------------------------------------------
add_styled_sheet <- function(wb, sheet_name, title, subtitle_text, data) {
  ncols <- max(ncol(data), 1L)
  last_col <- if (ncols <= 26L) LETTERS[ncols] else paste0("A", LETTERS[ncols - 26L])

  # Title row (row 1)
  wb$add_data(sheet = sheet_name, x = title, start_row = 1, start_col = 1)
  wb$add_font(sheet = sheet_name, dims = "A1",
              name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937"))
  wb$merge_cells(sheet = sheet_name, dims = glue("A1:{last_col}1"))

  # Subtitle row (row 2)
  wb$add_data(sheet = sheet_name, x = subtitle_text, start_row = 2, start_col = 1)
  wb$add_font(sheet = sheet_name, dims = "A2",
              name = "Calibri", size = 10, color = wb_color("FF6B7280"))
  wb$merge_cells(sheet = sheet_name, dims = glue("A2:{last_col}2"))

  # Data table at row 4
  wb$add_data(sheet = sheet_name, x = data, start_row = 4, start_col = 1)

  # Header row styling (row 4): dark gray fill + white bold font
  wb$add_fill(sheet = sheet_name, dims = glue("A4:{last_col}4"),
              color = wb_color("FF374151"))
  wb$add_font(sheet = sheet_name, dims = glue("A4:{last_col}4"),
              name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))

  # Freeze pane below header
  wb$freeze_pane(sheet = sheet_name, firstActiveRow = 5)

  wb
}

run_date <- format(Sys.Date(), "%Y-%m-%d")

# ---------------------------------------------------------------------------
# Workbook creation
# ---------------------------------------------------------------------------
wb <- wb_workbook()

# Sheet 1: Summary (D-02 headline before/after)
wb$add_worksheet("Summary")
wb <- add_styled_sheet(
  wb,
  sheet_name    = "Summary",
  title         = "Phase 124 Output-Level Before/After: Treatment Episodes & Chemo Patients (D-02)",
  subtitle_text = glue("Generated: {run_date} | BEFORE = pre-Phase-122 RDS snapshot; AFTER = regenerated artifacts; n_patients HIPAA-suppressed"),
  data          = df_summary
)

# Sheet 2: Regimen Distribution (D-02, D-09)
wb$add_worksheet("Regimen Distribution")
wb <- add_styled_sheet(
  wb,
  sheet_name    = "Regimen Distribution",
  title         = "First-Line Regimen Distribution Before vs After Phase 122 Fix (D-02/D-09)",
  subtitle_text = glue("Generated: {run_date} | First-line chemo episodes (is_first_line==TRUE if available, else all chemo); regimen_label from treatment_episodes.rds"),
  data          = df_regimen
)

# Sheet 3: First-Chemo Timing Shift
wb$add_worksheet("First-Chemo Timing Shift")
wb <- add_styled_sheet(
  wb,
  sheet_name    = "First-Chemo Timing Shift",
  title         = "Per-Patient First-Chemo Timing Shift: Before vs After Phase 122 Fix",
  subtitle_text = glue("Generated: {run_date} | delta_days_earlier > 0 = gained earlier date; n_patients HIPAA-suppressed (D-15)"),
  data          = df_timing_summary
)

# Sheet 4: Payer-Anchor Window
wb$add_worksheet("Payer-Anchor Window")
wb <- add_styled_sheet(
  wb,
  sheet_name    = "Payer-Anchor Window",
  title         = "Treatment-Anchored Payer Window: Before vs After Phase 122 Fix",
  subtitle_text = glue("Generated: {run_date} | Source: output/payer_at_chemo.csv from R/11/R/14; n_patients HIPAA-suppressed (D-15)"),
  data          = df_payer
)

# Sheet 5: Unmapped Names (D-08)
wb$add_worksheet("Unmapped Names")
wb <- add_styled_sheet(
  wb,
  sheet_name    = "Unmapped Names",
  title         = "Drug Names with No Canonical Mapping: SME Review List (D-08)",
  subtitle_text = glue("Generated: {run_date} | Unmapped = canonicalize_drug_name(x)==x AND not in MEDICATION_LOOKUP values; n_patients HIPAA-suppressed (D-15)"),
  data          = df_unmapped
)

# ---------------------------------------------------------------------------
# Save workbook — tryCatch so a Windows run (no data) does not hard-fail.
# Runtime write is verified on HiPerGator (Plan 04).
# ---------------------------------------------------------------------------
tryCatch({
  wb$save(OUT_XLSX)
  message(glue("  Wrote deliverable xlsx: {OUT_XLSX}"))
}, error = function(e) {
  message(glue("  [WARN] Could not write xlsx (expected on Windows with no data): {conditionMessage(e)}"))
})


# ==============================================================================
# SECTION 10: CONSOLE SUMMARY ----
# ==============================================================================

# >= 4 lines prefixed "P124" or "OUTLVL" for parseable Plan 04 runtime confirmation.
message("\n=== P124 OUTPUT LEVEL BEFORE/AFTER REPORT: COMPLETE ===")
message(glue("P124 Summary sheet: {nrow(df_summary)} metric rows (before/after/delta)"))
message(glue("P124 Regimen Distribution sheet: {nrow(df_regimen)} regimen rows"))
message(glue("OUTLVL Timing Shift sheet: {nrow(df_timing_summary)} direction rows"))
message(glue("OUTLVL Payer-Anchor sheet: {nrow(df_payer)} payer rows"))
message(glue("OUTLVL Unmapped Names sheet: {nrow(df_unmapped)} unmapped name/source combos"))
message(glue("P124 Output xlsx: {OUT_XLSX}"))
message(glue("P124 Run date: {run_date}"))
