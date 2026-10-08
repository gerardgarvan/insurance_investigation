#!/bin/bash
#SBATCH --job-name=88_smoke_test
#SBATCH --account=erin.mobley-hl.bcu
#SBATCH --qos=erin.mobley-hl.bcu
#SBATCH --nodes=1 --ntasks=1 --cpus-per-task=2
#SBATCH --mem=16gb
#SBATCH --time=02:00:00
#SBATCH --output=logs/88_smoke_%j.out
#
# ==============================================================================
# 88_smoke_test.sbatch
#
# Run R/88_smoke_test_comprehensive.R after all phase-specific jobs complete.
# Typically submitted with --dependency=afterok:<J165>:<J166>:<J167>:<J168>.
#
# Submit:
#   J88=$(sbatch --parsable --dependency=afterok:$J165:$J166:$J167:$J168 \
#           slurm/88_smoke_test.sbatch)
# ==============================================================================

set -e

module load R/4.5

cd /blue/erin.mobley-hl.bcu/insurance_investigation

mkdir -p logs

Rscript R/88_smoke_test_comprehensive.R > logs/88_smoke_$(date +%Y%m%d).log 2>&1
