# R/120_zip5_backfill_concordance.R
# Phase 150: ZIP5-missing but ZIP9-elsewhere — patient counts and first-5 concordance
# Read-only diagnostic. No output files written.
# Outputs (1), (2), (3a-c), (4) are patient-level (distinct ID) per D-02.
# Output (5) is a supplementary record-level diagnostic per D-09.

source("R/00_config.R")   # auto-loads R/utils/utils_address.R and defines CONFIG

suppressPackageStartupMessages({
  library(dplyr)
  library(vroom)
})

cat("\n=== 120 ZIP5-backfill concordance ===\n")

# --- Resolve the ZIP5 normalizer (O-01) -------------------------------------
# normalize_zip5_raw() is the correct call on raw ADDRESS_ZIP5 if utils_address.R
# defines it; otherwise normalize_zip5() is used. Fail loudly if neither exists.
zip5_fn_name <- if (exists("normalize_zip5_raw", mode = "function")) {
  "normalize_zip5_raw"
} else if (exists("normalize_zip5", mode = "function")) {
  "normalize_zip5"
} else {
  stop("Neither normalize_zip5_raw() nor normalize_zip5() found after sourcing R/00_config.R")
}
for (fn in c("normalize_zip9", "is_sentinel_zip5")) {
  if (!exists(fn, mode = "function")) {
    stop("Required helper not found after sourcing R/00_config.R: ", fn)
  }
}
norm_zip5 <- get(zip5_fn_name, mode = "function")
cat("ZIP5 normalizer in use:", zip5_fn_name, "\n")

# --- Load -------------------------------------------------------------------
addr_path <- file.path(CONFIG$data_dir, "LDS_ADDRESS_HISTORY_Mailhot_V1.csv")
if (!file.exists(addr_path)) stop("Address file not found: ", addr_path)

addr_raw <- vroom::vroom(
  addr_path,
  col_types = vroom::cols(.default = vroom::col_character()),
  progress  = FALSE
)

required_cols <- c("ID", "ADDRESS_ZIP5", "ADDRESS_ZIP9")
missing_cols  <- setdiff(required_cols, names(addr_raw))
if (length(missing_cols) > 0L) {
  stop("Missing expected column(s) in ", basename(addr_path), ": ",
       paste(missing_cols, collapse = ", "))
}
has_start <- "ADDRESS_PERIOD_START" %in% names(addr_raw)

cat("Rows read:", nrow(addr_raw),
    "| period start available:", has_start, "\n")

# --- Normalize and flag -----------------------------------------------------
# NA-safe logical: NA becomes FALSE so the flags partition rows cleanly.
tf <- function(x) !is.na(x) & x

addr <- addr_raw |>
  dplyr::transmute(
    pid          = ID,
    zip5_norm    = norm_zip5(ADDRESS_ZIP5),
    zip9_norm    = normalize_zip9(ADDRESS_ZIP9),
    # Assumed ISO-8601; used only as a modal tie-break, so lexical order suffices.
    period_start = if (has_start) ADDRESS_PERIOD_START else NA_character_
  )

n_bad_id <- sum(is.na(addr$pid) | !nzchar(trimws(addr$pid)))
if (n_bad_id > 0L) {
  cat("WARNING: dropping", n_bad_id, "row(s) with missing or blank ID\n")
}
addr <- addr |> dplyr::filter(!is.na(pid), nzchar(trimws(pid)))

addr <- addr |>
  dplyr::mutate(
    zip5_missing = is.na(zip5_norm) | tf(is_sentinel_zip5(zip5_norm)),
    zip9_valid   = tf(!is.na(zip9_norm) & nchar(zip9_norm) == 9L),
    zip9_usable  = zip9_valid & !tf(is_sentinel_zip5(substr(zip9_norm, 1L, 5L)))
  )

cat("Rows retained:", nrow(addr),
    "| patients:", dplyr::n_distinct(addr$pid), "\n\n")

# --- Modal value per patient, explicit grouping + deterministic tie-break ----
# D-08 order: record frequency, then latest period start, then ZIP lexically.
max_chr <- function(x) {
  x <- x[!is.na(x)]
  if (length(x) == 0L) NA_character_ else max(x)
}

modal_by_patient <- function(df, value_col, out_name) {
  tallied <- df |>
    dplyr::group_by(pid, .data[[value_col]]) |>
    dplyr::summarise(n_rows     = dplyr::n(),
                     last_start = max_chr(period_start),
                     .groups    = "drop")
  names(tallied)[2] <- "value"

  n_tied <- tallied |>
    dplyr::group_by(pid) |>
    dplyr::summarise(tied = sum(n_rows == max(n_rows)) > 1L, .groups = "drop") |>
    dplyr::pull(tied) |>
    sum()

  picked <- tallied |>
    dplyr::group_by(pid) |>
    dplyr::arrange(dplyr::desc(n_rows), dplyr::desc(last_start), value,
                   .by_group = TRUE) |>
    dplyr::slice(1L) |>
    dplyr::ungroup() |>
    dplyr::select(pid, value)

  names(picked)[2] <- out_name
  attr(picked, "n_tied") <- n_tied
  picked
}

# --- COUNT 1 ----------------------------------------------------------------
pts_missing_zip5 <- addr |>
  dplyr::filter(zip5_missing) |>
  dplyr::distinct(pid)

n_missing_zip5 <- nrow(pts_missing_zip5)
cat("(1) Patients with >=1 record where ZIP5 is missing or sentinel:",
    n_missing_zip5, "\n")

