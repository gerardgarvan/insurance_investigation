# 172_closeout_checks.R
# Read-only verification script for Phase 172 closeout.
# Prints to console; writes nothing to disk.
#
# Usage (after Task 2 instructions):
#   old_gantt <- c("<90-day _pre172.csv>", "<180-day _pre172.csv>")
#   new_gantt <- c("<new 90-day csv>",     "<new 180-day csv>")
#   old_r170  <- "output/internal/nhl_gantt_subsets_20261008.xlsx"
#   new_r170  <- list.files("output/internal", "^nhl_gantt_subsets_\\d{8}\\.xlsx$", full.names = TRUE) |>
#                  sort() |> tail(1)
#   source("scratch/172_closeout_checks.R")

stopifnot(exists("old_gantt"), exists("new_gantt"), exists("old_r170"), exists("new_r170"))
stopifnot(length(old_gantt) == 2L, length(new_gantt) == 2L)
stopifnot(length(new_r170)  == 1L, nchar(new_r170) > 0L)

library(readr)
library(dplyr)
library(openxlsx)

cat("\n=======================================================================\n")
cat("PART 1 — RENAME CHECK ON NEW GANTT FILES\n")
cat("=======================================================================\n")

bad_pat    <- "(?i)adriamycin|doxil|caelyx|liposom"
good_word  <- "Doxorubicin"

for (path in new_gantt) {
  cat("\nFile:", path, "\n")
  df <- readr::read_csv(path, col_types = cols(.default = col_character()),
                        show_col_types = FALSE)
  if (!"drug_names" %in% names(df)) {
    cat("  WARNING: no drug_names column\n"); next
  }
  n_bad  <- sum(grepl(bad_pat, df$drug_names, perl = TRUE, ignore.case = TRUE), na.rm = TRUE)
  n_good <- sum(grepl(good_word, df$drug_names, fixed = TRUE), na.rm = TRUE)
  cat(sprintf("  Rows matching Adriamycin/Doxil/Caelyx/liposom (expect 0): %d\n", n_bad))
  cat(sprintf("  Rows containing 'Doxorubicin' (expect > 0):              %d\n", n_good))
}

cat("\n=======================================================================\n")
cat("PART 2 — RECONCILIATION: old Gantt vs new Gantt (drug_names, patients)\n")
cat("=======================================================================\n")

# old_gantt[1] = pre-172 90-day, old_gantt[2] = pre-172 180-day
# new_gantt[1] = post-172 90-day, new_gantt[2] = post-172 180-day

for (i in seq_along(old_gantt)) {
  label <- if (i == 1L) "90-day Gantt (gantt_episodes)" else "180-day Gantt (gantt_episodes_180)"
  cat(sprintf("\n--- %s ---\n", label))

  old <- readr::read_csv(old_gantt[i], col_types = cols(.default = col_character()),
                         show_col_types = FALSE)
  new <- readr::read_csv(new_gantt[i], col_types = cols(.default = col_character()),
                         show_col_types = FALSE)

  dox_pat_old <- "(?i)adriamycin|doxorubicin|liposom|doxil|caelyx"
  dox_pat_new <- "Doxorubicin"

  pid_col <- if ("patient_id" %in% names(old)) "patient_id" else names(old)[1]

  n_old_pts <- old |> dplyr::filter(grepl(dox_pat_old, drug_names, perl=TRUE, ignore.case=TRUE)) |>
    dplyr::pull(!!pid_col) |> dplyr::n_distinct()
  n_new_pts <- new |> dplyr::filter(grepl(dox_pat_new, drug_names, fixed=TRUE)) |>
    dplyr::pull(!!pid_col) |> dplyr::n_distinct()

  cat(sprintf("  Old distinct patients with any doxorubicin/adriamycin variant: %d\n", n_old_pts))
  cat(sprintf("  New distinct patients with 'Doxorubicin':                       %d\n", n_new_pts))
  cat(sprintf("  Patient count change (expect 0):                                %d\n", n_new_pts - n_old_pts))

  cat(sprintf("  Old row count: %d\n", nrow(old)))
  cat(sprintf("  New row count: %d\n", nrow(new)))
  cat(sprintf("  Row delta:     %d\n", nrow(new) - nrow(old)))

  # How many old rows that carried a dox alias became duplicates after canonicalisation
  if ("episode_number" %in% names(old) && "drug_names" %in% names(old)) {
    n_alias_old <- old |>
      dplyr::filter(grepl(bad_pat, drug_names, perl=TRUE, ignore.case=TRUE)) |> nrow()
    cat(sprintf("  Old rows with alias names (collapse candidates): %d\n", n_alias_old))
  }
}

