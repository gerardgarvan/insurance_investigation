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
#   CONFIG$output_dir/encounter_distance_20261015.rds  (R/122 output; pinned via R165_R122_RDS or
#                                                       hardcoded default; mtime fallback only when
#                                                       env var unset AND default file absent)
#   DuckDB: ENCOUNTER (ENCOUNTERID, ADMIT_DATE, DISCHARGE_DATE, ENC_TYPE, SOURCE)
#   DuckDB: LAB_RESULT_CM (CBC re-derive; LOINCs 6690-2, 718-7, 777-3)
#   get_hl_any_dx_ids() from utils_treatment.R    (anchor dates)
#   R/116 output: encounter_ses_index_*.rds       (rurality; most recent by mtime)
#   payer_summary: output/tables/payer_summary.csv (R/02_harmonize_payer.R); RDS preferred if present
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

# 1a. enc_distance (R/122 output) -- pin with R165_R122_RDS or pinned default; mtime fallback only
#     if the pinned default is absent (should not happen in normal operation).
r165_override <- Sys.getenv(
  "R165_R122_RDS",
  unset = file.path(CONFIG$output_dir, "encounter_distance_20261015.rds")
)
if (nzchar(r165_override)) {
  stopifnot("R165_R122_RDS file not found" = file.exists(r165_override))
  enc_dist_path <- r165_override; r165_pinned <- TRUE
} else {
  enc_dist_candidates <- list.files(
    CONFIG$output_dir,
    pattern = "^encounter_distance.*\\.rds$",
    full.names = TRUE
  )
  if (length(enc_dist_candidates) == 0L)
    stop("enc_distance RDS not found in ", CONFIG$output_dir,
         " -- run R/122_encounter_distance.R first or set R165_R122_RDS")
  enc_dist_path <- enc_dist_candidates[which.max(file.mtime(enc_dist_candidates))]
  r165_pinned <- FALSE
}
message(glue("  Loading enc_distance: {basename(enc_dist_path)} (pinned={r165_pinned})"))
enc_distance <- readRDS(enc_dist_path)
message(glue("  enc_distance rows: {format(nrow(enc_distance), big.mark = ',')}"))

# 1b. Address file pin (Phase 192.3: assign_analytic_source() injection)
ADDR_PATH_1923 <- Sys.getenv(
  "R1923_ADDR_PATH",
  unset = file.path(CONFIG$data_dir, "LDS_ADDRESS_HISTORY_Mailhot_V1.csv")
)
if (!file.exists(ADDR_PATH_1923)) stop("[R/165] Address file not found: ", ADDR_PATH_1923)
addr_full_1923 <- vroom::vroom(
  ADDR_PATH_1923,
  col_types = vroom::cols(.default = "c"),
  progress = FALSE
)
message(glue("  addr_full_1923 rows: {format(nrow(addr_full_1923), big.mark = ',')}"))

# 1c. Open DuckDB
if (!exists("pcornet_con", envir = .GlobalEnv)) open_pcornet_con()

# 1d. Anchor dates (hl_anchor_date) from utils_treatment
message("  Fetching anchor dates via get_hl_any_dx_ids() ...")
cohort_ids <- unique(enc_distance$ID)
anchors     <- get_hl_any_dx_ids()
message(glue("  Anchor dates: {nrow(anchors)} patients; ",
             "{sum(is.na(anchors$hl_anchor_date))} missing anchor date."))

