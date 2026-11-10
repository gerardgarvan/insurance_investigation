# ==============================================================================
# 165_validate_workbook.R -- Standalone validator for R/165 output workbook
# ==============================================================================
#
# Purpose:
#   Run nine structural and content checks on the distance_cbc_association_*.xlsx
#   workbook produced by R/165_distance_cbc_association.R. Prints PASS/FAIL per
#   check; calls stop() on the first FAIL.
#
# Usage:
#   source("R/165_validate_workbook.R", local = new.env(parent = globalenv()))
#   # Optionally: Sys.setenv(R165_VALIDATE_WB = "output/distance_cbc_association_YYYYMMDD.xlsx")
#
# Argument (via env var or interactive prompt):
#   R165_VALIDATE_WB -- path to workbook; default = most recent
#     output/distance_cbc_association_*.xlsx (pin note: set env var for reproducibility).
#
# Checks:
#   1  No dangling drawing rels in archive (unzip list)
#   2  KEY is sheet 1, SUMMARY is sheet 2
#   3  A_crosstab Whole record Total == B_test Whole record N_enc; Post likewise
#   4  SOURCE_REASSIGN_QC has all four methods and address > 0
#   5  Each _addr sheet differs from its _flm sheet (at least one cell differs)
#   6  Every BY_SOURCE sheet has an MH_POOLED row per window with BD_chi2 and BD_p
#   7  Pat-sheet stratum n_far+n_not_far totals sum to patient N per window
#   8  No row with a "<11" cell has a non-blank OR/CI/p; no visible pct 0%/100% next to suppressed count
#   9  No C_sensitivity SOURCE coefficient |log-OR| > 5
#
# ==============================================================================

source(here::here("R/00_config.R"))
suppressPackageStartupMessages(library(openxlsx))

wb_path_env <- Sys.getenv("R165_VALIDATE_WB", unset = "")
if (nzchar(wb_path_env)) {
  WB_PATH <- wb_path_env
  message("[validate] Using workbook from R165_VALIDATE_WB: ", WB_PATH)
} else {
  candidates <- list.files(
    CONFIG$output_dir,
    pattern = "^distance_cbc_association.*\\.xlsx$",
    full.names = TRUE
  )
  if (length(candidates) == 0L)
    stop("[validate] No distance_cbc_association_*.xlsx found in ", CONFIG$output_dir,
         ". Set R165_VALIDATE_WB to the workbook path.")
  WB_PATH <- candidates[which.max(file.mtime(candidates))]
  message("[validate] Pin note: set R165_VALIDATE_WB for reproducibility. Using: ", WB_PATH)
}
if (!file.exists(WB_PATH))
  stop("[validate] Workbook not found: ", WB_PATH)

message("[validate] Validating: ", WB_PATH)

pass_fail <- function(check_name, passed, msg = NULL) {
  status <- if (passed) "PASS" else "FAIL"
  cat(sprintf("  %-60s [%s]\n", check_name, status))
  if (!passed) {
    detail <- if (!is.null(msg)) msg else "check failed"
    stop("[validate] FAIL — ", check_name, ": ", detail)
  }
  invisible(passed)
}

# ---------------------------------------------------------------------------
# Check 1: No dangling drawing relationships
# ---------------------------------------------------------------------------
{
  archive_entries <- utils::unzip(WB_PATH, list = TRUE)$Name
  rel_entries     <- archive_entries[grepl("xl/worksheets/_rels/sheet.*\\.rels$", archive_entries)]
  dangling <- character(0)
  if (length(rel_entries) > 0L) {
    tmp_dir <- tempfile()
    dir.create(tmp_dir)
    utils::unzip(WB_PATH, files = rel_entries, exdir = tmp_dir)
    for (rel_file in rel_entries) {
      full_path <- file.path(tmp_dir, rel_file)
      if (!file.exists(full_path)) next
      rel_text  <- paste(readLines(full_path, warn = FALSE), collapse = "")
      targets <- regmatches(rel_text, gregexpr('Target="[^"]*drawing[^"]*"', rel_text))[[1]]
      targets <- gsub('Target="|"$', "", targets)
      for (tgt in targets) {
        normalized <- gsub("^\\.\\./", "xl/", tgt)
        if (!normalized %in% archive_entries) dangling <- c(dangling, tgt)
      }
    }
    unlink(tmp_dir, recursive = TRUE)
  }
  pass_fail("1. No dangling drawing rels in archive", length(dangling) == 0L,
            if (length(dangling) > 0L) paste("dangling:", paste(dangling, collapse=", ")) else NULL)
}

