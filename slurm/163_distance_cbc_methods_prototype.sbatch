#!/bin/bash
#SBATCH --job-name=163_dist_cbc_proto
#SBATCH --account=erin.mobley-hl.bcu
#SBATCH --qos=erin.mobley-hl.bcu
#SBATCH --nodes=1 --ntasks=1 --cpus-per-task=4
#SBATCH --mem=64gb
#SBATCH --time=08:00:00
#SBATCH --output=logs/163_prototype_%j.out
#
# ==============================================================================
# 163_distance_cbc_methods_prototype.sbatch
#
# Phase 165 Plan 01: Distance >100 mi and CBC association methods prototype.
# Runs all four candidate statistical tests (naive Pearson, Rao-Scott,
# GEE logistic, patient-level) for both windows (whole record, post-anchor).
# Writes enc_far_from_care.rds (ACC-01 deliverable) and prints DEFF table.
#
# Prerequisites (must be satisfied before submitting):
#   1. R/122_encounter_distance.R has run and produced enc_distance_*.rds in
#      CONFIG$cache$outputs_dir (/blue/erin.mobley-hl.bcu/clean/rds/outputs/).
#   2. survey and geepack are installed in the renv library:
#        module load R/4.5
#        R -e 'renv::install(c("survey","geepack")); renv::snapshot()'
#   3. renv.lock is up to date (copy local repo -> HiPerGator after snapshot).
#
# Sizing notes (adjust after first run):
#   --mem=64gb : LAB_RESULT_CM CBC re-derive + GEE on large encounter sets
#   --time=08:00:00 : conservative; GEE with exchangeable on a large cluster
#                     may take 2-4 hours; reduce after timing is known
#   --cpus-per-task=4 : DuckDB multi-thread for CBC query
#
# Submit:
#   sbatch slurm/163_distance_cbc_methods_prototype.sbatch
#
# Check output:
#   tail -f logs/163_prototype_<jobid>.out
#   grep -E "ERROR|error|Warning|Section|Window|DEFF|results" logs/163_prototype_<jobid>.out
# ==============================================================================

module load R/4.5

cd /blue/erin.mobley-hl.bcu/insurance_investigation

mkdir -p logs

Rscript R/163_distance_cbc_methods_prototype.R > logs/163_prototype_$(date +%Y%m%d).log 2>&1
