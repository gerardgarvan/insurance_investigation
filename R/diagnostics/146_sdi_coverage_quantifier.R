# R/diagnostics/146_sdi_coverage_quantifier.R
#
# Quantify the ZIP5-with-no-ZCTA haircut for SDI coverage.
#
# This script computes BOTH figures required by 146-03 CONTEXT.md §3a:
#
#   (a) DISTINCT CODES -- how many unique non-NA cohort ZIP5 codes lack a ZCTA counterpart.
#       sum(zips %in% sdi$ZIP5)   --> matched distinct codes
#       sum(!zips %in% sdi$ZIP5)  --> unmatched distinct codes (ZIP5s with no corresponding ZCTA)
#       (a) alone is misleading: a rare code and a high-volume code weigh the same.
#
#   (b) ENCOUNTER-WEIGHTED COVERAGE -- the coverage figure reported in the deliverable.
#       sum(!is.na(enc$ZIP5) & enc$ZIP5 %in% sdi$ZIP5) / nrow(enc)
#       Denominates over ALL encounters (including those without a usable ZIP5),
#       consistent with the 77.7% ceiling denominator.
#
# The unmatched count from (a)/(b) is the SECOND HAIRCUT below the 77.7% ceiling.
# Label for the 146-05 coverage sheet: "ZIP5s with no corresponding ZCTA"
#
# Prerequisites:
#   - data/reference/zip5_sdi_reference.csv  (staged by 146-03 / R/146_stage_sdi_reference.R)
#   - output/encounter_ses_index_<date>.rds  (produced by R/116_encounter_ses_index.R)
#
# Usage (HiPerGator login or compute node after 146-06 job completes):
#   Rscript R/diagnostics/146_sdi_coverage_quantifier.R
#
# RESULT: PENDING HiPerGator run -- do NOT run on this Windows planning box.
#         No PCORnet encounter data is available here.

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(here)
  library(glue)
})

# ── Paths ──────────────────────────────────────────────────────────────────────
sdi_path <- here("data", "reference", "zip5_sdi_reference.csv")

# R/116 outputs are dated; find the most recent encounter_ses_index RDS.
enc_files <- list.files(here("output"), pattern = "^encounter_ses_index_.*\\.rds$", full.names = TRUE)
if (length(enc_files) == 0L) {
  stop(
    "No encounter_ses_index_<date>.rds found in output/. ",
    "Run R/116_encounter_ses_index.R on HiPerGator first (Phase 146 plan 146-06)."
  )
}
enc_path <- enc_files[length(enc_files)]  # lexicographically last = most recent date

# ── Load ───────────────────────────────────────────────────────────────────────
message("Loading SDI reference: ", sdi_path)
sdi <- read_csv(
  sdi_path,
  col_types = cols(ZIP5 = col_character(), SDI_score = col_double()),
  show_col_types = FALSE
)
message("  SDI rows: ", nrow(sdi))

message("Loading encounter SES index: ", enc_path)
enc <- readRDS(enc_path)
message("  Encounter rows: ", nrow(enc))

# Confirm ZIP5 column is present in encounter data (R/116 names it ZIP5 after normalize_zip5_raw).
if (!"ZIP5" %in% names(enc)) {
  stop(
    "ZIP5 column not found in encounter RDS. Available columns: ",
    paste(names(enc), collapse = ", ")
  )
}

# ── (a) Distinct-code matched/unmatched count ──────────────────────────────────
message("\n--- (a) DISTINCT CODES ---")

zips <- enc %>%
  filter(!is.na(ZIP5)) %>%
  distinct(ZIP5) %>%
  pull(ZIP5)

n_unique_zips    <- length(zips)
n_matched_codes  <- sum(zips %in% sdi$ZIP5)
n_unmatched_codes <- sum(!zips %in% sdi$ZIP5)

message(glue("  Unique non-NA cohort ZIP5 codes:  {n_unique_zips}"))
message(glue("  Matched to SDI ZCTA (has a ZCTA): {n_matched_codes}"))
message(glue("  UNMATCHED (ZIP5s with no corresponding ZCTA): {n_unmatched_codes}"))
message(glue("  Code-level match rate: {round(100 * n_matched_codes / n_unique_zips, 1)}%"))

# ── (b) Encounter-weighted coverage ───────────────────────────────────────────
message("\n--- (b) ENCOUNTER-WEIGHTED COVERAGE ---")

n_enc_total          <- nrow(enc)
n_enc_has_zip5       <- sum(!is.na(enc$ZIP5))
n_enc_sdi_matched    <- sum(!is.na(enc$ZIP5) & enc$ZIP5 %in% sdi$ZIP5)
n_enc_zip5_no_zcta   <- sum(!is.na(enc$ZIP5) & !(enc$ZIP5 %in% sdi$ZIP5))

pct_sdi_covered      <- round(100 * n_enc_sdi_matched / n_enc_total, 1)
pct_zip5_no_zcta     <- round(100 * n_enc_zip5_no_zcta / n_enc_total, 1)

message(glue("  Total encounters (denominator): {n_enc_total}"))
message(glue("  Encounters with non-NA ZIP5:    {n_enc_has_zip5}"))
message(glue("  Encounters matched to SDI ZCTA: {n_enc_sdi_matched} ({pct_sdi_covered}%)"))
message(glue("  Encounters with ZIP5 but no corresponding ZCTA: {n_enc_zip5_no_zcta} ({pct_zip5_no_zcta}%)"))
message(glue("  (For reference, 77.7% ceiling = max possible if every ZIP5 had a ZCTA)"))
message(glue("  Second haircut below 77.7% ceiling: {pct_zip5_no_zcta}% of encounters"))

# ── Summary ────────────────────────────────────────────────────────────────────
message("\n=== SDI COVERAGE SUMMARY ===")
message(glue("  (a) Distinct ZIP5 codes with no corresponding ZCTA: {n_unmatched_codes} / {n_unique_zips}"))
message(glue("  (b) Encounter-weighted SDI coverage: {pct_sdi_covered}% ({n_enc_sdi_matched} / {n_enc_total})"))
message(glue("  Coverage sheet label (146-05): 'ZIP5s with no corresponding ZCTA'"))
message(glue("  Record these figures in 146-DISCOVERY.md PART I (replace PENDING)."))
