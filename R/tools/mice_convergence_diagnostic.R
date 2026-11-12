# R/tools/mice_convergence_diagnostic.R
# Reads existing mice_input_patient_*.rds and mice_mids_*.rds.
# Reports: n and % missing dist_to_source_facility_mi per main_source level;
#          Gelman-Rubin-style R-hat by iteration (convergence).
# Writes: .planning/phases/197-phase-b-pipeline-hardening/197-MICE-CONVERGENCE.md
#
# Run on HiPerGator:
#   module load R/4.5; R --no-save
#   source("R/tools/mice_convergence_diagnostic.R", local = new.env(parent = globalenv()))
#
# Env-var overrides:
#   MICE_DIAG_INPUT  — full path to mice_input_patient_*.rds
#   MICE_DIAG_MIDS   — full path to mice_mids_*.rds
# Falls back to R183_MICE_INPUT_RDS / R183_MICE_MIDS_RDS, then to file discovery.
#
# Phase 197-08 — updated: UCI handling is a data/modelling decision, not a collapse fix.

suppressPackageStartupMessages({
  library(mice)
  library(dplyr)
  library(here)
})

MICE_INPUT_PATH <- Sys.getenv(
  "MICE_DIAG_INPUT",
  Sys.getenv("R183_MICE_INPUT_RDS",
    list.files(file.path(here(), "output", "internal"),
               pattern = "^mice_input_patient_.*\\.rds$", full.names = TRUE) |>
      (\(f) if (length(f) == 0) stop("No mice_input_patient_*.rds in output/internal/") else f[length(f)])()
  )
)
MICE_MIDS_PATH <- Sys.getenv(
  "MICE_DIAG_MIDS",
  Sys.getenv("R183_MICE_MIDS_RDS",
    list.files(file.path(here(), "output", "internal"),
               pattern = "^mice_mids_.*\\.rds$", full.names = TRUE) |>
      (\(f) if (length(f) == 0) stop("No mice_mids_*.rds in output/internal/") else f[length(f)])()
  )
)

OUT_MD <- file.path(here(), ".planning", "phases",
                    "197-phase-b-pipeline-hardening", "197-MICE-CONVERGENCE.md")

message("[diag] mice_input: ", MICE_INPUT_PATH)
message("[diag] mice_mids:  ", MICE_MIDS_PATH)

# --- 1. main_source level counts and distance missingness -------------------
mice_input <- readRDS(MICE_INPUT_PATH)
message("[diag] main_source counts:")
print(table(mice_input$main_source, useNA = "always"))

src_tbl <- mice_input |>
  group_by(main_source) |>
  summarise(
    n             = n(),
    n_miss_dist   = sum(is.na(dist_to_source_facility_mi)),
    pct_miss_dist = round(100 * n_miss_dist / n, 1),
    .groups = "drop"
  ) |>
  arrange(desc(n)) |>
  mutate(
    flag = case_when(
      pct_miss_dist == 100 ~
        "100% missing -> indicator constant 0 among observed rows -> MICE drops it (loggedEvents; UCI data decision, not collapse)",
      n < 30 & pct_miss_dist == 0 ~
        paste0("n=", n, " < 30 but 0% missing distance -> no collapse needed"),
      n < 30 ~
        paste0("n=", n, " < 30"),
      TRUE ~ ""
    )
  )

message("[diag] main_source missingness for dist_to_source_facility_mi:")
print(as.data.frame(src_tbl), row.names = FALSE)

# --- 2. R-hat convergence by iteration -------------------------------------
mids_raw <- readRDS(MICE_MIDS_PATH)
# mids RDS may be a single mids object OR a named list of mids objects (d01/d02/...).
if (inherits(mids_raw, "mids")) {
  mids_list <- list(all = mids_raw)
} else if (is.list(mids_raw) && all(vapply(mids_raw, inherits, logical(1), "mids"))) {
  mids_list <- mids_raw
} else {
  stop("[diag] MICE_MIDS_RDS does not contain a mids object or a named list of mids objects.")
}
message("[diag] mids objects found: ", paste(names(mids_list), collapse = ", "))

rhat_all <- list()
current_maxit <- NA_integer_

