#!/bin/bash
#SBATCH --job-name=147_verify
#SBATCH --account=erin.mobley-hl.bcu
#SBATCH --qos=erin.mobley-hl.bcu
#SBATCH --nodes=1 --ntasks=1 --cpus-per-task=2
#SBATCH --mem=16gb
#SBATCH --time=01:00:00
#SBATCH --output=logs/147_verify_%j.out
#
# ==============================================================================
# 147_verify.sbatch
#
# Run R/147_verify_vs_1006.R.  Propagates the Rscript exit code so SLURM
# shows FAILED (not COMPLETED) when verify reports OVERALL: FAIL.
#
# VERIFY_RUN_DATE must be passed via --export so the verify script reads the
# correct dated input files and writes the correct dated log.
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
# afterany on JOB_VER so R/88 always runs even if verify fails,
# showing both verify failures and smoke-test results in one submission.
# ==============================================================================

# NOTE: no set -e — we capture the Rscript exit code manually.

module load R/4.5

cd /blue/erin.mobley-hl.bcu/insurance_investigation

mkdir -p logs output/logs

echo "VERIFY_RUN_DATE=${VERIFY_RUN_DATE}"

Rscript R/147_verify_vs_1006.R \
  > logs/147_verify_${VERIFY_RUN_DATE:-$(date +%Y%m%d)}.log 2>&1

rc=$?
echo "verify exit: $rc"
exit $rc
