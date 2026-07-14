#!/usr/bin/env bash
# ==============================================================================
# run_122_verification.sh -- Phase 122 checkpoint capture (HiPerGator)
# ==============================================================================
# Runs R/88 (comprehensive smoke test) and R/107 (MED_ADMIN/DISPENSING chemo-gap
# diagnostic) and saves ALL console output (stdout + stderr) to one timestamped
# log file so it can be reviewed/pasted.
#
# Prereq: run R/108 first to build data/reference/ndc_rxnorm_crosswalk.rds, else
#         the NDC-crosswalk paths degrade to empty (DISPENSING/MED_ADMIN-ND = 0).
#
# Usage (from the repo root on HiPerGator):
#   bash run_122_verification.sh
#
# Output:
#   output/logs/phase122_verification_<YYYYMMDD_HHMMSS>.log
# ==============================================================================

set -o pipefail

# --- Load the R module (HiPerGator). Adjust the version if your project pins another. ---
# 'module' is a shell function; source the init script so it works in a non-login shell.
if ! command -v module >/dev/null 2>&1; then
  if [ -f /etc/profile.d/modules.sh ]; then
    # shellcheck disable=SC1091
    . /etc/profile.d/modules.sh
  fi
fi
module load R/4.4.2 2>/dev/null || echo "[warn] could not 'module load R/4.4.2' — assuming Rscript is already on PATH"

# --- Confirm Rscript is available ---
if ! command -v Rscript >/dev/null 2>&1; then
  echo "[error] Rscript not found on PATH. Load an R module first (module load R/4.4.2)." >&2
  exit 1
fi

# --- Prepare timestamped log ---
mkdir -p output/logs
STAMP="$(date +%Y%m%d_%H%M%S)"
LOG="output/logs/phase122_verification_${STAMP}.log"

# --- Run both scripts, tee everything (stdout+stderr) to the log ---
{
  echo "=============================================================="
  echo " Phase 122 verification run"
  echo " Date        : $(date)"
  echo " Host        : $(hostname)"
  echo " Repo root   : $(pwd)"
  echo " R version   : $(Rscript -e 'cat(R.version.string)' 2>/dev/null)"
  echo " Crosswalk   : $( [ -f data/reference/ndc_rxnorm_crosswalk.rds ] && echo 'PRESENT' || echo 'MISSING (run R/108 first)')"
  echo "=============================================================="
  echo

  echo "######################## R/88 SMOKE TEST ########################"
  Rscript R/88_smoke_test_comprehensive.R
  echo "[exit code R/88: $?]"
  echo

  echo "#################### R/107 CHEMO-GAP DIAGNOSTIC ##################"
  Rscript R/107_med_admin_dispensing_gap_diagnostic.R
  echo "[exit code R/107: $?]"
  echo

  echo "=============================================================="
  echo " Done. Full log: ${LOG}"
  echo "=============================================================="
} 2>&1 | tee "$LOG"

echo
echo ">>> Saved console output to: ${LOG}"
echo ">>> Download or 'cat' that file and paste it back."
