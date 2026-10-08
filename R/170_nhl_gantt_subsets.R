# R/170_nhl_gantt_subsets.R
# =============================================================================
# Purpose:  Produce NHL-only (Group 1 strict) and HL+NHL (Group 2) filtered
#           views of the pinned 2026-08-14 gantt_episodes_180 snapshot, with
#           chemo-combos columns E-J left-joined onto chemo rows only at the
#           (patient_id, episode_number) grain.  Delivers one workbook
#           (KEY / NHL_only_episodes / HL_NHL_episodes / QC) plus two matching
#           CSVs in output/internal/.
#
# Inputs:   CONFIG$gantt_180_snapshot_path  — pinned 2026-08-14 gantt CSV
#           CONFIG$chemo_combos_path        — team chemo-combos workbook
#           CONFIG$chemo_combos_tab         — sheet name "Chemo and Cancer Dx"
#
# Outputs:  output/internal/nhl_gantt_subsets_<YYYYMMDD>.xlsx
#           output/internal/nhl_only_episodes_<YYYYMMDD>.csv
#           output/internal/hl_nhl_episodes_<YYYYMMDD>.csv
#
# Requirements: NHLSUB-01, NHLSUB-02, NHLSUB-03, NHLSUB-04
# Phase: 168 — nhl-only-and-hl-nhl-gantt-episode-subsets
# Plan:  168-01
# INTERNAL: outputs contain patient IDs — write only to output/internal/
# =============================================================================

source(here::here("R/00_config.R"))
suppressPackageStartupMessages({
  library(dplyr)
  library(glue)
  library(stringr)
  library(readr)
  library(openxlsx)
})
run_date <- format(Sys.Date(), "%Y%m%d")

# =============================================================================
# SECTION 1B — pure helpers (no I/O; sourced before the probe gate so tests
# can sys.source() this file up to the probe gate and exercise all functions)
# =============================================================================

#' Normalise a join key column to a plain character string.
#' Trims whitespace, strips trailing .0+ (for integer-looking numerics read as
#' "1.0"), and converts empty strings to NA.
#' Apply to BOTH sides of every join.
norm_key <- function(x) {
  x <- trimws(as.character(x))
  x <- sub("\\.0+$", "", x)
  x[x == ""] <- NA
  x
}

#' Return TRUE where v is non-NA and (case-insensitively) equal to "x".
classify_x <- function(v) {
  !is.na(v) & tolower(trimws(v)) == "x"
}

#' Return TRUE where v is non-NA, non-blank after trim, and NOT "x"
#' (case-insensitive) — i.e. an unexpected value the team should inspect.
flag_unexpected_x <- function(v) {
  trimmed <- trimws(v)
  !is.na(v) & trimmed != "" & tolower(trimmed) != "x"
}

#' Normalise drug_names for cross-check comparison.
#' lowercase → split on ; or , → trim each token → drop empty → sort → rejoin
#' with ";".  NA input stays NA (vectorised).
normalize_drug_names <- function(s) {
  vapply(s, function(x) {
    if (is.na(x)) return(NA_character_)
    tokens <- unlist(strsplit(x, "\\s*[;,]\\s*"))
    tokens <- trimws(tolower(tokens))
    tokens <- tokens[tokens != ""]
    if (length(tokens) == 0L) return(NA_character_)
    paste(sort(tokens), collapse = ";")
  }, character(1L), USE.NAMES = FALSE)
}

#' Classify patients into Group 1 (strict NHL-only) and Group 2 (HL+NHL)
#' from the chemo-combos sheet.
#'
#' @param sheet data.frame with columns: patient_id, hl (logical), nhl (logical),
#'   hlnhl (logical).
#' @return data.frame with patient_id, group1_strict, group1_loose, group2.
classify_groups <- function(sheet) {
  sheet |>
    dplyr::group_by(patient_id) |>
    dplyr::summarise(
      group1_strict = all(nhl, na.rm = TRUE) & !any(hl, na.rm = TRUE) & !any(hlnhl, na.rm = TRUE),
      group1_loose  = any(nhl, na.rm = TRUE),
      group2        = any(hlnhl, na.rm = TRUE),
      .groups = "drop"
    )
}

