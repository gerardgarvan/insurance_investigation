# R/117_build_svi_zcta.R
# Derive ZCTA-level SVI (2020) using the findSVI CRAN package.
#
# Decision: D-02a-i (findSVI) — confirmed in 146-DISCOVERY.md PART H, 2026-08-17.
#
# IMPORTANT COMPARABILITY CAVEAT:
#   findSVI percentile-ranks SVI against the national ZCTA universe.
#   CDC's published 2020 SVI ranks against the national census tract universe.
#   Same ACS variables, same CDC methodology, DIFFERENT reference population.
#   A findSVI RPL_THEMES value is NOT comparable to a CDC tract SVI value.
#   This caveat is recorded in the `method` column of every output row.
#
# Output: data/reference/svi_2020_zcta_derived.csv
#   Columns: ZCTA (character, 5-digit), RPL_THEMES (numeric, 0-1 or NA),
#            vintage (character), method (character), source (character).
#   NO svi_areal_coverage column — findSVI does no tract-to-ZCTA aggregation.
#
# Run on HiPerGator login node: Rscript R/117_build_svi_zcta.R
#
# Prerequisites (install interactively ONCE, then renv::snapshot()):
#   install.packages("findSVI")
#   install.packages("tidycensus")   # findSVI dependency
#   renv::snapshot()
#
# Census API key must be in ~/.Renviron on the machine running this script:
#   CENSUS_API_KEY=<your_key>
# Register free at: https://api.census.gov/data/key_signup.html
#
# DO NOT install packages inside a SLURM script.
# DO NOT hard-code the API key.
# ==============================================================================

suppressPackageStartupMessages({
  library(here)
  library(dplyr)
  library(readr)
  library(findSVI)
})

# ---- CONSTANTS ---------------------------------------------------------------

SVI_YEAR         <- 2020L
SVI_GEOGRAPHY    <- "zcta"
SVI_OUTPUT_PATH  <- here("data", "reference", "svi_2020_zcta_derived.csv")

# SVI_COVERAGE_FLOOR is defined here for reference only.
# D-02a-i (findSVI) does NO tract-to-ZCTA aggregation, so there is no partial
# coverage to measure and no floor to apply. This constant is retained so the
# script documents the threshold used in D-02a-ii (areal mean) for comparison;
# it has no effect on any computation in this script.
SVI_COVERAGE_FLOOR <- 0.80

# ---- STEP 1: Retrieve Census API key ----------------------------------------

census_key <- Sys.getenv("CENSUS_API_KEY")
if (nchar(census_key) == 0L) {
  stop(
    "CENSUS_API_KEY is not set. Add it to ~/.Renviron:\n",
    "  CENSUS_API_KEY=<your_key>\n",
    "Register free at https://api.census.gov/data/key_signup.html"
  )
}
message("Census API key found (length ", nchar(census_key), " chars).")

# ---- STEP 2: Derive SVI at ZCTA using findSVI --------------------------------

message("Calling findSVI::find_svi(year=", SVI_YEAR, ", geography=", SVI_GEOGRAPHY, ") ...")
message("This may take several minutes (Census API data retrieval).")

svi_raw <- findSVI::find_svi(
  year      = SVI_YEAR,
  geography = SVI_GEOGRAPHY,
  key       = census_key
)

message("findSVI returned ", nrow(svi_raw), " rows, ", ncol(svi_raw), " columns.")

# ---- STEP 3: Locate the RPL_THEMES column ------------------------------------
# findSVI returns composite SVI as RPL_themes or RPL_THEMES depending on version.
# Normalise to RPL_THEMES so the rest of the script is case-consistent.

rpl_col <- intersect(c("RPL_THEMES", "RPL_themes"), names(svi_raw))[1]
if (is.na(rpl_col)) {
  stop(
    "RPL_THEMES column not found in findSVI output.\n",
    "Available columns: ", paste(names(svi_raw), collapse = ", ")
  )
}
if (rpl_col != "RPL_THEMES") {
  svi_raw <- dplyr::rename(svi_raw, RPL_THEMES = !!rlang::sym(rpl_col))
}