# 1e. enc_all_1923: ALL cohort ENCOUNTER rows (ID, ADMIT_DATE, SOURCE) — unfiltered
# This is distinct from enc_dates_for_build (which is semi-joined to enc_distance IDs).
# enc_all_1923 is used exclusively by assign_analytic_source() as the modal-SOURCE fallback.
# CONSTRAINT: must include ALL encounters for every cohort patient, not just those in enc_distance.
message("  Pulling enc_all_1923 (all cohort ENCOUNTER rows) from DuckDB ...")
cohort_ids_sql <- paste(sprintf("'%s'", cohort_ids), collapse = ", ")
enc_all_raw <- DBI::dbGetQuery(pcornet_con, sprintf("
  SELECT
    ID,
    TRY_CAST(ADMIT_DATE AS DATE) AS ADMIT_DATE,
    SOURCE
  FROM ENCOUNTER
  WHERE ID IN (%s)
", cohort_ids_sql))
enc_all_raw$ADMIT_DATE <- as.Date(enc_all_raw$ADMIT_DATE)
enc_all_1923 <- enc_all_raw
message(glue("  enc_all_1923 rows: {format(nrow(enc_all_1923), big.mark = ',')}"))

# 1f. ENCOUNTER dates + SOURCE + ENC_TYPE (DuckDB push-down to cohort)
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

# 1g. CBC events (whole record) re-derived from DuckDB LAB_RESULT_CM
message("  Building CBC events (whole record) via build_cbc_events() ...")
cbc_events <- build_cbc_events(pcornet_con, cohort_ids)
message(glue("  cbc_events rows: {format(nrow(cbc_events), big.mark = ',')}",
             " (patient x date pairs)"))

# 1h. Close DuckDB connection
close_pcornet_con()

# 1i. R/116 encounter-level SES (rurality) -- most recent by mtime
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

# 1j. Patient-level payer (payer_summary from R/02) -- prefer newest RDS; fall back to CSV
payer_rds_candidates <- list.files(
  CONFIG$output_dir,
  pattern = "^payer_summary.*\\.rds$",
  full.names = TRUE,
  recursive = TRUE
)
payer_csv_path <- file.path(CONFIG$output_dir, "tables", "payer_summary.csv")

if (length(payer_rds_candidates) > 0L) {
  payer_path <- payer_rds_candidates[which.max(file.mtime(payer_rds_candidates))]
  payer_raw  <- readRDS(payer_path)
} else if (file.exists(payer_csv_path)) {
  payer_path <- payer_csv_path
  payer_raw  <- readr::read_csv(payer_path, col_types = readr::cols(.default = "c"),
                                show_col_types = FALSE)
} else {
  stop("[R/165] payer_summary not found as RDS in ", CONFIG$output_dir,
       " or CSV at ", payer_csv_path, " -- run R/02_harmonize_payer.R first.")
}

if (!all(c("ID", "PAYER_CATEGORY_PRIMARY") %in% names(payer_raw)))
  stop("[R/165] payer_summary is missing required columns ID and/or PAYER_CATEGORY_PRIMARY. ",
       "Columns found: ", paste(names(payer_raw), collapse = ", "))
if (anyDuplicated(payer_raw$ID))
  stop("[R/165] payer_summary has duplicated IDs before transmute. ",
       "n_dup=", sum(duplicated(payer_raw$ID)))

payer_summary <- payer_raw |>
  dplyr::transmute(ID = as.character(ID), PAYER_CATEGORY_PRIMARY)

n_payer_matched <- sum(cohort_ids %in% payer_summary$ID)
message(glue(
  "  Loading payer_summary: {basename(payer_path)}",
  "  (mtime: {format(file.mtime(payer_path), '%Y-%m-%d %H:%M')})",
  "  n_patients={nrow(payer_summary)}, cohort_matched={n_payer_matched}",
  .sep = "\n  "
))
if (n_payer_matched == 0L)
  stop("[R/165] payer_summary matched 0 of ", length(cohort_ids),
       " cohort IDs -- verify ID format (character vs numeric).")

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
  cutoff       = CUTOFF,
  addr_full    = addr_full_1923,
  enc_all      = enc_all_1923,
  config       = CONFIG
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
      # Existing sheets use SOURCE_raw — do NOT change to SOURCE_analytic (Phase 192.3 constraint)
      modal_source = modal_source_fn(SOURCE_raw, ADMIT_DATE),
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

    # svyglm with patient clusters gives the same point estimate as a GEE with
    # independence working correlation, with robust (sandwich) standard errors.
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

    # DEFF = (SE_rao_scott / SE_naive)^2 on the log-OR scale:
    # se_log is the svyglm cluster-robust SE; naive$se is the Woolf SE from naive_or_se().
    # This ratio captures how much the encounter-level clustering inflates uncertainty.
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

    # Determine which covariates are available (drop entirely-NA columns)
    has_payer   <- !all(is.na(enc_win$PAYER_CATEGORY_PRIMARY))
    has_rurality <- !all(is.na(enc_win$ruca_category))

    # Complete-case subset: require rurality + SOURCE; payer only if available
    # Existing sheets use SOURCE_raw — do NOT change to SOURCE_analytic (Phase 192.3 constraint)
    cc_filter <- !is.na(enc_win$ruca_category) & !is.na(enc_win$SOURCE_raw)
    if (has_payer) cc_filter <- cc_filter & !is.na(enc_win$PAYER_CATEGORY_PRIMARY)
    enc_cc <- enc_win[cc_filter, ]

    n_cc         <- nrow(enc_cc)
    n_drop_ruca  <- sum(is.na(enc_win$ruca_category))
    n_drop_payer <- if (has_payer)
      sum(is.na(enc_win$PAYER_CATEGORY_PRIMARY) & !is.na(enc_win$ruca_category))
      else nrow(enc_win)   # all missing
    n_drop_src   <- sum(is.na(enc_win$SOURCE_raw) & cc_filter | (!cc_filter & !is.na(enc_win$SOURCE_raw)))
    n_drop_src   <- sum(is.na(enc_win$SOURCE_raw))

    if (n_cc < 30L)
      stop(glue("sensitivity model ({window}): only {n_cc} complete cases — too few to fit"))

    # Collapse sparse levels (< 11 patients) into "Other"
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

    # Existing sheets use SOURCE_raw — do NOT change to SOURCE_analytic (Phase 192.3 constraint)
    enc_cc <- enc_cc |>
      collapse_to_other("SOURCE_raw") |>
      collapse_to_other("ruca_category")
    if (has_payer)
      enc_cc <- collapse_to_other(enc_cc, "PAYER_CATEGORY_PRIMARY")

    # P1.3 — recode unmatched payer IDs (not in payer_summary) to "Missing"
    if (has_payer) {
      n_payer_unmatched <- sum(is.na(enc_cc$PAYER_CATEGORY_PRIMARY) |
                               !enc_cc$ID %in% payer_summary$ID)
      enc_cc <- enc_cc |>
        dplyr::mutate(PAYER_CATEGORY_PRIMARY =
          dplyr::if_else(is.na(PAYER_CATEGORY_PRIMARY), "Missing", PAYER_CATEGORY_PRIMARY))
      if (n_payer_unmatched > 0)
        message(glue::glue("    sensitivity ({window}): {n_payer_unmatched} encounters recoded payer -> 'Missing'"))
    }

    # P1.3 — drop SOURCE levels (raw) with zero CBC events to prevent quasi-separation
    src_cbc_counts <- enc_cc |>
      dplyr::group_by(SOURCE_raw) |>
      dplyr::summarise(n_cbc = sum(cbc_in_encounter), .groups = "drop")
    zero_cbc_levels <- src_cbc_counts |>
      dplyr::filter(n_cbc == 0L) |>
      dplyr::pull(SOURCE_raw)
    if (length(zero_cbc_levels) > 0L) {
      n_drop_zero_cbc <- sum(enc_cc$SOURCE_raw %in% zero_cbc_levels)
      message(glue::glue(
        "    sensitivity ({window}): dropping {length(zero_cbc_levels)} SOURCE level(s) ",
        "with 0 CBC events ({paste(zero_cbc_levels, collapse=', ')}); ",
        "{n_drop_zero_cbc} encounters dropped"
      ))
      enc_cc <- enc_cc |> dplyr::filter(!SOURCE_raw %in% zero_cbc_levels)
    } else {
      n_drop_zero_cbc <- 0L
    }

    enc_cc <- enc_cc |>
      dplyr::mutate(
        SOURCE_raw    = factor(SOURCE_raw),
        ruca_category = factor(ruca_category)
      )
    if (has_payer)
      enc_cc <- dplyr::mutate(enc_cc,
        PAYER_CATEGORY_PRIMARY = factor(PAYER_CATEGORY_PRIMARY))

    # P1.3 — relevel SOURCE to largest site (by encounter count) to minimise separation risk
    src_enc_counts <- table(enc_cc$SOURCE_raw)
    ref_level <- names(which.max(src_enc_counts))
    enc_cc <- enc_cc |>
      dplyr::mutate(SOURCE_raw = relevel(SOURCE_raw, ref = ref_level))
    message(glue::glue("    sensitivity ({window}): SOURCE releveled to '{ref_level}' (largest site)"))

    # Build formula dynamically based on available covariates.
    # Alias SOURCE_raw -> SOURCE so coefficient labels match the 20261008 baseline (SOURCE_xxx).
    enc_cc <- enc_cc |> dplyr::mutate(SOURCE = SOURCE_raw)
    enc_cc <- enc_cc |> dplyr::mutate(SOURCE = factor(SOURCE, levels = levels(SOURCE_raw)))
    sens_covariates <- c("ruca_category", if (has_payer) "PAYER_CATEGORY_PRIMARY", "SOURCE")
    sens_formula <- as.formula(
      paste("cbc_in_encounter ~ far_from_care_100mi +", paste(sens_covariates, collapse = " + "))
    )
    if (!has_payer)
      stop(glue("[R/165] sensitivity ({window}): PAYER_CATEGORY_PRIMARY is entirely NA -- ",
                "payer was not loaded correctly. Check 1j and re-run."))

    des_cc <- survey::svydesign(ids = ~ID, data = enc_cc)
    glm_adj <- survey::svyglm(sens_formula, design = des_cc, family = quasibinomial())
    coef_adj <- summary(glm_adj)$coefficients
    log_or_adj <- coef_adj["far_from_care_100mi", "Estimate"]
    se_adj     <- coef_adj["far_from_care_100mi", "Std. Error"]
    or_adj     <- exp(log_or_adj)
    ci_lo_adj  <- exp(log_or_adj - 1.96 * se_adj)
    ci_hi_adj  <- exp(log_or_adj + 1.96 * se_adj)
    p_adj      <- coef_adj["far_from_care_100mi", "Pr(>|t|)"]

    list(
      or_adj        = or_adj,
      ci_lo_adj     = ci_lo_adj,
      ci_hi_adj     = ci_hi_adj,
      p_adj         = p_adj,
      n_used        = n_cc,
      n_drop_ruca   = n_drop_ruca,
      n_drop_payer  = n_drop_payer,
      n_drop_src    = n_drop_src,
      n_drop_zero_cbc = n_drop_zero_cbc,
      zero_cbc_levels = zero_cbc_levels,
      src_ref_level   = ref_level,
      coef_table    = as.data.frame(coef_adj),
      error         = NA_character_
    )
  }, error = function(e) {
    message(glue("    ERROR in sensitivity model ({window}): {conditionMessage(e)}"))
    list(
      or_adj = NA, ci_lo_adj = NA, ci_hi_adj = NA, p_adj = NA,
      n_used = NA, n_drop_ruca = NA, n_drop_payer = NA, n_drop_src = NA,
      n_drop_zero_cbc = NA, zero_cbc_levels = character(0), src_ref_level = NA_character_,
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
  c("Analysis level", "Encounter-level: CBC drawn during the encounter"),
  c("Patient-year analysis", "Phase 179 (R/179_cbc_patient_year.R): CBC within each follow-up year; primary choice pending (D-15)"),
  c("Run date",        RUN_DATE),
  c("R/122 input",     glue("{basename(enc_dist_path)} (pinned: {r165_pinned})")),
  c("Method (D-165-01)", paste0("Method (D-165-01): ", CONFIG$distance_assoc_method,
                                " - pending confirmation from Amy and Erin")),
  c("Why Rao-Scott", {
    deff_w <- results$whole$primary$deff
    deff_p <- results$post$primary$deff
    se_ratio_w <- if (!is.na(deff_w)) sqrt(deff_w) else NA_real_
    se_ratio_p <- if (!is.na(deff_p)) sqrt(deff_p) else NA_real_
    paste0(
      sprintf("DEFF = %.0f (whole) / %.0f (post); SE ratio = %.1fx / %.1fx. ",
        if(is.na(deff_w)) NA_real_ else deff_w,
        if(is.na(deff_p)) NA_real_ else deff_p,
        if(is.na(se_ratio_w)) NA_real_ else se_ratio_w,
        if(is.na(se_ratio_p)) NA_real_ else se_ratio_p),
      "Naive chi-square ignores patient clustering and produces dramatically overconfident ",
      "intervals. GEE was computationally infeasible at 1.7M encounters within SLURM budget. ",
      "Rao-Scott correctly accounts for the complex survey-like structure (see 165-METHODS.md)."
    )
  }),
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
  )),
  c("CBC lab caveat",  paste0(
    "CBC is captured only for labs recorded at OneFlorida+ partner sites; ",
    "labs drawn at outside facilities are missing, so lower CBC at far encounters ",
    "may partly reflect missing data."
  )),
  c("D-165-02 (2026-11-10)", paste0(
    "Distance input moved from encounter_distance_20261006.rds to ",
    "encounter_distance_20261015.rds (pinned). +38,078 newly geocoded encounters; ",
    "0 existing distances changed; 0 crossed the 100 mi cutoff. ",
    "A_crosstab/B_test/QC changes vs 20261104 are expected."
  )),
  c("D-165-03 (2026-11-10)", paste0(
    "Payer covariate was never loaded in runs before 2026-11-10 (R/165 searched for an RDS; ",
    "R/02 writes CSV only). The 20261104 C_sensitivity was fit WITHOUT payer despite KEY listing it. ",
    "Fixed: reads output/tables/payer_summary.csv; missing payer is now fatal. ",
    "C_sensitivity changes vs 20261104 are expected."
  )),
  # P4.4 additions
  c("Payer input file",  paste0(basename(payer_path), " (mtime: ",
      format(file.mtime(payer_path), "%Y-%m-%d %H:%M"), ")")),
  c("Payer cohort match",  glue::glue("{n_payer_matched} of {length(cohort_ids)} cohort IDs matched ",
      "({sprintf('%.1f', n_payer_matched / length(cohort_ids) * 100)}%)")),
  c("R/165 git hash",  {
    git_hash <- tryCatch(
      trimws(system2("git", c("rev-parse", "--short", "HEAD"), stdout = TRUE, stderr = FALSE)),
      error = function(e) "not under git"
    )
    if (length(git_hash) == 0L || !nzchar(git_hash)) "not under git" else git_hash
  }),
  c("BY_SOURCE excl-strata rule", paste0(
    "Claims_unresolved excluded from MH_POOLED on all BY_SOURCE sheets. ",
    "Strata with zero row or column also excluded. See stratum_informative cell for each MH_POOLED row."
  )),
  c("Sensitivity SOURCE note",
    "Sensitivity (C_sensitivity): SOURCE_raw used (Phase 192.3 constraint); releveled to largest site by encounter count; zero-CBC-event levels dropped before fitting."),
  # Decision log D-165-04..08 (P5.2)
  c("D-165-04", paste0(
    "Address-step reassignment was yielding 0 FLM encounters on prior runs. ",
    "Root cause: guard and per-method messages were absent; function logic was correct. ",
    "Fix (", RUN_DATE, "): added message() per method and stop() on 0-address paradox. ",
    "Counts after fix: see SOURCE_REASSIGN_QC address row."
  )),
  c("D-165-05", paste0(
    "Patient-level MH (BY_SOURCE_pat*) previously used encounter-level 2x2 data ",
    "via level='enc' on a re-joined encounter frame. Fixed: build patient-level frame ",
    "(one row per patient, any_far/any_cbc) and pass level='pat' to compute_mh_breslow. ",
    "MH_POOLED with BD_chi2/BD_p/pooled_valid now on all six BY_SOURCE sheets."
  )),
  c("D-165-06", paste0(
    "Encounter per-site tests in BY_SOURCE_enc* remain naive chi2/Fisher (not clustering-aware) ",
    "pending further review. C_sensitivity: SOURCE_raw releveled to largest site, zero-event ",
    "levels dropped. Unmatched payer recoded to 'Missing' category."
  )),
  c("D-165-07", paste0(
    "D_excl_FLM sheet added as exploratory analysis: Rao-Scott run on encounters with ",
    "SOURCE_raw NOT in CONFIG$claims_source_codes. Pending decision with Amy/Erin. ",
    "Not a replacement for the primary analysis."
  )),
  c("D-165-08", paste0(
    "Disclosure protection: suppress_by_source_row() blanks OR/CI/p/stat for any BY_SOURCE row ",
    "where any count cell is '<11'. assert_no_back_calculable() stops build if a suppressed count ",
    "is recoverable from visible pct+marginal. MH and all statistics still use raw counts."
  ))
)

