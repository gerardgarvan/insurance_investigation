# ==============================================================================
# 147_verify_vs_1006.R -- Fail-safe PASS/FAIL harness: R/147 output vs 1006 ref
# ==============================================================================
# Compares today's INTERNAL surveillance_modality_frequency_INTERNAL_<run_date>.xlsx
# and surveillance_patient_modality_dates_<run_date>.rds against the 2026-10-06
# INTERNAL reference, accounting for Phase 163 DIAGNOSIS exclusion.
#
# Usage:
#   export VERIFY_RUN_DATE=20261009   # optional; defaults to today
#   Rscript R/147_verify_vs_1006.R
#
# Always writes OVERALL: PASS or OVERALL: FAIL to the log and exits with code
# 0 (PASS) or 1 (FAIL).  No stop() outside check functions.
#
# See .planning/phases/170-r147-rerun-and-verification/170-BASELINE-DRIFT.md
# for drift analysis and expected_differences rationale.
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(readxl)
  library(glue)
})

source("R/00_config.R")

# ==============================================================================
# A. DATES AND PATHS
# ==============================================================================
run_date <- Sys.getenv("VERIFY_RUN_DATE", unset = format(Sys.Date(), "%Y%m%d"))
out_dir  <- CONFIG$cache$outputs_dir

ref_path     <- file.path(out_dir, "surveillance_modality_frequency_INTERNAL_20261006.xlsx")
new_path     <- file.path(out_dir, glue("surveillance_modality_frequency_INTERNAL_{run_date}.xlsx"))
ref_rds_path <- file.path(out_dir, "surveillance_patient_modality_dates_20261006.rds")
new_rds_path <- file.path(out_dir, glue("surveillance_patient_modality_dates_{run_date}.rds"))

EXCLUDED_IDS  <- c("SC039", "SC047", "SC065", "SC090")
CHANGED_MODS  <- c("Echocardiogram", "Electrocardiogram", "Mammogram", "Pulmonary function test")

# EXPECTED_DIFFS: check names that should SKIP instead of FAIL.
# Phase 163 outcomes are all positively asserted — no checks need to be skipped.
# See 170-BASELINE-DRIFT.md expected_differences section.
EXPECTED_DIFFS <- character(0)

# ==============================================================================
# B. SINK FIRST (before any check)
# ==============================================================================
log_dir  <- file.path(CONFIG$output_dir, "logs")
dir.create(log_dir, showWarnings = FALSE, recursive = TRUE)
log_path <- file.path(log_dir, glue("147_verify_vs_1006_{run_date}.txt"))
con      <- file(log_path, open = "wt")
sink(con, split = TRUE)

cat("run_date:", run_date, "\n")
cat("REF:", ref_path, "\n")
cat("NEW:", new_path, "\n")
cat("REF_RDS:", ref_rds_path, "\n")
cat("NEW_RDS:", new_rds_path, "\n\n")

results <- list()

# ==============================================================================
# C. INPUT FILE CHECKS (missing file → FAIL result, not stop())
# ==============================================================================
if (!file.exists(ref_path))  results[["input:ref_workbook"]]  <- glue("FAIL — reference workbook missing: {ref_path}")
if (!file.exists(new_path))  results[["input:new_workbook"]]  <- glue("FAIL — new workbook missing: {new_path}")
if (!file.exists(ref_rds_path)) results[["input:ref_rds"]]   <- glue("FAIL — reference RDS missing: {ref_rds_path}")
if (!file.exists(new_rds_path)) results[["input:new_rds"]]   <- glue("FAIL — new RDS missing: {new_rds_path}")

# ==============================================================================
# D. HELPERS
# ==============================================================================

run_check <- function(name, fn) {
  if (name %in% EXPECTED_DIFFS) {
    results[[name]] <<- glue("SKIP — expected difference (see 170-BASELINE-DRIFT.md)")
    return(invisible())
  }
  results[[name]] <<- tryCatch(fn(), error = function(e) glue("FAIL — error: {conditionMessage(e)}"))
}

