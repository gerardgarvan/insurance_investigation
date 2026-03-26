#!/bin/bash
#SBATCH --job-name=hl_payer_pipeline
#SBATCH --output=output/slurm_%j.log
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=64G
#SBATCH --time=100:00:00
#SBATCH --partition=default
#SBATCH --account=erin.mobley-hl.bcu

module load R/4.5

Rscript R/04_build_cohort.R
