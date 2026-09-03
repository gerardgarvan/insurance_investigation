# R/121_zip_problem_inventory.R
# Phase 151: Per-patient ZIP problem inventory
# One row per patient ID with 12 problem flags, supporting counts, and a triage category.
# Flag predicates are semantically identical to R/120, enforced by reconciliation (D-04).
# Writes a workbook + RDS (D-01).

source("R/00_config.R")   # auto-loads R/utils/utils_address.R and defines CONFIG

suppressPackageStartupMessages({
  library(dplyr)
  library(tibble)
  library(vroom)
  library(openxlsx)
})

cat("\n=== 121 ZIP problem inventory ===\n")

# --- Pinned inputs from the Phase 150 run (D-05, D-10) ----------------------
# PHASE150_ZIP5_FN must match the "ZIP5 normalizer in use:" line in 150-01-SUMMARY.md.
PHASE150_ZIP5_FN <- "normalize_zip5_raw"   # confirmed from Phase 150 run: normalize_zip5_raw

EXPECTED <- c(
  n_missing_zip5      = 1128L,
  n_zip9_available    = 701L,
  n_unreachable       = 427L,
  n_concordant        = 530L,
  n_discordant        = 152L,
  n_no_zip5_elsewhere = 19L,
  n_rows_both_present = 19739L,
  n_rows_mismatch     = 12L
)

UF_BLUE   <- "#0021A5"
UF_ORANGE <- "#FA4616"
OUT_DIR   <- CONFIG$output_dir         # confirmed: CONFIG$output_dir (R/115 line 430)

# --- Resolve helpers; no silent fallback on the normalizer (D-10) ----------
if (!exists(PHASE150_ZIP5_FN, mode = "function")) {
  stop("Phase 150 used ", PHASE150_ZIP5_FN,
       "() but it is not available after sourcing R/00_config.R. ",
       "The reconciliation constants were derived under that function; ",
       "do not substitute another normalizer.")
}
for (fn in c("normalize_zip9", "is_sentinel_zip5")) {
  if (!exists(fn, mode = "function")) {
    stop("Required helper not found after sourcing R/00_config.R: ", fn)
  }
}
norm_zip5 <- get(PHASE150_ZIP5_FN, mode = "function")
cat("ZIP5 normalizer (pinned to Phase 150):", PHASE150_ZIP5_FN, "\n")

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
has_end   <- "ADDRESS_PERIOD_END"   %in% names(addr_raw)

n_rows_read <- nrow(addr_raw)
cat("Rows read:", n_rows_read, "\n")

# --- Date format assertion (tie-break sorts lexically) ---------------------
if (has_start) {
  s <- addr_raw$ADDRESS_PERIOD_START
  s <- s[!is.na(s) & nzchar(trimws(s))]
  if (length(s) > 0L && !all(grepl("^\\d{4}-\\d{2}-\\d{2}", s))) {
    stop("ADDRESS_PERIOD_START is not ISO-8601; the modal tie-break sorts these ",
         "lexically and would pick the wrong record. Parse the dates before use.")
  }
}

# --- Normalize and flag -----------------------------------------------------
tf <- function(x) !is.na(x) & x

addr <- addr_raw |>
  dplyr::transmute(
    pid          = ID,
    zip5_raw     = ADDRESS_ZIP5,
    zip9_raw     = ADDRESS_ZIP9,
    zip5_norm    = norm_zip5(ADDRESS_ZIP5),
    zip9_norm    = normalize_zip9(ADDRESS_ZIP9),
    period_start = if (has_start) ADDRESS_PERIOD_START else NA_character_,
    period_end   = if (has_end)   ADDRESS_PERIOD_END   else NA_character_
  )

n_bad_id <- sum(is.na(addr$pid) | !nzchar(trimws(addr$pid)))
if (n_bad_id > 0L) cat("WARNING: dropping", n_bad_id, "row(s) with missing or blank ID\n")
addr <- addr |> dplyr::filter(!is.na(pid), nzchar(trimws(pid)))