# Read a sheet; return NULL silently if absent or file missing.
read_sheet <- function(path, sheet) {
  if (!file.exists(path)) return(NULL)
  sheets <- excel_sheets(path)
  if (!sheet %in% sheets) return(NULL)
  read_excel(path, sheet = sheet, col_types = "text")
}

# Strip rows where ALL values are NA (can appear after read_excel on sparse sheets).
drop_all_na_rows <- function(df) {
  df[!apply(is.na(df), 1, all), , drop = FALSE]
}

# ==============================================================================
# E. CHECKS
# ==============================================================================

# ---- E1: KEY denominator/cohort N; QC person-years ----
run_check("KEY:denominator_N", function() {
  new_key <- read_sheet(new_path, "KEY")
  ref_key <- read_sheet(ref_path, "KEY")
  if (is.null(new_key) || is.null(ref_key)) return("FAIL — KEY sheet missing from ref or new")
  get_val <- function(df, label) {
    row_idx <- which(df[[1]] == label)
    if (length(row_idx) == 0) return(NA_character_)
    as.character(df[[2]][row_idx[1]])
  }
  ref_val <- get_val(ref_key, "Denominator N")
  new_val <- get_val(new_key, "Denominator N")
  if (is.na(new_val)) return("FAIL — 'Denominator N' label not found in KEY")
  ok <- ref_val == new_val
  glue("{if (ok) 'PASS' else 'FAIL'} — Denominator N: ref={ref_val}, new={new_val} (expected 9331)")
})

run_check("KEY:confirmed_cohort_N", function() {
  new_key <- read_sheet(new_path, "KEY")
  ref_key <- read_sheet(ref_path, "KEY")
  if (is.null(new_key) || is.null(ref_key)) return("FAIL — KEY sheet missing")
  # Use grepl because the label may appear as "Confirmed-cohort N", "Confirmed cohort N", etc.
  get_val <- function(df, pattern) {
    row_idx <- which(grepl(pattern, df[[1]], ignore.case = TRUE))
    if (length(row_idx) == 0) return(NA_character_)
    as.character(df[[2]][row_idx[1]])
  }
  ref_val <- get_val(ref_key, "Confirmed.cohort N")
  new_val <- get_val(new_key, "Confirmed.cohort N")
  if (is.na(new_val)) return(glue("FAIL — 'Confirmed-cohort N' label not found in KEY (col 1 values: {paste(head(new_key[[1]], 20), collapse=' | ')})"))
  ok <- ref_val == new_val
  glue("{if (ok) 'PASS' else 'FAIL'} — Confirmed-cohort N: ref={ref_val}, new={new_val} (expected 9282)")
})

run_check("QC:total_person_years", function() {
  new_qc <- read_sheet(new_path, "QC")
  ref_qc <- read_sheet(ref_path, "QC")
  if (is.null(new_qc) || is.null(ref_qc)) return("FAIL — QC sheet missing")
  get_val <- function(df, label) {
    row_idx <- which(grepl(label, df[[1]], fixed = TRUE))
    if (length(row_idx) == 0) return(NA_character_)
    as.character(df[[2]][row_idx[1]])
  }
  ref_val <- get_val(ref_qc, "Total person-years")
  new_val <- get_val(new_qc, "Total person-years")
  if (is.na(new_val)) return("FAIL — 'Total person-years' label not found in QC")
  ok <- ref_val == new_val
  glue("{if (ok) 'PASS' else 'FAIL'} — Total person-years: ref={ref_val}, new={new_val} (expected 40298.9)")
})

# ---- E2: Identical sheets: B, A2, A3 ----
for (sht in c("B_modality_primary", "A2_analyte_presence", "A3_missing_analyte")) {
  local({
    s <- sht
    run_check(glue("{s}:identical"), function() {
      ref_df <- drop_all_na_rows(as.data.frame(read_sheet(ref_path, s) %||% data.frame()))
      new_df <- drop_all_na_rows(as.data.frame(read_sheet(new_path, s) %||% data.frame()))
      if (nrow(ref_df) == 0 || nrow(new_df) == 0) return(glue("FAIL — sheet '{s}' missing or empty"))
      if (identical(ref_df, new_df)) {
        glue("PASS — identical ({nrow(new_df)} rows)")
      } else {
        diff_cols <- names(new_df)[vapply(names(new_df), function(col) {
          !isTRUE(identical(new_df[[col]], ref_df[[col]]))
        }, logical(1))]
        glue("FAIL — differing columns: {paste(diff_cols, collapse=', ')}")
      }
    })
  })
}

