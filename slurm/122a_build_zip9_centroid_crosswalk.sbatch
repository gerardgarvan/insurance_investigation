#!/bin/bash
#SBATCH --job-name=122a_zip9_centroid
#SBATCH --output=output/logs/122a_zip9_centroid_%j.log
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=32G
#SBATCH --time=04:00:00
#SBATCH --account=erin.mobley-hl.bcu

# ==============================================================================
# 122a_build_zip9_centroid_crosswalk.sbatch
# One-time builder: ZIP9 -> block-group centroid crosswalk (Phase 152, Plan 00)
#
# Reads 51 Neighborhood Atlas ZIP+4 files (~7.5 GB total), normalizes ZIP9s,
# joins to block-group internal-point coordinates, writes:
#   data/reference/zip9_bg_centroid_crosswalk.csv
#   data/reference/zip9_bg_centroid_crosswalk_BUILDLOG_<date>.txt
#
# BEFORE SUBMITTING:
#   1. Confirm CONFIG$atlas_zip4_dir in R/00_config.R (Task 1 head inspection):
#        ls /blue/erin.mobley.precision/
#        head -2 <atlas_dir>/<smallest_state>.csv
#   2. Update ZIP4_COL and FIPS_COL placeholders in R/122a_build_zip9_centroid_crosswalk.R
#      with the confirmed column names from step 1.
#   3. Confirm a centroid source (NHGIS CSV or TIGER/Line DBFs) is staged under
#      /blue/erin.mobley.precision/ or /blue/erin.mobley-hl.bcu/reference/.
#      The script stops with a message if neither is found.
#
# Submit:
#   sbatch slurm/122a_build_zip9_centroid_crosswalk.sbatch
# ==============================================================================

module load R/4.4.2

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG="output/logs/122a_zip9_centroid_${TIMESTAMP}.log"

mkdir -p output/logs data/reference

echo "=== R/122a ZIP9 centroid crosswalk build: ${TIMESTAMP} ===" | tee "$LOG"
Rscript R/122a_build_zip9_centroid_crosswalk.R 2>&1 | tee -a "$LOG"
echo "=== Done: $(date) ===" | tee -a "$LOG"