addr <- addr |>
  dplyr::mutate(
    zip5_sentinel = !is.na(zip5_norm) & tf(is_sentinel_zip5(zip5_norm)),
    zip5_missing  = is.na(zip5_norm) | tf(is_sentinel_zip5(zip5_norm)),
    zip9_valid    = tf(!is.na(zip9_norm) & nchar(zip9_norm) == 9L),
    zip9_usable   = zip9_valid & !tf(is_sentinel_zip5(substr(zip9_norm, 1L, 5L))),
    zip9_present_unusable = !is.na(zip9_raw) & nzchar(trimws(zip9_raw)) & !zip9_usable,
    zip9_first5   = ifelse(zip9_usable, substr(zip9_norm, 1L, 5L), NA_character_),
    row_mismatch  = !zip5_missing & zip9_usable & (zip9_first5 != zip5_norm)
  )

n_rows_kept <- nrow(addr)
cat("Rows retained:", n_rows_kept, "| patients:", dplyr::n_distinct(addr$pid), "\n\n")

# --- Modal value per patient (grouped; deterministic tie-break) -------------
max_chr <- function(x) { x <- x[!is.na(x)]; if (!length(x)) NA_character_ else max(x) }
min_chr <- function(x) { x <- x[!is.na(x)]; if (!length(x)) NA_character_ else min(x) }

modal_by_patient <- function(df, value_col, out_name) {
  tallied <- df |>
    dplyr::group_by(pid, .data[[value_col]]) |>
    dplyr::summarise(n_rows = dplyr::n(), last_start = max_chr(period_start), .groups = "drop")
  names(tallied)[2] <- "value"

  ties <- tallied |>
    dplyr::group_by(pid) |>
    dplyr::summarise(tied = sum(n_rows == max(n_rows)) > 1L, .groups = "drop")

  tallied |>
    dplyr::group_by(pid) |>
    dplyr::arrange(dplyr::desc(n_rows), dplyr::desc(last_start), value, .by_group = TRUE) |>
    dplyr::slice(1L) |>
    dplyr::ungroup() |>
    dplyr::select(pid, value) |>
    dplyr::rename(!!out_name := value) |>
    dplyr::left_join(ties, by = "pid") |>
    dplyr::rename(!!paste0(out_name, "_tied") := tied)
}

modal_zip5 <- addr |> dplyr::filter(!zip5_missing) |> modal_by_patient("zip5_norm",   "modal_zip5")
modal_zip9 <- addr |> dplyr::filter(zip9_usable)   |> modal_by_patient("zip9_first5", "modal_zip9_first5")

stopifnot(!anyDuplicated(modal_zip5$pid), !anyDuplicated(modal_zip9$pid))

# --- Per-patient aggregation ------------------------------------------------
pat <- addr |>
  dplyr::group_by(pid) |>
  dplyr::summarise(
    n_records               = dplyr::n(),
    n_zip5_missing          = sum(zip5_missing),
    n_zip5_observed         = sum(!zip5_missing),
    n_zip5_sentinel         = sum(zip5_sentinel),
    n_zip9_usable           = sum(zip9_usable),
    n_zip9_present_unusable = sum(zip9_present_unusable),
    n_distinct_zip5         = dplyr::n_distinct(zip5_norm[!zip5_missing]),
    n_distinct_zip9_first5  = dplyr::n_distinct(zip9_first5[zip9_usable]),
    n_same_row_backfill     = sum(zip5_missing & zip9_usable),
    n_both_present          = sum(!zip5_missing & zip9_usable),
    n_row_mismatch          = sum(row_mismatch, na.rm = TRUE),
    period_first            = min_chr(period_start),
    period_last             = max_chr(period_end),
    .groups = "drop"
  ) |>
  dplyr::left_join(modal_zip5, by = "pid") |>
  dplyr::left_join(modal_zip9, by = "pid") |>
  dplyr::mutate(
    modal_zip5_tied        = dplyr::coalesce(modal_zip5_tied, FALSE),
    modal_zip9_first5_tied = dplyr::coalesce(modal_zip9_first5_tied, FALSE),
    n_missing_zip5_no_same_row_zip9 = n_zip5_missing - n_same_row_backfill
  )

stopifnot(!anyDuplicated(pat$pid))

