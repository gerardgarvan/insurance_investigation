#!/bin/bash
# run_149_adi_rebuild.sh
# Archive pre-ADI outputs, rebuild SES index with new ADI reference, smoke test.
# Usage: bash run_149_adi_rebuild.sh
# Log: output/logs/149_adi_rebuild_<timestamp>.log

set -euo pipefail

PROJECT=/blue/erin.mobley-hl.bcu/insurance_investigation
LOG_DIR="$PROJECT/output/logs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG="$LOG_DIR/149_adi_rebuild_${TIMESTAMP}.log"

mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG") 2>&1

echo "========================================"
echo "149 ADI rebuild — $(date)"
echo "Log: $LOG"
echo "========================================"

# ── 1. Confirm the reference file arrived ────────────────────────────────────
REF="$PROJECT/data/reference/neighborhood_atlas_zip9_adi.csv"
if [ ! -f "$REF" ]; then
  echo "ERROR: $REF not found — transfer it before rebuilding." >&2
  exit 1
fi
SIZE=$(du -h "$REF" | cut -f1)
ROWS=$(( $(wc -l < "$REF") - 1 ))
echo "Reference file: $REF"
echo "  size: $SIZE  rows: $ROWS"
echo

# ── 2. Archive pre-ADI outputs ───────────────────────────────────────────────
echo "--- Archiving pre-ADI output files ---"
cd "$PROJECT/output"
ARCHIVED=0
for f in encounter_ses_index_*.rds encounter_ses_index_summary_*.xlsx zip_stability_counts_*.xlsx; do
  [ -e "$f" ] || continue
  case "$f" in *_preadi.*) continue ;; esac
  newname="${f%.*}_preadi.${f##*.}"
  mv "$f" "$newname"
  echo "  archived: $f -> $newname"
  ARCHIVED=$(( ARCHIVED + 1 ))
done
[ "$ARCHIVED" -eq 0 ] && echo "  (no files to archive)"
cd "$PROJECT"
echo

# ── 3. R/118 — build ZIP5 ADI summary ───────────────────────────────────────
echo "========================================"
echo "--- R/118_build_zip5_adi_summary.R --- $(date)"
echo "========================================"
Rscript "$PROJECT/R/118_build_zip5_adi_summary.R"
echo "--- R/118 done: $(date) ---"
echo

# ── 5. R/116 — encounter SES index ──────────────────────────────────────────
echo "========================================"
echo "--- R/116_encounter_ses_index.R --- $(date)"
echo "========================================"
Rscript "$PROJECT/R/116_encounter_ses_index.R"
echo "--- R/116 done: $(date) ---"
echo

# ── 6. Verify zip9_source distribution ──────────────────────────────────────
echo "========================================"
echo "--- zip9_source distribution check ---"
echo "========================================"
LATEST_RDS=$(ls -t "$PROJECT/output/encounter_ses_index_"*.rds 2>/dev/null | grep -v preadi | head -1)
if [ -z "$LATEST_RDS" ]; then
  echo "WARNING: no encounter_ses_index_*.rds found — R/116 may have failed"
else
  echo "RDS: $LATEST_RDS"
  Rscript - << 'REOF'
library(dplyr)
f <- Sys.glob("output/encounter_ses_index_*.rds") |> grep("preadi", x=_, invert=TRUE, value=TRUE) |> sort() |> tail(1)
d <- readRDS(f)
cat("\nzip9_source distribution:\n")
d |> count(zip9_source, sort=TRUE) |> mutate(pct=round(n/sum(n)*100,1)) |> print()
cat("\nTotal encounters:", format(nrow(d), big.mark=","), "\n")
cat("\nExpected: zip5_no_zip9 ~900, zip5_representative ~58000, zip9_observed ~1516469, none ~158699\n")
REOF
fi
echo

# ── 7. R/88 — smoke test ────────────────────────────────────────────────────
echo "========================================"
echo "--- R/88_smoke_test_comprehensive.R --- $(date)"
echo "========================================"
Rscript "$PROJECT/R/88_smoke_test_comprehensive.R"
echo "--- R/88 done: $(date) ---"
echo

echo "========================================"
echo "Rebuild complete: $(date)"
echo "Log saved to: $LOG"
echo "========================================"
