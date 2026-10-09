#!/bin/bash
#SBATCH --job-name=147_surveillance
#SBATCH --account=erin.mobley-hl.bcu
#SBATCH --qos=erin.mobley-hl.bcu
#SBATCH --nodes=1 --ntasks=1 --cpus-per-task=4
#SBATCH --mem=32gb
#SBATCH --time=04:00:00
#SBATCH --output=logs/147_surveillance_%j.out
#
# ==============================================================================
# 147_surveillance.sbatch
#
# Run R/147_surveillance_modality_frequency.R.  R/147 dates its own output
# files by Sys.Date() at runtime.  Pass VERIFY_RUN_DATE so the downstream
# verify job uses the same date string.
#
# Submit as part of the Phase 170 job chain (see 170-CONTEXT.md D-01):
#
#   export VERIFY_RUN_DATE=$(date +%Y%m%d)
#   JOB147=$(sbatch --parsable \
#             --export=ALL,VERIFY_RUN_DATE=$VERIFY_RUN_DATE \
#             slurm/147_surveillance.sbatch)
#   JOB_VER=$(sbatch --parsable \
#              --dependency=afterok:$JOB147 \
#              --export=ALL,VERIFY_RUN_DATE=$VERIFY_RUN_DATE \
#              slurm/147_verify.sbatch)
#   JOB88=$(sbatch  --parsable \
#            --dependency=afterany:$JOB_VER \
#            slurm/88_smoke_test.sbatch)
#
# NOTE: If R/147 runs past midnight and Sys.Date() changes, the verify job
# will fail with "new workbook missing" because VERIFY_RUN_DATE and the file
# date will differ.  Re-run with the correct VERIFY_RUN_DATE.
# ==============================================================================

set -e

module load R/4.5

cd /blue/erin.mobley-hl.bcu/insurance_investigation

mkdir -p logs output/logs

Rscript R/147_surveillance_modality_frequency.R \
  > logs/147_surveillance_${VERIFY_RUN_DATE:-$(date +%Y%m%d)}.log 2>&1