# ---------------------------------------------------------------------------
# Check 2: KEY is sheet 1, SUMMARY is sheet 2
# ---------------------------------------------------------------------------
{
  sheet_names <- openxlsx::getSheetNames(WB_PATH)
  pass_fail("2. KEY is sheet 1", length(sheet_names) >= 1L && sheet_names[1] == "KEY",
            paste0("sheet 1 = '", if(length(sheet_names)>=1) sheet_names[1] else "(none)", "'"))
  pass_fail("2. SUMMARY is sheet 2", length(sheet_names) >= 2L && sheet_names[2] == "SUMMARY",
            paste0("sheet 2 = '", if(length(sheet_names)>=2) sheet_names[2] else "(none)", "'"))
}

# ---------------------------------------------------------------------------
# Check 3: A_crosstab totals match B_test N_enc
# ---------------------------------------------------------------------------
{
  a_df <- tryCatch(openxlsx::read.xlsx(WB_PATH, sheet = "A_crosstab", colNames = FALSE),
                   error = function(e) NULL)
  b_df <- tryCatch(openxlsx::read.xlsx(WB_PATH, sheet = "B_test", colNames = TRUE),
                   error = function(e) NULL)
  if (!is.null(a_df) && !is.null(b_df) && "N_enc" %in% names(b_df)) {
    # A_crosstab: "Total" row in col 4 for each window block
    # Total row is row 5 (1=header, 2=col-headers, 3=far=0, 4=far=1, 5=Total)
    # col 4 is the Total column in the count block
    total_row_whole <- suppressWarnings(as.integer(as.character(a_df[5L, 4L])))
    total_row_post  <- suppressWarnings(as.integer(as.character(a_df[5L, 9L])))
    b_nenc_whole <- suppressWarnings(as.integer(gsub(",", "", as.character(
      b_df$N_enc[b_df$Window == "Whole record"]))))
    b_nenc_post  <- suppressWarnings(as.integer(gsub(",", "", as.character(
      b_df$N_enc[b_df$Window == "Post-anchor"]))))
    if (!is.na(total_row_whole) && length(b_nenc_whole) == 1L && !is.na(b_nenc_whole))
      pass_fail("3. A_crosstab whole Total == B_test N_enc whole",
                total_row_whole == b_nenc_whole,
                paste0("A=", total_row_whole, " B=", b_nenc_whole))
    if (!is.na(total_row_post) && length(b_nenc_post) == 1L && !is.na(b_nenc_post))
      pass_fail("3. A_crosstab post Total == B_test N_enc post",
                total_row_post == b_nenc_post,
                paste0("A=", total_row_post, " B=", b_nenc_post))
    if (is.na(total_row_whole) || is.na(total_row_post) ||
        length(b_nenc_whole) != 1L || length(b_nenc_post) != 1L) {
      message("  3. A_crosstab vs B_test totals: could not parse — skipping numeric comparison")
    }
  } else {
    message("  3. A_crosstab or B_test not found — skipping check 3")
  }
}

# ---------------------------------------------------------------------------
# Check 4: SOURCE_REASSIGN_QC has all four methods and address > 0
# ---------------------------------------------------------------------------
{
  qc_df <- tryCatch(openxlsx::read.xlsx(WB_PATH, sheet = "SOURCE_REASSIGN_QC", colNames = TRUE),
                    error = function(e) NULL)
  if (!is.null(qc_df) && "source_reassign_method" %in% names(qc_df)) {
    expected_methods <- c("address", "modal_encounter", "unresolved", "not_reassigned")
    methods_present  <- all(expected_methods %in% qc_df$source_reassign_method)
    pass_fail("4a. SOURCE_REASSIGN_QC has all four methods", methods_present,
              paste0("missing: ", paste(setdiff(expected_methods, qc_df$source_reassign_method), collapse=", ")))
    addr_row <- qc_df[qc_df$source_reassign_method == "address", ]
    addr_n   <- suppressWarnings(as.integer(gsub(",", "", as.character(addr_row$n_encounters[1]))))
    pass_fail("4b. SOURCE_REASSIGN_QC address > 0 encounters", !is.na(addr_n) && addr_n > 0,
              paste0("address n_encounters = ", if(is.na(addr_n)) "NA or suppressed" else addr_n))
  } else {
    message("  4. SOURCE_REASSIGN_QC not found or missing source_reassign_method column")
  }
}

