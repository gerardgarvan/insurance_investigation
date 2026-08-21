#!/usr/bin/env bash
# Phase 149 re-run: R/118 -> R/115 -> R/116 -> R/88
# Logs all console output to output/logs/phase149_rerun_<timestamp>.log

set -euo pipefail

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
mkdir -p output/logs
LOG="output/logs/phase149_rerun_${TIMESTAMP}.log"

echo "Phase 149 re-run — $(date)" | tee "$LOG"
echo "Log: $LOG"
echo "----------------------------------------" | tee -a "$LOG"

run_script() {
  local script="$1"
  echo "" | tee -a "$LOG"
  echo "=== $script — $(date) ===" | tee -a "$LOG"
  Rscript "$script" 2>&1 | tee -a "$LOG"
  local exit_code=${PIPESTATUS[0]}
  if [ "$exit_code" -ne 0 ]; then
    echo "FAILED: $script exited $exit_code" | tee -a "$LOG"
    exit "$exit_code"
  fi
  echo "--- $script complete ---" | tee -a "$LOG"
}

run_script R/118_build_zip5_adi_summary.R
run_script R/115_zip_stability_counts.R
run_script R/116_encounter_ses_index.R
run_script R/88_smoke_test_comprehensive.R

echo "" | tee -a "$LOG"
echo "========================================" | tee -a "$LOG"
echo "All scripts complete — $(date)" | tee -a "$LOG"
echo "Log saved to: $LOG"
