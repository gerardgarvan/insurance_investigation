#!/bin/bash
#SBATCH --job-name=171_verify_survivorship
#SBATCH --account=erin.mobley-hl.bcu
#SBATCH --qos=erin.mobley-hl.bcu
#SBATCH --nodes=1 --ntasks=1 --cpus-per-task=1
#SBATCH --mem=8gb
#SBATCH --time=00:30:00
#SBATCH --output=logs/171_verify_survivorship_%j.out
#
# ==============================================================================
# 171_verify_survivorship.sbatch
#
# Run R/171_verify_survivorship.R.  Propagates the Rscript exit code so SLURM
# shows FAILED (not COMPLETED) when verify reports OVERALL: FAIL.
#
# Chain after 166_survivorship.sbatch using afterok so this script only runs
# when all three Phase 166 scripts (R/166, R/167, R/168) exit 0.
#
# SURV_RUN_DATE must be passed via --export so both R/168 (in the upstream job)
# and this verify script use the same date to locate the new workbook.
#
# Submit as part of the Phase 171 job chain:
#
#   export SURV_RUN_DATE=$(date +%Y%m%d)
#   JOB166=$(sbatch --parsable \
#             --export=ALL,SURV_RUN_DATE=$SURV_RUN_DATE \
#             slurm/166_survivorship.sbatch)
#   JOB_VER=$(sbatch --parsable \
#              --dependency=afterok:$JOB166 \
#              --export=ALL,SURV_RUN_DATE=$SURV_RUN_DATE \
#              slurm/171_verify_survivorship.sbatch)
#   JOB88=$(sbatch  --parsable \
#            --dependency=afterany:$JOB_VER \
#            slurm/88_smoke_test.sbatch)
#
# afterany on JOB_VER so R/88 always runs even if verify fails,
# showing smoke-test results in one submission.
# ==============================================================================

# NOTE: no set -e — we capture the Rscript exit code manually.

module load R/4.5

cd /blue/erin.mobley-hl.bcu/insurance_investigation

mkdir -p logs output/logs

echo "SURV_RUN_DATE=${SURV_RUN_DATE}"

Rscript R/171_verify_survivorship.R \
  > logs/171_verify_${SURV_RUN_DATE:-$(date +%Y%m%d)}.log 2>&1

rc=$?
echo "171 verify exit: $rc"
exit $rc