# ---------------------------------------------------------------------------
# Check 5: Each _addr sheet differs from its _flm counterpart
# ---------------------------------------------------------------------------
{
  sheet_pairs <- list(
    list(addr = "BY_SOURCE_enc_addr", flm = "BY_SOURCE_enc_flm"),
    list(addr = "BY_SOURCE_pat_addr", flm = "BY_SOURCE_pat_flm")
  )
  all_sheets <- openxlsx::getSheetNames(WB_PATH)
  for (pair in sheet_pairs) {
    if (pair$addr %in% all_sheets && pair$flm %in% all_sheets) {
      df_addr <- openxlsx::read.xlsx(WB_PATH, sheet = pair$addr, colNames = TRUE)
      df_flm  <- openxlsx::read.xlsx(WB_PATH, sheet = pair$flm,  colNames = TRUE)
      differs <- !identical(df_addr, df_flm)
      pass_fail(paste0("5. ", pair$addr, " differs from ", pair$flm), differs,
                "sheets are identical — address reassignment may be a no-op")
    } else {
      message("  5. Sheet pair not found: ", pair$addr, " / ", pair$flm, " — skipping")
    }
  }
}

# ---------------------------------------------------------------------------
# Check 6: Every BY_SOURCE sheet has MH_POOLED with BD_chi2 and BD_p
# ---------------------------------------------------------------------------
{
  by_src_sheets <- openxlsx::getSheetNames(WB_PATH)
  by_src_sheets <- by_src_sheets[grepl("^BY_SOURCE_", by_src_sheets)]
  for (sht in by_src_sheets) {
    df <- tryCatch(openxlsx::read.xlsx(WB_PATH, sheet = sht, colNames = TRUE), error = function(e) NULL)
    if (is.null(df)) { message("  6. Could not read sheet: ", sht); next }
    has_mh_whole <- any(df$SOURCE_analytic == "MH_POOLED" & df$window == "Whole record", na.rm = TRUE)
    has_mh_post  <- any(df$SOURCE_analytic == "MH_POOLED" & df$window == "Post-anchor",  na.rm = TRUE)
    has_bd_chi2  <- "BD_chi2" %in% names(df)
    has_bd_p     <- "BD_p"    %in% names(df)
    pass_fail(paste0("6. ", sht, ": MH_POOLED whole + post + BD cols"),
              has_mh_whole && has_mh_post && has_bd_chi2 && has_bd_p,
              paste0("mh_whole=", has_mh_whole, " mh_post=", has_mh_post,
                     " BD_chi2=", has_bd_chi2, " BD_p=", has_bd_p))
  }
}

# ---------------------------------------------------------------------------
# Check 7: Pat-sheet stratum n_far+n_not_far totals sum to patient N per window
# ---------------------------------------------------------------------------
{
  pat_sheets <- c("BY_SOURCE_pat", "BY_SOURCE_pat_addr", "BY_SOURCE_pat_flm")
  pat_sheets <- pat_sheets[pat_sheets %in% openxlsx::getSheetNames(WB_PATH)]
  for (sht in pat_sheets) {
    df <- tryCatch(openxlsx::read.xlsx(WB_PATH, sheet = sht, colNames = TRUE), error = function(e) NULL)
    if (is.null(df) || !all(c("SOURCE_analytic","n_far","n_not_far","window") %in% names(df))) next
    for (win in c("Whole record", "Post-anchor")) {
      stratum_rows <- df[df$window == win & df$SOURCE_analytic != "MH_POOLED", ]
      n_far_vals   <- suppressWarnings(as.integer(gsub(",","", as.character(stratum_rows$n_far))))
      n_notf_vals  <- suppressWarnings(as.integer(gsub(",","", as.character(stratum_rows$n_not_far))))
      if (any(is.na(n_far_vals)) || any(is.na(n_notf_vals))) {
        message("  7. ", sht, " ", win, ": suppressed cells — skipping total sum check")
        next
      }
      stratum_sum <- sum(n_far_vals + n_notf_vals, na.rm = TRUE)
      # Verify via B_test N_pat for the same window
      b_df2 <- tryCatch(openxlsx::read.xlsx(WB_PATH, sheet = "B_test", colNames = TRUE),
                        error = function(e) NULL)
      if (!is.null(b_df2) && "N_pat" %in% names(b_df2)) {
        b_npat <- suppressWarnings(as.integer(gsub(",","", as.character(
          b_df2$N_pat[b_df2$Window == win]))))
        if (length(b_npat) == 1L && !is.na(b_npat) && !is.na(stratum_sum)) {
          pass_fail(paste0("7. ", sht, " ", win, ": stratum totals == patient N"),
                    stratum_sum == b_npat,
                    paste0("stratum_sum=", stratum_sum, " N_pat=", b_npat))
        }
      }
    }
  }
}

