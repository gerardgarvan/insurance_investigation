#!/bin/bash
#SBATCH --job-name=168_nhl_gantt_subsets
#SBATCH --account=erin.mobley-hl.bcu
#SBATCH --qos=erin.mobley-hl.bcu
#SBATCH --nodes=1 --ntasks=1 --cpus-per-task=2
#SBATCH --mem=8gb
#SBATCH --time=01:00:00
#SBATCH --output=logs/168_nhl_gantt_subsets_%j.out
#
# ==============================================================================
# 168_nhl_gantt_subsets.sbatch
#
# Phase 168: NHL-Only and HL+NHL Gantt Episode Subsets.
# Runs the Phase 168 testthat file, then R/170_nhl_gantt_subsets.R, then the
# comprehensive smoke test (SMOKE-168-01).
#
# Prerequisites (must be satisfied before submitting):
#   1. Confirm CONFIG$chemo_combos_path (the chemo-combos workbook path).
#   2. Confirm CONFIG$gantt_180_snapshot_path points at the 2026-08-14
#      gantt_episodes_180.csv (stat -c %s <file> should print 6549041).
#   3. Confirm the tab name "Chemo and Cancer Dx" and 10 column headers.
#   4. openxlsx and readxl are available in the renv library:
#        module load R/4.5
#        R -e 'renv::install(c("openxlsx","readxl")); renv::snapshot()'
#
# Submit:
#   sbatch slurm/168_nhl_gantt_subsets.sbatch
#
# Monitor:
#   tail -f logs/168_nhl_gantt_subsets_<jobid>.out
#   grep -E "ERROR|FAIL|PASS|SMOKE-168|complete|Wrote" logs/168_nhl_gantt_subsets_<jobid>.out
#
# Outputs (all INTERNAL — patient-level):
#   output/internal/nhl_gantt_subsets_<YYYYMMDD>.xlsx
#   output/internal/nhl_only_episodes_<YYYYMMDD>.csv
#   output/internal/hl_nhl_episodes_<YYYYMMDD>.csv
# ==============================================================================

set -e

module load R/4.5

cd /blue/erin.mobley-hl.bcu/insurance_investigation

mkdir -p logs

echo "=== Phase 168: NHL-Only and HL+NHL Gantt Episode Subsets ==="
echo "=== Started: $(date) ==="

# Step 0: Run Phase 168 unit tests
echo "--- Step 0: Running Phase 168 unit tests ---"
Rscript -e 'testthat::test_file("tests/testthat/test-170-nhl-gantt-subsets.R")' \
  > logs/168_tests_$(date +%Y%m%d).log 2>&1
echo "--- Tests complete. See logs/168_tests_$(date +%Y%m%d).log ---"

# Step 1: NHL-only / HL+NHL subsets script
echo "--- Step 1: R/170_nhl_gantt_subsets.R ---"
Rscript R/170_nhl_gantt_subsets.R \
  > logs/168_nhl_gantt_subsets_$(date +%Y%m%d).log 2>&1
echo "--- R/170 complete. See logs/168_nhl_gantt_subsets_$(date +%Y%m%d).log ---"

# Step 2: Comprehensive smoke test (SMOKE-168-01)
echo "--- Step 2: R/88_smoke_test_comprehensive.R (SMOKE-168-01) ---"
Rscript R/88_smoke_test_comprehensive.R \
  > logs/168_smoke_$(date +%Y%m%d).log 2>&1
echo "--- Smoke test complete. See logs/168_smoke_$(date +%Y%m%d).log ---"

echo "=== Phase 168 COMPLETE: $(date) ==="
