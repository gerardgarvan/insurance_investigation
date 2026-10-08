# ==============================================================================
# 163_distance_cbc_methods_prototype.R -- Distance >100 mi and CBC: Methods Prototype
# ==============================================================================
#
# Purpose:
#   Prototype script for Phase 165 Plan 01. Runs all four candidate statistical
#   tests (naive Pearson, Rao-Scott cluster-adjusted, GEE logistic, patient-level)
#   for BOTH windows (whole record, post-anchor). Prints design effects (DEFF) and
#   a summary results table. Writes enc_far_from_care.rds (ACC-01 deliverable).
#   Results feed directly into 165-METHODS.md.
#
# Inputs:
#   R/122 output: enc_distance RDS (readRDS from CONFIG$cache$outputs_dir)
#   DuckDB: ENCOUNTER (ENCOUNTERID, DISCHARGE_DATE, SOURCE), LAB_RESULT_CM (CBC re-derive)
#   get_hl_any_dx_ids() from utils_treatment.R (anchor dates)
#
# Outputs:
#   CONFIG$cache$outputs_dir/enc_far_from_care.rds   (ACC-01; one row per ENCOUNTERID)
#   Console log: cluster distribution, 2x2 tables, DEFF table, 8-row results summary
#
# Depends:
#   R/00_config.R (auto-sources utils_distance_cbc.R, utils_duckdb.R, utils_treatment.R)
#   survey, geepack, dplyr, glue (must be in renv.lock before running on HiPerGator)
#
# Requirements: ACC-01, ACC-02, ACC-04 (Phase 165)
#
# Usage:
#   sbatch slurm/163_distance_cbc_methods_prototype.sbatch    (preferred)
#   Rscript R/163_distance_cbc_methods_prototype.R            (compute node only)
#   Do NOT run interactively on a login/OnDemand session: DuckDB + LAB_RESULT_CM
#   query requires a batch allocation.
#
# ==============================================================================

# ==============================================================================
# SECTION 0: SETUP ----
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(glue)
  library(survey)
  library(geepack)
})

source(here::here("R/00_config.R"))
# 00_config.R auto-sources R/utils/utils_distance_cbc.R, utils_duckdb.R,
# utils_treatment.R (and others). All build_*() and get_*() helpers are available.

RUN_START <- proc.time()
RUN_DATE  <- format(Sys.Date(), "%Y%m%d")

# Single source of truth for the cutoff -- never use 100 literally below this line.
CUTOFF <- CONFIG$far_from_care_cutoff_mi
stopifnot(
  "far_from_care_cutoff_mi must be set (not NA)" = !is.na(CUTOFF),
  "far_from_care_cutoff_mi must be positive"     = CUTOFF > 0
)

# GEE working correlation from config (may be overridden to "independence" in Section 3)
CORSTR <- CONFIG$distance_gee_corstr

message(glue("=== Phase 165 prototype (run {RUN_DATE}) ==="))
message(glue("  Cutoff: {CUTOFF} mi | GEE corstr: {CORSTR}"))

# ==============================================================================
# SECTION 1: BUILD INPUTS ----
# ==============================================================================

message("\n--- Section 1: Building inputs ---")

# 1a. Open DuckDB connection (read-only; auto-closed in Section 1e)
if (!exists("pcornet_con", envir = .GlobalEnv)) open_pcornet_con()
con <- get("pcornet_con", envir = .GlobalEnv)

# 1b. Load enc_distance (R/122 output, read-only)
enc_dist_path <- list.files(
  CONFIG$output_dir,
  pattern = "^encounter_distance.*\\.rds$",
  full.names = TRUE
)
if (length(enc_dist_path) == 0)
  stop("enc_distance RDS not found in ", CONFIG$output_dir,
       " -- run R/122_encounter_distance.R first")
enc_dist_path <- enc_dist_path[which.max(file.mtime(enc_dist_path))]  # most recent
message(glue("  Loading enc_distance: {basename(enc_dist_path)}"))
enc_distance <- readRDS(enc_dist_path)
message(glue("  enc_distance rows: {format(nrow(enc_distance), big.mark=',')}"))

