# ==============================================================================
# 165_distance_cbc_association.R -- Distance >100 mi and CBC: Production Analysis
# ==============================================================================
#
# Purpose:
#   Implement the team-selected method D-165-01 (Rao-Scott cluster-adjusted
#   chi-square, encounter-level, clustered on patient ID) for the association
#   between far_from_care_100mi and CBC receipt. Runs both windows (whole record
#   and post-anchor). Produces the five-sheet deliverable workbook.
#
# Inputs:
#   CONFIG$output_dir/encounter_distance_*.rds   (R/122 output; most recent by mtime)
#   DuckDB: ENCOUNTER (ENCOUNTERID, ADMIT_DATE, DISCHARGE_DATE, ENC_TYPE, SOURCE)
#   DuckDB: LAB_RESULT_CM (CBC re-derive; LOINCs 6690-2, 718-7, 777-3)
#   get_hl_any_dx_ids() from utils_treatment.R    (anchor dates)
#   R/116 output: encounter_ses_index_*.rds       (rurality; most recent by mtime)
#   payer_summary from R/02_harmonize_payer.R     (reloaded via saved RDS)
#
# Outputs:
#   CONFIG$output_dir/distance_cbc_association_<YYYYMMDD>.xlsx
#     Sheets (in order): KEY, A_crosstab, B_test, C_sensitivity, QC
#
# Depends:
#   R/00_config.R (auto-sources utils_distance_cbc.R, utils_duckdb.R, utils_treatment.R)
#   survey    (Rao-Scott; must be in renv.lock)
#   openxlsx  (workbook construction)
#   dplyr, glue, here (standard pipeline)
#
# Requirements: ACC-01, ACC-03, ACC-04 (Phase 165)
#
# Usage:
#   sbatch slurm/165_distance_cbc_association.sbatch    (preferred)
#   Rscript R/165_distance_cbc_association.R            (compute node only)
#   Do NOT run interactively on a login/OnDemand session -- DuckDB + LAB_RESULT_CM
#   query requires a batch allocation.
#
# ==============================================================================

# ==============================================================================
# SECTION 0: SETUP ----
# ==============================================================================

source(here::here("R/00_config.R"))
# 00_config.R auto-sources utils_distance_cbc.R, utils_duckdb.R, utils_treatment.R.
# build_*(), get_*(), suppress_small_vec(), suppress_display(), naive_or_se() available.

suppressPackageStartupMessages({
  library(dplyr)
  library(openxlsx)
  library(glue)
  library(survey)
})

RUN_START <- proc.time()
RUN_DATE  <- format(Sys.Date(), "%Y%m%d")

METHOD <- CONFIG$distance_assoc_method
CUTOFF <- CONFIG$far_from_care_cutoff_mi

stopifnot(
  "D-165-01 not recorded: set CONFIG$distance_assoc_method in R/00_config.R" =
    !is.na(METHOD),
  "distance_assoc_method must be gee, rao_scott, or patient_fisher" =
    METHOD %in% c("gee", "rao_scott", "patient_fisher"),
  "far_from_care_cutoff_mi must be set (not NA)" = !is.na(CUTOFF),
  "far_from_care_cutoff_mi must be positive"     = CUTOFF > 0
)

message(glue("================================================================================"))
message(glue("R/165 distance_cbc_association -- RUN DATE {RUN_DATE}"))
message(glue("  Method : {METHOD}  (D-165-01)"))
message(glue("  Cutoff : {CUTOFF} mi"))
message(glue("================================================================================"))

# ==============================================================================
# SECTION 1: INPUTS ----
# ==============================================================================

# 1a. enc_distance (R/122 output) -- read most recent by mtime from output_dir
enc_dist_candidates <- list.files(
  CONFIG$output_dir,
  pattern = "^encounter_distance.*\\.rds$",
  full.names = TRUE
)
if (length(enc_dist_candidates) == 0L)
  stop("enc_distance RDS not found in ", CONFIG$output_dir,
       " -- run R/122_encounter_distance.R first")
enc_dist_path <- enc_dist_candidates[which.max(file.mtime(enc_dist_candidates))]
message(glue("  Loading enc_distance: {basename(enc_dist_path)}"))
enc_distance <- readRDS(enc_dist_path)
message(glue("  enc_distance rows: {format(nrow(enc_distance), big.mark = ',')}"))

# 1b. Open DuckDB
if (!exists("pcornet_con", envir = .GlobalEnv)) open_pcornet_con()

# 1c. Anchor dates (hl_anchor_date) from utils_treatment
message("  Fetching anchor dates via get_hl_any_dx_ids() ...")
cohort_ids <- unique(enc_distance$ID)
anchors     <- get_hl_any_dx_ids()
message(glue("  Anchor dates: {nrow(anchors)} patients; ",
             "{sum(is.na(anchors$hl_anchor_date))} missing anchor date."))