# %||% helper (readxl returns NULL if sheet absent)
`%||%` <- function(a, b) if (!is.null(a)) a else b

# ---- E3: A_code_presence minus excluded rows ----
run_check("A_code_presence:ref_minus_excl_eq_new", function() {
  ref_a <- as.data.frame(read_sheet(ref_path, "A_code_presence") %||% data.frame())
  new_a <- as.data.frame(read_sheet(new_path, "A_code_presence") %||% data.frame())
  if (nrow(ref_a) == 0 || nrow(new_a) == 0) return("FAIL — A_code_presence missing or empty")
  id_col <- grep("codeset_row_id", names(ref_a), ignore.case = TRUE, value = TRUE)[1]
  if (is.na(id_col)) return("FAIL — codeset_row_id column not found in A_code_presence")
  ref_filtered <- ref_a[!(ref_a[[id_col]] %in% EXCLUDED_IDS), , drop = FALSE]
  rownames(ref_filtered) <- NULL
  rownames(new_a) <- NULL
  if (identical(ref_filtered, new_a)) {
    glue("PASS — ref minus {length(EXCLUDED_IDS)} excluded rows == new ({nrow(new_a)} rows)")
  } else {
    glue("FAIL — ref({nrow(ref_filtered)} rows after exclusion) != new({nrow(new_a)} rows)")
  }
})

run_check("A:excluded_rows_gone", function() {
  ref_a <- as.data.frame(read_sheet(ref_path, "A_code_presence") %||% data.frame())
  new_a <- as.data.frame(read_sheet(new_path, "A_code_presence") %||% data.frame())
  if (nrow(ref_a) == 0 || nrow(new_a) == 0) return("FAIL — A_code_presence missing or empty")
  id_col_ref <- grep("codeset_row_id", names(ref_a), ignore.case = TRUE, value = TRUE)[1]
  id_col_new <- grep("codeset_row_id", names(new_a), ignore.case = TRUE, value = TRUE)[1]
  if (is.na(id_col_ref) || is.na(id_col_new)) return("FAIL — codeset_row_id column not found")
  in_ref <- EXCLUDED_IDS %in% ref_a[[id_col_ref]]
  in_new <- EXCLUDED_IDS %in% new_a[[id_col_new]]
  none_in_new <- !any(in_new)
  if (!none_in_new) {
    present_in_new <- EXCLUDED_IDS[in_new]
    return(glue("FAIL — excluded IDs still in new: {paste(present_in_new, collapse=',')}"))
  }
  # Ref may also be post-Phase-163 (IDs already absent). Both absent = PASS.
  if (all(in_ref)) {
    glue("PASS — all 4 excluded IDs in ref; none in new")
  } else {
    glue("PASS — excluded IDs absent from both ref (ref was already post-163) and new")
  }
})

# ---- E4: Codeset_summary minus excluded ----
run_check("Codeset_summary:excl_gone", function() {
  new_cs <- as.data.frame(read_sheet(new_path, "Codeset_summary") %||% data.frame())
  ref_cs <- as.data.frame(read_sheet(ref_path, "Codeset_summary") %||% data.frame())
  if (nrow(new_cs) == 0) return("FAIL — Codeset_summary missing or empty in new")
  # Check excluded IDs absent from new
  id_col_new <- grep("codeset_row_id", names(new_cs), ignore.case = TRUE, value = TRUE)[1]
  if (!is.na(id_col_new)) {
    in_new <- EXCLUDED_IDS %in% new_cs[[id_col_new]]
    if (any(in_new)) return(glue("FAIL — excluded IDs still in new Codeset_summary: {paste(EXCLUDED_IDS[in_new], collapse=',')}"))
  }
  # Count distinct modality blocks in new (expect 14)
  mod_col <- new_cs[[grep("modality", names(new_cs), ignore.case = TRUE)[1]]]
  n_mods  <- length(unique(mod_col[!is.na(mod_col)]))
  if (n_mods != 14L) return(glue("FAIL — {n_mods} modality blocks in new Codeset_summary (expect 14)"))
  glue("PASS — excluded IDs absent; 14 modality blocks")
})

