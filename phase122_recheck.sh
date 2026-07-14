#!/usr/bin/env bash
# ==============================================================================
# phase122_recheck.sh -- Phase 122 close-out recheck (HiPerGator)
# ==============================================================================
# Runs R/88 (to confirm Section 15t is now 14/14 after the Check-8 fix) and
# summarizes the NDC->RxNorm crosswalk's CHEMO coverage (the proof that the
# DISPENSING / MED_ADMIN-ND path can now match chemo). Captures everything to a
# timestamped log AND prints the full log text to the terminal at the end, so it
# can be copied/pasted even from a SLURM .out or a non-interactive shell.
#
# Usage (from the repo root on HiPerGator):
#   git pull origin main
#   bash phase122_recheck.sh
#
# Output:
#   output/logs/phase122_recheck_<YYYYMMDD_HHMMSS>.log
# ==============================================================================

set -o pipefail

# --- Load the R module (HiPerGator) ---
if ! command -v module >/dev/null 2>&1; then
  [ -f /etc/profile.d/modules.sh ] && . /etc/profile.d/modules.sh
fi
module load R/4.4.2 2>/dev/null || echo "[warn] could not 'module load R/4.4.2' — assuming Rscript is on PATH"

if ! command -v Rscript >/dev/null 2>&1; then
  echo "[error] Rscript not found on PATH. Load an R module first." >&2
  exit 1
fi

mkdir -p output/logs
STAMP="$(date +%Y%m%d_%H%M%S)"
LOG="output/logs/phase122_recheck_${STAMP}.log"

{
  echo "=============================================================="
  echo " Phase 122 recheck"
  echo " Date      : $(date)"
  echo " Host      : $(hostname)"
  echo " Repo root : $(pwd)"
  echo " Crosswalk : $( [ -f data/reference/ndc_rxnorm_crosswalk.rds ] && echo PRESENT || echo 'MISSING (run R/108 first)')"
  echo "=============================================================="
  echo

  echo "#################### R/88 SMOKE TEST ####################"
  echo "(look for the [Phase 122] Section 15t block and the final FAILED: n/N line)"
  Rscript R/88_smoke_test_comprehensive.R
  echo "[exit code R/88: $?]"
  echo

  echo "############### NDC->RxNorm CROSSWALK CHEMO COVERAGE ###############"
  Rscript -e '
    # R/00_config.R calls glue()/data.table at load time and assumes the caller
    # already attached these (the pipeline scripts do). Load them before sourcing.
    suppressWarnings(suppressPackageStartupMessages({
      library(glue); library(data.table); library(dplyr)
      library(stringr); library(lubridate); library(tibble)
      library(tidyr); library(checkmate)
    }))
    suppressWarnings(suppressMessages(source("R/00_config.R")))
    p <- file.path("data", "reference", "ndc_rxnorm_crosswalk.rds")
    if (!file.exists(p)) { cat("crosswalk RDS MISSING at", p, "\n"); quit(status = 0) }
    cw    <- readRDS(p)                       # named char vector: NDC -> RxCUI
    chemo <- as.character(TREATMENT_CODES$chemo_rxnorm)
    is_chemo <- as.character(cw) %in% chemo
    cat(sprintf("Crosswalk entries (NDC -> RxCUI)   : %d\n", length(cw)))
    cat(sprintf("Distinct RxCUIs in crosswalk       : %d\n", length(unique(as.character(cw)))))
    cat(sprintf("NDCs mapping to a CHEMO RxCUI      : %d\n", sum(is_chemo)))
    cat(sprintf("Distinct CHEMO RxCUIs covered      : %d  (of %d in chemo list)\n",
                length(unique(as.character(cw)[is_chemo])), length(unique(chemo))))
    ac <- file.path(CONFIG$output_dir, "ndc_rxnorm_crosswalk_audit.csv")
    if (file.exists(ac)) {
      a  <- read.csv(ac, colClasses = "character", check.names = FALSE)
      nm <- tolower(names(a)); names(a) <- nm
      rc <- if ("rxcui" %in% nm) a$rxcui else rep(NA, nrow(a))
      matched <- sum(!is.na(rc) & rc != "")
      cat(sprintf("Audit rows (distinct NDCs queried) : %d\n", nrow(a)))
      cat(sprintf("Audit matched (RxCUI resolved)     : %d\n", matched))
      cat(sprintf("Audit miss (no RxCUI)              : %d\n", nrow(a) - matched))
    } else {
      cat("audit CSV not found at", ac, "(non-fatal)\n")
    }
  '
  echo "[exit code crosswalk summary: $?]"
  echo

  echo "=============================================================="
  echo " Done. Full log: ${LOG}"
  echo "=============================================================="
} 2>&1 | tee "$LOG"

# --- Print the full log text so it can be copied even if stdout was lost ---
echo
echo ">>>>>>>>>>>>>>>>>>>> BEGIN LOG TEXT (${LOG}) <<<<<<<<<<<<<<<<<<<<"
cat "$LOG"
echo ">>>>>>>>>>>>>>>>>>>>  END LOG TEXT  <<<<<<<<<<<<<<<<<<<<"
