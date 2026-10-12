# ==============================================================================
# 177_temporal_match_sizing.R -- Temporal ZIP-Match Sizing Memo (Phase 177)
# ==============================================================================
#
# Purpose:
#   Size how many Phase 165 analysis encounters a temporal ZIP match would add,
#   project how many would be >100 mi, reconcile R/121 vs R/122, and apply the
#   locked decision rule (CONTEXT D-03). Read-only investigation.
#
# Inputs:
#   output/zip_problem_inventory_<date>.rds   (R/121 output; pinned or most recent)
#   output/encounter_distance_<date>.rds      (R/122 output; same file R/165 used)
#
# Outputs:
#   output/temporal_match_sizing_<YYYYMMDD>.xlsx
#   output/internal/temporal_match_sizing_encounters_<YYYYMMDD>.rds
#
# Read-only: no other files written.
#
# Environment overrides (set before sourcing):
#   R177_R121_RDS -- path to a specific R/121 RDS (skips most-recent search)
#   R177_R122_RDS -- path to a specific R/122 RDS (skips most-recent search)
#
# Dependencies:
#   R/00_config.R (auto-sources utils_address.R, utils_distance_cbc.R, etc.)
#   utils/utils_zip_calendar.R (sourced explicitly; compute_encounter_distance)
#   dplyr, openxlsx, glue, zipcodeR
#
# Requirements: Phase 177 sizing memo
#
# Usage:
#   sbatch slurm/177_temporal_match_sizing.sbatch   (preferred)
#   Rscript R/177_temporal_match_sizing.R           (compute node only)
#
# ==============================================================================

# SECTION 0: SETUP ----

suppressPackageStartupMessages({
  library(dplyr)
  library(openxlsx)
  library(glue)
  library(zipcodeR)
})

source("R/00_config.R")
# 00_config.R auto-sources utils_address.R (get_zip9_at_date, normalize_zip5_raw),
# utils_distance_cbc.R (build_enc_analysis, suppress_small_vec, suppress_display).

# utils_zip_calendar.R provides compute_encounter_distance() and build_patient_zip_calendar().
# It is NOT auto-sourced by 00_config.R; source explicitly (matches R/122 pattern).
source("R/utils/utils_zip_calendar.R")

message("================================================================================")
message("R/177 temporal_match_sizing -- Phase 177 Sizing Memo")
message("================================================================================")

RUN_DATE <- format(Sys.Date(), "%Y%m%d")
CUTOFF   <- CONFIG$far_from_care_cutoff_mi

# Output paths
out_dir      <- CONFIG$output_dir
out_internal <- file.path(out_dir, "internal")
if (!dir.exists(out_internal)) dir.create(out_internal, recursive = TRUE, showWarnings = FALSE)

OUTPUT_XLSX <- file.path(out_dir, glue("temporal_match_sizing_{RUN_DATE}.xlsx"))
OUTPUT_RDS  <- file.path(out_internal, glue("temporal_match_sizing_encounters_{RUN_DATE}.rds"))

message(glue("  Output XLSX : {OUTPUT_XLSX}"))
message(glue("  Output RDS  : {OUTPUT_RDS}"))
message(glue("  Cutoff      : {CUTOFF} mi"))

# ==============================================================================
# SECTION 1: INPUTS ----
# ==============================================================================

# --- 1a. R/121 RDS -----------------------------------------------------------
# Priority: R177_R121_RDS env var > pinned path from Phase 176 > most recent by mtime.
r121_override <- Sys.getenv("R177_R121_RDS", unset = "")
r121_pinned   <- ""   # Set to a specific path once Phase 176 run is validated.

