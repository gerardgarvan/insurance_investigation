#!/bin/bash
#SBATCH --job-name=hl_investigations
#SBATCH --output=output/logs/investigations_%j.log
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=32G
#SBATCH --time=04:00:00
#SBATCH --account=erin.mobley-hl.bcu

module load R/4.4.2

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG="output/logs/investigations_${TIMESTAMP}.log"

mkdir -p output/logs

echo "=== R/39 investigations run: ${TIMESTAMP} ===" | tee "$LOG"
Rscript R/39_run_all_investigations.R 2>&1 | tee -a "$LOG"
echo "=== Done: $(date) ===" | tee -a "$LOG"