run_check("Codeset_summary:no_z_codes", function() {
  new_cs <- as.data.frame(read_sheet(new_path, "Codeset_summary") %||% data.frame())
  if (nrow(new_cs) == 0) return("FAIL — Codeset_summary missing or empty")
  # Check any cell for Z-code patterns
  has_z <- any(vapply(new_cs, function(col) {
    col_nona <- col[!is.na(col)]
    length(col_nona) > 0L && any(grepl("(^|[;,[:space:]])Z[0-9]", col_nona))
  }, logical(1)))
  if (!has_z) "PASS — no Z-codes in Codeset_summary" else "FAIL — Z-code found in Codeset_summary"
})

# ---- E5: C_modality_with_sensitivity ----
run_check("C:primary_all_14", function() {
  new_c <- as.data.frame(read_sheet(new_path, "C_modality_with_sensitivity") %||% data.frame())
  ref_c <- as.data.frame(read_sheet(ref_path, "C_modality_with_sensitivity") %||% data.frame())
  if (nrow(new_c) == 0 || nrow(ref_c) == 0) return("FAIL — C sheet missing or empty")
  primary_cols <- grep("^primary_", names(new_c), value = TRUE)
  key_cols <- intersect(c("modality", "submodality"), names(new_c))
  keep_cols <- c(key_cols, primary_cols)
  new_pk <- new_c[, keep_cols, drop = FALSE]
  ref_pk <- ref_c[, keep_cols, drop = FALSE]
  rownames(new_pk) <- NULL; rownames(ref_pk) <- NULL
  if (identical(new_pk, ref_pk)) {
    glue("PASS — primary_* columns identical for all rows ({nrow(new_pk)} rows)")
  } else {
    diff_cols <- primary_cols[vapply(primary_cols, function(col) !isTRUE(identical(new_pk[[col]], ref_pk[[col]])), logical(1))]
    glue("FAIL — differing primary_* columns: {paste(diff_cols, collapse=', ')}")
  }
})

for (mod in CHANGED_MODS) {
  local({
    m <- mod
    run_check(glue("C:changed_mod:{m}"), function() {
      new_c <- as.data.frame(read_sheet(new_path, "C_modality_with_sensitivity") %||% data.frame())
      if (nrow(new_c) == 0) return("FAIL — C sheet missing")
      new_row <- new_c[new_c[["modality"]] == m & new_c[["submodality"]] == "(all)", , drop = FALSE]
      if (nrow(new_row) == 0) return(glue("FAIL — modality '{m}' (all) row not found"))
      sens_n <- suppressWarnings(as.integer(new_row[["sensitivity_n_patients"]]))
      pri_n  <- suppressWarnings(as.integer(new_row[["primary_n_patients"]]))
      any_n  <- suppressWarnings(as.integer(new_row[["any_n_patients"]]))
      ok_sens <- isTRUE(is.na(sens_n) || sens_n == 0L)
      ok_any  <- isTRUE(!is.na(pri_n) && !is.na(any_n) && any_n == pri_n)
      if (ok_sens && ok_any) {
        glue("PASS — sensitivity_n={sens_n} (0), any_n={any_n} == primary_n={pri_n}")
      } else {
        glue("FAIL — sensitivity_n={sens_n} (expect 0), any_n={any_n}, primary_n={pri_n}")
      }
    })
  })
}