# --- Flags ------------------------------------------------------------------
pat <- pat |>
  dplyr::mutate(
    F01_missing_zip5          = n_zip5_missing > 0L,
    F02_zip5_never_observed   = n_zip5_observed == 0L,
    F03_no_usable_zip9        = n_zip9_usable == 0L,
    F04_same_row_backfillable = n_same_row_backfill > 0L,
    F05_other_row_zip9_only   = n_zip5_missing > 0L & n_zip9_usable > 0L &
                                 n_same_row_backfill == 0L,
    F06_modal_discordant      = !is.na(modal_zip5) & !is.na(modal_zip9_first5) &
                                 modal_zip5 != modal_zip9_first5,
    F07_multiple_zip5         = n_distinct_zip5 > 1L,
    F08_tied_modal            = modal_zip5_tied | modal_zip9_first5_tied,
    F09_record_level_mismatch = n_row_mismatch > 0L,
    F10_sentinel_zip5_present = n_zip5_sentinel > 0L,
    F11_invalid_zip9_present  = n_zip9_present_unusable > 0L,
    F12_partial_same_row      = n_zip5_missing > 0L & n_same_row_backfill > 0L &
                                 n_missing_zip5_no_same_row_zip9 > 0L
  ) |>
  dplyr::mutate(
    triage = dplyr::case_when(
      !F01_missing_zip5                                     ~ "NO_MISSING_ZIP5",
      n_same_row_backfill == n_zip5_missing                 ~ "SAME_ROW_BACKFILL_ALL",
      n_same_row_backfill > 0L                              ~ "SAME_ROW_BACKFILL_PARTIAL",
      F05_other_row_zip9_only                               ~ "NEEDS_TEMPORAL_MATCH",
      TRUE                                                  ~ "UNREACHABLE_NO_ZIP9"
    )
  )

flag_cols <- grep("^F[0-9]{2}_", names(pat), value = TRUE)
pat <- pat |>
  dplyr::mutate(n_flags = rowSums(dplyr::across(dplyr::all_of(flag_cols))))

# --- Structural invariants --------------------------------------------------
stopifnot(sum(pat$F04_same_row_backfillable & pat$F05_other_row_zip9_only) == 0L)
stopifnot(all(!pat$F05_other_row_zip9_only | pat$F01_missing_zip5))
stopifnot(all(!pat$F12_partial_same_row | pat$F01_missing_zip5))
stopifnot(
  sum(pat$triage %in% c("SAME_ROW_BACKFILL_ALL", "SAME_ROW_BACKFILL_PARTIAL",
                        "NEEDS_TEMPORAL_MATCH", "UNREACHABLE_NO_ZIP9")) ==
    sum(pat$F01_missing_zip5)
)

# --- Reconciliation against Phase 150 (D-05) --------------------------------
obs <- c(
  n_missing_zip5      = sum(pat$F01_missing_zip5),
  n_zip9_available    = sum(pat$F01_missing_zip5 & pat$n_zip9_usable > 0L),
  n_unreachable       = sum(pat$F01_missing_zip5 & pat$F03_no_usable_zip9),
  n_concordant        = sum(pat$F01_missing_zip5 & pat$n_zip9_usable > 0L &
                            !is.na(pat$modal_zip5) & pat$modal_zip5 == pat$modal_zip9_first5),
  n_discordant        = sum(pat$F01_missing_zip5 & pat$n_zip9_usable > 0L &
                            !is.na(pat$modal_zip5) & pat$modal_zip5 != pat$modal_zip9_first5),
  n_no_zip5_elsewhere = sum(pat$F01_missing_zip5 & pat$n_zip9_usable > 0L &
                            is.na(pat$modal_zip5)),
  n_rows_both_present = sum(pat$n_both_present),
  n_rows_mismatch     = sum(pat$n_row_mismatch)
)

recon <- tibble::tibble(
  quantity = names(EXPECTED),
  expected = as.integer(EXPECTED),
  observed = as.integer(obs[names(EXPECTED)])
) |>
  dplyr::mutate(status = ifelse(expected == observed, "PASS", "FAIL"))

print(as.data.frame(recon), row.names = FALSE)

# --- Summaries --------------------------------------------------------------
n_all_patients <- nrow(pat)
n_f01 <- sum(pat$F01_missing_zip5)

flag_summary <- tibble::tibble(
  flag         = flag_cols,
  n_patients   = vapply(flag_cols, function(f) sum(pat[[f]]), integer(1)),
  n_within_F01 = vapply(flag_cols,
                        function(f) sum(pat[[f]] & pat$F01_missing_zip5), integer(1))
) |>
  dplyr::mutate(
    pct_all_patients = round(100 * n_patients / n_all_patients, 2),
    pct_within_F01   = round(100 * n_within_F01 / n_f01, 2)
  )