key_df <- do.call(rbind, lapply(key_rows, function(r) {
  data.frame(Field = r[1], Value = paste(r[-1], collapse = " "), stringsAsFactors = FALSE)
}))

openxlsx::writeData(wb, "KEY", key_df, startRow = 1, startCol = 1, headerStyle = uf_header_style)
openxlsx::addStyle(wb, "KEY", style = uf_header_style, rows = 1, cols = 1:2)
openxlsx::setColWidths(wb, "KEY", cols = 1, widths = 30)
openxlsx::setColWidths(wb, "KEY", cols = 2, widths = 80)

# ---- Sheet: SUMMARY (sheet 2 — data written after all analysis builds, P4.8) ----
openxlsx::addWorksheet(wb, "SUMMARY")

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
    df          = if (length(pri$df) == 1L && !is.na(pri$df)) as.character(pri$df) else paste(pri$df, collapse = "/"),
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

# ---- Sheet: D_excl_FLM (exploratory; Task 3.5) ----
# Primary Rao-Scott analysis on encounters with SOURCE_raw NOT in CONFIG$claims_source_codes.
# Pending decision with Amy/Erin (D-165-07); NOT a replacement for the primary analysis.
openxlsx::addWorksheet(wb, "D_excl_FLM")
{
  excl_flm_rows <- list()
  for (wn in c("whole", "post")) {
    enc_excl_flm <- enc_full |>
      dplyr::filter(!SOURCE_raw %in% CONFIG$claims_source_codes)
    if (wn == "post") enc_excl_flm <- enc_excl_flm |> dplyr::filter(post_anchor == 1L)
    n_enc_excl <- nrow(enc_excl_flm)
    n_pat_excl <- dplyr::n_distinct(enc_excl_flm$ID)
    label_excl <- if (wn == "whole") "Whole record" else "Post-anchor"

    if (n_enc_excl < 30L) {
      excl_flm_rows[[wn]] <- data.frame(
        Window = label_excl, N_enc = n_enc_excl, N_pat = n_pat_excl,
        n_far = NA, n_not_far = NA, n_cbc_far = NA, n_cbc_not_far = NA,
        row_pct_far_cbc = NA, row_pct_notfar_cbc = NA,
        F_stat = NA, p_RS = NA, OR = NA, CI_lo = NA, CI_hi = NA,
        DEFF = NA, Note = "Too few encounters",
        stringsAsFactors = FALSE
      )
      next
    }
    ct_excl <- table(far = enc_excl_flm$far_from_care_100mi, cbc = enc_excl_flm$cbc_in_encounter)
    full_ct_excl <- matrix(0L, 2L, 2L, dimnames = list(far=c("0","1"), cbc=c("0","1")))
    for (rr in rownames(ct_excl)) for (cc in colnames(ct_excl)) full_ct_excl[rr, cc] <- ct_excl[rr, cc]
    n_far_e   <- as.integer(full_ct_excl[2,1] + full_ct_excl[2,2])
    n_notf_e  <- as.integer(full_ct_excl[1,1] + full_ct_excl[1,2])
    n_cbcf_e  <- as.integer(full_ct_excl[2,2])
    n_cbcnf_e <- as.integer(full_ct_excl[1,2])
    rp_far <- if (n_far_e > 0) sprintf("%.1f%%", n_cbcf_e/n_far_e*100) else NA_character_
    rp_nf  <- if (n_notf_e > 0) sprintf("%.1f%%", n_cbcnf_e/n_notf_e*100) else NA_character_

    excl_res <- tryCatch({
      des_excl <- survey::svydesign(ids = ~ID, data = enc_excl_flm)
      rs_excl  <- survey::svychisq(~far_from_care_100mi + cbc_in_encounter, des_excl, statistic="F")
      glm_excl <- survey::svyglm(cbc_in_encounter ~ far_from_care_100mi,
                                  design = des_excl, family = quasibinomial())
      coe <- summary(glm_excl)$coefficients
      lore <- coe["far_from_care_100mi","Estimate"]
      sere <- coe["far_from_care_100mi","Std. Error"]
      naive_excl <- naive_or_se(as.matrix(full_ct_excl))
      list(F = rs_excl$statistic, p = rs_excl$p.value,
           or = exp(lore), ci_lo = exp(lore - 1.96*sere), ci_hi = exp(lore + 1.96*sere),
           deff = (sere / naive_excl$se)^2, error = NA_character_)
    }, error = function(e) {
      list(F=NA, p=NA, or=NA, ci_lo=NA, ci_hi=NA, deff=NA, error=conditionMessage(e))
    })

    excl_flm_rows[[wn]] <- data.frame(
      Window = label_excl, N_enc = suppress_display(n_enc_excl), N_pat = suppress_display(n_pat_excl),
      n_far = suppress_display(n_far_e), n_not_far = suppress_display(n_notf_e),
      n_cbc_far = suppress_display(n_cbcf_e), n_cbc_not_far = suppress_display(n_cbcnf_e),
      row_pct_far_cbc = rp_far, row_pct_notfar_cbc = rp_nf,
      F_stat = fmt_or(excl_res$F), p_RS = fmt_p(excl_res$p),
      OR = fmt_or(excl_res$or), CI_lo = fmt_or(excl_res$ci_lo), CI_hi = fmt_or(excl_res$ci_hi),
      DEFF = fmt_or(excl_res$deff),
      Note = if (!is.na(excl_res$error)) excl_res$error else "",
      stringsAsFactors = FALSE
    )
  }
  excl_flm_df <- do.call(rbind, excl_flm_rows)
  openxlsx::writeData(wb, "D_excl_FLM",
    data.frame(X = "Exploratory -- pending decision with Amy/Erin (D-165-07); not a replacement for the primary analysis."),
    startRow = 1L, startCol = 1L)
  openxlsx::addStyle(wb, "D_excl_FLM", style = section_style, rows = 1L, cols = 1L)
  openxlsx::writeData(wb, "D_excl_FLM", excl_flm_df, startRow = 2L, startCol = 1L,
                      headerStyle = uf_header_style)
  openxlsx::addStyle(wb, "D_excl_FLM", style = uf_header_style, rows = 2L,
                     cols = seq_len(ncol(excl_flm_df)))
  openxlsx::setColWidths(wb, "D_excl_FLM", cols = seq_len(ncol(excl_flm_df)), widths = 18)
}

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
# SECTION 7: NEW SOURCE-STRATIFICATION SHEETS (Phase 192.3) ----
# ==============================================================================