# ---- STEP 4: Locate the ZCTA identifier column -------------------------------
# findSVI may return the ZCTA code under 'GEOID' or 'zcta'; normalise to 'ZCTA'.

zcta_col <- intersect(c("GEOID", "zcta", "ZCTA"), names(svi_raw))[1]
if (is.na(zcta_col)) {
  stop(
    "No ZCTA identifier column found in findSVI output.\n",
    "Available columns: ", paste(names(svi_raw), collapse = ", ")
  )
}
message("ZCTA identifier column: '", zcta_col, "'")

# ---- STEP 5: Clean and guard -------------------------------------------------

svi_clean <- svi_raw %>%
  # Rename to canonical output names
  rename(ZCTA = !!rlang::sym(zcta_col)) %>%
  # Guard: map RPL_THEMES < 0 (CDC -999 suppression) to NA BEFORE writing.
  # findSVI computes fresh from ACS so -999 is unlikely, but the guard is
  # applied unconditionally for defensive correctness.
  mutate(
    RPL_THEMES = if_else(RPL_THEMES < 0, NA_real_, RPL_THEMES),
    # Pad ZCTA to exactly 5 characters (leading zeros)
    ZCTA       = stringr::str_pad(as.character(ZCTA), width = 5, pad = "0", side = "left")
  ) %>%
  # Keep only rows with a parseable ZCTA
  filter(!is.na(ZCTA), nchar(ZCTA) == 5L)

message(
  "After cleaning: ", nrow(svi_clean), " ZCTA rows; ",
  sum(is.na(svi_clean$RPL_THEMES)), " RPL_THEMES = NA ",
  "(suppressed or missing)."
)

# ---- STEP 6: Add derivation metadata columns ---------------------------------

findSVI_version <- tryCatch(
  as.character(utils::packageVersion("findSVI")),
  error = function(e) "unknown"
)

svi_out <- svi_clean %>%
  select(ZCTA, RPL_THEMES) %>%
  mutate(
    vintage = "2020",
    method  = paste0(
      "findSVI CRAN package v", findSVI_version, ", ",
      "geography=zcta, year=2020; ",
      "percentile-ranked against ZCTAs (national ZCTA universe), ",
      "NOT comparable to CDC published 2020 SVI which is ranked against ",
      "census tracts. Same ACS variables and CDC methodology, different ",
      "reference population."
    ),
    source  = paste0(
      "ACS 2020 5-year estimates retrieved via Census API (api.census.gov); ",
      "findSVI CRAN package (https://CRAN.R-project.org/package=findSVI). ",
      "Original CDC SVI methodology: CDC/ATSDR GRASP, svi.cdc.gov."
    )
  ) %>%
  distinct(ZCTA, .keep_all = TRUE)

# ---- STEP 7: Write output CSV -----------------------------------------------

message("Writing output to: ", SVI_OUTPUT_PATH)

# Ensure output directory exists (it should, but guard for safety)
out_dir <- dirname(SVI_OUTPUT_PATH)
if (!dir.exists(out_dir)) {
  dir.create(out_dir, recursive = TRUE)
  message("Created directory: ", out_dir)
}

write_csv(svi_out, SVI_OUTPUT_PATH)

message(
  "Done. Wrote ", nrow(svi_out), " ZCTA rows to:\n  ", SVI_OUTPUT_PATH, "\n",
  "Columns: ", paste(names(svi_out), collapse = ", ")
)
message(
  "RPL_THEMES summary:\n",
  "  non-NA: ", sum(!is.na(svi_out$RPL_THEMES)), "\n",
  "  NA:     ", sum( is.na(svi_out$RPL_THEMES))
)