r121_path <- if (nzchar(r121_override) && file.exists(r121_override)) {
  message(glue("  [R/121 RDS] Using R177_R121_RDS override: {r121_override}"))
  r121_override
} else if (nzchar(r121_pinned) && file.exists(r121_pinned)) {
  message(glue("  [R/121 RDS] Using pinned path: {r121_pinned}"))
  r121_pinned
} else {
  candidates <- list.files(
    out_dir,
    pattern = "^zip_problem_inventory.*\\.rds$",
    full.names = TRUE
  )
  if (length(candidates) == 0L)
    stop("[R/177] R/121 RDS not found in ", out_dir,
         " -- run R/121_zip_problem_inventory.R first, or set R177_R121_RDS.")
  sel <- candidates[which.max(file.mtime(candidates))]
  message(glue("  [R/121 RDS] Falling back to most recent: {basename(sel)}"))
  message("  NOTE: Pin this path in R177_R121_RDS or r121_pinned once Phase 176 is validated.")
  sel
}

r121 <- readRDS(r121_path)
pat121 <- r121$patients   # one row per patient; columns include PATID, triage, F01_missing_zip5, ...
message(glue("  R/121 patients: {nrow(pat121)}"))

# --- 1b. R/122 RDS -----------------------------------------------------------
# Priority: R177_R122_RDS env var > most recent by mtime (same file R/165 used).
r122_override <- Sys.getenv("R177_R122_RDS", unset = "")

r122_path <- if (nzchar(r122_override) && file.exists(r122_override)) {
  message(glue("  [R/122 RDS] Using R177_R122_RDS override: {r122_override}"))
  r122_override
} else {
  candidates <- list.files(
    out_dir,
    pattern = "^encounter_distance.*\\.rds$",
    full.names = TRUE
  )
  if (length(candidates) == 0L)
    stop("[R/177] R/122 RDS not found in ", out_dir,
         " -- run R/122_encounter_distance.R first, or set R177_R122_RDS.")
  sel <- candidates[which.max(file.mtime(candidates))]
  message(glue("  [R/122 RDS] Most recent by mtime: {basename(sel)}"))
  sel
}

enc_distance <- readRDS(r122_path)
message(glue("  enc_distance rows: {format(nrow(enc_distance), big.mark = ',')}"))

r121_pinned_flag  <- nzchar(r121_pinned) && file.exists(r121_pinned)
r122_pinned_flag  <- nzchar(r122_override) && file.exists(r122_override)

# ==============================================================================
# SECTION 2: BUILD PHASE 165 ANALYSIS SET (exact replica of R/165 logic) ----
# ==============================================================================
# R/165 requires: anchors from get_hl_any_dx_ids(), enc_dates from DuckDB.
# R/177 must replicate exactly -- same build_enc_analysis() call, same CUTOFF.

message("--- Building Phase 165 analysis set via build_enc_analysis() ---")

# Anchor dates
# Primary: get_hl_any_dx_ids() requires DIAGNOSIS table in DuckDB.
# Fallback: confirmed_hl_cohort.rds (R/47 output) has first_hl_dx_date = anchor.
cohort_ids <- unique(enc_distance$ID)
anchors <- tryCatch(
  get_hl_any_dx_ids(),
  error = function(e) {
    message("  get_hl_any_dx_ids() failed: ", conditionMessage(e))
    cohort_rds <- file.path(CONFIG$output_dir, "confirmed_hl_cohort.rds")
    if (!file.exists(cohort_rds))
      stop("Fallback anchor source not found: ", cohort_rds,
           "\nEnsure R/47 has been run or DIAGNOSIS is available in DuckDB.")
    message("  Falling back to confirmed_hl_cohort.rds (R/47 output) for anchor dates.")
    rds <- readRDS(cohort_rds)
    dplyr::tibble(
      ID                 = rds$ID,
      hl_anchor_date     = as.Date(rds$first_hl_dx_date),
      in_confirmed_cohort = TRUE
    )
  }
)
message(glue("  Anchors: {nrow(anchors)} patients; ",
             "{sum(is.na(anchors$hl_anchor_date))} missing anchor date."))

# enc_dates from DuckDB (ENCOUNTERID, DISCHARGE_DATE, SOURCE) -- matches R/165 Section 1d.
if (!exists("pcornet_con", envir = .GlobalEnv)) open_pcornet_con()

