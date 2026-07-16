#!/usr/bin/env bash
# ==============================================================================
# phase130_runtime_check.sh -- Phase 130 DoI runtime gate on HiPerGator (DOI-QA-03)
# ==============================================================================
# Runs the DoI producers (R/111 classification -> R/112 attribution) against the
# REAL DIAGNOSIS table, then runs R/88_smoke_test_comprehensive.R so Section 15w
# Checks 12-14 exercise the real outputs. Captures everything to a timestamped
# log and prints a SHAREABLE SUMMARY that answers the three definition-of-done
# items:
#   (a) verbatim DoI category counts  ([Phase 130 RUNTIME] block)
#   (b) R/88 pass/fail summary         (ALL N CHECKS PASSED | FAILED: n/N)
#   (c) mutual-exclusivity hard-stop   (R/111 "Mutual-exclusivity check: 0 ...")
#
# Usage (from the repo root on HiPerGator, in PRODUCTION mode / IS_LOCAL=FALSE):
#   git pull origin main
#   bash phase130_runtime_check.sh            # direct: R/111 -> R/112 -> R/88
#   bash phase130_runtime_check.sh full       # full pipeline: R/39 -> R/88
#
# Output:
#   output/logs/phase130_runtime_check_<YYYYMMDD_HHMMSS>.log   (full, shareable)
# ==============================================================================

set -o pipefail

MODE="${1:-direct}"   # 'direct' (R/111 + R/112) or 'full' (R/39_run_all_investigations.R)

# --- Load the R module (HiPerGator) ---
if ! command -v module >/dev/null 2>&1; then
  [ -f /etc/profile.d/modules.sh ] && . /etc/profile.d/modules.sh
fi
module load R/4.4.2 2>/dev/null || echo "[warn] could not 'module load R/4.4.2' — assuming Rscript is on PATH"

if ! command -v Rscript >/dev/null 2>&1; then
  echo "[error] Rscript not found on PATH. Load an R module first." >&2
  exit 1
fi

mkdir -p output/logs
STAMP="$(date +%Y%m%d_%H%M%S)"
LOG="output/logs/phase130_runtime_check_${STAMP}.log"

# Per-stage capture files (so the shareable summary can grep exact lines) ---
STAGE_111="output/logs/.p130_r111_${STAMP}.txt"
STAGE_112="output/logs/.p130_r112_${STAMP}.txt"
STAGE_39="output/logs/.p130_r39_${STAMP}.txt"
STAGE_88="output/logs/.p130_r88_${STAMP}.txt"
: > "$STAGE_111"; : > "$STAGE_112"; : > "$STAGE_39"; : > "$STAGE_88"

rc111="(skipped)"; rc112="(skipped)"; rc39="(skipped)"; rc88="(not run)"

