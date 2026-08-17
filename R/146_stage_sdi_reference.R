# R/146_stage_sdi_reference.R
#
# Stage the SDI reference file at the path R/116 probes.
#
# Input:  asset_rgc_sdi_2015_through_2019_zcta.csv  (repo root)
#         Raw columns include: ZCTA5_FIPS (5-digit ZCTA), SDI_score (numeric)
#
# Output: data/reference/zip5_sdi_reference.csv
#         Columns: ZIP5 (character, 5-digit zero-padded), SDI_score (numeric)
#
# R/116 SECTION 6 contract:
#   sdi_raw %>% select(ZIP5, sdi_score = SDI_score)
#   ZIP5 is then passed through normalize_zip5_raw(); SDI_score coerced to numeric.
#
# Vintage: 2015-2019 ACS 5-year (Robert Graham Center)
# Terms:   Review pending; commit approved by user 2026-08-17.
# D-01:    sdi_score is a ZCTA-level value attached through ZIP5 -- NOT a ZIP5-level measure.
#
# Usage:
#   Rscript R/146_stage_sdi_reference.R
#   (Run on Windows box or HiPerGator login node after downloading the raw file.)

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(here)
})

# ── Paths ──────────────────────────────────────────────────────────────────────
raw_path <- here("asset_rgc_sdi_2015_through_2019_zcta.csv")
out_path  <- here("data", "reference", "zip5_sdi_reference.csv")

# ── Load ───────────────────────────────────────────────────────────────────────
message("Reading raw SDI file: ", raw_path)

sdi_raw <- read_csv(
  raw_path,
  col_types = cols(
    ZCTA5_FIPS = col_character(),  # 5-digit ZCTA code; must be character to preserve leading zeros
    .default   = col_guess()
  ),
  progress = FALSE,
  show_col_types = FALSE
)

message("  Raw rows: ", nrow(sdi_raw))
message("  Raw columns: ", paste(names(sdi_raw), collapse = ", "))

# ── Validate expected columns ──────────────────────────────────────────────────
stopifnot(
  "ZCTA5_FIPS must be present in raw file" = "ZCTA5_FIPS" %in% names(sdi_raw),
  "SDI_score must be present in raw file"   = "SDI_score"  %in% names(sdi_raw)
)

# ── Restructure ────────────────────────────────────────────────────────────────
# Keep only ZIP5 (renamed from ZCTA5_FIPS) and SDI_score.
# Zero-pad to 5 characters so leading-zero ZCTAs are preserved.
sdi_ref <- sdi_raw %>%
  select(ZIP5 = ZCTA5_FIPS, SDI_score) %>%
  mutate(
    ZIP5      = stringr::str_pad(ZIP5, width = 5, side = "left", pad = "0"),
    SDI_score = as.numeric(SDI_score)
  ) %>%
  filter(!is.na(ZIP5), nchar(ZIP5) == 5L) %>%
  distinct(ZIP5, .keep_all = TRUE) %>%
  arrange(ZIP5)

message("  Output rows (distinct ZIP5 with non-NA): ", nrow(sdi_ref))

# Spot-check: confirm no non-5-char ZIP5 values slipped through
bad_len <- sum(nchar(sdi_ref$ZIP5) != 5L, na.rm = TRUE)
if (bad_len > 0L) {
  stop("BUG: ", bad_len, " rows have ZIP5 length != 5 after padding. Investigate.")
}

# ── Write ──────────────────────────────────────────────────────────────────────
dir.create(dirname(out_path), showWarnings = FALSE, recursive = TRUE)
write_csv(sdi_ref, out_path)
message("Wrote: ", out_path)
message("Header: ", paste(names(sdi_ref), collapse = ","))

# ── Verify ─────────────────────────────────────────────────────────────────────
check <- read_csv(out_path, col_types = cols(ZIP5 = col_character(), SDI_score = col_double()),
                  show_col_types = FALSE)
stopifnot(
  "ZIP5 column present"     = "ZIP5"      %in% names(check),
  "SDI_score column present" = "SDI_score" %in% names(check),
  "row count matches"        = nrow(check) == nrow(sdi_ref)
)
message("Verification PASSED — ZIP5/SDI_score present, ", nrow(check), " rows.")
message("First 3 ZIP5 values: ", paste(head(check$ZIP5, 3), collapse = ", "))