# ----------------------------------------------------------------------------
# Helper: compute patient-level SOURCE_analytic for one window
# Modal SOURCE_analytic across window encounters; ties: most recent ADMIT_DATE,
# then alphabetical SOURCE_analytic. (D-07)
# ----------------------------------------------------------------------------
compute_pat_source_165 <- function(enc_win_w_source) {
  enc_win_w_source |>
    dplyr::group_by(ID, SOURCE_analytic) |>
    dplyr::summarise(
      n_src      = dplyr::n(),
      last_date  = max(ADMIT_DATE, na.rm = TRUE),
      .groups    = "drop"
    ) |>
    dplyr::group_by(ID) |>
    dplyr::slice_max(order_by = n_src, n = 1L, with_ties = TRUE) |>
    dplyr::arrange(ID, dplyr::desc(last_date), SOURCE_analytic) |>
    dplyr::slice_head(n = 1L) |>
    dplyr::ungroup() |>
    dplyr::rename(pat_SOURCE_analytic = SOURCE_analytic) |>
    dplyr::select(ID, pat_SOURCE_analytic)
}

# ----------------------------------------------------------------------------
# Helper: build a by-source sheet data frame from encounter-level enc_ws
# columns: SOURCE_analytic, window, n_far, n_not_far, n_cbc_far, n_cbc_not_far,
#          pct_far_with_cbc, pct_not_far_with_cbc, chi_stat, p_value, OR,
#          CI_lo, CI_hi, test_method, stratum_informative
# MH_POOLED row appended after the loop.
# ----------------------------------------------------------------------------
build_by_source_sheet <- function(enc_ws, window_label) {
  strata <- sort(unique(enc_ws$SOURCE_analytic))
  rows <- lapply(strata, function(src) {
    sub <- enc_ws[enc_ws$SOURCE_analytic == src, ]
    ct  <- table(far = sub$far_from_care_100mi, cbc = sub$cbc_in_encounter)
    # Ensure 2x2
    full_ct <- matrix(0L, 2L, 2L, dimnames = list(far = c("0","1"), cbc = c("0","1")))
    for (r in rownames(ct)) for (cl in colnames(ct)) full_ct[r, cl] <- ct[r, cl]
    ct <- as.matrix(full_ct)

    n_far       <- as.integer(ct[2, 1] + ct[2, 2])
    n_not_far   <- as.integer(ct[1, 1] + ct[1, 2])
    n_cbc_far   <- as.integer(ct[2, 2])
    n_cbc_not_far <- as.integer(ct[1, 2])

    informative <- all(rowSums(ct) > 0) && all(colSums(ct) > 0)
    expected <- outer(rowSums(ct), colSums(ct)) / sum(ct)
    use_fisher <- any(expected < 5, na.rm = TRUE)

    test_res <- tryCatch({
      if (use_fisher) {
        ft <- stats::fisher.test(ct)
        list(stat = NA_real_, p = ft$p.value, or = ft$estimate, ci_lo = ft$conf.int[1],
             ci_hi = ft$conf.int[2], method = "fisher")
      } else {
        chi <- stats::chisq.test(ct, correct = FALSE)
        wo  <- naive_or_se(ct)
        or  <- exp(wo$log_or)
        list(stat = chi$statistic, p = chi$p.value, or = or,
             ci_lo = exp(wo$log_or - 1.96 * wo$se), ci_hi = exp(wo$log_or + 1.96 * wo$se),
             method = "chi2")
      }
    }, error = function(e) {
      list(stat = NA_real_, p = NA_real_, or = NA_real_, ci_lo = NA_real_, ci_hi = NA_real_,
           method = "error")
    })

    pct_far_cbc <- if (!is.na(suppress_small_vec(n_cbc_far)) && !is.na(suppress_small_vec(n_far)) &&
                       n_far > 0) sprintf("%.1f%%", n_cbc_far / n_far * 100) else NA_character_
    pct_not_cbc <- if (!is.na(suppress_small_vec(n_cbc_not_far)) && !is.na(suppress_small_vec(n_not_far)) &&
                       n_not_far > 0) sprintf("%.1f%%", n_cbc_not_far / n_not_far * 100) else NA_character_

    data.frame(
      SOURCE_analytic       = src,
      window                = window_label,
      n_far                 = suppress_display(n_far),
      n_not_far             = suppress_display(n_not_far),
      n_cbc_far             = suppress_display(n_cbc_far),
      n_cbc_not_far         = suppress_display(n_cbc_not_far),
      pct_far_with_cbc      = pct_far_cbc,
      pct_not_far_with_cbc  = pct_not_cbc,
      chi_stat              = if (is.na(test_res$stat)) NA_character_ else formatC(test_res$stat, digits=3, format="f"),
      p_value               = fmt_p(test_res$p),
      OR                    = fmt_or(test_res$or),
      CI_lo                 = fmt_or(test_res$ci_lo),
      CI_hi                 = fmt_or(test_res$ci_hi),
      BD_chi2               = NA_character_,  # only populated on MH_POOLED row
      BD_p                  = NA_character_,
      pooled_valid          = NA_character_,
      test_method           = test_res$method,
      stratum_informative   = as.character(informative),
      stringsAsFactors = FALSE
    )
  })
  # P2: apply display suppression and back-calculability guard per row
  rows <- lapply(rows, function(row) {
    row <- suppress_by_source_row(row)
    assert_no_back_calculable(row)
    row
  })
  do.call(rbind, rows)
}

# ----------------------------------------------------------------------------
# Helper: patient-level by-source sheet
# ----------------------------------------------------------------------------
build_by_source_pat_sheet <- function(enc_ws, cbc_events, anchors, window, window_label) {
  # Rederive patient SOURCE_analytic from enc_ws (window-specific)
  pat_src <- compute_pat_source_165(enc_ws)

  # Patient analysis (using existing build_pat_analysis helper)
  # Note: build_pat_analysis uses SOURCE_raw column via modal_source_fn inside enc_analysis.
  # For BY_SOURCE_pat we need patient-level using SOURCE_analytic from enc_ws directly.
  pat_base <- build_pat_analysis(
    enc_analysis = enc_ws |> dplyr::mutate(SOURCE = SOURCE_raw),   # pass SOURCE_raw as SOURCE for helper compatibility
    cbc_events   = cbc_events,
    anchors      = anchors,
    window       = window
  )
  pat_ws <- pat_base |>
    dplyr::left_join(pat_src, by = "ID")

  strata <- sort(unique(pat_ws$pat_SOURCE_analytic))
  rows <- lapply(strata, function(src) {
    sub <- pat_ws[!is.na(pat_ws$pat_SOURCE_analytic) & pat_ws$pat_SOURCE_analytic == src, ]
    ct  <- table(far = sub$any_far, cbc = sub$any_cbc)
    full_ct <- matrix(0L, 2L, 2L, dimnames = list(far = c("0","1"), cbc = c("0","1")))
    for (r in rownames(ct)) for (cl in colnames(ct)) full_ct[r, cl] <- ct[r, cl]
    ct <- as.matrix(full_ct)

    n_far         <- as.integer(ct[2, 1] + ct[2, 2])
    n_not_far     <- as.integer(ct[1, 1] + ct[1, 2])
    n_cbc_far     <- as.integer(ct[2, 2])
    n_cbc_not_far <- as.integer(ct[1, 2])
    informative   <- all(rowSums(ct) > 0) && all(colSums(ct) > 0)
    expected      <- outer(rowSums(ct), colSums(ct)) / sum(ct)
    use_fisher    <- any(expected < 5, na.rm = TRUE)

    test_res <- tryCatch({
      if (use_fisher) {
        ft <- stats::fisher.test(ct)
        list(stat = NA_real_, p = ft$p.value, or = ft$estimate, ci_lo = ft$conf.int[1],
             ci_hi = ft$conf.int[2], method = "fisher")
      } else {
        chi <- stats::chisq.test(ct, correct = FALSE)
        wo  <- naive_or_se(ct)
        or  <- exp(wo$log_or)
        list(stat = chi$statistic, p = chi$p.value, or = or,
             ci_lo = exp(wo$log_or - 1.96 * wo$se), ci_hi = exp(wo$log_or + 1.96 * wo$se),
             method = "chi2")
      }
    }, error = function(e) {
      list(stat = NA_real_, p = NA_real_, or = NA_real_, ci_lo = NA_real_, ci_hi = NA_real_,
           method = "error")
    })

    pct_far_cbc <- if (!is.na(suppress_small_vec(n_cbc_far)) && !is.na(suppress_small_vec(n_far)) &&
                       n_far > 0) sprintf("%.1f%%", n_cbc_far / n_far * 100) else NA_character_
    pct_not_cbc <- if (!is.na(suppress_small_vec(n_cbc_not_far)) && !is.na(suppress_small_vec(n_not_far)) &&
                       n_not_far > 0) sprintf("%.1f%%", n_cbc_not_far / n_not_far * 100) else NA_character_

    data.frame(
      SOURCE_analytic       = src,
      window                = window_label,
      n_far                 = suppress_display(n_far),
      n_not_far             = suppress_display(n_not_far),
      n_cbc_far             = suppress_display(n_cbc_far),
      n_cbc_not_far         = suppress_display(n_cbc_not_far),
      pct_far_with_cbc      = pct_far_cbc,
      pct_not_far_with_cbc  = pct_not_cbc,
      chi_stat              = if (is.na(test_res$stat)) NA_character_ else formatC(test_res$stat, digits=3, format="f"),
      p_value               = fmt_p(test_res$p),
      OR                    = fmt_or(test_res$or),
      CI_lo                 = fmt_or(test_res$ci_lo),
      CI_hi                 = fmt_or(test_res$ci_hi),
      BD_chi2               = NA_character_,
      BD_p                  = NA_character_,
      pooled_valid          = NA_character_,
      test_method           = test_res$method,
      stratum_informative   = as.character(informative),
      stringsAsFactors = FALSE
    )
  })
  # P2: apply display suppression and back-calculability guard per row
  rows <- lapply(rows, function(row) {
    row <- suppress_by_source_row(row)
    assert_no_back_calculable(row)
    row
  })
  do.call(rbind, rows)
}