{
  echo "=============================================================="
  echo " Phase 130 DoI runtime gate (DOI-QA-03)"
  echo " Date      : $(date)"
  echo " Host      : $(hostname)"
  echo " Repo root : $(pwd)"
  echo " Mode      : ${MODE}  (direct = R/111+R/112 | full = R/39)"
  echo " R/111     : $( [ -f R/111_doi_classification.R ]        && echo PRESENT || echo MISSING )"
  echo " R/112     : $( [ -f R/112_doi_attribution_report.R ]    && echo PRESENT || echo MISSING )"
  echo " R/88      : $( [ -f R/88_smoke_test_comprehensive.R ]   && echo PRESENT || echo MISSING )"
  echo "=============================================================="
  echo
  echo "[note] This gate MUST run in PRODUCTION mode (IS_LOCAL=FALSE) so the real"
  echo "       DIAGNOSIS table is queried. In local mode Section 15w Checks 12-14"
  echo "       stay SKIPPED and the DoI counts will NOT be produced."
  echo

  if [ "$MODE" = "full" ]; then
    echo "#################### STAGE 1: R/39 full investigation pipeline ####################"
    Rscript R/39_run_all_investigations.R 2>&1 | tee "$STAGE_39"
    rc39="${PIPESTATUS[0]}"
    echo "[exit code R/39: ${rc39}]"
    echo
  else
    echo "#################### STAGE 1: R/111 DoI classification ####################"
    echo "(watch for: 'Mutual-exclusivity check: 0 codes classify as BOTH DoI and cancer')"
    Rscript R/111_doi_classification.R 2>&1 | tee "$STAGE_111"
    rc111="${PIPESTATUS[0]}"
    echo "[exit code R/111: ${rc111}]"
    echo

    if [ "$rc111" != "0" ]; then
      echo "[error] R/111 did not exit 0 (rc=${rc111}). If the mutual-exclusivity hard-stop"
      echo "        fired, DOI-CLASS-04 was violated — DO NOT approve the gate. Continuing to"
      echo "        R/112 anyway is pointless; skipping to R/88 for the structural summary."
      echo
    else
      echo "#################### STAGE 2: R/112 DoI attribution report ####################"
      Rscript R/112_doi_attribution_report.R 2>&1 | tee "$STAGE_112"
      rc112="${PIPESTATUS[0]}"
      echo "[exit code R/112: ${rc112}]"
      echo
    fi
  fi

  echo "#################### STAGE 3: R/88 smoke test (Section 15w) ####################"
  echo "(look for the [Phase 130 RUNTIME] DoI category counts block and the final summary line)"
  Rscript R/88_smoke_test_comprehensive.R 2>&1 | tee "$STAGE_88"
  rc88="${PIPESTATUS[0]}"
  echo "[exit code R/88: ${rc88}]"
  echo

  # --- Build the SHAREABLE SUMMARY by extracting exact lines from stage logs ----
  echo "=============================================================="
  echo " SHAREABLE SUMMARY — Phase 130 definition-of-done (DOI-QA-03)"
  echo "=============================================================="
  echo

  echo "----- (a) DoI category counts [verbatim, log into phase notes] -----"
  # Print the [Phase 130 RUNTIME] header and the indented count lines that follow it.
  awk '/\[Phase 130 RUNTIME\] DoI category counts/{p=1} p{print} /R\/111 real-data DoI counts non-empty/{if(p)p=0}' "$STAGE_88" \
    | grep -vE "R/111 real-data DoI counts non-empty" \
    || echo "  (NOT FOUND — did R/88 run in PRODUCTION mode with IS_LOCAL=FALSE and the .rds present?)"
  # Fallback: also surface any raw '<name>: <n>' count lines captured under the block.
  echo

  echo "----- (b) R/88 pass/fail summary -----"
  grep -E "ALL [0-9]+ CHECKS PASSED|FAILED: [0-9]+/[0-9]+ checks failed" "$STAGE_88" \
    || echo "  (summary line NOT FOUND — inspect the full R/88 output above)"
  echo "  R/88 process exit code: ${rc88}   (0 = clean)"
  echo

  echo "----- (c) Mutual-exclusivity hard-stop (must be 0; must NOT halt R/111) -----"
  if [ "$MODE" = "full" ]; then
    grep -E "Mutual-exclusivity check:" "$STAGE_39" \
      || echo "  (line NOT FOUND in R/39 output — check R/111 ran within the pipeline)"
    echo "  R/39 exit code: ${rc39}   (non-zero may indicate the hard-stop fired)"
  else
    grep -E "Mutual-exclusivity check:" "$STAGE_111" \
      || echo "  (line NOT FOUND — check R/111 output above)"
    echo "  R/111 exit code: ${rc111}   (non-zero may indicate the hard-stop fired)"
  fi
  echo

  echo "----- Section 15w check lines (from R/88) -----"
  grep -E "Phase 130|Section 15w|DoI|DOI-QA" "$STAGE_88" | grep -E "PASS|FAIL|SKIP|check" | head -40 \
    || echo "  (no Section 15w lines matched — inspect full output)"
  echo

  echo "=============================================================="
  echo " Approve the gate ONLY IF: (a) counts present with RA dominant and"
  echo " NMO/Pemphigus rare, (b) 'ALL N CHECKS PASSED' (0 failed), and (c)"
  echo " 'Mutual-exclusivity check: 0 ...' with R/111 exiting 0."
  echo " Full log: ${LOG}"
  echo "=============================================================="
} 2>&1 | tee "$LOG"

# --- Clean up per-stage temp files (kept only for grep) ---
rm -f "$STAGE_111" "$STAGE_112" "$STAGE_39" "$STAGE_88"

# --- Print the full log text so it can be copied even if stdout was lost ---
echo
echo ">>>>>>>>>>>>>>>>>>>> BEGIN LOG TEXT (${LOG}) <<<<<<<<<<<<<<<<<<<<"
cat "$LOG"
echo ">>>>>>>>>>>>>>>>>>>>  END LOG TEXT  <<<<<<<<<<<<<<<<<<<<"