# ---- E6: D_pre_vs_post_anchor (long format) ----
run_check("D:primary_all_14_eq_ref", function() {
  new_d <- as.data.frame(read_sheet(new_path, "D_pre_vs_post_anchor") %||% data.frame())
  ref_d <- as.data.frame(read_sheet(ref_path, "D_pre_vs_post_anchor") %||% data.frame())
  if (nrow(new_d) == 0 || nrow(ref_d) == 0) return("FAIL — D sheet missing or empty")
  # Filter to primary rows only
  tier_col_new <- grep("tier_scope|tier|scope", names(new_d), ignore.case = TRUE, value = TRUE)[1]
  tier_col_ref <- grep("tier_scope|tier|scope", names(ref_d), ignore.case = TRUE, value = TRUE)[1]
  if (is.na(tier_col_new) || is.na(tier_col_ref)) return("FAIL — tier_scope column not found in D sheet")
  new_prim <- new_d[new_d[[tier_col_new]] == "primary", , drop = FALSE]
  ref_prim <- ref_d[ref_d[[tier_col_ref]] == "primary", , drop = FALSE]
  rownames(new_prim) <- NULL; rownames(ref_prim) <- NULL
  if (identical(new_prim, ref_prim)) {
    glue("PASS — D primary rows identical ({nrow(new_prim)} rows)")
  } else {
    glue("FAIL — D primary rows differ: new {nrow(new_prim)} rows vs ref {nrow(ref_prim)} rows")
  }
})

for (mod in CHANGED_MODS) {
  local({
    m <- mod
    run_check(glue("D:changed_mod:{m}:any_eq_primary"), function() {
      new_d <- as.data.frame(read_sheet(new_path, "D_pre_vs_post_anchor") %||% data.frame())
      if (nrow(new_d) == 0) return("FAIL — D sheet missing")
      mod_col  <- grep("^modality$", names(new_d), ignore.case = TRUE, value = TRUE)[1]
      tier_col <- grep("tier_scope|tier|scope", names(new_d), ignore.case = TRUE, value = TRUE)[1]
      if (is.na(mod_col) || is.na(tier_col)) return("FAIL — modality or tier_scope column not found")
      new_prim <- new_d[new_d[[mod_col]] == m & new_d[[tier_col]] == "primary", , drop = FALSE]
      new_any  <- new_d[new_d[[mod_col]] == m & new_d[[tier_col]] == "any",     , drop = FALSE]
      if (nrow(new_prim) == 0) return(glue("FAIL — '{m}' primary row not found in D"))
      if (nrow(new_any)  == 0) return(glue("FAIL — '{m}' any row not found in D"))
      # Compare any vs primary (drop tier_scope column itself)
      val_cols <- setdiff(names(new_d), tier_col)
      prim_vals <- new_prim[, val_cols, drop = FALSE]
      any_vals  <- new_any[, val_cols, drop = FALSE]
      rownames(prim_vals) <- NULL; rownames(any_vals) <- NULL
      if (identical(prim_vals, any_vals)) {
        glue("PASS — D '{m}' any row == primary row")
      } else {
        glue("FAIL — D '{m}' any row != primary row")
      }
    })
  })
}

run_check("D:unaffected_any_eq_ref", function() {
  new_d <- as.data.frame(read_sheet(new_path, "D_pre_vs_post_anchor") %||% data.frame())
  ref_d <- as.data.frame(read_sheet(ref_path, "D_pre_vs_post_anchor") %||% data.frame())
  if (nrow(new_d) == 0 || nrow(ref_d) == 0) return("FAIL — D sheet missing or empty")
  mod_col  <- grep("^modality$", names(new_d), ignore.case = TRUE, value = TRUE)[1]
  tier_col <- grep("tier_scope|tier|scope", names(new_d), ignore.case = TRUE, value = TRUE)[1]
  if (is.na(mod_col) || is.na(tier_col)) return("FAIL — modality or tier_scope column not found")
  unaffected <- setdiff(unique(new_d[[mod_col]]), CHANGED_MODS)
  fails <- character(0)
  for (m in unaffected) {
    new_any <- new_d[new_d[[mod_col]] == m & new_d[[tier_col]] == "any", , drop = FALSE]
    ref_any <- ref_d[ref_d[[mod_col]] == m & ref_d[[tier_col]] == "any", , drop = FALSE]
    rownames(new_any) <- NULL; rownames(ref_any) <- NULL
    if (!identical(new_any, ref_any)) fails <- c(fails, m)
  }
  if (length(fails) == 0) {
    glue("PASS — D any rows identical for {length(unaffected)} unaffected modalities")
  } else {
    glue("FAIL — D any rows differ for: {paste(fails, collapse=', ')}")
  }
})

