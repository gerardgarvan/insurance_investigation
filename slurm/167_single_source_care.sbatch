#!/bin/bash
#SBATCH --job-name=167_single_source_care
#SBATCH --account=erin.mobley-hl.bcu
#SBATCH --qos=erin.mobley-hl.bcu
#SBATCH --nodes=1 --ntasks=1 --cpus-per-task=4
#SBATCH --mem=16gb
#SBATCH --time=02:00:00
#SBATCH --output=logs/167_single_source_care_%j.out
#
# ==============================================================================
# 167_single_source_care.sbatch
#
# Phase 167: Single-health-system care flag.
# Runs the Phase 167 testthat file, then R/169_single_source_care.R, then the
# comprehensive smoke test (SMOKE-167-01).
#
# Prerequisites (must be satisfied before submitting):
#   1. DuckDB cache exists (R/03_duckdb_ingest.R has been run).
#   2. get_hl_any_dx_ids() anchor source is available (R/147 has been run).
#   3. openxlsx is available in the renv library:
#        module load R/4.5
#        R -e 'renv::install("openxlsx"); renv::snapshot()'
#
# Submit:
#   sbatch slurm/167_single_source_care.sbatch
#
# Monitor:
#   tail -f logs/167_single_source_care_<jobid>.out
#   grep -E "ERROR|FAIL|PASS|SMOKE-167|complete|Wrote" logs/167_single_source_care_<jobid>.out
#
# Outputs:
#   output/single_source_care_<YYYYMMDD>.xlsx                  (aggregate, suppressed)
#   output/internal/single_source_care_<YYYYMMDD>.csv          (INTERNAL, patient-level)
#   output/internal/single_source_care_<YYYYMMDD>.rds          (INTERNAL, patient-level)
#   output/internal/single_source_care_parts_<YYYYMMDD>.rds    (INTERNAL, parts for downstream)
# ==============================================================================

set -e

module load R/4.5

cd /blue/erin.mobley-hl.bcu/insurance_investigation

mkdir -p logs

echo "=== Phase 167: Single-health-system care flag ==="
echo "=== Started: $(date) ==="

# Step 0: Run Phase 167 unit tests
echo "--- Step 0: Running Phase 167 unit tests ---"
Rscript -e 'testthat::test_file("tests/testthat/test-169-single-source-care.R")' \
  > logs/167_tests_$(date +%Y%m%d).log 2>&1
echo "--- Tests complete. See logs/167_tests_$(date +%Y%m%d).log ---"

# Step 1: Single-source care flag script
echo "--- Step 1: R/169_single_source_care.R ---"
Rscript R/169_single_source_care.R \
  > logs/167_single_source_care_$(date +%Y%m%d).log 2>&1
echo "--- R/169 complete. See logs/167_single_source_care_$(date +%Y%m%d).log ---"

# Step 2: Comprehensive smoke test (SMOKE-167-01)
echo "--- Step 2: R/88_smoke_test_comprehensive.R (SMOKE-167-01) ---"
Rscript R/88_smoke_test_comprehensive.R \
  > logs/167_smoke_$(date +%Y%m%d).log 2>&1
echo "--- Smoke test complete. See logs/167_smoke_$(date +%Y%m%d).log ---"

echo "=== Phase 167 COMPLETE: $(date) ==="