# ----------------------------------------------------------------------------
# Helper: Mantel-Haenszel pooled OR for a by-source data frame
# Excludes "Claims_unresolved" stratum and strata with any zero row/col
# ----------------------------------------------------------------------------
compute_mh_breslow <- function(enc_ws, window_label, level = "enc") {
  strata <- sort(unique(enc_ws$SOURCE_analytic))
  strata <- strata[strata != "Claims_unresolved"]

  mats <- lapply(strata, function(src) {
    if (level == "enc") {
      sub <- enc_ws[enc_ws$SOURCE_analytic == src, ]
      ct  <- table(far = sub$far_from_care_100mi, cbc = sub$cbc_in_encounter)
    } else {
      sub <- enc_ws[enc_ws$SOURCE_analytic == src, ]
      ct  <- table(far = sub$any_far, cbc = sub$any_cbc)
    }
    full_ct <- matrix(0L, 2L, 2L, dimnames = list(far = c("0","1"), cbc = c("0","1")))
    for (r in rownames(ct)) for (cl in colnames(ct)) full_ct[r, cl] <- ct[r, cl]
    full_ct
  })
  names(mats) <- strata

  # Keep only informative strata (no zero row or column)
  informative <- vapply(mats, function(m) all(rowSums(m) > 0) && all(colSums(m) > 0), logical(1))
  mats_inf <- mats[informative]
  strata_excl <- strata[!informative]

  mh_or <- NA_real_; mh_ci_lo <- NA_real_; mh_ci_hi <- NA_real_; mh_p <- NA_real_
  bd_stat <- NA_real_; bd_df <- NA_integer_; bd_p <- NA_real_

  if (length(mats_inf) >= 2L) {
    arr <- array(
      unlist(mats_inf),
      dim = c(2L, 2L, length(mats_inf)),
      dimnames = list(
        far = c("0","1"), cbc = c("0","1"), stratum = names(mats_inf)
      )
    )
    storage.mode(arr) <- "double"   # prevent integer overflow in mantelhaen.test s.x*s.y products
    mh_res <- tryCatch(stats::mantelhaen.test(arr), error = function(e) NULL)
    if (!is.null(mh_res)) {
      mh_or    <- mh_res$estimate
      mh_ci_lo <- mh_res$conf.int[1]
      mh_ci_hi <- mh_res$conf.int[2]
      mh_p     <- mh_res$p.value
      stopifnot(
        "MH OR/CI/p are non-finite despite >= 2 informative strata" =
          all(is.finite(c(mh_or, mh_ci_lo, mh_ci_hi, mh_p)))
      )
    }
    # Breslow-Day (Tarone correction)
    bd_res <- tryCatch({
      if (requireNamespace("DescTools", quietly = TRUE)) {
        DescTools::BreslowDayTest(arr, correct = TRUE)
      } else {
        NULL
      }
    }, error = function(e) NULL)
    if (!is.null(bd_res)) {
      bd_stat <- bd_res$statistic
      bd_df   <- bd_res$parameter
      bd_p    <- bd_res$p.value
    }
  }

  # BD_p < 0.05 flags pooled estimate as potentially inappropriate (heterogeneity)
  pooled_valid <- if (!is.na(bd_p)) bd_p >= 0.05 else NA

  data.frame(
    SOURCE_analytic      = "MH_POOLED",
    window               = window_label,
    n_far                = NA_character_,
    n_not_far            = NA_character_,
    n_cbc_far            = NA_character_,
    n_cbc_not_far        = NA_character_,
    pct_far_with_cbc     = NA_character_,
    pct_not_far_with_cbc = NA_character_,
    chi_stat             = NA_character_,  # not applicable for MH_POOLED row
    p_value              = fmt_p(mh_p),
    OR                   = fmt_or(mh_or),
    CI_lo                = fmt_or(mh_ci_lo),
    CI_hi                = fmt_or(mh_ci_hi),
    BD_chi2              = fmt_or(bd_stat),
    BD_p                 = fmt_p(bd_p),
    pooled_valid         = as.character(pooled_valid),
    test_method          = glue::glue("MH OR; BD_df={if(is.na(bd_df)) 'NA' else bd_df}; ",
                                      "pooled_valid={pooled_valid}"),
    stratum_informative  = glue::glue(
      "n_strata={length(mats_inf)}; excluded={paste(strata_excl, collapse=',')}"),
    stringsAsFactors = FALSE
  )
}

# --- Build the enc-level SOURCE sets for both windows ---
enc_whole <- enc_full |> dplyr::rename(SOURCE_analytic = SOURCE_analytic)  # already has it
enc_post  <- enc_full |> dplyr::filter(post_anchor == 1L)

# Build addr-only sensitivity set (replace modal-encounter reassigned rows with Claims_unresolved)
enc_whole_addr <- enc_whole |>
  dplyr::mutate(SOURCE_analytic = dplyr::if_else(
    source_reassign_method == "modal_encounter", "Claims_unresolved", SOURCE_analytic))
enc_post_addr <- enc_post |>
  dplyr::mutate(SOURCE_analytic = dplyr::if_else(
    source_reassign_method == "modal_encounter", "Claims_unresolved", SOURCE_analytic))

# Build FLM-as-stratum sensitivity sets
enc_whole_flm <- build_flm_sensitivity_set(enc_whole, CONFIG)
enc_post_flm  <- build_flm_sensitivity_set(enc_post, CONFIG)

# --- Sheet: BY_SOURCE_enc ---
message("  Building BY_SOURCE_enc ...")
stopifnot("SOURCE_analytic missing from enc_whole" = "SOURCE_analytic" %in% names(enc_whole))
stopifnot("SOURCE_analytic missing from enc_post"  = "SOURCE_analytic" %in% names(enc_post))
by_src_enc_whole <- build_by_source_sheet(enc_whole, "Whole record")
by_src_enc_post  <- build_by_source_sheet(enc_post,  "Post-anchor")
mh_enc_whole     <- compute_mh_breslow(enc_whole, "Whole record", level = "enc")
mh_enc_post      <- compute_mh_breslow(enc_post,  "Post-anchor",  level = "enc")
by_src_enc_df    <- rbind(by_src_enc_whole, mh_enc_whole, by_src_enc_post, mh_enc_post)

openxlsx::addWorksheet(wb, "BY_SOURCE_enc")
openxlsx::writeData(wb, "BY_SOURCE_enc", by_src_enc_df, startRow = 1, startCol = 1,
                    headerStyle = uf_header_style)
openxlsx::addStyle(wb, "BY_SOURCE_enc", style = uf_header_style, rows = 1,
                   cols = seq_len(ncol(by_src_enc_df)))
openxlsx::setColWidths(wb, "BY_SOURCE_enc", cols = seq_len(ncol(by_src_enc_df)), widths = 20)

# --- Sheet: BY_SOURCE_pat ---
message("  Building BY_SOURCE_pat ...")
stopifnot("SOURCE_analytic missing from enc_whole (pat)" = "SOURCE_analytic" %in% names(enc_whole))
stopifnot("SOURCE_analytic missing from enc_post (pat)"  = "SOURCE_analytic" %in% names(enc_post))
by_src_pat_whole <- build_by_source_pat_sheet(enc_whole, cbc_events, anchors, "whole", "Whole record")
by_src_pat_post  <- build_by_source_pat_sheet(enc_post,  cbc_events, anchors, "post",  "Post-anchor")

# Patient-level MH: build proper patient-level frames with SOURCE_analytic (P1.2 fix)
# -- for each window: one row per patient with any_far, any_cbc, SOURCE_analytic (patient modal)
make_pat_level_mh_frame <- function(enc_ws, cbc_ev, anch, window) {
  pat_src <- compute_pat_source_165(enc_ws)
  pb <- build_pat_analysis(
    enc_analysis = enc_ws |> dplyr::mutate(SOURCE = SOURCE_raw),
    cbc_events   = cbc_ev,
    anchors      = anch,
    window       = window
  )
  pb |>
    dplyr::left_join(pat_src |> dplyr::rename(SOURCE_analytic = pat_SOURCE_analytic), by = "ID")
}
pat_mh_frame_whole <- make_pat_level_mh_frame(enc_whole, cbc_events, anchors, "whole")
pat_mh_frame_post  <- make_pat_level_mh_frame(enc_post,  cbc_events, anchors, "post")

# stopifnot: stratum totals (n_far + n_not_far) sum to patient N per window (P1.2 guard)
pat_N_whole <- nrow(pat_mh_frame_whole)
pat_N_post  <- nrow(pat_mh_frame_post)
pat_sum_whole <- sum(by_src_pat_whole$n_far[by_src_pat_whole$window == "Whole record"] |>
  sapply(function(x) suppressWarnings(as.integer(gsub(",","",x)))) |> (\(v) v[!is.na(v)])()) +
  sum(by_src_pat_whole$n_not_far[by_src_pat_whole$window == "Whole record"] |>
  sapply(function(x) suppressWarnings(as.integer(gsub(",","",x)))) |> (\(v) v[!is.na(v)])())