# 1c. Anchor dates (ID, hl_anchor_date, in_confirmed_cohort)
message("  Loading anchor dates via get_hl_any_dx_ids()...")
anchors_full <- get_hl_any_dx_ids()
anchors <- anchors_full |> dplyr::select(ID, hl_anchor_date)
cohort_ids <- unique(anchors_full$ID)
message(glue("  Anchor dates: {format(length(cohort_ids), big.mark=',')} IDs; ",
             "{sum(is.na(anchors_full$hl_anchor_date))} with NA anchor"))

# 1d. ENCOUNTER dates/SOURCE scoped to cohort IDs (SQL push-down before collect)
message("  Pulling ENCOUNTER (ENCOUNTERID, DISCHARGE_DATE, SOURCE) from DuckDB...")
enc_tbl <- safe_table("ENCOUNTER")
if (is.null(enc_tbl))
  stop("ENCOUNTER table not available in DuckDB -- run R/03_duckdb_ingest.R first")

id_filter <- unique(enc_distance$ID)  # only IDs we have distance for
enc_dates <- enc_tbl |>
  dplyr::filter(ID %in% id_filter) |>
  dplyr::select(ENCOUNTERID, ADMIT_DATE, DISCHARGE_DATE, ENC_TYPE, SOURCE) |>
  dplyr::collect() |>
  dplyr::mutate(
    ADMIT_DATE    = as.Date(ADMIT_DATE),
    DISCHARGE_DATE = as.Date(DISCHARGE_DATE)
  )
message(glue("  enc_dates rows: {format(nrow(enc_dates), big.mark=',')}"))

# 1e. CBC events -- whole record, re-derived from DuckDB LAB_RESULT_CM
# (R/147 saves only post-anchor; CONTEXT.md D-06a requires whole-record coverage)
message("  Building CBC events from LAB_RESULT_CM (whole record)...")
cbc_t0 <- proc.time()
cbc_events <- build_cbc_events(con, cohort_ids)
message(glue("  CBC events: {format(nrow(cbc_events), big.mark=',')} (ID x date pairs) ",
             "[{round((proc.time()-cbc_t0)[['elapsed']])}s]"))

# 1f. Close DuckDB connection before heavy R processing
close_pcornet_con()
message("  DuckDB connection closed.")

# ==============================================================================
# SECTION 2: ANALYSIS SETS ----
# ==============================================================================

message("\n--- Section 2: Building analysis sets ---")

enc_t0 <- proc.time()
enc <- build_enc_analysis(
  enc_distance = enc_distance,
  cbc_events   = cbc_events,
  anchors      = anchors,
  enc_dates    = enc_dates,
  cutoff       = CUTOFF
)
message(glue("  build_enc_analysis(): {round((proc.time()-enc_t0)[['elapsed']])}s"))

# Save ACC-01 deliverable: enc_far_from_care.rds
out_rds <- file.path(CONFIG$output_dir, "enc_far_from_care.rds")
saveRDS(enc, out_rds)
message(glue("  Saved enc_far_from_care.rds: {format(nrow(enc), big.mark=',')} encounters"))

# QC counts
n_enc_total    <- nrow(enc)
n_patients     <- n_distinct(enc$ID)
n_far          <- sum(enc$far_from_care_100mi == 1L, na.rm = TRUE)
n_cbc          <- sum(enc$cbc_in_encounter == 1L, na.rm = TRUE)
n_post_anchor  <- sum(enc$post_anchor == 1L, na.rm = TRUE)
n_tele_types   <- enc |> dplyr::count(ENC_TYPE, sort = TRUE)

message(glue("\n  Analysis set summary:"))
message(glue("    Encounters (computed distance, known anchor): {format(n_enc_total, big.mark=',')}"))
message(glue("    Distinct patients:                            {format(n_patients, big.mark=',')}"))
message(glue("    Far from care (>{CUTOFF} mi):                {format(n_far, big.mark=',')} encounters"))
message(glue("    CBC in encounter:                            {format(n_cbc, big.mark=',')} encounters"))
message(glue("    Post-anchor encounters:                      {format(n_post_anchor, big.mark=',')}"))
message("\n  Encounter type distribution (informational; all ENC_TYPE retained):")
print(n_tele_types)

# ==============================================================================
# SECTION 3: CLUSTER STRUCTURE ----
# ==============================================================================

message("\n--- Section 3: Cluster structure (encounters per patient) ---")

