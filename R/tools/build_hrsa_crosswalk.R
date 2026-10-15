# ==============================================================================
# build_hrsa_crosswalk.R -- One-off: download UDS Mapper crosswalk via zippeR
# ==============================================================================
#
# Purpose:
#   Downloads the HRSA UDS Mapper ZIP Code to ZCTA Crosswalk (2022 vintage,
#   the latest year available in zippeR at the time this was built) via
#   zippeR::zi_load_crosswalk() and writes it to data/reference/ as a plain
#   CSV so the pipeline can read it without a network call or zippeR dependency
#   at run time.
#
# Usage (interactive R, repo root, after installing zippeR):
#   source("R/tools/build_hrsa_crosswalk.R", local = new.env(parent = globalenv()))
#
# Output:
#   data/reference/hrsa_zip_zcta_2022.csv -- two columns: ZIP, ZCTA (5-digit,
#   character). Will not overwrite an existing file unless the environment
#   variable OVERWRITE_XWALK is set to "1".
#
# NOT part of the pipeline chain. Run once on HiPerGator, then snapshot renv.
# After this file is staged, R/122 reads it via load_hrsa_crosswalk().
# ==============================================================================

if (!requireNamespace("zippeR", quietly = TRUE))
  stop("zippeR is not installed. Run install.packages('zippeR') first.",
       call. = FALSE)

out_path <- here::here("data", "reference", "hrsa_zip_zcta_2022.csv")

if (file.exists(out_path) && Sys.getenv("OVERWRITE_XWALK") != "1") {
  message("[build_hrsa_crosswalk] File already exists -- skipping download.")
  message("  Set OVERWRITE_XWALK=1 to force rebuild.")
  message("  Path: ", out_path)
} else {

  message("[build_hrsa_crosswalk] Calling zippeR::zi_load_crosswalk(UDS, 2022)...")
  raw <- zippeR::zi_load_crosswalk(zip_source = "UDS", year = 2022)

  message("[build_hrsa_crosswalk] Raw columns: ", paste(names(raw), collapse = ", "))
  message("[build_hrsa_crosswalk] Raw rows:    ", nrow(raw))

  # Validate required columns (case-insensitive)
  nm <- toupper(trimws(names(raw)))
  zip_col  <- which(nm %in% c("ZIP_CODE", "ZIP"))[1]
  zcta_col <- which(nm == "ZCTA")[1]

  if (is.na(zip_col) || is.na(zcta_col))
    stop(
      "[build_hrsa_crosswalk] Expected ZIP_CODE (or ZIP) and ZCTA columns.\n",
      "  Available: ", paste(names(raw), collapse = ", "),
      call. = FALSE
    )

  pad5 <- function(v) {
    v <- gsub("[^0-9]", "", trimws(as.character(v)))
    ifelse(nchar(v) %in% 1:5,
           formatC(as.integer(v), width = 5, flag = "0"),
           NA_character_)
  }

  out <- data.frame(
    ZIP  = pad5(raw[[zip_col]]),
    ZCTA = pad5(raw[[zcta_col]]),
    stringsAsFactors = FALSE
  )
  out <- out[!is.na(out$ZIP), ]
  out <- out[!duplicated(out$ZIP), ]

  dir.create(dirname(out_path), showWarnings = FALSE, recursive = TRUE)
  utils::write.csv(out, out_path, row.names = FALSE)

  chk <- tools::md5sum(out_path)
  message("[build_hrsa_crosswalk] Written: ", out_path)
  message("  Rows:   ", nrow(out))
  message("  MD5:    ", chk)
  message("  Source: HRSA UDS crosswalk via zippeR 0.2.0 (zi_load_crosswalk), vintage 2022")
  message("[build_hrsa_crosswalk] Done. Run renv::snapshot() to lock zippeR.")
}
