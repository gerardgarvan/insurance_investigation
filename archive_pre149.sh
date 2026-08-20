#!/usr/bin/env bash
# archive_pre149.sh
#
# Run this on HiPerGator BEFORE the Phase 149 re-run (R/118 -> R/115 -> R/116 -> R/88).
# Renames existing dated output files to *_pre149.* so the re-run does not silently
# overwrite the 2026-08-20 baseline.
#
# Usage (from repo root on HiPerGator):
#   bash archive_pre149.sh
#
# Source: 149-CONTEXT.md §5 (verbatim loop)

set -euo pipefail

cd output

for f in encounter_ses_index_*.rds encounter_ses_index_*.xlsx \
         encounter_ses_index_summary_*.xlsx zip_stability_counts_*.xlsx; do
  [ -e "$f" ] || continue
  case "$f" in *_pre14*.*) continue;; esac
  mv "$f" "${f%.*}_pre149.${f##*.}" && echo "archived $f"
done

cd ..

echo "Archive complete. Verify with: ls output/*_pre149.*"