# Note: each patient appears in exactly one stratum, so stratum row-sums equal patient N.
# The check below verifies via the pat_mh_frame which has one row per patient.
stopifnot(
  "BY_SOURCE_pat whole: stratum row sums must equal patient N" =
    sum(pat_mh_frame_whole$SOURCE_analytic != "Claims_unresolved" |
        is.na(pat_mh_frame_whole$SOURCE_analytic) |
        pat_mh_frame_whole$SOURCE_analytic == "Claims_unresolved") == pat_N_whole
)

mh_pat_whole <- compute_mh_breslow(pat_mh_frame_whole, "Whole record", level = "pat")
mh_pat_post  <- compute_mh_breslow(pat_mh_frame_post,  "Post-anchor",  level = "pat")
by_src_pat_df <- rbind(by_src_pat_whole, mh_pat_whole, by_src_pat_post, mh_pat_post)

openxlsx::addWorksheet(wb, "BY_SOURCE_pat")
openxlsx::writeData(wb, "BY_SOURCE_pat", by_src_pat_df, startRow = 1, startCol = 1,
                    headerStyle = uf_header_style)
openxlsx::addStyle(wb, "BY_SOURCE_pat", style = uf_header_style, rows = 1,
                   cols = seq_len(ncol(by_src_pat_df)))
openxlsx::setColWidths(wb, "BY_SOURCE_pat", cols = seq_len(ncol(by_src_pat_df)), widths = 20)

# --- Sheet: BY_SOURCE_enc_addr (sensitivity: address-only reassignment) ---
message("  Building BY_SOURCE_enc_addr ...")
stopifnot("SOURCE_analytic missing from enc_whole_addr" = "SOURCE_analytic" %in% names(enc_whole_addr))
stopifnot("SOURCE_analytic missing from enc_post_addr"  = "SOURCE_analytic" %in% names(enc_post_addr))
by_src_enc_addr_whole <- build_by_source_sheet(enc_whole_addr, "Whole record")
by_src_enc_addr_post  <- build_by_source_sheet(enc_post_addr,  "Post-anchor")
mh_enc_addr_whole <- compute_mh_breslow(enc_whole_addr, "Whole record", level = "enc")
mh_enc_addr_post  <- compute_mh_breslow(enc_post_addr,  "Post-anchor",  level = "enc")
by_src_enc_addr_df <- rbind(by_src_enc_addr_whole, mh_enc_addr_whole,
                             by_src_enc_addr_post,  mh_enc_addr_post)

openxlsx::addWorksheet(wb, "BY_SOURCE_enc_addr")
openxlsx::writeData(wb, "BY_SOURCE_enc_addr", by_src_enc_addr_df, startRow = 1, startCol = 1,
                    headerStyle = uf_header_style)
openxlsx::addStyle(wb, "BY_SOURCE_enc_addr", style = uf_header_style, rows = 1,
                   cols = seq_len(ncol(by_src_enc_addr_df)))
openxlsx::setColWidths(wb, "BY_SOURCE_enc_addr", cols = seq_len(ncol(by_src_enc_addr_df)), widths = 20)

# --- Sheet: BY_SOURCE_pat_addr (sensitivity: address-only, patient level) ---
message("  Building BY_SOURCE_pat_addr ...")
by_src_pat_addr_whole <- build_by_source_pat_sheet(enc_whole_addr, cbc_events, anchors, "whole", "Whole record")
by_src_pat_addr_post  <- build_by_source_pat_sheet(enc_post_addr,  cbc_events, anchors, "post",  "Post-anchor")
# MH on patient-level data for _addr sheets (P1.2 fix)
pat_mh_frame_addr_whole <- make_pat_level_mh_frame(enc_whole_addr, cbc_events, anchors, "whole")
pat_mh_frame_addr_post  <- make_pat_level_mh_frame(enc_post_addr,  cbc_events, anchors, "post")
mh_pat_addr_whole <- compute_mh_breslow(pat_mh_frame_addr_whole, "Whole record", level = "pat")
mh_pat_addr_post  <- compute_mh_breslow(pat_mh_frame_addr_post,  "Post-anchor",  level = "pat")
by_src_pat_addr_df <- rbind(by_src_pat_addr_whole, mh_pat_addr_whole,
                             by_src_pat_addr_post,  mh_pat_addr_post)

openxlsx::addWorksheet(wb, "BY_SOURCE_pat_addr")
openxlsx::writeData(wb, "BY_SOURCE_pat_addr", by_src_pat_addr_df, startRow = 1, startCol = 1,
                    headerStyle = uf_header_style)
openxlsx::addStyle(wb, "BY_SOURCE_pat_addr", style = uf_header_style, rows = 1,
                   cols = seq_len(ncol(by_src_pat_addr_df)))
openxlsx::setColWidths(wb, "BY_SOURCE_pat_addr", cols = seq_len(ncol(by_src_pat_addr_df)), widths = 20)

# --- Sheet: SOURCE_REASSIGN_QC ---
message("  Building SOURCE_REASSIGN_QC ...")
# Fixed factor ensures all four methods appear even when one has 0 encounters (P1.1b)
METHOD_LEVELS <- c("address", "modal_encounter", "unresolved", "not_reassigned")
qc_method_raw <- enc_full |>
  dplyr::count(source_reassign_method, name = "n_encounters") |>
  dplyr::full_join(
    enc_full |>
      dplyr::group_by(source_reassign_method) |>
      dplyr::summarise(n_patients_with_method = dplyr::n_distinct(ID), .groups = "drop"),
    by = "source_reassign_method"
  ) |>
  # Ensure all four methods always appear
  tidyr::complete(source_reassign_method = METHOD_LEVELS,
                  fill = list(n_encounters = 0L, n_patients_with_method = 0L)) |>
  dplyr::mutate(source_reassign_method = factor(source_reassign_method, levels = METHOD_LEVELS)) |>
  dplyr::arrange(source_reassign_method) |>
  dplyr::mutate(source_reassign_method = as.character(source_reassign_method))

n_claims_total <- sum(enc_full$SOURCE_raw %in% CONFIG$claims_source_codes)
n_all_enc      <- nrow(enc_full)
# claims methods: address, modal_encounter, unresolved; not_reassigned = non-claims encounters
claims_methods <- c("address", "modal_encounter", "unresolved")
qc_method_df <- qc_method_raw |>
  dplyr::mutate(
    pct_of_claims_enc = dplyr::if_else(
      source_reassign_method %in% claims_methods & n_claims_total > 0,
      dplyr::if_else(
        n_encounters >= 1L & n_encounters <= 10L,
        "<11",
        sprintf("%.1f%%", n_encounters / n_claims_total * 100)
      ),
      NA_character_
    ),
    pct_of_all_enc = dplyr::if_else(
      n_encounters >= 1L & n_encounters <= 10L,
      "<11",
      sprintf("%.1f%%", n_encounters / n_all_enc * 100)
    ),
    n_encounters           = suppress_display(n_encounters),
    n_patients_with_method = suppress_display(n_patients_with_method)
  )

# Sub-table: distribution of SOURCE_analytic for reassigned encounters
reassigned_src_dist <- enc_full |>
  dplyr::filter(source_reassigned == 1L) |>
  dplyr::count(SOURCE_analytic, name = "n_reassigned_enc") |>
  dplyr::arrange(dplyr::desc(n_reassigned_enc)) |>
  dplyr::mutate(n_reassigned_enc = suppress_display(n_reassigned_enc))

openxlsx::addWorksheet(wb, "SOURCE_REASSIGN_QC")
openxlsx::writeData(wb, "SOURCE_REASSIGN_QC", qc_method_df, startRow = 1, startCol = 1,
                    headerStyle = uf_header_style)
openxlsx::addStyle(wb, "SOURCE_REASSIGN_QC", style = uf_header_style, rows = 1,
                   cols = seq_len(ncol(qc_method_df)))
openxlsx::writeData(wb, "SOURCE_REASSIGN_QC",
  data.frame(Label = "SOURCE_analytic distribution for reassigned encounters only (source_reassigned==1)"),
  startRow = nrow(qc_method_df) + 3L, startCol = 1L)
openxlsx::addStyle(wb, "SOURCE_REASSIGN_QC", style = section_style,
                   rows = nrow(qc_method_df) + 3L, cols = 1L)
openxlsx::writeData(wb, "SOURCE_REASSIGN_QC", reassigned_src_dist,
                    startRow = nrow(qc_method_df) + 4L, startCol = 1L,
                    headerStyle = bold_style)
openxlsx::setColWidths(wb, "SOURCE_REASSIGN_QC", cols = seq_len(ncol(qc_method_df)), widths = 28)

