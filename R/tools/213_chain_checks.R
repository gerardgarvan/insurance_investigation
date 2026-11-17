# R/tools/213_chain_checks.R
# Phase 213: expected-vs-actual checkpoint lines for the v3.15 chain rerun.
# Source after each chain step on HiPerGator:
#   source("R/tools/213_chain_checks.R"); chk_cohort(); chk_gantt_hl("output/gantt_episodes_180.csv")
# Prints counts only (no IDs, no data frames). Counts 1-10 print as "<11".
# Lives in R/tools/ (not auto-sourced). Base R only.

CHAIN_EXPECTED_COHORT <- 9179L   # Phase 212 final cohort (212-05-SUMMARY.md)

.fmt_n <- function(n) if (is.na(n)) "NA" else if (n >= 1L && n <= 10L) "<11" else format(n, big.mark = ",")

# One expected-vs-actual line. Returns TRUE when equal (invisible).
chk_expect <- function(label, expected, actual) {
  ok <- !is.na(actual) && !is.na(expected) && identical(as.numeric(expected), as.numeric(actual))
  message(sprintf("[213 CHECK] %-48s EXPECT %s | ACTUAL %s | %s",
                  label, .fmt_n(expected), .fmt_n(actual), if (ok) "OK" else "MISMATCH"))
  invisible(ok)
}

# Cohort rds: rows and distinct IDs both 9,179.
chk_cohort <- function(path = file.path("output", "confirmed_hl_cohort.rds"),
                       expected = CHAIN_EXPECTED_COHORT) {
  if (!file.exists(path)) stop("[213] missing: ", path)
  x <- readRDS(path)
  a <- chk_expect("cohort rows", expected, nrow(x))
  b <- chk_expect("cohort distinct IDs", expected, length(unique(x$ID)))
  invisible(a && b)
}

# Gantt-style CSV (patient_id, treatment_type): HL Diagnosis rows and distinct patients.
chk_gantt_hl <- function(path, expected = CHAIN_EXPECTED_COHORT, extra_expect = NULL) {
  if (!file.exists(path)) stop("[213] missing: ", path)
  d <- utils::read.csv(path, colClasses = "character", na.strings = "",
                       check.names = FALSE, stringsAsFactors = FALSE)
  if (!all(c("patient_id", "treatment_type") %in% names(d))) stop("[213] gantt lacks patient_id / treatment_type")
  hl <- d[!is.na(d$treatment_type) & d$treatment_type == "HL Diagnosis", ]
  message("[213] ", basename(path), ": ", .fmt_n(nrow(d)), " rows; ",
          .fmt_n(length(unique(d$patient_id))), " distinct patients")
  a <- chk_expect("HL Diagnosis rows", expected, nrow(hl))
  b <- chk_expect("HL Diagnosis distinct patients", expected, length(unique(hl$patient_id)))
  invisible(a && b)
}

# Share of a vector's distinct IDs that are in the cohort (not-in-cohort count expected 0).
chk_ids_in_cohort <- function(label, ids, cohort_path = file.path("output", "confirmed_hl_cohort.rds")) {
  coh <- readRDS(cohort_path)$ID
  chk_expect(paste0(label, ": IDs not in cohort"), 0L, sum(!unique(as.character(ids)) %in% as.character(coh)))
}

# Coverage (not equality): every cohort ID appears in `ids`. Expected missing = 0.
# Use where a script scopes wider than the cohort (R/169 uses get_hl_any_dx_ids()).
chk_cohort_covered <- function(label, ids, cohort_path = file.path("output", "confirmed_hl_cohort.rds")) {
  coh <- unique(as.character(readRDS(cohort_path)$ID))
  n_missing <- sum(!coh %in% unique(as.character(ids)))
  message("[213] ", label, ": distinct IDs ", .fmt_n(length(unique(ids))), "; cohort IDs ", .fmt_n(length(coh)))
  chk_expect(paste0(label, ": cohort IDs missing"), 0L, n_missing)
}

# Cohort-only Gantt file (user decision 2026-11-17): every patient_id is in the cohort and
# distinct patients equal the HL Diagnosis patient count (cohort size). Counts only.
chk_gantt_cohort_only <- function(path, cohort_path = file.path("output", "confirmed_hl_cohort.rds"),
                                  expected = CHAIN_EXPECTED_COHORT) {
  if (!file.exists(path)) stop("[213] missing: ", path)
  d <- utils::read.csv(path, colClasses = "character", na.strings = "",
                       check.names = FALSE, stringsAsFactors = FALSE)
  if (!all(c("patient_id", "treatment_type") %in% names(d))) stop("[213] gantt lacks patient_id / treatment_type")
  coh <- unique(as.character(readRDS(cohort_path)$ID))
  pts <- unique(d$patient_id)
  hl  <- unique(d$patient_id[!is.na(d$treatment_type) & d$treatment_type == "HL Diagnosis"])
  message("[213] ", basename(path), ": ", .fmt_n(nrow(d)), " rows; ", .fmt_n(length(pts)), " distinct patients")
  a <- chk_expect("patients not in cohort", 0L, sum(!pts %in% coh))
  b <- chk_expect("distinct patients == HL Diagnosis patients", length(hl), length(pts))
  c <- chk_expect("distinct patients == expected cohort", expected, length(pts))
  invisible(a && b && c)
}
