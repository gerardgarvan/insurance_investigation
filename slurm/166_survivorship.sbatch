#!/bin/bash
#SBATCH --job-name=166_survivorship
#SBATCH --account=erin.mobley-hl.bcu
#SBATCH --qos=erin.mobley-hl.bcu
#SBATCH --nodes=1 --ntasks=1 --cpus-per-task=4
#SBATCH --mem=32gb
#SBATCH --time=04:00:00
#SBATCH --output=logs/166_survivorship_%j.out
#
# ==============================================================================
# 166_survivorship.sbatch
#
# Phase 166: Survivorship modality rates and anthracycline-to-echo timing.
# Runs testthat files, then the three Phase 166 driver scripts in dependency
# order (rates -> echo -> workbook), each with a dated log.
#
# Prerequisites (must be satisfied before submitting):
#   1. R/147 has been run and surveillance_modality_patient_<date>.rds exists.
#   2. R/162 has been run and patient modality date exports exist.
#   3. treatment_episode_detail_180.rds exists in CONFIG$cache$outputs_dir.
#   4. openxlsx and survival are available in the renv library:
#        module load R/4.5
#        R -e 'renv::install(c("openxlsx","survival")); renv::snapshot()'
#
# Submit:
#   sbatch slurm/166_survivorship.sbatch
#
# Monitor:
#   tail -f logs/166_survivorship_<jobid>.out
#   grep -E "ERROR|FAIL|PASS|Section|complete|Outputs" logs/166_survivorship_<jobid>.out
#
# Outputs:
#   output/survivorship_modality_rates_parts_<YYYYMMDD>.rds
#   output/survivorship_echo_parts_<YYYYMMDD>.rds
#   output/survivorship_modality_rates_long_<YYYYMMDD>.rds        (INTERNAL)
#   output/survivorship_modality_rates_patient_<YYYYMMDD>.rds     (INTERNAL)
#   output/survivorship_modality_rates_patient_<YYYYMMDD>.csv     (INTERNAL)
#   output/survivorship_modality_rates_<YYYYMMDD>.xlsx
# ==============================================================================

set -e

module load R/4.5

cd /blue/erin.mobley-hl.bcu/insurance_investigation

mkdir -p logs

echo "=== Phase 166: Survivorship rates + anthracycline-echo timing ==="
echo "=== Started: $(date) ==="

# Step 0: Run testthat unit tests for Phase 166
echo "--- Step 0: Running Phase 166 unit tests ---"
Rscript -e 'testthat::test_file("tests/testthat/test-166-rates.R"); testthat::test_file("tests/testthat/test-166-echo.R")' \
  > logs/166_tests_$(date +%Y%m%d).log 2>&1
echo "--- Tests complete. See logs/166_tests_$(date +%Y%m%d).log ---"

# Step 1: Survivorship modality rates (Plan 02 driver)
echo "--- Step 1: R/166_survivorship_modality_rates.R ---"
Rscript R/166_survivorship_modality_rates.R \
  > logs/166_rates_$(date +%Y%m%d).log 2>&1
echo "--- Rates complete. See logs/166_rates_$(date +%Y%m%d).log ---"

# Step 2: Anthracycline-to-echo timing (Plan 03 driver)
echo "--- Step 2: R/167_anthracycline_echo.R ---"
Rscript R/167_anthracycline_echo.R \
  > logs/166_echo_$(date +%Y%m%d).log 2>&1
echo "--- Echo complete. See logs/166_echo_$(date +%Y%m%d).log ---"

# Step 3: Survivorship workbook assembler (Plan 04)
echo "--- Step 3: R/168_survivorship_workbook.R ---"
Rscript R/168_survivorship_workbook.R \
  > logs/166_workbook_$(date +%Y%m%d).log 2>&1
echo "--- Workbook complete. See logs/166_workbook_$(date +%Y%m%d).log ---"

echo "=== Phase 166 COMPLETE: $(date) ==="