#' Left-join E-J chemo-combos columns onto chemo rows only.
#'
#' @param gantt_rows data.frame of gantt rows (already filtered to the group).
#' @param ej         data.frame with patient_id, episode_number, and the 6 E-J
#'                   columns (already key-normalised).
#' @param chemo_value character scalar — value of treatment_type for chemo rows.
#'
#' @return gantt_rows with 6 E-J columns appended; E-J are NA on non-chemo rows.
#'   Row count and order are preserved exactly.
join_ej_chemo_only <- function(gantt_rows, ej, chemo_value) {
  gantt_rows <- gantt_rows |> dplyr::mutate(.row = dplyr::row_number())

  chemo_rows <- gantt_rows |> dplyr::filter(treatment_type == chemo_value)
  other_rows <- gantt_rows |> dplyr::filter(treatment_type != chemo_value)

  ej_cols <- setdiff(names(ej), c("patient_id", "episode_number"))

  chemo_joined <- chemo_rows |>
    dplyr::left_join(ej, by = c("patient_id", "episode_number"))

  # E-J columns as NA for non-chemo rows
  for (col in ej_cols) {
    other_rows[[col]] <- NA_character_
  }

  dplyr::bind_rows(chemo_joined, other_rows) |>
    dplyr::arrange(.row) |>
    dplyr::select(-.row)
}

#' Compare drug_names between the sheet and the gantt (over chemo rows where
#' both have a sheet episode_number matched).
#'
#' @param df data.frame with columns sheet_drug_names, gantt_drug_names.
#' @return list: n_exact, n_norm_only, n_mismatch, n_one_side_missing,
#'   mismatch_rows (patient_id, episode_number, sheet_drug_names, gantt_drug_names).
check_drug_names <- function(df, sheet_col = "sheet_drug_names", gantt_col = "drug_names") {
  both_present <- !is.na(df[[sheet_col]]) & !is.na(df[[gantt_col]])
  one_missing  <- xor(is.na(df[[sheet_col]]), is.na(df[[gantt_col]]))

  s_raw <- df[[sheet_col]][both_present]
  g_raw <- df[[gantt_col]][both_present]
  s_norm <- normalize_drug_names(s_raw)
  g_norm <- normalize_drug_names(g_raw)

  exact_match  <- s_raw == g_raw
  norm_match   <- s_norm == g_norm
  n_exact      <- sum(exact_match,             na.rm = TRUE)
  n_norm_only  <- sum(!exact_match & norm_match, na.rm = TRUE)
  n_mismatch   <- sum(!norm_match,              na.rm = TRUE)

  mismatch_idx <- which(!norm_match)
  mismatch_rows <- if (length(mismatch_idx) > 0L) {
    df[both_present, ][mismatch_idx, c("patient_id", "episode_number", sheet_col, gantt_col)]
  } else {
    data.frame(
      patient_id = character(0), episode_number = character(0),
      sheet_drug_names = character(0), gantt_drug_names = character(0),
      stringsAsFactors = FALSE
    )
  }

  list(
    n_exact             = n_exact,
    n_norm_only         = n_norm_only,
    n_mismatch          = n_mismatch,
    n_one_side_missing  = sum(one_missing),
    mismatch_rows       = mismatch_rows
  )
}

# =============================================================================
# SECTION 1C — Probe gate
# Body runs only when both input files are present (HiPerGator).
# Local runs skip silently with a message.
# =============================================================================

inputs_ok <- !is.null(CONFIG$chemo_combos_path) && file.exists(CONFIG$chemo_combos_path) &&
             !is.null(CONFIG$gantt_180_snapshot_path) && file.exists(CONFIG$gantt_180_snapshot_path)

