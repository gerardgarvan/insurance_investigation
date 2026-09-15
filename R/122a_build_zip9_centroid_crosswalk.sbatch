#!/bin/bash
#SBATCH --job-name=122a_zip9_centroid
#SBATCH --account=erin.mobley-hl.bcu
#SBATCH --qos=erin.mobley-hl.bcu
#SBATCH --nodes=1 --ntasks=1 --cpus-per-task=4
#SBATCH --mem=32gb
#SBATCH --time=02:00:00
#SBATCH --output=logs/122a_%j.out
# Set the R module to whatever `module spider R` lists (the plans' "R/4.4.2" does not exist).
module load R
cd /blue/erin.mobley-hl.bcu/insurance_investigation
Rscript R/122a_build_zip9_centroid_crosswalk.R