# 1d. ENCOUNTER dates + SOURCE + ENC_TYPE (DuckDB push-down to cohort)
message("  Pulling ENCOUNTER dates, ENC_TYPE, SOURCE from DuckDB ...")
enc_ids_sql <- paste(sprintf("'%s'", unique(enc_distance$ENCOUNTERID)), collapse = ", ")
enc_dates_raw <- DBI::dbGetQuery(pcornet_con, sprintf("
  SELECT
    ENCOUNTERID,
    TRY_CAST(ADMIT_DATE    AS DATE) AS ADMIT_DATE,
    TRY_CAST(DISCHARGE_DATE AS DATE) AS DISCHARGE_DATE,
    ENC_TYPE,
    SOURCE
  FROM ENCOUNTER
  WHERE ENCOUNTERID IN (%s)
", enc_ids_sql))
enc_dates_raw$ADMIT_DATE    <- as.Date(enc_dates_raw$ADMIT_DATE)
enc_dates_raw$DISCHARGE_DATE <- as.Date(enc_dates_raw$DISCHARGE_DATE)
message(glue("  enc_dates_raw rows: {format(nrow(enc_dates_raw), big.mark = ',')}"))

# 1e. CBC events (whole record) re-derived from DuckDB LAB_RESULT_CM
message("  Building CBC events (whole record) via build_cbc_events() ...")
cbc_events <- build_cbc_events(pcornet_con, cohort_ids)
message(glue("  cbc_events rows: {format(nrow(cbc_events), big.mark = ',')}",
             " (patient x date pairs)"))

# 1f. Close DuckDB connection
close_pcornet_con()

# 1g. R/116 encounter-level SES (rurality) -- most recent by mtime
ses_candidates <- list.files(
  CONFIG$output_dir,
  pattern = "^encounter_ses_index.*\\.rds$",
  full.names = TRUE
)
if (length(ses_candidates) == 0L) {
  warning("encounter_ses_index RDS not found in ", CONFIG$output_dir,
          " -- rurality covariate will be missing for all encounters.")
  enc_ses <- tibble::tibble(
    PATID = character(0), ENCOUNTERID = character(0),
    ruca_code = integer(0), ruca_category = character(0)
  )
} else {
  ses_path <- ses_candidates[which.max(file.mtime(ses_candidates))]
  message(glue("  Loading SES (rurality): {basename(ses_path)}"))
  enc_ses <- readRDS(ses_path) |>
    dplyr::select(PATID, ENCOUNTERID, ruca_code, ruca_category)
}

# 1h. Patient-level payer (payer_summary from R/02) -- read from output dir
payer_candidates <- list.files(
  CONFIG$output_dir,
  pattern = "^payer_summary.*\\.rds$",
  full.names = TRUE
)
if (length(payer_candidates) == 0L) {
  warning("payer_summary RDS not found in ", CONFIG$output_dir,
          " -- payer covariate will be missing for all patients.")
  payer_summary <- tibble::tibble(ID = character(0), PAYER_CATEGORY_PRIMARY = character(0))
} else {
  payer_path <- payer_candidates[which.max(file.mtime(payer_candidates))]
  message(glue("  Loading payer_summary: {basename(payer_path)}"))
  payer_summary <- readRDS(payer_path) |>
    dplyr::select(ID, PAYER_CATEGORY_PRIMARY)
}

# ==============================================================================
# SECTION 2: BUILD ENCOUNTER-LEVEL ANALYSIS SET ----
# ==============================================================================

message("  Building enc_analysis via build_enc_analysis() ...")

# enc_dates for build_enc_analysis: ENCOUNTERID, DISCHARGE_DATE, SOURCE
enc_dates_for_build <- enc_dates_raw |>
  dplyr::select(ENCOUNTERID, DISCHARGE_DATE, SOURCE)

# ENC_TYPE lives in enc_dates_raw; merge it into enc_distance so build_enc_analysis
# can return it (enc_distance from R/122 may not carry ENC_TYPE)
if (!"ENC_TYPE" %in% names(enc_distance)) {
  enc_distance <- enc_distance |>
    dplyr::left_join(
      enc_dates_raw |> dplyr::select(ENCOUNTERID, ENC_TYPE),
      by = "ENCOUNTERID"
    )
}

enc <- build_enc_analysis(
  enc_distance = enc_distance,
  cbc_events   = cbc_events,
  anchors      = anchors,
  enc_dates    = enc_dates_for_build,
  cutoff       = CUTOFF
)
message(glue("  enc_analysis rows (whole): {format(nrow(enc), big.mark = ',')}"))
message(glue("  enc_analysis post-anchor : {format(sum(enc$post_anchor), big.mark = ',')}"))

# 2a. Attach rurality to enc (join on ENCOUNTERID; R/116 join key is PATID but
#     ENCOUNTERID is also in the schema per DISCOVERY Q7)
enc_with_rurality <- enc |>
  dplyr::left_join(
    enc_ses |> dplyr::select(ENCOUNTERID, ruca_code, ruca_category),
    by = "ENCOUNTERID"
  )

# 2b. Attach patient-level payer (join on ID)
enc_full <- enc_with_rurality |>
  dplyr::left_join(payer_summary, by = "ID")

# 2c. QC: missing rurality / payer at encounter level
n_miss_rurality_whole <- sum(is.na(enc_full$ruca_category))
n_miss_payer_whole    <- sum(is.na(enc_full$PAYER_CATEGORY_PRIMARY))
n_miss_rurality_post  <- enc_full |>
  dplyr::filter(post_anchor == 1L) |>
  dplyr::summarise(n = sum(is.na(ruca_category))) |>
  dplyr::pull(n)
n_miss_payer_post <- enc_full |>
  dplyr::filter(post_anchor == 1L) |>
  dplyr::summarise(n = sum(is.na(PAYER_CATEGORY_PRIMARY))) |>
  dplyr::pull(n)

message(glue("  Missing rurality (whole): {n_miss_rurality_whole}"))
message(glue("  Missing payer    (whole): {n_miss_payer_whole}"))
message(glue("  Missing rurality (post) : {n_miss_rurality_post}"))
message(glue("  Missing payer    (post) : {n_miss_payer_post}"))

# ==============================================================================
# SECTION 3: SUPPRESSION HELPER FOR DISPLAY TABLES ----
# ==============================================================================
# suppress_small_vec() and suppress_display() come from utils_distance_cbc.R.
#
# apply_complementary_suppression():
#   Given a 2x2 + totals matrix (3x3), apply HIPAA display suppression:
#   1. Suppress any interior cell with count 1-10.
#   2. If a row has exactly one suppressed interior cell, suppress that row's total
#      (to prevent back-calculation by subtraction).
#   3. Same for columns.
#   Returns a character matrix with "<11" for suppressed cells.
#
# WHY: Back-calculation attack: if row total = 50 and three cells are 10, 0, <11,
# the reader can derive the suppressed cell. Complementary suppression of the total
# removes the information. Totals ARE computed from raw counts first; only display
# is suppressed.
apply_complementary_suppression <- function(ct_raw) {
  # ct_raw: numeric 2x2 matrix (rows = far 0/1, cols = cbc 0/1) with raw counts.
  # Returns a 3x3 character matrix with row/col totals and suppression applied.
  stopifnot(is.matrix(ct_raw), all(dim(ct_raw) == c(2L, 2L)))

  # Build 3x3 with raw totals
  row_tots <- rowSums(ct_raw)
  col_tots <- colSums(ct_raw)
  grand    <- sum(ct_raw)
  m_raw <- rbind(
    cbind(ct_raw,          row_tots),
    c(col_tots,            grand)
  )
  dimnames(m_raw) <- list(
    c("far=0", "far=1", "Total"),
    c("CBC=0", "CBC=1", "Total")
  )

  # Display matrix (character); start with raw values
  m_disp <- matrix(as.character(m_raw), nrow = 3L, ncol = 3L,
                   dimnames = dimnames(m_raw))

  # Step 1: suppress interior cells (rows 1-2, cols 1-2)
  supp_flag <- matrix(FALSE, 3L, 3L)
  for (r in 1:2) {
    for (cl in 1:2) {
      v <- m_raw[r, cl]
      if (!is.na(v) && v >= 1 && v <= 10) {
        m_disp[r, cl]     <- "<11"
        supp_flag[r, cl]  <- TRUE
      }
    }
  }

  # Step 2: row totals — suppress if row has exactly one suppressed interior cell
  for (r in 1:2) {
    if (sum(supp_flag[r, 1:2]) == 1L) {
      m_disp[r, 3L] <- "<11"
    }
  }

  # Step 3: column totals — suppress if column has exactly one suppressed interior cell
  for (cl in 1:2) {
    if (sum(supp_flag[1:2, cl]) == 1L) {
      m_disp[3L, cl] <- "<11"
    }
  }

  m_disp
}

# ==============================================================================
# SECTION 4: PER-WINDOW ANALYSIS FUNCTION ----
# ==============================================================================

analyse_window <- function(window, enc_full, cbc_events, anchors) {
  stopifnot(window %in% c("whole", "post"))
  label <- if (window == "whole") "Whole record" else "Post-anchor"
  message(glue("  --- analyse_window({window}) ---"))

  # 4a. Encounter subset
  enc_win <- if (window == "post") {
    enc_full |> dplyr::filter(post_anchor == 1L)
  } else {
    enc_full
  }
  n_enc_in <- nrow(enc_win)
  message(glue("    Encounters in window: {format(n_enc_in, big.mark = ',')}"))

  # 4b. Patient-level analysis set (shared helper, same unit as prototype)
  pat_win <- build_pat_analysis(
    enc_analysis = enc_full,   # full set; helper subsets internally
    cbc_events   = cbc_events,
    anchors      = anchors,
    window       = window
  )

  # 4c. Attach patient-level covariates for sensitivity model
  #     rurality  = ruca_category at patient's LATEST in-window encounter
  #     payer     = PAYER_CATEGORY_PRIMARY (patient-level from payer_summary)
  #     modal_source = modal SOURCE across in-window encounters; ties -> earliest

  latest_enc_rurality <- enc_win |>
    dplyr::arrange(ID, dplyr::desc(ADMIT_DATE)) |>
    dplyr::group_by(ID) |>
    dplyr::slice_head(n = 1L) |>
    dplyr::ungroup() |>
    dplyr::select(ID, ruca_category)

  modal_source_fn <- function(sources, dates) {
    df <- data.frame(s = sources, d = dates, stringsAsFactors = FALSE)
    df <- df[!is.na(df$s), , drop = FALSE]
    if (nrow(df) == 0L) return(NA_character_)
    freq <- sort(table(df$s), decreasing = TRUE)
    top_freq <- freq[freq == max(freq)]
    if (length(top_freq) == 1L) return(names(top_freq))
    # Tie: earliest encounter's SOURCE
    candidates <- names(top_freq)
    df_tie <- df[df$s %in% candidates, ]
    df_tie <- df_tie[order(df_tie$d), ]
    df_tie$s[1L]
  }

  modal_src_tbl <- enc_win |>
    dplyr::group_by(ID) |>
    dplyr::summarise(
      modal_source = modal_source_fn(SOURCE, ADMIT_DATE),
      .groups = "drop"
    )

  pat_cov <- pat_win |>
    dplyr::left_join(latest_enc_rurality, by = "ID") |>
    dplyr::left_join(payer_summary,        by = "ID") |>
    dplyr::left_join(modal_src_tbl,        by = "ID")

  n_pat_in   <- nrow(pat_cov)
  message(glue("    Patients in window: {format(n_pat_in, big.mark = ',')}"))

  # 4d. QC counts
  n_telehealth  <- sum(enc_win$ENC_TYPE == "TH", na.rm = TRUE)
  n_miss_ruca   <- sum(is.na(enc_win$ruca_category))
  n_miss_payer  <- sum(is.na(enc_win$PAYER_CATEGORY_PRIMARY))
  cbc_match_rate <- mean(enc_win$cbc_in_encounter)
  n_pat_cbc     <- sum(pat_win$any_cbc)

  qc <- list(
    window        = label,
    n_enc_in      = n_enc_in,
    n_pat_in      = n_pat_in,
    n_telehealth  = n_telehealth,
    n_miss_ruca   = n_miss_ruca,
    n_miss_payer  = n_miss_payer,
    cbc_match_rate = round(cbc_match_rate * 100, 2),
    n_pat_cbc     = n_pat_cbc
  )

  # 4e. Crosstab (raw counts, encounter-level for rao_scott)
  ct_raw <- table(
    far = enc_win$far_from_care_100mi,
    cbc = enc_win$cbc_in_encounter
  )
  # Ensure 2x2 even if one level is absent
  if (!all(c("0","1") %in% rownames(ct_raw))) {
    full_ct <- matrix(0L, 2L, 2L, dimnames = list(far=c("0","1"), cbc=c("0","1")))
    for (r in rownames(ct_raw)) for (cl in colnames(ct_raw)) full_ct[r, cl] <- ct_raw[r, cl]
    ct_raw <- full_ct
  }
  ct_raw <- as.matrix(ct_raw)

  # Row percentages on raw counts
  ct_row_pct <- ct_raw / rowSums(ct_raw) * 100

  # Suppressed display
  ct_disp <- apply_complementary_suppression(ct_raw)

  # Naive OR/SE for DEFF comparison
  naive <- naive_or_se(ct_raw)
  haldane_flag <- naive$haldane

  crosstab <- list(
    ct_raw    = ct_raw,
    ct_row_pct = ct_row_pct,
    ct_disp   = ct_disp
  )

  # 4f. Primary analysis (Rao-Scott, dispatched on METHOD = "rao_scott")
  primary <- tryCatch({
    message(glue("    Running primary Rao-Scott analysis ({window}) ..."))
    des <- survey::svydesign(ids = ~ID, data = enc_win)
    rs_chisq <- survey::svychisq(
      ~far_from_care_100mi + cbc_in_encounter, des,
      statistic = "F"
    )

    # svyglm for OR (quasibinomial = logit link, appropriate for binary outcome
    # in a survey design; produces cluster-robust SEs)
    glm_fit <- survey::svyglm(
      cbc_in_encounter ~ far_from_care_100mi,
      design = des,
      family = quasibinomial()
    )
    coef_tbl <- summary(glm_fit)$coefficients
    log_or   <- coef_tbl["far_from_care_100mi", "Estimate"]
    se_log   <- coef_tbl["far_from_care_100mi", "Std. Error"]
    or       <- exp(log_or)
    ci_lo    <- exp(log_or - 1.96 * se_log)
    ci_hi    <- exp(log_or + 1.96 * se_log)
    p_val    <- coef_tbl["far_from_care_100mi", "Pr(>|t|)"]

    # DEFF: ratio of cluster SE^2 to naive SE^2
    deff <- (se_log / naive$se)^2

    list(
      method      = "rao_scott",
      statistic   = rs_chisq$statistic,
      df          = rs_chisq$parameter,
      p_chisq     = rs_chisq$p.value,
      or          = or,
      ci_lo       = ci_lo,
      ci_hi       = ci_hi,
      se_log_or   = se_log,
      p_svyglm    = p_val,
      deff        = deff,
      n_enc       = n_enc_in,
      n_pat       = n_pat_in,
      haldane     = haldane_flag,
      error       = NA_character_
    )
  }, error = function(e) {
    message(glue("    ERROR in primary analysis ({window}): {conditionMessage(e)}"))
    list(
      method = "rao_scott", statistic = NA, df = NA, p_chisq = NA,
      or = NA, ci_lo = NA, ci_hi = NA, se_log_or = NA, p_svyglm = NA,
      deff = NA, n_enc = n_enc_in, n_pat = n_pat_in,
      haldane = haldane_flag, error = conditionMessage(e)
    )
  })

  # 4g. Sensitivity: adjusted encounter-level Rao-Scott model
  #     Covariates: rurality (ruca_category) + payer (PAYER_CATEGORY_PRIMARY) + SOURCE
  #     Collapse levels with < 11 patients into "Other" before fitting
  sensitivity <- tryCatch({
    message(glue("    Running sensitivity model ({window}) ..."))

    # Complete-case subset (enc level, must have rurality + payer + SOURCE)
    enc_cc <- enc_win |>
      dplyr::filter(
        !is.na(ruca_category),
        !is.na(PAYER_CATEGORY_PRIMARY),
        !is.na(SOURCE)
      )
    n_cc      <- nrow(enc_cc)
    n_drop_ruca  <- sum(is.na(enc_win$ruca_category))
    n_drop_payer <- sum(is.na(enc_win$PAYER_CATEGORY_PRIMARY) &
                          !is.na(enc_win$ruca_category))
    n_drop_src   <- sum(is.na(enc_win$SOURCE) &
                          !is.na(enc_win$ruca_category) &
                          !is.na(enc_win$PAYER_CATEGORY_PRIMARY))

    # Collapse sparse SOURCE levels (< 11 patients)
    collapse_to_other <- function(df, col, min_n = 11L) {
      pat_counts <- df |>
        dplyr::group_by(.data[[col]]) |>
        dplyr::summarise(n_pat = dplyr::n_distinct(ID), .groups = "drop")
      small_levels <- pat_counts |>
        dplyr::filter(n_pat < min_n) |>
        dplyr::pull(.data[[col]])
      df |> dplyr::mutate(
        !!col := dplyr::if_else(.data[[col]] %in% small_levels, "Other", .data[[col]])
      )
    }

    enc_cc <- enc_cc |>
      collapse_to_other("SOURCE") |>
      collapse_to_other("PAYER_CATEGORY_PRIMARY") |>
      collapse_to_other("ruca_category")

    enc_cc <- enc_cc |>
      dplyr::mutate(
        SOURCE                = factor(SOURCE),
        PAYER_CATEGORY_PRIMARY = factor(PAYER_CATEGORY_PRIMARY),
        ruca_category         = factor(ruca_category)
      )

    des_cc <- survey::svydesign(ids = ~ID, data = enc_cc)
    glm_adj <- survey::svyglm(
      cbc_in_encounter ~ far_from_care_100mi + ruca_category +
        PAYER_CATEGORY_PRIMARY + SOURCE,
      design = des_cc,
      family = quasibinomial()
    )
    coef_adj <- summary(glm_adj)$coefficients
    log_or_adj <- coef_adj["far_from_care_100mi", "Estimate"]
    se_adj     <- coef_adj["far_from_care_100mi", "Std. Error"]
    or_adj     <- exp(log_or_adj)
    ci_lo_adj  <- exp(log_or_adj - 1.96 * se_adj)
    ci_hi_adj  <- exp(log_or_adj + 1.96 * se_adj)
    p_adj      <- coef_adj["far_from_care_100mi", "Pr(>|t|)"]

    list(
      or_adj      = or_adj,
      ci_lo_adj   = ci_lo_adj,
      ci_hi_adj   = ci_hi_adj,
      p_adj       = p_adj,
      n_used      = n_cc,
      n_drop_ruca = n_drop_ruca,
      n_drop_payer = n_drop_payer,
      n_drop_src  = n_drop_src,
      coef_table  = as.data.frame(coef_adj),
      error       = NA_character_
    )
  }, error = function(e) {
    message(glue("    ERROR in sensitivity model ({window}): {conditionMessage(e)}"))
    list(
      or_adj = NA, ci_lo_adj = NA, ci_hi_adj = NA, p_adj = NA,
      n_used = NA, n_drop_ruca = NA, n_drop_payer = NA, n_drop_src = NA,
      coef_table = data.frame(),
      error = conditionMessage(e)
    )
  })

  list(
    window    = window,
    label     = label,
    ct_raw    = ct_raw,
    crosstab  = crosstab,
    primary   = primary,
    sensitivity = sensitivity,
    qc        = qc
  )
}

# ==============================================================================
# SECTION 5: RUN BOTH WINDOWS ----
# ==============================================================================

results <- lapply(c("whole", "post"), function(w) {
  analyse_window(w, enc_full, cbc_events, anchors)
})
names(results) <- c("whole", "post")

# ==============================================================================
# SECTION 6: BUILD WORKBOOK ----
# ==============================================================================

message("  Building workbook ...")

# UF brand colours
UF_BLUE   <- "#0021A5"
UF_ORANGE <- "#FA4616"
WHITE     <- "#FFFFFF"

uf_header_style <- openxlsx::createStyle(
  fgFill    = UF_BLUE,
  fontColour = WHITE,
  textDecoration = "bold",
  borderStyle = "thin"
)
section_style <- openxlsx::createStyle(
  fgFill    = UF_ORANGE,
  fontColour = WHITE,
  textDecoration = "bold"
)
bold_style <- openxlsx::createStyle(textDecoration = "bold")
note_style <- openxlsx::createStyle(
  fgFill = "#F2F2F2",
  wrapText = TRUE
)

wb <- openxlsx::createWorkbook()

# ---- Sheet: KEY ----
openxlsx::addWorksheet(wb, "KEY")
key_rows <- list(
  c("Field", "Value"),
  c("Analysis",       "far_from_care_100mi x CBC receipt (encounter-level)"),
  c("Run date",        RUN_DATE),
  c("Method (D-165-01)", "C2 Rao-Scott cluster-adjusted chi-square (encounter-level, cluster = patient ID)"),
  c("Why Rao-Scott",  paste0(
    "DEFF = 130 in both windows (whole SE/naive SE ratio = 11x). ",
    "Naive chi-square ignores patient clustering and produces dramatically overconfident ",
    "intervals. GEE was computationally infeasible at 1.7M encounters within SLURM budget. ",
    "Rao-Scott correctly accounts for the complex survey-like structure (see 165-METHODS.md)."
  )),
  c("Cutoff",          glue("{CUTOFF} miles (CONFIG$far_from_care_cutoff_mi)")),
  c("Distance def.",   "ZIP-centroid straight-line distance, patient residence to encounter facility"),
  c("CBC def. (locked R/147)",
    "WBC (6690-2) + Hgb (718-7) + PLT (777-3) resulted same calendar date; ",
    "re-derived from DuckDB LAB_RESULT_CM (R/147 saves post-anchor only)"),
  c("CBC encounter match", "CBC date in [ADMIT_DATE, coalesce(DISCHARGE_DATE, ADMIT_DATE)]"),
  c("Windows",         paste0(
    "Whole record: all encounters with computed distance and known anchor date. ",
    "Post-anchor: ADMIT_DATE > hl_anchor_date; anchor day = pre (R/147 D-25)."
  )),
  c("Anchor date src", "get_hl_any_dx_ids() from utils_treatment.R (earliest HL DX_DATE)"),
  c("Encounter scope", paste0(
    "All ENC_TYPE retained (AV, OT, IC, ED, OA, TH, OS, IP, EI, IS, NI, UN). ",
    "Telehealth (TH) encounters carry provider ZIP, not patient travel burden."
  )),
  c("Primary",         "Unadjusted Rao-Scott F-statistic + svyglm OR (quasibinomial); clustering handled by survey design"),
  c("Sensitivity covariates", "rurality (ruca_category, R/116) + payer (PAYER_CATEGORY_PRIMARY, R/02) + SOURCE (site)"),
  c("SOURCE caveat",   paste0(
    "SOURCE is likely a near-proxy for far_from_care_100mi: encounters far from home often occur ",
    "at a different site than the patient's usual care. Adjusting for SOURCE may absorb a ",
    "substantial portion of the association. The adjusted estimate should be interpreted with this in mind."
  )),
  c("Rurality source", "R/116 encounter_ses_index_*.rds; ruca_category (Metropolitan/Micropolitan/Small town/Rural/Not coded)"),
  c("Rurality drop (whole)", suppress_display(results$whole$qc$n_miss_ruca)),
  c("Rurality drop (post)",  suppress_display(results$post$qc$n_miss_ruca)),
  c("Suppression rule", "Counts 1-10 displayed as '<11'; complementary suppression of row/col totals where back-calculation is possible; statistics computed on raw counts"),
  c("Sheet guide",     paste0(
    "KEY: this metadata. ",
    "A_crosstab: 2x2 counts + row % per window. ",
    "B_test: primary test statistics. ",
    "C_sensitivity: adjusted model. ",
    "QC: analysis-set counts per window."
  ))
)

key_df <- do.call(rbind, lapply(key_rows, function(r) {
  data.frame(Field = r[1], Value = paste(r[-1], collapse = " "), stringsAsFactors = FALSE)
}))

openxlsx::writeData(wb, "KEY", key_df, startRow = 1, startCol = 1, headerStyle = uf_header_style)
openxlsx::addStyle(wb, "KEY", style = uf_header_style, rows = 1, cols = 1:2)
openxlsx::setColWidths(wb, "KEY", cols = 1, widths = 30)
openxlsx::setColWidths(wb, "KEY", cols = 2, widths = 80)

# ---- Sheet: A_crosstab ----
openxlsx::addWorksheet(wb, "A_crosstab")

write_crosstab_block <- function(wb, sheet, res, start_col) {
  label    <- res$label
  ct_disp  <- res$crosstab$ct_disp
  ct_raw   <- res$crosstab$ct_raw
  ct_pct   <- res$crosstab$ct_row_pct

  # Header row
  openxlsx::writeData(wb, sheet, data.frame(X = label), startRow = 1, startCol = start_col)
  openxlsx::addStyle(wb, sheet, style = uf_header_style, rows = 1, cols = start_col:(start_col + 3))

  # Column headers
  openxlsx::writeData(wb, sheet,
    data.frame(X = c("", "CBC=0", "CBC=1", "Total")),
    startRow = 2, startCol = start_col, colNames = FALSE)
  openxlsx::addStyle(wb, sheet, style = bold_style, rows = 2, cols = start_col:(start_col + 3))

  # Build display block: 3 rows (far=0, far=1, Total), 4 cols (label, CBC=0, CBC=1, Total)
  for (ri in seq_len(3L)) {
    row_label <- c("far=0", "far=1", "Total")[ri]
    cells <- c(row_label, ct_disp[ri, ])
    openxlsx::writeData(wb, sheet,
      data.frame(t(cells)),
      startRow = 2L + ri, startCol = start_col, colNames = FALSE)
  }

  # Row % block (only for interior cells; blank where count suppressed)
  openxlsx::writeData(wb, sheet,
    data.frame(X = glue("{label} — row %")),
    startRow = 7L, startCol = start_col)
  openxlsx::addStyle(wb, sheet, style = section_style, rows = 7L, cols = start_col:(start_col + 3))
  openxlsx::writeData(wb, sheet,
    data.frame(X = c("", "CBC=0 %", "CBC=1 %", "Row N")),
    startRow = 8L, startCol = start_col, colNames = FALSE)
  openxlsx::addStyle(wb, sheet, style = bold_style, rows = 8L, cols = start_col:(start_col + 3))

  for (ri in 1:2) {
    row_label <- c("far=0", "far=1")[ri]
    # Blank % where the count is suppressed
    pct0 <- if (ct_disp[ri, 1] == "<11") "" else sprintf("%.1f%%", ct_pct[ri, 1])
    pct1 <- if (ct_disp[ri, 2] == "<11") "" else sprintf("%.1f%%", ct_pct[ri, 2])
    row_n <- ct_disp[ri, 3]
    openxlsx::writeData(wb, sheet,
      data.frame(t(c(row_label, pct0, pct1, row_n))),
      startRow = 8L + ri, startCol = start_col, colNames = FALSE)
  }
}

write_crosstab_block(wb, "A_crosstab", results$whole, start_col = 1L)
write_crosstab_block(wb, "A_crosstab", results$post,  start_col = 6L)
openxlsx::setColWidths(wb, "A_crosstab", cols = 1:10, widths = 16)

# ---- Sheet: B_test ----
openxlsx::addWorksheet(wb, "B_test")

fmt_p <- function(p) {
  if (is.na(p)) return(NA_character_)
  if (p < 0.001) return("<0.001")
  formatC(p, digits = 3, format = "f")
}
fmt_or <- function(x) if (is.na(x)) NA_character_ else formatC(x, digits = 3, format = "f")

b_rows <- list()
for (wn in c("whole", "post")) {
  pri <- results[[wn]]$primary
  b_rows[[wn]] <- data.frame(
    Window      = results[[wn]]$label,
    Method      = "Rao-Scott (F)",
    F_statistic = fmt_or(pri$statistic),
    df          = if (!is.na(pri$df)) as.character(pri$df) else NA_character_,
    p_chisq     = fmt_p(pri$p_chisq),
    OR          = fmt_or(pri$or),
    CI_lo       = fmt_or(pri$ci_lo),
    CI_hi       = fmt_or(pri$ci_hi),
    SE_logOR    = fmt_or(pri$se_log_or),
    p_svyglm    = fmt_p(pri$p_svyglm),
    DEFF        = fmt_or(pri$deff),
    N_enc       = suppress_display(pri$n_enc),
    N_pat       = suppress_display(pri$n_pat),
    Haldane     = as.character(pri$haldane),
    Error_msg   = if (is.na(pri$error)) "" else pri$error,
    stringsAsFactors = FALSE
  )
}
b_df <- do.call(rbind, b_rows)
openxlsx::writeData(wb, "B_test", b_df, startRow = 1, startCol = 1,
                    headerStyle = uf_header_style)
openxlsx::addStyle(wb, "B_test", style = uf_header_style, rows = 1, cols = 1:ncol(b_df))
openxlsx::setColWidths(wb, "B_test", cols = seq_len(ncol(b_df)), widths = 16)

# ---- Sheet: C_sensitivity ----
openxlsx::addWorksheet(wb, "C_sensitivity")

c_current_row <- 1L
for (wn in c("whole", "post")) {
  sens  <- results[[wn]]$sensitivity
  label <- results[[wn]]$label

  openxlsx::writeData(wb, "C_sensitivity",
    data.frame(X = label),
    startRow = c_current_row, startCol = 1L)
  openxlsx::addStyle(wb, "C_sensitivity", style = uf_header_style,
                     rows = c_current_row, cols = 1:6)
  c_current_row <- c_current_row + 1L

  if (!is.na(sens$error)) {
    openxlsx::writeData(wb, "C_sensitivity",
      data.frame(Field = "Error", Value = sens$error),
      startRow = c_current_row, startCol = 1L)
    c_current_row <- c_current_row + 2L
    next
  }

  # Adjusted primary result
  primary_adj_df <- data.frame(
    Field  = c("Adjusted OR (far_from_care)", "95% CI lower", "95% CI upper",
                "p (svyglm)", "N used (complete cases)", "N dropped (missing rurality)",
                "N dropped (missing payer)", "N dropped (missing SOURCE)"),
    Value  = c(fmt_or(sens$or_adj), fmt_or(sens$ci_lo_adj), fmt_or(sens$ci_hi_adj),
                fmt_p(sens$p_adj),
                as.character(sens$n_used),
                as.character(sens$n_drop_ruca),
                as.character(sens$n_drop_payer),
                as.character(sens$n_drop_src)),
    stringsAsFactors = FALSE
  )
  openxlsx::writeData(wb, "C_sensitivity", primary_adj_df,
                      startRow = c_current_row, startCol = 1L,
                      headerStyle = bold_style)
  c_current_row <- c_current_row + nrow(primary_adj_df) + 2L

  # Full coefficient table
  openxlsx::writeData(wb, "C_sensitivity",
    data.frame(X = glue("{label} — Full coefficient table")),
    startRow = c_current_row, startCol = 1L)
  openxlsx::addStyle(wb, "C_sensitivity", style = section_style,
                     rows = c_current_row, cols = 1:5)
  c_current_row <- c_current_row + 1L

  if (nrow(sens$coef_table) > 0L) {
    ct <- sens$coef_table
    ct$term <- rownames(ct)
    ct <- ct[, c("term", setdiff(names(ct), "term"))]
    openxlsx::writeData(wb, "C_sensitivity", ct,
                        startRow = c_current_row, startCol = 1L,
                        headerStyle = bold_style)
    c_current_row <- c_current_row + nrow(ct) + 3L
  } else {
    openxlsx::writeData(wb, "C_sensitivity",
      data.frame(Note = "Coefficient table unavailable (model error)"),
      startRow = c_current_row, startCol = 1L)
    c_current_row <- c_current_row + 3L
  }
}
openxlsx::setColWidths(wb, "C_sensitivity", cols = 1:8, widths = 30)

# ---- Sheet: QC ----
openxlsx::addWorksheet(wb, "QC")

qc_rows <- list()
for (wn in c("whole", "post")) {
  q <- results[[wn]]$qc
  qc_rows[[wn]] <- data.frame(
    Window              = q$window,
    N_encounters        = suppress_display(q$n_enc_in),
    N_patients          = suppress_display(q$n_pat_in),
    N_telehealth        = suppress_display(q$n_telehealth),
    N_missing_rurality  = suppress_display(q$n_miss_ruca),
    N_missing_payer     = suppress_display(q$n_miss_payer),
    CBC_match_rate_pct  = q$cbc_match_rate,
    N_patients_any_CBC  = suppress_display(q$n_pat_cbc),
    stringsAsFactors = FALSE
  )
}
qc_df <- do.call(rbind, qc_rows)
openxlsx::writeData(wb, "QC", qc_df, startRow = 1, startCol = 1,
                    headerStyle = uf_header_style)
openxlsx::addStyle(wb, "QC", style = uf_header_style, rows = 1, cols = 1:ncol(qc_df))
openxlsx::setColWidths(wb, "QC", cols = seq_len(ncol(qc_df)), widths = 22)

# ==============================================================================
# SECTION 7: SAVE WORKBOOK ----
# ==============================================================================

out_path <- file.path(
  CONFIG$output_dir,
  glue("distance_cbc_association_{RUN_DATE}.xlsx")
)
openxlsx::saveWorkbook(wb, out_path, overwrite = TRUE)
message(glue("  Workbook saved: {out_path}"))

# ==============================================================================
# SECTION 8: SESSION / RUNTIME ----
# ==============================================================================

RUN_ELAPSED <- proc.time() - RUN_START
message(glue("================================================================================"))
message(glue("R/165 distance_cbc_association COMPLETE"))
message(glue("  Elapsed : {round(RUN_ELAPSED['elapsed'] / 60, 1)} min"))
message(glue("  Output  : {out_path}"))
message(glue("================================================================================"))