cluster_dist_fn <- function(d) {
  clust <- d |> dplyr::count(ID, name = "n_enc")
  qs <- quantile(clust$n_enc, probs = c(0, .25, .5, .75, .95, 1))
  message(glue("    min={qs[1]}  Q1={qs[2]}  median={qs[3]}  Q3={qs[4]}  p95={qs[5]}  max={qs[6]}  ",
               "mean={round(mean(clust$n_enc),1)}  patients={nrow(clust)}"))
  clust
}

message("  Whole-record window:")
clust_whole <- cluster_dist_fn(enc)
message("  Post-anchor window:")
clust_post  <- cluster_dist_fn(dplyr::filter(enc, post_anchor == 1L))

# Decide GEE working correlation: try exchangeable; fall back to independence if
# max cluster size or row count suggests infeasibility (empirical threshold).
MAX_CLUST <- max(clust_whole$n_enc)
if (MAX_CLUST > 500 || nrow(enc) > 200000) {
  CORSTR <- "independence"
  message(glue(
    "  GEE corstr overridden to 'independence': max cluster size = {MAX_CLUST}, ",
    "n_enc = {format(nrow(enc), big.mark=',')}. Exchangeable GEE may be ",
    "computationally infeasible at this scale within SLURM time limit."
  ))
} else {
  message(glue(
    "  GEE corstr retained as '{CORSTR}' (max cluster = {MAX_CLUST}, ",
    "n_enc = {format(nrow(enc), big.mark=',')})"
  ))
}

# ==============================================================================
# SECTION 4: RUN ALL CANDIDATES FOR EACH WINDOW ----
# ==============================================================================

message("\n--- Section 4: Candidate tests ---")

