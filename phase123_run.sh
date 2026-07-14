#!/usr/bin/env bash
# ==============================================================================
# phase123_run.sh -- Run R/109 and capture full output to a text file (HiPerGator)
# ==============================================================================
# Runs R/109_med_admin_dispensing_fix_impact_audit.R and captures the ENTIRE
# console output (including any error + traceback) to a timestamped log, then
# prints the full log text to the terminal at the end so it can be copied/pasted
# even from a SLURM .out or a non-interactive shell.
#
# Usage (from the repo root on HiPerGator):
#   git pull origin main
#   bash phase123_run.sh
#
# Output:
#   output/logs/phase123_run_<YYYYMMDD_HHMMSS>.log
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
LOG="output/logs/phase123_run_${STAMP}.log"

{
  echo "=============================================================="
  echo " Phase 123 run (R/109 fix-impact + NDC audit)"
  echo " Date      : $(date)"
  echo " Host      : $(hostname)"
  echo " Repo root : $(pwd)"
  echo " Crosswalk : $( [ -f data/reference/ndc_rxnorm_crosswalk.rds ] && echo PRESENT || echo 'MISSING (run R/108 first)')"
  echo " Episodes  : $( [ -f cache/outputs/treatment_episodes.rds ] && echo PRESENT || echo 'MISSING (D-06 will skip)')"
  echo "=============================================================="
  echo

  echo "#################### R/109 DIAGNOSTIC ####################"
  # --verbose forces full traceback on error so we can diagnose failures.
  Rscript --verbose R/109_med_admin_dispensing_fix_impact_audit.R
  echo "[exit code R/109: $?]"
  echo

  echo "#################### OUTPUT CHECK ####################"
  echo "xlsx    : $( [ -f output/med_admin_dispensing_fix_impact.xlsx ] && echo "PRESENT ($(stat -c%s output/med_admin_dispensing_fix_impact.xlsx 2>/dev/null) bytes)" || echo MISSING )"
  echo "requery : $( [ -f output/ndc_rxnorm_crosswalk_requery.csv ] && echo PRESENT || echo MISSING )"
  echo "audit   : $( [ -f output/ndc_rxnorm_crosswalk_audit.csv ] && echo 'PRESENT (should be unchanged)' || echo MISSING )"
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