# --- COUNT 2 (D-07: usable ZIP9 on ANY record, same row included) -----------
pts_with_zip9 <- pts_missing_zip5 |>
  dplyr::semi_join(addr |> dplyr::filter(zip9_usable) |> dplyr::distinct(pid),
                   by = "pid")

n_zip9_available <- nrow(pts_with_zip9)
cat("(2) Of those, patients with a usable ZIP9 on at least one record:",
    n_zip9_available, "\n")

n_same_row <- addr |>
  dplyr::filter(zip5_missing, zip9_usable) |>
  dplyr::distinct(pid) |>
  nrow()

n_other_row <- addr |>
  dplyr::semi_join(pts_with_zip9, by = "pid") |>
  dplyr::filter(!zip5_missing, zip9_usable) |>
  dplyr::distinct(pid) |>
  nrow()

cat("    (2a) usable ZIP9 on a missing-ZIP5 record itself:", n_same_row, "\n")
cat("    (2b) usable ZIP9 on a record where ZIP5 is present:", n_other_row, "\n")
cat("         (2a and 2b overlap; they do not sum to (2))\n")

# --- COUNTS 3a / 3b / 3c ----------------------------------------------------
addr_grp2 <- addr |> dplyr::semi_join(pts_with_zip9, by = "pid")

zip9_first5_by_pat <- addr_grp2 |>
  dplyr::filter(zip9_usable) |>
  dplyr::mutate(zip9_first5 = substr(zip9_norm, 1L, 5L)) |>
  modal_by_patient("zip9_first5", "zip9_first5")

real_zip5_by_pat <- addr_grp2 |>
  dplyr::filter(!zip5_missing) |>
  modal_by_patient("zip5_norm", "zip5_real")

# Catches an accidentally ungrouped modal pick: one row per group-2 patient.
stopifnot(nrow(zip9_first5_by_pat) == n_zip9_available)
stopifnot(!any(duplicated(zip9_first5_by_pat$pid)))
stopifnot(!any(duplicated(real_zip5_by_pat$pid)))

concordance_tbl <- zip9_first5_by_pat |>
  dplyr::left_join(real_zip5_by_pat, by = "pid") |>
  dplyr::mutate(
    status = dplyr::case_when(
      is.na(zip5_real)         ~ "no_zip5_elsewhere",
      zip9_first5 == zip5_real ~ "concordant",
      TRUE                     ~ "discordant"
    )
  )

get_n <- function(tbl, key) {
  hit <- tbl$n[tbl$status == key]
  if (length(hit) == 0L) 0L else as.integer(hit[1L])
}
status_counts <- dplyr::count(concordance_tbl, status, name = "n")

n_concordant        <- get_n(status_counts, "concordant")
n_discordant        <- get_n(status_counts, "discordant")
n_no_zip5_elsewhere <- get_n(status_counts, "no_zip5_elsewhere")

cat("(3a) n_concordant (modal ZIP9 first-5 == modal ZIP5):", n_concordant, "\n")
cat("(3b) n_discordant (modal ZIP9 first-5 != modal ZIP5):", n_discordant, "\n")
cat("(3c) n_no_zip5_elsewhere (ZIP9 present, no ZIP5 to compare):",
    n_no_zip5_elsewhere, "\n")

# Buckets must exhaust group 2; detects dropped or duplicated patients.
stopifnot(n_concordant + n_discordant + n_no_zip5_elsewhere == n_zip9_available)

cat("     Patients with a tied modal ZIP9 first-5:",
    attr(zip9_first5_by_pat, "n_tied"), "\n")
cat("     Patients with a tied modal ZIP5:",
    attr(real_zip5_by_pat, "n_tied"), "\n")

# --- COUNT 4 ----------------------------------------------------------------
denom <- n_concordant + n_discordant
if (denom > 0L) {
  rate <- n_concordant / denom
  cat(sprintf("(4) Patient-level modal concordance: %.1f%% (%d / %d)\n",
              rate * 100, n_concordant, denom))
  cat("    Interpretation: modal ZIP9 first-5 and modal observed ZIP5 agree for ",
      sprintf("%.1f%%", rate * 100), " of\n",
      "    patients with both values available. This compares patient-level modal\n",
      "    values across all records, so a change of address within the study period\n",
      "    registers as discordance. It does not by itself establish that ZIP9\n",
      "    recovers the value of any specific missing ZIP5 record; see (5) for the\n",
      "    record-level measure.\n", sep = "")
} else {
  cat("(4) Patient-level modal concordance: N/A (no comparable patients)\n")
}

# --- (5) Record-level same-record validation (supplementary, D-09) ----------
# Direct test of the same-row backfill mechanism: on records carrying both a
# usable ZIP9 and a non-missing ZIP5, does the ZIP9 first-5 equal that ZIP5?
rowlevel <- addr |>
  dplyr::filter(!zip5_missing, zip9_usable) |>
  dplyr::mutate(row_match = substr(zip9_norm, 1L, 5L) == zip5_norm)

n_rows_cmp   <- nrow(rowlevel)
n_rows_match <- sum(rowlevel$row_match, na.rm = TRUE)
n_pts_cmp    <- dplyr::n_distinct(rowlevel$pid)

cat("\n(5) Record-level same-record check (supplementary, not patient-level):\n")
if (n_rows_cmp > 0L) {
  cat(sprintf("    %d of %d records agree (%.1f%%), across %d patients.\n",
              n_rows_match, n_rows_cmp,
              100 * n_rows_match / n_rows_cmp, n_pts_cmp))
  cat("    This measures the same-row mechanism directly and is unaffected by moves.\n")
} else {
  cat("    N/A (no records carry both a usable ZIP9 and a non-missing ZIP5)\n")
}

cat("\n=== 120 done ===\n")