for (mids_nm in names(mids_list)) {
  mids <- mids_list[[mids_nm]]
  # chainMean structure differs by mice version:
  #   older mice: list[variable][m x maxit matrix]
  #   mice >= 3:  3D array [n_vars x m x maxit] with dimnames
  cm <- mids$chainMean
  if (is.null(cm)) {
    message("[diag] ", mids_nm, ": chainMean is NULL — skipping.")
    next
  }
  # mice >= 3: chainMean is [n_vars x maxit x m] (NOT [n_vars x m x maxit])
  # get_chain_mat extracts a [m x maxit] matrix for downstream R-hat computation.
  if (is.array(cm) && length(dim(cm)) == 3) {
    vars_imp  <- dimnames(cm)[[1]]
    get_chain_mat <- function(v) t(cm[v, , ])   # cm[v,,] is [maxit x m]; t() -> [m x maxit]
  } else {
    vars_imp  <- names(cm)
    get_chain_mat <- function(v) cm[[v]]         # older mice: already [m x maxit]
  }
  if (is.na(current_maxit) && length(vars_imp) > 0) {
    m0 <- get_chain_mat(vars_imp[1])
    if (!is.null(m0)) current_maxit <- ncol(m0)
  }

  # method lookup for categorical detection
  mids_method <- mids$method
  is_categorical <- function(v) {
    if (is.null(mids_method) || !v %in% names(mids_method)) return(FALSE)
    mids_method[[v]] %in% c("polyreg", "polr", "logreg")
    # logreg is binary — still meaningful for R-hat; only polyreg/polr are excluded
  }
  CATEGORICAL_METHODS <- c("polyreg", "polr")

  rhat_rows <- lapply(vars_imp, function(v) {
    mat <- get_chain_mat(v)   # [m x maxit]
    meth <- if (!is.null(mids_method) && v %in% names(mids_method)) mids_method[[v]] else ""
    is_cat <- meth %in% CATEGORICAL_METHODS

    if (is.null(mat) || !is.matrix(mat) || ncol(mat) < 2) {
      message(sprintf("[diag]   %s/%s: skipped (not a matrix or < 2 iterations)", mids_nm, v))
      return(NULL)
    }
    if (all(is.na(mat))) {
      message(sprintf("[diag]   %s/%s: skipped (all-NA chainMean; not imputed)", mids_nm, v))
      return(NULL)
    }
    if (is_cat) {
      message(sprintf("[diag]   %s/%s: extracted (method=%s; informational only, excluded from maxit rec)", mids_nm, v, meth))
    } else {
      message(sprintf("[diag]   %s/%s: extracted (method=%s)", mids_nm, v, meth))
    }

    rhats <- sapply(seq_len(ncol(mat)), function(iter) {
      chains_iter <- mat[, 1:iter, drop = FALSE]  # [m x iter]
      if (iter < 2 || nrow(chains_iter) < 2) return(NA_real_)
      chain_means <- apply(chains_iter, 1, mean)
      chain_vars  <- apply(chains_iter, 1, var)
      W_bar <- mean(chain_vars, na.rm = TRUE)
      B_comp <- var(chain_means, na.rm = TRUE) * nrow(mat)
      var_hat <- ((iter - 1) / iter) * W_bar + (1 / iter) * B_comp
      if (is.na(W_bar) || W_bar <= 0) return(NA_real_)
      sqrt(var_hat / W_bar)
    })
    data.frame(mids_model = mids_nm, variable = v, method = meth,
               is_categorical = is_cat,
               iteration = seq_along(rhats), rhat = rhats,
               stringsAsFactors = FALSE)
  })
  rhat_all[[mids_nm]] <- bind_rows(Filter(Negate(is.null), rhat_rows))
}

rhat_df <- bind_rows(rhat_all)

if (nrow(rhat_df) == 0) {
  message("[diag] WARNING: no R-hat data extracted from any mids$chainMean. ",
          "chainMean may be empty or all variables are non-imputed. Skipping convergence table.")
  converge_iter <- data.frame(mids_model = character(), variable = character(),
                              method = character(), is_categorical = logical(),
                              max_rhat = numeric(), converge_at = integer(),
                              stringsAsFactors = FALSE)
} else {
  converge_iter <- rhat_df |>
    group_by(mids_model, variable, method, is_categorical) |>
    summarise(
      max_rhat   = max(rhat, na.rm = TRUE),
      converge_at = {
        below <- which(rhat < 1.1)
        if (length(below) == 0) NA_integer_
        else {
          last_above <- max(which(rhat >= 1.1), 0L)
          if (last_above == 0L) min(below)
          else { after <- below[below > last_above]; if (length(after) == 0) NA_integer_ else min(after) }
        }
      },
      .groups = "drop"
    )
  message("[diag] Convergence table (all variables):")
  print(as.data.frame(converge_iter[, c("mids_model", "variable", "method", "max_rhat", "converge_at")]),
        row.names = FALSE)
}

if (is.na(current_maxit) && nrow(rhat_df) > 0) current_maxit <- max(rhat_df$iteration)