enc_ids_sql <- paste(sprintf("'%s'", unique(enc_distance$ENCOUNTERID)), collapse = ", ")
enc_dates_raw <- DBI::dbGetQuery(pcornet_con, sprintf("
  SELECT
    ENCOUNTERID,
    TRY_CAST(ADMIT_DATE      AS DATE) AS ADMIT_DATE,
    TRY_CAST(DISCHARGE_DATE  AS DATE) AS DISCHARGE_DATE,
    ENC_TYPE,
    SOURCE
  FROM ENCOUNTER
  WHERE ENCOUNTERID IN (%s)
", enc_ids_sql))
enc_dates_raw$ADMIT_DATE     <- as.Date(enc_dates_raw$ADMIT_DATE)
enc_dates_raw$DISCHARGE_DATE <- as.Date(enc_dates_raw$DISCHARGE_DATE)
close_pcornet_con()

message(glue("  enc_dates_raw rows: {format(nrow(enc_dates_raw), big.mark = ',')}"))

# Attach ENC_TYPE to enc_distance (matches R/165 Section 2 pattern)
if (!"ENC_TYPE" %in% names(enc_distance)) {
  enc_distance <- enc_distance |>
    dplyr::left_join(
      enc_dates_raw |> dplyr::select(ENCOUNTERID, ENC_TYPE),
      by = "ENCOUNTERID"
    )
}

# CBC events (whole record) -- needed only to produce enc_now; R/177 does not
# perform the CBC association analysis but must replicate build_enc_analysis().
if (!exists("pcornet_con", envir = .GlobalEnv)) open_pcornet_con()
cbc_events <- build_cbc_events(pcornet_con, cohort_ids)
close_pcornet_con()
message(glue("  cbc_events rows: {format(nrow(cbc_events), big.mark = ',')}"))

enc_dates_for_build <- enc_dates_raw |>
  dplyr::select(ENCOUNTERID, DISCHARGE_DATE, SOURCE)

enc_now <- build_enc_analysis(
  enc_distance = enc_distance,
  cbc_events   = cbc_events,
  anchors      = anchors,
  enc_dates    = enc_dates_for_build,
  cutoff       = CUTOFF
)
# enc_now: one row per ENCOUNTERID with distance_status == "computed" and known anchor date.
# Columns: ID, ENCOUNTERID, ADMIT_DATE, ENC_TYPE, SOURCE,
#          distance_mi, far_from_care_100mi, post_anchor, cbc_in_encounter.

n_enc_whole <- nrow(enc_now)
n_pat_whole <- dplyr::n_distinct(enc_now$ID)
n_enc_post  <- sum(enc_now$post_anchor == 1L)
n_pat_post  <- dplyr::n_distinct(enc_now$ID[enc_now$post_anchor == 1L])
n_far_whole <- sum(enc_now$far_from_care_100mi == 1L, na.rm = TRUE)
n_far_post  <- sum(enc_now$post_anchor == 1L & enc_now$far_from_care_100mi == 1L, na.rm = TRUE)

message(glue(
  "  enc_now: {n_enc_whole} encounters / {n_pat_whole} patients (whole); ",
  "{n_enc_post} encounters / {n_pat_post} patients (post-anchor)"
))
message(glue(
  "  Current far (>{CUTOFF} mi): {n_far_whole} whole / {n_far_post} post-anchor"
))

# ==============================================================================
# SECTION 3: BUILD CANDIDATES ----
# ==============================================================================
# Candidates = patient_zip_missing encounters that would enter the Phase 165 set
# IF they had a distance (i.e., satisfy all other R/165 filters except distance_status).
#
# R/165 keeps: distance_status == "computed" AND inner_join on anchor.
# We mirror: distance_status == "patient_zip_missing" AND inner_join on anchor.
# All other joins (enc_dates, cbc_events) are applied to be conservative.

message("--- Building candidates (patient_zip_missing encounters) ---")

enc_pzm <- enc_distance |>
  dplyr::filter(distance_status == "patient_zip_missing")

# Attach DISCHARGE_DATE, SOURCE, ENC_TYPE (mirrors build_enc_analysis steps 2-3)
enc_pzm_dates <- enc_pzm |>
  dplyr::left_join(
    enc_dates_raw |> dplyr::select(ENCOUNTERID, DISCHARGE_DATE, SOURCE),
    by = "ENCOUNTERID"
  )

if (!"ENC_TYPE" %in% names(enc_pzm_dates)) {
  enc_pzm_dates <- enc_pzm_dates |>
    dplyr::left_join(
      enc_dates_raw |> dplyr::select(ENCOUNTERID, ENC_TYPE),
      by = "ENCOUNTERID"
    )
}

# Inner join on anchor (mirrors build_enc_analysis step 4)
enc_pzm_anchored <- enc_pzm_dates |>
  dplyr::inner_join(
    anchors |> dplyr::select(ID, hl_anchor_date),
    by = "ID"
  )

# post_anchor flag (mirrors step 5)
enc_pzm_anchored <- enc_pzm_anchored |>
  dplyr::mutate(
    ADMIT_DATE  = as.Date(ADMIT_DATE),
    post_anchor = as.integer(ADMIT_DATE > hl_anchor_date)
  )

cand <- enc_pzm_anchored
n_cand_whole <- nrow(cand)
n_cand_post  <- sum(cand$post_anchor == 1L)
n_cand_pat_whole <- dplyr::n_distinct(cand$ID)
n_cand_pat_post  <- dplyr::n_distinct(cand$ID[cand$post_anchor == 1L])

message(glue(
  "  Candidates: {n_cand_whole} encounters / {n_cand_pat_whole} patients (whole); ",
  "{n_cand_post} post-anchor / {n_cand_pat_post} patients"
))

# ==============================================================================
# SECTION 4: ATTACH R/121 TRIAGE TO CANDIDATES ----
# ==============================================================================

message("--- Attaching R/121 triage to candidates ---")

# R/121 patient key is PATID; R/122 uses ID. Join on patient identity.
triage_map <- pat121 |>
  dplyr::select(PATID, triage) |>
  dplyr::mutate(ID = as.character(PATID))   # harmonize key type

cand <- cand |>
  dplyr::mutate(ID = as.character(ID)) |>
  dplyr::left_join(triage_map |> dplyr::select(ID, triage), by = "ID") |>
  dplyr::mutate(triage = dplyr::coalesce(triage, "not in R/121"))

message(glue("  Triage distribution among candidates:\n",
             paste(utils::capture.output(
               print(table(cand$triage, useNA = "ifany"))), collapse = "\n")))

# ==============================================================================
# SECTION 5: CONTEXT ROW (all Phase-165-eligible encounters of NEEDS_TEMPORAL_MATCH patients)
# ==============================================================================

message("--- Building context row (NEEDS_TEMPORAL_MATCH patients in enc_now) ---")

ntm_ids <- unique(pat121$PATID[pat121$triage == "NEEDS_TEMPORAL_MATCH"])
ntm_ids_chr <- as.character(ntm_ids)

context_whole <- enc_now |> dplyr::filter(ID %in% ntm_ids_chr)
n_ctx_whole   <- nrow(context_whole)
n_ctx_pat_whole <- dplyr::n_distinct(context_whole$ID)
n_ctx_post    <- sum(context_whole$post_anchor == 1L)
n_ctx_pat_post  <- dplyr::n_distinct(context_whole$ID[context_whole$post_anchor == 1L])

message(glue(
  "  Context (NEEDS_TEMPORAL_MATCH patients in Phase 165 set): ",
  "{n_ctx_whole} encounters / {n_ctx_pat_whole} patients (whole); ",
  "{n_ctx_post} post-anchor / {n_ctx_pat_post} patients"
))

# ==============================================================================
# SECTION 6: TEMPORAL LOOKUP ON CANDIDATES ----
# ==============================================================================
# Use get_zip9_at_date() to try to resolve a ZIP for each candidate encounter.
# Lookup is on DISTINCT (ID, Date) with Date-coerced keys.
# Row count is asserted unchanged after the join (plan invariant).

message("--- Temporal lookup via get_zip9_at_date() ---")

keys <- cand |>
  dplyr::mutate(id = as.character(ID), d = as.Date(ADMIT_DATE)) |>
  dplyr::distinct(id, d)
message(glue("  Distinct (ID, date) lookup keys: {nrow(keys)}"))

# get_zip9_at_date() returns tibble(ID, query_date, ZIP9, ZIP5, match_type)
# Result is distinct on (ID, query_date). Join on (id, query_date).
message("  cand cols before lookup: ", paste(names(cand), collapse = ", "))
lk <- get_zip9_at_date(ids = keys$id, dates = keys$d)
message("  get_zip9_at_date returned ", nrow(lk), " rows; cols: ", paste(names(lk), collapse = ", "))
names(lk)[names(lk) == "ZIP5"] <- "ZIP5_matched"   # rename to avoid collision with cand$zip5_patient

# Prepare join keys on cand side using base R to avoid any dplyr masking issue
n0 <- nrow(cand)
cand$.id <- as.character(cand$ID)
cand$.d  <- as.Date(cand$ADMIT_DATE)
cand <- cand |>
  dplyr::left_join(
    lk |> dplyr::select(ID, query_date, ZIP9_matched = ZIP9, ZIP5_matched, match_type),
    by = c(".id" = "ID", ".d" = "query_date")
  )
stopifnot(nrow(cand) == n0)   # plan invariant: join must not fan out

# Coverable = interval match AND non-missing matched ZIP5
cand$coverable <- cand$match_type %in% "interval" & !is.na(cand$ZIP5_matched)

n_cov_whole <- sum(cand$coverable)
n_cov_post  <- sum(cand$coverable & cand$post_anchor == 1L)
n_not_in_db_whole <- sum(!cand$coverable & !is.na(cand$match_type) &
                         cand$match_type == "interval" & is.na(cand$ZIP5_matched))

message(glue(
  "  Coverable (interval match + non-NA ZIP5): {n_cov_whole} whole / {n_cov_post} post-anchor"
))
message(glue(
  "  Interval-matched but no ZIP5 (zip_not_in_db path): {n_not_in_db_whole}"
))

# ==============================================================================
# SECTION 7: PROJECTED DISTANCE FOR COVERABLE ROWS ----
# ==============================================================================
# Reuse R/122's own distance method: zipcodeR::zip_distance() on distinct ZIP5 pairs.
# Only coverable rows get a projected distance.

message("--- Projecting distances for coverable encounters ---")

cov <- cand |>
  dplyr::filter(coverable)
# zip5_facility is already present in enc_distance output (R/122 computes it there)

# Compute on distinct (zip5_patient_proj, zip5_facility) pairs for performance.
proj_pairs <- cov |>
  dplyr::distinct(zip5_patient = ZIP5_matched, zip5_facility) |>
  dplyr::filter(!is.na(zip5_patient), !is.na(zip5_facility))

if (nrow(proj_pairs) > 0L) {
  zd <- zipcodeR::zip_distance(proj_pairs$zip5_patient, proj_pairs$zip5_facility, units = "miles")
  proj_pairs$proj_mi <- zd$distance

  cov <- cov |>
    dplyr::left_join(
      proj_pairs |> dplyr::rename(ZIP5_matched = zip5_patient),
      by = c("ZIP5_matched", "zip5_facility")
    )
} else {
  cov$proj_mi <- numeric(0)
}

cov <- cov |>
  dplyr::mutate(
    proj_distance_status = dplyr::case_when(
      is.na(zip5_facility)  ~ "facility_zip_missing",
      is.na(ZIP5_matched)   ~ "patient_zip_missing",
      is.na(proj_mi)        ~ "zip_not_in_db",
      TRUE                  ~ "computed"
    ),
    proj_far = dplyr::if_else(
      proj_distance_status == "computed",
      proj_mi > CUTOFF,
      NA
    )
  )

# Merge proj columns back onto cand
cand <- cand |>
  dplyr::left_join(
    cov |> dplyr::select(ENCOUNTERID, zip5_facility, proj_mi,
                         proj_distance_status, proj_far),
    by = "ENCOUNTERID"
  )

n_filled_whole <- sum(cand$coverable & !is.na(cand$proj_mi), na.rm = TRUE)
n_filled_post  <- sum(cand$coverable & !is.na(cand$proj_mi) & cand$post_anchor == 1L,
                      na.rm = TRUE)
n_proj_far_whole <- sum(cand$proj_far == TRUE, na.rm = TRUE)
n_proj_far_post  <- sum(cand$proj_far == TRUE & cand$post_anchor == 1L, na.rm = TRUE)
n_cov_zip_not_in_db_whole <- sum(cand$coverable & !is.na(cand$proj_distance_status) &
                                  cand$proj_distance_status == "zip_not_in_db", na.rm = TRUE)
n_cov_zip_not_in_db_post  <- sum(cand$coverable & !is.na(cand$proj_distance_status) &
                                  cand$proj_distance_status == "zip_not_in_db" &
                                  cand$post_anchor == 1L, na.rm = TRUE)

message(glue("  Filled (coverable with a projected distance): ",
             "{n_filled_whole} whole / {n_filled_post} post-anchor"))
message(glue("  Projected >100 mi (whole/post): {n_proj_far_whole} / {n_proj_far_post}"))

# ==============================================================================
# SECTION 8: COMPUTE SHARES AND DECISION RULE (D-03 locked) ----
# ==============================================================================

message("--- Computing shares and applying locked decision rule ---")

share_whole <- if (n_enc_whole > 0L) n_filled_whole / n_enc_whole else NA_real_
share_post  <- if (n_enc_post  > 0L) n_filled_post  / n_enc_post  else NA_real_

far_ratio_whole <- if (n_far_whole > 0L) n_proj_far_whole / n_far_whole else NA_real_
far_ratio_post  <- if (n_far_post  > 0L) n_proj_far_post  / n_far_post  else NA_real_

# Locked decision rule (CONTEXT D-03):
share_max   <- max(share_whole, share_post, na.rm = TRUE)
far_trigger <- isTRUE(far_ratio_whole > 0.05) || isTRUE(far_ratio_post > 0.05)
tier        <- if (share_max > 0.05 || far_trigger) {
  "New phase"
} else if (share_max >= 0.01) {
  "Inline fix"
} else {
  "Document only"
}

message(glue("  share_whole  = {round(share_whole * 100, 2)}%"))
message(glue("  share_post   = {round(share_post * 100, 2)}%"))
message(glue("  far_ratio_whole = {round(far_ratio_whole * 100, 2)}%"))
message(glue("  far_ratio_post  = {round(far_ratio_post * 100, 2)}%"))
message(glue("  tier_if_d04_explained = {tier}"))

# ==============================================================================
# SECTION 9: D-04 CROSS-TAB ----
# ==============================================================================
# R/122 patient_zip_missing patients x R/121 triage group.
# Structural cross-tab, not a numeric tolerance.

message("--- D-04 cross-tab: R/122 patient_zip_missing patients x R/121 triage ---")

# All unique patients in R/122 with patient_zip_missing status
pzm_pats <- enc_distance |>
  dplyr::filter(distance_status == "patient_zip_missing") |>
  dplyr::distinct(ID) |>
  dplyr::mutate(ID = as.character(ID))

# Attach R/121 triage
pzm_triage <- pzm_pats |>
  dplyr::left_join(
    pat121 |>
      dplyr::mutate(ID = as.character(PATID)) |>
      dplyr::select(ID, triage),
    by = "ID"
  ) |>
  dplyr::mutate(triage_r121 = dplyr::coalesce(triage, "not in R/121"))

d04_crosstab <- pzm_triage |>
  dplyr::count(triage_r121, name = "n_patients") |>
  dplyr::arrange(dplyr::desc(n_patients)) |>
  dplyr::mutate(
    definitional_reason = ""   # blank -- for memo author to fill
  )

# Count of NEEDS_TEMPORAL_MATCH patients in R/121 with NO patient_zip_missing encounter
ntm_no_pzm <- length(setdiff(ntm_ids_chr, pzm_pats$ID))
message(glue("  D-04 cross-tab (R/122 patient_zip_missing patients x R/121 triage):"))
print(as.data.frame(d04_crosstab))
message(glue("  NEEDS_TEMPORAL_MATCH patients with no patient_zip_missing encounter: {ntm_no_pzm}"))

# ==============================================================================
# SECTION 10: ASSEMBLE WORKBOOK ----
# ==============================================================================

message("--- Assembling workbook ---")

# Helper: format pct only when both numerator and denominator are non-suppressed (>=11)
safe_pct <- function(num, den) {
  if (!is.na(num) && !is.na(den) && num >= 11L && den >= 11L) {
    paste0(round(100 * num / den, 2), "%")
  } else {
    "—"
  }
}

# --- KEY sheet ----------------------------------------------------------------
key_tbl <- tibble::tribble(
  ~item,                          ~value,
  "Script",                       "R/177_temporal_match_sizing.R (Phase 177)",
  "Run date",                     RUN_DATE,
  "R/121 input",                  basename(r121_path),
  "R/121 pinned",                 as.character(r121_pinned_flag),
  "R/122 input",                  basename(r122_path),
  "R/122 pinned",                 as.character(r122_pinned_flag),
  "Far-from-care cutoff (mi)",    as.character(CUTOFF),
  "Threshold: new phase",         "share > 5% OR far_ratio > 5%",
  "Threshold: inline fix",        "share >= 1%",
  "Threshold: document only",     "share < 1%",
  "share_whole",                  if (!is.na(share_whole)) paste0(round(share_whole * 100, 3), "%") else "NA",
  "share_post",                   if (!is.na(share_post))  paste0(round(share_post * 100, 3), "%")  else "NA",
  "far_ratio_whole",              if (!is.na(far_ratio_whole)) paste0(round(far_ratio_whole * 100, 3), "%") else "NA",
  "far_ratio_post",               if (!is.na(far_ratio_post))  paste0(round(far_ratio_post * 100, 3), "%")  else "NA",
  "tier_if_d04_explained",        tier,
  "D-04 explained",               "NOT YET -- set in Plan 02 memo",
  "Confidentiality",              "Contains patient identifiers; project output directory only"
)

# --- A_counts sheet -----------------------------------------------------------
# Rows in order: current set (denominator), context, candidates, coverable,
# coverable but zip_not_in_db, filled, projected far.
# Each row: whole (encounter, patient), post (encounter, patient).
# Counts suppressed through suppress_small_vec; pct shown only when both sides >= 11.

make_count_row <- function(label,
                           n_enc_w, n_pat_w, n_enc_p, n_pat_p,
                           den_enc_w = NA_integer_, den_enc_p = NA_integer_) {
  tibble::tibble(
    Row                     = label,
    Enc_whole               = suppress_small_vec(n_enc_w),
    Pat_whole               = suppress_small_vec(n_pat_w),
    Enc_post                = suppress_small_vec(n_enc_p),
    Pat_post                = suppress_small_vec(n_pat_p),
    Pct_enc_whole           = safe_pct(suppress_small_vec(n_enc_w), suppress_small_vec(den_enc_w)),
    Pct_enc_post            = safe_pct(suppress_small_vec(n_enc_p), suppress_small_vec(den_enc_p))
  )
}

a_counts <- dplyr::bind_rows(
  make_count_row("Current Phase 165 set (denominator)",
                 n_enc_whole, n_pat_whole, n_enc_post, n_pat_post),
  make_count_row("Context: NEEDS_TEMPORAL_MATCH patients in Phase 165 set",
                 n_ctx_whole, n_ctx_pat_whole, n_ctx_post, n_ctx_pat_post,
                 n_enc_whole, n_enc_post),
  make_count_row("Current far (>100 mi) in Phase 165 set",
                 n_far_whole, NA_integer_, n_far_post, NA_integer_),
  make_count_row("Candidates (patient_zip_missing, anchor-scoped)",
                 n_cand_whole, n_cand_pat_whole, n_cand_post, n_cand_pat_post,
                 n_enc_whole, n_enc_post),
  make_count_row("Coverable (interval match + non-NA ZIP5)",
                 n_cov_whole, NA_integer_, n_cov_post, NA_integer_,
                 n_cand_whole, n_cand_post),
  make_count_row("Coverable but zip_not_in_db",
                 n_cov_zip_not_in_db_whole, NA_integer_, n_cov_zip_not_in_db_post, NA_integer_),
  make_count_row("Filled (coverable with projected distance_mi)",
                 n_filled_whole, NA_integer_, n_filled_post, NA_integer_,
                 n_enc_whole, n_enc_post),
  make_count_row("Projected >100 mi among filled",
                 n_proj_far_whole, NA_integer_, n_proj_far_post, NA_integer_,
                 n_far_whole, n_far_post),
  make_count_row("NEEDS_TEMPORAL_MATCH patients with no patient_zip_missing encounter",
                 ntm_no_pzm, ntm_no_pzm, NA_integer_, NA_integer_)
)

# --- B_by_triage sheet --------------------------------------------------------
b_by_triage <- cand |>
  dplyr::group_by(triage) |>
  dplyr::summarise(
    n_encounters_whole  = dplyr::n(),
    n_patients_whole    = dplyr::n_distinct(ID),
    n_coverable_whole   = sum(coverable, na.rm = TRUE),
    n_filled_whole      = sum(coverable & !is.na(proj_mi), na.rm = TRUE),
    n_proj_far_whole    = sum(proj_far == TRUE, na.rm = TRUE),
    n_encounters_post   = sum(post_anchor == 1L),
    n_patients_post     = dplyr::n_distinct(ID[post_anchor == 1L]),
    n_coverable_post    = sum(coverable & post_anchor == 1L, na.rm = TRUE),
    n_filled_post       = sum(coverable & !is.na(proj_mi) & post_anchor == 1L, na.rm = TRUE),
    n_proj_far_post     = sum(proj_far == TRUE & post_anchor == 1L, na.rm = TRUE),
    .groups = "drop"
  ) |>
  dplyr::mutate(
    dplyr::across(dplyr::starts_with("n_"), suppress_small_vec)
  ) |>
  dplyr::arrange(dplyr::desc(n_encounters_whole))

# --- C_d04_crosstab sheet -----------------------------------------------------
c_d04 <- d04_crosstab |>
  dplyr::mutate(
    n_patients = suppress_small_vec(n_patients)
  )

# --- Build workbook -----------------------------------------------------------
hdr_style <- openxlsx::createStyle(
  fgFill         = "#0021A5",
  fontColour     = "#FFFFFF",
  textDecoration = "bold",
  halign         = "left"
)

wb <- openxlsx::createWorkbook()

for (nm in c("KEY", "A_counts", "B_by_triage", "C_d04_crosstab")) {
  df <- switch(nm,
    "KEY"          = key_tbl,
    "A_counts"     = a_counts,
    "B_by_triage"  = b_by_triage,
    "C_d04_crosstab" = c_d04
  )
  openxlsx::addWorksheet(wb, nm)
  openxlsx::writeData(wb, nm, df, headerStyle = hdr_style)
  openxlsx::freezePane(wb, nm, firstActiveRow = 2L, firstActiveCol = 1L)
  openxlsx::setColWidths(wb, nm, cols = seq_along(df), widths = "auto")
}

openxlsx::saveWorkbook(wb, OUTPUT_XLSX, overwrite = TRUE)
message(glue("  Wrote workbook: {OUTPUT_XLSX}"))

# ==============================================================================
# SECTION 11: SAVE INTERNAL ENCOUNTER-LEVEL RDS ----
# ==============================================================================
# Encounter-level candidates with triage, match_type, coverable, ZIP5_matched,
# proj_mi, proj_far, window flags.

saveRDS(cand, OUTPUT_RDS)
message(glue("  Wrote internal encounter RDS: {OUTPUT_RDS}"))

message("================================================================================")
message(glue("R/177 done. tier_if_d04_explained = {tier}"))
message("================================================================================")