run_candidates <- function(window_label) {
  message(glue("\n  === Window: {window_label} ==="))

  # Subset encounters for this window
  d_enc <- if (window_label == "post") {
    enc |> dplyr::filter(post_anchor == 1L)
  } else {
    enc
  }
  n_rows <- nrow(d_enc)
  message(glue("    Encounter rows: {format(n_rows, big.mark=',')}"))

  # Patient-level set for C4
  d_pat <- build_pat_analysis(enc, cbc_events, anchors, window = window_label)
  n_pat <- nrow(d_pat)
  message(glue("    Patient rows: {format(n_pat, big.mark=',')}"))

  # ------ 2x2 contingency table (encounter level) ------
  ct_enc <- table(
    far  = d_enc$far_from_care_100mi,
    cbc  = d_enc$cbc_in_encounter
  )
  message("    2x2 encounter-level table (far=rows, cbc=cols):")
  print(ct_enc)
  exp_cells_enc <- chisq.test(ct_enc, correct = FALSE)$expected
  message("    Expected cells:")
  print(round(exp_cells_enc, 1))
  any_small_expected <- any(exp_cells_enc < 5)

  ct_pat <- table(
    far = d_pat$any_far,
    cbc = d_pat$any_cbc
  )
  message("    2x2 patient-level table (far=rows, cbc=cols):")
  print(ct_pat)
  exp_cells_pat <- chisq.test(ct_pat, correct = FALSE)$expected
  message("    Expected cells (patient-level):")
  print(round(exp_cells_pat, 1))

  results <- list()

  # ------ C1: Naive Pearson chi-square (encounter level) ------
  t0 <- proc.time()
  c1_chi <- chisq.test(ct_enc, correct = FALSE)
  c1_or  <- naive_or_se(ct_enc)
  c1_time <- round((proc.time() - t0)[["elapsed"]], 2)
  message(glue("    C1 naive Pearson: chi2={round(c1_chi$statistic,3)} p={format.pval(c1_chi$p.value,3)} ",
               "OR(exp)={round(exp(c1_or$log_or),3)} [{round((proc.time()-t0)[['elapsed']],1)}s]"))

  results[["C1"]] <- tibble::tibble(
    window    = window_label,
    candidate = "C1_naive_pearson",
    unit      = "encounter",
    n_rows    = n_rows,
    n_patients = n_distinct(d_enc$ID),
    OR        = exp(c1_or$log_or),
    CI_lo     = exp(c1_or$log_or - 1.96 * c1_or$se),
    CI_hi     = exp(c1_or$log_or + 1.96 * c1_or$se),
    SE_log_OR = c1_or$se,
    DEFF      = NA_real_,
    p         = c1_chi$p.value,
    notes     = if (c1_or$haldane) "Haldane correction applied" else ""
  )

  # ------ C2: Rao-Scott cluster-adjusted chi-square (encounter level) ------
  t0 <- proc.time()
  des <- survey::svydesign(ids = ~ID, data = d_enc)
  c2_chi <- survey::svychisq(
    ~far_from_care_100mi + cbc_in_encounter, des,
    statistic = "F"   # Rao-Scott F statistic
  )
  # Marginal OR via svyglm (quasi-binomial for binary outcome)
  c2_glm <- survey::svyglm(
    cbc_in_encounter ~ far_from_care_100mi,
    design = des,
    family = quasibinomial(link = "logit")
  )
  c2_coef <- coef(summary(c2_glm))["far_from_care_100mi", ]
  c2_se_rs <- c2_coef["Std. Error"]
  c2_se_naive <- c1_or$se
  c2_deff <- (c2_se_rs / c2_se_naive)^2
  c2_time <- round((proc.time() - t0)[["elapsed"]], 2)
  message(glue("    C2 Rao-Scott: F={round(c2_chi$statistic,3)} p={format.pval(c2_chi$p.value,3)} ",
               "OR={round(exp(c2_coef['Estimate']),3)} DEFF={round(c2_deff,3)} [{c2_time}s]"))

  results[["C2"]] <- tibble::tibble(
    window    = window_label,
    candidate = "C2_rao_scott",
    unit      = "encounter",
    n_rows    = n_rows,
    n_patients = n_distinct(d_enc$ID),
    OR        = exp(c2_coef["Estimate"]),
    CI_lo     = exp(c2_coef["Estimate"] - 1.96 * c2_se_rs),
    CI_hi     = exp(c2_coef["Estimate"] + 1.96 * c2_se_rs),
    SE_log_OR = c2_se_rs,
    DEFF      = c2_deff,
    p         = c2_chi$p.value,
    notes     = ""
  )

  # ------ C3: GEE logistic (encounter level, cluster = patient) ------
  t0 <- proc.time()
  d_gee <- d_enc |>
    dplyr::mutate(cid = as.integer(factor(ID))) |>
    dplyr::arrange(cid)

  c3_result <- tryCatch({
    corstr_used <- CORSTR
    gee_fit <- geepack::geeglm(
      cbc_in_encounter ~ far_from_care_100mi,
      id      = cid,
      data    = d_gee,
      family  = binomial(link = "logit"),
      corstr  = corstr_used
    )
    gee_sum  <- coef(summary(gee_fit))
    gee_coef <- gee_sum["far_from_care_100mi", ]
    gee_se   <- gee_coef["Std.err"]
    gee_deff <- (gee_se / c1_or$se)^2
    gee_alpha <- if (corstr_used == "exchangeable") {
      tryCatch(gee_fit$geese$alpha, error = function(e) NA_real_)
    } else NA_real_
    message(glue("    C3 GEE ({corstr_used}): OR={round(exp(gee_coef['Estimate']),3)} ",
                 "p={format.pval(gee_coef['Pr(>|W|)'],3)} ",
                 "DEFF={round(gee_deff,3)} alpha={round(gee_alpha,4)} ",
                 "[{round((proc.time()-t0)[['elapsed']],1)}s]"))
    tibble::tibble(
      window    = window_label,
      candidate = "C3_gee",
      unit      = "encounter",
      n_rows    = n_rows,
      n_patients = n_distinct(d_enc$ID),
      OR        = exp(gee_coef["Estimate"]),
      CI_lo     = exp(gee_coef["Estimate"] - 1.96 * gee_se),
      CI_hi     = exp(gee_coef["Estimate"] + 1.96 * gee_se),
      SE_log_OR = gee_se,
      DEFF      = gee_deff,
      p         = gee_coef["Pr(>|W|)"],
      notes     = glue("corstr={corstr_used}; alpha={round(gee_alpha, 4)}")
    )
  }, error = function(e) {
    if (corstr_used != "independence") {
      message(glue("    C3 GEE ({corstr_used}) failed: {e$message}. Retrying with independence."))
      corstr_used <<- "independence"
      gee_fit2 <- geepack::geeglm(
        cbc_in_encounter ~ far_from_care_100mi,
        id = cid, data = d_gee,
        family = binomial(link = "logit"),
        corstr = "independence"
      )
      gee_sum2  <- coef(summary(gee_fit2))
      gee_coef2 <- gee_sum2["far_from_care_100mi", ]
      gee_se2   <- gee_coef2["Std.err"]
      gee_deff2 <- (gee_se2 / c1_or$se)^2
      message(glue("    C3 GEE (independence fallback): OR={round(exp(gee_coef2['Estimate']),3)} ",
                   "DEFF={round(gee_deff2,3)} [{round((proc.time()-t0)[['elapsed']],1)}s]"))
      tibble::tibble(
        window    = window_label,
        candidate = "C3_gee",
        unit      = "encounter",
        n_rows    = n_rows,
        n_patients = n_distinct(d_enc$ID),
        OR        = exp(gee_coef2["Estimate"]),
        CI_lo     = exp(gee_coef2["Estimate"] - 1.96 * gee_se2),
        CI_hi     = exp(gee_coef2["Estimate"] + 1.96 * gee_se2),
        SE_log_OR = gee_se2,
        DEFF      = gee_deff2,
        p         = gee_coef2["Pr(>|W|)"],
        notes     = glue("corstr=independence (fallback from {CORSTR}): {e$message}")
      )
    } else {
      message(glue("    C3 GEE failed (independence): {e$message}"))
      tibble::tibble(
        window = window_label, candidate = "C3_gee", unit = "encounter",
        n_rows = n_rows, n_patients = n_distinct(d_enc$ID),
        OR = NA_real_, CI_lo = NA_real_, CI_hi = NA_real_,
        SE_log_OR = NA_real_, DEFF = NA_real_, p = NA_real_,
        notes = glue("GEE failed: {e$message}")
      )
    }
  })
  results[["C3"]] <- c3_result

  # ------ C4: Patient-level chi-square / Fisher ------
  t0 <- proc.time()
  c4_chi    <- chisq.test(ct_pat, correct = FALSE)
  c4_fisher <- fisher.test(ct_pat)
  c4_or     <- naive_or_se(ct_pat)
  c4_time   <- round((proc.time() - t0)[["elapsed"]], 2)
  message(glue("    C4 patient-level: chi2={round(c4_chi$statistic,3)} p={format.pval(c4_chi$p.value,3)} ",
               "Fisher OR={round(c4_fisher$estimate,3)} [{c4_time}s]"))

  results[["C4"]] <- tibble::tibble(
    window    = window_label,
    candidate = "C4_patient_fisher",
    unit      = "patient",
    n_rows    = n_pat,
    n_patients = n_pat,
    OR        = c4_fisher$estimate,
    CI_lo     = c4_fisher$conf.int[1],
    CI_hi     = c4_fisher$conf.int[2],
    SE_log_OR = c4_or$se,
    DEFF      = NA_real_,
    p         = c4_fisher$p.value,
    notes     = glue("chi2_p={format.pval(c4_chi$p.value,3)}; ",
                     "any_small_expected={any(exp_cells_pat < 5)}")
  )

  dplyr::bind_rows(results)
}

# Run for both windows; time each
message("\nRunning 'whole' window...")
t_whole <- system.time(res_whole <- run_candidates("whole"))

message("\nRunning 'post' window...")
t_post  <- system.time(res_post  <- run_candidates("post"))

# ==============================================================================
# SECTION 5: SUMMARY ----
# ==============================================================================

message("\n--- Section 5: Summary ---")

all_results <- dplyr::bind_rows(res_whole, res_post) |>
  dplyr::mutate(
    across(c(OR, CI_lo, CI_hi, SE_log_OR, DEFF), ~round(.x, 4)),
    p = signif(p, 3)
  )

message("\nFull results (8 rows = 4 candidates x 2 windows):")
print(all_results, n = Inf, width = 120)

message(glue("\n  Timing: whole-window {round(t_whole['elapsed'])}s | ",
             "post-window {round(t_post['elapsed'])}s | ",
             "total elapsed {round((proc.time()-RUN_START)['elapsed'])}s"))

message("\n=== Phase 165 prototype complete ===")