triage_summary <- pat |>
  dplyr::count(triage, name = "n_patients") |>
  dplyr::mutate(pct = round(100 * n_patients / n_all_patients, 2)) |>
  dplyr::arrange(dplyr::desc(n_patients))

record_mismatches <- addr |>
  dplyr::filter(tf(row_mismatch)) |>
  dplyr::transmute(ID = pid, zip5_norm, zip9_norm, zip9_first5, period_start, period_end)

roster <- pat |>
  dplyr::filter(n_flags > 0L) |>
  dplyr::arrange(dplyr::desc(n_flags), triage, pid) |>
  dplyr::rename(ID = pid)

# --- KEY: every column in A_patient_flags, plus flags and triage (D-06) -----
key_tbl <- tibble::tribble(
  ~item,                             ~definition,
  "Unit of observation",             "One row per patient ID with at least one flag set",
  "ID",                              "Patient identifier from LDS_ADDRESS_HISTORY",
  "n_records",                       "Address records for this patient after blank-ID filtering",
  "n_zip5_missing",                  "Records where ZIP5 is NA or sentinel",
  "n_zip5_observed",                 "Records with a usable non-sentinel ZIP5",
  "n_zip5_sentinel",                 "Records where ZIP5 is present but sentinel",
  "n_zip9_usable",                   "Records with a 9-char ZIP9 whose first-5 is not sentinel",
  "n_zip9_present_unusable",         "Records with a non-blank ZIP9 that fails the usable test",
  "n_distinct_zip5",                 "Distinct observed ZIP5 values across this patient's records",
  "n_distinct_zip9_first5",          "Distinct first-5 values across usable ZIP9 records",
  "n_same_row_backfill",             "Missing-ZIP5 records that carry a usable ZIP9 on the same row",
  "n_missing_zip5_no_same_row_zip9", "Missing-ZIP5 records with no same-row ZIP9 (residual work)",
  "n_both_present",                  "Records with both a usable ZIP9 and a non-missing ZIP5",
  "n_row_mismatch",                  "Of those, records where ZIP9 first-5 differs from ZIP5",
  "modal_zip5",                      "Most frequent observed ZIP5; ties broken by latest period start, then lexically",
  "modal_zip5_tied",                 "TRUE if modal_zip5 was decided by tie-break",
  "modal_zip9_first5",               "Most frequent usable ZIP9 first-5; same tie-break",
  "modal_zip9_first5_tied",          "TRUE if modal_zip9_first5 was decided by tie-break",
  "period_first",                    "Earliest ADDRESS_PERIOD_START across this patient's records",
  "period_last",                     "Latest ADDRESS_PERIOD_END across this patient's records",
  "n_flags",                         "Count of F01-F12 flags set for this patient",
  "triage",                          "Mutually exclusive category; see triage rows below",
  "F01_missing_zip5",                ">=1 record where ZIP5 is NA or sentinel",
  "F02_zip5_never_observed",         "No non-missing ZIP5 on any record",
  "F03_no_usable_zip9",              "No usable ZIP9 on any record",
  "F04_same_row_backfillable",       ">=1 missing-ZIP5 record carries a usable ZIP9 on that same row",
  "F05_other_row_zip9_only",         "Has missing ZIP5 and a usable ZIP9, but never on a missing-ZIP5 row",
  "F06_modal_discordant",            "Modal ZIP9 first-5 differs from modal observed ZIP5",
  "F07_multiple_zip5",               "More than one distinct observed ZIP5 (mobility proxy)",
  "F08_tied_modal",                  "A modal value was decided by tie-break",
  "F09_record_level_mismatch",       ">=1 record where both values present and first-5 disagree",
  "F10_sentinel_zip5_present",       ">=1 ZIP5 present but sentinel",
  "F11_invalid_zip9_present",        ">=1 ZIP9 present but not usable",
  "F12_partial_same_row",            "Some missing-ZIP5 records have a same-row ZIP9 and some do not",
  "triage NO_MISSING_ZIP5",          "Nothing to backfill",
  "triage SAME_ROW_BACKFILL_ALL",    "Every missing-ZIP5 record has a same-row ZIP9; fully fixable now",
  "triage SAME_ROW_BACKFILL_PARTIAL","Some but not all missing records fixable from the same row",
  "triage NEEDS_TEMPORAL_MATCH",     "ZIP9 only on other records; exposed to residential mobility",
  "triage UNREACHABLE_NO_ZIP9",      "No ZIP9 anywhere; ZIP5-only methods or exclusion",
  "Modal tie-break",                 "Record frequency, then latest ADDRESS_PERIOD_START, then ZIP lexically",
  "Source",                          basename(addr_path),
  "Generated",                       as.character(Sys.time()),
  "Script",                          "R/121_zip_problem_inventory.R (Phase 151)",
  "Confidentiality",                 "Contains patient identifiers; project output directory only"
)