# ---- E7: QC matched-rows drop ----
run_check("QC:matched_rows_drop", function() {
  ref_a  <- as.data.frame(read_sheet(ref_path, "A_code_presence") %||% data.frame())
  ref_qc <- as.data.frame(read_sheet(ref_path, "QC") %||% data.frame())
  new_qc <- as.data.frame(read_sheet(new_path, "QC") %||% data.frame())
  if (nrow(ref_a) == 0 || nrow(ref_qc) == 0 || nrow(new_qc) == 0)
    return("FAIL — A_code_presence or QC sheet missing")
  id_col  <- grep("codeset_row_id", names(ref_a), ignore.case = TRUE, value = TRUE)[1]
  rec_col <- grep("n_records", names(ref_a), ignore.case = TRUE, value = TRUE)[1]
  if (is.na(id_col) || is.na(rec_col)) return("FAIL — codeset_row_id or n_records column not found in A")
  excl_rows <- ref_a[ref_a[[id_col]] %in% EXCLUDED_IDS, , drop = FALSE]
  expected_drop <- sum(suppressWarnings(as.integer(excl_rows[[rec_col]])), na.rm = TRUE)
  get_qc_val <- function(qc, label) {
    row_idx <- which(grepl(label, qc[[1]], fixed = TRUE))
    if (length(row_idx) == 0) return(NA_integer_)
    suppressWarnings(as.integer(qc[[2]][row_idx[1]]))
  }
  matched_ref <- get_qc_val(ref_qc, "Matched rows, type ok")
  matched_new <- get_qc_val(new_qc, "Matched rows, type ok")
  if (is.na(matched_ref) || is.na(matched_new)) return("FAIL — 'Matched rows, type ok' label not found in QC")
  actual_drop <- matched_ref - matched_new
  if (actual_drop == expected_drop) {
    glue("PASS — drop={actual_drop}, expected={expected_drop} (sum of n_records for excluded IDs)")
  } else {
    glue("FAIL — drop={actual_drop}, expected={expected_drop}. Note: verify grain vs n_records grain before treating as regression.")
  }
})

# ---- E8: QC/KEY structure ----
run_check("QC:excluded_row_present", function() {
  new_qc <- as.data.frame(read_sheet(new_path, "QC") %||% data.frame())
  if (nrow(new_qc) == 0) return("FAIL — QC sheet missing")
  has_excl <- any(grepl("Codeset rows excluded", new_qc[[1]], fixed = TRUE))
  if (has_excl) "PASS — 'Codeset rows excluded (DIAGNOSIS)' present" else "FAIL — row missing"
})

run_check("QC:old_diag_row_absent", function() {
  new_qc <- as.data.frame(read_sheet(new_path, "QC") %||% data.frame())
  if (nrow(new_qc) == 0) return("FAIL — QC sheet missing")
  has_old <- any(grepl("DIAGNOSIS rows collected", new_qc[[1]], fixed = TRUE))
  if (!has_old) "PASS — 'DIAGNOSIS rows collected' absent" else "FAIL — old row still present"
})

run_check("KEY:163_D01_note", function() {
  new_key <- as.data.frame(read_sheet(new_path, "KEY") %||% data.frame())
  if (nrow(new_key) == 0) return("FAIL — KEY sheet missing")
  has_note <- any(grepl("163 D-01", unlist(new_key), fixed = TRUE))
  if (has_note) "PASS — '163 D-01' note present" else "FAIL — note missing"
})