cat("\n=======================================================================\n")
cat("PART 3 — R/170 REGRESSION: old run vs new run\n")
cat("=======================================================================\n")

read_qc <- function(path) {
  wb  <- openxlsx::loadWorkbook(path)
  qc  <- openxlsx::readWorkbook(wb, sheet = "QC", colNames = TRUE)
  names(qc) <- c("QC_Field", "QC_Value")
  qc
}

qc_old <- read_qc(old_r170)
qc_new <- read_qc(new_r170)

# Key fields to compare (section headers are dashes, skip them)
key_fields <- c(
  "Group 1 strict (all-NHL, no HL, no HL+NHL)",
  "Group 1 loose  (any NHL)",
  "Group 2        (any HL+NHL)",
  "Group overlap count",
  "Sheet eps matched to chemo rows (G1)",
  "Sheet eps unmatched (G1)",
  "Chemo gantt rows matched to sheet (G1)",
  "Chemo gantt rows unmatched (G1)",
  "Sheet eps matched to chemo rows (G2)",
  "Sheet eps unmatched (G2)",
  "Chemo gantt rows matched to sheet (G2)",
  "Chemo gantt rows unmatched (G2)",
  "Exact matches",
  "Normalised-only",
  "Real mismatches",
  "One side missing",
  "NA-key sheet rows",
  "Gantt chemo duplicate (patient_id,episode_number) pairs",
  "Sheet duplicate (patient_id,episode_number) pairs",
  "Count of rows with unexpected values",
  "Snapshot size bytes",
  "Snapshot MD5"
)

old_lookup <- setNames(qc_old$QC_Value, qc_old$QC_Field)
new_lookup <- setNames(qc_new$QC_Value, qc_new$QC_Field)

cat(sprintf("\n%-60s %-18s %-18s %s\n", "QC Field", "Old (20261008)", "New", "Match?"))
cat(strrep("-", 110), "\n")

all_match <- TRUE
for (fld in key_fields) {
  ov <- old_lookup[fld] %||% "(absent)"
  nv <- new_lookup[fld] %||% "(absent)"
  ok <- identical(as.character(ov), as.character(nv))
  if (!ok) all_match <- FALSE
  flag <- if (ok) "OK" else "*** DIFF ***"
  cat(sprintf("%-60s %-18s %-18s %s\n",
              substr(fld, 1, 58), substr(ov, 1, 16), substr(nv, 1, 16), flag))
}

cat("\n")
if (all_match) {
  cat("RESULT: R/170 regression PASS — all key QC fields match 2026-10-08 run.\n")
} else {
  cat("RESULT: R/170 regression FAIL — differences found above.\n")
}

# Tab row counts
cat("\nEpisode tab row counts:\n")
for (sheet in c("NHL_only_episodes", "HL_NHL_episodes")) {
  read_rows <- function(path, sh) {
    tryCatch(nrow(openxlsx::readWorkbook(openxlsx::loadWorkbook(path), sheet = sh, colNames = TRUE)),
             error = function(e) NA_integer_)
  }
  n_old <- read_rows(old_r170, sheet)
  n_new <- read_rows(new_r170, sheet)
  cat(sprintf("  %-30s old=%s  new=%s  delta=%s\n",
              sheet, n_old, n_new, if (!is.na(n_old) && !is.na(n_new)) n_new - n_old else "NA"))
}

cat("\n=======================================================================\n")
cat("Done. Paste this output into the Phase 172 checkpoint.\n")
cat("=======================================================================\n")