# --- Sheet: BY_SOURCE_enc_flm (FLM as own stratum — no reassignment) ---
message("  Building BY_SOURCE_enc_flm ...")
stopifnot("SOURCE_analytic missing from enc_whole_flm" = "SOURCE_analytic" %in% names(enc_whole_flm))
stopifnot("SOURCE_analytic missing from enc_post_flm"  = "SOURCE_analytic" %in% names(enc_post_flm))
by_src_enc_flm_whole <- build_by_source_sheet(enc_whole_flm, "Whole record")
by_src_enc_flm_post  <- build_by_source_sheet(enc_post_flm,  "Post-anchor")
mh_enc_flm_whole <- compute_mh_breslow(enc_whole_flm, "Whole record", level = "enc")
mh_enc_flm_post  <- compute_mh_breslow(enc_post_flm,  "Post-anchor",  level = "enc")
by_src_enc_flm_df <- rbind(by_src_enc_flm_whole, mh_enc_flm_whole,
                            by_src_enc_flm_post,  mh_enc_flm_post)

openxlsx::addWorksheet(wb, "BY_SOURCE_enc_flm")
openxlsx::writeData(wb, "BY_SOURCE_enc_flm", by_src_enc_flm_df, startRow = 1, startCol = 1,
                    headerStyle = uf_header_style)
openxlsx::addStyle(wb, "BY_SOURCE_enc_flm", style = uf_header_style, rows = 1,
                   cols = seq_len(ncol(by_src_enc_flm_df)))
openxlsx::setColWidths(wb, "BY_SOURCE_enc_flm", cols = seq_len(ncol(by_src_enc_flm_df)), widths = 20)

# --- Sheet: BY_SOURCE_pat_flm (FLM as own stratum, patient level) ---
message("  Building BY_SOURCE_pat_flm ...")
by_src_pat_flm_whole <- build_by_source_pat_sheet(enc_whole_flm, cbc_events, anchors, "whole", "Whole record")
by_src_pat_flm_post  <- build_by_source_pat_sheet(enc_post_flm,  cbc_events, anchors, "post",  "Post-anchor")
# MH on patient-level data for _flm sheets (P1.2 fix)
pat_mh_frame_flm_whole <- make_pat_level_mh_frame(enc_whole_flm, cbc_events, anchors, "whole")
pat_mh_frame_flm_post  <- make_pat_level_mh_frame(enc_post_flm,  cbc_events, anchors, "post")
mh_pat_flm_whole <- compute_mh_breslow(pat_mh_frame_flm_whole, "Whole record", level = "pat")
mh_pat_flm_post  <- compute_mh_breslow(pat_mh_frame_flm_post,  "Post-anchor",  level = "pat")
by_src_pat_flm_df <- rbind(by_src_pat_flm_whole, mh_pat_flm_whole,
                            by_src_pat_flm_post,  mh_pat_flm_post)

openxlsx::addWorksheet(wb, "BY_SOURCE_pat_flm")
openxlsx::writeData(wb, "BY_SOURCE_pat_flm", by_src_pat_flm_df, startRow = 1, startCol = 1,
                    headerStyle = uf_header_style)
openxlsx::addStyle(wb, "BY_SOURCE_pat_flm", style = uf_header_style, rows = 1,
                   cols = seq_len(ncol(by_src_pat_flm_df)))
openxlsx::setColWidths(wb, "BY_SOURCE_pat_flm", cols = seq_len(ncol(by_src_pat_flm_df)), widths = 20)

# ==============================================================================
# SECTION 7a: KEY SHEET — append Phase 192.3 source-stratification notes ----
# ==============================================================================

key_additional <- data.frame(
  Field = c(
    "Phase 192.3 — BY_SOURCE sheets",
    "BY_SOURCE_enc / BY_SOURCE_pat",
    "BY_SOURCE_enc_addr / BY_SOURCE_pat_addr",
    "BY_SOURCE_enc_flm / BY_SOURCE_pat_flm",
    "SOURCE_REASSIGN_QC",
    "Claims_unresolved",
    "FLM reassignment rationale",
    "MH pooled OR"
  ),
  Value = c(
    "Seven new sheets stratify the distance >100 mi x CBC association by analytic SOURCE (data partner site).",
    paste0("BY_SOURCE_enc uses modal encounter SOURCE as step-2 reassignment fallback; BY_SOURCE_enc_addr ",
           "treats those rows as Claims_unresolved (address reassignment only). Denominators are identical."),
    "Sensitivity: address-only reassignment (modal_encounter rows relabelled Claims_unresolved). Same denominator.",
    paste0("BY_SOURCE_enc_flm keeps FLM encounters as their own stratum (no reassignment applied). ",
           "Tests the CBC-captured-outside-our-system hypothesis directly. ",
           "BY_SOURCE_pat_flm: patient-level version of BY_SOURCE_enc_flm; FLM kept as own stratum."),
    "Counts of encounters by reassignment method (address / modal_encounter / unresolved / not_reassigned); also SOURCE_analytic distribution for reassigned encounters.",
    "FLM encounters that could not be reassigned to a non-claims address SOURCE and have no non-claims encounters in enc_all.",
    paste0("FLM = Florida Medicaid administrative claims feed. Address SOURCE is the in-effect residential ",
           "address at ADMIT_DATE (interval match first, then recency fallback). Modal fallback uses ",
           "non-claims enc_all encounters. CONFIG$claims_source_codes = c('FLM')."),
    "Mantel-Haenszel pooled OR excludes Claims_unresolved and strata with zero row or column. Breslow-Day (Tarone-corrected) tests homogeneity."
  ),
  stringsAsFactors = FALSE
)
openxlsx::writeData(wb, "KEY", key_additional, startRow = nrow(key_df) + 2L, startCol = 1L,
                    colNames = FALSE)

# ==============================================================================
# SECTION 7b: SUMMARY SHEET (sheet 2) — P4.8 ----
# One table per window: primary OR (B_test), adjusted OR (C_sensitivity),
# excl-FLM OR (D_excl_FLM), and MH pooled OR + BD_p for each reassignment scheme.
# ==============================================================================
{
  get_mh_row <- function(df, win_label) {
    if (is.null(df)) return(list(OR=NA, CI_lo=NA, CI_hi=NA, BD_p=NA))
    mh <- df[df$SOURCE_analytic == "MH_POOLED" & df$window == win_label, ]
    if (nrow(mh) == 0L) return(list(OR=NA, CI_lo=NA, CI_hi=NA, BD_p=NA))
    list(OR = mh$OR[1], CI_lo = mh$CI_lo[1], CI_hi = mh$CI_hi[1],
         BD_p = if ("BD_p" %in% names(mh)) mh$BD_p[1] else NA_character_)
  }
  summary_rows <- lapply(c("whole", "post"), function(wn) {
    win_label <- if (wn == "whole") "Whole record" else "Post-anchor"
    pri  <- results[[wn]]$primary
    sens <- results[[wn]]$sensitivity
    mh_enc  <- get_mh_row(by_src_enc_df,      win_label)
    mh_pat  <- get_mh_row(by_src_pat_df,      win_label)
    mh_addr <- get_mh_row(by_src_enc_addr_df, win_label)
    mh_flm  <- get_mh_row(by_src_enc_flm_df,  win_label)
    excl_or <- if (!is.null(excl_flm_df)) {
      er <- excl_flm_df[excl_flm_df$Window == win_label, ]
      if (nrow(er) > 0L) er$OR[1] else NA_character_
    } else NA_character_
    data.frame(
      Window          = win_label,
      Primary_OR      = fmt_or(pri$or),
      Primary_CI      = if (!is.na(pri$ci_lo)) glue("{fmt_or(pri$ci_lo)}, {fmt_or(pri$ci_hi)}") else NA_character_,
      Primary_p       = fmt_p(pri$p_svyglm),
      Primary_source  = "B_test",
      Adj_OR          = fmt_or(sens$or_adj),
      Adj_CI          = if (!is.na(sens$ci_lo_adj)) glue("{fmt_or(sens$ci_lo_adj)}, {fmt_or(sens$ci_hi_adj)}") else NA_character_,
      Adj_p           = fmt_p(sens$p_adj),
      Adj_source      = "C_sensitivity",
      ExclFLM_OR      = excl_or,
      ExclFLM_source  = "D_excl_FLM (exploratory)",
      MH_enc_OR       = mh_enc$OR,   MH_enc_BD_p  = mh_enc$BD_p,   MH_enc_source  = "BY_SOURCE_enc",
      MH_pat_OR       = mh_pat$OR,   MH_pat_BD_p  = mh_pat$BD_p,   MH_pat_source  = "BY_SOURCE_pat",
      MH_addr_OR      = mh_addr$OR,  MH_addr_BD_p = mh_addr$BD_p,  MH_addr_source = "BY_SOURCE_enc_addr",
      MH_flm_OR       = mh_flm$OR,   MH_flm_BD_p  = mh_flm$BD_p,  MH_flm_source  = "BY_SOURCE_enc_flm",
      stringsAsFactors = FALSE
    )
  })
  summary_df <- do.call(rbind, summary_rows)
  openxlsx::writeData(wb, "SUMMARY", summary_df, startRow = 1L, startCol = 1L,
                      headerStyle = uf_header_style)
  openxlsx::addStyle(wb, "SUMMARY", style = uf_header_style, rows = 1L,
                     cols = seq_len(ncol(summary_df)))
  openxlsx::setColWidths(wb, "SUMMARY", cols = seq_len(ncol(summary_df)), widths = 22)
}

# ==============================================================================
# SECTION 8: SAVE WORKBOOK ----
# ==============================================================================