# ---- E9: "diagnosis" text residue ----
run_check("residue:diagnosis_text", function() {
  sheets_to_scan <- c("KEY", "QC", "A_code_presence", "B_modality_primary",
                      "C_modality_with_sensitivity", "D_pre_vs_post_anchor", "Codeset_summary")
  # Allowed occurrences: denominator/anchor/excluded/163 D-01 context
  allowed_patterns <- c("denominator", "anchor", "excluded", "163 D-01", "Confirmed-cohort",
                        "DIAGNOSIS rows excluded", "Codeset rows excluded",
                        "HL diagnosis", "usable HL")
  violations <- character(0)
  for (sht in sheets_to_scan) {
    df <- as.data.frame(read_sheet(new_path, sht) %||% data.frame())
    if (nrow(df) == 0) next
    all_text <- unlist(df, use.names = FALSE)
    all_text <- all_text[!is.na(all_text)]
    diag_hits <- all_text[grepl("diagnosis|DIAGNOSIS", all_text, ignore.case = TRUE)]
    for (hit in diag_hits) {
      is_allowed <- any(grepl(paste(allowed_patterns, collapse = "|"), hit, ignore.case = TRUE))
      if (!is_allowed) violations <- c(violations, glue("{sht}: '{substr(hit, 1, 80)}'"))
    }
  }
  if (length(violations) == 0) "PASS — no disallowed 'diagnosis' occurrences" else
    glue("FAIL — disallowed occurrences: {paste(violations, collapse='; ')}")
})

# ---- E10: RDS checks ----
run_check("RDS:same_ids", function() {
  if (!file.exists(ref_rds_path)) return("FAIL — input:ref_rds missing")
  if (!file.exists(new_rds_path)) return("FAIL — input:new_rds missing")
  ref <- tryCatch(readRDS(ref_rds_path), error = function(e) NULL)
  new <- tryCatch(readRDS(new_rds_path), error = function(e) NULL)
  if (is.null(ref) || is.null(new)) return("FAIL — could not load RDS files")
  key <- grep("^id$", names(ref), ignore.case = TRUE, value = TRUE)[1]
  if (is.na(key)) return("FAIL — ID column not found in ref RDS")
  ref_ids <- sort(unique(as.character(ref[[key]])))
  new_ids <- sort(unique(as.character(new[[key]])))
  if (identical(ref_ids, new_ids)) {
    glue("PASS — same {length(ref_ids)} IDs")
  } else {
    only_ref <- setdiff(ref_ids, new_ids)
    only_new <- setdiff(new_ids, ref_ids)
    glue("FAIL — {length(only_ref)} IDs only in ref; {length(only_new)} only in new")
  }
})

run_check("RDS:primary_cols", function() {
  if (!file.exists(ref_rds_path) || !file.exists(new_rds_path)) return("FAIL — RDS file missing")
  ref <- tryCatch(readRDS(ref_rds_path), error = function(e) NULL)
  new <- tryCatch(readRDS(new_rds_path), error = function(e) NULL)
  if (is.null(ref) || is.null(new)) return("FAIL — could not load RDS files")
  key      <- grep("^id$", names(ref), ignore.case = TRUE, value = TRUE)[1]
  if (is.na(key)) return("FAIL — ID column not found")
  ord      <- function(d) { d <- as.data.frame(d); d[order(d[[key]]), , drop = FALSE] }
  ref_s    <- ord(ref); new_s <- ord(new)
  any_cols <- grep("_any$", names(new_s), value = TRUE)
  prim_cols <- setdiff(names(new_s), any_cols)
  # Only compare columns present in both
  shared <- intersect(prim_cols, names(ref_s))
  result <- all.equal(ref_s[shared], new_s[shared], check.attributes = FALSE)
  if (isTRUE(result)) {
    glue("PASS — {length(shared)} primary columns equal")
  } else {
    glue("FAIL — {paste(head(result, 3), collapse='; ')}")
  }
})