if (!inputs_ok) {
  message("[R/170] chemo-combos or gantt snapshot absent - skipping (expected on local runs).")
} else {

# =============================================================================
# SECTION 2 — Load and verify inputs
# =============================================================================

message("=== Phase 168: NHL-Only and HL+NHL Gantt Episode Subsets ===\n")

## 2.1 Snapshot identity --------------------------------------------------

gantt_path <- CONFIG$gantt_180_snapshot_path
snap_bytes  <- file.size(gantt_path)
snap_md5    <- unname(tools::md5sum(gantt_path))

message(glue("  Snapshot path : {gantt_path}"))
message(glue("  Snapshot size : {snap_bytes} bytes"))
message(glue("  Snapshot MD5  : {snap_md5}"))

snap_size_ok <- (snap_bytes == CONFIG$gantt_180_snapshot_bytes)
if (!snap_size_ok) {
  warning(glue(
    "[R/170] gantt snapshot is not the 2026-08-14 file: {snap_bytes} bytes vs ",
    "{CONFIG$gantt_180_snapshot_bytes}. Proceeding, but QC will flag this."
  ))
}

snap_md5_ok <- TRUE
if (!is.na(CONFIG$gantt_180_snapshot_md5) && CONFIG$gantt_180_snapshot_md5 != snap_md5) {
  snap_md5_ok <- FALSE
  warning(glue(
    "[R/170] gantt snapshot MD5 mismatch: got {snap_md5}, expected {CONFIG$gantt_180_snapshot_md5}."
  ))
}

## 2.2 Load gantt ----------------------------------------------------------

EXPECTED_GANTT_COLS <- c(
  "patient_id", "treatment_type", "episode_number",
  "episode_start", "episode_stop", "episode_length_days",
  "distinct_dates_in_episode",
  "triggering_codes", "drug_names", "triggering_code_descriptions",
  "cancer_category", "is_hodgkin",
  "drug_group", "code_type", "source_table", "sct_cross_use_flag",
  "episode_dx_codes", "episode_dx_categories",
  "episode_dx_7day_confirmed", "age_at_episode"
)

gantt <- readr::read_csv(
  gantt_path,
  col_types = readr::cols(.default = readr::col_character()),
  show_col_types = FALSE
)
gantt_nrow <- nrow(gantt)
message(glue("  Loaded {format(gantt_nrow, big.mark=',')} gantt rows"))

missing_gantt_cols <- setdiff(EXPECTED_GANTT_COLS, names(gantt))
if (length(missing_gantt_cols) > 0L) {
  stop(glue(
    "[R/170] Missing expected gantt columns: {paste(missing_gantt_cols, collapse=', ')}\n",
    "Actual columns: {paste(names(gantt), collapse=', ')}"
  ))
}

## 2.3 Confirm chemo treatment_type value ----------------------------------

chemo_value <- CONFIG$gantt_chemo_treatment_type
tt_counts <- sort(table(gantt$treatment_type), decreasing = TRUE)

if (is.na(chemo_value) || !(chemo_value %in% names(tt_counts))) {
  stop(glue(
    "[R/170] CONFIG$gantt_chemo_treatment_type ('{chemo_value}') not found in gantt.\n",
    "Distinct treatment_type values and counts:\n",
    paste(names(tt_counts), tt_counts, sep = " = ", collapse = "\n")
  ))
}

n_chemo_rows     <- sum(gantt$treatment_type == chemo_value, na.rm = TRUE)
n_non_chemo_rows <- gantt_nrow - n_chemo_rows
message(glue("  Chemo rows     : {format(n_chemo_rows, big.mark=',')}  (treatment_type == '{chemo_value}')"))
message(glue("  Non-chemo rows : {format(n_non_chemo_rows, big.mark=',')}"))

## 2.4 Normalise gantt keys ------------------------------------------------

gantt <- gantt |>
  dplyr::mutate(
    patient_id     = norm_key(patient_id),
    episode_number = norm_key(episode_number)
  )

## 2.5 Load chemo-combos sheet ---------------------------------------------

EXPECTED_SHEET_COLS <- c(
  "patient_id", "episode_number", "drug_names", "episode_dx_categories",
  "Definitely HL", "Definitely NHL", "Initial", "Relapse", "Notes", "HL and NHL"
)

sheet_raw <- readxl::read_excel(
  CONFIG$chemo_combos_path,
  sheet     = CONFIG$chemo_combos_tab,
  col_types = "text"
)

missing_sheet_cols <- setdiff(EXPECTED_SHEET_COLS, names(sheet_raw))
if (length(missing_sheet_cols) > 0L) {
  stop(glue(
    "[R/170] Missing expected sheet columns: {paste(missing_sheet_cols, collapse=', ')}\n",
    "Actual columns: {paste(names(sheet_raw), collapse=', ')}"
  ))
}

## 2.6 Normalise sheet keys ------------------------------------------------

sheet_raw <- sheet_raw |>
  dplyr::mutate(
    patient_id     = norm_key(patient_id),
    episode_number = norm_key(episode_number)
  )

na_key_sheet_rows <- sheet_raw |>
  dplyr::filter(is.na(patient_id) | is.na(episode_number))
n_na_key_sheet <- nrow(na_key_sheet_rows)
message(glue("  Sheet rows with NA keys (excluded from join): {n_na_key_sheet}"))

sheet_valid <- sheet_raw |>
  dplyr::filter(!is.na(patient_id) & !is.na(episode_number))

## 2.7 Episode-number scope (D-14) ----------------------------------------

# Are (patient_id, episode_number) unique across ALL gantt rows, or only within
# treatment_type?
gantt_all_dupes <- gantt |>
  dplyr::count(patient_id, episode_number) |>
  dplyr::filter(n > 1L)
n_all_scope_dupes <- nrow(gantt_all_dupes)

gantt_chemo_rows <- gantt |> dplyr::filter(treatment_type == chemo_value)
gantt_chemo_dupes <- gantt_chemo_rows |>
  dplyr::count(patient_id, episode_number) |>
  dplyr::filter(n > 1L)

if (nrow(gantt_chemo_dupes) > 0L) {
  stop(glue(
    "[R/170] Duplicate (patient_id, episode_number) keys found among chemo rows: ",
    "{nrow(gantt_chemo_dupes)} pairs duplicated.\n",
    "First few:\n",
    paste(utils::head(gantt_chemo_dupes$patient_id, 5), collapse = ", ")
  ))
}

episode_scope_note <- if (n_all_scope_dupes > 0L) {
  glue("episode_number is scoped WITHIN treatment_type (not unique across all rows; {n_all_scope_dupes} cross-type duplicate pairs)")
} else {
  "episode_number appears UNIQUE across all treatment types"
}
message(glue("  Episode-number scope: {episode_scope_note}"))

## 2.8 Sheet uniqueness and classify HL/NHL/HL-and-NHL columns ------------

sheet_dupes <- sheet_valid |>
  dplyr::count(patient_id, episode_number) |>
  dplyr::filter(n > 1L)
if (nrow(sheet_dupes) > 0L) {
  stop(glue(
    "[R/170] Duplicate (patient_id, episode_number) keys in sheet: ",
    "{nrow(sheet_dupes)} pairs.\n",
    "First few: {paste(utils::head(sheet_dupes$patient_id, 5), collapse=', ')}"
  ))
}

sheet_classified <- sheet_valid |>
  dplyr::mutate(
    hl    = classify_x(`Definitely HL`),
    nhl   = classify_x(`Definitely NHL`),
    hlnhl = classify_x(`HL and NHL`)
  )

unexpected_rows <- sheet_valid |>
  dplyr::filter(
    flag_unexpected_x(`Definitely HL`) |
    flag_unexpected_x(`Definitely NHL`) |
    flag_unexpected_x(`HL and NHL`)
  ) |>
  dplyr::select(patient_id, episode_number, `Definitely HL`, `Definitely NHL`, `HL and NHL`)

message(glue("  Unexpected E/F/J values (non-x, non-blank): {nrow(unexpected_rows)}"))

# =============================================================================
# SECTION 3 — Groups, chemo-only join, invariants, match counts
# =============================================================================

## 3.1 Classify groups -----------------------------------------------------

groups       <- classify_groups(sheet_classified)
g1_ids       <- groups$patient_id[groups$group1_strict]
g2_ids       <- groups$patient_id[groups$group2]
n_strict_g1  <- length(g1_ids)
n_loose_g1   <- sum(groups$group1_loose)
n_g2         <- length(g2_ids)
group_overlap_ids <- intersect(g1_ids, g2_ids)

message(glue("\n  Group 1 strict (all-NHL, no HL, no HL+NHL): {n_strict_g1}"))
message(glue("  Group 1 loose  (any NHL episode):           {n_loose_g1}"))
message(glue("  Group 2        (any HL+NHL episode):        {n_g2}"))
message(glue("  Group overlap  (in both G1 and G2):         {length(group_overlap_ids)}"))

## 3.2 Build E-J join table ------------------------------------------------

EJ_COLS <- c("Definitely HL", "Definitely NHL", "Initial", "Relapse", "Notes", "HL and NHL")

ej <- sheet_raw |>
  dplyr::filter(!is.na(patient_id) & !is.na(episode_number)) |>
  dplyr::select(patient_id, episode_number, dplyr::all_of(EJ_COLS))

# Preserve sheet drug_names separately for the cross-check (not a join key)
sheet_drug_for_check <- sheet_raw |>
  dplyr::filter(!is.na(patient_id) & !is.na(episode_number)) |>
  dplyr::select(patient_id, episode_number, sheet_drug_names = drug_names)

## 3.3 Build subsets -------------------------------------------------------

nhl_only_episodes <- join_ej_chemo_only(
  gantt |> dplyr::filter(patient_id %in% g1_ids),
  ej,
  chemo_value
)

hl_nhl_episodes <- join_ej_chemo_only(
  gantt |> dplyr::filter(patient_id %in% g2_ids),
  ej,
  chemo_value
)

## 3.4 Invariants ----------------------------------------------------------

stopifnot(
  "NHL-only row count changed" =
    nrow(nhl_only_episodes) == sum(gantt$patient_id %in% g1_ids),
  "HL+NHL row count changed" =
    nrow(hl_nhl_episodes) == sum(gantt$patient_id %in% g2_ids),
  "E-J on non-chemo rows (NHL-only)" =
    all(is.na(nhl_only_episodes$`Definitely NHL`[nhl_only_episodes$treatment_type != chemo_value])),
  "E-J on non-chemo rows (HL+NHL)" =
    all(is.na(hl_nhl_episodes$`HL and NHL`[hl_nhl_episodes$treatment_type != chemo_value]))
)

## 3.5 Zero-match guard ----------------------------------------------------

nhl_chemo_keys  <- nhl_only_episodes |> dplyr::filter(treatment_type == chemo_value) |>
                   dplyr::distinct(patient_id, episode_number)
hl_nhl_chemo_keys <- hl_nhl_episodes |> dplyr::filter(treatment_type == chemo_value) |>
                     dplyr::distinct(patient_id, episode_number)
ej_keys <- ej |> dplyr::distinct(patient_id, episode_number)

g1_sheet_match <- sum(ej_keys$patient_id %in% g1_ids)
g2_sheet_match <- sum(ej_keys$patient_id %in% g2_ids)

if (n_strict_g1 > 0L && g1_sheet_match == 0L) {
  stop("[R/170] Zero sheet keys match Group 1 chemo rows. Check key normalisation and snapshot version.")
}
if (n_g2 > 0L && g2_sheet_match == 0L) {
  stop("[R/170] Zero sheet keys match Group 2 chemo rows. Check key normalisation and snapshot version.")
}

## 3.6 Match counts (per group) --------------------------------------------

compute_match_counts <- function(subset_chemo_keys, group_ids, group_label) {
  sheet_for_group <- ej_keys |> dplyr::filter(patient_id %in% group_ids)
  gantt_keys      <- subset_chemo_keys

  sheet_matched   <- dplyr::inner_join(sheet_for_group, gantt_keys, by = c("patient_id", "episode_number"))
  sheet_unmatched <- dplyr::anti_join(sheet_for_group, gantt_keys, by = c("patient_id", "episode_number"))
  gantt_matched   <- dplyr::inner_join(gantt_keys, sheet_for_group, by = c("patient_id", "episode_number"))
  gantt_unmatched <- dplyr::anti_join(gantt_keys, sheet_for_group, by = c("patient_id", "episode_number"))

  # Sheet keys that match only non-chemo gantt rows
  nonchemo_keys <- gantt |>
    dplyr::filter(patient_id %in% group_ids, treatment_type != chemo_value) |>
    dplyr::distinct(patient_id, episode_number)
  sheet_nonchemo_only <- sheet_for_group |>
    dplyr::anti_join(gantt_keys, by = c("patient_id", "episode_number")) |>
    dplyr::inner_join(nonchemo_keys, by = c("patient_id", "episode_number"))

  # Sheet patient_ids absent from gantt entirely
  absent_pids <- setdiff(group_ids, unique(gantt$patient_id))

  message(glue("  [{group_label}] sheet episodes matched to chemo rows: {nrow(sheet_matched)}"))
  message(glue("  [{group_label}] sheet episodes unmatched:             {nrow(sheet_unmatched)}"))
  message(glue("  [{group_label}] chemo gantt rows matched to sheet:    {nrow(gantt_matched)}"))
  message(glue("  [{group_label}] chemo gantt rows unmatched:           {nrow(gantt_unmatched)}"))
  message(glue("  [{group_label}] sheet keys matching non-chemo only:   {nrow(sheet_nonchemo_only)}"))
  message(glue("  [{group_label}] group patient_ids absent from gantt:  {length(absent_pids)}"))

  list(
    sheet_matched       = sheet_matched,
    sheet_unmatched     = sheet_unmatched,
    gantt_matched       = gantt_matched,
    gantt_unmatched     = gantt_unmatched,
    sheet_nonchemo_only = sheet_nonchemo_only,
    absent_pids         = absent_pids
  )
}

message("\n--- Match counts ---")
mc_g1 <- compute_match_counts(nhl_chemo_keys,     g1_ids, "NHL-only")
mc_g2 <- compute_match_counts(hl_nhl_chemo_keys,  g2_ids, "HL+NHL")

# =============================================================================
# SECTION 4 — Drug-name cross-check, CSVs, and workbook
# =============================================================================

## 4.1 Drug-name cross-check -----------------------------------------------

# Build a single data frame of chemo rows with sheet drug_names joined
build_chemo_with_sheet_drugs <- function(subset_episodes, group_ids) {
  subset_episodes |>
    dplyr::filter(treatment_type == chemo_value) |>
    dplyr::left_join(sheet_drug_for_check, by = c("patient_id", "episode_number"))
}

chemo_g1 <- build_chemo_with_sheet_drugs(nhl_only_episodes, g1_ids)
chemo_g2 <- build_chemo_with_sheet_drugs(hl_nhl_episodes,   g2_ids)
chemo_combined <- dplyr::bind_rows(chemo_g1, chemo_g2)

dn <- check_drug_names(chemo_combined, sheet_col = "sheet_drug_names", gantt_col = "drug_names")
message(glue("\n  drug_names cross-check (chemo rows, both groups):"))
message(glue("    Exact matches       : {dn$n_exact}"))
message(glue("    Normalised-only     : {dn$n_norm_only}"))
message(glue("    Real mismatches     : {dn$n_mismatch}"))
message(glue("    One side missing    : {dn$n_one_side_missing}"))

## 4.2 Write CSVs ----------------------------------------------------------

int_dir <- file.path(CONFIG$output_dir, "internal")
if (!dir.exists(int_dir)) dir.create(int_dir, recursive = TRUE, showWarnings = FALSE)

csv_nhl  <- file.path(int_dir, glue("nhl_only_episodes_{run_date}.csv"))
csv_hlnhl <- file.path(int_dir, glue("hl_nhl_episodes_{run_date}.csv"))

readr::write_csv(nhl_only_episodes, csv_nhl)
readr::write_csv(hl_nhl_episodes,   csv_hlnhl)
message(glue("\n  Wrote: {csv_nhl}"))
message(glue("  Wrote: {csv_hlnhl}"))

## 4.3 Build workbook ------------------------------------------------------

UF_BLUE   <- "#0021A5"
UF_ORANGE <- "#FA4616"

wb <- openxlsx::createWorkbook()

# Style helpers
hdr_style <- openxlsx::createStyle(
  fontColour = "#FFFFFF", fgFill = UF_BLUE,
  halign = "center", textDecoration = "bold", wrapText = TRUE
)
flag_style <- openxlsx::createStyle(fgFill = UF_ORANGE)

add_hdr <- function(wb, sheet, df) {
  openxlsx::addStyle(wb, sheet, hdr_style, rows = 1, cols = seq_along(df), gridExpand = TRUE)
}

## --- KEY sheet -----------------------------------------------------------

key_rows <- data.frame(
  Field = c(
    "Run date",
    "Script",
    "INTERNAL — patient-level outputs",
    "QC counts intentionally unsuppressed",
    "Group 1 strict definition",
    "Group 2 definition",
    "Join grain",
    "Chemo-only rule",
    glue("Chemo treatment_type value"),
    "Snapshot path",
    "Snapshot size (bytes)",
    "Snapshot MD5",
    "Snapshot size matches 6,549,041",
    "Chemo-combos path",
    "Chemo-combos tab",
    "E-J source",
    "Key normalisation",
    "Drug-name normalisation"
  ),
  Value = c(
    run_date,
    "R/170_nhl_gantt_subsets.R",
    "Yes — write only to output/internal/",
    "Yes — aggregate QC only; episode tabs are already patient-level",
    "All episodes Definitely NHL (x), none Definitely HL (x), none HL and NHL (x)",
    "Any episode marked HL and NHL (x)",
    "(patient_id, episode_number)",
    "E-J columns populated only on chemo rows; NA on all other treatment types",
    chemo_value,
    gantt_path,
    as.character(snap_bytes),
    snap_md5,
    if (snap_size_ok) "YES" else glue("NO — got {snap_bytes}, expected {CONFIG$gantt_180_snapshot_bytes}"),
    CONFIG$chemo_combos_path,
    CONFIG$chemo_combos_tab,
    "Sheet tab 'Chemo and Cancer Dx' columns E-J (Definitely HL, Definitely NHL, Initial, Relapse, Notes, HL and NHL)",
    "norm_key(): trimws + strip .0+$ + empty->NA; applied to both sides",
    "normalize_drug_names(): lowercase, split ;/,, trim, drop empty, sort, rejoin ;"
  ),
  stringsAsFactors = FALSE
)

openxlsx::addWorksheet(wb, "KEY")
openxlsx::writeData(wb, "KEY", key_rows)
add_hdr(wb, "KEY", key_rows)
openxlsx::setColWidths(wb, "KEY", cols = 1:2, widths = c(40, 80))

## --- NHL_only_episodes sheet --------------------------------------------

openxlsx::addWorksheet(wb, "NHL_only_episodes")
openxlsx::writeData(wb, "NHL_only_episodes", nhl_only_episodes)
add_hdr(wb, "NHL_only_episodes", nhl_only_episodes)
openxlsx::setColWidths(wb, "NHL_only_episodes", cols = seq_along(nhl_only_episodes), widths = 18)

## --- HL_NHL_episodes sheet ----------------------------------------------

openxlsx::addWorksheet(wb, "HL_NHL_episodes")
openxlsx::writeData(wb, "HL_NHL_episodes", hl_nhl_episodes)
add_hdr(wb, "HL_NHL_episodes", hl_nhl_episodes)
openxlsx::setColWidths(wb, "HL_NHL_episodes", cols = seq_along(hl_nhl_episodes), widths = 18)

## --- QC sheet -----------------------------------------------------------

# Helper: flatten a data.frame to a block of rows labelled "key: value"
qc_block <- function(label, df_or_list) {
  if (is.data.frame(df_or_list)) {
    if (nrow(df_or_list) == 0L) {
      return(data.frame(QC_Field = label, QC_Value = "(none)", stringsAsFactors = FALSE))
    }
    rows <- apply(df_or_list, 1, function(r) paste(names(r), r, sep = "=", collapse = " | "))
    data.frame(QC_Field = label, QC_Value = rows, stringsAsFactors = FALSE)
  } else {
    data.frame(QC_Field = label, QC_Value = as.character(df_or_list), stringsAsFactors = FALSE)
  }
}

qc_df <- dplyr::bind_rows(
  # (a) Group counts
  data.frame(QC_Field = "--- (a) Group counts ---", QC_Value = "", stringsAsFactors = FALSE),
  qc_block("Group 1 strict (all-NHL, no HL, no HL+NHL)",     n_strict_g1),
  qc_block("Group 1 loose  (any NHL)",                        n_loose_g1),
  qc_block("Group 2        (any HL+NHL)",                     n_g2),
  # (b) Group overlap
  data.frame(QC_Field = "--- (b) Group overlap ---", QC_Value = "", stringsAsFactors = FALSE),
  qc_block("Group overlap patient IDs", if (length(group_overlap_ids) == 0L) "(none)" else paste(group_overlap_ids, collapse="; ")),
  qc_block("Group overlap count", length(group_overlap_ids)),
  # (c) Match counts
  data.frame(QC_Field = "--- (c) Match counts (NHL-only) ---", QC_Value = "", stringsAsFactors = FALSE),
  qc_block("Sheet eps matched to chemo rows (G1)",   nrow(mc_g1$sheet_matched)),
  qc_block("Sheet eps unmatched (G1)",                nrow(mc_g1$sheet_unmatched)),
  qc_block("Chemo gantt rows matched to sheet (G1)",  nrow(mc_g1$gantt_matched)),
  qc_block("Chemo gantt rows unmatched (G1)",          nrow(mc_g1$gantt_unmatched)),
  data.frame(QC_Field = "--- (c) Match counts (HL+NHL) ---", QC_Value = "", stringsAsFactors = FALSE),
  qc_block("Sheet eps matched to chemo rows (G2)",   nrow(mc_g2$sheet_matched)),
  qc_block("Sheet eps unmatched (G2)",                nrow(mc_g2$sheet_unmatched)),
  qc_block("Chemo gantt rows matched to sheet (G2)",  nrow(mc_g2$gantt_matched)),
  qc_block("Chemo gantt rows unmatched (G2)",          nrow(mc_g2$gantt_unmatched)),
  # (d) Sheet keys matching only non-chemo rows
  data.frame(QC_Field = "--- (d) Sheet keys matching non-chemo rows only ---", QC_Value = "", stringsAsFactors = FALSE),
  qc_block("Count (G1)", nrow(mc_g1$sheet_nonchemo_only)),
  qc_block("Count (G2)", nrow(mc_g2$sheet_nonchemo_only)),
  # (e) Sheet IDs absent from gantt
  data.frame(QC_Field = "--- (e) Sheet patient_ids absent from gantt ---", QC_Value = "", stringsAsFactors = FALSE),
  qc_block("Absent IDs (G1)", if (length(mc_g1$absent_pids)==0L) "(none)" else paste(mc_g1$absent_pids,collapse="; ")),
  qc_block("Absent IDs (G2)", if (length(mc_g2$absent_pids)==0L) "(none)" else paste(mc_g2$absent_pids,collapse="; ")),
  # (f) NA-key sheet rows
  data.frame(QC_Field = "--- (f) NA-key sheet rows excluded from join ---", QC_Value = "", stringsAsFactors = FALSE),
  qc_block("NA-key sheet rows", n_na_key_sheet),
  # (g) Duplicate keys
  data.frame(QC_Field = "--- (g) Duplicate keys (0 if run completed) ---", QC_Value = "", stringsAsFactors = FALSE),
  qc_block("Gantt chemo duplicate (patient_id,episode_number) pairs", nrow(gantt_chemo_dupes)),
  qc_block("Sheet duplicate (patient_id,episode_number) pairs",       nrow(sheet_dupes)),
  # (h) Unexpected E/F/J values
  data.frame(QC_Field = "--- (h) Unexpected E/F/J values ---", QC_Value = "", stringsAsFactors = FALSE),
  qc_block("Count of rows with unexpected values", nrow(unexpected_rows)),
  if (nrow(unexpected_rows) > 0L)
    qc_block("Unexpected rows", unexpected_rows)
  else
    data.frame(QC_Field = "Unexpected rows", QC_Value = "(none)", stringsAsFactors = FALSE),
  # (i) Drug-name cross-check
  data.frame(QC_Field = "--- (i) drug_names cross-check ---", QC_Value = "", stringsAsFactors = FALSE),
  qc_block("Exact matches",      dn$n_exact),
  qc_block("Normalised-only",    dn$n_norm_only),
  qc_block("Real mismatches",    dn$n_mismatch),
  qc_block("One side missing",   dn$n_one_side_missing),
  if (nrow(dn$mismatch_rows) > 0L)
    qc_block("Mismatch rows", dn$mismatch_rows)
  else
    data.frame(QC_Field = "Mismatch rows", QC_Value = "(none)", stringsAsFactors = FALSE),
  # (j) Snapshot identity
  data.frame(QC_Field = "--- (j) Snapshot identity ---", QC_Value = "", stringsAsFactors = FALSE),
  qc_block("Snapshot path",        gantt_path),
  qc_block("Snapshot size bytes",  as.character(snap_bytes)),
  qc_block("Snapshot MD5",         snap_md5),
  qc_block("Size matches 6,549,041", if (snap_size_ok) "YES" else glue("NO — {snap_bytes}")),
  qc_block("MD5 matches pinned",   if (snap_md5_ok) "YES (or not pinned)" else "NO — MISMATCH"),
  # (k) Episode-number scope
  data.frame(QC_Field = "--- (k) Episode-number scope (D-14) ---", QC_Value = "", stringsAsFactors = FALSE),
  qc_block("Episode scope finding", episode_scope_note),
  qc_block("Cross-type duplicate (patient_id,episode_number) pairs in gantt", n_all_scope_dupes)
)

openxlsx::addWorksheet(wb, "QC")
openxlsx::writeData(wb, "QC", qc_df)
add_hdr(wb, "QC", qc_df)
openxlsx::setColWidths(wb, "QC", cols = 1:2, widths = c(50, 80))

# Flag snapshot size mismatch row in QC with orange fill
if (!snap_size_ok) {
  size_row_idx <- which(qc_df$QC_Field == "Size matches 6,549,041")
  if (length(size_row_idx) > 0L) {
    openxlsx::addStyle(wb, "QC", flag_style,
      rows = size_row_idx + 1L, cols = 2L)  # +1 for header row
  }
}

## 4.4 Save workbook -------------------------------------------------------

wb_path <- file.path(int_dir, glue("nhl_gantt_subsets_{run_date}.xlsx"))
openxlsx::saveWorkbook(wb, wb_path, overwrite = TRUE)
message(glue("  Wrote: {wb_path}"))
message("\n=== Phase 168: COMPLETE ===")

}  # end else (inputs_ok)