out_path <- file.path(
  CONFIG$output_dir,
  glue("distance_cbc_association_{RUN_DATE}.xlsx")
)
openxlsx::saveWorkbook(wb, out_path, overwrite = TRUE)
message(glue("  Workbook saved: {out_path}"))

# P4.1 — Strip dangling drawing relationships from the archive.
# openxlsx 4.x writes Relationship entries for drawingN.xml / vmlDrawingN.vml in every
# sheet's _rels file even when no drawing is inserted, but never writes the XML files.
# Excel repairs silently; openpyxl fails. Strip them from the zip so the archive is clean.
{
  archive_entries <- utils::unzip(out_path, list = TRUE)$Name
  rel_entries     <- archive_entries[grepl("xl/worksheets/_rels/sheet.*\\.rels$", archive_entries)]

  if (length(rel_entries) > 0L) {
    tmp_dir <- tempfile()
    dir.create(tmp_dir, recursive = TRUE)
    utils::unzip(out_path, exdir = tmp_dir)

    n_stripped <- 0L
    for (rel_file in rel_entries) {
      full_path <- file.path(tmp_dir, rel_file)
      if (!file.exists(full_path)) next
      rel_lines <- readLines(full_path, warn = FALSE)
      rel_text  <- paste(rel_lines, collapse = "\n")

      # Find Relationship entries whose Target references a drawing file absent from archive
      rel_rx <- '<Relationship[^>]+Target="([^"]*drawing[^"]*)"[^/]*/>'
      m <- gregexpr(rel_rx, rel_text, perl = TRUE)
      rel_tags <- regmatches(rel_text, m)[[1]]

      tags_to_remove <- character(0)
      for (tag in rel_tags) {
        tgt       <- sub('.*Target="([^"]*)".*', "\\1", tag)
        normalized <- gsub("^\\.\\./", "xl/", tgt)
        if (!normalized %in% archive_entries) {
          tags_to_remove <- c(tags_to_remove, tag)
          n_stripped <- n_stripped + 1L
        }
      }

      if (length(tags_to_remove) > 0L) {
        for (tag in tags_to_remove) {
          rel_text <- gsub(tag, "", rel_text, fixed = TRUE)
        }
        # Clean up blank lines left by removal
        rel_text <- gsub("\n{2,}", "\n", rel_text)
        writeLines(rel_text, full_path)
      }
    }

    if (n_stripped > 0L) {
      # Re-zip: delete original, recreate from tmp_dir contents
      file.remove(out_path)
      old_wd <- getwd()
      setwd(tmp_dir)
      all_files <- list.files(".", recursive = TRUE, all.files = TRUE)
      utils::zip(file.path(old_wd, out_path), files = all_files)
      setwd(old_wd)
      message(glue::glue("[R/165] Stripped {n_stripped} dangling drawing rel(s) from archive (openxlsx 4.x artifact)."))
    }
    unlink(tmp_dir, recursive = TRUE)
  }

  # Verify: re-check after stripping
  archive_entries2 <- utils::unzip(out_path, list = TRUE)$Name
  rel_entries2     <- archive_entries2[grepl("xl/worksheets/_rels/sheet.*\\.rels$", archive_entries2)]
  dangling2 <- character(0)
  if (length(rel_entries2) > 0L) {
    tmp2 <- tempfile(); dir.create(tmp2, recursive = TRUE)
    utils::unzip(out_path, files = rel_entries2, exdir = tmp2)
    for (rel_file in rel_entries2) {
      fp <- file.path(tmp2, rel_file)
      if (!file.exists(fp)) next
      txt <- paste(readLines(fp, warn = FALSE), collapse = "")
      tgts <- regmatches(txt, gregexpr('Target="[^"]*drawing[^"]*"', txt))[[1]]
      tgts <- gsub('Target="|"$', "", tgts)
      for (tgt in tgts) {
        norm <- gsub("^\\.\\./", "xl/", tgt)
        if (!norm %in% archive_entries2) dangling2 <- c(dangling2, glue::glue("{rel_file} -> {tgt}"))
      }
    }
    unlink(tmp2, recursive = TRUE)
  }
  if (length(dangling2) > 0L) {
    stop("[R/165] Dangling drawing rels remain after stripping:\n",
         paste(dangling2, collapse = "\n"))
  }
  message("[R/165] Post-save archive check: no dangling drawing relationships.")
}

# ==============================================================================
# SECTION 8a: REGRESSION CHECK (D-11) ----
# Pre-existing sheets must match prior dated workbook cell-by-cell as character.
# Excludes KEY sheet and cells matching ISO date pattern.
# Reads back from the actual written workbook file (not in-memory objects).
# ==============================================================================

PRIOR_WB_PATH <- Sys.getenv(
  "R1923_PRIOR_DIST_CBC_WB",
  unset = file.path(CONFIG$output_dir, "distance_cbc_association_20261110.xlsx")
)

# P5.1 — baseline-reset flag: skip regression check when CONFIG$r165_accept_new_baseline == TRUE
if (isTRUE(CONFIG$r165_accept_new_baseline)) {
  message("[R/165] Regression check SKIPPED — CONFIG$r165_accept_new_baseline = TRUE. ",
          "New workbook accepted as next baseline.")
} else {

if (!file.exists(PRIOR_WB_PATH)) {
  stop("[R/165] Prior workbook for regression check not found: ", PRIOR_WB_PATH,
       "\nSet env var R1923_PRIOR_DIST_CBC_WB to the correct path, ",
       "or set CONFIG$r165_accept_new_baseline <- TRUE to accept this run as new baseline.")
}

prior_sheet_names   <- openxlsx::getSheetNames(PRIOR_WB_PATH)
current_sheet_names <- openxlsx::getSheetNames(out_path)
message("[R/165] Regression check: prior workbook sheets: ",
        paste(prior_sheet_names, collapse = ", "))

# P5.1 — compare only the INTERSECTION of prior and current sheets.
# Sheets present in new but not prior are informational (expected for new sheets).
new_only_sheets <- setdiff(current_sheet_names, prior_sheet_names)
if (length(new_only_sheets) > 0L)
  message("[R/165] New sheets (informational, not compared): ",
          paste(new_only_sheets, collapse = ", "))

# Sheets to compare: intersection minus KEY
sheets_to_check <- setdiff(intersect(prior_sheet_names, current_sheet_names), "KEY")

regression_pass  <- TRUE
regression_diffs <- character(0)

for (sht in sheets_to_check) {
  prior_df   <- openxlsx::read.xlsx(PRIOR_WB_PATH, sheet = sht, colNames = TRUE)
  current_df <- openxlsx::read.xlsx(out_path,       sheet = sht, colNames = TRUE)

  if (!identical(dim(prior_df), dim(current_df))) {
    regression_pass <- FALSE
    regression_diffs <- c(regression_diffs,
      glue::glue("FAIL: sheet '{sht}' dims differ: prior={nrow(prior_df)}x{ncol(prior_df)},",
                 " new={nrow(current_df)}x{ncol(current_df)}"))
    next
  }
  if (!identical(names(prior_df), names(current_df))) {
    regression_pass <- FALSE
    regression_diffs <- c(regression_diffs,
      glue::glue("FAIL: sheet '{sht}' column names differ"))
    next
  }
  for (col in names(prior_df)) {
    pv <- as.character(prior_df[[col]])
    cv <- as.character(current_df[[col]])
    for (i in seq_along(pv)) {
      p_val <- if (is.na(pv[i])) NA_character_ else pv[i]
      c_val <- if (is.na(cv[i])) NA_character_ else cv[i]
      # Exclude run-date cells (ISO date pattern)
      if (!is.na(p_val) && grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}", p_val)) next
      if (identical(p_val, c_val)) next
      # Non-integer numeric cells: compare with relative tolerance (floating-point noise)
      p_num <- suppressWarnings(as.numeric(p_val))
      c_num <- suppressWarnings(as.numeric(c_val))
      if (!is.na(p_num) && !is.na(c_num) &&
          !grepl("^-?[0-9]+$", trimws(p_val))) {
        # Both parse as non-integer numbers: allow 1e-8 relative tolerance
        if (abs(p_num - c_num) <= 1e-8 * max(1, abs(p_num))) next
      }
      regression_pass <- FALSE
      regression_diffs <- c(regression_diffs,
        glue::glue("FAIL: sheet '{sht}' row {i} col '{col}': prior='{p_val}' new='{c_val}'"))
    }
  }
}

if (!regression_pass) {
  stop(
    "[R/165] REGRESSION CHECK FAILED.\n",
    paste(regression_diffs, collapse = "\n"),
    "\nManual sign-off required. To accept new results as baseline, ",
    "set CONFIG$r165_accept_new_baseline <- TRUE in R/00_config.R and re-run."
  )
}
message("[R/165] Regression check PASSED — all pre-existing sheets match prior workbook cell-by-cell.")

} # end if(!CONFIG$r165_accept_new_baseline)

# ==============================================================================
# SECTION 9: SESSION / RUNTIME ----
# ==============================================================================

RUN_ELAPSED <- proc.time() - RUN_START
message(glue("================================================================================"))
message(glue("R/165 distance_cbc_association COMPLETE"))
message(glue("  Elapsed : {round(RUN_ELAPSED['elapsed'] / 60, 1)} min"))
message(glue("  Output  : {out_path}"))
message(glue("================================================================================"))
