#!/usr/bin/env bash
# ==============================================================================
# phase123_smoke.sh -- Run R/88 smoke test and capture to a text file (HiPerGator)
# ==============================================================================
# Runs R/88_smoke_test_comprehensive.R (which includes Phase 123 Section 15u /
# SMOKE-123-01) and captures the full output to a timestamped log. Also prints
# the entire log text to the terminal at the end so it can be copied/pasted even
# from a SLURM .out or a non-interactive shell.
#
# Usage (from the repo root on HiPerGator):
#   git pull origin main
#   bash phase123_smoke.sh
#
# Output:
#   output/logs/phase123_smoke_<YYYYMMDD_HHMMSS>.log
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
LOG="output/logs/phase123_smoke_${STAMP}.log"

{
  echo "=============================================================="
  echo " Phase 123 smoke test (R/88)"
  echo " Date      : $(date)"
  echo " Host      : $(hostname)"
  echo " Repo root : $(pwd)"
  echo " R/109     : $( [ -f R/109_med_admin_dispensing_fix_impact_audit.R ] && echo PRESENT || echo MISSING )"
  echo "=============================================================="
  echo

  echo "#################### R/88 SMOKE TEST ####################"
  echo "(look for the [Phase 123] Section 15u block, the SMOKE-123-01 line,"
  echo " and the final FAILED: n/N summary line)"
  Rscript R/88_smoke_test_comprehensive.R
  echo "[exit code R/88: $?]"
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