pkg_versions <- paste(
  vapply(c("dplyr", "vroom", "openxlsx", "tibble"),
         function(p) paste0(p, " ", as.character(utils::packageVersion(p))),
         character(1)),
  collapse = "; "
)

qc_tbl <- tibble::tibble(
  metric = c("rows_read", "rows_retained", "blank_ids_dropped", "patients_total",
             "patients_flagged", "zip5_normalizer", "r_version", "package_versions"),
  value  = c(as.character(n_rows_read), as.character(n_rows_kept), as.character(n_bad_id),
             as.character(n_all_patients), as.character(nrow(roster)), PHASE150_ZIP5_FN,
             paste(R.version$major, R.version$minor, sep = "."), pkg_versions)
)

# --- Workbook ---------------------------------------------------------------
hdr <- openxlsx::createStyle(fgFill = UF_BLUE, fontColour = "#FFFFFF",
                             textDecoration = "bold", halign = "left")
fail_style <- openxlsx::createStyle(fgFill = UF_ORANGE, fontColour = "#FFFFFF",
                                    textDecoration = "bold")

build_wb <- function(sheets) {
  wb <- openxlsx::createWorkbook()
  for (nm in names(sheets)) {
    df <- sheets[[nm]]
    openxlsx::addWorksheet(wb, nm)
    openxlsx::writeData(wb, nm, df, headerStyle = hdr)
    openxlsx::freezePane(wb, nm, firstActiveRow = 2,
                         firstActiveCol = if (nm == "A_patient_flags") 2 else 1)
    openxlsx::setColWidths(wb, nm, cols = seq_along(df), widths = "auto")
  }
  fail_rows <- which(recon$status == "FAIL")
  if ("E_reconciliation" %in% names(sheets) && length(fail_rows) > 0L) {
    openxlsx::addStyle(wb, "E_reconciliation", fail_style,
                       rows = fail_rows + 1L, cols = 4, gridExpand = TRUE)
  }
  wb
}

stamp <- format(Sys.Date(), "%Y-%m-%d")

# On failure: write a diagnosable QC-failure workbook, then stop (D-05).
if (any(recon$status == "FAIL")) {
  fail_path <- file.path(OUT_DIR, paste0("zip_problem_inventory_QC_FAILED_", stamp, ".xlsx"))
  openxlsx::saveWorkbook(
    build_wb(list(KEY = key_tbl, E_reconciliation = recon, QC = qc_tbl)),
    fail_path, overwrite = TRUE
  )
  cat("\nWrote QC-failure workbook:", fail_path, "\n")
  stop("Reconciliation against Phase 150 failed for: ",
       paste(recon$quantity[recon$status == "FAIL"], collapse = ", "),
       ". A flag predicate has drifted from R/120 — fix before shipping the roster.")
}
cat("\nReconciliation: all 8 quantities PASS\n\n")

cat("Patients in roster (>=1 flag):", nrow(roster), "of", n_all_patients, "\n")
print(as.data.frame(triage_summary), row.names = FALSE)

wb <- build_wb(list(
  KEY                 = key_tbl,          # leftmost per D-06
  A_patient_flags     = roster,
  B_flag_summary      = flag_summary,
  C_triage_summary    = triage_summary,
  D_record_mismatches = record_mismatches,
  E_reconciliation    = recon,
  QC                  = qc_tbl
))

out_xlsx <- file.path(OUT_DIR, paste0("zip_problem_inventory_", stamp, ".xlsx"))
out_rds  <- file.path(OUT_DIR, paste0("zip_problem_inventory_", stamp, ".rds"))

openxlsx::saveWorkbook(wb, out_xlsx, overwrite = TRUE)
saveRDS(list(patients = pat, roster = roster, flag_summary = flag_summary,
             triage_summary = triage_summary, record_mismatches = record_mismatches,
             reconciliation = recon, qc = qc_tbl), out_rds)

cat("\nWrote:", out_xlsx, "\n")
cat("Wrote:", out_rds, "\n")
cat("\n=== 121 done ===\n")