# maxit recommendation: based on continuous/binary variables only (exclude polyreg/polr)
converge_cont <- converge_iter[!converge_iter$is_categorical, , drop = FALSE]
recommended_maxit_n <- NA_integer_
recommended_maxit <- if (nrow(converge_cont) == 0) {
  paste0("INCREASE from ", current_maxit, " — no continuous/binary variables found")
} else if (all(is.na(converge_cont$converge_at))) {
  paste0("INCREASE from ", current_maxit, " — not all continuous/binary variables converged within ", current_maxit, " iterations")
} else {
  worst      <- max(converge_cont$converge_at, na.rm = TRUE)
  rec_raw    <- worst + 5L
  rec        <- as.integer(ceiling(rec_raw / 5) * 5)
  recommended_maxit_n <- rec
  direction  <- if (rec < current_maxit) "REDUCE" else if (rec == current_maxit) "KEEP" else "INCREASE"
  sprintf("%d (current %d) -> %s  [worst conv iter: %d; +5 rounded to mult-of-5]",
          rec, current_maxit, direction, worst)
}
message("[diag] maxit recommendation: ", recommended_maxit)

# --- 3. Write markdown report -----------------------------------------------
src_md <- paste0(
  "| main_source | n | n_miss_dist | pct_miss_dist | note |\n",
  "|---|---|---|---|---|\n",
  paste(sprintf("| %s | %d | %d | %.1f%% | %s |",
                ifelse(is.na(src_tbl$main_source), "NA", src_tbl$main_source),
                src_tbl$n,
                src_tbl$n_miss_dist,
                src_tbl$pct_miss_dist,
                src_tbl$flag),
        collapse = "\n")
)

if (nrow(converge_iter) > 0) {
  conv_md <- paste0(
    "| Model | Variable | Method | Use for maxit? | First iter R-hat < 1.1 | Max R-hat |\n",
    "|---|---|---|---|---|---|\n",
    paste(sprintf("| %s | %s | %s | %s | %s | %.3f |",
                  converge_iter$mids_model,
                  converge_iter$variable,
                  converge_iter$method,
                  ifelse(converge_iter$is_categorical, "No (categorical)", "Yes"),
                  ifelse(is.na(converge_iter$converge_at), "not converged",
                         as.character(converge_iter$converge_at)),
                  converge_iter$max_rhat),
          collapse = "\n")
  )
} else {
  conv_md <- "_No convergence data (chainMean empty, all-NA, or m=1)._"
}

report <- paste0(
  "# 197-MICE-CONVERGENCE\n\n",
  "Generated by R/tools/mice_convergence_diagnostic.R\n\n",
  "Input: ", basename(MICE_INPUT_PATH), "\n",
  "Mids:  ", basename(MICE_MIDS_PATH), "\n\n",
  "## main_source: n and dist_to_source_facility_mi Missingness\n\n",
  src_md, "\n\n",
  "### Interpretation\n\n",
  "- **UCI (100% missing):** UCI encounters have no FACILITY_LOCATION data, so ",
  "zip5_facility is NA for all UCI encounters. No facility centroid can be computed, ",
  "so dist_to_source_facility_mi = NA for all 211 UCI patients. Among rows WITH observed ",
  "distance, main_sourceUCI is always 0 — the coefficient is constant (not a rare-level problem). ",
  "MICE drops main_sourceUCI from the distance model (loggedEvents). ",
  "This is a **data/modelling decision**, not a collapse fix — see 197-UCI-DISTANCE.md.\n",
  "- **TMC (n=29) and CHP (n=23) are below 30** but have 0% missing distance — no collapse needed ",
  "for the loggedEvents issue. COLLAPSE_RARE_SOURCE=FALSE is correct.\n",
  "- **ORL (25.4% missing):** Facility centroid is known for ORL; the missing distances ",
  "come from patient address (pat_zip5 missing for ~127 ORL patients).\n\n",
  "## Convergence (Gelman-Rubin-style R-hat by Iteration)\n\n",
  "Current maxit: ", current_maxit, "\n\n",
  conv_md, "\n\n",
  "**maxit recommendation:** `", recommended_maxit, "`\n\n",
  "_Categorical variables (polyreg/polr: main\\_source, payer) are shown informational only ",
  "and excluded from the recommendation — R-hat on numeric level codes is not a meaningful ",
  "convergence measure for multinomial variables._\n\n",
  "_Note: maxit changes alter MICE results and require a full R/183 rerun. ",
  "Change only after Gerard approves._\n"
)

writeLines(report, OUT_MD)
message("[diag] Report written: ", OUT_MD)