# ---------------------------------------------------------------------------
# Check 8: No <11 row has non-blank OR/CI/p; no visible pct 0%/100% next to suppressed count
# ---------------------------------------------------------------------------
{
  all_sheets <- openxlsx::getSheetNames(WB_PATH)
  by_src_all <- all_sheets[grepl("^BY_SOURCE_", all_sheets)]
  for (sht in by_src_all) {
    df <- tryCatch(openxlsx::read.xlsx(WB_PATH, sheet = sht, colNames = TRUE), error = function(e) NULL)
    if (is.null(df)) next
    count_cols <- intersect(c("n_far","n_not_far","n_cbc_far","n_cbc_not_far"), names(df))
    stat_cols  <- intersect(c("OR","CI_lo","CI_hi","p_value"), names(df))
    pct_cols   <- intersect(c("pct_far_with_cbc","pct_not_far_with_cbc"), names(df))
    pct_denom  <- c("n_far","n_not_far")
    fail_msg <- character(0)
    for (ri in seq_len(nrow(df))) {
      row_supp <- any(vapply(count_cols, function(col) {
        v <- as.character(df[ri, col]); !is.na(v) && trimws(v) == "<11"
      }, logical(1L)))
      if (row_supp) {
        # Stats must be blank (NA or empty)
        for (col in stat_cols) {
          v <- df[ri, col]
          if (!is.na(v) && nchar(trimws(as.character(v))) > 0) {
            fail_msg <- c(fail_msg, paste0("row ", ri, " col ", col, " = '", v, "' despite suppressed count"))
          }
        }
      }
      # pct 0%/100% next to suppressed count
      for (pi in seq_along(pct_cols)) {
        pct_col  <- pct_cols[pi]
        denom_col <- if (pi <= length(pct_denom)) pct_denom[pi] else NA_character_
        pct_val  <- as.character(df[ri, pct_col])
        if (!is.na(pct_col) && !is.na(pct_val) && trimws(pct_val) %in% c("0.0%","100.0%")) {
          if (!is.na(denom_col) && denom_col %in% names(df)) {
            denom_v <- as.character(df[ri, denom_col])
            if (!is.na(denom_v) && trimws(denom_v) == "<11") {
              fail_msg <- c(fail_msg, paste0("row ", ri, " ", pct_col,
                "=", pct_val, " with suppressed denominator ", denom_col))
            }
          }
        }
      }
    }
    pass_fail(paste0("8. ", sht, ": no non-blank stat for suppressed row"),
              length(fail_msg) == 0L,
              if (length(fail_msg) > 0L) paste(fail_msg[1:min(3,length(fail_msg))], collapse="; ") else NULL)
  }
}

# ---------------------------------------------------------------------------
# Check 9: No C_sensitivity SOURCE coefficient |log-OR| > 5
# ---------------------------------------------------------------------------
{
  c_df <- tryCatch(openxlsx::read.xlsx(WB_PATH, sheet = "C_sensitivity", colNames = TRUE),
                   error = function(e) NULL)
  if (!is.null(c_df) && "OR" %in% names(c_df)) {
    # Find rows with SOURCE in Field column (coefficient table rows)
    or_col <- c_df$OR
    # Only check rows that look like SOURCE coefficient rows (non-NA OR values that are plausibly model outputs)
    or_vals <- suppressWarnings(as.numeric(as.character(or_col)))
    log_or_vals <- log(or_vals[!is.na(or_vals) & or_vals > 0])
    large_lor   <- log_or_vals[!is.na(log_or_vals) & abs(log_or_vals) > 5]
    pass_fail("9. C_sensitivity no |log-OR| > 5", length(large_lor) == 0L,
              paste0("found |log-OR| > 5: ", paste(round(large_lor, 2), collapse=", ")))
  } else {
    # C_sensitivity may not have an OR column; check coef table structure
    message("  9. C_sensitivity OR column not found — checking via Field/Value structure")
    if (!is.null(c_df) && "Value" %in% names(c_df)) {
      or_rows <- c_df[grepl("OR|Estimate", as.character(c_df[[1]]), ignore.case=TRUE), ]
      or_vals <- suppressWarnings(as.numeric(as.character(or_rows$Value)))
      log_or_vals <- log(or_vals[!is.na(or_vals) & or_vals > 0])
      large_lor <- log_or_vals[!is.na(log_or_vals) & abs(log_or_vals) > 5]
      pass_fail("9. C_sensitivity no |log-OR| > 5 (via OR rows)", length(large_lor) == 0L,
                paste0("found |log-OR| > 5: ", paste(round(large_lor, 2), collapse=", ")))
    } else {
      message("  9. C_sensitivity structure not parseable — skipping check 9")
    }
  }
}

message("[validate] All checks complete: ", WB_PATH)
