#!/bin/bash
#SBATCH --job-name=165_dist_cbc_assoc
#SBATCH --account=erin.mobley-hl.bcu
#SBATCH --qos=erin.mobley-hl.bcu
#SBATCH --nodes=1 --ntasks=1 --cpus-per-task=4
#SBATCH --mem=64gb
#SBATCH --time=04:00:00
#SBATCH --output=logs/165_association_%j.out
#
# ==============================================================================
# 165_distance_cbc_association.sbatch
#
# Phase 165 Plan 02: far_from_care_100mi x CBC association — production run.
# Method: Rao-Scott cluster-adjusted chi-square + svyglm OR (D-165-01).
# Runs whole-record and post-anchor windows; produces five-sheet xlsx workbook.
#
# Prerequisites (must be satisfied before submitting):
#   1. R/122_encounter_distance.R has produced encounter_distance_*.rds in
#      CONFIG$output_dir (/blue/erin.mobley-hl.bcu/insurance_investigation/output/).
#   2. R/116_encounter_ses_index.R has produced encounter_ses_index_*.rds in
#      CONFIG$output_dir (rurality covariate; missing = sensitivity drops those rows).
#   3. payer_summary_*.rds is present in CONFIG$output_dir (from R/02_harmonize_payer.R).
#   4. survey and openxlsx are installed in the renv library:
#        module load R/4.5
#        R -e 'renv::install(c("survey","openxlsx")); renv::snapshot()'
#   5. CONFIG$distance_assoc_method is "rao_scott" (set in R/00_config.R; D-165-01).
#
# Sizing notes (from Plan 01 prototype timings):
#   Prototype whole-record Rao-Scott svychisq + svyglm on 1.7M encounters: ~35 min.
#   Post-anchor window: ~27 min. Sensitivity model (two windows): ~20 min total.
#   --time=04:00:00 is conservative; reduce to 02:00:00 once timing is confirmed.
#   --mem=64gb: CBC re-derive from LAB_RESULT_CM + survey design objects in memory.
#   --cpus-per-task=4: DuckDB multi-thread for CBC query; svydesign is single-threaded.
#
# Submit:
#   sbatch slurm/165_distance_cbc_association.sbatch
#
# Monitor:
#   tail -f logs/165_association_<jobid>.out
#   grep -E "ERROR|error|Warning|Section|Window|Workbook|COMPLETE" logs/165_association_<jobid>.out
#
# Output:
#   output/distance_cbc_association_<YYYYMMDD>.xlsx
# ==============================================================================

module load R/4.5

cd /blue/erin.mobley-hl.bcu/insurance_investigation

mkdir -p logs

Rscript R/165_distance_cbc_association.R > logs/164_association_$(date +%Y%m%d).log 2>&1