run_check("RDS:changed_any_eq_primary", function() {
  if (!file.exists(new_rds_path)) return("FAIL — new RDS missing")
  new <- tryCatch(readRDS(new_rds_path), error = function(e) NULL)
  if (is.null(new)) return("FAIL — could not load new RDS")
  norm <- function(x) tolower(gsub("[^a-z0-9]", "", x))
  norm_names <- setNames(vapply(names(new), norm, character(1)), names(new))
  any_cols   <- grep("_any$", names(new), value = TRUE)
  fails <- character(0)
  for (mod in CHANGED_MODS) {
    norm_mod <- norm(mod)
    # Find primary column: normalised name contains norm_mod and column name doesn't end in _any
    prim_col <- names(norm_names)[grepl(norm_mod, norm_names, fixed = TRUE) & !grepl("_any$", names(norm_names))]
    if (length(prim_col) == 0) {
      fails <- c(fails, glue("'{mod}': primary column not found (norm='{norm_mod}'; available: {paste(names(new), collapse=',')})"))
      next
    }
    prim_col <- prim_col[1]
    # Derive _any column: try appending _any first, then fall back to normalisation search
    any_col <- paste0(prim_col, "_any")
    if (!any_col %in% names(new)) {
      cand <- any_cols[vapply(any_cols, function(cn) grepl(norm_mod, norm(cn), fixed = TRUE), logical(1))]
      if (length(cand) == 0) {
        fails <- c(fails, glue("'{mod}': _any column not found (tried '{any_col}' and normalisation)"))
        next
      }
      any_col <- cand[1]
    }
    eq <- all.equal(new[[any_col]], new[[prim_col]], check.attributes = FALSE)
    if (!isTRUE(eq)) fails <- c(fails, glue("'{mod}': {any_col} != {prim_col}"))
  }
  if (length(fails) == 0) {
    glue("PASS — _any == primary for all {length(CHANGED_MODS)} changed modalities")
  } else {
    glue("FAIL — {paste(fails, collapse='; ')}")
  }
})

run_check("RDS:unaffected_any_eq_ref", function() {
  if (!file.exists(ref_rds_path) || !file.exists(new_rds_path)) return("FAIL — RDS file missing")
  ref <- tryCatch(readRDS(ref_rds_path), error = function(e) NULL)
  new <- tryCatch(readRDS(new_rds_path), error = function(e) NULL)
  if (is.null(ref) || is.null(new)) return("FAIL — could not load RDS files")
  key <- grep("^id$", names(ref), ignore.case = TRUE, value = TRUE)[1]
  if (is.na(key)) return("FAIL — ID column not found")
  ord  <- function(d) { d <- as.data.frame(d); d[order(d[[key]]), , drop = FALSE] }
  ref_s <- ord(ref); new_s <- ord(new)
  norm  <- function(x) tolower(gsub("[^a-z0-9]", "", x))
  all_any <- grep("_any$", names(new_s), value = TRUE)
  changed_norm <- sapply(CHANGED_MODS, norm)
  unaffected_any <- all_any[!sapply(all_any, function(c) any(sapply(changed_norm, function(n) grepl(n, norm(c)))))]
  if (length(unaffected_any) == 0) return("SKIP — no unaffected _any columns found")
  shared <- intersect(unaffected_any, names(ref_s))
  if (length(shared) == 0) return("SKIP — unaffected _any columns not in ref RDS")
  result <- all.equal(ref_s[shared], new_s[shared], check.attributes = FALSE)
  if (isTRUE(result)) {
    glue("PASS — {length(shared)} unaffected _any columns equal to ref")
  } else {
    glue("FAIL — {paste(head(result, 3), collapse='; ')}")
  }
})

# ==============================================================================
# F. FINAL BLOCK (always runs)
# ==============================================================================
n_pass <- 0L; n_fail <- 0L; n_skip <- 0L

cat("\n========== 147 vs 1006 VERIFICATION RESULTS ==========\n")
for (nm in names(results)) {
  v   <- results[[nm]]
  tag <- if (startsWith(v, "PASS")) {
           n_pass <- n_pass + 1L; "[PASS]"
         } else if (startsWith(v, "SKIP")) {
           n_skip <- n_skip + 1L; "[SKIP]"
         } else {
           n_fail <- n_fail + 1L; "[FAIL]"
         }
  cat(sprintf("%s %s: %s\n", tag, nm, sub("^(PASS|FAIL|SKIP)\\s*—\\s*", "", v)))
}

cat(sprintf("\n%d PASS, %d FAIL, %d SKIP out of %d checks\n",
            n_pass, n_fail, n_skip, length(results)))

if (n_fail == 0) {
  cat("OVERALL: PASS\n")
  writeLines(
    c(paste0("run_date=", run_date),
      paste0("log=", log_path),
      paste0("rds=", new_rds_path),
      paste0("workbook=", new_path)),
    file.path(log_dir, "147_verify_last_pass.txt")
  )
} else {
  cat(sprintf("OVERALL: FAIL (%d checks)\n", n_fail))
}

sink()
close(con)

quit(status = if (n_fail == 0) 0 else 1)
