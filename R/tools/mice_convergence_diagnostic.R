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
mids <- readRDS(MICE_MIDS_PATH)
# chainMean structure differs by mice version:
#   older mice: list[variable][m x maxit matrix]
#   mice >= 3:  3D array [n_vars x m x maxit] with dimnames
cm <- mids$chainMean
if (is.array(cm) && length(dim(cm)) == 3) {
  vars_imp  <- dimnames(cm)[[1]]
  get_chain_mat <- function(v) {
    # extract [m x maxit] matrix for variable v
    matrix(cm[v, , ], nrow = dim(cm)[2], ncol = dim(cm)[3])
  }
} else {
  vars_imp  <- names(cm)
  get_chain_mat <- function(v) cm[[v]]
}

rhat_rows <- lapply(vars_imp, function(v) {
  mat <- get_chain_mat(v)   # [m x maxit]
  if (is.null(mat) || ncol(mat) < 2) return(NULL)
  rhats <- sapply(seq_len(ncol(mat)), function(iter) {
    chains_iter <- mat[, 1:iter, drop = FALSE]
    if (iter < 2 || nrow(chains_iter) < 2) return(NA_real_)
    chain_means <- apply(chains_iter, 1, mean)   # one per chain
    chain_vars  <- apply(chains_iter, 1, var)    # within-chain variance
    n_iter <- iter
    n_chains <- nrow(mat)
    W_bar   <- mean(chain_vars)
    B_comp  <- var(chain_means) * n_chains       # ~ B/n (Gelman-Rubin approximation)
    var_hat <- ((n_iter - 1) / n_iter) * W_bar + (1 / n_iter) * B_comp
    if (W_bar <= 0) return(NA_real_)
    sqrt(var_hat / W_bar)
  })
  data.frame(variable = v, iteration = seq_along(rhats), rhat = rhats,
             stringsAsFactors = FALSE)
})
rhat_df <- bind_rows(Filter(Negate(is.null), rhat_rows))

if (nrow(rhat_df) == 0) {
  message("[diag] WARNING: no R-hat data extracted from mids$chainMean. ",
          "chainMean may be empty (m=1 or maxit<2). Skipping convergence table.")
  converge_iter <- data.frame(variable = character(), max_rhat = numeric(),
                              converge_at = integer(), stringsAsFactors = FALSE)
} else {
  # First iteration where R-hat < 1.1 and stays below for all remaining
  converge_iter <- rhat_df |>
    group_by(variable) |>
    summarise(
      max_rhat   = max(rhat, na.rm = TRUE),
      converge_at = {
        below <- which(rhat < 1.1)
        if (length(below) == 0) NA_integer_
        else {
          last_above <- max(which(rhat >= 1.1), 0L)
          if (last_above == 0L) min(below)
          else {
            after <- below[below > last_above]
            if (length(after) == 0) NA_integer_ else min(after)
          }
        }
      },
      .groups = "drop"
    )
  message("[diag] Convergence table:")
  print(as.data.frame(converge_iter), row.names = FALSE)
}

# maxit recommendation
current_maxit <- ncol(get_chain_mat(vars_imp[1]))
recommended_maxit <- if (nrow(converge_iter) == 0 || all(is.na(converge_iter$converge_at))) {
  paste0("INCREASE from ", current_maxit, " — not all variables converged")
} else {
  worst <- max(converge_iter$converge_at, na.rm = TRUE)
  rec <- ceiling(worst * 1.5)
  if (rec <= current_maxit) {
    paste0("KEEP at ", current_maxit, " (worst convergence at iter ", worst,
           "; 1.5x margin = ", rec, " <= current)")
  } else {
    paste0("INCREASE to ", rec, " (worst convergence at iter ", worst,
           "; 1.5x margin; pending Gerard approval)")
  }
}

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
    "| Variable | First iter R-hat < 1.1 (stable) | Max R-hat |\n|---|---|---|\n",
    paste(sprintf("| %s | %s | %.3f |",
                  converge_iter$variable,
                  ifelse(is.na(converge_iter$converge_at), "not converged",
                         as.character(converge_iter$converge_at)),
                  converge_iter$max_rhat),
          collapse = "\n")
  )
} else {
  conv_md <- "_No convergence data (chainMean empty or m=1)._"
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
  "**maxit recommendation:** ", recommended_maxit, "\n\n",
  "_Note: maxit changes alter MICE results and require a full R/183 rerun. ",
  "Change only after Gerard approves._\n"
)

writeLines(report, OUT_MD)
message("[diag] Report written: ", OUT_MD)
